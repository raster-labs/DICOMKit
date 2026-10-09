# dicom-qr

Integrated DICOM query-retrieve tool combining C-FIND and C-MOVE/C-GET operations into a seamless workflow.

## Overview

`dicom-qr` provides an integrated workflow for querying PACS servers and retrieving studies in a single operation. It combines the functionality of `dicom-query` and `dicom-retrieve` tools with additional features like interactive study selection, automatic retrieval, state persistence, and resume capability.

## Features

- **Integrated Workflow**: Query and retrieve in a single command
- **Multiple Modes**: 
  - Interactive mode with study selection
  - Automatic mode for bulk retrieval
  - Review mode for query-only operations
- **Progress Tracking**: Real-time progress for multi-study retrievals
- **State Persistence**: Save query/retrieval state for later resume
- **Resume Capability**: Resume interrupted retrievals from saved state
- **Validation**: Optional post-retrieval DICOM file validation
- **Flexible Retrieval**: Support for both C-MOVE and C-GET methods

## Usage

### Interactive Mode

Query PACS and interactively select studies to retrieve:

```bash
dicom-qr pacs://server:11112 \
  --aet MY_AET \
  --move-dest MY_SCP \
  --patient-name "DOE*" \
  --interactive
```

The tool will:
1. Execute the C-FIND query
2. Display all matching studies
3. Prompt you to select which studies to retrieve
4. Retrieve selected studies with progress tracking

### Automatic Mode

Query and automatically retrieve all matching studies:

```bash
dicom-qr pacs://server:11112 \
  --aet MY_AET \
  --move-dest MY_SCP \
  --study-date "20240101-20240131" \
  --modality CT \
  --output studies/ \
  --auto
```

### Review Mode

Query only, optionally save state for later retrieval:

```bash
dicom-qr pacs://server:11112 \
  --aet MY_AET \
  --patient-id "12345" \
  --review \
  --save-state query.state
```

Later, resume the retrieval:

```bash
dicom-qr resume --state query.state
```

### Resume Interrupted Retrievals

If a retrieval is interrupted, you can resume from saved state:

```bash
# During initial retrieval, save state
dicom-qr pacs://server:11112 \
  --aet MY_AET \
  --move-dest MY_SCP \
  --patient-name "SMITH*" \
  --save-state retrieval.state \
  --auto

# If interrupted, resume later
dicom-qr resume --state retrieval.state
```

## Options

### Query Parameters

All queries are Study Root, Query/Retrieve Level STUDY (PS3.4 2026a Table C.6-5):

- `--patient-name <name>`: Patient's Name (0010,0010) — wildcards * and ? (PS3.4 C.2.2.2.4)
- `--patient-id <id>`: Patient ID (0010,0020)
- `--study-date <date>`: Study Date (0008,0020) — YYYYMMDD, or a range YYYYMMDD-YYYYMMDD, -YYYYMMDD, YYYYMMDD- (PS3.4 C.2.2.2.5)
- `--study-uid <uid>`: Study Instance UID (0020,000D)
- `--accession-number <number>`: Accession Number (0008,0050)
- `--modality <modality>`: Modalities in Study (0008,0061), a PS3.3 C.7.3.1.1.1 Defined Term (e.g., CT, MR, US); `--strict-modality` rejects an unlisted value
- `--study-description <desc>`: Study Description (0008,1030) — wildcards * and ?

### Retrieval Options

- `--move-dest <aet>`: Move Destination (0000,0600): AE Title of the Storage SCP that receives the C-STORE sub-operations (required for C-MOVE)
- `--method <method>`: Retrieval method: c-move (Study Root Query/Retrieve Information Model - MOVE) or c-get (Study Root Query/Retrieve Information Model - GET) (default: c-move)
- `--output, -o <path>`: Output directory for retrieved files (default: current directory)
- `--hierarchical`: Organize C-GET output hierarchically (`<output>/<Study Instance UID>/`); C-MOVE output is stored by the move destination
- `--transfer-syntax <name|uid>`: Requested transfer syntax for the C-GET storage presentation contexts; advisory for C-MOVE
- `--priority <low|medium|high>`: Priority (0000,0700) of each C-MOVE-RQ / C-GET-RQ — LOW 0002H, MEDIUM 0000H, HIGH 0001H (PS3.7 2026a Tables 9.3-9 / 9.3-6; default: medium; also accepted by `resume`). Relational-retrieval is not offered: `dicom-qr` retrieves at STUDY level, where the Identifier already carries the level's Unique Key (use `dicom-retrieve --relational-retrieve` for series/instance retrieval by UID alone)

