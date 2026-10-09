// NEMA-verified: 2026a, checked 2026-10-06 — lifted from Sources/dicom-anon/AnonCLISupport.swift (D275) so dicom-anon and the DICOMStudio CLI Workshop (legacy and ps315 paths) share one copy; re-checked by script against the DocBook: option names are the 12 Options of PS3.15 2026a E.3 / the Option columns of Table E.1-1 (11 offered here; Clean Pixel Data in the CLI); E.3.6 "Full Dates" and "Modified Dates" Options mutually exclusive; E.3.2 Clean Recognizable Visual Features needs operator regions; `ps315` / `basic` are the Basic Application Level Confidentiality Profile (every row of Table E.1-1), the legacy-* lists are not PS3.15 profiles; action labels D, Z, X, C, U are the PS3.15 2026a Table E.1-1a single codes (K not listed: unchanged); the file meta sync writes Media Storage SOP Instance UID (0002,0003) = SOP Instance UID (0008,0018) per PS3.10 2026a Table 7.1-1; names from PS3.6 2026a Table 6-1 via DataElementDictionary. Texts unchanged (CLI parity).
//
// AnonCLISupport.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore
import DICOMDictionary

/// The `dicom-anon` command surface that is not ArgumentParser plumbing: option
/// validation against PS3.15 Annex E, tag parsing, and the per-attribute action report.
///
/// Lifted from the CLI (D275) so `dicom-anon` and the DICOMStudio CLI Workshop
/// (legacy and ps315 paths) share one copy next to ``Anonymizer`` / ``AnonConsole``.
public enum AnonCLI {

    /// A rejected option combination (``validate(profile:flags:shiftDates:regenerateUids:keep:redactRegions:)``).
    /// The CLI rethrows it as ArgumentParser's `ValidationError` with the same message.
    /// `localizedDescription` is the message, as for the CLI's own `ValidationError`.
    public struct ValidationError: LocalizedError, CustomStringConvertible, Equatable {
        public let message: String
        public init(_ message: String) { self.message = message }
        public var description: String { message }
        public var errorDescription: String? { message }
    }


    /// The PS3.15 E.3 option flags the command offers for `--profile ps315`.
    public struct PS315Flags: Equatable, Sendable {
        public var retainDates = false
        public var retainFullDates = false
        public var retainModifiedDates = false
        public var retainCharacteristics = false
        public var retainDevice = false
        public var retainInstitution = false
        public var retainUids = false
        public var cleanDescriptors = false
        public var retainSafePrivate = false
        public var cleanGraphics = false
        public var cleanStructuredContent = false
        public var cleanRecognizableVisualFeatures = false

        public init(retainDates: Bool = false, retainFullDates: Bool = false, retainModifiedDates: Bool = false,
                    retainCharacteristics: Bool = false, retainDevice: Bool = false, retainInstitution: Bool = false,
                    retainUids: Bool = false, cleanDescriptors: Bool = false, retainSafePrivate: Bool = false,
                    cleanGraphics: Bool = false, cleanStructuredContent: Bool = false,
                    cleanRecognizableVisualFeatures: Bool = false) {
            self.retainDates = retainDates
            self.retainFullDates = retainFullDates
            self.retainModifiedDates = retainModifiedDates
            self.retainCharacteristics = retainCharacteristics
            self.retainDevice = retainDevice
            self.retainInstitution = retainInstitution
            self.retainUids = retainUids
            self.cleanDescriptors = cleanDescriptors
            self.retainSafePrivate = retainSafePrivate
            self.cleanGraphics = cleanGraphics
            self.cleanStructuredContent = cleanStructuredContent
            self.cleanRecognizableVisualFeatures = cleanRecognizableVisualFeatures
        }

