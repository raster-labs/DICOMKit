// NEMA-verified: 2026a, checked 2026-10-01 — reads 13 attributes (Study/Series/SOP Instance UID, Study Date, Study Time, Study Description, Patient's Name, Patient ID, Accession Number, Series Number, Series Description, Modality, Instance Number) and groups by the Q/R unique keys of PS3.4 2026a Tables C.6-2 / C.6-3 / C.6-4; the 11 text labels are PS3.6 2026a Table 6-1 names (Study Instance UID, Study Date, Patient's Name, Patient ID, Study Description, Series Number, Modality, Series Description, Number of Study Related Series / Instances, Number of Series Related Instances); a file without Series Instance UID or SOP Instance UID (Type 1, PS3.3 Tables C.7-5a, C.12-1) is reported as skipped, not merged
import Foundation
import DICOMCore
import DICOMDictionary

// Shared study engine for the `dicom-study` CLI and DICOMStudio. Scanning and
// rendering live here (returning strings, never printing) so the two adapters
// run the same code and cannot drift. Series within a study are sorted by UID so
// summary / comparison output is deterministic.

// MARK: - Errors

public enum StudyError: Error, LocalizedError {
    case directoryNotFound(String)
    case fileNotFound(String)
    case invalidDICOMFile(String)
    case noFilesFound
    case invalidPattern(String)
    case writeError(String)

    public var errorDescription: String? {
        switch self {
        case .directoryNotFound(let path): return "Directory not found: \(path)"
        case .fileNotFound(let path): return "File not found: \(path)"
        case .invalidDICOMFile(let path): return "Invalid DICOM file: \(path)"
        case .noFilesFound: return "No DICOM files found in the specified directory"
        case .invalidPattern(let pattern): return "Invalid naming pattern: \(pattern). Use 'descriptive' or 'uid'"
        case .writeError(let msg): return "Write error: \(msg)"
        }
    }
}

// MARK: - Models

public struct StudyMetadata: Codable, Sendable {
    public let studyInstanceUID: String
    public let studyDate: String?
    public let studyTime: String?
    public let studyDescription: String?
    public let patientName: String?
    public let patientID: String?
    public let accessionNumber: String?
    public var series: [SeriesMetadata] = []

    public var totalInstances: Int { series.reduce(0) { $0 + $1.instances.count } }

    public init(studyInstanceUID: String, studyDate: String?, studyTime: String?, studyDescription: String?, patientName: String?, patientID: String?, accessionNumber: String?, series: [SeriesMetadata] = []) {
        self.studyInstanceUID = studyInstanceUID
        self.studyDate = studyDate
        self.studyTime = studyTime
        self.studyDescription = studyDescription
        self.patientName = patientName
        self.patientID = patientID
        self.accessionNumber = accessionNumber
        self.series = series
    }
}

public struct SeriesMetadata: Codable, Sendable {
    public let seriesInstanceUID: String
    public let seriesNumber: String?
    public let seriesDescription: String?
    public let modality: String?
    public var instances: [InstanceMetadata] = []

    public init(seriesInstanceUID: String, seriesNumber: String?, seriesDescription: String?, modality: String?, instances: [InstanceMetadata] = []) {
        self.seriesInstanceUID = seriesInstanceUID
        self.seriesNumber = seriesNumber
        self.seriesDescription = seriesDescription
        self.modality = modality
        self.instances = instances
    }
}

public struct InstanceMetadata: Codable, Sendable {
    public let sopInstanceUID: String
    public let instanceNumber: String?
    public let filePath: String
    public let fileSize: Int64

    public init(sopInstanceUID: String, instanceNumber: String?, filePath: String, fileSize: Int64) {
        self.sopInstanceUID = sopInstanceUID
        self.instanceNumber = instanceNumber
        self.filePath = filePath
        self.fileSize = fileSize
    }
}

/// `dicom-study stats` result.
///
/// JSON (P-STUDY-1, approved 2026-10-01): besides the original keys the encoding carries the
/// PS3.6 2026a Table 6-1 keywords `StudyInstanceUID` (0020,000D), `NumberOfStudyRelatedSeries`
/// (0020,1206), `NumberOfStudyRelatedInstances` (0020,1208) and `ModalitiesInStudy` (0008,0061).
/// The original keys `studyUID`, `seriesCount`, `totalInstances` keep their values and are
/// deprecated. Decoding reads the original keys.
public struct Statistics: Codable, Sendable {
    public let studyUID: String
    public let seriesCount: Int
    public let totalInstances: Int
    public let totalSizeBytes: Int64
    public let averageSizePerInstance: Int64
    public let modalityCounts: [String: Int]
    public let instancesPerSeries: [Int]

