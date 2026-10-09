// NEMA-verified: 2026a, checked 2026-10-01 — (moved from dicom-tags into DICOMKit, D150) Value length / character-repertoire limits of the 34 VRs dumped from PS3.5 2026a Table 6.2-1 (17 character VRs checked, 6 binary numeric VRs encoded, 11 VRs refused for --set); group 0002 placement per PS3.10 2026a 7.1; Item/delimiters (FFFE,E000/E00D/E0DD) per PS3.5 7.5; unused groups 0001/0003/0005/0007/FFFF and Private Creator (gggg,0010-00FF) per PS3.5 7.8.1
import Foundation
import DICOMCore
import DICOMDictionary

/// A tag edit the standard does not allow. ``TagEditor/applyCheckedChanges(to:sets:deletes:deletePrivate:sourceDataSet:copyTags:verbose:dryRun:)``
/// throws it before anything is changed, so a Data Set is never left half-edited
/// (`dicom-tags` exits 1).
public struct TagEditRefusal: Error, LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// The rules ``TagEditor`` applies to an edit: which tags a Data Set may hold, the VR a
/// set writes, and the PS3.5 Table 6.2-1 limits its value must respect.
///
/// Moved from the `dicom-tags` CLI (commit b091aa5) into DICOMKit so DICOMStudio's
/// Workshop, which runs the same engine, applies them too (D150).
public enum TagEditRules {

    // MARK: - Which tags a Data Set edit may touch

    /// Why `tag` may not be set, deleted or copied in the Data Set, or nil when it may.
    public static func dataSetRefusal(for tag: Tag) -> String? {
        switch tag.group {
        case 0x0002:
            // PS3.10 2026a 7.1: "Data Elements with a group of 0002 shall not be used in Data
            // Sets other than within the File Meta Information."
            return "\(tag.description) is a File Meta Information element (group 0002); PS3.10 7.1 does not allow group 0002 in the Data Set. The file writer sets the File Meta Information."
        case 0xFFFE:
            // PS3.5 2026a 7.5: Item (FFFE,E000), Item Delimitation Item (FFFE,E00D) and
            // Sequence Delimitation Item (FFFE,E0DD) encode sequences; they are not Attributes.
            return "\(tag.description) is a sequence Item or delimiter (PS3.5 7.5), not an Attribute that can be edited."
        case 0x0001, 0x0003, 0x0005, 0x0007, 0xFFFF:
            // PS3.5 2026a 7.8.1: "Elements with Tags (0001,xxxx), (0003,xxxx), (0005,xxxx),
            // (0007,xxxx) and (FFFF,xxxx) shall not be used."
            return "\(tag.description) is in a group PS3.5 7.8.1 says shall not be used."
        default:
            return nil
        }
    }

    /// Private Creator Data Elements (gggg,0010-00FF), gggg odd (PS3.5 7.8.1).
    public static func isPrivateCreator(_ tag: Tag) -> Bool {
        AttributeNames.isPrivateCreator(tag)
    }

    // MARK: - VR of a written element

    /// The VR `--set` writes: the PS3.6 dictionary VR (the existing element's VR when it is
    /// one of the dictionary's alternatives, e.g. "US or SS"); LO for a Private Creator
    /// (PS3.5 7.8.1); for other private or unknown tags the existing VR, else LO.
    public static func writeVR(for tag: Tag, existing: VR?) -> VR {
        if isPrivateCreator(tag) { return .LO }
        let dictionary = (DataElementDictionary.lookup(tag: tag)?.vr ?? []).filter { $0 != .UN }
        if !dictionary.isEmpty {
            if let existing, dictionary.contains(existing) { return existing }
            return dictionary[0]
        }
        if let existing, existing != .UN { return existing }
        return .LO
    }

    // MARK: - PS3.5 Table 6.2-1 limits

    /// How Table 6.2-1 counts a Value's length.
    public enum LengthUnit: Equatable, Sendable { case bytes, chars }

