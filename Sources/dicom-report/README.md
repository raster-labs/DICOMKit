# dicom-report

Generate professional clinical reports from DICOM Structured Report (SR) objects.

## Overview

`dicom-report` is a command-line tool for converting DICOM SR documents into human-readable clinical reports in various formats. It supports all common SR types including Basic Text SR, Enhanced SR, Comprehensive SR, and specialized report types.

## Features

- **Multiple Output Formats**: Text, HTML, JSON, Markdown (PDF planned)
- **SR Support**: Basic Text SR, Enhanced SR, Comprehensive SR, and specialized reports
- **Content Tree Navigation**: Hierarchical rendering of SR content structure
- **Measurement Extraction**: Automatic extraction and formatting of measurements
- **Customization**: Templates, branding, custom titles, and footers
- **Image Support**: Placeholder for embedding referenced images (HTML/PDF)

## Installation

Build from source:

```bash
swift build -c release
```

The binary will be located at `.build/release/dicom-report`.

## Usage

### Basic Usage

Generate a text report:
```bash
dicom-report sr.dcm --output report.txt
```

### Output Formats

#### Text Report
```bash
dicom-report sr.dcm --output report.txt --format text
```

#### HTML Report
```bash
dicom-report sr.dcm --output report.html --format html
```

#### JSON Report
```bash
dicom-report sr.dcm --output data.json --format json
```

#### Markdown Report
```bash
dicom-report sr.dcm --output report.md --format markdown
```

### Advanced Options

#### Custom Title
```bash
dicom-report sr.dcm --output report.html --format html --title "Cardiology Report"
```

#### With Branding
```bash
dicom-report sr.dcm --output report.html --format html \
  --logo hospital-logo.png \
  --footer "Confidential Medical Report - Hospital Name"
```

#### Include Measurements
```bash
dicom-report sr.dcm --output report.txt --include-measurements
```

#### Verbose Output
```bash
dicom-report sr.dcm --output report.html --format html --verbose
```

## Examples

### Example 1: Basic Text Report

Input:
```bash
dicom-report measurement-report.dcm --output report.txt
```

Output (report.txt):
```
================================================================================
                    Measurement Report - Chest CT
================================================================================

Patient: DOE^JOHN
Patient ID: 12345678
Study Date: 2026-02-12
Accession Number: ACC20260212001

--------------------------------------------------------------------------------

Findings:
  Nodule Measurement:
    3.2 mm
  Location:
    Right Upper Lobe
  Attenuation:
    -200 Hounsfield Units

--------------------------------------------------------------------------------
MEASUREMENTS
--------------------------------------------------------------------------------

Nodule Size: 3.2 mm
Attenuation: -200 Hounsfield Units
```

### Example 2: HTML Report

```bash
dicom-report cardiology-report.dcm --output report.html --format html \
  --logo hospital-logo.png \
  --footer "Confidential Medical Report"
```

Generates a styled HTML report with:
- Hospital branding
- Responsive design
- Color-coded sections
- Professional layout

### Example 3: JSON for Integration

```bash
dicom-report sr.dcm --output data.json --format json
```

Output structure:
```json
{
  "document_type": "Enhanced SR",
  "title": "Clinical Report",
  "completion_flag": "COMPLETE",
  "verification_flag": "VERIFIED",
  "preliminary_flag": "FINAL",
  "content_template": {
    "template_identifier": "2000",
    "mapping_resource": "DCMR"
  },
  "patient": {
    "name": "DOE^JOHN",
    "id": "12345678"
  },
  "study": {
    "uid": "1.2.840.113619...",
    "date": "20260212",
    "accession_number": "ACC001"
  },
  "content_item_count": 15,
  "content": [
    {
      "value_type": "CONTAINER",
      "relationship_type": "CONTAINS",
      "concept_name": {
        "code_value": "121070",
        "coding_scheme": "DCM",
        "code_meaning": "Findings"
      },
      "value": "[0 items]",
      "children": []
    }
  ],
  "measurements": [
    {
      "name": "Nodule Size",
      "value": "3.2",
      "units": "mm"
    }
  ]
}
```

