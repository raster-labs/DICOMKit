// NEMA-verified: 2026a, checked 2026-10-01 — the DICOM side of the HL7 v2 / FHIR mappings: PN five components and the "=" component groups of PS3.5 2026a Table 6.2-1 / 6.2.1, DA (YYYYMMDD) and TM (HHMMSS.FFFFFF) of Table 6.2-1, SH 16 / LO 64 characters, Patient's Sex Enumerated Values M, F, O of PS3.3 2026a Table C.7-1, UID syntax of PS3.5 9.1 (DICOMCore.DICOMUniqueIdentifier) and the "&ZZXX" Timezone Offset From UTC of PS3.3 C.12.1.1.8. HL7 v2 (XPN, CX, EI, DTM, table 0001) and FHIR (HumanName, date, dateTime, AdministrativeGender) are not NEMA standards and are treated as plumbing
import Foundation
import DICOMCore

/// DICOM-side value rules shared by the HL7 v2 and FHIR converters.
///
/// Only the DICOM half of each mapping is normative here (PS3.3 / PS3.5 2026a). The HL7 v2
/// and FHIR halves follow those specifications as commonly used and are not checked against
/// any NEMA text.
enum DICOMValueMapping {

    // MARK: - Person Name (PS3.5 Table 6.2-1 PN, 6.2.1)

    /// The five PN components in DICOM order.
    struct PersonName: Equatable {
        var family = ""
        var given = ""
        var middle = ""
        var prefix = ""
        var suffix = ""

        /// PN value: `family^given^middle^prefix^suffix`, trailing empty components dropped
        /// (PS3.5 6.2.1.1 example omits the delimiters of trailing null components; interior
        /// delimiters are kept). Characters that PN reserves (`^`, `=`, `\`) are removed from
        /// a component.
        var dicomValue: String {
            let parts = [family, given, middle, prefix, suffix].map(DICOMValueMapping.cleanComponent)
            return DICOMValueMapping.joinTrimmingTrailingEmpty(parts, separator: "^")
        }
    }

    /// Parses a DICOM PN value. Only the first (single-byte, alphabetic) component group is
    /// used; the ideographic and phonetic groups after "=" are not mapped.
    static func personName(fromDICOM value: String) -> PersonName {
        let group = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? ""
        let c = group.trimmingCharacters(in: .whitespaces)
            .split(separator: "^", omittingEmptySubsequences: false).map(String.init)
        func at(_ i: Int) -> String { i < c.count ? c[i] : "" }
        return PersonName(family: at(0), given: at(1), middle: at(2), prefix: at(3), suffix: at(4))
    }

