// ArchiveManagementViewModel.swift
// DICOMStudio
//
// DICOM Studio — ViewModel for Archive Management feature (dicom-archive)
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (dicom-archive command lines and
// placeholder statistics).

import Foundation
import Observation

/// ViewModel for the Archive Management feature.
///
/// Manages a local DICOM archive index, supporting import, export,
/// browse, search, and statistics.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
@Observable
@MainActor
public final class ArchiveManagementViewModel {
    private let service: ArchiveManagementService

    // MARK: - Navigation

    public var activeTab: ArchiveManagementTab = .browse

    // MARK: - Browse

    public var archivePath: String = ""
    public var patients: [ArchivePatientEntry] = []
    public var selectedPatientID: UUID? = nil

    // MARK: - Import

    public var importOptions: ArchiveImportOptions = ArchiveImportOptions()
    public var importResult: String = ""

    // MARK: - Export

    public var exportOptions: ArchiveExportOptions = ArchiveExportOptions()
    public var exportResult: String = ""

    // MARK: - Search

    public var searchQuery: ArchiveSearchQuery = ArchiveSearchQuery()
    public var searchResults: [ArchiveStudyEntry] = []

    // MARK: - Statistics

    public var statistics: ArchiveStatistics = ArchiveStatistics()

    // MARK: - UI State

    public var isLoading: Bool = false
    public var errorMessage: String? = nil
    public var statusMessage: String = "No archive loaded."

    public init(service: ArchiveManagementService = ArchiveManagementService()) {
        self.service = service
        self.archivePath = service.archivePath
        self.patients = service.patients
        self.statistics = service.statistics
    }

    // MARK: - Archive Path

    public func loadArchive() {
        guard !archivePath.isEmpty else {
            errorMessage = "Please provide an archive directory path."
            return
        }
        service.archivePath = archivePath
        isLoading = true
        statusMessage = "Loading archive from \(archivePath)…"
        // Populate with placeholder data to reflect CLI command intent
        let placeholder = ArchiveStatistics(
            patientCount: 0,
            studyCount: 0,
            seriesCount: 0,
            instanceCount: 0,
            indexVersion: "1.0",
            lastModified: Date()
        )
        service.setStatistics(placeholder)
        statistics = service.statistics
        patients = service.patients
        isLoading = false
        statusMessage = "Run: dicom-archive list --archive \"\(archivePath)\""
    }

    // MARK: - Import

    public func runImport() {
        guard !importOptions.sourceDirectory.isEmpty else {
            errorMessage = "Source directory is required."
            return
        }
        var cmd = "dicom-archive import \"\(importOptions.sourceDirectory)\" --archive \"\(archivePath)\""
        if importOptions.isRecursive { cmd += " --recursive" }
        if importOptions.overwriteExisting { cmd += " --overwrite" }
        if importOptions.organizeByPatient { cmd += " --organize-by-patient" }
        if importOptions.createDICOMDIR { cmd += " --create-dicomdir" }
        importResult = cmd
        statusMessage = "Import command ready."
    }

    // MARK: - Export

    public func runExport() {
        guard !exportOptions.outputDirectory.isEmpty else {
            errorMessage = "Output directory is required."
            return
        }
        var cmd = "dicom-archive export --archive \"\(archivePath)\" \"\(exportOptions.outputDirectory)\""
        if exportOptions.createDICOMDIR { cmd += " --create-dicomdir" }
        if exportOptions.flattenHierarchy { cmd += " --flatten" }
        exportResult = cmd
        statusMessage = "Export command ready."
    }

    // MARK: - Search

    public func runSearch() {
        guard searchQuery.isNonEmpty else {
            errorMessage = "Enter at least one search criterion."
            return
        }
        // Build CLI command preview
        var args: [String] = ["dicom-archive search --archive \"\(archivePath)\""]
        if !searchQuery.patientName.isEmpty { args.append("--patient-name \"\(searchQuery.patientName)\"") }
        if !searchQuery.patientID.isEmpty   { args.append("--patient-id \"\(searchQuery.patientID)\"") }
        if !searchQuery.studyDate.isEmpty   { args.append("--study-date \"\(searchQuery.studyDate)\"") }
        if !searchQuery.modality.isEmpty    { args.append("--modality \"\(searchQuery.modality)\"") }
        if !searchQuery.accessionNumber.isEmpty { args.append("--accession \"\(searchQuery.accessionNumber)\"") }
        statusMessage = args.joined(separator: " \\\n  ")
        searchResults = []
    }

    public func clearSearch() {
        searchQuery = ArchiveSearchQuery()
        searchResults = []
        statusMessage = "Search cleared."
    }

    // MARK: - Statistics

    public func refreshStatistics() {
        statistics = service.statistics
        statusMessage = "Run: dicom-archive stats --archive \"\(archivePath)\""
    }
}