## Command-Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `--output` / `-o` | Output file path | Required |
| `--format` / `-f` | Output format (text, html, json, markdown, pdf) | text |
| `--embed-images` | Embed images from referenced instances | false |
| `--image-dir` | Directory containing referenced image files | - |
| `--style` | Styling preset: default, cardiology, radiology, oncology (section order, colours). Not a PS3.16 SR template; an unknown value is refused (exit 1) | default |
| `--template` | **Deprecated** alias of `--style` (prints a note; giving both is refused) | — |
| `--title` | Custom report title (overrides SR title) | - |
| `--logo` | Path to hospital logo for branding | - |
| `--footer` | Custom footer text | - |
| `--include-measurements` | Include measurement tables | true |
| `--include-summary` / `--no-include-summary` | Include the summary sections (Impressions, Recommendations) in text, HTML and Markdown; the content tree is always rendered. JSON reports the setting as `include_summary` | true |
| `--language` | Section-heading language (en, es, fr, de) | en |
| `--force` | Force parsing files without DICM prefix | false |
| `--verbose` | Verbose output for debugging | false |

## Supported SR Types

- **Basic Text SR** (1.2.840.10008.5.1.4.1.1.88.11)
- **Enhanced SR** (1.2.840.10008.5.1.4.1.1.88.22)
- **Comprehensive SR** (1.2.840.10008.5.1.4.1.1.88.33)
- **Comprehensive 3D SR** (1.2.840.10008.5.1.4.1.1.88.34)
- **Mammography CAD SR** (1.2.840.10008.5.1.4.1.1.88.50)
- **Chest CAD SR** (1.2.840.10008.5.1.4.1.1.88.65)
- **Key Object Selection Document** (1.2.840.10008.5.1.4.1.1.88.59)
- **Extensible SR** (1.2.840.10008.5.1.4.1.1.88.35) and the other SR Storage SOP Classes of PS3.6 Table A-1
- Any root template, e.g. TID 1500 Measurement Report (shown from Content Template Sequence)

## How content is printed (PS3.3 / PS3.16 2026a)

- `value_type` (JSON): the Value Type names of PS3.3 Table C.17.3-7 (TEXT, NUM, CODE, DATETIME, DATE,
  TIME, UIDREF, PNAME, COMPOSITE, IMAGE, WAVEFORM, SCOORD, SCOORD3D, TCOORD, CONTAINER, TABLE);
  `relationship_type`: the Relationship Types of Table C.17.3-8.
- CODE values print as `(CV, CSD, "CM")`, the notation of PS3.16 Section 6.1.
- NUM values print the Numeric Value followed by the Code Meaning of the Measurement Units Code
  Sequence (UCUM, CID 82).
- The header lists Completion Flag, Verification Flag and Preliminary Flag (PS3.3 Table C.17-2) and the
  root Content Template (TID and Mapping Resource, Table C.18.8-1).
- Children are rendered under every content item that has them (e.g. NUM INFERRED FROM SCOORD), not
  only under CONTAINERs.

## Error Handling

The tool provides clear error messages for common issues:

```bash
$ dicom-report nonexistent.dcm --output report.txt
Error: File not found: nonexistent.dcm

$ dicom-report image.dcm --output report.txt
Error: Not a Structured Report. SOP Class UID indicates: CT Image Storage

$ dicom-report sr.dcm --output report.pdf --format pdf
Error: PDF generation requires additional libraries. Use HTML or Markdown format instead.
```

## Output Examples

### Text Format
- Clean, readable plain text
- Suitable for terminal display and log files
- 80-column formatted layout
- Hierarchical indentation

### HTML Format
- Professional styling with CSS
- Responsive design for web browsers
- Color-coded sections
- Hospital branding support
- Print-optimized layout

### JSON Format
- Structured data for integration
- Complete SR content tree
- Machine-readable format
- API-friendly structure

