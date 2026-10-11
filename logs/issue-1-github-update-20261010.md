## Live audit execution log — 2026-10-10

The original diagnostic SQL has now been executed successfully on **wiki20260401, PostgreSQL 18.4, port 5434**. The read-only repeatable-read transaction used UTC, bounded statement/lock timeouts, and ended with `ROLLBACK`. Audit timestamp: `2026-10-10T16:51:36.292095+00:00`.

**The reported defects remain reproducible in the live table. No parser or data correction has been deployed; this issue remains open for remediation.**

### Findings

- Full live RFPP population: **217,554 rows**. The historical mainspace/granted-or-denied filter still returns **178,110 rows**, spanning 2012-10-29 06:54 UTC to 2026-09-30 07:11 UTC.
- SQL04 and the cached Parquet export hashes match the original report. All nine fixture IDs retain the reported identities/labels; the five duration/tier failures and two ECP-to-semi direction failures remain present.
- The deterministic PostgreSQL reproducer produces the three expected old-parser failures; its three control labels return their expected tiers.
- The mainspace increase/ECP candidate population for 2016–2025 reproduces **3,535 granted / 2,595 denied**, including the **57 / 12** dual-word label queue. Applied-tier subsets overlap and are not error counts.
- Across all namespaces/outcomes, **115** labels contain both extended and semi. A separate detector identifies **736** label-derived ECP rows without explicit extended-confirmed/ECP/EC wording. These are review queues, not confirmed error totals.
- An expanded queue finds **18 explicit from/to labels**; **17** store a tier different from their stated destination. This extends the defect beyond ECP-to-semi downgrades. For example, **154614** requests an upgrade from semi to ECP but stores the origin tier `semi`. The complete ID list and bounded review method are in the attached log.
- The 2025 missing-tier profile also reproduces: **4,399 / 13,669** mainspace granted/denied increase requests have NULL tier. Missingness remains separate from misclassification.

### Design and downstream implications

A repair must distinguish duration from credential tier and origin from destination, keep alternatives/amendment chronology explicit, and separate requested intent from response and applied action. Neither regex alternation reordering nor a blanket “semi occurs, therefore semi” rule suffices.

Source and live schema inspection identify affected IV strata/subgroups, requested-tier sample/treated copies, denied/control eligibility, pseudo-expiry duration groups, and cached exports. The dependency list establishes where to inspect; it does not establish that every historical fitted estimate is affected. No effect fits were rerun.

### Recorded work

`db-auditing/README.md` now defines the workspace as an assessment of the April 2026 dump database and its collection, schema, linkage, classification, and analytical design choices. The local audit artifacts are:

- `issue-1-audit-log.org`: narrative execution log and remaining remediation.
- `audit_issue_1.py`: reproducible read-only runner with fixture assertions.
- `logs/issue-1-live-audit-20261010.json`: exact queries, results, hashes, timestamps, and bounded destination review.
- `logs/issue-1-live-diagnostics-20261010.log`: complete successful diagnostic output.

These local files have not been pushed. The complete narrative log and runner are included below to make this update independently reviewable. The structured JSON SHA256 is `8a720c30f4738fc372503a8f348a801f95571ff68771340b5c77eded013c6ba6`.

Remaining work: implement and validate a versioned parser, produce reversible old/new records and confusion tables, perform a scoped migration, and refresh affected downstream dependencies. Archived strike-through timing and ambiguous intent still require additional evidence.

<details>
<summary>Complete audit log: issue-1-audit-log.org</summary>

