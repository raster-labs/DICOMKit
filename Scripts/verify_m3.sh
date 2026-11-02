#!/bin/bash
# Query safety gates use locked dependencies, real processes and a synthetic peer.
set -euo pipefail
log_dir="${1:-m3-verification}"
mkdir -p "$log_dir"
log_dir="$(cd "$log_dir" && pwd)"
common=(--disable-automatic-resolution -Xswiftc -Xfrontend -Xswiftc -enable-cross-import-overlays)
if [[ -n "${DICOMKIT_VERIFY_SCRATCH:-}" ]]; then common+=(--scratch-path "$DICOMKIT_VERIFY_SCRATCH"); fi
if [[ -n "${DICOMKIT_VERIFY_CACHE:-}" ]]; then common+=(--cache-path "$DICOMKIT_VERIFY_CACHE"); fi
run_tests() {
  local product="$1" filter="$2" marker="$3" log="$log_dir/$1.log"
  swift test "${common[@]}" --test-product "$product" --filter "$filter" > "$log" 2>&1 || { tail -100 "$log"; return 1; }
  grep -F "$marker" "$log"
}
run_tests DICOMWebTests 'QIDO|DICOMwebServerTests|DICOMwebRequest|InMemoryStorageProvider|ServerCache|M3QueryProcessHarnessTests' "Test Suite 'QIDOResourcePolicyTests' passed"
run_tests DICOMNetworkTests 'QueryFilterPreflightTests|QueryJSONTextContextTests|QueryParentLevelKeyTests|QueryHierarchicalKeyTests|QueryServiceTests|QueryRetrieveCLIStandardTests|QueryKeysTests' "Test Suite 'QueryFilterPreflightTests' passed"
run_tests dicom-queryTests '.*' "Test Suite 'QueryLevelOptionTests' passed"
run_tests dicom-wadoTests '.*' "Test Suite 'QIDOOutgoingResourceTests' passed"
run_tests DICOMStudioTests 'M3Workshop|WorkshopShellArgumentSafetyTests|CLIWorkshopBasicAuthPreviewTests|NetworkToolWorkshopCLIParityTests|CLIWorkshopHelpersTests' 'Suite "M3 Workshop QIDO effective filters" passed'
for product in dicom-wado dicom-query; do
  swift build "${common[@]}" --product "$product" > "$log_dir/build-$product.log" 2>&1 || { tail -100 "$log_dir/build-$product.log"; exit 1; }
done
bin_dir="$(swift build "${common[@]}" --show-bin-path)"
python3 Scripts/verify_m3_queries.py --bin-dir "$bin_dir" --test-bundle "$bin_dir/DICOMWebTests.xctest" --output-dir "$log_dir/queries" > "$log_dir/process-tests.log" 2>&1 || { tail -80 "$log_dir/process-tests.log"; exit 1; }
cat "$log_dir/process-tests.log"
python3 -B Scripts/verify_m3_dimse.py --bin-dir "$bin_dir" --output-dir "$log_dir/dimse-cli" > "$log_dir/dimse-tests.log" 2>&1 || { tail -80 "$log_dir/dimse-tests.log"; exit 1; }
cat "$log_dir/dimse-tests.log"
