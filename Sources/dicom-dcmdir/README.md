# dicom-dcmdir

DICOMDIR management tool for creating, validating, and managing DICOM media storage directories.

## Overview

`dicom-dcmdir` is a command-line utility for working with DICOMDIR files, which are special DICOM files that provide an index of all DICOM files on removable media (CD, DVD, USB). DICOMDIR files enable efficient browsing of medical images without reading all files individually.

## Features

- **Create DICOMDIR**: Generate DICOMDIR from directories of DICOM files
- **Validate**: Verify DICOMDIR structure and integrity
- **Dump**: Display DICOMDIR contents in various formats (tree, JSON, text)
- **Update**: Add new files to existing DICOMDIR (planned)

## Usage

### Create a DICOMDIR

Create a DICOMDIR from a directory containing DICOM files:

```bash
# Basic creation
dicom-dcmdir create study_folder/ --output DICOMDIR

# With custom file-set ID and profile
dicom-dcmdir create study_folder/ \
  --output DICOMDIR \
  --file-set-id "MYSTUDY" \
  --profile STD-GEN-DVD-JPEG

# Strict mode (only include valid DICOM files)
dicom-dcmdir create study_folder/ --output DICOMDIR --strict --verbose

# Files named like img1.dcm: copy them into a new File-set with assigned File IDs
dicom-dcmdir create study_folder/ --copy-to media/
```

### Validate a DICOMDIR

Verify the structure and integrity of a DICOMDIR file:

```bash
# Basic validation
dicom-dcmdir validate DICOMDIR

# Detailed validation with file existence checks
dicom-dcmdir validate /media/cdrom/DICOMDIR --check-files --detailed
```

### Display DICOMDIR Structure

View the contents of a DICOMDIR in various formats:

```bash
# Tree format (default)
dicom-dcmdir dump DICOMDIR

# JSON format
dicom-dcmdir dump DICOMDIR --format json

# Text format with verbose output
dicom-dcmdir dump DICOMDIR --format text --verbose
```

## Options

### Create Command

- `--output, -o <path>`: Output DICOMDIR path (default: DICOMDIR in input directory)
- `--file-set-id <id>`: File-set ID (0004,1130), up to 16 characters A-Z, 0-9, _ (PS3.10 8.1, 8.5); a value outside these rules is refused with exit 1 (it was written with a warning before 2026-10-01) (default: the directory name upper-cased, other characters replaced by `_`, cut to 16)
- `--profile <profile>`: PS3.11 Application Profile identifier (default STD-GEN-CD; e.g. STD-GEN-DVD-JPEG, STD-GEN-USB-JPEG). The deprecated spellings STD-GEN-DVD, STD-GEN-USB, STD-GEN-SEC, STD-CTMR-XXXX and STD-US-XXXX are not PS3.11 identifiers; they are still accepted, print a stderr warning, and write STD-GEN-DVD-JPEG, STD-GEN-USB-JPEG, STD-GEN-SEC-CD, STD-CTMR-CD and STD-US-ID-SF-CDR respectively
- `--copy-to <folder>`: Copy every accepted file into a new File-set in `<folder>` under File IDs the tool assigns, `DICOM\PTnnnnnn\STnnnnnn\SEnnnnnn\IMnnnnnn` (PS3.10 8.2, 8.5), and write `<folder>/DICOMDIR`. Without it the files are indexed where they are, and a file whose path relative to the input directory is not a PS3.10 File ID (e.g. `img1.dcm`) is refused
- `--recursive`: Recursively scan subdirectories (default: true)
- `--strict`: Include only valid DICOM files
- `--verbose`: Verbose output showing progress

### Validate Command

- `--check-files`: Verify that every Referenced File ID (0004,1500) names a file in the File-set (PS3.10 8.6)

`validate` also checks the File-set ID (PS3.10 8.1, 8.5) and every Referenced File ID (at most 8 components of 1 to 8 characters A-Z, 0-9, _; PS3.10 8.2, 8.5; each File referenced by at most one record, PS3.3 Table F.3-3) and names the clause each failure breaks. `create` refuses (lists in the summary, and exits 1 when nothing is left) a file whose path relative to the input directory is not a valid File ID (name the files e.g. `DIR00001/IMG00001`, or use `--copy-to`), a SOP Class or Transfer Syntax the chosen profile's PS3.11 table does not list (e.g. STD-GEN-CD: Explicit VR Little Endian only, Table D.3-1; -JPEG profiles add JPEG Lossless SV1 / Baseline / Extended, -J2K profiles JPEG 2000, Tables H.3-1, J.3-1, M.3-1), a second file with an already indexed SOP Instance UID, an instance that breaks the profile's image attribute values (e.g. STD-XA1K Rows / Columns up to 1024, STD-CTMR High Bit = Bits Stored - 1, STD-US Photometric Interpretation / Transfer Syntax pairs; PS3.11 Tables A.3-3, B.3-3, B.3-4, C.3-2, E.3-3 to E.3-6, K.3-3, K.3-4, L.4-1, L.4-2), an MPEG instance without Number of Frames, a SOP Class PS3.3 gives no Directory Record Type (Procedure Protocol, Protocol Approval) and an instance without a Type 1 key of its record (e.g. an SR without Completion Flag). Every instance gets its own record, of the type PS3.3 F.5 gives its SOP Class (IMAGE, SR DOCUMENT, KEY OBJECT DOC, PRESENTATION, WAVEFORM, ENCAP DOC, RT DOSE, …; HANGING PROTOCOL, PALETTE, IMPLANT and INVENTORY at the root) with that record's Type 1 / 2 keys (Tables F.5-1 to F.5-49). A STUDY without Study ID gets its ordinal, a SERIES without Series Number and a record without Instance Number theirs; a missing Study Date / Time comes from the Series, Acquisition or Content Date / Time, else 19000101 / 000000 (PS3.11 D.3.3.1: the File-set Creator supplies them). The profile's "Additional DICOMDIR Keys" are added too (PS3.11 Tables A.3-2, B.3-2, D.3-2, E.3-2, H.3-2, I.3-2; USB / flash, BD and BD-MPEG4 profiles use H.3-2): e.g. Patient's Birth Date / Sex, Institution Name / Address and Performing Physicians' Name, Rows / Columns, Image Position / Orientation, Frame of Reference UID and Pixel Spacing; STD-XABC-CD and STD-XA1K IMAGE records get a 128 x 128 8-bit MONOCHROME2 Icon Image Sequence (A.3.3.2, B.3.3.2, PS3.3 F.7), copied from the instance when it carries a conforming one, else made from its pixels. An instance whose required key cannot be supplied (an icon from pixels that cannot be decoded, no Rows, an XA Image Type of BIPLANE A / B without Referenced Image Sequence) is refused.
- `--detailed`: Show detailed validation output including record statistics

