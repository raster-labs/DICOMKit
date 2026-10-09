# dicom-json

Convert between DICOM and JSON formats using the DICOM JSON Model (PS3.18 Annex F).

## Description

`dicom-json` is a command-line tool for converting DICOM files to JSON format and back. It implements the DICOM JSON Model as specified in PS3.18 Annex F, providing interoperability with DICOMweb services and other JSON-based tools.

## Features

- **Bidirectional Conversion**: Convert DICOM → JSON and JSON → DICOM
- **DICOM JSON Model**: PS3.18 Annex F (attribute objects in ascending tag order, F.2.2; empty attributes kept as `{"vr": ...}`, F.2.5)
- **DICOMweb Format**: Support for DICOMweb JSON format
- **Bulk Data Handling**: Inline binary data or URI references
- **Pretty Printing**: Human-readable JSON output
- **Metadata Filtering**: Extract specific tags only
- **Large File Support**: Streaming mode for efficient processing
- **Performance**: Fast conversion with detailed timing information

## Installation

```bash
swift build -c release
cp .build/release/dicom-json /usr/local/bin/
```

## Usage

### Basic Conversion

Convert DICOM to JSON:
```bash
dicom-json file.dcm --output file.json
```

Convert JSON to DICOM:
```bash
dicom-json file.json --output file.dcm --reverse
```

### Pretty-Printed JSON

Output formatted JSON for readability:
```bash
dicom-json file.dcm --output file.json --pretty
```

### DICOMweb Format

Use DICOMweb-compatible JSON format:
```bash
dicom-json file.dcm --output file.json --format dicomweb
```

### Metadata Only

The Metadata of PS3.18 10.4.1.1.2, without Bulk Data: every OB/OD/OF/OL/OV/OW/UN value
(Pixel Data, Float / Double Float Pixel Data, Encapsulated Document, Waveform and Overlay
Data, LUTs), in sequence items too, is left out; with `--bulk-data-url` each one is
written as a BulkDataURI instead (PS3.18 10.4.3.3.2):
```bash
dicom-json large-image.dcm --output metadata.json --metadata-only
```

### Bulk Data Handling

Configure inline binary threshold:
```bash
# Inline binary data up to 2KB
dicom-json file.dcm --output file.json --inline-threshold 2048

# Every OB/OD/OF/OL/OV/OW/UN value as a BulkDataURI (needs --bulk-data-url)
dicom-json file.dcm --output file.json --inline-threshold 0 --bulk-data-url "http://example.com/bulk"
```

### Filter Specific Tags

Extract only specific tags:
```bash
# By tag name
dicom-json file.dcm --output metadata.json --filter-tag PatientName --filter-tag StudyDate

# By tag hex (GGGG,EEEE)
dicom-json file.dcm --output metadata.json --filter-tag 0010,0010 --filter-tag 0008,0020
```

### Streaming Mode

Process large files efficiently:
```bash
dicom-json large-study.dcm --output large-study.json --stream
```

### Verbose Output

Show detailed timing and statistics:
```bash
dicom-json file.dcm --output file.json --verbose
```

## Options

