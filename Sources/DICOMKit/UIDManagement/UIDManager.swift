// NEMA-verified: 2026a, checked 2026-09-29 — PS3.5 2026a 9.1 UID syntax (at most 64 characters, numeric components, no leading zeros); UIDType labels via DICOMDictionary
// NEMA-verified: 2026a, checked 2026-10-01 — validateUID checks exactly the PS3.5 2026a 9.1 rules and cites them (no "at least 2 components" rule, D133); validateFileUIDs and regenerate walk every sequence item (D133, D135); regenerate replaces only the 57 UI attributes of PS3.15 2026a Table E.1-1 (action U, Annotation Group UID D; dumped by script with PS3.6 2026a VRs), never a PS3.6 Table A-1 UID, mapping each old UID to one new UID within a file and, with maintainRelationships, across files (D135, D138); not-found and --type texts name PS3.6 2026a Table A-1 and its 11 filterable UID Types (D136)
// NEMA-verified: 2026a, checked 2026-10-01 — validateUID checks exactly the PS3.5 2026a 9.1 rules and cites them (no "at least 2 components" rule, D133); validateFileUIDs and regenerate walk every sequence item (D133, D135); regenerate replaces only the 57 UI attributes of PS3.15 2026a Table E.1-1 (action U, Annotation Group UID D; dumped by script with PS3.6 2026a VRs), never a PS3.6 Table A-1 UID, mapping each old UID to one new UID within a file and, with maintainRelationships, across files (D135, D138); not-found and --type texts name PS3.6 2026a Table A-1 and its 11 filterable UID Types (D136)
// NEMA-verified: 2026a, checked 2026-10-06 — UIDManager.RootRule (lifted from dicom-uid UIDRootRule, D250) checks a root against the PS3.5 2026a 9.1 encoding rules read by script (components of one or more digits 0-9, no leading zero unless the component is a single digit, "." separators, at most 64 characters) and the room the generator's suffix needs within DICOMUniqueIdentifier.maximumLength
import Foundation
import DICOMCore
import DICOMDictionary

// Shared UID workflow engine for the `dicom-uid` CLI and DICOMStudio. Builds on
// the already-shared `UIDGenerator` (DICOMCore) and `UIDDictionary`
// (DICOMDictionary); this layer is the generate/validate/lookup/regenerate
// workflow both adapters call. No ArgumentParser / Process / printing here —
// adapters format the returned values/structs and handle I/O.

/// Errors for UID management operations
public enum UIDManagerError: Error, CustomStringConvertible {
    case fileNotFound(String)
    case invalidUID(String, String)
    case noUIDsFound(String)
    case writeError(String)

    public var description: String {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .invalidUID(let uid, let reason):
            return "Invalid UID '\(uid)': \(reason)"
        case .noUIDsFound(let path):
            return "No UIDs found in file: \(path)"
        case .writeError(let message):
            return "Write error: \(message)"
        }
    }
}

/// UID validation result
public struct UIDValidationResult {
    public let uid: String
    public let isValid: Bool
    public let errors: [String]
    public let registryName: String?

    public init(uid: String, isValid: Bool, errors: [String], registryName: String?) {
        self.uid = uid
        self.isValid = isValid
        self.errors = errors
        self.registryName = registryName
    }
}

/// UID mapping entry for old-to-new UID tracking
public struct UIDMapping: Codable {
    public let oldUID: String
    public let newUID: String
    public let tagName: String
    public let tagHex: String

    public init(oldUID: String, newUID: String, tagName: String, tagHex: String) {
        self.oldUID = oldUID
        self.newUID = newUID
        self.tagName = tagName
        self.tagHex = tagHex
    }
}

/// Manager for UID operations
public struct UIDManager {

    public init() {}

    // MARK: - UID Generation

    /// Generates UIDs with the specified root
    public func generateUIDs(count: Int, root: String?, type: String?) -> [String] {
        let generator = UIDGenerator(root: root ?? UIDGenerator.defaultRoot)
        var results: [String] = []

        for _ in 0..<count {
            let uid: DICOMUniqueIdentifier
            switch type?.lowercased() {
            case "study":
                uid = generator.generateStudyInstanceUID()
            case "series":
                uid = generator.generateSeriesInstanceUID()
            case "instance", "sop":
                uid = generator.generateSOPInstanceUID()
            default:
                uid = generator.generate()
            }
            results.append(uid.value)
        }

        return results
    }

