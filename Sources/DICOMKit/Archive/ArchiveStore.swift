// NEMA-verified: 2026a, checked 2026-10-01 — query/export key matching against PS3.4 2026a C.2.2.2 (Single Value C.2.2.2.1 case-sensitive except PN, List of UID C.2.2.2.2, Universal C.2.2.2.3, Wild Card C.2.2.2.4, DA Range C.2.2.2.5.1); the JSON index (archive_index.json) follows the Patient/Study/Series/Instance hierarchy of PS3.4 Tables C.6-1..C.6-4 with patients keyed on Patient ID + Issuer of Patient ID (0010,0021); study modality is Modalities in Study (0008,0061, C.6-5) from all series; 15 printed labels are PS3.6 2026a Table 6-1 names and SOP Classes are named from PS3.6 Table A-1
// NEMA-verified: 2026a, checked 2026-10-06 — studyDateKeyWarning (lifted from dicom-archive QueryKeys, D249) warns only for a key that is neither the DA value of PS3.5 2026a Table 6.2-1 nor one of the three DA range forms of PS3.4 2026a C.2.2.2.5.1 ("<date1> - <date2>", "- <date1>", "<date1> -"; clause read by script), the forms dateRange(_:) accepts
import Foundation
import DICOMCore
import DICOMDictionary

// Shared local-archive engine for the `dicom-archive` CLI and DICOMStudio. The
// index model, helpers, and every operation (init/import/query/list/export/
// check/stats) live here and RETURN their rendered output as a string (never
// printing) so the two adapters run identical code and cannot drift.

// MARK: - Errors

public enum ArchiveError: Error, LocalizedError {
    case archiveNotFound(String)
    case archiveExists(String)
    case noFilesToImport
    case invalidFormat(String)
    case cannotEnumerate(String)
    case noExportFilter

    public var errorDescription: String? {
        switch self {
        case .archiveNotFound(let path): return "No archive found at: \(path) (missing archive_index.json)"
        case .archiveExists(let path): return "Archive already exists at: \(path). Use --force to overwrite."
        case .noFilesToImport: return "No files found to import"
        case .invalidFormat(let msg): return msg
        case .cannotEnumerate(let dir): return "Cannot enumerate directory: \(dir)"
        case .noExportFilter: return "Specify at least one filter: --study-uid, --series-uid, or --patient-id"
        }
    }
}

// MARK: - Archive Index Types

public struct ArchiveInstance: Codable, Sendable {
    public let sopInstanceUID: String
    public let sopClassUID: String
    public let filePath: String
    public let fileSize: Int64
    public let importDate: String
    public let instanceNumber: String?
}

public struct ArchiveSeries: Codable, Sendable {
    public let seriesInstanceUID: String
    public let modality: String
    public let seriesDescription: String?
    public let seriesNumber: String?
    public var instances: [ArchiveInstance]
}

/// One study of the archive index.
///
/// `modality` is the Modality of the first instance imported (deprecated as a study-level key,
/// P-ARCHIVE-1). The study level carries Modalities in Study (0008,0061, CS 1-n; PS3.4 2026a
/// Tables C.6-2 / C.6-5): ``modalitiesInStudy``, written to JSON as `ModalitiesInStudy` next to
/// `modality`. Decoding reads only the stored keys, so indexes written before 2026-10-01 load.
public struct ArchiveStudy: Codable, Sendable {
    public let studyInstanceUID: String
    public let studyDate: String?
    public let studyDescription: String?
    /// The Modality of the first instance imported, kept for the index's `modality` key.
    let firstInstanceModality: String?
    public let accessionNumber: String?
    public var series: [ArchiveSeries]

    /// The Modality (0008,0060) of the first instance imported into the study — not a
    /// study-level attribute. A study's modalities are ``modalitiesInStudy``.
    @available(*, deprecated, message: "The first imported instance's Modality; use modalitiesInStudy (Modalities in Study (0008,0061), PS3.4 2026a Table C.6-5)")
    public var modality: String? { firstInstanceModality }

    init(studyInstanceUID: String, studyDate: String?, studyDescription: String?, modality: String?,
         accessionNumber: String?, series: [ArchiveSeries]) {
        self.studyInstanceUID = studyInstanceUID
        self.studyDate = studyDate
        self.studyDescription = studyDescription
        self.firstInstanceModality = modality
        self.accessionNumber = accessionNumber
        self.series = series
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        studyInstanceUID = try c.decode(String.self, forKey: .studyInstanceUID)
        studyDate = try c.decodeIfPresent(String.self, forKey: .studyDate)
        studyDescription = try c.decodeIfPresent(String.self, forKey: .studyDescription)
        firstInstanceModality = try c.decodeIfPresent(String.self, forKey: .modality)
        accessionNumber = try c.decodeIfPresent(String.self, forKey: .accessionNumber)
        series = try c.decode([ArchiveSeries].self, forKey: .series)
    }

    /// Modalities in Study (0008,0061): the distinct Modality values of the study's series, in
    /// series order, empty values left out.
    public var modalitiesInStudy: [String] {
        var seen: [String] = []
        for m in series.map(\.modality) where !m.isEmpty && !seen.contains(m) { seen.append(m) }
        return seen
    }

    enum CodingKeys: String, CodingKey {
        case studyInstanceUID, studyDate, studyDescription, modality, accessionNumber, series
    }

