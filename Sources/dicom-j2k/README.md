# dicom-j2k

Purpose-built CLI for JPEG 2000 / HTJ2K codestream operations on DICOM files.
Part of DICOMKit, powered by J2KSwift v3.2.0.

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `info <file>` | Show J2K/HTJ2K codestream metadata (geometry, tile grid, components, bit depth) |
| `validate <file>` | ISO/IEC 15444-4 conformance check |
| `transcode <in>` | Decode every frame and re-encode it to another JPEG 2000 / HTJ2K transfer syntax |
| `reduce <in>` | Re-encode losslessly with other decomposition levels / quality layers (pixels, Rows and Columns unchanged) |
| `roi <in>` | Crop a region of one frame into a new single-frame derived image |
| `benchmark <file>` | Decode-speed statistics for one frame |
| `compare <a> <b>` | MSE / MAE / PSNR between two DICOM images, sample by sample |
| `completions <shell>` | Generate shell completions (bash/zsh/fish) |

## Supported Transfer Syntaxes

| UID | Name |
|-----|------|
| `1.2.840.10008.1.2.4.90` | JPEG 2000 Image Compression (Lossless Only) |
| `1.2.840.10008.1.2.4.91` | JPEG 2000 Image Compression |
| `1.2.840.10008.1.2.4.92` | JPEG 2000 Part 2 Multi-component Image Compression (Lossless Only) |
| `1.2.840.10008.1.2.4.93` | JPEG 2000 Part 2 Multi-component Image Compression |
| `1.2.840.10008.1.2.4.201` | High-Throughput JPEG 2000 Image Compression (Lossless Only) |
| `1.2.840.10008.1.2.4.202` | High-Throughput JPEG 2000 with RPCL Options Image Compression (Lossless Only) |
| `1.2.840.10008.1.2.4.203` | High-Throughput JPEG 2000 Image Compression |

Names as in PS3.6 2026a Table A-1. `.91`, `.93` and `.203` carry either a lossless or a lossy
codestream (PS3.5 A.4.4). `.92` / `.93` are read; `transcode` refuses them as targets
(`j2k-part2-*`, exit 1): they specify the JPEG 2000 Part 2 multiple component transformation
extensions (PS3.5 A.4.4), which the encoder does not write.

`--target` also takes a PS3.6 Table A-1 keyword, which selects its Table A-1 UID:
`JPEG2000Lossless` is .90 and `HTJ2KLossless` .201 (changed 2026-10-01, a note is printed);
the reversible encode into .91 / .203 is `JPEG2000Reversible` / `HTJ2KReversible`
(or `j2k-lossless` / `htj2k-lossless`).

## Examples

```bash
# Inspect a JPEG 2000 codestream
dicom-j2k info ct.dcm

# Inspect and output JSON
dicom-j2k info ct.dcm --json

# Validate HTJ2K conformance
dicom-j2k validate scan.htj2k.dcm

# Transcode J2K → HTJ2K
dicom-j2k transcode j2k.dcm --output htj2k.dcm --target htj2k-lossless

# Transcode HTJ2K → J2K
dicom-j2k transcode htj2k.dcm --output j2k.dcm --target j2k-lossless

# Re-encode losslessly with 3 decomposition levels and 4 quality layers
dicom-j2k reduce input.dcm --output small.dcm --levels 3 --layers 4

# Extract ROI from Frame number 1, region x=0,y=0,w=256,h=256
dicom-j2k roi input.dcm --output roi.dcm --frame-number 1 --region 0,0,256,256

# Benchmark decoding of Frame number 1
dicom-j2k benchmark ct.dcm

# Benchmark with custom iterations
dicom-j2k benchmark ct.dcm --iterations 20

# Compute MSE / MAE / PSNR between original and transcoded
dicom-j2k compare ref.dcm test.dcm

# Install zsh completions
dicom-j2k completions zsh > ~/.zsh/completions/_dicom-j2k
```

## DICOM attributes written

- Frames are located through the Extended / Basic Offset Table, so a frame may span several
  fragments (PS3.5 A.4.4). Each re-encoded frame is written as one fragment.
- Photometric Interpretation follows the written codestream: YBR_RCT with the reversible and
  YBR_ICT with the irreversible multi-component transformation, Planar Configuration 0
  (PS3.5 8.2.4, 8.2.14).
- A lossy `transcode` sets Lossy Image Compression "01", appends Lossy Image Compression Ratio /
  Method (ISO_15444_1 or ISO_15444_15), Image Type value 1 DERIVED and a new SOP Instance UID
  (PS3.3 C.7.6.1.1.5).
- `roi` writes a derived image: new SOP Instance UID, DERIVED, Rows / Columns, Number of Frames 1,
  the kept frame's Per-frame Functional Groups item and the Image Position (Patient) of the crop
  origin (PS3.3 C.7.6.1.1.2, C.7.6.2.1.1).
- For `1.2.840.10008.1.2.4.202`, PS3.5 10.18.1 requires RPCL progression, a base resolution of at
  most 64 and TLM markers; the tool asks the encoder for RPCL and enough levels and warns when the
  written codestream still misses a requirement.

## Notes

- Frames are selected with `--frame-number`, numbered from 1 (PS3.3 Table 10-3: "The first Frame
  shall be denoted as Frame number 1"); output says "Frame number N". `--frame` (0-based index)
  is **deprecated**, prints a note, and exits 1 when given with `--frame-number`.
- `--json` keys: `TransferSyntaxUID` and `NumberOfFrames` (PS3.6 Table 6-1 keywords) and
  `frameNumber` (from 1) were added; `transferSyntaxUID`, `totalFrames` and the 0-based `frame`
  are **deprecated** and keep their old values.
- HTJ2K Lossy (`.203`) is partially validated; some entropy-coder edge cases may return
  errors. Use lossless (`.201`) for archival.

## Tests

Unit tests live in `Tests/dicom-j2kTests/`.

```bash
swift test --filter dicom_j2kTests
```
