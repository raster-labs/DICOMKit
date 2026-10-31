# Native print run card — 26 October 2026

**Prepared, not executed.** Use the final signed app and current CLI hashes. All command strings below are literal Import inputs; only the peer port/AE and actual Print Job UID are runtime substitutions. Import clears grants: Browse input/config/output again afterward. Suggested ports 21113/21114 must be available. Keep the app on Print for group A, then switch once to Print SCP for group B.

## Evidence that can be reused

| Evidence | Valid reuse | Native work still required |
|---|---|---|
| WS-COV-07/08 AC01 and AC02 | Recorded capability decision, source/catalog/parser coverage and real shared routes are already passed. Reuse unchanged-source M6/M7 regression and audit evidence; no VM campaign rerun is needed. | Reconfirm final binary identity; observe every command in the packaged Workshop. |
| 25 final CLI/VM comparisons and image references | Baseline argv/result schemas, compressed/native/frame pixel oracles and all-ten-route execution references. | AC03 requires visible form → preview/copied argv → actual request/output. A VM result cannot supply visible values, sandbox access, native file grants, Open or UI status. |
| 933 focused M6 passes; independent 24 print passes and one peer limitation | Deep parser/flag combinations, malformed DIMSE, byte/VR/status checks and unchanged shared-service behavior retain their prior coverage. No need to rerun every protocol negative or every option permutation. | The native checklist explicitly requires grayscale/color, frame/compressed selections, optional acceptance/refusal, status warning/failure/B604, job/event handling and cross-direction CLI/app. Capture these native actions; do not mark them executed from old evidence. |
| Earlier app milestones and final app build/signature | Prior context and identity/build evidence only. | AC04 and PLAN M6 packaged acceptance require actual final-app actions, registry relaunch persistence, Start/Stop/restart/collision/window/app cleanup, truthful failures and native file/Open behavior. |
| Independent peer implementation/version | Reuse the pinned peer and existing oracle functions. | PLAN M6 packaged acceptance requires actual final native SCU→independent SCP and independent SCU→native SCP. No full campaign rerun; execute bounded native exchanges in both roles. |
| Physical/CUPS/clinical limits | Preserve existing exclusions. | No physical paper, calibration or clinical pass is required or inferred. Queues and missing Allow Paper refusal are native gates; do not send real paper. |

References: `PLAN.md` M6 packaged acceptance and M6.1–M6.3; `native-final-checklist.json` ten PRINT entries; item criteria AC03/AC04 remain open until native results exist. Reuse is conditional on unchanged relevant source/build inputs and verified artifact identity, not merely the same branch name.

## Root-only controls and comparison convention

Root owns all peer/CLI launches. No helper below has been run by this preparation. Start the isolated CLI receiver and retain its JSON stream. Independent peers use fresh output directories and emit `endpoint.json`; substitute that URL and called AE PYM6 only for their cases. Small independent SCP: single image box, peer-* 16×16 input, `--layout 1x1 --film-size 8x10 --raw`, no `--verify`.

```sh
/Volumes/DICOMKit-M1-build/spm/out/Products/Debug/dicom-printscp serve --config /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/config/absent.json --port 21113 --ae-title M7CLI --output png --output-dir /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/cli-received --name-pattern 'native-{index}' --dpi 36 --max-pixels 1024 --duration 1800 --format json --verbose
```

CLI replay convention: replace the first token `dicom-print`/`dicom-printscp` with `/Volumes/DICOMKit-M1-build/spm/out/Products/Debug/dicom-print` or `.../dicom-printscp`; retain every other argument. For write-output parity change only the native output folder to its fresh `cli-*` counterpart. Replay registry **mutations** with `DICOMKIT_PRINT_TEST_SETTINGS_DIRECTORY=/Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/cli-settings`; do not duplicate them against the live app registry. Read the live app registry with:

```sh
env DICOMKIT_PRINT_TEST_SETTINGS_DIRECTORY=/Users/raster/Library/Containers/com.rasterlab.DICOMStudio/Data/Library/Caches/DICOMKitM7PrintQualification /Volumes/DICOMKit-M1-build/spm/out/Products/Debug/dicom-print list-printers --format json --verbose
```

Compare normalized JSON/DICOM fields, exit status and warnings; preserve literal spaces/order and numeric values. Ignore only demonstrated dynamic UID/time/duration/output-root differences. Saved output comparisons use decoded RGBA/dimensions; PDF comparison establishes complete container only. Record input hashes unchanged.

## Group A — Print, six commands

