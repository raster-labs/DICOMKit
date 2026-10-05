// PerformanceToolsHelpersTests.swift
// DICOMStudioTests

import Testing
@testable import DICOMStudio
import Foundation

@Suite("Performance Tools Helpers Tests")
struct PerformanceToolsHelpersTests {

    // MARK: - PerformanceDashboardHelpers.formatDurationMs

    @Test("formatDurationMs less than 1ms returns microseconds")
    func testFormatDurationMsMicroseconds() {
        let result = PerformanceDashboardHelpers.formatDurationMs(0.5)
        #expect(result.contains("µs"))
    }

    @Test("formatDurationMs between 1 and 1000ms returns milliseconds")
    func testFormatDurationMsMilliseconds() {
        let result = PerformanceDashboardHelpers.formatDurationMs(42.0)
        #expect(result.contains("ms"))
    }

    @Test("formatDurationMs 1000ms or more returns seconds")
    func testFormatDurationMsSeconds() {
        let result = PerformanceDashboardHelpers.formatDurationMs(1500.0)
        #expect(result.contains("s"))
        #expect(!result.contains("ms"))
    }

    // MARK: - PerformanceDashboardHelpers.formatHitRate

    @Test("formatHitRate 1.0 returns 100.0%")
    func testFormatHitRateFull() {
        let result = PerformanceDashboardHelpers.formatHitRate(1.0)
        #expect(result == "100.0%")
    }

    @Test("formatHitRate 0.0 returns 0.0%")
    func testFormatHitRateZero() {
        let result = PerformanceDashboardHelpers.formatHitRate(0.0)
        #expect(result == "0.0%")
    }

    @Test("formatHitRate 0.753 returns 75.3%")
    func testFormatHitRatePartial() {
        let result = PerformanceDashboardHelpers.formatHitRate(0.753)
        #expect(result == "75.3%")
    }

    // MARK: - PerformanceDashboardHelpers.formatMemoryMB

    @Test("formatMemoryMB under 1024MB shows MB")
    func testFormatMemoryMBMB() {
        let result = PerformanceDashboardHelpers.formatMemoryMB(512.0)
        #expect(result.contains("MB"))
    }

    @Test("formatMemoryMB 1024MB or more shows GB")
    func testFormatMemoryMBGB() {
        let result = PerformanceDashboardHelpers.formatMemoryMB(2048.0)
        #expect(result.contains("GB"))
    }

    // MARK: - PerformanceDashboardHelpers.performanceBadge

    @Test("performanceBadge returns Fast for low duration")
    func testPerformanceBadgeFast() {
        #expect(PerformanceDashboardHelpers.performanceBadge(durationMs: 5.0) == "Fast")
    }

    @Test("performanceBadge returns Slow for high duration")
    func testPerformanceBadgeSlow() {
        #expect(PerformanceDashboardHelpers.performanceBadge(durationMs: 200.0) == "Slow")
    }

    @Test("performanceBadge returns Normal for middle duration")
    func testPerformanceBadgeNormal() {
        #expect(PerformanceDashboardHelpers.performanceBadge(durationMs: 50.0) == "Normal")
    }

    // MARK: - PerformanceDashboardHelpers CSV Export

    @Test("benchmarkCSVHeader returns non-empty string")
    func testBenchmarkCSVHeader() {
        let header = PerformanceDashboardHelpers.benchmarkCSVHeader()
        #expect(!header.isEmpty)
        #expect(header.contains("Benchmark"))
    }

    @Test("benchmarkResultToCSV contains benchmark display name")
    func testBenchmarkResultToCSV() {
        let r = BenchmarkResult(type: .parseFiles, durationMs: 100, iterations: 100, status: .completed)
        let csv = PerformanceDashboardHelpers.benchmarkResultToCSV(r)
        #expect(csv.contains(r.type.displayName))
        #expect(csv.contains("100"))
    }

