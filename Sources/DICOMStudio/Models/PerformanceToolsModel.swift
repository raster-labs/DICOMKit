// PerformanceToolsModel.swift
// DICOMStudio
//
// DICOM Studio — Data models for Performance & Developer Tools (Milestone 13)
// Reference: DICOM PS3.2 (Conformance), PS3.5 (Data Structures), PS3.6 (Data Dictionary)
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data: record types (DICOMTagEntry, UIDEntry,
// TransferSyntaxInfoEntry, SOPClassEntry) whose values live in PerformanceToolsHelpers.swift, and UI enums.
// TagGroupFilter's group prefixes (0010 patient, 0020 study, 0008/0018 series and equipment, 0028 image) are
// a browsing heuristic, not a PS3.6 classification; PS3.6 Table 6-1 does not group tags by entity.

import Foundation

// MARK: - Navigation Tab

/// Navigation tabs for the Performance & Developer Tools feature.
public enum PerformanceToolsTab: String, Sendable, Equatable, Hashable, CaseIterable {
    case performanceDashboard  = "PERFORMANCE_DASHBOARD"
    case cacheManagement       = "CACHE_MANAGEMENT"
    case tagDictionary         = "TAG_DICTIONARY"
    case uidLookup             = "UID_LOOKUP"
    case transferSyntaxInfo    = "TRANSFER_SYNTAX_INFO"
    case conformanceStatement  = "CONFORMANCE_STATEMENT"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .performanceDashboard: return "Performance Dashboard"
        case .cacheManagement:      return "Cache Management"
        case .tagDictionary:        return "Tag Dictionary"
        case .uidLookup:            return "UID Lookup"
        case .transferSyntaxInfo:   return "Transfer Syntaxes"
        case .conformanceStatement: return "Conformance Statement"
        }
    }

    /// SF Symbol name for this tab.
    public var sfSymbol: String {
        switch self {
        case .performanceDashboard: return "speedometer"
        case .cacheManagement:      return "internaldrive"
        case .tagDictionary:        return "tag"
        case .uidLookup:            return "magnifyingglass"
        case .transferSyntaxInfo:   return "arrow.triangle.2.circlepath"
        case .conformanceStatement: return "checkmark.seal"
        }
    }
}

// MARK: - 13.1 Performance Dashboard

/// Types of benchmarks that can be run.
public enum BenchmarkType: String, Sendable, Equatable, Hashable, CaseIterable {
    case parseFiles       = "PARSE_FILES"
    case renderFrames     = "RENDER_FRAMES"
    case windowLevel      = "WINDOW_LEVEL"
    case networkLatency   = "NETWORK_LATENCY"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .parseFiles:     return "Parse 100 Files"
        case .renderFrames:   return "Render 100 Frames"
        case .windowLevel:    return "Window/Level 1000×"
        case .networkLatency: return "Network Round-Trip"
        }
    }

    /// SF Symbol for this benchmark type.
    public var sfSymbol: String {
        switch self {
        case .parseFiles:     return "doc.text.magnifyingglass"
        case .renderFrames:   return "photo.stack"
        case .windowLevel:    return "slider.horizontal.3"
        case .networkLatency: return "network"
        }
    }

    /// Brief description of what this benchmark measures.
    public var description: String {
        switch self {
        case .parseFiles:
            return "Full parse vs. metadata-only parse across 100 synthetic DICOM files"
        case .renderFrames:
            return "Image render time with and without SIMD acceleration"
        case .windowLevel:
            return "Window/level computation throughput over 1000 iterations"
        case .networkLatency:
            return "Round-trip latency to the configured DICOM server"
        }
    }
}

/// Status of a benchmark run.
public enum BenchmarkStatus: String, Sendable, Equatable, Hashable {
    case idle      = "IDLE"
    case running   = "RUNNING"
    case completed = "COMPLETED"
    case failed    = "FAILED"

