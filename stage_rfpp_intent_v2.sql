-- Immutable pre-repair backup plus full-population candidate classifications.
-- Refuses to overwrite an existing backup or stage; inspect before resuming.
\set ON_ERROR_STOP on
SET TIME ZONE 'UTC';
SET lock_timeout='5s';
SET statement_timeout='30min';
BEGIN ISOLATION LEVEL REPEATABLE READ;
CREATE TABLE analysis.rfpp_request_pre_intent_v2 TABLESPACE wiki_ts_lacie10 AS
SELECT * FROM analysis.rfpp_request;
ALTER TABLE analysis.rfpp_request_pre_intent_v2
    ADD PRIMARY KEY (rfpp_id) USING INDEX TABLESPACE wiki_ts_lacie10;
COMMENT ON TABLE analysis.rfpp_request_pre_intent_v2 IS
'Immutable full RFPP snapshot before issue #1 intent-v2 repair, 2026-10-10. Includes raw fields and original classifications/linkage. Retain for rollback and historical analyses.';
CREATE TABLE analysis.rfpp_intent_v2_stage TABLESPACE wiki_ts_lacie10 AS
SELECT rfpp_id, md5(to_jsonb(r)::text) AS before_hash,
       requested_action AS old_action, requested_level AS old_level,
       requested_level_source AS old_source, board AS old_board,
       analysis.rfpp_parse_intent_v2(reason) AS intent
FROM analysis.rfpp_request_pre_intent_v2 r;
ALTER TABLE analysis.rfpp_intent_v2_stage
    ADD PRIMARY KEY (rfpp_id) USING INDEX TABLESPACE wiki_ts_lacie10;
COMMENT ON TABLE analysis.rfpp_intent_v2_stage IS
'Full-population staged RFPP intent-v2 candidates for db-auditing issue #1. Proposed values and explicit uncertainty, not applied automatically by this script.';
ANALYZE analysis.rfpp_intent_v2_stage;
CREATE TABLE analysis.rfpp_intent_v2_run (
 id integer PRIMARY KEY CHECK(id=1), parser_signature text NOT NULL,
 status text NOT NULL, staged_at timestamptz NOT NULL DEFAULT now(), applied_at timestamptz
) TABLESPACE wiki_ts_lacie10;
INSERT INTO analysis.rfpp_intent_v2_run(id,parser_signature,status)
SELECT 1,md5(string_agg(pg_get_functiondef(oid), E'\n' ORDER BY proname)),'staged'
FROM pg_proc WHERE pronamespace='analysis'::regnamespace
AND proname IN ('rfpp_intent_normalize_v2','rfpp_intent_levels_v2','rfpp_parse_intent_v2');
COMMIT;
SELECT count(*) AS population,
       count(*) FILTER(WHERE old_action IS DISTINCT FROM intent->>'action') AS action_changes,
       count(*) FILTER(WHERE old_level IS DISTINCT FROM intent->>'tier') AS tier_changes
FROM analysis.rfpp_intent_v2_stage;
SELECT intent->>'status' AS status,count(*) FROM analysis.rfpp_intent_v2_stage GROUP BY 1 ORDER BY 2 DESC;
