\set ON_ERROR_STOP on
BEGIN READ ONLY;
SET LOCAL statement_timeout='20s';
SET LOCAL lock_timeout='2s';
SELECT current_database(),current_setting('port') AS port,current_setting('server_encoding') AS server_encoding;
SELECT * FROM analysis.rfpp_intent_v2_run;
SELECT object_name,direct_changed_rows,status FROM analysis.rfpp_intent_v2_invalidations ORDER BY object_name;
SELECT md5(string_agg(pg_get_functiondef(oid), E'\n' ORDER BY proname)) AS current_parser_signature FROM pg_proc WHERE pronamespace='analysis'::regnamespace AND proname IN ('rfpp_intent_normalize_v2','rfpp_intent_levels_v2','rfpp_parse_intent_v2');
SELECT rfpp_id,requested_action,requested_level,requested_intent->>'version' AS parser_version FROM analysis.rfpp_request WHERE rfpp_id IN (737,127462,144377,154614);
ROLLBACK;
