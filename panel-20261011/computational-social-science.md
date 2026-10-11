# Computational social-science audit — 11 October 2026

**Verdict:** the repaired RFPP source is suitable for further audited descriptive work, but the existing analytical products do not support an unqualified causal interpretation. Several problems are confirmed implementation/data inconsistencies; others are identification assumptions that this audit cannot establish. No estimates or database objects were changed.

Scope: source review of the sampling, request/episode, export, IV, panel, expiry and spillover pipelines; live bounded queries in `wiki20260401`, port 5434, starting 08:25 UTC. All database queries used `BEGIN READ ONLY` and a 30-second statement timeout. Evidence is in `social-science-queries.sql`, `social-science-followup.sql`, `social-science-dependence.sql` and their `*-results.txt` siblings. SQL source references below are relative to `20261001/wpp-analysis/` unless stated otherwise. Current working-tree source was reviewed; it is not necessarily the exact source used to create every frozen output.

## Findings

### CSS-01 — High: repaired requests coexist with incompatible frozen sample populations

**Confirmed.** All 21 entries in `analysis.rfpp_intent_v2_invalidations` retain `review_or_rebuild`. Among the 8,000 granted/denied rows in `sample_page_full`, 1,304 no longer meet the current `requested_action='increase'` criterion (889 denied, 415 granted), and 216 retain tiers different from the current source (139 denied, 77 granted). In `sample_request_treated`, 1,644 of 10,000 no longer meet that criterion and 342 retain different tiers. Counts overlap; no-longer-increase includes conservative unknown classifications, not necessarily positive evidence of a different intention.

SQL20 rebuilds the request frame but reuses nonempty persisted stages B/C/D (`sql/20_sample_page.sql:11`, `:153`). A routine rerun can therefore combine a new frame and duration medians with old sampled IDs/tiers. Snapshot loading similarly uses an existing file without checking its source/parser version (`src/io.jl:65`). The direct RFPP Parquet was refreshed by the repair, so a new IV run can combine corrected instrument data with old outcomes/samples (`scripts/40_quality_y3.jl:213`).

**Impact:** the declared target population, tier-specific outcomes, pseudo-expiries and instrument strata can refer to different request definitions. Old results are not automatically invalid numerically, but are not results for the repaired population.

**Action:** preserve the old run, rebuild eligibility, sampled requests/controls, medians, panels and outcomes in dependency order; require a source/parser/run fingerprint to match before reusing stages or joining caches. Report old/new sample membership and estimates. Treat `direct_changed_rows` as dependency intersections, not a unique-person count or complete impact bound.

### CSS-02 — High: quality-sampling source still uses dump-title identity

**Confirmed source/live inconsistency.** SQL42 samples and deduplicates by `rfpp_request.page_id` (`sql/42_sample_request_treated.sql:21`) rather than the repaired historical-match identity used by SQL20 (`sql/20_sample_page.sql:120`). In the current 10,000-row SQL42 sample, 742 page IDs differ from `page_id_match`; 1,468 requests carry the source redirect flag. Neither number proves all those rows are incorrectly resolved: `page_id_match` itself uses heuristic matching and requires validation.

SQL41 takes its article identity directly from its chosen source (`sql/41_quality_cutoff.sql:58`) and separately resolves talk-page identity by current title (`:71`). The currently loaded quality table must be assessed on `article_page_id`, not `page_id`, because talk cutoffs intentionally use a different page ID. The current 56,333 quality-cutoff rows have **zero** differences between `article_page_id` and the source `page_id_match`; that is a positive live check. An identity difference in SQL42 must not be automatically attributed to the current SQL41 materialization, which can be built from a different sample.

**Impact:** outcomes can describe a redirect, recreated title or different historical object; selection and first-request deduplication can also change.

**Action:** adopt an explicit event-time article identity with provenance/confidence throughout SQL42/41 and exports; review moved/recreated pages, and rebuild only after recording the resolved identity map. Report unresolved identities separately rather than treating them as untreated or zero outcomes.

### CSS-03 — High: historical eligible-editor measures are inconsistent across paths

**Confirmed code defect.** `export_arrow.py:488` exports `is_sysop = is_sysop_ever`. `scripts/61_expiry_rd.jl:44` then returns class 4 whenever that field is true, ignoring the time argument. That helper defines the pre-spell ineligible returner set (`:63`). An editor who acquired admin rights after the spell is therefore treated as already eligible under full protection. By contrast, event export applies start/end dates (`export_arrow.py:293`). The RD helper also does not carry the removal handling used for extended-confirmed status in event export.

**Confirmed representational limitation.** SQL12 collapses group intervals to min start/max end/current status (`sql/12_editor_state.sql:23`). Live intervals contain multiple records for 178 sysop, 196 extended-confirmed and 44 bot user IDs. Multiple intervals alone do not prove every case has a real gap; the compression cannot represent a genuine revoke/regrant gap when one exists.