    /// Human-readable display label.
    public var displayLabel: String {
        switch self {
        case .idle:      return "Idle"
        case .running:   return "Running…"
        case .completed: return "Completed"
        case .failed:    return "Failed"
        }
    }

    /// SF Symbol for the status.
    public var sfSymbol: String {
        switch self {
        case .idle:      return "circle"
        case .running:   return "arrow.circlepath"
        case .completed: return "checkmark.circle"
        case .failed:    return "xmark.circle"
        }
    }
}

/// A single benchmark result entry.
public struct BenchmarkResult: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let type: BenchmarkType
    /// Total elapsed time in milliseconds.
    public var durationMs: Double
    /// Number of iterations completed.
    public var iterations: Int
    /// Status of this benchmark run.
    public var status: BenchmarkStatus
    /// Optional error message when status is `.failed`.
    public var errorMessage: String?
    /// Timestamp when the benchmark started.
    public var startedAt: Date
    /// Timestamp when the benchmark finished (nil if still running).
    public var completedAt: Date?

    /// Average time per iteration in milliseconds.
    public var averageIterationMs: Double {
        guard iterations > 0 else { return 0 }
        return durationMs / Double(iterations)
    }

    public init(
        id: UUID = UUID(),
        type: BenchmarkType,
        durationMs: Double = 0,
        iterations: Int = 0,
        status: BenchmarkStatus = .idle,
        errorMessage: String? = nil,
        startedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.durationMs = durationMs
        self.iterations = iterations
        self.status = status
        self.errorMessage = errorMessage
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

/// Real-time performance metrics snapshot.
public struct PerformanceMetrics: Sendable, Hashable {
    /// Most recent full file parse time in milliseconds.
    public var parseFullMs: Double
    /// Most recent metadata-only parse time in milliseconds.
    public var parseMetadataOnlyMs: Double
    /// Most recent image render time in milliseconds.
    public var renderTimeMs: Double
    /// Image cache hit rate (0.0–1.0).
    public var cacheHitRate: Double
    /// Resident memory in megabytes.
    public var memoryResidentMB: Double
    /// Virtual memory in megabytes.
    public var memoryVirtualMB: Double
    /// Number of currently active memory-mapped files.
    public var memoryMappedFileCount: Int

    public init(
        parseFullMs: Double = 0,
        parseMetadataOnlyMs: Double = 0,
        renderTimeMs: Double = 0,
        cacheHitRate: Double = 0,
        memoryResidentMB: Double = 0,
        memoryVirtualMB: Double = 0,
        memoryMappedFileCount: Int = 0
    ) {
        self.parseFullMs = parseFullMs
        self.parseMetadataOnlyMs = parseMetadataOnlyMs
        self.renderTimeMs = renderTimeMs
        self.cacheHitRate = cacheHitRate
        self.memoryResidentMB = memoryResidentMB
        self.memoryVirtualMB = memoryVirtualMB
        self.memoryMappedFileCount = memoryMappedFileCount
    }
}

// MARK: - 13.2 Cache Management

/// Types of caches managed by DICOMKit.
public enum CacheType: String, Sendable, Equatable, Hashable, CaseIterable {
    case image     = "IMAGE"
    case thumbnail = "THUMBNAIL"
    case network   = "NETWORK"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .image:     return "Image Cache"
        case .thumbnail: return "Thumbnail Cache"
        case .network:   return "Network Cache"
        }
    }

    /// SF Symbol for this cache type.
    public var sfSymbol: String {
        switch self {
        case .image:     return "photo"
        case .thumbnail: return "photo.stack"
        case .network:   return "network"
        }
    }
}

/// Metadata about a single item stored in the cache.
public struct CacheItemInfo: Sendable, Identifiable, Hashable {
    public let id: UUID
    /// Human-readable cache key.
    public var key: String
    /// Size of this entry in bytes.
    public var sizeBytes: Int
    /// Age of the entry since it was inserted.
    public var insertedAt: Date
    /// Most recent access time.
    public var lastAccessedAt: Date
    /// Cache type this entry belongs to.
    public var cacheType: CacheType

