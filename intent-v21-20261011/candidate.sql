-- Versioned RFPP intent parser. No response, outcome, or applied-tier inputs.
-- Install independently; this file does not update request rows.
\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION analysis.rfpp_intent_normalize_v21(raw text)
RETURNS text LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $fn$
DECLARE t text := coalesce(raw, '');
BEGIN
    t := regexp_replace(t, '\[\[[^]|]+\|([^]]+)\]\]', '\1', 'g');
    t := regexp_replace(t, '\[\[([^]]+)\]\]', '\1', 'g');
    t := regexp_replace(t, '<!--.*?-->|<[^>]*>', ' ', 'g');
    t := regexp_replace(t, '&nbsp;|&#160;|&ndash;|&mdash;|&#8211;|&#8212;', ' ', 'gi');
    -- SQL_ASCII treats translate() characters as bytes: multibyte punctuation
    -- would remove bytes from unrelated Unicode text. Replace whole sequences.
    t := replace(replace(t, '–', ' '), '—', ' ');
    t := translate(t, '-_', '  ');
    RETURN lower(btrim(regexp_replace(t, '[[:space:]]+', ' ', 'g')));
END $fn$;

CREATE OR REPLACE FUNCTION analysis.rfpp_intent_levels_v21(t text, label_mode boolean)
RETURNS text[] LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $fn$
SELECT coalesce(array_agg(tier ORDER BY ord), ARRAY[]::text[])
FROM (VALUES
 (1,'none',t ~ '\m(unprotection|unprotect)\M|\m(no protection|not protected|open editing)\M'),
 (2,'semi',t ~ '\m(semi|semiprotection|autoconfirmed)\M|\mauto confirmed\M'),
 (3,'ecp',t ~ '\mextended confirm(ed)?\M|\mecp\M' OR
          (t ~ '\mec\M' AND (label_mode OR t ~ '\mec protection\M'))),
 (4,'full',t ~ '\m(full|fully) protection\M' OR (label_mode AND t ~ '\mfull\M')),
 (5,'template',t ~ '\mtemplate (protection|editor)\M|\mtemplateeditor\M'),
 (6,'pc',t ~ '\mpending changes?\M|\mpc protection\M' OR (label_mode AND t ~ '\m(pc|pending)\M')),
 (7,'salt',t ~ '\m(creat(e|ion) protection|salt(ing)?)\M'),
 (8,'move',t ~ '\mmove protection\M'),
 (9,'upload',t ~ '\mupload protection\M')
) AS levels(ord,tier,matched) WHERE matched
$fn$;


-- Keep the requested operation separate from its rationale. These expressions
-- deliberately do not infer a tier from vandalism, editor credentials or outcome.
CREATE OR REPLACE FUNCTION analysis.rfpp_intent_clause_v21(t text)
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $fn$
SELECT btrim(regexp_replace(
    regexp_replace(regexp_replace(regexp_replace(t,
        '\m(requested action|requested protection level)[[:space:]]*:', '\1 ', 'g'),
        '\(not necessarily (indefinite|permanent)\)', ' ', 'g'),
        '\mif not already (done|protected)\M', ' ', 'g'),
    '\mreason[[:space:]]*:.*$|[:][[:space:]]*(persistent|high level|disrupt(ion|ive editing)?|vandalism|repeated|reason|this page)\M.*$|\m(because|since|due to|as|in order to|to (reduce|prevent|stop|avoid|help)|for the purpose of)\M.*$', ' '));
$fn$;

