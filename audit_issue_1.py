"""Reproduce issue #1 against service=wiki without changing database records.

Run from this repository with ../official-dump/.venv/bin/python audit_issue_1.py.
The JSON log includes exact queries, source hashes, filters, and result rows.
"""
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path

import psycopg

ROOT = Path(__file__).resolve().parent
QUERIES = {
    "connection": "SELECT current_database() AS database,current_setting('port') AS port,current_setting('server_version') AS server_version,current_setting('transaction_read_only') AS transaction_read_only,current_timestamp AS audit_timestamp",
    "population": "SELECT page_namespace,outcome,count(*) AS cases,min(request_timestamp) AS first_request,max(request_timestamp) AS last_request FROM analysis.rfpp_request GROUP BY 1,2 ORDER BY 1,2",
    "snapshot_equivalent": "SELECT count(*) AS cases,min(request_timestamp) AS first_request,max(request_timestamp) AS last_request FROM analysis.rfpp_request WHERE page_namespace=0 AND outcome IN ('granted','denied')",
    "ecp_candidates_2016_2025": "SELECT outcome,count(*) AS cases,count(DISTINCT page_id_match) AS pages,count(*) FILTER(WHERE granted_type='edit' AND granted_level='ecp') AS ecp_log_matches,count(*) FILTER(WHERE granted_type='edit' AND granted_level='semi') AS semi_log_matches,count(*) FILTER(WHERE request_label LIKE '%extended%' AND request_label LIKE '%semi%') AS dual_word_labels FROM analysis.rfpp_request WHERE page_namespace=0 AND outcome IN ('granted','denied') AND requested_action='increase' AND requested_level='ecp' AND request_timestamp >= '2016-01-01 00:00:00+00' AND request_timestamp < '2026-01-01 00:00:00+00' GROUP BY 1 ORDER BY 1",
    "extended_semi_full_population": "SELECT request_label,requested_action,requested_level,requested_level_source,outcome,count(*) AS cases FROM analysis.rfpp_request WHERE request_label LIKE '%extended%' AND request_label LIKE '%semi%' GROUP BY 1,2,3,4,5 ORDER BY 1,2,3,4,5",
    "bare_extended_ecp_labels": r"SELECT request_label,count(*) AS cases FROM analysis.rfpp_request WHERE requested_level='ecp' AND requested_level_source='label' AND request_label !~ '(extended[ -]+confirmed|\mecp\M|\mec\M)' GROUP BY 1 ORDER BY 2 DESC,1",
    "explicit_direction_candidates": r"SELECT rfpp_id,request_timestamp,archive_page,request_label,requested_action,requested_level,outcome FROM analysis.rfpp_request WHERE request_label ~ '\mfrom\M.*\mto\M' AND request_label ~ '(semi|extended)' ORDER BY request_timestamp,rfpp_id",
    "fixtures": "SELECT rfpp_id,request_timestamp,archive_page,request_label,requested_action,requested_level,requested_level_source,outcome,response_code,matched_log_id,granted_type,granted_level_raw,granted_level,md5(reason) AS reason_md5 FROM analysis.rfpp_request WHERE rfpp_id IN (737,4219,5302,12914,30062,91188,127462,144377,192925) ORDER BY request_timestamp,rfpp_id",
    "missing_tiers_by_year": "SELECT extract(year FROM request_timestamp)::int AS request_year,count(*) AS cases,count(*) FILTER(WHERE requested_level IS NULL) AS missing_tier FROM analysis.rfpp_request WHERE page_namespace=0 AND outcome IN ('granted','denied') AND requested_action='increase' AND request_timestamp >= '2013-01-01 00:00:00+00' AND request_timestamp < '2026-01-01 00:00:00+00' GROUP BY 1 ORDER BY 1",
    "parser_dependency_columns": "SELECT table_name,column_name FROM information_schema.columns WHERE table_schema='analysis' AND column_name IN ('requested_action','requested_level','board','elig_level_code','elig_level_source','expiry_is_pseudo','rfpp_id') ORDER BY 1,2",
    "reproducer": r"WITH examples(label,expected_target) AS (VALUES ('extended semi-protection','semi'),('extended semi protection','semi'),('extended temporary semi-protection','semi'),('temporary extended confirmed protection','ecp'),('extended-confirmed protection','ecp'),('semi-protection','semi')), tokens AS (SELECT *,substring(label FROM '(semi|extended|\mecp\M|\mec\M|full|fully|pending|\mpc\M|flagged|template|creat|salt|\mmove)') AS token FROM examples) SELECT label,expected_target,token,CASE WHEN token='semi' THEN 'semi' WHEN token IN ('extended','ecp','ec') THEN 'ecp' END AS old_target FROM tokens ORDER BY label",
}


