"""Keep early XCTest failures visible when later Swift Testing output is green."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


RUNNER = Path(__file__).resolve().with_name("verify_m6.sh")


class PrintRunnerReportingTests(unittest.TestCase):
    def run_fixture(self, *, process_failure):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            swift = root / "swift"
            swift.write_text(f"#!{sys.executable}\n" + """
import sys
if sys.argv[1] == 'build':
    raise SystemExit(0)
""" + ("print('[colour-wire phase] cleanup')\n"
       "print('Fixture.swift:42: error: early XCTest assertion failed')\n"
       if process_failure else "") + """
for n in range(150):
    print(f'Later successful test {n}')
print('✔ Test run with 84 tests in 9 suites passed after 0.1 seconds.')
""" + f"raise SystemExit({1 if process_failure else 0})\n")
            swift.chmod(0o755)
            env = os.environ.copy()
            env["PATH"] = str(root) + os.pathsep + env["PATH"]
            return subprocess.run(
                ["bash", str(RUNNER), str(root / "logs")], cwd=root, env=env,
                capture_output=True, text=True, timeout=10)

    def test_early_xctest_failure_survives_green_trailing_output(self):
        result = self.run_fixture(process_failure=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Fixture.swift:42: error: early XCTest assertion failed", result.stdout)
        self.assertIn("[colour-wire phase] cleanup", result.stdout)
        self.assertIn("84 tests in 9 suites passed", result.stdout)

    def test_green_output_without_required_suite_marker_cannot_pass(self):
        result = self.run_fixture(process_failure=False)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
