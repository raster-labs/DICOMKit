# Reproduce M6 software qualification

M6 is complete for the recorded finite macOS arm64 software scope. Reproduction creates new evidence; it must not overwrite the historical captures or imply physical printing, all-platform support or M7 completion. The exact final native package/source identity is in [native-closure.json](native-closure.json). The old source overlay and 24 October build/test records remain historical, not a substitute for the final repaired package.

## Build and focused gates

From the repository root, with an isolated sufficiently sized build/cache location:

```sh
DICOMKIT_VERIFY_SCRATCH=/absolute/path/to/scratch \
DICOMKIT_VERIFY_CACHE=/absolute/path/to/cache \
bash Scripts/verify_m6.sh /absolute/path/to/new-logs
```

The script builds both print executables, runs real command/parser, network Print/DIMSE-N, PrintKit and Studio suites and audit regressions, and checks executed markers. A zero-test selection is not a pass. Historical M6 recorded 932 passes and 2 skips; the M7 descendant rerun recorded 933 and 1 ordinary opt-in skip because the independent DCMTK fixture became available. Later native repairs additionally have 20 SCU/20 SCP command passes, full Studio repair evidence and the 5-test actual-form gate; consult the exact logs rather than assuming one total applies to every source epoch.

## Independent software peers and CLI/VM comparisons

Use release-matched DCMTK 3.7.0 (`dcmprscp`, `dcmprscu`, `dcmpsprt`). Use an isolated Python 3.9+ environment with `pydicom==2.4.4`, `pynetdicom==2.0.2`, `Pillow==11.3.0`. Keep this M6 peer environment separate from the M7 codec environment if their package versions differ.

```sh
/path/to/m6-python -B Scripts/verify_m6_print_interop.py \
  --bin-dir /absolute/path/to/current/products \
  --dcmtk-dir /absolute/path/to/dcmtk/bin \
  --output-dir /absolute/path/to/new-interop-evidence
```

The output directory must not exist. The runner generates synthetic files, uses ephemeral loopback ports and bounded tracked processes, and never enables paper output. `--list` performs no networking; repeat `--case ID` for selected cases. The finite expected qualification is 24 passes and 1 `unqualified_peer` disabled-LUT probe, not 25 passes. PY-F08 supplies independent refused-context coverage. Missing peers or failed assertions remain failures/unexecuted. Raw traffic, decoded DIMSE and binary/fixture hashes are retained.

The actual ViewModel drivers are promoted in the repository as `Scripts/verify_m6_workshop.py`, `Scripts/verify_m6_workshop_images.py` and `Scripts/m6-workshop-requests.json`. Consult their `--help` for explicit `--bin-dir`, `--test-bundle` and fresh `--output-dir`. The baseline uses `--fixtures`/`--requests`; the image extension uses `--codec-campaign`. Use the independent synthetic gray8/gray12/rgb8 and DCMTK RLE/JPEG fixtures corresponding to that campaign. The expected finite result is 18 baseline plus 7 image actions and matching CLI comparisons, covering all 10 commands. These are actual test-host VM actions, not native GUI proof.

## Actual packaged Workshop gate

Build, sign with the normal project entitlements and identify the exact app before native execution. Use **CLI Workshop**, isolated synthetic paths and explicit native Browse grants. The preserved [print run card](evidence/native-2026-10-26/print-run-card.md) contains concrete values and commands; its original absolute paths identify the recorded run and must be relocated deliberately for a new run. The [evidence index](evidence/native-2026-10-26/evidence-index.json) maps the original root to this bundled evidence. Do not use real patient files, real printers or real paper queues.

1. Exercise all six SCU and four SCP commands. Compare visible values, imported/copied argv and actual outputs to an exact CLI invocation. Use structured argv; never shell-evaluate copied text. Isolate registry/config paths via the existing Debug seam/injected context, without repurposing HOME or adding unsupported flags.
2. Verify registry persistence/default/duplicate/remove/empty behavior and status/job text/JSON. Preserve literal/repeated inputs and row order. Cover dry-run and meaningful invalid option combinations before network activity.
3. Check gray/raw12/RGB, RLE/JPEG and frame/all-frame outputs; compare decoded pixels and receiver counts. Run loopback CLI→Workshop and Workshop→CLI plus independent peers. Record AE denial/allow and protocol warnings/failures.
4. Exercise config inheritance and explicit enabled/disabled flags, save/reload/save-before-gather, simulate/queues, Stop/restart/duration/max-film, occupied port, view departure and app quit/rebind. Check sink failures, inaccessible output, file-as-directory refusal, new child creation, filename tokens and native Open. Preserve paper opt-in refusal; do not print physically.
5. Confirm readable narrow forms in the actual split-pane hierarchy, Raw off/on argv and a final native action in each tool. The recorded final menu app has SCU dry-run and SCP status with exact 11-field CLI JSON equality. An isolated control test or app build alone cannot replace these native receipts.

Earlier partial reports retain their original states; final criterion reconciliation is [native-closure.json](native-closure.json). Reuse requires exact unchanged-service/source-dispatch evidence, as demonstrated by the final identity record; later generic/UI changes are not automatically equivalent. Never count a clipped initial form, inaccessible-config fallback, zero-test output or failed oracle as a native pass.

## Recheck retained PDF artifacts without product execution

Install `pypdf`, Pillow and Poppler `pdftoppm` (recorded Poppler 26.05.0). Copy the bundled native evidence root to a fresh writable directory, then run:

```sh
/path/to/pdf-python -B /absolute/path/to/copied-evidence/verify_pdf_print_outputs.py \
  --root /absolute/path/to/copied-evidence \
  --renderer /absolute/path/to/pdftoppm
```

This only reads the captured PDF/TIFF/PNG files and generates independent render/comparison records in that copy. Expected result: 33 passed checks. Exact native/CLI full-page raster equality and exact embedded film-image/companion equality are different assertions. Interpolated/ICC-managed rendered PDF pixels need not equal unrendered source pixels; the original cross-format oracle failure is preserved and explained, without tolerance-based masking. No product, peer or physical printer is launched.

The other bundled inspectors preserve the recorded absolute root/replay plans. To reuse them elsewhere, change only evidence-root paths in a scratch copy, retain source hashes and inspect requested inputs; do not invoke archived replay plans against stale endpoints. The canonical native captures are not recreated by an automated VM run.

## Boundaries

No native Print Center substitution, real paper/film/calibration guarantee, clinical or all-IOD claim follows from these checks. DCMTK's optional-LUT refusal remains peer-limited, planar 0 acceptance remains a compatibility tolerance, and keyboard/Space behavior is supplementary platform scope. Original remote M6 checks apply only to their recorded commit; local evidence does not establish current-head CI. M7 remains open and the user retains merge authority.
