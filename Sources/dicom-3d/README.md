# dicom-3d — 3D Reconstruction, MPR, and JP3D Volumetric Encoding

**Version:** 1.5.0  
**Part of:** DICOMKit CLI Tools (Phases 7 + 9.2)

## Overview

`dicom-3d` performs 3D volume reconstruction, Multi-Planar Reformation (MPR), intensity projections, JP3D volumetric encode/decode, and format export from multi-slice DICOM series.

## Features

### Multi-Planar Reformation (MPR)
- **Axial, Sagittal, Coronal** reformations, named in the patient (LPS) coordinate
  system of PS3.3 C.7.6.2.1.1 whatever the acquisition plane
- **Oblique** MPR: `--planes oblique --oblique-normal x,y,z [--oblique-point x,y,z]` (patient LPS
  coordinates, mm), one image sampled with PS3.3 C.7.6.2.1.1 Equation C.7.6.2.1-1; its Image
  Orientation (Patient) / Image Position (Patient) describe the oblique plane in `--format dcm`
- Curved MPR: not available
- Axial/sagittal/coronal planes are cut along the voxel grid (the volume axis closest to each LPS
  axis): no resampling, so `--interpolation` affects oblique planes only
- Configurable slice thickness (thick-slab averaging)
- `--format dcm`: derived DICOM series (Image Type `DERIVED\SECONDARY`, Derivation Code
  DCM 113072 "Multiplanar reformatting", Source Image Sequence, plane geometry)

### Intensity Projections
- **Maximum Intensity Projection (MIP)** - highlight bright structures
- **Minimum Intensity Projection (MinIP)** - highlight dark structures
- **Average Intensity Projection** - mean values along projection axis
- Configurable slab thickness for focused projections

### 3D Surface Extraction
- **Marching Cubes** algorithm for isosurface extraction
- Export to **STL** and **OBJ** formats
- Customizable threshold values
- Suitable for 3D printing and visualization

### Volume Export
- **NIfTI** format (.nii) — neuroimaging standard
- **MetaImage** format (.mhd + .raw) — ITK/VTK compatible
- Preserves spatial information and metadata

### JP3D Volumetric Encoding (J2KSwift v3.2.0)
- **encode-volume** — encode a slice series as a single JP3D DICOM document
- **decode-volume** — decode a JP3D document back to individual DICOM slices
- **inspect** — display JP3D sidecar metadata without decoding the codestream
- Compression modes: lossless, lossless-htj2k (~5× faster decode), lossy, lossy-htj2k
- Uses ISO/IEC 15444-10 (JP3D) via J2KSwift 3.2.0; experimental private SOP only

## Installation

```bash
swift build -c release
.build/release/dicom-3d --help
```

## Usage

### Multi-Planar Reformation

Generate axial, sagittal, and coronal reformations:

```bash
dicom-3d mpr series/*.dcm --output mpr/ --planes axial,sagittal,coronal
```

Generate only sagittal slices:

```bash
dicom-3d mpr series/*.dcm --output sagittal/ --planes sagittal
```

An oblique plane through a point, as a derived DICOM image (normal and point in LPS mm):

```bash
dicom-3d mpr series/*.dcm --output obl/ --planes oblique \
  --oblique-normal 0,1,1 --oblique-point 0,-20,35 --format dcm
```

With custom windowing:

```bash
dicom-3d mpr ct-series/*.dcm \
  --output mpr/ \
  --planes axial,sagittal,coronal \
  --window-center -600 \
  --window-width 1500
```

### Maximum Intensity Projection (MIP)

Generate MIP along axial direction:

```bash
dicom-3d mip series/*.dcm --output mip.png
```

MIP with slab thickness (20mm):

```bash
dicom-3d mip series/*.dcm \
  --output mip.png \
  --thickness 20 \
  --direction axial
```

Sagittal MIP:

```bash
dicom-3d mip series/*.dcm \
  --output mip-sagittal.png \
  --direction sagittal
```

### Minimum Intensity Projection (MinIP)

```bash
dicom-3d minip series/*.dcm \
  --output minip.png \
  --direction coronal \
  --thickness 10
```

### Average Intensity Projection

```bash
dicom-3d average series/*.dcm \
  --output average.png \
  --direction axial
```

### Surface Extraction

Extract isosurface at threshold 200 (e.g., bone in CT):

```bash
dicom-3d surface series/*.dcm \
  --output surface.stl \
  --threshold 200
```

Export as OBJ format:

