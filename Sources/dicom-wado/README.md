# dicom-wado

DICOMweb client for RESTful DICOM operations supporting WADO-RS, QIDO-RS, STOW-RS, and UPS-RS protocols.

## Overview

`dicom-wado` provides a comprehensive command-line interface to DICOMweb services, enabling RESTful HTTP/HTTPS-based access to DICOM objects without requiring traditional DICOM networking infrastructure. It's built on DICOMKit's DICOMWeb module and supports all major DICOMweb protocols.

## Features

- **WADO-RS (Web Access to DICOM Objects - RESTful)**
  - Retrieve studies, series, instances
  - Retrieve specific frames
  - Retrieve rendered images and thumbnails
  - Retrieve metadata only
  
- **QIDO-RS (Query based on ID for DICOM Objects - RESTful)**
  - Search for studies, series, instances
  - Filter by patient name, ID, dates, modality
  - Support for wildcards and date ranges
  - Multiple output formats (table, JSON, CSV)

- **STOW-RS (Store Over the Web - RESTful)**
  - Upload single or multiple DICOM files
  - Batch upload with configurable batch size
  - Targeted study storage
  - Progress tracking and error handling

- **UPS-RS (Unified Procedure Step - RESTful)**
  - Search worklist items
  - Retrieve worklist details
  - Create new worklist items from JSON files
  - Create new worklist items from command-line options (patient, scheduling, priority, etc.)
  - Update worklist state

## Installation

Build from source using Swift Package Manager:

```bash
swift build -c release
# Binary will be at: .build/release/dicom-wado
```

## Usage

### General Syntax

```bash
dicom-wado <subcommand> <server-url> [options]
```

### Subcommands

- `retrieve` - WADO-RS operations
- `query` - QIDO-RS operations
- `store` - STOW-RS operations
- `ups` - UPS-RS worklist operations

---

## WADO-RS: Retrieve Operations

### Retrieve Study

Download all instances in a study:

```bash
dicom-wado retrieve https://pacs.example.com/dicom-web \
  --study 1.2.840.113619.2.xxx \
  --output study/
```

### Retrieve Series

Download all instances in a specific series:

```bash
dicom-wado retrieve https://pacs.example.com/dicom-web \
  --study 1.2.840.113619.2.xxx \
  --series 1.2.840.113619.2.xxx.1 \
  --output series/
```

### Retrieve Instance

Download a single instance:

```bash
dicom-wado retrieve https://pacs.example.com/dicom-web \
  --study 1.2.840.113619.2.xxx \
  --series 1.2.840.113619.2.xxx.1 \
  --instance 1.2.840.113619.2.xxx.1.1 \
  --output ./
```

### Retrieve Metadata

Get metadata without pixel data:

```bash
dicom-wado retrieve https://pacs.example.com/dicom-web \
  --study 1.2.840.113619.2.xxx \
  --metadata \
  --format json
```

### Retrieve Frames

Get specific frames from a multi-frame instance:

```bash
dicom-wado retrieve https://pacs.example.com/dicom-web \
  --study 1.2.840.113619.2.xxx \
  --series 1.2.840.113619.2.xxx.1 \
  --instance 1.2.840.113619.2.xxx.1.1 \
  --frames 1,2,3 \
  --output frames/
```

### Retrieve Rendered Image

Get a rendered JPEG image:

```bash
dicom-wado retrieve https://pacs.example.com/dicom-web \
  --study 1.2.840.113619.2.xxx \
  --series 1.2.840.113619.2.xxx.1 \
  --instance 1.2.840.113619.2.xxx.1.1 \
  --rendered \
  --output ./
```

### Retrieve Thumbnail

Get a thumbnail image:

```bash
dicom-wado retrieve https://pacs.example.com/dicom-web \
  --study 1.2.840.113619.2.xxx \
  --thumbnail \
  --output ./
```

### WADO-URI (PS3.18 Section 9)

`--uri` sends a URI service request (`requestType=WADO&studyUID=…&seriesUID=…&objectUID=…`);
`--study`, `--series` and `--instance` are required. The other parameters:

