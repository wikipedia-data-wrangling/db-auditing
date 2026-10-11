-- Versioned RFPP intent parser. No response, outcome, or applied-tier inputs.
-- Install independently; this file does not update request rows.
\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION analysis.rfpp_intent_normalize_v2(raw text)
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

CREATE OR REPLACE FUNCTION analysis.rfpp_intent_levels_v2(t text, label_mode boolean)
RETURNS text[] LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $fn$
SELECT coalesce(array_agg(tier ORDER BY ord), ARRAY[]::text[])
FROM (VALUES
 (1,'none',t ~ '\m(unprotection|unprotect)\M|\m(no protection|not protected|open editing)\M'),
 (2,'semi',t ~ '\m(semi|semiprotection|autoconfirmed)\M|\mauto confirmed\M'),
 (3,'ecp',t ~ '\mextended confirmed\M|\mecp\M' OR
          (t ~ '\mec\M' AND (label_mode OR t ~ '\mec protection\M'))),
 (4,'full',t ~ '\m(full|fully) protection\M' OR (label_mode AND t ~ '\mfull\M')),
 (5,'template',t ~ '\mtemplate (protection|editor)\M|\mtemplateeditor\M'),
 (6,'pc',t ~ '\mpending changes?\M|\mpc protection\M' OR (label_mode AND t ~ '\m(pc|pending)\M')),
 (7,'salt',t ~ '\m(creat(e|ion) protection|salt(ing)?)\M'),
 (8,'move',t ~ '\mmove protection\M'),
 (9,'upload',t ~ '\mupload protection\M')
) AS levels(ord,tier,matched) WHERE matched
$fn$;

