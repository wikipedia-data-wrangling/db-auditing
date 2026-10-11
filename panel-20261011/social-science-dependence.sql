\set ON_ERROR_STOP on
\pset pager off
BEGIN READ ONLY;
SET LOCAL statement_timeout='30s';
SELECT count(*) AS window_neighbour_rows,count(DISTINCT neighbour_page_id) AS distinct_neighbours FROM analysis.neighbour_page_full;
SELECT count(*) AS neighbours_in_multiple_windows,max(n_windows) AS maximum_windows FROM (SELECT neighbour_page_id,count(DISTINCT window_id) AS n_windows FROM analysis.neighbour_page_full GROUP BY 1 HAVING count(DISTINCT window_id)>1) x;
SELECT count(*) AS quality_cutoffs,count(*) FILTER(WHERE q.article_page_id IS DISTINCT FROM r.page_id_match) AS cutoffs_with_identity_difference FROM analysis.quality_cutoff q JOIN analysis.rfpp_request r USING(rfpp_id);
COMMIT;
