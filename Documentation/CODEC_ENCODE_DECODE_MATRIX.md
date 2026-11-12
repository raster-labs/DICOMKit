# DICOMKit Codec Encode/Decode Matrix

Per–transfer-syntax **decode**, **encode**, and **compressed-domain transcode** coverage for the five pure-Swift MIT-licensed `raster-labs` codec libraries integrated into `DICOMCore` and `DICOMKit`:
**SwiftJ2K** (`12.2.0` — `SwiftJ2K`, `SwiftJ2K3D`, `SwiftJ2KJPIP`), **SwiftJLS** (`2.0.1`), **SwiftJLI** (`2.0.3`), **SwiftJXL** (`2.0.1`), and **SwiftRLE** (`1.0.2`).

Verified against the live registry wiring in [`Sources/DICOMCore/ImageCodec.swift`](../Sources/DICOMCore/ImageCodec.swift) (`CodecRegistry.shared`) and [`Sources/DICOMCore/SwiftJ2KProviderRegistry.swift`](../Sources/DICOMCore/SwiftJ2KProviderRegistry.swift).

**Legend**
- ✅ `<Codec>` — wired into `CodecRegistry.shared` and active for standard decode, caller-owned buffer decode (`decodeFrame(_:descriptor:frameIndex:into:)`), managed `DICOMAllocationBudget` decode (`decodeManagedPixelFrameOutcome`), and/or encode.
- 🔄 `<Transcoder>` — compressed-domain bitstream transcode without intermediate pixel re-encoding (`TransferSyntaxConverter`, `CompressionManager`, `dicom-j2k`, and `dicom-3d transcode-volume`).
- 🔗 `<Streaming>` — interactive network streaming via `DICOMJPIPClient` (`SwiftJ2KJPIP`).

All UIDs are under the `1.2.840.10008.1.2.4.*` prefix unless noted.

---

## 1. SwiftJ2K (`12.2.0`) — `SwiftJ2KDICOMCodec` (`J2KSwiftCodec` / `HTJ2KCodec`)

JPEG 2000 (Part 1 & Part 2) and High-Throughput JPEG 2000 (Part 15), backed by `J2KCodecProvider.swiftJ2K` (default in `CodecRegistry.shared` with `.strict` fallback policy). Hardware backends: `.metal` (Apple GPU), `.accelerate` (Apple SIMD), and `.scalar` (portable pure Swift).

| UID | Transfer Syntax | Decode | Encode | Compressed-Domain Transcode |
|---|---|---|---|---|
| `.90` | JPEG 2000 Lossless | ✅ `SwiftJ2KDICOMCodec` | ✅ `SwiftJ2KDICOMCodec` | 🔄 `SwiftJ2KDICOMTranscoder` (`↔ .201/.202`) |
| `.91` | JPEG 2000 (lossy / reversible) | ✅ `SwiftJ2KDICOMCodec` | ✅ `SwiftJ2KDICOMCodec` | 🔄 `SwiftJ2KDICOMTranscoder` (reversible 5/3 only) |
| `.92` | JPEG 2000 Part 2 Lossless | ✅ `SwiftJ2KDICOMCodec` | ✅ `SwiftJ2KDICOMCodec` | — (pixel path) |
| `.93` | JPEG 2000 Part 2 (lossy) | ✅ `SwiftJ2KDICOMCodec` | ✅ `SwiftJ2KDICOMCodec` | — (pixel path) |
| `.201` | HTJ2K Lossless | ✅ `SwiftJ2KDICOMCodec` | ✅ `SwiftJ2KDICOMCodec` | 🔄 `SwiftJ2KDICOMTranscoder` (`↔ .90/.91/.202`) |
| `.202` | HTJ2K RPCL Lossless | ✅ `SwiftJ2KDICOMCodec` | ✅ `SwiftJ2KDICOMCodec` | 🔄 `SwiftJ2KDICOMTranscoder` (`↔ .90/.91/.201`) |
| `.203` | HTJ2K (lossy / reversible) | ✅ `SwiftJ2KDICOMCodec` | ✅ `SwiftJ2KDICOMCodec` | 🔄 `SwiftJ2KDICOMTranscoder` (reversible 5/3 only) |

**Notes**
- **Public compatibility wrappers:** Direct instantiations of `J2KSwiftCodec` and `HTJ2KCodec` delegate to the same `SwiftJ2KDICOMCodec` implementation, including zero-intermediate-copy caller-owned buffer decode and `DICOMAllocationBudget` accounting.
- **Lossless codestream enforcement:** Decoding `.90`, `.92`, `.201`, or `.202` inspects the codestream wavelet marker and rejects irreversible 9/7 codestreams; `.202` additionally enforces RPCL progression order.
- **Progressive wavelet resolution decode:** `DICOMFile.pixelDataProgressive` and `DICOMStudio` `ImageDecodingService.decodeProgressively` decode reduced DWT levels directly via `SwiftJ2K`.

---

## 2. SwiftJLS (`2.0.1`) — `JPEGLSCodec`

JPEG-LS (ISO/IEC 14495-1 / ITU-T T.87). Per-UID decoders (`JPEGLSCodec(decodingTransferSyntaxUID:)`) and a shared encoder (`JPEGLSCodec()`).

| UID | Transfer Syntax | Decode | Encode |
|---|---|---|---|
| `.80` | JPEG-LS Lossless (`NEAR = 0`) | ✅ `JPEGLSCodec` | ✅ `JPEGLSCodec` |
| `.81` | JPEG-LS Near-Lossless (`NEAR >= 0`) | ✅ `JPEGLSCodec` | ✅ `JPEGLSCodec` |

