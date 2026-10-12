// NEMA-verified: 2026a, checked 2026-10-06 — AnonymizationProfile.basic documented against PS3.15 2026a Table E.1-1 by script: its 14 tags are all Table E.1-1 rows (Basic Profile actions Z, Z/D, X or X/Z/D as listed in the doc comment) but are removed (X) regardless; the other 641 rows of the table (655 in 2026a) are untouched; not PS3.15 Annex E, no behaviour change (D245)
// NEMA-verified: 2026a, checked 2026-10-01 — legacy profiles; de-identification method attributes per PS3.3 2026a C.7.1.1; tag specs take any PS3.6 2026a Table 6-1/7-1 keyword exactly (D163); --keep also exempts from the legacy date shift / UID regeneration (D164)
import Foundation
import DICOMCore
import DICOMDictionary

#if canImport(CryptoKit)
import CryptoKit
#endif

/// Anonymization profile types
public enum AnonymizationProfile {
    /// The legacy "basic" list (dicom-anon `legacy-basic`, DICOMStudio "Basic" /
    /// "HIPAA Safe Harbor"): **not** PS3.15 Annex E (D245, P-ANON-PROFILE).
    ///
    /// It removes exactly 14 attributes, all of them rows of PS3.15 2026a Table E.1-1
    /// (compared by script, 2026-10-06), but it removes (X) every one of them instead of
    /// applying the row's Basic Profile action:
    /// Patient's Name (0010,0010) Z, Patient ID (0010,0020) Z/D, Patient's Birth Date
    /// (0010,0030) Z, Patient's Birth Time (0010,0032) X, Other Patient IDs (0010,1000) X,
    /// Other Patient Names (0010,1001) X, Patient Comments (0010,4000) X, Referring
    /// Physician's Name (0008,0090) Z, Performing Physician's Name (0008,1050) X,
    /// Operators' Name (0008,1070) X/Z/D, Institution Name (0008,0080) X/Z/D, Institution
    /// Address (0008,0081) X, Station Name (0008,1010) X/Z/D, Device Serial Number
    /// (0018,1000) X/Z/D.
    ///
    /// It does not touch the other 641 rows of Table E.1-1, among them Other Patient IDs
    /// Sequence (0010,1002) X, Patient's Address (0010,1040) X, Patient's Telephone Numbers
    /// (0010,2154) X, Patient's Age (0010,1010) X, Patient's Sex (0010,0040) Z, Ethnic Group
    /// (0010,2160) X, Accession Number (0008,0050) Z, Study ID (0020,0010) Z, every date and
    /// time (Study Date (0008,0020) Z, …), every UID (Study Instance UID (0020,000D) U, SOP
    /// Instance UID (0008,0018) U, …) and Private Attributes X; nor does it record Patient
    /// Identity Removed (0012,0062). Use ``ConfidentialityProfile`` (dicom-anon `ps315`)
    /// for the Basic Application Level Confidentiality Profile.
    case basic
    case clinicalTrial
    case research
    case custom([Tag])
    
    var tagsToRemove: Set<Tag> {
        switch self {
        case .basic:
            return basicProfileTags
        case .clinicalTrial:
            return clinicalTrialProfileTags
        case .research:
            return researchProfileTags
        case .custom(let tags):
            return Set(tags)
        }
    }
    
    private var basicProfileTags: Set<Tag> {
        Set([
            .patientName,
            .patientID,
            .patientBirthDate,
            .patientBirthTime,
            .otherPatientIDs,
            .otherPatientNames,
            .patientComments,
            .referringPhysicianName,
            .performingPhysicianName,
            .operatorsName,
            .institutionName,
            .institutionAddress,
            .stationName,
            .deviceSerialNumber
        ])
    }
    
    private var clinicalTrialProfileTags: Set<Tag> {
        basicProfileTags.union([
            .studyDate,
            .seriesDate,
            .acquisitionDate,
            .contentDate,
            .studyTime,
            .seriesTime,
            .acquisitionTime,
            .contentTime
        ])
    }
    
    private var researchProfileTags: Set<Tag> {
        Set([
            .patientName,
            .patientID,
            .patientBirthDate
        ])
    }
}

