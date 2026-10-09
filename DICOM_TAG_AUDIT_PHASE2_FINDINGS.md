# DICOM Tag Audit — Phase 2: Key-Set Conformance per Service (for review)

Phase 1 proved *number == name*. Phase 2 asks the other question: **does each service send and
read the set of keys the standard's table says it should?** Each service below has the standard's
table (fetched 2026-09-18 from dicom.nema.org, current edition) on one side and the code on the
other.

Legend: ✅ present and correct · ❌ missing/wrong (needs a fix) · ➖ optional, deliberately not
supported (no action) · ⚠️ decision needed.

**Status 2026-09-18: implemented — see §7 Resolution at the end. P17 was withdrawn (not a bug),
P18 became an optional field, P13 and P15 went in as agreed.**

---

## 1. Modality Worklist C-FIND SCU — PS3.4 Table K.6-1

Code: `DICOMNetwork/ModalityWorklistService.swift` (`WorklistQueryKeys`, `WorklistItem`),
`dicom-mwl`, Studio Workshop MWL.

### 1a. Matching keys the SCU can send

| Key (K.6-1 type) | Tag | Nesting | Code | Semantics |
|---|---|---|---|---|
| Patient's Name (R) | (0010,0010) | root | ✅ `patientName` | wildcard passed verbatim ✅ |
| Patient ID (R) | (0010,0020) | root | ✅ | |
| Accession Number (O) | (0008,0050) | root | ✅ | |
| SPS Start Date (R) | (0040,0002) | SPS | ✅ `scheduledDate` | single/range validated ✅ |
| SPS Start Time (R) | (0040,0003) | SPS | ✅ `scheduledTime` | single/range ✅ |
| Scheduled Station AE Title (R) | (0040,0001) | SPS | ✅ | single value ✅ |
| Modality (R) | (0008,0060) | SPS | ✅ | single value ✅ |
| Scheduled Performing Physician's Name (R) | (0040,0006) | SPS | ✅ (added 09-17) | wildcard ✅ |
| SPS Status (O) | (0040,0020) | SPS | ✅ | |
| SPS Sequence sent as exactly one item (K.6.1.2.2) | (0040,0100) | — | ✅ `encodeSPSSequence` | |
| Specific Character Set (1C) | (0008,0005) | root | ✅ sent as ISO_IR 100 | see 1c |
| Scheduled Station Name (O) | (0040,0010) | SPS | ➖ no setter | |
| Requested Procedure ID / Study Instance UID / Referring Physician / Admission ID … (O) | various | root | ➖ no setter | |
| **Generic escape hatch** `matching(tag, value)` / `spsMatching(tag, value)` like `QueryKeys` has | — | — | ❌ **#P1** absent — every unsupported O key needs a code change | |

### 1b. Return keys requested by `default()` and readable from `WorklistItem`

