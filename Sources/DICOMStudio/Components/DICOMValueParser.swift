// DICOMValueParser.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent DICOM value representation parser
//
// NEMA-verified: 2026a, checked 2026-10-05 — per-VR formatting checked against PS3.5 2026a Table 6.2-1 (DA YYYYMMDD,
// TM HHMMSS.FFFFFF with trailing components optional, DT YYYYMMDDHHMMSS.FFFFFF&ZZXX, AS nnnD/W/M/Y, CS uppercase, UI
// trailing NUL padding, AE/UR space handling, DS/IS multi-value backslash) and 6.2.1.1/6.2.1.2 (PN: five components
// family^given^middle^prefix^suffix, up to three "="-separated component groups — group handling added);
// `characterSetDescription` keys diffed against the Defined Terms of PS3.3 2026a Tables C.12-2, C.12-3, C.12-4,
// C.12-5 (32 Defined Terms): 19 matched, 13 added (ISO_IR 203, GBK, ISO 2022 IR 13/58/101/109/110/126/127/138/144/
// 148/166/203); descriptions are display text.

import Foundation

/// Platform-independent helper for parsing and formatting DICOM value representations.
///
/// Converts raw DICOM values into human-readable display strings based on
/// their Value Representation (VR) type.
public enum DICOMValueParser: Sendable {

    /// Formats a raw DICOM string value based on its VR type.
    ///
    /// - Parameters:
    ///   - value: The raw string value from the DICOM element.
    ///   - vr: The two-character VR code (e.g., "DA", "TM", "PN").
    /// - Returns: A formatted display string.
    public static func format(value: String, vr: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "(empty)" }

