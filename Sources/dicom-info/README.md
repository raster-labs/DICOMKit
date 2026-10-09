# DICOMTools - Command-Line Tools for DICOM Files

A collection of command-line utilities for working with DICOM medical imaging files, built using DICOMKit.

## Tools

### dicom-info

Display metadata from DICOM files in various formats.

**Features:**
- Plain text, JSON, and CSV output formats
- Tag filtering by PS3.6 keyword, tag, or part of the Attribute name
- Private tag inclusion/exclusion
- File statistics
- Forced parsing of non-standard files

**Usage:**

```bash
# Basic usage - display all tags
dicom-info scan.dcm

# JSON output
dicom-info --format json report.dcm

# CSV output for spreadsheet analysis
dicom-info --format csv exam.dcm > metadata.csv

# Filter by PS3.6 keyword (exact), by tag, or by part of the Attribute name (case-insensitive)
dicom-info --tag PatientName --tag StudyDate scan.dcm
dicom-info --tag 0010,0010 scan.dcm
dicom-info --tag "Patient" scan.dcm

# Include private tags
dicom-info --show-private scan.dcm

# Show file statistics
dicom-info --statistics scan.dcm

# Force parsing of legacy DICOM files
dicom-info --force legacy.dcm
```

## Installation

### From Source

```bash
cd DICOMKit
swift build -c release
sudo cp .build/release/dicom-info /usr/local/bin/
```

### Using Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/raster-image/DICOMKit.git", from: "1.0.0")
]
```

## Requirements

- Swift 6.2+
- macOS 14+ or Linux

## Future Tools

The following tools are planned for future releases:

- **dicom-convert** - Transfer syntax conversion and image export
- **dicom-anon** - DICOM file anonymization
- **dicom-validate** - File validation and conformance checking
- **dicom-query** - PACS query using C-FIND
- **dicom-send** - Send files to PACS using C-STORE
- **dicom-dump** - Low-level debugging and hex dump

## License

See LICENSE file in the repository root.

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](../CONTRIBUTING.md).
