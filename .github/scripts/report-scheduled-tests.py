#!/usr/bin/env python3
"""Report existing serial Swift test logs without executing tests again.

SwiftPM can emit a separate XCTest and Swift Testing result for each product.
Only top-level XCTest summaries count: nested suite totals repeat those tests.
The process outcome and every summary must pass; a final green product cannot
hide an earlier failure. Missing, truncated and zero-selection logs fail closed.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re


XCTEST_RESULT = re.compile(r"Test Suite '(?:All|Selected) tests' (passed|failed) at")
XCTEST_COUNT = re.compile(
    r"Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?(\d+) failures?"
)
SWIFT_RESULT = re.compile(
    r"Test run with (\d+) tests?(?: in \d+ suites?)? (passed|failed) after"
)


def read_result(path, outcome, expected_tests=None):
    result = {"log": str(path), "execution_outcome": outcome,
              "xctest_products": [], "swift_testing_products": [], "errors": []}
    errors = result["errors"]
    if outcome != "success":
        errors.append(f"test execution outcome is {outcome or 'unavailable'}")
    if not path.is_file():
        errors.append("test log is missing; execution is not verified")
        result["reported_tests"] = 0
        return result

    raw = path.read_bytes()
    result["sha256"] = hashlib.sha256(raw).hexdigest()
    pending_xctest = None
    for line in raw.decode("utf-8", errors="replace").splitlines():
        match = XCTEST_RESULT.search(line)
        if match:
            if pending_xctest is not None:
                errors.append("XCTest product summary is missing its count")
            pending_xctest = match[1]
        elif pending_xctest is not None:
            match = XCTEST_COUNT.search(line)
            if match:
                result["xctest_products"].append({
                    "outcome": pending_xctest, "tests": int(match[1]),
                    "skipped": int(match[2] or 0), "failures": int(match[3])})
                pending_xctest = None
        match = SWIFT_RESULT.search(line)
        if match:
            result["swift_testing_products"].append({
                "outcome": match[2], "tests": int(match[1])})

    if pending_xctest is not None:
        errors.append("XCTest product summary is missing its count")
    products = result["xctest_products"] + result["swift_testing_products"]
    result["reported_tests"] = sum(product["tests"] for product in products)
    result["xctest_skipped"] = sum(product["skipped"] for product in result["xctest_products"])
    if any(p["outcome"] != "passed" or p.get("failures", 0) for p in products):
        errors.append("one or more test products reported failures")
    if result["reported_tests"] == 0:
        errors.append("no tests were reported; an empty selection cannot pass")
    if expected_tests is not None and result["reported_tests"] != expected_tests:
        errors.append(f"expected {expected_tests} source-envelope test, observed {result['reported_tests']}")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log_dir", type=Path)
    parser.add_argument("--release-outcome", required=True)
    parser.add_argument("--debug-outcome", required=True)
    parser.add_argument("--summary", type=Path)
    args = parser.parse_args()
    args.log_dir.mkdir(parents=True, exist_ok=True)
    checks = {
        "optimized_source_envelope": read_result(
            args.log_dir / "release-source-envelope.log", args.release_outcome, expected_tests=1),
        "debug_coverage": read_result(args.log_dir / "debug-suite.log", args.debug_outcome),
    }
    passed = all(not check["errors"] for check in checks.values())
    report = {"head_sha": os.environ.get("GITHUB_SHA"),
              "run_id": os.environ.get("GITHUB_RUN_ID"),
              "result": "passed" if passed else "failed", "checks": checks,
              "count_note": "Reported totals include skipped tests. XCTest skips are listed separately; raw logs retain all Swift Testing skip reasons."}
    (args.log_dir / "test-report.json").write_text(json.dumps(report, indent=2) + "\n")
    lines = ["## Comprehensive test evidence", "",
             "| Execution | Process outcome | Reported tests | Verification |",
             "| --- | --- | ---: | --- |"]
    for name, check in checks.items():
        lines.append(f"| {name} | {check['execution_outcome'] or 'unavailable'} | {check['reported_tests']} | {'failed' if check['errors'] else 'passed'} |")
        for error in check["errors"]:
            print(f"::error::{name}: {error}")
    lines.extend(["", report["count_note"], "",
                  "Debug runs once with coverage; the source-envelope test runs separately in Release."])
    for name, check in checks.items():
        lines.extend(f"- {name}: {error}" for error in check["errors"])
    summary = "\n".join(lines) + "\n"
    if args.summary:
        with args.summary.open("a") as stream:
            stream.write(summary)
    print(summary)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