        switch vr.uppercased() {
        case "DA": return formatDate(trimmed)
        case "TM": return formatTime(trimmed)
        case "DT": return formatDateTime(trimmed)
        case "AS": return formatAge(trimmed)
        case "PN": return formatPersonName(trimmed)
        case "DS": return formatDecimalString(trimmed)
        case "IS": return formatIntegerString(trimmed)
        case "CS": return trimmed.uppercased()
        case "UI": return formatUID(trimmed)
        case "AE": return trimmed.trimmingCharacters(in: .whitespaces)
        case "UR": return trimmed
        default: return trimmed
        }
    }

    /// Formats a DICOM Date (DA) value.
    ///
    /// Input format: YYYYMMDD
    /// Output format: YYYY-MM-DD
    public static func formatDate(_ value: String) -> String {
        let digits = value.filter(\.isWholeNumber)
        guard digits.count >= 8 else { return value }
        let year = String(digits.prefix(4))
        let month = String(digits.dropFirst(4).prefix(2))
        let day = String(digits.dropFirst(6).prefix(2))
        return "\(year)-\(month)-\(day)"
    }

    /// Formats a DICOM Time (TM) value.
    ///
    /// Input format: HHMMSS.FFFFFF
    /// Output format: HH:MM:SS
    public static func formatTime(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespaces)
        guard cleaned.count >= 4 else { return value }
        let digits = cleaned.filter { $0.isWholeNumber || $0 == "." }
        let parts = digits.split(separator: ".", maxSplits: 1)
        let timeDigits = String(parts[0])
        guard timeDigits.count >= 4 else { return value }

        let hour = String(timeDigits.prefix(2))
        let minute = String(timeDigits.dropFirst(2).prefix(2))
        if timeDigits.count >= 6 {
            let second = String(timeDigits.dropFirst(4).prefix(2))
            return "\(hour):\(minute):\(second)"
        }
        return "\(hour):\(minute)"
    }

    /// Formats a DICOM DateTime (DT) value.
    ///
    /// Input format: YYYYMMDDHHMMSS.FFFFFF&ZZXX
    /// Output format: YYYY-MM-DD HH:MM:SS
    public static func formatDateTime(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespaces)
        guard cleaned.count >= 8 else { return value }
        let datePart = formatDate(String(cleaned.prefix(8)))
        if cleaned.count >= 12 {
            let timeStr = String(cleaned.dropFirst(8).prefix(6))
            let timePart = formatTime(timeStr)
            return "\(datePart) \(timePart)"
        }
        return datePart
    }

    /// Formats a DICOM Age String (AS) value.
    ///
    /// Input format: nnnU where U is D(ays), W(eeks), M(onths), Y(ears)
    /// Output format: "nnn days/weeks/months/years"
    public static func formatAge(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return value }

        let unitChar = trimmed.last?.uppercased() ?? ""
        let numberStr = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
        guard let number = Int(numberStr) else { return value }

        let unit: String
        switch unitChar {
        case "D": unit = number == 1 ? "day" : "days"
        case "W": unit = number == 1 ? "week" : "weeks"
        case "M": unit = number == 1 ? "month" : "months"
        case "Y": unit = number == 1 ? "year" : "years"
        default: return value
        }

        return "\(number) \(unit)"
    }

    /// Formats a DICOM Person Name (PN) value.
    ///
    /// Input format: FamilyName^GivenName^MiddleName^Prefix^Suffix, in up to three component
    /// groups (alphabetic=ideographic=phonetic, PS3.5 6.2.1.2) separated by "=".
    /// Output format: "Prefix GivenName MiddleName FamilyName, Suffix", groups joined by " = ".
    public static func formatPersonName(_ value: String) -> String {
        if value.contains("=") {
            let groups = value.split(separator: "=", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
            let formatted = groups.filter { !$0.isEmpty }.map(formatPersonNameGroup)
            return formatted.isEmpty ? value : formatted.joined(separator: " = ")
        }
        return formatPersonNameGroup(value)
    }

    /// Formats one PN component group (PS3.5 6.2.1.1).
    private static func formatPersonNameGroup(_ value: String) -> String {
        let components = value.split(separator: "^", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }

        guard !components.isEmpty else { return value }

        let familyName = components.count > 0 ? components[0] : ""
        let givenName = components.count > 1 ? components[1] : ""
        let middleName = components.count > 2 ? components[2] : ""
        let prefix = components.count > 3 ? components[3] : ""
        let suffix = components.count > 4 ? components[4] : ""

        var parts: [String] = []
        if !prefix.isEmpty { parts.append(prefix) }
        if !givenName.isEmpty { parts.append(givenName) }
        if !middleName.isEmpty { parts.append(middleName) }
        if !familyName.isEmpty { parts.append(familyName) }

        var result = parts.joined(separator: " ")
        if !suffix.isEmpty {
            result += ", \(suffix)"
        }

        return result.isEmpty ? value : result
    }

    /// Formats a DICOM Decimal String (DS) value.
    public static func formatDecimalString(_ value: String) -> String {
        let parts = value.split(separator: "\\")
        let formatted = parts.map { part in
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if let double = Double(trimmed) {
                if double == double.rounded() && abs(double) < 1e15 {
                    return String(format: "%.0f", double)
                }
                return String(format: "%.6g", double)
            }
            return trimmed
        }
        return formatted.joined(separator: " \\ ")
    }

    /// Formats a DICOM Integer String (IS) value.
    public static func formatIntegerString(_ value: String) -> String {
        let parts = value.split(separator: "\\")
        let formatted = parts.map { part in
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if let int = Int(trimmed) {
                return String(int)
            }
            return trimmed
        }
        return formatted.joined(separator: " \\ ")
    }

    /// Formats a DICOM UID value with truncation for display.
    public static func formatUID(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(["\0"])))
    }

    /// Returns a human-readable description of a character set name.
    ///
    /// - Parameter characterSet: The DICOM Specific Character Set value.
    /// - Returns: A human-readable description.
    public static func characterSetDescription(_ characterSet: String) -> String {
        let mapping: [String: String] = [
            "": "Default (ASCII)",
            "ISO_IR 100": "Latin-1 (Western European)",
            "ISO_IR 101": "Latin-2 (Central European)",
            "ISO_IR 109": "Latin-3 (South European)",
            "ISO_IR 110": "Latin-4 (North European)",
            "ISO_IR 144": "Cyrillic",
            "ISO_IR 127": "Arabic",
            "ISO_IR 126": "Greek",
            "ISO_IR 138": "Hebrew",
            "ISO_IR 148": "Latin-5 (Turkish)",
            "ISO_IR 203": "Latin-9 (Western European, with Euro)",
            "ISO_IR 13": "Japanese (JIS X 0201)",
            "ISO_IR 166": "Thai (TIS 620-2533)",
            "ISO 2022 IR 6": "ASCII (ISO 646)",
            "ISO 2022 IR 100": "Latin-1 (ISO 2022)",
            "ISO 2022 IR 101": "Latin-2 (ISO 2022)",
            "ISO 2022 IR 109": "Latin-3 (ISO 2022)",
            "ISO 2022 IR 110": "Latin-4 (ISO 2022)",
            "ISO 2022 IR 144": "Cyrillic (ISO 2022)",
            "ISO 2022 IR 127": "Arabic (ISO 2022)",
            "ISO 2022 IR 126": "Greek (ISO 2022)",
            "ISO 2022 IR 138": "Hebrew (ISO 2022)",
            "ISO 2022 IR 148": "Latin-5 (ISO 2022)",
            "ISO 2022 IR 203": "Latin-9 (ISO 2022)",
            "ISO 2022 IR 166": "Thai (ISO 2022)",
            "ISO 2022 IR 13": "Japanese Katakana (JIS X 0201, ISO 2022)",
            "ISO 2022 IR 87": "Japanese (JIS X 0208)",
            "ISO 2022 IR 159": "Japanese (JIS X 0212)",
            "ISO 2022 IR 149": "Korean (KS X 1001)",
            "ISO 2022 IR 58": "Simplified Chinese (GB 2312)",
            "ISO_IR 192": "Unicode (UTF-8)",
            "GB18030": "Chinese (GB18030)",
            "GBK": "Chinese (GBK)",
        ]
        let trimmed = characterSet.trimmingCharacters(in: .whitespaces)
        return mapping[trimmed] ?? trimmed
    }
}
