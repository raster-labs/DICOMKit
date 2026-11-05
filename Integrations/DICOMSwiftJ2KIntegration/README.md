# DICOMSwiftJ2KIntegration (Apple OS 26 Full 2D JPEG 2000 & HTJ2K Adapter)

`DICOMSwiftJ2KIntegration` is a standalone nested Swift package inside `DICOMKit` that integrates the OS 26 `SwiftJ2K` JPEG 2000 Part 1, Part 2 (Annex I/J Multi-Component Transforms), and Part 15 (HTJ2K) codec without raising the deployment floors of `DICOMKit` (`iOS 18`, `macOS 15`, `tvOS 18`, `visionOS 2`) or `DICOMStudio` (`macOS 15.6`).

## Package & Dependency Pinning

- **Deployment floors**: `.macOS(.v26)`, `.iOS(.v26)`, `.tvOS(.v26)`, `.visionOS(.v26)`.
- **SwiftJ2K pin**: immutable GitHub URL revision `c95ac7b3cbb6d76039d16390497e68a1d8a07bfc` (`https://github.com/raster-labs/SwiftJ2K.git`), recorded in `Integrations/DICOMSwiftJ2KIntegration/Package.resolved`.
- **Root `DICOMKit` isolation**: root `Package.swift` retains `J2KSwift` `11.0.3` (`768f6b53499b806fd0304962056e1fc7833f12e5`) and existing OS 18 / macOS 15 deployment targets unchanged. Legacy `J2KSwiftCodec` continues refusing `.92` / `.93` Part 2 MCT encode and decode (`J2KRoutePlanner.part2MCTDecodeSupported == false`).

## Supported 2D Profiles & Transfer Syntaxes

Operations route across `auto` (`nil`), `.scalar` (`ExecutionPolicy.required(.scalarCPU)`), `.accelerate` (`AcceleratedEngine.cpuSIMD`), and `.metal` (`AcceleratedEngine.metalGPU`), verifying concrete engine provenance on every `OperationReport` so CPU SIMD and Metal GPU executions are never mislabelled, with no implicit bit-depth reduction, display LUT scaling, or pointer escape.

| Transfer Syntax UID | Name | Decode | Encode | Compressed-Domain Transcode (`SwiftJ2K.Transcoder`) |
| --- | --- | --- | --- | --- |
| `1.2.840.10008.1.2.4.90` | JPEG 2000 Lossless Only | Reversible 5/3 (`2...16`-bit signed/unsigned, 1 or 3 samples) | Reversible 5/3 | Source & target for canonical `2...16`-bit signed/unsigned monochrome and 3-component lossless `RGB` / `YBR_RCT` (`pixelAllocationCount == 0`) |
| `1.2.840.10008.1.2.4.91` | JPEG 2000 (Lossless or Lossy) | Reversible 5/3 & Irreversible 9/7 | Reversible 5/3 (`preferLossless == true`) & Irreversible 9/7 (`preferLossless == false`) | Source (when reversible 5/3) & lossless target for canonical `2...16`-bit signed/unsigned monochrome and 3-component `RGB` / `YBR_RCT` |
| `1.2.840.10008.1.2.4.92` | JPEG 2000 Part 2 Multi-component Lossless Only | Reversible 5/3 + ISO/IEC 15444-2 Annex I/J reversible array/dependency MCT (`CBD` `0xFF78`, `MCT` `0xFF74`, `MCC` `0xFF75`, `MCO` `0xFF77`) | Reversible 5/3 + Part 2 `CAP`/`CBD`/`MCT`/`MCC`/`MCO` | Routes via `SwiftJ2K` pixel decode + encode |
| `1.2.840.10008.1.2.4.93` | JPEG 2000 Part 2 Multi-component (Lossless or Lossy) | Reversible 5/3 & Irreversible 9/7 + Annex I/J reversible dependency or irreversible matrix/decorrelation MCT | Reversible (`preferLossless == true`) & Irreversible (`preferLossless == false`) Part 2 MCT | Routes via `SwiftJ2K` pixel decode + encode |
| `1.2.840.10008.1.2.4.201` | HTJ2K Lossless Only | Reversible 5/3 (`CAP` `0xFF50` `Pcap^15` required) | Reversible 5/3 (`CAP` `0xFF50`) | Source & target for canonical `2...16`-bit signed/unsigned monochrome and 3-component lossless `RGB` / `YBR_RCT` (`pixelAllocationCount == 0`) |
| `1.2.840.10008.1.2.4.202` | HTJ2K with RPCL Options Lossless Only | Reversible 5/3 + PS3.5 §10.18.1 (`RPCL`, base resolution ≤ 64, `TLM`) | Reversible 5/3 + `RPCL` + `TLM` | Source only; `.202` targets route through full `SwiftJ2K` pixel decode + RPCL/TLM encode |
| `1.2.840.10008.1.2.4.203` | HTJ2K (Lossless or Lossy) | Reversible 5/3 lossless HTJ2K & Irreversible 9/7 `HTIRV` (`Ccap^15` bit 5 + quantised `MAGB`) | Lossless 5/3 (`preferLossless == true`) & Lossy 9/7 `HTIRV` (`preferLossless == false`) | Source (when reversible 5/3) & lossless target for canonical `2...16`-bit signed/unsigned monochrome and 3-component `RGB` / `YBR_RCT` |

