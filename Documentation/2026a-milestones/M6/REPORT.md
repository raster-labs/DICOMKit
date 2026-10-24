# M6 checkpoint — Print SCU and SCP in CLI Workshop

**M6 remains in progress.** Both print tools now have shared CLI/Workshop implementations and automated evidence. Native packaged Workshop verification is **blocked by the locked Mac**. No M6 GUI action or completed enhancement is claimed. The two items are WS-COV-07 and WS-COV-08; their eight criteria currently comprise **4 passed implementation/route criteria, 2 partially verified comparisons and 2 blocked native-app criteria**. See [acceptance.json](acceptance.json).

This checkpoint uses M5 baseline `c91c79d9655929eef97ccffd601a9ef4297241d6` plus the recorded M6 overlay. [Source hashes](source-hashes.json), [source provenance](evidence/source-provenance.json), the reproducible [overlay archive](evidence/source-overlay.zip), and [verification.json](verification.json) distinguish source, builds and executed evidence. M7 changes and final-project qualification are outside this record.

## Implemented scope

| Tool | Existing commands routed through shared parser and services |
|---|---|
| `dicom-print` | `status`, `send`, `job`, `list-printers`, `add-printer`, `remove-printer` |
| `dicom-printscp` | `serve`, `simulate`, `status`, `queues` |

The new `DICOMPrintCommandSupport` target owns command mapping and ArgumentParser validation. Thin executable wrappers and Workshop adapters use that same implementation. Existing Print Management and image-composition services remain the execution paths. The frozen contract has 55 SCU and 72 SCP parameter declarations; the Workshop catalogs have 41 and 73 fields respectively, including their operation selectors. Shared SCU controls represent equivalent declarations across commands; SCP controls retain command-specific identities and inherited groups. These counts describe coverage mappings, not exhaustive testing of all option combinations. [Static CLI audit](evidence/print-cli-audit.log) and [Workshop audit](evidence/print-studio-parity-audit.log) retain the extraction evidence.

The forms preserve literal repeatable values as separate rows, inherited versus explicit false SCP settings, meaningful defaults and hidden-command isolation. Import validates the original and rebuilt argv using the real shared parser. Explicit empty scalar imports and duplicate scalar options are refused with an explanation when the form cannot represent them losslessly. Shell evaluation is not used for execution. The shared context supplies output, diagnostics, native open callbacks, listener state and cancellation; app execution does not install process signal handlers.

Printer registry operations use the CLI record schema and `printers.json` semantics. The effective location is displayed. The existing Print Center store remains separate; a sandbox home may differ from the terminal's home. SCP settings resolve the selected/default `printscp.json`, then explicit options. A Debug-only isolated settings seam and injected context paths avoid altering the user's actual printer configuration; no new CLI configuration flag was introduced. `--paper-queue` still requires explicit `--allow-paper`.

`serve` reports the bound listener, drains on cancellation and permits restart. The view requests Stop when it disappears or the app terminates; actual packaged window/application behavior still requires native verification. `status` does not listen; `queues` enumerates queues. `simulate --save-config` now writes resolved settings and exits before reading images or producing films, consistently with the shared option contract. Output-sink failures are reported without claiming a failed file was saved, while preserving the existing nonessential-sink/screen behavior.

## Executed automated evidence

| Layer | Passed | Skipped | Evidence |
|---|---:|---:|---|
| Print SCU command tests | 19 | 0 | [log](evidence/qualified-v2/dicom-printTests.log) |
| Print SCP command tests | 20 | 0 | [log](evidence/qualified-v2/dicom-printscpTests.log) |
| Focused network Print/DIMSE-N tests | 409 | 0 | [log](evidence/qualified-v2/DICOMNetworkTests.log) |
| PrintKit tests | 462: 378 XCTest + 84 Swift Testing | 1 | [log](evidence/qualified-v2/DICOMPrintKitTests.log) |
| Studio M6 tests | 22 | 1 | [log](evidence/qualified-v2/DICOMStudioTests.log) |
| Additional Studio catalog regressions | 220 Swift Testing | 0 | [log](evidence/catalog-regression-tests.log) |
| CLI/actual ViewModel comparisons | 25 actions/comparisons, all 10 commands | 0 | [baseline](evidence/workshop-campaign-v4/results.json), [image extension](evidence/workshop-image-extension/results.json) |
| Audit regressions | 38 | 0 | [log](evidence/qualified-v2/audit-regressions.log) |
| Independent print qualification | 24 cases | 1 peer limitation | [case index](interop-qualification.json) |

The focused test total is **932 passed and 2 skipped**. Audit and interoperability case counts are separate from test-method totals. The skipped legacy DCMTK reverse test requires an absent developer sample; the independent campaign uses synthetic fixtures instead. The regular Studio run skips its opt-in external action harness. That harness was separately activated for 18 baseline actions and 7 image sends, totaling 25 VM actions and 25 matching CLI comparisons. The baseline covers all 10 command routes, including registry/configuration errors and listener Stop. The additional 220 catalog tests are reported separately from the 932 focused total. Neither ordinary-suite skip is a pass.

The app build log ends in `BUILD SUCCEEDED`; this establishes compilation only. [Build log](evidence/app-build-final.log) and [native blocker record](evidence/native-gui-blocker.json) do not establish packaged GUI parity. The [fresh package and CLI identities](evidence/binary-identity.json) are recorded; all 1,012 hashes in the [source freeze](evidence/frozen-source-manifest.json) were verified unchanged. This is build/provenance evidence, not native execution.

