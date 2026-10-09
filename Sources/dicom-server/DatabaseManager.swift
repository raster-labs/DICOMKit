// NEMA-verified: 2026a, checked 2026-10-01 — C-FIND / C-MOVE / C-GET matching compared with PS3.4 2026a C.2.2.2 and Tables C.6-1..C.6-5 (dumped by Scripts/nema_docbook.py): all 12 Required/Unique keys of C.6-1 (2), C.6-2 (5), C.6-3 (3), C.6-4 (2) and C.6-5 (7, the Study Root study level) are matched and returned, plus 6 optional keys; Single Value Matching case-sensitive except PN (C.2.2.2.1, C.2.2.2.1.1), List of UID Matching for UI (C.2.2.2.2), Universal Matching (C.2.2.2.3), Wild Card Matching only for AE, CS, LO, LT, PN, SH, ST, UC, UR, UT and case-sensitive except PN (C.2.2.2.4), Range Matching for DA / TM (C.2.2.2.5.1-2); the response Identifier carries the requested keys, Query/Retrieve Level and Retrieve AE Title (C.4.1.1.3.2); the VR of every key comes from the data dictionary (PS3.6 Table 6-1); the DICOMMetadata attribute fields name PS3.6 2026a Table 6-1 keywords
import Foundation
import DICOMCore
import DICOMKit
import DICOMNetwork

/// Database manager for DICOM metadata indexing
actor DatabaseManager {
    private let connectionString: String
    private var instanceIndex: [String: DICOMMetadata] = [:] // sopInstanceUID -> metadata

    init(connectionString: String) throws {
        self.connectionString = connectionString

        // Validate connection string format
        if !connectionString.hasPrefix("sqlite://") && !connectionString.hasPrefix("postgres://") && !connectionString.isEmpty {
            throw ServerError.databaseError("Unsupported database type in connection string: \(connectionString)")
        }
    }

    /// Initialize the database connection
    func initialize() async throws {
        // Parse connection string and initialize
        if connectionString.hasPrefix("sqlite://") {
            try await initializeSQLite()
        } else if connectionString.hasPrefix("postgres://") {
            try await initializePostgreSQL()
        }
        // If empty, use in-memory storage (already initialized)
    }

    private func initializeSQLite() async throws {
        // TODO: Initialize SQLite database with schema
        // For Phase A, using in-memory storage
        guard connectionString.hasPrefix("sqlite://") else {
            throw ServerError.databaseError("Invalid SQLite connection string")
        }
    }

    private func initializePostgreSQL() async throws {
        // TODO: Initialize PostgreSQL database
        // For Phase A, not implemented
        guard connectionString.hasPrefix("postgres://") else {
            throw ServerError.databaseError("Invalid PostgreSQL connection string")
        }
        throw ServerError.databaseError("PostgreSQL support not yet implemented")
    }

    /// Index a DICOM file (a re-sent SOP Instance replaces the earlier entry)
    func index(filePath: String, metadata: DICOMMetadata) async throws {
        instanceIndex[metadata.sopInstanceUID] = metadata
    }

    /// Number of indexed instances
    var instanceCount: Int { instanceIndex.count }

    /// Query DICOM metadata for C-FIND.
    ///
    /// Returns one response Identifier per matching entity at `level` (PS3.4 C.4.1.1.3.2): every
    /// key of the request that the server supports at that level (zero length when it has no
    /// value), Query/Retrieve Level (0008,0052), and Retrieve AE Title (0008,0054) when given.
    func queryForFind(queryDataset: DataSet, level: QueryLevel, retrieveAETitle: String? = nil) async throws -> [DataSet] {
        let requested = QueryMatcher.requestedKeys(in: queryDataset, level: level)
        return entities(at: level)
            .filter { QueryMatcher.matches(group: $0, identifier: queryDataset, keys: requested) }
            .map { QueryMatcher.responseIdentifier(group: $0, keys: requested, level: level, retrieveAETitle: retrieveAETitle) }
    }

    /// Query DICOM metadata for C-MOVE/C-GET retrieval.
    ///
    /// Selects the entities at `level` whose keys match (Unique Keys with List of UID
    /// Matching, PS3.4 C.4.2.1.4.1 / C.4.3.1.3.1) and returns all their instances.
    func queryForRetrieve(queryDataset: DataSet, level: QueryLevel) async throws -> [DICOMMetadata] {
        let requested = QueryMatcher.requestedKeys(in: queryDataset, level: level)
        return entities(at: level)
            .filter { QueryMatcher.matches(group: $0, identifier: queryDataset, keys: requested) }
            .flatMap { $0 }
    }

    /// Instances grouped by the entity they belong to at `level`, in a stable order.
    private func entities(at level: QueryLevel) -> [[DICOMMetadata]] {
        let all = instanceIndex.values.sorted { $0.sopInstanceUID < $1.sopInstanceUID }
        let key: (DICOMMetadata) -> String
        switch level {
        case .patient: key = { $0.patientID ?? "" }
        case .study: key = { $0.studyInstanceUID ?? "" }
        case .series: key = { $0.seriesInstanceUID ?? "" }
        case .image: key = { $0.sopInstanceUID }
        }
        var order: [String] = []
        var groups: [String: [DICOMMetadata]] = [:]
        for m in all {
            let k = key(m)
            if groups[k] == nil { order.append(k) }
            groups[k, default: []].append(m)
        }
        return order.sorted().compactMap { groups[$0] }
    }

    /// Delete DICOM metadata
    func delete(sopInstanceUID: String) async throws {
        instanceIndex.removeValue(forKey: sopInstanceUID)
    }
}

