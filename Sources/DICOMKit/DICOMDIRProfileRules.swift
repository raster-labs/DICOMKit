// NEMA-verified: 2026a, checked 2026-10-01 — File-set Creator conformance rules: the SOP Class / Transfer Syntax rows of PS3.11 2026a Tables A.3-1, B.3-1, C.3-1, D.3-1, E.3-1, G.3-1, H.3-1, I.3-1, J.3-1, K.3-1, L.3-1, L.3-2, M.3-1, N.3-1 (57 rows, generated: DICOMDIRProfileTables.swift) mapped to the 64 identifiers of Tables A.1-1 to N.1-1; "Composite IODs for which a Media Storage SOP Class is defined in PS3.4" = PS3.4 2026a Table B.5-1 (170) + Table GG.3-1 (9) per PS3.4 I.4; File ID rules of PS3.10 2026a 8.2 (1-8 components of 1-8 characters) and 8.5 (A-Z, 0-9, _); "Multi-frame Composite IODs" rows admit only instances with Number of Frames (D233); the Additional DICOMDIR Keys tables A.3-2, B.3-2, D.3-2, E.3-2, H.3-2, I.3-2 and Icon Images sections are applied by DICOMDIRProfileKeys.swift (D239)
import Foundation
import DICOMCore
import DICOMDictionary

/// What a File-set Creator may put in a File-set it claims conforms to a PS3.11 Media
/// Storage Application Profile, and the PS3.10 File ID rules.
///
/// `DICOMDirectory.Builder.addFile` refuses (throws a ``Refusal``) an instance whose SOP
/// Class or Transfer Syntax the profile's PS3.11 table does not list, and a File ID that
/// breaks PS3.10 8.2 / 8.5: a profile identifier is a conformance claim (PS3.11 7), so a
/// File-set that breaks it is not written. Profiles PS3.11 does not define (private
/// identifiers, ``DICOMDIRProfile/none``) are not checked.
///
/// The per-profile image attribute values (PS3.11 Tables A.3-3, B.3-3, B.3-4, C.3-2, E.3-3 to
/// E.3-6, K.3-3, K.3-4, L.4-1, L.4-2) are checked by ``imageAttributeProblems(in:sopClassUID:transferSyntaxUID:profile:)``;
/// a row for "Multi-frame Composite IODs" only admits an instance with Number of Frames
/// (``refusal(sopClassUID:transferSyntaxUID:profile:isMultiFrame:)``).
public enum DICOMDIRProfileRules {

    /// Why an instance or File ID cannot go into the File-set.
    public enum Refusal: Error, CustomStringConvertible, Equatable, Sendable {
        /// The profile's PS3.11 table does not list this SOP Class.
        case sopClassNotInProfile(sopClassUID: String, profile: String, table: String)
        /// The profile's PS3.11 table does not list this Transfer Syntax for this SOP Class.
        case transferSyntaxNotInProfile(transferSyntaxUID: String, sopClassUID: String,
                                        profile: String, table: String, allowed: [String])
        /// The Referenced File ID breaks PS3.10 8.2 / 8.5.
        case nonConformantFileID(fileID: [String], problems: [String])
        /// Another Directory Record already references this SOP Instance.
        case duplicateSOPInstance(sopInstanceUID: String, fileID: [String])
        /// PS3.3 2026a F.5 defines no Directory Record Type for this SOP Class.
        case noDirectoryRecordType(sopClassUID: String)
        /// A Type 1 key of the record has no value in the instance and cannot be assigned.
        case missingRecordKey(recordType: String, key: String, tag: String, table: String)
        /// The instance breaks the profile's image attribute values (PS3.11 2026a).
        case imageAttributeValues(sopClassUID: String, profile: String, problems: [String])
        /// A Type 1 (or applicable 1C) key of the profile's PS3.11 2026a "Additional DICOMDIR Keys"
        /// table cannot be supplied (e.g. an Icon Image Sequence that cannot be made from the pixels).
        case missingProfileKey(profile: String, recordType: String, key: String, tag: String, table: String, reason: String)