| Option | WADO-URI parameter | PS3.18 2026a |
|--------|--------------------|--------------|
| `--content-type` | `contentType`: `application/dicom` (default) or a Rendered Media Type: `image/jpeg`, `image/gif`, `image/png`, `image/jp2`, `image/jph`, `image/jxl`, `video/mpeg`, `video/mp4`, `video/H265`, `text/html`, `text/plain`, `text/xml`, `text/rtf`, `application/pdf`. Any other value is rejected | 9.1.2.2.1, Table 8.7.4-1 |
| `--charset <list>` | `charset`: comma-separated character sets | 9.1.2.2.2 |
| `--transfer-syntax <uid>` | `transferSyntax` (application/dicom) | 9.4.1.2.3 |
| `--anonymize` | `anonymize=yes` (application/dicom) | 9.4.1.2.1 |
| `--annotation <list>` | `annotation` (application/dicom, Table 9.4.1-1) or `imageAnnotation` (rendered, Table 9.5.1-1): `patient`, `technique` | 9.4.1.2.2 |
| `--frames <n>` | `frameNumber`: one positive frame number; further list entries are not sent | 9.5.1.2.1 |
| `--image-quality <1-100>` | `imageQuality` | 9.5.1.2.3, 8.3.5.1.2 |
| `--rows <n>`, `--columns <n>` | `rows`, `columns`: positive integers, both or neither (rendered) | 9.5.1.2.4 |
| `--region <xmin,ymin,xmax,ymax>` | `region`: normalized 0.0-1.0, xmin < xmax, ymin < ymax | 9.5.1.2.5 |
| `--window-center <d>`, `--window-width <d>` | `windowCenter`, `windowWidth`: both or neither; not with application/dicom or a Presentation State | 9.5.1.2.6 |
| `--presentation-uid <uid>`, `--presentation-series-uid <uid>` | `presentationUID`, `presentationSeriesUID`: both or neither | 9.5.1.2.7 |

A value that breaks one of these rules is refused before the request is sent. A parameter
that the requested representation's table does not define (for example `--frames` with
`application/dicom`, Table 9.4.1-1) is still sent, with a warning on stderr.

```bash
dicom-wado retrieve http://server:8080/wado --uri \
  --study 1.2.3 --series 1.2.3.4 --instance 1.2.3.4.5 \
  --content-type image/jpeg --rows 512 --columns 512 -o out/
```

---

## QIDO-RS: Query Operations

### Search Studies

Search for studies by patient name:

```bash
dicom-wado query https://pacs.example.com/dicom-web \
  --patient-name "DOE*" \
  --limit 50
```

Search by date range:

```bash
dicom-wado query https://pacs.example.com/dicom-web \
  --study-date 20240101-20240131 \
  --modality CT
```

Ask the server for fuzzy matching of person names (`fuzzymatching=true`, PS3.18 8.3.4.2):

```bash
dicom-wado query https://pacs.example.com/dicom-web \
  --patient-name "DOE^JON" \
  --fuzzy-matching
```

`--limit` and `--offset` take unsigned integers (PS3.18 8.3.4.4). At the study level
`--modality` matches Modalities in Study (0008,0061); at the series level, Modality
(0008,0060) (PS3.18 Table 10.6.1-5).

Search with specific study UID:

```bash
dicom-wado query https://pacs.example.com/dicom-web \
  --study 1.2.840.113619.2.xxx
```

### Search Series

Search all series in a study:

```bash
dicom-wado query https://pacs.example.com/dicom-web \
  --level series \
  --study 1.2.840.113619.2.xxx
```

Search all series by modality:

```bash
dicom-wado query https://pacs.example.com/dicom-web \
  --level series \
  --modality MR
```

### Search Instances

Search instances in a series:

```bash
dicom-wado query https://pacs.example.com/dicom-web \
  --level instance \
  --study 1.2.840.113619.2.xxx \
  --series 1.2.840.113619.2.xxx.1
```

### Output Formats

Table format (default):

