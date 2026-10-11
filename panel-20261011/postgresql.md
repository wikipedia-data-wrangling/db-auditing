# PostgreSQL specialist audit — 11 October 2026

Target confirmed live at 09:25 BST: `wiki20260401`, port `5434`, PostgreSQL 18.4, approximately 14 TiB database size. Assessment used catalog reads, indexed probes, and one complete scan of the small `page_restrictions` relation joined to the page primary key. Every database statement ran in an explicit read-only transaction with 30-second statement and 2-second lock timeouts. No DDL, data repair, index creation, maintenance, or configuration change was performed. This is a structural and operational audit, not a full consistency check of 1.25 billion revisions or 14 TiB of text.

Evidence is reproducible in [postgresql-queries.sql](postgresql-queries.sql), [results](postgresql-query-results.txt), [follow-up SQL](postgresql-followup.sql), and [follow-up results](postgresql-followup-results.txt). Statistics below explicitly distinguish measured results from catalog estimates.

## Findings

### PG-01 — High: incomplete relationship migration leaves an unvalidated, enforced-on-new-writes foreign key

Live `revision_rev_page_fkey` is `FOREIGN KEY (rev_page) REFERENCES page(page_id) NOT VALID`. The 10 October [run log](../../official-dump/logs/index-connect-20261010.log) records validation failing because page ID `1133504` was absent. Its subsequent attempt to drop the newly created constraint failed with a lock timeout; [status JSON](../../official-dump/logs/index-connect-status.json) records only this final timeout as the top-level error. The live indexed probe returned revision IDs `7111938`, `11708322`, `16896358`, `773988997`, and `784468480` for that page, and no parent page row. This establishes a real historical inconsistency; it does not quantify its full prevalence or establish why the source snapshots differ.

`NOT VALID` is not equivalent to an inactive relationship: future inserts and relevant updates are checked while existing rows remain unproven. The runbook's documented cleanup promise was not fulfilled. The subsequent `change_tag.ct_tag_id` validation step was never reached, and no such FK exists live. Both actor indexes and the logging/revision actor FKs did complete and are valid.

Recommended action: make migration recovery record both the validation error and cleanup error, classify the residual constraint explicitly, and make continuation independent of failed candidate relationships. Decide whether this heterogeneous snapshot should keep this relationship as an audited LEFT JOIN rather than a strict FK. Do not delete child revisions or invent parent pages to obtain validation. If the constraint should be removed, schedule that separately with lock-aware execution; no constraint was changed by this audit. Quantify unmatched revisions with a planned large-table job before interpreting inner-join samples as complete.

### PG-02 — High: relation views preserve rows, but missing page references remain consequential

The full small-table anti-join measured **2,414 page-restriction rows referring to 1,487 absent page IDs**; three rows have `pr_page=0`. The catalog estimates 192,836 restriction rows, giving an approximate 1.25% unmatched share; the unmatched numerator is exact, the denominator was not recounted here. Individual absent IDs and multiplicities are retained in the query results. This confirms why a hard restriction→page FK is unsuitable without reconciling snapshot provenance.

An indexed count measured **zero non-NULL `public.logging.log_page` values**. This is consistent with its 8 KiB empty partial index and `pg_stats.null_frac=1`. Consequently, a log→page join on this field cannot resolve any record in this loaded snapshot. This is missing linkage, not evidence that all events concerned nonexistent pages. Namespace/title linkage can be useful, but moves, deletions, recreations, and time differences prevent treating a current title match as certain historical page identity.

Recommended action: distinguish missing IDs, failed joins, and historical absence in consumer-facing data dictionaries and QA summaries. Preserve LEFT JOIN and found-flag semantics. Inspect export/loader provenance for why logging page IDs were unavailable, then use existing independently sourced analysis linkage only with explicit source and temporal qualifiers. Validate derived samples for selection induced by missing links.

### PG-03 — High operational risk: default tablespace is on a nearly full volume

Database default tablespace is `wiki_ts_lacie`, located at `/media/simone/lacie14/postgres-wiki`. `revision_text_p1` uses that default for both heap and TOAST: approximately 320 GiB heap, 9,360 GiB TOAST, and 25 GiB primary-key index, totaling approximately 9,705 GiB. Filesystem inspection showed the underlying volume **96% used with 521 GiB available**. This is insufficient headroom for an in-place rewrite or complete temporary copy of this partition. Other relevant volumes: lacie10 51% used/4.3 TiB available; SSD1 86% used/1.1 TiB available; system volume 74% used/235 GiB available. These are filesystem measurements, not database relation estimates, and can change after the audit.

