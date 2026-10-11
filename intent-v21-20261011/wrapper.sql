CREATE OR REPLACE FUNCTION analysis.rfpp_parse_intent_v2(reason text)
RETURNS jsonb LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $fn$
SELECT analysis.rfpp_parse_intent_v21(reason);
$fn$;
