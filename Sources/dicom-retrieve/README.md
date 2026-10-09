# dicom-retrieve

Retrieve DICOM files from PACS servers using C-MOVE or C-GET protocols.

## Features

- **C-MOVE Support**: Traditional DICOM retrieval with move destination
- **C-GET Support**: Direct retrieval without separate SCP
- **Multi-Level Operations**: Retrieve studies, series, or individual instances
- **Bulk Retrieval**: Process multiple study UIDs from a file
- **Parallel Operations**: Concurrent retrieval for improved performance
- **Progress Tracking**: Real-time progress updates during retrieval
- **Flexible Organization**: Hierarchical or flat file structure
- **Error Handling**: Automatic retry logic and comprehensive error reporting

## Usage

### Basic Study Retrieval (C-MOVE)

```bash
dicom-retrieve pacs://server:11112 \
  --aet MY_SCU \
  --move-dest MY_SCP \
  --study-uid 1.2.840.113619.2.xxx \
  --output study_dir/
```

### Study Retrieval with C-GET

```bash
dicom-retrieve pacs://server:11112 \
  --aet MY_SCU \
  --study-uid 1.2.840.113619.2.xxx \
  --method c-get \
  --output study_dir/
```

### Series Retrieval

```bash
dicom-retrieve pacs://server:11112 \
  --aet MY_SCU \
  --move-dest MY_SCP \
  --study-uid 1.2.840.113619.2.xxx \
  --series-uid 1.2.840.113619.2.yyy \
  --output series_dir/
```

### Instance Retrieval

```bash
dicom-retrieve pacs://server:11112 \
  --aet MY_SCU \
  --move-dest MY_SCP \
  --study-uid 1.2.840.113619.2.xxx \
  --series-uid 1.2.840.113619.2.yyy \
  --instance-uid 1.2.840.113619.2.zzz \
  --output .
```

### Bulk Retrieval from UID List

Create a text file with one Study UID per line:

```
# study_uids.txt
1.2.840.113619.2.aaa
1.2.840.113619.2.bbb
1.2.840.113619.2.ccc
```

Then retrieve all studies:

```bash
dicom-retrieve pacs://server:11112 \
  --aet MY_SCU \
  --move-dest MY_SCP \
  --uid-list study_uids.txt \
  --output studies/ \
  --parallel 4
```

### Hierarchical Organization

Organize retrieved files by study and series:

```bash
dicom-retrieve pacs://server:11112 \
  --aet MY_SCU \
  --method c-get \
  --study-uid 1.2.840.113619.2.xxx \
  --output output/ \
  --hierarchical
```

This creates a structure like:
```
output/
  ├── 1.2.840.113619.2.xxx/
  │   ├── 1.2.840.113619.2.yyy/
  │   │   ├── 1.2.840.113619.2.zzz.dcm
  │   │   └── ...
  │   └── 1.2.840.113619.2.www/
  │       └── ...
```

### Verbose Output

```bash
dicom-retrieve pacs://server:11112 \
  --aet MY_SCU \
  --method c-get \
  --study-uid 1.2.840.113619.2.xxx \
  --output study/ \
  --verbose
```

## Options

