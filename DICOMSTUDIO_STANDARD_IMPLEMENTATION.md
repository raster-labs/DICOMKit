# DICOMStudio — DICOM Standard Implementation Report

Generated 2026-10-05. Covers all 334 Swift files in `Sources/DICOMStudio/` (333) and `Sources/DICOMStudioApp/` (1):
the macOS SwiftUI application over DICOMKit — the CLI Workshop (forms, executors and command previews for 29 of the
42 `dicom-*` tools), the image viewer and its PS3.4 N.2 display pipeline, presentation states, DIMSE and DICOMweb
panels, the print composer and Print SCP, DICOMDIR and media exchange, structured reports, anonymization and the
derived-object helpers. (The earlier status row said 335 files; `cb5090f2` moved `@main` to the DICOMStudioApp target
and deleted the old `App/DICOMStudioApp.swift`, so 334 is the closing count.)

**Status: in progress** (started 2026-10-05). Method:
[DICOMCORE_STANDARD_IMPLEMENTATION.md → Verification method](DICOMCORE_STANDARD_IMPLEMENTATION.md#verification-method-reuse-for-every-module),
used unchanged. Package target: **DICOM 2026a** (`dicomStandardEdition = "2026a"`,
[DICOMKit.swift](Sources/DICOMKit/DICOMKit.swift)). Diff script: [Scripts/diff_studio.py](Scripts/diff_studio.py)
(plus one `Scripts/diff_studio_g<N>.py` per group); markers checked with
`python3 Scripts/diff_studio.py --inventory | python3 Scripts/check_nema_markers.py --inventory - Sources/DICOMStudio Sources/DICOMStudioApp`.

**Scope note.** Most of the module is SwiftUI views, caches and view-model plumbing that carry no standard-derived
value. Only code that touches the standard is reviewed: tags, UIDs, SOP Classes, transfer syntaxes, VRs, coded terms
(CIDs), IOD and module rules, status codes, the PS3.4 N.2 display pipeline, PS3.15 profiles, DICOMDIR and media
profiles, network and DICOMweb wire values, and every CLI Workshop form or option that mirrors a `dicom-*` tool. Pure
UI, layout, theme and view-model plumbing get no marker; they are recorded as "not standard-touching" in the file
inventory (section 6) so the 334 / 334 count closes. The inventory lives in `FILES` of `diff_studio.py`, which also
feeds the marker checker. Tiers: **ST** standard-touching (row-by-row review, marker), **CR** confirm-read (one to three
incidental hits; read once, recorded as NST or promoted), **NST** not standard-touching (inventoried only).
DICOMToolbox is out of scope. The Workshop's shell-only categories (dicom-server, gateway, jpip, cloud, ai, j2k,
report, measure, 3d, viewer, print, printscp) have no form in the UI and are out of scope by the owner's decision
(2026-10-05): the Workshop work covers the 29 tools the UI offers (33 Workshop tool ids; dicom-wado is split into
QIDO / WADO / STOW / UPS).

**Evidence rule.** Code is checked by script against the frozen 2026a NEMA DocBook, row by row. Doc comments, READMEs
and memory do not count. Workshop ↔ CLI parity is checked against the CLI's ArgumentParser surface
(`diff_cli.extract_options`) and the contract tables of `Scripts/cli_contracts.py`, so every Workshop option maps to
the same tool option, wire value and default as the CLI contract.

---

## Summary

| Group | ST | CR | NST | Files | Status |
|---|---|---|---|---|---|
| G1 CLI Workshop | 20 | 2 | 15 | 37 | ⏳ |
| G2 Viewer and rendering | 52 | 31 | 54 | 137 | ⏳ |
| G3 Network and web | 19 | 5 | 13 | 37 | ⏳ |
| G4 File, media and DICOMDIR | 31 | 8 | 3 | 42 | ✅ 2026-10-05 (markers `b0eca043`, checks `f02ee47a`, fixes `e6c2a11a`…`1793c091`; `diff_studio.py --group G4`: 22 ok, 0 FAIL; two files share hunks with the codec pass) |
| G5 Derived objects, SR and security | 36 | 0 | 6 | 42 | ⏳ |
| G6 Print | 11 | 11 | 17 | 39 | ⏳ |
| **All** | **169** | **57** | **108** | **334** | ⏳ |

Standard text used (fetched 2026-10-05 from `/2026a/`, subtitles confirmed): PS3.3, PS3.4, PS3.5, PS3.6, PS3.10,
PS3.11, PS3.15, PS3.16, PS3.18.

### Baseline, before any change (2026-10-05, after `61670c42`)

`diff_studio.py --group G1 --only parity` over the 33 Workshop tool ids:

| Result | Workshop tool | Counts |
|---|---|---|
| FAIL | dicom-anon | 13, wrong 10, missing 0, extra 0, pending 1 |
| FAIL | dicom-archive | 18, wrong 1, missing 0, extra 0 |
| ok | dicom-compress | 12, wrong 0, missing 0, extra 0 |
| ok | dicom-convert | 12, wrong 0, missing 0, extra 0 |
| ok | dicom-dcmdir | 13, wrong 0, missing 0, extra 0 |
| ok | dicom-diff | 8, wrong 0, missing 0, extra 0 |
| FAIL | dicom-dump | 9, wrong 1, missing 0, extra 0 |
| ok | dicom-echo | 9, wrong 0, missing 0, extra 0 |
| FAIL | dicom-export | 24, wrong 1, missing 0, extra 0 |
| FAIL | dicom-image | 14, wrong 1, missing 0, extra 0 |
| ok | dicom-info | 5, wrong 0, missing 0, extra 0 |
| ok | dicom-json | 10, wrong 0, missing 0, extra 0 |
| FAIL | dicom-merge | 13, wrong 1, missing 0, extra 0 |
| ok | dicom-mpps | 38, wrong 0, missing 0, extra 0 |
| FAIL | dicom-mwl | 16, wrong 2, missing 0, extra 0 |
| FAIL | dicom-pdf | 14, wrong 3, missing 0, extra 0 |
| ok | dicom-pixedit | 9, wrong 0, missing 0, extra 0 |
| FAIL | dicom-qido | 18, wrong 6, missing 0, extra 0 |
| ok | dicom-qr | 20, wrong 0, missing 0, extra 0 |
| FAIL | dicom-query | 18, wrong 2, missing 0, extra 0 |
| ok | dicom-retrieve | 16, wrong 0, missing 0, extra 0 |
| ok | dicom-script | 6, wrong 0, missing 0, extra 0 |
| FAIL | dicom-send | 11, wrong 1, missing 0, extra 0 |
| ok | dicom-split | 17, wrong 0, missing 0, extra 0 |
| ok | dicom-stow | 6, wrong 0, missing 0, extra 0 |
| FAIL | dicom-study | 12, wrong 2, missing 0, extra 0 |
| FAIL | dicom-tags | 8, wrong 1, missing 0, extra 0 |
| FAIL | dicom-uid | 15, wrong 1, missing 0, extra 0 |
| FAIL | dicom-ups | 32, wrong 6, missing 0, extra 0 |
| ok | dicom-validate | 8, wrong 0, missing 0, extra 0 |
| FAIL | dicom-video | 29, wrong 1, missing 0, extra 0 |
| FAIL | dicom-wado | 12, wrong 9, missing 0, extra 0 |
| ok | dicom-xml | 10, wrong 0, missing 0, extra 0 |

17 of 33 fail; the findings are listed per tool in section 5 and closed there. Generic literal checks over the 169 ST
files (`--only generic`): PS3.6 Table A-1 names abbreviated next to UID literals in `ImportValidation`,
`J2KTestBenchModels`, `FileOperationsHelpers`, `PerformanceToolsHelpers` (20 rows); two UID family prefixes in
`ViewerContentKind` (.88, .104) flagged as unregistered (they are prefixes, to be documented); PS3.16 coded concepts in
`SRBuilderHelpers` (5 meanings differ from Table D-1 / CID 7461 / CID 83 / CID 7181; one SRT code to convert to SCT per
Table O-1). Every other generic check is ok.

### Progress log