New objects without explicit placement inherit the constrained default. Recommended action: document free-space thresholds and explicit placement for large derived objects; plan partition movement or capacity expansion before any rewrite, VACUUM FULL, or large index operation. Do not infer that aggregate free space across volumes permits a particular single-volume operation. This audit neither moved data nor performed maintenance.

### PG-04 — Medium: SQL_ASCII is an intentional byte-storage design with demonstrated parser risks

The database reports `server_encoding=SQL_ASCII`. Base schemas explicitly use byte-transparent representations, including bytea titles/names and text wikitext. SQL_ASCII does not enforce one Unicode encoding for textual values, so client encoding and binary-to-text conversions form part of the research pipeline's correctness contract. The existing RFPP repair log already records an encoding-defective attempt and its rollback; this audit does not claim that any remaining text is corrupt.

Recommended action: retain raw bytes; require explicit UTF-8 decoding/error policy at ingestion and exports; retain regression cases for punctuation, non-ASCII names, entities, and reversible metadata round trips. Record client/server encoding in every audit manifest. Treat any UTF-8 database migration as a separately planned validation and storage project, not a quick ALTER or blanket conversion.

### PG-05 — Medium/low: query-planning estimates and operational observability merit targeted review

Catalog estimates: revision 1,249,572,224 rows; text partitions 914,149,056 and 333,731,104; logging 158,079,680; change_tag 545,880,896; page 65,414,500. These are not exact counts. The partitioned text parent's estimate is 1,254,580,608, whereas its child estimates total 1,247,880,160. This difference cannot establish missing text; parent and child samples are approximate and recorded independently. A missing-text rate requires measured ID comparisons, not subtraction of these values.

`revision.rev_page` has estimated `n_distinct=199418`, a potentially consequential estimate for page-level joins. Its accuracy was not established; avoid assuming that the page table's row count equals the number of pages represented in revision. Most frozen base-table statistics date to May–July; age alone does not make statistics stale for an immutable dataset. Actor statistics were refreshed 10 October; `analysis.rfpp_request` has an explicit analyze recorded by the repair. No invalid/not-ready index was found, and no immediate freeze-age emergency is indicated by the largest observed user-table XID age (about 59.9 million).

Cumulative `pg_stat_database` counters show four deadlocks and approximately 20 TiB temporary bytes across 10,296,297 temp files, with `stats_reset` NULL. They do not establish a current incident or identify individual expensive queries. No other active transaction was seen in the follow-up activity snapshot, only an idle editor connection. Recommended action: use representative EXPLAIN plans and workload measurements to select any per-column statistics targets or indexes; record statistics epochs, temp-space trends, and long transactions. Avoid blindly analyzing all billion-row relations or tuning global memory from historical cumulative counters.

## Strengths and design choices

- Every public base table/partition inspected has a primary key. All 36 public indexes are marked valid and ready. A catalog-wide structural duplicate-index comparison found no exact duplicates. This is not a physical index-corruption test and does not prove every index is useful.
- Revision has page/time/actor, actor/time, parent, and ID indexes. Logging has actor, namespace/title, type/time, and JSON parameter indexes. Tags have revision, log, and tag ID indexes. These support the documented main join paths without adding speculative indexes.
- `actor_user_idx` overlaps the leading column of the unique `(actor_user, actor_name)` index but is a smaller partial index. It is not an exact duplicate; measure workloads and cache benefit before removing it.
- The large text payload is physically separated from revision metadata and range-partitioned at revision ID 1,000,000,000. Both partition PKs and their revision FKs are valid; the zero-byte parent size is normal because rows and indexes are held in the children. Range partitioning supports ID pruning and storage placement; repartitioning further is not automatically justified.
- Existing relation views intentionally preserve unmatched historical records; this is preferable to silently losing observations via inner joins. Protection titles need not correspond to existing pages, so absence of a conventional page FK is an appropriate domain choice.
- Page checksums are enabled and the database statistics report zero checksum failures. This only reports observed failures; it does not certify all unread storage or demonstrate recovery readiness. Backup verification and restore testing were outside this read-only audit.

## Recommended order

1. Resolve/document the failed migration's residual FK and preserve both failure causes; quantify snapshot link gaps without deleting evidence.
2. Add storage headroom monitoring and explicit tablespace placement; design any major relocation with per-volume capacity accounting.
3. Publish linkage and encoding contracts alongside analysis provenance, then audit sample attrition at each join.
4. Use measured workload plans and bounded integrity probes to choose targeted maintenance. Schedule any full revision/text completeness scan and recovery test as separate operations with resource budgets.

The audit establishes specific structural gaps and operational risks, while recognizing useful existing indexes, validated actor/text links, and intentional snapshot-oriented design. It does not certify the database as fully consistent, fully complete, or research-ready for every estimand.