    /// "Length of Value" column of PS3.5 2026a Table 6.2-1 for the character VRs that have a
    /// limit below 2^32-2 (UC, UR and UT allow 2^32-2 bytes and are not checked).
    /// `fixed` = "bytes fixed"; PN's limit is per component group.
    public static let lengthLimits: [VR: (max: Int, unit: LengthUnit, fixed: Bool)] = [
        .AE: (16, .bytes, false),
        .AS: (4, .bytes, true),
        .CS: (16, .bytes, false),
        .DA: (8, .bytes, true),
        .DS: (16, .bytes, false),
        .DT: (26, .bytes, false),
        .IS: (12, .bytes, false),
        .LO: (64, .chars, false),
        .LT: (10240, .chars, false),
        .PN: (64, .chars, false),
        .SH: (16, .chars, false),
        .ST: (1024, .chars, false),
        .TM: (14, .bytes, false),
        .UI: (64, .bytes, false),
    ]

    /// "Character Repertoire" column of Table 6.2-1 for the VRs limited to a subset of the
    /// Default Character Repertoire (stored values, not query keys).
    public static let repertoires: [VR: Set<Character>] = {
        let digits = Set("0123456789")
        return [
            .AS: digits.union("DWMY"),
            .CS: digits.union("ABCDEFGHIJKLMNOPQRSTUVWXYZ _"),
            .DA: digits,
            .DS: digits.union("+-Ee. "),
            .DT: digits.union("+-. "),
            .IS: digits.union("+- "),
            .TM: digits.union(". "),
            .UI: digits.union("."),
        ]
    }()

    /// VRs whose Values are separated by BACKSLASH; LT, ST, UT and UR "shall not be
    /// multi-valued" (Table 6.2-1), so a backslash is part of their one Value.
    public static let singleValuedTextVRs: Set<VR> = [.LT, .ST, .UT, .UR]

    /// Binary VRs `--set` encodes from decimal text (Table 6.2-1 ranges).
    public static let numericVRs: Set<VR> = [.US, .SS, .UL, .SL, .FL, .FD]

    /// Splits a `--set` value into its Values.
    public static func values(of text: String, vr: VR) -> [String] {
        singleValuedTextVRs.contains(vr)
            ? [text]
            : text.split(separator: "\\", omittingEmptySubsequences: false).map(String.init)
    }

    /// Why `text` cannot be written with `vr`, or nil when it can.
    public static func valueProblem(_ text: String, vr: VR) -> String? {
        if numericVRs.contains(vr) {
            return numericValues(text, vr: vr).problem
        }
        switch vr {
        case .AT, .OB, .OD, .OF, .OL, .OV, .OW, .SQ, .SV, .UN, .UV:
            return "--set writes character and numeric values; VR \(vr.rawValue) cannot be set from text"
        default:
            break
        }
        for value in values(of: text, vr: vr) {
            if let problem = stringValueProblem(value, vr: vr) { return problem }
        }
        return nil
    }

    private static func stringValueProblem(_ value: String, vr: VR) -> String? {
        if value.isEmpty { return nil }  // a zero-length Value is always encodable
        if let allowed = repertoires[vr], let bad = value.first(where: { !allowed.contains($0) }) {
            return "\"\(value)\": character \"\(bad)\" is not allowed in VR \(vr.rawValue) (PS3.5 Table 6.2-1)"
        }
        let controlAllowed: Set<Character> = singleValuedTextVRs.contains(vr)
            ? ["\t", "\n", "\r", "\u{0C}", "\u{1B}", "\r\n"] : ["\u{1B}"]
        if let bad = value.unicodeScalars.first(where: { $0.value < 0x20 || $0.value == 0x7F }),
           !controlAllowed.contains(Character(bad)) {
            return "\"\(value)\": control character U+\(String(format: "%04X", bad.value)) is not allowed in VR \(vr.rawValue) (PS3.5 Table 6.2-1)"
        }
        if vr == .AE, value.allSatisfy({ $0 == " " }) {
            return "an AE Value consisting solely of spaces shall not be used (PS3.5 Table 6.2-1)"
        }
        if vr == .IS, let n = Int(value.trimmingCharacters(in: .whitespaces)),
           n < Int(Int32.min) || n > Int(Int32.max) {
            return "\"\(value)\": IS must be in the range -2^31 to 2^31-1 (PS3.5 Table 6.2-1)"
        }
        guard let limit = lengthLimits[vr] else { return nil }
        let parts = vr == .PN ? value.split(separator: "=", omittingEmptySubsequences: false).map(String.init) : [value]
        if vr == .PN, parts.count > 3 {
            return "\"\(value)\": PN has at most 3 component groups (PS3.5 6.2.1)"
        }
        for part in parts {
            if vr == .PN, part.split(separator: "^", omittingEmptySubsequences: false).count > 5 {
                return "\"\(part)\": a PN component group has at most 5 components (PS3.5 Table 6.2-1, 6.2.1)"
            }
            let length = limit.unit == .bytes ? part.utf8.count : part.count
            if limit.fixed ? length != limit.max : length > limit.max {
                let rule = limit.fixed ? "exactly \(limit.max)" : "at most \(limit.max)"
                let unit = limit.unit == .bytes ? "bytes" : "characters"
                let scope = vr == .PN ? " per component group" : ""
                return "\"\(part)\" is \(length) \(unit); VR \(vr.rawValue) allows \(rule) \(unit)\(scope) (PS3.5 Table 6.2-1)"
            }
        }
        return nil
    }