    // MARK: - UID Validation

    /// Validates a UID string
    public func validateUID(_ uidString: String) -> UIDValidationResult {
        var errors: [String] = []

        // Check length
        if uidString.count > 64 {
            errors.append("Exceeds maximum length of 64 characters (length: \(uidString.count)) (PS3.5 9.1)")
        }

        // Check empty
        if uidString.isEmpty {
            errors.append("UID is empty; a UID has at least one component of one or more digits (PS3.5 9.1)")
            return UIDValidationResult(uid: uidString, isValid: false, errors: errors, registryName: nil)
        }

        // Check allowed characters
        let allowedCharacters = CharacterSet(charactersIn: "0123456789.")
        if uidString.unicodeScalars.contains(where: { !allowedCharacters.contains($0) }) {
            errors.append("Contains invalid characters (only digits 0-9 and the separator \".\" allowed) (PS3.5 9.1)")
        }

        // Check leading/trailing periods
        if uidString.hasPrefix(".") {
            errors.append("Must not start with a period: every component has one or more digits (PS3.5 9.1)")
        }
        if uidString.hasSuffix(".") {
            errors.append("Must not end with a period: every component has one or more digits (PS3.5 9.1)")
        }

        // Check consecutive periods
        if uidString.contains("..") {
            errors.append("Must not contain consecutive periods: every component has one or more digits (PS3.5 9.1)")
        }

        // Check leading zeros in components
        let components = uidString.split(separator: ".", omittingEmptySubsequences: false)
        for component in components {
            if component.count > 1 && component.hasPrefix("0") {
                errors.append("Component '\(component)' has a leading zero; only a single-digit component may start with 0 (PS3.5 9.1)")
            }
        }

        // PS3.5 9.1 sets no minimum number of components (the former "at least 2
        // components" check was not a 9.1 rule, D133).

        // Registry lookup
        let entry = UIDDictionary.lookup(uid: uidString)
        let registryName = entry?.name

        return UIDValidationResult(
            uid: uidString,
            isValid: errors.isEmpty,
            errors: errors,
            registryName: registryName
        )
    }

