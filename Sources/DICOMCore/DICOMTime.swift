import Foundation

/// DICOM Time (TM) value representation
///
/// Represents a time in DICOM format.
/// Reference: DICOM PS3.5 Section 6.2 - TM Value Representation
///
/// Grammar checked against PS3.5 2026d Table 6.2-1. Use `parseStrict` for DICOM
/// admission; `parse` also accepts the documented ACR-NEMA HH:MM:SS form.
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
    
    /// Parses a TM value with compatibility for ACR-NEMA `HH:MM:SS[.FFFFFF]`.
    ///
    /// Accepts complete HH, HHMM or HHMMSS components and 1–6 fractional digits
    /// only after seconds. Only trailing ASCII SPACE padding is allowed. Invalid
    /// suffixes, incomplete components and excessive fractions are rejected.
    /// Colon syntax is a deliberate compatibility extension, not valid DICOM TM.
    /// Use `parseStrict` when validating DICOM metadata.
    public static func parse(_ string: String) -> DICOMTime? {
        parseBytes(string.utf8, allowLegacyColons: true)
    }

    /// Parses one strict DICOM TM value (PS3.5 Table 6.2-1).
    ///
    /// Accepts ASCII HH, HHMM, HHMMSS or HHMMSS followed by a decimal point and
    /// 1–6 digits, with trailing ASCII SPACE padding, at most 14 bytes total.
    /// Empty values, query matching syntax, delimiters and colon forms return nil.
    /// Unpadded values are accepted; encoded Value Field evenness is a separate
    /// structural check. Omitted components remain nil. Fractions are represented
    /// exactly in microseconds; the original fractional digit count is not retained.
    /// Second 60 is preserved as leap-second syntax; the actual leap event requires
    /// date and timezone context and is not established by this scalar parser.
    public static func parseStrict(_ string: String) -> DICOMTime? {
        parseBytes(string.utf8, allowLegacyColons: false)
    }

    /// Parses borrowed bytes without copying or retaining them.
    ///
    /// Uses the same strict grammar as the String overload. The caller must keep
    /// the buffer valid for this synchronous call. Work is bounded by the 14-byte
    /// TM limit, and the result contains only scalar components. No String, Data,
    /// array, owner or callback is created or retained by this parser.
    public static func parseStrict(_ bytes: UnsafeRawBufferPointer) -> DICOMTime? {
        guard bytes.count <= 14 else { return nil }
        return parseBytes(bytes, allowLegacyColons: false)
    }

    private static func parseBytes<Bytes: BidirectionalCollection>(
        _ bytes: Bytes, allowLegacyColons: Bool
    ) -> DICOMTime? where Bytes.Element == UInt8 {
        // Bound traversal even for a non-contiguous String UTF-8 view. The two
        // additional compatibility bytes account only for the two legacy colons.
        let limit = allowLegacyColons ? 16 : 14
        var cursor = bytes.startIndex
        var count = 0
        while cursor != bytes.endIndex {
            guard count < limit else { return nil }
            bytes.formIndex(after: &cursor)
            count += 1
        }
        guard count >= 2 else { return nil }
        var end = bytes.endIndex
        while end != bytes.startIndex {
            let previous = bytes.index(before: end)
            guard bytes[previous] == 0x20 else { break }
            end = previous
        }
        cursor = bytes.startIndex
        func pair() -> Int? {
            guard cursor != end else { return nil }
            let tens = bytes[cursor]
            bytes.formIndex(after: &cursor)
            guard cursor != end else { return nil }
            let units = bytes[cursor]
            bytes.formIndex(after: &cursor)
            guard (48...57).contains(tens), (48...57).contains(units) else { return nil }
            return Int(tens - 48) * 10 + Int(units - 48)
        }
        guard let hour = pair(), hour <= 23 else { return nil }
        // Standard syntax keeps the 14-byte limit even on the compatibility API.
        let legacy = cursor != end && bytes[cursor] == 0x3A
        guard legacy ? allowLegacyColons : count <= 14 else { return nil }
        if cursor == end { return DICOMTime(hour: hour) }
        if legacy { bytes.formIndex(after: &cursor) }
        guard let minute = pair(), minute <= 59 else { return nil }
        if cursor == end {
            return legacy ? nil : DICOMTime(hour: hour, minute: minute)
        }
        if legacy {
            guard bytes[cursor] == 0x3A else { return nil }
            bytes.formIndex(after: &cursor)
        }
        guard let second = pair(), second <= 60 else { return nil }
        if cursor == end { return DICOMTime(hour: hour, minute: minute, second: second) }
        guard bytes[cursor] == 0x2E else { return nil }
        bytes.formIndex(after: &cursor)
        var fraction = 0
        var digits = 0
        while cursor != end {
            let byte = bytes[cursor]
            guard digits < 6, (48...57).contains(byte) else { return nil }
            fraction = fraction * 10 + Int(byte - 48)
            digits += 1
            bytes.formIndex(after: &cursor)
        }
        guard digits > 0 else { return nil }
        for _ in digits..<6 { fraction *= 10 }
        return DICOMTime(hour: hour, minute: minute, second: second, microsecond: fraction)
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
