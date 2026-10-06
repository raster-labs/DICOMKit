# dicom-send

Send DICOM files to PACS servers using the C-STORE protocol.

## Features

- **Transfer Protocols**: C-STORE (DIMSE) support
- **File Operations**: Send single files, multiple files, or entire directories
- **Recursive Scanning**: Use `--recursive` to traverse directory trees
- **Glob Patterns**: Support for wildcards (`*.dcm`, `study?.dcm`)
- **Connection Verification**: Pre-send C-ECHO verification with `--verify`
- **Retry Logic**: Configurable retry attempts with exponential backoff
- **Progress Reporting**: Real-time progress with file counts and bytes transferred
- **Dry Run Mode**: Test without actually sending files
- **Verbose Output**: Detailed logging for debugging

## Usage

### Basic Send

```bash
# Send a single file
dicom-send pacs://server:11112 --aet MY_SCU file.dcm

# Send multiple files
dicom-send pacs://server:11112 --aet MY_SCU file1.dcm file2.dcm file3.dcm
```

### Directory Operations

```bash
# Send all files in a directory (non-recursive)
dicom-send pacs://server:11112 --aet MY_SCU study_dir/

# Send all files recursively
dicom-send pacs://server:11112 --aet MY_SCU study_dir/ --recursive
```

### Glob Patterns

```bash
# Send all .dcm files in current directory
dicom-send pacs://server:11112 --aet MY_SCU *.dcm

# Send specific pattern
dicom-send pacs://server:11112 --aet MY_SCU CT_*.dcm
```

### Advanced Options

```bash
# Verify connection first
dicom-send pacs://server:11112 --aet MY_SCU study/ --verify

# Retry on failure
dicom-send pacs://server:11112 --aet MY_SCU study/ --retry 3

# Dry run (test without sending)
dicom-send pacs://server:11112 --aet MY_SCU study/ --dry-run

# Verbose output
dicom-send pacs://server:11112 --aet MY_SCU study/ --verbose

# Custom called AE title
dicom-send pacs://server:11112 --aet MY_SCU --called-aet PACS_SCP study/

# Set priority
dicom-send pacs://server:11112 --aet MY_SCU study/ --priority high

# Custom timeout
dicom-send pacs://server:11112 --aet MY_SCU study/ --timeout 120
```

## Options

- `--aet <AE>`: Local Application Entity Title (required)
- `--called-aet <AE>`: Remote Application Entity Title (default: ANY-SCP)
- `--recursive, -r`: Recursively scan directories
- `--verify`: Verify connection with C-ECHO before sending
- `--retry <N>`: Number of retry attempts on failure (default: 0)
- `--dry-run`: Show what would be sent without actually sending
- `--verbose, -v`: Show detailed progress and debugging information
- `--timeout <N>`: Connection timeout in seconds (default: 60)
- `--priority <low|medium|high>`: DIMSE priority (default: medium)

## URL Format

The tool uses a custom URL scheme for PACS servers:

```
pacs://hostname:port
```

- **hostname**: IP address or DNS name of PACS server
- **port**: DICOM port (default: 104 if not specified)

### Examples

```bash
pacs://192.168.1.100:11112
pacs://pacs.hospital.local:104
pacs://dicom-server:4242
```

## File Detection

The tool identifies DICOM files by:

1. **File Extension**: `.dcm`, `.dicom`, `.dic`
2. **Magic Bytes**: Checks for "DICM" signature at byte 128

Non-DICOM files are automatically skipped during directory scans.

## Progress Reporting

### Normal Mode

Simple progress bar showing completion percentage:

```
Progress: 15/100 (15%)
```

### Verbose Mode

Detailed per-file reporting:

```
[1/100] Sending: CT_001.dcm (512.34 KB)... ✓ (0.234s)
    SOP Instance UID: 1.2.840.113619.2.55.3.2...
[2/100] Sending: CT_002.dcm (498.12 KB)... ✓ (0.221s)
    SOP Instance UID: 1.2.840.113619.2.55.3.3...
```

### Final Summary

```
Transfer Summary
================
Total files:     100
Succeeded:       98
Failed:          2
Bytes sent:      51.23 MB
Duration:        45.6 s
Throughput:      1.12 MB/s

⚠ Partial success: 98 succeeded, 2 failed
```