    /// Validates every UID in a DICOM file: each value of every UI element of the File Meta
    /// Information and of the data set, including the elements inside sequence items
    /// (PS3.5 9.1), in tag order, depth first.
    public func validateFileUIDs(path: String) throws -> [UIDValidationResult] {
        guard FileManager.default.fileExists(atPath: path) else {
            throw UIDManagerError.fileNotFound(path)
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let file = try DICOMFile.read(from: data)
        return (Self.uidValues(in: file.fileMetaInformation) + Self.uidValues(in: file.dataSet))
            .map { validateUID($0) }
    }

    /// Every non-empty value of every UI element in `dataSet` and its sequence items,
    /// depth first, padding (NULL / space) removed.
    static func uidValues(in dataSet: DataSet) -> [String] {
        var out: [String] = []
        for tag in dataSet.tags.sorted() {
            guard let element = dataSet[tag] else { continue }
            if element.vr == .UI {
                for value in dataSet.strings(for: tag) ?? [] {
                    let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
                    if !trimmed.isEmpty { out.append(trimmed) }
                }
            } else if let items = element.sequenceItems {
                for item in items { out += uidValues(in: DataSet(elements: item.allElements)) }
            }
        }
        return out
    }

    // MARK: - UID Lookup

    /// Look up a UID in the DICOM registry
    public func lookupUID(_ uidString: String) -> (name: String, type: String)? {
        if let entry = UIDDictionary.lookup(uid: uidString) {
            return (name: entry.name, type: Self.uidTypeDescription(entry.type))
        }
        return nil
    }

    // MARK: - UID Regeneration

    /// UID tags that should be regenerated
    @available(*, deprecated, message: "Lists 3 of the UIDs regenerate replaces; use regeneratedUIDTags (the UI attributes of PS3.15 Table E.1-1)")
    public static let uidTags: [(tag: Tag, name: String)] = [
        (.sopInstanceUID, "SOPInstanceUID"),
        (.studyInstanceUID, "StudyInstanceUID"),
        (.seriesInstanceUID, "SeriesInstanceUID"),
    ]

    /// The UID attributes `regenerate` replaces: every attribute of PS3.15 2026a Table E.1-1
    /// (Basic Application Level Confidentiality Profile) whose VR is UI — action U, and D for
    /// Annotation Group UID (a dummy UID). These identify instances, series, studies, frames
    /// of reference and other real-world entities. UIDs of any other attribute (SOP Class,
    /// Transfer Syntax, Coding Scheme UID, Context Group Extension Creator UID, Mapping
    /// Resource UID, private UI attributes, …) are never replaced, nor is a value that is a
    /// PS3.6 Table A-1 UID (e.g. a Well-known SOP Instance).
    ///
    /// NEMA-verified: 2026a, checked 2026-10-01 — the 57 rows of PS3.15 2026a Table E.1-1 whose
    /// VR in PS3.6 2026a Tables 6-1 / 7-1 / 8-1 (or PS3.7 Table E.1-1) is UI, dumped by script.
    public static let regeneratedUIDTags: Set<Tag> = [
        Tag(group: 0x0000, element: 0x1000),  // Affected SOP Instance UID (X)
        Tag(group: 0x0000, element: 0x1001),  // Requested SOP Instance UID (U)
        Tag(group: 0x0002, element: 0x0003),  // Media Storage SOP Instance UID (U)
        Tag(group: 0x0004, element: 0x1511),  // Referenced SOP Instance UID in File (U)
        Tag(group: 0x0008, element: 0x0014),  // Instance Creator UID (U)
        Tag(group: 0x0008, element: 0x0017),  // Acquisition UID (U)
        Tag(group: 0x0008, element: 0x0018),  // SOP Instance UID (U)
        Tag(group: 0x0008, element: 0x0019),  // Pyramid UID (U)
        Tag(group: 0x0008, element: 0x0058),  // Failed SOP Instance UID List (U)
        Tag(group: 0x0008, element: 0x1155),  // Referenced SOP Instance UID (U)
        Tag(group: 0x0008, element: 0x1195),  // Transaction UID (U)
        Tag(group: 0x0008, element: 0x3010),  // Irradiation Event UID (U)
        Tag(group: 0x0018, element: 0x1002),  // Device UID (U)
        Tag(group: 0x0018, element: 0x100B),  // Manufacturer's Device Class UID (U)
        Tag(group: 0x0018, element: 0x2042),  // Target UID (U)
        Tag(group: 0x0020, element: 0x000D),  // Study Instance UID (U)
        Tag(group: 0x0020, element: 0x000E),  // Series Instance UID (U)
        Tag(group: 0x0020, element: 0x0052),  // Frame of Reference UID (U)
        Tag(group: 0x0020, element: 0x0200),  // Synchronization Frame of Reference UID (U)
        Tag(group: 0x0020, element: 0x9161),  // Concatenation UID (U)
        Tag(group: 0x0020, element: 0x9164),  // Dimension Organization UID (U)
        Tag(group: 0x0028, element: 0x1199),  // Palette Color Lookup Table UID (U)
        Tag(group: 0x0028, element: 0x1214),  // Large Palette Color Lookup Table UID (U)
        Tag(group: 0x003A, element: 0x0310),  // Multiplex Group UID (U)
        Tag(group: 0x0040, element: 0x0554),  // Specimen UID (U)
        Tag(group: 0x0040, element: 0x4023),  // Referenced General Purpose Scheduled Procedure Step Transaction UID (U)
        Tag(group: 0x0040, element: 0xA124),  // UID (U)
        Tag(group: 0x0040, element: 0xA171),  // Observation UID (U)
        Tag(group: 0x0040, element: 0xA172),  // Referenced Observation UID (Trial) (U)
        Tag(group: 0x0040, element: 0xA402),  // Observation Subject UID (Trial) (U)
        Tag(group: 0x0040, element: 0xDB0C),  // Template Extension Organization UID (U)
        Tag(group: 0x0040, element: 0xDB0D),  // Template Extension Creator UID (U)
        Tag(group: 0x0062, element: 0x0021),  // Tracking UID (U)
        Tag(group: 0x0064, element: 0x0003),  // Source Frame of Reference UID (U)
        Tag(group: 0x006A, element: 0x0003),  // Annotation Group UID (D)
        Tag(group: 0x0070, element: 0x031A),  // Fiducial UID (U)
        Tag(group: 0x0070, element: 0x1101),  // Presentation Display Collection UID (U)
        Tag(group: 0x0070, element: 0x1102),  // Presentation Sequence Collection UID (U)
        Tag(group: 0x0088, element: 0x0140),  // Storage Media File-set UID (U)
        Tag(group: 0x0400, element: 0x0100),  // Digital Signature UID (U)
        Tag(group: 0x3006, element: 0x0024),  // Referenced Frame of Reference UID (U)
        Tag(group: 0x3006, element: 0x00C2),  // Related Frame of Reference UID (U)
        Tag(group: 0x300A, element: 0x0013),  // Dose Reference UID (U)
        Tag(group: 0x300A, element: 0x0054),  // Table Top Position Alignment UID (U)
        Tag(group: 0x300A, element: 0x0083),  // Referenced Dose Reference UID (U)
        Tag(group: 0x300A, element: 0x0609),  // Treatment Position Group UID (U)
        Tag(group: 0x300A, element: 0x0650),  // Patient Setup UID (U)
        Tag(group: 0x300A, element: 0x0700),  // Treatment Session UID (U)
        Tag(group: 0x300A, element: 0x0785),  // Referenced Treatment Position Group UID (U)
        Tag(group: 0x3010, element: 0x0006),  // Conceptual Volume UID (U)
        Tag(group: 0x3010, element: 0x000B),  // Referenced Conceptual Volume UID (U)
        Tag(group: 0x3010, element: 0x0013),  // Constituent Conceptual Volume UID (U)
        Tag(group: 0x3010, element: 0x0015),  // Source Conceptual Volume UID (U)
        Tag(group: 0x3010, element: 0x0031),  // Referenced Fiducials UID (U)
        Tag(group: 0x3010, element: 0x003B),  // RT Treatment Phase UID (U)
        Tag(group: 0x3010, element: 0x006E),  // Dosimetric Objective UID (U)
        Tag(group: 0x3010, element: 0x006F),  // Referenced Dosimetric Objective UID (U)
    ]

    /// Regenerates instance UIDs in DICOM bytes, returning the new bytes plus the
    /// old→new mapping. Replaces every value of the ``regeneratedUIDTags`` attributes,
    /// at the top level and inside every sequence item (e.g. Referenced SOP Instance UID
    /// (0008,1155) in Referenced Image Sequence, Referenced Frame of Reference UID
    /// (3006,0024)), so references inside the file and — with `maintainRelationships`, which
    /// shares `existingMappings` — between files keep pointing at the right instance
    /// (PS3.15 Table E.1-1 action U). Within one file the same old UID always gets the same
    /// new UID. The File Meta Media Storage SOP Instance UID (0002,0003) follows the new SOP
    /// Instance UID (PS3.10 Table 7.1-1). No file I/O — the caller decides how to persist
    /// (e.g. a sandbox-aware write), so this is shared by the CLI and DICOMStudio.
    public func regenerateData(
        _ inputData: Data,
        root: String?,
        maintainRelationships: Bool,
        existingMappings: inout [String: String]
    ) throws -> (data: Data, mappings: [UIDMapping]) {
        let file = try DICOMFile.read(from: inputData)
        let generator = UIDGenerator(root: root ?? UIDGenerator.defaultRoot)
        var mappings: [UIDMapping] = []
        var fileMappings: [String: String] = [:]
        var shared = existingMappings

        let dataSet = Self.remapUIDs(in: file.dataSet, path: "", newUID: { old in
            if let mapped = fileMappings[old] { return mapped }
            let mapped: String
            if maintainRelationships, let existing = shared[old] {
                mapped = existing
            } else {
                mapped = generator.generate().value
                if maintainRelationships { shared[old] = mapped }
            }
            fileMappings[old] = mapped
            return mapped
        }, report: { tag, path, old, new in
            mappings.append(UIDMapping(
                oldUID: old, newUID: new, tagName: path + Self.tagName(for: tag),
                tagHex: String(format: "%04X,%04X", tag.group, tag.element)))
        })
        existingMappings = shared

        // Use Secondary Capture Image Storage as fallback SOP Class when the original is missing,
        // since it is the most generic storage SOP Class for DICOM files
        let newFile = DICOMFile.create(
            dataSet: dataSet,
            sopClassUID: dataSet.string(for: .sopClassUID) ?? "1.2.840.10008.5.1.4.1.1.7"
        )
        let newData = try newFile.write()
        return (newData, mappings)
    }

    /// Replaces each value of a ``regeneratedUIDTags`` attribute in `dataSet` and, depth
    /// first, in every sequence item; `report` receives (tag, sequence path, old, new) per
    /// replaced value. A value that is a PS3.6 Table A-1 UID is kept.
    static func remapUIDs(
        in dataSet: DataSet, path: String, newUID: (String) -> String,
        report: (Tag, String, String, String) -> Void
    ) -> DataSet {
        var out = dataSet
        for tag in dataSet.tags.sorted() {
            guard let element = dataSet[tag] else { continue }
            if let items = element.sequenceItems {
                let itemPath = path + tagName(for: tag) + ">"
                let remapped = items.map { item -> SequenceItem in
                    let inner = remapUIDs(in: DataSet(elements: item.allElements), path: itemPath,
                                          newUID: newUID, report: report)
                    return SequenceItem(elements: inner.tags.compactMap { inner[$0] })
                }
                out.setSequence(remapped, for: tag)
                continue
            }
            guard element.vr == .UI, regeneratedUIDTags.contains(tag),
                  let values = dataSet.strings(for: tag) else { continue }
            var changed = false
            let replaced = values.map { value -> String in
                let old = value.trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
                guard !old.isEmpty, UIDDictionary.lookup(uid: old) == nil else { return old }
                let new = newUID(old)
                report(tag, path, old, new)
                changed = true
                return new
            }
            if changed {
                out[tag] = DataElement.strings(tag: tag, vr: .UI, values: replaced)
            }
        }
        return out
    }

    /// Regenerates UIDs in a DICOM file on disk (CLI convenience over `regenerateData`).
    @discardableResult
    public func regenerateUIDs(
        inputPath: String,
        outputPath: String?,
        root: String?,
        maintainRelationships: Bool,
        existingMappings: inout [String: String]
    ) throws -> [UIDMapping] {
        guard FileManager.default.fileExists(atPath: inputPath) else {
            throw UIDManagerError.fileNotFound(inputPath)
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: inputPath))
        let (newData, mappings) = try regenerateData(
            data, root: root, maintainRelationships: maintainRelationships, existingMappings: &existingMappings)

        let outPath = outputPath ?? inputPath
        try newData.write(to: URL(fileURLWithPath: outPath))

        return mappings
    }

