# DICOM Tag Audit — End-User Verification Checklist

Companion to `DICOM_TAG_AUDIT_FINDINGS.md` §G/§H. Each row is something a user can see through
DICOM Studio or a `dicom-*` CLI, with the behaviour that changed and how to confirm it. Rows are
ordered by how likely a real deployment is to hit them.

Test data: use a file that actually carries the attribute in question — synthetic files made
with the CLI itself are fine for "written correctly" checks, but "read correctly" checks need a
file from another vendor/toolkit (dcm4che, DCMTK `dcmodify`, pydicom) so the old wrong tag cannot
mask the result.

| # | Surface | What changed | How to verify | Expect |
|---|---|---|---|---|
| 1 | **DICOM Studio → Inspector / Metadata**, `dicom-dump`, `dicom-info`, `dicom-tags` | Overlay (60xx) and Curve (50xx) attributes now have dictionary names and VRs | Open any file with an overlay plane (e.g. a CR/DX with burned-in overlay, or add one with `dcmodify -i "(6000,0010)=512"`) | (6000,0010) shows **Overlay Rows US**, (6000,3000) **Overlay Data OW** — not "Unknown"/UN. Odd groups (6001,xxxx) still show as private |
| 2 | **Studio Inspector**, `dicom-dump`, `dicom-validate` | Multi-VR attributes keep both VRs; Extended Offset Table is OV | Open a multi-frame file with (7FE0,0001) (HTJ2K / any file written with an extended offset table), and a file whose LUT Data (0028,3006) is OW | Inspector shows VR **OV** for (7FE0,0001); `dicom-validate` gives **no** "Unexpected VR OW for (0028,3006)" warning (expected list reads `US or OW`) |
| 3 | **Implicit VR Little Endian files** in any tool | VR for overlay/curve/OV tags is now inferred from the dictionary | `dicom-convert` an explicit-VR file with overlays to Implicit VR LE, then `dicom-dump` the result | Overlay attributes decode with the right VR (US/OW) instead of UN; round-trip back to explicit VR is byte-identical for those elements |
| 4 | **Studio → Waveform viewer**, `dicom-info` on ECG files | Waveform annotation text is written to (0070,0006) Unformatted Text Value; (0040,A160) still read | (a) Create an ECG with a text annotation via the API/Workshop and inspect: text is under (0070,0006) inside (0040,B020). (b) Open an ECG saved by an **older** DICOMKit build (annotation under (0040,A160)) | (a) Correct tag, and dcm4che/DCMTK readers now show the annotation. (b) Annotation text still displays |
| 5 | **Studio → Presentation State (GSPS) text annotations** | No behaviour change intended — same fallback as before, constant renamed | Open a GSPS with text objects saved by the current and by an older build | Text renders in both |
| 6 | **Studio → Parametric Map / RWV display**, `dicom-image` measurements on Enhanced CT/MR/PET | LUT-form Real World Value mappings now parse; FD first/last no longer swapped | Open an Enhanced image whose RWV Mapping Sequence uses **LUT Data** (0040,9212) rather than slope/intercept (PET SUV maps from GE/Siemens, or a pydicom-built test file) | Real-world value / units appear in the pixel probe and measurements; previously the mapping was silently absent (fell back to rescale) |
| 7 | **Hanging Protocols** (Studio hanging-protocol import / any HP file written by DICOMKit) | Tags in group 0072 corrected; US attributes now parsed | (a) Import a vendor HP object (or one made with dcm4che) → matcher recognises modality/laterality/number of priors. (b) Export an HP from DICOMKit and `dcmdump` it | (a) Fields populated (before: all nil). (b) (0072,0014) Number of Priors, (0072,000C) Definition Sequence, (0072,0022) Image Set Selector Sequence, (0072,0026) Selector Attribute — no (0072,0016)/(0072,0340) tags. **HP files written by older DICOMKit builds are non-conformant and must be regenerated** |
| 8 | **RT Plan** viewers / `dicom-info` on brachy plans | Application Setup Number ↔ Type swapped | Open an RT Plan with an Application Setup Sequence | Setup *number* is numeric, *type* is e.g. `FLETCHER_SUIT`/`SYED_NEBLETT` — not reversed |
| 9 | **Enhanced MR → legacy flattening** (`dicom-convert --split-frames` / Studio export of Enhanced MR) | Segmented k-Space Traversal read from (0018,9033) | Flatten an Enhanced MR with (0018,9033) present | Output legacy MR images carry the traversal value (before: always missing) |
| 10 | **Studio → CLI Workshop → UPS-RS panel**, `dicom-wado ups` | Workitem JSON keys corrected (Human Performer Code Seq/Organization, Retrieve URI, Discontinuation Reason, Contact URI/Display Name); tag-name labels in the JSON viewer corrected | Against a real UPS-RS server (dcm4chee-arc): create a workitem with a scheduled human performer *organisation*, an input instance with a *Retrieve URI*, then cancel it with contact name/URI | Server accepts without VR errors; `GET` of the workitem shows (0040,4036) Human Performer's Organization = your text, (0040,E010) Retrieve URI populated; cancellation shows (0074,100C)/(0074,100A). Workshop labels read *Human Performer's Organization*, *Requesting AE*, *Contact URI* for the right keys |
| 11 | `dicom-wado ups --search`, Studio UPS query | Station filters send the code-sequence attribute (unchanged bytes, renamed API) | Run a UPS search filtered by scheduled station | Same results as before |
| 12 | `dicom-anon` | `operatorsName` rename only | Anonymise a file with (0008,1070) Operators' Name | Attribute removed, as before |
| 13 | `dicom-ai`, Studio AI output | Presentation-state label constants renamed to `contentLabel`… (same tags) | Generate an AI-enhanced output with a presentation state | (0070,0080)/(0070,0081)/(0070,0084) present as before |
| 14 | `dicom-mwl`, Studio Workshop MWL | Regression check of the original bug (no change in this batch) | Query a worklist SCP with `--patient "*"` | **Requested Procedure Description** column populated from (0032,1060) |
| 15 | **Any tool reading an SR** | No tag change; `mappingResourceUID/Name` constants fixed but unused | Open a complex SR (TID 1500) | Unchanged rendering |

