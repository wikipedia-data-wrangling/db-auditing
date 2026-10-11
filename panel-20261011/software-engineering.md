# Software-engineering audit — 11 October 2026

Scope: source inspection of ingestion, validation, migrations, and analytical caching; bounded live read-only checks against `wiki20260401`, port 5434. No base-table scan, source modification, migration, freeze script, loader, or destructive test was executed. No applicable ancestor AGENTS.md was found. File references below are relative to the workspace root.

The recent RFPP repair has strong scoped recovery controls and passes its regression suite. The wider build and test system does not yet enforce comparable isolation, atomicity, or version consistency. The most urgent fixes are isolating ingestion tests from production and preventing mixed-generation analytical inputs.

| ID | Severity | Finding | Evidence status |
|---|---|---|---|
| SE-1 | High | Ingestion test can delete real production revisions | Confirmed code path; historical execution/damage not established |
| SE-2 | High | Existing analytical caches bypass invalidation and version checks | Confirmed source and live unresolved registry |
| SE-3 | High | Standard RFPP rebuild is destructive and non-atomic | Confirmed source; no failed rebuild induced |
| SE-4 | Medium | Freeze validation strips trailing newlines and can report completion without validation | Confirmed code and local reproduction |
| SE-5 | Medium | Duplicate ingestion masks conflicting payloads and overstates inserted counts | Confirmed behavior; differing duplicate payloads not established |
| SE-6 | Medium | Reproduction identity omits working-tree content and validation status | Confirmed source; recoverability not fully audited |

## SE-1 — Production-writing integration test

`official-dump/load_pages_meta_history_xml.py:71` hard-codes `PG_SERVICE = "service=wiki"`. `official-dump/test_load_pages_meta_history_xml.py:133` connects to it, inserts revision 9992 with `ON CONFLICT DO NOTHING`, and commits. Lines 147–157 drop `revision_text_rev_id_fkey` and delete existing text for IDs 9990, 9999, and 9992. Lines 191–207 delete those texts and revision 9992, then recreate the FK and commit. The entrypoint invokes this test at line 262.

A pre-existing revision is not distinguished from a fixture: skipping its insertion does not prevent its later deletion. The dropped FK and committed cleanup also make interruption unsafe. Other FKs may make deletion fail, but cannot be relied upon to isolate the test or restore already committed text deletions.

Recommendation: require an explicit disposable test database, assert its identity against an allowlist, create isolated fixture tables/schema, and deny the test role any write access to production. Preserve existing data by construction rather than cleanup. Add a negative test proving the runner refuses `wiki20260401`. Do not run this test to verify the finding against production.

## SE-2 — Mixed analytical generations remain consumable

Live query evidence lists 21 `analysis.rfpp_intent_v2_invalidations` rows, all `review_or_rebuild`. Examples: `analysis.sample_request_treated` has 1,751 direct changed-row intersections; `analysis.sample_page_full` has 1,352. These are direct intersections, not distinct requests across all tables or a bound on propagated impact.

`20261001/wpp-analysis/src/io.jl:65–74` chooses a cache solely by filename existence. It does not compare SQL, database generation, parser signature, source table generations, or invalidation status. Refresh at lines 69–72 writes directly to the active path. `scripts/95_snapshots.jl:18–25` refreshes sequentially; interruption can leave different generations side by side. The direct RFPP snapshot has a separately documented guarded refresh, but the ordinary reader cannot establish compatibility with old y3/topic/sample inputs.

Consequences: rerunning estimation can silently mix repaired intent with legacy eligibility and outcomes; changed SQL can continue returning an older cached result. A refresh failure can also leave an incomplete active cache, depending on writer behavior.

Recommendation: issue a dataset-generation manifest containing query/source hashes, parser signature, source snapshot identifiers, and dependencies. Reject incompatible or invalidated inputs before analysis. Write verified temporary artifacts and atomically publish an entire compatible generation. Rebuild eligibility, samples, panels, and estimates in dependency order; preserving old generations supports comparisons.

## SE-3 — Standard rebuild lacks transaction protection

`20261001/wpp-analysis/sql/04_rfpp_request_extend.sql:15–65` drops and re-adds 24 derived columns, followed by independent UPDATE and temporary-table steps. The recommended invocation at line 6 has `ON_ERROR_STOP`, but neither the file nor the invocation starts a encompassing transaction (`-1` is absent). An error after the initial committed ALTER therefore leaves incomplete derived state. A dependency on a dropped column can instead stop the rebuild before it starts. “Idempotent” at line 4 does not provide atomic recovery.

The targeted repair is stronger: `db-auditing/apply_rfpp_intent_v2.sql:20–37` takes a transaction lock and checks stage signatures and source hashes, and the rollback guards against overwriting subsequent edits. That mechanism does not wrap the ordinary SQL04 rebuild.

