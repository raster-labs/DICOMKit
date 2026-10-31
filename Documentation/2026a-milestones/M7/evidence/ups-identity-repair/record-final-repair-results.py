from pathlib import Path
import datetime, hashlib, json

root = Path(__file__).resolve().parent
checks = {
    "dicomweb-all-repaired-v2.log": ["Test run with 649 tests in 63 suites passed", "Executed 504 tests, with 2 tests skipped and 0 failures"],
    "studio-affected-workflows-confirmed.log": ["Test run with 60 tests in 3 suites passed"],
    "all-products-repaired.log": ["Build complete!"],
    "app-build/build.log": ["** BUILD SUCCEEDED **"],
}
logs = {}
for name, markers in checks.items():
    data = (root / name).read_bytes()
    text = data.decode(errors="replace")
    assert all(marker in text for marker in markers), name
    logs[name] = {"sha256": hashlib.sha256(data).hexdigest(), "required_markers": markers}
result = {
    "recorded_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "completed": True,
    "scope": "Automated repair checks and builds only; native acceptance and new-head remote CI remain pending.",
    "logs": logs,
    "dicomweb": {"observed_command_exit": 0, "swift_testing_tests": 649, "swift_testing_suites": 63,
                 "xctest_reported": 504, "xctest_skipped": 2, "xctest_executed": 502, "failures": 0},
    "studio_affected_workflows": {"observed_command_exit": 0, "swift_testing_tests": 60, "suites": 3, "failures": 0},
    "builds": {"all_products_success_marker": True, "app_build_sign_verify_command_exit": 0},
    "runner_correction": {
        "original": "verify-linked-products.sh completed the product tests but its final grep expected XCTest suite names; the three suites use Swift Testing.",
        "original_runner_exit": 1,
        "preserved_successful_log": "studio-affected-workflows.log",
        "confirmation": "A no-build repeat confirmed the same60 tests and returned0; do not add repeated tests to unique counts."
    },
    "preserved_failed_runs": ["identity-focused-v1.log", "identity-focused-v2.log", "dicomweb-all.log", "dicomweb-all-repaired-v1.log"],
    "native_status": "Unexecuted for repaired app: Mac locked; prior27 native groups retain scoped source-equivalence evidence."
}
path = root / "root-final-repair-verification.json"
assert not path.exists()
path.write_text(json.dumps(result, indent=2) + "\n")
print(path)
