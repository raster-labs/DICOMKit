# JPEG 2000 Guide for DICOMKit

This guide covers JPEG 2000 (Part 1 & Part 2), High-Throughput JPEG 2000 (HTJ2K, Part 15), progressive wavelet decoding, and compressed-domain transcoding in DICOMKit powered by **SwiftJ2K 12.1.0** (`raster-labs/SwiftJ2K`).

> **Deferral Notice (`SwiftJ2K 12.2.0`):** JP3D volumetric encoding/decoding (`JP3DCodec`, `JP3DVolumeDocument`, `dicom-3d`) and JPIP interactive streaming (`DICOMJPIPClient`, `dicom-jpip`, `dicom-viewer --jpip`) are intentionally deferred in this release pending `SwiftJ2K 12.2.0` (`SwiftJ2K3D` and `SwiftJPIP` qualification) and fail closed with explicit unsupported diagnostics.

## Table of Contents

1. [Overview](#overview)
2. [Supported Transfer Syntaxes](#supported-transfer-syntaxes)
3. [Quick Start](#quick-start)
4. [HTJ2K — High-Throughput JPEG 2000](#htj2k--high-throughput-jpeg-2000)
5. [Progressive Wavelet Decoding](#progressive-wavelet-decoding)
6. [Hardware Acceleration](#hardware-acceleration)
7. [CLI Tools](#cli-tools)
8. [Deferred Surfaces (`SwiftJ2K 12.2.0`)](#deferred-surfaces-swiftj2k-1220)
9. [Troubleshooting](#troubleshooting)

---

## Overview

DICOMKit uses **SwiftJ2K 12.1.0** (`SwiftJ2KCore`, `SwiftJ2KCodec`, `SwiftJ2KAccelerate`, `SwiftJ2KMetal`) as its sole default JPEG 2000 / HTJ2K codec stack via `J2KCodecProvider.swiftJ2K` in `CodecRegistry.shared` (`J2KProviderFallbackPolicy.strict`). Apple ImageIO (`NativeJPEG2000Codec`) is deprecated and never registered or invoked implicitly.

### Codec Stack

```
CodecRegistry.shared (J2KCodecProvider.swiftJ2K)
├── SwiftJ2KDICOMCodec       (Decode + Encode for .90–.93 and .201–.203)
│   ├── .metal               (SwiftJ2KMetal GPU backend on Apple Silicon)
│   ├── .accelerate          (SwiftJ2KAccelerate SIMD backend on Apple platforms)
│   └── .scalar              (Portable pure-Swift backend)
└── SwiftJ2KDICOMTranscoder  (Compressed-domain lossless Part 1 ↔ HTJ2K transcode)
```

The optimal hardware backend is probed automatically at startup by `CodecBackendProbe` and planned per codestream by `J2KRoutePlanner`. Override when needed via `CodecRegistry.shared.backendPreference` or `--backend`.

---

## Supported Transfer Syntaxes

| Transfer Syntax | UID | Status | Notes |
|-----------------|-----|--------|-------|
| JPEG 2000 Lossless | `1.2.840.10008.1.2.4.90` | ✅ Active | ISO/IEC 15444-1 reversible 5/3 |
| JPEG 2000 | `1.2.840.10008.1.2.4.91` | ✅ Active | ISO/IEC 15444-1 irreversible 9/7 or reversible 5/3 |
| JPEG 2000 Part 2 Lossless | `1.2.840.10008.1.2.4.92` | ✅ Active | ISO/IEC 15444-2 lossless |
| JPEG 2000 Part 2 | `1.2.840.10008.1.2.4.93` | ✅ Active | ISO/IEC 15444-2 lossy / lossless |
| HTJ2K Lossless | `1.2.840.10008.1.2.4.201` | ✅ Active | ISO/IEC 15444-15 reversible 5/3 |
| HTJ2K RPCL Lossless | `1.2.840.10008.1.2.4.202` | ✅ Active | HTJ2K lossless with mandatory RPCL progression |
| HTJ2K | `1.2.840.10008.1.2.4.203` | ✅ Active | ISO/IEC 15444-15 lossy / reversible |
| JPIP Referenced | `1.2.840.10008.1.2.4.94` | ⏸️ Deferred | Pending `SwiftJ2K 12.2.0` |
| JPIP Referenced Deflate | `1.2.840.10008.1.2.4.95` | ⏸️ Deferred | Pending `SwiftJ2K 12.2.0` |

---

## Quick Start

### Decode a JPEG 2000 or HTJ2K DICOM file

```swift
import DICOMKit

let file = try DICOMFile.read(from: url)
let pixels = try file.tryPixelData()   // decoded via SwiftJ2K in CodecRegistry.shared
let image = try file.tryRenderFrame(0) // CGImage on Apple platforms
```

### Encode with JPEG 2000 Lossless or HTJ2K Lossless

```swift
let manager = CompressionManager()
let compressedData = try await manager.compressData(
    dicomData,
    to: "htj2k-lossless" // or "j2k-lossless", "htj2k-rpcl", "htj2k", "j2k"
)
```

### Compressed-domain transcode J2K ↔ HTJ2K (no pixel re-encoding)

Both `TransferSyntaxConverter`, `CompressionManager`, and `dicom-j2k transcode` automatically invoke `SwiftJ2KDICOMTranscoder` when transcoding lossless JPEG 2000 Part 1 (`.90` or reversible `.91`) ↔ HTJ2K (`.201`, `.202`, or reversible `.203`), preserving wavelet coefficients bit-for-bit without full pixel reconstruction:

```swift
let converter = TransferSyntaxConverter()
let converted = try converter.convert(
    dataSet: file.dataSet,
    to: .htj2kLossless
)
```

---

## HTJ2K — High-Throughput JPEG 2000

HTJ2K (ISO/IEC 15444-15) replaces the EBCOT Tier-1 arithmetic coder with the high-throughput FBCOT block coder while sharing the exact same wavelet domain as JPEG 2000 Part 1.

### RPCL Progression (`.202`)

Transfer syntax `1.2.840.10008.1.2.4.202` enforces RPCL (Resolution-Position-Component-Layer) progression order, placing coarse wavelet resolution levels at the front of the codestream for progressive display.

### DICOMweb

HTJ2K is supported across `DICOMWeb` (`image/jph` and `image/jphc` media types) for WADO-RS frame retrieval and STOW-RS storage.

---

## Progressive Wavelet Decoding

`DICOMFile.pixelDataProgressive(frame:coarseLevels:)` and `DICOMStudio`'s `ImageDecodingService.decodeProgressively(file:)` stream genuine reduced-resolution DWT levels directly from `SwiftJ2K` (`quarter` `1/4` -> `half` `1/2` -> `full` `1/1`) before handing off to interactive GPU window/level rendering:

```swift
for try await partial in file.pixelDataProgressive(frame: 0, coarseLevels: [2, 1]) {
    // partial.resolutionLevel: 2 (quarter), 1 (half), 0 (full, partial.isFinal == true)
    let previewPixels = partial.pixelData
}
```

---

## Hardware Acceleration

### Checking the active backend

```swift
let backend = CodecRegistry.shared.activeBackend
// .metal, .accelerate, or .scalar

let description = CodecRegistry.shared.backendDescription
```

Note: In `DICOMStudio`, `ImageDecodingService.decode(file:)` reports the **actual effective backend per codec** (`J2KRoutePlanner.planDecode` for `SwiftJ2K`; `.accelerate`/`.scalar` for `SwiftJLI`, `SwiftJLS`, and `SwiftJXL`; `.scalar` for `SwiftRLE` and uncompressed datasets).

### Listing and selecting backends from the CLI

```bash
dicom-compress backends

dicom-compress compress scan.dcm --output scan_htj2k.dcm \
  --codec htj2k-lossless \
  --backend accelerate
```

---

## CLI Tools

### `dicom-j2k`

Purpose-built for JPEG 2000 and HTJ2K codestream operations on DICOM files:

| Subcommand | Description |
|------------|-------------|
| `info <file>` | Show J2K/HTJ2K codestream marker & progression metadata |
| `validate <file>` | Codestream marker & transfer syntax conformance check |
| `transcode <in> <out>` | Compressed-domain J2K ↔ HTJ2K fast-path transcode (with pixel fallback) |
| `reduce <in> <out>` | Decode reduced wavelet decomposition level (`SwiftJ2K`) |
| `roi <in> <out>` | Crop region of interest |
| `benchmark <file>` | Benchmark decode throughput across backends |
| `compare <a> <b>` | Compute PSNR / MAE / max-diff between two DICOM images |

```bash
dicom-j2k info ct.dcm
dicom-j2k validate scan.htj2k.dcm
dicom-j2k transcode j2k.dcm htj2k.dcm --to htj2k-lossless
dicom-j2k benchmark ct.dcm
```

### `dicom-compress`

```bash
dicom-compress compress ct.dcm --output ct.j2k.dcm --codec j2k-lossless
dicom-compress compress ct.dcm --output ct.htj2k.dcm --codec htj2k-lossless
dicom-compress transcode ct.j2k.dcm --to htj2k-lossless --output ct.htj2k.dcm
```

---

## Deferred Surfaces (`SwiftJ2K 12.2.0`)

- **JP3D (`JP3DCodec`, `JP3DVolumeDocument`, `dicom-3d`):** Volumetric ISO/IEC 15444-10 encode/decode is deferred pending `SwiftJ2K 12.2.0` (`SwiftJ2K3D` qualification). Standard multi-frame and slice-series volume loading (`DICOMFile.openVolume` and `JP3DVolumeBridge.makeVolume`, including RLE/J2K/JPEG-LS/JPEG/JXL compressed inputs) remains fully active.
- **JPIP (`DICOMJPIPClient`, `dicom-jpip`, `dicom-viewer --jpip`):** Interactive JPIP client/server streaming (`.94` / `.95`) is deferred pending `SwiftJ2K 12.2.0` (`SwiftJPIP` qualification). `dicom-jpip uri` local URI construction remains available; network `fetch`/`serve`/`info` and `dicom-viewer --jpip` exit cleanly with explicit deferral messages.

---

## Troubleshooting

### Irreversible 9/7 codestream rejected under lossless Transfer Syntax

**Symptom**: `DICOMError.decodingFailed` when reading a `.90` or `.201`/`.202` file.

**Cause**: `SwiftJ2KDICOMCodec` enforces DICOM PS3.5 conformance: lossless Transfer Syntaxes must use the reversible 5/3 wavelet transform, and `.202` must use RPCL progression order.

**Fix**: Ensure lossy 9/7 codestreams are tagged with `.91` (`JPEG 2000`) or `.203` (`HTJ2K`).
