import Foundation

/// DICOM Time (TM) value representation
///
/// Represents a time in DICOM format.
/// Reference: DICOM PS3.5 Section 6.2 - TM Value Representation
///
/// NEMA-verified: 2026a, checked 2026-09-25 — matches the TM row of PS3.5 2026a Table 6.2-1 (HH, HHMM, HHMMSS, 1-6 fractional digits, SS up to 60 for a leap second, 14 bytes max; the doc comment said 16). The ACR-NEMA HH:MM:SS form is accepted on read only.
///
/// The TM format is a string of characters with format HHMMSS.FFFFFF where:
/// - HH = hour (00-23)
/// - MM = minute (00-59, optional)
/// - SS = second (00-60, optional, 60 for leap second)
/// - FFFFFF = fractional second (optional, 1-6 digits)
///
/// Minimum format is HH, maximum is HHMMSS.FFFFFF (14 bytes maximum per PS3.5 Table 6.2-1)
///
/// Examples:
/// - "14" = 2 PM
/// - "1430" = 2:30 PM
/// - "143025" = 2:30:25 PM
/// - "143025.123456" = 2:30:25.123456 PM
public struct DICOMTime: Sendable, Hashable {
    /// Hour component (0-23)
    public let hour: Int
    
    /// Minute component (0-59), nil if not specified
    public let minute: Int?
    
    /// Second component (0-60, 60 for leap second), nil if not specified
    public let second: Int?
    
    /// Fractional second as microseconds (0-999999), nil if not specified
    public let microsecond: Int?
    
    /// Creates a DICOM time from components
    /// - Parameters:
    ///   - hour: Hour (0-23)
    ///   - minute: Minute (0-59), optional
    ///   - second: Second (0-60), optional
    ///   - microsecond: Microseconds (0-999999), optional
    public init(hour: Int, minute: Int? = nil, second: Int? = nil, microsecond: Int? = nil) {
        self.hour = hour
        self.minute = minute
        self.second = second
        self.microsecond = microsecond
    }
    
    /// Parses a DICOM TM string into a DICOMTime
    ///
    /// Accepts various formats:
    /// - HH (2 characters)
    /// - HHMM (4 characters)
    /// - HHMMSS (6 characters)
    /// - HHMMSS.FFFFFF (13 characters; 14 bytes with padding)
    ///
    /// Also handles legacy formats with colons (HH:MM:SS).
    ///
    /// Reference: DICOM PS3.5 Section 6.2 - TM Value Representation
    ///
    /// - Parameter string: The TM string to parse
    /// - Returns: A DICOMTime if parsing succeeds, nil otherwise
    public static func parse(_ string: String) -> DICOMTime? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        
        // Handle legacy format with colons
        let normalized = trimmed.replacingOccurrences(of: ":", with: "")
        
        // Separate the main part from fractional seconds.
        // Keep empty subsequences so an empty/dot-only value yields an empty
        // main part (handled by the length guard below) instead of trapping.
        let parts = normalized.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let mainPart = parts.isEmpty ? "" : String(parts[0])
        let fractionalPart = parts.count > 1 ? String(parts[1]) : nil

        guard mainPart.count >= 2 else {
            return nil
        }
        
        // Parse hour (first 2 characters)
        let hourStr = String(mainPart.prefix(2))
        guard let hour = Int(hourStr), hour >= 0, hour <= 23 else {
            return nil
        }
        
        // Parse minute (characters 3-4, if present)
        var minute: Int? = nil
        if mainPart.count >= 4 {
            let minuteStartIndex = mainPart.index(mainPart.startIndex, offsetBy: 2)
            let minuteEndIndex = mainPart.index(mainPart.startIndex, offsetBy: 4)
            let minuteStr = String(mainPart[minuteStartIndex..<minuteEndIndex])
            guard let m = Int(minuteStr), m >= 0, m <= 59 else {
                return nil
            }
            minute = m
        }
        
        // Parse second (characters 5-6, if present)
        var second: Int? = nil
        if mainPart.count >= 6 {
            let secondStartIndex = mainPart.index(mainPart.startIndex, offsetBy: 4)
            let secondEndIndex = mainPart.index(mainPart.startIndex, offsetBy: 6)
            let secondStr = String(mainPart[secondStartIndex..<secondEndIndex])
            guard let s = Int(secondStr), s >= 0, s <= 60 else {
                return nil
            }
            second = s
        }
        
        // Parse fractional seconds (up to 6 digits)
        var microsecond: Int? = nil
        if let frac = fractionalPart {
            // Pad or truncate to 6 digits
            let paddedFrac: String
            if frac.count < 6 {
                paddedFrac = frac + String(repeating: "0", count: 6 - frac.count)
            } else {
                paddedFrac = String(frac.prefix(6))
            }
            guard let us = Int(paddedFrac), us >= 0 else {
                return nil
            }
            microsecond = us
        }
        
        return DICOMTime(hour: hour, minute: minute, second: second, microsecond: microsecond)
    }
    
    /// Returns time components as DateComponents
    ///
    /// Useful for combining with a DICOMDate to create a full Date object.
    ///
    /// - Returns: DateComponents with hour, minute, second, and nanosecond
    public func toDateComponents() -> DateComponents {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute ?? 0
        components.second = second ?? 0
        if let us = microsecond {
            components.nanosecond = us * 1000
        }
        return components
    }
    
    /// Returns the DICOM TM format string
    ///
    /// Produces the shortest valid representation:
    /// - HH if only hour specified
    /// - HHMM if hour and minute specified
    /// - HHMMSS if hour, minute, and second specified
    /// - HHMMSS.FFFFFF if fractional seconds specified
    public var dicomString: String {
        var result = String(format: "%02d", hour)
        
        if let m = minute {
            result += String(format: "%02d", m)
            
            if let s = second {
                result += String(format: "%02d", s)
                
                if let us = microsecond {
                    result += String(format: ".%06d", us)
                }
            }
        }
        
        return result
    }
}

extension DICOMTime: CustomStringConvertible {
    public var description: String {
        return dicomString
    }
}
