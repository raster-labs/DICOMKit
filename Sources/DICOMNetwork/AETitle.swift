import Foundation
// NEMA-verified: 2026a, checked 2026-09-28 — compared with PS3.8 2026a Table 9-11 (16 characters, ISO 646:1990 basic G0 set 0x20-0x7E, leading/trailing SPACE non-significant) and PS3.5 Table 6.2-1 AE (no backslash), matching DICOMCore's DICOMApplicationEntity

/// DICOM Application Entity (AE) Title for network communication
///
/// An AE Title identifies an application entity in DICOM networking.
/// PS3.8 Table 9-11: 16 characters of the ISO 646:1990 Basic G0 Set
/// (20H-7EH), with leading and trailing spaces (20H) being non-significant.
/// Backslash (5CH) is excluded because the same title travels in AE-VR
/// elements (PS3.5 Table 6.2-1), where it is the multi-value delimiter.
///
/// Reference: PS3.8 Section 9.3.2 - A-ASSOCIATE-RQ PDU
public struct AETitle: Sendable, Hashable {
    /// The raw AE Title value (1-16 characters)
    public let value: String
    
    /// Maximum length for an AE Title
    public static let maxLength = 16
    
    /// Whether a byte is allowed in an AE Title: ISO 646 Basic G0 (20H-7EH)
    /// excluding backslash (5CH)
    private static func isPermitted(_ byte: UInt8) -> Bool {
        byte >= 0x20 && byte <= 0x7E && byte != 0x5C
    }
    
    /// Creates an AE Title from a string value
    ///
    /// Leading and trailing spaces are removed; any other character outside
    /// 20H-7EH (or a backslash) is rejected.
    ///
    /// - Parameter value: The AE Title string (1-16 G0 characters)
    /// - Throws: `DICOMNetworkError.invalidAETitle` if the value is invalid
    public init(_ value: String) throws {
        // PS3.8 Table 9-11: only SPACE (20H) padding is non-significant
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: " "))
        
        guard !trimmed.isEmpty else {
            throw DICOMNetworkError.invalidAETitle(value)
        }
        
        guard trimmed.utf8.count <= Self.maxLength else {
            throw DICOMNetworkError.invalidAETitle(value)
        }
        
        // ISO 646:1990 Basic G0 Set only, no backslash
        guard trimmed.utf8.allSatisfy(Self.isPermitted) else {
            throw DICOMNetworkError.invalidAETitle(value)
        }
        
        self.value = trimmed
    }
    
    /// The AE Title padded to 16 characters with trailing spaces
    ///
    /// Used for network transmission where fixed-length fields are required.
    public var paddedValue: String {
        value.padding(toLength: Self.maxLength, withPad: " ", startingAt: 0)
    }
    
    /// The AE Title as Data for network transmission (16 bytes, ASCII)
    public var data: Data {
        Data(paddedValue.utf8)
    }
    
    /// Creates an AE Title from padded network data
    ///
    /// PS3.8 Table 9-11 pads with spaces (20H); trailing NUL (00H) padding
    /// from lenient peers is tolerated on decode.
    ///
    /// - Parameter data: 16 bytes of ASCII data
    /// - Returns: An AE Title, or nil if the data is invalid
    public static func from(data: Data) -> AETitle? {
        guard data.count == maxLength else { return nil }
        var bytes = Array(data)
        while bytes.last == 0x00 {
            bytes.removeLast()
        }
        guard let string = String(bytes: bytes, encoding: .ascii) else { return nil }
        return try? AETitle(string)
    }
}

// MARK: - CustomStringConvertible
extension AETitle: CustomStringConvertible {
    public var description: String {
        value
    }
}

// MARK: - ExpressibleByStringLiteral
extension AETitle: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        // For string literals, we assume they are valid and crash if not
        // This is acceptable since string literals are compile-time constants
        do {
            try self.init(value)
        } catch {
            fatalError("Invalid AE Title string literal: '\(value)'")
        }
    }
}
