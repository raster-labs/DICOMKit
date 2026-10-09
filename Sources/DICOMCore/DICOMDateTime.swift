import Foundation

/// DICOM DateTime (DT) value representation
///
/// Represents a date and time in DICOM format.
/// Reference: DICOM PS3.5 Section 6.2 - DT Value Representation
///
/// NEMA-verified: 2026a, checked 2026-09-25 — matches the DT row of PS3.5 2026a Table 6.2-1 (YYYY first, trailing null components, 1-6 fractional digits, &ZZXX offset, 26 bytes max). Not enforced on read: the offset range -1200 to +1400 (`parseTimezone` accepts up to -1400) and the ban on -0000; both are accepted leniently.
///
/// The DT format is a concatenated date-time string: YYYYMMDDHHMMSS.FFFFFF&ZZXX where:
/// - YYYYMMDD = date in DA format
/// - HHMMSS.FFFFFF = time in TM format (optional)
/// - &ZZXX = timezone offset (optional), where & is + or -, ZZ is hours, XX is minutes
///
/// Minimum format is YYYY, maximum is 26 characters.
///
/// Examples:
/// - "2025" = year only
/// - "20250130" = date only
/// - "20250130143025" = date and time
/// - "20250130143025.123456" = with fractional seconds
/// - "20250130143025.123456+0530" = with timezone offset
public struct DICOMDateTime: Sendable, Hashable {
    /// Year component (e.g., 2025)
    public let year: Int
    
    /// Month component (1-12), nil if not specified
    public let month: Int?
    
    /// Day component (1-31), nil if not specified
    public let day: Int?
    
    /// Hour component (0-23), nil if not specified
    public let hour: Int?
    
    /// Minute component (0-59), nil if not specified
    public let minute: Int?
    
    /// Second component (0-60), nil if not specified
    public let second: Int?
    
    /// Fractional second as microseconds (0-999999), nil if not specified
    public let microsecond: Int?
    
    /// Timezone offset in minutes from UTC, nil if not specified
    /// Positive values are east of UTC, negative are west.
    public let timezoneOffsetMinutes: Int?
    