    enum KeywordKeys: String, CodingKey { case ModalitiesInStudy }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(studyInstanceUID, forKey: .studyInstanceUID)
        try c.encodeIfPresent(studyDate, forKey: .studyDate)
        try c.encodeIfPresent(studyDescription, forKey: .studyDescription)
        try c.encodeIfPresent(firstInstanceModality, forKey: .modality)
        try c.encodeIfPresent(accessionNumber, forKey: .accessionNumber)
        try c.encode(series, forKey: .series)
        var k = encoder.container(keyedBy: KeywordKeys.self)
        try k.encode(modalitiesInStudy, forKey: .ModalitiesInStudy)
    }
}

/// One patient of the archive index, keyed on Patient ID (0010,0020) together with Issuer of
/// Patient ID (0010,0021) (PS3.4 2026a Tables C.6-1 / C.6-5; PS3.3 Table 10-18). Files whose
/// Patient ID is empty or absent (Type 2, PS3.3 Table C.7-1) are additionally keyed on
/// Patient's Name, so unrelated unidentified patients are not merged into one entry.
public struct ArchivePatient: Codable, Sendable {
    public let patientName: String
    public let patientID: String
    /// Issuer of Patient ID (0010,0021); `nil` when the files carry none (and in indexes
    /// written before 2026-10-01).
    public let issuerOfPatientID: String?
    public var studies: [ArchiveStudy]

    init(patientName: String, patientID: String, issuerOfPatientID: String? = nil, studies: [ArchiveStudy]) {
        self.patientName = patientName
        self.patientID = patientID
        self.issuerOfPatientID = issuerOfPatientID
        self.studies = studies
    }
}

public struct ArchiveIndex: Codable, Sendable {
    public let version: String
    public let creationDate: String
    public var lastModified: String
    public var fileCount: Int
    public var patients: [ArchivePatient]
}

// MARK: - Matching

/// The PS3.4 2026a C.2.2.2 matching the archive's query and export keys use.
public enum ArchiveMatching {

    /// Single Value Matching (C.2.2.2.1) or, when `key` contains `*` or `?`, Wild Card Matching
    /// (C.2.2.2.4) of a string key. A zero-length key or `*` is Universal Matching (C.2.2.2.3).
    /// `caseSensitive` is `true` for every VR except PN: "This matching is case sensitive,
    /// except for Attributes with a PN VR".
    public static func matches(_ key: String, _ value: String, caseSensitive: Bool) -> Bool {
        if key.isEmpty { return true }
        let p = Array(caseSensitive ? key : key.uppercased())
        let t = Array(caseSensitive ? value : value.uppercased())
        return wildcard(p, 0, t, 0)
    }

    /// List of UID Matching (C.2.2.2.2): `key` is one UID or a backslash-separated list; each
    /// UID in the list may generate a match. A zero-length key is Universal Matching.
    public static func matchesUIDList(_ key: String, _ uid: String) -> Bool {
        if key.isEmpty { return true }
        return key.split(separator: "\\", omittingEmptySubsequences: true)
            .contains { $0.trimmingCharacters(in: .whitespaces) == uid }
    }

    /// Single Value Matching (C.2.2.2.1) or Range Matching (C.2.2.2.5.1) of a DA key:
    /// `YYYYMMDD`, `YYYYMMDD-YYYYMMDD` (inclusive), `-YYYYMMDD` (on or before) or `YYYYMMDD-`
    /// (on or after). An entity without a date matches only a zero-length key. A key that is
    /// neither form is compared as a literal string.
    public static func matchesDate(_ key: String, _ date: String?) -> Bool {
        let key = key.trimmingCharacters(in: .whitespaces)
        if key.isEmpty { return true }
        guard let date = date?.trimmingCharacters(in: .whitespaces), !date.isEmpty else { return false }
        guard let range = dateRange(key) else { return key == date }
        guard isDA(date) else { return false }
        if let lower = range.lower, date < lower { return false }
        if let upper = range.upper, date > upper { return false }
        return true
    }

    /// The bounds of a DA key (C.2.2.2.1 single value or C.2.2.2.5.1 range); `nil` when the
    /// key is neither a DA value (PS3.5 2026a Table 6.2-1: 8 bytes, "0"-"9") nor a DA range.
    public static func dateRange(_ key: String) -> (lower: String?, upper: String?)? {
        let key = key.trimmingCharacters(in: .whitespaces)
        if isDA(key) { return (key, key) }
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return nil }
        let lower = parts[0].isEmpty ? nil : parts[0]
        let upper = parts[1].isEmpty ? nil : parts[1]
        if lower == nil && upper == nil { return nil }
        if let lower, !isDA(lower) { return nil }
        if let upper, !isDA(upper) { return nil }
        if let lower, let upper, lower > upper { return nil }
        return (lower, upper)
    }

    static func isDA(_ s: String) -> Bool {
        s.utf8.count == 8 && s.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 }
    }

    private static func wildcard(_ pattern: [Character], _ pi: Int, _ text: [Character], _ ti: Int) -> Bool {
        var pi = pi
        var ti = ti
        while pi < pattern.count {
            let pc = pattern[pi]
            if pc == "*" {
                pi += 1
                while pi < pattern.count && pattern[pi] == "*" { pi += 1 }
                if pi == pattern.count { return true }
                while ti <= text.count {
                    if wildcard(pattern, pi, text, ti) { return true }
                    ti += 1
                }
                return false
            } else if pc == "?" {
                guard ti < text.count else { return false }
                pi += 1; ti += 1
            } else {
                guard ti < text.count, pc == text[ti] else { return false }
                pi += 1; ti += 1
            }
        }
        return ti == text.count
    }
}