**Notes**
- **Negotiated lossless guard:** The `.80` decoder strictly rejects JPEG-LS scans carrying `NEAR > 0`.
- **Signed & unsigned 8/16-bit greyscale and RGB** supported with bounded `DICOMAllocationBudget` tracking.

---

## 3. SwiftJLI (`2.0.3`) — `JLICodec`

Pure-Swift ITU-T T.81 JPEG (Baseline SOF0, Extended SOF1, Lossless SOF3), Accelerate-backed. Per-UID decoders (`JLICodec(decodingTransferSyntaxUID:)`) and per-UID encoders (`JLICodec(encodingTransferSyntaxUID:)`).

| UID | Transfer Syntax | JPEG process | Decode | Encode |
|---|---|---|---|---|
| `.50` | JPEG Baseline (Process 1) | SOF0 DCT, 8-bit, lossy | ✅ `JLICodec` | ✅ `JLICodec` |
| `.51` | JPEG Extended (Process 2 & 4) | SOF1 DCT, 8/12-bit, lossy | ✅ `JLICodec` | ✅ `JLICodec` |
| `.57` | JPEG Lossless (Process 14) | SOF3 predictive, lossless | ✅ `JLICodec` | ✅ `JLICodec` |
| `.70` | JPEG Lossless SV1 (Process 14, SV1) | SOF3 predictive (predictor 1), lossless | ✅ `JLICodec` | ✅ `JLICodec` |

**Notes**
- **Signed samples:** Preserved bit-exactly on lossless `.57`/`.70`; rejected on lossy DCT `.50`/`.51`.
- **Apple ImageIO isolation:** `NativeJPEGCodec` is **not** registered in `CodecRegistry.shared` and is never used implicitly; it is only reachable if a caller explicitly requests `jpegEngine: .native` for `.50` Baseline encoding.

---

## 4. SwiftJXL (`2.0.1`) — `JXLCodec`

JPEG XL (ISO/IEC 18181, Supplement 232: Modular lossless, VarDCT lossy, and `jbrd` lossless JPEG bitstream recompression/reconstruction). Per-UID decoders (`JXLCodec(decodingTransferSyntaxUID:)`) and per-UID pixel encoders (`JXLCodec(encodingTransferSyntaxUID:)`).

| UID | Transfer Syntax | Pixel Decode | Pixel Encode | Bitstream Transcode |
|---|---|---|---|---|
| `.110` | JPEG XL Lossless | ✅ `JXLCodec` | ✅ `JXLCodec` (Modular) | — |
| `.111` | JPEG XL JPEG Recompression | ✅ `JXLCodec` | — _(JPEG bitstream wrapper)_ | 🔄 `JXLCodec.recompressJPEGFragment` / `reconstructJPEGFragment` (`JPEG .50/.51 ↔ .111`) |
| `.112` | JPEG XL (general / lossy) | ✅ `JXLCodec` | ✅ `JXLCodec` (VarDCT / Modular fallback) | — |

**Notes**
- **`.111` JPEG Recompression:** Wraps an existing `.50`/`.51` JPEG fragment in a JPEG XL `jbrd` container and reconstructs the original JPEG fragment **byte-for-byte** via `TransferSyntaxConverter` and `CompressionManager` without re-quantizing pixels. Viewing or transcoding `.111` to any pixel syntax decodes through `JXLCodec` in `CodecRegistry.shared`.
- **Signed 16-bit CT support:** `JXLCodec` level-shifts signed 16-bit two's-complement samples (`word ^ 0x8000`) on pixel encode/decode and rejects signed 8-bit samples cleanly.

---

## 5. SwiftRLE (`1.0.2`) — `RLECodec`

DICOM PS3.5 Annex G RLE Lossless (`1.2.840.10008.1.2.5`). Single shared `RLECodec()` instance for decode and encode.

| UID | Transfer Syntax | Decode | Encode |
|---|---|---|---|
| `1.2.840.10008.1.2.5` | RLE Lossless | ✅ `RLECodec` | ✅ `RLECodec` |

---

## 6. SwiftJ2K3D & SwiftJ2KJPIP (`12.2.0`) — Volumetric JP3D & JPIP Streaming

| Surface | UID(s) | Decode / Retrieve | Encode / Serve | Wavelet-Domain Transcode |
|---|---|---|---|---|
| `JP3DCodec` / `JP3DVolumeDocument` / `dicom-3d` | `1.2.826.0.1.3680043.10.511.1`, `…511.2` *(experimental private)* | ✅ `JP3DCodec` (full + 3D ROI) | ✅ `JP3DCodec` (`lossless`, `losslessHTJ2K`, `lossy`, `lossyHTJ2K`) | 🔄 `VolumeTranscoder` (`J2K ↔ HTJ2K`) |
| `DICOMJPIPClient` / `dicom-jpip` / `dicom-viewer --jpip` / `DICOMStudio` | `1.2.840.10008.1.2.4.94`, `…4.95`, `…4.204`, `…4.205` | 🔗 `JPIPStreamingSession` (full, ROI, quality layers, DWT levels, HTJ2K `.204`/`.205`) | 🔗 `JPIPServer` (`dicom-jpip serve` & in-process) | — |

---

## Codecs present in `Sources/DICOMCore/` but NOT registered in `CodecRegistry.shared`

| Codec | Role |
|---|---|
| `NativeJPEGCodec` | Apple ImageIO JPEG — opt-in only via explicit `jpegEngine: .native` for `.50` Baseline |
| `NativeJPEG2000Codec` | Deprecated Apple ImageIO JPEG 2000 — never registered or implicitly invoked |
| `OpenJPEGCodec`, `DjpegCLICodec`, `DjxlCLICodec`, `GrokCLICodec`, `KakaduCLICodec` | External CLI benchmark wrappers used only by `DICOMStudio` `J2KTestBenchService` when external binaries are installed |
