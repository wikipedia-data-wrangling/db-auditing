\set ON_ERROR_STOP on
BEGIN READ ONLY;
SET LOCAL TIME ZONE 'UTC';
SET LOCAL statement_timeout='5min';
SELECT current_database(),current_setting('port') AS port,version();
SELECT * FROM analysis.rfpp_intent_v2_run;
SELECT count(*) AS rows,count(DISTINCT rfpp_id) AS unique_ids,
 count(*) FILTER(WHERE requested_intent->>'version'='rfpp-intent-v2.0.0') AS versioned
FROM analysis.rfpp_request;
DO $$ BEGIN
 IF (SELECT status FROM analysis.rfpp_intent_v2_run WHERE id=1) IS DISTINCT FROM 'applied' THEN
  RAISE EXCEPTION 'Repair not applied'; END IF;
 IF EXISTS(SELECT 1 FROM analysis.rfpp_request r FULL JOIN analysis.rfpp_intent_v2_stage s USING(rfpp_id)
 WHERE r.rfpp_id IS NULL OR s.rfpp_id IS NULL OR r.requested_intent IS DISTINCT FROM s.intent
 OR r.requested_action IS DISTINCT FROM s.intent->>'action'
 OR r.requested_level IS DISTINCT FROM s.intent->>'tier') THEN
  RAISE EXCEPTION 'Live repair differs from staged population'; END IF;
END $$;
SELECT rfpp_id,requested_action,requested_level,requested_intent->>'status' AS status,
 requested_intent->>'origin' AS origin,requested_intent->'targets' AS targets,
 outcome,granted_level
FROM analysis.rfpp_request
WHERE rfpp_id IN(737,4219,5302,12914,30062,127462,144377,154614,91188,192925)
ORDER BY rfpp_id;
SELECT outcome,count(*) AS candidates FROM analysis.rfpp_request
WHERE page_namespace=0 AND outcome IN('granted','denied')
AND requested_action='increase' AND requested_level='ecp'
AND request_timestamp>='2016-01-01' AND request_timestamp<'2026-01-01'
GROUP BY outcome ORDER BY outcome;
SELECT object_name,direct_changed_rows,status FROM analysis.rfpp_intent_v2_invalidations ORDER BY object_name;
ROLLBACK;