    /// Age of the entry in seconds.
    public var ageSeconds: TimeInterval {
        Date().timeIntervalSince(insertedAt)
    }

    public init(
        id: UUID = UUID(),
        key: String,
        sizeBytes: Int,
        insertedAt: Date = Date(),
        lastAccessedAt: Date = Date(),
        cacheType: CacheType
    ) {
        self.id = id
        self.key = key
        self.sizeBytes = sizeBytes
        self.insertedAt = insertedAt
        self.lastAccessedAt = lastAccessedAt
        self.cacheType = cacheType
    }
}

/// Aggregate statistics for a single cache.
public struct CacheStats: Sendable, Hashable {
    public var cacheType: CacheType
    /// Bytes currently used.
    public var currentSizeBytes: Int
    /// Maximum allowed bytes.
    public var maximumSizeBytes: Int
    /// Number of items currently cached.
    public var itemCount: Int
    /// Cache hit rate (0.0–1.0).
    public var hitRate: Double
    /// Cache miss rate (0.0–1.0).
    public var missRate: Double

    /// Fill percentage (0.0–100.0).
    public var fillPercentage: Double {
        guard maximumSizeBytes > 0 else { return 0 }
        return min(100.0, Double(currentSizeBytes) / Double(maximumSizeBytes) * 100.0)
    }

    public init(
        cacheType: CacheType,
        currentSizeBytes: Int = 0,
        maximumSizeBytes: Int = 256 * 1024 * 1024,
        itemCount: Int = 0,
        hitRate: Double = 0,
        missRate: Double = 0
    ) {
        self.cacheType = cacheType
        self.currentSizeBytes = currentSizeBytes
        self.maximumSizeBytes = maximumSizeBytes
        self.itemCount = itemCount
        self.hitRate = hitRate
        self.missRate = missRate
    }
}

// MARK: - 13.3 Tag Dictionary Explorer

/// Filter groups for browsing the DICOM tag dictionary.
public enum TagGroupFilter: String, Sendable, Equatable, Hashable, CaseIterable {
    case all        = "ALL"
    case patient    = "PATIENT"
    case study      = "STUDY"
    case series     = "SERIES"
    case equipment  = "EQUIPMENT"
    case image      = "IMAGE"
    case retired    = "RETIRED"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .all:       return "All Tags"
        case .patient:   return "Patient"
        case .study:     return "Study"
        case .series:    return "Series"
        case .equipment: return "Equipment"
        case .image:     return "Image"
        case .retired:   return "Retired"
        }
    }

    /// Tag group hex prefix (nil for .all and .retired).
    public var groupHexPrefix: String? {
        switch self {
        case .all:       return nil
        case .patient:   return "0010"
        case .study:     return "0020"
        case .series:    return "0008"
        case .equipment: return "0008"
        case .image:     return "0028"
        case .retired:   return nil
        }
    }
}

/// A single entry in the DICOM tag dictionary.
public struct DICOMTagEntry: Sendable, Identifiable, Hashable {
    public let id: UUID
    /// Tag in (GGGG,EEEE) format, e.g. "(0010,0010)".
    public var tag: String
    /// Human-readable tag name, e.g. "Patient's Name".
    public var name: String
    /// Keyword as defined in the DICOM standard, e.g. "PatientName".
    public var keyword: String
    /// Value Representation code, e.g. "PN".
    public var vr: String
    /// Value Multiplicity, e.g. "1" or "1-n".
    public var vm: String
    /// Whether this tag is retired in the current standard.
    public var isRetired: Bool
    /// Optional description / usage notes.
    public var tagDescription: String

