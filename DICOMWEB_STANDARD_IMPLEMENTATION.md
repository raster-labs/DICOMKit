# DICOMWeb — DICOM Standard Implementation Report

Generated 2026-09-28, last updated 2026-09-28. Covers all 54 Swift files in `Sources/DICOMWeb/`
(27,340 lines): the DICOM JSON Model (PS3.18 Annex F), the Native DICOM Model XML (PS3.19 Annex
A.1), the RESTful client for the Studies Service (WADO-RS, QIDO-RS, STOW-RS, PS3.18 Chapter 10)
and the Worklist Service (UPS-RS, Chapter 11), the URI Service client (WADO-URI, Chapter 9), an
embeddable server for the same services, and the HTTP, caching, OAuth2 and logging plumbing.

**Status: complete.** All five buckets are done: every constant the module carries is diffed
by script (`Scripts/diff_web.py`: 35 of 35 checks pass, 0 pending), every behaviour finding is
fixed with a test, and all 54 files carry a `NEMA-verified` marker
(`Scripts/check_nema_markers.py Sources/DICOMWeb` exits 0). The four public-API decisions
(P-STOW, P-EVENT, P-PRIORITY, P-URI) were approved by the owner on 2026-09-28 and applied
(commit df9d92b), as was the open P-CREATE item. The three deferred rows for this module (D2,
D3, D4) are closed. One new finding for DICOMCore (D25) was recorded below and fixed the same day. The work is
committed on `feature/dicom-tag-modality-audit`, locally, for review.