    enum CodingKeys: String, CodingKey {
        case studyUID, seriesCount, totalInstances, totalSizeBytes, averageSizePerInstance
        case modalityCounts, instancesPerSeries
    }

    /// PS3.6 Table 6-1 keyword keys written next to the original ones.
    enum KeywordKeys: String, CodingKey {
        case StudyInstanceUID, NumberOfStudyRelatedSeries, NumberOfStudyRelatedInstances, ModalitiesInStudy
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(studyUID, forKey: .studyUID)
        try c.encode(seriesCount, forKey: .seriesCount)
        try c.encode(totalInstances, forKey: .totalInstances)
        try c.encode(totalSizeBytes, forKey: .totalSizeBytes)
        try c.encode(averageSizePerInstance, forKey: .averageSizePerInstance)
        try c.encode(modalityCounts, forKey: .modalityCounts)
        try c.encode(instancesPerSeries, forKey: .instancesPerSeries)
        var k = encoder.container(keyedBy: KeywordKeys.self)
        try k.encode(studyUID, forKey: .StudyInstanceUID)
        try k.encode(seriesCount, forKey: .NumberOfStudyRelatedSeries)
        try k.encode(totalInstances, forKey: .NumberOfStudyRelatedInstances)
        try k.encode(modalityCounts.keys.sorted(), forKey: .ModalitiesInStudy)
    }
}

/// `dicom-study compare` result.
///
/// JSON (P-STUDY-1): besides the original keys the encoding carries `study1` and `study2`
/// objects keyed by the PS3.6 2026a Table 6-1 keywords `StudyInstanceUID`,
/// `NumberOfStudyRelatedSeries`, `NumberOfStudyRelatedInstances`. The original `study1UID`,
/// `study1SeriesCount`, `study1InstanceCount` (and `study2…`) keys are deprecated.
public struct StudyComparison: Codable, Sendable {
    public let study1UID: String
    public let study2UID: String
    public let study1SeriesCount: Int
    public let study2SeriesCount: Int
    public let study1InstanceCount: Int
    public let study2InstanceCount: Int
    public let commonSeriesCount: Int
    public let onlyInStudy1Count: Int
    public let onlyInStudy2Count: Int
    public let seriesDifferences: [SeriesDifference]

    enum CodingKeys: String, CodingKey {
        case study1UID, study2UID, study1SeriesCount, study2SeriesCount, study1InstanceCount, study2InstanceCount
        case commonSeriesCount, onlyInStudy1Count, onlyInStudy2Count, seriesDifferences
    }

    enum StudyKeys: String, CodingKey { case study1, study2 }

    enum KeywordKeys: String, CodingKey {
        case StudyInstanceUID, NumberOfStudyRelatedSeries, NumberOfStudyRelatedInstances
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(study1UID, forKey: .study1UID)
        try c.encode(study2UID, forKey: .study2UID)
        try c.encode(study1SeriesCount, forKey: .study1SeriesCount)
        try c.encode(study2SeriesCount, forKey: .study2SeriesCount)
        try c.encode(study1InstanceCount, forKey: .study1InstanceCount)
        try c.encode(study2InstanceCount, forKey: .study2InstanceCount)
        try c.encode(commonSeriesCount, forKey: .commonSeriesCount)
        try c.encode(onlyInStudy1Count, forKey: .onlyInStudy1Count)
        try c.encode(onlyInStudy2Count, forKey: .onlyInStudy2Count)
        try c.encode(seriesDifferences, forKey: .seriesDifferences)
        var studies = encoder.container(keyedBy: StudyKeys.self)
        var s1 = studies.nestedContainer(keyedBy: KeywordKeys.self, forKey: .study1)
        try s1.encode(study1UID, forKey: .StudyInstanceUID)
        try s1.encode(study1SeriesCount, forKey: .NumberOfStudyRelatedSeries)
        try s1.encode(study1InstanceCount, forKey: .NumberOfStudyRelatedInstances)
        var s2 = studies.nestedContainer(keyedBy: KeywordKeys.self, forKey: .study2)
        try s2.encode(study2UID, forKey: .StudyInstanceUID)
        try s2.encode(study2SeriesCount, forKey: .NumberOfStudyRelatedSeries)
        try s2.encode(study2InstanceCount, forKey: .NumberOfStudyRelatedInstances)
    }
}

