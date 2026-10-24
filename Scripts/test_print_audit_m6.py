"""M6 shared print declaration/catalog extraction; no product execution."""
import contextlib
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import diff_cli as dc
import diff_studio as ds

class SharedPrintAuditTests(unittest.TestCase):
    def test_shared_commands_keep_tool_ownership_and_exact_command_names(self):
        for tool, commands, prefix, other in [
            ('dicom-print', {'dicom-print','status','send','job','list-printers','add-printer','remove-printer'}, 'SCU', 'SCP'),
            ('dicom-printscp', {'dicom-printscp','serve','simulate','status','queues'}, 'SCP', 'SCU')]:
            files, options, _, names = dc.surface(tool)
            self.assertEqual(set(names),commands)
            self.assertTrue(options)
            shared=[p for p in files if 'DICOMPrintCommandSupport' in p]
            self.assertTrue(any(Path(p).name.startswith(prefix) for p in shared))
            self.assertFalse(any(Path(p).name.startswith(other) for p in shared))

    def test_missing_shared_declarations_is_an_audit_error(self):
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaisesRegex(ValueError,'shared SCU command declarations are missing'):
                dc.tool_files('dicom-print',sources=root)

    def test_late_configuration_and_forwarding_wrapper_do_not_invent_names(self):
        src='''struct Wrapper: AsyncParsableCommand { static let configuration = Shared.configuration }
struct Shared: AsyncParsableCommand {
  public init() {}
  static func validate() { let text = "brace } is data" }
  static let configuration = CommandConfiguration(commandName: "dicom-print")
}
struct SCUStatusCommand: PrintExecutableCommand {
 static let configuration = CommandConfiguration(commandName: "status")
}'''
        self.assertEqual(dc.extract_commands(src), ['dicom-print','status'])

    def test_catalogs_are_nonempty_and_preserve_source_locations(self):
        ws=ds.workshop_surface()
        self.assertEqual(len(ws['dicom-print']),41)
        self.assertEqual(len(ws['dicom-printscp']),73)
        for tool in ['dicom-print','dicom-printscp']:
            self.assertEqual(len(ws[tool]),len({p['id'] for p in ws[tool]}))
            for p in ws[tool]:
                lines=(Path(ds.SOURCES)/'DICOMStudio/Components'/p['file']).read_text().splitlines()
                self.assertIn(p['id'],lines[p['line']-1])

    def test_scu_helper_retains_command_specific_defaults_and_visibility(self):
        fields={p['id']:p for p in ds.workshop_surface()['dicom-print']}
        self.assertEqual(fields['queryTimeout']['defaultValue'],'30')
        self.assertEqual(fields['queryTimeout']['visibility'],[('operation',['status','job'])])
        self.assertEqual(fields['sendTimeout']['defaultValue'],'60')
        self.assertEqual(fields['format']['visibility'],[('operation',['status','send','job','list-printers'])])
        self.assertEqual(fields['paths']['flag'],'')
        self.assertEqual(fields['paths']['isRepeatable'],'true')

    def test_scp_inheritance_mapping_retains_both_flag_polarities(self):
        fields=ds.workshop_surface()['dicom-printscp']
        p=next(p for p in fields if p['flag']=='--accept-color')
        self.assertEqual(p['defaultValue'],'inherit')
        self.assertEqual(p['mapping'],{'inherit':'','enabled':'--accept-color','disabled':'--no-accept-color'})
        self.assertEqual(p['visibility'],[('subcommand',['serve','status'])])

    def test_print_parity_checks_are_active_and_do_not_hide_wrong_flags(self):
        ws=ds.workshop_surface()
        for tool in ['dicom-print','dicom-printscp']:
            r=ds.StudioReport()
            with contextlib.redirect_stdout(io.StringIO()): ds.check_workshop_parity(r,ws,tool)
            self.assertEqual(r.failed,0)
            ws[tool].append({'id':'deliberatelyWrong','flag':'--no-such-print-option','line':1})
            r=ds.StudioReport()
            with contextlib.redirect_stdout(io.StringIO()): ds.check_workshop_parity(r,ws,tool)
            self.assertGreater(r.failed,0)

    def test_unknown_visibility_expression_fails_extraction(self):
        original=ds.dw.read
        def changed(path):
            text=original(path)
            return text.replace('commands: network','commands: unsupportedDynamicList') if path.endswith('CLIWorkshopPrintCatalog.swift') else text
        with patch.object(ds.dw,'read',changed):
            with self.assertRaisesRegex(ValueError,'unresolved command list'):
                ds.workshop_surface()
