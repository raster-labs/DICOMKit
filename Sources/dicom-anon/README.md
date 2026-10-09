# dicom-anon

A command-line tool for anonymizing DICOM files to protect patient privacy.

## Features

- **Multiple Anonymization Profiles**:
  - **`ps315`** (the default; **`basic`** is an alias of it): the PS3.15 Basic Application Level
    Confidentiality Profile (every row of PS3.15 Table E.1-1) with the Options selected by the
    `--retain-*` / `--clean-*` flags; records Patient Identity Removed (0012,0062),
    De-identification Method (0012,0063) and De-identification Method Code Sequence (0012,0064)
  - **`legacy-basic`, `legacy-clinical-trial`, `legacy-research`** (deprecated): fixed attribute
    lists, **not** the PS3.15 Basic Profile and not any PS3.15 Profile + Options set; they record
    no (0012,0062). Each use prints a deprecation note on stderr

> **Changed 2026-10-01 (P-ANON-PROFILE):** the default profile is `ps315`, and `--profile basic`
> now means the PS3.15 Basic Profile. The attribute list `basic` used to select is
> `--profile legacy-basic`. `clinical-trial` and `research` are not PS3.15 profile names; they
> still select `legacy-clinical-trial` / `legacy-research`, with a deprecation note.
  - **Custom**: User-defined tag removal and replacement

- **Anonymization Actions**:
  - Remove tags entirely
  - Replace with empty values
  - Replace with dummy values (e.g., "ANONYMOUS")
  - Hash values for consistent pseudonymization (SHA-256)
  - Shift dates by random offset while preserving intervals
  - Regenerate UIDs while maintaining study/series relationships

- **Safety Features**:
  - Dry-run mode to preview changes without modifying files
  - Backup original files before anonymization
  - Audit logging for compliance and tracking
  - PHI leak detection in private tags
  - Batch processing with consistent pseudonyms

## Installation

Build from source:

```bash
swift build -c release --target dicom-anon
```

The executable will be available at `.build/release/dicom-anon`.

## Usage

### Basic Anonymization

```bash
# Anonymize a single file with the PS3.15 Basic Profile (the default; same as --profile ps315)
dicom-anon file.dcm --output anon.dcm

# Preview changes without modifying (dry-run)
dicom-anon file.dcm --dry-run
```

### Date Shifting

```bash
# Shift all dates by 100 days (Retain Longitudinal Temporal Information With Modified Dates Option)
dicom-anon file.dcm --output anon.dcm --retain-modified-dates --shift-dates 100
```

### UID Regeneration

```bash
# ps315 always replaces UIDs (Table E.1-1 action U), consistently across files.
# The deprecated legacy lists replace them only with --regenerate-uids:
dicom-anon file.dcm --output anon.dcm --profile legacy-basic --regenerate-uids
```

### Batch Processing

```bash
# Anonymize entire directory recursively
dicom-anon input_dir/ --output anon_dir/ --recursive

# With verbose output
dicom-anon input_dir/ --output anon_dir/ --recursive --verbose
```

### Custom Anonymization

```bash
# Remove specific tags
dicom-anon file.dcm --output anon.dcm --remove 0010,0010 --remove PatientID

# Replace specific tags with values
dicom-anon file.dcm --output anon.dcm --replace 0010,0030=19700101

# Keep specific tags from being anonymized (legacy lists only; with ps315 select a --retain-* Option)
dicom-anon file.dcm --output anon.dcm --profile legacy-basic --keep Modality --keep StudyDescription
```

### Audit Logging

```bash
# Generate audit log for compliance
dicom-anon file.dcm --output anon.dcm --audit-log anonymization.log

# Review audit log
cat anonymization.log
```

### Backup and Safety

```bash
# Create backup before anonymization
dicom-anon file.dcm --output anon.dcm --backup

# Force parsing of non-standard DICOM files
dicom-anon file.dcm --output anon.dcm --force
```

## Anonymization Profiles

### `ps315` (default; alias `basic`) — PS3.15 Basic Application Level Confidentiality Profile

Applies the Basic Profile action (D, Z, X, K, C, U) of every row of PS3.15 Table E.1-1, removes
private attributes, curve data and overlay data/comments, and replaces UIDs consistently. The
Options (PS3.15 E.3) and the PS3.16 CID 7050 code each one records in (0012,0064):

