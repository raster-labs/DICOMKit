# DICOM Tag Audit — End-User Test Cases

Manual test cases for every DICOM tag corrected by the tag audit (findings #1–#31 and #50–#63 in
`DICOM_TAG_AUDIT_FINDINGS.md`, plus the three follow-ups fixed on 2026-09-19: LUT Explanation in the
RWV parser, UPS Event Type ID key, playground comment). Rows 1–33 of
`DICOM_TAG_AUDIT_VERIFICATION.md` remain valid; this document adds the input data and the exact
steps for the modules that had none.

## 0. What can and cannot be tested from the app or CLI

Only some corrected modules are wired into DICOM Studio or a `dicom-*` tool. The rest are library
code that no CLI or screen calls yet. Do not expect them to show up in the app.

| Module | Studio / CLI surface | How to test |
|---|---|---|
| Dictionary (names, VRs, overlay/curve groups, OV) | `dicom-dump`, `dicom-info`, `dicom-tags`, `dicom-validate`, Studio Inspector | Part A |
| Waveform annotation (0070,0006) | Studio viewer, ECG files | Part A |
| Structured Report parsing | `dicom-report`, Studio SR view | Part A |
| UPS-RS wire keys, Event Type ID | `dicom-wado ups`, Studio → DICOMweb → UPS | Part A |
| MWL / MPPS / Q-R key sets | `dicom-mwl`, `dicom-mpps`, `dicom-query`, Studio Workshop | Rows 14–22 of the verification checklist |
| Hanging Protocol parser/serializer | none (Studio HP panel is app-internal, does not read HP objects) | Part B harness |
| RT Plan / RT Structure Set | none | Part B harness |
| Real World Value LUT, Parametric Map | none | Part B harness |
| Enhanced MR flattening (k-space traversal) | none (`dicom-convert`/`dicom-split` do not flatten) | Part B harness |
| CAD SR extractor, Measurement Report extractor/builder | none (Studio CAD list is fed by the app, not from files) | Part C, DICOMKit-written objects checked with `dcmdump` |

## 1. Setup

```bash
# Build every CLI once. Binaries land in .build/debug/dicom-*.
swift build
export PATH="$PWD/.build/debug:$PATH"

# Foreign-toolkit fixtures. Written by pydicom, never by DICOMKit, so a wrong
# constant cannot mask itself. Needs: pip3 install pydicom numpy
python3 Scripts/audit_fixtures/make_audit_fixtures.py ~/audit_fixtures
```

The generator writes nine files into `~/audit_fixtures`:

| File | SOP Class | Corrected tags it carries |
|---|---|---|
| `hp.dcm` | Hanging Protocol Storage | (0072,0010) (0072,0014) (0072,000C) (0072,0022) (0072,0024) (0072,0026) (0072,0028) (0072,0050) (0072,0062) (0072,007A), US screen sizes |
| `rtplan.dcm` | RT Plan | (300A,0232) Type = `FLETCHER_SUIT`, (300A,0234) Number = 7 |
| `rtstruct.dcm` | RT Structure Set | (3006,00B6) ROI Elemental Composition Sequence, 2 items |
| `ecg.dcm` | 12-lead ECG | (0070,0006) annotation text, (0018,106E) Trigger Sample Position = 25, (003A,0230) Display Scale = 10, (0018,1800) |
| `enhanced_mr.dcm` | Enhanced MR | RWV LUT form: (0028,3003) explanation, (0040,9216)/(0040,9211) first/last = 0/63, (0040,9212) 64 FD values; (0018,9033) = `SINGLE` |
| `enhanced_pet_fd.dcm` | Enhanced PET | (0040,9214)/(0040,9213) Double Float first/last = 0.0/63.0 |
| `pmap.dcm` | Parametric Map | (0040,9225) Slope FD = 2.5, (0040,9224) Intercept FD = 0 |
| `frame_dim_pointer.dcm` | Enhanced MR | (0028,000A) Frame Dimension Pointer |
| `sr_mapping_resource.dcm` | Comprehensive SR | (0008,0118) Mapping Resource UID, (0008,0122) Mapping Resource Name |

DCMTK (`dcmdump`, `dcmodify`) is used as the independent reference. `dcmdump` prints group numbers
in lower case, so grep for `300a`, not `300A`.

## 2. Part A — test cases through the CLI and DICOM Studio

Each case: **Input → Steps → Expected**. "Before" describes the behaviour with the old constants,
so you can tell a genuine pass from a test that never exercised the fix.

