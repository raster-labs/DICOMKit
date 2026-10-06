# dicom-pdf

Extract and encapsulate PDF/CDA/3D documents from/to DICOM format.

## Overview

`dicom-pdf` is a command-line tool for working with DICOM Encapsulated Documents. It supports extracting documents (PDF, CDA, STL, OBJ, MTL) from DICOM files and encapsulating documents into DICOM format for PACS storage and transmission.

## Supported Document Types

- **PDF** (Portable Document Format) - SOP Class UID: 1.2.840.10008.5.1.4.1.1.104.1
- **CDA** (Clinical Document Architecture XML) - SOP Class UID: 1.2.840.10008.5.1.4.1.1.104.2
- **STL** (Stereolithography 3D models) - SOP Class UID: 1.2.840.10008.5.1.4.1.1.104.3
- **OBJ** (Wavefront 3D object files) - SOP Class UID: 1.2.840.10008.5.1.4.1.1.104.4
- **MTL** (Wavefront material files) - SOP Class UID: 1.2.840.10008.5.1.4.1.1.104.5

## Installation

### Building from Source

```bash
cd DICOMKit
swift build -c release
cp .build/release/dicom-pdf /usr/local/bin/
```

### Verify Installation

```bash
dicom-pdf --version
# Output: 1.1.5
```

## Usage

### Extract Mode

Extract documents from DICOM Encapsulated Document files.

#### Extract Single File

```bash
# Extract PDF from DICOM
dicom-pdf report.dcm --output report.pdf --extract

# Extract with metadata display
dicom-pdf report.dcm --output report.pdf --extract --show-metadata --verbose

# Extract CDA document
dicom-pdf cda.dcm --output discharge_summary.xml --extract
```

#### Extract Multiple Files (Batch Mode)

```bash
# Extract all documents from a directory
dicom-pdf study/ --output documents/ --extract --recursive

# Verbose batch extraction
dicom-pdf study/ --output documents/ --extract --recursive --verbose
```

### Encapsulation Mode

Encapsulate documents into DICOM format with proper metadata.

#### Encapsulate Single File

```bash
# Encapsulate PDF
dicom-pdf report.pdf --output report.dcm \
  --patient-name "DOE^JOHN" \
  --patient-id "12345" \
  --title "Radiology Report"

# Encapsulate with full metadata
dicom-pdf report.pdf --output report.dcm \
  --patient-name "SMITH^JANE" \
  --patient-id "54321" \
  --title "CT Scan Report" \
  --modality "DOC" \
  --series-description "Radiology Reports" \
  --series-number 1 \
  --instance-number 1 \
  --study-uid "1.2.840.113619.2.55.3.2831961723.123" \
  --series-uid "1.2.840.113619.2.55.3.2831961723.456"

# Encapsulate CDA document (HL7 Instance Identifier (0040,E001) is read from
# /ClinicalDocument/id; --hl7-instance-identifier overrides it)
dicom-pdf discharge.xml --output discharge.dcm \
  --patient-name "DOE^JANE" \
  --patient-id "99999" \
  --title "Discharge Summary"

# Encapsulate a scanned paper report that does not identify the patient
dicom-pdf scan.pdf --output scan.dcm \
  --patient-name "DOE^JANE" --patient-id "99999" \
  --conversion-type SD --burned-in-annotation NO

# Encapsulate 3D model
dicom-pdf model.stl --output model.dcm \
  --patient-name "TEST^MODEL" \
  --patient-id "3D001" \
  --title "Surgical Planning Model" \
  --modality "M3D"
```

#### Encapsulate Multiple Files (Batch Mode)

```bash
# Encapsulate all PDFs in a directory
dicom-pdf documents/ --output dicoms/ --recursive \
  --patient-name "BATCH^PATIENT" \
  --patient-id "00000" \
  --series-description "Batch Encapsulation" \
  --verbose

# All files will be grouped into a single series with auto-incrementing instance numbers
```

