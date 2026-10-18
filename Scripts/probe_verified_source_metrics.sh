#!/bin/bash
# Run only after the stabilized package Release build. This builds test drivers,
# never replacement library implementations. The invoking qualification owns the
# build/source attestation; this receipt binds the exact objects actually linked.
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:-work/verified-source-metrics}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
if [[ -e "$output/qualification.json" || -e "$output/input-hashes.json" ]]; then
    echo "Use a fresh evidence directory: $output" >&2
    exit 2
fi
products="$PWD/.build/out/Products/Release"
base="$PWD/.build/out/Intermediates.noindex/DICOMKit.build/Release"
core="$base/DICOMCore-t.build/Objects-normal/arm64"
kit="$base/DICOMKit-t.build/Objects-normal/arm64"
maps="$PWD/.build/out/Intermediates.noindex/GeneratedModuleMaps"
objects=("$kit/VerifiedFileByteSource.o" "$kit/BoundedSHA256.o")
for name in DICOMAllocationBudget DICOMMappedStorage DICOMByteBuffer DICOMManagedStorage DICOMOutcomes \
            DICOMManagedFailure DICOMExternalAllocationCallbacks DICOMExecutionReservation; do
    objects+=("$core/$name.o")
done
inputs=("${objects[@]}" Scripts/VerifiedSourceWorkMetricsProbe.swift \
        Scripts/VerifiedSourceWorkMetricsProbe.c Scripts/probe_verified_source_metrics.sh \
        Scripts/DecimalScalarAllocations.c Sources/DICOMKit/Performance/VerifiedFileByteSource.swift \
        Sources/DICOMKit/Performance/BoundedSHA256.swift Package.swift Package.resolved \
        "$products/DICOMCore.swiftmodule/arm64-apple-macos.swiftmodule" \
        "$products/DICOMKit.swiftmodule/arm64-apple-macos.swiftmodule")
for name in DICOMAllocationBudget DICOMMappedStorage DICOMByteBuffer DICOMManagedStorage DICOMOutcomes \
            DICOMManagedFailure DICOMExternalAllocationCallbacks DICOMExecutionReservation; do
    inputs+=("Sources/DICOMCore/$name.swift")
done
module_maps=()
for map in "$maps"/*.modulemap; do
    module_maps+=(-Xcc "-fmodule-map-file=$map")
    inputs+=("$map")
done
python3 - "$output/input-hashes.json" "${inputs[@]}" <<'PY'
import hashlib, json, pathlib, subprocess, sys
paths = [pathlib.Path(p).resolve() for p in sys.argv[2:]]
result = {"files": {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},
          "head": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
          "swift": subprocess.check_output(["xcrun", "swiftc", "--version"], text=True).strip(),
          "scope": "Actual linked Release objects; invoking qualification supplies build/source attestation."}
pathlib.Path(sys.argv[1]).write_text(json.dumps(result, indent=2) + "\n")
PY
xcrun clang -Wall -Wextra -Werror -dynamiclib Scripts/DecimalScalarAllocations.c \
    -o "$output/libDecimalScalarAllocations.dylib"
xcrun clang -Wall -Wextra -Werror -c Scripts/VerifiedSourceWorkMetricsProbe.c -o "$output/driver.o"
xcrun swiftc -O -swift-version 6 -parse-as-library -emit-object \
    -module-name VerifiedSourceWorkMetricsProbe -module-cache-path "$output/module-cache" \
    -I "$products" "${module_maps[@]}" Scripts/VerifiedSourceWorkMetricsProbe.swift -o "$output/wrapper.o"
xcrun swiftc -sdk "$(xcrun --show-sdk-path)" "$output/wrapper.o" "$output/driver.o" \
    "${objects[@]}" -Xlinker -dead_strip \
    -L "$output" -lDecimalScalarAllocations -Xlinker -rpath -Xlinker "$output" \
    -o "$output/verified-source-metrics-probe"
for scenario in --control empty single cross-block; do
    name="${scenario#--}"
    DYLD_INSERT_LIBRARIES="$output/libDecimalScalarAllocations.dylib" \
        "$output/verified-source-metrics-probe" "$scenario" > "$output/$name.json"
done
python3 - "$output" <<'PY'
import hashlib, json, pathlib, sys
output = pathlib.Path(sys.argv[1])
inputs = json.loads((output / "input-hashes.json").read_text())
for name, expected in inputs["files"].items():
    assert hashlib.sha256(pathlib.Path(name).read_bytes()).hexdigest() == expected, ("Input changed", name)
control = json.loads((output / "control.json").read_text())
assert control["passed"] and control["allocations"] > 0 and control["mappings"] == 1
scenarios = [json.loads((output / (name + ".json")).read_text())
             for name in ["empty", "single", "cross-block"]]
assert all(s["passed"] and s["calls"] == 33 and s["coldAllocations"] == 0 and
           s["hotAllocations"] == 0 and s["mappings"] == 33 * s["expectedMappingsPerCall"]
           for s in scenarios)
artifacts = ["input-hashes.json", "driver.o", "wrapper.o", "libDecimalScalarAllocations.dylib",
             "verified-source-metrics-probe", "control.json", "empty.json", "single.json", "cross-block.json"]
result = {"passed": True, "freshProcesses": 3, "coldCalls": 3, "hotCalls": 96,
          "control": control, "scenarios": scenarios,
          "artifactSHA256": {name: hashlib.sha256((output / name).read_bytes()).hexdigest() for name in artifacts},
          "limits": "Single-threaded low-level descriptor capture/read/snapshot. Caller stack, fixture and callback storage are outside measured ownership. No worker/bootstrap, arbitrary callback, unmapping-interposer, or whole-program qualification claim."}
(output / "qualification.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps({"passed": True, "coldCalls": 3, "hotCalls": 96, "allocations": 0,
                  "receipt": str(output / "qualification.json")}))
PY
