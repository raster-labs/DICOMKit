# dicom-archive

Local DICOM file archive manager with JSON-based metadata indexing.

## Overview

`dicom-archive` manages a local archive of DICOM files, organizing them in a Patient/Study/Series directory hierarchy with a JSON metadata index. It supports importing, querying, exporting, and integrity checking of archived DICOM files with deduplication by SOP Instance UID.

## Features

- **Initialize**: Create a new archive with directory structure and metadata index
- **Import**: Import DICOM files with automatic metadata extraction and deduplication
- **Query**: Search archive metadata with wildcard pattern matching
- **List**: Display archive contents in tree, table, or JSON format
- **Export**: Export files from archive by study, series, or patient
- **Check**: Verify archive integrity (missing files, size mismatches, orphaned files)
- **Stats**: Display archive statistics including modality breakdown

## Usage

### Initialize an Archive

```bash
# Create a new archive
dicom-archive init --path /data/archive

# Overwrite an existing archive
dicom-archive init --path /data/archive --force
```

### Import DICOM Files

```bash
# Import individual files
dicom-archive import file1.dcm file2.dcm --archive /data/archive

# Import from a directory recursively
dicom-archive import /incoming/studies/ --archive /data/archive --recursive

# Import with verbose output, skipping duplicates
dicom-archive import /data/new/ --archive /data/archive --recursive --skip-duplicates --verbose
```

### Query Archive

```bash
# Search by patient name (wildcard matching)
dicom-archive query --archive /data/archive --patient-name "DOE*"

# Search by patient ID
dicom-archive query --archive /data/archive --patient-id "12345"

# Search by modality
dicom-archive query --archive /data/archive --modality CT

# Search by study date
dicom-archive query --archive /data/archive --study-date 20240101

# Combine filters with JSON output
dicom-archive query --archive /data/archive --patient-name "SMITH*" --modality MR --format json
```

### List Archive Contents

```bash
# Tree view (default)
dicom-archive list --archive /data/archive

# Table view
dicom-archive list --archive /data/archive --format table

# JSON output
dicom-archive list --archive /data/archive --format json

# Show individual instances
dicom-archive list --archive /data/archive --show-instances
```

### Export Files

```bash
# Export a study
dicom-archive export --archive /data/archive --study-uid 1.2.3.4.5 --output /tmp/export

# Export a series
dicom-archive export --archive /data/archive --series-uid 1.2.3.4.5.6 --output /tmp/export

# Export all files for a patient
dicom-archive export --archive /data/archive --patient-id "12345" --output /tmp/export

# Export with flattened directory structure
dicom-archive export --archive /data/archive --study-uid 1.2.3.4.5 --output /tmp/export --flatten
```

### Check Archive Integrity

```bash
# Basic integrity check
dicom-archive check --archive /data/archive

# Full check including DICOM file verification
dicom-archive check --archive /data/archive --verify-files --verbose
```

### Show Statistics

```bash
# Text statistics
dicom-archive stats --archive /data/archive

# JSON statistics
dicom-archive stats --archive /data/archive --format json
```

## Archive Structure

```
archive/
├── archive_index.json          # Metadata index (JSON)
└── data/
    └── PATIENT_ID/
        └── STUDY_UID/
            └── SERIES_UID/
                └── SOP_INSTANCE_UID.dcm
```

### Index File Format

The `archive_index.json` file contains:

- **version**: Archive format version
- **creationDate**: When the archive was created (ISO 8601)
- **lastModified**: When the archive was last modified (ISO 8601)
- **fileCount**: Total number of DICOM files
- **patients**: Array of patient records
  - **patientName**: Patient name
  - **patientID**: Patient ID (0010,0020)
  - **issuerOfPatientID**: Issuer of Patient ID (0010,0021), when the files carry it (patients are keyed on both)
  - **studies**: Array of study records
    - **studyInstanceUID**: Study Instance UID
    - **studyDate**: Study date (YYYYMMDD)
    - **studyDescription**: Study description
    - **modality**: Modality (0008,0060) of the first instance imported into the study (not Modalities in Study (0008,0061)). **Deprecated** study-level key: read `ModalitiesInStudy`
    - **ModalitiesInStudy**: Modalities in Study (0008,0061), PS3.6 2026a Table 6-1 keyword: the distinct series Modality values (written from 2026-10-01; indexes without it still load)
    - **series**: Array of series records
      - **seriesInstanceUID**: Series Instance UID
      - **modality**: Series modality
      - **seriesDescription**: Series description
      - **instances**: Array of instance records
        - **sopInstanceUID**: SOP Instance UID
        - **sopClassUID**: SOP Class UID
        - **filePath**: Relative path in archive
        - **fileSize**: File size in bytes
        - **importDate**: When the file was imported

