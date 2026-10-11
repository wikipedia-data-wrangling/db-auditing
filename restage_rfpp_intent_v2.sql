-- Re-evaluate the preserved original population after a parser refinement.
-- Only permitted before application; never replaces the original snapshot.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
 IF (SELECT status FROM analysis.rfpp_intent_v2_run WHERE id=1) IS DISTINCT FROM 'staged' THEN
  RAISE EXCEPTION 'Cannot restage an applied repair'; END IF;
END $$;
UPDATE analysis.rfpp_intent_v2_stage s
SET intent=analysis.rfpp_parse_intent_v2(b.reason)
FROM analysis.rfpp_request_pre_intent_v2 b WHERE b.rfpp_id=s.rfpp_id;
UPDATE analysis.rfpp_intent_v2_run SET parser_signature=(
 SELECT md5(string_agg(pg_get_functiondef(oid), E'\n' ORDER BY proname))
 FROM pg_proc WHERE pronamespace='analysis'::regnamespace
 AND proname IN ('rfpp_intent_normalize_v2','rfpp_intent_levels_v2','rfpp_parse_intent_v2')),
 staged_at=now() WHERE id=1;
COMMIT;