    /// Dry-run preview for `regenerate`: the lines listing which instance UIDs would be
    /// regenerated, in the canonical format (`  <TagName>: <oldUID> → <new UID>` followed
    /// by a count summary; an attribute inside a sequence item is named by its sequence
    /// path, e.g. `(0008,1140)>(0008,1155)`). Shared by the dicom-uid CLI and DICOMStudio so
    /// both emit byte-identical preview output. The same attributes as ``regenerateData`` —
    /// the UI attributes of PS3.15 Table E.1-1 — are listed; Table A-1 UIDs are left untouched.
    public static func regenerationPreviewLines(for dataSet: DataSet) -> [String] {
        var lines: [String] = []
        _ = remapUIDs(in: dataSet, path: "", newUID: { $0 }, report: { tag, path, old, _ in
            lines.append("  \(path)\(tagName(for: tag)): \(old) \u{2192} <new UID>")
        })
        let count = lines.count
        lines.append(count == 0 ? "  No instance UIDs to regenerate" : "  \(count) UID(s) would be regenerated")
        return lines
    }

    // MARK: - Helpers

    /// Gets a human-readable tag name
    public static func tagName(for tag: Tag) -> String {
        switch tag {
        case .sopInstanceUID: return "SOPInstanceUID"
        case .sopClassUID: return "SOPClassUID"
        case .studyInstanceUID: return "StudyInstanceUID"
        case .seriesInstanceUID: return "SeriesInstanceUID"
        case .instanceCreatorUID: return "InstanceCreatorUID"
        default:
            return String(format: "(%04X,%04X)", tag.group, tag.element)
        }
    }

