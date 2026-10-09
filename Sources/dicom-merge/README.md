# dicom-merge

Combine single-frame DICOM images into multi-frame files.

## Overview

`dicom-merge` combines multiple single-frame DICOM images into multi-frame DICOM files. It supports keeping the source SOP Class (`standard`) or writing Enhanced CT / MR / PET / XA / XRF, Legacy Converted Enhanced CT / MR / PET, Ultrasound Multi-frame and Multi-frame Secondary Capture objects, with Shared and Per-Frame Functional Groups Sequences (PS3.3 C.7.6.16) for the Enhanced and Legacy Converted targets. The tool can also organize files by series or study.

## Features

- **Single-to-Multi-Frame Conversion**: Combine single frames into a single multi-frame file
- **Series Merging**: Group files by Series Instance UID and create one multi-frame file per series
- **Study Merging**: Group files by Study Instance UID, then by series
- **Frame Sorting**: Order frames by Instance Number, Image Position (Patient), or Acquisition Time
- **Consistency Validation**: Verify that input files have compatible attributes
- **Metadata Consolidation**: Automatically merge and update DICOM metadata
- **UID Generation**: Generate unique SOP Instance UIDs for merged files

## Usage

### Basic Usage

Combine single frames into multi-frame:
```bash
dicom-merge frame_001.dcm frame_002.dcm frame_003.dcm --output multiframe.dcm
```

Using wildcard expansion:
```bash
dicom-merge frame_*.dcm --output multiframe.dcm
```

### Frame Sorting

Sort by Instance Number (default):
```bash
dicom-merge slices/*.dcm --output volume.dcm
```

Sort by Image Position (Patient) (distance along the slice normal):
```bash
dicom-merge slices/*.dcm --output volume.dcm --sort-by ImagePositionPatient
```

Sort by Acquisition Time:
```bash
dicom-merge slices/*.dcm --output volume.dcm --sort-by AcquisitionTime
```

Descending order:
```bash
dicom-merge slices/*.dcm --output volume.dcm --order descending
```

### Series and Study Merging

Merge by series (one file per series):
```bash
dicom-merge study_dir/ --output merged/ --level series --recursive
```

Merge by study (organized by study and series):
```bash
dicom-merge data/ --output organized/ --level study --recursive
```

### Enhanced Formats

Create Enhanced CT Image Storage:
```bash
dicom-merge ct_slices/*.dcm --output enhanced_ct.dcm --format enhanced-ct
```

Create Enhanced MR Image Storage, one Stack ID per Image Orientation (Patient):
```bash
dicom-merge mr_slices/*.dcm --output enhanced_mr.dcm --format enhanced-mr --make-stacks
```

Let the tool pick the multi-frame SOP Class from the source (CT/MR/PET -> Legacy Converted
Enhanced, Ultrasound -> Ultrasound Multi-frame, Secondary Capture -> Multi-frame SC):
```bash
dicom-merge slices/*.dcm --output volume.dcm --format auto
```

| `--format` | SOP Class (PS3.6 Table A-1) |
|---|---|
| `standard` | the source SOP Class is kept (only conformant when that IOD is multi-frame) |
| `auto` | chosen from the source SOP Class |
| `enhanced-ct` | Enhanced CT Image Storage (1.2.840.10008.5.1.4.1.1.2.1) |
| `enhanced-mr` | Enhanced MR Image Storage (1.2.840.10008.5.1.4.1.1.4.1) |
| `enhanced-pet` | Enhanced PET Image Storage (1.2.840.10008.5.1.4.1.1.130) |
| `enhanced-xa` | Enhanced XA Image Storage (1.2.840.10008.5.1.4.1.1.12.1.1) |
| `enhanced-xrf` | Enhanced XRF Image Storage (1.2.840.10008.5.1.4.1.1.12.2.1) |
| `legacy-converted-ct` | Legacy Converted Enhanced CT Image Storage (1.2.840.10008.5.1.4.1.1.2.2) |
| `legacy-converted-mr` | Legacy Converted Enhanced MR Image Storage (1.2.840.10008.5.1.4.1.1.4.4) |
| `legacy-converted-pet` | Legacy Converted Enhanced PET Image Storage (1.2.840.10008.5.1.4.1.1.128.1) |
| `us-multiframe` | Ultrasound Multi-frame Image Storage (1.2.840.10008.5.1.4.1.1.3.1) |
| `sc-multiframe` | Multi-frame Single Bit / Grayscale Byte / Grayscale Word / True Color Secondary Capture Image Storage (1.2.840.10008.5.1.4.1.1.7.1 - .7.4, by Bits Allocated and Samples per Pixel) |

### Validation

Validate consistency before merging:
```bash
dicom-merge slices/*.dcm --output volume.dcm --validate
```

### Verbose Output

Show detailed processing information:
```bash
dicom-merge slices/*.dcm --output volume.dcm --verbose
```

## Options

### Required
- `<inputs>...` - Input DICOM files or directories

