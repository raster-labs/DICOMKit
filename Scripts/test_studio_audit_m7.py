"""M7 audit wiring regressions; no Swift build, product execution or network access."""
import contextlib
import io
from pathlib import Path
import unittest
from unittest.mock import patch

import diff_cli as dc
import diff_studio as audit
import diff_studio_g1 as g1
import diff_studio_g6 as g6


class StudioAuditM7Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = Path(audit.SOURCES)
        cls.ctx = {'sources': str(source), 'dw': audit.dw, 'nd': audit.nd}
        cls.vm = (source / 'DICOMStudio/ViewModels/CLIWorkshopViewModel.swift').read_text()
        cls.helpers = (source / 'DICOMStudio/Components/CLIWorkshopHelpers.swift').read_text()
        cls.query = g1.cli_sources(cls.ctx, 'dicom-query')
        cls.wado = g1.cli_sources(cls.ctx, 'dicom-wado')
        cls.service = (source / 'DICOMNetwork/QueryService.swift').read_text()

    def dimse_issues(self, vm=None, cli=None, service=None):
        return g1.query_preflight_issues(self.vm if vm is None else vm,
                                        self.query if cli is None else cli,
                                        self.service if service is None else service, audit.dw)

    def qido_issues(self, vm=None, helpers=None, cli=None):
        return g1.qido_preflight_issues(self.vm if vm is None else vm,
                                       self.helpers if helpers is None else helpers,
                                       self.wado if cli is None else cli, audit.dw)

    def test_current_shared_preflights_are_recognized(self):
        self.assertEqual(self.dimse_issues(), [])
        self.assertEqual(self.qido_issues(), [])

    def test_dimse_comment_cannot_replace_a_refusing_guard(self):
        original = 'if let reason = buildKeys().rejectionReason {'
        self.assertIn(original, self.vm)
        broken = self.vm.replace(original, '// ' + original + '\nif false {')
        self.assertTrue(any('Workshop must refuse' in issue for issue in self.dimse_issues(vm=broken)))
        broken = self.vm.replace('refuse(reason, exitCode: 64)', 'refuse(reason, exitCode: 0)')
        self.assertTrue(any('Workshop must refuse' in issue for issue in self.dimse_issues(vm=broken)))

    def test_dimse_cli_preflight_and_shared_level_message_are_required(self):
        broken = self.query.replace('try validate()', '// try validate()')
        self.assertTrue(any('CLI must validate' in issue for issue in self.dimse_issues(cli=broken)))
        broken = self.service.replace('cannot be matched at \\(level.rawValue) level',
                                      'cannot be matched at INSTANCE level')
        self.assertTrue(any('QueryLevel.rawValue' in issue for issue in self.dimse_issues(service=broken)))

    def test_dimse_refusal_after_dispatch_is_not_preflight(self):
        marker = 'if let reason = buildKeys().rejectionReason {'
        broken = self.vm.replace(marker, 'let premature = DICOMQueryService.find(\n' + marker)
        self.assertTrue(any('before the header and C-FIND' in issue for issue in self.dimse_issues(vm=broken)))

    def test_qido_requires_strict_integer_and_shared_paging_validation(self):
        for old, new in [
            ('try DICOMwebOptionRules.validatePaging(limit: limit, offset: offset)',
             '// try DICOMwebOptionRules.validatePaging(limit: limit, offset: offset)'),
            ('guard let limit = Int(value("limit")), let offset = Int(value("offset")) else {',
             'if false {'),
            ('let effective = effectiveValues(values, definitions: definitions)',
             'let effective = values'),
        ]:
            with self.subTest(removed=old):
                self.assertIn(old, self.helpers)
                self.assertTrue(any('strictly parse' in issue for issue in
                                    self.qido_issues(helpers=self.helpers.replace(old, new))))

    def test_qido_effective_request_must_precede_client_creation(self):
        marker = 'let request = try effectiveQIDORequest(resolvedModality: resolved.value)'
        self.assertIn(marker, self.vm)
        for broken in [self.vm.replace(marker, '// ' + marker),
                       self.vm.replace(marker, 'let premature = DICOMwebClientFactory.makeClient(\n' + marker)]:
            self.assertTrue(any('before constructing the HTTP client' in issue for issue in self.qido_issues(vm=broken)))

    def test_qido_cli_must_use_the_same_resource_policy(self):
        marker = 'try QIDORequest(level:'
        self.assertIn(marker, self.wado)
        broken = self.wado.replace(marker, 'try BypassRequest(level:')
        self.assertTrue(any('same QIDORequest' in issue for issue in self.qido_issues(cli=broken)))

    def film_check(self):
        rep = audit.StudioReport()
        output = io.StringIO()
        with patch.object(g6, 'c13_lists', return_value={'Film Destination': ['MAGAZINE', 'PROCESSOR', 'BIN_i']}), \
                contextlib.redirect_stdout(output):
            g6.check_film_destination_picker(rep, {3: object()},
                                             audit.studio_files(tier='ST', group='G6'), self.ctx)
        return rep, output.getvalue()

    def test_print_discovery_follows_extracted_scu_commands(self):
        self.assertFalse((Path(audit.SOURCES) / 'dicom-print/main.swift').exists())
        sources = g1.cli_sources(self.ctx, 'dicom-print')
        self.assertIn('struct SCUFilmDestinationOption', sources)
        self.assertNotIn('struct SCPServeCommand', sources)
        rep, output = self.film_check()
        self.assertEqual(rep.failed, 0, output)

    def test_print_comment_does_not_hide_missing_film_destination_parser(self):
        original = dc.tool_files
        def broken(tool, sources=None):
            files = original(tool, sources=sources)
            return {name: text.replace('guard let destination = FilmDestination(catalogToken: argument)',
                                       'guard let destination = BypassDestination(argument)')
                    for name, text in files.items()}
        with patch.object(dc, 'tool_files', side_effect=broken):
            rep, output = self.film_check()
        self.assertEqual(rep.failed, 1)
        self.assertIn('no longer parses --film-destination', output)

    def test_known_anon_and_script_parity_differences_remain_visible(self):
        ws = audit.workshop_surface()
        for tool, expected in [('dicom-anon', '--profile'), ('dicom-script', "Workshop default 'true'")]:
            with self.subTest(tool=tool):
                rep = audit.StudioReport()
                output = io.StringIO()
                with contextlib.redirect_stdout(output):
                    audit.check_workshop_parity(rep, ws, tool)
                self.assertEqual(rep.failed, 1)
                self.assertIn(expected, output.getvalue())


if __name__ == '__main__':
    unittest.main()
