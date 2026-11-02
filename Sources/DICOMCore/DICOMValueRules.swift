import Foundation

/// Shared stored-value grammar, lengths and multiplicity from DICOM PS3.5/PS3.6 2026a.
/// Query matching syntax and IOD Type 1/2 requirements are deliberately separate.
public enum DICOMValueRules {

    public struct Rule: Sendable {
        /// Maximum length of one Value; `nil` when only bounded by the 32-bit length.
        public let maxLength: Int?
        /// Fixed length of one Value (AS: 4, DA: 8).
        public let fixedLength: Int?
        /// `true` for "bytes", `false` for "chars" in Table 6.2-1.
        public let countsBytes: Bool
        /// The repertoire, as Table 6.2-1 words it, for messages.
        public let repertoire: String
        public let allows: @Sendable (Unicode.Scalar) -> Bool
    }

    private static func isControl(_ c: Unicode.Scalar) -> Bool { c.value < 0x20 || (0x7F...0x9F).contains(c.value) }
    private static func digit(_ c: Unicode.Scalar) -> Bool { c.value >= 0x30 && c.value <= 0x39 }

    /// LO, SH, PN, UC: no BACKSLASH (it delimits Values) and no Control Characters except ESC.
    private static func stringRepertoire(_ c: Unicode.Scalar) -> Bool {
        c.value == 0x1B || !isControl(c)
    }
    /// LT, ST, UT: no Control Characters except TAB, LF, FF, CR and ESC.
    private static func textRepertoire(_ c: Unicode.Scalar) -> Bool {
        [0x09, 0x0A, 0x0C, 0x0D, 0x1B].contains(c.value) || !isControl(c)
    }

    /// The Table 6.2-1 rule of `vr`; `nil` for binary VRs.
    public static func rule(for vr: VR) -> Rule? {
        switch vr {
        case .AE: return Rule(maxLength: 16, fixedLength: nil, countsBytes: true,
                              repertoire: "Default Character Repertoire excluding BACKSLASH and control characters",
                              allows: { $0.value >= 0x20 && $0.value <= 0x7E && $0 != "\\" })
        case .AS: return Rule(maxLength: nil, fixedLength: 4, countsBytes: true,
                              repertoire: "\"0\"-\"9\", \"D\", \"W\", \"M\", \"Y\"",
                              allows: { digit($0) || "DWMY".unicodeScalars.contains($0) })
        case .CS: return Rule(maxLength: 16, fixedLength: nil, countsBytes: true,
                              repertoire: "uppercase characters, \"0\"-\"9\", SPACE and \"_\"",
                              allows: { ($0.value >= 0x41 && $0.value <= 0x5A) || digit($0) || $0 == " " || $0 == "_" })
        case .DA: return Rule(maxLength: nil, fixedLength: 8, countsBytes: true,
                              repertoire: "\"0\"-\"9\"", allows: digit)
        case .DS: return Rule(maxLength: 16, fixedLength: nil, countsBytes: true,
                              repertoire: "\"0\"-\"9\", \"+\", \"-\", \"E\", \"e\", \".\" and SPACE",
                              allows: { digit($0) || "+-Ee. ".unicodeScalars.contains($0) })
        case .DT: return Rule(maxLength: 26, fixedLength: nil, countsBytes: true,
                              repertoire: "\"0\"-\"9\", \"+\", \"-\", \".\" and SPACE",
                              allows: { digit($0) || "+-. ".unicodeScalars.contains($0) })
        case .IS: return Rule(maxLength: 12, fixedLength: nil, countsBytes: true,
                              repertoire: "\"0\"-\"9\", \"+\", \"-\" and SPACE",
                              allows: { digit($0) || "+- ".unicodeScalars.contains($0) })
        case .LO: return Rule(maxLength: 64, fixedLength: nil, countsBytes: false,
                              repertoire: "no control characters except ESC", allows: stringRepertoire)
        case .LT: return Rule(maxLength: 10240, fixedLength: nil, countsBytes: false,
                              repertoire: "no control characters except TAB, LF, FF, CR, ESC", allows: textRepertoire)
        case .PN: return Rule(maxLength: nil, fixedLength: nil, countsBytes: false,
                              repertoire: "no control characters except ESC", allows: stringRepertoire)
        case .SH: return Rule(maxLength: 16, fixedLength: nil, countsBytes: false,
                              repertoire: "no control characters except ESC", allows: stringRepertoire)
        case .ST: return Rule(maxLength: 1024, fixedLength: nil, countsBytes: false,
                              repertoire: "no control characters except TAB, LF, FF, CR, ESC", allows: textRepertoire)
        case .TM: return Rule(maxLength: 14, fixedLength: nil, countsBytes: true,
                              repertoire: "\"0\"-\"9\", \".\" and SPACE",
                              allows: { digit($0) || $0 == "." || $0 == " " })
        case .UC: return Rule(maxLength: nil, fixedLength: nil, countsBytes: false,
                              repertoire: "no control characters except ESC", allows: stringRepertoire)
        case .UI: return Rule(maxLength: 64, fixedLength: nil, countsBytes: true,
                              repertoire: "\"0\"-\"9\" and \".\"", allows: { digit($0) || $0 == "." })
        case .UR: return Rule(maxLength: nil, fixedLength: nil, countsBytes: true,
                              repertoire: "URI characters from the Default Character Repertoire",
                              allows: { $0.value >= 0x20 && $0.value <= 0x7E && $0 != "\\" })
        case .UT: return Rule(maxLength: nil, fixedLength: nil, countsBytes: false,
                              repertoire: "no control characters except TAB, LF, FF, CR, ESC", allows: textRepertoire)
        default: return nil
        }
    }