    /// Gets a human-readable description of a UID type.
    ///
    /// This is the legacy tool wording ("Well-Known UID", "Application Context", and
    /// "Coding Scheme" also for "DICOM UIDs as a Coding Scheme"), kept for the JSON `type` key
    /// of `dicom-uid lookup`, which is deprecated. For the PS3.6 Table A-1 UID Type text use
    /// ``tableA1UIDType(of:)`` (P-UID-TYPE).
    public static func uidTypeDescription(_ type: UIDType) -> String {
        switch type {
        case .transferSyntax: return "Transfer Syntax"
        case .sopClass: return "SOP Class"
        case .metaSOPClass: return "Meta SOP Class"
        case .wellKnown: return "Well-Known UID"
        case .ldap: return "LDAP OID"
        case .codingScheme: return "Coding Scheme"
        case .applicationContext: return "Application Context"
        case .serviceClass: return "Service Class"
        case .applicationHostingModel: return "Application Hosting Model"
        case .mappingResource: return "Mapping Resource"
        case .synchronizationFrameOfReference: return "Synchronization Frame of Reference"
        }
    }

    /// The UID whose PS3.6 2026a Table A-1 UID Type is "DICOM UIDs as a Coding Scheme"
    /// (DICOM UID Registry, DCMUID). `UIDType` folds it into `.codingScheme`.
    public static let dicomUIDsAsCodingSchemeUID = "1.2.840.10008.2.6.1"