**Action:** use a shared as-of interval lookup for all eligibility paths, retain unknown start dates as uncertainty, and add tests for pre-promotion, revocation and regrant. Quantify affected edits/returners using existing sampled events; this audit established the defect but did not estimate its outcome impact. The export also maps template/full eligibility to sysop only (`export_arrow.py:309`), which needs the domain specialist's policy validation.

### CSS-04 — High: missing request intent creates large, time-varying selection

**Confirmed live pattern.** In mainspace granted/denied requests, unknown action is 251/13,815 in 2020 (1.8%), 2,642/15,990 in 2021 (16.5%), 5,558/13,407 in 2022 (41.5%), and 5,043/13,969 in 2025 (36.1%). SQL20 and script30 exclude these via `requested_action='increase'`. This is appropriate abstention by the conservative parser, but it changes inclusion sharply across calendar time. No blinded population error-rate validation has been supplied; regression fixtures and diagnostic samples establish specific behavior, not general accuracy.

**Action:** audit stratified samples by year, archive format, outcome and parser status with independent annotation; publish inclusion/missingness flows and sensitivity analyses. Do not impute unknown intent from the later grant or protection tier. Preserve alternatives and chronology uncertainty as distinct states.

### CSS-05 — High: first-stage strength is not an assignment-validity result

**Confirmed pipeline gap.** Script30 requests six possible pre-treatment covariates (`scripts/30_leniency_iv.jl:29`), but none exists on live `analysis.rfpp_request` (query result: zero columns). Missing columns are silently excluded (`:104`), and the balance test is skipped when that list is empty (`src/causal.jl:132`). The stored `first_stage_tests.csv` has a large first-stage F, but no balance block; every row is marked `placeholder_outcome=true`. `validity=false` is the default. The labeling is a useful safeguard and must survive summaries.

The same request-frame code assigns treatment as `outcome == 'granted'` (`scripts/30_leniency_iv.jl:79`) and does not apply the outcome-support cutoff or substitute-remedy filter used for page-window sampling. Before its minimum-admin decision filter, the current qualifying source population contains 132,505 rows, including 3,501 after the April dump cutoff, 8,931 substitute remedies and 3,624 without a matched page. These are not necessarily invalid observations for a standalone decision-rate instrument; their use requires an explicit transport/measurement rationale.

**Unverified assumptions:** conditional administrator assignment, exclusion from outcomes through other administrator actions, monotonicity and stable instrument behavior across eras. The data and code reviewed do not prove these assumptions. A strong grant-prediction F cannot do so.

**Action:** materialize the promised pre-decision covariates, test assignment balance and overlap, specify the instrument population and calendar support, and distinguish the effect of a decision from the effect of applied protection. Keep placeholder and code-path results out of substantive effect claims. Pre-register how sparse strata and failed diagnostics are handled; script50 can fall back as far as no strata (`scripts/50_panel_causal.jl:105`) and appropriately labels those outputs code-path checks.

### CSS-06 — High: granted/denied contrasts are not clean protected/unprotected contrasts

**Confirmed live data.** For 2016–2024 mainspace increase requests with granted/denied outcomes, 1,923/20,624 denied requests have a matched treatment log, and 4,436/20,624 have an opening event within 30 days. Conversely, 80,612/82,629 grants have `treated_by_log=true`. The matched-log indicator is a heuristic association, not independently adjudicated ground truth. In frozen `sample_page_full`, 669/4,000 denied requests carry the 30-day protection flag.

**Impact:** assigning treatment from the administrative response estimates a decision-related contrast under additional assumptions, not automatically the effect of protection exposure. Flags alone do not remove crossover. Dropping crossovers after observing them would itself introduce post-decision selection.

**Action:** declare an intention-to-treat-style decision estimand or explicitly model applied protection as time-varying exposure; report crossover and alternative windows. Separately validate log matching against request chronology and pre-existing state. Do not recode a denied request as a grant merely because an event is nearby.

### CSS-07 — High: outcome windows and eligibility vary with the treatment arm

**Confirmed.** SQL20 assigns denied requests a median granted duration by requested tier/year, with fallbacks (`sql/20_sample_page.sql:375`). Granted requests use their own scheduled expiry. Export uses 30 pre-days and a variable during-period capped at pull end (`export_arrow.py:379`). Script50 regresses raw `log1p(n_edits)` without a duration adjustment (`scripts/50_panel_causal.jl:62`). Live full-sample during intervals have median 7 days in each arm, but range from about 0.083 to 174 days for grants/controls, versus 3–14 days for denials. Counts over these intervals are not comparable activity rates.

Unknown/non-edit denied tiers become semi eligibility (`sql/20_sample_page.sql:400`): 1,049/4,000 denied windows and 1,028/7,908 controls are marked `default_semi`. Thus eligible-editor outcomes use observed applied level for grants and requested or invented default level for denials. This is an arm-dependent measurement definition, not merely a missing covariate.