## Phase 2 additions (key-set conformance) — 2026-09-18

| # | Surface | What changed | How to verify | Expect |
|---|---|---|---|---|
| 16 | `dicom-mpps update`, Studio Workshop MPPS | Referenced SOP Class UID is the real class; Protocol Name always present | `dicom-mpps update … --status COMPLETED --study-uid … --series-uid … --image-uid … --sop-class-uid 1.2.840.10008.5.1.4.1.1.2 --protocol-name "Chest CT"` against dcm4chee-arc / Orthanc; then inspect the MPPS on the server | Accepted; Performed Series item shows CT Image Storage and Protocol Name. Omitting `--sop-class-uid` prints a stderr warning and still sends SC (unchanged behaviour). |
| 17 | `dicom-mpps update` | N-SET no longer carries Scheduled Step Attributes Sequence | Complete a step against a strict SCP (dcm4chee-arc) and against Orthanc | dcm4chee accepts. If Orthanc rejects, re-run with `--legacy-nset-scheduled-attributes` and tell me — that decides whether the flag stays. |
| 18 | `dicom-mpps create` | Type 2 attributes now sent (empty when unknown); Requested Procedure ID no longer copied from the PPS ID | Create with `--modality CT --patient-birth-date … --patient-sex F --requested-procedure-id RP1 --procedure-step-id PPS1` | Server shows (0040,1001)=RP1 and (0040,0253)=PPS1 — previously both were PPS1. No 0x0107/0x0120 warnings from strict SCPs about Performing Physician / Study UID at root. |
| 19 | `dicom-mwl`, Studio Workshop MWL | Non-ASCII patient names | Query a worklist containing a Latin-1 or UTF-8 (ISO_IR 192) patient name | Name displays correctly; previously the row showed no Patient Name at all. |
| 20 | `dicom-mwl` (table + `--json`) | New columns: Requested Proc. Code, Protocol Code, Priority, Contrast Agent, Weight, Allergies, Medical Alerts, Admission ID, Referenced Study … | Query a RIS worklist that fills these (most do) | Values appear; JSON gains `RequestedProcedureCode`, `ScheduledProtocolCodes`, `PatientWeight`, … keys (existing keys unchanged). |
| 21 | `dicom-query --level series` without `--study-uid` | Local validation | Run it | Immediate `--level series requires --study-uid (PS3.4 C.4.1.2.1 …)` — no connection, no server 0xA900. |
| 22 | `dicom-query`, Studio Q/R | Duplicate identifier elements removed | `dicom-query … --level study --patient-id P1` with `dicom-dump`-level capture (or a PACS log) | The C-FIND identifier carries a single (0010,0020) element. |
| 23 | `dicom-server` / Studio Workshop DICOMweb (QIDO-RS) | Required matching keys honoured, hex-tag form accepted, Retrieve URL etc. returned | `curl 'http://host/dicom-web/studies?StudyDate=20240101-20240131'` and `…?0020000D=<uid>`; OHIF / Weasis pointed at the server | Date filter narrows results (before: returned everything); hex form works; study rows show Retrieve URL (0008,1190), Study ID, Referring Physician, Birth Date/Sex; viewers that key on Retrieve URL now open instances. |
| 24 | `dicom-wado qido` / Studio DICOMweb | Series-level PPS Start Time and Request Attributes | Search series on a server that fills (0040,0275) (dcm4chee-arc) | New columns/JSON fields populated. |
| 25 | `dicom-print` with a Presentation LUT | Optional Illumination / Reflected Ambient Light | Only if you set them (API/config) | Printer receives (2010,015E)/(2010,0160) in the Film Box; unset = unchanged. |

