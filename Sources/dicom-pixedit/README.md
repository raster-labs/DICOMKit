# dicom-pixedit

A DICOM pixel data manipulation CLI tool (v1.3.0).

## Features

- **Mask regions** – black out burned-in annotations or other rectangular areas
- **Crop** – extract a region of interest from the image
- **Window/Level** – permanently bake window/level into pixel data
- **Invert** – invert pixel values (e.g., for photometric conversion)

## Usage

```bash
# Mask a region (e.g., burned-in patient name)
dicom-pixedit file.dcm --output masked.dcm --mask-region 0,0,200,50

# Mask with a specific fill value
dicom-pixedit file.dcm --output masked.dcm --mask-region 0,0,200,50 --fill-value 0

# Crop to a region of interest
dicom-pixedit file.dcm --output cropped.dcm --crop 100,100,400,400

# Apply window/level permanently
dicom-pixedit ct.dcm --output windowed.dcm --window-center 40 --window-width 400 --apply-window

# Invert pixel values
dicom-pixedit file.dcm --output inverted.dcm --invert

# Combine operations with verbose output
dicom-pixedit file.dcm --output edited.dcm --mask-region 0,0,200,50 --invert --verbose
```

## Options

| Option | Description |
|---|---|
| `--output` | Output DICOM file path (required) |
| `--mask-region` | Region to mask as `x,y,width,height` (0-based column, row) |
| `--fill-value` | Stored value for masked samples (default: 0); must lie in the range of Bits Stored (0028,0101) and Pixel Representation (0028,0103) (PS3.3 C.7.6.3.1), otherwise the tool exits 1 and writes nothing (until 2026-10-01 it was clamped with a warning; P-PIXEDIT-RANGE) |
| `--crop` | Crop region as `x,y,width,height` (0-based column, row) |
| `--window-center` | Window Center (0028,1050) in Modality LUT output units (e.g. HU for CT) |
| `--window-width` | Window Width (0028,1051) in the same units; at least 1 (PS3.3 C.11.2.1.2), otherwise the tool exits 1 (a width in (0,1) was raised to 1 with a warning until 2026-10-01; P-PIXEDIT-RANGE) |
| `--apply-window` | Bake the window into the stored values (PS3.3 C.11.2.1.2 linear function) |
| `--invert` | Invert stored values across the Bits Stored range |
| `-v, --verbose` | Show verbose output |

Operations run in the order mask, crop, window, invert.

## Output (DICOM 2026a)

An edited image is a Derived Image (PS3.3 C.7.6.1.1.2):

- a new SOP Instance UID (0008,0018), also in Media Storage SOP Instance UID (0002,0003);
- Image Type (0008,0008) Value 1 `DERIVED` (other Values kept; `DERIVED\SECONDARY` if absent);
- Derivation Description (0008,2111) naming the operations (appended to an existing one);
- a Source Image Sequence (0008,2112) item referencing the input (Purpose of Reference
  DCM 121322 "Source image for image processing operation", CID 7202). CID 7203 has no code for
  these operations, so no Derivation Code Sequence is written;
- after a crop, Rows/Columns and Image Position (Patient) (0020,0032) of the new first pixel
  (PS3.3 C.7.6.2.1.1);
- Smallest/Largest Image Pixel Value and Smallest/Largest Pixel Value in Series removed;
- the stored window replaced after `--apply-window` / `--invert` so the result displays as baked;
- Burned In Annotation (0028,0301) and Lossy Image Compression (0028,2110) unchanged — set
  Burned In Annotation yourself if a mask removed all identifying text.

Compressed inputs are decoded and written as Explicit VR Little Endian.

## Supported Pixel Formats

- 8-bit and 16-bit pixel data
- Signed and unsigned pixel representations
- Monochrome and multi-sample (e.g., RGB) images
