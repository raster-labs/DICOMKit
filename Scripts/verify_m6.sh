#!/bin/bash
# Print CLI, shared execution, protocol and Workshop contract regressions.
set -euo pipefail
log_dir="${1:-m6-verification}"
mkdir -p "$log_dir"
log_dir="$(cd "$log_dir" && pwd)"
common=(--disable-automatic-resolution -Xswiftc -Xfrontend -Xswiftc -enable-cross-import-overlays)
if [[ -n "${DICOMKIT_VERIFY_SCRATCH:-}" ]]; then common+=(--scratch-path "$DICOMKIT_VERIFY_SCRATCH"); fi
if [[ -n "${DICOMKIT_VERIFY_CACHE:-}" ]]; then common+=(--cache-path "$DICOMKIT_VERIFY_CACHE"); fi
for product in dicom-print dicom-printscp; do
  swift build "${common[@]}" --product "$product" > "$log_dir/build-$product.log" 2>&1 || { tail -100 "$log_dir/build-$product.log"; exit 1; }
done
run_tests() {
  local product="$1" filter="$2" marker="$3" log="$log_dir/$1.log"
  swift test "${common[@]}" --test-product "$product" --filter "$filter" > "$log" 2>&1 || { tail -100 "$log"; return 1; }
  grep -F "$marker" "$log"
  grep -E 'Executed .* tests?|Test run with .* tests? .*passed' "$log" | tail -3
}
run_tests dicom-printTests '.*' "Test Suite 'M6PrintSCUCommandTests' passed"
run_tests dicom-printscpTests '.*' "Test Suite 'M6SCPCommandTests' passed"
run_tests DICOMNetworkTests 'Print|NCreate|NSet|NAction|NDelete|NGet|NEvent|DIMSEN' "Test Suite 'M6PrintListenerStartupTests' passed"
run_tests DICOMPrintKitTests '.*' "Test Suite 'M6PrintSinkFailureTests' passed"
run_tests DICOMStudioTests 'M6' "Test Suite 'M6WorkshopExecutionTests' passed"
python3 -B -m unittest discover -s Scripts -p 'test_*audit_m*.py' > "$log_dir/audit-regressions.log" 2>&1 || { cat "$log_dir/audit-regressions.log"; exit 1; }
cat "$log_dir/audit-regressions.log"
# Native GUI, the opt-in Workshop campaign, independent peers and physical
# output are separate gates; none is inferred from this test-only CI job.
