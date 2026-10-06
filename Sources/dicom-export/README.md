# dicom-export

Advanced DICOM image export tool with metadata embedding, contact sheets, animation, and bulk export capabilities.

## Features

- **Single Export**: Export individual DICOM files to PNG, JPEG, or TIFF with optional EXIF metadata embedding
- **Contact Sheet**: Generate thumbnail grids from multiple DICOM files
- **Animated GIF**: Export multi-frame DICOM files as animated GIFs with configurable FPS and scaling
- **Bulk Export**: Batch export entire directories with patient/study/series organization
- **EXIF Embedding**: Map DICOM metadata fields to standard EXIF/TIFF tags
- **Windowing**: Every subcommand renders monochrome frames through the PS3.4 grayscale chain —
  Modality LUT (Rescale Slope/Intercept), the file's VOI (Window Center (0028,1050) and
  Window Width (0028,1051) with VOI LUT Function (0028,1056), else VOI LUT Sequence (0028,3010),
  else the full pixel range), then INVERSE for MONOCHROME1. `--apply-window` with `--window-center` /
  `--window-width` (modality units, LINEAR) overrides the file's VOI in `single` and `animate`.
  On `contact-sheet` and `bulk`, `--apply-window` has no effect and is **deprecated** (stderr warning on use).
- **Frame numbers**: frames are selected by Frame number, numbered from 1 (PS3.3 Table 10-3: "The first Frame
  shall be denoted as Frame number 1"): `single --frame-number`, `animate --start-frame-number` /
  `--end-frame-number`. The 0-based `--frame`, `--start-frame`, `--end-frame` still work, are **deprecated**
  and print a stderr warning; mixing a 0-based and a 1-based option exits 1.
- **Burned In Annotation**: a file whose Burned In Annotation (0028,0301) is YES gets a warning on
  stderr — its rendered pixels contain text that identifies the patient.
- The outputs (PNG, JPEG, TIFF, GIF) are not DICOM files.

## Requirements

- macOS 14+ or iOS 17+ (requires CoreGraphics and ImageIO)
- Swift 6.2+
- DICOMKit framework

## Usage

### Single Export

```bash
# Basic export
dicom-export single ct_scan.dcm --output ct_scan.jpg

# Export with EXIF metadata
dicom-export single ct_scan.dcm --output ct_scan.jpg --embed-metadata

# Export specific fields as EXIF
dicom-export single ct_scan.dcm --output ct_scan.jpg --embed-metadata --exif-fields PatientName,StudyDate,Modality

# Export with windowing
dicom-export single ct_scan.dcm --output ct_scan.png --format png --apply-window --window-center 40 --window-width 400

# Export a specific frame: Frame number 5 (numbered from 1, PS3.3 Table 10-3)
dicom-export single multi_frame.dcm --output frame5.png --format png --frame-number 5
# (deprecated, 0-based: --frame 4 selects the same frame)
```

### Contact Sheet

```bash
# Basic contact sheet
dicom-export contact-sheet file1.dcm file2.dcm file3.dcm --output sheet.png

# Custom grid layout
dicom-export contact-sheet *.dcm --output sheet.png --columns 6 --thumbnail-size 128 --spacing 2

# With labels
dicom-export contact-sheet *.dcm --output sheet.png --labels

# JPEG output with quality
dicom-export contact-sheet *.dcm --output sheet.jpg --format jpeg --quality 85
```

### Animated GIF

```bash
# Basic animation. Without --fps the rate is the file's Recommended Display Frame Rate (0008,2144),
# else Cine Rate (0018,0040), else 1000 / Frame Time (0018,1063) (msec), else 10 fps
dicom-export animate cine.dcm --output cine.gif

# Custom framerate and looping
dicom-export animate cine.dcm --output cine.gif --fps 15 --loop-count 3

# Export Frame numbers 11 to 51 (end inclusive) with scaling
dicom-export animate cine.dcm --output cine.gif --start-frame-number 11 --end-frame-number 51 --scale 0.5
# (deprecated, 0-based: --start-frame 10 --end-frame 50 selects the same frames)

# With windowing
dicom-export animate cine.dcm --output cine.gif --apply-window --window-center 40 --window-width 400
```

### Bulk Export

```bash
# Flat export
dicom-export bulk input_dir/ --output output_dir/ --format png

# Organized by patient: folder = Patient ID (0010,0020), followed by @<Issuer of Patient ID (0010,0021)>
# when the file has one (PS3.3 Table C.7-1; Patient ID is the Patient level unique key, PS3.4 Table C.6-1);
# no Patient ID gives UNKNOWN. Before 2026-10-01 the folder was named from Patient's Name (0010,0010).
# study and series add the Study Instance UID (0020,000D) and Series Instance UID (0020,000E) folders
dicom-export bulk input_dir/ --output output_dir/ --organize-by patient --recursive

# Full organization with metadata
dicom-export bulk input_dir/ --output output_dir/ --organize-by series --recursive --embed-metadata --verbose
```

`bulk` exits with status 1 after its summary line when any file failed to export (files
without Pixel Data are skipped, not failed), like `dicom-convert`'s directory run; it exits 0
only when every file exported or was skipped. Until 2026-10-06 it exited 0 whatever the
per-file outcomes (D251).

## Supported EXIF Field Mappings

`--exif-fields` takes these PS3.6 keywords (case-insensitive); any other keyword is reported with a warning and not embedded.

| DICOM Field | EXIF/TIFF Tag |
|---|---|
| PatientName | TIFF:ImageDescription |
| PatientID | EXIF:UserComment (`PatientID=<value>`) |
| StudyDate | EXIF:DateTimeOriginal, `YYYY:MM:DD HH:MM:SS` from Study Date (DA, PS3.5 Table 6.2-1) and Study Time (TM); blank time when Study Time is absent; not written when Study Date is not a DA value |
| Modality | EXIF:UserComment (`Modality=<value>`) |
| StudyDescription | TIFF:DocumentName |
| SeriesDescription | EXIF:UserComment (`SeriesDescription=<value>`) |
| InstitutionName | TIFF:Artist |
| Manufacturer | TIFF:Make |
| ManufacturerModelName | TIFF:Model |
| StationName | TIFF:HostComputer |

## Version

1.2.2
