#!/bin/bash
# Focused M2 runtime gates. Optional cache locations keep local builds off a full disk.
set -euo pipefail
log_dir="${1:-m2-verification}"
mkdir -p "$log_dir"
common=(--disable-automatic-resolution -Xswiftc -Xfrontend -Xswiftc -enable-cross-import-overlays)
if [[ -n "${DICOMKIT_VERIFY_SCRATCH:-}" ]]; then common+=(--scratch-path "$DICOMKIT_VERIFY_SCRATCH"); fi
if [[ -n "${DICOMKIT_VERIFY_CACHE:-}" ]]; then common+=(--cache-path "$DICOMKIT_VERIFY_CACHE"); fi
run_tests() {
  local product="$1" filter="$2" marker="$3" log="$log_dir/$1.log"
  swift test "${common[@]}" --test-product "$product" --filter "$filter" > "$log" 2>&1 || { tail -100 "$log"; return 1; }
  grep -F "$marker" "$log"
}
run_tests DICOMCoreTests 'DICOMValueRulesTests|DICOMDateTimeFormattingTests|DataElementTextContextTests|DataElementTests|DataElementByteOrderTests|CharacterSetHandlerTests|CharacterSetISO2022Tests|DICOMDateTests|DICOMTimeTests|DICOMDateTimeTests' "Test Suite 'DICOMValueRulesTests' passed"
run_tests dicom-tagsTests '.*' 'passed'
run_tests dicom-validateTests '.*' "Test Suite 'M2AttributeIntegrityTests' passed"
run_tests DICOMKitTests 'TagEditIntegrityTests|ToolEngineStandardTests|TextEncodingIntegrityTests|FileMetaMediaStorageUIDTests|MetadataDiscovery' 'Suite "M2 text encoding and edited identity integrity" passed'
run_tests DICOMWebTests 'UPSScheduledDateTimeTests|UPSTests|UPSEventSystemTests' 'Suite "UPS scheduled DICOM DT round trips" passed'
for product in dicom-tags dicom-validate dicom-mpps dicom-mwl dicom-wado; do
  swift build "${common[@]}" --product "$product" > "$log_dir/build-$product.log" 2>&1 || { tail -100 "$log_dir/build-$product.log"; exit 1; }
done
run_tests DICOMNetworkTests 'MPPSReferenceIntegrityTests|MPPSDataSetConformanceTests|MWLToMPPSWorkflowConformanceTests|MWLMPPSCLIEndToEndTests' "Test Suite 'MPPSReferenceIntegrityTests' passed"
run_tests DICOMStudioTests 'M2WorkshopAttributeTests|M2WorkshopMPPSReferenceTests|WorkshopShellArgumentSafetyTests|CLIWorkshopBasicAuthPreviewTests|NetworkToolWorkshopCLIParityTests' 'Suite "M2 Workshop attribute execution" passed'
bin_dir="$(swift build "${common[@]}" --show-bin-path)"
python3 Scripts/verify_m2_attributes.py --bin-dir "$bin_dir" --output-dir "$log_dir/cli" > "$log_dir/cli-tests.log" 2>&1 || { cat "$log_dir/cli-tests.log"; exit 1; }
cat "$log_dir/cli-tests.log"
