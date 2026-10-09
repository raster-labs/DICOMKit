import Foundation

/// Errors that can occur during DICOM parsing and processing
///
/// NEMA-verified: 2026a, checked 2026-09-25 — the only standard facts here are the 128-byte
/// preamble and the 4-byte "DICM" prefix, both from PS3.10 2026a §7.1 "DICOM File Meta
/// Information". No other standard data. C1 classification confirmed.
public enum DICOMError: Error, Sendable {
    /// Invalid or missing 128-byte preamble
    ///
    /// Reference: PS3.10 Section 7.1 - DICOM File Meta Information
    case invalidPreamble

    /// Invalid or missing "DICM" prefix after preamble
    ///
    /// Reference: PS3.10 Section 7.1 - DICOM File Meta Information
    case invalidDICMPrefix
    
    /// Unexpected end of data while parsing
    case unexpectedEndOfData
    
    /// Invalid or unsupported Value Representation
    case invalidVR(String)
    
    /// Unsupported Transfer Syntax UID
    ///
    /// The Transfer Syntax UID in the File Meta Information names a syntax whose
    /// data-set encoding this library cannot parse. The registered syntaxes are
    /// those of `TransferSyntax`; pixel-data codec availability is a separate
    /// question, reported through `PixelDataError.unsupportedTransferSyntax`.
    case unsupportedTransferSyntax(String)
    
    /// Invalid tag structure or value
    case invalidTag
    
    /// General parsing failure with description
    case parsingFailed(String)

    /// A configured or built-in resource limit was exceeded while parsing
    ///
    /// Raised when input declares structures that exceed safety ceilings
    /// (sequence nesting depth, element length, element count, fragment count).
    /// This protects against malformed or hostile files causing stack overflow
    /// or unbounded allocation. See `ParsingOptions` limit properties.
    case limitExceeded(String)
}

extension DICOMError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidPreamble:
            return "Invalid DICOM preamble"
        case .invalidDICMPrefix:
            return "Invalid DICM prefix: File is missing the 'DICM' magic bytes at offset 128. This may be a legacy DICOM file without Part 10 header. Use DICOMFile.read(from:force:) with force=true to attempt reading legacy files."
        case .unexpectedEndOfData:
            return "Unexpected end of data"
        case .invalidVR(let vr):
            return "Invalid Value Representation: \(vr)"
        case .unsupportedTransferSyntax(let uid):
            return "Unsupported Transfer Syntax: \(uid)"
        case .invalidTag:
            return "Invalid tag"
        case .parsingFailed(let message):
            return "Parsing failed: \(message)"
        case .limitExceeded(let message):
            return "Resource limit exceeded: \(message)"
        }
    }
}

extension DICOMError: LocalizedError {
    public var errorDescription: String? {
        description
    }
}