/// Anonymization action for a tag
public enum AnonymizationAction {
    case remove
    case replaceWithEmpty
    case replaceWithDummy(String)
    case hash
    case shiftDate(days: Int)
    case regenerateUID
}

/// Result of anonymization
public struct AnonymizationResult: Sendable {
    public let filePath: String
    public let success: Bool
    public let changedTags: [Tag]
    public let warnings: [String]

    public init(filePath: String, success: Bool, changedTags: [Tag], warnings: [String]) {
        self.filePath = filePath
        self.success = success
        self.changedTags = changedTags
        self.warnings = warnings
    }
}

/// Audit log entry
public struct AuditLogEntry {
    public let timestamp: Date
    public let filePath: String
    public let action: String
    public let tag: Tag
    public let originalValue: String?
    public let newValue: String?
    public let note: String?

    public init(timestamp: Date, filePath: String, action: String, tag: Tag, originalValue: String?, newValue: String?) {
        self.timestamp = timestamp
        self.filePath = filePath
        self.action = action
        self.tag = tag
        self.originalValue = originalValue
        self.newValue = newValue
        self.note = nil
    }
    public init(timestamp: Date, filePath: String, action: String, tag: Tag, note: String? = nil) {
        self.timestamp = timestamp
        self.filePath = filePath
        self.action = action
        self.tag = tag
        self.note = note
        self.originalValue = nil
        self.newValue = nil
    }

}

/// Main anonymizer class
public class Anonymizer {
    let profile: AnonymizationProfile
    let shiftDates: Int?
    let regenerateUIDs: Bool
    let preserveTags: Set<Tag>
    let customActions: [Tag: AnonymizationAction]
    
    private var dateOffset: Int?
    private var uidMapping: [String: String] = [:]
    private var auditLog: [AuditLogEntry] = []
    
    public init(
        profile: AnonymizationProfile,
        shiftDates: Int? = nil,
        regenerateUIDs: Bool = true,
        preserveTags: Set<Tag> = [],
        customActions: [Tag: AnonymizationAction] = [:]
    ) {
        self.profile = profile
        self.shiftDates = shiftDates
        self.regenerateUIDs = regenerateUIDs
        self.preserveTags = preserveTags
        self.customActions = customActions
        
        if let shift = shiftDates {
            self.dateOffset = shift
        }
    }
    
