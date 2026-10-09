# DICOM Tag Audit — Phase 0/1 Findings (for review)

Generated 2026-09-18 by the Phase 0 audit script against `Sources/` and the bundled PS3.6 2026a
dictionary. 1 746 lines carrying a tag were scanned; 1 268 human names resolved to a dictionary
entry. Raw hits: 65 BLOCKER / 44 MAJOR / 15 WARN. Every hit below was verified by hand against
`DataElementDictionary.txt` and the surrounding source; parser noise has been removed (see §F).

**Status 2026-09-18: all rows below are resolved — see §G at the end for what was changed,
§H for the additional defects the fixes uncovered, and §I for the end-user verification list.**

Legend — **Impact**: *wire* = wrong bytes on the network or in a file; *parse* = wrong value read
from a conformant file; *API* = identifier misleads callers, tag itself correct; *doc* = comment only.

---

## A. Wrong tag — behaviour bugs (fix required)

### A1. Hanging Protocol constants — [Tag+HangingProtocol.swift](Sources/DICOMCore/Tag+HangingProtocol.swift)

Every constant below carries the tag of its *neighbour*; parser and serializer both use them, so
round-trip tests pass while files are non-conformant and vendor HP files mis-parse.

| # | Constant | Code has | PS3.6 says | Used |
|---|---|---|---|---|
| 1 | `numberOfPriorsReferenced` | (0072,000E) = HP User Identification Code Seq | **(0072,0014)** | 10× |
| 2 | `hangingProtocolUserIdentificationCodeSequence` | (0072,0014) | **(0072,000E)** | 0 |
| 3 | `hangingProtocolUserGroupName` | (0072,0016) — *not a DICOM tag* | **(0072,0010)** | 7× |
| 4 | `hangingProtocolEnvironmentSequence` | (0072,0010) = HP User Group Name | *no such attribute in PS3.6*; C.23.2 has no sequence | 7× |
| 5 | `imageSetSelectorUsageFlag` | (0072,0022) = Image Set Selector Seq | **(0072,0024)** | 2× |
| 6 | `selectorAttribute` | (0072,0024) | **(0072,0026)** | 5× |
| 7 | `selectorValueNumber` | (0072,0026) | **(0072,0028)** | 3× |
| 8 | `selectorSequence` | (0072,0050) = Selector Attribute VR | parser uses it as *Image Set Selector Sequence* → **(0072,0022)** | 4× |
| 9 | `selectorCodeSequenceValue` | (0072,0052) = Selector Sequence Pointer | **(0072,0080)** | 0 |
| 10 | `imageBoxSynchronizationSequence` | (0072,0340) — *not a tag* | **(0072,0430)** | 0 |
| 11 | `synchronizedImageBoxList` | (0072,0342) — *not a tag* | **(0072,0432)** | 0 |
| 12 | `typeOfSynchronization` | (0072,0344) — *not a tag* | **(0072,0434)** | 0 |
| 13 | `imageBoxSynchronizationSequencePointer`, `textBoxSequencePointer`, `imageBoxSynchronizationSequenceItemNumber`, `textBoxSequenceItemNumber` | (0072,0430/0432/0434/0436) | these *names* don't exist; the tags belong to #10–12 | 0 |

**Proposed action**: this is not a one-line fix. Re-derive the HP tag table from PS3.6 group 0072,
then re-check `HangingProtocolParser` / `Serializer` against PS3.3 C.23.1–C.23.5 module tables
(Phase 2 item). Existing HP tests must be rewritten to assert *numeric* tags, not constants.

### A2. Real World Value LUT — two files