Recommendation: build and validate a new derived generation before transactional publication, or wrap the supported SQL04 invocation in one transaction after assessing lock duration. Set `ON_ERROR_STOP` inside the driver and add a disposable-database failure-injection test verifying that interruption leaves the old complete generation usable. Do not test failure by running the destructive driver on this live database.

## SE-4 — Freeze validation can give misleading results

`official-dump/freeze_phase3.sh:313–335` captures API content in shell command substitution, which removes trailing newline bytes, then hashes it against the full stored bytes. A correct revision ending in newline will therefore appear different. Local reproduction in `software-engineering-newline-reproduction.txt` produces SHA-1 `6bfa09d82ce3e898ad4641ae13dd4fdb9cf0d76b` for `line\n`, versus `264f39cab871e4cfd65b3a002f7255888bb5ed97` after substitution. Empty valid content is also rejected at line 318. Suppression/access changes are classified as mismatches at lines 307–310, although they do not themselves prove corruption.

Separately, API failures set `api_ok=0` at lines 273–301 and bypass the final validation block at line 347; line 360 still prints “Phase 3 freeze complete.” The manifest is appended before the check (lines 210–249). This may be intentional availability policy, but the artifact does not encode a machine-readable incomplete validation state.

Recommendation: decode and hash exact UTF-8 bytes in Python or binary-safe files, with fixtures for trailing newlines and empty text. Record verified, unavailable, suppressed, and mismatched results separately. Publish the final manifest only after checks, with a durable `validation_status`; distinguish captured artifacts from validated freeze. No claim is made that a past freeze failed or that production text is corrupt.

## SE-5 — Idempotent ingestion does not establish duplicate consistency

`official-dump/load_pages_meta_history_xml.py:327–330` uses `SELECT DISTINCT ON (rev_id)` without an ordering or equal-payload assertion, then `ON CONFLICT (rev_id) DO NOTHING`. This tolerates known overlapping dump boundaries and supports restarts, but if two records with the same ID differ, the winner depends on batch/worker arrival and differing bytes are silently ignored. Such differing records have not been demonstrated in this audit.

The loader logs `stats.revisions_loaded` at lines 420–426. That counter is parsed rows, not inserted rows: the existing test explicitly says so at `official-dump/test_load_pages_meta_history_xml.py:166–168`. Therefore it cannot reconcile actual database insertions, overlap, or skipped matches.

Recommendation: count parsed, filtered, inserted, equal-duplicate, and conflicting-duplicate records separately; compare byte/hash equality on collisions and quarantine differences. Persist a per-file completion ledger with input checksum, loader version, counts, and durable commit status, including crash/restart tests in a disposable database.

## SE-6 — Freeze provenance identifies HEAD rather than executed source

`official-dump/freeze_phase3.sh:213–222` records `git rev-parse HEAD` only. It does not establish a clean tree or record a patch/content hash. A dirty loader can therefore produce a manifest pointing to different source content. The analysis checkout is currently dirty, including modified SQL04 and untracked shared parser files; this is not itself an error, and existing work was preserved. It demonstrates why commit identity alone is insufficient for the current workspace. The recent RFPP repair does preserve a source patch and hashes, which is a useful pattern.

The freeze produces a schema-only dump (`freeze_phase3.sh:165–170`) and permits missing source archives (lines 205–207). This is explicitly documented rather than a hidden full-backup promise. However, schema-only output cannot establish recoverability without verified retained inputs, transformations, and restoration procedures. This audit did not inventory every source archive or perform a restore.

Recommendation: record hashes of executed code and environment/dependencies, plus dirty patch or clean commit requirement; keep an immutable input manifest with checksum and retrievable location. Run a scoped restore/rebuild drill on representative data before claiming reproducibility or disaster recovery. Record validation outcomes in the same manifest.

## Positive findings and verification

The live run is `applied`, timestamp `2026-10-10 22:04:16.173196+01`; current parser function signature matches the recorded signature `20650d4ec484afa2739613b3155b45aa`. IDs 737, 127462, 144377, and 154614 have the expected repaired actions/tiers and version `rfpp-intent-v2.0.0`. Seven parser test methods, including historical fixtures, uncertainty, transitions, and SQL_ASCII Unicode preservation, passed in 0.160 seconds under enforced read-only connections and 20-second statement timeout.

The repair migration and rollback preserve original rows, compare complete row hashes, reject stale stages, and retain audit evidence. The purpose-built cache repair writes a temporary file, validates every exported classification against stage, preserves the original by hard link, and atomically replaces the active path (`db-auditing/refresh_rfpp_intent_cache.py:19–37`). These controls should become standard pipeline behavior.

Evidence: `software-engineering-queries.sql`, `software-engineering-db-evidence.txt`, `software-engineering-parser-tests.txt`, and `software-engineering-newline-reproduction.txt` in this directory. The database reports `SQL_ASCII`; its wider implications belong to the PostgreSQL specialist's assessment. Full parser accuracy, historical recovery success, and actual downstream coefficient changes were not established by this software review.