/// One series whose instance count differs between the two studies. JSON (P-STUDY-1) adds the
/// PS3.6 keyword `SeriesInstanceUID` next to the deprecated `seriesUID`.
public struct SeriesDifference: Codable, Sendable {
    public let seriesUID: String
    public let instanceCountStudy1: Int
    public let instanceCountStudy2: Int

    enum CodingKeys: String, CodingKey { case seriesUID, instanceCountStudy1, instanceCountStudy2 }
    enum KeywordKeys: String, CodingKey { case SeriesInstanceUID }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(seriesUID, forKey: .seriesUID)
        try c.encode(instanceCountStudy1, forKey: .instanceCountStudy1)
        try c.encode(instanceCountStudy2, forKey: .instanceCountStudy2)
        var k = encoder.container(keyedBy: KeywordKeys.self)
        try k.encode(seriesUID, forKey: .SeriesInstanceUID)
    }
}

/// A DICOM file the scanner left out, with the reason.
public struct StudySkippedFile: Error, Sendable, Equatable {
    public let path: String
    public let reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }
}

/// ``StudyScanner/scan(at:)`` result: the studies and the files that could not be placed.
public struct StudyScanResult: Sendable {
    public let studies: [StudyMetadata]
    public let skipped: [StudySkippedFile]

    public init(studies: [StudyMetadata], skipped: [StudySkippedFile]) {
        self.studies = studies
        self.skipped = skipped
    }
}

// MARK: - Scanner

public enum StudyScanner {

    /// Scans a directory (or single file) into per-study metadata, merging series
    /// across files. Series within each study are sorted by UID for deterministic
    /// output; studies are sorted by UID. Files that cannot be grouped are left out;
    /// ``scan(at:)`` also returns them with the reason.
    public static func scanStudies(at path: String) -> [StudyMetadata] {
        scan(at: path).studies
    }

    /// Scans like ``scanStudies(at:)`` and also reports every DICOM file that was left out:
    /// unreadable, or without Study Instance UID (0020,000D), Series Instance UID (0020,000E) or
    /// SOP Instance UID (0008,0018). Those are Type 1 (PS3.3 2026a Tables C.7-3, C.7-5a, C.12-1)
    /// and are the Q/R unique keys of PS3.4 Tables C.6-2 / C.6-3 / C.6-4, so a file without one
    /// cannot be placed in the hierarchy; it is reported instead of being merged under a
    /// placeholder series.
    public static func scan(at path: String) -> StudyScanResult {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return StudyScanResult(studies: [], skipped: []) }

