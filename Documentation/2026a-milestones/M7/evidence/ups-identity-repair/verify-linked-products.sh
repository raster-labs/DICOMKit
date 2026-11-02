#!/bin/bash
set -euo pipefail
task_root=/Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3
result="$task_root/work/m7/native-2026-10-26/ups-identity-repair"
cd "$task_root/work/DICOMKit-milestones"
common=(--disable-automatic-resolution --scratch-path /Volumes/DICOMKit-M1-build/spm
  --cache-path /Volumes/DICOMKit-M1-build/cache
  -Xswiftc -Xfrontend -Xswiftc -enable-cross-import-overlays)
export DICOMKIT_TEST_BIN_DIR=/Volumes/DICOMKit-M1-build/spm/out/Products/Debug
swift build "${common[@]}" > "$result/all-products-repaired.log" 2>&1
swift test "${common[@]}" --test-product DICOMStudioTests \
  --filter 'WebUPSStateTests|DataExchangeServiceTests|DataExchangeViewModelTests' \
  > "$result/studio-affected-workflows.log" 2>&1
grep -E "Test Suite '(WebUPSStateTests|DataExchangeServiceTests|DataExchangeViewModelTests)' passed" \
  "$result/studio-affected-workflows.log"