// MARK: - Matching (PS3.4 C.2.2.2)

/// Query keys and matching rules of the server.
enum QueryMatcher {

    /// A key the server can match and return
    struct Key: Sendable {
        let tag: Tag
        /// Query/Retrieve level the attribute belongs to (Tables C.6-1..C.6-5)
        let level: QueryLevel
        let values: @Sendable ([DICOMMetadata]) -> [String]?
    }

    private static func first(_ get: @escaping @Sendable (DICOMMetadata) -> String?) -> @Sendable ([DICOMMetadata]) -> [String]? {
        { group in group.first.flatMap(get).map { [$0] } }
    }

    /// Supported keys. Required (R) and Unique (U) keys of PS3.4 2026a Tables C.6-1..C.6-5 are
    /// marked; the rest are optional keys the server stores.
    static let keys: [Key] = [
        // PATIENT — Table C.6-1 (and C.6-5 at the Study Root study level)
        Key(tag: .patientName, level: .patient, values: first(\.patientName)),           // R
        Key(tag: .patientID, level: .patient, values: first(\.patientID)),               // U (C.6-1), R (C.6-5)
        Key(tag: .patientBirthDate, level: .patient, values: first(\.patientBirthDate)),  // O
        Key(tag: .patientSex, level: .patient, values: first(\.patientSex)),             // O
        // STUDY — Tables C.6-2 / C.6-5
        Key(tag: .studyDate, level: .study, values: first(\.studyDate)),                 // R
        Key(tag: .studyTime, level: .study, values: first(\.studyTime)),                 // R
        Key(tag: .accessionNumber, level: .study, values: first(\.accessionNumber)),     // R
        Key(tag: .studyID, level: .study, values: first(\.studyID)),                     // R
        Key(tag: .studyInstanceUID, level: .study, values: first(\.studyInstanceUID)),   // U
        Key(tag: .studyDescription, level: .study, values: first(\.studyDescription)),   // O
        Key(tag: .modalitiesInStudy, level: .study, values: { group in                   // O
            let set = Set(group.compactMap(\.modality).filter { !$0.isEmpty })
            return set.isEmpty ? nil : set.sorted()
        }),
        // SERIES — Table C.6-3
        Key(tag: .modality, level: .series, values: first(\.modality)),                  // R
        Key(tag: .seriesNumber, level: .series, values: first(\.seriesNumber)),          // R
        Key(tag: .seriesInstanceUID, level: .series, values: first(\.seriesInstanceUID)), // U
        Key(tag: .seriesDescription, level: .series, values: first(\.seriesDescription)), // O
        // IMAGE — Table C.6-4
        Key(tag: .instanceNumber, level: .image, values: first(\.instanceNumber)),       // R
        Key(tag: .sopInstanceUID, level: .image, values: { $0.first.map { [$0.sopInstanceUID] } }), // U
        Key(tag: .sopClassUID, level: .image, values: first(\.sopClassUID)),             // O
    ]

