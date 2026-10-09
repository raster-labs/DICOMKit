# dicom-split

Extract individual frames from multi-frame DICOM files.

## Features

- **Multi-Frame Support**: Works with Enhanced CT/MR/PET/XA/XRF, Legacy Converted Enhanced, ultrasound, nuclear medicine, and other multi-frame SOP Classes
- **SOP Class Conversion**: Enhanced and Legacy Converted Enhanced objects become single-frame CT / MR / Positron Emission Tomography / X-Ray Angiographic / X-Ray Radiofluoroscopic Image Storage instances (`--target`)
- **Flexible Frame Selection**: Extract all frames or specific ranges (e.g., "1,3,5-10")
- **Multiple Output Formats**: DICOM, PNG, JPEG, or TIFF
- **Window/Level Application**: Apply windowing for proper image visualization
- **Custom Naming**: Flexible file naming patterns with variables
- **Batch Processing**: Process entire directories recursively
- **Metadata Preservation**: Shared and Per-Frame Functional Groups Sequences (PS3.3 C.7.6.16) are flattened into each extracted frame
- **Concatenations**: `--frames-per N` writes Concatenation parts (PS3.3 7.5.1, C.7.6.16) that keep the SOP Class

## Usage

### Extract All Frames to DICOM Files

```bash
dicom-split multiframe.dcm --output frames/
```

### Extract Specific Frames

```bash
# Extract Frame numbers 2, 6 and 11-16 (numbered from 1)
dicom-split multiframe.dcm --frame-numbers 2,6,11-16 --output selected/
# (deprecated, 0-based: --frames 1,5,10-15 selects the same frames)
```

### Extract as PNG Images

```bash
dicom-split ct-multiframe.dcm \
  --format png \
  --output images/
```

### Extract with Window/Level

```bash
dicom-split ct-multiframe.dcm \
  --format png \
  --apply-window \
  --window-center 40 \
  --window-width 400 \
  --output images/
```

### Use Stored Window Settings

```bash
dicom-split ct-multiframe.dcm \
  --format png \
  --apply-window \
  --output images/
```

### Custom File Naming

```bash
dicom-split multiframe.dcm \
  --output frames/ \
  --pattern "frame_{number:04d}_{modality}.dcm"
```

Available naming variables:
- `{number}` / `{number:04d}` - 0-based frame index (0-padded to 4 digits by default)
- `{instance}` - Instance Number (0020,0013) assigned to the frame (see `--instance-number`)
- `{stack}` - Stack ID (0020,9056) of the frame
- `{modality}` - Modality (0008,0060) (e.g., CT, MR, US; OT when absent)
- `{series}` - Series Number (0020,0011)

### Batch Processing

Process all DICOM files in a directory:

```bash
dicom-split studies/ \
  --output split_studies/ \
  --recursive \
  --verbose
```

### Export JPEG Images

```bash
dicom-split multiframe.dcm \
  --format jpeg \
  --apply-window \
  --output images/
```

### Export TIFF Images

```bash
dicom-split multiframe.dcm \
  --format tiff \
  --apply-window \
  --output images/
```

## Options

- `input` - Input DICOM file or directory
- `--output` - Output directory for extracted frames (default: current directory)
- `--frame-numbers` - Frame numbers to extract, numbered from 1 (e.g., '1,3,5-10'; default: all)
- `--frames` - **Deprecated** (stderr warning on use): 0-based frame indices (e.g., '0,2,4-9'); use `--frame-numbers`. Giving both exits 1
- `--format` - Output format: dicom, png, jpeg, tiff (default: dicom)
- `--apply-window` - Apply window/level settings to image output
- `--window-center` - Window center for image rendering
- `--window-width` - Window width for image rendering
- `--pattern` - Naming pattern for output files (variables: {number}, {number:04d}, {instance}, {stack}, {modality}, {series})
- `--target` - SOP Class of the extracted frames: auto (the single-frame class when one exists), same (keep the source SOP Class), classic (require a single-frame class) (default: auto)
- `--pixel-handling` - Encapsulated sources: preserve (keep the transfer syntax, one frame per instance) or decode (to Explicit VR Little Endian) (default: preserve)
- `--private-groups` - Private Sequences in the Shared / Per-Frame Functional Groups Sequence items: flatten, keep, drop (default: flatten)
- `--instance-number` - Instance Number (0020,0013): frame (1-based Frame number), instack (In-Stack Position Number (0020,9057)), original (default: frame)
- `--split-by` - One series per: none, stack (Stack ID (0020,9056)), temporal (Temporal Position Index (0020,9128)) (default: none)
- `--new-series` - Mint a new Series Instance UID (0020,000E)
- `--frames-per` - Write Concatenation parts of N frames (Concatenation UID (0020,9161), In-concatenation Number (0020,9162), Concatenation Frame Offset Number (0020,9228)); the SOP Class is kept
- `--random-uids` - Random SOP / Series Instance UIDs instead of ones derived from the source
- `-r, --recursive` - Recursively process directories
- `-v, --verbose` - Show verbose output