CREATE OR REPLACE FUNCTION analysis.rfpp_intent_direction_v21(t text)
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $fn$
SELECT CASE
 WHEN regexp_replace(btrim(t), '^(please[[:space:]]+)?(request(ing)?[[:space:]]+(to[[:space:]]+|for[[:space:]]+)?)?(temporary[[:space:]]+)?', '') ~ '^(please[[:space:]]+)?(unprotect(ion|ing)?|unsalt|remove|removal|removing|lift|lifting)\M'
      AND t ~ '\m(protection|semi|ecp|full|extended confirm(ed)?|pc|pending|salt(ing)?|unprotect(ion|ing)?)\M' THEN 'decrease'
 WHEN regexp_replace(btrim(t), '^(please[[:space:]]+)?(request(ing)?[[:space:]]+(to[[:space:]]+|for[[:space:]]+)?)?(temporary[[:space:]]+)?', '') ~ '^(please[[:space:]]+)?(reduce|reduction|downgrade|downgrading|lower|decrease)\M'
      AND t ~ '\m(protection|level|to|semi|ecp|full|extended confirm(ed)?)\M' THEN 'decrease'
 WHEN regexp_replace(btrim(t), '^(please[[:space:]]+)?(request(ing)?[[:space:]]+(to[[:space:]]+|for[[:space:]]+)?)?(temporary[[:space:]]+)?', '') ~ '^(please[[:space:]]+)?(increase|upgrade|escalate)\M' THEN 'increase'
 END;
$fn$;

CREATE OR REPLACE FUNCTION analysis.rfpp_parse_intent_v21(reason text)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $fn$
DECLARE
    raw_label text;
    leading_label text;
    requester text;
    label_tail text;
    continuation text;
    direction_text text;
    mixed_action boolean := false;
    removal boolean := false;
    target_phrase text;
    unresolved_alternative boolean := false;
    label text;
    evidence text;
    body text;
    part text;
    body_match text[];
    source text := 'label';
    status text := 'explicit';
    rule text := 'label_single_target';
    action text := 'increase';
    action_basis text := 'request_default';
    tier text;
    origin text;
    targets text[] := ARRAY[]::text[];
    found text[];
    transition text[];
    origins text[];
    origin_rank integer;
    target_rank integer;
    declared_action text;
    label_action text;
    extension boolean := false;
