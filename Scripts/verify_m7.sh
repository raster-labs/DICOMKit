#!/bin/bash
# Integrated local regressions. Independent peers and native GUI remain separate gates.
set -euo pipefail
log_dir="${1:-m7-verification}"
mkdir -p "$log_dir"
log_dir="$(cd "$log_dir" && pwd)"
common=(--disable-automatic-resolution -Xswiftc -Xfrontend -Xswiftc -enable-cross-import-overlays)
if [[ -n "${DICOMKIT_VERIFY_SCRATCH:-}" ]]; then common+=(--scratch-path "$DICOMKIT_VERIFY_SCRATCH"); fi
if [[ -n "${DICOMKIT_VERIFY_CACHE:-}" ]]; then common+=(--cache-path "$DICOMKIT_VERIFY_CACHE"); fi
swift build "${common[@]}" > "$log_dir/all-products-build.log" 2>&1
bin_dir="$(swift build "${common[@]}" --show-bin-path)"
export DICOMKIT_TEST_BIN_DIR="$bin_dir"
python3 -B Scripts/verify_m7_help_inventory.py --bin-dir "$bin_dir" --output-dir "$log_dir/help"
for milestone in 2 3 4 5 6; do
  bash "Scripts/verify_m${milestone}.sh" "$log_dir/m${milestone}" > "$log_dir/m${milestone}.log" 2>&1 || { tail -80 "$log_dir/m${milestone}.log"; exit 1; }
done
swift test "${common[@]}" --test-product DICOMCoreTests --filter 'M7JPEGExtendedProcessTests|M7NativePixelDataVRTests|JLICodec|JPEGInterchangeFormat|TransferSyntaxConverter' > "$log_dir/core-codec-tests.log" 2>&1
grep -F 'Suite "M7 JPEG Extended 8-bit coding process" passed' "$log_dir/core-codec-tests.log"
swift test "${common[@]}" --test-product DICOMKitTests --filter ConversionDiagnosticsTests > "$log_dir/conversion-diagnostics-tests.log" 2>&1
grep -F "Test Suite 'ConversionDiagnosticsTests' passed" "$log_dir/conversion-diagnostics-tests.log"
swift test "${common[@]}" --test-product DICOMWebTests > "$log_dir/dicomweb-tests.log" 2>&1
grep -E 'Suite "UPS Create identity.*passed' "$log_dir/dicomweb-tests.log"
grep -E 'Test run with [1-9][0-9]* tests .*passed' "$log_dir/dicomweb-tests.log"
swift test "${common[@]}" --test-product DICOMStudioTests > "$log_dir/studio-full-tests.log" 2>&1
grep -E 'Test run with [1-9][0-9]* tests .*passed' "$log_dir/studio-full-tests.log"
# The opt-in TLS/Workshop skips above never establish their external gates.
# Run verify_m7_{network,tls}_interop.py, verify_m7_codecs.py and native UI
# separately, with their documented dependencies and exact artifact identities.
