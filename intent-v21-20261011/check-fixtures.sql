\set ON_ERROR_STOP on
BEGIN READ ONLY;
SET LOCAL statement_timeout='45s';
SET LOCAL standard_conforming_strings=on;
WITH fixtures(case_id,rfpp_id,synthetic_reason,expected) AS (VALUES
('live-5270',5270,NULL,'{"tier": "semi", "origin": "pc", "action": "change"}'::jsonb),
('live-214872',214872,NULL,'{"targets": ["move"]}'::jsonb),
('live-8243',8243,NULL,'{"tier": "salt"}'::jsonb),
('live-44093',44093,NULL,'{"tier": "full"}'::jsonb),
('live-137153',137153,NULL,'{"tier": "semi"}'::jsonb),
('live-173498',173498,NULL,'{"label_raw": "Request increase of duration of current page protection"}'::jsonb),
('live-192177',192177,NULL,'{"tier": "semi", "label_raw": "Temporary semi-protection"}'::jsonb),
('live-114550',114550,NULL,'{"tier": "semi", "origin": "ecp", "action": "decrease"}'::jsonb),
('live-162248',162248,NULL,'{"tier": "ecp"}'::jsonb),
('live-183512',183512,NULL,'{"tier": "none", "action": "decrease"}'::jsonb),
('live-204731',204731,NULL,'{"action": "edit"}'::jsonb),
('live-212374',212374,NULL,'{"tier": "ecp"}'::jsonb),
('live-185991',185991,NULL,'{"tier": "semi", "action": "increase"}'::jsonb),
('live-198445',198445,NULL,'{"tier": "semi", "action": "increase"}'::jsonb),
('live-5784',5784,NULL,'{"tier": "none", "action": "decrease"}'::jsonb),
('synthetic-1',NULL,'''''''Reason:'''''' ''''''Temporary semi-protection'''''' Body ''''''other text''''''','{"label_raw": "Temporary semi-protection", "tier": "semi"}'::jsonb),
('synthetic-2',NULL,'''''''Long-term (not necessarily indefinite) full protection''''''','{"tier": "full"}'::jsonb),
('synthetic-3',NULL,'''''''Reason:'''''' Requesting semi protection to reduce disruption.','{"action": "increase", "tier": "semi"}'::jsonb),
('synthetic-4',NULL,'''''''Remove semi-protection''''''','{"action": "decrease", "tier": "none"}'::jsonb),
('synthetic-5',NULL,'''''''Change PC protection to semi-protection''''''','{"action": "change", "origin": "pc", "tier": "semi"}'::jsonb),
('synthetic-6',NULL,'''''''Reason:'''''' Unprotection','{"action": "decrease", "tier": "none"}'::jsonb),
('synthetic-7',NULL,'''''''extended protection''''''','{"tier": null}'::jsonb),
('synthetic-8',NULL,'''''''extended semi-protection''''''','{"tier": "semi"}'::jsonb),
('synthetic-9',NULL,'''''''Reason:'''''' Previous ECP was removed. Persistent vandalism.','{"tier": null}'::jsonb),
('synthetic-10',NULL,'''''''temporary <s>extended confirmed</s> semi''''''','{"tier": null, "status": "chronology_uncertain"}'::jsonb)), results AS (
SELECT f.case_id,f.rfpp_id,coalesce(f.synthetic_reason,r.reason) reason,f.expected,
analysis.rfpp_parse_intent_v21(coalesce(f.synthetic_reason,r.reason)) actual
FROM fixtures f LEFT JOIN analysis.rfpp_request r ON r.rfpp_id=f.rfpp_id)
SELECT jsonb_build_object('case_id',case_id,'rfpp_id',rfpp_id,'reason',reason,
 'expected',expected,'actual',actual,
 'passed', reason IS NOT NULL AND NOT EXISTS (
 SELECT 1 FROM jsonb_each(expected) e WHERE actual->e.key IS DISTINCT FROM e.value))
FROM results ORDER BY case_id;
ROLLBACK;