```bash
dicom-wado query https://pacs.example.com/dicom-web \
  --patient-name "SMITH*" \
  --format table
```

JSON format:

```bash
dicom-wado query https://pacs.example.com/dicom-web \
  --patient-name "SMITH*" \
  --format json > results.json
```

CSV format:

```bash
dicom-wado query https://pacs.example.com/dicom-web \
  --patient-name "SMITH*" \
  --format csv > results.csv
```

DICOM JSON Model (PS3.18 F.2: tag keys, `vr`, `Value`, PN component objects):

```bash
dicom-wado query https://pacs.example.com/dicom-web \
  --patient-name "SMITH*" \
  --format dicom-json > results.json
```

---

## STOW-RS: Store Operations

### Upload Files

Upload single file:

```bash
dicom-wado store https://pacs.example.com/dicom-web file.dcm
```

Upload multiple files:

```bash
dicom-wado store https://pacs.example.com/dicom-web file1.dcm file2.dcm file3.dcm
```

Upload all files in directory:

```bash
dicom-wado store https://pacs.example.com/dicom-web study/*.dcm
```

### Batch Upload

Upload with custom batch size:

```bash
dicom-wado store https://pacs.example.com/dicom-web \
  --input file_list.txt \
  --batch 20 \
  --verbose
```

### Targeted Storage

Store to specific study:

```bash
dicom-wado store https://pacs.example.com/dicom-web \
  file1.dcm file2.dcm \
  --study 1.2.840.113619.2.xxx
```

### Error Handling

Continue on errors:

```bash
dicom-wado store https://pacs.example.com/dicom-web \
  study/*.dcm \
  --continue-on-error \
  --verbose
```

`--continue-on-error` keeps later batches going; the run still exits 1 when any file was not
stored (PS3.18 Table 10.5.3-1: 202 Accepted or a 4xx status means some or all Instances were
not stored).

---

## UPS-RS: Worklist Operations

### Search Worklist

Search all worklist items:

```bash
dicom-wado ups https://pacs.example.com/dicom-web --search
```

Filter by state (Procedure Step State (0074,1000): `SCHEDULED`, `"IN PROGRESS"`, `COMPLETED`,
`CANCELED`, PS3.3 Table C.30.1-1; `IN_PROGRESS` is also accepted):

```bash
dicom-wado ups https://pacs.example.com/dicom-web \
  --search \
  --filter-state SCHEDULED
```

Filter by station:

```bash
dicom-wado ups https://pacs.example.com/dicom-web \
  --search \
  --scheduled-station CT_STATION_1
```

### Get Worklist Item

Retrieve specific worklist item:

```bash
dicom-wado ups https://pacs.example.com/dicom-web \
  --get 1.2.840.113619.2.xxx
```

### Create Worklist Item

Create from JSON file:

```bash
dicom-wado ups https://pacs.example.com/dicom-web \
  --create worklist.json
```

Example `worklist.json`:

```json
{
  "00741000": {
    "vr": "SQ",
    "Value": [{
      "00741002": { "vr": "SH", "Value": ["CT_SCAN_001"] },
      "00741004": { "vr": "CS", "Value": ["SCHEDULED"] },
      "00741224": { "vr": "SQ", "Value": [{ ... }] }
    }]
  }
}
```

### Create Worklist Item from Options

Create a workitem directly from command-line flags without crafting DICOM JSON:

```bash
dicom-wado ups https://pacs.example.com/dicom-web \
  --create-workitem \
  --label "CT Scan Chest" \
  --patient-name "Doe^Jane" \
  --patient-id PAT001 \
  --priority HIGH
```

With scheduling and study reference:

```bash
dicom-wado ups https://pacs.example.com/dicom-web \
  --create-workitem \
  --label "MRI Brain" \
  --patient-name "Smith^John" \
  --patient-id PAT002 \
  --patient-birth-date 19800115 \
  --patient-sex M \
  --priority HIGH \
  --scheduled-start "2026-03-21T09:00:00" \
  --expected-completion "2026-03-21T10:30:00" \
  --study-uid 1.2.840.113619.2.xxx \
  --accession-number ACC12345 \
  --referring-physician "Jones^Dr" \
  --verbose
```