## Phase 3 additions (selector values, SR extractors, parametric maps) — 2026-09-18

| # | Surface | What changed | How to verify | Expect |
|---|---|---|---|---|
| 26 | **Studio → Hanging Protocol panel** (export), any HP file written by DICOMKit | Selector values now live in Selector Attribute VR (0072,0050) + Selector *xx* Value (0072,005E–0083), not under the selected attribute's own tag | Create an HP with an image set selector "Modality = CT" and one with "Rows = 512", export, `dcmdump` the file (or open it in Studio Inspector) | Inside each (0072,0022) item: (0072,0026) Selector Attribute, (0072,0050) = `CS` / `US`, (0072,0062) Selector CS Value = `CT` / (0072,007A) Selector US Value = 512. **No** (0008,0060) or (0028,0010) inside the item. `dcm4che`/`dciodvfy` report no HP conformance error |
| 27 | **Studio → Hanging Protocol panel** (import) | Reads vendor HP objects and DICOMKit's old layout | (a) Import an HP written by another toolkit (dcm4che `HangingProtocol` sample or a vendor object). (b) Import an HP exported by a DICOMKit build **before** this change | (a) Selector values appear and the matcher picks the right series. (b) Still imports; values shown. Re-export it once so the file becomes conformant |
| 28 | **Studio → Structured Report view → CAD findings list**, `dicom-report` on CAD SRs | Findings, probability and manufacturer now extracted (before: the list was always empty) | Open a Mammography CAD SR or Chest CAD SR produced by DICOMKit, and one from a real CAD vendor (iCAD, Hologic, Siemens, or the dcm4che sample set) | Each finding listed with its type (Mass / Calcification / Nodule), probability, and location. Algorithm name, version **and manufacturer** shown |
| 29 | CAD SR **written** by DICOMKit (API / Studio) | CIRCLE regions encoded per PS3.3 C.18.6.1.2 (centre + circumference point) | Create a CAD finding with a circle ROI, save, `dcmdump` | (0070,0022) Graphic Data has **4** values `cx\cy\cx+r\cy` (before: 3). Third-party viewers (Weasis, OHIF SR panel) draw the circle at the right radius |
| 30 | **Studio → Structured Report view**, `dicom-report` on TID 1500 Measurement Reports | Qualitative evaluations extracted; Finding / Finding Site per measurement group | Open a TID 1500 report with a Qualitative Evaluations container (QIICR / dcmqi sample reports) and a group with Finding = Tumor, Finding Site = Lung | Evaluations listed (before: none); group header shows Finding and Site |
| 31 | Measurement report **written** by DICOMKit (API) | Qualitative evaluations keep their concept name; measurement groups accept a finding and site | Build a report via `MeasurementReportBuilder.addQualitativeEvaluation(conceptName:value:)` and `addMeasurementGroup(…, finding:, findingSite:)`, save, `dcmdump` | Each evaluation CODE item carries (0040,A043) Concept Name Code Sequence; dcm4che `sr2html`/`dsrdump` no longer warn about a missing concept name |
| 32 | **Studio → Specialized modality → Parametric Map**, RWV display | Linear Real World Value mappings now parse (slope/intercept read as FD) | Open a Parametric Map object (T1/ADC map from Siemens/GE, or a dcmqi-generated `pmap`) whose RWV mapping uses slope + intercept | Quantity, units, slope and intercept shown; pixel probe gives real-world values. Before: mapping list empty, probe showed stored values only |
| 33 | Regression: every previously silent test suite | `ParametricMap`, `RadiationTherapy`, `Segmentation`, `StructuredReporting`, `Waveform` and three `HangingProtocol` suites now run in CI | `swift test --filter DICOMKitTests` | 0 failures; CI green |