    /// The "UID Type" column of PS3.6 2026a Table A-1 for a registry entry, verbatim (12 values:
    /// Transfer Syntax, SOP Class, Meta SOP Class, Well-known SOP Instance, LDAP OID,
    /// Coding Scheme, DICOM UIDs as a Coding Scheme, Application Context Name, Service Class,
    /// Application Hosting Model, Mapping Resource, Synchronization Frame of Reference).
    ///
    /// NEMA-verified: 2026a, checked 2026-10-01 — the 12 UID Type values of the 465 Table A-1 rows
    /// dumped from part06 by script.
    public static func tableA1UIDType(of entry: UIDEntry) -> String {
        tableA1UIDType(entry.type, uid: entry.uid)
    }

    /// The PS3.6 2026a Table A-1 UID Type text for `type`; `uid` distinguishes "DICOM UIDs as a
    /// Coding Scheme" from "Coding Scheme".
    public static func tableA1UIDType(_ type: UIDType, uid: String) -> String {
        switch type {
        case .transferSyntax: return "Transfer Syntax"
        case .sopClass: return "SOP Class"
        case .metaSOPClass: return "Meta SOP Class"
        case .wellKnown: return "Well-known SOP Instance"
        case .ldap: return "LDAP OID"
        case .codingScheme:
            return uid == dicomUIDsAsCodingSchemeUID ? "DICOM UIDs as a Coding Scheme" : "Coding Scheme"
        case .applicationContext: return "Application Context Name"
        case .serviceClass: return "Service Class"
        case .applicationHostingModel: return "Application Hosting Model"
        case .mappingResource: return "Mapping Resource"
        case .synchronizationFrameOfReference: return "Synchronization Frame of Reference"
        }
    }
}

// MARK: - Shared console output (dicom-uid CLI ⇄ Workshop executors)

/// Builds every console line `dicom-uid` prints (generate / validate / lookup /
/// regenerate). The CLI text is canonical and the Workshop executors render
/// identical strings, so the two surfaces cannot drift.
public enum UIDConsole {
    // MARK: generate

    /// Plain listing — one UID per line (trailing newline).
    public static func generatedList(uids: [String]) -> String {
        uids.map { $0 + "\n" }.joined()
    }