        public var description: String {
            switch self {
            case let .sopClassNotInProfile(sop, profile, table):
                let what = DICOMDIRProfileRules.isGenericTable(table)
                    ? "is not a Media Storage SOP Class of PS3.4 2026a Table B.5-1 or GG.3-1 (\"Composite IODs for which a Media Storage SOP Class is defined in PS3.4\")"
                    : "is not one of the SOP Classes the profile lists"
                return "SOP Class \(DICOMDIRProfileRules.named(sop)) \(what); refused for \(profile) [PS3.11 2026a Table \(table)]"
            case let .transferSyntaxNotInProfile(ts, sop, profile, table, allowed):
                let list = allowed.map(DICOMDIRProfileRules.named).joined(separator: ", ")
                return "Transfer Syntax \(DICOMDIRProfileRules.named(ts)) is not allowed for SOP Class \(DICOMDIRProfileRules.named(sop)) in \(profile); the profile allows \(list) [PS3.11 2026a Table \(table)]"
            case let .nonConformantFileID(fileID, problems):
                return "File ID \(fileID.joined(separator: "\\")) is not a conformant File ID: \(problems.joined(separator: "; ")) [PS3.10 2026a 8.2, 8.5; PS3.3 Table F.3-3 Referenced File ID (0004,1500)]"
            case let .duplicateSOPInstance(uid, fileID):
                return "SOP Instance \(uid) is already referenced by File ID \(fileID.joined(separator: "\\")); a SOP Instance is indexed once [PS3.3 2026a Table F.3-3 Referenced SOP Instance UID in File (0004,1511)]"
            case let .noDirectoryRecordType(sop):
                return "SOP Class \(DICOMDIRProfileRules.named(sop)) has no Directory Record Type; refused [PS3.3 2026a F.4 Table F.4-1, F.5]"
            case let .missingRecordKey(recordType, key, tag, table):
                return "\(recordType) record: Type 1 key \(key) \(tag) has no value in the instance and cannot be supplied [PS3.3 2026a Table \(table); PS3.11 2026a D.3.3.1]"
            case let .missingProfileKey(profile, recordType, key, tag, table, reason):
                return "\(recordType) record: key \(key) \(tag), required by \(profile), cannot be supplied: \(reason) [PS3.11 2026a Table \(table)]"
            case let .imageAttributeValues(sop, profile, problems):
                return "SOP Class \(DICOMDIRProfileRules.named(sop)) instance breaks \(profile): \(problems.joined(separator: "; ")) [PS3.11 2026a]"
            }
        }
    }

    // MARK: - File IDs (PS3.10 8.2, 8.5)

    /// PS3.10 8.5 (Character Set): File IDs use A-Z, 0-9 and underscore (the CS repertoire without SPACE).
    public static let fileIDCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
    /// PS3.10 8.2: a File ID has one to eight components.
    public static let maxFileIDComponents = 8
    /// PS3.10 8.2: each component has one to eight characters.
    public static let maxFileIDComponentLength = 8

    /// The PS3.10 8.2 / 8.5 problems of a File ID (its components); empty when conformant.
    public static func fileIDProblems(_ components: [String]) -> [String] {
        var out: [String] = []
        if components.isEmpty || components.count > maxFileIDComponents {
            out.append("\(components.count) components, a File ID has 1 to \(maxFileIDComponents)")
        }
        for component in components {
            if component.isEmpty || component.count > maxFileIDComponentLength {
                out.append("component '\(component)' has \(component.count) characters, each has 1 to \(maxFileIDComponentLength)")
            }
            if !component.allSatisfy({ fileIDCharacters.contains($0) }) {
                out.append("component '\(component)' uses characters other than A-Z, 0-9 and _")
            }
        }
        return out
    }

    // MARK: - Profiles (PS3.11)