    /// VRs whose Value Field holds one Value even when it contains a BACKSLASH (Table 6.2-1:
    /// "shall not be multi-valued").
    public static let singleValued: Set<VR> = [.LT, .ST, .UT, .UR]

    /// Decoded Values, removing only the final legal field-padding byte. Leading
    /// whitespace is retained so that grammar checks can reject it where forbidden.
    public static func values(of element: DataElement) -> [String] {
        guard element.vr.characterRepertoire != nil, element.sequenceItems == nil,
              !element.valueData.isEmpty, let raw = element.decodedStringValue else { return [] }
        var field = raw
        if element.vr == .UI {
            if field.last == "\0" { field.removeLast() }
        } else if field.last == " ", !field.allSatisfy({ $0 == " " }) {
            field.removeLast()
        }
        guard !field.isEmpty else { return [] }
        return singleValued.contains(element.vr) ? [field] : field.components(separatedBy: "\\")
    }

    /// The number of Values (PS3.5 6.4): backslash-delimited Values of a character string, or
    /// Value Length / element size of a fixed-size binary VR; `nil` for VRs whose VM is 1 by
    /// definition (OB, OW, SQ, …) or when the length is not a whole number of elements.
    public static func valueCount(of element: DataElement) -> Int? {
        let size: Int
        switch element.vr {
        case .US, .SS: size = 2
        case .UL, .SL, .FL, .AT: size = 4
        case .FD, .SV, .UV: size = 8
        default:
            if element.vr.characterRepertoire != nil && element.sequenceItems == nil {
                let parts = values(of: element)
                return !singleValued.contains(element.vr) && parts.allSatisfy(\.isEmpty) ? 0 : parts.count
            }
            return nil
        }
        let length = element.valueData.count
        guard length % size == 0 else { return nil }
        return length / size
    }

    /// A PS3.6 Table 6-1 VM: "1", "1-3", "1-n", "2-2n", "3-3n", "1-n or 1".
    public struct ValueMultiplicity: Sendable {
        public let minimum: Int
        public let maximum: Int?      // nil = n
        public let step: Int          // "2-2n": multiples of 2

        public init?(_ text: String) {
            let vm = text.components(separatedBy: " or ").first?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !vm.isEmpty else { return nil }
            let parts = vm.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
            guard let lo = Int(parts[0]), lo > 0 else { return nil }
            if parts.count == 1 {
                minimum = lo; maximum = lo; step = 1
            } else if parts.count == 2 {
                let hi = parts[1]
                if let n = Int(hi), n >= lo {
                    minimum = lo; maximum = n; step = 1
                } else if hi == "n" {
                    minimum = lo; maximum = nil; step = 1
                } else if hi.hasSuffix("n"), let k = Int(hi.dropLast()), k > 0 {
                    minimum = lo; maximum = nil; step = k
                } else {
                    return nil
                }
            } else {
                return nil
            }
        }

