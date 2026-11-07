# DICOMKit Codec Reference

A developer reference for the five pure-Swift `raster-labs` codec libraries integrated into `DICOMCore`:
**SwiftJ2K** (`12.1.0`), **SwiftJLS** (`2.0.0`), **SwiftJLI** (`2.0.2`), **SwiftJXL** (`2.0.0`), and **SwiftRLE** (`1.0.1`).

---

## Quick-reference table

| Library | Version | Runtime engine | In `CodecRegistry.shared` | DICOM Transfer Syntaxes |
|---|---|---|---|---|
| **SwiftJ2K** | `12.1.0` | Pure Swift + Accelerate SIMD + Metal GPU | ✅ Active | 7 — J2K Part 1/2 (`.90`–`.93`) + HTJ2K (`.201`–`.203`), plus compressed-domain Part 1 ↔ HTJ2K transcode |
| **SwiftJLS** | `2.0.0` | Pure Swift + Accelerate | ✅ Active | 2 — JPEG-LS Lossless (`.80`) + Near-Lossless (`.81`) |
| **SwiftJLI** | `2.0.2` | Pure Swift + Accelerate | ✅ Active | 4 — JPEG Baseline/Extended (`.50`, `.51`) + Lossless/SV1 (`.57`, `.70`) |
| **SwiftJXL** | `2.0.0` | Pure Swift + Accelerate | ✅ Active | 3 — JPEG XL Lossless (`.110`), JPEG Recompression (`.111`), JPEG XL Lossy/General (`.112`) |
| **SwiftRLE** | `1.0.1` | Pure Swift | ✅ Active | 1 — RLE Lossless (`1.2.840.10008.1.2.5`) |

> **Deferred pending `SwiftJ2K 12.2.0`:** JP3D volumetric encode/decode (`JP3DCodec`, experimental private UIDs `1.2.826.0.1.3680043.10.511.1/.2`, `dicom-3d`) and JPIP interactive streaming (`DICOMJPIPClient`, `.94`/`.95`, `dicom-jpip`) are intentionally unregistered and fail closed with explicit `SwiftJ2K 12.2.0` deferral diagnostics.

---

## SwiftJ2K (`12.1.0`) — JPEG 2000 + HTJ2K

Pure-Swift JPEG 2000 Part 1, Part 2, and Part 15 (HTJ2K) codec stack with Accelerate SIMD and Metal GPU acceleration on Apple platforms (`iOS 26+`, `macOS 26+`, `visionOS 26+`, `tvOS 26+`, `watchOS 26+`, Swift 6.4+). External implementations (OpenJPEG, OpenJPH, Grok, Kakadu) are test-time validation oracles only.

### Library targets / products

| Product | Description |
|---|---|
| `SwiftJ2KCore` | Codestream parser, markers, image model, memory tracker |
| `SwiftJ2KCodec` | JPEG 2000 Part 1/2 & HTJ2K encoder, decoder, progressive resolution decode, and compressed-domain transcoder |
| `SwiftJ2KAccelerate` | Apple Accelerate SIMD wavelet & colour transforms |
| `SwiftJ2KMetal` | Apple Metal GPU-accelerated wavelet & colour transforms |

### `DICOMCore` codecs (`Sources/DICOMCore/`)

**`SwiftJ2KDICOMCodec`** (registered by default via `J2KCodecProvider.swiftJ2K`, with public compatibility wrappers **`J2KSwiftCodec`** and **`HTJ2KCodec`**) serves all seven JPEG 2000 family Transfer Syntaxes:

| Transfer Syntax UID | Name | Decode | Encode | Compressed-domain transcode |
|---|---|:---:|:---:|:---:|
| `1.2.840.10008.1.2.4.90` | JPEG 2000 Lossless | ✅ | ✅ | ✅ (`↔ .201 / .202`) |
| `1.2.840.10008.1.2.4.91` | JPEG 2000 | ✅ | ✅ | ✅ (when reversible 5/3) |
| `1.2.840.10008.1.2.4.92` | JPEG 2000 Part 2 Lossless | ✅ | ✅ | — |
| `1.2.840.10008.1.2.4.93` | JPEG 2000 Part 2 | ✅ | ✅ | — |
| `1.2.840.10008.1.2.4.201` | HTJ2K Lossless | ✅ | ✅ | ✅ (`↔ .90 / .91 / .202`) |
| `1.2.840.10008.1.2.4.202` | HTJ2K RPCL Lossless | ✅ | ✅ | ✅ (`↔ .90 / .91 / .201`) |
| `1.2.840.10008.1.2.4.203` | HTJ2K | ✅ | ✅ | ✅ (when reversible 5/3) |

*Note: `1.2.840.10008.1.2.4.202` enforces RPCL progression order.*

---

## SwiftJLS (`2.0.0`) — JPEG-LS