        /// Every flag that is set, by its command-line spelling.
        public var setFlags: [String] {
            [("--retain-dates", retainDates), ("--retain-full-dates", retainFullDates),
             ("--retain-modified-dates", retainModifiedDates),
             ("--retain-characteristics", retainCharacteristics), ("--retain-device", retainDevice),
             ("--retain-institution", retainInstitution), ("--retain-uids", retainUids),
             ("--clean-descriptors", cleanDescriptors), ("--retain-safe-private", retainSafePrivate),
             ("--clean-graphics", cleanGraphics), ("--clean-structured-content", cleanStructuredContent),
             ("--clean-recognizable-visual-features", cleanRecognizableVisualFeatures)].filter(\.1).map(\.0)
        }
    }

    /// A `--profile` value resolved to what the run applies (P-ANON-PROFILE).
    ///
    /// `ps315` is the default and the PS3.15 2026a E.1 Basic Application Level
    /// Confidentiality Profile (every row of Table E.1-1); `basic` is an alias of it.
    /// The three fixed attribute lists that `basic`, `clinical-trial` and `research`
    /// used to name are kept as `legacy-basic`, `legacy-clinical-trial` and
    /// `legacy-research`: they are not PS3.15 profiles, and are deprecated.
    public enum Profile: String, CaseIterable, Equatable, Sendable {
        case ps315
        case legacyBasic = "legacy-basic"
        case legacyClinicalTrial = "legacy-clinical-trial"
        case legacyResearch = "legacy-research"

        public var isPS315: Bool { self == .ps315 }

        /// The legacy engine list; nil for `ps315`, which bypasses the legacy engine.
        public var legacyProfile: AnonymizationProfile? {
            switch self {
            case .ps315: return nil
            case .legacyBasic: return .basic
            case .legacyClinicalTrial: return .clinicalTrial
            case .legacyResearch: return .research
            }
        }
    }

    /// The default `--profile`: the PS3.15 Basic Profile.
    public static let defaultProfile = "ps315"

    /// Old spellings and what they now resolve to (P-ANON-PROFILE). `basic` is the
    /// PS3.15 Basic Profile; `clinical-trial` / `research` are not standard profile
    /// names, so they keep their legacy lists, deprecated.
    public static let profileAliases: [String: Profile] = [
        "ps315": .ps315,
        "basic": .ps315,
        "legacy-basic": .legacyBasic,
        "legacy-clinical-trial": .legacyClinicalTrial,
        "legacy-research": .legacyResearch,
        "clinical-trial": .legacyClinicalTrial,
        "clinicaltrial": .legacyClinicalTrial,
        "research": .legacyResearch,
    ]

    /// Resolves a `--profile` value (case-insensitive); nil when unknown.
    public static func resolveProfile(_ value: String) -> Profile? {
        profileAliases[value.trimmingCharacters(in: .whitespaces).lowercased()]
    }

    /// The legacy profile values: fixed attribute lists, not PS3.15 Annex E.
    public static let legacyProfiles: Set<String> = Set(profileAliases.filter { !$0.value.isPS315 }.keys)

