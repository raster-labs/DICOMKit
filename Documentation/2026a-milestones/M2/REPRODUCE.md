# Reproducing M2 verification

Use the locked dependencies and macOS Swift 6.4 / Xcode 27 toolchain. From the
repository root, run:

```sh
bash Scripts/verify_m2.sh /absolute/path/to/m2-verification
```

Optional `DICOMKIT_VERIFY_SCRATCH` and `DICOMKIT_VERIFY_CACHE` environment
variables select external Swift build/cache directories. The script builds
the actual CLI products before spawn-based checks, runs the selected test
products, verifies that required suites executed, and runs independent Python
inspection of emitted Part 10 bytes. It does not contact an external PACS.
The integration fixtures are synthetic attribute datasets, not complete IODs.

The test scope includes stored-value grammar, calendar boundaries, supported
character sets and item inheritance/overrides; transactional tag edits;
dictionary VR, File Meta and nested validation; UPS request handling and MPPS
emitted datasets; and Workshop execution and command-preview regressions.
The MPPS receiver capture test is explicitly opt-in and skipped during the
ordinary automated run. Its skip is not a passed interoperability gate.

Build the packaged app separately. Give the checked-in app scheme a temporary
unique name because Xcode may select the package library scheme also named
DICOMStudio. Verify the log builds **DICOMStudioApp** and relinks the app bundle:

```sh
cp DICOMStudio.xcodeproj/xcshareddata/xcschemes/DICOMStudio.xcscheme \
  DICOMStudio.xcodeproj/xcshareddata/xcschemes/DICOMStudio-M2App.xcscheme
trap 'rm -f DICOMStudio.xcodeproj/xcshareddata/xcschemes/DICOMStudio-M2App.xcscheme' EXIT
xcodebuild -project DICOMStudio.xcodeproj -scheme DICOMStudio-M2App \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /absolute/path/to/app-build \
  -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  'OTHER_SWIFT_FLAGS=$(inherited) -Xfrontend -enable-cross-import-overlays' build
```

Use a temporary directory for GUI fixtures and outputs. Do not use the user's
study library or saved server profiles. `ui-verification.json` records the
actual packaged-app cases, observed statuses, and output/capture comparisons.
ViewModel tests alone do not establish that those GUI checks ran.

For an actual MPPS client/Workshop capture, set `DICOMKIT_M2_CAPTURE_DIR` to a
fresh directory and run `DICOMNetworkTests` with filter
`MPPSReferenceIntegrityTests/testManualMPPSCapturePeer`. `ready.json` supplies
the loopback port. Run the synthetic CLI and Workshop updates against that
port with explicit CT/MR/SC classes, then create `stop` in the capture
directory. The harness has a 600-second limit and saves N-SET dataset bytes
plus an independent decoded reference list. Mixed-class requests are covered
through the typed service API because the existing CLI/Workshop form accepts
one class for its image list. No new mixed-class import feature is claimed.

UPS create/retrieve/search/update server behavior is exercised by
`UPSScheduledDateTimeTests` through real request routing and independent JSON
and instant inspection. Packaged-app capture exercises the existing UPS
client route. The Workshop has no generic UPS attribute-update route, so that
server update case is explicitly UI-not-applicable rather than an unrun GUI
success. State-change operations are a separate contract.

Use the verification manifest to compare source, package-lock and artifact
hashes before reusing evidence. Changed implementation or build settings
invalidate the affected checks. This milestone does not qualify a clinical
deployment, an external PACS, physical printing, or the deferred milestones.
