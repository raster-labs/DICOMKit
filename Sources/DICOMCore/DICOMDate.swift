import Foundation

/// DICOM Date (DA) value representation
///
/// Represents a date in DICOM format (YYYYMMDD).
/// Reference: DICOM PS3.5 Section 6.2 - DA Value Representation
///
/// NEMA-verified: 2026a, checked 2026-09-25 — matches the DA row of PS3.5 2026a Table 6.2-1 (YYYYMMDD, 8 bytes fixed). The ACR-NEMA YYYY.MM.DD form is accepted on read; the row calls it non-compliant, and `dicomString` never emits it.
///
/// The DA format is a string of characters with format YYYYMMDD where:
/// - YYYY = year (e.g., 2025)
/// - MM = month (01-12)
/// - DD = day of month (01-31)
///
/// Example: "20250130" represents January 30, 2025
public struct DICOMDate: Sendable, Hashable {
    /// Year component (e.g., 2025)
    public let year: Int
    
    /// Month component (1-12)
    public let month: Int
    
    /// Day component (1-31)
    public let day: Int
    
    /// Creates a DICOM date from components
    /// - Parameters:
    ///   - year: Year (4 digits)
    ///   - month: Month (1-12)
    ///   - day: Day (1-31)
    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }
    
    /// Parses a DICOM DA string into a DICOMDate
    ///
    /// Accepts formats:
    /// - YYYYMMDD (8 characters) - standard format
    /// - YYYY.MM.DD (10 characters) - legacy format with dots
    ///
    /// Reference: DICOM PS3.5 Section 6.2 - DA Value Representation
    ///
    /// - Parameter string: The DA string to parse
    /// - Returns: A DICOMDate if parsing succeeds, nil otherwise
    public static func parse(_ string: String) -> DICOMDate? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        
        // Handle legacy format with dots (YYYY.MM.DD)
        let normalized: String
        if trimmed.contains(".") {
            normalized = trimmed.replacingOccurrences(of: ".", with: "")
        } else {
            normalized = trimmed
        }
        
        // Must be exactly 8 characters for YYYYMMDD
        guard normalized.count == 8 else {
            return nil
        }
        
        // Parse year (first 4 characters)
        let yearStr = String(normalized.prefix(4))
        guard let year = Int(yearStr), year >= 0 else {
            return nil
        }
        
        // Parse month (characters 5-6)
        let monthStartIndex = normalized.index(normalized.startIndex, offsetBy: 4)
        let monthEndIndex = normalized.index(normalized.startIndex, offsetBy: 6)
        let monthStr = String(normalized[monthStartIndex..<monthEndIndex])
        guard let month = Int(monthStr), month >= 1, month <= 12 else {
            return nil
        }
        
        // Parse day (characters 7-8)
        let dayStartIndex = normalized.index(normalized.startIndex, offsetBy: 6)
        let dayStr = String(normalized[dayStartIndex...])
        guard let day = Int(dayStr), day >= 1, day <= 31 else {
            return nil
        }
        
        return DICOMDate(year: year, month: month, day: day)
    }
    
    /// Converts to a Foundation Date object
    ///
    /// Uses UTC timezone for consistency. Returns nil if the date components
    /// don't form a valid calendar date.
    ///
    /// - Returns: A Date object if the date is valid, nil otherwise
    public func toDate() -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        
        return Calendar(identifier: .gregorian).date(from: components)
    }
    
    /// Returns the DICOM DA format string (YYYYMMDD)
    public var dicomString: String {
        return String(format: "%04d%02d%02d", year, month, day)
    }
}

extension DICOMDate: CustomStringConvertible {
    public var description: String {
        return dicomString
    }
}