| Option | Description |
|--------|-------------|
| `-o, --output <path>` | Output file path (default: input with .json or .dcm extension) |
| `-r, --reverse` | Convert from JSON to DICOM. A BulkData reference that is a `file:` URL (or absolute path) is read into the attribute; any other is reported on stderr and the attribute is written with an empty Value Field. Group 0002 attributes in the input go to the File Meta Information only (PS3.10 7.1) |
| `-p, --pretty` | Pretty-print JSON output |
| `--no-sort-keys` | **Deprecated** (prints a stderr warning; will be removed). Don't order attribute objects by tag (default: ordered; unordered output breaks PS3.18 F.2.2) |
| `--include-empty` / `--no-include-empty` | Keep attributes with an empty Value Field as `{"vr": ...}` (default: on, PS3.18 F.2.5) / drop them |
| `--inline-threshold <bytes>` | With `--bulk-data-url`: OB/OD/OF/OL/OV/OW/UN values longer than this become a BulkDataURI (default: 1024; 0: all of them). Without `--bulk-data-url` they are all InlineBinary |
| `--bulk-data-url <url>` | Base URL for BulkDataURI values (PS3.18 F.2.6): `<url>/<GGGGEEEE>`, inside sequence items `<url>/<SQ tag>/<item n>/<GGGGEEEE>` |
| `--metadata-only` | Metadata (PS3.18 10.4.1.1.2): every OB/OD/OF/OL/OV/OW/UN value at any depth is left out, or with `--bulk-data-url` becomes a BulkDataURI |
| `--filter-tag <tag>` | Keep only this attribute: PS3.6 keyword, `GGGG,EEEE` or `GGGGEEEE` (can be used multiple times) |
| `--verbose` | Show detailed timing and statistics |
| `--version` | Show version information |
| `--help` | Show help message |

## Examples

### Convert CT Image to JSON

```bash
dicom-json ct-scan.dcm --output ct-scan.json --pretty
```

### Convert Multiple Files

```bash
for file in *.dcm; do
    dicom-json "$file" --output "${file%.dcm}.json"
done
```

### Extract Patient Demographics

```bash
dicom-json patient.dcm --output demographics.json \
    --filter-tag PatientName \
    --filter-tag PatientID \
    --filter-tag PatientBirthDate \
    --filter-tag PatientSex \
    --pretty
```

### Roundtrip Conversion

```bash
# DICOM → JSON → DICOM
dicom-json original.dcm --output temp.json
dicom-json temp.json --output restored.dcm --reverse
```

### Large Study with Bulk Data URIs

```bash
dicom-json large-study.dcm --output large-study.json \
    --inline-threshold 0 \
    --bulk-data-url "http://pacs.example.com/bulk" \
    --stream \
    --verbose
```

## JSON Format

The tool outputs DICOM JSON format as specified in PS3.18 Annex F. Each DICOM tag is represented as:

```json
{
  "00100010": {
    "vr": "PN",
    "Value": [
      {
        "Alphabetic": "Doe^John"
      }
    ]
  },
  "00100020": {
    "vr": "LO",
    "Value": ["123456"]
  }
}
```

### Bulk Data

Binary data can be inline (Base64) or referenced:

```json
{
  "7FE00010": {
    "vr": "OB",
    "InlineBinary": "AQIDBAU="
  }
}
```

Or:

```json
{
  "7FE00010": {
    "vr": "OB",
    "BulkDataURI": "http://example.com/bulk/7FE00010"
  }
}
```

## Performance

Typical conversion times on modern hardware:

- Small image (512×512, ~500KB): 10-50ms
- Medium image (1024×1024, ~2MB): 50-200ms
- Large image (2048×2048, ~8MB): 200-500ms
- CT series (100 slices, ~100MB): 2-5s

## Error Handling

The tool provides clear error messages for common issues:

- **File not found**: Validates input file exists
- **Invalid JSON**: Reports JSON parsing errors
- **Invalid DICOM**: Reports DICOM parsing errors
- **Invalid tags**: Validates tag format for filtering
- **Write errors**: Reports file write failures

## Exit Codes

- `0`: Success
- `1`: Error occurred

## Related Tools

- `dicom-info`: Display DICOM metadata
- `dicom-dump`: Dump DICOM file structure
- `dicom-xml`: Convert DICOM to/from XML
- `dicom-validate`: Validate DICOM files

## References

- DICOM PS3.18 Annex F - DICOM JSON Model
- DICOM PS3.5 - Data Structures and Encoding
- DICOMweb Standard (QIDO-RS, WADO-RS, STOW-RS)

## Version

1.1.3 - Part of DICOMKit Phase 3 CLI Tools
