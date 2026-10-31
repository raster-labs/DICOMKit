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


def read_coverage(directory, source_root):
    """Require real exported coverage for this project's production sources."""
    result = {"directory": str(directory), "files": [], "covered_source_files": 0,
              "covered_functions": 0, "errors": []}
    errors = result["errors"]
    profile = directory / "default.profdata"
    if not profile.is_file() or profile.stat().st_size == 0:
        errors.append("merged coverage profile is missing or empty")
    else:
        result["files"].append({"path": str(profile), "bytes": profile.stat().st_size,
                                "sha256": hashlib.sha256(profile.read_bytes()).hexdigest()})
    exports = sorted(directory.glob("*.json"))
    if not exports:
        errors.append("coverage JSON export is missing")
    covered = set()
    for path in exports:
        try:
            raw = path.read_bytes()
            data = json.loads(raw)
            if data["type"] != "llvm.coverage.json.export" or not data["data"]:
                raise ValueError("unexpected coverage schema")
            result["files"].append({"path": str(path), "bytes": len(raw),
                                    "sha256": hashlib.sha256(raw).hexdigest()})
            for entry in data["data"]:
                for file in entry["files"]:
                    filename = Path(file["filename"]).resolve()
                    if not filename.is_relative_to(source_root.resolve()):
                        continue
                    functions = file["summary"]["functions"]
                    count, hits = functions["count"], functions["covered"]
                    if type(count) is not int or type(hits) is not int or not 0 <= hits <= count:
                        raise ValueError("invalid function counts")
                    if hits and filename not in covered:
                        covered.add(filename)
                        result["covered_functions"] += hits
        except (OSError, ValueError, KeyError, TypeError):
            errors.append(f"invalid coverage JSON export: {path.name}")
    result["covered_source_files"] = len(covered)
    if not covered:
        errors.append("coverage has no executed functions in this project's Sources directory")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log_dir", type=Path)
    parser.add_argument("--release-outcome", required=True)
    parser.add_argument("--debug-outcome", required=True)
    parser.add_argument("--coverage-dir", type=Path, required=True)
    parser.add_argument("--source-root", type=Path, default=Path("Sources"))
    parser.add_argument("--summary", type=Path)
    args = parser.parse_args()
    args.log_dir.mkdir(parents=True, exist_ok=True)
    checks = {
        "optimized_source_envelope": read_result(
            args.log_dir / "release-source-envelope.log", args.release_outcome, expected_tests=1),
        "debug_coverage": read_result(args.log_dir / "debug-suite.log", args.debug_outcome),
    }
    coverage = read_coverage(args.coverage_dir, args.source_root)
    passed = all(not check["errors"] for check in checks.values()) and not coverage["errors"]
    report = {"head_sha": os.environ.get("GITHUB_SHA"),
              "run_id": os.environ.get("GITHUB_RUN_ID"),
              "result": "passed" if passed else "failed", "checks": checks, "coverage": coverage,
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
    lines.append(f"Coverage: {'failed' if coverage['errors'] else 'passed'}; "
                 f"{coverage['covered_source_files']} production source files with executed functions.")
    for error in coverage["errors"]:
        print(f"::error::coverage: {error}")
        lines.append(f"- coverage: {error}")
    summary = "\n".join(lines) + "\n"
    if args.summary:
        with args.summary.open("a") as stream:
            stream.write(summary)
    print(summary)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
