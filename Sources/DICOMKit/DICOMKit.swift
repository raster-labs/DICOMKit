// NEMA-verified: 2026a, checked 2026-09-29 — the four supported Transfer Syntax UIDs and their names match PS3.6 2026a Table A-1; dicomStandardEdition is the package target
/// DICOMKit - A pure Swift DICOM toolkit for Apple platforms
///
/// Version 0.5.0
///
/// DICOMKit provides a modern, Swift-native interface for reading, writing, and parsing
/// DICOM (Digital Imaging and Communications in Medicine) files on iOS, macOS, and visionOS.
///
/// ## Features (v0.5)
/// - **DICOM file reading and writing** (new in v0.5)
/// - Create new DICOM files from scratch
/// - Modify existing DICOM files
/// - File Meta Information generation
/// - UID generation utilities
/// - Data element serialization for all VRs
/// - Sequence writing support
/// - Value padding per DICOM specification
/// - Explicit VR Little Endian Transfer Syntax support
/// - Implicit VR Little Endian Transfer Syntax support
/// - Explicit VR Big Endian Transfer Syntax support (Retired)
/// - Deflated Explicit VR Little Endian Transfer Syntax support (Apple platforms only)
/// - Compressed pixel data support (JPEG, JPEG 2000, RLE)
/// - Uncompressed pixel data extraction and rendering
/// - Support for MONOCHROME1, MONOCHROME2, RGB, PALETTE COLOR photometric interpretations
/// - Multi-frame image support
/// - Window Center/Width (VOI LUT) support
/// - CGImage rendering for display
/// - Value semantics with Swift 6 strict concurrency
/// - Full DICOM PS3.5 2026a compliance for supported features
///
/// ## Limitations (v0.5)
/// - No networking (DICOM C-* operations)
/// - No character set conversion (UTF-8 only)
///
/// ## Platform Requirements
/// - iOS 17.0+
/// - macOS 14.0+
/// - visionOS 1.0+

// Re-export core types
@_exported import DICOMCore
@_exported import DICOMDictionary

/// DICOMKit version
public let version = "0.5.0"

/// Supported DICOM Standard edition
public let dicomStandardEdition = "2026a"

/// Supported Transfer Syntax UIDs
public let supportedTransferSyntaxUIDs: [String] = [
    "1.2.840.10008.1.2.1",    // Explicit VR Little Endian
    "1.2.840.10008.1.2",      // Implicit VR Little Endian
    "1.2.840.10008.1.2.2",    // Explicit VR Big Endian (Retired)
    "1.2.840.10008.1.2.1.99"  // Deflated Explicit VR Little Endian
]

/// Primary supported Transfer Syntax UID (Explicit VR Little Endian)
/// - Note: For backward compatibility. Use `supportedTransferSyntaxUIDs` for full list.
public let supportedTransferSyntaxUID = "1.2.840.10008.1.2.1"