def normalize(value):
    # SQL_ASCII text is returned as bytes. Preserve undecodable source bytes
    # as escaped surrogates in JSON instead of changing connection encoding.
    if isinstance(value, bytes):
        return value.decode("utf-8", "surrogateescape")
    if isinstance(value, dict):
        return {str(normalize(k)): normalize(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [normalize(v) for v in value]
    if isinstance(value, datetime):
        return value.isoformat()
    return value


def main():
    report = {"recorded_at": datetime.now(timezone.utc).isoformat(),
              "mode": "read-only repeatable read", "source_hashes": {}, "queries": {}}
    for name in ("audit_issue_1.py", "ecp-label-diagnostics.sql", "ecp-label-issue-report.org",
                 "../20261001/wpp-analysis/sql/04_rfpp_request_extend.sql",
                 "../20261001/wpp-analysis/data/interim/rfpp_request.parquet"):
        report["source_hashes"][name] = hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
    with psycopg.connect("service=wiki", autocommit=True,
                         application_name="db-auditing-issue-1") as conn:
        conn.execute("BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY")
        conn.execute("SET LOCAL statement_timeout='60s'")
        conn.execute("SET LOCAL lock_timeout='2s'")
        conn.execute("SET LOCAL TIME ZONE 'UTC'")
        for name, query in QUERIES.items():
            cursor = conn.execute(query)
            columns = [column.name for column in cursor.description]
            rows = normalize([dict(zip(columns, row)) for row in cursor.fetchall()])
            report["queries"][name] = {"sql": query, "rows": rows}
            if name == "connection":
                if rows[0]["database"] != "wiki20260401" or rows[0]["port"] != "5434":
                    raise RuntimeError("Wrong audit target")
                if rows[0]["transaction_read_only"] != "on":
                    raise RuntimeError("Audit transaction is not read-only")
        conn.execute("ROLLBACK")
    # This bounded review describes the destinations written in the 18 labels.
    # It is not a new intent parser or a request-time chronology reconstruction.
    destination_review = []
    for row in report["queries"]["explicit_direction_candidates"]["rows"]:
        destination = row["request_label"].split(" to ", 1)[1]
        target = ("ecp" if re.search(r"extended[ -]+confirmed", destination) else
                  "semi" if "semi" in destination else
                  "full" if "full" in destination else
                  "pc" if "pending changes" in destination else None)
        destination_review.append({"rfpp_id": row["rfpp_id"],
                                   "destination_text": destination,
                                   "label_destination": target,
                                   "stored_tier": row["requested_level"],
                                   "disagrees": target is not None and target != row["requested_level"]})
    report["label_destination_review"] = destination_review
    reproducer = report["queries"]["reproducer"]["rows"]
    mismatches = [r["label"] for r in reproducer if r["old_target"] != r["expected_target"]]
    expected = {"extended semi protection", "extended semi-protection",
                "extended temporary semi-protection"}
    if set(mismatches) != expected:
        raise RuntimeError("The deterministic old-parser reproducer changed")
    fixtures = report["queries"]["fixtures"]["rows"]
    if {r["rfpp_id"] for r in fixtures} != {737, 4219, 5302, 12914, 30062, 91188, 127462, 144377, 192925}:
        raise RuntimeError("Historical fixtures are missing; verify identities")
    report["checks"] = {"old_parser_mismatches": mismatches,
                        "historical_fixture_count": len(fixtures),
                        "database_changes": "none; transaction rolled back"}
    report["completed_at"] = datetime.now(timezone.utc).isoformat()
    report["state"] = "complete"
    destination = ROOT / "logs" / "issue-1-live-audit-20261010.json"
    destination.parent.mkdir(exist_ok=True)
    destination.write_text(json.dumps(report, indent=2, ensure_ascii=True) + "\n")
    print(f"Wrote {destination}")
    print("Live rows:", sum(r["cases"] for r in report["queries"]["population"]["rows"]))
    for name in ("snapshot_equivalent", "ecp_candidates_2016_2025", "explicit_direction_candidates"):
        print(name, json.dumps(report["queries"][name]["rows"]))
    for name in ("extended_semi_full_population", "bare_extended_ecp_labels"):
        print(name, sum(r["cases"] for r in report["queries"][name]["rows"]))


if __name__ == "__main__":
    main()