    public func anonymize(file: DICOMFile, filePath: String) throws -> (DICOMFile, AnonymizationResult) {
        var newDataSet = file.dataSet
        var changedTags: [Tag] = []
        var warnings: [String] = []
        
        // Process every tag the profile removes PLUS any tag named explicitly via
        // customActions (--remove / --replace), minus preserved (--keep) tags.
        // Unioning customActions.keys is the shared-engine home of the F19 fix:
        // without it, `--remove`/`--replace` only affected tags already in the
        // profile set, silently dropping custom actions on any other tag.
        let tagsToProcess = profile.tagsToRemove.union(customActions.keys).subtracting(preserveTags)
        
        for tag in tagsToProcess {
            guard let element = newDataSet[tag] else { continue }
            
            let action = customActions[tag] ?? defaultAction(for: tag)
            
            switch action {
            case .remove:
                let originalValue = extractValue(from: element)
                newDataSet.remove(tag: tag)
                changedTags.append(tag)
                logChange(filePath: filePath, action: "remove", tag: tag, originalValue: originalValue, newValue: nil)
                
            case .replaceWithEmpty:
                let originalValue = extractValue(from: element)
                replaceWithEmpty(tag: tag, vr: element.vr, in: &newDataSet)
                changedTags.append(tag)
                logChange(filePath: filePath, action: "replace_empty", tag: tag, originalValue: originalValue, newValue: "")
                
            case .replaceWithDummy(let dummy):
                let originalValue = extractValue(from: element)
                replaceWithDummy(tag: tag, vr: element.vr, value: dummy, in: &newDataSet)
                changedTags.append(tag)
                logChange(filePath: filePath, action: "replace_dummy", tag: tag, originalValue: originalValue, newValue: dummy)
                
            case .hash:
                if let originalValue = extractValue(from: element) {
                    let hashed = hashValue(originalValue)
                    replaceWithDummy(tag: tag, vr: element.vr, value: hashed, in: &newDataSet)
                    changedTags.append(tag)
                    logChange(filePath: filePath, action: "hash", tag: tag, originalValue: originalValue, newValue: hashed)
                }
                
            case .shiftDate(let days):
                if let originalDate = newDataSet.string(for: tag) {
                    if let shifted = shiftDate(originalDate, byDays: days) {
                        newDataSet.setString(shifted, for: tag, vr: element.vr)
                        changedTags.append(tag)
                        logChange(filePath: filePath, action: "shift_date", tag: tag, originalValue: originalDate, newValue: shifted)
                    }
                }
                
            case .regenerateUID:
                if let originalUID = newDataSet.string(for: tag) {
                    let newUID = getMappedUID(originalUID)
                    newDataSet.setString(newUID, for: tag, vr: element.vr)
                    changedTags.append(tag)
                    logChange(filePath: filePath, action: "regenerate_uid", tag: tag, originalValue: originalUID, newValue: newUID)
                }
            }
        }
        
        // Handle date shifting if specified
        if let offset = dateOffset {
            shiftAllDates(in: &newDataSet, byDays: offset, changedTags: &changedTags, filePath: filePath)
        }
        
        // Regenerate UIDs if specified
        if regenerateUIDs {
            regenerateAllUIDs(in: &newDataSet, changedTags: &changedTags, filePath: filePath)
        }
        
        // Scan for potential PHI leaks in private tags
        let phiWarnings = scanForPHILeaks(in: newDataSet)
        warnings.append(contentsOf: phiWarnings)
        
        // PS3.10 2026a Table 7.1-1 / PS3.15 2026a Table E.1-1 (0002,0003) U: the File Meta
        // Media Storage UIDs follow the (possibly regenerated) (0008,0016) / (0008,0018) (D162).
        let newFile = DICOMFile(fileMetaInformation: file.fileMetaInformation, dataSet: newDataSet)
            .synchronizingMediaStorageUIDs()
        let result = AnonymizationResult(
            filePath: filePath,
            success: true,
            changedTags: changedTags,
            warnings: warnings
        )
        
        return (newFile, result)
    }
    
    private func defaultAction(for tag: Tag) -> AnonymizationAction {
        if tag == .patientName {
            return .replaceWithDummy("ANONYMOUS")
        } else if tag == .patientID {
            return .hash
        } else if isDateTag(tag) {
            return shiftDates != nil ? .shiftDate(days: shiftDates!) : .remove
        } else if isUIDTag(tag) {
            return regenerateUIDs ? .regenerateUID : .remove
        } else {
            return .remove
        }
    }
    
    private func isDateTag(_ tag: Tag) -> Bool {
        [.studyDate, .seriesDate, .acquisitionDate, .contentDate, .patientBirthDate].contains(tag)
    }
    
    private func isUIDTag(_ tag: Tag) -> Bool {
        [.studyInstanceUID, .seriesInstanceUID, .sopInstanceUID].contains(tag)
    }
    
    private func extractValue(from element: DataElement) -> String? {
        if let str = element.stringValue {
            return str
        }
        // Convert to a simple string representation
        return "\(element.tag)"
    }
    
    private func replaceWithEmpty(tag: Tag, vr: VR, in dataSet: inout DataSet) {
        dataSet.setString("", for: tag, vr: vr)
    }
    
    private func replaceWithDummy(tag: Tag, vr: VR, value: String, in dataSet: inout DataSet) {
        dataSet.setString(value, for: tag, vr: vr)
    }
    
    private func hashValue(_ value: String) -> String {
        #if canImport(CryptoKit)
        let data = Data(value.utf8)
        let hash = SHA256.hash(data: data)
        // Use 32 hex characters (128 bits) for pseudonymization.
        // This provides 2^128 possible values, significantly reducing collision
        // probability for large medical datasets while keeping values human-readable
        // in DICOM tags.
        let fullHex = hash.map { String(format: "%02x", $0) }.joined().uppercased()
        return String(fullHex.prefix(32))
        #else
        // Fallback to a deterministic 128-bit hex representation for platforms
        // without CryptoKit by combining two 64-bit hash values.
        let h1 = UInt64(bitPattern: Int64(value.hashValue))
        let reversedValue = String(value.reversed())
        let h2 = UInt64(bitPattern: Int64(reversedValue.hashValue))
        return String(format: "%016llX%016llX", h1, h2)
        #endif
    }
    
