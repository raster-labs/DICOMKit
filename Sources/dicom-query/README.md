# dicom-query

Query DICOM servers using C-FIND and QIDO-RS protocols.

## Overview

`dicom-query` is a command-line tool for querying DICOM PACS servers to find patients, studies, series, and instances. It supports the standard DICOM C-FIND service over TCP/IP and provides multiple output formats for different use cases.

## Features

- **Multiple Query Levels**: Patient, Study, Series, and Instance queries
- **Flexible Filters**: Filter by patient name, ID, study date, modality, and more
- **Multiple Output Formats**: Table (default), JSON, CSV, compact, and DICOM JSON (PS3.18 F.2) formats
- **Wildcard Support**: Use * and ? in patient names and descriptions
- **Date Range Queries**: Query by date ranges (e.g., 20240101-20240131)
- **PACS Protocol**: Standard DICOM C-FIND over TCP/IP

## Installation

Build from source:

```bash
swift build -c release --target dicom-query
```

The executable will be available at:
`.build/release/dicom-query`

## Usage

### Basic Syntax

```bash
dicom-query <url> --aet <calling-ae> [options]
```

### URL Format

- **PACS (C-FIND)**: `pacs://hostname:port`
  - Default port: 104 (if not specified)
  
### Required Options

- `--aet <string>`: Your Application Entity Title (calling AE)

### Query Level Options

- `--level <level>`: Query/Retrieve Level (0008,0052) (default: study). The values are those of
  PS3.4 Tables C.6.1-1 / C.6.2-1 in lower case:
  - `patient`: PATIENT level (Patient Root Query/Retrieve Information Model)
  - `study`: STUDY level
  - `series`: SERIES level (requires `--study-uid`)
  - `image`: IMAGE level, one composite object instance (requires `--study-uid` and `--series-uid`);
    `instance` is accepted as an alias of `image`

### Filter Options

- `--patient-name <name>`: Patient's Name (0010,0010); `*` and `?` wild cards (PS3.4 C.2.2.2.4)
- `--patient-id <id>`: Patient ID (0010,0020)
- `--study-date <date>`: Study Date (0008,0020): `YYYYMMDD`, or a range `YYYYMMDD-YYYYMMDD`,
  `-YYYYMMDD` (up to and including) or `YYYYMMDD-` (from) per PS3.4 C.2.2.2.5
- `--study-uid <uid>`: Study Instance UID
- `--series-uid <uid>`: Series Instance UID
- `--accession-number <number>`: Accession number
- `--modality <modality>`: Modality (e.g., CT, MR, US)
- `--study-description <description>`: Study description (wildcards supported)
- `--referring-physician <name>`: Referring physician name

### Output Options

- `--format <format>`: Output format (default: table)
  - `table`: Human-readable table format
  - `json`: JSON format for scripting
  - `csv`: CSV format for spreadsheets
  - `compact`: Compact one-line format
  - `dicom-json`: PS3.18 Annex F.2 DICOM JSON Model (see below)
- `--csv-keywords`: CSV header row uses PS3.6 keywords instead of `(GGGG,EEEE)`
- `--verbose`: Show detailed query information

### Connection Options

- `--called-aet <string>`: Remote Application Entity Title (default: ANY-SCP)
- `--timeout <seconds>`: Connection timeout in seconds (default: 60)

## Examples

### Query by Patient Name

```bash
dicom-query pacs://pacs.hospital.com:11112 \
  --aet MY_SCU \
  --patient-name "SMITH^JOHN"
```

### Query by Date Range

```bash
dicom-query pacs://pacs.hospital.com:11112 \
  --aet MY_SCU \
  --study-date 20240101-20240131
```

### Query by Modality

```bash
dicom-query pacs://pacs.hospital.com:11112 \
  --aet MY_SCU \
  --modality CT
```

### Wildcard Search

```bash
# Find all patients whose name starts with "DOE"
dicom-query pacs://pacs.hospital.com:11112 \
  --aet MY_SCU \
  --patient-name "DOE*"

# Find all CT chest studies
dicom-query pacs://pacs.hospital.com:11112 \
  --aet MY_SCU \
  --modality CT \
  --study-description "*CHEST*"
```

### JSON Output for Scripting

```bash
dicom-query pacs://pacs.hospital.com:11112 \
  --aet MY_SCU \
  --patient-name "SMITH*" \
  --format json > results.json
```

### CSV Output for Spreadsheets

```bash
dicom-query pacs://pacs.hospital.com:11112 \
  --aet MY_SCU \
  --study-date 20240101-20241231 \
  --format csv > studies.csv
```