### Mode Selection (choose one)

- `--interactive`: Interactive mode - select studies to retrieve
- `--auto`: Automatic mode - retrieve all matching studies
- `--review`: Review mode - query only, save state for later

### Additional Options

- `--save-state <path>`: Save query/retrieval state to file
- `--validate`: Validate retrieved files after download
- `--parallel <n>`: Maximum concurrent retrievals (default: 1). Up to `n` studies are retrieved at once, each on its own association; the per-study `[i/N] Retrieving` / outcome lines are printed in study order once each batch of `n` finishes (with `1`, each line is printed before its retrieval starts). Must be at least 1
- `--timeout <seconds>`: Connection timeout in seconds (default: 60; also accepted by `resume`)
- `--verbose`: Show verbose output including detailed progress
- `--aet <title>`: Local Application Entity Title (calling AE)
- `--called-aet <title>`: Remote Application Entity Title (default: ANY-SCP)

## Examples

### Interactive Study Selection

```bash
# Query for CT studies from January 2024
dicom-qr pacs://pacs.hospital.org:11112 \
  --aet WORKSTATION \
  --move-dest MY_SCP \
  --modality CT \
  --study-date "20240101-20240131" \
  --interactive

# Output:
# Found 15 studies
# 
# Studies:
# ─────────────────────────────────────────────────
# [1] SMITH^JOHN (ID: 123456)
#     Study: CT CHEST W/CONTRAST
#     Date: 20240105  Modality: CT
#     UID: 1.2.840.113619.2.xxx
# [2] DOE^JANE (ID: 234567)
#     Study: CT HEAD W/O CONTRAST
#     Date: 20240108  Modality: CT
#     UID: 1.2.840.113619.2.yyy
# ...
# 
# Enter study numbers to retrieve (comma-separated, or 'all'):
# Examples: 1,3,5  or  all  or  1-5
# 
# > 1,2,5-7
```

### Automatic Bulk Retrieval

```bash
# Retrieve all MR studies for a specific patient
dicom-qr pacs://pacs.hospital.org:11112 \
  --aet WORKSTATION \
  --move-dest MY_SCP \
  --patient-id "987654" \
  --modality MR \
  --output /data/studies/ \
  --hierarchical \
  --auto \
  --validate
```

### Query, Review, and Retrieve Later

```bash
# Step 1: Query and review results
dicom-qr pacs://pacs.hospital.org:11112 \
  --aet WORKSTATION \
  --patient-name "JOHNSON*" \
  --study-date "20240201-20240228" \
  --review \
  --save-state query_feb2024.state

# Step 2: Later, retrieve the studies
dicom-qr resume --state query_feb2024.state
```

### Using C-GET Instead of C-MOVE

```bash
# C-GET retrieves directly without needing a move destination
dicom-qr pacs://pacs.hospital.org:11112 \
  --aet WORKSTATION \
  --method c-get \
  --study-uid "1.2.840.113619.2.xxx" \
  --output study_dir/ \
  --auto
```

## Interactive Study Selection

In interactive mode, you can select studies using:

- **Individual numbers**: `1,3,5` - selects studies 1, 3, and 5
- **Ranges**: `1-5` - selects studies 1 through 5
- **All**: `all` - selects all studies
- **Combinations**: `1-3,5,7-9` - selects studies 1-3, 5, and 7-9

## State Files

State files are JSON files that store query results and retrieval configuration. They can be used to:

1. **Review queries**: Save query results to review before retrieving
2. **Resume retrievals**: Resume interrupted retrievals from where they stopped
3. **Batch processing**: Create state files for multiple queries and process them later

State file structure:

