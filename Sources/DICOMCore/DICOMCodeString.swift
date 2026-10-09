import Foundation

/// DICOM Code String (CS) value representation
///
/// Represents a DICOM Code String used for coded values in DICOM data elements.
/// Reference: DICOM PS3.5 Section 6.2 - CS Value Representation
///
/// NEMA-verified: 2026a, checked 2026-09-25 — matches the CS row of PS3.5 2026a Table 6.2-1 (uppercase, digits, SPACE, underscore; 16 bytes max). The Query "Empty Value Matching" form is out of scope for this type.
///
/// A Code String is a string of characters with leading or trailing spaces
/// (20H) being non-significant. The value shall contain only uppercase characters,
/// digits 0-9, the SPACE character, and the underscore character.
///
/// CS Value Constraints:
/// - Maximum 16 characters per value
/// - Characters: uppercase letters A-Z, digits 0-9, SPACE (20H), underscore (_)
/// - Leading and trailing spaces are not significant
///
/// Reference: DICOM PS3.5 Section 6.2 - CS Value Representation
///
/// Examples:
/// - "CT" (Modality)
/// - "HEAD" (Body Part Examined)
/// - "M" or "F" (Patient Sex)
/// - "MR_HEAD" (with underscore)
public struct DICOMCodeString: Sendable, Hashable {
    /// Maximum allowed length for a Code String per DICOM PS3.5 Section 6.2
    public static let maximumLength = 16
    
    /// The Code String value with spaces trimmed
    public let value: String
    
    /// Creates a DICOM Code String from a validated value
    /// - Parameter value: The validated Code String value
    private init(value: String) {
        self.value = value
    }
    
    /// Parses a DICOM Code String into a DICOMCodeString
    ///
    /// Validates the Code String per DICOM PS3.5 Section 6.2:
    /// - Maximum length of 16 characters (after trimming)
    /// - Contains only uppercase letters, digits, SPACE, or underscore
    ///
    /// Leading and trailing spaces are trimmed as they are not significant
    /// per the DICOM standard.
    ///
    /// Reference: DICOM PS3.5 Section 6.2 - CS Value Representation
    ///
    /// - Parameter string: The Code String to parse
    /// - Returns: A DICOMCodeString if parsing succeeds, nil otherwise
    public static func parse(_ string: String) -> DICOMCodeString? {
        // Trim leading and trailing spaces (not significant per PS3.5 Section 6.2)
        // Also trim null characters which may be used for padding
        let trimmed = string.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        
        // Empty string is valid (though not useful)
        // Per PS3.5, an empty value is allowed
        if trimmed.isEmpty {
            return DICOMCodeString(value: trimmed)
        }
        
        // Check maximum length per PS3.5 Section 6.2
        guard trimmed.count <= maximumLength else {
            return nil
        }
        
        // Validate characters: must be uppercase letters, digits, SPACE, or underscore
        // Valid characters: A-Z (0x41-0x5A), 0-9 (0x30-0x39), SPACE (0x20), _ (0x5F)
        for scalar in trimmed.unicodeScalars {
            let value = scalar.value
            
            // Check if character is valid
            let isUppercase = value >= 0x41 && value <= 0x5A  // A-Z
            let isDigit = value >= 0x30 && value <= 0x39      // 0-9
            let isSpace = value == 0x20                        // SPACE
            let isUnderscore = value == 0x5F                   // _
            
            guard isUppercase || isDigit || isSpace || isUnderscore else {
                return nil
            }
        }
        
        return DICOMCodeString(value: trimmed)
    }
    
    /// Parses multiple DICOM Code String values from a backslash-delimited string
    ///
    /// DICOM uses backslash (\) as a delimiter for multiple values.
    /// Reference: PS3.5 Section 6.2 - Value Multiplicity
    ///
    /// - Parameter string: The string containing multiple Code Strings
    /// - Returns: Array of parsed Code Strings, or nil if any parsing fails
    public static func parseMultiple(_ string: String) -> [DICOMCodeString]? {
        let values = string.split(separator: "\\", omittingEmptySubsequences: false)
            .map { String($0) }
        
        var results: [DICOMCodeString] = []
        for valueString in values {
            guard let cs = parse(valueString) else {
                return nil
            }
            results.append(cs)
        }
        
        return results.isEmpty ? nil : results
    }
    
    /// Returns the DICOM-formatted string value
    ///
    /// Returns the Code String as stored, without padding.
    public var dicomString: String {
        return value
    }
    
    /// Indicates whether this is an empty Code String
    public var isEmpty: Bool {
        return value.isEmpty
    }
    
    /// The length of the Code String in characters
    public var length: Int {
        return value.count
    }
    
    /// Returns the Code String padded to an even length with trailing space
    ///
    /// DICOM requires string values to have even length. This property
    /// returns the value padded with a trailing space if needed.
    ///
    /// Reference: PS3.5 Section 6.2
    public var paddedValue: String {
        if value.count % 2 == 0 {
            return value
        }
        return value + " "
    }
}

// MARK: - Protocol Conformances

extension DICOMCodeString: CustomStringConvertible {
    public var description: String {
        return value
    }
}

extension DICOMCodeString: ExpressibleByStringLiteral {
    /// Creates a Code String from a string literal
    ///
    /// - Note: This will crash if the string is not a valid Code String. Use `parse(_:)` for safe parsing.
    public init(stringLiteral value: String) {
        guard let cs = DICOMCodeString.parse(value) else {
            fatalError("Invalid DICOM Code String: \(value)")
        }
        self = cs
    }
}

extension DICOMCodeString: Comparable {
    /// Compares Code Strings lexicographically by their string value
    public static func < (lhs: DICOMCodeString, rhs: DICOMCodeString) -> Bool {
        return lhs.value < rhs.value
    }
}

extension DICOMCodeString: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let cs = DICOMCodeString.parse(string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid DICOM Code String format: \(string)"
            )
        }
        self = cs
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