With performer and station information:

```bash
dicom-wado ups https://pacs.example.com/dicom-web \
  --create-workitem \
  --label "CT Abdomen" \
  --patient-name "Brown^Alice" \
  --patient-id PAT003 \
  --station-name CT_STATION_1 \
  --performer-name "Tech^Mary" \
  --performer-organization "Radiology Dept" \
  --step-id STEP001 \
  --worklist-label "Morning Worklist" \
  --comments "Patient prepped for contrast" \
  --admission-id ADM789
```

With a specific workitem UID:

```bash
dicom-wado ups https://pacs.example.com/dicom-web \
  --create-workitem \
  --workitem-uid 1.2.3.4.5.6.7.8.9 \
  --label "Process Report" \
  --priority LOW
```

#### Create Workitem Options

| Option | Description |
|--------|-------------|
| `--label` | **(Required)** Procedure step label |
| `--workitem-uid` | Workitem UID (auto-generated if omitted) |
| `--patient-name` | Patient name in DICOM format (e.g. `Doe^Jane`) |
| `--patient-id` | Patient identifier |
| `--patient-birth-date` | Patient birth date (`YYYYMMDD`) |
| `--patient-sex` | Patient's Sex (0010,0040): `M`, `F`, `O` (PS3.3 Table C.7-1) |
| `--priority` | Scheduled Procedure Step Priority (0074,1200): `HIGH`, `MEDIUM` (default), `LOW` (PS3.3 Table C.30.2-1). `STAT` is accepted and sent as `HIGH` ("equivalent to a STAT request") |
| `--scheduled-start` | Scheduled start date/time (ISO 8601) |
| `--expected-completion` | Expected completion date/time (ISO 8601) |
| `--study-uid` | Study Instance UID to reference |
| `--accession-number` | Accession number |
| `--referring-physician` | Referring physician name |
| `--procedure-id` | Requested procedure ID |
| `--step-id` | Scheduled procedure step ID |
| `--worklist-label` | Worklist label |
| `--comments` | Comments on the procedure step |
| `--station-name` | Scheduled station name |
| `--performer-name` | Performer name |
| `--performer-organization` | Performer organization |
| `--admission-id` | Admission ID |
```

### Update Worklist State

Change worklist item state (Change Workitem State, PS3.18 11.7):

```bash
dicom-wado ups https://pacs.example.com/dicom-web \
  --change-state 1.2.840.113619.2.xxx \
  --state "IN PROGRESS"
```

`--update <uid>` is a deprecated alias of `--change-state` (it never performed Update Workitem,
PS3.18 11.6); it still works and prints a stderr note. Giving both is refused (exit 1).

Valid target states (PS3.18 11.7.1.4, Procedure Step State (0074,1000)):
- `IN PROGRESS` (`IN_PROGRESS` is also accepted; a Transaction UID is generated when `--transaction-uid` is omitted)
- `COMPLETED` (requires `--transaction-uid`)
- `CANCELED` (requires `--transaction-uid`)

`SCHEDULED` is refused with exit 1: it is not a Change State target (PS3.18 2026a 11.7.1.4), and
PS3.4 2026a Table CC.1.1-2 answers a change to SCHEDULED with C303H.

---

## Authentication

### OAuth2 Bearer Token

```bash
dicom-wado retrieve https://pacs.example.com/dicom-web \
  --study 1.2.840.113619.2.xxx \
  --token "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

Token can be set via environment variable:

```bash
export DICOMWEB_TOKEN="your-token-here"
dicom-wado retrieve https://pacs.example.com/dicom-web \
  --study 1.2.840.113619.2.xxx \
  --token "$DICOMWEB_TOKEN"
```

---

## Common Options

### Verbose Output

Show detailed progress and debug information:

```bash
dicom-wado retrieve https://pacs.example.com/dicom-web \
  --study 1.2.840.113619.2.xxx \
  --verbose
```

### Timeout Configuration

Set custom timeout (in seconds):

