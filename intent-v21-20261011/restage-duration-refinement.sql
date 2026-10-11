-- The final refinement removes only less/more from the open_target_alternative
-- trigger, to avoid confusing duration alternatives with tier alternatives.
-- Therefore only rows previously hitting that rule require re-evaluation.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout='30s';
DO $$ BEGIN
 IF (SELECT status FROM analysis.rfpp_intent_v21_run WHERE id=1)<>'staged' THEN
  RAISE EXCEPTION 'Already applied'; END IF;
END $$;
UPDATE analysis.rfpp_intent_v21_stage s SET intent=analysis.rfpp_parse_intent_v21(b.reason)
FROM analysis.rfpp_request_pre_intent_v21 b
WHERE b.rfpp_id=s.rfpp_id AND s.intent->>'rule'='open_target_alternative';
UPDATE analysis.rfpp_intent_v21_run SET parser_signature=(
 SELECT md5(string_agg(pg_get_functiondef(oid),E'\n' ORDER BY proname))
 FROM pg_proc WHERE pronamespace='analysis'::regnamespace AND proname IN
 ('rfpp_intent_normalize_v21','rfpp_intent_levels_v21','rfpp_intent_clause_v21','rfpp_intent_direction_v21','rfpp_parse_intent_v21'));
COMMIT;
