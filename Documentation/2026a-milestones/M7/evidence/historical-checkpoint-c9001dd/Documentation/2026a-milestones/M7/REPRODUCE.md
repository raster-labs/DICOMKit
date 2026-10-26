# Reproduce M7 qualification

Use the exact checkpoint/branch and Package.resolved, macOS arm64, Swift 6.4 and Xcode 27.0. The recorded host is macOS 27.0.1. Source and artifact hashes are in this directory. Each campaign needs a fresh output directory; a successful rerun does not establish a native GUI result.

## Integrated tests and CLI inventory

From the repository root:

```sh
export DICOMKIT_VERIFY_SCRATCH=/path/to/build-scratch
export DICOMKIT_VERIFY_CACHE=/path/to/package-cache
bash Scripts/verify_m7.sh /path/to/new-results/integrated
```

The script builds all products, checks 41 tools/147 routes, runs the M2–M6 scripts, focused M7 Core/diagnostic tests and the complete Studio product. Binary overrides are passed to tests rather than assuming a developer checkout. Optional harness skips remain visible.

## Static audit tools

Run `python3 -B -m unittest discover -s Scripts -p 'test_*audit_m*.py' -v` for all 48 regression tests. Run `Scripts/diff_cli.py`, `Scripts/diff_kit.py` and `Scripts/diff_studio.py` against the frozen official 2026a DocBook files using `--nema /path/to/standards`. The retained CLI/Kit results exit 0. Studio intentionally exits 1 for three visible finding checks: the absent anonymization-profile control (two checks) and script dry-run default difference. All 178 Studio callbacks execute with zero audit errors. Do not suppress these findings or equate static checks with runtime conformance.

## Independent software peers and codecs

Install the pinned `Scripts/m7-peer-requirements.txt` in a Python 3.12 environment with OpenSSL TLS 1.3. The recorded environment uses DCMTK 3.7.0, OpenJPEG, OpenJPH and libjxl; exact tool versions and hashes are in each provenance record. `dcmprscu`, `dcmprscp`, `dcmpsprt`, the DCMTK image codecs, `opj_compress/decompress`, `ojph_compress/expand`, `cjxl`, `djxl` and `jxlinfo` must be on PATH for their cases.

```sh
m7_python=/path/to/m7-python312-environment/bin/python
m6_python=/path/to/m6-print-environment/bin/python
bin_dir="$(swift build --disable-automatic-resolution --scratch-path "$DICOMKIT_VERIFY_SCRATCH" --show-bin-path)"
"$m7_python" Scripts/verify_m7_network_interop.py --bin-dir "$bin_dir" --output-dir /path/to/new-results/network
"$m7_python" Scripts/verify_m7_tls_interop.py --test-bundle "$bin_dir/DICOMNetworkTests.xctest" --output-dir /path/to/new-results/tls
"$m7_python" Scripts/verify_m7_codecs.py --bin-dir "$bin_dir" --output-dir /path/to/new-results/codecs
"$m6_python" Scripts/verify_m6_print_interop.py --bin-dir "$bin_dir" --output-dir /path/to/new-results/print
```

The print qualification used the separately preserved M6 environment (pydicom 2.4.4, pynetdicom 2.0.2, Pillow 11.3.0). Network/TLS/codec qualification used the pinned modern M7 environment. Do not silently exchange peer versions when comparing evidence. Bind synthetic peers only to loopback. TLS creates temporary certificates, uses custom per-test trust and does not change Keychain/system trust; exclude all generated private keys from shared evidence.

The codec runner's exit 0 means no unexpected failure. Read `totals.json`: refusals and interoperability limits are never codec passes. Full invocation executes 90 cases; unknown/empty case selection is refused. The retained DCMTK print peer limitation is similarly explicit.

## Actual Workshop execution harness

After building the Studio test product, use the final independently generated codec fixtures:

```sh
"$m6_python" Scripts/verify_m6_workshop.py --bin-dir "$bin_dir" --test-bundle "$bin_dir/DICOMStudioTests.xctest" --fixtures /path/to/new-results/codecs/fixtures --output-dir /path/to/new-results/workshop
"$m6_python" Scripts/verify_m6_workshop_images.py --bin-dir "$bin_dir" --test-bundle "$bin_dir/DICOMStudioTests.xctest" --codec-campaign /path/to/new-results/codecs --output-dir /path/to/new-results/workshop-images
```

Use the M6 peer environment for these scripts. They activate 18 plus seven ViewModel actions, isolated configuration directories and same-library loopback receivers. These are process/VM parity gates, not independent peers or native GUI. PNG/TIFF checks compare decoded pixels; PDF checks establish complete containers only.

## Final app and native acceptance

The retained `evidence/build_final_app.sh`, temporary scheme, build/signature logs and entitlement record show the exact local app build procedure. Its absolute paths are historical and must be adapted for another checkout. The script preserves normal project entitlements and isolates DEBUG print configuration through LSEnvironment; it does not weaken the sandbox. Do not change HOME or use the user's real printer registry or patient files.

Unlock the Mac and execute `evidence/native-final-checklist.json` against the exact signed app. Record actual UI inputs, visible outcomes, independent request/file/output checks, binary identity, and failures/skips per action. Exercise native file selection, preview/copy/import, Run/Stop, cross-direction CLI/app print and persistence after relaunch. A successful build, CLI replay or ViewModel invocation cannot replace this gate. Update M6/M7 acceptance and the global register only after the required native checks pass; then verify the exact pushed head. Do not merge main.
