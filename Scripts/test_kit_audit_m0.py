#!/usr/bin/env python3
"""AUD-03 regression coverage for the scoped private tag alias; no Swift build required."""
import contextlib
import io
import tempfile
import unittest
from unittest.mock import patch

import diff_kit as audit


class PrivateTagAliasTests(unittest.TestCase):
    source_path = 'Anonymization/ConfidentialityProfile.swift'
    # Independent PS3.6 2026a Table 6-1 fixture rows, not the audit's alias table.
    dictionary = {
        '00120064': ('De-identification Method Code Sequence',
                     'DeidentificationMethodCodeSequence', 'SQ', '1', ''),
        '00120063': ('De-identification Method', 'DeidentificationMethod', 'LO', '1-n', ''),
        '00100010': ("Patient's Name", 'PatientName', 'PN', '1', ''),
    }

    def extract(self, files):
        with tempfile.TemporaryDirectory() as core:
            return audit.tag_constants(core, files)

    def check_names(self, files, dictionary=None):
        _, local = self.extract(files)
        report = audit.dw.Report(False)
        output = io.StringIO()
        with patch.object(audit.dw, 'dictionary', return_value=dict(
                self.dictionary if dictionary is None else dictionary)), \
                patch.object(audit.dw, 'table_rows', return_value=[]), \
                contextlib.redirect_stdout(output):
            audit.check_tag_names(report, None, files, local)
        return report, output.getvalue()

    def test_exact_private_alias_matches(self):
        files = {self.source_path:
                 'private static let methodSequenceTag = Tag(group: 0x0012, element: 0x0064) '
                 '// De-identification Method Code Sequence\n'}
        report, output = self.check_names(files)
        self.assertEqual(report.failed, 0, output)
        self.assertIn('matched 2, wrong 0', output)

    def test_alias_with_wrong_registered_tag_still_fails(self):
        # No comment: the alias binding itself must catch the incorrect number.
        files = {self.source_path:
                 'private static let methodSequenceTag = Tag(group: 0x0012, element: 0x0063)\n'}
        report, output = self.check_names(files)
        self.assertEqual(report.failed, 1, output)
        self.assertIn('methodSequenceTag', output)
        self.assertIn('(0012,0063)', output)

    def test_alias_with_unknown_tag_still_fails(self):
        files = {self.source_path:
                 'private static let methodSequenceTag = Tag(group: 0x0012, element: 0xFFFF)\n'}
        report, output = self.check_names(files)
        self.assertEqual(report.failed, 1, output)
        self.assertIn('(0012,FFFF)', output)

    def test_alias_does_not_accept_wrong_canonical_keyword(self):
        dictionary = dict(self.dictionary)
        dictionary['00120064'] = ('De-identification Method Code Sequence',
                                 'PatientName', 'SQ', '1', '')
        files = {self.source_path:
                 'private static let methodSequenceTag = Tag(group: 0x0012, element: 0x0064)\n'}
        report, output = self.check_names(files, dictionary)
        self.assertEqual(report.failed, 1, output)
        self.assertIn('PatientName', output)

    def test_alias_is_not_allowed_in_another_file(self):
        files = {'Other/ConfidentialityProfile.swift':
                 'private static let methodSequenceTag = Tag(group: 0x0012, element: 0x0064)\n'}
        report, output = self.check_names(files)
        self.assertEqual(report.failed, 1, output)
        self.assertIn('Other/ConfidentialityProfile.swift', output)

    def test_alias_does_not_bypass_comment_check(self):
        files = {self.source_path:
                 'private static let methodSequenceTag = Tag(group: 0x0012, element: 0x0064) '
                 '// Patient Name\n'}
        report, output = self.check_names(files)
        self.assertEqual(report.failed, 1, output)
        self.assertIn('commented "Patient Name"', output)

    def test_unrelated_canonical_name_and_wrong_pair_are_still_checked(self):
        for element, expected_failures in [('0010', 0), ('0063', 1)]:
            group = '0010' if element == '0010' else '0012'
            with self.subTest(group=group, element=element):
                files = {'Other.swift':
                         f'static let patientName = Tag(group: 0x{group}, element: 0x{element})\n'}
                report, output = self.check_names(files)
                self.assertEqual(report.failed, expected_failures, output)

    def test_extracted_alias_still_reaches_vr_checks(self):
        files = {self.source_path:
                 'private static let methodSequenceTag = Tag(group: 0x0012, element: 0x0064)\n'
                 'DataElement(tag: .methodSequenceTag, vr: .LO)\n'}
        tags, local = self.extract(files)
        self.assertEqual(tags['methodSequenceTag'], '00120064')
        self.assertEqual(local['methodSequenceTag'], ('00120064', self.source_path))
        report = audit.dw.Report(False)
        output = io.StringIO()
        with patch.object(audit.dw, 'dictionary', return_value=dict(self.dictionary)), \
                contextlib.redirect_stdout(output):
            audit.check_vr_literals(report, None, files, tags)
        self.assertEqual(report.failed, 1, output.getvalue())
        self.assertIn('PS3.6 VR is SQ', output.getvalue())


if __name__ == '__main__':
    unittest.main()