### Dump Command

- `--format, -f <format>`: Output format (tree, json, text)
- `--verbose`: Show all attributes for each record

## Application Profiles

The tool supports standard DICOM application profiles:

- **STD-GEN-CD**: General Purpose CD-R Interchange (default; PS3.11 Table D.1-1)
- **STD-GEN-DVD-JPEG** / **STD-GEN-DVD-J2K**: General Purpose DVD Interchange with JPEG / JPEG 2000 (Table H.1-1)
- **STD-GEN-USB-JPEG** / **STD-GEN-USB-J2K**: General Purpose USB Media Interchange with JPEG / JPEG-2000 (Table J.1-1)
- every other identifier of PS3.11 2026a Annexes A-N (`dicom-dcmdir create --help` and the error text list them)

## Examples

### Creating a DICOMDIR for CD Distribution

```bash
# Prepare directory with DICOM files
cd /path/to/study

# Create DICOMDIR with CD profile
dicom-dcmdir create . --profile STD-GEN-CD --verbose

# Validate the created DICOMDIR
dicom-dcmdir validate DICOMDIR --detailed

# View the structure
dicom-dcmdir dump DICOMDIR --format tree
```

### Validating a DICOMDIR from Mounted Media

```bash
# Mount CD/DVD
# (e.g., /media/cdrom or /Volumes/DICOM_CD)

# Validate the DICOMDIR
dicom-dcmdir validate /media/cdrom/DICOMDIR --check-files

# Display contents
dicom-dcmdir dump /media/cdrom/DICOMDIR
```

## DICOMDIR Structure

A DICOMDIR file contains a hierarchical directory structure:

```
DICOMDIR
├── PATIENT (Patient Name, ID)
│   └── STUDY (Study Date, Description)
│       └── SERIES (Modality, Series Description)
│           └── IMAGE (Instance Number, File Path)
```

Each record contains DICOM attributes relevant to that level of the hierarchy.

## Technical Details

### File-set ID

The File-set ID (0004,1130) is a short human-readable label for the File-set (PS3.10 8.1, PS3.3 Table F.3-2):
- 0 to 16 characters
- Uppercase letters (A-Z), digits (0-9) and underscore only; SPACE is not allowed (PS3.10 8.5)
- Not necessarily unique; the File-set UID identifies the File-set

### Referenced File Paths

File IDs in DICOMDIR are stored in Referenced File ID (0004,1500) as components relative to the DICOMDIR location: 1 to 8 components, each 1 to 8 characters from A-Z, 0-9 and _ (PS3.10 8.2, 8.5). For example:
- `["PATIENT1", "STUDY1", "SERIES1", "IMG00001"]`
- Represents: `PATIENT1/STUDY1/SERIES1/IMG00001`

### Consistency Flag

File-set Consistency Flag (0004,1212) is written as 0000H. PS3.3 2026a Table F.3-3: "The Value FFFFH shall never be present."

## Limitations

- **Extract command** is not yet implemented
- PRIVATE directory records of an existing DICOMDIR are read and kept where its offsets place them (dump, validate); `create` and `update` index instances only and write no PRIVATE records
- Icon images are written only where the profile requires them (STD-XABC-CD, STD-XA1K); the optional STD-CTMR icons (E.3.3.3) are copied from the instance, never generated

## See Also

- `dicom-info` - Display DICOM file metadata
- `dicom-dump` - Hexadecimal dump of DICOM files
- `dicom-validate` - Validate DICOM files

## References

- DICOM PS3.3 Annex F - Basic Directory IOD (Table F.4-1 record types, F.5 directory records)
- DICOM PS3.4 Annex I - Media Storage Service Class (Media Storage Directory Storage, 1.2.840.10008.1.3.10)
- DICOM PS3.10 Section 8 - DICOM File Service (File-set, File IDs, character set, DICOMDIR)
- DICOM PS3.11 - Media Storage Application Profiles
