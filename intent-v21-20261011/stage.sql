\set ON_ERROR_STOP on
SET TIME ZONE 'UTC';
SET statement_timeout='10min';
SET lock_timeout='5s';
BEGIN ISOLATION LEVEL REPEATABLE READ;
DO $$ BEGIN
 IF current_database()<>'wiki20260401' OR current_setting('port')<>'5434' THEN
  RAISE EXCEPTION 'Wrong target'; END IF;
 IF EXISTS(SELECT 1 FROM analysis.rfpp_request WHERE requested_intent->>'version' IS DISTINCT FROM 'rfpp-intent-v2.0.0') THEN
  RAISE EXCEPTION 'Unexpected predecessor'; END IF;
END $$;
CREATE TABLE analysis.rfpp_request_pre_intent_v21 TABLESPACE wiki_ts_lacie10 AS TABLE analysis.rfpp_request;
ALTER TABLE analysis.rfpp_request_pre_intent_v21 ADD PRIMARY KEY(rfpp_id) USING INDEX TABLESPACE wiki_ts_lacie10;
CREATE TABLE analysis.rfpp_intent_v21_stage TABLESPACE wiki_ts_lacie10 AS
SELECT rfpp_id,md5(to_jsonb(r)::text) before_hash,
 requested_action old_action,requested_level old_level,
 requested_intent old_intent,analysis.rfpp_parse_intent_v21(reason) intent
FROM analysis.rfpp_request_pre_intent_v21 r;
ALTER TABLE analysis.rfpp_intent_v21_stage ADD PRIMARY KEY(rfpp_id) USING INDEX TABLESPACE wiki_ts_lacie10;
CREATE TABLE analysis.rfpp_intent_v21_run (
 id integer PRIMARY KEY CHECK(id=1),status text NOT NULL,parser_signature text NOT NULL,
 prior_parser_definition text NOT NULL,staged_at timestamptz DEFAULT now(),applied_at timestamptz
) TABLESPACE wiki_ts_lacie10;
INSERT INTO analysis.rfpp_intent_v21_run(id,status,parser_signature,prior_parser_definition)
SELECT 1,'staged',md5(string_agg(pg_get_functiondef(oid),E'\n' ORDER BY proname)),
 pg_get_functiondef('analysis.rfpp_parse_intent_v2(text)'::regprocedure)
FROM pg_proc WHERE pronamespace='analysis'::regnamespace AND proname IN
 ('rfpp_intent_normalize_v21','rfpp_intent_levels_v21','rfpp_intent_clause_v21','rfpp_intent_direction_v21','rfpp_parse_intent_v21');
COMMIT;
SELECT count(*) population,
 count(*) FILTER(WHERE old_action IS DISTINCT FROM intent->>'action') action_changes,
 count(*) FILTER(WHERE old_level IS DISTINCT FROM intent->>'tier') tier_changes,
 count(*) FILTER(WHERE old_intent-'version' IS DISTINCT FROM intent-'version') metadata_changes
FROM analysis.rfpp_intent_v21_stage;
SELECT intent->>'status' status,intent->>'rule' rule,count(*) n
FROM analysis.rfpp_intent_v21_stage GROUP BY 1,2 ORDER BY 1,3 DESC;
