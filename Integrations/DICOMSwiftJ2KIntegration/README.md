# DICOMSwiftJ2KIntegration (Apple OS 26 Scalar 2D Adapter)

`DICOMSwiftJ2KIntegration` is a standalone nested Swift package inside `DICOMKit` that integrates the OS 26 `SwiftJ2K` JPEG 2000 Part 1 and Part 15 (HTJ2K) codec without raising the deployment floors of `DICOMKit` (`iOS 18`, `macOS 15`, `tvOS 18`, `visionOS 2`) or `DICOMStudio` (`macOS 15.6`).

## Package & Dependency Pinning

- **Deployment floors**: `.macOS(.v26)`, `.iOS(.v26)`, `.tvOS(.v26)`, `.visionOS(.v26)`.
- **SwiftJ2K pin**: immutable GitHub URL revision `76850bc2286184847a1ecd1dc3ea61ab449ac4bd` (`https://github.com/raster-labs/SwiftJ2K.git`), recorded in `Integrations/DICOMSwiftJ2KIntegration/Package.resolved`.
- **Root `DICOMKit` isolation**: root `Package.swift` retains `J2KSwift` `11.0.3` (`768f6b53499b806fd0304962056e1fc7833f12e5`) and existing OS 18 / macOS 15 deployment targets unchanged.

## Supported 2D Profiles & Transfer Syntaxes

All operations execute deterministically on `SwiftJ2K`'s verified scalar CPU backend (`ExecutionPolicy.required(.scalarCPU)`), emitting `OperationReport.backend == .scalarCPU` (`CodecBackend.scalar`) with no implicit bit-depth reduction, display LUT scaling, or pointer escape.

| Transfer Syntax UID | Name | Decode | Encode | Compressed-Domain Transcode (`SwiftJ2K.Transcoder`) |
| --- | --- | --- | --- | --- |
| `1.2.840.10008.1.2.4.90` | JPEG 2000 Lossless Only | Reversible 5/3 (`2...16`-bit signed/unsigned, 1 or 3 samples) | Reversible 5/3 | Source & target for 1-component unsigned `2...16`-bit monochrome (`pixelAllocationCount == 0`) |
| `1.2.840.10008.1.2.4.91` | JPEG 2000 (Lossless or Lossy) | Reversible 5/3 & Irreversible 9/7 | Reversible 5/3 (`preferLossless == true`) & Irreversible 9/7 (`preferLossless == false`) | Source (when reversible 5/3) & lossless target for 1-component unsigned `2...16`-bit monochrome |
| `1.2.840.10008.1.2.4.201` | HTJ2K Lossless Only | Reversible 5/3 (`CAP` `0xFF50` required) | Reversible 5/3 (`CAP` `0xFF50`) | Source & target for 1-component unsigned `2...16`-bit monochrome (`pixelAllocationCount == 0`) |
| `1.2.840.10008.1.2.4.202` | HTJ2K with RPCL Options Lossless Only | Reversible 5/3 + PS3.5 §10.18.1 (`RPCL`, base resolution ≤ 64, `TLM`) | Reversible 5/3 + `RPCL` + `TLM` | Source only; `.202` targets route through full `SwiftJ2K` pixel decode + RPCL/TLM encode |
| `1.2.840.10008.1.2.4.203` | HTJ2K (Lossless or Lossy) | Reversible 5/3 lossless HTJ2K | **Lossless (`preferLossless == true`) only** | Source (when reversible 5/3) & lossless target for 1-component unsigned `2...16`-bit monochrome |
| `1.2.840.10008.1.2.4.92` / `.93` | JPEG 2000 Part 2 Multi-component | Part-1-compatible streams without `Rsiz 0x8000` or `MCT`/`MCC`/`MCO` markers | Refused before execution | Not supported |

### Supported Pixel Layouts

- **Greyscale (`SamplesPerPixel == 1`)**: `MONOCHROME1` and `MONOCHROME2`, `BitsAllocated` in `{8, 16}`, `BitsStored` in `2...BitsAllocated`, `HighBit == BitsStored - 1`, signed (`PixelRepresentation == 1`) and unsigned (`PixelRepresentation == 0`). Both sign-extended (`0xFFFF` for `-1`) and zero-cleared (`0x0FFF` for `-1` in 12-in-16) unused high bits in native DICOM Pixel Cells are normalised via `PixelDataDescriptor.storedValue(fromCell:)` on encode and emitted as canonical little-endian two's-complement `Int16` / zero-padded `UInt16` cells on decode.
- **Colour (`SamplesPerPixel == 3`)**: `RGB` (chunky `PlanarConfiguration == 0` and planar `PlanarConfiguration == 1`), plus `YBR_RCT` (decode) and `YBR_ICT` (lossy decode), `BitsAllocated` in `{8, 16}`, `BitsStored` in `2...BitsAllocated`. Lossy `YBR_FULL` sources converted through `CompressionManager` or `TransferSyntaxConverter` are converted to `RGB` prior to `ICT` encoding per PS3.5 §8.2.4.

