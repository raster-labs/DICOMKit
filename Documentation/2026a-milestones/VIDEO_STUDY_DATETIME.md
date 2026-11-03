# Video Study Date and Time — 3 November 2026

This follow-up adds user-supplied study start values to `dicom-video` and
DICOMStudio's CLI Workshop. It is separate from the original 68-item ledger.
The starting source was `f8240927bf93efac5f1e1fa28823283edb517bd5` on
`codex/dicom-2026a-milestones`. PR #233 was already merged by the owner when this
follow-up began; these changes require a subsequent review. The agent does not
merge into main or enable auto-merge.

## Behavior

Previously, neither interface accepted Study Date/Time and the shared workflow
always wrote its conversion clock. Both `convert` and `batch` now accept:

| CLI / Workshop input | Output attribute | Validation |
| --- | --- | --- |
| `--study-date` / Study Date | `(0008,0020)` Study Date, DA | Real Gregorian date in `YYYYMMDD` form |
| `--study-time` / Study Time | `(0008,0030)` Study Time, TM | `HH`, `HHMM`, `HHMMSS`, or seconds with 1–6 fractional digits |

The fields are available in both Workshop experience modes, only for Convert
and Batch. Command previews use the CLI flag names. Both execution paths share
the same strict validators and metadata builder. Supplied dates/times are not
replaced by conversion time or shifted between time zones. Fractions are
serialized with six digits; partial hour/minute precision is retained.

Each field can be omitted independently. Its Type 2 attribute is then present
with zero length, including when a Study UID is supplied. **Compatibility change:**
omission no longer implies the conversion clock; callers needing a known study
start must supply it. Batch values apply to all instances in both series modes.
Content/Acquisition clock behavior is outside this follow-up and remains as before.

Invalid dates and times produce exit 1 before output is written, including
dry runs. Workshop batch destination resolution now follows validation so an
invalid value cannot create an output directory. Shared-workflow entry points
also reject invalid study values before reading batch inputs or building output.

## Verification

| Check | Result |
| --- | --- |
| Shared video workflow/round-trip suite | 64 passed |
| Video option/attribute suites | 35 passed |
| Workshop form suite | 23 passed |
| Actual Workshop executor regressions | 2 passed; exercise 12 successful convert/batch routes and 8 refusal cases |
| Audit regression controls | 58 passed |
| CLI process and independent DCMTK reads | 30 checks passed |
| Updated Studio CI verification script | Passed, including 23 Toolbox CLI cases, 22 Workshop CLI cases and 23 ViewModel actions |
| CLI build, workflow YAML and diff whitespace check | Passed |

The 124 Swift tests include encoded-file checks for literal tag numbers and
VRs, leap dates, partial/fractional times, independent omissions, explicit Study
UIDs, both series modes, and refusal without output. The Workshop executor tests
generate ISO-BMFF metadata in temporary files and read their DICOM output. The
independent CLI check generates real H.264 video using FFmpeg and inspects the
written attributes with DCMTK `dcmdump`, avoiding reliance only on self-round-trips.
All generated media is outside the repository; the CLI check deletes its media
on exit. Only text evidence is retained.

The existing tests did not cover Study Date/Time. During implementation, the new
Workshop tests exposed early destination-directory creation, which is repaired.
An initial test-only optional unwrap and an unsuitable zero-dimension transport
stream fixture were corrected before final verification; the passing executor
tests use generated MP4 metadata without bypassing validation.

No new native-window/UI automation, physical-device validation or full-package
suite is claimed. Workshop form bindings and its real execution path were tested
automatically. The Studio contracts CI script now selects the new Workshop, shared workflow and
attribute suites, with explicit expected-suite markers. Video-source changes also
trigger that workflow. Publication-head GitHub CI is a separate post-push gate. Historical
R4 print-timeout limitations and deferred Pages deployment remain unchanged.

See [verification receipt](video-study-datetime-verification.json),
[CLI usage and compatibility notes](../../Sources/dicom-video/README.md), and
the independent reproduction command:

```sh
python3 -B Scripts/verify_video_study_datetime.py --bin-dir .build/debug --report /tmp/video-study-check.json
```

Run from the repository root after building `dicom-video`; FFmpeg and DCMTK must
be on PATH. Swift regressions are selected by `VideoConsoleParityTests`,
`VideoOptionConformanceTests|VideoAttributeTests`, and
`CLIWorkshopVideoTests|WorkshopVideoStudyDateTimeTests` in their respective
`DICOMRoundTripTests`, `DICOMKitTests` and `DICOMStudioTests` products.

## Standard references

- [PS3.3 2026a C.7.2.1, General Study Module](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part03/sect_C.7.2.html): Study Date and Study Time describe when the study started and are Type 2 attributes.
- [PS3.5 2026a Table 6.2-1](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part05/sect_6.2.html): Gregorian DA and TM formats, precision and ranges.

The standard defines the attribute semantics, not a mandatory CLI or screen design.