    /// The PS3.11 2026a "SOP Classes and Transfer Syntaxes" table that governs `profile`, or
    /// nil when PS3.11 does not define the identifier.
    public static func tableLabel(for profile: DICOMDIRProfile) -> String? {
        guard profile.isStandard else { return nil }
        let id = profile.rawValue
        switch id {
        case "STD-XABC-CD": return "A.3-1"
        case "STD-XA1K-CD", "STD-XA1K-DVD": return "B.3-1"
        case "STD-GEN-CD", "STD-GEN-DVD-RAM", "STD-GEN-SEC-CD", "STD-GEN-SEC-DVD-RAM", "STD-GEN-BD", "STD-GEN-SEC-BD":
            return "D.3-1"
        case "STD-GEN-MIME": return "G.3-1"
        case "STD-DVD-MPEG2-MPML", "STD-DVD-SEC-MPEG2-MPML": return "I.3-1"
        case "STD-DEN-CD": return "K.3-1"
        case "STD-GEN-ZIP-MAIL", "STD-GEN-SEC-ZIP-MAIL": return "L.3-1"
        case "STD-DTL-SEC-ZIP-MAIL": return "L.3-2"
        default: break
        }
        if id.hasPrefix("STD-US-") { return "C.3-1" }
        if id.hasPrefix("STD-CTMR-") { return "E.3-1" }
        if id.hasPrefix("STD-GEN-DVD-") || id.hasPrefix("STD-GEN-SEC-DVD-") { return "H.3-1" }
        for media in ["USB", "MMC", "CF", "SD"]
        where id.hasPrefix("STD-GEN-\(media)-") || id.hasPrefix("STD-GEN-SEC-\(media)-") {
            return "J.3-1"
        }
        if id.contains("-HPLV42-") || id.hasSuffix("-SHPLV42") { return "N.3-1" }
        if id.hasPrefix("STD-GEN-BD-") || id.hasPrefix("STD-GEN-SEC-BD-") { return "M.3-1" }
        return nil
    }

    /// The Transfer Syntax UIDs a File-set Creator may write for `sopClassUID` under `profile`.
    /// nil: no restriction (PS3.11 leaves it to the Conformance Statement, or the profile is
    /// not a PS3.11 one). An empty set: the profile does not admit this SOP Class at all.
    public static func allowedTransferSyntaxes(sopClassUID: String, profile: DICOMDIRProfile) -> Set<String>? {
        allowedTransferSyntaxes(sopClassUID: sopClassUID, profile: profile, isMultiFrame: nil)
    }

    /// As ``allowedTransferSyntaxes(sopClassUID:profile:)``; with `isMultiFrame == false` the
    /// rows for "Multi-frame Composite IODs" (the MPEG Transfer Syntaxes) are left out.
    public static func allowedTransferSyntaxes(sopClassUID: String, profile: DICOMDIRProfile,
                                               isMultiFrame: Bool?) -> Set<String>? {
        guard let label = tableLabel(for: profile), let rows = tables[label] else { return nil }
        var allowed = Set<String>()
        for row in rows where applies(row, table: label, to: profile.rawValue)
            && admits(row, sopClassUID: sopClassUID, profileID: profile.rawValue)
            && !(row.multiFrameOnly && isMultiFrame == false) {
            guard let ts = row.transferSyntaxUID else { return nil }
            allowed.insert(ts)
        }
        return allowed
    }

    /// The refusal for an instance of `sopClassUID` in `transferSyntaxUID` under `profile`,
    /// or nil when the profile admits it.
    public static func refusal(sopClassUID: String, transferSyntaxUID: String,
                               profile: DICOMDIRProfile) -> Refusal? {
        refusal(sopClassUID: sopClassUID, transferSyntaxUID: transferSyntaxUID, profile: profile, isMultiFrame: nil)
    }

    /// As ``refusal(sopClassUID:transferSyntaxUID:profile:)``; `isMultiFrame` (the instance has
    /// Number of Frames (0028,0008)) decides the "Multi-frame Composite IODs" rows; nil: unknown.
    public static func refusal(sopClassUID: String, transferSyntaxUID: String,
                               profile: DICOMDIRProfile, isMultiFrame: Bool?) -> Refusal? {
        guard let label = tableLabel(for: profile),
              let allowed = allowedTransferSyntaxes(sopClassUID: sopClassUID, profile: profile,
                                                    isMultiFrame: isMultiFrame) else { return nil }
        if allowed.isEmpty {
            return .sopClassNotInProfile(sopClassUID: sopClassUID, profile: profile.rawValue, table: label)
        }
        guard allowed.contains(transferSyntaxUID) else {
            return .transferSyntaxNotInProfile(
                transferSyntaxUID: transferSyntaxUID, sopClassUID: sopClassUID,
                profile: profile.rawValue, table: label, allowed: allowed.sorted(by: uidOrder))
        }
        return nil
    }