### A1. Dictionary names and VRs (findings #47–#49)

**Input**: any CT/CR file, plus `dcmodify` to add an overlay and an extended offset table.

```bash
cp some_ct.dcm ovl.dcm
dcmodify -nb -i "(6000,0010)=512" -i "(6000,0011)=512" -i "(6000,0040)=G" ovl.dcm
dicom-dump ovl.dcm --tag 6000,0010 --verbose
dicom-info ovl.dcm --format json | grep -i overlay
```

Expected: `dicom-dump` prints **Overlay Rows** with VR **US**, `dicom-info` names the overlay
attributes. Before: "Unknown" / `UN`. Odd groups (6001,xxxx) must still show as private.

Studio: open `ovl.dcm`, Inspector → Metadata. Rows (6000,0010), (6000,0011), (6000,0040) carry
their standard names.

Multi-VR: `dicom-validate` on a file whose LUT Data (0028,3006) is `OW` prints **no** "Unexpected VR
OW" warning. A multi-frame HTJ2K file with (7FE0,0001) shows VR **OV** in Studio's Inspector.

### A2. Waveform annotation text (finding #20)

**Input**: `~/audit_fixtures/ecg.dcm` (annotation under (0070,0006)), and, if you have one, an ECG
saved by a DICOMKit build older than 2026-09-18 (annotation under (0040,A160)).

Steps: open each file in Studio. The waveform chart's metadata strip shows **Annotations: 1** for
`ecg.dcm`. The old-build file also shows its annotation (read fallback).

CLI cross-check that the fixture really uses the new tag:

```bash
dcmdump ~/audit_fixtures/ecg.dcm | grep -E '0070,0006|0040,a160'
```

Expected: one (0070,0006) line, no (0040,a160). Before the fix Studio showed **Annotations: 0**
for vendor ECGs, because the parser looked for the SR Text Value tag.

Write side: create an ECG with a text annotation through the API or the Workshop, then
`dcmdump` it. The text must sit under (0070,0006) inside (0040,B020). dcm4che/DCMTK readers now
display it.

### A3. Structured Report parsing (findings #23, #24, #56–#60)

**Input**: `~/audit_fixtures/sr_mapping_resource.dcm`; a QIICR/dcmqi TID 1500 sample; a vendor
Mammography or Chest CAD SR if available.

```bash
dicom-report ~/audit_fixtures/sr_mapping_resource.dcm --format text --output sr.txt && cat sr.txt
dicom-report ~/audit_fixtures/sr_mapping_resource.dcm --format json --output sr.json

# The Mapping Resource attributes live inside Content Template Sequence.
# dicom-dump --tag only reads top-level elements, so check the nested pair with
# dcmdump, and check DICOMKit's dictionary names on a copy that has them at top level.
dcmdump ~/audit_fixtures/sr_mapping_resource.dcm | grep -E '0008,0118|0008,0122'
cp ~/audit_fixtures/sr_mapping_resource.dcm sr_top.dcm
dcmodify -nb -i "(0008,0118)=1.2.840.10008.8.1.1" -i "(0008,0122)=DICOM Content Mapping Resource" sr_top.dcm
dicom-dump sr_top.dcm --tag 0008,0118 --verbose
dicom-dump sr_top.dcm --tag 0008,0122 --verbose
```

Expected: `dicom-report` writes a report headed "Imaging Measurement Report" with the item
"Comment: audit" and exits 0. `dicom-dump` prints `(0008,0118)  Mapping Resource UID  VR=UI` and
`(0008,0122)  Mapping Resource Name  VR=LO`. Before: (0008,0118) was labelled Mapping Resource
Name with VR LO.

Studio: open the file. The SR view renders the document tree.

CAD and TID 1500 extraction is library-only. See Part C.

### A4. UPS-RS workitem keys (findings #27–#31, #50, #51)

Needs a UPS-RS server. dcm4chee-arc 5.x is the reference; Orthanc has no UPS-RS.

```bash
BASE=http://localhost:8080/dcm4chee-arc/aets/DCM4CHEE/rs

dicom-wado ups $BASE --create-workitem \
  --patient-name "UPS^Audit" --patient-id UPS1 --label "Audit CT" \
  --performer-name "Reader^One" --performer-organization "Audit Radiology Dept" \
  --format json
```

Copy the workitem UID from the output, then:

```bash
dicom-wado ups $BASE --get <uid> --format json > wi.json
python3 -c "import json;d=json.load(open('wi.json'));
print('org  ', d.get('00404036'));
print('code ', d.get('00404009'))"
```

