// NEMA-verified: 2026a, checked 2026-10-01 — Options add Retain Safe Private (E.3.10, Table E.3.10-1 generated: ConfidentialityProfileSafePrivate.swift, 479 rows) and Clean Graphics (E.3.3, the Table E.1-1 Clean Graph. column), recorded as CID 7050 113111 / 113103 (D159)
// NEMA-verified: 2026a, checked 2026-10-01 — Options add Clean Structured Content (E.3.4, recorded as CID 7050 113104): the Table E.1-1 Clean Struct. Cont. column (4 rows: C) and every row of Table E.3.4-1 (211, generated: ConfidentialityProfileStructuredContent.swift, with the retired SRT / SNM3 / 99SDM codes of its 11 SCT rows from PS3.16 Table O-1) applied to Content Items by contentItemAction(for:options:) (D159); Clean Recognizable Visual Features (E.3.2, 113102) is recorded by PixelRedactor, which blanks the operator's regions
// NEMA-verified: 2026a, checked 2026-09-30 — the rule table is every single-tag row of PS3.15 2026a Table E.1-1 (651, generated: ConfidentialityProfileTableE11.swift); action(for:options:) applies the Basic Profile column and the Retain UIDs / Device / Institution / Patient Characteristics / Longitudinal Full and Modified Dates / Clean Descriptors columns (D69; was 79 hand-picked rows)
// NEMA-verified: 2026a, checked 2026-09-29 — the Basic Profile action of every row diffed by Scripts/diff_kit.py against PS3.15 2026a Table E.1-1 (62 rows; Device UID U and the order numbers Z corrected); DeidentificationMethodCode values and meanings from PS3.16 2026a CID 7050 (113100-113112), option mapping from PS3.15 E.3
import Foundation
import DICOMCore

/// PS3.15 Annex E — Attribute Confidentiality Profiles.
///
/// This models the *action codes* of Table E.1-1 and a curated table of the attributes
/// that carry direct identifiers. It is deliberately additive: the legacy
/// ``AnonymizationProfile`` (basic/clinicalTrial/research) is unchanged; this type is the
/// standards-grounded engine used by the new ``Anonymizer/deidentify(file:)`` path.
///
/// ## Coverage
///
/// Table E.1-1 lists ~530 attributes. This table encodes the **direct-identifier core** —
/// every attribute in Table E.1-1 whose Basic Profile action is D/Z/X and that carries a
/// name, identifier, contact detail, address, date/time, description, device identity or
/// UID likely to hold PHI — plus the method-recording attributes. Attributes whose only
/// action is a retention *option* (C/K/U under a named option) are handled by the option
/// toggles rather than enumerated. Coverage is stated honestly in the tests and docs; the
/// engine also applies **VR-based sweeps** (all PN removed unless retained; all
/// UI regenerated consistently; all private tags removed unless retained) so an attribute
/// absent from the explicit table is not silently kept.
public enum ConfidentialityProfile {

    /// PS3.15 Table E.1-1 action codes.
    public enum Action: Sendable, Equatable {
        /// **D** — replace with a non-zero-length dummy value of consistent VR.
        case replaceDummy
        /// **Z** — replace with a zero-length value, or a dummy of consistent VR.
        case zero
        /// **X** — remove the attribute.
        case remove
        /// **K** — keep (retain unchanged). Used when an option turns retention on.
        case keep
        /// **C** — clean: retain but scrub embedded identifiers (best-effort; the
        /// engine currently zeroes free-text descriptors it cannot clean safely).
        case clean
        /// **U** — replace UID with an internally-consistent generated UID.
        case replaceUID
        /// **Z/D** — Z unless a dummy is required by an IOD; the engine treats as Z.
        case zeroOrDummy
        /// **X/Z**, **X/D**, **X/Z/D** etc. — the engine takes the most aggressive
        /// safe action (remove) unless a retention option applies.
        case removePreferred
    }

