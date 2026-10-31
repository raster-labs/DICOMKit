#!/usr/bin/env python3
"""M0 regression tests for audit execution, discovery and honest failure reporting.

Run: PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Scripts -p test_studio_audit_m0.py
These tests do not build or execute DICOMKit products.
"""
import contextlib
import io
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import diff_studio as audit
import diff_studio_g1 as g1


class StudioAuditM0Tests(unittest.TestCase):
    def capture(self, fn, *args, **kwargs):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            result = fn(*args, **kwargs)
        return result, output.getvalue()

    def test_extractor_errors_do_not_prevent_later_checks(self):
        rep = audit.StudioReport()
        seen = []
        for error in (FileNotFoundError('renamed.swift'), SystemExit('stale pattern')):
            def broken():
                raise error
            self.capture(audit.run_check, rep, 'broken', broken)
        self.capture(audit.run_check, rep, 'later', lambda: seen.append('ran'))
        self.assertEqual(seen, ['ran'])
        self.assertEqual(rep.failed, 0)
        self.assertEqual(len(rep.audit_errors), 2)
        self.assertEqual(rep.completed_checks, 1)
        self.assertEqual(rep.exit_code, 2)

    def test_real_findings_remain_failures(self):
        rep = audit.StudioReport()
        self.capture(audit.run_check, rep, 'product', rep.check, 'parity', 0,
                     ['Workshop omits an accepted flag'])
        self.assertEqual(rep.failed, 1)
        self.assertEqual(rep.audit_errors, [])
        self.assertEqual(rep.exit_code, 1)

    def test_keyboard_interrupt_is_not_swallowed(self):
        def interrupted():
            raise KeyboardInterrupt()
        with self.assertRaises(KeyboardInterrupt):
            audit.run_check(audit.StudioReport(), 'interrupt', interrupted)

    def test_renamed_and_split_cli_sources_are_discovered(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'dicom-anon'
            source.mkdir()
            (source / 'DICOMAnon.swift').write_text('entry point')
            (source / 'Support.swift').write_text('shared adapter')
            (source / 'README.md').write_text('not executable source')
            result = g1.cli_sources({'sources': tmp, 'dw': audit.dw}, 'dicom-anon')
        self.assertIn('entry point', result)
        self.assertIn('shared adapter', result)
        self.assertNotIn('not executable source', result)

    def test_current_inventory_is_complete(self):
        rep = audit.StudioReport()
        self.capture(audit.check_inventory, rep)
        self.assertEqual(rep.failed, 0)
        for name in ('DICOMStudio/Components/SelectionCard.swift',
                     'DICOMStudio/Models/StudioBuildInfo.swift'):
            self.assertEqual(audit.FILES[name], ('G2', 'NST'))

    def test_unknown_file_does_not_get_silently_inventoried(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'DICOMStudio'
            source.mkdir()
            (source / 'New.swift').write_text('struct New {}')
            rep = audit.StudioReport()
            with patch.object(audit, 'SOURCES', tmp), patch.object(audit, 'FILES', {}):
                _, output = self.capture(audit.check_inventory, rep)
        self.assertEqual(rep.failed, 1)
        self.assertIn('on disk but not in FILES', output)

    def test_missing_workshop_mapping_is_not_silent(self):
        rep = audit.StudioReport()
        with patch.object(audit, 'WORKSHOP_TOOLS', {}):
            _, output = self.capture(audit.check_workshop_coverage, rep, {'new-tool': []})
        self.assertEqual(rep.failed, 1)
        self.assertIn('form has no CLI audit mapping', output)

    def test_all_six_groups_continue_after_a_group_error(self):
        seen = []
        def broken(*_):
            raise SystemExit('obsolete source extractor')
        checks = {g: [('fixture', lambda *_, group=g: seen.append(group))] for g in audit.GROUPS}
        checks['G1'].insert(0, ('broken fixture', broken))
        output = io.StringIO()
        with patch('sys.argv', ['diff_studio.py', '--nema', '/fixture', '--only', 'fixture']), \
                patch.object(audit.os.path, 'exists', return_value=True), \
                patch.object(audit.nd, 'Part', return_value=SimpleNamespace(subtitle='DICOM 2026a')), \
                patch.object(audit, 'studio_files', return_value={}), \
                patch.object(audit, 'GROUP_CHECKS', checks), \
                patch.object(audit, 'GROUP_LOAD_ERRORS', {g: [] for g in audit.GROUPS}), \
                contextlib.redirect_stdout(output), self.assertRaises(SystemExit) as exited:
            audit.main()
        self.assertEqual(exited.exception.code, 2)
        self.assertEqual(seen, list(audit.GROUPS))
        for group in audit.GROUPS:
            self.assertIn(f'== {group}:', output.getvalue())
        self.assertIn('1 audit execution error(s)', output.getvalue())

    def test_missing_frozen_input_is_an_audit_error(self):
        output = io.StringIO()
        with patch('sys.argv', ['diff_studio.py', '--nema', '/missing', '--only', 'none']), \
                patch.object(audit.os.path, 'exists', return_value=False), \
                patch.object(audit, 'studio_files', return_value={}), \
                patch.object(audit, 'GROUP_LOAD_ERRORS', {g: [] for g in audit.GROUPS}), \
                contextlib.redirect_stdout(output), self.assertRaises(SystemExit) as exited:
            audit.main()
        self.assertEqual(exited.exception.code, 2)
        self.assertIn('ERROR PS3.7 input:', output.getvalue())
        self.assertIn('ERROR PS3.8 input:', output.getvalue())
        self.assertIn('ERROR PS3.19 input:', output.getvalue())

    def test_part7_uses_this_run_inputs(self):
        first, second = object(), object()
        self.assertIs(g1.part7({'parts': {7: first}}), first)
        self.assertIs(g1.part7({'parts': {7: second}}), second)
        self.assertIsNone(g1.part7({'parts': {}}))


if __name__ == '__main__':
    unittest.main()
