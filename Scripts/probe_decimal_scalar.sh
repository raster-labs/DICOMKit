#!/bin/bash
# Run after: swift build -c release --target DICOMCore
# Links the real package objects; never substitutes a source-only parser build.
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:-work/strict-borrowed-ds}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
products="$PWD/.build/out/Products/Release"
objects="$PWD/.build/out/Intermediates.noindex/DICOMKit.build/Release/DICOMCore-t.build/Objects-normal/arm64"
maps="$PWD/.build/out/Intermediates.noindex/GeneratedModuleMaps"
xcrun clang -Wall -Wextra -Werror -dynamiclib Scripts/DecimalScalarAllocations.c \
    -o "$output/libDecimalScalarAllocations.dylib"
xcrun clang -Wall -Wextra -Werror -c Scripts/DecimalScalarProbe.c -o "$output/driver.o"
module_maps=()
for map in "$maps"/*.modulemap; do module_maps+=(-Xcc "-fmodule-map-file=$map"); done
xcrun swiftc -O -swift-version 6 -parse-as-library -emit-object \
    -module-name DecimalScalarProbe -module-cache-path "$output/module-cache" \
    -I "$products" "${module_maps[@]}" Scripts/DecimalScalarProbe.swift -o "$output/wrapper.o"
xcrun swiftc -sdk "$(xcrun --show-sdk-path)" "$output/wrapper.o" "$output/driver.o" \
    "$objects/DICOMDecimalString+Scalar.o" \
    -L "$output" -lDecimalScalarAllocations -Xlinker -rpath -Xlinker "$output" \
    -o "$output/decimal-scalar-probe"
python3 Scripts/audit_scalar_setup.py --decimal-scalar "$output/call-closure.json" "$output/wrapper.o"
DYLD_INSERT_LIBRARIES="$output/libDecimalScalarAllocations.dylib" \
    python3 Scripts/qualify_decimal_scalar.py "$output/decimal-scalar-probe" "$output/numerical-allocation.json"