| Flag | PS3.15 E.3 Option | CID 7050 |
|---|---|---|
| (always) | Basic Application Level Confidentiality Profile | 113100 |
| `--clean-pixel-data` (all profiles) | Clean Pixel Data Option; sets Burned In Annotation (0028,0301) to NO | 113101 |
| `--clean-descriptors` | Clean Descriptors Option: descriptors are kept with every name component, identifier, address, age, UID and date the profile removes elsewhere (and a capitalised word after Dr/Mr/Mrs/Ms/Miss/Prof) taken out of their text (PS3.15 E.3.5) — review free text before release | 113105 |
| `--retain-full-dates`, or the deprecated `--retain-dates` | Retain Longitudinal Temporal Information With Full Dates Option | 113106 |
| `--retain-modified-dates --shift-dates N`, or the deprecated `--retain-dates --shift-dates N` | Retain Longitudinal Temporal Information With Modified Dates Option | 113107 |
| `--retain-characteristics` | Retain Patient Characteristics Option | 113108 |
| `--retain-device` | Retain Device Identity Option | 113109 |
| `--retain-uids` | Retain UIDs Option | 113110 |
| `--retain-institution` | Retain Institution Identity Option | 113112 |
| `--retain-safe-private` | Retain Safe Private Option: keeps the private attributes PS3.15 Table E.3.10-1 lists for their Private Creator, or that the file declares safe in Private Data Element Characteristics Sequence (0008,0300), with their Private Creators; applies a declared Deidentification Action (0008,0307); removes the rest (E.3.10) | 113111 |
| `--clean-graphics` | Clean Graphics Option: keeps Graphic Annotation Sequence (0070,0001) with the identifying information taken out of its text, as `--clean-descriptors` does; overlays are still removed (E.3.3) | 113103 |
| `--clean-structured-content` | Clean Structured Content Option: keeps Content Sequence (0040,A730) values (without it the Basic Profile "D" keeps the Content Items with their Text Value, numeric and table cell values replaced by dummies and Date/Time/DateTime/Person Name/UID by their own Table E.1-1 rows), Acquisition Context Sequence (0040,0555), Specimen Preparation Sequence (0040,0610) and Waveform Annotation Sequence (0040,B020) (Table E.1-1 "C"); each Content Item gets the action PS3.15 Table E.3.4-1 (211 rows; retired SRT / SNM3 / 99SDM codes of its SCT rows recognised) gives its Concept Name and Value Type under the Options in force: X removes the Content Item and its children, D replaces its value with a dummy, K keeps it, C cleans its text (as `--clean-descriptors`) or shifts its date (Modified Dates); the text kept is cleaned (E.3.4) | 113104 |
| `--clean-recognizable-visual-features --redact-region x,y,w,h ...` | Clean Recognizable Visual Features Option, operator-directed: the regions given are blanked on every frame, Icon Image Sequence removed, Recognizable Visual Features (0028,0302) set to NO (E.3.2). Without `--redact-region` the run is refused (exit 1): features are not detected automatically. Whether the regions prevent recognition, including in a 3D reconstruction of the series, is the operator's judgement | 113102 |

With `--clean-recognizable-visual-features`, `--redact-region` no longer implies
`--clean-pixel-data` (give both flags to claim both Options for the same regions).

The two Retain Longitudinal Temporal Information Options are mutually exclusive (E.3.6). The Option flags act only on `--profile
ps315` (they are refused with the legacy profiles), as do `--allow-burned-in-phi`; `--keep` is
refused with `ps315`. `--remove` and `--replace` are applied after the Profile.

`--retain-dates` is deprecated (P-ANON-RETAIN-DATES): it selects the Full Dates Option, or the
Modified Dates Option when `--shift-dates` is given, and prints a deprecation note. Use
`--retain-full-dates` or `--retain-modified-dates` (PS3.15 E.3.6, two mutually exclusive Options).

`--dry-run` and `--verbose` list each changed attribute with its PS3.6 name and the PS3.15
Table E.1-1a code; `--audit-log` writes the same list (without values).

```bash
dicom-anon file.dcm --output anon.dcm --profile ps315 --retain-modified-dates --shift-dates -100
```

