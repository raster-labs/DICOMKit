import Foundation

/// DICOM Decimal String (DS) value representation
///
/// Represents a decimal number in DICOM format.
/// Reference: DICOM PS3.5 Section 6.2 - DS Value Representation
///
/// NEMA-verified: 2026a, checked 2026-09-25 — matches the DS row of PS3.5 2026a Table 6.2-1 (fixed or floating point, optional sign, E/e exponent, 16 bytes max). `Double(_:)` also accepts hexadecimal floats, which the DS repertoire does not; that leniency is on read only.
///
/// A string of characters representing either a fixed point number
/// or a floating point number. A fixed point number shall contain
/// only the characters 0-9 with an optional leading "+" or "-" and
/// an optional "." to mark the decimal point. A floating point number
/// shall be conveyed as defined in ANSI X3.9, with an "E" or "e" to
/// indicate the start of the exponent. Decimal Strings may be padded
/// with leading or trailing spaces. Embedded spaces are not allowed.
///
/// Maximum length: 16 characters (including optional sign and decimal point)
///
/// Examples:
/// - "3.14159"
/// - "-123.456"
/// - "1.5e-2"
/// - "+1234.56E+10"
public struct DICOMDecimalString: Sendable, Hashable {
    /// The parsed decimal value
    public let value: Double
    
    /// The original string representation (trimmed)
    public let originalString: String
    
    /// Creates a DICOM decimal string from a Double value
    /// - Parameter value: The decimal value
    public init(value: Double) {
        self.value = value
        self.originalString = String(value)
    }
    
    /// Creates a DICOM decimal string from components
    /// - Parameters:
    ///   - value: The decimal value
    ///   - originalString: The original string representation
    init(value: Double, originalString: String) {
        self.value = value
        self.originalString = originalString
    }
    
    /// Parses a DICOM DS string into a DICOMDecimalString
    ///
    /// Accepts format:
    /// - Fixed point: [+-]?[0-9]*\.?[0-9]+
    /// - Floating point: [+-]?[0-9]*\.?[0-9]+[eE][+-]?[0-9]+
    ///
    /// Reference: DICOM PS3.5 Section 6.2 - DS Value Representation
    ///
    /// - Parameter string: The DS string to parse
    /// - Returns: A DICOMDecimalString if parsing succeeds, nil otherwise
    public static func parse(_ string: String) -> DICOMDecimalString? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        
        // Empty string is invalid
        guard !trimmed.isEmpty else {
            return nil
        }
        
        // Maximum 16 characters per DICOM standard
        guard trimmed.count <= 16 else {
            return nil
        }
        
        // Parse as Double
        guard let value = Double(trimmed) else {
            return nil
        }
        
        // Validate the parsed value is finite (not NaN or Inf)
        guard value.isFinite else {
            return nil
        }
        
        return DICOMDecimalString(value: value, originalString: trimmed)
    }
    
    /// Parses multiple DICOM DS values from a backslash-delimited string
    ///
    /// DICOM uses backslash (\) as a delimiter for multiple values.
    /// Reference: PS3.5 Section 6.2 - Value Multiplicity
    ///
    /// - Parameter string: The multi-valued DS string to parse
    /// - Returns: Array of DICOMDecimalString values, or nil if any value fails to parse
    public static func parseMultiple(_ string: String) -> [DICOMDecimalString]? {
        let components = string.split(separator: "\\", omittingEmptySubsequences: false)
        var results: [DICOMDecimalString] = []
        
        for component in components {
            guard let parsed = parse(String(component)) else {
                return nil
            }
            results.append(parsed)
        }
        
        return results.isEmpty ? nil : results
    }
    
    /// Returns the value as a Float
    public var floatValue: Float {
        return Float(value)
    }
    
    /// Returns the value as an Int (truncated)
    public var intValue: Int {
        return Int(value)
    }
    
    /// Returns a DICOM-compliant DS format string
    ///
    /// The returned string will be at most 16 characters.
    public var dicomString: String {
        // Format to fit within 16 character limit
        let formatted = String(format: "%.10g", value)
        if formatted.count <= 16 {
            return formatted
        }
        // Fall back to scientific notation if needed
        return String(format: "%.6e", value)
    }
}

extension DICOMDecimalString: CustomStringConvertible {
    public var description: String {
        return originalString
    }
}

extension DICOMDecimalString: Comparable {
    public static func < (lhs: DICOMDecimalString, rhs: DICOMDecimalString) -> Bool {
        return lhs.value < rhs.value
    }
}

extension DICOMDecimalString: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self.init(value: value)
    }
}