Expected: `00404036` holds `{"vr":"LO","Value":["Audit Radiology Dept"]}` and `00404009`, if
present, is an `SQ`. The server accepts the create without a VR error. Before: the organization
was sent as LO under `00404009`, which dcm4chee rejected or stored under the wrong attribute.

Studio: CLI Workshop → UPS-RS → Create with a performer organisation, then open the raw JSON
viewer for the created workitem. The label next to `00404036` reads **Human Performer's
Organization**, `0074100E` reads **Procedure Step Discontinuation Reason Code Sequence**,
`0040E010` reads **Retrieve URI**, `0074100C` **Contact Display Name**, `0074100A` **Contact URI**.

Cancel path: in Studio → DICOMweb → UPS, request cancellation of an IN PROGRESS workitem with a
reason, contact name and contact URI. On the server (`GET` the workitem, or its cancel-request
event) the contact appears under (0074,100C) and (0074,100A). Before: it was written to the
retired Placer Order Number (0040,1006) and Requested Procedure Location (0040,1005).

### A5. UPS Event Type ID (fix of 2026-09-19)

1. Studio → DICOMweb → UPS: subscribe to the workitem from A4 with AE title `STUDIO`, then Start
   the **Event Monitor**. Channel state reads Connected.
2. Drive state changes from the CLI while Studio listens:

```bash
TX=$(dicom-uid)   # any fresh UID
dicom-wado ups $BASE --update <uid> --state IN_PROGRESS --transaction-uid $TX
dicom-wado ups $BASE --update <uid> --state COMPLETED   --transaction-uid $TX
```

Expected: two rows typed **State change** with summaries like "State: SCHEDULED → IN PROGRESS"
and "State: IN PROGRESS → COMPLETED". Before: a server sending only the numeric Event Type ID
(0000,1002) produced rows of the wrong type or none, because the client read Command Field.

### A6. MWL / MPPS / Q-R

Already covered as rows 14–22 in `DICOM_TAG_AUDIT_VERIFICATION.md`. Use `dicom-mwl`, `dicom-mpps`
and `dicom-query` against dcm4chee-arc or Orthanc as described there.

## 3. Part B — library-only modules, one command

For the modules with no CLI or screen, the harness `Tests/DICOMKitTests/AuditFixtureHarnessTests.swift`
plays the role of the end user: it opens each pydicom fixture through the same public parsers a
future CLI would call and asserts the corrected value.

```bash
AUDIT_FIXTURES=~/audit_fixtures swift test --filter AuditFixtureHarnessTests
```

Expected: `Executed 10 tests, with 0 failures`. Without `AUDIT_FIXTURES` the suite skips.

| Test | Finding | Input | Asserts |
|---|---|---|---|
| `test_hangingProtocol_userGroupPriorsSelectorsAndUSValues` | #1–#13, #52 | `hp.dcm` | user group `AuditRadiologists`, 2 priors, 2 selectors: Modality = CT, Rows = 512 (US), screen 1920×1080 |
| `test_rtPlan_brachyApplicationSetupNumberAndTypeNotSwapped` | #17, #18 | `rtplan.dcm` | number 7, type `FLETCHER_SUIT` |
| `test_rtStruct_elementalCompositionSequenceTag` | #19 | `rtstruct.dcm` | (3006,00B6) has 2 items |
| `test_waveform_annotationTextFrom0070_0006_andTriggerAndDisplayScale` | #20–#22 | `ecg.dcm` | annotation text, trigger 25, display scale 10 |
| `test_enhancedMR_lutFormRWV_readsExplanationFirstLastAndData` | #16, LUT Explanation | `enhanced_mr.dcm` | explanation from (0028,3003), first 0, last 63, 64 LUT values |
| `test_enhancedPET_doubleFloatFirstLastNotSwapped` | #14, #15 | `enhanced_pet_fd.dcm` | first 0.0, last 63.0 |
| `test_parametricMap_linearRWVSlopeInterceptReadAsFD` | #61 | `pmap.dcm` | slope 2.5, intercept 0 |
| `test_enhancedMR_flatten_carriesSegmentedKSpaceTraversal` | #26 | `enhanced_mr.dcm` | flattened frame has (0018,9033) = `SINGLE` |
| `test_frameDimensionPointer_tag0028_000A` | #25 | `frame_dim_pointer.dcm` | constant is (0028,000A) and element present |
| `test_sr_mappingResourceUIDAndName` | #23, #24 | `sr_mapping_resource.dcm` | UID and name read from (0008,0118)/(0008,0122) |

