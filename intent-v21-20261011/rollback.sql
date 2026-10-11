-- Guarded reversal of this repair, defaulting to a rehearsal.
\set ON_ERROR_STOP on
SET TIME ZONE 'UTC';
\if :{?commit_rollback}
\else
 \set commit_rollback 0
\endif
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='10min';
LOCK TABLE analysis.rfpp_request IN SHARE ROW EXCLUSIVE MODE;
DO $$ BEGIN
 IF (SELECT status FROM analysis.rfpp_intent_v21_run WHERE id=1) IS DISTINCT FROM 'applied' THEN
  RAISE EXCEPTION 'Repair is not applied'; END IF;
 IF EXISTS(SELECT 1 FROM analysis.rfpp_request r FULL JOIN analysis.rfpp_intent_v21_stage s USING(rfpp_id)
  WHERE r.rfpp_id IS NULL OR s.rfpp_id IS NULL OR md5(to_jsonb(r)::text) IS DISTINCT FROM s.after_hash) THEN
  RAISE EXCEPTION 'Post-repair rows changed; refusing overwrite'; END IF;
END $$;
UPDATE analysis.rfpp_request r SET
 (requested_intent,requested_action,requested_level,requested_level_source,request_label,board,
 matched_log_id,matched_offset,matched_action,matched_same_admin,granted_type,granted_level,
 granted_level_raw,scheduled_expiry,treated_by_log)=
 (b.requested_intent,b.requested_action,b.requested_level,b.requested_level_source,b.request_label,b.board,
 b.matched_log_id,b.matched_offset,b.matched_action,b.matched_same_admin,b.granted_type,b.granted_level,
 b.granted_level_raw,b.scheduled_expiry,b.treated_by_log)
FROM analysis.rfpp_request_pre_intent_v21 b WHERE b.rfpp_id=r.rfpp_id;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM analysis.rfpp_request r FULL JOIN analysis.rfpp_request_pre_intent_v21 b USING(rfpp_id)
 WHERE to_jsonb(r) IS DISTINCT FROM to_jsonb(b)) THEN RAISE EXCEPTION 'Rollback differs from backup'; END IF;
 EXECUTE (SELECT prior_parser_definition FROM analysis.rfpp_intent_v21_run WHERE id=1);
END $$;
UPDATE analysis.rfpp_intent_v21_run SET status='rolled_back' WHERE id=1;
UPDATE analysis.rfpp_intent_v2_run SET status='applied' WHERE id=1;
COMMENT ON COLUMN analysis.rfpp_request.requested_intent IS
'rfpp-intent-v2.0.0 restored by guarded v2.1 rollback; see audit tables.';
\if :commit_rollback
 COMMIT;
\else
 ROLLBACK;
\endif
-- If committed, separately restore parser-before.sql as SQL04 parser source,
-- tests-before.py as the test source, and rfpp_request.pre-intent-v21.parquet.
-- Preserve both repair generations and their audit tables.
