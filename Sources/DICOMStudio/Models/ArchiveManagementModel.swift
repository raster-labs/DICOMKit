// ArchiveManagementModel.swift
// DICOMStudio
//
// DICOM Studio — Data models for Archive Management (dicom-archive)
// Reference: DICOM PS3.10 (Media Storage and File Format)
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (dicom-archive index entries, options
// and search fields; `indexVersion` is dicom-archive's).

import Foundation

// MARK: - Navigation Tab

/// Navigation tabs for the Archive Management feature.
public enum ArchiveManagementTab: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case browse    = "BROWSE"
    case importTab = "IMPORT"
    case exportTab = "EXPORT"
    case search    = "SEARCH"
    case stats     = "STATISTICS"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .browse:    return "Browse"
        case .importTab: return "Import"
        case .exportTab: return "Export"
        case .search:    return "Search"
        case .stats:     return "Statistics"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .browse:    return "archivebox"
        case .importTab: return "square.and.arrow.down"
        case .exportTab: return "square.and.arrow.up"
        case .search:    return "magnifyingglass"
        case .stats:     return "chart.bar.fill"
        }
    }
}

// MARK: - Archive Patient

/// A patient entry in the DICOM archive index.
public struct ArchivePatientEntry: Sendable, Identifiable, Hashable {
    public let id: UUID
    public var patientName: String
    public var patientID: String
    public var studyCount: Int
    public var instanceCount: Int
    public var totalSizeBytes: Int64

    public init(
        id: UUID = UUID(),
        patientName: String,
        patientID: String,
        studyCount: Int = 0,
        instanceCount: Int = 0,
        totalSizeBytes: Int64 = 0
    ) {
        self.id = id
        self.patientName = patientName
        self.patientID = patientID
        self.studyCount = studyCount
        self.instanceCount = instanceCount
        self.totalSizeBytes = totalSizeBytes
    }

    /// Formatted file size string.
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
    }
}

// MARK: - Archive Study Entry

/// A study entry in the DICOM archive index.
public struct ArchiveStudyEntry: Sendable, Identifiable, Hashable {
    public let id: UUID
    public var studyInstanceUID: String
    public var studyDate: String
    public var studyDescription: String
    public var modality: String
    public var accessionNumber: String
    public var seriesCount: Int
    public var instanceCount: Int
    public var totalSizeBytes: Int64

    public init(
        id: UUID = UUID(),
        studyInstanceUID: String,
        studyDate: String = "",
        studyDescription: String = "",
        modality: String = "",
        accessionNumber: String = "",
        seriesCount: Int = 0,
        instanceCount: Int = 0,
        totalSizeBytes: Int64 = 0
    ) {
        self.id = id
        self.studyInstanceUID = studyInstanceUID
        self.studyDate = studyDate
        self.studyDescription = studyDescription
        self.modality = modality
        self.accessionNumber = accessionNumber
        self.seriesCount = seriesCount
        self.instanceCount = instanceCount
        self.totalSizeBytes = totalSizeBytes
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
    }
}

// MARK: - Archive Statistics

/// Summary statistics for the entire archive.
public struct ArchiveStatistics: Sendable, Hashable {
    public var patientCount: Int
    public var studyCount: Int
    public var seriesCount: Int
    public var instanceCount: Int
    public var totalSizeBytes: Int64
    public var indexVersion: String
    public var lastModified: Date?

    public init(
        patientCount: Int = 0,
        studyCount: Int = 0,
        seriesCount: Int = 0,
        instanceCount: Int = 0,
        totalSizeBytes: Int64 = 0,
        indexVersion: String = "1.0",
        lastModified: Date? = nil
    ) {
        self.patientCount = patientCount
        self.studyCount = studyCount
        self.seriesCount = seriesCount
        self.instanceCount = instanceCount
        self.totalSizeBytes = totalSizeBytes
        self.indexVersion = indexVersion
        self.lastModified = lastModified
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
    }
}

// MARK: - Archive Import Options

/// Options controlling how files are imported into the archive.
public struct ArchiveImportOptions: Sendable, Hashable {
    public var sourceDirectory: String
    public var isRecursive: Bool
    public var overwriteExisting: Bool
    public var organizeByPatient: Bool
    public var createDICOMDIR: Bool

    public init(
        sourceDirectory: String = "",
        isRecursive: Bool = true,
        overwriteExisting: Bool = false,
        organizeByPatient: Bool = true,
        createDICOMDIR: Bool = false
    ) {
        self.sourceDirectory = sourceDirectory
        self.isRecursive = isRecursive
        self.overwriteExisting = overwriteExisting
        self.organizeByPatient = organizeByPatient
        self.createDICOMDIR = createDICOMDIR
    }
}

// MARK: - Archive Export Options

/// Options controlling how files are exported from the archive.
public struct ArchiveExportOptions: Sendable, Hashable {
    public var outputDirectory: String
    public var includeAll: Bool
    public var createDICOMDIR: Bool
    public var flattenHierarchy: Bool

    public init(
        outputDirectory: String = "",
        includeAll: Bool = true,
        createDICOMDIR: Bool = false,
        flattenHierarchy: Bool = false
    ) {
        self.outputDirectory = outputDirectory
        self.includeAll = includeAll
        self.createDICOMDIR = createDICOMDIR
        self.flattenHierarchy = flattenHierarchy
    }
}

// MARK: - Archive Search Query

/// Query parameters for searching the archive.
public struct ArchiveSearchQuery: Sendable, Hashable {
    public var patientName: String
    public var patientID: String
    public var studyDate: String
    public var modality: String
    public var accessionNumber: String

    public init(
        patientName: String = "",
        patientID: String = "",
        studyDate: String = "",
        modality: String = "",
        accessionNumber: String = ""
    ) {
        self.patientName = patientName
        self.patientID = patientID
        self.studyDate = studyDate
        self.modality = modality
        self.accessionNumber = accessionNumber
    }

    /// Returns true if at least one field is non-empty.
    public var isNonEmpty: Bool {
        !patientName.isEmpty || !patientID.isEmpty || !studyDate.isEmpty ||
        !modality.isEmpty || !accessionNumber.isEmpty
    }
}