    /// Elements of a request Identifier that are not keys (C.4.1.1.3.1)
    static let controlTags: Set<Tag> = [
        .queryRetrieveLevel,                       // (0008,0052)
        Tag(group: 0x0008, element: 0x0053),       // Query/Retrieve View
        .specificCharacterSet,                     // (0008,0005)
        Tag(group: 0x0008, element: 0x0201),       // Timezone Offset From UTC
    ]

    private static func rank(_ level: QueryLevel) -> Int {
        switch level {
        case .patient: return 0
        case .study: return 1
        case .series: return 2
        case .image: return 3
        }
    }

    /// Keys supported at a level: those of the level and of the levels above it.
    static func supportedKeys(at level: QueryLevel) -> [Key] {
        keys.filter { rank($0.level) <= rank(level) }
    }

    /// Supported keys present in the request Identifier, in tag order.
    static func requestedKeys(in identifier: DataSet, level: QueryLevel) -> [Key] {
        let present = Set(identifier.tags)
        return supportedKeys(at: level).filter { present.contains($0.tag) }.sorted { $0.tag < $1.tag }
    }

    /// Standard keys of the request the server does not support at this level; a non-empty
    /// result makes the pending status FF01 (PS3.4 Table C.4-1). Private elements are ignored.
    static func unsupportedKeys(in identifier: DataSet, level: QueryLevel) -> [Tag] {
        let supported = Set(supportedKeys(at: level).map(\.tag))
        return identifier.tags.filter { !$0.isPrivate && $0.group != 0x0000 && !controlTags.contains($0) && !supported.contains($0) }.sorted()
    }

    /// Whether every requested key matches the entity
    static func matches(group: [DICOMMetadata], identifier: DataSet, keys: [Key]) -> Bool {
        for key in keys {
            let pattern = identifier.string(for: key.tag) ?? ""
            let vr = DataSet.dictionaryVR(for: key.tag) ?? .LO
            if !matches(values: key.values(group), key: pattern, vr: vr) { return false }
        }
        return true
    }

    /// Builds the response Identifier (C.4.1.1.3.2)
    static func responseIdentifier(group: [DICOMMetadata], keys: [Key], level: QueryLevel, retrieveAETitle: String?) -> DataSet {
        var ds = DataSet()
        for key in keys {
            ds.set(string: (key.values(group) ?? []).joined(separator: "\\"), for: key.tag)
        }
        ds.set(string: level.queryRetrieveLevel, for: .queryRetrieveLevel)
        if let ae = retrieveAETitle {
            ds.set(string: ae, for: Tag(group: 0x0008, element: 0x0054)) // Retrieve AE Title
        }
        return ds
    }

    // MARK: Matching rules

    /// VRs for which C.2.2.2.4 defines Wild Card Matching
    static let wildcardVRs: Set<VR> = [.AE, .CS, .LO, .LT, .PN, .SH, .ST, .UC, .UR, .UT]