    /// Named retention options from PS3.15 E.3 that relax specific actions.
    public struct Options: Sendable, Equatable {
        public var retainLongitudinalTemporal: Bool  // dates/times kept (else removed/shifted)
        public var retainPatientCharacteristics: Bool // age/sex/weight/size kept
        public var retainDeviceIdentity: Bool          // device serial/UID/station kept
        public var retainInstitutionIdentity: Bool     // institution name/address kept
        public var retainUIDs: Bool                    // UIDs kept unchanged (else regenerated)
        public var cleanDescriptors: Bool              // scrub free-text rather than remove
        public var dateOffsetDays: Int?                // if set with retainLongitudinalTemporal, shift instead of remove
        /// Retain Safe Private Option (PS3.15 2026a E.3.10): Private Attributes listed in
        /// Table E.3.10-1 for their Private Creator, or declared safe in Private Data Element
        /// Characteristics Sequence (0008,0300), are kept with their Private Creators (D159).
        public var retainSafePrivate: Bool
        /// Clean Graphics Option (PS3.15 2026a E.3.3): Graphic Annotation Sequence (0070,0001)
        /// is kept with the identifying information taken out of its text (D159).
        public var cleanGraphics: Bool
        /// Clean Structured Content Option (PS3.15 2026a E.3.4): Content Sequence (0040,A730),
        /// Acquisition Context Sequence (0040,0555), Specimen Preparation Sequence (0040,0610)
        /// and Waveform Annotation Sequence (0040,B020) are kept and cleaned (Table E.1-1 "C");
        /// each Content Item gets the action Table E.3.4-1 gives its Concept Name and Value Type
        /// (``contentItemAction(for:options:)``), and the text kept is cleaned (D159).
        public var cleanStructuredContent: Bool

        public init(
            retainLongitudinalTemporal: Bool = false,
            retainPatientCharacteristics: Bool = false,
            retainDeviceIdentity: Bool = false,
            retainInstitutionIdentity: Bool = false,
            retainUIDs: Bool = false,
            cleanDescriptors: Bool = false,
            dateOffsetDays: Int? = nil,
            retainSafePrivate: Bool = false,
            cleanGraphics: Bool = false,
            cleanStructuredContent: Bool = false
        ) {
            self.retainLongitudinalTemporal = retainLongitudinalTemporal
            self.retainPatientCharacteristics = retainPatientCharacteristics
            self.retainDeviceIdentity = retainDeviceIdentity
            self.retainInstitutionIdentity = retainInstitutionIdentity
            self.retainUIDs = retainUIDs
            self.cleanDescriptors = cleanDescriptors
            self.dateOffsetDays = dateOffsetDays
            self.retainSafePrivate = retainSafePrivate
            self.cleanGraphics = cleanGraphics
            self.cleanStructuredContent = cleanStructuredContent
        }

        /// The strict Basic Application Level Confidentiality Profile: every option off.
        public static let basic = Options()

        /// The PS3.16 CID 7050 codes that describe this profile and its options, in
        /// the order the items are written to De-identification Method Code Sequence
        /// (0012,0064): the profile code first, then one code per option applied.
        public var methodCodes: [DeidentificationMethodCode] {
            var codes: [DeidentificationMethodCode] = [.basicApplicationConfidentialityProfile]
            if cleanGraphics { codes.append(.cleanGraphicsOption) }
            if cleanStructuredContent { codes.append(.cleanStructuredContentOption) }
            if cleanDescriptors { codes.append(.cleanDescriptorsOption) }
            if retainLongitudinalTemporal {
                // E.3: "Retain Longitudinal Temporal Information with Full Dates" keeps
                // dates verbatim; "… with Modified Dates" shifts them, which is what a
                // date offset does.
                codes.append(dateOffsetDays == nil
                             ? .retainLongitudinalTemporalInformationFullDatesOption
                             : .retainLongitudinalTemporalInformationModifiedDatesOption)
            }
            if retainPatientCharacteristics { codes.append(.retainPatientCharacteristicsOption) }
            if retainDeviceIdentity { codes.append(.retainDeviceIdentityOption) }
            if retainUIDs { codes.append(.retainUIDsOption) }
            if retainSafePrivate { codes.append(.retainSafePrivateOption) }
            if retainInstitutionIdentity { codes.append(.retainInstitutionIdentityOption) }
            return codes
        }
    }