## Wildcard Matching

`--patient-name` and `--patient-id` support the wild cards of PS3.4 C.2.2.2.4:

- `*` matches any number of characters
- `?` matches exactly one character

Patient's Name (0010,0010) matching is case-insensitive (PS3.4 C.2.2.2.4 leaves PN case handling
to the implementation); Patient ID (0010,0020) (LO) and Modality (CS) matching is case-sensitive, as
C.2.2.2.4 requires. `--study-uid` (and `export --study-uid / --series-uid`) take one UID or a
backslash-separated list (List of UID Matching, C.2.2.2.2). `--study-date` takes `YYYYMMDD` or a range
`YYYYMMDD-YYYYMMDD`, `-YYYYMMDD`, `YYYYMMDD-` (Range Matching, C.2.2.2.5.1); any other value gets a
warning and is compared as a literal string. `--modality` matches a study when any of its series has
that Modality (Modalities in Study (0008,0061)). Patients are keyed on Patient ID together with
Issuer of Patient ID (0010,0021); files without a Patient ID are also keyed on Patient's Name.

Examples:
- `DOE*` matches "DOE", "DOE^JOHN", "DOERING"
- `SM?TH` matches "SMITH", "SMYTH"
- `*BRAIN*` matches "CT BRAIN", "MR BRAIN SCAN"

## Deduplication

Files are deduplicated by SOP Instance UID. If a file with the same SOP Instance UID already exists in the archive, it will be skipped during import.

## Options Reference

### Init Command

- `--path, -p <path>`: Path for the new archive directory (required)
- `--force`: Overwrite existing archive

### Import Command

- `<files...>`: DICOM files or directories to import (required)
- `--archive, -a <path>`: Path to the archive (required)
- `--recursive`: Recursively import from directories
- `--skip-duplicates`: Skip duplicate SOP Instance UIDs without error
- `--verbose`: Verbose output

### Query Command

- `--archive, -a <path>`: Path to the archive (required)
- `--patient-name <pattern>`: Filter by Patient's Name (0010,0010) (wild cards)
- `--patient-id <pattern>`: Filter by Patient ID (0010,0020) (wild cards, case-sensitive)
- `--study-uid <uid>`: Filter by Study Instance UID (0020,000D) (one UID or a backslash-separated list)
- `--modality <modality>`: Filter by Modality (0008,0060) of any series in the study
- `--study-date <date>`: Filter by Study Date (0008,0020) (YYYYMMDD or a range)
- `--format, -f <format>`: Output format: table (default), json, text. JSON items carry the PS3.6 2026a Table 6-1 keywords `ModalitiesInStudy`, `NumberOfStudyRelatedSeries`, `NumberOfStudyRelatedInstances` (PS3.4 Table C.6-5); the former keys `modality`, `seriesCount`, `imageCount` keep their values and are **deprecated**

### List Command

- `--archive, -a <path>`: Path to the archive (required)
- `--format, -f <format>`: Output format: tree (default), table, json
- `--show-instances`: Show individual instances in tree view

### Export Command

- `--archive, -a <path>`: Path to the archive (required)
- `--output, -o <path>`: Output directory (required)
- `--study-uid <uid>`: Export by Study Instance UID (one UID or a backslash-separated list)
- `--series-uid <uid>`: Export by Series Instance UID (one UID or a backslash-separated list)
- `--patient-id <id>`: Export by Patient ID
- `--flatten`: Flatten output directory structure
- `--verbose`: Verbose output

### Check Command

- `--archive, -a <path>`: Path to the archive (required)
- `--verify-files`: Verify DICOM file readability
- `--verbose`: Verbose output

### Stats Command

- `--archive, -a <path>`: Path to the archive (required)
- `--format, -f <format>`: Output format: text (default), json

## Limitations

- Index is stored as JSON (not suitable for very large archives with millions of files)
- No concurrent access protection (single-user access assumed)
- Wildcard matching is case-insensitive for Patient's Name only
- File paths are sanitized (special characters replaced with underscores)

## See Also

- `dicom-info` - Display DICOM file metadata
- `dicom-dcmdir` - DICOMDIR management for media storage
- `dicom-dump` - Hexadecimal dump of DICOM files
- `dicom-validate` - Validate DICOM files

## References

- DICOM PS3.3 - Information Object Definitions
- DICOM PS3.10 - Media Storage and File Format
