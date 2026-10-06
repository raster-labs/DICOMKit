# DICOMStudio — DICOM Standard Implementation Report

Generated 2026-10-05, last updated 2026-10-06. Covers all 334 Swift files in `Sources/DICOMStudio/` (333) and `Sources/DICOMStudioApp/` (1):
the macOS SwiftUI application over DICOMKit — the CLI Workshop (forms, executors and command previews for 29 of the
42 `dicom-*` tools), the image viewer and its PS3.4 N.2 display pipeline, presentation states, DIMSE and DICOMweb
panels, the print composer and Print SCP, DICOMDIR and media exchange, structured reports, anonymization and the
derived-object helpers. (The earlier status row said 335 files; `cb5090f2` moved `@main` to the DICOMStudioApp target
and deleted the old `App/DICOMStudioApp.swift`, so 334 is the closing count.)

**Status: complete (pending the owner's decisions).** Verified 2026-10-05 / 06. Every one of the 334 files is in a group and
a tier: the 170 standard-touching files carry a `NEMA-verified` marker and the 164 not-standard-touching files are
inventoried (`check_nema_markers.py --inventory` exits 0 on both targets). Every data table, term set and Workshop form
the module carries was diffed by script against the frozen 2026a DocBook and the CLI contract:
[Scripts/diff_studio.py](Scripts/diff_studio.py) with its six group modules — **206 checks ok, 0 failing, 13 pending
the owner** (the P-items below). All 17 inherited rows are closed (the DICOMKit half of D237 on 2026-10-06, `7a3aac80`, after the owner approved P-VIDEO-CONTAINER);
D242–D275 were opened for other modules and closed on 2026-10-06 except D256 (left open by owner decision; D244, D246 void). The CLI Workshop mirrors the 29 tools the UI offers (33 Workshop tool ids)
option for option, default for default and output line for output line (section 5). Full `swift test` exit 0 on
2026-10-06: XCTest 5,819 executed / 44 skipped / 0 failures (baseline 5,798 / 44); Swift Testing 9,252
passed, 0 failures (baseline 9,083). Open for the owner: the 14 P-STUDIO-* items, unchanged by the 2026-10-06 follow-up (public API: new enum cases, raw-value changes,
deprecations) and the parity-driven behaviour changes listed before the Deferred findings. Method:
[DICOMCORE_STANDARD_IMPLEMENTATION.md → Verification method](DICOMCORE_STANDARD_IMPLEMENTATION.md#verification-method-reuse-for-every-module),
used unchanged. Package target: **DICOM 2026a** (`dicomStandardEdition = "2026a"`,
[DICOMKit.swift](Sources/DICOMKit/DICOMKit.swift)). Markers checked with
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
| G1 CLI Workshop | 20 | 2 | 15 | 37 | ✅ 2026-10-05 (file tools `2f730cac`, shell `6b57be6c`…`86aae0ee`, network `a2a828c2`…`7af3cce0`, pixel `38a2eea0`, markers `5678fa8e`; `diff_studio.py --group G1`: 67 ok, 0 FAIL, 2 PEND) |
| G2 Viewer and rendering | 52 | 31 | 54 | 137 | ✅ 2026-10-05 (viewer `6372e096`…`adf75ca6`, codec `1b0588eb`…`aaa81726`; `diff_studio.py --group G2`: 0 FAIL, 1 PEND P-STUDIO-ANNOTATION-UNITS; `PatientOverlayText.swift` promoted CR → ST) |
| G3 Network and web | 19 | 5 | 13 | 37 | ✅ 2026-10-05 (DIMSE / print model `6ab02140`…`fa11dbd0`; DICOMweb `abce7d7e`…`104c0052`; `diff_studio.py --group G3`: 36 ok, 0 FAIL, 4 PEND) |
| G4 File, media and DICOMDIR | 31 | 8 | 3 | 42 | ✅ 2026-10-05 (markers `b0eca043`, checks `f02ee47a`, fixes `e6c2a11a`…`1793c091`; `diff_studio.py --group G4`: 22 ok, 0 FAIL; two files share hunks with the codec pass) |
| G5 Derived objects, SR and security | 36 | 0 | 6 | 42 | ✅ 2026-10-05 (`32929df7`…`c87e60dd`; `diff_studio.py --group G5`: 11 checks, 0 FAIL, 6 PEND — seven P-STUDIO-* items) |
| G6 Print | 11 | 11 | 17 | 39 | ✅ 2026-10-05 (`77d47fd1`; `diff_studio.py --group G6`: 0 FAIL; DICOMPrintKit finding: `PrintOptionCatalog.filmDestinations` stops at BIN_2) |
| **All** | **170** | **56** | **108** | **334** | ✅ 2026-10-06 (`PatientOverlayText` promoted CR → ST; JP3DMPRViewModel promoted and marked within G2's 52) |

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
| 2026-10-05 | D22 — NetworkingModel print enums | PS3.3 2026a C.13.1 (Print Priority Enumerated Values 3/3; Medium Type Defined Terms: PAPER, CLEAR FILM match, BLU-RAY → BLUE FILM, 2 MAMMO terms not offered), C.13.3 (Film Size ID 12/12; Image Display Format STANDARD\C,R 8/8 columns-first), C.13.8 (Execution Status: COMPLETED → DONE, FAILED → FAILURE), C.4.14 (IN_PROGRESS → IN PROGRESS), PS3.4 Table C.6.1-1 (4/4) | `6ab02140` — raw values corrected; NetworkingViewModel passes `PrintLayout(rows:columns:)` to `DICOMPrintService.printImages(layout:)` (the layout was dropped before); markers on NetworkingModel/ViewModel/View/Service | NetworkingModelTests +6 |
| 2026-10-05 | G3 AE Title rule, ports | PS3.5 2026a Table 6.2-1 VR AE (16 bytes, Default Character Repertoire without 5CH and control chars, not solely spaces); PS3.8 Table 9-11; PS3.8 9.1.1 (104 well-known, 11112 registered); PS3.15 B.12 ("2762 dicom-tls") | `956bee08` — AETitleHelpers / ServerValidationHelpers delegate to DICOMNetwork.AETitle (former uppercase-only and alphanumerics+" _-" rules refused ANY-SCP / orthanc, admitted CAFÉ; normalize() no longer upper-cases); PortHelpers labels 104 / 11112 as the clause does; `wellKnownDICOMPort` added | NetworkingHelpersTests (+4, 1 fixture fixed), ShellServerConfigHelpersTests (new, 4) |
| 2026-10-05 | G3 PerformanceToolsHelpers | PS3.5 Table 6.2-1 (34 VR names), PS3.6 Table 6-1 (15 sample tags: name, keyword, VR, VM, not retired), PS3.6 Table A-1 (41 UID rows: name beside UID) | `5e557fc5` — OB/OD/OF/OW "Other … String" → Table names; UI/UR verbatim incl. abbreviation; Study Root Q/R names were paired with Patient Root UIDs .2.1.x → .2.2.x, Patient Root rows added (Workshop uses both); UPS Event, PET/US/SC, JPEG names as A-1; "Retired in DICOM 2014" → "Retired (PS3.6 Table A-1)" (not datable from text); conformance note clauses C.4.2 / C.4.3 / PS3.7 9.1.5 / PS3.18 10.4 | PerformanceToolsHelpersTests +3 (+2 pins updated) |
| 2026-10-05 | G3 markers (no data) | — | `f5b9746f` — PolishReleaseModel, PolishReleaseHelpers, CloudIntegrationModel | — |
| 2026-10-05 | G6 Print files | PS3.3 2026a C.13.1 Film Destination (MAGAZINE / PROCESSOR / BIN_i, no maximum), C.13.3 (Border / Empty Image Density BLACK, WHITE, i; Image Display Format forms), C.13.5 (Polarity; Bits Stored 8/12 in Table C.13-5), C.13.8 (Execution Status), C.13.9 + Table C.13.9.1-1 (Printer Status, Status Info: SUPPLY LOW / SUPPLY EMPTY / NORMAL), PS3.6 Table 6-1 (13 attribute labels, 3 tag reads) | `77d47fd1` — PrintSettingsView film-destination picker: Magazine / Processor / Sorter bin + number field via `FilmDestination.bin(n)` (catalogue stops at BIN_2); Bits Stored help cites Table C.13-5 (was C.13-3); PrintSCPView labels "Film Size" / "Magnification" → "Film Size ID" / "Magnification Type"; markers on 11 ST files | PrintFilmDestinationPickerTests (new, 5), PrintSCPScreenTests (1 label pin) |
| 2026-10-05 | D10, D11 — photometric sets | PS3.3 2026a C.7.6.3.1.2 (14 terms; HSV/ARGB/CMYK "Retired. See PS3.3-2001") | ThumbnailHelpers set built from DICOMCore (7 → 11 terms); ImageMetadataHelpers XYB label (1b0588eb) | ThumbnailHelpersTests, ImageMetadataHelpersTests |
| 2026-10-05 | D9 — transfer-syntax names | PS3.6 2026a Table A-1 (63 Transfer Syntax rows) | ImportValidation 16 comment names, FileOperationsHelpers 13, J2KTestBenchModels 5 (".4.110 JPEG XL Lossless Only" → "JPEG XL Lossless"); ImageMetadataHelpers 29-row hand table → DICOMCore shortName + new transferSyntaxStandardName (A-1 name as overlay tooltip); DataExchangeView CompressionAlgorithmHelpers rows all resolved through TransferSyntax.parseEncoding (jpeg-lossless labelled .4.70 → .4.57; j2k-lossless ".90" → reversible .91; htj2k-lossless → reversible .203); CodecInspectorViewModel description → displayName; CodecInspectorHelpers names JPEG XL / video / Deflated Image Frame / Encapsulated Uncompressed (1bbc18a8) | ImportValidationTests, FileOperationsHelpersTests, J2KTestBenchPart2Tests, ImageMetadataHelpersTests, CompressionAlgorithmHelpersTests, CodecInspectorHelpers/ViewModel |
| 2026-10-05 | D237 Studio half + viewer non-image content | PS3.6 2026a Table A-1 SOP Class arcs; PS3.4 Table B.5-1; PS3.3 Table C.17.3-7; PS3.6 Table 6-1 | ViewerNonImageContentView: exhaustive switch over DICOMKit VideoContainer removed, uses ExtractedVideo.containerDisplayName; SR narrative TABLE branch; ViewerContentKind arcs closed with "." (…1.1.9 also matched Content Assessment Results / Microscopy Bulk Simple Annotations; …1.1.11 matched Standalone VOI LUT) and Waveform Presentation States (…9.100.x) classed as presentation states (88c271c6) | ViewerContentKindTests (+ StructuredReportNarrativeValueTests) |
| 2026-10-05 | Viewer annotations | PS3.3 2026a C.7.6.2.1.1, C.7.6.1.1.1; PS3.5 A.4.11 | orientation letters S/I → H/F (Patient Orientation abbreviations); compressionLine lists Encapsulated Uncompressed .1.98 as "Uncompressed" (ba701ab5) | ViewerAnnotationTextTests |
| 2026-10-05 | JP3D / MPR / volume / blending | PS3.3 2026a C.11.2.1.2.1, C.11.14, C.7.6.2, C.18.9 | JP3DMPRSliceExtractor.applyWindowLevel → exact default LINEAR function; BlendingHelpers citation C.11.11 → C.11.14 (97704093) | JP3DMPRWindowLevelTests |
| 2026-10-05 | J2K bench | PS3.6 2026a Table A-1 | J2KBenchSyntax.isLossless default from the registry (JPEG Baseline / JPEG-LS Near-Lossless were "lossless" under the UID-suffix guess) (1bbc18a8) | J2KTestBenchPart2Tests |
| 2026-10-05 | markers | — | 27 files marked (aaa81726) | — |
| 2026-10-05 | D65 / D68 viewer chain | PS3.4 2026a N.2, N.2.1.1, N.2.1.3, N.2.1.4; PS3.3 C.11.1, C.11.2 (Table C.11-2b: window or VOI LUT Sequence, 1C each), C.11.2.1.2.1 (window "after any Modality LUT or Rescale Slope and Intercept"), C.11.6, C.11.15.1.1, C.7.6.3.1.2 | `ImageViewerViewModel.displayModalityLUT / displayWindow / displayVOI / displayICCProfile / displayRenderRequest`; `FrameRenderer.resolvedPipeline / request` (stored-unit window → c·m+b, w·\|m\| → `DICOMImageExporter.determineDisplayPipeline`); `ImageRenderingService.renderFrame` and `ImageDecodingService.decodeProgressively` through `renderFrameForExport`; progressive decode given `displayWindow` (was stored units) — `6372e096` | ViewerDisplayPipelineTests (slope 2, slope −1, dragged window, tiles, ImageRenderingService) |
| 2026-10-05 | D42 | PS3.4 N.2 / N.2.1.4 (Photometric Interpretation ignored under a state); PS3.3 A.33.1.1, Table A.33.2-1; C.11.1.1.2 | `ImageToSave(photometricInterpretation:, rescaleType:)`, `ViewerPresentationStateBridge.capture/restore(photometricInterpretation:)` at all 5 viewer sites and the print cell restore (`FrameRenderer.photometricInterpretation(path:)`) — `6372e096` | ViewerDisplayPipelineTests (MONOCHROME1 save INVERSE / restore upright, colour → CSPS 1.2.840.10008.5.1.4.1.1.11.2, Rescale Type HU in the state's Modality LUT) |
| 2026-10-05 | D28 | PS3.4 N.2.1.1 ("If the Modality LUT is not present in the Presentation State it shall be assumed to be an identity transformation. Any Modality LUT … in the Image shall not be used"); PS3.5 Table 6.2-1 | a state without a Modality LUT is the identity (`modalityLUTSource = .presentationState(nil)`), S-2 migration rule for this app's own pre-2026-09-29 objects (not imported, no Modality LUT → the image's rescale, which is the units they were written in); the image's LUT returns when a tool moves; inspector binary-VR set + OV — `6372e096` | ViewerDisplayPipelineTests (adopted PR identity, own legacy PR migrates, PR Modality LUT replaces image's, OV + 6 VRs shown as bytes) |
| 2026-10-05 | PresentationStateHelpers LINEAR | PS3.3 C.11.2.1.2.1 pseudo-code (3 lines), "w ≥ 1", w = 1 threshold | upper threshold was `c + w/2` (text: `c − 0.5 + (w−1)/2`): outputs > 1 at the top edge and ÷0 at w = 1 — corrected to the pseudo-code verbatim; LINEAR_EXACT and SIGMOID confirmed — `40c1acc6` | PresentationStateHelpersTests +2 (thresholds incl. the standard's c=2048/w=4096 example; w=1 threshold) |
| 2026-10-05 | PresentationStateHelpers.transformPoint | PS3.3 Table C.10-6 (Image Rotation "before any Image Horizontal Flip"; flip "after any Image Rotation") | flip was applied before the rotation — corrected (rotate, then mirror about the rotated width) — `40c1acc6` | PresentationStateHelpersTests +1 (rotate90FlipH, rotate270FlipH on 512×256) |
| 2026-10-05 | PresentationStateModel | C.11.6 (2 shapes), C.10.4 (3 size modes), C.11.1.1.2 (9 Rescale Type terms), PS3.6 Table B.1-1 (8 palettes), A.33.1–A.33.4 | `ModalityLUTTransform.rescaleType` default HU → US; IOD citations C.11.1/C.11.9/C.11.10/C.11.11 → A.33.1/2/3/4 and PS3.6 Annex B — `40c1acc6` | PresentationStateModelTests (default → US) |
| 2026-10-05 | Shutters | PS3.3 C.7.6.11 (3 shapes; "the least amount of image remaining shall be visible"; Shutter Presentation Value P-Values), C.7.6.15 (BITMAP); PS3.5 7.6 (even groups 6000–601E) | `ShutterCutoutShape` cut the union of the shapes → intersection; `BitmapShutter.isValid` accepted odd groups → even only — `6d8cea16` | ShutterHelpersTests +2 (intersection vs `isPixelVisible`), ShutterModelTests +1 |
| 2026-10-05 | ImageViewerViewModel.isWaveformFile | PS3.6 Table A-1 arc 1.2.840.10008.5.1.4.1.1.9.* (21 UIDs: 19 "… Waveform Storage", 2 ".9.100.*" Waveform Presentation State Storage) | the two presentation-state classes were classified as waveform files — arc narrowed — `6372e096` | script check (private func; the parse fallback masked it) |
| 2026-10-05 | markers on 24 C1/C2 files | per-file (see inventory) | markers only — `79cb70d9` | — |
| 2026-10-05 | Scripts/diff_studio_g2_viewer.py | C.7.6.11, C.7.6.15, C.11.2, C.11.6, C.11.1.1.2, C.10.4, C.10.5, C.10.6 / Table C.10-6, C.11.2.1.2.1, C.11.2.1.3.2, PS3.5 6.2-1, PS3.6 6-1, A-1, B.1-1, C.7.6.3.1.2, C.7.3.1.1.1 | new module, 19 checks (18 ok, 1 PEND) — `adf75ca6` | — |
| 2026-10-05 | D88 fixtures | PS3.16 2026a CID 9300 (includes CID 9301), Table D-1 rows 110500 / 110501 / 110513 / 110514 dumped by script | fixtures use (110513, "Discontinued for unspecified reason"), (110501, "Equipment failure") (`32929df7`) | NetworkToolWorkshopCLIParityTests |
| 2026-10-05 | SRBuilderHelpers coded concepts | PS3.16 2026a Table D-1 (17 DCM codes), CID 7003 / 7010 / 7021 / 7000 / 7001 / 7181 / 7461 / 83 / 7460, Table O-1 (G-C0E3 → 363698007), TID 1500 / 1501 / 2000 / 2010 rows | 13 concepts: 7 matched, 6 corrected (G-C0E3→SCT, 121200, 113000, mm2, [hnsf'U], 1); document titles from CID 7000/7021/7010 + TID 4000/4100 instead of retired 121070; 13 CID 7001 headings; TID 1500 row 6 container; TID 2010 IMAGE items without concept name; 99DCMSTUDIO private scheme for headings without a code (`275bdc0e`) | SRBuilderHelpersTests +5 |
| 2026-10-05 | TerminologyHelpers | every PS3.16 2026a CID table (dk.cid_index), Table 8-1 | 77 entries: SCT 3 ids corrected (816092008 "Pelvis"→10200004 Liver; 51185008→816094009 Chest; 129748003→27925004 Nodule), 9 LN meanings → CID 7000/7001 meanings, UCUM m → "m"; DCM / SRT names per Table 8-1; 37 codes in no CID table (RADLEX 18, SCT 6, LN 5, UCUM 4) left as external (`275bdc0e`) | TerminologyHelpersTests +1 |
| 2026-10-05 | StructuredReportModel | PS3.6 A-1 (8 UIDs), PS3.3 Tables C.17.3-7 / C.17.3-8, C.18.8-1, C.18.6.1.2, C.18.9.1.2, C.18.7.1.1, PS3.16 Table 8-1 | DCM display name → "DICOM Controlled Terminology"; 15/16 value types (TABLE), 7/7 relationships, 2/2 continuity, SCOORD 5 + POLYGON, SCOORD3D 6/6, TCOORD 6/6 (`7599d9bd`) | StructuredReportModelTests |
| 2026-10-05 | ROIHelpers / MeasurementPersistenceHelpers / CalibrationHelpers / MeasurementHelpers | PS3.16 CID 7461 / 7460 / 7183 / 7470 / 7471 / 7464 / 3488, Table D-1; PS3.6 Table 6-1 (4 tags); PS3.3 10.7.1.1 / 10.7.1.3 titles | area text "250.0 mm2 (mm²)" (CLI hand-over); 8 persistence concepts 7 match + Angle external; calibration citations corrected (`8aaa8654`) | ROIHelpersTests (3 pins) |
| 2026-10-05 | WaveformHelpers | PS3.6 2026a Table A-1 (16 current Waveform Storage rows under .9.) | table-driven names (A-1 name minus " Waveform Storage"): 16/16, was 9 with 3 wrong abbreviations (`a2f749c9`) | WaveformHelpersTests (+1 pin over 16 rows, 1 expectation → A-1 name) |
| 2026-10-05 | SpecializedModalityModel + SEG / RT / PM / WSI / Encapsulated / CAD helpers | PS3.3 Tables C.8-44, C.8-39, C.8-50, C.8.20-4, C.8.20-2; A.45.1.4.1 / A.45.2.4 / A.85.1-A.85.3 MIME terms; PS3.6 A-1 (5 SC UIDs); section titles C.8.32, C.8.8.5, A.85 | CDA MIME "text/xml" → "text/XML"; RTRadiationType 4/4; SegmentAlgorithmType 3/3; RTROIType 6/25 + OTHER and RTDoseUnits (PEND); 3 citations corrected (`16a5a78c`) | SpecializedModalityModelTests, EncapsulatedDocumentHelpersTests, RTHelpersTests, SegmentationHelpersTests, ParametricMapHelpersTests, WholeSlideImagingHelpersTests |
| 2026-10-05 | HangingProtocol*, AIAnalysis*, PrivacySettingsView | PS3.3 Table C.23.3-1 Sorting Direction, C.7.3.1.1.1 Modality (4 values) | markers; ImageSortDirection 0/2 (PEND); PS3.17 Annex U citation removed (`b0137a3d`) | HangingProtocolHelpersTests, HangingProtocolModelTests |
| 2026-10-05 | Security UI | PS3.15 2026a B.12 ("shall support TLS 1.2", RFC 8996), B.13 cipher suites, B.1-B.3 / B.9-B.11 "Retired"; DICOMKit Anonymizer.swift basic (14) / clinicalTrial (+8) tag sets; PS3.6 Table 6-1 names | preview lists = engine lists (18-tag "HIPAA" list had 7 tags in common with what ran); descriptions state engine counts; development minimum TLS 1.0 → 1.2; A.5 audit citation (`93553fa4`) | SecurityHelpersTests (+1), SecurityModelTests (+2), SecurityViewModelTests |
| 2026-10-05 | Scripts/diff_studio_g5.py | all of the above | new check module, 11 checks (`c87e60dd`) | — |
| 2026-10-05 | Draft of attempt 1 verified and kept (json, xml, uid, split, merge, validate, dump, tags, diff, info arms + executors) | PS3.18 F.2.2 / F.2.5, PS3.19 Table A.1.5-2, PS3.5 9.1 / B.2 / 7.1.1, PS3.6 Table A-1, PS3.3 C.7.6.16.1.2, PS3.10 Table 7.1-1 | parity ok for all 10; exit codes aligned to ArgumentParser (64 usage) — 2f730cac | CLIWorkshopHelpersTests, CLIWorkshopViewModelTests, SplitMergeWorkshopCLIParityTests |
| 2026-10-05 | dicom-dcmdir: --profile picker = DICOMDIRProfile.allStandard, File-set ID default / refusal, --copy-to, validate rules, exit codes (D29, D132) | PS3.11 2026a Tables A.1-1 … N.1-1 (58 fixed identifiers: 58 matched, 0 wrong); PS3.10 8.1 (0-16 chars), 8.2 (1-8 × 1-8), 8.5 (A-Z 0-9 _), 8.6; PS3.3 Tables F.3-2, F.3-3, F.4-1 | 2f730cac | dcmdirProfilePickerIsPS311, dcmdirCreateForm, fileSetRules, profileDeprecationNote; diff_studio_g1 × 2 |
| 2026-10-05 | dicom-archive: query --strict-modality, CLI help texts, ModalityOptionValidator / study-date warning in the executor, ArchiveError exit 64 | PS3.3 C.7.3.1.1.1; PS3.4 C.2.2.2.2 / C.2.2.2.4 / C.2.2.2.5.1; PS3.5 Table 6.2-1 DA | 2f730cac | archiveQueryKeys, archiveStudyDateWarning; diff_studio_g1 |
| 2026-10-05 | dicom-study: --copy default false, CLI help (keyword keys, deprecated keys), usage errors exit 64 | PS3.4 Tables C.6-2 / C.6-3 (0020,1206), (0020,1209); PS3.6 Table 6-1 keywords | 2f730cac | studyDefaults |
| 2026-10-05 | dicom-export: --frame-number / --start-frame-number / --end-frame-number, deprecated 0-based options with notes + exit-1 conflict, --fps default = file rate, shared render for contact-sheet / animate, buildOrganizedPath(patientID:issuerOfPatientID:), --apply-window deprecated on contact-sheet / bulk, Burned In Annotation warnings (D127) | PS3.3 Table 10-3, Table C.7-13 (3 attributes; names / tags match PS3.6 Table 6-1), Table C.7-9 (0028,0301), Table C.7-1 (0010,0020) / (0010,0021); PS3.4 N.2 | 2f730cac | exportFrameNumbers, exportFPSDefaultIsTheFileRate, exportApplyWindowDeprecation, exportPickers, exportCineFrameRate, exportTexts; WorkshopDicomImageOutputScopeTests; diff_studio_g1 |
| 2026-10-05 | dicom-split: SplitMergeWorkshopCLIParityTests — framesDeprecatedLine filter removed, 6 --frame-numbers / conflict cases added (D154) | PS3.3 C.7.6.16.1.2 | 2f730cac | SplitMergeWorkshopCLIParityTests (32 split × verbose on/off, merge matrix × 2: pass) |
| 2026-10-05 | ValidationModel / ViewModel / View: 5 IOD keywords corrected (Multiframe… → MultiFrame…), level texts = dicom-validate --level help, refusal text | PS3.6 2026a Table A-1 UID Keywords (30 checked: 25 matched, 5 wrong → fixed) | 97fa6e6f | validationHelpersIODKeywordsAndLevels; diff_studio_g1 "validation panel" |
| 2026-10-05 | Markers: CLIWorkshopModel, CLIWorkshopService, CLIToolBuilder, CLIToolTerminalCompare (no standard data) | grep for tags / UIDs / STD-* / VR / PS3 clauses: none | 8f3d8daa | — |
| 2026-10-05 | QIDO query building (DICOMwebClientFactory) | PS3.18 2026a Table 10.6.1-5 (study: Modalities in Study (0008,0061); series/instance: Modality (0008,0060)), Table 8.3.4-1 + 8.3.4.2 (fuzzymatching absent = false), 8.3.4.4 (limit, offset), PS3.4 2026a C.2.2.2.5 (open date ranges) | study-level modality key corrected (sent (0008,0060) at every level); fuzzymatching toggle now sent; to-only Study Date sent as `-YYYYMMDD` (was dropped) — `abce7d7e` | DICOMwebClientFactoryTests +5 pins; modality test expectation moved to (0008,0061) |
| 2026-10-05 | JPIP panel text (DICOMwebView) | PS3.6 2026a Table A-1 (4 JPIP transfer syntaxes .94/.95/.204/.205), Table 6-1 (0028,7FE0) Pixel Data Provider URL, PS3.5 2026a A.6 | uri panel said "(0008,1190) RETRIEVE URL" → Pixel Data Provider URL (0028,7FE0); header lists 4 UIDs (was 2) — `9de48296` | text only; script check 4/4, 1/1 |
| 2026-10-05 | UPS state machine (DICOMwebModel, DICOMwebHelpers, DICOMwebViewModel) | PS3.4 2026a Table CC.1.1-2 (Change State rows), Table CC.2.1-2 (status codes), PS3.3 2026a C.30.1 (4 terms), C.30.2 (3 priorities), PS3.18 2026a 11.7.1.4 | `scheduled.allowedTransitions` = [.inProgress] (SCHEDULED→CANCELED removed, C310H); SCHEDULED target refused with the dicom-wado message; refusals name CC.2.1-2 codes; displayName "Canceled"; internal `dicomTerm` — `53faaa9d` | DICOMwebModelTests +6, DICOMwebHelpersTests +4, DICOMwebViewModelTests +3 |
| 2026-10-05 | UPS event payload parser (DICOMwebHelpers) | PS3.4 2026a Table CC.2.4-1 (Event Report attributes per Event Type ID), PS3.6 Table 6-1 (11 tags) | progress read inside (0074,1002); Contact Display Name (0074,100C) top-level / inside (0074,1008); Human Performer Code Sequence (0040,4009) meaning for Assigned; bare-name keys kept as fallbacks — `53faaa9d` | DICOMwebHelpersTests +5 |
| 2026-10-05 | QIDO level sync, frames resource (DICOMwebViewModel) | PS3.18 Table 10.6.1-5 (key by level), Table 10.4.1.6-1 (Frame Pixel Data `/frames/{frames}`), PS3.3 Table 10-3 (1-based) | level picker copied into query params before building; frames jobs with a frame list call `retrieveFrames` — `53faaa9d` | covered by factory pins; frames path has no network test (see open items) |
| 2026-10-05 | Doc-comment citations (DICOMwebModel) | PS3.18 2026a section titles (8.11, 10.6.3, Ch. 9, 11.10, 11.13, Table 8.3.4-1, Table 10.5.3-1) | 11 wrong clause numbers corrected (docs) — `53faaa9d` | — |
| 2026-10-05 | Check module | all of the above | `Scripts/diff_studio_g3_web.py` — `104c0052` | 0 FAIL, 2 PEND |
| 2026-10-05 | CLIShellFoundationModel / CLIShellFoundationHelpers tool catalogue | Sources/dicom-* targets (42); PS3.7 2026a 9.1.1–9.1.5 service titles (C-STORE, C-FIND, C-GET, C-MOVE, C-ECHO); PS3.18 2026a WADO-RS / QIDO-RS / STOW-RS / UPS-RS; PS3.4 2026a Annex K (Modality Worklist), F.7 (MPPS SOP Class) | 38 → 42 tools: dicom-j2k, dicom-jpip, dicom-printscp, dicom-video added to ToolCategory.toolNames / allToolNames / totalToolCount / toolDescription / toolDisplayName; dicom-tags ("Tag dictionary lookup" → "Add, modify, and delete tags in DICOM files"), dicom-image ("Image extraction" → "Convert standard images to DICOM Secondary Capture"), dicom-wado ("Web Access to DICOM Objects (WADO)" → "DICOMweb client (WADO-RS, QIDO-RS, STOW-RS, UPS-RS)") corrected to the tools' abstracts (85d0a75c) | CLIShellCatalogueTests |
| 2026-10-05 | BrowserNavigationHelpers dicomStandardReference | 15 citations vs 2026a section ids/titles: PS3.7 9.1.5 C-ECHO Service; PS3.4 C.4 DIMSE-C Service Groups, B.2 Behavior, K.6 SOP Class Definitions, F.7 MPPS SOP Class, H.4 Print Management SOP Class Definitions; PS3.7 7.1 Service Types; PS3.3 C.17 SR Document Modules, C.18 Content Macros, C.7 Common Composite IOD Modules; PS3.15; PS3.10 | 14 exist; "PS3.18 §6.5" does not exist in PS3.18 2026a (chapter 6 has no subsections) → "PS3.18 §10" Studies Service and Resources (85d0a75c) | CLIShellCatalogueTests |
| 2026-10-05 | ParameterBuilderHelpers catalogue (12 tools) | diff_cli.extract_options surfaces of dicom-info, -diff, -convert, -anon, -compress, -echo, -query, -send, -retrieve, -uid, -image, -json; QueryLevelOption, RetrievalMethod, PriorityOption, ExportFormat, OutputFormat enums; AnonCLI.profileAliases / defaultProfile; CompressionManager.codecMap; CompressionConsole.parseQuality; PS3.8 2026a 9.1.1 (port 11112); PS3.5 2026a Table 6.2-1 (AE 16 bytes) | 59 old rows: 29 not options of the named tool (positional args spelled --input/--host/--file-a/--file-b/--uid; --calling-aet for --aet; --output-format for --format; --output-dir for --output; --pretty-print for --pretty; dicom-image given dicom-convert's --format/--frame-start/--frame-end; --tls; --verbose on dicom-info), 3 pickers with refused values (--profile standard/full; --codec jpeg-baseline ok but rle-lossless no; --quality 0–100 vs presets/0.0–1.0), --retain-dates deprecated. Rewritten: 113 rows (93 + 5 shared network rows × 4 tools), every name in the surface, picker values accepted, defaults = CLI defaults (port 11112, --called-aet ANY-SCP, --timeout 30/60, --level study, --profile ps315, --method c-move, --priority medium, --format text/dicom/table, --backend auto, --syntax explicit-le, --count 1, --quality 90, --output "."). FormRenderingHelpers.generateCommand emits `<positional>` names as bare values (new public helper `isPositional`, additive). Doc comments cite PS3.5 Table 6.2-1 and PS3.8 9.1.1 (6b57be6c) | ParameterBuilder* suites (17 expectations moved from "--host" to "<host>", 1 from "--input" to "<file-path>"), CLIShellCatalogueTests |
| 2026-10-05 | ParameterBuilderModel | PS3.5 2026a Table 6.2-1 AE; PS3.8 2026a 9.1.1 | doc comment "max 16 uppercase characters" → 16 bytes, not restricted to upper case; port doc names 104 / 11112 (6b57be6c) | — |
| 2026-10-05 | IntegrationTestingModel scenarios | Sources/dicom-* targets | 41 → 42 names: dicom-qido, dicom-stow, dicom-ups removed (they are dicom-wado subcommands, not tools), dicom-j2k, dicom-jpip, dicom-printscp, dicom-video added; toolCount networking 14 → 13, fileProcessing 4 → 5, dataExchange 5 → 6; IntegrationTestingHelpers.totalToolCount (NST) now derives from the categories instead of the literal 41 (a148b084) | IntegrationTestingTests (41 → 42, 14 → 13) |
| 2026-10-05 | IntegratedTerminalHelpers redactPHI | PS3.6 2026a Table 6-1 keyword → name; PS3.15 2026a Table E.1-1 rows | 7 of 7 keywords are E.1-1 attributes; comment now names Table E.1-1 (86aae0ee) | IntegratedTerminalHelpersTests, CLIShellCatalogueTests |
| 2026-10-05 | Marker | PS3.4 N.2; PS3.3 C.10.4 | `PrintViewModel+PresentationStates.swift` marked (no standard literal; D42 photometric hand-off) (`0dbb6047`) | — |
| 2026-10-05 | Server-profile injection (shell finding) | CLI ArgumentParser surface of the 7 DIMSE tools and dicom-wado | `NetworkInjectorHelpers.dicomParameters` / `dicomwebParameters` inject the positional `<host>` / `<base-url>` and `--token` instead of `--host`, `--tls`, `--url`, `--auth`, which no tool accepts (`diff_studio_g1_shell.py`: 37 / 0) | `ShellServerConfigHelpersTests` +2 |
| 2026-10-05 | dicom-query: --level picker patient/study/series/image (IMAGE on the wire, "instance" kept as alias), --format dicom-json, --csv-keywords, --strict-modality, CLI help texts; executor: validate() refusals (64), ModalityOptionValidator, warning names the level by QueryLevel.rawValue, shared formatter with csvHeader / dicomJSONEncoder, `Error: …` exit 1; echo / query presets positional host:port | PS3.4 2026a Tables C.6.1-1 / C.6.2-1 (4 values: 4 matched), C.4.1.2.1; PS3.18 F.2; PS3.3 C.7.3.1.1.1 | a2a828c2 | queryLevelPickerIsPS34, queryFormatAndModalityRows, queryLevelOption, queryLevelRefusal, queryResultFormatter, resolveModalityOption; parity test fixture series/image; g1 "net query levels" (15 matched) |
| 2026-10-05 | dicom-send: --transfer-syntax (TransferSyntax.negotiableImageTokens), PS3.7 priority help; executor: preferredTransferSyntaxUID through DICOMStorageService.store, header UID, PS3.4 Table B.2-1 classes (Failure class retried and counted failed, Warning class sendFileWarningLine + Warnings count), CLI refusals / SendError texts | PS3.7 2026a Table 9.3-1 (3 values: 3 matched = DIMSEPriority); PS3.4 Table B.2-1 (7 rows read); PS3.8 7.1.1.13 | 76a31e99 | sendTransferSyntaxAndPriorityRows, sendStoreOutcomeClasses; g1 "net priority send" (20 matched) |
| 2026-10-05 | dicom-retrieve / dicom-qr: --priority pickers, --relational-retrieve, qr --strict-modality / --include-parent-keys, CLI help; executors: RetrieveConfiguration(priority:extendedNegotiation:), RetrieveKeys at the most specific level, DIMSEServiceStatusText.describe(.cMove / .cGet) + subOperationCounts, Failed SOP Instance UID List lines, success rule C.4.2.2.1, retrieveHeader(priority:relationalRetrieval:), CLI refusals (64) and RetrieveError / DICOMQRError texts (1), qr --parallel batches with the CLI's line order, buildQueryKeys; app-only Study-UID C-FIND lookup removed | PS3.7 2026a Tables 9.3-9 / 9.3-6 (3 values: 3 matched); PS3.4 Tables C.4-2 / C.4-3 (Success / B000 rows read), C.4.2.2.1 / C.4.3.2.1, C.4.2.2.2.1, C.5.2.1 / Table C.5-3; PS3.7 Tables 9.3-10 / 9.3-7 | f8e70094 | retrieveAndQRRows, retrievePriorityOption, retrieveUIDRefusal, retrieveCheckTexts; g1 "net retrieve status" (43 matched) |
| 2026-10-05 | dicom-mwl: --sps-status picker = PS3.3 C.4.10 Defined Terms (was PPS words), --specific-character-set, --strict-modality, CLI help; executor: validator, spsStatusWarning mirror, specificCharacterSet passed, exit 64 / 1 texts. dicom-mpps: --modality required (Type 1), --strict-modality, CID 9301 placeholder / examples (D85), CLI help; executor: Type 1 refusal, sex / DA validation, status guards, --image-uid / --sop-class-uid rules, warning via DIMSEServiceStatusText, CLI header fields | PS3.3 2026a C.4.10 (5 terms: 5 matched), Table C.2-3 (3), Table C.4-14; PS3.4 Tables K.6-1a, F.7.2-1 rows 1 / 105; PS3.5 Table 6.2-1 DA; PS3.16 CID 9301 (17 DCM rows: 4 examples matched); PS3.4 Table F.7.2-2 / PS3.7 Annex C | d716de90 | mwlRows, mppsRows, mwlSPSStatusWarning, mppsValueRules; g1 "net mwl mpps terms" (33 matched); P-STUDIO-MWL-CREATE PEND |
| 2026-10-05 | dicom-wado query / retrieve / store / ups: qido --strict-modality, --fuzzy-matching, --format dicom-json, --limit ≥ 0; retrieve --content-type real flag (WADOURIClient.MediaType.allowed, 15 values), 12 WADO-URI parameters, --timeout wired, WADOURIClient.Parameters, CLI refusals / warnings, previews removed; store exit 1 on any unstored instance, Warning Reason lines, CLI refusals; ups --change-state / deprecated --update, --state IN PROGRESS / COMPLETED / CANCELED with SCHEDULED refusal, PS3.3 spellings, HIGH / MEDIUM / LOW, --format csv / dicom-json, CLI print structure; WorkshopWADOOptionRules text-identical mirror | PS3.18 2026a Tables 9.1.2-2 / 9.4.1-1 / 9.5.1-1, 9.1.2.2.1 / Table 8.7.4-1 (14 Rendered Media Types), 9.5.1.2.1, 8.3.4.2 / 8.3.4.4, 10.5.3-1, Table I.2-1, 11.7.1.4 (3 values: 3 matched), F.2; PS3.3 C.30.1 (4 states), C.30.2 (3 priorities), Table C.7-1; PS3.4 Table CC.1.1-2 | d52bbfa9 | qidoRows, wadoRetrieveRows, upsRows, upsChangeStateRefusal, wadoURIRules; g1 "net web rules" (59 matched); EXEMPT 5 rows, DEFERRED 1 |
| 2026-10-05 | dicom-echo: --count 0 refused with the CLI's text (64) instead of clamped; host refusal as usage error; ups catch prints String(describing:) as ArgumentParser | dicom-echo run() ValidationError; ArgumentParser MessageInfo | 7af3cce0 | (covered by the suites; no new row) |
| 2026-10-05 | dicom-anon: the 12 PS3.15 E.3 Option flags (`--retain-dates` deprecated), `--clean-pixel-data`, `--redact-region`, `--redact-fill`, `--allow-burned-in-phi` offered with the CLI's help; executor runs dicom-anon's run() (Anonymizer + PixelRedactor, AnonConsole lines, legacy-profile notice, E.1-1a action report on --dry-run / --verbose, (0002,0003) = (0008,0018), the CLI's refusals and exit codes); E.3 flags refused with the CLI's "apply only to --profile ps315" text; ps315 / basic refused (PEND P-STUDIO-ANON-PS315) | PS3.15 2026a Table E.1-1 (10 Option columns: 10 matched), E.3.1-E.3.11 titles (11 named), PS3.16 CID 7050 (13 rows: 11 Option meanings matched), PS3.10 7.1 | 38a2eea0 | anonOptionFlags, anonMirrorTexts; g1 "pixel anon options" (95 matched) |
| 2026-10-05 | dicom-image: `--conversion-type` (Table C.8-24 via ConversionType.definedTerms), `--strict-modality`, CLI help texts, modality default omitted; executor: P-IMAGE-VR refusals before ImageConverter, ModalityOptionValidator per file, SCOutput.finalize ((0002,0003), ISO_IR 192) mirror, CLI order / exit codes (64 usage, 1 refusal, 0 directory) | PS3.3 2026a Table C.8-24 (8 terms: 8 matched), Table C.12-1 / C.12-5, PS3.5 Table 6.2-1 (LO / PN 64, UI 64 — 3 phrases read), 9.1, PS3.10 Table 7.1-1 | 38a2eea0 | conversionTypePickers, imagePdfPixeditRules; g1 "pixel conversion type" (32), "pixel image pdf pixedit rules" (35) |
| 2026-10-05 | dicom-pdf: `--conversion-type`, `--burned-in-annotation`, `--hl7-instance-identifier`, `--strict-modality`, CLI help; executor: dicom-pdf's encapsulatedDataSet chain with Encapsulated Document Length (0042,0015) and Specific Character Set as the CLI writes them, padding cut on extraction (D182), the CLI's refusals (64) and exit codes | PS3.3 2026a Table C.24-2 (0042,0015 Type 3, (0028,0301) Type 1, (0040,E001) Type 1C), Table C.8-24, Table C.12-1 / C.12-5, PS3.6 Table A-1 SOP Classes (engine) | 38a2eea0 | conversionTypePickers, imagePdfPixeditRules; g1 (as above) |
| 2026-10-05 | dicom-pixedit: CLI help texts, `--fill-value` without default; executor: DerivedImage mirror (P-PIXEDIT-RANGE refusals, exit 1), PixelEditDerivation(descriptionPrefix: "dicom-pixedit"), the CLI's run() order, ArgumentParser two-line message for unparseable numbers (64) | PS3.3 2026a C.7.6.3.1 (Bits Stored / Pixel Representation range), C.11.2.1.2 ("shall always be greater than or equal to 1" read), C.7.6.1.1.2 | 38a2eea0 | pixeditRows, imagePdfPixeditRules; g1 "pixel image pdf pixedit rules" |
| 2026-10-05 | dicom-video: `--strict-modality`, `--audio-channel-source` (CID 3000 keywords / SCHEME:VALUE[:MEANING], one per track, D56), CLI help suffixes stating the refusals; executor: validatedShared() mirror (ModalityOptionValidator, audio sources into VideoWorkflow.Metadata.audioChannelSource(s)), VideoOptionConformance.violations mirror (ES/GM/XC, M/F/O, DA, unregistered HEVC UIDs; exit 1) in the CLI's order for convert and batch | PS3.16 2026a CID 3000 (6 rows: 6 matched, keywords = hyphenated meanings), PS3.3 A.32.5.4.1 / A.32.6.4.1 / A.32.7.4.1 ("shall be" ES / GM / XC read), C.7.1.1 Patient's Sex (M F O read), Table C.7-13, PS3.5 Table 6.2-1 DA, PS3.6 Table A-1 (UIDDictionary.registered) | 38a2eea0 | videoConformanceRows; CLIWorkshopVideoTests flag set; g1 "pixel cid3000 audio source" (40) |
| 2026-10-05 | dicom-convert: `--transfer-syntax` picker = DICOMConverter.cliTokens (Reversible names), old spellings canonicalised on entry (WorkshopTransferSyntaxKeywords.canonicalToken), TransferSyntaxKeywords mirror (+7 Table A-1 keywords), `--frame-number` (from 1) with `--frame` deprecated, CLI help; executor: validate() refusals (64), both-frame-spellings exit 1, deprecation and reassigned-keyword notes, invalidFrameNumberMessage, directory run exits 1 on a failure, app-only chrome removed | PS3.6 2026a Table A-1 (7 added keywords + 3 reassigned: 10 matched), PS3.3 Table 10-3 ("The first Frame shall be denoted as Frame number 1" read), C.11.2.1.2.1 | 38a2eea0 | convertTokensAndFrames, testDicomConvertParameterCount (14); g1 "pixel convert tokens" (24) |
| 2026-10-05 | dicom-compress: decompress / batch `--syntax` picker = NativeTargetSyntax.accepted (explicit-le, implicit-le, deflate, explicit-be), refusals mirrored (exit 1), CLI help texts; executors: validate() texts (64), `Error: \(error)` formatting, "Error scanning directory", info --json via CompressionConsole.infoJSON (already shared) | PS3.6 2026a Table A-1 (4 native UIDs: 4 matched), PS3.5 A.1, A.2, A.3 (retired, D206), A.5 | 38a2eea0 | compressSyntaxPicker; g1 "pixel compress syntax" (15) |
| 2026-10-05 | Markers on CLIWorkshopHelpers.swift and CLIWorkshopViewModel.swift summarising the three Workshop passes (33 tool ids; G1 parity 0 FAIL, 2 PEND) | — | 5678fa8e | — |
| 2026-10-06 | Module close | — | `diff_studio.py`: 206 ok, 0 FAIL, 13 PEND; `check_nema_markers.py --inventory`: 170 marked + 164 inventoried, exit 0; DICOMCore status row, CHANGELOG | full `swift test` exit 0: XCTest 5,819 / 44 skipped / 0 failures; Swift Testing 9,252 passed |
| 2026-10-06 | Deferred follow-up (owner: complete all open deferred items per recommendation, except D216, D221, D256): D237, D242, D243, D245, D247–D255, D257–D275 closed; P-VIDEO-CONTAINER approved | each row's 2026a clause (Deferred findings below) | 35 commits `7a3aac80` … `15b06782` (in each row's Status cell); D256 left open by owner decision; D244, D246 stay void; the 14 P-STUDIO-* items are unchanged (still pending: the instruction covered deferred rows only); D85 gains its sha (A8); Studio copies replaced by the engine symbols in the Studio pass (Studio pass: `2bd8e408`…`3060ee3e` (9 commits)) | diff_kit 0 wrong, diff_network 0, diff_web 0, diff_printkit 0, diff_renderkit 17 ok / 0 failing / 0 deferred, diff_cli 0 FAIL (42 tools), diff_cli_web 0 FAIL, every check_nema_markers run exit 0 (all with --nema 2026a); diff_studio is re-run in the Studio pass |

---

## Priority action list (P-items: public API, owner's decision needed)

| Item | What | Standard | Recommendation | Status |
|---|---|---|---|---|
| P-STUDIO-ANON-PS315 (existing, PEND) | the Workshop `--profile` picker offers the legacy lists only (default legacy-basic; the CLI default is ps315); ps315 / basic are refused with exit 1; the E.3 Option flags, `--allow-burned-in-phi` and the ps315 engine path (`Anonymizer.deidentify`, the ps315 audit log, the burned-in PHI refusal) therefore cannot run in the Workshop. The CLI-local AnonCLI texts are mirrored now, so adding the Studio enum case is the remaining step | PS3.15 2026a Table E.1-1 | approve the new AnonymizationProfile case (ps315) so the picker can default to ps315 like the CLI; the executor then runs `Anonymizer.deidentify(file:options:)` with `WorkshopAnonCLI` extended by the ps315-only AnonCLI texts (validate rules, retainDatesNotice, visualFeaturesLines, auditLogText) | | ⏳ pending |
| P-STUDIO-MWL-CREATE | The Workshop's dicom-mwl `create` operation (HL7 ORM^O01 over MLLP or the archive REST API; all its fields isInternal, preview rendered commented out) has no dicom-mwl CLI counterpart — the CLI registers only `query` (no DIMSE service creates a worklist item). The parity check flags the subcommand picker value; annotated PEND in diff_studio_g1 | PS3.4 Annex K (C-FIND only) | Either add a `dicom-mwl create` subcommand (HL7 / REST) to the CLI so the preview becomes paste-runnable, or move the create flow out of the CLI Workshop into the Networking panel. Until decided the arm stays as is (behaviour unchanged) | | ⏳ pending |
| — | none: all fixes are data/returned-value changes; `FormRenderingHelpers.isPositional` is an additive public helper | | | | ⏳ pending |
| P-STUDIO-TLS-PROFILES (shared with the DIMSE half) | `DICOMwebTLSMode` (NONE / COMPATIBLE / STRICT / DEVELOPMENT) selects TLS versions, not PS3.15 Annex B Secure Transport Connection Profiles (B.12 Non-Downgrading BCP 195, B.13 Extended BCP 195); `DICOMwebClientFactory` ignores the mode entirely | PS3.15 2026a Annex B | Offer the Annex B profile names as cases and pass the choice to `DICOMwebConfiguration` when DICOMWeb exposes one; same decision as NetworkingModel.TLSMode | | ⏳ pending |
| P-STUDIO-UPS-STATE-RAW | `DICOMwebModel.UPSState` raw values are `IN_PROGRESS` and `CANCELLED`; the Procedure Step State (0074,1000) terms are `IN PROGRESS` and `CANCELED`. The case `.cancelled` also mis-spells the term. `DICOMWeb.UPSState` already carries the correct raw values and a `isValidTransition`. Behaviour is unaffected (ViewModel maps by string; `dicomTerm` added internally) | PS3.3 2026a C.30.1; PS3.4 Table CC.1.1-1 | Replace Studio's `UPSState` by a typealias to `DICOMWeb.UPSState` (same four cases; `.cancelled` → `.canceled` with a deprecated alias), or change the raw values to the standard terms. Either is public API | | ⏳ pending |
| P-STUDIO-EXPORT-SINGLE-OUTPUT | `dicom-export single --output` is optional on the CLI (writes `<stem>.<ext>` in the working directory); the Workshop form requires it (a sandboxed app has no working directory) and refuses with ArgumentParser's "Missing expected argument '--output <output>'" (64) | — | keep it required in-app (documented non-mirroring); no public-API change involved | | ⏳ pending |
| (P-STUDIO-ANON-PS315, existing) | still open; `SecurityModel` doc comments now say no case is PS3.15 Annex E | PS3.15 2026a Annex E | as recorded by the orchestrator | | ⏳ pending |
| P-STUDIO-ANON-TAGLIST-NAME | `AnonymizationHelpers.hipaaDirectIdentifierTags` (public) now holds the engine's 14-attribute basic list; the name still says HIPAA | — (naming; 45 CFR §164.514(b)(2)(i) is law, not a DICOM table) | rename to `basicProfileTags` with `@available(*, deprecated, renamed:)` on the old name | | ⏳ pending |
| P-STUDIO-MEASURE-UM | `MeasurementUnit` (mm, cm, in) has no micrometre case; dicom-measure offers `--unit um` and CID 7460 / 7461 list um / um2 | PS3.16 2026a CID 7460 / 7461 | add `case micrometers = "um"`; ROIHelpers.ucumAreaCode then returns "um2" | | ⏳ pending |
| P-STUDIO-HP-SORTING-DIRECTION | `ImageSortDirection` raw values ASCENDING / DESCENDING vs Sorting Direction (0072,0604) INCREASING / DECREASING | PS3.3 2026a Table C.23.3-1 | change raw values to INCREASING / DECREASING with a decoding shim for stored state | | ⏳ pending |
| P-STUDIO-RT-DOSE-UNITS | `RTDoseUnits.cgy = "CGY"` is not a Dose Units term; RELATIVE and CODED absent | PS3.3 2026a Table C.8-39 Dose Units (GY, RELATIVE, CODED) | add `.relative`, `.coded`; keep cGy as a display scale, not a raw value | | ⏳ pending |
| P-STUDIO-RT-ROI-TYPES | `RTROIType` carries 6 of the 25 RT ROI Interpreted Type Defined Terms plus `OTHER`, which is not a term | PS3.3 2026a Table C.8-44 / C.8.8.8.1 | add the 19 missing cases (TREATED_VOLUME … DEVICE), map unknown values to nil instead of `.other`, deprecate `.other` | | ⏳ pending |
| P-STUDIO-SCOORD-POLYGON | `SpatialCoordGraphicType.polygon = "POLYGON"` is not a 2D SCOORD Graphic Type (closed POLYLINE is) | PS3.3 2026a C.18.6.1.2 (POINT, MULTIPOINT, POLYLINE, CIRCLE, ELLIPSE) | deprecate `.polygon` (`@available(*, deprecated, renamed: "polyline")`); writers emit POLYLINE | | ⏳ pending |
| P-STUDIO-SR-TABLE | `ContentItemValueType` (public enum) lacks the TABLE value type | PS3.3 2026a Table C.17.3-7 (16 value types) | add `case table = "TABLE"`; SRTreeHelpers display mapping follows (switches are exhaustive) | | ⏳ pending |
| P-STUDIO-ANNOTATION-UNITS | `TextAnchorType.imageRelative` has raw value `"IMAGE"`; the Anchor Point / Bounding Box Annotation Units Enumerated Values are PIXEL, DISPLAY, MATRIX. Changing a public raw value and adding a case is API | PS3.3 2026a C.10.5 (0070,0003), (0070,0004) | Rename the raw value to `"PIXEL"` (keep a deprecated `imageRelative` spelling if the raw string is persisted anywhere — it is not, as far as grep shows) and add `case matrixRelative = "MATRIX"` for tiled images; the script's PEND then clears | | ⏳ pending |
| P-STUDIO-ANON-PS315 | `AnonymizationProfile` (DICOMStudio, public enum) has no case for the PS3.15 Basic Profile, which is dicom-anon's default (`ps315`); the Workshop refuses it, the Security panel cannot run it | PS3.15 2026a Annex E, Table E.1-1 | Add `.ps315` (display "PS3.15 Basic Application Level Confidentiality Profile"), make it the default, route it to `Anonymizer.deidentify`; keep the legacy cases, labelled as not PS3.15 | ⏳ pending |
| P-VIDEO-CONTAINER | DICOMKit `VideoContainer` lacks `.mpegPS` / `.mpegPES` because `ViewerNonImageContentView.swift` switches exhaustively (D237) | PS3.5 2026a 8.2.5, 8.2.6 | Give the Studio switch a `default`, then add the two cases in DICOMKit (D237) | ✅ approved by the owner 2026-10-06 and done in `7a3aac80` (D237) |
| P-STUDIO-TLS-PROFILES | `TLSMode` (NONE / TLS_1_2 / TLS_1_3 / MTLS) cites "PS3.15 Annex B" but selects TLS versions and client-certificate use, not a Secure Transport Connection Profile; B.9–B.11 are retired in 2026a, the live TLS profiles are B.12 "BCP 195 RFC 8996, 9325 TLS" (TLS 1.2 required, 1.3 preferred) and B.13 "Modified BCP 195 RFC 8996, 9325 TLS". | PS3.15 2026a Annex B (B.12, B.13) | Either re-label the doc comment as a transport setting (no profile claim) — text only, done implicitly by the marker — or add cases `bcp195` / `modifiedBcp195` that configure the DICOMNetwork TLS options per B.12 / B.13 and deprecate `tls12` / `tls13` (a profile forbids pinning TLS 1.2 alone). New enum cases are public API — not done. | | ⏳ pending |
| P-STUDIO-PRINT-ENUMS | `DICOMStudio.PrintPriority`, `PrintMediumType`, `PrintFilmSize`, `PrintJobStatus` (NetworkingModel.swift) duplicate `DICOMNetwork.PrintPriority` / `MediumType` / `FilmSize` and the Execution Status terms; `PrintMediumType` offers 3 of the 5 Medium Type terms (no MAMMO). Their raw values are now the standard's terms and are mapped case-by-case onto DICOMNetwork's before anything reaches the wire. | PS3.3 2026a Table C.13-1, C.13-3, C.13-8 (D22) | Deprecate the three Studio enums with `@available(*, deprecated, renamed:)` typealiases onto `DICOMNetwork.PrintPriority`, `MediumType`, `FilmSize` (the raw-value sets are now identical for Priority and Film Size; Medium Type gains the two MAMMO terms in the picker), move `displayName` to extensions on the DICOMNetwork types, drop the switch mappings in `NetworkingViewModel.submitPrintJob`; keep `PrintJobStatus` (it is the panel's state, not a wire attribute) but rename to `NetworkPrintJobState` to stop it reading as the Print Job SOP Class's Execution Status. Public API — not done. | | ⏳ pending |


### Behaviour changes made for CLI parity, for the owner to confirm (2026-10-05)

The Workshop agents removed app-only behaviour where it diverged from the CLI tool the form mirrors. None is a
standard violation; each is listed so the owner can keep or restore it:

| Tool | What changed | Why | Commit |
|---|---|---|---|
| dicom-retrieve (Workshop) | the app-only Study-UID C-FIND lookup before a series / instance retrieve is gone; `--relational-retrieve` (PS3.4 C.5.2.1) is offered instead, as in the CLI | the CLI never did the lookup; parity of output and refusals | `f8e70094` |
| dicom-wado retrieve (Workshop) | per-instance previews after a retrieve removed | not CLI output | `d52bbfa9` |
| dicom-wado ups (Workshop) | app-only chrome removed: query dump, curl block, pre-flight check, hints | not CLI output; the print structure now equals the CLI's | `d52bbfa9` |
| dicom-anon (Workshop) | the executor runs dicom-anon's own loop (Anonymizer, PixelRedactor, AnonConsole, E.1-1a action report) instead of `SecurityViewModel` | parity of output and refusals | `38a2eea0` |
| dicom-convert (Workshop) | app-only header / banner removed | not CLI output | `38a2eea0` |
| dicom-image / dicom-pdf (Workshop) | directory runs exit 0 with failed files, as the CLIs do | parity; the CLI behaviour is itself a new finding | `38a2eea0` |
| dicom-pixedit (Workshop) | refuses out-of-range fill values and widths < 1 instead of clamping; output marked as a Derived Image | P-PIXEDIT-RANGE; PS3.3 C.7.6.1.1.2 | `38a2eea0` |
| dicom-anon (Workshop and Security panel) | `--profile` values are the CLI's `legacy-*` names; `ps315` / `basic` refused with exit 1 until P-STUDIO-ANON-PS315 | the old `basic` now means the PS3.15 Basic Profile in the CLI | `61670c42` |

---

## Deferred findings

### Rows inherited from earlier reports (worked first)

| Row | From | File | Problem | Standard | Status |
|---|---|---|---|---|---|
| D9 | DICOMCore | `Models/J2KTestBenchModels.swift:123,392` | .4.110 called "JPEG XL Lossless Only"; PS3.6 name "JPEG XL Lossless" | PS3.6 Table A-1 | ✅ 2026-10-05: every transfer-syntax display name tied to a UID in Studio text is the Table A-1 name or DICOMCore's shortName/displayName; abbreviations in ImportValidation, J2KTestBenchModels, FileOperationsHelpers spelled out; CompressionAlgorithmHelpers UIDs corrected; check `G2 codec: transfer-syntax names` (50 matched, 0 wrong) over all Studio ST files (1bbc18a8) |
| D10 | DICOMCore | `Components/ThumbnailHelpers.swift:107` | `supportedPhotometricInterpretations` omits XYB, YBR_PARTIAL_420, YBR_ICT, YBR_RCT | PS3.3 C.7.6.3.1.2 | ✅ 2026-10-05: ThumbnailHelpers.supportedPhotometricInterpretations built from DICOMCore PhotometricInterpretation; 11 terms == C.7.6.3.1.2 less HSV/ARGB/CMYK; pinned (1b0588eb) |
| D11 | DICOMCore | `Components/ImageMetadataHelpers.swift:62` | no label for XYB | PS3.3 C.7.6.3.1.2 | ✅ 2026-10-05: ImageMetadataHelpers.photometricLabel gains XYB; 11 labels checked term by term (1b0588eb) |
| D22 | DICOMNetwork | `Models/NetworkingModel.swift` (~L907-1050) | `PrintMediumType.bluFilm = "BLU-RAY"`; re-declared print enums | PS3.3 C.13.1 | ✅ 2026-10-05 strings (`6ab02140`: BLUE FILM, DONE/FAILURE, IN PROGRESS; FilmLayout now reaches the wire as Image Display Format); the duplicate enums are P-STUDIO-PRINT-ENUMS |
| D28 | DICOMKit | `ImageViewerViewModel+PresentationStates` (~L1057); `Views/DICOMInspectorView.swift:41` | PR without Modality LUT falls back to the image's rescale (S-2 migration rule); "is binary" check omits OV (D5 half) | PS3.4 N.2.1.1; PS3.5 Table 6.2-1 | ✅ 2026-10-05 `6372e096`: PR without Modality LUT = identity, with the S-2 rule (only this app's own, non-imported, pre-2026-09-29 objects keep the image rescale); inspector binary VRs include OV (PS3.5 Table 6.2-1) |
| D29 | DICOMKit | `CLIWorkshopViewModel.swift:1730`, `CLIWorkshopHelpers.swift:3128` | dcmdir `--profile` choices list STD-GEN-DVD / STD-GEN-USB (family headings) | PS3.11 Annexes H, J | ✅ 2026-10-05 `2f730cac` (Workshop file tools mirror the CLI; see the parity section) |
| D42 | DICOMPrintKit | `ImageViewerViewModel+PresentationStates.swift` (~L460, 610, 1040), `PrintViewModel+PresentationStates.swift` (~L365) | pass Photometric Interpretation and Rescale Type to the bridge and `ImageToSave` | PS3.4 N.2; PS3.3 A.33.1.1, Table A.33.2-1 | ✅ 2026-10-05 `6372e096`: Photometric Interpretation and Rescale Type passed to `ViewerPresentationStateBridge.capture/restore` and `ImageToSave`; MONOCHROME1 → INVERSE Presentation LUT fold, colour → Color Softcopy PS |
| D56 | DICOMKit | CLI Workshop video form | no Audio Channel Source field | PS3.3 Table C.7-13; PS3.16 CID 3000 | ✅ 2026-10-05 `38a2eea0`: `--audio-channel-source` per audio track (CID 3000 keywords or SCHEME:VALUE[:MEANING]) → `VideoWorkflow.Metadata.audioChannelSources` |
| D65 (viewer half) | DICOMRenderKit | `ImageViewerViewModel.swift` ~L1390, ~L1432; `+PresentationStates.swift` ~L1060 | stored-unit window conversion exact for slope 1 only | PS3.3 C.11.2.1.2.1 | ✅ 2026-10-05 `6372e096`: the viewer renders through the N.2 chain; a stored-unit window is converted c·m+b, w·|m| before the renderer (exact for every slope) |
| D68 | DICOMRenderKit | `Services/FrameRenderer.swift`, `ViewModels/ImageViewerViewModel.swift` | pass Modality LUT, VOI and ICC Profile to `FrameRenderRequest` | PS3.4 N.2; PS3.3 C.11.2.1.2.1, C.11.15.1.1 | ✅ 2026-10-05 `6372e096`: viewer, tiles, film cells, `ImageRenderingService` and the progressive decoder pass `modalityLUT` / `voiLUT` / `presentationLUT` / `iccProfile` to `FrameRenderRequest` (or use `renderFrameForExport`); VOI LUT Sequence shown until a drag; `ViewerDisplayPipelineTests` 13 |
| D85 | DICOMCLI | `CLIWorkshopHelpers.swift:1379-1380, 1217-1221` | mpps placeholder "110513\|DCM\|Doctor cancelled procedure"; `--modality` optional | PS3.16 Table D-1; PS3.4 Table F.7.2-1 | ✅ 2026-10-05: CLIWorkshopHelpers mpps `--discontinuation-reason` placeholder "110513\ (Doctor cancelled procedure" → "110513\); commit `d716de90` (sha added 2026-10-06, audit A8) |
| D88 | DICOMCLI | `Tests/DICOMStudioTests/NetworkToolWorkshopCLIParityTests.swift:151-157` | fixtures with wrong CID 9300 code/meaning pairs | PS3.16 Table D-1 | ✅ 2026-10-05: NetworkToolWorkshopCLIParityTests fixtures use real CID 9301 pairs (110513 "Discontinued for unspecified reason", 110501 "Equipment failure") (`32929df7`) |
| D114 | DICOMCLI | `CLIWorkshopViewModel.swift:1258`, `CLIWorkshopHelpers.swift:2847, 2920` | json/xml empty-attribute default differs from the CLI (on); no `--no-include-empty` | PS3.18 F.2.5; PS3.19 A.1.5-2 | ✅ 2026-10-05: json / xml `include-empty` default on with `negatedFlag: --no-include-empty`; executor `includeEmpty: != "false"`; no-sort-keys / no-keywords marked deprecated with the CLIs' stderr notes (text-identical) (2f730cac) |
| D127 | DICOMCLI | `CLIWorkshopViewModel.swift:4410, 4557-4562, 4620-4628` | contact-sheet / animate copy the old render path; fps default | PS3.4 N.2; PS3.3 C.11.2.1.2.1 | ✅ 2026-10-05: export executor: contact-sheet and animate render through `DICOMImageExporter.renderFrameForExport` (PS3.4 N.2 chain), fps default = file rate ((0008,2144) → (0018,0040) → 1000 / (0018,1063) → 10), Burned In Annotation warnings, `frame-number` / `start-frame-number` / `end-frame-number`, deprecation notes, exit-1 conflict, exit-64 "< 1", `buildOrganizedPath(…patientID:issuerOfPatientID:…)`, `apply-window` deprecated on contact-sheet / bulk (2f730cac) |
| D132 | DICOMCLI | Workshop dcmdir executor | lacks the CLI validate rules and File-set ID default | PS3.10 8.x | ✅ 2026-10-05: dcmdir executor: `WorkshopFileSetRules` (text-identical copy of the CLI-local FileSetRules) — File-set ID default (upper-cased, `_`, cut to 16), invalid `--file-set-id` refused exit 1, validate prints the File ID / File-set ID / duplicate-reference / missing-file findings with their clauses (exit 1), `--copy-to`, "no file could be indexed" (exit 1), ValidationErrors exit 64 (2f730cac) |
| D154 | DICOMCLI | `CLIWorkshopHelpers.swift:2520` | split `--frames` help does not say 0-based | PS3.3 C.7.6.16.1.2 | ✅ 2026-10-05: split `--frames` help "deprecated: 0-based index; use --frame-numbers" (the CLI's), `--frame-numbers` added (SplitConsole.parseFrameNumberSelection, headerLines(frameNumbers:)), `SplitConsole.framesDeprecatedLine` printed, both refused with `framesAndFrameNumbersConflictMessage` (exit 1); parity-test filter removed, 6 cases added (2f730cac) |
| D237 | DICOMCLI | `Views/ViewerNonImageContentView.swift:422` | exhaustive switch blocks `VideoContainer.mpegPS` / `.mpegPES` | PS3.5 8.2.5, 8.2.6 | ✅ 2026-10-06 `7a3aac80`: VideoContainer.mpegPS / .mpegPES reported for MPEG-2 Program Stream and PES; P-VIDEO-CONTAINER approved by the owner 2026-10-06 (PS3.5 2026a 8.2.5, 8.2.6); Studio half 2026-10-05 `88c271c6` (the view uses `ExtractedVideo.containerDisplayName`, no exhaustive switch over `VideoContainer`) |

### New findings for other modules

| ID | Module | File | Problem | Standard | Severity | Status |
|---|---|---|---|---|---|---|
| D266 | Scripts (orchestrator) | Scripts/diff_studio.py parse_definition | a picker written `[""] + Expr` is read as the literal `[""]`, so dicom-video --type (an enum-typed CLI option) is reported as offering only '' and lacking the three values — annotated DEFR in diff_studio_g1.DEFERRED; the g1 checks therefore test such pickers on the definition's source text (raw_definition). Teach parse_definition the `[""] + expr` form | — (tooling) | Low | ✅ 2026-10-06 `4d26acec`: diff_studio parse_definition reads [""] + Expr and enum-backed pickers (with D247, D258) (tooling, no NEMA clause) |
| D267 | dicom-compress | Sources/dicom-compress/main.swift (NativeTargetSyntax) | CLI-local native-target set and refusal texts mirrored by WorkshopNativeTargetSyntax; lift into CompressionConsole | PS3.6 Table A-1; PS3.5 A.1, A.2, A.3, A.5 | Low (duplication) | ✅ 2026-10-06 `36022531`: native decompress targets lifted into CompressionConsole.NativeTargetSyntax (PS3.6 2026a Table A-1; PS3.5 A.1, A.2, A.3, A.5); Studio copy replaced by the engine symbol in the Studio pass (Studio pass: `2bd8e408`) |
| D268 | dicom-convert | Sources/dicom-convert/TransferSyntaxKeywords.swift | CLI-local 7 Table A-1 keywords and the composed --transfer-syntax help mirrored by WorkshopTransferSyntaxKeywords; fold the keywords into the DICOMConverter catalog (extraAliases) | PS3.6 Table A-1 | Low (duplication) | ✅ 2026-10-06 `b281e64f`: the 7 Table A-1 keywords folded into DICOMConverter.additionalTableA1Keywords / resolveTarget for every caller (FrameMerger included); help via transferSyntaxOptionHelpWithKeywords (PS3.6 2026a Table A-1); Studio copy replaced by the engine symbol in the Studio pass (Studio pass: `2bd8e408`) |
| D269 | dicom-video | Sources/dicom-video/OptionConformance.swift, AudioChannelSourceOption.swift | CLI-local refusals and CID 3000 option grammar mirrored by WorkshopVideoOptionConformance / WorkshopAudioChannelSourceOption; lift into DICOMKit Video (VideoConsole / VideoWorkflow) | PS3.3 A.32.x, Table C.7-1; PS3.16 CID 3000 | Low (duplication) | ✅ 2026-10-06 `cc3c3675`: VideoOptionConformance and AudioChannelSourceOption lifted into DICOMKit Video (PS3.16 2026a CID 3000; PS3.3 A.32.5–A.32.7, Table C.7-1); Studio copy replaced by the engine symbol in the Studio pass (Studio pass: `2bd8e408`) |
| D270 | dicom-pixedit | Sources/dicom-pixedit/DerivedImage.swift | CLI-local P-PIXEDIT-RANGE refusals mirrored by WorkshopDerivedImage; lift next to PixelEditor | PS3.3 C.7.6.3.1, C.11.2.1.2 | Low (duplication) | ✅ 2026-10-06 `4a756536`: PixelEditInputChecks lifted next to PixelEditor (PS3.3 2026a C.7.6.3.1, C.11.2.1.2); Studio copy replaced by the engine symbol in the Studio pass (Studio pass: `2bd8e408`) |
| D271 | dicom-pdf | Sources/dicom-pdf/main.swift (extractFromDirectory / encapsulateFromDirectory) | a directory run exits 0 whatever the per-file outcomes; the Workshop mirrors it | — (tool contract) | Low | ✅ 2026-10-06 `15b06782`: dicom-pdf directory runs (extract and encapsulate) exit 1 after the summary when any file failed; --extract skipping non-documents follows in the Studio pass (tool contract, P-CONVERT-EXIT precedent); Studio copy replaced by the engine symbol in the Studio pass (Studio pass: `66bd8c42`, `726957b5`) |
| D272 | dicom-pdf | Sources/dicom-pdf/EncapsulationAttributes.swift | CLI-local PDFEncapsulation ((0042,0015), ISO_IR 192, padding cut, option vocabularies); mirrored by WorkshopPDFEncapsulation. Lift into EncapsulatedDocumentBuilder / EncapsulatedDocumentParser (D182 engine half) | PS3.3 Table C.24-2, Table C.12-1 | Low (duplication) | ✅ 2026-10-06 `98e59069`: PDFEncapsulation lifted into EncapsulatedDocumentBuilder.OptionRules; the extract padding cut follows the engine rule (PS3.3 2026a Table C.24-2, Table C.12-1, Table C.8-24); Studio copy replaced by the engine symbol in the Studio pass (Studio pass: `2bd8e408`) |
| D273 | dicom-image | Sources/dicom-image/main.swift (convertDirectory) | a directory run exits 0 when files failed (only the summary carries the count), unlike dicom-convert (P-CONVERT-EXIT); the Workshop mirrors exit 0 | — (tool contract) | Low | ✅ 2026-10-06 `db10d0f3`: dicom-image directory run exits 1 after the summary when any image failed (non-images skipped) (tool contract, P-CONVERT-EXIT precedent); Studio copy replaced by the engine symbol in the Studio pass (Studio pass: `726957b5`) |
| D274 | dicom-image | Sources/dicom-image/SCOutput.swift | CLI-local P-IMAGE-VR refusals and finalize() ((0002,0003) = (0008,0018), ISO_IR 192); mirrored by WorkshopSCOutput. The engine (ImageConverter) mints two different UIDs for (0002,0003) / (0008,0018) and writes UTF-8 without Specific Character Set, so every caller must post-process — lift both into ImageConverter | PS3.10 Table 7.1-1; PS3.3 Table C.12-1 | Low (duplication; engine gap) | ✅ 2026-10-06 `46f4a61a`: SCOutput lifted into ImageConverter.OutputRules; finalize also covers non-ASCII text in sequence items (PS3.10 2026a Table 7.1-1; PS3.3 Table C.12-1, C.12-5, Table C.8-24; PS3.5 Table 6.2-1, 9.1); Studio copy replaced by the engine symbol in the Studio pass (Studio pass: `2bd8e408`) |
| D275 | dicom-anon | Sources/dicom-anon/AnonCLISupport.swift | CLI-local AnonCLI (profile aliases, notices, E.1-1a action report, (0002,0003) sync, validate texts); DICOMStudio carries a text-identical copy of the legacy-path parts (WorkshopAnonCLI, checked by diff_studio_g1). Lift into DICOMKit next to Anonymizer / AnonConsole so the ps315 path (P-STUDIO-ANON-PS315) can share it too | PS3.15 2026a Annex E; PS3.10 7.1 | Low (duplication) | ✅ 2026-10-06 `b711104e`: AnonCLI lifted into DICOMKit Anonymization (ValidationError is LocalizedError) (PS3.15 2026a E.3, Table E.1-1a; PS3.10 Table 7.1-1); Studio copy replaced by the engine symbol in the Studio pass (Studio pass: `2bd8e408`) |
| D258 | Scripts (orchestrator) | Scripts/diff_studio.py check_workshop_parity / parse_definition | (a) by-flag collapse: `retrieve --format` (MetadataFormat json \| xml) is compared with `ups --format` (OutputFormat) — 3 false FAILs annotated DEFR; (b) cliMapping tokens and non-literal allowedValues are not parsed, so flags emitted through a picker's cliMapping (ups --search / --create-workitem / --subscribe / --unsubscribe, retrieve --uri) need EXEMPT rows. Key options by (subcommand, flag) and count cliMapping tokens as offered | — | Low (tooling) | ✅ 2026-10-06 `4d26acec`: diff_studio parity keyed by (subcommand, flag), cliMapping tokens counted as offered; 4 DEFERRED + 5 EXEMPT rows removed (with D247, D266) (tooling, no NEMA clause) |
| D259 | DICOMStudio (naming) | Sources/DICOMStudio (local `UPSState` and a `DICOMWeb` namespace enum) | DICOMWeb.UPSState cannot be named inside DICOMStudio (shadowed), so the UPS rules carry the state as its PS3.3 Table C.30.1-1 word and resolve the enum contextually at the client call | PS3.3 Table C.30.1-1 | Low (tooling) | ✅ 2026-10-06 `d49d23ac`: WebUPSState (internal alias) names DICOMWeb.UPSState inside DICOMStudio; the Workshop UPS rules hold the enum, not its word (PS3.3 2026a Table C.30.1-1); Studio copy replaced by the engine symbol in the Studio pass (Studio pass: `64a2a74e`) |
| D260 | DICOMStudio (Services) | Sources/DICOMStudio/Services/DICOMwebClientFactory.swift:25 | makeConfiguration has no timeouts parameter, so the Workshop rebuilds the DICOMwebConfiguration to honour `retrieve --timeout` (the field was never read before). A `timeouts:` parameter (defaulted) would remove the rebuild — public-API addition, owner's call | — | Low | ✅ 2026-10-06 `81349178`: DICOMwebClientFactory.makeConfiguration(from:timeouts:); the Workshop passes retrieve --timeout instead of rebuilding the configuration (no NEMA clause) |
| D261 | dicom-send | Sources/dicom-send/SendExecutor.swift (StoreOutcome, SendError) | CLI-local outcome classes and texts copied by the Workshop (checked); `NetworkConsole.sendFileResult(status:rtt:)` already renders the three classes — the CLI and the Workshop could both call it | PS3.4 Table B.2-1 | Low (duplication) | ✅ 2026-10-06 `cf4667c7`: dicom-send success / warning lines rendered through NetworkConsole.CStoreOutcome / sendFileResult(status:rtt:); the failure wording is completed in the Studio pass (PS3.4 2026a Table B.2-1); Studio copy replaced by the engine symbol in the Studio pass (Studio pass: `04aa31ea`, `e4a73d9a`) |
| D262 | dicom-retrieve / dicom-qr | Sources/dicom-retrieve/RetrieveExecutor.swift:470-483, Sources/dicom-qr/DICOMQR.swift:checkRetrieveResult | The two CLIs word the same non-success final response differently ("C-MOVE final response … (counts)" + stderr "Final C-MOVE response: … — counts" vs "Retrieval failed: C-MOVE final response … (counts)" + "  Failed SOP Instance UID List (0008,0058):" block); the Workshop mirrors each. One shared NetworkConsole function would end the drift | PS3.4 Tables C.4-2 / C.4-3 | Low (inconsistency / duplication) | ✅ 2026-10-06 `d7609891`: one NetworkConsole.retrieveFinalResponse for dicom-retrieve and dicom-qr; dicom-qr drops the "Retrieval failed: " prefix, stderr UID list reformatted (PS3.4 2026a Tables C.4-2 / C.4-3; PS3.7 Table 9.3-10); Studio copy replaced by the engine symbol in the Studio pass (Studio pass: `e4a73d9a`) |
| D263 | dicom-mpps | Sources/dicom-mpps/DICOMMPPSCommand.swift (parseStatus, validatePatientSex, validateBirthDate, reportWarning) | CLI-local value rules and warning wording copied by the Workshop (checked); lift into DICOMNetwork MPPSService | PS3.3 Tables C.4-14 / C.2-3; PS3.5 Table 6.2-1 DA | Low (duplication) | ✅ 2026-10-06 `d2812df4`: status, Patient's Sex, birth-date rules and the warning line lifted into DICOMMPPSService (PS3.3 2026a Tables C.4-14, C.2-3; PS3.5 Table 6.2-1 DA); Studio copy replaced by the engine symbol in the Studio pass (Studio pass: `e4a73d9a`) |
| D264 | dicom-mwl | Sources/dicom-mwl/DICOMMWLCommand.swift:156-168 | CLI-local scheduledProcedureStepStatusDefinedTerms / spsStatusWarning copied by the Workshop (checked); lift next to WorklistQueryKeys in DICOMNetwork | PS3.3 Table C.4-10 | Low (duplication) | ✅ 2026-10-06 `29496ff0`: WorklistQueryKeys.scheduledProcedureStepStatusDefinedTerms / spsStatusWarning (PS3.3 2026a Table C.4-10); Studio copy replaced by the engine symbol in the Studio pass (Studio pass: `e4a73d9a`) |
| D265 | dicom-wado | Sources/dicom-wado/WADOOptionRules.swift | CLI-local rules (contentType, frameNumber, parameter warnings, paging, UPS Change State refusal, --update alias, timeouts); DICOMStudio carries a text-identical copy (WorkshopWADOOptionRules, equality checked by diff_studio_g1 "net web rules"). Lift into DICOMWeb (next to WADOURIClient / UPSConsole) so both surfaces share one source | PS3.18 9.1.2.2.1, 9.5.1.2.1, 8.3.4.4, 11.7.1.4 | Low (duplication) | ✅ 2026-10-06 `87bbcbf8`: dicom-wado rules lifted into DICOMWeb DICOMwebOptionRules (WADO-URI contentType / frameNumber / region / annotation / warnings, QIDO paging, --update alias, timeouts) (PS3.18 2026a 9.1.2.2.1, 9.4.1.2.2, 9.5.1.2.1, 8.3.4.4, 11.7, Table 8.7.4-1); Studio copy replaced by the engine symbol in the Studio pass (Studio pass: `64a2a74e`) |
| D256 | Package.swift | Package.swift:189 | `dicom-cloud` product is commented out ("Phase 1 scope") while Sources/dicom-cloud exists and Studio lists it as shipped | — | low (note) | ⏳ — left open by owner decision 2026-10-06 |
| D257 | DICOMStudio (G1, ShellServerConfigHelpers — another agent's file, already marked) | Sources/DICOMStudio/Components/ShellServerConfigHelpers.swift:457 | `dicomParameters(from:)` injects the server host as `--host`, but every DIMSE tool (dicom-echo/query/send/retrieve/qr/mwl/mpps) takes the host as a positional `<host>` argument; a generated command `dicom-echo --host pacs` is refused by ArgumentParser | CLI surface (diff_cli --list-surface), not a NEMA clause | medium | ✅ 2026-10-06 `62b76e1e`: test only: the host has been positional since `490e18d3`; the generated command is checked against the 7 DIMSE tool surfaces (CLI surface, no NEMA clause) |
| D254 | DICOMWeb | Sources/DICOMWeb/UPS/UPSEvent.swift:3 (marker) | Marker still says the event-type strings / bare-name keys are "pending owner approval (P-EVENT)" although the report records P-EVENT as approved and applied (df9d92b) and `toDICOMJSON` now nests progress under (0074,1002). Marker text is stale | PS3.4 Table CC.2.4-1 | docs | ✅ 2026-10-06 `c9bad73e`: UPSEvent marker re-checked; P-EVENT no longer named as pending (PS3.4 2026a Table CC.2.4-1) |
| D255 | dicom-wado / DICOMWeb | Sources/dicom-wado/WADOOptionRules.swift:124-141 (`changeStateTargets`, `changeStateTarget`) | The Change-State target rule and its refusal text are CLI-local; Studio now carries a second copy of the message (`DICOMwebUPSHelpers.changeStateRefusal`), kept identical by `diff_studio_g3_web.py`. Lift the rule into DICOMWeb (e.g. `UPSState.changeStateTargets` + a shared refusal string next to `UPSState.isValidTransition`) so both front ends use one source | PS3.18 2026a 11.7.1.4; PS3.4 Table CC.1.1-2 | low (duplication, guarded by script) | ✅ 2026-10-06 `f4b3bddd`: UPSState.changeStateTargets / changeStateRefusal / init(optionValue:) / changeStateTarget(optionValue:) and DICOMwebOptionRefusal in DICOMWeb (PS3.18 2026a 11.7.1.4; PS3.4 Table CC.1.1-2); Studio copy replaced by the engine symbol in the Studio pass (Studio pass: `64a2a74e`) |
| D247 | Scripts (orchestrator) | Scripts/diff_studio.py check_workshop_parity | `by_name` keys CLI options by flag, so an option several subcommands declare (study --format, export --format) is compared with the last one (compare --format text, bulk --format png); the two false FAILs (summary --format table, single --format jpeg — both correct) are marked DEFR by diff_studio_g1.DEFERRED. Key by (subcommand, flag) | — | Low (tooling) | ✅ 2026-10-06 `4d26acec`: diff_studio parity keyed by (subcommand, flag); cliMapping tokens counted, [""] + Expr pickers parsed; 4 DEFERRED + 5 EXEMPT rows removed (with D258, D266) (tooling, no NEMA clause) |
| D248 | dicom-validate | Sources/dicom-validate/IODOption.swift | CLI-local SOP Class → engine IOD name map copied by the Workshop (validateEngineNameBySOPClassUID; equality checked by diff_studio_g1); DICOMValidator should export it | PS3.6 Table A-1 | Low (duplication) | ✅ 2026-10-06 `923c496e`: SOP Class → IOD name map lifted into DICOMValidator.iodNameBySOPClassUID / iodName(forIODOption:) / sopClassUID(forIODOption:), 7/7 UIDs checked (PS3.6 2026a Table A-1); Studio copy replaced by the engine symbol in the Studio pass (Studio pass: `2bd8e408`) |
| D249 | dicom-archive | Sources/dicom-archive/QueryKeys.swift | CLI-local --study-date warning copied by the Workshop (checked); lift next to ArchiveMatching | PS3.4 C.2.2.2.5.1 | Low (duplication) | ✅ 2026-10-06 `2182f73d`: --study-date warning lifted into ArchiveMatching.studyDateKeyWarning (PS3.4 2026a C.2.2.2.5.1); Studio copy replaced by the engine symbol in the Studio pass (Studio pass: `2bd8e408`) |
| D250 | dicom-uid | Sources/dicom-uid/UIDOptions.swift | CLI-local UIDRootRule texts copied by the Workshop (uidRootProblems; checked by diff_studio_g1); lift into DICOMKit UIDManager / UIDConsole | PS3.5 9.1 | Low (duplication) | ✅ 2026-10-06 `aeab8202`: UID root rule lifted into UIDManager.RootRule (PS3.5 2026a 9.1); Studio copy replaced by the engine symbol in the Studio pass (Studio pass: `2bd8e408`) |
| D251 | dicom-export | Sources/dicom-export/main.swift (Bulk.run, after the summary line) | `bulk` exits 0 when files failed (only the summary line carries the count), unlike dicom-convert's directory run (exit 1 after the codec batch). The Workshop mirrors exit 0 | — (tool contract) | Low | ✅ 2026-10-06 `fbf25c1f`: dicom-export bulk exits 1 after the summary when any file failed (files without pixel data are skipped), like dicom-convert's directory run (tool contract, P-CONVERT-EXIT precedent); Studio copy replaced by the engine symbol in the Studio pass (Studio pass: `726957b5`) |
| D252 | dicom-export | Sources/dicom-export/ExportStandard.swift | CLI-local CineFrameRate / ExportFrameSelection / BurnedInAnnotation / ExportApplyWindowDeprecation; DICOMStudio copies the texts and the rate resolution (checked by diff_studio_g1). Lift into DICOMKit DICOMImageExporter | PS3.3 Table C.7-13, Table 10-3, Table C.7-9 | Low (duplication) | ✅ 2026-10-06 `be267a71`: ExportStandard lifted into DICOMImageExporter.CineFrameRate / BurnedInAnnotation / FrameSelection / FrameSelectionConflict / ApplyWindowDeprecation (PS3.3 2026a Table C.7-13, Table C.7-9, Table 10-3); Studio copy replaced by the engine symbol in the Studio pass (Studio pass: `2bd8e408`) |
| D253 | dicom-dcmdir | Sources/dicom-dcmdir/FileSetRules.swift | CLI-local; DICOMStudio carries a text-identical copy (WorkshopFileSetRules, equality checked by diff_studio_g1). Lift into DICOMKit (e.g. next to DICOMDIRWorkflow) so both surfaces share one source | PS3.10 8.1, 8.2, 8.5, 8.6 | Low (duplication) | ✅ 2026-10-06 `6adbe40e`: File-set rules lifted into DICOMKit DICOMDIRFileSetRules (PS3.10 2026a 8.1, 8.2, 8.5, 8.6); Studio copy replaced by the engine symbol in the Studio pass (Studio pass: `2bd8e408`) |
| D244 | (none else) | | | | | — void: number reserved by the pass, no finding (audit 2026-10-06) |
| D245 | DICOMKit | Sources/DICOMKit/Anonymization/Anonymizer.swift:30-47 (basicProfileTags) | The `.basic` legacy profile (dicom-anon `legacy-basic`, Studio "Basic" / "HIPAA Safe Harbor") removes 14 attributes only; it leaves Other Patient IDs Sequence, Patient's Address, telephone numbers, Patient's Age / Sex / Ethnic Group, Accession Number, Study ID, dates and all UIDs. Already known not to be PS3.15 Annex E (P-ANON-PROFILE / P-STUDIO-ANON-PS315); recorded here because the Studio UI now states exactly this list | PS3.15 2026a Table E.1-1 | low (documented legacy behaviour) | ✅ 2026-10-06 `005b5ec4`: AnonymizationProfile.basic documented: 14 Table E.1-1 rows removed, 641 untouched, not Annex E (PS3.15 2026a Table E.1-1) |
| D243 | DICOMKit | `Sources/DICOMKit/DICOMFile+PixelData.swift:315` `renderFrame(_:window:)`, `:342` `renderFrameWithStoredWindow`, `:359` `tryRenderFrameWithStoredWindow` | The convenience renderers hand the header's Window Center/Width (modality units) to `PixelDataRenderer.renderMonochromeFrame(_:window:)`, which applies it to stored values — the D65 defect, still present on this public path (export and the viewer were fixed around it). Any caller gets a window misplaced by the Rescale Intercept (a CT at −1024 washes out). Route through `GrayscaleDisplayPipeline` / `renderMonochromeFrame(_:pipeline:)` | PS3.3 C.11.2.1.2.1; PS3.4 N.2 | Medium | ✅ 2026-10-06 `15e74ebc`: DICOMFile renderFrame / tryRenderFrame / renderFrameWithStoredWindow / tryRenderFrameWithStoredWindow apply the window after the Modality LUT through GrayscaleDisplayPipeline (window in modality units); DICOMImageExporter.determineModalityWindow added, determineWindowSettings deprecated (A6, D65 engine half); diff_renderkit 0 deferred (PS3.3 2026a C.11.2.1.2.1; PS3.4 N.2); Studio copy replaced by the engine symbol in the Studio pass (Studio pass: `123b81a5`) |
| D246 | (none in DICOMKit/DICOMCore from this pass) | | | | | — void: number reserved by the pass, no finding (audit 2026-10-06) |
| D242 | DICOMPrintKit | Sources/DICOMPrintKit/PrintOptionCatalog.swift:217 | `filmDestinations` offers only MAGAZINE, PROCESSOR, BIN_1, BIN_2; the dicom-print CLI therefore cannot name a bin above 2 although `FilmDestination.bin(n)` exists (Studio works around it with its own bin-number field) | PS3.3 2026a C.13.1 Table C.13-1 (BIN_i, "no maximum is placed on the number of BINs") | Low | ✅ 2026-10-06 `f1ba662b`: FilmDestination(catalogToken:) accepts any BIN_i; dicom-print --film-destination parses through it, the pickers keep the four defaults (PS3.3 2026a Table C.13-1); Studio copy replaced by the engine symbol in the Studio pass (Studio pass: `a169450e`) |

---

## Workshop ↔ CLI parity (G1)

One subsection per Workshop tool, filled as each is verified: the parity table from `diff_studio.py --emit-parity
<tool>` (Workshop parameter, CLI option, DICOM concept, 2026a reference, values and defaults on both sides, verdict),
the output parity (what the executor prints or returns against the CLI's shared console functions), the findings and
their commits. Handed-over follow-ups from DICOMCLI_STANDARD_IMPLEMENTATION.md "Rows handed to DICOMStudio" parts 3
and 4 are closed in the tool they belong to.

### dicom-info → dicom-info

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `inputPath` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `format` (enumPicker) | `--format` | output format | — (JSON is not PS3.18 F and does not claim it) | text, json, csv / text | `OutputFormat` / .text | match |
| `tag` (textField) | `--tag` | Attribute selection | PS3.6 Tables 6-1/7-1 (name, keyword, tag) |  | `[String]` / [] | match |
| `show-private` (booleanToggle) | `--show-private` | Private Data Elements (odd group) | PS3.5 7.8, 7.8.1 |  | `Bool` / false | match |
| `statistics` (booleanToggle) | `--statistics` | Transfer Syntax UID, SOP Class UID, Modality | PS3.10 Table 7.1-1; PS3.6 Table A-1 names |  | `Bool` / false | match |
| `force` (booleanToggle) | `--force` | read a file without preamble/"DICM" | PS3.10 7.1 |  | `Bool` / false | match |

Output parity: the executor reads through DICOMFile.read and prints through the shared DICOMKit console the CLI uses; a missing file is refused with the CLI's text and ArgumentParser's exit 64 (was 1). No standard data of its own.

### dicom-dump → dicom-dump

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `inputPath` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `tag` (textField) | `--tag` | Data Element Tag | PS3.5 7.1.1; PS3.6 Tables 6-1/7-1 keywords |  | `String?` | match |
| `offset` (textField) | `--offset` | byte offset into the file | — |  | `String?` | match |
| `length` (integerField) | `--length` | bytes to dump | — |  | `Int?` | match |
| `bytes-per-line` (enumPicker) | `--bytes-per-line` | hex line width | — | 8, 16, 32 / 16 | `Int` / 16 | match |
| `highlight` (textField) | `--highlight` | Data Element Tag | PS3.5 7.1.1; PS3.6 Tables 6-1/7-1 keywords |  | `String?` | match |
| `no-color` (booleanToggle) | `--no-color` | ANSI colour off | — | false | `Bool` / false | match |
| `annotate` (booleanToggle) | `--annotate` | tag, VR, length, PS3.6 keyword per element | PS3.5 7.1.2 / Table 6.2-1; PS3.6 Tables 6-1/7-1 |  | `Bool` / false | match |
| `verbose` (booleanToggle) | `--verbose` | VR and Value Length (undefined = FFFFFFFFH) | PS3.5 7.1.1, 7.1.2 |  | `Bool` / false | match |
| `force` (booleanToggle) | `--force` | read a file without preamble/"DICM" | PS3.10 7.1 |  | `Bool` / false | match |

Output parity: the whole-file HexDumper call of the CLI (annotations / highlight found from the file start, D144), the CLI's tag grammar (0010,0010 / (0010,0010) / 00100010 / PS3.6 keyword, PS3.5 7.1.1) and its refusal text 'Invalid tag format: … Use format: 0010,0010 or a PS3.6 keyword such as PatientName' (exit 1), 'Invalid hex offset' / 'Invalid offset' (exit 1), the --verbose 'Could not parse DICOM structure' warning, the final newline of print(); --no-color default is now the CLI's (off) and the in-app console strips ANSI itself.

### dicom-tags → dicom-tags

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `inputPath` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `list-modalities` (booleanToggle) | `--list-modalities` | Modality (0008,0060) Defined Terms | PS3.3 C.7.3.1.1.1 |  | `Bool` / false | match |
| `output` (outputPath) | `--output` | output path | — |  | `String?` | match |
| `set` (textField) | `--set` | Attribute value | PS3.6 Table 6-1 keyword/VR; PS3.5 Table 6.2-1 limits; PS3.10 7.1 group 0002; PS3.5 7.8.1 |  | `[String]` / [] | match |
| `delete` (textField) | `--delete` | remove Attribute | PS3.6 keywords; PS3.10 7.1 |  | `[String]` / [] | match |
| `delete-private` (booleanToggle) | `--delete-private` | remove Private Data Elements | PS3.5 7.8, 7.8.1 |  | `Bool` / false | match |
| `copy-from` (filePath) | `--copy-from` | source file | PS3.10 7.1 |  | `String?` | match |
| `tags` (textField) | `--tags` | Attributes to copy | PS3.6 keywords; PS3.10 7.1 |  | `String?` | match |
| `verbose` (booleanToggle) | `--verbose` | change lines | — |  | `Bool` / false | match |
| `dry-run` (booleanToggle) | `--dry-run` | preview | — |  | `Bool` / false | match |

Output parity: --list-modalities prints ModalityOptionValidator.listing() (PS3.3 C.7.3.1.1.1 Defined Terms) with no input; edits go through TagEditor.applyCheckedChanges (TagEditRules: PS3.5 Table 6.2-1 limits, group 0002 refused per PS3.10 7.1), with TagEditorError texts and exit 1; the missing positional is ArgumentParser's message (exit 64).

### dicom-diff → dicom-diff

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `file1` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `file2` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `format` (enumPicker) | `--format` | report rendering |  | text, json, summary / text | `ComparisonOutputFormat` / .text | match |
| `ignore-tag` (textField) | `--ignore-tag` | Data Element Tag / keyword to skip | PS3.6 Table 6-1 (Tag, Keyword); PS3.5 7.1.1 |  | `[String]` / [] | match |
| `ignore-private` (booleanToggle) | `--ignore-private` | skip Private Data Elements | PS3.5 7.1 / 7.8.1 (odd group, not 0001/0003/0005/0007/FFFF) |  | `Bool` / false | match |
| `compare-pixels` (booleanToggle) | `--compare-pixels` | compare Pixel Data (7FE0,0010) separately | PS3.6 Table 6-1; PS3.5 8.1.1 / 8.2 |  | `Bool` / false | match |
| `tolerance` (integerField) | `--tolerance` | largest per-byte difference treated as equal | PS3.5 8.1.1 (pixel cells of Bits Allocated) | 0 | `Double` / 0.0 | match |
| `quick` (booleanToggle) | `--quick` | metadata only |  |  | `Bool` / false | match |
| `show-identical` (booleanToggle) | `--show-identical` | list identical elements |  |  | `Bool` / false | match |
| `verbose` (booleanToggle) | `--verbose` |  |  |  | `Bool` / false | match |

Output parity: DICOMComparer + ComparisonReport (shared); exit 0 identical / 1 different / 2 'dicom-diff: error: File not found: …' or 'Cannot read … as DICOM: …' or 'Comparison failed' / 64 for an invalid --ignore-tag (the CLI's parseTag grammar); --verbose header and the trailing newline of print().

### dicom-json → dicom-json

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `inputPath` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `output` (outputPath) | `--output` | output path; default <input>.json / .dcm |  |  | `String?` | match |
| `reverse` (booleanToggle) | `--reverse` | DICOM JSON Model -> PS3.10 file; Transfer Syntax from (0002,0010) else Explicit VR Little Endian | PS3.18 F.2; PS3.6 Table A-1 1.2.840.10008.1.2.1 |  | `Bool` / false | match |
| `pretty` (booleanToggle) | `--pretty` | whitespace only | PS3.18 F.2 (RFC 8259) |  | `Bool` / false | match |
| `no-sort-keys` (booleanToggle) | `--no-sort-keys` | attribute-object order | PS3.18 F.2.2 ("shall be ordered ... ascending lexicographic") |  | `Bool` / false | match |
| `include-empty` (booleanToggle) | `--include-empty` |  |  | true | `Bool` / true | match |
| `metadata-only` (booleanToggle) | `--metadata-only` | omit Pixel Data (7FE0,0010) | PS3.18 10.4.1.1.2 / 10.4.3.3.2 Metadata resource (all attributes, bulk data as BulkDataURI) |  | `Bool` / false | match |
| `inline-threshold` (integerField) | `--inline-threshold` | InlineBinary vs BulkDataURI for OB/OD/OF/OL/OV/OW/UN | PS3.18 F.2.2, F.2.6, F.2.7; 10.4.3.3.2 | 1024 | `Int` / 1024 | match |
| `bulk-data-url` (textField) | `--bulk-data-url` | BulkDataURI base | PS3.18 F.2.6 -> PS3.19 Table A.1.5-2 BulkData uri |  | `String?` | match |
| `filter-tag` (arrayField) | `--filter-tag` | attribute selection | PS3.6 Table 6-1 keyword; PS3.18 F.2.2 attribute name |  | `[String]` / [] | match |
| `verbose` (booleanToggle) | `--verbose` |  |  |  | `Bool` / false | match |

Output parity: DataExchangeWorkflow (shared) with includeEmpty on by default (PS3.18 F.2.5) and --no-include-empty, the CLI's 'dicom-json: warning: --no-sort-keys is deprecated …' stderr note, --filter-tag accepting (GGGG,EEEE) and GGGGEEEE (F.2.2), 'dicom-json: Warning: …' prefix on reverse warnings, WorkflowError as exit 64 (ValidationError), missing file 'Error: File not found' exit 64.

### dicom-xml → dicom-xml

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `input` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `output` (outputPath) | `--output` | output path; default <input>.xml / .dcm |  |  | `String?` | match |
| `reverse` (booleanToggle) | `--reverse` | Native DICOM Model -> PS3.10 file; Transfer Syntax from (0002,0010) else Explicit VR Little Endian | PS3.19 A.1; PS3.6 Table A-1 1.2.840.10008.1.2.1 |  | `Bool` / false | match |
| `pretty` (booleanToggle) | `--pretty` | indentation only (xml:space="preserve" kept) | PS3.19 Table A.1.5-1 |  | `Bool` / false | match |
| `no-keywords` (booleanToggle) | `--no-keywords` | DicomAttribute keyword attribute | PS3.19 Table A.1.5-2 (keyword C: "Required unless ... unknown to the host") |  | `Bool` / false | match |
| `include-empty` (booleanToggle) | `--include-empty` |  |  | true | `Bool` / true | match |
| `inline-threshold` (integerField) | `--inline-threshold` | InlineBinary vs BulkData for OB/OD/OF/OL/OV/OW/UN | PS3.19 Table A.1.5-2 InlineBinary / BulkData | 1024 | `Int` / 1024 | match |
| `bulk-data-url` (textField) | `--bulk-data-url` | BulkData uri base | PS3.19 Table A.1.5-2 >>uri ("Required if ... WADO-RS Retrieve Metadata ... Shall not be present otherwise"), >>uuid |  | `String?` | match |
| `metadata-only` (booleanToggle) | `--metadata-only` | omit Pixel Data (7FE0,0010) | PS3.18 10.4.1.1.2 / 10.4.3.3.2 |  | `Bool` / false | match |
| `filter-tag` (arrayField) | `--filter-tag` | attribute selection | PS3.6 Table 6-1 keyword; PS3.19 Table A.1.5-2 tag form |  | `[String]` / [] | match |
| `verbose` (booleanToggle) | `--verbose` |  |  |  | `Bool` / false | match |

Output parity: as dicom-json with PS3.19 Table A.1.5-2 (includeEmpty on, --no-include-empty, 'dicom-xml: warning: --no-keywords is deprecated …').

### dicom-validate → dicom-validate

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `inputPath` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `level` (enumPicker) | `--level` | validation depth | PS3.10 Table 7.1-1; PS3.5 Table 6.2-1, 9.1; PS3.3 IOD/module tables; PS3.5 7.4.1-7.4.4 | 1, 2, 3, 4, 5 / 3 | `Int` / 3 | match |
| `iod` (textField) | `--iod` | IOD / SOP Class | PS3.6 Table A-1 keywords; PS3.3 Annex A |  | `String?` | match |
| `detailed` (booleanToggle) | `--detailed` | output | - |  | `Bool` / false | match |
| `recursive` (booleanToggle) | `--recursive` | directory walk | - |  | `Bool` / false | match |
| `strict` (booleanToggle) | `--strict` | warnings -> exit 2 | - |  | `Bool` / false | match |
| `format` (enumPicker) | `--format` | output | - | text, json / text | `ValidationOutputFormat` / .text | match |
| `output` (outputPath) | `--output` | report path | - |  | `String?` | match |
| `force` (booleanToggle) | `--force` | read without DICM prefix | PS3.10 7.1 |  | `Bool` / false | match |

Output parity: the executor now runs dicom-validate's own loop — DICOMValidator (shared), FileGatherer.regularFiles, ValidationReport.render / exitCode (0 / 1 / 2 with --strict), OutputPathResolver.resolveFileOutput for a directory --output — with the CLI's refusals as exit 64 ('Input path not found', 'Validation level must be between 1 and 5', 'Directory validation requires --recursive flag'); --iod takes PS3.6 Table A-1 keywords / UIDs through the same map as dicom-validate's IODOption (equality checked by diff_studio_g1).

### dicom-split → dicom-split

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `inputPath` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `output` (outputPath) | `--output` | output directory |  |  | `String` / "." | match |
| `frame-numbers` (textField) | `--frame-numbers` |  |  |  | `String?` | match |
| `frames` (textField) | `--frames` | frames to extract | PS3.3 C.7.6.16.1.2 ("Frames are implicitly numbered starting from 1"); Table 10-3 Referenced Frame Number (0008,1160) |  | `String?` | match |
| `format` (enumPicker) | `--format` | output container |  | dicom, png, jpeg, tiff / dicom | `SplitOutputFormat` / .dicom | match |
| `apply-window` (booleanToggle) | `--apply-window` | apply VOI LUT window to image output | PS3.3 C.11.2.1.2 |  | `Bool` / false | match |
| `window-center` (textField) | `--window-center` | Window Center (0028,1050) override | PS3.3 C.11.2.1.2; PS3.6 Table 6-1 |  | `Double?` | match |
| `window-width` (textField) | `--window-width` | Window Width (0028,1051) override | PS3.3 C.11.2.1.2; PS3.6 Table 6-1 |  | `Double?` | match |
| `pattern` (textField) | `--pattern` | output file naming | PS3.6 Table 6-1 (Instance Number, Stack ID, Modality, Series Number) |  | `String?` | match |
| `target` (enumPicker) | `--target` | SOP Class of the extracted frames | PS3.6 Table A-1; PS3.3 A.38/A.70-A.72 vs single-frame IODs | auto | `SplitTargetPolicy` / .auto | match |
| `pixel-handling` (enumPicker) | `--pixel-handling` | encapsulated frame handling | PS3.5 8.2, A.4 (fragments per frame, Basic Offset Table); Table A-1 Explicit VR Little Endian | preserve | `MultiframePixelHandling` / .preserve | match |
| `private-groups` (enumPicker) | `--private-groups` | private Sequences inside functional group items | PS3.3 C.7.6.16 | flatten | `PrivateFunctionalGroupPolicy` / .flatten | match |
| `instance-number` (enumPicker) | `--instance-number` | Instance Number (0020,0013) of each output | PS3.3 C.7.6.1; C.7.6.16.2.2 In-Stack Position Number (0020,9057) | frame | `SplitInstanceNumbering` / .frame | match |
| `split-by` (enumPicker) | `--split-by` | one series per Frame Content value | PS3.3 C.7.6.16.2.2 Stack ID (0020,9056), Temporal Position Index (0020,9128) | none | `SplitSeriesGrouping` / .none | match |
| `new-series` (booleanToggle) | `--new-series` | new Series Instance UID (0020,000E) | PS3.3 C.7.3.1 |  | `Bool` / false | match |
| `frames-per` (textField) | `--frames-per` | Concatenation parts of N frames | PS3.3 7.5.1; C.7.6.16 Concatenation UID / In-concatenation Number / In-concatenation Total Number / Concatenation Frame Offset Number / SOP Instance UID of Concatenation Source |  | `Int?` | match |
| `random-uids` (booleanToggle) | `--random-uids` | random vs derived SOP / Series Instance UIDs | PS3.5 9.1 (2.25 UUID-derived UIDs) |  | `Bool` / false | match |
| `recursive` (booleanToggle) | `--recursive` |  |  |  | `Bool` / false | match |
| `verbose` (booleanToggle) | `--verbose` |  |  |  | `Bool` / false | match |

Output parity: SplitMergeWorkshopCLIParityTests runs every option combination on both surfaces (32 split cases x verbose on/off, incl. 6 new --frame-numbers / conflict cases) and compares console text, written files and outcome: all pass against .build/release/dicom-split. --frame-numbers (SplitConsole.parseFrameNumberSelection, headerLines(frameNumbers:)), SplitConsole.framesDeprecatedLine for --frames, framesAndFrameNumbersConflictMessage (exit 1), ValidationErrors as 64.

### dicom-merge → dicom-merge

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `inputPath` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `output` (outputPath) | `--output` | output file (file level) or directory (series/study) |  |  | `String` | match |
| `format` (enumPicker) | `--format` | SOP Class of the merged object | PS3.6 Table A-1; PS3.3 A.38 (Enhanced CT), A.70-A.72 (Legacy Converted) | standard | `MergeFormat` / .standard | match |
| `pixel-handling` (enumPicker) | `--pixel-handling` | encapsulated frame handling | PS3.5 8.2, A.4 (one fragment per frame, Basic Offset Table); Table A-1 Explicit VR Little Endian | preserve | `MultiframePixelHandling` / .preserve | match |
| `make-stacks` (booleanToggle) | `--make-stacks` | Stack ID (0020,9056) per Image Orientation (Patient) (0020,0037) | PS3.3 C.7.6.16.2.2 |  | `Bool` / false | match |
| `temporal-position` (booleanToggle) | `--temporal-position` | Temporal Position Index (0020,9128) | PS3.3 C.7.6.16.2.2; source Trigger Time (0018,1060) / Temporal Position Identifier (0020,0100) / Acquisition Time (0008,0032) |  | `Bool` / false | match |
| `new-series` (booleanToggle) | `--new-series` | new Series Instance UID (0020,000E) | PS3.3 C.7.3.1 |  | `Bool` / false | match |
| `allow-any-source` (booleanToggle) | `--allow-any-source` | skip the source SOP Class check | PS3.6 Table A-1 |  | `Bool` / false | match |
| `level` (enumPicker) | `--level` | grouping of inputs | PS3.3 C.7.2.1 Study Instance UID, C.7.3.1 Series Instance UID | file, series, study / file | `MergeLevel` / .file | match |
| `sort-by` (enumPicker) | `--sort-by` | frame order key | PS3.6 Table 6-1 keywords | MergeSortCriteria.instanceNumber.rawValue | `MergeSortCriteria` / .instanceNumber | match |
| `order` (enumPicker) | `--order` | sort direction |  | ascending, descending / ascending | `MergeSortOrder` / .ascending | match |
| `validate` (booleanToggle) | `--validate` | identity consistency check | PS3.6 Table 6-1 (Study/Series Instance UID, Modality, Frame of Reference UID) |  | `Bool` / false | match |
| `recursive` (booleanToggle) | `--recursive` |  |  |  | `Bool` / false | match |
| `verbose` (booleanToggle) | `--verbose` |  |  |  | `Bool` / false | match |

Output parity: SplitMergeWorkshopCLIParityTests merge matrix passes; the sort-by picker is MergeSortCriteria (shared enum); refusals carry MergeConsole texts and ArgumentParser exit 64.

### dicom-dcmdir → dicom-dcmdir

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `subcommand` (subcommand) | `—` |  |  | create, validate, dump, update / create | `—` | not a CLI option |
| `inputDirectory` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `output` (outputPath) | `--output` |  |  |  | `String?` | match |
| `fileSetID` (textField) | `--file-set-id` |  |  |  | `String?` | match |
| `profile` (enumPicker) | `--profile` |  |  | STD-GEN-CD | `String` / "STD-GEN-CD" | match |
| `recursive` (booleanToggle) | `--recursive` |  |  | true | `Bool` / true | match |
| `strict` (booleanToggle) | `--strict` |  |  |  | `Bool` / false | match |
| `copyTo` (outputPath) | `--copy-to` |  |  |  | `String?` | match |
| `createVerbose` (booleanToggle) | `--verbose` |  |  |  | `Bool` / false | match |
| `dicomdirPath` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `checkFiles` (booleanToggle) | `--check-files` |  |  |  | `Bool` / false | match |
| `detailed` (booleanToggle) | `--detailed` |  |  |  | `Bool` / false | match |
| `format` (enumPicker) | `--format` |  |  | tree, json, text / tree | `String` / "tree" | match |
| `dumpVerbose` (booleanToggle) | `--verbose` |  |  |  | `Bool` / false | match |
| `add` (filePath) | `--add` |  |  |  | `String?` | match |
| `updateVerbose` (booleanToggle) | `--verbose` |  |  |  | `Bool` / false | match |

Output parity: create / validate / dump / update follow dicom-dcmdir's run() line by line — DICOMDIRWorkflow (shared build, --copy-to, summary), the File-set ID default and 'Refusing --file-set-id: …' (exit 1, PS3.10 8.1/8.5), 'Invalid profile: … Use a PS3.11 Application Profile identifier: <DICOMDIRProfile.allStandard>' (exit 64), the 'dicom-dcmdir: warning: --profile … is deprecated' note, 'no file could be indexed; no DICOMDIR written' (exit 1), 'Warning: N file(s) not indexed'; validate prints the File ID / File-set ID findings with their PS3.10 8.1/8.2/8.5/8.6 and PS3.3 Table F.3-3 clauses (exit 1) via WorkshopFileSetRules, text-identical to the CLI's FileSetRules (checked by diff_studio_g1); 'DICOMDIR file not found' / 'No DICOMDIR found in directory' exit 64.

### dicom-archive → dicom-archive

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `subcommand` (subcommand) | `—` |  |  | init, import, query, list, export, check, stats / list | `—` | not a CLI option |
| `archive` (filePath) | `--archive` |  |  |  | `String` | match |
| `path` (outputPath) | `--path` |  |  |  | `String` | match |
| `force` (booleanToggle) | `--force` |  |  |  | `Bool` / false | match |
| `files` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `recursive` (booleanToggle) | `--recursive` |  |  |  | `Bool` / false | match |
| `skip-duplicates` (booleanToggle) | `--skip-duplicates` |  |  |  | `Bool` / false | match |
| `patient-name` (textField) | `--patient-name` |  |  |  | `String?` | match |
| `patient-id` (textField) | `--patient-id` |  |  |  | `String?` | match |
| `study-uid` (textField) | `--study-uid` |  |  |  | `String?` | match |
| `series-uid` (textField) | `--series-uid` |  |  |  | `String?` | match |
| `modality` (textField) | `--modality` |  |  |  | `String?` | match |
| `strict-modality` (booleanToggle) | `--strict-modality` |  |  |  | `Bool` / false | match |
| `study-date` (textField) | `--study-date` |  |  |  | `String?` | match |
| `output` (outputPath) | `--output` |  |  |  | `String` | match |
| `flatten` (booleanToggle) | `--flatten` |  |  |  | `Bool` / false | match |
| `show-instances` (booleanToggle) | `--show-instances` |  |  |  | `Bool` / false | match |
| `verify-files` (booleanToggle) | `--verify-files` |  |  |  | `Bool` / false | match |
| `format` (enumPicker) | `--format` |  |  | table, tree, text, json | `String` / "text" | match |
| `verbose` (booleanToggle) | `--verbose` |  |  |  | `Bool` / false | match |

Output parity: ArchiveStore (shared) for every subcommand; query runs --modality through DICOMCore.ModalityOptionValidator exactly as the CLI ('warning: … Sending it as-is.' or 'Error: … Rejected because --strict-modality is set.' exit 1), prints the --study-date warning of ArchiveQueryKeys (text-identical), and ArchiveError is exit 64 (ValidationError) as in runArchive; missing --archive / --path / --output are ArgumentParser's messages (64).

### dicom-study → dicom-study

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `operation` (subcommand) | `—` |  |  | organize, summary, check, stats, compare / organize | `—` | not a CLI option |
| `input` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `output` (outputPath) | `--output` |  |  |  | `String` | match |
| `pattern` (enumPicker) | `--pattern` |  |  | descriptive, uid / descriptive | `String` / "descriptive" | match |
| `copy` (booleanToggle) | `--copy` |  |  | false | `Bool` / false | match |
| `path` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `summary-format` (enumPicker) | `--format` |  |  | table, json, csv / table | `String` / "text" | match |
| `expected-series` (integerField) | `--expected-series` |  |  |  | `Int?` | match |
| `expected-instances` (integerField) | `--expected-instances` |  |  |  | `Int?` | match |
| `report` (outputPath) | `--report` |  |  |  | `String?` | match |
| `detailed` (booleanToggle) | `--detailed` |  |  | false | `Bool` / false | match |
| `stats-format` (enumPicker) | `--format` |  |  | text, json / text | `String` / "text" | match |
| `path1` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `path2` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `compare-format` (enumPicker) | `--format` |  |  | text, json / text | `String` / "text" | match |
| `verbose` (booleanToggle) | `--verbose` |  |  | false | `Bool` / false | match |

Output parity: StudyOrganizer / StudyScanner / StudyReport (shared) print every label and the PS3.6 keyword JSON/CSV keys; the Workshop no longer sends --copy by default (the CLI moves files), the three --format pickers keep their subcommand's default (table / text / text), missing positionals are ArgumentParser's messages (64), StudyError texts exit 1.

### dicom-uid → dicom-uid

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `subcommand` (subcommand) | `—` |  |  | generate, validate, lookup, regenerate / generate | `—` | not a CLI option |
| `count` (integerField) | `--count` |  |  | 1 | `Int` / 1 | match |
| `type` (enumPicker) | `--type` |  |  | generic, study, series, instance, sop / generic | `String?` | match |
| `root` (textField) | `--root` |  |  |  | `String?` | match |
| `uuid` (booleanToggle) | `--uuid` |  |  |  | `Bool` / false | match |
| `json` (booleanToggle) | `--json` |  |  |  | `Bool` / false | match |
| `uids` (arrayField) | `—` |  |  |  | `—` | not a CLI option |
| `file` (filePath) | `--file` |  |  |  | `String?` | match |
| `check-registry` (booleanToggle) | `--check-registry` |  |  |  | `Bool` / false | match |
| `lookup-uid` (textField) | `—` |  |  |  | `—` | not a CLI option |
| `list-all` (booleanToggle) | `--list-all` |  |  |  | `Bool` / false | match |
| `lookup-type` (enumPicker) | `--type` |  |  |  | `String?` | match |
| `search` (textField) | `--search` |  |  |  | `String?` | match |
| `inputPath` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `output` (outputPath) | `--output` |  |  |  | `String?` | match |
| `maintain-relationships` (booleanToggle) | `--maintain-relationships` |  |  |  | `Bool` / false | match |
| `export-map` (outputPath) | `--export-map` |  |  |  | `String?` | match |
| `dry-run` (booleanToggle) | `--dry-run` |  |  |  | `Bool` / false | match |
| `verbose` (booleanToggle) | `--verbose` |  |  |  | `Bool` / false | match |

Output parity: UIDManager / UIDConsole (shared); lookup prints UIDManager.tableA1UIDType (PS3.6 Table A-1 UID Type) and the JSON uidType key through the uidType: overloads, the --type filter is UIDConsole.lookupTypeFilters / entries(forTypeFilter:), generate --uuid builds PS3.5 B.2 UIDs through DICOMCore UIDGenerator.uuidDerivedUID, --root is checked with dicom-uid's UIDRootRule texts (PS3.5 9.1, exit 64; text-identical, checked by diff_studio_g1).

### dicom-export → dicom-export

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `operation` (subcommand) | `—` |  |  | single, contact-sheet, animate, bulk / single | `—` | not a CLI option |
| `inputPath` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `output` (outputPath) | `--output` |  |  |  | `String` | match |
| `format` (enumPicker) | `--format` |  |  | jpeg | `ExportImageFormat` / .png | match |
| `quality` (integerField) | `--quality` |  |  | 90 | `Int` / 90 | match |
| `embed-metadata` (booleanToggle) | `--embed-metadata` |  |  |  | `Bool` / false | match |
| `exif-fields` (textField) | `--exif-fields` |  |  |  | `String?` | match |
| `frame-number` (integerField) | `--frame-number` |  |  |  | `Int?` | match |
| `frame` (integerField) | `--frame` |  |  |  | `Int?` | match |
| `apply-window` (booleanToggle) | `--apply-window` |  |  |  | `Bool` / false | match |
| `apply-window-deprecated` (booleanToggle) | `--apply-window` |  |  |  | `Bool` / false | match |
| `window-center` (textField) | `--window-center` |  |  |  | `Double?` | match |
| `window-width` (textField) | `--window-width` |  |  |  | `Double?` | match |
| `columns` (integerField) | `--columns` |  |  | 4 | `Int` / 4 | match |
| `thumbnail-size` (integerField) | `--thumbnail-size` |  |  | 256 | `Int` / 256 | match |
| `spacing` (integerField) | `--spacing` |  |  | 4 | `Int` / 4 | match |
| `labels` (booleanToggle) | `--labels` |  |  |  | `Bool` / false | match |
| `sheet-format` (enumPicker) | `--format` |  |  | png | `ExportImageFormat` / .png | match |
| `fps` (textField) | `--fps` |  |  |  | `Double?` | match |
| `loop-count` (integerField) | `--loop-count` |  |  | 0 | `Int` / 0 | match |
| `start-frame-number` (integerField) | `--start-frame-number` |  |  |  | `Int?` | match |
| `end-frame-number` (integerField) | `--end-frame-number` |  |  |  | `Int?` | match |
| `start-frame` (integerField) | `--start-frame` |  |  |  | `Int?` | match |
| `end-frame` (integerField) | `--end-frame` |  |  |  | `Int?` | match |
| `scale` (textField) | `--scale` |  |  | 1.0 | `Double` / 1.0 | match |
| `bulk-format` (enumPicker) | `--format` |  |  | png | `ExportImageFormat` / .png | match |
| `organize-by` (enumPicker) | `--organize-by` |  |  | flat | `OrganizationScheme` / .flat | match |
| `recursive` (booleanToggle) | `--recursive` |  |  |  | `Bool` / false | match |
| `verbose` (booleanToggle) | `--verbose` |  |  |  | `Bool` / false | match |

Output parity: every subcommand renders through DICOMImageExporter.renderFrameForExport (PS3.4 N.2 chain; contact-sheet and animate no longer use the DICOMFile stored-window paths), frames are selected by Frame number from 1 with the CLI's deprecation notes / exit-1 conflict / exit-64 '< 1' refusals and 'Frame number N does not exist…' text, animate's rate follows PS3.3 Table C.7-13 ((0008,2144) -> (0018,0040) -> 1000/(0018,1063) -> 10), bulk uses buildOrganizedPath(patientID:issuerOfPatientID:), the Burned In Annotation (0028,0301) YES warnings and the contact-sheet / bulk --apply-window deprecation note are printed; ExportConsole lines are shared. bulk exits 0 with failures, as the CLI does (recorded in section 4).

### dicom-echo → dicom-echo

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `host` (textField) | `--host` |  |  |  | `—` | not a CLI option |
| `port` (integerField) | `--port` | TCP port | PS3.8 9.1.1 (well-known 104, registered 11112) | 11112 | `UInt16?` | match |
| `aet` (textField) | `--aet` | Calling AE Title | PS3.8 7.1.1.3; PS3.5 Table 6.2-1 VR AE | DICOMSTUDIO | `String` | match |
| `called-aet` (textField) | `--called-aet` | Called AE Title | PS3.8 7.1.1.4; PS3.5 Table 6.2-1 VR AE | ANY-SCP | `String` / "ANY-SCP" | match |
| `count` (integerField) | `--count` | number of C-ECHO operations | PS3.7 9.1.5 | 1 | `Int` / 1 | match |
| `timeout` (enumPicker) | `--timeout` | ARTIM / socket timeout | PS3.8 9.1.2 | 5, 10, 15, 30, 60, 120, 300 / 30 | `Int` / 30 | match |
| `stats` (booleanToggle) | `--stats` | round-trip statistics |  |  | `Bool` / false | match |
| `diagnose` (booleanToggle) | `--diagnose` | connectivity probe; prints PS3.7 Tables D.3-1 / D.3-3 identification | PS3.7 Annex D.3 |  | `Bool` / false | match |
| `verbose` (booleanToggle) | `--verbose` |  |  |  | `Bool` / false | match |

Output parity: every line comes from DICOMNetwork.NetworkConsole (echoHeader, echoSuccess, echoStatusFailure, echoFailureDetail, echoSummary / echoStats, the --diagnose blocks), exactly as DICOMEcho.swift prints them; `--count 0` is refused with the CLI's ValidationError text (exit 64) instead of being clamped; the host refusal is an `Error: …` usage error. The presets use the positional host:port form (the `--host` flag they carried does not exist). No standard data of its own.

### dicom-query → dicom-query

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `host` (textField) | `--host` |  |  |  | `—` | not a CLI option |
| `port` (integerField) | `--port` | TCP port | PS3.8 9.1.1 (well-known 104, registered 11112) | 11112 | `UInt16?` | match |
| `aet` (textField) | `--aet` | Calling AE Title | PS3.8 7.1.1.3; PS3.5 Table 6.2-1 VR AE | DICOMSTUDIO | `String` | match |
| `called-aet` (textField) | `--called-aet` | Called AE Title | PS3.8 7.1.1.4; PS3.5 Table 6.2-1 VR AE | ANY-SCP | `String` / "ANY-SCP" | match |
| `level` (enumPicker) | `--level` | Query/Retrieve Level (0008,0052) | PS3.4 Tables C.6.1-1 / C.6.2-1; C.4.1.1.3.1 | patient, study, series, image / study | `QueryLevelOption` / .study | match |
| `patient-id` (textField) | `--patient-id` | Patient ID (0010,0020) matching key | PS3.4 Table C.6-5 R / C.6-1 U |  | `String?` | match |
| `patient-name` (textField) | `--patient-name` | Patient's Name (0010,0010) matching key | PS3.4 Table C.6-5 R / C.6-1 R; C.2.2.2.4 |  | `String?` | match |
| `study-date` (textField) | `--study-date` | Study Date (0008,0020) matching key | PS3.4 Table C.6-5 R; C.2.2.2.5 |  | `String?` | match |
| `modality` (enumPicker) | `--modality` | Modalities in Study (0008,0061) at STUDY; Modality (0008,0060) at SERIES | PS3.4 Tables C.6-5 O / C.6-3 R; PS3.3 C.7.3.1.1.1 |  | `String?` | match |
| `strict-modality` (booleanToggle) | `--strict-modality` | reject a value that is not a Defined Term | PS3.3 C.7.3.1.1.1 |  | `Bool` / false | match |
| `study-uid` (textField) | `--study-uid` | Study Instance UID (0020,000D) unique key | PS3.4 Table C.6-5 U; C.4.1.2.1 |  | `String?` | match |
| `series-uid` (textField) | `--series-uid` | Series Instance UID (0020,000E) unique key | PS3.4 Table C.6-3 U; C.4.1.2.1 |  | `String?` | match |
| `accession-number` (textField) | `--accession-number` | Accession Number (0008,0050) matching key | PS3.4 Table C.6-5 R |  | `String?` | match |
| `study-description` (textField) | `--study-description` | Study Description (0008,1030) matching key | PS3.4 Table C.6-5 O; C.2.2.2.4 |  | `String?` | match |
| `referring-physician` (textField) | `--referring-physician` | Referring Physician's Name (0008,0090) matching key | PS3.4 Table C.6-5 O |  | `String?` | match |
| `timeout` (enumPicker) | `--timeout` | ARTIM / socket timeout | PS3.8 9.1.2 | 5, 10, 15, 30, 60, 120, 300 / 60 | `Int` / 60 | match |
| `output-format` (enumPicker) | `--format` | output rendering |  | table, json, csv, compact, dicom-json / table | `OutputFormat` / .table | match |
| `csv-keywords` (booleanToggle) | `--csv-keywords` |  |  |  | `Bool` / false | match |
| `include-parent-keys` (booleanToggle) | `--include-parent-keys` | non-baseline parent-level return keys at SERIES/IMAGE | PS3.4 C.4.1.2.1 (forbids them for a baseline SCU) |  | `Bool` / false | match |
| `verbose` (booleanToggle) | `--verbose` |  |  |  | `Bool` / false | match |

Output parity: keys through DICOMQueryService.buildQueryKeys (shared), the C-FIND through DICOMQueryService.find, results through DICOMQueryResultFormatter built exactly as DICOMQuery.formatter does — `csvHeader: csvKeywords ? .keyword : .tag`, `dicomJSONEncoder: DICOMJSONEncoder(prettyPrinted).encodeMultiple` (PS3.18 F.2 DICOM JSON Model, P-QUERY-JSON) — the verbose NetworkConsole.queryHeader, the PS3.4 C.4.1.2.1 warning naming the level by QueryLevel.rawValue (IMAGE), ModalityOptionValidator alias note / warning / `… Rejected because --strict-modality is set.` (exit 1), the CLI's validate() refusals (`--level series requires --study-uid …`, `--level image (instance) requires …`; exit 64) and `Error: <DICOMNetworkError.description>` (exit 1).

### dicom-send → dicom-send

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `host` (textField) | `--host` |  |  |  | `—` | not a CLI option |
| `port` (integerField) | `--port` | TCP port | PS3.8 9.1.1 (well-known 104, registered 11112) | 11112 | `UInt16?` | match |
| `aet` (textField) | `--aet` | Calling AE Title | PS3.8 7.1.1.3; PS3.5 Table 6.2-1 VR AE | DICOMSTUDIO | `String` | match |
| `called-aet` (textField) | `--called-aet` | Called AE Title | PS3.8 7.1.1.4; PS3.5 Table 6.2-1 VR AE | ANY-SCP | `String` / "ANY-SCP" | match |
| `files` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `recursive` (booleanToggle) | `--recursive` |  |  | false | `Bool` / false | match |
| `verify` (booleanToggle) | `--verify` | C-ECHO before sending | PS3.4 Annex A |  | `Bool` / false | match |
| `priority` (enumPicker) | `--priority` | Priority (0000,0700) of C-STORE-RQ | PS3.7 Table 9.3-1 | low, medium, high / medium | `PriorityOption` / .medium | match |
| `retry` (integerField) | `--retry` | retry on error or Failure-class status |  | 0 | `Int` / 0 | match |
| `timeout` (enumPicker) | `--timeout` | ARTIM / socket timeout | PS3.8 9.1.2 | 10, 30, 60, 120, 300 / 60 | `Int` / 60 | match |
| `dry-run` (booleanToggle) | `--dry-run` |  |  |  | `Bool` / false | match |
| `transfer-syntax` (enumPicker) | `--transfer-syntax` | Transfer Syntax Name of the proposed Presentation Context | PS3.8 7.1.1.13; PS3.6 Table A-1 |  | `String?` | match |
| `verbose` (booleanToggle) | `--verbose` |  |  |  | `Bool` / false | match |

Output parity: DICOMSendFileGatherer (shared) and NetworkConsole.sendHeader / sendFilePrefix / sendFileResultSuffix / sendDryRunLine; the C-STORE response is classed like SendExecutor.StoreOutcome per PS3.4 Table B.2-1 — Success and the Warning class (B000 / B006 / B007) stored, the Warning class followed by NetworkConsole.sendFileWarningLine(status:) and counted in sendSummary(…warnings:), the Failure class not stored, retried and reported with SendError.storeFailed's text (D75 Studio half, P-SEND-SUMMARY); `--transfer-syntax` resolves through TransferSyntax.parse and is proposed via DICOMStorageService.store(preferredTransferSyntaxUID:) and printed in the header as the UID; refusals are the CLI's (`--retry must be zero or greater`, `Unknown transfer syntax: …`, `No DICOM files found to send`: exit 64; `Send completed with N succeeded and M failed`: exit 1).

### dicom-retrieve → dicom-retrieve

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `host` (textField) | `--host` |  |  |  | `—` | not a CLI option |
| `port` (integerField) | `--port` | DICOM UL port | PS3.8 9.1.2 | 11112 | `UInt16?` | match |
| `aet` (textField) | `--aet` | Calling AE Title | PS3.8 Table 9-11; PS3.5 Table 6.2-1 VR AE | DICOMSTUDIO | `String` | match |
| `called-aet` (textField) | `--called-aet` | Called AE Title | PS3.8 Table 9-11; PS3.5 VR AE | ANY-SCP | `String` / "ANY-SCP" | match |
| `method` (enumPicker) | `--method` | C-MOVE / C-GET: Study Root QR IM - MOVE 1.2.840.10008.5.1.4.1.2.2.2 / - GET ...2.2.3 | PS3.4 Table C.6.2.3-1; C.4.2 / C.4.3 | c-move, c-get / c-move | `RetrievalMethod` / .cMove | match |
| `move-dest` (textField) | `--move-dest` | Move Destination (0000,0600) | PS3.7 Table 9.3-9; PS3.4 C.4.2.2.1 |  | `String?` | match |
| `study-uid` (textField) | `--study-uid` | Study Instance UID (0020,000D), unique key, level STUDY | PS3.4 Table C.6-5; Table C.6.1-1 |  | `String?` | match |
| `series-uid` (textField) | `--series-uid` | Series Instance UID (0020,000E), level SERIES | PS3.4 C.4.2.2.1; Table C.6.1-1 |  | `String?` | match |
| `instance-uid` (textField) | `--instance-uid` | SOP Instance UID (0008,0018), level IMAGE | PS3.4 Table C.6.1-1; C.4.2.2.1 |  | `String?` | match |
| `uid-list` (filePath) | `--uid-list` | several Study Instance UIDs, one request each | PS3.4 C.4.2.2.1 |  | `String?` | match |
| `output` (outputPath) | `--output` | output directory for Part 10 files | PS3.10 7.1 |  | `String` / "." | match |
| `hierarchical` (booleanToggle) | `--hierarchical` | output layout study/series (C-GET only) | — |  | `Bool` / false | match |
| `parallel` (integerField) | `--parallel` | concurrent uid-list retrievals | — | 1 | `Int` / 1 | match |
| `priority` (enumPicker) | `--priority` |  |  | low, medium, high / medium | `RetrievePriorityOption` / .medium | match |
| `relational-retrieve` (booleanToggle) | `--relational-retrieve` |  |  |  | `Bool` / false | match |
| `timeout` (enumPicker) | `--timeout` | socket timeout | — | 10, 30, 60, 120, 300 / 60 | `Int` / 60 | match |
| `transfer-syntax` (enumPicker) | `--transfer-syntax` | Transfer Syntax proposed for C-GET storage contexts | PS3.4 C.4.3.2.1; PS3.6 Table A-1 |  | `String?` | match |
| `verbose` (booleanToggle) | `--verbose` |  |  |  | `Bool` / false | match |

Output parity: RetrieveConfiguration(…priority:extendedNegotiation:) and RetrieveKeys at the most specific level (RetrieveExecutor.retrieveKeys) through DICOMRetrieveService.move / get; NetworkConsole.retrieveHeader(…priority:relationalRetrieval:) with the CLI's `(not sent — relational-retrieve)` placeholder; the final response worded by DIMSEServiceStatusText.describe(result.status, service: .cMove / .cGet) and subOperationCounts (PS3.4 Tables C.4-2 / C.4-3, PS3.7 Tables 9.3-10 / 9.3-7; D76 Studio half) in cMoveResult, the Failed SOP Instance UID List (0008,0058) lines and the `Final C-MOVE response: …` line of RetrieveExecutor.checkResult, success only for 0000 with no failed sub-operations (PS3.4 C.4.2.2.1 / C.4.3.2.1); validateUIDOptions / `C-MOVE requires --move-dest parameter` / `--parallel must be at least 1` / `Unknown transfer syntax` as exit 64, RetrieveError texts as `Error: …` exit 1; the bulk path prints one result block per study and the CLI's `Bulk retrieval partially failed: …`. The app-only C-FIND `Resolving Study UID from server…` lookup is gone: a series / instance UID without its parents is the CLI's refusal unless --relational-retrieve is on.

### dicom-qr → dicom-qr

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `host` (textField) | `--host` |  |  |  | `—` | not a CLI option |
| `port` (integerField) | `--port` | DICOM UL port | PS3.8 9.1.2 | 11112 | `UInt16?` | match |
| `aet` (textField) | `--aet` | Calling AE Title | PS3.8 Table 9-11; PS3.5 VR AE | DICOMSTUDIO | `String` | match |
| `called-aet` (textField) | `--called-aet` | Called AE Title | PS3.8 Table 9-11; PS3.5 VR AE | ANY-SCP | `String` / "ANY-SCP" | match |
| `mode` (flagPicker) | `—` |  |  | interactive, auto, review / interactive | `—` | not a CLI option |
| `method` (enumPicker) | `--method` | Study Root QR IM - MOVE / - GET | PS3.4 Table C.6.2.3-1 | c-move, c-get / c-move | `String` / "c-move" | match |
| `move-dest` (textField) | `--move-dest` | Move Destination (0000,0600) | PS3.7 Table 9.3-9; PS3.4 C.4.2.2.1 |  | `String?` | match |
| `patient-name` (textField) | `--patient-name` | Patient's Name (0010,0010), R key STUDY level, wild card | PS3.4 Table C.6-5; C.2.2.2.4 |  | `String?` | match |
| `patient-id` (textField) | `--patient-id` | Patient ID (0010,0020), R | PS3.4 Table C.6-5 |  | `String?` | match |
| `study-date` (textField) | `--study-date` | Study Date (0008,0020), R, range matching | PS3.4 Table C.6-5; C.2.2.2.5 |  | `String?` | match |
| `accession` (textField) | `--accession-number` | Accession Number (0008,0050), R | PS3.4 Table C.6-5 |  | `String?` | match |
| `modality` (enumPicker) | `--modality` | Modalities in Study (0008,0061), O | PS3.4 Table C.6-5; PS3.3 C.7.3.1.1.1 |  | `String?` | match |
| `strict-modality` (booleanToggle) | `--strict-modality` | — | — |  | `Bool` / false | match |
| `study-uid` (textField) | `--study-uid` | Study Instance UID (0020,000D), U | PS3.4 Table C.6-5 |  | `String?` | match |
| `study-description` (textField) | `--study-description` | Study Description (0008,1030), O, wild card | PS3.4 Table C.6-5; C.2.2.2.4 |  | `String?` | match |
| `include-parent-keys` (booleanToggle) | `--include-parent-keys` | parent-level return keys (no effect at STUDY) | PS3.4 C.4.1.1.3.1 |  | `Bool` / false | match |
| `output` (outputPath) | `--output` |  |  |  | `String` / "." | match |
| `hierarchical` (booleanToggle) | `--hierarchical` | output layout <output>/<StudyInstanceUID>/ (C-GET only) | — |  | `Bool` / false | match |
| `validate` (booleanToggle) | `--validate` | Part 10 read of received files | PS3.10 |  | `Bool` / false | match |
| `parallel` (integerField) | `--parallel` | declared, never read (sequential) | — | 1 | `Int` / 1 | match |
| `priority` (enumPicker) | `--priority` |  |  | low, medium, high / medium | `QRPriorityOption` / .medium | match |
| `timeout` (enumPicker) | `--timeout` | socket timeout | — | 10, 30, 60, 120, 300 / 60 | `Int` / 60 | match |
| `transfer-syntax` (enumPicker) | `--transfer-syntax` | Transfer Syntax proposed for C-GET storage contexts | PS3.4 C.4.3.2.1; PS3.6 Table A-1 |  | `String?` | match |
| `save-state` (outputPath) | `--save-state` | state file | — |  | `String?` | match |

Output parity: NetworkConsole.qrHeader / qrFound / qrStudyEntry / qrRetrieveLine / qrRetrieveOutcome / qrSummary (shared); keys through DICOMQueryService.buildQueryKeys(level: .study, …, includeParentLevelReturnKeys:) as DICOMQR.buildQueryKeys; each retrieval through RetrieveConfiguration(priority:) and RetrieveKeys.forStudy, up to --parallel at once with the CLI's line order (line before the retrieval with --parallel 1, after the batch otherwise), the final response checked like RetrieveExecutor.checkRetrieveResult (`Retrieval failed: C-MOVE final response <PS3.4 Table C.4-2 wording> (<PS3.7 counters>)`, Failed SOP Instance UID List block); ModalityOptionValidator; refusals `--move-dest is required for C-MOVE method`, `Invalid method: …`, `--parallel must be at least 1` (64), `Retrieval incomplete: N study(ies) succeeded, M failed` (1); QRSessionState (shared) for --save-state.

### dicom-mwl → dicom-mwl

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `operation` (subcommand) | `—` |  |  | query, create / query | `—` | not a CLI option |
| `host` (textField) | `--host` |  |  |  | `—` | not a CLI option |
| `port` (integerField) | `--port` | TCP port | PS3.8 9.1.1 (well-known 104; 11112 IANA registered) | 11112 | `UInt16?` | match |
| `aet` (textField) | `--aet` | Calling AE Title | PS3.8 7.1.1.3; PS3.5 Table 6.2-1 VR AE | DICOMSTUDIO | `String` | match |
| `called-aet` (textField) | `--called-aet` | Called AE Title | PS3.8 7.1.1.4; PS3.5 Table 6.2-1 VR AE | ANY-SCP | `String` / "ANY-SCP" | match |
| `date-from` (textField) | `--date` | Scheduled Procedure Step Start Date (0040,0002), R key | PS3.4 Table K.6-1 row 4; C.2.2.2.5.1; PS3.5 Table 6.2-1 DA |  | `String?` | match |
| `time-from` (textField) | `--time` | Scheduled Procedure Step Start Time (0040,0003), R key | PS3.4 Table K.6-1 row 5 (combined date-time remark); C.2.2.2.5.2/.4; PS3.5 Table 6.2-1 TM |  | `String?` | match |
| `station` (textField) | `--station` | Scheduled Station AE Title (0040,0001), R key | PS3.4 Table K.6-1 row 3 (Single Value Matching only); PS3.5 VR AE |  | `String?` | match |
| `patient` (textField) | `--patient` | Patient's Name (0010,0010), R key | PS3.4 Table K.6-1 row 86 |  | `String?` | match |
| `patient-id` (textField) | `--patient-id` | Patient ID (0010,0020), R key | PS3.4 Table K.6-1 row 87 |  | `String?` | match |
| `modality` (enumPicker) | `--modality` | Modality (0008,0060), R key | PS3.4 Table K.6-1 row 6; PS3.3 C.7.3.1.1.1 |  | `String?` | match |
| `strict-modality` (booleanToggle) | `--strict-modality` | reject non-Defined-Term modality | PS3.3 C.7.3.1.1.1 |  | `Bool` / false | match |
| `sps-status` (enumPicker) | `--sps-status` | Scheduled Procedure Step Status (0040,0020), O key type 3 | PS3.4 Table K.6-1 row 35; PS3.3 Table C.4-10 Defined Terms | , SCHEDULED, ARRIVED, READY, STARTED, DEPARTED | `String?` | match |
| `query-accession-number` (textField) | `--accession-number` | Accession Number (0008,0050), O key type 2 | PS3.4 Table K.6-1 row 64 |  | `String?` | match |
| `None` (textField) | `--performing-physician` | Scheduled Performing Physician's Name (0040,0006), R key type 2 | PS3.4 Table K.6-1 row 7 |  | `String?` | match |
| `specific-character-set` (textField) | `--specific-character-set` | Specific Character Set (0008,0005) of the Identifier | PS3.4 Table K.6-1a; PS3.5 6.1.2 / Table 6.1-1 |  | `String?` | match |
| `create-method` (enumPicker) | `—` |  |  | hl7, rest / hl7 | `—` | internal |
| `hl7-port` (integerField) | `--hl7-port` |  |  | 2575 | `—` | internal |
| `create-patient-name` (textField) | `--patient-name` |  |  |  | `—` | internal |
| `create-patient-id` (textField) | `--patient-id` | Patient ID (0010,0020), R key | PS3.4 Table K.6-1 row 87 |  | `String?` | match |
| `patient-dob` (textField) | `--patient-dob` |  |  |  | `—` | internal |
| `patient-sex` (enumPicker) | `--patient-sex` |  |  | , M, F, O | `—` | internal |
| `accession-number` (textField) | `--accession-number` | Accession Number (0008,0050), O key type 2 | PS3.4 Table K.6-1 row 64 |  | `String?` | match |
| `referring-physician` (textField) | `--referring-physician` |  |  |  | `—` | internal |
| `procedure-id` (textField) | `--procedure-id` |  |  |  | `—` | internal |
| `procedure-desc` (textField) | `--procedure-desc` |  |  |  | `—` | internal |
| `create-modality` (enumPicker) | `--modality` | Modality (0008,0060), R key | PS3.4 Table K.6-1 row 6; PS3.3 C.7.3.1.1.1 | CT | `String?` | match |
| `scheduled-station` (textField) | `--scheduled-station` |  |  |  | `—` | internal |
| `station-name` (textField) | `--station-name` |  |  |  | `—` | internal |
| `scheduled-date` (textField) | `--scheduled-date` |  |  |  | `—` | internal |
| `scheduled-time` (textField) | `--scheduled-time` |  |  |  | `—` | internal |
| `sps-id` (textField) | `--sps-id` |  |  |  | `—` | internal |
| `sps-desc` (textField) | `--sps-desc` |  |  |  | `—` | internal |
| `performing-physician` (textField) | `--physician` |  |  |  | `—` | internal |
| `rest-base-url` (textField) | `--rest-url` |  |  |  | `—` | internal |
| `sending-application` (textField) | `--sending-app` |  |  | DICOMSTUDIO | `—` | internal |
| `sending-facility` (textField) | `--sending-facility` |  |  | IMAGING | `—` | internal |
| `receiving-application` (textField) | `--receiving-app` |  |  | DCM4CHEE | `—` | internal |
| `receiving-facility` (textField) | `--receiving-facility` |  |  | HOSPITAL | `—` | internal |
| `timeout` (enumPicker) | `--timeout` | ARTIM / socket timeout | PS3.8 9.1.2 | 5, 10, 15, 30, 60, 120, 300 / 60 | `Int` / 60 | match |
| `json` (booleanToggle) | `--json` | JSON rendering; 28/38 keys are PS3.6 keywords | PS3.6 Table 6-1 |  | `Bool` / false | match |
| `verbose` (booleanToggle) | `--verbose` |  |  |  | `Bool` / false | match |

Output parity (query): WorklistQueryKeys.forQuery (shared) → DICOMModalityWorklistService.find(…specificCharacterSet:), NetworkConsole.mwlQueryHeader / mwlFound / mwlItem / mwlCompleted / mwlNoResults / mwlLimitWarning / mwlJSON (shared, same gating as the CLI), ModalityOptionValidator, the CLI-local spsStatusWarning mirrored text-identically (PS3.3 Table C.4-10 Defined Terms; checked by diff_studio_g1), WorklistDateFilterError as exit 64, `Error: <DICOMNetworkError.description>` exit 1. The `create` arm is Studio-only (HL7 ORM^O01 / REST; preview rendered commented out) — P-STUDIO-MWL-CREATE.

### dicom-mpps → dicom-mpps

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `operation` (subcommand) | `—` |  |  | create, update / create | `—` | not a CLI option |
| `host` (textField) | `--host` |  |  |  | `—` | not a CLI option |
| `port` (integerField) | `--port` | TCP port | PS3.8 9.1.1 (well-known 104; 11112 IANA registered) | 11112 | `UInt16?` | match |
| `aet` (textField) | `--aet` | Calling AE Title | PS3.8 7.1.1.3; PS3.5 Table 6.2-1 VR AE | DICOMSTUDIO | `String` | match |
| `called-aet` (textField) | `--called-aet` | Called AE Title | PS3.8 7.1.1.4; PS3.5 Table 6.2-1 VR AE | ANY-SCP | `String` / "ANY-SCP" | match |
| `patient-name` (textField) | `--patient-name` | Patient's Name (0010,0010) | PS3.4 Table F.7.2-1 row 32 (2/2) |  | `String?` | match |
| `patient-id` (textField) | `--patient-id` | Patient ID (0010,0020) | PS3.4 Table F.7.2-1 row 33 (2/2) |  | `String?` | match |
| `study-uid` (textField) | `--study-uid` | Study Instance UID (0020,000D) in (0040,0270) [create]; Performed Series pairing [update] | PS3.4 Table F.7.2-1 row 4 (1/1) |  | `String?` | match |
| `sps-id` (textField) | `--sps-id` | Scheduled Procedure Step ID (0040,0009) in (0040,0270) | PS3.4 Table F.7.2-1 row 27 (2/2) |  | `String?` | match |
| `accession-number` (textField) | `--accession-number` | Accession Number (0008,0050) in (0040,0270) | PS3.4 Table F.7.2-1 row 8 (2/2) |  | `String?` | match |
| `modality` (enumPicker) | `--modality` | Modality (0008,0060) | PS3.4 Table F.7.2-1 row 105 (1/1); PS3.3 C.7.3.1.1.1 |  | `String?` | match |
| `strict-modality` (booleanToggle) | `--strict-modality` | reject non-Defined-Term modality | PS3.3 C.7.3.1.1.1 |  | `Bool` / false | match |
| `patient-birth-date` (textField) | `--patient-birth-date` | Patient's Birth Date (0010,0030) | PS3.4 Table F.7.2-1 row 45 (2/2); PS3.5 Table 6.2-1 DA |  | `String?` | match |
| `patient-sex` (enumPicker) | `--patient-sex` | Patient's Sex (0010,0040) | PS3.4 Table F.7.2-1 row 46 (2/2); PS3.3 Table C.2-3 | , M, F, O | `String?` | match |
| `study-id` (textField) | `--study-id` | Study ID (0020,0010) | PS3.4 Table F.7.2-1 row 106 (2/2) |  | `String?` | match |
| `station-name` (textField) | `--station-name` | Performed Station Name (0040,0242) | PS3.4 Table F.7.2-1 row 88 (2/2) |  | `String?` | match |
| `performed-location` (textField) | `--performed-location` | Performed Location (0040,0243) | PS3.4 Table F.7.2-1 row 89 (2/2) |  | `String?` | match |
| `procedure-step-id` (textField) | `--procedure-step-id` | Performed Procedure Step ID (0040,0253) | PS3.4 Table F.7.2-1 row 86 (1/1) |  | `String?` | match |
| `procedure-step-description` (textField) | `--procedure-step-description` | Performed Procedure Step Description (0040,0254) | PS3.4 Table F.7.2-1 row 93 (2/2) |  | `String?` | match |
| `create-performing-physician` (textField) | `--performing-physician` | Performing Physician's Name (0008,1050) in Performed Series item | PS3.4 Table F.7.2-1 row 111 (2/2) |  | `String?` | match |
| `requested-procedure-id` (textField) | `--requested-procedure-id` | Requested Procedure ID (0040,1001) in (0040,0270) | PS3.4 Table F.7.2-1 row 23 (2/2) |  | `String?` | match |
| `requested-procedure-description` (textField) | `--requested-procedure-description` | Requested Procedure Description (0032,1060) in (0040,0270) | PS3.4 Table F.7.2-1 row 26 (2/2) |  | `String?` | match |
| `sps-description` (textField) | `--sps-description` | Scheduled Procedure Step Description (0040,0007) in (0040,0270) | PS3.4 Table F.7.2-1 row 28 (2/2) |  | `String?` | match |
| `referenced-study-uid` (textField) | `--referenced-study-uid` | Referenced SOP Instance UID (0008,1155) in Referenced Study Sequence (0008,1110) | PS3.4 Table F.7.2-1 rows 5-7 |  | `String?` | match |
| `mpps-uid` (textField) | `--mpps-uid` | Requested SOP Instance UID of the N-SET | PS3.7 Table 10.3-5; 10.1.5.1.4 |  | `String` | match |
| `status` (enumPicker) | `--status` | Performed Procedure Step Status (0040,0252) | PS3.3 Table C.4-14; PS3.4 F.7.2.1.2 (create: IN PROGRESS only), F.7.2.2.2 (update: COMPLETED|DISCONTINUED, final) | IN PROGRESS / IN PROGRESS | `String` | match |
| `status-update` (enumPicker) | `--status` | Performed Procedure Step Status (0040,0252) | PS3.3 Table C.4-14; PS3.4 F.7.2.1.2 (create: IN PROGRESS only), F.7.2.2.2 (update: COMPLETED|DISCONTINUED, final) | COMPLETED, DISCONTINUED / COMPLETED | `String` | match |
| `series-uid` (textField) | `--series-uid` | Series Instance UID (0020,000E) of the Performed Series item | PS3.4 Table F.7.2-1 row 114 (1/1) |  | `String?` | match |
| `image-uid` (textField) | `--image-uid` | Referenced SOP Instance UID (0008,1155) in Referenced Image Sequence (0008,1140) | PS3.4 Table F.7.2-1 rows 118-120 |  | `[String]` / [] | match |
| `sop-class-uid` (textField) | `--sop-class-uid` | Referenced SOP Class UID (0008,1150) | PS3.4 Table F.7.2-1 row 119 (1/1); PS3.6 Table A-1 |  | `String?` | match |
| `protocol-name` (textField) | `--protocol-name` | Protocol Name (0018,1030) | PS3.4 Table F.7.2-1 row 112 (1/1) |  | `String?` | match |
| `series-description` (textField) | `--series-description` | Series Description (0008,103E) | PS3.4 Table F.7.2-1 row 115 (2/2) |  | `String?` | match |
| `operator-name` (textField) | `--operator-name` | Operators' Name (0008,1070) | PS3.4 Table F.7.2-1 row 113 (2/2) |  | `String?` | match |
| `update-performing-physician` (textField) | `--performing-physician` | Performing Physician's Name (0008,1050) in Performed Series item | PS3.4 Table F.7.2-1 row 111 (2/2) |  | `String?` | match |
| `discontinuation-reason` (textField) | `--discontinuation-reason` | PPS Discontinuation Reason Code Sequence (0040,0281) | PS3.4 Table F.7.2-1 row 102 (3/3, macro F.7.2-1c); PS3.16 CID 9300 / CID 9301 / Table D-1 |  | `String?` | match |
| `legacy-nset-scheduled-attributes` (booleanToggle) | `--legacy-nset-scheduled-attributes` | Scheduled Step Attributes Sequence (0040,0270) in N-SET | PS3.4 Table F.7.2-1 row 3 (N-SET: Not allowed) |  | `Bool` / false | match |
| `specific-character-set` (textField) | `--specific-character-set` | Specific Character Set (0008,0005) | PS3.4 Table F.7.2-1 row 1 (1C/1C); PS3.5 6.1.2 |  | `String?` | match |
| `timeout` (enumPicker) | `--timeout` | ARTIM / socket timeout | PS3.8 9.1.2 | 5, 10, 15, 30, 60, 120, 300 / 60 | `Int` / 60 | match |
| `verbose` (booleanToggle) | `--verbose` |  |  |  | `Bool` / false | match |

Output parity: DICOMMPPSService.createDetailed / update (shared), NetworkConsole.mppsHeader (the CLI's field set) / mppsProgress / mppsCreateResult / mppsUpdateResult; the SCP warning line worded like dicom-mpps' reportWarning through DIMSEServiceStatusText (PS3.4 Table F.7.2-2 for N-SET, PS3.7 Annex C for N-CREATE), the `note: SCP assigned MPPS SOP Instance UID …` line; the CLI's refusals as exit 64 (`--modality is required: Modality (0008,0060) is Type 1 …`, `--patient-sex must be one of M, F, O …`, `--patient-birth-date must be YYYYMMDD …`, `Create status must be IN PROGRESS …`, `Update status must be COMPLETED or DISCONTINUED`, `--discontinuation-reason is only valid with --status DISCONTINUED`, MPPSCodedEntry.parseErrorMessage, `--image-uid needs --study-uid and --series-uid …`) and the `warning: --sop-class-uid not given; …` line text-identical; failures `Error: <description>` exit 1. The placeholder / help examples are PS3.16 CID 9301 pairs (D85).

### dicom-qido → dicom-wado

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `url` (textField) | `—` |  |  |  | `—` | not a CLI option |
| `level` (enumPicker) | `--level` |  |  | study, series, instance / study | `QueryLevel` / .study | match |
| `patient-name` (textField) | `--patient-name` |  |  |  | `String?` | match |
| `patient-id` (textField) | `--patient-id` |  |  |  | `String?` | match |
| `study-date` (textField) | `--study-date` |  |  |  | `String?` | match |
| `modality` (enumPicker) | `--modality` |  |  |  | `String?` | match |
| `strict-modality` (booleanToggle) | `--strict-modality` |  |  |  | `Bool` / false | match |
| `study-uid` (textField) | `--study` |  |  |  | `String?` | match |
| `series-uid` (textField) | `--series` |  |  |  | `String?` | match |
| `accession` (textField) | `--accession-number` |  |  |  | `String?` | match |
| `study-description` (textField) | `--study-description` |  |  |  | `String?` | match |
| `pps-start-date` (textField) | `--pps-start-date` |  |  |  | `String?` | match |
| `pps-start-time` (textField) | `--pps-start-time` |  |  |  | `String?` | match |
| `qido-sps-id` (textField) | `--sps-id` |  |  |  | `String?` | match |
| `qido-requested-procedure-id` (textField) | `--requested-procedure-id` |  |  |  | `String?` | match |
| `limit` (integerField) | `--limit` |  |  | 100 | `Int` / 100 | match |
| `offset` (integerField) | `--offset` |  |  | 0 | `Int` / 0 | match |
| `fuzzy-matching` (booleanToggle) | `--fuzzy-matching` |  |  |  | `Bool` / false | match |
| `auth` (enumPicker) | `--auth` |  |  | none, basic, bearer / none | `—` | internal |
| `token` (secureField) | `--token` |  |  |  | `String?` | match |
| `username` (textField) | `--username` |  |  |  | `—` | internal |
| `password` (secureField) | `—` |  |  |  | `—` | internal |
| `output-format` (enumPicker) | `--format` |  |  | table, json, csv, dicom-json / table | `OutputFormat` / .table | match |
| `verbose` (booleanToggle) | `--verbose` |  |  |  | `Bool` / false | match |

Output parity: QIDOQuery built in QueryCommand.buildQuery's order (limit / offset / fuzzymatching / keys; Modality (0008,0060) at series level, Modalities In Study (0008,0061) otherwise), ModalityOptionValidator, QIDOResultFormatter (shared; table / json / csv / dicom-json), the CLI's verbose header (`DICOMweb Server:`, `Query Level:`, `Limit: …, Offset: …`, blank line — it read a non-existent `base-url` field before) and `Found N …` lines, WADOOptionRules.validatePaging texts (64), `Error: <localizedDescription>` (1).

### dicom-wado → dicom-wado

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `wado-protocol` (enumPicker) | `—` |  |  | wado-rs, wado-uri / wado-rs | `—` | internal |
| `url` (textField) | `—` |  |  |  | `—` | not a CLI option |
| `study-uid` (textField) | `--study` |  |  |  | `String?` | match |
| `series-uid` (textField) | `--series` |  |  |  | `String?` | match |
| `instance-uid` (textField) | `--instance` |  |  |  | `String?` | match |
| `frames` (textField) | `--frames` |  |  |  | `String?` | match |
| `metadata` (booleanToggle) | `--metadata` |  |  |  | `Bool` / false | match |
| `rendered` (booleanToggle) | `--rendered` |  |  |  | `Bool` / false | match |
| `thumbnail` (booleanToggle) | `--thumbnail` |  |  |  | `Bool` / false | match |
| `content-type` (enumPicker) | `--content-type` |  |  |  | `String?` | match |
| `transfer-syntax` (textField) | `--transfer-syntax` |  |  |  | `String?` | match |
| `anonymize` (booleanToggle) | `--anonymize` |  |  |  | `Bool` / false | match |
| `charset` (textField) | `--charset` |  |  |  | `String?` | match |
| `annotation` (textField) | `--annotation` |  |  |  | `String?` | match |
| `rows` (integerField) | `--rows` |  |  |  | `Int?` | match |
| `columns` (integerField) | `--columns` |  |  |  | `Int?` | match |
| `image-quality` (integerField) | `--image-quality` |  |  |  | `Int?` | match |
| `region` (textField) | `--region` |  |  |  | `String?` | match |
| `window-center` (textField) | `--window-center` |  |  |  | `Double?` | match |
| `window-width` (textField) | `--window-width` |  |  |  | `Double?` | match |
| `presentation-uid` (textField) | `--presentation-uid` |  |  |  | `String?` | match |
| `presentation-series-uid` (textField) | `--presentation-series-uid` |  |  |  | `String?` | match |
| `output` (outputPath) | `-o` |  |  |  | `String?` | match |
| `format` (enumPicker) | `--format` |  |  | json, xml / json | `OutputFormat` / .table | match |
| `auth` (enumPicker) | `--auth` |  |  | none, basic, bearer / none | `—` | internal |
| `token` (secureField) | `--token` |  |  |  | `String?` | match |
| `username` (textField) | `--username` |  |  |  | `—` | internal |
| `password` (secureField) | `—` |  |  |  | `—` | internal |
| `timeout` (integerField) | `--timeout` |  |  | 60 | `Int` / 60 | match |
| `verbose` (booleanToggle) | `--verbose` |  |  |  | `Bool` / false | match |

Output parity: WADORetrieveConsoleFormatter (shared) for every WADO-RS / WADO-URI line; WADO-URI through WADOURIClient.Parameters (PS3.18 Tables 9.1.2-2 / 9.4.1-1 / 9.5.1-1; validated by the shared client), the CLI-local WADOOptionRules mirrored text-identically as WorkshopWADOOptionRules (contentType per 9.1.2.2.1 / Table 8.7.4-1, frameNumber 9.5.1.2.1 and its dropped-frames warning, the Table 9.4.1-1 / 9.5.1-1 parameter warnings, --timeout mapping; checked by diff_studio_g1), the CLI's refusals as exit 64 (`--study is required for retrieve operations`, `--series / --instance is required for WADO-URI retrieval`, `--rows / --columns must be a positive integer …`, `--series and --instance are required for rendered / frame retrieval`, WADOFrameParseError, Section 9 rule problems joined with `; `), `Error: …` exit 1; the app-only per-instance dataset previews are no longer printed. The `--format` field is the CLI's MetadataFormat (json | xml, default json, PS3.18 Table 8.7.3-3); the parity check's by-flag collapse against the ups OutputFormat is annotated DEFR.

### dicom-stow → dicom-wado

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `url` (textField) | `—` |  |  |  | `—` | not a CLI option |
| `files` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `study-uid` (textField) | `--study` |  |  |  | `String?` | match |
| `input` (filePath) | `--input` |  |  |  | `String?` | match |
| `batch` (integerField) | `--batch` |  |  | 10 | `Int` / 10 | match |
| `continue-on-error` (booleanToggle) | `--continue-on-error` |  |  |  | `Bool` / false | match |
| `auth` (enumPicker) | `--auth` |  |  | none, basic, bearer / none | `—` | internal |
| `token` (secureField) | `--token` |  |  |  | `String?` | match |
| `username` (textField) | `--username` |  |  |  | `—` | internal |
| `password` (secureField) | `—` |  |  |  | `—` | internal |
| `verbose` (booleanToggle) | `--verbose` |  |  |  | `Bool` / false | match |

Output parity: STOWResultFormatter (shared) header / batchStart / batchResult / failureDetail / warningDetail (Warning Reason (0008,1196), PS3.18 Table I.2-1; D106) / summary; `Error reading …` / `Error uploading batch N: …` lines with --continue-on-error; any unstored instance exits 1 with or without --continue-on-error (PS3.18 Table 10.5.3-1, as the CLI since 39da529 — the Workshop exited 0 with the flag); `No files specified. Use file arguments or --input option.` and `--batch must be at least 1` as exit 64.

### dicom-ups → dicom-wado

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `operation` (enumPicker) | `—` |  |  | search, get, create-workitem, create-json, change-state, subscribe, unsubscribe / search | `—` | internal |
| `url` (textField) | `—` |  |  |  | `—` | not a CLI option |
| `get-uid` (textField) | `--get` |  |  |  | `String?` | match |
| `create-json-file` (filePath) | `--create` |  |  |  | `String?` | match |
| `update-uid` (textField) | `--change-state` |  |  |  | `String?` | match |
| `update-uid-deprecated` (textField) | `--update` |  |  |  | `String?` | match |
| `workitem-uid` (textField) | `--workitem-uid` |  |  |  | `String?` | match |
| `subscribe-aet` (textField) | `--aet` |  |  | DICOM_STUDIO | `String?` | match |
| `create-label` (textField) | `--label` |  |  |  | `String?` | match |
| `create-patient-name` (textField) | `--patient-name` |  |  |  | `String?` | match |
| `create-patient-id` (textField) | `--patient-id` |  |  |  | `String?` | match |
| `create-patient-birth-date` (textField) | `--patient-birth-date` |  |  |  | `String?` | match |
| `create-patient-sex` (enumPicker) | `--patient-sex` |  |  | , M, F, O | `String?` | match |
| `create-priority` (enumPicker) | `--priority` |  |  | HIGH, MEDIUM, LOW / MEDIUM | `String?` | match |
| `create-scheduled-start` (textField) | `--scheduled-start` |  |  |  | `String?` | match |
| `create-expected-completion` (textField) | `--expected-completion` |  |  |  | `String?` | match |
| `create-study-uid` (textField) | `--study-uid` |  |  |  | `String?` | match |
| `create-accession` (textField) | `--accession-number` |  |  |  | `String?` | match |
| `create-referring-physician` (textField) | `--referring-physician` |  |  |  | `String?` | match |
| `create-procedure-id` (textField) | `--procedure-id` |  |  |  | `String?` | match |
| `create-step-id` (textField) | `--step-id` |  |  |  | `String?` | match |
| `create-worklist-label` (textField) | `--worklist-label` |  |  |  | `String?` | match |
| `create-station-name` (textField) | `--station-name` |  |  |  | `String?` | match |
| `create-performer` (textField) | `--performer-name` |  |  |  | `String?` | match |
| `create-performer-organization` (textField) | `--performer-organization` |  |  |  | `String?` | match |
| `create-comments` (textField) | `--comments` |  |  |  | `String?` | match |
| `create-admission-id` (textField) | `--admission-id` |  |  |  | `String?` | match |
| `state` (enumPicker) | `--state` |  |  | IN PROGRESS, COMPLETED, CANCELED / IN PROGRESS | `String?` | match |
| `change-state-aet` (textField) | `--aet` |  |  | DCM4CHEE | `String?` | match |
| `transaction-uid` (textField) | `--transaction-uid` |  |  |  | `String?` | match |
| `filter-state` (enumPicker) | `--filter-state` |  |  | , SCHEDULED, IN PROGRESS, COMPLETED, CANCELED | `String?` | match |
| `scheduled-station` (textField) | `--scheduled-station` |  |  |  | `String?` | match |
| `auth` (enumPicker) | `--auth` |  |  | none, basic, bearer / none | `—` | internal |
| `token` (secureField) | `--token` |  |  |  | `String?` | match |
| `username` (textField) | `--username` |  |  |  | `—` | internal |
| `password` (secureField) | `—` |  |  |  | `—` | internal |
| `output-format` (enumPicker) | `--format` |  |  | table, json, csv, dicom-json / table | `OutputFormat` / .table | match |
| `verbose` (booleanToggle) | `--verbose` |  |  |  | `Bool` / false | match |

Output parity: UPSQuery.workitemSearch, UPSResultFormatter (table / json / csv / dicom-json), UPSConsole.createResponseText / updateVerboseHeader / finalStateUpdatingLine / finalStateUpdatedLine / updateResultText (all shared) in the CLI's structure — verbose-gated `DICOMweb Server:`, `Searching worklist items...`, `Retrieving worklist item:`, `Creating worklist item from …`, `Found N worklist item(s)`, `Retrieved worklist item …`, subscribe / unsubscribe lines incl. the global (Worklist) forms; the app-only query-URL / filter dump, field echo, curl block, pre-flight state check and Event-Monitor hints are gone. --change-state (PS3.18 11.7) with --update as deprecated alias (CLI note; both → refused), SCHEDULED refused with the CLI's text (PS3.18 11.7.1.4; PS3.4 Table CC.1.1-2 C303H; exit 1 — P-WADO-UPS-STATE / -UPDATE), `--transaction-uid is required for COMPLETED/CANCELED transition …` (64; the in-app IN PROGRESS claim cache stands in for the returned UID), `--label is required when using --create-workitem`, `Invalid patient sex …`, `Invalid priority …`, `Invalid date format for …` (64).

### dicom-anon → dicom-anon

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `inputPath` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `output` (outputPath) | `--output` | output file or directory | PS3.10 7.1; (0002,0003) = (0008,0018) |  | `String?` | match |
| `profile` (enumPicker) | `--profile` | Attribute Confidentiality Profile | PS3.15 E.1, E.2, Table E.1-1 | legacy-basic, legacy-clinical-trial, legacy-research / legacy-basic | `String` / AnonCLI.defaultProfile | match |
| `retain-dates` (booleanToggle) | `--retain-dates` | Retain Longitudinal Temporal Information With Full Dates / With Modified Dates Option | PS3.15 E.3.6; CID 7050 113106/113107 |  | `Bool` / false | match |
| `retain-full-dates` (booleanToggle) | `--retain-full-dates` | Retain Longitudinal Temporal Information With Full Dates Option | PS3.15 E.3.6; CID 7050 113106 |  | `Bool` / false | match |
| `retain-modified-dates` (booleanToggle) | `--retain-modified-dates` | Retain Longitudinal Temporal Information With Modified Dates Option | PS3.15 E.3.6; CID 7050 113107 |  | `Bool` / false | match |
| `retain-characteristics` (booleanToggle) | `--retain-characteristics` | Retain Patient Characteristics Option | PS3.15 E.3.7; CID 7050 113108 |  | `Bool` / false | match |
| `retain-device` (booleanToggle) | `--retain-device` | Retain Device Identity Option | PS3.15 E.3.8; CID 7050 113109 |  | `Bool` / false | match |
| `retain-institution` (booleanToggle) | `--retain-institution` | Retain Institution Identity Option | PS3.15 E.3.11; CID 7050 113112 |  | `Bool` / false | match |
| `retain-uids` (booleanToggle) | `--retain-uids` | Retain UIDs Option | PS3.15 E.3.9; CID 7050 113110 |  | `Bool` / false | match |
| `clean-descriptors` (booleanToggle) | `--clean-descriptors` | Clean Descriptors Option | PS3.15 E.3.5; CID 7050 113105 |  | `Bool` / false | match |
| `retain-safe-private` (booleanToggle) | `--retain-safe-private` |  |  |  | `Bool` / false | match |
| `clean-graphics` (booleanToggle) | `--clean-graphics` |  |  |  | `Bool` / false | match |
| `clean-structured-content` (booleanToggle) | `--clean-structured-content` |  |  |  | `Bool` / false | match |
| `clean-recognizable-visual-features` (booleanToggle) | `--clean-recognizable-visual-features` |  |  |  | `Bool` / false | match |
| `clean-pixel-data` (booleanToggle) | `--clean-pixel-data` | Clean Pixel Data Option | PS3.15 E.3.1; CID 7050 113101; (0028,0301) NO |  | `Bool` / false | match |
| `redact-region` (textField) | `--redact-region` | Clean Pixel Data region | PS3.15 E.3.1 |  | `[String]` / [] | match |
| `redact-fill` (integerField) | `--redact-fill` | fill sample value for blanked pixels | PS3.15 E.3.1 |  | `Int?` | match |
| `shift-dates` (integerField) | `--shift-dates` | date modification for Modified Dates Option | PS3.15 E.3.6 |  | `Int?` | match |
| `regenerate-uids` (booleanToggle) | `--regenerate-uids` | UID replacement (U) | PS3.15 Table E.1-1 (U), E.3.9 |  | `Bool` / false | match |
| `remove` (textField) | `--remove` | remove attribute (X) | PS3.15 Table E.1-1a X; PS3.6 Table 6-1 keywords |  | `[String]` / [] | match |
| `replace` (textField) | `--replace` | replace attribute value | PS3.6 Table 6-1 keywords |  | `[String]` / [] | match |
| `keep` (textField) | `--keep` | keep attribute (K) | PS3.15 Table E.1-1a K |  | `[String]` / [] | match |
| `recursive` (booleanToggle) | `--recursive` | directory walk | - |  | `Bool` / false | match |
| `dry-run` (booleanToggle) | `--dry-run` | preview | - |  | `Bool` / false | match |
| `backup` (booleanToggle) | `--backup` | copy of input next to output | - |  | `Bool` / false | match |
| `audit-log` (outputPath) | `--audit-log` | de-identification record | PS3.15 E.1.1 |  | `String?` | match |
| `force` (booleanToggle) | `--force` | read without DICM prefix | PS3.10 7.1 |  | `Bool` / false | match |
| `allow-burned-in-phi` (booleanToggle) | `--allow-burned-in-phi` | write despite Burned In Annotation YES / overlays | PS3.15 E.1.1 (0012,0062), E.3.1 |  | `Bool` / false | match |
| `verbose` (booleanToggle) | `--verbose` | verbosity | - |  | `Bool` / false | match |

Output parity: the executor runs dicom-anon's run() in-process — `WorkshopAnonCLI.legacyProfileNotice` (the CLI's stderr Deprecated note for a legacy list), the shared Anonymizer for the legacy profiles, PixelRedactionPlan / PixelRedactor for `--clean-pixel-data` / `--redact-region` (AnonConsole.pixelRedactionLines when verbose), AnonConsole.fileSuccessLine / fileFailureLine in directory mode, the PS3.15 Table E.1-1a action report (`Attribute actions for … (PS3.15 Table E.1-1a: D dummy, Z zero length, X removed, C cleaned, U new UID)`) on --dry-run / --verbose, AnonConsole.summary, `Anonymizer.writeAuditLog` + auditLogLine, (0002,0003) synced to the replaced (0008,0018) before writing; refusals are the CLI's (`File not found`, `Invalid anonymization profile (…)`, `PS3.15 Annex E Option flags apply only to --profile ps315: …`, `Invalid tag format: …`, `Invalid replace format: …. Use TAG=VALUE`, `Directory anonymization requires --recursive flag` / `--output directory`, `Anonymization requires --output (or use --dry-run to preview without writing)`), all exit 1 as dicom-anon's own ValidationError type gives; the missing positional is ArgumentParser's (64); any failed file exits 1. `--profile ps315` / `basic` are refused (P-STUDIO-ANON-PS315).

### dicom-image → dicom-image

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `input` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `output` (outputPath) | `--output` | output PS3.10 file or directory | PS3.10 7.1 |  | `String?` | match |
| `patient-name` (textField) | `--patient-name` | Patient's Name (0010,0010) | PS3.3 Table C.7-1 (Type 2); PS3.5 Table 6.2-1 PN |  | `String?` | match |
| `patient-id` (textField) | `--patient-id` | Patient ID (0010,0020) | PS3.3 Table C.7-1 (Type 2); PS3.5 Table 6.2-1 LO |  | `String?` | match |
| `study-description` (textField) | `--study-description` | Study Description (0008,1030) | PS3.3 Table C.7-3 (Type 3); LO |  | `String?` | match |
| `series-description` (textField) | `--series-description` | Series Description (0008,103E) | PS3.3 Table C.7-5a (Type 3); LO |  | `String?` | match |
| `study-uid` (textField) | `--study-uid` | Study Instance UID (0020,000D) | PS3.3 Table C.7-3 (Type 1); PS3.5 9.1 |  | `String?` | match |
| `series-uid` (textField) | `--series-uid` | Series Instance UID (0020,000E) | PS3.3 Table C.7-5a (Type 1); PS3.5 9.1 |  | `String?` | match |
| `series-number` (integerField) | `--series-number` | Series Number (0020,0011) | PS3.3 Table C.7-5a (Type 2); PS3.5 Table 6.2-1 IS |  | `Int?` | match |
| `instance-number` (integerField) | `--instance-number` | Instance Number (0020,0013) | PS3.3 Table C.7-9 (Type 2); IS |  | `Int?` | match |
| `modality` (textField) | `--modality` | Modality (0008,0060) | PS3.3 Table C.7-5a (Type 1); C.7.3.1.1.1 (97 Defined Terms) |  | `String?` | match |
| `strict-modality` (booleanToggle) | `--strict-modality` | reject non-Defined-Term Modality | PS3.3 C.7.3.1.1.1 |  | `Bool` / false | match |
| `conversion-type` (enumPicker) | `--conversion-type` | Conversion Type (0008,0064) | PS3.3 Table C.8-24 (Type 1) |  | `String?` | match |
| `use-exif` (booleanToggle) | `--use-exif` | Acquisition Date/Time (0008,0022/0032), Nominal Scanned Pixel Spacing (0018,2010) | PS3.3 Table C.7.10.1-1; Table C.8-25 |  | `Bool` / false | match |
| `split-pages` (booleanToggle) | `--split-pages` | one single-frame SC instance per TIFF page | PS3.3 A.8.1 |  | `Bool` / false | match |
| `recursive` (booleanToggle) | `--recursive` |  |  |  | `Bool` / false | match |
| `verbose` (booleanToggle) | `--verbose` |  |  |  | `Bool` / false | match |

Output parity: dicom-image's run() order — `--conversion-type` refusal (`… is not a Defined Term of PS3.3 Table C.8-24 (DV, DI, …)`, 64), the P-IMAGE-VR `Error: …` lines of WorkshopSCOutput.valueViolations (exit 1, nothing written), `Input path not found` / `Directory processing requires --recursive flag` / `Patient Name is required for (batch) conversion (--patient-name)` / `Patient ID is required …` (64); ImageConsole lines (batchHeader, skippedLine, fileSuccessLine / fileFailureLine, batchSummary, tiffHeader, pageSuccessLine / pageFailureLine, tiffSummary, convertingLine, convertedLine); `--modality` through the shared ModalityOptionValidator at the point of use, so a `--strict-modality` rejection is a per-file failure in batch and `Error: …` exit 1 for one file; every output passes WorkshopSCOutput.finalize ((0002,0003) = (0008,0018), ISO_IR 192); a directory / TIFF run exits 0 whatever its per-file outcomes, as the CLI does (section 4).

### dicom-pdf → dicom-pdf

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `inputPath` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `output` (outputPath) | `--output` | output file or directory | PS3.10 7.1 |  | `String?` | match |
| `extract` (booleanToggle) | `--extract` | DICOM -> document | PS3.3 Table C.24-2 Encapsulated Document (0042,0011), Encapsulated Document Length (0042,0015) | false | `Bool` / false | match |
| `patient-name` (textField) | `--patient-name` | Patient's Name (0010,0010) | PS3.3 Table C.7-1 (Type 2); PN |  | `String?` | match |
| `patient-id` (textField) | `--patient-id` | Patient ID (0010,0020) | PS3.3 Table C.7-1 (Type 2); LO |  | `String?` | match |
| `title` (textField) | `--title` | Document Title (0042,0010) | PS3.3 Table C.24-2 (Type 2); ST |  | `String?` | match |
| `study-uid` (textField) | `--study-uid` | Study Instance UID (0020,000D) | PS3.3 Table C.7-3 (Type 1) |  | `String?` | match |
| `series-uid` (textField) | `--series-uid` | Series Instance UID (0020,000E) | PS3.3 Table C.24-1 (Type 1) |  | `String?` | match |
| `modality` (textField) | `--modality` | Modality (0008,0060) | PS3.3 Table C.24-1 (Type 1, C.7.3.1.1.1 Defined Terms); A.85.x.4.3 (Enumerated M3D) |  | `String?` | match |
| `strict-modality` (booleanToggle) | `--strict-modality` | Modality Defined Terms | PS3.3 C.7.3.1.1.1 | false | `Bool` / false | match |
| `series-description` (textField) | `--series-description` | Series Description (0008,103E) | PS3.3 Table C.24-1 (Type 3); LO |  | `String?` | match |
| `series-number` (integerField) | `--series-number` | Series Number (0020,0011) | PS3.3 Table C.24-1 (Type 1); IS |  | `Int?` | match |
| `instance-number` (integerField) | `--instance-number` | Instance Number (0020,0013) | PS3.3 Table C.24-2 (Type 1); IS |  | `Int?` | match |
| `conversion-type` (enumPicker) | `--conversion-type` | Conversion Type (0008,0064) | PS3.3 Table C.8-24 (Type 1, 8 Defined Terms) |  | `String?` | match |
| `burned-in-annotation` (enumPicker) | `--burned-in-annotation` | Burned In Annotation (0028,0301) | PS3.3 Table C.24-2 (Type 1) | , YES, NO | `String?` | match |
| `hl7-instance-identifier` (textField) | `--hl7-instance-identifier` | HL7 Instance Identifier (0040,E001) | PS3.3 Table C.24-2 (Type 1C, required for CDA); ST |  | `String?` | match |
| `recursive` (booleanToggle) | `--recursive` | directory mode |  | false | `Bool` / false | match |
| `show-metadata` (booleanToggle) | `--show-metadata` | metadata report (extract) |  | false | `Bool` / false | match |
| `verbose` (booleanToggle) | `--verbose` | progress output |  | false | `Bool` / false | match |

Output parity: dicom-pdf's run() — `Input path not found` / `Directory processing requires --recursive flag` / `Patient's Name is required for (batch) encapsulation (--patient-name)` / `Patient ID is required …` / the two `--hl7-instance-identifier` rules / `--conversion-type … is not a Conversion Type (0008,0064) Defined Term of PS3.3 Table C.8-24: …` / `--burned-in-annotation … is not YES or NO …` as ArgumentParser ValidationErrors (64), other failures `Error: …` exit 1; the shared EncapsulatedDocumentBuilder chain plus setConversionType / setBurnedInAnnotation / setHL7InstanceIdentifier and WorkshopPDFEncapsulation.complete ((0042,0015), ISO_IR 192); extraction writes WorkshopPDFEncapsulation.documentBytes (cut to (0042,0015)) and reports its size; the verbose / non-verbose lines (`Extracting document from:`, `✓ Extracted … (size)`, `Extracted: …`, `Encapsulating document:`, `✓ Encapsulated … / DICOM size / Patient / Study UID / Output`, `Encapsulated: …`, the `Extraction complete:` / `Encapsulation complete:` blocks) are the CLI's; a directory run exits 0 (section 4). The Workshop keeps auto-naming inside a typed output directory (sandbox convenience).

### dicom-pixedit → dicom-pixedit

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `inputPath` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `output` (outputPath) | `--output` | output PS3.10 file | PS3.10 7.1 |  | `String` | match |
| `mask-region` (textField) | `--mask-region` | rectangle of pixels, 0-based column/row | PS3.3 C.7.6.2.1.1 (indices from 0) |  | `String?` | match |
| `fill-value` (integerField) | `--fill-value` | stored sample value | PS3.3 C.7.6.3.1 (Bits Stored, Pixel Representation) |  | `Int?` | match |
| `crop` (textField) | `--crop` | sub-matrix; Rows/Columns and Image Position (Patient) | PS3.3 Table C.7-11c; C.7.6.2.1.1 Equation C.7.6.2.1-1 |  | `String?` | match |
| `window-center` (textField) | `--window-center` | Window Center (0028,1050) | PS3.3 C.11.2.1.2 (Modality LUT output units) |  | `Double?` | match |
| `window-width` (textField) | `--window-width` | Window Width (0028,1051) | PS3.3 C.11.2.1.2 (>= 1) |  | `Double?` | match |
| `apply-window` (booleanToggle) | `--apply-window` | bake the linear VOI function into stored values | PS3.3 C.11.2.1.2 |  | `Bool` / false | match |
| `invert` (booleanToggle) | `--invert` | invert stored values across the Bits Stored range | PS3.3 C.7.6.3.1 |  | `Bool` / false | match |
| `verbose` (booleanToggle) | `--verbose` |  |  |  | `Bool` / false | match |

Output parity: dicom-pixedit's run() — `Input file not found: …`, PixelEditError texts for a bad region, WorkshopDerivedImage.fillValueViolation (`--fill-value N is outside the stored range a...b given by Bits Stored (0028,0101) and Pixel Representation (0028,0103) (PS3.3 C.7.6.3.1)`), `--apply-window requires both --window-center and --window-width`, WorkshopDerivedImage.windowWidthViolation (`… shall always be greater than or equal to 1 (PS3.3 C.11.2.1.2)`), `No operations specified. Use --mask-region, --crop, --apply-window, or --invert` — all exit 1 (the CLI's own ValidationError type); an unparseable number is ArgumentParser's two-line message (64); PixelEditConsole.headerLines / writtenLine / doneLine and the engine's verbose log, verbose-gated; the edit runs through the shared PixelEditor with `PixelEditDerivation(descriptionPrefix: "dicom-pixedit")`, so the Derived Image marking is the CLI's.

### dicom-video → dicom-video

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `operation` (subcommand) | `—` |  |  | convert, probe, extract, batch / convert | `—` | not a CLI option |
| `input` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `dicomInput` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `inputDirectory` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `output` (outputPath) | `--output` |  |  |  | `String` | match |
| `videoOutput` (outputPath) | `--output` |  |  |  | `String` | match |
| `outputDir` (outputPath) | `--output-dir` | output directory | PS3.10 7.1 |  | `String` | match |
| `type` (enumPicker) | `--type` | SOP Class / IOD | PS3.3 A.32.5, A.32.6, A.32.7; PS3.6 Table A-1 (...77.1.1.1, ...77.1.2.1, ...77.1.4.1) |  | `VideoConsole.TypeArgument?` | match |
| `transferSyntax` (textField) | `--transfer-syntax` | Transfer Syntax UID (0002,0010) | PS3.6 Table A-1 (16 MPEG2 / MPEG-4 AVC/H.264 / HEVC/H.265 rows); PS3.5 8.2.5-8.2.11 |  | `String?` | match |
| `frameRate` (textField) | `--frame-rate` | Cine Rate (0018,0040), Frame Time (0018,1063), Recommended Display Frame Rate (0008,2144) | PS3.3 Table C.7-13; PS3.5 Tables 8-2, 8-5, 8-7 |  | `Double?` | match |
| `instanceNumber` (integerField) | `--instance-number` |  |  | 1 | `Int` / 1 | match |
| `seriesNumber` (integerField) | `--series-number` |  |  | 1 | `Int` / 1 | match |
| `seriesMode` (enumPicker) | `--series-mode` | series grouping | IHE Endoscopy Image Archiving 3.10.4.1.1.1 (not DICOM) | single | `VideoConsole.SeriesMode` / .single | match |
| `recursive` (booleanToggle) | `--recursive` | descend into subdirectories |  | false | `Bool` / false | match |
| `continueOnError` (booleanToggle) | `--continue-on-error` | skip failures |  | false | `Bool` / false | match |
| `dryRun` (booleanToggle) | `--dry-run` | probe and validate only |  | false | `Bool` / false | match |
| `trustInput` (booleanToggle) | `--trust-input` | encapsulate MPEG-TS unvalidated; needs --transfer-syntax | PS3.5 8.2.7-8.2.11 | false | `Bool` / false | match |
| `force` (booleanToggle) | `--force` | overwrite output |  | false | `Bool` / false | match |
| `verbose` (booleanToggle) | `--verbose` | commentary on stderr |  | false | `Bool` / false | match |
| `patientName` (textField) | `--patient-name` | Patient's Name (0010,0010) | PS3.3 Table C.7-1 (Type 2); PS3.6 Table 6-1 PN |  | `String?` | match |
| `patientID` (textField) | `--patient-id` | Patient ID (0010,0020) | PS3.3 Table C.7-1 (Type 2); LO |  | `String?` | match |
| `patientBirthDate` (textField) | `--patient-birth-date` | Patient's Birth Date (0010,0030) | PS3.3 Table C.7-1 (Type 2); PS3.6 Table 6-1 DA |  | `String?` | match |
| `patientSex` (enumPicker) | `--patient-sex` | Patient's Sex (0010,0040) | PS3.3 Table C.7-1 (Type 2, Enumerated Values M F O) | , M, F, O | `String?` | match |
| `studyUID` (textField) | `--study-uid` | Study Instance UID (0020,000D) | PS3.3 Table C.7-3 (Type 1); PS3.5 9.1 |  | `String?` | match |
| `seriesUID` (textField) | `--series-uid` | Series Instance UID (0020,000E) | PS3.3 Table C.7-5a (Type 1); PS3.5 9.1 |  | `String?` | match |
| `accessionNumber` (textField) | `--accession-number` | Accession Number (0008,0050) | PS3.3 Table C.7-3 (Type 2); SH |  | `String?` | match |
| `studyID` (textField) | `--study-id` | Study ID (0020,0010) | PS3.3 Table C.7-3 (Type 2); SH |  | `String?` | match |
| `referringPhysician` (textField) | `--referring-physician` | Referring Physician's Name (0008,0090) | PS3.3 Table C.7-3 (Type 2); PN |  | `String?` | match |
| `seriesDescription` (textField) | `--series-description` | Series Description (0008,103E) | PS3.3 Table C.7-5a (Type 3); LO |  | `String?` | match |
| `modality` (textField) | `--modality` | Modality (0008,0060) | PS3.3 A.32.5.4.1 / A.32.6.4.1 / A.32.7.4.1 ("shall be" ES / GM / XC) |  | `String?` | match |
| `strictModality` (booleanToggle) | `--strict-modality` | Modality Defined Terms | PS3.3 C.7.3.1.1.1 (via DICOMCore ModalityOptionValidator) | false | `Bool` / false | match |
| `manufacturer` (textField) | `--manufacturer` | Manufacturer (0008,0070) | PS3.3 Table C.7-8 (Type 2); LO |  | `String?` | match |
| `institutionName` (textField) | `--institution-name` | Institution Name (0008,0080) | PS3.3 Table C.7-8 (Type 3); LO |  | `String?` | match |
| `audioChannelSource` (textField) | `--audio-channel-source` | Channel Source Sequence (003A,0208) in (003A,0300) | PS3.3 Table C.7-13; PS3.16 CID 3000 |  | `[String]` / [] | match |

Output parity: convert / batch validate the metadata as the CLI's `MetadataOptions.validatedShared()` does — `--modality` through the shared ModalityOptionValidator (`--strict-modality` → `Error: … Rejected because --strict-modality is set.`, exit 1), `--audio-channel-source` parsed by the mirrored AudioChannelSourceOption grammar (`Error: --audio-channel-source: "…" is neither a listed keyword nor SCHEME:VALUE[:MEANING]; keywords: …` / `… so its Code Meaning is required (SCHEME:VALUE:MEANING)`, exit 1) into VideoWorkflow.Metadata.audioChannelSource / audioChannelSources — then the mirrored VideoOptionConformance.violations lines (transfer syntax, modality, sex, birth date, in option order; exit 1, nothing written), in the CLI's order relative to the input read (convert) and validateBatchOptions (batch); everything else is the shared VideoWorkflow / VideoConsole as before (probe / extract unchanged).

### dicom-convert → dicom-convert

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `inputPath` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `output` (outputPath) | `--output` | output file or directory |  |  | `String` | match |
| `format` (enumPicker) | `--format` | output: PS3.10 file or PNG/JPEG/TIFF raster |  | dicom, png, jpeg, tiff / dicom | `ExportFormat` / .dicom | match |
| `transfer-syntax` (enumPicker) | `--transfer-syntax` | target Transfer Syntax UID + intent | PS3.6 Table A-1 (keyword column); PS3.5 A.1-A.4 |  | `String?` | match |
| `quality` (integerField) | `--quality` | JPEG raster quality (not DICOM) |  | 90 | `Int` / 90 | match |
| `window-center` (textField) | `--window-center` | Window Center (0028,1050) | PS3.3 C.11.2.1.2.1 |  | `Double?` | match |
| `window-width` (textField) | `--window-width` | Window Width (0028,1051) | PS3.3 C.11.2.1.2.1 ("shall always be greater than or equal to 1") |  | `Double?` | match |
| `apply-window` (booleanToggle) | `--apply-window` | VOI LINEAR window for export | PS3.3 C.11.2.1.2.1 |  | `Bool` / false | match |
| `frame-number` (integerField) | `--frame-number` |  |  |  | `Int?` | match |
| `frame` (integerField) | `--frame` | frame to export | PS3.3 C.7.6.6 / C.7.6.16 (frames numbered from 1) |  | `Int?` | match |
| `strip-private` (booleanToggle) | `--strip-private` | remove Private Data Elements | PS3.5 7.8, 7.8.1 |  | `Bool` / false | match |
| `recursive` (booleanToggle) | `--recursive` |  |  |  | `Bool` / false | match |
| `validate` (booleanToggle) | `--validate` | re-read output as PS3.10 | PS3.10 7.1 |  | `Bool` / false | match |
| `force` (booleanToggle) | `--force` | read files without preamble/DICM | PS3.10 7.1 |  | `Bool` / false | match |

Output parity: dicom-convert's validate() / run() — ArgumentParser's missing-argument and invalid-value messages (64), `--quality must be between 1 and 100`, `--window-width must be at least 1 (Window Width (0028,1051), PS3.3 C.11.2.1.2.1)`, `--frame is a 0-based frame index and must be 0 or more`, `--frame-number must be 1 or more (PS3.3 Table 10-3: …)` (64), `--frame (deprecated, 0-based) and --frame-number (numbered from 1) cannot be used together` (exit 1), the `warning: --frame is deprecated …` and `TransferSyntax.reassignedKeywordNote` notes first, `Input path not found` / `Directory conversion requires --recursive flag` (64); a single-file failure prints ConvertConsole.failureReport (exit 1), success prints only ConvertConsole.transcodeLine (DICOM) or nothing (image export); the directory run prints the shared batchProgressLine / batchSummary and exits 1 when any file failed; out-of-range frames use DICOMConverter.invalidFrameNumberMessage (Frame number) or invalidFrameMessage (deprecated index); `--transfer-syntax` resolves through the mirrored TransferSyntaxKeywords (catalog, then the 7 Table A-1 keywords) with DICOMConverter.unknownTargetMessage.

### dicom-compress → dicom-compress

| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |
|---|---|---|---|---|---|---|
| `operation` (subcommand) | `—` |  |  | info, compress, decompress, batch, backends / info | `—` | not a CLI option |
| `input` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `json` (booleanToggle) | `--json` |  |  | false | `Bool` / false | match |
| `inputDir` (filePath) | `—` |  |  |  | `—` | not a CLI option |
| `output` (outputPath) | `--output` |  |  |  | `String` | match |
| `outputDir` (outputPath) | `--output` |  |  |  | `String` | match |
| `codec` (enumPicker) | `--codec` |  |  | jpeg-lossless | `String?` | match |
| `batchCodec` (enumPicker) | `--codec` |  |  |  | `String?` | match |
| `jpegCodec` (enumPicker) | `—` |  |  | JPEGCodecEngine.jli.rawValue | `—` | internal |
| `quality` (textField) | `--quality` |  |  |  | `String?` | match |
| `syntax` (enumPicker) | `--syntax` |  |  | explicit-le | `String` / "explicit-le" | match |
| `decompress` (booleanToggle) | `--decompress` |  |  | false | `Bool` / false | match |
| `recursive` (booleanToggle) | `--recursive` |  |  | false | `Bool` / false | match |
| `backend` (enumPicker) | `--backend` |  |  | auto, metal, accelerate, scalar / auto | `String` / "auto" | match |
| `verbose` (booleanToggle) | `--verbose` |  |  | false | `Bool` / false | match |

Output parity: every line is the shared CompressionConsole's (infoText / infoJSON / infoErrorLine, compressPreamble / recompressNoteLine / compressResultLine / compressStats / compressSummary, decompressPreamble / decompressResultLine / decompressStats / decompressSummary, batchFoundLine / batchProgressLine / batchSummaryLine, backendsText / backendsJSON); the CLI's validate() refusals as exit 64 (`Input file not found: …`, `File not found: …`, `Input directory not found: …`, `Unknown codec '…'. Supported: …`, `Specify --codec for compression or use --decompress for decompression`, ArgumentParser's missing arguments), `--syntax` through the mirrored NativeTargetSyntax (`--syntax X names <uid>, an encapsulated (compressed) Transfer Syntax (PS3.6 2026a Table A-1); …` / `Unknown syntax '…'. Native targets: …`, exit 1), run failures as `Error: \(error)` (the CLI's String(describing:)), `Error scanning directory: …` and `No DICOM files found in: …` (exit 1), a batch with a failed file exits 1. The app-only JPEG engine picker (isInternal) stays out of the preview.

---

## File inventory (all 334 files)

Bucket per the method (A, B1, B2, C1, C2) is recorded for ST files once verified; CR files get "confirmed NST" or
are promoted to ST; NST files carry the scan result. "Marker" names the marker line or "none (inventoried)".

### G1 — CLI Workshop

| File | Tier | Bucket | What it carries / what was compared | Marker | Status |
|---|---|---|---|---|---|
| [BrowserNavigationHelpers.swift](Sources/DICOMStudio/Components/BrowserNavigationHelpers.swift) | ST | B2 | 15 citations: 14 exist, 1 wrong (PS3.18 §6.5) → fixed; 15 tool names are targets | see file line 5 | ✅ |
| [CLIShellFoundationHelpers.swift](Sources/DICOMStudio/Components/CLIShellFoundationHelpers.swift) | ST | B2 | allToolNames 38/42 → 42; toolDescription 38 rows → 42, 3 corrected; 5 DIMSE names = PS3.7 9.1.x titles; 4 RESTful names in PS3.18; 2 PS3.4 names | see file line 5 | ✅ |
| [CLIToolBuilder.swift](Sources/DICOMStudio/Components/CLIToolBuilder.swift) | ST | C1 | same grep: 0 | `// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (testing-only: builds the dicom-* products with swift build for the Compare-CLI diff; grep for tags, UIDs, STD-* profiles, VR codes and PS3 clauses found none)` | marked, 8f3d8daa |
| [CLIToolTerminalCompare.swift](Sources/DICOMStudio/Components/CLIToolTerminalCompare.swift) | ST | C1 | same grep: 0 | `// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (testing-only: spawns the real dicom-* binary with the Workshop's pasted command and diffs both consoles, ANSI stripped; the output parity it measures is pinned by SplitMergeWorkshopCLIParityTests and NetworkToolWorkshopCLIParityTests; grep for tags, UIDs, STD-* profiles, VR codes and PS3 clauses found none)` | marked, 8f3d8daa |
| [CLIWorkshopHelpers.swift](Sources/DICOMStudio/Components/CLIWorkshopHelpers.swift) | ST | B2 → fixed | 14 file-tool arms vs the ArgumentParser surfaces: 14/14 parity ok (189 flag rows matched, 0 wrong); pickers from shared enums (DICOMDIRProfile.allStandard, ExportImageFormat, OrganizationScheme, MergeSortCriteria, UIDConsole.lookupTypeFilters); help texts carry the CLI wording and PS3 clauses | no marker (the last Workshop agent adds it; network / pixel / codec arms pending) | edited, 2f730cac |
| [ImportValidation.swift](Sources/DICOMStudio/Components/ImportValidation.swift) | ST | B2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — DICM at offset 128 after the 128-byte preamble and the 132-byte minimum (PS3.10 2026a 7.1); the 16 import-list UIDs are PS3.6 2026a Table A-1 Transfer Syntax rows and their comment names text-diffed against A-1 (16 match after 8 abbreviations were spelled out — D9); a registered but unlisted syntax is now named from DICOMCore rather than called unrecognized; required-tag messages name (0008,0018), (0008,0016), (0020,000D) per Table 6-1` | fixed (D9) |
| [IntegratedTerminalHelpers.swift](Sources/DICOMStudio/Components/IntegratedTerminalHelpers.swift) | ST | C2 | 7 PHI keywords vs PS3.15 Table E.1-1: 7 match | see file line 5 | ✅ |
| [ParameterBuilderHelpers.swift](Sources/DICOMStudio/Components/ParameterBuilderHelpers.swift) | ST | B2 | 59 rows vs 12 CLI surfaces: 30 matched, 29 wrong → 113 rows, 113 matched (197 incl. picker values and defaults), 1 exempt (--transfer-syntax computed from DICOMConverter.aliasTokens) | see file line 5 | ✅ |
| [ShellServerConfigHelpers.swift](Sources/DICOMStudio/Components/ShellServerConfigHelpers.swift) | ST | — | to verify | — | ⏳ |
| [BrowserNavigationModel.swift](Sources/DICOMStudio/Models/BrowserNavigationModel.swift) | ST | C1 | no standard data; doc example "PS3.7 §9.1.5" exists | see file line 5 | ✅ |
| [CLIShellFoundationModel.swift](Sources/DICOMStudio/Models/CLIShellFoundationModel.swift) | ST | B2 | ToolCategory.toolNames vs 42 Sources/dicom-* targets: 38 matched, 4 missing → fixed | see file line 5 | ✅ |
| [CLIWorkshopModel.swift](Sources/DICOMStudio/Models/CLIWorkshopModel.swift) | ST | C1 | grep for (gggg,eeee), 1.2.840.10008, STD-*, VR codes, PS3 clauses: 0 | `// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (CLI Workshop data models: tool and parameter definitions, visibility conditions, history, presets, terminal/SCP log levels; grep for (gggg,eeee) tags, 1.2.840.10008 UIDs, STD-* profiles, VR codes and PS3 clauses found none); the standard-derived form content is in CLIWorkshopHelpers.swift and the executors in CLIWorkshopViewModel.swift` | marked, 8f3d8daa |
| [IntegrationTestingModel.swift](Sources/DICOMStudio/Models/IntegrationTestingModel.swift) | ST | B2 | 41 tool names vs 42 targets: 38 matched, 3 nonexistent, 4 missing → 42/42 | see file line 5 | ✅ |
| [ParameterBuilderModel.swift](Sources/DICOMStudio/Models/ParameterBuilderModel.swift) | ST | C2 | AE 16 (PS3.5 Table 6.2-1) match; "uppercase" claim removed; port range 1–65535 | see file line 5 | ✅ |
| [ShellServerConfigModel.swift](Sources/DICOMStudio/Models/ShellServerConfigModel.swift) | ST | — | to verify | — | ⏳ |
| [ValidationModel.swift](Sources/DICOMStudio/Models/ValidationModel.swift) | ST | B2 → fixed | 30 IOD keywords vs PS3.6 Table A-1 (25 matched, 5 fixed); 5 level texts vs dicom-validate --level help | `// NEMA-verified: 2026a, checked 2026-10-05 — the 30 --iod suggestions are SOP Class UID Keywords of PS3.6 2026a Table A-1 (script-checked: 25 matched, 5 corrected from Multiframe… to MultiFrame…); the 5 level descriptions carry dicom-validate's --level help wording (PS3.10 Table 7.1-1, PS3.6 Table 6-1, PS3.5 Table 6.2-1 / 6.2.1 / 9.1, PS3.3 Type 1/1C/2/2C); issue levels, run records and the command builder are plumbing` | edited, 97fa6e6f |
| [CLIWorkshopService.swift](Sources/DICOMStudio/Services/CLIWorkshopService.swift) | ST | C1 | same grep: 0 | `// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (thread-safe Workshop state holder: selected tool, parameter values, console status, history; grep for tags, UIDs, STD-* profiles, VR codes and PS3 clauses found none)` | marked, 8f3d8daa |
| [CLIWorkshopViewModel.swift](Sources/DICOMStudio/ViewModels/CLIWorkshopViewModel.swift) | ST | B2 → fixed | 14 executors vs Sources/dicom-*/main.swift: shared console / engine calls, refusal texts, exit codes (64 usage / 1 / 2 diff); CLI-local texts mirrored and script-checked (FileSetRules 34, ExportStandard 19, UIDRootRule, dicom-dump, ArchiveQueryKeys, DICOMJson / DICOMXml notes) | no marker (same) | edited, 2f730cac |
| [ValidationViewModel.swift](Sources/DICOMStudio/ViewModels/ValidationViewModel.swift) | ST | C1 | runs DICOMKit.DICOMValidator / ValidationReport; level refusal text aligned to the CLI | `// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data of its own: validation runs through the shared DICOMKit.DICOMValidator and renders through DICOMKit.ValidationReport (the dicom-validate engine and renderer); the level range 1-5 and its refusal text are dicom-validate's; IOD suggestions come from ValidationHelpers.knownIODs (PS3.6 Table A-1 keywords)` | edited, 97fa6e6f |
| [ValidationView.swift](Sources/DICOMStudio/Views/ValidationView.swift) | ST | C1 | shows ValidationHelpers texts only | `// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data of its own (SwiftUI for the dicom-validate panel: the level picker shows ValidationHelpers.levelDescription, the IOD popover ValidationHelpers.knownIODs, both verified in ValidationModel.swift; the console text is DICOMKit.ValidationReport's)` | edited, 97fa6e6f |
| [IntegratedTerminalModel.swift](Sources/DICOMStudio/Models/IntegratedTerminalModel.swift) | CR | — | confirm-read pending | — | ⏳ |
| [CLIWorkshopView.swift](Sources/DICOMStudio/Views/CLIWorkshopView.swift) | CR | — | confirm-read pending | — | ⏳ |
| [IntegrationTestingHelpers.swift](Sources/DICOMStudio/Components/IntegrationTestingHelpers.swift) | NST | — | totalToolCount literal 41 replaced by the sum of IntegrationTestToolCategory.toolCount (no marker, NST) | — | edited |
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
| [AnnotationHelpers.swift](Sources/DICOMStudio/Components/AnnotationHelpers.swift) | ST | C2 | C.10.5.1.2 point counts 5/5 (POINT 1, POLYLINE/INTERPOLATED ≥ 2, CIRCLE 2 centre+circumference, ELLIPSE 4 major then minor) | `… point counts and geometry checked against PS3.3 2026a C.10.5.1.2: …` | ✅ |
| [BlendingHelpers.swift](Sources/DICOMStudio/Components/BlendingHelpers.swift) | ST | B1 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — alpha blend underlay·(1−α) + overlay·α agrees with Relative Opacity (0070,0403) in PS3.3 2026a C.11.14 Presentation State Blending Module (1.0 = superimposed replaces underlying); the citation read C.11.11, which is the Presentation State Relationship Module in 2026a, and was corrected; opacities and fusion labels are UI values` | citation fixed |
| [CodecInspectorHelpers.swift](Sources/DICOMStudio/Components/CodecInspectorHelpers.swift) | ST | B2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — codecDisplayName resolves the UID through DICOMCore TransferSyntax and names the codec family; JPEG XL, video, Deflated Image Frame Compression (PS3.5 2026a A.4.13) and Encapsulated Uncompressed (A.4.11) were "Unknown" and are now named; every non-retired PS3.6 2026a Table A-1 transfer syntax gets a name (CodecInspectorTests)` | fixed |
| [ColorLUTHelpers.swift](Sources/DICOMStudio/Components/ColorLUTHelpers.swift) | ST | C1 | PS3.6 B.1-1 (8 palettes) vs own ramps; citation C.11.10 wrong → PS3.6 Annex B / A.33.3 | `… carries no DICOM-standard data: the palette ramps are this app's own (PS3.6 2026a Table B.1-1 defines HOT_IRON, PET, HOT_METAL_BLUE, PET_20_STEP, SPRING, SUMMER, FALL and WINTER …)` | citation fixed, ✅ |
| [EnterpriseRenderHelpers.swift](Sources/DICOMStudio/Components/EnterpriseRenderHelpers.swift) | ST | C2 | MONOCHROME1 after VOI (C.7.6.3.1.2) | `… the one standard claim checked: a MONOCHROME1 volume is shown with the minimum sample as white …` | ✅ |
| [ICCProfileHelpers.swift](Sources/DICOMStudio/Components/ICCProfileHelpers.swift) | ST | C1 | ICC.1 header fields; C.11.15.1.2 terms not modelled | `… carries no DICOM-standard data: parses the ICC.1 profile header …; the Color Space (0028,2002) Defined Terms of C.11.15.1.2 … are not modelled here …` | ✅ |
| [ImageInversion.swift](Sources/DICOMStudio/Components/ImageInversion.swift) | ST | C1 | none | `… carries no DICOM-standard data (a CoreGraphics difference blend …)` | ✅ |
| [ImageMetadataHelpers.swift](Sources/DICOMStudio/Components/ImageMetadataHelpers.swift) | ST | B2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — photometricLabel's 11 `case` terms == the PS3.3 2026a C.7.6.3.1.2 Defined Terms less the three retired in PS3.3-2001 (HSV, ARGB, CMYK): 10 matched, XYB added (D11); transfer-syntax labels are DICOMCore shortName / displayName (PS3.6 2026a Table A-1 names) instead of a 29-row hand table (D9); planar configuration 0/1 wording per C.7.6.3.1.3` | fixed (D9, D11) |
| [JP3DMPRSliceExtractor.swift](Sources/DICOMStudio/Components/JP3DMPRSliceExtractor.swift) | ST | B2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — applyWindowLevel is the PS3.3 2026a C.11.2.1.2.1 default LINEAR function (thresholds c − 0.5 ∓ (w−1)/2, slope 255/(w−1); was c ∓ w/2 with slope 255/w); slice extraction is voxel-index geometry, not Image Plane Module data` | fixed |
| [MPRHelpers.swift](Sources/DICOMStudio/Components/MPRHelpers.swift) | ST | C1 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — carries no transcribed DICOM-standard data — voxel-index slice, crosshair and reference-line arithmetic; the PS3.3 C.7.6.2 (Image Plane Module) citation names the right 2026a clause` | marked |
| [MacOSEnhancementsHelpers.swift](Sources/DICOMStudio/Components/MacOSEnhancementsHelpers.swift) | ST | C1 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (menu, shortcut, Dock, automation and Quick Look helpers)` | marked |
| [ModalityIcon.swift](Sources/DICOMStudio/Components/ModalityIcon.swift) | ST | C2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — the codes offered are DICOMCore Modality.allCases: 79 == the PS3.3 2026a C.7.3.1.1.1 Defined Terms (0 wrong, 0 missing) and 18 retired terms recognised on parse; the "79" quoted here equals that count; icons are presentation` | marked |
| [ModalityPicker.swift](Sources/DICOMStudio/Components/ModalityPicker.swift) | ST | C2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — offers DICOMCore Modality.groupedByCategory: 79 current codes == the PS3.3 2026a C.7.3.1.1.1 Defined Terms (0 wrong, 0 missing); retired and private codes stay selectable when already bound` | marked |
| [PresentationStateHelpers.swift](Sources/DICOMStudio/Components/PresentationStateHelpers.swift) | ST | B2 | LINEAR 3 branches (1 wrong → fixed), LINEAR_EXACT 3/3, SIGMOID form; 3 function terms; INVERSE rule; 4 rotation values; rotate-before-flip (was reversed → fixed) | `… \`applyLinearVOI\` thresholds and ramp are the C.11.2.1.2.1 pseudo-code verbatim (upper bound was c + w/2 …: corrected; …)` | fixed, ✅ |
| [ShutterHelpers.swift](Sources/DICOMStudio/Components/ShutterHelpers.swift) | ST | C2 | C.7.6.11 geometry and AND-combination; P-Value normalisation | `… geometry checked against PS3.3 2026a C.7.6.11: rectangle edges inclusive …, several shapes ANDed so "the least amount of image remaining shall be visible" …` | ✅ |
| [ThumbnailHelpers.swift](Sources/DICOMStudio/Components/ThumbnailHelpers.swift) | ST | B2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — supportedPhotometricInterpretations is built from DICOMCore PhotometricInterpretation == the 11 PS3.3 2026a C.7.6.3.1.2 Defined Terms less the three retired in PS3.3-2001 (was 7: YBR_PARTIAL_420, YBR_ICT, YBR_RCT, XYB missing — D10); default window presets are not standard data` | fixed (D10) |
| [WindowLevelPresets.swift](Sources/DICOMStudio/Components/WindowLevelPresets.swift) | ST | C2 | 14 modality codes ∈ C.7.3.1.1.1 (by script); presets claim nothing standard-defined; widths ≥ 1 | `… the preset centres and widths claim nothing standard-defined …; the 15 modality codes … are PS3.3 2026a C.7.3.1.1.1 Defined Terms …` | ✅ |
| [AnnotationModel.swift](Sources/DICOMStudio/Models/AnnotationModel.swift) | ST | C2 (+PEND) | GraphicType 5/5 C.10.5; GraphicLayer 4 tags ↔ 6-1 names 4/4; TextAnchorType IMAGE ∉ {PIXEL, DISPLAY, MATRIX} → P-STUDIO-ANNOTATION-UNITS | `… \`GraphicType\` raw values are the 5 Graphic Type (0070,0023) Enumerated Values of PS3.3 2026a C.10.5 …, all match; … \`TextAnchorType\` raw value IMAGE is not an Anchor Point Annotation Units (0070,0004) value … pending P-STUDIO-ANNOTATION-UNITS …` | ✅ (PEND) |
| [CodecInspectorModel.swift](Sources/DICOMStudio/Models/CodecInspectorModel.swift) | ST | C1 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (inspector state; transferSyntaxDescription is filled by CodecInspectorViewModel with the Table A-1 name)` | marked |
| [J2KTestBenchModels.swift](Sources/DICOMStudio/Models/J2KTestBenchModels.swift) | ST | C2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — J2KBenchSyntax.all is built from DICOMCore TransferSyntax.selectableEncodings, so its names are SelectableEncoding.displayName (PS3.6 2026a Table A-1 names); the 5 default UIDs of J2KTestPlan are A-1 rows and their comment names text-diffed against A-1 (5 match after .110 "JPEG XL Lossless Only" → "JPEG XL Lossless"); isLossless defaults to the registry's answer; the rest is bench plumbing` | fixed |
| [PresentationStateModel.swift](Sources/DICOMStudio/Models/PresentationStateModel.swift) | ST | B2 | Presentation LUT Shape 2/2; size mode default ∈ 3; Rescale Type default: HU → US (∈ 9); palettes 3 of 8 B.1-1 names + 4 own; 4 IOD citations corrected | `… \`PresentationLUTShape\` raw values are the 2 Presentation LUT Shape (2050,0020) Enumerated Values of PS3.3 2026a C.11.6 …` | fixed, ✅ |
| [ProgressiveDecodeModel.swift](Sources/DICOMStudio/Models/ProgressiveDecodeModel.swift) | ST | C2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — carries no transcribed DICOM-standard data — isJ2KTransferSyntax is the 7 PS3.6 2026a Table A-1 JPEG 2000 / HTJ2K rows (.90 .91 .92 .93 .201 .202 .203) resolved through DICOMCore TransferSyntax.isJPEG2000; resolution levels are codec, not DICOM, concepts` | marked |
| [ShutterModel.swift](Sources/DICOMStudio/Models/ShutterModel.swift) | ST | B2 | 4 shapes = C.7.6.11 (3) + C.7.6.15 (1); P-Value range; overlay group evenness (PS3.5 7.6; was accepted odd → fixed) | `… the 4 \`ShutterShape\` raw values are the Shutter Shape (0018,1600) Enumerated Values of PS3.3 2026a C.7.6.11 … plus C.7.6.15's BITMAP, all 4 match; …` | fixed, ✅ |
| [ViewerAnnotationText.swift](Sources/DICOMStudio/Models/ViewerAnnotationText.swift) | ST | B2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — orientation letters: direction cosines read in the PS3.3 2026a C.7.6.2.1.1 patient coordinate system (+x L, +y P, +z head) and lettered with the Patient Orientation abbreviations of C.7.6.1.1.1 (A/P, L/R, H/F — S/I corrected); compressionLine's 5 "Uncompressed" UIDs are the PS3.6 2026a Table A-1 "… VR … Endian" rows (Encapsulated Uncompressed .1.98 added, PS3.5 A.4.11); the 11 tags read are Table 6-1 rows` | fixed |
| [ViewerContentKind.swift](Sources/DICOMStudio/Models/ViewerContentKind.swift) | ST | B2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — the 5 `…Prefix` constants are PS3.6 2026a Table A-1 OID arcs under 1.2.840.10008.5.1.4.1.1 (88. SR, 104. Encapsulated, 11. Presentation State, 9.100. Waveform Presentation State, 9. Waveform), each ending in "." and used with hasPrefix — 64 member SOP Classes fit their kind, 0 wrong; the two exact UIDs (.88.59 Key Object Selection Document Storage, .66 Raw Data Storage) match A-1; the open arcs "…1.1.9"/"…1.1.11" also matched Content Assessment Results / Microscopy Bulk Simple Annotations / Standalone Curve / VOI LUT and were closed` | fixed |
| [ViewerNonImageContent.swift](Sources/DICOMStudio/Models/ViewerNonImageContent.swift) | ST | C2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — the 7 (group,element) rows of generalRows carry PS3.6 2026a Table 6-1 names (Modality, Protocol Name, Series Description, Content Date, Study Date, Series Number, Instance Number): 7 match; EncapsulatedDocumentType names and the content switch are plumbing` | marked |
| [VolumeVisualizationModel.swift](Sources/DICOMStudio/Models/VolumeVisualizationModel.swift) | ST | C1 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (3D visualisation state: plane, interpolation, projection, preset and shading enums with app-private raw values); the PS3.3 C.7.6.2 and C.18.9 citations name the right 2026a clauses; InterpolationQuality.bicubic and ObliquePlaneConfiguration are stored settings only — no resampling kernel or oblique extraction exists in DICOMStudio` | marked (open: bicubic/oblique state-only) |
| [CharLSCLICodec.swift](Sources/DICOMStudio/Services/CharLSCLICodec.swift) | ST | C2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — the throwaway wrapper file sets the PS3.3 C.7.6.3 Image Pixel attributes from the PixelDataDescriptor and encapsulates one fragment with an empty Basic Offset Table (PS3.5 2026a A.4) under JPEG-LS Lossless (A-1 .4.80); no standard data of its own` | marked |
| [FrameRenderer.swift](Sources/DICOMStudio/Services/FrameRenderer.swift) | ST | B2 | request carries modalityLUT/voiLUT/presentationLUT/iccProfile (1/1); w ≥ 1 rule; (0028,0004), (0028,2000) ∈ 6-1 | `… tiles and film cells render through the PS3.4 2026a N.2 chain (D65, D68): …` | fixed, ✅ |
| [FrameSourceCache.swift](Sources/DICOMStudio/Services/FrameSourceCache.swift) | ST | C1 | none | `… carries no DICOM-standard data (decoded-pixel cache; …)` | ✅ |
| [ImageDecodingService.swift](Sources/DICOMStudio/Services/ImageDecodingService.swift) | ST | B2 | render path vs C.11.2.1.2.1 (was stored-value window) | `… the progressive previews are now rendered through \`DICOMImageExporter.renderFrameForExport\`, the PS3.4 2026a N.2 chain …` | fixed, ✅ |
| [ImageRenderingService.swift](Sources/DICOMStudio/Services/ImageRenderingService.swift) | ST | B2 | render path vs C.11.2.1.2.1 (was stored-value window) | `… frames are now rendered through DICOMKit's \`DICOMImageExporter.renderFrameForExport\`, i.e. the PS3.4 2026a N.2 chain …` | fixed, ✅ |
| [J2KTestBenchService.swift](Sources/DICOMStudio/Services/J2KTestBenchService.swift) | ST | C1 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — carries no transcribed DICOM-standard data — encodes/decodes through DICOMKit codecs by UID, PSNR dynamic range uses Bits Stored (PS3.3 C.7.6.3.1.1) as 2^bitsStored − 1; names come from J2KBenchSyntax` | marked |
| [PresentationStateService.swift](Sources/DICOMStudio/Services/PresentationStateService.swift) | ST | C1 | N.2.1.3 (state VOI replaces image's) | `… carries no DICOM-standard data of its own: a GSPS Softcopy VOI LUT replaces the image's window (PS3.4 2026a N.2.1.3), …` | ✅ |
| [StudyPresentationStateAdoption.swift](Sources/DICOMStudio/Services/StudyPresentationStateAdoption.swift) | ST | C2 | C.11.11 sequence nesting (0008,1115 › 0008,1140 › 0008,1155); Rows/Columns/Number of Frames tags | `… reads Referenced Series Sequence (0008,1115) › Referenced Image Sequence (0008,1140) › Referenced SOP Instance UID (0008,1155) as PS3.3 2026a C.11.11 … lays them out …` | ✅ |
| [CodecInspectorViewModel.swift](Sources/DICOMStudio/ViewModels/CodecInspectorViewModel.swift) | ST | B2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — transferSyntaxDescription is DICOMCore TransferSyntax.displayName (the PS3.6 2026a Table A-1 name); it was `description`, which spelled the VR/byte-order encoding for every compressed syntax` | fixed |
| [DICOMVolumeViewerViewModel.swift](Sources/DICOMStudio/ViewModels/DICOMVolumeViewerViewModel.swift) | ST | C2 | CT/MR/PT ∈ C.7.3.1.1.1; presets not standard | `… the 8 CT viewer presets claim nothing standard-defined …; the modality codes it keys on (CT, MR, PT) are C.7.3.1.1.1 Defined Terms; …` | ✅ |
| [ImageViewerViewModel+PatientOverlay.swift](Sources/DICOMStudio/ViewModels/ImageViewerViewModel+PatientOverlay.swift) | ST | C2 | 8 tag literals ↔ Table 6-1 names, 8/8 | `… the 8 tag literals (0010,0010) Patient's Name, … are PS3.6 2026a Table 6-1 rows with those names, all 8 match; …` | ✅ |
| [ImageViewerViewModel+PresentationStates.swift](Sources/DICOMStudio/ViewModels/ImageViewerViewModel+PresentationStates.swift) | ST | B2 | 4 ImageToSave / 2 capture / 1 restore sites carry photometric + Rescale Type (6/6 by script); N.2.1.1 identity rule; SC fallback UID ∈ A-1 | `… saves hand DICOMPrintKit the image's Photometric Interpretation and Rescale Type (D42): …` | fixed, ✅ |
| [ImageViewerViewModel.swift](Sources/DICOMStudio/ViewModels/ImageViewerViewModel.swift) | ST | B2 | N.2 chain inputs; 3 photometric literals ∈ C.7.6.3.1.2; LINEAR default ∈ C.11.2; waveform arc 21/21 A-1 names after the fix (2 were wrong) | `NEMA-verified: 2026a, checked 2026-10-05 — the viewport now renders through the PS3.4 2026a N.2 chain (D65, D68): …` | fixed, ✅ |
| [J2KTestBenchViewModel.swift](Sources/DICOMStudio/ViewModels/J2KTestBenchViewModel.swift) | ST | C1 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (bench orchestration, persistence and standings); fixtures record Photometric Interpretation as DICOMCore's rawValue and syntax names as J2KBenchSyntax.shortName (A-1 names)` | marked |
| [J2KTestingViewModel.swift](Sources/DICOMStudio/ViewModels/J2KTestingViewModel.swift) | ST | C2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — the support matrix is DICOMCore TransferSyntax.selectableEncodings filtered by isJPEG2000, named by SelectableEncoding.displayName (PS3.6 2026a Table A-1 names); the one UID literal (.4.90 default) is an A-1 row; no other standard data` | marked |
| [JP3DComparisonViewModel.swift](Sources/DICOMStudio/ViewModels/JP3DComparisonViewModel.swift) | ST | C1 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (JP3D bench state); PSNR uses 2^bitsAllocated − 1 as the peak, window defaults are UI values` | marked |
| [JP3DVolumeComparisonViewModel.swift](Sources/DICOMStudio/ViewModels/JP3DVolumeComparisonViewModel.swift) | ST | C2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — codecOptions are DICOMCore TransferSyntax.selectableEncodings filtered by isJPEG2000 and named by SelectableEncoding.displayName (PS3.6 2026a Table A-1 names); the .4.90 default is an A-1 row; no other standard data` | marked |
| [PresentationStateViewModel.swift](Sources/DICOMStudio/ViewModels/PresentationStateViewModel.swift) | ST | C1 | IDENTITY default ∈ C.11.6 | `… carries no DICOM-standard data (selection state over the GSPS, shutter, palette and blending models; defaults to IDENTITY …)` | ✅ |
| [AnnotationOverlayView.swift](Sources/DICOMStudio/Views/AnnotationOverlayView.swift) | ST | C2 | draws per C.10.5.1.2 definitions | `… draws the 5 Graphic Types as PS3.3 2026a C.10.5.1.2 defines them …` | ✅ |
| [CodecInspectorView.swift](Sources/DICOMStudio/Views/CodecInspectorView.swift) | ST | C1 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — UI layout only; the #Preview's .4.90 literal and its name "JPEG 2000 Image Compression (Lossless Only)" match PS3.6 2026a Table A-1` | marked |
| [MainView.swift](Sources/DICOMStudio/Views/MainView.swift) | ST | C1 | none | `… carries no DICOM-standard data (navigation shell and library/presentation-series bookkeeping)` | ✅ |
| [SavedViewPickerView.swift](Sources/DICOMStudio/Views/SavedViewPickerView.swift) | ST | C1 | none | `… carries no DICOM-standard data (menu, naming and deletion of saved views; …)` | ✅ |
| [ShutterOverlayView.swift](Sources/DICOMStudio/Views/ShutterOverlayView.swift) | ST | B2 | C.7.6.11 combination rule (union → intersection) | `… the visible region of a shutter with several shapes is now their intersection, as PS3.3 2026a C.7.6.11 requires …` | fixed, ✅ |
| [ViewerNonImageContentView.swift](Sources/DICOMStudio/Views/ViewerNonImageContentView.swift) | ST | B2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — StructuredReportNarrativeView.value(of:) covers the 15 non-CONTAINER Value Types of PS3.3 2026a Table C.17.3-7 (TABLE was missing, D237 sibling); the video container name is DICOMKit's containerDisplayName (no exhaustive switch over VideoContainer here, D237); PS3.5 2026a 8.2.7 cited for the MPEG-4 AVC/H.264 container rule` | fixed (D237, TABLE) |
| [WindowLevelPanel.swift](Sources/DICOMStudio/Views/WindowLevelPanel.swift) | ST | C1 | width floor 1 (C.11.2.1.2.1) | `… carries no DICOM-standard data: the slider ranges … are UI conveniences in the viewer's stored-pixel units; the width floor of 1 is the LINEAR minimum …` | ✅ |
| [J2KBenchmarkBaseline.swift](Sources/DICOMStudio/Components/J2KBenchmarkBaseline.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ViewportLayoutHelpers.swift](Sources/DICOMStudio/Components/ViewportLayoutHelpers.swift) | CR | — | confirm-read pending | — | ⏳ |
| [MacOSEnhancementsModel.swift](Sources/DICOMStudio/Models/MacOSEnhancementsModel.swift) | CR | — | confirm-read pending | — | ⏳ |
| [PatientOverlayText.swift](Sources/DICOMStudio/Models/PatientOverlayText.swift) | CR → promoted | C2 | 11 tag literals ↔ 6-1 names 11/11 | `… the 11 tag literals (0010,0010), … are PS3.6 2026a Table 6-1 rows with the names the fields carry …; promoted from CR; …` | ✅ (please move to ST in diff_studio.py FILES) |
| [ViewerAnnotationCorners.swift](Sources/DICOMStudio/Models/ViewerAnnotationCorners.swift) | CR | — | read: corner text layout | — | confirmed NST |
| [ViewerHoverGeometry.swift](Sources/DICOMStudio/Models/ViewerHoverGeometry.swift) | CR | — | read: Pixel Spacing [row, column] order (C.7.6.3.1.1) and orientation cosines consumed, not defined | — | confirmed NST (one correct citation) |
| [ViewerSeriesEntry.swift](Sources/DICOMStudio/Models/ViewerSeriesEntry.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ViewerTileLayout.swift](Sources/DICOMStudio/Models/ViewerTileLayout.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ViewportModel.swift](Sources/DICOMStudio/Models/ViewportModel.swift) | CR | — | read: viewport state | — | confirmed NST |
| [FrameImageStore.swift](Sources/DICOMStudio/Services/FrameImageStore.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ThumbnailService.swift](Sources/DICOMStudio/Services/ThumbnailService.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ViewerTileImageCache.swift](Sources/DICOMStudio/Services/ViewerTileImageCache.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ViewerTileTextureCache.swift](Sources/DICOMStudio/Services/ViewerTileTextureCache.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ImageViewerViewModel+Annotations.swift](Sources/DICOMStudio/ViewModels/ImageViewerViewModel+Annotations.swift) | CR | — | read: " HU" suffix for CT only (Rescale Type HU, C.11.1.1.2); no tables | — | confirmed NST |
| [ImageViewerViewModel+Layout.swift](Sources/DICOMStudio/ViewModels/ImageViewerViewModel+Layout.swift) | CR | — | read: tile window bookkeeping, width ≥ 1 guard | — | confirmed NST |
| [ImageViewerViewModel+StudyDownload.swift](Sources/DICOMStudio/ViewModels/ImageViewerViewModel+StudyDownload.swift) | CR | — | read: ZIP download, no standard data | — | confirmed NST |
| [JP3DMPRViewModel.swift](Sources/DICOMStudio/ViewModels/JP3DMPRViewModel.swift) | CR→ST | C2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — MONOCHROME1 is inverted after windowing, as PS3.3 2026a C.7.6.3.1.2 requires ("displayed as white after any VOI gray scale transformations"; quote text-checked); the rest is MPR view state` | promoted from CR, marked |
| [MultiViewportViewModel.swift](Sources/DICOMStudio/ViewModels/MultiViewportViewModel.swift) | CR | — | confirm-read pending | — | ⏳ |
| [DICOMVolumeViewerView.swift](Sources/DICOMStudio/Views/DICOMVolumeViewerView.swift) | CR | — | read: W/C slider −1024…3072 UI range; labels | — | confirmed NST |
| [ImageMetadataOverlayView.swift](Sources/DICOMStudio/Views/ImageMetadataOverlayView.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ImageViewerView.swift](Sources/DICOMStudio/Views/ImageViewerView.swift) | CR | — | read: 2,237 lines of layout; no standard values | — | confirmed NST |
| [J2KTestBenchView.swift](Sources/DICOMStudio/Views/J2KTestBenchView.swift) | CR | — | confirm-read pending | — | ⏳ |
| [J2KTestingView.swift](Sources/DICOMStudio/Views/J2KTestingView.swift) | CR | — | confirm-read pending | — | ⏳ |
| [JP3DComparisonView.swift](Sources/DICOMStudio/Views/JP3DComparisonView.swift) | CR | — | confirm-read pending | — | ⏳ |
| [JP3DMPRView.swift](Sources/DICOMStudio/Views/JP3DMPRView.swift) | CR | — | confirm-read pending | — | ⏳ |
| [JP3DVolumeComparisonView.swift](Sources/DICOMStudio/Views/JP3DVolumeComparisonView.swift) | CR | — | confirm-read pending | — | ⏳ |
| [MacOSEnhancementsView.swift](Sources/DICOMStudio/Views/MacOSEnhancementsView.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ProgressiveImageView.swift](Sources/DICOMStudio/Views/ProgressiveImageView.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ViewerAnnotationEditLayer.swift](Sources/DICOMStudio/Views/ViewerAnnotationEditLayer.swift) | CR | — | read: SwiftUI editing of arrows/text | — | confirmed NST |
| [ViewerImageSavedViewList.swift](Sources/DICOMStudio/Views/ViewerImageSavedViewList.swift) | CR | — | read: list UI | — | confirmed NST |
| [ViewerTileGridView.swift](Sources/DICOMStudio/Views/ViewerTileGridView.swift) | CR | — | read: grid layout | — | confirmed NST |
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
| [DICOMwebHelpers.swift](Sources/DICOMStudio/Components/DICOMwebHelpers.swift) | ST | B2 | parser tags vs Table 6-1 (11/11 exist, names written) and Table CC.2.4-1 (9 event-report attrs; 2 fallbacks + 4 bare keys extra); nesting under (0074,1002) was missing → fixed; endpointSuffix 3/3; "409" vs Table 10.5.3-1 1/1; refusal codes vs CC.2.1-2 5/5 | `// NEMA-verified: 2026a, checked 2026-10-05 — UPSEventPayloadParser tags diffed against PS3.6 2026a Table 6-1 (11 tags, all match) and PS3.4 2026a Table CC.2.4-1 (progress attributes read inside Procedure Step Progress Information Sequence (0074,1002); Contact Display Name (0074,100C) top-level and inside (0074,1008); Human Performer Code Sequence (0040,4009) for UPS Assigned; bare-name keys kept as legacy fallbacks); previous-state inference against Table CC.1.1-2; changeStateRefusal text against PS3.18 2026a 11.7.1.4 and Table CC.1.1-2 / CC.2.1-2 status codes (same SCHEDULED message as dicom-wado); endpointSuffix against PS3.18 Table 10.6.1-1 (3/3); "409" against Table 10.5.3-1; URL, auth, TLS, byte and latency formatting are plumbing` | ✅ fixed `53faaa9d` |
| [NetworkingHelpers.swift](Sources/DICOMStudio/Components/NetworkingHelpers.swift) | ST | B2 | AE rule (behaviour fixed), 3 ports, FilmLayout helpers restate the model | `NEMA-verified: 2026a, checked 2026-10-05 — AE Title rule compared with PS3.5 2026a Table 6.2-1 (AE: 16 bytes maximum, Default Character Repertoire without backslash and control characters, leading/trailing spaces non-significant, not solely spaces) and PS3.8 Table 9-11: the former uppercase-letters/digits/space/underscore rule rejected valid titles such as ANY-SCP and lowercase names and was replaced by DICOMNetwork's AETitle; normalize() no longer upper-cases (the standard does not fold case). Ports compared with PS3.8 2026a 9.1.1 (104 well-known, 11112 registered) and PS3.15 2026a B.12 ("2762 dicom-tls"); 4242 is Orthanc's, not DICOM's. The Film Layout helpers restate FilmLayout (Table C.13-3 STANDARD\C,R) and carry no terms of their own.` | ✅ `956bee08` |
| [PerformanceToolsHelpers.swift](Sources/DICOMStudio/Components/PerformanceToolsHelpers.swift) | ST | B2 | 34 VR names (6 fixed), 15 tag rows 15/15, 41 UID rows (4 UIDs / 7 names fixed), 4 clause citations | `NEMA-verified: 2026a, checked 2026-10-05 — the 15 sample tag rows text-diffed against PS3.6 2026a Table 6-1 (name, keyword, VR, VM, retired: 15 of 15 match); the 34 VR names against PS3.5 2026a Table 6.2-1 (OB/OD/OF/OW corrected from "Other … String" to "Other Byte/Double/Float/Word", UI and UR now carry the full "VR Name" cell including its abbreviation); every UID literal and the name beside it against PS3.6 Table A-1 (the three Query/Retrieve rows paired Study Root names with the Patient Root UIDs 1.2.840.10008.5.1.4.1.2.1.x — the Study Root UIDs .2.2.x are what the Workshop's study/series/image-level C-FIND uses and are now written, and the Patient Root rows it uses at PATIENT level are listed beside them; 1.2.840.10008.5.1.4.34.6.4 is named Unified Procedure Step - Event; PET/US/SC and the two JPEG abbreviations spelled as in A-1); "Retired in DICOM 2014" for Explicit VR Big Endian is not datable from the 2026a text or the 2014a–2016a release notes and now reads "Retired (PS3.6 Table A-1)". The conformance notes' clause citations checked against the 2026a section titles (C-MOVE C.4.2, C-GET C.4.3, C-ECHO PS3.7 9.1.5, WADO-RS PS3.18 10.4).` | ✅ `5e557fc5`, marker count corrected to 34 in `fa11dbd0` |
| [PolishReleaseHelpers.swift](Sources/DICOMStudio/Components/PolishReleaseHelpers.swift) | ST | C1 | none | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (sample localization entries, WCAG checklist, coverage and benchmark targets); the VoiceOver label takes the modality string it is given.` | ✅ `f5b9746f` |
| [CloudIntegrationModel.swift](Sources/DICOMStudio/Models/CloudIntegrationModel.swift) | ST | C1 | none | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (cloud providers, bucket paths, transfer jobs). The PS3.18 line above is a pointer to the transport the files travel over, not a claim that any PS3.18 resource, media type or parameter is implemented here.` | ✅ `f5b9746f` |
| [DICOMwebModel.swift](Sources/DICOMStudio/Models/DICOMwebModel.swift) | ST | B2 | UPSState transitions vs Table CC.1.1-2 (3 allowed matched, 1 wrong removed); dicomTerm vs C.30.1 (4/4); UPSPriority vs C.30.2 (3/3); QIDOQueryLevel vs Table 10.6.1-1 (3/3); WADO-URI params vs Table 9.1.2-1 (4/4); WADORetrieveMode names vs Table 10.1-1 (5/5 + "Rendered" abbreviation); raw values IN_PROGRESS/CANCELLED pending P-item; 11 doc citations corrected | `// NEMA-verified: 2026a, checked 2026-10-05 — UPSState.allowedTransitions diffed against PS3.4 2026a Table CC.1.1-2 (Change State rows: SCHEDULED→IN PROGRESS; IN PROGRESS→COMPLETED/CANCELED; SCHEDULED→CANCELED removed, C310H; SCHEDULED is never a target, C303H); UPSState.dicomTerm against PS3.3 2026a C.30.1 (4/4), UPSPriority against C.30.2 (3/3); QIDOQueryLevel resources and WADOProtocol.protocolDescription parameter names against PS3.18 2026a Tables 10.6.1-1 and 9.1.2-1 (3/3, 4/4); the raw values IN_PROGRESS / CANCELLED are Studio-local spellings (P-STUDIO-UPS-STATE-RAW); DICOMwebTLSMode names TLS versions, not PS3.15 Annex B profiles (P-STUDIO-TLS-PROFILES); tabs, auth methods, job statuses, event-channel states and performance statistics carry no DICOM-standard data` | ✅ fixed `53faaa9d` (PEND 2 P-items) |
| [NetworkingModel.swift](Sources/DICOMStudio/Models/NetworkingModel.swift) | ST | B2 | Print Priority 3/3; Medium Type 3 offered, 1 wrong (BLU-RAY) fixed, 2 MAMMO not offered; Film Size ID 12/12; FilmLayout 8/8; PrintJobStatus 4 (2 fixed); MPPSStatus 3 (1 fixed); NetworkQueryLevel 4/4; port 11112 | `NEMA-verified: 2026a, checked 2026-10-05 — the Studio print enums text-diffed against PS3.3 2026a Table C.13-1 (Print Priority HIGH/MED/LOW: 3 match; Medium Type: PAPER and CLEAR FILM match, BLU-RAY corrected to BLUE FILM, the two MAMMO terms are not offered), Table C.13-3 (Film Size ID: 12 of 12 match; Image Display Format STANDARD\C,R: the 8 FilmLayout values match, columns first) and Table C.13-8 (PrintJobStatus is the app's job state, re-spelled with the Execution Status terms PENDING/PRINTING/DONE/FAILURE); MPPSStatus against PS3.3 C.4.14 (IN PROGRESS/COMPLETED/DISCONTINUED: IN_PROGRESS corrected); NetworkQueryLevel against PS3.4 Table C.6.1-1 (4 of 4); default port 11112 is the PS3.8 9.1.1 registered port. TLSMode names TLS versions, not the PS3.15 Annex B profiles — B.9–B.11 are retired in 2026a, B.12/B.13 are the live BCP 195 profiles (P-STUDIO-TLS-PROFILES); TransferPriority orders the app's queue and is not the DIMSE Priority (0000,0700). The four print enums duplicate DICOMNetwork's (D22, P-STUDIO-PRINT-ENUMS).` | ✅ `6ab02140` |
| [PerformanceToolsModel.swift](Sources/DICOMStudio/Models/PerformanceToolsModel.swift) | ST | C1 | none (record types) | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data: record types (DICOMTagEntry, UIDEntry, TransferSyntaxInfoEntry, SOPClassEntry) whose values live in PerformanceToolsHelpers.swift, and UI enums. TagGroupFilter's group prefixes (0010 patient, 0020 study, 0008/0018 series and equipment, 0028 image) are a browsing heuristic, not a PS3.6 classification; PS3.6 Table 6-1 does not group tags by entity.` | ✅ `5e557fc5` |
| [PolishReleaseModel.swift](Sources/DICOMStudio/Models/PolishReleaseModel.swift) | ST | C1 | none | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (localization, accessibility, testing, profiling, documentation and release-checklist records; the word DICOM appears only in display text).` | ✅ `f5b9746f` |
| [DICOMwebClientFactory.swift](Sources/DICOMStudio/Services/DICOMwebClientFactory.swift) | ST | B2 | keys vs Table 10.6.1-5 (7 matched; study modality key was wrong); params vs Table 8.3.4-1 (3/3 sent; fuzzymatching was never sent); open ranges vs PS3.4 C.2.2.2.5 (to-only was dropped) | `// NEMA-verified: 2026a, checked 2026-10-05 — buildQIDOQuery keys diffed against PS3.18 2026a Table 10.6.1-5 (study level Modalities in Study (0008,0061), series/instance Modality (0008,0060) — corrected) and Table 8.3.4-1 (fuzzymatching, limit, offset — fuzzymatching now sent); open Study Date ranges against PS3.4 2026a C.2.2.2.5; the tags themselves are DICOMWeb.QIDOQueryAttribute (verified 2026-09-28); authentication and TLS mapping are plumbing (PS3.18 8.11 names no mechanism)` | ✅ fixed `abce7d7e` |
| [DICOMwebService.swift](Sources/DICOMStudio/Services/DICOMwebService.swift) | ST | C1 | read in full: locked state store, no literals | `// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (locked display state for profiles, jobs, workitems and statistics; the UPS state it stores is validated by DICOMwebViewModel against PS3.4 2026a Table CC.1.1-2)` | ✅ `53faaa9d` |
| [NetworkingService.swift](Sources/DICOMStudio/Services/NetworkingService.swift) | ST | C1 | 1 literal (DICOMSTUDIO) | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (locked display state: profiles, queues, MPPS and print job records, audit entries); the only literal is the fallback AE title DICOMSTUDIO, a valid PS3.5 Table 6.2-1 AE value (11 characters). Status values are the enums of NetworkingModel.swift.` | ✅ `6ab02140` |
| [PerformanceToolsService.swift](Sources/DICOMStudio/Services/PerformanceToolsService.swift) | ST | C2 | 2 TS UIDs in A-1 | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data of its own; the two Transfer Syntax UID defaults (1.2.840.10008.1.2.1 Explicit VR Little Endian, 1.2.840.10008.1.2.4.70 JPEG Lossless SV1) are registered in PS3.6 2026a Table A-1 (checked by Scripts/diff_studio.py). The tables it holds are built by PerformanceToolsHelpers.swift, verified there.` | ✅ `5e557fc5` |
| [DICOMwebViewModel.swift](Sources/DICOMStudio/ViewModels/DICOMwebViewModel.swift) | ST | B2 | state/priority strings from DICOMWeb vs C.30.1 (4/4) and C.30.2 (3/3, STAT→HIGH as DICOMWeb); change-state refusal behaviour vs Table CC.1.1-2 / 11.7.1.4 (was a generic message, SCHEDULED→CANCELED allowed); level→key; frames resource | `// NEMA-verified: 2026a, checked 2026-10-05 — transitionUPSState refuses per PS3.4 2026a Table CC.1.1-2 and refuses a SCHEDULED target with dicom-wado's PS3.18 2026a 11.7.1.4 message; UPS state and priority strings mapped from DICOMWeb diffed against PS3.3 2026a C.30.1 (4/4) and C.30.2 (3/3; STAT folded into HIGH as DICOMWeb does); the QIDO level is passed to the query so the Table 10.6.1-5 key is chosen; frames jobs with a frame list use the Frame Pixel Data resource of Table 10.4.1.6-1; the remaining code is request plumbing over DICOMWeb (verified 2026-09-28)` | ✅ fixed `53faaa9d` |
| [NetworkingViewModel.swift](Sources/DICOMStudio/ViewModels/NetworkingViewModel.swift) | ST | B2 | enum mapping 3+3+12 cases onto DICOMNetwork; layout now passed; C-ECHO via DICOMVerificationService; no DIMSE status worded (C-FIND/MOVE/GET/STORE/MWL/MPPS are display state) | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data of its own: the print job's Priority, Medium Type and Film Size are mapped case by case onto DICOMNetwork's enums (whose raw values are the PS3.3 2026a Table C.13-1 / C.13-3 terms) and the Film Layout is handed to DICOMPrintService as a PrintLayout (Image Display Format STANDARD\C,R, Table C.13-3), which this panel used to drop; C-ECHO goes through DICOMVerificationService. C-FIND, C-MOVE/C-GET, C-STORE, MWL and MPPS here are display state loaded by the caller — no DIMSE status is produced or worded in this file.` | ✅ `6ab02140` |
| [PerformanceToolsViewModel.swift](Sources/DICOMStudio/ViewModels/PerformanceToolsViewModel.swift) | ST | C1 | 2 TS UIDs | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data of its own: UI state over PerformanceToolsService; the two Transfer Syntax UID defaults are registered in PS3.6 2026a Table A-1 and the benchmark figures are simulated, not standard values.` | ✅ `5e557fc5` |
| [DICOMwebView.swift](Sources/DICOMStudio/Views/DICOMwebView.swift) | ST | B2 | JPIP UIDs vs Table A-1 (2/4 listed → 4/4); uri tag vs Table 6-1 / PS3.5 A.6 (wrong tag → fixed); state literals vs C.30.1 (4/4); dicom-jpip option strings out of scope | `// NEMA-verified: 2026a, checked 2026-10-05 — JPIP header lists the 4 JPIP transfer syntaxes of PS3.6 2026a Table A-1 (1.2.840.10008.1.2.4.94 / .95 / .204 / .205) and the uri panel names Pixel Data Provider URL (0028,7FE0) per PS3.6 Table 6-1 and PS3.5 A.6 (was "(0008,1190) RETRIEVE URL"); UPS state strings SCHEDULED / IN PROGRESS / COMPLETED / CANCELED match PS3.3 2026a C.30.1; the dicom-jpip command strings are tool options (ISO/IEC 15444-9), out of scope; everything else is layout` | ✅ fixed `9de48296` |
| [NetworkingView.swift](Sources/DICOMStudio/Views/NetworkingView.swift) | ST | C1 | defaults 11112, DICOMSTUDIO (11 bytes) | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data of its own: the pickers enumerate NetworkingModel's enums (Table C.13-1 / C.13-3 terms, verified there) and the MPPS and print rows show those enums' raw values; the form's defaults are port 11112 (PS3.8 2026a 9.1.1 registered port) and the AE title DICOMSTUDIO (PS3.5 Table 6.2-1: 11 of 16 bytes). No DIMSE status is worded here.` | ✅ `6ab02140` |
| [PerformanceToolsView.swift](Sources/DICOMStudio/Views/PerformanceToolsView.swift) | ST | C1 | none | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (SwiftUI layout over the view model; every tag, UID, VR and SOP Class value it shows comes from PerformanceToolsHelpers.swift, verified there).` | ✅ `5e557fc5` |
| [GatewayModel.swift](Sources/DICOMStudio/Models/GatewayModel.swift) | CR | — | one constant: default `targetPort` 104 = PS3.8 2026a 9.1.1 well-known DICOM port (checked by diff_studio_g3_dimse "ports"); HL7/FHIR enums are not DICOM data | — (no marker) | confirmed NST; promote only if a single default-port constant counts |
| [CloudIntegrationViewModel.swift](Sources/DICOMStudio/ViewModels/CloudIntegrationViewModel.swift) | CR | — | confirm-read pending | — | ⏳ |
| [GatewayViewModel.swift](Sources/DICOMStudio/ViewModels/GatewayViewModel.swift) | CR | — | confirm-read pending | — | ⏳ |
| [CloudIntegrationView.swift](Sources/DICOMStudio/Views/CloudIntegrationView.swift) | CR | — | provider / bucket UI; the word DICOM in display text only | — | confirmed NST |
| [GatewayView.swift](Sources/DICOMStudio/Views/GatewayView.swift) | CR | — | HL7 ↔ DICOM / FHIR direction labels only; no tag, UID, term or clause | — | confirmed NST |
| [NetworkUtilityModel.swift](Sources/DICOMStudio/Models/NetworkUtilityModel.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [CloudIntegrationService.swift](Sources/DICOMStudio/Services/CloudIntegrationService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [DICOMwebServerProfileStorageService.swift](Sources/DICOMStudio/Services/DICOMwebServerProfileStorageService.swift) | NST | — | grep for UIDs, tags, CS terms, ports, PS3 citations: none | — (no marker, NST) | confirmed NST: JSON persistence of profiles |
| [GatewayService.swift](Sources/DICOMStudio/Services/GatewayService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [NetworkUtilityService+Parsing.swift](Sources/DICOMStudio/Services/NetworkUtilityService+Parsing.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [NetworkUtilityService.swift](Sources/DICOMStudio/Services/NetworkUtilityService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [PolishReleaseService.swift](Sources/DICOMStudio/Services/PolishReleaseService.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [ServerProfileStorageService.swift](Sources/DICOMStudio/Services/ServerProfileStorageService.swift) | NST | — | same grep: none | — | confirmed NST: JSON persistence |
| [NetworkUtilityViewModel.swift](Sources/DICOMStudio/ViewModels/NetworkUtilityViewModel.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [PolishReleaseViewModel.swift](Sources/DICOMStudio/ViewModels/PolishReleaseViewModel.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [LocalListenerView.swift](Sources/DICOMStudio/Views/LocalListenerView.swift) | NST | — | same grep: only two TextField placeholders, port "11112" (PS3.8 2026a 9.1.1 registered port, already checked by diff_studio_g3_dimse "ports") and AE title "DICOMSTUDIO" (11 bytes, within PS3.5 Table 6.2-1 VR AE 16); no other data | — | confirmed NST (placeholders match the standard; no promotion needed) |
| [NetworkUtilityView.swift](Sources/DICOMStudio/Views/NetworkUtilityView.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |
| [PolishReleaseView.swift](Sources/DICOMStudio/Views/PolishReleaseView.swift) | NST | — | not standard-touching (scan: no UID, tag, VR, code, citation, CS term, option or wire literal) | — | ⏳ |

### G4 — File, media and DICOMDIR

| File | Tier | Bucket | What it carries / what was compared | Marker | Status |
|---|---|---|---|---|---|
| [DICOMDIRParser.swift](Sources/DICOMStudio/Components/DICOMDIRParser.swift) | ST | B2 | Table F.4-1 record types 35: 29 matched, 6 missing added, 1 retired kept; record keys 8/8 in F.5-1/F.5-2/F.5-3/F.3-3; File ID backslash split (PS3.10 8.2) | `NEMA-verified: 2026a, checked 2026-10-05 — \`knownRecordTypes\` diffed against the 35 Directory Record Types of PS3.3 2026a Table F.4-1 …` | fixed, ✅ |
| [DICOMValueParser.swift](Sources/DICOMStudio/Components/DICOMValueParser.swift) | ST | B2 | per-VR formats (11 VR cases, all real VRs); PN component groups added; charset terms 32: 19 matched, 13 added | `NEMA-verified: 2026a, checked 2026-10-05 — per-VR formatting checked against PS3.5 2026a Table 6.2-1 …` | fixed, ✅ |
| [DataExchangeHelpers.swift](Sources/DICOMStudio/Components/DataExchangeHelpers.swift) | ST | B2 | 8 TS UIDs all A-1 TS rows; 6/8 names were abbreviations → DICOMCore A-1 names; Encapsulated PDF Storage UID ok; citations 2026a ok | `NEMA-verified: 2026a, checked 2026-10-05 — \`TransferSyntaxHelpers.wellKnownSyntaxes\`: the 8 UIDs are PS3.6 2026a Table A-1 Transfer Syntax rows …` | fixed, ✅ |
| [FileOperationsHelpers.swift](Sources/DICOMStudio/Components/FileOperationsHelpers.swift) | ST | B2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — DICM prefix at bytes 128–131 after the 128-byte File Preamble (PS3.10` | TS name table fixed (D9); marker is file-media's |
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
| [DICOMInspectorView.swift](Sources/DICOMStudio/Views/DICOMInspectorView.swift) | ST | B2 | binary VR set 7/7 vs 6.2-1 "Other …" + UN (OV added, D28); (7FE0,0010); private creator range 7.8.1 | `… the binary-VR set shown as bytes is now OB, OD, OF, OL, OV, OW and UN — the 6 'Other …' VRs of PS3.5 2026a Table 6.2-1 plus Unknown (OV was missing: corrected, D28); …` | fixed, ✅ |
| [DataExchangeView.swift](Sources/DICOMStudio/Views/DataExchangeView.swift) | ST | B2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — UI layout; the only standard-derived data is` | codec block fixed (D9); marker is file-media's |
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
| [CADVisualizationHelpers.swift](Sources/DICOMStudio/Components/CADVisualizationHelpers.swift) | ST | C1 | citations A.35.5 / A.35.6, TID 4000/4100/4015/4016/4018/4019 exist; no standard data | `NEMA-verified: 2026a, checked 2026-10-05 — citations checked against PS3.3 / PS3.16 2026a titles (C.17.3 is the SR Document Content Module, replaced by the CAD SR IOD and template references); carries no …` | ✅ |
| [CalibrationHelpers.swift](Sources/DICOMStudio/Components/CalibrationHelpers.swift) | ST | B1→A | 4 attributes vs PS3.6 Table 6-1 (4/4); 10.7.1.1 / 10.7.1.3 / C.7.6.2.1.1 citations corrected to 2026a titles | `NEMA-verified: 2026a, checked 2026-10-05 — the 4 attributes diffed against PS3.6 2026a Table 6-1 (Pixel Spacing (0028,0030), Imager Pixel Spacing (0018,1164), Nominal Scanned Pixel Spacing (0018,2010), E …` | fixed (citations), ✅ |
| [EncapsulatedDocumentHelpers.swift](Sources/DICOMStudio/Components/EncapsulatedDocumentHelpers.swift) | ST | B1→A | 5 MIME values vs A.45.1.4.1 / A.45.2.4 / A.85.1-A.85.3 (5/5); STL/OBJ/MTL citation A.45.3-5 -> A.85 corrected; 5 UIDs from DICOMKit (A-1) | `NEMA-verified: 2026a, checked 2026-10-05 — the 5 MIME Type of Encapsulated Document Enumerated Values matched case-insensitively against PS3.3 2026a A.45.1.4.1, A.45.2.4 and A.85.1-A.85.3 (application/pd …` | fixed (citation), ✅ |
| [HangingProtocolHelpers.swift](Sources/DICOMStudio/Components/HangingProtocolHelpers.swift) | ST | C2 | 4 modalities vs C.7.3.1.1.1 (4/4); matching logic is the app's own | `NEMA-verified: 2026a, checked 2026-10-05 — the 4 Modality values of the built-in protocols (CT, MR, PT, CR) are PS3.3 2026a Table C.7-3 Defined Terms (4/4); match scoring, series filtering and layout lab …` | ✅ |
| [MeasurementHelpers.swift](Sources/DICOMStudio/Components/MeasurementHelpers.swift) | ST | C2 | geometry; formatLength prints CID 7460 codes mm/cm; inches no code | `NEMA-verified: 2026a, checked 2026-10-05 — geometry only (PS3.3 2026a C.18.6 pixel coordinates; the physical distance uses the row and column spacing per axis as C.7.6.2 / 10.7.1.3 define them); formatLe …` | ✅ |
| [MeasurementPersistenceHelpers.swift](Sources/DICOMStudio/Components/MeasurementPersistenceHelpers.swift) | ST | C2 | 8 concepts vs Table D-1 / CIDs 7470/7471/7464/3488: 7 match, Angle external; UCUM mm/mm2/deg in CID 7460/7461/7183 | `NEMA-verified: 2026a, checked 2026-10-05 — the 8 SR concepts diffed by script against PS3.16 2026a Table D-1 and the CID tables: (125007, DCM, "Measurement Group") TID 1501 row 1; Length / Area / Mean /  …` | ✅ |
| [ParametricMapHelpers.swift](Sources/DICOMStudio/Components/ParametricMapHelpers.swift) | ST | B1→A | citation C.8.23 (Surface Segmentation in 2026a) -> C.8.32; SUV unit g/ml{SUVbw} is CID 85; no coded data | `NEMA-verified: 2026a, checked 2026-10-05 — citations checked against PS3.3 2026a section titles (C.8.23 is "Surface Segmentation" in 2026a; the Parametric Map modules are C.8.32, corrected); the colormap …` | fixed (citation), ✅ |
| [ROIHelpers.swift](Sources/DICOMStudio/Components/ROIHelpers.swift) | ST | B2 | area text: UCUM code (CID 7461) + symbol as dicom-measure; in²/px² keep symbol; µm needs P-STUDIO-MEASURE-UM | `NEMA-verified: 2026a, checked 2026-10-05 — geometry and statistics only; area text now prints the PS3.16 2026a CID 7461 UCUM code with the symbol as dicom-measure does ("250.0 mm2 (mm²)", cm2; inches and …` | fixed, ✅ |
| [RTHelpers.swift](Sources/DICOMStudio/Components/RTHelpers.swift) | ST | B1→A | citation C.8.8.5 = Structure Set Module (not RT Plan) corrected; switches exhaustive over the model enums | `NEMA-verified: 2026a, checked 2026-10-05 — citations checked against PS3.3 2026a section titles (C.8.8.5 is the Structure Set Module, not RT Plan: corrected); switches over RTROIType / RTDoseUnits are ex …` | fixed (citation), ✅ |
| [SRBuilderHelpers.swift](Sources/DICOMStudio/Components/SRBuilderHelpers.swift) | ST | B2 | 13 concepts vs Table D-1 / CIDs: 7 matched, 6 corrected; titles CID 7000/7001/7010/7021 + TID 1500/1501/2000/2010 layout (retired 121070 removed) | `NEMA-verified: 2026a, checked 2026-10-05 — the 13 coded concepts diffed by script against PS3.16 2026a Table D-1 and the CID tables (7003, 7010, 7021, 7181, 7461, 7470, 9000): 7 matched, 6 corrected ((G- …` | fixed, ✅ |
| [SRTreeHelpers.swift](Sources/DICOMStudio/Components/SRTreeHelpers.swift) | ST | C2 | 15 value-type / 7 relationship cases exhaustive over the model enums (Tables C.17.3-7/-8); TABLE absent (P-STUDIO-SR-TABLE) | `NEMA-verified: 2026a, checked 2026-10-05 — switches over the 15 ContentItemValueType cases and 7 SRRelationshipType cases are exhaustive over the model enums verified in StructuredReportModel.swift (PS3. …` | ✅ |
| [SecurityHelpers.swift](Sources/DICOMStudio/Components/SecurityHelpers.swift) | ST | B2 | preview lists vs DICOMKit Anonymizer basic/clinicalTrial: 18-tag list had 7 in common -> 14 + 8 (22/22 Table 6-1 names); 3 cipher suites in B.13 | `NEMA-verified: 2026a, checked 2026-10-05 — the anonymization preview lists are diffed by script against the DICOMKit Anonymizer profiles the app runs (basic 14 attributes, clinical trial + 8 date/time at …` | fixed, ✅ |
| [SegmentationHelpers.swift](Sources/DICOMStudio/Components/SegmentationHelpers.swift) | ST | C2 | switches exhaustive over SegmentAlgorithmType (Table C.8.20-4 3/3); Segmentation Type / CID 7150-7151 not modelled | `NEMA-verified: 2026a, checked 2026-10-05 — switches over SegmentAlgorithmType are exhaustive over the 3 Segment Algorithm Type (0062,0008) Defined Terms of PS3.3 2026a Table C.8.20-4 (verified in Special …` | ✅ |
| [TerminologyHelpers.swift](Sources/DICOMStudio/Components/TerminologyHelpers.swift) | ST | B2 | 77 entries vs every CID table: SCT 26 (17 match, 3 corrected, 6 external), LN 15 (1 match, 9 corrected, 5 external), RADLEX 18 external, UCUM 18 (14 match, 1 corrected, 4 external); 6/6 Table 8-1 names (2 corrected) | `NEMA-verified: 2026a, checked 2026-10-05 — the 77 (code, scheme, meaning) entries diffed by script against every PS3.16 2026a CID table: SCT 26 (17 match, 3 corrected — Liver 816092008 (that id is "Pelvi …` | fixed, ✅ |
| [WaveformHelpers.swift](Sources/DICOMStudio/Components/WaveformHelpers.swift) | ST | B2 | 16 Waveform Storage SOP Classes vs PS3.6 Table A-1: 16/16 after fix (7 missing, 3 abbreviated differently) | `NEMA-verified: 2026a, checked 2026-10-05 — the 16 Waveform Storage SOP Class UID suffixes and display names diffed by script against PS3.6 2026a Table A-1 (names are the A-1 name minus " Waveform Storage …` | fixed, ✅ |
| [WholeSlideImagingHelpers.swift](Sources/DICOMStudio/Components/WholeSlideImagingHelpers.swift) | ST | C1 | A.32.8 / C.8.12.4 titles; no standard data (Table C.8.12.4-2 flavors not modelled) | `NEMA-verified: 2026a, checked 2026-10-05 — citation checked against the PS3.3 2026a section title; carries no DICOM-standard data (the 40x base magnification, pyramid level mapping, tile ranges, optical- …` | ✅ |
| [AIAnalysisModel.swift](Sources/DICOMStudio/Models/AIAnalysisModel.swift) | ST | C1 | no standard data; PS3.17 Annex U citation removed | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (tabs, output-format and task enums, job and model records); the former PS3.17 Annex U radiomics citation was removed because not …` | ✅ |
| [HangingProtocolModel.swift](Sources/DICOMStudio/Models/HangingProtocolModel.swift) | ST | B2 (PEND) | ImageSortDirection vs Table C.23.3-1 Sorting Direction: 0/2 (P-STUDIO-HP-SORTING-DIRECTION); rest app model | `NEMA-verified: 2026a, checked 2026-10-05 — the only standard-shaped enum, ImageSortDirection (ASCENDING / DESCENDING), diffed against PS3.3 2026a Sorting Direction (0072,0604) Enumerated Values INCREASIN …` | marker, P-item |
| [SecurityModel.swift](Sources/DICOMStudio/Models/SecurityModel.swift) | ST | B2 | TLS minimum versions vs PS3.15 B.12 (development TLS 1.0 -> 1.2; B.9/B.10 retired in 2026a); profile descriptions vs engine (14/22/3); cliFlag ok | `NEMA-verified: 2026a, checked 2026-10-05 — SecurityTLSMode is the app's own policy, not a PS3.15 profile: its minimum versions checked against PS3.15 2026a B.12 ("Servers and clients shall support TLS 1. …` | fixed, ✅ |
| [SpecializedModalityModel.swift](Sources/DICOMStudio/Models/SpecializedModalityModel.swift) | ST | B2 | RTROIType 6/25 + OTHER (PEND); RTDoseUnits 1 match, CGY wrong, 2 missing (PEND); RTRadiationType 4/4; SegmentAlgorithmType 3/3; MIME 5 (CDA corrected text/XML); 5 SC UIDs A-1 | `NEMA-verified: 2026a, checked 2026-10-05 — enum raw values diffed by script against PS3.3 2026a: RTROIType 7 cases vs RT ROI Interpreted Type (3006,00A4) Defined Terms (Table C.8-44: 6 match, OTHER is no …` | fixed, ✅ (+2 P-items) |
| [StructuredReportModel.swift](Sources/DICOMStudio/Models/StructuredReportModel.swift) | ST | B2 | 8 SOP UIDs A-1; value types 15/16 (TABLE PEND); relationships 7/7; continuity 2/2; SCOORD 5 + POLYGON (PEND); SCOORD3D 6/6; TCOORD 6/6; 5 designators Table 8-1 (DCM name corrected) | `NEMA-verified: 2026a, checked 2026-10-05 — 8 SOP Class UIDs diffed against PS3.6 2026a Table A-1 (8 registered, names match; measurementReport reuses Enhanced SR Storage); ContentItemValueType 15 cases a …` | fixed, ✅ (+2 P-items) |
| [HangingProtocolService.swift](Sources/DICOMStudio/Services/HangingProtocolService.swift) | ST | C1 | no standard data | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (protocol storage, selection and active-protocol state over HangingProtocolHelpers) …` | ✅ |
| [SecurityService.swift](Sources/DICOMStudio/Services/SecurityService.swift) | ST | C1 | state store | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (locked state store for certificates, server entries, anonymization jobs and rules, audit entries, sessions; defaults .compatible …` | ✅ |
| [SpecializedModalityService.swift](Sources/DICOMStudio/Services/SpecializedModalityService.swift) | ST | C1 | no standard data | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (thread-safe display state over the SpecializedModalityModel types verified there) …` | ✅ |
| [StructuredReportService.swift](Sources/DICOMStudio/Services/StructuredReportService.swift) | ST | C1 | no standard data | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (thread-safe document, terminology, CAD and builder state) …` | ✅ |
| [AIAnalysisViewModel.swift](Sources/DICOMStudio/ViewModels/AIAnalysisViewModel.swift) | ST | C1 | dicom-ai subcommands/options named exist | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data; the dicom-ai command lines it shows (classify / segment / detect / enhance with --model and --confidence) name real dicom-ai sub …` | ✅ |
| [HangingProtocolViewModel.swift](Sources/DICOMStudio/ViewModels/HangingProtocolViewModel.swift) | ST | C1 | no standard data | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (editing state and protocol selection over HangingProtocolService; the modality it edits is free text) …` | ✅ |
| [SecurityViewModel.swift](Sources/DICOMStudio/ViewModels/SecurityViewModel.swift) | ST | C1 | engine mapping; no standard data | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data of its own: the UI profiles are mapped onto the DICOMKit Anonymizer profiles (basic / clinicalTrial / research / custom, enginePr …` | ✅ |
| [SpecializedModalityViewModel.swift](Sources/DICOMStudio/ViewModels/SpecializedModalityViewModel.swift) | ST | C1 | only "mV" UCUM channel unit | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data beyond the ECG channel unit "mV" (a UCUM code; PS3.3 2026a C.10.9 Channel Sensitivity Units Sequence carries UCUM codes) and tab  …` | ✅ |
| [StructuredReportViewModel.swift](Sources/DICOMStudio/ViewModels/StructuredReportViewModel.swift) | ST | B2 | document title was (121070, DCM, displayName) -> SRBuilderHelpers.documentTitle (CID 7000/7021/7010, TID 4000/4100) | `NEMA-verified: 2026a, checked 2026-10-05 — the only standard data was the document title it built: retired (121070, DCM, "Findings") with the document type's display name as meaning; now SRBuilderHelpers …` | fixed, ✅ |
| [AIAnalysisView.swift](Sources/DICOMStudio/Views/AIAnalysisView.swift) | ST | C1 | UI only | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (UI state and layout only) …` | ✅ |
| [HangingProtocolPanel.swift](Sources/DICOMStudio/Views/HangingProtocolPanel.swift) | ST | C1 | UI only | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (UI state and layout only) …` | ✅ |
| [SecurityView.swift](Sources/DICOMStudio/Views/SecurityView.swift) | ST | C1 | UI only | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (UI state and layout; the profile picker shows AnonymizationProfile display names and `--profile <cliFlag>`, verified in Security …` | ✅ |
| [PrivacySettingsView.swift](Sources/DICOMStudio/Views/Settings/PrivacySettingsView.swift) | ST | C1 | no Annex E / CID 7050 displayed | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (three toggles bound to SettingsViewModel; no PS3.15 Annex E profile or CID 7050 code is displayed) …` | ✅ |
| [StructuredReportView.swift](Sources/DICOMStudio/Views/StructuredReportView.swift) | ST | C1 | shows model enum raw values | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data of its own (it shows the value type and relationship raw values of the model enums verified in StructuredReportModel.swift); UI s …` | ✅ |
| [WaveformChartView.swift](Sources/DICOMStudio/Views/WaveformChartView.swift) | ST | C1 | C.10.9 / A.34 titles; grid/themes are conventions | `NEMA-verified: 2026a, checked 2026-10-05 — citations checked against PS3.3 2026a section titles; carries no DICOM-standard data (the 1 mm / 5 mm grid, paper and monitor themes, and the Hz / s metadata la …` | ✅ |
| [MeasurementModel.swift](Sources/DICOMStudio/Models/MeasurementModel.swift) | NST | — | left alone (MeasurementUnit raw values mm/cm/in read by the G5 UCUM check: mm, cm are CID 7460 codes) | — | NST, no marker |
| [ROIModel.swift](Sources/DICOMStudio/Models/ROIModel.swift) | NST | — | left alone (MeasurementUnit raw values mm/cm/in read by the G5 UCUM check: mm, cm are CID 7460 codes) | — | NST, no marker |
| [AIAnalysisService.swift](Sources/DICOMStudio/Services/AIAnalysisService.swift) | NST | — | left alone (MeasurementUnit raw values mm/cm/in read by the G5 UCUM check: mm, cm are CID 7460 codes) | — | NST, no marker |
| [CalibrationService.swift](Sources/DICOMStudio/Services/CalibrationService.swift) | NST | — | left alone (MeasurementUnit raw values mm/cm/in read by the G5 UCUM check: mm, cm are CID 7460 codes) | — | NST, no marker |
| [MeasurementService.swift](Sources/DICOMStudio/Services/MeasurementService.swift) | NST | — | left alone (MeasurementUnit raw values mm/cm/in read by the G5 UCUM check: mm, cm are CID 7460 codes) | — | NST, no marker |
| [MeasurementViewModel.swift](Sources/DICOMStudio/ViewModels/MeasurementViewModel.swift) | NST | — | left alone (MeasurementUnit raw values mm/cm/in read by the G5 UCUM check: mm, cm are CID 7460 codes) | — | NST, no marker |

### G6 — Print

| File | Tier | Bucket | What it carries / what was compared | Marker | Status |
|---|---|---|---|---|---|
| [PrinterStatusPresentation.swift](Sources/DICOMStudio/Components/PrinterStatusPresentation.swift) | ST | C2 | 3 Printer Status values + unknown covered 4/4 | `NEMA-verified: 2026a, checked 2026-10-05 — the three Printer Status (2110,0010) values of PS3.3 2026a Table C.13-9 (NORMAL, WARNING, FAILURE) are DICOMNetwork's PrinterStatusSeverity cases, each given its own colour and glyph here plus unknown; Printer Status Info (2110,0020) is shown as the SCP sent it. No literal of its own.` | ✅ `77d47fd1` |
| [PrinterProfile.swift](Sources/DICOMStudio/Models/PrinterProfile.swift) | ST | C2 | port 11112, DICOMSTUDIO, colour mode → PrintColorMode | `NEMA-verified: 2026a, checked 2026-10-05 — default port 11112 is the PS3.8 2026a 9.1.1 registered DICOM port; the default AE title DICOMSTUDIO is a valid PS3.5 Table 6.2-1 AE value (11 of 16 bytes); the colour mode maps onto DICOMNetwork's PrintColorMode (Basic Grayscale / Basic Color Print Management, PS3.4 Annex H). No other standard data.` | ✅ `77d47fd1` |
| [PrintCellTextureCache.swift](Sources/DICOMStudio/Services/PrintCellTextureCache.swift) | ST | C1 | none (Polarity composed as FilmComposer) | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data; Polarity REVERSE (2020,0020, PS3.3 2026a Table C.13-5) and the rendered-inverse Presentation LUT are composed into the shader's invert flag exactly as DICOMPrintKit's FilmComposer composes them on the sheet.` | ✅ `77d47fd1` |
| [PrintService.swift](Sources/DICOMStudio/Services/PrintService.swift) | ST | C1 | none | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data: an adapter over DICOMPrintKit's PrintImagePreparer / PrintWorkflow and DICOMNetwork's DICOMVerificationService; the Film Size and orientation it pads cells against come from the request's enums, verified in DICOMNetwork.` | ✅ `77d47fd1` |
| [PrintSCPViewModel.swift](Sources/DICOMStudio/ViewModels/PrintSCPViewModel.swift) | ST | C1 | none of its own | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data of its own: the reported Printer Status and Status Info (PS3.3 2026a Table C.13-9 / C.13.9.1) are DICOMPrintKit's EmulatedPrinterStatus values, pushed to the handler unchanged, and every log line is worded by PrintSCPConsole.` | ✅ `77d47fd1` |
| [PrintViewModel+CellEditing.swift](Sources/DICOMStudio/ViewModels/PrintViewModel+CellEditing.swift) | ST | C2 | MONOCHROME1/2 terms (generic check 2/2), Samples per Pixel rule C.13-5 | `NEMA-verified: 2026a, checked 2026-10-05 — the colour test reads Samples per Pixel (0028,0002) first and falls back to Photometric Interpretation, treating MONOCHROME1 and MONOCHROME2 (PS3.3 2026a C.7.6.3.1.2 terms) as grey — the rule PS3.3 Table C.13-5 fixes for the Basic Color Image Box (RGB, 3 samples). Polarity REVERSE (2020,0020) and the Presentation LUT inverse compose as FilmComposer composes them; no other literal.` | ✅ `77d47fd1` |
| [PrintViewModel+PresentationStates.swift](Sources/DICOMStudio/ViewModels/PrintViewModel+PresentationStates.swift) | ST (G6) | — | D42 only: `itemApplying(…, photometricInterpretation:)` and the restore call pass the cell's photometric; no marker added (print agent's file) | — | D42 hunk only |
| [PrintViewModel.swift](Sources/DICOMStudio/ViewModels/PrintViewModel.swift) | ST | C2 | density defaults BLACK 2/2; custom format default ROW\1,2; Execution Status shown unchanged | `NEMA-verified: 2026a, checked 2026-10-05 — the job settings are DICOMNetwork enums (PrintPriority, MediumType, FilmDestination, FilmSize, FilmOrientation, MagnificationType, TrimOption, ImagePolarity, PresentationLUTShape), whose raw values were verified against PS3.3 2026a Tables C.13-1 / C.13-3 / C.13-5 / C.11-4 in DICOMNetwork; the two density literals BLACK are Table C.13-3 Border / Empty Image Density terms, and the hand-typed Image Display Format (default ROW\1,2) is validated by DICOMPrintKit's PrintImageDisplayFormat against C.13.3 before it is sent. The execution-status re-query shows the printer's own Execution Status (C.13-8) string unchanged.` | ✅ `77d47fd1` |
| [FilmPreviewView.swift](Sources/DICOMStudio/Views/Print/FilmPreviewView.swift) | ST | C2 | BLACK/WHITE/i densities 2/2; Trim; FilmSheet | `NEMA-verified: 2026a, checked 2026-10-05 — Border Density (2010,0100) and Empty Image Density (2010,0110) are drawn for the three forms PS3.3 2026a Table C.13-3 defines — BLACK, WHITE, and i in hundredths of OD (read as FilmComposer reads it); the sheet's shape comes from DICOMPrintKit's FilmSheet for the job's Film Size ID and Film Orientation; Trim YES draws the composer's corner marks. No other standard literal is carried.` | ✅ `77d47fd1` |
| [PrintSCPView.swift](Sources/DICOMStudio/Views/Print/PrintSCPView.swift) | ST | B2 | 13 labels vs Table 6-1 (2 fixed); 3 Printer Status; 3 Execution Status words | `NEMA-verified: 2026a, checked 2026-10-05 — the 13 attribute labels with tags in attributeRows (Film Size ID (2010,0050) … Presentation LUT Shape (2050,0020)) text-diffed against PS3.6 2026a Table 6-1: 13 of 13 labels are the attribute name of their tag ("Film Size" and "Magnification" were abbreviations and now read Film Size ID / Magnification Type; Scripts/diff_studio_g6.py); the Printer Status picker lists DICOMPrintKit's EmulatedPrinterStatus (Table C.13-9 NORMAL/WARNING/FAILURE) and the Print Job event help names the C.13-8 Execution Status progression PENDING → PRINTING → DONE. The attribute values shown are the received ones.` | ✅ `77d47fd1` |
| [PrintSettingsView.swift](Sources/DICOMStudio/Views/Print/PrintSettingsView.swift) | ST | B2 | Film Destination 3 terms (BIN_i now any i); Bits Stored help citation fixed; all other terms from PrintOptionCatalog | `NEMA-verified: 2026a, checked 2026-10-05 — every print term offered here comes from DICOMPrintKit's PrintOptionCatalog over DICOMNetwork's enums (verified in those modules against PS3.3 2026a Tables C.13-1, C.13-3, C.13-5 and C.11-4); this file adds no literal of its own. Film Destination (2000,0040) now offers BIN_i for any i ≥ 1 through FilmDestination.bin(n) — Table C.13-1 puts no maximum on the number of sorter bins and the catalogue lists only BIN_1 and BIN_2. The bit-depth help cited Table C.13-3 for the Bits Stored 8/12 rule; the rule is in the Image Box Pixel Presentation Module, Table C.13-5 (D23's sibling).` | ✅ `77d47fd1` |
| [PrintSCPModel.swift](Sources/DICOMStudio/Models/PrintSCPModel.swift) | CR | — | confirm-read pending | — | ⏳ |
| [PrintSelectionModel.swift](Sources/DICOMStudio/Models/PrintSelectionModel.swift) | CR | — | confirm-read pending | — | ⏳ |
| [PrintImageNumberCache.swift](Sources/DICOMStudio/Services/PrintImageNumberCache.swift) | ST | C2 | 3 tags vs Table 6-1 3/3 | `NEMA-verified: 2026a, checked 2026-10-05 — the three tags read — Instance Number (0020,0013), Series Description (0008,103E), Modality (0008,0060) — checked against PS3.6 2026a Table 6-1 (names and tags match; Scripts/diff_studio_g6.py); the parse stops at Instance Number because it follows the other two in tag order.` | ✅ `77d47fd1` |
| [PrintQueueService.swift](Sources/DICOMStudio/Services/PrintQueueService.swift) | CR | — | confirm-read pending | — | ⏳ |
| [PrintSCPSettingsStorageService.swift](Sources/DICOMStudio/Services/PrintSCPSettingsStorageService.swift) | CR | — | confirm-read pending | — | ⏳ |
| [PrintThumbnailCache.swift](Sources/DICOMStudio/Services/PrintThumbnailCache.swift) | CR | — | confirm-read pending | — | ⏳ |
| [ImageViewerViewModel+Print.swift](Sources/DICOMStudio/ViewModels/ImageViewerViewModel+Print.swift) | ST | C2 | 2 tags vs Table 6-1 2/2 | `NEMA-verified: 2026a, checked 2026-10-05 — the two tags read — Series Description (0008,103E) and Instance Number (0020,0013) — checked against PS3.6 2026a Table 6-1 (names and tags match; Scripts/diff_studio_g6.py).` | ✅ `77d47fd1` |
| [PrintViewModel+CellSync.swift](Sources/DICOMStudio/ViewModels/PrintViewModel+CellSync.swift) | CR | — | confirm-read pending | — | ⏳ |
| [FilmLayoutGalleryView.swift](Sources/DICOMStudio/Views/Print/FilmLayoutGalleryView.swift) | CR | — | two prose mentions of PS3.3 C.13.3 (ROW\R1,R2 lets rows hold different counts) — accurate against the 2026a Image Display Format list; no literal of its own (the custom format string is PrintViewModel's) | — | confirmed NST |
| [PrintCenterView.swift](Sources/DICOMStudio/Views/Print/PrintCenterView.swift) | CR | — | confirm-read pending | — | ⏳ |
| [PrintProgressView.swift](Sources/DICOMStudio/Views/Print/PrintProgressView.swift) | CR | — | grep for UIDs, tags, PS3 citations, CS-looking literals: none | — | confirmed NST |
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
