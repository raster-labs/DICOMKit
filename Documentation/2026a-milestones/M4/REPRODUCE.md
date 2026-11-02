# Reproducing M4 service verification

Use locked dependencies, macOS, Swift 6.4 and Xcode 27. From the repository root:

```sh
bash Scripts/verify_m4.sh /absolute/path/to/new-m4-verification
```

Use a fresh output directory. Optional `DICOMKIT_VERIFY_SCRATCH` and
`DICOMKIT_VERIFY_CACHE` select existing build/dependency caches. The script builds
six required CLI products, runs focused tests in seven test products, then runs
the three independent Python process campaigns. It captures DIMSE commands,
capability documents, subprocess results and binary/dataset hashes. Opt-in XCTest
harnesses are skipped in the normal invocation and explicitly activated by the
process campaigns. Swift Testing and XCTest counts are recorded separately.

The capabilities campaign uses the production DICOMweb router through a test-only
HTTP listener, exercises negotiation and CORS, validates WADL against checked-in
W3C schemas offline, and runs real dicom-wado requests. The durability campaign
uses independently constructed Part 10 fixtures, real dicom-server processes,
store/restart/query/retrieve calls, conflicting retransmissions and startup
refusals. The cancellation tests use controlled delays and capture raw commands;
the Python FE00 peer separately verifies client presentation and exit status.

Run the existing 30 audit regressions separately:

```sh
python3 -B -m unittest discover -s Scripts -p 'test_*_audit_m0.py' -v
```

For packaged checks, build a temporary uniquely named copy of the checked-in app
scheme as described in M2/REPRODUCE.md, confirm the build selects DICOMStudioApp
and relinks its bundle, then remove the temporary scheme. Record the app binary
hash. Automated ViewModel tests do not replace launching the actual app.

Run `Scripts/m4_client_outcome_peer.py --help` for the controlled peer. In
Workshop, use its loopback port and synthetic identifiers `M4ZERO` and `M4PARTIAL`
for JSON C-FIND, then the peer's synthetic study for C-MOVE and C-GET. Check ERROR,
FE00, partial results, final counts and a completed history entry. Compare the
same CLI invocations with saved raw identifier/response captures. This peer
supplies controlled final outcomes; it is not a C-CANCEL server oracle.

For WADO, run `Scripts/verify_m4_capabilities.py --serve` with the same `--bin-dir`,
`--test-bundle` and a fresh `--output-dir`. Read `http-ready.json` and `fixtures.json`;
retrieve its synthetic instance through Workshop and the CLI, and compare bytes.
Stop the listener with `stop-http` in its output directory. A serve-only results
file is not a completed capability campaign; record actual GUI outcomes separately.

For restart UI checks, retain the synthetic storage produced by the durability
campaign, restart dicom-server with `--database filesystem` and that same storage,
then run Workshop study query and C-GET. Independently parse the retrieved dataset
and compare SOP identity and raw dataset bytes with the original fixture. Stop
only the test processes started for this run and close the app when finished.

Record screenshots, visible status/console evidence and raw requests separately.
Accessibility truncation prevents a blanket claim of full GUI console byte
equality. Do not add a new server tool or cancellation button for these checks.
Do not count unavailable external interoperability, platform/device execution or
power-loss tests as passed.