```bash
dicom-3d surface series/*.dcm \
  --output model.obj \
  --threshold 150 \
  --format obj
```

### JP3D Volumetric Encoding

Encode a series directory as a lossless JP3D document:

```bash
dicom-3d encode-volume ./series/ --output volume.jp3d.dcm
```

Encode with HTJ2K lossless (~5× faster decode):

```bash
dicom-3d encode-volume series/*.dcm --output volume.jp3d.dcm --mode lossless-htj2k
```

Encode with lossy compression at 55 dB PSNR:

```bash
dicom-3d encode-volume series/*.dcm --output volume.jp3d.dcm --mode lossy --psnr 55
```

Decode back to individual slices:

```bash
dicom-3d decode-volume volume.jp3d.dcm --output ./decoded/
```

Inspect metadata without decoding the codestream:

```bash
dicom-3d inspect volume.jp3d.dcm
dicom-3d inspect volume.jp3d.dcm --json
```

### Volume Export

Export as NIfTI:

```bash
dicom-3d export series/*.dcm \
  --output volume \
  --formats nifti
```

Export as MetaImage:

```bash
dicom-3d export series/*.dcm \
  --output volume \
  --formats metaimage
```

Export both formats:

```bash
dicom-3d export series/*.dcm \
  --output volume \
  --formats nifti,metaimage
```

## Options

### Common Options

- `--verbose` - Enable verbose output for debugging
- `--window-center <value>` - Window Center for display (Modality LUT output units, e.g. Hounsfield units for CT)
- `--window-width <value>` - Window Width for display; >= 1, applied with the LINEAR VOI LUT function (PS3.3 C.11.2.1.2.1). MONOCHROME1 data are shown inverted (C.7.6.3.1.2)

### MPR Options

- `--planes <list>` - Comma-separated list: axial, sagittal, coronal, oblique
- `--oblique-normal <x,y,z>` - Normal of the oblique plane in the patient (LPS) system (x to patient
  left, y to posterior, z to head); required with `oblique`, need not be unit length
- `--oblique-point <x,y,z>` - A point on the oblique plane, mm (LPS); default: the centre of the volume.
  The output grid has a pixel centre on this point; Pixel Spacing is the smaller in-plane source
  spacing; the image covers the volume's projection on the plane, outside samples take the volume
  minimum. Row/column directions follow the patient plane whose normal is closest to the given normal
- `--thickness <mm>` - Slice thickness in millimeters: consecutive planes are averaged into slabs
  (oblique: samples along the normal averaged over this thickness)
- `--interpolation <method>` - Interpolation of oblique planes: nearest, linear (trilinear; default).
  `cubic` is **deprecated** and uses linear (a note is printed). Axial/sagittal/coronal planes are
  voxel-aligned and not resampled
- `--format <fmt>` - Output format: png, dcm (default: png)

### Projection Options

- `--direction <dir>` - Projection direction: axial, sagittal, coronal
- `--thickness <mm>` - Slab thickness in mm, centred on the middle of the volume (0 = full volume; mip and minip)

### Surface Options

- `--threshold <value>` - Threshold for surface extraction
- `--format <fmt>` - Output format: stl, obj (default: stl)

### Export Options

- `--formats <list>` - Comma-separated: nifti, metaimage

## Examples

### CT Chest MIP

```bash
# Load CT chest series and create MIP for vessel visualization
dicom-3d mip ct-chest/*.dcm \
  --output chest-mip.png \
  --direction axial \
  --window-center 40 \
  --window-width 400 \
  --verbose
```

### Spine Sagittal Reformation

```bash
# Generate sagittal reformations of spine
dicom-3d mpr spine-ct/*.dcm \
  --output spine-sagittal/ \
  --planes sagittal \
  --window-center 40 \
  --window-width 400
```

### Bone Surface for 3D Printing

```bash
# Extract bone surface and save as STL
dicom-3d surface skull-ct/*.dcm \
  --output skull.stl \
  --threshold 200 \
  --verbose
```

### Brain Volume Export

```bash
# Export brain MRI as NIfTI for analysis
dicom-3d export brain-mri/*.dcm \
  --output brain \
  --formats nifti \
  --verbose
```

## Technical Details

### Volume Loading

