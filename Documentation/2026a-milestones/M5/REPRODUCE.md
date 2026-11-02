# Reproduce M5 qualification

Use the accepted M5 source revision, or reconstruct M4 baseline `441ae21ab09bbb18687baa06baa131831a3ac10d` in a separate checkout and overlay the 27 files in `evidence/source-snapshot/`. Verify [source-hashes.json](source-hashes.json) and the baseline inputs before reusing evidence. Do not run this historical gate against a tree containing concurrent M6 extraction and call it M5 evidence. The frozen binary manifest records the qualified artifacts; newer binaries require their own qualification.

## Automated and actual-CLI gates

From that repository root, use a fresh output directory and sufficient build storage:

```sh
DICOMKIT_VERIFY_SCRATCH=/absolute/path/to/spm-build \
DICOMKIT_VERIFY_CACHE=/absolute/path/to/package-cache \
bash Scripts/verify_m5.sh /absolute/path/to/new-m5-results
```

The script builds six required CLI products, generates the synthetic SR fixture, runs the Toolbox suite, focused Studio suites and ScriptRoundTripTests, exports actual validated Toolbox argv, and runs the real Toolbox/Workshop process oracles. It activates the Workshop harness separately with its request/output environment. The normal Studio run's opt-in skip is not a pass. The actual configured harness must pass and produce all 23 VM records. Keep expected nonzero negative cases; do not replace them with blanket exit-zero expectations.

Run the 30 Python extraction regressions from the same coherent source tree:

```sh
python3 -B -m unittest discover -s Scripts -p 'test_*_audit_m0.py' -v
```

Retain stdout/stderr and the real test exit status. The historical final audit used an isolated baseline archive plus frozen M5 overlay because M6 extraction was already in progress in the shared checkout. The mixed-tree failure is not a failure of this frozen M5 implementation and was not counted as a pass.

## Packaged app

Use a temporary unique app scheme so Xcode cannot choose the package library scheme of the same name. Run in a subshell so the temporary scheme is removed afterward:

```sh
(
  cp DICOMStudio.xcodeproj/xcshareddata/xcschemes/DICOMStudio.xcscheme \
    DICOMStudio.xcodeproj/xcshareddata/xcschemes/DICOMStudio-M5App.xcscheme
  trap 'rm -f DICOMStudio.xcodeproj/xcshareddata/xcschemes/DICOMStudio-M5App.xcscheme' EXIT
  xcodebuild -project DICOMStudio.xcodeproj -scheme DICOMStudio-M5App \
    -configuration Debug -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath /absolute/path/to/app-build \
    -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO \
    COMPILER_INDEX_STORE_ENABLE=NO \
    'OTHER_SWIFT_FLAGS=$(inherited) -Xfrontend -enable-cross-import-overlays' build
)
```

Confirm the build log contains DICOMStudioApp and a relinked app executable, then launch that bundle. Use only the generated synthetic files and an ephemeral loopback server. Do not use existing saved profiles or patient studies. Preserve fixture and binary hashes.

1. Workshop `dicom-script`: select live execution and verify Run is unavailable with CLI guidance. Select Dry Run on `valid.dcmscript` and record SUCCESS with no commands executed. Validate it. Generate the workflow template using Generate Template. Run the conditional-pipeline negative fixture and record the line-2 error. Preserve a full result snapshot or explicit operator observation, not just a no-change AX delta.
2. Workshop `dicom-anon`: use `burned-in-synthetic.dcm` with pixel cleaning disabled. In Beginner advanced disclosure verify one PHI control; false refuses and leaves no output. Enable it, switch to Advanced and verify one retained control/one flag. Run and independently inspect Patient Identity Removed = NO and unchanged pixel bytes. This intentionally does not claim safe de-identification.
3. Workshop `dicom-qr`: use the synthetic loopback fixture and explicit Study UID from `server-ready.json`. Review must return the study without writing a file; Auto must write one file. Repeat the equivalent CLI calls against the same fixture and compare raw dataset bytes, excluding independently generated File Meta where appropriate. The retained request/argv records provide the exact options; ephemeral ports must be refreshed.
4. Import the generated `m5-sr-temporal-precision.dcm`, open M5 Temporal Precision in the viewer, and inspect all sixteen expected values from the fixture manifest. Select/copy the positive-offset fractional value and paste into a harmless text field to verify the exact string. Hash the original file before and after display/copy. Do not edit existing studies.

Toolbox is a separate library with no packaged application in this repository. Its real form/validated argv/history coverage and CLI process oracle are the applicable gates; do not claim the Studio UI proves Toolbox behavior. Unsupported saved profiles/flags/output settings must be rebuilt using current controls after actionable refusal; no semantic auto-migration is promised. The backup oracle expects the original input bytes at the selected output path with `.backup` appended.

Record separate framework counts, opt-in skips and activated results, CLI/VM cases, native GUI observations, source/package/binary hashes, and limitations. Unrelated M0 gaps, deferred enhancements, hardware, broad interoperability and remote exact-head CI are outside this local M5 record.
