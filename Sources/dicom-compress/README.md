# dicom-compress

DICOM compression and decompression utilities for DICOMKit.

## Features

- **Compress** DICOM files using various codecs (JPEG, JPEG-LS, JPEG 2000, HTJ2K, JPEG XL, RLE, Deflate)
- **Decompress** compressed DICOM files to uncompressed transfer syntaxes
- **Info** — display compression status, transfer syntax, and image parameters
- **Batch** — process entire directories with optional recursion

## Installation

Built as part of DICOMKit using Swift Package Manager:

```bash
swift build --product dicom-compress
```

## Usage

### Info — Show Compression Details

```bash
# Display compression info for a DICOM file
dicom-compress info file.dcm

# Output as JSON
dicom-compress info file.dcm --json
```

`info --json` carries the PS3.6 Table 6-1 keyword keys `TransferSyntaxUID`, `Rows`, `Columns`,
`BitsAllocated`, `BitsStored`, `SamplesPerPixel`, `PhotometricInterpretation`, `NumberOfFrames`
and `LossyImageCompression` (when present). The camelCase keys `transferSyntaxUID`, `rows`,
`columns`, `bitsAllocated`, `bitsStored`, `samplesPerPixel`, `photometricInterpretation` and
`numberOfFrames` are **deprecated** and keep their old values.

### Compress — Compress a DICOM File

```bash
# Compress using JPEG Lossless
dicom-compress compress input.dcm --output output.dcm --codec jpeg-lossless

# Compress using JPEG 2000 with high quality
dicom-compress compress input.dcm --output output.dcm --codec jpeg2000 --quality high

# Compress using JPEG Baseline with custom quality
dicom-compress compress input.dcm --output output.dcm --codec jpeg-baseline --quality 0.85
```

### Decompress — Decompress a DICOM File

```bash
# Decompress to Explicit VR Little Endian (default)
dicom-compress decompress compressed.dcm --output uncompressed.dcm

# Decompress to Implicit VR Little Endian
dicom-compress decompress compressed.dcm --output uncompressed.dcm --syntax implicit-le
```

`decompress --syntax` and `batch --syntax` accept only the native targets `explicit-le`,
`implicit-le` and `deflate` (PS3.5 A.2, A.1, A.5), and `explicit-be` — Explicit VR Big Endian,
retired (PS3.5 A.3), for legacy readers only; values are byte-swapped per PS3.5 7.3. A compressed
codec name (for example `jpeg2000`) is refused with exit 1.

### Batch — Process Directories

```bash
# Batch compress a directory
dicom-compress batch input_dir/ --output output_dir/ --codec jpeg-lossless

# Batch compress recursively with quality setting
dicom-compress batch input_dir/ --output output_dir/ --codec jpeg2000 --quality high --recursive

# Batch decompress
dicom-compress batch input_dir/ --output output_dir/ --decompress --recursive
```

## Supported Codecs

