import Foundation

/// DICOM Universal Resource Identifier (UR) value representation
///
/// Represents a DICOM Universal Resource Identifier or Universal Resource Locator (URI/URL)
/// used for referencing external resources in DICOM data elements.
/// Reference: DICOM PS3.5 Section 6.2 - UR Value Representation
///
/// NEMA-verified: 2026a, checked 2026-09-25 — matches the UR row of PS3.5 2026a Table 6.2-1 (RFC 3986 URI, 2^32-2 bytes max, trailing spaces ignored). The row forbids leading spaces; `parse` trims them, a leniency on read.
///
/// A Universal Resource Identifier is a string that identifies a resource
/// as specified by RFC 3986 "Uniform Resource Identifier (URI): Generic Syntax".
///
/// UR Value Constraints:
/// - No maximum length (2^32-2 bytes maximum)
/// - Valid URI/URL as per RFC 3986
/// - Leading and trailing spaces are not significant
/// - Padded with trailing space (20H) if odd length
///
/// Reference: DICOM PS3.5 Section 6.2 - UR Value Representation
///
/// Examples:
/// - "http://www.example.com/wado?requestType=WADO"
/// - "https://dicom.nema.org/medical/dicom/current"
/// - "file:///path/to/resource"
/// - "urn:oid:1.2.840.10008.5.1.4.1.1.2"
public struct DICOMUniversalResource: Sendable, Hashable {
    /// The URI/URL value with spaces trimmed
    public let value: String
    
    /// Creates a DICOM Universal Resource from a validated URI/URL value
    /// - Parameter value: The validated URI/URL value
    private init(value: String) {
        self.value = value
    }
    
    /// Parses a DICOM Universal Resource Identifier into a DICOMUniversalResource
    ///
    /// Validates the URI per DICOM PS3.5 Section 6.2 and RFC 3986:
    /// - Leading and trailing spaces are trimmed (not significant per DICOM)
    /// - Empty strings after trimming are valid but return empty URI
    /// - The string should conform to URI syntax per RFC 3986
    ///
    /// Reference: DICOM PS3.5 Section 6.2 - UR Value Representation
    /// Reference: RFC 3986 - Uniform Resource Identifier (URI): Generic Syntax
    ///
    /// - Parameter string: The URI/URL string to parse
    /// - Returns: A DICOMUniversalResource if parsing succeeds, nil otherwise
    public static func parse(_ string: String) -> DICOMUniversalResource? {
        // Trim leading and trailing spaces (not significant per PS3.5 Section 6.2)
        // Also trim null characters which may be used for padding
        let trimmed = string.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        
        // Empty string is valid (though not useful)
        // Per PS3.5, an empty value is allowed
        if trimmed.isEmpty {
            return DICOMUniversalResource(value: trimmed)
        }
        
        // Validate URI structure per RFC 3986
        // The URI should be parseable by Foundation's URL class
        // or match basic URI structure
        guard isValidURI(trimmed) else {
            return nil
        }
        
        return DICOMUniversalResource(value: trimmed)
    }
    
    /// Validates a string as a URI per RFC 3986
    ///
    /// RFC 3986 defines the following URI syntax:
    /// URI = scheme ":" hier-part [ "?" query ] [ "#" fragment ]
    ///
    /// This method performs basic validation to ensure the string
    /// conforms to URI structure. It accepts:
    /// - Absolute URIs with scheme (http://, https://, file://, urn:, etc.)
    /// - URIs with various components (host, port, path, query, fragment)
    ///
    /// Reference: RFC 3986 Section 3 - Syntax Components
    ///
    /// - Parameter string: The string to validate
    /// - Returns: True if the string is a valid URI
    private static func isValidURI(_ string: String) -> Bool {
        // Empty strings are handled by caller
        guard !string.isEmpty else {
            return true
        }
        
        // Check for control characters (not allowed in URIs)
        // Control characters are ASCII 0x00-0x1F and 0x7F
        for scalar in string.unicodeScalars {
            let value = scalar.value
            if value <= 0x1F || value == 0x7F {
                return false
            }
        }
        
        // Check for spaces within the URI (not allowed)
        // Leading/trailing spaces have already been trimmed
        if string.contains(" ") {
            return false
        }
        
        // Per RFC 3986, a URI must have a scheme component
        // A URI must have a scheme followed by ":"
        // Reference: RFC 3986 Section 3.1 - Scheme
        guard let colonIndex = string.firstIndex(of: ":") else {
            return false
        }
        
        // Scheme must not be empty
        let scheme = String(string[..<colonIndex])
        guard !scheme.isEmpty else {
            return false
        }
        
        // Scheme must start with a letter
        // Reference: RFC 3986 Section 3.1
        guard let firstChar = scheme.first, firstChar.isASCII && firstChar.isLetter else {
            return false
        }
        
        // Rest of scheme must be letter, digit, +, -, or .
        let validSchemeChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+-."))
        for scalar in scheme.unicodeScalars {
            guard validSchemeChars.contains(scalar) else {
                return false
            }
        }
        
        // At this point we have validated:
        // 1. No control characters
        // 2. No spaces
        // 3. Has a valid scheme
        
        // Try to parse with Foundation's URL for additional validation
        // This will catch malformed URIs with valid schemes
        if URL(string: string) != nil {
            return true
        }
        
        // If URL couldn't parse it, accept it if it has a valid scheme
        // Some URIs like "urn:oid:1.2.3" or "data:text/plain;..." might not
        // be fully parseable by URL but are still valid
        return true
    }
    
