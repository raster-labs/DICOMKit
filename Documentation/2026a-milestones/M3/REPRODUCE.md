# Reproducing M3 query verification

Use the locked dependencies and macOS Swift 6.4 / Xcode 27 toolchain. Choose a
fresh output directory for each run; the DIMSE gate refuses to overwrite captures:

```sh
bash Scripts/verify_m3.sh /absolute/path/to/m3-verification
```

Optional `DICOMKIT_VERIFY_SCRATCH` and `DICOMKIT_VERIFY_CACHE` select existing
external build and dependency caches. The script runs focused server, provider,
client, command parser and Workshop tests, then builds the actual CLI products.
The Python campaign constructs synthetic Explicit VR Little Endian Part 10
datasets independently of DICOMKit's writer. It verifies expected result UIDs,
attribute values and request paths, including UTF-8 and nested sequence items.
Each malformed/extreme pagination probe runs in a separate XCTest process, so
a process termination is a failed check rather than a lost test suite.

The opt-in `M3QueryProcessHarnessTests` harness is intentionally skipped in the
normal Swift test invocation. The Python campaign invokes it explicitly with
fixtures and records its exit status. The HTTP adapter is test code: the
production DICOMwebServer remains a request router for an embedding server.

For packaged-app QIDO checks, build the app with a temporary uniquely named
copy of the checked-in app scheme, as described in M2/REPRODUCE.md. Confirm the
log selects **DICOMStudioApp** and relinks the app bundle before launching it.
Run the synthetic loopback bridge:

```sh
python3 Scripts/verify_m3_queries.py --serve \
  --bin-dir /absolute/path/to/Products/Debug \
  --test-bundle /absolute/path/to/Products/Debug/DICOMWebTests.xctest \
  --output-dir /private/tmp/dicomkit-m3-qido
```

`http-ready.json` contains the actual loopback URL; `fixtures.json` supplies the
synthetic UIDs. In Workshop, exercise all six resource forms and compare saved
`captures.json` requests with the preview and equivalent CLI invocation. Set
all four PPS/request-attribute filters at series level, switch to studies and
back, then to unscoped/study-scoped/series-scoped instances. Verify exclusion
and restoration in both the form and actual requests. Change tools and verify
the values clear. Create `stop-http` in the capture directory when finished.

For DIMSE, `Scripts/m3_dimse_capture_peer.py` is an independent Python standard
library loopback C-FIND receiver. It retains raw command/identifier bytes and
decoded fields. `Scripts/verify_m3_dimse.py` runs the CLI cases; the peer can
also be run directly with a fresh capture directory for the packaged app.
Check the saved association count before and after rejected filter combinations.
These peers contain only fabricated patients and identifiers and are not
general-purpose PACS implementations.

Record app artifact hashes and actual UI outcomes separately from ViewModel
tests. Generic server routes without Workshop controls use explicit
UI-not-applicable entries; do not introduce additional tools to satisfy an
automated server test. Later milestones, external vendors and physical printing
remain outside this focused M3 qualification.