    /// `--json` output (pretty-printed, sorted keys, trailing newline).
    public static func generatedJSON(uids: [String]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: uids, options: [.prettyPrinted, .sortedKeys])
        return (String(data: data, encoding: .utf8) ?? "") + "\n"
    }

    // MARK: validate

    /// Text listing for validation results. Registry names appear only under
    /// `--check-registry`. Returns the block and whether every UID was valid.
    public static func validationText(results: [UIDValidationResult], checkRegistry: Bool) -> (text: String, allValid: Bool) {
        var out = ""
        var allValid = true
        for result in results {
            if result.isValid {
                var line = "✅ \(result.uid)"
                if checkRegistry, let name = result.registryName {
                    line += " [\(name)]"
                }
                out += line + "\n"
            } else {
                allValid = false
                out += "❌ \(result.uid)\n"
                for error in result.errors {
                    out += "   - \(error)\n"
                }
            }
        }
        return (out, allValid)
    }

    /// `--json` output for validation results (trailing newline).
    public static func validationJSON(results: [UIDValidationResult]) throws -> String {
        let jsonResults = results.map { result -> [String: Any] in
            var dict: [String: Any] = [
                "uid": result.uid,
                "valid": result.isValid,
            ]
            if !result.errors.isEmpty { dict["errors"] = result.errors }
            if let name = result.registryName { dict["registryName"] = name }
            return dict
        }
        let data = try JSONSerialization.data(withJSONObject: jsonResults, options: [.prettyPrinted, .sortedKeys])
        return (String(data: data, encoding: .utf8) ?? "") + "\n"
    }

    // MARK: lookup

    /// Single-UID hit (three lines).
    public static func lookupEntryText(uid: String, name: String, type: String) -> String {
        "UID:  \(uid)\nName: \(name)\nType: \(type)\n"
    }

    /// Single-UID hit as `--json` (trailing newline).
    public static func lookupEntryJSON(uid: String, name: String, type: String) throws -> String {
        let dict: [String: String] = ["uid": uid, "name": name, "type": type]
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        return (String(data: data, encoding: .utf8) ?? "") + "\n"
    }

    /// Single-UID hit as `--json` with the PS3.6 Table A-1 UID Type in `uidType` (P-UID-TYPE);
    /// `type` keeps the legacy wording (deprecated key).
    public static func lookupEntryJSON(uid: String, name: String, type: String, uidType: String) throws -> String {
        let dict: [String: String] = ["uid": uid, "name": name, "type": type, "uidType": uidType]
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        return (String(data: data, encoding: .utf8) ?? "") + "\n"
    }

    /// The "not found" line of `lookup`: the registry is all of PS3.6 Table A-1 (every UID
    /// Type, not only Transfer Syntaxes and SOP Classes).
    public static func lookupNotFoundLine(uid: String) -> String {
        "UID not found in the DICOM UID registry (PS3.6 Table A-1): \(uid)"
    }

    /// `lookup --type` values: one per UID Type of PS3.6 2026a Table A-1 ("DICOM UIDs as a
    /// Coding Scheme" is folded into coding-scheme by `UIDType`), with the PS3.6 text.
    public static let lookupTypeFilters: [(value: String, type: UIDType, tableA1: String)] = [
        ("transfer-syntax", .transferSyntax, "Transfer Syntax"),
        ("sop-class", .sopClass, "SOP Class"),
        ("meta-sop-class", .metaSOPClass, "Meta SOP Class"),
        ("well-known-sop-instance", .wellKnown, "Well-known SOP Instance"),
        ("ldap-oid", .ldap, "LDAP OID"),
        ("coding-scheme", .codingScheme, "Coding Scheme"),
        ("application-context-name", .applicationContext, "Application Context Name"),
        ("service-class", .serviceClass, "Service Class"),
        ("application-hosting-model", .applicationHostingModel, "Application Hosting Model"),
        ("mapping-resource", .mappingResource, "Mapping Resource"),
        ("synchronization-frame-of-reference", .synchronizationFrameOfReference, "Synchronization Frame of Reference"),
    ]

    /// The registry entries a `--type` value selects (`transfersyntax` / `sopclass` are
    /// accepted spellings too), or nil for an unknown value.
    public static func entries(forTypeFilter value: String) -> [UIDEntry]? {
        let v = value.lowercased()
        let key = ["transfersyntax": "transfer-syntax", "sopclass": "sop-class"][v] ?? v
        guard let type = lookupTypeFilters.first(where: { $0.value == key })?.type else { return nil }
        return UIDDictionary.allEntries.filter { $0.type == type }
    }

    /// The error line for an unknown `--type` value, listing all the valid ones.
    public static func unknownTypeFilterLine(_ filter: String) -> String {
        "Unknown type filter '\(filter)'. Valid types (PS3.6 Table A-1 UID Type): "
            + lookupTypeFilters.map(\.value).joined(separator: ", ")
    }

    public static func noMatchesLine() -> String {
        "No UIDs found matching criteria"
    }

    /// One listing row of `--list-all`/`--search` output.
    public static func listingLine(uid: String, name: String, type: String) -> String {
        "\(uid)  \(name)  (\(type))"
    }

    /// The trailing result count (leading blank line).
    public static func listingSummary(count: Int) -> String {
        "\n\(count) UIDs found"
    }

    /// `--list-all`/`--search` as `--json` (trailing newline).
    public static func listingJSON(entries: [(uid: String, name: String, type: String)]) throws -> String {
        let jsonEntries = entries.map { ["uid": $0.uid, "name": $0.name, "type": $0.type] }
        let data = try JSONSerialization.data(withJSONObject: jsonEntries, options: [.prettyPrinted, .sortedKeys])
        return (String(data: data, encoding: .utf8) ?? "") + "\n"
    }

    /// `--list-all`/`--search` as `--json` with the PS3.6 Table A-1 UID Type in `uidType`
    /// (P-UID-TYPE); `type` keeps the legacy wording (deprecated key).
    public static func listingJSON(entries: [(uid: String, name: String, type: String, uidType: String)]) throws -> String {
        let jsonEntries = entries.map { ["uid": $0.uid, "name": $0.name, "type": $0.type, "uidType": $0.uidType] }
        let data = try JSONSerialization.data(withJSONObject: jsonEntries, options: [.prettyPrinted, .sortedKeys])
        return (String(data: data, encoding: .utf8) ?? "") + "\n"
    }

    // MARK: regenerate

    public static func fileNotFoundWarning(path: String) -> String {
        "Warning: File not found: \(path), skipping"
    }

    public static func processingLine(path: String) -> String {
        "Processing: \(path)"
    }

    /// Verbose per-mapping line.
    public static func mappingLine(tagName: String, oldUID: String, newUID: String) -> String {
        "  \(tagName): \(oldUID) → \(newUID)"
    }

    public static func wroteLine(path: String, count: Int) -> String {
        "Wrote: \(path) (\(count) UIDs regenerated)"
    }

    public static func mapExportedLine(path: String) -> String {
        "UID mapping exported to: \(path)"
    }

    public static func dryRunCompleteLine() -> String {
        "Dry run complete — no files modified."
    }
}

