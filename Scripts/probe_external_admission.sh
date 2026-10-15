#!/bin/bash
# Focused bootstrap failure probe; no global limits or process-wide exhaustion.
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:-work/external-admission-bootstrap}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
xcrun clang -Wall -Wextra -Werror -dynamiclib Scripts/ExternalAdmissionBootstrapProbe.c \
    -o "$output/libExternalAdmissionBootstrapProbe.dylib"
xcrun swiftc -O -swift-version 6 -package-name DICOMKit -parse-as-library \
    -module-cache-path "$output/module-cache" \
    Sources/DICOMCore/DICOMExternalAllocationCallbacks.swift \
    Sources/DICOMCore/DICOMAllocationBudget.swift Sources/DICOMCore/DICOMMappedStorage.swift \
    Sources/DICOMCore/DICOMOutcomes.swift Sources/DICOMCore/DICOMManagedFailure.swift \
    Scripts/ExternalAdmissionBootstrapProbe.swift \
    -L "$output" -lExternalAdmissionBootstrapProbe -Xlinker -rpath -Xlinker "$output" \
    -o "$output/bootstrap-probe"
for mode in 0 1 2 3; do
    DYLD_INSERT_LIBRARIES="$output/libExternalAdmissionBootstrapProbe.dylib" \
        "$output/bootstrap-probe" "$mode" > "$output/mode-$mode.json"
done
cat "$output"/mode-*.json
