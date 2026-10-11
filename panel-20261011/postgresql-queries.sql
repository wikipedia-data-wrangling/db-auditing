\set ON_ERROR_STOP on
\pset pager off
\timing on
BEGIN READ ONLY;
SET LOCAL statement_timeout='30s';
SET LOCAL lock_timeout='2s';
SELECT now() AS audited_at,current_database(),current_setting('port'),version(),current_setting('server_encoding'),pg_size_pretty(pg_database_size(current_database()));
SELECT n.nspname,c.relname,c.relkind,c.reltuples::bigint AS estimated_rows,pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size,t.spcname,st.n_live_tup,st.n_dead_tup,st.last_analyze,st.last_autoanalyze,st.last_autovacuum FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace LEFT JOIN pg_tablespace t ON t.oid=c.reltablespace LEFT JOIN pg_stat_all_tables st ON st.relid=c.oid WHERE n.nspname='public' AND c.relkind IN ('r','p') ORDER BY pg_total_relation_size(c.oid) DESC;
SELECT conrelid::regclass,conname,contype,convalidated,pg_get_constraintdef(oid) FROM pg_constraint WHERE connamespace IN ('public'::regnamespace,'analysis'::regnamespace) ORDER BY conrelid::regclass::text,conname;
SELECT n.nspname,c.relname,i.indexrelid::regclass,i.indisvalid,i.indisready,pg_size_pretty(pg_relation_size(i.indexrelid)),pg_get_indexdef(i.indexrelid) FROM pg_index i JOIN pg_class c ON c.oid=i.indrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' OR NOT i.indisvalid OR NOT i.indisready ORDER BY c.relname,i.indexrelid::regclass::text;
SELECT i.indrelid::regclass,array_agg(i.indexrelid::regclass) AS possible_duplicate_indexes FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname NOT IN ('pg_catalog','information_schema') GROUP BY i.indrelid,c.relam,i.indkey,i.indclass,i.indcollation,i.indoption,i.indexprs::text,i.indpred::text,i.indisunique HAVING count(*)>1;
SELECT c.oid::regclass,pg_get_partkeydef(c.oid) FROM pg_class c WHERE c.relkind='p';
SELECT inhparent::regclass,inhrelid::regclass,pg_get_expr(c.relpartbound,c.oid) FROM pg_inherits JOIN pg_class c ON c.oid=inhrelid WHERE c.relispartition;
SELECT spcname,pg_tablespace_location(oid) FROM pg_tablespace;
SELECT name,setting,unit FROM pg_settings WHERE name IN ('autovacuum','autovacuum_analyze_scale_factor','autovacuum_vacuum_scale_factor','default_statistics_target','shared_buffers','work_mem','maintenance_work_mem','max_parallel_workers_per_gather','max_connections','effective_cache_size','data_checksums');
SELECT datname,stats_reset,deadlocks,temp_files,pg_size_pretty(temp_bytes) AS temp_bytes,checksum_failures FROM pg_stat_database WHERE datname=current_database();
SELECT p.page_id FROM public.page p WHERE page_id=1133504;
SELECT r.rev_id,r.rev_page FROM public.revision r WHERE rev_page=1133504 LIMIT 5;
SELECT pr.pr_page,count(*) FROM public.page_restrictions pr LEFT JOIN public.page p ON p.page_id=pr.pr_page WHERE p.page_id IS NULL GROUP BY pr.pr_page ORDER BY pr.pr_page;
SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p') AND NOT EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid=c.oid AND k.contype='p') ORDER BY c.relname;
COMMIT;
