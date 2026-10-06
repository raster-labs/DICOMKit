# dicom-image

Convert standard images (JPEG, PNG, TIFF, BMP, GIF) to DICOM Secondary Capture format.

## Overview

`dicom-image` is a command-line tool for converting standard image formats to the DICOM Secondary Capture Image IOD, SOP Class "Secondary Capture Image Storage" (1.2.840.10008.5.1.4.1.1.7; PS3.4 Table B.5-1). It supports EXIF metadata extraction, batch conversion, and multi-page TIFF handling.

## Features

- **Image Format Support**: JPEG, PNG, TIFF, BMP, GIF (platform-dependent)
- **EXIF Metadata**: Extract and map EXIF data to DICOM tags
- **Batch Conversion**: Process entire directories of images
- **Multi-Page TIFF**: Split multi-page TIFFs into separate DICOM files
- **Secondary Capture**: Creates standards-compliant Secondary Capture SOP instances
- **Customizable Metadata**: Set patient, study, series, and equipment information

## Installation

### Building from Source

```bash
cd DICOMKit
swift build -c release
cp .build/release/dicom-image /usr/local/bin/
```

### Verify Installation

```bash
dicom-image --version
# Output: 1.1.6
```

## Usage

### Basic Conversion

Convert a single image file to DICOM:

```bash
dicom-image photo.jpg --output capture.dcm \
  --patient-name "DOE^JOHN" \
  --patient-id "12345"
```

### With Study Description

```bash
dicom-image xray.jpg --output xray.dcm \
  --patient-name "SMITH^JANE" \
  --patient-id "54321" \
  --study-description "Chest X-Ray" \
  --series-description "PA View"
```

### Using EXIF Metadata

Extract EXIF metadata from the image and use it in DICOM:

```bash
dicom-image photo.jpg --output capture.dcm \
  --patient-name "DOE^JOHN" \
  --patient-id "12345" \
  --use-exif \
  --study-description "Clinical Photography"
```

EXIF metadata mapping:
- **Date/Time Original** → Acquisition Date (0008,0022) / Acquisition Time (0008,0032)
- **DPI** → Nominal Scanned Pixel Spacing (0018,2010), mm on the scanned medium (SC Image Module,
  PS3.3 Table C.8-25) — not Pixel Spacing (0028,0030), which is a distance in the patient
- **User Comment / Image Description** → Study Description (if `--study-description` is not given)

### Batch Conversion

Convert all images in a directory:

```bash
dicom-image photos/ --output dicoms/ --recursive \
  --patient-name "BATCH^PATIENT" \
  --patient-id "BATCH001" \
  --series-description "Clinical Photography" \
  --verbose
```

All images will be grouped into a single series with auto-incrementing instance numbers.

A directory run exits with status 1 after its summary when any image failed to convert (files
that are not images are skipped, not failed), like `dicom-convert`'s directory run; until
2026-10-06 it exited 0 whatever the per-file outcomes (D273).

### Multi-Page TIFF

Split a multi-page TIFF into separate DICOM files:

```bash
dicom-image multipage.tiff --output frames/ \
  --split-pages \
  --patient-name "TEST^PATIENT" \
  --patient-id "99999" \
  --verbose
```

Each page becomes a separate DICOM instance in the same series.

## Options

### Required Arguments

- `<input>` - Input image file or directory

### Required Metadata

- `--patient-name <name>` - Patient Name in DICOM PN format (e.g., "DOE^JOHN")
- `--patient-id <id>` - Patient ID

### Optional Metadata

- `-o, --output <path>` - Output file or directory (auto-generated if not specified)
- `--study-description <desc>` - Study Description
- `--series-description <desc>` - Series Description
- `--study-uid <uid>` - Study Instance UID (auto-generated if not provided)
- `--series-uid <uid>` - Series Instance UID (auto-generated if not provided)
- `--study-date <YYYYMMDD>` - Study Date (0008,0020): the date the Study started (DA, Gregorian calendar)
- `--study-time <HHMMSS[.FFFFFF]>` - Study Time (0008,0030): the time the Study started (TM; HH, HHMM, HHMMSS
  or HHMMSS with 1-6 fraction digits)

  When neither is given, a new Study (no `--study-uid`) gets the date and time the run started, the
  same in every file of a batch or TIFF run; with `--study-uid` both are written empty (Type 2,
  PS3.3 Table C.7-3), since the Study started earlier at a time the tool does not know. When one
  is given, only that one is written. A fraction is written with six digits (`.5` → `.500000`).