```json
{
  "studies": [
    {
      "patientName": "SMITH^JOHN",
      "patientID": "123456",
      "studyInstanceUID": "1.2.840.113619.2.xxx",
      "studyDate": "20240105",
      "ModalitiesInStudy": "CT\\PR",
      "modality": "CT",
      "studyDescription": "CT CHEST W/CONTRAST"
    }
  ],
  "host": "pacs.hospital.org",
  "port": 11112,
  "callingAE": "WORKSTATION",
  "calledAE": "ANY-SCP",
  "moveDestination": "MY_SCP",
  "method": "c-move",
  "outputPath": "/data/studies",
  "hierarchical": true
}
```

`ModalitiesInStudy` is the PS3.6 keyword of Modalities in Study (0008,0061), the
STUDY-level value of PS3.4 Table C.6-5 (multiple values joined by `\`). The older
`modality` key holds Modality (0008,0060), a Series-level attribute that is usually
absent from a STUDY-level response; it is still written with the same value for older
readers but is **deprecated** — read `ModalitiesInStudy`. State files written before
this change lack `ModalitiesInStudy` and still load.

## Validation

When `--validate` is specified, retrieved files are validated after download:

```bash
dicom-qr pacs://server:11112 \
  --aet MY_AET \
  --move-dest MY_SCP \
  --patient-id "12345" \
  --output studies/ \
  --auto \
  --validate
```

Validation checks:
- File is a valid DICOM file
- File can be read and parsed
- Reports count of valid and invalid files

## Exit Codes

- `0` - Every selected study was retrieved: final C-MOVE/C-GET response Success (0000) with no failed sub-operations (PS3.4 C.4.2.2.1 / C.4.3.2.1)
- `1` - At least one study failed (final response Warning, Failure or Cancel, a failed sub-operation, or a transport error) — the summary is still printed; also any other error
- `64` - Usage error (no mode, several modes, C-MOVE without `--move-dest`, unknown method)

A non-success final response is reported with the wording of PS3.4 2026a Table C.4-2 (C-MOVE) or C.4-3 (C-GET) and the PS3.7 sub-operation counter names.

## Error Handling

The tool provides detailed error messages for common issues:

- **Missing move destination**: C-MOVE requires `--move-dest` to be specified
- **No studies found**: Query returned no results
- **Connection timeout**: PACS server didn't respond within timeout period
- **Invalid state file**: Saved state file is corrupted or incompatible

## Performance

For large retrievals, consider:

- Using `--parallel <n>` (or `dicom-retrieve --uid-list --parallel`) for concurrent study retrieval (use cautiously)
- Saving state files for checkpoint/resume capability
- Using `--hierarchical` for better organization of retrieved files
- Monitoring with `--verbose` to track progress

## See Also

- `dicom-query` - Standalone C-FIND query tool
- `dicom-retrieve` - Standalone C-MOVE/C-GET retrieval tool
- `dicom-send` - C-STORE operations to send files to PACS
- `dicom-archive` - Local DICOM archive management

## Technical Details

### C-MOVE vs C-GET

- **C-MOVE**: Server sends files to a third-party destination (specified by `--move-dest`)
  - Requires a running SCP at the move destination
  - More common in clinical environments
  - Requires `--move-dest` parameter

- **C-GET**: Server sends files directly to the requesting client
  - Simpler setup, no third-party SCP needed
  - Less common but easier for testing
  - Use `--method c-get`

### Query Levels

The tool performs study-level queries (default). All matching studies are retrieved in full.

### Wildcards

Patient name and study description support DICOM wildcards:
- `*` matches any sequence of characters
- `?` matches any single character

Examples:
- `SMITH*` - matches SMITH, SMITHSON, etc.
- `*JOHN*` - matches anything containing JOHN
- `DOE?` - matches DOE plus one character

## Requirements

- macOS 10.15 or later (Network framework required)
- Network connectivity to PACS server
- Valid AE titles configured on PACS
- For C-MOVE: Running SCP at move destination

## Limitations

- Study-level queries and retrievals only (Query/Retrieve Level STUDY; not PATIENT, SERIES or IMAGE)
- Instance Availability (0008,0056) and Retrieve AE Title (0008,0054) returned by the query are not used: `resume` retrieves from the queried SCP
- Interactive mode requires terminal input
- State files are not encrypted (do not store in insecure locations)
- Parallel retrievals may overwhelm some PACS servers
