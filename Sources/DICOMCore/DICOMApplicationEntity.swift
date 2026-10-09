import Foundation

/// DICOM Application Entity (AE) value representation
///
/// Represents a DICOM Application Entity Title used to identify DICOM applications.
/// Reference: DICOM PS3.5 Section 6.2 - AE Value Representation
///
/// An Application Entity (AE) Title is a string of characters identifying
/// an application entity. Leading and trailing spaces are not significant
/// and should be ignored.
///
/// AE Title Constraints:
/// - Maximum 16 characters
/// - Characters from the Default Character Repertoire (ISO 646 G0)
/// - Excludes control characters and backslash (\)
/// - Leading and trailing spaces are not significant
///
/// Reference: DICOM PS3.5 Section 6.2 - AE Value Representation
/// Reference: DICOM PS3.8 Section 9.2.1 - AE Title
///
/// NEMA-verified: 2026a, checked 2026-09-25 — matches the AE row of PS3.5 2026a Table 6.2-1 (16 bytes max; Default Character Repertoire without 5CH and control characters; leading/trailing spaces not significant). The row also says a Value of spaces only "shall not be used"; `parse` accepts it as the empty value, a deliberate leniency on read.
///
/// Examples:
/// - "STORESCU"
/// - "PACS_SERVER"
/// - "MY_DICOM_APP"
public struct DICOMApplicationEntity: Sendable, Hashable {
    /// Maximum allowed length for an AE Title per DICOM PS3.5 Section 6.2
    public static let maximumLength = 16
    
    /// The AE Title value with spaces trimmed
    public let value: String
    
    /// Creates a DICOM Application Entity from a validated value
    /// - Parameter value: The validated AE Title value
    private init(value: String) {
        self.value = value
    }
    
    /// Parses a DICOM AE Title string into a DICOMApplicationEntity
    ///
    /// Validates the AE Title per DICOM PS3.5 Section 6.2:
    /// - Maximum length of 16 characters (after trimming)
    /// - Contains only characters from the Default Character Repertoire
    /// - Does not contain control characters or backslash
    ///
    /// Leading and trailing spaces are trimmed as they are not significant
    /// per the DICOM standard.
    ///
    /// Reference: DICOM PS3.5 Section 6.2 - AE Value Representation
    ///
    /// - Parameter string: The AE Title string to parse
    /// - Returns: A DICOMApplicationEntity if parsing succeeds, nil otherwise
    public static func parse(_ string: String) -> DICOMApplicationEntity? {
        // Trim leading and trailing spaces (not significant per PS3.5 Section 6.2)
        // Also trim null characters which may be used for padding
        let trimmed = string.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        
        // Empty string is valid (though not useful)
        // Per PS3.5, an empty value is allowed
        if trimmed.isEmpty {
            return DICOMApplicationEntity(value: trimmed)
        }
        
        // Check maximum length per PS3.5 Section 6.2
        guard trimmed.count <= maximumLength else {
            return nil
        }
        
        // Validate characters: must be from Default Character Repertoire
        // (printable ASCII excluding backslash and control characters)
        // Valid range: 0x20-0x5B (space through '[') and 0x5D-0x7E (']' through '~')
        // This excludes: 0x5C (backslash) and control characters
        for scalar in trimmed.unicodeScalars {
            let value = scalar.value
            
            // Must be within printable ASCII range (0x20-0x7E)
            guard value >= 0x20 && value <= 0x7E else {
                return nil
            }
            
            // Must not be backslash (0x5C)
            guard value != 0x5C else {
                return nil
            }
        }
        
        return DICOMApplicationEntity(value: trimmed)
    }
    
    /// Parses multiple DICOM AE Title values from a backslash-delimited string
    ///
    /// DICOM uses backslash (\) as a delimiter for multiple values.
    /// Reference: PS3.5 Section 6.2 - Value Multiplicity
    ///
    /// - Parameter string: The string containing multiple AE Titles
    /// - Returns: Array of parsed AE Titles, or nil if any parsing fails
    public static func parseMultiple(_ string: String) -> [DICOMApplicationEntity]? {
        let values = string.split(separator: "\\", omittingEmptySubsequences: false)
            .map { String($0) }
        
        var results: [DICOMApplicationEntity] = []
        for valueString in values {
            guard let ae = parse(valueString) else {
                return nil
            }
            results.append(ae)
        }
        
        return results.isEmpty ? nil : results
    }
    
    /// Returns the DICOM-formatted string value
    ///
    /// Returns the AE Title as stored, without padding.
    public var dicomString: String {
        return value
    }
    
    /// Indicates whether this is an empty AE Title
    public var isEmpty: Bool {
        return value.isEmpty
    }
    
    /// The length of the AE Title in characters
    public var length: Int {
        return value.count
    }
    
    /// Returns the AE Title padded to 16 characters with spaces
    ///
    /// Some DICOM implementations require AE Titles to be exactly 16 characters.
    /// This property returns the value padded with trailing spaces.
    ///
    /// Reference: PS3.5 Section 6.2
    public var paddedValue: String {
        return value.padding(toLength: Self.maximumLength, withPad: " ", startingAt: 0)
    }
}

// MARK: - Protocol Conformances

extension DICOMApplicationEntity: CustomStringConvertible {
    public var description: String {
        return value
    }
}

extension DICOMApplicationEntity: ExpressibleByStringLiteral {
    /// Creates an AE Title from a string literal
    ///
    /// - Note: This will crash if the string is not a valid AE Title. Use `parse(_:)` for safe parsing.
    public init(stringLiteral value: String) {
        guard let ae = DICOMApplicationEntity.parse(value) else {
            fatalError("Invalid DICOM Application Entity: \(value)")
        }
        self = ae
    }
}

extension DICOMApplicationEntity: Comparable {
    /// Compares AE Titles lexicographically by their string value
    public static func < (lhs: DICOMApplicationEntity, rhs: DICOMApplicationEntity) -> Bool {
        return lhs.value < rhs.value
    }
}

extension DICOMApplicationEntity: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let ae = DICOMApplicationEntity.parse(string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid DICOM Application Entity format: \(string)"
            )
        }
        self = ae
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