    /// Matches the entity's value(s) against one key.
    ///
    /// - Universal Matching (C.2.2.2.3): a zero-length key matches everything.
    /// - List of UID Matching (C.2.2.2.2): a UI key is a backslash-separated list.
    /// - Range Matching (C.2.2.2.5): a DA or TM key containing "-".
    /// - Wild Card Matching (C.2.2.2.4): only for the VRs listed there; case-sensitive except PN.
    /// - Single Value Matching (C.2.2.2.1): exact and case-sensitive except PN; DA by value,
    ///   TM by meaning (C.2.2.2.1.3), IS / DS numerically (C.2.2.2.1.4, implementation dependent).
    /// An entity without a value does not match a non-universal key.
    static func matches(values: [String]?, key: String, vr: VR) -> Bool {
        let key = key.trimmingCharacters(in: .whitespaces)
        if key.isEmpty { return true }
        guard let values, !values.isEmpty else { return false }
        return values.contains { matches(value: $0, key: key, vr: vr) }
    }

    static func matches(value: String, key: String, vr: VR) -> Bool {
        switch vr {
        case .UI:
            return key.components(separatedBy: "\\").contains { $0.trimmingCharacters(in: .whitespaces) == value }
        case .DA, .TM:
            if key.contains("-") { return rangeMatches(value: value, key: key, vr: vr) }
            if vr == .TM { return timeValue(value, upper: false) == timeValue(key, upper: false) }
            return value == key
        case .IS, .DS:
            if let a = Double(value.trimmingCharacters(in: .whitespaces)),
               let b = Double(key.trimmingCharacters(in: .whitespaces)) { return a == b }
            return value == key
        default:
            if wildcardVRs.contains(vr), key.contains("*") || key.contains("?") {
                return wildcardMatches(value, pattern: key, caseInsensitive: vr == .PN)
            }
            if vr == .PN { return value.caseInsensitiveCompare(key) == .orderedSame }
            return value == key
        }
    }

    /// "*" matches any sequence (including empty), "?" any single character
    static func wildcardMatches(_ value: String, pattern: String, caseInsensitive: Bool) -> Bool {
        let v = Array(caseInsensitive ? value.uppercased() : value)
        let p = Array(caseInsensitive ? pattern.uppercased() : pattern)
        var vi = 0, pi = 0, star = -1, mark = 0
        while vi < v.count {
            if pi < p.count, p[pi] == "?" || p[pi] == v[vi] {
                vi += 1; pi += 1
            } else if pi < p.count, p[pi] == "*" {
                star = pi; mark = vi; pi += 1
            } else if star >= 0 {
                pi = star + 1; mark += 1; vi = mark
            } else {
                return false
            }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }

    /// "<a>-<b>", "-<b>", "<a>-" inclusive (C.2.2.2.5.1 DA, C.2.2.2.5.2 TM)
    static func rangeMatches(value: String, key: String, vr: VR) -> Bool {
        let parts = key.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return false }
        if vr == .TM {
            guard let t = timeValue(value, upper: false) else { return false }
            if !parts[0].isEmpty { guard let lo = timeValue(parts[0], upper: false), t >= lo else { return false } }
            if !parts[1].isEmpty { guard let hi = timeValue(parts[1], upper: true), t <= hi else { return false } }
            return true
        }
        if !parts[0].isEmpty, value < parts[0] { return false }
        if !parts[1].isEmpty, value > parts[1] { return false }
        return true
    }

    /// Seconds since midnight of a TM value (HH, HHMM, HHMMSS, HHMMSS.F…); with `upper`, a
    /// partial time stands for the end of its last given unit.
    static func timeValue(_ tm: String, upper: Bool) -> Double? {
        let s = tm.replacingOccurrences(of: ":", with: "")
        let parts = s.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let digits = String(parts.first ?? "")
        guard [2, 4, 6].contains(digits.count), digits.allSatisfy(\.isNumber) else { return nil }
        let chars = Array(digits)
        func field(_ i: Int) -> Double? { i + 2 <= chars.count ? Double(String(chars[i..<i + 2])) : nil }
        var seconds = (field(0) ?? 0) * 3600
        if let m = field(2) { seconds += m * 60 } else if upper { seconds += 59 * 60 + 59.999999 }
        if let sec = field(4) { seconds += sec } else if upper && chars.count == 4 { seconds += 59.999999 }
        if parts.count == 2, let frac = Double("0." + parts[1]) {
            seconds += frac
        } else if upper && chars.count == 6 {
            seconds += 0.999999
        }
        return seconds
    }
}

