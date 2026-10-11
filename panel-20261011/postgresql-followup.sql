\set ON_ERROR_STOP on
\pset pager off
BEGIN READ ONLY;
SET LOCAL statement_timeout='30s'; SET LOCAL lock_timeout='2s';
SELECT d.datname,t.spcname FROM pg_database d JOIN pg_tablespace t ON t.oid=d.dattablespace WHERE datname=current_database();
SELECT c.oid::regclass,c.reloptions,coalesce(t.spcname,'database default') AS heap_tablespace,pg_size_pretty(pg_relation_size(c.oid)) AS heap_size,c.reltoastrelid::regclass,coalesce(tt.spcname,'database default') AS toast_tablespace,pg_size_pretty(pg_total_relation_size(c.reltoastrelid)) AS toast_total FROM pg_class c LEFT JOIN pg_tablespace t ON t.oid=c.reltablespace LEFT JOIN pg_class tc ON tc.oid=c.reltoastrelid LEFT JOIN pg_tablespace tt ON tt.oid=tc.reltablespace WHERE c.oid IN ('public.revision_text_p1'::regclass,'public.revision_text_p2'::regclass,'public.revision'::regclass,'analysis.rfpp_request'::regclass);
SELECT count(*) AS logging_rows_with_page_id FROM public.logging WHERE log_page IS NOT NULL;
SELECT schemaname,tablename,attname,null_frac,n_distinct FROM pg_stats WHERE schemaname='public' AND (tablename,attname) IN (('logging','log_page'),('revision','rev_page'),('page','page_latest'));
SELECT schemaname,relname,n_live_tup,n_dead_tup,last_analyze,last_autoanalyze,last_autovacuum,n_mod_since_analyze FROM pg_stat_user_tables WHERE schemaname='analysis' ORDER BY n_dead_tup DESC LIMIT 15;
SELECT pid,application_name,state,wait_event_type,wait_event,now()-xact_start AS transaction_age FROM pg_stat_activity WHERE datname=current_database() AND pid<>pg_backend_pid() ORDER BY xact_start NULLS LAST;
SELECT n.nspname,c.relname,age(c.relfrozenxid) AS xid_age FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind='r' AND n.nspname IN ('public','analysis') ORDER BY age(c.relfrozenxid) DESC LIMIT 5;
COMMIT;
