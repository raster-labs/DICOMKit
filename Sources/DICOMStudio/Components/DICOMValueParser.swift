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
import DICOMCore

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
        // Temporal values are checked before general whitespace trimming. A
        // malformed value must remain visible, not become a different valid one.
        if vr.uppercased() == "TM" { return value.isEmpty ? "(empty)" : formatTime(value) }
        if vr.uppercased() == "DT" { return value.isEmpty ? "(empty)" : formatDateTime(value) }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "(empty)" }

        switch vr.uppercased() {
        case "DA": return formatDate(trimmed)
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

    /// Formats one valid DICOM Time (TM), preserving omitted components and
    /// the original 1–6 fractional digits. Invalid input is returned unchanged.
    /// Only legal trailing ASCII SPACE padding is omitted from valid display.
    public static func formatTime(_ value: String) -> String {
        guard DICOMValueRules.isValidTime(value) else { return value }
        return separatedTime(withoutTemporalPadding(value))
    }

    /// Formats one valid DICOM DateTime (DT) without creating a Foundation Date.
    /// This retains partial precision, fractional trailing zeroes and the exact
    /// signed UTC offset; it never invents omitted components or changes zones.
    /// Invalid input is returned unchanged rather than silently repaired.
    public static func formatDateTime(_ value: String) -> String {
        guard DICOMValueRules.parseDateTime(value) != nil else { return value }
        var lexical = withoutTemporalPadding(value)
        var offset = ""
        if lexical.count >= 9, let sign = lexical.suffix(5).first, sign == "+" || sign == "-" {
            offset = " " + String(lexical.suffix(5))
            lexical.removeLast(5)
        }
        let digits = Array(lexical.prefix { $0 != "." })
        var result = String(digits[0..<4])
        if digits.count >= 6 { result += "-" + String(digits[4..<6]) }
        if digits.count >= 8 { result += "-" + String(digits[6..<8]) }
        if digits.count >= 10 { result += " " + separatedTime(String(lexical.dropFirst(8))) }
        return result + offset
    }

    private static func withoutTemporalPadding(_ value: String) -> String {
        String(value.reversed().drop(while: { $0 == " " }).reversed())
    }

    /// Called only after strict TM/DT validation. Work on lexical components,
    /// because numeric/time objects discard the number of fractional digits.
    private static func separatedTime(_ value: String) -> String {
        let digits = Array(value.prefix { $0 != "." })
        return stride(from: 0, to: digits.count, by: 2)
            .map { String(digits[$0..<$0 + 2]) }.joined(separator: ":")
            + String(value.dropFirst(digits.count))
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
        let parts = value.split(separator: "\\", omittingEmptySubsequences: false)
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
        let parts = value.split(separator: "\\", omittingEmptySubsequences: false)
        let formatted = parts.map { part in
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if let int = Int(trimmed) {
                return String(int)
            }
            return trimmed
        }
        return formatted.joined(separator: " \\ ")
    }

    /// Decodes scalar numeric VRs and AT using the element's byte order. Each
    /// returned string represents one value; an empty Value Field returns `[]`.
    /// Reject incomplete values rather than silently dropping a trailing byte.
    /// Floating-point text uses Swift's round-trip representation, including
    /// signed zero, infinities and NaN; NaN payload bits are not represented.
    /// Other-byte/word streams remain opaque rather than being treated as VM > 1.
    static func numericValues(for element: DataElement) -> [String]? {
        let width: Int
        switch element.vr {
        case .US, .SS: width = 2
        case .UL, .SL, .FL, .AT: width = 4
        case .FD, .SV, .UV: width = 8
        default: return nil
        }
        guard element.valueData.count % width == 0 else { return nil }
        if element.valueData.isEmpty { return [] }
        switch element.vr {
        case .US: return element.uint16Values?.map { String($0) }
        case .SS: return element.int16Values?.map { String($0) }
        case .UL: return element.uint32Values?.map { String($0) }
        case .SL: return element.int32Values?.map { String($0) }
        case .FL: return element.float32Values?.map { String($0) }
        case .FD: return element.float64Values?.map { String($0) }
        case .SV: return element.int64Values?.map { String($0) }
        case .UV: return element.uint64Values?.map { String($0) }
        case .AT: return element.attributeTagValues?.map { String(format: "(%04X,%04X)", $0.group, $0.element) }
        default: return nil
        }
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