- `--series-number <num>` - Series Number
- `--instance-number <num>` - Instance Number (starting value for batch operations)
- `--modality <modality>` - Modality (0008,0060), a PS3.3 C.7.3.1.1.1 Defined Term (default: OT); unknown codes warn
- `--strict-modality` - Reject a `--modality` value that is not a current Defined Term
- `--conversion-type <term>` - Conversion Type (0008,0064): DV, DI, DF, WSD, SD, SI, DRW or SYN
  (PS3.3 Table C.8-24; default WSD = Workstation; e.g. SI for a scanned image, DRW for a drawing)

Values that the written VR cannot hold (PS3.5 Table 6.2-1 and Section 9: a UID that breaks
PS3.5 9.1, LO/PN over 64 characters or containing a backslash, an Instance/Series Number outside
the IS range -2^31..2^31-1, a `--study-date` / `--study-time` that is not a DA / TM value) are refused: the tool exits with status 1 and writes nothing. (Until
2026-10-01 they were written as given with a warning; P-IMAGE-VR.)

### Processing Options

- `--use-exif` - Extract and use EXIF metadata from images
- `--split-pages` - Split multi-page TIFF into separate DICOM files
- `--recursive` - Process directories recursively (required for directory operations)
- `--verbose` - Verbose output with detailed progress information

### General Options

- `--version` - Show version information
- `-h, --help` - Show help information

## Supported Image Formats

- **JPEG** (.jpg, .jpeg) - Lossy compression, widely supported
- **PNG** (.png) - Lossless compression, supports transparency (converted to opaque)
- **TIFF** (.tif, .tiff) - Lossless, supports multi-page
- **BMP** (.bmp) - Uncompressed bitmap
- **GIF** (.gif) - Limited color palette

Note: Platform support varies. CoreGraphics (macOS/iOS) provides the best format support.

## DICOM Standards Compliance

### Secondary Capture Image Storage

**SOP Class UID**: 1.2.840.10008.5.1.4.1.1.7

### DICOM Modules Implemented

Every Type 1 and Type 2 attribute of the mandatory modules of PS3.3 Table A.8-1 (Secondary
Capture Image IOD) is written:

