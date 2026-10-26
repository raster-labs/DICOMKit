# Reproducing the M6 checkpoint

Use M5 baseline `c91c79d9655929eef97ccffd601a9ef4297241d6` plus the exact files in `evidence/source-overlay.zip`, removing only the five baseline paths listed in `source-hashes.json`. The overlay does not contain a Git repository or change global settings. Alternatively use the parent-pushed milestone commit once recorded. Verify SHA256 against `source-hashes.json` before comparing results. These instructions authorize no merge or physical print.

## Focused automated gate

The recorded environment is macOS arm64, Debug, Xcode 27. The repository's Swift toolchain selector and package requirements still apply. Use an isolated scratch directory with sufficient disk space:

```sh
DICOMKIT_VERIFY_SCRATCH=/absolute/path/to/scratch \
DICOMKIT_VERIFY_CACHE=/absolute/path/to/cache \
bash Scripts/verify_m6.sh /absolute/path/to/new-logs
```

The script builds both print executables and runs the two command suites, focused Print/DIMSE-N network suite, PrintKit, Studio M6 tests and 38 audit regressions. It checks named test markers; a build or zero-test selection does not count as a pass. The current expected result is 932 passed test methods plus 2 explicit skips. CI runs this bounded script; it does not establish GUI or independent-peer qualification.

The external Workshop harness was separately activated for the recorded 18 baseline and 7 image-extension actions. Drivers and corpus are preserved as `evidence/run_workshop_campaign.py`, `evidence/run_workshop_image_extension.py` and `evidence/workshop-requests.json`. They accept current `--bin-dir`, `--test-bundle` and new `--output-dir`; the baseline also accepts `--fixtures` (gray8/gray12/rgb8 from the independent campaign) and `--requests`. The extension accepts `--codec-campaign`; use the preserved `evidence/image-control-inputs` directory, whose native and independent DCMTK-generated RLE/JPEG inputs match the recorded fixture hashes. Its preserved generated fixtures are under `evidence/workshop-image-extension/fixtures/`. The drivers use isolated Debug settings paths. Do not interpret the ordinary suite's skip as execution of these configured actions.

The additional 220 catalog tests are preserved in `evidence/catalog-regression-tests.log` and are reported separately; their three suites are the CLI Workshop Service, Helpers and ViewModel suites.

## Independent software peers

Install release-matched DCMTK 3.7.0 tools (`dcmprscp`, `dcmprscu`, `dcmpsprt`). In an isolated Python 3.9+ virtual environment use `pydicom==2.4.4`, `pynetdicom==2.0.2`, and `Pillow==11.3.0`. The preserved installation log and provenance record the actual environment. No NumPy or DICOMKit parser is used for the independent wire assertions.

```sh
/path/to/venv/bin/python -B Scripts/verify_m6_print_interop.py \
  --bin-dir /absolute/path/to/current/products \
  --dcmtk-dir /absolute/path/to/dcmtk/bin \
  --output-dir /absolute/path/to/new-interop-evidence
```

The output directory must not exist. The runner generates synthetic files, uses ephemeral loopback ports, starts only tracked bounded processes and stops them, and never enables paper output. Every case keeps raw traffic and decoded request/response data. `--list` performs no networking; repeat `--case ID` for focused cases. A normal qualification result is 24 passes and one `unqualified_peer` DCMTK disabled-LUT probe, with no failures. The independent refused-LUT test is PY-F08. A missing peer or failed assertion is not a pass.

The preserved canonical index combines the complete final campaign with a single PY-F08 diagnostic-oracle rerun. Product and peer binary hashes match across both. Initial outcomes remain available; they are not substituted into the passing count.

For later native/VM checks, `--peer-only --peer-seconds 900` runs a bounded recording peer and writes `endpoint.json` with its port, AE title and synthetic fixture paths. This mode produces observations only; it never assigns passing status. Both grayscale/color meta SOP classes and the separately negotiated optional LUT/annotation/Print Job contexts are available. The Print Job UID announced in the endpoint is usable after a send. Terminate the tracked peer normally or let its stated deadline expire.

## Native app gate — still pending

After the Mac is unlocked, rebuild and identify the exact packaged `DICOMStudio.app`, verify its source/binary identity, and run both tools in **CLI Workshop**. Exercise all ten commands and compare visible values, effective argv, actual requests/results and files against matching CLI cases. Use native Browse grants for isolated inputs/config/output. Confirm registry persistence, cancellation/restart, listener status, leaving the view and application shutdown; test CLI→app and app→CLI as well as an independent peer. Keep the effective displayed settings location and app sandbox behavior explicit.

No Print Center action, test-host ViewModel action, app build or copied command preview substitutes for this gate. Do not mark M6 complete until AC03/AC04 have actual packaged Workshop evidence. Physical device negotiation/output and calibration remain separate, unexecuted hardware gates.
