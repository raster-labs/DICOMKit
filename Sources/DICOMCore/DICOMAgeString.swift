import Foundation

/// DICOM Age String (AS) value representation
///
/// Represents an age in DICOM format (nnnX).
/// Reference: DICOM PS3.5 Section 6.2 - AS Value Representation
///
/// NEMA-verified: 2026a, checked 2026-09-25 — matches the AS row of PS3.5 2026a Table 6.2-1 (nnnD/W/M/Y, 4 bytes fixed).
///
/// The AS format is a string of 4 characters with format nnnX where:
/// - nnn = 3-digit number (000-999)
/// - X = age unit: D (days), W (weeks), M (months), Y (years)
///
/// Examples:
/// - "018Y" = 18 years old
/// - "003M" = 3 months old
/// - "006W" = 6 weeks old
/// - "045D" = 45 days old
public struct DICOMAgeString: Sendable, Hashable {
    /// Age unit enumeration
    public enum AgeUnit: String, Sendable, Hashable, CaseIterable {
        /// Days
        case days = "D"
        /// Weeks
        case weeks = "W"
        /// Months
        case months = "M"
        /// Years
        case years = "Y"
        
        /// Human-readable description of the unit
        public var description: String {
            switch self {
            case .days: return "days"
            case .weeks: return "weeks"
            case .months: return "months"
            case .years: return "years"
            }
        }
        
        /// Singular form of the unit
        public var singularDescription: String {
            switch self {
            case .days: return "day"
            case .weeks: return "week"
            case .months: return "month"
            case .years: return "year"
            }
        }
    }
    
    /// Numeric value (0-999)
    public let value: Int
    
    /// Age unit (D, W, M, or Y)
    public let unit: AgeUnit
    
    /// Creates a DICOM age string from components
    /// - Parameters:
    ///   - value: Numeric value (0-999)
    ///   - unit: Age unit (days, weeks, months, years)
    public init(value: Int, unit: AgeUnit) {
        self.value = max(0, min(999, value))
        self.unit = unit
    }
    
    /// Parses a DICOM AS string into a DICOMAgeString
    ///
    /// Accepts format:
    /// - nnnX (4 characters) - standard format
    ///
    /// Reference: DICOM PS3.5 Section 6.2 - AS Value Representation
    ///
    /// - Parameter string: The AS string to parse
    /// - Returns: A DICOMAgeString if parsing succeeds, nil otherwise
    public static func parse(_ string: String) -> DICOMAgeString? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        
        // Must be exactly 4 characters
        guard trimmed.count == 4 else {
            return nil
        }
        
        // Parse numeric value (first 3 characters)
        let valueStr = String(trimmed.prefix(3))
        guard let value = Int(valueStr), value >= 0, value <= 999 else {
            return nil
        }
        
        // Parse unit (last character)
        let unitChar = String(trimmed.suffix(1))
        guard let unit = AgeUnit(rawValue: unitChar) else {
            return nil
        }
        
        return DICOMAgeString(value: value, unit: unit)
    }
    
    /// Approximate age in years
    ///
    /// Converts the age to an approximate number of years.
    /// Uses standard approximations:
    /// - Days: value / 365.25
    /// - Weeks: value / 52.18
    /// - Months: value / 12
    /// - Years: value
    ///
    /// - Returns: Approximate age in years as a Double
    public var approximateYears: Double {
        switch unit {
        case .days:
            return Double(value) / 365.25
        case .weeks:
            return Double(value) / 52.18
        case .months:
            return Double(value) / 12.0
        case .years:
            return Double(value)
        }
    }
    
    /// Approximate age in days
    ///
    /// Converts the age to an approximate number of days.
    /// Uses standard approximations:
    /// - Days: value
    /// - Weeks: value * 7
    /// - Months: value * 30.4375 (365.25 / 12)
    /// - Years: value * 365.25
    ///
    /// - Returns: Approximate age in days as a Double
    public var approximateDays: Double {
        switch unit {
        case .days:
            return Double(value)
        case .weeks:
            return Double(value) * 7.0
        case .months:
            return Double(value) * 30.4375  // 365.25 / 12 for consistency
        case .years:
            return Double(value) * 365.25
        }
    }
    
    /// Returns the DICOM AS format string (nnnX)
    public var dicomString: String {
        return String(format: "%03d%@", value, unit.rawValue)
    }
    
    /// Human-readable description of the age
    ///
    /// Examples:
    /// - "18 years"
    /// - "1 year"
    /// - "3 months"
    /// - "1 day"
    public var humanReadable: String {
        let unitStr = value == 1 ? unit.singularDescription : unit.description
        return "\(value) \(unitStr)"
    }
}

extension DICOMAgeString: CustomStringConvertible {
    public var description: String {
        return humanReadable
    }
}

extension DICOMAgeString: Comparable {
    public static func < (lhs: DICOMAgeString, rhs: DICOMAgeString) -> Bool {
        return lhs.approximateDays < rhs.approximateDays
    }
}
