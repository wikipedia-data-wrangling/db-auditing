"""Behavioral regression cases for the PostgreSQL RFPP intent parser."""
import json
import unittest

import psycopg


class IntentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.conn = psycopg.connect('service=wiki', autocommit=True,
                                   options='-c client_encoding=UTF8',
                                   application_name='rfpp-intent-v2-tests')
        cls.conn.execute('BEGIN READ ONLY')

    @classmethod
    def tearDownClass(cls):
        cls.conn.execute('ROLLBACK')
        cls.conn.close()

    def parse(self, reason):
        return self.conn.execute('SELECT analysis.rfpp_parse_intent_v21(%s)', (reason,)).fetchone()[0]

    def test_labels(self):
        cases = [
            ('extended semi-protection', 'semi', 'increase', 'explicit'),
            ('extended semi protection', 'semi', 'increase', 'explicit'),
            ('extended temporary semi-protection', 'semi', 'increase', 'explicit'),
            ('temporary extended confirmed protection', 'ecp', 'increase', 'explicit'),
            ('extended-confirmed protection', 'ecp', 'increase', 'explicit'),
            ('semi-protection', 'semi', 'increase', 'explicit'),
            ('from semi-protection to extended confirmed', 'ecp', 'increase', 'explicit'),
            ('from extended confirmed protection to semi', 'semi', 'decrease', 'explicit'),
            ('change from extended-confirmed-protection to semi', 'semi', 'decrease', 'explicit'),
            ('reduce from full-protection to semi-protection', 'semi', 'decrease', 'explicit'),
            ('increase from semi-protection to full-protection', 'full', 'increase', 'explicit'),
            ('upgrade from pending changes to semi-protection', 'semi', 'increase', 'explicit'),
            ('from pending changes to semi-protection', 'semi', 'change', 'explicit'),
            ('extended confirmed or semi-protection', None, 'increase', 'alternative'),
            ('temporary <s>extended confirmed</s> semi', None, None, 'chronology_uncertain'),
            ('extended protection', None, None, 'unspecified'),
            ('Reason: extend current protection', None, None, 'unspecified'),
            ('reduction in protection level', None, 'decrease', 'unspecified'),
            ('removal of unnecessary protection', 'none', 'decrease', 'explicit'),
            ('unprotection', 'none', 'decrease', 'explicit'),
            ('Edit request', None, 'edit', 'edit_request'),
            ('temporary or indefinite semi-protection', 'semi', 'increase', 'explicit'),
            ('indefinite template protection', 'template', 'increase', 'explicit'),
            ('temporary creation protection', 'salt', 'increase', 'explicit'),
            ('temporary move protection', 'move', 'increase', 'explicit'),
            ('temporary full protection', 'full', 'increase', 'explicit'),
            ('ECP', 'ecp', 'increase', 'explicit'),
            ('temporary EC protection', 'ecp', 'increase', 'explicit'),
            ('Extended&nbsp;Confirmed Protection', 'ecp', 'increase', 'explicit'),
            ('[[WP:ECP|extended-confirmed protection]]', 'ecp', 'increase', 'explicit'),
            ('temporary semi protection and full protection', None, 'increase', 'ambiguous'),
            ('increase from extended confirmed to semi', None, None, 'ambiguous'),
            ('not ECP', None, 'increase', 'ambiguous'),
        ]
        for label, tier, action, status in cases:
            with self.subTest(label=label):
                parsed = self.parse("'''" + label + ":''' Reason text.")
                self.assertEqual((parsed['tier'], parsed['action'], parsed['status']),
                                 (tier, action, status))

    def test_body_intent(self):
        cases = [
            ("'''Reason:''' Semi failed; please apply extended confirmed protection.", 'ecp'),
            ("'''Reason:''' Not ECP; temporary semi is enough.", 'semi'),
            ("'''Protection:''' Please apply extended confirmed protection.", 'ecp'),
            ("'''Reason:''' " + ('Background. ' * 60) + 'Please apply semi-protection.', 'semi'),
            ("'''Reason:''' Previous ECP was removed. Persistent vandalism.", None),
            ("'''Reason:''' Please do not apply ECP.", None),
            ("'''Reason:''' Please increase protection because autoconfirmed users are disrupting it.", None),
            ("'''Reason:''' Please apply ECP because semi protection failed.", 'ecp'),
            (None, None),
            ('', None),
        ]
        for reason, tier in cases:
            with self.subTest(reason=reason):
                self.assertEqual(self.parse(reason)['tier'], tier)
        parsed = self.parse("'''Reason:''' Could you downgrade it to pending changes?")
        self.assertEqual((parsed['tier'], parsed['action']), ('pc', 'decrease'))

    def test_nested_heading_and_partial_alternatives(self):
        parsed = self.parse("'''Reason:''' '''Temporary semi-protection''' Vandalism.")
        self.assertEqual(parsed['tier'], 'semi')
        parsed = self.parse("'''Reason:''' Try unprotecting this page or downgrade it to pending changes.")
        self.assertIsNone(parsed['tier'])
        self.assertEqual(set(parsed['targets']), {'none', 'pc'})
        parsed = self.parse("'''Reason:''' Request semi protection or extended protection.")
        self.assertIsNone(parsed['tier'])
        self.assertEqual(parsed['status'], 'ambiguous')

    def test_long_label_and_provenance(self):
        label = 'temporary ' + ' ' * 100 + 'semi-protection'
        parsed = self.parse("'''" + label + "''' Vandalism.")
        self.assertEqual(parsed['tier'], 'semi')
        self.assertEqual(parsed['label_raw'], label)
        self.assertEqual(parsed['version'], 'rfpp-intent-v2.1.0')
        self.assertTrue(self.parse("'''extended semi-protection''' Test.")['duration_extension'])
        self.assertFalse(self.parse("'''extended confirmed protection''' Test.")['duration_extension'])

    def test_unicode_bytes_preserved_on_sql_ascii(self):
        parsed = self.parse("'''Mike•Owen''' Context.")
        self.assertEqual(parsed['label'], 'mike•owen')
        for dash in ['–', '—']:
            parsed = self.parse("'''extended" + dash + "confirmed protection''' Test.")
            self.assertEqual(parsed['tier'], 'ecp')
        parsed = self.parse("'''Semi-protection''' Café 日本語 • quotation “text”.")
        self.assertEqual(parsed['tier'], 'semi')

    def test_alternative_targets_and_origin(self):
        parsed = self.parse("'''extended confirmed or semi-protection''' Test.")
        self.assertEqual(set(parsed['targets']), {'ecp', 'semi'})
        parsed = self.parse("'''from semi to extended confirmed''' Test.")
        self.assertEqual(parsed['origin'], 'semi')
        self.assertEqual(parsed['targets'], ['ecp'])

    def test_historical_fixtures(self):
        expected = {737: ('semi', 'increase'), 4219: ('semi', 'increase'),
                    5302: ('semi', 'increase'), 12914: ('semi', 'increase'),
                    30062: ('semi', 'increase'), 127462: ('semi', 'decrease'),
                    144377: ('semi', 'decrease'), 154614: ('ecp', 'increase'),
                    91188: (None, 'increase'), 192925: (None, None)}
        rows = self.conn.execute('SELECT rfpp_id,analysis.rfpp_parse_intent_v21(reason) '
                                 'FROM analysis.rfpp_request WHERE rfpp_id=ANY(%s)',
                                 (list(expected),)).fetchall()
        self.assertEqual(len(rows), len(expected))
        for identifier, parsed in rows:
            with self.subTest(rfpp_id=identifier):
                self.assertEqual((parsed['tier'], parsed['action']), expected[identifier])


    def test_repair_cases_and_guards(self):
        cases = [
            ("'''Semi-protection''' or block the disruptive user.", {'tier':None,'status':'alternative'}),
            ("'''Unprotection''' or at least reduction to TE protection.", {'tier':None,'status':'alternative'}),
            ("'''Protection''' or '''Semi-protection'''", {'tier':None,'status':'alternative'}),
            ("'''Semi-protect for month or more'''", {'tier':'semi','action':'increase'}),
            ("'''Pending changes protection for 1 month or less'''", {'tier':'pc','action':'increase'}),
            ("'''Removal of PC'''", {'action':'decrease'}),
            ("'''Request removal of semi-protection'''", {'tier':'none','action':'decrease'}),
            ("'''Remove: Extended Confirmed protection:'''", {'tier':'none','action':'decrease'}),
            ("* [[User:Example]]\n'''Semi-protection''' Please protect.", {'tier':'semi'}),
            ("'''Reason:''' Requesting edit protection.", {'tier':None,'action':None}),
            ("'''Reason:''' Months have passed since his funeral, so request unprotection.", {'tier':'none','action':'decrease'}),
            ("'''Reason:''' Requesting semi protection because edits are unsourced or edit wars occur.", {'tier':'semi','action':'increase'}),
            ("'''Reason:''' '''Unprotect''' - or at least '''Semi-protect'''", {'tier':None,'status':'alternative'}),
            ("'''Reason:''' '''Permanently full-protect''' or '''permanently extended confirmed protect'''", {'tier':None,'status':'alternative'}),
            ("'''Semi-protection or lower'''", {'tier':None,'status':'ambiguous'}),
            ("'''Reason:''' Requesting semi protection to reduce disruption.", {'tier':'semi','action':'increase'}),
            ("'''Reason:''' Requesting semi protection to prevent removal of sourced material.", {'tier':'semi','action':'increase'}),
            ("'''Reason:''' Please remove semi-protection.", {'tier':'none','origin':'semi','action':'decrease'}),
            ("'''Reason:''' Remove protection.", {'tier':'none','action':'decrease'}),
            ("'''Reason:''' Reduce protection to semi.", {'tier':'semi','action':'decrease'}),
            ("'''Remove semi-protection'''", {'tier':'none','origin':'semi','action':'decrease'}),
            ("'''Removal of extended confirmed protection'''", {'tier':'none','origin':'ecp','action':'decrease'}),
            ("'''Remove full protection'''", {'tier':'none','origin':'full','action':'decrease'}),
            ("'''Remove semi-protection and retain pending changes'''", {'tier':None,'status':'ambiguous'}),
            ("'''Reduce to semi-protection'''", {'tier':'semi','action':'decrease'}),
            ("'''Reason:''' Request full protection or edit the article to remove disputed information.", {'tier':None,'action':None,'rule':'mixed_action_alternative'}),
            ("'''Reason:''' Request semi protection because the old full protection was removed.", {'tier':'semi','action':'increase'}),
            ("'''Reason:''' Request indefinite move protection: disruption by autoconfirmed users.", {'tier':'move','targets':['move']}),
            ("'''Reason:''' '''Temporary semi-protection''' A rationale '''with bold words'''", {'label_raw':'Temporary semi-protection','tier':'semi'}),
            ("'''Reason:''' Unprotection [[Special:Contributions/1.2.3.4|1.2.3.4]]", {'tier':'none','action':'decrease'}),
            ("'''Long-term (not necessarily indefinite) full protection'''", {'tier':'full'}),
            ("'''Salting if not already done'''", {'tier':'salt'}),
            ("'''Do not renew semi-protection'''", {'tier':None,'status':'ambiguous'}),
            ("'''Reason:''' Persistent vandalism. [[User:Requester|R]]\n'''Full protection'''", {'tier':None}),
            ("'''Reason:''' Persistent vandalism. [[User_talk:Requester|R]]\n'''Full protection'''", {'tier':None}),
            ("Persistent vandalism.\n:[[File:Pictogram voting support.svg|20px]] '''Full protection'''", {'tier':None}),
        ]
        for reason,expected in cases:
            with self.subTest(reason=reason):
                actual=self.parse(reason)
                for key,value in expected.items():
                    self.assertEqual(actual.get(key),value,(key,actual))


    def test_saved_diagnostic_fixtures(self):
        cases = [{'case_id': 'live-5270', 'rfpp_id': 5270, 'expected': {'tier': 'semi', 'origin': 'pc', 'action': 'change'}}, {'case_id': 'live-214872', 'rfpp_id': 214872, 'expected': {'targets': ['move']}}, {'case_id': 'live-8243', 'rfpp_id': 8243, 'expected': {'tier': 'salt'}}, {'case_id': 'live-44093', 'rfpp_id': 44093, 'expected': {'tier': 'full'}}, {'case_id': 'live-137153', 'rfpp_id': 137153, 'expected': {'tier': 'semi'}}, {'case_id': 'live-173498', 'rfpp_id': 173498, 'expected': {'label_raw': 'Request increase of duration of current page protection'}}, {'case_id': 'live-192177', 'rfpp_id': 192177, 'expected': {'tier': 'semi', 'label_raw': 'Temporary semi-protection'}}, {'case_id': 'live-114550', 'rfpp_id': 114550, 'expected': {'tier': 'semi', 'origin': 'ecp', 'action': 'decrease'}}, {'case_id': 'live-162248', 'rfpp_id': 162248, 'expected': {'tier': 'ecp'}}, {'case_id': 'live-183512', 'rfpp_id': 183512, 'expected': {'tier': 'none', 'action': 'decrease'}}, {'case_id': 'live-204731', 'rfpp_id': 204731, 'expected': {'action': 'edit'}}, {'case_id': 'live-212374', 'rfpp_id': 212374, 'expected': {'tier': 'ecp'}}, {'case_id': 'live-185991', 'rfpp_id': 185991, 'expected': {'tier': 'semi', 'action': 'increase'}}, {'case_id': 'live-198445', 'rfpp_id': 198445, 'expected': {'tier': 'semi', 'action': 'increase'}}, {'case_id': 'live-5784', 'rfpp_id': 5784, 'expected': {'tier': 'none', 'action': 'decrease'}}, {'case_id': 'synthetic-1', 'reason': "'''Reason:''' '''Temporary semi-protection''' Body '''other text'''", 'expected': {'label_raw': 'Temporary semi-protection', 'tier': 'semi'}}, {'case_id': 'synthetic-2', 'reason': "'''Long-term (not necessarily indefinite) full protection'''", 'expected': {'tier': 'full'}}, {'case_id': 'synthetic-3', 'reason': "'''Reason:''' Requesting semi protection to reduce disruption.", 'expected': {'action': 'increase', 'tier': 'semi'}}, {'case_id': 'synthetic-4', 'reason': "'''Remove semi-protection'''", 'expected': {'action': 'decrease', 'tier': 'none'}}, {'case_id': 'synthetic-5', 'reason': "'''Change PC protection to semi-protection'''", 'expected': {'action': 'change', 'origin': 'pc', 'tier': 'semi'}}, {'case_id': 'synthetic-6', 'reason': "'''Reason:''' Unprotection", 'expected': {'action': 'decrease', 'tier': 'none'}}, {'case_id': 'synthetic-7', 'reason': "'''extended protection'''", 'expected': {'tier': None}}, {'case_id': 'synthetic-8', 'reason': "'''extended semi-protection'''", 'expected': {'tier': 'semi'}}, {'case_id': 'synthetic-9', 'reason': "'''Reason:''' Previous ECP was removed. Persistent vandalism.", 'expected': {'tier': None}}, {'case_id': 'synthetic-10', 'reason': "'''temporary <s>extended confirmed</s> semi'''", 'expected': {'tier': None, 'status': 'chronology_uncertain'}}]
        for case in cases:
            with self.subTest(case_id=case['case_id']):
                if 'rfpp_id' in case:
                    row=self.conn.execute('SELECT reason FROM analysis.rfpp_request WHERE rfpp_id=%s',(case['rfpp_id'],)).fetchone()
                    self.assertIsNotNone(row)
                    reason=row[0]
                else:
                    reason=case['reason']
                actual=self.parse(reason)
                for key,value in case['expected'].items():
                    self.assertEqual(actual.get(key),value,(key,actual))


if __name__ == '__main__':
    unittest.main(verbosity=2)