Method: [DICOMCORE_STANDARD_IMPLEMENTATION.md → Verification method](DICOMCORE_STANDARD_IMPLEMENTATION.md#verification-method-reuse-for-every-module),
used unchanged. Package target: **DICOM 2026a** (`dicomStandardEdition = "2026a"`,
[DICOMKit.swift](Sources/DICOMKit/DICOMKit.swift)).

**Scope note.** DICOMWeb is behaviour-heavy, like DICOMNetwork: its tables are the VR-to-JSON
mapping, the media type and transfer syntax tables, the URI templates and query parameter names,
the status code and header tables per transaction, the Store Instances Response Module, the QIDO
matching and return attributes, and (for UPS-RS) the state transition table, the N-CREATE
attribute list and the event table of PS3.4 Annex CC. All of those are extracted from the Swift
by regex and diffed against the frozen 2026a DocBook by [Scripts/diff_web.py](Scripts/diff_web.py).
Behaviour (what is sent when, what a server answers) was read clause by clause against the
same text: PS3.18 F.2.2-F.2.7, 8.3.3-8.3.5, 8.5, 8.6.1, 8.7.1-8.7.8, 8.10, 9.1-9.5, 10.4-10.6,
11.4-11.12, Annex I; PS3.19 A.1.1-A.1.6; PS3.4 CC.1.1, CC.2.1-CC.2.8; PS3.5 6.2, 7.8.1, 9.1.
HTTP itself (RFC 7230-7235, 6455), OAuth2 (RFC 6749), SMART on FHIR scopes, JWT handling and
the WebSocket framing are not DICOM and are not scored; PS3.18 only names them.

---

## Summary

| Bucket | Files | Meaning | Status |
|---|---|---|---|
| A — cites 2026a | 0 | No file in the module named the target edition | — |
| B1 — cites another edition / CP / Sup | 1 (`ConformanceStatement.swift`, "2024c") | Default `dicomVersion` moved to the package target | ✅ |
| B2 — no citation, data or behaviour differs from 2026a | 27 | See the bucket table; every finding verified against the frozen text | ✅ All 27 fixed (4 after owner approval, df9d92b) |
| C1 — plumbing | 17 | Confirmed to carry no standard data | ✅ |
| C2 — standard-derived, edition-stable | 9 | Diffed all the same; all constants match | ✅ |

### Baseline diff, before any change (2026-09-28, `Scripts/diff_web.py`)

21 scripted checks against PS3.3, PS3.4, PS3.6, PS3.18 and PS3.19 2026a; 16 failed, 4 pending
(the check count grew to 35 as fixes split checks; the pending ones are unchanged):

| Check | Standard | Result before |
|---|---|---|
| VR → JSON data type, encoder and decoder | PS3.18 Table F.2.3-1 | 34 / 34 (DS, IS, SV, UV as "Number or String") |
| JSON object layout | PS3.18 F.2.2-F.2.7 | **FAIL:** InlineBinary/BulkDataURI inside `Value` (D2); AT read `uint32Values`, nil for AT (D3); Group Length written; no `null` for empty values; empty attributes dropped |
| Native DICOM Model elements and VRs | PS3.19 Table A.1.5-2, A.1.6 | **FAIL:** OV not binary (D4); no `<Value>` at all for FL/FD/SL/SS/UL/US/SV/UV/AT (encoder read `stringValues`, nil for them; decoder stored numeric text as the Value Field); no `xml:space`; no `privateCreator`; `uuid` ignored |
| Media type names | PS3.18 8.7.3.5, Tables 8.7.3-3/5, 8.7.4-1 | 15 / 15 match; image/jpx, image/jxl, image/dicom-rle, application/x-deflate missing |
| Multipart `type` parameter quoting | PS3.18 8.7.1, RFC 2045 §5.1 | **FAIL:** `type=application/dicom` unquoted (contains a tspecial) |
| Transfer syntax → bulk data media type | PS3.18 Tables 8.7.3-4, 8.7.3-5 | **FAIL:** not carried; frames requested as `type="application/dicom"` |
| Accept for frames (pixel data) | PS3.18 Table 10.4.4-1 | **FAIL:** application/dicom is not a pixel data media type |
| Every `1.2.840.10008` literal registered | PS3.6 Table A-1 | 34 / 34 |
| UID names next to literals | PS3.6 Table A-1 | 44 / 49; 5 comments ("JPEG Lossless SV1", "HTJ2K Lossy", …) |
| URI templates (builder + router) | PS3.18 Tables 10.4.1-x, 10.5.1-1, 10.6.1-1, 11.1.1-1, 11.4.1-1, 11.10-11.12 | 28 / 28 match; `/workitems?workitem=` and the filtered/global suspend templates missing; 5 dcm4chee-style extensions |
| RESTful query parameter names | PS3.18 Tables 8.3.4-1, 8.3.5-1/2, 10.4.1-5 | **FAIL:** `windowcenter`, `windowwidth`, `columns`, `rows` are not PS3.18 parameters (`window`, `viewport` are) |
| Rendered parameter syntax | PS3.18 8.3.5.1.3, 8.3.5.1.4 | **FAIL:** neither builder emitted `window=c,w,function` or `viewport=vw,vh` |
| URI service query parameter names | PS3.18 Tables 9.1.2-1/2, 9.4.1-1, 9.5.1-1 | 10 / 10 match |
| URI service `contentType` values | PS3.18 9.1.2.2.1 | **PEND:** `image/jphc` is not a Rendered Media Type (P-URI) |
| QIDO required matching attributes | PS3.18 Table 10.6.1-5 | 20 / 20 in `QIDOQueryAttribute`; 15 / 20 parsed by the server |
| QIDO return attributes emitted by the server | PS3.18 Tables 10.6.3-3/4/5 | 15 / 15, 6 / 8, 8 / 8 R+U keys |
| Study-level modality key | PS3.18 Table 10.6.1-5 | **FAIL:** `studiesByModality` sent (0008,0060) |
| UPS-RS methods and resources | PS3.18 Table 11.3-1 | **FAIL:** Request Cancellation as PUT (server and both clients); POST `/workitems/{uid}` routed to Create (it is Update); Deletion Lock as a `Deletion-Lock` header |
| Status codes per transaction | PS3.18 Tables 11.4.3-1 … 11.12.3-1, 10.5.3-1, 8.5-1 | **FAIL:** Update 204 (200), Subscribe 200 (201), not-implemented retrievals 500 (501); STOW all-failed 400 (409) |
| Prescribed Warning header texts | PS3.18 8.3.4.4.1, 11.4.3.2-11.10.3.2 | 0 / 17 emitted |
| Store Instances Response Module tags | PS3.18 Table I.1-1 | 10 / 11 (Other Failures Sequence not carried) |
| Failure Reason codes, client enum | PS3.18 Tables I.2-1 / I.2-2 | **PEND:** 8 of 14 raw values not in the tables (P-STOW) |
| Failure Reason codes, server enum | PS3.18 Table I.2-2 | **FAIL:** 6 of 8 values were PS3.7 statuses the table does not define |
| UPS state, priority, readiness terms | PS3.3 C.30.1, C.30.2 | 4 / 4, 3 / 3, 3 / 3; **PEND:** `STAT` is not a priority term (P-PRIORITY) |
| Change State transitions | PS3.4 Table CC.1.1-2 | **FAIL:** SCHEDULED → CANCELED allowed (the table gives C310H) |
| `UPSTag` tags and keywords | PS3.6 Table 6-1 | 55 / 56; `commentsOnScheduledProcedureStep` (keyword CommentsOnTheScheduledProcedureStep) |
| VR of every JSON attribute literal | PS3.6 Table 6-1 | **FAIL:** 99 / 102; Human Performer's Name LO (PN), Progress Description LO (ST), Progress US (DS) |
| N-CREATE Type 1/2 attributes emitted | PS3.4 Table CC.2.5-3 | 19 / 32 (13 Type 2 attributes not sent, see P-CREATE) |
| Event Type IDs decoded | PS3.4 Table CC.2.4-1 | 3 / 5 (4 and 5 not decoded) |
| Event identification | PS3.4 Table CC.2.4-1 | **PEND:** string event types instead of (0000,1002) (P-EVENT) |
| Character set names | PS3.18 Table D-1 | 3 / 3 |
| Status codes mapped by `DICOMwebError` | PS3.18 Table 8.5-1 | 11 / 11; 422, 429, 502, 504 are generic HTTP |
| Section citations in doc comments | PS3.18 / PS3.19 2026a table of contents | **FAIL:** 91 / 119; "Section 6 status codes", "6.7 Delete Transaction", "10.8 Capabilities" do not exist; 11.4-11.11 numbered one transaction off in both UPS clients |

Tests at the start: `swift test --filter DICOMWebTests` — 616 swift-testing tests pass; the
XCTest bundle passes. Full `swift test` at the start was green (network report, 2026-09-28).

Tests at the end (2026-09-28): `swift test --filter DICOMWebTests` — 630 swift-testing tests (14 new) and the XCTest bundle pass. Full `swift test`: all 9 XCTest bundles and every swift-testing run pass, exit 0.

---

## Progress log

| Date | Item | What was compared | What changed | Tests |
|---|---|---|---|---|
| 2026-09-28 | Baseline | All 53 files read in full and bucketed. PS3.3, 3.4, 3.5, 3.6, 3.18, 3.19 2026a fetched (subtitles checked). `Scripts/diff_web.py` written: 21 checks, 16 failed, 4 pending (table above). Behaviour read against PS3.18 §8-§11, Annex F, Annex I; PS3.19 A.1; PS3.4 Annex CC. | Nothing yet (commit 40e4e89, script only) | 616 swift-testing pass |
| 2026-09-28 | D2, D3 (P1, P2) | PS3.18 F.2.2 (layout, ordering, Group Length), F.2.3 (AT), F.2.5 (null, empty), F.2.6/F.2.7, Table F.2.3-1. `JSONSerialization.sortedKeys` found to order keys numerically on this Foundation ("7FE00010" before "0020000D"), so a writer was added. | `DICOMJSONEncoder`, `DICOMJSONDecoder`, new `DICOMJSONWriter`; 9 new tests (`DICOMJSONModelConformanceTests`); 4 tests that pinned the old layout corrected (commit c78356f) | 626 / 626 |
| 2026-09-28 | D4 (P3) | PS3.19 Tables A.1.5-1, A.1.5-2, schema A.1.6, A.1.1 | `DICOMXMLEncoder`, `DICOMXMLDecoder`; 7 new tests (`DICOMXMLModelConformanceTests`) (commit 767356c) | 626 / 626 |
| 2026-09-28 | P4-P8 | PS3.18 8.7.1, Tables 8.7.3-4/5, 8.7.4-1, 10.4.4-1, 8.3.5.1.2-4, Table 8.3.5-2, 10.6.1-5, 11.3-1, 11.10.1.2; PS3.4 CC.2.1.2 | `DICOMMediaType`, `DICOMwebURLBuilder`, `DICOMwebClient`, `UPSClient`, `QIDOQuery`; 3 new tests; 6 corrected (commit 82d6320) | 629 / 629 |
| 2026-09-28 | P9-P20 | PS3.18 Tables 11.3-1, 11.4.1-1, 11.4.3-1, 11.6.3-1, 11.7.3-1, 11.8.3-1, 11.10.3-1, 10.5.3-1/2, 8.5-1, 8.6.1-1, I.2-2, 8.3.4.4.1, 11.x.3.2 texts, 8.7.5; PS3.4 CC.1.1-2, CC.2.1.3, CC.2.2.3, CC.2.5.3, CC.2.6.3, CC.2.7.3; PS3.6 Table 6-1 | `DICOMwebServer`, `DICOMwebRoutes`, `Workitem`, `UPSStorageProvider`; 1 new test; 8 corrected (commit 9e9c460) | 630 / 630 |
| 2026-09-28 | Markers, citations, B1 | PS3.18/PS3.19 table of contents; PS3.6 Table A-1 names; PS3.18 Table D-1 | 42 files marked; 28 citations corrected; `ConformanceStatement` 2024c → 2026a; `AuthenticationMiddleware` recognises thumbnail/pixeldata (commit e352350) | build |
| 2026-09-28 | Close | `Scripts/diff_web.py` re-run: 35 ok, 0 fail, 4 pending. `check_nema_markers.py`: 54 of 54. CHANGELOG `[Unreleased]`; DICOMCore status table updated. | — | Full `swift test`: all bundles pass |
| 2026-09-28 | Owner approval: P-STOW, P-EVENT, P-PRIORITY, P-URI, P-CREATE | PS3.18 Tables I.2-1/I.2-2; PS3.4 Table CC.2.4-1, CC.2.4.3, CC.2.7.3, Table CC.2.5-3; PS3.3 C.30.2; PS3.18 9.1.2.2.1, Table 8.7.4-1 | `STOWResponse`, `UPSEvent`, `Workitem`, `UPSStorageProvider`, `WebSocketEventDeliveryService`, `UPSWebSocketClient`, `UPSQuery`, `WADOURIClient`, `DICOMwebServer`; DICOMStudio and dicom-wado call sites; 7 tests corrected (commit df9d92b). Script: 35 ok, 0 pending. | 630 / 630; full `swift test` below |
| 2026-10-06 | D254, D255, D265; A4 | PS3.4 2026a Table CC.2.4-1, Table CC.1.1-2; PS3.18 2026a 11.7.1.4, 9.1.2.2.1, 9.4.1.2.2, 9.5.1.2.1, 8.3.4.4, 11.7, Table 8.7.4-1 | `c9bad73e` UPSEvent marker (P-EVENT no longer named as pending); `f4b3bddd` UPSState change-state API + DICOMwebOptionRefusal; `87bbcbf8` DICOMwebOptionRules (2 files added, marked); `986c517b` diff_cli_web.py reads media types and Change-State targets from DICOMWeb; D25 gains its sha (A8) | diff_kit 0 wrong, diff_network 0, diff_web 0, diff_printkit 0, diff_renderkit 17 ok / 0 failing / 0 deferred, diff_cli 0 FAIL (42 tools), diff_cli_web 0 FAIL, every check_nema_markers run exit 0 (all with --nema 2026a); `check_nema_markers.py`: 57 / 57 |

Full `swift test` before the approvals (2026-09-28, run after commit e352350): all 9 XCTest bundles pass (DICOMCore, DICOMKit 1,159, DICOMNetwork, DICOMPrintKit 323, DICOMRenderKit 92, DICOMRoundTrip 524, DICOMStudio, DICOMViewer, DICOMWeb) and every swift-testing run passes (DICOMWebTests 630 tests in 61 suites, 14 new), exit 0. No failures, no pre-existing failures to log.

Full `swift test` after the approvals (2026-09-28, run after commit df9d92b): all 9 XCTest bundles pass (DICOMCore, DICOMKit, DICOMNetwork, DICOMPrintKit, DICOMRenderKit, DICOMRoundTrip, DICOMStudio, DICOMViewer, DICOMWeb) and every swift-testing run passes (5,165 + 1,504 + 674 + 630 + 474 + 226 + 84 + 53 + 30 + 20 tests), exit 0. No failures.

---

## Priority action list

| # | What | Standard | Impact | Status |
|---|---|---|---|---|
| P1 | D2: InlineBinary / BulkDataURI inside the `Value` array | PS3.18 F.2.2, F.2.6, F.2.7 | **High:** every other DICOMweb implementation rejects or misreads the JSON | ✅ c78356f (siblings of `vr`; old layout still accepted on input) |
| P2 | D3: AT encoded through `uint32Values` (nil for AT) → string fallback | PS3.18 F.2.3 | Medium | ✅ c78356f |
| P3 | D4: XML encoder omitted OV; no `<Value>` for any numeric VR (Rows, Columns, …); decoder stored numeric text as the Value Field; no `xml:space`, `privateCreator`, `uuid` | PS3.19 Tables A.1.5-1/2, A.1.6 | **High:** every numeric attribute lost in XML | ✅ 767356c |
| P4 | `type=application/dicom` unquoted in Content-Type / Accept | PS3.18 8.7.1; RFC 2045 §5.1 | Medium: strict servers reject the STOW-RS request | ✅ 82d6320 |
| P5 | Frames requested with `type="application/dicom"` | PS3.18 Table 10.4.4-1, Table 8.7.3-5 | Medium: 406 from conformant servers | ✅ 82d6320 (`bulkDataMediaType(forTransferSyntax:)`) |
| P6 | Rendered URLs sent `windowcenter`, `windowwidth`, `columns`, `rows`; thumbnails sent `quality`; quality clamped to 0 | PS3.18 8.3.5.1.2-4, Tables 8.3.5-1/2 | Medium: parameters ignored or 400 | ✅ 82d6320 (old constants deprecated) |
| P7 | `studiesByModality` sent Modality (0008,0060) to `/studies` | PS3.18 Table 10.6.1-5 | Medium | ✅ 82d6320 |
| P8 | Both UPS clients: Request Cancellation as PUT; `Deletion-Lock` header; no Transaction UID generated for IN PROGRESS | PS3.18 Table 11.3-1, 11.10.1.2, 11.7.1.4; PS3.4 CC.2.1.2 | Medium | ✅ 82d6320 |
| P9 | Router: POST `/workitems/{uid}` was Create (it is Update), Create with a UID is `?workitem=`; cancel PUT; well-known subscription UIDs went to the per-workitem handler and 404'd | PS3.18 Tables 11.3-1, 11.4.1-1, 11.10.1-1 | Medium | ✅ 9e9c460 |
| P10 | Create accepted any state and returned a payload | PS3.18 11.4.2, 11.4.3.3; PS3.4 CC.2.5.3 | Medium | ✅ 9e9c460 |
| P11 | Update: 204, no Transaction UID check, 409 for final state | PS3.18 11.6.2, Table 11.6.3-1; PS3.4 CC.2.6.3 | Medium | ✅ 9e9c460 |
| P12 | Change State: Transaction UID optional, generated by the server and returned in a payload; 409 for missing / wrong UID; no "already in state" warning | PS3.18 11.7.1.4, 11.7.3.2, Table 11.7.3-1; PS3.4 Table CC.1.1-2 | Medium | ✅ 9e9c460 |
| P13 | `UPSState.validTransitions` allowed SCHEDULED → CANCELED; provider cancelled a SCHEDULED UPS directly | PS3.4 Table CC.1.1-2 (C310H), CC.2.2.3 | Medium | ✅ 9e9c460 (through IN PROGRESS) |
| P14 | Transaction UIDs generated as `2.25.<32 hex digits>` (letters are not UID characters) | PS3.5 9.1, B.2 | Medium | ✅ 9e9c460 (`UIDGenerator`) |
| P15 | Retrieved and searched Workitems carried the Transaction UID | PS3.18 11.5.2; PS3.4 CC.2.7.3 | Medium: the access lock leaked | ✅ 9e9c460 |
| P16 | Subscribe 200; no Deletion Lock / filtered-worklist warnings; not-implemented retrievals 500 | PS3.18 Tables 11.10.3-1, 8.5-1; 11.10.3.2 | Low-Medium | ✅ 9e9c460 |
| P17 | Prescribed Warning texts absent (17); no remaining-results warning on searches | PS3.18 8.3.4.4.1, 11.4.3.2-11.10.3.2 | Low-Medium | ✅ 9e9c460 (13 of 17 emitted; the 4 for Create/Update modifications and "performer" cases have no trigger in this server) |
| P18 | Server STOW Failure Reason codes were PS3.7 statuses; all-failed answered 400; no Location; no Content-Location on multipart parts; no 406; no single-part `application/dicom` | PS3.18 Table I.2-2, 10.5.3-1/2, 8.6.1-1, 8.7.5, 10.4.4-1 | Medium | ✅ 9e9c460 |
| P19 | Human Performer's Name written LO (PN); Progress Description LO (ST); Progress US (DS); `UPSTag.commentsOnScheduledProcedureStep` keyword | PS3.6 Table 6-1 | Low-Medium | ✅ 9e9c460 (old name deprecated) |
| P20 | 28 wrong PS3.18 section citations; `ConformanceStatement` said 2024c; DX SOP Class name with an en dash; thumbnail/pixeldata unknown to the auth path parser | PS3.18/19 ToC; PS3.6 A-1; Table 10.1-1 | Low | ✅ e352350 |
| P-STOW | `STOWResponse.FailureReasonCode`: 0112, 0113, 0114, 0115, 0120 are not in Tables I.2-1/I.2-2; `transferSyntaxNotSupported = 0x0124` should be C122; `dataSetDoesNotMatchSOPClass = 0x0131` should be A900 (error) / B007 (warning); B007 and C122 missing | PS3.18 Tables I.2-1, I.2-2 | Medium: `knownFailureReason` was nil for a conformant server's C122/A900 | ✅ Approved and done, df9d92b: `referencedTransferSyntaxNotSupported = 0xC122`, `dataSetDoesNotMatchSOPClassError = 0xA900`, `dataSetDoesNotMatchSOPClassWarning = 0xB007` added; the seven PS3.7-only / mis-valued cases deprecated; `knownFailureReason` classifies A7xx, A9xx, Cxxx; 0111 kept as an additional code (I.2.2) |
| P-EVENT | `UPSEventType` raw values were invented strings; event JSON used bare keys, carried the Transaction UID, put progress at the top level, omitted Input Readiness State and had no Event Type ID (0000,1002); `Completed` / `Canceled` are State Reports; Event Type IDs 4 and 5 were not decoded | PS3.4 Table CC.2.4-1, CC.2.4.3, CC.2.7.3; PS3.18 8.10.5 | Medium: DICOMKit-to-DICOMKit only | ✅ Approved and done, df9d92b: `UPSEventType.eventTypeID` / `init(eventTypeID:)` (1-5, `scpStatusChange` added); every `toDICOMJSON` is the Table CC.2.4-1 Event Report with (0000,1002); State Reports carry Input Readiness State; progress inside (0074,1002); contact fields as (0074,100A)/(0074,100C); no Transaction UID; `completed`/`canceled` serialise as State Reports; the provider dispatches one State Report per change; the WebSocket client decodes IDs 4 and 5 |
| P-PRIORITY | `UPSPriority.stat = "STAT"` | PS3.3 C.30.2 (HIGH, MEDIUM, LOW; HIGH is "equivalent to a STAT request") | Low-Medium: a wrong value on the wire when selected | ✅ Approved and done, df9d92b: `.stat` deprecated, `dicomValue` writes HIGH everywhere the priority goes on the wire, `allCases` is the three defined terms; dicom-wado and DICOMStudio map "STAT" to `.high` |
| P-URI | `WADOURIClient.ContentType.htj2kContainer = "image/jphc"` | PS3.18 9.1.2.2.1 (application/dicom or a Rendered Media Type of Table 8.7.4-1; image/jph is one, image/jphc is bulk data) | Low | ✅ Approved and done, df9d92b: deprecated; `fromRequestString` maps `jphc` to `.htj2k` |
| P-CREATE | `Workitem.toDICOMJSONForCreate` omitted 12 Type 2 attributes of the N-CREATE column (Scheduled Processing Parameters Sequence, Issuer of Patient ID, Issuer of Patient ID Qualifiers Sequence, Other Patient IDs Sequence, Admission ID, Issuer of Admission ID Sequence, Admitting Diagnoses Description/Code Sequence, Procedure Step Progress Information Sequence, Unified Procedure Step Performed Procedure Sequence, Transaction UID "shall be empty"); Patient ID, Birth Date and Sex were dropped when nil | PS3.4 Table CC.2.5-3 | Medium: a strict origin server answers 400 | ✅ Done, df9d92b: every Type 2 attribute of the N-CREATE column is sent (empty when the model has no value), the Transaction UID empty as the table requires; the 1C Replaced Procedure Step Sequence is not modelled |

### Decisions taken without asking (all within the method's "fix behaviour that contradicts the standard")

- **Empty attributes are kept by default (D2):** `includeEmptyValues` of both encoders now defaults
  to `true`, and the JSON encoder writes `{"vr": …}` with no `Value` (F.2.5 "shall be preserved");
  `false` drops the attribute. Two tests that expected `"Value": []` were corrected. The
  parameter and its type are unchanged.
- **Own JSON writer:** `JSONSerialization.sortedKeys` orders "7FE00010" before "0020000D" on
  macOS 27 (numeric-aware comparison), which is not the lexicographic order F.2.2 requires.
  `DICOMJSONWriter` (internal) sorts by Unicode scalar and is used for every DICOM JSON body,
  client and server. Numbers use Swift's shortest round-trip form.
- **Legacy JSON accepted on input:** the decoder still reads `{"Value": [{"InlineBinary": …}]}`,
  so JSON written by earlier DICOMKit releases keeps decoding.
- **Private elements in XML:** the decoder assigns a block to a `privateCreator` element by
  looking for that creator in the same Data Set and allocating the first free block (0x10-0xFF)
  otherwise, synthesising the Private Creator element (PS3.5 7.8.1).
- **Lenient Accept:** the server treats a missing Accept header as `*/*` (8.7.5 would answer
  406); with a header present it answers 406 when nothing supported matches. PUT is still
  accepted as an alias of POST for Update and Request Cancellation, and `X-Total-Count` is kept
  as a non-standard extension. `application/dicom+xml` metadata is answered 406 (not implemented).
- **Deprecated, not removed:** the seven `FailureReasonCode` cases, `UPSPriority.stat` and
  `WADOURIClient.ContentType.htj2kContainer` stay as deprecated members so existing callers
  compile with a warning; `UPSPriority.allCases` lists only the three defined terms.
- **Server-generated Transaction UID:** `InMemoryUPSStorageProvider.changeWorkitemState` still
  generates a Transaction UID when a direct caller passes none; the HTTP handler never lets that
  happen (400 "The Transaction UID is missing.").
- **STOW Duplicate SOP Instance:** the server keeps 0111H (PS3.7 C.5.9) for a duplicate, an
  additional code as I.2.2 permits; the script lists it as an extra, not a failure.

### Explicitly out of scope — do not chase

- Frames, rendered, thumbnail and bulk data retrieval on the server (501); `includefield`,
  `fuzzymatching`, `emptyvaluematching`, `multiplevaluematching` on the server (parsed, not honoured);
  the 8.9 Retrieve Capabilities Transaction (OPTIONS / with a WADL Capabilities Description);
  subscription and deletion-lock tracking in the server (the SubscriptionManager exists but is
  not wired to it); PS3.4 Table CC.2.3-2 subscription state machine; UPS State Report on create
  and on subscribe (CC.2.4.3).
- DELETE on studies, series and instances: not a PS3.18 transaction; documented as an extension.
- The `/bulkdata/{attributePath}`, `/state/{requestingAE}`, `/cancelrequest/{requestingAE}` and
  `/ws/subscribers/{aeTitle}` paths: dcm4chee conventions kept for interoperability; PS3.18 uses
  `?requester=` and leaves the WebSocket URL to the origin server (8.10.4).
- OAuth2 scopes (`system/ImagingStudy.read`, SMART v1 syntax), JWT roles: not DICOM.
- `DICOMwebError` cases for 410 Gone: adding a case is API; 410 maps to `httpError`.

---

## Deferred findings

**Carried in from the DICOMCore report:**

| ID | Location | Problem | Standard (2026a) | Status |
|---|---|---|---|---|
| D2 | `DICOMJSONEncoder.encodeValue`, `DICOMJSONDecoder.decodeValue` | InlineBinary and BulkDataURI inside the `Value` array | PS3.18 F.2.2 | ✅ Done 2026-09-28, commit c78356f (P1): siblings of `vr`; `DICOMJSONEncoderTests.testEncodeInlineBinary`, `DICOMJSON64BitVRTests.testEncodeOVInlineBinary` and two `JSONRoundTripTests` corrected; legacy layout accepted on input |
| D3 | `DICOMJSONEncoder.encodeNumericValues` case `.AT` | Read `uint32Values` (nil for AT) and fell to the string fallback | PS3.18 F.2.3 | ✅ Done 2026-09-28, commit c78356f (P2): `attributeTagValues` → `GGGGEEEE` |
| D4 | `DICOMXMLEncoder.isBinaryVR`; SV/UV handling | OV omitted; numeric VRs unchecked | PS3.19 A.1.5-2; PS3.5 Table 6.2-1 | ✅ Done 2026-09-28, commit 767356c (P3): OV added; every numeric VR was in fact dropped and is now written and read back |

**New findings for other modules** (recorded, not fixed here):

| ID | Module | Location | Problem | Standard (2026a) | Severity | Status |
|---|---|---|---|---|---|---|
| D25 | DICOMCore | [DataElement.swift:178](Sources/DICOMCore/DataElement.swift#L178) `stringValues` | Splits on backslash with `split(separator:)`, which omits empty subsequences, so `"MPG\\XR3"` (three values, the second empty) comes back as two values and `"A\B\"` as two: value positions shift for every caller that indexes into a multi-valued attribute. DICOMWeb splits with `components(separatedBy:)` locally (JSON F.2.5, XML Table A.1.5-2) instead. | PS3.5 6.4 (Value Multiplicity; an empty value is a value), Table A.1.5-2 example | Medium: wrong value indices | ✅ Done 2026-09-28: `components(separatedBy:)` keeps empty values in position, an empty or padding-only Value Field returns `[]`; test `DataElementTests.testEmptyValuesPreserved`; commit `511ac8ab` (sha added 2026-10-06, audit A8) |

---

## Bucket B1 — Cites another edition (1 file)

| File | Before | After |
|---|---|---|
| [ConformanceStatement.swift](Sources/DICOMWeb/ConformanceStatement.swift) | `dicomVersion` defaulted to "2024c" in the initialiser and the `dicomKit` preset | ✅ 2026a; character set names diffed against PS3.18 Table D-1 (3 / 3), UPS states against PS3.3 C.30.1. Marked. |

## Bucket B2 — No citation, data or behaviour differs from 2026a (27 files)

| File | Before | After |
|---|---|---|
| [DICOMJSONEncoder.swift](Sources/DICOMWeb/DICOMJSONEncoder.swift) | D2, D3; Group Length written; no null values; empty attributes dropped; PN via `DICOMPersonName` | ✅ P1, P2; Table F.2.3-1 34 / 34. Marked. |
| [DICOMJSONDecoder.swift](Sources/DICOMWeb/DICOMJSONDecoder.swift) | D2 on input; null rejected | ✅ P1; F.2.5 nulls; 34 / 34. Marked. |
| [DICOMXMLEncoder.swift](Sources/DICOMWeb/DICOMXMLEncoder.swift) | D4; numeric VRs never written; empty values dropped; no `xml:space`, `privateCreator` | ✅ P3. Marked. |
| [DICOMXMLDecoder.swift](Sources/DICOMWeb/DICOMXMLDecoder.swift) | Numeric text stored as the Value Field; `privateCreator`, `uuid` ignored | ✅ P3. Marked. |
| [DICOMMediaType.swift](Sources/DICOMWeb/DICOMMediaType.swift) | `type=application/dicom` unquoted; 4 names missing; no TS → media type table; "Section 6" citations | ✅ P4, P5; 19 names, Table 8.7.3-5 36 / 36. Marked. |
| [DICOMwebURLBuilder.swift](Sources/DICOMWeb/DICOMwebURLBuilder.swift) | `windowcenter`/`columns`/`rows`; quality 0-100; "Section 10 URI Templates", "11.11 event channel" | ✅ P6, P20; 28 templates match; deprecated constants. Marked. |
| [DICOMwebClient.swift](Sources/DICOMWeb/DICOMwebClient.swift) | Frames Accept; render params; thumbnail quality; UPS PUT cancel, `Deletion-Lock`, no Transaction UID; 11.x citations off by one | ✅ P5, P6, P8, P20. Marked. |
| [UPS/UPSClient.swift](Sources/DICOMWeb/UPS/UPSClient.swift) | Same UPS findings as the client above | ✅ P8, P20. Marked. |
| [QIDOQuery.swift](Sources/DICOMWeb/QIDOQuery.swift) | `studiesByModality` at the wrong level | ✅ P7; 20 / 20 tags. Marked. |
| [Server/DICOMwebRoutes.swift](Sources/DICOMWeb/Server/DICOMwebRoutes.swift) | Create/Update/cancel methods; global UIDs; no 501 factory; no bulkdata route | ✅ P9, P16. Marked. |
| [Server/DICOMwebServer.swift](Sources/DICOMWeb/Server/DICOMwebServer.swift) | P10-P12, P15-P18 | ✅ All; 12 handlers' status codes match their tables. Marked. |
| [UPS/Workitem.swift](Sources/DICOMWeb/UPS/Workitem.swift) | P13, P19; STAT; 13 Type 2 attributes missing at create | ✅ P13, P19, P-PRIORITY, P-CREATE; 66 / 66 tags. Marked. |
| [UPS/UPSStorageProvider.swift](Sources/DICOMWeb/UPS/UPSStorageProvider.swift) | Invalid Transaction UIDs; SCHEDULED → CANCELED directly | ✅ P13, P14. Marked. |
| [STOWResponse.swift](Sources/DICOMWeb/STOWResponse.swift) | Failure codes from "PS3.4 Annex B"; C122, A900, B007 missing | ✅ P-STOW; Table I.1-1 tags 7 / 7. Marked. |
| [UPS/UPSEvent.swift](Sources/DICOMWeb/UPS/UPSEvent.swift) | Invented event model; CC.2.6.x citations (N-SET) | ✅ P-EVENT; citations → Table CC.2.4-1. Marked. |
| [UPS/UPSWebSocketClient.swift](Sources/DICOMWeb/UPS/UPSWebSocketClient.swift) | "§11.11" for the WebSocket; IDs 4, 5 not decoded | ✅ Citations → 8.10.4 / Table CC.2.4-1; IDs 1-5 decoded. Marked. |
| [UPS/WebSocketEventDeliveryService.swift](Sources/DICOMWeb/UPS/WebSocketEventDeliveryService.swift) | "§11.8-11.11" citations; no (0000,1002); Transaction UID sent | ✅ Citations; P-EVENT payload. Marked. |
| [WADOURIClient.swift](Sources/DICOMWeb/WADOURIClient.swift) | "PS3.18 §8" for the URI Service (Chapter 9); image/jphc | ✅ P20, P-URI; parameters 10 / 10. Marked. |
| [Server/AuthenticationMiddleware.swift](Sources/DICOMWeb/Server/AuthenticationMiddleware.swift) | thumbnail, pixeldata, suspend unknown segments | ✅ P20. Marked. |
| [DICOMwebCapabilities.swift](Sources/DICOMWeb/DICOMwebCapabilities.swift) | "Section 10.8 Capabilities"; 4 non-A-1 names | ✅ P20; 11 UIDs registered. Marked. |
| [DICOMwebError.swift](Sources/DICOMWeb/DICOMwebError.swift) | "Section 6 status codes" | ✅ P20 (8.5). Marked. |
| [Server/DICOMwebStorageProvider.swift](Sources/DICOMWeb/Server/DICOMwebStorageProvider.swift) | "Section 6.7 Delete Transaction" (none exists) | ✅ P20. Marked. |
| [Server/DICOMwebServerConfiguration.swift](Sources/DICOMWeb/Server/DICOMwebServerConfiguration.swift) | "Section 6 Security" | ✅ P20 (PS3.15 B.12). Marked. |
| [WADORetrieveConsoleFormatter.swift](Sources/DICOMWeb/WADORetrieveConsoleFormatter.swift) | "WADO-URI (PS3.18 §8)" label | ✅ P20. Marked. |
| [MultipartMIME.swift](Sources/DICOMWeb/MultipartMIME.swift) | "Section 8 Multipart MIME" | ✅ P20 (8.6.1.2, 8.7.1); syntax read against 8.6.1.2.1. Marked. |
| [DICOMWeb.swift](Sources/DICOMWeb/DICOMWeb.swift) | Same citation | ✅ P20. Marked. |
| [ConformanceStatementGenerator.swift](Sources/DICOMWeb/ConformanceStatementGenerator.swift) | DX name with an en dash | ✅ P20; 20 SOP Class UIDs and names match A-1. Marked. |

## Bucket C1 — Plumbing (17 files)

| File | Confirmed | Result |
|---|---|---|
| [Caching/CacheConfiguration.swift](Sources/DICOMWeb/Caching/CacheConfiguration.swift) | TTL and size limits | ✅ Marked |
| [Caching/InMemoryCache.swift](Sources/DICOMWeb/Caching/InMemoryCache.swift) | Response cache; RFC 7231 header names | ✅ Marked |
| [Logging/DICOMwebMetrics.swift](Sources/DICOMWeb/Logging/DICOMwebMetrics.swift) | Counters | ✅ Marked |
| [Logging/DICOMwebRequestLogger.swift](Sources/DICOMWeb/Logging/DICOMwebRequestLogger.swift) | Logging | ✅ Marked |
| [OAuth2/OAuth2Configuration.swift](Sources/DICOMWeb/OAuth2/OAuth2Configuration.swift) | RFC 6749 / SMART scopes, not DICOM | ✅ Marked |
| [OAuth2/OAuth2Token.swift](Sources/DICOMWeb/OAuth2/OAuth2Token.swift) | RFC 6749 §5.1 / §5.2 | ✅ Marked |
| [OAuth2/OAuth2TokenProvider.swift](Sources/DICOMWeb/OAuth2/OAuth2TokenProvider.swift) | Token fetch | ✅ Marked |
| [HTTPClient.swift](Sources/DICOMWeb/HTTPClient.swift) | URLSession wrapper | ✅ Marked |
| [HTTPConnectionPool.swift](Sources/DICOMWeb/HTTPConnectionPool.swift) | Pooling | ✅ Marked |
| [HTTPPrefetchManager.swift](Sources/DICOMWeb/HTTPPrefetchManager.swift) | Prefetch | ✅ Marked |
| [HTTPRequestPipeline.swift](Sources/DICOMWeb/HTTPRequestPipeline.swift) | Pipelining | ✅ Marked |
| [QIDOResultFormatter.swift](Sources/DICOMWeb/QIDOResultFormatter.swift) | Console columns | ✅ Marked |
| [STOWResultFormatter.swift](Sources/DICOMWeb/STOWResultFormatter.swift) | Console text | ✅ Marked |
| [UPSResultFormatter.swift](Sources/DICOMWeb/UPSResultFormatter.swift) | Console text; Final State note matches CC.2.1.3 | ✅ Marked |
| [UPS/EventDeliveryService.swift](Sources/DICOMWeb/UPS/EventDeliveryService.swift) | In-process queue | ✅ Marked |
| [UPS/SubscriptionManager.swift](Sources/DICOMWeb/UPS/SubscriptionManager.swift) | In-memory registry; not wired to the server; CC.2.3-2 not modelled (said in the marker) | ✅ Marked |
| [Server/CompressionMiddleware.swift](Sources/DICOMWeb/Server/CompressionMiddleware.swift) | Content-Encoding of the whole response (Table 8.4.2-1 permits) | ✅ Marked |

## Bucket C2 — Standard-derived, edition-stable (9 files)

| File | Standard data | Result |
|---|---|---|
| [DICOMJSONWriter.swift](Sources/DICOMWeb/DICOMJSONWriter.swift) (new) | PS3.18 F.2.2 ordering; RFC 8259 §7 escaping | ✅ Marked |
| [DICOMwebConfiguration.swift](Sources/DICOMWeb/DICOMwebConfiguration.swift) | Default Accept = the Default Media Type of Tables 10.4.4-1, 10.6.4-1, 11.1.3-1 | ✅ Marked |
| [DataExchangeWorkflow.swift](Sources/DICOMWeb/DataExchangeWorkflow.swift) | 1.2.840.10008.1.2.1 (A-1; 8.7.3.4 default) | ✅ Marked |
| [QIDOResults.swift](Sources/DICOMWeb/QIDOResults.swift) | Accessor tags ⊂ Tables 10.6.3-3/4/5 | ✅ Marked |
| [Server/ServerCacheMiddleware.swift](Sources/DICOMWeb/Server/ServerCacheMiddleware.swift) | Media type names of 8.7.3.5 | ✅ Marked |
| [Server/InMemoryStorageProvider.swift](Sources/DICOMWeb/Server/InMemoryStorageProvider.swift) | PS3.4 C.2.2.2.4/5 matching (case-insensitive wildcards, a leniency) | ✅ Marked |
| [UPS/UPSQuery.swift](Sources/DICOMWeb/UPS/UPSQuery.swift) | 23 tags (PS3.6 6-1); Table 8.3.4-1 parameters | ✅ Marked |
| [UPS/UPSResults.swift](Sources/DICOMWeb/UPS/UPSResults.swift) | 19 tags (PS3.6 6-1) | ✅ Marked |
| [UPS/WorkitemBuilder.swift](Sources/DICOMWeb/UPS/WorkitemBuilder.swift) | Defaults are C.30.2 terms | ✅ Marked |

---

## Verification notes

- Reproduce: `python3 Scripts/nema_docbook.py fetch 2026a N --out DIR` for N = 3, 4, 6, 18, 19
  (subtitles must read "DICOM PS3.N 2026a - …"), then `python3 Scripts/diff_web.py --nema DIR`.
  Expected: 35 ok, 0 FAIL, 0 PEND. PS3.5 was read for
  6.2 (VRs), 7.8.1 (private blocks) and 9.1 (UID characters) only.
- Behaviour clauses were compared by reading the extracted text (PS3.18 8.3.4-8.3.5, 8.6.1,
  8.7.5-8.7.8, 10.4.4, 10.5.2-3, 11.4-11.12; PS3.19 A.1.1; PS3.4 CC.1.1, CC.2.1-CC.2.8); they
  are cited in the markers and pinned by `DICOMJSONModelConformanceTests`,
  `DICOMXMLModelConformanceTests`, `DICOMwebMediaTypeConformanceTests` and the server tests.
- `JSONSerialization.sortedKeys` ordering was measured on macOS 27.0 / Swift 6.4 (the probe is
  in the commit message of c78356f); the writer does not depend on it.
- Not checked, by decision: the WADL Capabilities Description (Annex H, not implemented); the
  PS3.18 Chapter 12-15 services (not implemented); Annex J / K modules; the CC.2.3-2 subscription
  state table (not implemented); the STOW-RS `Other Failures Sequence` (0008,119A), not carried.
- Leniencies kept on purpose and documented in code: missing Accept treated as `*/*`; PUT alias
  for Update / Request Cancellation; legacy JSON binary layout on input; case-insensitive
  wildcard matching in the in-memory storage provider; `X-Total-Count`.
