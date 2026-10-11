-- Scoped, audited repair. Default is a full rehearsal ending in ROLLBACK.
-- Apply: psql -X service=wiki -v commit_repair=1 -f apply_rfpp_intent_v21.sql
-- Requires the immutable backup, reviewed stage, and stage signature.
\set ON_ERROR_STOP on
\if :{?commit_repair}
\else
  \set commit_repair 0
\endif
SET TIME ZONE 'UTC';
SET lock_timeout='5s';
SET statement_timeout='30min';
SET work_mem='256MB';
DO $$ BEGIN
  IF current_database()<>'wiki20260401' OR current_setting('port')<>'5434' THEN
    RAISE EXCEPTION 'Wrong migration target';
  END IF;
END $$;
-- Short independent catalog change; release its exclusive lock before the scan.
ALTER TABLE analysis.rfpp_request ADD COLUMN IF NOT EXISTS requested_intent jsonb;
BEGIN;
LOCK TABLE analysis.rfpp_request IN SHARE ROW EXCLUSIVE MODE;
DO $$ DECLARE actual_signature text; BEGIN
  IF (SELECT status FROM analysis.rfpp_intent_v21_run WHERE id=1) IS DISTINCT FROM 'staged' THEN
    RAISE EXCEPTION 'Migration is not in staged state';
  END IF;
  SELECT md5(string_agg(pg_get_functiondef(oid), E'\n' ORDER BY proname)) INTO actual_signature
  FROM pg_proc WHERE pronamespace='analysis'::regnamespace
    AND proname IN ('rfpp_intent_normalize_v21','rfpp_intent_levels_v21','rfpp_intent_clause_v21','rfpp_intent_direction_v21','rfpp_parse_intent_v21');
  IF actual_signature IS DISTINCT FROM (SELECT parser_signature FROM analysis.rfpp_intent_v21_run WHERE id=1) THEN
    RAISE EXCEPTION 'Parser changed after staging';
  END IF;
  IF (SELECT count(*) FROM analysis.rfpp_request)<>(SELECT count(*) FROM analysis.rfpp_intent_v21_stage)
     OR EXISTS (SELECT 1 FROM analysis.rfpp_request r FULL JOIN analysis.rfpp_intent_v21_stage s USING(rfpp_id)
                WHERE r.rfpp_id IS NULL OR s.rfpp_id IS NULL
                   OR md5(to_jsonb(r)::text)<>s.before_hash) THEN
    RAISE EXCEPTION 'Live rows changed after staging; stop and reconcile';
  END IF;
END $$;

CREATE TEMP TABLE rfpp_match_ids AS
SELECT rfpp_id FROM analysis.rfpp_intent_v21_stage
WHERE old_action IS DISTINCT FROM intent->>'action';
CREATE UNIQUE INDEX ON rfpp_match_ids (rfpp_id);

UPDATE analysis.rfpp_request r
SET requested_intent=s.intent,
    requested_action=s.intent->>'action', requested_level=s.intent->>'tier',
    requested_level_source=s.intent->>'source',
    request_label=lower(btrim(regexp_replace(s.intent->>'label_raw','[:.\s]+$',''))),
    board=CASE WHEN r.archive_page ~ '/Increase' THEN 'increase'
               WHEN r.archive_page ~ '/Decrease' THEN 'decrease'
               WHEN r.archive_page ~ '/Edit' THEN 'edit' ELSE s.intent->>'action' END
FROM analysis.rfpp_intent_v21_stage s WHERE s.rfpp_id=r.rfpp_id;

-- Recompute only associations whose direction input changed. Applied levels
-- still come solely from protection events, never from the requested tier.
\ir /home/simone/githubRepos/wikipediaData/20261001/wpp-analysis/sql/04c_rfpp_request_match.sql

CREATE TABLE analysis.rfpp_intent_v21_changes TABLESPACE wiki_ts_lacie10 AS
SELECT r.rfpp_id,s.before_hash,md5(to_jsonb(r)::text) AS after_hash,
       b.requested_action AS old_action,r.requested_action AS new_action,
       b.requested_level AS old_level,r.requested_level AS new_level,
       b.requested_level_source AS old_source,r.requested_level_source AS new_source,
       b.request_label AS old_label,r.request_label AS new_label,
       b.board AS old_board,r.board AS new_board,
       b.matched_log_id AS old_log_id,r.matched_log_id AS new_log_id,
       b.treated_by_log AS old_treated_by_log,r.treated_by_log AS new_treated_by_log,
       r.requested_intent,current_timestamp AS applied_at
FROM analysis.rfpp_request r JOIN analysis.rfpp_request_pre_intent_v21 b USING(rfpp_id)
JOIN analysis.rfpp_intent_v21_stage s USING(rfpp_id)
WHERE (to_jsonb(r)-'requested_intent') IS DISTINCT FROM (to_jsonb(b)-'requested_intent')
 OR r.requested_intent-'version' IS DISTINCT FROM b.requested_intent-'version';
ALTER TABLE analysis.rfpp_intent_v21_changes
  ADD PRIMARY KEY(rfpp_id) USING INDEX TABLESPACE wiki_ts_lacie10;