### Patient-Level Query

```bash
dicom-query pacs://pacs.hospital.com:11112 \
  --aet MY_SCU \
  --level patient \
  --patient-name "DOE*"
```

### Series-Level Query

```bash
dicom-query pacs://pacs.hospital.com:11112 \
  --aet MY_SCU \
  --level series \
  --study-uid 1.2.840.113619.2.55.3.4 \
  --modality MR
```

### Instance-Level Query

```bash
dicom-query pacs://pacs.hospital.com:11112 \
  --aet MY_SCU \
  --level image \
  --study-uid 1.2.840.113619.2.55.3.4 \
  --series-uid 1.2.840.113619.2.55.3.5
```

### Verbose Output

```bash
dicom-query pacs://pacs.hospital.com:11112 \
  --aet MY_SCU \
  --patient-name "SMITH*" \
  --verbose
```

This will show connection details and query filters:

```
Connecting to: pacs.hospital.com:11112
Calling AE: MY_SCU
Called AE: ANY-SCP
Query Level: STUDY

Query filters:
  (0010,0010) Patient's Name: SMITH*
  (0010,0020) Patient ID: (return)
  (0020,000D) Study Instance UID: (return)
  ...

Found 42 result(s)
```

## Output Formats

### Table Format (Default)

Human-readable table with aligned columns. The column labels are the PS3.6 2026a Table 6-1
Attribute Names of the attributes shown (e.g. `Patient's Name`, `Modalities in Study`,
`Number of Study Related Series`, `SOP Class UID`, `Number of Frames`; the instance table's
`Columns × Rows` column prints Columns (0028,0011) × Rows (0028,0010)). Labels before
2026-10-01 were abbreviations (`Patient Name`, `Date`, `Modalities`, `Series`, `Dimensions`, …):

```
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
Patient's Name            Patient ID   Study Date   Study Description              Modalities in Study Number of Study Related Series
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
SMITH^JOHN                12345        2024-02-15   CT CHEST W/ CONTRAST           CT                  3                             
DOE^JANE                  67890        2024-02-16   MR BRAIN W/WO CONTRAST         MR                  5                             
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
Total: 2 study(ies)
```

### JSON Format

A tool-specific summary for scripting: one object per match, keyed by the attribute tag as
`(GGGG,EEEE)` with the decoded string value. This is **not** the PS3.18 Annex F DICOM JSON Model;
use `--format dicom-json` for that (below). `json` keeps its keys and values unchanged.

```json
[
  {
    "(0008,0020)": "20240215",
    "(0008,1030)": "CT CHEST W/ CONTRAST",
    "(0010,0010)": "SMITH^JOHN",
    "(0010,0020)": "12345",
    "(0020,000D)": "1.2.840.113619.2.55.3.4"
  }
]
```

### DICOM JSON Format (`--format dicom-json`)

The PS3.18 2026a Annex F.2 DICOM JSON Model, encoded by DICOMWeb's `DICOMJSONEncoder` (the
same encoder `dicom-json` and `dicom-wado` use): a top-level array with one object per match,
keyed by the eight-digit uppercase tag in ascending order, each attribute carrying `vr` and
`Value` (PN as `{"Alphabetic": …}` component objects, F.2.2–F.2.5). The VR is taken from PS3.6
Table 6-1 (C-FIND responses may be Implicit VR; unknown or private tags are `UN`). Text is
decoded with the response's Specific Character Set and written as UTF-8, and (0008,0005) is
written as `ISO_IR 192` (F.2: "The default character repertoire shall be UTF-8 / ISO_IR 192").
A sequence in a response is written as `UN` `InlineBinary` (its raw bytes, F.2.7).

```json
[
  {
    "00080020" : { "vr" : "DA", "Value" : [ "20240215" ] },
    "00100010" : { "vr" : "PN", "Value" : [ { "Alphabetic" : "SMITH^JOHN" } ] },
    "0020000D" : { "vr" : "UI", "Value" : [ "1.2.840.113619.2.55.3.4" ] }
  }
]
```

### CSV Format

CSV output for spreadsheet import. By default the header row holds the attribute tags as
`(GGGG,EEEE)` (quoted, since they contain a comma), sorted by tag. With `--csv-keywords` the
header names each column by its PS3.6 Table 6-1 Keyword instead (`StudyDate,StudyDescription,
PatientName,…`; a tag without a keyword keeps its `(GGGG,EEEE)` form); rows are unchanged:

