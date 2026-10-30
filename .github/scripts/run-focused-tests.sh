#!/usr/bin/env bash

# Run from the DICOMKit checkout to validate. Separate build/run phases let CI
# start its execution timeout only after the two Debug test products are ready.
set -euo pipefail

fail() {
  printf '::error::%s\n' "$*" >&2
  exit 1
}

phase="${1:-all}"
[[ "$#" -le 1 ]] || fail 'Usage: run-focused-tests.sh [build|run|all]'
case "$phase" in
  build|run|all) ;;
  *) fail 'Usage: run-focused-tests.sh [build|run|all]' ;;
esac

cd "$(git rev-parse --show-toplevel)"
[[ -f Package.swift && -d Sources/DICOMCore ]] || fail 'Run from a DICOMKit checkout.'
head="$(git rev-parse HEAD)"
log_dir=".build/ci-logs/focused-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
mkdir -p "$log_dir"
marker="$log_dir/built-head.txt"
swift_test_flags=(-Xswiftc -Xfrontend -Xswiftc -enable-cross-import-overlays --scratch-path .build -c debug)
core_filter='StrictDICOMTimeTests|DICOMTimeTests|DataElementTests|BugRegressionTests|DICOMExternalAllocationTests'
cli_filter='ImageConverterOutputRulesTests|BoundedInputTests/(signedPaddingVR|paddingVRNestedContext|paddingVRRejectsContext|paddingVRLocalOverride|paddingVRPreservesExplicitMismatch|paddingVRRejectsLength|paddingVRAbsentIsUnchanged|paddingVRFinalizationCancellation|allocationFailureSweep|modalityLUTImplicitValues|modalityLUTNestedContext|modalityLUTRejectsMalformed|modalityLUTPreservesExplicit|modalityLUTScopeExclusions|modalityLUTFinalizationCancellation)\('

check_source() {
  [[ "$(git rev-parse HEAD)" == "$head" ]] || fail 'HEAD changed during focused validation.'
  [[ -z "$(git status --porcelain --untracked-files=no)" ]] || fail 'Focused validation requires a clean tracked checkout.'
}

build_products() {
  check_source
  rm -f "$marker"
  swift test "${swift_test_flags[@]}" --test-product DICOMCoreTests list \
    2>&1 | tee "$log_dir/core-discovery.log"
  swift test "${swift_test_flags[@]}" --test-product DICOMKitTests list \
    2>&1 | tee "$log_dir/cli-discovery.log"
  check_source
  printf '%s\n' "$head" > "$marker"
}

run_tests() {
  check_source
  [[ -f "$marker" && "$(cat "$marker")" == "$head" ]] || fail 'Build these test products at this HEAD before using --skip-build.'
  swift test "${swift_test_flags[@]}" --test-product DICOMCoreTests \
    --skip-build --no-parallel --filter "$core_filter" \
    2>&1 | tee "$log_dir/core-tests.log"
  grep -Eq 'Test run with 81 tests in 5 suites passed' "$log_dir/core-tests.log" \
    || fail 'Expected all 81 selected Core tests in 5 suites to pass; zero or partial selection is not a pass.'
  swift test "${swift_test_flags[@]}" --test-product DICOMKitTests \
    --skip-build --no-parallel --filter "$cli_filter" \
    2>&1 | tee "$log_dir/cli-tests.log"
  grep -Fq "Test Suite 'ImageConverterOutputRulesTests' passed" "$log_dir/cli-tests.log" \
    || fail 'The selected CLI output-rules suite did not pass.'
  grep -Eq 'Executed 6 tests, with 0 failures \(0 unexpected\)' "$log_dir/cli-tests.log" \
    || fail 'Expected all 6 selected CLI XCTest cases to pass; zero or partial selection is not a pass.'
  grep -Eq 'Test run with 15 tests in 1 suite passed' "$log_dir/cli-tests.log" \
    || fail 'Expected all 15 selected bounded-input tests to pass; zero or partial selection is not a pass.'
  check_source
  printf 'Focused validation passed: 81 Core, 15 bounded-input and 6 CLI tests. Logs: %s\n' "$log_dir"
}

case "$phase" in
  build) build_products ;;
  run) run_tests ;;
  all) build_products; run_tests ;;
esac