    /// PS3.16 2026a CID 7050 De-identification Method (DCM codes), the vocabulary of
    /// De-identification Method Code Sequence (0012,0064). The raw value is the Code
    /// Value; ``meaning`` is the Code Meaning exactly as printed in CID 7050.
    public enum DeidentificationMethodCode: String, CaseIterable, Sendable {
        case basicApplicationConfidentialityProfile = "113100"
        case cleanPixelDataOption = "113101"
        case cleanRecognizableVisualFeaturesOption = "113102"
        case cleanGraphicsOption = "113103"
        case cleanStructuredContentOption = "113104"
        case cleanDescriptorsOption = "113105"
        case retainLongitudinalTemporalInformationFullDatesOption = "113106"
        case retainLongitudinalTemporalInformationModifiedDatesOption = "113107"
        case retainPatientCharacteristicsOption = "113108"
        case retainDeviceIdentityOption = "113109"
        case retainUIDsOption = "113110"
        case retainSafePrivateOption = "113111"
        case retainInstitutionIdentityOption = "113112"

        /// Coding Scheme Designator (0008,0102) of every CID 7050 row.
        public static let codingSchemeDesignator = "DCM"

        /// Code Value (0008,0100).
        public var codeValue: String { rawValue }

        /// Code Meaning (0008,0104), verbatim from CID 7050.
        public var meaning: String {
            switch self {
            case .basicApplicationConfidentialityProfile: return "Basic Application Confidentiality Profile"
            case .cleanPixelDataOption: return "Clean Pixel Data Option"
            case .cleanRecognizableVisualFeaturesOption: return "Clean Recognizable Visual Features Option"
            case .cleanGraphicsOption: return "Clean Graphics Option"
            case .cleanStructuredContentOption: return "Clean Structured Content Option"
            case .cleanDescriptorsOption: return "Clean Descriptors Option"
            case .retainLongitudinalTemporalInformationFullDatesOption: return "Retain Longitudinal Temporal Information Full Dates Option"
            case .retainLongitudinalTemporalInformationModifiedDatesOption: return "Retain Longitudinal Temporal Information Modified Dates Option"
            case .retainPatientCharacteristicsOption: return "Retain Patient Characteristics Option"
            case .retainDeviceIdentityOption: return "Retain Device Identity Option"
            case .retainUIDsOption: return "Retain UIDs Option"
            case .retainSafePrivateOption: return "Retain Safe Private Option"
            case .retainInstitutionIdentityOption: return "Retain Institution Identity Option"
            }
        }

        /// A Code Sequence Item (PS3.3 Table 8.8-1: Code Value SH, Coding Scheme
        /// Designator SH, Code Meaning LO) for De-identification Method Code Sequence.
        public var sequenceItem: SequenceItem {
            SequenceItem(elements: [
                DataElement.string(tag: .codeValue, vr: .SH, value: codeValue),
                DataElement.string(tag: .codingSchemeDesignator, vr: .SH, value: Self.codingSchemeDesignator),
                DataElement.string(tag: .codeMeaning, vr: .LO, value: meaning),
            ])
        }
    }

    /// A single row of the confidentiality table: which option (if any) can relax it.
    public struct Rule: Sendable {
        public let action: Action
        /// If non-nil, this action is relaxed to `.keep` when the named option is on.
        public let relaxedBy: RelaxKey?
        public init(_ action: Action, relaxedBy: RelaxKey? = nil) {
            self.action = action
            self.relaxedBy = relaxedBy
        }
    }