/// DICOM metadata for database indexing
struct DICOMMetadata: Sendable, Codable {
    let patientID: String?
    let patientName: String?
    let studyInstanceUID: String?
    let studyDate: String?
    let studyDescription: String?
    let seriesInstanceUID: String?
    let seriesNumber: String?
    let modality: String?
    let sopInstanceUID: String
    let sopClassUID: String?
    let instanceNumber: String?
    let filePath: String
    let studyTime: String?
    let accessionNumber: String?
    let studyID: String?
    let patientBirthDate: String?
    let patientSex: String?
    let seriesDescription: String?
    /// Transfer Syntax UID of the stored file (plumbing)
    let transferSyntaxUID: String?

    init(
        patientID: String?,
        patientName: String?,
        studyInstanceUID: String?,
        studyDate: String?,
        studyDescription: String?,
        seriesInstanceUID: String?,
        seriesNumber: String?,
        modality: String?,
        sopInstanceUID: String,
        sopClassUID: String?,
        instanceNumber: String?,
        filePath: String,
        studyTime: String? = nil,
        accessionNumber: String? = nil,
        studyID: String? = nil,
        patientBirthDate: String? = nil,
        patientSex: String? = nil,
        seriesDescription: String? = nil,
        transferSyntaxUID: String? = nil
    ) {
        self.patientID = patientID
        self.patientName = patientName
        self.studyInstanceUID = studyInstanceUID
        self.studyDate = studyDate
        self.studyDescription = studyDescription
        self.seriesInstanceUID = seriesInstanceUID
        self.seriesNumber = seriesNumber
        self.modality = modality
        self.sopInstanceUID = sopInstanceUID
        self.sopClassUID = sopClassUID
        self.instanceNumber = instanceNumber
        self.filePath = filePath
        self.studyTime = studyTime
        self.accessionNumber = accessionNumber
        self.studyID = studyID
        self.patientBirthDate = patientBirthDate
        self.patientSex = patientSex
        self.seriesDescription = seriesDescription
        self.transferSyntaxUID = transferSyntaxUID
    }

    /// Metadata of a stored instance, read from its data set
    init(dataSet: DataSet, filePath: String, sopInstanceUID: String? = nil, sopClassUID: String? = nil, transferSyntaxUID: String? = nil) {
        self.init(
            patientID: dataSet.string(for: .patientID),
            patientName: dataSet.string(for: .patientName),
            studyInstanceUID: dataSet.string(for: .studyInstanceUID),
            studyDate: dataSet.string(for: .studyDate),
            studyDescription: dataSet.string(for: .studyDescription),
            seriesInstanceUID: dataSet.string(for: .seriesInstanceUID),
            seriesNumber: dataSet.string(for: .seriesNumber),
            modality: dataSet.string(for: .modality),
            sopInstanceUID: sopInstanceUID ?? dataSet.string(for: .sopInstanceUID) ?? "",
            sopClassUID: sopClassUID ?? dataSet.string(for: .sopClassUID),
            instanceNumber: dataSet.string(for: .instanceNumber),
            filePath: filePath,
            studyTime: dataSet.string(for: .studyTime),
            accessionNumber: dataSet.string(for: .accessionNumber),
            studyID: dataSet.string(for: .studyID),
            patientBirthDate: dataSet.string(for: .patientBirthDate),
            patientSex: dataSet.string(for: .patientSex),
            seriesDescription: dataSet.string(for: .seriesDescription),
            transferSyntaxUID: transferSyntaxUID
        )
    }
}
