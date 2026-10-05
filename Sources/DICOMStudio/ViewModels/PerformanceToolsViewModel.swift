// PerformanceToolsViewModel.swift
// DICOMStudio
//
// DICOM Studio — ViewModel for Performance & Developer Tools (Milestone 13)
// Reference: DICOM PS3.2 (Conformance), PS3.5 (Data Structures), PS3.6 (Data Dictionary)
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data of its own: UI state over
// PerformanceToolsService; the two Transfer Syntax UID defaults are registered in PS3.6 2026a Table A-1 and
// the benchmark figures are simulated, not standard values.

import Foundation
import Observation

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
@Observable
public final class PerformanceToolsViewModel {
    private let service: PerformanceToolsService

    // Navigation
    public var activeTab: PerformanceToolsTab = .performanceDashboard
    public var isLoading: Bool = false
    public var errorMessage: String? = nil

    // 13.1 Performance Dashboard
    public var metrics: PerformanceMetrics = PerformanceMetrics()
    public var benchmarkResults: [BenchmarkResult] = []
    public var isRunningBenchmark: Bool = false
    public var benchmarkExportCSV: String = ""

    // 13.2 Cache Management
    public var cacheStats: [CacheType: CacheStats] = [:]
    public var cacheItems: [CacheType: [CacheItemInfo]] = [:]
    public var selectedCacheType: CacheType = .image
    public var isClearCacheConfirmPresented: Bool = false

    // 13.3 Tag Dictionary
    public var tagEntries: [DICOMTagEntry] = []
    public var tagSearchQuery: String = ""
    public var tagGroupFilter: TagGroupFilter = .all
    public var selectedTagEntry: DICOMTagEntry? = nil

    // 13.4 UID Lookup
    public var uidEntries: [UIDEntry] = []
    public var uidSearchQuery: String = ""
    public var lastGeneratedUID: String = ""
    public var uidValidationInput: String = ""
    public var uidValidationResult: UIDValidationResult? = nil
    public var isCopyUIDConfirmPresented: Bool = false

    // 13.5 Transfer Syntax Info
    public var transferSyntaxEntries: [TransferSyntaxInfoEntry] = []
    public var selectedSourceSyntaxUID: String = "1.2.840.10008.1.2.1"
    public var selectedTargetSyntaxUID: String = "1.2.840.10008.1.2.4.70"

    // 13.6 Conformance Statement
    public var sopClassEntries: [SOPClassEntry] = []
    public var capabilityEntries: [ConformanceCapabilityEntry] = []
    public var conformanceServiceFilter: ConformanceServiceCategory = .dicomNetworking

    public init(service: PerformanceToolsService = PerformanceToolsService()) {
        self.service = service
        loadFromService()
    }

    // MARK: - Load

    public func loadFromService() {
        metrics = service.getMetrics()
        benchmarkResults = service.getBenchmarkResults()
        for ct in CacheType.allCases {
            cacheStats[ct] = service.getCacheStats(for: ct)
            cacheItems[ct] = service.getCacheItems(for: ct)
        }
        tagEntries = service.getTagEntries()
        tagSearchQuery = service.getTagSearchQuery()
        tagGroupFilter = service.getTagGroupFilter()
        uidEntries = service.getUIDEntries()
        uidSearchQuery = service.getUIDSearchQuery()
        lastGeneratedUID = service.getLastGeneratedUID()
        uidValidationResult = service.getUIDValidationResult()
        transferSyntaxEntries = service.getTransferSyntaxEntries()
        selectedSourceSyntaxUID = service.getSelectedSourceSyntaxUID()
        selectedTargetSyntaxUID = service.getSelectedTargetSyntaxUID()
        sopClassEntries = service.getSOPClassEntries()
        capabilityEntries = service.getCapabilityEntries()
        conformanceServiceFilter = service.getConformanceServiceFilter()
    }

    // MARK: - 13.1 Performance Dashboard

    public func updateMetrics(_ m: PerformanceMetrics) {
        metrics = m
        service.setMetrics(m)
    }

    public func addBenchmarkResult(_ result: BenchmarkResult) {
        benchmarkResults.append(result)
        service.addBenchmarkResult(result)
    }

    public func updateBenchmarkResult(_ result: BenchmarkResult) {
        if let idx = benchmarkResults.firstIndex(where: { $0.id == result.id }) {
            benchmarkResults[idx] = result
        }
        service.updateBenchmarkResult(result)
    }

    public func clearBenchmarkResults() {
        benchmarkResults.removeAll()
        service.clearBenchmarkResults()
        benchmarkExportCSV = ""
    }

    public func exportBenchmarksToCSV() {
        benchmarkExportCSV = PerformanceDashboardHelpers.exportBenchmarksToCSV(benchmarkResults)
    }