1. **Patient** (C.7.1.1, M): Patient's Name, Patient ID, Patient's Birth Date (empty), Patient's Sex (empty)
2. **General Study** (C.7.2.1, M): Study Instance UID, Study Date/Time (`--study-date` / `--study-time`;
   default: the run's start for a new Study, empty with `--study-uid`),
   Referring Physician's Name, Study ID, Accession Number (empty), Study Description (optional)
3. **General Series** (C.7.3.1, M): Series Instance UID, Modality, Series Number (empty unless given),
   Series Description (optional)
4. **General Equipment** (C.7.5.1, U): Manufacturer "DICOMKit", Manufacturer's Model Name, Software Versions
5. **SC Equipment** (C.8.6.1, M): Conversion Type (`--conversion-type`, default WSD)
6. **General Acquisition** (C.7.10.1, M): Acquisition Date/Time from EXIF (`--use-exif`)
7. **General Image** (C.7.6.1, M): Instance Number, Patient Orientation (empty, Type 2C)
8. **Image Pixel** (C.7.6.3, M): Samples per Pixel 1 or 3, Photometric Interpretation MONOCHROME2 or RGB,
   Rows, Columns, Bits Allocated 8, Bits Stored 8, High Bit 7, Pixel Representation 0,
   Planar Configuration 0 (RGB), Pixel Data
9. **SC Image** (C.8.6.2, M): Date / Time of Secondary Capture (time of conversion), Nominal Scanned
   Pixel Spacing from the image DPI (`--use-exif`)
10. **SOP Common** (C.12.1, M): SOP Class UID, SOP Instance UID (also in Media Storage SOP Instance
    UID (0002,0003), PS3.10 Table 7.1-1), Instance Creation Date / Time (time of conversion),
    Specific Character Set "ISO_IR 192" when a text value is not ASCII

Images with more than 8 bits per sample (e.g. 16-bit PNG) are reduced to 8 bits; alpha is composited on white.

Reference: **PS3.3 A.8.1 - Secondary Capture Image IOD**

## Examples

### Example 1: Convert Clinical Photo

```bash
dicom-image clinical_photo.jpg --output photo.dcm \
  --patient-name "SMITH^JOHN" \
  --patient-id "12345" \
  --study-description "Dermatology" \
  --series-description "Skin Lesion Documentation"
```

### Example 2: Batch Convert with EXIF

```bash
dicom-image photos/ --output dicoms/ --recursive \
  --patient-name "PATIENT^TEST" \
  --patient-id "TEST001" \
  --use-exif \
  --series-description "Clinical Photography" \
  --verbose
```

Output:
```
Converting images from: photos/
Output directory: dicoms/

✓ photo1.jpg → photo1.dcm
✓ photo2.jpg → photo2.dcm
✓ photo3.png → photo3.dcm

Conversion complete:
  Successful: 3
  Study UID: 2.25.1738903123456789.123456
  Series UID: 2.25.1738903123456789.654321
  Output directory: dicoms/
```

### Example 3: Multi-Page TIFF

```bash
dicom-image document.tiff --output frames/ \
  --split-pages \
  --patient-name "DOC^TEST" \
  --patient-id "DOC001" \
  --study-description "Document Imaging" \
  --verbose
```

Output:
```
Splitting multi-page TIFF: document.tiff
Pages: 5
Output directory: frames/

✓ Page 1 → frame_0001.dcm
✓ Page 2 → frame_0002.dcm
✓ Page 3 → frame_0003.dcm
✓ Page 4 → frame_0004.dcm
✓ Page 5 → frame_0005.dcm

Multi-page TIFF conversion complete:
  Pages: 5
  Output directory: frames/
```

### Example 4: Custom UIDs and Numbering

```bash
dicom-image image.png --output image.dcm \
  --patient-name "CUSTOM^UID" \
  --patient-id "UID001" \
  --study-uid "1.2.840.113619.2.55.3.123456789" \
  --series-uid "1.2.840.113619.2.55.3.123456789.1" \
  --series-number 1 \
  --instance-number 1 \
  --modality "XC"
```

## Color Space Handling

- **Grayscale images** → MONOCHROME2, 1 Sample Per Pixel
- **RGB images** → RGB, 3 Samples Per Pixel, Planar Configuration 0
- **RGBA images** → Converted to RGB (alpha composited onto white, then removed)
- **CMYK images** → Converted to RGB
- **Indexed color** → Converted to RGB

All output is 8-bit per sample.

## Auto-Generated Metadata

When not specified, the following metadata is auto-generated:

- **Study Instance UID**: Generated using timestamp and random component (format: 2.25.{timestamp}{random})
- **Series Instance UID**: Generated using timestamp and random component
- **SOP Instance UID**: Auto-generated for each DICOM instance
- **Study Date/Time**: The date and time the run started, for a new Study (empty with `--study-uid`)
- **Instance Creation Date/Time, Date/Time of Secondary Capture**: When each instance is converted
- **Modality**: "OT" (Other) if not specified
- **Output filename**: Input filename with .dcm extension

## Limitations

- Output is always 8-bit per sample (high bit depth images are converted)
- No support for YCbCr color space in output
- EXIF orientation tag is not applied (images stored as-is)
- Maximum practical image size depends on available memory
- Platform-dependent format support (best on macOS)

## Performance

- **Single image**: < 1 second for typical images (1-5 MP)
- **Large images**: 10+ MP may take a few seconds
- **Batch operations**: Scales linearly with number of images
- **Memory usage**: Peak ~2-3x the uncompressed image size

## Integration with PACS

Created DICOM files can be:

- Stored on PACS using `dicom-send`
- Queried with `dicom-query`
- Converted with `dicom-convert`
- Validated with `dicom-validate`

## Error Handling

Common errors and solutions:

### "Input path not found"

Ensure the input file or directory path is correct and accessible.

### "Patient Name is required for conversion"

Both `--patient-name` and `--patient-id` are mandatory for DICOM creation.

### "Failed to load image file"

The file may not be a valid image or the format is not supported on this platform.

### "Directory processing requires --recursive flag"

Use `--recursive` when processing directories.

## Troubleshooting

### Image appears rotated in DICOM viewer

EXIF orientation is not applied during conversion. Rotate the source image before conversion.

### Colors look different

Color space conversion may cause slight color shifts. For critical color accuracy, use PNG (lossless).

### Large batch conversion is slow

This is expected. Consider processing in parallel batches or using faster storage.

## See Also

- **dicom-convert**: Convert DICOM transfer syntaxes and export images
- **dicom-send**: Send DICOM files to PACS
- **dicom-validate**: Validate DICOM conformance
- **dicom-info**: Display DICOM metadata

## Version

v1.1.6 (Phase 3: Format Conversion Tools)

## License

See LICENSE file in repository root.

## Author

Part of DICOMKit - A pure Swift DICOM toolkit for Apple platforms.
