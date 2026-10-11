\set ON_ERROR_STOP on
BEGIN READ ONLY;
SET LOCAL statement_timeout='60s';
SELECT jsonb_build_object('summary',jsonb_build_object('population',count(*),
 'action_changes',count(*) FILTER(WHERE old_action IS DISTINCT FROM intent->>'action'),
 'tier_changes',count(*) FILTER(WHERE old_level IS DISTINCT FROM intent->>'tier'),
 'semantic_changes',count(*) FILTER(WHERE old_intent-'version' IS DISTINCT FROM intent-'version')))
FROM analysis.rfpp_intent_v21_stage;
SELECT jsonb_build_object('stratum',row_to_json(t)) FROM (
 SELECT old_action,intent->>'action' new_action,old_level,intent->>'tier' new_tier,count(*) n
 FROM analysis.rfpp_intent_v21_stage
 WHERE (old_action,old_level) IS DISTINCT FROM (intent->>'action',intent->>'tier')
 GROUP BY 1,2,3,4 ORDER BY 5 DESC) t;
WITH ranked AS (
 SELECT s.*,row_number() OVER(PARTITION BY old_action,intent->>'action',old_level,intent->>'tier',intent->>'rule'
 ORDER BY md5('v21-review:'||rfpp_id::text)) rn
 FROM analysis.rfpp_intent_v21_stage s
 WHERE old_intent-'version' IS DISTINCT FROM intent-'version')
SELECT jsonb_build_object('sample',jsonb_build_object('rfpp_id',s.rfpp_id,
 'old',s.old_intent,'new',s.intent,'reason',b.reason))
FROM ranked s JOIN analysis.rfpp_request_pre_intent_v21 b USING(rfpp_id)
WHERE rn<=2 ORDER BY s.rfpp_id;
ROLLBACK;