    /// Rejects option combinations that the command would otherwise ignore silently.
    ///
    /// - The PS3.15 E.3 option flags act only on `--profile ps315`.
    /// - PS3.15 E.3.6: the Full Dates and Modified Dates options are mutually exclusive;
    ///   `--shift-dates` is how the dates are modified, so it needs the Modified Dates
    ///   option and is meaningless with Full Dates.
    /// - `--keep` is applied only by the legacy profiles.
    /// - PS3.15 E.3.2: recognizable visual features are not detected automatically, so
    ///   `--clean-recognizable-visual-features` needs the operator's `--redact-region`s.
    public static func validate(profile: String, flags: PS315Flags, shiftDates: Int?,
                         regenerateUids: Bool, keep: [String], redactRegions: [String] = []) throws {
        guard let resolved = resolveProfile(profile) else {
            throw ValidationError("Unknown --profile '\(profile)': use ps315 (or its alias basic), "
                + "or the deprecated legacy-basic, legacy-clinical-trial, legacy-research")
        }
        guard resolved.isPS315 else {
            if !flags.setFlags.isEmpty {
                throw ValidationError(
                    "PS3.15 Annex E Option flags apply only to --profile ps315: \(flags.setFlags.joined(separator: ", "))")
            }
            return
        }
        if flags.retainFullDates && (flags.retainModifiedDates || shiftDates != nil) {
            throw ValidationError(
                "--retain-full-dates (Retain Longitudinal Temporal Information With Full Dates Option) "
                + "excludes --retain-modified-dates and --shift-dates (PS3.15 E.3.6: the two Options are mutually exclusive)")
        }
        if flags.retainModifiedDates && shiftDates == nil {
            throw ValidationError(
                "--retain-modified-dates (Retain Longitudinal Temporal Information With Modified Dates Option) "
                + "needs --shift-dates N: shifting is how the dates are modified")
        }
        if shiftDates != nil && !(flags.retainDates || flags.retainModifiedDates) {
            throw ValidationError(
                "--shift-dates with --profile ps315 needs --retain-modified-dates (or --retain-dates): "
                + "without a Retain Longitudinal Temporal Information Option the Basic Profile removes dates")
        }
        if regenerateUids && flags.retainUids {
            throw ValidationError("--regenerate-uids contradicts --retain-uids (Retain UIDs Option)")
        }
        if !keep.isEmpty {
            throw ValidationError(
                "--keep is not applied by --profile ps315; select a PS3.15 Option (--retain-*) instead")
        }
        if flags.cleanRecognizableVisualFeatures && redactRegions.isEmpty {
            throw ValidationError(visualFeaturesNeedRegions)
        }
    }

    /// Refusal of `--clean-recognizable-visual-features` without a region (PS3.15 E.3.2).
    public static let visualFeaturesNeedRegions =
        "--clean-recognizable-visual-features (PS3.15 E.3.2 Clean Recognizable Visual Features Option) "
        + "needs one or more --redact-region x,y,width,height: recognizable visual features are not "
        + "detected automatically (E.3.2: \"This may require intervention of or approval by a human "
        + "operator\"), and Recognizable Visual Features (0028,0302) = NO with code 113102 is recorded "
        + "only when the operator's regions have been blanked"

    /// Verbose report of the Clean Recognizable Visual Features pass (PS3.15 E.3.2).
    public static func visualFeaturesLines(outcome: PixelRedactor.Outcome) -> String {
        var out = "Cleaned recognizable visual features (PS3.15 E.3.2): \(outcome.note)\n"
        for r in outcome.regions {
            out += "  blanked (\(r.x),\(r.y)) \(r.width)x\(r.height)"
            out += outcome.frameCount > 1 ? " on all \(outcome.frameCount) frames\n" : "\n"
        }
        if outcome.removedIconImage { out += "  removed Icon Image Sequence (derived before cleaning)\n" }
        out += "  recorded DCM 113102 Clean Recognizable Visual Features Option; Recognizable Visual Features = NO\n"
        out += "  ⚠️  Verify visually (and in any 3D reconstruction of the series) that recognition is prevented.\n"
        return out
    }

    /// The engine options for `--profile ps315`.
    public static func options(flags: PS315Flags, shiftDates: Int?) -> ConfidentialityProfile.Options {
        ConfidentialityProfile.Options(
            retainLongitudinalTemporal: flags.retainDates || flags.retainFullDates || flags.retainModifiedDates,
            retainPatientCharacteristics: flags.retainCharacteristics,
            retainDeviceIdentity: flags.retainDevice,
            retainInstitutionIdentity: flags.retainInstitution,
            retainUIDs: flags.retainUids,
            cleanDescriptors: flags.cleanDescriptors,
            dateOffsetDays: shiftDates,
            retainSafePrivate: flags.retainSafePrivate,
            cleanGraphics: flags.cleanGraphics,
            cleanStructuredContent: flags.cleanStructuredContent)
    }