        public func allows(_ count: Int) -> Bool {
            if count < minimum { return false }
            if let maximum, count > maximum { return false }
            return count % step == 0
        }
    }

    /// A problem with a complete character Value Field supplied by an editor.
    public static func textProblem(_ text: String, vr: VR) -> String? {
        let parts = singleValued.contains(vr) ? [text] : text.components(separatedBy: "\\")
        return parts.lazy.compactMap { valueProblem($0, vr: vr) }.first
    }

    /// Checks a single stored Value. Empty Values are encodable; IOD Type requirements
    /// are checked separately. Query matching syntax is intentionally not accepted.
    public static func valueProblem(_ value: String, vr: VR) -> String? {
        guard !value.isEmpty else { return nil }
        if let rule = rule(for: vr) {
            if let bad = value.unicodeScalars.first(where: { !rule.allows($0) }) {
                return "character U+\(String(format: "%04X", bad.value)) is not allowed in VR \(vr.rawValue) (PS3.5 Table 6.2-1)"
            }
            let count = rule.countsBytes ? value.utf8.count : value.unicodeScalars.count
            if let fixed = rule.fixedLength, count != fixed {
                return "VR \(vr.rawValue) requires exactly \(fixed) bytes (PS3.5 Table 6.2-1)"
            }
            if let max = rule.maxLength, count > max {
                return "VR \(vr.rawValue) allows at most \(max) \(rule.countsBytes ? "bytes" : "characters") (PS3.5 Table 6.2-1)"
            }
        }
        let valid: Bool
        switch vr {
        case .AE:
            valid = !value.allSatisfy { $0 == " " }
        case .AS:
            valid = matches(value, "[0-9]{3}[DWMY]")
        case .DA:
            valid = isValidDate(value)
        case .DS:
            valid = matches(value, " *[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[Ee][+-]?[0-9]+)? *")
        case .IS:
            valid = matches(value, " *[+-]?[0-9]+ *") && Int32(value.trimmingCharacters(in: CharacterSet(charactersIn: " "))) != nil
        case .TM:
            valid = isValidTime(value)
        case .DT:
            valid = isValidDateTime(value)
        case .UI:
            valid = isValidUID(value)
        case .PN:
            let groups = value.components(separatedBy: "=")
            if groups.count > 3 { return "PN has at most 3 component groups (PS3.5 6.2.1)" }
            for (index, group) in groups.enumerated() {
                let groupLength = group.unicodeScalars.count + (index < groups.count - 1 ? 1 : 0)
                if groupLength > 64 { return "PN allows at most 64 characters per component group (PS3.5 6.2.1)" }
                if group.components(separatedBy: "^").count > 5 { return "a PN component group has at most 5 components (PS3.5 6.2.1)" }
            }
            valid = true
        case .UR:
            let uri = removingTrailingSpaces(value)
            valid = matches(uri, "(?:[A-Za-z0-9._~:/?#\\[\\]@!$&'()*+,;=\\-]|%[0-9A-Fa-f]{2})+")
        default:
            valid = true
        }
        return valid ? nil : "invalid stored \(vr.rawValue) value \(String(reflecting: value)) (PS3.5 Table 6.2-1)"
    }

    public static func isValidUID(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count <= 64 && matches(text, "(?:0|[1-9][0-9]*)(?:\\.(?:0|[1-9][0-9]*))*")
    }

    public static func isValidDate(_ text: String) -> Bool {
        guard matches(text, "[0-9]{8}") else { return false }
        let digits = Array(text.utf8)
        return validDate(year: integer(digits, 0, 4), month: integer(digits, 4, 2), day: integer(digits, 6, 2))
    }

