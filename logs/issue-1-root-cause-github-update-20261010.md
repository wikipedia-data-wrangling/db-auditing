The root-cause fix is now implemented in the analysis source and applied to `wiki20260401` (PostgreSQL 18, port 5434).

- SQL04 now calls one versioned, request-only intent parser. Bare **extended** is no longer ECP; explicit transitions use their destination and retain origin; alternatives/amended text retain uncertainty. Administrative response codes no longer determine request intent.
- Preserved all **217,554** requests and their raw text, identities, outcomes and unrelated derived fields. Full before-state snapshot, staged values, original/after hashes and old/new records are retained in PostgreSQL.
- **44,075** records changed legacy derived fields: **36,320** action changes, **13,712** tier changes, **269** matched-log-ID changes. Counts overlap and are **not confirmed error counts**. Many changes remove unsupported default classifications. Matching was recalculated only for changed-action IDs; applied levels still come from protection events.
- Seven regression methods with multiple subcases pass, including all ten historical fixtures. IDs 737/4219/5302/12914/30062 now target semi; 127462/144377 are decrease/semi; 154614 is increase/ECP; 91188 retains alternatives; 192925 retains chronology uncertainty.
- Transaction invariants and post-commit checks pass. The direct mainspace granted/denied Parquet was refreshed: **178,110** unique requests, zero intent-classification mismatches against the stage, original file preserved.

End-to-end export validation caught a Unicode normalization defect in my first implementation on this SQL_ASCII database. I executed the guarded rollback, verified exact original-row restoration, replaced multibyte `translate` with whole-sequence replacements, and added Unicode regression cases. All 217,554 final JSON records pass strict UTF-8 validation. The first attempt's evidence is archived; the final repair and valid export are now active.

**Remaining work:** 21 frozen analytical tables are explicitly registered for review/rebuild in `analysis.rfpp_intent_v2_invalidations`. Rebuild selection/eligibility and denied/control pseudo-expiry medians, sampled frames and dependent caches, then IV strata/models/reports. Existing estimates were not rerun. Keep this issue open for that work and independent human validation. The deterministic stratified sample is a diagnostic review, not a blinded accuracy study. Unsupported language, restriction-type/tier combinations and chronology remain review categories.

Local execution log: `db-auditing/issue-1-repair-log.org`.
Structured report: `db-auditing/logs/issue-1-repair-applied-20261010.json` (source hashes, strata, sample, fixtures, invalidations).
Full changed records: `db-auditing/logs/issue-1-changed-records-20261010.csv` (also `analysis.rfpp_intent_v2_changes`).
Rollback source: `db-auditing/rollback_rfpp_intent_v2.sql`; original rows: `analysis.rfpp_request_pre_intent_v2`.
These workspace artifacts are not yet repository commits. The complete reviewable analysis patch and migration are included below so the fix itself is available from the issue.

Final parse-status counts:

| status | n |
| --- | --- |
| explicit | 180833 |
| unspecified | 36125 |
| alternative | 347 |
| ambiguous | 169 |
| chronology_uncertain | 69 |
| edit_request | 11 |

<details>
<summary>Full old/new action confusion table</summary>

| old_action | new_action | n |
| --- | --- | --- |
| decrease | change | 1 |
| decrease | decrease | 2664 |
| decrease | increase | 131 |
| decrease | NULL | 1059 |
| edit | decrease | 12 |
| edit | edit | 10 |
| edit | increase | 2 |
| edit | NULL | 354 |
| increase | change | 12 |
| increase | decrease | 112 |
| increase | edit | 1 |
| increase | increase | 178560 |
| increase | NULL | 34636 |

</details>

<details>
<summary>Full old/new tier confusion table</summary>

| old_level | new_level | n |
| --- | --- | --- |
| ecp | ecp | 10902 |
| ecp | full | 7 |
| ecp | move | 1 |
| ecp | none | 1 |
| ecp | semi | 86 |
| ecp | NULL | 1377 |
| full | full | 8215 |
| full | none | 3 |
| full | semi | 4 |
| full | template | 1 |
| full | NULL | 260 |
| move | full | 2 |
| move | move | 1183 |
| move | none | 1 |
| move | template | 1 |
| move | NULL | 100 |
| other | ecp | 5 |
| other | full | 3 |
| other | none | 2311 |
| other | salt | 3827 |
| other | semi | 23 |
| other | upload | 5 |
| other | NULL | 2079 |
| pc | ecp | 2 |
| pc | full | 1 |
| pc | pc | 7633 |
| pc | semi | 8 |
| pc | NULL | 456 |
| salt | none | 2 |
| salt | salt | 86 |
| salt | NULL | 201 |
| semi | ecp | 4 |
| semi | full | 1 |
| semi | none | 37 |
| semi | pc | 3 |
| semi | semi | 145122 |
| semi | NULL | 2717 |
| template | full | 1 |
| template | semi | 1 |
| template | template | 1203 |
| template | upload | 1 |
| template | NULL | 33 |
| NULL | ecp | 7 |
| NULL | full | 1 |
| NULL | move | 1 |
| NULL | none | 77 |
| NULL | pc | 3 |
| NULL | semi | 57 |
| NULL | upload | 1 |
| NULL | NULL | 29498 |

</details>

The original 2016–2025 mainspace granted/denied increase/ECP filter now gives 3,199 granted and 2,201 denied candidates (previously 3,535/2,595). These are parser-defined candidates, not validated ECP demand.

`issue-1-changed-records-20261010.csv` SHA256: `285d248b1ad6029895ac2109d2ba8d7720f0b6f60892b74d5b8e85bf526db6d6`.

`issue-1-analysis-parser-20261010.patch` SHA256: `c19c2e1eb8fd9ff39902d3ac0119b54847becf9e8ead6a0068af67625c12e28f`.

<details>
<summary>Analysis source patch (apply within wpp-analysis)</summary>