    /// Stderr notice for a `--profile` value: the deprecated legacy lists (which are
    /// not PS3.15 Annex E), and `basic`, whose meaning changed to the PS3.15 Basic
    /// Profile. Nil for `ps315`.
    public static func legacyProfileNotice(_ profile: String) -> String? {
        let key = profile.trimmingCharacters(in: .whitespaces).lowercased()
        guard let resolved = resolveProfile(key) else { return nil }
        if key == "basic" {
            return "Note: --profile basic is the PS3.15 Basic Application Level Confidentiality Profile "
                + "(same as ps315, PS3.15 Table E.1-1). The former basic attribute list is --profile legacy-basic."
        }
        guard !resolved.isPS315 else { return nil }
        var text = "Deprecated: --profile \(profile) "
        if key != resolved.rawValue { text += "(now \(resolved.rawValue)) " }
        return text + "is a legacy attribute list, not a PS3.15 Annex E profile; it records no "
            + "Patient Identity Removed (0012,0062). Use --profile ps315 (PS3.15 Basic Application Level "
            + "Confidentiality Profile, Table E.1-1)."
    }

    /// Stderr notice for the deprecated `--retain-dates` (P-ANON-RETAIN-DATES).
    public static func retainDatesNotice(shiftDates: Int?) -> String {
        "Deprecated: --retain-dates; use --retain-full-dates (Retain Longitudinal Temporal Information With "
            + "Full Dates Option) or --retain-modified-dates with --shift-dates (... With Modified Dates Option), "
            + "PS3.15 E.3.6. This run applies the "
            + (shiftDates == nil ? "Full Dates" : "Modified Dates") + " Option."
    }

    /// A tag given to --remove / --replace / --keep: `gggg,eeee`, `(gggg,eeee)`,
    /// `ggggeeee`, or a PS3.6 Table 6-1 keyword (e.g. `PatientAge`).
    /// The shared parser knows every keyword since D163, so this is a plain pass-through.
    public static func parseTag(_ string: String) -> Tag? {
        Anonymizer.parseFlexibleTag(string)
    }

    /// Applies --remove / --replace after the PS3.15 pass (the engine takes no custom
    /// actions). A replacement is written only for an attribute present in the source,
    /// with the source VR, as the legacy path does.
    public static func applyCustomActions(_ actions: [Tag: AnonymizationAction], source: DataSet,
                                   to dataSet: inout DataSet) {
        for (tag, action) in actions {
            switch action {
            case .remove:
                dataSet.remove(tag: tag)
            case .replaceWithDummy(let value):
                if let element = source[tag] { dataSet.setString(value, for: tag, vr: element.vr) }
            default:
                break
            }
        }
    }

    /// PS3.10 7.1: the file meta Media Storage SOP Instance UID (0002,0003) is the SOP
    /// Instance UID (0008,0018) of the data set. Applied to the output file, so a replaced
    /// (U) SOP Instance UID does not survive in the meta header.
    public static func syncingMediaStorageSOPInstanceUID(_ file: DICOMFile) -> DICOMFile {
        guard let uid = file.dataSet.string(for: .sopInstanceUID)?
                .trimmingCharacters(in: CharacterSet(charactersIn: " \0")), !uid.isEmpty,
              file.fileMetaInformation[.mediaStorageSOPInstanceUID] != nil else { return file }
        var meta = file.fileMetaInformation
        meta.setString(uid, for: .mediaStorageSOPInstanceUID, vr: .UI)
        return DICOMFile(fileMetaInformation: meta, dataSet: file.dataSet)
    }

    // MARK: - Per-attribute action report

    /// One top-level attribute the run changed, with the PS3.15 Table E.1-1a action code
    /// that describes what was done to it.
    public struct AttributeAction: Equatable, Sendable {
        public let tag: Tag
        /// D, Z, X, C or U (Table E.1-1a), or "recorded" for the de-identification
        /// method / attestation attributes the run writes.
        public let code: String
        /// PS3.6 Table 6-1 name.
        public let name: String

        public init(tag: Tag, code: String, name: String) {
            self.tag = tag
            self.code = code
            self.name = name
        }
    }