### Supported Pixel Layouts

- **Greyscale (`SamplesPerPixel == 1`)**: `MONOCHROME1` and `MONOCHROME2`, `BitsAllocated` in `{8, 16}`, `BitsStored` in `2...BitsAllocated`, `HighBit == BitsStored - 1`, signed (`PixelRepresentation == 1`) and unsigned (`PixelRepresentation == 0`). Both sign-extended (`0xFFFF` for `-1`) and zero-cleared (`0x0FFF` for `-1` in 12-in-16) unused high bits in native DICOM Pixel Cells are normalised via `PixelDataDescriptor.storedValue(fromCell:)` on encode and emitted as canonical little-endian two's-complement `Int16` / zero-padded `UInt16` cells on decode.
- **Colour (`SamplesPerPixel == 3`)**: `RGB` (chunky `PlanarConfiguration == 0` and planar `PlanarConfiguration == 1`), plus `YBR_RCT` (lossless decode) and `YBR_ICT` (lossy decode), `BitsAllocated` in `{8, 16}`, `BitsStored` in `2...BitsAllocated`. Lossy `YBR_FULL` sources converted through `CompressionManager` or `TransferSyntaxConverter` are converted to `RGB` prior to `ICT` / Part 2 MCT encoding per PS3.5 §8.2.4.

## Explicit Pre-Execution Capability Refusals & Fallback Policy

Capabilities outside this 2D adapter are refused **before execution** via `J2KCodecProvider.canDecode` / `canEncode` / `canTranscode`:

1. **Implicit bit-depth reduction (`maxBitsPerSample < bitsStored`)**: refused before execution so sample precision is never altered silently.
2. **Unavailable hardware backend**: `.accelerate` checks `CodecCapabilities.isSIMDAvailable` and `.metal` checks `CodecCapabilities.isMetalAvailable` before execution, and `verifyExecutedBackend` verifies `OperationReport.backend` and `OperationReport.acceleratedEngine` after execution. When `defaultBackend == .metal` and converting `.201 -> .90` (where compressed-domain block transcoding is CPU-only), `SwiftJ2KDICOMTranscoder.canTranscode` returns `false` so `TransferSyntaxConverter` routes through Metal GPU pixel decode + Metal GPU pixel encode without mislabelling.
3. **Unsupported Part 2 extensions**: `ADS` (`0xFF73`), `NLT` (`0xFF76`), wavelet-based `Tmcc`, and Part 2 markers stuffed under Part 1 (`.90`/`.91`) or HTJ2K (`.201`–`.203`) fail closed.
4. **Subsampled YCbCr (`YBR_FULL_422`, `YBR_PARTIAL_*`), `PALETTE COLOR`, 32-bit float, JP3D volumetric (`.96`/`.97`), and JPIP (`.94`/`.95`/`.204`/`.205`)**: outside this 2D adapter.