- `host` - PACS server hostname or IP address, optionally with port (host:port; `pacs://` prefix accepted)
- `--port` - PACS server port (default: 11112, the registered DICOM port; 104 is the well-known port — PS3.8 9.1.2)
- `--aet` - Local Application Entity Title (calling AE)
- `--called-aet` - Remote Application Entity Title (default: ANY-SCP)
- `--study-uid` - Study Instance UID (0020,000D) to retrieve — Query/Retrieve Level STUDY
- `--series-uid` - Series Instance UID (0020,000E) to retrieve — Query/Retrieve Level SERIES (requires --study-uid unless --relational-retrieve)
- `--instance-uid` - SOP Instance UID (0008,0018) to retrieve — Query/Retrieve Level IMAGE (requires --study-uid and --series-uid unless --relational-retrieve)
- `--uid-list` - File containing list of Study UIDs (one per line)
- `--output` - Output directory for retrieved files (default: current directory)
- `--method` - Retrieval method: c-move (Study Root Query/Retrieve Information Model - MOVE, 1.2.840.10008.5.1.4.1.2.2.2) or c-get (Study Root Query/Retrieve Information Model - GET, 1.2.840.10008.5.1.4.1.2.2.3) (default: c-move)
- `--move-dest` - Move Destination (0000,0600): AE Title of the Storage SCP that receives the C-STORE sub-operations (required for C-MOVE)
- `--hierarchical` - Organize C-GET output hierarchically (`<output>/<Study Instance UID>/<Series Instance UID>/`); C-MOVE output is stored by the move destination
- `--transfer-syntax` - Requested transfer syntax (name or UID) for the C-GET storage presentation contexts; advisory for C-MOVE
- `--timeout` - Connection timeout in seconds (default: 60)
- `--parallel` - Number of parallel retrieval operations (default: 1)
- `--priority` - Priority (0000,0700) of the C-MOVE-RQ / C-GET-RQ: `low` (0002H), `medium` (0000H), `high` (0001H) — PS3.7 2026a Tables 9.3-9 / 9.3-6 (default: medium). A non-default value is shown in the header as `Priority:`
- `--relational-retrieve` - Propose relational-retrieval in a SOP Class Extended Negotiation Sub-Item for the retrieval SOP Class (PS3.4 2026a C.5.2.1 / C.5.3.1, Table C.5-3 byte 1 = 1; PS3.7 Table D.3-11). With it, `--series-uid` or `--instance-uid` may be given without the UIDs of the levels above (PS3.4 C.4.2.2.2.1 / C.4.3.2.2.1). If the SCP returns no sub-item or byte 1 = 0 (Table C.5-4) and the identifier lacks those UIDs, the request is not sent and the tool exits 1; with all UIDs given the retrieve proceeds as baseline
- `-v, --verbose` - Show verbose output including progress

## C-MOVE vs C-GET

### C-MOVE
- Traditional DICOM retrieval method
- Requires a separate C-STORE SCP (move destination) to receive files
- PACS sends files to the move destination, not directly to the requester
- Useful when retrieving to a different system

### C-GET
- Direct retrieval method
- Files are sent directly to the requester (no separate destination needed)
- Simpler setup, but not supported by all PACS
- Recommended for direct downloads

## Requirements

- PACS server with C-MOVE or C-GET support
- Network connectivity to PACS (typically port 104 or 11112)
- For C-MOVE: A running C-STORE SCP at the move destination
- Valid AE titles configured on PACS

## Examples

### Download a complete study
```bash
dicom-retrieve pacs://pacs.hospital.org:11112 \
  --aet WORKSTATION \
  --method c-get \
  --study-uid 1.2.840.113619.2.55.3.2609895290.675.1234567890.123 \
  --output /data/studies/patient_123/ \
  --hierarchical \
  --verbose
```

### Batch download multiple studies
```bash
# Create UID list
cat > studies_to_download.txt << 'EOL'
1.2.840.113619.2.55.3.2609895290.675.1234567890.123
1.2.840.113619.2.55.3.2609895290.675.1234567890.456
1.2.840.113619.2.55.3.2609895290.675.1234567890.789
EOL

# Download with parallelism
dicom-retrieve pacs://pacs.hospital.org:11112 \
  --aet WORKSTATION \
  --method c-get \
  --uid-list studies_to_download.txt \
  --output /data/studies/ \
  --parallel 3 \
  --hierarchical \
  --verbose
```

## Exit Codes

- `0` - The final C-MOVE/C-GET response was Success (0000) with no failed sub-operations (PS3.4 C.4.2.2.1 / C.4.3.2.1)
- `1` - A final response of Warning (B000), Failure (A701, A702, A801, A900, Cxxx) or Cancel (FE00), any failed sub-operation, a transport error, or a bulk run with at least one failed study
- `64` - Usage error (for example C-MOVE without `--move-dest`, or `--series-uid` without `--study-uid`)

The final status is printed with the wording of PS3.4 2026a Table C.4-2 (C-MOVE) or Table C.4-3 (C-GET), and the counters under their PS3.7 names (Number of Completed / Failed / Warning Sub-operations); the Failed SOP Instance UID List (0008,0058) is printed to stderr when the SCP supplies one.

## See Also

- `dicom-query` - Query PACS for studies/series/instances
- `dicom-send` - Send DICOM files to PACS
- `dicom-info` - Display DICOM metadata