## Supported DICOM Formats

- **Enhanced IODs (Multi-frame Functional Groups)**: Enhanced CT / MR / PET / XA / XRF Image Storage, Legacy Converted Enhanced CT / MR / PET Image Storage
- **Multi-frame IODs without functional groups**: Ultrasound Multi-frame Image Storage, Nuclear Medicine Image Storage, X-Ray Angiographic / X-Ray Radiofluoroscopic Image Storage, RT Image Storage
- **Multi-frame Secondary Capture**: Multi-frame Single Bit / Grayscale Byte / Grayscale Word / True Color Secondary Capture Image Storage
- **Any DICOM file with Number of Frames (0028,0008) > 1**

## Frame Numbering

DICOM numbers frames from 1 ("Frames are implicitly numbered starting from 1",
PS3.3 C.7.6.16.1.2; Referenced Frame Number (0008,1160), PS3.3 Table 10-3, uses the same numbering).
`--frame-numbers` and the verbose progress lines ("Extracted Frame number N") use that numbering.
The deprecated `--frames` and the `{number}` naming variable use 0-based **indices** instead:
- First frame: index 0 = Frame number 1
- Second frame: index 1 = Frame number 2
- etc.

With `--instance-number frame` (the default) the Instance Number of each output is
the 1-based Frame number.

## Window/Level Application

### Custom Window Settings

Specify exact window center and width:

```bash
dicom-split ct.dcm \
  --format png \
  --apply-window \
  --window-center 40 \
  --window-width 400 \
  --output images/
```

### Stored Window Settings

Use window settings stored in the DICOM file:

```bash
dicom-split ct.dcm \
  --format png \
  --apply-window \
  --output images/
```

If no window settings are found, defaults will be used based on pixel value range.

## Examples

### Extract CT Multi-Frame Study

```bash
# Extract all frames as windowed PNG images
dicom-split ct-chest-multiframe.dcm \
  --format png \
  --apply-window \
  --window-center 40 \
  --window-width 400 \
  --output ct_frames/ \
  --verbose
```

### Extract Ultrasound Cine Loop

```bash
# Extract Frame numbers 11-51 from ultrasound cine
dicom-split us-cine.dcm \
  --frame-numbers 11-51 \
  --format png \
  --output us_frames/ \
  --pattern "us_{number:04d}.png"
```

### Batch Process MR Series

```bash
# Process all multi-frame MR files in a directory
dicom-split mr_studies/ \
  --output split_mr/ \
  --recursive \
  --format dicom \
  --verbose
```

### Extract Key Frames

```bash
# Extract specific diagnostic frames (Frame numbers 1, 11, 21, 31, 41)
dicom-split multiframe.dcm \
  --frame-numbers 1,11,21,31,41 \
  --format jpeg \
  --apply-window \
  --output key_frames/
```

## Exit Codes

- `0` - Success (non-DICOM and single-frame inputs are skipped, not failures)
- `1` - At least one frame could not be extracted
- `64` - Usage error (invalid option value, input not found, output is not a directory)

## Notes

- Each extracted DICOM frame gets a new SOP Instance UID, derived from the source by default (`--random-uids` for random ones)
- Original metadata (patient info, Study Instance UID, Series Instance UID unless `--new-series` / `--split-by`) is preserved
- Pixel data is extracted as-is for DICOM output (encapsulated frames keep their transfer syntax unless `--pixel-handling decode`)
- Image formats (PNG, JPEG, TIFF) apply rendering and windowing
- Multi-frame files with only 1 frame are skipped
- Non-DICOM files in directories are automatically skipped

## See Also

- `dicom-merge` - Combine single frames into multi-frame files
- `dicom-info` - Display DICOM metadata including frame count
- `dicom-convert` - Convert DICOM files between transfer syntaxes