### Optional
- `-o, --output <path>` - Output file or directory path
- `--format <format>` - Output format: standard, auto, enhanced-ct, enhanced-mr, enhanced-pet, enhanced-xa, enhanced-xrf, legacy-converted-ct, legacy-converted-mr, legacy-converted-pet, sc-multiframe, us-multiframe (default: standard)
- `--pixel-handling <mode>` - Encapsulated inputs: preserve (keep the transfer syntax, one fragment per frame with a Basic Offset Table, PS3.5 A.4) or decode (to Explicit VR Little Endian) (default: preserve)
- `--make-stacks` - Assign Stack ID (0020,9056) per Image Orientation (Patient) (0020,0037)
- `--temporal-position` - Derive Temporal Position Index (0020,9128) from Trigger Time (0018,1060), Temporal Position Identifier (0020,0100) or Acquisition Time (0008,0032)
- `--new-series` - Mint a new Series Instance UID (0020,000E)
- `--allow-any-source` - Skip the source SOP Class check for Enhanced / Legacy Converted targets
- `--level <level>` - Merge level: file, series, study (default: file)
- `--sort-by <criteria>` - Sort frames by: InstanceNumber, ImagePositionPatient, AcquisitionTime, none (default: InstanceNumber)
- `--order <order>` - Sort order: ascending, descending (default: ascending)
- `--validate` - Also require equal Study / Series Instance UID, Modality and Frame of Reference UID
- `-r, --recursive` - Process directories recursively
- `-v, --verbose` - Show verbose output

## Merge Levels

### File Level (default)
Combines all input files into a single multi-frame DICOM file.

```bash
dicom-merge frame_*.dcm --output merged.dcm
```

### Series Level
Groups files by Series Instance UID and creates one multi-frame file per series.

```bash
dicom-merge study/ --output output/ --level series
```

Output structure:
```
output/
├── series_1.2.840.113619.2.134.dcm
├── series_1.2.840.113619.2.135.dcm
└── series_1.2.840.113619.2.136.dcm
```

### Study Level
Groups files by Study Instance UID, then by series. Creates a directory per study containing multi-frame files per series.

```bash
dicom-merge data/ --output output/ --level study
```

Output structure:
```
output/
├── study_1.2.840.113619.2.1/
│   ├── series_1.2.840.113619.2.1.1.dcm
│   └── series_1.2.840.113619.2.1.2.dcm
└── study_1.2.840.113619.2.2/
    ├── series_1.2.840.113619.2.2.1.dcm
    └── series_1.2.840.113619.2.2.2.dcm
```

## Sort Criteria

### Instance Number
Sorts frames by the DICOM Instance Number attribute (0020,0013). This is the default.

### Image Position (Patient)
Sorts frames by the distance along the slice normal derived from Image Position (Patient) (0020,0032) and Image Orientation (Patient) (0020,0037), or by the Z coordinate (third value) when the orientation is absent. Useful for CT/MR volumes where slices have spatial positions.

### Acquisition Time
Sorts frames by Acquisition Time (0008,0032). Useful for temporal sequences.

### None
Preserves the order in which files were provided.

## Validation

Every run checks that the inputs agree on the Image Pixel Module attributes (Rows, Columns,
Bits Allocated, Bits Stored, High Bit, Pixel Representation, Samples per Pixel, Photometric
Interpretation), the pixel data size, the Transfer Syntax UID, and that no SOP Instance UID
occurs twice.

When `--validate` is enabled, the tool also checks:

- Study Instance UID
- Series Instance UID
- Modality
- Frame of Reference UID

If any inconsistencies are found, the tool reports an error and does not create output.

## Examples

### Example 1: Combine CT Slices

Combine CT slices into a single multi-frame file, sorted by position:

```bash
dicom-merge ct_slices/*.dcm \
  --output ct_volume.dcm \
  --sort-by ImagePositionPatient \
  --validate \
  --verbose
```

### Example 2: Organize Multi-Series Study

Process a study directory containing multiple series, creating one multi-frame file per series:

```bash
dicom-merge study_20240101/ \
  --output organized/ \
  --level series \
  --recursive \
  --verbose
```

### Example 3: Process Multiple Studies

Process multiple studies, organizing by study and series:

```bash
dicom-merge patient_data/ \
  --output processed/ \
  --level study \
  --recursive \
  --validate
```

## Technical Details

### DICOM Compliance

- Generates valid DICOM Part 10 files
- Updates Number of Frames (0028,0008) attribute
- Generates a new SOP Instance UID for the merged object
- Concatenates native pixel data from all frames; encapsulated frames are carried as one fragment per frame with a Basic Offset Table (PS3.5 A.4)
- Preserves most metadata from the first input file
- Updates Instance Number (0020,0013) to 1 (multi-frame files are single instances)
- Enhanced and Legacy Converted targets: Shared / Per-Frame Functional Groups Sequences (PS3.3 C.7.6.16) factored by attribute equality, Frame Content Macro (Stack ID, In-Stack Position Number, Dimension Index Values), Multi-frame Dimension Module (PS3.3 C.7.6.17)
- Concatenation parts (Concatenation UID (0020,9161)) are detected and reassembled

### Limitations

- `--format standard` on a single-frame IOD (e.g. CT Image Storage) merges with a warning; that object is not conformant — use `--format auto`
- Frame de-duplication and metadata merging strategies are not implemented

## Exit Codes

- `0` - Success
- `1` - Merge failed (inconsistent inputs, unsupported source SOP Class, duplicate SOP Instance UID, file I/O errors)
- `64` - Usage error (invalid option value, input path not found, no DICOM files found)

## See Also

- `dicom-split` - Extract individual frames from multi-frame files
- `dicom-info` - Display DICOM metadata
- `dicom-validate` - Validate DICOM conformance
- `dicom-convert` - Convert transfer syntaxes

## Version

1.1.2 (Phase 2)
