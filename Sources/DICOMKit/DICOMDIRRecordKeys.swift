// NEMA-verified: 2026a, checked 2026-10-01 — Directory Record Type per SOP Class and the Type 1 / 1C / 2 / 2C keys of every record type from PS3.3 2026a Annex F (Tables F.4-1, F.5-1 to F.5-49) and PS3.4 2026a Tables B.5-1 / GG.3-1, generated (DICOMDIRRecordKeyTables.swift); keys an FSC must supply per PS3.11 2026a D.3.3.1 (Study ID, Series Number, Instance Number assigned when the instance has none) (D229, D230)
import Foundation
import DICOMCore
import DICOMDictionary

/// The Directory Record a File-set Creator writes for an instance, and its keys.
///
/// PS3.3 2026a F.5: each Directory Record Type "shall be used to reference" the SOP Instances of
/// its IODs (an SR Document by SR DOCUMENT, a Presentation State by PRESENTATION, an RT Dose by
/// RT DOSE, …; IMAGE only for Image SOP Instances), and lists its keys with a Type. Type 1 keys
/// shall have a value, Type 2 keys shall be present (zero length when unknown). PS3.11 D.3.3.1
/// notes that an FSC supplies Type 1 keys the instance lacks.
public enum DICOMDIRRecordKeys {

    /// One key of a Directory Record (PS3.3 Tables F.5-1 to F.5-49).
    public struct Key: Sendable, Hashable {
        public let tag: Tag
        /// The Key column, e.g. "Study ID".
        public let name: String
        /// "1", "1C", "2" or "2C".
        public let type: String
    }

    /// The Directory Record Type for an instance of `sopClassUID`: from PS3.3 2026a F.5 and the
    /// IOD of PS3.4 Table B.5-1 / GG.3-1. nil for a SOP Class PS3.3 gives no record type (see
    /// ``hasNoDirectoryRecordType(sopClassUID:)``) or that is not a Media Storage SOP Class.
    public static func recordType(forSOPClassUID sopClassUID: String) -> DirectoryRecordType? {
        recordTypeBySOPClass[sopClassUID].flatMap(DirectoryRecordType.init(rawValue:))
    }

    /// Whether `sopClassUID` is a SOP Class of PS3.4 Table B.5-1 / GG.3-1 for which PS3.3 2026a
    /// defines no Directory Record Type (Performed / Defined Procedure Protocol, Protocol Approval).
    public static func hasNoDirectoryRecordType(sopClassUID: String) -> Bool {
        sopClassesWithoutRecordType[sopClassUID] != nil
    }

    /// The Type 1 / 1C / 2 / 2C keys of `recordType`, in table order (Specific Character Set left
    /// out), and the PS3.3 table they come from.
    public static func keys(for recordType: DirectoryRecordType) -> (table: String, keys: [Key])? {
        keyTable[recordType.rawValue]
    }

    // MARK: - Building a record's keys

    /// A Type 1 key the instance cannot supply.
    struct MissingKey: Error {
        let recordType: DirectoryRecordType
        let key: Key
        let table: String
    }

    /// Values the File-set Creator assigns when the instance has no value for these Type 1
    /// keys (PS3.11 2026a D.3.3.1: "either these attributes are present in the Image IOD, or
    /// they are in some other way supplied by the File-set Creator").
    struct Assigned {
        var studyID: String?
        var seriesNumber: String?
        var instanceNumber: String?
        /// Modality (0008,0060) for an instance without one (Type 1 in every IOD).
        var modality: String?
        /// Last resort for Study Date / Study Time when the instance has no date / time at all.
        var studyDate: String?
        var studyTime: String?
    }

    /// The key elements of a `recordType` record for the instance `dataSet`.
    ///
    /// Type 1: the instance's value, else the assigned identifier (Study ID, Series Number,
    /// Instance Number), else Study Date / Study Time from Series, Acquisition or Content
    /// Date / Time, else the last-resort Study Date / Time of `assigned`, else ``MissingKey``. Type 2: the instance's element, else zero length.
    /// Type 1C / 2C: the instance's element when present (Content Sequence: its HAS CONCEPT
    /// MOD Items only, PS3.3 Tables F.5-25 / F.5-26; Verification DateTime: the most recent
    /// one of the Verifying Observer Sequence when VERIFIED). Specific Character Set (1C) is
    /// copied when the instance has one.
    static func keyElements(for recordType: DirectoryRecordType, from dataSet: DataSet,
                            assigned: Assigned) throws -> [Tag: DataElement] {
        var out: [Tag: DataElement] = [:]
        if let charset = dataSet[.specificCharacterSet], !(charset.stringValue ?? "").isEmpty {
            out[.specificCharacterSet] = charset
        }
        guard let (table, keys) = keys(for: recordType) else { return out }
        for key in keys {
            switch key.type {
            case "1":
                if let element = present(key.tag, in: dataSet) {
                    out[key.tag] = element
                } else if let value = assignedValue(key.tag, assigned) ?? fallbackValue(key.tag, dataSet)
                            ?? lastResortValue(key.tag, assigned) {
                    out[key.tag] = DataElement.string(tag: key.tag, vr: vr(of: key.tag), value: value)
                } else {
                    throw MissingKey(recordType: recordType, key: key, table: table)
                }
            case "2":
                out[key.tag] = dataSet[key.tag] ?? emptyElement(key.tag)
            default:  // 1C, 2C
                if let element = conditional(key.tag, recordType: recordType, dataSet: dataSet) {
                    out[key.tag] = element
                }
            }
        }
        // PS3.11 2026a Table D.3-2 (STD-GEN): Image Type and Referenced Image Sequence are 1C
        // "Required if present in image object"; both are Type 3 keys of every IMAGE record.
        if recordType == .image {
            for tag in [Tag.imageType, Tag.referencedImageSequence] {
                if let element = dataSet[tag] { out[tag] = element }
            }
        }
        return out
    }

