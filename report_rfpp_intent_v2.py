"""Export versioned repair evidence without modifying database records."""
import csv
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
import psycopg

ROOT = Path(__file__).resolve().parent
LOG = ROOT / 'logs'

def clean(value):
    if isinstance(value, bytes):
        return value.decode('utf8', 'surrogateescape')
    if isinstance(value, dict):
        return {clean(k): clean(v) for k, v in value.items()}
    if isinstance(value, (tuple, list)):
        return [clean(v) for v in value]
    if isinstance(value, datetime):
        return value.isoformat()
    return value

queries = {
    'run': 'SELECT * FROM analysis.rfpp_intent_v2_run',
    'population': '''SELECT count(*) AS rows,count(DISTINCT rfpp_id) AS unique_ids,
       count(*) FILTER(WHERE old_action IS DISTINCT FROM intent->>'action') AS action_changes,
       count(*) FILTER(WHERE old_level IS DISTINCT FROM intent->>'tier') AS tier_changes
       FROM analysis.rfpp_intent_v2_stage''',
    'action_confusion': '''SELECT old_action,intent->>'action' AS new_action,count(*) AS n
       FROM analysis.rfpp_intent_v2_stage GROUP BY 1,2 ORDER BY 1,2''',
    'tier_confusion': '''SELECT old_level,intent->>'tier' AS new_level,count(*) AS n
       FROM analysis.rfpp_intent_v2_stage GROUP BY 1,2 ORDER BY 1,2''',
    'status': "SELECT intent->>'status' AS status,count(*) AS n FROM analysis.rfpp_intent_v2_stage GROUP BY 1 ORDER BY 2 DESC",
    'strata': '''SELECT extract(year FROM b.request_timestamp) AS year,b.outcome,
       s.old_source,s.intent->>'source' AS new_source,s.intent->>'status' AS status,
       count(*) AS n,count(*) FILTER(WHERE s.old_action IS DISTINCT FROM s.intent->>'action') AS action_changes,
       count(*) FILTER(WHERE s.old_level IS DISTINCT FROM s.intent->>'tier') AS tier_changes
       FROM analysis.rfpp_intent_v2_stage s JOIN analysis.rfpp_request_pre_intent_v2 b USING(rfpp_id)
       GROUP BY 1,2,3,4,5 ORDER BY 1,2,3,4,5''',
    'fixtures': '''SELECT s.rfpp_id,s.old_action,s.old_level,s.intent,b.outcome
       FROM analysis.rfpp_intent_v2_stage s JOIN analysis.rfpp_request_pre_intent_v2 b USING(rfpp_id)
       WHERE rfpp_id IN (737,4219,5302,12914,30062,127462,144377,154614,91188,192925) ORDER BY rfpp_id''',
    'review_sample': '''WITH samples AS (
       SELECT s.rfpp_id,s.old_action,s.old_level,s.intent,b.reason,
       row_number() OVER (PARTITION BY s.intent->>'status',s.intent->>'source',
       (s.old_level IS DISTINCT FROM s.intent->>'tier'),s.intent->>'tier'
       ORDER BY md5(s.rfpp_id::text)) AS sample_rank
       FROM analysis.rfpp_intent_v2_stage s JOIN analysis.rfpp_request_pre_intent_v2 b USING(rfpp_id))
       SELECT * FROM samples WHERE sample_rank<=3 ORDER BY intent->>'status',rfpp_id''',
}
with psycopg.connect('service=wiki', application_name='rfpp-intent-v2-report') as conn:
    conn.execute('SET TRANSACTION READ ONLY')
    conn.execute("SET TIME ZONE 'UTC'")
    report = {'recorded_at': datetime.now(timezone.utc).isoformat(), 'queries': {}}
    for name, query in queries.items():
        cur = conn.execute(query)
        columns = [c.name for c in cur.description]
        rows = [dict(zip(columns, clean(row))) for row in cur.fetchall()]
        report['queries'][name] = {'sql': query, 'rows': rows}
    if conn.execute("SELECT to_regclass('analysis.rfpp_intent_v2_changes')").fetchone()[0]:
        for name, query in {
            'invalidations': 'SELECT * FROM analysis.rfpp_intent_v2_invalidations ORDER BY object_name',
            'change_summary': '''SELECT count(*) AS changed_records,
                count(*) FILTER(WHERE old_log_id IS DISTINCT FROM new_log_id) AS log_changes,
                count(*) FILTER(WHERE old_treated_by_log IS DISTINCT FROM new_treated_by_log) AS treatment_changes
                FROM analysis.rfpp_intent_v2_changes''',
        }.items():
            cur = conn.execute(query)
            report['queries'][name] = {'sql': query, 'rows': [dict(zip([c.name for c in cur.description], clean(row))) for row in cur.fetchall()]}
        with (LOG/'issue-1-changed-records-20261010.csv').open('wb') as output:
            with conn.cursor().copy('COPY (SELECT * FROM analysis.rfpp_intent_v2_changes ORDER BY rfpp_id) TO STDOUT WITH CSV HEADER') as copy:
                for data in copy: output.write(data)
    for name in ['action_confusion','tier_confusion']:
        rows = report['queries'][name]['rows']
        with (LOG/f'issue-1-{name}-20261010.csv').open('w',newline='') as output:
            writer=csv.DictWriter(output,fieldnames=list(rows[0]))
            writer.writeheader(); writer.writerows(rows)
    report['sha256'] = {str(p.relative_to(ROOT.parent)): hashlib.sha256(p.read_bytes()).hexdigest()
                       for p in [*ROOT.glob('*intent_v2*.*'),
                                 ROOT/'check_rfpp_intent_encoding.py', ROOT/'refresh_rfpp_intent_cache.py',
                                 ROOT/'restage_rfpp_after_encoding_fix.sql',
                                 *ROOT.parent.glob('20261001/wpp-analysis/sql/04*.sql')]}
    stage_status=report['queries']['run']['rows'][0]['status']
    path=LOG/f'issue-1-repair-{stage_status}-20261010.json'
    path.write_text(json.dumps(report,ensure_ascii=True,indent=2,default=str)+'\n')
    print(path)
    print(json.dumps(report['queries']['population']['rows']))