```diff
diff --git a/sql/04_rfpp_request_extend.sql b/sql/04_rfpp_request_extend.sql
index 1ba46ec..bd29b6d 100644
--- a/sql/04_rfpp_request_extend.sql
+++ b/sql/04_rfpp_request_extend.sql
@@ -5,11 +5,9 @@
 -- Requires analysis.protect_event (sql/02).
 -- Run: psql service=wiki -v ON_ERROR_STOP=1 -f sql/04_rfpp_request_extend.sql  (~2 min)
 --
--- requested_level is parsed from the FIRST bold label in `reason` (the RFPP template
--- puts "'''Temporary semi-protection:'''" after the {{pagelinks}} line). Since 2021 a
--- growing share of requests (~30 %) use a form that writes only "'''Reason:'''" — for
--- those the level is inferred from the first level keyword in the reason body
--- (requested_level_source = 'body') or left NULL.
+-- Request intent is parsed by the shared versioned parser in 04a/04b.
+-- Explicit tiers, destination transitions, alternatives, and uncertainty are
+-- preserved without using administrative outcomes or applied-action fields.
 SET work_mem = '1GB';
 SET default_tablespace = wiki_ts_lacie10;
 SET TIME ZONE 'UTC';
@@ -41,10 +39,10 @@ ALTER TABLE analysis.rfpp_request
     DROP COLUMN IF EXISTS board;
 
 ALTER TABLE analysis.rfpp_request
-    ADD COLUMN requested_action         text,        -- increase | decrease | edit | NULL (unparsed)
-    ADD COLUMN requested_level          text,        -- semi | ecp | full | pc | move | salt | template | other | NULL
+    ADD COLUMN requested_action         text,        -- increase | decrease | edit | change | NULL (unresolved)
+    ADD COLUMN requested_level          text,        -- semi | ecp | full | pc | move | salt | template | upload | none | NULL
     ADD COLUMN requested_level_source   text,        -- label | body | NULL
-    ADD COLUMN request_label            text,        -- the bold label as written (audit)
+    ADD COLUMN request_label            text,        -- lowercased/trimmed label; verbatim text is in requested_intent
     ADD COLUMN substitute_remedy        text,        -- bloc | already protected | noun | NULL
     ADD COLUMN self_decided             boolean,     -- admin = requester
     ADD COLUMN decision_ts              timestamptz, -- COALESCE(admin_timestamp, request_timestamp)
@@ -64,13 +62,12 @@ ALTER TABLE analysis.rfpp_request
     ADD COLUMN year_month               text,
     ADD COLUMN utc_hour_block           smallint,    -- 0..3 = six-hour UTC blocks of request_timestamp
     ADD COLUMN weekday                  smallint,    -- ISO 1 = Monday .. 7 = Sunday
-    ADD COLUMN board                    text;        -- increase | decrease | edit (from the archive path when present, else requested_action)
+    ADD COLUMN board                    text;        -- archive section when explicit, otherwise requested_action (including change/NULL)
 
 ------------------------------------------------------------------------------
 -- 1. Request decomposition
 ------------------------------------------------------------------------------
 UPDATE analysis.rfpp_request r SET
-    request_label = x.lbl,
     decision_ts   = COALESCE(r.admin_timestamp, r.request_timestamp),
     self_decided  = (r.admin_actor_id IS NOT NULL AND r.admin_actor_id = r.requester_actor_id),
     substitute_remedy = CASE lower(r.response_code)
@@ -79,66 +76,9 @@ UPDATE analysis.rfpp_request r SET
                           WHEN 'noun' THEN 'noun' END,
     year_month     = to_char(r.request_timestamp AT TIME ZONE 'UTC', 'YYYY-MM'),
     utc_hour_block = (extract(hour FROM r.request_timestamp AT TIME ZONE 'UTC')::int / 6)::smallint,
-    weekday        = extract(isodow FROM r.request_timestamp AT TIME ZONE 'UTC')::smallint
-FROM (SELECT rfpp_id,
-             lower(btrim(regexp_replace(substring(reason FROM '''''''([^'']{1,80})'''''''), '[:.\s]+$', ''))) AS lbl
-        FROM analysis.rfpp_request) x
-WHERE x.rfpp_id = r.rfpp_id;
+    weekday        = extract(isodow FROM r.request_timestamp AT TIME ZONE 'UTC')::smallint;
 
-UPDATE analysis.rfpp_request r SET
-    requested_action = CASE
-        WHEN r.outcome = 'unparsed' AND r.reason IS NULL THEN NULL
-        WHEN r.response_code = 'edre' OR r.request_label ~ 'edit request' THEN 'edit'
-        WHEN r.request_label ~ '(unprotect|reduc|downgrad|lower|remov|lift|decrease)'
-          OR lower(r.response_code) IN ('unprotected','noun','isun','unpr') THEN 'decrease'
-        ELSE 'increase' END;
-
--- level: first keyword in the bold label (POSIX leftmost match), else in the reason body
-UPDATE analysis.rfpp_request r SET
-    requested_level = CASE
-        WHEN x.k IS NULL THEN NULL
-        WHEN x.k IN ('semi','semi-protect','semiprotect')             THEN 'semi'
-        WHEN x.k IN ('extended','ecp','ec')                            THEN 'ecp'
-        WHEN x.k IN ('full','fully')                                   THEN 'full'
-        WHEN x.k IN ('pending','pc','flagged')                         THEN 'pc'
-        WHEN x.k IN ('template')                                       THEN 'template'
-        WHEN x.k IN ('create','creation','salt')                       THEN 'salt'
-        WHEN x.k IN ('move')                                           THEN 'move'
-        ELSE 'other' END,
-    requested_level_source = x.src
-FROM (
-    SELECT rfpp_id,
-           COALESCE(lbl_k, body_k) AS k,
-           CASE WHEN lbl_k IS NOT NULL THEN 'label' WHEN body_k IS NOT NULL THEN 'body' END AS src
-      FROM (
-        SELECT rfpp_id,
-               CASE WHEN request_label IS NOT NULL AND request_label !~ '^reason' THEN
-                    COALESCE(substring(request_label FROM '(semi|extended|\mecp\M|\mec\M|full|fully|pending|\mpc\M|flagged|template|creat|salt|\mmove)'),
-                             CASE WHEN request_label ~ 'protect' THEN 'other' END) END AS lbl_k,
-               substring(lower(left(regexp_replace(reason, '\{\{pagelinks[^}]*\}\}', '', 'g'), 400))
-                         FROM '(semi|extended.confirmed|\mecp\M|full.protect|pending|\mpc\M|template.protect|creat(e|ion).protect|salt|move.protect)') AS body_k
-          FROM analysis.rfpp_request) y
-) x
-WHERE x.rfpp_id = r.rfpp_id;
--- normalise the multi-word body keys
-UPDATE analysis.rfpp_request SET requested_level = 'ecp'      WHERE requested_level = 'other' AND requested_level_source='body' AND reason ~* 'extended.confirmed';
-UPDATE analysis.rfpp_request SET requested_level = CASE
-        WHEN requested_level_source = 'body' AND requested_level IS NULL THEN NULL ELSE requested_level END;
-
--- second pass for body-derived keys that the CASE above could not map (multi-word tokens)
-UPDATE analysis.rfpp_request r SET requested_level = m.lvl
-FROM (
-    SELECT rfpp_id,
-           CASE k WHEN 'full.protect' THEN 'full' WHEN 'template.protect' THEN 'template'
-                  WHEN 'move.protect' THEN 'move' ELSE NULL END AS lvl
-      FROM (SELECT rfpp_id, regexp_replace(
-                 substring(lower(left(regexp_replace(reason, '\{\{pagelinks[^}]*\}\}', '', 'g'), 400))
-                           FROM '(full.protect|template.protect|move.protect)'), '[ -]', '.') AS k
-              FROM analysis.rfpp_request WHERE requested_level_source = 'body' AND requested_level = 'other') z
-     WHERE k IS NOT NULL) m
-WHERE m.rfpp_id = r.rfpp_id AND m.lvl IS NOT NULL;
-UPDATE analysis.rfpp_request SET requested_level = 'salt'
- WHERE requested_level_source = 'body' AND requested_level = 'other' AND reason ~* 'creat(e|ion).protect';
+\ir 04b_rfpp_request_intent.sql
 
 ------------------------------------------------------------------------------
 -- 1b. Page identity repair. rfpp_request.page_id is the page that carries the
@@ -184,61 +124,9 @@ UPDATE analysis.rfpp_request SET page_id_match = COALESCE(page_id_log, page_id);
 ------------------------------------------------------------------------------
 -- 2. Match to the protection log (on page_id_match)
 ------------------------------------------------------------------------------
--- one candidate row per protect/stable LOG row (a log row spans several restriction types)
-CREATE TEMP TABLE ev_row AS
-SELECT log_id, page_id, ts, log_type, log_action, admin_actor_id,
-       bool_or(is_opening) AS is_opening, bool_or(is_closing) AS is_closing,
-       -- primary restriction: edit > stable > create > move > upload
-       (array_agg(restriction_type ORDER BY CASE restriction_type WHEN 'edit' THEN 1 WHEN 'stable' THEN 2 WHEN 'create' THEN 3 WHEN 'move' THEN 4 ELSE 5 END)
-          FILTER (WHERE is_opening))[1] AS prim_type,
-       (array_agg(level ORDER BY CASE restriction_type WHEN 'edit' THEN 1 WHEN 'stable' THEN 2 WHEN 'create' THEN 3 WHEN 'move' THEN 4 ELSE 5 END)
-          FILTER (WHERE is_opening))[1] AS prim_level,
-       (array_agg(expiry ORDER BY CASE restriction_type WHEN 'edit' THEN 1 WHEN 'stable' THEN 2 WHEN 'create' THEN 3 WHEN 'move' THEN 4 ELSE 5 END)
-          FILTER (WHERE is_opening))[1] AS prim_expiry
-  FROM analysis.protect_event
- WHERE page_id IS NOT NULL AND (is_opening OR is_closing)
- GROUP BY 1,2,3,4,5,6;
-CREATE INDEX ON ev_row (page_id, ts);
-ANALYZE ev_row;
-
-CREATE TEMP TABLE matched AS
-SELECT r.rfpp_id, m.log_id, m.ts - r.decision_ts AS off, m.log_action, m.is_opening, m.is_closing,
-       (m.admin_actor_id = r.admin_actor_id) AS same_admin,
-       m.prim_type, m.prim_level, m.prim_expiry
-  FROM analysis.rfpp_request r
-  JOIN LATERAL (
-        SELECT e.* FROM ev_row e
-         WHERE e.page_id = r.page_id_match
-           AND e.ts >= r.request_timestamp - interval '1 hour'
-           AND e.ts <= r.decision_ts + interval '48 hours'
-           -- only rows that go in the requested direction (an unprotect by the same admin must not shadow a protect)
-           AND (e.is_opening OR r.requested_action = 'decrease')
-         ORDER BY (e.admin_actor_id = r.admin_actor_id) DESC NULLS LAST,
-                  abs(extract(epoch FROM e.ts - r.decision_ts))
-         LIMIT 1) m ON true
- WHERE r.page_id_match IS NOT NULL AND r.request_timestamp IS NOT NULL;
-
-UPDATE analysis.rfpp_request r SET
-    matched_log_id     = m.log_id,
-    matched_offset     = m.off,
-    matched_action     = m.log_action,
-    matched_same_admin = m.same_admin,
-    granted_type       = m.prim_type,
-    granted_level_raw  = m.prim_level,
-    granted_level      = CASE
-        WHEN m.is_closing AND NOT m.is_opening THEN 'none'
-        WHEN m.prim_type = 'edit' THEN CASE m.prim_level WHEN 'autoconfirmed' THEN 'semi' WHEN 'extendedconfirmed' THEN 'ecp'
-                                                         WHEN 'sysop' THEN 'full' WHEN 'templateeditor' THEN 'template' ELSE m.prim_level END
-        WHEN m.prim_type = 'stable' THEN 'pc'
-        WHEN m.prim_type = 'create' THEN 'salt'
-        WHEN m.prim_type = 'move'   THEN 'move'
-        WHEN m.prim_type = 'upload' THEN 'upload' END,
-    scheduled_expiry   = m.prim_expiry,
-    treated_by_log     = CASE
-        WHEN r.requested_action = 'decrease' THEN (m.is_closing OR m.is_opening)   -- unprotect or downgrade (modify)
-        ELSE m.is_opening END
-FROM matched m WHERE m.rfpp_id = r.rfpp_id;
-UPDATE analysis.rfpp_request SET treated_by_log = false WHERE treated_by_log IS NULL;
+CREATE TEMP TABLE rfpp_match_ids AS SELECT rfpp_id FROM analysis.rfpp_request;
+CREATE UNIQUE INDEX ON rfpp_match_ids (rfpp_id);
+\ir 04c_rfpp_request_match.sql
 
 -- denied requests whose page nevertheless received an opening event within 30 days of the decision
 UPDATE analysis.rfpp_request r SET denied_but_protected_30d = EXISTS (
diff --git a/sql/04a_rfpp_intent_parser.sql b/sql/04a_rfpp_intent_parser.sql
new file mode 100644
--- /dev/null
+++ b/sql/04a_rfpp_intent_parser.sql
@@ -0,0 +1,195 @@
+-- Versioned RFPP intent parser. No response, outcome, or applied-tier inputs.
+-- Install independently; this file does not update request rows.
+\set ON_ERROR_STOP on
+
+CREATE OR REPLACE FUNCTION analysis.rfpp_intent_normalize_v2(raw text)
+RETURNS text LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $fn$
+DECLARE t text := coalesce(raw, '');
+BEGIN
+    t := regexp_replace(t, '\[\[[^]|]+\|([^]]+)\]\]', '\1', 'g');
+    t := regexp_replace(t, '\[\[([^]]+)\]\]', '\1', 'g');
+    t := regexp_replace(t, '<!--.*?-->|<[^>]*>', ' ', 'g');
+    t := regexp_replace(t, '&nbsp;|&#160;|&ndash;|&mdash;|&#8211;|&#8212;', ' ', 'gi');
+    -- SQL_ASCII treats translate() characters as bytes: multibyte punctuation
+    -- would remove bytes from unrelated Unicode text. Replace whole sequences.
+    t := replace(replace(t, '–', ' '), '—', ' ');
+    t := translate(t, '-_', '  ');
+    RETURN lower(btrim(regexp_replace(t, '[[:space:]]+', ' ', 'g')));
+END $fn$;
+
+CREATE OR REPLACE FUNCTION analysis.rfpp_intent_levels_v2(t text, label_mode boolean)
+RETURNS text[] LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $fn$
+SELECT coalesce(array_agg(tier ORDER BY ord), ARRAY[]::text[])
+FROM (VALUES
+ (1,'none',t ~ '\m(unprotection|unprotect)\M|\m(no protection|not protected|open editing)\M'),
+ (2,'semi',t ~ '\m(semi|semiprotection|autoconfirmed)\M|\mauto confirmed\M'),
+ (3,'ecp',t ~ '\mextended confirmed\M|\mecp\M' OR
+          (t ~ '\mec\M' AND (label_mode OR t ~ '\mec protection\M'))),
+ (4,'full',t ~ '\m(full|fully) protection\M' OR (label_mode AND t ~ '\mfull\M')),
+ (5,'template',t ~ '\mtemplate (protection|editor)\M|\mtemplateeditor\M'),
+ (6,'pc',t ~ '\mpending changes?\M|\mpc protection\M' OR (label_mode AND t ~ '\m(pc|pending)\M')),
+ (7,'salt',t ~ '\m(creat(e|ion) protection|salt(ing)?)\M'),
+ (8,'move',t ~ '\mmove protection\M'),
+ (9,'upload',t ~ '\mupload protection\M')
+) AS levels(ord,tier,matched) WHERE matched
+$fn$;
+
+CREATE OR REPLACE FUNCTION analysis.rfpp_parse_intent_v2(reason text)
+RETURNS jsonb LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $fn$
+DECLARE
+    raw_label text;
+    leading_label text;
+    unresolved_alternative boolean := false;
+    label text;
+    evidence text;
+    body text;
+    part text;
+    body_match text[];
+    source text := 'label';
+    status text := 'explicit';
+    rule text := 'label_single_target';
+    action text := 'increase';
+    action_basis text := 'request_default';
+    tier text;
+    origin text;
+    targets text[] := ARRAY[]::text[];
+    found text[];
+    transition text[];
+    origins text[];
+    origin_rank integer;
+    target_rank integer;
+    declared_action text;
+    label_action text;
+    extension boolean := false;
+BEGIN
+    IF reason IS NULL OR btrim(reason) = '' THEN
+        RETURN jsonb_build_object('version','rfpp-intent-v2.0.0','status','unspecified',
+            'rule','missing_reason','action',NULL,'tier',NULL,'targets',targets,
+            'origin',NULL,'source',NULL,'action_basis','unknown','label_raw',NULL);
+    END IF;
+    -- No 80-character limit: retain the original extracted label as evidence.
+    raw_label := (regexp_match(reason, $re$'''(.*?)'''$re$))[1];
+    -- Generic form headings can precede the actual bold request label.
+    IF analysis.rfpp_intent_normalize_v2(raw_label) ~ '^(reason|protection|request)[:. ]*$' THEN
+        leading_label := (regexp_match(reason,
+            $re$'''(?:Reason|Protection|Request)[:.[:space:]]*'''[[:space:]]*'''(.*?)'''$re$, 'i'))[1];
+        IF leading_label IS NOT NULL THEN raw_label := leading_label; END IF;
+    END IF;
+    label := analysis.rfpp_intent_normalize_v2(raw_label);
+    label := regexp_replace(label, '[:.[:space:]]+$', '');
+    evidence := label;
+    IF label ~ '\m(unprotect|unprotection|reduc(e|tion)|downgrad(e|ing)|lower|remov(e|al|ing)|lift|decrease)\M' THEN
+        label_action := 'decrease';
+    ELSIF label ~ '\m(increase|upgrade|escalate)\M' THEN label_action := 'increase'; END IF;
+    IF raw_label ~* '<(s|del|strike)([[:space:]>])' THEN
+        status := 'chronology_uncertain'; rule := 'amended_label';
+        action := NULL; action_basis := 'unknown';
+        targets := analysis.rfpp_intent_levels_v2(label, true);
+    ELSE
+        targets := analysis.rfpp_intent_levels_v2(label, true);
+        IF label = '' OR label ~ '^(reason|protection|request|protect)$' OR
+           (cardinality(targets)=0 AND label !~ '\m(edit request|unprotect|unprotection)\M') THEN
+            source := 'body'; rule := 'body_explicit_request'; evidence := NULL;
+            body := regexp_replace(reason, '\{\{[^{}]*\}\}', ' ', 'g');
+            -- Avoid signatures and subsequent discussion when available.
+            body := regexp_replace(body, '\[\[(User|User talk|Special:Contributions):.*$', '', 'i');
+            IF body ~* '<(s|del|strike)([[:space:]>])' THEN
+                status := 'chronology_uncertain'; rule := 'amended_body';
+                action := NULL; action_basis := 'unknown';
+            ELSE
+                body := analysis.rfpp_intent_normalize_v2(body);
+                body := replace(body, $q$'''$q$, '');
+                body := regexp_replace(body, '^reason[[:space:]]*:', '');
+                -- Search request clauses rather than the first tier mentioned.
+                -- Multiple supported clauses remain ambiguous; no 400-char cap.
+                FOR part IN SELECT unnest(regexp_split_to_array(body, '[;.!?]|\mbut\M')) LOOP
+                    IF part ~ '\m(not|never|do not|don''t)\M' THEN CONTINUE; END IF;
+                    -- A target must be the object of a request phrase. A later
+                    -- mention of disruptive autoconfirmed users is not a target.
+                    body_match := regexp_match(part,
+                        '\m(request(ing)?|apply|ask(ing)? for|would like|want|need|upgrade (it )?to|downgrade (it )?to)[[:space:]]+(((temporary|indefinite|permanent|long term|short term|a|an|the|some|at least)[[:space:]]+)*(semi|semiprotection|extended confirmed|ecp|full protection|pending changes|template protection|creation protection|create protection|move protection|upload protection|unprotection)\M.*)');
+                    IF body_match IS NOT NULL THEN
+                        IF part ~ '\mor\M.*\mextended protection\M' THEN
+                            unresolved_alternative := true;
+                        END IF;
+                        IF part ~ '\munprotect(ion|ing)?\M.*\mor\M' THEN
+                            IF evidence IS NULL THEN evidence := 'unprotection or';
+                            ELSE evidence := evidence || '; unprotection or'; END IF;
+                        END IF;
+                        part := body_match[1] || ' ' || body_match[6];
+                        part := regexp_replace(part, '\m(because|since|due to|as)\M.*$', '');
+                    ELSIF part ~ '\m(please|request(ing)?|could you|can you|would you)\M.*\munprotect\M' THEN
+                        part := 'unprotection';
+                    ELSIF part !~ '^[[:space:]]*(temporary[[:space:]]+)?semi([[:space:]]+protection)?[[:space:]]+is enough' THEN
+                        CONTINUE;
+                    END IF;
+                    IF part IS NOT NULL THEN
+                        found := analysis.rfpp_intent_levels_v2(part, false);
+                        IF cardinality(found)>0 THEN
+                            IF evidence IS NULL THEN evidence := part;
+                            ELSE evidence := evidence || '; ' || part; END IF;
+                        END IF;
+                    END IF;
+                END LOOP;
+                targets := analysis.rfpp_intent_levels_v2(coalesce(evidence,''), false);
+                IF evidence IS NULL AND label_action IS NOT NULL THEN evidence := label; END IF;
+                IF evidence IS NULL THEN action := NULL; action_basis := 'unknown'; END IF;
+            END IF;
+        END IF;
+        IF status <> 'chronology_uncertain' THEN
+            IF evidence ~ '\medit request\M' THEN
+                action := 'edit'; action_basis := 'explicit_request';
+                targets := ARRAY[]::text[]; status := 'edit_request'; rule := 'edit_request';
+            ELSE
+                declared_action := label_action;
+                IF evidence ~ '\m(unprotect|unprotection|reduc(e|tion)|downgrad(e|ing)|lower|remov(e|al|ing)|lift|decrease)\M' THEN
+                    declared_action := 'decrease';
+                ELSIF evidence ~ '\m(increase|upgrade|escalate)\M' THEN declared_action := 'increase'; END IF;
+                IF declared_action IS NOT NULL THEN action := declared_action; action_basis := 'explicit_request'; END IF;
+                IF action IS NULL AND cardinality(targets)>0 THEN action := 'increase'; action_basis := 'explicit_target'; END IF;
+                transition := regexp_match(evidence, '\mfrom[[:space:]]+(.*?)[[:space:]]+to[[:space:]]+(.*)');
+                IF transition IS NOT NULL THEN
+                    origins := analysis.rfpp_intent_levels_v2(transition[1], true);
+                    targets := analysis.rfpp_intent_levels_v2(transition[2], true);
+                    IF cardinality(origins)=1 THEN origin := origins[1]; END IF;
+                    rule := 'explicit_transition';
+                    -- Only compare edit tiers with an established ordering here.
+                    origin_rank := array_position(ARRAY['none','semi','ecp','full'], origin);
+                    target_rank := array_position(ARRAY['none','semi','ecp','full'], targets[1]);
+                    IF cardinality(targets)=1 AND origin_rank IS NOT NULL AND target_rank IS NOT NULL THEN
+                        action := CASE WHEN target_rank>origin_rank THEN 'increase'
+                                       WHEN target_rank<origin_rank THEN 'decrease' ELSE 'change' END;
+                        action_basis := 'explicit_transition';
+                        IF declared_action IS NOT NULL AND declared_action<>action THEN
+                            action := NULL; status := 'ambiguous'; rule := 'conflicting_direction';
+                        END IF;
+                    ELSIF declared_action IS NULL THEN
+                        action := 'change'; action_basis := 'unordered_transition';
+                    END IF;
+                END IF;
+                extension := coalesce(coalesce(evidence,label) ~ '\m(extend|extending|renew(al)?|longer)\M|\mextended\M(?![[:space:]]+confirmed)', false);
+                IF cardinality(targets)=1 AND status<>'ambiguous' THEN
+                    tier := targets[1];
+                    IF tier='none' THEN action := 'decrease'; action_basis := 'explicit_request'; END IF;
+                    -- Negated or quoted labels are not single-target evidence.
+                    IF evidence ~ '\m(not|never|rather than|instead of)\M' THEN
+                        tier := NULL; status := 'ambiguous'; rule := 'negated_label';
+                    END IF;
+                ELSIF cardinality(targets)>1 THEN
+                    status := CASE WHEN evidence ~ '\mor\M|/' THEN 'alternative' ELSE 'ambiguous' END;
+                    rule := 'multiple_targets';
+                    IF 'none'=ANY(targets) THEN action := NULL; action_basis := 'unknown'; END IF;
+                ELSIF cardinality(targets)=0 AND status<>'edit_request' THEN
+                    status := 'unspecified'; rule := 'no_supported_target'; source := NULL;
+                END IF;
+            END IF;
+        END IF;
+    END IF;
+    IF unresolved_alternative THEN
+        tier := NULL; status := 'ambiguous'; rule := 'unsupported_alternative';
+    END IF;
+    RETURN jsonb_build_object('version','rfpp-intent-v2.0.0','status',status,'rule',rule,
+        'action',action,'tier',tier,'targets',targets,'origin',origin,'source',source,
+        'action_basis',action_basis,'duration_extension',extension,'label_raw',raw_label,
+        'label',label,'evidence',evidence);
+END $fn$;
diff --git a/sql/04b_rfpp_request_intent.sql b/sql/04b_rfpp_request_intent.sql
new file mode 100644
--- /dev/null
+++ b/sql/04b_rfpp_request_intent.sql
@@ -0,0 +1,13 @@
+-- Shared intent decomposition for fresh SQL04 builds.
+-- Existing databases should use the audited staged migration in db-auditing.
+\set ON_ERROR_STOP on
+\ir 04a_rfpp_intent_parser.sql
+ALTER TABLE analysis.rfpp_request ADD COLUMN IF NOT EXISTS requested_intent jsonb;
+UPDATE analysis.rfpp_request SET requested_intent=analysis.rfpp_parse_intent_v2(reason);
+UPDATE analysis.rfpp_request
+SET requested_action=requested_intent->>'action',
+    requested_level=requested_intent->>'tier',
+    requested_level_source=requested_intent->>'source',
+    request_label=lower(btrim(regexp_replace(requested_intent->>'label_raw', '[:.\s]+$', '')));
+COMMENT ON COLUMN analysis.rfpp_request.requested_intent IS
+'Versioned request-only intent evidence: origin, target set, parse status, rule, raw label, evidence, direction basis, and duration-extension language. No outcome/applied-tier inputs. NULL tier/action means unresolved where indicated; archived amendments remain chronology_uncertain.';
diff --git a/sql/04c_rfpp_request_match.sql b/sql/04c_rfpp_request_match.sql
new file mode 100644
--- /dev/null
+++ b/sql/04c_rfpp_request_match.sql
@@ -0,0 +1,73 @@
+-- Shared protection-log matching. The caller creates temp rfpp_match_ids(rfpp_id).
+-- Full SQL04 builds supply all requests; the intent migration supplies only
+-- rows whose requested action changed. Protection-event records are read-only.
+\set ON_ERROR_STOP on
+-- one candidate row per protect/stable LOG row (a log row spans several restriction types)
+CREATE TEMP TABLE ev_row AS
+SELECT log_id, page_id, ts, log_type, log_action, admin_actor_id,
+       bool_or(is_opening) AS is_opening, bool_or(is_closing) AS is_closing,
+       -- primary restriction: edit > stable > create > move > upload
+       (array_agg(restriction_type ORDER BY CASE restriction_type WHEN 'edit' THEN 1 WHEN 'stable' THEN 2 WHEN 'create' THEN 3 WHEN 'move' THEN 4 ELSE 5 END)
+          FILTER (WHERE is_opening))[1] AS prim_type,
+       (array_agg(level ORDER BY CASE restriction_type WHEN 'edit' THEN 1 WHEN 'stable' THEN 2 WHEN 'create' THEN 3 WHEN 'move' THEN 4 ELSE 5 END)
+          FILTER (WHERE is_opening))[1] AS prim_level,
+       (array_agg(expiry ORDER BY CASE restriction_type WHEN 'edit' THEN 1 WHEN 'stable' THEN 2 WHEN 'create' THEN 3 WHEN 'move' THEN 4 ELSE 5 END)
+          FILTER (WHERE is_opening))[1] AS prim_expiry
+  FROM analysis.protect_event
+ WHERE page_id IS NOT NULL AND (is_opening OR is_closing)
+ GROUP BY 1,2,3,4,5,6;
+CREATE INDEX ON ev_row (page_id, ts);
+ANALYZE ev_row;
+
+CREATE TEMP TABLE matched AS
+SELECT r.rfpp_id, m.log_id, m.ts - r.decision_ts AS off, m.log_action, m.is_opening, m.is_closing,
+       (m.admin_actor_id = r.admin_actor_id) AS same_admin,
+       m.prim_type, m.prim_level, m.prim_expiry
+  FROM analysis.rfpp_request r
+  JOIN rfpp_match_ids scope ON scope.rfpp_id=r.rfpp_id
+  JOIN LATERAL (
+        SELECT e.* FROM ev_row e
+         WHERE e.page_id = r.page_id_match
+           AND e.ts >= r.request_timestamp - interval '1 hour'
+           AND e.ts <= r.decision_ts + interval '48 hours'
+           -- only rows that go in the requested direction (an unprotect by the same admin must not shadow a protect)
+           AND (e.is_opening OR r.requested_action IN ('decrease','change') OR r.requested_action IS NULL)
+         ORDER BY (e.admin_actor_id = r.admin_actor_id) DESC NULLS LAST,
+                  abs(extract(epoch FROM e.ts - r.decision_ts)), e.log_id
+         LIMIT 1) m ON true
+ WHERE r.page_id_match IS NOT NULL AND r.request_timestamp IS NOT NULL
+   AND r.requested_action IS DISTINCT FROM 'edit';
+
+-- Clear prior associations only for the caller's explicit scope.
+UPDATE analysis.rfpp_request r SET
+    matched_log_id=NULL, matched_offset=NULL, matched_action=NULL,
+    matched_same_admin=NULL, granted_type=NULL, granted_level=NULL,
+    granted_level_raw=NULL, scheduled_expiry=NULL,
+    treated_by_log=CASE WHEN r.requested_action IS NULL THEN NULL ELSE false END
+FROM rfpp_match_ids scope WHERE scope.rfpp_id=r.rfpp_id;
+
+UPDATE analysis.rfpp_request r SET
+    matched_log_id     = m.log_id,
+    matched_offset     = m.off,
+    matched_action     = m.log_action,
+    matched_same_admin = m.same_admin,
+    granted_type       = m.prim_type,
+    granted_level_raw  = m.prim_level,
+    granted_level      = CASE
+        WHEN m.is_closing AND NOT m.is_opening THEN 'none'
+        WHEN m.prim_type = 'edit' THEN CASE m.prim_level WHEN 'autoconfirmed' THEN 'semi' WHEN 'extendedconfirmed' THEN 'ecp'
+                                                         WHEN 'sysop' THEN 'full' WHEN 'templateeditor' THEN 'template' ELSE m.prim_level END
+        WHEN m.prim_type = 'stable' THEN 'pc'
+        WHEN m.prim_type = 'create' THEN 'salt'
+        WHEN m.prim_type = 'move'   THEN 'move'
+        WHEN m.prim_type = 'upload' THEN 'upload' END,
+    scheduled_expiry   = m.prim_expiry,
+    treated_by_log     = CASE
+        WHEN r.requested_action IS NULL THEN NULL -- unknown intent cannot establish treatment direction
+        WHEN r.requested_action IN ('decrease','change') THEN (m.is_closing OR m.is_opening)
+        ELSE m.is_opening END
+FROM matched m WHERE m.rfpp_id = r.rfpp_id;
+UPDATE analysis.rfpp_request r SET treated_by_log=false
+FROM rfpp_match_ids scope WHERE scope.rfpp_id=r.rfpp_id AND r.treated_by_log IS NULL
+  AND r.requested_action IS NOT NULL;
+
```