    public static func isValidTime(_ text: String) -> Bool {
        let value = removingTrailingSpaces(text)
        guard text.utf8.count <= 14,
              matches(value, "[0-9]{2}(?:[0-9]{2}(?:[0-9]{2}(?:\\.[0-9]{1,6})?)?)?") else { return false }
        let digits = Array(value.prefix { $0 != "." }.utf8)
        return integer(digits, 0, 2) <= 23
            && (digits.count < 4 || integer(digits, 2, 2) <= 59)
            && (digits.count < 6 || integer(digits, 4, 2) <= 60)
    }

    public static func isValidDateTime(_ text: String) -> Bool { parseDateTime(text) != nil }

    /// Strict compact DT grammar with legal partial precision, Gregorian dates,
    /// fractions only after seconds, and offsets from -1200 through +1400.
    public static func parseDateTime(_ text: String) -> DICOMDateTime? {
        var value = removingTrailingSpaces(text)
        guard text.utf8.count <= 26,
              matches(value, "[0-9]{4}(?:[0-9]{2}){0,5}(?:\\.[0-9]{1,6})?(?:[+-][0-9]{4})?") else { return nil }
        var offset: Int?
        if value.count >= 9 {
            let suffix = String(value.suffix(5))
            if suffix.first == "+" || suffix.first == "-" {
                let bytes = Array(suffix.utf8)
                let hours = integer(bytes, 1, 2), minutes = integer(bytes, 3, 2)
                let total = (hours * 60 + minutes) * (suffix.first == "-" ? -1 : 1)
                guard minutes <= 59, (-720...840).contains(total), suffix != "-0000" else { return nil }
                offset = total
                value.removeLast(5)
            }
        }
        let parts = value.components(separatedBy: ".")
        let digits = Array(parts[0].utf8)
        guard [4, 6, 8, 10, 12, 14].contains(digits.count), parts.count == 1 || digits.count == 14 else { return nil }
        let year = integer(digits, 0, 4)
        let month: Int? = digits.count >= 6 ? integer(digits, 4, 2) : nil
        let day: Int? = digits.count >= 8 ? integer(digits, 6, 2) : nil
        let hour: Int? = digits.count >= 10 ? integer(digits, 8, 2) : nil
        let minute: Int? = digits.count >= 12 ? integer(digits, 10, 2) : nil
        let second: Int? = digits.count >= 14 ? integer(digits, 12, 2) : nil
        guard validDate(year: year, month: month ?? 1, day: day ?? 1),
              hour == nil || hour! <= 23, minute == nil || minute! <= 59,
              second == nil || second! <= 60 else { return nil }
        let microsecond = parts.count == 2 ? Int(parts[1] + String(repeating: "0", count: 6 - parts[1].count)) : nil
        return DICOMDateTime(year: year, month: month, day: day, hour: hour, minute: minute,
                             second: second, microsecond: microsecond, timezoneOffsetMinutes: offset)
    }

    /// Fixed-width binary Values must occupy a whole number of their storage units.
    public static func binaryLengthProblem(of element: DataElement) -> String? {
        let width: Int
        switch element.vr {
        case .US, .SS, .OW: width = 2
        case .UL, .SL, .FL, .AT, .OF, .OL: width = 4
        case .FD, .SV, .UV, .OD, .OV: width = 8
        default: return nil
        }
        guard element.valueData.count % width != 0 else { return nil }
        return "VR \(element.vr.rawValue) Value Length \(element.valueData.count) is not a multiple of \(width) bytes (PS3.5 Table 6.2-1)"
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: "\\A(?:" + pattern + ")\\z", options: .regularExpression) != nil
    }

    private static func removingTrailingSpaces(_ text: String) -> String {
        String(text.reversed().drop(while: { $0 == " " }).reversed())
    }

    private static func integer(_ bytes: [UInt8], _ start: Int, _ length: Int) -> Int {
        bytes[start..<(start + length)].reduce(0) { $0 * 10 + Int($1 - 48) }
    }

    private static func validDate(year: Int, month: Int, day: Int) -> Bool {
        guard (1...9999).contains(year), (1...12).contains(month), day >= 1 else { return false }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return day <= days[month - 1]
    }
}
