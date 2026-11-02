# Reproducing M1 verification

Use the locked dependencies and a macOS toolchain satisfying `Package.swift`
(Swift 6.4 in this run). Run from the checkout:

```sh
swift test --disable-automatic-resolution --test-product DICOMStudioTests \
  -Xswiftc -Xfrontend -Xswiftc -enable-cross-import-overlays \
  --filter 'WorkshopShellArgumentSafetyTests|CLIWorkshopBasicAuthPreviewTests|CLIWorkshopHelpersTests|NetworkToolWorkshopCLIParityTests'
swift test --disable-automatic-resolution --test-product DICOMToolboxTests \
  -Xswiftc -Xfrontend -Xswiftc -enable-cross-import-overlays
python3 -m unittest discover -s Scripts -p 'test_*_audit_m0.py' -v
xcodebuild -project DICOMStudio.xcodeproj -scheme DICOMStudio \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /absolute/path/to/build \
  -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  'OTHER_SWIFT_FLAGS=$(inherited) -Xfrontend -enable-cross-import-overlays' build
```

An optional `--scratch-path`/`--cache-path` can place Swift artifacts on another
volume. This run used a dedicated APFS build image on the external drive because
internal disk headroom was low. It reused locked dependency source copies, then
compiled current project sources; no cached product was used as current proof.

The tests execute real sh/zsh serialization oracles, the actual MWL parser, and
safe local subprocess probes. They require `/bin/sh`, `/bin/zsh` on macOS and
`/usr/bin/python3` for process fixtures. No PACS or external DICOMweb service is used.
Check suite names and nonzero counts; a discovered/compiled test bundle alone is
not a runtime pass. The focused workflow also rejects missing suite-success markers.

Materialize M0 `base.dcm` from `Scripts/audit_fixtures/m0/fixtures.json`, using the
SHA-256 in that manifest. Follow `ui-verification.json` for actual packaged-app steps.
Use a writable temporary directory, preserve the source, and give CLI and app
separate output paths. Compare complete bytes and independently decode the three
explicit-VR attributes recorded in `fixture-parity.json`.

For future verification, compare the changed-source and artifact hashes in
`verification.json`; any code, dependency or build-setting change requires the
relevant checks again. The final remote commit identity is available with its
`Command safety` Actions run and the task's remote verification deliverable.
