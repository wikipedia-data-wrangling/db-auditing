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
        return self.conn.execute('SELECT analysis.rfpp_parse_intent_v2(%s)', (reason,)).fetchone()[0]

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
            ('removal of unnecessary protection', None, 'decrease', 'unspecified'),
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
        self.assertEqual(parsed['version'], 'rfpp-intent-v2.0.0')
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
        rows = self.conn.execute('SELECT rfpp_id,analysis.rfpp_parse_intent_v2(reason) '
                                 'FROM analysis.rfpp_request WHERE rfpp_id=ANY(%s)',
                                 (list(expected),)).fetchall()
        self.assertEqual(len(rows), len(expected))
        for identifier, parsed in rows:
            with self.subTest(rfpp_id=identifier):
                self.assertEqual((parsed['tier'], parsed['action']), expected[identifier])


if __name__ == '__main__':
    unittest.main(verbosity=2)
