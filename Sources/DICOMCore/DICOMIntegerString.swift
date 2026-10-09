import Foundation

/// DICOM Integer String (IS) value representation
///
/// Represents an integer number in DICOM format.
/// Reference: DICOM PS3.5 Section 6.2 - IS Value Representation
///
/// NEMA-verified: 2026a, checked 2026-09-25 — matches the IS row of PS3.5 2026a Table 6.2-1 (digits with optional sign, 12 bytes max, -2^31 <= n <= 2^31-1).
///
/// A string of characters representing an Integer in base-10 (decimal),
/// shall contain only the characters 0-9 with an optional leading "+" or "-".
/// Integer Strings may be padded with leading and/or trailing spaces.
/// Embedded spaces are not allowed.
///
/// The integer shall be in the range -2^31 <= n <= (2^31 - 1).
/// Maximum length: 12 characters (including optional sign)
///
/// Examples:
/// - "123"
/// - "-456"
/// - "+789"
/// - "0"
public struct DICOMIntegerString: Sendable, Hashable {
    /// The parsed integer value
    public let value: Int
    
    /// The original string representation (trimmed)
    public let originalString: String
    
    /// Creates a DICOM integer string from an Int value
    ///
    /// Note: The DICOM standard specifies IS values should be in the range
    /// -2^31 <= n <= (2^31 - 1). Values outside this range will be accepted
    /// but `int32Value` will return a clamped result.
    ///
    /// - Parameter value: The integer value
    public init(value: Int) {
        self.value = value
        self.originalString = String(value)
    }
    
    /// Creates a DICOM integer string from components
    /// - Parameters:
    ///   - value: The integer value
    ///   - originalString: The original string representation
    init(value: Int, originalString: String) {
        self.value = value
        self.originalString = originalString
    }
    
    /// Parses a DICOM IS string into a DICOMIntegerString
    ///
    /// Accepts format: [+-]?[0-9]+
    ///
    /// Reference: DICOM PS3.5 Section 6.2 - IS Value Representation
    ///
    /// - Parameter string: The IS string to parse
    /// - Returns: A DICOMIntegerString if parsing succeeds, nil otherwise
    public static func parse(_ string: String) -> DICOMIntegerString? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        
        // Empty string is invalid
        guard !trimmed.isEmpty else {
            return nil
        }
        
        // Maximum 12 characters per DICOM standard
        guard trimmed.count <= 12 else {
            return nil
        }
        
        // Parse as Int
        guard let value = Int(trimmed) else {
            return nil
        }
        
        // Validate range per DICOM standard: -2^31 <= n <= (2^31 - 1)
        // Note: Swift's Int on 64-bit platforms is larger, so we need to check
        let minValue = Int(Int32.min)
        let maxValue = Int(Int32.max)
        guard value >= minValue && value <= maxValue else {
            return nil
        }
        
        return DICOMIntegerString(value: value, originalString: trimmed)
    }
    
    /// Parses multiple DICOM IS values from a backslash-delimited string
    ///
    /// DICOM uses backslash (\) as a delimiter for multiple values.
    /// Reference: PS3.5 Section 6.2 - Value Multiplicity
    ///
    /// - Parameter string: The multi-valued IS string to parse
    /// - Returns: Array of DICOMIntegerString values, or nil if any value fails to parse
    public static func parseMultiple(_ string: String) -> [DICOMIntegerString]? {
        let components = string.split(separator: "\\", omittingEmptySubsequences: false)
        var results: [DICOMIntegerString] = []
        
        for component in components {
            guard let parsed = parse(String(component)) else {
                return nil
            }
            results.append(parsed)
        }
        
        return results.isEmpty ? nil : results
    }
    
    /// Returns the value as an Int32
    ///
    /// Values created via `parse(_:)` are guaranteed to be within Int32 range.
    /// Values created directly via `init(value:)` are clamped to Int32 range.
    public var int32Value: Int32 {
        return Int32(clamping: value)
    }
    
    /// Returns the value as a UInt16 if within range
    public var uint16Value: UInt16? {
        guard value >= 0 && value <= Int(UInt16.max) else {
            return nil
        }
        return UInt16(value)
    }
    
    /// Returns a DICOM-compliant IS format string
    public var dicomString: String {
        return String(value)
    }
}

extension DICOMIntegerString: CustomStringConvertible {
    public var description: String {
        return originalString
    }
}

extension DICOMIntegerString: Comparable {
    public static func < (lhs: DICOMIntegerString, rhs: DICOMIntegerString) -> Bool {
        return lhs.value < rhs.value
    }
}

extension DICOMIntegerString: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self.init(value: value)
    }
}