    public enum RelaxKey: Sendable {
        case longitudinalTemporal
        case patientCharacteristics
        case deviceIdentity
        case institutionIdentity
        case uids
    }

    /// Every single-tag row of PS3.15 Table E.1-1 as a rule: the Basic Profile action and
    /// the first retention option that relaxes it (for display; ``action(for:options:)``
    /// applies every option column of the row).
    ///
    /// Generated from the DocBook (`ConfidentialityProfileTableE11.swift`,
    /// `Scripts/generate_confidentiality_profile.py`). Before D69 this table held 79
    /// hand-picked rows and every other attribute of Table E.1-1 that was not a person
    /// name, UID or private attribute was kept.
    public static let table: [Tag: Rule] = {
        var t: [Tag: Rule] = [:]
        for (key, row) in tableE11 {
            let tag = Tag(group: UInt16(key >> 16), element: UInt16(key & 0xFFFF))
            let relax: RelaxKey?
            if row.uids == "K" { relax = .uids }
            else if row.device != nil { relax = .deviceIdentity }
            else if row.institution != nil { relax = .institutionIdentity }
            else if row.patient != nil { relax = .patientCharacteristics }
            else if row.fullDates != nil || row.modifiedDates != nil { relax = .longitudinalTemporal }
            else { relax = nil }
            t[tag] = Rule(basicAction(row.basic), relaxedBy: relax)
        }
        return t
    }()

    /// The engine action for a Basic Profile code of Table E.1-1. A choice of codes takes
    /// the most protective one the engine can always satisfy: remove where X is offered,
    /// Z/D as zero-length (a dummy only where the IOD needs one, which the engine cannot
    /// know).
    static func basicAction(_ code: String) -> Action {
        switch code {
        case "X": return .remove
        case "Z": return .zero
        case "D": return .replaceDummy
        case "U": return .replaceUID
        case "K": return .keep
        case "C": return .clean
        case "Z/D": return .zeroOrDummy
        default: return .removePreferred   // X/Z, X/D, X/Z/D, X/Z/U*
        }
    }

    /// Resolves the effective action for a tag under the given options: the row's option
    /// columns for every option in force (Retain UIDs, Device Identity, Institution
    /// Identity, Patient Characteristics, Longitudinal Temporal Information with Full or
    /// Modified Dates, Clean Descriptors, Clean Graphics, Clean Structured Content), else its
    /// Basic Profile action.
    /// Returns nil when the tag is not a row of Table E.1-1 (the engine's group, private,
    /// PN and UI rules handle those).
    ///
    /// NEMA-verified: 2026a, checked 2026-09-30 — the option columns of PS3.15 2026a Table
    /// E.1-1 ("K" keep, "C" clean; Modified Dates "C" shifts dates) and E.3 (D69).
    public static func action(for tag: Tag, options: Options) -> Action? {
        guard let row = tableE11[UInt32(tag.group) << 16 | UInt32(tag.element)] else { return nil }
        func substitute(_ code: String) -> Action { code == "K" ? .keep : .clean }
        if options.retainUIDs, row.uids == "K" { return .keep }
        if options.retainDeviceIdentity, let code = row.device { return substitute(code) }
        if options.retainInstitutionIdentity, let code = row.institution { return substitute(code) }
        if options.retainPatientCharacteristics, let code = row.patient { return substitute(code) }
        if options.retainLongitudinalTemporal {
            // "… with Modified Dates": dates are shifted (the engine's date path);
            // "… with Full Dates": kept verbatim.
            if options.dateOffsetDays != nil, row.modifiedDates != nil { return .zeroOrDummy }
            if options.dateOffsetDays == nil, row.fullDates == "K" { return .keep }
        }
        if options.cleanDescriptors, row.cleanDescriptors == "C" { return .clean }
        if options.cleanGraphics, row.cleanGraphics == "C" { return .clean }
        if options.cleanStructuredContent, row.cleanStructuredContent == "C" { return .clean }
        return basicAction(row.basic)
    }