    private func shiftDate(_ dateString: String, byDays days: Int) -> String? {
        let formatter = DateFormatter()
        
        // Try DICOM date format (YYYYMMDD)
        formatter.dateFormat = "yyyyMMdd"
        if let date = formatter.date(from: dateString) {
            if let shifted = Calendar.current.date(byAdding: .day, value: days, to: date) {
                return formatter.string(from: shifted)
            }
        }
        
        return nil
    }
    
    private func shiftAllDates(in dataSet: inout DataSet, byDays days: Int, changedTags: inout [Tag], filePath: String) {
        let dateTags: [Tag] = [.studyDate, .seriesDate, .acquisitionDate, .contentDate]
        
        // --keep (preserveTags) wins over the date shift too (D164).
        for tag in dateTags where !preserveTags.contains(tag) {
            if let originalDate = dataSet.string(for: tag), !changedTags.contains(tag) {
                if let shifted = shiftDate(originalDate, byDays: days) {
                    if let element = dataSet[tag] {
                        dataSet.setString(shifted, for: tag, vr: element.vr)
                        changedTags.append(tag)
                        logChange(filePath: filePath, action: "shift_date", tag: tag, originalValue: originalDate, newValue: shifted)
                    }
                }
            }
        }
    }
    
    private func regenerateAllUIDs(in dataSet: inout DataSet, changedTags: inout [Tag], filePath: String) {
        let uidTags: [Tag] = [.studyInstanceUID, .seriesInstanceUID, .sopInstanceUID]
        
        for tag in uidTags where !preserveTags.contains(tag) {  // --keep wins (D164)
            if let originalUID = dataSet.string(for: tag), !changedTags.contains(tag) {
                let newUID = getMappedUID(originalUID)
                if let element = dataSet[tag] {
                    dataSet.setString(newUID, for: tag, vr: element.vr)
                    changedTags.append(tag)
                    logChange(filePath: filePath, action: "regenerate_uid", tag: tag, originalValue: originalUID, newValue: newUID)
                }
            }
        }
    }
    
    private func getMappedUID(_ originalUID: String) -> String {
        if let mapped = uidMapping[originalUID] {
            return mapped
        }
        
        let newUID = UIDGenerator.generateUID().value
        uidMapping[originalUID] = newUID
        return newUID
    }
    
    private func scanForPHILeaks(in dataSet: DataSet) -> [String] {
        var warnings: [String] = []
        
        for tag in dataSet.tags {
            // Check private tags
            if tag.isPrivate {
                if let element = dataSet[tag], let value = extractValue(from: element) {
                    if containsSuspiciousPHI(value) {
                        warnings.append("Potential PHI detected in private tag \(tag); value omitted to protect privacy.")
                    }
                }
            }
        }
        
        return warnings
    }
    
    private func containsSuspiciousPHI(_ value: String) -> Bool {
        let patterns = [
            "\\b[A-Z][a-z]+\\s[A-Z][a-z]+\\b", // Name pattern
            "\\b\\d{3}-\\d{2}-\\d{4}\\b", // SSN pattern
            "\\b\\d{10}\\b", // Phone number pattern
            "\\b\\d{1,2}/\\d{1,2}/\\d{4}\\b" // Date pattern
        ]
        
        for pattern in patterns {
            if let _ = value.range(of: pattern, options: .regularExpression) {
                return true
            }
        }
        
        return false
    }
    
    private func logChange(filePath: String, action: String, tag: Tag, originalValue: String?, newValue: String?) {
        let entry = AuditLogEntry(
            timestamp: Date(),
            filePath: filePath,
            action: action,
            tag: tag,
            originalValue: originalValue,
            newValue: newValue
        )
        auditLog.append(entry)
    }
    
