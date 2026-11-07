# DICOMKit Architecture

This document describes the architectural design of DICOMKit.

## Module Overview

DICOMKit is organized into five modules with clear responsibilities:

```
┌─────────────────────────────────────────────────────────────┐
│                        DICOMWeb                              │
│              (DICOMweb RESTful Services)                     │
├─────────────────────────────────────────────────────────────┤
│                        DICOMKit                              │
│              (High-level API, File I/O)                      │
├──────────────────────┬──────────────────────────────────────┤
│   DICOMDictionary    │            DICOMNetwork               │
│  (Tag/UID Lookup)    │     (DICOM Upper Layer Protocol)      │
├──────────────────────┴──────────────────────────────────────┤
│                        DICOMCore                             │
│          (Data Elements, Types, Codecs)                      │
└─────────────────────────────────────────────────────────────┘
```

## Module Dependencies

```
DICOMWeb ─────┬────► DICOMKit ────► DICOMDictionary ────► DICOMCore
              │                            ▲                 ▲
              └────────────────────────────┘                 │
                                                             │
DICOMNetwork ────────────────────────────────────────────────┤
              └─────────────────► DICOMDictionary           │
```

## DICOMCore

**Purpose**: Core types and utilities for DICOM data representation.

### Compression & Codec Architecture (`raster-labs` Pure-Swift Suite)

`DICOMCore` integrates five pure-Swift `raster-labs` codec packages through `CodecRegistry.shared`, with zero runtime C/C++ codec dependencies and zero implicit Apple ImageIO fallbacks:

- **`SwiftJ2K 12.1.0`** (`SwiftJ2KDICOMCodec` / `SwiftJ2KDICOMTranscoder`): JPEG 2000 Part 1/2 (`.90`–`.93`) and HTJ2K Part 15 (`.201`–`.203`), progressive wavelet decode, and compressed-domain Part 1 ↔ HTJ2K transcoding.
- **`SwiftJLS 2.0.0`** (`JPEGLSCodec`): JPEG-LS Lossless (`.80`) and Near-Lossless (`.81`).
- **`SwiftJLI 2.0.2`** (`JLICodec`): JPEG Baseline (`.50`), Extended (`.51`), Lossless (`.57`), and Lossless SV1 (`.70`).
- **`SwiftJXL 2.0.0`** (`JXLCodec`): JPEG XL Lossless (`.110`), JPEG Recompression (`.111` pixel decode + byte-exact `JPEG ↔ .111` bitstream transcoding), and JPEG XL Lossy/General (`.112`).
- **`SwiftRLE 1.0.1`** (`RLECodec`): DICOM RLE Lossless (`1.2.840.10008.1.2.5`).

#### Codec Layering

```
┌──────────────────────────────────────────────────────────────┐
│  DICOMStudio (SwiftUI app) / dicom-viewer (terminal)         │
│  + dicom-j2k / dicom-compress / dicom-convert / 41 CLIs      │
└───────────────────────────┬──────────────────────────────────┘
                            │
┌───────────────────────────▼──────────────────────────────────┐
│  DICOMKit (facade) / DICOMNetwork / DICOMWeb                 │
└───────────────────────────┬──────────────────────────────────┘
                            │
┌───────────────────────────▼──────────────────────────────────┐
│  DICOMCore (CodecRegistry.shared + TransferSyntaxConverter)  │
│  ├── SwiftJ2KDICOMCodec    (J2K .90–.93, HTJ2K .201–.203)    │
│  ├── JPEGLSCodec           (JPEG-LS .80 / .81)               │
│  ├── JLICodec              (JPEG .50 / .51 / .57 / .70)      │
│  ├── JXLCodec              (JPEG XL .110 / .111 / .112)      │
│  └── RLECodec              (RLE Lossless 1.2.840.10008.1.2.5)│
│      *(JP3D & JPIP deferred pending SwiftJ2K 12.2.0)*        │
└───────────────────────────┬──────────────────────────────────┘
                            │
┌───────────────────────────▼──────────────────────────────────┐
│  External Pure-Swift Codec Packages (raster-labs)            │
│  ├── SwiftJ2K 12.1.0  (Core / Codec / Accelerate / Metal)    │
│  ├── SwiftJLS 2.0.0   (ISO/IEC 14495-1 JPEG-LS)              │
│  ├── SwiftJLI 2.0.2   (ITU-T T.81 JPEG + Accelerate)         │
│  ├── SwiftJXL 2.0.0   (ISO/IEC 18181 JPEG XL + jbrd)         │
│  └── SwiftRLE 1.0.1   (DICOM Annex G PackBits RLE)           │
└──────────────────────────────────────────────────────────────┘
```

