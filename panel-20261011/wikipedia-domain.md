# Wikipedia-domain audit — wiki20260401

Reviewed 11 October 2026. Read-only review of shared `inventory-results.json`, `wikipedia-results.json`, source SQL/Python, and two bounded supplementary queries in `wikipedia-extra-results.json`. Counts describe these query snapshots, not a transactionally frozen database. No database or pipeline changes made. Severity indicates consequences for the intended research interpretation, not that all records are invalid.

## W1 — High: the declared episode cutoff is not enforced

**Confirmed implementation defect.** SQL03 declares `2026-04-01 00:00:00+00` at line 27. Its `rows_` and `op` inputs (lines 56–81) do not filter event timestamps; the cutoff is consulted only when labeling an expiry (lines 125–141). The resulting 1,004,247 episodes include **203 starts at or after the declared cutoff**, **37 actual ends after it**, and a latest start of **2026-04-02 17:22:43 UTC** (`episode_coverage`). Therefore this is not an April 1 as-of episode table under its own documented definition.

Coverage is also mixed across inputs: protect events reach April 2, API protection metadata reaches May 6, and RFPP requests reach September 30. **8,463 of 217,554 RFPP requests are dated at or after April 1** (`rfpp_coverage`, `event_coverage`, `api_coverage`). A database name/dump date is not a shared observation horizon. This does not make later RFPP records bad records; it makes event absence after coverage ends unsuitable evidence of no treatment. Likewise an April 2 record in a nominal April dump need not itself be an upstream defect: export timing must be established.

A bounded follow-up (`wikipedia-coverage-results.json`) finds **8,380 requests strictly after the last observed protect_event timestamp**. Another **100 decisions at or before that timestamp have their decision + 48-hour matching-window end beyond it** (97 requests have request + 48 hours beyond it). These are coverage diagnostics, not counts of false untreated assignments. The last event timestamp is an observed boundary, not proof of uninterrupted log completeness up to that instant. Stable events stop earlier still.

**Remedy:** define per-source coverage and an explicit analysis horizon; restrict replay inputs and boundaries consistently; right-censor at that horizon while retaining scheduled expiry separately. Add assertions that starts precede the analysis cutoff and observed end times do not exceed it. Require outcome follow-up coverage for RFPP cohorts, rather than labeling uncovered follow-up as untreated.

## W2 — High: 133 reconstructed spells have impossible negative observed duration

**Confirmed derived-data defect; original expiry cause not yet established.** All 133 rows with `actual_end_ts < start_ts` also have a scheduled expiry before their start (`episode_coverage`). Their opening-event level sources are **90 raw / 43 comment** (`negative_expiry_sources`). SQL03 copies the expiry directly to the actual end when it considers it expired, with no lower-bound validation.

Examples (`negative_episode_examples`): episode 27360, opening log 6986170, starts **2007-02-10 16:54:24** but ends **2006-02-12 00:00:00**. Episode 1752 starts 12 seconds after the assigned end; episode 36305 starts 48 seconds after it. Minute-resolution historical text is a plausible explanation for the short discrepancies, but has not been proven for these records; it cannot explain every anomaly. These are not valid positive-duration exposures and can contaminate duration-based eligibility, thresholds, and exposure summaries.

**Remedy:** preserve the raw expiry, inspect original log details, classify precision/truncation versus malformed or stale expiry, and quarantine uncertain intervals from duration-sensitive analyses. Do not silently clamp every end to its start. Add an explicit interval-validity flag and a validated-table constraint after correction. The low overall frequency does not establish negligible influence on a narrowly selected duration sample.

## W3 — High for edit-protection comparisons: requested_level merges action type with access tier

