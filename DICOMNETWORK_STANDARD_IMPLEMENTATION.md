# DICOMNetwork — DICOM Standard Implementation Report

Generated 2026-09-28, last updated 2026-09-28. Covers all 63 Swift files in `Sources/DICOMNetwork/`
(43,212 lines): the upper-layer protocol (PS3.8), DIMSE (PS3.7), and the Verification, Storage,
Query/Retrieve, Modality Worklist, MPPS, Storage Commitment and Print Management service classes
(PS3.4), with their encoders over PS3.5.

**Status: complete.** All five buckets are done: every constant
diffed by script (43 checks, all pass; the `MediumType` raw-value change, P-MAMMO, was approved and
applied on 2026-09-29 with the DICOMPrintKit pass), every behaviour finding fixed with a test, all 63 files marked
(`Scripts/check_nema_markers.py Sources/DICOMNetwork` exits 0). The three deferred rows for this
module (D1, D13, D21) are closed. Three new findings for other modules (D22-D24) are recorded
below. The work is committed on `feature/dicom-tag-modality-audit`, locally, for review.**

Method: [DICOMCORE_STANDARD_IMPLEMENTATION.md → Verification method](DICOMCORE_STANDARD_IMPLEMENTATION.md#verification-method-reuse-for-every-module),
used unchanged. Package target: **DICOM 2026a** (`dicomStandardEdition = "2026a"`,
[DICOMKit.swift](Sources/DICOMKit/DICOMKit.swift)).

**Scope note.** DICOMNetwork carries far less *table* data than DICOMCore or DICOMDictionary and far
more *behaviour*: PDU layouts, the association state machine, DIMSE message field sets, status
codes, negotiation rules and the per-service attribute sets. The audit therefore has two parts.
Every constant the module carries (PDU and item types, command elements, Command Field and
Priority values, reject/abort/result codes, user-identity types, status codes, every
`1.2.840.10008` UID, Q/R levels and keys, print defined terms, storage-commitment and MPPS
attributes, state numbering, AE-title rules) is text-diffed against the frozen 2026a DocBook by
[Scripts/diff_network.py](Scripts/diff_network.py). Behaviour (what is sent when) was checked
clause by clause against the same text: PS3.8 Tables 9-10 (state transitions), 9-11..9-26 and
Annex D/E; PS3.7 §9/§10 status lists, Annex C, Annex D.3 and E.1-1; PS3.4 Annexes B, C, F, H, J,
K; PS3.5 §6.1.2, §6.2, §7.1, §7.5; PS3.3 C.4.13-15, C.13, C.14.1.1; PS3.15 Annex B.12/B.13.
UPS (PS3.4 Annex CC) and the other N-service classes are not implemented by this module, so there
was nothing to compare. TLS itself (PS3.15) is configuration only; the cipher-suite lists of
B.13 are not enforced by the module, and the report says so rather than claiming conformance.

---

## Summary

| Bucket | Files | Meaning | Status |
|---|---|---|---|
| A — cites 2026a | 0 | No file in the module named an edition | — |
| B1 — cites another edition / CP / Sup | 1 (`UserIdentity.swift`, Supplement 99) | Kept as provenance; JWT (type 5) is not from Sup 99 | ✅ Diffed against PS3.7 Tables D.3-14/D.3-15 |
| B2 — no citation, data or behaviour differs from 2026a | 23 | See the bucket table; every finding was verified against the frozen text | ✅ 22 of 23 fixed; `PrintService.swift` MediumType MAMMO terms added 2026-09-29 (P-MAMMO) |
| C1 — plumbing | 9 | Confirmed to carry no standard data; two doc claims corrected (audit, TLS) | ✅ |
| C2 — standard-derived, edition-stable | 30 | Diffed all the same; all constants match | ✅ |

### Baseline diff, before any change (2026-09-28, `Scripts/diff_network.py`)

44 scripted checks against PS3.3, PS3.4, PS3.6, PS3.7 and PS3.8 2026a; 6 failed:

| Check | Standard | Result before |
|---|---|---|
| PDU-type bytes | PS3.8 Tables 9-11..9-26 | 7 / 7 match |
| Item and sub-item type bytes | PS3.8 9-12..9-20, D.1-1; PS3.7 D.3-1..D.3-15 | 12 encoded/decoded; 0x53 Asynchronous Operations Window, 0x56 SOP Class Extended Negotiation, 0x57 Common Extended Negotiation are not implemented (skipped on receipt, as §9.3.1 permits) |
| Command elements (tag, name, VR, VM) | PS3.7 Table E.1-1 | 24 / 24 match; 20 retired elements of E.2-1 not carried by design |
| Command Field values | PS3.7 Table E.1-1 | 23 / 23 match |
| Priority, Command Data Set Type | PS3.7 Table E.1-1 | 3 / 3, 0x0101 match |
| A-ASSOCIATE-RJ result/source values | PS3.8 Table 9-21 | 5 / 5 match |
| A-ASSOCIATE-RJ reason texts, `AssociateRejectPDU` | PS3.8 Table 9-21 | 8 / 8 match |
| A-ASSOCIATE-RJ reason texts, `NetworkConsoleFormatter` | PS3.8 Table 9-21 | **FAIL:** reasons 3 and 7 swapped (calling ↔ called AE title), reason 0 invented for source 3 |
| A-ABORT source/reason values | PS3.8 Table 9-26 | 9 / 9 match |
| Presentation-context Result/Reason values | PS3.8 Table 9-18 | 5 / 5 match |
| User-Identity-Type values | PS3.7 Table D.3-14 | 5 / 5 match |
| `DIMSEStatus` named codes and class | PS3.7 Annex C; PS3.4 B.2-1, C.4-1..3, K.4-1, F.7.2-2, F.8.2-2 | 16 / 16 match; 19 standard codes have no named case (classified by range) |
| Print status codes and meanings | PS3.4 Annex H tables | 21 / 21 codes match; **FAIL:** 0xC600 documented as "film session is printing" (H.4-4: "hierarchy does not contain Film Box SOP Instances"); B601/B602/B603/B60A/C602/C616 not modelled |
| Every `1.2.840.10008` literal registered | PS3.6 Table A-1 | 67 / 69; **FAIL:** `DICOMValidator` lists `1.2.4.107.1` and `.108.1`, which no PS3.6 edition registers (and lacks 29 registered transfer syntaxes) |
| UID names in doc comments | PS3.6 Table A-1 | 28 / 28 match |
| Q/R levels; Q/R and MWL SOP Classes | PS3.4 C.6.1-1, C.6.1.3-1, C.6.2.3-1, K.6.1.4-1 | 4 / 4, 6 / 6, 1 / 1 match |
| R and U keys in the default return keys | PS3.4 C.6-1..C.6-5 | PATIENT 2 / 2, STUDY 7 / 7, SERIES 3 / 3, IMAGE 2 / 2 |
| Print defined terms (11 enums) | PS3.3 C.13.1, C.13.3, C.13.5, C.13.8, C.13.9 | 10 enums match; **FAIL:** `MediumType` has `MAMMO CLEAR` / `MAMMO BLUE` for the terms `MAMMO CLEAR FILM` / `MAMMO BLUE FILM` |
| Storage Commitment failure reasons, action/event IDs, attributes | PS3.3 C.14.1.1; PS3.4 J.3-1, J.3-2 | 6 / 6, 3 / 3, 6 / 9 (Retrieve AE Title and the two File-Set attributes, all Type 3, not carried) |
| MPPS N-CREATE Type 1/2 attributes; PPS status terms | PS3.4 F.7.2-1; PS3.3 C.4.14 | 23 / 23, 3 / 3 |
| State numbering | PS3.8 Tables 9-1..9-5 | **FAIL:** 6 of 9 states carry the wrong Sta number |
| AE title rules | PS3.8 Table 9-11 | **FAIL:** control characters and backslash accepted |

The behaviour findings that no table check can catch are in the Priority action list; the two
worst (a little-endian PDU length in the Storage Commitment SCP, and a 2-byte length header on
64-bit VRs) were the deferred rows D13 and D1.

Tests at the start: `swift test --filter DICOMNetworkTests` — 1,331 XCTest cases, 8 failures (D13);
197 swift-testing cases pass.

Tests at the end (2026-09-28): `swift test --filter DICOMNetworkTests` — 1,401 XCTest cases (70 new), 0
failures; 226 swift-testing cases pass. Full `swift test`: all 9 XCTest bundles (DICOMCore, DICOMKit,
DICOMNetwork, DICOMPrintKit, DICOMRenderKit, DICOMRoundTrip, DICOMStudio, DICOMViewer, DICOMWeb) pass and all
13 swift-testing runs pass (5,165 + 1,504 + 674 + 616 + 474 + 226 + 84 + 53 + 30 + 20 tests), exit 0.

---

## Progress log

| Date | Item | What was compared | What changed | Tests |
|---|---|---|---|---|
| 2026-09-28 | Baseline | All 63 files read in full and bucketed. PS3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.15 2026a fetched (subtitles checked). `Scripts/diff_network.py` written: 44 checks, 6 failed (table above). Behaviour read against PS3.8 Table 9-10, PS3.7 §9/§10 status lists, PS3.4 Annexes B/C/F/H/J/K. | Nothing yet | 1,331 XCTest, 8 failures (D13) |
| 2026-09-28 | D13 | The two "ARTIM" failures traced with timestamps: the SCP's 6-byte header read returned 50,397,184 for a 259-byte PDU (little-endian read of a big-endian field, PS3.8 §9.3.1). Six padding expectations checked against PS3.5 §6.2. | `PDUDecoder.readHeader` at both sites; listener ready-continuation guarded; six expectations corrected (commit ab3e5fc) | 1,331 / 1,331 |
| 2026-09-28 | D1 | `VR.uses4ByteLength` vs PS3.5 Table 7.1-1: OV/SV/UV missing. | Eleven call sites → DICOMCore `VR.uses32BitLength`; duplicate deleted; regression test (commit d271fea) | pass |
| 2026-09-28 | C1/C2 (21 files) | Constants diffed by script; TLS/audit/user-identity claims read against PS3.15 B.12/B.13, A.5 and PS3.7 D.3.3.7. | Doc corrections, markers (commit c8d3f86) | build |
| 2026-09-28 | B2 DIMSE / Q-R / MWL / MPPS (P3, P8-P16) | PS3.8 §9.3.2.2 (D21); PS3.5 §7.1/§7.5/Table 6.2-1; PS3.4 C.4.2.1.4.1, C.2.2.2, K.4.1.1.3.1, F.7.2-1; PS3.7 Table E.1-1, Annex C, §10.x status lists; PS3.6 Table A-1 | 12 commits be777c1..ef8733b (merged d904fa2); markers (f4f8dfd) | 1,365 / 1,365 |
| 2026-09-28 | B2 Print (P17-P24) | PS3.4 Tables H.3.2.2.1-1, H.3.2.2.2-1, H.3.3.2-1, H.4-3, H.4-4, H.4-6, H.4-8, H.4-9, H.4.2.2.1.2-1; PS3.3 C.13.1, C.13.3, Table C.13-5, C.13-8, C.13-9; PS3.7 §10.1.4.1.10, Annex C | 8 commits 3729188..1e13e2a (merged); markers | DICOMNetworkTests and DICOMPrintKitTests green in the worktree |
| 2026-09-28 | B2 Upper layer (P4-P7, P25-P30) | PS3.8 Tables 9-1..9-5, 9-10, 9-11, 9-18, 9-21, 9-26, §7.2.2, Annex D.1, Annex E.2; PS3.7 Tables D.3-1/D.3-3, §10.1.1.1.8, §10.1.4.1.10 | 10 commits 620db54..a9a22a2 (merged); PrintSCP maximum-length rule; markers | 1,339 XCTest + 226 swift-testing in the worktree |
| 2026-09-28 | Close | `Scripts/diff_network.py` re-run: 43 ok, 0 fail, 1 pending (P-MAMMO). `check_nema_markers.py`: 63 of 63. CHANGELOG `[Unreleased]`; DICOMCore status table updated. | — | Full `swift test`: every bundle and run passes, exit 0 (DICOMNetworkTests 1,401 XCTest + 226 swift-testing) |
| 2026-09-29 | P-MAMMO, D40, D41 (with the DICOMPrintKit pass) | PS3.3 Table C.13-1; PS3.5 6.3 and Table 6.2-1 | MAMMO CLEAR FILM / MAMMO BLUE FILM (see P-MAMMO); `PrintPixelDepthConformance` cites PS3.5 6.3; Text String (2030,0020) written through `PrintAnnotation.textStringValue` (LO: 64 characters, no backslash or control characters) | DICOMNetworkTests 1,403, all pass |
| 2026-10-06 | D1 remainder and new D276 (A5); D261–D264 | PS3.5 2026a 7.1.2, Tables 7.1-1/7.1-2; PS3.4 Table B.2-1, Tables C.4-2/C.4-3; PS3.7 Table 9.3-10; PS3.3 Tables C.4-14, C.2-3, C.4-10; PS3.5 Table 6.2-1 DA | `5de7575d` duplicate `VR.uses4ByteLength` deleted, PrintService walker uses `VR.uses32BitLength`; `cf4667c7` NetworkConsole.CStoreOutcome / sendFileResult; `d7609891` NetworkConsole.retrieveFinalResponse; `d2812df4` DICOMMPPSService status / sex / birth-date rules; `29496ff0` WorklistQueryKeys SPS Status terms | diff_kit 0 wrong, diff_network 0, diff_web 0, diff_printkit 0, diff_renderkit 17 ok / 0 failing / 0 deferred, diff_cli 0 FAIL (42 tools), diff_cli_web 0 FAIL, every check_nema_markers run exit 0 (all with --nema 2026a); `check_nema_markers.py`: 66 / 66 |

---

## Priority action list

| # | What | Standard | Impact | Status |
|---|---|---|---|---|
| P1 | D1: 64-bit VRs got a 2-byte length header in every Explicit VR encoder/parser | PS3.5 §7.1.2 | **High:** wire corruption | ✅ d271fea |
| P2 | D13: Storage Commitment SCP and listener read the PDU length little-endian; six test expectations wrong | PS3.8 §9.3.1; PS3.5 §6.2 | **High:** every commitment association hung until the peer gave up | ✅ ab3e5fc |
| P3 | D21: C-GET dropped the last 43 Storage SOP Classes | PS3.8 §9.3.2.2 | Medium: zero instances for those classes | ✅ be777c1 (batches of 127, second pass only on failures) |
| P4 | A-ASSOCIATE-AC omitted the Transfer Syntax sub-item for rejected contexts | PS3.8 Table 9-18 | Medium: strict decoders reject the AC | ✅ 620db54 |
| P5 | A-ABORT sent a non-zero reason with the service-user source; protocol errors used the user source; the abort on a local timeout was never transmitted | PS3.8 Table 9-26, Table 9-9 AA-1/AA-8 | Medium | ✅ 66afdbc |
| P6 | A-RELEASE-RQ received while established was not answered; release collision closed without waiting for the peer's A-RELEASE-RP | PS3.8 Table 9-10 AR-2/AR-4, AR-9/AR-3 | Medium: peers hang until their timer | ✅ 66afdbc |
| P7 | State numbering wrong for 6 of 9 states; Sta13 ignored A-ABORT/ARTIM; requestor timeouts mislabelled AA-2 | PS3.8 Tables 9-1..9-5, 9-10 | Low (labels) / Medium (Sta13) | ✅ f4d6a95 |
| P8 | Retrieve identifier out of tag order; non-ASCII values emptied, no (0008,0005); duplicate keys | PS3.5 §7.1; PS3.4 C.4.2.1.4.1 | Medium | ✅ 02e0ecd |
| P9 | `parseQueryResponse` merged nested sequence items into the top level | PS3.5 §7.5 | Medium: wrong attribute values | ✅ 68a7e95 |
| P10 | Rows/Columns (US) parsed as text, always nil | PS3.5 Table 6.2-1 | Low | ✅ 0effe5f |
| P11 | Store-and-forward queue sent LOW priority first | PS3.7 Table E.1-1 | Medium | ✅ c7bd921 |
| P12 | Command-set AE/LO values NUL-padded | PS3.5 Table 6.2-1 | Low-Medium | ✅ 841dbc7 |
| P13 | `DICOMValidator` transfer-syntax list: 2 unregistered, 29 missing | PS3.6 Table A-1 | Medium: valid files flagged unknown | ✅ 525f4da |
| P14 | MWL identifier sent a zero-length (0008,0005); undeclared responses decoded as Latin-1 | PS3.4 C.2.2.2, K.4.1.1.3.1; PS3.5 §6.1.2 | Medium | ✅ bf2c2d1 |
| P15 | MPPS: fabricated SPS ID, hand-built command sets with odd-length UIDs, Type comments | PS3.4 F.7.2-1; PS3.7 §6.3.1 | Low-Medium | ✅ 1f3e84c |
| P16 | Batch C-STORE trapped past 128 distinct classes | PS3.8 §9.3.2.2 | Low | ✅ dc81b6e (groups of 128 per association) |
| P17 | Print N-ACTION-RSP carried the Print Job as Affected SOP Instance and no (2100,0500); SCU guessed the job UID from it | PS3.4 Tables H.4-3/H.4-8; PS3.7 §10.1.4 | **High** for interop with real printers | ✅ b42c4d7 |
| P18 | Meta SOP Class treated as covering Print Job, Presentation LUT, Annotation Box and both image boxes | PS3.4 Tables H.3.2.2.1-1, H.3.2.2.2-1, H.3.3.2-1 | Medium | ✅ 3e78ba7 |
| P19 | Print statuses: C000 for C600, failure for the B602/B603 warnings, 0106 for 0123, 0122 for 0211; 0xC600 documented wrongly | PS3.4 Tables H.4-4, H.4-9; PS3.7 Annex C | Medium | ✅ b42c4d7 |
| P20 | Execution Status Info free text in a CS | PS3.3 C.13.8 | Low | ✅ f915e10 |
| P21 | Colour image box interleaved, no Planar Configuration; Bits Allocated 16 accepted for colour | PS3.3 Table C.13-5 | Medium | ✅ 7d3e558 |
| P22 | Print Job N-GET carried Number of Copies, lacked Originator | PS3.3 Table C.13-8 | Low | ✅ 3729188 |
| P23 | Printer N-GET without data set reported NORMAL | PS3.3 C.13.9 | Low | ✅ 9e21356 |
| P24 | ~20 wrong PS3.3/PS3.4 section citations in the print files | — | Low | ✅ 93ff87e |
| P25 | A-ASSOCIATE-RJ reasons: 2 for 3 (StorageSCP, PrintSCP), ACSE source with reason 3 (listener), formatter 3/7 swapped + phantom 0 | PS3.8 Table 9-21 | Medium: operators told to fix the wrong AE title | ✅ fb307d1 |
| P26 | Peer maximum length 0 treated as 0; limit applied to every PDU type; fragments 6 bytes too small | PS3.8 Annex D.1, Table 9-23 | Medium | ✅ 60bd0ab |
| P27 | AE titles accepted control characters and backslash | PS3.8 Table 9-11; PS3.5 Table 6.2-1 | Low-Medium | ✅ 03e7ce3 |
| P28 | No limits on Implementation Class UID / Version Name; Protocol-version bit 0 never tested | PS3.7 D.3-1/D.3-3; PS3.8 Table 9-11 | Low | ✅ 85a7ee2, fb307d1 |
| P29 | Listener never answered an N-EVENT-REPORT-RQ without a data set; SCP used 0110/0122 for unknown action type / SOP class | PS3.4 J.3.3.1.3; PS3.7 §10.1.4.1.10 | Medium | ✅ 4136039, 9d8ac0a |
| P30 | StorageSCP silently ignored unsupported requests | PS3.7 Annex C (0211H) | Low-Medium | ✅ a9a22a2 |
| P31 | Doc claims: TLS "PS3.8 Annex A", audit "PS3.15/ATNA", Supplement 99 for JWT, "16KB" defaults | PS3.15 B.12/B.13, A.5; PS3.7 D.3-14 | Low | ✅ c8d3f86 |
| P-MAMMO | `MediumType.mammoFilmClearBase` / `mammoFilmBlueBase` raw values are `MAMMO CLEAR` / `MAMMO BLUE` | PS3.3 C.13.1: `MAMMO CLEAR FILM`, `MAMMO BLUE FILM` | Medium: a wrong Medium Type on the wire when selected | ✅ 2026-09-29, approved with the DICOMPrintKit pass and implemented as recommended: `mammoClearFilm` / `mammoBlueFilm` added, the old cases deprecated (renamed), still parsed and normalized, `wireValue` always writes the term, `allCases` lists the five terms; `diff_network.py` has no pending entry. DICOMStudio's `PrintMediumType` has no MAMMO case, so the D22 remainder is only its own terms |

### Decisions taken without asking (all within the method's "fix behaviour that contradicts the standard")

- **Batch C-GET (P3):** one C-GET per batch of 127 classes rather than a new API for "propose these
  classes" (the existing `storageSopClasses:` parameter still lets a caller pick). A second pass runs
  only when the first reported failures, so the common case costs one association.
- **Empty pages print (P19):** a Film Box N-ACTION whose image boxes are empty now prints an
  empty page with warning B603 (Table H.4-9 defines no failure for it); the composer fills unfilled
  cells with Empty Image Density.
- **AE title tightening (P27):** `AETitle(...)` now throws for TAB, control characters, DEL and
  backslash, which it used to accept. This is validation, not a signature change.
- **Requestor timeouts (P7):** the 30 s wait for A-ASSOCIATE-AC / A-RELEASE-RP is kept (PS3.8 has
  no such timer on the requestor side) but is labelled a local timeout handled as AA-1, and the
  A-ABORT it sends now uses the service-user source with reason 0.
- **Discarded P-DATA during release (P6):** PS3.8 §7.2.2 lets the acceptor keep sending P-DATA
  until it answers the release (AR-6 "issue P-DATA indication"); `release()` has no consumer, so the
  data is dropped and the comment now says so instead of claiming §7.2 requires it.

### Explicitly out of scope — do not chase

- Sub-items 0x53 (Asynchronous Operations Window), 0x56 (SOP Class Extended Negotiation) and 0x57
  (Common Extended Negotiation): not implemented; skipped on receipt as PS3.8 §9.3.1 permits.
  Relational queries and Enhanced Multi-Frame conversion are therefore not negotiated.
- UPS (PS3.4 Annex CC) and the other N-service classes (Instance Availability, Media Creation, RT
  Machine Verification, Display System, Inventory): not implemented by this module.
- PS3.15 B.13 cipher-suite enforcement: Network.framework chooses the suites; the header says so.
  Producing PS3.15 A.5 audit messages: not a feature of `AuditLogger`; the header says so.
- Named `DIMSEStatus` cases for the 19 standard codes the enum lacks (0105H, 0106H, 0107H, 0113H …
  0212H, A701H, A702H, 0001H): adding cases is a public API change; the range classification
  handles them correctly (tested), and the SCPs emit them through `DIMSEStatus.from(_:)`.
- `Tag.originatingPrintManagement` (2100,0070): the PS3.6 keyword is `Originator`; renaming is API,
  a FIXME marks it.

---

## Deferred findings

**Carried in from the earlier reports:**

| ID | Location | Problem | Standard (2026a) | Status |
|---|---|---|---|---|
| D1 | `QueryService.swift` `VR.uses4ByteLength` | Private copy of the Explicit VR length rule omitted OV, SV and UV; 11 encoder/parser call sites | PS3.5 §7.1.2, Tables 7.1-1, 7.1-2 | ✅ Done 2026-09-28, commit d271fea: all call sites use DICOMCore's `VR.uses32BitLength`, duplicate deleted, regression test; audit 2026-10-06 (A5): the duplicate `VR.uses4ByteLength` was in fact still present (`QueryService.swift`, pinned by `QueryServiceTests`); ✅ 2026-10-06 `5de7575d`: duplicate deleted, PrintService's data-set walker moved to `VR.uses32BitLength` as well (D276) (PS3.5 2026a 7.1.2, Tables 7.1-1/7.1-2) |
| D13 | DICOMNetworkTests (8 failures) | Six were test expectations that contradicted PS3.5 §6.2 even-length padding. Two "ARTIM timeouts" were a wire bug: `StorageCommitmentSCP` and the commitment listener read the 4-byte PDU length little-endian, so a 259-byte A-ASSOCIATE-RQ was taken for a 50 MB PDU | PS3.5 §6.2; PS3.8 §9.3.1 / Table 9-11 | ✅ Done 2026-09-28, commit ab3e5fc: both sites use `PDUDecoder.readHeader`; expectations corrected; 1,331 / 1,331 pass |
| D21 | `RetrieveService.swift` C-GET storage contexts | 127-context limit dropped the last 43 of the 170 Storage SOP Classes | PS3.8 §9.3.2.2; PS3.4 C.4.3 | ✅ Done 2026-09-28, commit be777c1 (P3): storage classes proposed in batches of 127 (`storageContextBatches`), a second C-GET on a new association only when the first pass reported failures, results merged |

**New findings for other modules** (recorded, not fixed here):

| ID | Module | Location | Problem | Standard (2026a) | Severity | Status |
|---|---|---|---|---|---|---|
| D22 | DICOMStudio | [NetworkingModel.swift](Sources/DICOMStudio/Models/NetworkingModel.swift) `PrintMediumType.bluFilm = "BLU-RAY"` and the re-declared print enums (~L907-1050) | `BLU-RAY` is not a Medium Type defined term; the app re-declares `PrintPriority`, `PrintMediumType`, `PrintFilmSize`, `PrintJobStatus` with their own strings instead of using DICOMNetwork's enums, and inherits `MAMMO CLEAR` / `MAMMO BLUE` (see P-MAMMO) | PS3.3 C.13.1 (PAPER, CLEAR FILM, BLUE FILM, MAMMO CLEAR FILM, MAMMO BLUE FILM) | Medium: a wrong value on the wire if selected | ✅ 2026-10-05 `6ab02140` (audit 2026-10-06, was "⏳ Open"): strings fixed; the duplicate enums are P-STUDIO-PRINT-ENUMS, see DICOMSTUDIO_STANDARD_IMPLEMENTATION.md |
| D23 | DICOMPrintKit | [PrintOptionCatalog.swift](Sources/DICOMPrintKit/PrintOptionCatalog.swift) (~L256) | Cites "PS3.3 Table C.13-3" for the Bits Stored 8/12 rule; the image-box pixel enumerations are Table C.13-5 (C.13-3 is the Film Box Presentation Module). Its `mediumTypes` list also omits the two MAMMO values | PS3.3 Table C.13-5, C.13.1 | Low: text | ✅ citations 2026-09-29 (DICOMPRINTKIT_STANDARD_IMPLEMENTATION.md); the MAMMO values 2026-09-29 with P-MAMMO |
| D24 | DICOMKit | [ImagePreprocessor.swift:23](Sources/DICOMKit/ImagePreprocessor.swift#L23) `PrintColorMode` | Second declaration of DICOMNetwork's `PrintColorMode` (same raw values). Not a standard error; a duplication to collapse when DICOMKit is audited | — | Low | ✅ Done 2026-09-29, `535d609` (DICOMKit pass): one `DICOMCore.PrintColorMode`, typealiases in DICOMKit and DICOMNetwork |
| D276 | DICOMNetwork | `PrintService.swift` data-set walker (~L3823; audit A5) | The walker hard-coded the 10 VRs that take a 4-byte length (`["OB","OD","OF","OL","OW","SQ","UC","UN","UR","UT"]`), so an OV, SV or UV element was read with a 2-byte length and the walk lost sync | PS3.5 2026a 7.1.2, Tables 7.1-1 / 7.1-2 | Medium | ✅ 2026-10-06 `5de7575d`: the walker uses DICOMCore's `VR.uses32BitLength` (PS3.5 2026a 7.1.2, Tables 7.1-1/7.1-2) |

---

## Bucket B1 — Cites a Supplement (1 file)

| File | Before | After |
|---|---|---|
| [UserIdentity.swift](Sources/DICOMNetwork/UserIdentity.swift) | Cited "Supplement 99" for all five identity types; Sup 99 defined types 1-4, JWT (5) came later (the introducing CP is not named in the 2014a-2026c release notes; CP 2405 in 2024e only clarifies JWT use) | ✅ Types 1-5 and the RQ/AC sub-item layouts text-diffed against PS3.7 2026a Tables D.3-14 / D.3-15; Sup 99 kept as provenance for 1-4. Marked. |

## Bucket B2 — No citation, data or behaviour differs from 2026a (23 files)

| File | Before | After |
|---|---|---|
| [AETitle.swift](Sources/DICOMNetwork/AETitle.swift) | Accepted TAB/NUL/ESC/DEL/backslash; `.whitespaces` trim | ✅ 0x20-0x7E minus 0x5C, SPACE trim, NUL tolerated on decode (P27). Marked. |
| [AssociateAcceptPDU.swift](Sources/DICOMNetwork/AssociateAcceptPDU.swift) | No Transfer Syntax sub-item for rejected contexts; no length limits | ✅ Table 9-18 sub-item always present; limits enforced (P4, P28). Marked. |
| [Association.swift](Sources/DICOMNetwork/Association.swift) | A-RELEASE-RQ unanswered; collision closed early; user-source abort with reason; abort not sent on timeout; max length 0 → 0 | ✅ P5, P6, P26. Marked. |
| [AssociationStateMachine.swift](Sources/DICOMNetwork/AssociationStateMachine.swift) | 6 wrong Sta numbers; Sta13 ignored A-ABORT/ARTIM | ✅ P7. Marked. |
| [CommandSet.swift](Sources/DICOMNetwork/CommandSet.swift) | NUL pad for AE/LO | ✅ P12. Marked. |
| [DICOMConnection.swift](Sources/DICOMNetwork/DICOMConnection.swift) | Max length applied to every PDU; 0 rejected everything | ✅ P26. Marked. |
| [DICOMValidator.swift](Sources/DICOMNetwork/DICOMValidator.swift) | 36-entry hand list of transfer syntaxes (2 unregistered, 29 missing) | ✅ DICOMCore registry (P13). Marked. |
| [MessageAssembler.swift](Sources/DICOMNetwork/MessageAssembler.swift) | Fragment = max − 12; 0 → 4096 | ✅ max − 6; 0 = unlimited (P26). Marked. |
| [ModalityWorklistService.swift](Sources/DICOMNetwork/ModalityWorklistService.swift) | Zero-length (0008,0005); Latin-1 default decode | ✅ P14. Marked. |
| [NetworkConsoleFormatter.swift](Sources/DICOMNetwork/NetworkConsoleFormatter.swift) | Reasons 3/7 swapped, reason 0 invented, misleading hint | ✅ Delegates to `AssociateRejectPDU` (P25). Marked. |
| [PrintPresentationContexts.swift](Sources/DICOMNetwork/PrintPresentationContexts.swift) | Meta class "covered" 8 classes | ✅ 4 members per Tables H.3.2.2.x-1 (P18). Marked. |
| [PrintSCP.swift](Sources/DICOMNetwork/PrintSCP.swift) | Wrong N-ACTION-RSP shape; C000/0106/0122 statuses; free-text CS; reason 2 | ✅ P17, P19, P20, P25. Marked. |
| [PrintSCPEncoder.swift](Sources/DICOMNetwork/PrintSCPEncoder.swift) | Print Job N-GET with Number of Copies, without Originator | ✅ P22, (2100,0500) builder (P17). Marked. |
| [PrintSCPParser.swift](Sources/DICOMNetwork/PrintSCPParser.swift) | Bits Allocated 16 on colour; Planar Configuration ignored | ✅ P21. Marked. |
| [PrintSCPTypes.swift](Sources/DICOMNetwork/PrintSCPTypes.swift) | 0xC600 documented as "printing"; C601 scope | ✅ P19 (codes 21/21 match). Marked. |
| [PrintService.swift](Sources/DICOMNetwork/PrintService.swift) | Job UID from Affected SOP Instance; interleaved colour without Planar Configuration; NORMAL fabricated; ~12 wrong citations; MAMMO terms | ✅ P17, P21, P23, P24; P-MAMMO 2026-09-29. Marked. |
| [QueryResults.swift](Sources/DICOMNetwork/QueryResults.swift) | Rows/Columns parsed as text | ✅ P10. Marked. |
| [QueryService.swift](Sources/DICOMNetwork/QueryService.swift) | D1 length rule; nested items flattened | ✅ P1, P9. Marked. |
| [RetrieveService.swift](Sources/DICOMNetwork/RetrieveService.swift) | D21; identifier order/charset/duplicates | ✅ P3, P8. Marked. |
| [StorageCommitmentSCP.swift](Sources/DICOMNetwork/StorageCommitmentSCP.swift) | D13 PDU length; 0110/0122 statuses; transient/ACSE reject | ✅ P2, P25, P29. Marked. |
| [StorageCommitmentService.swift](Sources/DICOMNetwork/StorageCommitmentService.swift) | D13 PDU length in the listener; reject codes; unanswered N-EVENT-REPORT-RQ; "Table J.3-3" citations (the failure reasons are PS3.3 C.14.1.1) | ✅ P2, P25, P29. Marked. |
| [StorageSCP.swift](Sources/DICOMNetwork/StorageSCP.swift) | Reason 2 for 3; max length on every PDU; unsupported requests ignored | ✅ P25, P26, P30. Marked. |
| [StoreAndForwardQueue.swift](Sources/DICOMNetwork/StoreAndForwardQueue.swift) | LOW dequeued first | ✅ P11. Marked. |

## Bucket C1 — Plumbing (9 files)

| File | Confirmed | Result |
|---|---|---|
| [AuditLogger.swift](Sources/DICOMNetwork/AuditLogger.swift) | Event names and JSON-Lines schema are DICOMKit's own; no PS3.15 A.5 content. The header claimed "PS3.15 / ATNA alignment" | ✅ Header rewritten to say what it is (and is not). Marked. |
| [BandwidthLimiter.swift](Sources/DICOMNetwork/BandwidthLimiter.swift) | Token-bucket constants only | ✅ Marked |
| [CircuitBreaker.swift](Sources/DICOMNetwork/CircuitBreaker.swift) | Thresholds and timers only | ✅ Marked |
| [DICOMClient.swift](Sources/DICOMNetwork/DICOMClient.swift) | Facade; defaults only ("16KB" doc corrected to the 64 KB default) | ✅ Marked |
| [DICOMLogger.swift](Sources/DICOMNetwork/DICOMLogger.swift) | Log categories only | ✅ Marked |
| [DICOMNetwork.swift](Sources/DICOMNetwork/DICOMNetwork.swift) | Documentation; example UIDs registered in A-1 | ✅ Marked |
| [DICOMStorageClient.swift](Sources/DICOMNetwork/DICOMStorageClient.swift) | Pool/retry plumbing; defaults only | ✅ Marked |
| [QRSessionState.swift](Sources/DICOMNetwork/QRSessionState.swift) | CLI resume state; no standard data (note: reads Modality (0008,0060) from a STUDY row, where a C-FIND SCP returns Modalities in Study (0008,0061), Table C.6-5 — CLI display only) | ✅ Marked (display only; the study-level Modality read is noted, not changed) |
| [QueryResultFormatter.swift](Sources/DICOMNetwork/QueryResultFormatter.swift) | Column lists only | ✅ Marked |

## Bucket C2 — Standard-derived, edition-stable (30 files)

| File | Standard data | Result |
|---|---|---|
| [AbortPDU.swift](Sources/DICOMNetwork/AbortPDU.swift) | PS3.8 Table 9-26 | ✅ Layout matches; user-source reason forced to 0 (P5). Marked. |
| [AssociateRejectPDU.swift](Sources/DICOMNetwork/AssociateRejectPDU.swift) | PS3.8 Table 9-21 | ✅ 12 / 12 texts and values match. Marked. |
| [AssociateRequestPDU.swift](Sources/DICOMNetwork/AssociateRequestPDU.swift) | PS3.8 Tables 9-11..9-16, D.1-1; PS3.7 D.3-1/D.3-3; A.2.1 | ✅ Layout matches; limits now enforced (P28). Marked. |
| [CommandTag.swift](Sources/DICOMNetwork/CommandTag.swift) | PS3.7 Table E.1-1 | ✅ 24 / 24 (tag, name, VR, VM). Marked. |
| [ConnectionPool.swift](Sources/DICOMNetwork/ConnectionPool.swift) | Verification UID, 2 transfer syntaxes | ✅ Registered. Marked. |
| [DICOMNetworkError.swift](Sources/DICOMNetwork/DICOMNetworkError.swift) | PS3.8 Tables 9-21, 9-26 enums | ✅ 14 / 14; ARTIM citation §9.1.5. Marked. |
| [DIMSECharacterSet.swift](Sources/DICOMNetwork/DIMSECharacterSet.swift) | PS3.5 §6.1.2 terms | ✅ Marked. |
| [DIMSECommand.swift](Sources/DICOMNetwork/DIMSECommand.swift) | PS3.7 Table E.1-1 Command Field | ✅ 23 / 23. Marked. |
| [DIMSEMessages.swift](Sources/DICOMNetwork/DIMSEMessages.swift) | PS3.7 Tables 9.3-x, 10.3-x | ✅ Field sets match; citations corrected. Marked. |
| [DIMSEPriority.swift](Sources/DICOMNetwork/DIMSEPriority.swift) | PS3.7 Table E.1-1 Priority | ✅ 3 / 3. Marked. |
| [DIMSEStatus.swift](Sources/DICOMNetwork/DIMSEStatus.swift) | PS3.7 Annex C; PS3.4 status tables | ✅ 16 / 16 named codes; ranges tested; texts corrected. Marked. |
| [DataTransferPDU.swift](Sources/DICOMNetwork/DataTransferPDU.swift) | PS3.8 Tables 9-22/9-23, E.2 | ✅ Marked. |
| [MPPSService.swift](Sources/DICOMNetwork/MPPSService.swift) | PS3.4 Table F.7.2-1, F.1-3; PS3.3 C.4.14 | ✅ 23 / 23 Type 1/2 attributes; P15 fixes. Marked. |
| [PDU.swift](Sources/DICOMNetwork/PDU.swift) | PS3.8 Annex D.1 | ✅ Docs reworded; `negotiatedMaxPDUSize` (P26). Marked. |
| [PDUDecoder.swift](Sources/DICOMNetwork/PDUDecoder.swift) | PS3.8 Tables 9-11..9-26; PS3.7 D.3-x | ✅ 12 item types; Protocol-version kept. Marked. |
| [PDUType.swift](Sources/DICOMNetwork/PDUType.swift) | PS3.8 PDU-type bytes | ✅ 7 / 7. Marked. |
| [PresentationContext.swift](Sources/DICOMNetwork/PresentationContext.swift) | PS3.8 Table 9-18, §9.3.2.2 | ✅ 5 / 5. Marked. |
| [PrintDatasetReader.swift](Sources/DICOMNetwork/PrintDatasetReader.swift) | PS3.5 §7.1/7.5 | ✅ Marked. |
| [PrintPixelDepthConformance.swift](Sources/DICOMNetwork/PrintPixelDepthConformance.swift) | PS3.3 Table C.13-5 | ✅ Citation corrected. Marked. |
| [QueryKeys.swift](Sources/DICOMNetwork/QueryKeys.swift) | PS3.4 C.6-1..C.6-5; PS3.6 6-1 | ✅ Patient's Age relabelled study-level. Marked. |
| [QueryLevel.swift](Sources/DICOMNetwork/QueryLevel.swift) | PS3.4 Table C.6.1-1 | ✅ 4 / 4. Marked. |
| [QueryRetrieveInformationModel.swift](Sources/DICOMNetwork/QueryRetrieveInformationModel.swift) | PS3.4 C.6.1.3-1, C.6.2.3-1; PS3.6 A-1 | ✅ 9 / 9. Marked. |
| [ReleasePDU.swift](Sources/DICOMNetwork/ReleasePDU.swift) | PS3.8 Tables 9-24/9-25 | ✅ Marked. |
| [RetryPolicy.swift](Sources/DICOMNetwork/RetryPolicy.swift) | 4 storage UIDs | ✅ Registered; doc example fixed. Marked. |
| [SCPSCURoleSelection.swift](Sources/DICOMNetwork/SCPSCURoleSelection.swift) | PS3.7 D.3-9/D.3-10, D.3.3.4 | ✅ Marked. |
| [SendFileGatherer.swift](Sources/DICOMNetwork/SendFileGatherer.swift) | PS3.10 §7.1 | ✅ Marked. |
| [StorageService.swift](Sources/DICOMNetwork/StorageService.swift) | PS3.7 9.3-1; PS3.4 B.2-1; PS3.8 §9.3.2.2 | ✅ Contexts grouped per association (P16). Marked. |
| [TLSConfiguration.swift](Sources/DICOMNetwork/TLSConfiguration.swift) | PS3.15 B.12/B.13 | ✅ Header states what is and is not met. Marked. |
| [TransferPriorityQueue.swift](Sources/DICOMNetwork/TransferPriorityQueue.swift) | PS3.7 Priority | ✅ Citation corrected. Marked. |
| [VerificationService.swift](Sources/DICOMNetwork/VerificationService.swift) | PS3.7 9.3-12/13; 3 UIDs | ✅ Marked. |

---

## Verification notes

- Reproduce: `python3 Scripts/nema_docbook.py fetch 2026a N --out DIR` for N = 3, 4, 6, 7, 8
  (subtitles must read "DICOM PS3.N 2026a - …"), then `python3 Scripts/diff_network.py --nema DIR`.
  Expected: 43 ok, 0 FAIL, 0 PEND (P-MAMMO applied 2026-09-29). PS3.15 was read for the TLS header only.
- Behaviour clauses were compared by reading the extracted text (PS3.8 Table 9-10 cells, PS3.7
  status lists, PS3.4 Annex H/J/K prose); they are not scriptable and are cited in the markers and
  in the per-item tests (`UpperLayerConformanceTests`, `DIMSEConformanceTests`,
  `PrintConformanceTests`).
- The introducing CP for User-Identity-Type 5 (JWT) could not be located in the 2014a-2026c release
  notes mirror; only CP 2405 (2024e) mentions JWT. The marker names the 2026a table, not a CP.
- Not checked, by decision: the Storage Commitment optional attributes (Retrieve AE Title, Storage
  Media File-Set ID/UID, all Type 3, not carried); the dcm4chee REST / HL7 ORM paths of
  `ModalityWorklistService` (not DICOM); the MLLP framing.
- Leniencies kept on purpose and documented in code: undeclared bytes ≥ 0x80 in MWL responses decode
  as Latin-1 after the default repertoire fails; Presentation LUT Shape `INVERSE` accepted by the
  print SCP; YBR photometric accepted on the colour image box.
- Test-port note: the loopback tests bind fixed ports 19140-19143 and 19171-19177 on 127.0.0.1.