## Compatibility notes worth telling users

- **Hanging Protocol files** and **waveform annotation text** written by DICOMKit before this
  change were non-conformant. Waveforms still read back (fallback). HP files do **not** —
  regenerate them.
- Deprecated names (`thermalIndex`, `operatorName`, `presentationLabel`, `selectorSequence`,
  `hangingProtocolEnvironmentSequence`, `textObjectUnformattedTextValue`, `UPSQueryAttribute.
  scheduledStationName`, …) still compile with a warning and forward to the correct tag.
- Four never-valid Hanging Protocol names are now `unavailable` (compile error with the correct
  replacement in the message).

## Not covered

Phase 2 (per-service key sets) is done — see `DICOM_TAG_AUDIT_PHASE2_FINDINGS.md` §7. Phase 3 of
the findings doc (§J, 2026-09-18) closed the Hanging Protocol Selector Attribute Value encoding
and enabled every previously excluded DICOMKitTests suite. Still open, all optional or
guardrail-level, from `DICOM_TAG_ATTRIBUTE_AUDIT_PLAN.md`:

- Phase 2 optional items P14 (request Available Transfer Syntax UID in Q/R), P16 (expose
  Retrieve AE Title from Storage Commitment), P19 (confirm/document Pixel Aspect Ratio handling
  in Print).
- Phase 3 structural checks not yet done as a pass of their own: SCP-side responses
  (`dicom-server`, `dicom-printscp`, Workshop MWL/MPPS SCPs) carrying every requested Type 1/2
  attribute, keyword-based APIs (`lookup(keyword:)`, QIDO `includefield`, CLI `--tag`) spelled
  exactly as PS3.6, QIDO `includefield`.
- Phase 4.4 golden fixtures (one anonymised real-world MWL/MPPS/Q-R response per service).
- Phase 5: the bare-`Tag(group:element:)` lint outside `Tag+*.swift`, and the ~478 bare-hex tag
  lines (mostly `PrintService.swift`, `PrintSCPEncoder.swift`, `StorageService.swift`) that
  still carry no keyword comment, so the audit script cannot check them.
- Phase 6: GitHub issues per finding and `Docs/audit/README.md`.