    public init(
        id: UUID = UUID(),
        tag: String,
        name: String,
        keyword: String,
        vr: String,
        vm: String,
        isRetired: Bool = false,
        tagDescription: String = ""
    ) {
        self.id = id
        self.tag = tag
        self.name = name
        self.keyword = keyword
        self.vr = vr
        self.vm = vm
        self.isRetired = isRetired
        self.tagDescription = tagDescription
    }
}

// MARK: - 13.4 UID Lookup Tool

/// Categories of DICOM UIDs.
public enum UIDCategory: String, Sendable, Equatable, Hashable, CaseIterable {
    case transferSyntax = "TRANSFER_SYNTAX"
    case sopClass       = "SOP_CLASS"
    case wellKnown      = "WELL_KNOWN"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .transferSyntax: return "Transfer Syntax"
        case .sopClass:       return "SOP Class"
        case .wellKnown:      return "Well-Known"
        }
    }
}

/// A single registered UID entry.
public struct UIDEntry: Sendable, Identifiable, Hashable {
    public let id: UUID
    /// The UID string, e.g. "1.2.840.10008.1.2.1".
    public var uid: String
    /// Human-readable name.
    public var name: String
    /// Category of this UID.
    public var category: UIDCategory
    /// Brief description.
    public var uidDescription: String

    public init(
        id: UUID = UUID(),
        uid: String,
        name: String,
        category: UIDCategory,
        uidDescription: String = ""
    ) {
        self.id = id
        self.uid = uid
        self.name = name
        self.category = category
        self.uidDescription = uidDescription
    }
}

/// UID validation result.
public struct UIDValidationResult: Sendable, Hashable {
    public var uid: String
    public var isValid: Bool
    public var errorMessage: String?

    public init(uid: String, isValid: Bool, errorMessage: String? = nil) {
        self.uid = uid
        self.isValid = isValid
        self.errorMessage = errorMessage
    }
}

// MARK: - 13.5 Transfer Syntax Information

/// Compression type of a transfer syntax.
public enum TSCompressionType: String, Sendable, Equatable, Hashable, CaseIterable {
    case none      = "NONE"
    case lossless  = "LOSSLESS"
    case lossy     = "LOSSY"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .none:     return "Uncompressed"
        case .lossless: return "Lossless"
        case .lossy:    return "Lossy"
        }
    }
}

/// Byte order of a transfer syntax.
public enum TSByteOrder: String, Sendable, Equatable, Hashable, CaseIterable {
    case littleEndian = "LITTLE_ENDIAN"
    case bigEndian    = "BIG_ENDIAN"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .littleEndian: return "Little Endian"
        case .bigEndian:    return "Big Endian"
        }
    }
}

/// VR encoding mode.
public enum TSVREncoding: String, Sendable, Equatable, Hashable, CaseIterable {
    case explicit = "EXPLICIT"
    case implicit = "IMPLICIT"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .explicit: return "Explicit VR"
        case .implicit: return "Implicit VR"
        }
    }
}

/// DICOMKit support status for a transfer syntax.
public enum TSSupportStatus: String, Sendable, Equatable, Hashable, CaseIterable {
    case supported          = "SUPPORTED"
    case partiallySupported = "PARTIALLY_SUPPORTED"
    case notSupported       = "NOT_SUPPORTED"

    /// Human-readable display label.
    public var displayLabel: String {
        switch self {
        case .supported:          return "Supported"
        case .partiallySupported: return "Partial"
        case .notSupported:       return "Not Supported"
        }
    }

    /// SF Symbol for status.
    public var sfSymbol: String {
        switch self {
        case .supported:          return "checkmark.circle"
        case .partiallySupported: return "exclamationmark.circle"
        case .notSupported:       return "xmark.circle"
        }
    }
}

/// Detailed information about a single transfer syntax.
public struct TransferSyntaxInfoEntry: Sendable, Identifiable, Hashable {
    public let id: UUID
    /// Transfer Syntax UID.
    public var uid: String
    /// Human-readable name.
    public var name: String
    /// Brief description.
    public var tsDescription: String
    public var compressionType: TSCompressionType
    public var byteOrder: TSByteOrder
    public var vrEncoding: TSVREncoding
    public var supportStatus: TSSupportStatus