#### CodecBackend selection

`CodecBackendProbe` runs at startup and selects the best available hardware backend for `SwiftJ2K`:

| Backend | Condition | `CodecBackend` case |
|---------|-----------|---------------------|
| Metal (`SwiftJ2KMetal`) | Metal compute device available (Apple platforms, OS 26.0+) | `.metal` |
| Apple Accelerate (`SwiftJ2KAccelerate`) | `canImport(Accelerate)` | `.accelerate` |
| Scalar (pure Swift) | always | `.scalar` |

The registry falls through gracefully to `.accelerate` or `.scalar` when Metal is unavailable or when `J2KRoutePlanner` selects CPU execution for small/lossless codestreams.

#### Key points

- `SwiftJ2K` (`J2KCodecProvider.swiftJ2K` with `.strict` fallback policy) is the default codec for all active JPEG 2000 and HTJ2K UIDs
- `NativeJPEG2000Codec` and `NativeJPEGCodec` (Apple ImageIO) are never registered in `CodecRegistry.shared` (`NativeJPEGCodec` is reachable only via explicit `jpegEngine: .native` for `.50` Baseline encoding)
- `JP3DCodec` (`dicom-3d`) and `DICOMJPIPClient` (`dicom-jpip`) are cleanly deferred pending `SwiftJ2K 12.2.0`

### Key Types

| Type | Description |
|------|-------------|
| `DataElement` | Basic unit of DICOM data (tag, VR, value) |
| `Tag` | DICOM attribute identifier (group, element) |
| `VR` | Value Representation (data type) |
| `TransferSyntax` | Encoding rules for DICOM data |
| `PixelData` | Image pixel data container |
| `CharacterSetHandler` | International text encoding |

### Design Principles

- **Value Semantics**: All types are structs conforming to `Sendable`
- **Immutability**: Data elements are immutable after creation
- **Type Safety**: Strong typing for VR-specific values

## DICOMDictionary

**Purpose**: Standard DICOM tag and UID registries.

### Key Types

| Type | Description |
|------|-------------|
| `DataElementDictionary` | Registry of standard DICOM tags |
| `UIDDictionary` | Registry of SOP Classes and UIDs |
| `DictionaryEntry` | Tag information (keyword, VR, VM) |

### Usage Pattern

```swift
// Lookup by tag
let entry = DataElementDictionary.shared.lookup(group: 0x0010, element: 0x0010)

// Lookup by keyword  
let entry = DataElementDictionary.shared.lookup(keyword: "PatientName")
```

## DICOMKit

**Purpose**: High-level API for file operations and image handling.

### Key Types

| Type | Description |
|------|-------------|
| `DICOMFile` | DICOM Part 10 file representation |
| `DICOMParser` | DICOM file parser |
| `DataSet` | Collection of data elements |
| `PixelDataRenderer` | Image rendering with windowing |

### Subsystems

- **Presentation States**: GSPS, CSPS, Pseudo-Color
- **Hanging Protocols**: Display layout automation
- **Segmentation**: Binary and fractional masks
- **Parametric Maps**: Quantitative imaging
- **Radiation Therapy**: RT Structure Set, Plan, Dose
- **Structured Reporting**: SR document creation

## DICOMNetwork

**Purpose**: DICOM network protocol implementation.

**Dependencies**: `DICOMCore`, `DICOMDictionary`

### Key Types