| Order | Native action / import below | Expected control or observation |
|---|---|---|
| A01 | add-printer; list-printers | Exact literal Unicode/quote/semicolon name, host/port, color and default persisted; visible registry location is the signed DEBUG container path. |
| A02 | Repeat add-printer | Refused duplicate; registry unchanged. CLI mutation control on separate registry produces equivalent refusal. |
| A03 | Quit/relaunch; list-printers JSON and text | Same record after real relaunch. Then remove-printer and repeat remove. First succeeds, second reports not found; only synthetic record removed. |
| A04 | status JSON then text | Actual CLI peer NORMAL; same keyword/legacy fields. |
| A05 | send literal-layout-annotations | Browse literal filename. Observe `ROW\1,3`, negative center, two separate annotations with exact spaces/order; Copy → Import → Browse → run. Same request/output as CLI. |
| A06 | Edit controls into invalid combinations, without sending | Layout+Template, Raw+Window, Frame2+AllFrames, lone window bound, missing annotation format: native refusal/disabled Run. Restore valid values. Existing unit coverage supplies remaining flag permutations. |
| A07 | send raw12 and rgb8 | Correct gray12 and color submissions, visible mode/raw/template values and success. |
| A08 | send gray8, rle, jpeg; three-files/all-frames; frame2/frame2-control | Counts `[1,1,1,3,3,1,1]`; raw native/RLE/JPEG films equal, three files=all frames, selected frame2=extracted frame2 and differs from frame1. Use live receiver output and prior image reference. |
| A09 | send dry-run-no-peer | Plan completes with no print submission; check existing CLI dry-run behavior rather than assume optional flags contact a peer. |
| A10 | job with UID from a current send; then valid but nonexistent UID | DONE/NORMAL and dates/keywords agree with CLI; missing job refuses. Do not reuse historical UID. |
| A11 | Native sends to independent normal, no-LUT, warning/failure, set-failure, B604/event peers | Capture actual datasets/status/cleanup. B604 remains successful with warning; N-SET/preflight refusal sends no action; requested unavailable LUT refuses. Same literal input rules. |

**dicom-print add-printer**

```text
dicom-print add-printer --name 'Native; O'"'"'Neil 雪' --host 127.0.0.1 --port 21113 --called-ae M7CLI --calling-ae M7NATIVE --color color --default
```

**dicom-print list-printers**

```text
dicom-print list-printers --format json --verbose
```

**dicom-print remove-printer**

```text
dicom-print remove-printer --name 'Native; O'"'"'Neil 雪'
```

**dicom-print status**

```text
dicom-print status pacs://127.0.0.1:21113 --aet M7NATIVE --called-aet M7CLI --timeout 5 --format json
```

**send: literal-layout-annotations**

```text
dicom-print send pacs://127.0.0.1:21113 '/Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/print-fixtures/literal O'"'"'Neil; snow 雪.dcm' --called-aet M7CLI --aet M7NATIVE --timeout 5 --format json --layout 'ROW\1,3' --copies 2 --priority MED --medium 'CLEAR FILM' --film-destination bin-2 --window-center=-600 --window-width 1200 --presentation-lut IDENTITY --annotate ' first; literal note ' --annotate 'O'"'"'Neil second' --annotation-format M7FMT --check-status --verify
```

**send: raw12**

```text
dicom-print send pacs://127.0.0.1:21113 /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/print-fixtures/gray12.dcm --called-aet M7CLI --aet M7NATIVE --timeout 5 --format json --raw
```

**send: rgb8**

```text
dicom-print send pacs://127.0.0.1:21113 /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/print-fixtures/rgb8.dcm --called-aet M7CLI --aet M7NATIVE --timeout 5 --format json --color color --template single
```

**send: gray8**

```text
dicom-print send pacs://127.0.0.1:21113 /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/print-fixtures/gray8.dcm --called-aet M7CLI --aet M7NATIVE --timeout 5 --format json --raw
```

**send: rle**

```text
dicom-print send pacs://127.0.0.1:21113 /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/print-fixtures/rle.dcm --called-aet M7CLI --aet M7NATIVE --timeout 5 --format json --raw
```

**send: jpeg**

```text
dicom-print send pacs://127.0.0.1:21113 /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/print-fixtures/jpeg.dcm --called-aet M7CLI --aet M7NATIVE --timeout 5 --format json --raw
```

**send: three-files**

```text
dicom-print send pacs://127.0.0.1:21113 /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/print-fixtures/frame1.dcm /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/print-fixtures/frame2.dcm /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/print-fixtures/frame3.dcm --aet M7NATIVE --called-aet M7CLI --raw --layout 'STANDARD\2,2' --timeout 5 --format json
```

**send: all-frames**

```text
dicom-print send pacs://127.0.0.1:21113 /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/print-fixtures/multi.dcm --called-aet M7CLI --aet M7NATIVE --timeout 5 --format json --raw --all-frames --layout 'STANDARD\2,2'
```

