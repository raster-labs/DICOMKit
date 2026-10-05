// PerformanceToolsService.swift
// DICOMStudio
//
// DICOM Studio — Thread-safe service for Performance & Developer Tools state (Milestone 13)
// Reference: DICOM PS3.2 (Conformance), PS3.6 (Data Dictionary)
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data of its own; the two Transfer Syntax UID
// defaults (1.2.840.10008.1.2.1 Explicit VR Little Endian, 1.2.840.10008.1.2.4.70 JPEG Lossless SV1) are
// registered in PS3.6 2026a Table A-1 (checked by Scripts/diff_studio.py). The tables it holds are built by
// PerformanceToolsHelpers.swift, verified there.

import Foundation

/// Thread-safe service that manages state for the Performance & Developer Tools feature.
public final class PerformanceToolsService: @unchecked Sendable {
    private let lock = NSLock()

    // 13.1 Performance Dashboard
    private var _metrics: PerformanceMetrics = PerformanceMetrics()
    private var _benchmarkResults: [BenchmarkResult] = []

    // 13.2 Cache Management
    private var _cacheStats: [CacheType: CacheStats] = {
        var dict = [CacheType: CacheStats]()
        for cacheType in CacheType.allCases {
            dict[cacheType] = CacheStats(cacheType: cacheType)
        }
        return dict
    }()
    private var _cacheItems: [CacheType: [CacheItemInfo]] = [:]

    // 13.3 Tag Dictionary
    private var _tagEntries: [DICOMTagEntry] = TagDictionaryHelpers.sampleTagEntries()
    private var _tagSearchQuery: String = ""
    private var _tagGroupFilter: TagGroupFilter = .all

    // 13.4 UID Lookup
    private var _uidEntries: [UIDEntry] = UIDLookupHelpers.sampleUIDEntries()
    private var _uidSearchQuery: String = ""
    private var _lastGeneratedUID: String = ""
    private var _uidValidationResult: UIDValidationResult? = nil

    // 13.5 Transfer Syntax Info
    private var _transferSyntaxEntries: [TransferSyntaxInfoEntry] = TransferSyntaxInfoHelpers.builtInEntries()
    private var _selectedSourceSyntaxUID: String = "1.2.840.10008.1.2.1"
    private var _selectedTargetSyntaxUID: String = "1.2.840.10008.1.2.4.70"

    // 13.6 Conformance Statement
    private var _sopClassEntries: [SOPClassEntry] = ConformanceStatementHelpers.sopClassEntries()
    private var _capabilityEntries: [ConformanceCapabilityEntry] = ConformanceStatementHelpers.networkCapabilities()
    private var _conformanceServiceFilter: ConformanceServiceCategory = .dicomNetworking

    public init() {}

    // MARK: - 13.1 Performance Metrics

    public func getMetrics() -> PerformanceMetrics { lock.withLock { _metrics } }
    public func setMetrics(_ m: PerformanceMetrics) { lock.withLock { _metrics = m } }

    public func getBenchmarkResults() -> [BenchmarkResult] { lock.withLock { _benchmarkResults } }
    public func addBenchmarkResult(_ r: BenchmarkResult) { lock.withLock { _benchmarkResults.append(r) } }
    public func updateBenchmarkResult(_ r: BenchmarkResult) {
        lock.withLock {
            guard let idx = _benchmarkResults.firstIndex(where: { $0.id == r.id }) else { return }
            _benchmarkResults[idx] = r
        }
    }
    public func clearBenchmarkResults() { lock.withLock { _benchmarkResults.removeAll() } }

    // MARK: - 13.2 Cache Management

    public func getCacheStats(for cacheType: CacheType) -> CacheStats {
        lock.withLock { _cacheStats[cacheType] ?? CacheStats(cacheType: cacheType) }
    }
    public func setCacheStats(_ stats: CacheStats, for cacheType: CacheType) {
        lock.withLock { _cacheStats[cacheType] = stats }
    }
    public func getAllCacheStats() -> [CacheType: CacheStats] { lock.withLock { _cacheStats } }