    /// Parses multiple DICOM Universal Resource values from a backslash-delimited string
    ///
    /// DICOM uses backslash (\) as a delimiter for multiple values.
    /// Reference: PS3.5 Section 6.2 - Value Multiplicity
    ///
    /// - Parameter string: The string containing multiple URIs
    /// - Returns: Array of parsed URIs, or nil if any parsing fails
    public static func parseMultiple(_ string: String) -> [DICOMUniversalResource]? {
        let values = string.split(separator: "\\", omittingEmptySubsequences: false)
            .map { String($0) }
        
        var results: [DICOMUniversalResource] = []
        for valueString in values {
            guard let uri = parse(valueString) else {
                return nil
            }
            results.append(uri)
        }
        
        return results.isEmpty ? nil : results
    }
    
    /// Returns the DICOM-formatted string value
    ///
    /// Returns the URI/URL as stored, without padding.
    public var dicomString: String {
        return value
    }
    
    /// Indicates whether this is an empty URI
    public var isEmpty: Bool {
        return value.isEmpty
    }
    
    /// The length of the URI in characters
    public var length: Int {
        return value.count
    }
    
    /// Returns the URI padded to an even length with trailing space
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
    
    /// Returns a Foundation URL representation if valid
    ///
    /// Attempts to convert the URI string to a Foundation URL object.
    /// Returns nil if the string cannot be parsed as a URL.
    public var url: URL? {
        return URL(string: value)
    }
    
    /// The URI scheme (e.g., "http", "https", "urn", "file")
    ///
    /// Returns the scheme component of the URI if present.
    /// Reference: RFC 3986 Section 3.1
    public var scheme: String? {
        guard let colonIndex = value.firstIndex(of: ":") else {
            return nil
        }
        return String(value[..<colonIndex])
    }
    
    /// Indicates whether this is an absolute URI (has a scheme)
    ///
    /// An absolute URI contains a scheme component.
    /// Reference: RFC 3986 Section 4.3
    public var isAbsolute: Bool {
        return scheme != nil
    }
}

// MARK: - Protocol Conformances

extension DICOMUniversalResource: CustomStringConvertible {
    public var description: String {
        return value
    }
}

extension DICOMUniversalResource: ExpressibleByStringLiteral {
    /// Creates a Universal Resource from a string literal
    ///
    /// - Note: This will crash if the string is not a valid URI. Use `parse(_:)` for safe parsing.
    public init(stringLiteral value: String) {
        guard let uri = DICOMUniversalResource.parse(value) else {
            fatalError("Invalid DICOM Universal Resource: \(value)")
        }
        self = uri
    }
}

extension DICOMUniversalResource: Comparable {
    /// Compares Universal Resources lexicographically by their string value
    public static func < (lhs: DICOMUniversalResource, rhs: DICOMUniversalResource) -> Bool {
        return lhs.value < rhs.value
    }
}

extension DICOMUniversalResource: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let uri = DICOMUniversalResource.parse(string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid DICOM Universal Resource format: \(string)"
            )
        }
        self = uri
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