| Type | Description |
|------|-------------|
| `DICOMClient` | Network client for DIMSE operations |
| `Association` | DICOM association management |
| `QueryService` | C-FIND query operations |
| `RetrieveService` | C-GET/C-MOVE operations |
| `StorageService` | C-STORE operations |
| `ModalityWorklistService` | Modality Worklist (MWL) query operations |

### Protocol Layers

```
┌─────────────────────────────┐
│     DIMSE Services          │
│  (C-ECHO, C-STORE, C-FIND)  │
├─────────────────────────────┤
│    Association Layer        │
│ (Request, Accept, Release)  │
├─────────────────────────────┤
│      PDU Layer              │
│   (Protocol Data Units)     │
├─────────────────────────────┤
│      TCP/TLS                │
└─────────────────────────────┘
```

## DICOMWeb

**Purpose**: RESTful DICOMweb services implementation.

### Key Types

| Type | Description |
|------|-------------|
| `DICOMwebClient` | HTTP client for DICOMweb |
| `QIDOQuery` | QIDO-RS query builder |
| `DICOMwebServer` | DICOMweb server implementation |

### Supported Services

- **QIDO-RS**: Query for studies, series, instances
- **WADO-RS**: Retrieve DICOM objects
- **STOW-RS**: Store DICOM objects
- **UPS-RS**: Unified Procedure Step

## Threading and Concurrency

DICOMKit is designed for Swift 6 strict concurrency:

### Sendable Conformance

All data types conform to `Sendable`:

```swift
public struct DataElement: Sendable { ... }
public struct DataSet: Sendable { ... }
public struct DICOMFile: Sendable { ... }
```

### Async/Await

Network operations use Swift concurrency:

```swift
let results = try await client.queryStudies(query)
```

### Actor Isolation

Mutable state is protected by actors:

```swift
actor ImageCache {
    private var cache: [String: CGImage] = [:]
    
    func get(key: String) -> CGImage? { ... }
    func set(_ image: CGImage, for key: String) { ... }
}
```

## Memory Management

### Value Semantics

DICOM data uses Swift value semantics with copy-on-write:

```swift
var dataSet = originalDataSet  // Shallow copy
dataSet[.patientName] = ...    // Copy made here
```

### Large File Handling

- **Memory Mapping**: Files >100MB use memory-mapped access
- **Lazy Loading**: Pixel data loaded on demand
- **Streaming**: Large files parsed incrementally

### Image Caching

```swift
let cache = ImageCache(configuration: .default)
// Automatic LRU eviction when memory limit reached
```

## Error Handling

DICOMKit uses Swift's native error handling:

```swift
enum DICOMError: Error {
    case invalidFile(String)
    case parsingError(String)
    case unsupportedTransferSyntax(String)
    // ...
}
```

All errors provide detailed context for debugging.

## Platform Support

| Platform | Minimum Version | Notes |
|----------|-----------------|-------|
| iOS | 26.0 | Unified Apple OS 26.0+ deployment target across DICOMKit & codec suite |
| macOS | 26.0 | Unified Apple OS 26.0+ deployment target (including DICOMStudio & 41 CLIs) |
| visionOS | 26.0 | Full support |
| tvOS / watchOS | 26.0 | Core library & codec support |

### Platform-Specific Features

- **CoreGraphics**: Image rendering (all platforms)
- **Accelerate**: SIMD image processing (Apple platforms)
- **Network.framework**: TLS support (Apple platforms)

## Extension Points

### Custom Transfer Syntaxes

Implement `ImageCodec` for custom compression:

```swift
struct MyCodec: ImageCodec {
    func decode(data: Data) throws -> PixelData { ... }
    func encode(pixelData: PixelData) throws -> Data { ... }
}
```

### Custom Storage Providers

Implement `DICOMwebStorageProvider` for custom storage:

```swift
class MyStorage: DICOMwebStorageProvider {
    func store(_ dicomFile: DICOMFile) async throws { ... }
    func retrieve(instanceUID: String) async throws -> DICOMFile { ... }
}
```