    /// Creates a DICOM datetime from components
    public init(
        year: Int,
        month: Int? = nil,
        day: Int? = nil,
        hour: Int? = nil,
        minute: Int? = nil,
        second: Int? = nil,
        microsecond: Int? = nil,
        timezoneOffsetMinutes: Int? = nil
    ) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
        self.microsecond = microsecond
        self.timezoneOffsetMinutes = timezoneOffsetMinutes
    }
    
    /// Parses a DICOM DT string into a DICOMDateTime
    ///
    /// Accepts various formats from minimum (YYYY) to maximum (YYYYMMDDHHMMSS.FFFFFF&ZZXX).
    ///
    /// Reference: DICOM PS3.5 Section 6.2 - DT Value Representation
    ///
    /// - Parameter string: The DT string to parse
    /// - Returns: A DICOMDateTime if parsing succeeds, nil otherwise
    public static func parse(_ string: String) -> DICOMDateTime? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        
        guard trimmed.count >= 4 else {
            return nil
        }
        
        // Extract timezone if present (last 5 characters like +0530 or -0530)
        var mainPart = trimmed
        var timezoneOffset: Int? = nil
        
        if let plusIndex = trimmed.lastIndex(of: "+") {
            let tzStr = String(trimmed[plusIndex...])
            if let offset = parseTimezone(tzStr) {
                timezoneOffset = offset
                mainPart = String(trimmed[..<plusIndex])
            }
        } else if let minusIndex = trimmed.lastIndex(of: "-") {
            // Check if it's a timezone (at least 5 chars from end: -HHMM)
            let distance = trimmed.distance(from: minusIndex, to: trimmed.endIndex)
            if distance == 5 {
                let tzStr = String(trimmed[minusIndex...])
                if let offset = parseTimezone(tzStr) {
                    timezoneOffset = offset
                    mainPart = String(trimmed[..<minusIndex])
                }
            }
        }
        
        // Separate fractional seconds
        var datePart = mainPart
        var microsecond: Int? = nil
        
        if let dotIndex = mainPart.firstIndex(of: ".") {
            let fractionalStr = String(mainPart[mainPart.index(after: dotIndex)...])
            if !fractionalStr.isEmpty {
                let paddedFrac: String
                if fractionalStr.count < 6 {
                    paddedFrac = fractionalStr + String(repeating: "0", count: 6 - fractionalStr.count)
                } else {
                    paddedFrac = String(fractionalStr.prefix(6))
                }
                microsecond = Int(paddedFrac)
            }
            datePart = String(mainPart[..<dotIndex])
        }
        
        // Parse components based on length
        // Minimum: YYYY (4), Maximum: YYYYMMDDHHMMSS (14)
        guard datePart.count >= 4, datePart.count <= 14 else {
            return nil
        }
        
        // Parse year (first 4 characters)
        let yearStr = String(datePart.prefix(4))
        guard let year = Int(yearStr), year >= 0 else {
            return nil
        }
        
        // Parse month (characters 5-6, if present)
        var month: Int? = nil
        if datePart.count >= 6 {
            let startIndex = datePart.index(datePart.startIndex, offsetBy: 4)
            let endIndex = datePart.index(datePart.startIndex, offsetBy: 6)
            let monthStr = String(datePart[startIndex..<endIndex])
            guard let m = Int(monthStr), m >= 1, m <= 12 else {
                return nil
            }
            month = m
        }
        
        // Parse day (characters 7-8, if present)
        var day: Int? = nil
        if datePart.count >= 8 {
            let startIndex = datePart.index(datePart.startIndex, offsetBy: 6)
            let endIndex = datePart.index(datePart.startIndex, offsetBy: 8)
            let dayStr = String(datePart[startIndex..<endIndex])
            guard let d = Int(dayStr), d >= 1, d <= 31 else {
                return nil
            }
            day = d
        }
        
        // Parse hour (characters 9-10, if present)
        var hour: Int? = nil
        if datePart.count >= 10 {
            let startIndex = datePart.index(datePart.startIndex, offsetBy: 8)
            let endIndex = datePart.index(datePart.startIndex, offsetBy: 10)
            let hourStr = String(datePart[startIndex..<endIndex])
            guard let h = Int(hourStr), h >= 0, h <= 23 else {
                return nil
            }
            hour = h
        }
        
        // Parse minute (characters 11-12, if present)
        var minute: Int? = nil
        if datePart.count >= 12 {
            let startIndex = datePart.index(datePart.startIndex, offsetBy: 10)
            let endIndex = datePart.index(datePart.startIndex, offsetBy: 12)
            let minuteStr = String(datePart[startIndex..<endIndex])
            guard let m = Int(minuteStr), m >= 0, m <= 59 else {
                return nil
            }
            minute = m
        }
        
        // Parse second (characters 13-14, if present)
        var second: Int? = nil
        if datePart.count >= 14 {
            let startIndex = datePart.index(datePart.startIndex, offsetBy: 12)
            let endIndex = datePart.index(datePart.startIndex, offsetBy: 14)
            let secondStr = String(datePart[startIndex..<endIndex])
            guard let s = Int(secondStr), s >= 0, s <= 60 else {
                return nil
            }
            second = s
        }
        
        return DICOMDateTime(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second,
            microsecond: microsecond,
            timezoneOffsetMinutes: timezoneOffset
        )
    }
    
    /// Parses a timezone string like "+0530" or "-0800"
    private static func parseTimezone(_ string: String) -> Int? {
        guard string.count == 5 else {
            return nil
        }
        
        let sign: Int
        let offsetStr: String
        
        if string.hasPrefix("+") {
            sign = 1
            offsetStr = String(string.dropFirst())
        } else if string.hasPrefix("-") {
            sign = -1
            offsetStr = String(string.dropFirst())
        } else {
            return nil
        }
        
        guard offsetStr.count == 4 else {
            return nil
        }
        
        let hoursStr = String(offsetStr.prefix(2))
        let minutesStr = String(offsetStr.suffix(2))
        
        guard let hours = Int(hoursStr), hours >= 0, hours <= 14,
              let minutes = Int(minutesStr), minutes >= 0, minutes <= 59 else {
            return nil
        }
        
        return sign * (hours * 60 + minutes)
    }
    
    /// Converts to a Foundation Date object
    ///
    /// Uses the specified timezone offset if available, otherwise UTC.
    /// Returns nil if the date components don't form a valid calendar date.
    ///
    /// - Returns: A Date object if the datetime is valid, nil otherwise
    public func toDate() -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month ?? 1
        components.day = day ?? 1
        components.hour = hour ?? 0
        components.minute = minute ?? 0
        components.second = second ?? 0
        
        if let us = microsecond {
            components.nanosecond = us * 1000
        }
        
        if let offsetMinutes = timezoneOffsetMinutes {
            components.timeZone = TimeZone(secondsFromGMT: offsetMinutes * 60)
        } else {
            components.timeZone = TimeZone(identifier: "UTC")
        }
        
        return Calendar(identifier: .gregorian).date(from: components)
    }
    
    /// The date component as a DICOMDate, if available
    public var date: DICOMDate? {
        guard let m = month, let d = day else {
            return nil
        }
        return DICOMDate(year: year, month: m, day: d)
    }
    
    /// The time component as a DICOMTime, if available
    public var time: DICOMTime? {
        guard let h = hour else {
            return nil
        }
        return DICOMTime(hour: h, minute: minute, second: second, microsecond: microsecond)
    }
    
    /// Returns the DICOM DT format string
    public var dicomString: String {
        var result = String(format: "%04d", year)
        
        if let m = month {
            result += String(format: "%02d", m)
            
            if let d = day {
                result += String(format: "%02d", d)
                
                if let h = hour {
                    result += String(format: "%02d", h)
                    
                    if let min = minute {
                        result += String(format: "%02d", min)
                        
                        if let s = second {
                            result += String(format: "%02d", s)
                            
                            if let us = microsecond {
                                result += String(format: ".%06d", us)
                            }
                        }
                    }
                }
            }
        }
        
        if let offset = timezoneOffsetMinutes {
            let sign = offset >= 0 ? "+" : "-"
            let absOffset = abs(offset)
            let hours = absOffset / 60
            let minutes = absOffset % 60
            result += String(format: "%@%02d%02d", sign, hours, minutes)
        }
        
        return result
    }
}

extension DICOMDateTime: CustomStringConvertible {
    public var description: String {
        return dicomString
    }
}
