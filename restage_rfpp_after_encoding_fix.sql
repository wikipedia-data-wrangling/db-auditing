-- One-time recovery after the first application was fully rolled back.
-- Archive its audit tables before preparing the corrected normalizer run.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
 IF (SELECT status FROM analysis.rfpp_intent_v2_run WHERE id=1) IS DISTINCT FROM 'rolled_back' THEN
  RAISE EXCEPTION 'Original values must first be restored by guarded rollback'; END IF;
END $$;
ALTER TABLE analysis.rfpp_intent_v2_changes RENAME TO rfpp_intent_v2_first_apply_changes;
ALTER TABLE analysis.rfpp_intent_v2_invalidations RENAME TO rfpp_intent_v2_first_apply_invalidations;
CREATE TABLE analysis.rfpp_intent_v2_first_run TABLESPACE wiki_ts_lacie10 AS SELECT * FROM analysis.rfpp_intent_v2_run;
UPDATE analysis.rfpp_intent_v2_run SET status='staged',applied_at=NULL WHERE id=1;
COMMIT;
\ir restage_rfpp_intent_v2.sql