| # | File | Code has | PS3.6 says | Impact |
|---|---|---|---|---|
| 14 | [Tag+ParametricMap.swift:87](Sources/DICOMCore/Tag+ParametricMap.swift#L87) `doubleFloatRealWorldValueFirstValueMapped` | (0040,9213) = *Last* | **(0040,9214)** | parse — FD first/last swapped in `ParametricMapParser:177/187` |
| 15 | [Tag+ParametricMap.swift:91](Sources/DICOMCore/Tag+ParametricMap.swift#L91) `doubleFloatRealWorldValueLastValueMapped` | (0040,9214) = *First* | **(0040,9213)** | same |
| 16 | [RealWorldValueLUTParser.swift:133-135](Sources/DICOMKit/RealWorldValue/RealWorldValueLUTParser.swift#L133-L135) | first ← (0040,9212) **LUT Data**; last ← (0040,9213) **Double Last**; lutData ← (0040,9216) **First Value Mapped** | first (0040,9216)/(0040,9214), last (0040,9211)/(0040,9213), data **(0040,9212)** | parse — LUT-form RWV mappings can never parse (`float64Value` of an FD array / US scalar mismatch) |

**Proposed action**: swap #14/#15; rewrite #16 to read US pair (9216/9211) with FD fallback
(9214/9213) and data from 9212. Add a round-trip test with a real LUT-form RWVM item.

### A3. Radiation Therapy — [Tag+RadiationTherapy.swift](Sources/DICOMCore/Tag+RadiationTherapy.swift)

| # | Constant | Code has | PS3.6 says | Used |
|---|---|---|---|---|
| 17 | `applicationSetupNumber` (L325) | (300A,0232) = Type | **(300A,0234)** | `RTPlanParser:324` |
| 18 | `applicationSetupType` (L328) | (300A,0234) = Number | **(300A,0232)** | `RTPlanParser:328` |
| 19 | `roiElementalCompositionSequence` (L118) | (3006,00B7) = …Atomic Number | **(3006,00B6)** | 0 |

**Proposed action**: swap #17/#18 (brachy application setups currently parse number as type);
fix #19.

### A4. Waveforms — [Tag+Waveforms.swift](Sources/DICOMCore/Tag+Waveforms.swift)

| # | Constant | Code has | PS3.6 says | Used |
|---|---|---|---|---|
| 20 | `unformattedTextValue` (L208) | (0040,A160) = SR *Text Value* | Waveform Annotation Module C.10.9 uses **(0070,0006)** Unformatted Text Value | `WaveformParser:286`, `WaveformBuilder:590`, GSPS legacy fallback |
| 21 | `triggerSamplePosition` (L40) | (0018,106C) = Synchronization Channel | **(0018,106E)** | 0 |
| 22 | `waveformDataDisplayScale` (L155) | (5400,1014) — *not a tag* | **(003A,0230)** | 0 |

**Proposed action**: #20 — waveform annotations are written to / read from the SR tag; fix
builder+parser to (0070,0006) and keep (0040,A160) as read-fallback (same pattern GSPS already
uses). Rename constant to `textValue` (its real PS3.6 keyword) to stop future confusion.
#21/#22 straight fixes.

### A5. Structured Reporting — [Tag+StructuredReporting.swift](Sources/DICOMCore/Tag+StructuredReporting.swift)

| # | Constant | Code has | PS3.6 says | Used |
|---|---|---|---|---|
| 23 | `mappingResourceUID` (L176) | (0008,0117) = Context UID | **(0008,0118)** | 0 |
| 24 | `mappingResourceName` (L180) | (0008,0118) = Mapping Resource UID | **(0008,0122)** | 0 |

### A6. Image / Multiframe

| # | Location | Code has | PS3.6 says | Used |
|---|---|---|---|---|
| 25 | [Tag+ImageInformation.swift:230](Sources/DICOMCore/Tag+ImageInformation.swift#L230) `frameDimensionPointer` | (0028,0014) = Ultrasound Color Data Present | **(0028,000A)** | 0 |
| 26 | [FunctionalGroupFlattener.swift:261](Sources/DICOMKit/Multiframe/FunctionalGroupFlattener.swift#L261) `segmentedKSpaceTraversal` | (0018,9105) = Slab Orientation (FD) | **(0018,9033)** (CS) | L291 — Enhanced MR flattening reads an FD as CS → always nil |

### A7. DICOMweb UPS-RS — wire-level

| # | Location | Code has | PS3.6 says | Impact |
|---|---|---|---|---|
| 27 | [Workitem.swift:1368](Sources/DICOMWeb/UPS/Workitem.swift#L1368) `humanPerformerCodeSequence` | `"00404036"` = Human Performer's Organization | **`"00404009"`** | wire — swapped with #28; build+parse+tests all use the swap |
| 28 | [Workitem.swift:1370](Sources/DICOMWeb/UPS/Workitem.swift#L1370) `humanPerformerOrganization` | `"00404009"` = Human Performer Code Seq | **`"00404036"`** | wire |
| 29 | [UPSEvent.swift:266](Sources/DICOMWeb/UPS/UPSEvent.swift#L266) | writes organization to `"00404009"` with `vr: LO` | **`"00404036"`** | wire — sends an LO where an SQ is expected |
| 30 | [Workitem.swift:1391](Sources/DICOMWeb/UPS/Workitem.swift#L1391) `procedureStepDiscontinuationReasonCodeSequence` | `"00741236"` = Requesting AE | **`"0074100E"`** | wire |
| 31 | [Workitem.swift:1404](Sources/DICOMWeb/UPS/Workitem.swift#L1404) `retrieveURI` | `"00401002"` = Reason for the Requested Procedure | **`"0040E010"`** | wire — `Workitem:1087/1306` |

**Proposed action**: fix all five; update `WorkitemBuilderTests:494-495` which currently pins the
swap.

---

## B. Identifier ≠ PS3.6 keyword — tag correct, name misleading (API rename, optional)

| # | File:line | Constant | PS3.6 keyword | Note |
|---|---|---|---|---|
| 32 | Tag+ModalitySpecific:46 | `exposureInMicroAs` | `ExposureInuAs` | cosmetic |
| 33 | Tag+ModalitySpecific:244 | `thermalIndex` | `CranialThermalIndex` | misleading — TI, TIS, TIB, TIC are separate tags |
| 34 | Tag+PresentationState:18/21/24/33 | `presentationInstanceNumber/Label/Description/CreatorsName` | `InstanceNumber`, `ContentLabel`, `ContentDescription`, `ContentCreatorName` | deliberate aliases? — `presentationInstanceNumber` duplicates `Tag.instanceNumber` |
| 35 | Tag+PresentationState:154 | `verticesOfPolygonalShutter` | `VerticesOfThePolygonalShutter` | cosmetic |
| 36 | Tag+RadiationTherapy:322 | `brachyApplicationSetupSequence` | `ApplicationSetupSequence` | cosmetic |
| 37 | Tag+Segmentation:42 | `maxFractionalValue` | `MaximumFractionalValue` | cosmetic |
| 38 | Tag+SeriesInformation:46 | `operatorName` | `OperatorsName` | VM 1-n; singular name hides that |
| 39 | Tag+StudyInformation:62/66/70/74 | `physicianOfRecord`, `…IdentificationSequence`, `nameOfPhysicianReadingStudy`, `physicianReadingStudy…` | `PhysiciansOfRecord`, … | VM 1-n; same |
| 40 | Tag+PresentationState:73 | `textObjectUnformattedTextValue` | `UnformattedTextValue` | only exists because #20 stole the real name — collapses once #20 is fixed |
| 41 | UPSQuery.swift:464 | `scheduledStationName = "00404025"` | `ScheduledStationNameCodeSequence` | comment says it matches on the code sequence — deliberate, keep, but rename |

**Proposed action**: decide policy — either (a) rename to the PS3.6 keyword with a deprecated alias,
or (b) leave and add these to the script's allow-list. Recommend (a) for #33, #38, #39, #40; (b) for
the rest.

---

## C. Doc comment / VR annotation wrong — no behaviour change

| # | File:line | Says | Should say |
|---|---|---|---|
| 42 | Tag+ImageInformation:230 | `VR: AT` for (0028,0014) | resolves with #25 |
| 43 | Tag+PixelData:22 | `VR: UT` for (0028,7FE0) Pixel Data Provider URL | `UR` |
| 44 | Tag+StructuredReporting:180 | `VR: LO` for (0008,0118) | resolves with #24 |
| 45 | Tag+Waveforms:40 | `VR: US` for (0018,106C) | resolves with #21 |
| 46 | Tag+Waveforms:155 | `VR: DS` for Waveform Data Display Scale | `FL` (with #22) |

---

## D. Ground-truth (dictionary) defects — must fix before the script goes into CI

| # | Finding | Effect |
|---|---|---|
| 47 | `DataElementDictionary.txt` has **no repeating-group entries** — 0 rows for 50xx (Curve) and 60xx (Overlay). `DataElementDictionary.lookup(tag:)` returns nil for every overlay tag, so `dicom-dump` / Studio tag view show them as unknown | Tag+OverlayInformation constants can't be verified; runtime name lookup fails |
| 48 | Multi-VR attributes are collapsed to one VR: (0028,3006) LUT Data stored as `US` (PS3.6: `US or OW`), (7FE0,0010) Pixel Data as `OB` (`OB or OW`), etc. — 66 rows affected | VR checks give false positives (`PrintService:823` writes OW, which is correct) |
| 49 | (7FE0,0001)/(7FE0,0002) Extended Offset Table stored as `UN`; PS3.6 says `OV`. Code doc comments are right, dictionary is wrong | wrong VR shown in dumps |

**Proposed action**: fix [generate_full_dictionary.py](Scripts/generate_full_dictionary.py) to (a)
emit `xx` repeating groups the way PS3.6 does, (b) keep the full `A or B` VR string, (c) not
downgrade OV. Then regenerate and re-run the audit.

---

## E. Things the audit could *not* cover yet (Phase 2/3 scope — semantic, not mechanical)

- `DICOMNetwork` (MWL, MPPS, Q/R, Storage Commitment, Print) and all `dicom-*` CLIs produced **zero
  confirmed tag/name mismatches** in the mechanical pass. That means number == name everywhere a
  name is written — it does *not* yet prove the right key *sets* are used. That is Phase 2.
- 478 tag lines carry no name at all (bare hex, no comment) — mostly in
  `DICOMNetwork/PrintService.swift`, `PrintSCPEncoder.swift`, `StorageService.swift`. The script
  can't check those; Phase 5's "always write the keyword beside the tag" rule closes this.

---

## F. Discarded — parser noise (no action)

`Reference:` doc headers → retired attr "Reference" (0020,1020); "Contrast/Bolus …" → "Contrast";
`// Study Date / Time` → "Time"; generic struct fields `uid`, `status`, `date`, `sopClassUID`
inside Referenced-SOP items; explanatory prose in doc comments (Slice Thickness under
`pixelMeasuresSequence`, Window Center under `softcopyVOILUTSequence`, Other Patient IDs Sequence
under `otherPatientIDs`, Text Value under `textObjectUnformattedTextValue`, Graphic Data under
`graphicAnnotationUnits`). All 20 verified as correct code.

---

## Proposed next steps (awaiting your ✅)

1. **Fix batch 1 — pure swaps/one-liners with no design question**: #14–#19, #21–#26, #27–#31,
   #43, #46 (+ update the tests that pin the wrong values).
2. **Fix batch 2 — Waveform annotation text (#20)** — includes a read-fallback so existing files
   written by DICOMKit still parse.
3. **Redesign item — Hanging Protocol (#1–#13)**: re-derive from PS3.3 C.23 + PS3.6 group 0072.
4. **Dictionary generator (#47–#49)**, then regenerate and re-run.
5. **Naming policy (§B)** — your decision.
6. **Add the audit script to `Scripts/audit-tags.py`** and a `DICOMCoreTests` test that asserts
   every `Tag.xxx` constant's keyword against the dictionary (Phase 4.1) — this is what makes the
   fix permanent.

---

## G. Resolution (2026-09-18)

All of §A, §C and §D fixed; §B applied per the naming policy (rename + deprecated forwarder for
#33, #34, #38, #39, #40, #41; allow-list for #32, #35, #36, #37). Audit script now reports
**0 BLOCKER / 0 MAJOR / 0 WARN**; full package test run: **3 336 XCTest + 8 030 Swift Testing
cases, 0 failures**.

| Area | Change |
|---|---|
| Ground truth | `Scripts/generate_full_dictionary.py` rewritten: keeps every VR (`US/OW`), emits 50xx/60xx repeating groups at their base group (66 rows), adds a Retired column, emits OV/SV/UV. `DataElementDictionary.lookup(tag:)` normalises repeating groups. `VR` enum gains `OV`, `SV`, `UV` (34 VRs, PS3.5 2026a). |
| DICOMCore constants | #1–#25 corrected in `Tag+HangingProtocol`, `Tag+ParametricMap`, `Tag+RadiationTherapy`, `Tag+Waveforms`, `Tag+StructuredReporting`, `Tag+ImageInformation`. Four non-existent HP names are `@available(*, unavailable)`. `Tag+HangingProtocol` now carries the full Selector Attribute Macro (0072,0050–0083). |
| Parsers | `RealWorldValueLUTParser` LUT form reads (0040,9216)/(0040,9211) with FD fallback and LUT data from (0040,9212). `FunctionalGroupFlattener` reads Segmented k-Space Traversal (0018,9033). Waveform annotations written to / read from (0070,0006) with (0040,A160) read-fallback. GSPS parser same fallback. |
| Hanging Protocol | Parser/serializer use Hanging Protocol Definition Sequence (0072,000C) and Image Set Selector Sequence (0072,0022). |
| DICOMweb UPS-RS | `Workitem` keys #27–#31 corrected; `UPSEvent` organisation → (0040,4036); `UPSQuery` station attributes renamed to `…CodeSequence`. |
| Guardrails | `Scripts/audit_tags.py --strict` added to `.github/workflows/ci.yml` before the build. `DICOMDictionaryTests/TagConstantAuditTests` checks all 985 `Tag` constants against the dictionary plus pins for every corrected tag. `DICOMKitTests/TagAuditRegressionTests` rebuilds RWV, waveform and HP inputs from numeric tags. CONTRIBUTING §DICOM Standard Compliance rule 6. |

## H. Additional defects found while fixing (not in the original list)

| # | Where | What | Fix |
|---|---|---|---|
| 50 | `DICOMWeb/UPS/UPSClient.swift:721/729`, `DICOMWeb/DICOMwebClient.swift:2041/2049` | UPS cancel-request contact info written to **(0040,1006) Placer Order Number** (retired) and **(0040,1005) Requested Procedure Location** | (0074,100C) Contact Display Name LO, (0074,100A) Contact URI UR |
| 51 | `DICOMStudio/Components/CLIWorkshopHelpers.swift` UPS tag-name map | `"00404036"` labelled *Human Performer Code Sequence*, `"00741236"` labelled *Procedure Step Discontinuation Reason Code Sequence*, `"00741002"` labelled *Contact URI* | names corrected; (0040,4009), (0074,100E), (0074,100A), (0074,100C) added |
| 52 | `DICOMKit/HangingProtocol/HangingProtocolParser.swift` | every US attribute (Image Set Number, Selector Value Number, screen pixels, Display Set Number, tile dimensions, scroll amounts, …) read via `integerStringValue`, which returns nil for anything but IS → all numeric HP fields parsed as nil; FD attributes read as DS | read US via `uint16Value`, FD via `float64Value(s)` |
| 53 | `DICOMKit/HangingProtocol/HangingProtocolSerializer.swift` | Relative Time (0072,0038) written as SL; Display Environment Spatial Position (0072,0108) written as a backslash string tagged FD | US and FD respectively |
| 54 | `Package.swift` DICOMKitTests | `HangingProtocol/`, `RealWorldValue/`, `Waveform/`, `ParametricMap/`, `RadiationTherapy/`, `Segmentation/`, `StructuredReporting/` test directories are **excluded** from the build — those suites have never run. This is why #1–#13 and #52 survived. | HP parser/serializer and RWV parser suites added to the allowlist and pass; the remaining five directories enabled in Phase 3 (§J), which surfaced #56–#61 |
| 55 | `Tests/DICOMCoreTests/VRTests.swift` | pinned `VR.allCases.count == 31` | 34 |

## J. Phase 3 (2026-09-18) — Selector Attribute Value Macro and the five remaining suites

**Hanging Protocol selector values.** `HangingProtocolSerializer` wrote an Image Set Selector's
values under the selected attribute's own tag inside the selector item (a Modality selector put
"CT" in (0008,0060) as LO) and `HangingProtocolParser` read them back the same way. PS3.3
Table C.23.4-1 carries them in Selector Attribute VR (0072,0050) plus the Selector *xx* Value
element for that VR ((0072,005E)–(0072,0083)). `SelectorAttributeValueCoding` now maps every VR
to its value tag and encodes/decodes it (string VRs, binary numerics, AT, the byte VRs as hex,
SV/UV/OV, and Selector Code Sequence Value (0072,0080) for SQ). `ImageSetSelector` gains
`attributeVR` (nil → data dictionary; required for private attributes carrying values),
`sequencePointer` (0072,0052) and `codeValues`. The parser still accepts the old layout and a
Selector *xx* Value with no (0072,0050) beside it. `SelectorAttributeValueTests` (17 tests).

**Five suites enabled** (`ParametricMap`, `RadiationTherapy`, `Segmentation`,
`StructuredReporting`, `Waveform`, the three remaining `HangingProtocol` suites (DisplaySet,
Matcher, ImageSetDefinition), plus `TestHelpers/DataSet+TestHelpers.swift`, which was
excluded as a directory and therefore never compiled either). Defects they surfaced:

| # | Where | What | Fix |
|---|---|---|---|
| 56 | `CADFindingsExtractor` | probability looked for (111023, DCM); both CAD SR builders and PS3.16 TID 4021/4104 use (111047, DCM) *Probability of cancer* → every finding was dropped | accept 111047 (111023 kept) |
| 57 | `CADFindingsExtractor` | Manufacturer expected as a CODE item; builders write TEXT (113878, DCM) | accept TEXT |
| 58 | `CADFindingsExtractor` | builders write finding type *and* each characteristic as CODE under (121071, DCM) "Finding"; the last one overwrote the type | first is the type, the rest characteristics |
| 59 | `MammographyCADSRBuilder`, `ChestCADSRBuilder`, `CADFindingsExtractor` | CIRCLE written as 3 values (cx, cy, r); PS3.3 C.18.6.1.2 is two points (centre + circumference point); extractor took the axis differences as radii | writer emits (cx, cy, cx+r, cy); reader uses the distance |
| 60 | `MeasurementReportBuilder` / `MeasurementReportExtractor` | `addQualitativeEvaluation(conceptName:value:)` discarded the concept name and wrote CODE items with none; the extractor only looked for evaluations at the root, not in the TID 1500 row 9 container (C0034375, UMLS) | concept name kept (`qualitativeEvaluationConceptNames`); extractor descends into the container |
| 61 | `ParametricMapParser` | Real World Value Slope/Intercept (0040,9225/9224) read as DS only; they are FD → every linear mapping was dropped | FD first, DS fallback |
| 62 | `Tests/…/DataSet+TestHelpers` | `append(_:Int)` wrote every integer as SL and `append(_:Double)` every double as FD, regardless of the tag's VR | dictionary VR honoured (IS/US/SS/UL/FD/FL/DS) |
| 63 | `MeasurementReportExtractorTests` | three tests asserted a Finding / Finding Site they never set, and one expected no Tracking UID although TID 1411 makes it mandatory (the builder generates one) | tests set them via the new `addMeasurementGroup(…, finding:, findingSite:)` parameters |

## I. Verification from the end-user side

See the closing message of the audit session / `DICOM_TAG_AUDIT_VERIFICATION.md`.