    @Test("exportBenchmarksToCSV has header and one row per result")
    func testExportBenchmarksToCSV() {
        let results = [
            BenchmarkResult(type: .parseFiles, durationMs: 100, iterations: 100, status: .completed),
            BenchmarkResult(type: .renderFrames, durationMs: 200, iterations: 100, status: .completed),
        ]
        let csv = PerformanceDashboardHelpers.exportBenchmarksToCSV(results)
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 3) // header + 2 results
    }

    @Test("exportBenchmarksToCSV empty results returns only header")
    func testExportBenchmarksToCSVEmpty() {
        let csv = PerformanceDashboardHelpers.exportBenchmarksToCSV([])
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 1)
    }

    // MARK: - PerformanceDashboardHelpers.improvementDescription

    @Test("improvementDescription returns N/A for zero beforeMs")
    func testImprovementDescriptionZeroBefore() {
        let result = PerformanceDashboardHelpers.improvementDescription(beforeMs: 0, afterMs: 10)
        #expect(result == "N/A")
    }

    @Test("improvementDescription returns faster when afterMs less than beforeMs")
    func testImprovementDescriptionFaster() {
        let result = PerformanceDashboardHelpers.improvementDescription(beforeMs: 100, afterMs: 50)
        #expect(result.contains("faster"))
    }

    @Test("improvementDescription returns slower when afterMs greater than beforeMs")
    func testImprovementDescriptionSlower() {
        let result = PerformanceDashboardHelpers.improvementDescription(beforeMs: 50, afterMs: 100)
        #expect(result.contains("slower"))
    }

    @Test("improvementDescription returns No change when equal")
    func testImprovementDescriptionNoChange() {
        let result = PerformanceDashboardHelpers.improvementDescription(beforeMs: 100, afterMs: 100)
        #expect(result == "No change")
    }

    // MARK: - CacheManagementHelpers.formatBytes

    @Test("formatBytes less than 1024 returns B")
    func testFormatBytesBytes() {
        #expect(CacheManagementHelpers.formatBytes(512) == "512 B")
    }

    @Test("formatBytes KB range")
    func testFormatBytesKB() {
        let result = CacheManagementHelpers.formatBytes(2048)
        #expect(result.contains("KB"))
    }

    @Test("formatBytes MB range")
    func testFormatBytesMB() {
        let result = CacheManagementHelpers.formatBytes(2 * 1024 * 1024)
        #expect(result.contains("MB"))
    }

    @Test("formatBytes GB range")
    func testFormatBytesGB() {
        let result = CacheManagementHelpers.formatBytes(2 * 1024 * 1024 * 1024)
        #expect(result.contains("GB"))
    }

    // MARK: - CacheManagementHelpers.fillDescription

    @Test("fillDescription low usage below 25%")
    func testFillDescriptionLow() {
        #expect(CacheManagementHelpers.fillDescription(fillPercentage: 10.0) == "Low usage")
    }

    @Test("fillDescription moderate usage 25–60%")
    func testFillDescriptionModerate() {
        #expect(CacheManagementHelpers.fillDescription(fillPercentage: 40.0) == "Moderate usage")
    }

    @Test("fillDescription high usage 60–85%")
    func testFillDescriptionHigh() {
        #expect(CacheManagementHelpers.fillDescription(fillPercentage: 70.0) == "High usage")
    }

    @Test("fillDescription near capacity above 85%")
    func testFillDescriptionNearCapacity() {
        #expect(CacheManagementHelpers.fillDescription(fillPercentage: 90.0) == "Near capacity")
    }

    // MARK: - CacheManagementHelpers.ageDescription

    @Test("ageDescription just now for under 60 seconds")
    func testAgeDescriptionJustNow() {
        #expect(CacheManagementHelpers.ageDescription(ageSeconds: 30) == "Just now")
    }

    @Test("ageDescription minutes ago for 60–3600 seconds")
    func testAgeDescriptionMinutes() {
        let result = CacheManagementHelpers.ageDescription(ageSeconds: 120)
        #expect(result.contains("min"))
    }

    @Test("ageDescription hours ago for 3600–86400 seconds")
    func testAgeDescriptionHours() {
        let result = CacheManagementHelpers.ageDescription(ageSeconds: 7200)
        #expect(result.contains("hr"))
    }

    @Test("ageDescription days ago for over 86400 seconds")
    func testAgeDescriptionDays() {
        let result = CacheManagementHelpers.ageDescription(ageSeconds: 172800)
        #expect(result.contains("day"))
    }

    // MARK: - CacheManagementHelpers.sortByLRU

    @Test("sortByLRU returns items in ascending lastAccessedAt order")
    func testSortByLRU() {
        let now = Date()
        let item1 = CacheItemInfo(key: "a", sizeBytes: 100, lastAccessedAt: now.addingTimeInterval(-60), cacheType: .image)
        let item2 = CacheItemInfo(key: "b", sizeBytes: 100, lastAccessedAt: now, cacheType: .image)
        let sorted = CacheManagementHelpers.sortByLRU([item2, item1])
        #expect(sorted.first?.key == "a")
    }

    // MARK: - CacheManagementHelpers.totalSizeBytes

    @Test("totalSizeBytes sums all item sizes")
    func testTotalSizeBytes() {
        let items = [
            CacheItemInfo(key: "a", sizeBytes: 100, cacheType: .image),
            CacheItemInfo(key: "b", sizeBytes: 200, cacheType: .image),
        ]
        #expect(CacheManagementHelpers.totalSizeBytes(of: items) == 300)
    }

    // MARK: - TagDictionaryHelpers.matches

    @Test("matches returns true when query is empty")
    func testTagDictionaryMatchesEmptyQuery() {
        let entry = DICOMTagEntry(tag: "(0010,0010)", name: "Patient Name", keyword: "PatientName", vr: "PN", vm: "1")
        #expect(TagDictionaryHelpers.matches(entry: entry, query: ""))
    }

    @Test("matches returns true when query matches tag number")
    func testTagDictionaryMatchesTagNumber() {
        let entry = DICOMTagEntry(tag: "(0010,0010)", name: "Patient Name", keyword: "PatientName", vr: "PN", vm: "1")
        #expect(TagDictionaryHelpers.matches(entry: entry, query: "0010"))
    }

    @Test("matches returns true when query matches name case-insensitively")
    func testTagDictionaryMatchesName() {
        let entry = DICOMTagEntry(tag: "(0010,0010)", name: "Patient Name", keyword: "PatientName", vr: "PN", vm: "1")
        #expect(TagDictionaryHelpers.matches(entry: entry, query: "patient"))
    }

    @Test("matches returns false for non-matching query")
    func testTagDictionaryMatchesFalse() {
        let entry = DICOMTagEntry(tag: "(0010,0010)", name: "Patient Name", keyword: "PatientName", vr: "PN", vm: "1")
        #expect(!TagDictionaryHelpers.matches(entry: entry, query: "ZZZnotfound"))
    }

    // MARK: - TagDictionaryHelpers.filter

    @Test("filter all returns all entries")
    func testTagDictionaryFilterAll() {
        let entries = TagDictionaryHelpers.sampleTagEntries()
        let result = TagDictionaryHelpers.filter(entries, by: .all)
        #expect(result.count == entries.count)
    }

    @Test("filter retired returns only retired entries")
    func testTagDictionaryFilterRetired() {
        var entries = TagDictionaryHelpers.sampleTagEntries()
        entries[0] = DICOMTagEntry(tag: entries[0].tag, name: entries[0].name, keyword: entries[0].keyword, vr: entries[0].vr, vm: entries[0].vm, isRetired: true)
        let result = TagDictionaryHelpers.filter(entries, by: .retired)
        #expect(result.allSatisfy { $0.isRetired })
    }

    @Test("filter patient returns only (0010,...) tags")
    func testTagDictionaryFilterPatient() {
        let entries = TagDictionaryHelpers.sampleTagEntries()
        let result = TagDictionaryHelpers.filter(entries, by: .patient)
        #expect(result.allSatisfy { $0.tag.hasPrefix("(0010,") })
    }

    // MARK: - TagDictionaryHelpers.vrFullName

    @Test("vrFullName returns known full name for PN")
    func testVRFullNamePN() {
        #expect(TagDictionaryHelpers.vrFullName(for: "PN") == "Person Name")
    }

    @Test("vrFullName returns known full name for UI")
    func testVRFullNameUI() {
        #expect(TagDictionaryHelpers.vrFullName(for: "UI") == "Unique Identifier (UID)")   // PS3.5 Table 6.2-1 "VR Name" verbatim
    }

    @Test("vrFullName returns input for unknown code")
    func testVRFullNameUnknown() {
        #expect(TagDictionaryHelpers.vrFullName(for: "XX") == "XX")
    }

    @Test("vrFullName uses the PS3.5 Table 6.2-1 names: the Other VRs are not 'String' VRs")
    func testVRFullNameOtherVRs() {
        #expect(TagDictionaryHelpers.vrFullName(for: "OB") == "Other Byte")
        #expect(TagDictionaryHelpers.vrFullName(for: "OD") == "Other Double")
        #expect(TagDictionaryHelpers.vrFullName(for: "OF") == "Other Float")
        #expect(TagDictionaryHelpers.vrFullName(for: "OW") == "Other Word")
        #expect(TagDictionaryHelpers.vrFullName(for: "OL") == "Other Long")
        #expect(TagDictionaryHelpers.vrFullName(for: "OV") == "Other 64-bit Very Long")
        // The two VRs whose Table 6.2-1 name carries its abbreviation are shown as the table writes them.
        #expect(TagDictionaryHelpers.vrFullName(for: "UI") == "Unique Identifier (UID)")
        #expect(TagDictionaryHelpers.vrFullName(for: "UR") == "Universal Resource Identifier or Universal Resource Locator (URI/URL)")
    }

    // MARK: - TagDictionaryHelpers.sampleTagEntries

    @Test("sampleTagEntries returns non-empty list")
    func testSampleTagEntriesNonEmpty() {
        #expect(!TagDictionaryHelpers.sampleTagEntries().isEmpty)
    }

    @Test("sampleTagEntries all entries have non-empty tag, name, keyword, vr, vm")
    func testSampleTagEntriesFieldsNonEmpty() {
        for entry in TagDictionaryHelpers.sampleTagEntries() {
            #expect(!entry.tag.isEmpty)
            #expect(!entry.name.isEmpty)
            #expect(!entry.keyword.isEmpty)
            #expect(!entry.vr.isEmpty)
            #expect(!entry.vm.isEmpty)
        }
    }

    // MARK: - UIDLookupHelpers.validate

    @Test("validate returns valid for well-formed UID")
    func testUIDValidateValid() {
        let result = UIDLookupHelpers.validate(uid: "1.2.840.10008.1.2.1")
        #expect(result.isValid)
    }

    @Test("validate returns invalid for empty UID")
    func testUIDValidateEmpty() {
        let result = UIDLookupHelpers.validate(uid: "")
        #expect(!result.isValid)
        #expect(result.errorMessage != nil)
    }

    @Test("validate returns invalid for UID longer than 64 chars")
    func testUIDValidateTooLong() {
        let uid = String(repeating: "1.", count: 33) // 66 chars
        let result = UIDLookupHelpers.validate(uid: uid)
        #expect(!result.isValid)
    }

    @Test("validate returns invalid for UID with non-digit component")
    func testUIDValidateNonDigit() {
        let result = UIDLookupHelpers.validate(uid: "1.2.abc")
        #expect(!result.isValid)
    }

    @Test("validate returns invalid for UID with leading zero in component")
    func testUIDValidateLeadingZero() {
        let result = UIDLookupHelpers.validate(uid: "1.02.3")
        #expect(!result.isValid)
    }

    @Test("validate allows single-digit 0 component")
    func testUIDValidateSingleZero() {
        let result = UIDLookupHelpers.validate(uid: "1.0.1")
        #expect(result.isValid)
    }

    // MARK: - UIDLookupHelpers.generateUID

    @Test("generateUID returns non-empty string starting with 2.25.")
    func testGenerateUID() {
        let uid = UIDLookupHelpers.generateUID()
        #expect(!uid.isEmpty)
        #expect(uid.hasPrefix("2.25."))
    }

    @Test("generateUID produces unique UIDs on each call")
    func testGenerateUIDUnique() {
        let uid1 = UIDLookupHelpers.generateUID()
        let uid2 = UIDLookupHelpers.generateUID()
        #expect(uid1 != uid2)
    }

    // MARK: - UIDLookupHelpers.sampleUIDEntries

    @Test("sampleUIDEntries returns non-empty list")
    func testSampleUIDEntriesNonEmpty() {
        #expect(!UIDLookupHelpers.sampleUIDEntries().isEmpty)
    }

    @Test("sampleUIDEntries all entries have non-empty uid and name")
    func testSampleUIDEntriesFieldsNonEmpty() {
        for entry in UIDLookupHelpers.sampleUIDEntries() {
            #expect(!entry.uid.isEmpty)
            #expect(!entry.name.isEmpty)
        }
    }

    // MARK: - TransferSyntaxInfoHelpers.builtInEntries

    @Test("builtInEntries returns more than 5 entries")
    func testBuiltInTransferSyntaxEntriesCount() {
        #expect(TransferSyntaxInfoHelpers.builtInEntries().count > 5)
    }

    @Test("builtInEntries all entries have non-empty uid and name")
    func testBuiltInTransferSyntaxEntriesFields() {
        for entry in TransferSyntaxInfoHelpers.builtInEntries() {
            #expect(!entry.uid.isEmpty)
            #expect(!entry.name.isEmpty)
        }
    }

    // MARK: - TransferSyntaxInfoHelpers.compatibilityNote

    @Test("compatibilityNote returns no conversion needed for same UID")
    func testCompatibilityNoteIdentical() {
        let note = TransferSyntaxInfoHelpers.compatibilityNote(from: "1.2.840.10008.1.2.1", to: "1.2.840.10008.1.2.1")
        #expect(note.contains("No conversion needed"))
    }

    @Test("compatibilityNote warns about lossy target")
    func testCompatibilityNoteLossy() {
        let note = TransferSyntaxInfoHelpers.compatibilityNote(from: "1.2.840.10008.1.2.1", to: "1.2.840.10008.1.2.4.50")
        #expect(note.contains("lossy"))
    }

    @Test("compatibilityNote returns without quality loss for lossless target")
    func testCompatibilityNoteLossless() {
        let note = TransferSyntaxInfoHelpers.compatibilityNote(from: "1.2.840.10008.1.2.1", to: "1.2.840.10008.1.2.4.70")
        #expect(note.contains("without quality loss"))
    }

    // MARK: - ConformanceStatementHelpers.networkCapabilities

    @Test("networkCapabilities returns non-empty list")
    func testNetworkCapabilitiesNonEmpty() {
        #expect(!ConformanceStatementHelpers.networkCapabilities().isEmpty)
    }

    @Test("networkCapabilities includes C-ECHO")
    func testNetworkCapabilitiesIncludesCEcho() {
        let entries = ConformanceStatementHelpers.networkCapabilities()
        #expect(entries.contains { $0.serviceName == "C-ECHO" })
    }

    @Test("networkCapabilities includes WADO-RS")
    func testNetworkCapabilitiesIncludesWADORS() {
        let entries = ConformanceStatementHelpers.networkCapabilities()
        #expect(entries.contains { $0.serviceName == "WADO-RS" })
    }

    // MARK: - ConformanceStatementHelpers.sopClassEntries

    @Test("sopClassEntries returns non-empty list")
    func testSOPClassEntriesNonEmpty() {
        #expect(!ConformanceStatementHelpers.sopClassEntries().isEmpty)
    }

    @Test("sopClassEntries all entries have non-empty uid and name")
    func testSOPClassEntriesFields() {
        for entry in ConformanceStatementHelpers.sopClassEntries() {
            #expect(!entry.uid.isEmpty)
            #expect(!entry.name.isEmpty)
        }
    }

    @Test("sopClassEntries pairs the Study Root names with the Study Root UIDs (PS3.6 Table A-1 .2.2.x, not Patient Root .2.1.x)")
    func testSOPClassEntriesStudyRootUIDs() {
        let byName = Dictionary(uniqueKeysWithValues:
            ConformanceStatementHelpers.sopClassEntries().map { ($0.name, $0.uid) })
        #expect(byName["Study Root Query/Retrieve Information Model - FIND"] == "1.2.840.10008.5.1.4.1.2.2.1")
        #expect(byName["Study Root Query/Retrieve Information Model - MOVE"] == "1.2.840.10008.5.1.4.1.2.2.2")
        #expect(byName["Study Root Query/Retrieve Information Model - GET"]  == "1.2.840.10008.5.1.4.1.2.2.3")
        #expect(byName["Unified Procedure Step - Event"] == "1.2.840.10008.5.1.4.34.6.4")
        #expect(byName["Positron Emission Tomography Image Storage"] == "1.2.840.10008.5.1.4.1.1.128")
        #expect(byName["Patient Root Query/Retrieve Information Model - FIND"] == "1.2.840.10008.5.1.4.1.2.1.1")
        #expect(byName["Patient Root Query/Retrieve Information Model - MOVE"] == "1.2.840.10008.5.1.4.1.2.1.2")
        #expect(byName["Patient Root Query/Retrieve Information Model - GET"]  == "1.2.840.10008.5.1.4.1.2.1.3")
        // No row pairs a Study Root name with a Patient Root UID or the reverse.
        for entry in ConformanceStatementHelpers.sopClassEntries() where entry.name.contains("Root Query") {
            let isStudyUID = entry.uid.hasPrefix("1.2.840.10008.5.1.4.1.2.2.")
            #expect(entry.name.hasPrefix("Study Root") == isStudyUID, "\(entry.name) \(entry.uid)")
        }
    }

    @Test("sampleUIDEntries names the SOP Classes as PS3.6 Table A-1 does")
    func testSampleUIDEntriesNames() {
        let byUID = Dictionary(uniqueKeysWithValues:
            UIDLookupHelpers.sampleUIDEntries().map { ($0.uid, $0.name) })
        #expect(byUID["1.2.840.10008.5.1.4.1.1.128"] == "Positron Emission Tomography Image Storage")
        #expect(byUID["1.2.840.10008.5.1.4.1.1.6.1"] == "Ultrasound Image Storage")
        #expect(byUID["1.2.840.10008.5.1.4.1.1.7"] == "Secondary Capture Image Storage")
        #expect(byUID["1.2.840.10008.1.2.2"] == "Explicit VR Big Endian")
    }

    // MARK: - ConformanceStatementHelpers.capabilities filter

    @Test("capabilities filter for dicomNetworking returns only networking entries")
    func testCapabilitiesFilterNetworking() {
        let all = ConformanceStatementHelpers.networkCapabilities()
        let filtered = ConformanceStatementHelpers.capabilities(all, for: .dicomNetworking)
        #expect(filtered.allSatisfy { $0.serviceCategory == .dicomNetworking })
    }

    @Test("capabilities filter for dicomweb returns only dicomweb entries")
    func testCapabilitiesFilterDICOMweb() {
        let all = ConformanceStatementHelpers.networkCapabilities()
        let filtered = ConformanceStatementHelpers.capabilities(all, for: .dicomweb)
        #expect(filtered.allSatisfy { $0.serviceCategory == .dicomweb })
    }

    // MARK: - ConformanceStatementHelpers versions

    @Test("dicomkitVersion returns non-empty string")
    func testDICOMKitVersion() {
        #expect(!ConformanceStatementHelpers.dicomkitVersion().isEmpty)
    }

    @Test("dicomStandardVersion returns non-empty string containing DICOM")
    func testDICOMStandardVersion() {
        let v = ConformanceStatementHelpers.dicomStandardVersion()
        #expect(v.contains("DICOM"))
    }
}
