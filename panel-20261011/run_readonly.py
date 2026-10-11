"""Run a named JSON mapping of bounded SQL queries in read-only transactions.
Usage: official-dump/.venv/bin/python .../run_readonly.py queries.json output.json
Individual failures/timeouts are evidence; they do not imply an empty result.
"""
import datetime, decimal, json, sys, time
from pathlib import Path
import psycopg

def clean(v):
    if isinstance(v, bytes): return v.decode('utf8','backslashreplace')
    if isinstance(v, (list,tuple)): return [clean(x) for x in v]
    if isinstance(v, dict): return {str(clean(k)):clean(x) for k,x in v.items()}
    if isinstance(v, (datetime.date,datetime.datetime,datetime.timedelta,decimal.Decimal)): return str(v)
    return v

queries=json.loads(Path(sys.argv[1]).read_text())
out={'started_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'connection':'service=wiki',
     'scope':'Bounded read-only queries, each with its own snapshot; not a single database-wide snapshot.', 'results':{}}
with psycopg.connect('service=wiki',autocommit=True,application_name='panel-audit-20261011') as conn:
    for name,sql in queries.items():
        result={'sql':sql}; start=time.monotonic()
        try:
            conn.execute('BEGIN READ ONLY')
            conn.execute("SET LOCAL statement_timeout='30s'")
            conn.execute("SET LOCAL lock_timeout='2s'")
            conn.execute("SET LOCAL TIME ZONE 'UTC'")
            cur=conn.execute(sql)
            result['rows']=[dict(zip([c.name for c in cur.description],clean(row))) for row in cur.fetchall()]
            result['status']='ok'
        except Exception as e:
            result.update(status='error',error=str(e))
        finally:
            conn.execute('ROLLBACK')
        result['elapsed_seconds']=round(time.monotonic()-start,3)
        out['results'][name]=result
        Path(sys.argv[2]).write_text(json.dumps(out,indent=2,ensure_ascii=True)+'\n')
        print(name,result['status'],len(result.get('rows',[])),result['elapsed_seconds'],flush=True)