**Confirmed lossy construct design.** `04a_rfpp_intent_parser.sql` puts `semi`, `ecp`, `full`, `template`, `pc`, `salt`, `move`, and `upload` in one target array. These do not form one scale: edit/move/create/upload are protected actions; sysop/extendedconfirmed/autoconfirmed are access requirements. MediaWiki stores those separately as `pr_type` and `pr_level`. [MediaWiki page_restrictions specification](https://www.mediawiki.org/wiki/Manual:Page_restrictions_table)

Live examples (`request_type_label_examples`):

| RFPP ID | Label | Stored action / level | Information that must remain separate |
|---|---|---|---|
| 33645 | create indefinite full protection | increase / full | creation action; sysop requirement |
| 57453 | temporary move full protection | increase / full | move action; sysop requirement |
| 176990 | downgrade edit and move protections from administrator to template-editor access | decrease / template | two requested actions; origin and destination access |
| 202386 | indefinitely creation extended confirmed protection | increase / ecp | creation action; extendedconfirmed requirement |
| 106324 | removal of salting | decrease / salt | remove a creation restriction; salt is the restriction being removed, not necessarily a destination access level |

This demonstrates that selecting `requested_level='ecp'` or `'full'` alone does not identify requests to restrict editing of existing pages. It does **not** establish the population-wide contamination rate or invalidate a study that independently screens action type. `04c_rfpp_request_match.sql` also selects one primary applied restriction in edit > stable > create > move order; multi-action log rows can lose the component relevant to a particular request.

**Remedy:** represent requested restrictions as an array or child table with action type, source access, destination access, operation, duration, and evidence; retain unknowns and alternatives. Match requested components to observed components. Validate creation, move, combined-action and removal fixtures alongside existing ECP/semi transition tests before redefining analytical cohorts.

## W4 — High for claims about original intent: RFPP source revision provenance is discarded

**Confirmed provenance gap; alteration rate unknown.** `fetch-protection-events/fetch_rfpp.py:348–400` fetches current archive wikitext, asks for `content|timestamp|ids`, but retains only `slot['content']`. `load_rfpp_postgres.py:137–149` stores archive title and collection time, not the source archive revision ID/timestamp. The current collection window is September 30, 2026; request signatures span 2005–2026. The parser has 69 records flagged `chronology_uncertain`, but absence of a visible strike-through is not proof that a request label has never been changed.

**Inference:** request signature time and collection time do not recover the exact text visible when an administrator decided. This matters when intent serves as a pre-decision covariate or subgroup definition. It is not evidence that all archived requests were altered, nor that the 69 flagged cases exhaust the uncertainty.

**Remedy:** retain source revision ID, revision timestamp, archive content hash and parser version for reproducibility; for causal timing claims, recover/request-label revisions preceding the decision, or clearly designate current-archive text as retrospective evidence and conduct sensitivity analyses. Retaining an archive revision ID alone improves reproducibility but does not resolve original-intent chronology.

## W5 — Medium, potentially High for historical page panels: resolution provenance must enter analysis

The event table resolves **526,808 logs by api_logpage**, **172,033 by api_pageid**, **28,825 by title**, with **144,032 logs unresolved** (`event_resolution`). The API contains **63,745 rows with differing non-null api_logpage and api_pageid** (`api_coverage`). These differences are not themselves errors. SQL02 uses API log identity first and current API page ID next, then associated revision, then a current dump namespace/title lookup (lines 105–145).

**Inference:** present-day title matches and API lookups need not identify the historical page incarnation after moves, deletion or recreation. Unresolved creation protection is also semantically different from losing an ordinary existing article: protected titles concern non-existent pages, so there may be no page row to reference. A forced FK from all protected titles to `page` would encode the wrong entity model. [MediaWiki protected_titles specification](https://www.mediawiki.org/wiki/Manual:Protected_titles_table)

**Remedy:** retain title identity and page incarnation explicitly; compare findings across resolution methods; review move/deletion/recreation histories for relevant ambiguous cases; quantify exclusions by era, restriction action and namespace. Avoid treating resolution-method counts as measured linkage-error rates. Preserve legitimate absent page references for title protections.

## W6 — Medium interpretive boundary: technical protections do not exhaust policy exposure

The snapshot tables record technical settings and derived events reconstruct their changes; they do not by themselves enumerate all policy obligations. Extended-confirmed topic restrictions can cover edits across a topic and be enforced without technical ECP, including through reverts, blocks or other mechanisms. Consequently, no `extendedconfirmed` protection row does not establish absence of that policy exposure. [Arbitration Committee procedures, extended confirmed restriction](https://en.wikipedia.org/wiki/Wikipedia:Arbitration_Committee/Procedures#Extended_confirmed_restriction)

Pending changes permits submissions whose public visibility awaits review; it is not equivalent to an edit-access barrier. SQL03 correctly separates its `stable` event family. Retain that distinction in analysis rather than treating stable/autoconfirmed as the same treatment as edit/autoconfirmed. [Wikipedia protection policy, pending changes](https://en.wikipedia.org/wiki/Wikipedia:Protection_policy#Pending_changes_protection)

There are **17,708 opening rows / 8,854 logs labeled assumed_full** and **633 unparsed log rows** (`event_uncertainty`). These uncertainty markers are useful design choices, but inferred early full protection must not silently become equally certain as structured event details. The zero current `expiry_unknown` count establishes a parser result, not historical completeness. Snapshot cascade settings (38 edit and 29 move rows) also imply that direct restriction-row membership alone may not enumerate every indirectly affected page; the MediaWiki specification documents transclusion-based cascade effects.

**Remedy:** name the measured construct precisely (requested technical restriction, implemented technical restriction, or broader policy exposure); version historical policy sources if coding policy exposure; preserve method/uncertainty strata and compare robust subsets. The current policy documents consulted on 11 October 2026 establish these conceptual distinctions, not that every rule had identical wording throughout 2005–2026.

## Supported strengths and limits

The event schema already separates restriction action from access level, preserves resolution and level-source provenance, and distinguishes stable from ordinary protection. The intent repair preserves raw evidence and parser status. These are sound foundations. The confirmed replay boundary/interval defects and request construct/provenance limitations require resolution before claiming a uniformly timed, historically identified treatment panel. This review did not estimate a global semantic error rate, reconstruct deleted histories, certify archive chronology, or determine causal validity of a particular final model.
