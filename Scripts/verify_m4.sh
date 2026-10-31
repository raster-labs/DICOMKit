#!/bin/bash
# M4 service reliability gates; dependencies remain locked.
set -euo pipefail
log_dir="${1:-m4-verification}"
mkdir -p "$log_dir"
log_dir="$(cd "$log_dir" && pwd)"
common=(--disable-automatic-resolution -Xswiftc -Xfrontend -Xswiftc -enable-cross-import-overlays)
if [[ -n "${DICOMKIT_VERIFY_SCRATCH:-}" ]]; then common+=(--scratch-path "$DICOMKIT_VERIFY_SCRATCH"); fi
if [[ -n "${DICOMKIT_VERIFY_CACHE:-}" ]]; then common+=(--cache-path "$DICOMKIT_VERIFY_CACHE"); fi
export DICOMKIT_M4_CAPTURE_DIR="$log_dir/cancellation-wire"
export DICOMKIT_M4_CAPABILITIES_EXPORT="$log_dir/capabilities-export"
run_tests() {
  local product="$1" filter="$2" log="$log_dir/$1.log"
  swift test "${common[@]}" --test-product "$product" --filter "$filter" > "$log" 2>&1 || { tail -100 "$log"; return 1; }
  grep -E 'Executed .* tests?|Test run with .* tests? .*passed' "$log" | tail -3
}
for product in dicom-server dicom-send dicom-query dicom-retrieve dicom-wado dicom-qr; do
  swift build "${common[@]}" --product "$product" > "$log_dir/build-$product.log" 2>&1 || { tail -100 "$log_dir/build-$product.log"; exit 1; }
done
run_tests DICOMWebTests 'M4Capabilities|CapabilitiesTests|DICOMwebServerTests|QIDOResourcePolicyTests'
run_tests dicom-serverTests '.*'
run_tests DICOMNetworkTests 'QueryCancellationOutcomeTests|QueryServiceTests|RetrieveServiceTests|QueryFilterPreflightTests|QueryRetrieveCLIStandardTests|DIMSEConformanceTests|DIMSENStatusText2026aTests|NetworkConsole'
run_tests dicom-queryTests '.*'
run_tests dicom-retrieveTests '.*'
run_tests dicom-wadoTests '.*'
run_tests DICOMStudioTests 'M4ClientOutcomeHarnessTests|M3WorkshopDIMSEFilterTests|NetworkToolWorkshopCLIParityTests|CLIWorkshopHelpersTests'
bin_dir="$(swift build "${common[@]}" --show-bin-path)"
python3 -B Scripts/verify_m4_clients.py --bin-dir "$bin_dir" --test-bundle "$bin_dir/DICOMStudioTests.xctest" --output-dir "$log_dir/clients" > "$log_dir/client-process.log" 2>&1 || { tail -100 "$log_dir/client-process.log"; exit 1; }
cat "$log_dir/client-process.log"
python3 -B Scripts/verify_m4_durability.py --bin-dir "$bin_dir" --test-bundle "$bin_dir/DICOMStudioTests.xctest" --output-dir "$log_dir/durability" > "$log_dir/durability-process.log" 2>&1 || { tail -100 "$log_dir/durability-process.log"; exit 1; }
cat "$log_dir/durability-process.log"
python3 -B Scripts/verify_m4_capabilities.py --bin-dir "$bin_dir" --test-bundle "$bin_dir/DICOMWebTests.xctest" --output-dir "$log_dir/capabilities" > "$log_dir/capabilities-process.log" 2>&1 || { tail -100 "$log_dir/capabilities-process.log"; exit 1; }
cat "$log_dir/capabilities-process.log"