### Markdown Format
- GitHub/GitLab compatible
- Easy to read and edit
- Converts to HTML/PDF with external tools
- Version control friendly

## Integration Examples

### Shell Script Pipeline
```bash
#!/bin/bash
# Process all SR files in a directory
for file in *.dcm; do
  dicom-report "$file" --output "${file%.dcm}.html" --format html --verbose
done
```

### Python Integration
```python
import subprocess
import json

# Generate JSON report
subprocess.run([
    'dicom-report',
    'sr.dcm',
    '--output', 'report.json',
    '--format', 'json'
])

# Parse and process
with open('report.json') as f:
    report = json.load(f)
    print(f"Patient: {report['patient']['name']}")
    print(f"Measurements: {len(report['measurements'])}")
```

## Performance

- **Small SR (<100 items)**: <100ms
- **Medium SR (100-1000 items)**: <500ms
- **Large SR (>1000 items)**: <2s

Memory usage scales linearly with SR content size.

## Limitations

### Current Version (v1.4.0)

- **PDF Generation**: Not yet implemented. Use HTML or Markdown and convert with external tools.
- **Image Embedding**: Placeholder only. Images not yet embedded in HTML/PDF.
- **Styles**: `--style` presets change section order and colours. SR templates (PS3.16 TIDs) are not chosen by an option: the root template is read from the document's Content Template Sequence (0040,A504) and shown.

### Planned Features (Future Releases)

- Native PDF generation using PDFKit
- Image embedding from referenced instances
- Full template system with specialty-specific layouts
- Multi-language support
- Comparison reports (current vs. prior)
- DICOM print support

## DICOM Conformance

This tool conforms to:
- **PS3.3**: DICOM SR Information Object Definitions
- **PS3.4**: DICOM SR Service Classes
- **CP-1848**: Template ID 1500 (Measurement Report)

Validated against sample SR files from:
- dcm4che test datasets
- NEMA DICOM sample files
- Clinical SR examples

## Troubleshooting

### Issue: "Not a Structured Report"

**Solution**: Ensure the input file is a valid DICOM SR. Check the SOP Class UID with `dicom-info`.

### Issue: "Parse error in content sequence"

**Solution**: SR may be malformed or use unsupported extensions. Try `--force` flag or validate with `dicom-validate`.

### Issue: "PDF not implemented"

**Solution**: Use HTML format and convert to PDF with a browser or tool like `wkhtmltopdf`:
```bash
dicom-report sr.dcm --output report.html --format html
wkhtmltopdf report.html report.pdf
```

## Development

### Running Tests
```bash
swift test --filter DICOMReportTests
```

### Code Coverage
```bash
swift test --enable-code-coverage
xcrun llvm-cov report .build/debug/dicom-reportPackageTests.xctest/Contents/MacOS/dicom-reportPackageTests
```

## Contributing

Contributions welcome! Please:
1. Follow Swift API Design Guidelines
2. Add tests for new features
3. Update README with examples
4. Ensure zero compiler warnings

## License

MIT License - See LICENSE file

## References

- [DICOM PS3.3](https://dicom.nema.org/medical/dicom/current/output/chtml/part03/ps3.3.html) - SR IOD Definitions
- [DICOM PS3.16](https://dicom.nema.org/medical/dicom/current/output/chtml/part16/PS3.16.html) - Content Mapping Resources
- [Template ID 1500](https://dicom.nema.org/medical/dicom/current/output/chtml/part16/chapter_A.html) - Measurement Report

## Version History

### v1.4.0 (2026-02-12)
- Initial release
- Text, HTML, JSON, Markdown output formats
- Basic SR, Enhanced SR, Comprehensive SR support
- Measurement extraction
- Customization options (title, footer, branding)
- Comprehensive documentation

---

**Status**: Phase 7.1 - Clinical Report Generation (Phase A Complete)  
**Part of**: [DICOMKit CLI Tools Phase 7](../../CLI_TOOLS_PHASE7.md)
