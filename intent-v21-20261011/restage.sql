\set ON_ERROR_STOP on
SET TIME ZONE 'UTC';
BEGIN;
SET LOCAL statement_timeout='10min';
DO $$ BEGIN
 IF (SELECT status FROM analysis.rfpp_intent_v21_run WHERE id=1)<>'staged' THEN
  RAISE EXCEPTION 'Restaging permitted only before application'; END IF;
END $$;
-- CTAS permits parallel evaluation; UPDATE expressions are evaluated serially.
CREATE TEMP TABLE candidates AS
SELECT rfpp_id,analysis.rfpp_parse_intent_v21(reason) intent
FROM analysis.rfpp_request_pre_intent_v21;
CREATE UNIQUE INDEX ON candidates(rfpp_id);
UPDATE analysis.rfpp_intent_v21_stage s SET intent=b.intent
FROM candidates b WHERE b.rfpp_id=s.rfpp_id;
UPDATE analysis.rfpp_intent_v21_run SET parser_signature=(
 SELECT md5(string_agg(pg_get_functiondef(oid),E'\n' ORDER BY proname))
 FROM pg_proc WHERE pronamespace='analysis'::regnamespace AND proname IN
 ('rfpp_intent_normalize_v21','rfpp_intent_levels_v21','rfpp_intent_clause_v21','rfpp_intent_direction_v21','rfpp_parse_intent_v21'));
COMMIT;