    /// De-identifies a file with the PS3.15 Annex E Basic Application Level
    /// Confidentiality Profile — the standards-grounded path.
    ///
    /// Unlike ``anonymize(file:filePath:)`` (which applies the legacy fixed tag lists),
    /// this walks Table E.1-1 action codes, recurses into every sequence item, sweeps by
    /// VR (all residual PN removed, all instance UIDs consistently regenerated, all
    /// private tags removed), and records the de-identification method attributes.
    ///
    /// - Parameters:
    ///   - file: The source file.
    ///   - options: PS3.15 E.3 retention options; default is the strict Basic Profile.
    ///   - uidMap: Optional shared UID map for cross-file consistency within a study.
    /// - Returns: The de-identified file, a result summary, and the (possibly extended)
    ///   UID map for reuse on sibling files.
    public func deidentify(
        file: DICOMFile,
        options: ConfidentialityProfile.Options = .basic,
        uidMap: [String: String] = [:]
    ) -> (DICOMFile, AnonymizationResult, [String: String]) {
        var engine = ConfidentialityEngine(options: options, uidMap: uidMap)
        // Use the residual-PHI-reporting pass: pixels are out of scope for this engine,
        // so burned-in annotation / overlay planes must reach the caller as warnings
        // rather than being silently certified as de-identified.
        var (scrubbed, changed, warnings) = engine.deidentifyReportingResidualPHI(file.dataSet)
        AnonCLI.applyCustomActions(customActions, source: file.dataSet, to: &scrubbed)
        // PS3.10 2026a Table 7.1-1 / PS3.15 2026a Table E.1-1 (0002,0003) U: the File Meta
        // Media Storage UIDs follow the regenerated (0008,0016) / (0008,0018) (D162).
        let newFile = DICOMFile(fileMetaInformation: file.fileMetaInformation, dataSet: scrubbed)
            .synchronizingMediaStorageUIDs()
        let result = AnonymizationResult(
            filePath: "", success: true, changedTags: changed, warnings: warnings)
        return (newFile, result, engine.uidMap)
    }

    public private(set) var options: ConfidentialityProfile.Options = .basic
    private var workflowUIDMap: [String: String] = [:]
    private var usesWorkflow = false

    public convenience init(options: ConfidentialityProfile.Options = .basic, customActions: [Tag: AnonymizationAction] = [:]) {
        self.init(profile: .basic, customActions: customActions)
        self.options = options
        self.usesWorkflow = true
    }

    /// De-identifies one file's data set, extending the run-wide UID map and audit log.
    ///
    /// Pixels are out of scope here (the pixel pass runs first), so a declared
    /// burned-in annotation or overlay plane surfaces as a warning and (0012,0062) NO
    /// rather than being silently certified as removed.
    public func deidentify(file: DICOMFile, filePath: String) -> (DICOMFile, AnonymizationResult) {
        var engine = ConfidentialityEngine(options: options, uidMap: workflowUIDMap)
        var (scrubbed, changed, warnings) = engine.deidentifyReportingResidualPHI(file.dataSet)
        AnonCLI.applyCustomActions(customActions, source: file.dataSet, to: &scrubbed)
        for (tag, action) in customActions where file.dataSet[tag] != nil {
            if !changed.contains(tag) { changed.append(tag) }
            let name: String
            switch action {
            case .remove: name = "X remove"
            case .replaceWithDummy: name = "D replace"
            default: continue
            }
            auditLog.append(AuditLogEntry(timestamp: Date(), filePath: filePath, action: name, tag: tag))
        }
        workflowUIDMap = engine.uidMap
        for change in engine.changes {
            auditLog.append(AuditLogEntry(
                timestamp: Date(), filePath: filePath,
                action: Self.actionName(change.action), tag: change.tag))
        }
        let newFile = DICOMFile(fileMetaInformation: file.fileMetaInformation, dataSet: scrubbed).synchronizingMediaStorageUIDs()
        return (newFile, AnonymizationResult(
            filePath: filePath, success: true, changedTags: changed, warnings: warnings))
    }

