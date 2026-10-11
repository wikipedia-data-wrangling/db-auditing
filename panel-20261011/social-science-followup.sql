\set ON_ERROR_STOP on
\pset pager off
BEGIN READ ONLY;
SET LOCAL statement_timeout='30s';
SET LOCAL TIME ZONE 'UTC';
SELECT count(*) AS quality_sample,count(*) FILTER(WHERE s.page_id IS DISTINCT FROM r.page_id_match) AS identity_differs_from_match, count(*) FILTER(WHERE r.page_is_redirect) AS source_id_is_redirect FROM analysis.sample_request_treated s JOIN analysis.rfpp_request r USING(rfpp_id);
SELECT arm,round((percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM (least(coalesce(expiry_anchor,pull_end),pull_end)-admin_ts))/86400))::numeric,2) AS median_during_days, min(extract(epoch FROM (least(coalesce(expiry_anchor,pull_end),pull_end)-admin_ts))/86400) AS min_during_days,max(extract(epoch FROM (least(coalesce(expiry_anchor,pull_end),pull_end)-admin_ts))/86400) AS max_during_days FROM analysis.sample_page_full GROUP BY 1 ORDER BY 1;
SELECT table_name,column_name FROM information_schema.columns WHERE table_schema='analysis' AND table_name='neighbour_page_full' ORDER BY ordinal_position;
SELECT grp,count(*) AS user_ids_with_multiple_intervals FROM (SELECT grp,user_id FROM analysis.user_group_interval WHERE grp IN ('sysop','bot','extendedconfirmed') AND user_id IS NOT NULL GROUP BY grp,user_id HAVING count(*)>1) x GROUP BY grp ORDER BY grp;
COMMIT;