| Date | Item | Standard | What changed | Tests |
|---|---|---|---|---|
| 2026-10-05 | Inventory | — | 334 files scanned by script for standard signals and classified into six groups and three tiers (`diff_studio.py FILES`); `check_nema_markers.py --inventory` added so inventoried NST files need no marker | — |
| 2026-10-05 | Anon flag (urgent, from DICOMCLI "Rows handed to DICOMStudio" part 4) | PS3.15 2026a Annex E (E.1-1; E.3) | `AnonymizationProfile.cliFlag` → `legacy-basic` / `legacy-clinical-trial` / `legacy-research`; `AnonHelpers.buildCommand` always names `--profile`; Workshop form, presets and executor follow; `ps315` / `basic` refused in the Workshop until P-STUDIO-ANON-PS315 (`61670c42`) | `SecurityModelTests` +2, `CLIWorkshopHelpersTests` +2 (175 pass in the two suites) |
| 2026-10-05 | Baseline | — | `diff_studio.py`: Workshop parity 17 / 33 FAIL, 1 PEND; generic literal checks: 6 FAIL rows (above) | — |
| 2026-10-05 | DICOMDIRParser.knownRecordTypes | PS3.3 2026a Table F.4-1 (35 record types = F.3-3 Enumerated Values of (0004,1430)); F.5-1/F.5-2/F.5-3/F.3-3 record keys; PS3.10 8.2/8.6 File ID | 29/35 matched; 6 added (RT TREAT RECORD, WAVEFORM, PLAN, ANNOTATION, INVENTORY, WF PRESENTATION); HL7 STRUC DOC kept, documented as retired (F.5.33, PS3.3-2018b) (commit e6c2a11a) | DICOMDIRParserTests (+1 pin) |
| 2026-10-05 | VRDescriptions (VRBadge.swift) | PS3.5 2026a Table 6.2-1, 34 VRs, "VR Name" verbatim | 25 matched, 2 corrected (UI → "Unique Identifier (UID)", SQ → "Sequence of Items"), 7 added (AS, AT, OL, OV, SV, UV, UR); category covers all 34 (commit 395aa723) | VRDescriptionsTests (+1 pin of all 34, 2 expectations corrected) |
| 2026-10-05 | DICOMValueParser | PS3.5 Table 6.2-1 per-VR formats; 6.2.1.1/6.2.1.2 PN component groups; PS3.3 Tables C.12-2…C.12-5 (32 Specific Character Set Defined Terms) | PN "=" component groups now formatted per group (were run together as one name); charset keys 19 matched, 13 added (ISO_IR 203, GBK, ISO 2022 IR 13/58/101/109/110/126/127/138/144/148/166/203) (commit 3a975c0e) | DICOMValueParserTests (+3) |
| 2026-10-05 | PrivateTagIdentifier | PS3.5 2026a 7.8.1 ("Elements with Tags (0001,xxxx), (0003,xxxx), (0005,xxxx), (0007,xxxx) and (FFFF,xxxx) shall not be used"; creators (gggg,0010-00FF)) | isPrivateGroup now refuses the 5 reserved odd groups (was: any odd group); creator range already correct (commit be45ab83) | PrivateTagIdentifierTests (+1) |
| 2026-10-05 | TransferSyntaxDescriptions.describe (MetadataViewModel.swift) | PS3.6 2026a Table A-1 "UID Name" | own 13-row table (5 names not A-1: .4.70, .4.80, .4.90, .4.91, .2) replaced by DICOMCore `TransferSyntax.displayName` (A-1 verbatim, verified 2026-10-01) (commit fccbdef5) | TransferSyntaxDescriptionsTests (expectations → A-1 names, +1 pin over `TransferSyntax.allKnown`) |
| 2026-10-05 | TransferSyntaxHelpers.wellKnownSyntaxes (DataExchangeHelpers.swift) | PS3.6 Table A-1 (8 Transfer Syntax rows) | 6 of 8 `displayName` literals were abbreviations → now `TransferSyntax.<x>.displayName`; `shortName` keeps the abbreviation (commit fccbdef5) | DataExchangeHelpersTests (+1 pin) |
| 2026-10-05 | DataExchangeViewModel.secondaryCaptureModality | PS3.3 2026a C.7.3.1.1.1 Modality Defined Terms (97) | default "SC" is not a Defined Term → "OT" (`Modality.ot`, dicom-image's own default) (commit 1793c091) | DataExchangeViewModelTests (+1) |
| 2026-10-05 | markers on 23 C1/C2 files | per-file (see inventory) | markers only, no data change (commit b0eca043) | — |
| 2026-10-05 | Scripts/diff_studio_g4.py | F.4-1, F.5-1…F.5-3/F.3-3, 6.2-1, C.12-2…C.12-5, 7.8.1, A-1 (TS rows), C.7.3.1.1.1, PS3.10 7.1-1, PS3.11 A.1-1…N.1-1 | new check module, 22 checks ok (commit f02ee47a) | — |

---

## Priority action list (P-items: public API, owner's decision needed)

| Item | What | Standard | Recommendation | Status |
|---|---|---|---|---|
| P-STUDIO-ANON-PS315 | `AnonymizationProfile` (DICOMStudio, public enum) has no case for the PS3.15 Basic Profile, which is dicom-anon's default (`ps315`); the Workshop refuses it, the Security panel cannot run it | PS3.15 2026a Annex E, Table E.1-1 | Add `.ps315` (display "PS3.15 Basic Application Level Confidentiality Profile"), make it the default, route it to `Anonymizer.deidentify`; keep the legacy cases, labelled as not PS3.15 | ⏳ pending |
| P-VIDEO-CONTAINER | DICOMKit `VideoContainer` lacks `.mpegPS` / `.mpegPES` because `ViewerNonImageContentView.swift` switches exhaustively (D237) | PS3.5 2026a 8.2.5, 8.2.6 | Give the Studio switch a `default`, then add the two cases in DICOMKit (D237) | ⏳ pending |
| P-PRINT-ENUMS | `NetworkingModel.swift` re-declares `PrintPriority`, `PrintMediumType`, `PrintFilmSize`, `PrintJobStatus` with their own strings (D22); `BLU-RAY` is not a Medium Type term | PS3.3 2026a C.13.1 | Fix the strings as behaviour now; deprecate the four Studio enums in favour of the DICOMNetwork types | ⏳ pending |

---

## Deferred findings

### Rows inherited from earlier reports (worked first)

| Row | From | File | Problem | Standard | Status |
|---|---|---|---|---|---|
| D9 | DICOMCore | `Models/J2KTestBenchModels.swift:123,392` | .4.110 called "JPEG XL Lossless Only"; PS3.6 name "JPEG XL Lossless" | PS3.6 Table A-1 | ⏳ |
| D10 | DICOMCore | `Components/ThumbnailHelpers.swift:107` | `supportedPhotometricInterpretations` omits XYB, YBR_PARTIAL_420, YBR_ICT, YBR_RCT | PS3.3 C.7.6.3.1.2 | ⏳ |
| D11 | DICOMCore | `Components/ImageMetadataHelpers.swift:62` | no label for XYB | PS3.3 C.7.6.3.1.2 | ⏳ |
| D22 | DICOMNetwork | `Models/NetworkingModel.swift` (~L907-1050) | `PrintMediumType.bluFilm = "BLU-RAY"`; re-declared print enums | PS3.3 C.13.1 | ⏳ (P-PRINT-ENUMS) |
| D28 | DICOMKit | `ImageViewerViewModel+PresentationStates` (~L1057); `Views/DICOMInspectorView.swift:41` | PR without Modality LUT falls back to the image's rescale (S-2 migration rule); "is binary" check omits OV (D5 half) | PS3.4 N.2.1.1; PS3.5 Table 6.2-1 | ⏳ |
| D29 | DICOMKit | `CLIWorkshopViewModel.swift:1730`, `CLIWorkshopHelpers.swift:3128` | dcmdir `--profile` choices list STD-GEN-DVD / STD-GEN-USB (family headings) | PS3.11 Annexes H, J | ⏳ |
| D42 | DICOMPrintKit | `ImageViewerViewModel+PresentationStates.swift` (~L460, 610, 1040), `PrintViewModel+PresentationStates.swift` (~L365) | pass Photometric Interpretation and Rescale Type to the bridge and `ImageToSave` | PS3.4 N.2; PS3.3 A.33.1.1, Table A.33.2-1 | ⏳ |
| D56 | DICOMKit | CLI Workshop video form | no Audio Channel Source field | PS3.3 Table C.7-13; PS3.16 CID 3000 | ⏳ |
| D65 (viewer half) | DICOMRenderKit | `ImageViewerViewModel.swift` ~L1390, ~L1432; `+PresentationStates.swift` ~L1060 | stored-unit window conversion exact for slope 1 only | PS3.3 C.11.2.1.2.1 | ⏳ |
| D68 | DICOMRenderKit | `Services/FrameRenderer.swift`, `ViewModels/ImageViewerViewModel.swift` | pass Modality LUT, VOI and ICC Profile to `FrameRenderRequest` | PS3.4 N.2; PS3.3 C.11.2.1.2.1, C.11.15.1.1 | ⏳ |
| D85 | DICOMCLI | `CLIWorkshopHelpers.swift:1379-1380, 1217-1221` | mpps placeholder "110513\|DCM\|Doctor cancelled procedure"; `--modality` optional | PS3.16 Table D-1; PS3.4 Table F.7.2-1 | ⏳ |
| D88 | DICOMCLI | `Tests/DICOMStudioTests/NetworkToolWorkshopCLIParityTests.swift:151-157` | fixtures with wrong CID 9300 code/meaning pairs | PS3.16 Table D-1 | ⏳ |
| D114 | DICOMCLI | `CLIWorkshopViewModel.swift:1258`, `CLIWorkshopHelpers.swift:2847, 2920` | json/xml empty-attribute default differs from the CLI (on); no `--no-include-empty` | PS3.18 F.2.5; PS3.19 A.1.5-2 | ⏳ |
| D127 | DICOMCLI | `CLIWorkshopViewModel.swift:4410, 4557-4562, 4620-4628` | contact-sheet / animate copy the old render path; fps default | PS3.4 N.2; PS3.3 C.11.2.1.2.1 | ⏳ |
| D132 | DICOMCLI | Workshop dcmdir executor | lacks the CLI validate rules and File-set ID default | PS3.10 8.x | ⏳ |
| D154 | DICOMCLI | `CLIWorkshopHelpers.swift:2520` | split `--frames` help does not say 0-based | PS3.3 C.7.6.16.1.2 | ⏳ |
| D237 | DICOMCLI | `Views/ViewerNonImageContentView.swift:422` | exhaustive switch blocks `VideoContainer.mpegPS` / `.mpegPES` | PS3.5 8.2.5, 8.2.6 | ⏳ (P-VIDEO-CONTAINER) |

### New findings for other modules

| ID | Module | File | Problem | Standard | Severity | Status |
|---|---|---|---|---|---|---|

---

## Workshop ↔ CLI parity (G1)

One subsection per Workshop tool, filled as each is verified: the parity table from `diff_studio.py --emit-parity
<tool>` (Workshop parameter, CLI option, DICOM concept, 2026a reference, values and defaults on both sides, verdict),
the output parity (what the executor prints or returns against the CLI's shared console functions), the findings and
their commits. Handed-over follow-ups from DICOMCLI_STANDARD_IMPLEMENTATION.md "Rows handed to DICOMStudio" parts 3
and 4 are closed in the tool they belong to.

(to be filled)

---

## File inventory (all 334 files)

Bucket per the method (A, B1, B2, C1, C2) is recorded for ST files once verified; CR files get "confirmed NST" or
are promoted to ST; NST files carry the scan result. "Marker" names the marker line or "none (inventoried)".

### G1 — CLI Workshop

| File | Tier | Bucket | What it carries / what was compared | Marker | Status |
|---|---|---|---|---|---|
| [BrowserNavigationHelpers.swift](Sources/DICOMStudio/Components/BrowserNavigationHelpers.swift) | ST | — | to verify | — | ⏳ |
| [CLIShellFoundationHelpers.swift](Sources/DICOMStudio/Components/CLIShellFoundationHelpers.swift) | ST | — | to verify | — | ⏳ |
| [CLIToolBuilder.swift](Sources/DICOMStudio/Components/CLIToolBuilder.swift) | ST | — | to verify | — | ⏳ |
| [CLIToolTerminalCompare.swift](Sources/DICOMStudio/Components/CLIToolTerminalCompare.swift) | ST | — | to verify | — | ⏳ |
| [CLIWorkshopHelpers.swift](Sources/DICOMStudio/Components/CLIWorkshopHelpers.swift) | ST | — | to verify | — | ⏳ |
| [ImportValidation.swift](Sources/DICOMStudio/Components/ImportValidation.swift) | ST | — | to verify | — | ⏳ |
| [IntegratedTerminalHelpers.swift](Sources/DICOMStudio/Components/IntegratedTerminalHelpers.swift) | ST | — | to verify | — | ⏳ |
| [ParameterBuilderHelpers.swift](Sources/DICOMStudio/Components/ParameterBuilderHelpers.swift) | ST | — | to verify | — | ⏳ |
| [ShellServerConfigHelpers.swift](Sources/DICOMStudio/Components/ShellServerConfigHelpers.swift) | ST | — | to verify | — | ⏳ |
| [BrowserNavigationModel.swift](Sources/DICOMStudio/Models/BrowserNavigationModel.swift) | ST | — | to verify | — | ⏳ |
| [CLIShellFoundationModel.swift](Sources/DICOMStudio/Models/CLIShellFoundationModel.swift) | ST | — | to verify | — | ⏳ |
| [CLIWorkshopModel.swift](Sources/DICOMStudio/Models/CLIWorkshopModel.swift) | ST | — | to verify | — | ⏳ |
| [IntegrationTestingModel.swift](Sources/DICOMStudio/Models/IntegrationTestingModel.swift) | ST | — | to verify | — | ⏳ |
| [ParameterBuilderModel.swift](Sources/DICOMStudio/Models/ParameterBuilderModel.swift) | ST | — | to verify | — | ⏳ |
| [ShellServerConfigModel.swift](Sources/DICOMStudio/Models/ShellServerConfigModel.swift) | ST | — | to verify | — | ⏳ |
| [ValidationModel.swift](Sources/DICOMStudio/Models/ValidationModel.swift) | ST | — | to verify | — | ⏳ |
| [CLIWorkshopService.swift](Sources/DICOMStudio/Services/CLIWorkshopService.swift) | ST | — | to verify | — | ⏳ |
| [CLIWorkshopViewModel.swift](Sources/DICOMStudio/ViewModels/CLIWorkshopViewModel.swift) | ST | — | to verify | — | ⏳ |
| [ValidationViewModel.swift](Sources/DICOMStudio/ViewModels/ValidationViewModel.swift) | ST | — | to verify | — | ⏳ |
| [ValidationView.swift](Sources/DICOMStudio/Views/ValidationView.swift) | ST | — | to verify | — | ⏳ |
| [IntegratedTerminalModel.swift](Sources/DICOMStudio/Models/IntegratedTerminalModel.swift) | CR | — | confirm-read pending | — | ⏳ |
| [CLIWorkshopView.swift](Sources/DICOMStudio/Views/CLIWorkshopView.swift) | CR | — | confirm-read pending | — | ⏳ |
| [IntegrationTestingHelpers.swift](Sources/DICOMStudio/Components/IntegrationTestingHelpers.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [BrowserNavigationService.swift](Sources/DICOMStudio/Services/BrowserNavigationService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [CLIShellFoundationService.swift](Sources/DICOMStudio/Services/CLIShellFoundationService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [IntegratedTerminalService.swift](Sources/DICOMStudio/Services/IntegratedTerminalService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [IntegrationTestingService.swift](Sources/DICOMStudio/Services/IntegrationTestingService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [ParameterBuilderService.swift](Sources/DICOMStudio/Services/ParameterBuilderService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [ShellServerConfigService.swift](Sources/DICOMStudio/Services/ShellServerConfigService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [ValidationService.swift](Sources/DICOMStudio/Services/ValidationService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [BrowserNavigationViewModel.swift](Sources/DICOMStudio/ViewModels/BrowserNavigationViewModel.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [CLIShellFoundationViewModel.swift](Sources/DICOMStudio/ViewModels/CLIShellFoundationViewModel.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [IntegratedTerminalViewModel.swift](Sources/DICOMStudio/ViewModels/IntegratedTerminalViewModel.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [IntegrationTestingViewModel.swift](Sources/DICOMStudio/ViewModels/IntegrationTestingViewModel.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [ParameterBuilderViewModel.swift](Sources/DICOMStudio/ViewModels/ParameterBuilderViewModel.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [ShellServerConfigViewModel.swift](Sources/DICOMStudio/ViewModels/ShellServerConfigViewModel.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [IntegrationTestingView.swift](Sources/DICOMStudio/Views/IntegrationTestingView.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |

### G2 — Viewer and rendering

| File | Tier | Bucket | What it carries / what was compared | Marker | Status |
|---|---|---|---|---|---|
| [AnnotationHelpers.swift](Sources/DICOMStudio/Components/AnnotationHelpers.swift) | ST | — | to verify | — | ⏳ |
| [BlendingHelpers.swift](Sources/DICOMStudio/Components/BlendingHelpers.swift) | ST | — | to verify | — | ⏳ |
| [CodecInspectorHelpers.swift](Sources/DICOMStudio/Components/CodecInspectorHelpers.swift) | ST | — | to verify | — | ⏳ |
| [ColorLUTHelpers.swift](Sources/DICOMStudio/Components/ColorLUTHelpers.swift) | ST | — | to verify | — | ⏳ |
| [EnterpriseRenderHelpers.swift](Sources/DICOMStudio/Components/EnterpriseRenderHelpers.swift) | ST | — | to verify | — | ⏳ |
| [ICCProfileHelpers.swift](Sources/DICOMStudio/Components/ICCProfileHelpers.swift) | ST | — | to verify | — | ⏳ |
| [ImageInversion.swift](Sources/DICOMStudio/Components/ImageInversion.swift) | ST | — | to verify | — | ⏳ |
| [ImageMetadataHelpers.swift](Sources/DICOMStudio/Components/ImageMetadataHelpers.swift) | ST | — | to verify | — | ⏳ |
| [JP3DMPRSliceExtractor.swift](Sources/DICOMStudio/Components/JP3DMPRSliceExtractor.swift) | ST | — | to verify | — | ⏳ |
| [MPRHelpers.swift](Sources/DICOMStudio/Components/MPRHelpers.swift) | ST | — | to verify | — | ⏳ |
| [MacOSEnhancementsHelpers.swift](Sources/DICOMStudio/Components/MacOSEnhancementsHelpers.swift) | ST | — | to verify | — | ⏳ |
| [ModalityIcon.swift](Sources/DICOMStudio/Components/ModalityIcon.swift) | ST | — | to verify | — | ⏳ |
| [ModalityPicker.swift](Sources/DICOMStudio/Components/ModalityPicker.swift) | ST | — | to verify | — | ⏳ |
| [PresentationStateHelpers.swift](Sources/DICOMStudio/Components/PresentationStateHelpers.swift) | ST | — | to verify | — | ⏳ |
| [ShutterHelpers.swift](Sources/DICOMStudio/Components/ShutterHelpers.swift) | ST | — | to verify | — | ⏳ |
| [ThumbnailHelpers.swift](Sources/DICOMStudio/Components/ThumbnailHelpers.swift) | ST | — | to verify | — | ⏳ |
| [WindowLevelPresets.swift](Sources/DICOMStudio/Components/WindowLevelPresets.swift) | ST | — | to verify | — | ⏳ |
| [AnnotationModel.swift](Sources/DICOMStudio/Models/AnnotationModel.swift) | ST | — | to verify | — | ⏳ |
| [CodecInspectorModel.swift](Sources/DICOMStudio/Models/CodecInspectorModel.swift) | ST | — | to verify | — | ⏳ |
| [J2KTestBenchModels.swift](Sources/DICOMStudio/Models/J2KTestBenchModels.swift) | ST | — | to verify | — | ⏳ |
| [PresentationStateModel.swift](Sources/DICOMStudio/Models/PresentationStateModel.swift) | ST | — | to verify | — | ⏳ |
| [ProgressiveDecodeModel.swift](Sources/DICOMStudio/Models/ProgressiveDecodeModel.swift) | ST | — | to verify | — | ⏳ |
| [ShutterModel.swift](Sources/DICOMStudio/Models/ShutterModel.swift) | ST | — | to verify | — | ⏳ |
| [ViewerAnnotationText.swift](Sources/DICOMStudio/Models/ViewerAnnotationText.swift) | ST | — | to verify | — | ⏳ |
| [ViewerContentKind.swift](Sources/DICOMStudio/Models/ViewerContentKind.swift) | ST | — | to verify | — | ⏳ |
| [ViewerNonImageContent.swift](Sources/DICOMStudio/Models/ViewerNonImageContent.swift) | ST | — | to verify | — | ⏳ |
| [VolumeVisualizationModel.swift](Sources/DICOMStudio/Models/VolumeVisualizationModel.swift) | ST | — | to verify | — | ⏳ |
| [CharLSCLICodec.swift](Sources/DICOMStudio/Services/CharLSCLICodec.swift) | ST | — | to verify | — | ⏳ |
| [FrameRenderer.swift](Sources/DICOMStudio/Services/FrameRenderer.swift) | ST | — | to verify | — | ⏳ |
| [FrameSourceCache.swift](Sources/DICOMStudio/Services/FrameSourceCache.swift) | ST | — | to verify | — | ⏳ |
| [ImageDecodingService.swift](Sources/DICOMStudio/Services/ImageDecodingService.swift) | ST | — | to verify | — | ⏳ |
| [ImageRenderingService.swift](Sources/DICOMStudio/Services/ImageRenderingService.swift) | ST | — | to verify | — | ⏳ |
| [J2KTestBenchService.swift](Sources/DICOMStudio/Services/J2KTestBenchService.swift) | ST | — | to verify | — | ⏳ |
| [PresentationStateService.swift](Sources/DICOMStudio/Services/PresentationStateService.swift) | ST | — | to verify | — | ⏳ |
| [StudyPresentationStateAdoption.swift](Sources/DICOMStudio/Services/StudyPresentationStateAdoption.swift) | ST | — | to verify | — | ⏳ |
| [CodecInspectorViewModel.swift](Sources/DICOMStudio/ViewModels/CodecInspectorViewModel.swift) | ST | — | to verify | — | ⏳ |
| [DICOMVolumeViewerViewModel.swift](Sources/DICOMStudio/ViewModels/DICOMVolumeViewerViewModel.swift) | ST | — | to verify | — | ⏳ |
| [ImageViewerViewModel+PatientOverlay.swift](Sources/DICOMStudio/ViewModels/ImageViewerViewModel+PatientOverlay.swift) | ST | — | to verify | — | ⏳ |
| [ImageViewerViewModel+PresentationStates.swift](Sources/DICOMStudio/ViewModels/ImageViewerViewModel+PresentationStates.swift) | ST | — | to verify | — | ⏳ |
| [ImageViewerViewModel.swift](Sources/DICOMStudio/ViewModels/ImageViewerViewModel.swift) | ST | — | to verify | — | ⏳ |
| [J2KTestBenchViewModel.swift](Sources/DICOMStudio/ViewModels/J2KTestBenchViewModel.swift) | ST | — | to verify | — | ⏳ |
| [J2KTestingViewModel.swift](Sources/DICOMStudio/ViewModels/J2KTestingViewModel.swift) | ST | — | to verify | — | ⏳ |
| [JP3DComparisonViewModel.swift](Sources/DICOMStudio/ViewModels/JP3DComparisonViewModel.swift) | ST | — | to verify | — | ⏳ |
| [JP3DVolumeComparisonViewModel.swift](Sources/DICOMStudio/ViewModels/JP3DVolumeComparisonViewModel.swift) | ST | — | to verify | — | ⏳ |
| [PresentationStateViewModel.swift](Sources/DICOMStudio/ViewModels/PresentationStateViewModel.swift) | ST | — | to verify | — | ⏳ |
| [AnnotationOverlayView.swift](Sources/DICOMStudio/Views/AnnotationOverlayView.swift) | ST | — | to verify | — | ⏳ |
| [CodecInspectorView.swift](Sources/DICOMStudio/Views/CodecInspectorView.swift) | ST | — | to verify | — | ⏳ |
| [MainView.swift](Sources/DICOMStudio/Views/MainView.swift) | ST | — | to verify | — | ⏳ |
| [SavedViewPickerView.swift](Sources/DICOMStudio/Views/SavedViewPickerView.swift) | ST | — | to verify | — | ⏳ |
| [ShutterOverlayView.swift](Sources/DICOMStudio/Views/ShutterOverlayView.swift) | ST | — | to verify | — | ⏳ |
| [ViewerNonImageContentView.swift](Sources/DICOMStudio/Views/ViewerNonImageContentView.swift) | ST | — | to verify | — | ⏳ |
| [WindowLevelPanel.swift](Sources/DICOMStudio/Views/WindowLevelPanel.swift) | ST | — | to verify | — | ⏳ |
| [J2KBenchmarkBaseline.swift](Sources/DICOMStudio/Components/J2KBenchmarkBaseline.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ViewportLayoutHelpers.swift](Sources/DICOMStudio/Components/ViewportLayoutHelpers.swift) | CR | — | confirm-read pending | — | ⏳ |
| [MacOSEnhancementsModel.swift](Sources/DICOMStudio/Models/MacOSEnhancementsModel.swift) | CR | — | confirm-read pending | — | ⏳ |
| [PatientOverlayText.swift](Sources/DICOMStudio/Models/PatientOverlayText.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ViewerAnnotationCorners.swift](Sources/DICOMStudio/Models/ViewerAnnotationCorners.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ViewerHoverGeometry.swift](Sources/DICOMStudio/Models/ViewerHoverGeometry.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ViewerSeriesEntry.swift](Sources/DICOMStudio/Models/ViewerSeriesEntry.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ViewerTileLayout.swift](Sources/DICOMStudio/Models/ViewerTileLayout.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ViewportModel.swift](Sources/DICOMStudio/Models/ViewportModel.swift) | CR | — | confirm-read pending | — | ⏳ |
| [FrameImageStore.swift](Sources/DICOMStudio/Services/FrameImageStore.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ThumbnailService.swift](Sources/DICOMStudio/Services/ThumbnailService.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ViewerTileImageCache.swift](Sources/DICOMStudio/Services/ViewerTileImageCache.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ViewerTileTextureCache.swift](Sources/DICOMStudio/Services/ViewerTileTextureCache.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ImageViewerViewModel+Annotations.swift](Sources/DICOMStudio/ViewModels/ImageViewerViewModel+Annotations.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ImageViewerViewModel+Layout.swift](Sources/DICOMStudio/ViewModels/ImageViewerViewModel+Layout.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ImageViewerViewModel+StudyDownload.swift](Sources/DICOMStudio/ViewModels/ImageViewerViewModel+StudyDownload.swift) | CR | — | confirm-read pending | — | ⏳ |
| [JP3DMPRViewModel.swift](Sources/DICOMStudio/ViewModels/JP3DMPRViewModel.swift) | CR | — | confirm-read pending | — | ⏳ |
| [MultiViewportViewModel.swift](Sources/DICOMStudio/ViewModels/MultiViewportViewModel.swift) | CR | — | confirm-read pending | — | ⏳ |
| [DICOMVolumeViewerView.swift](Sources/DICOMStudio/Views/DICOMVolumeViewerView.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ImageMetadataOverlayView.swift](Sources/DICOMStudio/Views/ImageMetadataOverlayView.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ImageViewerView.swift](Sources/DICOMStudio/Views/ImageViewerView.swift) | CR | — | confirm-read pending | — | ⏳ |
| [J2KTestBenchView.swift](Sources/DICOMStudio/Views/J2KTestBenchView.swift) | CR | — | confirm-read pending | — | ⏳ |
| [J2KTestingView.swift](Sources/DICOMStudio/Views/J2KTestingView.swift) | CR | — | confirm-read pending | — | ⏳ |
| [JP3DComparisonView.swift](Sources/DICOMStudio/Views/JP3DComparisonView.swift) | CR | — | confirm-read pending | — | ⏳ |
| [JP3DMPRView.swift](Sources/DICOMStudio/Views/JP3DMPRView.swift) | CR | — | confirm-read pending | — | ⏳ |
| [JP3DVolumeComparisonView.swift](Sources/DICOMStudio/Views/JP3DVolumeComparisonView.swift) | CR | — | confirm-read pending | — | ⏳ |
| [MacOSEnhancementsView.swift](Sources/DICOMStudio/Views/MacOSEnhancementsView.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ProgressiveImageView.swift](Sources/DICOMStudio/Views/ProgressiveImageView.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ViewerAnnotationEditLayer.swift](Sources/DICOMStudio/Views/ViewerAnnotationEditLayer.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ViewerImageSavedViewList.swift](Sources/DICOMStudio/Views/ViewerImageSavedViewList.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ViewerTileGridView.swift](Sources/DICOMStudio/Views/ViewerTileGridView.swift) | CR | — | confirm-read pending | — | ⏳ |
| [StudioWindowCommands.swift](Sources/DICOMStudio/App/StudioWindowCommands.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [ViewerCommands.swift](Sources/DICOMStudio/App/ViewerCommands.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [CinePlaybackHelpers.swift](Sources/DICOMStudio/Components/CinePlaybackHelpers.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [ClipboardHelper.swift](Sources/DICOMStudio/Components/ClipboardHelper.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [GestureHelpers.swift](Sources/DICOMStudio/Components/GestureHelpers.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [ImageCacheHelpers.swift](Sources/DICOMStudio/Components/ImageCacheHelpers.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [InteractiveSurface.swift](Sources/DICOMStudio/Components/InteractiveSurface.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [J2KBenchImageRenderer.swift](Sources/DICOMStudio/Components/J2KBenchImageRenderer.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [J2KTestBenchExporter.swift](Sources/DICOMStudio/Components/J2KTestBenchExporter.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [JP3DMPRRenderHelpers.swift](Sources/DICOMStudio/Components/JP3DMPRRenderHelpers.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [OutputAccess.swift](Sources/DICOMStudio/Components/OutputAccess.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [ProjectionHelpers.swift](Sources/DICOMStudio/Components/ProjectionHelpers.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [ScrollWheelModifier.swift](Sources/DICOMStudio/Components/ScrollWheelModifier.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [StatusIndicator.swift](Sources/DICOMStudio/Components/StatusIndicator.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [SurfaceExtractionHelpers.swift](Sources/DICOMStudio/Components/SurfaceExtractionHelpers.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [TooltipModifier.swift](Sources/DICOMStudio/Components/TooltipModifier.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [VolumeRenderingHelpers.swift](Sources/DICOMStudio/Components/VolumeRenderingHelpers.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [DICOMStudioApp.swift](Sources/DICOMStudioApp/DICOMStudioApp.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [SavedViewReference.swift](Sources/DICOMStudio/Models/SavedViewReference.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [AnnotationOverlayTextureCache.swift](Sources/DICOMStudio/Services/AnnotationOverlayTextureCache.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [AnnotationTextureBuilder.swift](Sources/DICOMStudio/Services/AnnotationTextureBuilder.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [ImageCacheService.swift](Sources/DICOMStudio/Services/ImageCacheService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [J2KTestBenchStore.swift](Sources/DICOMStudio/Services/J2KTestBenchStore.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [MacOSEnhancementsService.swift](Sources/DICOMStudio/Services/MacOSEnhancementsService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [NavigationService.swift](Sources/DICOMStudio/Services/NavigationService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [PatientOverlayTextCache.swift](Sources/DICOMStudio/Services/PatientOverlayTextCache.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [SettingsService.swift](Sources/DICOMStudio/Services/SettingsService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [ViewerAnnotationTextCache.swift](Sources/DICOMStudio/Services/ViewerAnnotationTextCache.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [VolumeVisualizationService.swift](Sources/DICOMStudio/Services/VolumeVisualizationService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [StudioTheme.swift](Sources/DICOMStudio/Theme/StudioTheme.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [ImageViewerViewModel+DrawnAnnotationEditing.swift](Sources/DICOMStudio/ViewModels/ImageViewerViewModel+DrawnAnnotationEditing.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [ImageViewerViewModel+ImageNavigation.swift](Sources/DICOMStudio/ViewModels/ImageViewerViewModel+ImageNavigation.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [ImageViewerViewModel+Series.swift](Sources/DICOMStudio/ViewModels/ImageViewerViewModel+Series.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [MacOSEnhancementsViewModel.swift](Sources/DICOMStudio/ViewModels/MacOSEnhancementsViewModel.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [SettingsViewModel.swift](Sources/DICOMStudio/ViewModels/SettingsViewModel.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [VolumeVisualizationViewModel.swift](Sources/DICOMStudio/ViewModels/VolumeVisualizationViewModel.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [CineControlsView.swift](Sources/DICOMStudio/Views/CineControlsView.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [CodecImageComparisonView.swift](Sources/DICOMStudio/Views/CodecImageComparisonView.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [KeyboardShortcutsLegendView.swift](Sources/DICOMStudio/Views/KeyboardShortcutsLegendView.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [MultiViewportView.swift](Sources/DICOMStudio/Views/MultiViewportView.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [PatientIdentificationOverlayView.swift](Sources/DICOMStudio/Views/PatientIdentificationOverlayView.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [SavedViewPromptView.swift](Sources/DICOMStudio/Views/SavedViewPromptView.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [ScrollWheelHandler.swift](Sources/DICOMStudio/Views/ScrollWheelHandler.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [AboutView.swift](Sources/DICOMStudio/Views/Settings/AboutView.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [GeneralSettingsView.swift](Sources/DICOMStudio/Views/Settings/GeneralSettingsView.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [PerformanceSettingsView.swift](Sources/DICOMStudio/Views/Settings/PerformanceSettingsView.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [SettingsView.swift](Sources/DICOMStudio/Views/Settings/SettingsView.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [SidebarView.swift](Sources/DICOMStudio/Views/SidebarView.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [ToolSymbolCursor.swift](Sources/DICOMStudio/Views/ToolSymbolCursor.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [ViewerAnnotationOverlayView.swift](Sources/DICOMStudio/Views/ViewerAnnotationOverlayView.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [ViewerPalettePickerView.swift](Sources/DICOMStudio/Views/ViewerPalettePickerView.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [ViewerPaneChrome.swift](Sources/DICOMStudio/Views/ViewerPaneChrome.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [ViewerSeriesPaneView.swift](Sources/DICOMStudio/Views/ViewerSeriesPaneView.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [ViewerSeriesSavedViewList.swift](Sources/DICOMStudio/Views/ViewerSeriesSavedViewList.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |

### G3 — Network and web

| File | Tier | Bucket | What it carries / what was compared | Marker | Status |
|---|---|---|---|---|---|
| [DICOMwebHelpers.swift](Sources/DICOMStudio/Components/DICOMwebHelpers.swift) | ST | — | to verify | — | ⏳ |
| [NetworkingHelpers.swift](Sources/DICOMStudio/Components/NetworkingHelpers.swift) | ST | — | to verify | — | ⏳ |
| [PerformanceToolsHelpers.swift](Sources/DICOMStudio/Components/PerformanceToolsHelpers.swift) | ST | — | to verify | — | ⏳ |
| [PolishReleaseHelpers.swift](Sources/DICOMStudio/Components/PolishReleaseHelpers.swift) | ST | — | to verify | — | ⏳ |
| [CloudIntegrationModel.swift](Sources/DICOMStudio/Models/CloudIntegrationModel.swift) | ST | — | to verify | — | ⏳ |
| [DICOMwebModel.swift](Sources/DICOMStudio/Models/DICOMwebModel.swift) | ST | — | to verify | — | ⏳ |
| [NetworkingModel.swift](Sources/DICOMStudio/Models/NetworkingModel.swift) | ST | — | to verify | — | ⏳ |
| [PerformanceToolsModel.swift](Sources/DICOMStudio/Models/PerformanceToolsModel.swift) | ST | — | to verify | — | ⏳ |
| [PolishReleaseModel.swift](Sources/DICOMStudio/Models/PolishReleaseModel.swift) | ST | — | to verify | — | ⏳ |
| [DICOMwebClientFactory.swift](Sources/DICOMStudio/Services/DICOMwebClientFactory.swift) | ST | — | to verify | — | ⏳ |
| [DICOMwebService.swift](Sources/DICOMStudio/Services/DICOMwebService.swift) | ST | — | to verify | — | ⏳ |
| [NetworkingService.swift](Sources/DICOMStudio/Services/NetworkingService.swift) | ST | — | to verify | — | ⏳ |
| [PerformanceToolsService.swift](Sources/DICOMStudio/Services/PerformanceToolsService.swift) | ST | — | to verify | — | ⏳ |
| [DICOMwebViewModel.swift](Sources/DICOMStudio/ViewModels/DICOMwebViewModel.swift) | ST | — | to verify | — | ⏳ |
| [NetworkingViewModel.swift](Sources/DICOMStudio/ViewModels/NetworkingViewModel.swift) | ST | — | to verify | — | ⏳ |
| [PerformanceToolsViewModel.swift](Sources/DICOMStudio/ViewModels/PerformanceToolsViewModel.swift) | ST | — | to verify | — | ⏳ |
| [DICOMwebView.swift](Sources/DICOMStudio/Views/DICOMwebView.swift) | ST | — | to verify | — | ⏳ |
| [NetworkingView.swift](Sources/DICOMStudio/Views/NetworkingView.swift) | ST | — | to verify | — | ⏳ |
| [PerformanceToolsView.swift](Sources/DICOMStudio/Views/PerformanceToolsView.swift) | ST | — | to verify | — | ⏳ |
| [GatewayModel.swift](Sources/DICOMStudio/Models/GatewayModel.swift) | CR | — | confirm-read pending | — | ⏳ |
| [CloudIntegrationViewModel.swift](Sources/DICOMStudio/ViewModels/CloudIntegrationViewModel.swift) | CR | — | confirm-read pending | — | ⏳ |
| [GatewayViewModel.swift](Sources/DICOMStudio/ViewModels/GatewayViewModel.swift) | CR | — | confirm-read pending | — | ⏳ |
| [CloudIntegrationView.swift](Sources/DICOMStudio/Views/CloudIntegrationView.swift) | CR | — | confirm-read pending | — | ⏳ |
| [GatewayView.swift](Sources/DICOMStudio/Views/GatewayView.swift) | CR | — | confirm-read pending | — | ⏳ |
| [NetworkUtilityModel.swift](Sources/DICOMStudio/Models/NetworkUtilityModel.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [CloudIntegrationService.swift](Sources/DICOMStudio/Services/CloudIntegrationService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [DICOMwebServerProfileStorageService.swift](Sources/DICOMStudio/Services/DICOMwebServerProfileStorageService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [GatewayService.swift](Sources/DICOMStudio/Services/GatewayService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [NetworkUtilityService+Parsing.swift](Sources/DICOMStudio/Services/NetworkUtilityService+Parsing.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [NetworkUtilityService.swift](Sources/DICOMStudio/Services/NetworkUtilityService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [PolishReleaseService.swift](Sources/DICOMStudio/Services/PolishReleaseService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [ServerProfileStorageService.swift](Sources/DICOMStudio/Services/ServerProfileStorageService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [NetworkUtilityViewModel.swift](Sources/DICOMStudio/ViewModels/NetworkUtilityViewModel.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [PolishReleaseViewModel.swift](Sources/DICOMStudio/ViewModels/PolishReleaseViewModel.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [LocalListenerView.swift](Sources/DICOMStudio/Views/LocalListenerView.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [NetworkUtilityView.swift](Sources/DICOMStudio/Views/NetworkUtilityView.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [PolishReleaseView.swift](Sources/DICOMStudio/Views/PolishReleaseView.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |

### G4 — File, media and DICOMDIR

| File | Tier | Bucket | What it carries / what was compared | Marker | Status |
|---|---|---|---|---|---|
| [DICOMDIRParser.swift](Sources/DICOMStudio/Components/DICOMDIRParser.swift) | ST | B2 | Table F.4-1 record types 35: 29 matched, 6 missing added, 1 retired kept; record keys 8/8 in F.5-1/F.5-2/F.5-3/F.3-3; File ID backslash split (PS3.10 8.2) | `NEMA-verified: 2026a, checked 2026-10-05 — \`knownRecordTypes\` diffed against the 35 Directory Record Types of PS3.3 2026a Table F.4-1 …` | fixed, ✅ |
| [DICOMValueParser.swift](Sources/DICOMStudio/Components/DICOMValueParser.swift) | ST | B2 | per-VR formats (11 VR cases, all real VRs); PN component groups added; charset terms 32: 19 matched, 13 added | `NEMA-verified: 2026a, checked 2026-10-05 — per-VR formatting checked against PS3.5 2026a Table 6.2-1 …` | fixed, ✅ |
| [DataExchangeHelpers.swift](Sources/DICOMStudio/Components/DataExchangeHelpers.swift) | ST | B2 | 8 TS UIDs all A-1 TS rows; 6/8 names were abbreviations → DICOMCore A-1 names; Encapsulated PDF Storage UID ok; citations 2026a ok | `NEMA-verified: 2026a, checked 2026-10-05 — \`TransferSyntaxHelpers.wellKnownSyntaxes\`: the 8 UIDs are PS3.6 2026a Table A-1 Transfer Syntax rows …` | fixed, ✅ |
| [FileOperationsHelpers.swift](Sources/DICOMStudio/Components/FileOperationsHelpers.swift) | ST | C2 (+codec names) | DICM at 128–131 (PS3.10 7.1); 13 TS UIDs are A-1 TS rows (names: agent codec); PN components | `… DICM prefix at bytes 128–131 after the 128-byte File Preamble (PS3.10 2026a 7.1); … comment names are corrected by the codec pass and not claimed here …` | ✅ (marker only; file also carries codec hunks) |
| [PrivateTagIdentifier.swift](Sources/DICOMStudio/Components/PrivateTagIdentifier.swift) | ST | B2 | 7.8.1 reserved groups 5/5 (were accepted), creator range 0010-00FF ok; vendor table not NEMA data | `NEMA-verified: 2026a, checked 2026-10-05 — \`isPrivateGroup\` and \`isPrivateCreator\` checked against PS3.5 2026a 7.8.1 …` | fixed, ✅ |
| [StudyBrowserHelpers.swift](Sources/DICOMStudio/Components/StudyBrowserHelpers.swift) | ST | C1 | none | `… carries no DICOM-standard data (sorting, filtering and search over the library models).` | ✅ |
| [VRBadge.swift](Sources/DICOMStudio/Components/VRBadge.swift) | ST | B2 | Table 6.2-1 34 VRs: 25 matched, 2 wrong, 7 missing → all 34 | `NEMA-verified: 2026a, checked 2026-10-05 — \`VRDescriptions.fullName\` diffed against the 34 VRs of PS3.5 2026a Table 6.2-1 …` | fixed, ✅ |
| [ArchiveManagementModel.swift](Sources/DICOMStudio/Models/ArchiveManagementModel.swift) | ST | C1 | none | `… carries no DICOM-standard data (dicom-archive index entries, options and search fields; \`indexVersion\` is dicom-archive's).` | ✅ |
| [DataExchangeModel.swift](Sources/DICOMStudio/Models/DataExchangeModel.swift) | ST | C2 | DICOMDIREntry fields 5/5 F.5 keys; citations; targetDisplayName from DICOMCore | `NEMA-verified: 2026a, checked 2026-10-05 — tab, format, status and job enums carry no DICOM-standard values; …` | ✅ |
| [FileOperationsModel.swift](Sources/DICOMStudio/Models/FileOperationsModel.swift) | ST | C1 | none | `… carries no DICOM-standard data (drop-zone, output-path and scan state; …)` | ✅ |
| [ImportModels.swift](Sources/DICOMStudio/Models/ImportModels.swift) | ST | C1 | none | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (import results, validation rule identifiers and progress).` | ✅ |
| [InstanceModel.swift](Sources/DICOMStudio/Models/InstanceModel.swift) | ST | C2 | 10 fields ↔ Table 6-1 attributes | `… fields mirror PS3.6 2026a Table 6-1 attributes (SOP Instance UID, …); no standard values carried.` | ✅ |
| [LibraryModel.swift](Sources/DICOMStudio/Models/LibraryModel.swift) | ST | C1 | none | `… carries no DICOM-standard data (in-memory study/series/instance index keyed by the UIDs).` | ✅ |
| [MetadataTreeNode.swift](Sources/DICOMStudio/Models/MetadataTreeNode.swift) | ST | C2 | SQ, 0xFFFFFFFF undefined length (PS3.5 7.1.2, 7.5) | `NEMA-verified: 2026a, checked 2026-10-05 — \`isSequence\` keys on VR SQ and \`lengthString\` names 0xFFFFFFFF Undefined Length …` | ✅ |
| [SeriesModel.swift](Sources/DICOMStudio/Models/SeriesModel.swift) | ST | C2 | 5 fields ↔ Table 6-1; "OT" default ∈ C.7.3.1.1.1 | `… fields mirror PS3.6 2026a Table 6-1 attributes (Series Instance UID, …); default Modality "OT" …` | ✅ |
| [StudyModel.swift](Sources/DICOMStudio/Models/StudyModel.swift) | ST | C2 | 11 fields ↔ Table 6-1; PN display join | `… fields mirror PS3.6 2026a Table 6-1 attributes (Study Instance UID, …); \`patientDisplayName\` joins PN components …` | ✅ |
| [StudyRowSummary.swift](Sources/DICOMStudio/Models/StudyRowSummary.swift) | ST | C1 | none | `… carries no DICOM-standard data (row text derived from the study, series and instance models).` | ✅ |
| [DICOMFileService.swift](Sources/DICOMStudio/Services/DICOMFileService.swift) | ST | C2 | FMI reads 2/2 in Table 7.1-1; Media Storage Directory Storage UID ok; 3 Tag literals 6-1 ok; IS/DA handling; "OT" default | `NEMA-verified: 2026a, checked 2026-10-05 — Transfer Syntax UID read from File Meta Information (0002,0010) …` | ✅ |
| [DataExchangeService.swift](Sources/DICOMStudio/Services/DataExchangeService.swift) | ST | C1 | default target TS 1.2.840.10008.1.2.1 = Explicit VR LE | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (locked state store); …` | ✅ |
| [FileOperationsService.swift](Sources/DICOMStudio/Services/FileOperationsService.swift) | ST | C1 | none | `… carries no DICOM-standard data (drop handling and output path resolution).` | ✅ |
| [ImportService.swift](Sources/DICOMStudio/Services/ImportService.swift) | ST | C2 | DICM at 128 (PS3.10 7.1) via ImportValidation (G1) | `NEMA-verified: 2026a, checked 2026-10-05 — DICM prefix at offset 128 after the 128-byte File Preamble (PS3.10 2026a 7.1) …` | ✅ |
| [LibraryStorageService.swift](Sources/DICOMStudio/Services/LibraryStorageService.swift) | ST | C1 | none | `… carries no DICOM-standard data (JSON persistence of the library index).` | ✅ |
| [ViewerSeriesCatalog.swift](Sources/DICOMStudio/Services/ViewerSeriesCatalog.swift) | ST | C2 | Image Orientation (Patient) normal = row × column, LPS (C.7.6.2.1.1); plane names are convention | `… plane label from Image Orientation (Patient) (0020,0037): slice normal = row × column direction cosines …` | ✅ |
| [ArchiveManagementViewModel.swift](Sources/DICOMStudio/ViewModels/ArchiveManagementViewModel.swift) | ST | C1 | none | `… carries no DICOM-standard data (dicom-archive command lines and placeholder statistics).` | ✅ |
| [DataExchangeViewModel.swift](Sources/DICOMStudio/ViewModels/DataExchangeViewModel.swift) | ST | B2 | modality default vs C.7.3.1.1.1: "SC" wrong → "OT" | `NEMA-verified: 2026a, checked 2026-10-05 — default target Transfer Syntax 1.2.840.10008.1.2.1 is Explicit VR Little Endian …` | fixed, ✅ |
| [MainViewModel.swift](Sources/DICOMStudio/ViewModels/MainViewModel.swift) | ST | C1 | none | `… carries no DICOM-standard data (navigation, service wiring and viewer hand-off).` | ✅ |
| [MetadataViewModel.swift](Sources/DICOMStudio/ViewModels/MetadataViewModel.swift) | ST | B2 | TS name table 13 rows: 8 matched A-1, 5 wrong → DICOMCore displayName; FMI before Data Set (7.1-1); 6-1 names via DICOMDictionary | `NEMA-verified: 2026a, checked 2026-10-05 — tree nodes carry the tag, the DICOMCore VR (PS3.5 2026a Table 6.2-1, 34 VRs) …` | fixed, ✅ |
| [StudyBrowserViewModel.swift](Sources/DICOMStudio/ViewModels/StudyBrowserViewModel.swift) | ST | C1 | none | `… carries no DICOM-standard data (library state, import orchestration and file clean-up).` | ✅ |
| [ArchiveManagementView.swift](Sources/DICOMStudio/Views/ArchiveManagementView.swift) | ST | C1 | none (ModalityPicker is G2) | `… carries no DICOM-standard data (layout; the modality field is \`ModalityPicker\`, verified with G2).` | ✅ |
| [DICOMInspectorView.swift](Sources/DICOMStudio/Views/DICOMInspectorView.swift) | ST | — | to verify | — | ⏳ |
| [DataExchangeView.swift](Sources/DICOMStudio/Views/DataExchangeView.swift) | ST | C1 (+codec block) | layout; `CompressionAlgorithmHelpers` block excluded (agent codec) | `NEMA-verified: 2026a, checked 2026-10-05 — UI layout; the only standard-derived data is \`CompressionAlgorithmHelpers.algorithms\`/\`isLossy\` … not claimed here …` | ✅ (marker only; file also carries codec hunks) |
| [LibraryFilter.swift](Sources/DICOMStudio/Models/LibraryFilter.swift) | CR | — | read: filter fields and sort labels only | — | confirmed NST |
| [StudyFileCleanup.swift](Sources/DICOMStudio/Services/StudyFileCleanup.swift) | CR | — | read: file deletion bookkeeping | — | confirmed NST |
| [FileOperationsViewModel.swift](Sources/DICOMStudio/ViewModels/FileOperationsViewModel.swift) | CR | — | read: drop/output state; modality icon via helpers | — | confirmed NST |
| [FileOperationsView.swift](Sources/DICOMStudio/Views/FileOperationsView.swift) | CR | — | read: layout, "Modality" label only | — | confirmed NST |
| [ImageMetadataPanelView.swift](Sources/DICOMStudio/Views/ImageMetadataPanelView.swift) | CR | — | read: layout | — | confirmed NST |
| [ImportedShapeView.swift](Sources/DICOMStudio/Views/ImportedShapeView.swift) | CR | — | read: cites PS3.3 C.10.5 = "Graphic Annotation Module" (title confirmed in 2026a); geometry is DICOMPrintKit's | — | confirmed NST |
| [MetadataView.swift](Sources/DICOMStudio/Views/MetadataView.swift) | CR | — | read: labels "Transfer Syntax", "Character Set" (values from MetadataViewModel) | — | confirmed NST |
| [StudyBrowserView.swift](Sources/DICOMStudio/Views/StudyBrowserView.swift) | CR | — | read: layout over StudyRowSummary | — | confirmed NST |
| [DICOMTagView.swift](Sources/DICOMStudio/Components/DICOMTagView.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [ArchiveManagementService.swift](Sources/DICOMStudio/Services/ArchiveManagementService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [StorageService.swift](Sources/DICOMStudio/Services/StorageService.swift) | NST | — | grep for UIDs/tags/terms: none | — | left alone |

### G5 — Derived objects, SR and security

| File | Tier | Bucket | What it carries / what was compared | Marker | Status |
|---|---|---|---|---|---|
| [CADVisualizationHelpers.swift](Sources/DICOMStudio/Components/CADVisualizationHelpers.swift) | ST | — | to verify | — | ⏳ |
| [CalibrationHelpers.swift](Sources/DICOMStudio/Components/CalibrationHelpers.swift) | ST | — | to verify | — | ⏳ |
| [EncapsulatedDocumentHelpers.swift](Sources/DICOMStudio/Components/EncapsulatedDocumentHelpers.swift) | ST | — | to verify | — | ⏳ |
| [HangingProtocolHelpers.swift](Sources/DICOMStudio/Components/HangingProtocolHelpers.swift) | ST | — | to verify | — | ⏳ |
| [MeasurementHelpers.swift](Sources/DICOMStudio/Components/MeasurementHelpers.swift) | ST | — | to verify | — | ⏳ |
| [MeasurementPersistenceHelpers.swift](Sources/DICOMStudio/Components/MeasurementPersistenceHelpers.swift) | ST | — | to verify | — | ⏳ |
| [ParametricMapHelpers.swift](Sources/DICOMStudio/Components/ParametricMapHelpers.swift) | ST | — | to verify | — | ⏳ |
| [ROIHelpers.swift](Sources/DICOMStudio/Components/ROIHelpers.swift) | ST | — | to verify | — | ⏳ |
| [RTHelpers.swift](Sources/DICOMStudio/Components/RTHelpers.swift) | ST | — | to verify | — | ⏳ |
| [SRBuilderHelpers.swift](Sources/DICOMStudio/Components/SRBuilderHelpers.swift) | ST | — | to verify | — | ⏳ |
| [SRTreeHelpers.swift](Sources/DICOMStudio/Components/SRTreeHelpers.swift) | ST | — | to verify | — | ⏳ |
| [SecurityHelpers.swift](Sources/DICOMStudio/Components/SecurityHelpers.swift) | ST | — | to verify | — | ⏳ |
| [SegmentationHelpers.swift](Sources/DICOMStudio/Components/SegmentationHelpers.swift) | ST | — | to verify | — | ⏳ |
| [TerminologyHelpers.swift](Sources/DICOMStudio/Components/TerminologyHelpers.swift) | ST | — | to verify | — | ⏳ |
| [WaveformHelpers.swift](Sources/DICOMStudio/Components/WaveformHelpers.swift) | ST | — | to verify | — | ⏳ |
| [WholeSlideImagingHelpers.swift](Sources/DICOMStudio/Components/WholeSlideImagingHelpers.swift) | ST | — | to verify | — | ⏳ |
| [AIAnalysisModel.swift](Sources/DICOMStudio/Models/AIAnalysisModel.swift) | ST | — | to verify | — | ⏳ |
| [HangingProtocolModel.swift](Sources/DICOMStudio/Models/HangingProtocolModel.swift) | ST | — | to verify | — | ⏳ |
| [SecurityModel.swift](Sources/DICOMStudio/Models/SecurityModel.swift) | ST | — | to verify | — | ⏳ |
| [SpecializedModalityModel.swift](Sources/DICOMStudio/Models/SpecializedModalityModel.swift) | ST | — | to verify | — | ⏳ |
| [StructuredReportModel.swift](Sources/DICOMStudio/Models/StructuredReportModel.swift) | ST | — | to verify | — | ⏳ |
| [HangingProtocolService.swift](Sources/DICOMStudio/Services/HangingProtocolService.swift) | ST | — | to verify | — | ⏳ |
| [SecurityService.swift](Sources/DICOMStudio/Services/SecurityService.swift) | ST | — | to verify | — | ⏳ |
| [SpecializedModalityService.swift](Sources/DICOMStudio/Services/SpecializedModalityService.swift) | ST | — | to verify | — | ⏳ |
| [StructuredReportService.swift](Sources/DICOMStudio/Services/StructuredReportService.swift) | ST | — | to verify | — | ⏳ |
| [AIAnalysisViewModel.swift](Sources/DICOMStudio/ViewModels/AIAnalysisViewModel.swift) | ST | — | to verify | — | ⏳ |
| [HangingProtocolViewModel.swift](Sources/DICOMStudio/ViewModels/HangingProtocolViewModel.swift) | ST | — | to verify | — | ⏳ |
| [SecurityViewModel.swift](Sources/DICOMStudio/ViewModels/SecurityViewModel.swift) | ST | — | to verify | — | ⏳ |
| [SpecializedModalityViewModel.swift](Sources/DICOMStudio/ViewModels/SpecializedModalityViewModel.swift) | ST | — | to verify | — | ⏳ |
| [StructuredReportViewModel.swift](Sources/DICOMStudio/ViewModels/StructuredReportViewModel.swift) | ST | — | to verify | — | ⏳ |
| [AIAnalysisView.swift](Sources/DICOMStudio/Views/AIAnalysisView.swift) | ST | — | to verify | — | ⏳ |
| [HangingProtocolPanel.swift](Sources/DICOMStudio/Views/HangingProtocolPanel.swift) | ST | — | to verify | — | ⏳ |
| [SecurityView.swift](Sources/DICOMStudio/Views/SecurityView.swift) | ST | — | to verify | — | ⏳ |
| [PrivacySettingsView.swift](Sources/DICOMStudio/Views/Settings/PrivacySettingsView.swift) | ST | — | to verify | — | ⏳ |
| [StructuredReportView.swift](Sources/DICOMStudio/Views/StructuredReportView.swift) | ST | — | to verify | — | ⏳ |
| [WaveformChartView.swift](Sources/DICOMStudio/Views/WaveformChartView.swift) | ST | — | to verify | — | ⏳ |
| [MeasurementModel.swift](Sources/DICOMStudio/Models/MeasurementModel.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [ROIModel.swift](Sources/DICOMStudio/Models/ROIModel.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [AIAnalysisService.swift](Sources/DICOMStudio/Services/AIAnalysisService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [CalibrationService.swift](Sources/DICOMStudio/Services/CalibrationService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [MeasurementService.swift](Sources/DICOMStudio/Services/MeasurementService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [MeasurementViewModel.swift](Sources/DICOMStudio/ViewModels/MeasurementViewModel.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |

### G6 — Print

| File | Tier | Bucket | What it carries / what was compared | Marker | Status |
|---|---|---|---|---|---|
| [PrinterStatusPresentation.swift](Sources/DICOMStudio/Components/PrinterStatusPresentation.swift) | ST | — | to verify | — | ⏳ |
| [PrinterProfile.swift](Sources/DICOMStudio/Models/PrinterProfile.swift) | ST | — | to verify | — | ⏳ |
| [PrintCellTextureCache.swift](Sources/DICOMStudio/Services/PrintCellTextureCache.swift) | ST | — | to verify | — | ⏳ |
| [PrintService.swift](Sources/DICOMStudio/Services/PrintService.swift) | ST | — | to verify | — | ⏳ |
| [PrintSCPViewModel.swift](Sources/DICOMStudio/ViewModels/PrintSCPViewModel.swift) | ST | — | to verify | — | ⏳ |
| [PrintViewModel+CellEditing.swift](Sources/DICOMStudio/ViewModels/PrintViewModel+CellEditing.swift) | ST | — | to verify | — | ⏳ |
| [PrintViewModel+PresentationStates.swift](Sources/DICOMStudio/ViewModels/PrintViewModel+PresentationStates.swift) | ST | — | to verify | — | ⏳ |
| [PrintViewModel.swift](Sources/DICOMStudio/ViewModels/PrintViewModel.swift) | ST | — | to verify | — | ⏳ |
| [FilmPreviewView.swift](Sources/DICOMStudio/Views/Print/FilmPreviewView.swift) | ST | — | to verify | — | ⏳ |
| [PrintSCPView.swift](Sources/DICOMStudio/Views/Print/PrintSCPView.swift) | ST | — | to verify | — | ⏳ |
| [PrintSettingsView.swift](Sources/DICOMStudio/Views/Print/PrintSettingsView.swift) | ST | — | to verify | — | ⏳ |
| [PrintSCPModel.swift](Sources/DICOMStudio/Models/PrintSCPModel.swift) | CR | — | confirm-read pending | — | ⏳ |
| [PrintSelectionModel.swift](Sources/DICOMStudio/Models/PrintSelectionModel.swift) | CR | — | confirm-read pending | — | ⏳ |
| [PrintImageNumberCache.swift](Sources/DICOMStudio/Services/PrintImageNumberCache.swift) | CR | — | confirm-read pending | — | ⏳ |
| [PrintQueueService.swift](Sources/DICOMStudio/Services/PrintQueueService.swift) | CR | — | confirm-read pending | — | ⏳ |
| [PrintSCPSettingsStorageService.swift](Sources/DICOMStudio/Services/PrintSCPSettingsStorageService.swift) | CR | — | confirm-read pending | — | ⏳ |
| [PrintThumbnailCache.swift](Sources/DICOMStudio/Services/PrintThumbnailCache.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ImageViewerViewModel+Print.swift](Sources/DICOMStudio/ViewModels/ImageViewerViewModel+Print.swift) | CR | — | confirm-read pending | — | ⏳ |
| [PrintViewModel+CellSync.swift](Sources/DICOMStudio/ViewModels/PrintViewModel+CellSync.swift) | CR | — | confirm-read pending | — | ⏳ |
| [FilmLayoutGalleryView.swift](Sources/DICOMStudio/Views/Print/FilmLayoutGalleryView.swift) | CR | — | confirm-read pending | — | ⏳ |
| [PrintCenterView.swift](Sources/DICOMStudio/Views/Print/PrintCenterView.swift) | CR | — | confirm-read pending | — | ⏳ |
| [PrintProgressView.swift](Sources/DICOMStudio/Views/Print/PrintProgressView.swift) | CR | — | confirm-read pending | — | ⏳ |
| [PrintAuditEvent.swift](Sources/DICOMStudio/Models/PrintAuditEvent.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [PrintJobHistoryEntry.swift](Sources/DICOMStudio/Models/PrintJobHistoryEntry.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [PrintSelectionModel+Annotations.swift](Sources/DICOMStudio/Models/PrintSelectionModel+Annotations.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [PrintQueueStorageService.swift](Sources/DICOMStudio/Services/PrintQueueStorageService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [PrintReportPDF.swift](Sources/DICOMStudio/Services/PrintReportPDF.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [PrinterProfileStorageService.swift](Sources/DICOMStudio/Services/PrinterProfileStorageService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [PrinterStatusMonitor.swift](Sources/DICOMStudio/Services/PrinterStatusMonitor.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [PrintViewModel+Annotations.swift](Sources/DICOMStudio/ViewModels/PrintViewModel+Annotations.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [PrintViewModel+CellSelection.swift](Sources/DICOMStudio/ViewModels/PrintViewModel+CellSelection.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [PrintViewModel+ImageRange.swift](Sources/DICOMStudio/ViewModels/PrintViewModel+ImageRange.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [AuditTrailView.swift](Sources/DICOMStudio/Views/Print/AuditTrailView.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [FilmCellAnnotationLayer.swift](Sources/DICOMStudio/Views/Print/FilmCellAnnotationLayer.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [PrintOverlayColor+SwiftUI.swift](Sources/DICOMStudio/Views/Print/PrintOverlayColor+SwiftUI.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [PrintQueueView.swift](Sources/DICOMStudio/Views/Print/PrintQueueView.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [PrintSCPWindow.swift](Sources/DICOMStudio/Views/Print/PrintSCPWindow.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [PrinterManagementView.swift](Sources/DICOMStudio/Views/Print/PrinterManagementView.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [ViewerPrintTrayView.swift](Sources/DICOMStudio/Views/ViewerPrintTrayView.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |

---

## Verification notes

- The scan that produced the tiers is a script over regexes for UID roots, tag literals, PS3 citations, VR names,
  CID / TID / DCM codes, transfer-syntax and SOP names, photometric terms, DIMSE and status words, DICOMweb terms,
  DICOMDIR and media profiles, PS3.15 terms, `--option` strings, print, presentation-state, SR and derived-object
  terms and CS defined terms. A file with no hit and a pure UI / cache / storage / view-model role is NST; the
  classification is corrected during the pass whenever a reviewer finds otherwise (the log records every promotion).
- Nothing in this report is claimed from memory; every row names the table or section it was compared with.