    /// Previews the header pass and reserves UID mappings for the subsequent write.
    /// Used to learn the engine's own replacement values for `--redact-style replace`.
    public func preview(file: DICOMFile) -> DICOMFile {
        var engine = ConfidentialityEngine(options: options, uidMap: workflowUIDMap)
        var (scrubbed, _) = engine.deidentify(file.dataSet)
        AnonCLI.applyCustomActions(customActions, source: file.dataSet, to: &scrubbed)
        workflowUIDMap = engine.uidMap
        return DICOMFile(fileMetaInformation: file.fileMetaInformation, dataSet: scrubbed).synchronizingMediaStorageUIDs()
    }

    /// Table E.1-1 action code names as they appear in the audit log.
    static func actionName(_ action: ConfidentialityProfile.Action) -> String {
        switch action {
        case .remove, .removePreferred: return "X remove"
        case .zero:                     return "Z zero"
        case .zeroOrDummy:              return "Z/D zero-or-shift"
        case .replaceDummy:             return "D dummy"
        case .clean:                    return "C clean"
        case .replaceUID:               return "U replace-uid"
        case .keep:                     return "K keep"
        }
    }

    /// Records pixel-work audit lines (PHI-safe — callers pass
    /// `PixelCleaningWorkflow.Report.auditLines`, never raw OCR strings).
    public func recordPixelAudit(filePath: String, lines: [String]) {
        for line in lines {
            auditLog.append(AuditLogEntry(
                timestamp: Date(), filePath: filePath, action: "pixel-data",
                tag: .pixelData, note: line))
        }
    }

    public func getAuditLog() -> [AuditLogEntry] {
        return auditLog
    }
    