```csv
"(0008,0020)","(0008,1030)","(0010,0010)","(0010,0020)","(0020,000D)"
20240215,CT CHEST W/ CONTRAST,SMITH^JOHN,12345,1.2.840.113619.2.55.3.4
20240216,MR BRAIN W/WO CONTRAST,DOE^JANE,67890,1.2.840.113619.2.55.3.5
```

### Compact Format

One-line format for quick parsing:

```
SMITH^JOHN | 12345 | 20240215 | CT CHEST W/ CONTRAST | 1.2.840.113619.2.55.3.4
DOE^JANE | 67890 | 20240216 | MR BRAIN W/WO CONTRAST | 1.2.840.113619.2.55.3.5
```

## DICOM Query Matching

### Wildcard Support

DICOM supports two wildcard characters:

- `*`: Matches zero or more characters
- `?`: Matches exactly one character

Examples:
- `"SMITH*"`: Matches SMITH, SMITHSON, SMITH-JONES
- `"SM?TH"`: Matches SMITH, SMYTH
- `"*CHEST*"`: Matches anything containing CHEST

### Date Range Queries

Date ranges use the format: `YYYYMMDD-YYYYMMDD`

Examples:
- `20240101-20240131`: January 2024
- `20240101-20241231`: All of 2024
- `20240215`: Exact date (February 15, 2024)

### Empty Values

If you don't specify a filter, the attribute will be returned in results but won't be used for matching. This allows you to retrieve all values while still filtering on other criteria.

## Exit Codes

- `0`: Success (the C-FIND completed; an empty result set is still a success)
- `1`: Connection error, association rejected, or a C-FIND Failure status (PS3.4 Table C.4-1)
- `64`: Invalid arguments (usage error, e.g. `--level series` without `--study-uid`)

## Limitations

- **QIDO-RS Support**: HTTP/HTTPS URLs for QIDO-RS are planned but not yet implemented
- **TLS/SSL**: Secure DICOM connections are not yet supported
- **Authentication**: User authentication is not yet supported
- **Large Result Sets**: Very large result sets (>10,000) may be slow

## Requirements

- macOS 14.0+ or Linux
- Network access to DICOM PACS server
- Valid Application Entity Title (AE Title) configured on PACS

## Related Tools

- `dicom-info`: Display metadata from DICOM files
- `dicom-retrieve`: Retrieve DICOM files from PACS (coming soon)
- `dicom-send`: Send DICOM files to PACS (coming soon)

## Technical Details

### DICOM Standards

This tool implements:
- **PS3.4 Section C**: Query/Retrieve Service Class
- **PS3.7 Section 9.1.2**: C-FIND DIMSE Service
- **PS3.3 Section C.6**: Query/Retrieve Information Models

### Information Model

Uses the Study Root Query/Retrieve Information Model by default, which supports:
- PATIENT level (top; `--level patient` switches to the Patient Root model, PS3.4 Table C.6.1-1)
- STUDY level
- SERIES level
- IMAGE level (`--level image`, alias `instance`; PS3.4 Table C.6.2-1)

### Network Protocol

Standard DICOM Upper Layer Protocol over TCP/IP:
1. Association Request (A-ASSOCIATE-RQ)
2. Association Accept (A-ASSOCIATE-AC)
3. C-FIND Request (C-FIND-RQ) with query identifier
4. C-FIND Response (C-FIND-RSP) for each match (status: Pending)
5. C-FIND Response (status: Success) when complete
6. Association Release (A-RELEASE-RQ/RP)

## Troubleshooting

### Connection Refused

```
Error: Connection refused
```

**Solutions:**
- Verify the PACS hostname and port
- Check firewall settings
- Ensure PACS is running and accepting connections
- Verify your IP is allowed by PACS firewall

### Association Rejected

```
Error: Association rejected
```

**Solutions:**
- Verify your AE Title is configured on the PACS
- Check the called AE Title (use `--called-aet` if different from default)
- Contact PACS administrator to register your AE Title

### No Results

If your query returns no results:
- Check filter criteria (are they too restrictive?)
- Try broader wildcards (e.g., `"*"` returns all)
- Verify data exists in PACS using PACS UI
- Check query level is appropriate

### Timeout

```
Error: Connection timeout
```

**Solutions:**
- Increase timeout: `--timeout 120`
- Check network connectivity
- Verify PACS is responding

## License

Part of DICOMKit - see repository LICENSE file.

## Contributing

Contributions welcome! Please see the main DICOMKit repository for guidelines.
