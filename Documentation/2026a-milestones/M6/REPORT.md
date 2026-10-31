# M6 — Print SCU and SCP in CLI Workshop

**Completed 26 October 2026: WS-COV-07 and WS-COV-08, eight criteria passed.** The finite macOS arm64 software qualification covers the existing six `dicom-print` and four `dicom-printscp` commands in the CLI and actual packaged CLI Workshop. M7 remains in progress. Physical printing, calibration, clinical fitness and complete DICOM conformance are not asserted. See [acceptance](acceptance.json), [native closure](native-closure.json) and [verification](verification.json).

## Implemented scope

| Tool | Existing commands routed through shared parser and services |
|---|---|
| `dicom-print` | `status`, `send`, `job`, `list-printers`, `add-printer`, `remove-printer` |
| `dicom-printscp` | `serve`, `simulate`, `status`, `queues` |

`DICOMPrintCommandSupport` owns command mapping and ArgumentParser validation. Thin CLI wrappers and Workshop adapters use the same execution paths. The frozen CLI contract contains 55 SCU and 72 SCP parameter declarations; Workshop has 41 and 73 fields including operation selectors. Shared SCU controls represent repeated declarations across commands; SCP controls preserve command-specific identities. These are mapping counts, not all possible option combinations. [CLI audit](evidence/print-cli-audit.log) and [Workshop audit](evidence/print-studio-parity-audit.log) retain the extraction evidence.

Repeatable values use separate rows; SCP settings distinguish inherited, enabled and disabled values. Import validates original and rebuilt argv using the actual parser. Unsupported duplicate or empty scalar representations refuse with an explanation. Execution does not evaluate a shell. The shared context supplies output, diagnostics, native Open, listener state and cancellation; the app installs no process signal handlers.

Printer registry operations retain CLI schema and `printers.json` semantics; the effective location is visible. Print Center storage remains separate and the sandbox home may differ from the terminal home. The Debug-only isolated settings seam avoids the user's registry without adding a new CLI flag. SCP config resolves first, followed by explicit overrides. `--paper-queue` requires `--allow-paper`; real paper dispatch was not performed. `simulate --save-config` writes resolved settings before gathering input. Sink failures emit warnings and never claim a failed file was saved, while preserving the existing nonessential sink contract.

## Executed evidence and provenance

| Evidence layer | Result | Record |
|---|---|---|
| Original M6 implementation suites |932 passes,2 explicit skips;38 audit regressions | [historical verification](evidence/historical-pre-native-closure/verification.json) |
| Later M7 descendant M6 recheck |933 passes,1 ordinary opt-in skip | [M7 verification](../M7/verification.json) |
| Additional catalog regression |220 Swift Testing passes, separate from 932 | [log](evidence/catalog-regression-tests.log) |
| Independent print peers |24 passed cases,1 DCMTK peer limitation | [index](interop-qualification.json) |
| Actual test-host Workshop/CLI comparisons |25 actions/comparisons, all 10 commands | [baseline](evidence/workshop-campaign-v4/results.json), [image extension](evidence/workshop-image-extension/results.json) |
| Native image/CLI parity |100 passed assertions | [record](evidence/native-2026-10-26/print-native-cli-parity.json) |
| Native SCP/CLI controls |64 passed assertions,9 CLI controls | [record](evidence/native-2026-10-26/scp-native-verification-post-repair.json) |
| Registry and granted tri-state controls |17 passed assertions | [record](evidence/native-2026-10-26/repaired-print-controls-review.json) |
| Final six CLI/native controls |33 passed assertions | [record](evidence/native-2026-10-26/final-print-controls-verification.json) |
| Native independent SCU peer review |128 assertions;8 outcomes,7 peers,10 associations,76 DIMSE messages | [record](evidence/native-2026-10-26/native-scu-peer-independent-review.json) |
| PDF raster and embedded image comparisons |33 passed assertions | [record](evidence/native-2026-10-26/pdf-raster-verification.json) |
| Final menu/native closure |13 assertions; no required M6 software gap | [review](evidence/native-2026-10-26/m6-native-closure-review.json) |

These layers overlap and must not be added. A skipped ordinary opt-in harness is not a pass; separate activation is identified. The original 932 checkpoint and later 933 result use different qualification epochs. Neither is whole-project coverage. Earlier raw records retain their then-current partial/pending wording; [native-closure.json](native-closure.json) reconciles the subsequent receipts rather than rewriting history.

After the generic path and first print repairs, full Studio reported 5,391 Swift Testing tests in 493 suites, including one optional SampleStudies skip, with overall success. XCTest reported 92 cases, including 4 skips and 0 failures (88 executed passes). The later menu-only correction passed 5 focused tests using the actual form hierarchy at 240/380/620 widths. [Full repair log](evidence/native-2026-10-26/print-repair-verification/DICOMStudioTests-path-repair-full-v2.log) and [later focused log](evidence/native-2026-10-26/print-repair-verification/DICOMStudioTests-real-form-layout-v2.log) preserve that timing; the earlier full suite is not represented as a run of the later menu app.

