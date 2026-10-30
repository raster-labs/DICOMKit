#!/usr/bin/env python3
"""Keep CLI option maps distinct from DICOM names without suppressing tag checks."""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


AUDIT = Path(__file__).with_name("audit_tags.py").resolve()
# Independent PS3.6 fixture rows. The test does not read the production map or
# the audit's normalization tables to decide the expected attribute identities.
DICTIONARY = """0008|0060|Modality|Modality|CS|1|
0008|0061|Modalities in Study|ModalitiesInStudy|CS|1-n|
0010|0010|Patient's Name|PatientName|PN|1|
0010|0020|Patient ID|PatientID|LO|1|
"""


class TagMapRoleTests(unittest.TestCase):
    def audit(self, source, filename="Other/Example.swift"):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dictionary = root / "Sources/DICOMDictionary/Resources/DataElementDictionary.txt"
            dictionary.parent.mkdir(parents=True)
            dictionary.write_text(DICTIONARY)
            path = root / "Sources" / filename
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(source)
            return subprocess.run([sys.executable, str(AUDIT), str(root), "--strict"],
                                  capture_output=True, text=True)

    def test_query_level_tags_can_share_one_cli_option(self):
        result = self.audit('let options = ["00080060": "--modality", "00080061": "--modality"]')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("## BLOCKER (0)", result.stdout)

    def test_option_role_is_generic_not_a_file_or_flag_exception(self):
        for flag in ["--patient-name", "--PatientName"]:
            with self.subTest(flag=flag):
                result = self.audit(f'let options = ["00100020": "{flag}"]', "Any/Options.swift")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_correct_dicom_keywords_and_display_names_remain_valid(self):
        result = self.audit('let names = ["00080060": "Modality", "00080061": "Modalities in Study"]')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_wrong_dicom_keyword_or_display_name_still_fails(self):
        for tag, name in [("00080061", "Modality"), ("00080060", "ModalitiesInStudy"),
                          ("00080060", "Modalities in Study")]:
            with self.subTest(tag=tag, name=name):
                result = self.audit(f'let names = ["{tag}": "{name}"]')
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn(f"map entry '{name}' resolves to", result.stdout)

    def test_cli_entry_does_not_suppress_another_bad_map_entry_on_same_line(self):
        result = self.audit('let values = ["00080061": "--modality", "00100020": "PatientName"]')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("map entry 'PatientName' resolves to (0010,0010)", result.stdout)

    def test_cli_entry_does_not_suppress_wrong_comment(self):
        result = self.audit('let options = ["00080061": "--modality"] // Modality')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("comment 'Modality' resolves to (0008,0060)", result.stdout)

    def test_cli_entry_does_not_suppress_wrong_vr(self):
        result = self.audit('consume(["00080061": "--modality"], vr: .LO)')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("vr .LO for (0008,0061) but PS3.6 VR is 'CS'", result.stdout)

    def test_arbitrary_leading_punctuation_is_not_an_option_token(self):
        for name in ["- Modality", "-- Modality", "---Modality", "--Modality-", "!Modality"]:
            with self.subTest(name=name):
                result = self.audit(f'let names = ["00080061": "{name}"]')
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn(f"map entry '{name}' resolves to", result.stdout)


if __name__ == "__main__":
    unittest.main()