    // MARK: - Clean Structured Content Option (PS3.15 2026a E.3.4, Table E.3.4-1)

    /// The Table E.3.4-1 row for a Content Item, by the Coding Scheme Designator and Code
    /// Value of its Concept Name and its Value Type: the generated rows, which include the
    /// retired SRT / SNM3 / 99SDM codes of the SCT rows (E.3.4: retired codes are to be
    /// recognised). A concept listed only under other Value Types gives the most protective
    /// Basic Profile action of its rows ("X" where one has it, else "D"), with no option
    /// substitution, since the option columns are stated for the listed Value Types only.
    static func structuredContentRow(designator: String, codeValue: String, valueType: String) -> E341Row? {
        if let row = structuredContentRows["\(designator)|\(codeValue)|\(valueType)"] { return row }
        let prefix = "\(designator)|\(codeValue)|"
        let rows = structuredContentRows.filter { $0.key.hasPrefix(prefix) }.map(\.value)
        guard let first = rows.first else { return nil }
        return E341Row(meaning: first.meaning,
                       basic: rows.contains { $0.basic.contains("X") } ? "X" : "D")
    }

    /// The action PS3.15 2026a Table E.3.4-1 gives a Content Item under the Clean Structured
    /// Content Option: the option columns for every option in force (Retain UIDs, Device
    /// Identity, Institution Identity, Patient Characteristics, Longitudinal Temporal
    /// Information with Full or Modified Dates, Clean Descriptors), else its Basic Profile
    /// action, in the order ``action(for:options:)`` applies the Table E.1-1 columns. Nil
    /// when its Concept Name Code Sequence (0040,A043) names no row (the Item is kept, with
    /// its attributes processed by Table E.1-1 and its text cleaned).
    ///
    /// The Item is matched by Coding Scheme Designator (0008,0102) and Code Value (0008,0100),
    /// Long Code Value (0008,0119) or URN Code Value (0008,0120), and Value Type (0040,A040).
    static func contentItemAction(for item: SequenceItem, options: Options) -> Action? {
        guard let concept = DataSet(elements: item.allElements).sequence(for: .conceptNameCodeSequence)?.first
        else { return nil }
        func value(_ tag: Tag) -> String? {
            concept.string(for: tag)?.trimmingCharacters(in: CharacterSet(charactersIn: " \u{0}"))
        }
        guard let designator = value(.codingSchemeDesignator),
              let code = value(.codeValue) ?? value(.longCodeValue) ?? value(.urnCodeValue),
              let row = structuredContentRow(
                designator: designator, codeValue: code,
                valueType: item.string(for: .valueType)?.trimmingCharacters(in: .whitespaces).uppercased() ?? "")
        else { return nil }
        func substitute(_ code: String) -> Action { code == "K" ? .keep : .clean }
        if options.retainUIDs, row.uids == "K" { return .keep }
        if options.retainDeviceIdentity, let code = row.device { return substitute(code) }
        if options.retainInstitutionIdentity, let code = row.institution { return substitute(code) }
        if options.retainPatientCharacteristics, let code = row.patient { return substitute(code) }
        if options.retainLongitudinalTemporal {
            if options.dateOffsetDays != nil, let code = row.modifiedDates { return substitute(code) }
            if options.dateOffsetDays == nil, let code = row.fullDates { return substitute(code) }
        }
        if options.cleanDescriptors, let code = row.cleanDescriptors { return substitute(code) }
        return basicAction(row.basic)
    }

    static func isRelaxed(_ key: RelaxKey, _ o: Options) -> Bool {
        switch key {
        case .longitudinalTemporal: return o.retainLongitudinalTemporal
        case .patientCharacteristics: return o.retainPatientCharacteristics
        case .deviceIdentity: return o.retainDeviceIdentity
        case .institutionIdentity: return o.retainInstitutionIdentity
        case .uids: return o.retainUIDs
        }
    }
}