| Return key (K.6-1 type) | Tag | Nesting | Requested | Readable |
|---|---|---|---|---|
| Patient's Name (1) / ID (1) | (0010,0010/0020) | root | ✅ | ✅ |
| Patient's Birth Date (2) / Sex (2) | (0010,0030/0040) | root | ✅ | ✅ |
| Study Instance UID (1) | (0020,000D) | root | ✅ | ✅ |
| Accession Number (2) | (0008,0050) | root | ✅ | ✅ |
| Referring Physician's Name (2) | (0008,0090) | root | ✅ | ✅ |
| Requested Procedure ID (1) | (0040,1001) | root | ✅ | ✅ |
| Requested Procedure Description (1C) | (0032,1060) | root | ✅ | ✅ |
| SPS: AE Title, Start Date, Start Time, Modality, SPS ID, SPS Description, Status, Performing Physician, Station Name | | SPS | ✅ | ✅ |
| **Requested Procedure Code Sequence (1C)** | (0032,1064) | root | ❌ **#P2** | ❌ | 
| **Scheduled Protocol Code Sequence (1C)** | (0040,0008) | SPS | ❌ **#P2** | ❌ |
| **Referenced Study Sequence (2)** | (0008,1110) | root | ❌ **#P3** | ❌ — needed to fill MPPS Referenced Study Sequence (see 2) |
| Requested Procedure Priority (2) | (0040,1003) | root | ❌ **#P4** | ❌ |
| Patient's Weight (2) / Size (3) | (0010,1030/1020) | root | ❌ **#P4** | ❌ — CT dose / PET SUV inputs |
| Pregnancy Status (2), Medical Alerts (2), Allergies (2), Special Needs (2), Patient State (2) | (0010,21C0)(0010,2000)(0010,2110)(0038,0050)(0038,0500) | root | ❌ **#P4** | ❌ — safety attributes a modality is expected to show |
| Admission ID (2), Current Patient Location (2), Requesting Physician (2), Patient Transport Arrangements (2) | (0038,0010)(0038,0300)(0032,1032)(0040,1004) | root | ❌ **#P4** | ❌ |
| SPS Location (2), Requested Contrast Agent (2C), Pre-Medication (2C) | (0040,0011)(0032,1070)(0040,0012) | SPS | ❌ **#P4** | ❌ |
| Referenced Patient Sequence (2), Issuer of Patient ID (3), Other Patient IDs Sequence (3), Study Date/Time (3), Scheduled Specimen Sequence (3) | | | ➖ | ➖ |

### 1c. Structural

