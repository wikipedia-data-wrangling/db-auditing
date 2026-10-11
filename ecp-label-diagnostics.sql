-- RFPP requested-tier issue: READ-ONLY handoff diagnostics, 2026-10-10.
-- Review against the live schema before running. Not executed on PostgreSQL here.
-- Does NOT rerun sql/04_rfpp_request_extend.sql or change stored classifications.
-- Use the database agent's approved connection; no credentials embedded.
\set ON_ERROR_STOP on
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout = '2s';
SET LOCAL TIME ZONE 'UTC';
SET LOCAL standard_conforming_strings = on;

-- 1. Provenance and schema. If incompatible, stop and adapt remaining queries.
SELECT current_database(), current_user, version(),
       current_setting('transaction_read_only') AS transaction_read_only;
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'analysis' AND table_name = 'rfpp_request'
ORDER BY ordinal_position;

-- 2. Full live frame: deliberately NOT restricted to the old snapshot population.
SELECT page_namespace, outcome, count(*) AS n,
       min(request_timestamp) AS first_request,
       max(request_timestamp) AS last_request
FROM analysis.rfpp_request
GROUP BY 1,2 ORDER BY 1,2;

-- 3. Exact old export filter: live totals may differ from the historical snapshot.
SELECT count(*) AS snapshot_equivalent_rows,
       min(request_timestamp) AS first_request,
       max(request_timestamp) AS last_request
FROM analysis.rfpp_request
WHERE page_namespace = 0 AND outcome IN ('granted','denied');

-- 4. Deterministic label-branch reproducer only. No request table mutation.
-- Expected old erroneous output for the first three rows: token extended, tier ecp.
-- This intentionally reproduces OLD logic; it is not a proposed repair.
WITH examples(label, expected_target) AS (
  VALUES ('extended semi-protection', 'semi'),
         ('extended semi protection', 'semi'),
         ('extended temporary semi-protection', 'semi'),
         ('temporary extended confirmed protection', 'ecp'),
         ('extended-confirmed protection', 'ecp'),
         ('semi-protection', 'semi')
), tokens AS (
  SELECT label, expected_target,
         substring(label FROM
           '(semi|extended|\mecp\M|\mec\M|full|fully|pending|\mpc\M|flagged|template|creat|salt|\mmove)') AS k
  FROM examples
), mapped AS (
  SELECT *, CASE WHEN k IN ('semi','semi-protect','semiprotect') THEN 'semi'
                 WHEN k IN ('extended','ecp','ec') THEN 'ecp'
                 ELSE NULL END AS old_label_branch_tier
  FROM tokens
)
SELECT *, old_label_branch_tier IS DISTINCT FROM expected_target AS mismatch
FROM mapped ORDER BY label;

-- 5. Source-text fixtures. Verify identities if the live table has been rebuilt.
SELECT rfpp_id, request_timestamp, archive_page,
       request_label, requested_action, requested_level, requested_level_source,
       outcome, response_code, matched_log_id, matched_same_admin,
       granted_type, granted_level_raw, granted_level, reason
FROM analysis.rfpp_request
WHERE rfpp_id IN (737,4219,5302,12914,30062,91188,127462,144377,192925)
ORDER BY request_timestamp, rfpp_id;

-- 6. Snapshot-equivalent parsed ECP candidates. These are NOT validated ECP demand.
SELECT outcome, count(*) AS parsed_candidates,
       count(DISTINCT page_id_match) AS distinct_resolved_pages,
       count(*) FILTER (WHERE granted_type='edit' AND granted_level='ecp') AS ecp_log_matches,
       count(*) FILTER (WHERE granted_type='edit' AND granted_level='semi') AS semi_log_matches,
       count(*) FILTER (WHERE lower(request_label) LIKE '%extended%'
                          AND lower(request_label) LIKE '%semi%') AS dual_word_labels
FROM analysis.rfpp_request
WHERE page_namespace=0 AND outcome IN ('granted','denied')
  AND requested_action='increase' AND requested_level='ecp'
  AND request_timestamp >= TIMESTAMPTZ '2016-01-01 00:00:00+00'
  AND request_timestamp <  TIMESTAMPTZ '2026-01-01 00:00:00+00'
GROUP BY outcome ORDER BY outcome;

-- 7. Full-population extended/semi queue, regardless of existing parsed tier/action.
-- This is a candidate detector, NOT a correction rule or a count of confirmed errors.
SELECT request_label, requested_action, requested_level, requested_level_source,
       outcome, count(*) AS n
FROM analysis.rfpp_request
WHERE lower(request_label) LIKE '%extended%' AND lower(request_label) LIKE '%semi%'
GROUP BY 1,2,3,4,5 ORDER BY n DESC, request_label;

-- 8. Snapshot-equivalent missing-tier time profile, all parsed increase requests.
SELECT extract(year FROM request_timestamp)::integer AS year,
       count(*) AS n, count(*) FILTER (WHERE requested_level IS NULL) AS null_tier
FROM analysis.rfpp_request
WHERE page_namespace=0 AND outcome IN ('granted','denied')
  AND requested_action='increase'
  AND request_timestamp >= TIMESTAMPTZ '2013-01-01 00:00:00+00'
  AND request_timestamp <  TIMESTAMPTZ '2026-01-01 00:00:00+00'
GROUP BY 1 ORDER BY 1;

-- 9. Full-population direction/alternative/amendment candidate queue, bounded output.
-- Inspect body and historical revisions before assigning requested-time intent.
SELECT rfpp_id, request_timestamp, archive_page, request_label,
       requested_action, requested_level, requested_level_source, outcome,
       left(reason,1000) AS reason_excerpt
FROM analysis.rfpp_request
WHERE lower(request_label) ~ '(from.*to|<s>|<del>|\mor\M)'
  AND (lower(request_label) LIKE '%semi%' OR lower(request_label) LIKE '%extended%')
ORDER BY request_timestamp, rfpp_id LIMIT 200;

-- 10. Body/missing-tier candidate queue, including possible false negatives.
-- 'extended.confirmed' mirrors one OLD detection pattern, not semantic validation.
SELECT rfpp_id, request_timestamp, request_label, requested_action,
       requested_level, requested_level_source, outcome, left(reason,1000) AS reason_excerpt
FROM analysis.rfpp_request
WHERE requested_level IS DISTINCT FROM 'ecp'
  AND reason ~* 'extended.confirmed'
ORDER BY request_timestamp, rfpp_id LIMIT 200;

-- 11. Stored raw-vs-mapped matched levels: do NOT force agreement with request tier.
SELECT requested_level, granted_type, granted_level_raw, granted_level,
       outcome, count(*) AS n
FROM analysis.rfpp_request
WHERE requested_level='ecp' OR granted_level='ecp'
GROUP BY 1,2,3,4,5 ORDER BY 1,2,3,4,5;

ROLLBACK;
