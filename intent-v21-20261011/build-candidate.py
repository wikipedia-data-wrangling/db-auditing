# Historical prototype generator; candidate.sql is the finalized source.
raise SystemExit("Use candidate.sql; this prototype generator omits later reviewed refinements.")
"""Build an independently installable v2.1 candidate from the preserved v2 source."""
from pathlib import Path

ROOT=Path(__file__).resolve().parent
s=(ROOT/'parser-before.sql').read_text().replace('_v2(', '_v21(').replace('rfpp-intent-v2.0.0','rfpp-intent-v2.1.0')
def change(old,new):
    global s
    assert old in s, old
    s=s.replace(old,new)

change(r'\mextended confirmed\M', r'\mextended confirm(ed)?\M')
change('    leading_label text;', '''    leading_label text;
    requester text;
    label_tail text;
    continuation text;
    direction_text text;
    mixed_action boolean := false;
    removal boolean := false;
    target_phrase text;''')
change("    -- No 80-character limit: retain the original extracted label as evidence.\n    raw_label := (regexp_match(reason, $re$'''(.*?)'''$re$))[1];", r"""    -- Stop at the requester's first signature or the beginning of an RFPP
    -- response. Never promote a response's bold protection level to intent.
    requester := regexp_replace(reason, '\[\[(User([ _]talk)?:|Special:Contributions[/ :])[^\n]*[0-9]{1,2}:[0-9]{2},[^\n]*\(UTC\)[\s\S]*$', '', 'i');
    requester := regexp_replace(requester,
        '(?in)^[[:space:]]*:[[:space:]]*\[\[File:Pictogram[^\n]*([\s\S]*)$', '', 'i');
    raw_label := (regexp_match(requester, $re$'''(.*?)'''$re$))[1];""")
start=s.index('    -- Generic form headings')
end=s.index('    label := analysis.',start)
s=s[:start]+r"""    -- Slice off the first heading before matching the next bold span.
    -- A greedy prefix on the same PostgreSQL regexp makes the whole match
    -- longest even when its final capture uses .*?.
    IF analysis.rfpp_intent_normalize_v21(raw_label) ~ '^(reason|protection|request|requested action|requested protection level)[:. ]*$' THEN
        label_tail := substring(requester FROM strpos(requester, $q$'''$q$) + length(raw_label) + 6);
        IF label_tail ~ $re$^[[:space:]:]*'''$re$ THEN
            leading_label := (regexp_match(label_tail, $re$'''(.*?)'''$re$))[1];
            IF leading_label IS NOT NULL THEN raw_label := leading_label; END IF;
        END IF;
    END IF;
"""+s[end:]
change("    evidence := label;", r"""    label_tail := substring(requester FROM strpos(requester, $q$'''$q$ || raw_label || $q$'''$q$) + length(raw_label) + 6);
    IF label_tail ~ '^[[:space:]:-]*(or\M|/|and\M)' THEN
        continuation := (regexp_match(label_tail, '^[[:space:]:-]*(?:or\M|/|and\M)[^\n.]*'))[1];
        label := label || ' ' || replace(analysis.rfpp_intent_normalize_v21(continuation), $q$'''$q$, '');
    END IF;
    evidence := label;""")
start=s.index("    IF label ~ '\\m(unprotect")
end=s.index('    IF raw_label ~*',start)
s=s[:start]+r"""    label_action := analysis.rfpp_intent_direction_v21(label);
"""+s[end:]
change("            body := regexp_replace(reason,", "            body := regexp_replace(requester,")
change("                body := regexp_replace(body, '^reason[[:space:]]*:', '');",r"""                body := regexp_replace(body, '^[[:space:]*]*(reason|protection|request)[[:space:]]*:', '');
                IF label_action IS NOT NULL AND cardinality(targets)=0 THEN
                    body := regexp_replace(body, '^[[:space:]*]*[^:]*:', '');
                END IF;
""")
change("                    IF part ~ '\\m(not|never|do not|don''t)\\M' THEN CONTINUE; END IF;",r"""                    IF part ~ '\m(not|never|do not|don''t)\M' THEN CONTINUE; END IF;""")
start=s.index('                    body_match := regexp_match(part,')
end=s.index('                    IF part IS NOT NULL THEN',start)
s=s[:start]+r"""                    body_match := regexp_match(part,
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
"""+s[end:]
change("                FOR part IN SELECT", r"""                body := regexp_replace(body, '\m(requested action|requested protection level)[[:space:]]*:', '\1 ', 'g');
                FOR part IN SELECT""")
change('                        found := analysis.rfpp_intent_levels_v21(part, false);', '                        part := analysis.rfpp_intent_clause_v21(part);\n                        found := analysis.rfpp_intent_levels_v21(part, false);')
change('                        IF cardinality(found)>0 THEN',r"""                        IF cardinality(found)>0 OR analysis.rfpp_intent_direction_v21(part) IS NOT NULL OR part ~ '\mrequest(ing)? (an? )?edit\M(?![[:space:]]+protection)' THEN""")
change("            IF evidence ~ '\\medit request\\M' THEN",r"""            IF evidence ~ '\medit request\M|\mrequest(ing)? (an? )?edit\M(?![[:space:]]+protection)' AND NOT mixed_action THEN""")
start=s.index('                declared_action := label_action;')
end=s.index('                IF declared_action IS NOT NULL THEN',start)
s=s[:start]+r"""                -- Direction verbs must govern the requested operation; rationale
                -- such as 'to reduce disruption' is excluded from this clause.
                evidence := analysis.rfpp_intent_clause_v21(evidence);
                declared_action := coalesce(analysis.rfpp_intent_direction_v21(evidence),label_action);
"""+s[end:]
change("                IF transition IS NOT NULL THEN",r"""                IF transition IS NULL THEN
                    transition := regexp_match(evidence,
                        '^change[[:space:]]+(.*?)[[:space:]]+to[[:space:]]+(.*)');
                END IF;
                IF transition IS NOT NULL THEN""")
start=s.index('                extension :=')
s=s[:start]+r"""                -- In removal wording the named level is an object/origin,
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
"""+s[start:]
change("    IF unresolved_alternative THEN",r"""    IF action='decrease' AND cardinality(targets)=1 AND targets[1] IN ('pc','salt','move','upload')
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
    IF unresolved_alternative THEN""")

helpers=r"""
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

"""
position=s.index('CREATE OR REPLACE FUNCTION analysis.rfpp_parse_intent_v21')
s=s[:position]+helpers+s[position:]
s=s.replace(r'\[\[(User|User talk|Special:Contributions):.*$', r'\[\[(User([ _]talk)?:|Special:Contributions[/ :]).*$')
(ROOT/'candidate.sql').write_text(s)
tests=(ROOT/'tests-before.py').read_text().replace('rfpp_parse_intent_v2','rfpp_parse_intent_v21').replace('rfpp-intent-v2.0.0','rfpp-intent-v2.1.0')
tests=tests.replace("('removal of unnecessary protection', None, 'decrease', 'unspecified')", "('removal of unnecessary protection', 'none', 'decrease', 'explicit')")
tests=tests.replace("\nif __name__ == '__main__':", '\n'+(ROOT/'extra-tests.fragment').read_text()+"\nif __name__ == '__main__':")
(ROOT/'test_candidate.py').write_text(tests)
fixtures=(ROOT.parent/'rfpp-intent-validation-20261011/check-fixtures.sql').read_text().replace('rfpp_parse_intent_v2(', 'rfpp_parse_intent_v21(')
(ROOT/'check-fixtures.sql').write_text(fixtures)
