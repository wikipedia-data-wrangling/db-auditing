\set ON_ERROR_STOP on
SET TIME ZONE 'UTC';
BEGIN READ ONLY;
SET LOCAL statement_timeout='2min';
SELECT current_database(),current_setting('port');
SELECT * FROM analysis.rfpp_intent_v21_run;
DO $$ BEGIN
 IF (SELECT status FROM analysis.rfpp_intent_v21_run WHERE id=1) IS DISTINCT FROM 'applied' THEN
  RAISE EXCEPTION 'Not applied'; END IF;
 IF EXISTS(SELECT 1 FROM analysis.rfpp_request r FULL JOIN analysis.rfpp_intent_v21_stage s USING(rfpp_id)
 WHERE r.rfpp_id IS NULL OR s.rfpp_id IS NULL OR requested_intent IS DISTINCT FROM s.intent
 OR requested_action IS DISTINCT FROM s.intent->>'action' OR requested_level IS DISTINCT FROM s.intent->>'tier'
 OR md5(to_jsonb(r)::text) IS DISTINCT FROM s.after_hash) THEN
  RAISE EXCEPTION 'Live/stage mismatch'; END IF;
 IF analysis.rfpp_parse_intent_v2('test')->>'version' <> 'rfpp-intent-v2.1.0' THEN
  RAISE EXCEPTION 'Active entrypoint has wrong version'; END IF;
END $$;
SELECT count(*) population,count(DISTINCT rfpp_id) unique_ids,
 count(*) FILTER(WHERE requested_intent->>'version'='rfpp-intent-v2.1.0') versioned
FROM analysis.rfpp_request;
SELECT count(*) changed_records,
 count(*) FILTER(WHERE old_action IS DISTINCT FROM new_action) action_changes,
 count(*) FILTER(WHERE old_level IS DISTINCT FROM new_level) tier_changes,
 count(*) FILTER(WHERE old_log_id IS DISTINCT FROM new_log_id) log_changes
FROM analysis.rfpp_intent_v21_changes;
SELECT requested_intent->>'status' status,count(*) n FROM analysis.rfpp_request GROUP BY 1 ORDER BY 2 DESC;
SELECT count(*) invalidated_products FROM analysis.rfpp_intent_v21_invalidations;
ROLLBACK;