A directory run (extract or encapsulate) exits with status 1 after its summary when any file
failed, like `dicom-convert`'s directory run. Files the run does not apply to are skipped, not
failed: in extract mode a file that is not an Encapsulated Document (not a DICOM file, or a data
set without Encapsulated Document (0042,0011), PS3.3 C.24.2; `--verbose` prints
`⊘ <file>: not an Encapsulated Document (skipped)`), as `dicom-image` skips non-images and
`dicom-export bulk` files without pixel data; in encapsulate mode a file of an unsupported type.
Only a document that fails to extract (or a file that cannot be read or written) counts as
failed. Until 2026-10-06 a directory run exited 0 whatever the per-file outcomes (D271).

## Options

### Required Arguments

- `<input>` - Input file or directory (DICOM or document)

### Mode Selection

- `--extract` - Extract mode: Extract document from DICOM

### Output Options

- `-o, --output <output>` - Output file or directory path (auto-generated if not specified)

### Encapsulation Metadata (Required for Encapsulation)

- `--patient-name <name>` - Patient's Name (DICOM PN format, e.g., "DOE^JOHN")
- `--patient-id <id>` - Patient ID

### Encapsulation Metadata (Optional)

- `--title <title>` - Document Title (0042,0010)
- `--study-uid <uid>` - Study Instance UID (auto-generated if not provided)
- `--series-uid <uid>` - Series Instance UID (auto-generated if not provided)
- `--modality <modality>` - Modality (default: DOC for documents; STL, OBJ and MTL require M3D, PS3.3 A.85.x.4.3)
- `--conversion-type <term>` - Conversion Type (0008,0064) for PDF and CDA, one of the PS3.3 Table C.8-24 Defined Terms DV, DI, DF, WSD, SD, SI, DRW, SYN (default: WSD)
- `--burned-in-annotation <YES|NO>` - Burned In Annotation (0028,0301): whether the document identifies the patient and the date (default: YES)
- `--hl7-instance-identifier <uid[^ext]>` - HL7 Instance Identifier (0040,E001) of a CDA document (default: root^extension of /ClinicalDocument/id; single file only)
- `--series-description <desc>` - Series Description
- `--series-number <num>` - Series Number
- `--instance-number <num>` - Instance Number

### Processing Options

- `--recursive` - Process directories recursively (required for directory operations)
- `--show-metadata` - Show document metadata during extraction
- `--verbose` - Verbose output with detailed progress information

### General Options

- `--version` - Show version information
- `-h, --help` - Show help information

## Examples

### Example 1: Extract PDF from DICOM

```bash
dicom-pdf report.dcm --output report.pdf --extract
# Output: Extracted: report.pdf
```

### Example 2: Extract with Metadata Display

```bash
dicom-pdf report.dcm --output report.pdf --extract --show-metadata

# Output:
# Document Metadata:
#   Type: pdf
#   MIME Type: application/pdf
#   Size: 125.45 KB
#   SOP Class: 1.2.840.10008.5.1.4.1.1.104.1
#   SOP Instance: 1.2.3.4.5.6.7
#   Title: Radiology Report
#
# Patient Information:
#   Name: DOE^JOHN
#   ID: 12345
#
# Study/Series:
#   Study UID: 1.2.3.4.5
#   Series UID: 1.2.3.4.5.6
#   Modality: DOC
#
# ✓ Extracted pdf (125.45 KB)
#   Output: report.pdf
```

### Example 3: Batch Extract Documents

```bash
dicom-pdf study/ --output documents/ --extract --recursive --verbose

# Output:
# Extracting documents from: study/
# Output directory: documents/
#
# ✓ report1.dcm → report1.pdf
# ✓ report2.dcm → report2.pdf
# ✓ cda1.dcm → cda1.xml
# ✗ image.dcm: Missing or empty Encapsulated Document data
#
# Extraction complete:
#   Successful: 3
#   Failed: 1
#   Output directory: documents/
```

### Example 4: Encapsulate PDF with Metadata

```bash
dicom-pdf report.pdf --output report.dcm \
  --patient-name "SMITH^JOHN" \
  --patient-id "12345" \
  --title "CT Scan Report" \
  --series-description "Radiology Reports" \
  --verbose

# Output:
# Encapsulating document: report.pdf
# ✓ Encapsulated pdf (125.45 KB)
#   DICOM size: 127.12 KB
#   Patient: SMITH^JOHN [12345]
#   Study UID: 2.25.1738903123456789.123456
#   Output: report.dcm
```

### Example 5: Batch Encapsulate Documents