```bash
dicom-wado retrieve https://pacs.example.com/dicom-web \
  --study 1.2.840.113619.2.xxx \
  --timeout 120
```

---

## Examples

### Complete Workflow Example

1. Query for studies:

```bash
dicom-wado query https://pacs.example.com/dicom-web \
  --patient-name "SMITH^JOHN" \
  --study-date 20240101-20240131 \
  --format json > studies.json
```

2. Extract study UID from results and retrieve:

```bash
STUDY_UID="1.2.840.113619.2.xxx"
dicom-wado retrieve https://pacs.example.com/dicom-web \
  --study $STUDY_UID \
  --output "studies/$STUDY_UID/" \
  --verbose
```

3. Upload processed results:

```bash
dicom-wado store https://pacs.example.com/dicom-web \
  processed/*.dcm \
  --batch 10 \
  --verbose
```

### Metadata-Only Retrieval

Retrieve study metadata for processing:

```bash
dicom-wado retrieve https://pacs.example.com/dicom-web \
  --study 1.2.840.113619.2.xxx \
  --metadata \
  --format json | jq '.[] | .["00100010"]'
```

### Thumbnail Gallery

Download thumbnails for all series in a study:

```bash
#!/bin/bash
STUDY_UID="1.2.840.113619.2.xxx"

# Query series
SERIES=$(dicom-wado query https://pacs.example.com/dicom-web \
  --level series \
  --study $STUDY_UID \
  --format json | jq -r '.[].SeriesInstanceUID')

# Download thumbnail for each series
for SERIES_UID in $SERIES; do
  dicom-wado retrieve https://pacs.example.com/dicom-web \
    --study $STUDY_UID \
    --series $SERIES_UID \
    --thumbnail \
    --output thumbnails/
done
```

---

## Error Handling

The tool provides detailed error messages and appropriate exit codes:

- Exit code 0: Success
- Exit code 1: General error, an HTTP error status, or (store) any file not stored
- Exit code 64: Invalid arguments (ArgumentParser validation error)

HTTP errors are reported with the PS3.18 Table 8.5-1 status names, e.g.:
- 400: Bad Request
- 401: Unauthorized
- 404: Not Found
- 409: Conflict
- 500: Internal Server Error

Other codes print as `HTTP Error <code>`. Example error output:

```
Error: Not Found: <response body, if any>
```

`--format json` for `query` and `ups` prints a summary array (query: PS3.6 keywords as keys,
e.g. `"SeriesInstanceUID"`; ups: camelCase keys), not the PS3.18 Annex F DICOM JSON Model.
`--format dicom-json` for `query` and `ups --search` / `--get` prints the PS3.18 2026a F.2 DICOM
JSON Model: the objects the server returned, as one top-level array, attributes in ascending tag
order, Group Length attributes removed (F.2.2).
`retrieve --metadata --format json` prints the server's DICOM JSON Model as received.

---

## Performance Tips

1. **Use batch operations** for bulk uploads to reduce overhead
2. **Retrieve metadata first** to plan selective downloads
3. **Use appropriate timeouts** for large studies
4. **Enable verbose mode** to monitor progress on long operations
5. **Use JSON format** for programmatic processing of results

---

## Limitations

- Requires macOS 10.15 or later for async/await support
- HTTPS certificate validation follows system settings

---

## Related Tools

- `dicom-query` - Traditional DICOM C-FIND queries
- `dicom-send` - Traditional DICOM C-STORE operations
- `dicom-retrieve` - Traditional DICOM C-MOVE/C-GET operations
- `dicom-qr` - Integrated query-retrieve workflow

---

## Standards Reference

- **DICOM PS3.18**: Web Services (DICOMweb specification)
- **WADO-RS**: Section 10.4 - Web Access to DICOM Objects
- **QIDO-RS**: Section 10.6 - Query based on ID for DICOM Objects
- **STOW-RS**: Section 10.5 - Store Over the Web
- **UPS-RS**: Section 11 - Unified Procedure Step

---

## Version

Version 1.0.0 - Part of DICOMKit CLI Tools Phase 5