BEGIN
    IF reason IS NULL OR btrim(reason) = '' THEN
        RETURN jsonb_build_object('version','rfpp-intent-v2.1.0','status','unspecified',
            'rule','missing_reason','action',NULL,'tier',NULL,'targets',targets,
            'origin',NULL,'source',NULL,'action_basis','unknown','label_raw',NULL);
    END IF;
    -- Stop at the requester's first signature or the beginning of an RFPP
    -- response. Never promote a response's bold protection level to intent.
    requester := regexp_replace(reason, '\[\[(User([ _]talk)?:|Special:Contributions[/ :])[^\n]*[0-9]{1,2}:[0-9]{2},[^\n]*\(UTC\)[\s\S]*$', '', 'i');
    requester := regexp_replace(requester,
        '(?in)^[[:space:]]*:[[:space:]]*\[\[File:Pictogram[^\n]*([\s\S]*)$', '', 'i');
    raw_label := (regexp_match(requester, $re$'''(.*?)'''$re$))[1];
    -- Slice off the first heading before matching the next bold span.
    -- A greedy prefix on the same PostgreSQL regexp makes the whole match
    -- longest even when its final capture uses .*?.
    IF analysis.rfpp_intent_normalize_v21(raw_label) ~ '^(reason|protection|request|requested action|requested protection level)[:. ]*$' THEN
        label_tail := substring(requester FROM strpos(requester, $q$'''$q$) + length(raw_label) + 6);
        IF label_tail ~ $re$^[[:space:]:]*'''$re$ THEN
            leading_label := (regexp_match(label_tail, $re$'''(.*?)'''$re$))[1];
            IF leading_label IS NOT NULL THEN raw_label := leading_label; END IF;
        END IF;
    END IF;
    label := analysis.rfpp_intent_normalize_v21(raw_label);
    label := regexp_replace(label, '[:.[:space:]]+$', '');
    label_tail := substring(requester FROM strpos(requester, $q$'''$q$ || raw_label || $q$'''$q$) + length(raw_label) + 6);
    IF label_tail ~ '^[[:space:]:-]*(or\M|/|and\M)' THEN
        continuation := (regexp_match(label_tail, '^[[:space:]:-]*(?:or\M|/|and\M)[^\n.]*'))[1];
        label := label || ' ' || replace(analysis.rfpp_intent_normalize_v21(continuation), $q$'''$q$, '');
    END IF;
    evidence := label;
    label_action := analysis.rfpp_intent_direction_v21(label);
    IF raw_label ~* '<(s|del|strike)([[:space:]>])' THEN
        status := 'chronology_uncertain'; rule := 'amended_label';
        action := NULL; action_basis := 'unknown';
        targets := analysis.rfpp_intent_levels_v21(label, true);
    ELSE
        targets := analysis.rfpp_intent_levels_v21(label, true);
        IF label = '' OR label ~ '^(reason|protection|request|protect)$' OR
           (cardinality(targets)=0 AND label !~ '\m(edit request|unprotect|unprotection)\M') THEN
            source := 'body'; rule := 'body_explicit_request'; evidence := NULL;
            body := regexp_replace(requester, '\{\{[^{}]*\}\}', ' ', 'g');
            -- Avoid signatures and subsequent discussion when available.
            body := regexp_replace(body, '\[\[(User([ _]talk)?:|Special:Contributions[/ :]).*$', '', 'i');
            IF body ~* '<(s|del|strike)([[:space:]>])' THEN
                status := 'chronology_uncertain'; rule := 'amended_body';
                action := NULL; action_basis := 'unknown';
            ELSE
                body := analysis.rfpp_intent_normalize_v21(body);
                body := replace(body, $q$'''$q$, '');
                body := regexp_replace(body, '^[[:space:]*]*(reason|protection|request)[[:space:]]*:', '');
                IF label_action IS NOT NULL AND cardinality(targets)=0 THEN
                    body := regexp_replace(body, '^[[:space:]*]*[^:]*:', '');
                END IF;

                -- Search request clauses rather than the first tier mentioned.
                -- Multiple supported clauses remain ambiguous; no 400-char cap.
                body := regexp_replace(body, '\m(requested action|requested protection level)[[:space:]]*:', '\1 ', 'g');
                FOR part IN SELECT unnest(regexp_split_to_array(body, '[;.!?]|\mbut\M')) LOOP
                    IF part ~ '\m(not|never|do not|don''t)\M' THEN CONTINUE; END IF;
                    -- A target must be the object of a request phrase. A later
                    -- mention of disruptive autoconfirmed users is not a target.
                    body_match := regexp_match(part,
                        '\m((?:request(?:ing)?|remove|removal of|lift|reduce|downgrade to|apply|ask(?:ing)? for|would like|want|need|upgrade (?:it )?to|downgrade (?:it )?to|requested action|requested protection level)[[:space:]]+(?:(?:temporary|indefinite|permanent|long term|short term|a|an|the|some|at least)[[:space:]]+)*(?:semi|semiprotection|extended confirm(?:ed)?|ecp|full protection|pending changes|template protection|creation protection|create protection|move protection|upload protection|unprotection|protection|edit)\M.*)');
                    IF body_match IS NOT NULL THEN
                        IF part ~ '\mor\M.*\mextended protection\M' THEN
                            unresolved_alternative := true;
                        END IF;
                        IF part ~ '\munprotect(ion|ing)?\M.*\mor\M' THEN
                            IF evidence IS NULL THEN evidence := 'unprotection or';
                            ELSE evidence := evidence || '; unprotection or'; END IF;
                        END IF;
                        part := body_match[1];
                    ELSIF part ~ '\m(please|request(ing)?|could you|can you|would you)\M.*\munprotect\M' THEN
                        part := 'unprotection';
                    ELSIF part ~ '^[[:space:]]*unprotection[[:space:]]*$' THEN
                        part := 'unprotection';
                    ELSIF label_action IS NOT NULL AND part ~ '\mfrom\M.*\mto\M' THEN
                        part := substring(part FROM '\mfrom\M.*');
                    ELSIF part ~ '^[[:space:]]*(temporary|indefinite|extended)[[:space:]]+semi[[:space:]]+protection\M' THEN
                        NULL;
                    ELSIF part !~ '^[[:space:]]*(temporary[[:space:]]+)?semi([[:space:]]+protection)?[[:space:]]+is enough' THEN
                        CONTINUE;
                    END IF;
                    IF part IS NOT NULL THEN
                        part := analysis.rfpp_intent_clause_v21(part);
                        found := analysis.rfpp_intent_levels_v21(part, false);
                        IF cardinality(found)>0 OR analysis.rfpp_intent_direction_v21(part) IS NOT NULL OR part ~ '\mrequest(ing)? (an? )?edit\M(?![[:space:]]+protection)' THEN
                            IF evidence IS NULL THEN evidence := part;
                            ELSE evidence := evidence || '; ' || part; END IF;
                        END IF;
                    END IF;
                END LOOP;
                targets := analysis.rfpp_intent_levels_v21(coalesce(evidence,''), false);
                IF evidence IS NULL AND label_action IS NOT NULL THEN evidence := label; END IF;
                IF evidence IS NULL THEN action := NULL; action_basis := 'unknown'; END IF;
            END IF;
        END IF;
        IF status <> 'chronology_uncertain' THEN
            IF evidence ~ '\medit request\M|\mrequest(ing)? (an? )?edit\M(?![[:space:]]+protection)' AND NOT mixed_action THEN
                action := 'edit'; action_basis := 'explicit_request';
                targets := ARRAY[]::text[]; status := 'edit_request'; rule := 'edit_request';
            ELSE
                -- Direction verbs must govern the requested operation; rationale
                -- such as 'to reduce disruption' is excluded from this clause.
                evidence := analysis.rfpp_intent_clause_v21(evidence);
                declared_action := coalesce(analysis.rfpp_intent_direction_v21(evidence),label_action);
                IF declared_action IS NOT NULL THEN action := declared_action; action_basis := 'explicit_request'; END IF;
                IF action IS NULL AND cardinality(targets)>0 THEN action := 'increase'; action_basis := 'explicit_target'; END IF;
                transition := regexp_match(evidence, '\mfrom[[:space:]]+(.*?)[[:space:]]+to[[:space:]]+(.*)');
                IF transition IS NULL THEN
                    transition := regexp_match(evidence,
                        '^change[[:space:]]+(.*?)[[:space:]]+to[[:space:]]+(.*)');
                END IF;
                IF transition IS NOT NULL THEN
                    origins := analysis.rfpp_intent_levels_v21(transition[1], true);
                    targets := analysis.rfpp_intent_levels_v21(transition[2], true);
                    IF cardinality(origins)=1 THEN origin := origins[1]; END IF;
                    rule := 'explicit_transition';
                    -- Only compare edit tiers with an established ordering here.
                    origin_rank := array_position(ARRAY['none','semi','ecp','full'], origin);
                    target_rank := array_position(ARRAY['none','semi','ecp','full'], targets[1]);
                    IF cardinality(targets)=1 AND origin_rank IS NOT NULL AND target_rank IS NOT NULL THEN
                        action := CASE WHEN target_rank>origin_rank THEN 'increase'
                                       WHEN target_rank<origin_rank THEN 'decrease' ELSE 'change' END;
                        action_basis := 'explicit_transition';
                        IF declared_action IS NOT NULL AND declared_action<>action THEN
                            action := NULL; status := 'ambiguous'; rule := 'conflicting_direction';
                        END IF;
                    ELSIF declared_action IS NULL THEN
                        action := 'change'; action_basis := 'unordered_transition';
                    END IF;
                END IF;
                -- In removal wording the named level is an object/origin,
                -- not a destination. Do not collapse compound or partial removals.
                direction_text := regexp_replace(evidence, '^(please[[:space:]]+)?(request(ing)?[[:space:]]+(to[[:space:]]+|for[[:space:]]+)?)?', '');
                direction_text := regexp_replace(direction_text, '^(remove|removal)[[:space:]]*:[[:space:]]*', '\1 ');
                removal := direction_text ~ '^(please[[:space:]]+)?(remove|removal of|removing|lift|lifting of)[[:space:]]+(the[[:space:]]+)?(current[[:space:]]+|existing[[:space:]]+|unnecessary[[:space:]]+|indefinite[[:space:]]+)?(semi([[:space:]]+protection)?|extended confirm(ed)?([[:space:]]+protection)?|ecp([[:space:]]+protection)?|full([[:space:]]+protection)?|protection)\M';
                IF removal AND transition IS NULL AND evidence !~ '\m(to|and|or|but|only|keep|retain|except)\M' THEN
                    IF cardinality(targets)=1 AND targets[1] IN ('semi','ecp','full') THEN
                        origin := targets[1];
                    END IF;
                    IF cardinality(targets)<=1 AND (cardinality(targets)=0 OR targets[1] IN ('semi','ecp','full','none')) THEN
                        targets := ARRAY['none']; action := 'decrease';
                        action_basis := 'explicit_request'; rule := 'explicit_removal';
                    END IF;
                END IF;
                extension := coalesce(coalesce(evidence,label) ~ '\m(extend|extending|renew(al)?|longer)\M|\mextended\M(?![[:space:]]+confirmed)', false);
                IF cardinality(targets)=1 AND status<>'ambiguous' THEN
                    tier := targets[1];
                    IF tier='none' THEN action := 'decrease'; action_basis := 'explicit_request'; END IF;
                    -- Negated or quoted labels are not single-target evidence.
                    IF evidence ~ '\m(not|never|rather than|instead of)\M' THEN
                        tier := NULL; status := 'ambiguous'; rule := 'negated_label';
                    END IF;
                ELSIF cardinality(targets)>1 THEN
                    status := CASE WHEN evidence ~ '\mor\M|/' THEN 'alternative' ELSE 'ambiguous' END;
                    rule := 'multiple_targets';
                    IF 'none'=ANY(targets) THEN action := NULL; action_basis := 'unknown'; END IF;
                ELSIF cardinality(targets)=0 AND status<>'edit_request' THEN
                    status := 'unspecified'; rule := 'no_supported_target'; source := NULL;
                END IF;
            END IF;
        END IF;
    END IF;
    IF action='decrease' AND cardinality(targets)=1 AND targets[1] IN ('pc','salt','move','upload')
       AND evidence ~ '\m(remove|removal|lift|unsalt)\M' THEN
        origin := targets[1]; tier := NULL; targets := ARRAY[]::text[];
        status := 'ambiguous'; rule := 'non_edit_removal';
    END IF;
    IF cardinality(targets)>1 AND evidence ~ '[,;&][[:space:]]*(remove|lift|unprotect)\M' THEN
        tier := NULL; action := NULL; action_basis := 'unknown'; status := 'ambiguous'; rule := 'compound_request';
    END IF;
    mixed_action := coalesce(evidence ~ '\m(or|alternatively)[[:space:]]+((an?[[:space:]]+)?edit[[:space:]]+(to|the|this|that|it|article|page)\M|an?[[:space:]]+edit\M)',false);
    IF mixed_action AND status <> 'chronology_uncertain' THEN
        tier := NULL; action := NULL; action_basis := 'unknown';
        status := 'alternative'; rule := 'mixed_action_alternative';
    END IF;
    IF evidence ~ '\mor[[:space:]]+(lower|higher)\M' AND status <> 'chronology_uncertain' THEN
        tier := NULL; action := NULL; action_basis := 'unknown'; status := 'ambiguous'; rule := 'open_target_alternative';
    END IF;
    IF status <> 'chronology_uncertain' AND (
       evidence ~ '\mor[[:space:]]+(just[[:space:]]+)?(remove|removal|block|at least reduction)\M'
       OR evidence ~ '^(protection|extended)[[:space:]]+or\M') THEN
        tier := NULL; action := NULL; action_basis := 'unknown';
        status := 'alternative'; rule := 'unsupported_operation_alternative';
    END IF;
    IF unresolved_alternative THEN
        tier := NULL; status := 'ambiguous'; rule := 'unsupported_alternative';
    END IF;
    RETURN jsonb_build_object('version','rfpp-intent-v2.1.0','status',status,'rule',rule,
        'action',action,'tier',tier,'targets',targets,'origin',origin,'source',source,
        'action_basis',action_basis,'duration_extension',extension,'label_raw',raw_label,
        'label',label,'evidence',evidence);
END $fn$;