        let paths = isDir.boolValue ? collectDICOMFiles(at: path) : [path]
        var dict: [String: StudyMetadata] = [:]
        var skipped: [StudySkippedFile] = []
        for filePath in paths {
            let fileStudy: StudyMetadata
            switch scanFile(filePath) {
            case .success(let study): fileStudy = study
            case .failure(let skip): skipped.append(skip); continue
            }
            let uid = fileStudy.studyInstanceUID
            if var existing = dict[uid] {
                for newSeries in fileStudy.series {
                    if let idx = existing.series.firstIndex(where: { $0.seriesInstanceUID == newSeries.seriesInstanceUID }) {
                        existing.series[idx].instances.append(contentsOf: newSeries.instances)
                    } else {
                        existing.series.append(newSeries)
                    }
                }
                dict[uid] = existing
            } else {
                dict[uid] = fileStudy
            }
        }
        let studies = dict.values.map(sortSeries).sorted { $0.studyInstanceUID < $1.studyInstanceUID }
        return StudyScanResult(studies: studies, skipped: skipped)
    }

    private static func sortSeries(_ study: StudyMetadata) -> StudyMetadata {
        var copy = study
        copy.series.sort { $0.seriesInstanceUID < $1.seriesInstanceUID }
        return copy
    }

    private static func scanFile(_ filePath: String) -> Result<StudyMetadata, StudySkippedFile> {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              let file = try? DICOMFile.read(from: data) else {
            return .failure(StudySkippedFile(path: filePath, reason: "not a readable DICOM file"))
        }
        let ds = file.dataSet
        func uid(_ tag: Tag) -> String? {
            guard let v = ds.string(for: tag), !v.isEmpty else { return nil }
            return v
        }
        guard let studyUID = uid(Tag.studyInstanceUID) else {
            return .failure(StudySkippedFile(path: filePath, reason: "no Study Instance UID (0020,000D)"))
        }
        guard let seriesUID = uid(Tag.seriesInstanceUID) else {
            return .failure(StudySkippedFile(path: filePath, reason: "no Series Instance UID (0020,000E)"))
        }
        guard let sopUID = uid(Tag.sopInstanceUID) else {
            return .failure(StudySkippedFile(path: filePath, reason: "no SOP Instance UID (0008,0018)"))
        }
        let size = ((try? FileManager.default.attributesOfItem(atPath: filePath))?[.size] as? Int64) ?? 0
        let inst = InstanceMetadata(
            sopInstanceUID: sopUID,
            instanceNumber: ds.string(for: Tag.instanceNumber),
            filePath: filePath, fileSize: size)
        let series = SeriesMetadata(
            seriesInstanceUID: seriesUID,
            seriesNumber: ds.string(for: Tag.seriesNumber),
            seriesDescription: ds.string(for: Tag.seriesDescription),
            modality: ds.string(for: Tag.modality),
            instances: [inst])
        return .success(StudyMetadata(
            studyInstanceUID: studyUID,
            studyDate: ds.string(for: Tag.studyDate),
            studyTime: ds.string(for: Tag.studyTime),
            studyDescription: ds.string(for: Tag.studyDescription),
            patientName: ds.string(for: Tag.patientName),
            patientID: ds.string(for: Tag.patientID),
            accessionNumber: ds.string(for: Tag.accessionNumber),
            series: [series]))
    }

    /// Recursively collects DICOM file paths under a directory (sorted).
    public static func collectDICOMFiles(at path: String) -> [String] {
        var result: [String] = []
        let fm = FileManager.default
        let base = URL(fileURLWithPath: path)
        guard let en = fm.enumerator(atPath: path) else { return result }
        while let rel = en.nextObject() as? String {
            let full = base.appendingPathComponent(rel).path
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue,
               rel.hasSuffix(".dcm") || isDICOMFile(full) {
                result.append(full)
            }
        }
        return result.sorted()
    }

    static func isDICOMFile(_ path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 132), data.count >= 132 else { return false }
        return data.subdata(in: 128..<132) == Data([0x44, 0x49, 0x43, 0x4D])
    }
}

// MARK: - Reports (return strings; never print)

public enum StudyReport {

    /// Renders the `summary` subcommand output (table / json / csv).
    public static func renderSummary(studies: [StudyMetadata], format: String, verbose: Bool) throws -> String {
        var out = ""
        switch format {
        case "json":
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(studies)
            out += (String(data: data, encoding: .utf8) ?? "") + "\n"
        case "csv":
            // P-STUDY-1: the PS3.6 Table 6-1 keyword columns StudyInstanceUID,
            // NumberOfStudyRelatedSeries, NumberOfStudyRelatedInstances are appended; the
            // original StudyUID, SeriesCount, InstanceCount columns keep their place (deprecated).
            out += "StudyUID,StudyDate,PatientName,PatientID,SeriesCount,InstanceCount,StudyInstanceUID,NumberOfStudyRelatedSeries,NumberOfStudyRelatedInstances\n"
            for st in studies {
                out += "\(st.studyInstanceUID),\(st.studyDate ?? ""),\(st.patientName ?? ""),\(st.patientID ?? ""),\(st.series.count),\(st.totalInstances),\(st.studyInstanceUID),\(st.series.count),\(st.totalInstances)\n"
            }
        case "table":
            for st in studies {
                out += "═══════════════════════════════════════════════════════════════\n"
                // Labels: PS3.6 2026a Table 6-1 attribute names.
                out += "Study Instance UID: \(st.studyInstanceUID)\n"
                if let v = st.studyDate { out += "Study Date: \(v)\n" }
                if let v = st.patientName { out += "Patient's Name: \(v)\n" }
                if let v = st.patientID { out += "Patient ID: \(v)\n" }
                if let v = st.studyDescription { out += "Study Description: \(v)\n" }
                out += "Number of Study Related Series: \(st.series.count)\n"
                out += "Number of Study Related Instances: \(st.totalInstances)\n"
                if verbose {
                    out += "\nSeries:\n"
                    for (idx, se) in st.series.enumerated() {
                        out += "  [\(idx + 1)] \(se.seriesInstanceUID)\n"
                        if let v = se.seriesNumber { out += "      Series Number: \(v)\n" }
                        if let v = se.modality { out += "      Modality: \(v)\n" }
                        if let v = se.seriesDescription { out += "      Series Description: \(v)\n" }
                        out += "      Number of Series Related Instances: \(se.instances.count)\n"
                    }
                }
                out += "\n"
            }
        default:
            throw StudyError.invalidPattern(format)
        }
        return out
    }