    static func present(_ tag: Tag, in dataSet: DataSet) -> DataElement? {
        guard let element = dataSet[tag] else { return nil }
        if element.vr == .SQ { return (element.sequenceItems?.isEmpty ?? true) ? nil : element }
        if element.length == 0 { return nil }
        if element.vr.isStringVR,
           (element.stringValue ?? "").trimmingCharacters(in: CharacterSet(charactersIn: " \0")).isEmpty {
            return nil
        }
        return element
    }

    private static func assignedValue(_ tag: Tag, _ assigned: Assigned) -> String? {
        switch tag {
        case .studyID: return assigned.studyID
        case .seriesNumber: return assigned.seriesNumber
        case .instanceNumber: return assigned.instanceNumber
        case .modality: return assigned.modality
        default: return nil
        }
    }

    private static func lastResortValue(_ tag: Tag, _ assigned: Assigned) -> String? {
        switch tag {
        case .studyDate: return assigned.studyDate
        case .studyTime: return assigned.studyTime
        default: return nil
        }
    }

    /// Study Date / Study Time from the Series, Acquisition or Content Date / Time of the instance.
    private static func fallbackValue(_ tag: Tag, _ dataSet: DataSet) -> String? {
        let chain: [Tag]
        switch tag {
        case .studyDate: chain = [.seriesDate, .acquisitionDate, .contentDate]
        case .studyTime: chain = [.seriesTime, .acquisitionTime, .contentTime]
        default: return nil
        }
        for candidate in chain {
            if let value = dataSet.string(for: candidate)?.trimmingCharacters(in: .whitespaces), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func conditional(_ tag: Tag, recordType: DirectoryRecordType, dataSet: DataSet) -> DataElement? {
        switch tag {
        case .contentSequence:
            // "Contains the Target Content Items that modify the Concept Name Code Sequence
            // (0040,A043) of the root Content Item" — Relationship Type HAS CONCEPT MOD only.
            guard let items = dataSet.sequence(for: .contentSequence) else { return nil }
            let modifiers = items.filter { $0.string(for: .relationshipType)?.trimmingCharacters(in: .whitespaces) == "HAS CONCEPT MOD" }
            guard !modifiers.isEmpty else { return nil }
            var copy = DataSet()
            copy.setSequence(modifiers, for: .contentSequence)
            return copy[.contentSequence]
        case .verificationDateTime:
            // "Most recent Date and Time of verification among those defined in the Verifying
            // Observer Sequence (0040,A073). Required if Verification Flag (0040,A493) is VERIFIED."
            guard dataSet.string(for: .verificationFlag)?.trimmingCharacters(in: .whitespaces) == "VERIFIED" else { return nil }
            let times = (dataSet.sequence(for: .verifyingObserverSequence) ?? [])
                .compactMap { $0.string(for: .verificationDateTime)?.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard let latest = times.max() else { return dataSet[.verificationDateTime] }
            return DataElement.string(tag: .verificationDateTime, vr: .DT, value: latest)
        default:
            return present(tag, in: dataSet)
        }
    }

    static func vr(of tag: Tag) -> VR {
        DataElementDictionary.lookup(tag: tag)?.vr.first ?? .UN
    }

    static func emptyElement(_ tag: Tag) -> DataElement {
        let vr = vr(of: tag)
        if vr == .SQ {
            var copy = DataSet()
            copy.setSequence([], for: tag)
            if let element = copy[tag] { return element }
        }
        return DataElement(tag: tag, vr: vr, length: 0, valueData: Data())
    }
}

private extension VR {
    /// Character-string VRs, whose all-space value is empty.
    var isStringVR: Bool {
        switch self {
        case .AE, .AS, .CS, .DA, .DS, .DT, .IS, .LO, .LT, .PN, .SH, .ST, .TM, .UC, .UI, .UR, .UT: return true
        default: return false
        }
    }
}