Pure-Swift implementation of JPEG-LS (ISO/IEC 14495-1 / ITU-T T.87). CharLS is a test-time validation oracle only, not a runtime dependency.

### `DICOMCore` codec (`Sources/DICOMCore/`)

**`JPEGLSCodec`** — registered for both JPEG-LS UIDs (per-UID decoder so `.80` strictly rejects near-lossless `NEAR > 0` scans, plus shared encoder):

| Transfer Syntax UID | Name | Decode | Encode |
|---|---|:---:|:---:|
| `1.2.840.10008.1.2.4.80` | JPEG-LS Lossless (`NEAR = 0`) | ✅ | ✅ |
| `1.2.840.10008.1.2.4.81` | JPEG-LS Near-Lossless (`NEAR >= 0`) | ✅ | ✅ |

---

## SwiftJLI (`2.0.2`) — JPEG (Baseline, Extended, Lossless & SV1)

Pure-Swift implementation of ITU-T T.81 JPEG modes: Baseline (SOF0), Extended Sequential (SOF1), and Lossless Predictive (SOF3, predictors 1–7), with Accelerate SIMD hot paths. Validated against `libjpeg-turbo`, `mozjpeg`, and `jpegli` at test time only.

### `DICOMCore` codec (`Sources/DICOMCore/`)

**`JLICodec`** — registered in `CodecRegistry.shared` for all four standard DICOM JPEG Transfer Syntaxes (per-UID decoders enforcing the negotiated DICOM process, and per-UID encoders selecting the target JPEG process):

| Transfer Syntax UID | Name | JPEG process | Quality |
|---|---|---|---|
| `1.2.840.10008.1.2.4.50` | JPEG Baseline (Process 1) | SOF0 DCT, 8-bit | Lossy |
| `1.2.840.10008.1.2.4.51` | JPEG Extended (Process 2 & 4) | SOF1 DCT, 8/12-bit | Lossy |
| `1.2.840.10008.1.2.4.57` | JPEG Lossless (Process 14) | SOF3 predictive | Lossless |
| `1.2.840.10008.1.2.4.70` | JPEG Lossless SV1 (Process 14, SV1) | SOF3 predictive, predictor 1 | Lossless |

Behaviour notes:
- **Mode is driven by the transfer syntax.** Lossless syntaxes (`.57`, `.70`) are always bit-exact (`pointTransform = 0`); lossy syntaxes (`.50`, `.51`) map `CompressionConfiguration.quality` (`0.0–1.0`) to a JPEG quality factor (`1–100`).
- **Lossy is sequential and 4:4:4.** Chroma is kept full-resolution for diagnostic fidelity.
- **Signed samples** (e.g. CT Hounsfield units) are preserved bit-exactly on lossless `.57`/`.70` and rejected on lossy DCT `.50`/`.51`.
- `NativeJPEGCodec` (Apple ImageIO) is **not** registered in `CodecRegistry.shared`; it is reachable only when an API caller explicitly passes `jpegEngine: .native` for `.50` Baseline encoding.

---

## SwiftJXL (`2.0.0`) — JPEG XL

Pure-Swift implementation of ISO/IEC 18181 JPEG XL (Modular lossless, VarDCT lossy, and `jbrd` lossless JPEG bitstream recompression/reconstruction). `libjxl` is a test-time validation oracle only.

### `DICOMCore` codec (`Sources/DICOMCore/`)

**`JXLCodec`** — registered in `CodecRegistry.shared` for all three Supplement 232 DICOM JPEG XL Transfer Syntaxes:

| Transfer Syntax UID | Name | Pixel Decode | Pixel Encode | Bitstream Transcode (`SwiftJXL.Transcoder`) |
|---|---|:---:|:---:|:---:|
| `1.2.840.10008.1.2.4.110` | JPEG XL Lossless | ✅ | ✅ (Modular) | — |
| `1.2.840.10008.1.2.4.111` | JPEG XL JPEG Recompression | ✅ | — _(JPEG bitstream wrapper)_ | ✅ (`JPEG .50/.51 ↔ .111` byte-exact) |
| `1.2.840.10008.1.2.4.112` | JPEG XL (general / lossy) | ✅ | ✅ (VarDCT / Modular fallback) | — |

---

## SwiftRLE (`1.0.1`) — RLE Lossless

Pure-Swift DICOM PS3.5 Annex G PackBits byte-plane RLE encoder and decoder with caller-owned buffer and `DICOMAllocationBudget` support.

### `DICOMCore` codec (`Sources/DICOMCore/`)

**`RLECodec`** — registered in `CodecRegistry.shared` for `1.2.840.10008.1.2.5` (RLE Lossless, decode + encode).

---

## `CodecRegistry` wiring

**Location:** `Sources/DICOMCore/ImageCodec.swift`