    public static func computeStatistics(for study: StudyMetadata, detailed: Bool) -> Statistics {
        let totalInstances = study.totalInstances
        let totalSize = study.series.flatMap { $0.instances }.reduce(Int64(0)) { $0 + $1.fileSize }
        let avg = totalInstances > 0 ? totalSize / Int64(totalInstances) : 0
        var modalityCounts: [String: Int] = [:]
        for s in study.series { modalityCounts[s.modality ?? "Unknown", default: 0] += 1 }
        let instancesPerSeries = study.series.map { $0.instances.count }
        return Statistics(
            studyUID: study.studyInstanceUID,
            seriesCount: study.series.count,
            totalInstances: totalInstances,
            totalSizeBytes: totalSize,
            averageSizePerInstance: avg,
            modalityCounts: modalityCounts,
            instancesPerSeries: detailed ? instancesPerSeries : [])
    }

    /// Renders the `stats` subcommand output (text / json).
    public static func renderStats(_ stats: Statistics, detailed: Bool, format: String) throws -> String {
        if format == "json" {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted]
            let data = try enc.encode(stats)
            return (String(data: data, encoding: .utf8) ?? "") + "\n"
        }
        var out = ""
        out += "═══════════════════════════════════════════════════════════════\n"
        out += "Study Statistics\n"
        out += "═══════════════════════════════════════════════════════════════\n"
        out += "Study Instance UID: \(stats.studyUID)\n"
        out += "Number of Study Related Series: \(stats.seriesCount)\n"
        out += "Number of Study Related Instances: \(stats.totalInstances)\n"
        out += "Total Size: \(formatBytes(stats.totalSizeBytes))\n"
        out += "Avg Size/Instance: \(formatBytes(stats.averageSizePerInstance))\n"
        out += "\nModalities:\n"
        for (m, c) in stats.modalityCounts.sorted(by: { $0.key < $1.key }) {
            out += "  \(m): \(c) series\n"
        }
        if detailed && !stats.instancesPerSeries.isEmpty {
            out += "\nInstances per Series:\n"
            for (idx, c) in stats.instancesPerSeries.enumerated() {
                out += "  Series \(idx + 1): \(c) instances\n"
            }
            let mn = stats.instancesPerSeries.min() ?? 0
            let mx = stats.instancesPerSeries.max() ?? 0
            let average = stats.instancesPerSeries.isEmpty ? 0.0 : Double(stats.instancesPerSeries.reduce(0, +)) / Double(stats.instancesPerSeries.count)
            out += "\nInstance Count Statistics:\n"
            out += "  Min: \(mn)\n"
            out += "  Max: \(mx)\n"
            out += "  Average: \(String(format: "%.1f", average))\n"
        }
        return out
    }

    public static func compareStudies(_ s1: StudyMetadata, _ s2: StudyMetadata) -> StudyComparison {
        let set1 = Set(s1.series.map { $0.seriesInstanceUID })
        let set2 = Set(s2.series.map { $0.seriesInstanceUID })
        let common = set1.intersection(set2)
        let only1 = set1.subtracting(set2)
        let only2 = set2.subtracting(set1)
        var diffs: [SeriesDifference] = []
        for uid in common.sorted() {
            if let a = s1.series.first(where: { $0.seriesInstanceUID == uid }),
               let b = s2.series.first(where: { $0.seriesInstanceUID == uid }),
               a.instances.count != b.instances.count {
                diffs.append(SeriesDifference(seriesUID: uid, instanceCountStudy1: a.instances.count, instanceCountStudy2: b.instances.count))
            }
        }
        return StudyComparison(
            study1UID: s1.studyInstanceUID, study2UID: s2.studyInstanceUID,
            study1SeriesCount: s1.series.count, study2SeriesCount: s2.series.count,
            study1InstanceCount: s1.totalInstances, study2InstanceCount: s2.totalInstances,
            commonSeriesCount: common.count, onlyInStudy1Count: only1.count, onlyInStudy2Count: only2.count,
            seriesDifferences: diffs)
    }

    /// Renders the `compare` subcommand output (text / json).
    public static func renderComparison(_ cmp: StudyComparison, format: String, verbose: Bool) throws -> String {
        if format == "json" {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted]
            let data = try enc.encode(cmp)
            return (String(data: data, encoding: .utf8) ?? "") + "\n"
        }
        var out = ""
        out += "═══════════════════════════════════════════════════════════════\n"
        out += "Study Comparison\n"
        out += "═══════════════════════════════════════════════════════════════\n"
        out += "Study 1 UID: \(cmp.study1UID)\n"
        out += "Study 2 UID: \(cmp.study2UID)\n\n"
        out += "Series Counts:\n"
        out += "  Study 1: \(cmp.study1SeriesCount)\n"
        out += "  Study 2: \(cmp.study2SeriesCount)\n"
        out += "  Common: \(cmp.commonSeriesCount)\n"
        out += "  Only in Study 1: \(cmp.onlyInStudy1Count)\n"
        out += "  Only in Study 2: \(cmp.onlyInStudy2Count)\n\n"
        out += "Instance Counts:\n"
        out += "  Study 1: \(cmp.study1InstanceCount)\n"
        out += "  Study 2: \(cmp.study2InstanceCount)\n"
        if !cmp.seriesDifferences.isEmpty {
            out += "\nSeries with Different Instance Counts:\n"
            for d in cmp.seriesDifferences {
                out += "  \(d.seriesUID):\n"
                out += "    Study 1: \(d.instanceCountStudy1)\n"
                out += "    Study 2: \(d.instanceCountStudy2)\n"
                out += "    Difference: \(abs(d.instanceCountStudy1 - d.instanceCountStudy2))\n"
            }
        }
        if cmp.study1SeriesCount == cmp.study2SeriesCount &&
           cmp.study1InstanceCount == cmp.study2InstanceCount &&
           cmp.seriesDifferences.isEmpty {
            out += "\n✓ Studies are structurally identical\n"
        } else {
            out += "\n✗ Studies have differences\n"
        }
        return out
    }

    /// Evaluates study completeness, returning the rendered output, the issue
    /// list (for an optional report file), and whether the study is complete.
    public static func evaluateCompleteness(
        study: StudyMetadata,
        expectedSeries: Int?,
        expectedInstances: Int?
    ) -> (output: String, issues: [String], isComplete: Bool) {
        var issues: [String] = []
        var isComplete = true

        if let expected = expectedSeries, study.series.count != expected {
            issues.append("Expected \(expected) series, found \(study.series.count)")
            isComplete = false
        }
        for series in study.series {
            if let expected = expectedInstances, series.instances.count != expected {
                let desc = series.seriesDescription ?? series.seriesInstanceUID
                issues.append("Series '\(desc)': Expected \(expected) instances, found \(series.instances.count)")
                isComplete = false
            }
            let numbers = series.instances.compactMap { $0.instanceNumber }.compactMap { Int($0) }.sorted()
            if let minNum = numbers.first, let maxNum = numbers.last, minNum <= maxNum {
                let missing = Set(minNum...maxNum).subtracting(Set(numbers))
                if !missing.isEmpty {
                    let desc = series.seriesDescription ?? series.seriesInstanceUID
                    issues.append("Series '\(desc)': Missing instance numbers: \(missing.sorted())")
                    isComplete = false
                }
            }
        }

        var out = ""
        if isComplete {
            out += "✓ Study is complete\n"
        } else {
            out += "✗ Study has \(issues.count) issues:\n"
            for issue in issues { out += "  - \(issue)\n" }
        }
        return (out, issues, isComplete)
    }

    public static func formatBytes(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024.0, mb = Double(bytes) / 1_048_576.0, gb = Double(bytes) / 1_073_741_824.0
        if gb >= 1.0 { return String(format: "%.2f GB", gb) }
        if mb >= 1.0 { return String(format: "%.2f MB", mb) }
        if kb >= 1.0 { return String(format: "%.2f KB", kb) }
        return "\(bytes) bytes"
    }
}
