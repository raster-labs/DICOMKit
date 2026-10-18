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
maps="$PWD/.build/out/Intermediates.noindex/GeneratedModuleMaps"
# Swift shares emitted specializations/metadata across source files. Link the
# complete real library products used by the Release dicom-info executable;
# partial source-file selection leaves unresolved public metadata dependencies.
# Its main and ArgumentParser products belong to the CLI, not DICOMKit.
link_file="$base/dicom-info-p.build/Objects-normal/arm64/dicom-info.LinkFileList"
objects=()
for name in J2KCore CompressionFamily J2KCodec J2KMetal J2KCodecNEON J2KFileFormat J2K3D \
            JPEGLS JLISwift JXLSwift DICOMCore DICOMDictionary JPIP DICOMKit; do
    objects+=("$products/$name.o")
done
inputs=("${objects[@]}" "$link_file" Scripts/VerifiedSourceWorkMetricsProbe.swift \
        Scripts/VerifiedSourceWorkMetricsProbe.c Scripts/probe_verified_source_metrics.sh \
        Scripts/DecimalScalarAllocations.c Sources/DICOMKit/Performance/VerifiedFileByteSource.swift \
        Sources/DICOMKit/Performance/BoundedSHA256.swift Sources/DICOMKit/Archive/ArchiveStore.swift \
        Package.swift Package.resolved \
        "$products/DICOMCore.swiftmodule/arm64-apple-macos.swiftmodule" \
        "$products/DICOMKit.swiftmodule/arm64-apple-macos.swiftmodule")
for name in AlignedPixelBuffer DICOMAllocationBudget DICOMMappedStorage DICOMByteBuffer DICOMManagedStorage DICOMOutcomes \
            DICOMManagedFailure DICOMExternalAllocationCallbacks DICOMExecutionReservation; do
    inputs+=("Sources/DICOMCore/$name.swift")
done
module_maps=()
for map in "$maps"/*.modulemap; do
    module_maps+=(-Xcc "-fmodule-map-file=$map")
    inputs+=("$map")
done
python3 - "$output/input-hashes.json" "$link_file" "${#objects[@]}" "${inputs[@]}" <<'PY'
import hashlib, json, pathlib, shlex, subprocess, sys
paths = [pathlib.Path(p).resolve() for p in sys.argv[4:]]
objects = paths[:int(sys.argv[3])]
listed = [pathlib.Path(p).resolve() for p in shlex.split(pathlib.Path(sys.argv[2]).read_text())]
excluded = {"main.o", "ArgumentParser.o", "ArgumentParserToolInfo.o"}
assert len(listed) == len(set(listed)), "Duplicate Release link input"
assert {p.name for p in listed if p.name in excluded} == excluded
assert {p for p in listed if p.name not in excluded} == set(objects), "Release dependency closure changed"
def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()
result = {"files": {str(p): digest(p) for p in paths},
          "linkedReleaseObjects": [str(p) for p in objects],
          "excludedCLIObjects": sorted(excluded),
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
def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()
inputs = json.loads((output / "input-hashes.json").read_text())
for name, expected in inputs["files"].items():
    assert digest(pathlib.Path(name)) == expected, ("Input changed", name)
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
          "artifactSHA256": {name: digest(output / name) for name in artifacts},
          "limits": "Single-threaded low-level descriptor capture/read/snapshot. Caller stack, fixture and callback storage are outside measured ownership. No worker/bootstrap, arbitrary callback, unmapping-interposer, or whole-program qualification claim."}
(output / "qualification.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps({"passed": True, "coldCalls": 3, "hotCalls": 96, "allocations": 0,
                  "receipt": str(output / "qualification.json")}))
PY