    /// HL7 v2 XPN (family^given^second and further given names^suffix^prefix^degree^…) to a
    /// DICOM PN value. Suffix and prefix swap places: DICOM orders prefix before suffix. Only
    /// the first repetition (`~`) is used, and the family-name subcomponents (`&`) are joined
    /// with a space.
    static func personName(fromHL7XPN xpn: String) -> String {
        let first = xpn.split(separator: "~", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? ""
        let c = first.split(separator: "^", omittingEmptySubsequences: false).map(String.init)
        func at(_ i: Int) -> String { i < c.count ? c[i] : "" }
        let family = at(0).split(separator: "&").map(String.init).filter { !$0.isEmpty }.joined(separator: " ")
        return PersonName(family: family, given: at(1), middle: at(2), prefix: at(4), suffix: at(3)).dicomValue
    }

    /// DICOM PN value to an HL7 v2 XPN (family^given^middle^suffix^prefix).
    static func hl7XPN(fromDICOM value: String) -> String {
        let pn = personName(fromDICOM: value)
        return joinTrimmingTrailingEmpty([pn.family, pn.given, pn.middle, pn.suffix, pn.prefix], separator: "^")
    }

    /// FHIR HumanName to a DICOM PN value: the first given name is the given-name component,
    /// further given names form the middle-name component.
    static func personName(fhirFamily family: String, given: [String], prefix: [String] = [], suffix: [String] = []) -> String {
        PersonName(
            family: family,
            given: given.first ?? "",
            middle: given.dropFirst().joined(separator: " "),
            prefix: prefix.joined(separator: " "),
            suffix: suffix.joined(separator: " ")
        ).dicomValue
    }

    // MARK: - DA / TM (PS3.5 Table 6.2-1)

    /// DA value from an HL7 v2 DTM/TS (`YYYY[MM[DD[HH…]]]`): the date only when the full
    /// YYYYMMDD is present, because DA has no reduced-precision form; nil otherwise.
    static func date(fromHL7 ts: String) -> String? {
        let digits = ts.trimmingCharacters(in: .whitespaces)
        guard digits.count >= 8 else { return nil }
        return validDA(String(digits.prefix(8)))
    }

    /// TM value from an HL7 v2 DTM/TS: HH, HHMM or HHMMSS after the date, plus up to six
    /// fraction digits; the "+/-ZZZZ" offset is not part of TM and is dropped. Nil when no
    /// hour is present.
    static func time(fromHL7 ts: String) -> String? {
        let s = ts.trimmingCharacters(in: .whitespaces)
        guard s.count > 8 else { return nil }
        var rest = String(s.dropFirst(8))
        if let tz = rest.firstIndex(where: { $0 == "+" || $0 == "-" }) { rest = String(rest[..<tz]) }
        return validTM(rest)
    }

    /// DA value from a FHIR `date` / `dateTime` (`YYYY-MM-DD[Thh:mm:ss…]`); nil for a partial
    /// date (`YYYY`, `YYYY-MM`).
    static func date(fromFHIR value: String) -> String? {
        let datePart = value.split(separator: "T", maxSplits: 1).first.map(String.init) ?? ""
        let fields = datePart.split(separator: "-", omittingEmptySubsequences: false)
        guard fields.count == 3 else { return nil }
        return validDA(fields.joined())
    }

    /// TM value from a FHIR `dateTime` (`…Thh:mm:ss[.sss][Z|±hh:mm]`); the zone is dropped.
    static func time(fromFHIR value: String) -> String? {
        let parts = value.split(separator: "T", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        var t = String(parts[1])
        if let z = t.firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) { t = String(t[..<z]) }
        return validTM(t.replacingOccurrences(of: ":", with: ""))
    }

    private static func validDA(_ s: String) -> String? {
        guard s.count == 8, s.allSatisfy({ $0.isASCII && $0.isNumber }),
              let month = Int(s.dropFirst(4).prefix(2)), (1...12).contains(month),
              let day = Int(s.suffix(2)), (1...31).contains(day) else { return nil }
        return s
    }

    private static func validTM(_ s: String) -> String? {
        let pieces = s.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let hms = String(pieces.first ?? "")
        guard [2, 4, 6].contains(hms.count), hms.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        let n = hms.map { Int(String($0))! }
        guard n[0] * 10 + n[1] <= 23 else { return nil }
        if hms.count >= 4, n[2] * 10 + n[3] > 59 { return nil }
        if hms.count == 6, n[4] * 10 + n[5] > 60 { return nil }
        guard hms.count == 6, pieces.count == 2 else { return hms }
        let fraction = String(pieces[1].prefix(6))
        guard !fraction.isEmpty, fraction.allSatisfy({ $0.isASCII && $0.isNumber }) else { return hms }
        return hms + "." + fraction
    }

    // MARK: - Patient's Sex (PS3.3 Table C.7-1: Enumerated Values M, F, O)

    /// HL7 v2 table 0001 to Patient's Sex. U (unknown) and an empty value give the empty
    /// value Patient's Sex allows as a Type 2 Attribute; any other code (A, N, …) is O.
    static func patientSex(fromHL7 code: String) -> String {
        switch code.trimmingCharacters(in: .whitespaces).uppercased() {
        case "M": return "M"
        case "F": return "F"
        case "O": return "O"
        case "U", "": return ""
        default: return "O"
        }
    }

    /// FHIR AdministrativeGender to Patient's Sex; `unknown` gives the empty value.
    static func patientSex(fromFHIR gender: String) -> String {
        switch gender.lowercased() {
        case "male": return "M"
        case "female": return "F"
        case "other": return "O"
        default: return ""
        }
    }

    // MARK: - Identifiers

    /// Maximum length in characters of a SH value (PS3.5 Table 6.2-1), e.g. Accession Number.
    static let shortStringMaxLength = 16
    /// Maximum length in characters of a LO value (PS3.5 Table 6.2-1), e.g. Patient ID.
    static let longStringMaxLength = 64

    /// HL7 v2 CX (ID^check digit^scheme^assigning authority^…, repeating with `~`) to the
    /// Patient ID (0010,0020) value and the Issuer of Patient ID (0010,0021) value (the
    /// assigning authority's namespace ID), from the first repetition.
    static func patientID(fromHL7CX cx: String) -> (id: String, issuer: String?) {
        let first = cx.split(separator: "~", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? ""
        let c = first.split(separator: "^", omittingEmptySubsequences: false).map(String.init)
        let issuer = c.count > 3 ? c[3].split(separator: "&", omittingEmptySubsequences: false).first.map(String.init) : nil
        return (c.first ?? "", (issuer?.isEmpty ?? true) ? nil : issuer)
    }

    /// The entity identifier (first component) of an HL7 v2 EI field such as ORC-2 / OBR-3.
    static func entityIdentifier(fromHL7EI ei: String) -> String {
        ei.split(separator: "^", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
    }

    /// True when the value is a UID per PS3.5 9.1 (digits and dots, no leading zeros, ≤ 64).
    static func isValidUID(_ value: String) -> Bool {
        guard !value.isEmpty, value == value.trimmingCharacters(in: .whitespaces) else { return false }
        return DICOMUniqueIdentifier.parse(value) != nil
    }

    // MARK: - Timezone Offset From UTC (PS3.3 C.12.1.1.8: "&ZZXX")

    /// "&ZZXX" for an offset in seconds east of UTC; UTC is "+0000" ("-0000" is not used).
    static func timezoneOffsetFromUTC(secondsFromGMT: Int) -> String {
        let sign = secondsFromGMT < 0 ? "-" : "+"
        let minutes = abs(secondsFromGMT) / 60
        return String(format: "%@%02d%02d", sign, minutes / 60, minutes % 60)
    }

    // MARK: - Helpers

    fileprivate static func cleanComponent(_ s: String) -> String {
        s.filter { $0 != "^" && $0 != "=" && $0 != "\\" }.trimmingCharacters(in: .whitespaces)
    }

    fileprivate static func joinTrimmingTrailingEmpty(_ parts: [String], separator: String) -> String {
        var p = parts
        while let last = p.last, last.isEmpty { p.removeLast() }
        return p.joined(separator: separator)
    }
}