// MARK: - UID root rule (shared by dicom-uid --root and the Workshop; D250)

extension UIDManager {

    /// PS3.5 2026a 9.1 checks for a UID root and the room it leaves for the UIDs
    /// ``DICOMCore/UIDGenerator`` derives from it. The rules: each component is a number of
    /// one or more digits 0-9; the first digit of a component is not zero unless the
    /// component is a single digit; components are separated by "."; a UID has at most 64
    /// characters.
    public enum RootRule {

        /// The longest suffix `UIDGenerator` appends to the root: `.<µs timestamp>.<random 0-999999>`,
        /// plus `.<1|2|3>` for a typed (study / series / instance) UID.
        public static func suffixLength(typed: Bool) -> Int {
            let timestampDigits = String(UInt64(Date().timeIntervalSince1970 * 1_000_000)).count
            return 1 + timestampDigits + 1 + 6 + (typed ? 2 : 0)
        }

        /// Problems with `root` as a UID root: the PS3.5 9.1 syntax rules, and the 64-character
        /// limit of 9.1 for the generated UID. A root too long for the suffix would make the
        /// generator cut the unique part off and return the same UID every time. Empty when the
        /// root is usable.
        public static func problems(root: String, typed: Bool) -> [String] {
            var out: [String] = []
            let components = root.split(separator: ".", omittingEmptySubsequences: false)
            if root.isEmpty || components.contains(where: { $0.isEmpty }) {
                out.append("UID root '\(root)' has an empty component; components are separated by single \".\" characters (PS3.5 9.1)")
            }
            for component in components where !component.isEmpty {
                if !component.allSatisfy({ ("0"..."9").contains($0) }) {
                    out.append("UID root component '\(component)' is not a number; only the digits 0-9 are allowed (PS3.5 9.1)")
                } else if component.count > 1 && component.hasPrefix("0") {
                    out.append("UID root component '\(component)' has a leading zero; only a single-digit component may start with 0 (PS3.5 9.1)")
                }
            }
            let room = DICOMUniqueIdentifier.maximumLength - suffixLength(typed: typed)
            if root.count > room {
                out.append("UID root is \(root.count) characters; generated UIDs add up to \(suffixLength(typed: typed)) more and may not exceed \(DICOMUniqueIdentifier.maximumLength) (PS3.5 9.1), so the root may have at most \(room)")
            }
            return out
        }
    }
}