    public func getCacheItems(for cacheType: CacheType) -> [CacheItemInfo] {
        lock.withLock { _cacheItems[cacheType] ?? [] }
    }
    public func setCacheItems(_ items: [CacheItemInfo], for cacheType: CacheType) {
        lock.withLock { _cacheItems[cacheType] = items }
    }
    public func clearCache(for cacheType: CacheType) {
        lock.withLock {
            _cacheItems[cacheType] = []
            if var stats = _cacheStats[cacheType] {
                stats.currentSizeBytes = 0
                stats.itemCount = 0
                _cacheStats[cacheType] = stats
            }
        }
    }

    // MARK: - 13.3 Tag Dictionary

    public func getTagEntries() -> [DICOMTagEntry] { lock.withLock { _tagEntries } }
    public func setTagEntries(_ entries: [DICOMTagEntry]) { lock.withLock { _tagEntries = entries } }
    public func getTagSearchQuery() -> String { lock.withLock { _tagSearchQuery } }
    public func setTagSearchQuery(_ q: String) { lock.withLock { _tagSearchQuery = q } }
    public func getTagGroupFilter() -> TagGroupFilter { lock.withLock { _tagGroupFilter } }
    public func setTagGroupFilter(_ f: TagGroupFilter) { lock.withLock { _tagGroupFilter = f } }

    // MARK: - 13.4 UID Lookup

    public func getUIDEntries() -> [UIDEntry] { lock.withLock { _uidEntries } }
    public func setUIDEntries(_ entries: [UIDEntry]) { lock.withLock { _uidEntries = entries } }
    public func getUIDSearchQuery() -> String { lock.withLock { _uidSearchQuery } }
    public func setUIDSearchQuery(_ q: String) { lock.withLock { _uidSearchQuery = q } }
    public func getLastGeneratedUID() -> String { lock.withLock { _lastGeneratedUID } }
    public func setLastGeneratedUID(_ uid: String) { lock.withLock { _lastGeneratedUID = uid } }
    public func getUIDValidationResult() -> UIDValidationResult? { lock.withLock { _uidValidationResult } }
    public func setUIDValidationResult(_ r: UIDValidationResult?) { lock.withLock { _uidValidationResult = r } }

    // MARK: - 13.5 Transfer Syntax Info

    public func getTransferSyntaxEntries() -> [TransferSyntaxInfoEntry] { lock.withLock { _transferSyntaxEntries } }
    public func setTransferSyntaxEntries(_ entries: [TransferSyntaxInfoEntry]) { lock.withLock { _transferSyntaxEntries = entries } }
    public func getSelectedSourceSyntaxUID() -> String { lock.withLock { _selectedSourceSyntaxUID } }
    public func setSelectedSourceSyntaxUID(_ uid: String) { lock.withLock { _selectedSourceSyntaxUID = uid } }
    public func getSelectedTargetSyntaxUID() -> String { lock.withLock { _selectedTargetSyntaxUID } }
    public func setSelectedTargetSyntaxUID(_ uid: String) { lock.withLock { _selectedTargetSyntaxUID = uid } }

    // MARK: - 13.6 Conformance Statement

    public func getSOPClassEntries() -> [SOPClassEntry] { lock.withLock { _sopClassEntries } }
    public func setSOPClassEntries(_ entries: [SOPClassEntry]) { lock.withLock { _sopClassEntries = entries } }
    public func getCapabilityEntries() -> [ConformanceCapabilityEntry] { lock.withLock { _capabilityEntries } }
    public func setCapabilityEntries(_ entries: [ConformanceCapabilityEntry]) { lock.withLock { _capabilityEntries = entries } }
    public func getConformanceServiceFilter() -> ConformanceServiceCategory { lock.withLock { _conformanceServiceFilter } }
    public func setConformanceServiceFilter(_ f: ConformanceServiceCategory) { lock.withLock { _conformanceServiceFilter = f } }
}