    public init(
        id: UUID = UUID(),
        uid: String,
        name: String,
        tsDescription: String = "",
        compressionType: TSCompressionType,
        byteOrder: TSByteOrder,
        vrEncoding: TSVREncoding,
        supportStatus: TSSupportStatus
    ) {
        self.id = id
        self.uid = uid
        self.name = name
        self.tsDescription = tsDescription
        self.compressionType = compressionType
        self.byteOrder = byteOrder
        self.vrEncoding = vrEncoding
        self.supportStatus = supportStatus
    }
}

// MARK: - 13.6 DICOM Conformance Statement

/// Role a DICOMKit SOP Class implementation plays.
public enum SOPClassRole: String, Sendable, Equatable, Hashable, CaseIterable {
    case scu  = "SCU"
    case scp  = "SCP"
    case both = "BOTH"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .scu:  return "SCU (Service Class User)"
        case .scp:  return "SCP (Service Class Provider)"
        case .both: return "SCU + SCP"
        }
    }
}

/// A single SOP Class entry in the conformance statement.
public struct SOPClassEntry: Sendable, Identifiable, Hashable {
    public let id: UUID
    /// SOP Class UID.
    public var uid: String
    /// Human-readable name.
    public var name: String
    /// Role DICOMKit supports for this SOP Class.
    public var role: SOPClassRole
    /// Transfer Syntax UIDs supported for this SOP Class.
    public var supportedTransferSyntaxUIDs: [String]

    public init(
        id: UUID = UUID(),
        uid: String,
        name: String,
        role: SOPClassRole,
        supportedTransferSyntaxUIDs: [String] = []
    ) {
        self.id = id
        self.uid = uid
        self.name = name
        self.role = role
        self.supportedTransferSyntaxUIDs = supportedTransferSyntaxUIDs
    }
}

/// Category of a DICOM conformance service.
public enum ConformanceServiceCategory: String, Sendable, Equatable, Hashable, CaseIterable {
    case dicomNetworking = "DICOM_NETWORKING"
    case dicomweb        = "DICOMWEB"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .dicomNetworking: return "DICOM Networking (DIMSE)"
        case .dicomweb:        return "DICOMweb (RESTful)"
        }
    }
}

/// Capability status for a conformance service.
public enum ConformanceCapabilityStatus: String, Sendable, Equatable, Hashable {
    case supported    = "SUPPORTED"
    case notSupported = "NOT_SUPPORTED"
    case planned      = "PLANNED"

    /// Human-readable display label.
    public var displayLabel: String {
        switch self {
        case .supported:    return "Supported"
        case .notSupported: return "Not Supported"
        case .planned:      return "Planned"
        }
    }

    /// SF Symbol for this status.
    public var sfSymbol: String {
        switch self {
        case .supported:    return "checkmark.circle.fill"
        case .notSupported: return "xmark.circle"
        case .planned:      return "clock.circle"
        }
    }
}

/// A row in the conformance capability matrix.
public struct ConformanceCapabilityEntry: Sendable, Identifiable, Hashable {
    public let id: UUID
    public var serviceCategory: ConformanceServiceCategory
    /// Short name for the service (e.g. "C-ECHO", "WADO-RS").
    public var serviceName: String
    public var status: ConformanceCapabilityStatus
    /// Optional notes about support level or limitations.
    public var notes: String

    public init(
        id: UUID = UUID(),
        serviceCategory: ConformanceServiceCategory,
        serviceName: String,
        status: ConformanceCapabilityStatus,
        notes: String = ""
    ) {
        self.id = id
        self.serviceCategory = serviceCategory
        self.serviceName = serviceName
        self.status = status
        self.notes = notes
    }
}
