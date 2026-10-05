# Changelog

All notable changes to DICOMKit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed — DICOMStudio CLI shell, parameter builder, browser navigation (2026-10-05, DICOM 2026a)
- Parameter Builder: the 12 tool forms now mirror the tools' ArgumentParser surfaces (29 of 59 rows were not options of the named tool: positional arguments spelled `--input`/`--host`/`--file-a`, `--calling-aet` for `--aet`, `--output-format` for `--format`, `--pretty-print` for `--pretty`, dicom-image given dicom-convert's `--format`/`--frame-*`, `--tls`); positional arguments are spelled `<host>`, `<file-path>` and emitted as bare values; `dicom-anon --profile` offers `ps315` (PS3.15 2026a E.1 Basic Profile, the tool's default) and the deprecated `legacy-*` lists instead of the refused `standard`/`full`; `dicom-query --level` offers the PS3.4 Query/Retrieve Level values `patient, study, series, image`; `dicom-compress --codec` / `--quality` offer the CompressionManager / CompressionConsole names; defaults follow the tools (port 11112 = PS3.8 2026a 9.1.1 registered DICOM port, `--called-aet ANY-SCP`).
- Tool registry: the 4 shipped tools dicom-j2k, dicom-jpip, dicom-printscp, dicom-video are catalogued (42, one per `Sources/dicom-*` target); dicom-tags, dicom-image and dicom-wado descriptions say what the tools do (tag editing; images → Secondary Capture; WADO-RS / QIDO-RS / STOW-RS / UPS-RS client).
- Integration testing scenarios: dicom-qido, dicom-stow, dicom-ups (dicom-wado subcommands, not tools) replaced by the 4 missing tools; counts derive from the lists.
- Browser navigation: dicom-wado header cites PS3.18 §10 (Studies Service); PS3.18 2026a has no §6.5.
- AE Title field documentation no longer claims upper case (PS3.5 2026a Table 6.2-1: 16 bytes maximum).

### Fixed — DICOMStudio DICOMweb panel (2026-10-05, DICOM 2026a)
- `DICOMwebClientFactory.buildQIDOQuery` sends Modalities in Study (0008,0061) at the study level and Modality (0008,0060) at the series/instance levels (PS3.18 Table 10.6.1-5); the Fuzzy matching toggle is sent as `fuzzymatching=true` (8.3.4.2); a Study Date with one bound is sent as the open range of PS3.4 C.2.2.2.5. `DICOMwebViewModel.runQIDOQuery` passes the level picker into the query parameters.
- `UPSState.scheduled.allowedTransitions` no longer offers CANCELED: PS3.4 Table CC.1.1-2 refuses a Change State to CANCELED from SCHEDULED (C310H); `DICOMwebViewModel.transitionUPSState` refuses a SCHEDULED target with the same message as `dicom-wado` (PS3.18 11.7.1.4, C303H) and names the Table CC.2.1-2 status of any other refused change. `UPSState.cancelled.displayName` is "Canceled" (PS3.3 C.30.1 spelling).
- `UPSEventPayloadParser` reads Procedure Step Progress and its Description inside Procedure Step Progress Information Sequence (0074,1002), Contact Display Name (0074,100C) at the top level and inside (0074,1008), and the Human Performer Code Sequence meaning of a UPS Assigned report (PS3.4 Table CC.2.4-1); the old flat keys remain as fallbacks.
- WADO-RS frames jobs that carry a frame list retrieve the Frame Pixel Data resource `/frames/{frames}` (PS3.18 Table 10.4.1.6-1) instead of the whole instance.
- DICOMweb Hub JPIP panel: the URI panel names Pixel Data Provider URL (0028,7FE0) (PS3.5 A.6) instead of "(0008,1190) RETRIEVE URL", and the header lists all four JPIP transfer syntaxes of PS3.6 Table A-1.

### Verified — DICOMStudio (2026-10-05, DICOM 2026a)
- DICOMweb panel (6 files) NEMA-verified; `Scripts/diff_studio_g3_web.py` adds 9 row-by-row checks (UPS states and transitions, QIDO keys/parameters/resources, WADO-URI parameters, event-report tags, HTTP status numbers, JPIP text, TLS mode).

### Fixed — DICOMStudio CLI Workshop file tools (2026-10-05, DICOM 2026a)
- dicom-dcmdir Workshop: `--profile` offers only PS3.11 2026a Application Profile identifiers (`DICOMDIRProfile.allStandard`; STD-GEN-DVD / STD-GEN-USB were family headings, D29), prints the CLI's deprecation note for a legacy spelling, derives the CLI's File-set ID default and refuses an invalid `--file-set-id` (PS3.10 8.1, 8.5; exit 1), offers `--copy-to`, and `validate` reports File ID / File-set ID rule violations with their PS3.10 / PS3.3 clauses (D132).
- dicom-json / dicom-xml Workshop: empty attributes are kept by default (PS3.18 F.2.5; PS3.19 Table A.1.5-2) with `--no-include-empty` to drop them; `--no-sort-keys` / `--no-keywords` are marked deprecated and print the CLIs' notes; `--filter-tag` accepts `(GGGG,EEEE)` and `GGGGEEEE` (D114).
- dicom-export Workshop: frames are selected by Frame number from 1 (`--frame-number`, `--start-frame-number`, `--end-frame-number`; PS3.3 Table 10-3), the 0-based options are deprecated with the CLI's notes and refused when mixed; `animate` defaults to the file's Recommended Display Frame Rate / Cine Rate / Frame Time (PS3.3 Table C.7-13); contact-sheet and animate render through the shared PS3.4 N.2 pipeline; bulk patient folders are keyed on Patient ID + Issuer of Patient ID; `--apply-window` is deprecated on contact-sheet / bulk; Burned In Annotation (0028,0301) YES warns (D127).
- dicom-split Workshop: `--frame-numbers` (from 1, PS3.3 C.7.6.16.1.2) added; `--frames` is the deprecated 0-based index and prints the CLI's note; both together are refused (D154).
- dicom-archive Workshop: `query --strict-modality`; `--modality` is validated by the shared ModalityOptionValidator (PS3.3 C.7.3.1.1.1) with the CLI's warning / rejection; the `--study-date` warning (PS3.4 C.2.2.2.5.1) and the CLI's query-key help texts.
- dicom-study Workshop: `organize` no longer sends `--copy` by default (the CLI moves); help names the PS3.6 keyword keys and the deprecated old keys.
- dicom-uid Workshop: lookup prints the PS3.6 Table A-1 UID Type (`UIDManager.tableA1UIDType`), the `--type` filter is the shared `UIDConsole.lookupTypeFilters`, `generate --uuid` (PS3.5 B.2), `--root` checked against PS3.5 9.1.
- dicom-validate Workshop: runs dicom-validate's own loop (DICOMValidator, ValidationReport, FileGatherer); `--iod` accepts PS3.6 Table A-1 keywords and UIDs; the `--level` help is the CLI's.
- dicom-dump / dicom-tags / dicom-diff / dicom-info Workshop: the CLI's tag grammar and refusal texts, `--list-modalities`, `TagEditor.applyCheckedChanges` (PS3.5 Table 6.2-1 limits), dicom-diff exit 2 for a missing / unreadable file, ArgumentParser usage errors as exit 64.
- Validation panel: 5 IOD suggestions corrected to the PS3.6 2026a Table A-1 keywords (`UltrasoundMultiFrameImageStorage`, `MultiFrame…SecondaryCaptureImageStorage`); level descriptions carry dicom-validate's `--level` help.

### Fixed — DICOMStudio (2026-10-05, DICOM 2026a)
- SR builder: coded concepts corrected to PS3.16 2026a — Finding Site is (363698007, SCT) (was the SRT id G-C0E3), (121200, DCM) is "Illustration of ROI", (113000, DCM) is "Of Interest", UCUM meanings "square millimeter" / "Hounsfield unit" / "no units"; document titles come from CID 7000 / 7021 / 7010 and TID 4000 / 4100 (the retired heading code 121070 is no longer used as a title), section headings from CID 7001, Key Object Selection documents follow TID 2010, Measurement Reports nest their groups under (126010, DCM, "Imaging Measurements") (TID 1500 row 6).
- Terminology browser: three SNOMED CT ids corrected (Liver 10200004 — 816092008 is "Pelvis"; Chest 816094009; Nodule 27925004), nine LOINC meanings aligned with CID 7000 / 7001, coding scheme names per PS3.16 Table 8-1 ("DICOM Controlled Terminology", SRT → "SNOMED CT").
- ROI statistics show the area with its UCUM code as dicom-measure does ("250.0 mm2 (mm²)", PS3.16 CID 7461).
- Waveform display names cover all 16 PS3.6 2026a Table A-1 Waveform Storage SOP Classes (e.g. "12-lead ECG", "Cardiac Electrophysiology", "Basic Voice Audio"; the 32-bit ECG, multi-channel respiratory, EEG / EMG / EOG and body-position classes were unnamed).
- Encapsulated CDA MIME type is "text/XML" (PS3.3 2026a A.45.2.4 Enumerated Value).
- Security Center: the anonymization preview and default rules list exactly the attributes the shared DICOMKit engine removes (Basic / HIPAA Safe Harbor 14, Clinical Trial 22; the former "18 HIPAA direct identifiers" list shared only 7 tags with what ran), profile descriptions say so, and the Development TLS mode no longer advertises TLS 1.0 (PS3.15 2026a B.12 / RFC 8996 prohibit it; minimum TLS 1.2).
- Citations corrected to 2026a: Parametric Map modules are C.8.32 (C.8.23 is Surface Segmentation), C.8.8.5 is the Structure Set Module, the STL / OBJ / MTL IODs are A.85.1-A.85.3, calibration references 10.7.1.1 / 10.7.1.3, PS3.15 B.9 / B.10 (retired) no longer cited.

### Fixed — DICOMStudio viewer (2026-10-05, DICOM 2026a)
- The viewer, its tiles, film cells, `ImageRenderingService` and the progressive decoder render through the PS3.4 N.2 chain — the image's Modality LUT (or the applied presentation state's), then the window in modality units or the VOI LUT Sequence, then the Presentation LUT — and pass the image's ICC Profile; a stored-unit window is no longer handed to the renderer, so rescale slopes other than 1 (PET, NM) and negative slopes show the standard's picture (PS3.3 C.11.2.1.2.1, C.11.15.1.1; D65, D68).
- Saved views carry the image's Photometric Interpretation and Rescale Type: a MONOCHROME1 image saves and restores with the right Presentation LUT, a colour image is saved as a Color Softcopy Presentation State, and the state's Modality LUT names its units (PS3.4 N.2; PS3.3 A.33.1.1, Table A.33.2-1; D42).
- A presentation state without a Modality LUT is the identity while it is shown — the image's rescale is no longer substituted — except for this app's own objects written before 2026-09-29, which are read with the image's rescale they were written in (PS3.4 N.2.1.1; D28).
- The tag inspector shows OV as bytes, with the other "Other …" VRs and UN (PS3.5 Table 6.2-1; D28).
- `PresentationStateHelpers.applyLinearVOI` uses the C.11.2.1.2.1 thresholds (the upper one was a unit too high, so the top of the ramp exceeded 1 and a width of 1 divided by zero); `transformPoint` rotates before it flips, as Table C.10-6 orders it.
- `ModalityLUTTransform.rescaleType` defaults to `US` (Unspecified) instead of `HU` (PS3.3 C.11.1.1.2).
- A display shutter with several shapes shows their intersection, not their union (PS3.3 C.7.6.11); a bitmap shutter accepts only the even overlay groups 6000–601E (PS3.5 7.6).
- Waveform Presentation State objects (1.2.840.10008.5.1.4.1.1.9.100.*) are no longer classified as waveform files (PS3.6 Table A-1).

### Fixed — DICOMStudio codecs, transfer-syntax names and labels (2026-10-05, DICOM 2026a)
- Transfer-syntax names shown in DICOM Studio are the PS3.6 2026a Table A-1 names (D9): ImportValidation, FileOperationsHelpers and the J2K Test Bench spell them out (".4.110 JPEG XL Lossless Only" → "JPEG XL Lossless"); the overlay's short label comes from DICOMCore `TransferSyntax.shortName` with the Table A-1 name as tooltip (`ImageMetadataHelpers.transferSyntaxStandardName`); the Data Exchange compression picker labels every row with the UID its `dicom-compress` token really produces (`jpeg-lossless` is .4.57, not .4.70; `j2k-lossless` / `htj2k-lossless` are reversible .4.91 / .4.203); the codec inspector names the Table A-1 syntax instead of "Explicit VR Little Endian (…)" and recognises JPEG XL, video, Deflated Image Frame Compression and Encapsulated Uncompressed.
- Thumbnails render every PS3.3 2026a C.7.6.3.1.2 photometric interpretation DICOMCore decodes (YBR_PARTIAL_420, YBR_ICT, YBR_RCT, XYB were missing — D10); the pixel-metadata overlay labels XYB (D11).
- Viewer content classification uses closed PS3.6 OID arcs: "…5.1.4.1.1.9" no longer claims Content Assessment Results or Microscopy Bulk Simple Annotations as waveforms, Waveform Presentation States are presentation states; the SR narrative renders TABLE content items (PS3.3 Table C.17.3-7); the video player names the container through DICOMKit (D237, Studio half).
- Viewport orientation letters use the PS3.3 C.7.6.1.1.1 Patient Orientation abbreviations H/F instead of S/I; Encapsulated Uncompressed (PS3.5 A.4.11) is annotated "Uncompressed".
- JP3D MPR window/level is the PS3.3 C.11.2.1.2.1 default LINEAR function (thresholds c − 0.5 ∓ (w−1)/2); BlendingHelpers cites C.11.14 (Presentation State Blending Module), not C.11.11.
- J2K Test Bench rows built without an explicit lossless flag ask the transfer-syntax registry, so JPEG Baseline and JPEG-LS Near-Lossless score by PSNR rather than demanding a bit-exact round trip.

- **D22 — Networking Hub print enums (PS3.3 2026a C.13.1 / C.13.3 / C.13.8, C.4.14).** `PrintMediumType.bluFilm` now carries the Medium Type term `BLUE FILM` (was `BLU-RAY`, not a term); `PrintJobStatus.completed` / `.failed` carry the Execution Status terms `DONE` / `FAILURE` (were `COMPLETED` / `FAILED`); `MPPSStatus.inProgress` is `IN PROGRESS` (was `IN_PROGRESS`). The Networking print job now sends its chosen Film Layout as the film box's Image Display Format (`STANDARD\C,R`); it used to be dropped and the SCU chose its own grid. The four print enums still duplicate DICOMNetwork's — P-STUDIO-PRINT-ENUMS.
- **AE Title validation (PS3.5 2026a Table 6.2-1, PS3.8 Table 9-11).** `AETitleHelpers` and `ServerValidationHelpers` validate through `DICOMNetwork.AETitle`: 16 bytes after trimming the non-significant spaces, printable ASCII 20H–7EH without backslash, not solely spaces. Lowercase and hyphenated titles (`orthanc`, `ANY-SCP`) are accepted; non-ASCII letters are refused; `AETitleHelpers.normalize` no longer upper-cases. `PortHelpers.wellKnownDICOMPort` (104) added; `displayName` labels 104 "well-known" and 11112 "registered" (PS3.8 9.1.1).
- **Developer tools reference data (PS3.5 Table 6.2-1, PS3.6 Tables 6-1 and A-1).** VR names read as Table 6.2-1 writes them (`Other Byte`, …, `Unique Identifier (UID)`); the conformance list pairs the Study Root Query/Retrieve names with the Study Root UIDs (.2.2.x) and lists the Patient Root rows beside them; SOP Class and transfer-syntax names are the Table A-1 names; the undatable "Retired in DICOM 2014" note reads "Retired (PS3.6 Table A-1)".
- **Print sheet Film Destination (PS3.3 2026a Table C.13-1).** The destination picker offers Magazine, Processor and any sorter bin `BIN_i` (i ≥ 1) with a bin-number field, instead of BIN_1 / BIN_2 only. The Bits Stored 8/12 help cites Table C.13-5 (was C.13-3). The Print SCP attribute panel labels (2010,0050) "Film Size ID" and (2010,0060) "Magnification Type" (PS3.6 Table 6-1 names).

### Fixed — DICOMStudio (2026-10-05, DICOM 2026a)
- `DICOMDIRParser.knownRecordTypes` now lists all 35 Directory Record Types of PS3.3 2026a Table F.4-1: RT TREAT RECORD, WAVEFORM, PLAN, ANNOTATION, INVENTORY and WF PRESENTATION were missing; HL7 STRUC DOC is kept and documented as retired (F.5.33, PS3.3-2018b).
- `VRDescriptions.fullName` covers all 34 VRs of PS3.5 2026a Table 6.2-1 with the "VR Name" verbatim: AS, AT, OL, OV, SV, UV and UR were missing; UI is "Unique Identifier (UID)" and SQ "Sequence of Items". `category` groups the seven added VRs.
- `DICOMValueParser.formatPersonName` formats the up-to-three "="-separated PN component groups separately (PS3.5 6.2.1.2) instead of running the ideographic/phonetic groups into the alphabetic name; `characterSetDescription` names all 32 Specific Character Set Defined Terms of PS3.3 2026a Tables C.12-2…C.12-5 (13 added, e.g. ISO_IR 203, GBK, ISO 2022 IR 58).
- `PrivateTagIdentifier.isPrivateGroup` no longer reports groups 0001, 0003, 0005, 0007 and FFFF as private; PS3.5 2026a 7.8.1 excludes them from private use.
- `TransferSyntaxDescriptions.describe` (metadata viewer) and `TransferSyntaxHelpers.wellKnownSyntaxes.displayName` (Data Exchange) return the PS3.6 2026a Table A-1 "UID Name" from DICOMCore `TransferSyntax.displayName` instead of their own abbreviated tables (5 of 13 and 6 of 8 names differed from A-1); `shortName` keeps the abbreviations.
- Data Exchange Secondary Capture: the modality default was "SC", which is not a PS3.3 2026a C.7.3.1.1.1 Modality Defined Term; it is now "OT", dicom-image's own default.

### Fixed — DICOMStudio anonymization profile flags name the CLI's legacy lists (2026-10-05, DICOM 2026a)

- **DICOMStudio** `AnonymizationProfile.cliFlag`: `basic`, `hipaaeSafeHarbor` and `custom` sent `--profile basic`, which since
  2026-10-01 (P-ANON-PROFILE) runs dicom-anon's PS3.15 Basic Application Level Confidentiality Profile (Table E.1-1, UIDs
  replaced), not the fixed "remove direct identifiers" list the app's label describes and its in-app engine runs. The five
  cases now map to `legacy-basic`, `legacy-clinical-trial`, `legacy-research`; `AnonHelpers.buildCommand` always names
  `--profile` (the CLI default is now `ps315`). The CLI Workshop dicom-anon form offers the three `legacy-*` values
  (default `legacy-basic`), its presets say "legacy basic attribute list", and its executor refuses `ps315` / `basic` with
  exit 1 instead of silently running the legacy list. Offering the PS3.15 profile itself needs a new `AnonymizationProfile`
  case (P-STUDIO-ANON-PS315, pending the owner). 4 tests (`SecurityModelTests`, `CLIWorkshopHelpersTests`).

### Changed — audio that breaks PS3.5 8.2.5 / 8.2.12 is rejected (2026-10-05, DICOM 2026a)

- `VideoConformanceValidator.validate(probe:transferSyntax:)` raises `.audioNotPermitted` for each known violation found by
  `validateAudio` (the 2026a per-format checks), so `convert` and `probe` exit 2 instead of writing an object whose audio
  the standard forbids. A value the container does not state is still "not checked", never a violation. The remedy
  re-encodes only the audio (`-c:v copy`). Previously these findings were warnings.

### Fixed — JPEG XL JPEG Recompression source check per PS3.5 Table 8.2.15-1 (2026-10-01)

- **DICOMKit** `ConversionDiagnostics`: a source for .4.111 must be MONOCHROME2 with 1 sample or YBR_FULL_422 / XYB / RGB with 3 samples (PS3.5 2026a Table 8.2.15-1); PALETTE COLOR and YBR_FULL sources were accepted before and are now refused with the table named. The file now carries its NEMA-verified marker (it arrived from main after the DICOMKit audit).

### Fixed — deferred rows, batch r3 (2026-10-01, DICOM 2026a)

- **MPEG2 frame rates** (D238; PS3.5 2026a 8.2.5 Table 8-1, 8.2.6 Table 8-2, Note 4, Table 8-3):
  `VideoConformanceValidator.validate` refuses an MPEG2 Main Profile / Main Level stream whose frame rate is not
  30 (29.97, 525-line NTSC, at most 480 x 720) or 25 (625-line PAL, at most 576 x 720)
  (`mpeg2FrameRateNotPermitted`, `mpeg2MainLevelGeometryExceedsMaximum`), and a Main Profile / High Level stream
  whose frame rate is not 25, 30 (29.97), 50 or 60 (59.94), or that is 1080 rows at 50 / 60.
  `selectTransferSyntax` no longer offers .100 / .101 to such a stream. The tables are public
  (`mpeg2MainLevelFormats`, `mpeg2HighLevelFrameRates`, `mpeg2HighLevel1080FrameRates`) and diffed against the
  2026a DocBook by `Scripts/diff_kit.py` (check `mpeg2-frame-rates`). A stream with no frame rate is not refused.
- **DICOMDIR read by its offsets** (D240; PS3.3 2026a F.3.2.2, Table F.3-3, Table F.4-1, F.6.1):
  `DICOMDIRReader.read(from:)` builds the record tree from Offset of the First Directory Record of the Root
  Directory Entity (0004,1200), Offset of the Next Directory Record (0004,1400) and Offset of Referenced
  Lower-Level Directory Entity (0004,1420), counted from the first byte of the File Meta Information (Explicit or
  Implicit VR Little Endian, defined or undefined lengths), so a DICOMDIR whose records are not in depth-first
  order is read correctly; the sequence order is used only when the offsets cannot be followed. PRIVATE records are
  kept where the offsets place them (were dropped). A Record In-use Flag other than 0000H is read as FFFFH, as
  Table F.3-3 requires (was inactive).
- **DICOMDIR profile keys and icons** (D239; PS3.11 2026a Tables A.3-2, B.3-2, D.3-2, E.3-2, H.3-2, I.3-2,
  A.3.3.2, B.3.3.2, E.3.3.3; PS3.3 2026a F.7): `DICOMDirectory.Builder` adds the profile's "Additional DICOMDIR
  Keys" to the PATIENT, SERIES and instance records (Annexes J, M and N apply H.3-2): Type 1 copied, Type 2 copied
  or zero length, Type 1C when the Notes condition holds (present in the object; in any object of a subordinate
  record, filled in as later instances arrive; in the Shared Functional Groups Sequence; XA Image; BIPLANE A / B).
  STD-XABC-CD / STD-XA1K IMAGE records get an Icon Image Sequence of 128 x 128, 8 bits, MONOCHROME2: the instance's
  own icon when it conforms, else one made from its representative frame (Representative Frame Number, else a
  third of the way through; windowed, MONOCHROME1 inverted, colour as luminance, aspect kept). A key that cannot
  be supplied refuses the instance with the new `Refusal.missingProfileKey`. New
  `DICOMDIRProfileRules.additionalKeyTableLabel(for:)`. The tables, the Annex mapping and the icon rules are
  generated by `Scripts/generate_dicomdir_profile_rules.py` (`--check`). STD-GEN-DVD / USB / BD-* (H.3-2) and
  STD-CTMR / STD-DVD-MPEG2 IMAGE records now require Rows / Columns. `dicom-dcmdir` README updated.

### Fixed — Basic Profile D on SR Content Sequence (D236, 2026-10-01)

- **DICOMKit** `ConfidentialityEngine`: without the Clean Structured Content Option, Content Sequence (0040,A730) gets its PS3.15 2026a Table E.1-1 Basic Profile action D on the Sequence "and all of its contents" (E.1.1); C applies only under the Option. The Content Items stay (Relationship Type, Value Type, Concept Name, references), Date / Time / DateTime / Person Name keep their own Table E.1-1 rows (D, or K/C under the temporal Options) and UID its U, and the values Table E.1-1 does not list are replaced by dummies of their VR: Text Value (0040,A160), the NUM numeric values (Numeric Value 0, Floating Point Value 0, Rational Numerator 0, Rational Denominator 1, in the Item and its Measured Value Sequence) and the Selector <VR> Value of each TABLE cell (number of values kept). Previously the Basic Profile released SR free text unchanged. Coded values are kept (E.1.1 note on Code Sequences). `dicom-anon` help and README describe the Basic behaviour.

### Fixed — JPEG 2000 / HTJ2K irreversible encode at maximum quality (D234, 2026-10-01)

- **DICOMCore** `J2KSwiftCodec`: the bit-exact round-trip check now follows the planned encode. A lossy-intent encode on .91 / .203 with `--quality maximum` is planned as the irreversible 9-7 transform (PS3.5 2026a 8.2.4) and is no longer refused with "lossless round-trip validation failed"; reversible (5-3) encodes are still verified bit-exact.

### Fixed — deferred rows, batch r2 new findings (2026-10-01, DICOM 2026a)

- **`dicom-mpps` status text** (D220; PS3.7 2026a Annex C, PS3.4 2026a Table F.7.2-2): the CLI's own 22-code
  DIMSE-N name table and its dead `.storeFailed` re-wrap are removed; SCP warnings are worded by DICOMNetwork's
  `DIMSEServiceStatusText` (e.g. "Warning (0x0107): Attribute List warning", N-SET via Table F.7.2-2) and
  failures arrive already worded in `DICOMNetworkError.mppsOperationFailed`.
- **`dicom-report` WAVEFORM channels** (D225; PS3.3 2026a C.18.5.1.1): Referenced Waveform Channels print as
  (Multiplex Group, Channel) pairs, `channels (M,C) (1,0) (3,2) (3,3)` (was the channel numbers only).
- **Content Creator's Name is Type 3** (D222; PS3.3 2026a Table 10.9.3-1 via Table 10-12): comments, the GSPS
  builder marker and test messages no longer call it Type 2; behaviour unchanged (written zero length when unknown,
  which PS3.5 7.4.5 permits).
- **EXIF export** (D126; PS3.5 2026a Table 6.2-1 DA / TM): `DICOMImageExporter` converts Study Date (DA) with Study
  Time (TM) to Exif DateTimeOriginal "YYYY:MM:DD HH:MM:SS" (blank time without Study Time; a value that is not a DA
  is not written; was the raw YYYYMMDD). Patient ID, Modality and Series Description go to Exif UserComment as
  `Keyword=value` entries joined by "; " (Patient ID was read and dropped; Modality went to an Exif "Software" key).
  New `supportedEXIFFields`, `unsupportedEXIFFields(_:)`, `exifDateTime(fromDA:tm:)`; `dicom-export single` warns
  for an `--exif-fields` keyword it cannot embed. **Behaviour change**: Series Description's UserComment is now
  `SeriesDescription=<value>`.
- **MPEG2 Main Profile / High Level geometry** (D226; PS3.5 2026a 8.2.6): `VideoConformanceValidator.validate`
  refuses .101 / .107 unless Rows/Columns are 720/1280 or 1080/1920 and `aspect_ratio_information` is 0011 (16:9)
  (new violations `mpeg2HighLevelGeometryNotPermitted`, `mpeg2AspectRatioNotPermitted`;
  `VideoStreamInfo.mpeg2AspectRatioInformation`). `selectTransferSyntax` no longer offers .101 to MP@H-14 or to
  another geometry. **Behaviour change**: a 720x576 Main Level stream is no longer accepted under .101.
- **MPEG-2 Program Stream and PES input** (D227; PS3.5 2026a 8.2.5 / 8.2.6 list MPEG-PS and MPEG-PES among the
  MPEG-2 containers): new `MPEG2SystemsLayer`, `MP4ContainerParser.mpeg2SystemsLayer(_:)`,
  `mpeg2VideoElementaryStream(_:)`, `mpeg2AudioStreamIDs(_:)`; `VideoProbe` reads the video PES payloads (sequence
  header, frame count, audio stream count) and `VideoProbeResult.mpeg2SystemsLayer` / `containerDisplayName` name
  the container; the systems stream is encapsulated unchanged. A PES input was "not a recognized video container".
  `VideoContainer` keeps its cases (PS / PES report `.elementaryStream`); `ExtractedVideo` suggests `.mpg`.
- **Script templates without shell syntax** (D223; template plumbing): the runner execs each tool without a shell,
  so the workflow / pipeline / anonymize templates and the `dicom-script` README now pass a directory with
  `--recursive` instead of `*.dcm` and drop `> file` redirection. `ScriptValidator` reports globs and redirection
  as passed literally; `ScriptParser` removes the quotes of a "quoted" argument (the query template's
  `--patient-name "DOE*"` used to reach dicom-query with its quotes). New `ScriptParser.tokenize(_:)` and
  `unsupportedShellSyntax(in:)`.
- **`JP3DVolumeBridge` slice geometry** (D224; PS3.3 2026a C.7.6.2.1.1 Equation C.7.6.2.1-1, Table C.7-10,
  C.7.6.2.1.2): `makeVolume` sets the `J2KVolume` origin to the first slice's Image Position (Patient) (was 0,0,0);
  `makeDICOMSeries` places slice i at origin + i·spacing along the template's Image Orientation (Patient) normal
  (was z-only), always writes Image Orientation (Patient) with the position (1\0\0\0\1\0 when the template has
  none), and Pixel Spacing, Rows, Columns and Slice Location from the volume.
- **DICOMDIR records per SOP Class, with their keys** (D229, D230; PS3.3 2026a F.4 Table F.4-1, F.5, Tables F.5-1
  to F.5-49; PS3.11 2026a D.3.3.1): `DICOMDirectory.Builder` gives each instance the Directory Record Type PS3.3
  F.5 names for its SOP Class (SR DOCUMENT, KEY OBJECT DOC, PRESENTATION, WAVEFORM, ENCAP DOC, RT DOSE, RT PLAN,
  PLAN, RADIOTHERAPY, …; HANGING PROTOCOL, PALETTE, IMPLANT*, INVENTORY as root records) instead of IMAGE for all,
  with the Type 1 / 1C / 2 / 2C keys of that record's table: STUDY now carries Study ID and Accession Number, Type 2
  keys are written zero length when unknown. The mapping of 174 SOP Classes (PS3.4 Tables B.5-1, GG.3-1) and 145
  keys are generated into `DICOMDIRRecordKeyTables.swift` by the new `Scripts/generate_dicomdir_record_keys.py`
  (`--check`). Missing Study ID / Series Number / Instance Number get their ordinal; Study Date / Time come from
  the Series, Acquisition or Content Date / Time, else 19000101 / 000000 (`Builder.suppliesMissingStudyDateTime`,
  false refuses); any other missing Type 1 key, and the 5 SOP Classes with no record type, are refused (new
  `Refusal.missingRecordKey`, `.noDirectoryRecordType`). New public `DICOMDIRRecordKeys`,
  `DirectoryRecordType.rootLevelTypes` / `allowedChildTypes` / `isRetired`,
  `DICOMDirectory.Statistics.instanceRecordCount`; dump and create summaries add "Other instance records".
  **Behaviour change**: non-image instances are no longer indexed as IMAGE records.
- **File-set Consistency Flag** (D231; PS3.3 2026a Table F.3-3: "The Value FFFFH shall never be present"):
  `DICOMDIRWriter` always writes 0000H.
- **DICOMDIR reader keeps every record type** (D232; PS3.3 2026a Table F.4-1): all Series-level record types
  (KEY OBJECT DOC, ENCAP DOC, RT TREAT RECORD, SPECTROSCOPY, RAW DATA, REGISTRATION, …) are kept under their SERIES
  and HANGING PROTOCOL / PALETTE / IMPLANT / IMPLANT ASSY / IMPLANT GROUP / INVENTORY at the root (were dropped).
- **Per-profile image attribute values** (D233; PS3.11 2026a Tables A.3-3, B.3-3, B.3-4, C.3-2, E.3-3 to E.3-6,
  K.3-3, K.3-4, L.4-1, L.4-2): `DICOMDIRProfileRules.imageAttributeProblems(in:sopClassUID:transferSyntaxUID:profile:)`
  (tables generated by `generate_dicomdir_profile_rules.py`, Value text parsed) is applied by `addFile`
  (`Refusal.imageAttributeValues`); the "Multi-frame Composite IODs" rows (MPEG syntaxes) admit only instances with
  Number of Frames (`refusal(...isMultiFrame:)`, `allowedTransferSyntaxes(...isMultiFrame:)`).

### Fixed — deferred rows, codec batch b6a (2026-10-01, DICOM 2026a)

- **Lossy compression creates a new instance** (D184, D192; PS3.3 2026a C.7.6.1.1.5: "if the predecessor was a
  DICOM image, then the Image shall receive a new SOP Instance UID"): `dicom-compress` / `CompressionManager` and
  `dicom-convert` / `DICOMConverter` give every irreversible output a new SOP Instance UID (also written to
  (0002,0003)), next to Lossy Image Compression "01", Ratio, Method and Image Type DERIVED; the step is appended
  to Derivation Description (0008,2111) as "Lossy compression <method>, ratio N:1" (C.7.6.1.1.5.2 "should").
  **Behaviour change**: lossless output keeps the source UID; lossy output never does.
- **JPEG 2000 / HTJ2K colour labels in `CompressionManager`** (D185, D186, D-KIT-1; PS3.5 2026a 8.2.4, Table
  8.2.4-1, 8.2.14): a 3-sample encode whose COD has MCT = 1 is labelled YBR_RCT (5-3) or YBR_ICT (9-7) with
  Planar Configuration 0 (was RGB); decompressing YBR_RCT / YBR_ICT to native relabels RGB (was left YBR_*).
- **YBR_FULL → JPEG 2000 / HTJ2K** (D-CORE-3; PS3.5 2026a 8.2.4: "No other Value of Photometric Interpretation
  than YBR_RCT or YBR_ICT is permitted when SGcod Multiple component transformation type is 1"): J2KSwift always
  applies the colour transform to 3 components, so a lossy encode converts YBR_FULL to RGB first (PS3.3 C.7.6.3.1.2
  equations, new `YBRFullConversion`) and labels YBR_ICT, in `TransferSyntaxConverter` and `CompressionManager`.
  **Behaviour change**: a reversible (lossless) J2K / HTJ2K encode of YBR_FULL is refused, since the conversion
  rounds and MCT 0 cannot be written (was a codestream with MCT = 1 under YBR_FULL).
- **JPEG colour is YCbCr 4:2:2 labelled YBR_FULL_422** (D190 colour half, D-CORE-2; PS3.5 2026a Table 8.2.1-1
  allows a 3-sample JPEG Baseline stream only as YBR_FULL_422 or RGB): `JLICodec` encodes lossy colour 4:2:2 (was
  4:4:4 YCbCr under RGB) and `TransferSyntaxConverter` / `CompressionManager` label it YBR_FULL_422 with Planar
  Configuration 0 from the frame header's sampling factors (new `JPEGInterchangeFormat.frameComponents(in:)`,
  `isHorizontally422(_:)`). **Behaviour change**: JPEG Extended (.51) colour is refused (Table 8.2.1-1 has no
  3-sample .51 row), and `NativeJPEGCodec` (ImageIO, DICOMStudio's benchmark engine) refuses colour — it writes
  4:2:0 below quality 1.0 and 4:4:4 at 1.0, neither of which has a valid label.
- **Explicit VR Big Endian values are byte-swapped** (D206; PS3.5 2026a 7.3, A.3 retired): `DICOMWriter` writes
  every 2-, 4- and 8-byte binary value (US SS OW AT / UL SL FL OF OL / FD OD OV SV UV) in its own byte order when
  the element's `byteOrder` differs (new `DICOMWriter.byteSwapUnit(for:)`, `DICOMWriter.value(_:vr:from:to:)`), so
  LE → BE and BE → LE output is correct at any nesting depth; `CompressionManager` encodes a Big Endian source from
  little-endian samples. `dicom-compress decompress|batch --syntax explicit-be` is accepted again (P-COMPRESS-SYNTAX
  had refused it because of this defect).
- **`TransferSyntaxConverter` keeps defined-length sequences** (D-CORE-5, found in this batch; PS3.5 2026a 7.5.2
  "Explicit Length"): its parser kept no Items for a defined-length SQ and `DICOMWriter` re-encodes an SQ from its
  Items, so every such sequence was written empty on a `dicom-convert` transcode (all `DataSet.write` output uses
  defined lengths). Parsed elements now carry the source byte order, and an Explicit VR Big Endian source is
  encoded from little-endian samples (D206).
- **`dicom-compress` File Meta UIDs are even length** (D188; PS3.5 2026a 6.2, 7.1): (0002,0002), (0002,0003),
  (0002,0010), (0002,0012) are padded with one trailing NULL.
- **`dicom-convert --strip-private` reaches into Sequence Items** (D191; PS3.5 2026a 7.8.1): Private Data Elements
  and Private Creators inside Items are removed at any depth and counted.
- **Per-frame rescale** (D197; PS3.3 2026a C.7.6.16.2.9, Table C.7.6.16-10): new `DataSet.rescale(_:frameIndex:)`
  and `DICOMFile.rescale(_:frameIndex:)` use the frame's Pixel Value Transformation Sequence; `rescale(_:)` is
  unchanged (shared / first-frame values). dicom-measure uses the new call.
- **`dicom-compress` ratio lines** (D183; PS3.3 2026a C.7.6.1.1.5.2): "Compression ratio: 3.03:1" (input / output)
  and "Decompression ratio: 1:3.03" replace the output-as-percent-of-input figure; info prints "Samples per Pixel"
  (PS3.6 2026a (0028,0002)).

### Added — PS3.15 Clean Structured Content and Clean Recognizable Visual Features Options, batch d159-rest (2026-10-01, DICOM 2026a)

- **`ConfidentialityProfile.Options.cleanStructuredContent` (Clean Structured Content Option, 113104)** (D159;
  PS3.15 2026a E.3.4, Table E.3.4-1): Content Sequence (0040,A730), Acquisition Context Sequence (0040,0555),
  Specimen Preparation Sequence (0040,0610) and Waveform Annotation Sequence (0040,B020) are kept and cleaned
  (Table E.1-1 Clean Struct. Cont. "C"); every Content Item of Content Sequence, Acquisition Context Sequence and
  Specimen Preparation Step Content Item Sequence (0040,0612) gets the action Table E.3.4-1 gives its Concept Name
  and Value Type under the Options in force — X removes the Content Item with its children, D replaces its value
  with a dummy of the VR (UIDREF: a consistently mapped UID), K keeps its value, C cleans its text or shifts its
  date (Modified Dates) — and the text kept is cleaned of the values removed (removed Content Items included).
  The 211 rows are generated into `ConfidentialityProfileStructuredContent.swift` by
  `Scripts/generate_confidentiality_profile.py` (`--check` re-verifies it; it now also reads PS3.16), with the
  retired SRT / SNM3 / 99SDM SNOMED IDs of its 11 SCT rows from PS3.16 2026a Table O-1 (E.3.4: retired codes are
  to be recognised). 113104 is recorded only with the Option. dicom-anon `--clean-structured-content`.
- **`PixelRedactor.redactRecognizableVisualFeatures(fileData:regions:fillValue:)` (Clean Recognizable Visual
  Features Option, 113102)** (D159; PS3.15 2026a E.3.2, "may require intervention of or approval by a human
  operator"): operator-directed — the regions given are blanked on every frame, Icon Image Sequence removed,
  Recognizable Visual Features (0028,0302) set to NO and 113102 appended to (0012,0064); no region throws the new
  `PixelRedactionError.noRecognizableVisualFeatureRegions`. Burned In Annotation and 113101 are not written for
  these regions. The PS3.15 engine keeps the record and names it in (0012,0063). dicom-anon
  `--clean-recognizable-visual-features` needs one or more `--redact-region` (exit 1 citing PS3.15 E.3.2
  without); with it, `--redact-region` no longer implies `--clean-pixel-data`.
- `ConfidentialityEngine`: a cleaned (C) Sequence at the top level is reported as changed when its Items differ
  from the source, not only when text cleaning changed them.

### Added — PS3.15 Retain Safe Private and Clean Graphics Options, batch b4 (2026-10-01, DICOM 2026a)

- **`ConfidentialityProfile.Options.retainSafePrivate` (Retain Safe Private Option, 113111)** (D159; PS3.15 2026a
  E.3.10, Table E.3.10-1): Private Attributes listed in Table E.3.10-1 for their Private Creator (479 rows,
  generated into `ConfidentialityProfileSafePrivate.swift` by `Scripts/generate_confidentiality_profile.py`,
  `--check` re-verifies it), or declared SAFE / Nonidentifying (0008,0304) in Private Data Element
  Characteristics Sequence (0008,0300), are kept with the Private Creators they need; a Deidentification Action
  (0008,0307) D / Z / X / U is applied as declared; a private Sequence not known safe is kept with its Items
  processed; all other Private Attributes are removed. dicom-anon `--retain-safe-private`.
- **`ConfidentialityProfile.Options.cleanGraphics` (Clean Graphics Option, 113103)** (D159; PS3.15 2026a E.3.3,
  Table E.1-1 Clean Graph. column): Graphic Annotation Sequence (0070,0001) is kept and the text inside it is
  cleaned as Clean Descriptors cleans (a descriptor row inside a cleaned Sequence is cleaned, not replaced by a
  dummy); overlays are still removed. dicom-anon `--clean-graphics`.
- Clean Structured Content and Clean Recognizable Visual Features: added later the same day (see the section
  above).

### Fixed — deferred rows, de-identification, batch b4 (2026-10-01, DICOM 2026a)

- **Clean Descriptors Option cleans** (D158; PS3.15 2026a E.3.5, Table E.1-1a "C"): a C attribute was kept
  verbatim while 113105 was recorded. `ConfidentialityEngine` now removes from each kept text value every
  value the profile removes or replaces elsewhere in the data set (name components and whole names,
  identifiers, addresses, institution and device names, ages, UIDs, dates in YYYYMMDD and common display
  forms), whole-word and case-insensitive, and a capitalised word after Dr / Mr / Mrs / Ms / Miss / Prof;
  a C attribute of a non-text VR is made zero-length. dicom-anon `--clean-descriptors` help and README say so.
- **Retain Longitudinal Temporal Information With Modified Dates modifies DT too** (D157; PS3.15 2026a E.3.6):
  DA values and the date part of DT values are shifted by the whole-day offset (time and UTC offset kept); TM
  values are kept (the time of day of a shifted date); Timezone Offset From UTC and the two OB timestamps get
  their Basic Profile action. DT values and 3 other rows used to be zeroed. Date shifting uses a UTC Gregorian
  calendar, so a daylight-saving change cannot move a date.
- **Longitudinal Temporal Information Modified (0028,0303) is recorded** (D161; PS3.15 2026a E.2, E.3.6; PS3.3
  Table C.7-1): REMOVED without a Retain Longitudinal Temporal Information Option, UNMODIFIED with Full Dates,
  MODIFIED with Modified Dates.
- **De-identification method record after pixel cleaning** (D160; PS3.15 2026a E.1.1; PS3.3 Table C.7-1): the
  113100 Basic Profile Item is first in (0012,0064), before a 113101 Item recorded by `PixelRedactor`, and
  (0012,0063) has one value per Item, so "Clean Pixel Data Option" is named there too.
- **`Anonymizer.parseFlexibleTag` takes every PS3.6 keyword** (D163; PS3.6 2026a Table 6-1), exactly, instead
  of 11 hard-coded ones (its lowercased lookup could never match). dicom-anon drops its own dictionary fallback.
- **`--keep` exempts a tag from the legacy date shift and UID regeneration** (D164): `--keep StudyDate
  --shift-dates N` no longer shifts Study Date.

### Fixed — deferred rows, UID batch (2026-10-01, DICOM 2026a)

- **`UIDManager.regenerateData` remaps UIDs inside sequences and only the UIDs PS3.15 replaces** (D135, D138;
  PS3.15 2026a Table E.1-1): the 57 UI attributes of Table E.1-1 (action U; D for Annotation Group UID) —
  `UIDManager.regeneratedUIDTags` — are replaced at every sequence depth, so Referenced SOP Instance UID (0008,1155)
  in Referenced / Source Image Sequence and Referenced Frame of Reference UID (3006,0024) follow the instance they
  point at, within a file always and across files with `maintainRelationships`. UIDs of other attributes (Coding
  Scheme UID, Context Group Extension Creator UID, SOP Class UIDs, private UI attributes) and any PS3.6 Table A-1 UID
  are no longer replaced. The dry-run preview lists nested values as `(0008,1140)>(0008,1155)`; nested mapping
  entries carry that path in `tagName`. `UIDManager.uidTags` is deprecated.
- **`validateUID` applies the PS3.5 9.1 rules only** (D133): a one-component UID is valid (the "at least 2
  components" rule is not in 9.1) and every message cites PS3.5 9.1; `validateFileUIDs` checks every UI value of the
  File Meta and of all sequence items (was top-level data set only).
- **`UIDConsole` lookup texts name PS3.6 Table A-1** (D136): "UID not found in the DICOM UID registry (PS3.6 Table
  A-1): …"; the unknown `--type` line lists the 11 UID Type filters (new shared `UIDConsole.lookupTypeFilters` /
  `entries(forTypeFilter:)`, used by `dicom-uid`).

### Fixed — deferred rows, DICOMDIR batch (2026-10-01, DICOM 2026a)

- **`DICOMDirectory.Builder` indexes every instance** (D129; PS3.3 2026a F.4, Table F.4-1): a second image of a
  series, or a second series of a study, used to be added to a copy of the (value-type) record that was never written
  back, so only the first image per series and the first series per study were indexed. Every instance now gets its
  own IMAGE record, records keep the order the files were added (was dictionary order), and a second file with an
  already indexed SOP Instance UID is refused.
- **The Application Profile is enforced** (D70; PS3.11 2026a Tables A.3-1, B.3-1, C.3-1, D.3-1, E.3-1, G.3-1, H.3-1,
  I.3-1, J.3-1, K.3-1, L.3-1, L.3-2, M.3-1, N.3-1, generated into `DICOMDIRProfileTables.swift` by the new
  `Scripts/generate_dicomdir_profile_rules.py`): `addFile` throws `DICOMDIRProfileRules.Refusal` naming the table
  when the profile does not list the SOP Class or Transfer Syntax — e.g. STD-GEN-CD / -DVD-RAM / -BD admit Explicit
  VR Little Endian only, -JPEG profiles add JPEG Lossless SV1 / Baseline / Extended, -J2K profiles JPEG 2000, MPEG
  profiles their one MPEG syntax; the general profiles admit the Media Storage SOP Classes of PS3.4 Tables B.5-1 and
  GG.3-1 only. Behaviour change: an Implicit VR or compressed file is no longer indexed under the default STD-GEN-CD.
- **File IDs follow PS3.10 8.2 / 8.5** (D131): `addFile` refuses a Referenced File ID that is not 1-8 components of
  1-8 characters A-Z, 0-9, _ (in-place `create` of `img1.dcm` is refused; the summary lists each refused file and
  why). New `DICOMDIRWorkflow.buildDirectory(..., copyingInto:)` and `dicom-dcmdir create --copy-to <folder>` copy
  the files into a new File-set under assigned File IDs `DICOM\PTnnnnnn\STnnnnnn\SEnnnnnn\IMnnnnnn`. `create` exits 1
  and writes no DICOMDIR when every file is refused (PS3.11 D.3.3). `CreateResult` / `UpdateResult` gain `failures`.
- **`dicom-dcmdir dump --verbose` labels record keys with their PS3.6 names** (D128): `(0010,0020) Patient ID: …`
  instead of `(0010,0020): …`; "Consistent: true" / "Yes" is now `File-set Consistency Flag: 0000H (no known
  inconsistencies)` (PS3.3 2026a Table F.3-3) in tree, text and the validate report. JSON keys are unchanged.

### Fixed — deferred rows, DICOMweb client and console output (2026-10-01, DICOM 2026a)

- **QIDO table labels are PS3.6 names** (D105): `QIDOResultFormatter` tables say Study Instance UID, Patient's Name,
  Modalities in Study, Number of Study Related Series, Series Instance UID, Series Description, Number of Series
  Related Instances, SOP Class UID (printed whole, no longer cut to 15 characters) and Number of Frames. PS3.6 2026a
  Table 6-1.
- **STOW Failure / Warning Reason** (D106): `STOWResultFormatter.failureReason` prints `<hex> (<decimal>): <meaning>`
  (PS3.18 2026a Table I.2-2, ranges included); Warning Reason (0008,1196) is read from the Referenced SOP Sequence
  items (Table I.1-1) into the new `STOWResponse.InstanceResult.warningReason` and `STOWResponse.warnings`, and
  `dicom-wado store --verbose` prints it with its Table I.2-1 meaning (new `STOWResultFormatter.warningDetail`,
  `STOWResponse.standardMeaning(forFailureReason:)` / `(forWarningReason:)`).
- **UPS search takes "IN PROGRESS"** (D107): `UPSQuery.workitemSearch` accepts the PS3.3 2026a Table C.30.1-1 term
  with the space (IN_PROGRESS / INPROGRESS still accepted); dicom-wado's rewrite workaround is removed.
- **WADO-URI: every Section 9 parameter and Rendered Media Type** (D108): new `WADOURIClient.Parameters`,
  `MediaType`, `Region`, `retrieve(studyUID:seriesUID:objectUID:parameters:)`, `requestURL(...)` and
  `WADOURIParameterError` carry charset, annotation / imageAnnotation, imageQuality, region, windowCenter,
  windowWidth, presentationUID, presentationSeriesUID and the 14 Rendered Media Types of Table 8.7.4-1 (image/jxl,
  video/mp4, video/H265, text/*, application/pdf added), and check the 9.5.1.2.x pair / exclusion / range rules
  before sending. The `ContentType` enum and the old `retrieve` are unchanged. `dicom-wado retrieve --uri` gains
  `--charset`, `--annotation`, `--image-quality`, `--region`, `--window-center`, `--window-width`,
  `--presentation-uid`, `--presentation-series-uid` and accepts the new media types; `--rows` without `--columns`
  (or the reverse) is now refused (9.5.1.2.4: "both shall be present"). PS3.18 2026a Tables 9.1.2-2, 9.4.1-1,
  9.5.1-1, 8.7.4-1.
- **UPS `dicom-json` from the parsed result** (D213): `WorkitemResult` keeps the server's DICOM JSON object
  (`dicomJSON`, `attributes`); `UPSOutputFormat.dicomJSON` renders it (PS3.18 F.2). dicom-wado `ups --search` /
  `--get` no longer fetch a second raw copy (`DICOMwebClient.searchWorkitemsDICOMJSON` stays public).
- **Retrieve Workitem without SOP Instance UID** (D-WEB-UPSGET-1): `retrieveWorkitemResult(uid:)` uses the requested
  UID when the response has no (0008,0018), which PS3.4 2026a Table CC.2.5-3 (N-GET column) does not allow in it.

### Fixed — deferred rows, pixel / video / document batch (2026-10-01, DICOM 2026a)

- **`ImageConverter` writes Specific Character Set, the SC device identity and valid EXIF text** (D166, D167, D168;
  PS3.3 2026a Tables C.12-1, C.12-5, C.8-24 and the C.8.6.1 scenario table; PS3.5 Table 6.2-1): (0008,0005)
  `ISO_IR 192` when a text value is not ASCII; the converter is recorded as Secondary Capture Device Manufacturer /
  Model Name / Software Versions (0018,1016/1018/1019: "DICOMKit", "DICOMKit ImageConverter",
  `DICOMFile.implementationVersionName`) instead of General Equipment Manufacturer "DICOMKit" / "dicom-image CLI" /
  "1.1.6" (General Equipment, U in Table A.8-1, describes the original equipment and is no longer written); an EXIF
  UserComment / ImageDescription copied to Study Description is cut to 64 characters with `\` → `/` and control
  characters → space. DICOMStudio's conversion gets all three; dicom-image's own ISO_IR 192 step stays (idempotent).
- **`PixelEditor.processData` output is a Derived Image; window in Modality LUT units; crop geometry; stored range;
  lossy flag; PALETTE COLOR and padding** (D169–D174; PS3.3 2026a C.7.6.1.1.2, Table C.12-10, C.11.2.1.2,
  C.7.6.2.1.1, C.9.2, C.7.6.3.1, C.7.6.1.1.5, C.7.6.3.1.5, C.7.5.1.1.2; PS3.10 Table 7.1-1): new parameter
  `derivation: PixelEditDerivation? = PixelEditDerivation()` (also on `processFile`) — new SOP Instance UID and
  (0002,0003), Image Type Value 1 DERIVED, Derivation Description "<prefix>: <steps>", a Source Image Sequence Item
  with Purpose of Reference DCM 121322 (CID 7202), Smallest/Largest (Image) Pixel Value removed, Implementation Class
  UID / Version Name of DICOMKit; `nil` keeps the source identity (PixelRedactor passes `nil`). `.windowLevel`
  center/width are now Modality LUT output units (Rescale per frame or the Modality LUT Sequence) and a width below 1
  throws `invalidWindowWidth`; `.crop` moves Image Position (Patient) at the top level and in the Plane Position
  Sequence of the functional groups, and Overlay Origin (60xx,0050); every written sample (mask fill included) is
  clamped to Bits Stored / Pixel Representation; decoding a lossy source sets Lossy Image Compression "01" and the
  Method when absent; window/invert of PALETTE COLOR throw the new `PixelEditError.notApplicableToPaletteColor`;
  Pixel Padding Value / Range Limit follow invert and window, or are removed when a window maps padding onto image
  values. dicom-pixedit now calls the engine with prefix "dicom-pixedit" and no longer marks or translates itself.
- **Video: MPEG-2 container unconstrained, MPEG-2 levels named, raw MPEG-2 detected, Specific Character Set** (D177,
  D178, D179, D180; PS3.5 2026a 8.2.5–8.2.11; PS3.3 Tables C.12-1, C.12-5): new
  `VideoContainer.isPermittedByDICOM(for:)` — MPEG-TS/MP4 for H.264/HEVC, any readable container (elementary stream,
  QuickTime included) for MPEG-2; the codec-blind `isPermittedByDICOM` property is deprecated. `levelDescription`
  prints MPEG-2 levels as "Main" / "High" / "High 1440" / "Low" instead of "0.8"; the MPEG-2 level ceiling now
  compares level_identification the right way round (High in MP@ML is a violation, Low is not). `VideoProbe`
  recognises a raw MPEG-2 stream (sequence header 00 00 01 B3) before the H.264 search, which took slice 0x07 for an
  SPS. `Video.toDataSet` writes `ISO_IR 192` for non-ASCII text.
- **Encapsulated Document Length and Specific Character Set** (D181, D182; PS3.3 2026a Table C.24-2, Tables C.12-1,
  C.12-5): `EncapsulatedDocument.toDataSet` writes (0042,0015) with the unpadded byte count and `ISO_IR 192` for
  non-ASCII text (also in `buildDataSet`); `EncapsulatedDocumentParser` cuts the value to (0042,0015) when it is one
  less than the value length (new `documentStream(_:in:)`), so an odd-length document no longer gains a 0x00 and
  `metadataReport()` shows the real size. dicom-pdf's own steps stay (idempotent).

### Fixed — deferred rows, DICOMweb data exchange (2026-10-01, DICOM 2026a)

- **BulkDataURI / BulkData uri unique per element** (D110): `DICOMJSONEncoder` and `DICOMXMLEncoder` name an element
  inside sequence items `<base>/<SQ tag>/<item n>/<GGGGEEEE>` (top level unchanged, `<base>/<GGGGEEEE>`); the XML
  encoder uses the full (gggg,xxee) tag of a private element. PS3.18 2026a F.2.6, PS3.19 Table A.1.5-2.
- **`--metadata-only` is the Metadata of PS3.18 10.4.1.1.2** (D111, **behaviour change**, dicom-json / dicom-xml and
  `DataExchangeWorkflow`): every OB/OD/OF/OL/OV/OW/UN value at any depth (Pixel Data, Float / Double Float Pixel Data,
  Encapsulated Document, Waveform, Overlay, LUTs) is left out, or with `--bulk-data-url` written as a BulkDataURI /
  BulkData (10.4.3.3.2); before, only top-level (7FE0,0010) was dropped.
- **BulkData references on `--reverse`** (D113): `DICOMJSONDecoder` / `DICOMXMLDecoder` take an optional synchronous
  `bulkDataResolver` (new, defaulted `Configuration` parameter); `DataExchangeWorkflow.decode` reads a `file:` URL or
  absolute path and reports every other reference as a `Warning:` line (dicom-json / dicom-xml print it on stderr)
  instead of writing an empty element silently. PS3.18 F.2.6, PS3.19 Table A.1.5-2.
- **Empty PersonName value keeps its number** (D115): `DICOMXMLEncoder` writes `<PersonName number="n"/>`, so numbers
  run 1..n by 1 and the value survives a round trip. PS3.19 2026a Table A.1.5-2.
- **Group 0002 stays out of the data set on `--reverse`** (D-WEB-FILEMETA-1): `DataExchangeWorkflow.decode` takes the
  Transfer Syntax UID from group 0002 of the input and leaves group 0002 out of the main data set. PS3.10 2026a 7.1.

### Fixed — deferred rows, dump / info / tags / diff engines, batch b4 (2026-10-01, DICOM 2026a)

- **`HexDumper` annotates the right bytes at any offset** (D144; PS3.10 2026a 7.1): the element walk skips the
  128-byte Preamble and "DICM" Prefix only when "DICM" is at bytes 128-131, so a file without them (`--force`) is
  annotated from byte 0. New `HexDumper.dump(fileData:startOffset:length:dicomFile:highlightTag:)` walks the whole
  file and shows the requested range, so `--offset` keeps `--annotate` / `--highlight` on their bytes (an element
  that starts before the range can still be highlighted); dicom-dump uses it. `dump(data:startOffset:…)` is
  unchanged for a slice that starts on an element boundary.
- **`HexDumper` labels Items and delimiters and descends every Item** (D145; PS3.5 2026a 7.5, A.4; PS3.6 Table
  6-1): (FFFE,E000) Item, (FFFE,E00D) ItemDelimitationItem and (FFFE,E0DD) SequenceDelimitationItem are annotated
  (no VR), defined-length Sequences and Items are descended so their elements are annotated, and the fragments of
  encapsulated Pixel Data are stepped over.
- **Private Creator Data Elements are named "Private Creator"** (D146; PS3.5 2026a 7.8.1: (gggg,0010-00FF), gggg
  odd) instead of "Unknown" / no name in `MetadataPresenter` (dicom-info text, JSON, CSV), `HexDumper` (`--tag`
  header, annotations), `TagEditor` change lines and the dicom-diff report (`ComparisonReport`).
- **`MetadataPresenter --statistics` names the UIDs** (D147; PS3.6 2026a Table A-1): text prints
  `Transfer Syntax: 1.2.840.10008.1.2.1 (Explicit VR Little Endian)` and the SOP Class likewise; JSON keeps
  `transferSyntax` / `sopClass` and adds `transferSyntaxName` / `sopClassName`.
- **`MetadataPresenter` filters match PS3.6 keywords exactly** (D148; PS3.6 2026a Table 6-1/7-1), as well as the
  name / tag substring. dicom-info drops its own keyword-to-tag workaround (`DICOMInfo.filterTerms`).
- **`MetadataPresenter` JSON gives every element a `value`** (D149): VRs without a character value (US, SS, UL,
  SL, FL, FD, AT, the Other VRs) carry the same rendering as the text and CSV output. The JSON is the tool's own
  model (tag / name / vr / value), not the PS3.18 Annex F DICOM JSON Model.
- **`TagEditor` applies the PS3.5 / PS3.10 edit rules** (D150; PS3.5 2026a Table 6.2-1, 7.5, 7.8.1; PS3.10 7.1):
  the rules dicom-tags carried since b091aa5 moved into DICOMKit as public `TagEditRules` and `TagEditRefusal`.
  `applyChanges` now writes the PS3.6 dictionary VR (US, SS, UL, SL, FL, FD as binary; `Rows=512` was the text
  "512 " in a US element), refuses a value outside the Table 6.2-1 limits of that VR, and refuses group 0002,
  Items/delimiters and groups 0001/0003/0005/0007/FFFF for set, delete and copy, each with a "(refused: …)"
  line. New `applyCheckedChanges(…) throws` refuses the whole edit before changing anything; dicom-tags calls
  it (its `checkDataSetEdits` / `applySets` are gone).
- **`DICOMComparer` `ignorePrivate` applies inside Sequence Items** (D152; PS3.5 2026a 7.8).
- **`DICOMComparer` compares Pixel Data per Pixel Sample Value** (D153; PS3.5 2026a 8.1.1, 8.2; PS3.3 C.7.6.3.1.3):
  both files are decoded (compressed ones too) and each sample is read per Bits Allocated, Bits Stored, High Bit
  and Pixel Representation in frame / pixel / sample order whatever the Planar Configuration; `--tolerance`, the
  maximum and the mean are in sample values and "Different pixels" counts pixels with a differing sample.
  Pixel Data that cannot be decoded is compared byte by byte as before. dicom-diff help and README updated.

### Fixed — deferred rows, DICOMCore batch a2 (2026-10-01, DICOM 2026a)

- **`TransferSyntax.isJPIP` covers JPIP HTJ2K Referenced (.204) and JPIP HTJ2K Referenced Deflate (.205)** (D109;
  PS3.5 2026a A.11, A.12; PS3.6 Table A-1), so `DICOMJPIPClient.jpipURI` reads their Pixel Data Provider URL
  (0028,7FE0) instead of throwing `notAJPIPTransferSyntax`. dicom-jpip drops its own .204/.205 fallback.
- **`DICOMDirectory.validate(checkFileExistence:fileSetRoot:)` checks Referenced File IDs on disk** (D130;
  PS3.10 2026a 8.6): with the new `fileSetRoot` (the directory that holds the DICOMDIR) every Referenced File ID
  (0004,1500) must name an existing regular file inside the File-set, else `missingReferencedFile(<File ID>)`;
  `.`/`..` components are rejected. Without a root the call behaves as before.
- **`UIDGenerator` no longer crashes or repeats UIDs** (D139; PS3.5 2026a 9.1, B.2): a root that breaks the 9.1
  rules or leaves no room for the suffix within 64 characters now yields a UUID derived UID (`2.25.<UUID as a
  decimal integer>`) instead of a force-unwrap crash or a truncated, identical UID. New `UIDGenerator.isUsableRoot(_:)`
  and `UIDGenerator.uuidDerivedUID(_:)`.
- **`Tag.isPrivate` excludes groups 0001, 0003, 0005, 0007 and FFFF** (D151; PS3.5 2026a 7.1: Private Data
  Elements have "an odd Group Number that is not 0001, 0003, 0005, 0007, or FFFF"; 7.8.1: those "shall not be
  used"). New `Tag.isOddGroup` (the old parity test) and `Tag.unusableOddGroups`; the Basic Profile engine
  (`ConfidentialityEngine`) and `TagEditor`'s delete-private pass use `isOddGroup`, so such elements are still removed.
- **`TransferSyntax.displayName` is the PS3.6 2026a Table A-1 UID Name** (D176), verbatim for all 63 rows (e.g.
  "MPEG2 Main Profile / Main Level", "JPEG 2000 Image Compression (Lossless Only)", "Explicit VR Big Endian
  (Retired)"); the former abbreviations are the new `shortName`. `SelectableEncoding.displayName` is the A-1 name
  plus "(lossless)" / "(lossy)" for the either-intent UIDs (.91, .93, .203); `SelectableEncoding.shortName` keeps
  the old picker label. `PixelDataError.transferSyntaxName` is the A-1 name. Every tool line that prints a transfer
  syntax name (dicom-video, dicom-j2k, dicom-compress, conversion diagnostics, …) now shows the standard's name.
- **HTJ2K Lossless RPCL (.202) codestreams meet PS3.5 2026a 10.18.1** (D187): the encoder is given enough
  decomposition levels for a base resolution ≤ 64, the main header gets a TLM marker segment, and the COD
  progression order is set to RPCL when the packet sequence is provably identical (one quality layer, default
  precincts — what J2KSwift writes; J2KSwift itself always writes LRCP). J2K → .202 no longer takes the
  coefficient fast path. New `J2KCodestreamInspector.codingStyle(in:)`, `htj2kRPCLViolations(in:rows:columns:)`,
  `minimumDecompositionLevelsForRPCL(rows:columns:)` and `conformingToHTJ2KRPCL(_:)`. Verified bit-exact with
  OpenJPH, OpenJPEG, Kakadu and Grok.
- **JPEG output carries no JFIF APP0 segment** (D190; PS3.5 2026a 8.2.1: "it is recommended that it be absent"):
  `JLICodec` and `NativeJPEGCodec` strip it. New `JPEGInterchangeFormat.removingJFIFSegments(_:)`.
- **JPEG 2000 / HTJ2K Photometric Interpretation follows the codestream** (D193; PS3.5 2026a 8.2.4, Table 8.2.4-1,
  8.2.14): `TransferSyntaxConverter` labels RGB encoded with the multi-component transformation (COD MCT = 1)
  YBR_RCT (5-3) or YBR_ICT (9-7) with Planar Configuration 0, and relabels YBR_RCT / YBR_ICT to RGB after
  decoding to native.

### Fixed — deferred rows, SR / script / JP3D batch (2026-10-01, DICOM 2026a)

- **SR NUM without a value (D194)**: `SRDocumentParser` no longer reads a NUM whose Measured Value Sequence (0040,A300) is empty as 0.0 in lenient mode; `numericValues` stays empty and `value` is nil (PS3.3 2026a Table C.18.1-1: Type 2, "Zero or one Item"; C.18.1: "may be empty to convey ... a measurement whose value is unknown or missing"). `SRDocumentSerializer` writes a NUM with no value as an empty Measured Value Sequence instead of an empty Numeric Value.
- **SR Numeric Value Qualifier (D195)**: Numeric Value Qualifier Code Sequence (0040,A301) (Type 1C, CID 42 = CID 43 + CID 44) is read into `NumericContentItem.numericValueQualifier` and written by `SRDocumentSerializer`.
- **SR Referenced Waveform Channels (D196)**: `SRDocumentSerializer` writes Referenced Waveform Channels (0040,A0B0) as US (M,C) pairs (Table C.18.5-1, C.18.5.1.1). New in DICOMCore (additive): `WaveformChannelReference`, `WaveformReference.referencedChannels`, `WaveformReference.init(sopReference:referencedChannels:)`; the parser keeps the Multiplex Group numbers it used to drop. `init(sopReference:channelNumbers:)` places its channels in multiplex group 1.
- **SR Type 2 Patient / General Study / General Equipment attributes (D198)**: `SRDocument` gains `patientBirthDate`, `patientSex`, `referringPhysicianName`, `studyID` and `manufacturer` (new defaulted `init` parameters, `withPatientStudyAndEquipment(...)`, `withRootContent(_:)`); the nine SR builders pass Patient's Birth Date, Patient's Sex and Referring Physician's Name through `build()`. `SRDocumentSerializer` now always writes Patient's Name, Patient ID, Patient's Birth Date, Patient's Sex, Study Date, Study Time, Referring Physician's Name, Study ID, Accession Number and Manufacturer, zero length when unknown (Type 2 in PS3.3 2026a Tables C.7-1, C.7-3, C.7-8; modules M in Table A.35.3-1). `SRDocumentParser` reads these attributes and returns nil for a zero-length value.
- **TID 1500 algorithm, observer and template (D199)**: `MeasurementReportBuilder.withAlgorithmIdentification(_:)` (TID 1500 row 6b → TID 4019), `withQualitativeEvaluationsAlgorithmIdentification(_:)` (row 12b), `MeasurementGroupData.algorithmIdentification` (TID 1501 row 9b) and `addObserver(_:)` with `MeasurementReportObserver.person` / `.device` (row 3 → TID 1001 → TID 1002/1003/1004); the root CONTAINER always carries Content Template Sequence (DCMR, 1500) (PS3.3 Table C.18.8-1). Row 6 is written when an algorithm is set and there are no Qualitative Evaluations (MC "IF Row 10 and Row 12 are absent"). dicom-ai now uses `withAlgorithmIdentification` instead of adding row 6b and the template itself.
- **Segmentation IOD modules (D71)**: `Segmentation.buildDataSet(pixelData:)` writes the Type 2 Patient (PS3.3 2026a Table C.7-1) and General Study (Table C.7-3) attributes, zero length when unknown, and the Enhanced General Equipment Module (Table C.7-8b: Manufacturer, Manufacturer's Model Name, Device Serial Number, Software Versions, all Type 1), both Modules M in Table A.51-1. New: `SegmentationPatientAndStudy` (with `init(copyingFrom:)`), `SegmentationEquipment` (default `.dicomKit`: "DICOMKit" / "SegmentationBuilder" / DICOMKit's Implementation Class UID / Implementation Version Name), `Segmentation.patientAndStudy` / `.equipment`, `SegmentationBuilder.setPatientAndStudy(_:)` / `setEquipment(_:)`. dicom-ai still sets these attributes itself after `buildDataSet`; that is now redundant but left unchanged.
- **dicom-script templates (D200, D201, D203)**: the `pipeline`, `query` and `archive` templates (`TemplateGenerator`) and the dicom-script README now use options the called tools declare: the PACS host is dicom-query's / dicom-retrieve's positional argument (no `--host`), the calling AE Title is `--aet` (no `--calling-aet`), levels are `patient` / `study`, a Study Date range is one PS3.4 2026a C.2.2.2.5 range value `--study-date 20240101-20241231` (no `--study-date-from/--study-date-to`), dicom-retrieve retrieves by `--study-uid` with `--method c-get` (it has no `--patient-id`), and dicom-archive uses `init --path` / `import <dir> --archive` / `query --archive` / `export --archive` (it has no `create` subcommand).
- **JP3D decode-volume geometry (D204, D205)**: `JP3DVolumeDocument.decode(from:)` places slice *i* at the first slice's Image Position (Patient) plus *i* × spacing along the normal of Image Orientation (Patient) (row cosine × column cosine, PS3.3 2026a C.7.6.2.1.1, Equation C.7.6.2.1-1) instead of moving only z, and writes Image Orientation (Patient) and Pixel Spacing (Table C.7-10), one Frame of Reference UID per series (C.7.4.1.1.1), the source Rescale Intercept / Slope / Type and the source SOP Class (sidecars without it: CT, MR or PET Image Storage by Modality, else Secondary Capture, instead of CT for any source); Slice Location is the position along the normal. `encode` records the origin, spacing, orientation, pixel spacing, Frame of Reference UID, rescale and SOP Class of the first slice in the order `JP3DVolumeBridge.makeVolume` stacks the volume, and the bridge now sorts and spaces slices by Image Position (Patient) projected on the slice normal (z only when Image Orientation (Patient) is absent), so unsorted and sagittal / coronal / oblique series keep their geometry.

### Fixed — deferred rows, study / archive / validator batch (2026-10-01, DICOM 2026a)

- **Study engine labels are PS3.6 names** (D116): `StudyReport.renderSummary` (table) and `renderStats` (text),
  used by dicom-study and DICOMStudio, print Study Instance UID, Patient's Name, Study Description, Series Number,
  Series Description, Number of Study Related Series, Number of Study Related Instances and Number of Series
  Related Instances (PS3.6 2026a Table 6-1) instead of "Study UID", "Patient Name", "Description", "Number",
  "Series Count", "Total Instances", "Instances".
- **`organize --pattern descriptive` gives every series (and study) its own folder** (D117): a descriptive name
  shared by two series (Series Number is Type 2 in PS3.3 2026a Table C.7-5a, so absent numbers all became "0") or
  two studies is suffixed with the full Series (Study) Instance UID; before, the second copy failed "already exists".
- **Files without Series Instance UID / SOP Instance UID are reported, not merged** (D118): both are Type 1
  (PS3.3 Tables C.7-5a, C.12-1). New `StudyScanner.scan(at:)` returns the studies and a `skipped` list
  (`StudySkippedFile`: path + reason); `scanStudies(at:)` is unchanged in signature and leaves those files out
  instead of grouping them under "UNKNOWN". dicom-study prints one `warning: skipped …` line per file on stderr;
  `StudyOrganizer` logs `Missing Series Instance UID (0020,000E)` and leaves the file in place instead of filing it
  under `UNKNOWN_SERIES`.
- **ArchiveStore matches query keys per PS3.4 2026a C.2.2.2** (D120, D121): new public `ArchiveMatching`.
  Patient ID and Modality wild cards are case-sensitive (C.2.2.2.4: "case sensitive, except for Attributes with a
  PN VR"); Patient's Name stays case-insensitive. Study Instance UID (query) and Study / Series Instance UID
  (export) take a backslash-separated List of UIDs (C.2.2.2.2). Study Date takes `YYYYMMDD`, `YYYYMMDD-YYYYMMDD`,
  `-YYYYMMDD` or `YYYYMMDD-` (DA Range Matching, C.2.2.2.5.1, inclusive). dicom-archive no longer warns that ranges
  and UID lists match exactly; it warns only for a Study Date that is neither a DA value nor a DA range.
- **Study modality is Modalities in Study** (D122, D209): the query table and text print Modalities in Study
  (0008,0061), the distinct Modality values of all the study's series (`CT\PT`), instead of the first imported
  instance's Modality. `ArchiveStudy.modality` is deprecated (use `modalitiesInStudy`); the index keeps writing
  the `modality` key.
- **Archive labels are PS3.6 names** (D123): query table / text print Patient's Name, Study Instance UID, Study
  Description, Modalities in Study, Number of Study Related Series / Instances; list table prints Number of Patient
  Related Studies / Series / Instances (PS3.6 2026a Table 6-1); "Images" (which counted every instance) is gone;
  stats names each SOP Class UID from PS3.6 Table A-1.
- **Patients are keyed on Patient ID + Issuer of Patient ID (0010,0021)** (D124; PS3.4 Tables C.6-1 / C.6-5): new
  `ArchivePatient.issuerOfPatientID` (index key `issuerOfPatientID`, query JSON `IssuerOfPatientID`, shown in
  list tree and query text); files with an empty or absent Patient ID (Type 2) are also keyed on Patient's Name,
  so different unidentified patients are no longer merged into one "UNKNOWN" patient. Older indexes load.
- **GSPS / Pseudo-Color PS: no error for a missing Content Creator's Name** (D140): (0070,0084) is Type 3 in the
  Content Creator Macro (PS3.3 2026a Table 10.9.3-1, included by Table 10-12), not Type 2.
- **IOD message prefixes are PS3.6 Table A-1 names** (D141): "Computed Radiography Image Storage", "Ultrasound
  Image Storage", "Grayscale Softcopy Presentation State Storage", "Pseudo-Color Softcopy Presentation State
  Storage", "Key Object Selection Document Storage" and the SR SOP Class name (e.g. "Basic Text SR Storage")
  instead of "CR Image Storage", "US Image Storage", "GSPS", "Pseudo-Color PS", "Key Object Selection Document",
  "Structured Report".
- **SR / KOS root Concept Name Code Sequence is Type 1C** (D143): reported as "Missing Type 1C … (required for the
  Root Content Item) [PS3.3 … (Table C.17-5); PS3.5 7.4.2]" instead of Type 1.
- **Level 2 checks lengths, repertoires and VM** (D142): every character-string Value is checked against PS3.5
  2026a Table 6.2-1 (maximum or fixed length — LO 64 chars, SH 16, CS 16 bytes, DS 16, IS 12, UI 64, AS 4, …;
  character repertoire; AS / DS / IS forms, IS within -2^31…2^31-1), PN against PS3.5 6.2.1 (≤ 3 component groups,
  ≤ 4 "^" per group, 64 chars per group), and the number of Values against the PS3.6 Table 6-1 VM column; each is
  an error. A lowercase Code String is now an error (outside the CS repertoire) instead of a "should be uppercase"
  warning. DA / TM / UI are judged per Value (a multi-valued DA no longer fails) and each problem is reported once
  (no second "Invalid Study Date format" line).

### Fixed — deferred rows, network batch (2026-10-01, DICOM 2026a)

- **DIMSE-N, Modality Worklist, MPPS and Print status names** (D73, D79, D82, D91): `DIMSEServiceStatusText` now
  carries, generated from the 2026a DocBook and verbatim, PS3.4 Tables K.4-1 (MWL C-FIND), F.7.2-2 (MPPS N-SET,
  with Error ID A710 "Performed Procedure Step Object may no longer be updated"), F.8.2-2 (MPPS N-GET), the seven
  Print Management tables H.4.1.2.1.2-1, H.4-4, H.4.2.2.1.2-1, H.4-9, H.4.3.1.2.1.2-1, H.4.3.2.2.1.2-1,
  H.4.9.2.1.2-1, and the 24 PS3.7 Annex C sections that fix a code (`annexCRow(for:)`, `printRow(for:)`,
  `describePrintStatus(_:)`, `mppsNSetErrorComment(errorID:)`). `DIMSEStatusService` gains `.mwlFind`, `.mppsNSet`,
  `.mppsNGet`, `.filmSessionNCreate`, `.filmSessionNAction`, `.filmBoxNCreate`, `.filmBoxNAction`,
  `.grayscaleImageBoxNSet`, `.colorImageBoxNSet`, `.presentationLUTNCreate` and `.dimseN` (new enum cases: an
  exhaustive `switch` over `DIMSEStatusService` outside DICOMNetwork needs the new cases or a `default`);
  `description(for:)` names a code the service table lacks from Annex C. `DIMSEStatus.description` uses the 2026a
  names: A900 "Error: Data Set does not match SOP Class" (was "Error: Identifier/Data does not match SOP Class"),
  0110 "Processing Failure" (was "Failed: Unable to process", the Cxxx row of the Q/R tables), A701/A702 "Refused: Out
  of resources", A801 "Refused: Move Destination unknown", B000/B006/B007 in Table B.2-1 capitalisation, 0111 / 0112
  / 0118 / 0213 without the invented "Failed:" prefix, and every other Annex C code by its section title instead of
  "Unknown status" (0105, 0106, 0107, 0113-0117, 0119-0121, 0123, 0124, 0210-0212; 0117 is "Invalid SOP Instance").
  `DICOMNetworkError.printOperationFailed` words the status per Annex H, e.g. "Failure (0xC603): Failed: Image size is
  larger than image box size" instead of "Failed: unable to process / cannot understand (Cxxx)".
- **`PrintSCPStatus.explanation` (Error Comment) is the Annex H / Annex C text** (D93): B604, B605, B609, C603, C605,
  C613 were paraphrases; C600 / C601 gain the table's "Failed: " prefix; 0117 reads "Invalid SOP Instance", 0119
  "Class-Instance conflict" (PS3.7 C.5.12 / C.5.7).
- **MPPS** (D83, D84, D86, D87): N-CREATE / N-SET failures are thrown as the new
  `DICOMNetworkError.mppsOperationFailed(operation:status:errorComment:errorID:)` ("MPPS N-SET failed: Failure
  (0x0110): Processing Failure — Error ID A710H: Performed Procedure Step Object may no longer be updated") instead of
  `storeFailed` ("Store failed: …"; new enum case — exhaustive switches outside DICOMNetwork need it); the N-CREATE
  data set creates Performed Procedure Step Discontinuation Reason Code Sequence (0040,0281) zero-length so a later
  N-SET to DISCONTINUED may fill it (PS3.4 F.7.2.1.1 note, F.7.2.1.2); `DICOMMPPSService.validate(_:for: .nCreate)`
  refuses an empty Modality (0008,0060), Type 1 in Table F.7.2-1 (it was sent empty); the `CODE|SCHEME|MEANING` example
  is `110513|DCM|Discontinued for unspecified reason` (PS3.16 Table D-1; "Doctor canceled procedure" is 110500) and CID
  9300 is "Procedure Discontinuation Reason". dicom-mpps' own `.storeFailed` renaming is now unused (left in place).
- **C-STORE Warning is a stored result** (D72): `DICOMStorageService.store` sets `StoreResult.success` for the Success
  and the Warning class of PS3.4 Table B.2-1 (B000, B006, B007 store the instance; it was true only for 0000), the
  meaning `FileStoreResult.success` already had; new `isStored`, `isSuccess`, `isWarning`, `isFailure`. A Failure
  status is still returned, not thrown (documented); `StoreAndForwardQueue` now completes items stored with a warning.
- **Shared network console** (D74, D75, D77): Query/Retrieve Level values print as PATIENT / STUDY / SERIES / IMAGE
  (`levelName`, the retrieve header's `Level:`; "instance" / "Instance" before — PS3.4 Table C.6.1-1); the C-MOVE
  result counters read "Number of Completed / Failed / Warning Sub-operations" (PS3.7 Table 9.3-10); the dicom-qr study
  entry labels (0008,0061) "Modalities in Study:" (was "Modality:"); new `NetworkConsole.sendFileResult(status:rtt:)`
  renders Success, Warning (stored, with the B.2-1 warning line) and Failure (not stored) from the status in one call.
  DICOMStudio's CLI Workshop renders the same text through the same functions.
- **Scheduled Station AE Title is Single Value Matching only** (D81): `WorklistQueryKeys.validateScheduledStationAETitle`
  (and `forQuery(station:)`, dicom-mwl `--station`) refuses `*` and `?` (PS3.4 Table K.6-1); they were accepted.
- **Implementation Class UID under DICOMKit's root** (D155): every DICOMNetwork configuration default
  (`StorageConfiguration`, `StorageSCPConfiguration`, `QueryConfiguration`, `RetrieveConfiguration`,
  `VerificationConfiguration`, MPPS, MWL, Print, Storage Commitment, `DICOMClient`) is the new
  `DICOMNetworkImplementation.classUID` = `DICOMFile.implementationClassUID` (1.2.826.0.1.3680043.10.511.3.0.5.0,
  PS3.7 D.3.3.2, PS3.5 9.2.2); they were 1.2.826.0.1.3680043.9.7433.1.x. dicom-retrieve's C-GET File Meta (0002,0012)
  uses it too.
- **Move Originator on the C-STORE-RQ** (D156): `StorageConfiguration.moveOriginatorAETitle` /
  `moveOriginatorMessageID` and `withMoveOriginator(aeTitle:messageID:)` put (0000,1030) / (0000,1031) on every
  C-STORE-RQ (PS3.7 9.1.1.1.6 / 9.1.1.1.7, written only as a pair); dicom-server's C-MOVE sub-operations now carry the
  C-MOVE's calling AE Title and Message ID.
- **dicom-query `--format dicom-json` writes sequences as sequences** (D210): `GenericQueryResult` keeps the Explicit VR
  of each attribute (`vrs`) and the response transfer syntax (`transferSyntaxUID`, new initializer; the old one is
  kept), so `dicomJSONElements()` uses the response's VR (e.g. SS for a "US or SS" attribute) and decodes an SQ into
  item objects (PS3.18 F.2.2 / F.2.5) instead of UN InlineBinary.

### Fixed — File Meta Media Storage UIDs follow the data set (2026-10-01, DICOM 2026a)

- **`DICOMFile.create` takes (0002,0002) / (0002,0003) from the data set** (D175; fixes D112, D137, D165):
  PS3.10 2026a Table 7.1-1 says Media Storage SOP Class / Instance UID identify the SOP Class / Instance of the
  data set in the file. `create` now uses the data set's SOP Class UID (0008,0016) and SOP Instance UID
  (0008,0018) when present (they win over a differing argument); otherwise the argument; otherwise Secondary
  Capture Image Storage / a generated UID, which is then also written into the data set (not for a DICOMDIR,
  whose Basic Directory IOD has no SOP Common Module, PS3.3 Table F.3-1). `sopClassUID:` is now `String?`
  (default nil); existing call sites compile unchanged. Before, an omitted `sopInstanceUID:` minted a second UID
  and an omitted `sopClassUID:` wrote Secondary Capture whatever the data set was: dicom-json / dicom-xml
  `--reverse` (`DataExchangeWorkflow.decode`), dicom-uid `regenerate` (`UIDManager.regenerateData`), dicom-image /
  DICOMStudio (`ImageConverter.secondaryCaptureData`) and dicom-pdf wrote File Meta that disagreed with the data set.
- **De-identified files carry the new SOP Instance UID in (0002,0003)** (D162): `Anonymizer.anonymize` and
  `Anonymizer.deidentify` re-align the carried-over File Meta with the data set through the new public
  `DICOMFile.synchronizingMediaStorageUIDs()` (PS3.15 2026a Table E.1-1 (0002,0003) U; PS3.10 Table 7.1-1), so
  DICOMStudio and every other caller get what dicom-anon already wrote.

### Fixed — deferred rows, misc batch (2026-10-01, DICOM 2026a)

- **DICOMPrintKit status labels** (D90): `PrintConsoleFormatter.printerStatusText` / `jobStatusText` (dicom-print
  `status` / `job`, dicom-printscp `status`, DICOMStudio) label each attribute by its PS3.3 2026a Table C.13-9 /
  C.13-8 name as PS3.6 Table 6-1 spells it: Printer Name, Printer Status, Printer Status Info, Manufacturer's
  Model Name; Execution Status, Execution Status Info, Creation Date and (new line) Creation Time. JSON output is
  unchanged.
- **Trim (2010,0140) = YES prints a trim box around each image** (D92): `FilmComposer` strokes one rectangle just
  outside every placed image, as PS3.3 2026a Table C.13-3 says ("a trim box shall be printed surrounding each
  image on the film"), instead of four crop marks at the sheet corners. `drawTrimMarks` / `--trim-marks` keep
  their names and now switch the trim box.
- **dicom-3d nearest-neighbour edge sample** (D207): `VolumeData.interpolatedVoxelAt(.nearest)` returned nil in the
  last half voxel of the accepted range [0, n) because `round` carried the index to n; it now clamps to the last
  voxel centre (PS3.3 2026a C.7.6.2.1.1), as the linear branch already did.
- **dicom-gateway `listen --forward` builds no template-less data set** (D214): the listener's forward path no longer
  converts each HL7 message into the Secondary Capture data set that `hl7-to-dicom` refuses without `--template`
  (P-GATEWAY-SC, PS3.3 2026a Table A.8-1); it writes one stderr line per message, "Not forwarded to host:port: …",
  with the same reason, since `listen` takes no `--template` and C-STORE forwarding is not implemented (D103).
- **Frame-number citations** (D208): help, error, deprecation and README text of dicom-convert, dicom-export,
  dicom-measure and dicom-j2k, and the DICOMKit `ConversionDiagnostics.invalidFrameNumberMessage` doc, cite PS3.3
  2026a Table 10-3 ("The first Frame shall be denoted as Frame number 1") instead of C.7.6.6, which does not say
  it. dicom-export's deprecation note now reads "PS3.3 Table 10-3: the first Frame is Frame number 1".

### Changed — CLI P-items, net batch (approved 2026-10-01, DICOM 2026a)

- **Service-specific DIMSE status text in DICOMNetwork** (P-QR-STATUS-TEXT, closes D76): new public
  `DIMSEServiceStatusText` / `DIMSEStatusService` carry the 31 rows of PS3.4 2026a Tables B.2-1 (C-STORE),
  C.4-1 (C-FIND), C.4-2 (C-MOVE) and C.4-3 (C-GET) verbatim, and `DIMSEStatus.description(for:)` words a status
  as the table of the answering service names it (0xB000 is "Sub-operations Complete - One or more Failures"
  for C-MOVE, "Coercion of Data Elements" for C-STORE). `dicom-retrieve` and `dicom-qr` drop their private
  `RetrieveStatusText.swift` copies and use it; output text is unchanged. `DIMSEStatus.description` is unchanged.
- **`dicom-retrieve --priority low|medium|high`** and **`dicom-qr query|resume --priority`** (P-RETRIEVE-PRIORITY):
  Priority (0000,0700) of the C-MOVE-RQ / C-GET-RQ, LOW 0002H / MEDIUM 0000H / HIGH 0001H (PS3.7 2026a Tables
  9.3-9 / 9.3-6; default medium, as before). Engine: `RetrieveConfiguration.priority` (new initializer overload
  with `priority:`; the existing initializers keep their signatures and send MEDIUM).
- **`dicom-retrieve --relational-retrieve`** (P-RETRIEVE-EXTNEG): proposes relational-retrieval in a SOP Class
  Extended Negotiation Sub-Item (PS3.7 Table D.3-11; PS3.4 C.5.2.1 / C.5.3.1, Table C.5-3 byte 1), so
  `--series-uid` / `--instance-uid` may be given without the UIDs of the levels above (PS3.4 C.4.2.2.2.1 /
  C.4.3.2.2.1). If the SCP turns it down (no sub-item, or byte 1 = 0, Table C.5-4) such a request is not sent
  (exit 1). Engine: new public `SOPClassExtendedNegotiation`, `RetrieveExtendedNegotiation`,
  `RetrieveConfiguration.extendedNegotiation`, `AssociateRequestPDU` / `AssociateAcceptPDU.extendedNegotiations`
  (encoded and decoded; `PDUDecoder` no longer skips item 56H) and `Association.request(…extendedNegotiations:)`
  — all as overloads, existing signatures unchanged. A non-default priority and the proposal appear in the
  shared retrieve header (`NetworkConsole.retrieveHeader(…priority:relationalRetrieval:)`).
- **`dicom-qr --parallel` now works** (P-QR-PARALLEL): up to N studies are retrieved at once, each on its own
  association; per-study lines are printed in study order after each batch (with the default 1, output is as
  before). `--parallel` below 1 is refused.
- **`dicom-qr` state files gain `ModalitiesInStudy`** (P-QR-STATE-MODALITIES): the PS3.6 keyword key for
  Modalities in Study (0008,0061), the STUDY-level value of PS3.4 Table C.6-5 (`QRStudyInfo.modalitiesInStudy`).
  The old `modality` key ((0008,0060)) is still written with the same value and is deprecated; old state files
  still load.
- **`dicom-send` warning count in the shared summary** (P-SEND-SUMMARY): `NetworkConsole.sendSummary(…warnings:)`
  prints `Warnings: N (stored; PS3.4 Table B.2-1 Warning class)` (only when N > 0) and
  `NetworkConsole.sendFileWarningLine(status:)` words the per-file line by Table B.2-1
  (`⚠️ Stored with warning: Warning (0xB000): Coercion of Data Elements`); the tool's own trailing
  `Stored with warning: N` line is gone.
- **`dicom-query --format dicom-json`** (P-QUERY-JSON): the PS3.18 2026a F.2 DICOM JSON Model (tag keys, `vr`,
  `Value`, PN component objects; UTF-8 / ISO_IR 192), encoded by DICOMWeb's `DICOMJSONEncoder`
  (`QueryOutputFormat.dicomJSON`, `GenericQueryResult.dicomJSONElements()`). `--format json` is unchanged.
- **`dicom-query` table labels are PS3.6 Attribute Names** (P-QUERY-COLUMNS): `Patient's Name`, `Patient's
  Birth Date`, `Patient's Sex`, `Number of Patient Related Studies`, `Study Date`, `Study Description`,
  `Modalities in Study`, `Number of Study Related Series`, `Series Description`, `Series Date`, `Number of Series
  Related Instances`, `SOP Class UID`, `Columns × Rows`, `Number of Frames` (shared formatter, so the DICOMStudio
  query console changes too; columns widen to fit). New `--csv-keywords` writes PS3.6 keywords in the CSV header;
  the default `(GGGG,EEEE)` header is unchanged.
- **`dicom-mwl --json` adds PS3.6 keyword keys** (P-MWL-JSON-KEYS): `ScheduledProcedureStepStartDate`, `…StartTime`,
  `…Status`, `…ID`, `…Description`, `…Location`, `ScheduledPerformingPhysicianName`,
  `RequestedProcedureCodeSequence`, `ScheduledProtocolCodeSequence`, `ReferencedStudySequence` (sequences as arrays
  of item objects) next to the ten abbreviated keys, which keep their values and are deprecated.
- **`dicom-mpps` input checks stay errors** (P-MPPS-STRICT, owner decision): missing `--modality` (Type 1, PS3.4
  Table F.7.2-1), `--patient-sex` outside M/F/O (PS3.3 Table C.2-3), a non-DA `--patient-birth-date`, and
  `update --image-uid` without study/series UIDs are refused (exit 64); now documented in the README.

### Changed — CLI P-items, codec batch (approved 2026-10-01, DICOM 2026a)

- **`dicom-convert --transfer-syntax` / `dicom-j2k transcode --target`: PS3.6 Table A-1 keywords mean their
  Table A-1 UID** (P-CONVERT-TS-KEYWORDS). `JPEG2000Lossless`, `HTJ2KLossless` and `JPEGXLLossless` now select
  1.2.840.10008.1.2.4.90 / .201 / .110 (PS3.6 2026a Table A-1); until now they selected the reversible encode
  into the general UIDs .91 / .203 / .112, which is now spelled `JPEG2000Reversible`, `HTJ2KReversible`,
  `JPEGXLReversible` (the kebab names `jpeg2000-lossless`, `htj2k-lossless`, `jpeg-xl-lossless` are unchanged).
  Using one of the three keywords prints a one-line stderr note for this release. Shared code: the
  `DICOMConverter` catalog (DICOMKit) and `TransferSyntax.parseEncoding` (DICOMCore); `TransferSyntax.parse`
  also accepts every Table A-1 keyword of a target it knows; new `TransferSyntax.reassignedTableA1Keywords` /
  `reassignedKeywordNote(for:)`.
- **`dicom-convert --frame-number`** (P-CONVERT-FRAME): new 1-based frame option (PS3.3 2026a C.7.6.6, "The first
  Frame shall be denoted as Frame number 1"). `--frame` (0-based index) is deprecated: it still works, `--help`
  says so and it prints a stderr note; giving both exits 1. New `DICOMConverter.invalidFrameNumberMessage`.
- **`dicom-convert` directory run exits 1 when any file failed** (P-CONVERT-EXIT), as `dicom-compress batch` does;
  it exited 0.
- **`dicom-compress decompress --syntax` / `batch --syntax` accept only native targets** (P-COMPRESS-SYNTAX):
  `explicit-le`, `implicit-le` and `deflate` (PS3.5 2026a A.2, A.1, A.5). Every compressed codec name (e.g.
  `--syntax jpeg2000`, which wrote encapsulated .91) and the retired `explicit-be` (PS3.5 A.3; the engine does not
  byte-swap values) are refused with exit 1 (an unknown name exited 64).
- **`dicom-compress info --json`** (P-COMPRESS-JSON) adds the PS3.6 2026a Table 6-1 keyword keys
  `TransferSyntaxUID`, `Rows`, `Columns`, `BitsAllocated`, `BitsStored`, `SamplesPerPixel`,
  `PhotometricInterpretation`, `NumberOfFrames` (a JSON number) and `LossyImageCompression`; the camelCase keys
  are deprecated and keep their values. Shared: `CompressionConsole.infoJSON` / new `infoKeywordFields`,
  `CompressionInfo.lossyImageCompression` (DICOMKit), so the Studio Workshop output matches.
- **`dicom-j2k --frame-number`** on info / validate / roi / benchmark / compare (P-J2K-FRAME): 1-based (PS3.3 2026a
  C.7.6.6); `--frame` (0-based) is deprecated (help, stderr note; both together exit 1). Output says
  "Frame number N" (info printed "Frame: 0 of N"); roi's Derivation Description names the Frame number.
- **`dicom-j2k --json`** (P-J2K-JSON) adds `TransferSyntaxUID` (info, validate) and `NumberOfFrames` (info), the
  PS3.6 2026a Table 6-1 keywords, and `frameNumber`; `transferSyntaxUID`, `totalFrames` and the 0-based `frame`
  are deprecated and keep their values.
- **`dicom-j2k transcode` refuses the `j2k-part2-*` targets** (P-J2K-PART2) with exit 1: .92 / .93 specify the
  JPEG 2000 Part 2 multiple component transformation extensions (PS3.5 2026a A.4.4) and the tool wrote a Part 1
  codestream under them; the engine already refused Part 2 encodes. `--help` lists them as refused.

### Changed — CLI P-items, webprint batch (approved 2026-10-01, DICOM 2026a)

- **`dicom-wado ups --change-state <uid>`** is the canonical name of Change Workitem State (PS3.18 2026a
  11.7); **`--update`** stays as a **deprecated** alias (help says so, stderr note on use; giving both is
  refused with exit 1) (P-WADO-UPS-UPDATE).
- **`dicom-wado ups --state SCHEDULED`** is now **refused with exit 1** (it only warned): PS3.18 2026a
  11.7.1.4 allows IN PROGRESS, COMPLETED or CANCELED, and PS3.4 2026a Table CC.1.1-2 answers a change to
  SCHEDULED with C303H (P-WADO-UPS-STATE).
- **`dicom-wado query` / `ups --search` / `ups --get` `--format dicom-json`** (new, additive) prints the
  PS3.18 2026a F.2 DICOM JSON Model the server returned (one top-level array, attributes in ascending tag
  order, Group Length removed); `--format json` is unchanged. DICOMWeb adds `QIDOOutputFormat.dicomJSON`,
  `DICOMJSONModelFormatter` and `DICOMwebClient.searchWorkitemsDICOMJSON(query:)` (P-QUERY-JSON for dicom-wado).
- **`dicom-print status` / `job` and `dicom-printscp status` `--format json`** add the PS3.6 2026a keyword
  keys `PrinterStatus`, `PrinterStatusInfo`, `PrinterName`, `Manufacturer`, `ManufacturerModelName`,
  `ExecutionStatus`, `ExecutionStatusInfo`, `CreationDate` (DA) and `CreationTime` (TM) beside the old
  keys, which keep their values and are deprecated (help and README say so) (P-PRINT-JSON).
- **Film Destination BIN_i** (P-BIN, closes D89): `DICOMNetwork.FilmDestination` carries every sorter bin
  of PS3.3 2026a Table C.13-1 (numbered from 1, no maximum, no leading zeros) through `.bin(n)`;
  `.bin1` / `.bin2` are deprecated. It is now a struct (`rawValue`, `init?(rawValue:)`, single-string
  `Codable`, `allCases` keep working; an exhaustive `switch` needs a `default`). `dicom-print send
  --film-destination` accepts any `bin-N` / `BIN_N`; the Print SCP accepts any BIN_i on N-CREATE.
- **`dicom-gateway hl7-to-dicom` / `fhir-to-dicom` require `--template`** (P-GATEWAY-SC, closes D104):
  without it the output claimed Secondary Capture Image Storage with no Image Pixel and no SC Image Module,
  both Mandatory in PS3.3 2026a Table A.8-1; it is now refused with exit 1, as is a template that claims
  an image Storage SOP Class but has no Pixel Data. README and examples updated.

### Changed — CLI P-items, pixel batch (approved 2026-10-01, DICOM 2026a)

- **`dicom-anon --profile` default is now `ps315`** (P-ANON-PROFILE), the PS3.15 2026a Basic Application Level
  Confidentiality Profile (every row of Table E.1-1), and **`--profile basic` is an alias of it** (with a stderr
  note saying so). The fixed attribute lists that `basic`, `clinical-trial` and `research` used to select are kept
  as `legacy-basic`, `legacy-clinical-trial` and `legacy-research`, deprecated: each use prints a stderr note.
  `clinical-trial`/`clinicaltrial` and `research` are not PS3.15 profile names; they still select the
  `legacy-*` lists, with the deprecation note. **Behaviour change:** a run without `--profile`, or with
  `--profile basic`, now records Patient Identity Removed (0012,0062) = YES and code 113100, replaces UIDs,
  removes private attributes, refuses `--keep`, needs `--retain-modified-dates` for `--shift-dates`, and refuses
  files that may have burned-in PHI unless `--clean-pixel-data` or `--allow-burned-in-phi` is given. Use
  `--profile legacy-basic` for the old output. On the 647-row Table E.1-1 fixture, the default and `basic` give
  the same result as `ps315`.
- **`dicom-anon --retain-dates` is deprecated** (P-ANON-RETAIN-DATES). It still selects the Full Dates Option, or
  the Modified Dates Option with `--shift-dates`. `--help` says "Deprecated", and each use prints a stderr note.
  Use `--retain-full-dates` or `--retain-modified-dates` (PS3.15 E.3.6).
- **DICOMKit `TemplateGenerator`** (D202): the `pipeline` and `anonymize` script templates now run
  `dicom-anon --profile ps315`. They had used the legacy `basic` list and `--profile strict`, a profile that does not
  exist. The sensitive-file step uses `--profile ps315 --clean-pixel-data`, the PS3.15 E.3.1 Clean Pixel Data
  Option. The `dicom-script` README examples now match the templates.
- **`dicom-image` refuses values the written VR cannot hold** (P-IMAGE-VR): a `--study-uid`/`--series-uid` that
  breaks PS3.5 2026a Section 9, a `--patient-id`/`--study-description`/`--series-description` or
  `--patient-name` component group over 64 characters or with a backslash, and a `--series-number`/
  `--instance-number` outside the IS range (PS3.5 Table 6.2-1) now exit 1 and write nothing. Before, they were
  written with a warning.
- **`dicom-pixedit` refuses out-of-range values** (P-PIXEDIT-RANGE): a `--fill-value` outside the Bits Stored /
  Pixel Representation range (PS3.3 2026a C.7.6.3.1) and an `--apply-window` `--window-width` below 1
  (C.11.2.1.2) now exit 1 and write nothing. Before, the fill value was clamped with a warning, a width in (0,1)
  was raised to 1, and a width of 0 or less went to the engine unchecked.
- **`dicom-video convert`/`batch` refuse values the Video IODs do not allow**:
  - P-VIDEO-MODALITY-ENUMERATED: a `--modality` other than ES, GM or XC for the chosen `--type` (PS3.3 2026a
    A.32.5.4.1 / A.32.6.4.1 / A.32.7.4.1).
  - P-VIDEO-SEX-ENUMERATED: a `--patient-sex` outside M/F/O (Table C.7-1), and a `--patient-birth-date` that is
    not DA (PS3.5 Table 6.2-1).
  - P-VIDEO-TS-REGISTERED: `--transfer-syntax` 1.2.840.10008.1.2.4.107.1 or .108.1, which are not registered in
    PS3.6 Table A-1.

  These now exit 1 before anything is written. Before, they were written with a warning. The CLI `--help`
  states the refusal; the shared `VideoConsole.Help` strings are unchanged.
- **`dicom-video --audio-channel-source` is repeatable** (P-AUDIO-SOURCE-PER-TRACK). Given once, it is the
  source of every audio track, as before. Given several times, the values apply one per audio track, in
  container order (PS3.3 2026a Table C.7-13: one (003A,0300) Item per channel, each with its own Channel Source
  Sequence (003A,0208)). A count that does not match the tracks exits 1. DICOMKit additions:
  `VideoWorkflow.Metadata.audioChannelSources`, where a track without an entry takes `audioChannelSource`;
  `VideoWorkflow.validateAudioChannelSources(for:metadata:)`, which `convert` and `runBatch` call;
  `VideoAudioChannel.channels(describing:sources:)`; and `VideoConsole.audioChannelSourceCountLine(given:tracks:)`.
  Nothing was deprecated.

### Changed — CLI P-items, derived batch (approved 2026-10-01, DICOM 2026a)

- **`dicom-viewer --frame`** (0-based index) is **deprecated**: it still works with a stderr note; use
  `--frame-number` (1-based, PS3.3 2026a Table 10-3). Giving both is now refused with exit 1 (was a
  usage error only when `--frame` was non-zero). Status line, thumbnails and errors say
  "Frame number N" (P-VIEWER-FRAME).
- **`dicom-3d mpr --planes oblique --oblique-normal x,y,z [--oblique-point x,y,z]`** (LPS mm; point
  defaults to the volume centre) now generates the oblique plane (it was skipped with a warning): one
  image sampled with PS3.3 2026a Equation C.7.6.2.1-1, nearest or trilinear, `--thickness` averages
  along the normal; `--format dcm` writes Image Orientation (Patient) / Image Position (Patient) /
  Pixel Spacing of the oblique plane (P-3D-OBLIQUE).
- **`dicom-3d mpr --interpolation cubic`** is **deprecated**: it uses linear and prints a note; help
  and README say that axial/sagittal/coronal planes are voxel-aligned and not resampled
  (P-3D-INTERPOLATION).
- **`dicom-3d volume`** is hidden from `--help`; it prints that volume rendering is not implemented
  (stderr) and exits 1 for any arguments (P-3D-VOLUME).
- **`dicom-measure pixel --frame-number N`** (1-based; PS3.3 2026a Table 10-3 "The first Frame shall be
  denoted as Frame number 1") is added; `--frame` (0-based index) is **deprecated** (stderr note) and
  giving both is refused with exit 1. Text output labels "Frame number N"; JSON adds `frame_number` and
  keeps `frame` (0-based, deprecated) (P-MEASURE-FRAME).
- **`dicom-measure --unit um`** (micrometre, UCUM `um` / `um2`, PS3.16 2026a CID 7460 / CID 7461) is
  added. Text output prints the UCUM code with the display symbol in parentheses when it differs
  (`2.0 mm2 (mm²)`, `90.0 deg (°)`, `[hnsf'U] (HU)`); distances in pixels carry UCUM `{pixels}` as PS3.16
  TIDs write it. JSON `unit` / `area_unit` (display symbols) are **deprecated** and unchanged;
  `unit_ucum` / `area_unit_ucum` carry the code (P-MEASURE-UNIT).
- **`dicom-report --style`** names the styling preset (default, cardiology, radiology, oncology);
  `--template` is a **deprecated** alias (stderr note; giving both is refused). An unknown value is
  now refused with exit 1 listing the valid styles (was a silent fallback to `default`); a value that
  looks like a template number (`1500`, `TID 1500`) is told that SR templates are PS3.16 2026a TIDs,
  read from the document's Content Template Sequence (0040,A504) (P-REPORT-TEMPLATE).
- **`dicom-report --include-summary` / `--no-include-summary`** now controls the summary sections
  (Impressions, Recommendations) in text, HTML and Markdown (it was parsed but never read); the content
  tree is always rendered. JSON adds `include_summary` (P-REPORT-SUMMARY).

### Changed — CLI P-items, file batch (approved 2026-10-01, DICOM 2026a)

- **`dicom-json --no-sort-keys`** and **`dicom-xml --no-keywords`** are deprecated (P-JSON-NO-SORT-KEYS,
  P-XML-NO-KEYWORDS): both still work, `--help` says "Deprecated", and using them prints a one-line stderr
  warning, because their output breaks PS3.18 2026a F.2.2 (ascending tag order) and PS3.19 2026a
  Table A.1.5-2 (keyword required). They will be removed in the next major version.
- **`dicom-diff` exit status** (P-DIFF-1): 0 identical, 1 different, **2** when a file is missing or cannot
  be read or parsed as DICOM, or the comparison fails (the `diff`/`cmp` convention; such errors exited 1, a
  missing file 64). The error goes to stderr; 64 remains the usage error. `--help` and README document it.
- **`dicom-dcmdir create --file-set-id`** refuses (exit 1, message citing PS3.10 2026a 8.1/8.5 and PS3.3
  2026a Table F.3-2) a File-set ID longer than 16 characters or with characters other than A-Z, 0-9 and `_`;
  it used to warn and write it (P-DCMDIR-FSID). No override flag.
- **`dicom-dcmdir create --profile`**: the spellings STD-GEN-DVD, STD-GEN-USB, STD-GEN-SEC, STD-CTMR-XXXX and
  STD-US-XXXX are deprecated (not PS3.11 identifiers). They still work and print a one-line stderr note naming
  the identifier written: STD-GEN-DVD-JPEG (PS3.11 2026a Table H.1-1), STD-GEN-USB-JPEG (J.1-1),
  STD-GEN-SEC-CD (D.1-1), STD-CTMR-CD (E.1-1), STD-US-ID-SF-CDR (C.1-1) (P-DCMDIR-PROFILE). The tests that
  used the deprecated `DICOMDIRProfile` constants use the -JPEG constants.
- **`dicom-uid lookup`** prints the UID Type of PS3.6 2026a Table A-1 verbatim ("Well-known SOP Instance",
  "Application Context Name", "DICOM UIDs as a Coding Scheme" instead of "Well-Known UID", "Application
  Context", "Coding Scheme"; 21 UIDs change) in text output, and `--json` adds a **`uidType`** key with that
  text. The JSON `type` key keeps the former wording and is deprecated (P-UID-TYPE). New DICOMKit API:
  `UIDManager.tableA1UIDType(of:)` / `tableA1UIDType(_:uid:)`, `UIDManager.dicomUIDsAsCodingSchemeUID`, and
  `UIDConsole.lookupEntryJSON(uid:name:type:uidType:)` / `listingJSON(entries:)` overloads with `uidType`.
- **`dicom-study`** output carries the PS3.6 2026a Table 6-1 keywords (P-STUDY-1): `summary --format csv` appends
  the columns `StudyInstanceUID,NumberOfStudyRelatedSeries,NumberOfStudyRelatedInstances` (the former `StudyUID`,
  `SeriesCount`, `InstanceCount` stay in place, deprecated); `stats --format json` adds `StudyInstanceUID`,
  `NumberOfStudyRelatedSeries`, `NumberOfStudyRelatedInstances`, `ModalitiesInStudy` next to the deprecated
  `studyUID`, `seriesCount`, `totalInstances`; `compare --format json` adds `study1` / `study2` objects with those
  keywords and `SeriesInstanceUID` in each `seriesDifferences` item (former keys kept, deprecated). Implemented in
  DICOMKit `Statistics` / `StudyComparison` / `SeriesDifference` encoding (decoding unchanged) and
  `StudyReport.renderSummary`.
- **`dicom-archive`** JSON carries the PS3.6 2026a Table 6-1 keywords (P-ARCHIVE-1): every study in
  `archive_index.json` (and `list --format json`) gets `ModalitiesInStudy` (0008,0061), the distinct series
  Modality values, next to the deprecated study-level `modality` (first instance's Modality); `query --format json`
  adds `ModalitiesInStudy`, `NumberOfStudyRelatedSeries`, `NumberOfStudyRelatedInstances` (PS3.4 Table C.6-5) next
  to the deprecated `modality`, `seriesCount`, `imageCount`. Indexes written before still load (the key is
  computed, not read). New DICOMKit API: `ArchiveStudy.modalitiesInStudy`.
- **`dicom-export` frame numbers** (P-EXPORT-1): new 1-based `single --frame-number` and `animate
  --start-frame-number` / `--end-frame-number` (PS3.3 2026a Table 10-3 "The first Frame shall be denoted as Frame
  number 1"; C.7.6.6). The 0-based `--frame`, `--start-frame`, `--end-frame` keep their meaning, say "deprecated:
  0-based index" in `--help` and print a stderr note; a 0-based and a 1-based option together exit 1. An
  out-of-range Frame number is reported as "Frame number N does not exist … numbered 1 to M".
- **`dicom-export bulk --organize-by patient|study|series`** names the patient folder from Patient ID (0010,0020),
  followed by `@` and Issuer of Patient ID (0010,0021) when present (PS3.3 2026a Table C.7-1 / Table 10-18; the
  Patient level unique key of PS3.4 Table C.6-1), instead of Patient's Name (P-EXPORT-2). **Behaviour change:**
  existing output trees organized by name are not reused. New DICOMKit API:
  `DICOMImageExporter.patientFolderName(patientID:issuerOfPatientID:)` and
  `buildOrganizedPath(baseOutput:scheme:patientID:issuerOfPatientID:studyUID:seriesUID:filename:)`; the
  `patientName:` variant is deprecated.
- **`dicom-export contact-sheet --apply-window`** and **`bulk --apply-window`** are deprecated (P-EXPORT-3): they
  have no effect (the file's VOI is always applied); `--help` says so and use prints a stderr warning.
- **`dicom-split --frame-numbers`** (P-SPLIT-1): new option taking Frame numbers, numbered from 1 (PS3.3 2026a
  C.7.6.16.1.2 "Frames are implicitly numbered starting from 1"; Table 10-3), as a list with ranges (`1,3,5-10`).
  The 0-based `--frames` keeps its meaning, says "deprecated: 0-based index" in `--help` and prints a stderr note;
  both together exit 1; Frame number 0 is refused. Verbose progress and errors of the shared FrameSplitter now say
  "Frame number N" (1-based) instead of "frame <index>", the banner prints "Frame numbers: …", and the
  concatenation warning names both options. New DICOMKit API: `SplitConsole.parseFrameNumberSelection(_:)`,
  `framesDeprecatedLine`, `framesAndFrameNumbersConflictMessage`, `headerLines(…, frameNumbers:)`.
  SplitMergeWorkshopCLIParityTests ignore the CLI-only `--frames` deprecation line until the Workshop prints it.

### Fixed — dicom-viewer grayscale display verified against DICOM 2026a (2026-10-01)

- **`dicom-viewer`** applies the window with the VOI LUT Function of the file (PS3.3 Table C.11-2b,
  C.11.2.1.3: SIGMOID and LINEAR_EXACT were ignored) and with LINEAR when it is absent (C.11.2.1.2.1;
  the LINEAR_EXACT formula was used for every window); the auto window is computed on rescaled values
  (it used stored values, so CT images with an intercept were mis-windowed); rescale is read per frame;
  MONOCHROME1 images show the minimum as white (C.7.6.3.1.2; they were shown inverted).
- **New options `--voi-lut-function`** (LINEAR, LINEAR_EXACT, SIGMOID) and **`--frame-number`** (1-based
  DICOM Frame Number; `--frame` stays the 0-based index). `--window-width` must be >= 1 for LINEAR and
  > 0 for LINEAR_EXACT / SIGMOID; a frame past Number of Frames is reported as such.
- **`--show-overlay`** draws the overlay planes (60xx) at their 1-based Overlay Origin (Table C.9-2);
  it only printed a status line. Thumbnail and volume grids apply the window, inversion and overlays too,
  and label frames with Frame Numbers from 1 (they started at 0).
- **`--show-info`** labels are the PS3.6 names (Patient's Name, Patient ID, Patient's Sex, Study
  Description, Study Date, Rows x Columns, Number of Frames, Window Center, Window Width); "W/L" printed
  the centre first and truncated decimals.

### Fixed — dicom-3d volume geometry, plane names and DICOM MPR output verified against DICOM 2026a (2026-10-01)

- **`dicom-3d` volume loading** read Pixel Spacing (0028,0030) in the wrong order: value 1 is the
  spacing between rows and value 2 the spacing between columns (PS3.3 Table C.7-10), so non-square pixels
  were stretched in every output. Voxel positions now follow Equation C.7.6.2.1-1 along the slice normal
  (the slice offset was added to z only), slice spacing is the mean distance along the normal, one slice
  uses Spacing Between Slices before Slice Thickness, Rescale Slope/Intercept are read per slice, slices
  with different Frame of Reference UIDs (C.7.4.1.1.1), orientations or matrix sizes are rejected, and
  Enhanced multi-frame input is placed by its Plane Position / Plane Orientation / Pixel Measures
  functional groups (a classic multi-frame image is rejected instead of read as one slice).
- **`axial`, `sagittal`, `coronal`** (mpr `--planes`, mip/minip/average `--direction`) are the patient
  planes of PS3.3 C.7.6.2.1.1 for any acquisition orientation (they were the volume's index planes);
  sagittal and coronal images have the head at the top. minip and average now reject an unknown direction
  (it silently became axial).
- **`mpr --format dcm`** writes a derived DICOM series (it wrote PNG files): Image Type DERIVED\SECONDARY
  (MR Value 3 MPR), Derivation Code Sequence (113072, DCM, "Multiplanar reformatting") (CID 7203),
  Derivation Description, Source Image Sequence with Purpose of Reference 121322, new Series/SOP Instance
  UIDs, and the plane's Image Position/Orientation (Patient), Pixel Spacing and Slice Thickness.
  `mpr --thickness` now averages slabs and `mip/minip --thickness` limits the projection to a centred
  slab (both were ignored); `oblique` prints a warning instead of being skipped silently; a single
  `--planes` output directory no longer writes its files into the parent directory.
- **`--window-center/--window-width`** use the LINEAR VOI LUT function of PS3.3 C.11.2.1.2.1 (width must
  be >= 1 and both must be given); MONOCHROME1 volumes are shown inverted (C.7.6.3.1.2).
- **`export`**: the NIfTI sform is the RAS form of the DICOM LPS affine (it ignored orientation and the
  LPS→RAS sign change) and scl_slope/scl_inter are 1/0 because voxels are already rescaled (they were
  applied twice); MetaImage TransformMatrix and AnatomicalOrientation come from Image Orientation (Patient).
- **`encode-volume`** orders the slices along the normal before encoding; **`inspect`** labels are the
  PS3.6 names (Patient's Name, Study Instance UID, Series Description).

### Fixed — dicom-ai SR, enhance and GSPS output verified against DICOM 2026a (2026-10-01)

- **`dicom-ai classify|detect --format dicom-sr`** writes a PS3.16 TID 1500 Measurement Report built by
  `MeasurementReportBuilder` instead of a hand-built Comprehensive SR whose title codes (129007 / 129008,
  DCM) are not in PS3.16 Table D-1, whose confidence used (121072, DCM), which is "Impressions" (retired),
  and whose image reference used (121191, DCM) "Referenced Segment". The report has the title
  (126000, DCM, "Imaging Measurement Report") (CID 7021), an Image Library with the source image, an
  Imaging Measurements container carrying TID 4019 Algorithm Name (111001) and Algorithm Version (111003),
  and one Measurement Group per prediction/detection (Tracking Identifier / UID, the label as TEXT
  (121071, DCM, "Finding"), and NUM (111012, DCM, "Certainty of Finding") in (%, UCUM, "Percent") with
  value 0-100, was 0-1 labelled percent) inferred from the source IMAGE or, for a detection, from the
  bounding-box SCOORD POLYLINE selected from it. The root carries Content Template Sequence DCMR/1500
  (PS3.3 Table C.18.8-1); the Type 2 Patient, General Study and General Equipment attributes are written.
  The output is now a PS3.10 file (preamble + File Meta Information), as is the `enhance` output.
- **New option `--algorithm-version`** (classify, detect, segment, enhance; used by dicom-sr): the Algorithm Version written
  in the SR (TID 4019 row 2, M). Default: the CoreML model's version metadata, else `unknown`.
- **`dicom-ai enhance`** writes a derived image of the source SOP Class that keeps the source's other
  attributes (it kept 12), with Image Type DERIVED\SECONDARY (PS3.3 C.7.6.1.1.2), a new SOP Instance and
  Series Instance UID, Derivation Description and a Source Image Sequence Item with Purpose of Reference
  (121322, DCM, "Source image for image processing operation") (CID 7202); a multi-frame source keeps only
  the processed frame.
- **`dicom-ai segment`** writes the model file name as Segment Algorithm Name (was the fixed text
  "AI Model"). The GSPS generator (no subcommand calls it yet) now goes through
  `GrayscalePresentationStateBuilder`. 6 new tests in `dicom-aiTests`.

### Fixed — dicom-report SR rendering verified against DICOM 2026a (2026-10-01)

- **dicom-report** prints a value for every Value Type of PS3.3 Table C.17.3-7: DATE, TIME, UIDREF, PNAME,
  COMPOSITE, WAVEFORM (with channels), SCOORD/SCOORD3D (graphic type and points), TCOORD (range type and
  references) and TABLE printed `[Content]` before. CODE values print as `(CV, CSD, "CM")` (PS3.16 6.1;
  Long/URN Code Value when Code Value is absent, Table 8.8-1a); NUM prints whole numbers without `.0` and
  keeps the Code Meaning of the Measurement Units Code Sequence. Children of NUM, CODE, TCOORD and every
  other Value Type are rendered (they were dropped unless the parent was a CONTAINER), in all formats and in
  the measurement / referenced-image / section searches. The header shows Completion Flag, Verification
  Flag, Preliminary Flag (Table C.17-2) and the root Content Template (`TID 1500 Measurement Report (DCMR)`,
  Table C.18.8-1); the text format also shows the SR SOP Class. JSON adds `value_type`, `completion_flag`,
  `verification_flag`, `preliminary_flag` and `content_template` (additive). HTML escapes concept names and
  values. A file whose root Value Type is not CONTAINER (e.g. an image) is refused with "Not a Structured
  Report. SOP Class UID indicates: <PS3.6 Table A-1 name>" instead of producing an empty report. New
  `dicom-reportTests` (10 tests).

### Fixed — dicom-measure calibration, coordinates and units verified against DICOM 2026a (2026-10-01)

- **dicom-measure** takes the pixel spacing from, in order, Pixel Spacing (0028,0030), the frame's Pixel
  Measures Sequence (0028,9110) (PS3.3 C.7.6.16.2.1), the Sequence of Ultrasound Regions (0018,6011) region
  in cm holding the points (C.8.5.5), Imager Pixel Spacing (0018,1164) (front plane of the detector housing,
  Tables C.8-2 / C.8-71) and Nominal Scanned Pixel Spacing (0018,2010) (Table C.8-25). An image with none of
  them is measured in pixels (`px`, `px²`) with a warning, instead of being reported in mm at an assumed
  1.0 mm per pixel. Results carry `spacing_source` (PS3.6 keyword), `spacing_mm` and `spacing_note`; JSON adds
  `unit_ucum` / `area_unit_ucum` (PS3.16 CID 7460, 7461, 7183 `deg`, 7181 `[hnsf'U]`) and ROI `value_unit`.
- `angle` scales the vectors by column and row spacing, so the angle is correct when they differ.
- Pixel values come from `PixelData` (Bits Stored / High Bit masking and sign extension, PS3.5 8.1.1;
  compressed transfer syntaxes decoded), go through the Modality LUT Sequence when present (it was ignored)
  or the frame's Rescale Slope/Intercept; images with Samples per Pixel ≠ 1 are refused.
- `hu` labels a value HU only when Rescale Type (or Modality LUT Type) is HU, or absent on a CT image (PS3.3
  Table C.8-3); otherwise the value keeps its Rescale Type as unit with a warning. `pixel` reports that unit.
- Coordinates follow PS3.3 Table C.18.6-1 (0,0 = top-left corner of the top-left pixel): a point samples pixel
  floor(x),floor(y) (negative coordinates are out of bounds), ROIs hold the pixels whose centres lie inside.
- `--frame` is checked against Number of Frames (0028,0008); the help says it is 0-based (Frame number 1 = 0).
  Verbose diagnostics go to stderr. New test target `dicom-measureTests` (17 tests).

### Fixed — dicom-convert option contract verified against DICOM 2026a (2026-10-01)

- **dicom-convert** `--transfer-syntax` also accepts the PS3.6 Table A-1 keywords of the catalog targets it
  did not know (DeflatedExplicitVRLittleEndian, JPEGBaseline8Bit, JPEGExtended12Bit, JPEG2000MCLossless,
  JPEG2000MC, JPEGXLJPEGRecompression, HTJ2KLosslessRPCL); the help says that `JPEG2000Lossless`,
  `HTJ2KLossless` and `JPEGXLLossless` keep their catalog meaning (reversible encode into .91 / .203 / .112,
  not the Table A-1 .90 / .201 / .110). **Behaviour change:** `--window-width` below 1 is refused (PS3.3
  C.11.2.1.2.1), as are `--quality` outside 1-100 and a negative `--frame`. README: target list, 0-based
  frames, real exit codes, `--strip-private` described as top-level private elements (not de-identification),
  the non-existent "export all frames" example removed. New test target `dicom-convertTests` (8 tests).

### Fixed — dicom-j2k DICOM boundary verified against DICOM 2026a (2026-10-01)

- **dicom-j2k** finds each frame through the Extended / Basic Offset Table (or SOC-delimited fragments),
  so frames that span several fragments are read instead of failing (PS3.5 A.4.4). `transcode`, `reduce`
  and `roi` set Photometric Interpretation from the written codestream (YBR_RCT / YBR_ICT when the
  multi-component transform is applied, RGB when a YBR_RCT/ICT source is re-encoded without one) and
  Planar Configuration 0 (PS3.5 8.2.4 / 8.2.14); `--quality` now reaches the encoder (it was ignored).
  A lossy `transcode` sets Lossy Image Compression "01", appends Ratio / Method (ISO_15444_1 /
  ISO_15444_15), Derivation Description, Image Type DERIVED and a new SOP Instance UID (also in
  (0002,0003)) (PS3.3 C.7.6.1.1.5). `roi` output is a derived single-frame image: new SOP Instance UID,
  DERIVED, Number of Frames 1, the kept Per-frame Functional Groups item and the Image Position (Patient)
  of the crop origin; a negative `--region` origin is refused. `reduce`/`roi` keep the HTJ2K block coder
  for HTJ2K sources; for `.202` the encoder is asked for RPCL and enough levels, `reduce --levels` below the
  PS3.5 10.18.1 minimum is refused, and a warning names any 10.18.1 requirement the codestream misses.
  File Meta Group Length is recomputed after a meta change. `compare` decodes both files through the
  shared pixel pipeline (16-bit native and colour images compared sample by sample). **Behaviour change:**
  `validate` exits 2 (as documented) when the file cannot be read or is not JPEG 2000. Help/README: PS3.6
  Table A-1 transfer syntax names, `reduce` described as a lossless re-encode, `--backends` example removed.

### Fixed — dicom-pdf verified against DICOM 2026a (2026-10-01)

- **dicom-pdf** writes Encapsulated Document Length (0042,0015) with the unpadded length and cuts the
  extracted document to it, so an odd-length PDF/CDA comes back byte for byte (it gained a trailing 0x00;
  PS3.3 Table C.24-2), and writes Specific Character Set (0008,0005) "ISO_IR 192" when a text value is not
  ASCII (Type 1C, Tables C.12-1 / C.12-5). New `--conversion-type` (Conversion Type (0008,0064), the 8
  Table C.8-24 Defined Terms, default WSD), `--burned-in-annotation YES|NO` (0028,0301, default YES) and
  `--hl7-instance-identifier` (0040,E001, Type 1C for CDA): a CDA document could not be encapsulated at all;
  the identifier is now read from /ClinicalDocument/id unless given. Help/README: "Patient's Name", M3D
  required for STL/OBJ/MTL (A.85.x.4.3), corrected standard references (A.45.1, A.85, C.24.1/C.24.2,
  PS3.5 A.2). New test target `dicom-pdfTests` (7 tests).

### Fixed — dicom-video option contract verified against DICOM 2026a (2026-10-01)

- **dicom-video** `convert` / `batch` warn on stderr (the object is still written) when an option value
  yields a non-conformant object: `--modality` other than the IOD's ES / GM / XC (PS3.3 A.32.5.4.1,
  A.32.6.4.1, A.32.7.4.1), `--patient-sex` outside M / F / O (Table C.7-1), a `--patient-birth-date` that is
  not DA (it is written empty), and `--transfer-syntax 1.2.840.10008.1.2.4.107.1` / `.108.1`, which PS3.6
  Table A-1 does not register. `VideoConsole.Help` (strings only): "Patient's Name", the modality each
  `--type` requires, the transfer syntaxes accepted, and that MOV and raw elementary streams are probed but
  not converted. README lists the warnings, `--audio-channel-source` and the A.32.6/A.32.7 IODs.
  `OptionConformanceTests` (8 tests) in `dicom-videoTests`.

### Fixed — dicom-image and dicom-pixedit verified against DICOM 2026a (2026-10-01)

- **dicom-image** writes Media Storage SOP Instance UID (0002,0003) equal to SOP Instance UID (0008,0018)
  (PS3.10 Table 7.1-1; the engine minted two different UIDs) and Specific Character Set (0008,0005)
  "ISO_IR 192" when a name or description is not ASCII (Type 1C, PS3.3 Table C.12-1 / C.12-5). New
  `--conversion-type` sets Conversion Type (0008,0064) to a Table C.8-24 Defined Term (DV, DI, DF, WSD, SD,
  SI, DRW, SYN; default WSD as before). A UID that breaks PS3.5 9.1, LO/PN values over 64 characters and
  numbers outside the IS range now warn on stderr (still written). Help and README name the SOP Class
  "Secondary Capture Image Storage", the attribute tags, and list the Table A.8-1 modules; the README no
  longer says DPI maps to Pixel Spacing (it is Nominal Scanned Pixel Spacing (0018,2010)). New test target
  `dicom-imageTests`.
- **dicom-pixedit** output is now a Derived Image (PS3.3 C.7.6.1.1.2): new SOP Instance UID (and
  (0002,0003)), Image Type Value 1 DERIVED, Derivation Description (0008,2111) and a Source Image Sequence
  (0008,2112) item referencing the input (Purpose of Reference DCM 121322, CID 7202); Implementation Class
  UID / Version Name name DICOMKit; stale Smallest/Largest (Image) Pixel Value attributes are removed; a crop
  moves Image Position (Patient) (C.7.6.2.1.1). `--window-center` / `--window-width` are taken in Modality
  LUT output units (e.g. HU; C.11.2.1.2) — they were applied to stored values, so a CT window ignored
  Rescale Intercept; a width below 1 warns and uses 1. `--fill-value` outside the Bits Stored / Pixel
  Representation range is clamped with a warning (values above Bits Stored were written). New test target
  `dicom-pixeditTests`.

### Fixed — dicom-anon verified against DICOM 2026a (2026-10-01)

- **dicom-anon** `--profile ps315` (PS3.15 Basic Application Level Confidentiality Profile) now applies
  `--remove` / `--replace` (they were silently ignored on that path), writes a per-attribute `--audit-log`
  (the log held only its header), and writes Media Storage SOP Instance UID (0002,0003) equal to the replaced
  SOP Instance UID (0008,0018) (PS3.10 7.1; the original UID stayed in the meta header, all profiles).
  `--dry-run` / `--verbose` list each changed attribute with its PS3.6 name and PS3.15 Table E.1-1a code.
  New `--retain-full-dates` and `--retain-modified-dates` name the two Retain Longitudinal Temporal
  Information Options (E.3.6); conflicting or ignored combinations are refused (exit 1): the Option flags
  with a legacy profile, `--shift-dates` on ps315 without a dates Option, Full with Modified Dates,
  `--regenerate-uids` with `--retain-uids`, `--keep` on ps315. `--remove` / `--replace` / `--keep` accept
  any PS3.6 keyword (only 11 were recognised). Help, README and a stderr note state that the legacy
  `basic`, `clinical-trial` and `research` profiles are not PS3.15 (basic matches 11 of 647 Table E.1-1
  data-set rows) and that `--clean-descriptors` keeps descriptors uncleaned. New test target `dicom-anonTests`.

### Fixed — dicom-dump, dicom-info, dicom-tags verified against DICOM 2026a (2026-10-01)

- **dicom-tags** `--set` now writes the PS3.6 dictionary VR and refuses, before anything is
  written (exit 1), a value outside the PS3.5 2026a Table 6.2-1 limits of that VR (length,
  character repertoire, IS range, PN component groups). US, SS, UL, SL, FL and FD values are
  encoded as binary numbers (`--set Rows=512` used to write the text "512 " under VR US); AT,
  OB, OD, OF, OL, OV, OW, SQ, SV, UV and UN are refused. `--set`, `--delete` and `--tags` refuse
  File Meta Information tags (group 0002, PS3.10 7.1 — setting TransferSyntaxUID used to put
  (0002,0010) into the Data Set and make the file unreadable), Item/delimiter tags (FFFE,xxxx)
  and the groups PS3.5 7.8.1 says shall not be used. New `dicom-tagsTests`.
- **dicom-info** `--tag` also accepts a PS3.6 keyword exactly (the documented
  `--tag PatientName --tag StudyDate` selected nothing). New `dicom-infoTests`.
- **dicom-dump** `--tag` / `--highlight` accept a PS3.6 keyword; a negative `--length` (trap)
  and `--bytes-per-line 0` (endless loop) are rejected. README: `--annotate` is off by default.
  New `dicom-dumpTests`.

### Fixed — dicom-diff, dicom-split, dicom-merge verified against DICOM 2026a (2026-10-01)

- **dicom-diff** `--ignore-tag` also accepts the `(gggg,eeee)` Tag notation the report itself prints (PS3.6
  2026a Table 6-1) and the 8-digit `ggggeeee` form; `gggg,eeee` and PS3.6 keywords work as before. Help and
  README state that `--tolerance` and the pixel statistics are per byte of Pixel Data (7FE0,0010), not per
  sample value, that `--ignore-private` (odd groups, PS3.5 7.1) filters top-level elements only, that the File
  Meta Information (group 0002) is not compared, and that exit 1 also means an unreadable file. New test target
  `dicom-diffTests`.
- **dicom-split** help and README: `--frames` and `{number}` are documented as 0-based indices (index 0 is
  Frame number 1, PS3.3 2026a C.7.6.16.1.2); the README called 0-based numbering "the DICOM convention". The
  discussion names the SOP Classes as in PS3.6 Table A-1 (e.g. Positron Emission Tomography Image Storage,
  X-Ray Radiofluoroscopic Image Storage) and the Shared / Per-Frame Functional Groups Sequences; `--split-by`,
  `--instance-number`, `--pattern`, `--new-series` name Stack ID, Temporal Position Index, In-Stack Position
  Number, Instance Number and Series Instance UID with their tags. README lists all 18 options and the real exit
  codes (64 for usage errors). Behaviour unchanged. New test target `dicom-splitTests`.
- **dicom-merge** help and README: the PS3.6 2026a Table A-1 SOP Class of every `--format` value is listed;
  "Legacy Converted Enhanced MR (Sup 157)" is cited as PS3.3 A.71; `--sort-by`, `--make-stacks`,
  `--temporal-position` (now also naming Temporal Position Identifier), `--level` and `--validate` name their
  attributes. The stale README (Enhanced output "not yet implemented", 4 of 12 formats, "Samples Per Pixel",
  exit 64 for inconsistent inputs, which exit 1) now matches the tool. Behaviour unchanged. New test target
  `dicom-mergeTests`.

### Fixed — dicom-dcmdir, dicom-uid, dicom-validate verified against DICOM 2026a (2026-10-01)

- **dicom-dcmdir** `validate` checks the File-set ID (0-16 characters, PS3.10 8.1) and every Referenced
  File ID (0004,1500) (1-8 components of 1-8 characters, PS3.10 8.2; A-Z, 0-9, _ only, 8.5; each File
  referenced by at most one record, PS3.3 Table F.3-3) and exits 1 on a violation; every failure names
  its clause (PS3.10 8.x, PS3.3 Tables F.3-2, F.3-3, F.4-1, PS3.5 9.1). `--check-files` now looks each
  File ID up on disk (PS3.10 8.6) instead of only rejecting empty paths. Read/validation errors print
  the error text instead of "The operation couldn't be completed". `create` derives the default
  File-set ID from the directory name upper-cased with other characters as `_`, cut to 16 (was the raw
  name, e.g. lowercase), warns on an explicit `--file-set-id` outside 8.1/8.5, and warns when the
  indexed file names are not valid File IDs. README: SPACE is not allowed in a File-set ID, File ID
  example without `.dcm`, the 2026a File-set Consistency Flag text. New `dicom-dcmdirTests`.

- **dicom-uid** `generate` / `regenerate` reject a `--root` that is not a PS3.5 9.1 UID (it crashed the
  generator) or that leaves no room for the unique suffix within 64 characters (the generator cut the
  suffix off and returned the same UID every time); new `generate --uuid` makes UUID derived UIDs
  `2.25.<decimal UUID>` (PS3.5 B.2); `lookup --type` filters every PS3.6 Table A-1 UID Type
  (meta-sop-class, well-known-sop-instance, ldap-oid, coding-scheme, application-context-name,
  service-class, application-hosting-model, mapping-resource, synchronization-frame-of-reference added
  to transfer-syntax and sop-class). Help names the default root and PS3.5 9.1 / 9.2.2, and states what
  `regenerate` replaces (top-level UI values that are not Table A-1 UIDs; sequence items are not
  remapped). README synced. New `dicom-uidTests`.

- **dicom-validate** `--iod` also takes the PS3.6 Table A-1 keyword (any case) or SOP Class UID, e.g.
  `ComputedRadiographyImageStorage`, `UltrasoundImageStorage`, `GrayscaleSoftcopyPresentationStateStorage`,
  `KeyObjectSelectionDocumentStorage` (these used to report "IOD validation not implemented"), and `US`.
  `--level` help says what level 2 checks (VR against PS3.6, DA / TM / UI forms of PS3.5 Table 6.2-1 and
  9.1; no VM or length checks) instead of "Tags/VR/VM". README: Table A-1 IOD names, Pseudo-Color and
  Key Object Selection listed, no VM / deprecated-tag claims. New `dicom-validateTests`.

### Fixed — dicom-study, dicom-archive, dicom-export verified against DICOM 2026a (2026-10-01)

- **dicom-study** help names what `organize --pattern descriptive` is built from (Patient's Name,
  Study Description, Study Instance UID, Series Number, Modality, Series Description), the grouping keys
  (Study / Series Instance UID, the PS3.4 C.6.1.1 unique keys), the count options as Number of Study
  Related Series / Number of Series Related Instances, and the Instance Number (0020,0013) gap check as a
  heuristic (PS3.3 Table C.7-9 does not require consecutive numbers). README synced. New `dicom-studyTests`.
- **dicom-archive** `query` warns when `--study-date` is a range (PS3.4 C.2.2.2.5) or not YYYYMMDD, and
  `query` / `export` warn when a UID option holds a backslash UID list (C.2.2.2.2): the archive matches
  these exactly, so such values matched nothing in silence. Help names the PS3.6 attribute each key
  matches, that `--modality` matches any series of the study (Modalities in Study semantics), and that
  wild cards are case-insensitive for Patient ID too (tool-specific; C.2.2.2.4 is case-sensitive for LO).
  README synced (study `modality` is the first instance's). New `dicom-archiveTests`.
- **dicom-export** `contact-sheet` and `animate` render through `DICOMImageExporter.renderFrameForExport`,
  like `single` and `bulk` (PS3.4 N.2: Modality LUT, the file's VOI in modality units, INVERSE for
  MONOCHROME1). `contact-sheet --apply-window` applied Window Center/Width in HU to stored values (wrong
  whenever Rescale Intercept != 0) and by default ignored the file's VOI; `animate --apply-window` used a
  stored-unit window (wrong for slope != 1, no Modality LUT Sequence) and by default a per-frame auto
  window. `contact-sheet --apply-window` is now a no-op, as `bulk --apply-window` already was.
- **dicom-export** `animate` without `--fps` uses the file's Recommended Display Frame Rate (0008,2144), else
  Cine Rate (0018,0040), else 1000 / Frame Time (0018,1063) (PS3.3 Table C.7-13), else 10 (was always 10).
- **dicom-export** warns on stderr when an exported file has Burned In Annotation (0028,0301) YES (PS3.3
  Table C.7-9). Help: frames are 0-based indexes (DICOM frame number - 1); `--window-center/-width` are
  Window Center/Width in modality units; `--exif-fields` lists its 9 PS3.6 keywords; `--organize-by`
  names Patient's Name / Study / Series Instance UID. README synced. New `dicom-exportTests`.

### Fixed — dicom-json verified against DICOM 2026a (2026-10-01)

- **dicom-json**: an attribute with an empty Value Field is now kept as `{"vr": ...}` by default,
  as PS3.18 2026a F.2.5 requires ("shall be preserved"). `--include-empty` still parses, and the
  new `--no-include-empty` drops such attributes as the old default did. `--filter-tag` also
  accepts the eight-character attribute name of F.2.2 (`00100020`) and `(0010,0020)`. Help and
  README now say that `--no-sort-keys` output breaks the F.2.2 ascending order, that
  `--inline-threshold` acts only with `--bulk-data-url` (URI `<url>/<GGGGEEEE>`), and that
  `--metadata-only` omits only Pixel Data (7FE0,0010), so it is not the PS3.18 Metadata
  resource. The README rows for the removed `--format` / `--stream` options are deleted.
  Tests: `dicom-jsonTests`.

### Fixed — dicom-xml verified against DICOM 2026a (2026-10-01)

- **dicom-xml**: an attribute with an empty Value Field is now kept by default as a
  `DicomAttribute` without `Value` (PS3.19 2026a Table A.1.5-2: a DicomAttribute "corresponding
  to each DICOM Attribute"). `--include-empty` still parses, and the new `--no-include-empty`
  drops such attributes. `--filter-tag` also accepts `GGGGEEEE` and `(GGGG,EEEE)`. Help and
  README now say that `--no-keywords` output breaks Table A.1.5-2 (the keyword is required for
  PS3.6 elements), that a `BulkData uri` belongs to a WADO-RS Retrieve Metadata response, and
  that `--metadata-only` omits only Pixel Data (7FE0,0010). Tests: `dicom-xmlTests`.

### Fixed — dicom-gateway verified against DICOM 2026a (2026-10-01)

- **dicom-gateway** `hl7-to-dicom` / `fhir-to-dicom`: Patient's Name follows the PN component
  order of PS3.5 2026a 6.2.1 for every HL7 XPN length (a 4-component XPN put the suffix in the
  prefix slot) and FHIR further given names go to the middle-name component; PID-3 writes the
  CX ID to Patient ID and the assigning authority to Issuer of Patient ID (0010,0021); ORC-2 /
  OBR-3 use the EI identifier; DA is written only as a full YYYYMMDD (a partial date gives the
  empty Type 2 value) and TM keeps HH/HHMM/fractions without the time-zone suffix; Study
  Instance UIDs are checked against PS3.5 9.1; an Accession Number over 16 characters (SH)
  warns on stderr. Generated UIDs and File Meta Information now use DICOMKit's own root
  (`UIDGenerator`, `DICOMFile.create`) instead of other organisations' arcs of
  1.2.826.0.1.3680043.10. `dicom-to-hl7` / `dicom-to-fhir` read only the first PN component
  group; `--message-type ADT` sends `ADT^A01` instead of `ADT^AA01`. New `dicom-gatewayTests`.
- **dicom-gateway** `listen` / `forward` (D103): help no longer claims a PACS forward or a DICOM listener. `--forward pacs://…` only reports what it would send, and `forward --listen-port` speaks no PS3.8 Upper Layer protocol and is no Storage SCP; both now say so in `--help` and print a stderr warning when used.

### Fixed — dicom-server verified against DICOM 2026a (2026-10-01)

- **dicom-server** (target still excluded from `Package.swift`; it does not compile against the
  current DICOMNetwork API): C-FIND response elements now take their VR from the data
  dictionary (PS3.6 2026a Table 6-1) — Patient ID, Patient's Name, Study ID, Accession Number,
  Study Description and Series Description were written as CS. The SOP Class and Transfer
  Syntax names beside the accepted UIDs are the PS3.6 Table A-1 names; help and README name the
  Query/Retrieve Levels PATIENT/STUDY/SERIES/IMAGE (PS3.4 Tables C.6.1-1 / C.6.2-1).

### Fixed — dicom-server builds again and closes D94–D102 (2026-10-01)

- **dicom-server** is back in `Package.swift` (product, target and a new `dicom-serverTests`
  target; the old `DICOMServerTests.swift` moved there) and compiles against the current
  DICOMNetwork / DICOMKit API (D99). Received instances are stored as PS3.10 files — preamble,
  "DICM", File Meta Information from `DICOMFile.create` with the negotiated Transfer Syntax UID,
  Source/Sending/Receiving AE Titles — and decoded with that transfer syntax (D102). An unknown
  Move Destination is refused with A801 instead of being sent to localhost:104; new repeatable
  `start --move-destination AE=host:port` (D96). C-GET awaits each C-STORE-RSP, counts
  Completed/Warning/Failed from its status, honours C-CANCEL, needs the SCP role from SCP/SCU
  Role Selection and returns every Storage SOP Class of PS3.4 Table B.5-1; final C-MOVE/C-GET
  statuses follow C.4.2.3.1 / C.4.3.3.1 (0000, B000, A702, FE00) with the Failed SOP Instance UID
  List (D97). A missing Query/Retrieve Level is refused with A900 and Offending Element
  (0008,0052) (D101). C-FIND matches and returns all Required/Unique keys of PS3.4 Tables
  C.6-1..C.6-5, returns only requested keys plus Query/Retrieve Level and Retrieve AE Title, and
  applies the C.2.2.2 rules (wildcards only for the listed VRs and case-sensitive except PN, List
  of UID Matching, DA/TM Range Matching); FF01 when optional keys are unsupported (D98, D100).
  Outgoing P-DATA is fragmented to the peer's Maximum Length and the A-ASSOCIATE-AC carries the
  server's own (PS3.8 D.1, D95). `--aet`, `--allowed-ae`, `--blocked-ae` are validated as VR AE
  and the Implementation Class UID is DICOMKit's (1.2.826.0.1.3680043.10.511.3.0.5.0) (D94).

### Fixed — dicom-print and dicom-printscp verified against DICOM 2026a (2026-10-01)

- **dicom-print:** `send --medium` offers `mammo-clear-film` and `mammo-blue-film` (MAMMO CLEAR
  FILM / MAMMO BLUE FILM, the two Medium Type (2000,0030) Defined Terms of PS3.3 2026a Table C.13-1
  it lacked). Every film-session / film-box option's help names its attribute and the term each
  token sends (`14x17 = 14INX17IN`, `medium = MED`, `bin-1 = BIN_1`, `lin-od = LIN OD`, …; the film
  size help listed 9 of the 12 Film Size IDs), and the standard term itself is now accepted as an
  alias in any case (`--film-size 14INX17IN`, `--priority MED`, `--medium "CLEAR FILM"`,
  `--film-destination BIN_1`, `--presentation-lut "LIN OD"`). `--layout` help lists all six Image
  Display Format forms of Table C.13-3 and says a grid `RxC` is sent as `STANDARD\C,R`;
  `--bit-depth` cites Table C.13-5 (was C.13-3); `--color` names the two Print Management Meta SOP
  Classes; `status` / `job` help names the N-GET attributes. Verbose and `list-printers` labels use
  the attribute names (Film Size ID, Print Priority, Medium Type, Called AE Title, …). README: the
  `--bit-depth` row said 8, 12 or 16 (16 is clamped), and the exit-code table listed 65/66/74, which
  the tool never returns. Tokens, defaults and the values sent are otherwise unchanged. New test
  target `dicom-printTests`.
- **dicom-printscp:** help named (0018,1020) "Software Version" and (0008,1090) "Manufacturer Model
  Name"; the PS3.6 2026a names are Software Versions and Manufacturer's Model Name.
  `--annotation-box` said N-CREATE / N-SET (PS3.4 Table H.4.4.2-1 defines N-SET only);
  `--push-job-events` now says it sends the Done event (Event Type 3, Table H.4-14), which is what the
  emulator sends; the capability flags name their SOP Classes and UIDs. `simulate --layout` takes every
  Image Display Format form of PS3.3 Table C.13-3 (`ROW\…`, `COL\…`, `STANDARD\C,R`, `SLIDE`,
  `SUPERSLIDE`, `CUSTOM\i`) as `dicom-print --layout` does; `--border-density` / `--empty-density`
  take a density in hundredths of OD as well as BLACK / WHITE; `--bit-depth` help said 8, 12 or 16
  (16 was always refused; Bits Stored is 8 or 12, Table C.13-5). Film-size, medium, orientation,
  magnification, polarity and Presentation LUT tokens are listed with the term each sends, and the
  term is accepted as an alias. New test target `dicom-printscpTests`.

### Fixed — dicom-cloud checked against DICOM 2026a (2026-10-01)

- **dicom-cloud (docs):** the README's archival example ran `dicom-anon --profile archive`, a
  profile dicom-anon does not have; it now uses `--profile ps315` (PS3.15 Annex E Basic
  Application Level Confidentiality Profile), and the `--tags` example notes that object
  metadata is not de-identified. `sync` help no longer calls the default mode bidirectional.
  The tool carries no DICOM-standard data (cloud plumbing only); it remains excluded from the
  package build.

### Fixed — dicom-jpip verified against DICOM 2026a (2026-10-01)

- **dicom-jpip:** `info --list-syntaxes`, the help and the `uri` error listed 2 of the 4 JPIP
  Referenced Transfer Syntaxes of PS3.6 2026a Table A-1; JPIP HTJ2K Referenced (…4.204) and JPIP
  HTJ2K Referenced Deflate (…4.205) are added, and `uri` / `info` now recognise them and read
  their Pixel Data Provider URL (0028,7FE0) (the shared `TransferSyntax.isJPIP` does not, see the
  DICOMCLI report). The descriptions said Pixel Data "contains a JPIP server URI"; per PS3.5 A.6
  Pixel Data is absent and the URL is in (0028,7FE0), which the printed label now names
  ("Pixel Data Provider URL", JSON key `jpipURI` unchanged). `info` cited "PS3.5 Annex A.8"
  (SMPTE ST 2110-20); it now cites 8.4.1 and A.6, A.7, A.11, A.12. New test target
  `dicom-jpipTests`.

### Fixed — dicom-wado verified against DICOM 2026a (2026-10-01)

- **dicom-wado:** `retrieve --uri --content-type` rejects a value WADOURIClient cannot request
  instead of silently fetching application/dicom (PS3.18 9.1.2.2.1; help lists the 7 values);
  `--frames` with `--uri` must start with a positive frame number (9.5.1.2.1; `0` or text was sent
  or dropped) and warns that only the first frame of a list is sent. New WADO-URI options
  `--transfer-syntax`, `--anonymize`, `--rows`, `--columns` (Tables 9.4.1-1 / 9.5.1-1); a
  parameter outside its representation's table warns. `retrieve --timeout` now sets the request
  timeout (it was ignored). `query` adds `--fuzzy-matching` (8.3.4.2) and rejects a negative
  `--limit` / `--offset` (8.3.4.4). `ups --state` and `--filter-state` accept the standard
  "IN PROGRESS" (PS3.3 Table C.30.1-1; IN_PROGRESS still accepted); `--state SCHEDULED` warns
  that it is not a Change State target (PS3.18 11.7.1.4). Help names the Enumerated Values of
  `--priority` (HIGH, MEDIUM, LOW; STAT sent as HIGH), `--patient-sex` and `ups --format csv`.
  `store` exits 1 when any file was not stored, also with `--continue-on-error`. README: exit
  code 64 (not 2) for invalid arguments, error text as printed, `query --format json` keys are
  keywords (the jq example used tag keys), WADO-URI section added. New test target
  `dicom-wadoTests`; `Scripts/diff_cli_web.py` diffs the tool against PS3.18 / PS3.3 / PS3.6.

### Fixed — dicom-mwl and dicom-mpps verified against DICOM 2026a (2026-10-01)

- **dicom-mwl:** `--sps-status` help and the discussion listed the Performed Procedure Step
  Status words; the Scheduled Procedure Step Status (0040,0020) Defined Terms are SCHEDULED,
  ARRIVED, READY, STARTED, DEPARTED (PS3.3 Table C.4-10). A value outside that list is still
  sent, now with a warning on stderr. The combined date+time interval is cited to its clause
  (PS3.4 Table K.6-1 remark under (0040,0003), C.2.2.2.5.4) instead of "K.6.1"; `--time`
  documents the TM forms of PS3.5 Table 6.2-1.
- **dicom-mpps:** the `--discontinuation-reason` examples paired DCM codes with the wrong
  meanings (110513 is "Discontinued for unspecified reason", 110514 "Incorrect worklist entry
  selected"; 110518 is not in CID 9300) — corrected from PS3.16 CID 9300/9301 and Table D-1.
  `create` now requires `--modality` (Modality (0008,0060) is Type 1 in the N-CREATE, PS3.4
  Table F.7.2-1) and validates `--patient-sex` (M/F/O, PS3.3 Table C.2-3) and
  `--patient-birth-date` (DA YYYYMMDD). `update` rejects `--image-uid` without
  `--study-uid`/`--series-uid` instead of silently dropping the references, and its examples
  show the Performed Series item COMPLETED needs. N-CREATE/N-SET failure and warning statuses
  are named per PS3.7 Annex C (e.g. "0106H Invalid Attribute Value") instead of
  "Store failed: Unknown status".

### Added — dicom-video audio Channel Source (D56, 2026-10-01)

- **`dicom-video convert` / `batch --audio-channel-source <value>`:** names the source of the
  multiplexed audio, which no container records, so each audio track gets a Multiplexed Audio
  Channels Description Code Sequence (003A,0300) Item whose Channel Source Sequence (003A,0208)
  carries the code (PS3.3 2026a Table C.7-13, Cine Module). The value is a PS3.16 2026a CID 3000
  keyword (`voice`, `operators-narrative`, `ambient-room-environment`, `doppler-audio`,
  `phonocardiogram`, `physiological-audio-signal`; the 6 rows generated from the DocBook) or
  `SCHEME:VALUE[:MEANING]` for any code, the CID being Extensible (MEANING required for an unlisted
  code, Code Meaning being Type 1). Without the option the sequence stays empty, as before. One
  value applies to every audio track (the engine's `Metadata.audioChannelSource` takes one code).
  New test target `dicom-videoTests`.

### Fixed — dicom-ai Segmentation output (D44, 2026-10-01)

- **`dicom-ai segment --format dicom-seg` writes a conformant Segmentation object (D44):** the
  output is built through `SegmentationBuilder` / `Segmentation.buildDataSet` and `DICOMFile.create`
  instead of a private DataSet, so it is a PS3.10 file whose every Segment Sequence Item carries
  one Segmented Property Category Code Sequence (0062,0003) and one Segmented Property Type Code
  Sequence (0062,000F) Item (Type 1, PS3.3 2026a Table C.8.20-4) plus the other Type 1 rows of
  Tables C.8.20-2 / C.8.20-4 the old writer omitted (Image Type, Photometric Interpretation, Lossy
  Image Compression, Segmentation Type, Segment Sequence, Segment Algorithm Type/Name, Pixel Data
  element, File Meta Information). New options `--segment-category` / `--segment-type` take a
  listed keyword or `SCHEME:VALUE[:MEANING]`; the default for both is (85756007, SCT, "Tissue")
  from PS3.16 2026a CID 7150 / CID 7166 (in CID 7151). Type 2 Patient and General Study attributes
  are copied from the source image and the Enhanced General Equipment Type 1 rows are written.
  The `dicom-ai` product and a `dicom-aiTests` target are re-enabled in `Package.swift`.

### Fixed — dicom-* CLI tools verified against DICOM 2026a (2026-10-01)

- **dicom-compress** help names transfer syntax 1.2.840.10008.1.2.4.110 "JPEG XL Lossless", the
  PS3.6 2026a Table A-1 name, instead of "JPEG XL Lossless Only" (D9). The `jpeg-xl-lossless-only`
  codec name is unchanged.
- **dicom-dcmdir** `--profile` help and error text name PS3.11 2026a Application Profile
  identifiers (STD-GEN-CD, STD-GEN-DVD-JPEG, STD-GEN-DVD-J2K, STD-GEN-USB-JPEG, STD-GEN-USB-J2K, …)
  instead of the family headings STD-GEN-DVD / STD-GEN-USB (D29); the error lists every identifier
  `DICOMDIRProfile.allStandard` accepts. Accepted values are unchanged (the old spellings remain
  aliases).
- **dicom-retrieve** prints the final C-MOVE/C-GET status with the wording of PS3.4 2026a
  Table C.4-2 / C.4-3 (e.g. "Failure (0xA702): Refused: Out of resources - Unable to perform
  sub-operations", "Warning (0xB000): Sub-operations Complete - One or more Failures") instead of
  the service-agnostic DIMSE text, the counters under their PS3.7 names (Number of Completed /
  Failed / Warning Sub-operations), and labels the Failed SOP Instance UID List (0008,0058). Help
  names the Query/Retrieve Level (STUDY / SERIES / IMAGE), the Study Root MOVE/GET SOP Classes, Move
  Destination (0000,0600) and the PS3.8 ports; `--hierarchical` help says what it does (C-GET,
  study/series). Option names, values and defaults are unchanged.
- **dicom-qr** exits 1 when any selected study fails to retrieve (`query` and `resume` printed the
  summary and exited 0); failures are worded per PS3.4 2026a Tables C.4-2 / C.4-3 and PS3.7 as in
  dicom-retrieve; `resume --timeout <s>` is new (was fixed at 60 s); help names the Study-level
  match keys with their tags, the range forms of PS3.4 C.2.2.2.5, the SOP Classes and Move
  Destination. Option names, values and defaults are unchanged.
- **dicom-send** counts a C-STORE response in the Failure class of PS3.4 2026a Table B.2-1 (A7xx
  Refused: Out of resources, A9xx Error: Data Set does not match SOP Class, Cxxx Error: Cannot
  understand, 0122 Refused: SOP Class not supported) as a failed file: it is printed with its
  status, retried under `--retry`, and makes the exit code 1. Previously every response the SCP
  returned was tallied and printed as a success. A Warning-class response (B000, B006, B007: stored
  with a deviation) stays a success and is now printed under the file line and tallied as "Stored
  with warning". `--priority` help names the PS3.7 Table 9.3-1 values (LOW 0002H, MEDIUM 0000H,
  HIGH 0001H).
- **dicom-query** `--level` accepts `image`, the Query/Retrieve Level (0008,0052) value of PS3.4
  2026a Tables C.6.1-1 / C.6.2-1 (IMAGE); `instance` remains accepted as an alias and the value
  sent on the wire was and is IMAGE. Help, validation messages and the hierarchical-query warning
  name the level IMAGE instead of INSTANCE. `--study-date` help documents the open ranges
  `-YYYYMMDD` / `YYYYMMDD-` of PS3.4 C.2.2.2.5. The README now shows the real `--format json` /
  `csv` output (keys are `(GGGG,EEEE)` tag strings, a tool-specific summary rather than the PS3.18
  Annex F DICOM JSON Model) and the real exit codes (0, 1, 64).
- **dicom-echo** README exit codes corrected (64 for a usage error); no behaviour change.

### Fixed — remaining DICOMKit deferred findings and verification gaps (2026-09-30)

- **De-identification covers all of PS3.15 Table E.1-1 (D69):** the Basic Profile rules are
  generated from the DocBook (`Scripts/generate_confidentiality_profile.py`) — all 651 single-tag
  rows with their option columns — instead of 79 hand-picked rows; 503 identifying attributes were
  previously kept and 21 took another action. Curve Data, Overlay Data and Overlay Comments are
  removed; Z on a sequence empties it; D values are consistent with the VR. Behaviour change:
  de-identified objects lose more attributes (e.g. Request Attributes Sequence, admitting
  diagnoses, allergies), Study / Series Description are removed rather than emptied, and Patient's
  Birth Date is emptied even under Retain Longitudinal Temporal, as the table specifies.
- **MP3 dual channel mode is refused (D61):** PS3.5 8.2.5 / 8.2.12 allow "one main mono or
  stereo channel"; MPEG-1 Part 3's dual_channel mode is neither.
- **AAC bit rate in MPEG-TS is measured (D62):** ADTS and LOAS frames are walked and the most bits
  in any one-second window compared with Table 8.2.12-1's 640 kbit/s
  (`VideoAudioTrack.measuredBitRate`, additive).
- **`nonImageSOPClasses`** is generated from PS3.4 Tables B.5-1 / GG.3-1 and the PS3.3 IOD module
  tables: 113 SOP Classes (31 were missing), so `tryPixelData` explains them as non-image.
- `Scripts/diff_kit.py` checks both tables; the MPEG-4_audio_extension_descriptor parser was
  checked against TSDuck; the DICOMNetwork report's status header was corrected.

### Fixed — DICOMRenderKit verified against DICOM 2026a (2026-09-30)

See `DICOMRENDERKIT_STANDARD_IMPLEMENTATION.md`. No public API change.

- **Pixel Cell width** (PS3.5 8.1.1): the Metal backend no longer renders a Bits Allocated 32
  sample from its low two bytes; such frames are declined and rendered by the CPU backend. (The
  CPU backend still has the same limitation; recorded as D67.)
- `FrameRenderRequest.window` is documented as stored-value units (PS3.3 C.11.2.1.2.1 applies the
  window after the Modality LUT; see P-PIPELINE, D65).
- `RenderStandardConformanceTests` pins the C.11.2.1.2.1 LINEAR worked example, MONOCHROME1 after
  the VOI (C.7.6.3.1.2) and Planar Configuration 1 (C.7.6.3.1.3) on both backends.
- New `Scripts/diff_renderkit.py`: evaluates the VOI functions, identity window, Modality-before-VOI
  order, sample assembly, planar layouts, YBR inverses, palette lookup and the eight PS3.6 Annex B
  palettes against the 2026a DocBook, and checks Metal/CPU parity.

Approval pass, same day (owner: "complete all D63–D67 next, and P-PIPELINE / P-ICC as per the
recommendation"). Additive API only.

- **PS3.4 N.2 grayscale chain (P-PIPELINE):** new DICOMKit `GrayscaleDisplayPipeline` (Modality LUT
  → VOI window or LUT → Presentation LUT), shared by `PresentationStateApplicator`, the exporter and
  both DICOMRenderKit backends. `FrameRenderRequest` gains `modalityLUT`, `voiLUT`, `presentationLUT`
  (defaulted; with any of them `window` is in modality units; MONOCHROME1 is INVERSE unless a
  Presentation LUT is given). 1- and 2-byte cells render through the chain's table on either backend.
- **Export applies the window after the rescale (D65, PS3.3 C.11.2.1.2.1):**
  `DICOMImageExporter.determineDisplayPipeline` (Modality LUT Sequence or this frame's rescale; window
  in modality units, else the VOI LUT Sequence, else the frame's range); `renderFrameForExport` uses
  it for monochrome frames. Exports of images with a slope other than 1 (and negative slopes, which
  rendered inverted), a Modality LUT Sequence or only a VOI LUT Sequence change.
  `determineWindowSettings` is unchanged and documented as stored units (DICOMStudio's viewer, D68).
- **ICC Profile (P-ICC, C.11.15.1.1):** `FrameRenderRequest.iccProfile`; colour output of both
  backends and `DisplayFrameTexture.colorSpace` carry the profile's colour space; `MetalImageView`
  sets it on the view (macOS).
- **Display byte (D63):** `WindowLUT.displayByte` floors `y · 255` with a 1e-9 tolerance, so the
  C.11.2.1.2.1 identity window is exact (32 of 256 8-bit values were one level dark); used by
  `WindowLUT`, `SIMDImageProcessor` and the applicator.
- **Window Width (D64):** the minimum of 1 applies to LINEAR only; SIGMOID and LINEAR_EXACT keep
  widths above 0 (`WindowSettings.admissibleWidth`).
- **Full-range windows (D66):** the auto window (renderer, exporter, print preparer) and the window
  written after a pixel-edit bake select x1…x2 with centre (x1+x2+1)/2, width x2−x1+1; a flat frame
  is the unit-width threshold (black, was white); the exporter's fallback is the 16-bit identity.
- **32-bit Pixel Cells (D67, PS3.5 8.1.1):** read whole by every `PixelDataRenderer` path, the
  applicator and the print preparer (`PixelDataDescriptor.cellValue(in:at:)`,
  `storedValue(fromCell:)`); monochrome evaluated per pixel through the chain.
- Open: D65's DICOMStudio half and D68 (DICOMStudio passing the chain and the ICC Profile).

### Fixed — DICOMCore and DICOMKit deferred findings closed (2026-09-29/30)

Rows D26, D31–D35, D37, D38, D45–D55 and D57–D60 of `DICOMKIT_STANDARD_IMPLEMENTATION.md`,
each checked against the 2026a clause named there. Full `swift test` exits 0 as of the D38 closure;
D45–D55 and D57–D60 were checked with the affected suites only.

- **Colon CAD SR** (Table A.35.10-2, D26): WAVEFORM is an allowed value type; TCOORD is not.
- **RT Tag constants** (PS3.6, D35): `Tag` constants for DVH Volume Units (3004,0054),
  High-Dose Technique Type (300A,00C7) and Treatment Delivery Type (300A,00CE); the RT parsers use them.
- **SR child content items** (Table C.17-6, D31): every content item type carries `contentItems`
  (defaulted initialiser parameter; `AnyContentItem.children` now returns them for any value type).
  The serializer and parser nest a Content Sequence under any value type, and the Mammography CAD,
  Chest CAD and TID 1500 builders nest children under their template parent (TID 1204, 1501,
  4000–4021, 4100–4107). The extractors still read the sibling layout of earlier versions.
- **Measurement group children** (PS3.16 TID 1501, 300, 301, 320; P-MGC, closes the rest of D31).
  **Source-breaking:** `MeasurementGroupContent` gains three cases, so a `switch` over it without
  `default` no longer compiles until they are handled. `.measurementWithContent(conceptName:value:units:content:)`
  writes a TID 300 NUM with its TID 301 children (modifiers, Measurement Method, Derivation, Finding
  Sites with Laterality and Topographical modifier, and TID 320 INFERRED FROM IMAGE / SCOORD with its
  SELECTED FROM IMAGE / SCOORD3D) in the NUM's Content Sequence; `.spatialCoordinatesOnImage(...)`
  writes TID 1501 row 10d (SELECTED FROM IMAGE) under the SCOORD;
  `.qualitativeEvaluationWithModifiers(...)` writes row 11b under the CODE. New types
  `MeasurementContent`, `MeasurementSource`, `MeasurementFindingSite`, `MeasurementConceptModifier`;
  `MeasurementGroupData.topographicalModifier` (row 8); `MeasurementGroupContentHelper.coordinates(graphicType:graphicData:sourceImage:)`.
  `MeasurementGroupContent` is now `Equatable`. `MeasurementReport` reads the group back into
  `ExtractedMeasurementGroup.contents`, `.laterality` and `.topographicalModifier`. The existing
  cases are unchanged; `.spatialCoordinates` still writes a SCOORD without row 10d (M).
- **Hanging Protocol nesting** (Tables C.23.1-1, C.23.2-1, C.23.3-1, D32): Image Set attributes in
  Time Based Image Sets items; Filter Operations, Sorting Operations, Reformatting, 3D Rendering and
  Blending Operation Type in Display Sets items; Synchronized Scrolling and Navigation Indicator
  Sequences; Preferred Playback Sequencing, Recommended Display Frame Rate and Display Environment
  Spatial Position in Image Boxes items; the Type 2 sequences are written empty. The old properties are
  deprecated and still write the 2026a layout; the parser reads the old layout.
- **Volumes** (C.7.6.3.1.2, D33): `DICOMVolume.photometricInterpretation`, `highBit`,
  `isMonochrome1`; slices that differ in pixel description are refused; `voxel()` honours High Bit.
- **Video audio** (PS3.5 8.2.5–8.2.12, D34): the probe and convert messages no longer say DICOM video
  has no audio. Audio was always kept in the bit stream, and the message now says so. An empty
  Multiplexed Audio Channels Description Code Sequence (003A,0300) is written when the input has
  audio (Type 2C, Table C.7-13). `VideoConsole.audioDiscardedLine` is deprecated for `audioCarriedLine`.
- **SR Verifying Observer Sequence** (Table C.17-2, D37): `SRDocument.verifyingObservers`; a VERIFIED
  document without observers now throws on serialisation.
- **PALETTE COLOR LABELMAP segmentations** (Tables C.8.20-2, A.51-1, D37):
  `SegmentationBuilder.setPaletteColor(iccProfile:colorSpace:)` writes the Palette Color Lookup Table
  and ICC Profile modules. `Segmentation.buildDataSet(pixelData:)` throws; `toDataSet` is deprecated.
- **Segmented Property codes** (Table C.8.20-4, D37): `buildDataSet` throws for a segment without
  Segmented Property Category or Type Code Sequence.
- **`FrameMerger` MONOCHROME1** (A.70.3.1, A.71.3.1, A.8.x.4, C.8.15.2, D37): MONOCHROME1 sources
  merged into IODs that require MONOCHROME2 are losslessly inverted, with window, VOI LUT, padding and
  Presentation LUT Shape adjusted so the image looks the same. Compressed MONOCHROME1 frames and a
  Modality LUT Sequence throw `MergeError.pixelAssembly` instead of producing a non-conformant file.
- **Presentation state tests** (D38): the 14 test files that had never compiled are ported
  (345 tests). Two library fixes came from them: `SpatialTransformation(rotation:)` always yields
  0/90/180/270 (Table C.10-6; 315° gave 360), and `PaletteColorLUT.preset(.hot)` no longer traps.
- **`LUT1D.lookup` below the table** (D48): inputs in (−1/(n−1), 0) truncated to index 0 and
  extrapolated below the first entry (`lookup(-0.5)` on [0.2, 0.8] gave −0.1). The input is now
  clipped to 0…1 first; NaN returns the first entry and ±infinity clips, where `Int(_:)` used to trap.
- **Grayscale LUT and colour-source palette tests** (D51): `GrayscaleLUTTests` and
  `ColorSourcePaletteTests`, committed with the print work but never in the test allowlist, now
  compile and run. Two expectations contradicted PS3.3 C.11.2.1.1 (VOI LUT output range 0…2^n − 1);
  they now pin the standard and are disabled until D53 is decided.
- **Video plan audio text** (PS3.5 8.2.5–8.2.12, Table 8.2.12-1, D47): `DICOM_VIDEO_CONVERSION_PLAN.md`
  no longer says DICOM video has no audio; it says audio is kept in the bit stream unchecked and
  quotes the current warning.
- **Segment Tracking ID and Tracking UID** (Table C.8.20-4, D45): `Segmentation.buildDataSet(pixelData:)`
  throws `SegmentationDataSetError.missingTrackingUID` / `.missingTrackingID` when a segment carries only
  one of Tracking ID (0062,0020) and Tracking UID (0062,0021); each is Type 1C on the other.
- **`BlendingMode`** (D49): documented as a rendering model. The DICOM attribute Blending Mode
  (0070,1B06), Enumerated Values EQUAL and FOREGROUND, belongs to the Advanced Blending Presentation
  State (Table C.11.34.1-1, A.33.7), which DICOMKit does not read or write. No API change.
- **TID 1500 Measurement Groups** (PS3.16 §6.2.2, §6.2.3, §6.2.5; D52): TID 1500 rows 7, 8 and 9
  include TID 1410, 1411 and 1501, which all start with the same (125007, DCM, "Measurement Group")
  CONTAINER. `TemplateValidator` checked every group against TID 1410, so a TID 1501 SCOORD without
  its row 10d source image passed. A group is now checked against each and assigned to the template
  whose rows describe it (fewest items left to extension, then fewest errors). No API change.
- **CAD templates in the registry** (PS3.16 TID 4000, 4100; D50): Mammography CAD Document Root,
  Chest CAD Document Root and the 31 templates they include (TID 4001–4018, 4020–4023, 4101–4107,
  1401, 1402) are generated from the 2026a tables into `TemplateRegistry` (73 templates), with a
  `TemplateIdentifier` constant and a `TID…` struct each. `MammographyCADSRBuilder` and
  `ChestCADSRBuilder` output validates against them with no violations.
  `Scripts/diff_sr_templates.py` checks every generated row against the DocBook (646 rows, 0 differences).
- **Value sets of several codes** (PS3.16 TID 1000, 4020; D55): a Value Set Constraint of one code per
  paragraph was read from its first paragraph only; TID 1000 row 1 now accepts Verbal as well as
  Document, and TID 4020 rows 11–12 accept mm as well as µm.
- **`ColorLUT.lookup` and `GrayscaleLUT.entry(for:)`** (D54): NaN, ±infinity and inputs beyond `Int`
  no longer trap. NaN and −infinity give the first entry, +infinity the last, as `LUT1D.lookup` (D48).
- **Video audio checked** (PS3.5 8.2.5, 8.2.12 and Table 8.2.12-1; PS3.3 Table C.7-13; D46): the
  probe reads each audio track's format, sampling frequency, channels, bits per sample and bit rate
  from an MP4 (sample entry, `esds`, `dac3`, `btrt`, first MPEG audio frame) or an MPEG-TS (PMT,
  first frame), so TS audio is now counted (`VideoProbeResult.audioTracks`). `VideoConformanceValidator.validateAudio`
  checks them: MPEG2 allows only CBR MP3; H.264/HEVC allow LPCM and AC-3 (MPEG-2 TS only), AAC, MP3
  and MPEG-1 Layer II with their bit rate, sampling frequency, bit depth and channel limits. Each
  violation is a `convert`/`probe`/`batch` warning; the audio is never stripped or re-encoded, and a
  value the container does not expose is "not checked". (003A,0300) gets one Item per track
  (MONO/STEREO) when the caller names the CID 3000 source (`VideoWorkflow.Metadata.audioChannelSource`)
  and every track is mono or stereo; `VideoParser` reads the Items back. Additive API only.
- **VOI LUT output range** (PS3.3 C.11.2.1.1, D53). **Behaviour change:** `GrayscaleLUT.normalized(_:)`
  now divides by 2^n − 1 (n = third LUT Descriptor value, "The output range is from 0 to 2^n-1"), so a
  16-bit table whose entries stop at 4095 peaks at 4095/65535 and a flat table gives entry / (2^n − 1)
  instead of 0. The previous used-range scaling is the opt-in `normalized(_:normalizeToUsedRange: true)`;
  `ImagePreprocessor.prepareForPrint` passes it, so print output is unchanged.
- **E-AC-3 audio** (PS3.5 8.2.12, D59): 8.2.12 cites ETSI TS 102 366 for AC-3, which the PS3.5
  bibliography titles "Audio Compression (AC-3, Enhanced AC-3) Standard", so E-AC-3 is no longer
  reported as a format 8.2.12 does not permit; it is checked against the AC-3 limits (640 kbps, 48 kHz,
  16 bits, 2 or 5.1 channels, MPEG-2 TS only). **Behaviour change:** fewer warnings for E-AC-3 within them.
- **Audio Channel Source** (PS3.16 CID 3000 Extensible, PS3.3 Table C.7-13 DCID 3000; D57):
  `VideoAudioChannel.Source` is a struct wrapping any `CodedConcept`, with constants for the six CID 3000
  codes. **Behaviour change:** `VideoParser` keeps an Item with a code outside CID 3000 instead of
  dropping it, and `VideoBuilder` writes it back. (The type was added on this branch and never released.)
- **Cine attributes read back** (PS3.3 Table C.7-13, D60): `VideoParser` now reads Frame Time Vector,
  Preferred Playback Sequencing, Image Trigger Delay and Effective Duration, which `VideoBuilder` writes,
  so a parse and rewrite no longer drops them. No API change.
- **MP3 CBR, LATM AAC and remaining audio checks** (PS3.5 8.2.5, 8.2.12; D58): the probe walks every MP3
  frame header (MP4 sample table or MPEG-TS PES payloads, first 2,000 frames) and reports a stream whose
  frames differ in bit rate, or that opens with a Xing/VBRI header, as not "CBR MPEG-1 LAYER III".
  MPEG-TS LATM audio (stream_type 0x11) and raw MPEG-4 audio with an MPEG-4_audio_extension_descriptor
  (0x1C) are identified from their AudioSpecificConfig. Bits per sample of AAC, AC-3, MP3 and MP2 is
  stated as not in the coded stream instead of "not checked"; MP3 complementary channels (ISO/IEC 13818-3
  multichannel extension) remain "not checked", with the reason. **Behaviour change:** an MP4 AAC/AC-3/MP3
  track no longer reports the sample entry's template samplesize (16) as its bit depth. Additive API:
  `VideoAudioTrack.bitRateScan`, `VideoAudioCheckNote`, `VideoAudioTrackCheck.notes`.

New findings D44–D62 are recorded in the report (P-MGC, the API decision opened with them, is implemented above).

### Fixed — DICOMPrintKit verified against DICOM 2026a (2026-09-29)

Audit report: `DICOMPRINTKIT_STANDARD_IMPLEMENTATION.md`. Every value the module uses is diffed
against the frozen NEMA text by `Scripts/diff_printkit.py` (32 checks against PS3.3, PS3.4, PS3.5,
PS3.6 and PS3.14 2026a; 0 failing, 0 pending), and all 31 Swift files carry a `NEMA-verified`
marker. The three decisions of the first pass were approved and applied the same day:

- **Medium Type MAMMO terms (P-MAMMO, DICOMNetwork).** `MediumType.mammoClearFilm`
  ("MAMMO CLEAR FILM") and `.mammoBlueFilm` ("MAMMO BLUE FILM") per PS3.3 Table C.13-1;
  `.mammoFilmClearBase` / `.mammoFilmBlueBase` ("MAMMO CLEAR" / "MAMMO BLUE", not terms) are
  deprecated, still parsed, normalized on receipt and written as the terms (`wireValue`,
  `normalized`); `MediumType.allCases` lists the five terms; `PrintOptions.mammography` sends
  MAMMO BLUE FILM; `PrintOptionCatalog.mediumTypes` offers both (`mammo-clear-film`,
  `mammo-blue-film`).
- **Calibrated film rendering (P-GSDF).** `DensityMapping.gsdf` (`--density gsdf`, "Calibrated
  (PS3.14 GSDF)") draws the sheet a PS3.14-conforming printer produces: P-Values laid down through
  the Grayscale Standard Display Function between Min and Max Density (7.2 for film, 7.3 for
  PAPER), LIN OD and numeric Border/Empty densities as densities, shown as the sheet's luminance
  under PS3.14's typical viewing conditions. Reproduces PS3.14 Table D.2-1 within 0.0015 OD. The
  default mapping is unchanged.
- **Compound graphics and annotation styles (D39, DICOMKit).** The Graphic Annotation Module's
  Compound Graphic Sequence (0070,0209) — MULTILINE, INFINITELINE, CUTLINE, RANGELINE, RULER,
  AXIS, CROSSHAIR, ARROW, RECTANGLE, ELLIPSE — and the Text, Line and Fill Style Sequence Macros
  (PS3.3 2026a Tables C.10-5, C.10-5a/5b/5c) are modelled (`CompoundGraphic`, `TextStyle`,
  `LineStyle`, `FillStyle`, `GraphicShadow`), written with their 1C conditions and read back;
  graphic and text objects carry Compound Graphic Instance ID and Graphic Group ID; `validate`
  requires every compound graphic's alternate rendering (C.10.5.1.3.1). The parser now reads
  text objects that carry only an anchor point. DICOMPrintKit writes a drawn arrow as an ARROW
  compound graphic (with its polylines as the alternate rendering) and every drawing's own colour
  and halo in its Line or Text Style, and reads them back the same way.
- **Print annotation text and a citation (D40, D41, DICOMNetwork).** Text String (2030,0020) is
  written as a legal LO for every caller (`PrintAnnotation.textStringValue`: 64 characters, no
  backslash or control characters, PS3.5 Table 6.2-1); Enumerated Values cited as PS3.5 6.3.
- **Round-trip tests (D43).** `PDFRoundTripTests` expected the encapsulated-document output from
  before the DICOMKit P-ENCAP fix; its pins are now the 2026a values (STL `model/stl`, CDA
  `text/XML` with an HL7 Instance Identifier, Series/Instance Number 1, empty Type 2 Document
  Title). The full `swift test` passes.
- **CROP without a Requested Image Size (P-CROP).** The existing reading (fill the box) is kept
  and stated in `PRINT_CONFORMANCE.md` 3.5, whose stale Medium Type, Presentation LUT Shape, Bits
  Stored and YBR entries are corrected.

- **Saved views are conformant presentation states (D27, D36).** `PresentationStateStore.save`
  passes the image size to the builders, so a fitted view carries the Type 1 Displayed Area
  Selection Sequence (the whole image, SCALE TO FIT; PS3.3 Table C.10-4); writes the image's
  rescale as the state's own Modality LUT (PS3.4 N.2.1.1: the image's rescale is not used under a
  presentation state), with `ImageToSave.rescaleType` (default `US`); and saves a colour image as a
  Color Softcopy Presentation State (A.33.1.1: GSPS and Pseudo-Color reference monochrome images
  only), keeping a colour image's inversion in the sidecar. New defaulted input
  `ImageToSave.photometricInterpretation`.
- **MONOCHROME1 polarity.** `ViewerPresentationStateBridge.capture/restore` take an optional
  `photometricInterpretation`; for MONOCHROME1 the upright view is written as Presentation LUT
  INVERSE and read back the same way (PS3.4 N.2: the image's photometric is ignored under a
  presentation state).
- **Shutters from a study's presentation states** are placed on 1-based pixel positions (Table
  C.7-17a): the first open row and column were shuttered.
- **`--raw` print jobs** whose pixel module a Basic Grayscale or Color Image Box cannot carry
  (signed pixels, Bits Stored other than 8/12, YBR or PALETTE COLOR, High Bit ≠ Bits Stored − 1;
  PS3.3 Table C.13-5) now fail with the rule instead of being sent non-conformant.
- **Film geometry.** 10INX14IN is composed on 257 × 364 mm, as PS3.3 Table C.13-3 states (was
  254 × 355.6 mm). The Print SCP simulator writes the job's own Image Display Format (a `ROW\1,2`
  job was composed as `STANDARD\2,2`).
- **Emulator status.** The FAILURE default Printer Status Info is `SUPPLY EMPTY`, a C.13.9.1
  Defined Term (was `NO SUPPLY`).
- **Annotation Text String** (2030,0020) footer lines are kept legal LO values: at most 64
  characters, no backslash, no control characters (PS3.5 Table 6.2-1;
  `FilmIdentificationFooter.textString(_:)`).
- **Citations and comments** corrected against the 2026a text: Bits Stored 8/12 is Table C.13-5,
  not C.13-3 (D23; also in the `--bit-depth` message and the clamp note); Spatial Transformation
  is C.10.6 (not C.10.10); the hardcopy Presentation LUT is C.11.4; Film Size ID is C.13.3 (C.13.6
  is retired); Max Density is (2010,0130); the YBR 4:2:2 layout is C.7.6.3.1.2 (PS3.5 8.7.4 does
  not exist); Content Label (0070,0080); C.11.2 sets no precedence between VOI LUT Sequence and
  window and no default pair; C.10.5 does have an ARROW compound graphic and per-object colour
  (DICOMKit does not model them yet, D39).

### Fixed — DICOMKit verified against DICOM 2026a (2026-09-29)

Audit report: `DICOMKIT_STANDARD_IMPLEMENTATION.md`. Every constant the module carries is diffed
against the frozen NEMA text by `Scripts/diff_kit.py` (41 checks against PS3.3, PS3.5, PS3.6,
PS3.15 and PS3.16 2026a; 0 failing; the one pending item is the DICOMCore row D26), and all 157
Swift files carry a `NEMA-verified` marker. Behaviour fixes were each verified against the clause named.

- **Coded concepts (PS3.16 Table D-1, CID tables).** 58 code/meaning pairs were wrong and are
  corrected: RWV and parametric-map quantities (T1 113063, T2 113065, T2* 113064, ve 126314,
  Vp 126331, rCBF 113055, rCBV 113056, MTT 113052; SUV meanings SUVbw/lbm/bsa/ibw), KOS document
  titles (Best In Set 113013, For Printing 113018, For Report Attachment 113020), Chest CAD title
  and root (112000), the CAD finding concepts (111059 Single Image Finding, 111047 Probability of
  cancer, 111012 Certainty of Finding, 111010 Center, 111030 Image Region, 111017, 111034,
  122405 Algorithm Manufacturer), Enhanced SR measurement concepts (SCT 81827009 Diameter,
  410668003 Length, 42798000 Area, 118565006 Volume; 126010 Imaging Measurements), PET
  Measurement Report 126003, 121074 "Recommendations". SRT ids that meant other concepts are
  replaced by the SCT codes of CID 6015/6017/6104. Mammography and Chest CAD SRs no longer write a
  DATETIME item (Tables A.35.5-2 / A.35.6-2 do not permit one; `processingDateTime` is accepted
  and ignored). `CADFindingsExtractor` reads both the new and the old codes.
- **Structured Reporting.** `SRDocumentType.allowsValueType(_:)` is deprecated and forwards to
  DICOMCore's `allows(_:)` (D16). `ComprehensiveSRBuilder.addPolygon` / `.polygon` write a
  closed POLYLINE, since 2D SCOORD has no POLYGON (C.18.6.1.2, D18); `SpatialCoordinates.isClosed`
  and `area` recognise it. SCOORD3D writes and reads Referenced Frame of Reference UID
  (3006,0024), not (0020,0052) (Table C.18.9-1). KOS series Modality is `KO` (C.17.6.1).
- **Approved public-API items (2026-09-29, second pass).** Every P-item of the report was approved
  and implemented, each against the 2026a clause named in the report's Progress log:
  - *Hanging Protocol* (Tables C.23.1-1, C.23.3-1): the standard Filter-by Operator, Filter-by
    Category IMAGE_PLANE, Image Set Selector Category, Relative Time (US 2) / Abstract Prior Value
    (SS 2), Sort-by Category, Image Box Layout, Scroll, Reformatting and 3D Rendering terms,
    Hanging Protocol Level MANUFACTURER, VOI Type, top-level Partial Data Display Handling; the
    invented cases are deprecated and mapped; the matcher's MATCH/NO_MATCH semantics were inverted.
  - *RT* (Tables C.8-39…C.8-51): `CLOSEDPLANAR_XOR`, the full RT ROI Interpreted Type list, typed
    enums for every Dose/DVH/Beam/Plan/Brachy term (String storage unchanged).
  - *Segmentation*: LABELMAP write and read, Label Map Segmentation Storage, `Segmentation.toDataSet`.
  - *Waveform* (Tables C.10-8/9/10): all ten Sample Interpretation terms with correct names
    (`unsignedInteger`/`signedShort` deprecated), Type 1 attributes written, UL sample positions.
  - *Secondary Capture* (Tables A.8-x, C.8-24/25b/25c): DRW, `.unknown` deprecated (writes WSD),
    every Type 1/2 attribute written by the builder, converter and `FrameMerger`; EXIF DPI as
    Nominal Scanned Pixel Spacing.
  - *Coded concepts*: `regionOfInterest`, `measurementLocation`, `temporalExtent`, `comparison`
    now carry real 2026a concepts; `99DICOMKIT` private scheme (PS3.16 section 8) for the three AI
    detection types without a DICOM concept; `anatomicalStructure(_:)` with verified anatomy codes;
    confidence as (111012, DCM, "Certainty of Finding") in percent; CID 7021 titles renamed.
  - *SR serializer*: SR Document Series module, Type 1 flags always written, one code identifier per
    Table 8.8-1a, TABLE integer cells IS/SV; TID 1500 and TID 4000/4100 families emitted row by row
    (`MammographyCADSRBuilder`, `ChestCADSRBuilder`, `MeasurementReportBuilder`); extractors read
    the new and the old layouts.
  - *Presentation states*: MATRIX units, Shutter Presentation Color CIELab Value, Presentation
    Pixel Spacing / Aspect Ratio / Magnification Ratio with their 1C rules, a
    `ColorPresentationStateBuilder` (CSPS), builders take `imageSize:` so the Type 1 Displayed
    Area Selection Sequence is always written.
  - *UIDs* (PS3.5 9.2.2): `UIDGenerator.defaultRoot` and `DICOMFile.implementationClassUID` are
    under the library's root `1.2.826.0.1.3680043.10.511` (arcs .4 and .3), no longer the OFFIS
    DCMTK root; `PrintColorMode` is one DICOMCore type (D24).
  - *Validator*: data-driven Type 1/2 tables per IOD (PS3.5 7.4); *de-identification*: Patient
    Identity Removed, De-identification Method and Method Code Sequence (CID 7050) written;
    *encapsulated documents*: every Type 1/2 attribute; *volume*: slice spacing from Image Position
    deltas, source pixel descriptor; *rendering*: partial-range YBR, ICT/RCT pass-through, exact
    C.11.2.1.2.1 windowing in SIMD; *JPIP*: (0028,7FE0); *video*: Cine module, Lossy Image
    Compression Method per transfer syntax, empty Basic Offset Table, audio per PS3.5 8.2.12;
    *SUV*: CID 85 units, DCM 126411–126413 factors, decay START/ADMIN.
  - Test suites that had never been in the `DICOMKitTests` allowlist (AI, EncapsulatedDocument,
    SecondaryCapture, four first-pass suites) now compile and pass.
- **DICOMDIR and file meta.** A DICOMDIR with an unknown or PRIVATE Directory Record Type now
  opens; the record is skipped (F.6.1, D14). `DICOMFile.write()` computes File Meta Information
  Group Length when absent (PS3.10 Table 7.1-1); `DICOMDIRWriter` no longer writes the Deflated
  Transfer Syntax UID as its Implementation Class UID (`DICOMFile.implementationClassUID` is the
  one constant). The VR lists of `DICOMFile` and `HexDumper` include OV, SV, UV.
- **Segmentation.** 1-bit frames are packed and unpacked least-significant-bit first (PS3.5 8.1.1,
  D.1); they were MSB first, so every SEG DICOMKit wrote was mirrored byte-wise for other readers.
  **Behaviour change:** SEG objects written by earlier versions are now read mirrored.
- **Presentation states** (audit NC-1, 5–15, 19; MF-3, MF-10). The GSPS builder writes the
  Modality LUT (rescale or sequence), table-valued VOI and Presentation LUTs, the Display Shutter
  module, Graphic Filled only for closed shapes (C.10.5 1C), the layer colour as Graphic Layer
  Recommended Display CIELab Value (0070,0401) instead of the retired RGB value, and a Type 2
  Content Creator's Name. The parser reads circular/polygonal shutters row/column (C.7.6.11),
  CIELab first, LUT Descriptor/Data as binary, and skips MATRIX-unit objects instead of placing
  them in pixels. `PresentationStateApplicator` masks outside every shutter (intersection,
  origin 1,1, P-Value scaled) before rotating then flipping (C.10.6), and normalises the no-VOI
  range over the Modality LUT output. The PCSPS palette no longer bakes the window (PS3.4 N.2).
  The embedded ICC profile is Input Device class `scnr` (C.11.15.1.1). Citations corrected.
- **Hanging protocols.** Wire values follow Tables C.23.1-1/C.23.3-1 where one-to-one:
  Hanging Protocol Level `USER_GROUP`/`SINGLE_USER`, Sorting Direction `INCREASING`/`DECREASING`,
  Filter-by `LESS_OR_EQUAL`/`GREATER_OR_EQUAL`, 3D Rendering `VOLUME`/`SURFACE`, the display
  flags `YES`/`NO` (`Y`/`N` still read); Hanging Protocol Name SH, Description LO. The
  remaining enumerations need API changes (report P-HP).
- **Other data.** RT ROI Interpreted Type `IRRAD_VOLUME`, `FIXATION` (Table C.8-44);
  `WaveformSampleInterpretation.isSigned` follows Table C.10-10 (SB signed, US unsigned);
  Unformatted Text Value (0070,0006) as ST, Document Title (0042,0010) as ST, Frame Acquisition
  Number as US, Instance Number read as IS; Color Space `DISPLAYP3` read; STL MIME `model/stl`
  (A.85.1); PS3.15 Table E.1-1 actions for Device UID (U) and Placer/Filler Order Number (Z);
  `ComparisonReport` treats OL, OV and UN as binary (D5); `CompressionManager` relabels XYB to
  RGB after JPEG XL decode (D12); `DICOMValidator` requires the Type 1 file meta elements,
  accepts TM values of 2, 4 or 6 digits, drops the 1900 year bound, names ISO_IR 192 and detects
  every SR SOP Class; `nonImageSOPClasses` corrects `90.1`/`91.1` and `200.7`/`200.8`.

### Audited — Presentation State (GSPS/CSPS/PCSPS) against DICOM 2026a (2026-09-25)

Read-only audit report: `PRESENTATION_STATE_COMPLIANCE_AUDIT.md`. Covers
`Sources/DICOMKit/PresentationState/`, `Sources/DICOMPrintKit/PresentationState/` and the
DICOMStudio viewer paths that consume them, against PS3.3 A.33.1-A.33.3, C.7.6.11, C.7.9,
C.10.4-C.10.7, C.11.1, C.11.6, C.11.8-C.11.15, Table 10-12; PS3.4 N.2; PS3.5 §7.4.4; PS3.6
(0070,0067)/(0070,0401). No source code was changed. 19 non-conformances found (NC-1 to NC-19),
the highest-impact being: the Modality LUT is never written although the window is in rescaled
units (NC-1); GSPS is used for colour images with no CSPS writer (NC-3); the Displayed Area
Selection Sequence is omitted for "fit" views, which fails `dcmpschk` (NC-4); the ICC profile
class is Display (`mntr`) instead of Input (`scnr`) (NC-5); display-shutter semantics are
inverted and shutter geometry is read in the wrong order in `PresentationStateApplicator`
(NC-6, NC-7). Estimated compliance: GSPS ≈ 55%, CSPS ≈ 32% (read-side only), PCSPS ≈ 62%. Fixes
are not yet scheduled; findings are recorded for when this module's audit turn comes up.

### Fixed — DICOMCore `DataElement.stringValues` keeps empty values (D25, 2026-09-28)

- `stringValues` split on backslash with `split(separator:)`, which drops empty subsequences, so
  `"MPG\\XR3"` came back as two values and every later value moved down one position. It now
  keeps empty values in place (PS3.5 §6.4); a zero-length or padding-only Value Field returns
  `[]` as before. Callers that index into a multi-valued attribute get the right value.

### Fixed — DICOMWeb verified against DICOM 2026a (2026-09-28)

Audit report: `DICOMWEB_STANDARD_IMPLEMENTATION.md`. Every constant the module carries is diffed
against the frozen NEMA text by `Scripts/diff_web.py` (35 checks against PS3.3, PS3.4, PS3.6, PS3.18
and PS3.19 2026a; 4 report a pending public-API decision), and all 54 Swift files carry a
`NEMA-verified` marker. Behaviour fixes were each verified against the clause named.

- **DICOM JSON Model (D2, D3; PS3.18 Annex F).** `InlineBinary` and `BulkDataURI` are siblings of
  `vr`, never inside `Value` (F.2.2); the old DICOMKit layout is still accepted on input. AT values
  are the 8-character uppercase hexadecimal tag (F.2.3); Group Length attributes are not written;
  empty values of a multi-valued attribute are `null` (F.2.5) both ways; attribute objects are
  written in ascending lexicographic tag order by a new internal writer, because
  `JSONSerialization.sortedKeys` orders `7FE00010` before `0020000D` on current macOS.
  **Behaviour change:** `DICOMJSONEncoder.Configuration.includeEmptyValues` and
  `DICOMXMLEncoder.Configuration.includeEmptyValues` now default to `true`; an empty attribute is
  written as `{"vr": "XX"}` with no `Value` (F.2.5 "shall be preserved"), and `false` drops it.
- **Native DICOM Model XML (D4; PS3.19 A.1).** OV is InlineBinary/BulkData. Numeric VRs (FL, FD,
  SL, SS, UL, US, SV, UV) and AT were never written and, on input, were stored as text; they are
  now `<Value>` elements and decode to the binary Value Field. Empty values are preserved, the root
  carries `xml:space="preserve"`, private elements are written as `gggg00ee` with `privateCreator`
  and placed back in their creator's block on input, `BulkData uuid` is accepted.
- **Media types.** Parameter values containing RFC 2045 tspecials are quoted
  (`type="application/dicom"`, PS3.18 8.7.1); `image/jpx`, `image/jxl`, `image/dicom-rle`,
  `application/x-deflate` added; `DICOMMediaType.bulkDataMediaType(forTransferSyntax:)` carries
  Tables 8.7.3-4 / 8.7.3-5. `retrieveFrames` asks for `application/octet-stream` or the compressed
  bulk data media type, not `application/dicom` (Table 10.4.4-1).
- **Rendered resources.** `window=center,width,function` and `viewport=vw,vh` (8.3.5.1.3,
  8.3.5.1.4) replace `windowcenter`/`windowwidth`/`columns`/`rows`, whose `QueryParameter`
  constants are deprecated; `quality` is 1-100; thumbnails send no `quality` (Table 8.3.5-2).
  `QIDOQuery.studiesByModality` matches Modalities in Study (0008,0061) (Table 10.6.1-5).
- **UPS-RS clients (`DICOMwebClient`, `UPSClient`).** Request Cancellation is POST (Table 11.3-1);
  the Deletion Lock is the `deletionlock=true` query parameter (11.10.1.2); a change to IN PROGRESS
  without a Transaction UID generates a valid one (PS3.4 CC.2.1.2); filtered-worklist and global
  suspend URLs added; section citations renumbered to the 2026a text.
- **UPS-RS server (`DICOMwebServer`, `DICOMwebRouter`).** Create with a client UID is
  `POST /workitems?workitem=`; `POST /workitems/{uid}` is Update (PUT still accepted); cancel
  request is POST (PUT still accepted); the well-known subscription UIDs reach the global handlers.
  Status codes and Warning texts follow Tables 11.4.3-1 to 11.12.3-1 and 8.5-1: create 201 only
  in SCHEDULED and without a payload, update 200 with 400 for a final-state Workitem or a
  missing/incorrect Transaction UID, change state 200 without a payload, 400 for a missing or
  incorrect Transaction UID, 409 for a transition PS3.4 Table CC.1.1-2 refuses, a warning when
  already in the requested final state; cancel request 202 (409 when COMPLETED; a SCHEDULED UPS
  is cancelled through IN PROGRESS, CC.2.2.3); subscribe 201 (403 for the unsupported filtered
  worklist); not-implemented retrievals 501. Retrieved and searched Workitems no longer carry
  the Transaction UID (11.5.2). Searches emit the remaining-results warning (8.3.4.4.1).
- **Studies server.** STOW-RS Failure Reason values from Table I.2-2, 409 when nothing was
  stored, `Location` of the created study; `Content-Location` on every multipart part (Table
  8.6.1-1); single-part `application/dicom` instance retrieval; 406 when the Accept header names
  nothing supported (8.7.5); DICOM JSON responses in F.2.2 order.
- **UPS model.** `UPSState.scheduled.validTransitions` is `[.inProgress]` (PS3.4 Table CC.1.1-2);
  Transaction UIDs are valid UIDs (were `2.25.<hex>`); Human Performer's Name is PN, Procedure
  Step Progress Description ST, Procedure Step Progress DS (PS3.6 Table 6-1);
  `UPSTag.commentsOnTheScheduledProcedureStep` carries the PS3.6 keyword (old name deprecated).
- **Documentation.** 28 PS3.18 section citations corrected; `ConformanceStatement.dicomVersion`
  defaults to 2026a; `AuthenticationMiddleware` recognises the `thumbnail` and `pixeldata`
  segments; transfer syntax comments carry the PS3.6 Table A-1 names.
- **Public API, approved by the owner (2026-09-28).** `STOWResponse.FailureReasonCode` gains
  `referencedTransferSyntaxNotSupported` (C122), `dataSetDoesNotMatchSOPClassError` (A900) and
  `dataSetDoesNotMatchSOPClassWarning` (B007) per PS3.18 Tables I.2-1 / I.2-2; the seven
  PS3.7-only cases (0112-0115, 0120, 0124, 0131) are deprecated; `knownFailureReason` classifies
  the A7xx, A9xx and Cxxx ranges. `UPSEventType.eventTypeID` / `init(eventTypeID:)` carry the
  PS3.4 Table CC.2.4-1 Event Type ID (case `scpStatusChange` added); every UPS Event Report is
  DICOM JSON with Event Type ID (0000,1002) and the Table CC.2.4-1 attributes only, never the
  Transaction UID; `completed`/`canceled` events serialise as State Reports. `UPSPriority.stat`
  is deprecated and written as HIGH (`dicomValue`; PS3.3 C.30.2); `UPSPriority.allCases` is HIGH,
  MEDIUM, LOW. `WADOURIClient.ContentType.htj2kContainer` is deprecated (image/jphc is not a
  Rendered Media Type, PS3.18 9.1.2.2.1) and requests for it use image/jph.
- **UPS-RS Create payload.** `Workitem.toDICOMJSONForCreate` sends every Type 2 attribute of the
  N-CREATE column of PS3.4 Table CC.2.5-3, empty when the model has no value, and an empty
  Transaction UID as the table requires.

### Fixed — DICOMNetwork verified against DICOM 2026a (2026-09-28)

Audit report: `DICOMNETWORK_STANDARD_IMPLEMENTATION.md`. Every protocol constant the module carries
is now diffed against the frozen NEMA text by `Scripts/diff_network.py` (44 checks against PS3.3,
PS3.4, PS3.6, PS3.7 and PS3.8 2026a), and all 63 Swift files carry a `NEMA-verified` marker. The
behaviour fixes below were each verified against the clause named; none changes a public signature.

- **64-bit VRs on the wire (D1).** The Explicit VR encoders and parsers of Query, Retrieve, Storage,
  MPPS, Modality Worklist and Storage Commitment used a private length rule that omitted OV, SV and
  UV, so those elements got a 2-byte length header. They now use DICOMCore's `VR.uses32BitLength`
  (PS3.5 §7.1.2, Table 7.1-1).
- **Storage Commitment SCP and notification listener read the PDU length little-endian (D13).**
  A 259-byte A-ASSOCIATE-RQ was taken for a 50 MB PDU and the read never returned. Both use
  `PDUDecoder.readHeader` (PS3.8 §9.3.1, big-endian). The listener also resumed a continuation
  twice once the exchange got further. Six test expectations that contradicted PS3.5 §6.2
  even-length padding were corrected. DICOMNetworkTests: 1,331 → all green.
- **C-GET proposes every Storage SOP Class (D21).** With 170 classes in PS3.4 Table B.5-1 and 127
  contexts per association (PS3.8 §9.3.2.2), the last 43 were never proposed. The SCU now runs the
  C-GET in batches of 127 classes, a second pass on a new association only when the first reported
  failures; results are merged.
- **Upper layer (PS3.8).** A-ASSOCIATE-AC carries a Transfer Syntax sub-item in every Presentation
  Context item, rejected ones included (Table 9-18). A-ABORT from the service user sends reason 00H;
  protocol errors abort with the service-provider source (Table 9-26, AA-8); a local ARTIM timeout
  aborts as AA-1 and the abort is now actually transmitted. An A-RELEASE-RQ received while
  established is answered with A-RELEASE-RP (AR-2/AR-4); a release collision waits for the peer's
  A-RELEASE-RP (AR-9/AR-3). Sta13 handles A-ABORT and ARTIM expiry (AA-2). A peer maximum length
  of 0 means unlimited, the negotiated limit applies to P-DATA-TF only, and fragments use
  maximum − 6 bytes (Annex D.1, Table 9-23). AE titles accept only the ISO 646 basic G0 set
  0x20-0x7E without backslash, trim SPACE only and tolerate NUL padding on decode (Table 9-11,
  PS3.5 Table 6.2-1). `AssociateRequestPDU`/`AssociateAcceptPDU.encode()` throw for an
  Implementation Class UID over 64 bytes or a version name that is empty or over 16 (PS3.7
  D.3-1/D.3-3). SCPs reject an A-ASSOCIATE-RQ whose Protocol-version has bit 0 clear (ACSE,
  reason 2). State descriptions carry the Table 9-1..9-5 numbers.
- **A-ASSOCIATE-RJ reasons (Table 9-21).** StorageSCP and PrintSCP sent reason 2
  (application-context-name-not-supported) for an unknown calling AE title; now 3. The commitment
  listener sent reason 3 with the ACSE source; now the service-user source. "No presentation context
  accepted" rejections use permanent / service-user / 1. `NetworkConsoleFormatter` had reasons 3 and
  7 swapped and invented reason 0; it now takes its text from `AssociateRejectPDU`.
- **DIMSE.** Command-set AE and LO values (Move Destination, Move Originator AE Title, Error
  Comment) are SPACE-padded, UI values NULL-padded (PS3.5 Table 6.2-1). `StoreAndForwardQueue`
  ordered by the raw Priority code, so LOW went first; it now ranks HIGH, MEDIUM, LOW (PS3.7 Table
  E.1-1). StorageSCP answers unsupported requests with status 0211H instead of silence. The
  Storage Commitment SCP answers an unknown Action Type with 0123H and a wrong SOP Class with 0118H
  (PS3.7 §10.1.4.1.10); the listener answers every N-EVENT-REPORT-RQ (0110H when unparsable).
- **Query/Retrieve.** Retrieve identifiers are in ascending tag order (PS3.5 §7.1), carry
  (0008,0005) and encode non-ASCII values instead of emptying them (PS3.4 C.4.2.1.4.1), and never
  duplicate a key. `parseQueryResponse` no longer merges the elements of nested sequence items into
  the top level (PS3.5 §7.5). `InstanceResult.rows`/`columns` read the US value (were always nil).
  `DICOMValidator` takes its transfer syntaxes from DICOMCore's PS3.6 registry (was a hand list
  with two unregistered and 29 missing UIDs).
- **Modality Worklist / MPPS.** The MWL identifier omits (0008,0005) for the default repertoire
  (PS3.4 C.2.2.2 forbids a zero-length value) and decodes undeclared responses as the default
  repertoire first (PS3.5 §6.1.2). MPPS sends Scheduled Procedure Step ID empty when unknown
  (Type 2) instead of "1", and builds its command sets through `NCreateRequest`/`NSetRequest`.
- **Print Management (PS3.4 Annex H, PS3.3 C.13).** The N-ACTION-RSP names the Film Session /
  Film Box as Affected SOP Instance and returns the Print Job in Referenced Print Job Sequence
  (2100,0500) (Tables H.4-3/H.4-8); the SCU reads the job UID only from there. The Meta SOP
  Classes cover only Film Session, Film Box, the Image Box and Printer (Tables H.3.2.2.1-1/-2-1);
  Presentation LUT, Annotation Box and Print Job need their own context. Statuses: C600 for a film
  session without film boxes, B602/B603 (empty page, printed) instead of a failure, 0123H for an
  unknown Action Type, 0211H for an unrecognised operation; `PrintSCPStatus.filmSessionPrinting`'s
  documentation corrected to the C600 meaning. Execution Status Info is a CS defined term. The
  colour image box is sent and parsed colour-by-plane with Planar Configuration 1 and Bits
  Allocated 8 (Table C.13-5). Print Job N-GET returns the Table C.13-8 attributes (Originator
  added, Number of Copies removed). A Printer N-GET without a data set reports UNKNOWN, not NORMAL.
- **Docs.** TLSConfiguration cited a PS3.8 "Annex A" that does not exist (the profiles are PS3.15
  B.12/B.13; TLS 1.0/1.1 conform to none); AuditLogger claimed PS3.15/ATNA alignment for a custom
  schema; UserIdentity cited Supplement 99 for JWT; "16KB" defaults corrected to 64 KB; PS3.4/3.7/3.3
  section citations corrected throughout.
- **Pending owner approval (not changed):** `MediumType.mammoFilmClearBase/BlueBase` raw values
  are `MAMMO CLEAR` / `MAMMO BLUE`; PS3.3 C.13.1 defines `MAMMO CLEAR FILM` / `MAMMO BLUE FILM`.

### Changed — DICOMDictionary generated from the DICOM 2026a text (2026-09-28)

Audit report: `DICOMDICTIONARY_STANDARD_IMPLEMENTATION.md`. Every table the module carries is now
generated from the frozen NEMA DocBook and re-checked row by row by `Scripts/diff_dictionary.py`
(0 differences against PS3.4, PS3.6 and PS3.7 2026a).

- **Data Element Dictionary** (`Resources/DataElementDictionary.txt`): `Scripts/generate_full_dictionary.py`
  now reads PS3.6 Tables 6-1, 7-1, 8-1, 9-1 and PS3.7 Tables E.1-1, E.2-1 instead of the installed
  pydicom's dictionary (2.4.4, which predates 2026a). 5,102 → 5,326 rows: 227 elements that were
  missing (thermography and NDE group 0014, patient pronouns / gender identity / sex parameters
  (0010,0011)–(0010,0047), Ethnic Groups, photoacoustic (0018,982x), clinical-trial issuer IDs,
  Synthetic Data, diagnosis code sequences, (0006,0001) Current Frame Functional Groups Sequence …)
  are present, so DICOMKit no longer writes them as `UN`. Retired flags corrected for (0010,2160),
  (0038,0004), (0070,1807), (0070,1808) (now retired) and (3004,0012) (not retired). Keywords
  corrected: (003A,0320) `SummarizedFilterLookupTableSequence`, (003A,0325) `AnalogFilterTypeCodeSequence`.
  Cells are verbatim: names keep `µ`, (5200,9230) is "Per-Frame …", LUT Data VM is `1-n or 1`, and
  the six rows whose PS3.6 Name/Keyword is blank now load with an empty name and keyword (the
  three fully blank rows with VR `UN`) instead of the invented `Unknown` / `Retired-blank`.
  The 46 group 0000 command elements are unchanged (they match PS3.7). The file starts with `#`
  comment lines carrying the provenance marker; the loader and `Scripts/audit_tags.py` skip them.
- **`DataElementDictionary`**: new `allEntries`; `lookup(keyword:)` returns nil for an empty keyword.
- **`UIDDictionary`**: the registry is now every row of PS3.6 2026a Table A-1 (465 UIDs, generated
  into `UIDDictionaryEntries.swift` by `Scripts/generate_uid_dictionary.py`) instead of 47 hand-written
  rows. All 63 Transfer Syntaxes (JPEG-LS, JPEG XL, JPIP, SMPTE ST 2110, Deflated Image Frame
  Compression, Encapsulated Uncompressed, the retired JPEG processes …), 311 SOP Classes, Meta SOP
  Classes, Well-known SOP Instances, Coding Schemes, Service Classes, LDAP OIDs. Names are verbatim
  (e.g. "Explicit VR Big Endian (Retired)"); two keywords corrected to the registry's:
  `JPEG2000MCLossless` (.4.92) and `JPEG2000MC` (.4.93). The two Fragmentable HEVC syntaxes that no
  PS3.6 edition registers stay available as `UIDDictionary.unregisteredEntries` with
  `registered == false` and a name that says so.
- **`UIDEntry`** gains `retired` and `registered` (both defaulted, additive). **`UIDType`** gains
  `serviceClass`, `applicationHostingModel`, `mappingResource`, `synchronizationFrameOfReference`
  (source-breaking for exhaustive switches; `UIDManager.uidTypeDescription` updated).
- **`StorageSOPClass`**: `allUIDs` is now exactly PS3.4 2026a Table B.5-1 (170 Storage SOP Classes,
  generated by `Scripts/generate_storage_sop_classes.py`; was 78). The 92 added include 18 SR
  classes (X-Ray Radiation Dose SR, the CAD SRs, Procedure Log, …), 20 RT classes (RT Ion Plan and
  the 2nd-generation RT objects), 9 presentation states, 15 ophthalmic objects, Parametric Map,
  Encapsulated STL/OBJ/MTL, Photoacoustic, Thermography and more — a C-GET or C-MOVE of a study in
  any of them previously transferred zero instances. New `retiredUIDs` / `retiredUIDSet` (Table
  B.6-1, 4 classes); `isStorage(_:)` recognises both, `allUIDs` (what the SCU proposes) holds only
  current classes. Common imaging classes keep the low presentation-context IDs. **Known limit:**
  the C-GET SCU can propose at most 127 storage contexts, so the last 43 classes in the list are
  not proposed until DICOMNetwork gains a selection strategy (dictionary report, D21).
- **Docs**: the DocC page showed a `.shared` API and a `DictionaryEntry` symbol that never existed;
  rewritten against the real API.
- **Tests**: `Standard2026aTests` pins row counts, sampled rows, corrected rows, the command
  elements, the UID registry (463 + 2 unregistered) and the storage list; the 64-bit VR test now
  says CP 1818 / CP 1819 correctly.

### Tooling — standard verification (2026-09-25)

- `Scripts/nema_docbook.py`: fetches a frozen NEMA DocBook part (refusing a copy whose subtitle
  does not name the requested edition), lists its tables and dumps any table as TSV for scripted
  diffs.
- `Scripts/check_nema_markers.py`: checks that every Swift file of a module carries a well-formed
  `NEMA-verified` marker; exits 1 otherwise. DICOMCore: 104 of 104 files. Seven early markers were
  normalised to the standard format.

### Changed — SR templates generated from PS3.16 2026a (P10, 2026-09-25)

- **SR templates**: `SRCoreTemplates.swift` and `SRMeasurementTemplates.swift` are now
  generated from the PS3.16 2026a TID tables by `Scripts/generate_sr_templates.py`. The rows
  written by hand were a subset that diverged from the standard (30 of 142 rows matched, no
  INCLUDE rows). The set grows from 13 to 40 templates (the 13 plus every template they
  include), 337 rows. New types include `TID301MeasurementContent`,
  `TID320ImageOrSpatialCoordinates`, `TID1502TimePointContext`, `TID4019AlgorithmIdentification`
  and `TID4108TrackingIdentifier`; `displayName` is the PS3.16 title.
- **`TemplateRow`** (source-breaking): `relationshipType` and `valueType` are optional; new
  `isByReference`, `valueMultiplicity`, `includeParameters`, `conceptNameText`,
  `valueSetText`, `isInclude`. New `TemplateParameter`, `TemplateParameterBinding`,
  `TemplateParameterValue`. `ConceptNameConstraint` adds `.definedTerm`,
  `.fromBaselineContextGroup`, `.parameter`; `ValueConstraint` adds `.definedTermCode`,
  `.fromBaselineContextGroup`, `.parameter`, `.units`. `SRTemplate` adds `isOrderSignificant`,
  `isRoot`, `parameters` (defaulted). `TemplateRegistry.builtInTemplates`.
- **`TemplateValidator`**: validates the content tree against the nested rows, expands INCLUDE
  rows with their parameter bindings, requires M rows, counts VM, reports extra content only
  in Non-extensible templates, and ignores Code Meaning when comparing codes. Pass the root
  content item (e.g. the TID 1500 CONTAINER).

### Added — PS3.6 2026a transfer syntaxes, TABLE content items, SNOMED measurement concepts (2026-09-25)

- **`TransferSyntax`**: the 22 Table A-1 syntaxes that were missing are registered:
  Encapsulated Uncompressed Explicit VR LE (.1.98), JPIP HTJ2K Referenced (.4.204) and
  Deflate (.4.205), SMPTE ST 2110-20/30 (.7.1–.7.3), Deflated Image Frame Compression
  (.8.1), the 14 retired JPEG processes (.4.52–.4.56, .4.58–.4.66), RFC 2557 MIME (.6.1),
  XML Encoding (.6.2) and Papyrus 3 (1.2.840.10008.1.20). `from(uid:)`, `allKnown`,
  `displayName`, `isLossless` and `lossyImageCompressionMethod` cover them, and a new
  `isRetired` flags the 18 retired syntaxes. They are identified only; no codec was added.
- **TABLE content items** (PS3.3 C.18.10): `ContentItemValueType.table`,
  `TableContentItem` (rows, columns, row/column definitions, sparse cells with text,
  decimal, floating-point, integer, date-time, coded or content-item-reference values),
  `AnyContentItem.table`, the (0040,A801–A808) and (0040,A301) tags, and TABLE in
  `allowedValueTypes` for Extensible SR and Enhanced X-Ray Radiation Dose SR. The DICOMKit
  SR serializer and parser write and read the macro. `ContentItemValueType.allCases` grows
  from 15 to 16, so exhaustive switches on it need a `.table` case.
- **`SNOMEDCode`** gains the measurement concepts Diameter, Long Axis, Short Axis,
  Perpendicular Axis, Length, Width, Area, Volume, Circumference, Perimeter and Mode.

### Changed — three Tag constants renamed to their PS3.6 keywords (2026-09-25)

- `Tag.applicationSetupSequence` (was `brachyApplicationSetupSequence`),
  `Tag.maximumFractionalValue` (was `maxFractionalValue`) and
  `Tag.verticesOfThePolygonalShutter` (was `verticesOfPolygonalShutter`). The old names
  remain as deprecated aliases.

### Fixed — coding scheme designators, LOINC names and SR template concept codes (2026-09-25)

- **ICD-10 designators.** `CodingScheme.icd10CM` and `CodingSchemeDesignator.ICD10CM` used
  "I10", which PS3.16 Table 8-1 assigns to WHO ICD-10; ICD-10-CM is **"I10C"**. Both now use
  I10C, and `CodingScheme.icd10` / `CodingSchemeDesignator.ICD10` were added for I10
  (2.16.840.1.113883.6.3). `CodingScheme.acr` gained its UID 2.16.840.1.113883.6.76.
- **LOINC names.** Four `LOINCCode` constants named the wrong concept: `radiologyReport`
  (18748-4) is "Diagnostic imaging study", `technique` (55111-9) is "Current imaging procedure
  descriptions", `mriReport` (24590-2) is "MR Brain" and `ultrasoundReport` (18750-0) is
  "Cardiac electrophysiology study". The constant names are kept; check that they still mean
  what your code intends.
- **SR template concept codes.** In `SRCoreTemplates` and `SRMeasurementTemplates`: Subject UID
  is DCM 121028 (was 121030, "Subject ID"); "Referenced Segment" is DCM 121191 (was 121233,
  "Source image for segmentation", in two rows); "Source of Measurement" is DCM 121112 (was
  121405, "Population description"); "Maximum 3D Diameter" is IBSI L0JK (was DCM 121217, a
  volume-estimation method); mm2/mm3 meanings are "square millimeter"/"cubic millimeter";
  SCT 373098007 is "Mean". (The row structures were then regenerated from PS3.16 2026a; see
  "SR templates generated from PS3.16 2026a" above.)
- Doc citations corrected in `ContentItemTypes`, `ContentItemValueType`, `PrivateCreator`,
  `PrivateDataElement`, `PixelDataDescriptor`, `PaletteColorLUT` and the codec files.

### Fixed — Extended Offset Table frame indexing and RLE row boundaries (2026-09-25)

- **`EncapsulatedPixelData.makeFrameIndex(extendedOffsets:)`** now reads Extended Offset
  Table (7FE0,0001) values as PS3.3 C.7.6.3.1.8 defines them: the offset of each frame's
  Item Tag from the first Item Tag after the Basic Offset Table, headers included (the same
  reference point as the Basic Offset Table). They were treated as header-less, so every
  conformant table failed the consistency check and frame access fell back to nil.
- **`RLECodec.encodeFrame`** encodes each image row separately; PS3.5 G.3.1 forbids a run
  from crossing a row boundary. Output stays lossless and decodes with any conformant
  decoder; encoded size may grow by a few bytes per row on uniform images.

### Fixed — `DICOMUniqueIdentifier.isSOPClass` / `isTransferSyntax` (2026-09-25)

- Both now test membership in the PS3.6 2026a Table A-1 registry, exposed as
  `DICOMUniqueIdentifier.sopClassUIDs` (311) and `transferSyntaxUIDs` (63). The previous
  prefix heuristic returned false for Verification, Storage Commitment, every Print
  Management SOP Class and 24 others, and true for Meta SOP Classes, Service Classes and
  Well-known SOP Instances; `isTransferSyntax` missed the retired Papyrus 3 syntax.
- VR value-type docs: `DICOMTime` says 14 bytes maximum, as the standard does, not 16.

### Changed — Tag constants text-diffed against PS3.6 2026a (2026-09-25)

- All 971 `Tag` constants in `Tag+*.swift` were checked against PS3.6 2026a; every tag and
  (group, element) pair is correct. Doc comments now mark five retired elements (Ethnic
  Group (0010,2160) was retired in 2025a in favour of (0010,2161)/(0010,2162)), and four
  VR/VM notes and three element names were corrected. No constant changed value.

### Changed — SR template metadata aligned with PS3.16 2026a (2026-09-25)

- **`RequirementLevel`** now has the four Requirement Type symbols of PS3.16 §6.1.7:
  `mandatory` (M), `mandatoryConditional` (MC), `userOption` (U) and the new
  `userOptionConditional` (UC). `userConditional` is a deprecated alias of `userOption`
  (U means "User Option", not "User Conditional"). `conditional` (C) is deprecated: PS3.16
  has no such type; it is no longer in `allCases`, which stays at four entries (C out, UC in).
- **`TemplateIdentifier`**: `imageLibraryEntry` is now TID **1601**, which is what PS3.16
  calls Image Library Entry; TID 320 ("Image or Spatial Coordinates") is available as
  `imageOrSpatialCoordinates`. `cadAnalysis` and `cadFinding` are unavailable: TID 4000 is
  `mammographyCADDocumentRoot` and TID 4019 is `algorithmIdentification`. Doc titles for
  TIDs 1400, 1410, 1411, 1420 and 1501 now match the standard.
- **`TID320ImageLibraryEntry` is renamed `TID1601ImageLibraryEntry`** (deprecated alias
  kept). Its rows always modelled TID 1601; it now registers under 1601, so
  `TemplateRegistry.shared.template(tid: 320)` returns nil.

### Fixed — `PrivateTagDictionary` vendor entries (2026-09-25)

- 8 of the 15 built-in vendor definitions disagreed with the DCMTK and GDCM private
  dictionaries and were corrected: Siemens CSA header versions (0029,xx09/xx19) are LO;
  Siemens MR (0019,xx0D) is CS "Diffusion Directionality", (0019,xx0E) is FD "Diffusion
  Gradient Direction" and (0019,xx0F) SH "Gradient Mode" is added; GE (0009,xx01) "Full
  Fidelity" is LO; GE (0019,xx0F) is DS "Horizontal Frame Of Reference" (not the Protocol
  Data Block); Philips "Chemical Shift" is (2001,xx01), (2001,xx03) is FL "Diffusion
  B-Factor" and (2001,xx08) is IS "Phase Number".

### Changed — plumbing files checked for Bucket C1 of the DICOMCore audit (2026-09-25)

- **`PixelDataError.unsupportedTransferSyntax`'s `explanation`** now names the offending
  syntax (from `TransferSyntax.displayName`) and lists the decoders registered in
  `CodecRegistry`, instead of a fixed sentence that omitted JPEG-LS, HTJ2K, JPEG XL and JP3D.
  The doc comment no longer lists JPEG-LS, JPEG 2000 Part 2 and HTJ2K as unsupported.
- **Citations corrected** (comments only): `ByteOrder.swift` now cites PS3.5 §7.3 for byte
  ordering (Big Endian retired, see PS3.5 2016b) instead of §7.1.1/§7.1.2;
  `J2KCodestreamInspector.swift` cites A.4.4 for the HTJ2K syntaxes instead of A.4.6;
  `DICOMError.unsupportedTransferSyntax` lost a stale "v0.1 supports…" note.
- `UIDGenerator` gained tests asserting PS3.5 §9.1 on generated UIDs, and its doc comment
  says that the default root is OFFIS DCMTK's.

### Fixed — SR content-item enumerations aligned with PS3.3 2026a C.18 (2026-09-25)

- **`TemporalRangeType.multisegment`** (`MULTISEGMENT`) added; PS3.3 C.18.7.1.1 defines six
  Temporal Range Types and the enum had five.
- **`GraphicType.polygon` is deprecated.** PS3.3 C.18.6.1.2 defines POINT, MULTIPOINT,
  POLYLINE, CIRCLE and ELLIPSE for 2D SCOORD; a closed shape is a POLYLINE whose first
  and last vertices coincide. POLYGON exists only for SCOORD3D (`GraphicType3D.polygon`
  is unchanged). `GraphicType.allCases` now lists the five standard values, so its count
  changes from 6 to 5.
- **`NumericValueQualifier`** gains the seven CID 42 qualifiers it lacked (Divide by
  zero, Measurement failure, Measurement not attempted, Calculation failure, Value out
  of range, Value unknown, Value indeterminate), a `code` property giving the DCM code
  (114000–114011) for Numeric Value Qualifier Code Sequence (0040,A301), and
  `init?(code:)`. It is now `CaseIterable`.

### Changed — `DICOMCode`: constants corrected against PS3.16 2026a Annex D (2026-09-25)

- **64 of the 93 `DICOMCode` constants disagreed with PS3.16 Annex D.** 21 are corrected
  in place (e.g. `summary` is 121111, not 121070; `impression` 121073; `conclusion`
  121077; `mammographyCADReport` 111036; `study` 113014; `series` 113015;
  `clinicalHistory` keeps 121060 but its meaning is "History").
- **Source-breaking:** 43 constants are removed, marked `unavailable` with a message
  giving the correct reference. 13 were SNOMED or NCIt concepts that a DCM-only type
  cannot hold (`diameter`, `volume`, `length`, `longAxis`, `shortAxis`, ...; the message
  names the SCT code). 7 were relationship types, not codes (`contains`,
  `hasProperties`, `inferredFrom`, ...; use `RelationshipType`). 23 had no DCM code with
  that meaning at all (e.g. 121401–121408 are Derivation, Normality, Level of
  Significance, ..., not Mean/Min/Max/Std Dev). `measurement` and `measurementReport`
  point to `measurementGroup` and the new `imagingMeasurementReport` (126000).

### Changed — `ContextGroup`: the built-in CIDs are now generated from PS3.16 2026a (2026-09-25)

- **Seven of the nine built-in context groups carried CID numbers that PS3.16 assigns
  to other groups, and members PS3.16 does not define** (e.g. `findingSite` was
  numbered CID 4021, which is "PET Radiopharmaceutical"; `derivation` was CID 6024,
  "Depth"; the SRT codes in `quantitativeTemporalRelation` and `breastImagingFinding`
  exist in no CID). Only `laterality` was correct, and `measurementReportDocumentTitles`
  had two wrong meanings.
- **New groups, generated from the PS3.16 2026a CID tables** with "Include CID" rows
  expanded: `relativeTime` (CID 3600), `commonAnatomicRegion` (CID 4031, 119 codes),
  `recistDefinedLesionResponse` (CID 6144), `linearMeasurementUnit` (7460),
  `areaMeasurementUnit` (7461), `volumeMeasurementUnit` (7462), `breastImagingFinding`
  (now CID 6054, 47 codes) and `measurementType` (CID 3627). Each carries the
  standard's Type and Version.
- **Source-breaking:** `imagingObservations` is removed (PS3.16 has no such group).
  `quantitativeTemporalRelation`, `findingSite`, `responseEvaluation`,
  `roiMeasurementUnits` and `derivation` are deprecated aliases of the new groups;
  their members differ, so code that matched the old invented codes must change.
  `ContextGroupRegistry` no longer registers CIDs 218, 4021, 6147, 7464, 12301 or 6024.

### Fixed — `SRDocumentType`: two missing SOP Classes and corrected Value Type constraints (2026-09-25)

- **New public enum cases `SRDocumentType.procedureLog` (1.2.840.10008.5.1.4.1.1.88.40)
  and `.waveformAnnotationSR` (.88.77).** All 20 current SR Storage SOP Classes of
  PS3.6 2026a Table A-1 are now covered. `isSRDocument(sopClassUID:)` also recognizes
  the four retired "Trial" SR SOP Classes (.88.1–.88.4), which have no IOD in PS3.3
  and therefore no `SRDocumentType`.
  **Source-breaking for exhaustive switches** over `SRDocumentType`.
- **`allowedValueTypes` was wrong for 16 of the 18 document types.** Each set is now
  the Enumerated Values list of its IOD's Content Constraints in PS3.3 2026a A.35,
  generated from the DocBook text. Basic Text SR gains WAVEFORM and Enhanced SR gains
  SCOORD and TCOORD, so valid documents are no longer rejected. Key Object Selection,
  the CAD SRs and the Radiation Dose SRs lose DATETIME or DATE/TIME, which their IODs
  do not permit, so `validateOnBuild` now flags those. TABLE, permitted by Extensible
  SR and Enhanced X-Ray Radiation Dose SR, is not yet a `ContentItemValueType`.

### Changed — `DICOMDIRProfile` is now a struct covering all PS3.11 2026a profiles (2026-09-25)

- **`DICOMDIRProfile` is a `RawRepresentable` struct, not an enum.** PS3.11 2026a
  defines 64 Media Storage Application Profile identifiers, and the enum had 3 of
  them. Of its other 5 values, `STD-GEN-DVD`, `STD-GEN-USB` and `STD-GEN-SEC` are
  not identifiers (the real ones name the compression or media, e.g.
  `STD-GEN-DVD-JPEG`), `STD-CTMR-xxxx` and `STD-US-xxxx` were placeholders, and
  `STD-MAM-xxxx` does not exist in PS3.11. All 58 fixed identifiers are now static
  constants, the 24 Ultrasound identifiers are built with
  `ultrasound(_:frames:media:)`, and `isStandard` reports whether PS3.11 defines
  a value. `init(rawValue:)` stays failable and still accepts the five old
  strings, mapping them to the profile they most likely meant, so saved settings
  and scripts keep working.
  **Source-breaking:** exhaustive `switch` statements over `DICOMDIRProfile` no
  longer compile. The old constant names are deprecated aliases.

### Fixed — DICOMDIR record types and hierarchy validation per PS3.3 2026a (2026-09-24)

- **New public enum cases on `DirectoryRecordType`:** `plan`, `tract`,
  `assessment`, `radiotherapy`, `annotation`, `inventory` and `wfPresentation`
  (current), plus `printQueue`, `filmSession`, `filmBox`, `imageBox` and `mrdr`
  (retired, for reading legacy DICOMDIRs). All 35 current and 16 retired
  Enumerated Values of Directory Record Type (0004,1430) in Table F.3-3 are now
  covered. **Source-breaking for exhaustive switches** over `DirectoryRecordType`.
- **`DICOMDirectory.validate()` follows Table F.4-1.** It previously accepted
  only 7 of the 25 record types allowed under SERIES, and rejected PRIVATE
  children, so valid DICOMDIRs failed validation. Root-level records are now
  checked too. Retired record types are tolerated wherever they appear.

### Fixed — Specific Character Set (0008,0005): all 2026a Defined Terms, correct decoding, ISO 2022 per PS3.5 (2026-09-24)

- **New public enum cases on `CharacterSetEncoding`: `isoIR203` (Latin-9),
  `isoIR58` (Simplified Chinese GB 2312), `gb18030` and `gbk`.** With these, all
  20 Defined Terms of PS3.3 2026a Tables C.12-2 to C.12-5 are recognized, and so
  are the escape sequences ESC - b and ESC $ ) A.
  **Source-breaking for exhaustive switches** over `CharacterSetEncoding`.
- **Nine character sets were decoded with the wrong encoding.** Latin-3 and
  Latin-4 were decoded as Latin-1. Greek, Arabic, Hebrew, Cyrillic, Turkish,
  Korean and Thai were decoded as UTF-8, so non-ASCII text came out wrong or
  empty. Each set now uses its ISO 8859 part, EUC-KR or TIS-620.
- **ISO 2022 code extensions rewritten to follow PS3.5 §6.1.2.5.** G0 is read in
  GL and G1 in GR. The Value 1 sets are active again after control characters.
  Unrecognized escape sequences are skipped. JIS X 0208/0212, KS X 1001 and
  GB 2312 are decoded correctly. The encoder designates each set only when a
  character needs it, and restores Value 1 before delimiters and at the end of
  the value. Output matches the PS3.5 Annex H.3.1, H.3.2 and I.2 examples byte
  for byte.
- **An empty Value 1 is kept.** `"\\ISO 2022 IR 87"` previously lost the empty
  Value 1, so JIS X 0208 took over the default repertoire's role.

### Added — `PhotometricInterpretation.xyb` (JPEG XL XYB color) (2026-09-24)

- **New public enum case `PhotometricInterpretation.xyb` (`"XYB"`).** XYB is a
  Defined Term in PS3.3 2026a C.7.6.3.1.2 (Supplement 232). PS3.5 Table 8.2.15-1
  allows it with the JPEG XL transfer syntaxes, with Samples per Pixel 3.
  Previously `parse("XYB")` returned `nil`, so DICOMKit built no pixel descriptor
  for such a file and it could not be displayed.
  **Source-breaking for exhaustive switches:** code that switches over
  `PhotometricInterpretation` without a `default` must add a `.xyb` case.
- **Transcoding a JPEG XL XYB dataset now writes Photometric Interpretation `RGB`.**
  The JPEG XL decoder outputs RGB samples, and PS3.3 says "Images in XYB transcoded
  to other Transfer Syntaxes will use RGB". Before this change, an unrecognized
  value was also read as `MONOCHROME2` in the transcoder, so XYB colour images
  were described to re-encoders as monochrome.

### Fixed — OV, SV and UV (64-bit VRs) are fully supported (2026-09-24)

- `DataElement` gains `uint64Value`, `int64Value`, `uint64Values` and
  `int64Values`.
- Big/little-endian transcoding now byte-swaps OV, SV and UV (PS3.5 §7.3).
  Previously their values were left unswapped.
- DICOM JSON: OV is encoded as InlineBinary, and SV and UV as Number or String
  (PS3.18 Table F.2.3-1).
- Correction to 2.2.16: the 64-bit VRs came from **CP 1819**, not CP-1818 as
  that entry says.

### Added — Full DICOM 2026a modality coverage and a canonical `Modality` type (2026-09-23)

- **`DICOMCore.Modality`** — one type for Modality (0008,0060), carrying every
  PS3.3 C.7.3.1.1.1 defined term in 2026a: **79 current codes and 18 retired**,
  against the 26 the app previously recognized. It is a `struct`, not an `enum`,
  because Modality is a *Defined Term* rather than an Enumerated Value: private
  and vendor codes are legal on the wire, so `init(unchecked:)` round-trips any
  CS value losslessly while `isStandard` / `isRetired` / `isCurrent` report the
  truth about it. A `Category` (cross-sectional, radiography, ultrasound,
  visible light, ophthalmic, waveform, radiotherapy, derived, …) lets UI group
  79 codes and lets icons, colors and presets fall back per family.
- **Ophthalmic imaging is representable at all.** `OPT`, `OPTENF`, `OPTBSV`,
  `OCT`, `IVOCT`, `OPM`, `OAM`, `OPV`, `KER`, `LEN`, `SRF`, `VA` and `IOL`
  appeared nowhere in the codebase before; only `OP` existed.
- **`--modality` is validated for the first time.** No CLI checked the option at
  all, so a typo reached the PACS as a filter that silently matched nothing.
  `ModalityOptionValidator` now backs `dicom-query`, `dicom-qr`, `dicom-mwl`,
  `dicom-wado`, `dicom-mpps`, `dicom-archive`, `dicom-image`, `dicom-pdf` and
  `dicom-video`: an unknown code warns with the nearest defined terms ("Did you
  mean CT, CFM, CR?") and is still sent, since private codes are legal; a
  retired code warns; an alias is normalized. `--strict-modality` turns any of
  those into an error before the tool connects.
- **`dicom-tags --list-modalities`** prints all 79 codes grouped by category.
  (It lives here because every tool that takes `--modality` has a required
  positional argument, so a listing flag on those commands could never run.)
- **A sectioned `ModalityPicker`** replaces free-text modality fields in
  Networking, Data Exchange and Archive Management. It keeps an out-of-list
  bound value — a retired or private code already in the data — selectable
  rather than silently resetting the field.

### Changed

- **`ModalityMapping.StandardModality` is removed.** Its 26-code enum is
  replaced by `DICOMCore.Modality`; `allCodes`, `systemImage(for:)`,
  `fullName(for:)` and `normalize(_:)` keep their signatures, and `allCodes`
  grows from 26 to 79. The type was `public` but unreachable from outside the
  package (`DICOMStudio` is not a published product) and was referenced only by
  its own file.
- **`RT` is demoted to a legacy alias.** It was never a DICOM code: the standard
  defines eight distinct RT codes, and `normalize` collapsed `RTPLAN`, `RTDOSE`
  and `RTSTRUCT` onto a single invented `RT`, losing which object it was. Each
  now keeps its own name and identity; bare `RT` resolves to `RTIMAGE` so
  existing data still renders. **RT series will show different icons and names
  than before.**
- **One alias table for the whole project.** Two existed and disagreed:
  `ModalityMapping.normalize` knew `MRI`/`PET`/`RT*`/`PDF`, while
  `WindowLevelPresets` separately knew `MRI`/`RG`/`RF`. `Modality.normalized`
  is now the single table, and also absorbs the non-DICOM spellings `XR` and
  `DR` (→ `DX`) and `SPECT` (→ `NM`) that were buried in a private switch.
- **Four divergent icon/color/preset maps now agree.** `ModalityIcon` (26
  codes), `DICOMFileDropHelpers` (9 groups, using the non-DICOM `XR`),
  `StudioTheme` (4 color groups) and `ThumbnailHelpers` (7 groups) each had
  their own switch; CT was `lungs` in one and `cylinder.split.1x2` in another.
  All four now resolve through `Modality`/`Modality.Category`.
- **Window/level presets: 25 → 37**, adding `RG`, `PX`, `IO`, `BMD`, `IVUS` and
  `OPT`. Presets remain deliberately curated: display-ready modalities (US, ES,
  GM, SM, XC, …) and non-image objects (SR, PR, KO, SEG, DOC) still have none,
  because a fixed window for them would be an invented number, not a clinical one.
- **Inbound HL7 and FHIR modality values are normalized** rather than written
  straight into (0008,0060) as received.
- **`SC` and `VL` are recognized but never offered.** Neither is a Defined Term
  (verified absent from PS3.3 C.7.3.1.1.1 and CID 32 in 2026a). `SC` is not
  merely unlisted: PS3.3 C.8.6.1 makes Modality Type 3 on the Secondary Capture
  IOD and says the value describes "the equipment that originally created or
  generated the data, not the equipment performing the digitization or capture"
  — so a digitized film radiograph should carry `CR`/`XA`, not `SC`. Existing
  files using them still parse and display; nothing new is written with them.
- **IOD validation resolves aliases.** The six per-IOD checks compared raw
  strings, so a file with `Modality = "MRI"` was reported as *"MR Image Storage:
  Modality must be 'MR'"*. A new Defined-Term check also warns on unknown,
  retired and conventional codes.

### Fixed

- **Codes the library itself emitted were not displayable.** `WaveformBuilder`
  writes `AU`, `EPS` and `RESP`; `EncapsulatedDocumentWorkflow` writes `M3D`.
  None were in the app's 26-code list, so they rendered with the unknown-modality
  icon and a raw uppercased string instead of a name. A regression test now
  asserts every modality the library writes is displayable.
- **`XX` is no longer written as a modality.** `StudyOrganizer` and
  `FrameSplitter` used it as a filename placeholder; it is not a DICOM code, and
  is now `OT`.
- **Duplicated Enhanced-IOD logic.** `["CT","MR","PT"].contains(modality)` and
  `modality == "MR"` existed verbatim in both `FunctionalGroupBuilder` and
  `FrameMerger`. Both now call one documented
  `Modality.usesEnhancedFrameTypeDescriptors`.
- **Six defined terms had no icon.** `BI`, `DG`, `LS`, `OSS`, `PA` and `TG` were
  offered in pickers but fell back to the unknown-modality symbol.


### Fixed — Hanging Protocol selector values and five never-run test suites (2026-09-18, audit Phase 3)

- **Hanging Protocol selector values** — `HangingProtocolSerializer` wrote an Image Set
  Selector's values under the selected attribute's own tag (a Modality selector put "CT" in
  (0008,0060) as LO inside the selector item), and the parser read them back the same way.
  PS3.3 Table C.23.4-1 carries them in Selector Attribute VR (0072,0050) plus the Selector
  *xx* Value element for that VR ((0072,005E)–(0072,0083)). Both now do; every VR is covered,
  including the binary ones and Selector Code Sequence Value (0072,0080) for SQ attributes.
  `ImageSetSelector` gains `attributeVR` (nil = dictionary lookup, required for private
  attributes), `sequencePointer` (0072,0052) and `codeValues`. The parser still reads the
  old layout, and a Selector *xx* Value with no (0072,0050) beside it.
- **Tests** — the `ParametricMap`, `RadiationTherapy`, `Segmentation`, `StructuredReporting`
  and `Waveform` suites in `DICOMKitTests` were excluded from the build and had never run
  (`DICOM_TAG_AUDIT_FINDINGS.md` #54), as were the DisplaySet, Matcher and ImageSetDefinition
  Hanging Protocol suites. They are in the allowlist now, together with the
  `DataSet` test builders they depend on, which write each element in its dictionary VR.
  Running them surfaced (audit §J):
  - **CAD SR** — `CADFindingsExtractor` looked for the probability under (111023, DCM) while
    the builders and TID 4021/4104 use (111047, DCM), so every finding was dropped; the
    manufacturer was expected as CODE but written as TEXT; characteristics overwrote the
    finding type. CIRCLE coordinates were written as (cx, cy, r) instead of the PS3.3
    C.18.6.1.2 centre + circumference point, and read back with the wrong radius.
  - **Measurement Report (TID 1500)** — `addQualitativeEvaluation` dropped the concept name;
    the extractor did not look inside the Qualitative Evaluations container.
    `addMeasurementGroup` gains `finding:` and `findingSite:`.
  - **Parametric Map** — Real World Value Slope/Intercept were read as DS; they are FD, so
    no linear mapping ever parsed.

### Fixed — DICOM key-set conformance per service (2026-09-18, audit Phase 2)

Each network service's request/response key set was checked against the standard's table
(`DICOM_TAG_AUDIT_PHASE2_FINDINGS.md`). Q/R C-FIND/C-MOVE, Storage Commitment and Print were
already conformant; MPPS, MWL and the QIDO-RS server were not.

- **MPPS** — Referenced SOP Class UID was hard-coded to Secondary Capture for every image;
  Protocol Name (Type 1) was never sent; eight Type 2 attributes were missing; Performing
  Physician and Study Instance UID were sent at root where the table forbids them; the
  `attributes` extension point was silently dropped; the Scheduled Step Attributes Sequence was
  sent in N-SET (forbidden — now opt-in `--legacy-nset-scheduled-attributes`). New
  `MPPSPerformedSeries` / `MPPSReferencedInstance` / `MPPSCodedEntry` models and matching
  `dicom-mpps` options.
- **MWL** — responses were decoded as ASCII (non-ASCII names became nil); code sequences and
  Referenced Study Sequence were neither requested nor storable; fifteen Type 2 return keys were
  not requested. `WorklistItem.sequences`, `requestedProcedureCode`, `scheduledProtocolCodes`,
  `referencedStudies`, patient-safety attributes; `WorklistQueryKeys.matching/spsMatching`.
- **Q/R** — series/instance queries without the parent UIDs are rejected locally with a PS3.4
  C.4.1.2.1 message instead of a server 0xA900; `QueryKeys.matching` no longer emits duplicate
  elements for a tag.
- **QIDO-RS server** — StudyDate/StudyTime/ModalitiesInStudy/StudyID/SeriesNumber/SOPClassUID
  filters were ignored; hex-tag `{attributeID}` form was rejected; Retrieve URL, Instance
  Availability, Referring Physician, Study ID, Birth Date/Sex missing from results.
- **QIDO-RS client** — PPS Start Time and Request Attributes Sequence filter/result support.
- **Print** — optional Illumination / Reflected Ambient Light with a Presentation LUT.

### Fixed — DICOM attribute ↔ tag audit (2026-09-18)

A package-wide audit of every hand-written DICOM tag against the bundled PS3.6 dictionary
(`DICOM_TAG_AUDIT_FINDINGS.md`), prompted by the MWL Requested Procedure Description bug
((0032,1070) where (0032,1060) was meant). 36 wrong tags corrected; none were in the
network layer or the CLI tools.

- **Hanging Protocol** — thirteen `Tag+HangingProtocol` constants carried a neighbour's tag
  (Number of Priors Referenced, User Group Name, Image Set Selector Sequence/Usage Flag,
  Selector Attribute/Value Number, …). Parser and serializer now use the PS3.6 group 0072
  layout; US attributes are read as US (they were read as IS and always came back nil).
- **Real World Value LUT** — LUT-form mappings never parsed: first/last value were read from
  LUT Data and Double Float *Last*, and LUT data from First Value Mapped. `doubleFloat…First/
  LastValueMapped` constants were swapped.
- **Waveform annotations** — text was written to SR Text Value (0040,A160) instead of
  Unformatted Text Value (0070,0006); the parser still reads the old tag as a fallback.
- **RT Plan** — `applicationSetupNumber`/`applicationSetupType` swapped (300A,0232/0234).
- **UPS-RS** — `humanPerformerCodeSequence`/`humanPerformerOrganization` swapped;
  `retrieveURI` was (0040,1002) Reason for Requested Procedure; discontinuation reason was
  (0074,1236) Requesting AE; cancel-request contact info went to (0040,1005)/(0040,1006).
- **Enhanced MR flattening** read Segmented k-Space Traversal from Slab Orientation.
- **Dictionary** — repeating groups (50xx Curve, 60xx Overlay) were absent, so overlay
  attributes displayed as unknown; multi-VR attributes were collapsed to one VR; Extended
  Offset Table was UN instead of OV. `VR` gains `OV`, `SV`, `UV`.
- Renamed to the PS3.6 keyword (old names deprecated): `cranialThermalIndex`,
  `operatorsName`, `physiciansOfRecord`, `nameOfPhysiciansReadingStudy`, `contentLabel`/
  `contentDescription`/`contentCreatorName` (for `presentation*`), `unformattedTextValue`
  (0070,0006), `hangingProtocolDefinitionSequence`, `imageSetSelectorSequence`,
  `UPSQueryAttribute.scheduledStationNameCodeSequence`.
- Guardrails: `Scripts/audit_tags.py --strict` in CI; `TagConstantAuditTests` checks every
  `Tag` constant against the dictionary; `TagAuditRegressionTests` rebuilds inputs from
  numeric tags.

<!-- merged from origin/main (PR #217, DICOM 2026d video conformance) -->

### Fixed — `dicom-video` conformance against DICOM 2026d (PS3.5 8.2.5 - 8.2.12)

- **Level limits are checked against the coded picture.** Rows, Columns and
  frame rate must be compliant with the transfer syntax's level, so picture
  size and throughput are now checked against H.264 Table A-1 / H.265 Table
  A.8. A 4K stream signalled as Level 4.1 (which `x264 -level 4.1` produces)
  was previously accepted as `…4.102`.
- **HEVC High tier is rejected**; PS3.5 8.2.10 / 8.2.11 require Main tier.
- **MPEG-2:** the level ceiling check was inverted, letting a High Level stream
  through as Main Level (`…4.100`). Table 8-1 limits (720x576 at 25 Hz,
  720x480 at 30 Hz) and the 8.2.6 rules for `…4.101` (1280x720 or 1920x1080,
  `aspect_ratio_information` 16:9, Table 8-2 frame rates) are now enforced.
  MPEG-2 levels are reported by name ("Main", "High").
- **Audio is carried and validated, not "discarded".** The bit stream was
  always encapsulated unchanged, so audio tracks were in fact kept while the
  tool claimed otherwise. Audio is now described (format, rate, channels, bit
  rate) and validated against 8.2.12 for AVC/HEVC (LPCM and AC-3 in MPEG-TS
  only; AAC 48 kHz 2/5.1 ch ≤ 640 kbps; CBR MP3; MP2) and 8.2.5 for MPEG-2
  (CBR MP3 only). A non-conformant track is rejected with an audio-only
  remedy that copies the video bit-for-bit.
- **3D and stereo:** a frame packing arrangement SEI selects `…4.105` (and is
  refused for `…4.104`), an MVC subset SPS selects Stereo High `…4.106`, and
  Stereo Pairs Present (0022,0028) = YES is written for both (Table 8-8).
- **Basic Offset Table is empty.** It carried a single zero entry for a
  multi-frame object, which A.4 does not allow, and 8.2.5 / 8.2.6 require it
  empty for MPEG-2.
- **HEVC `…4.107` / `…4.108` are fragmentable**; the non-existent UIDs
  `…4.107.1` / `…4.108.1` were removed from `TransferSyntax`, the UID
  dictionary, the validator and DICOMStudio. Payloads larger than one 32-bit
  fragment are split, selecting the `….1` twin for MPEG-2 / H.264.
- **MPEG-TS input is demultiplexed and validated** instead of being accepted
  only with `--trust-input`: PAT/PMT, video PES reassembly, access-unit
  count, PTS-derived frame rate when the stream declares none, and audio PIDs.
- `probe` now reports container and audio violations too, and an H.264 stream
  too large for Level 4.1 is reported against Level 4.2, the highest H.264
  ceiling DICOM offers. Remedies are geometry-aware (HEVC to keep the
  resolution, or an orientation-aware scale to fit H.264 Level 4.2) and quote
  `'0:a?'` so they paste into zsh.
- A container display rotation (e.g. portrait iPhone clips) is reported with
  a warning, since DICOM has no attribute to record it.

### Added — JPEG XL JPEG Recompression (…4.111) now supports JPEG Extended sources

- `TransferSyntaxConverter` recompresses JPEG Extended (…4.51, SOF1/SOF2) in
  addition to JPEG Baseline (…4.50, SOF0) into JPEG XL JPEG Recompression
  (…4.111), both forward and reverse, since JXLSwift's `encodeLosslessJPEG`
  bridges any 8-bit Huffman DCT JPEG. `jxlRecompressibleJPEGSyntaxUIDs`
  replaces the previous single-UID check.
- A 12-bit or signed JPEG Extended source is rejected up front with a clear
  message (PS3.5 Table 8.2.15-1 limits …4.111 to 8-bit unsigned pixel data),
  and lossless JPEG (SOF3) sources get a specific "no DCT coefficients to
  carry over" explanation instead of a generic unsupported-target error.
- On reverse recompression the rebuilt JPEG's Start-Of-Frame marker is
  checked against the chosen target UID (`jpegFrame(_:isAllowedIn:)`) so a
  progressive/extended JPEG is never mislabelled JPEG Baseline.
- Decoding a JPEG Baseline/Extended colour image to an uncompressed target
  now relabels `YBR_FULL_422`/`YBR_FULL` Photometric Interpretation to `RGB`,
  since ImageIO's JPEG decoder converts YCbCr to RGB and `YBR_FULL_422` is
  invalid on native pixel data (PS3.3 C.7.6.3.1.2).
- The lossless-compression gate (`allowLossyCompression`) now looks only at
  whether the *target* syntax is lossy, not source-and-target: decoding an
  already-lossy source (e.g. JPEG Baseline → Implicit VR LE) adds no
  additional loss.

### Added — Readable, shared conversion failure messages for `dicom-convert` and DICOMStudio's Workshop

- New `ConversionFailure` (`Sources/DICOMKit/ConversionDiagnostics.swift`)
  explains why a conversion cannot run or failed, in plain words: source and
  target transfer syntax labels, the reason, the source's pixel attributes
  when relevant, and a suggested alternative target.
- `DICOMConverter.checkConversion(dicomFile:to:)` validates a chosen target
  before any work starts (unknown source transfer syntax, missing decoder,
  JPEG XL Recompression source rules, pixel format vs. encoder capability)
  and is public so a UI can validate a choice before running.
  `convertToDICOM` now wraps any later codec/parser error the same way, so
  both success and failure paths report through `ConversionFailure`.
- `ConvertConsole.failureReport(for:)` / `.failureSummary(for:)` render the
  shared multi-line and one-line failure text; the `dicom-convert` CLI and
  DICOMStudio's `CLIWorkshopViewModel` both use them instead of
  `error.localizedDescription`, so the two surfaces can no longer drift.
- `TranscodingError` now conforms to `LocalizedError` so its `description`
  surfaces through `localizedDescription` instead of Foundation's generic
  "TranscodingError error N" fallback.

### Fixed — `dicom-mwl` and DICOMStudio never returned the Requested Procedure Description

- The Modality Worklist service used tag (0032,1070), which is Requested
  Contrast Agent, instead of Requested Procedure Description (0032,1060). The
  default C-FIND return keys therefore never asked the SCP for the description,
  and `WorklistItem.requestedProcedureDescription` read the wrong tag, so the
  field was silently absent from the text and JSON output of `dicom-mwl` and
  from the DICOMStudio CLI Workshop, which share this code in DICOMNetwork.
- The query keys, the result accessor and the worklist create path
  (`DICOMModalityWorklistService.create`) now all use (0032,1060). Worklist
  items created by earlier versions carry the description in (0032,1070) and
  will not show it when queried back.
- Added regression tests for the default return keys and for surfacing the
  description through the accessor and the shared text and JSON formatters.

## [2.2.16] - 2026-09-22 (released on the 2.2 line; cherry-picked to main)

### Fixed — The 64-bit Value Representations OV, SV and UV were missing

- `VR` had no `OV`, `SV` or `UV` case (PS3.5 2026d Table 6.2-1, CP-1818), so an
  explicit "OV" element — notably Extended Offset Table (7FE0,0001) and Extended
  Offset Table Lengths (7FE0,0002) — was read as `UN` and the dictionary listed
  those tags as UN; `uses32BitLength` now covers OV, SV and UV (PS3.5 Table
  7.1-1), the parser retains the declared VR and value bytes exactly, and the
  writer emits the two reserved bytes and 32-bit length for them.
- Dictionary corrections: (7FE0,0001)/(7FE0,0002) OV, (7FE0,0003) UV,
  (0072,0081) OV, (0072,0082) SV, (0072,0083) UV, (0008,040C)/(0008,040D)/
  (0008,0428)/(0008,0429) UV.
- `EncapsulatedPixelData` still exposes only the Basic Offset Table; readers that
  need the extended table consult the two elements directly.

## [2.2.15] - 2026-09-22 (released on the 2.2 line; cherry-picked to main)

### Fixed — Deflated Explicit VR Little Endian data sets were silently truncated on read

- The reader inflated a deflated Data Set (PS3.5 A.5) into a fixed buffer of
  four times the compressed size (minimum 64 KiB) with `compression_decode_buffer`
  and kept whatever fit, so any file whose Data Set expanded more than four-fold
  (typical for segmentations and constant regions) parsed as a silently
  truncated object. New `DeflatedDataSet.inflate(_:maximumOutputByteCount:)`
  streams the inflation, requires the DEFLATE end-of-stream marker exactly at
  the last input byte, and reports `truncated`, `corrupt`, `trailingBytes` and
  `outputLimitExceeded` as distinct failures; `DICOMParser` maps them to
  `DICOMError.parsingFailed`.
- `ParsingOptions.maximumInflatedByteCount` (default 1 GiB) bounds the inflated
  size so a small compressed file cannot expand without limit.
- The private `Data.decompress()` helper was removed; `Data.deflateCompressed()`
  (the writer) is unchanged.

## [2.2.14] - 2026-09-22 (released on the 2.2 line; cherry-picked to main)

### Fixed — JPEG-LS and JPEG 2000 decoders accepted frames that did not match the descriptor

- `JPEGLSCodec.decodeFrame` now verifies the decoded frame against the
  `PixelDataDescriptor`: width/height must equal Columns/Rows, the component
  count must equal Samples per Pixel, the sample precision P must equal Bits
  Stored (as DCMTK's decoder requires) and every component must be a full-size
  plane. A mismatch throws `DICOMError`; previously the output was silently
  zero-filled, truncated, widened or clamped to the descriptor's byte count.
- `JPEGLSCodec(decodingTransferSyntaxUID:)` pins a decoder to a transfer
  syntax. Under JPEG-LS Lossless (…4.80) a scan with NEAR > 0 is refused
  (ITU-T T.87 C.2.4.1.1); the registry now wires one decoder per syntax. The
  default initializer accepts both scans as before.
- `J2KSwiftCodec.packPixels` now requires the decoded component count to equal
  Samples per Pixel (also for single-sample frames), every component precision
  to fit Bits Allocated and every component buffer to be exactly the declared
  frame's byte count. Previously a surplus component was ignored and an
  over-long buffer (for example a 16-bit codestream under an 8-bit descriptor)
  was silently truncated.
- `J2KSwiftCodec(decodingTransferSyntaxUID:)` and the new
  `J2KCodestreamInspector.usesIrreversibleWavelet(in:)` refuse a codestream
  whose COD/COC selects the irreversible 9/7 wavelet under a lossless-only
  transfer syntax (…4.90, …4.92, …4.201, …4.202). The registry, `HTJ2KCodec`
  and `CompressionManager` decode paths pass the source syntax through. The
  default initializer still decodes any Part-1 / HTJ2K codestream.
- Added strict-decoding contract tests for both codecs and the inspector.

### Changed — JLSwift floor raised to 0.9.2

- JPEG-LS streams whose entropy data is followed by a legal 0xFF fill byte
  before EOI (ITU-T T.81 B.1.1.2; CharLS / DCMTK `dcmcjpls` writes one on many
  single-row frames) failed to parse in JLSwift ≤ 0.9.1 ("premature end of
  bitstream"). Fixed upstream in JLSwift 0.9.2; `Package.swift` now requires
  `from: "0.9.2"` and a CharLS-authored regression stream is decoded in
  `JPEGLSCodecTests`.

### Fixed — RLE Lossless decoder silently repaired malformed segments (v2.2.13)

- `RLECodec.decodeRLESegment` now decodes strictly per PS3.5 Annex G: a segment
  that ends before the declared length throws instead of being zero-filled, a
  literal or repeat run that overshoots the declared length throws instead of
  being truncated, and more than one trailing byte after the declared length
  (the G.3.2 even-length pad) throws instead of being ignored.
- Well-formed streams, including every `RLECodec.encodeFrame` output, decode
  byte-identically as before. Added strict-decoding contract tests.
- Released as v2.2.13 from the v2.2.12 line.

### Added — dicom-mwl: date/time Range Matching and a scheduled-time filter (2026-09-17)

MWL scheduled-date filtering accepted only a single day; there was no way to ask
for a week's worklist, or for a window within a day. Both the date and the new
time filter now speak DICOM Range Matching (PS3.4 C.2.2.2.5), and the pair is
emitted so an SCP can read it as one continuous interval per PS3.4 K.6.1.

- **`--date` accepts ranges.** `YYYYMMDD-YYYYMMDD` (both bounds inclusive),
  `YYYYMMDD-` and `-YYYYMMDD` alongside the existing `YYYYMMDD` Single Value
  Match. `today`/`tomorrow` still work, and may now be used as either bound
  (`--date today-`, `--date today-tomorrow`). A range that *starts* with a hyphen
  must use the equals form — `--date=-20240707` — or ArgumentParser reads the
  value as another flag.
- **New `--time` filter**, mapping to (0040,0003) Scheduled Procedure Step Start
  Time inside the SPS sequence, with the same Single Value / Range grammar:
  `HHMMSS`, `HHMMSS-HHMMSS`, `HHMMSS-`, `-HHMMSS`. TM components validate at
  `HH`, `HHMM`, `HHMMSS` and `HHMMSS.FFFFFF` widths.
- **Combined date+time intervals.** When both filters are ranges, DICOMKit emits
  both matching keys as-is and the SCP interprets them as one continuous
  date-time interval (PS3.4 K.6.1) — `--date 20240705-20240707 --time 1000-1800`
  means "July 5 10:00 through July 7 18:00", not "those three days, 10:00-18:00
  each".
- **One source of truth.** `WorklistQueryKeys.resolveScheduledDate(_:)`, the new
  `resolveScheduledTime(_:)` and `forQuery(date:time:…)` are shared by the
  `dicom-mwl` CLI, DICOMStudio's in-app worklist query and the CLI Workshop, so
  the three cannot drift. The Workshop's `dicom-mwl` panel gained the matching
  **Time** field and range-aware help on **Date**.
- **Portability note, documented in `Sources/dicom-mwl/README.md`:** open-ended
  ranges are valid DICOM but not universally implemented — dcm4chee rejects them
  with `0x0110 Unable to process`. Closed ranges are the portable form.

**Breaking (source):** `WorklistDateFilterError.invalidFormat` is split into
`.invalidDateFormat` and `.invalidTimeFormat`, each naming the accepted grammar
in its message.

### Added — visible-light and video SOP Classes, and the modalities that carry them (2026-09-17)

Wrapping video surfaced gaps on either side of it: the still-image SOP Classes in
the same VL family were missing from the UID dictionary, and the modality codes
`dicom-video` emits had no icon or display name.

- **`UIDDictionary` gained the four VL still-image SOP Classes** — VL Endoscopic
  (`…77.1.1`), VL Microscopic (`…77.1.2`), VL Slide-Coordinates Microscopic
  (`…77.1.3`) and VL Photographic (`…77.1.4`) Image Storage — so they resolve to
  a name rather than the bare UID.
- **`ConformanceStatementGenerator` names seven more SOP Classes** in generated
  statements: those four, plus Video Endoscopic, Video Microscopic and Video
  Photographic Image Storage.
- **`ModalityMapping.StandardModality` gained ES, GM and XC** — Endoscopy,
  General Microscopy and External-Camera Photography — the codes
  `VideoType.defaultModality` emits, each with its own SF Symbol and display
  name. Previously they fell through to the generic badge.

### Added — dicom-video: video conversion, playback and Workshop parity (2026-09-10)

*Plan and per-phase status: `DICOM_VIDEO_CONVERSION_PLAN.md`. Phases 1-10 — the
whole of v1 — are delivered; transcoding stays out of scope.*

`dicom-video` wraps an already-conformant H.264/HEVC/MPEG-2 bit stream in a DICOM
Video IOD and extracts it back out, without re-encoding. Remuxing keeps the
diagnostic pixel data bit-for-bit; non-conformant input is **rejected with the
violated constraint named**, never silently "fixed".

- **One shared engine, `Sources/DICOMKit/Video/`**, used by the CLI, the Studio
  CLI Workshop and the Studio viewer alike (the same `*Console` pattern as
  `SplitConsole` / `CompressionConsole`):
  - `VideoWorkflow` — plan, build, encode, probe, extract and batch-orchestrate.
    It returns bytes and never writes a file, prints or parses argv, so the CLI
    writes with `Data.write(to:)` and the sandboxed app writes through
    `OutputAccess`.
  - `VideoConsole` — every console line, help string, argument enum and exit
    code, so the CLI's `--help` and the Workshop's field help cannot drift.
  - `Sources/dicom-video/main.swift` shrank from 921 to 500 lines and is now a
    thin ArgumentParser adapter over the two.
- **Four subcommands**: `convert` (one clip), `probe` (geometry and conformance,
  writes nothing), `extract` (recover the bit stream) and `batch` (a folder, with
  `--series-mode single|per-file` defaulting to `single`, which IHE ENDO
  §3.10.4.1.1.1 requires for one procedure step on one piece of equipment).
- **`-v/--verbose` on all four subcommands**, explaining which container was
  recognised, why that transfer syntax was chosen, where the frame count came
  from, the UIDs minted and how much of the output is payload rather than DICOM
  overhead. Commentary goes to **stderr**, so stdout stays byte-for-byte what a
  non-verbose run prints and redirection keeps working. It also explains
  rejections, printing what was learned before the failure; it never changes a
  message or an exit code.
- **DICOMStudio CLI Workshop** gained `dicom-video` with all four subcommands and
  every option, driven by the same `VideoWorkflow`/`VideoConsole` the terminal
  uses.
- **DICOMStudio viewer plays clips.** A video instance carries an *image* SOP
  Class, so the transfer syntax — not the SOP Class — now decides:
  `ViewerContentKind.kind(forSOPClassUID:transferSyntaxUID:)` classifies it as
  `.video` and the series pane labels it "Video" rather than "Images". The clip is
  handed to an `AVKit` player, and the toolbar's cine transport drives it through
  the same play/stop state that drives multi-frame images.

### Fixed — video probing and extraction defects found while wiring the CLI (2026-09-10)

- **H.264 parameter sets from `avcC` were parsed one byte short.** `avcC` stores
  each parameter set as a complete NAL unit, header byte included; `VideoProbe`
  called `parseSPSPayload` as though the header had already been stripped, so
  every MP4-sourced H.264 clip probed with wrong geometry or failed outright. It
  now calls `parseSPS(nalUnit:)`, which validates and strips the header.
- **`--trust-input` on an MPEG-TS emitted Rows and Columns of zero.** "Trusted"
  was taken to mean nothing at all was read, but Rows and Columns are required
  attributes and an object carrying zeroes is one no reader can display. New
  `TransportStreamScanner` reassembles just enough of the first video PID to reach
  a sequence or parameter set header (ISO/IEC 13818-1 §2.4.3.2, §2.4.3.6), so
  geometry is recovered while only the *conformance checks* are skipped — which is
  what the caller actually asked for. Full PAT/PMT/PES demuxing remains Phase 11.
  The codec is taken from the container's own declaration rather than sniffed,
  because an MPEG-2 sequence header parses as a plausible but wrong H.264 SPS.
- **Extraction returned one byte too many for odd-length streams.** A fragment's
  length must be even (PS3.5 §7.1), so an odd-length bit stream is padded on the
  way in. `VideoExtractor` now recovers the true length from the container's own
  top-level box extent (`MP4ContainerParser.topLevelBoxExtent`) rather than
  trusting parity: a stream whose real length happens to be odd is left untouched,
  and MPEG-TS and raw elementary streams — which have no such framing — are
  returned unchanged.
- **MPEG-2 in MP4 had no parameter sets to validate.** The parser now reads the
  decoder-specific info out of the `esds` descriptor chain (ISO/IEC 14496-1), and
  falls back to the sequence header in the first sample.

### Added — dicom-video test matrix (2026-09-10)

47 tests across seven suites, all passing:

- `Tests/DICOMRoundTripTest/VideoConsoleParityTests.swift` locks every console
  line and workflow behaviour the CLI shares with the Workshop, so drift would
  have to be introduced deliberately. Fixtures are ISO-BMFF files assembled from
  the box layouts in the specifications, so expected values follow from the
  standard rather than from an encoder.
- `Tests/DICOMRoundTripTest/VideoCLIEndToEndTests.swift` drives the real binary.
- `Tests/DICOMStudioTests/CLIWorkshopVideoTests.swift` pins the Workshop's tool
  definition, subcommands and options.
- `Tests/DICOMStudioTests/ViewerVideoContentTests.swift` and
  `ViewerVideoTransitionTests.swift` pin classification, and the state left behind
  when the reader steps between a clip, a picture and a report — in both
  directions and round trip.
- `Tests/DICOMKitTests/Video/VideoProbeTests.swift` and
  `MP4ContainerParserTests.swift` / `VideoExtractorTests.swift` cover the fixes
  above.


### Fixed — CLI Workshop dicom-image wrote onto the browsed output folder (2026-09-07)

The output Browse picker grants a *folder*; typing a filename after it left the
executor writing the bytes straight onto the folder URL, so a run with a
browsed `…/Desktop/Test` and a typed `…/Desktop/Test/TEST2.dcm` failed with
"The file "Test" couldn't be saved in the folder "Desktop"" while the CLI
succeeded. `executeDicomImage` now hands the typed path to the shared
`OutputAccess.write`, which places the file inside the grant (batch and
TIFF-split outputs go through the same path). Console lines print the path
actually written. `Tests/DICOMStudioTests/WorkshopDicomImageOutputScopeTests.swift`
pins both the folder+filename and folder-only cases.

### Fixed — dicom-image: colour images failed with "Failed to create graphics context" (2026-09-07)

`ImageConverter.extractPixelData` asked Core Graphics for a packed 24-bit RGB
bitmap context, which Core Graphics does not support (its only 8-bit RGB
layouts are 32 bits per pixel). Every colour PNG/JPEG/TIFF therefore failed in
both the `dicom-image` CLI and the Studio CLI Workshop, which shares the
converter; only grayscale sources ever converted. The RGB path now renders into
a 32-bit RGBX context, pre-filled white so transparent pixels composite onto
white, and strips the padding byte so PixelData stays packed 24-bit RGB with
Samples per Pixel 3. `Tests/DICOMKitTests/ImageConverterColorTests.swift`
pins the RGBA→RGB samples, the white composite, and the unchanged grayscale path.

### Added — dicom-split / dicom-merge: Workshop ↔ terminal parity suite (2026-09-03)

`Tests/DICOMStudioTests/SplitMergeWorkshopCLIParityTests.swift` runs every option
combination of both tools through the Studio CLI Workshop executor and the real
release binary and asserts identical console output, exit outcome and written
files. It found five app-side drifts, all fixed: the Workshop dropped the
engine's non-verbose warnings (skipped files, `--frames` ignored with
`--frames-per`), parsed `--frames` before the verbose banner, printed bad-value
errors without ArgumentParser's `<value-name>` / `Help:` line (now shared through
`SplitConsole.invalidValueLines` and help constants the CLI's `@Option` reads),
skipped merge's "Found 0 DICOM files" line, and reported a missing merge root as
"No DICOM files found" instead of "Input path does not exist".

### Added — dicom-split / dicom-merge understand Enhanced multi-frame, for every modality (2026-09-01)

*Work in progress, not yet committed. Plan and progress: `ENHANCED_MULTIFRAME_SPLIT_MERGE_PLAN.md`.*

Both tools used to be byte shufflers: split copied the whole data set per
frame (Enhanced SOP class kept, the complete Per-frame Functional Groups
Sequence left in every file), merge stacked pixel bytes under whatever SOP
class the template had and, for `--format enhanced-*`, emitted only a
Pixel Measures / Frame Content / Plane Position skeleton with Dimension Index
Values pointing at no Dimension Organization. Compressed input corrupted both
ways. The `--help` text claimed "proper functional groups" throughout.

- **One shared engine, `Sources/DICOMKit/Multiframe/`**, used by the CLIs and
  the Studio Workshop alike (same pattern as `CompressionConsole` /
  `DICOMConverter`): `MultiframeSOPClassMap` (the single table of multi-frame
  SOP classes → split target / merge sources), `FunctionalGroupFlattener`
  (Shared then Per-frame item promoted to the top level, per-frame wins, plus
  the typed clean-up — Frame Type → Image Type, Frame Laterality → Image
  Laterality, Effective Echo Time → Echo Time, MR Scanning Sequence / Sequence
  Variant / Scan Options derivation), `FunctionalGroupBuilder` (attribute
  equality decides shared vs per-frame, whole macro at once; Frame Content
  always per-frame; Multi-frame Dimension module; Conversion Source Attributes
  and Unassigned Per-Frame Converted Attributes for Legacy Converted targets),
  `LegacyVectorResolver` (Frame Time Vector → Frame Time, NM index vectors
  sliced per frame), `MultiframePixelAssembler` (native slicing or one
  encapsulated fragment per frame with a Basic Offset Table; `decode` mode
  writes Explicit VR LE).
- **dicom-split** converts Enhanced CT/MR/PET/XA/XRF and Legacy Converted
  objects to CT/MR/PET/XA/XRF Image Storage, US Multi-frame → US Image,
  Multi-frame SC → SC Image; keeps the class (one frame per instance, Per-frame
  sequence trimmed to the frame's item) for NM, XA/RF, RT, Breast Tomo, X-Ray
  3D, OPT, Enhanced US Volume, MR Colour, IVOCT; refuses Segmentation,
  Parametric Map and MR Spectroscopy. New options: `--target auto|same|classic`,
  `--pixel-handling preserve|decode`, `--private-groups flatten|keep|drop`,
  `--instance-number frame|instack|original`, `--split-by none|stack|temporal`,
  `--new-series`; `{number:04d}`, `{instance}` and `{stack}` pattern variables.
  Image export decodes only the requested frame and honours the frame's own VOI.
- **dicom-merge** formats: `auto` (Legacy Converted CT/MR/PET, US Multi-frame or
  Multi-frame SC from the source class), `enhanced-pet`, `enhanced-xrf`,
  `legacy-converted-ct|mr|pet`, `sc-multiframe`, `us-multiframe`; a source
  SOP-class gate (`--allow-any-source` to override); `--make-stacks`,
  `--temporal-position`, `--new-series`, `--pixel-handling`. Image Pixel module
  consistency, transfer-syntax equality and duplicate SOP Instance UIDs are
  checked on every run; `standard` on a classic IOD warns. Sorting by Image
  Position (Patient) now projects onto the slice normal and is stable.
- **Concatenations** (`MultiframeConcatenation`, DCMTK ConcatenationCreator /
  Loader parity): `dicom-split --frames-per N` writes parts that keep the SOP
  class and carry Concatenation UID, In-concatenation Number / Total Number,
  Concatenation Frame Offset Number and the source SOP Instance UID, with the
  Per-frame items and legacy vectors of their frames — the one legal split for
  Segmentation and Parametric Map (Ophthalmic Tomography is refused, as the
  IOD requires). `dicom-merge` recognises parts and reassembles them in
  In-concatenation order, restoring the source SOP Instance UID.
- **Provenance**: extracted instances get UIDs derived from the source
  (`2.25.<SHA-256>` — same input, same output; `--random-uids` opts out), so
  Referenced / Source Image references that name frames of another multi-frame
  object are rewritten to the single-frame instances they become (dcm4che
  `adjustReferencedImages`).
- **Multi-frame inputs to merge** contribute every frame (Enhanced chunks are
  flattened and re-factored; cine loops have their vectors sliced), and the
  (Volume) plane macros position frames of the volume IODs.
- **Viewer/export**: `DataSet.windowSettings()`, `allWindowSettings()`,
  `rescaleSlope()` and `rescaleIntercept()` fall back to the Frame VOI LUT /
  Pixel Value Transformation functional groups and take a `frameIndex:` (that
  frame's Per-frame item, else the Shared one); `DataSet.flattenedFrame(_:)`
  exposes a frame's attributes at the top level. The one window policy
  (`DICOMImageExporter.determineWindowSettings`) now honours the frame at the
  rescale and VOI rungs, so viewer tiles (GPU and CPU), film, `dicom-export`
  and `dicom-convert` render each frame of a per-frame-windowed Enhanced
  object (multi-echo MR, PET) with its own window instead of frame 0's. The
  focused viewport follows the frame while its window is untouched, keeps a
  dragged window across frames, always adopts the frame's rescale pair, and
  "reset" lands on the frame on screen.
- **Tests**: `EnhancedMultiframeRoundTripTests` (27 oracles — Enhanced CT →
  classic → Enhanced → classic identity, `--target same`, stacks, NM vectors,
  US cine, encapsulated preserve through split and merge, mixed transfer
  syntax, gating, Legacy Converted evidence, `auto`, sort-by-normal,
  concatenation split/reassembly, deterministic UIDs, reference expansion,
  multi-frame inputs, volume geometry, functional-group window fallback,
  per-frame window/rescale through accessors, policy and split) and
  `ViewerPerFrameWindowTests` (untouched window follows the frame, dragged
  window survives paging, shared window is not per-frame).

### Added — a study's own presentation states are adopted, drawn, and printed (2026-08-31)

*Work in progress, not yet committed.*

A study exported from a PACS or saved out of Weasis carries its PR objects
with it. They were indexed like any other series — the pane could name them,
and nothing could show them, because the viewer's saved views came from
`PresentationStateStore` and the store listed only what this app had itself
saved. The reader's workflow is "the presentation state arrives with the
study, apply it, print it", and that path did not exist.

- **Adoption on study open.** `StudyPresentationStateAdoption.adopt`, called
  from `MainViewModel.populateViewerSeriesPane` before the viewer is told
  about the study, offers every GSPS, CSPS and Pseudo-Color object the library
  indexes for the study to the store, which copies the ones it does not
  already hold. Keyed on SOP Instance UID, so reopening a study is a no-op.
  Cheap when there is nothing to do: a study with no PR series touches no
  file, and one with them reads a header per referenced image, never the whole
  study.

- **In the picker, marked *imported*, and the first one applied on arrival**,
  as Weasis does. Window, zoom, pan, rotation, flip, inversion and palette go
  onto the image; a Modality LUT rescale carried by the state is used to
  interpret its window (`RestoredDisplay.rescaleSlope`/`rescaleIntercept`).

- **What the other viewer drew is drawn here.** The Graphic Annotation
  Sequence — POLYLINE, INTERPOLATED, CIRCLE, ELLIPSE and POINT objects with
  their text — becomes `PrintOverlayAnnotation` shapes per image and frame in
  the sidecar, stroked in the layer's recommended colour. Display shutters
  become `.shutter` overlays, drawn first with an even-odd fill so everything
  outside the open region is masked. Three surfaces share one geometry:
  `ImageAnnotationBurner.shapePath` for the film, a GPU texture in the viewer,
  and `ImportedShapeView` for the print preview and the non-Metal fallback.

- **Imported views are locked, not editable.** There is no measuring tool here
  that could recompute a "42.3 mm" label, so a shape read out of somebody
  else's state is shown and printed exactly as stated and cannot be moved or
  reworded. The whole view can be taken off; deleting one writes a
  `<uid>.declined` tombstone so it is not adopted again on the next open.

- **On film.** A marked image burns the same shapes and shutter into the
  pixels, oriented with the cell, so the Print SCP receives them in the image
  box rather than as an overlay the printer may ignore.

- **Not carried:** a state's VOI LUT *table* (a window is), bitmap shutters
  that reference an overlay group, and a CSPS's ICC profile.

### Fixed — presentation states are written with the VRs the standard gives them (2026-08-31)

*Work in progress, not yet committed.*

`dcmpschk` rejected a saved view at the first attribute it checked. The
builder had hardcoded `vr: .IS` on seven binary attributes — Image Rotation
(US), the Displayed Area corners (SL), the Graphic Layer recommended display
values (US), and Graphic Data, Bounding Box corners and Anchor Point (FL) —
and the parser read back the same wrong forms, so every round-trip test passed
against a file no other toolkit would accept. **A round trip can never catch a
wrong VR; only a dictionary check or an external validator can.**

- **The VR now comes from the dictionary, not the call site.**
  `DataSet+DictionaryVR.swift` adds `setInteger(s)`, `setReals` and
  `setStringFromDictionary`, which read the VR from `DataElementDictionary` —
  DICOMKit already ships the full PS3.6 table. A call site can no longer
  disagree with the standard. `DataElement.int16s`/`int32s`/`float32s` fill in
  the multi-valued binary constructors these need.

- **Objects written before the fix still open.**
  `DataElement.integerValuesTolerant`/`realValuesTolerant` read a number
  whatever VR it was stored under, so a view saved by an older build restores
  its zoom, pan and layer colours instead of coming back blank.

- **Guarded by a sweep, not by an assertion.** `PublishedStateDictionaryVRTests`
  walks every element of a published object, recursing into sequences, and
  compares each VR to the dictionary — skipping the tags whose real VR depends
  on Pixel Representation or transfer syntax, which the flattened resource
  file would report as broken. Validated externally with `dcmpschk`.

### Fixed — image ordering, study deletion, and drawings that outlived their study (2026-08-31)

*Work in progress, not yet committed.*

- **Two viewers no longer disagree about which image is "17 of 31".** A window
  saved on image 17 here showed on 4/31 in Weasis — on the *same pixels* both
  times; only the ordinals differed. Instance Number is an IS, text, and was
  read as binary until 2026-07-30, so any library indexed before then holds
  nils forever: re-imports are deduplicated by SOP Instance UID and never
  refresh metadata, leaving the series in file-system order.
  `ViewerSeriesCatalog.resolvingInstanceOrder` repairs it at open time, off
  the main actor, reading only the series actually missing numbers and writing
  what it recovers back into the library so the files are read once rather than
  once per open. `loadStudySeries` adopts the repaired order without moving the
  image on screen.

- **Deleting a study now reclaims its files.** Import copies every file into
  `Imports/<StudyInstanceUID>/`; removing the index row left that copy behind,
  invisible to the browser and still holding pixel data and patient
  identification. `StudyFileCleanup` removes both halves, and checks every path
  is inside the import directory first — a library entry pointing at a file the
  user picked in place is never touched. The index is saved before anything is
  deleted, so a crash between the two leaves a listed study with missing files
  rather than orphaned files no screen can reach. `onStudyRemoved` lets the
  viewer, the caches and the print queue let go of the study at that moment.

- **Drawn annotations reset with the study.** Window, zoom and rotation were
  already dropped on a study switch; the drawings were the one tool state that
  stayed behind, keyed to the previous study's file paths, and reappeared the
  next time that study was opened.

### Added — research adoption: selected-frame access, parser hardening, PS3.15 de-identification (2026-08-10/11)

*Work in progress, not yet committed. Full plan and evidence:
`RESEARCH_ADOPTION_PLAN.md`, `Documentation/ResearchAdoption/`.*

A gap report comparing DICOMKit against the wider toolkit ecosystem
(`ECOSYSTEM_COMPARISON.md`) found that decoding one frame of a multi-frame file cost
the same as decoding the whole volume, that the parser had no depth/size limits, and
that JPIP was advertised as working when every upstream retrieval path throws
`notImplemented`. Milestones M0–M6 close those gaps one controlled change at a time,
each with a before/after release-build measurement and the round-trip suite green.

- **Selected-frame decode is now ~40× faster, not a full-volume decode.** New
  `DICOMByteSource`/`InMemoryByteSource`/`FileByteSource`, a validated encapsulated
  frame index (`EncapsulatedPixelData.makeFrameIndex`, EOT → BOT → 1:1, fail-closed
  on malformed tables), and public `DICOMFile.pixelData(frame:)` /
  `pixelFrameCount`. Measured on a 256×256×40 RLE synthetic (release, Mac16,13):
  182.9 ms → **4.56 ms median**; transient memory growth ~10 MB → unmeasurable;
  output byte-identical. Dead `DataSource`/`MemoryMappedDataSource`/
  `LazyPixelDataLoader` deleted; `.lazyPixelData` re-honestly-worded.
- **Caller-owned codec output removes a full-frame copy.** `ImageCodec.decodeFrame(into:)`
  (RLE interleaves segments straight into the destination) and
  `DICOMFile.alignedPixelData(frame:)` decode into page-aligned storage Metal wraps
  via `bytesNoCopy` — no separate `pageAligned()` re-copy on the render path.
- **Bounded parallel decode with cancellation.** `DICOMFile.pixelData(frames:maxInFlightBytes:)`
  / `pixelDataParallel` windows concurrency by a byte budget, never task count;
  `Task.checkCancellation()` at every frame boundary; `HTTPRequestPipeline`'s task
  group is now windowed too. Measured: whole-volume decode 181.6 ms serial →
  **34.1 ms parallel (5.3×)**, byte-identical.
- **Progressive decode**: `DICOMFile.pixelDataProgressive(frame:coarseLevels:)` streams
  J2KSwift's reduced-resolution decode as an `AsyncThrowingStream`, ending in a
  full-fidelity frame proven byte-identical to a direct decode. Found and fixed a
  real shipped writer bug along the way — `CompressionManager.buildBasicOffsetTable`
  computed BOT offsets from unpadded fragment lengths, so every offset after an
  odd-length fragment pointed one byte short.
- **Parser and protocol hardening.** `ParsingOptions` gains `maxSequenceDepth` (64),
  `maxElementLength`, `maxTotalElements`, `maxFragmentCount`; violations raise
  `DICOMError.limitExceeded`/`DICOMNetworkError.limitExceeded` instead of trapping or
  hanging; `PDUDecoder.maximumPDULength` guard added. A seeded mutation fuzz suite
  (`ParserLimitTests`, `PDUFuzzTests`, `CodecFuzzTests`; 4×10⁵+ inputs) found and fixed
  a real defect: `RLECodec` mixed slice-relative header reads with absolute
  `subdata(in:)` indexing and trapped (`EXC_BREAKPOINT`, not a thrown error) on any
  `Data` whose `startIndex` wasn't 0 — reachable through the public
  `EncapsulatedPixelData` API. Two more instances of the same pattern were found and
  fixed in `DICOMFile.read(from:)` and `TransferSyntaxConverter.transcode`, backed by
  new `SliceIndependenceTests`. A static copy-path map
  (`Documentation/ResearchAdoption/Copy_Path_Map_v0.1.0.md`) classifies the remaining
  ~35 sites carrying the same relative/absolute mixing for a future sweep.
  `DICOMBenchmark.measureDetailed` adds median/P90/P95/stddev and true high-water
  resident memory sampling, with a committed baseline artifact.
- **PS3.15 Annex E de-identification engine.** New `ConfidentialityProfile` (action
  codes D/Z/X/K/C/U, ≥60-row curated direct-identifier table) and
  `ConfidentialityEngine` (recursive sequence descent, consistent UID
  regeneration, private-tag removal, E.3 retention options), exposed as
  `Anonymizer.deidentify(file:options:uidMap:)` and `dicom-anon --profile ps315`.
  Not a full ~530-row Table E.1-1 implementation — VR sweeps are the safety net for
  the remainder; documented as such rather than overclaimed.
- **Modality LUT Sequence precedence fixed** (PS3.3 C.11.1) — the pixel pipeline
  applied Rescale Slope/Intercept unconditionally even when a Modality LUT Sequence
  (0028,3000) was present (the fo-dicom #1986 class of bug); `DataSet.modalityLUT()`
  and LUT-aware `rescale(_:)` added, malformed sequences fail open to linear.
  `CrossToolkitMatrixTests` turns eight other toolkits' historical shipped bugs into
  permanent regressions against DICOMKit's own pipeline.
- **JPIP marked honestly unavailable rather than silently broken.** Every retrieval
  path in the pinned upstream J2KSwift `JPIP` module throws `notImplemented`; the 39
  passing `JPIPTests` never exercised retrieval. `DICOMJPIPClient`'s four fetch
  methods and the two JPIP-backed `DICOMFile.openVolume` overloads are now
  `@available(*, unavailable, message:)` with a new `DICOMJPIPError.retrievalUnavailable`
  naming the upstream cause; `dicom-jpip fetch` and `dicom-viewer --jpip` fail loudly
  with a pointer to `dicom-wado`/`dicom-retrieve` instead of hanging or silently
  streaming empty. README/`ECOSYSTEM_COMPARISON.md` corrected to match.
- **README limitations table corrected** to remove provably-wrong rows ("JPEG-LS not
  supported", "7+ Transfer Syntaxes" — actually 29, "Storage Commitment not
  implemented" — SCU+SCP shipped) and add the real open items (JPIP, MWL SCP, IPv6,
  partial PS3.15 coverage).
- **`ImageCache` is O(1) per hit** (monotonic access tick, O(n) only on eviction) with
  `trim(toFraction:)` staged eviction; `FrameSourceCache`'s key now includes file
  size+mtime (fixed a stale-pixels bug) plus an aggregate 192 MB ceiling.

Verification throughout: full suite 7,312 tests / 730 suites green (3 consecutive
runs), zero known issues (a permanent `withKnownIssue` on 12-bit J2K was replaced
with a real test pinning the actual ImageIO behavior). Deferred: `BulkDataHandle` as
an internal zero-copy representation (needs parser offset tracking — a bigger
change, sequenced for later), an async `ImageCodec` variant to replace
`J2KSwiftCodec`'s semaphore bridge, and the remaining ~35 copy-path sites the map
identified but didn't sweep.

### Added — pseudo-colour palettes, from the picker to the printed film (2026-08-19)

*Work in progress, not yet committed.*

A reader can now colourise a monochrome image — the "LUT" dropdown other viewers
show — per cell or across a whole film, and print it. The palettes are one
shared type rather than a table restated in every renderer:
`PseudoColorPalette` (DICOMCore) carries 23 palettes in five groups, and every
consumer — the CPU renderer, the Metal renderer, the print preprocessor, both
pickers and the CLI — reads that one list.

- **The palettes and where they come from.** Eight are the standard's own
  (PS3.6 Annex B: Hot Iron, PET, Hot Metal Blue, PET 20 Step, Spring, Summer,
  Fall, Winter), transcribed with their Content Label and well-known SOP
  Instance UID — the segmented streams expanded at transcription time, so
  there is no runtime segmented-LUT decoder to get wrong. Four are the CC0
  perceptual maps (Viridis, Inferno, Magma, Plasma) at full 256-entry
  resolution. The rest are formula-defined spectra and single-hue ramps. Each
  records its `Provenance`, so the audit line can say where a colour came
  from. Other viewers were referenced for *which* palettes to offer and what
  to call them; no ramp data or code was copied from them.

- **One table, so the GPU and the CPU cannot disagree.**
  `PaletteDisplayLUT.make(window:entries:)` folds the window LUT and the
  palette into a single raw-sample → RGB table, which the existing palette
  kernel already consumes — colour on screen needed no new shader, and the
  CPU path indexes the same table the same way.

- **Print bakes the colour in, because the wire cannot carry it.** PS3.3
  Table C.13-5 permits only RGB in a Basic Color Image Sequence, and "palette"
  appears nowhere in PS3.4 Annex H: a printer can never be told which palette
  was used. So `preparationPalette` bakes it into 8-bit RGB before
  transmission, `preparationColorMode` widens monochrome to colour, and
  `preparationBitDepth` clamps to 8 bits. Two costs follow, and the sheet says
  both where they are chosen: colour film is capped at 8 bits per sample where
  grayscale can do 12 or 16, and the Linear-OD density curve stays
  grayscale-only. Raw pixel jobs never colourise, and a grey palette is
  dropped before it reaches any of this.

- **Film-wide with per-cell override.** `applyFilmPalette` sets the sheet;
  `setCellPalette` overrides one cell; a new `.palette` sync lock carries a
  change across linked cells. Resetting a cell restores the *film's* palette
  rather than grey, so a reset cell on a coloured sheet is not left the odd
  one out. The palette is part of `ViewerPresentation` and counts toward
  `isIdentity`, and it is folded into both the render cache key and the
  print-cell texture key — without which the picker would appear to do nothing.

- **`dicom-print --palette`.** Tokens are generated from the shared catalog
  (`hot-metal-blue`, `viridis`, `pet-20-step`, …), grouped in `--help`, so the
  terminal and the app cannot drift apart. A dry run names the palette and
  prints its well-known SOP Instance UID where the standard defines one.

- **Renamed to end a collision.** DICOMStudio's own `PseudoColorPalette` — the
  GSPS C.11.10 stored-state vocabulary, used only by headless
  presentation-state code — is now `PresentationStatePalette`. It was
  shadowing the DICOMCore type and is a genuinely different idea: what a
  *saved state* says an image should look like, not the palette a reader picks.

### Fixed — colour studies printed grey, and colour jobs the printer rejected (2026-08-19)

*Work in progress, not yet committed.*

- **A colour study came out grey.** Only raw mode preserved colour: the
  processed path handed the preprocessor the job's colour mode, which
  flattened RGB to luminance before the pixels ever reached the wire — so a
  colour ultrasound or a fused PET printed, and *saved*, as greys.
  `PrintJobRequest.preservesSourceColor` (default on) keeps a colour source in
  colour on an otherwise grayscale job. The app detects it rather than
  trusting the mark: `refreshSourceColor()` reads Samples per Pixel and
  Photometric Interpretation off each file. A "Print colour images as greys"
  toggle keeps the old behaviour deliberately, and the sheet says which way it
  will go.

- **The SOP class now follows the pixels, in both directions.** A job whose
  colour mode disagreed with its prepared pixels was rejected outright — raw
  RGB on a Basic Grayscale Image Box answers 0x0106, *Samples per Pixel must
  be 1*. `PrintWorkflow.reconcilingColorMode(_:with:diagnostics:)` moves a job
  carrying three-sample frames onto Basic Colour Print Management, and back to
  grayscale when no frame carries colour, reporting the switch to
  diagnostics rather than doing it silently.

- **A saved film is named after its pixels.** The simulator labelled the image
  box from the request, so a film the SCU had already moved onto Basic Colour
  could be written out claiming grayscale while holding three samples per
  pixel — a state no real printer could be in, and one that made the saved
  film disagree with the print.

### Fixed — Presentation LUT INVERSE is rendered into pixels, not sent on the wire (2026-08-19)

*Work in progress, not yet committed.*

INVERSE is the softcopy module's value (PS3.3 C.11.6); the print module
(C.11.4) enumerates only IDENTITY and LIN OD. Sending it risked the N-CREATE
being rejected for a film the reader plainly asked for.
`PresentationLUTShape.inverse` becomes `.inverseRendered`, with `wireValue`
nil, `invertsPixels` and `isLegalPrintShape`: the inversion is applied to the
pixels by the new `PresentationLUTTransform` and no Presentation LUT SOP
instance is created — the same answer DCMTK gives for `--inverse-plut`. The
CLI token `inverse` is unchanged; the menu now reads "Inverse (rendered into
pixels)". As an SCP we are liberal in the other direction: an incoming
INVERSE — NUL- and space-trimmed, upper-cased — is accepted and honoured
rather than failing the association, because printing the inverted film is a
better outcome than refusing it. The preview XORs the film's rendered inverse
with any per-cell invert, so screen and film agree.

`PresentationLUTTransform` also supplies the pixel side of LIN OD for the one
case with no printer to defer to — the on-screen preview — with the
standard's default density bounds (`minDensity` 20, `maxDensity` 300 in
hundredths of OD, PS3.3 C.13.3).

### Added — saved views: a presentation state the viewer writes and the film can adopt (2026-08-19)

*Work in progress, not yet committed.*

The viewer could read a GSPS but never write one. It now saves what is on
screen as a named view, and the print screen can dress a whole film in it.

- **The write half.** `GrayscalePresentationStateBuilder` (DICOMKit) emits a
  conformant GSPS IOD opposite the existing parser. Its contract is that the
  parser can read back what it writes, so the tests are round trips rather
  than tag assertions: a tag written in a form the parser rejects is a bug
  even when the tag itself is right.

- **The store.** `PresentationStateStore` (DICOMPrintKit) keeps one shared PR
  series per study — series 9001, "Presentation States" — holding one GSPS
  object per image per saved view, grouped by the reader's label.
  `SavedView.state(forImage:)` and `covers(image:)` encode the rule that a
  view says nothing about an image it was not saved on, which is why the
  picker only offers views that cover the image in front of you.

- **One translation, done in one place.** `ViewerPresentationStateBridge`
  converts between viewer state and the standard's vocabulary, handling the
  two mismatches explicitly: GSPS allows only 0/90/180/270 with a *horizontal*
  flip, so a vertical flip is written as 180° plus horizontal; and Displayed
  Area is a source-pixel rectangle, so a view saved in one viewport restores
  correctly into a different one.

- **What GSPS cannot hold goes beside it.** Drawn arrows have no primitive in
  the Graphic Annotation Sequence, which also has no per-annotation colour and
  no scale — so annotations are stored losslessly in an
  `<sopInstanceUID>.annotations.json` sidecar next to the object rather than
  written lossily into it. Re-saving with no annotations deletes the orphan.

- **In the viewer.** A picker lists Default first and saved views
  newest-first, with naming and a named delete confirmation, and hides itself
  when there is nothing to choose. Every tool property now clears the claim
  that a saved view is still on screen the moment it is moved, so the label
  never lies; the selection is remembered per image across series stepping.

- **On film.** Cells adopt stored states — one cell, every cell, or only the
  cells the reader has not already touched — with a film-wide toggle and a
  default-view picker that says how many cells each label would cover. The
  cell's own recorded size is passed as the viewport, so a stored Displayed
  Area becomes the right zoom and pan for that cell. A cell the reader has
  adjusted is never overwritten, and a raw job drops saved views entirely.

### Added — drawn annotations belong to the image, show live, and reach the film (2026-08-19)

*Work in progress, not yet committed.*

- **Keyed by the image, not by the film mark.** Annotations move to
  `ImageAnnotationKey(filePath:frameIndex:)`, so a frame marked into two cells
  carries one shared set and the viewer can find them without a mark at all.
  `annotationsForPrinting` expands that back to per-mark keys at print time —
  a frame on two cells is burned twice — dropping blank text boxes on the way.

- **Composited on the GPU in the main viewer.** `AnnotationOverlayTexture` is
  a sibling of the frame texture, so editing an annotation does not force a
  frame re-decode and panning does not rebuild the overlay. The shader takes a
  second texture and composites it *after* inversion, so a yellow arrow stays
  yellow on an inverted frame; a 1×1 transparent placeholder is always bound
  so the binding is unconditional. The rasterizer calls the film's own
  `ImageAnnotationBurner`, so screen and film cannot drift apart.

- **On film, deliberately.** "Include annotations on film" defaults on and
  burns for non-raw jobs; raw pixel jobs cannot carry them, which the sheet
  says, and a job that goes out without them logs a notice rather than
  dropping them quietly.

### Fixed — the film's geometry: rotation direction, crop, flip order, and the zoom dead zone (2026-08-19)

*Work in progress, not yet committed.*

A set of geometry defects that made the preview and the film disagree, each
now pinned by a test that compares the two paths directly.

- **Every CPU-drawn thumbnail turned the wrong way.** `FrameRenderer.applying`
  rotated opposite to the raw-pixel transform used for film: `rotate(by:)` in
  a bottom-left-origin context is counterclockwise on a top-down display, and
  the negation the comment promised was simply absent — so tray thumbnails,
  CPU film cells and unfocused viewer tiles sat at twice the angle from the
  film. `FrameRendererOrientationTests` now compares both paths pixel-for-pixel
  over the same presentations.

- **Free rotation shrank the anatomy instead of cropping.** A non-quarter turn
  grew the output to the turned bounding box — √2 at 45°, 14% at 10° — so the
  picture got smaller on film. It now turns about its centre at its existing
  scale and the corners are cut, which is what the viewer does. A byte-identical
  resample also reports itself as resampled, so true-size millimetres are not
  claimed for blended pixels.

- **Flip was applied before rotation.** Folded into the fit scale, a flip on a
  quarter-turned image came out upside-down rather than mirrored — the two
  orders differ by a half turn — and the film disagreed with the screen. Flip
  now happens after rotation.

- **Pan moved opposite the hand on flipped cells.** Stored pan is a
  screen-space vector that was un-rotated without being un-mirrored. The
  transform is now `q = F · R · (zoom · p) + t`, with `viewToImage(x:y:)`
  un-mirroring before un-rotating.

- **The zoom dead zone.** Every zoom in [0.25, 1) rendered identically to
  fitted, so downward drags did nothing and pan was clamped to zero; the
  minimum cell zoom is now 1.0, since a fitted film cell has nothing to zoom
  out to, and a notice explains when Pan has nowhere to go. Free rotation also
  delivered only 1.46× for a 2× zoom at 30°.

- **The crop is masked.** Fragments outside the film crop are painted black;
  previously the freely-rotated corners and the letterbox beside a zoomed cell
  showed the neighbouring anatomy the crop existed to remove.

- **"Reset Cell" lit for cells nobody had edited**, because the window seeded
  on first click counted as an edit — and a seed arriving after a reset re-lit
  it. Edits are now measured against that seeded baseline, and reset restores
  the seed rather than clearing it.

### Fixed — corner captions land on the cell's corners (2026-08-19)

*Work in progress, not yet committed.*

The preview anchors patient identification to the *cell's* corners, but on the
wire only the image box exists — so a fitted frame of a different aspect than
its cell was letterboxed by the printer, and the burned caption floated in the
margin instead of sitting in the corner. `PreparedPrintImage
.padded(toCellAspectRatio:)` widens the frame to the cell's shape with film
background first — minimum stored value for MONOCHROME2 and RGB, maximum for
MONOCHROME1 — and centres the picture. It applies only where the problem
exists: fit-to-film, non-raw, and only when there are captions to place; fill,
stretch, true size and raw are untouched.

**Caption sizes are shared constants now.** The burner's typography is public
and single-source, and the preview consumes it — dropping its own 11 pt cap
and its own size fraction, which had been drawing captions at well under half
the size the film actually printed.

### Changed — the viewer: cine that plays, cursors that name the tool, presets that address the right modality (2026-08-19)

*Work in progress, not yet committed.*

- **A multi-frame image opens already playing**, looping at the rate its own
  header asks for — Recommended Display Frame Rate first, then Cine Rate, then
  Frame Time — clamped, with malformed values ignored. There is a play/pause
  toolbar button on Space. The cine timer's lifecycle is fixed: it starts on
  appear if playback is already running, restarts on a rate change only while
  playing, and stops on disappear.

- **The pointer carries the tool's own icon.** `ToolSymbolCursor` draws the
  same SF Symbol the toolbar button shows into the cursor, cached per symbol,
  and switches to the filled variant while dragging — replacing a generic
  crosshair that stood for both windowing and rotate. Delivered through
  AppKit cursor rects and reset to the arrow when the view leaves its window,
  which fixes the cursor sticking outside the image area. The windowing icon
  is now `sun.max`, no longer the mirrored twin of the Invert button's glyph.

- **Window presets address the modality.** A preset's identity is now
  modality-qualified: "Bone" exists for CT, CR and DX, and the duplicate
  identifiers had been wiring preset rows to the wrong actions. A cell offers
  its own modality's presets first, with the rest under "Other Modalities" —
  the modality is read in the same header pass that already reads image
  numbers.

### Fixed — the print screen no longer leaks edits between visits, and status polling follows the queue (2026-08-19)

*Work in progress, not yet committed.*

- **Hand adjustments became permanent.** The print screen is kept alive
  between openings, and reverting cleared the flags without restoring the
  values: window one cell, close, adjust window, zoom or rotation in the
  viewer, reopen — and none of the viewer's work showed. Reverting now
  restores the values, opening a new film reverts adjustments and cancels any
  in-flight saved-view adoption, and marks are re-synced from the viewer only
  when the follow toggles are on. The viewer's print tray shows marks *as
  picked*, so it no longer flickers with every windowing drag on the print
  screen.

- **Window propagation carried the numbers but not the space.** Peers kept
  their own window space, so the same centre and width meant different
  pictures. The space now travels with them, and "Apply This Window to All
  Cells" is scoped to the current film.

- **A job held for an offline printer waited forever** unless the print screen
  happened to be open, because polling was tied to that screen's lifetime.
  The queue now says which printers have work waiting — excluding paused
  queues and paused jobs, including retrying ones — and monitoring follows
  that demand, polling a newly-demanded printer immediately.

### Fixed — the preview survives a scaling change, says when its tools are off, and sets its corners in one size (2026-08-14)

*Committed in `ac61700` / `de67c39`.*

- **Changing the scaling mode no longer kills the preview.** The mode decides
  which cache draws each cell — Stretch is CPU-drawn, the rest come off the
  GPU — without changing a single mark, so switching to Stretch asked for
  thumbnails that had been deliberately released while the GPU had the film,
  and nothing re-requested them: every cell fell to a spinner, and every tool
  drag looked dead until some unrelated edit happened to refresh the caches.
  The caches now refresh the moment the mode changes.

- **The film says when a job setting has taken the tools away.** Raw pixels
  disable window/zoom/pan/invert by definition, and the job-wide window
  disables per-cell windowing — but both did it silently: the drag was
  accepted and discarded, and the switch that did it sits folded away under
  More. A notice over the film now names the setting and what still works.

- **Identification corners are one block of type again.** A long line — a
  study description, an institution name — used to shrink alone (down to
  half) while the patient's name beside it kept full size, so one cell's
  corners came out in two font sizes; the burner meanwhile drew every line at
  full size, so the film disagreed with the preview too. Preview and burner
  now compute one size per cell — the cell's own, stepped down as a whole
  block until the widest line fits its corner — measured with the same face
  so they step down together.

### Added — the image filter works on a film that mixes series (2026-08-14)

*Committed in `ac61700` / `de67c39`.*

"Filter Images" used to be withheld the moment a second series was marked,
because image numbers restart at 1 in every series and one global "60 to 140"
would have taken a different run out of each. The filter now carries **one
range per marked series**, keyed by the series' identity (Series Instance UID,
with the existing description/folder fallbacks):

- The popover shows a row per series — its description, its marked run, and
  its own From/To fields plus a per-series "All" button. A single-series film
  gets the one row it always had. Rows are named by Series Description: from
  the mark, else read out of the file header alongside the image numbers — so
  a whole-series mark from a UID-named export folder still gets a readable
  name, not the UID.
- Each range clamps to its own series' bounds, and the ordinal fallback for
  unnumbered files now counts within the series, not across the film.
- Everything downstream still reads one filtered list (`printedItems`), so the
  preview, the plan and the print run cannot disagree; ranges whose series
  leave the film are dropped by the clamp, and a new film still starts
  unfiltered.

### Added — the queue survives a restart, the audit trail becomes a record, and four print-correctness gaps close (2026-08-14)

*Committed in `ac61700` / `de67c39`.*

The queue and audit trail built earlier today did their jobs only while the app
stayed up and only for a reader who trusted the file. This pass makes the queue
durable and the trail evidentiary, and closes the FR-004/006 rendering gaps —
one of which printed wrong contrast without saying so.

- **The print queue survives a quit or crash.** Jobs persist to
  `print-queue.json` on every state transition (never on progress ticks — a
  job restarting at 40% would be a lie). On relaunch, jobs that were on the
  printer come back **failed** ("Interrupted — the app quit while it was
  printing"): their association is gone and pretending otherwise would be
  worse. Waiting jobs come back waiting — but the queue restores **held**,
  because an app launch must never open an association and print film on its
  own; resuming is a deliberate act. A waiting job whose source file no longer
  exists fails at restore, naming the path, rather than at print time.
  Reprint therefore survives a restart too: Resend replays the captured
  payload from disk.

- **The queue speaks SRS §6.2's full state language.** SUBMITTING (association
  setup and image preparation) and RETRYING join the states. A job whose run
  *throws* — a dropped association, an unreachable printer — retries
  automatically, up to a cap, a few seconds apart, with the attempt count
  persisted so the §8.2 "retry count < max" gate survives a restart. A printer
  that **answered and rejected** the job does not retry: rejection is final,
  a fault is not.

- **A job for an offline printer waits instead of failing.** The last FR-012
  item: when the status monitor knows a printer is offline, its job stays
  pending — the row says it is waiting for the printer — and the monitor's
  next good report releases it. Strictly FIFO: a later job does not jump an
  offline printer's job, because queue order is a promise about film order.
  Only monitored printers hold jobs; an unmonitored printer has no live status
  to trust, so its jobs run and fail honestly.

- **Jobs can be reordered by dragging** in the queue list. The running job is
  tracked by ID, not position, so moving rows is always safe.

- **The audit trail is now a record, not a list.** Every new event carries a
  session ID (one UUID per app launch), the recording host, and — on
  transitions — the state before and after. Events are **hash-chained**
  (SHA-256, each entry sealing the one before it): editing a recorded field or
  removing an event from the middle breaks every hash after it, and the Audit
  Trail tab shows a red shield naming the first broken link. Trails written
  before these fields existed still load; their events are simply unhashed.

- **Retention is a policy, not a count.** The 500-event cap — which a busy
  department would roll past in days, silently — is gone. Audit events live
  seven years; a failure's *detail text* is redacted after one (the event
  itself stays); the rewrite re-chains the hashes and is itself recorded as
  a `retentionApplied` event, so the trail explains its own edits.

- **The Clear button is gone.** SRS §11.2 forbids deleting audit records, and
  a control whose own dialog conceded "This cannot be undone" had no business
  existing. Retention policy is now the only thing that removes an event.

- **CSV joins JSON and PDF** in the export menus of both the audit trail and
  the job history — the spreadsheet form §11.3 names.

- **A SIGMOID image now prints with sigmoid contrast.** A window carried off a
  viewer mark arrives as two bare numbers, and its VOI LUT Function silently
  defaulted to linear — the one place the never-silently-degrade rule was not
  honoured. The print path now inherits the file's (0028,1056), because the
  function belongs to the image; an explicit non-linear choice on the request
  still wins.

- **A custom Presentation LUT can be sent.** `PresentationLUTTable` travels as
  the Presentation LUT Sequence (2050,0010) — descriptor and 16-bit data — in
  the N-CREATE, instead of a shape, for printers calibrated against a
  site-supplied curve.

- **LIN OD is a density curve, not a negation.** The composer previously
  approximated Linear Optical Density by inverting the pixels. It now maps
  P-values through the film box's Min/Max Density range with transmitted
  luminance falling as 10^(−OD) — mid-gray on film transmits ~4% of full
  light, not 50%. Orientation is unchanged, so existing films do not flip.

- **The film-wide caption band can sit on any edge.** Footer (the default,
  unchanged), header, either side — where the text runs spine-wise along the
  film — or drawn over the images without reserving space. The band is carved
  out of the picture area on its edge only: a side band never costs the
  images height. Chosen in the printer emulator's settings as "Annotation
  position", persisted with the rest of the SCP settings.

### Changed — print preview: what is armed is now visible before the drag (2026-08-14)

*Committed in `ac61700` / `de67c39`.*

The preview's tools were readable only from the rail at the edge of the screen,
and only if you went and looked. Everything here is about making the answer to
"what will this drag do, and to how many cells" available where the hand
already is.

- **The pointer says which tool is armed.** Over a cell with a picture in it,
  the cursor takes the tool's shape — the plain arrow for W/L (matching the
  rail's own pointer glyph, and leaving the default tool's film untouched), a
  magnifier for zoom, an open hand for pan that closes while the drag is
  running, an I-beam for text, a crosshair for arrow. Empty cells and the sheet
  margin keep the normal arrow, since no tool can act there. Via a tracking
  area and `cursorUpdate` (`ToolCursor`), not `NSCursor.push()`/`.pop()`: hover
  callbacks do not arrive in balanced pairs, and moving quickly between cells
  left the pushed cursor stuck over the whole window. The overlay refuses hits
  in `hitTest` rather than through SwiftUI's `allowsHitTesting(false)` — the
  latter takes the view out of cursor tracking too, which is why the shape only
  ever changed when a tool was switched under a stationary mouse.

- **The W/L tool's rail icon is a pointer.** It was `circle.lefthalf.filled` —
  the same glyph the Invert button carries, mirrored — so two buttons a few
  points apart showed the same shape.

### Changed — advanced print defaults for the department setup (2026-08-14)

*Committed in `ac61700` / `de67c39`.*

The sheet now opens with Medium: Blue Film, Destination: Magazine,
Magnification: Bilinear, Presentation LUT: None (unchanged), and the burned
identification includes birth date and institution alongside the always-on
name/ID lines. Nothing here is persisted, so every launch starts from these;
within a session they still survive between films as department settings.
Burned birth date is a deliberate choice — it lives in the pixels and survives
later header de-identification.

### Fixed — the pan tool did nothing on a fill-scaled film (2026-08-14)

*Committed in `ac61700` / `de67c39`.*

Two halves of the same bug, found a layer apart. A fill-scaled cell is showing
a crop at every zoom, so a pan has real travel even unzoomed — but every step
of the pipeline read the picture with the *fitted* geometry:

- `ViewerPresentation.clampedPan` computed its travel limits from the fit
  scale, so at zoom 1 the limits were zero and the model discarded every pan.
  Fixed first: a `covers:` flag scales by `max` rather than `min`.
- That alone moved nothing on screen, because `visibleRegion` — the call that
  decides which pixels the shader and the film actually get — re-clamped the
  now-surviving pan with the same fitted assumption and answered "the whole
  image", which the fill crop then re-centred. The pan lived in the mark and
  died on the way to the pixels.

`visibleRegion` now takes the same `covers:` flag, and the film's real scaling
mode is threaded from one truth to every consumer: the model's clamps
(`panCell`, the zoom-out re-clamp, the linked-cells propagation), the preview
shader (`PrintCellDisplay.presentation`, covering when a fill cell size is
passed), and the print pixel path (`PrintPresentationTransform.apply` via
`PrintService`, from `request.scalingMode`) — so the film prints the same
panned crop the preview shows. `PrintFillPanTests` asserts on what the shader
and the transform are given, not on the stored value, which is exactly the gap
the first fix fell into.

Corrections to the first attempt: Stretch is out of the covering set — it
covers the cell by distortion, not by cropping, so nothing is hidden and a pan
has nowhere to go, same as fit. Fit at zoom 1 likewise remains a no-op by
design: the whole image is on the film, and the preview does not pretend a
drag would print. Zooming a fill cell back out to 1 still keeps the reader's
framing, since zoom 1 there is still a crop. The CPU thumbnail fallback keeps
the fitted read (it is shared with the viewer); a fill cell drawn from it shows
the centred crop only until its texture lands and the GPU path takes over.

- **The tools and locks reset on every visit.** They used to survive as
  "working habits", alongside the printer and film size. The difference is
  that a habit is visible when you come back to it and an armed mode is not:
  a reader who left the pan tool armed with the W/L lock shut pans four cells
  on the next visit's first drag, and finds out afterwards. The screen now
  always opens windowing, nothing locked, nothing picked, scope back to the
  series. Job settings — printer, film size, medium, identification — still
  survive, as before.

- **The sync locks are in the same order as the tools.** W/L, Zoom & Pan,
  Invert — matching the rail above them, so a lock sits where the tool it
  holds together does.

- **Separators are visible.** The rail's group rules and its edge against the
  film were hairline `Divider`s that all but vanished; they are now a 1pt rule
  at 45% secondary. The rail's grouping is what makes eleven buttons readable
  as four groups.

- **Every control on the rail has a key.** The five tools already had W, Z, P,
  T, R; the sync locks, the scope and Pick did not, and those are exactly the
  controls reached for mid-drag with the other hand on the film. A lock takes
  its tool's key shifted — ⇧W, ⇧Z, ⇧V — which is the same tool-to-lock pairing
  the rail now shows by ordering them alike. S swaps a shut lock's reach
  between Series and Film; A picks the run of cells from the focused one, or
  lets a picked set go. The full table is documented on `toolShortcuts`.

- **One door for shutting a lock.** The rail button, the context menu and the
  new shortcut all go through `toggleSyncFromUI(_:)`, which carries the window
  seeding (cells never opened have no window for a relative edit to work from)
  and the job-wide-window refusal. Previously the seeding was copied into each
  call site; a shortcut is delivered whether or not a disabled button would
  have taken the click, so that refusal had to move below the button.

- **Tooltips are a guide, not a label.** Every tool, lock, scope, selection
  and reset control now states the gesture, what it changes, its shortcut, and
  — read live from the same rules the drag itself uses — how many cells the
  next drag will actually reach. The film size, printer, orientation and copies
  controls gain the tooltips they never had, and the film size menu is labelled
  "Film Size" rather than "Film", which read as a heading for the whole bar.

### Added — app-side print queue and audit trail (2026-08-14)

*Committed in `ac61700` / `de67c39`.*

Queue management and the audit trail are app responsibilities, so both live
entirely in DICOMStudio — no package logic moved, and no login module: the
trail records what this app instance did, not who was signed in.

- **Print jobs now go through a queue.** `PrintQueueService` (DICOMStudio)
  executes submitted jobs one at a time, so two jobs never interleave
  associations on the same printer. Jobs move through pending → running →
  completed/failed, with paused and stopped under user control. The print
  sheet still mirrors its own job's phase, console, progress and result —
  through handlers the queue calls — so the submit flow looks unchanged.

- **Queue management screen.** The Print Center's right pane gains a
  Queue / History / Audit Trail switcher. The Queue tab lists every job with
  its state, progress and attempt count, with per-job actions the state makes
  meaningful — Start Now (jump the line), Pause/Resume (hold a waiting job),
  Stop (cancel; the SCU N-DELETEs the film session), Resend (a finished job
  re-enters the queue as a fresh attempt with the same captured payload),
  Remove — and queue-wide Pause/Resume, Stop All and Clear Finished.
  A running job cannot pause: its association is already open, so pausing
  one is refused rather than half-honored.

- **Audit trail, recorded and persisted app-side.** Every queue action and
  job outcome — submitted, started, completed (with Print Job UIDs), failed,
  paused, resumed, stopped, resent, removed, queue-level actions, history
  clearing — lands in `print-audit-trail.json` (newest first) the moment it
  happens, so a crash mid-job still leaves a record. The Audit Trail tab
  browses it with text search, an action filter and export. (Retention,
  tamper evidence and the removal of the clear control are in the later
  entry above.)

- **Both records export as PDF as well as JSON.** The Export button in the
  History and Audit Trail panes is now a menu offering **JSON…** or **PDF…**.
  JSON is unchanged and still byte-identical to the on-disk store, for another
  program to read. PDF renders a paginated Letter-size report — title, row
  count and generation date, ruled column headings, and a page footer — for
  the reader who is filing it with a QA record or handing it to a service
  engineer rather than running `jq` over it. The audit PDF always covers the
  whole trail, not the current search filter: an exported audit record that
  silently dropped rows would be a misleading document to file. Empty records
  still produce a one-page "No records." report, since a zero-page PDF is a
  file no viewer will open.

- **History records resends too.** Job history is now written by the queue's
  completion callback rather than the print sheet, so a job resent from the
  queue screen lands in Recent Jobs like any other. Cancelled jobs stay out
  of history — it remains a record of jobs that were sent — while the audit
  trail keeps the stop.

### Added — the print history answers questions, not just lists jobs (2026-08-14)

*Committed in `ac61700` / `de67c39`.*

The history stored every job's Print Job SOP Instance UIDs but never showed
them again: "did that print?" could only be asked while the print sheet was
still open. The Print Center's Recent Jobs pane now closes that loop.

- **Check Status on a past job.** Each history row with recorded job UIDs gains
  a **Check Status** button that N-GETs every film's execution status from the
  printer the job was sent to (found by name — if the profile has since been
  removed, the row says so instead of failing silently). Multi-film jobs get
  one line per film — `Film 2: FAILURE (CHECK PRINTER)` — coloured and
  glyphed by state, matching the print sheet's own status display. Results are
  in-memory only: an execution status is what the printer says now, so a stale
  answer from a previous launch would mislead. The query runs through a new
  `PrintJobStatusQuerying` seam (same pattern as the status monitor's probe),
  so the flow is tested without a printer on the network.

- **The UIDs are visible at last.** Hovering a history row shows the Film
  Session UID and Print Job UID(s) as a tooltip.

- **Fixed: the emulator forgot its print jobs the moment the SCU released.**
  `DICOMPrintServer` kept Print Job records on the association, so any status
  query on a later association — which is how "Check Status" necessarily asks —
  answered 0x0112 *No such SOP Instance* for a job it had just printed. Film
  session state is rightly association-scoped (PS3.4 H.4), but the Print Job
  SOP Instance is exactly the part that must outlive the release (PS3.4
  H.4.8). Jobs now live in a server-wide `PrintSCPJobStore`, bounded to the
  100 most recent. A loopback test prints, releases, and N-GETs the job on a
  fresh association.

- **Export… and Clear…** in the Recent Jobs header. Export writes the history
  as JSON in the exact on-disk format (`print-job-history.json`), so an
  exported audit file and the live store are interchangeable. Clear asks first
  and removes the entries from disk as well.

### Added — the workstation notices a printer changing state on its own (2026-08-13)

*Committed in `ac61700`. Closes five of the six FR-012 sub-items
of `PRINT_SRS_CONFORMANCE_REPORT.md`; the sixth needs FR-011's queue.*

A printer's state was only ever as fresh as the last time somebody pressed a
button, and it was reported in two colours where the standard defines three.
A printer low on film looked exactly like one that had failed.

- **A printer's state is now a closed enum, not a string comparison.**
  `PrinterStatusSeverity` covers the three states PS3.3 C.13.9 defines —
  NORMAL, WARNING, FAILURE — plus `unknown` for an SCP that answered with
  something else. Parsing is lenient about padding and case, because CS values
  arrive padded and non-conformant printers vary the case; anything it cannot
  place becomes `unknown` rather than being read as healthy, since the
  dangerous failure is a printer we cannot understand being handed a job.
  `PrinterStatus.isNormal` keeps working, joined by `isWarning`/`isFailure`.

- **WARNING is no longer reported as an error.** `ServerConnectionStatus` gains
  a `warning` case and the status pane maps onto it, replacing
  `status.isNormal ? .online : .error` — which had been telling the user a
  printer with low film was broken. A warning printer still accepts jobs, per
  the SRS: blocking on it would stop usable work. Warning and failure differ in
  glyph as well as colour, so the distinction survives for a colour-blind
  reader.

- **Background polling on a configurable interval (10–300s).**
  `PrinterStatusMonitor` runs one task per printer rather than a shared timer,
  so an unreachable printer cannot set everyone else's cadence. The first poll
  is jittered: printers enabled together would otherwise open associations in
  lockstep for as long as the app runs. On failure the interval doubles to a
  ten-minute ceiling and resets the moment the printer answers, so a printer
  switched off overnight is not probed every ten seconds until morning.

- **Monitoring is opt-in per printer, and off by default.** Polling opens a
  real association on someone's hospital printer; that is a thing to ask for,
  not something to switch on for every profile a user has ever saved.

- **Polled status is deliberately not persisted.** It is observed state, and
  writing `printer-profiles.json` on every poll would rewrite the file every
  few seconds per printer to store something meaningless after a restart. The
  interval and the opt-in *are* persisted, and a profile written before those
  fields existed still decodes — an older file loads with monitoring off
  rather than dropping every printer the user configured. An out-of-range
  interval, from a hand-edited file or an older build, is clamped rather than
  trusted: at zero it would be a hot loop against a hospital printer.

- An unreachable printer reports as offline, a failed one as error. "We could
  not ask" and "it answered and said it is broken" are different facts, and an
  operator needs to tell them apart.

- 43 tests. The probe and the clock are both injected, so the backoff curve,
  the lifecycle and the legacy-JSON decode are asserted without a real printer
  or a real second passing.

### Added — print scaling modes, table LUTs, and optional identification fields (2026-08-13)

*Committed in `ac61700`. Closes the FR-003 / FR-004 / FR-006 gaps
of `PRINT_FR_003_004_006_PLAN.md`; every default reproduces the previous
output byte for byte.*

- **Scaling modes (FR-003).** `PrintScalingMode` — Fit to Film (the old and
  still-default behaviour), Fill to Film, True Size (1:1), and Stretch — with
  9-way `PrintCellAlignment` positioning. Fit and fill travel to a real
  printer as Requested Decimate/Crop Behavior (2020,0040); true size
  additionally sends Requested Image Size (2020,0030), computed per image from
  Pixel Spacing / Imager Pixel Spacing / Nominal Scanned Pixel Spacing —
  column spacing × columns, so a crop narrows the request with it, a quarter
  turn swaps the axes, and a free-angle resample clears it. An image with no
  recorded spacing falls back to fit **with a console warning**, never
  silently: a wrong-scale film is one a clinician might measure against.
  Stretch and the alignment have no DICOM form and apply where the toolkit
  composes the film itself (preview, Save Film, the SCP emulator); the
  settings sheet says so. The film-box composer's CROP path now honours
  Requested Image Size (PS3.4 H.4.3) instead of ignoring it. In the live
  preview, fill is composed into the display shader's *source region* — the
  cell's Metal view keeps one size through every tool drag, which is what
  keeps a tool step at one quad redraw — and stretch draws on the CPU path,
  which can ignore the aspect. True size and non-centre alignment draw as
  centred fit on screen (a panel-scaled sheet has no physical size) and are
  exact on the composed film. Print preview cells sample bilinear where the
  viewer stays nearest-pixel: a film cell is judged as a picture, its
  CPU-drawn neighbours are smoothed, and a cell must not change texture the
  moment its GPU texture arrives.
- **Table-form LUTs (FR-004).** `GrayscaleLUT` decodes the Modality LUT
  Sequence (0028,3000) and VOI LUT Sequence (0028,3010): descriptor entry
  count 0 meaning 65536, sign following the pixels (and, for VOI, a negative
  rescale intercept), byte- and word-packed data, clamping at both ends, and
  normalization over the table's actual range so a 12-in-16-bit table keeps
  the film's full dynamic range. A Modality LUT **replaces** the rescale pair
  (PS3.3 C.11.1 makes them mutually exclusive); the VOI precedence is now
  explicit user window → VOI LUT table → header Window Center/Width →
  auto-stretch. Before this, an image whose presentation requires a table LUT
  printed with the wrong contrast, silently.
- **Window presets beyond CT and MR (FR-004).** CR/DX, MG, PT (SUV), NM and
  XA/RF join the preset table, in the viewer and the print cell tools alike.
  US stays empty deliberately: its frames are display-ready and a fixed
  window would be an invented number.
- **Optional identification fields (FR-006).** Birth date, accession number,
  institution and series description can join the burned caption — each
  opt-in, each in a documented corner, all off by default so the default film
  is unchanged. Birth date stays off unless deliberately chosen: burned into
  pixels it survives later header de-identification. Caption typography is
  now configurable (`PrintAnnotationStyle`: font family, size as a fraction
  of the frame clamped to a legible 2–10%, forced white/black that still
  flips for MONOCHROME1); the automatic style remains the default and the
  recommendation. The film footer's minimum type size rises from 2.5 mm to
  2.82 mm — the SRS's 8 pt floor stated physically.

### Changed — every film cell says what made its picture (2026-08-10)

*Committed in `ac61700` / `de67c39`.*

The caption under a film cell named the patient and the study, and stopped
there. A reader comparing two slices on one sheet is comparing their technique
as much as their anatomy, and that was on neither.

- **What made the picture, each value under its own label.** `Modality: CT`,
  `Image: 45` — the acquisition sequence number, with the series left off, since
  a cell is one image and its series is already named by the study description
  above it — then the technique that modality is actually read by:
  `Slice Thickness: 5.00 mm` and `kVp`/`Exposure` on a CT, `TR`/`TE` and
  `Field Strength` on an MR, `kVp`/`Exposure`/`View` on a plain film, thickness
  and `Radiopharmaceutical` on PT/NM. Anything the list does not know still gets
  its slice thickness. Labelled because "5.00 mm" alone could be a thickness, a
  spacing or a slice interval; whatever the scanner did not record is left off,
  since a film that prints "kVp:" with no number beside it has said something
  false about a machine. The patient and the study stay unlabelled — a name
  reads as a name.
- **The study date carries its time.** `15 Oct 2025 14:32`, to the minute: a
  patient can be scanned twice in a day, before and after contrast, and two
  films differing only by the hour are two films nobody can put in order.
- **The film footer is gone.** Stating the identification once at the foot of a
  sheet only worked while every cell said the same thing; a caption that names
  the image's own number and thickness cannot be lifted off the picture it
  belongs to. Captions are now always under the image, burned into the pixels
  that carry them, so nothing depends on whether a printer honours annotation
  boxes. The "Caption" placement picker and its context-menu twin are gone with
  it; the identification switch remains.
- **The caption moved into the corners, as on the viewer.** Not a strip below
  the picture: the corners of a fitted image are background, the reader's eye is
  in the middle, and a caption under the picture is one read by looking away
  from the anatomy it describes. The arrangement is the workstation's — who and
  what at the top right, what made the picture at the bottom left, the study
  date at the bottom right, the top left left clear for the printer's own label
  — so a film and the screen it was approved on are read the same way.
- **The picture gets its rows back.** Nothing is scaled to make room, in the
  preview or in the burned pixels: `ImageAnnotationBurner` draws the four corner
  blocks over the frame with a halo at the opposite end of the greyscale, so
  each line survives both a white lung field and a black background, and
  `PrintCornerAnnotation` is what the preview and the burner both lay out from.
  Set plain, at one weight, on screen and on film: nothing in the corners is a
  different kind of statement from anything else there, and the halo is what
  keeps a line legible, not its weight. The blocks are pushed into the corners
  of the *cell* rather than of the picture inside it — a frame that is not the
  cell's shape leaves a letterbox margin, and text held to the picture reads as
  floating in the middle of the sheet — and set a size smaller than the viewer's
  corners, since a film cell carries more lines in less room.

### Fixed — the range filtered by position, and ⌘-click never landed (2026-08-11)

*Committed in `ac61700` / `de67c39`.*

- **The image range now matches the series' own numbers.** It was falling back
  to each mark's *position in the tray*, which equals the image number only when
  a series is marked whole, from image one, with nothing skipped — so "3 to 9"
  printed whichever seven marks sat in those slots. Marking a whole series
  records paths and no numbers on purpose (reading two hundred headers to label
  a tray nobody has opened would stall the viewer), so the numbers are now read
  from the files themselves: header only, stopping at Instance Number, done once
  and kept, and only when the range control is actually opened. The control
  greys out while it reads rather than letting a range be typed against half the
  numbers.
- **⌘-click reaches the selection.** It was expressed as a second, modified
  `TapGesture` alongside the plain one, and SwiftUI's priority rules gave the
  plain one the click — so every ⌘-click arrived as an ordinary click, the
  picked set never grew past the cell clicked last, and Delete took only that
  cell. The modifier is now read from the event inside the one tap handler, so
  there is no contest to lose. A plain click on an unpicked cell clears the set,
  which is what makes "click somewhere else and start again" work.
- **Delete works from the keyboard.** It was handled by the film's own key
  handler, which needs the film to hold keyboard focus — after a click in the
  settings column or the range popover it does not. It is a shortcut now
  (⌫ and ⌦), delivered wherever the print screen is, and still takes a selected
  annotation before the cell it was drawn on.

### Added — a run of the series, and thinning a sheet out (2026-08-11)

*Committed in `ac61700` / `de67c39`.*

- **Images: from ( ) to ( ).** A CT of two hundred slices is fourteen sheets, and
  the reader wants the four where the finding is. The range names them by the
  image's own number — the one printed in the cell's corner — and the films are
  laid out from what falls inside it.

  It is a **filter, not an edit**: the marks it holds back keep their windowing
  and their arrangement, widening the range brings them straight back, and *Load
  All Images* is one click rather than a re-mark of the series. One filtered
  list feeds the plan, the preview and the print run, so the sheet on screen is
  the sheet the printer receives. Offered for a single series only — across two
  the numbers restart, and one range would take a different run out of each.
- **Cells come off the film with ⌫.** The picked cells, or the focused one, from
  the cell's own menu or the delete key — which still takes a selected
  annotation first, innermost thing first. The rest of the film shuffles up in
  order: image 7 moves into the hole image 4 left, no cell is left blank in the
  middle of a sheet, and the last film simply ends earlier. The focus lands on
  the cell that moved up into the first hole, so a run of deletions is done from
  one spot instead of chasing the picture around the sheet.
- **Locks stop at the edge of the sheet.** A locked window or zoom now reaches
  only the film being judged. It is the sheet in front of the reader and the
  only one whose cells they can watch move; re-windowing thirteen films nobody
  has turned to is an edit whose effects are discovered on paper. The scope
  choice is now *Same Series* or *Whole Film*, both read as "…on this film", and
  "All Cells" is gone.

### Added — picking out the cells a tool acts on (2026-08-11)

*Committed in `ac61700` / `de67c39`.*

The locks answer "which cells move with this one" by rule — same series, this
film, everything. That is right when the rule is the intent. It is the wrong
shape for "these four, and not the rest", which is common enough that stating
it as a rule is a chore.

- **⌘-click picks cells out.** A checkmark badge marks each one, a thin accent
  ring draws round it, and the film's caption says how many are picked. Escape
  clears them, and so does the rail's own button.
- **Select ▸ Succeeding Cells on This Film**, on the cell's right-click menu,
  takes the focused cell and everything after it on the sheet — stopping at the
  film's edge, so what a drag is about to touch is on screen to be seen. *All
  Cells on This Film* is beside it.
- **A selection outranks the locks.** While two or more cells are picked, every
  tool — window, zoom/pan, invert — acts on exactly those and the locks stand
  aside. An explicit selection is a statement the reader has just made by hand,
  and a lock quietly widening it to the rest of the series would undo the point
  of making it. Drag a cell that is *not* picked and it moves alone. Clear the
  selection and the locks are in charge again, unchanged.
- **A job-wide window still wins.** Nothing per-cell reaches the film then, so a
  picked selection carries no window edit either — geometry still travels.
- **The lock badge moved to the top left.** The identification now occupies the
  top right and both bottom corners, and a badge over a patient's name is a
  badge over the one thing on the film that must stay legible.
- **The film grew into the slack it already had.** The page arrows float over
  the empty gutter beside a portrait sheet instead of charging the picture 68
  points for two chevrons standing in space; when the panel is too tight for
  that, they take their gutter back and the sheet fits in the rest. The layout
  button now says what it is — *Layout: 4×5*.

### Fixed — a film of sixteen cells loaded one decode at a time (2026-08-11)

*Committed in `ac61700` / `de67c39`.*

`FrameSourceCache` is an actor, and it read and decoded the file *inside* its
own isolation. Every cell after the first therefore queued behind a full
JPEG 2000 decode, and a window/level drag — which needs nothing but pixels
already in hand — queued behind all of them: a 4×4 film trickled in row by row
and the tools felt dead while it did.

- **The decode runs off the actor.** The cache is shared state and has to be
  serialised; the codec is not. Each path's decode is a detached task the actor
  awaits, so sixteen files decode concurrently and sixteen cells of one file
  share a single decode.
- **A byte budget, not a file count.** The cache held three files, which is far
  too few for a film whose every cell is being adjusted — loading cell sixteen
  evicted cell one, so dragging it re-decoded from disk. It now holds 256 MB of
  decoded pixels, never fewer than three files, which is a whole CT film over.
- **Identification is read per film.** The preview parsed every marked file's
  header up front — a hundred marks is a hundred full reads competing for the
  same disk and cores as the decodes the cells are waiting on. It now reads the
  film on screen, and the next one when it is turned to.
- **A new layout loads its new cells.** The preview refreshed its caches when
  the film index or the mark list changed, and a layout change alters neither:
  a 2×2 turned into a 4×4 showed the four pictures it already had and twelve
  spinners nobody had asked to render, until some later event happened to
  refresh them. It now watches the cells the film is actually showing, which is
  the thing all three of those changes have in common.

### Added — linked film cells: adjust one, adjust them all (2026-08-07)

*Committed in `ac61700` / `de67c39`.*

"Apply this window to all cells" was a one-shot copy made after the fact. Judging
a film means comparing its cells, and cells can only be compared when they are
shown alike — which meant repeating every zoom by hand, cell by cell.

- **The tools are back on a rail, and the locks are on it too.** Window/level,
  zoom, pan, text, arrow and invert (`V`) sit down the left of the film with the
  three locks,
  the scope and the two resets. A right-click menu is a fine place for a command
  and a poor place for a *mode*: which tool is armed and which cells are linked
  have to be answerable at a glance, and a menu that only exists while it is open
  cannot answer them. The menu keeps everything it had.
- **The lock is drawn on the cells it applies to.** A closed padlock appears on
  every cell that will move when the focused cell is dragged — and on none that
  will not, which is how the scope becomes visible before the drag rather than
  after it. It is the one thing the preview draws over a picture that the film
  will not carry, sits in the corner over the letterbox margin, and takes no
  clicks.
- **A mode, not a command.** `PrintCellSyncOptions` — Zoom & Pan, Window, Invert
  — are locks on that rail. While one is on, dragging a cell carries that
  adjustment to the others as the gesture happens. Zoom and pan are one switch
  deliberately: cells that magnify together but sit over different anatomy are
  the confusing state, not one anybody asks for. Rotation and flip are not
  offered: they are how one image is put the right way up, and turning the whole
  sheet because one cell was upside down is never what was meant.
- **A way back out.** Reset Cell and Reset All sit beside the links (`0` and
  `⇧0`), because one linked drag can now put a whole sheet wrong and undoing it
  must not be harder than causing it. The cell menu's reset still acts on the
  cell that was right-clicked, and names itself so.
- **A dragged cell keeps up with the drag.** A window/level drag re-keys the
  cell on every mouse event, so its GPU render nearly always landed after its own
  key had been superseded — and `PrintCellTextureCache` threw those renders away,
  leaving the cell being dragged showing the picture the drag started from. A
  superseded render now stands in for the mark it belongs to, so the cell tracks
  the drag a dispatch behind instead of stalling.
- **Geometry copies absolutely, windowing carries relatively.** Every cell on a
  film is the same size, so the same zoom and pan is the same picture, and each
  peer's pan is then re-held inside its own image. A window is not portable that
  way — a film mixes modalities, and marks do not all state their window in the
  same space — so a drag scales each cell's width by the same factor and shifts
  its centre by the same fraction of a width. Presets are the exception: "lung"
  names a tissue, so it is copied as the numbers it is.
- **Scope, because a film is not always one series.** All Cells / Same Series /
  This Film, defaulting to Same Series — a film carrying two series is usually
  carrying them for comparison. Marks now carry their Series Instance UID for
  this; marks made without opening a file group by the folder they came from.
- **It yields to the job.** With raw pixels or a job-wide window on, nothing
  per-cell reaches the film, so the window link reads and behaves as off rather
  than claiming an effect the job has already taken away. Marks never opened are
  given their file's own window when the link goes on, so they move with the
  rest instead of sitting still.

### Added — a film of one study names its patient once (2026-08-07)

*Committed in `ac61700` / `de67c39`.*

Identification was burned under every image, which is right for a sheet that
mixes studies and repetitive noise on a sheet that does not: sixteen cells of one
CT carried the same name sixteen times, each one costing its picture a strip of
height. With multi-study selections coming, "print this film" has to answer both
cases.

- **The rule, in one place.** `FilmIdentificationPlanner` decides per *film*, not
  per job: a sheet whose captioned images all share one Study Instance UID states
  the patient once along its bottom edge; a sheet mixing studies captions each
  image, as before. A job spilling onto a second sheet has each sheet decided on
  its own, because each sheet has to be identifiable on its own. The UID is the
  test rather than the caption text — two studies of one patient on the same day
  read identically and are still two studies. An image whose header could not be
  read has no study to agree with, so it forces per-image captions.
- **The strip is kept clear of the pictures.** `FilmCellLayout` takes a footer
  band out of the sheet before it lays out cells, so the footer sits under the
  bottom row rather than across it — text over anatomy is where a finding hides.
  Annotation boxes generally now get that band too; they used to be drawn into
  the bottom margin over whatever was there, and they are centred rather than
  flush left.
- **It reaches real film three ways.** Composed sheets (Save Film, the printer
  emulator) draw the footer themselves. On the wire it goes as a film-level Basic
  Annotation Box — `PrintOptions.filmAnnotations` carries a set per film, so two
  sheets of one job can name two patients, which one job-wide list could not.
- **Whether the printer can carry it is asked, not assumed.** The first cut
  looked at whether an Annotation Display Format ID had been typed into the
  settings sheet, so every printer that had not been configured by hand — which
  is every printer, by default — silently fell back to captioning each image and
  the film never matched the preview. Support is now a question about the
  association: `DICOMPrintService.supportsAnnotationBoxes` opens one, asks
  whether the Basic Annotation Box SOP Class was accepted, and releases. It is
  asked *before* the frames are prepared, because the answer decides whether they
  are captioned. A printer that takes annotation boxes but has no configured
  format ID gets a plain default (`ANNOTATION`), since a film box cannot carry
  annotation boxes without one; a printer that refuses the film box over that
  value has it created again without it rather than losing the job, and the
  progress line says the film will carry no annotation text. A printer that takes
  no annotation boxes at all — or cannot be reached — still gets the caption
  burned under each image: a film with no name on it is worse than a film that
  repeats one.
- **The footer's type is sized off the film.** It was a flat 3 mm, which is
  oversized on an 8×10 held in a hand and lost on a 14×17 across a viewing room.
  It is now 1.1% of the sheet's height, floored at 2.5 mm and capped at 6 mm —
  ~2.8 mm on 8×10 and ~4.75 mm on 14×17 — and the strip reserved for it, in the
  composer and in the preview alike, follows the type rather than a constant.
- **Choosable, in the preview and in the settings column.** Automatic (the rule
  above), "Under each image", or "Once at the foot of the film". The preview
  draws whichever the film will carry, scaled off the physical sheet, so the
  strip that is approved is the strip that prints.

### Changed — the print preview stays shut, opens wider, and writes the film out (2026-08-07)

*Committed in `ac61700` / `de67c39`.*

- **A launch shows the library and nothing else.** Print Preview and Printer
  Emulator are singleton `Window` scenes, so macOS restored whichever was open at
  quit — the preview holding no marks and the emulator with its server stopped,
  because neither survives the app. Both now carry `.restorationBehavior(.disabled)`
  and `.defaultLaunchBehavior(.suppressed)`; they open when they are asked for and
  not before.
- **The console log column is as wide as the reader wants it.** It was a fixed 300
  points, which wrapped every import path and print job UID into four lines. It
  now opens at 460 and is dragged from the divider between it and the film, up to
  60% of the panel and never below 260; the width is kept in `AppStorage`, so it
  is chosen once rather than every job. The film takes back whatever the log is
  not using, as it did before.
- **The film can be saved as a file.** "Save Film" in the preview's header writes
  PNG, TIFF or PDF. Not a screenshot of the preview: the images go through the
  same `PrintService.prepare` a real print sends them through and the sheet comes
  out of the same `FilmComposer` the printer emulator composes received film
  with, so what lands on disk is the sheet the printer would have laid down —
  identification band, drawn annotations, spillover and all. A PDF holds every
  film of the job as a page; PNG and TIFF write one file per sheet.

### Added — film layouts the standard has and a grid has not (2026-08-06)

*Committed in `ac61700` / `de67c39`.*

PS3.3 C.13.3 lets a film's rows hold different numbers of images: `ROW\1,3` is a
scout above three slices, `COL\1,2` is one image beside two. The Print SCP has
always understood those forms — it has to, modalities send them — but everything
that *composes* a film here could only say rows × columns, so the one layout a
reader most often wants for a comparison film could be received and not sent.

- **Seven band layouts are in the gallery, drawn.** `ROW\1,2`, `ROW\2,3`,
  `COL\1,2`, `COL\1,3`, `COL\1,4`, `COL\1,4,4` and `COL\2,4,4` are picked the way
  the grids are — by looking at the film rather than reading a string — and live
  in `PrintBandLayout` in `PrintOptionCatalog`, the one table the print sheet and
  `dicom-print --layout` both read.
- **The print sheet takes a format string too.** Under the bands is a Custom
  field: type an Image Display Format and the film beside it is redrawn as it is
  typed, with the layout named in words underneath ("rows of 1, 3 — 4 images").
  Picking a band fills that same field, so the layout in force can always be read
  as the string that will be sent, and adjusted from there. Text that is not a
  format says so in red and leaves the film on the automatic grid rather than
  quietly printing 1×1, which is what a lenient parse would have made of
  half-typed input. The gallery scrolls now that it holds four sections.
- **The preview draws the film, not a grid.** `FilmPreviewView` lays its cells
  out with `FilmCellLayout` — the same geometry the SCP composes received film
  with — instead of a SwiftUI `Grid`, so a band layout is shown as the bands it
  is. Every per-cell measurement (zoom and pan limits, annotation anchors, the
  identification strip) now comes from that cell's own rectangle; it used to come
  from one film-wide size, which was only ever right because the cells were all
  the same. Arrow-key navigation follows the cells' geometry for the same reason.
- **The format reaches the printer verbatim.** `PrintLayoutSelection` gained a
  `.displayFormat` case, `PrintJobRequest`/`PrintPlan` carry the format and count
  films by its image-box count, and the SCU sends the string as written. Verified
  end to end against `dicom-printscp`: `--layout 'ROW\1,3'` composes one image
  over three, `'COL\1,2'` one beside two, `'COL\1,4,4'` one beside two columns
  of four.
- **`dicom-print --layout` accepts both.** A grid token ("2x3") as before, or a
  format (`'ROW\2,1,2'`, quoted so the shell keeps the backslash); the named
  bands are listed in its help. The dry-run banner and the film plan name a band
  layout by its format string — reporting `ROW\1,1` as a 2×1 grid would have
  misstated the film.
- `PrintImageDisplayFormat` gained `validated(_:)` (strict, for UI and command
  lines), an initializer from a `PrintLayout`, `isUniformGrid`, and `summary`.

### Changed — the viewer opens on the images (2026-08-06)

*Committed in `ac61700` / `de67c39`.*

Opening a study put four columns on screen before the first picture: the app's
feature list, the series pane, the images, and an empty selection tray. Two of
them were answering questions nobody had asked yet.

- The feature sidebar steps aside on the way into the viewer and comes back on
  the way out (`MainView` drives `columnVisibility`). The toolbar toggle still
  opens it over the images, and that choice holds until the viewer is left.
  Launching straight into the viewer starts collapsed too.
- The selection tray starts hidden (`isPrintTrayVisible` now defaults to `false`)
  and comes up on its own the moment the first image is marked — every marking
  path, the library's "Print…" included, goes through `revealPrintTray()`.
  Unmarking never puts it away again, so the "Clear" button cannot vanish under
  the pointer; opening a different study does, along with the marks it held.
- The current series is marked by one cue, on the card: a neutral white ring and
  a lifted surface. Nothing is drawn on the thumbnail — a ring there framed the
  letterboxing rather than the picture — and the accent stays out of the pane
  entirely, because in the viewer it means "this is what prints".
- In the grid, a marked tile no longer carries an accent edge along its bottom.
  The chip and the tick already say it, and with a film fully composed the edge
  drew a blue rule under every tile; the only accent edge left in the grid is the
  focus ring, so exactly one tile is lit — the one being worked on.

### Changed — the viewer's three columns are told apart (2026-08-06)

*Committed in `ac61700` / `de67c39`.*

The series pane, the reading area and the selection tray all sat on the same
near-black surface, so nothing on screen said which column held the images that
were about to print:

- Three planes instead of one. The panes are a lighter surface
  (`StudioColors.viewerPanel`) with a dark seam on the side facing the picture;
  the gutter is darker than before (0.14 → 0.10); the reading area keeps its pure
  black and gains a shadow that lifts it off the mount.
- Every column is titled. A shared `ViewerPaneHeader` names the panes ("Series",
  "On film" with its count); the reading area's own strip names it, shows the tile
  layout, and reports "N of M on film" — the count of images *on screen* that are
  marked, so the middle column visibly owns the print selection.
- The reading area's frame is thicker and keeps the accent while it holds the
  keyboard, in a grid as well as at 1×1.
- Marked tiles are readable across a whole grid: a numbered film-position chip in
  the top-left corner (the number the tray lists it at) and an accent bar along the
  bottom edge. The border stays focus-only — the live tile's ring went 2 pt → 3 pt,
  and hovering brightens a tile's hairline.
- The patient plate in the series pane is neutral rather than accent-tinted: in the
  viewer the accent now means "this is what prints".

### Changed — the print preview is a window, not a sheet (2026-08-06)

*Committed in `ac61700` / `de67c39`.*

- The preview's cells now draw from GPU textures (`PrintCellTextureCache`), because
  the preview is where the tools are used: window/level, zoom, pan, rotate, flip and
  invert were each a CPU re-render per mouse delta. The arrangement is the display
  shader's transform, so those drags now re-draw a quad and render nothing; only a
  window change makes a new texture, and that is one GPU dispatch. A re-windowed cell
  holds its previous texture while the new one renders, so a drag never falls back to
  the CPU. Falls back per cell — overlay planes, YBR, an unresolvable window, no
  Metal — never per film. Only the film on screen holds textures.
- The shader is given the *film's* geometry, not the viewer's: new
  `DisplayPresentation.sourceRegion` fits and centres the region that
  `ViewerPresentation.visibleRegion` — the same call the print path makes — says will
  be cropped, and flips after the rotation as `PrintPresentationTransform` does. The
  viewer's own transform agrees with the printer only while a cell is merely zoomed,
  so reusing it would have misreported every rotated or edge-panned cell.
- Film composition and export are unchanged and still CPU, as the GPU plan fences
  them: preview and film agree because neither invents anything the other does not.

- On macOS the print preview opens in its own window (`StudioWindowID.printPreview`)
  instead of a modal sheet over the viewer, so the film can be compared with the
  images it was made from, moved to a second display, or zoomed to fill one.
  ⌘P and the library's "Print…" both raise it; `PrintScreenPresenter` keeps the
  sheet on platforms without windows.
- `PrintSettingsView` takes a `presentation` (`.sheet` / `.window`): a sheet is
  still given a fixed size, a window only a minimum, so the user's own size sticks.
- The Print screen gained a "Print Preview" button that raises the window — the
  preview no longer has to be re-opened from the viewer once it has been closed.
- Opening a study closes the print preview window along with clearing the marks:
  the film on it was composed from the study being left. `prepareForNewStudy()`
  bumps `printScreenDismissRequests`, which the shell turns into a
  `dismissWindow` — watched there rather than in the viewer, since the study may
  be opened while the library is still on screen.
- The print log console starts closed and opens by itself when a job starts,
  giving the film its width while the film is what is being judged. It is put
  away again on "Print Again", and the header toggle still overrides both.

### Added — Metal GPU frame rendering, `DICOMRenderKit` (2026-08-04)

Full GPU rendering pipeline for the viewer, landing GPU plan milestones M0–M7
(see `GPU_RENDERING_PLAN.md`):

- New `DICOMRenderKit` target: a Metal compute pipeline that windows/LUTs a decoded
  frame directly into a `CGImage`-readable texture with zero-copy UMA input and no
  upload/render/readback round trip. Monochrome and RGB/palette kernels; YBR stays
  on the CPU. Output is byte-for-byte identical to the CPU path
  (`MetalCPUEquivalenceTests`), so the two are freely interchangeable.
- Shared `WindowLUT` (integer, not float shader math) backs both the CPU and GPU
  paths — 10–19× faster monochrome rendering on its own (M0+M1), before any GPU
  work.
- Focused-viewport direct-to-display path keeps the frame on the GPU across tool
  actions (window/level, invert, zoom, pan): 0.008 ms per action, down from a full
  re-render (M5). The per-drag decode is cached too, up to 675× faster per step.
- `minimumGPUPixelCount` dropped from 1 megapixel to 0 — no frame is declined for
  being small; the CPU is now purely the no-GPU fallback, not a size-selected
  alternative. Safe only because of the CPU/GPU output equivalence guarantee above.
- Shipped the compute shader as `.metal.txt` so the app builds without requiring
  the separate Metal Toolchain install in Xcode.

### Added — corner annotations and GPU textures for unfocused tiles (2026-08-04, in progress)

*Committed in `ac61700` / `de67c39`.*

- On-screen viewer tiles and the focused viewport now carry the traditional
  four-corner reading-room annotation layout — size/window/cursor readout
  (top left), patient/study identification (top right), zoom/position/
  compression/geometry (bottom left), acquisition date/time (bottom right) —
  composed by `ViewerAnnotationCorners`/`ViewerAnnotationText` and drawn by the
  new `ViewerAnnotationOverlayView`. Detail scales down (`.full` → `.reduced` →
  `.minimal`) as a tile shrinks, keeping identification and position and
  dropping the rest rather than shrinking everything to illegibility.
- `ViewerHoverGeometry` maps a cursor point back through the viewport's fit,
  zoom, pan, rotation and flip to the underlying image pixel — separately for
  the CPU/print transform order (pan before rotation) and the GPU display
  shader's order (pan after rotation), since they only agree when a picture is
  unrotated or unpanned — so the top-left corner can show the pixel value and
  patient-space position under the cursor. A wrong readout is worse than none,
  so every step returns `nil` rather than guess when the point is off the
  picture.
- `PatientIdentificationOverlayView` is now film/print-only — the on-screen
  viewer's old single-band overlay is replaced by the corner layout above,
  since on screen the reader can move the picture out from under the text but
  paper cannot.
- New `ViewerTileTextureCache` extends the GPU display path (M5) to unfocused
  grid tiles: a texture keyed only on file + frame + window, so a synchronized
  zoom or window drag across a grid re-draws a quad per tile instead of
  re-rendering one. This is the GPU-tile work M6 explicitly deferred ("`
  ViewerTileImageCache` ... stay on the readback path") — tiles now have both a
  CPU image and, where Metal is available and the frame supports it, a GPU
  texture, falling back to the CPU image per tile (overlay planes, an
  unresolvable window, no Metal device) rather than per grid.
- Also removed the unused Inspector-panel toggle from `MainView`/`MainViewModel`
  (dead code, unrelated cleanup).

### Removed — CLI-parity test harness (2026-08-03)

Deleted the whole Tier-2 CLI-parity subsystem: the "CLI Parity" Studio screen and its
engine/comparators, the orphaned CLI Automation Testing screen, bundled synthetic
fixtures and goldens, the `cli-parity-gen`/`cli-parity-docs`/`studio-cli-introspect`
dev targets, all `CLIParity*Tests` suites plus the `StudioParityTests` target, the
"Tier-2 Output Parity Gate" CI job, and every `APP_CLI_*PARITY*`/`docs/cli-parity/`
doc — 103 files, ~14,400 lines of code, ~5,100 lines of docs, 1.1 MB of fixtures.

- Kept deliberately: `CLIToolTerminalCompare` + `CLIToolBuilder` (reachable only from
  code now that the Workshop's comparator panel is gone) and the `syn-ct.dcm` fixture
  the print tests depend on, now `Tests/DICOMStudioTests/Fixtures/syn-ct.dcm` via a
  new `StudioTestFixtures` helper.
- `APP_CLI_SHARED_API.md` updated to describe verification as it stands today: the
  oracle-based round-trip suite (`DICOMRoundTripTests`) plus, per tool, an optional
  shared `*Console` type.

### Added — shared consoles for dicom-split/merge/script (2026-08-03)

`dicom-split`, `dicom-merge` and `dicom-script` were the last three tools whose
Workshop executors shared only the engine while duplicating console text and input
parsing. Text and parsing now live once in DICOMKit — `SplitConsole`, `MergeConsole`,
`ScriptConsole` — pinned by `Tests/DICOMRoundTripTest/SharedConsoleParityTests.swift`.
Fixed real drift found in the process: the app's banners had dropped the CLI version
string, `dicom-merge` relabelled its input-count line and echoed `--format` values as
enum case names instead of the CLI's raw text, and `dicom-split`'s frame parser
silently accepted whitespace-only components the CLI rejected.

### Fixed — Print SCP honors SCU-supplied SOP Instance UIDs (2026-08-03)

A dcm4che-based Print SCU failed at N-ACTION with `0x0112` "Unknown Film Session" and
never produced a film. PS3.7 10.1.5 lets the SCU supply the Affected SOP Instance UID on
N-CREATE, and such SCUs then address every follow-up N-SET / N-ACTION by *their* UID
regardless of what the response carries — while our SCP minted and stored its own.

- `PrintSCP.assignedUID(requested:)` stores the object under the SCU's UID whenever one is
  supplied, for Film Session, Film Box, Presentation LUT and Basic Annotation Box N-CREATE;
  it falls back to the generator otherwise. A supplied UID must be non-empty after trimming
  NUL/space padding, ≤ 64 characters, and digits-and-dots only, so a malformed value can
  never become a stored key.
- Film Box N-CREATE now rejects a UID already in use with `0x0111` (Duplicate SOP
  Instance) — unreachable while the SCP minted its own.
- Image Box UIDs remain SCP-allocated; they are created implicitly with the film box.
- `PrintSCPStatusMatrixTests.testSCUSuppliedSOPInstanceUIDsAreHonored` replays the field
  sequence end to end and asserts the composed film carries the SCU's UIDs.
- `PRINT_CONFORMANCE.md` §2.1 / §4 and `DICOM_PRINT_SCP_PLAN.md` updated.

### Added — DICOM Print SCP: emulator screen and `dicom-printscp` CLI (2026-07-31)

Milestones E and F of `DICOM_PRINT_SCP_PLAN.md` — the last two rows in that plan's
matrix. The app surface came first, so the sharing ran in the direction opposite
every other print entry: settings, assembly and wording were **moved** out of
`DICOMStudio` into `DICOMPrintKit`, and both the Studio screen and the CLI now
consume rather than own them.

- **`PrintSCPSettings` / `PrintSCPService` / `PrintSCPConsole` / `PrintSCPSimulator`**
  (`DICOMPrintKit/Printing/`): every configuration knob and its
  `PrintSCPConfiguration` / `FilmComposerConfiguration` mapping, the sink stack and
  server assembly, the wording of every event/film/startup line, and a no-network
  film simulator, in one place — Studio's view model now owns only what a window
  owns (retained films, selection, button state).
- **`dicom-printscp`** (`Sources/dicom-printscp/`): `serve` (default) / `simulate`
  / `status` / `queues`. `simulate` takes DICOM files rather than a `film.json`
  descriptor as originally sketched — the composer needs real pixels, and routing
  through `PrintImagePreparer` means a simulated sheet is built by the same code a
  live SCU's job is.
- **Studio's "Printer Emulator"** (`PrintSCPView`, `PrintSCPViewModel`,
  `PrintSCPSettingsStorageService`): a persistent `Window` (not a `WindowGroup` —
  one emulator, one listener) reachable from the sidebar while a print is in
  flight from the main window.
- **Two defects a live SCU→SCP run caught, both fixed in the shared core:**
  `--max-films` counted off the screen stream (delivered the instant a sheet is
  composed) instead of `.filmPrinted`, so the listener could stop mid-N-ACTION and
  abort the SCU's association before its PNG was written; and the association log
  line rendered the port as `:0` because `AssociationInfo.remotePort` is always 0
  for this SCP and the whole endpoint is in `remoteHost` — fixed once in the
  shared console.

Plan: `DICOM_PRINT_SCP_PLAN.md` ("Milestone F as built" section has the full
shared-type table). Not in the CLI-parity harness (print tools are covered by
dedicated tests instead, per `APP_CLI_SHARED_API.md`).

### Added — DICOM Studio: overlay planes, patient identification, and print window fixes (2026-07-31)

- **Overlay plane rendering** (`DICOMKit/OverlayPlaneRenderer.swift`): PS3.3
  C.9.2 group-60xx overlay bitmaps, read and drawn both as a `CGImage` composite
  (viewer) and burned into raw samples (film). Written for Siemens' "Patient
  Protocol" Secondary Capture, whose Pixel Data is entirely zero and whose whole
  content lives in a 1-bit overlay — previously rendered as a black square, now
  shown/printed correctly. Wired into both `ImageViewerViewModel` (render path)
  and `PrintImagePreparer` (so a film matches the screen it was approved on,
  except under `--raw`).
- **Print window resolution now falls back to the file's own VOI**
  (`PrintImagePreparer.resolvedWindow`, `PrintWindowSpace`): a mark made without
  opening the file (whole-series or library print) previously auto-stretched a
  CT's full pixel range and left soft tissue in a handful of indistinguishable
  greys; it now falls back to the data set's VOI window like the viewer, export
  and tiles already do. `PrintWindowSpace` (`.outputUnits` / `.storedValues`)
  travels with an explicit window so a value taken off the viewer (stored units)
  is converted through Rescale Slope/Intercept before printing — sending it
  unconverted put the window entirely outside the pixels and printed a flat
  black cell.
- **Arrow geometry fully consolidated** (`PrintArrowGeometry.swift`): the
  fractional-of-image-height math for shaft width and head size, previously
  duplicated between `ImageAnnotationBurner` (film) and `FilmCellAnnotationLayer`
  (preview), now lives once and both call it; the preview's arrow rendering also
  switched from a shadow-based halo to a stroked-outline halo so the head no
  longer blurs into the shaft and reads as a plain line. Selection handles on a
  selected arrow shrank to a small ring with a separately-sized (2x) invisible
  grab area, so a handle no longer hides the anatomy the arrow points at.
- **Viewer patient-identification header** (`ImageViewerViewModel+PatientOverlay`):
  `patientIdentityLine` ("name, ID · CT / PT"), `modalitiesForOverlay` (every
  modality in the open study, series order, no repeats — a study is routinely
  PET/CT or a CT with an SR), and `studyDescriptionSanitizedForOverlay` (strips
  the caret/pipe/backslash separators a description arrives with, keeping only
  what reads as words).
- **Viewer toolbar reworked around click-armed tools**: windowing and zoom are
  now toggled tool buttons (highlighted while armed) rather than ⌥-drag/⌘-drag
  modifiers, freeing ⌘-drag; `resetView()` now also resets window/level and
  inversion, not just pan/zoom/rotation; the inline "Open DICOM File" button,
  file importer and ⌘O shortcut were removed from the viewer.
- **Tests**: `PrintSCPSharedCoreTests` (23), `PrintSCPScreenTests` (39),
  `PrintWindowSpaceTests` (9), `OverlayPlaneRendererTests` (17),
  `PrintMarkWindowTests` (5), `ViewerIdentificationHeaderTests` (5);
  `PrintOverlayAnnotationTests`, `PrintCellEditingTests`, `NavigationServiceTests`,
  `ViewerTileLayoutTests` and `PolishReleaseViewModelTests` updated for the
  arrow-geometry, cell-editing-window and toolbar/reset-view changes.

### Added — DICOM Studio: the film as a working surface (2026-07-30)

Plan: `DICOM_PRINT_STUDIO_PLAN.md` §10.

- **Patient identification burned into the film** (`DICOMPrintKit/ImageAnnotationBurner.swift`,
  `PatientOverlayText`, `PatientOverlayTextCache`, `PatientIdentificationOverlayView`): "name,
  ID, study date" over the study description, from one definition shared by viewer tiles and
  film cells. A DICOM printer draws identification from annotation boxes to its own layout and
  many ignore them, so the lines are burned into the prepared 8-bit frame instead — one bitmap
  pass per cell, applied last so a later crop or rotate cannot carry the caption with it, and
  skipped quietly on an unexpected pixel format rather than failing the print. The viewer draws
  it as a reserved band below the picture; the film preview overlays it, since there the cell
  *is* the film.
- **Drawn annotations on a film cell** (`PrintOverlayAnnotation`, `PrintViewModel+Annotations`,
  `FilmCellAnnotationLayer`): text and arrows, in coordinates normalized to the **image** and
  held per **mark ID** — so re-arranging the film, changing layout or printing to another sheet
  cannot move an arrow off the vessel it pointed at, and the 512-pixel preview and the
  3000-pixel frame agree. The preview uses the burner's own arrow geometry.
- **Per-cell editing in the print preview** (`PrintViewModel+CellEditing`): window/level, zoom,
  pan, text and arrow tools writing back into the mark that `PrintService.prepare` reads, so
  the preview cannot drift from the film. `FrameSourceCache` keeps decoded pixels so a
  window/level drag re-maps rather than re-decoding (tens of ms per event on a JPEG 2000 CT);
  cell renders moved 256 → 512 (at 256 half the grey levels being judged are lost to
  downscaling) and the previous rendering stands in during a gesture instead of a spinner.
- **Non-image instances open instead of failing** (`ViewerContentKind`, `ViewerNonImageContent`,
  `ViewerNonImageContentView`): SR read as a narrative, encapsulated PDF as pages, presentation
  states / KOS / raw data as named summaries. Previously a valid SR was reported as an
  "unsupported transfer syntax" — a decode failure for pixels it never claimed to have.
- **Library rows describe the study again** (`StudyModel.merging`, `StudyRowSummary`,
  `LibraryModel`, `DICOMFileService`): study fields are unioned across the files of a study
  rather than overwritten by whichever was read last; rows fall back to the series' modality
  and description, then patient ID / accession, before saying "Unknown"; series and instances
  sort by Series/Instance Number with unnumbered **last** and a total-order tiebreak (a series
  used to open on a different image on each read); empty studies are pruned; a DICOMDIR and any
  object with no SOP/Series Instance UID are refused at import instead of manufacturing an
  unopenable "Unknown Patient, 0 series, 0 images" row.
- **Reading with one hand on the keyboard**: shared `ScrollWheelHandler` (viewer pages images,
  film preview zooms cells, both live while the print sheet is over the viewer) with step
  accumulation for fine trackpad deltas; first/last jumps and opt-in wrap at series ends;
  `ViewerPrintTrayView` — the selection in film order, each row rendered with that mark's own
  window and arrangement, without opening the print sheet; ⌘/ keyboard-shortcut legend on both
  screens.
- **Tests**: `PrintOverlayAnnotationTests`, `ImageAnnotationBurnerTests`,
  `PrintCellAnnotationTests`, `PrintCellEditingTests`, `PatientOverlayTextTests`,
  `PatientIdentificationOverlaySizingTests`, `ViewerContentKindTests`,
  `ViewerProtocolLineTests`, `LibraryStudyMergeTests`, `LibraryImportEndToEndTests`,
  `StudyRowSummaryTests`, `ScrollStepAccumulatorTests`, `ViewerTileLayoutTests` —
  4,335 tests in 394 suites green.

### Added — DICOM Print SCP: printer emulator (2026-07-28/29)

DICOMKit now implements Print Management (PS3.4 Annex H) in **both** roles. Any Print SCU —
modality, workstation or third-party tool — can associate, send a film session, film boxes
and image boxes, and issue N-ACTION *print*; the film is composed and handed to an output
sink. Conformance statement: `PRINT_CONFORMANCE.md`. Plan: `DICOM_PRINT_SCP_PLAN.md`.

- **Protocol machine** (`DICOMNetwork`): `DICOMPrintServer` actor + `PrintSCP.swift`,
  `PrintSCPTypes.swift`, `PrintSCPEncoder.swift` — association accept/reject, called/calling
  AE checks, N-CREATE / N-SET / N-GET / N-ACTION / N-DELETE / N-EVENT-REPORT across Film
  Session, Film Box, Grayscale/Color Image Box, Printer, Print Job, Presentation LUT and
  Basic Annotation Box, with the PS3.4 H.4 lifecycle and cascade deletes. Configurable via
  `PrintSCPConfiguration` (film sizes, medium types, colour, max boxes per film, annotation
  boxes, idle timeout, AE lists, printer identity).
- **SCP-direction dataset parsing** (`PrintDatasetReader.swift`, `PrintSCPParser.swift`):
  a real element walk for both Explicit and Implicit VR LE, including sequences with defined
  and undefined length and image-box `PixelData`, mapped back onto the existing `FilmSession`
  / `FilmBox` / `ImageBoxContent` / `PrintImageData` model.
- **`PrintImageDisplayFormat`**: parses `STANDARD` / `ROW` / `COL` / `SLIDE` / `SUPERSLIDE` /
  `CUSTOM`, driving image-box allocation, composer cell layout and the SCU's box maths.
- **Film composition** (`DICOMPrintKit/Printing/`): `FilmGeometry` (sheet sizes at a
  configurable DPI, cell layout, fitting), `FilmComposer` (image boxes → one page bitmap:
  magnification, polarity, LUT shape, border/empty density, trim marks) and `ComposedFilm`.
  Four inversions compose correctly — MONOCHROME1, Polarity REVERSE, INVERSE / LIN OD
  Presentation LUT shape, and film emulation. `DensityMapping` is `.paperDirect` by default,
  with `.filmEmulation` opt-in rather than a silent guess.
- **Output sinks**: `PrintOutputSink` protocol with `ScreenSink` (full-resolution stream +
  bounded downsampled scrollback; never blocks the SCP on a viewer that is not draining),
  `PDFSink`, `ImageSink` (PNG/TIFF), `PaperPrinterSink` (CUPS `lp`, opt-in) and
  `CompositePrintSink`; `FilmComposingPrintHandler` wires the SCP to them.
- **Tests**: `PrintSCPTests.swift` (74 — parser round-trip in both VRs, encoder, loopback SCU
  → SCP, status matrix, robustness) and `DICOMPrintKitTests` (63 — geometry, composer, sinks,
  screen scrollback, DCMTK interop).

### Fixed — DICOM Print interoperability, verified against DCMTK 3.7.0 (2026-07-29)

Automated in `Tests/DICOMPrintKitTests/DCMTKInteropTests.swift` (skips when DCMTK is absent):
`dcmpsprt`/`dcmprscu` → our SCP, and our SCU → `dcmprscp` (IHE Full profile).

- **SCU proposes the meta *and* the individual SOP Classes** and routes each N-service to an
  accepted context (`PrintPresentationContexts`). A printer that rejects the meta class was
  previously unusable.
- **Image Display Format order was a conformance bug:** PS3.3 C.13.3 defines `STANDARD\C,R`
  as columns-first; `PrintLayout.imageDisplayFormat` emitted rows-first, so every non-square
  layout printed transposed on a conformant printer. `PrintLayout` is now the single source
  of the string.
- **Configuration Information (2010,0150) threaded end to end** — Studio and the CLI collected
  it but `PrintOptions` had no field and it was never sent; several vendors require it.
- **0x0106 reclassified as a failure** (`DIMSEStatus`) — it was treated as a warning, so a job
  sailed past a printer's rejection and failed later with a misleading code.
- **Trim (2010,0140) omitted when NO** and **Requested Decimate/Crop Behavior (2020,0040)
  omitted when DECIMATE** — printers that do not implement them reject a box for merely
  carrying them.
- **SCP idle-association timeout** (default 300 s) so a vanished peer no longer holds a slot
  forever, and **A-ASSOCIATE-RJ at capacity** instead of dropping the socket.
- **Error Comment (0000,0902) transliterated to ASCII** — `CommandSet` encodes as ASCII and
  silently dropped any value containing a non-ASCII character, discarding the only diagnostic
  an SCU developer gets.

### Added — `DICOMPrintKit`: shared print core for the CLI and Studio

- **New target/product `DICOMPrintKit`** (DICOMCore + DICOMDictionary + DICOMKit +
  DICOMNetwork), consumed by `dicom-print` and `DICOMStudio`. The shared core cannot live in
  DICOMKit — it needs both `ImagePreprocessor` and `PrintImageData` — and putting networking
  into DICOMKit would force it on all ~30 CLIs.
- `PrintJobRequest` (every job knob as one value type, plus `validate()`, `filmCount(for:)`
  and `PrintPlan`), `PrintOptionCatalog` (one table of selectable values per option, feeding
  both UI pickers and the CLI's arg enums), `PrintImagePreparer`, `PrintWorkflow` (preflight,
  retries, events, progress, job/printer status) and `PrintConsoleFormatter` (text + JSON).
- **`dicom-print` refactored** onto all of the above — arg declarations, help text and output
  unchanged; `PrintCLIEndToEndTests`, `PrintServiceTests` and `PrintSCPIntegrationTests` stay
  green.
- **Multi-film gap fixed:** `PrintResult` now carries `filmBoxUIDs` and `printJobUIDs` (the
  singular properties remain as last-element accessors), so per-film job-status polling and
  job history work for multi-film jobs.

### Added — DICOM Studio: print workflow (2026-07-28)

Library → viewer → mark images → print. Plan and full file map:
`DICOM_PRINT_STUDIO_PLAN.md`.

- **Marking in the viewer**: ordered, frame-level `PrintSelectionModel`; **M** marks the
  current image, **⌘P** opens the print sheet, a badge shows the count, a capsule shows the
  film position, and the context menu carries mark-all-frames / whole-series / clear.
- **Print settings sheet**: printer picker with Test (C-ECHO) and Status (N-GET), layout
  (auto | grid | preset), film size, orientation, copies, a live film preview showing
  spillover, a marks tray, and an Advanced disclosure covering the rest of the CLI surface.
  (Reworked 2026-07-29 — see below.)
- **Printer management**: `PrinterProfile` + `PrinterProfileStorageService`
  (`printer-profiles.json`), modelled on the existing PACS server profiles. The CLI's
  `~/.config/dicomkit/printers.json` registry stays independent by design — a sandboxed app
  cannot reach it.
- **Execution**: `PrintViewModel` + Studio `PrintService` over `DICOMPrintKit`, determinate
  per-image-box progress, live N-EVENT-REPORT console, cancel with film-session cleanup,
  per-film **Check Status**, and job history persisted to `print-job-history.json`.
- **New `Print` navigation destination** (printers + job history) and a **Print…** action on
  a study/series in the library, which adds those files to the selection without discarding
  marks already made in the viewer.

### Fixed — DICOM Studio: windowing, series order and the print sheet layout (2026-07-29)

- **Multi-valued VOI no longer discarded** (`DICOMImageExporter.determineWindowSettings`): a
  CT that carries a lung *and* a soft-tissue window in one element (`-600\50` / `1200\350`)
  fell through `windowSettings()` — which parses a single DS — and was auto-stretched over the
  full pixel range. The multi-valued form is read first and its first pair, the default
  presentation, wins.
- **One window policy everywhere**: `ImageViewerViewModel` now adopts a file's default window
  through `determineWindowSettings` (the same call the exporter, tile cache and film use), and
  `FrameRenderer`'s fallback ladder goes through it too instead of
  `renderFrameWithStoredWindow`, which hands a raw HU centre to a renderer reading *stored*
  values and washes a CT with a large Rescale Intercept out to white.
- **A window no longer follows the user across a hang**: `ViewerCellState.windowCenter/Width`
  are optional, `nil` meaning "this image's own VOI". A freshly hung tile starts at its own
  VOI, and the viewer's window is inherited only by tiles in the same series — filling a grid
  from a flat file list used to stamp one kernel's window across an MPR and every other
  reconstruction in the study.
- **Series pane in series-number order**: ascending, unnumbered series last (the library's
  ordering treated a missing number as 0, filing them ahead of series 1), ties broken by title
  then UID so the pane cannot reshuffle between two reads. Cards show the series number badge,
  and VoiceOver announces "Series 4, …".
- **Print sheet reworked**: options moved from a 320 pt left column into a band across the top
  so the film preview owns the whole centre; the sheet opens at the size of the window it was
  raised from; Advanced expands sideways under a height cap instead of pushing the film off
  the bottom; the marks tray became a "Show List…" popover, since film order now follows the
  viewer's tile order (`syncPrintOrderToViewer`) rather than the order the boxes were ticked.

### Added — DICOM Studio: the film matches the screen (2026-07-28)

- **`ViewerPresentation` + `PrintPresentationTransform`** (`DICOMPrintKit`): a mark now
  records the viewer's arrangement as *geometry over the source image* — zoom, pan, viewport,
  quarter turns, flips, invert — and the print path crops, permutes and negates the
  full-resolution frame accordingly. Nothing resamples, so a zoomed print carries the
  modality's real detail rather than an upscaled copy of what the monitor showed.
- **Film preview shows the actual frames**: `FrameRenderer` + `FrameImageStore` +
  `PrintThumbnailCache` render each marked frame as it will print. Cache keys include the
  whole arrangement, so two marks of the same frame at different zooms are two pictures.
- **`ImageInversion`**: the viewer inverts the rendered frame rather than negating the VOI
  window, which is not equivalent once Rescale Slope/Intercept or a signed representation are
  involved; the print path inverts P-values directly.

### Added — DICOM Studio: viewer tile grid and series pane (2026-07-28)

- **Tile grid 1×1 … 4×4** whose cells map to film cells in the same order. The focused tile
  *is* the live view model, so gestures, window/level and cine behave exactly as at 1×1;
  every tile keeps its own file, frame, window, zoom/pan, rotation, flips and inversion.
  Unfocused tiles are cached renders keyed on full tile state, so panning one tile does not
  re-decode the others.
- **Series pane**: every series of the open study as a card (thumbnail, description, objects
  *and* frames, current/visited state). Drag a card onto a tile, or select a tile and
  double-click, to hang a different series there. Built from indexed library metadata, with
  orientation read from one file per series afterwards and folded in.
- **Arrow-key navigation by image, not by file**: frames first, rolling onto the neighbouring
  file and stopping at the end of the series; wrapping stays cine behaviour.
- **Tests**: `ViewerPresentationTests`, `PrintPresentationTransformTests`,
  `PrintViewerPresentationEndToEndTests`, `PrintThumbnailCacheTests`,
  `PrintSelectionModelTests`, `ViewerTileLayoutTests`, `ViewerSeriesPaneTests` —
  `DICOMStudioTests` 4,185 tests green.

### Fixed — DICOMNetwork test-suite hang and unmasked failures (2026-07-27)

- **`CommitmentNotificationListener.waitForResult` hang:** the timeout race used
  a task group whose waiter child suspended in a non-cancellation-aware
  continuation, so after the timeout threw the group could never drain —
  `testCommitmentNotificationListenerWaitForResultTimeout` (and any caller
  hitting the timeout path) hung forever, stalling full `DICOMNetworkTests`
  runs after ~880 tests. The wait is now a single continuation registered
  synchronously on the actor and resumed by exactly one of: result arrival,
  timeout, or `stop()`. `stop()` also no longer waits on a listener that is
  already cancelled.
- **`ClientIdentity` keychain lookup:** `kSecClassIdentity` queries do not
  reliably filter on `kSecAttrLabel`, so a lookup for a non-existent label
  could return an arbitrary keychain identity (wrong client certificate). The
  lookup now fetches attributes for all candidates and matches the label
  explicitly, throwing `keychainIdentityNotFound` when nothing matches.
- **`StoreAndForwardQueueTests.test_queue_enqueueDrainingThrows` race:** an
  empty queue could finish draining (→ `.stopped`) before the test's enqueue
  ran; the test now holds the queue in `.draining` via
  `notifyConnectivityLost()` first.
- Full `DICOMNetworkTests` (1086 XCTest + 192 swift-testing tests) now
  completes green in ~15 s and can gate CI.

### DICOM Print — post-plan pending work (items 1–7)

- **Palette color printing:** PALETTE COLOR sources are mapped through the data
  set's Red/Green/Blue palette LUTs to RGB (or luminance grayscale); a missing
  LUT module produces a clear error instead of `notYetImplemented`.
- **Uncompressed subsampled YBR:** packed YBR_FULL_422 (full range) and
  YBR_PARTIAL_422 (BT.601 studio range) frames are chroma-upsampled and
  converted to RGB; 4:2:0/ICT/RCT remain rejected (never occur uncompressed).
- **Deep grayscale output:** `--bit-depth 8|12|16` — depths above 8 emit
  little-endian 16-bit-allocated P-Values with matching Bits Stored/High Bit.
- **Explicit VOI window:** `--window-center`/`--window-width` override the
  data set's window.
- **Full Implicit VR LE support:** print presentation contexts propose
  Explicit VR LE with Implicit VR LE fallback, and both serialization and all
  response parsers honor the negotiated syntax — implicit-only printers now
  work end-to-end (verified against the mock SCP in both syntaxes).
- **`--magnification none`** exposed (library case existed).
- **Spawn-based CLI end-to-end tests:** `PrintCLIEndToEndTests` runs the built
  `dicom-print` binary — version/validation exit codes, dry-run behavior, the
  JSON stdout contract, and a full print + failure path against the in-process
  mock Print SCP.

### DICOM Network — release-window P-DATA tolerance (print plan P2-7)

- **`Association.release()` no longer aborts on a late P-DATA PDU:** a message
  pushed by the peer between A-RELEASE-RQ and A-RELEASE-RP (e.g. a Print SCP's
  N-EVENT-REPORT) previously hit the unexpected-PDU path — abort + error on an
  otherwise successful operation. Per PS3.8 §7.2 the release requestor now
  discards P-DATA received in the release window and keeps waiting for
  A-RELEASE-RP. Integration-tested with the mock Print SCP.

### DICOM Print — Milestone D: CLI re-enabled + mock SCP integration tests

- **`dicom-print` re-enabled in `Package.swift`** (product + executable target,
  owner approved) — previously excluded under Phase-1 scope. Builds with zero
  warnings.
- **Mock Print SCP test harness:** new in-process, NWListener-based
  `MockPrintSCP` (DICOMNetworkTests) implementing A-ASSOCIATE accept/reject,
  N-GET printer status, N-CREATE film session / film box (Referenced Image Box
  Sequence sized from the requested Image Display Format), N-SET, N-ACTION,
  N-DELETE, and A-RELEASE — with scriptable failure injection (status + Error
  Comment/ID), silence-after-accept, presentation-context rejection, omitted
  job UID, and pushed N-EVENT-REPORTs.
- **10 end-to-end workflow tests** (`PrintSCPIntegrationTests`): happy path with
  exact DIMSE sequence + single-association assertion (PS3.4 H.4), multi-film on
  one association, failure injection carrying "OUT OF FILM (Error ID 42)" to the
  thrown error, defensive cleanup, silent-SCP timeout, zero-context rejection,
  interleaved event delivery + acknowledgement, omitted-job-UID handling, and
  printer-status round-trip.
- **Defensive cleanup on failure (P2-3):** when a later workflow step fails, the
  SCU now attempts a best-effort in-association Film Session N-DELETE before
  aborting (the inner guards no longer abort pre-throw, so the association is
  still alive for cleanup).
- **Machine-readable output contract (P3-2):** `send` gained `--format json`
  (result object on stdout); the stdout/stderr/exit-code contract is documented
  in the CLI README.

### DICOM Print — Milestone E hardening + CLI ergonomics (partial)

- **Scoped image-box UID parsing (P2-2, bug fix):** `parseImageBoxUIDs` scanned
  the whole response for (0008,1155) and could mis-attribute annotation-box or
  presentation-LUT references as image boxes; it is now bounded to the
  Referenced Image Box Sequence (2010,0510).
- **Empty Print Job UID no longer recorded (P2-4):** the workflow silently
  appended an empty job UID when the N-ACTION response omitted it; consistent
  with the discrete `printFilmBox`, empty UIDs are now dropped.
- **Port bounds guard (P2-5, crash fix):** `pacs://host:99999` trapped on
  `UInt16` conversion; now a clean validation error.
- **New `send` options (P3-1):** `--magnification replicate|bilinear|cubic`,
  `--film-destination magazine|processor|bin-1|bin-2`, and the full film-size
  set (`8.5x11`, `24x24cm`, `24x30cm` added).
- **Pre-flight checks:** `--check-status` (P2-1) queries printer status before
  printing — aborts on FAILURE, warns on WARNING; `--verify` (P3-3) performs a
  C-ECHO connectivity check first.

### DICOM Print — Milestone C (interoperability) from the enhancement plan

- **Image-box pixel attributes always sent (P1-1, bug fix):** the N-SET
  Preformatted Image Sequence previously omitted Rows/Columns/BitsAllocated/
  PhotometricInterpretation when no descriptor was supplied — rejected by strict
  SCPs. The print workflow now requires one `PrintImageData` per image (validated
  up front, before any network activity) and emits the attributes unconditionally;
  the discrete `setImageBox` throws a clear error without a descriptor.
- **`printWithTemplate` / `printImagesWithProgress` on a single association
  (P1-2, conformance fix):** both previously opened a separate association per
  DIMSE step (PS3.4 H.4 violation — the Film Session UID does not survive across
  associations). Both are reimplemented on the single-association workflow; the
  progress stream keeps its phase/percent updates via a new internal progress
  hook, and both gained `imageDescriptors:`/`eventHandler:` parameters.
- **Transfer syntax (P1-3, documented decision):** print presentation contexts
  now propose **Explicit VR LE only**. Previously Implicit VR LE was also
  proposed but data was always serialized Explicit — an implicit-only SCP would
  accept a syntax we then mis-encoded. Now such an SCP cleanly rejects
  negotiation; full Implicit-VR support remains future work if a real printer
  needs it.
- **DIMSE-response timeout (P1-4, bug fix):** an SCP that accepted the
  association and then went silent hung the tool forever. All print DIMSE
  response reads now race against `PrintConfiguration.timeout`; on expiry the
  association is aborted and `operationTimeout` is thrown.

### DICOM Print — Milestone B (image fidelity) from the enhancement plan

- **Preprocessing pipeline wired into printing (P0-1, bug fix):** `dicom-print send`
  now runs every frame through `ImagePreprocessor` by default — Rescale
  Slope/Intercept → VOI window (from the data set or auto-calculated) →
  MONOCHROME1 inversion → 8-bit MONOCHROME2 output (8-bit RGB for color mode).
  Previously raw *stored* pixel values were sent, so windowed CT/MR and
  MONOCHROME1 images printed with clinically incorrect grayscale/polarity.
  A `--raw` flag bypasses the pipeline. The two `XCTSkip`-quarantined MONOCHROME1
  preprocessor tests were rewritten to the decided behavior and re-enabled.
- **Encapsulated pixel data decoded before N-SET (P0-2, bug fix):** compressed
  sources (JPEG, JPEG 2000, JPEG-LS, RLE) were shipped as raw encapsulated
  fragments — malformed image boxes. `send` now decodes to native frames via
  `DICOMFile.tryPixelData()`, which also applies the JPEG-Baseline YBR→RGB
  descriptor correction.
- **Multi-frame handling (P0-6, bug fix):** previously the entire multi-frame
  Pixel Data value was sent as one image. New `--frame N` (1-based, default 1)
  and `--all-frames` (one image box per frame) options with bounds validation.
- **YBR color conversion (P1-5):** uncompressed YBR_FULL sources are converted
  to RGB for color printing (PS3.3 C.7.6.3.1.2); RGB→grayscale conversion is
  applied for grayscale mode. Uncompressed *subsampled* YBR (YBR_FULL_422 etc.)
  is explicitly rejected with a clear error rather than mis-converted (packed
  4:2:2 layouts need `bytesPerFrame` modeling in DICOMCore first).
- **Signed pixel safety (P2-6):** with preprocessing on by default, Pixel
  Representation = 1 sources are sign-extended and emitted as unsigned 8-bit
  P-Values — signed values are no longer sent to unsigned Image Boxes.
- New `ImagePreprocessor.prepareForPrint(pixelData:dataSet:frameIndex:colorMode:)`
  API prepares a single frame of already-decoded pixel data (the existing
  data-set variant now delegates to it).

### DICOM Print — Milestone A (safety) from the enhancement plan

- **Real printer-status parsing (P0-3, bug fix):** `parsePrinterStatus` was a stub
  that always returned NORMAL regardless of the N-GET response, so
  `PrinterStatus.isNormal` was always true. It now decodes Printer Status
  (2110,0010), Printer Status Info (2110,0020), Printer Name (2110,0030), and —
  when returned — Manufacturer (0008,0070) / Manufacturer Model Name (0008,1090).
  A response without a status attribute now reports "UNKNOWN" instead of a false
  NORMAL. `dicom-print status` surfaces the new fields in text and JSON output.
- **Non-zero exit code on print failure (P0-4, bug fix):** `dicom-print send` now
  exits with a failure code when the print result is unsuccessful; previously it
  printed "✗ Print failed" but exited 0, so automation could not detect failures.
- **DIMSE error detail surfaced (P0-5):** `CommandSet` gained `errorComment`
  (0000,0902), `errorID` (0000,0903), and `offendingElements` (0000,0901)
  accessors. `DICOMNetworkError.printOperationFailed` now carries an optional
  `detail` string populated from the SCP's Error Comment / Error ID on every
  print failure path, so users see e.g. "OUT OF FILM" instead of only a numeric
  status. A one-argument `printOperationFailed(_:)` factory preserves source
  compatibility.

### DICOM Print tool (`dicom-print`) — features + fixes

- **`--layout` now honored (bug fix):** the flag was parsed and echoed but never
  applied — `send` always used the automatic layout. `printImages` gained an
  optional explicit `layout:` override (nil = existing auto-layout) and the CLI
  now threads `--layout` through. A single image with an explicit `--layout` is
  routed accordingly.
- **`--color` added (gap fix):** the CLI always printed grayscale because
  `PrintConfiguration.colorMode` was never set. Added `--color grayscale|color`
  on `send`, which negotiates the Color Print Management Meta SOP Class and sends
  color image boxes.
- **Conformant image descriptors:** `send` now extracts per-image attributes
  (rows, columns, bits allocated/stored, high bit, samples per pixel, pixel
  representation, photometric interpretation) from each dataset and sends them in
  the N-SET Preformatted Image Sequence (PS3.3 C.13.5.1). Previously required
  image attributes were omitted.
- **N-EVENT-REPORT reception:** the Print SCU now receives, decodes, and
  acknowledges asynchronous printer/print-job notifications pushed by the SCP
  (Printer SOP Class status; Print Job SOP Class progress). New `PrintEvent`,
  `PrinterEventType`, `PrintJobEventType`, and a `PrintEventHandler` callback
  wired through `printImage`/`printImages`. `dicom-print send` prints faults
  always and routine progress in `--verbose`. This also fixes a latent
  correctness bug where an interleaved event could be mis-parsed as the awaited
  DIMSE response.
- **Build:** the `dicom-print` target was excluded from `Package.swift` and had
  drifted out of compilability (`DICOMParser`/`data(for:)` no longer existed,
  `@Sendable` capture errors). Repaired to use `DICOMFile.read(from:force:)`.
- **Layout presets + retry:** `dicom-print send` gained `--template`
  (single/comparison/grid/multi-phase — sets layout + film size + orientation,
  routed through the conformant single-association path) and `--retries N`
  (retry on connection/setup failure with exponential backoff; a submitted job
  is never retried, so no duplicate prints).
- **Presentation LUT:** added `PresentationLUTShape` and a `presentationLUTShape`
  print option. When set, the workflow N-CREATEs a Presentation LUT SOP Instance
  (part of the Grayscale/Color Print Management Meta, so no extra presentation
  context) and references it from each film box (Referenced Presentation LUT
  Sequence, 2050,0500). CLI: `--presentation-lut identity|inverse|lin-od`.
- **Annotation boxes:** added `PrintAnnotation` and `annotations` /
  `annotationDisplayFormatID` print options. The workflow sets Annotation Display
  Format ID on the film box and N-SETs each Basic Annotation Box (position + text)
  using a new sequence-scoped UID parser so annotation-box UIDs are not confused
  with image-box UIDs. CLI: repeatable `--annotate <text>` + `--annotation-format
  <id>`. Note: the Annotation Display Format ID is printer-specific.
- **Overlay box scaffolding:** added the Basic Print Image Overlay Box SOP Class
  UID and Referenced Image Overlay Box Sequence tag; full overlay-plane extraction
  remains a follow-up.

### Tests

- **Re-enabled the `DICOMNetworkTests` target** (was excluded from `Package.swift`),
  so print logic — including the new Presentation LUT / annotation / N-EVENT-REPORT
  code — is covered again (177 tests). The rotted, live-PACS `PACSIntegrationTests`
  is quarantined via `exclude:` until ported to the current API; two outdated
  MONOCHROME1 `ImagePreprocessor` expectations are `XCTSkip`-quarantined pending a
  product decision on 8-bit vs 16-bit print output.

### Fixed — Bug review pass (library crashes/correctness + CLI hardening)

- **STOW-RS server (critical):** the multipart parser decoded the entire body as UTF-8
  before splitting, so binary `application/dicom` uploads (almost never valid UTF-8)
  parsed to zero parts and were silently dropped while the server still reported
  success; rare bodies that did decode were corrupted by whitespace-trimming raw bytes.
  Now uses the same byte-scanning `MultipartMIME` parser as the client. See `BUG_REVIEW.md` (C1).
- **SIMD window/level:** `applyWindowLevel` passed a positive offset instead of
  `-minValue` into the vDSP scalar-add, blowing out every image rendered through the
  fast path. `PerformanceTests/SIMDImageProcessorTests.swift` had also silently dropped
  out of the build (excluded in `Package.swift`), so the regression test for this never
  ran; both are now fixed and back in the build. See `BUG_REVIEW.md` (H1).
- **Crash hardening:** bounds-check encapsulated pixel-data fragment lengths before
  slicing (`TransferSyntaxConverter`), handle empty/dot-only `TM` values (`DICOMTime`),
  tolerate duplicate tags inside a sequence item (`SequenceItem`), and guard a
  double-`resume()` race in the Storage SCP association handshake (`StorageSCP`). See
  `BUG_REVIEW.md` (H2, H3, M3, H4).
- **Correctness:** `allowMissingVR` in the DICOM JSON decoder had its condition
  inverted and never inferred a VR from the dictionary; `AT`-valued elements were
  byte-swapped as a single 32-bit word instead of two ordered 16-bit words on
  cross-endian transcode (also added missing `OD`/`OL`/`SV`/`UV` to the numeric-VR
  swap set); the data element dictionary loader dropped rows with an empty `Name`
  field (`(0018,0061)`, `(0400,0315)`, `(300A,0782)`). See `BUG_REVIEW.md` (M1, M2, M4).
- **Hardening:** segmentation palette index underflow on `segmentNumber == 0`,
  slice-unsafe absolute-index reads in `ByteOrder`/`PaletteColorLUT` (now relative to
  `startIndex`), non-ASCII digits accepted in UID validation, and a 3-byte G1 escape
  sequence unrecognized at end-of-buffer. See `BUG_REVIEW.md` (L1-L4, M5).
- **CLI / DICOMStudio Workshop parity:** rejected negative `--frame`/`--retry`/
  `--parallel`/`--batch` values that previously reached a trapping range or stride
  instead of erroring cleanly; `dicom-anon` and its app equivalent now require
  `--output` (or `--dry-run`) instead of silently doing nothing; directory converts in
  `dicom-convert` now retag non-DICOM output files with the correct extension per file
  (previously only the single-file path did); reversed `--select` ranges in `dicom-qr`
  no longer trap; study-level C-GET with `--hierarchical` now recovers the series UID
  from the received dataset instead of collapsing to a flat layout; `dicom-split` now
  reports real per-file failure counts and exits non-zero when any file failed. See
  `BUG_REVIEW.md` ("CLI / DICOMStudio Workshop hardening").

## [2.2.10] - 2026-07-15

### Added — J2K GPU/CPU Encode Route Planner

- Introduced `J2KRoutePlanner`, which resolves the three previously conflated encode
  choices — backend (`CPU`/`GPU`/`auto`), intent (`lossy`/`lossless`/`lossless-only`),
  and compression type (JPEG 2000 Part-1/Part-2/HTJ2K) — into a single deterministic
  J2KSwift API call instead of reverse-engineering them from the transfer-syntax UID.
  `auto` now genuinely selects the Metal GPU backend for lossy JPEG 2000/HTJ2K encodes
  where previously it never did. See `J2K_ROUTING_ARCHITECTURE.md`.
- JPEG 2000 Part-2 (`.92`/`.93`) *encoding* is explicitly rejected with a clear error —
  the pinned J2KSwift v11.0.2 cannot decode the Part-2 codestreams it encodes — while
  *decoding* existing Part-2 files remains fully supported; the real-Part-2 encode path
  is gated behind a flag for when the library gains decode support.
- Updated `CodecBackend`/`CompressionManager`/`CompressionConsole` wiring and added
  `J2KRoutePlannerTests` and `J2KGPUEncodeRoundTripTests` covering the new routing
  decisions and GPU round-trip correctness.

### Added — CharLS (dcmdjpls) JPEG-LS Bench Peer, `repro12bit` Repro Tool

- Added `CharLSCLICodec` (macOS-only), a decode-only DICOMStudio bench peer that wraps DCMTK's
  `dcmdjpls` to cross-validate JLSwift-produced JPEG-LS codestreams against a CharLS-backed
  reference decoder, matching the existing `binaryPath`/`version`/`decodeFrame` surface used by
  the other CLI peers (djpeg/djxl/Kakadu/Grok).
- `J2KTestBenchModels`/`J2KTestBenchService`/`J2KTestBenchViewModel`/`J2KTestBenchView`: wired
  `.charls` through the JPEG-LS bench family (`includeCharLS`), and `J2KBenchSyntax.all` is now
  derived entirely from `TransferSyntax.selectableEncodings` for every format (previously only
  JPEG 2000/HTJ2K rows were catalog-driven), excluding JPEG XL JPEG Recompression (`.111`) since
  the bench encodes raw frames rather than repacking an existing JPEG.
- Added `repro12bit`, a standalone executable target for reproducing/isolating 12-bit codec
  issues against J2KSwift, alongside `JLISWIFT_GAP_ANALYSIS.md` documenting a verified bit-depth,
  color/sampling, and gap audit of the JLISwift dependency (no critical/high findings).
- `CompressionQuality.expectedMinPSNRDb` gives each encode preset (`.low`/`.medium`/`.high`/
  `.maximum`, and `.custom` via interpolation) a conservative minimum-PSNR pass bar for lossy
  round-trip tests, so the bench's `lossyPSNRThresholdDb` default now tracks
  `J2KTestBenchService.lossyEncodeQuality` instead of a fixed 40 dB value a lower-quality preset
  could never clear.
- `ModalityMapping.StandardModality`/`allCodes` centralizes the canonical DICOM modality list;
  the CLI Workshop's modality pickers (C-FIND/C-MOVE/MWL/etc.) now draw their `allowedValues`
  from it instead of hand-maintained arrays, so new modalities need updating in one place.

### Fixed — Same-syntax lossy recompression silently dropped `--quality`

- `CompressionManager.isRecompression`/`compressData`/`compressDataWithMetrics` now treat a
  same-UID lossy target with an explicit `quality` as a genuine recompression (decode-to-native
  + re-encode) rather than a byte passthrough. Previously, re-compressing an already-JPEG-2000
  (or other lossy-encapsulated) file into the *same* transfer syntax UID with a new `--quality`
  silently copied the existing codestream through unchanged (input size == output size, ~0 ms),
  discarding the requested quality. Lossless / no-quality same-syntax targets keep the
  passthrough. `dicom-compress` and the DICOMStudio Workshop both pass `quality` through to
  `isRecompression` so their two-phase-recompression UI note stays accurate.

### Fixed — Standalone macOS packaging

- Removed the DICOMStudio-only OpenJPEG comparison wrapper from `DICOMCore`'s
  default dependency graph. Standalone macOS consumers no longer require a
  Homebrew installation or the absolute `/opt/homebrew/lib/libopenjp2.a` path.
- Removed the corresponding DICOMStudio static-link and arm64-only Xcode settings;
  production JPEG 2000 support continues to use J2KSwift.
- Optional real-image codec and benchmark tests now report as skipped when the
  gitignored `LocalDatasets` or `SampleStudies` corpora are unavailable in CI.

### Changed — J2KSwift v11.0.2

- Updated the JPEG 2000 / HTJ2K / JP3D dependency floor to J2KSwift v11.0.2.
- The decoder-only update stops truncated quality-layer decoding at the exact
  coding-pass boundary and bounds scratch clearing to the active code-block region,
  without changing the DICOMKit public API or codestream format.

### Added — JPEG Baseline Encoder Choice (DICOMStudio-only)

- Added `JPEGCodecEngine` (DICOMCore: `.jli` / `.native`) and
  `CodecRegistry.encoder(for:engine:)`, which honours the engine selection **only** for
  JPEG Baseline (1.2.840.10008.1.2.4.50) — the one transfer syntax this library can encode
  two ways: the pure-Swift `JLICodec` (the registry default for all four JPEG syntaxes) or
  Apple's `NativeJPEGCodec` (ImageIO). JPEG Extended/Lossless/Lossless SV1 have no second
  encoder, so `engine` is a no-op for them.
- Threaded `jpegEngine` through `CompressionManager.compressData` /
  `compressDataWithMetrics`, defaulting to `.jli` so `dicom-compress` output is unchanged.
- Added an internal "JPEG Engine" picker to the DICOMStudio CLI Workshop's `dicom-compress`
  form, visible only for `operation == compress && codec == jpeg` — a benchmarking aid with
  no `dicom-compress` CLI counterpart, so it never appears in the copy-pasteable command
  preview. Required a new `CLIParameterDefinition.visibleWhenAll` ([`[CLIParameterVisibilityCondition]`],
  ANDed with the existing single-condition `visibleWhen`) since `codec` persists across
  operations and a single condition couldn't pin the picker to compress-only.
  `CommandBuilderHelpers.isVisible(...)` is now the one predicate shared by command-preview
  generation, required-field validation, and the ViewModel's form rendering.

### Fixed — `dicom-convert` to DEFLATE dropped pixel data from encapsulated sources

- An encapsulated source (JPEG/JPEG 2000/RLE/…) converted to Deflated Explicit VR Little
  Endian is now decoded to native pixels first. DEFLATE (PS3.5 A.5) is a data-set-level
  codec over a *native* stream — it has no encapsulated form — but `DICOMConverter` used to
  serialize the encapsulated (7FE0,0010) straight into the deflate stream: the codestream
  survived, but the output was labelled 1.2.840.10008.1.2.1.99 while still carrying an
  undefined-length, Item-fragmented pixel element, so no conformant reader (including
  DICOMKit's own) could decode pixel data from it — and the tool reported success.

### Fixed — `dicom-compress`/`dicom-convert` `--output` naming a directory failed with "Is a directory"

- Both CLIs now resolve `--output` through the existing `OutputPathResolver` (already used
  elsewhere) before writing, so passing a directory (e.g. `~/Desktop/DICOM_Output/`, or
  whatever the DICOMStudio Workshop's Browse button hands back) writes the input's filename
  into that directory instead of failing. An explicit file path is still used verbatim.

### Fixed — DICOMStudio CLI Workshop could build/compare against a different checkout's DICOMKit

- `CLIToolBuilder.repoRoot()` and `CLIToolTerminalCompare.locateBinary()` no longer fall back
  to a hard-coded absolute path or the process's working directory (which is `/` for a GUI
  app). They now resolve the SwiftPM package root by walking up from `#filePath` — the
  checkout the running app was actually compiled from — so `swift build`/binary lookup can
  no longer silently target a sibling repo whose DICOMKit accepts different tokens, which
  previously made "Compare CLI" report diffs that didn't exist in the current repo.

### Added — Transfer-Syntax Lossy/Lossless Split and Encode-Intent Threading

- Introduced `LosslessCapability` (`losslessOnly`/`lossyOnly`/`both`), `EncodingIntent`, and
  `SelectableEncoding` on `TransferSyntax` to correctly model the JPEG 2000/HTJ2K/JPEG XL
  "general" UIDs (`.91`/`.93`/`.203`/`.112`), which per PS3.5 may carry either a lossy or
  lossless codestream. `TransferSyntax.parse()` itself remains conservative (bare
  `…-lossless` still maps to the old reversible-only UID, to avoid changing association
  negotiation behavior in dicom-send/retrieve/qr) — the lossy/lossless split is exposed only
  through the new `parseEncoding()` API.
  See `J2K_HTJ2K_TRANSFER_SYNTAX_SPLIT_PLAN.md`.
- Added missing `UIDDictionary` entries and corrected display names for `.92`/`.93`/`.201`/
  `.202`/`.203` (e.g. "JPEG 2000 Lossless Only", "HTJ2K Lossless Only (RPCL)").
- Threaded `EncodingIntent` from CLI/app codec-name resolution through to `JXLCodec` and
  `DICOMConverter`, so `…-lossless` codec names now genuinely encode reversibly into the
  general UID (previously not possible) and `…-lossy` produces true irreversible compression.
  See `J2K_HTJ2K_JXL_ENCODE_INTENT_AND_LOSSY_ATTRS_PLAN.md`.
- Added `CompressionManager.applyLossyImageCompressionAttributes`, shared by `dicom-compress`
  and `dicom-convert`, which stamps Lossy Image Compression (0028,2110), Method (0028,2114),
  and Ratio (0028,2112) plus Image Type → DERIVED per PS3.3 C.7.6.1.1.5, with
  append/once-lossy-always-lossy semantics.
- `JXLCodec`: added signed 16-bit support (JXLSwift `int16` level-shift) and genuine lossy
  VarDCT grayscale encoding (JXLSwift 1.4.0) instead of silently falling back to lossless.

## [2.2.9] - 2026-07-15

### Fixed — SwiftPM consumer build hygiene

- Declared the `dicom-3d` and `dicom-j2k` target README files as excluded package
  inputs, removing the two unhandled-file warnings emitted during consumer builds.
- Declared the intentionally inactive complements of the explicitly sourced
  `DICOMKitTests` and `DICOMViewerTests` targets as excluded inputs, removing two
  package-planning warnings covering 102 test files without changing test membership.
- Applied the existing optional-fixture contract to two HTJ2K benchmark tests so
  clean CI checkouts skip them when the gitignored MR corpus is unavailable.
- Hardened release validation to reject production compiler warnings and test
  package-planning warnings, synchronized the release artifact matrix with all
  36 enabled CLI products, pinned manual release jobs to the requested tag, and
  staged release creation as a draft before publication for immutable releases.
- No decoder, runtime, product API, ABI, or command behavior changed.

## [2.2.6] - 2026-07-09

Patch release: shared transfer-syntax negotiation token list for `dicom-retrieve`/`dicom-qr`,
plus two reporting-accuracy fixes (`--backend`, `dicom-compress info` lossless state). No
association-negotiation or encode-behavior changes — this release only corrects what tools
report and what token lists they offer.

### Added — Shared transfer-syntax negotiation token list

- Added `TransferSyntax.negotiableImageSyntaxTokens` / `negotiableImageTokens` (DICOMCore) as
  the single source of truth for the transfer-syntax lists offered by the UID-only negotiation
  tools (`dicom-retrieve`, `dicom-qr`) — the negotiation analogue of
  `CompressionManager.supportedCodecs()` (dicom-compress) and `DICOMConverter.cliTokens`
  (dicom-convert). Every token round-trips through `TransferSyntax.parse()` (enforced by tests).
- Wired the DICOMStudio CLI Workshop `dicom-retrieve` / `dicom-qr` transfer-syntax pickers and
  the `dicom-retrieve` / `dicom-qr` CLI `--transfer-syntax` help onto that shared list, so both
  surfaces stay in lockstep. This adds the previously-missing JPEG-LS, JPEG XL, and JPEG 2000
  Part 2 (plus `explicit-vr-be`, `deflate`, `jpeg-extended`, `jpeg-lossless-sv1`) syntaxes that
  the old hand-maintained lists stopped short of; regenerated the `CLIContracts.json` parity
  golden to match.
- CLI Workshop: the `dicom-convert` transfer-syntax dropdown now shows the short kebab aliases
  (`DICOMConverter.aliasTokens`, e.g. `jpeg2000-lossless`, `htj2k-lossy`) instead of the CamelCase
  `cliTokens`, so it reads the same as the `dicom-compress` / `dicom-retrieve` / `dicom-qr`
  dropdowns. The `dicom-convert` CLI resolves the kebab alias identically, so the generated
  command and in-process execution are unchanged.

### Fixed — `dicom-compress info` reports the true lossless state for general J2K/HTJ2K/JXL UIDs

- `CompressionManager.getCompressionInfo` now derives `isLossless` (and the transfer-syntax
  display name) from Lossy Image Compression (0028,2110) for the `both`-capable general UIDs
  (`.91`/`.93`/`.203`/`.112`), instead of the UID-level flag which always reported "Lossy".
  A file reversibly encoded into a general UID (e.g. `--codec jpeg2000-lossless` → `.91`) now
  reports `Transfer Syntax: JPEG 2000 Lossless` / `Lossless: Yes` on both `dicom-compress info`
  surfaces (text + `--json`) and in the CLI Workshop, so the name and the Lossless line no
  longer contradict each other. Single-capability UIDs (e.g. `.90`, `.50`) are unchanged —
  their UID is authoritative. Reference: PS3.3 C.7.6.1.1.5.

### Fixed — `--backend` reporting reflected the hardware probe, not the actual encode path

- Added `CodecBackendPreference.effectiveEncodeBackend(isLossless:isJPEG2000Family:)` (DICOMCore)
  and `CompressionConsole.compressBackend(codec:preference:)` (DICOMKit), which report the backend
  the encoder will **actually** dispatch to rather than the best available hardware.
  `J2KSwiftCodec` only takes the Metal GPU path for a genuinely lossy JPEG 2000/HTJ2K encode — the
  lossless GPU path isn't bit-exact on 12/16-bit medical data — so `auto`/`--backend metal` on a
  lossless or non-J2K encode previously reported "Metal (GPU)" in `dicom-compress`/CLI Workshop
  verbose output even though the encode ran on the CPU. An explicit `--backend metal` request that
  can't use the GPU is now downgraded to the CPU backend with an explanatory note instead of
  silently misreporting.
- `CodecBackend.accelerate.displayName` now reports "Accelerate (CPU)" instead of the stale
  "Accelerate (not available)" on platforms where Apple's `Accelerate` framework is present but the
  old J2KAccelerate SIMD-family probe (removed in J2KSwift v11.0.0) no longer exists.

## [2.2.1] - 2026-07-06

Patch release: strict-concurrency bridge fix plus package-wide warning cleanup.
Both `swift build` and `swift build -Xswiftc -warnings-as-errors` pass cleanly;
no runtime behavior changes.

### Fixed — Swift 6 Strict-Concurrency Task Bridge in CLI Targets

- Fixed the `DispatchSemaphore` + `Task {}` async-to-sync bridge pattern used by CLI entry points so Swift 6 strict-concurrency no longer flags data-race sendability risks for `waitForTask`/`runAsync` helpers. The bridge now uses `Task.result` and an explicitly documented manually-synchronized capture (`nonisolated(unsafe)`), preserving runtime behavior while satisfying the compiler's model.
- Updated affected targets:
  - `Sources/dicom-jpip/main.swift`
  - `Sources/dicom-3d/main.swift`
  - `Sources/dicom-j2k/main.swift`
  - `Sources/dicom-viewer/main.swift`
- Also cleaned up adjacent strict/warnings-as-errors diagnostics surfaced during validation in shared runtime files (`ScriptEngine`, `DICOMDIRReader`/`DICOMDIRWriter`, `ImagePreprocessor`, `ImageResizer`, `JP3DVolumeBridge`, `JP3DVolumeDocument`, `StudyManager`, gateway mapping/converter helpers, and compression manager) without changing intended behavior.

### Fixed — Remaining `-warnings-as-errors` Diagnostics Across the Package

- `dicom-3d`: never-mutated `var` locals converted to `let` (`VolumeExport`, `MPRGenerator`); redundant `try`/`try?` removed from non-throwing `DataSet` accessor calls (`VolumeData`).
- `DICOMWeb`: redundant `await` removed from synchronous same-isolation calls (`ConformanceStatementGenerator`, `HTTPConnectionPool`, `HTTPRequestPipeline`); unused `guard let url` binding replaced with a `URL(string:) != nil` existence test (`DICOMJSONDecoder`); unused locals dropped (`CompressionMiddleware`, `HTTPRequestPipeline`).
- `DICOMStudio`: pure static J2K test helpers marked `nonisolated` — they already executed off the main actor at runtime (`J2KTestingViewModel`); pipe-drain captures in `CLIToolTerminalCompare` use the same documented `nonisolated(unsafe)` + happens-before pattern as the CLI bridge; cine timer callback wrapped in `MainActor.assumeIsolated` (timer is scheduled on the main run loop); slider `Binding` setters pass closures instead of non-`@Sendable` function values (`DICOMVolumeViewerView`, `JP3DComparisonView`, `JP3DVolumeComparisonView`); unused locals removed (`CLIWorkshopViewModel`, `JP3DMPRView`).

## [2.2.0] - 2026-07-04

CLI parity harness, JPEG XL lossy/recompression, and round-trip regression suite.

### Changed — P2/P3 Console-Builder and Dir-Walk Dedup (2026-07-04)

Follow-up to the remediation batch: every remaining hand-duplicated console block and directory
walk now lives in one shared builder/gatherer that both the CLI and the Workshop call, so the two
surfaces can no longer drift (`CLI_TOOLS_SHARED_CORE_VERIFICATION.md` → *P — duplication*).

- **New shared console builders (CLI text canonical):** `AnonConsole` (+ shared
  `Anonymizer.parseFlexibleTag`), `PixelEditConsole`, `ImageConsole`, `ExportConsole`,
  `UIDConsole`, `CompressionConsole.infoText/infoJSON/backendsText/backendsJSON`,
  `NetworkConsole` qr-line additions, `UPSConsole` (DICOMWeb), and
  `NetworkConsole.mwlCreateDetailBlock` (dedups the app's HL7/REST MWL-create branches).
- **New shared gatherers:** `FileGatherer.regularFiles(under:recursive:)` (sorted,
  content-agnostic walk — anon/validate/convert/pdf/export/image on both surfaces) and
  `FrameMerger.gatherInputFiles(from:recursive:)` + `FrameMerger.isDICOMFile` (dicom-merge).
- **Real drift found and fixed while hoisting** (all previously hiding in un-goldened paths):
  the app's pixedit executor double-printed the Image line, added an "Edited pixel data:" line
  and a byte-size suffix the CLI never prints; anon's per-file verbose text and single-file
  failure behavior differed from the CLI; UPS create-workitem/change-state used app-invented
  wording instead of the CLI's response text; dicom-merge sorted its inputs in-app but not in
  the CLI, so merged instance order could differ between surfaces (both now sort).
- **Deterministic batch order:** all shared walks sort by path, so directory-mode output order
  is stable run-to-run on both surfaces (previously filesystem enumeration order).
- App-only additions that have no CLI counterpart (sandbox redirect notes, UPS pre-flight
  guidance and error hints, MWL create banners) are unchanged.

### Changed — Three-Axis Shared-Core Remediation Batch (2026-07-04)

Follow-up to the three-axis verification of all 40 tools (`CLI_TOOLS_SHARED_CORE_VERIFICATION.md`,
full per-claim outcomes in its *Remediation outcomes* section). Eleven tools were held by user
triage (measure, viewer, 3d, ai, report, gateway, cloud, server, j2k, jpip, print) and the network
port/hostname workflow was left untouched as planned. Highlights:

- **New shared surfaces (CLI + Workshop call one implementation):**
  - `DataExchangeWorkflow` (DICOMWeb) — the entire dicom-json/dicom-xml pipeline (default output
    path, always-write-file behavior, tag filtering, metadata-only, verbose lines). Fixes the app's
    divergent print-to-console/refuse-reverse behavior.
  - `ConvertConsole` (DICOMKit) — dicom-convert's terse console (transcode line, batch ✓/✗ +
    `Conversion complete:` summary); the app's extra Read/Wrote/Transfer-Syntax chrome removed.
  - `TagEditConsole` (DICOMKit) — dicom-tags change block + `Output written to:` completion line
    (the app previously printed an unconditional count and `Saved:`).
  - `QRSessionState` (DICOMNetwork) — dicom-qr's save-state model hoisted from the executable;
    `--save-state` now also works in the Workshop and app-saved states resume via `dicom-qr resume`.
  - App validate now renders via the shared `ValidationReport` (the drifted app copy with its
    `Exit code:` annotation block was deleted); app compress batch uses the shared
    `findDICOMFiles`; app uid/pixedit call the shared `validateFileUIDs`/`parseRegion`.
- **Formerly-inert flags implemented:** `dicom-merge --format enhanced-ct/mr/xa` (Enhanced SOP
  Class + Shared/Per-frame Functional Groups), `dicom-script run --parallel` (concurrent pipeline
  commands with source-order output replay), `dicom-compress --backend`
  (`CompressionConfiguration.forcedBackend` → J2K/HTJ2K Metal GPU encode; other codecs unaffected),
  `dicom-image --use-exif` under `--split-pages` (per-page EXIF), `dicom-dcmdir update`
  (real implementation via `DICOMDIRWorkflow.updateDirectory`), `dicom-query
  --referring-physician` (now a study-level C-FIND matching key on both surfaces).
- **Removed (declared no-ops):** `dicom-json --format standard|dicomweb` and `--stream` (goldens
  proved byte-identical output for every value; the encoder always emits the DICOMweb PS3.18 JSON
  model); the app-only qido timeout field.
- **Wire/exit-code correctness:** app mpps update no longer sends a `studyInstanceUID` the CLI
  never sets; anon in-app exit code is now structured (any failed file → 1) instead of sniffed
  from output text; dump's No-Color toggle is honored (defaults ON in-app with a truthful
  `--no-color` preview).
- **Surface adds:** uid regenerate accepts multiple inputs in-app (cross-file UID mapping like the
  CLI); ups gains the CLI's `--create <json-file>` form; qido gains `--verbose`.
- **New round-trip oracles:** merge enhanced-format (SOP class + functional groups + standard
  unchanged), script parallel-pipeline (rendezvous concurrency + source-order replay + failure
  propagation), dcmdir update (add + prune-missing).

### Added — JPEG XL Lossy Encode (Transfer Syntax …4.112) in dicom-compress

- **`dicom-compress compress --codec jpeg-xl`** now produces **lossy** JPEG XL (`1.2.840.10008.1.2.4.112`, general JPEG XL) via JXLSwift's VarDCT encoder, alongside the existing lossless JPEG XL (`…4.110`). Both the `dicom-compress` CLI and the DICOMStudio CLI Workshop drive the identical shared `CompressionManager` / `CodecRegistry` path, so the two surfaces cannot drift. `--quality maximum|high|medium|low|0.0–1.0` maps to the JPEG XL quality/distance curve (mirroring the `--quality` mapping already used by the JPEG and JPEG-LS lossy codecs).
  - **Codec naming** aligns with the rest of the family (`jpeg2000`/`htj2k`): the bare `jpeg-xl`/`jxl` names now resolve to the **lossy** syntax (`…4.112`); the explicit `jpeg-xl-lossless`/`jxl-lossless` names select the lossless syntax (`…4.110`). `jpeg-xl-lossy`/`jxl-lossy` are accepted aliases for the lossy target. (Behaviour change: `jpeg-xl`/`jxl` previously encoded lossless.)
  - **`JXLCodec`** (`Sources/DICOMCore/JXLCodec.swift`): added `…4.112` to `supportedEncodingTransferSyntaxes`, a per-instance `encodingTransferSyntaxUID` that selects the encode mode (…4.110 → lossless Modular, distance 0; …4.112 → lossy VarDCT at a quality-derived distance), and a `jxlQuality(from:)` mapping. JXLSwift's VarDCT lossy encoder covers 8-/16-bit RGB/RGBA within its size limits; for inputs it can't take (grayscale, oversized) it transparently falls back to the lossless Modular path, so a `…4.112` encode always yields a valid — and conformant, since the general syntax permits both — JPEG XL codestream.
  - **`CodecRegistry`** (`Sources/DICOMCore/ImageCodec.swift`): the JPEG XL encoder is now wired per-UID (`JXLCodec(encodingTransferSyntaxUID: uid)` for `…4.110` and `…4.112`), mirroring the per-syntax encoder wiring already used for JLISwift / J2KSwift.
  - **`CompressionManager`** (`Sources/DICOMKit/Compression/CompressionManager.swift`): codec-name map splits JPEG XL into a lossless entry (`jpeg-xl-lossless`/`jxl-lossless` → `…4.110`) and a lossy entry (`jpeg-xl`/`jxl`/`jpeg-xl-lossy`/`jxl-lossy` → `…4.112`). Flows automatically to the CLI validator, the `--help` codec list, and the DICOMStudio Workshop codec picker (which derives from `supportedCodecs()`).
  - **DICOMStudio** (`Sources/DICOMStudio/Views/DataExchangeView.swift`): the Data Exchange compression-algorithm picker gains "JPEG XL Lossless" and "JPEG XL Lossy" entries, with `jpeg-xl` marked lossy.
  - **Tests** (`Tests/DICOMCoreTests/JXLCodecRegistryTests.swift`, `CompressionCodecMapTests.swift`): registry now exposes an encoder for `…4.112`; new round-trips prove an RGB lossy encode decodes back to source dimensions and a grayscale lossy request falls back to lossless (bit-exact); the codec-map parity test pins `jpeg-xl` → `…4.112` and `jpeg-xl-lossless` → `…4.110`.
  - **Note:** `dicom-convert`'s `jpeg-xl`/`jxl` `--transfer-syntax` aliases remain **lossless** (`…4.112` is not yet a convert target) — this change is scoped to `dicom-compress`.

### Added — JPEG XL JPEG Recompression (Transfer Syntax …4.111) in dicom-convert

- **`dicom-convert --transfer-syntax JPEGXLRecompression`** now losslessly transcodes a JPEG Baseline (…4.50) file to JPEG XL JPEG Recompression (`1.2.840.10008.1.2.4.111`) and back. Unlike every other codec, recompression is not a pixel operation: it wraps the existing JPEG bitstream in a JPEG XL container (with a `jbrd` reconstruction box) so the original JPEG is recovered **byte-for-byte** — no additional loss on top of the JPEG the file already carries. The reverse (`…4.111` → `JPEGBaseline`) reconstructs the byte-identical original JPEG.
  - **`JXLCodec`** (`Sources/DICOMCore/JXLCodec.swift`): added the fragment-level `recompressJPEGFragment(_:)` / `reconstructJPEGFragment(_:)` helpers (backed by JXLSwift's `encodeLosslessJPEG` / `decodeLosslessJPEG`), added `…4.111` to the decodable transfer syntaxes, and routed the `…4.111` pixel decode through JPEG reconstruction → the JPEG codec so decoded pixels match the wrapped JPEG with the descriptor's channel layout (rather than the VarDCT bridge's colour-space representation). The forward encode is deliberately NOT registered as a pixel `ImageEncoder` (recompression takes JPEG bytes, not pixels).
  - **`TransferSyntaxConverter`** (`Sources/DICOMCore/TransferSyntaxConverter.swift`): added `isJXLRecompressionForward` / `isJXLRecompressionReverse` predicates (gated to JPEG Baseline ↔ …4.111, matching JXLSwift's baseline-DCT scope), a fragment-level `transcodeJXLRecompression(…)` path (no pixel decode/re-encode — structurally mirrors the J2K↔HTJ2K fast path), the `canTranscode` admission for these pairs, and a lossless-guard bypass so a lossy-Baseline → …4.111 wrap is correctly treated as lossless (it adds no loss).
  - **`DICOMConverter`** (`Sources/DICOMKit/DICOMConverter.swift`): added `JPEGXLRecompression` to the shared convert target catalog, so the new target flows automatically to the CLI `--transfer-syntax` help, the DICOMStudio CLI Workshop picker, the representative parameter catalog, and `parseTarget(_:)` — the CLI and the Workshop share one code path. It is convert-only (not a `dicom-compress`/`CompressionManager` pixel codec).
  - **CLI parity**: `CLIContracts.json` transfer-syntax abstract updated; `cli-parity-gen` gains a derived `syn-ct-baseline.dcm` JPEG-Baseline fixture (`ctbaseline`) and a `dicom-convert ts-JPEGXLRecompression` decoded-pixel-hash scenario exercising the shared path in both surfaces.
  - **Tests** (`Tests/DICOMRoundTripTest/ConvertRoundTripTests.swift`): oracle round-trips proving byte-identical JPEG reconstruction through the …4.111 wrap, …4.111 pixel decode equals the wrapped JPEG's pixels, onward transcode …4.111 → J2K Lossless, and rejection of a non-JPEG source.

### Added — Shared CLI ↔ App Orchestration: CompressionConsole, DICOMConverter, DICOMDIRDumpFormatter, DICOMDIRWorkflow, EncapsulatedDocumentWorkflow

- **`CompressionConsole`** (`Sources/DICOMKit/Compression/CompressionConsole.swift`): Pure shared formatter and input-parser for `dicom-compress`. Both the CLI binary and DICOMStudio's CLI Workshop call this single type for `--quality` / `--backend` parsing, binary byte formatting, and every console line (compress header, stats, batch totals). Replaces duplicated inline formatting on both sides. Mirrors the `NetworkConsole` shared-formatter pattern.
- **`DICOMConverter`** (`Sources/DICOMKit/DICOMConverter.swift`): Single source of truth for the `dicom-convert` transfer-syntax conversion API — the ordered target catalog (UID, CamelCase CLI tokens, kebab aliases), `parseTarget(_:)`, `cliTokens`/`aliasTokens` picker lists, and the shared `convertToDICOM(dicomFile:to:stripPrivate:)` pipeline. Both the CLI (`dicom-convert`) and the DICOMStudio CLI Workshop call this directly so conversion bytes are identical and the `--transfer-syntax` help text cannot drift from the picker.
- **`DICOMDIRDumpFormatter`** (`Sources/DICOMKit/DICOMDIRDumpFormatter.swift`): Shared renderer for `dicom-dcmdir dump` output (tree / json / text formats). The CLI and the CLI Workshop both call `DICOMDIRDumpFormatter.render(_:format:verbose:)` so their output pipelines cannot drift.
- **`DICOMDIRWorkflow`** (`Sources/DICOMKit/DICOMDIRWorkflow.swift`): Shared orchestration helpers for `dicom-dcmdir` — recursive DICOM file discovery (skipping the existing DICOMDIR, sorting by path), the create build-loop (read, compute relative path, add to `DICOMDirectory.Builder`, emit summary), and the validate report (statistics + file-set + record-type breakdown). Both the CLI and the Workshop call these helpers, eliminating hand-mirrored orchestration that could silently diverge.
- **`EncapsulatedDocumentWorkflow`** (`Sources/DICOMKit/EncapsulatedDocument/EncapsulatedDocumentWorkflow.swift`): Shared orchestration helpers for `dicom-pdf` — `EncapsulatedDocumentType.fileExtension`, `defaultModality`, the `--show-metadata` report block, and the human-readable file-size formatter. Both the CLI and the Workshop call these helpers so the `dicom-pdf` parity surface cannot drift.
- **Synthetic DICOMDIR fixture** (`Sources/DICOMStudio/Resources/CLIParity/synthetic/syn-dicomdir`): Pre-built minimal DICOMDIR file added to the synthetic corpus for the offline `dicom-dcmdir` parity scenario, making the dcmdir dump/validate scenarios runnable without a real PACS file hierarchy.

### Fixed — DICOMWriter Drops Encapsulated Pixel Data

- **`DICOMWriter.serializeElement(_:)` now emits encapsulated pixel data** (`Sources/DICOMCore/DICOMWriter.swift`): The generic serializer previously skipped any undefined-length (`0xFFFFFFFF`) element that was not `.SQ`, silently emitting an empty PixelData shell. This caused `DICOMConverter`/`dicom-convert` to fail on ANY compressed source — the decoder saw zero fragments and threw "Frame 0 starts beyond data bounds" — and would have corrupted any `DataSet.write()` / `DICOMFile.write()` rewrite of a compressed dataset. Fixed by adding a dedicated `serializeEncapsulatedPixelData(_:fragments:)` branch that emits the full Basic Offset Table Item + one Item per codestream fragment (odd fragments padded to even length per PS3.5 A.4) + the Sequence Delimitation Item.

### Fixed — DICOMFile.pixelData() No Longer Relabels YBR as RGB

- **Removed stale YBR→RGB photometric relabel** (`Sources/DICOMKit/DICOMFile+PixelData.swift`): The previous code relabelled YBR pixel data as RGB for transfer syntaxes that the retired ImageIO-based codecs once handled (JPEG 50/51/57/70, JPEG 2000 90/91). The current registry uses pure-Swift codecs (JLISwift, J2KSwiftCodec, JPEG-LS, RLE) that decode to the *source* photometric interpretation and leave YBR→RGB conversion to `PixelDataRenderer`. The relabel suppressed that renderer conversion and washed out/blanked colour compressed previews. Removing it restores correct colour rendering for all compressed sources while preserving the existing `isImageIODecodedTransferSyntax` helper (unused after this change).

### Fixed — JPEG-LS NEAR Parameter Overflow for 16-bit Sources

- **JPEG-LS NEAR clamped to 255** (`Sources/DICOMCore/JPEGLSCodec.swift`): JLSwift's `JPEGLSEncoder.Configuration` rejects a NEAR value above 255. For a 16-bit source at high quality, the formula `maxVal * (1 - quality) * 0.1` could yield NEAR ≈ 655, causing the encode to throw. Added a `maxNear = 255` clamp so lossy JPEG-LS encoding of 16-bit images at any quality level succeeds.

### Fixed — PixelEditor Handles Compressed Sources

- **`PixelEditor` decodes encapsulated sources before editing** (`Sources/DICOMKit/PixelEditing/PixelEditor.swift`): Editing a compressed (encapsulated) PixelData element in place corrupts the encoded bitstream; the output — still tagged as the compressed transfer syntax — cannot be decoded by a viewer. `PixelEditor` now detects an encapsulated source, decodes it to native pixels first, and emits the edited result as uncompressed Explicit VR Little Endian. Multi-frame sources are handled correctly.

### Fixed — dicom-pixedit `--invert` Rendered Solid White

- **`PixelEditor` now inverts the VOI window and uses the correct signed pivot** (`Sources/DICOMKit/PixelEditing/PixelEditor.swift`): `dicom-pixedit --invert` (and the CLI Workshop "Invert" toggle, which shares `PixelEditor.processData`) produced a solid-white image. `applyInvert` inverted stored pixels around `2^bitsStored − 1` but never updated the file's VOI Window Center (0028,1050); because the viewer, image exporter, and Horos all honour the stored window by default (`DICOMImageExporter.determineWindowSettings`, rescale-adjusted), every inverted pixel fell outside the unchanged window and clamped to white. Signed data was additionally clamped because the pivot used the unsigned max instead of `−1`. Fixes: (1) invert around `isSigned ? −1 : maxValue`; (2) re-point each Window Center to `slope·pivot + 2·intercept − center` (output-unit equivalent of inverting the stored center around the pivot), leaving Window Width unchanged and no-op when the file carries no stored window; (3) `--apply-window` now bakes into — and resets the stored VOI window to — the full *representable* stored range (signed-aware: `[0, 2^b−1]` unsigned, `[−2^(b−1), 2^(b−1)−1]` signed), so a baked signed image is no longer written into only half the range and rendered ~2× too dark. `formatDS` guards against non-finite values from pathological rescale metadata. Regression tests in `PixelEditorTests` render the inverted frame through the shared viewer/export window policy and assert a true photographic negative (not solid white) for both MONOCHROME2 and MONOCHROME1, plus the signed window-bake range.

### Added — DICOMKitTests: Parity and Regression Test Suite

Seven new test files added to the `DICOMKitTests` target (`Package.swift` sources updated):

- **`EncapsulatedPixelDataWriteTests`**: Regression for the `DICOMWriter` encapsulated pixel data fix — asserts the full BOT + fragment structure is emitted, odd fragments are padded, a zero-fragment BOT writes cleanly, and a round-trip `DataSet.write()` → `DICOMParser.parse()` recovers the original fragments.
- **`CompressionManagerImplicitVRTests`**: Regression for `CompressionManager` on Implicit VR Little Endian sources — pins that the shared `DICOMWriter` path re-encodes sequences from parsed items (not raw bytes) and promotes oversized short-VR values to UN, preventing byte-stream desync and the "No pixel data found" failure on decompress.
- **`CompressedPreviewRenderParityTests`**: Parity regression that the `DICOMFile.pixelData()` return value for a freshly compressed file matches the value after a round-trip decompress, for every codec — so the photometric-relabel removal cannot silently reintroduce colour corruption.
- **`CompressionConsoleTests`**: Contract tests that lock the exact `dicom-compress` console strings produced by `CompressionConsole` — byte formatting, quality parsing, header lines, compressed-result lines — so the CLI and CLI Workshop cannot drift.
- **`DICOMConverterTests`**: Contract tests for the shared `DICOMConverter` API — every catalog token (cliToken / aliasToken / UID / extraAliases) round-trips through `parseTarget`; picker token lists are exactly the catalog; `CLIContracts.json` entry is regenerable from the catalog; DEFLATE converts without error.
- **`ExportWindowParityTests`**: Regression that `DICOMImageExporter.renderFrameForExport` and `determineWindowSettings` rescale-adjust the VOI window (HU → stored via Rescale Slope/Intercept), so a CT with a non-zero Rescale Intercept exports with the correct contrast — not washed out.
- **`PixelEditorTests`**: Regression that `PixelEditor` decodes encapsulated sources to native pixels before editing, emits Explicit VR Little Endian output, and preserves tag edits in the serialized file.

### Added — WADORetrieveConsoleFormatter (Shared WADO-RS / WADO-URI Retrieve Renderer)

- **`WADORetrieveConsoleFormatter`** (`Sources/DICOMWeb/WADORetrieveConsoleFormatter.swift`): Shared output renderer for WADO-RS / WADO-URI retrieve — verbose preamble blocks, per-mode status lines (metadata / rendered / thumbnail / frames / instances / WADO-URI result), and the metadata body (JSON pretty-printed + PS3.19 Native DICOM Model XML). Mirrors `QIDOResultFormatter` (query) and `UPSResultFormatter` (ups): a SINGLE formatter both sides call, so the `dicom-wado retrieve` CLI binary and DICOMStudio's in-app retrieve cannot produce different output.
  - `DICOMWado.swift` (`RetrieveCommand`) now delegates all verbose preamble, per-mode status, and metadata body output to `WADORetrieveConsoleFormatter` instead of hand-rolling inline strings.
  - `CLIWorkshopViewModel.swift` (WADO retrieve case) likewise delegates to the formatter; the mode-detection / inline-echo block is removed, and the verbose preamble is gated by `--verbose` on both sides identically.
  - `parseFrameNumbers` moved from `RetrieveCommand` into `WADORetrieveConsoleFormatter` (as a throwing method returning `[Int]`) with a companion `WADOFrameParseError` type; the CLI catches `WADOFrameParseError` and re-throws as `ValidationError`.

### Added — STOWResultFormatter (Shared WADO STOW-RS Upload Renderer)

- **`STOWResultFormatter`** (`Sources/DICOMWeb/STOWResultFormatter.swift`): Shared console renderer for `dicom-wado store` (STOW-RS) upload output — verbose pre-upload header, per-batch start/result lines, per-failure detail, and the always-printed final summary block. Both the `dicom-wado store` CLI path and DICOMStudio's in-app STOW upload call this single formatter, preventing output pipeline drift. The summary block format is a parity contract that `CLIParityWADOComparator.parseStore` anchors on.

### Added — UPS-RS Parity Harness: Full Operation Matrix, Global Subscribe, and get --format/--verbose

- **UPS write scenarios run out-of-the-box**: The parity harness no longer gates the full UPS operation matrix on a user-supplied Procedure Step Label. A `upsDefaultLabel` (`"CLI Parity Workitem"`) is substituted when the WADO panel's label is blank, so `ups-lifecycle`, `ups-lifecycle-complete`, `ups-lifecycle-cancel`, `ups-get`, `ups-create-attrs`, `ups-create-json`, and `ups-subscribe` always appear in the scenario list — matching how the harness already auto-picks the AE title and station filter.
- **Global UPS subscribe scenario** (`ups-subscribe-global`): New `runWADOUPSSubscribeGlobalScenario` runner exercises `ups --subscribe --aet <ae>` (no `--workitem-uid`) → `ups --unsubscribe --aet <ae>` — the GLOBAL round-trip that subscribes to ALL workitems' events. Reference uses `DICOMwebClient.subscribeToAllWorkitems` + `unsubscribeFromWorkitem(nil)`. Parity on round-trip outcome; servers that don't enable UPS subscription fail both sides identically (`failureAgreement`).
- **ups-get `--format` / `--verbose` variants**: Four `--format` flag variants (`table`, `json`, `csv`) plus a `--verbose` variant are now generated for the `ups-get` scenario. The flags are threaded through `studioParams["get-format"]` and `"get-verbose"` and appended at run time (after the Workitem UID is known), mirroring how the CLI appends them to the chained `ups --get <uid>` command.
- **Transaction UID flow corrected**: The UPS lifecycle runner (`runWADOUPSLifecycleScenario`) no longer pre-mints a Transaction UID and supplies it to the `--update --state IN_PROGRESS` claim. Instead it lets the server assign one, parses it from the CLI's IN PROGRESS output (`Transaction UID: …`), and reuses it for the terminal `COMPLETED`/`CANCELED` transition — exactly how a real operator works. The reference (`CLIParityNetworkReference.wadoUPSLifecycle`) likewise captures and reuses `claimResp.transactionUID`. When no UID is returned the terminal transition is skipped and recorded as not reached.
- **`wadoUPSSubscribeGlobal`** reference method added to `CLIParityNetworkReference`: calls `client.subscribeToAllWorkitems` + `client.unsubscribeFromWorkitem(nil)`; `createOK` is vacuously true (no workitem is created).

### Changed — C-GET and dicom-send Dry-Run Comparators Aligned with Shared Formatters

- **C-GET comparator** (`CLIParityRetrieveComparator`): The shared `NetworkConsole.cGetSummary` now emits exactly one terse line — `"✅ C-GET completed — N file(s) received"` on success or `"⚠️ C-GET completed but received 0 instances. …"` when nothing arrived — instead of a structured `C-GET Completed:` block with sub-operation counts. The parser now reads the received-file count from that line only; `completed`/`failed` are no longer parsed or compared for C-GET (they are unobservable in the CLI text). `canonical()` updated accordingly: C-GET compares `success + files`; C-MOVE still compares `completed + failed + warning`.
- **dicom-send dry-run comparator** (`CLIParitySendComparator`): The shared formatter's dry-run path (`NetworkConsole.sendHeader`) prints the gathered file count in the header's `"Files: N"` field rather than `"Found N file(s) to send"`. The parser now reads the first `"Files:"` line — the header count — rather than `"Found"`.

### Changed — UPS CLI Workshop: unsubscribe Operation and Simplified cliMapping

- **`unsubscribe` operation added** to the UPS parameter definition in `CLIWorkshopHelpers`: the operation picker now lists `search`, `get`, `create-workitem`, `change-state`, `subscribe`, `unsubscribe`. `--workitem-uid` is shown for `unsubscribe` as well as `subscribe` and `create-workitem`.
- **`--search` and `--create-workitem` moved to `cliMapping`**: Both flags are now emitted automatically when the matching operation tab is selected, removing the separate boolean-toggle `CLIParameterDefinition` entries that were previously needed. This mirrors the existing `--subscribe`/`--unsubscribe` mapping pattern.
- **No auto-pre-selection in Network mode**: Switching to Network mode no longer pre-selects the first network tool. The user explicitly picks which tools to include in the parity sweep.

### Fixed — HL7 ORM^O01 Field Placement for dcm4chee-arc MWL Create

- **HL7 ORM IPC segment + OBR field map corrected** (`ModalityWorklistService.buildHL7ORM`): The previous implementation wrote `scheduledStationAETitle` into `OBR-20`, which dcm4chee-arc's default inbound order stylesheet (`hl7-order2dcm.xsl`) reads as the **Scheduled Procedure Step ID** (`0040,0009`) — so a user's Station AET surfaced on the server as the SPS ID. Fixed in two ways:
  - **OBR path corrected**: rebuilt with an explicit index→value map (`hl7Segment(_:fields:)` helper) so the values land at their exact positions. OBR-18 = Accession Number, OBR-19 = Requested Procedure ID, OBR-20 = SPS ID, OBR-24 = Modality, OBR-27 4th component = SPS Start Date/Time.
  - **IPC segment added**: a dcm4che-private `IPC` (Imaging Procedure Control) segment is emitted after OBR so every SPS attribute has an unambiguous, configuration-independent slot — **IPC-7 = Station Name**, **IPC-9 = Scheduled Station AE Title** (the only ORM path that carries them). IPC-1/2/3 also supply Accession / Requested Procedure ID / Study Instance UID, matching the OBR fallback exactly.
  - `buildHL7ORM` promoted from `private` to `internal` to allow the new field-placement regression tests (`Tests/DICOMStudioTests/MWLCreateHL7ORMTests.swift`) to assert each value's exact HL7 position without requiring a live MLLP server.

### Fixed — WADO-URI Endpoint Resolution for dcm4chee5

- **`WADOURIClient.resolveURIEndpoint(_:)`** (new public static method): dcm4chee-arc 5.x serves WADO-URI (`?requestType=WADO`) from `/wado`, while the sibling WADO-RS/QIDO-RS endpoint lives at `/rs`. Supplying a WADO-RS base URL for a WADO-URI request returned HTTP 404. The resolver rewrites a trailing `/rs` path segment to `/wado`; all other base URLs are returned unchanged. Because the `dicom-wado` CLI, CLI Workshop, and parity reference all retrieve through this one client, they resolve identically and cannot drift.

### Fixed — dicom-mpps N-CREATE Status Guard

- **`dicom-mpps create --status` validation**: N-CREATE must always start the step `IN PROGRESS`; the previous code accepted `COMPLETED` or `DISCONTINUED` at creation, which servers reject (terminal states are reached only via N-SET). The `create` subcommand now validates that `--status` is `IN PROGRESS` and emits a clear `ValidationError` directing the user to `dicom-mpps update` for state transitions.

### Added — UPS-RS Result Formatter (Shared)

- **`UPSResultFormatter`** (`Sources/DICOMWeb/UPSResultFormatter.swift`): Shared output renderer for UPS-RS worklist search results — table, JSON (`UPSOutputFormat`), and CSV — used by both the `dicom-wado ups --search` CLI path and DICOMStudio's in-app UPS worklist search. Mirrors `QIDOResultFormatter` (QIDO-RS) and `DICOMQueryResultFormatter` (DIMSE): a single formatter both sides call so their output pipelines cannot drift.

### Added — CLI Workshop PACS Server Edit

- **Edit saved PACS server profiles**: The CLI Workshop saved-server list now supports in-place editing (`beginEditServer(id:)` / `saveEditedServer()` on `CLIWorkshopViewModel`). A new `showEditServerSheet` / `editingServerID` pair drives the edit sheet; saving re-applies the updated values when the edited profile is currently selected. Previously only add and delete were supported.

### Changed — NetworkConsole Shared Formatter Covers All Network CLIs

- **`NetworkConsole` (DICOMNetwork) now covers all DIMSE network tools**: `dicom-echo`, `dicom-mwl` (query), and `dicom-mpps` joined the shared formatter, completing the set started with `dicom-query / dicom-send / dicom-retrieve / dicom-qr / dicom-wado`. All human console output — headers, per-echo progress, summaries, verbose details — routes through one `NetworkConsole` method on both the CLI binary and the DICOMStudio CLI Workshop in-process path, making terminal-compare diff drift impossible by construction.
- **`dicom-send/ProgressReporter.swift` removed**: its logic was absorbed into `NetworkConsole`. Any callers that imported it directly must switch to the corresponding `NetworkConsole.*` methods.

### Added — Network CLI & DICOMweb Tests

- **`MWLCreateHL7ORMTests`** (`Tests/DICOMStudioTests/`): Regression tests asserting each value in the HL7 ORM^O01 message built by `ModalityWorklistService.buildHL7ORM` lands at its exact field position in both the OBR fallback path and the IPC segment, so the field-placement bug (`OBR-20` Station AET mismap) cannot silently return.
- **`UPSTests`** (`Tests/DICOMWebTests/`): Coverage for UPS-RS workitem query parsing and the new `UPSResultFormatter` output (table/JSON/CSV).
- **`WADOURIClientTests`** (`Tests/DICOMWebTests/`): Coverage for `WADOURIClient.resolveURIEndpoint` (no-op for `/wado`, rewrite for `/rs`, passthrough for other paths) and WADO-URI URL building.

### Added — Network Utility (Live Terminal Output)

- **Network Utility panel** (`NetworkUtilityView`, `NetworkUtilityViewModel`, `NetworkUtilityService`): Six-tab general-purpose network diagnostics tool surfaced as a new sidebar destination in DICOMStudio.
  - **Ping** — wraps `/sbin/ping`; live per-packet output streams into a terminal panel, parsed summary (min/avg/max RTT, packet loss) replaces it on completion.
  - **Port Scanner** — concurrent TCP probes via `NWConnection`; results append in arrival order for a live scan log, sorted by port number on completion.
  - **Traceroute** — wraps `/usr/sbin/traceroute`; each hop line streams as it resolves; stderr merged into stdout so the `traceroute to …` header appears at the top in real time.
  - **DNS Lookup** — wraps `/usr/bin/dig` per selected record type (A, AAAA, MX, TXT, NS, CNAME, SOA, PTR); each query echoes a `$ dig …` header then streams its answer block.
  - **Interfaces** — lists all network interfaces with IPv4/IPv6 addresses, MAC address, MTU, flags, and status badges.
  - **Netstat** — wraps `/usr/sbin/netstat`; streams TCP/UDP connections or routing table live; parsed counts (listening/established/routes) shown on completion.
- **Shared host input**: A single `sharedHost` field is shared by the Ping, Port Scanner, and Traceroute tabs — typing a host in any one of them pre-fills the others.
- **`AsyncStream<String>`-based live streaming** (`runStreamingProcess`): All five process-based tools share a single streaming process runner; stdout and stderr are merged into one pipe so output arrives in natural order, then yielded chunk-by-chunk via `AsyncStream`.
- **UTF-8 carry-over buffer**: A `var pending = Data()` accumulator in the `availableData` read loop ensures multibyte characters (IDN hostnames, TXT/PTR record content) are never split and silently dropped between reads.
- **Run-identity guard** (`streamGeneration` / `portScanGeneration`): Each run captures a generation counter; `onChunk` closures and completion assignments check `self.streamGeneration == gen` and discard stale deliveries from cancelled or superseded runs.
- **SIGKILL escalation**: Both the wall-clock watchdog and `ProcessKillBox.cancel()` send SIGTERM then escalate to SIGKILL after a 3-second grace period, preventing hung processes from blocking the UI indefinitely.
- **Watchdog liveness guard**: The watchdog `DispatchWorkItem` checks `proc.isRunning` before acting, preventing a process that exits naturally at the deadline from being mislabelled as timed out.

## [2.1.0] - 2026-05-21

DICOMStudio: J2K Test Bench, responsive layout, and imaging-first navigation.

## [2.0.0] - 2026-05-21

### Added — J2KSwift v3.2.0 Integration (Phases 1–9)

- **J2KSwift v3.2.0 codec stack** (`Sources/DICOMCore/J2KSwiftCodec.swift`, `HTJ2KCodec.swift`, `JP3DCodec.swift`): Replaces Apple ImageIO as the primary JPEG 2000 path on all platforms, enabling full Linux support via a pure-Swift scalar backend.
  - `J2KSwiftCodec`: Handles JPEG 2000 Lossless (`.90`), JPEG 2000 Lossy (`.91`), Part 2 Lossless (`.92`), Part 2 Lossy (`.93`) with 8/12/16-bit grayscale and RGB support.
  - `HTJ2KCodec`: Full HTJ2K Lossless (`.201`), HTJ2K RPCL Lossless (`.202`), HTJ2K Lossy (`.203`). Fast-path transcoder via `J2KTranscoder` (no pixel decode); 5.4× decode speedup over J2K on macOS arm64.
  - `JP3DCodec`: ISO/IEC 15444-10 volumetric encoding/decoding for multi-frame CT/MR/PET series with lossless, lossless-HTJ2K, and lossy modes.
- **JPIP streaming** (`Sources/DICOMKit/DICOMJPIPClient.swift`): Progressive 2D and 3D tile streaming for large remote studies; transfer syntaxes JPIP Referenced (`.94`) and JPIP Referenced Deflate (`.95`) registered.
  - `dicom-jpip` CLI tool with `fetch`, `uri`, `serve`, and `info` subcommands.
  - `DICOMFile.openVolumeProgressively(serverURL:sliceJPIPURIs:qualityLayers:)` API for huge CT/MR datasets.
- **JP3D volume bridge** (`Sources/DICOMKit/JP3DVolumeBridge.swift`): Converts multi-frame DICOM series ↔ `J2KVolume`; preserves `SliceLocation`, `ImagePositionPatient`, `SeriesInstanceUID`.
  - `JP3DVolumeDocument`: Encapsulated document SOP (private SOP `1.2.826.0.1.3680043.10.511.10`) with `.jp3d` payload + JSON sidecar; MIME type `application/x-jp3d`.
  - `DICOMFile.openVolume(from:)` / `openVolume(from:jpipServerURL:)` for unified volume access.
- **Hardware acceleration** (`CodecBackend` enum): Metal (Apple GPU), Accelerate (SIMD), scalar fallback; `CodecBackendProbe` selects best available at runtime. `--backend` flag on `dicom-compress` and `dicom-3d`.
- **`dicom-j2k` CLI tool** (8 subcommands): `info`, `validate`, `transcode`, `reduce`, `roi`, `benchmark`, `compare`, `completions`. 53 tests.
- **DICOMStudio enhancements**:
  - Progressive decoding with `ProgressiveDecodeModel` / `ProgressiveImageView` (AsyncStream-driven `.quarter → .half → .complete` state machine).
  - ROI decoding wired to pinch-zoom gestures.
  - JP3D MPR views (axial / sagittal / coronal) via `JP3DMPRViewModel` / `JP3DMPRView`.
  - JPIP loader with quality-layer slider.
- **Transfer syntaxes** added to registry, `DICOMValidator`, and `StorageSCP` presentation contexts: `.htj2kLossless`, `.htj2kRPCLLossless`, `.htj2kLossy`, `.jpip`, `.jpipDeflate`, `.jpeg2000Part2Lossless`, `.jpeg2000Part2`.
- **DICOMweb HTJ2K media types**: `image/jph` and `image/jphc` advertised in capability; WADO-RS accept headers updated.
- **`dicom-compress`**, **`dicom-convert`**, **`dicom-send`**, **`dicom-retrieve`**, **`dicom-viewer`**, **`dicom-info`**, **`dicom-validate`** extended for HTJ2K, JP3D, and JPIP transfer syntaxes.
- **Codec Inspector panel** in DICOMStudio: shows decoder name, backend (Metal/Accelerate/scalar), and decode timing.

### Fixed
- **JPEG 2000 16-bit rendering pipeline**: Fixed near-black output after conversion when preserving original bit depth
  - Normalized ImageIO-decoded 16-bit JPEG 2000 samples back to the DICOM `Bits Stored` range in `NativeJPEG2000Codec`
  - Preserved original metadata for JPEG 2000 and JPEG 2000 Lossless conversions (`BitsAllocated`, `BitsStored`, `HighBit`)
  - Verified CT-style datasets with VOI/Rescale tags render correctly after implicit VR → JPEG 2000 lossless transcoding

- **DICOM Studio metadata consistency**: Fixed transfer syntax source ordering in metadata loading
  - `MetadataViewModel` now prefers File Meta Information `(0002,0010)` before dataset fallback
  - Aligns metadata display behavior with converted-file transfer syntax as stored on disk

- **Test Infrastructure**: Fixed platform-specific test compilation errors
  - Added `#if canImport(CoreGraphics)` guards to ColorTransformTests for Apple platform-only APIs
  - Fixed DataElement initializer calls in ICCProfileAdvancedTests with missing length parameters
  - Fixed ambiguous type references in SegmentationParserTests
  - Tests now compile cleanly on Linux CI runners and Apple platforms

### Changed - DICOM Standard Edition Update
- **Updated DICOM standard reference from 2025e to 2026a**
  - The 2026a release is now the current edition available at https://www.dicomstandard.org/current/
  - Updated `dicomStandardEdition` constant to "2026a"
  - Updated all source code doc comments referencing DICOM PS3.x editions
  - Updated conformance statement, FAQ, contributing guide, and README
  - Key differences from 2025e to 2026a:
    - New supplements including CT Image Storage for Processing (Sup252)
    - Radiation Dose Structured Report (RDSR) informative annex (Sup245)
    - Enhanced DICOMweb services (Sup248, Sup228)
    - Data dictionary and controlled terminology updates
    - Correction proposals addressing encoding clarifications and CID additions
    - Improved sex and gender data representation
    - Frame Deflate transfer syntax enhancements for segmentation encoding

## [1.2.6] - 2026-02-07

### Added - Phase 5 CLI Tools Complete
- **dicom-mpps (v1.2.6)**: Modality Performed Procedure Step (MPPS) operations
  - N-CREATE operation for creating MPPS instances (procedure start)
  - N-SET operation for updating MPPS instances (procedure completion/discontinuation)
  - Support for IN PROGRESS, COMPLETED, and DISCONTINUED states
  - Referenced SOP instance tracking
  - MPPSService in DICOMNetwork module
  - Complete CLI tool with create and update subcommands
  - Documentation and README

## [1.2.5] - 2026-02-07

### Added - Phase 5 CLI Tools
- **dicom-mwl (v1.2.5)**: Modality Worklist Management
  - C-FIND query support for Modality Worklist Information Model
  - WorklistQueryKeys with flexible filtering (date, station AET, patient, modality)
  - JSON output support for automation
  - Verbose mode for detailed attribute display
  - ModalityWorklistService in DICOMNetwork module
  - Complete CLI tool with query subcommand
  - Documentation and README

## [1.0.0] - TBD

### Major Release - Production Ready

This is the first production-ready release of DICOMKit, a pure Swift DICOM toolkit for Apple platforms (iOS 17+, macOS 14+, visionOS 1+).

### Core Features (v0.1-v0.5)

#### DICOM File Support
- **Reading & Parsing**: Full support for reading DICOM files with comprehensive parsing
- **Transfer Syntaxes**: 
  - Explicit VR Little Endian (1.2.840.10008.1.2.1)
  - Implicit VR Little Endian (1.2.840.10008.1.2)
  - Explicit VR Big Endian (1.2.840.10008.1.2.2)
  - Deflated Explicit VR Little Endian (1.2.840.10008.1.2.1.99)
- **Data Types**: All standard DICOM Value Representations (VR) supported
- **Specialized Types**: Date, Time, DateTime, AgeString, PersonName, UniqueIdentifier, etc.
- **Writing**: Create and modify DICOM files with proper serialization
- **UID Generation**: Utilities for creating unique DICOM identifiers

#### Pixel Data Support (v0.3-v0.4)
- **Uncompressed Images**: Support for all standard photometric interpretations
  - MONOCHROME1, MONOCHROME2
  - RGB, PALETTE COLOR
- **Compressed Images**: Native codec support for:
  - JPEG Baseline (Process 1)
  - JPEG Extended (Process 2 & 4)
  - JPEG Lossless & JPEG Lossless SV1
  - JPEG 2000 (Lossless and Lossy)
  - RLE Lossless (pure Swift implementation)
- **Multi-frame Support**: Handle image sequences
- **CGImage Rendering**: Native Apple platform integration for display
- **Windowing**: Window Center/Width support for grayscale images

### Networking Features (v0.6-v0.7)

#### DICOM Network Protocol (DIMSE)
- **Core Infrastructure**: PDU handling, association management
- **C-ECHO**: Verification service for connectivity testing
- **C-FIND**: Query services for searching DICOM archives (Patient, Study, Series, Image levels)
- **C-MOVE & C-GET**: Retrieve services for fetching studies and images
- **C-STORE**: Storage services (SCU and SCP)
  - Single file and batch storage operations
  - Progress tracking with AsyncSequence
  - Storage SCP for receiving files
- **Storage Commitment**: N-ACTION based commitment verification
- **Advanced Features**:
  - TLS/SSL support for secure connections
  - Connection pooling and reuse
  - Association timeout configuration
  - Asynchronous API with Swift Concurrency

### DICOMweb Services (v0.8)

#### RESTful Web Services
- **WADO-RS**: Retrieve studies, series, and instances via HTTP
  - Multi-part response parsing
  - Metadata retrieval
  - Rendered image support
- **QIDO-RS**: Query services over HTTP
  - Study, series, and instance queries
  - Fuzzy matching support
  - Pagination with limit/offset
- **STOW-RS**: Store instances via HTTP multipart upload
  - Batch upload support
  - Progress tracking
- **UPS-RS**: Unified Procedure Step worklist services
  - Workitem creation, retrieval, updates
  - State transitions (SCHEDULED → IN PROGRESS → COMPLETED/CANCELED)
  - Subscription support for notifications
- **Authentication**: Bearer token and OAuth2 support
- **TLS**: Secure HTTPS connections with custom certificate validation

### Structured Reporting (v0.9)

#### SR Document Support
- **Core Infrastructure**: SR IOD parsing and document tree navigation
- **Document Types**: Support for all standard SR templates
  - Basic Text SR, Enhanced SR, Comprehensive SR
  - Key Object Selection
  - Measurement reports
  - CAD SR (Chest, Mammography)
- **Content Items**: All relationship types and value types supported
- **Coded Terminology**: SNOMED CT, LOINC, RadLex integration
- **Measurement Extraction**: Automated extraction of measurements and coordinates
- **Document Creation**: SR document builders with template validation
- **Template Support**: TID 1500 (Measurement Report), TID 1400 (Chest CAD SR), and more

### Advanced Features (v1.0.1-v1.0.13)

#### Presentation States
- **Grayscale Presentation State (GSPS)**: Annotations, LUT transformations, spatial transforms
- **Color Presentation State (CSPS)**: Color management, blending operations
- **Pseudo-Color**: Color lookup tables, hot/cold mapping

#### Hanging Protocols
- **Protocol Definition**: Screen layout and viewport configuration
- **Matching Logic**: Image set selection based on modality, anatomy, laterality
- **Display Sets**: Multi-image layout management

#### Radiation Therapy (RT)
- **RT Structure Set**: ROI contours, structure visualization, volume calculation
- **RT Plan**: Beam definitions, treatment machine setup
- **RT Dose**: Dose grids, isodose curves, DVH (Dose-Volume Histogram)

#### Segmentation
- **SEG IOD**: Binary and fractional segmentation support
- **Rendering**: Segment overlay with configurable colors
- **Builder API**: Create segmentation objects programmatically

#### Parametric Maps
- **Quantitative Imaging**: Float pixel data support
- **Real-World Value Mapping**: Physical units, SUV calculation
- **ICC Color Profiles**: Professional color management

#### International Support
- **Character Sets**: ISO 2022, ISO 8859, GB18030, GBK, EUC-KR, Shift_JIS, UTF-8
- **Private Tags**: Vendor-specific tag dictionaries (GE, Siemens, Philips)

#### Performance
- **Memory Optimization**: Efficient large file handling
- **SIMD Acceleration**: Vectorized operations for image processing
- **Lazy Loading**: On-demand pixel data decompression

#### Documentation
- **DocC Catalogs**: Comprehensive API documentation
- **Platform Guides**: iOS, macOS, visionOS integration guides
- **DICOM Conformance**: Formal conformance statement

### Example Applications (v1.0.14)

#### DICOMViewer iOS
- Multi-modality image viewer with gesture controls
- Windowing, pan, zoom, measurements
- Hanging protocol support
- Series browser with thumbnails
- Local file import and PACS integration

#### DICOMViewer macOS
- Removed from the repository.

#### Command-Line Tools
- **dicom-info**: Display DICOM file metadata
- **dicom-dump**: Detailed data element dump
- **dicom-convert**: Transfer syntax conversion
- **dicom-anon**: Anonymization tool
- **dicom-validate**: Conformance validation
- **dicom-query**: PACS query tool
- **dicom-send**: DICOM network send utility

#### Sample Code & Playgrounds
- 27 Xcode Playgrounds demonstrating library features
- Integration examples for iOS, macOS, visionOS
- Network protocol examples
- Image processing examples

### Technical Highlights

- **Pure Swift**: No Objective-C runtime dependencies
- **Swift 6 Compliant**: Full strict concurrency support
- **Platform Native**: Leverages Apple frameworks (ImageIO, CoreGraphics, RealityKit)
- **Modern API**: Swift Concurrency (async/await), Sendable types
- **Comprehensive Testing**: 1,920+ tests across core, networking, and applications
- **Medical Imaging Standards**: DICOM PS3.x compliant

### Platform Support

- **iOS**: 17.0 and later
- **macOS**: 14.0 and later  
- **visionOS**: 1.0 and later
- **Swift**: 6.0 and later

### Dependencies

- Swift Argument Parser 1.3+ (for CLI tools only)

### Installation

#### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Raster-Lab/DICOMKit.git", from: "1.0.0")
]
```

### Documentation

- [README.md](README.md) - Overview and quick start
- [CONTRIBUTING.md](CONTRIBUTING.md) - Contribution guidelines
- [MILESTONES.md](MILESTONES.md) - Development roadmap
- [Documentation/](Documentation/) - API documentation and guides

### Known Limitations

- Network integration tests require access to test PACS systems (documented for future)
- Transfer syntax conversion deferred to future versions
- Some advanced character sets deferred (ISO IR 100 extended)
- Store-and-forward networking features deferred

### Security & Privacy

- No known vulnerabilities in dependencies
- HIPAA considerations documented
- PHI (Protected Health Information) handling guidelines provided
- Secure network communication with TLS support

### Breaking Changes

This is the first stable release (v1.0.0). Future breaking changes will only occur in major version updates (2.0, 3.0, etc.).

### Contributors

Built with ❤️ by the DICOMKit team and contributors.

### License

See [LICENSE](LICENSE) file for details.

---

## Pre-release History

For detailed development history of pre-release versions (v0.1 - v0.9, v1.0.1 - v1.0.15), see [MILESTONES.md](MILESTONES.md).

### Notable Pre-release Versions

- **v0.1**: Core infrastructure, basic file parsing
- **v0.2**: Extended transfer syntax support
- **v0.3**: Pixel data access
- **v0.4**: Compressed pixel data
- **v0.5**: DICOM writing
- **v0.6**: Networking (Query/Retrieve)
- **v0.7**: Storage services
- **v0.8**: DICOMweb
- **v0.9**: Structured Reporting
- **v1.0.1-v1.0.13**: Advanced features
- **v1.0.14**: Example applications
- **v1.0.15**: Production release preparation

---

[1.0.0]: https://github.com/Raster-Lab/DICOMKit/releases/tag/v1.0.0