    public func startBenchmark(type: BenchmarkType) {
        var result = BenchmarkResult(type: type, status: .running, startedAt: Date())
        addBenchmarkResult(result)
        isRunningBenchmark = true
        // Simulate benchmark completion synchronously for testability
        result.durationMs = simulatedDurationMs(for: type)
        result.iterations = simulatedIterations(for: type)
        result.status = .completed
        result.completedAt = Date()
        updateBenchmarkResult(result)
        isRunningBenchmark = false
    }

    private func simulatedDurationMs(for type: BenchmarkType) -> Double {
        switch type {
        case .parseFiles:     return 245.0
        case .renderFrames:   return 380.0
        case .windowLevel:    return 12.5
        case .networkLatency: return 18.3
        }
    }

    private func simulatedIterations(for type: BenchmarkType) -> Int {
        switch type {
        case .parseFiles:     return 100
        case .renderFrames:   return 100
        case .windowLevel:    return 1000
        case .networkLatency: return 10
        }
    }

    // MARK: - 13.2 Cache Management

    public func updateCacheStats(_ stats: CacheStats, for cacheType: CacheType) {
        cacheStats[cacheType] = stats
        service.setCacheStats(stats, for: cacheType)
    }

    public func setCacheItems(_ items: [CacheItemInfo], for cacheType: CacheType) {
        cacheItems[cacheType] = items
        service.setCacheItems(items, for: cacheType)
    }

    public func clearCache(for cacheType: CacheType) {
        cacheItems[cacheType] = []
        cacheStats[cacheType] = CacheStats(cacheType: cacheType)
        service.clearCache(for: cacheType)
    }

    public func clearAllCaches() {
        for ct in CacheType.allCases {
            clearCache(for: ct)
        }
    }

    public var currentCacheStats: CacheStats {
        cacheStats[selectedCacheType] ?? CacheStats(cacheType: selectedCacheType)
    }

    public var currentCacheItems: [CacheItemInfo] {
        CacheManagementHelpers.sortByLRU(cacheItems[selectedCacheType] ?? [])
    }

    // MARK: - 13.3 Tag Dictionary

    public func setTagSearchQuery(_ q: String) {
        tagSearchQuery = q
        service.setTagSearchQuery(q)
    }

    public func setTagGroupFilter(_ f: TagGroupFilter) {
        tagGroupFilter = f
        service.setTagGroupFilter(f)
    }

    public var filteredTagEntries: [DICOMTagEntry] {
        TagDictionaryHelpers.search(tagEntries, query: tagSearchQuery, group: tagGroupFilter)
    }

    // MARK: - 13.4 UID Lookup

    public func setUIDSearchQuery(_ q: String) {
        uidSearchQuery = q
        service.setUIDSearchQuery(q)
    }

    public func generateUID() {
        let uid = UIDLookupHelpers.generateUID()
        lastGeneratedUID = uid
        service.setLastGeneratedUID(uid)
    }

    public func validateUID(_ uid: String) {
        let result = UIDLookupHelpers.validate(uid: uid)
        uidValidationResult = result
        service.setUIDValidationResult(result)
    }

    public var filteredUIDEntries: [UIDEntry] {
        let q = uidSearchQuery.lowercased()
        guard !q.isEmpty else { return uidEntries }
        return uidEntries.filter {
            $0.uid.lowercased().contains(q)
                || $0.name.lowercased().contains(q)
                || $0.category.displayName.lowercased().contains(q)
        }
    }

    // MARK: - 13.5 Transfer Syntax Info

    public func setSelectedSourceSyntaxUID(_ uid: String) {
        selectedSourceSyntaxUID = uid
        service.setSelectedSourceSyntaxUID(uid)
    }

    public func setSelectedTargetSyntaxUID(_ uid: String) {
        selectedTargetSyntaxUID = uid
        service.setSelectedTargetSyntaxUID(uid)
    }

    public var compatibilityNote: String {
        TransferSyntaxInfoHelpers.compatibilityNote(
            from: selectedSourceSyntaxUID,
            to: selectedTargetSyntaxUID
        )
    }

    // MARK: - 13.6 Conformance Statement

    public func setConformanceServiceFilter(_ f: ConformanceServiceCategory) {
        conformanceServiceFilter = f
        service.setConformanceServiceFilter(f)
    }

    public var filteredCapabilityEntries: [ConformanceCapabilityEntry] {
        ConformanceStatementHelpers.capabilities(capabilityEntries, for: conformanceServiceFilter)
    }

    public var dicomkitVersion: String {
        ConformanceStatementHelpers.dicomkitVersion()
    }

    public var dicomStandardVersion: String {
        ConformanceStatementHelpers.dicomStandardVersion()
    }
}