    // MARK: - Row applicability

    /// Whether a table row applies to the profile `id` (the qualifiers the tables write in
    /// their requirement columns, and the MPEG syntax each MPEG profile is named after).
    static func applies(_ row: TableRow, table: String, to id: String) -> Bool {
        // B.3-1: JPEG Baseline / Extended are "Disallowed for CD".
        if row.fsc.contains("Disallowed for CD"), id.hasSuffix("-CD") { return false }
        // H.3-1, J.3-1, M.3-1: "Mandatory for -JPEG profiles" / "for J2K profiles".
        if row.fsr.contains("JPEG profiles"), !id.hasSuffix("-JPEG") { return false }
        if row.fsr.contains("J2K profiles"), !id.hasSuffix("-J2K") { return false }
        // M.3-1 / N.3-1 MPEG rows: each profile is named after the one syntax it carries
        // (Tables M.1-1, N.1-1).
        if ["M.3-1", "N.3-1"].contains(table), row.multiFrameOnly,
           let ts = row.transferSyntaxUID, let suffix = mpegProfileSuffix[ts] {
            return id.hasSuffix(suffix)
        }
        return true
    }

    /// Whether a row admits `sopClassUID` (C.3-1: single-frame profiles carry the
    /// Ultrasound Image only, Table C.1-1).
    static func admits(_ row: TableRow, sopClassUID: String, profileID: String) -> Bool {
        if profileID.hasPrefix("STD-US-"), profileID.contains("-SF-"),
           sopClassUID == ultrasoundMultiFrameSOPClassUID { return false }
        guard let rowSOP = row.sopClassUID else { return isMediaStorageSOPClass(sopClassUID) }
        return rowSOP == sopClassUID
    }

    /// PS3.4 I.4: the Storage SOP Classes of Table B.5-1 and the Non-Patient Object Storage
    /// SOP Classes of Table GG.3-1 (the Media Storage Directory itself is not a composite IOD).
    public static func isMediaStorageSOPClass(_ uid: String) -> Bool {
        StorageSOPClass.allUIDSet.contains(uid) || nonPatientStorageUIDs.contains(uid)
    }

    /// The identifier suffix of the M.3-1 / N.3-1 profile each MPEG Transfer Syntax belongs to.
    static let mpegProfileSuffix: [String: String] = [
        "1.2.840.10008.1.2.4.100": "-MPEG2-MPML",       // MPEG2 Main Profile / Main Level
        "1.2.840.10008.1.2.4.101": "-MPEG2-MPHL",       // MPEG2 Main Profile / High Level
        "1.2.840.10008.1.2.4.102": "-MPEG4-HPLV41",     // MPEG-4 AVC/H.264 High Profile / Level 4.1
        "1.2.840.10008.1.2.4.103": "-MPEG4-HPLV41BD",   // ... BD-compatible High Profile / Level 4.1
        "1.2.840.10008.1.2.4.104": "-MPEG4-HPLV42-2D",  // ... High Profile / Level 4.2 For 2D Video
        "1.2.840.10008.1.2.4.105": "-MPEG4-HPLV42-3D",  // ... High Profile / Level 4.2 For 3D Video
        "1.2.840.10008.1.2.4.106": "-MPEG4-SHPLV42",    // ... Stereo High Profile / Level 4.2
    ]

    /// Ultrasound single-frame profiles (STD-US-xx-SF-xxxx) admit the Ultrasound Image only.
    static let ultrasoundMultiFrameSOPClassUID = "1.2.840.10008.5.1.4.1.1.3.1"

    static func isGenericTable(_ label: String) -> Bool {
        tables[label]?.contains { $0.sopClassUID == nil } ?? false
    }

    static func named(_ uid: String) -> String {
        if let name = UIDDictionary.lookup(uid: uid)?.name { return "\(name) (\(uid))" }
        return uid
    }

    private static func uidOrder(_ a: String, _ b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        return x.lexicographicallyPrecedes(y)
    }
}
