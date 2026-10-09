# dicom-convert

Convert DICOM files between transfer syntaxes and export pixel data to image formats.

## Features

- **Transfer Syntax Conversion**: native (Explicit / Implicit VR Little Endian, Explicit VR Big Endian, Deflated) and encapsulated (JPEG, JPEG-LS, JPEG 2000, HTJ2K, JPEG XL, RLE) targets
- **Image Export**: Export DICOM pixel data to PNG, JPEG, or TIFF
- **Window/Level Application**: Apply DICOM windowing during image export
- **Batch Processing**: Convert entire directories recursively
- **Private Tag Stripping**: Remove private tags during conversion
- **Output Check**: `--validate` re-reads the written file as DICOM

## Usage

### Transfer Syntax Conversion

```bash
# Convert to Explicit VR Little Endian
dicom-convert file.dcm --output output.dcm --transfer-syntax ExplicitVRLittleEndian

# Convert to Implicit VR Little Endian
dicom-convert file.dcm --output output.dcm --transfer-syntax ImplicitVRLittleEndian

# Convert with validation
dicom-convert file.dcm --output output.dcm --transfer-syntax ExplicitVRLittleEndian --validate
```

### Image Export

```bash
# Export to PNG
dicom-convert xray.dcm --output xray.png --format png

# Export to JPEG with quality setting
dicom-convert xray.dcm --output xray.jpg --format jpeg --quality 95

# Export to TIFF
dicom-convert ct.dcm --output ct.tiff --format tiff
```

### Window/Level Application

```bash
# Apply windowing from DICOM tags
dicom-convert ct.dcm --output ct.png --apply-window

# Specify custom window center and width
dicom-convert ct.dcm --output ct.png --apply-window --window-center 40 --window-width 400
```

### Multi-frame Images

```bash
# Export Frame number 5 (frames are numbered from 1, PS3.3 Table 10-3); the default is Frame number 1
dicom-convert multiframe.dcm --output frame5.png --frame-number 5 --format png
```

### Batch Conversion

```bash
# Convert directory recursively
dicom-convert input_dir/ --output output_dir/ --transfer-syntax ExplicitVRLittleEndian --recursive

# Strip private tags during batch conversion
dicom-convert input_dir/ --output output_dir/ --transfer-syntax ExplicitVRLittleEndian --recursive --strip-private
```

## Options

- `--output, -o <path>`: Output file or directory path (required)
- `--transfer-syntax <syntax>`: Target transfer syntax: a name from `--help` (e.g. ExplicitVRLittleEndian, JPEG2000Lossy, HTJ2KLosslessOnly), a Transfer Syntax UID, or a PS3.6 Table A-1 keyword (e.g. JPEGBaseline8Bit, HTJ2KLosslessRPCL). Every Table A-1 keyword selects its Table A-1 UID. **Changed 2026-10-01:** `JPEG2000Lossless`, `HTJ2KLossless` and `JPEGXLLossless` now select .90 / .201 / .110 (a note is printed on stderr); the reversible encode into the general UIDs .91 / .203 / .112 they used to select is `JPEG2000Reversible`, `HTJ2KReversible`, `JPEGXLReversible` (or the kebab names `jpeg2000-lossless`, `htj2k-lossless`, `jpeg-xl-lossless`). A lossy target records Lossy Image Compression (0028,2110) "01", Ratio, Method and Image Type DERIVED (PS3.3 C.7.6.1.1.5)
- `--format <format>`: Output format: png, jpeg, tiff, dicom (default: dicom)
- `--quality <1-100>`: JPEG quality for `--format jpeg` (default: 90; values outside 1-100 are refused)
- `--apply-window`: Apply window/level during export
- `--window-center <value>`: Window Center (0028,1050) for export
- `--window-width <value>`: Window Width (0028,1051) for export; at least 1 (PS3.3 C.11.2.1.2.1)
- `--frame-number <n>`: Export Frame number n; frames are numbered from 1 (PS3.3 Table 10-3)
- `--frame <index>`: **Deprecated** 0-based index (`--frame 0` = Frame number 1); prints a deprecation note. Giving both `--frame` and `--frame-number` exits 1
- `--recursive`: Process directories recursively
- `--strip-private`: Remove private (odd group) Data Elements of the top-level Data Set
- `--validate`: Validate output after conversion
- `--force`: Force parsing of files without DICM prefix

## Examples

### CT Scan Window/Level

```bash
# Lung window (center=-600, width=1500)
dicom-convert ct.dcm --output ct-lung.png --apply-window --window-center -600 --window-width 1500

# Bone window (center=300, width=1500)
dicom-convert ct.dcm --output ct-bone.png --apply-window --window-center 300 --window-width 1500

# Soft tissue window (center=40, width=400)
dicom-convert ct.dcm --output ct-soft.png --apply-window --window-center 40 --window-width 400
```

### Strip Private Data Elements

```bash
# Convert and remove top-level private Data Elements (this is not de-identification:
# use dicom-anon for the PS3.15 Annex E profile)
dicom-convert study/ --output stripped/ --transfer-syntax ExplicitVRLittleEndian --recursive --strip-private
```

### Transfer Syntax Normalization

```bash
# Normalize mixed transfer syntaxes to standard format
dicom-convert mixed_data/ --output normalized/ --transfer-syntax ExplicitVRLittleEndian --recursive --validate
```

## Exit Codes

- `0`: Success
- `1`: Conversion or export failed — a single file, or any file of a directory run (each failed file is reported); also `--frame` given with `--frame-number`
- `64`: Invalid arguments, or the input path does not exist

## Platform Support

Image export (PNG, JPEG, TIFF) requires CoreGraphics and is available on:
- macOS 14+
- iOS 17+
- visionOS 1+

Transfer syntax conversion works on all platforms.

## See Also

- `dicom-info`: Display DICOM metadata
- `dicom-anon`: Anonymize DICOM files
- `dicom-validate`: Validate DICOM files