| Check | Result |
|---|---|
| **Response strings decoded as ASCII** — `WorklistItem.stringValue` uses `String(data:encoding:.ascii)`; any Latin-1/UTF-8/multi-byte value (accented names, Japanese) returns **nil**, and the request even advertises ISO_IR 100 | ❌ **#P5** — decode using the response's (0008,0005), fall back to ISO_IR 100 |
| Flat `[Tag: Data]` result — code sequences (#P2) cannot be stored: Code Value (0008,0100) of Requested Procedure Code Seq and of Scheduled Protocol Code Seq would collide | ⚠️ **#P6** — `WorklistItem` needs nested storage for the two code sequences (and Referenced Study Sequence) before #P2/#P3 can land |
| `dicom-mwl` / Workshop options cover every supported matching key | ✅ (`--station-name` etc. follow #P1) |

---

## 2. MPPS N-CREATE / N-SET SCU — PS3.4 Table F.7.2-1

Code: `DICOMNetwork/MPPSService.swift`, `dicom-mpps`, Studio Workshop.

### 2a. N-CREATE

| Attribute (type) | Tag | Nesting | Code |
|---|---|---|---|
| Specific Character Set (1C) | (0008,0005) | root | ✅ |
| Modality (1) | (0008,0060) | root | ✅ |
| Patient's Name (2) / Patient ID (2) | (0010,0010/0020) | root | ✅ |
| **Patient's Birth Date (2) / Patient's Sex (2)** | (0010,0030/0040) | root | ❌ **#P7** absent |
| **Referenced Patient Sequence (2)** | (0008,1120) | root | ❌ **#P7** |
| Performed Station AE Title (1) / Name (2) | (0040,0241/0242) | root | ✅ |
| **Performed Location (2)** | (0040,0243) | root | ❌ **#P7** |
| PPS Start Date/Time (1) | (0040,0244/0245) | root | ✅ |
| PPS End Date/Time (2) | (0040,0250/0251) | root | ✅ |
| PPS Status (1) / ID (1) / Description (2) | (0040,0252/0253/0254) | root | ✅ |
| **Performed Procedure Type Description (2)** | (0040,0255) | root | ❌ **#P7** |
| **Procedure Code Sequence (2)** | (0008,1032) | root | ❌ **#P7** |
| **Study ID (2)** | (0020,0010) | root | ❌ **#P7** |
| **Performed Protocol Code Sequence (2)** | (0040,0260) | root | ❌ **#P7** |
| Scheduled Step Attributes Sequence (1) | (0040,0270) | root | ✅ |
| ↳ Study Instance UID (1), Accession (2), Requested Procedure ID (2), SPS ID (2), SPS Description (2) | | | ✅ |
| ↳ Referenced Study Sequence (2) | (0008,1110) | | ✅ sent **empty** — should carry the MWL item's value (#P3) ⚠️ |
| ↳ **Requested Procedure Description (2)** | (0032,1060) | | ❌ **#P8** |
| ↳ **Scheduled Protocol Code Sequence (2)** | (0040,0008) | | ❌ **#P8** |
| Performed Series Sequence (2) | (0040,0340) | root | ✅ |
| ↳ Series Instance UID (1), Series Description (2), Performing Physician (2), Referenced Image Sequence (2) | | | ✅ |
| ↳ **Protocol Name (Type 1)** | (0018,1030) | | ❌ **#P9** absent — Type 1 inside every series item; dcm4chee/DCMTK MPPS SCPs reject COMPLETED without it |
| ↳ **Operators' Name (2), Retrieve AE Title (2), Referenced Non-Image Composite SOP Instance Sequence (2)** | (0008,1070)(0008,0054)(0040,0220) | | ❌ **#P9** |
| ↳ Referenced Image Sequence › Referenced SOP Class UID | (0008,1150) | | ❌ **#P10** **hard-coded to Secondary Capture** `1.2.840.10008.5.1.4.1.1.7` for every image — wrong for CT/MR/… ; `referencedSOPs` tuple has no `sopClassUID` |
| Performing Physician's Name at **root** | (0008,1050) | root | ❌ **#P11** not in F.7.2-1 at root (belongs in Performed Series items only) — strict SCPs return 0x0107 |
| Study Instance UID at **root** | (0020,000D) | root | ❌ **#P11** not in F.7.2-1 at root (only inside 0040,0270) |
| `MPPSProcedureStep.attributes: [Tag: Data]` ("Additional attributes") | — | — | ❌ **#P12** declared, accepted by `init`, **never written** into the dataset — silently dropped |

### 2b. N-SET

| Attribute | Code |
|---|---|
| PPS Status (3/1), End Date/Time (3/1), PPS Description (3/2), Performed Series Sequence (3/1) | ✅ |
| Scheduled Step Attributes Sequence (0040,0270) sent in N-SET | ⚠️ **#P13** table says *Not allowed* in N-SET; comment cites Orthanc. Keep behind an option, default off? |
| Protocol Name (Type 1) inside Performed Series on COMPLETED | ❌ same as #P9 |

`dicom-mpps` exposes none of the ❌ fields; it follows the model, so #P7–#P10 imply new CLI options.

---

## 3. Query/Retrieve C-FIND / C-MOVE / C-GET — PS3.4 C.6

Code: `DICOMNetwork/QueryKeys.swift`, `QueryService.swift`, `RetrieveService.swift`, `dicom-query`, `dicom-qr`, Studio Workshop.

| Level / table | Required (R/U) keys | Code default set | Result |
|---|---|---|---|
| Patient (C.6-1) | Name R, ID U; BirthDate, Sex, 3 counts O | all seven | ✅ |
| Study (C.6-5, Study Root) | Date, Time, Accession, Name, ID, Study ID R; Study UID U | all + Description, Referring, Modalities in Study, counts, Birth Date | ✅ (Patient's Sex ➖ not requested — trivial) |
| Series (C.6-3) | Modality, Series Number R; Series UID U; count O | all + Description, Date, Time, Body Part | ✅ |
| Instance (C.6-4) | Instance Number R; SOP Instance UID U; SOP Class, Available Transfer Syntax UID O | all except Available Transfer Syntax UID (0008,3002) | ✅ (➖ #P14 optional: request (0008,3002) — lets `dicom-retrieve` pick a C-GET transfer syntax) |
| Query/Retrieve Level (0008,0052) always set | | ✅ | |
| Information model: Patient Root only for patient level, Study Root otherwise | | ✅ all three front-ends | |
| Hierarchical unique keys (Study UID required for series query, +Series UID for instance) | | ⚠️ **#P15** not validated client-side; a series query without `--study-uid` is sent and the SCP answers 0xA900. Cheap to catch locally with a clear error | |
| C-MOVE/C-GET identifiers: level + Study/Series/SOP UIDs (+Patient ID for Patient Root) | | ✅ | |
| Generic `matching(tag:value:vr:)` / `returning(tag:vr:)` for any O key | | ✅ | |

Q/R is conformant; only #P14/#P15 are quality-of-life.

---

## 4. Storage Commitment Push Model — PS3.4 J.3

Code: `StorageCommitmentService.swift` (SCU + event receiver), `StorageCommitmentSCP.swift`.

| Attribute | Tag | SCU sends | SCU reads | SCP emits |
|---|---|---|---|---|
| Transaction UID (1) | (0008,1195) | ✅ | ✅ | ✅ |
| Referenced SOP Sequence › Class + Instance UID (1) | (0008,1199)/(1150)/(1155) | ✅ | ✅ | ✅ |
| Failed SOP Sequence › Class, Instance, Failure Reason (1 on event 2) | (0008,1198)/(1197) | — | ✅ | ✅ |
| Event Type ID 1 / 2 | | — | ✅ | ✅ |
| Retrieve AE Title (3) | (0008,0054) | ➖ | ➖ ignored (#P16 optional: expose it — it tells the SCU where the committed instances live) | ➖ |
| Storage Media File-Set ID/UID (3) | (0088,0130/0140) | ➖ | ➖ | ➖ |

Conformant. ✅

---

## 5. Print Management — PS3.4 H.4

Code: `PrintService.swift`, `dicom-print`, `dicom-printscp`, Studio print.

| Operation / attribute | Tag | Code |
|---|---|---|
| Film Session N-CREATE: Number of Copies, Print Priority, Medium Type, Film Destination (U/M) ; Film Session Label (U/U) | (2000,0010/0020/0030/0040/0050) | ✅ |
| Memory Allocation, Owner ID | (2000,0060)(2100,0160) | ➖ |
| Film Box N-CREATE: Image Display Format (M), Referenced Film Session Sequence (M), Film Orientation, Film Size ID, Magnification Type, Border Density, Empty Image Density, Trim (2C), Configuration Information, Referenced Presentation LUT Sequence | | ✅ |
| Film Box: **Annotation Display Format ID** — model field exists (`annotationDisplayFormatID`) but is **never emitted** in N-CREATE, so film-level annotation boxes are never created | (2010,0030) | ❌ **#P17** |
| Film Box: Illumination / Reflected Ambient Light — MC when a Presentation LUT is referenced (H.4.2.1.2.1) | (2010,015E)/(2010,0160) | ⚠️ **#P18** not sent; verify against the table and the printer's conformance statement |
| Film Box: Min/Max Density, Smoothing Type (U/U) | (2010,0120/0130/0080) | ➖ |
| Image Box N-SET: Position (M), Polarity, Requested Image Size, Decimate/Crop (3, guarded), Basic Grayscale/Color Image Sequence with Samples per Pixel, Photometric, Rows, Columns, Bits Allocated/Stored, High Bit, Pixel Representation, Pixel Data | | ✅ |
| Image Box: Pixel Aspect Ratio (MC — required when not 1:1) | (0028,0034) | ➖ #P19 optional — current pipeline resamples to square pixels before printing; confirm and document |
| Printer N-GET: Printer Status, Status Info, Name | (2110,0010/0020/0030) | ✅ |
| Print Job N-GET: Execution Status, Status Info, Creation Date | (2100,0020/0030/0040) | ✅ |
| Presentation LUT N-CREATE: Presentation LUT Sequence / Shape | (2050,0010/0020) | ✅ |

---

## 6. QIDO-RS — PS3.18 Table 10.6.1-5 (required matching + return attributes)

Code: client `DICOMWeb/QIDOQuery.swift` + `QIDOResults.swift` (`dicom-wado`, Studio DICOMweb);
server `DICOMWeb/Server/DICOMwebServer.swift` (`dicom-server`, Studio Workshop); conformance
claims `ConformanceStatementGenerator.swift`.

### 6a. Client filters / results

| Level | Required key | Filter | Result accessor |
|---|---|---|---|
| Study | Date, Time, Accession, Modalities in Study, Referring Physician, Patient Name/ID, Study UID, Study ID | ✅ all | ✅ |
| Series | Modality, Series UID, Series Number, PPS Start Date | ✅ | ✅ |
| Series | **PPS Start Time** | ❌ **#P20** | ❌ |
| Series | **Request Attributes Sequence › SPS ID, Requested Procedure ID** | ❌ **#P20** | ❌ |
| Instance | SOP Class, SOP Instance, Instance Number | ✅ | ✅ |

### 6b. Server (`parseQIDOQuery`)

| Check | Result |
|---|---|
| Accepts `{attributeID}` as **hex tag** (`00100010=`) — PS3.18 8.3.4.1 allows tag or keyword; only keywords are parsed (the UPS handler does accept both) | ❌ **#P21** |
| Study matching keys honoured: PatientName, PatientID, AccessionNumber, StudyInstanceUID, StudyDescription, ReferringPhysicianName | ✅ |
| **StudyDate, StudyTime, ModalitiesInStudy, StudyID** (required) | ❌ **#P22** ignored — a `StudyDate=20240101-20240131` query returns everything |
| **Series: SeriesNumber, PPS Start Date/Time, Request Attributes** (required) | ❌ **#P22** |
| **Instance: SOPClassUID, InstanceNumber** (required) | ❌ **#P22** |
| `includefield`, `fuzzymatching` | fuzzy ✅ · includefield ➖ |
| Study results: Study UID, Patient Name/ID, Date, Time, Description, Accession, Modalities, counts | ✅ |
| Study results **Referring Physician, Patient Birth Date/Sex, Study ID, Retrieve URL (0008,1190), Instance Availability** (required returns) | ❌ **#P23** |
| Series results: Study/Series UID, Modality, Number, Description, count | ✅ · **Retrieve URL, PPS Start Date/Time, Request Attributes** ❌ **#P23** |
| Instance results: UIDs, SOP Class, Instance Number | ✅ · **Retrieve URL** ❌ **#P23** |
| `ConformanceStatementGenerator` claims StudyDate/StudyTime/ModalitiesInStudy/SeriesNumber/InstanceNumber/SOPClassUID as supported matching keys | ❌ **#P24** claim ≠ implementation (resolved by #P22, or the claim must shrink) |

---

## Summary of proposed fixes, by impact

| # | Service | Fix | Size |
|---|---|---|---|
| **P10** | MPPS | Referenced SOP Class UID hard-coded to Secondary Capture → carry the real class (model + CLI change) | M |
| **P9** | MPPS | Protocol Name (Type 1) + Operators' Name / Retrieve AE Title / Non-Image seq in Performed Series | S |
| **P5** | MWL | decode response strings per Specific Character Set instead of ASCII | S |
| **P12** | MPPS | write `attributes: [Tag: Data]` into the dataset (currently dropped) | S |
| **P7/P8** | MPPS | Type 2 attributes at root and in Scheduled Step Attributes (empty when unknown) | S |
| **P11** | MPPS | remove root-level Performing Physician / Study Instance UID | S |
| **P22/P21/P23** | QIDO server | honour required matching keys, hex-tag form, required return attributes incl. Retrieve URL | M |
| **P2/P3/P6** | MWL | nested code sequences + Referenced Study Sequence in request and `WorklistItem` | M |
| **P4** | MWL | remaining Type 2 return keys (weight, size, alerts, allergies, priority, …) | S |
| **P1** | MWL | generic `matching`/`spsMatching` escape hatch | S |
| **P20** | QIDO client | PPS Start Time + Request Attributes filter/result | S |
| **P17** | Print | emit Annotation Display Format ID | S |
| **P24** | QIDO | conformance statement matches implementation | S (falls out of P22) |
| P13, P15, P18 | | decisions | — |
| P14, P16, P19 | | optional | — |

---

## 7. Resolution (2026-09-18)

| # | Service | What changed |
|---|---|---|
| **P10** | MPPS | `MPPSReferencedInstance` / `MPPSPerformedSeries` model; `referencedSOPClassUID` on the tuple path; `dicom-mpps update --sop-class-uid`. Without a class the SC placeholder is still used **and the CLI warns on stderr**. |
| **P9** | MPPS | Protocol Name (Type 1, `--protocol-name`, default `UNSPECIFIED`), Operators' Name, Retrieve AE Title, Referenced Non-Image Composite SOP Instance Sequence in every Performed Series item. |
| **P12** | MPPS | `attributes: [Tag: Data]` now written (VR from the dictionary) in N-CREATE and N-SET. |
| **P7 / P8** | MPPS | Patient Birth Date/Sex, Referenced Patient Sequence, Performed Location, Performed Procedure Type Description, Procedure Code Sequence, Study ID, Performed Protocol Code Sequence at root; Requested Procedure Description, Scheduled Protocol Code Sequence, populated Referenced Study Sequence in Scheduled Step Attributes. Requested Procedure ID is now its own field (`--requested-procedure-id`) instead of reusing the PPS ID. Data set is emitted in tag order. |
| **P11** | MPPS | Performing Physician's Name and Study Instance UID no longer sent at root. |
| **P13** | MPPS | `MPPSConfiguration.includeScheduledStepAttributesInNSet` / `update(legacyNSetScheduledStepAttributes:)` / `dicom-mpps update --legacy-nset-scheduled-attributes`, **default off**. |
| **P5** | MWL | `WorklistItem` decodes with the response's (0008,0005) via `CharacterSetHandler`; ISO_IR 100 assumed when absent. |
| **P2 / P3 / P6** | MWL | Parser keeps non-SPS sequences per item (`WorklistItem.sequences`); `requestedProcedureCode`, `scheduledProtocolCodes`, `referencedStudies` accessors; requested by `default()`. |
| **P4** | MWL | Priority, Weight, Size, Pregnancy Status, Medical Alerts, Allergies, Special Needs, Patient State, Admission ID, Current Patient Location, Requesting Physician, Transport Arrangements, SPS Location, Requested Contrast Agent, Pre-Medication requested and exposed; console + JSON output extended. |
| **P1** | MWL | `WorklistQueryKeys.matching(_:_:)` and `spsMatching(_:_:)`. |
| **P15** | Q/R | `DICOMQueryService.missingHigherLevelUniqueKey` throws before connecting; `dicom-query` validates `--study-uid` / `--series-uid` per level. Also found and fixed: `QueryKeys.matching` appended a **duplicate element** for a tag already present (e.g. an empty and a filled (0010,0020)); it now replaces. |
| **P20** | QIDO client | `performedProcedureStepStartTime`, `scheduledProcedureStepID`, `requestedProcedureID` filters (sequence-attribute form `00400275.00400009`); `QIDOSeriesResult.performedProcedureStepStartTime` / `.requestAttributes`. |
| **P21 / P22 / P23 / P24** | QIDO server | Every key accepted as keyword or 8-hex tag; StudyDate/StudyTime (DA/TM single + range), ModalitiesInStudy, StudyID, SeriesNumber, BodyPartExamined, SOPClassUID matched; Study Description / Referring Physician wildcard matching (previously parsed but never applied); results carry Referring Physician, Birth Date, Sex, Study ID, Instance Availability, Retrieve URL at every level, Rows/Columns/Frames/Bits on instances. Conformance statement claims updated. Instance Number is parsed but the in-memory provider cannot match it (not indexed). |
| **P17** | Print | **Withdrawn** — the job-level print flow does emit Annotation Display Format ID (`PrintService.swift` ≈ 4011); only the low-level `createFilmBox(filmBox:)` lacks it, and its `FilmBox` model has no such field by design. |
| **P18** | Print | Optional `PrintOptions.illumination` / `.reflectedAmbientLight`, sent with the Presentation LUT reference when set. |
| P14, P16, P19 | | not done (optional). |

Tests: `MPPSDataSetConformanceTests`, `MWLKeySetConformanceTests`, `QueryHierarchicalKeyTests`
(DICOMNetworkTests) and `QIDOConformanceTests` (DICOMWebTests). Audit script: 0/0/0.