- Sorts slices by Image Position (Patient) along the normal of Image Orientation (Patient), not by Instance Number
- Pixel Spacing value 1 is the spacing between rows, value 2 between columns (PS3.3 Table C.7-10)
- Slice spacing is the mean centre-to-centre distance along the normal (Spacing Between Slices, then Slice Thickness, for a single slice)
- Rejects slices with different Frame of Reference UIDs, orientations or matrix sizes
- Enhanced multi-frame input: per-frame Plane Position / Plane Orientation / Pixel Measures functional groups
- Applies each slice's Rescale Slope/Intercept (e.g., Hounsfield units)

### Interpolation Methods

Used only for oblique planes (axial/sagittal/coronal are voxel-aligned, not resampled):

- **Nearest**: Fast, preserves original values
- **Linear**: Trilinear, smooth (default)
- **Cubic**: Deprecated — no cubic kernel exists; it uses linear and prints a note

### Coordinate Systems

- Preserves DICOM coordinate system (LPS); STL/OBJ vertices are LPS millimetres
- NIfTI sform is converted to RAS (x and y negated); MetaImage keeps LPS with the direction cosines in TransformMatrix
- Exported voxels are already rescaled, so NIfTI scl_slope/scl_inter are 1/0

### File Formats

#### NIfTI (.nii)
- Standard in neuroimaging
- Stores header and data in single file
- Includes spatial transform matrix
- Compatible with FSL, SPM, AFNI, etc.

#### MetaImage (.mhd + .raw)
- ITK/VTK standard format
- Text header (.mhd) + binary data (.raw)
- Easy to parse and process
- Compatible with 3D Slicer, ParaView, etc.

#### STL
- Standard for 3D printing
- Binary format for efficiency
- Triangular mesh representation
- Compatible with all 3D modeling software

#### OBJ
- ASCII format for 3D models
- Human-readable
- Widely supported
- Good for visualization and editing

## Limitations

### Current Version (1.5.0)

- **Volume rendering**: Not implemented. The `volume` subcommand is hidden from `--help`; running
  it prints that it is not implemented and exits 1 (`--camera-angle`, `--transfer-function` have no effect)
- **Curved MPR**: Planned for future version
- **Animation**: Planned for future version
- **Transfer functions**: Planned for future version
- **GPU acceleration**: Not available (CPU-only)
- **JP3D standard SOP**: No standard DICOM transfer syntax UID; private SOP only (experimental)

### Performance Notes

- Large volumes (>512³) may require significant memory
- Surface extraction is computationally intensive
- Use `--verbose` to monitor progress
- Consider using smaller slab thickness for MIP to improve speed

### Platform Requirements

- **macOS 14+** or **iOS 17+** for PNG export (CoreGraphics)
- Linux builds support export formats but not PNG rendering

## Dependencies

- **DICOMKit** - Core DICOM functionality
- **DICOMCore** - Low-level DICOM parsing
- **DICOMDictionary** - Tag and UID lookups
- **ArgumentParser** - Command-line interface

## Error Handling

Common errors and solutions:

### "Missing required metadata"
- Ensure input files are valid DICOM
- Check that Image Position Patient and Image Orientation Patient tags are present

### "File not found"
- Use absolute paths or correct relative paths
- Check file permissions

### "Invalid pixel data"
- Verify files contain pixel data (not just metadata)
- Check that transfer syntax is supported

### "Surface extraction failed"
- Try adjusting threshold value
- Ensure volume has meaningful data at threshold

## See Also

- `dicom-info` - Display DICOM metadata
- `dicom-convert` - Convert DICOM images
- `dicom-viewer` - View DICOM images in terminal
- `dicom-measure` - Extract measurements

## References

- DICOM PS3.3 - Information Object Definitions
- DICOM PS3.5 - Data Structures and Encoding
- Lorensen & Cline (1987) - Marching Cubes algorithm
- NIfTI-1 Data Format Specification
- MetaImage File Format Documentation

## Version History

### 1.5.0 (Current)
- `encode-volume`: JP3D volumetric encoding via J2KSwift v3.2.0
- `decode-volume`: JP3D document decode back to DICOM slices
- `inspect`: near-instant JP3D sidecar metadata display (no pixel decode)
- Compression modes: lossless, lossless-htj2k, lossy, lossy-htj2k

### 1.4.0
- Initial release
- MPR generation (axial, sagittal, coronal)
- Intensity projections (MIP, MinIP, Average)
- Surface extraction (Marching Cubes)
- Volume export (NIfTI, MetaImage)
- STL/OBJ mesh export

## License

Part of DICOMKit - See LICENSE file for details.

## Support

For issues, questions, or contributions:
- GitHub: https://github.com/Raster-Lab/DICOMKit
- Documentation: See DICOMKit README