**send: frame2**

```text
dicom-print send pacs://127.0.0.1:21113 /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/print-fixtures/multi.dcm --called-aet M7CLI --aet M7NATIVE --timeout 5 --format json --raw --frame 2
```

**send: frame2-control**

```text
dicom-print send pacs://127.0.0.1:21113 /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/print-fixtures/frame2.dcm --called-aet M7CLI --aet M7NATIVE --timeout 5 --format json --raw
```

**send: dry-run-no-peer**

```text
dicom-print send pacs://127.0.0.1:1 /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/print-fixtures/gray8.dcm --aet M7NATIVE --check-status --verify --dry-run -vr --retries 2
```

**job — replace the explicit UID placeholder**

```text
dicom-print job pacs://127.0.0.1:21113 --aet M7NATIVE --called-aet M7CLI --timeout 5 --job-id REPLACE_WITH_ACTUAL_PRINT_JOB_UID --format json
```

Independent native-SCU launch commands (normal and B604 shown; use fresh output for every mode):

```sh
/Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m6/peer-venv/bin/python /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/native_print_peer.py serve --output-dir /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/peer-normal
/Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m6/peer-venv/bin/python /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/native_print_peer.py serve --mode action-warning --output-dir /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/peer-b604
```

For `--mode warning`, use native send with `--check-status`; `failure` must refuse. `set-failure` must expose the supplied error. `no-lut` must reject requested `--presentation-lut IDENTITY`. `event` enables Print Job events. `normal` supports gray/color/LUT/annotations; use one peer-* image per film. Capture endpoint/case output and graceful peer close; detailed commands are in the setup inventory.

## Group B — Print SCP, four commands

| Order | Native action / import below | Expected control or observation |
|---|---|---|
| B01 | status baseline; enabled overrides; Save Config; reload | Inherit uses baseline false color/annotation/draw switches and true LUT; enable/disable/omit preview matches resolved JSON. Save exits with no listener or film, reload preserves Saved Native. Browse config. |
| B02 | queues; status with paper queue and no Allow Paper | Enumerate only; native refusal for paper gate, no spool or real queue. |
| B03 | simulate multi-output | Browse input/output. Final image format TIFF plus PDF, no PNG; one film. Compare live CLI TIFF pixels/dimensions, complete PDF. Inspect repeatable Output rows. |
| B04 | simulate save-before-gather | Missing input is never opened, settings file saved, no film. |
| B05 | simulate failed sink; Open after success | Existing `native-001.png` directory makes image emit fail. Console retains film/failure; no Wrote/open claim. Separate sink-is-file startup path must error. Successful Open actually opens saved synthetic file. |
| B06 | serve receive-and-stop; external CLI gray and color send | Actual bound port shown; UI responsive and controls locked during run; files/counters correspond to sends. Stop→130/cancelled→port released. Restart works. |
| B07 | duration-only and one-film-limit | Duration exits0 after2s with no film; max-films1 exits0 only after response/release and one saved film; CLI sender succeeds. |
| B08 | Occupied21114, then view leave/app termination | Root holds port with CLI peer. GUI bind error does not kill incumbent; status still succeeds. After native successful restart, leaving Workshop releases port; repeat app termination and verify release/rebind. |
| B09 | independent-color-event | Native AE DCMKIT_M6, color+push events. Independent color peer sends; terminal Done3 event on PrintJob context/implicitVR gets ACK0; subsequent N-GET0112, one PNG. Reuse prior malformed-planar backend evidence; exercise native AE rejection as described below. |
| B10 | independent-gray | Native gray/LUT/annotations enabled; DCMTK sends shape+annotation, one nonuniform film; inspect association/DIMSE captures and native result. |

**status: inherited baseline**

```text
dicom-printscp status --config /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/config/baseline-scp.json --format json
```

**status: explicit enabled overrides**

```text
dicom-printscp status --config /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/config/baseline-scp.json --accept-color --annotation-box --annotations --trim-marks --format json
```

**status: save resolved settings**

```text
dicom-printscp status --config /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/config/saved-scp.json --save-config --printer-name 'Saved Native' --output none --no-accept-color --no-annotations --format json
```

**status: reload saved settings**

```text
dicom-printscp status --config /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/config/saved-scp.json --format json --verbose
```

**queues**

```text
dicom-printscp queues --format json
```

**paper gate refusal**

```text
dicom-printscp status --config /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/config/baseline-scp.json --paper-queue SYNTHETIC-NONEXISTENT --format json
```

**simulate: TIFF plus PDF**