## Retry Logic

When `--retry N` is specified, the tool will:

1. Attempt to send each file
2. On failure, retry up to N times
3. Use exponential backoff between retries (1s, 2s, 4s, 8s...)
4. Continue with next file if all retries fail

Example:

```bash
dicom-send pacs://server:11112 --aet MY_SCU study/ --retry 3 --verbose
```

## Dry Run Mode

Use `--dry-run` to test file discovery without actually sending:

```bash
dicom-send pacs://server:11112 --aet MY_SCU study/ --recursive --dry-run
```

Output:

```
Found 150 file(s) to send
  [1] /path/to/study/CT_001.dcm
  [2] /path/to/study/CT_002.dcm
  ...

Dry run complete. Use without --dry-run to send files.
```

## Error Handling

The tool handles various error conditions:

- **Connection Failures**: Timeout, refused connection
- **Association Errors**: AE title mismatch, negotiation failure
- **Transfer Errors**: Protocol errors, server rejection
- **File Errors**: Read permission, corrupted files

Failed files are reported but don't stop the batch transfer unless `--retry` exhausts.

## C-STORE Response Statuses

Each C-STORE response is classified by PS3.4 Table B.2-1 (2026a):

- **Success** (`0000`): stored.
- **Warning** (`B000` Coercion of Data Elements, `B006` Elements Discarded, `B007` Data Set does
  not match SOP Class): the SCP stored the instance but reports a deviation. The file counts as
  sent; the status is printed under the file line in the Table B.2-1 wording
  (`⚠️ Stored with warning: Warning (0xB000): Coercion of Data Elements`) and counted on the
  `Warnings:` line of the Transfer Summary (shown only when non-zero; the same shared summary
  the DICOMStudio Workshop prints).
- **Failure** (`A7xx` Refused: Out of resources, `A9xx` Error: Data Set does not match SOP Class,
  `Cxxx` Error: Cannot understand, `0122` Refused: SOP Class not supported): not stored. The
  file counts as failed, `--retry` applies, and the status is printed on the file line in the
  Table B.2-1 wording
  (`❌ C-STORE response status Failure (0xA700): Refused: Out of resources — not stored (PS3.4 Table B.2-1)`).

## Exit Codes

- `0`: All files sent (stored, or stored with a warning status)
- `1`: One or more files failed (a Failure status or a network error), or an error before transfer
- `64`: Invalid arguments (usage error, e.g. a negative `--retry` or an unknown `--transfer-syntax`)

## Performance Considerations

- Files are sent sequentially (no parallel transfers in this version)
- Each file uses a new association (no association reuse yet)
- Memory usage is proportional to largest file size
- Network throughput depends on PACS server and network latency

## Limitations

- **STOW-RS**: Not yet implemented (DICOMweb upload)
- **Parallel Transfers**: Single-threaded operation only
- **Association Reuse**: New association per file
- **C-ECHO**: Verification is simplified in current version

## Examples

### Send Study to PACS

```bash
dicom-send pacs://192.168.1.100:11112 \
  --aet WORKSTATION \
  --called-aet PACS_SERVER \
  /path/to/study/ \
  --recursive \
  --verify \
  --verbose
```

### Batch Upload with Retry

```bash
dicom-send pacs://pacs.hospital.local:104 \
  --aet MODALITY_01 \
  --retry 3 \
  exams/*.dcm
```

### Test Before Sending

```bash
# First, dry run to check files
dicom-send pacs://server:11112 --aet MY_SCU study/ --dry-run

# Then, send with verification
dicom-send pacs://server:11112 --aet MY_SCU study/ --verify --verbose
```

## Related Tools

- **dicom-query**: Query PACS for studies and series
- **dicom-info**: Extract metadata from DICOM files
- **dicom-validate**: Validate DICOM file structure

## DICOM Conformance

- **SOP Classes**: Supports all standard storage SOP classes
- **Transfer Syntaxes**: Explicit VR Little Endian, Implicit VR Little Endian
- **Service**: C-STORE SCU (Storage Service Class User)
- **Specification**: DICOM PS3.4 Annex B - Storage Service Class

## See Also

- DICOM Standard PS3.4: Service Class Specifications
- DICOM Standard PS3.7: Message Exchange (DIMSE)
- RFC 3986: URI Generic Syntax
