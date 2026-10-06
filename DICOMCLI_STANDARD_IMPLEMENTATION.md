# `dicom-*` CLI tools — DICOM 2026a verification

Scope: the 42 `dicom-*` executable targets under `Sources/dicom-*` (80 Swift files at the start, 100 at the close — 23 files added, 3 removed again the same day: `TagEditRules.swift` folded into DICOMKit in `d812b918`, the two `RetrieveStatusText.swift` into DICOMNetwork in `5ab35bf4`). Target edition
**DICOM 2026a**. Method: ["Verification method (reuse for every module)"](DICOMCORE_STANDARD_IMPLEMENTATION.md#verification-method-reuse-for-every-module),
applied to the tools' *surface*: every tool is an adapter over a DICOMKit engine that was verified in
[DICOMKIT_STANDARD_IMPLEMENTATION.md](DICOMKIT_STANDARD_IMPLEMENTATION.md), so what is checked here is the
**parameter contract** — the options, flags and arguments the tool accepts (input contract) and the JSON
keys, XML elements, printed labels, status texts and exit codes it emits (output contract) — against the
2026a tables that define those vocabularies. Extraction and diff: [Scripts/diff_cli.py](Scripts/diff_cli.py)
(code side by regex over `@Argument` / `@Option` / `@Flag`, help strings, defaults, enum raw values, JSON
keys, printed labels and exit codes; standard side from the DocBook tables named in each row; the
DICOMKit literal checks of `diff_kit.py` / `diff_web.py` are re-run over every tool's sources).

Started and completed 2026-10-01. Status: **complete** — every tool has both contract tables; all 49 P-items approved and implemented the same day (Priority action list).

Groups (one section each, worked in this order):

| Group | Standard parts | Tools |
|---|---|---|
| G1 Network | PS3.7, PS3.8, PS3.4, PS3.18 | dicom-echo, dicom-send, dicom-query, dicom-qr, dicom-retrieve, dicom-mwl, dicom-mpps, dicom-server, dicom-gateway, dicom-print, dicom-printscp, dicom-wado, dicom-jpip, dicom-cloud |
| G2 File and media | PS3.5, PS3.10, PS3.11, PS3.18 Annex F, PS3.19 Annex A | dicom-dump, dicom-info, dicom-tags, dicom-json, dicom-xml, dicom-dcmdir, dicom-uid, dicom-validate, dicom-diff, dicom-split, dicom-merge, dicom-study, dicom-archive, dicom-export |
| G3 Encoding and pixel | PS3.5, PS3.3, PS3.15 | dicom-compress, dicom-convert, dicom-j2k, dicom-image, dicom-pixedit, dicom-video, dicom-pdf, dicom-anon |
| G4 Derived objects | PS3.3, PS3.16 | dicom-ai, dicom-report, dicom-measure, dicom-3d, dicom-viewer, dicom-script |

Surface extracted by `diff_cli.py --list-surface` on 2026-10-01: 1,042 options/flags/arguments across the
42 tools (9 to 78 per tool).

---

## Summary

| Bucket | Count | Meaning | Status |
|---|---|---|---|
| Carried rows | 4 | D9, D29, D44, D56 — CLI halves of findings opened by earlier reports | ✅ CLI halves closed 2026-10-01 (D9, D29, D56 DICOMStudio halves handed to DICOMStudio) |
| G1 Network | 14 tools | input/output contract vs PS3.7 Annex C, PS3.4 C.4/C.6/K/F/H, PS3.18 | ✅ 14 of 14 contracts done 2026-10-01; dicom-server repaired (D94–D102 closed, `7bad09d`); dicom-cloud excluded from Package.swift (no build) |
| G2 File and media | 14 tools | contract vs PS3.5, PS3.10, PS3.11 Annex H, PS3.18 F, PS3.19 A | ✅ 14 of 14 contracts done 2026-10-01 |
| G3 Encoding and pixel | 8 tools | contract vs PS3.5 8.2 / 10, PS3.6 A-1, PS3.3 C.7.6.3 / C.11.2, PS3.15 E | ✅ 8 of 8 contracts done 2026-10-01 |
| G4 Derived objects | 6 tools | contract vs PS3.3 C.8.20 / C.17, PS3.16 TIDs and CIDs | ✅ 6 of 6 contracts done 2026-10-01 |

---

## Progress log

| Date | Item | What was compared | What changed | Tests |
|---|---|---|---|---|
| 2026-10-01 | D9, D29 | dicom-compress help rows vs PS3.6 Table A-1 (24 match, 1 fixed); dicom-dcmdir profile literals vs PS3.11 Tables A.1-1 … N.1-1 (64 identifiers) | `dfc929c`, `ca2bd29`; D70 opened for DICOMKit; P-DCMDIR-PROFILE | no test target for either tool; binaries built and run; markers pass |
| 2026-10-01 | D44 | dicom-ai segmentation writer vs PS3.3 Tables C.8.20-2 (16 rows), C.8.20-4 (14 rows), A.51-1; CID 7150 / 7151 | `3fe88bd`; D71 opened for DICOMKit | `swift test --filter SegmentationOutputTests`: 5 passed |
| 2026-10-01 | D56 | dicom-video surface (42 declarations, no standard literals) and the new option vs PS3.16 CID 3000 (6 rows) and PS3.3 Table C.7-13 | `8eebfab`; P-AUDIO-SOURCE-PER-TRACK | `swift test --filter AudioChannelSourceOptionTests`: 10 passed; markers pass |
| 2026-10-01 | G1 echo, send, query | echo: PS3.7 9.1.5.1.4, PS3.5 VR AE, PS3.8 9.1.1 (9 options, all plumbing); send: PS3.4 Table B.2-1 (7 rows), PS3.7 Table 9.3-1 priority (matched 2, plumbing 11); query: PS3.4 Tables C.6.1-1/C.6.2-1, C.6-1/-3/-4/-5, C.2.2.2.4/5 (matched 9, wrong 1 fixed, extra 1 documented, plumbing 8) | `0c845da`, `0efff87`, `f24869c`, `695d961`: dicom-send no longer counts A7xx/A9xx/Cxxx C-STORE failures as success (exit 1, retried); `--level image` accepted, IMAGE named in help; README JSON/CSV/exit-code docs corrected; P-QUERY-JSON, P-QUERY-COLUMNS, P-SEND-SUMMARY; D72–D75 opened for DICOMNetwork | `dicom-queryTests` 7, `dicom-sendTests` 6: 13/13 pass; markers 5/5 |
| 2026-10-01 | G1 retrieve, qr | retrieve: PS3.4 Tables C.4-2/C.4-3 (17 status rows generated), PS3.7 Tables 9.3-7/9.3-10, C.6.1-1 levels, PS3.6 A-1 SOP Class names (matched 6, plumbing 10, 2 n/a); qr: PS3.4 C.6 key tables, C.2.2.2.5 range forms (matched 10, extra 1, plumbing 17) | `1f853e8`, `0b5a61a`, `dd74be3`: final status worded per the tables, counters under PS3.7 names, `--hierarchical` help corrected; dicom-qr `query`/`resume` now exit 1 on failed studies, `resume --timeout` added; P-QR-STATUS-TEXT, P-RETRIEVE-PRIORITY, P-RETRIEVE-EXTNEG, P-QR-STATE-MODALITIES, P-QR-PARALLEL; D76–D78 opened for DICOMNetwork | `QueryRetrieveCLIStandardTests` 6 passed; markers 5/5 |
| 2026-10-01 | G1 mwl, mpps | PS3.4 Tables K.6-1 (139 rows), K.6-1a, K.4-1, F.7.2-1 (130 rows), F.7.2-2; PS3.3 C.4-10, C.4-14, C.2-3; PS3.7 Annex C (27 codes); PS3.16 CID 9300/9301. mwl matched 10, wrong 1, plumbing 7; mpps matched 23, wrong 2, missing 1, plumbing 8 | `f2db8f9`: `--sps-status` help listed PPS words, now the 5 SPS Defined Terms; `416de5a`: CID 9300 examples had wrong meanings, `create` requires `--modality`, validates sex/birth date, `update --image-uid` no longer silently dropped, N-CREATE/N-SET statuses named per Annex C; P-MWL-JSON-KEYS, P-MPPS-STRICT; D79–D88 | `MWLMPPSCLIEndToEndTests` 16/16; MPPSDataSetConformanceTests 27 and WorklistQueryKeysTests 31 still pass |
| 2026-10-01 | G1 print, printscp | PS3.4 Annex H and PS3.3 C.13 module tables (Film Session, Film Box, Image Box, Annotation Box, Printer, Print Job, Presentation LUT); print matched 11, wrong 2, missing 2, extra 2, plumbing 24; printscp matched 20, wrong 5, missing 3, plumbing 38 | `ceeb966`: `--medium` adds MAMMO CLEAR/BLUE FILM, help maps each token to the wire value and the wire values are accepted, `--film-size` help lists all 12 IDs, README exit codes corrected; `deb66db`: two attribute names, Annotation Box is N-SET only, `simulate --layout` takes every Image Display Format, numeric densities; P-PRINT-JSON, P-BIN; D89–D93 | dicom-print 9 and dicom-printscp 6 new tests pass |
| 2026-10-01 | G1 server, gateway | server: PS3.6 A-1 names, PS3.4 B.5-1, C.2.2.2, C.4-2/C.4-3, C.6-x key tables, PS3.8, PS3.10 7.1 (options matched 2, plumbing 22); gateway: PS3.3 Table C.7-1, PS3.5 6.2 PN/DA/TM, PS3.4 K.6-1 (matched 1, wrong 3 fixed, plumbing 29); HL7/FHIR are not NEMA and were not checked | `d9cd70b`: 8 SOP Class names to A-1, 6 of 19 C-FIND response VRs wrong (CS) now from the dictionary, IMAGE level named; `95dcd11`: PN component order and multi-script groups, DA/TM, Sex M/F/O, UID checks, Issuer of Patient ID, DICOMKit UID root, ADT type sent as "ADT^AA01" fixed; D94–D104 opened (dicom-server does not compile: D99, High; stored files lack File Meta: D102, High) | `dicom-gatewayTests` 14 pass; dicom-server not buildable (excluded target), checked by script only |
| 2026-10-01 | G1 wado, jpip, cloud | wado: PS3.18 Sections 8, 9, 10, 11 and Annex F (diff_web checks re-run via `Scripts/diff_cli_web.py`: 0 fails; matched 52, wrong 6, missing 9, extra 3, plumbing 18); jpip: PS3.6 A-1 JPIP syntaxes, PS3.3 Pixel Data Provider URL (wrong 2 fixed, plumbing 15); cloud: no DICOM-standard data (plumbing 19) | `39da529`: `--content-type` rejects unrequestable values, frame/limit/offset validated, "IN PROGRESS" accepted, `--transfer-syntax`/`--anonymize`/`--rows`/`--columns`/`--fuzzy-matching` added, `--timeout` honoured, `store` exits 1 if any file failed; `827f021`: .4.204/.4.205 HTJ2K JPIP listed, (0028,7FE0) named, PS3.5 A.6/A.7/A.11/A.12 cited; `b7a11a4` README profile; P-WADO-UPS-STATE, P-WADO-UPS-UPDATE | `dicom-wadoTests` 15/15, `dicom-jpipTests` 6/6 |
| 2026-10-01 | G1 close | `swift build` (all products) and the G1 test targets: dicom-ai, -video, -wado, -jpip, -query, -send, -gateway, -print, -printscp, QueryRetrieveCLIStandardTests, MWLMPPSCLIEndToEndTests, MPPSDataSetConformanceTests, WorklistQueryKeysTests | — | build exit 0; XCTest 78 executed, 0 failures |
| 2026-10-01 | G2 json, xml | PS3.18 F.2.2/F.2.5/F.2.6/F.2.7, 10.4.1.1.2; PS3.19 Tables A.1.5-1/A.1.5-2 and the A.1.6 schema (xmllint); diff_web JSON/XML checks 0 fails; real conversions validated by script; JSON round trip equal by pydicom. Each tool: matched 2, wrong 1, missing 1, extra 2, plumbing 5 | `78214e8`, `4a428da`: **behaviour change** — empty attributes are now kept by default (F.2.5 "shall be preserved"; Table A.1.5-2), `--no-include-empty` restores the old output; `--filter-tag` accepts GGGGEEEE and (GGGG,EEEE); P-JSON-NO-SORT-KEYS, P-XML-NO-KEYWORDS; D110–D115 (D112 High: `--reverse` writes File Meta SOP UIDs that differ from the data set) | dicom-jsonTests 4/4, dicom-xmlTests 4/4 (run in a scratch package: the repo build was broken at that moment by the in-progress dicom-server repair) |
| 2026-10-01 | G2 study, archive, export | hierarchy and identifying attributes PS3.3 C.7.1.1/C.7.2.1/C.7.3.1, PS3.4 C.6 key tables and C.2.2.2 matching, PS3.3 C.11.2 VOI, C.7.6.3.1.2, C.7.6.6, Burned In Annotation, frame-rate attributes (0008,2144)/(0018,0040)/(0018,1063). study matched 3, plumbing 17; archive matched 10, plumbing 20; export matched 12, wrong 2, missing 2 (fixed), plumbing 25 | `b91e7b2` help; `d46affe` archive warns that date ranges and UID lists are matched as exact strings; `104202f` **behaviour change**: contact-sheet and animate now render through the single-image window/rescale path, animate fps defaults from (0008,2144) else (0018,0040) else (0018,1063) instead of 10, Burned In Annotation YES warns; P-EXPORT-1..3, P-STUDY-1, P-ARCHIVE-1; D116–D127 | StudyHelpTests 3, ArchiveQueryKeysTests 6, ExportStandardTests 12: 21 pass |
| 2026-10-01 | G2 dcmdir, uid, validate | dcmdir: PS3.10 8.1/8.2/8.5/8.6, PS3.3 Table F.3-3 (matched 3, wrong 3, missing 1); uid: PS3.5 9.1, B.2, PS3.6 Table A-1 465 rows (matched 5, wrong 5, missing 2, extra 1); validate: Table A-1 keywords/UIDs, 81 printed Type/table citations vs part03, 79 match (wrong 4, missing 1) | `a45fd45`: `validate` checks File-set ID / File ID rules with clause names, `--check-files` really checks, conformant default File-set ID — **behaviour change**: `validate` exits 1 on DICOMDIRs built from `*.dcm` names; `788f620`: malformed `--root` no longer crashes, too-long root no longer repeats one UID, `generate --uuid` (2.25), `lookup --type` covers every A-1 type; `606ef6d`: `--iod` accepts A-1 keywords/UIDs, `--level` help corrected; P-DCMDIR-FSID, P-UID-TYPE; D128–D143 (High: D129 DICOMDIR builder indexes only the first image of each series and first series of each study; D135 `regenerate` leaves nested Referenced SOP Instance UIDs; D137 (0002,0003) ≠ new SOP Instance UID) | 16 new tests pass |
| 2026-10-01 | G2 dump, info, tags | PS3.6 names/keywords/VRs for a CT fixture 31/31; PS3.3 C.7.3.1.1.1 Modality terms (79 current, 18 retired excluded); PS3.5 Table 6.2-1 value limits; PS3.10 Table 7.1-1. dump matched 4, plumbing 6; info matched 1, wrong 1 (fixed), missing 1 (deferred), plumbing 3; tags matched 3, wrong 3 (fixed), plumbing 6 | `e27aa9f` dump: keywords in `--tag`/`--highlight`, negative `--length` crash and `--bytes-per-line 0` hang refused; `ee2ce1f` info: documented `--tag PatientName` example selected nothing, now matches; `b091aa5` tags: `--set` wrote "512 " as text into US, put group 0002 elements in the Data Set (file read back empty), wrote bad DA and over-length PN — now writes the dictionary VR, enforces Table 6.2-1, refuses groups 0002/FFFE/unused (new `TagEditRules.swift`); D144–D150 (D-TAGS-1 High: DICOMKit `TagEditor` keeps the old behaviour, so the Studio Workshop does too) | dump 3, info 2, tags 13: 18/18 pass |
| 2026-10-01 | G2 diff, split, merge | PS3.3 C.7.6.6, C.7.6.16, C.7.6.16.1.2, C.7.6.17; PS3.6 Tables A-1 and 6-1; PS3.5 7.1. diff matched 2, wrong 1, missing 1, plumbing 6; split matched 11, wrong 1, plumbing 6; merge matched 8, plumbing 6 | `2c5428c` diff: `--ignore-tag` accepts (gggg,eeee) and ggggeeee, `--tolerance` help says per byte; `00ba2a3` (restored by `2ef9d28`, `f663f84` after a concurrent commit reverted it) split: `--frames` documented as 0-based (README called it "the DICOM convention"), A-1/6-1 names; `2ef9d28` merge: `--format` help names the A-1 SOP Class, README corrected (Enhanced output exists; inconsistent inputs exit 1); P-DIFF-1, P-SPLIT-1; D151–D154 | 4/4 per tool; round-trip tests and SplitMergeWorkshopCLIParityTests pass against rebuilt release binaries |
| 2026-10-01 | dicom-server repair | D94–D102 against PS3.4 Tables C.4-2, C.6-1..C.6-5, C.2.2.2; PS3.7 9.1.3; PS3.8 D.1; PS3.10 7.1; PS3.5 Table 6.2-1 | `7bad09d`: product, target and `dicom-serverTests` re-enabled; received instances written as PS3.10 files with the negotiated Transfer Syntax; unknown Move Destination → A801 (additive `start --move-destination AE=host:port`); C-GET awaits each C-STORE-RSP, honours C-CANCEL, requires SCP role; missing Q/R Level → A900; the 12 Required/Unique keys of C.6-1..C.6-5 matched and returned; P-DATA fragmented to the peer's Maximum Length; AE titles validated; D155, D156 opened for DICOMNetwork. Still open in the tool (not standard rows): C-MOVE ignores C-CANCEL mid-transfer, storage accepts only uncompressed syntaxes, in-memory index | dicom_serverTests 72/72 incl. an in-process loopback C-ECHO/STORE/FIND/GET/MOVE test; manual DCMTK storescu/findscu/getscu/movescu at PDU 4096 |
| 2026-10-01 | G2 close | `swift build` (all products; owner's uncommitted DICOMStudio edits present and building), release rebuild of dicom-split/dicom-merge, and every CLI test bundle: the 24 per-tool targets (except j2k, G3) plus QueryRetrieveCLIStandardTests, MWLMPPSCLIEndToEndTests, SplitMergeWorkshopCLIParityTests | — | build exit 0; XCTest 247 executed, 0 failures; Swift Testing 2 passed |
| 2026-10-01 | G3 anon | PS3.15 Annex E (Table E.1-1, 647 rows, one element each on a fixture, diffed per profile by script), E.3.x option names, PS3.16 CID 7050; matched 10, wrong 6 (fixed), missing 6 (2 added, 4 deferred), plumbing 8 | `06717c9`: `ps315` no longer ignores `--remove`/`--replace`/`--keep` and writes a real audit log; `--shift-dates` honoured; PS3.15 option flags honoured on every profile; `--remove`/`--replace` take any PS3.6 keyword; output File Meta (0002,0003) = new SOP Instance UID; `--retain-full-dates`, `--retain-modified-dates` added; `--dry-run`/`--verbose` list each action with its PS3.6 name and E.1-1a code; **behaviour change**: combinations that were silently ignored now exit 1; help/README/stderr say `basic` is not the PS3.15 Basic Profile; P-ANON-PROFILE, P-ANON-RETAIN-DATES; D157–D164 (engine; D158, D162 High) | dicom_anonTests 12/12 |
| 2026-10-01 | G3 image, pixedit | image: SC Image IOD PS3.3 Table A.8-1, 9 mandatory modules, Table C.8-24 Conversion Type, run on 6 fixtures and diffed by script (every Type 1/2 attribute present); matched 8, wrong 1, missing 3, plumbing 5. pixedit: C.7.6.1.1.2 Image Type, C.7.6.1 Derivation / Source Image Sequence, C.11.2 window in rescaled units, C.7.6.2 Image Position; matched 3, wrong 4, plumbing 3 | `1c9aaba8` image: (0002,0003) now equals (0008,0018), non-ASCII names get Specific Character Set ISO_IR 192, `--conversion-type` (8 terms, default WSD), VR warnings, README DPI → Nominal Scanned Pixel Spacing; `698de5df` pixedit: output is a Derived Image (new SOP Instance UID, DERIVED, Derivation Description, Source Image Sequence), window read in rescaled units (CT 40/400 now HU), crop moves Image Position (Patient), `--fill-value` clamped to Bits Stored; P-IMAGE-VR, P-PIXEDIT-RANGE; deferred engine rows (CLI works around them, Studio still affected) | 11 new tests pass |
| 2026-10-01 | G3 video, pdf | video: PS3.6 A-1 video syntaxes, PS3.5 8.2.5–8.2.12 limits stated in help, PS3.3 A.32.5–A.32.7, Table C.7-13 (40 rows: matched 20, wrong 3, extra 1, plumbing 16); pdf: Encapsulated PDF IOD A.45.1, C.24.2 Encapsulated Document Module, SC Equipment (25 rows: matched 13, wrong 1, missing 5, plumbing 6), scripted round trip 26/26 attributes, 10/10 value checks | `cfc81d9f` video: warnings for non-Enumerated modality, sex, malformed birth date, unregistered HEVC UIDs; four `VideoConsole.Help` strings corrected (text only); `3c739850` pdf: Encapsulated Document Length written and used on extraction (odd-length PDFs round-trip byte for byte), Specific Character Set ISO_IR 192 for non-ASCII, `--conversion-type`, `--burned-in-annotation`, `--hl7-instance-identifier` (CDA can now be encapsulated); P-VIDEO-MODALITY-ENUMERATED, P-VIDEO-SEX-ENUMERATED, P-VIDEO-TS-REGISTERED; D176–D182 | dicom-videoTests 18/18, VideoConsoleParityTests 60/60, dicom-pdfTests 7/7 |
| 2026-10-01 | G3 compress, convert, j2k | PS3.5 A.4 (fragments, BOT/EOT), 8.2.x; PS3.6 A-1 (7 j2k help names, 10 transcode targets); PS3.3 C.7.6.1.1.5 lossy attributes, C.7.6.1.1.2, C.7.6.3, C.11.2.1.2.1. compress matched 2, extra 2, plumbing 17; convert matched 3, wrong 1, missing 1, plumbing 8; j2k matched 5, wrong 4, plumbing 24 | `363fd82c` j2k: multi-fragment frames, YBR_RCT/YBR_ICT when the codestream uses a colour transform, lossy output gets Lossy Image Compression/Ratio/Method, DERIVED and a new SOP Instance UID, `roi` writes a derived single-frame image, `--quality` reaches the encoder; **behaviour change** `validate` exits 2 on read error (as documented); `d944a32e` compress: help rows pinned by test, README codec table; `55f7fc75` convert: 7 missing A-1 keywords accepted, refuses window width < 1, quality outside 1–100, negative frame; P-CONVERT-TS-KEYWORDS, P-CONVERT-FRAME, P-CONVERT-EXIT, P-COMPRESS-SYNTAX, P-COMPRESS-JSON, P-J2K-FRAME, P-J2K-PART2, P-J2K-JSON; D183–D193 (High: D184–D186, D192, D193 — lossy output keeps the source SOP Instance UID; J2K colour output labelled RGB; decompressed J2K stays YBR_RCT/ICT) | dicom_j2kTests 79/79 (26 new), dicom_compressTests 3/3, dicom_convertTests 8/8 |
| 2026-10-01 | G3 close | `swift build` (all products) and every CLI test bundle (all `dicom_*Tests` targets plus QueryRetrieveCLIStandardTests, MWLMPPSCLIEndToEndTests, SplitMergeWorkshopCLIParityTests, VideoConsoleParityTests); `diff_cli.py` G1, G2, G3 rerun with the UID-in-text check: 0 FAIL | — | build exit 0; XCTest 356 executed, 0 failures; Swift Testing 81 passed |
| 2026-10-01 | G4 report | renders SR only; PS3.3 C.17.3 value types (16) and relationship types (7), Table 8.8-1 coded entries, C.17.2 flags, Content Template Sequence, PS3.6 A-1 SR SOP Class names (20/20); an Extensible SR fixture using every value and relationship type rendered in text/JSON/Markdown/HTML and diffed by script: 75 labels matched, 0 wrong. matched 4, wrong 3, missing 4 (all fixed), plumbing 14 | `89c3ed93`: 10 value types printed `[Content]` and children of non-CONTAINER items were dropped — fixed in every format; CODE as (value, scheme, "meaning"); units by Code Meaning; completion/verification/preliminary flags and root template shown; JSON adds `value_type`, flag keys, `content_template` (no key changed); HTML escaped; **behaviour change**: a non-SR input is refused naming its SOP Class (was an empty report, exit 0); P-REPORT-TEMPLATE, P-REPORT-SUMMARY; D194–D196 | dicom_reportTests 10/10 |
| 2026-10-01 | G4 measure | PS3.3 10.7.1, C.7.6.2.1.1 Pixel Spacing, Tables C.8-2/C.8-71 Imager Pixel Spacing, Nominal Scanned Pixel Spacing, C.7.6.16.2.1 Pixel Measures, C.8.5.5 US Regions, Table C.18.6-1 ROI pixel inclusion, C.11.1 Modality LUT and Rescale Type; PS3.16 unit CIDs; 22 tag literals and 22 citations match. matched 10, wrong 7 (fixed), missing 2 (1 fixed; SUV not offered), plumbing 7. Correction: 2026a 10.7.1.3 has no "UI shall indicate" rule for detector-plane spacing; the wording is in Tables C.8-2/C.8-71 | `0fbc334f`: spacing from Pixel Spacing / Pixel Measures / US region / Imager Pixel Spacing (labelled detector plane) / Nominal Scanned, else pixels with a warning (was mm at an assumed 1 mm/pixel); angles in mm space; ROI by pixel centre; Bits Stored mask; Modality LUT applied (was ignored); HU only when Rescale Type is HU or absent on CT; `--frame` range-checked; output adds `spacing_source` and JSON `unit_ucum`; P-MEASURE-FRAME, P-MEASURE-UNIT; D197 | dicom_measureTests 17/17 |
| 2026-10-01 | G4 ai, script | ai: PS3.16 TID 1500, TID 4019, TID 1001, Table D-1 (coded concepts 35 matched, 0 wrong), CID 7203 / (121322, DCM), PS3.10 7.1; 46 options: matched 5, wrong 1, missing 1, plumbing 39. script: scripts name `dicom-*` tools and options, no DICOM keywords/tags/UIDs (plumbing 9/9) | `1ff3934e` ai: `--format dicom-sr` wrote unregistered titles 129007/129008, (121072, DCM) as "Confidence" (it is "Impressions"), (121191, DCM) misused, a 0–1 value labelled percent, no template and no File Meta — now a TID 1500 Measurement Report from `MeasurementReportBuilder`, validated strictly, confidence as (111012, DCM, "Certainty of Finding") in percent 0–100; `--algorithm-version` added (TID 4019 row 2 mandatory); SR and `enhance` outputs are PS3.10 files; `enhance` writes a DERIVED image with Source Image Sequence; `c233ec05` script: marker; D198–D203 (D202: ScriptEngine templates call `dicom-anon --profile basic/strict`) | dicom_aiTests 11/11 (6 new) |
| 2026-10-01 | G4 3d, viewer | 3d: PS3.3 C.7.6.2 / Table C.7-10 Pixel Spacing order, Equation C.7.6.2.1-1, C.7.4.1.1.1 Frame of Reference, C.7.6.16.2.3/.4 plane functional groups, C.7.6.1.1.2 / CID 7203 derived MPR, C.11.2 (54 rows: matched 1, wrong 16, missing 8, extra 5, plumbing 24); viewer: C.11.2 VOI LUT Function, MONOCHROME1, C.9.2 overlays, Table 10-3 frame numbering, PS3.6 labels (22 rows: wrong 4, missing 5, plumbing 13) | `aa35a519` 3d: Pixel Spacing was read as x\\y (value 1 is the row spacing); slice offset applied to z only instead of along the normal (also moved STL/OBJ vertices); slice spacing from the mean distance along the normal; Frame of Reference / orientation consistency checked; enhanced multi-frame read from plane functional groups; plane names are LPS planes (sagittal/coronal were upside down); `--format dcm` wrote PNG; `--thickness` honoured; derived MPR series with DERIVED and CID 7203; NIfTI/MetaImage affines corrected; `ffbc8d20` viewer: VOI LUT Function, MONOCHROME1 inversion, overlays, 1-based `--frame-number`, PS3.6 labels; P-3D-OBLIQUE, P-3D-INTERPOLATION, P-3D-VOLUME, P-VIEWER-FRAME; D204–D205 | dicom_3dTests 21/21, dicom_viewerTests 8/8 (verified after the agent stopped at the session restart) |
| 2026-10-01 | Deferred rows | Owner: "complete all the deferred row as per the standard". 11 batches plus 3 follow-up rounds closed every open row in this report except the DICOMStudio-owned ones; each row re-checked against the 2026a text before the fix; new rows found on the way (D215–D241) handled the same way. Open: D85, D88, D114, D127, D132, D154 (DICOMStudio), D237 (needs DICOMStudio's exhaustive switch first), D216 (J2KSwift upstream: progression order / TLM), D221 (DICOMToolbox, out of scope). Checker fixes: diff_kit tag names read PS3.6 Tables 7-1 / 8-1 and PS3.7 Table E.1-1, PALETTE accepted as a DICOMDIR record type. New generators: Scripts/generate_dicomdir_profile_rules.py, generate_dicomdir_record_keys.py, generate_confidentiality_profile.py now also emits Tables E.3.10-1 and E.3.4-1 | commits 55b5e6b9 … 7c6dfabd (see each row) | diff_kit / diff_web / diff_network / diff_printkit / diff_renderkit / diff_cli: 0 failing; markers: every module exit 0; full `swift test` exit 0: XCTest 5,798 executed, 44 skipped, 0 failures; Swift Testing 9,083 passed |
| 2026-10-01 | P-items | All 49 P-items implemented after the owner's approval ("complete all items as per standard 2026 a recommendation"), in six batches; uniform rules: 1-based `--frame-number(s)` added and 0-based options deprecated (PS3.3 Table 10-3), PS3.6 keyword JSON keys added next to deprecated old keys, warn→refuse with exit 1, deprecate never remove. Engine rows closed by them: D76, D78, D80, D89, D104, D134, D202. New rows D206–D214. One deviation: retired `explicit-be` is refused rather than accepted by `dicom-compress --syntax` because the engine writes it corrupt (D206) | net `3b0033f8` `5ab35bf4` `f618767c` `cc5f315a`; webprint `c51c05e9` `214bab33` `6db2d67f`; file `c11deab4` `33c5d800` `63740ab9` `72483003` `d0f2152d` `97f83dd2` `0ba637d0` `ba21553f`; pixel `e2c5ea18` `20a9935d` `2539fce6`; codec `cd0184ce` `a82b7530` `d514d47e`; derived `7752b2ac` `cf3f0e57` `c3a1b8c6` `49375769` | per-batch targeted tests pass; full `swift test` (release dicom-split/dicom-merge rebuilt first) exit 0: XCTest 5,557 executed, 44 skipped, 0 failures; Swift Testing 9,047 passed |
| 2026-10-01 | Module close | `diff_cli.py` over all 42 tools: 0 FAIL; `check_nema_markers.py` on every `Sources/dicom-*`: exit 0; full `swift test` (release dicom-split/dicom-merge rebuilt first); D103 closed, D104 carried as P-GATEWAY-SC; Rows handed to DICOMStudio written | `92421a38` (D103) | full `swift test` exit 0: XCTest 5,421 executed, 44 skipped, 0 failures; Swift Testing 9,036 passed |
| 2026-10-01 | Scaffold | `Scripts/diff_cli.py`: surface extractor (1,042 options), generic DICOMKit literal checks re-run per tool, transfer-syntax-name and documented-default checks; this report | — | — |

---

## Priority action list (P-items — need the owner's approval)

| Item | What | Status | Evidence |
|---|---|---|---|
| P-DCMDIR-PROFILE | `dicom-dcmdir create --profile` still accepts STD-GEN-DVD / -USB / -SEC / STD-CTMR-XXXX / STD-US-XXXX. Help calls them deprecated. Use prints one stderr line naming the identifier written and its table (STD-GEN-DVD-JPEG H.1-1, STD-GEN-USB-JPEG J.1-1, STD-GEN-SEC-CD D.1-1, STD-CTMR-CD E.1-1, STD-US-ID-SF-CDR C.1-1). README lists PS3.11 identifiers. DcmdirRoundTripTests.swift:459 and DICOMDcmdirTests.swift:312 now use `.standardGeneralDVDJPEG` / `.standardGeneralUSBJPEG`. `63740ab9` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.11 2026a Tables H.1-1, J.1-1 |
| P-QUERY-JSON | `dicom-query --format dicom-json`: PS3.18 F.2 DICOM JSON Model encoded by DICOMWeb's `DICOMJSONEncoder` (dicom-query now depends on DICOMWeb). Shared side: `QueryOutputFormat.dicomJSON` (`"dicom-json"`), `DICOMQueryResultFormatter(format:level:csvHeader:dicomJSONEncoder:)` overload (DICOMNetwork cannot import DICOMWeb, so the encoder is injected), `GenericQueryResult.dicomJSONElements()` (VR from PS3.6 Table 6-1, text transcoded from the response's (0008,0005) to UTF-8 and (0008,0005) written `ISO_IR 192`, SQ as UN InlineBinary). `--format json` unchanged. dicom-wado `query` / `ups --format json` not touched (owned by the wado agent; same shared encoder applies there). `3b0033f8`, `f618767c` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.18 2026a F.2 |
| P-QUERY-COLUMNS | Table labels are now the PS3.6 Table 6-1 Attribute Names (19 rows dumped): Patient's Name, Patient ID, Patient's Birth Date, Patient's Sex, Number of Patient Related Studies, Study Date, Study Description, Modalities in Study, Number of Study Related Series, Series Number, Modality, Series Description, Series Date, Number of Series Related Instances, Instance Number, SOP Class UID, Columns × Rows, Number of Frames (columns widen to fit; rule spans the row). CSV: default `(GGGG,EEEE)` header kept for compatibility; new `--csv-keywords` (`QueryCSVHeader.keyword`) writes PS3.6 keywords. No parity test pinned the old labels (searched Tests/). Shared formatter, so the Studio query console changes with it. `3b0033f8`, `f618767c` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.6 2026a Table 6-1 |
| P-SEND-SUMMARY | `NetworkConsole.sendSummary(…warnings:)` overload prints `Warnings: N (stored; PS3.4 Table B.2-1 Warning class)` between Succeeded and Failed (only when N > 0, so a warning-free run is byte-identical); `NetworkConsole.sendFileWarningLine(status:)` words the per-file line by Table B.2-1 (`⚠️ Stored with warning: Warning (0xB000): Coercion of Data Elements`); dicom-send uses both and drops its own trailing line; old `sendSummary(total:succeeded:failed:bytes:duration:)` kept. `3b0033f8`, `cc5f315a` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.4 2026a Table B.2-1 |
| P-QR-STATUS-TEXT | Hoisted into DICOMNetwork as public `DIMSEServiceStatusText` / `DIMSEStatusService` / `DIMSEServiceStatusRow`: the 31 rows of PS3.4 2026a Tables B.2-1 (7), C.4-1 (7), C.4-2 (9), C.4-3 (8) generated from the DocBook, verbatim; exact code wins over `A7xx`/`A9xx`/`Cxxx` ranges; `DIMSEStatus.description(for:)`; `subOperationCounts` under the PS3.7 names. dicom-retrieve and dicom-qr deleted their `RetrieveStatusText.swift` copies and use it (CLI text unchanged). `DIMSEStatus.description` itself unchanged (service-agnostic default). **Closes D76** (and D-QR1) on the DICOMNetwork/CLI side; the Studio console must call it (Workshop follow-up). `3b0033f8`, `5ab35bf4` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.4 2026a Tables C.4-2, C.4-3 |
| P-RETRIEVE-PRIORITY | Engine: `RetrieveConfiguration.priority` (new initializer overloads with `priority:`; the two existing initializers keep their signatures and send MEDIUM) drives the C-MOVE-RQ / C-GET-RQ Priority (0000,0700). CLI: `dicom-retrieve --priority low\|medium\|high` and `dicom-qr query\|resume --priority` (LOW 0002H / MEDIUM 0000H / HIGH 0001H, default medium); a non-default value is shown as `Priority:` in the shared retrieve header (`retrieveHeader(…priority:relationalRetrieval:)` overload). Verified on the wire (mock SCP records 0002/0000/0001). `3b0033f8`, `5ab35bf4` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.7 2026a Table 9.3-7 / 9.3-10 |
| P-RETRIEVE-EXTNEG | Engine: public `SOPClassExtendedNegotiation` (item 56H, PS3.7 Table D.3-11) encoded in A-ASSOCIATE-RQ/-AC and decoded (PDUDecoder no longer skips 56H); `RetrieveExtendedNegotiation` (Table C.5-3 byte 1 relational-retrieval, byte 2 Enhanced Multi-Frame Image Conversion — byte 2 only sent when asked; AC per Table C.5-4, missing bytes = 0, no answer = baseline); `RetrieveConfiguration.extendedNegotiation`; `Association.request(…extendedNegotiations:)` overload. With relational-retrieval requested the identifier may omit the above-level Unique Keys; if the SCP does not accept it the request is not sent and the call throws. CLI: `dicom-retrieve --relational-retrieve` (then `--series-uid` / `--instance-uid` alone allowed). dicom-qr: n/a (always STUDY level with the Study Instance UID; documented). Note: the row cited "C.5.1 / Table C.5-1 items 1, 5" — those are the C-FIND bytes; the retrieval sub-item is C.5.2.1 / C.5.3.1, Tables C.5-3 / C.5-4. `3b0033f8`, `5ab35bf4` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.4 2026a C.5.1 |
| P-QR-STATE-MODALITIES | `QRStudyInfo.modalitiesInStudy`, JSON key `ModalitiesInStudy` (exact PS3.6 keyword of (0008,0061)) written next to `modality`, which keeps its old value ((0008,0060)) and is documented as deprecated; old state files decode (key absent → nil). Shared type, so Studio state files carry it automatically. **Closes D78.** `3b0033f8`, `5ab35bf4` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.4 2026a Table C.6-5 |
| P-QR-PARALLEL | Implemented (safe: each DICOMRetrieveService call opens its own association; dicom-retrieve already ran the same pattern). `dicom-qr query --parallel N` retrieves up to N studies at once in batches via a task group; per-study `[i/N] Retrieving` / outcome lines are printed in study order after each batch (N = 1: unchanged output, line before each retrieval); `--parallel` < 1 refused; README no longer says "accepted for compatibility". `5ab35bf4` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | — |
| P-MWL-JSON-KEYS | `NetworkConsole.mwlJSON` also writes the 10 values under their PS3.6 keywords (`NetworkConsole.mwlJSONKeywordKeys`): ScheduledProcedureStepStartDate/StartTime/Status/ID/Description/Location, ScheduledPerformingPhysicianName, RequestedProcedureCodeSequence (array of one code item), ScheduledProtocolCodeSequence (array), ReferencedStudySequence (array of `{ReferencedSOPClassUID, ReferencedSOPInstanceUID}`, every item); the old keys keep their values; `--json` help and README mark them deprecated. **Closes D80.** `3b0033f8`, `cc5f315a` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.6 2026a Table 6-1 |
| P-MPPS-STRICT | Confirmed: the refusals stay errors (exit 64, no override): missing `--modality` (Type 1), `--patient-sex` not M/F/O, non-DA `--patient-birth-date`, `update --image-uid` without study/series; documented in a README "Input Validation" table and the CHANGELOG. No code change (MWLMPPSCLIEndToEndTests 16/16 still pin them). `cc5f315a` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.4 2026a Table F.7.2-1; PS3.3 Table C.2-3 |
| P-PRINT-JSON | `PrintConsoleFormatter.printerStatusJSON` / `jobStatusJSON` add `PrinterStatus`, `PrinterStatusInfo`, `PrinterName`, `Manufacturer`, `ManufacturerModelName`, `ExecutionStatus`, `ExecutionStatusInfo`, `CreationDate` (DA), `CreationTime` (TM) beside the old keys (same values, deprecated in help + README of dicom-print and dicom-printscp); covers `dicom-print status/job` and `dicom-printscp status`; commit `214bab33` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.6 2026a Table 6-1; PS3.3 C.13 |
| P-BIN | `DICOMNetwork.FilmDestination` is now a struct (RawRepresentable, Hashable, Codable single string, CaseIterable) with `.bin(n)` for any n ≥ 1 (≤ 12 digits, CS 16 chars), `init?(rawValue:)` refuses BIN_0 / leading zeros; `.bin1`/`.bin2` deprecated; `dicom-print --film-destination` takes any `bin-N`/`BIN_N`; PrintOptionCatalog uses `.bin(1)/.bin(2)`; Print SCP parser accepts any BIN_i. **Closes D89.** Scripts/diff_network.py and diff_printkit.py taught the struct form (both 0 FAIL); commit `214bab33` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.3 2026a C.13.1 Film Destination |
| P-WADO-UPS-STATE | `dicom-wado ups --state SCHEDULED` refused with exit 1 (was a warning), message cites PS3.18 2026a 11.7.1.4 and PS3.4 Table CC.1.1-2 (C303H); `WADOOptionRules.changeStateTarget`, `WADORefusal`; test `testChangeToScheduledIsRefusedWithExit1`; commit `c51c05e9` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.18 2026a 11.7.1.4 |
| P-WADO-UPS-UPDATE | `ups --change-state <uid>` added as the canonical Change Workitem State option; `--update` kept, help "Deprecated alias of --change-state", stderr note on use; both → exit 1; examples, README updated; commit `c51c05e9` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.18 2026a 11.7 |
| P-JSON-NO-SORT-KEYS | `dicom-json --no-sort-keys` still works. Help says "Deprecated". Use prints a stderr warning citing F.2.2. README updated. `c11deab4` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.18 2026a F.2.2 |
| P-XML-NO-KEYWORDS | `dicom-xml --no-keywords` still works. Help says "Deprecated". Use prints a stderr warning citing Table A.1.5-2. Removed from the discussion examples; README updated. `c11deab4` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.19 2026a Table A.1.5-2 |
| P-EXPORT-1 | New 1-based options: `single --frame-number`, `animate --start-frame-number` / `--end-frame-number`. `--frame`, `--start-frame`, `--end-frame` keep their meaning; help says "deprecated: 0-based index; use …" and use prints a stderr note. Giving a 0-based and a 1-based option together exits 1. Frame number 0 is refused. Out-of-range message: "Frame number N does not exist … numbered 1 to M". `0ba637d0` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.3 2026a C.7.6.6 |
| P-EXPORT-2 | `bulk --organize-by patient|study|series`: the patient folder is now `<Patient ID>`, or `<Patient ID>@<Issuer of Patient ID>` when an issuer is present. Each part is sanitized; an empty ID becomes UNKNOWN. Changed and documented (behaviour change); no flag keeps the old layout. New DICOMKit API: `DICOMImageExporter.patientFolderName(patientID:issuerOfPatientID:)` and `buildOrganizedPath(…patientID:issuerOfPatientID:…)`; the `patientName:` variant is `@available(deprecated)`. `0ba637d0` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.3 2026a Table C.7-1 |
| P-EXPORT-3 | `contact-sheet --apply-window` and `bulk --apply-window` still parse. Help says "deprecated: no effect"; use prints a stderr warning. bulk now passes `applyWindow: false` explicitly, which gives the same output. `0ba637d0` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | — |
| P-STUDY-1 | summary CSV appends `StudyInstanceUID,NumberOfStudyRelatedSeries,NumberOfStudyRelatedInstances` after the old columns. stats JSON adds `StudyInstanceUID`, `NumberOfStudyRelatedSeries`, `NumberOfStudyRelatedInstances`, `ModalitiesInStudy`. compare JSON adds `study1`/`study2` objects with those keys, and `SeriesInstanceUID` per difference. Old keys keep their values and are documented as deprecated. Done with explicit `encode(to:)` on DICOMKit `Statistics` / `StudyComparison` / `SeriesDifference`; decoding unchanged. `d0f2152d` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.6 2026a Table 6-1 |
| P-ARCHIVE-1 | Each `archive_index.json` study (and `list --format json`) gains `ModalitiesInStudy`: the distinct series modalities, computed on encode, so old indexes still load. `query --format json` adds `ModalitiesInStudy`, `NumberOfStudyRelatedSeries`, `NumberOfStudyRelatedInstances`. `modality` / `seriesCount` / `imageCount` keep their values and are documented as deprecated. New API: `ArchiveStudy.modalitiesInStudy`. `97f83dd2` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.6 2026a Table 6-1; PS3.4 Table C.6-5 |
| P-DCMDIR-FSID | `create --file-set-id` outside PS3.10 8.1/8.5 is now refused: exit 1, message cites PS3.10 2026a 8.1, 8.5 and PS3.3 Table F.3-2, nothing written, no override flag. The warning is gone. Note: the File-set ID (0004,1130) is in Table **F.3-2** (dumped), not F.3-3 as the row says. `63740ab9` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.10 2026a 8.5; PS3.3 Table F.3-3 |
| P-UID-TYPE | `dicom-uid lookup` text prints the Table A-1 UID Type verbatim. `--json` adds `uidType` next to `type`, which keeps the old wording and is documented as deprecated. 12 types / 465 rows checked by test against the DocBook dump. New DICOMKit API: `UIDManager.tableA1UIDType(of:)`, `tableA1UIDType(_:uid:)`, `dicomUIDsAsCodingSchemeUID`, plus `UIDConsole.lookupEntryJSON(…uidType:)` / `listingJSON` overloads. `72483003` (closes D134) | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.6 2026a Table A-1 |
| P-DIFF-1 | `dicom-diff` exit codes: 0 identical, 1 different, 2 for a missing file, a file that is not DICOM, or a comparison failure (message on stderr). 64 stays for usage errors. Documented in help and README. `33c5d800` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | — |
| P-SPLIT-1 | New `dicom-split --frame-numbers` (1-based, list and ranges). `--frames` keeps its 0-based meaning; help says "deprecated: 0-based index; use --frame-numbers" and use prints a stderr note. Both together exit 1; Frame number 0 is refused. Shared FrameSplitter progress and errors say "Frame number N"; the verbose banner prints "Frame numbers: …". New SplitConsole API: `parseFrameNumberSelection`, `framesDeprecatedLine`, `framesAndFrameNumbersConflictMessage`, `headerLines(…frameNumbers:)`. The `{number}` pattern variable stays a 0-based index. Release dicom-split and dicom-merge were rebuilt; SplitMergeWorkshopCLIParityTests pass 64 + 60 cases. `ba21553f` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.3 2026a C.7.6.16.1.2 |
| P-ANON-PROFILE | `dicom-anon --profile` default is now `ps315`, and `basic` is an alias of it (stderr note says the old list is `legacy-basic`). The old lists are `legacy-basic`, `legacy-clinical-trial`, `legacy-research`, deprecated with a stderr note. `clinical-trial`/`clinicaltrial`/`research` map to the `legacy-*` lists with the deprecation note. `AnonCLI.Profile` / `resolveProfile` added (CLI only, no DICOMKit API change). Help, README and examples updated. Table E.1-1 fixture re-run by `diffe11.py`: the default, `basic` and `ps315` all give 642 + 5 SQ D rows kept with scrubbed items (= the 647 recorded for ps315, identical to the baseline `out_ps315.dcm`). `legacy-basic` 11, `legacy-clinical-trial` 15, `legacy-research` 1 (same as the old `basic`/`clinical-trial`/`research`). D202 closed in the same commit (ScriptEngine `TemplateGenerator` uses `--profile ps315`, and `--profile ps315 --clean-pixel-data` replaces `strict`; dicom-script README matches; a test parses every template `dicom-anon` line). `e2c5ea18` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.15 2026a Table E.1-1 |
| P-ANON-RETAIN-DATES | `--retain-dates` deprecated: `--help` starts "Deprecated: use --retain-full-dates or --retain-modified-dates", and a stderr note on use names the E.3.6 Option the run applies. Behaviour unchanged. `e2c5ea18` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.15 2026a E.3.6 |
| P-IMAGE-VR | `dicom-image` refuses with exit 1 and writes nothing when any of these holds: `--study-uid`/`--series-uid` breaks PS3.5 9.1; LO (`--patient-id`, `--study-description`, `--series-description`) or a PN component group is over 64 characters or contains a backslash; `--series-number`/`--instance-number` is outside the IS range. `SCOutput.valueWarnings` → `valueViolations`. Help and README updated. `20a9935d` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.5 2026a Table 6.2-1, Section 9 |
| P-PIXEDIT-RANGE | `dicom-pixedit` refuses with exit 1 and writes nothing for a `--fill-value` outside the Bits Stored / Pixel Representation range, and for an `--apply-window` `--window-width` below 1. Before, a width in (0,1) was raised to 1 and a width ≤ 0 reached the engine. `DerivedImage.clampFill` → `fillValueViolation`, plus `windowWidthViolation`. `20a9935d` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.3 2026a C.7.6.3.1, C.11.2.1.2 |
| P-VIDEO-MODALITY-ENUMERATED | `dicom-video convert`/`batch`: a `--modality` other than the IOD's ES/GM/XC is refused with exit 1 before probing or writing. `VideoOptionConformance.warnings` → `violations`. The CLI help adds the refusal; the shared `VideoConsole.Help` is unchanged (Studio). `2539fce6` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.3 2026a A.32.5–A.32.7 |
| P-VIDEO-SEX-ENUMERATED | `--patient-sex` outside M/F/O, and a `--patient-birth-date` that is not DA, are refused with exit 1. `2539fce6` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.3 2026a Table C.7-1; PS3.5 Table 6.2-1 |
| P-VIDEO-TS-REGISTERED | `--transfer-syntax 1.2.840.10008.1.2.4.107.1` / `.108.1` is refused with exit 1 for writing. Table A-1, dumped by script, registers only `.107` and `.108`. DICOMCore unchanged (decision P2). `2539fce6` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.6 2026a Table A-1 |
| P-CONVERT-TS-KEYWORDS | `JPEG2000Lossless` / `HTJ2KLossless` / `JPEGXLLossless` now select their PS3.6 Table A-1 UIDs .90 / .201 / .110 in the `DICOMConverter` catalog (DICOMKit), `TransferSyntax.parseEncoding` (DICOMCore) and so in dicom-convert and dicom-j2k `--target`; the old meaning (reversible encode into .91 / .203 / .112) is renamed `JPEG2000Reversible` / `HTJ2KReversible` / `JPEGXLReversible` (catalog cliTokens; kebab aliases unchanged); one-line stderr note when one of the three keywords is used (`TransferSyntax.reassignedKeywordNote(for:)`, new `reassignedTableA1Keywords`); `TransferSyntax.parse` accepts every Table A-1 keyword of a UID it knows (+11 additive spellings). Tests: all 63 A-1 TS keywords dumped by script — every keyword dicom-convert accepts (21) and every keyword `parse`/`parseEncoding` accepts maps to its A-1 UID; reversible names → general UID with lossless intent; note text. `cd0184ce` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.6 2026a Table A-1 |
| P-CONVERT-FRAME / P-J2K-FRAME | dicom-convert: new 1-based `--frame-number` (default 1); `--frame` kept, help "deprecated: 0-based index; use --frame-number", stderr note on use; both → exit 1 (non-ValidationError); `--frame-number 0` → usage error; out-of-range message "Frame number N does not exist … numbered 1 to T" (new `DICOMConverter.invalidFrameNumberMessage`). `cd0184ce` dicom-j2k info / validate / roi / benchmark / compare: `@OptionGroup FrameSelection` with 1-based `--frame-number` and deprecated 0-based `--frame` (help text, stderr note, both → exit 1); labels "Frame number N" (info "Frame number:     2 of 3", validate/benchmark/compare headers, roi Derivation Description "… of Frame number N of <SOP>", out-of-range error). `d514d47e` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.3 2026a C.7.6.6 |
| P-CONVERT-EXIT | dicom-convert directory run throws `ExitCode.failure` after the summary when any file failed (was 0); README/help exit codes updated; tested with a junk file (exit 1) and an empty dir (exit 0). `cd0184ce` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | — |
| P-COMPRESS-SYNTAX | `decompress --syntax` / `batch --syntax` accept only `explicit-le`, `implicit-le`, `deflate` (new `NativeTargetSyntax`); every encapsulated codec name and unknown names refused with exit 1 citing Table A-1 / PS3.5 A.1, A.2, A.5. **Deviation:** retired `explicit-be` is refused too (exit 1, cites PS3.5 A.3): it was never accepted (not in the codec table) and the engine serializer does not byte-swap values, so accepting it would write corrupt files (D206). Help/README list the native targets and the refusals. `a82b7530` Update 2026-10-01: D206 fixed the big-endian writer (`d37433f0`, `59936daf`; PS3.5 7.3 byte swap, bit-exact LE→BE→LE), so the retired explicit-be target is accepted again. | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.5 2026a A.1, A.2 |
| P-COMPRESS-JSON / P-J2K-JSON | `info --json` adds PS3.6 keyword keys `TransferSyntaxUID`, `Rows`, `Columns`, `BitsAllocated`, `BitsStored`, `SamplesPerPixel`, `PhotometricInterpretation`, `NumberOfFrames` (JSON number, PS3.18 F.2.3 / Table F.2.3-1), `LossyImageCompression` next to the old camelCase keys (old values kept; help + README say deprecated). Shared `CompressionConsole.infoJSON` + new `infoKeywordFields`, new `CompressionInfo.lossyImageCompression` (additive, defaulted). Keywords/tags checked against Table 6-1 dump. `a82b7530` info adds `TransferSyntaxUID`, `NumberOfFrames`; validate adds `TransferSyntaxUID`; info/validate/benchmark/compare add `frameNumber` (1-based); `transferSyntaxUID`, `totalFrames`, `frame` kept with old values, marked deprecated in each subcommand's help and README. `d514d47e` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.6 2026a Table 6-1 |
| P-J2K-PART2 | `transcode --target j2k-part2-*` (and the A-1 keywords `JPEG2000MC` / `JPEG2000MCLossless`) refused with exit 1; message cites PS3.5 2026a A.4.4 plus the engine's `J2KRoutePlanner.unsupportedEncodeReason`; help keeps the three rows under "Refused (exit 1)"; removed from bash completion and the "Valid values" error list. `d514d47e` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.5 2026a A.4.4 |
| P-REPORT-TEMPLATE | `--style` is the canonical option (default, cardiology, radiology, oncology; case-insensitive); `--template` is a deprecated alias (help says so, stderr note on use). Giving both, or an unknown value, is refused with exit 1 and the valid styles are listed (before: silent fallback to `default`). A TID-like value (`1500`, `TID 1500`, `tid1500`) is told that SR templates are PS3.16 TIDs read from Content Template Sequence (0040,A504) and that this option is only a styling preset. `7752b2ac` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.16 2026a (TID numbering) |
| P-REPORT-SUMMARY | Implemented. `--include-summary` / `--no-include-summary` now gates the summary sections (Impressions, Recommendations) in text, HTML and Markdown. The content tree is always rendered. JSON adds `include_summary`. `7752b2ac` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | — |
| P-MEASURE-FRAME | `pixel --frame-number N` (1-based) added. `--frame` (0-based) is deprecated: help says "Deprecated: 0-based index; use --frame-number", with a stderr note on use. Giving both exits 1. `--frame-number 0` is a usage error. Text prints "Frame number N". JSON adds `frame_number` and keeps `frame` (0-based). The out-of-range message now gives Frame numbers 1...n. `cf3f0e57` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.3 2026a C.7.6.6 |
| P-MEASURE-UNIT | JSON `unit` / `area_unit` are kept (display symbols) and marked deprecated in help and README. `unit_ucum` / `area_unit_ucum` carry the UCUM code. Text prints the code with the symbol in parentheses when they differ (`2.0 mm2 (mm²)`, `90.0 deg (°)`, `[hnsf'U] (HU)`). `--unit um` added (UCUM `um` / `um2`). Pixel distances carry `{pixels}`, as PS3.16 TID UNITS write it. Inches and px² have no PS3.16 code and print the symbol only. CID 7460 (cm, mm, um), 7461 (cm2, mm2, um2) and 7462, and CID 82 "comprises the case-sensitive codes of UCUM", were dumped by script; a test pins every coded unit to CID 7460/7461. `cf3f0e57` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.16 2026a CID 7460–7462, CID 82 |
| P-3D-OBLIQUE | `mpr --planes oblique --oblique-normal x,y,z [--oblique-point x,y,z]` (LPS mm; the point defaults to the volume centre). Validation: the normal is required, must not be zero, and both options need `oblique`. Generates one image sampled with Equation C.7.6.2.1-1 (P = S + X·Δi·i + Y·Δj·j). Row/column cosines come from the nearest patient plane, projected into the oblique plane and made orthonormal. Δ is the smaller in-plane source spacing. The grid has a pixel centre on the point. Voxels are read nearest or trilinear; samples outside the volume take its minimum value. `--thickness` averages along the normal. `--format dcm` writes Image Orientation (Patient), Image Position (Patient), Pixel Spacing, Series/Derivation Description "oblique". Tests on a synthetic linear volume: the known oblique gives known values at every interior pixel, the voxel-centre point gives 190, neighbours give +6.25 / +8.839, and IOP is `1\0\0\0\0.7071067812\-0.7071067812`. `c3a1b8c6` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.3 2026a C.7.6.2.1.1 |
| P-3D-INTERPOLATION | `cubic` is deprecated: it maps to linear, with a stderr note (no cubic kernel was implemented). Help and README say `--interpolation` applies to oblique planes only, and that axial/sagittal/coronal planes are cut along the voxel grid with no resampling. `c3a1b8c6` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | — |
| P-3D-VOLUME | The `volume` subcommand is hidden (`shouldDisplay: false`). For any arguments it prints "volume rendering (ray casting) is not implemented; --camera-angle and --transfer-function have no effect" on stderr and exits 1. The arguments became optional, so no usage error (exit 64) comes first. `c3a1b8c6` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | — |
| P-VIEWER-FRAME | `--frame` (0-based) is deprecated: help says so, with a stderr note on use. `--frame-number` (1-based) is the documented option. Both given exits 1 (before: a usage error only when `--frame` ≠ 0). The status line ("Frame number N of M"), thumbnail labels ("Frame number N"; the bare number when a thumbnail is narrower) and "Frame number N is not available" use 1-based labels. `49375769` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.3 2026a Table 10-3 |
| P-GATEWAY-SC | Option (a): `hl7-to-dicom` / `fhir-to-dicom` refuse (exit 1) without `--template`, and refuse a template that claims an image Storage SOP Class (Table B.5-1/B.6-1 name "… Image Storage") with no Pixel Data; message cites PS3.3 2026a Table A.8-1; help, README and CLI_TOOLS_PHASE7.md example updated. **Closes D104.** New `GatewayOutputRules.swift`, `TemplateRequirementTests` (4 tests); commit `6db2d67f` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.3 2026a A.8.1; PS3.4 Table K.6-1 |
| P-AUDIO-SOURCE-PER-TRACK | DICOMKit additions (nothing deprecated): `VideoWorkflow.Metadata.audioChannelSources: [VideoAudioChannel.Source]?` (new init parameter, defaulted; a track without an entry takes `audioChannelSource`); `VideoWorkflow.validateAudioChannelSources(for:metadata:)` (more sources than tracks, or fewer with no default → `Failure.inputError`, exit 1), called by `convert` (after planning, so `--dry-run` refuses too) and `runBatch`; `VideoAudioChannel.channels(describing:sources:)`; `VideoConsole.audioChannelSourceCountLine(given:tracks:)`. `--audio-channel-source` is repeatable: one value = every track (unchanged); several = one per audio track in container order; a mismatch exits 1 and writes nothing. `2539fce6` | ✅ Done 2026-10-01 (owner approval: "complete all items as per standard 2026 a recommendation") | PS3.3 2026a Table C.7-13 (one (003A,0300) Item per channel, each with its own (003A,0208)) |

---

## Deferred findings

### Rows carried into this module (close first)

| ID | Module | Where | Problem | Standard | Severity | Status |
|---|---|---|---|---|---|---|
| D9 | dicom-compress (+ DICOMStudio) | `Sources/dicom-compress/main.swift:63`; `J2KTestBenchModels.swift:123,392` | .4.110 called "JPEG XL Lossless Only"; PS3.6 name is "JPEG XL Lossless". The 25 codec help rows were resolved alias → UID → Table A-1 name by script: 24 match, 1 fixed | PS3.6 2026a Table A-1; PS3.5 Table 8.2.1-1 | Low: text | ✅ CLI half closed 2026-10-01 (`dfc929c`); DICOMStudio half open |
| D29 | dicom-dcmdir (+ DICOMStudio) | `Sources/dicom-dcmdir/main.swift:59,104`; `CLIWorkshopViewModel.swift:1730`, `CLIWorkshopHelpers.swift:3128` | `--profile` help/error listed STD-GEN-DVD / STD-GEN-USB (Annex H/J family headings, not identifiers). 64 identifiers extracted from PS3.11 Tables A.1-1 … N.1-1; help, error list and verbose summary now print the resolved identifier (`DICOMDIRProfile.allStandard`) | PS3.11 2026a Annexes H, J (Tables H.1-1, J.1-1) | Low: text | ✅ CLI half closed 2026-10-01 (`ca2bd29`); DICOMStudio half open |
| D44 | dicom-ai | `AIDICOMOutputGenerator.swift` `createSegmentationObject` | Worse than reported: the writer discarded the builder's data set and emitted 14 attributes plus raw frames — no Segment Sequence, Segmentation Type, Pixel Data element or File Meta; by script, 5 of the 30 rows of Tables C.8.20-2 / C.8.20-4 were written and 10 applicable Type 1/1C rows were missing. Now routes through `Segmentation.buildDataSet` (D37d's check) and `DICOMFile.create`; every segment carries one CID 7150 and one CID 7151 Item, default (85756007, SCT, "Tissue"); additive `--segment-category` / `--segment-type` (keyword or `SCHEME:VALUE[:MEANING]`); new `SegmentPropertyCodes.swift` (8 CID 7150 rows, 21 type keywords from the CIDs CID 7151 includes). `dicom-ai` product and a `dicom-aiTests` target re-enabled in Package.swift (build config, not API) | PS3.3 2026a Tables C.8.20-2, C.8.20-4, A.51-1; PS3.16 CID 7150, 7151 | Medium | ✅ 2026-10-01 (`3fe88bd`); 5 tests pass |
| D56 | dicom-video (+ DICOMStudio) | `convert` / `batch`; CLI Workshop | No option named the audio Channel Source. Correction to the earlier row: (003A,0300) is Multiplexed Audio Channels Description Code Sequence (Type 2C, Cine Module Table C.7-13); the Channel Source is its nested Channel Source Sequence (003A,0208), Type 1, single Item, DCID 3000. Now `--audio-channel-source <value>` on `convert` and `batch` (one of the 6 CID 3000 keywords generated from the DocBook, or `SCHEME:VALUE[:MEANING]`, the CID being Extensible) maps to `VideoWorkflow.Metadata.audioChannelSource`; absent option → no Items, as before. New `dicom-videoTests` target | PS3.3 2026a Table C.7-13; PS3.16 CID 3000 | Low | ✅ CLI half closed 2026-10-01 (`8eebfab`), 10 tests pass; DICOMStudio Workshop half open |

### New findings (other modules, and tool defects left open)

| ID | Module | Where | Problem | Standard | Severity | Status |
|---|---|---|---|---|---|---|
| D70 | DICOMKit | `Sources/DICOMKit/DICOMDIRWriter.swift:273` (`DICOMDirectory.Builder`), `DICOMDIRWorkflow.buildDirectory` | The chosen Application Profile is stored but never enforced: PS3.11 Table D.3-1 allows only Explicit VR Little Endian for STD-GEN-CD, Tables H.3-1 / J.3-1 add specific JPEG (.50/.51/.70) or JPEG 2000 (.90/.91) syntaxes per -JPEG / -J2K profile, and each profile restricts SOP Classes; any syntax / SOP Class is accepted for any profile | PS3.11 2026a Tables D.3-1, H.3-1, J.3-1 | Low | ✅ Closed 2026-10-01 (`c0943cfc`): `DICOMDirectory.Builder.addFile` refuses (throws `DICOMDIRProfileRules.Refusal`, text names the table) a SOP Class or Transfer Syntax the profile's PS3.11 2026a table does not list. The 57 non-Basic-Directory rows of Tables A.3-1, B.3-1, C.3-1, D.3-1, E.3-1, G.3-1, H.3-1, I.3-1, J.3-1, K.3-1, L.3-1, L.3-2, M.3-1 and N.3-1 are generated into `DICOMDIRProfileTables.swift` by the new `Scripts/generate_dicomdir_profile_rules.py` (`--check` re-verifies). The 64 identifiers of Tables A.1-1–N.1-1 are mapped to these tables, and the -JPEG / -J2K, "Disallowed for CD", MPEG-per-profile and US single-frame (Table C.1-1) qualifiers are applied. The result: STD-GEN-CD/-DVD-RAM/-BD allow Explicit VR LE only (D.3-1). -JPEG profiles add .70/.50/.51 and -J2K profiles add .90/.91 (H.3-1, J.3-1, M.3-1). "Composite IODs for which a Media Storage SOP Class is defined in PS3.4" means PS3.4 2026a Tables B.5-1 + GG.3-1 (I.4). G.3-1 and L.3-1 leave the syntax to the Conformance Statement, so they are not checked. Private profiles are not checked. Not enforced: the per-profile image attribute values (D233). |
| D71 | DICOMKit | `Sources/DICOMKit/Segmentation/SegmentationBuilder.swift:1200` `writeDataSet` | `buildDataSet` writes neither the Enhanced General Equipment Module (Table A.51-1 M; Manufacturer, Manufacturer's Model Name, Device Serial Number, Software Versions, all Type 1 per Table C.7-8b) nor the Type 2 Patient / General Study rows, so its output is not a complete Segmentation IOD on its own; dicom-ai adds them itself | PS3.3 2026a Tables A.51-1, C.7-8b | Low | ✅ Closed 2026-10-01 (`96012f70`): `Segmentation.buildDataSet` writes the Type 2 Patient (Table C.7-1: 4 rows) and General Study (Table C.7-3: 5 rows) attributes, zero length when unknown, and the Enhanced General Equipment Module (Table C.7-8b: Manufacturer, Manufacturer's Model Name, Device Serial Number, Software Versions, all Type 1); both modules M in PS3.3 2026a Table A.51-1. New `SegmentationPatientAndStudy` / `SegmentationEquipment` (default `.dicomKit`), `SegmentationBuilder.setPatientAndStudy` / `setEquipment`. dicom-ai still sets these attributes itself after `buildDataSet` — now redundant, left unchanged (SegmentationIODModulesTests) |
| D72 | DICOMNetwork | `StorageService.swift:829` | `StoreResult.success` is false for the Warning class (B000, B006, B007 are successes per PS3.4 Table B.2-1) and Failure statuses are returned rather than thrown, so callers that test `success` alone misreport | PS3.4 2026a Table B.2-1; PS3.7 9.1.1.1.9 | Medium | ✅ Closed 2026-10-01 (`22e39bd8`): `DICOMStorageService.store` sets `StoreResult.success` for the Success and Warning classes (B000/B006/B007 store the instance, PS3.4 2026a Table B.2-1), as `FileStoreResult.success` already did; new `isStored` / `isSuccess` / `isWarning` / `isFailure`; a Failure is still returned, not thrown (now documented on `StoreResult`; throwing would break every caller); `StoreAndForwardQueue` completes warned items; test NetworkDeferredRows2026aTests.testStoreResultClassesFollowTableB21 |
| D73 | DICOMNetwork | `DIMSEStatus.swift` `from(_:)` | No names for 0117 (Invalid object instance), 0210 (Duplicate invocation), 0211 (Unrecognized operation), 0212 (Mistyped argument) | PS3.7 2026a Annex C (C.5.x) | Low | ✅ Closed 2026-10-01 (`e3caf409`): 0117, 0210, 0211, 0212 (and every other PS3.7 2026a Annex C fixed code, 24 sections) are named by `DIMSEStatus.description` via the generated `DIMSEServiceStatusText.annexCRow(for:)`. Correction to the row: the 2026a title of 0117 (C.5.12) is "Invalid SOP Instance", not "Invalid object instance" |
| D74 | DICOMNetwork | `NetworkConsoleFormatter.swift` `levelName(.image)` | Prints "instance"; the Query/Retrieve Level value is IMAGE | PS3.4 2026a C.6.1.1.3 / Table C.6.1-1 | Low | ✅ Closed 2026-10-01 (`22e39bd8`): `NetworkConsole.levelName` returns the Query/Retrieve Level value (PATIENT / STUDY / SERIES / IMAGE, PS3.4 2026a Table C.6.1-1); the Workshop shows the same text through the same function |
| D75 | DICOMNetwork | `NetworkConsoleFormatter.swift:143,155` | C-STORE Warning statuses are rendered neither as success nor failure | PS3.4 2026a Table B.2-1 | Low | ✅ Closed 2026-10-01 (`22e39bd8`, after `3b0033f8`/`cc5f315a`): the shared console renders the Warning class (sendFileWarningLine + summary Warnings, P-SEND-SUMMARY); new `NetworkConsole.sendFileResult(status:rtt:)` renders Success / Warning (stored) / Failure (not stored) from the status in one call (PS3.4 Table B.2-1). Studio follow-up below |
| D76 | DICOMNetwork | `DIMSEStatus.description` | Service-agnostic wording for A701/A702/A801/A900/B000/Cxxx differs from the Q/R names in PS3.4 Tables C.4-2 / C.4-3 | PS3.4 2026a Tables C.4-2, C.4-3 | Low | ✅ Closed 2026-10-01, `3b0033f8` (P-QR-STATUS-TEXT: shared `DIMSEServiceStatusText`, 31 rows of PS3.4 Tables B.2-1, C.4-1, C.4-2, C.4-3) |
| D77 | DICOMNetwork | `NetworkConsoleFormatter` | "Level: Instance"; "Completed:/Failed:/Warnings:" instead of the PS3.7 sub-operation names; "Modality:" label used for Modalities in Study (0008,0061) | PS3.4 2026a C.6.1.1.3; PS3.7 Tables 9.3-7 / 9.3-10 | Low | ✅ Closed 2026-10-01 (`22e39bd8`): retrieve header `Level:` normalised to STUDY / SERIES / IMAGE ("Instance" → IMAGE; Table C.6.1-1 has no INSTANCE); `cMoveResult` counters read "Number of Completed / Failed / Warning Sub-operations" (PS3.7 2026a Table 9.3-10); dicom-qr study entry labels (0008,0061) "Modalities in Study:" (PS3.6) |
| D78 | DICOMNetwork | `QRSessionState.swift:25` | state JSON stores (0008,0060) under `modality` for a study-level (0008,0061) value | PS3.4 2026a Table C.6-5 | Low | ✅ Closed 2026-10-01, `3b0033f8` (P-QR-STATE-MODALITIES: `ModalitiesInStudy` state key) |
| D79 | DICOMNetwork | Sources/DICOMNetwork/DIMSEStatus.swift:278, :280, :282 | C-FIND failure names differ from the 2026a tables: 0xA900 printed "Error: Identifier/Data does not match SOP Class" (K.4-1: "Error: Data Set does not match SOP Class"); 0x0110 printed "Failed: Unable to process" (PS3.7 C.5.21: "Processing Failure"; "Unable to process" is the Cxxx class of K.4-1) | PS3.4 Table K.4-1; PS3.7 C.5.21 | low (wording) | ✅ Closed 2026-10-01 (`e3caf409`): A900 → "Error: Data Set does not match SOP Class (0xA900)" (Tables C.4-1..C.4-3, K.4-1), 0110 → "Processing Failure (0x0110)" (PS3.7 C.5.21); `description(for: .mwlFind)` gives the K.4-1 rows verbatim (FF01 has no "and/or matching" in K.4-1) |
| D80 | DICOMNetwork | Sources/DICOMNetwork/NetworkConsoleFormatter.swift:502-547 | 10 of 38 JSON keys are not PS3.6 keywords (see P-MWL-JSON-KEYS); shared with DICOMStudio's MWL panel | PS3.6 Table 6-1 | low (P-item) | ✅ Closed 2026-10-01, `3b0033f8` (P-MWL-JSON-KEYS: PS3.6 keyword keys) |
| D81 | DICOMNetwork | Sources/DICOMNetwork/ModalityWorklistService.swift:157-168 | `validateScheduledStationAETitle` tolerates `*`/`?` although Table K.6-1 row 3 allows Single Value Matching only for (0040,0001) | PS3.4 Table K.6-1 | low | ✅ Closed 2026-10-01 (`22e39bd8`): `validateScheduledStationAETitle` refuses `*` and `?` — PS3.4 2026a Table K.6-1 "Scheduled Station AE Title shall be retrieved with Single Value Matching only"; affects `forQuery(station:)`, dicom-mwl `--station`, the Workshop MWL panel |
| D82 | DICOMNetwork | Sources/DICOMNetwork/DIMSEStatus.swift:124-171, 267-300 | `DIMSEStatus.from` maps no DIMSE-N code except 0110/0111/0112/0118/0122/0213; 0105, 0106, 0107, 0115, 0116, 0117, 0119, 0120, 0121, 0124, 0210-0212 print "Unknown status"; 0110 is named "Failed: Unable to process" instead of "Processing Failure"; the N-SET A710 Error ID (Table F.7.2-2) is never surfaced | PS3.7 Annex C C.4.2-C.5.25; PS3.4 Table F.7.2-2 | medium (every MPPS and Print failure message) | ✅ Closed 2026-10-01 (`e3caf409`): every Annex C DIMSE-N code is named (no "Unknown status"), 0110 is "Processing Failure"; MPPS N-SET failures surface Error ID (0000,0903) with its Table F.7.2-2 Error Comment (A710 "Performed Procedure Step Object may no longer be updated") and the SCP's Error Comment (0000,0902) in `DICOMNetworkError.mppsOperationFailed` |
| D83 | DICOMNetwork | Sources/DICOMNetwork/MPPSService.swift:1034, :1099; DICOMNetworkError.swift:476 | MPPS N-CREATE / N-SET failures are thrown as `DICOMNetworkError.storeFailed` → "Store failed: …" (a C-STORE wording) | PS3.4 F.7.2.1.4 / Table F.7.2-2 | low (wording) | ✅ Closed 2026-10-01 (`e3caf409`): MPPS N-CREATE / N-SET failures throw the new `DICOMNetworkError.mppsOperationFailed(operation:status:errorComment:errorID:)` ("MPPS N-SET failed: Failure (0x0110): Processing Failure — Error ID A710H: …") instead of `storeFailed`; PS3.4 F.7.2.1.4 (no specific codes) / Table F.7.2-2. dicom-mpps' `rethrowNamed` `.storeFailed` branch is now dead (left in place, see D220) |
| D84 | DICOMNetwork | Sources/DICOMNetwork/MPPSService.swift:143, :162, :326 | `MPPSCodedEntry.parseErrorMessage` and doc comments give "110513\|DCM\|Doctor cancelled procedure" and the title "Procedure Discontinuation Reasons"; Table D-1: 110513 = "Discontinued for unspecified reason", 110500 = "Doctor canceled procedure"; CID 9300 title is "Procedure Discontinuation Reason" | PS3.16 CID 9300, CID 9301, Table D-1 | ✅ Closed 2026-10-01 (`e3caf409`): `MPPSCodedEntry.parseErrorMessage` / docs give "110513/DCM/Discontinued for unspecified reason" and CID 9300 "Procedure Discontinuation Reason" (PS3.16 2026a CID 9300/9301, Table D-1; 110500 is "Doctor canceled procedure"). Workshop placeholder still old (Studio follow-up) |
| D85 | DICOMStudio | Sources/DICOMStudio/Components/CLIWorkshopHelpers.swift:1379-1380 | same wrong placeholder "110513\|DCM\|Doctor cancelled procedure"; and :1217-1221 offers `--modality` as optional ("Any") although `dicom-mpps create` now requires it (Table F.7.2-1 row 105, 1/1) | PS3.16 Table D-1; PS3.4 Table F.7.2-1 | low | ✅ Studio 2026-10-05 (audit 2026-10-06: the row had no Status cell): mpps placeholder 110513 "Discontinued for unspecified reason", --modality required; see DICOMSTUDIO_STANDARD_IMPLEMENTATION.md |
| D86 | DICOMNetwork | Sources/DICOMNetwork/MPPSService.swift:1125-1168 (N-CREATE builder) | the N-CREATE data set never creates (0040,0281) zero-length, yet the N-SET sends it for DISCONTINUED; F.7.2.1.1 note: "If an SCU wishes to use the PPS Discontinuation Reason Code Sequence (0040,0281), it must create that Attribute (zero-length) during N-CREATE"; F.7.2.1.2 "All Attributes shall be created before they can be set" | PS3.4 F.7.2.1.1 note, F.7.2.1.2 | medium (strict SCPs may answer 0105H No such Attribute) | ✅ Closed 2026-10-01 (`e3caf409`): the N-CREATE data set always creates (0040,0281) zero-length (PS3.4 2026a F.7.2.1.1 note; F.7.2.1.2 "All Attributes shall be created before they can be set"); test DIMSENStatusText2026aTests.testNCreateCreatesZeroLengthDiscontinuationReason |
| D87 | DICOMNetwork | Sources/DICOMNetwork/MPPSService.swift:1163 | `add(0x0008,0x0060,.CS, procedureStep.modality)` writes an empty value when `modality` is nil — a Type 1 attribute (Table F.7.2-1 row 105); the engine's `validate(_:for:)` does not check it (the CLI now refuses before calling) | PS3.4 Table F.7.2-1 | medium | ✅ Closed 2026-10-01 (`e3caf409`): `DICOMMPPSService.validate(_:for: .nCreate)` throws invalidState for a nil/blank Modality (0008,0060), Type 1/1 in PS3.4 2026a Table F.7.2-1 — so `create`/`createDetailed` refuse before connecting (Workshop now gets this error for an empty Modality field) |
| D88 | Tests/DICOMStudioTests | NetworkToolWorkshopCLIParityTests.swift:151-157 | parse fixtures use the wrong code/meaning pairs ("110513 Doctor cancelled procedure", "110514 Equipment failure"); harmless for parsing but mislead readers | PS3.16 Table D-1 | low | ✅ Studio half 2026-10-05 (audit 2026-10-06, was "⏳ Open"): NetworkToolWorkshopCLIParityTests fixtures use real CID 9301 pairs; see DICOMSTUDIO_STANDARD_IMPLEMENTATION.md |

| D89 | DICOMNetwork | `Sources/DICOMNetwork/PrintService.swift:272-277` | `FilmDestination` has only BIN_1 and BIN_2; Table C.13-1 defines BIN_i "with no maximum", without leading zeros. Adding cases is public API: see P-BIN | PS3.3 2026a Table C.13-1 | Low | ✅ Closed 2026-10-01, `214bab33` (P-BIN: `FilmDestination.bin(n)`, Table C.13-1) |
| D90 | DICOMPrintKit | `Sources/DICOMPrintKit/PrintConsoleFormatter.swift:21-37, 93-109` | Printer/job status labels "Name", "Status", "Status Info", "Model", "Created" instead of the PS3.3 attribute names (Printer Name, Printer Status, Printer Status Info, Manufacturer's Model Name; Execution Status, Execution Status Info, Creation Date/Time). Shared with DICOMStudio and dicom-printscp `status` | PS3.3 2026a Tables C.13-8, C.13-9; PS3.6 Table 6-1 | Low | ✅ Closed 2026-10-01 (`350bc2de`): PrintConsoleFormatter printerStatusText / jobStatusText labels are the PS3.3 2026a Table C.13-9 / C.13-8 attribute names as PS3.6 Table 6-1 spells them (Printer Name, Printer Status, Printer Status Info, Manufacturer, Manufacturer's Model Name; Execution Status, Execution Status Info, Creation Date, and a new Creation Time line); JSON unchanged; PrintConsoleLabelTests (2) |
| D91 | DICOMNetwork | `Sources/DICOMNetwork/DIMSEStatus.swift:124-160, 264-300` (used by `DICOMNetworkError.printOperationFailed`, DICOMNetworkError.swift:484) | Print Management statuses carry no Annex H name: C6xx prints as "Failed: unable to process / cannot understand (Cxxx)" and B6xx as "Unknown status". It should name e.g. 0xC603 "Failed: Image size is larger than image box size", 0xB605 "Requested Min Density or Max Density outside of printer's operating range…" (a lookup by the SOP Class of the request) | PS3.4 2026a Tables H.4.1.2.1.2-1, H.4-4, H.4.2.2.1.2-1, H.4-9, H.4.3.1.2.1.2-1, H.4.3.2.2.1.2-1, H.4.9.2.1.2-1 | Low–Medium | ✅ Closed 2026-10-01 (`e3caf409`): the 7 Annex H status tables are carried verbatim (`DIMSEStatusService` print cases, `DIMSEServiceStatusText.printRow(for:)` / `describePrintStatus`); `DICOMNetworkError.printOperationFailed` prints e.g. "Failure (0xC603): Failed: Image size is larger than image box size" (PS3.4 2026a Tables H.4.1.2.1.2-1, H.4-4, H.4.2.2.1.2-1, H.4-9, H.4.3.1.2.1.2-1, H.4.3.2.2.1.2-1, H.4.9.2.1.2-1). The error does not carry the operation, so a code is looked up across the print tables (every C6xx failure has one meaning; B604/B60A take the H.4-4 wording); callers that know the operation can use `status.description(for: .filmBoxNAction)` etc. |
| D92 | DICOMPrintKit | `Sources/DICOMPrintKit/Printing/FilmComposer.swift:817-838` | Trim = YES is drawn as four crop marks at the sheet corners; Table C.13-3 says "a trim box shall be printed surrounding each image on the film" | PS3.3 2026a Table C.13-3 Trim (2010,0140) | Low (emulator fidelity) | ✅ Closed 2026-10-01 (`350bc2de`): FilmComposer strokes a trim box just outside each placed image when Trim (2010,0140) = YES ("a trim box shall be printed surrounding each image on the film", PS3.3 2026a Table C.13-3) instead of sheet-corner crop marks; `drawTrimMarks` / `--trim-marks` keep their names (help/README reworded); FilmComposerTests +2 |
| D93 | DICOMNetwork | `Sources/DICOMNetwork/PrintSCPTypes.swift:91-115` (`PrintSCPStatus.explanation`, also the default Error Comment) | 6 of 9 Annex H codes paraphrased. B604 should read "Image size is larger than image box size, the image has been demagnified.", B605 "Requested Min Density or Max Density outside of printer's operating range. The printer will use its respective minimum or maximum density value instead.", B609 "Image size is larger than the Image Box size. The Image has been cropped to fit.", C603 "Failed: Image size is larger than image box size", C605 "Failed: Insufficient memory in printer to store the image", C613 "Failed: Combined Print Image size is larger than the Image Box size" | PS3.4 2026a Tables H.4-4, H.4-9, H.4.2.2.1.2-1, H.4.3.1.2.1.2-1, H.4.3.2.2.1.2-1 | Low | ✅ Closed 2026-10-01 (`e3caf409`): `PrintSCPStatus.explanation` reads the Annex H Further Meaning / Annex C title from the generated table (B604, B605, B609, C603, C605, C613 verbatim; C600/C601 with "Failed: "; 0117 "Invalid SOP Instance", 0119 "Class-Instance conflict"); Error Comment still truncated to the 64 chars of LO by PrintSCP |
| D94 | dicom-server | DICOMServer.swift StartCommand; ServerSession.swift implementationClassUID | --aet / --allowed-ae / --blocked-ae not validated as VR AE (16 chars); Implementation Class UID 1.2.826.0.1.3680043.9.7433.1.2 is not under DICOMKit's root (1.2.826.0.1.3680043.10.511) | PS3.5 Table 6.2-1, 9.1 | Low | ✅ Closed 2026-10-01 (`7bad09d`); dicom-serverTests 72 pass |
| D95 | dicom-server | ServerSession.swift sendDIMSEResponse / sendAssociationAccept | Outgoing P-DATA fragmented to the server's own --max-pdu-size instead of the peer's Maximum Length; AC does not carry the server's Maximum Length | PS3.8 D.1; PS3.7 D.3.3.1 | Medium | ✅ Closed 2026-10-01 (`7bad09d`); dicom-serverTests 72 pass |
| D96 | dicom-server | ServerSession.swift sendToDestination (fallback `("localhost", 104, destination)`) | Unknown Move Destination is sent to localhost:104 instead of status A801 "Refused: Move Destination unknown" | PS3.4 Table C.4-2 | Medium | ✅ Closed 2026-10-01 (`7bad09d`); dicom-serverTests 72 pass |
| D97 | dicom-server | ServerSession.swift sendViaCStore | C-GET sub-operations counted Completed without awaiting C-STORE-RSP; no SCP/SCU Role Selection; only the 5 accepted storage classes can be returned | PS3.4 C.4.3.3.1; PS3.7 D.3.3.4 | Medium | ✅ Closed 2026-10-01 (`7bad09d`); dicom-serverTests 72 pass |
| D98 | dicom-server | DatabaseManager.swift `matchesWildcard` | Wildcard applied to UI keys (C.2.2.2.4 lists AE, CS, LO, LT, PN, SH, ST, UC, UR, UT only), case-insensitive for non-PN (C.2.2.2.4 "case sensitive, except PN"), no List of UID Matching (C.2.2.2.2), no Range Matching for Study Date (C.2.2.2.5) | PS3.4 C.2.2.2 | Medium | ✅ Closed 2026-10-01 (`7bad09d`); dicom-serverTests 72 pass |
| D99 | dicom-server | Package.swift:214, 1140; DICOMServer.swift; ServerSession.swift | Target excluded and ~35 compile errors against the current DICOMNetwork/DICOMKit API; DICOMServerTests compiled by no target | — | High | ✅ Closed 2026-10-01 (`7bad09d`); dicom-serverTests 72 pass |
| D100 | dicom-server | DatabaseManager.swift query*Level | Required keys not matched/returned: Study Time, Accession Number, Study ID (C.6-2), Patient's Name at Study level (C.6-5), Series Number (C.6-3), Instance Number (C.6-4); responses carry a fixed attribute set instead of the requested keys and omit Query/Retrieve Level (C.4.1.1.3.2) | PS3.4 Tables C.6-1..C.6-5, C.4.1.1.3.2 | Medium | ✅ Closed 2026-10-01 (`7bad09d`); dicom-serverTests 72 pass |
| D101 | dicom-server | ServerSession.swift handleCFind/CMove/CGet (`?? "STUDY"`) | Missing Query/Retrieve Level (0008,0052) defaults to STUDY; the request Identifier "shall contain" it (C.4.1.1.3.1 / C.4.2.1.4.1) — should fail A900 | PS3.4 C.4.1.1.3.1, Table C.4-1 | Low | ✅ Closed 2026-10-01 (`7bad09d`); dicom-serverTests 72 pass |
| D102 | dicom-server | StorageManager.swift storeFile; ServerSession.swift handleCStore | Stored files lack preamble/DICM/File Meta (PS3.10 7.1) and the data set is parsed without the negotiated transfer syntax; sendViaCStore then rejects every stored file (no DICM) | PS3.10 7.1; PS3.5 10 | High | ✅ Closed 2026-10-01 (`7bad09d`); dicom-serverTests 72 pass |
| D103 | dicom-gateway | GatewayListener.swift handleDICOMClient / forwardToPACS | `forward --listen-port` accepts TCP but implements no PS3.8 Upper Layer / C-STORE SCP; `listen --forward pacs://` only prints "Would forward" | PS3.8 9; PS3.4 B | Low (help overstates) | ✅ Closed 2026-10-01 (`92421a38`): help and a stderr warning now say both are not implemented; implementing them is a feature, not a standard row |
| D104 | dicom-gateway | HL7ToDICOMConverter.swift / FHIRConverter.swift createBasicDICOMFile | Without --template the output claims Secondary Capture Image Storage but has no Image Pixel Module and no Type 1 Conversion Type (0008,0064) — not a conforming SC instance; an MWL-shaped output (PS3.4 Table K.6-1) or a template requirement is a design decision | PS3.3 A.8.1; PS3.4 K.6-1 | Medium | ✅ Closed 2026-10-01, `6db2d67f` (P-GATEWAY-SC: `--template` required, PS3.3 Table A.8-1) |
| D105 | DICOMWeb | `QIDOResultFormatter` (QIDOResultFormatter.swift:34, :95, :148) | study column "Modality" holds Modalities In Study (0008,0061); "# Images" is Number of Series Related Instances (0020,1209); "SOP Class" truncates the UID to 15 chars. PS3.6 Table 6-1 names | see the tool section | Low | ✅ Closed 2026-10-01 (`f4262b4f`): `QIDOResultFormatter` table labels are the PS3.6 2026a Table 6-1 Attribute Names (12 dumped): Study Instance UID, Patient's Name, Study Date, Modalities in Study, Number of Study Related Series, Series Instance UID, Modality, Series Description, Number of Series Related Instances, SOP Instance UID, SOP Class UID (now printed whole, no 15-char cut), Number of Frames; border widths kept; tests QIDOResultFormatterTests (3 new). CLI and DICOMStudio both get it (shared formatter). |
| D106 | DICOMWeb | `STOWResultFormatter.failureReason` (STOWResultFormatter.swift:52) | prints "Code <decimal>" without the PS3.18 Table I.2-2 meaning/hex; Warning Reason (Table I.2-1) never printed | see the tool section | Low | ✅ Closed 2026-10-01 (`f4262b4f`): `STOWResultFormatter.failureReason` prints `<hex> (<decimal>): <meaning>` from PS3.18 2026a Table I.2-2 (6 rows, A7xx/A9xx/Cxxx ranges; server description appended in brackets); Warning Reason (0008,1196) is now read from Referenced SOP Sequence items (Table I.1-1) into new `InstanceResult.warningReason` and `STOWResponse.warnings`, printed by new `STOWResultFormatter.warningDetail` with the Table I.2-1 meaning (3 rows) under `dicom-wado store --verbose`; new `STOWResponse.standardMeaning(forFailureReason:/forWarningReason:)`; tests WebClientDeferredRowsTests (2). |
| D107 | DICOMWeb | `UPSQuery.workitemSearch` (Sources/DICOMWeb/UPS/UPSQuery.swift:611) | rejects the standard term "IN PROGRESS" (accepts only IN_PROGRESS/INPROGRESS); PS3.3 Table C.30.1-1 (Tool normalises before calling.) | see the tool section | Low | ✅ Closed 2026-10-01 (`f4262b4f`): `UPSQuery.workitemSearch` accepts "IN PROGRESS" as PS3.3 2026a Table C.30.1-1 spells it (Enumerated Values SCHEDULED, IN PROGRESS, CANCELED, COMPLETED; = PS3.4 Table CC.1.1-1), case-insensitive, IN_PROGRESS/INPROGRESS kept; error text names the standard term; dicom-wado's `WADOOptionRules.searchFilterState` rewrite removed (internal helper, trivially safe); tests UPSTests.testWorkitemSearchAcceptsTheStandardInProgressTerm, WADOOptionRulesTests. |
| D108 | DICOMWeb | `WADOURIClient` | 9 optional WADO-URI parameters (charset, annotation, imageAnnotation, imageQuality, region, windowCenter, windowWidth, presentationUID, presentationSeriesUID) and 8 Rendered Media Types (image/jxl, video/mp4, video/H265, text/*, application/pdf) not requestable; PS3.18 Tables 9.4.1-1, 9.5.1-1, 8.7.4-1. Low (optional). | PS3.18 2026a Section 9 | Low | ✅ Closed 2026-10-01 (`f4262b4f`): new `WADOURIClient.Parameters` / `MediaType` / `Region` / `retrieve(studyUID:seriesUID:objectUID:parameters:)` / `requestURL(...)` / `WADOURIParameterError` carry all 19 parameters of PS3.18 2026a Tables 9.1.2-1 (4), 9.1.2-2 (2), 9.4.1-1 (3), 9.5.1-1 (12) — `annotation` for application/dicom, `imageAnnotation` for rendered, as the two tables name it — and the 14 distinct Rendered Media Types of Table 8.7.4-1 (image/jxl, video/mp4, video/H265, text/html, text/plain, text/xml, text/rtf, application/pdf added); rules 9.1.2.2.1, 9.5.1.2.1, 9.5.1.2.4 (rows/columns pair), 9.5.1.2.5 (region), 9.5.1.2.6 (window pair, not with application/dicom, not with a Presentation State), 9.5.1.2.7 (presentation pair), 8.3.5.1.2 (quality 1-100) checked before sending. `ContentType` enum and the old `retrieve` unchanged (DICOMStudio's exhaustive switch over it still compiles). dicom-wado `retrieve --uri` adds `--charset`, `--annotation`, `--image-quality`, `--region`, `--window-center`, `--window-width`, `--presentation-uid`, `--presentation-series-uid` (additive) and accepts the 15 contentType values; behaviour change: `--rows` without `--columns` (or reverse) is now refused (9.5.1.2.4 "both shall be present"). Tests WebClientDeferredRowsTests (3), WADOOptionRulesTests (2 new, 2 updated). |
| D109 | DICOMCore | `TransferSyntax.isJPIP` (Sources/DICOMCore/TransferSyntax.swift:1087) returns false for 1.2.840.10008.1.2.4.204 / .205 (JPIP HTJ2K Referenced [Deflate], PS3.5 A.11 / A.12, PS3.6 Table A-1), so `DICOMJPIPClient.jpipURI` (DICOMKit/DICOMJPIPClient.swift:335) throws notAJPIPTransferSyntax for them; the .204 doc comment (TransferSyntax.swift:581) says "the Pixel Data is a URI reference" (A.11 | Pixel Data absent, (0028,7FE0)) | see the tool section | Medium | ✅ Closed 2026-10-01 (`0d8aa69d`): `TransferSyntax.isJPIP` now covers .204 JPIP HTJ2K Referenced and .205 JPIP HTJ2K Referenced Deflate (PS3.5 2026a A.11 / A.12: "Pixel Data (7FE0,0010) shall not be present, but rather Pixel Data shall be referenced via Data Element (0028,7FE0) Pixel Data Provider URL"; PS3.6 Table A-1, 4 JPIP rows), so `DICOMJPIPClient.jpipURI` serves all four; .204 doc comment now cites A.11 incl. its PI limit; .94/.95 citations corrected A.8 → A.6 / A.7; dicom-jpip's own .204/.205 fallback removed (`JPIPSyntaxes.pixelDataProviderURL` now calls `jpipURI`) |
| D110 | DICOMWeb | `DICOMJSONEncoder.encodeElement` (Sources/DICOMWeb/DICOMJSONEncoder.swift:159) and `DICOMXMLEncoder` (Sources/DICOMWeb/DICOMXMLEncoder.swift:188) | The BulkDataURI is `<base>/<GGGGEEEE>` regardless of nesting, so the same tag in two sequence items, or at two levels, gets one URI for different values. PS3.18 F.2.6 / PS3.19 Table A.1.5-2: the URI references that element's own Bulk Data. Low. | see the tool section | Low | ✅ Closed 2026-10-01 (`d6baa4f7`): `DICOMJSONEncoder` and `DICOMXMLEncoder` name a nested element's Bulk Data `<base>/<SQ tag>/<item n>/…/<GGGGEEEE>` (top level unchanged `<base>/<GGGGEEEE>`; XML uses the full gggg,xxee tag of a private element, so two private blocks no longer share a URI); PS3.18 2026a F.2.6, PS3.19 Table A.1.5-2; tests DataExchangeDeferredRowsTests (JSON, XML); dicom-json/dicom-xml help + README state the item form. |
| D111 | DICOMWeb | `DataExchangeWorkflow.encode` (Sources/DICOMWeb/DataExchangeWorkflow.swift:154-156) | `metadataOnly` removes only (7FE0,0010) at the top level. Float Pixel Data (7FE0,0008), Double Float Pixel Data (7FE0,0009), Encapsulated Document (0042,0011), waveform and overlay data stay inline (seen: a 2048-byte OB was inlined). PS3.18 10.4.1.1.2 / 10.4.3.3.2 define Metadata as all attributes with the bulk data omitted or replaced by a BulkDataURI. Low (the help now says what the flag does). | see the tool section | Low | ✅ Closed 2026-10-01 (`d6baa4f7`): `DataExchangeWorkflow.encode` metadataOnly leaves out every OB/OD/OF/OL/OV/OW/UN value at any depth (Pixel Data, Float/Double Float Pixel Data, Encapsulated Document, Waveform, Overlay, LUTs — PS3.19 A.1.5-2 names "pixel data or look up tables" as Bulk Data), or with `--bulk-data-url` writes each as a BulkDataURI/BulkData (PS3.18 2026a 10.4.1.1.2 "without Bulk Data", 10.4.3.3.2); behaviour change; dicom-json/dicom-xml `--metadata-only` help and README rewritten; tests DataExchangeDeferredRowsTests (2), DICOMJsonOptionsTests, DICOMXmlOptionsTests. |
| D112 | DICOMWeb | `DataExchangeWorkflow.decode` (Sources/DICOMWeb/DataExchangeWorkflow.swift:216-217) | `DICOMFile.create` is called without `sopClassUID:` / `sopInstanceUID:`, so a reverse-converted file gets Media Storage SOP Class UID 1.2.840.10008.5.1.4.1.1.7 and a freshly generated Media Storage SOP Instance UID. Seen: a CT (0008,0016) 1.2.840.10008.5.1.4.1.1.2 with (0002,0002) .1.1.7, and (0002,0003) ≠ (0008,0018). This breaks PS3.10 Table 7.1-1 ("Uniquely identifies the SOP Class / SOP Instance associated with the Data Set"). It affects dicom-json and dicom-xml `--reverse`. High. | see the tool section | High | ✅ Closed 2026-10-01 (`55b5e6b9`): fixed by D175 with no edit to `DataExchangeWorkflow.decode` — dicom-json / dicom-xml `--reverse` now write (0002,0002)/(0002,0003) equal to the decoded (0008,0016)/(0008,0018); PS3.10 2026a Table 7.1-1; test Tests/DICOMWebTests/DataExchangeFileMetaTests.swift. |
| D113 | DICOMWeb | `DataExchangeWorkflow.decode` (DataExchangeWorkflow.swift:204-209) | The decoder runs with `fetchBulkData: false`, so an attribute that carries a BulkDataURI (JSON) or BulkData (XML) is written to the PS3.10 file as a zero-length element, with no warning (seen: the OB and OW values were lost on round trip). PS3.18 F.2.6 / PS3.19 A.1.5-2: the value is retrievable, not empty. Medium. | see the tool section | Medium | ✅ Closed 2026-10-01 (`d6baa4f7`): `DICOMJSONDecoder` / `DICOMXMLDecoder` `Configuration` gain an optional synchronous `bulkDataResolver` (defaulted init parameter, source-compatible); `DataExchangeWorkflow.decode` reads a `file:` URL / absolute-path reference into the element and reports every other one as `Warning: (gggg,eeee) BulkDataURI/BulkData <ref> could not be retrieved; … empty Value Field (PS3.18 F.2.6, PS3.19 Table A.1.5-2)`, which dicom-json / dicom-xml print on stderr; tests DataExchangeDeferredRowsTests (2: unresolved warning; file: resolved for JSON BulkDataURI and XML BulkData uri, XML uuid reported). |
| D114 | DICOMStudio |  | Workshop `CLIWorkshopViewModel.swift:1258` builds `includeEmpty` from `paramValue("include-empty") == "true"`, and `CLIWorkshopHelpers.swift:2847` / `:2920` offer only `--include-empty`. The app default is still "drop", so it now differs from the CLI default (on, PS3.18 F.2.5 / PS3.19 A.1.5-2), and it has no `--no-include-empty`. Low. | see the tool section | Low | ✅ Studio half 2026-10-05 (audit 2026-10-06, was "⏳ Open"): json / xml include-empty default and --no-include-empty in the Workshop; see DICOMSTUDIO_STANDARD_IMPLEMENTATION.md |
| D115 | DICOMWeb | `DICOMXMLEncoder` (Sources/DICOMWeb/DICOMXMLEncoder.swift:199, `where !value.isEmpty`) | An empty value of a multi-valued PN is skipped, so the numbers come out as 1, 3. `DICOMXMLDecoder` then collapses the gap and the value is lost on round trip; seen: (0010,1001) "A^B\\C^D^E^Dr^Jr" comes back with 2 values. PS3.19 Table A.1.5-2: PersonName number runs "monotonically increasing from 1 by 1". The A.1.6 schema allows an empty `<PersonName number="2"/>`. Low. | see the tool section | Low | ✅ Closed 2026-10-01 (`d6baa4f7`): `DICOMXMLEncoder` writes an empty value of a multi-valued PN as `<PersonName number="n"/>` (numbers run 1..n by 1, PS3.19 2026a Table A.1.5-2; the A.1.6 schema makes each component group optional); the existing decoder then keeps the value — (0010,1001) "A^B\\C^D^E^Dr^Jr" round-trips with 3 values; test DataExchangeDeferredRowsTests.test_D115. |
| D116 | DICOMKit | Sources/DICOMKit/Study/StudyManager.swift:235-249 (renderSummary), 289-291 (renderStats) | Labels are not PS3.6 names: "Study UID", "Patient Name", "Description" (study and series), "Number", "Series Count", "Total Instances", "Instances" | PS3.6 Table 6-1; PS3.4 C.6-2 / C.6-3 | Low | ✅ Closed 2026-10-01 (`0a7f5b57`): StudyReport summary table / stats text print the PS3.6 2026a Table 6-1 names Study Instance UID, Patient's Name, Study Description, Series Number, Series Description, Number of Study Related Series / Instances, Number of Series Related Instances (dumped from Table 6-1); test StudyEngineStandardTests |
| D117 | DICOMKit | Sources/DICOMKit/Study/StudyOrganizer.swift:113-118, 126 | `--pattern descriptive` series folder `<Series Number>_<Modality>_<Series Description>` is not unique: two series with equal values (Series Number is Type 2; absent → "0") share a folder and the second copy fails "already exists" at `<n>.dcm`. Key the folder on (or suffix it with) Series Instance UID | PS3.4 Table C.6-3 (Series Instance UID U); PS3.3 Table C.7-5a (Series Number Type 2) | Medium | ✅ Closed 2026-10-01 (`0a7f5b57`): StudyOrganizer `--pattern descriptive` appends the full Series (Study) Instance UID to a folder name shared by two series (studies); PS3.3 2026a Table C.7-5a Series Number Type 2, Series Instance UID Type 1; PS3.4 Table C.6-3 |
| D118 | DICOMKit | Sources/DICOMKit/Study/StudyManager.swift:165-166; StudyOrganizer.swift:77 | Files without Series Instance UID / SOP Instance UID (Type 1) are merged under "UNKNOWN"/"UNKNOWN_SERIES" instead of being reported | PS3.3 Table C.7-5a; C.12-1 | Low | ✅ Closed 2026-10-01 (`0a7f5b57`): new `StudyScanner.scan(at:)` → `StudyScanResult(studies, skipped: [StudySkippedFile])`; files without Study/Series/SOP Instance UID (Type 1, PS3.3 2026a Tables C.7-3, C.7-5a, C.12-1) are reported (dicom-study: `warning: skipped …` on stderr) instead of merged under "UNKNOWN"; StudyOrganizer logs and skips instead of UNKNOWN_SERIES |
| D119 | DICOMKit | Sources/DICOMKit/Study/StudyManager.swift:1, StudyOrganizer.swift:1 | Markers say "carries no DICOM-standard data", but the files read 13 attributes, group by the Q/R unique keys and build names from 6 attributes; the marker claim should name what was compared | DICOMCORE method, "The marker" | Low | ✅ Closed 2026-10-01 (`0a7f5b57`): StudyManager.swift / StudyOrganizer.swift markers name the 13 attributes read, the Q/R unique keys (PS3.4 Tables C.6-2..C.6-4), the 11 PS3.6 labels and the 6 folder-name attributes |
| D120 | DICOMKit | Sources/DICOMKit/Archive/ArchiveStore.swift:83-87 | `wildcardMatch` upper-cases pattern and value for every key; Patient ID (LO) wild cards must be case-sensitive (now documented as tool-specific in help and README) | PS3.4 C.2.2.2.4 | Low | ✅ Closed 2026-10-01 (`2f70f6eb`): new public `ArchiveMatching`; Patient ID (LO) and Modality (CS) wild cards / single values are case-sensitive, Patient's Name (PN) case-insensitive — PS3.4 2026a C.2.2.2.4 "case sensitive, except for Attributes with a PN VR", C.2.2.2.1.1; dicom-archive help/README no longer call it tool-specific |
| D121 | DICOMKit | ArchiveStore.swift:461, 466, 677 | No List of UID Matching or DA Range Matching for Study Instance UID / Study Date (the CLI now warns) | PS3.4 C.2.2.2.2, C.2.2.2.5.1 | Low | ✅ Closed 2026-10-01 (`2f70f6eb`): List of UID Matching for query `--study-uid` and export `--study-uid` / `--series-uid` (PS3.4 C.2.2.2.2); DA Range Matching `d1-d2`, `-d1`, `d1-` inclusive for `--study-date` (C.2.2.2.5.1); the d46affe exact-match warnings are removed, only a Study Date that is neither DA nor DA range is warned |
| D122 | DICOMKit | ArchiveStore.swift:416-423 (makeStudy), 496, 527, 548 | The study record's `modality` is the first imported instance's Modality and is shown as the study's Modality; a multi-modality study (e.g. PET/CT, MR + SR) is misreported. Should be Modalities in Study (0008,0061): the distinct series Modality values, recomputed on import | PS3.4 Tables C.6-2 / C.6-5; PS3.6 (0008,0061) CS 1-n | Medium | ✅ Closed 2026-10-01 (`2f70f6eb`): every study surface uses Modalities in Study (0008,0061), the distinct series Modality values computed from all series (`modalitiesInStudy`); `ArchiveStudy.modality` (first imported instance) is `@available(*, deprecated)`, index key `modality` kept; PS3.4 Tables C.6-2 / C.6-5, PS3.6 (0008,0061) CS 1-n |
| D123 | DICOMKit | ArchiveStore.swift:484, 544-550, 612, 887-893 | Labels "Patient Name", "Description", "Series", "Images", "Studies" are not PS3.6 names (Patient's Name, Study Description, Number of Study Related Series / Instances, Number of Patient Related Studies); "Images" counts every instance; "SOP Classes:" prints UIDs without their Table A-1 names | PS3.6 Table 6-1, Table A-1 | Low | ✅ Closed 2026-10-01 (`2f70f6eb`): query table / text print Patient's Name, Patient ID, Study Instance UID, Study Date, Study Description, Modalities in Study, Number of Study Related Series / Instances; list table Number of Patient Related Studies / Series / Instances (PS3.6 2026a Table 6-1); "Images" removed; stats prints each SOP Class UID with its PS3.6 Table A-1 name |
| D124 | DICOMKit | ArchiveStore.swift:289-290, 425 | Patients keyed on Patient ID alone: Issuer of Patient ID (0010,0021) ignored, and every file with an empty/absent Patient ID (Type 2) merges into one "UNKNOWN" patient whose Patient's Name is the first file's | PS3.4 Tables C.6-1 / C.6-5 (Issuer of Patient ID); PS3.3 Table C.7-1 | Low | ✅ Closed 2026-10-01 (`2f70f6eb`): patients keyed on Patient ID + Issuer of Patient ID (0010,0021) (new `ArchivePatient.issuerOfPatientID`, index key `issuerOfPatientID`, query JSON `IssuerOfPatientID`, text/tree line); empty/absent Patient ID (Type 2, PS3.3 Table C.7-1) is also keyed on Patient's Name; PS3.4 Tables C.6-1 / C.6-5 |
| D125 | DICOMKit | ArchiveStore.swift:1 | Marker says "carries no DICOM-standard data (SQLite-backed index)": the index is JSON, and the file implements C-FIND-like matching and the Q/R hierarchy; the marker should name what was compared | DICOMCORE method, "The marker" | Low | ✅ Closed 2026-10-01 (`2f70f6eb`): ArchiveStore.swift marker names the JSON index, the C.2.2.2 matching, the C.6-1..C.6-4 hierarchy with the issuer key, Modalities in Study and the PS3.6 / Table A-1 labels |
| D126 | DICOMKit | Sources/DICOMKit/ImageExport/DICOMImageExporter.swift:84-111 | `--exif-fields PatientID` is read (getDICOMFieldValue) but has no EXIF mapping and is dropped silently; Study Date (DA YYYYMMDD) is written unconverted into Exif DateTimeOriginal ("YYYY:MM:DD HH:MM:SS"); Modality goes to an Exif "Software" key | PS3.5 Table 6.2-1 DA (DICOM side only) | Low | ✅ Closed 2026-10-01 (`46e453ee`): `DICOMImageExporter` converts Study Date (DA, PS3.5 2026a Table 6.2-1 "YYYYMMDD") with Study Time (TM) to Exif DateTimeOriginal "YYYY:MM:DD HH:MM:SS" (blank time without Study Time; a value that is not a DA is not written); Patient ID, Modality and Series Description go to Exif UserComment as `<PS3.6 keyword>=<value>` (Patient ID was read and dropped, Modality went to an Exif "Software" key); new `supportedEXIFFields`, `unsupportedEXIFFields(_:)`, `exifDateTime(fromDA:tm:)`; dicom-export warns for a keyword it cannot embed; help / README list PatientID (ExportEXIFFieldsTests, ExportRoundTripTests) |
| D127 | DICOMStudio | `CLIWorkshopViewModel.swift:4410, 4557-4562, 4620-4628` | The CLI Workshop still copies the contact-sheet and animate render paths that dicom-export now routes through the shared window/rescale path | see the dicom-export section | Low | ✅ Studio half 2026-10-05 (audit 2026-10-06, was "⏳ Open (DICOMStudio)"): export executor renders through DICOMImageExporter.renderFrameForExport (PS3.4 N.2); see DICOMSTUDIO_STANDARD_IMPLEMENTATION.md |
| D128 | DICOMKit | `Sources/DICOMKit/DICOMDIRDumpFormatter.swift:60-63, 158-161, 45, 141` | `--verbose` record attributes printed as bare tags, no PS3.6 attribute names; "Consistent" label instead of File-set Consistency Flag | PS3.6 Table 6-1; PS3.3 F.3-3 | Low | ✅ Closed 2026-10-01 (`c0943cfc`): `DICOMDIRDumpFormatter` `--verbose` record keys now print as `(gggg,eeee) <PS3.6 2026a Attribute Name>` (via DICOMDictionary) and are sorted in the text format too. "Consistent: true/Yes" is replaced by `File-set Consistency Flag: 0000H (no known inconsistencies)` (PS3.3 2026a Table F.3-3 Enumerated Value; FFFFH is shown as the retired value) in tree, text and the `validate` report. JSON keys are unchanged. |
| D129 | DICOMKit | `Sources/DICOMKit/DICOMDIRWriter.swift:346-395` (`DICOMDirectory.Builder.addFile`) | `DirectoryRecord` is a struct: when the series (or study) already exists, the copy that receives the new IMAGE (or SERIES) is never written back, so only the first image of each series and the first series of each study are indexed. Fixture: 2 distinct SOP Instances in one series → "Files processed: 3/3 … Images: 1". `DcmdirRoundTripTests` works around it with one patient per file | PS3.3 F.4, Table F.4-1, F.5.3/F.5.4 | High: DICOMDIR silently omits instances | ✅ Closed 2026-10-01 (`c0943cfc`): the Builder keeps PATIENT records in an ordered array and mutates STUDY/SERIES/IMAGE children in place by index. Every instance now gets its own IMAGE record (PS3.3 2026a F.4, Table F.4-1), and record order follows first addition, not dictionary order. A second file with an already indexed SOP Instance UID is refused (`duplicateSOPInstance`, PS3.3 Table F.3-3 (0004,1511)). `DcmdirRoundTripTests` no longer needs one patient per file. Every instance still gets an IMAGE record whatever its SOP Class (D230). |
| D130 | DICOMCore | `Sources/DICOMCore/DICOMDirectory.swift:619-630` | `validate(checkFileExistence:)` is a placeholder (only rejects an empty path) — CLI now checks on disk | PS3.10 8.6 | Medium | ✅ Closed 2026-10-01 (`b8425965`): `DICOMDirectory.validate(checkFileExistence:fileSetRoot:)` resolves every Referenced File ID (0004,1500) against the File-set root (PS3.10 2026a 8.6: File IDs "relative to this directory node"; "The DICOMDIR shall not reference Files outside of the File-set") and throws `missingReferencedFile(<File ID>)` for a missing file, a directory or a "."/".." component; without a root behaviour is unchanged. dicom-dcmdir keeps its FileSetRules on-disk check (it reports every missing File ID, not the first) — left as is |
| D131 | DICOMKit | `Sources/DICOMKit/DICOMDIRWorkflow.swift:166-172` | FSC writes the raw relative path as File ID (lower case, `.dcm`, >8 chars); an FSC should assign conformant File IDs | PS3.10 8.2, 8.5 | Medium | ✅ Closed 2026-10-01 (`c0943cfc`): `addFile` refuses a Referenced File ID that is not 1-8 components of 1-8 characters A-Z 0-9 _ (PS3.10 2026a 8.2, 8.5); this is the same rule `dicom-dcmdir validate` applies since a45fd45. `DICOMDIRWorkflow` lists every refused file with its reason (`CreateResult/UpdateResult.failures`, also in the shared summary). New `buildDirectory(..., copyingInto:)` and `dicom-dcmdir create --copy-to <folder>` copy the files byte for byte into a new File-set under assigned File IDs `DICOM\PTnnnnnn\STnnnnnn\SEnnnnnn\IMnnnnnn` and write `<folder>/DICOMDIR`. `create` exits 1 and writes nothing when every file is refused (PS3.11 D.3.3). The CLI's old "File IDs do not conform" warning was removed because the engine now refuses those IDs. |
| D132 | DICOMStudio | Workshop dcmdir executor | lacks the CLI's new validate rules and File-set ID default (parity) | PS3.10 8.x | Low | ✅ Studio half 2026-10-05 (audit 2026-10-06, was "⏳ Open"): dcmdir executor WorkshopFileSetRules mirrors the CLI FileSetRules; see DICOMSTUDIO_STANDARD_IMPLEMENTATION.md |
| D133 | DICOMKit | `UIDManager.swift:137-140, 155-176` | "Must have at least 2 components" is not a PS3.5 9.1 rule; messages don't cite 9.1; `validateFileUIDs` checks top-level elements only | PS3.5 9.1 | Low | ✅ Closed 2026-10-01 (`5c921abf`): `validateUID` drops "Must have at least 2 components", which is not in PS3.5 2026a 9.1 (a one-component UID is valid). Every message now cites "(PS3.5 9.1)". `validateFileUIDs` checks every value of every UI element of the File Meta and of all sequence items; it used to check top-level data set elements only. |
| D134 | DICOMKit | `UIDManager.swift:317-330` (`uidTypeDescription`) | "Well-Known UID" / "Application Context" / folded "DICOM UIDs as a Coding Scheme" differ from Table A-1 UID Type (21 UIDs) | PS3.6 Table A-1 | Low (JSON value change → P-UID-TYPE) | ✅ Closed 2026-10-01, `72483003` (P-UID-TYPE: PS3.6 Table A-1 UID Type) |
| D135 | DICOMKit | `Sources/DICOMKit/UIDManagement/UIDManager.swift:213` (`regenerateData`), `:289` (preview) | walks `dataSet.allElements` (top level only): Referenced SOP Instance UID (0008,1155) in Referenced / Source Image Sequence kept the OLD UID after regenerating both files → references dangle; same for (3006,0024) etc. | PS3.15 Table E.1-1 (0008,1155) U, (3006,0024) U | High | ✅ Closed 2026-10-01 (`5c921abf`): `regenerateData` and the dry-run preview walk every sequence item. Referenced SOP Instance UID (0008,1155) in Referenced/Source Image Sequence and Referenced Frame of Reference UID (3006,0024) now follow the new UID of the instance they reference (PS3.15 2026a Table E.1-1, U). The same old UID always gets the same new UID within a file, and also across files when `maintainRelationships` is set (shared map; the CLI sets it for more than one input). Nested values are named by path, e.g. `(0008,1140)>(0008,1155)`. |
| D136 | DICOMKit | `UIDManager.swift:407-413` (`UIDConsole.lookupNotFoundLine`, `unknownTypeFilterLine`) | not-found text says "Transfer Syntax or SOP Class"; filter list has 2 values (CLI no longer uses it; Studio does) | PS3.6 Table A-1 | Low | ✅ Closed 2026-10-01 (`5c921abf`): `UIDConsole.lookupNotFoundLine` now prints "UID not found in the DICOM UID registry (PS3.6 Table A-1): <uid>". `unknownTypeFilterLine` lists all 11 UID Type filters of PS3.6 2026a Table A-1 ("DICOM UIDs as a Coding Scheme" is folded into coding-scheme). The filter list is now shared as `UIDConsole.lookupTypeFilters` / `entries(forTypeFilter:)`, and dicom-uid's `LookupTypeFilter` delegates to it. |
| D137 | DICOMKit | `UIDManager.swift:251-254` | `DICOMFile.create(dataSet:sopClassUID:)` without `sopInstanceUID:` writes a fresh Media Storage SOP Instance UID (0002,0003) ≠ the new SOP Instance UID (fixture: …511.4.3.1790835791361393… vs …511.4.1790835791360376…) | PS3.10 Table 7.1-1 (0002,0003) "Uniquely identifies the SOP Instance associated with the Data Set"; PS3.15 E.1-1 U | High | ✅ Closed 2026-10-01 (`55b5e6b9`): fixed by D175 with no edit to `UIDManager.regenerateData` — (0002,0003) now equals the regenerated (0008,0018); PS3.10 2026a Table 7.1-1, PS3.15 2026a Table E.1-1 (0002,0003) U; test FileMetaMediaStorageUIDTests.test_uidManager_regenerate_fileMetaFollowsNewSOPInstanceUID. |
| D138 | DICOMKit | `UIDManager.swift:219-222` | criterion "value not in Table A-1" also replaces UIDs that are not instance identifiers: Coding Scheme UID (0008,010C) 2.16.840.1.113883.6.96 was replaced in the fixture; also Context Group Extension Creator UID, Mapping Resource UID, private SOP Class UIDs, Referenced SOP Class UID values not in A-1 (37 UI attributes not in E.1-1) | PS3.15 Table E.1-1 (U set) | Medium | ✅ Closed 2026-10-01 (`5c921abf`): regeneration replaces only `UIDManager.regeneratedUIDTags`. These are the 57 PS3.15 2026a Table E.1-1 rows whose VR is UI (action U; D for Annotation Group UID), dumped by script with PS3.6 2026a VRs and cross-checked in the test against the generated E.1-1 table. A value that is a PS3.6 Table A-1 UID is never replaced. Coding Scheme UID (0008,010C), Context Group Extension Creator UID, Mapping Resource UID, SOP Class / Referenced SOP Class UIDs and private UI attributes are kept. `UIDManager.uidTags` (3 tags) is deprecated, not removed. |
| D139 | DICOMCore | `Sources/DICOMCore/UIDGenerator.swift:84-88, 113-116, 75-81` | force-unwrap crash on a malformed root; truncation to 64 cuts the unique suffix (identical UIDs). CLI guards now | PS3.5 9.1, 9.2.2 | Medium | ✅ Closed 2026-10-01 (`b8425965`): `UIDGenerator.generate()` / `generate(type:)` no longer force-unwrap or truncate: a root that breaks PS3.5 2026a 9.1 or leaves no room for the suffix within 64 characters yields a UUID derived UID ("2.25." + UUID as decimal, PS3.5 B.2); new `UIDGenerator.isUsableRoot(_:)`, `UIDGenerator.uuidDerivedUID(_:)` (X.667 example 2.25.329800735698586629295641978511506172918 pinned). dicom-uid's own root guard and UUIDDerivedUID left in place (they give the CLI its error text) |
| D140 | DICOMKit | `DICOMValidator.swift:825` | GSPS/PCPS: Content Creator's Name (0070,0084) required as Type 2 "[C.11.10 … (Table 10-12)]"; in 2026a it is Type 3 in Content Creator Macro Table 10.9.3-1, included by Table 10-12 → false error on every presentation state without it | PS3.3 Tables 10-12, 10.9.3-1, C.11.10-1 | Medium | ✅ Closed 2026-10-01 (`eddc0b49`): Content Creator's Name (0070,0084) removed from the GSPS/PCPS Type 2 list — PS3.3 2026a Table 10.9.3-1 (Content Creator Macro, included by Table 10-12, included by C.11.10-1) gives Type 3 (tables dumped by script) |
| D141 | DICOMKit | `DICOMValidator.swift` IOD validators' `iod` names | message prefixes "CR Image Storage", "US Image Storage", "GSPS", "Pseudo-Color PS", "Key Object Selection Document", "Structured Report" are not PS3.6 Table A-1 names | PS3.6 Table A-1 | Low | ✅ Closed 2026-10-01 (`eddc0b49`): IOD prefixes are PS3.6 2026a Table A-1 names: Computed Radiography Image Storage, Ultrasound Image Storage, Grayscale Softcopy Presentation State Storage, Pseudo-Color Softcopy Presentation State Storage, Key Object Selection Document Storage, and the SR SOP Class's own name (e.g. Basic Text SR Storage); "Structured Report Document" (PS3.3 A.35) only when the data set has no SR SOP Class |
| D142 | DICOMKit | `Sources/DICOMKit/Validation/DICOMValidator.swift:148-240` | level 2 checks no VR maximum length / repertoire except DA, TM, UI and CS lowercase (warning only, though outside the CS repertoire), and no VM: LO 70, SH 20, CS 20, DS 19, IS 13, PN 70 all pass; "Person Name has more than 3 components" means component groups; DA/TM errors reported twice (validateValueFormat + validateDatesAndTimes) | PS3.5 Table 6.2-1, 6.2.1; PS3.6 Table 6-1 VM | Medium | ✅ Closed 2026-10-01 (`eddc0b49`): level 2 checks, as errors, PS3.5 2026a Table 6.2-1 maximum/fixed lengths (AE 16, AS 4, CS 16, DA 8, DS 16, DT 26, IS 12, LO 64, LT 10240, SH 16, ST 1024, TM 14, UI 64) and character repertoires of 16 VRs, AS/DS/IS forms (IS in -2^31..2^31-1), PS3.5 6.2.1 PN (≤3 component groups, ≤4 "^", 64 chars per group), and the PS3.6 Table 6-1 VM column (PS3.5 6.4); lowercase CS is now an error; DA/TM/UI judged per Value and reported once; dicom-validate --level help / README updated |
| D143 | DICOMKit | `DICOMValidator.swift:894` | KOS/SR root Concept Name Code Sequence printed as "Type 1 … (Table C.17-5, Root Content Item)"; Table C.17-5 gives Type 1C (condition) | PS3.3 Table C.17-5; PS3.5 7.4.2 | Low | ✅ Closed 2026-10-01 (`eddc0b49`): root Concept Name Code Sequence reported as "Missing Type 1C … (required for the Root Content Item) [PS3.3 C.17.3 SR Document Content (Table C.17-5); PS3.5 7.4.2]" (Table C.17-5 dumped: 1C, "or this is the Root Content Item") |
| D144 | DICOMKit | Sources/DICOMKit/HexDumper.swift:186 | `buildTagPositionMap` always skips 132 bytes when the data is longer than 132, without checking "DICM" at 128 and regardless of `startOffset`: with `--offset` > 0 (and the Workshop equivalent) `--annotate` / `--highlight` are lost or misplaced; a file without preamble (`--force`) is misannotated | PS3.10 7.1, Table 7.1-1 | medium | ✅ Closed 2026-10-01 (`d812b918`): HexDumper skips 132 bytes only when "DICM" is at bytes 128-131 (a --force file without preamble is walked from byte 0); new `HexDumper.dump(fileData:startOffset:length:dicomFile:highlightTag:)` walks the whole file so --offset keeps --annotate/--highlight on their bytes (an element starting before the range is still highlighted); dicom-dump uses it; tests pin offsets 0xC8.. and a no-preamble file; PS3.10 2026a 7.1, Table 7.1-1 |
| D145 | DICOMKit | Sources/DICOMKit/HexDumper.swift:203-207 | (FFFE,xxxx) is stepped over with no position entry, so Item / Item Delimitation Item / Sequence Delimitation Item are never annotated; defined-length Items are skipped whole (their elements are not annotated) while undefined-length Items are descended | PS3.5 7.5; PS3.6 Table 6-1 | low | ✅ Closed 2026-10-01 (`d812b918`): (FFFE,E000) Item, (FFFE,E00D) ItemDelimitationItem, (FFFE,E0DD) SequenceDelimitationItem annotated with their PS3.6 2026a Table 6-1 keywords and no VR; defined-length SQs and Items descended (their elements annotated); encapsulated Pixel Data fragments stepped over; PS3.5 2026a 7.5, A.4 |
| D146 | DICOMKit | Sources/DICOMKit/MetadataPresenter.swift:117,191,214; HexDumper.swift:44; TagEditing/TagEditor.swift:147 | Private Creator Data Elements (gggg,0010-00FF) print "Unknown" / no name | PS3.5 7.8.1 | low | ✅ Closed 2026-10-01 (`d812b918`, `d032c4d7`): (gggg,0010-00FF), gggg odd, named "Private Creator" in MetadataPresenter (text/JSON/CSV), HexDumper (--tag header, annotations), TagEditor change lines and ComparisonReport (shared DICOMKit `AttributeNames`); PS3.5 2026a 7.8.1 |
| D147 | DICOMKit | Sources/DICOMKit/MetadataPresenter.swift:76-92, 142-156 | `--statistics` prints the Transfer Syntax UID and SOP Class UID without their Table A-1 names (UIDDictionary has them) | PS3.6 Table A-1 | low | ✅ Closed 2026-10-01 (`d812b918`): --statistics prints `Transfer Syntax: <uid> (<Table A-1 name>)` and the SOP Class likewise; JSON keeps transferSyntax/sopClass and adds transferSyntaxName/sopClassName; PS3.6 2026a Table A-1 |
| D148 | DICOMKit | Sources/DICOMKit/MetadataPresenter.swift:108-112, 181-185, 250-253 | the tag filter matches the PS3.6 name or tag text but never the keyword (DICOMStudio's Workshop still affected; the CLI now adds the keyword's tag) | PS3.6 Table 6-1 keywords | medium | ✅ Closed 2026-10-01 (`d812b918`): MetadataPresenter filters match the PS3.6 keyword exactly (plus name/tag substring); dicom-info's keyword workaround (`DICOMInfo.filterTerms`) removed, so the Workshop gets the same matching; PS3.6 2026a Table 6-1/7-1 |
| D149 | DICOMKit | Sources/DICOMKit/MetadataPresenter.swift:195-197 | JSON `value` is omitted for binary VRs (US, UL, FL, FD, AT, …) though text/CSV render them | PS3.5 Table 6.2-1 | low | ✅ Closed 2026-10-01 (`d812b918`): JSON `value` present for every element: non-character VRs (US/SS/UL/SL/FL/FD/AT, Other VRs) carry the text/CSV rendering. The JSON is the tool's own model (tag/name/vr/value), not PS3.18 Annex F, so InlineBinary/BulkDataURI do not apply; PS3.5 2026a Table 6.2-1 |
| D150 | DICOMKit | Sources/DICOMKit/TagEditing/TagEditor.swift:124-139 (sets), 83-95 / 110-121 | `applyChanges` writes `setString` under the existing-or-first dictionary VR for any VR (binary VRs get text bytes: Rows=512 → US "512 "), applies no Table 6.2-1 limits, and puts group 0002 into the Data Set (unreadable file); deletes/copies of group 0002 are not refused. The CLI now runs `--set` and the refusals itself (Sources/dicom-tags/TagEditRules.swift); DICOMStudio's Workshop still uses the engine — move these rules into TagEditor | PS3.5 Table 6.2-1; PS3.10 7.1; PS3.6 Table 6-1 | high | ✅ Closed 2026-10-01 (`d812b918`): TagEditRules/TagEditRefusal moved from dicom-tags (b091aa5) into DICOMKit (public); `TagEditor.applyChanges` writes the PS3.6 dictionary VR (US etc. binary), refuses Table 6.2-1 violations, group 0002, (FFFE,xxxx) and groups 0001/0003/0005/0007/FFFF with a "(refused: …)" line; new `applyCheckedChanges(…) throws` refuses the whole edit before any change; dicom-tags calls it (its own checkDataSetEdits/applySets removed); PS3.5 2026a Table 6.2-1, 7.5, 7.8.1; PS3.10 7.1 |
| D151 | DICOMCore | Sources/DICOMCore/Tag.swift:29 | `isPrivate` = any odd group; PS3.5 7.1 excludes 0001, 0003, 0005, 0007, FFFF from Private Data Elements (7.8.1: those groups shall not be used) | PS3.5 2026a 7.1, 7.8.1 | low | ✅ Closed 2026-10-01 (`b8425965`): `Tag.isPrivate` = odd group not in {0001, 0003, 0005, 0007, FFFF} (PS3.5 2026a 7.1: "Private Data Elements have an odd Group Number that is not 0001, 0003, 0005, 0007, or FFFF"; 7.8.1: "(0001,xxxx), (0003,xxxx), (0005,xxxx), (0007,xxxx) and (FFFF,xxxx) shall not be used"); new `Tag.isOddGroup` (old parity test) and `Tag.unusableOddGroups`. One-line DICOMKit follow-ups: `ConfidentialityEngine` (resolveAction) and `TagEditor` delete-private pass use `isOddGroup`, so elements in those groups are still removed. `Anonymizer.scanForPHILeaks` (warnings only; file being edited by another agent) not changed |
| D152 | DICOMKit | Sources/DICOMKit/Comparison/DICOMComparer.swift:66, 141-158 | `ignorePrivate` applies only to top-level elements; private elements inside sequence items still make the parent SQ differ | PS3.5 2026a 7.8 | low | ✅ Closed 2026-10-01 (`d812b918`): `ignorePrivate` filters Private Data Elements (and Private Creators) inside Sequence Items at every depth; dicom-diff help/README updated; PS3.5 2026a 7.8 |
| D153 | DICOMKit | Sources/DICOMKit/Comparison/DICOMComparer.swift:160-199; ComparisonReport.swift:56-60 | Pixel Data compared byte by byte: `--tolerance`, max/mean and "Different pixels" are per byte, not per sample (16-bit pixel cells, PS3.5 8.1.1); encapsulated data compared as compressed bytes (PS3.5 8.2, A.4) | PS3.5 2026a 8.1.1, 8.2 | medium | ✅ Closed 2026-10-01 (`d812b918`): Pixel Data decoded (`DICOMFile.pixelData()`, compressed too) and compared per Pixel Sample Value (Bits Allocated 1/8/16/32, Bits Stored, High Bit, Pixel Representation sign extension), in frame/pixel/sample order whatever the Planar Configuration; --tolerance/max/mean in sample values, "Different pixels" = pixels with a differing sample; undecodable data falls back to the byte comparison; PS3.5 2026a 8.1.1, 8.2; PS3.3 C.7.6.3.1.3 |
| D154 | DICOMStudio | Sources/DICOMStudio/Components/CLIWorkshopHelpers.swift:2520 | Workshop help for dicom-split `--frames` ("Frame selection (ranges/list)") does not say the values are 0-based indices | PS3.3 2026a C.7.6.16.1.2 | low | ✅ Studio half 2026-10-05 (audit 2026-10-06, was "⏳ Open"): split --frames deprecated help and --frame-numbers in the Workshop; see DICOMSTUDIO_STANDARD_IMPLEMENTATION.md |
| D155 | DICOMNetwork | `StorageSCP.swift:47` `StorageSCPConfiguration.defaultImplementationClassUID`; `StorageService.swift` `StorageConfiguration.defaultImplementationClassUID` ("1.2.826.0.1.3680043.9.7433.1.1") | Default SCP/SCU Implementation Class UIDs are not under DICOMKit's UID root | PS3.7 D.3.3.2; PS3.5 9 | Low | ✅ Closed 2026-10-01 (`22e39bd8`): all 13 DICOMNetwork `defaultImplementationClassUID`s are the new `DICOMNetworkImplementation.classUID` = `DICOMFile.implementationClassUID` (1.2.826.0.1.3680043.10.511.3.0.5.0; DICOMNetwork cannot import DICOMKit, a test pins the equality), PS3.7 2026a D.3.3.2, PS3.5 9.2.2; dicom-retrieve's C-GET File Meta (0002,0012) literal replaced too; dicom-server's override kept (same value). Studio's CLIWorkshopViewModel:81 literal remains (Studio follow-up) |
| D156 | DICOMNetwork | `StorageService.swift` `DICOMStorageService.store(...)` | No way to set Move Originator AE Title / Message ID (0000,1030/1031) on the C-STORE-RQ, so a C-MOVE SCP built on it cannot identify the originating C-MOVE in its sub-operations | PS3.7 9.1.1.1.6 / 9.1.1.1.7 | Low | ✅ Closed 2026-10-01 (`22e39bd8`): `StorageConfiguration.moveOriginatorAETitle` / `moveOriginatorMessageID` + `withMoveOriginator(aeTitle:messageID:)` write (0000,1030)/(0000,1031) on the C-STORE-RQ (single and batch store; only as a pair), PS3.7 2026a 9.1.1.1.6 / 9.1.1.1.7; dicom-server's C-MOVE sub-operations now send the C-MOVE's calling AE Title and Message ID |
| D157 | DICOMKit | Sources/DICOMKit/Anonymization/ConfidentialityEngine.swift:239 | Modified Dates Option shifts only DA; DT (60 rows), TM (52) and 3 other C cells are zeroed while 113107 is recorded; E.3.6 requires dates and times modified preserving temporal relationships | PS3.15 2026a E.3.6 | Medium | ✅ Closed 2026-10-01 (`31536bad`): Modified Dates shifts DA and the DT date part (time, UTC offset kept) by the whole-day offset in a UTC Gregorian calendar; TM kept (time of day of a date shifted by whole days — the date/time pair is modified, every interval kept, as E.3.6 asks; manner stated in the dicom-anon README); Timezone Offset From UTC and the 2 OB timestamps get their Basic action; was: DT/TM/3 others zeroed; PS3.15 2026a E.3.6 |
| D158 | DICOMKit | Sources/DICOMKit/Anonymization/ConfidentialityEngine.swift:181 | Clean Descriptors Option keeps every C attribute verbatim (140 rows on the fixture, e.g. Study Comments "… John Doe") yet records 113105 Clean Descriptors Option; C requires values "known not to contain identifying information" | PS3.15 2026a E.3.5, Table E.1-1a (C) | High | ✅ Closed 2026-10-01 (`31536bad`): C now cleans: from each kept text value (and the text inside a C sequence) every value the profile removes/replaces elsewhere in the data set (PN components and whole names, IDs, addresses, institution/device names, ages, UIDs, dates in 6 forms) is removed whole-word case-insensitively, plus a capitalised word after Dr/Mr/Mrs/Ms/Miss/Prof; non-text C → zero-length; 113105 therefore recorded only with a real cleaning; manner documented (help, README); PS3.15 2026a E.3.5, Table E.1-1a |
| D159 | DICOMKit | Sources/DICOMKit/Anonymization/ConfidentialityProfile.swift:49 | `Options` has no Retain Safe Private, Clean Structured Content, Clean Graphics, Clean Recognizable Visual Features; the generated cleanStructuredContent/cleanGraphics columns are unused by `action(for:options:)`; the CLI cannot offer these four Options | PS3.15 2026a E.3.2, E.3.3, E.3.4, E.3.10; CID 7050 113102-113104, 113111 | Low | ✅ Closed 2026-10-01 (`5aeca208`, `dfe30cc9`): all four Options now offered. Retain Safe Private (113111; Table E.3.10-1, 479 rows) and Clean Graphics (113103) as before; Clean Structured Content (113104; PS3.15 2026a E.3.4): `Options.cleanStructuredContent` applies the 4 Table E.1-1 Clean Struct. Cont. "C" rows and gives every Content Item of Content Sequence (0040,A730), Acquisition Context Sequence (0040,0555) and Specimen Preparation Step Content Item Sequence (0040,0612) the Table E.3.4-1 action of its Concept Name + Value Type under the Options in force (X item and children removed, D dummy value / mapped UID, K value kept, C text cleaned / date shifted); 211 rows generated into ConfidentialityProfileStructuredContent.swift by Scripts/generate_confidentiality_profile.py (`--check`), plus the retired SRT / SNM3 / 99SDM SNOMED IDs of its 11 SCT rows from PS3.16 2026a Table O-1 (244 keys); 113104 recorded only with the Option. Clean Recognizable Visual Features (113102; E.3.2 "may require intervention of or approval by a human operator"): operator-directed `PixelRedactor.redactRecognizableVisualFeatures(fileData:regions:fillValue:)` blanks the given regions on every frame, removes Icon Image Sequence, sets Recognizable Visual Features (0028,0302) = NO and records 113102 only then (no region → `PixelRedactionError.noRecognizableVisualFeatureRegions`); the engine keeps the record and names it in (0012,0063). dicom-anon `--clean-structured-content`, `--clean-recognizable-visual-features` (needs `--redact-region`, exit 1 citing PS3.15 E.3.2 without; its regions then do not imply `--clean-pixel-data`). Judging that the regions prevent recognition (incl. a 3D reconstruction of the series; one rectangle set applies to every frame) is the operator's, as E.3.2 allows; no automatic face/surface detection. Tests: DICOMKitTests ConfidentialityOptionsTests (+6), PixelRedactionTests (+2); dicom_anonTests AnonOptionContractTests (+4); Table E.1-1 tests unchanged and passing. |
| D160 | DICOMKit | Sources/DICOMKit/Anonymization/ConfidentialityEngine.swift:337 | After pixel cleaning (113101 recorded by PixelRedactor), (0012,0063) omits "Clean Pixel Data Option" and the 113100 item follows 113101 in (0012,0064) | PS3.15 2026a E.1.1; PS3.3 2026a Table C.7-1 | Low | ✅ Closed 2026-10-01 (`31536bad`): 113100 is the first Item of (0012,0064) with an earlier pass's 113101 after it; (0012,0063) has one value per Item ("Clean Pixel Data Option" named); PS3.15 2026a E.1.1; PS3.3 Table C.7-1 |
| D161 | DICOMKit | Sources/DICOMKit/Anonymization/ConfidentialityEngine.swift:310 | `recordMethod` never writes Longitudinal Temporal Information Modified (0028,0303): REMOVED without a dates Option, UNMODIFIED with Full Dates, MODIFIED with Modified Dates | PS3.15 2026a E.2, E.3.6 | Medium | ✅ Closed 2026-10-01 (`31536bad`): (0028,0303) CS written: REMOVED without a Retain Longitudinal Temporal Information Option, UNMODIFIED with Full Dates, MODIFIED with Modified Dates; PS3.15 2026a E.2, E.3.6; PS3.3 Table C.7-1 Enumerated Values |
| D162 | DICOMKit | Sources/DICOMKit/Anonymization/Anonymizer.swift:416 | `deidentify` (and `anonymize`, :222) keep the source File Meta: Media Storage SOP Instance UID (0002,0003) keeps the original UID while (0008,0018) is replaced (U); dicom-anon now syncs it at write, other callers (Studio) do not | PS3.10 2026a 7.1; PS3.15 2026a Table E.1-1 (0002,0003) U | High | ✅ Closed 2026-10-01 (`55b5e6b9`): `Anonymizer.anonymize` (:222) and `Anonymizer.deidentify` (:416) keep the source File Meta but pass it through `DICOMFile.synchronizingMediaStorageUIDs()`, so (0002,0003) carries the replaced (0008,0018) for every caller (DICOMStudio included); PS3.15 2026a Table E.1-1 (0002,0003) U, PS3.10 2026a Table 7.1-1; tests FileMetaMediaStorageUIDTests.test_anonymizer_* (2). |
| D163 | DICOMKit | Sources/DICOMKit/Anonymization/Anonymizer.swift:458 | `parseFlexibleTag` knows 11 hard-coded keywords and its lowercased lookup can never match (keys are PascalCase); dicom-anon now falls back to DataElementDictionary, the Studio Workshop executor does not | PS3.6 2026a Table 6-1 | Low | ✅ Closed 2026-10-01 (`31536bad`): `Anonymizer.parseFlexibleTag` resolves any PS3.6 keyword exactly via DataElementDictionary (11 hard-coded keywords and the dead lowercased lookup removed); dicom-anon's own fallback removed; PS3.6 2026a Table 6-1 |
| D164 | DICOMKit | Sources/DICOMKit/Anonymization/Anonymizer.swift:305 | Legacy `shiftAllDates`/`regenerateAllUIDs` (:321) ignore `preserveTags`: `--keep StudyDate --shift-dates N` still shifts it | (legacy behaviour, no PS3.15 clause) | Low | ✅ Closed 2026-10-01 (`31536bad`): legacy `shiftAllDates`/`regenerateAllUIDs` skip `preserveTags`, so `--keep StudyDate --shift-dates N` keeps Study Date (legacy behaviour, no PS3.15 clause) |
| D165 | DICOMKit | Sources/DICOMKit/SecondaryCapture/ImageConverter.swift:139 | `DICOMFile.create(dataSet:transferSyntaxUID:)` is called without `sopInstanceUID`, so (0002,0003) gets a second UID ≠ (0008,0018) (DICOMStudio path too; the CLI now rewrites it) | PS3.10 2026a Table 7.1-1 | High | ✅ Closed 2026-10-01 (`55b5e6b9`): fixed by D175 with no edit to `ImageConverter.secondaryCaptureData` — (0002,0003) equals the SC data set's (0008,0018) (dicom-image and DICOMStudio); PS3.10 2026a Table 7.1-1; test FileMetaMediaStorageUIDTests.test_imageConverter_secondaryCapture_fileMetaEqualsDataSet. |
| D166 | DICOMKit | Sources/DICOMKit/SecondaryCapture/ImageConverter.swift:157-181 | text written as UTF-8 without Specific Character Set (0008,0005) "ISO_IR 192" when a value is not ASCII (CLI adds it) | PS3.3 2026a Table C.12-1 (1C), Table C.12-5 | Medium | ✅ Closed 2026-10-01 (`3ca15a08`): ImageConverter writes Specific Character Set (0008,0005) "ISO_IR 192" when a SH/LO/ST/LT/PN/UC/UT value (sequences included) is not ASCII, via the new internal DataSet.setUTF8SpecificCharacterSetIfNeeded (PS3.3 2026a Table C.12-1 Type 1C, Table C.12-5; PS3.5 6.1.2.3); dicom-image's SCOutput.finalize step left in place (idempotent); ImageConverterStandardTests |
| D167 | DICOMKit | Sources/DICOMKit/SecondaryCapture/ImageConverter.swift:184-187 | converter identity (DICOMKit / "dicom-image CLI" / "1.1.6") written to General Equipment, which describes the equipment that created the original image; belongs in SC Equipment Secondary Capture Device Manufacturer / Model Name / Software Versions (0018,1016/1018/1019); "dicom-image CLI" also when DICOMStudio converts | PS3.3 2026a C.8.6.1 (scenario table), Table C.8-24 | Low | ✅ Closed 2026-10-01 (`3ca15a08`): converter identity moved to SC Equipment Secondary Capture Device Manufacturer / Manufacturer's Model Name / Software Versions (0018,1016/1018/1019) = "DICOMKit" / "DICOMKit ImageConverter" / DICOMFile.implementationVersionName; General Equipment (U in Table A.8-1; C.8.6.1 scenario table: equipment that created the original image) no longer written, so no "dicom-image CLI" / "1.1.6" from DICOMStudio (PS3.3 2026a C.8.6.1, Table C.8-24) |
| D168 | DICOMKit | Sources/DICOMKit/SecondaryCapture/ImageConverter.swift:166 | EXIF UserComment/ImageDescription written to Study Description (LO) without the 64-character limit or `\` check | PS3.5 2026a Table 6.2-1 (LO) | Low | ✅ Closed 2026-10-01 (`3ca15a08`): EXIF UserComment / ImageDescription copied to Study Description is made a valid LO: control characters → space, `\` → "/", trimmed, at most 64 characters, omitted when empty (ImageConverter.longStringValue; PS3.5 2026a Table 6.2-1) |
| D169 | DICOMKit | Sources/DICOMKit/PixelEditing/PixelEditor.swift:81-214 | `processData` returns the edit with the source SOP Instance UID, Image Type, Implementation Class UID and stale Smallest/Largest Pixel Value, no Derivation Description / Source Image Sequence; DICOMStudio uses it as is (the CLI fixes this in DerivedImage.swift) | PS3.3 2026a C.7.6.1.1.2, Table C.12-10; PS3.10 Table 7.1-1 | Medium | ✅ Closed 2026-10-01 (`ed4470db`): PixelEditor.processData/processFile take `derivation: PixelEditDerivation? = PixelEditDerivation()`: new SOP Instance UID + (0002,0003), Image Type Value 1 DERIVED (DERIVED\SECONDARY when absent), Derivation Description "<prefix>: <steps>" (ST ≤1024, appended), Source Image Sequence Item with Purpose of Reference DCM 121322 (CID 7202; CID 7203 has no code for fill/crop/window/invert — DCM 113047 is masking one image by another — so no Derivation Code Sequence), Smallest/Largest (Image) Pixel Value (in Series) removed, DICOMKit Implementation Class UID / Version Name (PS3.3 2026a C.7.6.1.1.2, Table C.12-10; PS3.10 Table 7.1-1); `nil` keeps the identity — PixelRedactor passes nil so redaction never writes a Source Image Sequence naming the identified original; dicom-pixedit calls the engine with prefix "dicom-pixedit" and its DerivedImage.markDerived workaround was removed; PixelEditorStandardTests, dicom-pixeditTests |
| D170 | DICOMKit | Sources/DICOMKit/PixelEditing/PixelEditor.swift:296-332 | `applyWindowLevel` applies center/width to stored values; Window Center/Width are Modality LUT output units (CLI translates; DICOMStudio does not) | PS3.3 2026a C.11.2.1.2 | Medium | ✅ Closed 2026-10-01 (`ed4470db`): `.windowLevel` center/width are Modality LUT output units: stored values go through Rescale Slope/Intercept (per frame via Pixel Value Transformation Sequence) or the Modality LUT Sequence before the C.11.2.1.2.1 function; width < 1 throws invalidWindowWidth ("shall always be greater than or equal to 1"); dicom-pixedit's storedWindow translation removed (PS3.3 2026a C.11.2.1.2) |
| D171 | DICOMKit | Sources/DICOMKit/PixelEditing/PixelEditor.swift:259-294 | `applyCrop` leaves Image Position (Patient) (top level and Plane Position Sequence in functional groups) and Overlay Rows/Columns/Origin unchanged (CLI updates top-level IPP only) | PS3.3 2026a C.7.6.2.1.1, C.9.2 | Medium | ✅ Closed 2026-10-01 (`ed4470db`): crop moves Image Position (Patient) per Equation C.7.6.2.1-1 at the top level and in the Plane Position Sequence of the Shared / Per-Frame Functional Groups (orientation and Pixel Measures taken per frame or shared), and Overlay Origin (60xx,0050) by −(rows, columns); Overlay Rows/Columns are the overlay plane's own size and correctly stay (PS3.3 2026a C.7.6.2.1.1, Table C.9-2) |
| D172 | DICOMKit | Sources/DICOMKit/PixelEditing/PixelEditor.swift:486-509 | `setPixelValue` clamps to the Bits Allocated range, not Bits Stored / Pixel Representation, so `.mask` can write values above High Bit | PS3.3 2026a C.7.6.3.1 | Low | ✅ Closed 2026-10-01 (`ed4470db`): setPixelValue clamps every written sample (mask fill included) to the Bits Stored / Pixel Representation range, so nothing lands above High Bit (PS3.3 2026a C.7.6.3.1); dicom-pixedit still refuses an out-of-range --fill-value first (P-PIXEDIT-RANGE) |
| D173 | DICOMKit | Sources/DICOMKit/PixelEditing/PixelEditor.swift:107-128 | decoding a lossy-compressed input writes native pixels without setting Lossy Image Compression "01" (and Method) when the input lacks them | PS3.3 2026a C.7.6.1.1.5 | Low | ✅ Closed 2026-10-01 (`ed4470db`): decoding an encapsulated lossy source sets Lossy Image Compression (0028,2110) "01" and, when absent, Lossy Image Compression Method from TransferSyntax.lossyImageCompressionMethod; J2K .91/.93/.203 decided by J2KCodestreamInspector.usesIrreversibleWavelet, a JPEG XL .112 codestream is not inspected and left as it was (PS3.3 2026a C.7.6.1.1.5) |
| D174 | DICOMKit | Sources/DICOMKit/PixelEditing/PixelEditor.swift:296-345 | window/invert transform PALETTE COLOR indices and leave Pixel Padding Value (0028,0120) untransformed | PS3.3 2026a C.7.6.3.1.5, C.7.5.1.1.2 | Low | ✅ Closed 2026-10-01 (`ed4470db`): window/invert on PALETTE COLOR throw the new PixelEditError.notApplicableToPaletteColor (stored values are palette indices, C.7.6.3.1.5); Pixel Padding Value / Range Limit are remapped by invert ([pivot−high, pivot−low]) and window (mapped range, ordered per MONOCHROME1/2), or removed when a window maps padding onto values present in the image (PS3.3 2026a C.7.5.1.1.2) |
| D175 | DICOMKit | `Sources/DICOMKit/DICOMFile+Write.swift:230` `DICOMFile.create(dataSet:sopClassUID:sopInstanceUID:transferSyntaxUID:)` | Root cause of D112, D137, D162, D165 (and the CLI workarounds in dicom-anon, dicom-image, dicom-json): when `sopInstanceUID` is nil the File Meta gets a freshly generated UID, and `sopClassUID` defaults to Secondary Capture, instead of copying (0008,0018) / (0008,0016) from the data set, so (0002,0003)/(0002,0002) disagree with the data set for every caller that omits them. PS3.10 Table 7.1-1 requires them to equal the SOP Instance / Class UID. Proposed fix (behaviour, no signature change for the instance UID): default to the data set's (0008,0018) when present; for the class UID, the default can only be fixed by making the parameter optional — a P-item for DICOMKit | PS3.10 2026a Table 7.1-1 | High | ✅ Closed 2026-10-01 (`55b5e6b9`): `DICOMFile.create` (Sources/DICOMKit/DICOMFile+Write.swift) now takes Media Storage SOP Class UID (0002,0002) / Media Storage SOP Instance UID (0002,0003) from the data set's SOP Class UID (0008,0016) / SOP Instance UID (0008,0018) when present (data set authoritative; a differing argument is ignored), else from the argument, else Secondary Capture Image Storage / a generated UID, which is then also written into the data set (except for Media Storage Directory Storage 1.2.840.10008.1.3.10: the Basic Directory IOD has no SOP Common Module, PS3.3 2026a Table F.3-1). `sopClassUID:` changed from `String = SC` to `String? = nil` (source-compatible; no deprecation needed). New public `DICOMFile.synchronizingMediaStorageUIDs()` re-aligns a carried-over File Meta and recomputes (0002,0000). PS3.10 2026a Table 7.1-1 ("Uniquely identifies the SOP Class / SOP Instance associated with the Data Set"); 17 tests in Tests/DICOMKitTests/FileMetaMediaStorageUIDTests.swift. |
| D176 | DICOMCore | Sources/DICOMCore/TransferSyntax.swift:1332 (`displayName`) | The 16 video transfer syntax names are abbreviations, not the PS3.6 names ("MPEG2 Main Profile @ Main Level" vs "MPEG2 Main Profile / Main Level", "MPEG-4 AVC/H.264 HP @ Level 4.1" vs "MPEG-4 AVC/H.264 High Profile / Level 4.1"; 16/16 differ); dicom-video prints them on the probe/convert "Transfer syntax:" line, in --verbose and violation messages. `UIDDictionary.lookup(uid:)?.name` has the A-1 name | PS3.6 2026a Table A-1 | Low | ✅ Closed 2026-10-01 (`0d8aa69d`): `TransferSyntax.displayName` = PS3.6 2026a Table A-1 "UID Name" verbatim for all 63 Transfer Syntax rows (dumped by script; 48 differed, not only the 16 video rows — e.g. "Implicit VR Little Endian: Default Transfer Syntax for DICOM", "JPEG 2000 Image Compression (Lossless Only)", "… (Retired)"); old abbreviations kept as new `shortName`. `SelectableEncoding.displayName` = A-1 name + " (lossless)"/" (lossy)" for .91/.93/.203, `SelectableEncoding.shortName` = old picker label; `PixelDataError.transferSyntaxName` = A-1 name. Unregistered HEVC Fragmentable pair named "Fragmentable HEVC/H.265 Main [10] Profile / Level 5.1"; JP3D pair unchanged. Pinned expectations updated: DICOMCoreTests (TransferSyntaxTests, PixelDataErrorTests), DICOMKitTests (CompressionManagerMetricsTests:80, ConversionDiagnosticsTests:73, LossyImageCompressionAttributesTests:143/154), DICOMRoundTripTests (VideoConsoleParityTests:215, dicom-video probe line), dicom-j2kTests (DicomJ2KTests label tests ×4), DICOMStudioTests (DataExchangeModelTests:255, 273, 274 — expectations only) |
| D177 | DICOMKit | Sources/DICOMKit/Video/MP4ContainerParser.swift:32 (`isPermittedByDICOM`); VideoConformanceValidator.swift:113 | MPEG2 MP@ML/MP@HL streams are rejected unless in MP4 or MPEG-TS, citing 8.2.7; 8.2.5 and 8.2.6 say "The container format for the video bit stream is not constrained" (MPEG-TS, PS, ES, PES or MP4) | PS3.5 2026a 8.2.5, 8.2.6 | Low | ✅ Closed 2026-10-01 (`99c47e2e`): new VideoContainer.isPermittedByDICOM(for: VideoCodec): MPEG-TS or MP4 for H.264/HEVC (PS3.5 2026a 8.2.7–8.2.11), any readable container incl. raw elementary stream and QuickTime for MPEG-2 ("The container format for the video bit stream is not constrained", 8.2.5, 8.2.6); codec-blind `isPermittedByDICOM` property deprecated (= H.264 rule); VideoWorkflow.planConversion uses the codec's rule; rejection text cites 8.2.7-8.2.11 |
| D178 | DICOMKit | Sources/DICOMKit/Video/VideoStreamInfo.swift:98 (`levelDescription`) | MPEG2 level printed as "0.8" (level_indication 8); PS3.5 names the levels "Main Level" / "High Level" | PS3.5 2026a 8.2.5, 8.2.6 | Low | ✅ Closed 2026-10-01 (`99c47e2e`): VideoStreamInfo.levelDescription names MPEG-2 levels "Main" / "High" / "High 1440" / "Low" (PS3.5 2026a 8.2.5/8.2.6 "Main Level" / "High Level") instead of "0.8"; also fixed in the same commit: the MPEG-2 level ceiling in VideoConformanceValidator compared level_identification the wrong way (High Level content passed MP@ML, Low was flagged) — now smaller identifier = higher level; the existing test that asserted Main Level fails MP@HL was corrected (8.2.6: an MP@HL decoder decodes lower levels) |
| D179 | DICOMKit | Sources/DICOMKit/Video/VideoProbe.swift:291 (`probeElementaryStream`) | A raw MPEG-2 elementary stream (.m2v, sequence header 00 00 01 B3) is tried as H.264 first and reported as "H.264/AVC, profile_idc 51, level 12.5, 32x16"; the MPEG2 sequence-header check (line 319) is never reached | PS3.5 2026a 8.2.5 | Medium | ✅ Closed 2026-10-01 (`99c47e2e`): VideoProbe.probeElementaryStream checks the first start code; 00 00 01 B3 (MPEG-2 sequence header) is parsed as MPEG-2 before the H.264/HEVC SPS search, which took slice start code 0x07 for NAL type 7; a raw .m2v now probes as MPEG2 MP@ML and plans transfer syntax 1.2.840.10008.1.2.4.100 (PS3.5 2026a 8.2.5); VideoProbeTests |
| D180 | DICOMKit | Sources/DICOMKit/Video/VideoBuilder.swift:649 (`toDataSet`) | A non-ASCII --patient-name (or other text) is written as UTF-8 without Specific Character Set (0008,0005) (checked: "Müller^Jörg" read back as "MÃ¼ller^JÃ¶rg") | PS3.3 2026a Table C.12-1 (Type 1C), Table C.12-5 (ISO_IR 192); PS3.5 6.1.2.2 | Medium | ✅ Closed 2026-10-01 (`99c47e2e`): Video.toDataSet sets Specific Character Set "ISO_IR 192" when a text value is not ASCII ("Müller^Jörg" reads back unchanged) (PS3.3 2026a Table C.12-1 Type 1C, Table C.12-5; PS3.5 6.1.2.3) |
| D181 | DICOMKit | Sources/DICOMKit/EncapsulatedDocument/EncapsulatedDocumentParser.swift:54; EncapsulatedDocumentWorkflow.swift:99 | `documentData` is the padded value; (0042,0015) is ignored, so an odd-length document gains a 0x00 and `metadataReport()` "Size" shows the padded length (dicom-pdf now cuts it itself) | PS3.3 2026a Table C.24-2 (0042,0015) | Low | ✅ Closed 2026-10-01 (`51ef296a`): EncapsulatedDocumentParser cuts the value to Encapsulated Document Length (0042,0015) when it is one less than the value length (new public documentStream(_:in:); a length that is neither VL nor VL−1 is ignored), so an odd-length document no longer gains 0x00 and metadataReport() "Size" is the unpadded size (PS3.3 2026a Table C.24-2); dicom-pdf's documentBytes cut left in place (idempotent) |
| D182 | DICOMKit | Sources/DICOMKit/EncapsulatedDocument/EncapsulatedDocumentBuilder.swift:485 (`buildDataSet`), :560 (`toDataSet`) | Builder writes neither Encapsulated Document Length (0042,0015) nor Specific Character Set (0008,0005) for non-ASCII text (UTF-8 bytes written); dicom-pdf now adds both itself, the DICOMStudio Workshop path does not | PS3.3 2026a Table C.24-2; Table C.12-1 (Type 1C), Table C.12-5 | Low | ✅ Closed 2026-10-01 (`51ef296a`): EncapsulatedDocument.toDataSet writes (0042,0015) UL = unpadded byte count, and toDataSet / buildDataSet set Specific Character Set "ISO_IR 192" for non-ASCII text, so the DICOMStudio Workshop path gets both (PS3.3 2026a Table C.24-2; Table C.12-1 Type 1C, C.12-5); dicom-pdf's EncapsulationAttributes.complete left in place (idempotent) |
| D183 | DICOMKit | Sources/DICOMKit/Compression/CompressionConsole.swift:83-89, 324 | "Compression ratio: 12.0%" is output/input size in percent, not the N:1 ratio PS3.3 defines for (0028,2112); info label "Samples Per Pixel" (PS3.6: "Samples per Pixel") | PS3.3 2026a C.7.6.1.1.5.2; PS3.6 2026a Table 6-1 | Low | ✅ Closed 2026-10-01 (`d37433f0`): CompressionConsole ratio lines use the PS3.3 2026a C.7.6.1.1.5.2 form ("the numerator of an implicit ratio in which the denominator is always one", "30:1"): "Compression ratio: 3.03:1" (input / output) and "Decompression ratio: 1:3.03" (was output as % of input); info label "Samples per Pixel" (PS3.6 2026a (0028,0002)). Shared with DICOMStudio's Workshop through the same console |
| D184 | DICOMKit | Sources/DICOMKit/Compression/CompressionManager.swift:552-591 | Lossy compress records (0028,2110/2112/2114) and DERIVED but keeps the SOP Instance UID and (0002,0003): rgb8.dcm → jpeg, jpeg2000, htj2k, jpeg-ls, jpeg-xl outputs all carry the source UID | PS3.3 2026a C.7.6.1.1.5 ("if the predecessor was a DICOM image, then the Image shall receive a new SOP Instance UID") | High | ✅ Closed 2026-10-01 (`d37433f0`): `CompressionManager.applyLossyImageCompressionAttributes` (used by dicom-compress and dicom-convert) gives every irreversible output a new SOP Instance UID, written to (0002,0003) too (PS3.3 2026a C.7.6.1.1.5: "If an image is a compressed version of another image, Lossy Image Compression (0028,2110) is set to "01", Value 1 of the Attribute Image Type (0008,0008) shall be set to DERIVED, and if the predecessor was a DICOM image, then the Image shall receive a new SOP Instance UID" — all three are "shall"); appends "Lossy compression <method>, ratio N:1" to Derivation Description (0008,2111) (C.7.6.1.1.5.2: "should also be described"). Lossless output keeps the UID. Source Image Sequence (0008,2112) with CID 7202 "Uncompressed predecessor" not added (Type 3, optional; General Reference Module not in every IOD) |
| D185 | DICOMKit | Sources/DICOMKit/Compression/CompressionManager.swift:451-530 (encodePixelDataInPlace) | After a JPEG 2000 / HTJ2K encode of a 3-sample image the codestream has COD MCT = 1 (RCT with 5-3, ICT with 9-7) but Photometric Interpretation stays RGB (fixtures out_rgb_jpeg2000/-lossless/htj2k/htj2k-rpcl) | PS3.5 2026a 8.2.4, 8.2.14 ("No other Value of Photometric Interpretation than YBR_RCT or YBR_ICT is permitted when SGcod Multiple component transformation type is 1"), Tables 8.2.4-1, 8.2.14-1 | High | ✅ Closed 2026-10-01 (`d37433f0`): after a J2K / HTJ2K encode `CompressionManager.labelEncodedColour` reads COD SGcod via `J2KCodestreamInspector.codingStyle`: MCT = 1 → YBR_RCT (5-3) / YBR_ICT (9-7), Planar Configuration 0 (PS3.5 2026a 8.2.4, Table 8.2.4-1; 8.2.14, Table 8.2.14-1: "No other Value of Photometric Interpretation than YBR_RCT or YBR_ICT is permitted when SGcod Multiple component transformation type is 1"); jpeg2000 / jpeg2000-lossless / -lossless-only / htj2k / htj2k-lossless-only / htj2k-rpcl pinned in DeferredRowsB6aCodecTests |
| D186 | DICOMKit | Sources/DICOMKit/Compression/CompressionManager.swift:593-680 (decodePixelDataInPlace) | Decompressing a YBR_RCT / YBR_ICT JPEG 2000 file writes native RGB samples labelled YBR_RCT / YBR_ICT (only JPEG YBR and XYB are relabelled) | PS3.5 2026a 8.2 (native PI "shall be other than YBR_RCT, YBR_ICT, YBR_PARTIAL_420"), 8.2.4 ("will be changed to RGB") | High | ✅ Closed 2026-10-01 (`d37433f0`): `decodePixelDataInPlace` relabels YBR_RCT / YBR_ICT to RGB after a JPEG 2000 / HTJ2K decode (PS3.5 2026a 8.2.4: "the Photometric Interpretation will be changed to RGB in the Data Set with the Native encoding"); reversible round trip is bit-exact |
| D187 | DICOMCore (J2KSwift dependency) | Sources/DICOMCore/J2KRoutePlanner.swift:324-326; J2KSwiftCodec.swift:509-528; .build/checkouts/J2KSwift/Sources/J2KCodec/J2KEncoderPipeline.swift:6454 | 1.2.840.10008.1.2.4.202 output has COD progression LRCP (the encoder always writes 0 whatever `progressionOrder` says) and no TLM marker segment, while the markers claim RPCL is satisfied; seen via dicom-compress `htj2k-rpcl-lossless-only` and dicom-j2k `transcode` (which now warns) | PS3.5 2026a 10.18.1 (RPCL, base resolution ≤ 64, TLM shall be present) | Medium | ✅ Closed 2026-10-01 (`4ed69751`): .202 output now meets PS3.5 2026a 10.18.1 — `J2KSwiftCodec` passes decomposition levels max(5, levels for a base resolution ≤ 64) to J2KSwift, and `J2KCodestreamInspector.conformingToHTJ2KRPCL` inserts a TLM marker segment (Ztlm/Stlm/Ttlm/Ptlm from every SOT Psot) and sets COD SGcod to RPCL (2) when the packet sequence is provably identical (1 quality layer, default precincts, no POC/COC/tile COD — exactly what J2KSwift writes: probe showed layers=1, Scod=0, 1 tile-part); round-trip verify runs on the final stream; J2K → .202 excluded from the coefficient fast path. Output bit-exact with OpenJPH, OpenJPEG, Kakadu (Corder=RPCL, Clevels=6 for 3000×2500) and Grok. J2KSwift itself is unchanged — see D216 for the upstream request |
| D188 | DICOMKit | Sources/DICOMKit/Compression/CompressionManager.swift:904-933 | File Meta UI values (0002,0002), (0002,0003), (0002,0010) are written with odd length and no trailing NULL (DCMTK: "Length of element (0002,0002) is odd") | PS3.5 2026a 6.2 (UI padding), 7.1 (even Value Length); PS3.10 7.1 | Medium | ✅ Closed 2026-10-01 (`d37433f0`): TransferSyntaxHelper writes (0002,0002), (0002,0003), (0002,0010), (0002,0012) padded to even length with one trailing NULL (PS3.5 2026a 6.2 / Table 6.2-1 UI; 7.1 even Value Length); test pins the odd 17-character UID → 18 bytes |
| D189 | DICOMKit | Sources/DICOMKit/Compression/CompressionManager.swift:583 | Comment cites "PS3.3 C.7.6.1.1.5.1: shall be set to DERIVED"; that sentence is in C.7.6.1.1.5 (C.7.6.1.1.5.1 is Lossy Image Compression Method) | PS3.3 2026a C.7.6.1.1.5 | Low | ✅ Closed 2026-10-01 (`d37433f0`): the DERIVED comment cites PS3.3 2026a C.7.6.1.1.5 and quotes it; the C.7.6.1.1.5.1 citation is kept only for the Ratio/Method value order, which is what C.7.6.1.1.5.1 says |
| D190 | DICOMCore | JPEG Baseline encoder (default `.jli` engine, CodecRegistry) | .4.50 colour output carries a JFIF APP0 segment and YCbCr 4:4:4 components while Photometric Interpretation is RGB; PS3.5 recommends JFIF be absent and not relied on, and Table 8.2.1-1 allows YBR_FULL_422 or RGB only | PS3.5 2026a 8.2.1, Table 8.2.1-1 | Low | ✅ Closed 2026-10-01 (`4ed69751` JFIF half; `d2e9e3f8` + `d37433f0` colour half): JLICodec encodes lossy colour as YCbCr 4:2:2 and TransferSyntaxConverter / CompressionManager label it YBR_FULL_422, Planar Configuration 0, from the SOF sampling factors (new `JPEGInterchangeFormat.frameComponents(in:)` / `isHorizontally422(_:)`; test parses SOF independently: 2x1, 1x1, 1x1). PS3.5 2026a Table 8.2.1-1 (dumped) has one 3-sample row: YBR_FULL_422 / RGB, JPEG Baseline .50 only — so JPEG Extended .51 colour is now refused, and NativeJPEGCodec (ImageIO) refuses colour: probed, ImageIO writes 4:2:0 (H2 V2) for quality < 1.0 and 4:4:4 at 1.0, no option changes it, neither is labelable |
| D191 | DICOMKit | Sources/DICOMKit/DICOMConverter.swift:340-352 | `stripPrivate` filters the top-level Data Set only; a Private Creator and Private Data Element inside a Sequence Item survive (fixture priv.dcm: (0011,0010)/(0011,1001) in Referenced Image Sequence) | PS3.5 2026a 7.8.1 (Items are self-contained Data Sets with their own Private Data Elements) | Medium | ✅ Closed 2026-10-01 (`d37433f0`): `DICOMConverter` strip-private recurses into Sequence Items at any depth (`strippingPrivate(_:count:)`), counts nested removals (PS3.5 2026a 7.8.1); fixture with (0011,0010)/(0011,1001) in Referenced Image Sequence pinned |
| D192 | DICOMKit | Sources/DICOMKit/DICOMConverter.swift:488-491 (applyLossyProvenance) | A lossy convert records (0028,2110/2112/2114) and DERIVED but keeps the SOP Instance UID (c_lossy.dcm, c_jpeg.dcm) | PS3.3 2026a C.7.6.1.1.5 | High | ✅ Closed 2026-10-01 (`d37433f0`): same shared writer as D184 — a lossy dicom-convert output has a new SOP Instance UID in the data set and (0002,0003) (PS3.3 2026a C.7.6.1.1.5) |
| D193 | DICOMCore | Sources/DICOMCore/TransferSyntaxConverter.swift:791-826 | J2K → native keeps PI YBR_RCT / YBR_ICT over RGB samples (only XYB and JPEG YBR are relabelled); RGB → J2K leaves PI RGB with COD MCT = 1 | PS3.5 2026a 8.2, 8.2.4, Table 8.2.4-1 | High | ✅ Closed 2026-10-01 (`4ed69751`): `TransferSyntaxConverter` — native RGB → JPEG 2000 / HTJ2K with COD SGcod MCT = 1 is labelled YBR_RCT (5-3) or YBR_ICT (9-7) and Planar Configuration 0; J2K / HTJ2K → native relabels YBR_RCT / YBR_ICT to RGB (PS3.5 2026a 8.2.4 / Table 8.2.4-1: "If the JPEG 2000 Part 1 reversible multi-component transformation has been applied then … shall be YBR_RCT … irreversible … YBR_ICT"; "If color components are converted from YBR_ICT or YBR_RCT to RGB during decompression and Native re-encoding, the Photometric Interpretation will be changed to RGB"; 8.2.14 for HTJ2K). Same defect remains in DICOMKit CompressionManager (D219); dicom-j2k's own J2KDICOMBoundary relabel left in place |
| D194 | DICOMKit | Sources/DICOMKit/StructuredReporting/SRDocumentParser.swift:489 | NUM with an empty Measured Value Sequence (Type 2, zero items allowed) is parsed as value 0.0 in the default lenient mode, so renderers print a fabricated "0" measurement | PS3.3 2026a Table C.18.1-1 | Medium | ✅ Closed 2026-10-01 (`488a9c07`): a NUM with an empty Measured Value Sequence keeps no value (`numericValues` empty, `value` nil) instead of a fabricated 0.0; the serializer writes such a NUM as an empty Measured Value Sequence; PS3.3 2026a Table C.18.1-1 (Type 2, "Zero or one Item") and C.18.1 ("may be empty to convey ... unknown or missing, or a measurement or calculation failure") (SRDeferredRowsTests) |
| D195 | DICOMKit | Sources/DICOMKit/StructuredReporting/SRDocumentParser.swift:499 | Numeric Value Qualifier Code Sequence (0040,A301) is never read (`qualifier: nil`), although `NumericValueQualifier(code:)` exists | PS3.3 2026a Table C.18.1-1; PS3.16 CID 42 | Medium | ✅ Closed 2026-10-01 (`488a9c07`): Numeric Value Qualifier Code Sequence (0040,A301), Type 1C "Required if Measured Value Sequence (0040,A300) is empty", read into `numericValueQualifier` (codes outside CID 42 → nil) and written; CID 42 = CID 43 + CID 44, 12 codes 114000-114011 compared by script with the enum; PS3.3 2026a Table C.18.1-1, PS3.16 2026a CID 42/43/44 |
| D196 | DICOMKit | Sources/DICOMKit/StructuredReporting/SRDocumentSerializer.swift:898 | Referenced Waveform Channels (0040,A0B0), Type 1C, is not written for WAVEFORM items ("can be added if needed"), so channel references are lost on round-trip | PS3.3 2026a Table C.18.5-1, C.18.5.1.1 | Low | ✅ Closed 2026-10-01 (`488a9c07`): Referenced Waveform Channels (0040,A0B0) written as US (M,C) pairs; new DICOMCore `WaveformChannelReference`, `WaveformReference.referencedChannels`, `init(sopReference:referencedChannels:)` (additive; `init(sopReference:channelNumbers:)` puts its channels in multiplex group 1); the parser keeps the Multiplex Group numbers it used to drop; PS3.3 2026a Table C.18.5-1, C.18.5.1.1 (example 0001 0000 0003 0002 0003 0003 pinned in the test) |
| D197 | DICOMKit | Sources/DICOMKit/DataSet+PixelData.swift:476 (also DICOMFile+PixelData.swift:465) | `rescale(_:)` takes no frame index and calls `rescaleSlope()`/`rescaleIntercept()` without one, so a Per-frame Pixel Value Transformation Sequence (0028,9145) is ignored for every frame but the first; dicom-measure works around it with `rescaleSlope(frameIndex:)` | PS3.3 2026a Table C.7.6.16-10, Table C.8-126 | Low | ✅ Closed 2026-10-01 (`d37433f0`): new `DataSet.rescale(_:frameIndex:)` / `DICOMFile.rescale(_:frameIndex:)` take Rescale Slope / Intercept from the frame's Pixel Value Transformation Sequence (0028,9145) in the Per-Frame Functional Groups (PS3.3 2026a C.7.6.16.2.9, Tables C.7.6.16-10, C.8-126); `rescale(_:)` unchanged (shared / first frame). dicom-measure's workaround replaced by the new call (trivially equivalent, dicom_measureTests 22/22) |
| D198 | DICOMKit | Sources/DICOMKit/StructuredReporting/SRDocumentSerializer.swift:91, :113 | `SRDocumentSerializer` writes only Patient's Name / Patient ID and Study Instance UID / Study Date / Study Time / Accession Number (when set); the Type 2 Patient's Birth Date, Patient's Sex, Referring Physician's Name, Study ID and Manufacturer (0008,0070) are never written and `SRDocument` has no fields for them (`MeasurementReportBuilder.withPatientBirthDate/withPatientSex/withReferringPhysicianName` are dropped by `build()`) | PS3.3 2026a Tables C.7-1, C.7-3, C.7-8, A.35.3-1 | Medium | ✅ Closed 2026-10-01 (`488a9c07`): `SRDocument` carries Patient's Birth Date, Patient's Sex, Referring Physician's Name, Study ID, Manufacturer (defaulted init parameters, `withPatientStudyAndEquipment`, `withRootContent`); the 9 SR builders pass birth date / sex / referring physician through `build()`; `SRDocumentSerializer` always writes the Type 2 rows (Patient's Name, Patient ID, Birth Date, Sex; Study Date, Study Time, Referring Physician's Name, Study ID, Accession Number; Manufacturer), zero length when unknown; the parser reads them (zero length → nil); PS3.3 2026a Tables C.7-1, C.7-3, C.7-8, A.35.3-1 |
| D199 | DICOMKit | Sources/DICOMKit/StructuredReporting/MeasurementReportBuilder.swift:494 (root at :583) | `MeasurementReportBuilder` has no API for TID 4019 Algorithm Identification (TID 1500 rows 6b, 10b, 12b; TID 1501 row 9b) or for the TID 1001 observation context (row 3 → TID 1002/1004 device observer), and builds the root CONTAINER without a template identifier, so the Content Template Sequence (DCMR, 1500) that PS3.3 Table C.18.8-1 requires is never written; dicom-ai adds row 6b and the root template after `build()` | PS3.16 2026a TID 1500, TID 1501, TID 4019, TID 1001; PS3.3 2026a Table C.18.8-1 | Medium | ✅ Closed 2026-10-01 (`488a9c07`): `MeasurementReportBuilder.withAlgorithmIdentification` (TID 1500 row 6b), `withQualitativeEvaluationsAlgorithmIdentification` (row 12b), `MeasurementGroupData.algorithmIdentification` (TID 1501 row 9b) → TID 4019 rows 1, 2, 2b, 3, 4 (reusing `CADAlgorithmIdentification`); `addObserver(.person/.device)` → row 3 → TID 1001 row 1 → TID 1002 rows 1-3 → TID 1003 rows 1-2 / TID 1004 rows 1-5; root Content Template Sequence (DCMR, 1500) always written (PS3.3 Table C.18.8-1); row 6 written when an algorithm is set and row 12 is absent (MC); 14 concept meanings compared with PS3.16 2026a Table D-1. dicom-ai now uses `withAlgorithmIdentification` (its own row-6b/template code removed); its Patient/Study/Manufacturer copy after serialization is kept (it carries the source values) |
| D200 | DICOMKit | Sources/DICOMKit/Scripting/ScriptEngine.swift:587 | the `query` template passes `--study-date-from 20240101 --study-date-to 20241231`, options dicom-query does not have; a Study Date range is one PS3.4 range value, `--study-date 20240101-20241231` | PS3.4 2026a C.2.2.2.5 (Range Matching) | Low | ✅ Closed 2026-10-01 (`092cf368`): query template uses `--study-date 20240101-20241231`, one range value per PS3.4 2026a C.2.2.2.5 (dicom-query declares no `--study-date-from/-to`) |
| D201 | DICOMKit | Sources/DICOMKit/Scripting/ScriptEngine.swift:555, :558, :584, :587 | `pipeline` / `query` templates pass `--host ${PACS_HOST}`; dicom-query and dicom-retrieve take host[:port] as a positional argument, and dicom-retrieve has no `--patient-id` (it retrieves by `--study-uid` etc.), so the generated scripts fail | — (template plumbing) | Low | ✅ Closed 2026-10-01 (`092cf368`): pipeline / query templates pass host as the positional argument, `--aet` for the calling AE (there is no `--calling-aet` either), lowercase levels; dicom-retrieve by `--study-uid ${STUDY_UID} --method c-get` (it has no `--patient-id`); dicom-script README examples fixed; ScriptRoundTripTests checks every template option against the tools' declarations |
| D202 | DICOMKit | Sources/DICOMKit/Scripting/ScriptEngine.swift:564, :619, :623 | `pipeline` / `anonymize` templates use `dicom-anon --profile basic` (the legacy profile dicom-anon documents as not PS3.15) and `--profile strict` (no such profile); the PS3.15 Basic Application Level Confidentiality Profile is `--profile ps315` | PS3.15 2026a E.1 | Medium | ✅ Closed 2026-10-01, `e2c5ea18` (templates run `dicom-anon --profile ps315`; `strict` → `--profile ps315 --clean-pixel-data`) |
| D203 | DICOMKit | Sources/DICOMKit/Scripting/ScriptEngine.swift:567, :600 | `dicom-archive create … --input` — dicom-archive has no `create` subcommand (`init`, `import`) | — (template plumbing) | Low | ✅ Closed 2026-10-01 (`092cf368`): `dicom-archive create` replaced by `init --path` + `import <dir> --archive --recursive`; query / export templates use `--archive` (the archive is an option, not a positional) |
| D204 | DICOMKit | Sources/DICOMKit/JP3DVolumeDocument.swift:486-497 | decode-volume slices: Image Position (Patient) z = origin.z + i·spacing (ignores Image Orientation (Patient)); no Image Orientation (Patient), Pixel Spacing, Frame of Reference UID or Rescale written; Slice Location = z; SOP Class falls back to CT Image Storage for any source | PS3.3 2026a C.7.6.2.1.1, Table C.7-10, C.7.4.1.1.1 | Medium | ✅ Closed 2026-10-01 (`100a5455`): decode-volume slices: Image Position (Patient) = origin + i·spacing·(row × column cosine) per PS3.3 2026a C.7.6.2.1.1 Equation C.7.6.2.1-1; Image Orientation (Patient) and Pixel Spacing written (Table C.7-10), one Frame of Reference UID per series (C.7.4.1.1.1), source Rescale Intercept/Slope/Type and source SOP Class (legacy sidecars: CT/MR/PET Image Storage by Modality, else Secondary Capture); Slice Location = position along the normal (C.7.6.2.1.2) (JP3DSliceGeometryTests, unsorted sagittal series) |
| D205 | DICOMKit | Sources/DICOMKit/JP3DVolumeDocument.swift:393, 412-424 | sidecar origin taken from the unsorted series[0] and slice spacing from the z coordinate of the first/last input files, while JP3DVolumeBridge sorts the volume itself; wrong for unsorted or non-axial input (dicom-3d encode-volume now pre-sorts) | PS3.3 2026a C.7.6.2.1.1 | Low | ✅ Closed 2026-10-01 (`100a5455`): sidecar origin / spacing / orientation from the first slice in the order JP3DVolumeBridge stacks the volume; the bridge now sorts and spaces by Image Position (Patient) projected on the slice normal (z only without Image Orientation (Patient)); PS3.3 2026a C.7.6.2.1.1 |
| D206 | DICOMKit | Sources/DICOMKit/Compression/CompressionManager.swift:1004-1032 (TransferSyntaxHelper.createWriter / writeDataSet) with Sources/DICOMCore/DICOMWriter.swift:324 | For an Explicit VR Big Endian target the helper writes big-endian headers but copies each element's little-endian value bytes unchanged (no byte swap of US/UL/OW/… values), so a decompress to 1.2.840.10008.1.2.2 would be corrupt; dicom-compress therefore refuses `explicit-be` (P-COMPRESS-SYNTAX) | PS3.5 2026a A.3 (retired; described in PS3.5 2016b) | Low | ✅ Closed 2026-10-01 (`d2e9e3f8`, `d37433f0`, `59936daf`): `DICOMWriter` writes every 2/4/8-byte binary VR value in its own byte order when the element's `byteOrder` differs (PS3.5 2026a 7.3 lists "2-byte US, SS, OW and each component of AT", "4-byte OF, OL, UL, SL, and FL", "8-byte OD, OV, FD, SV and UV"); TransferSyntaxConverter marks parsed / transcoded values with their order (no double swap); CompressionManager and the converter encode a Big Endian source from little-endian samples. Round trips LE → BE → LE (and BE → JPEG Lossless / JPEG 2000 Lossless → LE) are bit-exact in tests. **dicom-compress `decompress/batch --syntax explicit-be` is accepted again** (help: "Explicit VR Big Endian (Retired) — for legacy readers only", A.3 retired 2006); P-COMPRESS-SYNTAX's explicit-be deviation is lifted (update that row's text) |
| D207 | dicom-3d | Sources/dicom-3d/VolumeData.swift:111-121 | `interpolatedVoxelAt(.nearest)` accepts x in [n-1, n) and uses `round`, so x ≥ n-0.5 rounds to n and returns nil; the edge half-voxel reads as missing. The new oblique sampler clamps to voxel centres first, so it is not affected; projections and orthogonal MPR do not use it | PS3.3 2026a C.7.6.2.1.1 (voxel centres) | Low | ✅ Closed 2026-10-01 (`6347a617`): VolumeData.interpolatedVoxelAt(.nearest) clamps the rounded index to n-1, so the edge half voxel reads the last voxel (index = voxel centre, PS3.3 2026a C.7.6.2.1.1), as the linear branch does; Volume3DContractTests +1 |
| D208 | dicom-convert | Sources/dicom-convert/DICOMConvert.swift:26, 64, 98 (and DICOMKit ConversionDiagnostics.swift `invalidFrameNumberMessage` doc) | Help attributes "the first Frame is Frame number 1" to PS3.3 C.7.6.6. In the 2026a DocBook that sentence ("The first Frame shall be denoted as Frame number 1") is in Table 10-3 (sect_10.3), also C.8.25.16.6 / C.18.4. C.7.6.6 only says "Frames numbered from 1" (stereo pairs) and C.7.6.16.1.2 "Frames are implicitly numbered starting from 1". The PITEMS rule text carries the same attribution. dicom-export now cites "Table 10-3, C.7.6.6" | PS3.3 2026a Table 10-3; C.7.6.6; C.7.6.16.1.2 | Low | ✅ Closed 2026-10-01 (`990636cc`): 2026a DocBook dump: "The first Frame shall be denoted as Frame number 1" is in Tables 10-2, 10-3, 10-3b, C.8.25.16-6, C.18.4-1; C.7.6.6 has only "Frames numbered from 1" in the stereo-pairs note C.7.6.6.1.3. All Sources/ frame-number citations of C.7.6.6 (dicom-convert, dicom-export, dicom-measure, dicom-j2k help/errors/READMEs/markers; DICOMKit ConversionDiagnostics doc) now cite PS3.3 Table 10-3; Multi-frame Module / Number of Frames citations (VideoBuilder, FrameSplitter, PixelDataDescriptor, dicom-3d C.7.6.6.1.1) are correct and kept; test pins dicom-convert help + error text |
| D209 | DICOMKit | Sources/DICOMKit/Archive/ArchiveStore.swift (queryTable / queryText, "Modality" column / line) | The query table and text output still print the study-level `modality` (first instance imported) under "Modality". The JSON now has `ModalitiesInStudy`, but the text surfaces still misreport multi-modality studies (rest of D122) | PS3.4 2026a Tables C.6-2 / C.6-5; PS3.6 (0008,0061) | Low | ✅ Closed 2026-10-01 (`2f70f6eb`): query table "Modalities in Study" column and text "Modalities in Study:" line print the series modalities (`CT\PT`), no longer the first-instance `modality`; PS3.4 Tables C.6-2 / C.6-5; PS3.6 (0008,0061) |
| D210 | DICOMNetwork | Sources/DICOMNetwork/QueryResults.swift:459 | `GenericQueryResult` keeps only `[Tag: Data]` (no VR, no transfer syntax), so `dicomJSONElements()` takes the VR from PS3.6 (first of a multi-VR row, e.g. US for "US or SS") and writes a returned sequence as UN InlineBinary instead of nested DICOM JSON objects | PS3.18 2026a F.2.2 (SQ Value = array of objects), F.2.3 | Low | ✅ Closed 2026-10-01 (`22e39bd8`): `GenericQueryResult` keeps `vrs` (Explicit VR as received) and `transferSyntaxUID` (new init, old init kept); `dicomJSONElements()` uses the received VR (e.g. SS for "US or SS") and decodes SQ values into items (PrintDatasetReader, Explicit/Implicit VR LE) so dicom-json writes nested objects, PS3.18 2026a F.2.2 / F.2.5; UN InlineBinary only when undecodable |
| D211 | dicom-anon (docs) | README.md:4388, :4554; CLI_TOOLS_PLAN.md:283-301; CLI_TOOLS_COMPLETION_SUMMARY.md:96, :401; CLI_TOOLS_PHASE7_SUMMARY.md:337; ROUND_TRIP_COVERAGE_GAPS.md:62, :255; DEMO_APPLICATION_PLAN.md:288-289 | repo docs still show `dicom-anon --profile clinical-trial` / `basic` as the old lists. `basic` is now the PS3.15 Basic Profile; `clinical-trial` and `research` are deprecated; `minimal` never existed | PS3.15 2026a E.1 | Low | ✅ Closed 2026-10-01 (`c1dcbbb5`): README.md, CLI_TOOLS_PLAN.md, CLI_TOOLS_COMPLETION_SUMMARY.md, CLI_TOOLS_PHASE7_SUMMARY.md, CLI_TOOLS_MILESTONES.md, DEMO_APPLICATION_PLAN.md, ROUND_TRIP_COVERAGE_GAPS.md, Documentation/DICOMToolbox-UserGuide.md use `--profile ps315` (PS3.15 2026a E.1; basic = alias) or the deprecated `legacy-*` lists with a short note; `--shift-dates` examples add `--retain-modified-dates` (E.3.6, required by ps315); `--keep` example moved to legacy-basic (ps315 refuses it); README's nonexistent `--check-only` → `--dry-run` |
| D212 | dicom-anon (tests) | Tests/DICOMToolsTests/DICOMScriptTests.swift:211, :213, :340 | uncompiled test scripts still use `dicom-anon --profile basic` / `--profile strict` (no such profile). The file is in no target | PS3.15 2026a E.1 | Low | ✅ Closed 2026-10-01 (`c1dcbbb5`): Tests/DICOMToolsTests/DICOMScriptTests.swift uses `--profile ps315` and `--profile ps315 --clean-pixel-data` (E.3.1) instead of basic / strict, as the ScriptEngine templates since D202 (file still compiled by no target) |
| D213 | DICOMWeb | `Sources/DICOMWeb/UPS/UPSResults.swift:70` (`WorkitemResult`) | The parsed workitem drops the server's DICOM JSON, so `UPSResultFormatter` cannot render `dicom-json`; the CLI fetches the raw objects separately (`searchWorkitemsDICOMJSON`) | PS3.18 2026a F.2 | Low | ✅ Closed 2026-10-01 (`f4262b4f`): `WorkitemResult` keeps the server's DICOM JSON object (`dicomJSON: Data?`, `attributes`), `UPSOutputFormat.dicomJSON` ("dicom-json") renders it via `DICOMJSONModelFormatter` (PS3.18 2026a F.2); dicom-wado `ups --search` / `--get` drop their separate raw fetch (safe: (0008,0018) is Return Key Type 1 in PS3.4 Table CC.2.5-3, so no search object is lost; `--get` relies on D228); `DICOMwebClient.searchWorkitemsDICOMJSON` stays public; test WebClientDeferredRowsTests.test_D213. |
| D214 | dicom-gateway | `Sources/dicom-gateway/GatewayListener.swift:217` (`forwardToPACS`) and `HL7ToDICOMConverter.createBasicDICOMFile` / `FHIRConverter.createBasicDICOMFile` | The listener's (not implemented, D103) forward path still builds the template-less Secondary Capture data set and discards it; when the forward is implemented it must take a template or an MWL-shaped output, not this data set | PS3.3 2026a Table A.8-1 | Low | ✅ Closed 2026-10-01 (`8e018761`): GatewayListener.forwardToPACS no longer calls HL7ToDICOMConverter.convert(templateFile: nil); it builds nothing and writes "Not forwarded to host:port: … message not converted" with the P-GATEWAY-SC reason (shared GatewayOutputRules.noImageReason, PS3.3 2026a Table A.8-1) and "C-STORE forwarding is not implemented (D103)"; startup warning updated; TemplateRequirementTests +1 |
| D215 | DICOMWeb | Sources/DICOMWeb/DataExchangeWorkflow.swift:214-216 | (unverified, for the DICOMWeb agent) `decode` builds the main data set from every decoded element and reads (0002,0010) from it, so a DICOM JSON / XML input that carries group 0002 elements would have them written into the main data set as well as the File Meta; PS3.10 7.1 puts group 0002 only in the File Meta Information | PS3.10 2026a 7.1, Table 7.1-1 | Low | ✅ Closed 2026-10-01 (`d6baa4f7`) |
| D216 | DICOMCore (J2KSwift dependency) | .build/checkouts/J2KSwift/Sources/J2KCodec/J2KEncoderPipeline.swift:6454 (writeCODMarker "SGcod — Progression order: always LRCP (0)"); DICOMCore/J2KCodestreamInspector.swift (conformingToHTJ2KRPCL) | J2KSwift ignores `J2KEncodingConfiguration.progressionOrder` (packets always LRCP, COD 0), writes no TLM, and caps decomposition levels by the smaller image dimension (4100×100 gets 5 levels, base 129×4 — conformant only under the "width or height" reading). DICOMCore relabels RPCL / inserts TLM only for single-layer default-precinct output; a multi-layer or precinct-partitioned encode would stay LRCP. Upstream request to J2KSwift: emit packets in the configured progression order, an option to write TLM (and PLT), and honour `decompositionLevels` up to the larger dimension | PS3.5 2026a 10.18.1 | Low | ⏳ Open |
| D217 | DICOMCore (JLISwift dependency) | Sources/DICOMCore/JLICodec.swift:205-215 (lossy cfg, `.yuv444`); NativeJPEGCodec.swift encodeToJPEG | .4.50/.4.51 colour output is YCbCr (4:4:4 JLI; ImageIO subsampling unchecked) while Photometric Interpretation stays RGB; Table 8.2.1-1 allows YBR_FULL_422 (4:2:2) or RGB (components stored as RGB). Needs either a JLISwift lossy mode without colour transform (Adobe APP14 transform 0) so PI RGB is true, or an owner decision to encode 4:2:2 and relabel YBR_FULL_422 in TransferSyntaxConverter and CompressionManager | PS3.5 2026a 8.2.1, Table 8.2.1-1 | Low | ✅ Closed 2026-10-01 (`d2e9e3f8`, `d37433f0`): owner decision applied — colour .50 written YCbCr 4:2:2 and labelled YBR_FULL_422 (Planar Configuration 0) in TransferSyntaxConverter and CompressionManager; .51 colour and ImageIO colour refused (see D190) |
| D218 | DICOMCore (J2KSwift dependency) | .build/checkouts/J2KSwift/Sources/J2KCodec/J2KEncoderPipeline.swift:6467 (`useMCT = image.components.count >= 3`); DICOMCore/TransferSyntaxConverter.swift (transcodeToEncapsulated) | J2KSwift applies the multi-component transformation to every 3-component image, so native YBR_FULL → JPEG 2000 / HTJ2K writes MCT = 1 under PI YBR_FULL ("No other Value of Photometric Interpretation than YBR_RCT or YBR_ICT is permitted when SGcod Multiple component transformation type is 1"; YBR_FULL needs MCT 0). DICOMCore relabels only RGB sources. Needs a J2KSwift option to disable MCT, or a YBR_FULL→RGB conversion before encode | PS3.5 2026a 8.2.4, Table 8.2.4-1 | Medium | ✅ Closed 2026-10-01 (`d2e9e3f8`, `d37433f0`), with one deviation: lossy J2K / HTJ2K of native YBR_FULL converts to RGB first (new `YBRFullConversion`, inverse computed from the PS3.3 2026a C.7.6.3.1.2 forward matrix, half full scale 2^(Bits Stored−1)) and is labelled YBR_ICT (PS3.5 2026a 8.2.4: YBR_FULL needs "SGcod Multiple component transformation type … 0"; J2KSwift always writes 1). **Deviation:** a reversible (lossless) J2K / HTJ2K encode of YBR_FULL is refused with a message citing 8.2.4, not converted: the YBR→RGB step rounds (8.2.4 itself calls YBR_FULL with MCT 0 the way to convert "without further loss"), so a "Lossless Only" output would not preserve the source pixels. Before, it wrote MCT = 1 under YBR_FULL. If the owner prefers convert-and-label-YBR_RCT for lossless too, flip `lossless` handling in `TransferSyntaxConverter.rgbForJPEG2000Encode`. Upstream alternative unchanged: a J2KSwift option to write MCT 0 |
| D219 | DICOMKit | Sources/DICOMKit/Compression/CompressionManager.swift:520-535 (encodePixelDataInPlace), 660-684 (decodePixelDataInPlace), 141-148 (transferSyntaxName) | The D193 defect in the DICOMKit compression path (dicom-compress, DICOMStudio): RGB → J2K/HTJ2K keeps PI RGB over a COD MCT = 1 codestream, and J2K decode keeps YBR_RCT / YBR_ICT over RGB samples (only JPEG .50/.51 and XYB are relabelled). Reuse `J2KCodestreamInspector.codingStyle(in:)` as TransferSyntaxConverter now does. Also: its name for a both-capable UID is the "(lossy)" SelectableEncoding label; PixelDataError now uses the plain A-1 name | PS3.5 2026a 8.2.4, Table 8.2.4-1, 8.2.14 | High | ✅ Closed 2026-10-01 (`d37433f0`): with D185 / D186 — CompressionManager labels by the codestream on encode and relabels to RGB on decode, matching TransferSyntaxConverter (D193). The "(lossy)" display name for a bare .91/.93/.203 in `transferSyntaxDisplayName` is left as is (it is a SelectableEncoding label, not a Table A-1 name claim; info lines already use the intent-derived name) |
| D220 | dicom-mpps | Sources/dicom-mpps/DICOMMPPSCommand.swift:127-168 | `dimseNStatusNames` duplicates DICOMNetwork's generated Annex C table and `rethrowNamed`'s `.storeFailed` branch is dead since MPPS failures throw `mppsOperationFailed` (e3caf409); the CLI's `describe` could call `DIMSEServiceStatusText.describe(_:service:)` | PS3.7 2026a Annex C; PS3.4 Table F.7.2-2 | Low | ✅ Closed 2026-10-01 (`4739989f`): dicom-mpps's own 22-code status table and the dead `.storeFailed` re-wrap removed; warnings worded by DICOMNetwork `DIMSEServiceStatusText.describe` (N-SET: PS3.4 2026a Table F.7.2-2, N-CREATE: PS3.7 2026a Annex C), failures arrive worded in `mppsOperationFailed` (e3caf409); CLI test against the in-process mock SCP: 0106H "Failure (0x0106): Invalid Attribute Value", 0107H "Warning (0x0107): Attribute List warning" (MWLMPPSCLIEndToEndTests) |
| D221 | DICOMToolbox | Sources/DICOMToolbox/Models/ToolRegistry.swift:213-217 | dicom-anon `--profile` picker offers basic / clinical-trial / research (default basic): clinical-trial and research now select the deprecated legacy lists with a stderr note, and ps315 / legacy-* are not offered; Tests/DICOMToolboxTests/Phase3FileProcessingTests.swift:353, :429 and Phase8IntegrationTests.swift:181 assert the old values | PS3.15 2026a E.1 | Low | ⏳ Open |
| D222 | DICOMKit | Sources/DICOMKit/PresentationState/GrayscalePresentationStateBuilder.swift:1 (marker "Type 2 Content Creator Name (Table 10-12)"); Sources/DICOMKit/Segmentation/SegmentationBuilder.swift (comment "Content Creator's Name 2"); Tests/DICOMKitTests/Segmentation/SegmentationBuilderTests.swift:927 ("Content Creator's Name is Type 2") | Content Creator's Name (0070,0084) is Type 3 in 2026a (Table 10.9.3-1 via Table 10-12, also in Segmentation Table C.8.20-2); writing it empty is legal, but the comments, marker and test message cite Type 2 | PS3.3 2026a Tables 10-12, 10.9.3-1, C.8.20-2 | Low | ✅ Closed 2026-10-01 (`60937f6b`): GSPS builder marker and comment, the Segmentation builder comment and the Segmentation / Color PS test messages now cite Content Creator's Name (0070,0084) as Type 3 (PS3.3 2026a Table 10.9.3-1 via Table 10-12); still written zero length when unknown, which PS3.5 2026a 7.4.5 allows for Type 3; wording only |
| D223 | DICOMKit | Sources/DICOMKit/Scripting/ScriptEngine.swift:529, 532, 535, 563, 566, 623, 631 (templates); Sources/dicom-script/main.swift:12 | the workflow / pipeline / anonymize templates and README pass `*.dcm` globs and `> file` redirection, but the runner execs `/usr/bin/env <tool> args` without a shell, so neither is expanded; dicom-validate and dicom-convert take one path argument | — (template plumbing) | Low | ✅ Closed 2026-10-01 (`1a4e5455`): the workflow / pipeline / anonymize templates and the dicom-script README pass `<dir> --recursive` instead of `*.dcm` and drop `> file` (the runner execs `/usr/bin/env <tool>` without a shell); `ScriptValidator` reports globs and redirection as passed literally; `ScriptParser.tokenize` removes the quotes of a quoted argument (the query template's `--patient-name "DOE*"` reached dicom-query with its quotes) (ScriptRoundTripTests: no glob/redirect in templates, --recursive declared by dicom-validate / -convert / -anon) |
| D224 | DICOMKit | Sources/DICOMKit/JP3DVolumeBridge.swift:232-235 (`makeDICOMSeries`) | slice Image Position (Patient) is `originX\originY\originZ + i·spacingZ` from a `J2KVolume` whose origin `makeVolume` never sets (0,0,0) and that has no orientation; Image Orientation (Patient) not written | PS3.3 2026a C.7.6.2.1.1, Table C.7-10 | Low | ✅ Closed 2026-10-01 (`c4808d1c`): `makeVolume` sets the `J2KVolume` origin to the first slice's Image Position (Patient); `makeDICOMSeries` places slice i at origin + i·spacing along the template's Image Orientation (Patient) normal (PS3.3 2026a C.7.6.2.1.1 Equation C.7.6.2.1-1), always writes Image Orientation (Patient) with the position (1\0\0\0\1\0 when the template has none), and Pixel Spacing, Rows, Columns and Slice Location (Table C.7-10, C.7.6.2.1.2) (JP3DSliceGeometryTests, sagittal round trip) |
| D225 | dicom-report | Sources/dicom-report/ReportGenerator.swift:573 | WAVEFORM items print `channelNumbers` only; the Multiplex Group of each (M,C) pair (now in `referencedChannels`) is not shown | PS3.3 2026a C.18.5.1.1 | Low | ✅ Closed 2026-10-01 (`4739989f`): WAVEFORM items print `channels (M,C) (1,0) (3,2) (3,3)` from `referencedChannels`; PS3.3 2026a C.18.5.1.1 example 0001 0000 0003 0002 0003 0003 pinned (SRRenderingTests) |
| D226 | DICOMKit | Sources/DICOMKit/Video/VideoConformanceValidator.swift:342 (`validate`) | MPEG2 MP@HL (1.2.840.10008.1.2.4.101) constraints of 8.2.6 not checked: "Rows (0028,0010) shall be either 720 or 1080", "Columns … 1280 if Rows is 720, or … 1920 if Rows is 1080", aspect_ratio_information 0011 (16:9); a 720x576 Main Level stream is accepted under .101 (before the D178 fix it was rejected only by the inverted level check) | PS3.5 2026a 8.2.6 | Low | ✅ Closed 2026-10-01 (`ada8def3`): `VideoConformanceValidator.validate` refuses .101 / .107 unless Rows/Columns are 720/1280 or 1080/1920 and aspect_ratio_information is 0011 (PS3.5 2026a 8.2.6); new violations `mpeg2HighLevelGeometryNotPermitted`, `mpeg2AspectRatioNotPermitted`, `VideoStreamInfo.mpeg2AspectRatioInformation`; `selectTransferSyntax` no longer offers .101 to MP@H-14 ("not supported by this Transfer Syntax") or another geometry (MPEG2HighLevelAndSystemsStreamTests) |
| D227 | DICOMKit | Sources/DICOMKit/Video/MP4ContainerParser.swift:142 (`detectContainer`) | MPEG-2 Program Stream (pack header 00 00 01 BA) and PES input are not recognised (`.unknown`, "not a recognized video container"), though 8.2.5/8.2.6 list MPEG-PS and MPEG-PES as permitted MPEG-2 containers | PS3.5 2026a 8.2.5, 8.2.6 | Low | ✅ Closed 2026-10-01 (`ada8def3`): MPEG-2 Program Stream (pack header 00 00 01 BA, MPEG-1/-2 markers) and PES (00 00 01 E0-EF) are recognised: new `MPEG2SystemsLayer`, `MP4ContainerParser.mpeg2SystemsLayer(_:)` / `mpeg2VideoElementaryStream(_:)` / `mpeg2AudioStreamIDs(_:)`; `VideoProbe` probes the video PES payloads (sequence header, frame count, audio stream count) and names the container (`VideoProbeResult.mpeg2SystemsLayer`, `containerDisplayName`); the systems stream is encapsulated unchanged (PS3.5 2026a 8.2.5 / 8.2.6 list MPEG-PS and MPEG-PES). `VideoContainer` keeps its cases (PS / PES report `.elementaryStream`) because DICOMStudio switches on it exhaustively (D237) |
| D228 | DICOMWeb | Sources/DICOMWeb/UPS/UPSResults.swift:247, DICOMwebClient.swift:1525, UPS/UPSClient.swift:170 | `retrieveWorkitemResult(uid:)` failed ("Failed to parse workitem JSON") on a conforming Retrieve Workitem response, which follows the N-GET column of PS3.4 Table CC.2.5-3 where SOP Instance UID (0008,0018) is "Not allowed"; now the requested UID stands in (dicom-wado `ups --get`, DICOMStudio) | PS3.18 2026a 11.5.3.3; PS3.4 2026a Table CC.2.5-3 | Medium | ✅ Closed 2026-10-01 (`f4262b4f`) |
| D229 | DICOMKit | `Sources/DICOMKit/DICOMDIRWriter.swift` (`Builder.addFile`), `Sources/DICOMCore/DirectoryRecord.swift:353-460` | STUDY records never carry Study ID (0020,0010) (Type 1) or Accession Number (0008,0050) (Type 2). Study Date/Time (1), Series Number (1) and Instance Number (1) are written only when the instance has them. An FSC must supply them (PS3.11 D.3.3.1 note) | PS3.3 2026a Tables F.5-2, F.5-3, F.5-4; PS3.11 2026a D.3.3.1 | Medium | ✅ Closed 2026-10-01 (`23e8227d`): STUDY records carry Study ID (Type 1) and Accession Number (Type 2); every record gets the Type 1 / 1C / 2 / 2C keys of its PS3.3 2026a table (F.5-1 to F.5-49, 145 keys generated by the new `Scripts/generate_dicomdir_record_keys.py`, `--check`), Type 2 zero length when unknown; per PS3.11 2026a D.3.3.1 the FSC supplies a missing Study ID / Series Number / Instance Number (ordinal) and Study Date / Time (Series, Acquisition or Content Date / Time, else 19000101 / 000000, `Builder.suppliesMissingStudyDateTime`, false refuses); any other missing Type 1 key refuses the instance (`Refusal.missingRecordKey`) (DICOMDIRRecordKeysTests) |
| D230 | DICOMKit | `Sources/DICOMKit/DICOMDIRWriter.swift` (`Builder.addFile`) | Every instance gets an IMAGE record whatever its SOP Class. SR, KOS, presentation states, RT, encapsulated documents, waveforms and others need their own record type (SR DOCUMENT, KEY OBJECT DOC, PRESENTATION, RT DOSE, ENCAP DOC, WAVEFORM, …) with that type's Type 1 keys (e.g. F.5-25 Completion/Verification Flag, Content Date/Time, Concept Name Code Sequence) | PS3.3 2026a F.4 Table F.4-1; F.5.19-F.5.49 key tables | Medium | ✅ Closed 2026-10-01 (`23e8227d`): each instance gets the record type PS3.3 2026a F.5 names for its SOP Class — 174 SOP Classes of PS3.4 Tables B.5-1 / GG.3-1 mapped by script from the F.5 IOD links and the IOD IEs (SR DOCUMENT, KEY OBJECT DOC, PRESENTATION, WAVEFORM, WF PRESENTATION, ENCAP DOC, RT DOSE / STRUCTURE SET / PLAN / TREAT RECORD, PLAN, RADIOTHERAPY, SPECTROSCOPY, RAW DATA, REGISTRATION, FIDUCIAL, SURFACE, SURFACE SCAN, TRACT, MEASUREMENT, VALUE MAP, STEREOMETRIC, ASSESSMENT, ANNOTATION; HANGING PROTOCOL, PALETTE, IMPLANT*, INVENTORY as root records), with that type's keys (SR: Completion / Verification Flag, Content Date / Time, Verification DateTime, Concept Name Code Sequence, HAS CONCEPT MOD Content Items); the 5 SOP Classes with no record type in 2026a (Defined / Performed Procedure Protocol, Protocol Approval) are refused (`Refusal.noDirectoryRecordType`); new public `DICOMDIRRecordKeys`, `DICOMDirectory.Statistics.instanceRecordCount` |
| D231 | DICOMKit | `Sources/DICOMKit/DICOMDIRWriter.swift:109` | Writes File-set Consistency Flag FFFFH when `isConsistent == false`; 2026a defines only 0000H and says "The Value FFFFH shall never be present" | PS3.3 2026a Table F.3-3 (0004,1212) | Low | ✅ Closed 2026-10-01 (`23e8227d`): `DICOMDIRWriter` always writes File-set Consistency Flag 0000H (PS3.3 2026a Table F.3-3: "The Value FFFFH shall never be present") |
| D232 | DICOMKit | `Sources/DICOMKit/DICOMDIRReader.swift:151-161` | Only IMAGE/PRESENTATION/SR DOCUMENT/WAVEFORM/RT DOSE/RT STRUCTURE SET/RT PLAN records are nested under SERIES. KEY OBJECT DOC, ENCAP DOC, RT TREAT RECORD, SPECTROSCOPY, RAW DATA, REGISTRATION, … (Table F.4-1 series-level types) and root-level HANGING PROTOCOL/PALETTE/IMPLANT* records fall into `default: break` and are dropped on read | PS3.3 2026a F.4, Table F.4-1 | Medium | ✅ Closed 2026-10-01 (`23e8227d`): the reader keeps every Series-level record type of PS3.3 2026a Table F.4-1 under its SERIES (KEY OBJECT DOC, ENCAP DOC, RT TREAT RECORD, SPECTROSCOPY, RAW DATA, REGISTRATION, FIDUCIAL, VALUE MAP, STEREOMETRIC, PLAN, MEASUREMENT, SURFACE, TRACT, ASSESSMENT, RADIOTHERAPY, ANNOTATION, WF PRESENTATION) and HANGING PROTOCOL / PALETTE / IMPLANT / IMPLANT ASSY / IMPLANT GROUP / INVENTORY at the root; `DirectoryRecordType.rootLevelTypes` / `allowedChildTypes` / `isRetired` made public |
| D233 | DICOMKit | `Sources/DICOMKit/DICOMDIRProfileRules.swift` | Profile enforcement covers SOP Class + Transfer Syntax only. The per-profile image attribute values / photometric pairs (A.3-3, B.3-3, B.3-4, C.3-2, E.3-3–E.3-6, K.3-3, K.3-4, L.4-1, L.4-2) and the "Multi-frame Composite IODs" restriction of the MPEG rows are not checked | PS3.11 2026a Annexes A, B, C, E, I, K, L, M, N | Low | ✅ Closed 2026-10-01 (`23e8227d`): PS3.11 2026a Tables A.3-3, B.3-3, B.3-4, E.3-3 to E.3-6, K.3-3, L.4-1 (Value text parsed: values, ranges, "up to", relations, the K.3-3 conditional), K.3-4 / L.4-2 (specialized Type 2) and C.3-2 (Photometric Interpretation / Transfer Syntax pairs) generated by `generate_dicomdir_profile_rules.py` and applied by `addFile` to the instances each section names (`DICOMDIRProfileRules.imageAttributeProblems`, `Refusal.imageAttributeValues`); the "Multi-frame Composite IODs" rows (MPEG syntaxes) admit only instances with Number of Frames (`refusal(...isMultiFrame:)`) |
| D234 | DICOMCore | Sources/DICOMCore/J2KSwiftCodec.swift:584 (verifyEncodedRoundTrip) | `--codec jpeg2000` / `htj2k` (lossy intent on .91 / .203) with `--quality maximum` plans an irreversible 9-7 encode (J2KRoutePlanner:143 keys .both UIDs off `preferLossless` only), but the round-trip check demands bit-exact output whenever `quality.isLossless`, so the encode fails "J2KSwift lossless round-trip validation failed" for content the 9-7 path does not reproduce exactly (seen on a 16×16 converted-YBR gradient; an RGB gradient happened to pass). The check should key off the planned intent (`J2KRoutePlanner.planEncode(...).intent.isLossless`) | PS3.5 2026a 8.2.4 (reversible vs irreversible), A.4.4 | Low | ✅ Closed 2026-10-01 (`3b7d09de`): the bit-exact round-trip check follows the planned encode (`EncodePlan.lossless`, PS3.5 2026a 8.2.4 reversible 5-3); irreversible 9-7 at maximum quality no longer refused; test fails with the old check |
| D235 | DICOMCore | Sources/DICOMCore/TransferSyntaxConverter.swift:1390 (parseDataElement) | A defined-length SQ was returned with raw bytes and no Items; DICOMWriter re-encodes SQ from Items, so every defined-length sequence (all `DataSet.write` output) was written empty on any dicom-convert / TransferSyntaxConverter transcode (.50, .90, RLE, Implicit VR LE reproduced) | PS3.5 2026a 7.5.2 ("Explicit Length"), 7.5 | High | ✅ Closed 2026-10-01 (`59936daf`): Items parsed; values marked with the source byte order; test_DCORE5_sequencesSurviveConvert |
| D236 | DICOMKit | Sources/DICOMKit/Anonymization/ConfidentialityEngine.swift:196 (apply, `.replaceDummy` on SQ) | Without the Clean Structured Content Option, Content Sequence (0040,A730) Basic Profile "D" keeps every Content Item with only its Table E.1-1 attributes processed: Text Value (0040,A160) (not a Table E.1-1 row), Concept Code Sequence and numeric values survive verbatim, so free text in an SR (e.g. Accession Number, Comment, Finding items) is released unchanged by the Basic Profile. E.1-1a D allows "a dummy value"; E.3.4 note: a de-identifier without the Option "creates significant risk" for SR. Proposal: in the Basic Profile, apply the Table E.3.4-1 Basic column (or replace TEXT/PNAME/DATE values with dummies) to Content Items even without the Option, or warn when an SR Content Sequence is kept | PS3.15 2026a Table E.1-1 (0040,A730) D, Table E.1-1a, E.3.4 | Medium | ✅ Closed 2026-10-01 (`bb4f551a`): row confirmed against the 2026a text (Table E.1-1 (0040,A730) Basic Prof. "D", Clean Struct. Cont. Opt. "C"; Text Value (0040,A160) has no Table E.1-1 row; E.1.1 "These action codes are applicable to both Sequence and non-Sequence Attributes; in the case of Sequences, the action is applicable to the Sequence and all of its contents"; E.1.1 "Textual Content Items of Structured Reports ... are specifically addressed"; E.3.4 "A de-identifier that does not implement this Option creates significant risk"). `ConfidentialityEngine` without the Option now applies the D to the Content Items: Items kept (Relationship Type, Value Type, Concept Name, references, so the SR IOD stays valid, E.1.1), Date/Time/DateTime/Person Name (0040,A121/A122/A120/A123) D and UID (0040,A124) U by their own rows (temporal Options still apply), and the value attributes Table E.1-1 does not list get a dummy of their VR: Text Value, NUM Numeric Value / Floating Point / Rational Numerator 0 and Rational Denominator 1 (Item and Measured Value Sequence, PS3.3 Table C.18.1-1), TABLE Cell Values Sequence Selector <VR> Values (PS3.3 Table C.18.10-1), number of values kept; codes kept (E.1.1 note on Code Sequences); nested Content Sequences the same. C (Table E.3.4-1) only under the Option (unchanged). Acquisition Context Sequence (0040,0555) Basic X/Z (removed) and Specimen Preparation Sequence (0040,0610) Basic Z (emptied) already matched. dicom-anon help/README describe the Basic behaviour. Tests: ConfidentialityOptionsTests (19 pass, 1 new + 1 rewritten), ConfidentialityProfileTests (24 pass, incl. every-row test), dicom_anonTests (21 pass, end-to-end Basic SR added); generate_confidentiality_profile.py --check: 651 rows + 4 patterns, 479 E.3.10-1, 211 E.3.4-1 match; diffe11.py fixture unchanged at 642 + 5 SQ D rows kept with scrubbed items (its Content Sequence item is a code item, not a Content Item). |
| D237 | DICOMKit | Sources/DICOMKit/Video/MP4ContainerParser.swift:20 (`VideoContainer`) | MPEG-PS / MPEG-PES are reported as `.elementaryStream` (named by `MPEG2SystemsLayer` / `containerDisplayName`) because a new enum case would break DICOMStudio's exhaustive switch (ViewerNonImageContentView.swift:422); add `.mpegPS` / `.mpegPES` once Studio's switch has a default or the cases | PS3.5 2026a 8.2.5, 8.2.6 | Low | ⏳ Carried (DICOMStudio dependency): adding `.mpegPS` / `.mpegPES` to the public `VideoContainer` enum breaks the exhaustive switch in `ViewerNonImageContentView.swift:422`, which the owner is editing; add the cases together with a `default` there in the DICOMStudio pass |
| D238 | DICOMKit | Sources/DICOMKit/Video/VideoConformanceValidator.swift (`validate`) | MPEG2 MP@HL frame rates of the 8.2.6 table (25, 30, 50, 60 Hz; 1080-line progressive only at 25 / 30) and the MP@ML Table 8-1 frame rate / maximum geometry pairs are not checked | PS3.5 2026a 8.2.5 Table 8-1, 8.2.6 | Low | ✅ Closed 2026-10-01 (`73691331`): `VideoConformanceValidator.validate` refuses MPEG2 MP@ML outside PS3.5 2026a Table 8-1 (30 fps incl. 29.97 per Note 4 at most 480 x 720; 25 fps at most 576 x 720: `mpeg2FrameRateNotPermitted`, `mpeg2MainLevelGeometryExceedsMaximum`) and MP@HL outside Table 8-2 (25, 30, 50, 60 and 30/1.001, 60/1.001 per Note 2) or Rows 1080 at 50 / 60 (8.2.6 Note 4, Table 8-3: 1080 x 1920 only at 25 / 30, P or I); `selectTransferSyntax` no longer offers .100 / .101 to such streams; no frame rate in the stream = not checked. Tables public (`mpeg2MainLevelFormats`, `mpeg2HighLevelFrameRates`, `mpeg2HighLevel1080FrameRates`) and diffed by the new `Scripts/diff_kit.py` check `mpeg2-frame-rates` (Tables 8-1 / 8-2 / 8-3, 8 values) (MPEG2FrameRateTableTests 8) |
| D239 | DICOMKit | Sources/DICOMKit/DICOMDIRRecordKeys.swift (`keyElements`) | The per-profile "Additional DICOMDIR Keys" tables are not applied (only the STD-GEN Image Type / Referenced Image Sequence 1C keys are copied); STD-XABC-CD / STD-XA1K need Icon Image Sequence (Type 1, F.7), Calibration Image, Institution Name / Address, Performing Physicians' Name, Patient's Birth Date / Sex; STD-CTMR needs the Image Plane / Frame of Reference keys and Rows / Columns on IMAGE records | PS3.11 2026a A.3.3, B.3.3, D.3.3.1, E.3.3 (Additional Keys tables); PS3.3 F.7 | Medium | ✅ Closed 2026-10-01 (`cd1cc509`): `generate_dicomdir_profile_rules.py` now also generates the "Additional DICOMDIR Keys" Tables A.3-2 (9), B.3-2 (10), D.3-2 (2), E.3-2 (7), H.3-2 (19), I.3-2 (9) (top-level rows, Notes verbatim, 1C condition classified, unknown Notes stop the script), the Annex → table mapping read from the X.3.3 xrefs (J, M, N apply H.3-2; C, G, K, L none) and the Icon Images sections A.3.3.2 / B.3.3.2 / E.3.3.3; `DICOMDirectory.Builder` adds them to PATIENT / SERIES / instance records (Type 1 copied, Type 2 copied or zero length, 1C per Notes: present, non-zero, subordinate objects (filled as later instances arrive), Shared Functional Groups (5200,9229), XA Image, BIPLANE A / B); STD-XABC-CD / STD-XA1K IMAGE records get a 128 x 128 8-bit MONOCHROME2 Icon Image Sequence per PS3.3 2026a F.7 / C.7.6.1.1.6 (instance's own when it conforms, else made from the representative frame: Representative Frame Number or one third through, window / MONOCHROME1 / colour luminance / PALETTE LUT, aspect kept, OB); STD-CTMR optional icons only copied; a key that cannot be supplied refuses the instance (new `Refusal.missingProfileKey`); new `DICOMDIRProfileRules.additionalKeyTableLabel(for:)`; dicom-dcmdir README updated (DICOMDIRProfileKeysTests 9) |
| D240 | DICOMKit | Sources/DICOMKit/DICOMDIRReader.swift:100 (`parseDirectoryRecordSequence`) | The record tree is rebuilt from the order of the Directory Record Sequence, not from Offset of the Next Directory Record / Referenced Lower-Level Directory Entity; a DICOMDIR whose records are not in depth-first order is misread; PRIVATE records are dropped | PS3.3 2026a F.3.2.2, Table F.3-3, F.6.1 | Low | ✅ Closed 2026-10-01 (`59d43e1c`): `DICOMDIRReader.read(from:)` measures the byte offset of every Directory Record Sequence item from the first byte of the File Meta Information (Explicit / Implicit VR Little Endian, defined or undefined lengths, nested sequences) and builds the tree from (0004,1200), (0004,1400), (0004,1420) per PS3.3 2026a F.3.2.2 / Table F.3-3; sequence order only when the offsets cannot be followed (no file bytes, root offset 0, an offset not on an item, a cycle); PRIVATE records kept where the offsets place them (Table F.4-1, F.6.1); Record In-use Flag other than 0000H read as FFFFH (Table F.3-3, was inactive) (DICOMDIRReaderOffsetTests 5, DICOMDIRReaderRecordTypeTests updated) |
| D241 | DICOMKit | Sources/dicom-script/README.md (Examples 3, 5) | README examples still call `echo`, `exit 1` and `rm -rf`, which are not dicom-* tools (the validator reports them as unknown tools; the runner execs them without a shell) | — (documentation) | Low | ✅ Closed 2026-10-01 (`b0d55a65`): dicom-script README Example 3 else-branch runs `dicom-info ${INPUT_FILE}` (a failed command stops the script) instead of `echo` / `exit 1`, Example 5 checks the archive with `dicom-archive check --verify-files` / `stats` instead of `rm -rf`, the Conditional Logic else-branch no longer calls `echo`; Error Handling says `validate` reports other commands as unknown tools and the runner uses no shell (ScriptRoundTripTests: every command line of the Script Syntax / Examples blocks starts with dicom-, the five examples validate with no issue) |

### Rows handed to DICOMStudio

DICOMStudio's CLI Workshop runs the same DICOMKit engines and shared console types as the tools. So the Studio audit
inherits three kinds of work from this module.

**1. DICOMStudio halves of carried rows**

| Row | What Studio still has | Where |
|---|---|---|
| D9 | .4.110 called "JPEG XL Lossless Only" | `J2KTestBenchModels.swift:123,392` |
| D29 | `--profile` choices list STD-GEN-DVD / STD-GEN-USB | `CLIWorkshopViewModel.swift:1730`, `CLIWorkshopHelpers.swift:3128` |
| D56 | no Channel Source field for `dicom-video` | CLI Workshop video form |
| D42, D65 (viewer half), D68 | from earlier reports, unchanged | see DICOMPRINTKIT / DICOMRENDERKIT reports |

**2. Rows owned by DICOMStudio, opened here**

D85 (mpps placeholder and optional Modality), D88 (parity-test fixtures with wrong CID 9300 meanings), D114
(json/xml empty-attribute default), D127 (export contact-sheet/animate render path), D132 (dcmdir validate rules and
File-set ID default), D154 (split `--frames` help). Each row is in the Deferred findings table above.

**3. Workshop parity with CLI changes made here**

The CLI gained options, defaults or refusals that the Workshop forms do not offer yet. Each is additive or a fix in
the tool layer; the Workshop should mirror them:

| Tool | Change the Workshop must mirror | Commit |
|---|---|---|
| dicom-query | `--level image` (IMAGE wire value) | `695d961` |
| dicom-send | Failure statuses counted as failures; warnings tallied | `0efff87` |
| dicom-qr / dicom-retrieve | status text per PS3.4 Tables C.4-2/C.4-3 (`RetrieveStatusText.swift`; see P-QR-STATUS-TEXT) | `1f853e8`, `0b5a61a` |
| dicom-mwl / dicom-mpps | SPS Status terms; `create` requires `--modality`; CID 9300 examples | `f2db8f9`, `416de5a` |
| dicom-print / dicom-printscp | MAMMO media, token→wire value help, all Image Display Formats | `ceeb966`, `deb66db` |
| dicom-wado | `--transfer-syntax`, `--anonymize`, `--rows`, `--columns`, `--fuzzy-matching`; "IN PROGRESS" | `39da529` |
| dicom-json / dicom-xml | empty attributes kept by default; `--no-include-empty` | `78214e8`, `4a428da` |
| dicom-tags | `--set` VR and value-limit rules (`TagEditRules.swift`; engine still lacks them, D150) | `b091aa5` |
| dicom-dcmdir | File-set ID / File ID rules in `validate` | `a45fd45` |
| dicom-uid | `generate --uuid`; root validation | `788f620` |
| dicom-validate | `--iod` accepts Table A-1 keywords/UIDs | `606ef6d` |
| dicom-export | shared render path for contact-sheet/animate; frame-rate default | `104202f` |
| dicom-anon | ps315 honours `--remove/--replace/--keep`; `--retain-full-dates`, `--retain-modified-dates`; refusals | `06717c9` |
| dicom-image / dicom-pixedit | `--conversion-type`; derived-image output; rescaled window | `1c9aaba8`, `698de5df` |
| dicom-pdf | `--conversion-type`, `--burned-in-annotation`, `--hl7-instance-identifier`; Encapsulated Document Length | `3c739850` |
| dicom-video | `--audio-channel-source`; value warnings | `8eebfab`, `cfc81d9f` |
| dicom-ai | `--segment-category`, `--segment-type`, `--algorithm-version`; TID 1500 SR | `3fe88bd`, `1ff3934e` |
| dicom-measure | spacing source and UCUM units | `0fbc334f` |
| dicom-3d / dicom-viewer | LPS planes, Pixel Spacing order, `--frame-number` | `aa35a519`, `ffbc8d20` |

D237 waits for DICOMStudio: give `ViewerNonImageContentView.swift:422` a `default` (or the new cases) so `VideoContainer` can gain `.mpegPS` / `.mpegPES`.

Engine rows (DICOMKit, DICOMNetwork, DICOMWeb, DICOMCore, DICOMPrintKit) stay with their modules; fixing them fixes the
Workshop too. Where the CLI works around an engine bug (D112/D137/D162/D165 via D175, D150, D158), the Workshop is
still affected until the engine row is closed.


**4. Workshop follow-ups from the approved P-items (2026-10-01)**

The P-items changed option names, defaults, refusals and JSON keys in the CLI. The Workshop forms and shared-console
callers in DICOMStudio must mirror them. Most urgent: `SecurityModel.cliFlag` sends `--profile basic`, which now runs
the PS3.15 Basic Profile (UIDs replaced) instead of the old "remove direct identifiers" list its label describes; map it
to `legacy-basic` or relabel it. Also: Studio presets or history that use `JPEG2000Lossless`, `HTJ2KLossless` or
`JPEGXLLossless` now resolve to the Table A-1 UIDs (.90 / .201 / .110); `FilmDestination` is now a struct, so any
exhaustive `switch` needs a `default`; `SplitMergeWorkshopCLIParityTests` filters the CLI-only `--frames` deprecation
line until the Workshop mirrors P-SPLIT-1.

Per batch, as reported by the implementing agents:

**codec**
- dicom-convert Workshop picker: `DICOMConverter.cliTokens` now lists `JPEG2000Reversible`, `HTJ2KReversible`, `JPEGXLReversible` in place of `JPEG2000Lossless` / `HTJ2KLossless` / `JPEGXLLossless`; saved presets / command history holding the old three names now resolve to .90 / .201 / .110 — migrate them to the `…Reversible` names (or show `TransferSyntax.reassignedKeywordNote(for:)`).
- dicom-convert Workshop: add the `--frame-number` field (1-based) and stop emitting `--frame`; use `DICOMConverter.invalidFrameNumberMessage`; a directory run with a failed file must report failure (exit 1).
- dicom-compress Workshop: the decompress / batch syntax picker must offer only explicit-le, implicit-le, deflate and refuse other names; `info --json` output already matches (shared `CompressionConsole.infoJSON`).
- dicom-j2k Workshop: `--frame-number` instead of `--frame` on info / validate / roi / benchmark / compare, "Frame number N" labels, new JSON keys; drop the three `j2k-part2-*` transcode targets from the picker.
- Observed, not changed (Studio): `CompressionAlgorithmHelpers.algorithms` (DataExchangeView.swift ~1075) labels `jpeg-lossless` as ".4.70" (it is .57) and comments `j2k-lossless` as ".90" (it is .91 reversible).

**derived**
- The CLI Workshop has no parameter definitions for dicom-report, dicom-measure, dicom-3d or dicom-viewer (only shell categories in CLIShellFoundationModel/Helpers). If they are added: offer `--style` (not `--template`), `--include-summary`, `pixel --frame-number` (1-based), `--unit um`, `mpr --oblique-normal/--oblique-point`, interpolation nearest/linear only, no `volume` subcommand, and viewer `--frame-number` rather than `--frame`.
- ROI/measurement display (Components/ROIHelpers.swift:336-358, "mm²"/"cm²"): to match the CLI, show the UCUM code (`mm2`, PS3.16 CID 7461) with the symbol, and offer µm/`um`.
- Frame labels: MultiViewportViewModel.swift:219 "Frame N/M", ImageMetadataHelpers.swift:112 "Frame N / M", CineControlsView.swift:43. These are already 1-based; for consistency with the CLI rule they could read "Frame number N".
- VolumeVisualizationModel.swift:30 offers `BICUBIC` interpolation and :242 an oblique MPR configuration. Check that bicubic is a real kernel (the CLI deprecated its fake `cubic`) and that oblique output geometry follows Equation C.7.6.2.1-1 like the CLI.

**file**
- dicom-json / dicom-xml: mark the `no-sort-keys` / `no-keywords` parameters (CLIWorkshopHelpers.swift:2840, 2914) as deprecated, and print the same stderr lines (`DICOMJson.deprecationNotes` / `DICOMXml.deprecationNotes` text).
- dicom-diff: the Workshop executor (CLIWorkshopViewModel.swift:6120) returns `hasDifferences ? 1 : 0`. It must return 2, with the stderr text, when a file is missing or unreadable.
- dicom-dcmdir: Workshop create must refuse an invalid File-set ID with exit 1. Move `FileSetRules.fileSetIDRefusal` into DICOMKit if it should be shared. It must also print the `--profile` deprecation note (`FileSetRules.profileDeprecationNote`), and the profile picker should offer only PS3.11 identifiers.
- dicom-uid: Workshop lookup (CLIWorkshopViewModel.swift:1473-1519) still uses `UIDManager.uidTypeDescription`. Switch text output to `UIDManager.tableA1UIDType(of:)` and JSON to the `uidType:` overloads of `UIDConsole.lookupEntryJSON` / `listingJSON`.
- dicom-study / dicom-archive: the output comes from shared StudyReport / ArchiveStore, so the Workshop gets the new keys automatically. Parameter help in the Workshop should name the keyword keys and the deprecated old keys.
- dicom-export: the Workshop (CLIWorkshopViewModel.swift:4592 `validatedFrameRange`, 4686 `buildOrganizedPath(patientName:)`, now deprecated) needs:
  - the `frame-number`, `start-frame-number` and `end-frame-number` parameters;
  - the deprecation notes and the exit-1 conflict;
  - a switch to `buildOrganizedPath(…patientID:issuerOfPatientID:…)`;
  - `apply-window` marked deprecated on contact-sheet and bulk.
- dicom-split: add a `frame-numbers` parameter (`SplitConsole.parseFrameNumberSelection`, `headerLines(frameNumbers:)`). Print `SplitConsole.framesDeprecatedLine` when `frames` is used, and refuse both with `framesAndFrameNumbersConflictMessage` (exit 1). Then:
  - remove the `framesDeprecatedLine` filter in `SplitMergeWorkshopCLIParityTests.normalize` (Tests/DICOMStudioTests, added by `ba21553f`);
  - add `--frame-numbers` cases to that matrix.

**net**
- C-MOVE / C-GET result (CLIWorkshopViewModel ~8720-8911, `NetworkConsole.cMoveResult(status:)`): pass
  `DIMSEServiceStatusText.describe(result.status, service: .cMove / .cGet)` instead of the in-app status string, and use
  `DIMSEServiceStatusText.subOperationCounts` for failure detail — the Studio half of D76.
- Send (`NetworkConsole.sendSummary` ~8424): count Warning-class C-STORE responses and call
  `sendSummary(…warnings:)`; print `NetworkConsole.sendFileWarningLine(status:)` after a warning file line (parity with
  dicom-send, else the Compare-CLI diff shows the new lines).
- Retrieve panel: Priority picker (low/medium/high) and a relational-retrieve toggle → `RetrieveConfiguration(…priority:
  extendedNegotiation:)` + `DICOMRetrieveService.move/get(configuration:keys:)`, and
  `NetworkConsole.retrieveHeader(…priority:relationalRetrieval:)` (shown only when non-default). Allow series/instance
  UID without study UID when the toggle is on.
- Query-Retrieve panel: Priority picker (query and resume); `--parallel` now meaningful (batches; lines in study order).
- Query panel: add `dicom-json` to the format values (CLIWorkshopHelpers.swift:514 lists table/json/csv/compact) and build
  the formatter with `DICOMQueryResultFormatter(format:level:csvHeader:dicomJSONEncoder:)` passing
  `{ try DICOMJSONEncoder(configuration: .init(prettyPrinted: true)).encodeMultiple($0) }`; add a CSV-keywords toggle
  (`csvHeader: .keyword`). Table labels change automatically (shared formatter) — update any Studio screenshots/docs.
- MWL panel / CLI-parity MWL comparator: may switch to the keyword keys (`ScheduledProcedureStepID` for `SPSID`); old keys
  still present.
- QR state files: shared `QRStudyInfo` now writes `ModalitiesInStudy`; any Studio code that displays the saved study's
  modality should read `modalitiesInStudy` (fallback `modality`).

**pixel**
- **Anon (urgent: behaviour change).** `SecurityModel.swift` `cliFlag` maps `.basic`, `.hipaaeSafeHarbor` and `.custom` to `"basic"`. That now runs the PS3.15 Basic Profile (ps315), not the "Basic (Remove Direct Identifiers)" list the label describes. `.clinicalTrial`/`.research` print a deprecation note. Either map them to `legacy-*` or move the picker to `ps315` (default) + `legacy-*` (deprecated). `CLIWorkshopHelpers.swift:4885-4890` presets say "basic profile" for `--profile basic`; reword as the PS3.15 Basic Profile. Mark `--retain-dates` deprecated in the Workshop form.
- **Image.** The Workshop form for dicom-image should refuse the PS3.5 Table 6.2-1 / Section 9 violations (UID syntax, LO/PN length and backslash, IS range) instead of passing them to `ImageConverter`.
- **Pixedit.** The Workshop form should refuse a `--fill-value` outside the stored range and a window width < 1, instead of clamping.
- **Video.** The Workshop form should refuse a modality other than ES/GM/XC for the chosen type, a sex outside M/F/O, a non-DA birth date, and the two Fragmentable HEVC UIDs, all with exit 1. The CLI-only help suffixes are in `Sources/dicom-video/OptionConformance.swift`, and `VideoConsole.Help` is unchanged. Offer one Audio Channel Source per audio track (`VideoWorkflow.Metadata.audioChannelSources`). The count check already runs inside `VideoWorkflow.convert` / `runBatch`, so Studio gets the refusal automatically once it sets the field.

**webprint**
- CLI Workshop dicom-wado: add `--change-state` (keep `--update` labelled deprecated) and `dicom-json` to the query/ups output-format pickers; the in-app UPS change-state path must refuse SCHEDULED with the same message (`WADOOptionRules.changeStateTarget` is CLI-local — lift to DICOMWeb if Studio wants one source). QIDO `dicom-json` already works through `QIDOOutputFormat(rawValue:)`; UPS needs `DICOMwebClient.searchWorkitemsDICOMJSON` / `retrieveWorkitem` + `DICOMJSONModelFormatter` (UPSOutputFormat was not extended).
- PrintSettingsView film-destination Picker: offer bins beyond 2 (`FilmDestination.bin(n)`, e.g. a stepper); `PrintViewModel` compiles unchanged (Studio target builds).
- Print / Print SCP status panes that show JSON (PrinterManagementView via PrintConsoleFormatter) now also show the keyword keys — no code change needed; labels still D90.
- CLI Workshop dicom-gateway: hl7-to-dicom / fhir-to-dicom must require a template file (same refusal).

---

## G1 Network

### dicom-echo

Commands: dicom-echo · files: DICOMEcho.swift · bucket C1 (plumbing adapter over DICOMNetwork.DICOMVerificationService)

Compared: PS3.7 2026a 9.1.5.1.4 (C-ECHO status values, 5 named codes, dumped from the DocBook), PS3.5 2026a Table 6.2-1 (VR AE: 16 bytes maximum), PS3.8 2026a 9.1.1 (well-known port 104, registered port 11112), PS3.6 2026a Table A-1 (Verification SOP Class 1.2.840.10008.1.1, the two uncompressed transfer syntaxes named in `--diagnose`). The tool holds no literal of its own; every standard value it prints comes from DICOMNetwork (DIMSEStatus, VerificationConfiguration, NetworkConsole). `Scripts/diff_cli.py --tool dicom-echo`: 11 checks ok, 0 FAIL.

**Input contract**

| Option | DICOM concept | 2026a reference | Allowed per standard | Code accepts | Default (std) | Default (code) | Verdict |
|---|---|---|---|---|---|---|---|
| `<host>` | TCP transport address (plumbing) | PS3.8 9.1.1 | hostname / IP (`host[:port]`) | `String` | — | — | plumbing |
| `--port` | TCP port (plumbing) | PS3.8 9.1.1: well-known 104, registered 11112 | 1–65535 | `UInt16?` | 104 if privileged ports allowed, else 11112 | 11112 | plumbing (matches the PS3.8 registered port) |
| `--aet` | Calling AE Title | PS3.8 7.1.1.3; PS3.5 Table 6.2-1 VR AE | ≤16 bytes, no backslash/control chars, not all spaces | `String` (checked by DICOMNetwork.AETitle) | none | required | plumbing |
| `--called-aet` | Called AE Title | PS3.8 7.1.1.4; PS3.5 Table 6.2-1 VR AE | as above | `String` | none | `"ANY-SCP"` | plumbing — "ANY-SCP" is a tool convention, not a standard value; noted |
| `-c, --count` | number of C-ECHO operations (one association each) | PS3.7 9.1.5 | — | `Int` > 0 | — | 1 | plumbing |
| `--timeout` | ARTIM / socket timeout | PS3.8 9.1.2 (ARTIM) | — | `Int` seconds | — | 30 | plumbing |
| `--stats` | round-trip statistics | — | — | `Bool` | — | false | plumbing |
| `--diagnose` | connectivity probe (prints Implementation Class UID / Version Name, PS3.7 Tables D.3-1 / D.3-3, from VerificationConfiguration) | PS3.7 Annex D.3 | — | `Bool` | — | false | plumbing |
| `-v, --verbose` | — | — | — | `Bool` | — | false | plumbing |

Counts: matched 0, wrong 0, missing 0, extra 0, plumbing 9.

**Output contract**

| Field | DICOM source | Encoding (standard) | Encoding (code) | Verdict |
|---|---|---|---|---|
| `Status: …` (echoSuccess / echoStatusFailure) | C-ECHO-RSP Status (0000,0900) | PS3.7 9.1.5.1.4: Success 0000H; Refused: SOP Class not supported 0122H; Duplicate invocation 0210H; Unrecognized operation 0211H; Mistyped argument 0212H | `DIMSEStatus.description`: "Success (0x0000)", "Refused: SOP Class not supported (0x0122)"; 0210/0211/0212 → "Unknown status (0x0210)" | match for 0000 / 0122; 0210–0212 → deferred (DIMSEStatus, DICOMNetwork) |
| `✅ C-ECHO successful` / `❌ C-ECHO failed` | success = status 0000 (`VerificationResult.success = status.isSuccess`) | PS3.7 9.1.5.1.4 | shared NetworkConsole | match |
| `SOP Class: Verification (1.2.840.10008.1.1)` (--diagnose) | PS3.6 Table A-1 | "Verification SOP Class" | abbreviated name, correct UID (shared NetworkConsole) | match (abbreviation) |
| `Transfer Syntaxes: Explicit VR Little Endian, Implicit VR Little Endian` (--diagnose) | PS3.6 Table A-1 | "Explicit VR Little Endian", "Implicit VR Little Endian: Default Transfer Syntax for DICOM" | shared NetworkConsole | match |
| `Implementation Class UID` / `Implementation Version` (--diagnose) | PS3.7 Tables D.3-1 / D.3-3 | UID ≤64 bytes; version name ≤16 bytes | `1.2.826.0.1.3680043.9.7433.1.1` / `DICOMKIT_001` (VerificationConfiguration) | plumbing (implementation identity) |
| exit `0` / `1` / `64` | — | — | 0 all succeeded, 1 any failure (`ExitCode(1)`), 64 usage (`ValidationError`, e.g. `--count 0`) | plumbing; README corrected to list 64 |

Findings: none in the tool. README exit-code list lacked 64 (fixed, docs only).

Deferred (DICOMNetwork): see D-rows in the dicom-send section (DIMSEStatus 0210/0211/0212/0117 unnamed).

P-items: none.

Marker: `// NEMA-verified: 2026a, checked 2026-10-01 — carries no DICOM-standard data of its own: every option is plumbing (host, port, AE Titles, count, timeout, stats, diagnose, verbose); the C-ECHO statuses it prints (PS3.7 2026a 9.1.5.1.4: 0000 Success, 0122 Refused: SOP Class not supported, 0210 Duplicate invocation, 0211 Unrecognized operation, 0212 Mistyped argument) are rendered by DICOMNetwork.DIMSEStatus; port 11112 is the registered DICOM port of PS3.8 2026a 9.1.1; AE Titles are PS3.5 Table 6.2-1 VR AE (16 bytes), checked by DICOMNetwork.AETitle`

Tests: none needed (no behaviour change). `swift build --product dicom-echo` ok; `check_nema_markers.py Sources/dicom-echo`: 1/1.

Commit: 0c845da `docs(cli): dicom-echo verified against DICOM 2026a (marker, README exit codes)`.

### dicom-send

Commands: dicom-send · files: DICOMSend.swift, SendExecutor.swift · bucket B2 (C-STORE status handling contradicted PS3.4 Table B.2-1)

Compared: PS3.4 2026a Table B.2-1 (C-STORE Response Status Values, 7 rows dumped by script: Failure A7xx / A9xx / Cxxx, Warning B000 / B007 / B006, Success 0000); PS3.7 2026a 9.1.1.1.9 (C-STORE status prose: Warning = "was able to store … but detected a probable error", 0122 Refused: SOP Class not supported); PS3.7 2026a Table 9.3-1 (C-STORE-RQ Priority: LOW = 0002H, MEDIUM = 0000H, HIGH = 0001H — 3 of 3 match DIMSEPriority); PS3.6 2026a Table A-1 (transfer-syntax UIDs accepted by `--transfer-syntax` via DICOMCore.TransferSyntax.parse, verified in the DICOMCore report); PS3.5 Table 6.2-1 (VR AE); PS3.8 9.1.1 (port 11112). `Scripts/diff_cli.py --tool dicom-send`: 11 checks ok, 0 FAIL (the status bug is behaviour, not a literal, so only the contract row caught it).

**Input contract**

| Option | DICOM concept | 2026a reference | Allowed per standard | Code accepts | Default (std) | Default (code) | Verdict |
|---|---|---|---|---|---|---|---|
| `<host>` | TCP transport address | PS3.8 9.1.1 | `host[:port]` | `String` | — | — | plumbing |
| `--port` | TCP port | PS3.8 9.1.1 (104 well-known, 11112 registered) | 1–65535 | `UInt16?` | 104 / 11112 | 11112 | plumbing |
| `--aet` | Calling AE Title | PS3.8 7.1.1.3; PS3.5 Table 6.2-1 VR AE | ≤16 bytes | `String` (DICOMNetwork.AETitle) | none | required | plumbing |
| `--called-aet` | Called AE Title | PS3.8 7.1.1.4; PS3.5 Table 6.2-1 | ≤16 bytes | `String` | none | `"ANY-SCP"` (tool convention) | plumbing |
| `<paths>` | files to send (PS3.10 files; SOP Class / Instance / Transfer Syntax read from File Meta) | PS3.10 Table 7.1-1 | — | `[String]` | — | — | plumbing |
| `-r, --recursive` | — | — | — | `Bool` | — | false | plumbing |
| `--verify` | C-ECHO before sending | PS3.4 Annex A | — | `Bool` | — | false | plumbing |
| `--retry` | retry on a thrown error or a Failure-class status | — | — | `Int` ≥ 0 | — | 0 | plumbing |
| `--dry-run` | — | — | — | `Bool` | — | false | plumbing |
| `-v, --verbose` | — | — | — | `Bool` | — | false | plumbing |
| `--timeout` | ARTIM / socket timeout | PS3.8 9.1.2 | — | `Int` s | — | 60 | plumbing |
| `--priority` | Priority (0000,0700) of C-STORE-RQ | PS3.7 Table 9.3-1 | LOW 0002H, MEDIUM 0000H, HIGH 0001H | `low`→0x0002, `medium`→0x0000, `high`→0x0001 (DIMSEPriority) | none (required field) | medium | match (help now cites the hex values) |
| `--transfer-syntax` | Transfer Syntax Name of the proposed Presentation Context | PS3.8 7.1.1.13; PS3.6 Table A-1 | any Table A-1 Transfer Syntax UID | UID or DICOMCore alias (`TransferSyntax.parse`); unknown → usage error | none (file's own) | nil = file's own syntax | match |

Counts: matched 2, wrong 0, missing 0, extra 0, plumbing 11.

**Output contract**

| Field | DICOM source | Encoding (standard) | Encoding (code) | Verdict |
|---|---|---|---|---|
| per-file `✅ (rtt)` / `❌ <error>` | C-STORE-RSP Status (0000,0900) | PS3.4 Table B.2-1: Success 0000 stored; Warning B000/B006/B007 stored with deviation; Failure A7xx/A9xx/Cxxx (+0122, PS3.7 9.1.1.1.9) not stored | **was wrong**: every `StoreResult` returned by the engine was counted and printed as ✅ regardless of status (a Failure response gave ✅ and exit 0). Now: Failure → `SendError.storeFailed(status)` ("C-STORE response status Refused: Out of resources (0xA700) — not stored (PS3.4 Table B.2-1)"), retried, counted as failed, exit 1; Warning → ✅ plus `    ⚠️ Stored with warning: <status>` and a `Stored with warning: N` summary line | wrong → fixed (StoreOutcome, 7 rows of B.2-1 + 0122 pinned by StoreOutcomeTests) |
| `Priority: medium` (sendHeader) | option word | — | shared NetworkConsole prints the CLI word | plumbing |
| `Transfer Syntax: <uid>` (sendHeader) | PS3.6 Table A-1 UID | UID | UID | match |
| `Transfer Summary` (Total files / Succeeded / Failed / Bytes sent / …) | — | — | shared NetworkConsole; no warning count (tool prints its own line) | plumbing (see P-SEND-SUMMARY) |
| exit `0` / `1` / `64` | — | — | 0 all stored (incl. warnings); 1 any failed file (`SendError.partialFailure`) or pre-flight error; 64 usage (`ValidationError`: negative `--retry`, unknown `--transfer-syntax`, no files) | plumbing; README said 2 for partial — corrected |

Findings
1. **Failure statuses counted as success** — `SendExecutor.sendFiles` incremented `successCount` for every returned `StoreResult` and never read `result.success` / `result.status`; `DICOMStorageService.store` returns a `StoreResult` (does not throw) for A7xx / A9xx / Cxxx / 0122. Fixed in the tool: `StoreOutcome(status:)` classifies per Table B.2-1; `sendFile` throws `SendError.storeFailed` for the Failure class so `--retry` applies; Warning class printed and tallied. Test: `Tests/dicom-sendTests/StoreOutcomeTests.swift` (6 tests: 0000; B000/B006/B007/B001/BFFF; A700/A701/A7FF/A900/A901/A9FF/C000/C123/CFFF/0122; error text; priority values; priority help).
2. `--priority` help did not say which Priority values the words map to — now cites PS3.7 Table 9.3-1.
3. README exit codes claimed 2 for partial success (code: 1) — corrected; new "C-STORE Response Statuses" section.

Deferred findings (other modules)
| ID | Module | File:line | Problem | Standard | Severity |
|---|---|---|---|---|---|
| D-new | DICOMNetwork | Sources/DICOMNetwork/StorageService.swift:829 (`success: response.status.isSuccess`, also the preferredTransferSyntax path) | `StoreResult.success` is false for a Warning-class response (B000/B006/B007) although PS3.7 9.1.1.1.9 says the SCP "was able to store the composite SOP Instance"; and a Failure-class response is returned as a result, not thrown, so every caller must re-classify the status (dicom-send did not) | PS3.4 2026a Table B.2-1; PS3.7 9.1.1.1.9 | medium |
| D-new | DICOMNetwork | Sources/DICOMNetwork/DIMSEStatus.swift:122–170 (`from(_:)`) | 0210 Duplicate invocation, 0211 Unrecognized operation, 0212 Mistyped argument, 0117 Invalid SOP Instance (PS3.7 9.1.1.1.9 / 9.1.5.1.4) have no named case and print as "Unknown status (0x0210)" | PS3.7 2026a 9.1.1.1.9, 9.1.5.1.4, Annex C | low |
| D-new | DICOMNetwork | Sources/DICOMNetwork/NetworkConsoleFormatter.swift:143 (`sendFileResultSuffix`) and :155 (`sendSummary`) | no rendering for a Warning-class C-STORE status and no warning tally; dicom-send prints a tool-side line, so Studio parity diverges for warning responses | PS3.4 Table B.2-1 Warning class | low |

P-items
- **P-SEND-SUMMARY**: add a `warnings:` parameter to `NetworkConsole.sendSummary` / a warning variant of `sendFileResultSuffix` (shared DICOMNetwork type, Studio parity) so the Warning class is rendered on both sides; dicom-send would then drop its tool-side lines.

Markers
- DICOMSend.swift: `// NEMA-verified: 2026a, checked 2026-10-01 — --priority values diffed against PS3.7 2026a Table 9.3-1 (C-STORE-RQ Priority: LOW 0002H, MEDIUM 0000H, HIGH 0001H: 3 of 3 match via DIMSEPriority); --transfer-syntax accepts a PS3.6 Table A-1 UID or a DICOMCore.TransferSyntax alias; port 11112 is the registered DICOM port of PS3.8 2026a 9.1.1; AE Titles are PS3.5 Table 6.2-1 VR AE (16 bytes), checked by DICOMNetwork.AETitle`
- SendExecutor.swift: `// NEMA-verified: 2026a, checked 2026-10-01 — C-STORE response handling diffed against PS3.4 2026a Table B.2-1 (7 rows: Success 0000 stored; Warning B000/B006/B007 stored and reported; Failure A7xx/A9xx/Cxxx not stored, counted as failed) and PS3.7 9.1.1.1.9 (0122 Refused: SOP Class not supported); status text comes from DICOMNetwork.DIMSEStatus`

Tests: `swift test --filter StoreOutcomeTests` — 6 tests, 0 failures. `swift build --product dicom-send` ok; `check_nema_markers.py Sources/dicom-send`: 2/2.

Commits: 0efff87 `fix(cli): dicom-send treats a C-STORE Failure status as a failed file (PS3.4 Table B.2-1)`; f24869c `fix(cli): dicom-send test target and CHANGELOG entry` (Package.swift `dicom-sendTests` target + CHANGELOG bullet, which 0efff87 missed).

### dicom-query

Commands: dicom-query · files: DICOMQuery.swift, QueryExecutor.swift · bucket B2 (level naming contradicted PS3.4; JSON/CSV docs wrong)

Compared: PS3.4 2026a Tables C.6.1-1 / C.6.2-1 (Query/Retrieve Level values: PATIENT, STUDY, SERIES, IMAGE — 4 rows / 3 rows dumped by script; the code's `QueryLevel` sends exactly these 4 values); Tables C.6-1 (Patient level, 17 rows), C.6-3 (Series level, 5 rows), C.6-4 (Composite Object Instance level, 20 rows), C.6-5 (Study Root Study level, 65 rows) — every attribute an option maps to (via DICOMNetwork.DICOMQueryService.buildQueryKeys) is listed at that level or covered by "All other Attributes at … Level"; PS3.4 C.4.1.1.3.1 (Identifier structure), C.4.1.2.1 (hierarchical SCU baseline: only the Unique Keys of the levels above), C.2.2.2.4 (wild cards `*` `?`), C.2.2.2.5 (date ranges `d1-d2`, `-d1`, `d1-`); PS3.4 Table C.4-1 (C-FIND status, 7 rows: engine-handled, the tool prints none); PS3.3 C.7.3.1.1.1 (Modality Defined Terms: via DICOMCore.Modality, text-diffed in the DICOMCore report; the tool keeps no list); PS3.18 Annex F (JSON model — not claimed by the tool). `Scripts/diff_cli.py --tool dicom-query`: 11 checks ok, 0 FAIL. The surface extractor missed `--modality` (help built by `ArgumentHelp(stringLiteral: ModalityOptionValidator.helpText("filter"))`, two levels of nested parentheses); the `ATTR` regex in Scripts/diff_cli.py was widened by one nesting level (19 options now listed).

**Input contract**

| Option | DICOM concept | 2026a reference | Allowed per standard | Code accepts | Default (std) | Default (code) | Verdict |
|---|---|---|---|---|---|---|---|
| `<host>` | TCP transport address | PS3.8 9.1.1 | `host[:port]` | `String` | — | — | plumbing |
| `--port` | TCP port | PS3.8 9.1.1 (104 / 11112) | 1–65535 | `UInt16?` | 104 / 11112 | 11112 | plumbing |
| `--aet` | Calling AE Title | PS3.8 7.1.1.3; PS3.5 Table 6.2-1 VR AE | ≤16 bytes | `String` (AETitle) | none | required | plumbing |
| `--called-aet` | Called AE Title | PS3.8 7.1.1.4 | ≤16 bytes | `String` | none | `"ANY-SCP"` (tool convention) | plumbing |
| `-l, --level` | Query/Retrieve Level (0008,0052) | PS3.4 Tables C.6.1-1 / C.6.2-1; C.4.1.1.3.1 | PATIENT, STUDY, SERIES, IMAGE | `patient`, `study`, `series`, `image` (+ alias `instance`) → `QueryLevel` PATIENT/STUDY/SERIES/IMAGE on the wire | none | study | **wrong → fixed**: help/validation/warning said "instance"; wire value was already IMAGE. `image` added, `instance` kept |
| `--patient-name` | Patient's Name (0010,0010) | C.6-5 R (Study Root), C.6-1 R; wild cards C.2.2.2.4 | PN; `*` `?` | `String?` → matching key (PN) | — | — | match |
| `--patient-id` | Patient ID (0010,0020) | C.6-5 R; C.6-1 U | LO | `String?` | — | — | match |
| `--study-date` | Study Date (0008,0020) | C.6-5 R; range C.2.2.2.5 | DA; `d1-d2`, `-d1`, `d1-` | `String?` passed verbatim (DA) | — | — | match (help now lists the open ranges) |
| `--study-uid` | Study Instance UID (0020,000D) | C.6-5 U; C.4.1.2.1 | UI, single value / UID list | `String?` | — | — | match (required at SERIES/IMAGE by `validate()`) |
| `--series-uid` | Series Instance UID (0020,000E) | C.6-3 U; C.4.1.2.1 | UI | `String?` | — | — | match (required at IMAGE) |
| `--accession-number` | Accession Number (0008,0050) | C.6-5 R | SH | `String?` | — | — | match |
| `--modality` | STUDY: Modalities in Study (0008,0061) C.6-5 O; SERIES: Modality (0008,0060) C.6-3 R | PS3.3 C.7.3.1.1.1 Defined Terms | Defined Terms (not Enumerated — unknown value warns) | `String?` via ModalityOptionValidator / DICOMCore.Modality | — | — | match |
| `--strict-modality` | reject a non-Defined-Term | PS3.3 C.7.3.1.1.1 | — | `Bool` | — | false | plumbing |
| `--study-description` | Study Description (0008,1030) | C.6-5 O; C.2.2.2.4 | LO; wild cards | `String?` | — | — | match |
| `--referring-physician` | Referring Physician's Name (0008,0090) | C.6-5 O | PN | `String?` | — | — | match |
| `-f, --format` | output rendering | — | — | `table`, `json`, `csv`, `compact` | — | table | plumbing (see output contract) |
| `--timeout` | ARTIM / socket timeout | PS3.8 9.1.2 | — | `Int` s | — | 60 | plumbing |
| `--verbose` | — | — | — | `Bool` | — | false | plumbing |
| `--include-parent-keys` | non-baseline: parent-level return keys at SERIES/IMAGE | PS3.4 C.4.1.2.1 forbids them for a baseline SCU | — | `Bool` | — | false | extra (deliberate, documented as non-baseline) |

Counts: matched 9, wrong 1 (fixed), missing 0, extra 1 (documented), plumbing 8.

**Output contract**

| Field | DICOM source | Encoding (standard) | Encoding (code) | Verdict |
|---|---|---|---|---|
| JSON object keys (`--format json`) | attribute tags of each C-FIND-RSP Identifier | PS3.18 F.2.2: `"00100010": {"vr":"PN","Value":[…]}` (keyword keys are not standard) | `"(0010,0010)": "SMITH^JOHN"` — tag string → decoded string (DICOMNetwork.DICOMQueryResultFormatter) | tool-specific summary, now documented as such in the README (README previously showed `"(0010,0010) Patient's Name"` keys that the code never produced); see P-QUERY-JSON |
| CSV header (`--format csv`) | attribute tags | PS3.6 keywords/names would be the natural labels | `(0008,0020),(0008,1030),…` sorted by tag | tool-specific; README corrected |
| table column labels (`--format table`) | Patient's Name, Patient ID, Patient's Birth Date, Patient's Sex, Number of Patient Related Studies, Study Date, Study Description, Modalities in Study, Number of Study Related Series, Series Number, Modality, Series Description, Series Date, Number of Series Related Instances, Instance Number, SOP Class UID, Rows×Columns, Number of Frames | PS3.6 Table 6-1 names | "Patient Name", "Patient ID", "Birth Date", "Sex", "Studies", "Date", "Description", "Modalities", "Series", "Series Number", "Modality", "Instances", "Instance Number", "SOP Class", "Dimensions", "Frames" (shared formatter) | abbreviations, 2 match PS3.6 verbatim; shared DICOMNetwork type with Studio parity → P-QUERY-COLUMNS |
| `Query Level: instance` (verbose header) | Query/Retrieve Level (0008,0052) | IMAGE (Table C.6.2-1) | `NetworkConsole.levelName(.image)` = "instance" | deferred (DICOMNetwork NetworkConsoleFormatter.swift:834) |
| `Information Model: Patient Root` / `Study Root` (verbose) | PS3.4 C.6.1 / C.6.2 | PATIENT → Patient Root; else Study Root | QueryExecutor | match |
| stderr `Warning: … cannot be matched at IMAGE level …` | PS3.4 C.4.1.2.1 | level value | now `level.queryLevel.rawValue` (was "INSTANCE") | wrong → fixed |
| `--level series requires --study-uid` / `--level image (instance) requires --study-uid and --series-uid` | PS3.4 C.4.1.2.1 | Unique Key of each level above | `validate()` | match |
| `Total: N study(ies)` etc. | — | — | shared formatter | plumbing |
| C-FIND status (Pending FF00/FF01, Success 0000, Failure A700/A900/Cxxx, Cancel FE00) | PS3.4 Table C.4-1 | — | consumed by DICOMNetwork.DICOMQueryService (not printed by the tool; a Failure surfaces as a thrown error with `DIMSEStatus.description`) | engine (verified in the DICOMNetwork report) |
| exit `0` / `1` / `64` | — | — | 0 completed (empty result set included); 1 thrown error (network, rejection, Failure status); 64 usage (`ValidationError`) | plumbing; README said 1 = validation, 2 = connection — corrected |

Findings
1. `--level` named the bottom level "instance" in help, in the `validate()` message and in the C.4.1.2.1 warning ("at INSTANCE level"), while PS3.4 Tables C.6.1-1 / C.6.2-1 name it IMAGE and the wire value was already IMAGE. Fixed: `QueryLevelOption` cases are patient/study/series/image with `instance` as an alias (`init?(argument:)`), help cites (0008,0052) and the tables, the warning prints `level.queryLevel.rawValue`. Test: `Tests/dicom-queryTests/QueryLevelOptionTests.swift` (7 tests: 4 wire values; alias; rejection; allValueStrings; help; validate(); warning text).
2. README documented JSON keys as `"(0010,0010) Patient's Name"` and CSV headers with names; the code emits bare `(GGGG,EEEE)` tags. README corrected and the format declared a tool-specific summary (not PS3.18 Annex F).
3. README exit codes (1 validation / 2 connection) did not match ArgumentParser (64 / 1). Corrected.
4. Help for `--study-date`, `--patient-name`, `--study-description`, `--include-parent-keys` now cite the tag and PS3.4 clause (C.2.2.2.4 / C.2.2.2.5); SERIES/INSTANCE → SERIES/IMAGE.

Deferred findings (other modules)
| ID | Module | File:line | Problem | Standard | Severity |
|---|---|---|---|---|---|
| D-new | DICOMNetwork | Sources/DICOMNetwork/NetworkConsoleFormatter.swift:834 (`levelName`) | prints "instance" for `QueryLevel.image`; the verbose header therefore shows "Query Level: instance" while the Identifier carries IMAGE | PS3.4 2026a Tables C.6.1-1 / C.6.2-1 | low |

P-items
- **P-QUERY-JSON**: `--format json` emits a tool-specific `{"(GGGG,EEEE)": "string"}` summary. Proposed: a new additive value `--format dicom-json` producing the PS3.18 F.2 DICOM JSON Model (`"00100010": {"vr":"PN","Value":[{"Alphabetic":"…"}]}`) from the raw Identifier; needs `QueryOutputFormat` (shared DICOMNetwork enum, Studio parity) — not implemented. The existing `json` keys stay as they are.
- **P-QUERY-COLUMNS**: table/CSV labels to PS3.6 Table 6-1 names or keywords (e.g. "Patient's Name", "Patient's Birth Date", "Modalities in Study", "Number of Study Related Series", "SOP Class UID"); lives in `DICOMNetwork.DICOMQueryResultFormatter` (shared, byte-compared with Studio) — not implemented.

Markers
- DICOMQuery.swift: `// NEMA-verified: 2026a, checked 2026-10-01 — --level values diffed against PS3.4 2026a Tables C.6.1-1 / C.6.2-1 (PATIENT, STUDY, SERIES, IMAGE: 4 of 4 sent on the wire via QueryLevel; "instance" kept as a CLI alias of image); the match keys each option maps to checked against Tables C.6-1, C.6-3, C.6-4, C.6-5 (9 options, all listed at their level); wildcard and date-range help against C.2.2.2.4 / C.2.2.2.5; --modality terms via DICOMCore.Modality (C.7.3.1.1.1); --format json/csv keys are the tool's own "(GGGG,EEEE)" tag strings, not PS3.18 F.2 (documented in README)`
- QueryExecutor.swift: `// NEMA-verified: 2026a, checked 2026-10-01 — Information Model choice checked against PS3.4 2026a C.6.1 / C.6.2: PATIENT level → Patient Root (Table C.6.1-1), STUDY/SERIES/IMAGE → Study Root (Table C.6.2-1); the key tables themselves live in DICOMNetwork.DICOMQueryService.buildQueryKeys`

Tests: `swift test --filter QueryLevelOptionTests` — 7 tests, 0 failures. `swift build --product dicom-query` ok; `check_nema_markers.py Sources/dicom-query`: 2/2.

Commit: 695d961 `fix(cli): dicom-query --level names the PS3.4 IMAGE level; instance kept as alias` (Sources/dicom-query, Tests/dicom-queryTests, Package.swift `dicom-queryTests` target, CHANGELOG).

Note for the orchestrator: 695d961's Package.swift hunk also carried the concurrently edited `dicom-videoTests` target from the working tree; the dicom-video agent's own commit 8eebfab then added it a second time and 0efff87 removed the duplicate — HEAD has each target once. Scripts/diff_cli.py `status_codes(p7)` finds no rows because the PS3.7 Annex C status tables carry no `label` in the 2026a DocBook (only Tables 7.5-x / 9.x / D.3-x do); the service-specific status rows are in PS3.4 (B.2-1, C.4-1…).

### dicom-retrieve

Commands: dicom-retrieve · files: DICOMRetrieve.swift (C2), RetrieveExecutor.swift (C2), RetrieveStatusText.swift (A, new) · README.md
Commits: 1f853e8 (fix(cli): dicom-retrieve final status worded per PS3.4 2026a Tables C.4-2 / C.4-3, counters per PS3.7)
Standard dumped by script: PS3.4 2026a Tables C.4-2 (9 rows), C.4-3 (8 rows), C.6.1-1 (4), C.6.2.3-1 (3), C.6.1.3-1 (3), C.6-5 (Study level keys), C.5-1 (7 extended-negotiation items); PS3.7 2026a Tables 9.1-3, 9.1-4, 9.3-6, 9.3-7, 9.3-9, 9.3-10; PS3.6 Table A-1 (the 12 1.2.840.10008.5.1.4.1.2.* rows); PS3.8 2026a 9.1.2 (ports 104 / 11112); PS3.10 Table 7.1-1; sections C.4.2.2.1, C.4.3.2.1, C.4.2.1.4.2, C.2.2.2.4, C.2.2.2.5.

**Input contract** — matched 6, wrong 0, missing 0, extra 0, plumbing 10 (+2 n/a rows: Priority, extended negotiation)

| Option | DICOM concept | 2026a reference | Allowed per standard | Code accepts | Default (std) | Default (code) | Verdict |
|---|---|---|---|---|---|---|---|
| `<host>` | TCP transport address of the SCP | PS3.8 9.1.2 | hostname / IP | `String`, `host[:port]`, `pacs://` prefix stripped | — | — | plumbing |
| `--port` | DICOM UL TCP port | PS3.8 9.1.2: "well known" 104, "registered" 11112 | any port | `UInt16?` | none mandated | 11112 (the PS3.8 registered port) | plumbing; help now cites PS3.8 9.1.2 |
| `--aet` | Calling AE Title | PS3.8 Table 9-11; PS3.5 Table 6.2-1 VR AE (≤16 chars) | AE | `String`, validated by DICOMNetwork `AETitle` at association | — | required | plumbing |
| `--called-aet` | Called AE Title | PS3.8 Table 9-11; PS3.5 VR AE | AE | `String` | — | `"ANY-SCP"` | plumbing (no standard default) |
| `--study-uid` | Study Instance UID (0020,000D), unique key at level STUDY | PS3.4 Table C.6-5 (U); Table C.6.1-1 "STUDY" | UI | `String?` | — | — | match (help now names tag and level) |
| `--series-uid` | Series Instance UID (0020,000E), level SERIES; one unique key for each level above (study) required | PS3.4 C.4.2.2.1 / C.4.3.2.1; Table C.6.1-1 "SERIES" | UI | `String?`, requires `--study-uid` (exit 64) | — | — | match |
| `--instance-uid` | SOP Instance UID (0008,0018), level IMAGE (the option says "instance"; the wire value is `IMAGE` via `QueryLevel.image`, PS3.4 Table C.6.1-1 "Composite Object Instance Information — IMAGE") | PS3.4 Table C.6.1-1; C.4.2.2.1 | UI | `String?`, requires study + series (exit 64) | — | — | match (help now says "Query/Retrieve Level IMAGE") |
| `--uid-list` | several Study Instance UIDs, one C-MOVE/C-GET per UID | PS3.4 C.4.2.2.1 allows a UID list at STUDY level; the tool issues one request per UID | — | file path, `#` comments | — | — | plumbing |
| `--output` | directory for the Part 10 files written by C-GET | PS3.10 7.1 | — | path | — | `"."` | plumbing |
| `--method` | C-MOVE = Study Root Query/Retrieve Information Model - MOVE 1.2.840.10008.5.1.4.1.2.2.2; C-GET = … - GET …2.2.3 | PS3.4 C.4.2 / C.4.3; Table C.6.2.3-1; PS3.6 Table A-1 | the two SOP Classes (Patient Root …2.1.2/3 exist but are not selectable) | `c-move`, `c-get` (enum) | none | `c-move` | match (help now names the SOP Classes) |
| `--move-dest` | Move Destination (0000,0600), AE of the Storage SCP | PS3.7 Table 9.3-9 (M in C-MOVE-RQ, Table 9.1-4); PS3.4 C.4.2.2.1 | AE | `String?`, required for c-move (exit 64) | — | — | match |
| `--hierarchical` | output layout `<output>/<StudyInstanceUID>/<SeriesInstanceUID>/` (C-GET only) | — | — | `Bool` | — | false | plumbing; help said "patient/study/series" — fixed to what the code does |
| `--timeout` | socket timeout (not the PS3.8 ARTIM timer) | — | — | `Int` s | — | 60 | plumbing |
| `--parallel` | concurrent `--uid-list` retrievals | — | — | `Int ≥ 1` (exit 64 otherwise) | — | 1 | plumbing |
| `--transfer-syntax` | Transfer Syntax proposed for the Storage presentation contexts of C-GET (advisory for C-MOVE) | PS3.4 C.4.3.2.1 (SCU proposes the storage contexts); PS3.6 Table A-1 via shared `TransferSyntax.parse` | registered transfer syntaxes | any token the shared parser accepts; unknown → exit 64 | — | nil | match (shared parser verified in DICOMCore) |
| `-v, --verbose` | — | — | — | `Bool` | — | false | plumbing |
| *(no option)* Priority (0000,0700) | LOW 0002H / MEDIUM 0000H / HIGH 0001H | PS3.7 Table 9.3-9 / 9.3-6 | three values | not exposed; engine sends MEDIUM (RetrieveService.swift:958, 1267) | — | MEDIUM | n/a — P-RETRIEVE-PRIORITY |
| *(no option)* Extended negotiation | relational-retrieve, Enhanced Multi-Frame Image Conversion | PS3.4 Table C.5-1 items 1, 5; C.4.2.2.2 | — | not exposed; baseline SCU behaviour | — | baseline | n/a — P-RETRIEVE-EXTNEG |

**Output contract** — matched 8, wrong 0 (4 fixed in this commit), missing 0, extra 0, plumbing 5; shared-formatter rows → deferred

| Field | DICOM source | Encoding (standard) | Encoding (code) | Verdict |
|---|---|---|---|---|
| header `Calling AE Title:` / `Called AE Title:` / `Move Destination:` (shared `NetworkConsole.retrieveHeader`) | PS3.8 Table 9-11; (0000,0600) | names as PS3.6/PS3.7 | same | match |
| header `Level:` `Study` / `Series` / `Instance` (shared formatter, string chosen by CLI) | Query/Retrieve Level (0008,0052) | `STUDY` / `SERIES` / `IMAGE` (Table C.6.1-1) | display label; wire value is `QueryLevel.rawValue` (`IMAGE`) | match on the wire; display label "Instance" → deferred D-QR2 (shared console wording, kept for DICOMStudio parity) |
| `C-MOVE Result:` → `Status:` | Status (0000,0900) | PS3.4 Table C.4-2 "Service Status" + "Further Meaning" | `RetrieveStatusText.describe`: e.g. `Failure (0xA702): Refused: Out of resources - Unable to perform sub-operations`, `Warning (0xB000): Sub-operations Complete - One or more Failures`, `Success (0x0000): Sub-operations Complete - No Failures` | **fixed** (was `DIMSEStatus.description`: "Warning: Coercion of data elements (0xB000)", "Failed: Out of resources (0xA702)") |
| `C-MOVE Result:` → `Completed:` / `Failed:` / `Warnings:` (shared formatter) | (0000,1021) (0000,1022) (0000,1023) | Number of Completed / Failed / Warning Sub-operations (PS3.7 Table 9.3-10) | short labels | shared → deferred D-QR2 |
| stderr `Final C-MOVE|C-GET response: <status> — Number of Completed Sub-operations: n, Number of Failed Sub-operations: n, Number of Warning Sub-operations: n` | Tables 9.3-10 / 9.3-7 | PS3.7 names | PS3.7 names | **fixed** (was "n completed, n failed, n warning(s)") |
| stderr `Failed SOP Instance UID List (0008,0058), n UID(s):` + one UID per line | (0008,0058), PS3.4 C.4.2.1.4.2 | attribute name | attribute name + tag | **fixed** (was "Failed SOP Instance UIDs (n):") |
| error `C-MOVE final response <status> (<counters>); Failed SOP Instance UID List (0008,0058): …` (`RetrieveError.retrievalFailed`) | as above | — | PS3.4 / PS3.7 wording | **fixed** |
| `C-GET completed — n file(s) received` / 0-instance warning (shared `cGetSummary`) | — | — | — | plumbing |
| `Bulk retrieval complete: Success n / Failed n` (stderr) | — | — | — | plumbing |
| Part 10 file per received instance | PS3.10 Table 7.1-1 | Type 1: group length, (0002,0001), (0002,0002), (0002,0003), (0002,0010), (0002,0012) | all 6 written, no Type 3 rows; Implementation Class UID literal `1.2.826.0.1.3680043.9.7433.1.1` not compared with DICOMKit's registered one | match (6/6 Type 1) |
| exit `0` | final status Success (0000) and Number of Failed Sub-operations = 0 (PS3.4 C.4.2.2.1 / C.4.3.2.1) | — | `RetrieveResult.isSuccess` | match |
| exit `1` | Warning B000 / Failure A701 A702 A801 A900 Cxxx / Cancel FE00, any failed sub-operation, transport error, bulk partial failure | — | thrown `RetrieveError` → ArgumentParser exit 1 | match (README now documents it) |
| exit `64` | usage (no move-dest with c-move, series without study, …) | — | `ValidationError` → `ExitCode.validationFailure` | match (documented) |
| JSON | none emitted | — | — | — |

**Findings**
- Status text: `DIMSEStatus.description` is service-agnostic; for C-MOVE/C-GET 5 of the 8 final codes were worded differently from Table C.4-2/C.4-3 (A701, A702, A801, A900, B000, Cxxx). Fixed in the tool with `RetrieveStatusText` (17 rows generated from the DocBook; pinned by `QueryRetrieveCLIStandardTests.testRetrieveStatusTextCarriesPS34Tables2026a`). The engine text itself → deferred D-QR1.
- Counters and the Failed SOP Instance UID List were labelled informally → PS3.7 / PS3.6 names (tool-local lines).
- Help: levels, SOP Classes, Move Destination, ports, `--hierarchical` (said patient/study/series; the code lays out study/series and only for C-GET).
- README: `url` row was stale (`pacs://host:port`), exit codes now list 0 / 1 / 64 with the status classes.
- `Tests/DICOMToolsTests/DICOMRetrieveTests.swift` is not compiled by any target (`DICOMToolsTests` is commented out in Package.swift; the file is in `DICOMViewerTests`' exclude list) — its 32 tests have never run. Tests for this pass were placed in `Tests/DICOMNetworkTests/QueryRetrieveCLIStandardTests.swift` (compiled, no Package.swift change). Orchestrator: worth a report note for every dicom-* tool whose tests live there.

**Tests** — `swift test --filter QueryRetrieveCLIStandardTests`: 6 passed, 0 failed, 0 skipped (`testRetrieveStatusTextCarriesPS34Tables2026a`, `testRetrieveStatusTextCopiesAreIdentical`, `testRetrieveHelpNamesStandardConcepts`, `testRetrieveExitCodesForUsageAndTransportFailure` spawn the built product; usage → 64, refused connection with `--timeout 2` → 1). `swift build --product dicom-retrieve` ok. `check_nema_markers.py Sources/dicom-retrieve`: 3 files, 3 markers (2026a). `diff_cli.py --tool dicom-retrieve`: 0 FAIL.

**Deferred findings (DICOMNetwork)**
| ID | Module | file:line | Problem | Standard | Severity |
|---|---|---|---|---|---|
| D-QR1 | DICOMNetwork | Sources/DICOMNetwork/DIMSEStatus.swift:262-305 | `description` is service-agnostic: 0xB000 "Warning: Coercion of data elements" (the C-STORE meaning) where C-MOVE/C-GET mean "Sub-operations Complete - One or more Failures [or Warnings]"; 0xA701/0xA702 "Failed: Out of resources" vs "Refused: Out of resources - Unable to calculate number of matches / Unable to perform sub-operations"; 0xA801 "Failed: Move destination unknown" vs "Refused: Move Destination unknown"; 0xA900 "Identifier/Data does not match SOP Class" vs "Data Set does not match SOP Class"; Cxxx "unable to process / cannot understand" vs "Failed: Unable to process". A service-aware description (see P-QR-STATUS-TEXT) would fix the app console too. | PS3.4 2026a Tables C.4-2, C.4-3 | low (text) |
| D-QR2 | DICOMNetwork | Sources/DICOMNetwork/NetworkConsoleFormatter.swift:174-231 | `retrieveHeader` prints the level as "Instance" (value is IMAGE, Table C.6.1-1); `cMoveResult` labels the counters "Completed:/Failed:/Warnings:" instead of Number of Completed / Failed / Warning Sub-operations; `Remaining` (0000,1020) is never shown. Shared with DICOMStudio, so not changed in the CLI. | PS3.4 Table C.6.1-1; PS3.7 Table 9.3-10 | low |

**P-items**
- P-QR-STATUS-TEXT: hoist `RetrieveStatusText` (PS3.4 Tables C.4-2 / C.4-3 wording, PS3.7 counter names) into DICOMNetwork as public API so `DIMSEStatus` / `NetworkConsole` and DICOMStudio print the same text as the CLI; until then the CLI `Status:` line differs from the in-app console.
- P-RETRIEVE-PRIORITY: `--priority low|medium|high` (PS3.7 Table 9.3-9: LOW 0002H / MEDIUM 0000H / HIGH 0001H) needs `DICOMRetrieveService.move*/get*` to take a `DIMSEPriority` (public API; engine hardcodes `.medium`).
- P-RETRIEVE-EXTNEG: relational-retrieve / Enhanced Multi-Frame Image Conversion (PS3.4 Table C.5-1 items 1, 5) need engine API before a flag can exist.

**Markers**
- `Sources/dicom-retrieve/DICOMRetrieve.swift`: `// NEMA-verified: 2026a, checked 2026-10-01 — option surface compared with PS3.4 2026a: the 3 retrieve levels and their unique keys (Table C.6.1-1 STUDY/SERIES/IMAGE; Table C.6-5 Study Instance UID U key; C.4.2.2.1 / C.4.3.2.1 one unique key per level above the retrieve level), the 2 methods and their SOP Classes (Table C.6.2.3-1, Study Root MOVE/GET), Move Destination (0000,0600) per PS3.7 Table 9.3-9, ports 104 / 11112 per PS3.8 9.1.2; host, --called-aet default, --output, --timeout, --parallel, --hierarchical, --verbose are plumbing`
- `Sources/dicom-retrieve/RetrieveExecutor.swift`: `// NEMA-verified: 2026a, checked 2026-10-01 — final-status handling checked against PS3.4 2026a Tables C.4-2 / C.4-3 (status wording via RetrieveStatusText, success = 0000 with no failed sub-operations per C.4.2.2.1 / C.4.3.2.1), the four counters against PS3.7 2026a Tables 9.3-7 / 9.3-10, Failed SOP Instance UID List (0008,0058) against C.4.2.1.4.2; the Part 10 wrapper writes the 6 Type 1 rows of PS3.10 2026a Table 7.1-1 (…) and no Type 3 row`
- `Sources/dicom-retrieve/RetrieveStatusText.swift`: `// NEMA-verified: 2026a, checked 2026-10-01 — the 9 C-MOVE rows of PS3.4 2026a Table C.4-2 and the 8 C-GET rows of Table C.4-3 (Service Status, Further Meaning, Status Code) generated from the DocBook by Scripts/nema_docbook.py, 17 of 17 carried verbatim; the sub-operation counter names are those of PS3.7 2026a Tables 9.3-7 / 9.3-10. Byte-identical copy in Sources/dicom-qr and Sources/dicom-retrieve (pinned by DICOMRetrieveTests).`

### dicom-qr

Commands: dicom-qr, query (default), resume · files: DICOMQR.swift (C2), RetrieveStatusText.swift (A, byte-identical copy of dicom-retrieve's) · README.md
Commits: 0b5a61a (fix(cli): dicom-qr exits 1 when a study fails; status per PS3.4 2026a Tables C.4-2 / C.4-3; resume --timeout), HEAD docs commit (dicom-qr README no longer claims --parallel runs retrievals concurrently)
Standard dumped by script: PS3.4 2026a Table C.6-5 (Study level keys, Study Root), Tables C.4-2 / C.4-3, C.6.1-1, C.6.2.3-1, C.5-1; PS3.7 Tables 9.3-9 / 9.3-10 / 9.3-7; PS3.6 Table A-1 Q/R rows; PS3.8 9.1.2; PS3.10 Table 7.1-1; sections C.2.2.2.4 (wild card), C.2.2.2.5 (range), C.4.1.1.3.1, C.4.2.2.1, C.4.3.2.1.

**Input contract** — matched 10, wrong 0, missing 0, extra 1 (`--parallel`, accepted with no effect), plumbing 17

| Option | DICOM concept | 2026a reference | Allowed per standard | Code accepts | Default (std) | Default (code) | Verdict |
|---|---|---|---|---|---|---|---|
| `<host>` | TCP address of the SCP | PS3.8 9.1.2 | — | `host[:port]`, `pacs://` stripped | — | — | plumbing |
| `--port` | DICOM UL port | PS3.8 9.1.2 (104 well-known, 11112 registered) | — | `UInt16?` | none | 11112 | plumbing; help cites PS3.8 |
| `--aet` | Calling AE Title | PS3.8 Table 9-11; PS3.5 VR AE | AE | `String` → `AETitle` (throws on >16) | — | required | plumbing |
| `--called-aet` | Called AE Title | same | AE | `String` | — | `"ANY-SCP"` | plumbing |
| `--move-dest` | Move Destination (0000,0600) | PS3.7 Table 9.3-9; PS3.4 C.4.2.2.1 | AE of a Storage SCP | `String?`, required for c-move (exit 64) | — | — | match |
| `--method` | Study Root QR IM - MOVE / - GET | PS3.4 Table C.6.2.3-1 | the two SOP Classes | `"c-move"` / `"c-get"` (String, lower-cased) | none | `"c-move"` | match (help names the SOP Classes) |
| `--patient-name` | Patient's Name (0010,0010), R key at STUDY level; wild card `*` `?` | PS3.4 Table C.6-5; C.2.2.2.4 | PN, wild cards | `String?`, upper-cased before sending (C.2.2.2.4 leaves PN case handling to the SCP, so harmless) | — | — | match |
| `--patient-id` | Patient ID (0010,0020), R | Table C.6-5 | LO | `String?` | — | — | match |
| `--study-date` | Study Date (0008,0020), R; range matching | Table C.6-5; C.2.2.2.5: `d1-d2`, `-d1`, `d1-` | DA / range | `String?` passed through (all three range forms reach the SCP) | — | — | match (help listed only `d1-d2`; now all three forms) |
| `--study-uid` | Study Instance UID (0020,000D), U | Table C.6-5 | UI | `String?` | — | — | match |
| `--accession-number` | Accession Number (0008,0050), R | Table C.6-5 | SH | `String?` | — | — | match |
| `--modality` | Modalities in Study (0008,0061), O key at STUDY level | Table C.6-5; PS3.3 C.7.3.1.1.1 Defined Terms (shared `ModalityOptionValidator`, verified with its module) | CS Defined Terms | any; unknown value warns, `--strict-modality` rejects | — | — | match (the key sent is (0008,0061), not Modality (0008,0060)) |
| `--strict-modality` | — | — | — | `Bool` | — | false | plumbing |
| `--study-description` | Study Description (0008,1030), O; wild card | Table C.6-5; C.2.2.2.4 | LO | `String?` | — | — | match |
| `-o, --output` | — | PS3.10 (Part 10 files from C-GET) | — | path | — | `"."` | plumbing |
| `--hierarchical` | `<output>/<StudyInstanceUID>/` (C-GET only) | — | — | `Bool` | — | false | plumbing; help said Patient/Study/Series — fixed |
| `--interactive` / `--auto` / `--review` | — | — | — | exactly one (exit 64) | — | false | plumbing |
| `--save-state` | — | — | — | path | — | — | plumbing |
| `--timeout` | socket timeout | — | — | `Int` s | — | 60 | plumbing |
| `--parallel` | "Maximum concurrent retrievals" | — | — | `Int`, parsed and never read: `query` retrieves sequentially | — | 1 | extra (no effect) — P-QR-PARALLEL; README corrected |
| `--validate` | Part 10 read of the received files | PS3.10 | — | `Bool` | — | false | plumbing |
| `--transfer-syntax` | Transfer Syntax proposed for the C-GET storage contexts | PS3.4 C.4.3.2.1; PS3.6 Table A-1 via shared parser | registered TS | shared `TransferSyntax.parse`; unknown → exit 64 | — | nil | match |
| `--verbose` | — | — | — | `Bool` | — | false | plumbing |
| `--include-parent-keys` | parent-level return keys at SERIES/IMAGE (non-baseline) | PS3.4 C.4.1.1.3.1 / C.6.2.1.? | — | `Bool`, no effect at STUDY level (documented in help) | — | false | plumbing |
| `resume -s, --state` | — | — | — | path to the state JSON | — | required | plumbing |
| `resume --timeout` (new, additive) | socket timeout | — | — | `Int` s | — | 60 (was hard-coded 60) | plumbing |
| `resume --verbose` | — | — | — | `Bool` | — | false | plumbing |
| *(no option)* Query/Retrieve Level | always STUDY | PS3.4 Table C.6.1-1 | PATIENT/STUDY/SERIES/IMAGE | `QueryLevel.study` → `"STUDY"`; retrieve `RetrieveKeys(level: .study)` | — | STUDY | match |
| *(no option)* Priority / extended negotiation | as dicom-retrieve | PS3.7 Table 9.3-9; PS3.4 Table C.5-1 | — | not exposed (engine MEDIUM, baseline) | — | — | n/a (P-RETRIEVE-PRIORITY, P-RETRIEVE-EXTNEG) |
| *(resume)* Instance Availability (0008,0056) / Retrieve AE Title (0008,0054) | optional return keys the SCP may add | PS3.4 Table C.6-5 ("All other Attributes at Study Level", O); PS3.3 C.4.23 | — | not requested, not stored; `resume` retrieves from the saved host/port/calledAE | — | — | n/a (documented in README Limitations) |

**Output contract** — matched 12, wrong 0 (4 fixed), missing 0, extra 0, plumbing 6; shared-formatter rows → deferred

| Field | DICOM source | Encoding (standard) | Encoding (code) | Verdict |
|---|---|---|---|---|
| header (shared `qrHeader`): `Calling AE Title:` `Called AE Title:` `Method:` `Move Destination:` `Filters:` | PS3.8 Table 9-11; (0000,0600) | — | — | match |
| `Found n study(ies):` / `No studies found …` | C-FIND Pending/Success (Table C.4-1) | — | counts of FF00/FF01 Identifiers | plumbing |
| study entry (shared `qrStudyEntry`): `[i] <PatientName> (ID: <PatientID>)`, `Study:`, `Date:`, `Modality: <Modalities in Study>`, `UID:` | (0010,0010) (0010,0020) (0008,1030) (0008,0020) (0008,0061) (0020,000D) | — | label `Modality:` shows Modalities in Study (0008,0061) | match except the label → deferred D-QR2 (shared) |
| `[i/n] Retrieving: <name> — <uid>` then `  ✅ Success` / `  ❌ Failed: <error>` | — | — | — | plumbing |
| `❌ Failed: Retrieval failed: C-MOVE final response <Service Status (code): Further Meaning> (Number of Completed Sub-operations: n, Number of Failed Sub-operations: n, Number of Warning Sub-operations: n)` | Status (0000,0900); (0000,1021-1023) | PS3.4 Tables C.4-2 / C.4-3; PS3.7 Table 9.3-10 | `RetrieveStatusText` | **fixed** (was "status <DIMSEStatus>: n completed, n failed, n warning(s)") |
| stderr `  Failed SOP Instance UID List (0008,0058):` + UIDs | (0008,0058), C.4.2.1.4.2 | attribute name | name + tag | **fixed** (was "Failed SOP Instance UIDs:") |
| `Retrieval Summary: Total / Success / Failed` | — | — | — | plumbing |
| stderr `Error: Retrieval incomplete: n study(ies) succeeded, n failed` + exit 1 | final status not Success / failed sub-operations (C.4.2.2.1 / C.4.3.2.1) | — | `DICOMQRError.retrievalIncomplete` thrown after the summary (query and resume) | **fixed** (both exited 0 with failures) |
| `Validating retrieved files` block | PS3.10 read | — | — | plumbing |
| state JSON `studies[].studyInstanceUID`, `patientName`, `patientID`, `studyDate`, `studyDescription`, `accessionNumber` | PS3.6 keywords StudyInstanceUID, PatientName, PatientID, StudyDate, StudyDescription, AccessionNumber | keyword | lower-camel keyword (shared `QRStudyInfo`) | match |
| state JSON `studies[].modality` | written from (0008,0060) Modality, a Series-level attribute; the STUDY query carries Modalities in Study (0008,0061) | Table C.6-5 | value is nil unless the SCP volunteers (0008,0060) | shared type → deferred D-QR3; rename → P-QR-STATE-MODALITIES |
| state JSON `host`, `port`, `callingAE`, `calledAE`, `moveDestination`, `method` (`c-move`/`c-get`), `outputPath`, `hierarchical` | — | — | shared `QRRetrievalState` | plumbing |
| Part 10 file per received instance (C-GET) | PS3.10 Table 7.1-1 | 6 Type 1 rows | all 6 written | match |
| exit `0` | every selected study: Success (0000) and no failed sub-operations | — | — | match |
| exit `1` | any study with Warning / Failure / Cancel / failed sub-operation / transport error; any other error | — | thrown error → 1 | match (**fixed**, documented) |
| exit `64` | usage: no mode, several modes, c-move without `--move-dest`, unknown method / transfer syntax, bad modality under `--strict-modality` | — | `ValidationError` | match (documented) |

**Findings**
- Exit code: `query` and `resume` counted failures, printed the summary and returned → exit 0. Fixed (`retrievalIncomplete` thrown after the summary; pinned by `testQRResumeExitsNonZeroWhenAStudyFails`, which spawns `dicom-qr resume` against a refused port with the new `--timeout 2`).
- `resume` had the timeout hard-coded at 60 s; `--timeout` added (additive).
- Status / counter / Failed SOP Instance UID List wording as for dicom-retrieve (byte-identical `RetrieveStatusText`, pinned by `testRetrieveStatusTextCopiesAreIdentical`).
- Help: the 7 match keys now carry their tags; `--study-date` lists the three range forms of C.2.2.2.5; `--hierarchical` said Patient/Study/Series (code: `<output>/<StudyInstanceUID>/`, C-GET only).
- `--parallel` is parsed but never read (sequential loop) — README corrected; the option itself is a P-item (P-QR-PARALLEL).
- `Tests/DICOMToolsTests/DICOMQRTests.swift` (31 tests) is not compiled by any target — same as dicom-retrieve; tests placed in `Tests/DICOMNetworkTests/QueryRetrieveCLIStandardTests.swift`.

**Tests** — `swift test --filter QueryRetrieveCLIStandardTests`: 6 passed (2 dicom-qr spawn tests: `testQRQueryHelpNamesStandardConcepts`, `testQRResumeExitsNonZeroWhenAStudyFails`; 2 table tests shared). `swift build --product dicom-qr` ok. `check_nema_markers.py Sources/dicom-qr`: 2 files, 2 markers. `diff_cli.py --tool dicom-qr`: 0 FAIL (documented defaults 5/5).

**Deferred findings (new, DICOMNetwork)**
| ID | Module | file:line | Problem | Standard | Severity |
|---|---|---|---|---|---|
| D-QR3 | DICOMNetwork | Sources/DICOMNetwork/QRSessionState.swift:25 (`QRStudyInfo.modality = result.modality`) and :117 (`GenericQueryResult.modality` → (0008,0060)) | The dicom-qr state file stores Modality (0008,0060), a Series-level attribute, while the STUDY-level C-FIND requests Modalities in Study (0008,0061) (Table C.6-5); the saved value is empty unless the SCP volunteers (0008,0060). The console entry correctly shows `modalitiesInStudy`. | PS3.4 2026a Table C.6-5 | low |
(D-QR1, D-QR2 as in the dicom-retrieve section.)

**P-items**
- P-QR-STATE-MODALITIES: add `modalitiesInStudy` to `QRStudyInfo` (shared JSON key; keep `modality` for old files).
- P-QR-PARALLEL: `--parallel` has no effect in `dicom-qr query`; either implement (task group as in dicom-retrieve) or deprecate the option.
- P-QR-STATUS-TEXT, P-RETRIEVE-PRIORITY, P-RETRIEVE-EXTNEG: as in dicom-retrieve.

**Markers**
- `Sources/dicom-qr/DICOMQR.swift`: `// NEMA-verified: 2026a, checked 2026-10-01 — the 7 match keys compared with PS3.4 2026a Table C.6-5 (Study Root, Study level: 4 R keys, 1 U key, 2 O keys — Modalities in Study (0008,0061) carries --modality), wildcard / range matching with C.2.2.2.4 / C.2.2.2.5, Query/Retrieve Level STUDY with Table C.6.1-1, methods with Table C.6.2.3-1 (Study Root MOVE/GET), Move Destination (0000,0600) with PS3.7 Table 9.3-9, final-status handling with Tables C.4-2 / C.4-3 via RetrieveStatusText, ports 104 / 11112 with PS3.8 9.1.2; the Part 10 wrapper writes the 6 Type 1 rows of PS3.10 2026a Table 7.1-1; modes, state file, --output, --timeout, --parallel, --validate, --verbose are plumbing`
- `Sources/dicom-qr/RetrieveStatusText.swift`: identical to dicom-retrieve's.

**For Scripts/diff_cli.py (orchestrator)**: the ATTR regex already handles the 3-level nesting of `--modality` / `--transfer-syntax` (both listed now; no edit made). The output-contract skeleton lists `JSON \`Automatic\`` / `JSON \`Interactive\`` for dicom-qr — those are ternary string literals (`modeLabel`), not JSON keys. Consider a check "CLI final-status strings are PS3.4 Table C.4-2/C.4-3 Further Meaning" reading `RetrieveStatusText.swift`, like `testRetrieveStatusTextCarriesPS34Tables2026a`.

### dicom-mwl

Commands: dicom-mwl, query · files: DICOMMWLCommand.swift · bucket C2 (thin adapter over DICOMNetwork.WorklistQueryKeys / DICOMModalityWorklistService / NetworkConsole; the help and discussion carry standard-derived text)

Compared (all dumped by `Scripts/nema_docbook.py` / `sect.py` from the 2026a DocBook): PS3.4 Table K.6-1 (139 rows — the 9 matching keys the options set, their R/O type and the matching allowed per row), Table K.6-1a, Table K.4-1 (7 C-FIND status rows), Table K.6.1.4-1 (SOP Class UID), C.2.2.2.5.1 / C.2.2.2.5.2 / C.2.2.2.5.4 (DA/TM Range Matching, combined date-time with Extended Negotiation), PS3.3 Table C.4-10 (0040,0020) Defined Terms (5), PS3.5 Table 6.2-1 (AE, DA, TM), PS3.6 Table 6-1 (38 JSON keys vs keywords) and Table A-1 (1.2.840.10008.5.1.4.31), PS3.7 Annex C status names (27 codes), PS3.8 9.1.1 (port 104 / 11112). `Scripts/diff_cli.py --tool dicom-mwl`: 11 checks ok, 0 FAIL (18 options extracted).

**Input contract**

| Option | DICOM concept | 2026a reference | Allowed per standard | Code accepts | Default (std) | Default (code) | Verdict |
|---|---|---|---|---|---|---|---|
| `<host>` | TCP transport address | PS3.8 9.1.1 | `host[:port]`, `pacs://` prefix stripped | `String` | — | required | plumbing |
| `--port` | TCP port | PS3.8 9.1.1 (well-known 104; 11112 is the IANA "dicom" registered port, not in the PS3.8 text) | 1–65535 | `UInt16?` | 104 recommended | 11112 | plumbing |
| `--aet` | Calling AE Title | PS3.8 7.1.1.3; PS3.5 Table 6.2-1 VR AE | ≤16 bytes, no backslash/control chars, not all spaces | `String` (DICOMNetwork.AETitle) | none | required | plumbing |
| `--called-aet` | Called AE Title | PS3.8 7.1.1.4; PS3.5 Table 6.2-1 VR AE | as above | `String` | none | `"ANY-SCP"` (tool convention) | plumbing |
| `--date` | Scheduled Procedure Step Start Date (0040,0002), R key in SPS Sequence | PS3.4 Table K.6-1 row 4: Single Value or Range Matching; C.2.2.2.5.1; PS3.5 Table 6.2-1 DA (YYYYMMDD, 18 bytes max with `-`) | `YYYYMMDD`, `D1-D2`, `D1-`, `-D2` | same, plus `today`/`tomorrow` shorthands resolved to YYYYMMDD (WorklistQueryKeys.resolveScheduledDate) | — | absent (Universal Matching) | match |
| `--time` | Scheduled Procedure Step Start Time (0040,0003), R key | PS3.4 Table K.6-1 row 5 (Single Value or Range Matching; combined with the date range as one interval — remark under (0040,0003), C.2.2.2.5.4); C.2.2.2.5.2 (no crossing midnight); PS3.5 Table 6.2-1 TM (HH, HHMM, HHMMSS[.FFFFFF]) | as PS3.5 TM, `T1-T2`, `T1-`, `-T2` | same (resolveScheduledTime; short forms and fraction tested in WorklistQueryKeysTests) | — | absent | match — help/discussion cited "PS3.4 K.6.1" (an overview clause); now cites Table K.6-1 remark + C.2.2.2.5.x and the TM forms (fixed) |
| `--station` | Scheduled Station AE Title (0040,0001), R key | PS3.4 Table K.6-1 row 3: Single Value Matching only; PS3.5 VR AE 16 bytes | AE Title (wildcards `*`/`?` are tolerated by the shared validator although K.6-1 says Single Value only) | `String?` (validateScheduledStationAETitle) | — | absent | match (wildcard tolerance is engine leniency, noted) |
| `--patient` | Patient's Name (0010,0010), R key | PS3.4 Table K.6-1 row 86: Single Value or Wild Card Matching | PN with `*`/`?` | `String?` | — | absent | match |
| `--patient-id` | Patient ID (0010,0020), R key | PS3.4 Table K.6-1 row 87: Single Value Matching | LO | `String?` | — | absent | match |
| `--modality` | Modality (0008,0060), R key | PS3.4 Table K.6-1 row 6: Single Value Matching; PS3.3 C.7.3.1.1.1 Defined Terms | Defined Terms | `String?` via DICOMCore.ModalityOptionValidator (checked against PS3.3 2026a in DICOMCore's report) | — | absent | match (shared) |
| `--strict-modality` | reject non-Defined-Term modality | PS3.3 C.7.3.1.1.1 (Defined Terms are extensible) | — | `Bool` | — | false | plumbing |
| `--sps-status` | Scheduled Procedure Step Status (0040,0020), O key type 3 | PS3.4 Table K.6-1 row 35; PS3.3 Table C.4-10 Defined Terms: SCHEDULED, ARRIVED, READY, STARTED, DEPARTED | Defined Terms (extensible) | any string, sent as given; now warns on stderr when not one of the 5 terms | — | absent | **wrong → fixed**: help and discussion listed "SCHEDULED, IN PROGRESS, DISCONTINUED, COMPLETED" (three are PPS Status values, Table C.4-14) |
| `--accession-number` | Accession Number (0008,0050), O key type 2 | PS3.4 Table K.6-1 row 64 | SH | `String?` | — | absent | match |
| `--performing-physician` | Scheduled Performing Physician's Name (0040,0006), R key type 2 | PS3.4 Table K.6-1 row 7: Single Value or Wild Card Matching | PN with `*`/`?` | `String?` | — | absent | match |
| `--specific-character-set` | Specific Character Set (0008,0005) of the Identifier | PS3.4 Table K.6-1a (1C in the C-FIND Identifier); PS3.5 6.1.2 | Defined Terms of PS3.5 Table 6.1-1 | `String?` (engine chooses the narrowest set otherwise) | absent for ISO-IR 6 | auto | match (shared) |
| `--timeout` | ARTIM / socket timeout | PS3.8 9.1.2 | seconds | `Int` | — | 60 | plumbing |
| `-v, --verbose` | — | — | — | `Bool` | — | false | plumbing |
| `--json` | JSON rendering of the responses | — | — | `Bool` | — | false | plumbing |

Counts: matched 10, wrong 1 (fixed), missing 0, extra 0, plumbing 7.

**Output contract**

| Field | DICOM source | Encoding (standard) | Encoding (code) | Verdict |
|---|---|---|---|---|
| JSON keys `PatientName PatientID PatientBirthDate PatientSex AccessionNumber StudyInstanceUID ReferringPhysicianName RequestedProcedureID RequestedProcedureDescription Modality ScheduledStationAETitle ScheduledStationName RequestedProcedurePriority RequestedContrastAgent PreMedication PatientWeight PatientSize PregnancyStatus MedicalAlerts Allergies SpecialNeeds PatientState AdmissionID CurrentPatientLocation RequestingPhysician` and nested `CodeValue CodingSchemeDesignator CodeMeaning` (28) | the return keys of Table K.6-1 | PS3.6 Table 6-1 keywords | NetworkConsole.mwlJSON (shared) — identical to the keyword | match |
| JSON keys `SPSStartDate SPSStartTime SPSStatus SPSID SPSDescription SPSLocation ScheduledPerformingPhysician RequestedProcedureCode ScheduledProtocolCodes ReferencedStudySOPInstanceUID` (10) | (0040,0002) (0040,0003) (0040,0020) (0040,0009) (0040,0007) (0040,0011) (0040,0006) (0032,1064) (0040,0008) (0008,1110)>(0008,1155) | PS3.6 keywords `ScheduledProcedureStepStartDate … ScheduledPerformingPhysicianName`, `RequestedProcedureCodeSequence`, `ScheduledProtocolCodeSequence`, `ReferencedStudySequence` | abbreviated / flattened names in the shared formatter | not PS3.6 keywords → P-MWL-JSON-KEYS (rename = JSON-key change, not implemented) |
| `PregnancyStatus` value | (0010,21C0) US | PS3.3 C.2-4 Enumerated Values 1–4 | `Int(v)` | match |
| printed labels (`Patient Name:`, `SPS Status:`, `Scheduled Date/Time:`, …) | free-form | — | NetworkConsole.mwlItem (shared) | plumbing |
| C-FIND statuses: Pending FF00/FF01 (items collected), Success 0000, Cancel FE00, A700, A900, Cxxx → `DICOMNetworkError.queryFailed(status)` → "Query failed: <DIMSEStatus>" | C-FIND-RSP Status (0000,0900) | PS3.4 Table K.4-1: A700 "Refused: Out of resources", A900 "Error: Data Set does not match SOP Class", Cxxx "Failed: Unable to process" | DIMSEStatus.description (DICOMNetwork): "Refused: Out of resources (0xA700)" ✓, "Error: Identifier/Data does not match SOP Class (0xA900)", "Failed: unable to process / cannot understand (Cxxx)" | match for A700/FE00/FF00/FF01/0000; A900 / Cxxx wording differs from K.4-1 → deferred (DICOMNetwork, cosmetic) |
| `--date`/`--time`/`--station` validation errors | — | — | ValidationError, exit 64 | plumbing |
| `⚠️ The result count (N) may be capped…` | heuristic | — | shared | plumbing |
| exit codes | — | — | 0 success (also 0 for "No worklist items found."), 64 usage/validation, 1 thrown DICOMNetworkError | plumbing |

Findings:
1. `--sps-status` help/discussion listed PPS Status words as SPS Status values (PS3.3 Table C.4-10 Defined Terms are SCHEDULED, ARRIVED, READY, STARTED, DEPARTED) — fixed in help, discussion and README; a non-Defined-Term value now warns on stderr (still sent, Defined Terms are extensible). Test: `testMWL_helpListsTheScheduledProcedureStepStatusDefinedTerms`, `testMWL_ppsStatusWordAsSPSStatusWarnsBeforeTheQuery`, `testMWL_definedTermDoesNotWarn`.
2. "PS3.4 K.6.1" cited for the combined date+time interval (help, discussion, README): the clause is the remark under (0040,0003) in Table K.6-1 (K.6.1.2.2) and C.2.2.2.5.4 (Extended Negotiation of combined datetime matching) — citations fixed; test `testMWL_helpCitesRangeMatchingClauses`.
3. `--time` help now states the PS3.5 Table 6.2-1 TM forms (HH, HHMM, HHMMSS[.FFFFFF]) the engine already accepts, and that a range never crosses midnight (C.2.2.2.5.2).

Deferred (not fixed here):
| ID | Module | file:line | Problem | Standard ref | Severity |
|---|---|---|---|---|---|
| D79 | DICOMNetwork | Sources/DICOMNetwork/DIMSEStatus.swift:278, :280, :282 | C-FIND failure names differ from the 2026a tables: 0xA900 printed "Error: Identifier/Data does not match SOP Class" (K.4-1: "Error: Data Set does not match SOP Class"); 0x0110 printed "Failed: Unable to process" (PS3.7 C.5.21: "Processing Failure"; "Unable to process" is the Cxxx class of K.4-1) | PS3.4 Table K.4-1; PS3.7 C.5.21 | low (wording) |
| D80 | DICOMNetwork | Sources/DICOMNetwork/NetworkConsoleFormatter.swift:502-547 | 10 of 38 JSON keys are not PS3.6 keywords (see P-MWL-JSON-KEYS); shared with DICOMStudio's MWL panel | PS3.6 Table 6-1 | low (P-item) |
| D81 | DICOMNetwork | Sources/DICOMNetwork/ModalityWorklistService.swift:157-168 | `validateScheduledStationAETitle` tolerates `*`/`?` although Table K.6-1 row 3 allows Single Value Matching only for (0040,0001) | PS3.4 Table K.6-1 | low |

P-items:
- **P-MWL-JSON-KEYS**: rename the 10 abbreviated `--json` keys to the PS3.6 keywords (`SPSStartDate`→`ScheduledProcedureStepStartDate`, `SPSStartTime`→`ScheduledProcedureStepStartTime`, `SPSStatus`→`ScheduledProcedureStepStatus`, `SPSID`→`ScheduledProcedureStepID`, `SPSDescription`→`ScheduledProcedureStepDescription`, `SPSLocation`→`ScheduledProcedureStepLocation`, `ScheduledPerformingPhysician`→`ScheduledPerformingPhysicianName`, `RequestedProcedureCode`→`RequestedProcedureCodeSequence`, `ScheduledProtocolCodes`→`ScheduledProtocolCodeSequence`, `ReferencedStudySOPInstanceUID`→`ReferencedStudySequence[{ReferencedSOPClassUID, ReferencedSOPInstanceUID}]`). Lives in shared `NetworkConsole.mwlJSON` and is parsed by the Studio CLI-parity comparator; keep the old keys as aliases if approved.

Marker: `// NEMA-verified: 2026a, checked 2026-10-01 — the 9 matching keys behind --date/--time/--station/--patient/--patient-id/--modality/--sps-status/--accession-number/--performing-physician diffed against PS3.4 2026a Table K.6-1 (139 rows; matching-key type and allowed matching per row); Range Matching forms against PS3.4 C.2.2.2.5.1/.2 and the combined date-time remark under (0040,0003) in Table K.6-1; SPS Status values against PS3.3 Table C.4-10 (0040,0020) Defined Terms (5: SCHEDULED, ARRIVED, READY, STARTED, DEPARTED); SOP Class UID against PS3.6 Table A-1; DA/TM forms against PS3.5 Table 6.2-1. The 38 JSON keys and the response statuses are shared DICOMNetwork code (NetworkConsole.mwlJSON, DIMSEStatus): 28 keys are PS3.6 keywords, 10 are not (P-item).`

Tests: `Tests/DICOMNetworkTests/MWLMPPSCLIEndToEndTests.swift` (new, spawn-based, 16 tests for both tools; 4 for dicom-mwl) — `swift test --filter MWLMPPSCLIEndToEndTests`: 16 passed, 0 failed. `swift build --product dicom-mwl` ok; `check_nema_markers.py Sources/dicom-mwl`: 1/1.

diff_cli.py note for the orchestrator: `--modality` is declared with `help: ArgumentHelp(stringLiteral: ModalityOptionValidator.helpText(...))`, so the extractor lists it with an empty help column; the `CODE|SCHEME|MEANING` literals (dicom-mpps) are not recognised by the PS3.16 coded-concept check (it reported "matched 0" while the examples were wrong) — a pattern `"(\w+)\|(\w+)\|([^"]+)"` would have caught them.

Commit: f2db8f9 `fix(cli): dicom-mwl SPS Status Defined Terms per PS3.3 Table C.4-10, clause-exact Range Matching citations (2026a)` (also carries the shared test file and the CHANGELOG bullet for both tools).

### dicom-mpps

Commands: dicom-mpps, create, update · files: DICOMMPPSCommand.swift · bucket C2 (adapter over DICOMNetwork.DICOMMPPSService / MPPSStatus / MPPSCodedEntry / NetworkConsole; carries the status-word parser, the CID 9300 examples and, now, the PS3.7 Annex C status names)

Compared (dumped by script from the 2026a DocBook): PS3.4 Table F.7.2-1 (130 rows — N-CREATE/N-SET/Final-State usage of the 24 attributes the options set), Table F.7.2-2 (N-SET 0110/A710), Table F.7.1-1, F.7.2.1.1 note (0040,0281 must be created at N-CREATE), F.7.2.1.2 (N-CREATE only IN PROGRESS), F.7.2.1.3 (0106H on another value), F.7.2.2.2 (final state, no later N-SET); PS3.3 Table C.4-14 (0040,0252) Enumerated Values (3), Table C.2-3 (0010,0040) Enumerated Values (3), Tables C.4-13 / C.4-15 (attribute semantics); PS3.5 Table 6.2-1 (DA, TM, AE); PS3.6 Table 6-1 (the 30 tags cited in help) and Table A-1 (3 UIDs); PS3.7 Annex C C.4.2–C.5.25 (27 status codes with names) and 10.1.5.1.4 (SCP-assigned Affected SOP Instance UID); PS3.16 CID 9300 (6 DCM rows + includes 9301/9302/60), CID 9301 (19 rows), Table D-1 (110500, 110501, 110507, 110513, 110514, 110518, 110526). `Scripts/diff_cli.py --tool dicom-mpps`: 11 checks ok, 0 FAIL (46 options extracted; 2 citations matched).

**Input contract** (plumbing rows `<host>`, `--port`, `--aet`, `--called-aet`, `--timeout`, `-v` are identical to dicom-mwl and appear in both subcommands; counted once)

| Option | DICOM concept | 2026a reference | Allowed per standard | Code accepts | Default (std) | Default (code) | Verdict |
|---|---|---|---|---|---|---|---|
| `<host>` / `--port` / `--aet` / `--called-aet` / `--timeout` / `-v, --verbose` / `--specific-character-set` | as dicom-mwl (PS3.8 9.1.1, 7.1.1.3/4; PS3.5 VR AE; PS3.4 Table F.7.2-1 row 1 for (0008,0005) 1C/1C) | | | | | 11112 / "ANY-SCP" / 60 | plumbing (7) |
| create `--study-uid` | Study Instance UID (0020,000D) in Scheduled Step Attributes Sequence | Table F.7.2-1 row 4: 1/1 N-CREATE | UI | `String` required | — | required | match |
| create `--status` | Performed Procedure Step Status (0040,0252) | Table C.4-14 Enumerated Values IN PROGRESS / COMPLETED / DISCONTINUED; F.7.2.1.2: N-CREATE only "IN PROGRESS"; Table F.7.2-1 row 92 1/1 | IN PROGRESS | `parseStatus`: case-insensitive, space may be `_` or omitted; sends `MPPSStatus.rawValue` = "IN PROGRESS"; create rejects COMPLETED/DISCONTINUED | IN PROGRESS | "IN PROGRESS" | match (tests `testMPPS_createRejectsTerminalStatus`, `_RejectsUnknownStatusWord`, `_updateAcceptsStatusWordSpellings`) |
| create `--modality` | Modality (0008,0060) | Table F.7.2-1 row 105: 1/1 N-CREATE; PS3.3 C.7.3.1.1.1 Defined Terms | Defined Term, Type 1 | was optional (engine sent an empty Type 1 value); **now required** | — | required | **missing → fixed** (`testMPPS_createRequiresModality`) |
| create `--strict-modality` | — | — | — | `Bool` | — | false | plumbing |
| create `--patient-name` | Patient's Name (0010,0010) | Table F.7.2-1 row 32: 2/2 | PN | `String?` | — | empty | match |
| create `--patient-id` | Patient ID (0010,0020) | row 33: 2/2 | LO | `String?` | — | empty | match |
| create `--patient-birth-date` | Patient's Birth Date (0010,0030) | row 45: 2/2; PS3.5 Table 6.2-1 DA 8 bytes fixed | YYYYMMDD | **now validated** 8 digits | — | empty | match (validation added; `testMPPS_createRejectsNonDABirthDate`) |
| create `--patient-sex` | Patient's Sex (0010,0040) | row 46: 2/2; PS3.3 Table C.2-3 Enumerated Values M, F, O | M / F / O | **now validated** (case-insensitive, upper-cased) | — | empty | match (validation added; `testMPPS_createRejectsPatientSexOutsideEnumeratedValues`) |
| create `--sps-id` | Scheduled Procedure Step ID (0040,0009) in (0040,0270) | row 27: 2/2 | SH | `String?` | — | empty | match |
| create `--accession-number` | Accession Number (0008,0050) in (0040,0270) | row 8: 2/2 | SH | `String?` | — | empty | match |
| create `--requested-procedure-id` | Requested Procedure ID (0040,1001) in (0040,0270) | row 23: 2/2 | SH | `String?` | — | empty | match |
| create `--requested-procedure-description` | Requested Procedure Description (0032,1060) | row 26: 2/2 | LO | `String?` | — | empty | match |
| create `--sps-description` | Scheduled Procedure Step Description (0040,0007) | row 28: 2/2 | LO | `String?` | — | empty | match |
| create `--referenced-study-uid` | Referenced SOP Instance UID (0008,1155) in Referenced Study Sequence (0008,1110) | rows 5–7: 2/2, item 1/1 | UI | `String?` | — | empty sequence | match |
| create `--study-id` | Study ID (0020,0010) | row 106: 2/2 | SH | `String?` | — | empty | match |
| create `--station-name` | Performed Station Name (0040,0242) | row 88: 2/2 | SH | `String?` | — | empty | match |
| create `--performed-location` | Performed Location (0040,0243) | row 89: 2/2 | SH | `String?` | — | empty | match |
| create `--procedure-step-id` | Performed Procedure Step ID (0040,0253) | row 86: 1/1 | SH | `String?` | — | "1" (engine) | match |
| create `--procedure-step-description` | Performed Procedure Step Description (0040,0254) | row 93: 2/2 | LO | `String?` | — | empty | match |
| create `--performing-physician` | Performing Physician's Name (0008,1050) in Performed Series Sequence | row 111: 2/2 (inside (0040,0340)); not a root attribute of Table F.7.2-1 | PN | `String?` → engine stores it on the step; `test_nCreate_doesNotCarryAttributesTheTableDoesNotAllowAtRoot` pins it off the root | — | empty | match (shared) |
| update `--mpps-uid` | Requested SOP Instance UID of the N-SET | PS3.7 10.3.5 Table 10.3-5; PS3.7 10.1.5.1.4 (SCP may assign the UID at N-CREATE — the create path prints the assigned UID) | UI | `String` required | — | required | match |
| update `--status` | Performed Procedure Step Status (0040,0252) | Table F.7.2-1 row 92 N-SET 3/1 final; F.7.2.2.2 COMPLETED / DISCONTINUED final; F.7.2.1.1 note: COMPLETED needs ≥1 Performed Series item | COMPLETED / DISCONTINUED | parseStatus; update rejects IN PROGRESS; engine refuses COMPLETED without a series item before connecting | — | required | match (help now says COMPLETED needs a series item; `testMPPS_updateRejectsInProgress`, `_updateCompletedWithoutSeriesFailsBeforeConnecting`) |
| update `--study-uid` / `--series-uid` / `--image-uid` | Performed Series Sequence (0040,0340) item: Series Instance UID (0020,000E) 1/1, Referenced Image Sequence (0008,1140) > Referenced SOP Instance UID (0008,1155) 1/1 | Table F.7.2-1 rows 110, 114, 118–120 | UI | `--image-uid` repeatable; **now an error** without `--study-uid` and `--series-uid` (references were dropped silently) | — | none | **wrong → fixed** (`testMPPS_updateRejectsImageUIDWithoutSeries`) |
| update `--sop-class-uid` | Referenced SOP Class UID (0008,1150) | row 119: 1/1; PS3.6 Table A-1 | registered SOP Class UID | `String?`; warning when absent (engine defaults to 1.2.840.10008.5.1.4.1.1.7 Secondary Capture Image Storage) | — | SC (engine) | match (default is engine leniency, warned; UIDs/names in help verified: 5.1.4.1.1.2 CT Image Storage, 5.1.4.1.1.7 Secondary Capture Image Storage) |
| update `--protocol-name` | Protocol Name (0018,1030) in Performed Series item | row 112: 1/1 N-CREATE and N-SET | LO | `String?` | — | "UNSPECIFIED" (engine) | match |
| update `--series-description` | Series Description (0008,103E) | row 115: 2/2 | LO | `String?` | — | empty | match |
| update `--operator-name` | Operators' Name (0008,1070) | row 113: 2/2 | PN | `String?` | — | empty | match |
| update `--performing-physician` | Performing Physician's Name (0008,1050) | row 111: 2/2 | PN | `String?` | — | empty | match |
| update `--legacy-nset-scheduled-attributes` | Scheduled Step Attributes Sequence (0040,0270) in N-SET | row 3: "Not allowed" in N-SET | not allowed | `Bool` opt-in for non-conformant SCPs | absent | false | match (opt-in documented as forbidden) |
| update `--discontinuation-reason` | Performed Procedure Step Discontinuation Reason Code Sequence (0040,0281) | row 102: 3/3 (macro F.7.2-1c); PS3.3 C.4-14; PS3.16 CID 9300 "Procedure Discontinuation Reason" (includes CID 9301) | CODE\|SCHEME\|MEANING | `MPPSCodedEntry.parse` (shared); only with DISCONTINUED | — | absent | **wrong examples → fixed**: help/discussion cited "110513 Doctor cancelled procedure", "110514 Equipment failure", "110518 Patient did not arrive"; Table D-1: 110513 = Discontinued for unspecified reason, 110514 = Incorrect worklist entry selected, 110518 = Patient Movement (not in CID 9300); correct codes 110500 Doctor canceled procedure, 110501 Equipment failure, 110507 Patient did not arrive (`testMPPS_helpCitesCID9300CodesWithTheirTableD1Meanings`) |

Counts: matched 23, wrong 2 (fixed), missing 1 (fixed), extra 0, plumbing 8 (the 7 shared plumbing options + `--strict-modality`).

**Output contract**

| Field | DICOM source | Encoding (standard) | Encoding (code) | Verdict |
|---|---|---|---|---|
| `Status: IN PROGRESS` (verbose header), `New Status: COMPLETED|DISCONTINUED` | (0040,0252) | PS3.3 Table C.4-14 Enumerated Values, written with the space | `MPPSStatus.rawValue` (DICOMNetwork) | match |
| `MPPS Instance UID: …` and `note: SCP assigned MPPS SOP Instance UID … (PS3.7 10.1.5.1.4)` | N-CREATE-RSP Affected SOP Instance UID (0000,1000) | PS3.7 10.1.5.1.4: included in the success response when assigned by the SCP | `MPPSOperationResult.sopInstanceUIDWasReassigned` (shared) | match (citation verified) |
| `warning: SCP completed the operation with <status>` | N-CREATE/N-SET-RSP Status (0000,0900) warning class | PS3.7 C.4.2 0107H "Attribute List warning", C.4.3 0116H "Attribute Value out of range", B000-BFFF | was `DIMSEStatus.description` → "Unknown status (0x0107)"; now `DICOMMPPSCommand.describe` → "0107H Attribute List warning (PS3.7 C.4.2)" | **wrong → fixed** in the tool (engine row deferred) |
| `Error: N-CREATE failed: SCP returned <status>` / `N-SET failed: …` | failure class | PS3.7 C.5.6–C.5.25 (0105H–0124H, 0210H–0213H) with the Annex C names; PS3.4 Table F.7.2-2: N-SET 0110 Processing Failure, "Performed Procedure Step Object may no longer be updated", Error ID A710; F.7.2.1.3: N-CREATE with a status other than IN PROGRESS → 0106H Invalid Attribute Value | was "Store failed: Unknown status (0x0106)" (DICOMNetworkError.storeFailed); now the 22 DIMSE-N codes are named from the local PS3.7 table | **wrong → fixed** in the tool; engine rows deferred |
| `--sop-class-uid` warning text naming Secondary Capture (1.2.840.10008.5.1.4.1.1.7) | PS3.6 Table A-1 | "Secondary Capture Image Storage" | abbreviated "Secondary Capture" with the right UID | match |
| `Creating MPPS instance (N-CREATE)...`, `✅ MPPS instance created/updated`, `Referenced Images: N` | — | — | shared NetworkConsole | plumbing |
| exit codes | — | — | 0 success, 64 ValidationError (status words, enumerated values, missing --modality, image/series pairing, SCP failure status), 1 other DICOMNetworkError | plumbing |

Findings (all fixed in the tool, tests in MWLMPPSCLIEndToEndTests): CID 9300 example meanings (3 wrong codes); `create` sent an empty Type 1 Modality when `--modality` was omitted; `--patient-sex` / `--patient-birth-date` unvalidated; `--image-uid` silently dropped without `--study-uid`/`--series-uid`; discussion/README examples showed `update --status COMPLETED` without the Performed Series item the final state requires (the engine refuses it before connecting); DIMSE-N statuses printed as "Unknown status". Behaviour changes are in the CHANGELOG bullet (shared with dicom-mwl).

Deferred (not fixed here):
| ID | Module | file:line | Problem | Standard ref | Severity |
|---|---|---|---|---|---|
| D82 | DICOMNetwork | Sources/DICOMNetwork/DIMSEStatus.swift:124-171, 267-300 | `DIMSEStatus.from` maps no DIMSE-N code except 0110/0111/0112/0118/0122/0213; 0105, 0106, 0107, 0115, 0116, 0117, 0119, 0120, 0121, 0124, 0210-0212 print "Unknown status"; 0110 is named "Failed: Unable to process" instead of "Processing Failure"; the N-SET A710 Error ID (Table F.7.2-2) is never surfaced | PS3.7 Annex C C.4.2-C.5.25; PS3.4 Table F.7.2-2 | medium (every MPPS and Print failure message) |
| D83 | DICOMNetwork | Sources/DICOMNetwork/MPPSService.swift:1034, :1099; DICOMNetworkError.swift:476 | MPPS N-CREATE / N-SET failures are thrown as `DICOMNetworkError.storeFailed` → "Store failed: …" (a C-STORE wording) | PS3.4 F.7.2.1.4 / Table F.7.2-2 | low (wording) |
| D84 | DICOMNetwork | Sources/DICOMNetwork/MPPSService.swift:143, :162, :326 | `MPPSCodedEntry.parseErrorMessage` and doc comments give "110513\|DCM\|Doctor cancelled procedure" and the title "Procedure Discontinuation Reasons"; Table D-1: 110513 = "Discontinued for unspecified reason", 110500 = "Doctor canceled procedure"; CID 9300 title is "Procedure Discontinuation Reason" | PS3.16 CID 9300, CID 9301, Table D-1 | low (message text; shared with the Studio CLI Workshop) |
| D85 | DICOMStudio | Sources/DICOMStudio/Components/CLIWorkshopHelpers.swift:1379-1380 | same wrong placeholder "110513\|DCM\|Doctor cancelled procedure"; and :1217-1221 offers `--modality` as optional ("Any") although `dicom-mpps create` now requires it (Table F.7.2-1 row 105, 1/1) | PS3.16 Table D-1; PS3.4 Table F.7.2-1 | low |
| D86 | DICOMNetwork | Sources/DICOMNetwork/MPPSService.swift:1125-1168 (N-CREATE builder) | the N-CREATE data set never creates (0040,0281) zero-length, yet the N-SET sends it for DISCONTINUED; F.7.2.1.1 note: "If an SCU wishes to use the PPS Discontinuation Reason Code Sequence (0040,0281), it must create that Attribute (zero-length) during N-CREATE"; F.7.2.1.2 "All Attributes shall be created before they can be set" | PS3.4 F.7.2.1.1 note, F.7.2.1.2 | medium (strict SCPs may answer 0105H No such Attribute) |
| D87 | DICOMNetwork | Sources/DICOMNetwork/MPPSService.swift:1163 | `add(0x0008,0x0060,.CS, procedureStep.modality)` writes an empty value when `modality` is nil — a Type 1 attribute (Table F.7.2-1 row 105); the engine's `validate(_:for:)` does not check it (the CLI now refuses before calling) | PS3.4 Table F.7.2-1 | medium |
| D88 | Tests/DICOMStudioTests | NetworkToolWorkshopCLIParityTests.swift:151-157 | parse fixtures use the wrong code/meaning pairs ("110513 Doctor cancelled procedure", "110514 Equipment failure"); harmless for parsing but mislead readers | PS3.16 Table D-1 | low |

P-items: none (no option name, accepted value or JSON key was renamed; the new `--modality` requirement, the M/F/O and DA checks and the image/series pairing error are validations of values the standard already constrained — flagged in the CHANGELOG as behaviour changes for the owner's attention: **P-MPPS-STRICT** if the owner prefers warnings instead of errors).

Marker: `// NEMA-verified: 2026a, checked 2026-10-01 — the 24 attribute-bearing options of create/update diffed against PS3.4 2026a Table F.7.2-1 (130 rows: N-CREATE / N-SET / Final State usage per tag); --status words against PS3.3 Table C.4-14 (0040,0252) Enumerated Values (3) and the N-CREATE/N-SET rules of PS3.4 F.7.2.1.2, F.7.2.1.3, F.7.2.2.2; --patient-sex against PS3.3 Table C.2-3 (0010,0040) Enumerated Values (3); --patient-birth-date against PS3.5 Table 6.2-1 DA; --discontinuation-reason examples against PS3.16 CID 9300 (6 DCM rows + CID 9301 17 rows, Table D-1); SOP Class UIDs against PS3.6 Table A-1 (3); response status names against PS3.7 Annex C C.4.2-C.5.25 (27 codes) and PS3.4 Table F.7.2-2 (A710). Data-set building, the status enum and the console text live in DICOMNetwork (MPPSService, NetworkConsole).`

Tests: `Tests/DICOMNetworkTests/MWLMPPSCLIEndToEndTests.swift` — 12 dicom-mpps tests (16 in the file), all pass; `swift build --product dicom-mpps` ok; `check_nema_markers.py Sources/dicom-mpps`: 1/1.

Commit: 416de5a `fix(cli): dicom-mpps CID 9300 reason examples, Type 1 Modality, M/F/O and DA checks, PS3.7 Annex C status names (2026a)`.

### dicom-print (G1, 2026-10-01)

Files: `Sources/dicom-print/main.swift` (53 options + 1 argument over status/send/job/list-printers/add-printer/remove-printer), README. Evidence: PS3.3 2026a Tables C.13-1, C.13-3, C.13-5, C.13-8, C.13-9, C.11-4 (dumped by script; the print module tables have no Type column, so `diff_kit.attribute_terms` returns nothing for them and a variablelist dump of the Description cell was used), PS3.4 2026a Tables H.3.2.2.1-1/H.3.2.2.2-1, H.4-2, H.4-6, H.4-10, H.4-14 and the Annex H status tables, PS3.6 2026a Tables 6-1 and A-1. `Scripts/diff_cli.py --tool dicom-print`: 11 checks ok (15 citations matched, 22 documented defaults matched). The baseline "JPEG-LS/RLE" hit at main.swift:502 is a code comment about decoding, not a transfer-syntax label; the current script no longer flags it. No standard default exists for any film-session or film-box attribute in PS3.4 Annex H (only the recommended L0/La of H.4.2.2.1.1), so "Default (std)" is "none (SCP default)" except Polarity (NORMAL).

**Counts:** matched 11, wrong 2, missing 2, extra 2, plumbing 24 (plus 2 absent optional U/U concepts). Both wrong rows and 1 missing row are fixed. The other missing row (BIN_i for i > 2) is engine-side and deferred.

**Input contract**

| Option | DICOM concept | 2026a reference | Allowed per standard / code accepts, defaults | Verdict |
|---|---|---|---|---|
| `<url>` | TCP address of the Print SCP (pacs://host[:port]) | PS3.8 9.1.1 (well-known 104, registered 11112) | host[:port]; code default port 11112 | plumbing |
| `--aet` | Calling AE Title | PS3.8 7.1.1.3; PS3.5 Table 6.2-1 VR AE | AE <=16 chars | plumbing |
| `--called-aet` | Called AE Title | PS3.8 7.1.1.4; PS3.5 Table 6.2-1 VR AE | AE; default "ANY-SCP" is a tool convention | plumbing |
| `--timeout` | ARTIM / socket timeout | PS3.8 9.1.2 | seconds (status/job 30, send 60) | plumbing |
| `--verbose` |  |  |  | plumbing |
| `--format` | output rendering |  | text, json | plumbing |
| `<paths>` | PS3.10 files to print | PS3.10 7.1 |  | plumbing |
| `--copies` | Number of Copies (2000,0010) | PS3.3 Table C.13-1; PS3.4 Table H.4-2 U/M | IS; std default none (SCP); code 1, >=1 | match |
| `--film-size` | Film Size ID (2010,0050) | PS3.3 Table C.13-3 (12 Defined Terms) | 8INX10IN..A3 = 12 tokens (8x10..a3); term accepted as alias; std default none; code 14x17 | wrong -> fixed (help listed 9 of 12, named no term) |
| `--orientation` | Film Orientation (2010,0040) | PS3.3 Table C.13-3 | PORTRAIT, LANDSCAPE = portrait/landscape; std default none; code portrait | match |
| `--priority` | Print Priority (2000,0020) | PS3.3 Table C.13-1 (Enumerated Values) | HIGH, MED, LOW = high/medium/low; std default none; code medium | match (help now names MED) |
| `--layout` | Image Display Format (2010,0010) | PS3.3 Table C.13-3 (Enumerated Values) | STANDARD\C,R, ROW\.., COL\.., SLIDE, SUPERSLIDE, CUSTOM\i all accepted; RxC grid sent as STANDARD\C,R; std default none; code auto | match (help listed 2 of 6 forms -> fixed) |
| `--template` | layout preset (Image Display Format + Film Size ID + Film Orientation) | PS3.3 Table C.13-3 | single, comparison, grid, multi-phase | extra (tool convenience) |
| `--medium` | Medium Type (2000,0030) | PS3.3 Table C.13-1 (5 Defined Terms) | PAPER, CLEAR FILM, BLUE FILM, MAMMO CLEAR FILM, MAMMO BLUE FILM; std default none; code paper | missing -> fixed (mammo-clear-film, mammo-blue-film added) |
| `--magnification` | Magnification Type (2010,0060) | PS3.3 Table C.13-3 | REPLICATE, BILINEAR, CUBIC, NONE; std default none; code replicate | match |
| `--film-destination` | Film Destination (2000,0040) | PS3.3 Table C.13-1 | MAGAZINE, PROCESSOR, BIN_i (i>=1, no maximum); code BIN_1, BIN_2 only; std default none; code processor | missing (BIN_i for i>2: engine enum, D89) |
| `--check-status` | N-GET Printer Status (2110,0010) before printing | PS3.3 Table C.13-9; PS3.4 H.4.6 | FAILURE aborts (exit 1), WARNING warns | match |
| `--verify` | C-ECHO before printing | PS3.4 Annex A |  | plumbing |
| `--color` | Print Management Meta SOP Class negotiated | PS3.4 H.3.2.2.1 / H.3.2.2.2; PS3.6 Table A-1 | grayscale = 1.2.840.10008.5.1.1.9, color = 1.2.840.10008.5.1.1.18 | match |
| `--frame` | frame of a multi-frame source |  | >=1 | plumbing |
| `--all-frames` |  |  |  | plumbing |
| `--raw` | send stored values (no VOI/rescale) | PS3.3 Table C.13-5 |  | plumbing |
| `--window-center` | VOI window applied before sending | PS3.3 C.11.2 |  | plumbing |
| `--window-width` | VOI window applied before sending | PS3.3 C.11.2 |  | plumbing |
| `--bit-depth` | Bits Stored (0028,0101) of the Basic Grayscale Image Sequence | PS3.3 Table C.13-5 | 8, 12 (higher clamped); code default 8 | wrong -> fixed (help cited Table C.13-3; README said 16) |
| `--presentation-lut` | Presentation LUT Shape (2050,0020) | PS3.3 Table C.11-4 | IDENTITY, LIN OD; inverse = no shape, pixels inverted; std default none; code none | match (inverse: extra, documented) |
| `--palette` | pseudo-colour baked into RGB | PS3.3 Table C.13-5 (RGB only) | DICOMCore.PseudoColorPalette tokens | extra (tool feature) |
| `--annotate` | Text String (2030,0020) of Basic Annotation Box | PS3.4 H.4.4; PS3.3 Table C.13-7 | LO; position = order given | match |
| `--annotation-format` | Annotation Display Format ID (2010,0030) | PS3.3 Table C.13-3 | CS, printer Conformance Statement | match |
| `--recursive` |  |  |  | plumbing |
| `--dry-run` |  |  |  | plumbing |
| `--retries` | retry on connection/setup failure |  | >=0 | plumbing |
| `job --job-id` | Print Job SOP Instance UID (N-GET) | PS3.4 H.4.5; PS3.5 VR UI | UI | match |
| `add-printer --name` | local registry name |  |  | plumbing |
| `add-printer --host` | TCP address | PS3.8 9.1.1 |  | plumbing |
| `add-printer --port` | TCP port | PS3.8 9.1.1 (well-known 104, registered 11112) | code default 11112 | plumbing |
| `add-printer --called-ae` | Called AE Title | PS3.8 7.1.1.4; PS3.5 VR AE |  | plumbing |
| `add-printer --calling-ae` | Calling AE Title | PS3.8 7.1.1.3; PS3.5 VR AE |  | plumbing |
| `add-printer --color` | Meta SOP Class preference | PS3.6 Table A-1 | grayscale, color | plumbing |
| `add-printer --default` |  |  |  | plumbing |
| `remove-printer --name` |  |  |  | plumbing |
| `(smoothing-type)` | Smoothing Type (2010,0080) | PS3.3 Table C.13-3 (values in Conformance Statement; CUBIC only) | not offered (U/U) | absent (optional) |
| `(border/empty density, trim, polarity, min/max density)` | Border Density, Empty Image Density, Trim, Polarity, Min/Max Density | PS3.3 Tables C.13-3 / C.13-5 | not offered on send (U/U; offered by dicom-printscp simulate) | absent (optional) |

**Output contract**

| Output | Standard name / ref | Code | Verdict |
|---|---|---|---|
| `status` text: Name / Status / Status Info / Manufacturer / Model / Is Normal | Printer Name (2110,0030), Printer Status (2110,0010), Printer Status Info (2110,0020), Manufacturer (0008,0070), Manufacturer's Model Name (0008,1090): PS3.3 Table C.13-9 | DICOMPrintKit `PrintConsoleFormatter.printerStatusText` (shared with DICOMStudio) | wrong labels, engine: D90 |
| `status` JSON keys `status`, `statusInfo`, `name`, `manufacturer`, `model`, `isNormal` | PS3.6 keywords PrinterStatus, PrinterStatusInfo, PrinterName, Manufacturer, ManufacturerModelName | shared formatter | P-PRINT-JSON |
| `status` values | Printer Status NORMAL/WARNING/FAILURE (Table C.13-9) passed through; unknown or absent becomes UNKNOWN | DICOMNetwork `PrinterStatusSeverity` | match |
| `job` text: Job UID / Status / Status Info / Created | Execution Status (2100,0020) PENDING/PRINTING/DONE/FAILURE, Execution Status Info (2100,0030), Creation Date/Time (2100,0040/0050): Table C.13-8 | shared formatter | wrong labels, engine: D90 |
| `job` JSON `jobUID`, `status`, `statusInfo`, `creationDate` | PS3.6 keywords ExecutionStatus, ExecutionStatusInfo, CreationDate | shared formatter | P-PRINT-JSON |
| `send` JSON `success`, `printJobUID`, `filmSessionUID`, `filmBoxUID`(s), `printJobUIDs`, `error` | SOP Instance UIDs of Print Job / Basic Film Session / Basic Film Box (PS3.4 H.4) | shared formatter | match (tool keys, no attribute keyword applies) |
| `send` failure text for N-CREATE/N-SET/N-ACTION statuses | PS3.4 Tables H.4.1.2.1.2-1, H.4-4, H.4.2.2.1.2-1, H.4-9, H.4.3.x status names (B600–B60A, C600–C616) | DICOMNetwork `DIMSEStatus.description`: "Failed: unable to process / cannot understand (Cxxx) (0xC603)", "Unknown status (0xB605)" | wrong, engine: D91 |
| verbose banner labels | Number of Copies, Film Size ID, Film Orientation, Print Priority, Medium Type, Film Destination, Magnification Type, Presentation LUT Shape, Calling/Called AE Title | main.swift | wrong -> fixed (were Copies, Film Size, Orientation, Priority, Medium, Calling AE …; Medium printed rawValue, now wireValue) |
| `list-printers` labels / JSON | Called AE Title, Calling AE Title (PS3.8 7.1.1.3/4); JSON `calledAETitle`, `callingAETitle`, … | main.swift | wrong -> fixed labels (were "Called AE"); JSON keys match |
| exit codes | — | 0 success (status/job: the printer answered); 1 print not accepted, `--check-status` FAILURE, connection/file error; 64 usage | match. README listed 65/66/74, which the tool never returns -> fixed |

**Changes** (commit `ceeb966`): `--medium` gains `mammo-clear-film` / `mammo-blue-film`. A `StandardTermOption` protocol gives each film option a `standardTerm`: help lists `token = TERM`, and the term is accepted as an alias in any case (additive). Help was rewritten for `--film-size` (listed 9 of 12), `--priority` (MED), `--film-destination` (BIN_i note), `--layout` (6 forms; RxC is sent as STANDARD\C,R), `--bit-depth` (Table C.13-5, was C.13-3), `--color` (Meta SOP Class names/UIDs), `--presentation-lut`, `--annotate` / `--annotation-format`, `--check-status`, and the status/job discussions. Verbose and list-printers labels were fixed. README: option table, `--bit-depth` (said 8, 12 or 16), exit codes. Test target `dicom-printTests` (Package.swift hunk only): `PrintOptionTermsTests`, 9 tests, all pass. `swift build --product dicom-print` ok; `check_nema_markers.py Sources/dicom-print` exits 0.

**Deferred findings**
- D90 | DICOMPrintKit | `Sources/DICOMPrintKit/PrintConsoleFormatter.swift:21-37, 93-109` | Printer/job status labels "Name", "Status", "Status Info", "Model", "Created" instead of the PS3.3 attribute names (Printer Name, Printer Status, Printer Status Info, Manufacturer's Model Name; Execution Status, Execution Status Info, Creation Date/Time). Shared with DICOMStudio and dicom-printscp `status` | PS3.3 2026a Tables C.13-8, C.13-9; PS3.6 Table 6-1 | Low
- D91 | DICOMNetwork | `Sources/DICOMNetwork/DIMSEStatus.swift:124-160, 264-300` (used by `DICOMNetworkError.printOperationFailed`, DICOMNetworkError.swift:484) | Print Management statuses carry no Annex H name: C6xx prints as "Failed: unable to process / cannot understand (Cxxx)" and B6xx as "Unknown status". It should name e.g. 0xC603 "Failed: Image size is larger than image box size", 0xB605 "Requested Min Density or Max Density outside of printer's operating range…" (a lookup by the SOP Class of the request) | PS3.4 2026a Tables H.4.1.2.1.2-1, H.4-4, H.4.2.2.1.2-1, H.4-9, H.4.3.1.2.1.2-1, H.4.3.2.2.1.2-1, H.4.9.2.1.2-1 | Low–Medium
- D89 | DICOMNetwork | `Sources/DICOMNetwork/PrintService.swift:272-277` | `FilmDestination` has only BIN_1 and BIN_2; Table C.13-1 defines BIN_i "with no maximum", without leading zeros. Adding cases is public API: see P-BIN | PS3.3 2026a Table C.13-1 | Low

**P-items**
- P-PRINT-JSON: the shared `PrintConsoleFormatter` JSON keys (`status`, `statusInfo`, `name`, `model`, `jobUID`, `creationDate`) are not PS3.6 keywords. Proposal: add `PrinterStatus`, `PrinterStatusInfo`, `PrinterName`, `ManufacturerModelName`, `ExecutionStatus`, `ExecutionStatusInfo`, `CreationDate`/`CreationTime` alongside the old keys, keeping the old keys (deprecated in docs) for one release.
- P-BIN: replace or extend `DICOMNetwork.FilmDestination` with a `bin(Int)` form (or `.bin(n)` factory plus raw-value parsing of `BIN_n`), deprecating `.bin1` / `.bin2`; then dicom-print accepts `bin-N` / `BIN_N` for any N ≥ 1.

**Marker:** `// NEMA-verified: 2026a, checked 2026-10-01 — send option vocabularies text-diffed against PS3.3 2026a Tables C.13-1 (Print Priority 3, Medium Type 5, Film Destination MAGAZINE/PROCESSOR/BIN_i), C.13-3 (Film Size ID 12, Film Orientation 2, Magnification Type 4, Image Display Format 6 forms) and C.11-4 (Presentation LUT Shape 2): every term offered (MAMMO CLEAR FILM / MAMMO BLUE FILM added), BIN_i limited to BIN_1/BIN_2 by DICOMNetwork.FilmDestination; Bits Stored 8/12 per Table C.13-5; Meta SOP Class and Printer SOP Instance UIDs per PS3.6 Table A-1; status/job N-GET attributes per PS3.6 Table 6-1 and PS3.3 Tables C.13-8/C.13-9`

**Notes for the orchestrator:** `diff_kit.attribute_terms` requires >= 4 columns and so returns no terms for the 3-column PS3.3 C.13 / C.11-4 module tables. The terms were dumped with `<scratch>/print_terms.py` / `print_desc.py`. A 3-column fallback in attribute_terms would let diff_cli check these. The UID check counted 0 UIDs because the UIDs appear inside help sentences. They were checked against Table A-1 by dump: .9, .14, .15, .17, .18, .23.

### dicom-printscp (G1, 2026-10-01)

Files: `Sources/dicom-printscp/` DICOMPrintSCPCommand.swift (C1), EmulatorOptions.swift, InfoCommands.swift, ServeCommand.swift, SimulateCommand.swift, README (72 options over serve/simulate/status/queues). Evidence: the same PS3.3 / PS3.4 / PS3.6 2026a dumps as dicom-print, plus PS3.4 Tables H.4.4.2-1 (Basic Annotation Box: N-SET only), H.4.9.2-1 and H.4-14 (Print Job events Pending 1 / Printing 2 / Done 3 / Failure 4), PS3.3 C.13.9.1. `Scripts/diff_cli.py --tool dicom-printscp`: 11 checks ok. The inverted flags keep "(default: yes)", and their help now names the SOP Class each one controls.

**Counts:** matched 20, wrong 5, missing 3, extra 0, plumbing 38. All wrong and missing rows are fixed.

**Input contract**

| Option | DICOM concept | 2026a reference | Allowed per standard / code accepts, defaults | Verdict |
|---|---|---|---|---|
| `--port` | TCP port the SCP listens on | PS3.8 9.1.1 (well-known 104, registered 11112) | code default 11113 (avoids a local SCP on 11112) | plumbing |
| `--ae-title` | Called AE Title the SCP answers as | PS3.8 7.1.1.4; PS3.5 VR AE | code default DCMPRINT | plumbing |
| `--max-associations` |  |  | default 10 | plumbing |
| `--idle-timeout` | association idle timeout | PS3.8 9.1.2 (ARTIM) | seconds; 0 disables; default 300 | plumbing |
| `--allow-ae` | Calling AE Title accepted | PS3.8 Table 9-21 (A-ASSOCIATE-RJ reason 3) |  | plumbing |
| `--deny-ae` | Calling AE Title refused | PS3.8 Table 9-21 |  | plumbing |
| `--max-pdu` | Maximum Length sub-item | PS3.8 D.1 | bytes; default 65536 | plumbing |
| `--accept-color` | Basic Color Print Management Meta SOP Class | PS3.4 H.3.2.2.2; PS3.6 Table A-1 (1.2.840.10008.5.1.1.18) | default yes | match (help named "Color Print Management" -> fixed) |
| `--presentation-lut` | Presentation LUT SOP Class N-CREATE | PS3.4 H.4.9, Table H.4.9.2-1; PS3.6 Table A-1 (1.2.840.10008.5.1.1.23) | default yes | match |
| `--annotation-box` | Basic Annotation Box SOP Class N-SET | PS3.4 Table H.4.4.2-1 (N-SET only); PS3.6 Table A-1 (1.2.840.10008.5.1.1.15) | default yes | wrong -> fixed (help said N-CREATE / N-SET) |
| `--annotation-boxes-per-film` | Referenced Basic Annotation Box Sequence (2010,0520) item count | PS3.4 Table H.4-6 | default 6 | plumbing |
| `--push-job-events` | Print Job N-EVENT-REPORT | PS3.4 H.4.5, Table H.4-14 | Done (Event Type ID 3) only | wrong -> fixed (help implied several events) |
| `serve --film-size` | Film Size ID (2010,0050) accepted | PS3.3 Table C.13-3 (12 Defined Terms) | all 12 tokens, term accepted as alias; default all | match (help now names terms) |
| `serve --medium` | Medium Type (2000,0030) accepted | PS3.3 Table C.13-1 (5 Defined Terms) | all 5; default all | match |
| `--max-image-boxes` | image boxes per Image Display Format | PS3.3 Table C.13-3 | default 64 | plumbing |
| `--max-image-dimension` |  |  | default 10000 | plumbing |
| `--printer-name` | Printer Name (2110,0030) | PS3.3 Table C.13-9; PS3.6 Table 6-1 | LO | match |
| `--manufacturer` | Manufacturer (0008,0070) | PS3.3 Table C.13-9; PS3.6 Table 6-1 | LO | match |
| `--model` | Manufacturer's Model Name (0008,1090) | PS3.6 Table 6-1 | LO | wrong -> fixed (help said "Manufacturer Model Name") |
| `--serial-number` | Device Serial Number (0018,1000) | PS3.6 Table 6-1 | LO | match |
| `--software-version` | Software Versions (0018,1020) | PS3.6 Table 6-1 | LO 1-n | wrong -> fixed (help said "Software Version") |
| `--printer-status` | Printer Status (2110,0010) | PS3.3 Table C.13-9 (Enumerated Values) | NORMAL, WARNING, FAILURE = normal/warning/failure; default normal | match |
| `--status-info` | Printer Status Info (2110,0020) | PS3.3 Table C.13-9; C.13.9.1 (108 Defined Terms) | free CS; empty = the status default term | match (Defined Terms extensible) |
| `--dpi` | composition resolution |  | default 300 | plumbing |
| `--density` | P-Value to grey mapping | PS3.14 7 (gsdf) | paper, film, gsdf | plumbing |
| `--margin-mm` |  |  |  | plumbing |
| `--cell-spacing-mm` |  |  |  | plumbing |
| `--annotations` | draw Basic Annotation Box text | PS3.3 Table C.13-7 | default yes | plumbing |
| `--trim-marks` | draw Trim (2010,0140) = YES | PS3.3 Table C.13-3 | default yes; draws sheet-corner marks, not a trim box per image (D92) | plumbing |
| `--max-pixels` |  |  |  | plumbing |
| `--output` |  |  | png, tiff, pdf, none | plumbing |
| `--output-dir` |  |  |  | plumbing |
| `--name-pattern` |  |  |  | plumbing |
| `--paper-queue` |  |  |  | plumbing |
| `--allow-paper` |  |  |  | plumbing |
| `--open` |  |  |  | plumbing |
| `--config` |  |  |  | plumbing |
| `--save-config` |  |  |  | plumbing |
| `--max-films` |  |  |  | plumbing |
| `--duration` |  |  |  | plumbing |
| `--format` | output rendering |  | text, json | plumbing |
| `--verbose` |  |  |  | plumbing |
| `--quiet` |  |  |  | plumbing |
| `simulate <paths>` | PS3.10 files | PS3.10 7.1 |  | plumbing |
| `simulate --layout` | Image Display Format (2010,0010) | PS3.3 Table C.13-3 | grid RxC (STANDARD\C,R) + STANDARD/ROW/COL/SLIDE/SUPERSLIDE/CUSTOM forms | missing -> fixed (only grid tokens were accepted) |
| `simulate --film-size` | Film Size ID (2010,0050) | PS3.3 Table C.13-3 | 12 terms; code default 14x17 | match |
| `simulate --orientation` | Film Orientation (2010,0040) | PS3.3 Table C.13-3 | PORTRAIT, LANDSCAPE | match |
| `simulate --magnification` | Magnification Type (2010,0060) | PS3.3 Table C.13-3 | 4 terms | match |
| `simulate --medium` | Medium Type (2000,0030) | PS3.3 Table C.13-1 | 5 terms | match |
| `simulate --copies` | Number of Copies (2000,0010) | PS3.3 Table C.13-1 | >=1 (clamped) | match |
| `simulate --polarity` | Polarity (2020,0020) | PS3.3 Table C.13-5 | NORMAL, REVERSE; std default NORMAL = code | match |
| `simulate --presentation-lut` | Presentation LUT Shape (2050,0020) | PS3.3 Table C.11-4 | IDENTITY, LIN OD; inverse rendered | match |
| `simulate --trim` | Trim (2010,0140) | PS3.3 Table C.13-3 | YES/NO; code default NO | match |
| `simulate --border-density` | Border Density (2010,0100) | PS3.3 Table C.13-3 | BLACK, WHITE, i hundredths of OD; code default BLACK | missing -> fixed (i added) |
| `simulate --empty-density` | Empty Image Density (2010,0110) | PS3.3 Table C.13-3 | BLACK, WHITE, i; code default BLACK | missing -> fixed (i added) |
| `simulate --annotate` | Text String (2030,0020) | PS3.3 Table C.13-7 | LO | match |
| `simulate --annotation-format` | Annotation Display Format ID (2010,0030) | PS3.3 Table C.13-3 | CS | match |
| `simulate --color` | Basic Grayscale / Color Image Box SOP Class | PS3.4 H.4.3; PS3.6 Table A-1 | grayscale, color | match |
| `simulate --frame` |  |  |  | plumbing |
| `simulate --all-frames` |  |  |  | plumbing |
| `simulate --raw` |  |  |  | plumbing |
| `simulate --window-center` |  | PS3.3 C.11.2 |  | plumbing |
| `simulate --window-width` |  | PS3.3 C.11.2 |  | plumbing |
| `simulate --bit-depth` | Bits Stored (0028,0101) | PS3.3 Table C.13-5 | 8, 12 | wrong -> fixed (help said 8, 12 or 16; 16 was refused) |
| `simulate --recursive` |  |  |  | plumbing |
| `simulate --calling-ae` | Calling AE Title recorded | PS3.5 VR AE | default SIMULATE | plumbing |

**Output contract**

| Output | Standard name / ref | Code | Verdict |
|---|---|---|---|
| `status` text / JSON | Printer Status / Printer Status Info / Printer Name … (Table C.13-9) | `PrintSCPConsole.printerStatusText` → shared `PrintConsoleFormatter` | wrong labels, engine: D90; JSON keys P-PRINT-JSON |
| Printer Status values reported to N-GET | NORMAL, WARNING, FAILURE (Table C.13-9); default Status Info terms per C.13.9.1 (FAILURE → SUPPLY EMPTY) | DICOMPrintKit `EmulatedPrinterStatus` (verified in DICOMPRINTKIT report) | match |
| Request-failure log line / Error Comment (0000,0902) | Annex H status names | `"<command> failed (0xC603): <PrintSCPStatus.explanation>"`; 6 of 9 Annex H codes paraphrased (B604, B605, B609, C603, C605, C613), 3 match, by script | wrong, engine: D93 |
| film line / `--verbose` film detail | Film Size ID, Image Display Format, Film Orientation, Medium Type, Number of Copies, Magnification Type, Border/Empty Image Density, Trim, Min/Max Density, Presentation LUT Shape: values are the received terms | `PrintSCPConsole.filmLine/filmDetail` (short labels "Film", "Magnify", "LUT shape") | match on values; labels are the engine's (minor, included in D93) |
| film JSON | `ComposedFilm.info.jsonRepresentation` | engine | not re-checked (DICOMPrintKit report) |
| `--trim-marks` rendering | Trim YES: "a trim box shall be printed surrounding each image" (Table C.13-3) | sheet-corner crop marks | wrong, engine: D92 (help now says what is drawn) |
| exit codes | — | 0 success / listener stopped for its configured reason; 1 bad option value (PrintSCPCommandError), port in use, unreadable input; 64 ArgumentParser usage | match (README) |

**Changes** (commit `deb66db`):
- EmulatorOptions: `--model` "Manufacturer's Model Name (0008,1090)" and `--software-version` "Software Versions (0018,1020)", per PS3.6 Table 6-1.
- `--annotation-box` is N-SET only (help said N-CREATE / N-SET).
- `--push-job-events` sends Done (3) only, as the engine does.
- `--accept-color`, `--presentation-lut` and `--annotation-box` name their SOP Class and UID.
- `--film-size` / `--medium` list `token = TERM`.
- `OptionTokens.validate` accepts the standard term as an alias (additive).
- SimulateCommand:
  - `--layout` accepts the Image Display Format forms (missing).
  - `--border-density` / `--empty-density` accept i hundredths of OD (missing; leading zeros stripped).
  - `--bit-depth` help is "8 or 12, Table C.13-5" (said 8, 12 or 16).
  - All film-box options name their attribute and term.
- Info and Serve discussions name the Printer SOP Instance UID and the N-GET attributes.
- README updated, including `--density gsdf`, which it omitted.
- Test target `dicom-printscpTests` (Package.swift hunk only; other agents' wado/gateway hunks were left unstaged): `EmulatorOptionTermsTests`, 6 tests, all pass.

`swift build --product dicom-printscp` ok; `check_nema_markers.py Sources/dicom-printscp` exits 0 (5/5).

**Deferred findings**
- D93 | DICOMNetwork | `Sources/DICOMNetwork/PrintSCPTypes.swift:91-115` (`PrintSCPStatus.explanation`, also the default Error Comment) | 6 of 9 Annex H codes paraphrased. B604 should read "Image size is larger than image box size, the image has been demagnified.", B605 "Requested Min Density or Max Density outside of printer's operating range. The printer will use its respective minimum or maximum density value instead.", B609 "Image size is larger than the Image Box size. The Image has been cropped to fit.", C603 "Failed: Image size is larger than image box size", C605 "Failed: Insufficient memory in printer to store the image", C613 "Failed: Combined Print Image size is larger than the Image Box size" | PS3.4 2026a Tables H.4-4, H.4-9, H.4.2.2.1.2-1, H.4.3.1.2.1.2-1, H.4.3.2.2.1.2-1 | Low
- D92 | DICOMPrintKit | `Sources/DICOMPrintKit/Printing/FilmComposer.swift:817-838` | Trim = YES is drawn as four crop marks at the sheet corners; Table C.13-3 says "a trim box shall be printed surrounding each image on the film" | PS3.3 2026a Table C.13-3 Trim (2010,0140) | Low (emulator fidelity)
- (shared) D90 for the `status` labels.

**P-items:** none new (P-PRINT-JSON from dicom-print also covers `dicom-printscp status --format json`).

**Markers:**
- EmulatorOptions.swift: `// NEMA-verified: 2026a, checked 2026-10-01 — option vocabularies text-diffed against PS3.3 2026a Tables C.13-1 (Medium Type 5), C.13-3 (Film Size ID 12) and C.13-9 (Printer Status 3; Printer Status Info per C.13.9.1) via the DICOMPrintKit catalog: all offered, each term also accepted as an alias; 7 identity attribute names/tags per PS3.6 2026a Table 6-1 (Software Versions, Manufacturer's Model Name corrected); 4 SOP Class names/UIDs per PS3.6 Table A-1; DIMSE services per PS3.4 Tables H.4.4.2-1 (Annotation Box N-SET only), H.4.9.2-1, H.4-14 (Done = 3)`
- SimulateCommand.swift: `… film-box option vocabularies text-diffed against PS3.3 2026a Tables C.13-1 (Medium Type 5), C.13-3 (Film Size ID 12, Film Orientation 2, Magnification Type 4, Image Display Format 6 forms, Border/Empty Image Density BLACK/WHITE/i, Trim 2), C.13-5 (Polarity 2 with default NORMAL; Bits Stored 8/12) and C.11-4 (Presentation LUT Shape 2): all match (Image Display Format forms and numeric densities added in this pass)`
- InfoCommands.swift: `… status names the N-GET attributes per PS3.3 2026a Table C.13-9 / PS3.6 Table 6-1 and the Printer SOP Instance UID per PS3.6 Table A-1; the text/JSON is DICOMPrintKit's PrintConsoleFormatter (labels reported as a deferred finding); queues carries no DICOM-standard data`
- ServeCommand.swift: `… Printer SOP Instance UID (PS3.6 2026a Table A-1) and PS3.4 H.4.6 citation checked; otherwise carries no DICOM-standard data (listener lifecycle, console routing)`
- DICOMPrintSCPCommand.swift: `… carries no DICOM-standard data (ArgumentParser shell, output-format enum, console routing, error type)`

### dicom-server (G1) — 2026-10-01

Bucket: B2 (no citation; data gaps). **The executable target is commented out in Package.swift
("Phase 1 scope") and does not compile**: a typecheck of the 9 files against the current build
products (`swiftc -typecheck`) gives 5 errors in DICOMServer.swift and ~30 in ServerSession.swift
(`DataSet.read(from:)`, `PresentationContextAccept`, `DIMSEStatus.processingFailure`,
`.pending(warningOptionalKeys:)`, `CFindResponse(hasDataSet:)`, `StorageService`, `EchoService`,
`AETitle` vs `String`, `DICOMClient(callingAETitle:)`, top-level code beside `@main`). So no XCTest
can exercise it; fixes were limited to data whose evidence is script-diffed, and the behavioural
gaps are recorded as D-DICOM-SERVER rows. `Tests/DICOMToolsTests/DICOMServerTests.swift` is compiled
by no target (README now says so).

Evidence scripts (scratch): server_checks.py (Table 6-1: DB columns, metadata fields, helper VRs),
server_std.py (B.5-1/GG.3-1, B.2-1, C.4-1..3, C.6.x, PS3.8 9-18/9-21), diff_cli.py --tool dicom-server.
DataSetExtensions behaviour checked with an ad-hoc link of the file against the built DICOMKit
objects (13 tags: VRs LO/PN/SH/SH/LO/LO/CS/DA/TM/IS/IS/UI/UI, UI NUL-padded).

#### Input contract (24 options)

| Option | DICOM concept | 2026a ref | Standard values | Code | Std default | Code default | Verdict |
|---|---|---|---|---|---|---|---|
| start --aet | Called AE Title | PS3.5 Table 6.2-1 AE; PS3.8 9.3.2 | ≤16 chars | any string, unchecked | — | DICOMKIT_SCP | plumbing (D94) |
| start --port | TCP port | PS3.8 9.1.1 | 104 well-known, else 11112 | UInt16 | 104/11112 | 11112 | plumbing (match) |
| start --data-dir / --database / --database-url / --config | storage, index | — | — | sqlite/postgres/none (in-memory; postgres throws) | — | ./dicom-data, sqlite | plumbing |
| start --max-connections | association limit | — | — | Int | — | 10 | plumbing |
| start --max-pdu-size | Maximum Length | PS3.8 D.1, PS3.7 D.3.3.1 | 0 = unlimited | UInt32; used to fragment *outgoing* PDUs, not advertised in the AC | — | 16384 | plumbing (D95) |
| start --allowed-ae / --blocked-ae | reject unknown Calling AE | PS3.8 Table 9-21 | result 1 rejected-permanent, source 1 service-user, reason 3 calling-AE-title-not-recognized | 1/1/3 | — | none | match (2) |
| start --verbose / --tls | logging / TLS | PS3.15 B.1 (TLS not implemented) | — | flags | — | false | plumbing |
| status/stats --host, --port, --calling-ae, --called-ae, --verbose | C-ECHO SCU | PS3.8 9.1.1; PS3.5 AE | 11112; ≤16 | AETitle-checked by DICOMNetwork | — | localhost, 11112, DICOM_ECHO/DICOM_STATS, DICOMKIT_SCP | plumbing (10); `-h` for --host collides with ArgumentParser help |
| stop --port, --verbose | none (prints SIGINT hint) | — | — | — | — | 11112 | plumbing (2) |

Counts: matched 2, wrong 0, missing 0, extra 0, plumbing 22.

#### Output contract

| Item | 2026a ref | Standard | Code | Verdict |
|---|---|---|---|---|
| UID literals (16) and names beside them (15) | PS3.6 Table A-1 | A-1 Name | 8 names wrong (CR, PET, 6 × "Q/R"), 3 shortened | **wrong → fixed** (8+3) |
| Storage SOP Classes accepted | PS3.4 Table B.5-1 (+GG.3-1: 179) | — | 5 (CT, MR, CR, SC, PET), all in B.5-1 | match (subset; 174 not accepted) |
| Q/R models accepted | PS3.4 C.6.1 / C.6.2 | Patient Root, Study Root FIND/MOVE/GET | 6 | match |
| Transfer syntaxes accepted | PS3.6 A-1 | — | Explicit VR LE, Implicit VR LE, Explicit VR BE (Retired) | match (BE retired, still accepted) |
| Application Context Name | PS3.6 A-1 | 1.2.840.10008.3.1.1.1 | same | match |
| Implementation Class UID / Version Name | PS3.7 D.3.3.2 | UID ≤64, name 1–16 chars | 1.2.826.0.1.3680043.9.7433.1.2 / DICOMKIT_SCP | plumbing (UID not DICOMKit's root, D94) |
| Presentation-context result | PS3.8 Table 9-18 | 0 acceptance, 3 abstract-syntax-not-supported, 4 transfer-syntaxes-not-supported | 0/3/4 | match |
| A-ASSOCIATE-RJ on decode error | PS3.8 Table 9-21 | result 2 transient, source 2 ACSE, reason 1 no-reason-given | 2/2/1 | match |
| C-ECHO status | PS3.7 9.1.5 | 0000 | 0000 | match |
| C-STORE statuses | PS3.4 Table B.2-1, PS3.7 C | 0000; failure A7xx/A9xx/Cxxx | 0000 / 0110 Processing failure | match (0110 is a PS3.7 general failure) |
| C-FIND statuses | PS3.4 Table C.4-1 | FF00, 0000, A700, A900, Cxxx | FF00, 0000, 0110 | match |
| C-MOVE statuses | PS3.4 Table C.4-2 | FF00, 0000, B000 "Sub-operations Complete - One or more Failures", A801 "Refused: Move Destination unknown" | FF00, 0000, B000, 0110; A801 never sent | **missing A801** (D96) |
| C-GET statuses | PS3.4 Table C.4-3 | FF00, 0000, B000 | FF00, 0000, B000, 0110 | match (counts unreliable, D97) |
| C-FIND response VRs | PS3.6 Table 6-1 | LO/PN/SH/SH/LO/LO… | 6 of 19 tags CS | **wrong → fixed** (dictionary VR) |
| C-FIND keys / matching | PS3.4 C.2.2.2, C.4.1.1.3.2, Tables C.6-1..C.6-5 | 15 R/U keys; UID list, range, case-sensitive wildcard; Q/R Level in response | 9 of 15 keys; see D98/3 | **missing** (deferred) |
| Help/README level names | PS3.4 Tables C.6.1-1 / C.6.2-1 | PATIENT, STUDY, SERIES, IMAGE | "Instance" | **wrong → fixed** |
| `stats` labels C-ECHO, C-STORE, C-FIND, C-MOVE, C-GET | PS3.7 9.1.1–9.1.5 | same | same | match (5) |
| DATABASE_SCHEMA.md columns | PS3.6 Table 6-1 keywords | — | 21 of 26 columns are snake_case of a keyword (e.g. patient_birth_date = PatientBirthDate); 5 plumbing (created_at, updated_at, file_path, file_size, transfer_syntax_uid); widths ≥ VR max (LO 64, UI 64, CS 16, PN, SH) | match (report only) |
| DICOMMetadata fields | PS3.6 keywords | — | 11 attribute fields name keywords; filePath plumbing | match |
| Exit codes | — | — | status/stats: 0 reachable, 1 not | plumbing |

#### Commit
d9cd70b `fix(cli): dicom-server PS3.6 2026a VRs for C-FIND response elements, Table A-1 SOP Class names, IMAGE level name; markers on 9 files` — DataSetExtensions.swift (dictionary VR), ServerSession.swift (A-1 names), DICOMServer.swift + README (level names, build-status note), markers on all 9 files, CHANGELOG bullet. `check_nema_markers.py Sources/dicom-server`: 9/9. `diff_cli.py --tool dicom-server`: 0 FAIL (A-1 names 15/15). No swift build/test possible (target excluded).

#### Deferred findings (orchestrator assigns D-numbers)
| ID | File:line | Problem | Ref | Severity |
|---|---|---|---|---|
| D99 | Package.swift:214, 1140; DICOMServer.swift; ServerSession.swift | Target excluded and ~35 compile errors against the current DICOMNetwork/DICOMKit API; DICOMServerTests compiled by no target | — | High |
| D98 | DatabaseManager.swift `matchesWildcard` | Wildcard applied to UI keys (C.2.2.2.4 lists AE, CS, LO, LT, PN, SH, ST, UC, UR, UT only), case-insensitive for non-PN (C.2.2.2.4 "case sensitive, except PN"), no List of UID Matching (C.2.2.2.2), no Range Matching for Study Date (C.2.2.2.5) | PS3.4 C.2.2.2 | Medium |
| D100 | DatabaseManager.swift query*Level | Required keys not matched/returned: Study Time, Accession Number, Study ID (C.6-2), Patient's Name at Study level (C.6-5), Series Number (C.6-3), Instance Number (C.6-4); responses carry a fixed attribute set instead of the requested keys and omit Query/Retrieve Level (C.4.1.1.3.2) | PS3.4 Tables C.6-1..C.6-5, C.4.1.1.3.2 | Medium |
| D101 | ServerSession.swift handleCFind/CMove/CGet (`?? "STUDY"`) | Missing Query/Retrieve Level (0008,0052) defaults to STUDY; the request Identifier "shall contain" it (C.4.1.1.3.1 / C.4.2.1.4.1) — should fail A900 | PS3.4 C.4.1.1.3.1, Table C.4-1 | Low |
| D96 | ServerSession.swift sendToDestination (fallback `("localhost", 104, destination)`) | Unknown Move Destination is sent to localhost:104 instead of status A801 "Refused: Move Destination unknown" | PS3.4 Table C.4-2 | Medium |
| D97 | ServerSession.swift sendViaCStore | C-GET sub-operations counted Completed without awaiting C-STORE-RSP; no SCP/SCU Role Selection; only the 5 accepted storage classes can be returned | PS3.4 C.4.3.3.1; PS3.7 D.3.3.4 | Medium |
| D102 | StorageManager.swift storeFile; ServerSession.swift handleCStore | Stored files lack preamble/DICM/File Meta (PS3.10 7.1) and the data set is parsed without the negotiated transfer syntax; sendViaCStore then rejects every stored file (no DICM) | PS3.10 7.1; PS3.5 10 | High |
| D95 | ServerSession.swift sendDIMSEResponse / sendAssociationAccept | Outgoing P-DATA fragmented to the server's own --max-pdu-size instead of the peer's Maximum Length; AC does not carry the server's Maximum Length | PS3.8 D.1; PS3.7 D.3.3.1 | Medium |
| D94 | DICOMServer.swift StartCommand; ServerSession.swift implementationClassUID | --aet / --allowed-ae / --blocked-ae not validated as VR AE (16 chars); Implementation Class UID 1.2.826.0.1.3680043.9.7433.1.2 is not under DICOMKit's root (1.2.826.0.1.3680043.10.511) | PS3.5 Table 6.2-1, 9.1 | Low |

P-items: none.

Marker text (ServerSession.swift, representative): `// NEMA-verified: 2026a, checked 2026-10-01 — 16 UID literals are registered in PS3.6 2026a Table A-1 and the 15 names written next to them match it (8 wrong SOP Class names corrected; 3 shortened names …completed…); A-ASSOCIATE-RJ result/source/reason 1/1/3 and 2/2/1 and presentation-context results 0/3/4 match PS3.8 2026a Tables 9-21 / 9-18; the 5 accepted Storage SOP Classes are in PS3.4 2026a Table B.5-1 (5 of 179); C-MOVE / C-GET final statuses 0000 / B000 match Tables C.4-2 / C.4-3; …D101..8`. C1 files: ServerConfiguration, PACSServer, ServerLogger ("carries no DICOM-standard data (…)").

diff_cli.py: nothing to add; a check for "VR chosen in a hand-written switch vs Table 6-1" (server_checks.py §3) could be generalised.

### dicom-gateway (G1) — 2026-10-01

Bucket: B2. HL7 v2 (ER7, XPN, CX, EI, DTM, table 0001), FHIR R4 and IHE are **not NEMA standards —
plumbing**; only the DICOM side was checked. The gateway cites no PS3.17 clause (no citation found;
part17 not fetched). Evidence scripts (scratch/reports): gw_std.py (PS3.3 C.7-1/C.7-3/C.7-5a/C.12-1
types, Patient's Sex terms, Modality terms vs D-1 / CID 29 / CID 33, PS3.5 Table 6.2-1, PS3.16
Table 8-1), gw_checks.py (VRs written vs Table 6-1, MappingEngine names vs keywords), diff_cli.py.

#### Input contract (33 options)

| Option | Concept | 2026a ref | Standard values | Code | Verdict |
|---|---|---|---|---|---|
| dicom-to-hl7 `<input>` | Part 10 file; Patient's Name read as PN | PS3.5 6.2.1 | first component group; family^given^middle^prefix^suffix | was split across "=" groups and 4-component names mis-ordered | **wrong → fixed** |
| dicom-to-hl7 --output, --verbose | path, output | — | — | — | plumbing (2) |
| dicom-to-hl7 --message-type | HL7 type (not NEMA) | — | ADT, ORM, ORU | same | plumbing |
| dicom-to-hl7 --event-type | HL7 trigger (not NEMA) | — | A01… | sent "ADT^AA01" | plumbing (bug fixed) |
| hl7-to-dicom `<input>`, --template, --verbose | HL7 file, template, output | PS3.10 7.1 | — | — | plumbing (3) |
| hl7-to-dicom --output | DICOM values written | PS3.5 Table 6.2-1, 6.2.1, 9.1; PS3.3 Table C.7-1 | PN 5 components (≤4 "^"); DA YYYYMMDD; TM HH[MM[SS[.F≤6]]]; Patient's Sex M/F/O (Type 2 empty); SH ≤16; LO ≤64; UID syntax | 4-comp XPN put suffix in prefix slot; partial dates written as DA; CX/EI components written whole; UID check digits-only; UIDs + File Meta under other arcs of 1.2.826.0.1.3680043.10 | **wrong → fixed** |
| dicom-to-fhir `<input>` | PN → HumanName | PS3.5 6.2.1 | first group; middle name kept | given only, middle dropped | **wrong → fixed** (with the PN row above: 1 row) |
| dicom-to-fhir --resource | FHIR type; ImagingStudy.modality system | PS3.16 Table 8-1 (DCM FHIR URI) | http://dicom.nema.org/resources/ontology/DCM | same | match |
| dicom-to-fhir --output, --pretty, --verbose | — | — | — | — | plumbing (3) |
| fhir-to-dicom `<input>`, --template, --verbose | FHIR JSON, template | — | — | — | plumbing (3) |
| fhir-to-dicom --output | DICOM values written | as hl7-to-dicom --output | as above | given names joined in one component; partial dates and "+05:30" zones written into DA/TM; Study UID unchecked | **wrong → fixed** |
| batch `<conversion-type>`, `<input-pattern>`, --output, --type, --verbose | — | — | — | — | plumbing (5) |
| listen --protocol, --port (2575), --forward, --message-types, --verbose | HL7 listener; PACS forward is a stub | PS3.8 9.1.1 for pacs://…:11112 | — | — | plumbing (5) |
| forward --listen-port | DICOM port | PS3.8 9.1.1 | 11112 registered | 11112; no PS3.8 UL behind it | plumbing (match default; D103) |
| forward --forward-hl7, --forward-fhir, --message-type, --verbose | — | — | — | — | plumbing (4) |

Counts: matched 1, wrong 3 (all fixed), missing 0, extra 0, plumbing 29.

#### Output contract

| Item | 2026a ref | Standard | Code | Verdict |
|---|---|---|---|---|
| VRs of the 16 / 14 elements written by HL7ToDICOMConverter / FHIRConverter | PS3.6 Table 6-1 | — | all match (gw_checks.py) | match (30) |
| Issuer of Patient ID (0010,0021) from CX.4 | PS3.3 Table C.7-1 (Type 3, LO) | — | new | missing → added |
| Patient's Sex | PS3.3 Table C.7-1 | Enumerated M, F, O (Type 2) | M/F/O or empty from HL7 0001 / FHIR gender | match |
| Patient's Birth Date / Study Date | PS3.5 Table 6.2-1 DA | YYYYMMDD | full date only; partial → empty (birth) / omitted (study) | wrong → fixed |
| Study Time | PS3.5 Table 6.2-1 TM | HHMMSS.FFFFFF, reduced precision right-truncated | HH/HHMM/HHMMSS + fraction; zone dropped | wrong → fixed |
| Accession Number | PS3.5 SH 16 | ≤16 chars | EI.1; stderr warning above 16 (value kept) | match (warn) |
| Modality | PS3.3 C.7.3.1.1.1; PS3.16 CID 29/33 | 147 terms (union), OT in CID 33 not CID 29 | DICOMCore.Modality.normalized (verified in DICOMCore); unknown codes kept as CS | match (delegated) |
| SOP Class of created file | PS3.6 A-1 | 1.2.840.10008.5.1.4.1.1.7 Secondary Capture Image Storage | same | match; IOD incomplete (D104) |
| Generated UIDs / Implementation Class UID | PS3.5 9.1 | under the organisation's root | was 1.2.826.0.1.3680043.10.<timestamp>.<rand> and …10.1078 (other registrants' arcs); now UIDGenerator / DICOMFile.create (…10.511) | wrong → fixed |
| IHEProfiles PDI labels | PS3.3 C.7-1, C.7-3 | Patient ID / Patient's Name / Birth Date / Study Date are Type 2 | "Required Type 1", "recommended" | wrong → fixed |
| IHEProfiles Timezone Offset From UTC | PS3.3 C.12.1.1.8 | "&ZZXX" with minutes | hours only (+0500 for +05:30, -0300 for -03:30) | wrong → fixed |
| IHEProfiles Instance Creator UID example | PS3.5 9.1 | numeric, own root | "1.2.840.113619.DICOMKit" (GE root, letters) | wrong → fixed |
| MappingEngine tag names (12) | PS3.6 keywords | — | all keywords | match |
| README attribute names | PS3.6 Table 6-1 | Patient's Name, Patient's Birth Date, Patient's Sex | Patient Name, Birth Date, Sex | wrong → fixed; HL7→DICOM table added |
| Exit codes | — | — | thrown errors → ArgumentParser exit 1 | plumbing |

#### Commit / tests
95dcd11 `fix(cli): dicom-gateway PN/DA/TM/Patient's Sex/UID values per PS3.5 and PS3.3 2026a, own UID root, ADT event; dicom-gatewayTests` — new Sources/dicom-gateway/DICOMValueMapping.swift; HL7ToDICOMConverter, DICOMToHL7Converter, FHIRConverter, IHEProfiles, README; markers on 10 files; Package.swift test target `dicom-gatewayTests` (only this hunk); Tests/dicom-gatewayTests/DICOMValueMappingTests.swift; CHANGELOG bullet.
`swift build --product dicom-gateway`: OK. `swift test --filter DICOMValueMappingTests`: 14 tests, 0 failures. `check_nema_markers.py Sources/dicom-gateway`: 10/10. `diff_cli.py --tool dicom-gateway`: 0 FAIL.

#### Deferred findings
| ID | File:line | Problem | Ref | Severity |
|---|---|---|---|---|
| D104 | HL7ToDICOMConverter.swift / FHIRConverter.swift createBasicDICOMFile | Without --template the output claims Secondary Capture Image Storage but has no Image Pixel Module and no Type 1 Conversion Type (0008,0064) — not a conforming SC instance; an MWL-shaped output (PS3.4 Table K.6-1) or a template requirement is a design decision | PS3.3 A.8.1; PS3.4 K.6-1 | Medium |
| D103 | GatewayListener.swift handleDICOMClient / forwardToPACS | `forward --listen-port` accepts TCP but implements no PS3.8 Upper Layer / C-STORE SCP; `listen --forward pacs://` only prints "Would forward" | PS3.8 9; PS3.4 B | Low (help overstates) |

P-items: none (no option, value or JSON key renamed; `--event-type` still takes "A01").
Marker (DICOMValueMapping.swift): `// NEMA-verified: 2026a, checked 2026-10-01 — the DICOM side of the HL7 v2 / FHIR mappings: PN five components and the "=" component groups of PS3.5 2026a Table 6.2-1 / 6.2.1, DA (YYYYMMDD) and TM (HHMMSS.FFFFFF) of Table 6.2-1, SH 16 / LO 64 characters, Patient's Sex Enumerated Values M, F, O of PS3.3 2026a Table C.7-1, UID syntax of PS3.5 9.1 … HL7 v2 … and FHIR … are not NEMA standards and are treated as plumbing`.

### dicom-wado (G1, PS3.18 2026a)

Files: DICOMWado.swift (bucket B2), WADOOptionRules.swift (new, A). Commit `39da529`.
Scripts: `Scripts/diff_cli.py --tool dicom-wado` (11 ok, 0 fail); new `Scripts/diff_cli_web.py` (0 fail) —
engine checks rerun over Sources/DICOMWeb, the code every subcommand calls (diff_web.py): F.2.3-1 VR→JSON 34/34 (encoder and decoder),
media types 19 match + 1 extra (application/json), URI templates 31 match / 7 missing (bulkdata, pixeldata, ?workitem create, suspend) / 5 known extensions,
RESTful query parameter names 15 match / 13 missing (volume rendering), WADO-URI buildURL 10 match / 9 optional absent, contentType 7/7,
Table 10.6.1-5 QIDOQueryAttribute 20/20, UPS methods 14/14. Tool-level: WADO-URI parameters reachable 10 of 19; contentType 7/7 valid (8 of 15 Rendered Media Types not requestable);
help lists exactly the 7; QIDO parameters 4 of 7; levels 3/3; matching keys 12 of 20; UPS transactions 6 of 8; Change State targets 3/3 (11.7.1.4);
C.30.1-1 states 4/4, C.30.2-1 priorities 3/3, C.7-1 sexes 3/3; query JSON keys 27/27 PS3.6 keywords; ups JSON keys 0/18 keywords (camelCase).

**Counts: matched 52, wrong 6, missing 9, extra 3, plumbing 18** (88 rows; 79 options + 9 grouped/qualified rows).

**Input contract**

| Option | DICOM concept | 2026a reference | Allowed / code accepts | Verdict |
|---|---|---|---|---|
| `retrieve <base-url>` | Studies Service base URI / URI service endpoint | PS3.18 Table 10.1-1; 9.1 | http(s) URL; /rs rewritten to /wado with --uri (dcm4chee) | plumbing |
| `retrieve --study` | Study Instance UID: {study} path segment / studyUID | PS3.18 Tables 10.4.1-1, 9.1.2-1 | UID; required (M in 9.1.2-1) | match |
| `retrieve --series` | Series Instance UID: {series} / seriesUID | PS3.18 Tables 10.4.1-1, 9.1.2-1 | UID; required with --uri | match |
| `retrieve --instance` | SOP Instance UID: {instance} / objectUID | PS3.18 Tables 10.4.1-1, 9.1.2-1 | UID; required with --uri | match |
| `retrieve --frames` | {frameList} (RS) / frameNumber (URI) | PS3.18 Table 10.4.1.6-1; 9.5.1.2.1 | RS: comma list of positive ints; URI: one positive int | wrong (URI: 0/text sent or dropped; fixed 39da529) |
| `retrieve --uri` | URI service (WADO-URI), requestType=WADO | PS3.18 9.1.2.1.1 | "WADO" | match |
| `retrieve --content-type` | contentType | PS3.18 9.1.2.2.1; Table 8.7.4-1 | application/dicom or a Rendered Media Type (15 in 8.7.4-1); tool: 7 | wrong (unknown value silently fetched application/dicom; fixed 39da529) |
| `retrieve --transfer-syntax` | transferSyntax | PS3.18 9.4.1.2.3, Table 9.4.1-1 | one Transfer Syntax UID | missing (added 39da529) |
| `retrieve --anonymize` | anonymize=yes | PS3.18 9.4.1.2.1, Table 9.4.1-1 | "yes" | missing (added 39da529) |
| `retrieve --rows` | rows | PS3.18 9.5.1.2.4.1, Table 9.5.1-1 | positive integer | missing (added 39da529) |
| `retrieve --columns` | columns | PS3.18 9.5.1.2.4.2, Table 9.5.1-1 | positive integer | missing (added 39da529) |
| `(retrieve: charset, annotation, imageAnnotation, imageQuality, region, windowCenter, windowWidth, presentationUID, presentationSeriesUID)` | optional WADO-URI parameters | PS3.18 Tables 9.1.2-2, 9.4.1-1, 9.5.1-1 | O; not in WADOURIClient.buildURL | missing (optional) |
| `retrieve --metadata` | Metadata resources | PS3.18 Table 10.4.1-2 | study / series / instance /metadata | match |
| `retrieve --rendered` | Rendered resources | PS3.18 Table 10.4.1-3; 8.7.4-1 (image/jpeg default) | instance /rendered; saved as .jpg | match |
| `retrieve --thumbnail` | Thumbnail resources | PS3.18 Table 10.4.1-4 | study / series / instance /thumbnail | match |
| `retrieve -f, --format` | metadata media type | PS3.18 Table 8.7.3-3; Annex F (JSON); PS3.19 Native DICOM Model (XML) | json, xml; default json | match |
| `retrieve -o, --output` |  |  | directory | plumbing |
| `retrieve --token` | HTTP Authorization bearer token | PS3.18 8.4 (header fields; RFC 6750) |  | plumbing |
| `retrieve --timeout` | HTTP request timeout |  | seconds; default 60 | plumbing (was ignored; fixed 39da529) |
| `retrieve --verbose` |  |  |  | plumbing |
| `query <base-url>` | Studies Service base URI | PS3.18 Table 10.1-1 | http(s) URL | plumbing |
| `query --level` | Search resource level | PS3.18 Tables 10.6.1-1, 10.6.1-5 | study, series, instance; default study | match |
| `query --patient-name` | Patient's Name (0010,0010) | PS3.18 Table 10.6.1-5; 8.3.4.1 | PN, * ? wild card | match |
| `query --patient-id` | Patient ID (0010,0020) | PS3.18 Table 10.6.1-5 | LO | match |
| `query --study-date` | Study Date (0008,0020) | PS3.18 Table 10.6.1-5; PS3.4 C.2.2.2.5 | DA or DA-DA range | match |
| `query --study` | Study Instance UID (0020,000D); {study} of series/instance search | PS3.18 Tables 10.6.1-1, 10.6.1-5 | UID | match |
| `query --series` | Series Instance UID (0020,000E) | PS3.18 Table 10.6.1-5 | UID | match |
| `query --accession-number` | Accession Number (0008,0050) | PS3.18 Table 10.6.1-5 | SH | match |
| `query --modality` | Modalities In Study (0008,0061) at study/instance level; Modality (0008,0060) at series level | PS3.18 Table 10.6.1-5 | CS Defined Terms (shared ModalityOptionValidator) | match |
| `query --strict-modality` | reject non-Defined-Term Modality | PS3.3 C.7.3.1.1.1 |  | match |
| `query --study-description` | Study Description (0008,1030) | not in PS3.18 Table 10.6.1-5 (server-optional key) | LO | extra |
| `query --pps-start-date` | Performed Procedure Step Start Date (0040,0244), series | PS3.18 Table 10.6.1-5 | DA / range | match |
| `query --pps-start-time` | Performed Procedure Step Start Time (0040,0245), series | PS3.18 Table 10.6.1-5 | TM / range | match |
| `query --sps-id` | >Scheduled Procedure Step ID (0040,0275.0040,0009), series | PS3.18 Table 10.6.1-5 | SH | match |
| `query --requested-procedure-id` | >Requested Procedure ID (0040,0275.0040,1001), series | PS3.18 Table 10.6.1-5 | SH | match |
| `query --limit` | limit | PS3.18 Table 8.3.4-1; 8.3.4.4 | uint; no standard default (code 100) | wrong (negative accepted; fixed 39da529) |
| `query --offset` | offset | PS3.18 Table 8.3.4-1; 8.3.4.4 | uint; default 0 | wrong (negative accepted; fixed 39da529) |
| `query --fuzzy-matching` | fuzzymatching=true | PS3.18 Table 8.3.4-1; 8.3.4.2 | true/false | missing (added 39da529) |
| `(query: includefield, emptyvaluematching, multiplevaluematching)` | QIDO query parameters | PS3.18 Table 8.3.4-1; 8.3.4.3, 8.3.4.5, 8.3.4.6 | O for user agent | missing (optional; includefield useful only with P-QUERY-JSON) |
| `(query keys: Study Time, Referring Physician Name, Study ID, Series Number, SOP Class UID, SOP Instance UID, Instance Number)` | Required Matching Attributes the origin server supports | PS3.18 Table 10.6.1-5 | 7 of 20 rows not settable | missing (optional for the user agent) |
| `query -f, --format` | result rendering | PS3.18 Annex F (not followed) | table, json (keyword-keyed summary), csv | extra (P-QUERY-JSON) |
| `query --token` | HTTP Authorization bearer token | PS3.18 8.4 |  | plumbing |
| `query --verbose` |  |  |  | plumbing |
| `store <base-url>` | Studies Service base URI | PS3.18 Table 10.5.1-1 | http(s) URL | plumbing |
| `store <files>` | PS3.10 files sent as application/dicom parts | PS3.18 10.5.1; Table 8.7.3-2 | paths | plumbing |
| `store --study` | /studies/{study} target | PS3.18 Table 10.5.1-1 | UID | match |
| `store --input` |  |  | file list | plumbing |
| `store --batch` | instances per request |  | >= 1; default 10 | plumbing |
| `store --continue-on-error` |  | PS3.18 Table 10.5.3-1 (202/4xx = not all stored) |  | plumbing (exit 0 on failures; fixed 39da529: exit 1) |
| `store --token` | HTTP Authorization bearer token | PS3.18 8.4 |  | plumbing |
| `store --verbose` |  |  |  | plumbing |
| `ups <base-url>` | Worklist Service base URI | PS3.18 Table 11.1.1-1 | http(s) URL | plumbing |
| `ups --search` | Search Transaction GET /workitems | PS3.18 11.9; Table 11.3-1 |  | match |
| `ups --get` | Retrieve Workitem GET /workitems/{workitem} | PS3.18 11.5; Table 11.3-1 | UID | match |
| `ups --create` | Create Workitem POST /workitems from DICOM JSON | PS3.18 11.4; Table 11.3-1 | JSON file | match |
| `ups --create-workitem` | Create Workitem from options | PS3.18 11.4; PS3.4 Table CC.2.5-3 |  | match |
| `ups --update` | Change Workitem State PUT /workitems/{workitem}/state | PS3.18 11.7; Table 11.3-1 | UID (name suggests Update 11.6: P-WADO-UPS-UPDATE) | match |
| `ups --subscribe` | Subscribe POST .../subscribers/{subscriber} | PS3.18 11.10; Table 11.1.1-1 | workitem or Worklist (1.2.840.10008.5.1.4.34.5) | match |
| `ups --unsubscribe` | Unsubscribe DELETE .../subscribers/{subscriber} | PS3.18 11.11 |  | match |
| `ups --aet` | {subscriber} AE Title / requester | PS3.18 11.10.1, Table 11.7.2.1-1; PS3.5 VR AE | AE; sent as path segment (dcm4chee), not ?requester= | match |
| `ups --state` | Procedure Step State (0074,1000) of Change State | PS3.18 11.7.1.4; PS3.3 Table C.30.1-1 | IN PROGRESS, COMPLETED, CANCELED | wrong ("IN PROGRESS" rejected; fixed 39da529; SCHEDULED warns, P-WADO-UPS-STATE) |
| `ups --transaction-uid` | Transaction UID (0008,1195) | PS3.18 11.7.1.4 | UI; generated for IN PROGRESS, required for COMPLETED/CANCELED | match |
| `ups --filter-state` | Procedure Step State (0074,1000) matching key | PS3.3 Table C.30.1-1 | SCHEDULED, IN PROGRESS, COMPLETED, CANCELED | wrong ("IN PROGRESS" rejected; fixed 39da529) |
| `ups --scheduled-station` | Scheduled Station Name Code Sequence (0040,4025) key | PS3.4 Table CC.2.5-3 |  | match |
| `ups --workitem-uid` | Workitem SOP Instance UID {workitem} | PS3.18 Table 11.1.1-1 | UID; generated under 1.2.826.0.1.3680043.8.498 | match |
| `ups --label` | Procedure Step Label (0074,1204) | PS3.3 Table C.30.2-1 | LO; required for --create-workitem | match |
| `ups --patient-name` | Patient's Name (0010,0010) | PS3.4 Table CC.2.5-3 | PN | match |
| `ups --patient-id` | Patient ID (0010,0020) | PS3.4 Table CC.2.5-3 | LO | match |
| `ups --priority` | Scheduled Procedure Step Priority (0074,1200) | PS3.3 Table C.30.2-1 | HIGH, MEDIUM, LOW; STAT -> HIGH; default MEDIUM | match (help named STAT as a value; fixed 39da529) |
| `ups --patient-birth-date` | Patient's Birth Date (0010,0030) | PS3.5 VR DA | YYYYMMDD | match |
| `ups --patient-sex` | Patient's Sex (0010,0040) | PS3.3 Table C.7-1 | M, F, O | match |
| `ups --study-uid` | Study Instance UID (0020,000D) | PS3.4 Table CC.2.5-3 | UID | match |
| `ups --accession-number` | Accession Number (0008,0050) | PS3.4 Table CC.2.5-3 | SH | match |
| `ups --referring-physician` | Referring Physician's Name (0008,0090) | PS3.6 Table 6-1 | PN | match |
| `ups --procedure-id` | Requested Procedure ID (0040,1001) | PS3.6 Table 6-1 | SH | match |
| `ups --step-id` | Scheduled Procedure Step ID (0040,0009) | PS3.6 Table 6-1 | SH | match |
| `ups --worklist-label` | Worklist Label (0074,1202) | PS3.3 Table C.30.2-1 | LO | match |
| `ups --comments` | Comments on the Scheduled Procedure Step (0040,0400) | PS3.6 Table 6-1 | LT | match |
| `ups --scheduled-start` | Scheduled Procedure Step Start DateTime (0040,4005) | PS3.5 VR DT | ISO 8601 input -> DT | match |
| `ups --expected-completion` | Expected Completion DateTime (0040,4011) | PS3.5 VR DT | ISO 8601 input -> DT | match |
| `ups --station-name` | Scheduled Station Name Code Sequence (0040,4025) item | PS3.3 8.2 (designator "L" = local) | code value = meaning = name, scheme L | match |
| `ups --performer-name` | Human Performer's Name (0040,4037) in (0040,4034) | PS3.6 Table 6-1 | PN | match |
| `ups --performer-organization` | Human Performer's Organization (0040,4036) | PS3.6 Table 6-1 | LO | match |
| `ups --admission-id` | Admission ID (0038,0010) | PS3.6 Table 6-1 | LO | match |
| `(ups: Update Workitem, Request Cancellation)` | UPS-RS transactions | PS3.18 11.6, 11.8; Table 11.3-1 | DICOMwebClient has both | missing (optional) |
| `ups -f, --format` | result rendering | PS3.18 Annex F (not followed) | table, json (camelCase summary), csv; help omitted csv (fixed) | extra (P-QUERY-JSON) |
| `ups --token` | HTTP Authorization bearer token | PS3.18 8.4 |  | plumbing |
| `ups --verbose` |  |  |  | plumbing |

**Output contract**

| Field | DICOM source | Encoding (standard) | Encoding (code) | Verdict |
|---|---|---|---|---|
| `query --format json` keys | QIDO-RS result attributes | PS3.18 F.2 (tag keys, vr, Value) | keyword → string summary (27 keys, all PS3.6 keywords; QIDOResultFormatter) | tool summary — P-QUERY-JSON (extend to dicom-wado) |
| `ups --format json` keys | UPS workitem attributes | PS3.18 F.2 | camelCase keys (`state`, `priority`, `procedureStepLabel`, … 18 not keywords; UPSResultFormatter) | tool summary — P-QUERY-JSON |
| `retrieve --metadata --format json` | metadata resource | PS3.18 F.2 | server JSON as received | match |
| `retrieve --metadata --format xml` | metadata resource | PS3.19 Native DICOM Model | shared DICOMXMLEncoder | match |
| table labels (query) | Study/Series/Instance columns | PS3.6 names | "Modality" column shows Modalities In Study; "# Images" = Number of Series Related Instances; "SOP Class" truncates the UID to 15 chars | shared formatter (D105) |
| UPS state text | Procedure Step State (0074,1000) | "IN PROGRESS" | UPSState.rawValue "IN PROGRESS" | match |
| STOW failure line | Failure Reason (0008,1197) | PS3.18 Table I.2-2 (hex + decimal + meaning) | "Code 42752" (decimal only, no meaning) | shared formatter (D106) |
| STOW warnings | Warning Reason (0008,1196), Table I.2-1 | — | not printed | missing (D106) |
| HTTP status text | PS3.18 Table 8.5-1 | "404 (Not Found)" … | DICOMwebError: "Not Found: …", others "HTTP Error <code>" | match |
| exit codes | — | — | 0 ok; 1 runtime/HTTP error or any file not stored (store, now also with --continue-on-error); 64 validation | match (README said 2; fixed) |

**Fixed (39da529, 15 tests in new target `dicom-wadoTests`)**: --content-type unknown values rejected (were fetched as application/dicom);
--uri --frames positive single frame (0/text sent or dropped), extra list entries warn; new --transfer-syntax/--anonymize/--rows/--columns;
parameter-outside-its-table warnings; --timeout wired (was ignored); query --fuzzy-matching, --limit/--offset ≥ 0; ups "IN PROGRESS" accepted for
--state/--filter-state, --state SCHEDULED warns; help texts (priority HIGH/MEDIUM/LOW, M/F/O, csv); comment citations §11.6→11.7 (Change State, `requester` Table 11.7.2.1-1), §11.5→11.6 (Update);
store exits 1 on any unstored file. README: exit 64, real error text, jq example used tag keys on keyword JSON, WADO-URI/fuzzy/state sections.

**P-items**
- **P-WADO-UPS-STATE**: `ups --state SCHEDULED` is accepted and sent; PS3.18 11.7.1.4 allows only IN PROGRESS, COMPLETED, CANCELED and PS3.4 Table CC.1.1-2 refuses it (C303H/C307H). Proposal: reject SCHEDULED (currently warns).
- **P-WADO-UPS-UPDATE**: `ups --update <uid>` performs Change Workitem State (11.7), not Update Workitem (11.6). Proposal: additive alias `--change-state`, keep `--update`; optionally add Update (11.6) and `--cancel-request` (11.8).
- **P-QUERY-JSON** (existing): extend to `dicom-wado query/ups --format json` (shared QIDOResultFormatter / UPSResultFormatter).

**Deferred findings**
- D107 — DICOMWeb `UPSQuery.workitemSearch` (Sources/DICOMWeb/UPS/UPSQuery.swift:611): rejects the standard term "IN PROGRESS" (accepts only IN_PROGRESS/INPROGRESS); PS3.3 Table C.30.1-1. Low. (Tool normalises before calling.)
- D105 — DICOMWeb `QIDOResultFormatter` (QIDOResultFormatter.swift:34, :95, :148): study column "Modality" holds Modalities In Study (0008,0061); "# Images" is Number of Series Related Instances (0020,1209); "SOP Class" truncates the UID to 15 chars. PS3.6 Table 6-1 names. Low.
- D106 — DICOMWeb `STOWResultFormatter.failureReason` (STOWResultFormatter.swift:52): prints "Code <decimal>" without the PS3.18 Table I.2-2 meaning/hex; Warning Reason (Table I.2-1) never printed. Low.
- D108 — DICOMWeb `WADOURIClient`: 9 optional WADO-URI parameters (charset, annotation, imageAnnotation, imageQuality, region, windowCenter, windowWidth, presentationUID, presentationSeriesUID) and 8 Rendered Media Types (image/jxl, video/mp4, video/H265, text/*, application/pdf) not requestable; PS3.18 Tables 9.4.1-1, 9.5.1-1, 8.7.4-1. Low (optional).

**Markers**: DICOMWado.swift "options diffed against PS3.18 2026a Tables 9.1.2-1/9.1.2-2/9.4.1-1/9.5.1-1 (WADO-URI: 10 of 19 parameters reachable, the other 9 optional and absent from WADOURIClient), 9.1.2.2.1/8.7.4-1 (7 contentType values, all match), 8.3.4-1 (QIDO: 4 of 7 parameters), 10.6.1-5 (3 levels; 12 of 20 matching keys), 11.3-1 (UPS: 6 of 8 transactions), 11.7.1.4 (3 Change State targets); PS3.3 2026a Tables C.30.1-1 (4 states), C.30.2-1 (3 priorities), C.7-1 (3 sexes): all match; Scripts/diff_cli_web.py"; WADOOptionRules.swift "WADO-URI rules read against PS3.18 2026a 9.1.2.2.1, 9.4.1.2.1, 9.4.1.2.3, 9.5.1.2.1, 9.5.1.2.4 and Tables 9.4.1-1 / 9.5.1-1 / 8.7.4-1 (7 contentType values); limit/offset against 8.3.4.4; UPS states against PS3.3 2026a Table C.30.1-1 (4 Enumerated Values) and PS3.18 11.7.1.4 (3 Change State targets)". check_nema_markers: 2/2.

**For Scripts/diff_cli.py (orchestrator)**: optionally call `Scripts/diff_cli_web.py` checks for dicom-wado / dicom-jpip (standalone today).

### dicom-jpip (G1, PS3.6 Table A-1, PS3.5 8.4.1 / A.6 / A.7 / A.11 / A.12)

Files: main.swift (B2), JPIPSyntaxes.swift (new, A). Commit `827f021`. JPIP itself (ISO/IEC 15444-9: layers, levels, regions, sessions) is out of scope;
DICOM governs only the Transfer Syntax UIDs and Pixel Data Provider URL (0028,7FE0) (UR, PS3.6 Table 6-1). `fetch` still exits 1 (F1, unimplemented upstream).
PS3.6 Table A-1 dumped by script: 4 JPIP rows (.4.94 JPIP Referenced, .4.95 JPIP Referenced Deflate, .4.204 JPIP HTJ2K Referenced, .4.205 JPIP HTJ2K Referenced Deflate).
Before: --list-syntaxes and help listed 2 of 4 (diff_cli_web: matched 2, missing 2); after: 4/4 both. diff_cli generic: A-1 UIDs 4/4, names next to UIDs 4/4, citations 4/4.

**Counts: matched 0, wrong 2, missing 0, extra 0, plumbing 15** (17 rows; both wrong rows fixed).

**Input contract**

| Option | DICOM concept | 2026a reference | Allowed / code accepts | Verdict |
|---|---|---|---|---|
| `fetch <server-url>` | JPIP server (ISO/IEC 15444-9) | PS3.5 8.4.1 (HTTP/HTTPS transport) | http(s) URL | plumbing |
| `fetch --image` | JPIP target | ISO/IEC 15444-9 (out of scope) |  | plumbing |
| `fetch --layers` | JPIP quality layers | ISO/IEC 15444-9 (out of scope) |  | plumbing |
| `fetch --level` | JPIP resolution level | ISO/IEC 15444-9 (out of scope) |  | plumbing |
| `fetch --region` | JPIP region | ISO/IEC 15444-9 (out of scope) | x,y,w,h | plumbing |
| `fetch -o, --output` |  |  |  | plumbing |
| `fetch -v, --verbose` |  |  |  | plumbing |
| `uri <input>` | PS3.10 file with a JPIP Referenced Transfer Syntax; prints Pixel Data Provider URL (0028,7FE0) | PS3.6 Table A-1 (4 JPIP UIDs); PS3.5 8.4.1, A.6, A.7, A.11, A.12 | .4.94, .4.95, .4.204, .4.205 | wrong (.4.204/.4.205 refused; fixed 827f021) |
| `uri --json` | summary JSON (file, transferSyntaxUID, isDeflated, jpipURI) |  | tool keys | plumbing |
| `serve -p, --port` | JPIP server port | ISO/IEC 15444-9; no DICOM default | default 8080 | plumbing |
| `serve -d, --directory` |  |  | *.dcm files | plumbing |
| `serve --max-clients` |  |  | default 16 | plumbing |
| `serve --client-bandwidth` |  |  | bytes/s; 0 = unlimited | plumbing |
| `serve -v, --verbose` |  |  |  | plumbing |
| `info <target>` | file or JPIP server URL | PS3.5 8.4.1 |  | plumbing |
| `info --list-syntaxes` | JPIP Referenced Transfer Syntaxes | PS3.6 Table A-1 | 4 UIDs with A-1 names | wrong (2 of 4 listed, "Pixel Data contains a JPIP URI", A.8 cited; fixed 827f021) |
| `info --json` | summary JSON (file, transferSyntaxUID, isJPIP, jpipURI) |  | tool keys | plumbing |

**Output contract**

| Field | DICOM source | Encoding (standard) | Encoding (code) | Verdict |
|---|---|---|---|---|
| `--list-syntaxes` uid/name | PS3.6 Table A-1 | 4 JPIP rows | 4 rows, A-1 names | wrong → fixed (2 of 4) |
| `--list-syntaxes` description | PS3.5 A.6 / A.11 | Pixel Data absent; URL in (0028,7FE0) | was "Pixel Data contains a JPIP server URI" | wrong → fixed |
| label "Pixel Data Provider URL" (uri, info) | (0028,7FE0) | PS3.6 name | was "JPIP URI" | fixed |
| label "Transfer Syntax" | (0002,0010) | UID + A-1 name | UID (+ "(deflated)") → UID (A-1 name) | fixed |
| info banner citation | PS3.5 | 8.4.1, A.6, A.7, A.11, A.12 | was "Annex A.8" (SMPTE ST 2110-20) | wrong → fixed |
| JSON `jpipURI`, `transferSyntaxUID`, `isDeflated`, `isJPIP`, `file` | tool summary | — | unchanged | plumbing (key `jpipURI` names (0028,7FE0); rename would be a P-item, not proposed) |
| exit codes | — | — | 0; 1 (non-JPIP file, fetch, errors); 64 validation | match |

**Fixed (827f021, 6 tests in new target `dicom-jpipTests`)**: HTJ2K JPIP pair listed and recognised by uri/info (reads (0028,7FE0) itself because the engine guard rejects them); descriptions/labels/citations.

**P-items**: none.

**Deferred findings**
- D109 — DICOMCore `TransferSyntax.isJPIP` (Sources/DICOMCore/TransferSyntax.swift:1087) returns false for 1.2.840.10008.1.2.4.204 / .205 (JPIP HTJ2K Referenced [Deflate], PS3.5 A.11 / A.12, PS3.6 Table A-1), so `DICOMJPIPClient.jpipURI` (DICOMKit/DICOMJPIPClient.swift:335) throws notAJPIPTransferSyntax for them; the .204 doc comment (TransferSyntax.swift:581) says "the Pixel Data is a URI reference" (A.11: Pixel Data absent, (0028,7FE0)). Medium.

**Markers**: main.swift "transfer syntax lists diffed against PS3.6 2026a Table A-1 (4 JPIP rows, 4 / 4 match, via JPIPSyntaxes); Pixel Data Provider URL (0028,7FE0) and section citations against PS3.5 2026a 8.4.1, 10.8, A.6, A.7, A.11, A.12; fetch/serve parameters (layers, level, region, port) belong to ISO/IEC 15444-9 JPIP and are out of scope (plumbing)"; JPIPSyntaxes.swift "the 4 JPIP Referenced Transfer Syntax UIDs and names diffed against PS3.6 2026a Table A-1 (4 / 4 match); Pixel Data Provider URL (0028,7FE0) per PS3.5 2026a 8.4.1, A.6, A.7, A.11, A.12 and PS3.6 Table 6-1 (UR); JPIP itself (ISO/IEC 15444-9) is out of scope". check_nema_markers: 2/2.

### dicom-cloud (G1, bucket C1)

Files: DICOMCloud.swift, CloudTypes.swift, CloudOperations.swift, CloudProvider.swift (all C1). Commit `b7a11a4` (docs + markers).
The target is commented out of Package.swift ("Phase 1 scope: exclude dicom-cloud …"), so it is not built and has no tests; only comments, help prose and README changed.
diff_cli generic: 0 UID / tag / code / citation literals (all checks ok, matched 0). DICOM concepts vs cloud plumbing:
no DICOMweb endpoint, no transfer syntax, no de-identification and no SOP Class / modality filter exist in the code — files are moved as opaque bytes
(GCS upload sends Content-Type application/octet-stream, not application/dicom). Baseline: "--bidirectional (default: upload only)" is prose (plumbing).

**Counts: matched 0, wrong 0, missing 0, extra 0, plumbing 19**

**Input contract**

| Option | DICOM concept | 2026a reference | Allowed / code accepts | Verdict |
|---|---|---|---|---|
| `<source>` | local path or cloud URL |  | s3:// gs:// azure:// | plumbing |
| `<destination>` | cloud URL or local path |  |  | plumbing |
| `<cloud-url>` | cloud URL |  |  | plumbing |
| `<local-path>` | local directory |  |  | plumbing |
| `-r, --recursive` |  |  |  | plumbing |
| `--tags` | object metadata key=value | none (keys are free text; e.g. PatientID is a PS3.6 keyword but not written as a DICOM attribute) |  | plumbing |
| `--encrypt` | storage encryption | none (not PS3.15) | none, server-side, client-side | plumbing |
| `--multipart` |  |  |  | plumbing |
| `--parallel` |  |  | default 4 | plumbing |
| `--resume` |  |  |  | plumbing |
| `--endpoint` | S3-compatible endpoint |  |  | plumbing |
| `--region` | cloud region |  |  | plumbing |
| `--details` |  |  |  | plumbing |
| `--force` |  |  |  | plumbing |
| `--bidirectional` | sync direction |  | default upload only (help prose fixed b7a11a4) | plumbing |
| `--delete` |  |  |  | plumbing |
| `--source-region` |  |  |  | plumbing |
| `--dest-region` |  |  |  | plumbing |
| `-v, --verbose` |  |  |  | plumbing |

**Output contract**

| Field | DICOM source | Encoding (standard) | Encoding (code) | Verdict |
|---|---|---|---|---|
| list lines (key, size, ISO 8601 date) | — | — | tab-separated | plumbing |
| verbose / error text (CloudError) | — | — | free text | plumbing |
| exit codes | — | — | 0; 1 on error; 64 validation | plumbing |

**Fixed (b7a11a4)**: README ran `dicom-anon --profile archive` (no such profile; dicom-anon takes basic, clinical-trial, research, ps315) → `--profile ps315`, labelled with the PS3.15 Annex E title "Basic Application Level Confidentiality Profile" (E.2, dumped by script); --tags example notes metadata keys (PatientID, StudyDate, Modality — PS3.6 keywords, 3/3) are not de-identified; `sync` help no longer calls the default bidirectional.

**P-items**: none. **Deferred**: none (note: storing DICOM objects with Content-Type application/dicom would be more accurate, not a standard requirement for object stores).

**Markers** (all four): "carries no DICOM-standard data (<file role>); Scripts/diff_cli.py: 0 UID, tag or code literals". check_nema_markers: 4/4.


### dicom-server repair (D94–D102)

Commit: `7bad09d` fix(cli): dicom-server builds again; PS3.10 files, A801, C-GET sub-operation status, A900 for missing level, C.2.2.2 matching, PS3.8 D.1 lengths, VR AE checks (D94-D102)

It is a single commit because the ServerSession rewrite is shared by every row. D98 and D100 depend on the new DatabaseManager API, which ServerSession calls, so no smaller commit would build on its own.

Files: Package.swift (only my 4 hunks: product, executableTarget, `dicom-serverTests` target, and `DICOMServerTests.swift` removed from the DICOMViewerTests exclude list), Sources/dicom-server/{DICOMServer, ServerSession, StorageManager, DatabaseManager, ServerConfiguration}.swift, new ServerProtocol.swift (pure protocol rules, unit-testable), README.md, CHANGELOG.md. The tests in Tests/dicom-serverTests/ are DICOMServerTests.swift (moved from Tests/DICOMToolsTests and adapted) and the new DICOMServerStandardTests.swift.

The uncommitted DICOMStudio edits in the working tree are not mine. They are the staged deletion of Sources/DICOMStudio/App/DICOMStudioApp.swift, ViewerCommands.swift, Sources/DICOMStudioApp/DICOMStudioApp.swift, ARCHITECTURE.md and the DICOMStudio `exclude:` hunk in Package.swift. I left them alone. I committed through a temporary index, so neither that hunk nor the staged deletion is in 7bad09d.

#### Evidence (dumped by script from the 2026a DocBook)
- PS3.4 Tables C.6-1..C.6-5, Required/Unique rows (`nema_docbook.py table part04 C.6-x | awk $3~/^[RU]$/`). There are 12 distinct keys: C.6-1 Patient's Name R, Patient ID U; C.6-2 Study Date, Study Time, Accession Number, Study ID R, Study Instance UID U; C.6-3 Modality, Series Number R, Series Instance UID U; C.6-4 Instance Number R, SOP Instance UID U; C.6-5 adds Patient's Name and Patient ID as R at the Study Root study level.
- PS3.4 C.2.2.2.1 to .5 (sect.py): single value matching, list of UID, universal, wild card (AE, CS, LO, LT, PN, SH, ST, UC, UR, UT; case sensitive except PN), and DA/TM/DT ranges. C.4.1.1.3.1 and .2 cover the request and response identifier (requested keys, Q/R Level, Retrieve AE Title). C.4.2.3.1 and C.4.3.3.1 cover baseline C-MOVE/C-GET SCP behaviour and final statuses.
- PS3.4 Tables C.4-1, C.4-2, C.4-3 and B.2-1 (status codes, names and related fields). PS3.10 Table 7.1-1 (16 rows). PS3.8 D.1 (Maximum Length).

#### D-rows
| ID | Status | What changed | Test |
|---|---|---|---|
| D99 | ✅ closed | Product and target re-enabled. The Package.swift exclude list for the target now covers DATABASE_SCHEMA.md and DEPLOYMENT_GUIDE.md too. The old top-level `main` beside `@main` is removed. `EchoService`/`DICOMClient(callingAETitle:)` are replaced by `DICOMVerificationService.echo`, `DataSet.read(from:)` by a transfer-syntax-aware decode, and `PresentationContextAccept` by `AcceptedPresentationContext`. Async enumerator loops are fixed. No DICOMNetwork/DICOMKit API change. `swift build --product dicom-server` passes with 0 warnings in the target. | the whole `dicom-serverTests` target (72) |
| D102 | ✅ closed | `StorageManager.storeReceived` writes the preamble, "DICM" and File Meta Information (`DICOMFile.create` + `write`: (0002,0000), 0001, 0002 = Affected SOP Class UID, 0003, 0010 = context Transfer Syntax UID, 0012/0013 = DICOMKit's, plus Type 3 0016 Source AE = server, 0017 Sending AE = calling AE, 0018 Receiving AE = server), then the data set bytes unchanged. The data set is decoded with the negotiated transfer syntax. UIDs used as path components are sanitised. | test_D102_* (4) and loopback |
| D96 | ✅ closed | `ServerConfiguration.moveDestination(for:)` returns nil for an unknown AE. C-MOVE then answers A801 "Refused: Move Destination unknown" with an Error Comment. New additive option `start --move-destination AE=host:port` (repeatable). The old "host:port:AE" value form is kept. | test_D96_*, loopback (A801, and a real C-MOVE to a second server) |
| D97 | ✅ closed | C-GET sends each C-STORE-RQ and reads PDUs until its C-STORE-RSP arrives. Completed/Warning/Failed are counted from the status (B.2-1). C-CANCEL-RQ gives FE00 with counts. SCP/SCU Role Selection is answered in the AC and a context is used only if the SCU got the SCP role. All PS3.4 Table B.5-1 storage classes are accepted (`StorageSOPClass.allUIDSet`). Uncompressed syntaxes are converted to the context's syntax. Final C-MOVE/C-GET status follows C.4.2.3.1/C.4.3.3.1 (0000, B000, A702 when all fail, FE00), and failures add a Failed SOP Instance UID List (0008,0058) identifier. | test_D97_* (3), loopback C-GET |
| D101 | ✅ closed | A missing, empty or unknown Q/R Level, or PATIENT on Study Root (C.6.2-1), gets A900 "Error: Data Set does not match SOP Class" with Offending Element (0008,0052) and an Error Comment. This applies to C-FIND, C-MOVE and C-GET. | test_D101_* (2) |
| D98 | ✅ closed | `QueryMatcher` has wildcards only for the 10 C.2.2.2.4 VRs, case sensitive except PN. UI uses List of UID Matching. DA/TM use Range Matching, inclusive, with open ends. TM single values are compared by meaning; IS/DS numerically. | test_D98_* (2) |
| D100 | ✅ closed | All 12 R/U keys (plus 6 optional: Patient's Birth Date, Patient's Sex, Study Description, Modalities in Study, Series Description, SOP Class UID) are matched and returned. A response carries only the requested supported keys (zero length when the server has no value), plus Q/R Level and Retrieve AE Title (C.4.1.1.3.2). FF01 is sent when the request has optional keys the server does not support. | test_D100_* (4), loopback C-FIND |
| D95 | ✅ closed | Outgoing P-DATA is fragmented to the peer's Maximum Length (0 → own value). The AC carries `--max-pdu-size`. An incoming P-DATA-TF over that value is aborted (A-ABORT, provider, reason 6). The AC echoes the RQ AE fields (PS3.8 9.3.3). | test_D95_* (2), DCMTK interop |
| D94 | ✅ closed | `--aet`, `--allowed-ae`, `--blocked-ae`, `--move-destination` and the same fields in a `--config` file are validated as VR AE through DICOMNetwork.AETitle (1–16 chars, G0 without backslash). The Implementation Class UID and Version Name are `DICOMFile.implementationClassUID` (1.2.826.0.1.3680043.10.511.3.0.5.0) and `DICOMFile.implementationVersionName`. | test_D94_* (2) |

Behaviour changes outside the rows:
- Failure statuses now come from the tables. C-STORE: A700 when the file cannot be written, C000 when the data set cannot be decoded (B.2-1). C-FIND/MOVE/GET: C000 "Failed: Unable to process". The former 0110 is no longer sent.
- Unrecognized DIMSE requests get 0211.
- Re-sending a SOP Instance replaces its index entry instead of duplicating it.

#### Tests run
- `swift build --product dicom-server`: ok.
- `swift test --filter dicom_serverTests`: 72 tests, 0 failures (51 in DICOMServerTests, 21 in DICOMServerStandardTests). This includes `test_loopback_echoStoreFindGetMove`, which runs two in-process PACSServer instances on random ports and drives DICOMNetwork's SCUs: C-ECHO, a C-STORE in Implicit VR LE, C-FIND, a C-GET with role selection, a C-MOVE to an unknown AE (A801) and a C-MOVE to the second server. It takes about 0.15 s and passed 3 out of 3 repeat runs.
- One stale test was adapted (`test_DatabaseManager_IndexAndQuery`): it now requests Study Instance UID, because responses carry only requested keys (C.4.1.1.3.2). Two stale `storeFile` tests were changed to use `storeReceived`.
- Manual interop with DCMTK 3.6.x (echoscu, storescu -xi, storescu --max-pdu 4096 with a 12.5 KB file, findscu, getscu --max-pdu 4096, movescu):
  - all associations succeeded;
  - dcmdump shows the Table 7.1-1 meta;
  - findscu without a level returned "Error: DataSetDoesNotMatchSOPClass";
  - getscu reported 2 completed and 0 failed, and the pixel data was identical;
  - movescu to an unknown AE got "Refused: MoveDestinationUnknown";
  - echoscu -d showed "Their Max PDU Receive Size: 8192", the server's own value;
  - getscu -d showed the SCP role negotiated.
- `diff_cli.py --tool dicom-server`: 0 FAIL (A-1 literals 10/10, names 10/10, citations 23/23). `check_nema_markers.py Sources/dicom-server`: 10/10 files.

#### Limitations left open (not part of D94–D102)
- C-MOVE does not read C-CANCEL-RQ while its sub-operations run (the session has no concurrent reader). C-FIND sends all matches at once, so cancel has nothing to stop.
- C-MOVE sub-operations do not carry Move Originator AE Title/Message ID (0000,1030/1031). `DICOMStorageService.store` has no parameter for them (see D156).
- Storage accepts only the 3 uncompressed transfer syntaxes, as before.
- The index is in memory and is not rebuilt from the data directory on restart, as before.
- Specific Character Set is not tracked for C-FIND responses.

#### Deferred findings (engine; not fixed here)
| ID | File:line | Problem | Ref | Severity |
|---|---|---|---|---|
| D155 | Sources/DICOMNetwork/StorageSCP.swift:47 `StorageSCPConfiguration.defaultImplementationClassUID`; StorageService.swift (`StorageConfiguration.defaultImplementationClassUID` "1.2.826.0.1.3680043.9.7433.1.1") | DICOMNetwork's SCP/SCU default Implementation Class UIDs are under 1.2.826.0.1.3680043.9.7433, not DICOMKit's root 1.2.826.0.1.3680043.10.511 (the root DICOMFile.implementationClassUID uses). dicom-server now overrides them. | PS3.7 D.3.3.2; PS3.5 9.2.2 | Low |
| D156 | Sources/DICOMNetwork/StorageService.swift `DICOMStorageService.store(...)` | There is no way to set Move Originator AE Title / Message ID on the C-STORE-RQ, so a C-MOVE SCP built on it cannot identify the originating C-MOVE in its sub-operations. | PS3.7 9.1.1.1.6 / 9.1.1.1.7 | Low |

P-items: none. The one option added, `start --move-destination`, is additive. No DICOMKit/DICOMNetwork public API was changed. Parsing a bare data set in a given transfer syntax has no public DICOMKit entry point; the server wraps the bytes in a Part 10 header and uses `DICOMFile.read`, so no API change was needed.

Contract: one new row, `start --move-destination` (PS3.4 C.4.2.1.3 / Table C.4-2, match, additive). `start --aet`, `--allowed-ae`, `--blocked-ae` and `--max-pdu-size` are now "match". Written to `<scratch>/contracts/dicom-server.py` (25 rows). Counts: matched 6, wrong 0, missing 0, extra 0, plumbing 19.

Marker (ServerProtocol.swift, new): `// NEMA-verified: 2026a, checked 2026-10-01 — Maximum Length rules from PS3.8 2026a D.1 (...); SCP/SCU Role Selection reply per PS3.7 D.3.3.4; AE Title rules of PS3.5 Table 6.2-1 (...); Query/Retrieve Level values of PS3.4 Tables C.6.1-1 (4) / C.6.2-1 (3) and the A900 failure of Table C.4-1..C.4-3 when the level is missing; final C-MOVE / C-GET status per C.4.2.3.1 / C.4.3.3.1 and Tables C.4-2 / C.4-3 (0000, B000, A702, FE00); the 3 accepted transfer syntaxes are PS3.6 2026a Table A-1 names`. These markers were updated: ServerSession.swift, DatabaseManager.swift ("all 12 Required/Unique keys of C.6-1..C.6-5 ... matched and returned"), StorageManager.swift (Table 7.1-1, D102 closed), ServerConfiguration.swift (VR AE, A801) and DICOMServer.swift (25 options, D99/D94).

Report-file updates for the orchestrator:
- Rows D94–D102 → ✅ Closed (7bad09d).
- Row 35 "open: dicom-server repair" → done.
- Line 53: "dicom-server not buildable" → `dicom-serverTests` 72 pass.
- Input contract rows for --aet, --max-pdu-size, --allowed-ae and --blocked-ae → match; add `--move-destination`.
- Output contract: the C-MOVE row now includes A801 (match), the C-GET row now has counts from C-STORE-RSP (match), and the C-FIND keys/matching row → match (12/12 R/U keys).

## G2 File and media

### dicom-json (G2, PS3.18 2026a Annex F)

Files: main.swift (B2). The tool carries no encoder: the whole pipeline is the shared `DataExchangeWorkflow` (DICOMWeb), which drives
`DICOMJSONEncoder` / `DICOMJSONDecoder` / `DICOMJSONWriter`. Commit `78214e8`.

**Evidence (by script, 2026a DocBook)**
- `Scripts/diff_web.py` checks re-run over the engines (`<scratch>/jx_diffweb.py`): Table F.2.3-1 VR → JSON type, encoder 34/34 and decoder 34/34; F.2.2-F.2.7 object layout 6/6; 0 fails. The tool sources contain no VR or layout code (they call only `DataExchangeWorkflow`), so the checks have nothing to match there.
- F.2.2, F.2.5, F.2.6, F.2.7, 10.4.1.1.2, 10.4.3.3.2 dumped by `<scratch>/jx_sect.py`. Key sentences: F.2.2 "Attribute objects ... shall be ordered by their property name in ascending lexicographic (alphabetic) order"; F.2.5 "If an attribute is present in DICOM but empty (i.e., Value Length is 0), it shall be preserved in the DICOM JSON attribute object containing no "Value", "BulkDataURI" or "InlineBinary""; 10.4.1.1.2 Metadata "includes only the DICOM Data Set (without Bulk Data), and in particular does not include any Group 0002"; 10.4.3.3.2 the payload "shall ... contain all Attributes", and the origin server may replace the Value Field of DS, FL, FD, IS, LT, OB, OD, OF, OL, OV, OW, SL, SS, ST, SV, UC, UL, UN, US, UT and UV with a Bulk Data URI.
- Real conversions (the fixture `Tests/DICOMStudioTests/Fixtures/syn-ct.dcm` plus a pydicom-built file with an empty SH/PN/SQ, a multi-valued CS and PN with an empty value, a 3-group PN, a sequence with an empty item, a private block (0009,0010)/(0009,1001 LO)/(0009,1002 UN), FD, AT, 2048-byte OB and OW) validated by `<scratch>/jx_validate.py`. It checks Table F.2.3-1 types per VR (extracted), 8-hex uppercase names, ascending order at every level, Group Length absent, at most one of Value/BulkDataURI/InlineBinary, InlineBinary only on binary VRs, PN members, null for empty values, AT form, and F.2.5 empties. Before the fix: default output 3 violations (3 empty attributes dropped); after: 32 attribute objects, 0 violations. `--no-sort-keys`: 2 order violations (top level and item level), as expected. Cross-check: JSON → DICOM → pydicom compares equal on every element (29/29) when the JSON came from the default (now include-empty) conversion.

**Counts: matched 2, wrong 1, missing 1, extra 2, plumbing 5** (11 rows; wrong and missing fixed).

**Input contract**

| Option | DICOM concept | 2026a reference | Allowed per standard | Code accepts | Default (std) | Default (code) | Verdict |
|---|---|---|---|---|---|---|---|
| `<input>` | PS3.10 file (forward) / DICOM JSON document (reverse) | PS3.10 7.1; PS3.18 F.2 | — | path | — | — | plumbing |
| `-o, --output` | output path | — | — | path; default `<input>.json` / `.dcm` | — | — | plumbing |
| `-r, --reverse` | JSON → PS3.10; TS from (0002,0010) else 1.2.840.10008.1.2.1 | PS3.18 F.2; PS3.6 Table A-1 | — | flag | — | false | plumbing |
| `-p, --pretty` | whitespace | RFC 8259 (F.2) | — | flag | — | false | plumbing |
| `--no-sort-keys` | attribute-object order | PS3.18 F.2.2 | ascending lexicographic order only | flag → unordered (also inside items) | ordered | ordered | extra (non-conformant; help now says so; P-JSON-NO-SORT-KEYS) |
| `--include-empty` | empty attribute = `{"vr"}` only | PS3.18 F.2.5 "shall be preserved" | always kept | `--include-empty` / `--no-include-empty` (added) | kept | was dropped → kept | wrong → fixed |
| `--inline-threshold` | InlineBinary vs BulkDataURI (OB/OD/OF/OL/OV/OW/UN) | PS3.18 F.2.2, F.2.6, F.2.7 | either form; at most one | bytes; acts only with `--bulk-data-url` (0 = every value to URI); without it all InlineBinary | — | 1024 | match (help said "0 to always use URIs" without the URL condition; corrected) |
| `--bulk-data-url` | BulkDataURI | PS3.18 F.2.6 → PS3.19 Table A.1.5-2 | URI of the Bulk Data | `<url>/<GGGGEEEE>` | — | none | match (help corrected; D110 for nested items) |
| `--metadata-only` | drop Pixel Data | PS3.18 10.4.1.1.2 / 10.4.3.3.2 Metadata resource | all attributes; bulk data replaced by BulkDataURI | removes (7FE0,0010) only; other bulk data stays inline | — | false | extra (tool convention, not the Metadata resource; help corrected; D111) |
| `--filter-tag` | attribute selection | PS3.6 Table 6-1 keyword; PS3.18 F.2.2 name | — | keyword, `GGGG,EEEE`; added `GGGGEEEE` (the F.2.2 attribute name), `(GGGG,EEEE)` | — | none | missing → fixed (help said "by name or group"; group was never accepted) |
| `--verbose` | console timing lines | — | — | flag | — | false | plumbing |

**Output contract**

| Field | DICOM source | Encoding (standard) | Encoding (code) | Verdict |
|---|---|---|---|---|
| attribute name | tag | F.2.2: 8 uppercase hex | `%04X%04X` | match (32/32 objects) |
| `vr` | PS3.6 VR | F.2.3 / Table F.2.3-1 (34 VRs) | `element.vr.rawValue` | match |
| `Value` | Value Field | Table F.2.3-1 types; null for empty values (F.2.5); `{}` for an empty item | as standard | match |
| PN `Alphabetic` / `Ideographic` / `Phonetic` | PN groups | F.2.2, non-empty groups only | as standard | match (3-group name validated) |
| `InlineBinary` | OB/OD/OF/OL/OV/OW/UN Value Field | F.2.7, one Base64 string | as standard | match |
| `BulkDataURI` | Bulk Data | F.2.6 | `<url>/<GGGGEEEE>` | match (D110) |
| Group Length (gggg,0000) | — | F.2.2 shall not be included | excluded | match |
| private elements | PS3.5 7.8.1 | F.2.2 Note | gggg10ee + creator (0009,0010) kept | match |
| empty attribute | VL 0 | F.2.5 `{"vr"}` | was dropped by default → kept | wrong → fixed |
| console lines (Input/Output/Mode, Read/Parsed/Encoded/Wrote, "✓ Conversion complete") | — | — | `DataExchangeWorkflow` | plumbing |
| exit codes | — | — | 0; 64 usage / file not found / "Invalid tag"; 1 parse or write errors | plumbing |

**Fixed (`78214e8`, 4 tests in new target `dicom-jsonTests`)**: `--include-empty` default on per F.2.5 with `--no-include-empty` added (the old spelling still parses); `--filter-tag` accepts `GGGGEEEE` and `(GGGG,EEEE)`; help for `--no-sort-keys`, `--inline-threshold`, `--bulk-data-url`, `--metadata-only` and `--filter-tag` states the standard behaviour. README: the removed `--format` / `--stream` rows deleted, BulkDataURI example `.../7FE00010` (was a UID, which the code never writes), "Section F" changed to "Annex F", option rows synced.

**P-items**
- P-JSON-NO-SORT-KEYS: `--no-sort-keys` can only produce JSON that breaks PS3.18 F.2.2. Proposal: deprecate it (keep it parsing and print a stderr warning), then remove it. Not implemented.

**Deferred findings**
- D111: DICOMWeb `DataExchangeWorkflow.encode` (Sources/DICOMWeb/DataExchangeWorkflow.swift:154-156). `metadataOnly` removes only (7FE0,0010) at the top level. Float Pixel Data (7FE0,0008), Double Float Pixel Data (7FE0,0009), Encapsulated Document (0042,0011), waveform and overlay data stay inline (seen: a 2048-byte OB was inlined). PS3.18 10.4.1.1.2 / 10.4.3.3.2 define Metadata as all attributes with the bulk data omitted or replaced by a BulkDataURI. Low (the help now says what the flag does).
- D110: DICOMWeb `DICOMJSONEncoder.encodeElement` (Sources/DICOMWeb/DICOMJSONEncoder.swift:159) and `DICOMXMLEncoder` (Sources/DICOMWeb/DICOMXMLEncoder.swift:188). The BulkDataURI is `<base>/<GGGGEEEE>` regardless of nesting, so the same tag in two sequence items, or at two levels, gets one URI for different values. PS3.18 F.2.6 / PS3.19 Table A.1.5-2: the URI references that element's own Bulk Data. Low.
- D112: DICOMWeb `DataExchangeWorkflow.decode` (Sources/DICOMWeb/DataExchangeWorkflow.swift:216-217). `DICOMFile.create` is called without `sopClassUID:` / `sopInstanceUID:`, so a reverse-converted file gets Media Storage SOP Class UID 1.2.840.10008.5.1.4.1.1.7 and a freshly generated Media Storage SOP Instance UID. Seen: a CT (0008,0016) 1.2.840.10008.5.1.4.1.1.2 with (0002,0002) .1.1.7, and (0002,0003) ≠ (0008,0018). This breaks PS3.10 Table 7.1-1 ("Uniquely identifies the SOP Class / SOP Instance associated with the Data Set"). It affects dicom-json and dicom-xml `--reverse`. High.
- D113: DICOMWeb `DataExchangeWorkflow.decode` (DataExchangeWorkflow.swift:204-209). The decoder runs with `fetchBulkData: false`, so an attribute that carries a BulkDataURI (JSON) or BulkData (XML) is written to the PS3.10 file as a zero-length element, with no warning (seen: the OB and OW values were lost on round trip). PS3.18 F.2.6 / PS3.19 A.1.5-2: the value is retrievable, not empty. Medium.
- D114 (DICOMStudio): Workshop `CLIWorkshopViewModel.swift:1258` builds `includeEmpty` from `paramValue("include-empty") == "true"`, and `CLIWorkshopHelpers.swift:2847` / `:2920` offer only `--include-empty`. The app default is still "drop", so it now differs from the CLI default (on, PS3.18 F.2.5 / PS3.19 A.1.5-2), and it has no `--no-include-empty`. Low.

**Marker**: main.swift "// NEMA-verified: 2026a, checked 2026-10-01 — options read against PS3.18 2026a F.2.2 (ascending attribute order, 8-hex attribute names), F.2.5 (empty attribute kept as "vr" only), F.2.6 / F.2.7 (BulkDataURI, InlineBinary), 10.4.1.1.2 / 10.4.3.3.2 (Metadata resource); 11 options; output validated by script against Table F.2.3-1 (34 VRs)". check_nema_markers 1/1.

**For Scripts/diff_cli.py (orchestrator)**: optional check: run `<scratch>/jx_validate.py` (Annex F / A.1.5-2 validator) over a fresh conversion of a fixture.

**Tests**: `swift build --product dicom-json` ok. In the repo, `swift test --filter` could not link the bundle because another agent's uncommitted dicom-server target did not compile (ServerSession.swift:1146). The same sources and test files were run in a scratch harness package (`<scratch>/jxpkg`, symlinked sources, repo DICOMKit as a path dependency): dicom-jsonTests 4/4 and dicom-xmlTests 4/4 passed.

### dicom-xml (G2, PS3.19 2026a Annex A.1)

Files: main.swift (B2). There is no encoder in the tool: it runs the shared `DataExchangeWorkflow` (DICOMWeb), which drives
`DICOMXMLEncoder` / `DICOMXMLDecoder`. Commit `4a428da`.

**Evidence (by script, 2026a DocBook)**
- `Scripts/diff_web.py` `check_xml_model` re-run over the engines: Table A.1.5-2 / A.1.6 elements, attributes and the 34 schema VRs, 54/54, 0 fails. The tool sources hold no XML-model code.
- Tables A.1.5-1 and A.1.5-2 dumped by `nema_docbook.py table`, plus the cell text of the `Value`, `>>uri` and `InlineBinary` rows. Key rules: keyword is "Required unless the DICOM Data Element is unknown to the host"; there is a DicomAttribute "corresponding to each DICOM Attribute"; an empty value inside a multi-valued field is written `<Value number="2"></Value>`, and a zero-length Value Field has "no Infoset Value elements at all"; PersonName / Value / Item `number` runs "monotonically increasing ... from 1 by 1"; BulkData `uri` is "Required if the NativeDicomModel was returned in response to a Studies Service Retrieve (WADO-RS) Retrieve Metadata request. Shall not be present otherwise", and `uuid` is required when there is no uri; xml:space="preserve" "shall be included" (A.1.5-1).
- Schema: the A.1.6 RELAX NG Compact text was extracted from the DocBook by script (`<scratch>/jx_native.rnc`), converted with rnc2rng, and every output was validated with `xmllint --relaxng`. Result: 7/7 outputs validate (default, empties kept, `--no-keywords`, `--bulk-data-url`, `--metadata-only`, `--inline-threshold 0`, fixture) once `xml:space` is stripped. The normative schema does not declare the `xml:space` attribute that Table A.1.5-1 requires, so every conformant document fails the schema as published; this is a defect in the standard, recorded as a verification note.
- Script validation (`<scratch>/jx_validate.py`): tag pattern, schema VR list, keyword equal to the PS3.6 Table 6-1 keyword (5263 keywords loaded; 0 mismatches), privateCreator on private elements only, private tag in gggg00ee form (0009,1001 → `00090001 privateCreator="ACME 1.0"`), number runs 1..n, BulkData uri/uuid exclusivity, and empties kept. Before the fix, the default output had 4 violations (3 empty attributes dropped, plus D115). After: 32 DicomAttributes, 1 violation (D115, engine). `--no-keywords` gives 29 keyword violations, as expected.

**Counts: matched 2, wrong 1, missing 1, extra 2, plumbing 5** (11 rows; wrong and missing fixed).

**Input contract**

| Option | DICOM concept | 2026a reference | Allowed per standard | Code accepts | Default (std) | Default (code) | Verdict |
|---|---|---|---|---|---|---|---|
| `<input>` | PS3.10 file / Native DICOM Model document | PS3.10 7.1; PS3.19 A.1 | — | path | — | — | plumbing |
| `-o, --output` | output path | — | — | path; default `<input>.xml` / `.dcm` | — | — | plumbing |
| `-r, --reverse` | XML → PS3.10; TS from (0002,0010) else 1.2.840.10008.1.2.1 | PS3.19 A.1; PS3.6 Table A-1 | — | flag | — | false | plumbing |
| `-p, --pretty` | indentation (xml:space="preserve" still written) | PS3.19 Table A.1.5-1 | — | flag | — | false | plumbing |
| `--no-keywords` | `keyword` attribute | PS3.19 Table A.1.5-2 (C: required unless unknown) | present for every PS3.6 element | flag omits it | present | present | extra (non-conformant; help now says so; P-XML-NO-KEYWORDS) |
| `--include-empty` | zero-length attribute as DicomAttribute without Value | PS3.19 Table A.1.5-2 | kept | `--include-empty` / `--no-include-empty` (added) | kept | was dropped → kept | wrong → fixed |
| `--inline-threshold` | InlineBinary vs BulkData (OB/OD/OF/OL/OV/OW/UN) | PS3.19 Table A.1.5-2 | either | bytes; acts only with `--bulk-data-url` (0 = all BulkData) | — | 1024 | match (help corrected) |
| `--bulk-data-url` | BulkData `uri` | PS3.19 Table A.1.5-2 `>>uri` / `>>uuid` | uri only in a WADO-RS Retrieve Metadata response, else uuid | `<url>/<GGGGEEEE>`; uuid not offered | — | none | match (help states the uri condition; D110) |
| `--metadata-only` | drop Pixel Data | PS3.18 10.4.1.1.2 / 10.4.3.3.2 | — | (7FE0,0010) only | — | false | extra (tool convention; help corrected; D111) |
| `--filter-tag` | attribute selection | PS3.6 Table 6-1; PS3.19 A.1.5-2 tag form | — | keyword, `GGGG,EEEE`; added `GGGGEEEE`, `(GGGG,EEEE)` | — | none | missing → fixed (help said "group") |
| `--verbose` | console timing lines | — | — | flag | — | false | plumbing |

**Output contract**

| Field | DICOM source | Encoding (standard) | Encoding (code) | Verdict |
|---|---|---|---|---|
| root `NativeDicomModel`, namespace, xml:space | — | A.1.6 namespace; A.1.5-1 xml:space="preserve" | as standard | match |
| `DicomAttribute@tag` | tag | `[0-9A-F]{8}`; private gggg00ee | as standard | match |
| `@vr` | PS3.6 VR | A.1.6 list (34) | `vr.rawValue` | match |
| `@keyword` | PS3.6 keyword | A.1.5-2 C | DICOMDictionary keyword | match (0 mismatches against Table 6-1) |
| `@privateCreator` | (gggg,00xx) value | A.1.5-2 C | as standard | match |
| `Value@number` | values | 1..n by 1; empty value is an empty element | as standard | match |
| `PersonName@number` + Alphabetic/Ideographic/Phonetic, FamilyName..NameSuffix | PN | 1..n by 1 | an empty PN value is skipped, giving 1,3 | wrong (engine, D115) |
| `Item@number` | SQ items | 1..n by 1 | as standard | match |
| `InlineBinary` / `BulkData@uri` | binary VRs | A.1.5-2 | uri only (no uuid form) | match (uri condition noted) |
| empty attribute | VL 0 | DicomAttribute without children | was dropped by default → kept | wrong → fixed |
| console lines, exit codes | — | — | as dicom-json | plumbing |

**Fixed (`4a428da`, 4 tests in new target `dicom-xmlTests`)**: `--include-empty` is on by default and `--no-include-empty` is added. `--filter-tag` also accepts `GGGGEEEE` and `(GGGG,EEEE)`. Help text corrected for `--no-keywords`, `--inline-threshold`, `--bulk-data-url`, `--metadata-only` and `--filter-tag`. README: "Native DICOM Model (PS3.19 Annex A.1)" (was "DICOM Native XML Model"), xml:space added to the example, option rows synced.

**P-items**
- P-XML-NO-KEYWORDS: `--no-keywords` can only produce XML that breaks PS3.19 Table A.1.5-2. Proposal: deprecate it with a stderr warning, then remove it. Not implemented.

**Deferred findings**
- D115: DICOMWeb `DICOMXMLEncoder` (Sources/DICOMWeb/DICOMXMLEncoder.swift:199, `where !value.isEmpty`). An empty value of a multi-valued PN is skipped, so the numbers come out as 1, 3. `DICOMXMLDecoder` then collapses the gap and the value is lost on round trip; seen: (0010,1001) "A^B\\C^D^E^Dr^Jr" comes back with 2 values. PS3.19 Table A.1.5-2: PersonName number runs "monotonically increasing from 1 by 1". The A.1.6 schema allows an empty `<PersonName number="2"/>`. Low.
- D111 to D113 (DataExchangeWorkflow metadata-only, BulkDataURI collisions, File Meta SOP UIDs on reverse, BulkData written as zero-length on reverse) apply to dicom-xml as well; see dicom-json.
- D114 (Studio Workshop include-empty default) also covers the dicom-xml form (CLIWorkshopHelpers.swift:2920).

**Verification note**: the PS3.19 2026a A.1.6 RELAX NG schema does not declare `xml:space`, which Table A.1.5-1 requires ("shall be included"). Strict schema validation therefore needs the attribute stripped or declared; this is a defect in the standard, not in DICOMKit.

**Marker**: main.swift "// NEMA-verified: 2026a, checked 2026-10-01 — options read against PS3.19 2026a Table A.1.5-1 / A.1.5-2 (keyword required for PS3.6 elements, DicomAttribute per attribute, empty Value Field, BulkData uri/uuid, InlineBinary); 11 options; output validated by script and by xmllint against the A.1.6 RELAX NG schema (34 VRs)". check_nema_markers 1/1.

**Tests**: `swift build --product dicom-xml` ok. In the repo, `swift test --filter` could not link the bundle because another agent's uncommitted dicom-server target did not compile (ServerSession.swift:1146). The same sources and test files were run in a scratch harness package (`<scratch>/jxpkg`, symlinked sources, repo DICOMKit as a path dependency): dicom-jsonTests 4/4 and dicom-xmlTests 4/4 passed.

### dicom-study (G2) — 2026-10-01

Bucket: B2 (help only; the CLI is a thin adapter — scanning, grouping, organize naming, every printed
label and JSON/CSV key live in DICOMKit `Sources/DICOMKit/Study/StudyManager.swift` and
`StudyOrganizer.swift`, which were not changed: engine findings are deferred below). Evidence scripts
(scratch/reports): `g2sae_std.py` (PS3.4 Tables C.6-1..C.6-5 key types, PS3.6 Table 6-1 rows for 37
attributes, PS3.3 Tables C.7-1/C.7-3/C.7-5a/C.7-9), `g2sae_checks.py` (every "Name (gggg,eeee)" in the
tool's Swift + README vs Table 6-1: 9 matched, 0 wrong; engine JSON keys vs PS3.6 keywords),
`diff_cli.py --tool dicom-study` (0 FAIL; extractor lists commands ['dicom-study'] only — the
`extension DICOMStudy { struct Organize … }` subcommands are not split out; harmless, noted).

#### Input contract (20 options)

| Option | Concept | 2026a ref | Standard values | Code | Verdict |
|---|---|---|---|---|---|
| organize `<input>`, --output, --copy, --verbose | paths, copy/move, output | PS3.10 7.1 (DICM test) | — | — | plumbing (4) |
| organize --pattern | folder names; grouping by Study / Series unique keys | PS3.4 C.6-2 / C.6-3 (Study Instance UID, Series Instance UID: U); PS3.6 Table 6-1 | — | `descriptive` = <Patient's Name>_<Study Description>_<last 8 of Study Instance UID>/<Series Number>_<Modality>_<Series Description>/<n>.dcm; `uid` = <Study Instance UID>/<Series Instance UID>; help said only "'descriptive' or 'uid'", now names the 7 attributes | match |
| summary `<path>`, --format (table/json/csv), --verbose | — | — | — | — | plumbing (3) |
| check `<path>`, --report, --verbose | — | — | — | — | plumbing (3) |
| check --expected-series | Number of Study Related Series (0020,1206) | PS3.4 C.6-2; PS3.6 6-1 | count | distinct Series Instance UIDs | match |
| check --expected-instances | Number of Series Related Instances (0020,1209) | PS3.4 C.6-3; PS3.6 6-1 | count | instances per series | match |
| stats `<path>`, --detailed, --format | — | — | — | — | plumbing (3) |
| compare `<path1>`, `<path2>`, --format, --verbose | — | — | — | — | plumbing (4) |

Counts: matched 3, wrong 0, missing 0, extra 0, plumbing 17.

#### Output contract (DICOMKit StudyReport / StudyOrganizer — engine)

| Item | 2026a ref | Standard | Code | Verdict |
|---|---|---|---|---|
| Grouping keys | PS3.4 C.6-2 / C.6-3 / C.6-4 (U) | Study Instance UID, Series Instance UID, SOP Instance UID | same; series compared by Series Instance UID in `compare` | match |
| summary JSON keys (StudyMetadata 7, SeriesMetadata 4, InstanceMetadata 2 of 4) | PS3.6 keywords | lowerCamel of keyword | studyInstanceUID, studyDate, studyTime, studyDescription, patientName, patientID, accessionNumber, seriesInstanceUID, seriesNumber, seriesDescription, modality, sopInstanceUID, instanceNumber | match (13); filePath, fileSize plumbing |
| summary CSV header | PS3.6 keywords | StudyInstanceUID, NumberOfStudyRelatedSeries, NumberOfStudyRelatedInstances | `StudyUID`, `SeriesCount`, `InstanceCount` (StudyDate, PatientName, PatientID match) | tool-specific (P-STUDY-1) |
| summary table labels | PS3.6 Table 6-1 | Study Instance UID, Patient's Name, Study Description, Series Number, Series Description, Number of Study Related Series / Instances, Number of Series Related Instances | "Study UID", "Patient Name", "Description", "Number", "Series Count", "Total Instances", "Instances" ("Study Date", "Patient ID", "Modality" match) | wrong label text (engine, D116) |
| stats / compare JSON keys | — | — | studyUID, seriesCount, totalInstances, … (17 keys, none a keyword) | tool-specific (P-STUDY-1) |
| stats "Modalities:" | PS3.3 C.7-5a Modality (series level) | — | series counted per Modality | match |
| check gaps | PS3.3 Table C.7-9 Instance Number "A number that identifies this image", Type 2 | no contiguity rule | gaps reported as missing | tool-specific heuristic (now said in help) |
| organize descriptive series folder | PS3.4 C.6-3 (Series Instance UID is the unique key) | — | <Series Number>_<Modality>_<Series Description> can collide | engine bug (D117) |
| verbose "Missing StudyInstanceUID" | PS3.6 keyword | StudyInstanceUID | same | match |
| Exit codes | — | — | thrown StudyError → 1; `check` exits 0 even when incomplete | plumbing |

#### Commit / tests
b91e7b2 `docs(cli): dicom-study help names the PS3.6 2026a attributes of organize --pattern, …; dicom-studyTests` — main.swift (help, discussion, marker), StudyManager.swift (marker), README (naming patterns, gap heuristic), Package.swift `dicom-studyTests` (own hunk only, staged from HEAD), Tests/dicom-studyTests/StudyHelpTests.swift, CHANGELOG bullet.
`swift build --product dicom-study`: OK. `swift test --filter StudyHelpTests`: 3 tests, 0 failures. `check_nema_markers.py Sources/dicom-study`: 2/2. `diff_cli.py --tool dicom-study`: 0 FAIL.

#### Deferred findings
| ID | File:line | Problem | Ref | Severity |
|---|---|---|---|---|
| D116 | Sources/DICOMKit/Study/StudyManager.swift:235-249 (renderSummary), 289-291 (renderStats) | Labels are not PS3.6 names: "Study UID", "Patient Name", "Description" (study and series), "Number", "Series Count", "Total Instances", "Instances" | PS3.6 Table 6-1; PS3.4 C.6-2 / C.6-3 | Low |
| D117 | Sources/DICOMKit/Study/StudyOrganizer.swift:113-118, 126 | `--pattern descriptive` series folder `<Series Number>_<Modality>_<Series Description>` is not unique: two series with equal values (Series Number is Type 2; absent → "0") share a folder and the second copy fails "already exists" at `<n>.dcm`. Key the folder on (or suffix it with) Series Instance UID | PS3.4 Table C.6-3 (Series Instance UID U); PS3.3 Table C.7-5a (Series Number Type 2) | Medium |
| D118 | Sources/DICOMKit/Study/StudyManager.swift:165-166; StudyOrganizer.swift:77 | Files without Series Instance UID / SOP Instance UID (Type 1) are merged under "UNKNOWN"/"UNKNOWN_SERIES" instead of being reported | PS3.3 Table C.7-5a; C.12-1 | Low |
| D119 | Sources/DICOMKit/Study/StudyManager.swift:1, StudyOrganizer.swift:1 | Markers say "carries no DICOM-standard data", but the files read 13 attributes, group by the Q/R unique keys and build names from 6 attributes; the marker claim should name what was compared | DICOMCORE method, "The marker" | Low |

P-items:
- **P-STUDY-1** — summary CSV header `StudyUID,…,SeriesCount,InstanceCount` and stats/compare JSON keys `studyUID`, `seriesCount`, `totalInstances` (DICOMKit StudyReport / Statistics, shared with DICOMStudio) → PS3.6 keywords `StudyInstanceUID`, `NumberOfStudyRelatedSeries`, `NumberOfStudyRelatedInstances` (JSON: lowerCamel). Keep the old keys until approved.

Marker (main.swift): `// NEMA-verified: 2026a, checked 2026-10-01 — help names the hierarchy keys of PS3.4 2026a Tables C.6-2 / C.6-3 / C.6-4 (Study Instance UID (0020,000D), Series Instance UID (0020,000E), SOP Instance UID (0008,0018) are the unique keys) and the PS3.6 Table 6-1 names of the 8 attributes used for folder names and checks (…); all match. Labels and JSON/CSV keys are printed by DICOMKit StudyReport (deferred, …)`; StudyManager.swift: `… thin adapters over DICOMKit StudyScanner / StudyReport; the file itself carries no DICOM-standard data (paths, error text, printing)`.

### dicom-archive (G2) — 2026-10-01

Bucket: B2. The CLI is a thin adapter over DICOMKit `Sources/DICOMKit/Archive/ArchiveStore.swift`
(index model, matching, every printed label and JSON key), which was not changed: engine findings are
deferred below. Evidence scripts (scratch/reports): `g2sae_std.py match` (PS3.4 C.2.2.2.1, .1.1, .1.2,
.1.3, .2, .4, .5 text), `g2sae_std.py levels` (PS3.4 Tables C.6-1..C.6-5), `g2sae_std.py dict` (PS3.6
Table 6-1 rows), `g2sae_checks.py` (names next to tags in Swift + README: 30 matched, 0 wrong; JSON keys
of ArchiveInstance/Series/Study/Patient/QueryResult vs PS3.6 keywords), `diff_cli.py --tool
dicom-archive` (0 FAIL).

Matching, from the 2026a text: Wild Card Matching (C.2.2.2.4) — "* shall match any sequence of
characters (including a zero length value) and ? shall match any single character. This matching is
case sensitive, except for Attributes with a PN VR"; List of UID Matching (C.2.2.2.2) — backslash
list; Range Matching of DA (C.2.2.2.5.1) — "<date1> - <date2>", "- <date1>", "<date1> -".

#### Input contract (30 options)

| Option | Concept | 2026a ref | Standard values | Code | Verdict |
|---|---|---|---|---|---|
| init --path, --force | archive dir | — | — | — | plumbing (2) |
| import `<files>`, --archive, --recursive, --verbose | PS3.10 files | PS3.10 7.1 | — | — | plumbing (4) |
| import --skip-duplicates | dedup on SOP Instance UID (0008,0018) | PS3.4 C.6-4 (U) | instance unique key | duplicates always skipped; flag only stops counting them as errors | match |
| query --archive, --format | — | — | — | table, json, text | plumbing (2) |
| query --patient-name | Patient's Name (0010,0010), Wild Card Matching | PS3.4 C.2.2.2.4; C.6-1 (R) | * ?; PN case handling implementation dependent | * ?, case-insensitive | match |
| query --patient-id | Patient ID (0010,0020) LO, Wild Card Matching | PS3.4 C.2.2.2.4; C.6-1 (U) | * ?; case-sensitive | * ?, case-insensitive (README "Limitations" said so; help now too) | match, documented deviation (D120) |
| query --study-uid | Study Instance UID (0020,000D) | PS3.4 C.2.2.2.1 / C.2.2.2.2; C.6-2 (U) | single UID or backslash list | one UID, exact; list matched nothing → now warned | match (list: warned) |
| query --modality | Modality (0008,0060) of any series = Modalities in Study (0008,0061) | PS3.4 C.6-2 / C.6-5 (Modalities in Study O); PS3.3 C.7.3.1.1.1 | Defined Terms | ModalityOptionValidator (DICOMCore, verified); exact, upper-cased; help now names the semantics | match |
| query --strict-modality | reject non-Defined-Term | PS3.3 C.7.3.1.1.1 | — | flag | match |
| query --study-date | Study Date (0008,0020) DA | PS3.4 C.2.2.2.1.3, C.2.2.2.5; PS3.5 Table 6.2-1 | YYYYMMDD or range | exact string; range / non-DA matched nothing → now warned | match (range: warned) |
| list --archive, --format, --show-instances | — | — | — | tree, table, json | plumbing (3) |
| export --archive, --output, --flatten, --verbose | — | — | — | — | plumbing (4) |
| export --study-uid / --series-uid | Study / Series Instance UID | PS3.4 C.6-2 / C.6-3 (U) | — | one UID, exact; list warned | match (2) |
| export --patient-id | Patient ID (0010,0020) | PS3.4 C.6-1 (U) | — | exact, no wild cards (help now says so) | match |
| check --archive, --verify-files, --verbose | — | PS3.10 7.1 | — | — | plumbing (3) |
| stats --archive, --format | — | — | — | text, json | plumbing (2) |

Counts: matched 10, wrong 0, missing 0, extra 0, plumbing 20. (The two "matched nothing in silence"
rows were fixed with a warning, not with range/list matching, which is engine work: D121.)

#### Output contract (DICOMKit ArchiveStore — engine)

| Item | 2026a ref | Standard | Code | Verdict |
|---|---|---|---|---|
| Storage path data/<Patient ID>/<Study Instance UID>/<Series Instance UID>/<SOP Instance UID>.dcm | PS3.4 C.6-1..C.6-4 unique keys | — | same | match |
| Index / query JSON keys | PS3.6 keywords | lowerCamel | patientName, patientID, studyInstanceUID, studyDate, studyDescription, accessionNumber, seriesInstanceUID, seriesNumber, seriesDescription, modality, sopInstanceUID, sopClassUID, instanceNumber | match (13 keyword keys) |
| study-level `modality` (index, query JSON/table/text) | PS3.4 C.6-2 / C.6-5: study level carries Modalities in Study (0008,0061), CS 1-n | all series modalities | Modality of the first instance imported | wrong (engine, D122; key P-ARCHIVE-1) |
| query JSON `seriesCount`, `imageCount`; table "Series", "Images" | PS3.6: Number of Study Related Series / Instances | — | counts are right; names not PS3.6, "Images" counts non-image instances too | tool-specific (P-ARCHIVE-1, D123) |
| query table "Patient Name", "Description" | PS3.6 Patient's Name, Study Description | — | — | wrong label text (D123) |
| stats "SOP Classes:" | PS3.6 Table A-1 | UID + name | UID only | tool-specific (D123) |
| `creationDate` (index, stats JSON) | — | collides with PS3.6 keyword CreationDate but is the archive's own ISO 8601 time | — | plumbing |
| Errors | — | — | ArchiveError → ValidationError, exit 64; other errors exit 1 | plumbing |

#### Commit / tests
d46affe `fix(cli): dicom-archive warns on Study Date ranges and UID lists it matches exactly (PS3.4 2026a C.2.2.2.5 / C.2.2.2.2); …; dicom-archiveTests` — new Sources/dicom-archive/QueryKeys.swift, main.swift (help, discussion, warnings, marker), README (matching section, options, study `modality`), Package.swift `dicom-archiveTests` (own hunk only), Tests/dicom-archiveTests/ArchiveQueryKeysTests.swift, CHANGELOG bullet.
`swift build --product dicom-archive`: OK. `swift test --filter ArchiveQueryKeysTests`: 6 tests, 0 failures. `check_nema_markers.py Sources/dicom-archive`: 2/2. `diff_cli.py --tool dicom-archive`: 0 FAIL.

#### Deferred findings
| ID | File:line | Problem | Ref | Severity |
|---|---|---|---|---|
| D120 | Sources/DICOMKit/Archive/ArchiveStore.swift:83-87 | `wildcardMatch` upper-cases pattern and value for every key; Patient ID (LO) wild cards must be case-sensitive (now documented as tool-specific in help and README) | PS3.4 C.2.2.2.4 | Low |
| D122 | ArchiveStore.swift:416-423 (makeStudy), 496, 527, 548 | The study record's `modality` is the first imported instance's Modality and is shown as the study's Modality; a multi-modality study (e.g. PET/CT, MR + SR) is misreported. Should be Modalities in Study (0008,0061): the distinct series Modality values, recomputed on import | PS3.4 Tables C.6-2 / C.6-5; PS3.6 (0008,0061) CS 1-n | Medium |
| D121 | ArchiveStore.swift:461, 466, 677 | No List of UID Matching or DA Range Matching for Study Instance UID / Study Date (the CLI now warns) | PS3.4 C.2.2.2.2, C.2.2.2.5.1 | Low |
| D123 | ArchiveStore.swift:484, 544-550, 612, 887-893 | Labels "Patient Name", "Description", "Series", "Images", "Studies" are not PS3.6 names (Patient's Name, Study Description, Number of Study Related Series / Instances, Number of Patient Related Studies); "Images" counts every instance; "SOP Classes:" prints UIDs without their Table A-1 names | PS3.6 Table 6-1, Table A-1 | Low |
| D124 | ArchiveStore.swift:289-290, 425 | Patients keyed on Patient ID alone: Issuer of Patient ID (0010,0021) ignored, and every file with an empty/absent Patient ID (Type 2) merges into one "UNKNOWN" patient whose Patient's Name is the first file's | PS3.4 Tables C.6-1 / C.6-5 (Issuer of Patient ID); PS3.3 Table C.7-1 | Low |
| D125 | ArchiveStore.swift:1 | Marker says "carries no DICOM-standard data (SQLite-backed index)": the index is JSON, and the file implements C-FIND-like matching and the Q/R hierarchy; the marker should name what was compared | DICOMCORE method, "The marker" | Low |

P-items:
- **P-ARCHIVE-1** — JSON keys (ArchiveStudy in archive_index.json, query JSON): study-level `modality` → `modalitiesInStudy` (array, PS3.6 keyword ModalitiesInStudy); query `seriesCount` / `imageCount` → `numberOfStudyRelatedSeries` / `numberOfStudyRelatedInstances`. Changes the on-disk index format (needs a reader for old indexes) and DICOMStudio. Keep the old keys until approved.

Marker (main.swift): `// NEMA-verified: 2026a, checked 2026-10-01 — option help names the PS3.6 2026a Table 6-1 attributes each key matches (…; all match) and how it matches against PS3.4 C.2.2.2 (wild cards * ?, case-insensitive: tool-specific for LO; no range or UID-list matching, warned); labels and JSON keys are printed by DICOMKit ArchiveStore (deferred, …)`; QueryKeys.swift: `… the archive's query and export keys against PS3.4 2026a C.2.2.2 (Single Value, List of UID C.2.2.2.2, Wild Card C.2.2.2.4, Range C.2.2.2.5 matching) and the Q/R key tables C.6-1 / C.6-2 / C.6-3 / C.6-5; the 7 attribute names and tags in the help match PS3.6 Table 6-1; matching that is not DICOM's is documented as tool-specific`.

### dicom-export (G2) — 2026-10-01

Bucket: B2. Rendering engine (DICOMImageExporter.renderFrameForExport → GrayscaleDisplayPipeline,
PS3.4 N.2) is verified in DICOMKit (D65/D66/D67) and was not changed; only what the CLI passes and
prints was checked. PNG / JPEG / TIFF / GIF and EXIF/TIFF tags are not NEMA standards — plumbing.
Evidence scripts (scratch/reports): `g2sae_std.py modules` (PS3.3 Tables C.7-9, C.7-13, C.7-14,
C.11-2b, C.11.6-1), `g2sae_std.py render` (C.11.2.1.2.1, C.11.2.1.3 — LINEAR, SIGMOID, LINEAR_EXACT —
C.11.6.1.2 IDENTITY / INVERSE, C.7.6.6.1.1, C.7.6.5.1.1 "the first Frame number is one", C.7.6.3.1.2:
14 photometric terms), `g2sae_std.py dict`, `g2sae_checks.py` (names next to tags in Swift + README: 54
matched, 0 wrong; the 9 `--exif-fields` names are PS3.6 keywords and equal the engine's 9 mapped
fields), `diff_cli.py --tool dicom-export` (0 FAIL).

#### Input contract (38 options + 3 concept rows)

| Option | Concept | 2026a ref | Standard values | Code | Verdict |
|---|---|---|---|---|---|
| single `<input>`, --output, --format, --quality | file, PNG/JPEG/TIFF | PS3.10 7.1 | — | png, jpeg, tiff; 1-100 | plumbing (4) |
| single --embed-metadata | attributes → EXIF/TIFF | — | — | flag | plumbing |
| single --exif-fields | attribute keywords | PS3.6 Table 6-1 | keywords | 9 keywords, all PS3.6; help gave 3 examples, now lists all 9 | match |
| single / animate --apply-window | explicit window instead of the file's VOI | PS3.3 C.11.2.1.2.1 (LINEAR) | — | single: file VOI by default (Window Center/Width + VOI LUT Function, else VOI LUT Sequence, else full range), flag gates explicit values; animate: see below | match (single) |
| single / animate --window-center, --window-width | Window Center (0028,1050) / Window Width (0028,1051), modality units | PS3.3 C.11.2.1.2.1 (width >= 1) | after Modality LUT / rescale | passed to the N.2 chain in modality units; help said "Window center value", now names the attributes and units | match (4) |
| single --frame | frame selection | PS3.3 C.7.6.5.1.1 (first Frame number is one); C.7.6.6 | 1..Number of Frames | 0-based index, validated; help said "0-indexed", now "DICOM frame number - 1" | match, documented (P-EXPORT-1) |
| contact-sheet `<inputs>`, --output, --columns, --thumbnail-size, --spacing, --format, --quality, --labels | grid, image | — | — | — | plumbing (8) |
| contact-sheet --apply-window | VOI of thumbnails | PS3.3 C.11.2.1.2.1; PS3.4 N.2 | window after the rescale | `tryRenderFrameWithStoredWindow`: the HU window applied to stored values (CT 40/400 with intercept -1024 → wrong picture), single-valued DS only; default full-range auto | **wrong → fixed** (renderFrameForExport; flag kept as a no-op like bulk) |
| animate `<input>`, --output, --loop-count, --scale | — | — | — | — | plumbing (4) |
| animate --fps | display frame rate | PS3.3 Table C.7-13: Recommended Display Frame Rate (0008,2144), Cine Rate (0018,0040), Frame Time (0018,1063) msec (C.7.6.5.1.1) | from the file | fixed 10 | **missing → fixed** (default (0008,2144) > (0018,0040) > 1000/(0018,1063) > 10; `--fps` optional) |
| animate --apply-window | explicit window | PS3.3 C.11.2.1.2.1; PS3.4 N.2 | window in modality units | `determineWindowSettings` stored-unit window + `tryRenderFrame(window:)` (wrong for slope != 1, Modality LUT Sequence ignored); default per-frame auto window | **wrong → fixed** (renderFrameForExport, as single) |
| animate --start-frame, --end-frame | frame range | PS3.3 C.7.6.5.1.1 | 1-based | 0-based, end inclusive, clamped; help now says so | match, documented (2) (P-EXPORT-1) |
| bulk `<input>`, --output, --format, --quality, --recursive, --embed-metadata, --verbose | — | — | — | — | plumbing (7) |
| bulk --organize-by | folders from Patient's Name (0010,0010) / Study Instance UID / Series Instance UID | PS3.4 C.6-1..C.6-3 (Patient ID is the patient unique key) | — | flat, patient, study, series; help now names the attributes | match (P-EXPORT-2 for the patient key) |
| bulk --apply-window | — | — | — | no effect (file VOI always); help now says so | plumbing |
| (burned-in annotation) | Burned In Annotation (0028,0301) | PS3.3 Table C.7-9, C.7.6.1: Enumerated Values YES, NO | warn when YES | none | **missing → fixed** (stderr warning in all 4 subcommands) |
| (voi-lut-function) | VOI LUT Function (0028,1056) | PS3.3 C.11.2.1.3: LINEAR, LINEAR_EXACT, SIGMOID | — | not an option; the file's value is honoured by the engine; explicit windows LINEAR | match |
| (presentation-lut-shape) | Presentation LUT Shape (2050,0020) | PS3.3 C.11.6.1.2: IDENTITY, INVERSE | INVERSE for MONOCHROME1 (C.7.6.3.1.2) | engine: INVERSE for MONOCHROME1 else IDENTITY | match |

Counts: matched 12, wrong 2 (fixed), missing 2 (fixed), extra 0, plumbing 25.

#### Output contract

| Item | 2026a ref | Standard | Code | Verdict |
|---|---|---|---|---|
| Photometric handling (MONOCHROME1 inversion, PALETTE COLOR, RGB/YBR) | PS3.3 C.7.6.3.1.2 | — | engine (PixelDataRenderer / GrayscaleDisplayPipeline), now the same call in all 4 subcommands | match (delegated) |
| "Exported:", "Contact sheet exported:", "Animated GIF exported: … (N frames, X fps)", bulk lines | — | — | ExportConsole (DICOMKit); fps now the resolved rate | plumbing |
| Burned In Annotation warning (stderr) | PS3.3 Table C.7-9 | YES / NO | "warning: <file>: Burned In Annotation (0028,0301) is YES — …"; bulk/contact-sheet: one count line | match (new) |
| EXIF mapping (9 keywords) | PS3.6 keywords | — | PatientName→TIFF ImageDescription, StudyDate→Exif DateTimeOriginal, Modality→Exif "Software", … | plumbing; D126 |
| Errors / exit codes | — | — | "Invalid frame N. File has M frames (0-(M-1))"; thrown → exit 1 | plumbing |

#### Commit / tests
104202f `fix(cli): dicom-export contact-sheet and animate render through the PS3.4 N.2 chain like single/bulk; animate default fps from Recommended Display Frame Rate / Cine Rate / Frame Time (PS3.3 2026a Table C.7-13); Burned In Annotation (0028,0301) YES warning; 0-based frame index and PS3.6 names in help; dicom-exportTests` — new Sources/dicom-export/ExportStandard.swift (CineFrameRate, BurnedInAnnotation, ExportFrames), main.swift, README, Package.swift `dicom-exportTests` (own hunk only), Tests/dicom-exportTests/ExportStandardTests.swift, CHANGELOG bullets.
`swift build --product dicom-export`: OK. `swift test --filter ExportStandardTests`: 12 tests, 0 failures (incl. contact-sheet frame == single export and != the old stored-window render for a CT with intercept -1024). `check_nema_markers.py Sources/dicom-export`: 2/2. `diff_cli.py --tool dicom-export`: 0 FAIL.

#### Deferred findings
| ID | File:line | Problem | Ref | Severity |
|---|---|---|---|---|
| D126 | Sources/DICOMKit/ImageExport/DICOMImageExporter.swift:84-111 | `--exif-fields PatientID` is read (getDICOMFieldValue) but has no EXIF mapping and is dropped silently; Study Date (DA YYYYMMDD) is written unconverted into Exif DateTimeOriginal ("YYYY:MM:DD HH:MM:SS"); Modality goes to an Exif "Software" key | PS3.5 Table 6.2-1 DA (DICOM side only) | Low |
| D127 (to DICOMStudio) | Sources/DICOMStudio/ViewModels/CLIWorkshopViewModel.swift:4410, 4557-4562, 4620-4628 | The CLI Workshop mirror of `dicom-export` still uses fps 10 by default, `tryRenderFrameWithStoredWindow` for contact-sheet and a stored-unit window for animate: it now differs from the CLI and repeats the two fixed bugs; no Burned In Annotation warning | PS3.4 N.2; PS3.3 C.11.2.1.2.1, Table C.7-13, C.7-9 | Medium |

P-items:
- **P-EXPORT-1** — frame selection is 0-based (`single --frame`, `animate --start-frame/--end-frame`, error text "0-(M-1)"); PS3.3 C.7.6.5.1.1 numbers the first Frame 1. Proposal: accept DICOM frame numbers (e.g. `--frame-number`, `--start-frame-number`, `--end-frame-number`, 1-based) and deprecate the 0-based options. Now documented in help/README as "DICOM frame number - 1".
- **P-EXPORT-2** — `bulk --organize-by patient|study|series` names the patient folder from Patient's Name (0010,0010); the patient-level unique key is Patient ID (0010,0020) (PS3.4 Table C.6-1, U), so two patients with one name merge and one patient with name variants splits. Proposal: key on Patient ID (DICOMImageExporter.buildOrganizedPath signature + folder layout change, shared with DICOMStudio).
- **P-EXPORT-3** — `contact-sheet --apply-window` and `bulk --apply-window` have no effect (the file's VOI is always applied); deprecate or give them explicit `--window-center/--window-width`.

Marker (ExportStandard.swift): `// NEMA-verified: 2026a, checked 2026-10-01 — the DICOM inputs dicom-export reads: the cine rate attributes of the Cine Module, PS3.3 2026a Table C.7-13 (Recommended Display Frame Rate (0008,2144), Cine Rate (0018,0040), Frame Time (0018,1063) in msec, C.7.6.5.1.1; 3 rows, names and tags match PS3.6 Table 6-1), Burned In Annotation (0028,0301) Enumerated Values YES / NO of PS3.3 Table C.7-9 / C.7.6.1; the frame render goes through DICOMImageExporter.renderFrameForExport (PS3.4 N.2 chain, verified in DICOMKit)`; main.swift: `… option help names the PS3.6 2026a attributes it reads (…, the 9 --exif-fields keywords, all match Table 6-1); frames are 0-based indexes (frame number - 1, PS3.3 C.7.6.5.1.1 numbers the first Frame 1); PNG/JPEG/TIFF/GIF outputs are non-DICOM plumbing; every subcommand renders through ExportFrames (PS3.4 N.2 chain)`.

CHANGELOG ([Unreleased], section "Fixed — dicom-study, dicom-archive, dicom-export verified against DICOM 2026a (2026-10-01)"): 5 bullets, committed with the three tools.

### dicom-dcmdir (G2) — commit `a45fd45`

Compared: PS3.10 2026a 8.1 (File-set ID 0-16 chars), 8.2 (File ID 1-8 components of 1-8 chars), 8.5 (A-Z, 0-9, _), 8.6 (DICOMDIR, no File outside the File-set) — section text dumped by script; PS3.3 2026a Table F.4-1 (35 Directory Record Type terms; `DirectoryRecordType` raw values diffed by script: 35/35 match, 16 retired terms + internal ROOT extra by design), Tables F.3-2 / F.3-3 (File-set ID (0004,1130), File-set Consistency Flag (0004,1212) "The Value FFFFH shall never be present", Referenced File ID (0004,1500) "max 8 components, each 1 to 8 characters … referenced by at most one Directory Record", Referenced SOP Instance UID in File (0004,1511)); PS3.11 profile identifiers (done in ca2bd29, D29; D70 enforcement already filed). Tool run end-to-end on a 3-file fixture folder (create / validate / dump tree,text,json / --check-files). `Scripts/diff_cli.py --tool dicom-dcmdir`: 11 checks ok, 0 FAIL (16 options found; extractor needed no change).

**Input contract**

| Option | DICOM concept | 2026a reference | Allowed per standard | Code accepts | Default (std) | Default (code) | Verdict |
|---|---|---|---|---|---|---|---|
| `create <input-directory>` | File-set root; File IDs = relative paths | PS3.10 8.1, 8.2, 8.6 | File IDs 1-8 comps × 1-8 chars A-Z 0-9 _ | any directory; any file names | — | — | match (now warns when indexed names are not valid File IDs) |
| `create -o, --output` | reserved File ID DICOMDIR | PS3.10 8.6 | `DICOMDIR` in the File-set root | path | — | `<input>/DICOMDIR` | plumbing |
| `create --file-set-id` | File-set ID (0004,1130) | PS3.10 8.1, 8.5; PS3.3 Table F.3-2 | 0-16 chars A-Z 0-9 _ (Type 2) | any string | — | was raw dir name (e.g. lowercase `media`) | wrong → fixed: default upper-cased, other chars `_`, cut to 16; explicit invalid value warns (P-DCMDIR-FSID to reject) |
| `create --profile` | Application Profile | PS3.11 Tables A.1-1 … N.1-1 | 64 identifiers | DICOMDIRProfile | — | STD-GEN-CD | match (ca2bd29) |
| `create --recursive/--no-recursive` | discovery | — | — | flag | — | on | plumbing |
| `create --strict` | Part 10 read | PS3.10 7.1 | — | flag | — | off | plumbing |
| `create --verbose` | output | — | — | flag | — | off | plumbing |
| `validate <dicomdir-path>` | DICOMDIR / File-set folder | PS3.10 8.6 | — | path | — | — | plumbing |
| `validate --check-files` | Referenced File ID exists in File-set | PS3.10 8.6; PS3.3 Table F.3-3 | — | flag | — | off | wrong → fixed (engine check only rejected empty paths; CLI now stats every File ID) |
| `validate --detailed` | records by (0004,1430) | PS3.3 Table F.4-1 | 35 terms | flag | — | off | match |
| (validate rules) | File-set ID, File ID, duplicate File ID, hierarchy, duplicate SOP Instance — each naming its clause | PS3.10 8.1/8.2/8.5/8.6; PS3.3 F.3-2, F.3-3, F.4-1; PS3.5 9.1 | — | — | — | — | missing → fixed |
| `dump <dicomdir-path>` | DICOMDIR | PS3.10 8.6 | — | path | — | — | plumbing |
| `dump -f, --format` | output | — | — | tree, json, text | — | tree | plumbing |
| `dump --verbose` | record keys | PS3.3 F.5 key tables | attribute names | prints `(gggg,eeee): value` only | — | off | wrong (engine formatter, D128) |
| `update <dicomdir-path>` | FSU role | PS3.10 8.3 | — | path | — | — | plumbing |
| `update --add` | files to add | PS3.10 8.3, 8.6 | inside File-set | path | — | — | plumbing |
| `update --verbose` | output | — | — | flag | — | off | plumbing |

**Output contract**

| Output | Standard | Verdict |
|---|---|---|
| Record labels `PATIENT`, `STUDY`, `SERIES`, `IMAGE`, … (tree/text/`--detailed`) | PS3.3 Table F.4-1 Directory Record Type terms (35) | match |
| `File-set ID:` / `ID:` | PS3.6 name "File-set ID" (0004,1130) | match |
| `Consistent: true/Yes` | File-set Consistency Flag (0004,1212) | label not the PS3.6 name (low, D128) |
| `Profile:` | no attribute carries it (PS3.11; D15 documented) | match (documented assumption) |
| validate failure lines `❌ … [PS3.10 8.2, 8.5; PS3.3 Table F.3-3 Referenced File ID (0004,1500)]`, `[PS3.3 F.4, Table F.4-1]`, `[PS3.10 8.6 …]`, `[PS3.5 9.1 …]` | clause per rule | new (fixed: errors used to print "The operation couldn't be completed") |
| JSON keys `fileSetID profile isConsistent statistics{patients studies series images} recordCount` | tool-defined (no PS3.18 F model claimed) | extra/tool-defined |
| Exit codes 0 ok; 1 read/validation failure (now also File ID / File-set ID violations); 64 usage | — | plumbing |

Counts (17 rows): matched 3, wrong 3 (2 fixed, 1 deferred), missing 1 (fixed), extra 0, plumbing 10.

Changed: `Sources/dicom-dcmdir/FileSetRules.swift` (new), `main.swift`, `README.md` (SPACE not allowed in a File-set ID; File ID example without `.dcm`; 2026a Consistency Flag text; removed "update not implemented"; references PS3.3 Annex F / PS3.4 Annex I / PS3.10 8), new test target `dicom-dcmdirTests` (7 tests), CHANGELOG bullet. Behaviour change: `validate` exits 1 for a DICOMDIR whose File IDs are not PS3.10 8.2/8.5 conformant (e.g. ones `create` builds from `*.dcm` names; `create` now warns about that).

Tests: `swift test --filter FileSetRulesTests` 7/7 pass; `swift build --product dicom-dcmdir` ok; `check_nema_markers.py Sources/dicom-dcmdir` exit 0 (2 files).

Deferred:
| ID | Module | file:line | Problem | Ref | Severity |
|---|---|---|---|---|---|
| D129 | DICOMKit | `Sources/DICOMKit/DICOMDIRWriter.swift:346-395` (`DICOMDirectory.Builder.addFile`) | `DirectoryRecord` is a struct: when the series (or study) already exists, the copy that receives the new IMAGE (or SERIES) is never written back, so only the first image of each series and the first series of each study are indexed. Fixture: 2 distinct SOP Instances in one series → "Files processed: 3/3 … Images: 1". `DcmdirRoundTripTests` works around it with one patient per file | PS3.3 F.4, Table F.4-1, F.5.3/F.5.4 | High: DICOMDIR silently omits instances |
| D130 | DICOMCore | `Sources/DICOMCore/DICOMDirectory.swift:619-630` | `validate(checkFileExistence:)` is a placeholder (only rejects an empty path) — CLI now checks on disk | PS3.10 8.6 | Medium |
| D128 | DICOMKit | `Sources/DICOMKit/DICOMDIRDumpFormatter.swift:60-63, 158-161, 45, 141` | `--verbose` record attributes printed as bare tags, no PS3.6 attribute names; "Consistent" label instead of File-set Consistency Flag | PS3.6 Table 6-1; PS3.3 F.3-3 | Low |
| D131 | DICOMKit | `Sources/DICOMKit/DICOMDIRWorkflow.swift:166-172` | FSC writes the raw relative path as File ID (lower case, `.dcm`, >8 chars); an FSC should assign conformant File IDs | PS3.10 8.2, 8.5 | Medium |
| D132 | DICOMStudio | Workshop dcmdir executor | lacks the CLI's new validate rules and File-set ID default (parity) | PS3.10 8.x | Low |

P-items: **P-DCMDIR-FSID** — reject (instead of warn about) an explicit `--file-set-id` outside PS3.10 8.1/8.5 (accepted-value change).

Markers: `main.swift` (2nd line) `// NEMA-verified: 2026a, checked 2026-10-01 — create derives the default File-set ID per PS3.10 2026a 8.1/8.5 and warns on File IDs outside 8.2/8.5; validate reports each failure with its PS3.10 8.1, 8.2, 8.5, 8.6 / PS3.3 Table F.3-2, F.3-3, F.4-1 clause and --check-files tests every Referenced File ID (0004,1500) on disk (8.6); dump record labels are the 35 Directory Record Type terms of PS3.3 Table F.4-1 (DICOMCore.DirectoryRecordType)`; `FileSetRules.swift` `// NEMA-verified: 2026a, checked 2026-10-01 — File ID and File-set ID rules of PS3.10 2026a 8.1 …, 8.2 …, 8.5 …, 8.6 …; PS3.3 2026a Table F.3-2 …, Table F.3-3 … and Table F.4-1 …; every rule text extracted from the DocBook by script`.

### dicom-uid (G2) — commit `788f620`

Compared: PS3.5 2026a 9.1 (UID encoding rules), 9.2.2 (privately defined UIDs on a registered root), B.2 (UUID derived UID) — section text dumped by script; PS3.6 2026a Table A-1 (465 rows: `lookup --list-all --json` diffed by script — names 465/465 match, 2 extra unregistered Fragmentable HEVC entries by decision (DICOMCore P2); UID Type labels 444 match, 21 wrong); PS3.6 Table 6-1 UI attributes (92, 10 retired) and PS3.15 2026a Table E.1-1 (via `generate_confidentiality_profile.rows`: 53 rows are UI attributes, all action U except Annotation Group UID (006A,0003) D; U also for (0002,0003), (0004,1511), (0000,1001), and X/Z/U* for Referenced / Source Image Sequence) against `regenerate` run on two linked fixtures (ref_b references ref_a in Referenced Image Sequence and Source Image Sequence). Default root `UIDGenerator.defaultRoot` = 1.2.826.0.1.3680043.10.511.4 (DICOMKit's own root, 28 chars; generated UIDs ≤ 54 chars, PS3.5 9.1 valid). `Scripts/diff_cli.py --tool dicom-uid`: 11 checks ok, 0 FAIL (21 options with the new `--uuid`).

**Input contract**

| Option | DICOM concept | 2026a reference | Allowed per standard | Code accepts | Default (std) | Default (code) | Verdict |
|---|---|---|---|---|---|---|---|
| `generate -c, --count` | number of UIDs | — | — | 1-1000 | — | 1 | plumbing (help no longer prints the default twice) |
| `generate -t, --type` | DICOMKit arc .1/.2/.3 under the root | PS3.5 9.1 (no component semantics) | — | study, series, instance, sop, generic | — | generic | match (sop alias now in help) |
| `generate -r, --root` | UID root | PS3.5 9.1, 9.2.2 | registered root; numeric comps, no leading zero; root + suffix ≤ 64 | any string | org root | 1.2.826.0.1.3680043.10.511.4 | wrong → fixed: malformed root crashed (exit 133); root > 38/40 chars returned the same UID for every `--count` |
| `generate --uuid` | UUID derived UID | PS3.5 B.2 | `2.25.` + decimal UUID (≤ 39 digits) | flag | — | off | missing → added |
| `generate --json` | output | — | — | flag | — | off | plumbing |
| `validate <uids>` | UID syntax | PS3.5 9.1 | ≤ 64, numeric comps, no leading zero | engine rules | — | — | match (+1 extra engine rule "at least 2 components", D133) |
| `validate --file` | UI elements of a file | PS3.5 9.1; PS3.6 VR UI | all UI elements | top-level only | — | — | wrong (engine, D133) |
| `validate --check-registry` | Table A-1 name | PS3.6 Table A-1 | — | flag | — | off | match |
| `validate --json` | output | — | — | flag | — | off | plumbing |
| `lookup <uid>` | name, UID Type | PS3.6 Table A-1 | 465 rows | UIDDictionary | — | — | names match 465/465; Type labels wrong for 21 (engine, D134) |
| `lookup --list-all` | registry listing | PS3.6 Table A-1 | 465 | 467 (2 unregistered by decision) | — | — | match |
| `lookup --type` | UID Type filter | PS3.6 Table A-1 "UID Type" (12 values) | 12 | was transfer-syntax, sop-class | — | — | missing → fixed (11 values; DICOM UIDs as a Coding Scheme folded into coding-scheme by UIDType) |
| `lookup --search` | text search | — | — | string | — | — | plumbing |
| `lookup --json` | output | — | — | flag | — | off | plumbing |
| `regenerate <inputs>` | UIDs replaced | PS3.15 Table E.1-1 (U); PS3.10 Table 7.1-1 (0002,0003) | U rows incl. nested references; (0002,0003) = SOP Instance UID | every top-level UI value not in Table A-1 | — | — | wrong (engine, D135/2/3) — help/README now state the scope |
| `regenerate -o, --output` | output | — | — | path | — | in place | plumbing |
| `regenerate -r, --root` | UID root | PS3.5 9.1, 9.2.2 | as generate | any string | — | default root | wrong → fixed |
| `regenerate --maintain-relationships` | same old → same new | PS3.15 Table E.1-1 (action U) | — | flag (forced for > 1 file) | — | off | match (top-level only, D135) |
| `regenerate --export-map` | mapping JSON | — | — | path | — | — | plumbing |
| `regenerate -v, --verbose` | output | — | — | flag | — | off | plumbing |
| `regenerate --dry-run` | preview | — | — | flag | — | off | plumbing |

**Output contract**

| Output | Standard | Verdict |
|---|---|---|
| `UID: / Name: / Type:` and listing `uid  name  (type)`; JSON `uid name type` | PS3.6 Table A-1 UID Value / UID Name / UID Type | names match 465/465; type text: 444 match; "Well-Known UID" ×19 ≠ "Well-known SOP Instance", "Application Context" ×1 ≠ "Application Context Name", "Coding Scheme" ×1 for "DICOM UIDs as a Coding Scheme" (D134, P-UID-TYPE) |
| validate `✅/❌ uid`, `- reason`; JSON `uid valid errors registryName` | PS3.5 9.1 | match; reasons don't cite 9.1 (D133) |
| mapping JSON `oldUID newUID tagName tagHex`; `tagName` = PS3.6 keyword for 5 tags (SOPInstanceUID, SOPClassUID, StudyInstanceUID, SeriesInstanceUID, InstanceCreatorUID), else `(gggg,eeee)` | PS3.6 Table 6-1 keywords | match (5/5) |
| "UID not found in DICOM registry (not a standard Transfer Syntax or SOP Class UID)" | registry is all of Table A-1 | wrong text (engine, D136) |
| unknown `--type`: now lists the 11 Table A-1 values | PS3.6 Table A-1 | fixed |
| `--root` errors name the PS3.5 9.1 rule | PS3.5 9.1 | new |
| Exit codes 0; 1 invalid UID / not found / unknown filter; 64 usage (was 133 crash on a bad root) | — | plumbing (fixed crash) |

Counts (21 rows): matched 5, wrong 5 (2 fixed, 3 deferred), missing 2 (fixed), extra 1 (engine rule inside a matched row), plumbing 9.

Changed: `Sources/dicom-uid/UIDOptions.swift` (new: `UIDRootRule`, `UUIDDerivedUID`, `LookupTypeFilter`), `main.swift` (root validation in `generate`/`regenerate` `validate()`, `--uuid`, `--type` filters, help text), `README.md`, new test target `dicom-uidTests` (5 tests), CHANGELOG bullet.

Tests: `swift test --filter UIDOptionsTests` 5/5 pass (incl. 2^128-1 → 39-digit 2.25 UID, RFC 4122 example UUID, 20 distinct UIDs on the longest allowed root); `check_nema_markers.py Sources/dicom-uid` exit 0.

Deferred:
| ID | Module | file:line | Problem | Ref | Severity |
|---|---|---|---|---|---|
| D135 | DICOMKit | `Sources/DICOMKit/UIDManagement/UIDManager.swift:213` (`regenerateData`), `:289` (preview) | walks `dataSet.allElements` (top level only): Referenced SOP Instance UID (0008,1155) in Referenced / Source Image Sequence kept the OLD UID after regenerating both files → references dangle; same for (3006,0024) etc. | PS3.15 Table E.1-1 (0008,1155) U, (3006,0024) U | High |
| D137 | DICOMKit | `UIDManager.swift:251-254` | `DICOMFile.create(dataSet:sopClassUID:)` without `sopInstanceUID:` writes a fresh Media Storage SOP Instance UID (0002,0003) ≠ the new SOP Instance UID (fixture: …511.4.3.1790835791361393… vs …511.4.1790835791360376…) | PS3.10 Table 7.1-1 (0002,0003) "Uniquely identifies the SOP Instance associated with the Data Set"; PS3.15 E.1-1 U | High |
| D138 | DICOMKit | `UIDManager.swift:219-222` | criterion "value not in Table A-1" also replaces UIDs that are not instance identifiers: Coding Scheme UID (0008,010C) 2.16.840.1.113883.6.96 was replaced in the fixture; also Context Group Extension Creator UID, Mapping Resource UID, private SOP Class UIDs, Referenced SOP Class UID values not in A-1 (37 UI attributes not in E.1-1) | PS3.15 Table E.1-1 (U set) | Medium |
| D139 | DICOMCore | `Sources/DICOMCore/UIDGenerator.swift:84-88, 113-116, 75-81` | force-unwrap crash on a malformed root; truncation to 64 cuts the unique suffix (identical UIDs). CLI guards now | PS3.5 9.1, 9.2.2 | Medium |
| D134 | DICOMKit | `UIDManager.swift:317-330` (`uidTypeDescription`) | "Well-Known UID" / "Application Context" / folded "DICOM UIDs as a Coding Scheme" differ from Table A-1 UID Type (21 UIDs) | PS3.6 Table A-1 | Low (JSON value change → P-UID-TYPE) |
| D136 | DICOMKit | `UIDManager.swift:407-413` (`UIDConsole.lookupNotFoundLine`, `unknownTypeFilterLine`) | not-found text says "Transfer Syntax or SOP Class"; filter list has 2 values (CLI no longer uses it; Studio does) | PS3.6 Table A-1 | Low |
| D133 | DICOMKit | `UIDManager.swift:137-140, 155-176` | "Must have at least 2 components" is not a PS3.5 9.1 rule; messages don't cite 9.1; `validateFileUIDs` checks top-level elements only | PS3.5 9.1 | Low |

P-items: **P-UID-TYPE** — print the PS3.6 Table A-1 UID Type text ("Well-known SOP Instance", "Application Context Name", "DICOM UIDs as a Coding Scheme") in lookup output and the JSON `type` value (shared `UIDManager.uidTypeDescription`, also DICOMStudio).

Markers: `main.swift` `// NEMA-verified: 2026a, checked 2026-10-01 — help and checks cite PS3.5 2026a 9.1, 9.2.2 and B.2; --root is validated (UIDRootRule) and the default root is UIDGenerator.defaultRoot; lookup prints the PS3.6 2026a Table A-1 names (465 of 465 match, 2 unregistered Fragmentable HEVC entries by decision) and --type filters every Table A-1 UID Type (UIDOptions.swift); regenerate replaces top-level UI values that are not Table A-1 UIDs (compared with PS3.15 Table E.1-1: 53 UI rows, action U except Annotation Group UID D; sequence items are not remapped, deferred)`; `UIDOptions.swift` `// NEMA-verified: 2026a, checked 2026-10-01 — --root is checked against PS3.5 2026a 9.1 (…) and must leave room for the generated suffix; --uuid builds the UUID derived UID of PS3.5 B.2 (…); lookup --type covers all 12 UID Type values of PS3.6 2026a Table A-1 (465 rows dumped by script; …)`.

### dicom-validate (G2) — commit `606ef6d`

Compared: the tool's own output, run at `--level 4 --detailed` on 10 pydicom fixtures (one near-empty instance per supported IOD: CT, MR, CR, US, SC, GSPS, PCPS, Comprehensive SR, KOS; plus `vr_limits.dcm` with LO 70, SH 20, CS 20/lowercase, DS 19, IS 13, PN 70, 4 PN groups, bad DA/TM/UI). Every "Missing Type T attribute N [PS3.3 S Title (Table L); PS3.5 7.4.x]" line was parsed and checked by script (`scratch/g2/check_validate_out.py`) against PS3.3 2026a: section S exists and its title contains the printed module name, Table L is the module's table or a macro it includes (followed recursively), N is a row of L (or of a table L includes) with Type T, and 7.4.x is the PS3.5 7.4 subsection for Type T. 81 distinct messages: 79 match, 2 wrong. IOD prefixes vs PS3.6 Table A-1 names: 3 match, 6 not A-1 names. VR forms printed vs PS3.5 2026a Table 6.2-1 (dumped by script): DA "YYYYMMDD" and TM "HHMMSS.FFFFFF" match; UI 64 (not printed, enforced) matches; no maximum-length or repertoire check exists for the other VRs, and no VM check (none reported on `vr_limits.dcm`). `--iod` values vs Table A-1 keywords. `Scripts/diff_cli.py --tool dicom-validate`: 11 checks ok, 0 FAIL (7 UID literals in IODOption match Table A-1).

**Input contract**

| Option | DICOM concept | 2026a reference | Allowed per standard | Code accepts | Default (std) | Default (code) | Verdict |
|---|---|---|---|---|---|---|---|
| `<input-path>` | Part 10 file / directory | PS3.10 7.1 | — | path | — | — | plumbing |
| `--level` | validation depth | PS3.10 Table 7.1-1; PS3.5 Table 6.2-1, 9.1; PS3.3 IOD/module tables; PS3.5 7.4.1-7.4.4 | — | 1-5 | — | 3 | wrong → fixed (help said "2=Tags/VR/VM"; level 2 checks VR vs dictionary and DA/TM/UI forms only) |
| `--iod` | IOD / SOP Class | PS3.6 Table A-1 keywords; PS3.3 Annex A | keyword or UID | engine names: ct/mr/cr/ultrasound/sc/gsps/sr/kos, `CRImageStorage`, `USImageStorage`, `GrayscaleSoftcopyPresentationState`, … | — | from (0008,0016) | wrong → fixed: Table A-1 keywords `ComputedRadiographyImageStorage`, `UltrasoundImageStorage`, `GrayscaleSoftcopyPresentationStateStorage`, `PseudoColorSoftcopyPresentationStateStorage`, SR/KOS keywords and UIDs reported "IOD validation not implemented"; now mapped (IODOption), plus `US` |
| `--detailed` | output | — | — | flag | — | off | plumbing |
| `--recursive` | directory walk | — | — | flag | — | off | plumbing |
| `-f, --format` | output | — | — | text, json | — | text | plumbing |
| `-o, --output` | report path | — | — | path | — | stdout | plumbing |
| `--strict` | warnings → exit 2 | — | — | flag | — | off | plumbing |
| `--force` | no DICM prefix | PS3.10 7.1 | — | flag | — | off | plumbing |

**Output contract**

| Output | Standard | Verdict |
|---|---|---|
| `<IOD>: Missing Type 1/1C/2/2C attribute <name> [PS3.3 <sect> <module> (Table <x>); PS3.5 7.4.n]` | PS3.3 2026a module/macro tables; PS3.5 7.4.1-7.4.4 | 81 distinct: 79 match; 2 wrong (D140, -3) |
| IOD prefixes `CT Image Storage`, `MR Image Storage`, `Secondary Capture Image Storage` / `CR Image Storage`, `US Image Storage`, `GSPS`, `Pseudo-Color PS`, `Key Object Selection Document`, `Structured Report` | PS3.6 Table A-1 names | 3 match, 6 wrong (D141) |
| `Invalid date format … (expected YYYYMMDD)`, `Invalid time format … (expected HHMMSS.FFFFFF)`, UID ≤ 64 | PS3.5 Table 6.2-1 DA, TM, UI | match 3 |
| max lengths / repertoires AE 16, AS 4, CS 16, DS 16, DT 26, IS 12, LO 64, LT 10240, PN 64 per group, SH 16, ST 1024, TM 14; VM | PS3.5 Table 6.2-1; PS3.6 Table 6-1 VM | missing (engine, D142) |
| `Code String should be uppercase` (warning); `Person Name has more than 3 components` | PS3.5 Table 6.2-1 CS repertoire; 6.2.1 component groups | wrong wording/level (D142) |
| `Missing required File Meta Information element: …` (6 Type 1 elements) | PS3.10 Table 7.1-1 | match (engine-verified 2026-09-29) |
| JSON keys `totalFiles validFiles invalidFiles totalErrors totalWarnings files[filePath isValid errorCount warningCount errors[message tag] warnings[…]]`; tag `(gggg,eeee)` | tool-defined; PS3.5 7.1 tag notation | extra/tool-defined; tag notation match |
| Exit 0 valid; 1 errors; 2 warnings with `--strict`; 64 usage | — | plumbing |

Counts (12 rows): matched 0 rows fully (3 value forms match inside the VR row), wrong 4 (2 fixed, 2 deferred), missing 1 (deferred), extra 0, plumbing 7. Value-level: citations 79/81, IOD labels 3/9, VR forms 3 matched / 11 VR limits + VM missing.

Changed: `Sources/dicom-validate/IODOption.swift` (new), `DICOMValidate.swift` (`--iod` mapped through IODOption, `--level` / `--iod` help), `README.md` (Table A-1 IOD names, Pseudo-Color and KOS listed, no VM / deprecated-tag claims, level descriptions), new test target `dicom-validateTests` (4 tests), CHANGELOG bullet.

Tests: `swift test --filter IODOptionTests` 4/4 pass; `check_nema_markers.py Sources/dicom-validate` exit 0.

Deferred:
| ID | Module | file:line | Problem | Ref | Severity |
|---|---|---|---|---|---|
| D142 | DICOMKit | `Sources/DICOMKit/Validation/DICOMValidator.swift:148-240` | level 2 checks no VR maximum length / repertoire except DA, TM, UI and CS lowercase (warning only, though outside the CS repertoire), and no VM: LO 70, SH 20, CS 20, DS 19, IS 13, PN 70 all pass; "Person Name has more than 3 components" means component groups; DA/TM errors reported twice (validateValueFormat + validateDatesAndTimes) | PS3.5 Table 6.2-1, 6.2.1; PS3.6 Table 6-1 VM | Medium |
| D140 | DICOMKit | `DICOMValidator.swift:825` | GSPS/PCPS: Content Creator's Name (0070,0084) required as Type 2 "[C.11.10 … (Table 10-12)]"; in 2026a it is Type 3 in Content Creator Macro Table 10.9.3-1, included by Table 10-12 → false error on every presentation state without it | PS3.3 Tables 10-12, 10.9.3-1, C.11.10-1 | Medium |
| D143 | DICOMKit | `DICOMValidator.swift:894` | KOS/SR root Concept Name Code Sequence printed as "Type 1 … (Table C.17-5, Root Content Item)"; Table C.17-5 gives Type 1C (condition) | PS3.3 Table C.17-5; PS3.5 7.4.2 | Low |
| D141 | DICOMKit | `DICOMValidator.swift` IOD validators' `iod` names | message prefixes "CR Image Storage", "US Image Storage", "GSPS", "Pseudo-Color PS", "Key Object Selection Document", "Structured Report" are not PS3.6 Table A-1 names | PS3.6 Table A-1 | Low |

P-items: none.

Marker: `DICOMValidate.swift` `// NEMA-verified: 2026a, checked 2026-10-01 — printed Type / PS3.3 module-table / PS3.5 7.4.1-7.4.4 citations run on 10 fixtures and diffed against PS3.3 2026a (81 distinct messages: 79 match, 2 wrong in the engine, deferred); --iod takes PS3.6 Table A-1 keywords and UIDs (IODOption.swift); --level help states what level 2 checks (PS3.5 Table 6.2-1 DA, TM, UI forms; no length or VM checks, deferred)`; `IODOption.swift` `// NEMA-verified: 2026a, checked 2026-10-01 — --iod accepts the PS3.6 2026a Table A-1 keyword or UID of the 7 image / presentation-state SOP Classes and every SR SOP Class (DICOMCore.SRDocumentType) that DICOMValidator implements; the 7 UID literals below match Table A-1 (diff_cli.py uid check); the engine's own short names stay accepted`.

Scripts for the orchestrator (candidates for Scripts/diff_cli.py): `scratch/g2/check_validate_out.py` (output citation diff against PS3.3, follows macro includes), `scratch/g2/check_uid_lookup.py` (lookup output vs Table A-1 names/types), `scratch/g2/check_uid_regen.py` (UI attributes vs E.1-1), fixtures `scratch/g2/mkfx.py`.

### dicom-dump (G2 File and media) — verified 2026-10-01

Files: `Sources/dicom-dump/main.swift` (B2). Engine: `DICOMKit/HexDumper.swift` (deferred; its VR lists already carry a 2026a marker for Table 6.2-1 / 7.1-1).

Evidence (script): `--annotate --verbose` of the CT fixture vs PS3.6 2026a Tables 6-1/7-1: (keyword, VR) 31/31 match; `--tag` header name/VR per PS3.6; layout per PS3.10 Table 7.1-1 (File Preamble 128 bytes, "DICM", group 0002). Observed: `--offset 0x84 --length 300 --annotate` printed no annotations and `--highlight` found nothing (D144); `--length=-5` traps; `--bytes-per-line 0` never advances.

#### Input contract
| Option | DICOM concept | 2026a reference | Standard | Code accepts | Default std / code | Verdict |
|---|---|---|---|---|---|---|
| `<file-path>` | DICOM File | PS3.10 7.1 | — | path | — | plumbing |
| `--tag` | Data Element Tag | PS3.5 7.1.1; PS3.6 Tables 6-1/7-1 | (gggg,eeee), keyword | (gggg,eeee) / gggg,eeee / ggggeeee + keyword exact (added) | — | match |
| `--highlight` | Data Element Tag | same | same | same | — | match |
| `--offset` | byte offset | — | — | decimal / 0x hex | 0 | plumbing |
| `--length` | bytes | — | — | ≥ 0 (now checked) | 65,536 cap | plumbing (fixed) |
| `--bytes-per-line` | line width | — | — | ≥ 1 (now checked) | 16 | plumbing (fixed) |
| `--no-color` | — | — | — | flag | off | plumbing |
| `--annotate` | tag / VR / length / keyword | PS3.5 7.1.2, Table 6.2-1; PS3.6 | — | flag | off (README said on; fixed) | match |
| `--force` | file without "DICM" | PS3.10 7.1 | — | flag | off | plumbing |
| `--verbose` | VR, Value Length (undefined = FFFFFFFFH) | PS3.5 7.1.1, 7.1.2 | — | `VR=XX Len=N` / `Len=undefined` | off | match |

#### Output contract
| Output | 2026a reference | Code | Verdict |
|---|---|---|---|
| `← (gggg,eeee) [VR=XX Len=N] Keyword` | PS3.6 Tables 6-1/7-1; PS3.5 6.2-1 | 31/31 | match |
| `Tag: (gggg,eeee)  Name  VR=XX  Length=N` / `Value:` | PS3.6; PS3.5 7.1 | name + VR form value | match |
| Item / Item Delimitation Item / Sequence Delimitation Item | PS3.5 7.5; PS3.6 (FFFE,E000/E00D/E0DD) | not labelled | missing (engine, D145) |
| Annotations with `--offset` > 0 | PS3.10 7.1 | lost / misplaced | wrong (engine, D144) |
| Private Creator name | PS3.5 7.8.1 | "Unknown" / no keyword | missing (engine, D146) |
| Exit codes | — | 0 ok; 1 error (file/tag not found, bad tag, range); 64 usage | plumbing |

Counts: matched 4, wrong 0, missing 0, extra 0, plumbing 6 (input; 2 plumbing bugs fixed); output matched 2, wrong 1, missing 2 (all deferred).

README fixed: `--annotate` default (off), keyword form, sequence example (`--annotate --verbose`, FFFE items not labelled), offset limitation, element-walk description (34 VR codes of Table 6.2-1, 4-byte-length VRs of Table 7.1-1).
Tests: new target `dicom-dumpTests` (Tests/dicom-dumpTests/DumpTagArgumentTests.swift: hex forms, keywords exact, range checks).
Marker: `// NEMA-verified: 2026a, checked 2026-10-01 — --tag/--highlight accept (gggg,eeee) or a PS3.6 2026a Table 6-1/7-1 keyword (exact); … 31/31; layout follows PS3.10 7.1 …`.
P-items: none.

#### Deferred findings (G2 dump/info/tags; orchestrator numbers them)
| ID | Module | file:line | Problem | Standard | Severity |
|---|---|---|---|---|---|
| D144 | DICOMKit | Sources/DICOMKit/HexDumper.swift:186 | `buildTagPositionMap` always skips 132 bytes when the data is longer than 132, without checking "DICM" at 128 and regardless of `startOffset`: with `--offset` > 0 (and the Workshop equivalent) `--annotate` / `--highlight` are lost or misplaced; a file without preamble (`--force`) is misannotated | PS3.10 7.1, Table 7.1-1 | medium |
| D145 | DICOMKit | Sources/DICOMKit/HexDumper.swift:203-207 | (FFFE,xxxx) is stepped over with no position entry, so Item / Item Delimitation Item / Sequence Delimitation Item are never annotated; defined-length Items are skipped whole (their elements are not annotated) while undefined-length Items are descended | PS3.5 7.5; PS3.6 Table 6-1 | low |
| D146 | DICOMKit | Sources/DICOMKit/MetadataPresenter.swift:117,191,214; HexDumper.swift:44; TagEditing/TagEditor.swift:147 | Private Creator Data Elements (gggg,0010-00FF) print "Unknown" / no name | PS3.5 7.8.1 | low |
| D147 | DICOMKit | Sources/DICOMKit/MetadataPresenter.swift:76-92, 142-156 | `--statistics` prints the Transfer Syntax UID and SOP Class UID without their Table A-1 names (UIDDictionary has them) | PS3.6 Table A-1 | low |
| D148 | DICOMKit | Sources/DICOMKit/MetadataPresenter.swift:108-112, 181-185, 250-253 | the tag filter matches the PS3.6 name or tag text but never the keyword (DICOMStudio's Workshop still affected; the CLI now adds the keyword's tag) | PS3.6 Table 6-1 keywords | medium |
| D149 | DICOMKit | Sources/DICOMKit/MetadataPresenter.swift:195-197 | JSON `value` is omitted for binary VRs (US, UL, FL, FD, AT, …) though text/CSV render them | PS3.5 Table 6.2-1 | low |
| D150 | DICOMKit | Sources/DICOMKit/TagEditing/TagEditor.swift:124-139 (sets), 83-95 / 110-121 | `applyChanges` writes `setString` under the existing-or-first dictionary VR for any VR (binary VRs get text bytes: Rows=512 → US "512 "), applies no Table 6.2-1 limits, and puts group 0002 into the Data Set (unreadable file); deletes/copies of group 0002 are not refused. The CLI now runs `--set` and the refusals itself (Sources/dicom-tags/TagEditRules.swift); DICOMStudio's Workshop still uses the engine — move these rules into TagEditor | PS3.5 Table 6.2-1; PS3.10 7.1; PS3.6 Table 6-1 | high |

Commit: e27aa9f. Tests: `swift test --filter dicom_dumpTests` 3/3 passed.

### dicom-info (G2 File and media) — verified 2026-10-01

Files: `Sources/dicom-info/main.swift` (B2). Engine: `DICOMKit/MetadataPresenter.swift` (deferred).

Evidence (script): dicom-info text output of the CT fixture vs PS3.6 2026a Tables 6-1/7-1: (tag, name, VR) 31/31 match (Pixel Data OW within "OB or OW"). Help example `--tag PatientName --tag StudyDate` selected nothing (the presenter matches the PS3.6 name "Patient's Name" or tag text, not the keyword).

#### Input contract
| Option | DICOM concept | 2026a reference | Standard | Code accepts | Default std / code | Verdict |
|---|---|---|---|---|---|---|
| `<file-path>` | DICOM File | PS3.10 7.1 | — | path | — | plumbing |
| `-f/--format` | output format | — (JSON is not PS3.18 F and does not claim it) | — | text, json, csv | — / text | plumbing |
| `-t/--tag` | Attribute selection | PS3.6 Tables 6-1/7-1 | keyword, name, tag | name substring, tag text, + keyword exact (added) | — | wrong → fixed |
| `--show-private` | Private Data Elements | PS3.5 7.8, 7.8.1 | odd groups | odd groups | off | match |
| `--statistics` | Transfer Syntax UID / SOP Class UID / Modality | PS3.10 Table 7.1-1; PS3.6 Table A-1 | UID + name | UID only | off | missing (engine, D147) |
| `--force` | file without preamble/"DICM" | PS3.10 7.1 | — | flag | off | plumbing |

#### Output contract
| Output | 2026a reference | Code | Verdict |
|---|---|---|---|
| `=== File Meta Information ===` / `=== Main Data Set ===` | PS3.10 7.1 | as shown | match |
| `(gggg,eeee) Name VR=XX value` | PS3.6 Tables 6-1/7-1 | 31/31 | match |
| DA/TM/DT values | PS3.5 Table 6.2-1 | stored VR form (20200101, 120000) | match |
| CSV `Tag,Name,VR,Value` | — | — | plumbing |
| JSON `fileMetaInformation`, `dataSet`, `tag`, `name`, `vr`, `value`, `statistics.{transferSyntax,sopClass,modality,j2k_*}` | not PS3.18 F (not claimed) | `value` absent for binary VRs | plumbing; D149 |
| Private Creator name | PS3.5 7.8.1 | "Unknown" | missing (engine, D146) |
| Exit codes | — | 0 ok; 1 not readable as DICOM; 64 file not found / bad option | plumbing |

Counts: matched 1, wrong 1 (fixed), missing 1 (deferred), extra 0, plumbing 3 (input); output matched 3, missing 1, plumbing 3.

Tests: new target `dicom-infoTests` (Tests/dicom-infoTests/InfoTagFilterTests.swift: keyword → tag term; help example selects Study Date and Patient's Name through the shared presenter).
Marker: `// NEMA-verified: 2026a, checked 2026-10-01 — --tag accepts PS3.6 2026a Table 6-1/7-1 keywords exactly …; printed (tag, name, VR) of a CT fixture match PS3.6 Table 6-1/7-1 31/31; …`.
P-items: none.

Commit: ee2ce1f. Tests: `swift test --filter dicom_infoTests` 2/2 passed.

### dicom-tags (G2 File and media) — verified 2026-10-01

Files: `Sources/dicom-tags/main.swift` (B2), `Sources/dicom-tags/TagEditRules.swift` (new, A). Engine: `DICOMKit/TagEditing/TagEditor.swift` (deferred).

Evidence (script): PS3.5 2026a Table 6.2-1 dumped (34 VRs; Length-of-Value and Character-Repertoire columns) → `g2/vr62.tsv`; PS3.6 Tables 6-1 (5,263 rows) / 7-1 (22 rows); PS3.10 7.1 sentence "Data Elements with a group of 0002 shall not be used in Data Sets other than within the File Meta Information"; PS3.5 7.5 (Item names), 7.8 / 7.8.1 (unused groups; Private Creator LO, VM 1, default repertoire), 6.2.1 (three PN component groups). README keyword table: 17/17 (keyword, tag, VR) match PS3.6 Table 6-1. `--list-modalities` vs PS3.3 C.7.3.1.1.1: 79/79 current Defined Terms, 18 retired not listed (as the listing says); display names are DICOMKit's own (9 differ from the standard's meaning text; documented in Modality.swift).

Observed before the fix (CT fixture): `--set Rows=512` wrote US with bytes "512 " (value read back 12597\8242); `--set TransferSyntaxUID=…` put (0002,0010) in the Data Set and the file read back with an empty Data Set; `--set StudyDate=2020-01-01` wrote a 10-byte DA; a 70-character PN was written; `--delete 0002,0010` said "not present, skipped".

#### Input contract
| Option | DICOM concept | 2026a reference | Standard | Code accepts | Default std / code | Verdict |
|---|---|---|---|---|---|---|
| `<input>` | DICOM File | PS3.10 7.1 | — | path | — | plumbing |
| `--list-modalities` | Modality (0008,0060) Defined Terms | PS3.3 C.7.3.1.1.1 | 79 current + 18 retired | lists 79 current | — | match |
| `-o/--output` | output path | — | — | path | — / overwrite input | plumbing |
| `--set` | Attribute value | PS3.6 Table 6-1; PS3.5 Table 6.2-1; PS3.10 7.1; PS3.5 7.8.1 | keyword exact or (gggg,eeee); dictionary VR; VR value limits | Keyword=Value / GGGG,EEEE=Value; dictionary VR; length/repertoire/IS range/PN groups checked; US/SS/UL/SL/FL/FD encoded; AT/O*/SQ/SV/UV/UN refused; group 0002, FFFE, 0001/3/5/7/FFFF refused | — | wrong → fixed |
| `--delete` | remove Attribute | PS3.6 keywords; PS3.10 7.1 | Data Set has no group 0002 | keyword / GGGG,EEEE; group 0002 refused | — | wrong → fixed |
| `--delete-private` | Private Data Elements | PS3.5 7.8, 7.8.1 | odd groups | odd groups | off / off | match |
| `--copy-from` | source file | PS3.10 7.1 | — | path | — | plumbing |
| `--tags` | Attributes to copy | PS3.6 keywords; PS3.10 7.1 | — | comma list; group 0002 refused | — / all source tags | wrong → fixed |
| `-v/--verbose`, `--dry-run` | — | — | — | flags | off | plumbing |

#### Output contract
| Output | 2026a reference | Code | Verdict |
|---|---|---|---|
| `SET/DELETE/COPY (gggg,eeee) Name …`, `N change(s) applied.`, `Dry run complete — no files modified.`, `Output written to: …` | PS3.6 Table 6-1 names | shared TagEditConsole + same label for --set | match |
| Private Creator label | PS3.5 7.8.1 | bare `(0009,0010)` | missing (engine, D146) |
| Written VR | PS3.6 Table 6-1 VR | dictionary VR (existing if one of the alternatives) | match (was existing-or-first) |
| Exit codes | — | 0 ok; 1 refused edit / file not found / no operation; 64 missing input | plumbing (README updated) |

Counts: matched 3, wrong 3 (fixed), missing 0, extra 0, plumbing 6 (input); output matched 3, missing 1 (deferred).

Tests: new target `dicom-tagsTests` (Tests/dicom-tagsTests/TagEditRulesTests.swift, 13 tests: Table 6.2-1 limits and repertoires pinned, refusals, writeVR, Rows=512 → US 00 02, order/skip lines, dry-run, Private Creator, keyword exactness, help).
Marker: `// NEMA-verified: 2026a, checked 2026-10-01 — tag specifiers resolve PS3.6 2026a Table 6-1/7-1 keywords exactly …` (main.swift) and `… Value length / character-repertoire limits of the 34 VRs dumped from PS3.5 2026a Table 6.2-1 …` (TagEditRules.swift).

Deferred: D150 (below). P-items: none.

Commit: b091aa5. Tests: `swift test --filter dicom_tagsTests` 13/13 passed.

Note for the orchestrator: `swift test --filter dicom-xxxTests` (hyphen) matches no test under the Swift Build backend (each target is its own .xctest bundle; test ids use the module name `dicom_xxxTests`) — use the underscore form.

### dicom-diff (G2) — verified 2026-10-01

Mostly plumbing: the comparison engine (`DICOMKit/Comparison/DICOMComparer.swift`, `ComparisonReport.swift`) was
verified in the DICOMKit pass (2026-09-29); the CLI adds option parsing and help. Evidence:
`<scratch>/g2sm_checks.py` (PS3.6 Table 6-1 names/keywords in help and README: all match),
`<scratch>/g2sm_grep.py` (PS3.5 7.1 / 7.8.1 private-group text, PS3.10 7.1 title), `diff_cli.py --tool dicom-diff` (all ok).

**Input contract**

| Option | DICOM concept | 2026a reference | Allowed (standard) | Code accepts | Default std / code | Verdict |
|---|---|---|---|---|---|---|
| `<file1>` `<file2>` | PS3.10 files | PS3.10 7.1 | — | paths; group 0002 not compared | — | plumbing |
| `--format` | report rendering | — | — | text, json, summary | — / text | plumbing |
| `--ignore-tag` | Data Element Tag or keyword | PS3.6 Table 6-1 (Tag, Keyword); PS3.5 7.1.1 | `(gggg,eeee)`, keyword | was `gggg,eeee` + keyword; now also `(gggg,eeee)` (as the report prints it) and `ggggeeee` | — | missing → fixed (additive) |
| `--ignore-private` | Private Data Elements | PS3.5 7.1 (odd group, not 0001/0003/0005/0007/FFFF), 7.8.1 | — | odd group, top level only | — / off | match (D151, D152) |
| `--compare-pixels` | Pixel Data (7FE0,0010) | PS3.6 Table 6-1; PS3.5 8.1.1 / 8.2 | — | byte-wise | — / off | match (help reworded) |
| `--tolerance` | per-byte difference tolerance | PS3.5 8.1.1 | — | Double | — / 0 | wrong help → fixed ("pixel value" → bytes, not sample values; D153) |
| `--quick` | metadata only | — | — | flag | off | plumbing |
| `--show-identical` | list identical elements | — | — | flag | off | plumbing |
| `--verbose` | — | — | — | flag | off | plumbing |

matched 2, wrong 1, missing 1, extra 0, plumbing 6

**Output contract**

| Output | Standard | Verdict |
|---|---|---|
| text `[(gggg,eeee)] <Name>: value` | PS3.6 Table 6-1 Tag notation + Name (DataElementDictionary, verified) | match |
| `<Binary data, N bytes>` for OB/OD/OF/OL/OV/OW/UN | PS3.5 Table 6.2-1 (D5, DICOMKit pass) | match |
| `<Sequence with N items>` | SQ, PS3.5 7.5 | match |
| `Pixel Data: IDENTICAL/DIFFERENT` | PS3.6 name Pixel Data | match |
| `Max difference` / `Different pixels: N / M` | counts bytes, not samples | wrong — engine, D153 |
| JSON `files.file1/file2`, `summary.totalTags/differences/hasDifferences`, `onlyInFile1/2[].tag/value`, `modified[].tag/tagName/value1/value2`, `pixelData.*` | tool keys, not PS3.18 Annex F; `tag` = `(gggg,eeee)`, `tagName` = PS3.6 Name ("Unknown" when unlisted) | plumbing / match |
| exit 0 identical, 1 different **or unreadable file**, 64 usage | — | plumbing (P-DIFF-1) |

**Changes** (`Sources/dicom-diff/main.swift`, `README.md`): `--ignore-tag` parser (now `static func parseTag`) also
accepts `(gggg,eeee)` and `ggggeeee` (old `gggg,eeee` incl. short hex and keywords kept); help for `--ignore-tag`,
`--ignore-private`, `--compare-pixels`, `--tolerance`, `--quick` names the PS3.5/PS3.6 concepts; README documents the
tag forms, byte-wise tolerance, group 0002 not compared, top-level-only private filtering, exit 1 for unreadable files.
Test target `dicom-diffTests` (`Tests/dicom-diffTests/IgnoreTagParsingTests.swift`, 4 tests).

**P-items**
- P-DIFF-1: exit 1 means both "files differ" and "a file could not be read"; propose exit 2 for errors (as diff/cmp). Not implemented (exit-code contract change).

**Deferred findings**

| ID | Module | file:line | Problem | Standard | Severity |
|---|---|---|---|---|---|
| D151 | DICOMCore | Sources/DICOMCore/Tag.swift:29 | `isPrivate` = any odd group; PS3.5 7.1 excludes 0001, 0003, 0005, 0007, FFFF from Private Data Elements (7.8.1: those groups shall not be used) | PS3.5 2026a 7.1, 7.8.1 | low |
| D153 | DICOMKit | Sources/DICOMKit/Comparison/DICOMComparer.swift:160-199; ComparisonReport.swift:56-60 | Pixel Data compared byte by byte: `--tolerance`, max/mean and "Different pixels" are per byte, not per sample (16-bit pixel cells, PS3.5 8.1.1); encapsulated data compared as compressed bytes (PS3.5 8.2, A.4) | PS3.5 2026a 8.1.1, 8.2 | medium |
| D152 | DICOMKit | Sources/DICOMKit/Comparison/DICOMComparer.swift:66, 141-158 | `ignorePrivate` applies only to top-level elements; private elements inside sequence items still make the parent SQ differ | PS3.5 2026a 7.8 | low |

**Marker**: `// NEMA-verified: 2026a, checked 2026-10-01 — --ignore-tag accepts the Tag notation of PS3.6 2026a Table 6-1 ((gggg,eeee), also gggg,eeee / ggggeeee; PS3.5 7.1.1) and Table 6-1 keywords; --ignore-private is the odd-group rule of PS3.5 7.1/7.8; the 10 options otherwise carry no DICOM-standard data (comparison engine verified in DICOMKit/Comparison)`

**Commit**: 2c5428c (adds the `dicom-diffTests` target to Package.swift and the CHANGELOG section "Fixed — dicom-diff, dicom-split, dicom-merge verified against DICOM 2026a").
**Tests**: `dicom-diffTests` 4/4 pass; `DICOMRoundTripTests.Diff*` pass; `diff_cli.py --tool dicom-diff` 0 wrong; `check_nema_markers.py Sources/dicom-diff` 0 without.

### dicom-split (G2) — verified 2026-10-01

The splitting engine (`DICOMKit/Splitting`, `DICOMKit/Multiframe`: SOP Class map 37 UIDs vs PS3.6 Table A-1,
concatenation per C.7.6.16, flattening per C.7.6.16) was verified in the DICOMKit pass (2026-09-29). This pass checks
the CLI surface. Evidence (by script, `<scratch>/g2sm_std.py`, `g2sm_checks.py`, `g2sm_sop.py`, `g2sm_grep.py`):
PS3.6 Table 6-1 rows for 38 attributes the options act on (Instance Number, Stack ID, In-Stack Position Number,
Temporal Position Index, Concatenation UID, In-concatenation Number, Concatenation Frame Offset Number, …);
PS3.3 section titles C.7.6.6, C.7.6.16, C.7.6.16.1.2, C.7.6.16.2.2, C.7.6.17, 7.5.1, A.70-A.72;
PS3.3 C.7.6.16.1.2 "Frames are implicitly numbered starting from 1" and Table 10-3 Referenced Frame Number
"The first Frame shall be denoted as Frame number 1"; PS3.5 8.2 / A.4 Basic Offset Table text;
SOP Class phrases in help + README: 33 exact Table A-1 names, 5 slash-abbreviated lists ("Enhanced CT / MR / PET …")
whose members are Table A-1 names; split conversions in help checked against the 13 `.convert` entries of
MultiframeSOPClassMap. `diff_cli.py --tool dicom-split`: all ok (6 defaults matched).

**Input contract**

| Option | DICOM concept | 2026a reference | Allowed / code accepts | Default std / code | Verdict |
|---|---|---|---|---|---|
| `<input>` | multi-frame file(s) | PS3.10 7.1; PS3.3 C.7.6.6 Number of Frames > 1 | path | — | plumbing |
| `--output` | output directory | — | path | . | plumbing |
| `--frames` | frames to extract | PS3.3 C.7.6.16.1.2 (1-based Frame numbers); Table 10-3 | 0-based indices `1,3,5-10` | all | wrong → help/README fixed (help said "Frame numbers", README called 0-based "the DICOM convention"); 1-based = P-SPLIT-1 |
| `--format` | output container | — | dicom, png, jpeg, tiff | dicom | plumbing |
| `--apply-window` | VOI window | PS3.3 C.11.2.1.2 | flag | off | match |
| `--window-center` | Window Center (0028,1050) | PS3.3 C.11.2.1.2 | Double | stored value | match |
| `--window-width` | Window Width (0028,1051) | PS3.3 C.11.2.1.2 | Double | stored value | match |
| `--pattern` | file naming | PS3.6 Table 6-1 (Instance Number, Stack ID, Modality, Series Number) | {number}/{number:04d} (0-based index), {instance}, {stack}, {modality}, {series} | `<base>_frame_NNNN` | match (help names the attributes) |
| `--target` | SOP Class of outputs | PS3.6 Table A-1; PS3.3 A.38, A.70-A.72 | auto, same, classic | auto | match (help/discussion now use Table A-1 names) |
| `--pixel-handling` | encapsulated frames | PS3.5 8.2, A.4; Table A-1 Explicit VR Little Endian | preserve, decode | preserve | match |
| `--private-groups` | private Sequences in functional group items | PS3.3 C.7.6.16 | flatten, keep, drop | flatten | match |
| `--instance-number` | Instance Number (0020,0013) | PS3.3 C.7.6.1; C.7.6.16.2.2 In-Stack Position Number (0020,9057) | frame (1-based Frame number), instack, original | frame | match (help names the attributes) |
| `--split-by` | series per Frame Content value | PS3.3 C.7.6.16.2.2 Stack ID (0020,9056), Temporal Position Index (0020,9128) | none, stack, temporal | none | match (help names the attributes) |
| `--new-series` | Series Instance UID (0020,000E) | PS3.3 C.7.3.1 | flag | off | match |
| `--frames-per` | Concatenation parts | PS3.3 7.5.1; C.7.6.16 (Concatenation UID, In-concatenation Number / Total Number, Concatenation Frame Offset Number, SOP Instance UID of Concatenation Source) | Int >= 1 | — | match |
| `--random-uids` | random vs derived UIDs | PS3.5 9.1 | flag | off (derived) | plumbing |
| `-r` / `-v` | — | — | flags | off | plumbing |

matched 11, wrong 1, missing 0, extra 0, plumbing 6

**Output contract**

| Output | Standard | Verdict |
|---|---|---|
| written SOP Class per source (13 conversions, 16 same-class, 3 refused) | PS3.6 Table A-1 (MultiframeSOPClassMap, DICOMKit pass) | match |
| Instance Number = 1-based Frame number (`frame`) | PS3.3 C.7.6.16.1.2 | match |
| console lines (SplitConsole: plan, skipped, "Split complete! Processed/extracted/skipped/failed") | SOP Class names per Table A-1 (DICOMKit pass) | match |
| file names `<base>_frame_NNNN.<ext>` (0-based) | — | plumbing |
| exit 0 (skips are not failures), 1 frame extraction failed, 64 usage | — | plumbing (README fixed: said 1 for "file not found", which is 64) |

**Changes** (`Sources/dicom-split/DICOMSplit.swift`, `README.md`): discussion uses Table A-1 names (CT Image Storage,
MR Image Storage, Positron Emission Tomography Image Storage, X-Ray Angiographic / X-Ray Radiofluoroscopic Image Storage,
Ultrasound (Multi-frame) Image Storage, Secondary Capture Image Storage) and "Shared and Per-Frame Functional Groups
Sequences"; states that `--frames` is 0-based (index 0 = Frame number 1); help of `--frames`, `--pattern`, `--target`,
`--pixel-handling`, `--private-groups`, `--instance-number`, `--split-by`, `--new-series` names the PS3.6 attributes;
README: "0-based is the DICOM convention" corrected, all 18 options listed, supported SOP Classes by Table A-1 name,
exit codes. Test target `dicom-splitTests` (`Tests/dicom-splitTests/SplitOptionHelpTests.swift`, 4 tests).

**P-items**
- P-SPLIT-1: `--frames` takes 0-based indices while PS3.3 C.7.6.16.1.2 / Table 10-3 number frames from 1. Proposal: accept 1-based Frame numbers (new option `--frame-numbers`, or switch `--frames` with a deprecation period; Studio Workshop must follow). Not implemented.

**Deferred findings**

| ID | Module | file:line | Problem | Standard | Severity |
|---|---|---|---|---|---|
| D154 | DICOMStudio | Sources/DICOMStudio/Components/CLIWorkshopHelpers.swift:2520 | Workshop help for dicom-split `--frames` ("Frame selection (ranges/list)") does not say the values are 0-based indices | PS3.3 2026a C.7.6.16.1.2 | low |

**Marker**: `// NEMA-verified: 2026a, checked 2026-10-01 — help names checked by script: 9 SOP Class names quoted in full and 2 abbreviated lists (Enhanced CT/MR/PET/XA/XRF, Legacy Converted Enhanced CT/MR/PET) against PS3.6 2026a Table A-1, 7 attribute names/tags (Instance Number, Stack ID, In-Stack Position Number, Temporal Position Index, Series Instance UID, Shared/Per-Frame Functional Groups Sequence) against Table 6-1; --frames is a 0-based index (Frame number 1 = index 0, PS3.3 C.7.6.16.1.2); Explicit VR Little Endian per Table A-1`

**Commits**: 00ba2a3 (split), reverted by the concurrent dicom-dump commit e27aa9f (built on a stale tree: it also dropped the `dicom-splitTests` target and the CHANGELOG bullet), re-applied in 2ef9d28 (Package.swift target + CHANGELOG bullet, with merge) and f663f84 (sources, README, test). HEAD now equals 00ba2a3 for every split file.
**Tests**: `dicom-splitTests` 4/4 pass; `SplitMergeWorkshopCLIParityTests` (against freshly built release binaries) pass; `DICOMRoundTripTests.(Split|Enhanced|SharedConsole)*` pass (1 corpus test skipped, corpus absent); `diff_cli.py --tool dicom-split` 0 wrong; markers 0 without.

### dicom-merge (G2) — verified 2026-10-01

The merge engine (`DICOMKit/Merging`, `DICOMKit/Multiframe`) was verified in the DICOMKit pass (2026-09-29/30). This
pass checks the CLI surface. Evidence by script (`<scratch>/g2sm_checks.py`, `g2sm_std.py`, `g2sm_sop.py`):
`--format` → `MergeFormat.enhancedSOPClassUID` → PS3.6 Table A-1: 10 of 10 values match UID and name (enhanced-xa /
enhanced-xrf flagged by the tokenizer only: Table A-1 names are "Enhanced XA/XRF Image Storage"; standard/auto carry
no UID); `--sort-by` raw values vs PS3.6 Table 6-1 keywords: 3 of 3 (InstanceNumber (0020,0013),
ImagePositionPatient (0020,0032), AcquisitionTime (0008,0032)); attribute names in help/README: 29 PS3.6 names,
all exact after the fix ("Samples Per Pixel" → "Samples per Pixel", "Image Position Patient" → "Image Position
(Patient)"); PS3.3 A.70-A.72, C.7.6.16, C.7.6.17 titles; PS3.5 A.4 Basic Offset Table text. `diff_cli.py --tool
dicom-merge`: all ok (5 defaults matched).

**Input contract**

| Option | DICOM concept | 2026a reference | Allowed / code accepts | Default std / code | Verdict |
|---|---|---|---|---|---|
| `<inputs>` | single-frame files | PS3.10 7.1 | paths | — | plumbing |
| `-o, --output` | output path | — | path | required | plumbing |
| `--format` | SOP Class of the merged object | PS3.6 Table A-1; PS3.3 A.38, A.70-A.72 | standard, auto, enhanced-ct/-mr/-pet/-xa/-xrf, legacy-converted-ct/-mr/-pet, sc-multiframe (Single Bit / Grayscale Byte / Grayscale Word / True Color by Bits Allocated, Samples per Pixel), us-multiframe | standard | match (discussion now lists the Table A-1 class per value) |
| `--pixel-handling` | encapsulated frames | PS3.5 8.2, A.4; Table A-1 Explicit VR Little Endian | preserve, decode | preserve | match |
| `--make-stacks` | Stack ID (0020,9056) per Image Orientation (Patient) (0020,0037) | PS3.3 C.7.6.16.2.2 | flag | off | match |
| `--temporal-position` | Temporal Position Index (0020,9128) | PS3.3 C.7.6.16.2.2 | flag; from Trigger Time, Temporal Position Identifier, Acquisition Time | off | match (help listed 2 of the 3 sources) |
| `--new-series` | Series Instance UID (0020,000E) | PS3.3 C.7.3.1 | flag | off | match |
| `--allow-any-source` | skip source SOP Class check | PS3.6 Table A-1 | flag | off | plumbing |
| `--level` | grouping of inputs | PS3.3 C.7.2.1 / C.7.3.1 (Study / Series Instance UID) | file, series, study | file | match (tool grouping, not a Q/R level) |
| `--sort-by` | frame order key | PS3.6 Table 6-1 keywords | InstanceNumber, ImagePositionPatient, AcquisitionTime, none | InstanceNumber | match |
| `--order` | direction | — | ascending, descending | ascending | plumbing |
| `--validate` | identity consistency | PS3.6 Table 6-1 | flag (Study/Series Instance UID, Modality, Frame of Reference UID) | off | match (help now names them) |
| `-r` / `-v` | — | — | flags | off | plumbing |

matched 8, wrong 0, missing 0, extra 0, plumbing 6

**Output contract**

| Output | Standard | Verdict |
|---|---|---|
| merged SOP Class, Number of Frames (0028,0008), Instance Number 1, functional groups, Frame Content, Multi-frame Dimension | PS3.3 C.7.6.6, C.7.6.16, C.7.6.17 (DICOMKit pass) | match |
| error "Inconsistent (gggg,eeee): …" / "Inconsistent TransferSyntaxUID" | PS3.6 Table 6-1 Tag notation / keyword (0002,0010) | match |
| console lines (MergeConsole) | carries no standard data (DICOMKit pass) | plumbing |
| exit 0, 1 merge failure, 64 usage | — | plumbing (README fixed: claimed 64 for inconsistent inputs; verified by run: 1) |

**Changes** (`Sources/dicom-merge/DICOMMerge.swift`, `README.md`): discussion names the Shared and Per-Frame
Functional Groups Sequences, Frame Content Macro, Multi-frame Dimension Module, the Table A-1 class of every
`--format` value; "Legacy Converted Enhanced MR (Sup 157)" → "Legacy Converted Enhanced MR Image Storage (PS3.3
A.71)"; help of `--pixel-handling`, `--make-stacks`, `--temporal-position`, `--new-series`, `--level`, `--sort-by`,
`--validate` names the PS3.6 attributes with tags. README was stale (said Enhanced output "not yet implemented",
listed 4 of 12 formats, 8 of 14 options, wrong exit code for inconsistent inputs, "Samples Per Pixel",
"Image Position Patient"): rewritten to the current behaviour with a `--format` → Table A-1 table.
Test target `dicom-mergeTests` (`Tests/dicom-mergeTests/MergeOptionTermsTests.swift`, 4 tests).

**P-items**: none.

**Deferred findings**: none new.

**Marker**: `// NEMA-verified: 2026a, checked 2026-10-01 — --format: 10 SOP Classes match PS3.6 2026a Table A-1 (UID and name); --sort-by: 3 values are PS3.6 Table 6-1 keywords; help pairs 7 attribute names with their Table 6-1 tags; it names the PS3.3 2026a Multi-frame Functional Groups / Frame Content / Multi-frame Dimension modules and A.70-A.72 Legacy Converted IODs; Basic Offset Table per PS3.5 A.4`

**Commit**: 2ef9d28 (also carries the dicom-split Package.swift target and CHANGELOG bullet that e27aa9f dropped).
**Tests**: `dicom-mergeTests` 4/4 pass; `SplitMergeWorkshopCLIParityTests` (release binaries rebuilt) pass; `DICOMRoundTripTests.(Merge|Enhanced)*` pass; `diff_cli.py --tool dicom-merge` 0 wrong; markers 0 without.


## G3 Encoding and pixel

### dicom-anon

Commands: dicom-anon · files: main.swift, AnonCLISupport.swift (new) · commit `06717c9`

**What was compared (by script):** PS3.15 2026a Table E.1-1 (651 rows; header dumped: Basic Prof. + 10 Option columns), Table E.1-1a (11 action codes), sections E.1.1, E.2, E.3.1–E.3.11 (12 Option names, dumped via section titles + text); PS3.16 2026a CID 7050 (13 rows); PS3.6 Table 6-1 (VRs for the fixture, names). Fixture: one element per data-set row of Table E.1-1 (647 of 651; the 4 command/meta/DICOMDIR rows cannot live in a data set), VR from PS3.6, plus a private block; each profile run through the built tool and every row's outcome (X/Z/K/D/U) diffed against the 2026a action code (`scratch/anon/fixture.py`, `scratch/anon/diffe11.py`).

| Profile | Table E.1-1 rows matched (of 647) |
|---|---|
| `ps315` | 647 (642 literal; 5 SQ rows with D kept with scrubbed items, which satisfies D) |
| `ps315 --retain-full-dates` (Full Dates column) | 647 |
| `ps315 --retain-modified-dates --shift-dates 10` (Modified Dates column C) | 647 counted as C, but only the 54 DA rows are shifted; 60 DT, 52 TM, 3 other C cells zeroed (D157) |
| `basic` (legacy, default) | 11 |
| `clinical-trial` (legacy) | 15 |
| `research` (legacy) | 1 |

`--profile basic` is therefore not the PS3.15 Basic Profile, and no legacy value equals a PS3.15 Profile+Options set (each is a strict subset: 14, 22 and 3 attributes); there is no standard alias to record. CID 7050: engine codes and meanings 13/13 match, PixelRedactor 113101 "Clean Pixel Data Option" matches.

**Input contract**

| Option | DICOM concept | 2026a reference | Allowed per standard | Code accepts | Default (std) | Default (code) | Verdict |
|---|---|---|---|---|---|---|---|
| `<input-path>` | input file / directory | PS3.10 7.1 | — | `String` | — | — | plumbing |
| `-o, --output` | output file / directory | PS3.10 7.1 | (0002,0003) = (0008,0018) | `String?` | — | — | plumbing; fixed: meta (0002,0003) kept the original SOP Instance UID (all profiles) |
| `--profile` | Attribute Confidentiality Profile | PS3.15 E.1, E.2, Table E.1-1 | Basic Application Level Confidentiality Profile + E.3 Options | `ps315`; legacy `basic`, `clinical-trial`/`clinicaltrial`, `research` | Basic Profile | `basic` (legacy, 11/647) | **wrong** — documented in help/README + stderr note; rename/default = P-ANON-PROFILE |
| `--retain-dates` | Retain Longitudinal Temporal Information With Full Dates / With Modified Dates Option | PS3.15 E.3.6; CID 7050 113106/113107 | two mutually exclusive Options | Full; Modified with `--shift-dates`; ps315 only | off | off | match (help names the Options; ambiguity = P-ANON-RETAIN-DATES) |
| `--retain-full-dates` | … With Full Dates Option | PS3.15 E.3.6; 113106 | — | flag | off | off | missing → **added** |
| `--retain-modified-dates` | … With Modified Dates Option | PS3.15 E.3.6; 113107 | — | flag, needs `--shift-dates` | off | off | missing → **added** |
| `--retain-characteristics` | Retain Patient Characteristics Option | PS3.15 E.3.7; 113108 | — | flag, ps315 only | off | off | match (refused on legacy profiles; was silently ignored) |
| `--retain-device` | Retain Device Identity Option | PS3.15 E.3.8; 113109 | — | flag, ps315 only | off | off | match (idem) |
| `--retain-institution` | Retain Institution Identity Option | PS3.15 E.3.11; 113112 | — | flag, ps315 only | off | off | match (idem) |
| `--retain-uids` | Retain UIDs Option | PS3.15 E.3.9; 113110 | — | flag, ps315 only | off (U) | off (U) | match |
| `--clean-descriptors` | Clean Descriptors Option | PS3.15 E.3.5; 113105 | C = clean | flag, ps315 only; engine keeps verbatim | off | off | match (surface; help now says "kept as they are, not cleaned"); engine D158 |
| `--clean-pixel-data` | Clean Pixel Data Option | PS3.15 E.3.1; 113101; (0028,0301) NO | — | flag, all profiles | off | off | match |
| `--redact-region` | Clean Pixel Data region | PS3.15 E.3.1 | — | `x,y,w,h` repeatable | — | — | plumbing |
| `--redact-fill` | blank sample value | PS3.15 E.3.1 | — | `Int` | — | 0 | plumbing |
| `--shift-dates` | date modification (Modified Dates) | PS3.15 E.3.6 | needs the Modified Dates Option | `Int` days | — | — | **wrong → fixed**: on ps315 without a dates Option it was silently ignored; now refused |
| `--regenerate-uids` | U action | PS3.15 Table E.1-1 U | U by default | legacy: 3 UIDs; ps315: always U unless `--retain-uids` | U | off (legacy) | match (documented; legacy default = P-ANON-PROFILE); refused with `--retain-uids` |
| `--remove` | X action | Table E.1-1a X; PS3.6 Table 6-1 keywords | — | hex forms + any PS3.6 keyword | — | — | **wrong → fixed**: ignored on ps315; only 11 keywords recognised |
| `--replace` | replace value | PS3.6 Table 6-1 | — | `TAG=VALUE`, `KEYWORD=VALUE` | — | — | **wrong → fixed** (idem; README example `InstitutionName=` failed) |
| `--keep` | K action | Table E.1-1a K | — | legacy only | — | — | **wrong → fixed**: ignored on ps315, now refused there |
| `--recursive` | directory walk | — | — | flag | — | off | plumbing |
| `--dry-run` | preview | — | — | flag | — | off | match (now lists actions) |
| `--backup` | copy input | — | — | flag | — | off | plumbing |
| `--audit-log` | de-identification record | PS3.15 E.1.1 | — | path | — | — | **wrong → fixed**: ps315 log held only its header; now one line per attribute (code + PS3.6 name, no values) |
| `--force` | no DICM prefix | PS3.10 7.1 | — | flag | — | off | plumbing |
| `--allow-burned-in-phi` | write with residual pixel PHI | PS3.15 E.1.1, E.3.1 | (0012,0062) NO | flag, ps315 only | — | off | match (help: stale "never redacts pixels" fixed) |
| `--verbose` | verbosity | — | — | flag | — | off | plumbing |
| `(Retain Safe Private Option)` | | PS3.15 E.3.10; 113111 | | not offered | | | missing (engine: D159) |
| `(Clean Structured Content Option)` | | PS3.15 E.3.4; 113104 | | not offered | | | missing (D159) |
| `(Clean Graphics Option)` | | PS3.15 E.3.3; 113103 | | not offered | | | missing (D159) |
| `(Clean Recognizable Visual Features Option)` | | PS3.15 E.3.2; 113102 | | not offered | | | missing (D159) |

Counts (26 options + 4 absent concepts): matched 10, wrong 6 (all fixed; `--profile` documented + P-item), missing 6 (2 added, 4 deferred), extra 0, plumbing 8.

**Output contract**

| Field | DICOM source | Encoding (standard) | Encoding (code) | Verdict |
|---|---|---|---|---|
| (0012,0062) Patient Identity Removed | PS3.15 E.1.1; PS3.3 Table C.7-1 | CS `YES` | `YES`; `NO` when Burned In Annotation YES / overlays remain | match |
| (0012,0063) De-identification Method | PS3.15 E.1.1 | LO 1-n text | "PS3.15 Basic Application Level Confidentiality Profile" + CID 7050 meanings of Options | match (omits Clean Pixel Data text: D160) |
| (0012,0064) De-identification Method Code Sequence | PS3.16 CID 7050 | DCM 113100–113112 | 13/13 codes + meanings match by script; 113100 + one per Option | match |
| (0028,0303) Longitudinal Temporal Information Modified | PS3.15 E.2, E.3.6 | REMOVED / UNMODIFIED / MODIFIED | never written | **missing** (engine: D161) |
| (0028,0301) Burned In Annotation | PS3.15 E.3.1 | `NO` | `NO` only when pixels were blanked; 113101 added | match |
| (0002,0003) Media Storage SOP Instance UID | PS3.10 7.1; Table E.1-1 U | = (0008,0018) | original UID kept | **wrong → fixed** in CLI write step (engine: D162) |
| Per-attribute action lines (`--dry-run`/`--verbose`) | PS3.15 Table E.1-1a; PS3.6 Table 6-1 | D/Z/X/C/U + name | none (only "(gggg,eeee)" list) | missing → **added**: `  Z        (0010,0010) Patient's Name`; `recorded` for 0012,0062-0064 / 0028,0301-0303 |
| `--audit-log` lines (ps315) | as above | — | `[ts] path - Z - (0010,0010) Patient's Name`, `Method:` line of CID 7050 meanings | missing → **added** |
| Summary block (shared `AnonConsole.summary`) | — | — | Total/Successful/Failed/"(DRY RUN - no files modified)"/Modified tags | plumbing (shared console, unchanged) |
| stderr note for legacy profiles | PS3.15 E.2 | — | "is a legacy attribute list, not the PS3.15 Basic Application Level Confidentiality Profile" | added |
| exit codes | — | — | 0 ok; 1 any failure or refused option (CLI's own ValidationError, not ArgumentParser's 64) | plumbing |
| extractor "JSON" `basic`/`clinicaltrial`/`ps315`/`research` | — | — | these are `--profile` values, not JSON keys | n/a |

**Findings fixed (commit 06717c9):** ps315 ignored `--remove`/`--replace`/`--keep`; ps315 audit log empty; `--shift-dates` silently ignored on ps315 without a dates Option; Option flags silently ignored on legacy profiles; keyword parsing limited to 11 keywords; (0002,0003) kept the original UID; no per-attribute action/E.1-1a output; help/README claimed `basic` handles address/phone (it does not) and implied PS3.15 conformance; stale "never redacts pixels". Added `--retain-full-dates`, `--retain-modified-dates`.

**P-items**
- **P-ANON-PROFILE**: make `--profile` default `ps315`; make `basic` an alias of `ps315` (the PS3.15 Basic Profile); keep the legacy lists as `legacy-basic`, `legacy-clinical-trial`, `legacy-research` (old spellings deprecated with a warning for one release). Recommended.
- **P-ANON-RETAIN-DATES**: deprecate `--retain-dates` (its Option depends on `--shift-dates`) in favour of `--retain-full-dates` / `--retain-modified-dates`.

**Deferred findings**

| D161 | DICOMKit | Sources/DICOMKit/Anonymization/ConfidentialityEngine.swift:310 | `recordMethod` never writes Longitudinal Temporal Information Modified (0028,0303): REMOVED without a dates Option, UNMODIFIED with Full Dates, MODIFIED with Modified Dates | PS3.15 2026a E.2, E.3.6 | Medium | ✅ 2026-10-01 (`31536bad`) — see the deferred-findings table above |
| D158 | DICOMKit | Sources/DICOMKit/Anonymization/ConfidentialityEngine.swift:181 | Clean Descriptors Option keeps every C attribute verbatim (140 rows on the fixture, e.g. Study Comments "… John Doe") yet records 113105 Clean Descriptors Option; C requires values "known not to contain identifying information" | PS3.15 2026a E.3.5, Table E.1-1a (C) | High | ✅ 2026-10-01 (`31536bad`) — see the deferred-findings table above |
| D157 | DICOMKit | Sources/DICOMKit/Anonymization/ConfidentialityEngine.swift:239 | Modified Dates Option shifts only DA; DT (60 rows), TM (52) and 3 other C cells are zeroed while 113107 is recorded; E.3.6 requires dates and times modified preserving temporal relationships | PS3.15 2026a E.3.6 | Medium | ✅ 2026-10-01 (`31536bad`) — see the deferred-findings table above |
| D159 | DICOMKit | Sources/DICOMKit/Anonymization/ConfidentialityProfile.swift:49 | `Options` has no Retain Safe Private, Clean Structured Content, Clean Graphics, Clean Recognizable Visual Features; the generated cleanStructuredContent/cleanGraphics columns are unused by `action(for:options:)`; the CLI cannot offer these four Options | PS3.15 2026a E.3.2, E.3.3, E.3.4, E.3.10; CID 7050 113102-113104, 113111 | Low | ✅ 2026-10-01 (`5aeca208`) — see the deferred-findings table above |
| D162 | DICOMKit | Sources/DICOMKit/Anonymization/Anonymizer.swift:416 | `deidentify` (and `anonymize`, :222) keep the source File Meta: Media Storage SOP Instance UID (0002,0003) keeps the original UID while (0008,0018) is replaced (U); dicom-anon now syncs it at write, other callers (Studio) do not | PS3.10 2026a 7.1; PS3.15 2026a Table E.1-1 (0002,0003) U | High | ✅ 2026-10-01 (`55b5e6b9`) — see the deferred-findings table above |
| D160 | DICOMKit | Sources/DICOMKit/Anonymization/ConfidentialityEngine.swift:337 | After pixel cleaning (113101 recorded by PixelRedactor), (0012,0063) omits "Clean Pixel Data Option" and the 113100 item follows 113101 in (0012,0064) | PS3.15 2026a E.1.1; PS3.3 2026a Table C.7-1 | Low | ✅ 2026-10-01 (`31536bad`) — see the deferred-findings table above |
| D163 | DICOMKit | Sources/DICOMKit/Anonymization/Anonymizer.swift:458 | `parseFlexibleTag` knows 11 hard-coded keywords and its lowercased lookup can never match (keys are PascalCase); dicom-anon now falls back to DataElementDictionary, the Studio Workshop executor does not | PS3.6 2026a Table 6-1 | Low | ✅ 2026-10-01 (`31536bad`) — see the deferred-findings table above |
| D164 | DICOMKit | Sources/DICOMKit/Anonymization/Anonymizer.swift:305 | Legacy `shiftAllDates`/`regenerateAllUIDs` (:321) ignore `preserveTags`: `--keep StudyDate --shift-dates N` still shifts it | (legacy behaviour, no PS3.15 clause) | Low | ✅ 2026-10-01 (`31536bad`) — see the deferred-findings table above |

**Markers**
- main.swift: `// NEMA-verified: 2026a, checked 2026-10-01 — --profile and the Option flags against PS3.15 2026a E.1-E.3 and the 12 Option columns of Table E.1-1 (8 Options offered, 4 not offered by the engine); on a fixture of the 647 data-set rows of Table E.1-1, --profile ps315 matches 647 (5 SQ D rows kept with scrubbed items) and the legacy basic 11, clinical-trial 15, research 1 (documented as not PS3.15); recorded codes match PS3.16 2026a CID 7050 (13 rows); (0002,0003) follows (0008,0018) per PS3.10 2026a 7.1`
- AnonCLISupport.swift: `// NEMA-verified: 2026a, checked 2026-10-01 — option names diffed against the 12 Options of PS3.15 2026a E.3 and the Table E.1-1 Option columns (7 offered here: …; Clean Pixel Data in main.swift); action labels are the 6 PS3.15 2026a Table E.1-1a single codes (K not listed: unchanged); names from PS3.6 2026a Table 6-1 via DataElementDictionary`

**Tests:** `swift build --product dicom-anon` ok; `swift test --filter dicom_anonTests` 12/12 pass (new target `dicom-anonTests`, Package.swift hunk committed via a temporary index); `check_nema_markers.py Sources/dicom-anon` 2/2; `diff_cli.py --tool dicom-anon` 0 FAIL (26 options).

**diff_cli.py note:** nothing to add to the extractor; the "JSON basic/clinicaltrial/ps315/research" rows it emits are `--profile` switch values, not JSON keys.

### dicom-image (G3) — verified 2026-10-01

Converts JPEG/PNG/TIFF/BMP/GIF to the **Secondary Capture Image IOD** (PS3.3 A.8.1, SOP Class "Secondary Capture
Image Storage" 1.2.840.10008.5.1.4.1.1.7 per PS3.4 Table B.5-1 / PS3.6 Table A-1), single-frame, Explicit VR Little
Endian; it does not render DICOM to images and does not use the multi-frame SC IODs (A.8.2–A.8.5; `--split-pages`
writes one single-frame instance per TIFF page). Engine: `DICOMKit/SecondaryCapture/ImageConverter.swift` (DICOMKit
pass 2026-09-29). Evidence: `<scratch>/g3img/iod_attrs.py` (expands Table A.8-1 M modules through their Include
macros: Tables C.7-1, C.7-3, C.7-5a, C.8-24, C.7.10.1-1, C.7-9, C.7-11a > C.7-11c, C.8-25 > 10-10, C.12-1 > 10.41-1),
`<scratch>/g3img/check_sc.py` (runs on tool output for RGB, gray, RGBA, 16-bit gray PNG, EXIF JPEG, GIF; every Type 1/2
and applicable 1C/2C present, Type 1 non-empty, Image Pixel 8/8/7/0, Pixel Data length), `diff_kit.attribute_terms`
for Conversion Type (8 terms) and Modality (97 terms), PS3.3 Table C.12-5 (ISO_IR 192), PS3.5 Table 6.2-1 (UI, LO, PN,
IS), PS3.10 Table 7.1-1. `diff_cli.py --tool dicom-image`: 0 wrong (13 citations matched).

**Before the fix** the output had Media Storage SOP Instance UID (0002,0003) ≠ SOP Instance UID (0008,0018) in every
file, and no Specific Character Set for a non-ASCII Patient's Name (UTF-8 bytes written); all Type 1/2 attributes were
otherwise present (27 grayscale / 28 colour).

**Input contract**

| Option | DICOM concept | 2026a reference | Allowed (standard) | Code accepts | Default std / code | Verdict |
|---|---|---|---|---|---|---|
| `<input>` | raster image or directory | — | — | path; .jpg .jpeg .png .tif .tiff .bmp .gif | — | plumbing |
| `-o, --output` | output path | PS3.10 7.1 | — | path | — / `<name>.dcm`, `<dir>/dicom`, `<name>_frames` | plumbing |
| `--patient-name` | Patient's Name (0010,0010) | Table C.7-1 Type 2; PS3.5 Table 6.2-1 PN | PN, ≤64 chars per component group, no `\` | any (required by tool); now warns on >64/`\` | — / required | match |
| `--patient-id` | Patient ID (0010,0020) | Table C.7-1 Type 2; LO | LO ≤64, no `\` | any (required); now warns | — / required | match |
| `--study-description` | Study Description (0008,1030) | Table C.7-3 Type 3; LO | LO ≤64 | any; warns | absent / EXIF description or absent | match |
| `--series-description` | Series Description (0008,103E) | Table C.7-5a Type 3; LO | LO ≤64 | any; warns | absent | match |
| `--study-uid` | Study Instance UID (0020,000D) | Table C.7-3 Type 1; PS3.5 9.1, Table 6.2-1 UI | UID syntax, ≤64 bytes | any, written unchecked → now warns (DICOMUniqueIdentifier.parse) | — / generated | missing → fixed (warning; P-IMAGE-VR) |
| `--series-uid` | Series Instance UID (0020,000E) | Table C.7-5a Type 1; PS3.5 9.1 | UID syntax | as above | — / generated | missing → fixed (warning) |
| `--series-number` | Series Number (0020,0011) | Table C.7-5a Type 2; IS | −2^31..2^31−1 | Int; now warns outside IS range | empty / empty | match |
| `--instance-number` | Instance Number (0020,0013) | Table C.7-9 Type 2; IS | IS range | Int; warns | — / 1 (+1 per file/page) | match |
| `--modality` | Modality (0008,0060) | Table C.7-5a Type 1; C.7.3.1.1.1 Defined Terms (97) | Defined Terms (extensible) | shared ModalityOptionValidator (DICOMCore, verified); unknown warns | — / OT | match |
| `--strict-modality` | reject non-Defined-Term | C.7.3.1.1.1 | — | flag | off | plumbing |
| `--conversion-type` (new) | Conversion Type (0008,0064) | Table C.8-24 Type 1 | DV, DI, DF, WSD, SD, SI, DRW, SYN | the 8 terms, case-insensitive; others exit 64 | — / WSD | missing → fixed (option added; was always WSD) |
| `--use-exif` | Acquisition Date/Time (0008,0022/0032); Nominal Scanned Pixel Spacing (0018,2010) | Table C.7.10.1-1 (General Acquisition, M); Table C.8-25 | — | DateTimeOriginal, DPI, UserComment/ImageDescription | off | wrong → fixed (README said DPI → Pixel Spacing; code writes (0018,2010), correct) |
| `--split-pages` | one SC instance per TIFF page | A.8.1 (single-frame) | — | flag | off | match |
| `--recursive` | — | — | — | flag | off | plumbing |
| `--verbose` | — | — | — | flag | off | plumbing |

matched 8, wrong 1, missing 3, extra 0, plumbing 5

**Output contract**

| Output | Standard | Verdict |
|---|---|---|
| SOP Class UID 1.2.840.10008.5.1.4.1.1.7, Transfer Syntax 1.2.840.10008.1.2.1 | PS3.4 Table B.5-1; PS3.6 Table A-1 | match |
| Type 1/2 attributes of the 9 M modules of Table A.8-1 (27 gray / 28 RGB incl. Planar Configuration 1C, Patient Orientation 2C empty) | PS3.3 2026a Tables C.7-1 … C.12-1 | match |
| Image Pixel: Samples per Pixel 1/3, MONOCHROME2/RGB, 8/8/7/0, Planar Configuration 0, Pixel Data OB | C.7.6.3.1; Table C.7-11c | match (16-bit sources are reduced to 8 bits; alpha composited on white) |
| Media Storage SOP Instance UID (0002,0003) | PS3.10 Table 7.1-1 | wrong → fixed (CLI `SCOutput.finalize`; engine D165) |
| Specific Character Set (0008,0005) | Table C.12-1 Type 1C; Table C.12-5 "ISO_IR 192" | missing → fixed (written when a text value is not ASCII; engine D166) |
| Conversion Type (0008,0064) | Table C.8-24 | match (WSD default; `--conversion-type`) |
| Nominal Scanned Pixel Spacing (0018,2010) from DPI, `row\column` | Table C.8-25; 10.7.1.3 | match |
| General Equipment Manufacturer "DICOMKit", Model "dicom-image CLI", Software Versions | C.8.6.1 scenario table (General Equipment = equipment that created the image) | deferred (D167) |
| stdout `Converted: <path>`, batch/TIFF summaries; exit 0 / 1 (I/O) / 64 (usage, bad `--conversion-type`) | — | plumbing |

**Changes** (commit `1c9aaba8`): `Sources/dicom-image/SCOutput.swift` (new: `conversionType`, `valueWarnings`,
`finalize`), `main.swift` (`--conversion-type`, warnings, `finalize` on all three write paths, help with tags and the
PS3.4 SOP Class name), `README.md` (EXIF mapping corrected, options, Table A.8-1 module list). Test target
`dicom-imageTests` (`Tests/dicom-imageTests/SCOutputTests.swift`, 5 tests: Table C.8-24 terms; PS3.5 6.2-1 warnings;
finalize UID + ISO_IR 192; ASCII left alone; converted PNG carries every Type 1/2 attribute of Table A.8-1).

**P-items**
- P-IMAGE-VR: `--study-uid`/`--series-uid` breaking PS3.5 9.1, LO/PN values over 64 characters or with `\`, and
  `--series-number`/`--instance-number` outside the IS range only warn; proposal: reject them (exit 64). Not
  implemented (accepted-value change).

**Deferred findings**

| ID | Module | file:line | Problem | Standard | Severity | Status |
|---|---|---|---|---|---|---|
| D165 | DICOMKit | Sources/DICOMKit/SecondaryCapture/ImageConverter.swift:139 | `DICOMFile.create(dataSet:transferSyntaxUID:)` is called without `sopInstanceUID`, so (0002,0003) gets a second UID ≠ (0008,0018) (DICOMStudio path too; the CLI now rewrites it) | PS3.10 2026a Table 7.1-1 | High | ✅ 2026-10-01 (`55b5e6b9`) — see the deferred-findings table above |
| D166 | DICOMKit | Sources/DICOMKit/SecondaryCapture/ImageConverter.swift:157-181 | text written as UTF-8 without Specific Character Set (0008,0005) "ISO_IR 192" when a value is not ASCII (CLI adds it) | PS3.3 2026a Table C.12-1 (1C), Table C.12-5 | Medium | ✅ 2026-10-01 (`3ca15a08`) — see the deferred-findings table above |
| D167 | DICOMKit | Sources/DICOMKit/SecondaryCapture/ImageConverter.swift:184-187 | converter identity (DICOMKit / "dicom-image CLI" / "1.1.6") written to General Equipment, which describes the equipment that created the original image; belongs in SC Equipment Secondary Capture Device Manufacturer / Model Name / Software Versions (0018,1016/1018/1019); "dicom-image CLI" also when DICOMStudio converts | PS3.3 2026a C.8.6.1 (scenario table), Table C.8-24 | Low | ✅ 2026-10-01 (`3ca15a08`) — see the deferred-findings table above |
| D168 | DICOMKit | Sources/DICOMKit/SecondaryCapture/ImageConverter.swift:166 | EXIF UserComment/ImageDescription written to Study Description (LO) without the 64-character limit or `\` check | PS3.5 2026a Table 6.2-1 (LO) | Low | ✅ 2026-10-01 (`3ca15a08`) — see the deferred-findings table above |

**Marker**: `// NEMA-verified: 2026a, checked 2026-10-01 — output diffed against PS3.3 2026a Table A.8-1 (Secondary Capture Image IOD): all Type 1/2 attributes of the 9 M modules present (27 grayscale, 28 colour incl. Planar Configuration 1C; Tables C.7-1, C.7-3, C.7-5a, C.8-24, C.7.10.1-1, C.7-9, C.7-11a/c, C.8-25, C.12-1); 16 options: --modality via ModalityOptionValidator (C.7.3.1.1.1, 97 terms), --conversion-type Table C.8-24 (8 terms), SOP Class name/UID per PS3.4 Table B.5-1 and PS3.6 Table A-1, help names per PS3.6 Table 6-1 (see SCOutput.swift)` (main.swift); SCOutput.swift: `… Conversion Type Defined Terms … (Table C.8-24, 8 of 8); Specific Character Set "ISO_IR 192" (Table C.12-5 …); (0002,0003) = SOP Instance UID (PS3.10 Table 7.1-1); value limits of PS3.5 Table 6.2-1 …`

**Tests**: `dicom-imageTests` 5/5 pass; `swift build --product dicom-image` ok; `diff_cli.py --tool dicom-image` 0 wrong; `check_nema_markers.py Sources/dicom-image` 2/2 marked.

### dicom-pixedit (G3) — verified 2026-10-01

Edits stored pixel values of an image: mask a rectangle, crop, bake a window, invert. Engine:
`DICOMKit/PixelEditing/PixelEditor.swift` (DICOMKit pass 2026-09-29: C.11.2.1.2 formula). Evidence, by script from
the 2026a DocBook: PS3.3 C.7.6.1.1.2 (Image Type; "the Derived Image shall have a SOP Instance UID different than all
the source images"), Table C.7-9 (Image Type, Burned In Annotation, Recognizable Visual Features, Lossy Image
Compression all Type 3), Table C.12-10 General Reference Module (Derivation Description, Derivation Code Sequence
CID 7203, Source Image Sequence with Table 10-3 and CID 7202), C.12.4.1.1/.2, C.7.6.1.1.5, C.7.6.2.1.1 Equation
C.7.6.2.1-1, C.11.2.1.2 (VOI input = Modality LUT output; Window Width ≥ 1), PS3.16 CID 7202 (9 rows) and CID 7203
(34 rows: none for mask/crop/window/invert), PS3.10 Table 7.1-1. Run on a 12-bit CT fixture (`<scratch>/g3img/mkct.py`,
`show.py`). `diff_cli.py --tool dicom-pixedit`: 0 wrong (6 citations matched).

**Before the fix** the output kept the source SOP Instance UID, Image Type ORIGINAL, no Derivation Description /
Source Image Sequence, the source's Implementation Class UID and stale Smallest/Largest Image Pixel Value; a crop left
Image Position (Patient) at the old corner; `--window-center 40 --window-width 400` on a CT (Rescale Intercept −1024)
was applied to stored values (i.e. −984 HU); `--fill-value 9000` on Bits Stored 12 wrote 9000.

**Input contract**

| Option | DICOM concept | 2026a reference | Allowed (standard) | Code accepts | Default std / code | Verdict |
|---|---|---|---|---|---|---|
| `<input>` | PS3.10 file with Pixel Data | PS3.10 7.1 | — | path; encapsulated inputs decoded | — | plumbing |
| `--output` | output PS3.10 file | PS3.10 7.1 | — | path (required) | — | plumbing |
| `--mask-region` | rectangle of pixels (0-based column, row) | C.7.6.2.1.1 indices i, j from 0 | — | `x,y,w,h`, x,y ≥ 0, w,h > 0 | — | match (Burned In Annotation left unchanged; documented) |
| `--fill-value` | stored sample value | C.7.6.3.1 (Bits Stored, Pixel Representation) | 0..2^BS−1 / −2^(BS−1)..2^(BS−1)−1 | Int; was clamped to Bits Allocated only → now clamped to the stored range with a warning | — / 0 | wrong → fixed |
| `--crop` | sub-matrix; Rows/Columns, Image Position (Patient) | Table C.7-11c; C.7.6.2.1.1 Eq. C.7.6.2.1-1 | — | `x,y,w,h` | — | wrong → fixed (IPP moved: S + X·Δi·x + Y·Δj·y, Δi = Pixel Spacing Value 2) |
| `--window-center` | Window Center (0028,1050) | C.11.2.1.2 (Modality LUT output units) | any | Double; was applied to stored values → now translated through Rescale Slope/Intercept | — | wrong → fixed |
| `--window-width` | Window Width (0028,1051) | C.11.2.1.2 (≥ 1) | ≥ 1 | Double; ≤ 0 refused by engine; 0 < w < 1 now warns and uses 1; translated as above | — | wrong → fixed |
| `--apply-window` | linear VOI function baked into stored values | C.11.2.1.2 | — | flag; requires both window options | off | match |
| `--invert` | invert stored values across the Bits Stored range | C.7.6.3.1 | — | flag | off | match |
| `-v, --verbose` | — | — | — | flag | off | plumbing |

matched 3, wrong 4, missing 0, extra 0, plumbing 3

**Output contract**

| Output | Standard | Verdict |
|---|---|---|
| SOP Instance UID (0008,0018) and (0002,0003) | C.7.6.1.1.2 (new UID when pixel data differ); PS3.10 Table 7.1-1 | wrong → fixed (new UID) |
| Image Type (0008,0008) Value 1 | C.7.6.1.1.2: DERIVED | missing → fixed (Value 1 DERIVED, others kept; DERIVED\SECONDARY if absent) |
| Derivation Description (0008,2111) | Table C.12-10; ST ≤ 1024 (PS3.5 Table 6.2-1) | missing → fixed (appended, capped at 1024) |
| Derivation Code Sequence (0008,9215) | Table C.12-10, CID 7203 | match (not written: CID 7203 has no code for these operations) |
| Source Image Sequence (0008,2112) | Table C.12-10; Table 10-3; CID 7202 DCM 121322 "Source image for image processing operation" | missing → fixed (item appended) |
| Implementation Class UID / Version Name (0002,0012/0013) | PS3.10 Table 7.1-1 ("implementation that last wrote the file") | wrong → fixed (DICOMKit values) |
| Smallest/Largest Image Pixel Value, … in Series (0028,0106–0109) | Table C.7-11a | wrong → fixed (removed; stale after the edit) |
| Window Center/Width after bake/invert | C.11.2.1.2 | match (engine) |
| Lossy Image Compression (0028,2110), Burned In Annotation (0028,0301) | C.7.6.1.1.5 (never reset); Table C.7-9 | match (left as they are) |
| Transfer Syntax after an encapsulated input | PS3.5 A.2 Explicit VR Little Endian | match |
| stderr `Input:`/`Output:`/`Operations:`/`Written:`/`Done.`, warnings; exit 0 / 1 / 64 | — | plumbing |

**Changes** (commit `698de5df`): `Sources/dicom-pixedit/DerivedImage.swift` (new: `storedRange`, `clampFill`,
`storedWindow`, `description`, `markDerived`, `croppedPosition`), `main.swift` (reads the source once, clamps the fill
value, translates the window, runs `processData`, marks the result derived, help), `README.md` (options, output
section). Test target `dicom-pixeditTests` (`Tests/dicom-pixeditTests/DerivedImageTests.swift`, 6 tests: derived
attributes and new UID; Image Type when absent + ST cap; crop IPP; HU window on CT incl. pixel value 369; fill
clamp; successive derivations).

**P-items**
- P-PIXEDIT-RANGE: `--fill-value` outside the stored range is clamped and `--window-width` in (0,1) is raised to 1,
  both with a warning; proposal: reject them (exit 64). Not implemented (accepted-value change).

**Deferred findings**

| ID | Module | file:line | Problem | Standard | Severity | Status |
|---|---|---|---|---|---|---|
| D169 | DICOMKit | Sources/DICOMKit/PixelEditing/PixelEditor.swift:81-214 | `processData` returns the edit with the source SOP Instance UID, Image Type, Implementation Class UID and stale Smallest/Largest Pixel Value, no Derivation Description / Source Image Sequence; DICOMStudio uses it as is (the CLI fixes this in DerivedImage.swift) | PS3.3 2026a C.7.6.1.1.2, Table C.12-10; PS3.10 Table 7.1-1 | Medium | ✅ 2026-10-01 (`ed4470db`) — see the deferred-findings table above |
| D170 | DICOMKit | Sources/DICOMKit/PixelEditing/PixelEditor.swift:296-332 | `applyWindowLevel` applies center/width to stored values; Window Center/Width are Modality LUT output units (CLI translates; DICOMStudio does not) | PS3.3 2026a C.11.2.1.2 | Medium | ✅ 2026-10-01 (`ed4470db`) — see the deferred-findings table above |
| D171 | DICOMKit | Sources/DICOMKit/PixelEditing/PixelEditor.swift:259-294 | `applyCrop` leaves Image Position (Patient) (top level and Plane Position Sequence in functional groups) and Overlay Rows/Columns/Origin unchanged (CLI updates top-level IPP only) | PS3.3 2026a C.7.6.2.1.1, C.9.2 | Medium | ✅ 2026-10-01 (`ed4470db`) — see the deferred-findings table above |
| D172 | DICOMKit | Sources/DICOMKit/PixelEditing/PixelEditor.swift:486-509 | `setPixelValue` clamps to the Bits Allocated range, not Bits Stored / Pixel Representation, so `.mask` can write values above High Bit | PS3.3 2026a C.7.6.3.1 | Low | ✅ 2026-10-01 (`ed4470db`) — see the deferred-findings table above |
| D173 | DICOMKit | Sources/DICOMKit/PixelEditing/PixelEditor.swift:107-128 | decoding a lossy-compressed input writes native pixels without setting Lossy Image Compression "01" (and Method) when the input lacks them | PS3.3 2026a C.7.6.1.1.5 | Low | ✅ 2026-10-01 (`ed4470db`) — see the deferred-findings table above |
| D174 | DICOMKit | Sources/DICOMKit/PixelEditing/PixelEditor.swift:296-345 | window/invert transform PALETTE COLOR indices and leave Pixel Padding Value (0028,0120) untransformed | PS3.3 2026a C.7.6.3.1.5, C.7.5.1.1.2 | Low | ✅ 2026-10-01 (`ed4470db`) — see the deferred-findings table above |

**Marker**: main.swift `// NEMA-verified: 2026a, checked 2026-10-01 — 10 options: --fill-value clamped to the Bits Stored / Pixel Representation range (PS3.3 2026a C.7.6.3.1), --window-center/--window-width in Modality LUT output units (C.11.2.1.2, Rescale Slope/Intercept C.11.1), output marked as a Derived Image (C.7.6.1.1.2, Table C.12-10; see DerivedImage.swift); --output/--verbose/<input> are plumbing`; DerivedImage.swift `// NEMA-verified: 2026a, checked 2026-10-01 — derived-image rules of PS3.3 2026a C.7.6.1.1.2 (…), C.12.4 General Reference Module Table C.12-10 (…CID 7202 DCM 121322; CID 7203 has no code…), C.7.6.2.1.1 Equation C.7.6.2.1-1, C.11.2.1.2 (width >= 1), PS3.5 Table 6.2-1 (ST 1024, DS 16), PS3.10 Table 7.1-1 (0002,0003), (0002,0012), (0002,0013)`

**Tests**: `dicom-pixeditTests` 6/6 pass; `swift build --product dicom-pixedit` ok; `diff_cli.py --tool dicom-pixedit` 0 wrong; `check_nema_markers.py Sources/dicom-pixedit` 2/2 marked.

### dicom-video (G3) — 2026-10-01

Scope: all 42 option/flag/argument declarations (43 found by `--list-surface`, `-o/--output` counted per subcommand) of `convert`, `probe`, `extract`, `batch`; help text is DICOMKit `VideoConsole.Help`; engine `VideoWorkflow` (verified in the DICOMKIT report, D34/D46/D58–D62) and D56 (`--audio-channel-source`, 8eebfab) not redone.

Compared by script (`<scratch>/vid_checks.py`, ffmpeg-made H.264 High@4.1, HEVC Main / Main 10, MPEG2 MP@ML clips, pydicom dumps):
- `--transfer-syntax` accepted set (`TransferSyntax.isVideo`) vs PS3.6 2026a Table A-1 MPEG2/MPEG-4/HEVC rows: matched 16, missing 0, **extra 2** (1.2.840.10008.1.2.4.107.1, .108.1 — written into an object without complaint before); the 16 `displayName`s differ from the A-1 names (16/16, "@" for "/", "HP" for "High Profile") → D176.
- `VideoConsole.Help` names vs PS3.6 2026a Tables 6-1/7-1: 16 rows, matched 15, wrong 1 ("Patient Name" → "Patient's Name", fixed).
- `--type` → SOP Class UID/name (Table A-1) and Modality (PS3.3 A.32.5.4.1/A.32.6.4.1/A.32.7.4.1 "shall be" ES/GM/XC): 3/3 match; `--modality CT --type photographic` was written as CT silently → now warned.
- Patient's Sex Enumerated Values M/F/O (Table C.7-1): `--patient-sex X` written silently → warned; `--patient-birth-date 1990-01-01` silently written empty → warned.
- Written dataset (H.264, HEVC Main, HEVC Main 10, 29.97 fps): Cine Module Table C.7-13 (Frame Time 33.333333 / 33.366667 ms, Cine Rate 30, Recommended Display Frame Rate 30), Frame Increment Pointer (0018,1063) (Table C.7-14), YBR_PARTIAL_420, Bits 8/8/7 and Main 10 16/10/9 (PS3.5 8.2.7, 8.2.10, 8.2.11), Lossy Image Compression Method ISO_14496_10 / ISO_23008_2: all match. Extract returns the MP4 byte-identical (cmp).
- README limits: Table 8-4 (BD), Pixel Aspect Ratio absent (8.2.7), 8/10-bit, 4:2:0 match the dumped text; container rule extended (8.2.5/8.2.6 leave MPEG2 unconstrained).

Counts (contract, 40 rows): matched 20, wrong 3, missing 0, extra 1, plumbing 16 (wrong/extra now warned; rejecting them is the P-items below).

#### Input contract

| Option | DICOM concept | 2026a reference | Allowed per standard | Code accepts | Default std | Default code | Verdict |
|---|---|---|---|---|---|---|---|
| --patient-name | Patient's Name (0010,0010) | PS3.3 C.7-1 Type 2 | PN | any string | empty | empty | match (help fixed) |
| --patient-id | Patient ID (0010,0020) | C.7-1 Type 2 | LO | any | empty | empty | match |
| --patient-birth-date | Patient's Birth Date (0010,0030) | C.7-1 Type 2; PS3.6 DA | YYYYMMDD | any; non-DA written empty | empty | empty | wrong → fixed (warns) |
| --patient-sex | Patient's Sex (0010,0040) | C.7-1 Type 2, Enumerated M F O | M, F, O | any | empty | empty | wrong → fixed (warns) |
| --study-uid / --series-uid | (0020,000D) / (0020,000E) | C.7-3 / C.7-5a Type 1; PS3.5 9.1 | UID | any | — | generated | match |
| --accession-number / --study-id / --referring-physician | (0008,0050) / (0020,0010) / (0008,0090) | C.7-3 Type 2 | SH / SH / PN | any | empty | empty | match |
| --series-description / --institution-name | (0008,103E) / (0008,0080) | C.7-5a / C.7-8 Type 3 | LO | any | absent | absent | match |
| --manufacturer | Manufacturer (0008,0070) | C.7-8 Type 2 | LO | any | empty | empty | match |
| --modality | Modality (0008,0060) | A.32.5.4.1 / A.32.6.4.1 / A.32.7.4.1 | ES / GM / XC per IOD | any (Defined Terms with --strict-modality) | ES/GM/XC | ES/GM/XC | wrong → fixed (warns; help names the rule) |
| --strict-modality | Modality Defined Terms | C.7.3.1.1.1 | — | flag | — | off | plumbing |
| --audio-channel-source | (003A,0208) in (003A,0300) | C.7-13; PS3.16 CID 3000 | 6 codes, Extensible | keyword or SCHEME:VALUE[:MEANING] | none | none | match (8eebfab) |
| convert <input> | bit stream container | PS3.5 8.2.5–8.2.11 | MP4/MPEG-TS (H.264, HEVC); any (MPEG2) | MP4, MPEG-TS | — | — | plumbing (help fixed; D177) |
| --type | SOP Class / IOD | A.32.5–A.32.7; PS3.6 A-1 | 3 Video IODs | endoscopic, microscopic, photographic | — | endoscopic (note printed) | match |
| --transfer-syntax | Transfer Syntax UID | PS3.6 A-1; PS3.5 8.2.5–8.2.11 | 16 UIDs | 18 UIDs (+ .107.1, .108.1) | detected | detected | extra (warned) |
| --frame-rate | Cine Rate / Frame Time / Recommended Display Frame Rate | C.7-13; PS3.5 Tables 8-2, 8-5, 8-7 | per transfer syntax | 0 < fps < 1000, then validated | from stream | from stream | match |
| --instance-number / --series-number | (0020,0013) / (0020,0011) | C.7-9 / C.7-5a Type 2 | IS | Int | — | 1 / 1 (help = code) | match |
| --dry-run, --trust-input, --force, -v, -o, probe/extract/batch arguments, --output-dir, --series-mode (IHE EIA), --recursive, --continue-on-error | — | — | — | — | — | — | plumbing |
| (cine module, FIP, pixel attributes, SOP class, extract frame numbering) | C.7-13, C.7-14, PS3.5 8.2.x | see above | | no option | | | match (n/a for frame numbering: extract returns the whole bit stream) |

#### Output contract

| Output | Concept | 2026a reference | Verdict |
|---|---|---|---|
| probe/convert "Container:", "Codec:", "Profile:", "Level:", "Resolution:", "Chroma:", "Bit depth:", "Scan:", "Frame rate:", "Frames:", "Audio tracks:" | bit stream properties (not attribute names); Resolution → Rows/Columns, Frames → Number of Frames | PS3.5 8.2.x | match, except MPEG2 "Level: 0.8" (D178) and raw MPEG2 ES reported as H.264 (D179) |
| "Transfer syntax:" UID | Transfer Syntax UID | PS3.6 A-1 | match |
| "Transfer syntax:" name line | A-1 name | PS3.6 A-1 | wrong, engine (`TransferSyntax.displayName`, 16/16) — D176 |
| "Conformance: OK" / violation lines | PS3.5 8.2.x constraints | PS3.5 Tables 8-1 to 8-8 | match (engine verified) |
| extract "Wrote <path> (<n> bytes)", Codec / Container / Transfer syntax UID | bit stream recovered unchanged | PS3.5 A.4 | match (cmp identical) |
| warnings (new) | A.32.x.4.1, C.7-1, DA, A-1 registration | as cited | added |
| exit codes 0 / 1 / 2 | success / I/O-usage / conformance rejection | tool-defined | plumbing |

#### Changes

- `Sources/dicom-video/OptionConformance.swift` (new): warnings for --modality ≠ ES/GM/XC of the --type, --patient-sex ∉ {M,F,O}, non-DA --patient-birth-date, unregistered --transfer-syntax (via `UIDDictionary.lookup(...).registered`).
- `Sources/dicom-video/main.swift`: prints them in `convert` and `batch` (object still written; no accepted value removed); marker.
- `Sources/DICOMKit/Video/VideoConsole.swift` (`VideoConsole.Help`, strings only, no member renamed): "Patient's Name"; modality help names ES/GM/XC per --type; transfer-syntax help names the accepted families; input help says MOV/raw ES are probed but not converted; marker line added.
- `Sources/dicom-video/README.md`: warnings, `--audio-channel-source`, container note for MPEG2, references A.32.6/A.32.7, Tables 8-1..8-8, 8.2.12, C.7-13.
- `Tests/dicom-videoTests/OptionConformanceTests.swift` (8 tests).
- Commit **cfc81d9f** (with CHANGELOG bullet).

Tests: `swift test --filter OptionConformanceTests` 8 passed; `AudioChannelSourceOptionTests` 10 passed (dicom-videoTests 18/18); `VideoConsoleParityTests` 60 passed. `swift build --product dicom-video` ok; `check_nema_markers.py Sources/dicom-video`: 3/3 files.

#### P-items (not implemented)

- **P-VIDEO-MODALITY-ENUMERATED**: refuse `--modality` values other than the IOD's ES/GM/XC (PS3.3 A.32.5.4.1/A.32.6.4.1/A.32.7.4.1), or drop `--modality` for video; today warned.
- **P-VIDEO-SEX-ENUMERATED**: refuse `--patient-sex` outside M/F/O (PS3.3 Table C.7-1) and a non-DA `--patient-birth-date` instead of writing it empty; today warned.
- **P-VIDEO-TS-REGISTERED**: refuse `--transfer-syntax 1.2.840.10008.1.2.4.107.1` / `.108.1` (not in PS3.6 Table A-1; DICOMCore keeps them by decision P2) for writing; today warned.

#### Deferred findings

| D176 | DICOMCore | Sources/DICOMCore/TransferSyntax.swift:1332 (`displayName`) | The 16 video transfer syntax names are abbreviations, not the PS3.6 names ("MPEG2 Main Profile @ Main Level" vs "MPEG2 Main Profile / Main Level", "MPEG-4 AVC/H.264 HP @ Level 4.1" vs "MPEG-4 AVC/H.264 High Profile / Level 4.1"; 16/16 differ); dicom-video prints them on the probe/convert "Transfer syntax:" line, in --verbose and violation messages. `UIDDictionary.lookup(uid:)?.name` has the A-1 name | PS3.6 2026a Table A-1 | Low | ✅ 2026-10-01 (`0d8aa69d`) — see the deferred-findings table above |
| D178 | DICOMKit | Sources/DICOMKit/Video/VideoStreamInfo.swift:98 (`levelDescription`) | MPEG2 level printed as "0.8" (level_indication 8); PS3.5 names the levels "Main Level" / "High Level" | PS3.5 2026a 8.2.5, 8.2.6 | Low | ✅ 2026-10-01 (`99c47e2e`) — see the deferred-findings table above |
| D179 | DICOMKit | Sources/DICOMKit/Video/VideoProbe.swift:291 (`probeElementaryStream`) | A raw MPEG-2 elementary stream (.m2v, sequence header 00 00 01 B3) is tried as H.264 first and reported as "H.264/AVC, profile_idc 51, level 12.5, 32x16"; the MPEG2 sequence-header check (line 319) is never reached | PS3.5 2026a 8.2.5 | Medium | ✅ 2026-10-01 (`99c47e2e`) — see the deferred-findings table above |
| D177 | DICOMKit | Sources/DICOMKit/Video/MP4ContainerParser.swift:32 (`isPermittedByDICOM`); VideoConformanceValidator.swift:113 | MPEG2 MP@ML/MP@HL streams are rejected unless in MP4 or MPEG-TS, citing 8.2.7; 8.2.5 and 8.2.6 say "The container format for the video bit stream is not constrained" (MPEG-TS, PS, ES, PES or MP4) | PS3.5 2026a 8.2.5, 8.2.6 | Low | ✅ 2026-10-01 (`99c47e2e`) — see the deferred-findings table above |
| D180 | DICOMKit | Sources/DICOMKit/Video/VideoBuilder.swift:649 (`toDataSet`) | A non-ASCII --patient-name (or other text) is written as UTF-8 without Specific Character Set (0008,0005) (checked: "Müller^Jörg" read back as "MÃ¼ller^JÃ¶rg") | PS3.3 2026a Table C.12-1 (Type 1C), Table C.12-5 (ISO_IR 192); PS3.5 6.1.2.2 | Medium | ✅ 2026-10-01 (`99c47e2e`) — see the deferred-findings table above |

Marker text (main.swift): `// NEMA-verified: 2026a, checked 2026-10-01 — input/output contract of all 42 option/flag/argument declarations (4 subcommands) by script: --transfer-syntax accepts the 16 MPEG2/MPEG-4 AVC/HEVC UIDs of PS3.6 2026a Table A-1 plus the 2 unregistered Fragmentable HEVC UIDs (warned, OptionConformance.swift); --type selects the 3 Video IODs of PS3.3 A.32.5-A.32.7 (Modality ES/GM/XC, SOP Class names per Table A-1); --modality/--patient-sex/--patient-birth-date values the IOD forbids are warned (A.32.x.4.1, Table C.7-1, DA); help text is VideoConsole.Help (16 names vs PS3.6 Table 6-1); --audio-channel-source per PS3.16 CID 3000 (AudioChannelSourceOption.swift, 6 rows) into Table C.7-13 (003A,0300)`; OptionConformance.swift and VideoConsole.swift carry their own lines.

Note for the orchestrator: `Scripts/diff_cli.py` does not scan `VideoConsole.Help` (DICOMKit) for the tool's help; the A-1 name/UID check therefore reports 0 rows for dicom-video. `<scratch>/vid_checks.py` does it.

### dicom-pdf (G3) — 2026-10-01

Scope: all 16 declarations found by `--list-surface` (19 after this pass), the Encapsulated PDF IOD (PS3.3 2026a A.45.1, Table A.45.1-1) and its mandatory modules, both directions.

Compared by script (`<scratch>/pdf_rt_diff.py`): a 329-byte (odd) PDF encapsulated with a non-ASCII name and extracted again; the dataset diffed against Tables C.7-1, C.7-3, C.24-1, C.7-8, C.8-24, C.24-2, C.12-1 (Type 1/2 rows, VRs from PS3.6 Table 6-1) plus value checks.
- Before: 26 Type 1/2 attributes present and right; **3 value checks wrong** — Encapsulated Document Length (0042,0015) absent, Specific Character Set (0008,0005) absent while "Müller^Jörg" was written as UTF-8, extracted PDF 330 bytes (padding 0x00 kept). CDA could not be encapsulated at all (HL7 Instance Identifier Type 1C, no option). Conversion Type and Burned In Annotation fixed at WSD / YES with no option.
- After: Type 1/2 matched 26, wrong 0, missing 0; value checks 10/10 (SOP Class 1.2.840.10008.5.1.4.1.1.104.1 = Media Storage SOP Class; MIME application/pdf (A.45.1.4.1); Burned In Annotation YES/NO; Conversion Type a C.8-24 term; OB even length; (0042,0015) = document length = VL or VL−1; ISO_IR 192 exactly when text is non-ASCII; extracted bytes identical). CDA round trip identical, (0040,E001) "root^extension" from /ClinicalDocument/id, MIME text/XML (A.45.2.4).
- Vocabularies: Conversion Type 8 Defined Terms (DV DI DF WSD SD SI DRW SYN, Table C.8-24, dumped) = builder list; Modality default DOC, M3D enforced for STL/OBJ/MTL (A.85.x.4.3, engine); SOP Class UIDs .104.1–.104.5 in README = Table A-1 names.

Counts (contract, 25 rows): matched 13, wrong 1, missing 5, extra 0, plumbing 6 (all wrong/missing fixed).

#### Input contract

| Option | DICOM concept | 2026a reference | Allowed per standard | Code accepts | Default std | Default code | Verdict |
|---|---|---|---|---|---|---|---|
| <input>, --output, --recursive, --show-metadata, --verbose, --strict-modality | — | PS3.10 7.1 | — | — | — | — | plumbing |
| --extract | Encapsulated Document (0042,0011) → file | C.24-2 (0042,0015) "not including any trailing padding" | unpadded bytes | padded value written | — | — | wrong → fixed |
| --patient-name | Patient's Name (0010,0010) | C.7-1 Type 2 | PN | required string | — | — | match (help fixed; charset fixed) |
| --patient-id | Patient ID (0010,0020) | C.7-1 Type 2 | LO | required | — | — | match |
| --title | Document Title (0042,0010) | C.24-2 Type 2 | ST | any | empty | empty | match |
| --study-uid / --series-uid | (0020,000D) / (0020,000E) | C.7-3 / C.24-1 Type 1 | UID | any | — | generated | match |
| --modality | Modality (0008,0060) | C.24-1 Type 1 (C.7.3.1.1.1); A.85.x.4.3 M3D | Defined Terms; M3D for 3D | any; M3D enforced for 3D | — | DOC / M3D | match |
| --series-description | (0008,103E) | C.24-1 Type 3 | LO | any | — | absent | match |
| --series-number | (0020,0011) | C.24-1 Type 1 | IS | Int | — | 1 | match |
| --instance-number | (0020,0013) | C.24-2 Type 1 | IS | Int | — | 1 (batch increments) | match |
| --conversion-type (new) | Conversion Type (0008,0064) | C.8-24 Type 1 | 8 Defined Terms | 8 terms, case-insensitive | — | WSD | missing → added |
| --burned-in-annotation (new) | Burned In Annotation (0028,0301) | C.24-2 Type 1 | YES, NO | YES, NO | — | YES | missing → added |
| --hl7-instance-identifier (new) | HL7 Instance Identifier (0040,E001) | C.24-2 Type 1C (CDA) | UID[^Extension] | string; CDA only; single file | — | /ClinicalDocument/id | missing → added |
| (0042,0015), (0008,0005) | Encapsulated Document Length; Specific Character Set | C.24-2 Type 3; C.12-1 Type 1C, C.12-5 | | | | | missing → fixed |
| (sop-class), (mime-type), (concept-name-code), (source-instance-sequence) | | A-1; A.45.1.4.1; C.24-2 | | | | | match |

#### Output contract

| Output | Concept | Verdict |
|---|---|---|
| "Encapsulated: <path>", "Extracted: <path>", batch "Successful/Failed/Study UID/Series UID/Output directory" | plumbing | plumbing |
| --show-metadata "Type", "MIME Type", "Size", "SOP Class", "SOP Instance", "Title", "Name", "ID", "Study UID", "Series UID", "Modality", "Series Description", "Series Number", "Instance Number" | shared DICOMKit `metadataReport()`; short labels of C.24-2/C.7-x attributes | match, except "Size" = padded value length (D181) |
| exit codes: 0 success; 64 usage / ValidationError; 1 other errors; batch exits 0 even when files fail | tool-defined | plumbing |

#### Changes

- `Sources/dicom-pdf/EncapsulationAttributes.swift` (new): (0042,0015) + ISO_IR 192 completion, padding cut on extraction, Conversion Type / Burned In Annotation vocabularies, CDA `/ClinicalDocument/id` reader.
- `Sources/dicom-pdf/main.swift`: one `encapsulatedDataSet(...)` for single and batch; new options; extraction (single and batch) cut to (0042,0015); help "Patient's Name", "Document Title (0042,0010)", M3D rule; CDA/SD examples; marker.
- `Sources/dicom-pdf/README.md`: new options, references corrected (A.45 → A.45.1, + A.85, C.24.1/C.24.2, C.8.6.1, C.12.1; "PS3.5 Section 8.2: Transfer Syntax (Explicit VR Little Endian)" → PS3.5 A.2).
- `Tests/dicom-pdfTests/EncapsulationAttributesTests.swift` (7 tests), new `dicom-pdfTests` target in Package.swift (own hunk only, committed through a temporary index).
- Commit **3c739850** (with CHANGELOG bullet).

Tests: `swift test --filter EncapsulationAttributesTests` 7 passed. `swift build --product dicom-pdf` ok; `check_nema_markers.py Sources/dicom-pdf`: 2/2 files.

P-items: none (all changes additive).

#### Deferred findings

| D182 | DICOMKit | Sources/DICOMKit/EncapsulatedDocument/EncapsulatedDocumentBuilder.swift:485 (`buildDataSet`), :560 (`toDataSet`) | Builder writes neither Encapsulated Document Length (0042,0015) nor Specific Character Set (0008,0005) for non-ASCII text (UTF-8 bytes written); dicom-pdf now adds both itself, the DICOMStudio Workshop path does not | PS3.3 2026a Table C.24-2; Table C.12-1 (Type 1C), Table C.12-5 | Low | ✅ 2026-10-01 (`51ef296a`) — see the deferred-findings table above |
| D181 | DICOMKit | Sources/DICOMKit/EncapsulatedDocument/EncapsulatedDocumentParser.swift:54; EncapsulatedDocumentWorkflow.swift:99 | `documentData` is the padded value; (0042,0015) is ignored, so an odd-length document gains a 0x00 and `metadataReport()` "Size" shows the padded length (dicom-pdf now cuts it itself) | PS3.3 2026a Table C.24-2 (0042,0015) | Low | ✅ 2026-10-01 (`51ef296a`) — see the deferred-findings table above |

Marker text (main.swift): `// NEMA-verified: 2026a, checked 2026-10-01 — input/output contract of all 19 option/flag/argument declarations by script: Encapsulated PDF Storage 1.2.840.10008.5.1.4.1.1.104.1 (PS3.6 2026a Table A-1); a round trip of an odd-length PDF diffed against PS3.3 2026a Tables A.45.1-1, C.7-1, C.7-3, C.24-1, C.7-8, C.8-24, C.24-2, C.12-1 (every Type 1/2 attribute present; (0042,0015) and (0008,0005) added here, padding byte stripped on extraction); --modality default DOC / M3D (C.24-1, A.85.x.4.3); --conversion-type 8 Defined Terms (C.8-24); --burned-in-annotation YES/NO and --hl7-instance-identifier (C.24-2); see EncapsulationAttributes.swift`; EncapsulationAttributes.swift carries its own line.

Note: DICOMStudio CLI Workshop does not yet offer the three new dicom-pdf options (Studio files untouched by rule).

### dicom-compress (G3) — verified 2026-10-01

Compared: `diff_cli.py --list-surface` (21 options, 5 subcommands; the extractor lists only `dicom-compress` and `backends` as commands because compress/decompress/info/batch take their names from the struct — noted, not changed); `diff_cli.py --tool dicom-compress` (11 checks ok, 0 FAIL); the 25 codec/syntax help rows (alias → engine UID → PS3.6 2026a Table A-1 name) were diffed by script earlier today (24 match, 1 fixed in `dfc929c`, D9) and are now pinned by `dicom-compressTests`. Output: `compress` with 8 codecs on pydicom RGB / 16-bit fixtures, `decompress` of YBR_RCT / YBR_ICT JPEG 2000, `info` (text, JSON), codestream COD/TLM parsed by script (`scratch/g3c/fx/cod.py`) against PS3.5 2026a 8.2.4 / 8.2.14 / Tables 8.2.4-1, 8.2.14-1 / 10.18.1 and PS3.3 C.7.6.1.1.5 (texts dumped by `sect.py`).

Counts: matched 2, wrong 0, missing 0, extra 2, plumbing 17.

**Input contract**

| Option | DICOM concept | 2026a reference | Allowed (standard) | Code accepts | Default std | Default code | Verdict |
|---|---|---|---|---|---|---|---|
| compress `<input>` | PS3.10 file | PS3.10 Table 7.1-1 | — | path | — | — | plumbing |
| compress `--output` | output PS3.10 file | PS3.10 7.1 | — | path (directory resolved to file) | — | — | plumbing |
| compress `--codec` | Transfer Syntax UID + intent | PS3.6 Table A-1; PS3.5 A.4.1–A.4.4, A.4.12, Table 8.2.1-1 | Table A-1 UIDs | 23 names → 21 UIDs (25 help rows) | — | required | match (D9 fixed in `dfc929c`; test added) |
| compress `--quality` | irreversible quality; ratio recorded in (0028,2112) | PS3.3 C.7.6.1.1.5.2 | — | maximum/high/medium/low/0.0–1.0 | — | engine default | plumbing |
| compress `--verbose`, `--backend` | — | — | — | auto/metal/accelerate/scalar | — | auto | plumbing |
| decompress `<input>`, `--output`, `--verbose` | — | PS3.10 7.1 | — | — | — | — | plumbing |
| decompress `--syntax` | native Transfer Syntax | PS3.6 Table A-1; PS3.5 A.1, A.2 | 1.2.840.10008.1.2.1, 1.2.840.10008.1.2 | explicit-le, implicit-le (names match A-1) **and every codec name** (`--syntax jpeg2000` writes encapsulated .91) | — | explicit-le | extra (P-COMPRESS-SYNTAX) |
| info `<input>`, `--json` | — | — | — | — | — | — | plumbing |
| batch `<input>`, `--output`, `--decompress`, `--quality`, `--recursive`, `--verbose` | — | — | — | — | — | — | plumbing |
| batch `--codec` | as compress | PS3.6 Table A-1 | | same table | | | match |
| batch `--syntax` | as decompress | PS3.6 Table A-1 | | same as decompress | | explicit-le | extra (P-COMPRESS-SYNTAX) |
| backends `--json` | — | — | — | — | — | — | plumbing |

**Output contract**

| Output | 2026a reference | Code | Verdict |
|---|---|---|---|
| info "Transfer Syntax UID", "Bits Allocated", "Bits Stored", "Photometric Interpretation" | PS3.6 Table 6-1 names | as standard | match |
| info "Samples Per Pixel" | PS3.6 Table 6-1 "Samples per Pixel" | capital P (CompressionConsole, DICOMKit) | wrong (engine, D183) |
| info "Transfer Syntax" | PS3.6 Table A-1 | engine short display name (DICOMCore policy) + intent for .91/.93/.203/.112 from (0028,2110) | match (policy) |
| info "Lossless" | PS3.3 C.7.6.1.1.5 | from (0028,2110) for the general UIDs | match |
| info `--json` keys | PS3.6 keywords | `transferSyntaxUID`, `bitsAllocated`, `samplesPerPixel`, `rows`, … tool camelCase | plumbing (P-COMPRESS-JSON) |
| compress "Compression ratio: 12.0%" | PS3.3 C.7.6.1.1.5.2 (ratio N:1) | output/input size in % | wrong (engine, D183) |
| lossy output (0028,2110) "01", (0028,2112) ratio, (0028,2114) ISO_10918_1 / ISO_14495_1 / ISO_15444_1 / ISO_15444_15 / ISO_18181_1, Image Type DERIVED | PS3.3 C.7.6.1.1.5, C.7.6.1.1.5.1 | as standard (5 lossy codecs on fixture) | match |
| lossy output SOP Instance UID | PS3.3 C.7.6.1.1.5 ("shall receive a new SOP Instance UID") | source UID kept | wrong (engine, D184) |
| J2K/HTJ2K colour output PI | PS3.5 8.2.4, 8.2.14, Tables 8.2.4-1 / 8.2.14-1 | RGB while COD MCT = 1 | wrong (engine, D185) |
| decompress of YBR_RCT / YBR_ICT | PS3.5 8.2, 8.2.4 | native RGB samples labelled YBR_RCT / YBR_ICT | wrong (engine, D186) |
| .202 codestream | PS3.5 10.18.1 | LRCP, no TLM | wrong (codec dependency, D187) |
| File Meta UI values | PS3.5 6.2, 7.1 | odd length, unpadded | wrong (engine, D188) |
| exit codes | — | 0 ok, 1 failure (batch: any file failed), 64 invalid arguments | plumbing |

Changes: `d944a32e` docs(cli): new test target `dicom-compressTests` (3 tests: every compress/decompress help row resolves to the UID and intent it shows and uses the Table A-1 name's words; "Lossless Only" only where A-1 has it); README codec table (13 rows, some naming PS3.6 keywords of other UIDs) replaced by the 23 rows with UID, A-1 name, encoding; marker extended. No behaviour change, so no CHANGELOG bullet.

Tests: `swift test --filter dicom_compressTests` 3/3 pass; `swift build --product dicom-compress` ok; `check_nema_markers.py Sources/dicom-compress` 1/1.

Marker (`main.swift`): `// NEMA-verified: 2026a, checked 2026-10-01 — the 25 codec/syntax help rows (alias → UID → name) diffed by script against PS3.6 2026a Table A-1 and the engine codec table: 24 match, 1 fixed (.4.110 is "JPEG XL Lossless", D9), now pinned by dicom-compressTests; JPEG Extended 8/12-bit per PS3.5 2026a Table 8.2.1-1; the cited PS3.5 A.4.4 / A.4.12 section titles confirmed; 21 options classified (input contract); compressed / decompressed output checked on fixtures against PS3.3 C.7.6.1.1.5 and PS3.5 8.2, 8.2.4, 8.2.14, 10.18.1 (engine findings deferred)`

P-items:
- **P-COMPRESS-SYNTAX** — `decompress --syntax` / `batch --syntax` accept every codec name (validation calls the full codec table); `--syntax jpeg2000` "decompresses" into encapsulated .91. Proposal: accept only native targets (explicit-le, implicit-le, deflate, retired explicit-be) as the help and the error text already say.
- **P-COMPRESS-JSON** — `info --json` keys are tool camelCase; proposal: add PS3.6 keywords (TransferSyntaxUID, Rows, Columns, BitsAllocated, BitsStored, SamplesPerPixel, PhotometricInterpretation, LossyImageCompression).

Deferred findings:

| D184 | DICOMKit | Sources/DICOMKit/Compression/CompressionManager.swift:552-591 | Lossy compress records (0028,2110/2112/2114) and DERIVED but keeps the SOP Instance UID and (0002,0003): rgb8.dcm → jpeg, jpeg2000, htj2k, jpeg-ls, jpeg-xl outputs all carry the source UID | PS3.3 2026a C.7.6.1.1.5 ("if the predecessor was a DICOM image, then the Image shall receive a new SOP Instance UID") | High | ✅ 2026-10-01 (`d37433f0`) — see the deferred-findings table above |
| D185 | DICOMKit | Sources/DICOMKit/Compression/CompressionManager.swift:451-530 (encodePixelDataInPlace) | After a JPEG 2000 / HTJ2K encode of a 3-sample image the codestream has COD MCT = 1 (RCT with 5-3, ICT with 9-7) but Photometric Interpretation stays RGB (fixtures out_rgb_jpeg2000/-lossless/htj2k/htj2k-rpcl) | PS3.5 2026a 8.2.4, 8.2.14 ("No other Value of Photometric Interpretation than YBR_RCT or YBR_ICT is permitted when SGcod Multiple component transformation type is 1"), Tables 8.2.4-1, 8.2.14-1 | High | ✅ 2026-10-01 (`d37433f0`) — see the deferred-findings table above |
| D186 | DICOMKit | Sources/DICOMKit/Compression/CompressionManager.swift:593-680 (decodePixelDataInPlace) | Decompressing a YBR_RCT / YBR_ICT JPEG 2000 file writes native RGB samples labelled YBR_RCT / YBR_ICT (only JPEG YBR and XYB are relabelled) | PS3.5 2026a 8.2 (native PI "shall be other than YBR_RCT, YBR_ICT, YBR_PARTIAL_420"), 8.2.4 ("will be changed to RGB") | High | ✅ 2026-10-01 (`d37433f0`) — see the deferred-findings table above |
| D187 | DICOMCore (J2KSwift dependency) | Sources/DICOMCore/J2KRoutePlanner.swift:324-326; J2KSwiftCodec.swift:509-528; .build/checkouts/J2KSwift/Sources/J2KCodec/J2KEncoderPipeline.swift:6454 | 1.2.840.10008.1.2.4.202 output has COD progression LRCP (the encoder always writes 0 whatever `progressionOrder` says) and no TLM marker segment, while the markers claim RPCL is satisfied; seen via dicom-compress `htj2k-rpcl-lossless-only` and dicom-j2k `transcode` (which now warns) | PS3.5 2026a 10.18.1 (RPCL, base resolution ≤ 64, TLM shall be present) | Medium | ✅ 2026-10-01 (`4ed69751`) — see the deferred-findings table above |
| D188 | DICOMKit | Sources/DICOMKit/Compression/CompressionManager.swift:904-933 | File Meta UI values (0002,0002), (0002,0003), (0002,0010) are written with odd length and no trailing NULL (DCMTK: "Length of element (0002,0002) is odd") | PS3.5 2026a 6.2 (UI padding), 7.1 (even Value Length); PS3.10 7.1 | Medium | ✅ 2026-10-01 (`d37433f0`) — see the deferred-findings table above |
| D183 | DICOMKit | Sources/DICOMKit/Compression/CompressionConsole.swift:83-89, 324 | "Compression ratio: 12.0%" is output/input size in percent, not the N:1 ratio PS3.3 defines for (0028,2112); info label "Samples Per Pixel" (PS3.6: "Samples per Pixel") | PS3.3 2026a C.7.6.1.1.5.2; PS3.6 2026a Table 6-1 | Low | ✅ 2026-10-01 (`d37433f0`) — see the deferred-findings table above |
| D189 | DICOMKit | Sources/DICOMKit/Compression/CompressionManager.swift:583 | Comment cites "PS3.3 C.7.6.1.1.5.1: shall be set to DERIVED"; that sentence is in C.7.6.1.1.5 (C.7.6.1.1.5.1 is Lossy Image Compression Method) | PS3.3 2026a C.7.6.1.1.5 | Low | ✅ 2026-10-01 (`d37433f0`) — see the deferred-findings table above |
| D190 | DICOMCore | JPEG Baseline encoder (default `.jli` engine, CodecRegistry) | .4.50 colour output carries a JFIF APP0 segment and YCbCr 4:4:4 components while Photometric Interpretation is RGB; PS3.5 recommends JFIF be absent and not relied on, and Table 8.2.1-1 allows YBR_FULL_422 or RGB only | PS3.5 2026a 8.2.1, Table 8.2.1-1 | Low | ✅ 2026-10-01 (`4ed69751`) — see the deferred-findings table above |

### dicom-convert (G3) — verified 2026-10-01

Compared: `diff_cli.py --list-surface` (13 options) and `--tool dicom-convert` (11 checks ok, 0 FAIL); `--transfer-syntax` vocabulary (DICOMConverter catalog, 25 targets → 21 UIDs) diffed by script (`scratch/g3c/diff_convert_ts.py`) against the PS3.6 2026a Table A-1 keyword column: 11 keywords accepted for the same UID, 3 catalog names are A-1 keywords of another UID, 7 A-1 keywords not accepted; PS3.3 2026a C.11.2.1.2.1 / C.11.2.1.2.2 (window), PS3.5 7.8.1 (private elements) dumped by `sect.py`; output run on pydicom fixtures (lossy J2K/JPEG, YBR_RCT/YBR_ICT decode, nested private tags, colour window, batch with a bad file).

Counts: matched 3, wrong 1, missing 1, extra 0, plumbing 8.

**Input contract**

| Option | DICOM concept | 2026a reference | Allowed (standard) | Code accepts | Default std | Default code | Verdict |
|---|---|---|---|---|---|---|---|
| `<input-path>` | PS3.10 file / directory | PS3.10 7.1 | — | path (directory needs `--recursive`) | — | — | plumbing |
| `--output` | output path | — | — | path | — | — | plumbing |
| `--transfer-syntax` | Transfer Syntax UID + intent | PS3.6 Table A-1 (keyword); PS3.5 A.1–A.4 | A-1 keywords / UIDs of 21 targets | 25 catalog names + UIDs; now + DeflatedExplicitVRLittleEndian, JPEGBaseline8Bit, JPEGExtended12Bit, JPEG2000MCLossless, JPEG2000MC, JPEGXLJPEGRecompression, HTJ2KLosslessRPCL | — | required for `--format dicom` | missing → fixed (7); 3 collisions → P-CONVERT-TS-KEYWORDS |
| `--format` | DICOM vs raster | — | — | dicom, png, jpeg, tiff | — | dicom | plumbing |
| `--quality` | JPEG raster quality | — | — | 1–100 (out of range now refused) | — | 90 | plumbing |
| `--apply-window` | VOI LINEAR | PS3.3 C.11.2.1.2.1 | — | flag (stored window by default) | — | off | plumbing |
| `--window-center` | Window Center (0028,1050) | PS3.3 C.11.2.1.2.1 | DS | Double | — | stored | match |
| `--window-width` | Window Width (0028,1051) | PS3.3 C.11.2.1.2.1 "shall always be greater than or equal to 1" | ≥ 1 | any Double (0, 0.5 accepted) → now ≥ 1 | — | stored | wrong → fixed |
| `--frame` | frame | PS3.3 C.7.6.6 / C.7.6.16 (numbered from 1) | 1…n | 0-based index; negative now refused | — | 0 | match by design (P-CONVERT-FRAME) |
| `--recursive` | — | — | — | flag | — | off | plumbing |
| `--strip-private` | Private Data Elements | PS3.5 7.8, 7.8.1 | odd groups, incl. inside items | top-level only (engine) | — | off | match (engine gap D191) |
| `--validate` | re-read output | PS3.10 7.1 | — | flag (spelling kept; property renamed to allow `validate()`) | — | off | plumbing |
| `--force` | no preamble/DICM | PS3.10 7.1 | — | flag | — | off | plumbing |

**Output contract**

| Output | 2026a reference | Code | Verdict |
|---|---|---|---|
| "Transcoded from <UID> to <UID> (lossless/lossy)" (ConvertConsole) | PS3.6 Table A-1 UIDs | UIDs | match |
| lossy output (0028,2110/2112/2114), Image Type DERIVED | PS3.3 C.7.6.1.1.5 | set (c_lossy.dcm, c_jpeg.dcm) | match |
| lossy output SOP Instance UID | PS3.3 C.7.6.1.1.5 | source UID kept | wrong (engine, D192) |
| J2K encode of RGB / decode of YBR_RCT, YBR_ICT | PS3.5 8.2, 8.2.4 | RGB under MCT 1; native labelled YBR_RCT / YBR_ICT | wrong (engine, D193) |
| `--strip-private` | PS3.5 7.8.1 | nested (0011,0010)/(0011,1001) kept | wrong (engine, D191) |
| window on colour export | PS3.3 C.11.2.1.2.2 (no meaning for non-MONOCHROME) | not applied (identical PNG) | match |
| exit codes | — | 0; 1 single-file failure; 64 bad arguments / missing input; directory run exits 0 with failed files | plumbing (P-CONVERT-EXIT); README listed 1–4, corrected |

Changes: `55f7fc75` fix(cli): `TransferSyntaxKeywords.swift` (7 A-1 keywords, catalog tried first so nothing is shadowed; help names the 3 collisions); `validate()` (window width ≥ 1, quality 1–100, frame ≥ 0); README (target list, 0-based frames, real exit codes, `--strip-private` not de-identification, impossible "export all frames" example removed); CHANGELOG bullet; new test target `dicom-convertTests` (8 tests).

Tests: `swift test --filter dicom_convertTests` 8/8 pass; `swift build --product dicom-convert` ok; `check_nema_markers.py Sources/dicom-convert` 2/2.

Markers: `DICOMConvert.swift` `// NEMA-verified: 2026a, checked 2026-10-01 — 13 options classified against PS3.6 2026a Table A-1 (--transfer-syntax: 25 catalog targets, 21 UIDs; A-1 keywords 11 match, 3 name another UID (P-item), 7 added in TransferSyntaxKeywords.swift), PS3.3 C.11.2.1.2.1 (--window-width ≥ 1, now enforced), C.7.6.16 (--frame 0-based, P-item), PS3.5 7.8 (--strip-private, engine deferred), PS3.10 7.1 (--force); DICOM output checked on fixtures against PS3.3 C.7.6.1.1.5 and PS3.5 8.2, 8.2.4 (engine findings deferred)`; `TransferSyntaxKeywords.swift` `// NEMA-verified: 2026a, checked 2026-10-01 — the 7 keyword → UID rows below are PS3.6 2026a Table A-1 rows (keyword column) whose keyword the shared DICOMConverter catalog does not accept; diffed by script against the 21 target UIDs of the catalog (A-1 keywords: 11 accepted for the same UID, 3 accepted for another UID (P-item), 7 added here)`

P-items:
- **P-CONVERT-TS-KEYWORDS** — `JPEG2000Lossless`, `HTJ2KLossless`, `JPEGXLLossless` (DICOMConverter catalog; also `TransferSyntax.parseEncoding` "jpeg2000lossless"/"htj2klossless") select the reversible encode into .91 / .203 / .112, but in PS3.6 Table A-1 these keywords name .90 / .201 / .110. Proposal: deprecate the three catalog spellings (e.g. `JPEG2000Reversible`, `HTJ2KReversible`, `JPEGXLReversible`) and let the A-1 keywords select their A-1 UIDs.
- **P-CONVERT-FRAME** — `--frame` is a 0-based index; DICOM frames are numbered from 1 (same as P-EXPORT-1 / P-SPLIT-1).
- **P-CONVERT-EXIT** — a directory run exits 0 when files fail (dicom-compress batch exits 1); proposal: exit 1.

Deferred findings:

| D192 | DICOMKit | Sources/DICOMKit/DICOMConverter.swift:488-491 (applyLossyProvenance) | A lossy convert records (0028,2110/2112/2114) and DERIVED but keeps the SOP Instance UID (c_lossy.dcm, c_jpeg.dcm) | PS3.3 2026a C.7.6.1.1.5 | High | ✅ 2026-10-01 (`d37433f0`) — see the deferred-findings table above |
| D193 | DICOMCore | Sources/DICOMCore/TransferSyntaxConverter.swift:791-826 | J2K → native keeps PI YBR_RCT / YBR_ICT over RGB samples (only XYB and JPEG YBR are relabelled); RGB → J2K leaves PI RGB with COD MCT = 1 | PS3.5 2026a 8.2, 8.2.4, Table 8.2.4-1 | High | ✅ 2026-10-01 (`4ed69751`) — see the deferred-findings table above |
| D191 | DICOMKit | Sources/DICOMKit/DICOMConverter.swift:340-352 | `stripPrivate` filters the top-level Data Set only; a Private Creator and Private Data Element inside a Sequence Item survive (fixture priv.dcm: (0011,0010)/(0011,1001) in Referenced Image Sequence) | PS3.5 2026a 7.8.1 (Items are self-contained Data Sets with their own Private Data Elements) | Medium | ✅ 2026-10-01 (`d37433f0`) — see the deferred-findings table above |

### dicom-j2k (G3) — verified 2026-10-01

Compared: `diff_cli.py --list-surface` (33 options, 8 subcommands) and `--tool dicom-j2k` (11 checks ok, 0 FAIL — the generic UID check did not see the help UID rows); the 7 UID/name rows of the help and the 10 `transcode --target` rows diffed by script (`scratch/g3c/diff_j2k_help.py`) against PS3.6 2026a Table A-1: 7 names wrong (fixed), 10 target rows match (alias → UID → intent, now also pinned by a test). DICOM boundary checked by script on pydicom / dicom-compress fixtures (single, 3-frame, 3-frame with 2 fragments per frame with and without Basic Offset Table, RGB) against PS3.5 2026a A.4, A.4.4, 8.2, 8.2.4, 8.2.14, Tables 8.2.4-1 / 8.2.14-1, 10.18.1 and PS3.3 2026a C.7.6.1.1.2, C.7.6.1.1.5, C.7.6.1.1.5.1–2, C.7.6.2.1.1 (all dumped by `nema_docbook.py` / `sect.py`); codestream COD/TLM parsed by script (`scratch/g3c/fx/cod.py`). Codestream internals (ISO/IEC 15444) out of scope.

Counts: matched 5, wrong 4, missing 0, extra 0, plumbing 24.

**Input contract**

| Option | DICOM concept | 2026a reference | Allowed (standard) | Code accepts | Default std | Default code | Verdict |
|---|---|---|---|---|---|---|---|
| info / validate / roi / benchmark `--frame` | frame of encapsulated Pixel Data | PS3.5 A.4, A.4.4 (a frame may span fragments; 8.2: not supporting this is non-conformance) | frames 1…n | 0-based; was `fragments[i]` → fragmented frames failed; now EOT → BOT → one per frame → single → SOC | — | 0 | match (lookup fixed; 0-based P-J2K-FRAME) |
| transcode `--target` | Transfer Syntax UID + intent | PS3.6 Table A-1; PS3.5 A.4.4, 10.18.1 | .90–.93, .201–.203 | 10 names (+ parseEncoding aliases, UIDs) → 7 UIDs, all match | — | required | match (output fixed, see below) |
| transcode `--quality` | irreversible quality → (0028,2112) | PS3.3 C.7.6.1.1.5.2 | — | 0.0–1.0, was never passed to the encoder (q 0.1/0.5/0.95 gave 270 bytes each) | — | 0.9 | wrong → fixed |
| reduce `--levels` | decomposition levels (COD) | PS3.5 10.18.1 (.202: base resolution ≤ 64) | ≥ minimum for .202 | 1–10; below the .202 minimum now refused | — | — | wrong → fixed |
| reduce `--layers` | quality layers | ISO (out of scope) | — | 1–20 | — | — | plumbing |
| roi `--region` | crop → Rows / Columns, Image Position (Patient) | PS3.3 C.7.6.3, C.7.6.2.1.1 | x, y ≥ 0 | negative origin was accepted; now refused; ≤ 65535 | — | required | wrong → fixed |
| compare `<test>` (and `<reference>`) | samples per Bits Allocated / Pixel Representation / Samples per Pixel | PS3.3 C.7.6.3 | — | native 16-bit read per byte, colour J2K first component only → "Pixel count mismatch"; now shared pixel pipeline | — | — | wrong → fixed |
| all other options (paths, `--json`, `--verbose`, `--strict`, `--iterations`, `<shell>`, compare `--frame`) | — | — | — | — | — | — | plumbing (24) |

**Output contract**

| Output | 2026a reference | Before | Now | Verdict |
|---|---|---|---|---|
| help UID list (7 rows) | PS3.6 Table A-1 | "JPEG 2000 Lossless Only", "JPEG 2000 (Lossless or Lossy)", "HTJ2K Lossless Only (RPCL)", … | Table A-1 names verbatim | wrong → fixed |
| transcode target table (10 rows) | PS3.6 Table A-1 | intent glosses of the A-1 names | unchanged | match |
| PI after transcode / reduce / roi | PS3.5 8.2.4, 8.2.14, Tables 8.2.4-1 / 8.2.14-1 | source PI copied (RGB with MCT 1) | YBR_RCT (MCT, 5-3) / YBR_ICT (MCT, 9-7) / RGB for a YBR source re-encoded without MCT; Planar Configuration 0 | wrong → fixed |
| lossy transcode provenance | PS3.3 C.7.6.1.1.5, .1, .2 | none | (0028,2110) "01", Ratio / Method (ISO_15444_1, ISO_15444_15) appended, Derivation Description, DERIVED, new SOP Instance UID + (0002,0003) | missing → fixed |
| roi output | PS3.3 C.7.6.1.1.2, C.7.6.2.1.1, C.7.6.16 | same SOP Instance UID, Number of Frames 3 with 1 fragment, IPP of the full image | new UID, DERIVED, Derivation Description, Number of Frames 1, kept Per-frame FG item, IPP of the crop origin | wrong → fixed |
| reduce / roi of HTJ2K sources | PS3.5 A.4.4, 8.2.14 | Part 1 codestream under the HTJ2K UID | HTJ2K block coder | wrong → fixed |
| .202 codestream | PS3.5 10.18.1 | LRCP, no TLM, silent | RPCL + levels requested; warning names what is still missing (encoder, D187) | wrong → warned |
| (0002,0000) after a meta change | PS3.10 Table 7.1-1 | stale (DCMTK: incorrect value) | recomputed | wrong → fixed |
| validate exit code | tool contract ("2 = read error") | 64 | 2 | wrong → fixed |
| info "Transfer Syntax: <name> (<UID>)" | PS3.6 Table A-1 | engine short display name | unchanged (DICOMCore policy) | match (policy) |
| JSON keys (info, validate, benchmark, compare) | — | tool camelCase; compare `pixelCount` counts samples | unchanged | plumbing (P-J2K-JSON) |

Changes: `363fd82c` fix(cli): `J2KDICOMBoundary.swift` (frame mapping, codestream COD/TLM facts, PI rule, lossy provenance, derived image, ROI geometry, .202 checks); `main.swift` uses it in all subcommands, `--quality` passed to the encoder, validate exit 2, help/abstract/completions corrected, `--backends` example removed; README rewritten (A-1 names, no false "fast-path, no pixel decode" / "nearest-neighbour" / SSIM claims); `dicom-j2kTests` now depends on the tool (26 new tests incl. end-to-end transcode / roi / compare on engine-made fixtures); CHANGELOG bullet.

Tests: `swift test --filter dicom_j2kTests` 79/79 pass (53 existing + 26 new); `swift build --product dicom-j2k` ok; `check_nema_markers.py Sources/dicom-j2k` 2/2.

Markers: `main.swift` `// NEMA-verified: 2026a, checked 2026-10-01 — the 7 UID/name rows of the help diffed by script against PS3.6 2026a Table A-1 (7 wrong names fixed) and the 10 transcode target rows (alias → UID → intent, 10 match); 33 options classified (input contract); frame lookup, Photometric Interpretation, lossy provenance, derived-image and .202 handling moved to J2KDICOMBoundary.swift (PS3.5 A.4.4, 8.2.4, 8.2.14, 10.18.1; PS3.3 C.7.6.1.1.2, C.7.6.1.1.5); --quality now reaches the encoder; validate exits 2 on read errors as documented`; `J2KDICOMBoundary.swift` `// NEMA-verified: 2026a, checked 2026-10-01 — DICOM boundary of the J2K re-encodes: frame → fragment mapping per PS3.5 2026a A.4 / A.4.4 (Extended and Basic Offset Table, one fragment per frame, single frame, SOC-delimited frames); Photometric Interpretation after encode per PS3.5 2026a 8.2.4 / 8.2.14 and Tables 8.2.4-1 / 8.2.14-1 (MCT 1 → YBR_RCT (5-3) or YBR_ICT (9-7), Planar Configuration 0); lossy provenance per PS3.3 2026a C.7.6.1.1.5, C.7.6.1.1.5.1 (ISO_15444_1 / ISO_15444_15 via TransferSyntax), C.7.6.1.1.5.2; derived images per C.7.6.1.1.2 (Image Type Value 1 DERIVED, new SOP Instance UID, PS3.10 Table 7.1-1 (0002,0003)); ROI geometry per C.7.6.2.1.1 and C.7.6.16 (Number of Frames, Per-frame Functional Groups); .202 RPCL / ≤64 base resolution / TLM per PS3.5 2026a 10.18.1`

Notes: `validate` reports violations (exit 1) on a J2KSwift-written .90 codestream (ct16_j2k.dcm) — ISO/IEC 15444 conformance, out of scope, not deferred. Input fixtures from dicom-compress carry the odd-length (0002,0002) of D188; dicom-j2k copies the source meta and does not repair it.

P-items:
- **P-J2K-FRAME** — `--frame` on info/validate/roi/benchmark/compare is a 0-based index and info prints "Frame: 0 of N"; DICOM frames are numbered from 1 (as P-EXPORT-1 / P-SPLIT-1).
- **P-J2K-PART2** — `transcode --target j2k-part2-*` writes a Part 1 codestream (Rsiz 0, no Annex J MCT) under .92 / .93, while the engine refuses Part 2 encodes (J2KRoutePlanner.unsupportedEncodeReason). PS3.5 A.4.4 defines .92/.93 as the use of the Part 2 multi-component extensions; proposal: refuse the three targets as the engine does, or confirm that a Part 1 codestream is acceptable.
- **P-J2K-JSON** — JSON keys are tool camelCase (`transferSyntaxUID`, `totalFrames`, `pixelCount` = sample count); proposal: PS3.6 keywords where a DICOM attribute is meant (TransferSyntaxUID, NumberOfFrames).

Deferred findings: none new for dicom-j2k itself; the .202 encoder gap is D187 (dicom-j2k now warns).


## G4 Derived objects

### dicom-measure (G4)

Commands: dicom-measure, distance, area, angle, roi, hu, pixel · files: MeasurementEngine.swift, main.swift (README.md surface) · commit `0fbc334f`

**Standard extracted by script** (scratch/meas/: `sect.py`, `grep_para.py`, `nema_docbook.py table`): PS3.3 2026a 10.7.1.1–10.7.1.3 and Table 10-10 (Basic Pixel Spacing Calibration Macro; GEOMETRY / FIDUCIAL); Table C.7.6.16-2 (Pixel Measures, 3 rows); every table row for (0018,1164) / (0018,2010) / (0028,0A02/0A04) / (0018,6024/602C) (Tables C.8-2, C.8-17, C.8-25, C.8-25b, C.8-27, C.8-71, C.8-77, C.8.19.6-4); C.8.5.5.1.1/.14/.15/.17 (Physical Units: 13 Enumerated Values, 0003H cm; Region Location inclusive pixel indices); Table C.11-1b and C.11.1.1.2 (9 Defined Terms: OD HU US MGML Z_EFF ED EDW HU_MOD PCT); Table C.8-3 (CT Rescale Type "Required if the Rescale Type is not HU"); Tables C.8-126, C.7.6.16-10; Table C.7-14 and C.7.6.6.1.1; 10.2/10.3 ("The first Frame shall be denoted as Frame number 1"); C.10.5.1.2 and Table C.18.6-1 Graphic Data ("(column,row) … TLHC of the TLHC pixel is 0.0\0.0, the BRHC of the TLHC pixel is 1.0\1.0"); PS3.6 Table 6-1 rows for the 28 tags used; PS3.16 CID 7460 (cm, mm, um), CID 7461 (cm2, mm2, um2), CID 7181 ([hnsf'U] Hounsfield Unit + 23 others), CID 83 ([hnsf'U]), CID 7183 (deg Degree). No CID 82 table exists in 2026a; "[in_i]" and any pixel unit are in no PS3.16 table.

**Correction to the brief:** PS3.3 2026a 10.7.1.3 carries no "UI shall indicate detector plane" rule (dumped in full: Value order + positive values only); the detector-plane definition is in Tables C.8-2 / C.8-71 ("measured at the front plane of the … detector housing"). The tool now labels it anyway (`spacing_note`). The tool writes no DICOM object (no SR, no GSPS), so CID 7469/7470/7472 and the Graphic Type terms do not apply; `--ellipse cx,cy,rx,ry` is not the C.10.5.1.2 ELLIPSE 4-point form and is not encoded anywhere.

**Input contract**

| Option | DICOM concept | 2026a reference | Allowed per standard | Code accepts | Default (std) | Default (code) | Verdict |
|---|---|---|---|---|---|---|---|
| `<file-path>` | PS3.10 file | PS3.10 7.1 | — | path | — | — | plumbing |
| `-o, --output` | output file | — | — | path | — | stdout | plumbing |
| `-f, --format` | report format | — | — | text, json, csv | — | text | plumbing |
| `--unit` | length / area unit | PS3.3 10.7.1.3 (mm); PS3.16 CID 7460, 7461 | cm, mm, um / cm2, mm2, um2 | mm, cm, inches, pixels | — | mm | wrong → fixed (mm was printed at an assumed 1 mm/pixel when no spacing existed; now pixels + warning) |
| `--force` | no preamble / DICM | PS3.10 7.1 | — | flag | — | false | plumbing |
| `--verbose` | — | — | — | flag (now stderr) | — | false | plumbing |
| `distance --p1/--p2` | point (column,row) | Table C.18.6-1; 10.7.1.3 | column\row, 0,0 = TLHC of TLHC pixel | x,y; dx × column spacing, dy × row spacing | — | — | match (help fixed) ×2 |
| `area --polygon` | polygon | Table C.18.6-1 | ≥ 3 points | ≥ 3 x,y | — | [] | match |
| `area --ellipse` | ellipse | C.10.5.1.2 | (ELLIPSE = 4 axis endpoints) | cx,cy,rx,ry | — | — | match (not an encoding) |
| `angle --vertex` | angle | Table C.18.6-1; 10.7.1.3 | — | x,y; angle was in the pixel grid, now in mm space | — | — | wrong → fixed |
| `angle --p1/--p2` | arm endpoints | Table C.18.6-1 | — | x,y | — | — | match ×2 |
| `roi --rect` | rectangle | Table C.18.6-1 | pixel (c,r) = [c,c+1)×[r,r+1) | pixels whose centres are inside | — | — | match |
| `roi --polygon` | polygon ROI | Table C.18.6-1 | as above | was pixel-corner test, now centre | — | [] | wrong → fixed |
| `roi --circle` | circle ROI | C.10.5.1.2 CIRCLE; Table C.18.6-1 | as above | was pixel-corner test, now centre | — | — | wrong → fixed |
| `roi --statistics` | Modality LUT output stats | C.11.1, C.11.1.1.2 | LUT Sequence xor Rescale | Modality LUT Sequence was ignored; now applied; `value_unit` | — | false | wrong → fixed |
| `roi --histogram` | — | — | — | flag | — | false | plumbing |
| `roi --bins` | — | — | — | 2…65536 | — | 256 | plumbing |
| `hu --point` | CT number | Table C.8-3; C.11.1.1.2 | HU when Rescale Type HU / absent on CT | was always labelled HU; now HU only then, else the Rescale Type + warning | — | — | wrong → fixed |
| `hu --rect` | mean CT number | C.11.1 | — | x,y,w,h | — | — | match |
| `hu --statistics` | ROI stats | C.11.1 | — | flag | — | false | match |
| `pixel --point` | stored value → modality output | PS3.5 8.1.1; C.11.1 | Bits Stored / High Bit / sign from High Bit | raw cell was read (no mask, sign from cell width, RGB read as gray, compressed unsupported); now `PixelData`, Samples per Pixel 1 only | — | — | wrong → fixed |
| `pixel --frame` | frame | 10.3; C.7.6.6.1.1 | Frame numbers from 1, ≤ Number of Frames | 0-based index, now range-checked | 1 | 0 | match (0-based by design, P-MEASURE-FRAME) |
| (spacing source) | calibration attribute | 10.7.1.1–3; Table C.7.6.16-2; C.8.5.5; Tables C.8-2, C.8-71, C.8-25 | PS → Pixel Measures → US Region (cm) → Imager PS (detector plane) → Nominal Scanned PS | only Pixel Spacing was read; 4 sources added | — | — | missing → fixed |
| (suv) | SUV | PS3.16 CID 85 (DICOMKit `SUVCalculator`, P-SUV) | — | not offered; the CLI passes nothing to SUVCalculator | — | — | missing (not offered) |

Counts: matched 10, wrong 7 (all fixed), missing 2 (1 fixed, 1 not offered), extra 0, plumbing 7 (24 options + 2 concept rows).

**Output contract**

| Field | DICOM source | Encoding (standard) | Encoding (code) | Verdict |
|---|---|---|---|---|
| JSON `type`, `description`, `value`, `p1`, `p2`, `vertex`, `point`, `shape`, `center`, `radii`, `vertices` | — | — | tool keys (not PS3.18 F) | plumbing |
| JSON `unit` / text unit `mm`, `cm` | CID 7460 | UCUM mm, cm | mm, cm | match |
| `mm²`, `cm²` | CID 7461 | UCUM mm2, cm2 | display symbol; code in `unit_ucum`/`area_unit_ucum` | match (display) |
| `°` | CID 7183 | UCUM deg | display; `unit_ucum` deg | match (display) |
| `HU` | CID 7181 / CID 83; Table C.8-3 | UCUM [hnsf'U] | was printed for any modality; now only for HU output units, `unit_ucum` [hnsf'U] | wrong → fixed |
| `in`, `in²`, `px`, `px²` | — | no PS3.16 code | display only, no `unit_ucum` | extra (non-DICOM units) |
| `px` for an uncalibrated image | 10.7.1.1 | no spacing ⇒ no physical unit | was `mm` | wrong → fixed |
| JSON `unit_ucum`, `area_unit_ucum` (new) | CID 7460/7461/7181/7183 | UCUM code | codes above | match (added) |
| JSON/text `spacing_source` (new) | PS3.6 Table 6-1 keyword | PixelSpacing, PixelMeasuresSequence, SequenceOfUltrasoundRegions, ImagerPixelSpacing, NominalScannedPixelSpacing, none | same 5 + none | match (added) |
| `spacing_mm` (new) | 10.7.1.3 | row\column | row\column | match (added) |
| `spacing_note` (new) | Tables C.8-2/C.8-71, C.8-25, 10.7.1.2 | front plane of detector housing / scanned media / Calibration Type | same | match (added) |
| ROI JSON `roi`, `pixel_count`, `area`, `area_unit`, `mean`, `std_dev`, `min`, `max`, `histogram[lower,upper,count]` | — | — | tool keys | plumbing |
| ROI JSON `value_unit` (new) | Rescale Type / Modality LUT Type | C.11.1.1.2 Defined Terms | value as stored | match (added) |
| labels `Image`, `Bits`, `Rescale`, `Warning`, `Output written to` | — | — | stderr / stdout | plumbing |
| exit codes | — | — | 0 ok; 1 error; 64 validation (ArgumentParser) | plumbing |

**Findings fixed** (all in `Sources/dicom-measure`, tests in `Tests/dicom-measureTests/MeasureStandardTests.swift`, 17 tests): spacing source chain (5 sources, `spacing_source`); uncalibrated → pixels instead of assumed mm; angle in physical space; Modality LUT applied; Bits Stored/High Bit/sign via `PixelData` (and compressed data decoded via `DICOMFile.pixelData()`); HU label only for HU output units; C.18.6-1 coordinates (floor sampling, negative coordinates out of bounds, pixel-centre ROI membership); frame range check; Samples per Pixel ≠ 1 refused; verbose to stderr; help/README document all of it.

**Open (tool, not fixed):** with no spacing, Pixel Aspect Ratio (0028,0034) ≠ 1:1 is not applied to pixel distances (Low); Pixel Spacing Calibration Description (0028,0A04) is not printed (only Calibration Type).

**P-items**
- P-MEASURE-FRAME: `--frame` is a 0-based index; PS3.3 2026a 10.3 numbers Frames from 1. Proposal: add `--frame-number` (1-based) and deprecate `--frame` (kept; help now states the mapping and the range is checked).
- P-MEASURE-UNIT: JSON `unit`/`area_unit` carry display symbols (`mm²`, `°`, `HU`, `in`, `px`). Proposal: make `unit` the PS3.16 UCUM code (now in `unit_ucum`), and add `um` (CID 7460/7461) to `--unit`; `inches` has no PS3.16 code.

**Deferred findings**

| D197 | DICOMKit | Sources/DICOMKit/DataSet+PixelData.swift:476 (also DICOMFile+PixelData.swift:465) | `rescale(_:)` takes no frame index and calls `rescaleSlope()`/`rescaleIntercept()` without one, so a Per-frame Pixel Value Transformation Sequence (0028,9145) is ignored for every frame but the first; dicom-measure works around it with `rescaleSlope(frameIndex:)` | PS3.3 2026a Table C.7.6.16-10, Table C.8-126 | Low | ✅ 2026-10-01 (`d37433f0`) — see the deferred-findings table above |

**Markers**
- MeasurementEngine.swift: `// NEMA-verified: 2026a, checked 2026-10-01 — spacing sources diffed against PS3.3 2026a 10.7.1.1-10.7.1.3, Table 10-10, Table C.7.6.16-2, Tables C.8-2/C.8-71 (Imager Pixel Spacing), C.8-25 (Nominal Scanned Pixel Spacing), C.8-17 with C.8.5.5.1.14/.15/.17 (13 Physical Units values; cm used); 11 Tag literals match PS3.6 2026a Table 6-1 (name and keyword); output units per C.11.1.1.2 (9 Defined Terms) and Table C.8-3; coordinates per Table C.18.6-1; UCUM codes per PS3.16 2026a CID 7460 (3), CID 7461 (3), CID 7181/83 [hnsf'U], CID 7183 deg`
- main.swift: `// NEMA-verified: 2026a, checked 2026-10-01 — option help and output keys diffed against PS3.3 2026a 10.7.1.3 (spacing Value order), Table C.18.6-1 (column,row; 0,0 = TLHC of the TLHC pixel), 10.3 (first Frame is Frame number 1; --frame stays a 0-based index, P-MEASURE-FRAME), C.11.1.1.2 (output units); spacing_source values are PS3.6 2026a Table 6-1 keywords (5); unit_ucum values per PS3.16 2026a CID 7460/7461/7181/7183`

**Checks:** `swift build --product dicom-measure` ok; `swift test --filter dicom_measureTests` 17/17 pass; `diff_cli.py --tool dicom-measure` 0 wrong (Table 6-1 tag literals 22 matched, citations 22 matched); `check_nema_markers.py Sources/dicom-measure` 2/2. diff_cli extractor: no change needed (it lists all 24 options; duplicate names across subcommands are keyed `distance --p1` etc. in the contract).

### dicom-ai (G4)

Commands: dicom-ai, classify, segment, detect, enhance, batch, registry (add, list, remove, search, info, clear) · 6 Swift files · 46 options (45 + new `--algorithm-version`). Segmentation (D44, 3fe88bd) was not redone; this pass covers every other object the tool writes.

**Compared (by script / TemplateValidator):** `diff_cli.py --tool dicom-ai` baseline: coded concepts matched 31, wrong 4 → after fix matched 35, wrong 0; doc citations matched 92, wrong 0. PS3.16 2026a TID 1500 (18 rows), TID 1501 (26 rows), TID 4019 (6 rows), TID 1001/1002/1004, TID 300, TID 1600/1601 dumped with `nema_docbook.py`; Table D-1 rows for 111001, 111003, 111012, 112039, 112040, 121071, 121072, 121112, 121191, 125007, 126000, 126010; CID 7021 (4), CID 7551→7552/7553, CID 7202 (9), CID 7203 (34); certainty units from TID 4006 row 6 / TID 4104 row 12 / TID 4127 row 8 (`UNITS = EV (%, UCUM, "Percent") Value = 0 - 100`); PS3.3 Tables A.35.3-1, C.18.8-1 (Content Template Sequence 1C), C.12-10, C.7-9, C.7.6.1.1.2; PS3.6 Table A-1 (88.33, 66.4, 11.1). The SR output is validated in the tests by `TemplateValidator(mode: .strict)` against TID 1500 (a mutation that drops Algorithm Version is caught).

**Input contract**

| Option | DICOM concept | 2026a reference | Allowed per standard | Code accepts | Default (std) | Default (code) | Verdict |
|---|---|---|---|---|---|---|---|
| `<input>` | source image | PS3.10 7.1 | PS3.10 file | path; `--force` for no preamble | — | — | plumbing |
| `-m, --model` | model path; file name = Algorithm Name (111001, DCM) and Segment Algorithm Name (0062,0009) | PS3.16 TID 4019 row 1 (TEXT, M); PS3.3 Table C.8.20-4 (1C, AUTOMATIC) | text | file name | — | — | match (segment wrote fixed "AI Model" → fixed) |
| `-o, --output` | output path | — | — | path | — | — | plumbing |
| `-f, --format` | dicom-sr → Comprehensive SR Storage 1.2.840.10008.5.1.4.1.1.88.33, TID 1500; dicom-seg → Segmentation Storage 1.2.840.10008.5.1.4.1.1.66.4 | PS3.6 Table A-1; PS3.3 A.35.3-1; PS3.16 TID 1500 | json, text, csv (plumbing); dicom-sr; dicom-seg | same | — | json | **wrong → fixed** (dicom-sr: title 129007/129008 DCM not in Table D-1; confidence (121072, DCM) = "Impressions" (retired); image (121191, DCM) = "Referenced Segment"; 0-1 confidence written as %; no template; no File Meta) |
| `--confidence` | threshold, not written | — | — | 0.0-1.0 | — | 0.5 | plumbing |
| `--force`, `--verbose`, `--profile`, `--profile-output` | — | — | — | — | — | — | plumbing |
| `--frame` | Referenced Frame Number (1-based) of the analysed frame in the SR IMAGE/SCOORD source and Source Image Sequence | PS3.3 Table 10-3; Table C.12-10 | 1..n | index+1, multi-frame only | — | 0 | match (not referenced before → fixed) |
| `--algorithm-version` | Algorithm Version (111003, DCM) | PS3.16 TID 4019 row 2 (TEXT, M) | text | text | — | model CoreML versionString, else "unknown" | **missing → added** (new option) |
| `classify --top-k`, `detect --max-detections` | number of TID 1501 Measurement Groups | TID 1500 row 9 (1-n) | — | Int | — | 5 / 10 | plumbing |
| `segment --labels` | Segment Label (0062,0005) | PS3.3 Table C.8.20-4 (1) | text | JSON array | — | Class_n | match (D44) |
| `segment --segment-category` | Segmented Property Category Code Sequence (0062,0003) | Table C.8.20-4; CID 7150 | 8 rows | keyword or SCHEME:VALUE[:MEANING] | — | tissue | match (D44) |
| `segment --segment-type` | Segmented Property Type Code Sequence (0062,000F) | Table C.8.20-4; CID 7151 | CIDs via 7151 | 21 keywords or code | — | tissue | match (D44) |
| `detect --iou-threshold` | NMS | — | — | Double | — | 0.5 | plumbing |
| batch (8 options), registry add/list/remove/search/info/clear (21 options) | local files and model registry (registry `--version` is not written to DICOM) | — | — | — | — | — | plumbing |

**Output contract**

| Output | 2026a reference | What it carries now | Verdict |
|---|---|---|---|
| dicom-sr file | PS3.10 7.1; PS3.3 A.35.3-1 | PS3.10 file (preamble, File Meta: Media Storage SOP Class 1.2.840.10008.5.1.4.1.1.88.33) | wrong (raw data set) → fixed |
| SR root | TID 1500 row 1, CID 7021; Table C.18.8-1 | CONTAINER (126000, DCM, "Imaging Measurement Report"); Content Template Sequence DCMR / 1500 | wrong → fixed |
| SR Image Library | TID 1500 row 5 → TID 1600 rows 1, 2, 4 → TID 1601 row 1 | source IMAGE (frame number for multi-frame) | missing → fixed |
| SR Imaging Measurements | TID 1500 rows 6, 6b → TID 4019 rows 1-2 | (126010, DCM); HAS CONCEPT MOD TEXT (111001, DCM, "Algorithm Name"), TEXT (111003, DCM, "Algorithm Version"); written also with no findings (row 6 MC) | wrong (111001 was a root CONTAINS TEXT; no version) → fixed |
| SR per finding | TID 1501 rows 1, 2, 3, 10 → TID 300 row 1 → TID 301 row 13 → TID 320 rows 1 / 3-4; row 12 | Measurement Group (125007), Tracking Identifier (112039), Tracking Unique Identifier (112040), NUM (111012, DCM, "Certainty of Finding") UNITS (%, UCUM, "Percent") 0-100 INFERRED FROM IMAGE (classify) or SCOORD POLYLINE closed bbox SELECTED FROM IMAGE (detect), $ImagePurpose (121112, DCM, "Source of Measurement") (CID 7552); TEXT (121071, DCM, "Finding") = label | wrong → fixed |
| SR Type 2 attributes | Tables C.7-1, C.7-3, C.7-8 | Patient's Birth Date/Sex, Referring Physician's Name, Study ID, Accession Number copied; Manufacturer "DICOMKit" | missing → fixed (in dicom-ai; engine gap D198) |
| TID 1001 observation context | TID 1500 row 3 (M) → TID 1001 rows MC "if not inherited" | not written (all rows inherited/defaulted) | match (builder has no API: D199) |
| dicom-seg file | PS3.3 A.51 | unchanged from D44 except Segment Algorithm Name = model file name | match |
| enhance file | PS3.10 7.1; PS3.3 C.7.6.1.1.2; Table C.12-10; CID 7202 | PS3.10 file of the source SOP Class keeping all source attributes; new SOP Instance/Series UIDs; Image Type DERIVED\SECONDARY\<value 3+>; Image Pixel attributes of the result; Smallest/Largest Image Pixel Value removed; 1 frame; Derivation Description; Source Image Sequence with (121322, DCM, "Source image for image processing operation") | wrong (raw data set with 12 copied attributes, Image Type kept ORIGINAL, no source reference) → fixed |
| GSPS (library function, no subcommand calls it) | PS3.3 A.33.1, C.10.5 | built by GrayscalePresentationStateBuilder: Presentation Creation Date/Time, Displayed Area, Graphic Layer, POLYLINE graphic + text object (Bounding Box Annotation Units (0070,0003)) | wrong (text object used Graphic Annotation Units (0070,0005); no Displayed Area / creation date) → fixed |
| JSON keys `file`, `predictions`, `label`, `confidence`, `detections`, `bbox`, `mask_size`, `num_classes`, `error`; CSV headers; text/markdown reports; "DICOM SR saved to …" etc. | — | tool vocabulary, not PS3.6/PS3.18 keywords | plumbing |
| exit codes | — | 0 success; 1 error (ArgumentParser); 64 usage | plumbing |

**Counts:** matched 5, wrong 1, missing 1, extra 0, plumbing 39 (46 options). Output rows: 8 wrong/missing → fixed, 2 match, 2 plumbing.

**Changes:** `AIDICOMOutputGenerator.swift` (SR via `MeasurementReportBuilder` + `withAlgorithmIdentification`; `partTenFile`; enhance; GSPS via builder), `main.swift` (`--algorithm-version`, `--frame` passed to SR, model file name to SEG, PS3.10 writes), `AIEngine.swift` (`modelVersion` from CoreML metadata), README, CHANGELOG. Commit **1ff3934e**.

**Tests:** `swift test --filter dicom_aiTests`: 11 tests, 0 failures (6 new in `Tests/dicom-aiTests/AIOutputObjectsTests.swift`: TID 1500 strict validation for classify, detect, empty result; codes/units/values; Content Template Sequence; PS3.10 round trip; enhance derived image; GSPS; option). `swift build --product dicom-ai` ok; `check_nema_markers.py Sources/dicom-ai`: 6/6; `diff_cli.py --tool dicom-ai`: 0 checks failing.

**Deferred findings**

| D199 | DICOMKit | Sources/DICOMKit/StructuredReporting/MeasurementReportBuilder.swift:494 (root at :583) | `MeasurementReportBuilder` has no API for TID 4019 Algorithm Identification (TID 1500 rows 6b, 10b, 12b; TID 1501 row 9b) or for the TID 1001 observation context (row 3 → TID 1002/1004 device observer), and builds the root CONTAINER without a template identifier, so the Content Template Sequence (DCMR, 1500) that PS3.3 Table C.18.8-1 requires is never written; dicom-ai adds row 6b and the root template after `build()` | PS3.16 2026a TID 1500, TID 1501, TID 4019, TID 1001; PS3.3 2026a Table C.18.8-1 | Medium | ✅ 2026-10-01 (`488a9c07`) — see the deferred-findings table above |
| D198 | DICOMKit | Sources/DICOMKit/StructuredReporting/SRDocumentSerializer.swift:91, :113 | `SRDocumentSerializer` writes only Patient's Name / Patient ID and Study Instance UID / Study Date / Study Time / Accession Number (when set); the Type 2 Patient's Birth Date, Patient's Sex, Referring Physician's Name, Study ID and Manufacturer (0008,0070) are never written and `SRDocument` has no fields for them (`MeasurementReportBuilder.withPatientBirthDate/withPatientSex/withReferringPhysicianName` are dropped by `build()`) | PS3.3 2026a Tables C.7-1, C.7-3, C.7-8, A.35.3-1 | Medium | ✅ 2026-10-01 (`488a9c07`) — see the deferred-findings table above |

**P-items:** none (`--algorithm-version` is additive; internal `createEnhancedDICOMFile` / SR function signatures changed with defaults, not public API).

**Notes:** the GSPS generator and the text/Markdown report functions are not reachable from any subcommand; `Tests/DICOMToolsTests/DICOMAITests.swift` (compiled by no target) still calls the old signatures, which compile through the new defaults.

**Markers:** AIDICOMOutputGenerator.swift (2 lines: D44 + "classify/detect --format dicom-sr: … replaced by a TID 1500 Measurement Report from MeasurementReportBuilder, validated by TemplateValidator against PS3.16 2026a TID 1500/1501/300/301/320/1600/4019 …"); main.swift ("… --algorithm-version is Algorithm Version (111003, DCM), PS3.16 2026a TID 4019 row 2 (M) …; the 46 options are otherwise plumbing"); AIEngine.swift ("carries no DICOM-standard data beyond reading the Image Pixel Module … Tables C.7-11a, C.7-11b and C.7-11c …"); ModelRegistry.swift, PerformanceMetrics.swift ("carries no DICOM-standard data (…)"); SegmentPropertyCodes.swift unchanged (D44).

### dicom-script (G4)

Commands: dicom-script, run, validate, template · 1 Swift file · 9 options. The script engine (parser, executor, validator, templates) lives in `Sources/DICOMKit/Scripting/ScriptEngine.swift` (marked C1 on 2026-09-29).

**Compared:** `diff_cli.py --tool dicom-script`: all 12 checks ok (0 UIDs, 0 codes, 0 tags, 0 citations). The script language has no DICOM keyword, (gggg,eeee) tag or UID syntax: a script is variables, `if exists … endif`, pipelines and command lines of `dicom-*` tools; DICOM values reach the standard only through the called tool's own options (verified in those tools' passes). The 5 templates were checked against the option surfaces of the tools they call (`diff_cli.py --list-surface`): dicom-validate `--level` (1-5), dicom-convert `--format png`, dicom-study `summary --format json`, dicom-query `--level PATIENT|STUDY` (case-insensitive; PS3.4 Q/R Level values) match; 4 template faults are in DICOMKit (below).

**Input contract**

| Option | DICOM concept | 2026a reference | Allowed per standard | Code accepts | Default (std) | Default (code) | Verdict |
|---|---|---|---|---|---|---|---|
| `run <script-path>` | — | — | — | path | — | — | plumbing |
| `run --variables` | — | — | — | KEY=VALUE … | — | [] | plumbing |
| `run --parallel` | — | — | — | flag | — | false | plumbing |
| `run -v, --verbose` | — | — | — | flag | — | false | plumbing |
| `run --dry-run` | — | — | — | flag | — | false | plumbing |
| `run --log` | — | — | — | path | — | — | plumbing |
| `validate <script-path>` | — | — | — | path | — | — | plumbing |
| `validate -v, --verbose` | — | — | — | flag | — | false | plumbing |
| `template <template-name>` | — | — | — | workflow, pipeline, query, archive, anonymize | — | — | plumbing |

**Output contract**

| Output | Reference | Verdict |
|---|---|---|
| executed tool output, validation lines (`ScriptConsole`), template text | — | plumbing |
| exit codes 0 / 1 (validation issues, script errors) | — | plumbing |

**Counts:** matched 0, wrong 0, missing 0, extra 0, plumbing 9.

**Changes:** marker only. Commit **c233ec05**. Build `swift build --product dicom-script` ok; `check_nema_markers.py Sources/dicom-script`: 1/1. No tests added (no behaviour change; no `dicom_scriptTests` target needed).

**Deferred findings**

| D200 | DICOMKit | Sources/DICOMKit/Scripting/ScriptEngine.swift:587 | the `query` template passes `--study-date-from 20240101 --study-date-to 20241231`, options dicom-query does not have; a Study Date range is one PS3.4 range value, `--study-date 20240101-20241231` | PS3.4 2026a C.2.2.2.5 (Range Matching) | Low | ✅ 2026-10-01 (`092cf368`) — see the deferred-findings table above |
| D201 | DICOMKit | Sources/DICOMKit/Scripting/ScriptEngine.swift:555, :558, :584, :587 | `pipeline` / `query` templates pass `--host ${PACS_HOST}`; dicom-query and dicom-retrieve take host[:port] as a positional argument, and dicom-retrieve has no `--patient-id` (it retrieves by `--study-uid` etc.), so the generated scripts fail | — (template plumbing) | Low | ✅ 2026-10-01 (`092cf368`) — see the deferred-findings table above |
| D202 | DICOMKit | Sources/DICOMKit/Scripting/ScriptEngine.swift:564, :619, :623 | `pipeline` / `anonymize` templates use `dicom-anon --profile basic` (the legacy profile dicom-anon documents as not PS3.15) and `--profile strict` (no such profile); the PS3.15 Basic Application Level Confidentiality Profile is `--profile ps315` | PS3.15 2026a E.1 | Medium | ✅ 2026-10-01 (`e2c5ea18`) — see the deferred-findings table above |
| D203 | DICOMKit | Sources/DICOMKit/Scripting/ScriptEngine.swift:567, :600 | `dicom-archive create … --input` — dicom-archive has no `create` subcommand (`init`, `import`) | — (template plumbing) | Low | ✅ 2026-10-01 (`092cf368`) — see the deferred-findings table above |

**P-items:** none.

**Marker (main.swift):** `// NEMA-verified: 2026a, checked 2026-10-01 — carries no DICOM-standard data (runs, validates and prints templates of the shell-like script language in DICOMKit/Scripting; scripts name dicom-* tools and their options, not DICOM keywords, tags or UIDs)`

### dicom-3d (G4)

Files: main.swift, VolumeData.swift, MPRGenerator.swift, VolumeExport.swift, SurfaceExtractor.swift, DerivedSeries.swift (new) · 11 subcommands · 54 options.
Evidence: `<scratch>/g4v/g4v_std.py` (output `g4v/std_dump.txt`) dumps PS3.3 Tables C.7-10, C.7.6.16-2/-4/-5, C.7-6, C.11-2b, C.9-2, 10-3, C.12-10, C.8-130, sections C.7.6.2.1.1, C.7.4.1.1.1, C.7.6.1.1.2, C.8.2.1.1.1, C.8.3.1.1.1, C.11.2.1.2.1, C.11.2.1.3.1/.2, C.7.6.3.1.2, and PS3.16 CID 7203 (34 rows; 113072 written, 113078/113079/113049 cited) and CID 7202 (121322). `diff_cli.py --tool dicom-3d`: 12 checks ok (no 1.2.840.10008 literals; 2 Photometric Interpretation literals match).

**Input contract** — matched 1, wrong 16, missing 8, extra 5, plumbing 24 (54 rows; every wrong/missing row fixed with a test)

| Option | DICOM concept | 2026a reference | Allowed per standard / accepted by code | Verdict |
|---|---|---|---|---|
| `mpr <input-paths>` | volume assembly from Image Plane / functional groups | PS3.3 Table C.7-10, C.7.6.2.1.1, C.7.4.1.1.1, Tables C.7.6.16-2/-4/-5, C.11.1.1.2 | Pixel Spacing value 1 = row spacing, value 2 = column spacing; sort along normal; one Frame of Reference UID; per-frame Plane Position/Orientation; per-instance rescale | wrong → fixed |
| `mpr --output` | output path | — | path | plumbing |
| `mpr --planes` | patient planes axial/sagittal/coronal | PS3.3 C.7.6.2.1.1 (LPS axes) | axial ⟂ z, coronal ⟂ y, sagittal ⟂ x; oblique accepted, not generated (warning) | wrong → fixed |
| `mpr --format` | derived image output (dcm) | PS3.3 C.7.6.1.1.2, Table C.12-10, PS3.16 CID 7203 (113072), CID 7202 (121322) | png \| dcm; dcm = DERIVED\SECONDARY (MR Value 3 MPR), Derivation Code 113072, Source Image Sequence, plane geometry | missing → fixed |
| `mpr --thickness` | Slice Thickness of the reformatted image | PS3.3 Table C.7-10 (Slice Thickness nominal) | mm > 0; slabs averaged | missing → fixed |
| `mpr --interpolation` | resampling method (no DICOM attribute) | — | nearest \| linear \| cubic (cubic = linear; only the unreachable oblique path interpolates) | extra |
| `mpr --window-center` | Window Center | PS3.3 Table C.11-2b, C.11.2.1.2.1 | Modality LUT output units; LINEAR function | wrong → fixed |
| `mpr --window-width` | Window Width | PS3.3 C.11.2.1.2.1 | >= 1 (LINEAR) | missing → fixed |
| `mpr --verbose` | verbosity | — | flag | plumbing |
| `mip <input-paths>` | volume assembly | PS3.3 Table C.7-10, C.7.6.2.1.1 | shared VolumeLoader (see mpr) | wrong → fixed |
| `mip --output` | output path | — | path | plumbing |
| `mip --direction` | projection plane | PS3.3 C.7.6.2.1.1 | axial \| sagittal \| coronal (LPS) | wrong → fixed |
| `mip --thickness` | projection slab (Pixel by pixel Maximum) | PS3.3 Table C.8-130 MAXIMUM; PS3.16 CID 7203 113078 | mm, centred slab; 0 = whole volume | missing → fixed |
| `mip --window-center` | Window Center | PS3.3 Table C.11-2b, C.11.2.1.2.1 | LINEAR function | wrong → fixed |
| `mip --window-width` | Window Width | PS3.3 C.11.2.1.2.1 | >= 1 | missing → fixed |
| `mip --verbose` | verbosity | — | flag | plumbing |
| `minip <input-paths>` | volume assembly | PS3.3 Table C.7-10, C.7.6.2.1.1 | shared VolumeLoader (see mpr) | wrong → fixed |
| `minip --output` | output path | — | path | plumbing |
| `minip --direction` | projection plane | PS3.3 C.7.6.2.1.1 | axial \| sagittal \| coronal (LPS); unknown values rejected (were silently axial) | wrong → fixed |
| `minip --thickness` | projection slab (Pixel by pixel Minimum) | PS3.3 Table C.8-130 MINIMUM; PS3.16 CID 7203 113079 | mm, centred slab; 0 = whole volume | missing → fixed |
| `minip --window-center` | Window Center | PS3.3 Table C.11-2b, C.11.2.1.2.1 | LINEAR function | wrong → fixed |
| `minip --window-width` | Window Width | PS3.3 C.11.2.1.2.1 | >= 1 | missing → fixed |
| `minip --verbose` | verbosity | — | flag | plumbing |
| `average <input-paths>` | volume assembly | PS3.3 Table C.7-10, C.7.6.2.1.1 | shared VolumeLoader (see mpr) | wrong → fixed |
| `average --output` | output path | — | path | plumbing |
| `average --direction` | projection plane (Pixel by pixel mean) | PS3.3 C.7.6.2.1.1; Table C.8-130 MEAN | axial \| sagittal \| coronal (LPS); unknown values rejected | wrong → fixed |
| `average --window-center` | Window Center | PS3.3 Table C.11-2b, C.11.2.1.2.1 | LINEAR function | wrong → fixed |
| `average --window-width` | Window Width | PS3.3 C.11.2.1.2.1 | >= 1 | missing → fixed |
| `average --verbose` | verbosity | — | flag | plumbing |
| `surface <input-paths>` | volume assembly; vertices in patient LPS mm | PS3.3 C.7.6.2.1.1 Equation C.7.6.2.1-1 | vertex = S + X·Δi·i + Y·Δj·j + N·Δk·k | wrong → fixed |
| `surface --output` | output path | — | path | plumbing |
| `surface --threshold` | iso-value in Modality LUT output units | PS3.3 C.11.1.1.2 | real value (e.g. HU) | match |
| `surface --format` | mesh file format (not a DICOM Surface Segmentation / Surface Scan Mesh IOD) | — | stl \| obj | plumbing |
| `surface --verbose` | verbosity | — | flag | plumbing |
| `volume <input-paths>` | volume rendering (not implemented, exits 1) | — | paths | plumbing |
| `volume --output` | output path | — | path | plumbing |
| `volume --camera-angle` | view angle (not implemented) | — | azimuth,elevation | extra |
| `volume --transfer-function` | transfer function file (not implemented) | — | JSON path | extra |
| `volume --verbose` | verbosity | — | flag | plumbing |
| `export <input-paths>` | volume assembly | PS3.3 Table C.7-10, C.7.6.2.1.1 | shared VolumeLoader | wrong → fixed |
| `export --output` | output prefix | — | path | plumbing |
| `export --formats` | NIfTI / MetaImage geometry from the DICOM affine | PS3.3 C.7.6.2.1.1 (LPS), C.11.1.1.2 | nifti (sform RAS, scl 1/0) \| metaimage (TransformMatrix from IOP) | wrong → fixed |
| `export --verbose` | verbosity | — | flag | plumbing |
| `backends --json` | codec backend list | — | flag | plumbing |
| `encode-volume <input-paths>` | slice order of the encoded volume | PS3.3 C.7.6.2.1.1 | sorted along the normal before encoding (was file-name order) | wrong → fixed |
| `encode-volume --output` | output path | — | path | plumbing |
| `encode-volume --mode` | JP3D codestream mode (ISO/IEC 15444-10 / -15; private SOP Class 1.2.826.0.1.3680043.10.511.10, not in PS3.6 Table A-1) | PS3.6 Table A-1 (no JP3D entry) | lossless \| lossless-htj2k \| lossy \| lossy-htj2k | extra |
| `encode-volume --psnr` | lossy target PSNR | — | dB > 0 | plumbing |
| `encode-volume --verbose` | verbosity | — | flag | plumbing |
| `decode-volume <input-path>` | JP3D document (private SOP Class) | — | path | plumbing |
| `decode-volume --output` | output directory | — | path | plumbing |
| `decode-volume --verbose` | verbosity | — | flag | plumbing |
| `inspect <input-path>` | JP3D document (private SOP Class) | — | path | plumbing |
| `inspect --json` | sidecar JSON (engine format, camelCase keys; not PS3.18 Annex F) | — | flag | extra |

**Output contract**

| Field | DICOM source | Standard | Code | Verdict |
|---|---|---|---|---|
| `mpr --format dcm` Image Type (0008,0008) | C.7.6.1.1.2, C.8.2.1.1.1, C.8.3.1.1.1 | DERIVED\SECONDARY; CT Value 3 AXIAL covers coronal/sagittal; MR Value 3 MPR | same | missing → fixed (was PNG) |
| Derivation Code Sequence (0008,9215) | Table C.12-10, CID 7203 | (113072, DCM, "Multiplanar reformatting") | same | missing → fixed |
| Derivation Description (0008,2111) | Table C.12-10 | ST | "Multiplanar reformatting, <plane> plane, by dicom-3d" | missing → fixed |
| Source Image Sequence (0008,2112) + Purpose of Reference | Table C.12-10, CID 7202 | Referenced SOP Class/Instance UID; (121322, DCM) | one Item per source instance | missing → fixed |
| SOP Instance UID / Series Instance UID | C.7.6.1.1.2 | new UIDs | new per instance / per plane | missing → fixed |
| Image Position / Orientation (Patient), Pixel Spacing, Slice Thickness, Rows, Columns | Table C.7-10, C.7.6.2.1.1 | Equation C.7.6.2.1-1, row\column spacing | per reformatted plane; test checks every pixel maps to its voxel | missing → fixed |
| Pixel Data | C.11.1.1.2 | stored = (value − intercept)/slope | clamped to Bits Stored / Pixel Representation; Explicit VR Little Endian | missing → fixed |
| PNG gray values | C.11.2.1.2.1, C.7.6.3.1.2 | LINEAR window; MONOCHROME1 minimum white | same (was LINEAR_EXACT formula, MONOCHROME1 not inverted) | wrong → fixed |
| NIfTI sform / scl_slope, scl_inter | C.7.6.2.1.1 (LPS), C.11.1.1.2 | LPS affine → RAS; voxels already rescaled | sform RAS from IOP; 1 / 0 (was axis-aligned LPS, rescale applied twice) | wrong → fixed |
| MetaImage TransformMatrix / AnatomicalOrientation | C.7.6.2.1.1 | direction cosines | from IOP (was identity / fixed RAI) | wrong → fixed |
| STL / OBJ vertices | C.7.6.2.1.1 | patient LPS mm | VolumeData.physicalCoordinates (slice offset now along the normal) | wrong → fixed |
| inspect labels | PS3.6 Table 6-1 | Patient's Name, Patient ID, Modality, Study Instance UID, Series Description, SOP Instance UID | same (were Patient, Study UID, Series) | wrong → fixed (3), match (3) |
| inspect `--json` keys | — (engine sidecar) | not PS3.18 Annex F | rows, columns, frames, bitsAllocated, …, _jp3dCodestreamBytes | extra |
| encode-volume SOP Class | PS3.6 Table A-1 | no JP3D SOP Class / TS | private 1.2.826.0.1.3680043.10.511.10 (help text = engine constant, test) | extra (documented private) |
| error text | PS3.6 names | Image Position (Patient) (0020,0032), Image Orientation (Patient) (0020,0037), Pixel Spacing (0028,0030), Frame of Reference UID (0020,0052) | same (were "Image Position Patient") | wrong → fixed |
| exit codes | — | — | ArgumentParser 64 on validation, 1 on failure; `volume` exits 1 "not yet implemented" | plumbing |

**Findings fixed** (commit aa35a519): Pixel Spacing read as x\y (value 1 is the row spacing, Table C.7-10); slice offset added to z only instead of along the normal (C.7.6.2.1.1), which also moved STL/OBJ vertices; slice spacing was the 3-D distance of the first two slices (now mean distance along the normal), and the one-slice fallback preferred Slice Thickness over Spacing Between Slices; no Frame of Reference UID / orientation / matrix consistency check (C.7.4.1.1.1); Enhanced multi-frame unreadable (Plane Position/Orientation functional groups) and classic multi-frame silently read as one slice; rescale from the first slice only; plane names were volume index planes, not LPS planes (wrong for sagittal/coronal acquisitions; sagittal/coronal images had the feet at the top); `--format dcm` wrote PNG; `--thickness` ignored by mpr, mip and minip; `oblique` silently skipped; single-plane PNG output landed in the parent directory; minip/average accepted any direction as axial; window used the LINEAR_EXACT formula with no width >= 1 check; MONOCHROME1 not inverted; NIfTI sform ignored orientation and LPS→RAS, and scl applied rescale twice; MetaImage transform was identity; encode-volume passed file-name order to the engine; inspect labels were not PS3.6 names.

**Tests**: new target `dicom-3dTests` (Tests/dicom-3dTests/Volume3DContractTests.swift), `swift test --filter dicom_3dTests`: 21 tests, 0 failures. `swift build --product dicom-3d` ok. `check_nema_markers.py Sources/dicom-3d`: 6/6 files marked 2026a.

**P-items**
- P-3D-OBLIQUE: `--planes oblique` is accepted but cannot produce output (no option supplies the normal/point; the generator ignores the volume origin/orientation). Proposal: add `--oblique-normal x,y,z` / `--oblique-point x,y,z` (LPS mm) and implement it with Equation C.7.6.2.1-1, or remove `oblique` from the accepted values. Kept; a warning is printed.
- P-3D-INTERPOLATION: `--interpolation` has no effect on the axial/sagittal/coronal planes (voxel-aligned) and `cubic` is linear. Proposal: drop `cubic` or implement it; document that orthogonal planes are not resampled.
- P-3D-VOLUME: `volume` and its `--camera-angle` / `--transfer-function` options are not implemented (exit 1). Proposal: hide the subcommand until implemented.

**Deferred findings**

| D204 | DICOMKit | Sources/DICOMKit/JP3DVolumeDocument.swift:486-497 | decode-volume slices: Image Position (Patient) z = origin.z + i·spacing (ignores Image Orientation (Patient)); no Image Orientation (Patient), Pixel Spacing, Frame of Reference UID or Rescale written; Slice Location = z; SOP Class falls back to CT Image Storage for any source | PS3.3 2026a C.7.6.2.1.1, Table C.7-10, C.7.4.1.1.1 | Medium | ✅ 2026-10-01 (`100a5455`) — see the deferred-findings table above |
| D205 | DICOMKit | Sources/DICOMKit/JP3DVolumeDocument.swift:393, 412-424 | sidecar origin taken from the unsorted series[0] and slice spacing from the z coordinate of the first/last input files, while JP3DVolumeBridge sorts the volume itself; wrong for unsorted or non-axial input (dicom-3d encode-volume now pre-sorts) | PS3.3 2026a C.7.6.2.1.1 | Low | ✅ 2026-10-01 (`100a5455`) — see the deferred-findings table above |

**Marker text** (first line of each file; abridged here, full text in the files):
- main.swift: `NEMA-verified: 2026a, checked 2026-10-01 — 54 options of 11 subcommands: plane names (axial/sagittal/coronal) per the LPS axes of PS3.3 2026a C.7.6.2.1.1; --window-center/--window-width are the C.11.2.1.2.1 LINEAR window (width >= 1, Table C.11-2b); --format dcm writes a derived series (C.7.6.1.1.2, CID 7203 113072); inspect labels are PS3.6 2026a Table 6-1 names (…); the JP3D SOP Class 1.2.826.0.1.3680043.10.511.10 is private (not in PS3.6 Table A-1); encode-volume orders slices along the normal before encoding`
- VolumeData.swift: `… PS3.3 2026a Table C.7-10 (…), C.7.6.2.1.1 Equation C.7.6.2.1-1 and LPS axes, C.7.4.1.1.1, Tables C.7.6.16-2/-4/-5, C.7.6.6.1.1, C.11.1.1.2: 6 geometry rules, 2 were wrong (spacing order, z offset off the normal) and 4 missing (FoR, orientation, per-frame geometry, per-slice rescale), all fixed`
- MPRGenerator.swift: `… plane names against the patient-based coordinate system of PS3.3 2026a C.7.6.2.1.1 (…; 3 planes mapped to the volume axis nearest each LPS axis …); reformatted-plane geometry by Equation C.7.6.2.1-1 with Pixel Spacing row\column order of Table C.7-10; window by the LINEAR function of C.11.2.1.2.1 (width >= 1) and MONOCHROME1 shown inverted (C.7.6.3.1.2)`
- DerivedSeries.swift: `… C.7.6.1.1.2, C.8.3.1.1.1, C.8.2.1.1.1, C.12.4 Table C.12-10, PS3.16 2026a CID 7203 (DCM 113072 "Multiplanar reformatting", 1 of 34 rows used) and CID 7202 (DCM 121322), Table C.7-10 / C.7.6.2.1.1, C.11.1.1.2, PS3.5 Table 6.2-1 (DS 16 bytes, ST 1024 chars)`
- VolumeExport.swift: `… the voxel-to-patient affine is PS3.3 2026a C.7.6.2.1.1 Equation C.7.6.2.1-1 with the LPS axes (NIfTI sform converted to RAS …; MetaImage keeps LPS), Pixel Spacing order of Table C.7-10, voxels already in Modality LUT output units (C.11.1.1.2) …; NIfTI-1 / MetaIO header layouts are not DICOM and were not compared with the standard`
- SurfaceExtractor.swift: `carries no DICOM-standard data (marching-cubes mesh, binary STL / OBJ writers); vertex coordinates come from VolumeData.physicalCoordinates, i.e. patient LPS millimetres of PS3.3 2026a C.7.6.2.1.1; no Surface Segmentation / Surface Scan Mesh IOD is written`

**Commit**: aa35a519 `fix(cli): dicom-3d volume geometry, LPS plane names and derived MPR series per DICOM 2026a` (Package.swift hunk = dicom-3dTests target only; CHANGELOG [Unreleased] section "dicom-3d volume geometry, plane names and DICOM MPR output …").

### dicom-viewer (G4)

Files: main.swift, TerminalRenderer.swift · 1 command · 22 options (20 + new `--voi-lut-function`, `--frame-number`).
Evidence: same dump (`<scratch>/g4v/g4v_std.py`): PS3.3 Table C.11-2b (VOI LUT Function; 3 Defined Terms, via DICOMCore VOILUTFunction, NEMA-verified 2026-09-24), C.11.2.1.2.1 / C.11.2.1.3.1 / C.11.2.1.3.2 (formulas and width rules; DICOMCore WindowSettings, verified D64), C.7.6.3.1.2 (MONOCHROME1), Table C.9-2 (Overlay Origin, Overlay Data order) and Image Frame Origin text, Table 10-3 (Referenced Frame Number: "The first Frame shall be denoted as Frame number 1"), PS3.6 Table 6-1 names. `diff_cli.py --tool dicom-viewer`: 12 checks ok.

**Input contract** — matched 0, wrong 4, missing 5, extra 0, plumbing 13 (22 rows; wrong/missing rows fixed with tests, except `--frame`, a P-item)

| Option | DICOM concept | 2026a reference | Allowed per standard / accepted by code | Verdict |
|---|---|---|---|---|
| `<file-paths>` | input files | PS3.10 7.1 | paths | plumbing |
| `--mode` | terminal output protocol | — | ascii \| ansi \| iterm2 \| kitty \| sixel | plumbing |
| `--quality` | ASCII ramp | — | low \| high | plumbing |
| `--color` | ANSI colour depth | — | 256 \| 24bit | plumbing |
| `--window-center` | Window Center | PS3.3 Table C.11-2b, C.11.2.1.2 | Modality LUT output units; applied with the VOI LUT Function (LINEAR when absent) | wrong → fixed |
| `--window-width` | Window Width | PS3.3 C.11.2.1.2.1, C.11.2.1.3.1, C.11.2.1.3.2 | >= 1 for LINEAR; > 0 for LINEAR_EXACT / SIGMOID | missing → fixed |
| `--voi-lut-function` | VOI LUT Function (0028,1056) | PS3.3 Table C.11-2b, C.11.2.1.3 | LINEAR \| LINEAR_EXACT \| SIGMOID (new option) | missing → fixed |
| `--frame` | frame index | PS3.3 Table 10-3 ("The first Frame shall be denoted as Frame number 1") | 0-based index (DICOM numbers from 1) | wrong (P-VIEWER-FRAME) |
| `--frame-number` | Frame Number | PS3.3 Table 10-3, Table C.9-2 Image Frame Origin | 1-based (new option) | missing → fixed |
| `--width` | output width | — | characters >= 1 | plumbing |
| `--height` | output height | — | characters >= 1 | plumbing |
| `--invert` | display inversion (MONOCHROME1 already inverted) | PS3.3 C.7.6.3.1.2 | flag; MONOCHROME1 minimum shown white | missing → fixed |
| `--show-info` | attribute labels | PS3.6 Table 6-1 | Patient's Name, Patient ID, Patient's Sex, Study Description, Study Date, Modality, Rows x Columns, Bits Stored, Number of Frames, Window Center, Window Width | wrong → fixed |
| `--show-overlay` | Overlay Plane display | PS3.3 Table C.9-2, C.9.2 | Overlay Origin 1\1 = upper left pixel (row\column); Overlay Data bit-packed | missing → fixed |
| `--thumbnail` | grid of files / frames | PS3.3 Table 10-3 | frame labels 1-based | wrong → fixed |
| `--size` | grid size | — | WxH | plumbing |
| `--force` | parse without preamble / DICM | PS3.10 7.1 | flag | plumbing |
| `--verbose` | verbosity | — | flag | plumbing |
| `--reduce` | downscale by 2^n after decode | — | n >= 0 | plumbing |
| `--roi` | crop rectangle (tool pixel coordinates, 0-based) | — | x,y,width,height | plumbing |
| `--volume` | all frames as filmstrip | — | flag | plumbing |
| `--jpip` | JPIP URL (unavailable in this build) | PS3.5 8.4 / PS3.6 JPIP Referenced TS | URL | plumbing |

**Output contract**

| Field | DICOM source | Standard | Code | Verdict |
|---|---|---|---|---|
| gray value of a pixel | C.11.1.1.2 → C.11.2.1.2/.3 → C.7.6.3.1.2 | rescale per frame → VOI LUT Function (LINEAR when absent) → MONOCHROME1 inverted | same (was: first-frame rescale, LINEAR_EXACT formula always, the file's SIGMOID/LINEAR_EXACT ignored, MONOCHROME1 not inverted) | wrong → fixed |
| auto window | C.11.2.1.2 (window in Modality LUT output units) | rescaled range | rescaled min/max (was stored-value range: CT with an intercept mis-windowed) | wrong → fixed |
| overlay pixels (`--show-overlay`) | Table C.9-2 | Overlay Origin row\column, 1\1 = upper left; bits left to right, top to bottom | drawn white via OverlayPlaneRenderer.planes / isSet (was not drawn) | missing → fixed |
| status line `Frame n/N` | Table 10-3 | 1-based | 1-based | match |
| thumbnail labels `Frame n` | Table 10-3 | 1-based | 1-based (were 0-based) | wrong → fixed |
| frame error text | Table 10-3 | — | "Frame 5 (0-based index 4) is not available"; past Number of Frames: "Frame number N does not exist; Number of Frames is M" | wrong → fixed |
| `--show-info` labels | PS3.6 Table 6-1 | Patient's Name, Patient ID, Patient's Sex, Study Description, Study Date, Modality, Rows/Columns, Bits Stored, Number of Frames, Window Center, Window Width (+ VOI LUT Function) | same (were Patient, ID, Sex, Study, Date, Size, Frames, "W/L: center/width" with truncated decimals) | wrong → fixed (8), match (2) |
| exit codes | — | — | ArgumentParser 64 on validation, 1 for JPIP | plumbing |

**Tests**: new target `dicom-viewerTests` (Tests/dicom-viewerTests/ViewerContractTests.swift), `swift test --filter dicom_viewerTests`: 8 tests, 0 failures. `swift build --product dicom-viewer` ok. `check_nema_markers.py Sources/dicom-viewer`: 2/2 files marked 2026a.

**P-items**
- P-VIEWER-FRAME: `--frame` is a 0-based index while DICOM numbers frames from 1 (PS3.3 Table 10-3; Table C.9-2 Image Frame Origin). Kept; additive `--frame-number` (1-based) added. Proposal: deprecate `--frame` in favour of `--frame-number`, or make `--frame` 1-based in the next major version.

**Deferred findings**: none. The engines used (DICOMCore WindowSettings / VOILUTFunction, DICOMKit OverlayPlaneRenderer) are already NEMA-verified 2026a and behaved per the text in the tests.

**Marker text**:
- main.swift: `NEMA-verified: 2026a, checked 2026-10-01 — 22 options (20 + new --voi-lut-function, --frame-number): window per PS3.3 2026a C.11.2.1.2.1 (LINEAR width >= 1; LINEAR_EXACT / SIGMOID width > 0, C.11.2.1.3.1/.2), VOI LUT Function values = the 3 Defined Terms of Table C.11-2b, frame numbering (Frame Number = 0-based --frame + 1; "The first Frame shall be denoted as Frame number 1", Table 10-3), --show-overlay draws 60xx overlay planes (C.9.2); display modes, sizes, ROI, JPIP are plumbing`
- TerminalRenderer.swift: `NEMA-verified: 2026a, checked 2026-10-01 — grayscale pipeline against PS3.3 2026a C.11.1.1.2 (Rescale per frame), Table C.11-2b / C.11.2.1.2.1 / C.11.2.1.3 (3 VOI LUT Function Defined Terms LINEAR, LINEAR_EXACT, SIGMOID; LINEAR when absent; via DICOMCore WindowSettings), C.7.6.3.1.2 (MONOCHROME1 minimum shown white), Table C.9-2 (Overlay Origin 1\1 = upper left pixel, row\column; Overlay Data left to right, top to bottom) and Image Frame Origin "Frames are numbered from 1"; 10 info labels are PS3.6 2026a Table 6-1 names; frame labels are 1-based Frame Numbers`

**Commit**: ffbc8d20 `fix(cli): dicom-viewer VOI LUT function, MONOCHROME1, overlays and frame numbers per DICOM 2026a` (Package.swift hunk = dicom-viewerTests target only; CHANGELOG [Unreleased] section "dicom-viewer grayscale display …").

**diff_cli.py**: no extractor change needed (54 and 22 options found).


### dicom-report (G4) — renders SR documents to text/HTML/JSON/Markdown (PDF not implemented)

The tool renders SR only; it does not create SR. Files: `Sources/dicom-report/main.swift`, `ReportGenerator.swift` (+ README.md). No SR `.dcm` fixture exists under Tests/ (only `Tests/DICOMStudioTests/Fixtures/syn-ct.dcm`), so `dicom-reportTests` builds an Extensible SR fixture (all 16 Value Types, all 7 Relationship Types, root TID 1500 DCMR, COMPLETE/UNVERIFIED/FINAL) through `SRDocumentSerializer` + `DICOMFile.create`. Setting `DICOM_REPORT_FIXTURE_DIR` writes it to disk; the CLI was then run on it in 4 formats, and `scratch/report/diff_report_labels.py` diffed the printed labels against the DocBook.

Compared (by script): PS3.3 Tables C.17.3-7 (16), C.17.3-8 (7), C.17-2 flag Enumerated Values (3 attributes; names against PS3.6 Table 6-1), C.18.8-1, 8.8-1a; PS3.16 6.1 notation, sect_TID_1500 title, Table D-1 (15 DCM concept names in fixture output); PS3.6 Table A-1 SR SOP Class names (`SRDocumentType.description` = A-1 name less " Storage": 20 of 20; the 4 retired 88.1–88.4 Trial classes map to "Unknown"). Label diff after fix: 75 matched, 0 wrong. `diff_cli.py --tool dicom-report`: 0 wrong (4 citations matched).

### Input contract

| Option | DICOM concept | 2026a reference | Allowed per standard | Code accepts | Default std | Default code | Verdict |
|---|---|---|---|---|---|---|---|
| `<file-path>` | SR Document | PS3.3 C.17.3 / Table C.17-6; PS3.6 A-1 | root Value Type CONTAINER | any file; now refuses a non-CONTAINER root with "Not a Structured Report. SOP Class UID indicates: <A-1 name>" (exit 64) | — | — | wrong → fixed |
| `-o, --output` | path | — | — | path | — | required | plumbing |
| `-f, --format` | rendering | — | — | text, html, pdf, json, markdown (pdf throws "requires additional libraries") | — | text | plumbing |
| `--embed-images` | IMAGE references | Table C.17.3-7 | — | flag | — | false | plumbing |
| `--image-dir` | path | — | — | path | — | — | plumbing |
| `--template` | styling preset, NOT a PS3.16 TID | (TIDs come from Content Template Sequence, C.18.8-1) | — | default, cardiology, radiology, oncology; unknown → default silently | — | default | plumbing (P-REPORT-TEMPLATE) |
| `--title` | overrides root CONTAINER Concept Name | Table C.17.3-7 | — | string | — | — | plumbing |
| `--logo` / `--footer` | branding | — | — | path / string | — | — | plumbing (2) |
| `--include-measurements` | NUM table | Table C.18.1-1 | — | flag | — | true | plumbing |
| `--include-summary` | — | — | — | flag, never read | — | true | plumbing (no effect; P-REPORT-SUMMARY) |
| `--language` | heading language | — | — | en, es, fr, de; unknown → en silently | — | en | plumbing |
| `--force` | no DICM preamble | PS3.10 7.1 | — | flag | — | false | plumbing |
| `--verbose` | diagnostics | — | — | flag | — | false | plumbing |

### Output contract

| Output | 2026a reference | Standard | Before | After | Verdict |
|---|---|---|---|---|---|
| JSON `value_type` | PS3.3 Table C.17.3-7 | 16 names | absent | rawValue of ContentItemValueType | missing → added |
| JSON `relationship_type` | Table C.17.3-8 | 7 names | rawValue | unchanged | match |
| JSON `document_type`, HTML/MD subtitle, text header (new) | PS3.6 Table A-1 | SOP Class Name | A-1 name less " Storage" | unchanged; text now prints it too | match |
| `completion_flag` / `verification_flag` / `preliminary_flag` + "Completion Flag:" etc. | Table C.17-2; PS3.6 Table 6-1 names | PARTIAL/COMPLETE; UNVERIFIED/VERIFIED; PRELIMINARY/FINAL | absent | printed in all 4 formats | missing → added |
| `content_template`, "Content Template: TID 1500 Measurement Report (DCMR)" | Table C.18.8-1; PS3.16 TID title (TemplateRegistry, generated) | Mapping Resource + Template Identifier | absent | printed | missing → added |
| Document title | root CONTAINER Concept Name | Table C.17.3-7 | codeMeaning | unchanged | match |
| CODE value | PS3.16 6.1; Table 8.8-1a | (CV, CSD, "CM") | meaning only | triplet; Long/URN Code Value when CV absent; `[CSV]` if version | wrong → fixed |
| NUM value | Table C.18.1-1; CID 82 | Numeric Value + units | `12.0 millimeter`-style (Double) | `12 mm`: whole numbers without `.0`; units = Code Meaning of (0040,08EA), the same in tree, table and JSON | match (format fixed) |
| DATE, TIME, UIDREF, PNAME, COMPOSITE, WAVEFORM, SCOORD, SCOORD3D, TCOORD, TABLE | Table C.17.3-7 | a value | `[Content]` | value printed | missing → fixed (10) |
| Children of non-CONTAINER items | Table C.17-6 | Content Sequence on any item | dropped in all formats, measurement/image/section searches | rendered | wrong → fixed |
| HTML concept/value text | — | — | unescaped | escaped | fixed (injection) |
| Exit codes | — | — | 0 success; 1 error; 64 validation | unchanged | plumbing |

Counts: matched 4, wrong 3 (fixed), missing 4 (fixed), extra 0, plumbing 14.

### Findings / P-items
- P-REPORT-TEMPLATE: `--template` is a presentation preset and falls back to "default" for any unknown value (e.g. `--template 1500` is silently accepted). Proposal: reject unknown values, or rename it to `--style` and keep `--template` as a deprecated alias. PS3.16 TIDs are already shown from the document's Content Template Sequence. Not implemented.
- P-REPORT-SUMMARY: `--include-summary` is parsed but nothing reads it. Proposal: make it gate the impressions/recommendations sections, or deprecate it. Not implemented. `--language` also falls back to `en` silently.
- Help text: the discussion says "image embedding planned", but `--embed-images` works for HTML. Left as is; it is not standard data.

### Deferred findings
| D194 | DICOMKit | Sources/DICOMKit/StructuredReporting/SRDocumentParser.swift:489 | NUM with an empty Measured Value Sequence (Type 2, zero items allowed) is parsed as value 0.0 in the default lenient mode, so renderers print a fabricated "0" measurement | PS3.3 2026a Table C.18.1-1 | Medium | ✅ 2026-10-01 (`488a9c07`) — see the deferred-findings table above |
| D195 | DICOMKit | Sources/DICOMKit/StructuredReporting/SRDocumentParser.swift:499 | Numeric Value Qualifier Code Sequence (0040,A301) is never read (`qualifier: nil`), although `NumericValueQualifier(code:)` exists | PS3.3 2026a Table C.18.1-1; PS3.16 CID 42 | Medium | ✅ 2026-10-01 (`488a9c07`) — see the deferred-findings table above |
| D196 | DICOMKit | Sources/DICOMKit/StructuredReporting/SRDocumentSerializer.swift:898 | Referenced Waveform Channels (0040,A0B0), Type 1C, is not written for WAVEFORM items ("can be added if needed"), so channel references are lost on round-trip | PS3.3 2026a Table C.18.5-1, C.18.5.1.1 | Low | ✅ 2026-10-01 (`488a9c07`) — see the deferred-findings table above |

### Marker text
- ReportGenerator.swift: `// NEMA-verified: 2026a, checked 2026-10-01 — rendered an Extensible SR fixture using all 16 Value Types of PS3.3 2026a Table C.17.3-7 and all 7 Relationship Types of Table C.17.3-8 in text/json/markdown/html and diffed the printed labels by script: 75 matched, 0 wrong (…); before: 10 Value Types printed "[Content]", children of non-CONTAINER items were dropped, no value_type, flags or template were shown`
- main.swift: `// NEMA-verified: 2026a, checked 2026-10-01 — a non-SR input is refused (root Value Type (0040,A040) must be CONTAINER, PS3.3 2026a C.17.3) with its PS3.6 Table A-1 SOP Class name; --format/--template/… are plumbing (presentation; --template is a styling preset, not a PS3.16 TID)`
- `check_nema_markers.py Sources/dicom-report`: 2 of 2 marked, exit 0.

### Tests and commit
- `swift build --product dicom-report`: ok. `swift test --filter dicom_reportTests`: 10 tests, 0 failures (new target `dicom-reportTests`, Tests/dicom-reportTests/SRRenderingTests.swift). The CLI was run on `syn-ct.dcm` and refused it (exit 64).
- Commit 89c3ed93 `fix(cli): dicom-report …`: Sources/dicom-report/{main.swift, ReportGenerator.swift, README.md}, Tests/dicom-reportTests, the Package.swift hunk (target only) and the CHANGELOG bullet, all committed through a temporary index. The owner's DICOMStudio changes are untouched.
- diff_cli.py: no change needed. The extractor found all 14 options. Suggestion for the orchestrator: add `scratch/report/diff_report_labels.py` as an SR-render check (it needs the fixture from `DICOM_REPORT_FIXTURE_DIR=… swift test --filter dicom_reportTests/SRRenderingTests/testWritesFixtureWhenAsked`).


---

## Verification notes

- `Tests/DICOMToolsTests/` (DICOMQRTests, DICOMRetrieveTests, DICOMDcmdirTests, DICOMAITests, …) is compiled by no target: `DICOMToolsTests` is commented out in Package.swift, so those tests have never run. New per-tool test targets (`dicom-queryTests`, `dicom-sendTests`, `dicom-aiTests`, `dicom-videoTests`) are being added as tools are verified; migrating the orphaned files is a follow-up.
- PS3.19 2026a A.1.6 schema does not declare `xml:space`, which Table A.1.5-1 requires on PersonName components; DICOMKit output validates with xmllint only after stripping it. This is a defect in the standard's schema, not in DICOMKit (found 2026-10-01, dicom-xml).
- Four engine findings (D112, D137, D162, D165) share one cause in `DICOMFile.create` (D175). Fixing D175 in DICOMKit closes them for DICOMStudio as well; the CLI tools already pass the UIDs explicitly.
- Nothing in this report is from memory; every row cites the table it was diffed against, or is labelled
  "not checked".