```text
dicom-printscp simulate /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/print-fixtures/gray8.dcm --config /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/config/absent.json --layout 'ROW\1,3' --window-center=-600 --window-width 1200 --copies 2 --trim --border-density 150 --empty-density WHITE --annotate ' first; literal note ' --annotate 'O'"'"'Neil second' --annotation-format M7FMT --presentation-lut IDENTITY --output png --output tiff --output pdf --output-dir /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/gui-simulated --name-pattern 'native-{index}' --dpi 36 --max-pixels 1024 --format json
```

**simulate: save before gather**

```text
dicom-printscp simulate /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/deliberately-missing.dcm --config /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/config/simulation-save.json --save-config --output none --dpi 36 --format json
```

**simulate: nonessential sink failure**

```text
dicom-printscp simulate /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/print-fixtures/gray8.dcm --config /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/config/absent.json --output png --output-dir /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/sink-failure --name-pattern 'native-{index}' --dpi 36 --max-pixels 1024 --format json
```

**simulate: native Open after write**

```text
dicom-printscp simulate /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/print-fixtures/gray8.dcm --config /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/config/absent.json --output png --output-dir /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/open-output --name-pattern 'opened-{index}' --dpi 36 --max-pixels 1024 --open
```

**serve: receive-and-stop**

```text
dicom-printscp serve --config /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/config/absent.json --port 21114 --ae-title DCMKIT_M6 --output png --output pdf --output-dir /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/gui-received --name-pattern 'native-{index}' --dpi 36 --max-pixels 1024 --duration 300 --format json --verbose
```

**serve: duration-only**

```text
dicom-printscp serve --config /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/config/absent.json --port 21114 --ae-title DCMKIT_M6 --output none --duration 2 --format json
```

**serve: one-film-limit**

```text
dicom-printscp serve --config /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/config/absent.json --port 21114 --ae-title DCMKIT_M6 --output png --output-dir /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/gui-received --name-pattern 'limited-{index}' --dpi 36 --max-pixels 1024 --max-films 1 --duration 60 --format json
```

**serve: independent-color-event**

```text
dicom-printscp serve --config /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/config/absent.json --port 21114 --ae-title DCMKIT_M6 --accept-color --push-job-events --output png --output-dir /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/gui-independent-color --name-pattern 'native-{index}' --dpi 36 --max-pixels 1024 --duration 300 --format json --verbose
```

**serve: independent-gray**

```text
dicom-printscp serve --config /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/config/absent.json --port 21114 --ae-title DCMKIT_M6 --no-accept-color --presentation-lut --annotation-box --output png --output-dir /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/gui-independent-gray --name-pattern 'native-{index}' --dpi 36 --max-pixels 1024 --duration 300 --format json --verbose
```

External sender while native SCP is running:

```sh
/Volumes/DICOMKit-M1-build/spm/out/Products/Debug/dicom-print send pacs://127.0.0.1:21114 /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/print-fixtures/gray8.dcm --aet M7CLI --called-aet DCMKIT_M6 --raw --timeout 5 --format json
```

For color send, substitute `rgb8.dcm` and add `--color color`; keep final app AE/port. Native receiver must allow color. For the one-film test use a fresh output prefix/folder or compare file/counter delta.

Independent send controls target the already running native listener and require an initially empty output folder. Helpers do not launch/stop that app listener:

```sh
/Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m6/peer-venv/bin/python /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/native_print_peer.py send-color --port 21114 --films /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/gui-independent-color --output-dir /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/independent-color-send
/Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m6/peer-venv/bin/python /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/native_print_peer.py send-gray --port 21114 --films /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/gui-independent-gray --shape identity --annotation --output-dir /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/independent-gray-send
```

Output oracles after equivalent native and CLI simulations:

```sh
/Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m6/peer-venv/bin/python /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/inspect_print_files.py --expect-equal /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/gui-simulated/native-001.tiff /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/cli-simulated/native-001.tiff
/Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m6/peer-venv/bin/python /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/inspect_print_files.py /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/gui-simulated/native-001.pdf
```

For native AE rejection: set Allow Ae to a different synthetic value, attempt the CLI sender, require rejection and zero film delta, then restore. Do not leave a permissive old hidden control in the next command. For sink-is-file: replace only the failed-sink command output directory with the existing `sink-is-file` path; this is a startup failure, not the recoverable emit failure.

## Recording / acceptance

Per action retain the native screenshot/AX showing effective values and outcome, copied command, CLI argv/result or independent capture, output/config hash or counter delta, and applicable cleanup observation. Do not combine UI observation and unrelated old request data as if one run. Record skips/failures explicitly. All ten commands must execute in the actual app; grouped variants may share a native capture only when the state and resulting action remain distinguishable. Old automation can support deeper unchanged implementation claims but cannot close missing native checklist actions.