When constructed with `CodecRegistry.swiftJ2K(fallbackPolicy: .strict)` (the default), pre-execution unsupported profiles fail closed. When constructed with `CodecRegistry.swiftJ2K(fallbackPolicy: .preselectPredecessorOnUnsupportedCapability)`, `CodecRegistry` preselects `.j2kSwift` **before execution** for unsupported capabilities and records `.j2kSwift` as the resolved provider ID. Once `SwiftJ2K` begins executing, malformed codestreams, finite resource-limit or deadline refusals, and `Task` cancellation propagate directly and **never** retry on `J2KSwift`.

## Lossy Tolerances

Lossless syntaxes and lossless intents (`.90`, `.92`, `.201`, `.202`, and `preferLossless == true` on `.91` / `.93` / `.203`) require **bit-exact logical sample reconstruction** (`maxAbsError == 0`, `OperationReport.fidelity == .exactSamples`). Lossy Part 1 `.91`, Part 2 `.93`, and Part 15 `.203` (`HTIRV`, `preferLossless == false`) report `OperationReport.fidelity == .lossy`, populate DICOM Lossy Image Compression provenance (`0028,2110 = "01"`, `0028,2112`, `0028,2114 = "ISO_15444_1"` or `"ISO_15444_15"`, `DERIVED` Image Type, and a new SOP Instance UID), and are validated against `CompressionQuality.expectedMinPSNRDb`.

## Managed Budget Integration (`DICOMAllocationBudget` & `ManagedDecodedPixelFrame`)

`SwiftJ2KDICOMCodec` implements `decodeManagedPixelFrame` and `decodeManagedPixelFrameOutcome` (both with and without `DICOMExecutionReservation`):

- Pre-validates frame dimensions, bit depth, component counts, and Part 1 / Part 2 / Part 15 header markers against `PixelDecodeLimits` and `SwiftJ2K.ResourceLimits` before admitting workspace charges.
- Reserves an upper-bound `.staging` lease on `DICOMAllocationBudget` covering the borrowed codestream copy and `SwiftJ2K` wavelet/MCT workspace before running bounded decode with `DICOMCancellation` polling, releasing `.staging` upon completion or failure.
- Admits and initializes the returned `ManagedDecodedPixelFrame` (`DICOMAllocationClass.decoded`) via `DICOMByteBuffer.admitInitialized`, participating in local `Limits` and `DICOMExternalAllocationCallbacks` aggregate admission without retaining mutable raw pointers after publication.

## Usage & Explicit Per-Operation Rollback

Provider selection is immutable per `CodecRegistry` value and captured once per operation—rolling back subsequent operations to `J2KSwift` never mutates an in-flight `SwiftJ2K` operation:

```swift
import DICOMCore
import DICOMKit
import DICOMSwiftJ2KIntegration

let collector = SwiftJ2KTelemetryCollector()
let swiftJ2KRegistry = CodecRegistry.swiftJ2K(
    options: SwiftJ2KProviderOptions(defaultBackend: nil, collector: collector),
    fallbackPolicy: .strict
)

// Compress, decompress, or convert with SwiftJ2K (.90/.91/.92/.93/.201/.202/.203):
let manager = CompressionManager(codecRegistry: swiftJ2KRegistry)
let (compressed, metrics) = try manager.compressDataWithMetrics(
    sourcePart10Data,
    codec: "jpeg2000-part2-lossless-only",
    quality: nil,
    backend: .auto
)

// Explicit rollback for subsequent operations (leaves in-flight SwiftJ2K work untouched):
let rollbackRegistry = CodecRegistry.j2kSwiftRollback
let rollbackManager = CompressionManager(codecRegistry: rollbackRegistry)
```
