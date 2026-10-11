-- Default rehearsal. Add -v commit_rollback=1 to restore the pre-repair derived fields.
-- Does not delete audit evidence. Restore the preserved Parquet separately.
\set ON_ERROR_STOP on
\if :{?commit_rollback}
\else
 \set commit_rollback 0
\endif
SET TIME ZONE 'UTC';
SET lock_timeout='5s';
SET statement_timeout='30min';
BEGIN;
LOCK TABLE analysis.rfpp_request IN SHARE ROW EXCLUSIVE MODE;
DO $$ BEGIN
 IF current_database()<>'wiki20260401' OR current_setting('port')<>'5434' THEN
  RAISE EXCEPTION 'Wrong rollback target'; END IF;
 IF (SELECT status FROM analysis.rfpp_intent_v2_run WHERE id=1) IS DISTINCT FROM 'applied' THEN
  RAISE EXCEPTION 'Repair is not applied'; END IF;
 IF (SELECT count(*) FROM analysis.rfpp_request)<>(SELECT count(*) FROM analysis.rfpp_intent_v2_stage)
 OR EXISTS(SELECT 1 FROM analysis.rfpp_request r FULL JOIN analysis.rfpp_intent_v2_stage s USING(rfpp_id)
 LEFT JOIN analysis.rfpp_intent_v2_changes c USING(rfpp_id)
 WHERE r.rfpp_id IS NULL OR s.rfpp_id IS NULL OR r.requested_intent IS DISTINCT FROM s.intent
 OR md5((to_jsonb(r)-'requested_intent')::text) IS DISTINCT FROM coalesce(c.after_hash,s.before_hash)) THEN
  RAISE EXCEPTION 'Rows changed since repair; reconcile before rollback'; END IF;
END $$;
UPDATE analysis.rfpp_request r SET
 requested_action=b.requested_action, requested_level=b.requested_level,
 requested_level_source=b.requested_level_source, request_label=b.request_label, board=b.board,
 matched_log_id=b.matched_log_id, matched_offset=b.matched_offset,
 matched_action=b.matched_action, matched_same_admin=b.matched_same_admin,
 granted_type=b.granted_type, granted_level=b.granted_level,
 granted_level_raw=b.granted_level_raw, scheduled_expiry=b.scheduled_expiry,
 treated_by_log=b.treated_by_log, requested_intent=NULL
FROM analysis.rfpp_request_pre_intent_v2 b WHERE b.rfpp_id=r.rfpp_id;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM analysis.rfpp_request r JOIN analysis.rfpp_request_pre_intent_v2 b USING(rfpp_id)
 WHERE (to_jsonb(r)-'requested_intent') IS DISTINCT FROM to_jsonb(b)) THEN
  RAISE EXCEPTION 'Rollback differs from original snapshot'; END IF;
END $$;
UPDATE analysis.rfpp_intent_v2_run SET status='rolled_back' WHERE id=1;
\if :commit_rollback
 COMMIT;
\else
 ROLLBACK;
\endif