The [baseline artifacts](evidence/workshop-campaign-v4/artifacts.json) establish CLI/VM TIFF simulation and PNG receive pixel equality; PDF checks establish complete containers only. The image extension produced 14 PNG films from 7 CLI and 7 VM sends: native and independent DCMTK-generated RLE/JPEG lossless inputs agree; three files agree with all three frames; selected frame 2 agrees with an extracted frame and differs from frame 1. Receiver image counts were `[1,1,1,3,3,1,1]` on each side. The receiver is the same library, and these are print-path comparisons, not independent receiver or broader codec qualification.

## Independent protocol results

DCMTK **3.7.0 (2025-12-15)** and **pynetdicom 2.0.2 / pydicom 2.4.4** operated as independent loopback peers. All input objects are synthetic. Actual executable hashes, versions, argv, fixture hashes, command logs, both raw DUL streams and independently decoded DIMSE messages are retained under [the full campaign](evidence/interop-qualified/results.json). One diagnostic-only oracle correction was rerun in [the targeted campaign](evidence/interop-qualified-lut-diagnostic/results.json); all five product/peer executable hashes match across those runs.

The 24 passing cases establish the specifically exercised paths:

- DICOMKit SCU to DCMTK: Printer N-GET; exact raw grayscale 8-bit and 12-in-16 pixel values; Explicit and Implicit VR LE; IDENTITY and LIN OD LUT creation and references.
- DCMTK SCU to DICOMKit: grayscale 8/12-bit, both transfer syntaxes, both LUT shapes, separately negotiated annotation and exact text, and readable composed PNG output.
- DICOMKit SCU to pynetdicom: planar RGB values, ordered repeated annotations, injected N-SET refusal and cleanup, Printer FAILURE/WARNING, preserved B604 N-ACTION warning, interleaved Print Job Done acknowledgment, job query and rejected optional LUT context without printing.
- pynetdicom SCU to DICOMKit: valid color, explicit film/implicit Print Job contexts, Done event type 3 and correlated acknowledgment, deletion after terminal confirmation, retention/query across associations when no terminal event is acknowledged, omitted optional context, and invalid planarity value 2 refusal.

DC-F07 is **unqualified with this peer**: DCMTK accepted the Presentation LUT context despite its disabled configuration. The final probe stops before printing and retains that evidence. PY-F08 independently establishes the actual refused-context behavior; the DCMTK limitation is not relabeled a pass. DCMTK's receiver does not qualify color or Annotation Box, so those positive paths use the separate pynetdicom peer.

## Repairs exposed by qualification

The bounded M6 repairs include listener-start timeout/cancellation completion, Print Job event context/encoding/correlation and terminal-instance lifetime, and file-backed CLI-test output with explicit deadlines and numeric fixture UIDs. Independent review also corrected Workshop import persistence, console replacement and runtime exit-code mapping. The focused suites cover those fixes.

An independent N-ACTION B604 response exposed a real warning-loss defect: the service accepted the film but replaced the warning with success. The shared service now retains per-film warnings and the first warning status; later successful films do not erase them. Text and JSON include the warning and its standard meaning while successful submission and exit zero remain intact. The final independent [B604 result](evidence/interop-qualified/PY-F06/client.stdout) and new network/output tests verify this behavior.

Initial oracle failures are retained separately in [repair provenance](repair-provenance.json). They were distinguished from product defects: response SOP Class UID is optional; PS3.4 Action Reply explicitly uses `(2100,0500)` despite the similarly named pydicom keyword mapping to `(2120,0070)`; LUT lifetime may end at association release; failure cleanup may abort; and confirmed terminal Print Job events delete their instances. An unsupported-LUT diagnostic may identify its exact SOP Class UID without spelling the acronym. None of these changes suppresses a product failure.

## Remaining gates and limits

Packaged Workshop controls, visible values, native file access, preview/copy/import, Run/Stop, actual listener lifecycle, profile persistence after relaunch and CLI/app cross-direction jobs remain pending native verification. The locked desktop blocks these actions; it does not waive them. The completed external ViewModel campaigns are separate automated evidence and do not satisfy the visible native form gate.

Existing SCP compatibility tolerance accepts color Planar Configuration 0 with a diagnostic; it does not prove strict PS3.3 C.13-5 conformance. The negative independent case uses value 2 and outbound color requires value 1. The finite suite does not exhaust every retry, malformed request, codec, layout or parameter combination. No physical printer/film, CUPS dispatch to a real queue, calibration, density measurement, diagnostic image quality, complete IOD or clinical-deployment claim is made.

The standards basis is frozen DICOM 2026a: PS3.4 Annex H; PS3.7 normalized DIMSE; PS3.3 C.13/C.11.4; PS3.5/PS3.8 encoding and transport. [Standard provenance](evidence/standard-provenance.json) identifies the exact source hashes. All seven remote CI workflows passed for M6 commit `3ee9af8a945b76aee72f0062ffb09139bb04d8a9`; see [remote verification](remote-verification.json). M6 remains in progress because native GUI acceptance is blocked. M7 completion, merge and release are not asserted.

## Final M7 descendant recheck

The final repaired M7 source re-runs all M6 focused gates: 933 passes and one ordinary opt-in skip (the legacy DCMTK synthetic fixture now runs successfully). Independent print again records 24 passes and one peer limitation; 25 CLI/VM comparisons also pass with final binary identities. See [M7 evidence](../M7/verification.json). These later results do not rewrite the historical M6 checkpoint or close its native GUI criteria.
