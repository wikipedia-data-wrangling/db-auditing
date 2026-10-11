# db-auditing

This workspace assesses the PostgreSQL database built from the **April 2026
English Wikipedia dump (`20260401`)** and the design choices made when collecting,
loading, linking, and transforming its data. The aim is to establish what the
database represents, which questions it can support, and where corrections or
additional evidence are needed.

The target is **`wiki20260401` on PostgreSQL 18, port 5434**. Connect through
the configured libpq service:

```sh
psql service=wiki
```

The database also contains API collections and derived analysis tables with
their own collection dates. The April dump date must not be treated as the
observation date of every record or as the coverage boundary of every source.

## What we assess

- **Coverage and provenance:** source files, collection dates, namespace and
  time coverage, retained/excluded records, and differences between the live
  database and cached exports.
- **Schema and relationships:** identifiers, primary/foreign keys, missing
  references, user-versus-actor identity, page moves/deletions, and whether
  joins preserve the intended observational unit.
- **Ingestion and storage choices:** SQL/XML/API reconciliation, byte-preserving
  types and encoding, timestamp handling, actor synthesis, partitioning,
  tablespaces, and indexes appropriate to the intended queries.
- **Derived classifications:** request intent, administrative outcomes, applied
  protection levels, protection episodes, missing values, ambiguity, and the
  evidence behind parsing and matching rules.
- **Consequences for analysis:** sample selection, request-to-log matches,
  eligibility rules, comparison groups, and propagation of corrections into
  exported data and downstream results.

Assessment covers both implementation correctness and the assumptions embodied
in a design choice. A query that runs successfully does not establish that its
classification, linkage, or interpretation is valid.

## Protection data: distinctions to preserve

| Object | What it represents |
| --- | --- |
| `public.page_restrictions` | Protection settings on existing pages at the dump snapshot |
| `public.protected_titles` | Creation protection for nonexistent page titles |
| `public.logging` | Historical administrative actions, including protection actions |
| `analysis.protect_event` | Parsed protection events and their reconstructed parameters |
| `analysis.protection_episode` | Reconstructed periods of protection |
| `analysis.rfpp_request` | Protection requests, inferred intent, responses, and matched actions |

Requested protection, the administrative decision, and the protection actually
applied are separate measurements. Disagreement between them can be informative;
it must not automatically be resolved by copying one classification into another.
Missing references and uncertain request chronology likewise need explicit treatment.

## Audit workflow and record

Each audit should identify its question and the relevant design choice, inspect
the implementation, reproduce the finding with bounded read-only diagnostics,
and distinguish confirmed defects from candidate cases and unresolved assumptions.
Record the database/source version, exact population filters, timestamps, stable
identities, source hashes where useful, queries, results, and limitations.

Repairs should have a reproducible test corpus and an old/new record of changes.
Track which derived tables, exports, and analyses need refreshing; preserve raw
source evidence and prior versions so that the change can be reviewed and reversed.
Reports and GitHub issues should state what was inspected, tested, changed, and
left unresolved. An audit is not complete merely because a symptom disappears.

## Current audit

The [four-specialist audit of 11 October 2026](panel-20261011/panel-audit.org)
assesses software engineering, PostgreSQL, computational social science, and
Wikipedia semantics. It includes measured findings, reproducible read-only
queries, a [prioritized action register](panel-20261011/findings.csv), and
source/evidence provenance. No database changes were made during that audit.

The [15 follow-up issues](panel-20261011/github-issues/index.org) are filed.
**All fixes are deferred until Tuesday, 13 October 2026 (Europe/London),**
at the user’s request; no automatic execution is scheduled.

## RFPP repair

[Issue #1: RFPP requested-protection classification](https://github.com/wikipedia-data-wrangling/db-auditing/issues/1)
examines duration language misclassified as extended confirmed protection and
explicit downgrade requests misclassified as protection increases.

The root-cause parser fix is applied to all 217,554 requests, and the direct
178,110-row request export is refreshed. Raw inputs and prior versions are
preserved. Frozen downstream samples and estimates still require a controlled
rebuild. Issue #1 was closed at the user’s request; closure does not complete
those dependencies or independent validation.

- [Diagnostic SQL](ecp-label-diagnostics.sql): read-only queries, a deterministic
  reproducer, historical fixtures, and full-population candidate queues.
- [Evidence and repair specification](ecp-label-issue-report.org): source analysis,
  snapshot provenance, confirmed examples, limitations, regression cases, and
  downstream dependencies to audit.
- [Initial live audit](issue-1-audit-log.org): historical reproduction before repair.
- [Root-cause repair log](issue-1-repair-log.org): shared parser implementation,
  scoped database migration, validation, rollback, and downstream invalidations.
- [Regression tests](test_rfpp_intent_v2.py) and [repair report exporter](report_rfpp_intent_v2.py):
  semantic fixtures, confusion tables, changed identities, and parser provenance.
- [Audit runner](audit_issue_1.py): repeatable read-only queries with structured
  results, source hashes, and fixture checks.

The original report describes a historical export; consult subsequent audit logs
and the issue discussion for live validation and repair status.

The collection implementation lives in the sibling `official-dump` and
`fetch-protection-events` repositories. The analysis implementation is in
`20261001/wpp-analysis`. This repository holds the assessment evidence and records
of the design choices being reviewed.