`CodecRegistry.shared` maintains per-UID decoder and encoder maps plus a `J2KCodecProvider` (`J2KCodecProvider.swiftJ2K` by default with `.strict` fallback policy):
- `codec(for:)` / `resolveDecoder(for:descriptor:decodeBackend:)` — returns `(any ImageCodec)?` (and `CodecProviderID`)
- `encoder(for:)` / `resolveEncoder(for:configuration:descriptor:)` — returns `(any ImageEncoder)?` (and `CodecProviderID`)
- `resolveJ2KTranscoder(from:to:descriptor:)` — returns `SwiftJ2KDICOMTranscoder` for compressed-domain lossless Part 1 ↔ HTJ2K transcoding

`NativeJPEGCodec` and `NativeJPEG2000Codec` (Apple ImageIO) are **never** registered in `CodecRegistry.shared` and are never invoked implicitly on default decode, encode, or transcode paths.

---

## Transfer Syntax categories

### Combined view — active transfer syntaxes at a glance

| Transfer Syntax | UID | `isEncapsulated` | `isLossless` | `isExplicitVR` | Owning Engine |
|---|---|:---:|:---:|:---:|---|
| ImplicitVRLittleEndian | `1.2.840.10008.1.2` | — | ✅ | ❌ | Native byte parser |
| ExplicitVRLittleEndian | `1.2.840.10008.1.2.1` | — | ✅ | ✅ | Native byte parser |
| ExplicitVRBigEndian _(Retired)_ | `1.2.840.10008.1.2.2` | — | ✅ | ✅ | Native byte parser |
| DEFLATE | `1.2.840.10008.1.2.1.99` | — ¹ | ✅ | ✅ | Dataset zlib stream |
| RLELossless | `1.2.840.10008.1.2.5` | ✅ | ✅ | ✅ | `SwiftRLE` (`RLECodec`) |
| JPEGBaseline | `1.2.840.10008.1.2.4.50` | ✅ | ❌ | ✅ | `SwiftJLI` (`JLICodec`) |
| JPEGExtended | `1.2.840.10008.1.2.4.51` | ✅ | ❌ | ✅ | `SwiftJLI` (`JLICodec`) |
| JPEGLossless | `1.2.840.10008.1.2.4.57` | ✅ | ✅ | ✅ | `SwiftJLI` (`JLICodec`) |
| JPEGLosslessSV1 | `1.2.840.10008.1.2.4.70` | ✅ | ✅ | ✅ | `SwiftJLI` (`JLICodec`) |
| JPEGLSLossless | `1.2.840.10008.1.2.4.80` | ✅ | ✅ | ✅ | `SwiftJLS` (`JPEGLSCodec`) |
| JPEGLSNearLossless | `1.2.840.10008.1.2.4.81` | ✅ | ❌ | ✅ | `SwiftJLS` (`JPEGLSCodec`) |
| JPEG2000Lossless / Part 2 Lossless | `…4.90`, `…4.92` | ✅ | ✅ | ✅ | `SwiftJ2K` (`SwiftJ2KDICOMCodec`) |
| JPEG2000 / Part 2 | `…4.91`, `…4.93` | ✅ | ❌ | ✅ | `SwiftJ2K` (`SwiftJ2KDICOMCodec`) |
| HTJ2KLossless / RPCL Lossless | `…4.201`, `…4.202` | ✅ | ✅ | ✅ | `SwiftJ2K` (`SwiftJ2KDICOMCodec`) |
| HTJ2K | `1.2.840.10008.1.2.4.203` | ✅ | ❌ | ✅ | `SwiftJ2K` (`SwiftJ2KDICOMCodec`) |
| JPEGXLLossless | `1.2.840.10008.1.2.4.110` | ✅ | ✅ | ✅ | `SwiftJXL` (`JXLCodec`) |
| JPEGXLRecompression | `1.2.840.10008.1.2.4.111` | ✅ | ✅ ² | ✅ | `SwiftJXL` (`JXLCodec`) |
| JPEGXL | `1.2.840.10008.1.2.4.112` | ✅ | ❌ | ✅ | `SwiftJXL` (`JXLCodec`) |

_¹ DEFLATE: `isDeflated: true`, `isEncapsulated: false` — compresses the entire dataset, not encapsulated pixel fragments._
_² JPEGXLRecompression is byte-exact with respect to the original JPEG bitstream._

---

## Validation oracles (test-time only)

None of the five `raster-labs` codec libraries carry runtime C/C++ codec dependencies. Interoperability validation is performed against external reference implementations at test time only:

| Library | Reference oracle(s) |
|---|---|
| `SwiftJ2K` | OpenJPEG, OpenJPH, Grok, Kakadu |
| `SwiftJLS` | CharLS |
| `SwiftJLI` | `libjpeg-turbo`, `mozjpeg`, `jpegli`, Apple CoreGraphics / ImageIO |
| `SwiftJXL` | `libjxl` (`cjxl` / `djxl`) |
| `SwiftRLE` | DCMTK (`dcmdrle` / `dcmcrle`), GDCM |