There are 118 granted windows with no expiry anchor and another 284 whose expiry+84 days exceeds the revision pull; their inherited controls share these limitations. Export omits uncovered post periods; script50 drops units with undefined outcomes to form a balanced two-period sample (`scripts/50_panel_causal.jl:73`). No-edit windows can therefore disappear from concentration/share outcomes in a treatment-dependent way.

**Action:** make fixed decision-clock horizons the primary comparison; report rates/exposure lengths and a prespecified treatment-duration estimand separately. Do not treat pseudo-expiry as an observed release. Define eligible subpopulations consistently across arms and report unknown tiers. Tabulate per-outcome retention, zero-edit status and expiry coverage before estimation.

### CSS-08 — High design risk: control selection uses information after historical treatment

**Confirmed selection rule, unquantified bias.** The never-requested pool excludes every page appearing anywhere in the archive (`sql/20_sample_page.sql:110`, `:179`), so a 2013 control's eligibility can depend on a 2026 request. Matching uses dump-time page length and redirect status (`:165`, `:189`), which may be affected by intervening history. Candidates are also required to remain unprotected through the selected range (`:368`). These are deliberate design choices, not evidence of an as-of risk set.

Only 3,853/7,908 full controls match the pre-edit-count bucket (48.7%); mean pre-30-day edits are 16.89 controls, 36.93 denied and 54.72 granted. Means alone do not estimate confounding, but show a substantial support concern.

**Action:** define the target as persistent never-requested survivors if that is intentional. Otherwise build controls eligible as of the decision date, use pre-treatment length/redirect/exposure measurements, report overlap and balance after adjustment, and assess sensitivity to including later-requested pages. Historical graph-based spillovers similarly need a stated rationale when neighbours come from the current graph (`sql/README.md`, neighbour selection section).

### CSS-09 — Medium/high: shared-neighbour dependence is only partly handled

**Confirmed.** `neighbour_page_full` contains 62,565 window-neighbour rows but 56,599 distinct neighbour pages. 4,431 neighbours occur in more than one focal window, up to 11. The neighbour DR-DiD path clusters only by focal window (`scripts/70_spillover.jl:322`), whereas the exposure-model path explicitly has page clustering/network-HAC options (`:108`). Thus different paths address different dependence structures.

**Impact:** the same neighbour's outcomes may be repeated across windows, and shared focal shocks correlate different neighbours. Overlapping time intervals were not quantified here, so this audit does not claim a numerical standard-error bias.

**Action:** report unique pages, windows and overlap; compare focal-window and neighbour-page/multiway or dependency-aware inference. Use consistent units in tables; window-neighbour row count is not the count of independent pages. Main full sample has unique pages within each arm, which is a positive check.

### CSS-10 — Medium design limitation: expiry RD requires substantive time assumptions

**Confirmed safeguards:** the implementation uses scheduled rather than actual expiry, models actual unprotection for fuzzy outcomes, clusters by page, and requests donut/placebo analyses (`scripts/61_expiry_rd.jl:75`, `:113`). It excludes pre-spell days and has unequal support for short spells. These are useful checks.

**Unverified:** no concurrent time-varying shock or predictable return of editors at expiry, credible continuity for discrete daily outcomes, and appropriate composition as spell lengths vary. Finite-expiry-only estimates do not generalize automatically to indefinite protection. A placebo test cannot establish these assumptions on its own.

**Action:** label results as conditional on the scheduled-expiry design; inspect duration-specific support, calendar alignment, anticipation and concurrent actions. Compare symmetric support and common event-time windows, and publish diagnostic failures rather than just the successful coefficient rows.

## Positive controls and audit boundaries

The root-cause parser separates request text from administrative outcomes, records uncertainty and preserves raw text; the repair provides before/after evidence and reversible migration artifacts (`db-auditing/issue-1-repair-log.org`). SQL20 deliberately bounds outcome coverage before the April cutoff and deduplicates the request frame by matched page. Event export and expiry analyses distinguish actual protection from the response field. Several preliminary results are explicitly labeled placeholder/code-path checks. These controls should be preserved.

The domain reviewer independently reports episodes with negative durations and boundaries beyond the nominal April cutoff. See the Wikipedia specialist report and `wikipedia-results.json` for its exact scope and examples. Those defects require resolution before treating replayed episode exposure or scheduled-duration medians as validated. Different source horizons (April event material versus RFPP archives into September) also require explicit source-specific censoring; the nominal dump name is not a guarantee that every relation ends at the same instant.

This was an audit, not a full annotation exercise, causal reanalysis, raw-revision recount, or independent validation of page/log linkage. No magnitude or sign of causal bias is asserted from source inspection alone. Highest-priority work is to prevent mixed-version analysis, repair historical eligibility/identity inconsistencies, rebuild the declared sample, and make the treatment, time horizon and target population explicit before rerunning estimates.
