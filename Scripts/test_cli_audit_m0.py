#!/usr/bin/env python3
"""M0 CLI audit regression tests; no Swift builds, clinical inputs or network access."""
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

import diff_cli as dc


class CLIInventoryTests(unittest.TestCase):
    def test_manifest_ignores_disabled_products_comments_and_string_examples(self):
        manifest = '''
        // .executable(name: "dicom-disabled", targets: [])
        /* outer /* nested */ .executable(name: "dicom-blocked", targets: []) */
        let example = """.executable(name: "dicom-example", targets: [])"""
        .library(name: "dicom-library", targets: [])
        .executableTarget(name: "dicom-target", dependencies: [])
        .executable(name: "dicom-first", targets: ["dicom-first"]),
        .executable( /* explanation */ name: "dicom-second", targets: [])
        '''
        self.assertEqual(dc.active_tools(manifest), ['dicom-first', 'dicom-second'])

    def test_current_manifest_has_41_active_products_and_42_source_directories(self):
        self.assertEqual(len(dc.active_tools()), 41)
        self.assertEqual(len(set(dc.active_tools())), 41)
        self.assertEqual(len(dc.source_tools()), 42)
        self.assertEqual(set(dc.source_tools()) - set(dc.active_tools()), {'dicom-cloud'})
        self.assertEqual(set(dc.ALL_TOOLS), set(dc.active_tools()))
        self.assertTrue(set(dc.active_tools()) <= {t for group in dc.GROUPS.values() for t in group})

    def surface_report(self, *args):
        result = subprocess.run([sys.executable, '-B', str(Path(dc.__file__)),
                                 '--nema', 'unused-for-source-inventory', '--list-surface', *args],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_default_selection_covers_only_enabled_products(self):
        text = self.surface_report()
        headers = [line for line in text.splitlines() if line.startswith('== ')]
        self.assertEqual(len(headers), 41)
        self.assertIn('41 active executable products; 42 source directories', text)
        self.assertFalse(any(line.startswith('== dicom-cloud:') for line in headers))

    def test_group_selection_excludes_cloud_but_explicit_source_check_is_labeled(self):
        self.assertNotIn('== dicom-cloud:', self.surface_report('--group', 'G1'))
        text = self.surface_report('--tool', 'dicom-cloud')
        self.assertIn('SOURCE-ONLY dicom-cloud: not an active Package.swift executable product', text)
        self.assertIn('== dicom-cloud:', text)


class OptionExtractionTests(unittest.TestCase):
    def extract(self, src):
        return dc.extract_options(src + '\n', 'fixture.swift')

    def test_inversion_help_is_not_an_inverted_flag(self):
        options = self.extract('''@Flag(name: .long, help: "no rescale/window/inversion")
var raw: Bool = false
@Flag(name: .long, help: "The text inversion: .prefixedNo is only documentation")
var other: Bool = false''')
        self.assertEqual(options[0]['names'], ['--raw'])
        self.assertEqual(options[1]['names'], ['--other'])
        for tool in ['dicom-print', 'dicom-printscp']:
            raw = [o for o in dc.surface(tool)[1] if o['var'] == 'raw']
            self.assertTrue(raw)
            self.assertTrue(all(o['names'] == ['--raw'] for o in raw))

    def test_inversion_uses_custom_long_name_and_optional_flag_is_nil(self):
        option, = self.extract('''@Flag(name: .customLong("enabled-color"), inversion: .prefixedNo,
    help: "Use the configured value if absent")
var differentProperty: Bool?''')
        self.assertEqual(option['names'], ['--enabled-color', '--no-enabled-color'])
        self.assertEqual(option['default'], 'nil')

    def test_nonoptional_flag_defaults_and_explicit_true_are_preserved(self):
        options = self.extract('''@Flag var first: Bool
@Flag var second: Bool = true
@Flag var third: Bool? = false''')
        self.assertEqual([o['default'] for o in options], ['false', 'true', 'false'])

    def test_current_printscp_optional_flags_retain_nil_defaults(self):
        flags = [o for o in dc.surface('dicom-printscp')[1]
                 if o['kind'] == 'Flag' and o['type'] == 'Bool?']
        self.assertEqual(len(flags), 5)
        self.assertTrue(all(o['default'] == 'nil' for o in flags))


class AuditReportingTests(unittest.TestCase):
    def test_current_anon_contract_covers_declared_flags_without_legacy_rows(self):
        options = dc.surface('dicom-anon')[1]
        rows = dc.CONTRACT['dicom-anon']
        self.assertNotIn('--keep', rows)
        self.assertNotIn('--regenerate-uids', rows)
        self.assertIn('ps315 (default) or basic', rows['--profile'][2])
        canonical = {n for o in options for n in o['names'] if not n.startswith('-') or n.startswith('--')}
        self.assertEqual(set(rows), canonical)
        rep = dc.dw.Report(False)
        with redirect_stdout(StringIO()):
            dc.check_contract(rep, {}, 'dicom-anon', options)
        self.assertEqual(rep.failed, 0)

    def test_stale_contract_and_wrong_documented_default_still_fail(self):
        options = dc.surface('dicom-anon')[1]
        rep, output = dc.dw.Report(False), StringIO()
        with patch.dict(dc.CONTRACT['dicom-anon'], {'--keep': ('', '', '', '')}), redirect_stdout(output):
            dc.check_contract(rep, {}, 'dicom-anon', options)
            dc.check_documented_defaults(rep, 'fixture', {}, [{
                'documented_default': '3', 'default': '4', 'kind': 'Option',
                'file': 'fixture.swift', 'line': 1, 'names': ['--count']}])
        self.assertEqual(rep.failed, 2)
        self.assertIn('--keep names no option in the source', output.getvalue())
        self.assertIn('help says default', output.getvalue())

    def test_inverted_contract_emission_keeps_positive_option_meaning(self):
        output = StringIO()
        with redirect_stdout(output):
            dc.emit_contract({}, 'dicom-anon')
        self.assertIn('`--clean-pixel-data, --no-clean-pixel-data` | Clean Pixel Data Option',
                      output.getvalue())

    def test_check_error_and_missing_standard_are_visible_and_do_not_abort_following_check(self):
        rep, output, called = dc.dw.Report(False), StringIO(), []
        def broken():
            raise KeyError('missing audit fixture')
        with redirect_stdout(output):
            dc.run_check(rep, 'broken check', broken)
            dc.run_check(rep, 'missing standard', lambda: called.append('incorrect'), {6})
            dc.run_check(rep, 'following check', lambda: called.append('following'))
        self.assertEqual(rep.failed, 2)
        self.assertEqual(called, ['following'])
        self.assertIn('AUDIT ERROR: KeyError', output.getvalue())
        self.assertIn('AUDIT ERROR: missing standard parts PS3.6', output.getvalue())


if __name__ == '__main__':
    unittest.main()