```bash
dicom-pdf reports/ --output dicoms/ --recursive \
  --patient-name "BATCH^ENCAPSULATION" \
  --patient-id "BATCH001" \
  --series-description "Batch Reports" \
  --verbose

# Output:
# Encapsulating documents from: reports/
# Output directory: dicoms/
#
# ✓ report1.pdf → report1.dcm
# ✓ report2.pdf → report2.dcm
# ✓ discharge.xml → discharge.dcm
# ⊘ readme.txt: Unsupported file type
#
# Encapsulation complete:
#   Successful: 3
#   Failed: 0
#   Study UID: 2.25.1738903123456789.123456
#   Series UID: 2.25.1738903123456789.654321
#   Output directory: dicoms/
```

## Document Type Detection

The tool automatically detects document types based on:

- **Extraction**: MIME type and SOP Class UID from DICOM metadata
- **Encapsulation**: File extension (.pdf, .xml, .stl, .obj, .mtl)

## Auto-generated Metadata

When not specified, the following metadata is auto-generated:

- **Study Instance UID**: Generated using timestamp and random component
- **Series Instance UID**: Generated using timestamp and random component  
- **SOP Instance UID**: Auto-generated by EncapsulatedDocumentBuilder
- **Modality**: DOC for documents (PDF, CDA), M3D for 3D models (STL, OBJ, MTL)
- **Output filename**: Based on input filename with appropriate extension

## DICOM Standards Compliance

This tool implements the following DICOM standards:

- **PS3.3 A.45.1**: Encapsulated PDF IOD (MIME Type application/pdf)
- **PS3.3 A.45.2**: Encapsulated CDA IOD (MIME Type text/XML)
- **PS3.3 A.85.1–A.85.3**: Encapsulated STL, OBJ and MTL IODs (Modality M3D)
- **PS3.3 C.24.1, C.24.2**: Encapsulated Document Series and Encapsulated Document Modules.
  Encapsulated Document Length (0042,0015) is written with the unpadded length, and
  extraction cuts the value to it, so an odd-length document comes back byte for byte
- **PS3.3 C.8.6.1**: SC Equipment Module (Conversion Type, PDF and CDA)
- **PS3.3 C.12.1**: SOP Common; Specific Character Set ISO_IR 192 when a text value is not ASCII
- **PS3.5 A.2**: DICOM Little Endian Transfer Syntax (Explicit VR)

## Error Handling

The tool provides clear error messages for common issues:

- Missing required metadata (Patient Name, Patient ID)
- Invalid or missing input files
- Unsupported file types
- Invalid DICOM files
- Failed extraction/encapsulation operations

## Limitations

- Only supports the 5 standard DICOM Encapsulated Document SOP Classes
- Batch operations share the same Study and Series UIDs
- Auto-generated UIDs use a simple timestamp-based scheme (sufficient for most use cases)
- Large files may take longer to process

## Performance

- **Single file operations**: < 1 second for typical documents
- **Batch operations**: Scales linearly with number of files
- **Memory usage**: Minimal (streams data where possible)

## Integration with PACS

Encapsulated DICOM documents can be:

- Stored on PACS using dicom-send
- Retrieved from PACS using dicom-query and dicom-retrieve
- Viewed in DICOM viewers that support Encapsulated Document SOP Classes
- Archived alongside related imaging studies

## Troubleshooting

### "Invalid Exclude .../README.md: File not found" Warning

This warning can be safely ignored - it's a build-time warning about missing README in the source directory.

### "Input path not found" Error

Ensure the input file or directory path is correct and accessible.

### "Patient Name is required for encapsulation" Error

When encapsulating documents, both `--patient-name` and `--patient-id` are required.

### "Directory processing requires --recursive flag" Error

Use `--recursive` flag when processing directories.

## See Also

- **dicom-info**: Display DICOM file metadata
- **dicom-query**: Query PACS for studies
- **dicom-send**: Send DICOM files to PACS
- **dicom-convert**: Convert DICOM transfer syntaxes and export images
- **dicom-validate**: Validate DICOM file conformance

## Version

v1.1.5 (Phase 3: Format Conversion Tools)

## License

See LICENSE file in repository root.

## Author

Part of DICOMKit - A pure Swift DICOM toolkit for Apple platforms.