    /// The attributes the run writes to record what it did (PS3.15 E.1.1, E.3).
    public static let recordingTags: Set<Tag> = [
        Tag(group: 0x0012, element: 0x0062), // Patient Identity Removed
        Tag(group: 0x0012, element: 0x0063), // De-identification Method
        Tag(group: 0x0012, element: 0x0064), // De-identification Method Code Sequence
        Tag(group: 0x0028, element: 0x0301), // Burned In Annotation
        Tag(group: 0x0028, element: 0x0302), // Recognizable Visual Features
        Tag(group: 0x0028, element: 0x0303), // Longitudinal Temporal Information Modified
    ]

    /// PS3.6 name of a tag; private and unknown tags are labelled as such.
    public static func name(of tag: Tag) -> String {
        if tag.isPrivate { return "Private Data Element" }
        return DataElementDictionary.lookup(tag: tag)?.name ?? "(not in PS3.6)"
    }

    /// Compares the source and output data sets attribute by attribute (top level;
    /// Pixel Data and group 0002 excluded) and labels each change with its E.1-1a code.
    /// `options` is nil for the legacy profiles.
    public static func attributeActions(before: DataSet, after: DataSet,
                                 options: ConfidentialityProfile.Options?) -> [AttributeAction] {
        var out: [AttributeAction] = []
        let tags = Set(before.tags).union(after.tags)
            .filter { $0 != .pixelData && $0.group != 0x0002 }
            .sorted { ($0.group, $0.element) < ($1.group, $1.element) }
        for tag in tags {
            let old = before[tag], new = after[tag]
            if let old, let new, fingerprint(old) == fingerprint(new) { continue }
            let code: String
            if recordingTags.contains(tag) {
                code = "recorded"
            } else if old == nil {
                code = "added"
            } else if let new {
                if isZeroLength(new) {
                    code = "Z"
                } else if let options, let applied = ConfidentialityProfile.action(for: tag, options: options),
                          applied == .clean
                            || (applied == .zeroOrDummy && options.retainLongitudinalTemporal
                                && options.dateOffsetDays != nil) {
                    code = "C"
                } else {
                    code = new.vr == .UI ? "U" : "D"
                }
            } else {
                code = "X"
            }
            out.append(AttributeAction(tag: tag, code: code, name: name(of: tag)))
        }
        return out
    }

    /// The action lines printed for one file (--dry-run or --verbose).
    public static func actionLines(path: String, actions: [AttributeAction]) -> String {
        var s = "\nAttribute actions for \(path) (PS3.15 Table E.1-1a: D dummy, Z zero length, "
            + "X removed, C cleaned, U new UID):\n"
        if actions.isEmpty { s += "  (none)\n" }
        for a in actions { s += "  \(a.code.padding(toLength: 8, withPad: " ", startingAt: 0)) \(a.tag) \(a.name)\n" }
        return s
    }

    /// The --audit-log text for `--profile ps315`: one line per changed attribute with
    /// its E.1-1a code and PS3.6 name. Values are not written (the log must not itself
    /// carry the identifiers that were removed).
    public static func auditLogText(profileDescription: [String], files: [(path: String, actions: [AttributeAction])],
                                    generated: Date) -> String {
        let iso = ISO8601DateFormatter().string(from: generated)
        var text = "DICOM Anonymization Audit Log\nGenerated: \(iso)\n"
        text += "Method: \(profileDescription.joined(separator: "; "))\n\n"
        for file in files {
            for a in file.actions { text += "[\(iso)] \(file.path) - \(a.code) - \(a.tag) \(a.name)\n" }
        }
        return text
    }

    private static func isZeroLength(_ e: DataElement) -> Bool {
        if let items = e.sequenceItems { return items.isEmpty }
        return e.valueData.allSatisfy { $0 == 0x20 || $0 == 0x00 }
    }

    private static func fingerprint(_ e: DataElement) -> String {
        if let items = e.sequenceItems {
            return "SQ[" + items.map { item in
                item.allElements.sorted { ($0.tag.group, $0.tag.element) < ($1.tag.group, $1.tag.element) }
                    .map(fingerprint).joined(separator: ",")
            }.joined(separator: "|") + "]"
        }
        return "\(e.tag)\(e.vr):\(e.valueData.base64EncodedString())"
    }
}