</details>

<details>
<summary>Scoped migration with rehearsal default and preservation assertions</summary>

```sql
-- Scoped, audited repair. Default is a full rehearsal ending in ROLLBACK.
-- Apply: psql -X service=wiki -v commit_repair=1 -f apply_rfpp_intent_v2.sql
-- Requires the immutable backup, reviewed stage, and stage signature.
\set ON_ERROR_STOP on
\if :{?commit_repair}
\else
  \set commit_repair 0
\endif
SET TIME ZONE 'UTC';
SET lock_timeout='5s';
SET statement_timeout='30min';
SET work_mem='256MB';
DO $$ BEGIN
  IF current_database()<>'wiki20260401' OR current_setting('port')<>'5434' THEN
    RAISE EXCEPTION 'Wrong migration target';
  END IF;
END $$;
-- Short independent catalog change; release its exclusive lock before the scan.
ALTER TABLE analysis.rfpp_request ADD COLUMN IF NOT EXISTS requested_intent jsonb;
BEGIN;
LOCK TABLE analysis.rfpp_request IN SHARE ROW EXCLUSIVE MODE;
DO $$ DECLARE actual_signature text; BEGIN
  IF (SELECT status FROM analysis.rfpp_intent_v2_run WHERE id=1) IS DISTINCT FROM 'staged' THEN
    RAISE EXCEPTION 'Migration is not in staged state';
  END IF;
  SELECT md5(string_agg(pg_get_functiondef(oid), E'\n' ORDER BY proname)) INTO actual_signature
  FROM pg_proc WHERE pronamespace='analysis'::regnamespace
    AND proname IN ('rfpp_intent_normalize_v2','rfpp_intent_levels_v2','rfpp_parse_intent_v2');
  IF actual_signature IS DISTINCT FROM (SELECT parser_signature FROM analysis.rfpp_intent_v2_run WHERE id=1) THEN
    RAISE EXCEPTION 'Parser changed after staging';
  END IF;
  IF (SELECT count(*) FROM analysis.rfpp_request)<>(SELECT count(*) FROM analysis.rfpp_intent_v2_stage)
     OR EXISTS (SELECT 1 FROM analysis.rfpp_request r FULL JOIN analysis.rfpp_intent_v2_stage s USING(rfpp_id)
                WHERE r.rfpp_id IS NULL OR s.rfpp_id IS NULL
                   OR md5((to_jsonb(r)-'requested_intent')::text)<>s.before_hash) THEN
    RAISE EXCEPTION 'Live rows changed after staging; stop and reconcile';
  END IF;
END $$;

CREATE TEMP TABLE rfpp_match_ids AS
SELECT rfpp_id FROM analysis.rfpp_intent_v2_stage
WHERE old_action IS DISTINCT FROM intent->>'action';
CREATE UNIQUE INDEX ON rfpp_match_ids (rfpp_id);

UPDATE analysis.rfpp_request r
SET requested_intent=s.intent,
    requested_action=s.intent->>'action', requested_level=s.intent->>'tier',
    requested_level_source=s.intent->>'source',
    request_label=lower(btrim(regexp_replace(s.intent->>'label_raw','[:.\s]+$',''))),
    board=CASE WHEN r.archive_page ~ '/Increase' THEN 'increase'
               WHEN r.archive_page ~ '/Decrease' THEN 'decrease'
               WHEN r.archive_page ~ '/Edit' THEN 'edit' ELSE s.intent->>'action' END
FROM analysis.rfpp_intent_v2_stage s WHERE s.rfpp_id=r.rfpp_id;

-- Recompute only associations whose direction input changed. Applied levels
-- still come solely from protection events, never from the requested tier.
\ir ../20261001/wpp-analysis/sql/04c_rfpp_request_match.sql

CREATE TABLE analysis.rfpp_intent_v2_changes TABLESPACE wiki_ts_lacie10 AS
SELECT r.rfpp_id,s.before_hash,md5((to_jsonb(r)-'requested_intent')::text) AS after_hash,
       b.requested_action AS old_action,r.requested_action AS new_action,
       b.requested_level AS old_level,r.requested_level AS new_level,
       b.requested_level_source AS old_source,r.requested_level_source AS new_source,
       b.request_label AS old_label,r.request_label AS new_label,
       b.board AS old_board,r.board AS new_board,
       b.matched_log_id AS old_log_id,r.matched_log_id AS new_log_id,
       b.treated_by_log AS old_treated_by_log,r.treated_by_log AS new_treated_by_log,
       r.requested_intent,current_timestamp AS applied_at
FROM analysis.rfpp_request r JOIN analysis.rfpp_request_pre_intent_v2 b USING(rfpp_id)
JOIN analysis.rfpp_intent_v2_stage s USING(rfpp_id)
WHERE (to_jsonb(r)-'requested_intent') IS DISTINCT FROM to_jsonb(b);
ALTER TABLE analysis.rfpp_intent_v2_changes
  ADD PRIMARY KEY(rfpp_id) USING INDEX TABLESPACE wiki_ts_lacie10;

DO $$ DECLARE mutable text[] := ARRAY[
 'requested_intent','requested_action','requested_level','requested_level_source','request_label','board',
 'matched_log_id','matched_offset','matched_action','matched_same_admin','granted_type','granted_level',
 'granted_level_raw','scheduled_expiry','treated_by_log']; BEGIN
  IF EXISTS(SELECT 1 FROM analysis.rfpp_request r JOIN analysis.rfpp_request_pre_intent_v2 b USING(rfpp_id)
            WHERE (to_jsonb(r)-mutable) IS DISTINCT FROM (to_jsonb(b)-mutable)) THEN
    RAISE EXCEPTION 'A raw, outcome, identity, or unrelated derived field changed';
  END IF;
  IF EXISTS(SELECT 1 FROM analysis.rfpp_request r JOIN analysis.rfpp_intent_v2_stage s USING(rfpp_id)
            WHERE r.requested_intent IS DISTINCT FROM s.intent
               OR r.requested_action IS DISTINCT FROM s.intent->>'action'
               OR r.requested_level IS DISTINCT FROM s.intent->>'tier') THEN
    RAISE EXCEPTION 'Applied classifications differ from reviewed stage';
  END IF;
  IF EXISTS(SELECT 1 FROM analysis.rfpp_request r JOIN analysis.rfpp_request_pre_intent_v2 b USING(rfpp_id)
            WHERE r.requested_action IS NOT DISTINCT FROM b.requested_action
              AND (r.matched_log_id,r.matched_offset,r.matched_action,r.matched_same_admin,
                   r.granted_type,r.granted_level,r.granted_level_raw,r.scheduled_expiry,r.treated_by_log)
                  IS DISTINCT FROM
                  (b.matched_log_id,b.matched_offset,b.matched_action,b.matched_same_admin,
                   b.granted_type,b.granted_level,b.granted_level_raw,b.scheduled_expiry,b.treated_by_log)) THEN
    RAISE EXCEPTION 'Association outside changed-action scope was altered';
  END IF;
END $$;

-- Frozen analytical products retain their original values and are explicitly
-- registered for review/rebuild. Their source population/medians can change,
-- so updating copied labels in place would leave inconsistent samples.
CREATE TABLE analysis.rfpp_intent_v2_invalidations (
 object_name text PRIMARY KEY, direct_changed_rows bigint,
 status text NOT NULL, reason text NOT NULL, recorded_at timestamptz DEFAULT now()
) TABLESPACE wiki_ts_lacie10;
DO $$ DECLARE t record; n bigint; BEGIN
 FOR t IN SELECT c.table_name FROM information_schema.columns c
          JOIN pg_class p ON p.relname=c.table_name AND p.relnamespace='analysis'::regnamespace
          WHERE c.table_schema='analysis' AND c.column_name='rfpp_id' AND p.relkind='r'
            AND c.table_name<>'rfpp_request' AND c.table_name NOT LIKE 'rfpp_intent_v2%'
            AND c.table_name<>'rfpp_request_pre_intent_v2'
 LOOP
   EXECUTE format('SELECT count(*) FROM analysis.%I t JOIN analysis.rfpp_intent_v2_changes c USING(rfpp_id)',t.table_name) INTO n;
   INSERT INTO analysis.rfpp_intent_v2_invalidations(object_name,direct_changed_rows,status,reason)
   VALUES ('analysis.'||t.table_name,n,'review_or_rebuild',
     'Frozen pre-intent-v2 product. Direct changed IDs counted; selection and grouped duration/eligibility effects can also affect other rows. Rebuild the dependency chain before combining with current classifications.');
 END LOOP;
END $$;
UPDATE analysis.rfpp_intent_v2_run SET status='applied',applied_at=now() WHERE id=1;
COMMENT ON COLUMN analysis.rfpp_request.requested_intent IS
'rfpp-intent-v2.0.0: request-only evidence, origin/target set, uncertainty, raw label, and parsing rule. Prior values and full source records retained in analysis.rfpp_request_pre_intent_v2; see changes and invalidations tables.';
ANALYZE analysis.rfpp_request;
SELECT count(*) AS population FROM analysis.rfpp_request;
SELECT count(*) AS changed_records,
 count(*) FILTER(WHERE old_action IS DISTINCT FROM new_action) AS action_changes,
 count(*) FILTER(WHERE old_level IS DISTINCT FROM new_level) AS tier_changes,
 count(*) FILTER(WHERE old_log_id IS DISTINCT FROM new_log_id) AS matched_log_changes
FROM analysis.rfpp_intent_v2_changes;
\if :commit_repair
 COMMIT;
\else
 ROLLBACK;
\endif
```

</details>