    public func writeAuditLog(to url: URL) throws {
        let dateFormatter = ISO8601DateFormatter()
        var logText = "DICOM Anonymization Audit Log\n"
        logText += "Generated: \(dateFormatter.string(from: Date()))\n"
        if usesWorkflow {
            logText += "Method: \(options.methodCodes.map(\.meaning).joined(separator: "; "))\n\n"
        }
        
        // Sort by file then tag so the audit log is deterministic (the rules are applied
        // in an unordered fashion, so the raw collection order varies run-to-run).
        let sorted = auditLog.sorted {
            ($0.filePath, $0.tag.group, $0.tag.element) < ($1.filePath, $1.tag.group, $1.tag.element)
        }
        for entry in sorted {
            logText += "[\(dateFormatter.string(from: entry.timestamp))] "
            logText += "\(entry.filePath) - \(entry.action) - \(entry.tag)\n"
            if let note = entry.note { logText += "  \(note)\n" }
            logText += "\n"
        }
        
        try logText.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Flexible tag parsing (shared by dicom-anon CLI and the Workshop executor)

extension Anonymizer {
    /// Parses a user-supplied tag spec: hex `(0010,0010)` / `0010,0010` / `00100010`,
    /// or a PS3.6 2026a Table 6-1/7-1 keyword, matched exactly (e.g. `PatientAge`). Before
    /// D163 only 11 hard-coded keywords were known.
    /// Returns nil when the spec is unparseable (callers decide how to error).
    public static func parseFlexibleTag(_ string: String) -> Tag? {
        let clean = string
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .trimmingCharacters(in: .whitespaces)
        if clean.count == 8, let value = UInt32(clean, radix: 16) {
            let group = UInt16((value >> 16) & 0xFFFF)
            let element = UInt16(value & 0xFFFF)
            return Tag(group: group, element: element)
        }
        return DataElementDictionary.lookup(keyword: string.trimmingCharacters(in: .whitespaces))?.tag
    }
}

// MARK: - Shared console output (dicom-anon CLI ⇄ Workshop Security executor)

/// Builds every console line `dicom-anon` prints. The CLI text is canonical and the
/// Workshop executor renders the identical strings, so the two surfaces cannot drift.
public enum AnonConsole {
    /// Per-file verbose line in directory mode (success).
    public static func fileSuccessLine(relativePath: String) -> String {
        "✓ \(relativePath)"
    }

    /// Per-file verbose line in directory mode (failure).
    public static func fileFailureLine(relativePath: String, message: String) -> String {
        "✗ \(relativePath): \(message)"
    }

    /// Verbose confirmation after the audit log is written.
    public static func auditLogLine(path: String) -> String {
        "Audit log written to: \(path)"
    }

    /// The operator's Burned In Annotation policy took the file past the pixel pass:
    /// the declaration was trusted, nothing was inspected. Console (verbose) and audit.
    public static let burnedInAnnotationTrustedNote =
        "Pixel data: Burned In Annotation (0028,0301) = NO — trusted; pixels were not inspected or modified."

    /// Verbose report of a pixel-redaction pass. States the basis for the region
    /// choice, not just the rectangle — an operator has to be able to judge whether
    /// the region was the right one, since no test can verify that for them.
    public static func pixelRedactionLines(outcome: PixelRedactor.Outcome) -> String {
        var out = "Cleaned pixel data (\(outcome.basis.rawValue)): \(outcome.note)\n"
        let fallback = Set(outcome.labelFallbackRegions)
        for r in outcome.regions {
            let verb: String
            switch outcome.style {
            case .blank: verb = "blanked"
            case .label(let text):
                verb = fallback.contains(r)
                    ? "blanked (too small for label \"\(text)\" — blank only)"
                    : "blanked + labelled \"\(text)\""
            case .replace(let fallbackLabel):
                if let value = outcome.replacements[r] {
                    verb = "blanked + replaced with header value \"\(value)\""
                } else if fallback.contains(r) {
                    verb = "blanked (\(outcome.replacementFallbackNotes[r] ?? "too small") — blank only)"
                } else {
                    verb = "blanked + labelled \"\(fallbackLabel)\" (\(outcome.replacementFallbackNotes[r] ?? "no replacement"))"
                }
            }
            out += "  \(verb) (\(r.x),\(r.y)) \(r.width)x\(r.height)"
            out += outcome.frameCount > 1 ? " on all \(outcome.frameCount) frames\n" : "\n"
        }
        if outcome.removedIconImage {
            out += "  removed Icon Image Sequence (derived before cleaning)\n"
        }
        if outcome.removedOverlays {
            out += "  removed overlay plane data (burned in by renderers)\n"
        }
        out += "  recorded DCM 113101 Clean Pixel Data Option; Burned In Annotation = NO\n"
        out += "  ⚠️  Verify visually before release — region selection is not verifiable by test.\n"
        return out
    }

    /// `--recompress` console lines: what was re-encoded to, and every caveat.
    public static func recompressionLines(_ r: PixelCleaningWorkflow.Recompression) -> String {
        var out: String
        if r.transferSyntaxUID == r.sourceTransferSyntaxUID {
            out = "Re-encoded to source syntax \(r.transferSyntaxUID) (\(r.codec), \(r.lossy ? "lossy" : "lossless"))\n"
        } else {
            out = "Re-encoded to \(r.transferSyntaxUID) (\(r.codec), \(r.lossy ? "lossy" : "lossless")); source was \(r.sourceTransferSyntaxUID)\n"
        }
        for n in r.notes { out += "  ⚠️  \(n)\n" }
        out += "  verified: redacted regions still blank after the codec round-trip\n"
        return out
    }

    /// One-line OCR summary. Reports what was done — never that the image is clean.
    public static func textDetectionLine(report: PixelCleaningWorkflow.Report) -> String {
        let n = report.detections.count
        let selected: Int
        if let plan = report.plan, case .redact(let regions, _) = plan.decision {
            selected = report.detections.filter { regions.contains($0.region) }.count
        } else {
            selected = 0
        }
        let kept = report.verdicts.filter { !$0.isRedact }.count
        let frames = report.scannedFrames.count
        var line = "OCR: \(n) candidate region\(n == 1 ? "" : "s"); \(selected) selected for redaction"
        if kept > 0 {
            let why = report.mode == .header ? "no header match" : "allowlisted clinical text"
            line += "; \(kept) kept (\(why)"
            // A keep verdict never shrinks another source's region: say how many of the
            // kept regions are blanked anyway, so "kept" is never read as "survives".
            let buried = kept - report.keptAndSurviving.count
            if buried > 0 { line += "; \(buried) of them inside blanked regions anyway" }
            line += ")"
        }
        line += " across \(frames) sampled frame\(frames == 1 ? "" : "s").\n"
        return line
    }

    /// The `--dry-run` region table (§7). Recognized text is shown on the console
    /// (`showText`) but must be passed as `false` for anything persisted.
    public static func pixelPlanTable(report: PixelCleaningWorkflow.Report, showText: Bool) -> String {
        var out = "Pixel redaction plan:\n"
        let indexed = Array(zip(report.detections, report.verdicts))
        let byFrame = Dictionary(grouping: indexed, by: { $0.0.frameIndex })
        let redacted: Set<PixelRedactionPlan.Region>
        if let plan = report.plan, case .redact(let regions, _) = plan.decision {
            redacted = Set(regions)
        } else {
            redacted = []
        }
        for frame in byFrame.keys.sorted() {
            out += "Frame \(frame):\n"
            for (d, v) in byFrame[frame]! {
                let verdict: String
                if v.isRedact {
                    verdict = redacted.contains(d.region) ? "redact" : "detected"
                } else {
                    verdict = "keep"
                }
                let reason = (v.isRedact && !redacted.contains(d.region))
                    ? "\(v.reason) — cleaning not requested" : v.reason
                let text = showText ? d.text : d.redactedForAudit
                out += "  OCR  rect=\(d.region.x),\(d.region.y),\(d.region.width),\(d.region.height)"
                    + "  verdict=\(verdict)  reason=\(reason)  conf=\(String(format: "%.2f", d.confidence))"
                    + "  text=\"\(text)\"\n"
            }
        }
        out += "Final:\n"
        guard let plan = report.plan else {
            out += "  detection only — no cleaning requested\n"
            out += "  Pixel modification: NO\n"
            return out
        }
        switch plan.decision {
        case .redact(let regions, _):
            let parts = plan.sources.map { source -> String in
                let n = source.regions.count
                let label: String
                switch source.basis {
                case .explicit: label = "explicit"
                case .keepRegionInversion: label = "keep-region"
                case .deviceTemplate: label = "template"
                case .textDetection: label = "OCR"
                }
                return "\(n) \(label) region\(n == 1 ? "" : "s")"
            }
            out += "  \(parts.joined(separator: " + ")) = \(regions.count) unioned region\(regions.count == 1 ? "" : "s")\n"
            for r in regions {
                out += "    (\(r.x),\(r.y)) \(r.width)x\(r.height)\n"
            }
            out += "  Frames affected: all (\(report.frameCount))\n"
            out += "  Pixel modification: YES\n"
        case .nothingToDo:
            out += "  nothing declared, nothing detected — no pixel work\n"
            out += "  Pixel modification: NO\n"
        case .unresolved(let reason):
            out += "  UNRESOLVED: \(reason)\n"
            out += "  Pixel modification: REFUSED\n"
        }
        return out
    }

    /// The end-of-run summary block (leading blank line, every line newline-terminated).
    /// The "Modified tags" section appears whenever verbose ran over at least one file,
    /// even with zero modified tags — matching the CLI.
    public static func summary(
        totalFiles: Int,
        successful: Int,
        failed: Int,
        dryRun: Bool,
        warnings: [String],
        modifiedTags: Set<String>,
        verbose: Bool
    ) -> String {
        var out = "\nAnonymization Summary:\n"
        out += "  Total files: \(totalFiles)\n"
        out += "  Successful: \(successful)\n"
        out += "  Failed: \(failed)\n"
        if dryRun { out += "  (DRY RUN - no files modified)\n" }
        if !warnings.isEmpty {
            out += "\nWarnings:\n"
            for warning in warnings.prefix(10) { out += "  ⚠️  \(warning)\n" }
            if warnings.count > 10 { out += "  ... and \(warnings.count - 10) more warnings\n" }
        }
        if verbose && totalFiles > 0 {
            out += "\nModified tags (\(modifiedTags.count)):\n"
            for tag in modifiedTags.sorted().prefix(20) { out += "  - \(tag)\n" }
        }
        return out
    }
}