### `legacy-basic` (deprecated; was `basic`)

Not the PS3.15 Basic Profile: of the 647 data-set rows of PS3.15 Table E.1-1 it handles 11.
Removes or replaces:
- Patient Name → "ANONYMOUS"
- Patient ID → Hashed value
- Patient Birth Date, Patient Birth Time → Removed
- Other Patient IDs, Other Patient Names, Patient Comments → Removed
- Referring Physician's Name, Performing Physician's Name, Operators' Name → Removed
- Institution Name/Address → Removed
- Station Name, Device Serial Number → Removed

### `legacy-clinical-trial` (deprecated; `clinical-trial` still selects it)

Not a PS3.15 profile. Includes the `legacy-basic` list plus:
- Study/Series/Acquisition Dates → Shifted by specified offset
- Study/Series/Acquisition Times → Removed
- Preserves intervals between dates

### `legacy-research` (deprecated; `research` still selects it)

Not a PS3.15 profile. Minimal anonymization:
- Patient Name → "ANONYMOUS"
- Patient ID → Hashed value
- Patient Birth Date → Removed
- Retains everything else

## Examples

### Example 1: PS3.15 Basic Profile

```bash
dicom-anon patient_scan.dcm --output anon_scan.dcm --profile ps315
```

Output:
```
Anonymization Summary:
  Total files: 1
  Successful: 1
  Failed: 0
```

### Example 2: Basic Profile with modified dates

```bash
dicom-anon study/ --output anon_study/ \
  --profile ps315 \
  --retain-modified-dates \
  --shift-dates 90 \
  --recursive \
  --audit-log trial_anon.log \
  --verbose
```

### Example 3: Custom Anonymization

```bash
dicom-anon research.dcm --output anon_research.dcm \
  --remove PatientName \
  --remove PatientID \
  --replace InstitutionName="Research Site"
```

## Security Considerations

1. **PHI Removal**: With `--profile ps315` the tool applies PS3.15 Annex E (which incorporates Supplement 142); the legacy profiles remove only their fixed attribute lists

2. **Private Tags**: Private tags are scanned for potential PHI and warnings are generated

3. **Burned-in Text**: Without `--clean-pixel-data` burned-in annotations in pixel data are not removed. With `--profile ps315`, a file whose Burned In Annotation (0028,0301) is YES or that has overlay planes is refused unless `--clean-pixel-data` or `--allow-burned-in-phi` is given.

4. **Audit Trail**: Always use `--audit-log` for compliance and tracking

5. **Verification**: Always verify anonymized files before distribution using:
   ```bash
   dicom-info anon.dcm --detailed
   ```

## PS3.15 Annex E (2026a)

`--profile ps315` implements the Basic Application Level Confidentiality Profile and the Options
in the table above. Longitudinal Temporal Information Modified (0028,0303) is recorded as REMOVED
without a Retain Longitudinal Temporal Information Option (PS3.15 E.2), UNMODIFIED with Full Dates
and MODIFIED with Modified Dates (E.3.6). With Modified Dates, DA values and the date part of DT
values are shifted by `--shift-dates` days and TM values are kept (a whole-day shift keeps every
interval).

## Exit Codes

- `0`: Success - all files anonymized successfully
- `1`: Failure - one or more files failed to anonymize

## Performance

- Single file anonymization: <100ms for typical files
- Batch processing: ~50-100 files/second
- Memory efficient: processes files individually

## Limitations

1. Burned-in text is removed only with `--clean-pixel-data` (region chosen automatically or by `--redact-region`)
2. The deprecated legacy-* profiles do not remove private tags (they generate warnings); `ps315` removes them
3. Sequence anonymization follows main dataset rules
4. Compressed transfer syntaxes are preserved without modification

## See Also

- `dicom-info`: Display DICOM file information
- `dicom-validate`: Validate DICOM file conformance
- `dicom-convert`: Convert DICOM transfer syntaxes

## References

- DICOM Standard PS3.15 - Security and System Management Profiles
- DICOM Supplement 142 - Clinical Trial De-identification Profiles
- HIPAA Privacy Rule - De-identification of Protected Health Information

## License

Part of DICOMKit - See LICENSE file for details.