DO $$ DECLARE mutable text[] := ARRAY[
 'requested_intent','requested_action','requested_level','requested_level_source','request_label','board',
 'matched_log_id','matched_offset','matched_action','matched_same_admin','granted_type','granted_level',
 'granted_level_raw','scheduled_expiry','treated_by_log']; BEGIN
  IF EXISTS(SELECT 1 FROM analysis.rfpp_request r JOIN analysis.rfpp_request_pre_intent_v21 b USING(rfpp_id)
            WHERE (to_jsonb(r)-mutable) IS DISTINCT FROM (to_jsonb(b)-mutable)) THEN
    RAISE EXCEPTION 'A raw, outcome, identity, or unrelated derived field changed';
  END IF;
  IF EXISTS(SELECT 1 FROM analysis.rfpp_request r JOIN analysis.rfpp_intent_v21_stage s USING(rfpp_id)
            WHERE r.requested_intent IS DISTINCT FROM s.intent
               OR r.requested_action IS DISTINCT FROM s.intent->>'action'
               OR r.requested_level IS DISTINCT FROM s.intent->>'tier') THEN
    RAISE EXCEPTION 'Applied classifications differ from reviewed stage';
  END IF;
  IF EXISTS(SELECT 1 FROM analysis.rfpp_request r JOIN analysis.rfpp_request_pre_intent_v21 b USING(rfpp_id)
            WHERE r.requested_action IS NOT DISTINCT FROM b.requested_action
              AND (r.matched_log_id,r.matched_offset,r.matched_action,r.matched_same_admin,
                   r.granted_type,r.granted_level,r.granted_level_raw,r.scheduled_expiry,r.treated_by_log)
                  IS DISTINCT FROM
                  (b.matched_log_id,b.matched_offset,b.matched_action,b.matched_same_admin,
                   b.granted_type,b.granted_level,b.granted_level_raw,b.scheduled_expiry,b.treated_by_log)) THEN
    RAISE EXCEPTION 'Association outside changed-action scope was altered';
  END IF;
END $$;

-- Frozen analytical products retain their original values and are explicitly
-- registered for review/rebuild. Their source population/medians can change,
-- so updating copied labels in place would leave inconsistent samples.
CREATE TABLE analysis.rfpp_intent_v21_invalidations (
 object_name text PRIMARY KEY, direct_changed_rows bigint,
 status text NOT NULL, reason text NOT NULL, recorded_at timestamptz DEFAULT now()
) TABLESPACE wiki_ts_lacie10;
DO $$ DECLARE t record; n bigint; BEGIN
 FOR t IN SELECT c.table_name FROM information_schema.columns c
          JOIN pg_class p ON p.relname=c.table_name AND p.relnamespace='analysis'::regnamespace
          WHERE c.table_schema='analysis' AND c.column_name='rfpp_id' AND p.relkind='r'
            AND c.table_name<>'rfpp_request' AND c.table_name NOT LIKE 'rfpp_intent_v2%' AND c.table_name NOT LIKE 'rfpp_request_pre_intent%'
            AND c.table_name<>'rfpp_request_pre_intent_v21'
 LOOP
   EXECUTE format('SELECT count(*) FROM analysis.%I t JOIN analysis.rfpp_intent_v21_changes c USING(rfpp_id)',t.table_name) INTO n;
   INSERT INTO analysis.rfpp_intent_v21_invalidations(object_name,direct_changed_rows,status,reason)
   VALUES ('analysis.'||t.table_name,n,'review_or_rebuild',
     'Frozen pre-intent-v2 product. Direct changed IDs counted; selection and grouped duration/eligibility effects can also affect other rows. Rebuild the dependency chain before combining with current classifications.');
 END LOOP;
END $$;
ALTER TABLE analysis.rfpp_intent_v21_stage ADD COLUMN after_hash text;
UPDATE analysis.rfpp_intent_v21_stage s SET after_hash=md5(to_jsonb(r)::text) FROM analysis.rfpp_request r WHERE r.rfpp_id=s.rfpp_id;
UPDATE analysis.rfpp_intent_v2_run SET status='superseded_by_v21' WHERE id=1;
UPDATE analysis.rfpp_intent_v21_run SET status='applied',applied_at=now() WHERE id=1;
COMMENT ON COLUMN analysis.rfpp_request.requested_intent IS
'rfpp-intent-v2.1.0: request-only evidence, origin/target set, uncertainty, raw label, and parsing rule. Prior values and full source records retained in analysis.rfpp_request_pre_intent_v21; see changes and invalidations tables.';
CREATE OR REPLACE FUNCTION analysis.rfpp_parse_intent_v2(reason text)
RETURNS jsonb LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $fn$
SELECT analysis.rfpp_parse_intent_v21(reason);
$fn$;
ANALYZE analysis.rfpp_request;
SELECT count(*) AS population FROM analysis.rfpp_request;
SELECT count(*) AS changed_records,
 count(*) FILTER(WHERE old_action IS DISTINCT FROM new_action) AS action_changes,
 count(*) FILTER(WHERE old_level IS DISTINCT FROM new_level) AS tier_changes,
 count(*) FILTER(WHERE old_log_id IS DISTINCT FROM new_log_id) AS matched_log_changes
FROM analysis.rfpp_intent_v21_changes;
\if :commit_repair
 COMMIT;
\else
 ROLLBACK;
\endif
