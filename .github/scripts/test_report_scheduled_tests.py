"""Failure-preservation tests for the scheduled CI evidence reporter."""

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("report-scheduled-tests.py")
SPEC = importlib.util.spec_from_file_location("scheduled_report", SCRIPT)
REPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REPORT)


class ReportTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def read(self, text, outcome="success", expected=None):
        path = self.root / "test.log"
        path.write_text(text)
        return REPORT.read_result(path, outcome, expected)

    def coverage(self, *, hits=1, filename=None):
        directory = self.root / "codecov"
        directory.mkdir(exist_ok=True)
        (directory / "default.profdata").write_bytes(b"synthetic profile control")
        (directory / "Package.json").write_text(json.dumps({
            "type": "llvm.coverage.json.export", "data": [{"files": [{
                "filename": str(filename or self.root / "Sources" / "Example.swift"),
                "summary": {"functions": {"count": 2, "covered": hits}}
            }]}]}))
        return directory

    def test_valid_production_coverage_records_hashes_and_counts(self):
        result = REPORT.read_coverage(self.coverage(), self.root / "Sources")
        self.assertEqual(result["errors"], [])
        self.assertEqual(result["covered_source_files"], 1)
        self.assertEqual(result["covered_functions"], 1)
        self.assertEqual(len(result["files"]), 2)
        self.assertTrue(all(len(f["sha256"]) == 64 for f in result["files"]))

    def test_absent_empty_and_malformed_coverage_fails(self):
        self.assertTrue(REPORT.read_coverage(self.root / "absent", self.root / "Sources")["errors"])
        directory = self.coverage()
        (directory / "default.profdata").write_bytes(b"")
        self.assertTrue(REPORT.read_coverage(directory, self.root / "Sources")["errors"])
        directory = self.coverage()
        for raw in ["", "{}", "[]", '{"type":"wrong","data":[]}',
                    '{"type":"llvm.coverage.json.export","data":[null]}']:
            (directory / "Package.json").write_text(raw)
            self.assertTrue(REPORT.read_coverage(directory, self.root / "Sources")["errors"])

    def test_unexecuted_or_foreign_coverage_cannot_pass(self):
        for hits in [0, -1, 3, True]:
            self.assertTrue(REPORT.read_coverage(self.coverage(hits=hits), self.root / "Sources")["errors"])
        for filename in [self.root / "Tests" / "Test.swift", self.root / "dependency" / "Sources" / "Library.swift"]:
            self.assertTrue(REPORT.read_coverage(self.coverage(filename=filename), self.root / "Sources")["errors"])

    def test_counts_each_product_once_not_nested_suites_or_last_trailer(self):
        result = self.read("""Test Suite 'Inner' passed at now.
Executed 3 tests, with 0 failures (0 unexpected)
Test Suite 'One.xctest' passed at now.
Executed 3 tests, with 0 failures (0 unexpected)
Test Suite 'All tests' passed at now.
Executed 3 tests, with 1 test skipped and 0 failures (0 unexpected)
Test Suite 'All tests' passed at now.
Executed 2 tests, with 0 failures (0 unexpected)
✔ Test run with 4 tests in 2 suites passed after 0.1 seconds.
✔ Test run with 0 tests in 0 suites passed after 0.1 seconds.
""")
        self.assertEqual(result["reported_tests"], 9)
        self.assertEqual(result["xctest_skipped"], 1)
        self.assertEqual(result["errors"], [])

    def test_earlier_xctest_failure_cannot_be_hidden_by_last_green_product(self):
        result = self.read("""Test Suite 'All tests' failed at now.
Executed 2 tests, with 1 failure (1 unexpected)
✔ Test run with 50 tests passed after 0.1 seconds.
""")
        self.assertTrue(result["errors"])

    def test_earlier_swift_testing_failure_cannot_be_hidden(self):
        result = self.read("""✘ Test run with 2 tests in 1 suite failed after 0.1 seconds with 1 issue.
✔ Test run with 50 tests in 3 suites passed after 0.1 seconds.
""")
        self.assertTrue(result["errors"])

    def test_process_failure_overrides_green_summaries(self):
        result = self.read("✔ Test run with 1 test passed after 0.1 seconds.", "failure")
        self.assertTrue(result["errors"])

    def test_empty_and_truncated_selections_fail(self):
        for text in ["", "Build complete!", "✔ Test run with 0 tests passed after 0.1 seconds.",
                     "Test Suite 'All tests' passed at now."]:
            with self.subTest(text=text):
                self.assertTrue(self.read(text)["errors"])

    def test_missing_log_is_not_verified(self):
        result = REPORT.read_result(self.root / "absent.log", "skipped")
        self.assertTrue(result["errors"])
        self.assertEqual(result["reported_tests"], 0)

    def test_source_envelope_requires_exactly_one_test(self):
        for count in [0, 2]:
            self.assertTrue(self.read(f"✔ Test run with {count} tests passed after 0.1 seconds.", expected=1)["errors"])
        self.assertFalse(self.read("✔ Test run with 1 test in 1 suite passed after 0.1 seconds.", expected=1)["errors"])

    def test_cli_preserves_failure_and_writes_report_without_rerunning(self):
        (self.root / "release-source-envelope.log").write_text("✔ Test run with 1 test passed after 0.1 seconds.")
        (self.root / "debug-suite.log").write_text("✔ Test run with 7 tests passed after 0.1 seconds.")
        for outcome, expected in [("failure", 1), ("success", 0)]:
            run = subprocess.run([sys.executable, str(SCRIPT), str(self.root),
                                  "--release-outcome", "success", "--debug-outcome", outcome,
                                  "--coverage-dir", str(self.coverage()), "--source-root", str(self.root / "Sources")],
                                 capture_output=True, text=True)
            self.assertEqual(run.returncode, expected, run.stderr)
            report = json.loads((self.root / "test-report.json").read_text())
            self.assertEqual(report["checks"]["debug_coverage"]["execution_outcome"], outcome)

    def test_cli_green_tests_without_coverage_fail(self):
        (self.root / "release-source-envelope.log").write_text("✔ Test run with 1 test passed after 0.1 seconds.")
        (self.root / "debug-suite.log").write_text("✔ Test run with 7 tests passed after 0.1 seconds.")
        run = subprocess.run([sys.executable, str(SCRIPT), str(self.root),
                              "--release-outcome", "success", "--debug-outcome", "success",
                              "--coverage-dir", str(self.root / "absent")], capture_output=True, text=True)
        self.assertEqual(run.returncode, 1)
        report = json.loads((self.root / "test-report.json").read_text())
        self.assertEqual(report["result"], "failed")
        self.assertTrue(report["coverage"]["errors"])


if __name__ == "__main__":
    unittest.main()
