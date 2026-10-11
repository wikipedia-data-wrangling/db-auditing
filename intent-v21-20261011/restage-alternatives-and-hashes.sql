-- Narrow final guard: uncertain non-tier alternatives must not become a single
-- tier. Only evidence containing 'or' can enter the new branch.
-- Standardize hash serialization to UTC; compare complete rows before rehashing.
\set ON_ERROR_STOP on
SET TIME ZONE 'UTC';
BEGIN;
SET LOCAL statement_timeout='3min';
DO $$ BEGIN
 IF (SELECT status FROM analysis.rfpp_intent_v21_run WHERE id=1)<>'staged' THEN
  RAISE EXCEPTION 'Already applied'; END IF;
 IF EXISTS(SELECT 1 FROM analysis.rfpp_request r FULL JOIN analysis.rfpp_request_pre_intent_v21 b USING(rfpp_id)
 WHERE to_jsonb(r) IS DISTINCT FROM to_jsonb(b)) THEN
  RAISE EXCEPTION 'Live data changed; cannot rehash'; END IF;
END $$;
UPDATE analysis.rfpp_intent_v21_stage s SET intent=analysis.rfpp_parse_intent_v21(b.reason)
FROM analysis.rfpp_request_pre_intent_v21 b
WHERE b.rfpp_id=s.rfpp_id AND s.intent->>'evidence' ~ '\mor\M';
UPDATE analysis.rfpp_intent_v21_stage s SET before_hash=md5(to_jsonb(b)::text)
FROM analysis.rfpp_request_pre_intent_v21 b WHERE b.rfpp_id=s.rfpp_id;
UPDATE analysis.rfpp_intent_v21_run SET parser_signature=(
 SELECT md5(string_agg(pg_get_functiondef(oid),E'\n' ORDER BY proname))
 FROM pg_proc WHERE pronamespace='analysis'::regnamespace AND proname IN
 ('rfpp_intent_normalize_v21','rfpp_intent_levels_v21','rfpp_intent_clause_v21','rfpp_intent_direction_v21','rfpp_parse_intent_v21'));
COMMIT;