// MARK: - Archive Store

public enum ArchiveStore {

    public static let archiveVersion = "1.2.1"

    // MARK: Matching (PS3.4 2026a C.2.2.2)

    /// Wild Card Matching (PS3.4 C.2.2.2.4) of a Patient's Name (PN) key: `*` matches any
    /// sequence of characters, `?` any single character, case-insensitively (C.2.2.2.1.1 and
    /// C.2.2.2.4 leave PN case handling to the implementation).
    static func wildcardMatch(_ pattern: String, _ text: String) -> Bool {
        ArchiveMatching.matches(pattern, text, caseSensitive: false)
    }

    // MARK: Helpers

    static func isoDateString() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }

    public static func indexURL(for archivePath: String) -> URL {
        URL(fileURLWithPath: archivePath).appendingPathComponent("archive_index.json")
    }

    public static func dataDirectory(for archivePath: String) -> URL {
        URL(fileURLWithPath: archivePath).appendingPathComponent("data")
    }

    public static func loadIndex(from archivePath: String) throws -> ArchiveIndex {
        let url = indexURL(for: archivePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ArchiveError.archiveNotFound(archivePath)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ArchiveIndex.self, from: data)
    }

    static func saveIndex(_ index: ArchiveIndex, to archivePath: String) throws {
        let url = indexURL(for: archivePath)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(index)
        try data.write(to: url)
    }

    static func sanitizePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        var result = ""
        for char in value.unicodeScalars {
            if allowed.contains(char) {
                result.append(Character(char))
            } else {
                result.append("_")
            }
        }
        if result.isEmpty { result = "UNKNOWN" }
        return result
    }

    static func countTotalInstances(_ index: ArchiveIndex) -> Int {
        var count = 0
        for patient in index.patients {
            for study in patient.studies {
                for series in study.series {
                    count += series.instances.count
                }
            }
        }
        return count
    }

    private static func truncate(_ str: String, to length: Int) -> String {
        if str.count <= length { return str }
        return String(str.prefix(length - 1)) + "…"
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0
        let maxUnitIndex = units.count - 1
        while value >= 1024 && unitIndex < maxUnitIndex {
            value /= 1024
            unitIndex += 1
        }
        if unitIndex == 0 { return "\(bytes) B" }
        return String(format: "%.1f %@", value, units[unitIndex])
    }

    // MARK: - init

    public static func initArchive(at archivePath: String, force: Bool) throws -> String {
        let fm = FileManager.default
        let idxURL = indexURL(for: archivePath)
        if fm.fileExists(atPath: idxURL.path) && !force {
            throw ArchiveError.archiveExists(archivePath)
        }
        let dataDir = dataDirectory(for: archivePath)
        try fm.createDirectory(at: dataDir, withIntermediateDirectories: true)
        let index = ArchiveIndex(
            version: archiveVersion,
            creationDate: isoDateString(),
            lastModified: isoDateString(),
            fileCount: 0,
            patients: []
        )
        try saveIndex(index, to: archivePath)
        var out = ""
        out += "✅ Archive initialized at: \(archivePath)\n"
        out += "\n"
        out += "Structure:\n"
        out += "  \(archivePath)/\n"
        out += "  ├── archive_index.json\n"
        out += "  └── data/\n"
        return out
    }

    // MARK: - import

    public static func importFiles(
        into archive: String,
        files: [String],
        recursive: Bool,
        skipDuplicates: Bool,
        verbose: Bool
    ) throws -> String {
        var index = try loadIndex(from: archive)
        let fm = FileManager.default
        let dataDir = dataDirectory(for: archive)
        var out = ""

        // Collect all file paths
        var filePaths: [String] = []
        for input in files {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: input, isDirectory: &isDir) else {
                out += "⚠️  File not found: \(input)\n"
                continue
            }
            if isDir.boolValue {
                let dirFiles = try collectDICOMFiles(in: input, recursive: recursive)
                filePaths.append(contentsOf: dirFiles)
            } else {
                filePaths.append(input)
            }
        }

        if filePaths.isEmpty {
            throw ArchiveError.noFilesToImport
        }

        var existingSOPs = Set<String>()
        for patient in index.patients {
            for study in patient.studies {
                for series in study.series {
                    for instance in series.instances {
                        existingSOPs.insert(instance.sopInstanceUID)
                    }
                }
            }
        }

        var imported = 0
        var skipped = 0
        var failed = 0

        for (i, filePath) in filePaths.enumerated() {
            if verbose {
                out += "[\(i + 1)/\(filePaths.count)] Processing \(URL(fileURLWithPath: filePath).lastPathComponent)...\n"
            }
            do {
                let fileData = try Data(contentsOf: URL(fileURLWithPath: filePath))
                let dicomFile = try DICOMFile.read(from: fileData, force: true)
                let ds = dicomFile.dataSet

                guard let sopInstanceUID = ds.string(for: .sopInstanceUID) else {
                    if verbose { out += "  ⚠️  Missing SOP Instance UID, skipping\n" }
                    failed += 1
                    continue
                }

                if existingSOPs.contains(sopInstanceUID) {
                    if verbose { out += "  ⏭️  Duplicate SOP Instance UID, skipping\n" }
                    skipped += 1
                    continue
                }

                let patientName = ds.string(for: .patientName) ?? "UNKNOWN"
                let patientID = ds.string(for: .patientID) ?? "UNKNOWN"
                let issuerOfPatientID = ds.string(for: Tag(group: 0x0010, element: 0x0021)).flatMap { $0.isEmpty ? nil : $0 }
                let studyInstanceUID = ds.string(for: .studyInstanceUID) ?? "UNKNOWN_STUDY"
                let seriesInstanceUID = ds.string(for: .seriesInstanceUID) ?? "UNKNOWN_SERIES"
                let sopClassUID = ds.string(for: .sopClassUID) ?? ""
                let modality = ds.string(for: .modality) ?? ""
                let studyDate = ds.string(for: .studyDate)
                let studyDescription = ds.string(for: .studyDescription)
                let seriesDescription = ds.string(for: .seriesDescription)
                let seriesNumber = ds.string(for: .seriesNumber)
                let instanceNumber = ds.string(for: .instanceNumber)
                let accessionNumber = ds.string(for: .accessionNumber)

                let safePID = sanitizePathComponent(patientID)
                let safeStudy = sanitizePathComponent(studyInstanceUID)
                let safeSeries = sanitizePathComponent(seriesInstanceUID)
                let fileName = sanitizePathComponent(sopInstanceUID) + ".dcm"
                let relativePath = "\(safePID)/\(safeStudy)/\(safeSeries)/\(fileName)"

                let destDir = dataDir
                    .appendingPathComponent(safePID)
                    .appendingPathComponent(safeStudy)
                    .appendingPathComponent(safeSeries)
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

                let destFile = destDir.appendingPathComponent(fileName)
                try fileData.write(to: destFile)

                let instance = ArchiveInstance(
                    sopInstanceUID: sopInstanceUID,
                    sopClassUID: sopClassUID,
                    filePath: relativePath,
                    fileSize: Int64(fileData.count),
                    importDate: isoDateString(),
                    instanceNumber: instanceNumber
                )

                addInstanceToIndex(
                    &index,
                    instance: instance,
                    patientName: patientName,
                    patientID: patientID,
                    issuerOfPatientID: issuerOfPatientID,
                    studyInstanceUID: studyInstanceUID,
                    studyDate: studyDate,
                    studyDescription: studyDescription,
                    modality: modality,
                    accessionNumber: accessionNumber,
                    seriesInstanceUID: seriesInstanceUID,
                    seriesDescription: seriesDescription,
                    seriesNumber: seriesNumber
                )

                existingSOPs.insert(sopInstanceUID)
                imported += 1
            } catch {
                failed += 1
                if verbose {
                    out += "  ❌ Failed: \(error.localizedDescription)\n"
                }
            }
        }

        index.fileCount = countTotalInstances(index)
        index.lastModified = isoDateString()
        try saveIndex(index, to: archive)

        out += "\n"
        out += "✅ Import complete\n"
        out += "  Imported: \(imported)\n"
        if skipped > 0 { out += "  Skipped (duplicates): \(skipped)\n" }
        if failed > 0 { out += "  Failed: \(failed)\n" }
        out += "  Total files in archive: \(index.fileCount)\n"
        return out
    }

    private static func collectDICOMFiles(in directory: String, recursive: Bool) throws -> [String] {
        let fm = FileManager.default
        let dirURL = URL(fileURLWithPath: directory)
        var results: [String] = []
        if recursive {
            guard let enumerator = fm.enumerator(
                at: dirURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                throw ArchiveError.cannotEnumerate(directory)
            }
            for case let fileURL as URL in enumerator {
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                if values.isRegularFile == true { results.append(fileURL.path) }
            }
        } else {
            let contents = try fm.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            for fileURL in contents {
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                if values.isRegularFile == true { results.append(fileURL.path) }
            }
        }
        return results.sorted()
    }

    private static func addInstanceToIndex(
        _ index: inout ArchiveIndex,
        instance: ArchiveInstance,
        patientName: String,
        patientID: String,
        issuerOfPatientID: String?,
        studyInstanceUID: String,
        studyDate: String?,
        studyDescription: String?,
        modality: String,
        accessionNumber: String?,
        seriesInstanceUID: String,
        seriesDescription: String?,
        seriesNumber: String?
    ) {
        func makeSeries() -> ArchiveSeries {
            ArchiveSeries(
                seriesInstanceUID: seriesInstanceUID,
                modality: modality,
                seriesDescription: seriesDescription,
                seriesNumber: seriesNumber,
                instances: [instance])
        }
        func makeStudy() -> ArchiveStudy {
            ArchiveStudy(
                studyInstanceUID: studyInstanceUID,
                studyDate: studyDate,
                studyDescription: studyDescription,
                modality: modality,
                accessionNumber: accessionNumber,
                series: [makeSeries()])
        }
        // Patient ID is unique only within its issuer (Issuer of Patient ID (0010,0021), PS3.4
        // Tables C.6-1 / C.6-5); an empty or absent Patient ID (Type 2) identifies no one, so
        // those files are also keyed on Patient's Name.
        let unidentified = patientID.isEmpty || patientID == "UNKNOWN"
        let samePatient: (ArchivePatient) -> Bool = { p in
            p.patientID == patientID && p.issuerOfPatientID == issuerOfPatientID
                && (!unidentified || p.patientName == patientName)
        }
        if let pi = index.patients.firstIndex(where: samePatient) {
            if let si = index.patients[pi].studies.firstIndex(where: { $0.studyInstanceUID == studyInstanceUID }) {
                if let sei = index.patients[pi].studies[si].series.firstIndex(where: { $0.seriesInstanceUID == seriesInstanceUID }) {
                    index.patients[pi].studies[si].series[sei].instances.append(instance)
                } else {
                    index.patients[pi].studies[si].series.append(makeSeries())
                }
            } else {
                index.patients[pi].studies.append(makeStudy())
            }
        } else {
            index.patients.append(ArchivePatient(patientName: patientName, patientID: patientID,
                                                 issuerOfPatientID: issuerOfPatientID, studies: [makeStudy()]))
        }
    }

    // MARK: - query

    public static func query(
        in archive: String,
        patientName: String?,
        patientID: String?,
        studyUID: String?,
        modality: String?,
        studyDate: String?,
        format: String
    ) throws -> String {
        let index = try loadIndex(from: archive)
        guard ["table", "json", "text"].contains(format.lowercased()) else {
            throw ArchiveError.invalidFormat("Invalid format: \(format). Use table, json, or text")
        }

        var results: [(patient: ArchivePatient, study: ArchiveStudy)] = []
        for patient in index.patients {
            // Patient's Name (PN): wild cards, case-insensitive (C.2.2.2.1.1, C.2.2.2.4).
            if let pn = patientName, !ArchiveMatching.matches(pn, patient.patientName, caseSensitive: false) { continue }
            // Patient ID (LO): wild cards, case-sensitive (C.2.2.2.1, C.2.2.2.4).
            if let pid = patientID, !ArchiveMatching.matches(pid, patient.patientID, caseSensitive: true) { continue }
            for study in patient.studies {
                // Study Instance UID (UI): List of UID Matching (C.2.2.2.2).
                if let uid = studyUID, !ArchiveMatching.matchesUIDList(uid, study.studyInstanceUID) { continue }
                // Modality (CS) against Modalities in Study (0008,0061): wild cards, case-sensitive.
                if let mod = modality,
                   !study.modalitiesInStudy.contains(where: { ArchiveMatching.matches(mod, $0, caseSensitive: true) }) { continue }
                // Study Date (DA): single value or Range Matching (C.2.2.2.5.1).
                if let sd = studyDate, !ArchiveMatching.matchesDate(sd, study.studyDate) { continue }
                results.append((patient: patient, study: study))
            }
        }

        if results.isEmpty {
            return "No matching results found.\n"
        }

        switch format.lowercased() {
        case "json": return queryJSON(results)
        case "text": return queryText(results)
        default: return queryTable(results)
        }
    }

    /// Renders `cols` / `rows` as a ` | `-separated table whose column widths fit the
    /// header and are capped at `maxWidths` for the values.
    private static func renderTable(_ cols: [String], _ rows: [[String]], maxWidths: [Int]) -> String {
        let widths = cols.indices.map { i in
            max(cols[i].count, min(maxWidths[i], rows.map { $0[i].count }.max() ?? 0))
        }
        func line(_ cells: [String]) -> String {
            zip(cells, widths).map { truncate($0.0, to: $0.1).padding(toLength: $0.1, withPad: " ", startingAt: 0) }
                .joined(separator: " | ")
        }
        var out = line(cols) + "\n"
        out += widths.map { String(repeating: "-", count: $0) }.joined(separator: "-+-") + "\n"
        for row in rows { out += line(row) + "\n" }
        return out
    }

    /// Modalities in Study (0008,0061) as a DICOM multi-value string ("CT\\PT").
    private static func modalitiesString(_ study: ArchiveStudy) -> String {
        study.modalitiesInStudy.joined(separator: "\\")
    }

    private static func queryTable(_ results: [(patient: ArchivePatient, study: ArchiveStudy)]) -> String {
        // Column labels: PS3.6 2026a Table 6-1 names (Number of Study Related Series /
        // Instances, PS3.4 Table C.6-5).
        let cols = ["Patient's Name", "Patient ID", "Study Date", "Modalities in Study", "Study Description",
                    "Number of Study Related Series", "Number of Study Related Instances"]
        let rows = results.map { result -> [String] in
            let instanceCount = result.study.series.reduce(0) { $0 + $1.instances.count }
            return [
                result.patient.patientName,
                result.patient.patientID,
                result.study.studyDate ?? "",
                modalitiesString(result.study),
                result.study.studyDescription ?? "",
                String(result.study.series.count),
                String(instanceCount)
            ]
        }
        var out = renderTable(cols, rows, maxWidths: [20, 15, 8, 19, 25, 30, 33])
        out += "\n"
        out += "Found \(results.count) matching study(ies)\n"
        return out
    }

    private static func queryJSON(_ results: [(patient: ArchivePatient, study: ArchiveStudy)]) -> String {
        // P-ARCHIVE-1 (approved 2026-10-01): the PS3.6 2026a Table 6-1 keywords ModalitiesInStudy
        // (0008,0061), NumberOfStudyRelatedSeries (0020,1206) and NumberOfStudyRelatedInstances
        // (0020,1208) (PS3.4 Table C.6-5) are written next to the former `modality`, `seriesCount`
        // and `imageCount`, which keep their values and are deprecated.
        struct QueryResult: Codable {
            let patientName: String
            let patientID: String
            let IssuerOfPatientID: String?
            let studyInstanceUID: String
            let studyDate: String?
            let studyDescription: String?
            let modality: String?
            let seriesCount: Int
            let imageCount: Int
            let ModalitiesInStudy: [String]
            let NumberOfStudyRelatedSeries: Int
            let NumberOfStudyRelatedInstances: Int
        }
        let items = results.map { r in
            let instances = r.study.series.reduce(0) { $0 + $1.instances.count }
            return QueryResult(
                patientName: r.patient.patientName,
                patientID: r.patient.patientID,
                IssuerOfPatientID: r.patient.issuerOfPatientID,
                studyInstanceUID: r.study.studyInstanceUID,
                studyDate: r.study.studyDate,
                studyDescription: r.study.studyDescription,
                modality: r.study.firstInstanceModality,
                seriesCount: r.study.series.count,
                imageCount: instances,
                ModalitiesInStudy: r.study.modalitiesInStudy,
                NumberOfStudyRelatedSeries: r.study.series.count,
                NumberOfStudyRelatedInstances: instances)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(items), let json = String(data: data, encoding: .utf8) {
            return json + "\n"
        }
        return ""
    }

    private static func queryText(_ results: [(patient: ArchivePatient, study: ArchiveStudy)]) -> String {
        // Labels: PS3.6 2026a Table 6-1 names.
        var out = ""
        for (i, result) in results.enumerated() {
            if i > 0 { out += "\n" }
            let instanceCount = result.study.series.reduce(0) { $0 + $1.instances.count }
            out += "Patient's Name: \(result.patient.patientName)\n"
            out += "Patient ID: \(result.patient.patientID)\n"
            if let issuer = result.patient.issuerOfPatientID { out += "Issuer of Patient ID: \(issuer)\n" }
            out += "  Study Instance UID: \(result.study.studyInstanceUID)\n"
            if let date = result.study.studyDate { out += "  Study Date: \(date)\n" }
            if let desc = result.study.studyDescription { out += "  Study Description: \(desc)\n" }
            let modalities = modalitiesString(result.study)
            if !modalities.isEmpty { out += "  Modalities in Study: \(modalities)\n" }
            out += "  Number of Study Related Series: \(result.study.series.count)\n"
            out += "  Number of Study Related Instances: \(instanceCount)\n"
        }
        out += "\n"
        out += "Found \(results.count) matching study(ies)\n"
        return out
    }

    // MARK: - list

    public static func list(in archive: String, format: String, showInstances: Bool) throws -> String {
        let index = try loadIndex(from: archive)
        guard ["tree", "table", "json"].contains(format.lowercased()) else {
            throw ArchiveError.invalidFormat("Invalid format: \(format). Use tree, table, or json")
        }
        if index.patients.isEmpty {
            return "Archive is empty.\n"
        }
        switch format.lowercased() {
        case "json": return listJSON(index)
        case "table": return listTable(index)
        default: return listTree(index, archive: archive, showInstances: showInstances)
        }
    }

    private static func listTree(_ index: ArchiveIndex, archive: String, showInstances: Bool) -> String {
        var out = ""
        out += "Archive: \(archive)\n"
        out += "Files: \(index.fileCount)\n"
        out += "\n"
        for (pi, patient) in index.patients.enumerated() {
            let isLastPatient = pi == index.patients.count - 1
            let pPrefix = isLastPatient ? "└── " : "├── "
            let pCont = isLastPatient ? "    " : "│   "
            let issuer = patient.issuerOfPatientID.map { ", Issuer of Patient ID: \($0)" } ?? ""
            out += "\(pPrefix)Patient: \(patient.patientName) (Patient ID: \(patient.patientID)\(issuer))\n"
            for (si, study) in patient.studies.enumerated() {
                let isLastStudy = si == patient.studies.count - 1
                let sPrefix = pCont + (isLastStudy ? "└── " : "├── ")
                let sCont = pCont + (isLastStudy ? "    " : "│   ")
                let desc = study.studyDescription ?? study.studyInstanceUID
                let date = study.studyDate.map { " [\($0)]" } ?? ""
                out += "\(sPrefix)Study: \(desc)\(date)\n"
                for (sei, series) in study.series.enumerated() {
                    let isLastSeries = sei == study.series.count - 1
                    let sePrefix = sCont + (isLastSeries ? "└── " : "├── ")
                    let seCont = sCont + (isLastSeries ? "    " : "│   ")
                    let seDesc = series.seriesDescription ?? series.seriesInstanceUID
                    out += "\(sePrefix)Series: \(series.modality) - \(seDesc) (\(series.instances.count) instances)\n"
                    if showInstances {
                        for (ii, instance) in series.instances.enumerated() {
                            let isLastInstance = ii == series.instances.count - 1
                            let iPrefix = seCont + (isLastInstance ? "└── " : "├── ")
                            out += "\(iPrefix)\(instance.sopInstanceUID)\n"
                        }
                    }
                }
            }
        }
        return out
    }

    private static func listTable(_ index: ArchiveIndex) -> String {
        // Column labels: PS3.6 2026a Table 6-1 names (PS3.4 Table C.6-1 patient-level counts).
        let cols = ["Patient's Name", "Patient ID", "Number of Patient Related Studies",
                    "Number of Patient Related Series", "Number of Patient Related Instances"]
        let rows = index.patients.map { patient -> [String] in
            let seriesCount = patient.studies.reduce(0) { $0 + $1.series.count }
            let instanceCount = patient.studies.reduce(0) { total, study in
                total + study.series.reduce(0) { $0 + $1.instances.count }
            }
            return [patient.patientName, patient.patientID, String(patient.studies.count),
                    String(seriesCount), String(instanceCount)]
        }
        var out = renderTable(cols, rows, maxWidths: [25, 15, 33, 32, 35])
        out += "\n"
        out += "Total: \(index.patients.count) patient(s), \(index.fileCount) file(s)\n"
        return out
    }

    private static func listJSON(_ index: ArchiveIndex) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(index), let json = String(data: data, encoding: .utf8) {
            return json + "\n"
        }
        return ""
    }

    // MARK: - export

    public static func export(
        from archive: String,
        output: String,
        studyUID: String?,
        seriesUID: String?,
        patientID: String?,
        flatten: Bool,
        verbose: Bool
    ) throws -> String {
        let index = try loadIndex(from: archive)
        let fm = FileManager.default
        let dataDir = dataDirectory(for: archive)
        let outputURL = URL(fileURLWithPath: output)
        var out = ""

        if studyUID == nil && seriesUID == nil && patientID == nil {
            throw ArchiveError.noExportFilter
        }

        try fm.createDirectory(at: outputURL, withIntermediateDirectories: true)

        var exported = 0
        var failed = 0

        for patient in index.patients {
            if let pid = patientID, patient.patientID != pid { continue }
            for study in patient.studies {
                // List of UID Matching (PS3.4 C.2.2.2.2) for both UID keys.
                if let uid = studyUID, !ArchiveMatching.matchesUIDList(uid, study.studyInstanceUID) { continue }
                for series in study.series {
                    if let uid = seriesUID, !ArchiveMatching.matchesUIDList(uid, series.seriesInstanceUID) { continue }
                    for instance in series.instances {
                        let sourceFile = dataDir.appendingPathComponent(instance.filePath)
                        let destFile: URL
                        if flatten {
                            let fileName = sanitizePathComponent(instance.sopInstanceUID) + ".dcm"
                            destFile = outputURL.appendingPathComponent(fileName)
                        } else {
                            let destDir = outputURL
                                .appendingPathComponent(sanitizePathComponent(patient.patientID))
                                .appendingPathComponent(sanitizePathComponent(study.studyInstanceUID))
                                .appendingPathComponent(sanitizePathComponent(series.seriesInstanceUID))
                            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                            let fileName = sanitizePathComponent(instance.sopInstanceUID) + ".dcm"
                            destFile = destDir.appendingPathComponent(fileName)
                        }
                        do {
                            try fm.copyItem(at: sourceFile, to: destFile)
                            exported += 1
                            if verbose { out += "  Exported: \(instance.sopInstanceUID)\n" }
                        } catch {
                            failed += 1
                            if verbose { out += "  ❌ Failed to export \(instance.sopInstanceUID): \(error.localizedDescription)\n" }
                        }
                    }
                }
            }
        }

        out += "\n"
        out += "✅ Export complete\n"
        out += "  Exported: \(exported) file(s)\n"
        if failed > 0 { out += "  Failed: \(failed)\n" }
        out += "  Output: \(output)\n"
        return out
    }

    // MARK: - check

    public static func check(in archive: String, verifyFiles: Bool, verbose: Bool) throws -> String {
        let index = try loadIndex(from: archive)
        let fm = FileManager.default
        let dataDir = dataDirectory(for: archive)
        var out = ""

        var missingFiles = 0
        var sizeMismatches = 0
        var unreadableFiles = 0
        var orphanedFiles: [String] = []
        var totalChecked = 0

        for patient in index.patients {
            for study in patient.studies {
                for series in study.series {
                    for instance in series.instances {
                        totalChecked += 1
                        let filePath = dataDir.appendingPathComponent(instance.filePath).path
                        if !fm.fileExists(atPath: filePath) {
                            missingFiles += 1
                            if verbose { out += "❌ Missing: \(instance.filePath)\n" }
                            continue
                        }
                        do {
                            let attrs = try fm.attributesOfItem(atPath: filePath)
                            if let fileSize = attrs[.size] as? Int64, fileSize != instance.fileSize {
                                sizeMismatches += 1
                                if verbose { out += "⚠️  Size mismatch: \(instance.filePath) (expected \(instance.fileSize), got \(fileSize))\n" }
                            }
                        } catch {
                            if verbose { out += "⚠️  Cannot read attributes: \(instance.filePath)\n" }
                        }
                        if verifyFiles {
                            do {
                                let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
                                _ = try DICOMFile.read(from: data, force: true)
                            } catch {
                                unreadableFiles += 1
                                if verbose { out += "❌ Unreadable DICOM: \(instance.filePath) - \(error.localizedDescription)\n" }
                            }
                        }
                    }
                }
            }
        }

        let indexedPaths = Set(
            index.patients.flatMap { p in
                p.studies.flatMap { st in
                    st.series.flatMap { se in
                        se.instances.map { $0.filePath }
                    }
                }
            }
        )

        if let enumerator = fm.enumerator(
            at: dataDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
                if values?.isRegularFile == true {
                    let relativePath = fileURL.path.replacingOccurrences(of: dataDir.path + "/", with: "")
                    if !indexedPaths.contains(relativePath) {
                        orphanedFiles.append(relativePath)
                        if verbose { out += "🔍 Orphaned file: \(relativePath)\n" }
                    }
                }
            }
        }

        out += "\n"
        out += "Archive Integrity Report\n"
        out += "========================\n"
        out += "  Files checked: \(totalChecked)\n"
        out += "  Index file count: \(index.fileCount)\n"
        out += "\n"

        var hasIssues = false
        if missingFiles > 0 { out += "  ❌ Missing files: \(missingFiles)\n"; hasIssues = true }
        if sizeMismatches > 0 { out += "  ⚠️  Size mismatches: \(sizeMismatches)\n"; hasIssues = true }
        if unreadableFiles > 0 { out += "  ❌ Unreadable DICOM files: \(unreadableFiles)\n"; hasIssues = true }
        if !orphanedFiles.isEmpty { out += "  🔍 Orphaned files: \(orphanedFiles.count)\n"; hasIssues = true }

        if hasIssues {
            out += "\n"
            out += "⚠️  Archive has integrity issues\n"
        } else {
            out += "  ✅ All files present and accounted for\n"
            if verifyFiles { out += "  ✅ All DICOM files readable\n" }
            out += "\n"
            out += "✅ Archive integrity OK\n"
        }
        return out
    }

    // MARK: - stats

    public static func stats(in archive: String, format: String) throws -> String {
        let index = try loadIndex(from: archive)
        guard ["text", "json"].contains(format.lowercased()) else {
            throw ArchiveError.invalidFormat("Invalid format: \(format). Use text or json")
        }

        var totalSeries = 0
        var totalInstances = 0
        var totalSize: Int64 = 0
        var modalities = [String: Int]()
        var sopClasses = [String: Int]()

        for patient in index.patients {
            for study in patient.studies {
                for series in study.series {
                    totalSeries += 1
                    totalInstances += series.instances.count
                    modalities[series.modality, default: 0] += series.instances.count
                    for instance in series.instances {
                        totalSize += instance.fileSize
                        if !instance.sopClassUID.isEmpty {
                            sopClasses[instance.sopClassUID, default: 0] += 1
                        }
                    }
                }
            }
        }

        let totalStudies = index.patients.reduce(0) { $0 + $1.studies.count }

        switch format.lowercased() {
        case "json":
            return statsJSON(index: index, totalStudies: totalStudies, totalSeries: totalSeries,
                             totalInstances: totalInstances, totalSize: totalSize, modalities: modalities)
        default:
            return statsText(index: index, totalStudies: totalStudies, totalSeries: totalSeries,
                             totalInstances: totalInstances, totalSize: totalSize,
                             modalities: modalities, sopClasses: sopClasses)
        }
    }

    private static func statsText(
        index: ArchiveIndex, totalStudies: Int, totalSeries: Int, totalInstances: Int,
        totalSize: Int64, modalities: [String: Int], sopClasses: [String: Int]
    ) -> String {
        var out = ""
        out += "Archive Statistics\n"
        out += "==================\n"
        out += "\n"
        out += "Archive Info:\n"
        out += "  Version: \(index.version)\n"
        out += "  Created: \(index.creationDate)\n"
        out += "  Last modified: \(index.lastModified)\n"
        out += "\n"
        out += "Contents:\n"
        out += "  Patients: \(index.patients.count)\n"
        out += "  Studies: \(totalStudies)\n"
        out += "  Series: \(totalSeries)\n"
        out += "  Instances: \(totalInstances)\n"
        out += "  Total size: \(formatBytes(totalSize))\n"
        out += "\n"
        if !modalities.isEmpty {
            out += "Modalities:\n"
            for (mod, count) in modalities.sorted(by: { $0.key < $1.key }) {
                let label = mod.isEmpty ? "(unknown)" : mod
                out += "  \(label): \(count) instance(s)\n"
            }
            out += "\n"
        }
        if !sopClasses.isEmpty {
            out += "SOP Classes:\n"
            for (sop, count) in sopClasses.sorted(by: { $0.value > $1.value }).prefix(10) {
                // SOP Class name from PS3.6 2026a Table A-1.
                let name = UIDDictionary.lookup(uid: sop).map { " (\($0.name))" } ?? ""
                out += "  \(sop)\(name): \(count)\n"
            }
            if sopClasses.count > 10 {
                out += "  ... and \(sopClasses.count - 10) more\n"
            }
        }
        return out
    }

    private static func statsJSON(
        index: ArchiveIndex, totalStudies: Int, totalSeries: Int, totalInstances: Int,
        totalSize: Int64, modalities: [String: Int]
    ) -> String {
        struct StatsOutput: Codable {
            let version: String
            let creationDate: String
            let lastModified: String
            let patients: Int
            let studies: Int
            let series: Int
            let instances: Int
            let totalSizeBytes: Int64
            let modalities: [String: Int]
        }
        let output = StatsOutput(
            version: index.version, creationDate: index.creationDate, lastModified: index.lastModified,
            patients: index.patients.count, studies: totalStudies, series: totalSeries,
            instances: totalInstances, totalSizeBytes: totalSize, modalities: modalities)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(output), let json = String(data: data, encoding: .utf8) {
            return json + "\n"
        }
        return ""
    }
}

// MARK: - Study Date key warning (shared by dicom-archive query and the Workshop; D249)

extension ArchiveMatching {

    /// The warning for a Study Date (0008,0020) query key that ``matchesDate(_:_:)`` can only
    /// compare as a literal string: `value` is neither a DA value (PS3.5 2026a Table 6.2-1:
    /// `YYYYMMDD`) nor a DA range of PS3.4 2026a C.2.2.2.5.1 (`<date1>-<date2>`, `-<date1>`,
    /// `<date1>-`), as ``dateRange(_:)`` decides. `nil` for an empty key (Universal Matching)
    /// or a key the archive matches as DICOM. `option` names the key as the caller spells it.
    public static func studyDateKeyWarning(_ value: String?, option: String = "--study-date") -> String? {
        guard let value, !value.isEmpty else { return nil }
        if dateRange(value) != nil { return nil }
        return "warning: \(option) '\(value)' is neither a DA value (YYYYMMDD) nor a DA range "
            + "(PS3.4 C.2.2.2.5.1); it matches only a Study Date (0008,0020) equal to the whole string"
    }
}
