# dicom-tags

A command-line tool for adding, modifying, and deleting tags in DICOM files.

## Features

- **Set Tag Values**: Add or update tags by keyword or hex code; the value is written with the PS3.6 VR and checked against PS3.5 Table 6.2-1
- **Delete Tags**: Remove specific tags from DICOM files
- **Delete Private Tags**: Strip all private (odd group) tags in one operation
- **Copy Tags**: Copy tags from one DICOM file to another
- **Dry Run**: Preview changes without writing to disk
- **Flexible Tag Formats**: Specify tags by PS3.6 keyword (exact case, e.g., `PatientName`) or hex (e.g., `0010,0010`)

## Installation

Build from source:

```bash
swift build -c release --target dicom-tags
```

The executable will be available at `.build/release/dicom-tags`.

## Usage

### Set Tag Values

```bash
# Set a tag by name
dicom-tags file.dcm --set PatientName=DOE^JOHN

# Set a tag by hex code
dicom-tags file.dcm --set 0010,0010=DOE^JOHN

# Set multiple tags
dicom-tags file.dcm --set PatientName=DOE^JOHN --set StudyDescription=Research

# Write to a different output file
dicom-tags file.dcm --set PatientName=DOE^JOHN --output modified.dcm
```

### Delete Tags

```bash
# Delete a tag by name
dicom-tags file.dcm --delete PatientBirthDate

# Delete multiple tags
dicom-tags file.dcm --delete PatientBirthDate --delete AccessionNumber

# Delete by hex code
dicom-tags file.dcm --delete 0010,0030
```

### Delete Private Tags

```bash
# Remove all private tags (odd group numbers)
dicom-tags file.dcm --delete-private --output clean.dcm
```

### Copy Tags Between Files

```bash
# Copy specific tags from another file
dicom-tags target.dcm --copy-from source.dcm --tags PatientName,PatientID

# Copy all tags from another file
dicom-tags target.dcm --copy-from source.dcm --output merged.dcm
```

### Dry Run

```bash
# Preview changes without writing
dicom-tags file.dcm --set StudyDescription=Research --delete AccessionNumber --dry-run

# Combine with verbose for detailed output
dicom-tags file.dcm --delete-private --dry-run --verbose
```

### Combined Operations

```bash
# Set, delete, and strip private tags in one pass
dicom-tags file.dcm \
  --set PatientName=ANONYMOUS \
  --delete PatientBirthDate \
  --delete-private \
  --output cleaned.dcm \
  --verbose
```

## Value Rules (DICOM 2026a)

- `--set` writes the VR of the PS3.6 data dictionary (for a tag with two dictionary VRs, such as
  "US or SS", the element's current VR when it is one of them). Private Creator elements
  (gggg,0010-00FF) are LO (PS3.5 7.8.1); other private tags keep their VR, else LO.
- Every value must fit PS3.5 Table 6.2-1 for that VR: e.g. DA is exactly 8 digits (`20200101`),
  CS is upper case, digits, space or `_`, at most 16 bytes; LO at most 64 characters; PN at most
  64 characters per component group. Multiple values are separated by `\` (except LT, ST, UT, UR).
- US, SS, UL, SL, FL and FD values are decimal numbers (`--set Rows=512`), range-checked.
  AT, OB, OD, OF, OL, OV, OW, SQ, SV, UV and UN cannot be set from text.
- File Meta Information (group 0002) cannot be set, deleted or copied: PS3.10 7.1 keeps group
  0002 out of the Data Set, and the file writer sets it. Item/delimiter tags (FFFE,xxxx) and the
  unused groups 0001, 0003, 0005, 0007, FFFF are refused too.
- A refused edit stops the run before anything is written (exit code 1).

## Example Keywords

| Name | Tag | VR |
|------|-----|-----|
| PatientName | (0010,0010) | PN |
| PatientID | (0010,0020) | LO |
| PatientBirthDate | (0010,0030) | DA |
| PatientSex | (0010,0040) | CS |
| PatientAge | (0010,1010) | AS |
| StudyDate | (0008,0020) | DA |
| StudyTime | (0008,0030) | TM |
| StudyDescription | (0008,1030) | LO |
| StudyInstanceUID | (0020,000D) | UI |
| AccessionNumber | (0008,0050) | SH |
| ReferringPhysicianName | (0008,0090) | PN |
| SeriesDate | (0008,0021) | DA |
| SeriesDescription | (0008,103E) | LO |
| SeriesInstanceUID | (0020,000E) | UI |
| Modality | (0008,0060) | CS |
| InstitutionName | (0008,0080) | LO |
| SOPInstanceUID | (0008,0018) | UI |

Any keyword of PS3.6 Table 6-1 works (exact case); a tag can always be given by hex code (e.g., `0008,0050`).

## Exit Codes

- `0`: Success
- `1`: Failure (file not found, no operation given, a value or tag refused by the rules above, write error, etc.)
- `64`: Usage error (missing input file, unknown option)

## See Also

- `dicom-anon`: Anonymize DICOM files with privacy profiles
- `dicom-info`: Display DICOM file information
- `dicom-dump`: Hex dump of DICOM file contents
- `dicom-validate`: Validate DICOM file conformance

## License

Part of DICOMKit — See LICENSE file for details.