The [final identity](evidence/native-2026-10-26/final-qualified-native-identity.json) records the signed, normally sandbox-entitled menu-repaired package, 2060 source hashes, binaries and explicit source-equivalence boundaries. Shared print services are unchanged since the first repair; the generic grant changes occur after the print early return. Current menu presentation is verified by actual native actions. [Artifact hashes](evidence/native-2026-10-26/final-qualified-native-artifact-hashes.json) identify the app executable `f69f9a34…`, debug library `968b7486…`, print CLI `ad3ceb05…` and SCP CLI `c34f4967…`; full hashes are authoritative. The original M6 overlay/source freeze remains historical in [source-hashes.json](source-hashes.json).

## Native plan gates closed

All ten commands were exercised in CLI Workshop. Visible forms, copied literal argv, request/result payloads and matching CLI controls are retained. SCU negatives include frame/all-frames, layout/template, lone window, raw/window and annotation format. Ordered file and annotation rows map to the received film; literal values are preserved. Gray8, raw12, RGB8, native/RLE/JPEG, selected frame2, all frames and three-file inputs have decoded output comparisons. Status/job text and JSON match; dry-run against port 1 creates no print job.

Registry add/default/list/duplicate/remove/missing cases, empty `[]` JSON, text guidance and relaunch persistence passed. The OS denied direct terminal access to the app-private registry; no access bypass was used. Native output was compared to an independent isolated CLI registry using the same schema.

SCP status inheritance, enabled/disabled overrides, config save/reload, queues and save-before-gather passed. The final Browse-granted verbose trio demonstrates full settings; an earlier inaccessible-config fallback is preserved and is not counted as a successful config read. Native simulate/serve output, independent gray/color receivers, Stop/restart, duration/max-film limits, occupied-port refusal, leave-Workshop and app-quit rebind were checked. Nonallowed AE refuses; allowed AE returns NORMAL. Running controls are disabled; Stop releases the listener. Failed sinks, chmod 0500 output, regular-file-as-directory refusal, fresh child creation, filename tokens and native Preview Open have matching controls.

The final 240px [SCU form](evidence/native-2026-10-26/ui-menu-final/send-narrow.png) and [SCP form](evidence/native-2026-10-26/ui-menu-final/scp-status-final.png) are readable. Raw off/on changes only `--raw`; final native dry-run succeeds without submission. Final SCP menu selection runs `status` successfully and [all 11 JSON fields match the CLI](evidence/native-2026-10-26/cli-final-controls/menu-final-scp-status.json).

PDF software parity now goes beyond complete containers: all four retained PDFs have one 14×17-inch page and exact embedded 504×612 film pixels matching companion TIFF/PNG. Native/CLI simulation PDF pages rasterize identically at 36 DPI. Their explicit interpolation and ICC profile can make rendered pixels differ from unrendered source images; the [initial cross-format oracle failure](evidence/native-2026-10-26/pdf-raster-verification.initial-cross-format-oracle.json) is retained. The corrected comparison uses exact CLI/native rendered pages and separately exact stored-image equality; no tolerance masks a parity difference.

## Independent protocol scope and retained limits

DCMTK 3.7.0 and pynetdicom 2.0.2/pydicom 2.4.4 operated as independent loopback peers on synthetic data. Recorded cases cover grayscale 8/12, explicit/implicit LE, IDENTITY/LIN OD LUT and references, annotation, planar RGB, N-SET refusal/cleanup, Printer FAILURE/WARNING, B604 N-ACTION warning, Print Job query and terminal event/correlated ACK, optional context omission/refusal and invalid planarity 2. Native CLI→app, app→CLI and independent directions are separately evidenced. [Protocol index](interop-qualification.json) and [standard provenance](evidence/standard-provenance.json) bound the PS3.4 Annex H, PS3.7, PS3.3 C.13/C.11.4 and PS3.5/8 claims.

DC-F07 remains peer-limited: DCMTK accepted LUT despite its disabled profile; PY-F08 supplies a separate genuine refusal. Color planar 0 remains a disclosed SCP compatibility tolerance; it is not strict conformance evidence. Outbound color uses 1. The suite does not exhaust every codec, malformed request, retry or parameter combination.

Qualification exposed and repaired warning loss, listener/event cleanup, CLI test deadlines/numeric UIDs, import/output state, empty JSON and native checkbox/form sizing. The final layout defect came from the long segmented operation selector expanding the actual form; a print-only menu and actual-hierarchy regression replaced that constraint. Historical narrow-pane failures and failed isolated/initial hierarchy tests remain in the evidence. [Original repair provenance](repair-provenance.json) and [native layout record](evidence/native-2026-10-26/print-real-form-layout-repair.json) distinguish product defects from oracle errors.

Keyboard/Space behavior is a supplementary platform-interaction limit, not an additional requirement retroactively imposed on the accepted M6 plan. Physical printer/film, real CUPS completion, calibration/density/diagnostic fidelity, clinical deployment, all IODs and other operating systems remain unqualified. Seven remote checks passed for original M6 commit `3ee9af8a`; [that record](remote-verification.json) is not CI for the later repair overlay. M7 completion, main merge and release are not asserted.
