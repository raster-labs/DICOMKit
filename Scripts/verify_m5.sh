#!/bin/bash
# M5 Studio/Toolbox contracts with actual CLI and synthetic shared-engine checks.
set -euo pipefail
log_dir="${1:-m5-verification}"
mkdir -p "$log_dir"
log_dir="$(cd "$log_dir" && pwd)"
common=(--disable-automatic-resolution -Xswiftc -Xfrontend -Xswiftc -enable-cross-import-overlays)
if [[ -n "${DICOMKIT_VERIFY_SCRATCH:-}" ]]; then common+=(--scratch-path "$DICOMKIT_VERIFY_SCRATCH"); fi
if [[ -n "${DICOMKIT_VERIFY_CACHE:-}" ]]; then common+=(--cache-path "$DICOMKIT_VERIFY_CACHE"); fi
for product in dicom-anon dicom-script dicom-info dicom-qr dicom-server dicom-mwl; do
  swift build "${common[@]}" --product "$product" > "$log_dir/build-$product.log" 2>&1 || { tail -100 "$log_dir/build-$product.log"; exit 1; }
done
python3 -B Scripts/generate_m5_sr_precision_fixture.py --output-dir "$log_dir/sr-fixture"
export DICOMKIT_M5_SR_FIXTURE="$log_dir/sr-fixture/m5-sr-temporal-precision.dcm"
export DICOMKIT_M5_SR_RESULTS="$log_dir/sr-results.json"
export DICOMKIT_M5_TOOLBOX_EXPORT_DIR="$log_dir/toolbox-cli"
run_tests() {
  local product="$1" filter="$2" marker="$3" log="$log_dir/$1.log"
  swift test "${common[@]}" --test-product "$product" --filter "$filter" > "$log" 2>&1 || { tail -100 "$log"; return 1; }
  grep -F "$marker" "$log"
  grep -E 'Executed .* tests?|Test run with .* tests? .*passed' "$log" | tail -3
}
run_tests DICOMToolboxTests '.*' "Test Suite 'M5ToolboxContractTests' passed"
run_tests DICOMStudioTests 'M5|DICOMValueParserTests|CLIWorkshopHelpersTests|NetworkToolWorkshopCLIParityTests|WorkshopShellArgumentSafetyTests' "Test Suite 'M5WorkshopContractTests' passed"
run_tests DICOMRoundTripTests 'ScriptRoundTripTests' "Test Suite 'ScriptRoundTripTests' passed"
bin_dir="$(swift build "${common[@]}" --show-bin-path)"
python3 -B Scripts/verify_m5_toolbox.py --bin-dir "$bin_dir" --output-dir "$log_dir/toolbox-cli" > "$log_dir/toolbox-process.log" 2>&1 || { tail -100 "$log_dir/toolbox-process.log"; exit 1; }
cat "$log_dir/toolbox-process.log"
python3 -B Scripts/verify_m5_workshop.py --bin-dir "$bin_dir" --test-bundle "$bin_dir/DICOMStudioTests.xctest" --output-dir "$log_dir/workshop" > "$log_dir/workshop-process.log" 2>&1 || { tail -100 "$log_dir/workshop-process.log"; exit 1; }
cat "$log_dir/workshop-process.log"