| Codec name(s) | Transfer Syntax UID | PS3.6 2026a Table A-1 name | Encoding |
|---|---|---|---|
| `jpeg`, `jpeg-baseline` | `1.2.840.10008.1.2.4.50` | JPEG Baseline (Process 1): Default Transfer Syntax for Lossy JPEG 8 Bit Image Compression | lossy |
| `jpeg-extended` | `1.2.840.10008.1.2.4.51` | JPEG Extended (Process 2 & 4): Default Transfer Syntax for Lossy JPEG 12 Bit Image Compression (Process 4 only) | lossy |
| `jpeg-lossless` | `1.2.840.10008.1.2.4.57` | JPEG Lossless, Non-Hierarchical (Process 14) | lossless |
| `jpeg-lossless-sv1` | `1.2.840.10008.1.2.4.70` | JPEG Lossless, Non-Hierarchical, First-Order Prediction (Process 14 [Selection Value 1]): Default Transfer Syntax for Lossless JPEG Image Compression | lossless |
| `jpeg2000`, `jpeg2000-lossy` | `1.2.840.10008.1.2.4.91` | JPEG 2000 Image Compression | irreversible (lossy) |
| `jpeg2000-lossless` | `1.2.840.10008.1.2.4.91` | JPEG 2000 Image Compression | reversible (lossless) |
| `jpeg2000-lossless-only` | `1.2.840.10008.1.2.4.90` | JPEG 2000 Image Compression (Lossless Only) | lossless |
| `j2k-part2`, `j2k-part2-lossy` | `1.2.840.10008.1.2.4.93` | JPEG 2000 Part 2 Multi-component Image Compression | irreversible (lossy) |
| `j2k-part2-lossless` | `1.2.840.10008.1.2.4.93` | JPEG 2000 Part 2 Multi-component Image Compression | reversible (lossless) |
| `j2k-part2-lossless-only` | `1.2.840.10008.1.2.4.92` | JPEG 2000 Part 2 Multi-component Image Compression (Lossless Only) | lossless |
| `htj2k`, `htj2k-lossy` | `1.2.840.10008.1.2.4.203` | High-Throughput JPEG 2000 Image Compression | irreversible (lossy) |
| `htj2k-lossless` | `1.2.840.10008.1.2.4.203` | High-Throughput JPEG 2000 Image Compression | reversible (lossless) |
| `htj2k-lossless-only` | `1.2.840.10008.1.2.4.201` | High-Throughput JPEG 2000 Image Compression (Lossless Only) | lossless |
| `htj2k-rpcl-lossless-only` | `1.2.840.10008.1.2.4.202` | High-Throughput JPEG 2000 with RPCL Options Image Compression (Lossless Only) | lossless |
| `jpeg-ls-lossless` | `1.2.840.10008.1.2.4.80` | JPEG-LS Lossless Image Compression | lossless |
| `jpeg-ls`, `jls` | `1.2.840.10008.1.2.4.81` | JPEG-LS Lossy (Near-Lossless) Image Compression | lossy |
| `jpeg-xl`, `jpeg-xl-lossy` | `1.2.840.10008.1.2.4.112` | JPEG XL | irreversible (lossy) |
| `jpeg-xl-lossless` | `1.2.840.10008.1.2.4.112` | JPEG XL | reversible (lossless) |
| `jpeg-xl-lossless-only` | `1.2.840.10008.1.2.4.110` | JPEG XL Lossless | lossless |
| `rle` | `1.2.840.10008.1.2.5` | RLE Lossless | lossless |
| `deflate` | `1.2.840.10008.1.2.1.99` | Deflated Explicit VR Little Endian | lossless |
| `explicit-le` | `1.2.840.10008.1.2.1` | Explicit VR Little Endian | lossless |
| `implicit-le` | `1.2.840.10008.1.2` | Implicit VR Little Endian: Default Transfer Syntax for DICOM | lossless |

Each name resolves through the shared codec table (`CompressionManager`); names and UIDs are
those of PS3.6 2026a Table A-1. The general JPEG 2000, HTJ2K and JPEG XL UIDs carry a reversible
or an irreversible codestream (PS3.5 A.4.4, A.4.12); `-lossless-only` selects the reversible-only
UID. A lossy encode records Lossy Image Compression (0028,2110) "01", Lossy Image Compression
Ratio / Method (0028,2112) / (0028,2114) and Image Type value 1 DERIVED (PS3.3 C.7.6.1.1.5).

## Quality Settings

The `--quality` option accepts:

- `maximum` — highest quality (0.98), lossless where supported
- `high` — high quality (0.90)
- `medium` — medium quality (0.75)
- `low` — low quality (0.60)
- A decimal value between `0.0` and `1.0` for custom quality

Quality settings only apply to irreversible (lossy) encodes; they are ignored for lossless codecs.

## Notes

- DICOM files are detected by `.dcm`, `.dicom`, `.dic` extensions or by the `DICM` magic prefix
- Batch mode preserves directory structure in the output
- The tool writes DICOM Part 10 files (preamble, DICM prefix, File Meta Information)
- JPEG 2000 compression now uses the J2KSwift v3.2.0 adapter as the Phase 1 implementation, with verified round-trip and benchmark coverage
- Platform codec support may vary; not all codecs are available on all systems

## Version

1.3.3 (Phase 6 — DICOMKit CLI Tools)