CREATE OR REPLACE FUNCTION analysis.rfpp_parse_intent_v2(reason text)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $fn$
DECLARE
    raw_label text;
    leading_label text;
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
        RETURN jsonb_build_object('version','rfpp-intent-v2.0.0','status','unspecified',
            'rule','missing_reason','action',NULL,'tier',NULL,'targets',targets,
            'origin',NULL,'source',NULL,'action_basis','unknown','label_raw',NULL);
    END IF;
    -- No 80-character limit: retain the original extracted label as evidence.
    raw_label := (regexp_match(reason, $re$'''(.*?)'''$re$))[1];
    -- Generic form headings can precede the actual bold request label.
    IF analysis.rfpp_intent_normalize_v2(raw_label) ~ '^(reason|protection|request)[:. ]*$' THEN
        leading_label := (regexp_match(reason,
            $re$'''(?:Reason|Protection|Request)[:.[:space:]]*'''[[:space:]]*'''(.*?)'''$re$, 'i'))[1];
        IF leading_label IS NOT NULL THEN raw_label := leading_label; END IF;
    END IF;
    label := analysis.rfpp_intent_normalize_v2(raw_label);
    label := regexp_replace(label, '[:.[:space:]]+$', '');
    evidence := label;
    IF label ~ '\m(unprotect|unprotection|reduc(e|tion)|downgrad(e|ing)|lower|remov(e|al|ing)|lift|decrease)\M' THEN
        label_action := 'decrease';
    ELSIF label ~ '\m(increase|upgrade|escalate)\M' THEN label_action := 'increase'; END IF;
    IF raw_label ~* '<(s|del|strike)([[:space:]>])' THEN
        status := 'chronology_uncertain'; rule := 'amended_label';
        action := NULL; action_basis := 'unknown';
        targets := analysis.rfpp_intent_levels_v2(label, true);
    ELSE
        targets := analysis.rfpp_intent_levels_v2(label, true);
        IF label = '' OR label ~ '^(reason|protection|request|protect)$' OR
           (cardinality(targets)=0 AND label !~ '\m(edit request|unprotect|unprotection)\M') THEN
            source := 'body'; rule := 'body_explicit_request'; evidence := NULL;
            body := regexp_replace(reason, '\{\{[^{}]*\}\}', ' ', 'g');
            -- Avoid signatures and subsequent discussion when available.
            body := regexp_replace(body, '\[\[(User|User talk|Special:Contributions):.*$', '', 'i');
            IF body ~* '<(s|del|strike)([[:space:]>])' THEN
                status := 'chronology_uncertain'; rule := 'amended_body';
                action := NULL; action_basis := 'unknown';
            ELSE
                body := analysis.rfpp_intent_normalize_v2(body);
                body := replace(body, $q$'''$q$, '');
                body := regexp_replace(body, '^reason[[:space:]]*:', '');
                -- Search request clauses rather than the first tier mentioned.
                -- Multiple supported clauses remain ambiguous; no 400-char cap.
                FOR part IN SELECT unnest(regexp_split_to_array(body, '[;.!?]|\mbut\M')) LOOP
                    IF part ~ '\m(not|never|do not|don''t)\M' THEN CONTINUE; END IF;
                    -- A target must be the object of a request phrase. A later
                    -- mention of disruptive autoconfirmed users is not a target.
                    body_match := regexp_match(part,
                        '\m(request(ing)?|apply|ask(ing)? for|would like|want|need|upgrade (it )?to|downgrade (it )?to)[[:space:]]+(((temporary|indefinite|permanent|long term|short term|a|an|the|some|at least)[[:space:]]+)*(semi|semiprotection|extended confirmed|ecp|full protection|pending changes|template protection|creation protection|create protection|move protection|upload protection|unprotection)\M.*)');
                    IF body_match IS NOT NULL THEN
                        IF part ~ '\mor\M.*\mextended protection\M' THEN
                            unresolved_alternative := true;
                        END IF;
                        IF part ~ '\munprotect(ion|ing)?\M.*\mor\M' THEN
                            IF evidence IS NULL THEN evidence := 'unprotection or';
                            ELSE evidence := evidence || '; unprotection or'; END IF;
                        END IF;
                        part := body_match[1] || ' ' || body_match[6];
                        part := regexp_replace(part, '\m(because|since|due to|as)\M.*$', '');
                    ELSIF part ~ '\m(please|request(ing)?|could you|can you|would you)\M.*\munprotect\M' THEN
                        part := 'unprotection';
                    ELSIF part !~ '^[[:space:]]*(temporary[[:space:]]+)?semi([[:space:]]+protection)?[[:space:]]+is enough' THEN
                        CONTINUE;
                    END IF;
                    IF part IS NOT NULL THEN
                        found := analysis.rfpp_intent_levels_v2(part, false);
                        IF cardinality(found)>0 THEN
                            IF evidence IS NULL THEN evidence := part;
                            ELSE evidence := evidence || '; ' || part; END IF;
                        END IF;
                    END IF;
                END LOOP;
                targets := analysis.rfpp_intent_levels_v2(coalesce(evidence,''), false);
                IF evidence IS NULL AND label_action IS NOT NULL THEN evidence := label; END IF;
                IF evidence IS NULL THEN action := NULL; action_basis := 'unknown'; END IF;
            END IF;
        END IF;
        IF status <> 'chronology_uncertain' THEN
            IF evidence ~ '\medit request\M' THEN
                action := 'edit'; action_basis := 'explicit_request';
                targets := ARRAY[]::text[]; status := 'edit_request'; rule := 'edit_request';
            ELSE
                declared_action := label_action;
                IF evidence ~ '\m(unprotect|unprotection|reduc(e|tion)|downgrad(e|ing)|lower|remov(e|al|ing)|lift|decrease)\M' THEN
                    declared_action := 'decrease';
                ELSIF evidence ~ '\m(increase|upgrade|escalate)\M' THEN declared_action := 'increase'; END IF;
                IF declared_action IS NOT NULL THEN action := declared_action; action_basis := 'explicit_request'; END IF;
                IF action IS NULL AND cardinality(targets)>0 THEN action := 'increase'; action_basis := 'explicit_target'; END IF;
                transition := regexp_match(evidence, '\mfrom[[:space:]]+(.*?)[[:space:]]+to[[:space:]]+(.*)');
                IF transition IS NOT NULL THEN
                    origins := analysis.rfpp_intent_levels_v2(transition[1], true);
                    targets := analysis.rfpp_intent_levels_v2(transition[2], true);
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
    IF unresolved_alternative THEN
        tier := NULL; status := 'ambiguous'; rule := 'unsupported_alternative';
    END IF;
    RETURN jsonb_build_object('version','rfpp-intent-v2.0.0','status',status,'rule',rule,
        'action',action,'tier',tier,'targets',targets,'origin',origin,'source',source,
        'action_basis',action_basis,'duration_extension',extension,'label_raw',raw_label,
        'label',label,'evidence',evidence);
END $fn$;