```org
#+title: Issue 1 — live PostgreSQL audit log
#+date: 2026-10-10
#+options: toc:2

* Scope and disposition

Issue: [[https://github.com/wikipedia-data-wrangling/db-auditing/issues/1][RFPP requested-protection classification]].

This entry records a completed investigation of the live database and the
classification design. The original handoff has now been reproduced on
PostgreSQL. The classification defects remain present: this investigation has
not deployed a replacement parser, changed database rows, refreshed analysis
caches, or rerun effect estimates. Keep the issue open for remediation.

The README now states the workspace's purpose: assess the April 2026 dump
database and the choices made in collection, ingestion, schema, linkage,
classification, and downstream analysis.

* Execution and reproducibility

Target verified: =wiki20260401=, PostgreSQL =18.4=, port =5434=, role =simone=,
connection =service=wiki=. Both diagnostic executions used read-only,
repeatable-read transactions, UTC, a 60-second per-statement timeout, a
2-second lock timeout, and =ROLLBACK=.

Executed from the =db-auditing= repository:

#+begin_src sh
psql -X service=wiki -v ON_ERROR_STOP=1 -f ecp-label-diagnostics.sql \
  > logs/issue-1-live-diagnostics-20261010.log 2>&1
../official-dump/.venv/bin/python audit_issue_1.py \
  > logs/issue-1-audit-run-20261010.log 2>&1
#+end_src

Artifacts:

- [[file:logs/issue-1-live-diagnostics-20261010.log][Full output of the original diagnostic script]], including source-text fixtures.
- [[file:logs/issue-1-live-audit-20261010.json][Structured live audit]]: exact queries, result rows, UTC execution timestamps,
  source hashes, fixture text hashes, bounded destination-label review, and checks.
- [[file:logs/issue-1-audit-run-20261010.log][Audit runner output]].
- [[file:audit_issue_1.py][Reproducible audit runner]]; requires the existing =psycopg= environment.

The original handoff files are retained unchanged. Their statements that live
diagnostics had not yet been executed describe the earlier handoff, superseded
by this log. Original SQL04 and the Parquet export hashes match the report:

| Artifact | SHA256 |
|----------+--------|
| =sql/04_rfpp_request_extend.sql= | =b6f4a1d99b4ef514bfed2917a1948e92d5bc43b69a6b9c9117803a57c3aeb914= |
| =data/interim/rfpp_request.parquet= | =c516207250f292445087d78d5926395a7385290725219cf3c943fc3d4aa41e35= |
| =ecp-label-diagnostics.sql= | =2beb0ad0abd3d095f1eed3709cbdd13e22ca0db48b6a9416e6b849da106a0ca0= |
| =ecp-label-issue-report.org= | =2903339a8032d3d14d3ad2ced56926c6888a299a382fe041e8cf5bbd2fec13c6= |

An initial supplemental in-memory query attempt failed on an unaliased =year=
identifier. It was read-only and produced no persisted results. The saved
runner uses =AS request_year= and was subsequently executed successfully.

* Live frame and snapshot-equivalent reproduction

Full live =analysis.rfpp_request=: *217,554 rows*, covering all loaded namespaces
and outcome categories. The matching historical export filter is
=page_namespace=0 AND outcome IN ('granted','denied')=: *178,110 rows*, from
=2012-10-29 06:54 UTC= through =2026-09-30 07:11 UTC=.

Matching totals and nine fixture identities do not establish row-for-row
equivalence of every export field; the live audit and export remain distinct
evidence sources with their recorded provenance.

For mainspace granted/denied rows with =requested_action='increase'=,
=requested_level='ecp'=, and
=2016-01-01 00:00 UTC <= request_timestamp < 2026-01-01 00:00 UTC=:

| Measurement | Granted | Denied |
|-------------+---------+--------|
| Parsed ECP candidates | 3535 | 2595 |
| Distinct resolved pages | 3268 | 2287 |
| Matched edit action at ECP | 809 | 94 |
| Matched edit action at semi | 2324 | 120 |
| Labels containing both extended and semi | 57 | 12 |

These reproduce the handoff counts. The matched-action and dual-word subsets
overlap; they are not additive. No requested/applied mismatch is automatically
counted as a classification error.

The full-population extended/semi label queue has *115 rows*. A separate queue
has *736 label-derived ECP classifications without explicit extended-confirmed,
ECP, or EC wording under the recorded detector*. These populations differ from
the 69 filtered dual-word candidates. Neither queue is a validated error count:
they include abbreviations, misspellings, alternatives, and uncertain language.

For mainspace granted/denied increase requests in 2025, *4,399 of 13,669* have
a NULL requested tier. Missingness is a separate measurement problem.

* Confirmed reproduction and additional findings

The deterministic PostgreSQL reproducer returns =ecp= rather than =semi= for
each of =extended semi-protection=, =extended semi protection=, and
=extended temporary semi-protection=. Three control labels return their
expected tiers. Assertions in the audit runner verify this exact mismatch set
and the presence of all nine historical fixtures.

The live rows preserve the reported five duration/tier examples:
=737, 4219, 5302, 12914, 30062=. The two explicit ECP-to-semi downgrades,
=127462= and =144377=, still store =increase/ecp=.

The alternative-target row =91188= and strike-through row =192925= also match
the report. The latter's original request-time intent cannot be determined
from final archived wording alone; this audit did not fetch historical edits.

The expanded direction queue contains *18* labels with an explicit =from ... to ...=
construction mentioning semi or extended. In a bounded review of their stated
destinations, *17* store a tier different from that destination:

| rfpp_id | Stored tier | Destination written in label |
|---------+-------------+------------------------------|
| 18057 | full | semi |
| 21322 | full | semi |
| 30905 | full | semi |
| 44440 | semi | full |
| 59459 | pc | semi |
| 66970 | pc | semi |
| 87454 | ecp | semi |
| 88812 | pc | semi |
| 89831 | pc | semi |
| 95610 | pc | ecp |
| 105148 | pc | semi |
| 117901 | ecp | full |
| 121254 | semi | pc |
| 121914 | pc | semi |
| 127462 | ecp | semi |
| 144377 | ecp | semi |
| 154614 | semi | ecp |

Row =170749= already stores semi, matching its stated destination. This review
is deliberately limited to explicit label destinations; it is not a replacement
parser, an estimate of population-wide error, or a reconstruction of historical
page state or request amendments. In particular, =154614= demonstrates the
opposite-direction tier failure: a semi-to-ECP request stores the origin semi.

* Design choices and dependency impact

SQL04 uses a first-keyword tier rule and defaults action to increase, partly
consulting response codes. The former confuses duration with tier and origin
with destination; the latter can introduce post-decision information into
requested intent. Neither regex alternation reordering nor a blanket
"semi appears, therefore semi" rule is an adequate repair.

The source inspection confirms requested tier enters IV strata/subgroups
(=scripts/30_leniency_iv.jl=), denied/control eligibility, and pseudo-expiry
duration groups (=sql/20_sample_page.sql:379-409=). Live schema inspection also
finds requested-tier copies in treated/sample tables. A repaired source table
would leave these products and cached exports stale until explicitly refreshed.

The dependency inventory in the JSON records existing columns, not proof that
every historical estimate is affected. Whether each fitted model included
changed records remains to be traced. Protection-event levels, matched applied
levels, and request outcomes must remain independent of requested intent.

* Remediation still required

1. Implement a versioned intent parser separating duration, origin, destination,
   alternatives, negation, source provenance, and chronology uncertainty.
2. Preserve raw input and old/new values by stable source identity. Apply the
   same requested-intent procedure to all outcome categories.
3. Validate on the full live population and the historical comparison filter,
   including false negatives, body-derived cases, missing tiers, and unchanged
   records. Expand fixtures to the opposite-direction cases above.
4. Produce staged confusion tables and changed IDs before a scoped migration.
   Do not rerun all of SQL04 as a label-only patch; it rebuilds unrelated fields.
5. Trace and refresh affected derived tables and caches in dependency order;
   document which analyses require re-estimation. Preserve prior artifacts.

Disposition: *audit reproduced and logged; parser repair remains open*.
```

</details>

<details>
<summary>Reproducible read-only audit runner: audit_issue_1.py</summary>

```python
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
```

</details>