    /// Parses decimal text for a binary numeric VR, checking the Table 6.2-1 range.
    public static func numericValues(_ text: String, vr: VR) -> (doubles: [Double], problem: String?) {
        var out: [Double] = []
        for raw in values(of: text, vr: vr) {
            let value = raw.trimmingCharacters(in: .whitespaces)
            switch vr {
            case .FL, .FD:
                guard let d = Double(value), vr == .FD || Float(value) != nil else {
                    return ([], "\"\(raw)\" is not a number for VR \(vr.rawValue)")
                }
                out.append(d)
            default:
                guard let n = Int(value) else {
                    return ([], "\"\(raw)\" is not an integer for VR \(vr.rawValue)")
                }
                let range: ClosedRange<Int>
                switch vr {
                case .US: range = 0...Int(UInt16.max)
                case .SS: range = Int(Int16.min)...Int(Int16.max)
                case .UL: range = 0...Int(UInt32.max)
                default: range = Int(Int32.min)...Int(Int32.max)  // SL
                }
                guard range.contains(n) else {
                    return ([], "\(n) is out of range for VR \(vr.rawValue) (\(range.lowerBound)...\(range.upperBound), PS3.5 Table 6.2-1)")
                }
                out.append(Double(n))
            }
        }
        return (out, nil)
    }

    /// The element `--set` writes, or the reason it cannot.
    public static func element(tag: Tag, vr: VR, text: String) -> Result<DataElement, TagEditRefusal> {
        if let problem = valueProblem(text, vr: vr) {
            return .failure(TagEditRefusal("--set \(tag.description): \(problem)"))
        }
        if numericVRs.contains(vr) {
            let numbers = numericValues(text, vr: vr).doubles
            switch vr {
            case .US: return .success(.uint16s(tag: tag, values: numbers.map { UInt16($0) }))
            case .SS: return .success(.int16s(tag: tag, values: numbers.map { Int16($0) }))
            case .UL: return .success(.uint32s(tag: tag, values: numbers.map { UInt32($0) }))
            case .SL: return .success(.int32s(tag: tag, values: numbers.map { Int32($0) }))
            case .FL: return .success(.float32s(tag: tag, values: numbers.map { Float32($0) }))
            default: return .success(.float64s(tag: tag, values: numbers))
            }
        }
        if isPrivateCreator(tag),
           text.contains("\\") || text.unicodeScalars.contains(where: { $0.value > 0x7E }) {
            // PS3.5 7.8.1: a Private Creator is LO with VM 1, in the Default Character Repertoire.
            return .failure(TagEditRefusal("--set \(tag.description): a Private Creator value has VM 1 and only Default Character Repertoire characters (PS3.5 7.8.1)"))
        }
        return .success(.string(tag: tag, vr: vr, value: text))
    }

    /// `(GGGG,EEEE) Name`, or the bare tag for a tag with no name — the label every
    /// change line prints. A Private Creator Data Element is named "Private Creator"
    /// (PS3.5 7.8.1, D146).
    public static func label(for tag: Tag) -> String {
        if let name = AttributeNames.name(for: tag) {
            return "\(tag.description) \(name)"
        }
        return tag.description
    }
}
