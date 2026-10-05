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
| G3 Network and web | 19 | 5 | 13 | 37 | ⏳ DIMSE / print-model files done 2026-10-05 (`6ab02140`…`fa11dbd0`; `--group G3`: 0 FAIL, 2 PEND); DICOMweb files pending |
| G4 File, media and DICOMDIR | 31 | 8 | 3 | 42 | ✅ 2026-10-05 (markers `b0eca043`, checks `f02ee47a`, fixes `e6c2a11a`…`1793c091`; `diff_studio.py --group G4`: 22 ok, 0 FAIL; two files share hunks with the codec pass) |
| G5 Derived objects, SR and security | 36 | 0 | 6 | 42 | ⏳ |
| G6 Print | 11 | 11 | 17 | 39 | ✅ 2026-10-05 (`77d47fd1`; `diff_studio.py --group G6`: 0 FAIL; DICOMPrintKit finding: `PrintOptionCatalog.filmDestinations` stops at BIN_2) |
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

---

## Priority action list (P-items: public API, owner's decision needed)

| Item | What | Standard | Recommendation | Status |
|---|---|---|---|---|
| P-STUDIO-ANON-PS315 | `AnonymizationProfile` (DICOMStudio, public enum) has no case for the PS3.15 Basic Profile, which is dicom-anon's default (`ps315`); the Workshop refuses it, the Security panel cannot run it | PS3.15 2026a Annex E, Table E.1-1 | Add `.ps315` (display "PS3.15 Basic Application Level Confidentiality Profile"), make it the default, route it to `Anonymizer.deidentify`; keep the legacy cases, labelled as not PS3.15 | ⏳ pending |
| P-VIDEO-CONTAINER | DICOMKit `VideoContainer` lacks `.mpegPS` / `.mpegPES` because `ViewerNonImageContentView.swift` switches exhaustively (D237) | PS3.5 2026a 8.2.5, 8.2.6 | Give the Studio switch a `default`, then add the two cases in DICOMKit (D237) | ⏳ pending |
| P-STUDIO-TLS-PROFILES | `TLSMode` (NONE / TLS_1_2 / TLS_1_3 / MTLS) cites "PS3.15 Annex B" but selects TLS versions and client-certificate use, not a Secure Transport Connection Profile; B.9–B.11 are retired in 2026a, the live TLS profiles are B.12 "BCP 195 RFC 8996, 9325 TLS" (TLS 1.2 required, 1.3 preferred) and B.13 "Modified BCP 195 RFC 8996, 9325 TLS". | PS3.15 2026a Annex B (B.12, B.13) | Either re-label the doc comment as a transport setting (no profile claim) — text only, done implicitly by the marker — or add cases `bcp195` / `modifiedBcp195` that configure the DICOMNetwork TLS options per B.12 / B.13 and deprecate `tls12` / `tls13` (a profile forbids pinning TLS 1.2 alone). New enum cases are public API — not done. | | ⏳ pending |
| P-STUDIO-PRINT-ENUMS | `DICOMStudio.PrintPriority`, `PrintMediumType`, `PrintFilmSize`, `PrintJobStatus` (NetworkingModel.swift) duplicate `DICOMNetwork.PrintPriority` / `MediumType` / `FilmSize` and the Execution Status terms; `PrintMediumType` offers 3 of the 5 Medium Type terms (no MAMMO). Their raw values are now the standard's terms and are mapped case-by-case onto DICOMNetwork's before anything reaches the wire. | PS3.3 2026a Table C.13-1, C.13-3, C.13-8 (D22) | Deprecate the three Studio enums with `@available(*, deprecated, renamed:)` typealiases onto `DICOMNetwork.PrintPriority`, `MediumType`, `FilmSize` (the raw-value sets are now identical for Priority and Film Size; Medium Type gains the two MAMMO terms in the picker), move `displayName` to extensions on the DICOMNetwork types, drop the switch mappings in `NetworkingViewModel.submitPrintJob`; keep `PrintJobStatus` (it is the panel's state, not a wire attribute) but rename to `NetworkPrintJobState` to stop it reading as the Print Job SOP Class's Execution Status. Public API — not done. | | ⏳ pending |

---

## Deferred findings

### Rows inherited from earlier reports (worked first)

| Row | From | File | Problem | Standard | Status |
|---|---|---|---|---|---|
| D9 | DICOMCore | `Models/J2KTestBenchModels.swift:123,392` | .4.110 called "JPEG XL Lossless Only"; PS3.6 name "JPEG XL Lossless" | PS3.6 Table A-1 | ✅ 2026-10-05: every transfer-syntax display name tied to a UID in Studio text is the Table A-1 name or DICOMCore's shortName/displayName; abbreviations in ImportValidation, J2KTestBenchModels, FileOperationsHelpers spelled out; CompressionAlgorithmHelpers UIDs corrected; check `G2 codec: transfer-syntax names` (50 matched, 0 wrong) over all Studio ST files (1bbc18a8) |
| D10 | DICOMCore | `Components/ThumbnailHelpers.swift:107` | `supportedPhotometricInterpretations` omits XYB, YBR_PARTIAL_420, YBR_ICT, YBR_RCT | PS3.3 C.7.6.3.1.2 | ✅ 2026-10-05: ThumbnailHelpers.supportedPhotometricInterpretations built from DICOMCore PhotometricInterpretation; 11 terms == C.7.6.3.1.2 less HSV/ARGB/CMYK; pinned (1b0588eb) |
| D11 | DICOMCore | `Components/ImageMetadataHelpers.swift:62` | no label for XYB | PS3.3 C.7.6.3.1.2 | ✅ 2026-10-05: ImageMetadataHelpers.photometricLabel gains XYB; 11 labels checked term by term (1b0588eb) |
| D22 | DICOMNetwork | `Models/NetworkingModel.swift` (~L907-1050) | `PrintMediumType.bluFilm = "BLU-RAY"`; re-declared print enums | PS3.3 C.13.1 | ✅ 2026-10-05 strings (`6ab02140`: BLUE FILM, DONE/FAILURE, IN PROGRESS; FilmLayout now reaches the wire as Image Display Format); the duplicate enums are P-STUDIO-PRINT-ENUMS |
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
| D237 | DICOMCLI | `Views/ViewerNonImageContentView.swift:422` | exhaustive switch blocks `VideoContainer.mpegPS` / `.mpegPES` | PS3.5 8.2.5, 8.2.6 | ✅ Studio half 2026-10-05 `88c271c6`: the view uses DICOMKit `ExtractedVideo.containerDisplayName`, no exhaustive switch over `VideoContainer` remains; adding `.mpegPS` / `.mpegPES` in DICOMKit is P-VIDEO-CONTAINER |

### New findings for other modules

| ID | Module | File | Problem | Standard | Severity | Status |
|---|---|---|---|---|---|---|
| D-new | (none in DICOMKit/DICOMCore from this pass) | | | | | ⏳ |
| D242 | DICOMPrintKit | Sources/DICOMPrintKit/PrintOptionCatalog.swift:217 | `filmDestinations` offers only MAGAZINE, PROCESSOR, BIN_1, BIN_2; the dicom-print CLI therefore cannot name a bin above 2 although `FilmDestination.bin(n)` exists (Studio works around it with its own bin-number field) | PS3.3 2026a C.13.1 Table C.13-1 (BIN_i, "no maximum is placed on the number of BINs") | Low | ⏳ |

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
| [ImportValidation.swift](Sources/DICOMStudio/Components/ImportValidation.swift) | ST | B2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — DICM at offset 128 after the 128-byte preamble and the 132-byte minimum (PS3.10 2026a 7.1); the 16 import-list UIDs are PS3.6 2026a Table A-1 Transfer Syntax rows and their comment names text-diffed against A-1 (16 match after 8 abbreviations were spelled out — D9); a registered but unlisted syntax is now named from DICOMCore rather than called unrecognized; required-tag messages name (0008,0018), (0008,0016), (0020,000D) per Table 6-1` | fixed (D9) |
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
| [BlendingHelpers.swift](Sources/DICOMStudio/Components/BlendingHelpers.swift) | ST | B1 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — alpha blend underlay·(1−α) + overlay·α agrees with Relative Opacity (0070,0403) in PS3.3 2026a C.11.14 Presentation State Blending Module (1.0 = superimposed replaces underlying); the citation read C.11.11, which is the Presentation State Relationship Module in 2026a, and was corrected; opacities and fusion labels are UI values` | citation fixed |
| [CodecInspectorHelpers.swift](Sources/DICOMStudio/Components/CodecInspectorHelpers.swift) | ST | B2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — codecDisplayName resolves the UID through DICOMCore TransferSyntax and names the codec family; JPEG XL, video, Deflated Image Frame Compression (PS3.5 2026a A.4.13) and Encapsulated Uncompressed (A.4.11) were "Unknown" and are now named; every non-retired PS3.6 2026a Table A-1 transfer syntax gets a name (CodecInspectorTests)` | fixed |
| [ColorLUTHelpers.swift](Sources/DICOMStudio/Components/ColorLUTHelpers.swift) | ST | — | to verify | — | ⏳ |
| [EnterpriseRenderHelpers.swift](Sources/DICOMStudio/Components/EnterpriseRenderHelpers.swift) | ST | — | to verify | — | ⏳ |
| [ICCProfileHelpers.swift](Sources/DICOMStudio/Components/ICCProfileHelpers.swift) | ST | — | to verify | — | ⏳ |
| [ImageInversion.swift](Sources/DICOMStudio/Components/ImageInversion.swift) | ST | — | to verify | — | ⏳ |
| [ImageMetadataHelpers.swift](Sources/DICOMStudio/Components/ImageMetadataHelpers.swift) | ST | B2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — photometricLabel's 11 `case` terms == the PS3.3 2026a C.7.6.3.1.2 Defined Terms less the three retired in PS3.3-2001 (HSV, ARGB, CMYK): 10 matched, XYB added (D11); transfer-syntax labels are DICOMCore shortName / displayName (PS3.6 2026a Table A-1 names) instead of a 29-row hand table (D9); planar configuration 0/1 wording per C.7.6.3.1.3` | fixed (D9, D11) |
| [JP3DMPRSliceExtractor.swift](Sources/DICOMStudio/Components/JP3DMPRSliceExtractor.swift) | ST | B2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — applyWindowLevel is the PS3.3 2026a C.11.2.1.2.1 default LINEAR function (thresholds c − 0.5 ∓ (w−1)/2, slope 255/(w−1); was c ∓ w/2 with slope 255/w); slice extraction is voxel-index geometry, not Image Plane Module data` | fixed |
| [MPRHelpers.swift](Sources/DICOMStudio/Components/MPRHelpers.swift) | ST | C1 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — carries no transcribed DICOM-standard data — voxel-index slice, crosshair and reference-line arithmetic; the PS3.3 C.7.6.2 (Image Plane Module) citation names the right 2026a clause` | marked |
| [MacOSEnhancementsHelpers.swift](Sources/DICOMStudio/Components/MacOSEnhancementsHelpers.swift) | ST | C1 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (menu, shortcut, Dock, automation and Quick Look helpers)` | marked |
| [ModalityIcon.swift](Sources/DICOMStudio/Components/ModalityIcon.swift) | ST | C2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — the codes offered are DICOMCore Modality.allCases: 79 == the PS3.3 2026a C.7.3.1.1.1 Defined Terms (0 wrong, 0 missing) and 18 retired terms recognised on parse; the "79" quoted here equals that count; icons are presentation` | marked |
| [ModalityPicker.swift](Sources/DICOMStudio/Components/ModalityPicker.swift) | ST | C2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — offers DICOMCore Modality.groupedByCategory: 79 current codes == the PS3.3 2026a C.7.3.1.1.1 Defined Terms (0 wrong, 0 missing); retired and private codes stay selectable when already bound` | marked |
| [PresentationStateHelpers.swift](Sources/DICOMStudio/Components/PresentationStateHelpers.swift) | ST | — | to verify | — | ⏳ |
| [ShutterHelpers.swift](Sources/DICOMStudio/Components/ShutterHelpers.swift) | ST | — | to verify | — | ⏳ |
| [ThumbnailHelpers.swift](Sources/DICOMStudio/Components/ThumbnailHelpers.swift) | ST | B2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — supportedPhotometricInterpretations is built from DICOMCore PhotometricInterpretation == the 11 PS3.3 2026a C.7.6.3.1.2 Defined Terms less the three retired in PS3.3-2001 (was 7: YBR_PARTIAL_420, YBR_ICT, YBR_RCT, XYB missing — D10); default window presets are not standard data` | fixed (D10) |
| [WindowLevelPresets.swift](Sources/DICOMStudio/Components/WindowLevelPresets.swift) | ST | — | to verify | — | ⏳ |
| [AnnotationModel.swift](Sources/DICOMStudio/Models/AnnotationModel.swift) | ST | — | to verify | — | ⏳ |
| [CodecInspectorModel.swift](Sources/DICOMStudio/Models/CodecInspectorModel.swift) | ST | C1 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (inspector state; transferSyntaxDescription is filled by CodecInspectorViewModel with the Table A-1 name)` | marked |
| [J2KTestBenchModels.swift](Sources/DICOMStudio/Models/J2KTestBenchModels.swift) | ST | C2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — J2KBenchSyntax.all is built from DICOMCore TransferSyntax.selectableEncodings, so its names are SelectableEncoding.displayName (PS3.6 2026a Table A-1 names); the 5 default UIDs of J2KTestPlan are A-1 rows and their comment names text-diffed against A-1 (5 match after .110 "JPEG XL Lossless Only" → "JPEG XL Lossless"); isLossless defaults to the registry's answer; the rest is bench plumbing` | fixed |
| [PresentationStateModel.swift](Sources/DICOMStudio/Models/PresentationStateModel.swift) | ST | — | to verify | — | ⏳ |
| [ProgressiveDecodeModel.swift](Sources/DICOMStudio/Models/ProgressiveDecodeModel.swift) | ST | C2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — carries no transcribed DICOM-standard data — isJ2KTransferSyntax is the 7 PS3.6 2026a Table A-1 JPEG 2000 / HTJ2K rows (.90 .91 .92 .93 .201 .202 .203) resolved through DICOMCore TransferSyntax.isJPEG2000; resolution levels are codec, not DICOM, concepts` | marked |
| [ShutterModel.swift](Sources/DICOMStudio/Models/ShutterModel.swift) | ST | — | to verify | — | ⏳ |
| [ViewerAnnotationText.swift](Sources/DICOMStudio/Models/ViewerAnnotationText.swift) | ST | B2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — orientation letters: direction cosines read in the PS3.3 2026a C.7.6.2.1.1 patient coordinate system (+x L, +y P, +z head) and lettered with the Patient Orientation abbreviations of C.7.6.1.1.1 (A/P, L/R, H/F — S/I corrected); compressionLine's 5 "Uncompressed" UIDs are the PS3.6 2026a Table A-1 "… VR … Endian" rows (Encapsulated Uncompressed .1.98 added, PS3.5 A.4.11); the 11 tags read are Table 6-1 rows` | fixed |
| [ViewerContentKind.swift](Sources/DICOMStudio/Models/ViewerContentKind.swift) | ST | B2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — the 5 `…Prefix` constants are PS3.6 2026a Table A-1 OID arcs under 1.2.840.10008.5.1.4.1.1 (88. SR, 104. Encapsulated, 11. Presentation State, 9.100. Waveform Presentation State, 9. Waveform), each ending in "." and used with hasPrefix — 64 member SOP Classes fit their kind, 0 wrong; the two exact UIDs (.88.59 Key Object Selection Document Storage, .66 Raw Data Storage) match A-1; the open arcs "…1.1.9"/"…1.1.11" also matched Content Assessment Results / Microscopy Bulk Simple Annotations / Standalone Curve / VOI LUT and were closed` | fixed |
| [ViewerNonImageContent.swift](Sources/DICOMStudio/Models/ViewerNonImageContent.swift) | ST | C2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — the 7 (group,element) rows of generalRows carry PS3.6 2026a Table 6-1 names (Modality, Protocol Name, Series Description, Content Date, Study Date, Series Number, Instance Number): 7 match; EncapsulatedDocumentType names and the content switch are plumbing` | marked |
| [VolumeVisualizationModel.swift](Sources/DICOMStudio/Models/VolumeVisualizationModel.swift) | ST | C1 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (3D visualisation state: plane, interpolation, projection, preset and shading enums with app-private raw values); the PS3.3 C.7.6.2 and C.18.9 citations name the right 2026a clauses; InterpolationQuality.bicubic and ObliquePlaneConfiguration are stored settings only — no resampling kernel or oblique extraction exists in DICOMStudio` | marked (open: bicubic/oblique state-only) |
| [CharLSCLICodec.swift](Sources/DICOMStudio/Services/CharLSCLICodec.swift) | ST | C2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — the throwaway wrapper file sets the PS3.3 C.7.6.3 Image Pixel attributes from the PixelDataDescriptor and encapsulates one fragment with an empty Basic Offset Table (PS3.5 2026a A.4) under JPEG-LS Lossless (A-1 .4.80); no standard data of its own` | marked |
| [FrameRenderer.swift](Sources/DICOMStudio/Services/FrameRenderer.swift) | ST | — | to verify | — | ⏳ |
| [FrameSourceCache.swift](Sources/DICOMStudio/Services/FrameSourceCache.swift) | ST | — | to verify | — | ⏳ |
| [ImageDecodingService.swift](Sources/DICOMStudio/Services/ImageDecodingService.swift) | ST | — | to verify | — | ⏳ |
| [ImageRenderingService.swift](Sources/DICOMStudio/Services/ImageRenderingService.swift) | ST | — | to verify | — | ⏳ |
| [J2KTestBenchService.swift](Sources/DICOMStudio/Services/J2KTestBenchService.swift) | ST | C1 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — carries no transcribed DICOM-standard data — encodes/decodes through DICOMKit codecs by UID, PSNR dynamic range uses Bits Stored (PS3.3 C.7.6.3.1.1) as 2^bitsStored − 1; names come from J2KBenchSyntax` | marked |
| [PresentationStateService.swift](Sources/DICOMStudio/Services/PresentationStateService.swift) | ST | — | to verify | — | ⏳ |
| [StudyPresentationStateAdoption.swift](Sources/DICOMStudio/Services/StudyPresentationStateAdoption.swift) | ST | — | to verify | — | ⏳ |
| [CodecInspectorViewModel.swift](Sources/DICOMStudio/ViewModels/CodecInspectorViewModel.swift) | ST | B2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — transferSyntaxDescription is DICOMCore TransferSyntax.displayName (the PS3.6 2026a Table A-1 name); it was `description`, which spelled the VR/byte-order encoding for every compressed syntax` | fixed |
| [DICOMVolumeViewerViewModel.swift](Sources/DICOMStudio/ViewModels/DICOMVolumeViewerViewModel.swift) | ST | — | to verify | — | ⏳ |
| [ImageViewerViewModel+PatientOverlay.swift](Sources/DICOMStudio/ViewModels/ImageViewerViewModel+PatientOverlay.swift) | ST | — | to verify | — | ⏳ |
| [ImageViewerViewModel+PresentationStates.swift](Sources/DICOMStudio/ViewModels/ImageViewerViewModel+PresentationStates.swift) | ST | — | to verify | — | ⏳ |
| [ImageViewerViewModel.swift](Sources/DICOMStudio/ViewModels/ImageViewerViewModel.swift) | ST | — | to verify | — | ⏳ |
| [J2KTestBenchViewModel.swift](Sources/DICOMStudio/ViewModels/J2KTestBenchViewModel.swift) | ST | C1 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (bench orchestration, persistence and standings); fixtures record Photometric Interpretation as DICOMCore's rawValue and syntax names as J2KBenchSyntax.shortName (A-1 names)` | marked |
| [J2KTestingViewModel.swift](Sources/DICOMStudio/ViewModels/J2KTestingViewModel.swift) | ST | C2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — the support matrix is DICOMCore TransferSyntax.selectableEncodings filtered by isJPEG2000, named by SelectableEncoding.displayName (PS3.6 2026a Table A-1 names); the one UID literal (.4.90 default) is an A-1 row; no other standard data` | marked |
| [JP3DComparisonViewModel.swift](Sources/DICOMStudio/ViewModels/JP3DComparisonViewModel.swift) | ST | C1 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (JP3D bench state); PSNR uses 2^bitsAllocated − 1 as the peak, window defaults are UI values` | marked |
| [JP3DVolumeComparisonViewModel.swift](Sources/DICOMStudio/ViewModels/JP3DVolumeComparisonViewModel.swift) | ST | C2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — codecOptions are DICOMCore TransferSyntax.selectableEncodings filtered by isJPEG2000 and named by SelectableEncoding.displayName (PS3.6 2026a Table A-1 names); the .4.90 default is an A-1 row; no other standard data` | marked |
| [PresentationStateViewModel.swift](Sources/DICOMStudio/ViewModels/PresentationStateViewModel.swift) | ST | — | to verify | — | ⏳ |
| [AnnotationOverlayView.swift](Sources/DICOMStudio/Views/AnnotationOverlayView.swift) | ST | — | to verify | — | ⏳ |
| [CodecInspectorView.swift](Sources/DICOMStudio/Views/CodecInspectorView.swift) | ST | C1 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — UI layout only; the #Preview's .4.90 literal and its name "JPEG 2000 Image Compression (Lossless Only)" match PS3.6 2026a Table A-1` | marked |
| [MainView.swift](Sources/DICOMStudio/Views/MainView.swift) | ST | — | to verify | — | ⏳ |
| [SavedViewPickerView.swift](Sources/DICOMStudio/Views/SavedViewPickerView.swift) | ST | — | to verify | — | ⏳ |
| [ShutterOverlayView.swift](Sources/DICOMStudio/Views/ShutterOverlayView.swift) | ST | — | to verify | — | ⏳ |
| [ViewerNonImageContentView.swift](Sources/DICOMStudio/Views/ViewerNonImageContentView.swift) | ST | B2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — StructuredReportNarrativeView.value(of:) covers the 15 non-CONTAINER Value Types of PS3.3 2026a Table C.17.3-7 (TABLE was missing, D237 sibling); the video container name is DICOMKit's containerDisplayName (no exhaustive switch over VideoContainer here, D237); PS3.5 2026a 8.2.7 cited for the MPEG-4 AVC/H.264 container rule` | fixed (D237, TABLE) |
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
| [JP3DMPRViewModel.swift](Sources/DICOMStudio/ViewModels/JP3DMPRViewModel.swift) | CR→ST | C2 | see marker | `NEMA-verified: 2026a, checked 2026-10-05 — MONOCHROME1 is inverted after windowing, as PS3.3 2026a C.7.6.3.1.2 requires ("displayed as white after any VOI gray scale transformations"; quote text-checked); the rest is MPR view state` | promoted from CR, marked |
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
| [NetworkingHelpers.swift](Sources/DICOMStudio/Components/NetworkingHelpers.swift) | ST | B2 | AE rule (behaviour fixed), 3 ports, FilmLayout helpers restate the model | `NEMA-verified: 2026a, checked 2026-10-05 — AE Title rule compared with PS3.5 2026a Table 6.2-1 (AE: 16 bytes maximum, Default Character Repertoire without backslash and control characters, leading/trailing spaces non-significant, not solely spaces) and PS3.8 Table 9-11: the former uppercase-letters/digits/space/underscore rule rejected valid titles such as ANY-SCP and lowercase names and was replaced by DICOMNetwork's AETitle; normalize() no longer upper-cases (the standard does not fold case). Ports compared with PS3.8 2026a 9.1.1 (104 well-known, 11112 registered) and PS3.15 2026a B.12 ("2762 dicom-tls"); 4242 is Orthanc's, not DICOM's. The Film Layout helpers restate FilmLayout (Table C.13-3 STANDARD\C,R) and carry no terms of their own.` | ✅ `956bee08` |
| [PerformanceToolsHelpers.swift](Sources/DICOMStudio/Components/PerformanceToolsHelpers.swift) | ST | B2 | 34 VR names (6 fixed), 15 tag rows 15/15, 41 UID rows (4 UIDs / 7 names fixed), 4 clause citations | `NEMA-verified: 2026a, checked 2026-10-05 — the 15 sample tag rows text-diffed against PS3.6 2026a Table 6-1 (name, keyword, VR, VM, retired: 15 of 15 match); the 34 VR names against PS3.5 2026a Table 6.2-1 (OB/OD/OF/OW corrected from "Other … String" to "Other Byte/Double/Float/Word", UI and UR now carry the full "VR Name" cell including its abbreviation); every UID literal and the name beside it against PS3.6 Table A-1 (the three Query/Retrieve rows paired Study Root names with the Patient Root UIDs 1.2.840.10008.5.1.4.1.2.1.x — the Study Root UIDs .2.2.x are what the Workshop's study/series/image-level C-FIND uses and are now written, and the Patient Root rows it uses at PATIENT level are listed beside them; 1.2.840.10008.5.1.4.34.6.4 is named Unified Procedure Step - Event; PET/US/SC and the two JPEG abbreviations spelled as in A-1); "Retired in DICOM 2014" for Explicit VR Big Endian is not datable from the 2026a text or the 2014a–2016a release notes and now reads "Retired (PS3.6 Table A-1)". The conformance notes' clause citations checked against the 2026a section titles (C-MOVE C.4.2, C-GET C.4.3, C-ECHO PS3.7 9.1.5, WADO-RS PS3.18 10.4).` | ✅ `5e557fc5`, marker count corrected to 34 in `fa11dbd0` |
| [PolishReleaseHelpers.swift](Sources/DICOMStudio/Components/PolishReleaseHelpers.swift) | ST | C1 | none | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (sample localization entries, WCAG checklist, coverage and benchmark targets); the VoiceOver label takes the modality string it is given.` | ✅ `f5b9746f` |
| [CloudIntegrationModel.swift](Sources/DICOMStudio/Models/CloudIntegrationModel.swift) | ST | C1 | none | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (cloud providers, bucket paths, transfer jobs). The PS3.18 line above is a pointer to the transport the files travel over, not a claim that any PS3.18 resource, media type or parameter is implemented here.` | ✅ `f5b9746f` |
| [DICOMwebModel.swift](Sources/DICOMStudio/Models/DICOMwebModel.swift) | ST | — | to verify | — | ⏳ |
| [NetworkingModel.swift](Sources/DICOMStudio/Models/NetworkingModel.swift) | ST | B2 | Print Priority 3/3; Medium Type 3 offered, 1 wrong (BLU-RAY) fixed, 2 MAMMO not offered; Film Size ID 12/12; FilmLayout 8/8; PrintJobStatus 4 (2 fixed); MPPSStatus 3 (1 fixed); NetworkQueryLevel 4/4; port 11112 | `NEMA-verified: 2026a, checked 2026-10-05 — the Studio print enums text-diffed against PS3.3 2026a Table C.13-1 (Print Priority HIGH/MED/LOW: 3 match; Medium Type: PAPER and CLEAR FILM match, BLU-RAY corrected to BLUE FILM, the two MAMMO terms are not offered), Table C.13-3 (Film Size ID: 12 of 12 match; Image Display Format STANDARD\C,R: the 8 FilmLayout values match, columns first) and Table C.13-8 (PrintJobStatus is the app's job state, re-spelled with the Execution Status terms PENDING/PRINTING/DONE/FAILURE); MPPSStatus against PS3.3 C.4.14 (IN PROGRESS/COMPLETED/DISCONTINUED: IN_PROGRESS corrected); NetworkQueryLevel against PS3.4 Table C.6.1-1 (4 of 4); default port 11112 is the PS3.8 9.1.1 registered port. TLSMode names TLS versions, not the PS3.15 Annex B profiles — B.9–B.11 are retired in 2026a, B.12/B.13 are the live BCP 195 profiles (P-STUDIO-TLS-PROFILES); TransferPriority orders the app's queue and is not the DIMSE Priority (0000,0700). The four print enums duplicate DICOMNetwork's (D22, P-STUDIO-PRINT-ENUMS).` | ✅ `6ab02140` |
| [PerformanceToolsModel.swift](Sources/DICOMStudio/Models/PerformanceToolsModel.swift) | ST | C1 | none (record types) | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data: record types (DICOMTagEntry, UIDEntry, TransferSyntaxInfoEntry, SOPClassEntry) whose values live in PerformanceToolsHelpers.swift, and UI enums. TagGroupFilter's group prefixes (0010 patient, 0020 study, 0008/0018 series and equipment, 0028 image) are a browsing heuristic, not a PS3.6 classification; PS3.6 Table 6-1 does not group tags by entity.` | ✅ `5e557fc5` |
| [PolishReleaseModel.swift](Sources/DICOMStudio/Models/PolishReleaseModel.swift) | ST | C1 | none | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (localization, accessibility, testing, profiling, documentation and release-checklist records; the word DICOM appears only in display text).` | ✅ `f5b9746f` |
| [DICOMwebClientFactory.swift](Sources/DICOMStudio/Services/DICOMwebClientFactory.swift) | ST | — | to verify | — | ⏳ |
| [DICOMwebService.swift](Sources/DICOMStudio/Services/DICOMwebService.swift) | ST | — | to verify | — | ⏳ |
| [NetworkingService.swift](Sources/DICOMStudio/Services/NetworkingService.swift) | ST | C1 | 1 literal (DICOMSTUDIO) | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (locked display state: profiles, queues, MPPS and print job records, audit entries); the only literal is the fallback AE title DICOMSTUDIO, a valid PS3.5 Table 6.2-1 AE value (11 characters). Status values are the enums of NetworkingModel.swift.` | ✅ `6ab02140` |
| [PerformanceToolsService.swift](Sources/DICOMStudio/Services/PerformanceToolsService.swift) | ST | C2 | 2 TS UIDs in A-1 | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data of its own; the two Transfer Syntax UID defaults (1.2.840.10008.1.2.1 Explicit VR Little Endian, 1.2.840.10008.1.2.4.70 JPEG Lossless SV1) are registered in PS3.6 2026a Table A-1 (checked by Scripts/diff_studio.py). The tables it holds are built by PerformanceToolsHelpers.swift, verified there.` | ✅ `5e557fc5` |
| [DICOMwebViewModel.swift](Sources/DICOMStudio/ViewModels/DICOMwebViewModel.swift) | ST | — | to verify | — | ⏳ |
| [NetworkingViewModel.swift](Sources/DICOMStudio/ViewModels/NetworkingViewModel.swift) | ST | B2 | enum mapping 3+3+12 cases onto DICOMNetwork; layout now passed; C-ECHO via DICOMVerificationService; no DIMSE status worded (C-FIND/MOVE/GET/STORE/MWL/MPPS are display state) | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data of its own: the print job's Priority, Medium Type and Film Size are mapped case by case onto DICOMNetwork's enums (whose raw values are the PS3.3 2026a Table C.13-1 / C.13-3 terms) and the Film Layout is handed to DICOMPrintService as a PrintLayout (Image Display Format STANDARD\C,R, Table C.13-3), which this panel used to drop; C-ECHO goes through DICOMVerificationService. C-FIND, C-MOVE/C-GET, C-STORE, MWL and MPPS here are display state loaded by the caller — no DIMSE status is produced or worded in this file.` | ✅ `6ab02140` |
| [PerformanceToolsViewModel.swift](Sources/DICOMStudio/ViewModels/PerformanceToolsViewModel.swift) | ST | C1 | 2 TS UIDs | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data of its own: UI state over PerformanceToolsService; the two Transfer Syntax UID defaults are registered in PS3.6 2026a Table A-1 and the benchmark figures are simulated, not standard values.` | ✅ `5e557fc5` |
| [DICOMwebView.swift](Sources/DICOMStudio/Views/DICOMwebView.swift) | ST | — | to verify | — | ⏳ |
| [NetworkingView.swift](Sources/DICOMStudio/Views/NetworkingView.swift) | ST | C1 | defaults 11112, DICOMSTUDIO (11 bytes) | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data of its own: the pickers enumerate NetworkingModel's enums (Table C.13-1 / C.13-3 terms, verified there) and the MPPS and print rows show those enums' raw values; the form's defaults are port 11112 (PS3.8 2026a 9.1.1 registered port) and the AE title DICOMSTUDIO (PS3.5 Table 6.2-1: 11 of 16 bytes). No DIMSE status is worded here.` | ✅ `6ab02140` |
| [PerformanceToolsView.swift](Sources/DICOMStudio/Views/PerformanceToolsView.swift) | ST | C1 | none | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (SwiftUI layout over the view model; every tag, UID, VR and SOP Class value it shows comes from PerformanceToolsHelpers.swift, verified there).` | ✅ `5e557fc5` |
| [GatewayModel.swift](Sources/DICOMStudio/Models/GatewayModel.swift) | CR | — | one constant: default `targetPort` 104 = PS3.8 2026a 9.1.1 well-known DICOM port (checked by diff_studio_g3_dimse "ports"); HL7/FHIR enums are not DICOM data | — (no marker) | confirmed NST; promote only if a single default-port constant counts |
| [CloudIntegrationViewModel.swift](Sources/DICOMStudio/ViewModels/CloudIntegrationViewModel.swift) | CR | — | confirm-read pending | — | ⏳ |
| [GatewayViewModel.swift](Sources/DICOMStudio/ViewModels/GatewayViewModel.swift) | CR | — | confirm-read pending | — | ⏳ |
| [CloudIntegrationView.swift](Sources/DICOMStudio/Views/CloudIntegrationView.swift) | CR | — | provider / bucket UI; the word DICOM in display text only | — | confirmed NST |
| [GatewayView.swift](Sources/DICOMStudio/Views/GatewayView.swift) | CR | — | HL7 ↔ DICOM / FHIR direction labels only; no tag, UID, term or clause | — | confirmed NST |
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
| [DICOMInspectorView.swift](Sources/DICOMStudio/Views/DICOMInspectorView.swift) | ST | — | to verify | — | ⏳ |
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
| [PrinterStatusPresentation.swift](Sources/DICOMStudio/Components/PrinterStatusPresentation.swift) | ST | C2 | 3 Printer Status values + unknown covered 4/4 | `NEMA-verified: 2026a, checked 2026-10-05 — the three Printer Status (2110,0010) values of PS3.3 2026a Table C.13-9 (NORMAL, WARNING, FAILURE) are DICOMNetwork's PrinterStatusSeverity cases, each given its own colour and glyph here plus unknown; Printer Status Info (2110,0020) is shown as the SCP sent it. No literal of its own.` | ✅ `77d47fd1` |
| [PrinterProfile.swift](Sources/DICOMStudio/Models/PrinterProfile.swift) | ST | C2 | port 11112, DICOMSTUDIO, colour mode → PrintColorMode | `NEMA-verified: 2026a, checked 2026-10-05 — default port 11112 is the PS3.8 2026a 9.1.1 registered DICOM port; the default AE title DICOMSTUDIO is a valid PS3.5 Table 6.2-1 AE value (11 of 16 bytes); the colour mode maps onto DICOMNetwork's PrintColorMode (Basic Grayscale / Basic Color Print Management, PS3.4 Annex H). No other standard data.` | ✅ `77d47fd1` |
| [PrintCellTextureCache.swift](Sources/DICOMStudio/Services/PrintCellTextureCache.swift) | ST | C1 | none (Polarity composed as FilmComposer) | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data; Polarity REVERSE (2020,0020, PS3.3 2026a Table C.13-5) and the rendered-inverse Presentation LUT are composed into the shader's invert flag exactly as DICOMPrintKit's FilmComposer composes them on the sheet.` | ✅ `77d47fd1` |
| [PrintService.swift](Sources/DICOMStudio/Services/PrintService.swift) | ST | C1 | none | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data: an adapter over DICOMPrintKit's PrintImagePreparer / PrintWorkflow and DICOMNetwork's DICOMVerificationService; the Film Size and orientation it pads cells against come from the request's enums, verified in DICOMNetwork.` | ✅ `77d47fd1` |
| [PrintSCPViewModel.swift](Sources/DICOMStudio/ViewModels/PrintSCPViewModel.swift) | ST | C1 | none of its own | `NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data of its own: the reported Printer Status and Status Info (PS3.3 2026a Table C.13-9 / C.13.9.1) are DICOMPrintKit's EmulatedPrinterStatus values, pushed to the handler unchanged, and every log line is worded by PrintSCPConsole.` | ✅ `77d47fd1` |
| [PrintViewModel+CellEditing.swift](Sources/DICOMStudio/ViewModels/PrintViewModel+CellEditing.swift) | ST | C2 | MONOCHROME1/2 terms (generic check 2/2), Samples per Pixel rule C.13-5 | `NEMA-verified: 2026a, checked 2026-10-05 — the colour test reads Samples per Pixel (0028,0002) first and falls back to Photometric Interpretation, treating MONOCHROME1 and MONOCHROME2 (PS3.3 2026a C.7.6.3.1.2 terms) as grey — the rule PS3.3 Table C.13-5 fixes for the Basic Color Image Box (RGB, 3 samples). Polarity REVERSE (2020,0020) and the Presentation LUT inverse compose as FilmComposer composes them; no other literal.` | ✅ `77d47fd1` |
| [PrintViewModel+PresentationStates.swift](Sources/DICOMStudio/ViewModels/PrintViewModel+PresentationStates.swift) | ST | — | to verify | — | ⏳ |
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