## Explicit Pre-Execution Capability Refusals & Fallback Policy

Capabilities outside this scalar 2D slice are refused **before execution** via `J2KCodecProvider.canDecode` / `canEncode` / `canTranscode`:

1. **Lossy HTJ2K (`.203` with `preferLossless == false`)**: `SwiftJ2K` `76850bc` implements lossless HTJ2K (`FBCOT`) only; lossy HTJ2K (`HTIRV`) is refused before execution on encode and rejected on decode.
2. **Forced non-scalar backends (`forcedBackend` or `decodeBackend` set to `.metal` or `.accelerate`)**: refused before execution so generic acceleration is never mislabelled as CPU Accelerate or Metal GPU. (`nil` / `auto` and `.scalar` execute on `.scalarCPU`.)
3. **JPEG 2000 Part 2 multi-component transforms (`.92` / `.93` encode, or decode of streams carrying `MCT` / `MCC` / `MCO` or `Rsiz 0x8000`)**: refused before sample decode/encode.
4. **Signed or multi-component compressed-domain fast path**: `SwiftJ2KDICOMTranscoder.canTranscode` returns `false` for signed (`PixelRepresentation == 1`) or 3-component images, so `TransferSyntaxConverter` routes them through `SwiftJ2K.Decoder` + `SwiftJ2K.Encoder` with exact sample preservation.
5. **Subsampled YCbCr (`YBR_FULL_422`, `YBR_PARTIAL_*`), `PALETTE COLOR`, 32-bit float, JP3D volumetric, and JPIP**: outside this 2D scalar adapter.

When constructed with `CodecRegistry.swiftJ2K(fallbackPolicy: .strict)` (the default), pre-execution unsupported profiles fail closed. When constructed with `CodecRegistry.swiftJ2K(fallbackPolicy: .preselectPredecessorOnUnsupportedCapability)`, `CodecRegistry` preselects `.j2kSwift` **before execution** for unsupported capabilities and records `.j2kSwift` as the resolved provider ID. Once `SwiftJ2K` begins executing, malformed codestreams, finite resource-limit or deadline refusals, and `Task` cancellation propagate directly and **never** retry on `J2KSwift`.

## Lossy Tolerances

Lossless syntaxes and lossless intents (`.90`, `.201`, `.202`, and `preferLossless == true` on `.91` / `.203`) require **bit-exact logical sample reconstruction** (`maxAbsError == 0`, `OperationReport.fidelity == .exactSamples`). Lossy Part 1 `.91` (`preferLossless == false`, irreversible 9/7 wavelet) reports `OperationReport.fidelity == .lossy`, populates DICOM Lossy Image Compression provenance (`0028,2110 = "01"`, `0028,2112`, `0028,2114 = "ISO_15444_1"`, `DERIVED` Image Type, and a new SOP Instance UID), and is validated against `CompressionQuality.expectedMinPSNRDb` (`48 dB` at `.maximum`, `42 dB` at `.high`, `35 dB` at `.medium`, `28 dB` at `.low`).

## Managed Budget Isolation

`DICOMCore`'s synchronous `DICOMAllocationBudget` / `ManagedDecodedPixelFrame` qualified path (`decodeManagedPixelFrameOutcome`) remains isolated from `SwiftJ2KDICOMCodec` in this milestone because `DICOMByteBuffer` write leases are `package`-scoped to `DICOMKit` and `SwiftJ2K`'s internal heap allocations (`OwnedImageStorage` and wavelet coefficient workspaces) are bounded by explicit finite `SwiftJ2K.ResourceLimits` rather than `DICOMAllocationBudget` reservation tokens.

## Usage & Explicit Per-Operation Rollback

Provider selection is immutable per `CodecRegistry` value and captured once per operation—rolling back subsequent operations to `J2KSwift` never mutates an in-flight `SwiftJ2K` operation:

```swift
import DICOMCore
import DICOMKit
import DICOMSwiftJ2KIntegration

let collector = SwiftJ2KTelemetryCollector()
let swiftJ2KRegistry = CodecRegistry.swiftJ2K(
    options: SwiftJ2KProviderOptions(collector: collector),
    fallbackPolicy: .strict
)

// Compress, decompress, or convert with SwiftJ2K:
let manager = CompressionManager(codecRegistry: swiftJ2KRegistry)
let (compressed, metrics) = try manager.compressDataWithMetrics(
    sourcePart10Data,
    codec: "htj2k-lossless-only",
    quality: nil
)

// Explicit rollback for subsequent operations (leaves in-flight SwiftJ2K work untouched):
let rollbackRegistry = CodecRegistry.j2kSwiftRollback
let rollbackManager = CompressionManager(codecRegistry: rollbackRegistry)
```