To reproduce a "before" failure, check out a commit older than 2026-09-18, keep the fixtures, and
run the same command. The HP, RT, RWV and waveform tests fail there.

Vendor data is a stronger input than pydicom. If you have any of the following, run the same
harness after copying the file over the fixture name: a GE/Siemens PET SUV series with LUT-form
RWV mapping (→ `enhanced_pet_fd.dcm`), a Varian/Elekta brachy RT Plan (→ `rtplan.dcm`), a
Philips/GE 12-lead ECG (→ `ecg.dcm`), a dcm4che Hanging Protocol sample (→ `hp.dcm`). Adjust the
expected literals in the test to the values shown by `dcmdump`.

## 4. Part C — objects written by DICOMKit, checked with DCMTK

These verify the write side of the corrected constants. The playgrounds under `Playgrounds/4.
Structured Reporting` build the objects; `dcmdump` is the independent reader.

### C1. Hanging Protocol export (findings #1–#13, #53)

Build an HP through `HangingProtocolSerializer` with an image set selector "Modality = CT" and one
"Rows = 512", save, then:

```bash
dcmdump hp_out.dcm | grep -E '0072,00(0c|10|14|22|24|26|28|38|50|62|7a)|0072,0108'
```

Expected inside each (0072,0022) item: (0072,0026) AT, (0072,0050) `CS` / `US`, (0072,0062) `CT`
or (0072,007A) 512. No (0008,0060) or (0028,0010) inside the item. (0072,0038) Relative Time is
**US**, (0072,0108) Display Environment Spatial Position is **FD** with 4 values. No (0072,0016) or
(0072,0340) anywhere. `dciodvfy hp_out.dcm` reports no HP module error. HP files written before
2026-09-18 are non-conformant and must be regenerated.

### C2. CAD SR (findings #56–#59) — Playground 4.4

Run `Playgrounds/4. Structured Reporting/4.4_CADSR.swift` to write a Mammography CAD SR with one
circle finding, then:

```bash
dcmdump cad.dcm | grep -E '111047|113878|0070,0022|0070,0023'
dicom-report cad.dcm --format text --output cad.txt
```

Expected: probability is coded (111047, DCM) "Probability of cancer"; manufacturer is a TEXT item
(113878, DCM); (0070,0023) `CIRCLE` with (0070,0022) holding **4** values `cx\cy\cx+r\cy`. Before:
3 values, and the extractor dropped every finding. Weasis or the OHIF SR panel draws the circle at
the right radius.

### C3. TID 1500 Measurement Report (finding #60) — Playground 4.3

Run `4.3_MeasurementReports.swift` adding a qualitative evaluation and a measurement group with
Finding = Tumor, Finding Site = Lung, then:

```bash
dcmdump tid1500.dcm | grep -B2 -A6 'C0034375'
dicom-report tid1500.dcm --format text --output tid1500.txt --include-measurements --include-findings
```

Expected: each evaluation CODE item inside the (C0034375, UMLS) container carries (0040,A043)
Concept Name Code Sequence; `dicom-report` lists the evaluations, and the group header shows
Finding and Finding Site. dcm4che `dsrdump` no longer warns about a missing concept name.

### C4. Waveform write (finding #20)

Build an ECG with a text annotation through `WaveformBuilder`, save, and confirm with A2's
`dcmdump` line that the text sits under (0070,0006), not (0040,A160).

## 5. Finding → test case index

| Findings | Test |
|---|---|
| #1–#13, #52, #53 | B `test_hangingProtocol…`, C1 |
| #14–#16, #61, LUT Explanation (2026-09-19) | B `test_enhancedMR_lutForm…`, `test_enhancedPET…`, `test_parametricMap…` |
| #17–#19 | B `test_rtPlan…`, `test_rtStruct…` |
| #20–#22 | A2, B `test_waveform…`, C4 |
| #23, #24 | A3, B `test_sr_mappingResource…` |
| #25, #26 | B `test_frameDimensionPointer…`, `test_enhancedMR_flatten…` |
| #27–#31, #50, #51 | A4 |
| Event Type ID (2026-09-19) | A5 |
| #47–#49 | A1 |
| #56–#60 | C2, C3 |
| MWL/MPPS/Q-R Phase 2 | Verification checklist rows 14–22 |
| Playground comment (2026-09-19) | open `Playgrounds/6. Advanced Topics/6.2_PresentationStates.swift`, Example 5 has no (0018,0060) line |
