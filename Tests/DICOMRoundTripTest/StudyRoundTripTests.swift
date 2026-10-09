// StudyRoundTripTests.swift
// Oracle-based round-trip tests for the `dicom-study` tool. Tests call the
// DICOMKit library directly (StudyScanner / StudyReport / StudyOrganizer) —
// never the CLI. Every assertion is a mathematical/semantic invariant, not a
// comparison to a re-implementation of the tool.
//
// Shared helpers (makeGrayscale8, writeTempDICOM, makeTempDir, readJSONObject,
// countFiles, rtUID, …) come from RoundTripFixture.swift and are NOT redefined.

import XCTest
import Foundation
@testable import DICOMKit
@testable import DICOMCore
@testable import DICOMDictionary

final class StudyRoundTripTests: XCTestCase {

    // MARK: - Private builders (class-scoped so they don't collide across files)

    /// Builds a minimal single-instance DICOM file with explicit study/series/SOP
    /// identity so multi-study/series scenarios can be assembled on disk.
    private func makeInstance(
        studyUID: String,
        seriesUID: String,
        sopUID: String = rtUID(),
        patientName: String? = nil,
        studyDescription: String? = nil,
        seriesNumber: String? = nil,
        seriesDescription: String? = nil,
        modality: String? = nil,
        instanceNumber: String? = nil
    ) -> DICOMFile {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        ds.setString(sopUID, for: .sopInstanceUID, vr: .UI)
        ds.setString(studyUID, for: .studyInstanceUID, vr: .UI)
        ds.setString(seriesUID, for: .seriesInstanceUID, vr: .UI)
        if let v = patientName { ds.setString(v, for: .patientName, vr: .PN) }
        if let v = studyDescription { ds.setString(v, for: .studyDescription, vr: .LO) }
        if let v = seriesNumber { ds.setString(v, for: .seriesNumber, vr: .IS) }
        if let v = seriesDescription { ds.setString(v, for: .seriesDescription, vr: .LO) }
        if let v = modality { ds.setString(v, for: .modality, vr: .CS) }
        if let v = instanceNumber { ds.setString(v, for: .instanceNumber, vr: .IS) }
        return DICOMFile.create(dataSet: ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.2")
    }

    /// Writes a DICOMFile into `dir` under `name` (a valid DICM-preamble file the
    /// scanner can re-read).
    private func write(_ file: DICOMFile, to dir: URL, name: String) throws {
        let data = try file.write()
        try data.write(to: dir.appendingPathComponent(name))
    }

    /// Returns the immediate subdirectory names of `dir`.
    private func subdirNames(of dir: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]))?
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { $0.lastPathComponent } ?? []
    }

    /// Recursively counts files with the given extension under `dir`.
    private func recursiveFileCount(in dir: URL, ext: String) -> Int {
        var count = 0
        guard let en = FileManager.default.enumerator(atPath: dir.path) else { return 0 }
        while let rel = en.nextObject() as? String {
            if rel.hasSuffix(".\(ext)") { count += 1 }
        }
        return count
    }

    // MARK: - scanStudies / metadata oracles

    // Oracle: after DICOMFile.read, studyInstanceUID is non-nil and scanStudies
    // surfaces exactly that UID for a single valid instance.
    func testScanSingleInstanceSurfacesStudyUID() throws {
        let dir = try makeTempDir()
        let studyUID = rtUID()
        let seriesUID = rtUID()
        try write(makeInstance(studyUID: studyUID, seriesUID: seriesUID), to: dir, name: "a.dcm")

        let studies = StudyScanner.scanStudies(at: dir.path)
        XCTAssertEqual(studies.count, 1)
        XCTAssertEqual(studies[0].studyInstanceUID, studyUID)
        XCTAssertEqual(studies[0].series.count, 1)
        XCTAssertEqual(studies[0].series[0].seriesInstanceUID, seriesUID)
    }

    // Oracle: totalInstances == series.reduce(0){ $0 + $1.instances.count } and
    // merged files with same study/series accumulate into one series.
    func testScanMergesInstancesAndTotalInstancesIsComputed() throws {
        let dir = try makeTempDir()
        let studyUID = rtUID()
        let seriesUID = rtUID()
        for i in 0..<4 {
            try write(makeInstance(studyUID: studyUID, seriesUID: seriesUID, instanceNumber: "\(i + 1)"),
                      to: dir, name: "inst\(i).dcm")
        }
        let studies = StudyScanner.scanStudies(at: dir.path)
        XCTAssertEqual(studies.count, 1)
        let study = studies[0]
        XCTAssertEqual(study.series.count, 1)
        XCTAssertEqual(study.series[0].instances.count, 4)
        XCTAssertEqual(study.totalInstances, study.series.reduce(0) { $0 + $1.instances.count })
        XCTAssertEqual(study.totalInstances, 4)
    }

    // Oracle: scanStudies returns studies sorted ascending by studyInstanceUID.
    func testScanStudiesSortedByUID() throws {
        let dir = try makeTempDir()
        // Numeric-string UIDs whose ASCII order is deterministic.
        let uidHigh = "1.2.3.999"
        let uidLow  = "1.2.3.100"
        try write(makeInstance(studyUID: uidHigh, seriesUID: rtUID()), to: dir, name: "high.dcm")
        try write(makeInstance(studyUID: uidLow, seriesUID: rtUID()), to: dir, name: "low.dcm")

        let studies = StudyScanner.scanStudies(at: dir.path)
        XCTAssertEqual(studies.count, 2)
        XCTAssertEqual(studies.map { $0.studyInstanceUID }, [uidLow, uidHigh])
        XCTAssertEqual(studies.map { $0.studyInstanceUID },
                       studies.map { $0.studyInstanceUID }.sorted())
    }

    // Oracle: series within a study are sorted ascending by seriesInstanceUID.
    func testScanSeriesSortedByUID() throws {
        let dir = try makeTempDir()
        let studyUID = rtUID()
        let sHigh = "1.2.3.1.999"
        let sLow  = "1.2.3.1.100"
        try write(makeInstance(studyUID: studyUID, seriesUID: sHigh), to: dir, name: "sh.dcm")
        try write(makeInstance(studyUID: studyUID, seriesUID: sLow), to: dir, name: "sl.dcm")

        let studies = StudyScanner.scanStudies(at: dir.path)
        XCTAssertEqual(studies.count, 1)
        XCTAssertEqual(studies[0].series.map { $0.seriesInstanceUID }, [sLow, sHigh])
    }

    // Oracle: scanStudies on a missing path returns empty (no throw).
    func testScanMissingPathReturnsEmpty() {
        let studies = StudyScanner.scanStudies(at: "/nonexistent/\(UUID().uuidString)")
        XCTAssertTrue(studies.isEmpty)
    }

    // Oracle: InstanceMetadata.fileSize equals FileManager's reported byte size.
    func testInstanceFileSizeMatchesFileManager() throws {
        let dir = try makeTempDir()
        let name = "size.dcm"
        try write(makeInstance(studyUID: rtUID(), seriesUID: rtUID()), to: dir, name: name)
        let path = dir.appendingPathComponent(name).path
        let fmSize = (try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? -1

        let studies = StudyScanner.scanStudies(at: dir.path)
        let inst = try XCTUnwrap(studies.first?.series.first?.instances.first)
        XCTAssertEqual(inst.fileSize, fmSize)
        XCTAssertGreaterThan(inst.fileSize, 0)
    }

    // MARK: - summary oracles

    // Oracle (plan): 2 studies — A: 2 series × 3 files (6), B: 1 series × 2 files
    // (2). JSON summary reflects these exact counts.
    func testSummaryJSONCounts() throws {
        let dir = try makeTempDir()
        let studyA = "1.2.100"
        let studyB = "1.2.200"
        let a1 = "1.2.100.1", a2 = "1.2.100.2", b1 = "1.2.200.1"
        for i in 0..<3 { try write(makeInstance(studyUID: studyA, seriesUID: a1), to: dir, name: "a1_\(i).dcm") }
        for i in 0..<3 { try write(makeInstance(studyUID: studyA, seriesUID: a2), to: dir, name: "a2_\(i).dcm") }
        for i in 0..<2 { try write(makeInstance(studyUID: studyB, seriesUID: b1), to: dir, name: "b1_\(i).dcm") }

        let studies = StudyScanner.scanStudies(at: dir.path)
        XCTAssertEqual(studies.count, 2)

        // Semantic count oracles straight off the model.
        let studyAMeta = try XCTUnwrap(studies.first { $0.studyInstanceUID == studyA })
        let studyBMeta = try XCTUnwrap(studies.first { $0.studyInstanceUID == studyB })
        XCTAssertEqual(studyAMeta.series.count, 2)
        XCTAssertEqual(studyAMeta.totalInstances, 6)
        XCTAssertEqual(studyBMeta.series.count, 1)
        XCTAssertEqual(studyBMeta.totalInstances, 2)

        // The JSON render round-trips the same identities and counts.
        let json = try StudyReport.renderSummary(studies: studies, format: "json", verbose: false)
        let jsonData = Data(json.utf8)
        let decoded = try JSONDecoder().decode([StudyMetadata].self, from: jsonData)
        XCTAssertEqual(decoded.count, 2)
        let decA = try XCTUnwrap(decoded.first { $0.studyInstanceUID == studyA })
        let decB = try XCTUnwrap(decoded.first { $0.studyInstanceUID == studyB })
        XCTAssertEqual(decA.series.count, 2)
        XCTAssertEqual(decA.totalInstances, 6)
        XCTAssertEqual(decB.series.count, 1)
        XCTAssertEqual(decB.totalInstances, 2)
    }

    // Oracle (plan): table output contains each series description verbatim.
    func testSummaryTableContainsSeriesDescriptions() throws {
        let dir = try makeTempDir()
        let studyUID = rtUID()
        try write(makeInstance(studyUID: studyUID, seriesUID: "1.2.5.1",
                               seriesDescription: "AXIAL_BRAIN"), to: dir, name: "s1.dcm")
        try write(makeInstance(studyUID: studyUID, seriesUID: "1.2.5.2",
                               seriesDescription: "SAG_SPINE"), to: dir, name: "s2.dcm")

        let studies = StudyScanner.scanStudies(at: dir.path)
        let table = try StudyReport.renderSummary(studies: studies, format: "table", verbose: true)
        XCTAssertTrue(table.contains("AXIAL_BRAIN"))
        XCTAssertTrue(table.contains("SAG_SPINE"))
    }

    // Oracle: CSV summary header + one data row per study; row carries series &
    // instance counts.
    func testSummaryCSVRowCounts() throws {
        let dir = try makeTempDir()
        let studyUID = "1.2.777"
        for i in 0..<3 { try write(makeInstance(studyUID: studyUID, seriesUID: "1.2.777.1"),
                                   to: dir, name: "c\(i).dcm") }
        let studies = StudyScanner.scanStudies(at: dir.path)
        let csv = try StudyReport.renderSummary(studies: studies, format: "csv", verbose: false)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        XCTAssertTrue(lines[0].hasPrefix("StudyUID,"))
        let dataRow = try XCTUnwrap(lines.first { $0.hasPrefix(studyUID + ",") })
        // Trailing fields are SeriesCount(1),InstanceCount(3).
        XCTAssertTrue(dataRow.hasSuffix(",1,3"))
    }

    // Oracle: an unknown format throws (invalidPattern), never silently succeeds.
    func testSummaryInvalidFormatThrows() {
        XCTAssertThrowsError(try StudyReport.renderSummary(studies: [], format: "yaml", verbose: false))
    }

    // MARK: - stats oracles

    // Oracle (plan): stats counts match what was imported; totalSize equals sum of
    // instance file sizes; modality counts by series.
    func testStatsCountsMatchImports() throws {
        let dir = try makeTempDir()
        let studyUID = rtUID()
        try write(makeInstance(studyUID: studyUID, seriesUID: "1.2.9.1", modality: "CT"),
                  to: dir, name: "ct1.dcm")
        try write(makeInstance(studyUID: studyUID, seriesUID: "1.2.9.1", modality: "CT"),
                  to: dir, name: "ct2.dcm")
        try write(makeInstance(studyUID: studyUID, seriesUID: "1.2.9.2", modality: "MR"),
                  to: dir, name: "mr1.dcm")

        let study = try XCTUnwrap(StudyScanner.scanStudies(at: dir.path).first)
        let stats = StudyReport.computeStatistics(for: study, detailed: true)

        XCTAssertEqual(stats.seriesCount, 2)
        XCTAssertEqual(stats.totalInstances, 3)
        XCTAssertEqual(stats.studyUID, studyUID)
        // modalityCounts key semantics: one series per modality above.
        XCTAssertEqual(stats.modalityCounts["CT"], 1)
        XCTAssertEqual(stats.modalityCounts["MR"], 1)
        // totalSizeBytes == sum of the per-instance file sizes (oracle).
        let expectedSize = study.series.flatMap { $0.instances }.reduce(Int64(0)) { $0 + $1.fileSize }
        XCTAssertEqual(stats.totalSizeBytes, expectedSize)
        // averageSizePerInstance == totalSize / totalInstances (integer division).
        XCTAssertEqual(stats.averageSizePerInstance, expectedSize / 3)
        // detailed => instancesPerSeries populated (2+1 or 1+2 depending on order).
        XCTAssertEqual(stats.instancesPerSeries.reduce(0, +), 3)
        XCTAssertEqual(stats.instancesPerSeries.count, 2)

        // Rendered text carries the counts.
        let text = try StudyReport.renderStats(stats, detailed: true, format: "text")
        XCTAssertTrue(text.contains("Number of Study Related Series: 2"))
        XCTAssertTrue(text.contains("Number of Study Related Instances: 3"))
    }

    // Oracle: detailed=false yields an empty instancesPerSeries array (per source).
    func testStatsNonDetailedOmitsInstancesPerSeries() throws {
        let dir = try makeTempDir()
        let studyUID = rtUID()
        try write(makeInstance(studyUID: studyUID, seriesUID: "1.2.11.1"), to: dir, name: "x.dcm")
        let study = try XCTUnwrap(StudyScanner.scanStudies(at: dir.path).first)
        let stats = StudyReport.computeStatistics(for: study, detailed: false)
        XCTAssertTrue(stats.instancesPerSeries.isEmpty)
        XCTAssertEqual(stats.totalInstances, 1)
    }

    // Oracle: JSON stats decode back to a Statistics with identical counts.
    func testStatsJSONRoundTrips() throws {
        let dir = try makeTempDir()
        let studyUID = rtUID()
        try write(makeInstance(studyUID: studyUID, seriesUID: "1.2.12.1", modality: "US"),
                  to: dir, name: "u.dcm")
        let study = try XCTUnwrap(StudyScanner.scanStudies(at: dir.path).first)
        let stats = StudyReport.computeStatistics(for: study, detailed: false)
        let json = try StudyReport.renderStats(stats, detailed: false, format: "json")
        let decoded = try JSONDecoder().decode(Statistics.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.studyUID, stats.studyUID)
        XCTAssertEqual(decoded.seriesCount, stats.seriesCount)
        XCTAssertEqual(decoded.totalInstances, stats.totalInstances)
        XCTAssertEqual(decoded.totalSizeBytes, stats.totalSizeBytes)
    }

    // MARK: - check / completeness oracles

    // Oracle (plan): expectedSeries matches actual → isComplete, no series issues.
    func testCheckAllSeriesPresentIsComplete() throws {
        let dir = try makeTempDir()
        let studyUID = rtUID()
        try write(makeInstance(studyUID: studyUID, seriesUID: "1.2.20.1", instanceNumber: "1"),
                  to: dir, name: "a.dcm")
        try write(makeInstance(studyUID: studyUID, seriesUID: "1.2.20.2", instanceNumber: "1"),
                  to: dir, name: "b.dcm")
        let study = try XCTUnwrap(StudyScanner.scanStudies(at: dir.path).first)
        let result = StudyReport.evaluateCompleteness(study: study, expectedSeries: 2, expectedInstances: nil)
        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertTrue(result.output.contains("complete"))
    }

    // Oracle (plan): expectedSeries=5 but only 2 → incomplete; issue mentions
    // expected vs found counts.
    func testCheckMissingSeriesDetected() throws {
        let dir = try makeTempDir()
        let studyUID = rtUID()
        try write(makeInstance(studyUID: studyUID, seriesUID: "1.2.21.1", instanceNumber: "1"),
                  to: dir, name: "a.dcm")
        try write(makeInstance(studyUID: studyUID, seriesUID: "1.2.21.2", instanceNumber: "1"),
                  to: dir, name: "b.dcm")
        let study = try XCTUnwrap(StudyScanner.scanStudies(at: dir.path).first)
        let result = StudyReport.evaluateCompleteness(study: study, expectedSeries: 5, expectedInstances: nil)
        XCTAssertFalse(result.isComplete)
        let joined = result.issues.joined(separator: " | ")
        XCTAssertTrue(joined.contains("5"))   // expected
        XCTAssertTrue(joined.contains("2"))   // found
    }

    // Oracle: a gap in instance numbers (1,2,4 → missing 3) is reported and marks
    // the study incomplete.
    func testCheckInstanceNumberGapDetected() throws {
        let dir = try makeTempDir()
        let studyUID = rtUID()
        let seriesUID = "1.2.22.1"
        for n in [1, 2, 4] {
            try write(makeInstance(studyUID: studyUID, seriesUID: seriesUID, instanceNumber: "\(n)"),
                      to: dir, name: "n\(n).dcm")
        }
        let study = try XCTUnwrap(StudyScanner.scanStudies(at: dir.path).first)
        let result = StudyReport.evaluateCompleteness(study: study, expectedSeries: nil, expectedInstances: nil)
        XCTAssertFalse(result.isComplete)
        XCTAssertTrue(result.issues.contains { $0.contains("3") && $0.lowercased().contains("missing") })
    }

    // Oracle: a contiguous instance-number sequence with no expectations is complete.
    func testCheckContiguousSequenceIsComplete() throws {
        let dir = try makeTempDir()
        let studyUID = rtUID()
        let seriesUID = "1.2.23.1"
        for n in 1...3 {
            try write(makeInstance(studyUID: studyUID, seriesUID: seriesUID, instanceNumber: "\(n)"),
                      to: dir, name: "n\(n).dcm")
        }
        let study = try XCTUnwrap(StudyScanner.scanStudies(at: dir.path).first)
        let result = StudyReport.evaluateCompleteness(study: study, expectedSeries: nil, expectedInstances: nil)
        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.issues.isEmpty)
    }

    // MARK: - compare oracles

    // Oracle (plan): identical studies → no differences; structurally identical.
    func testCompareIdenticalStudiesNoDifferences() throws {
        let studyUID = rtUID()
        let seriesUID = "1.2.30.1"
        let inst = InstanceMetadata(sopInstanceUID: rtUID(), instanceNumber: "1",
                                    filePath: "/x/a.dcm", fileSize: 100)
        let series = SeriesMetadata(seriesInstanceUID: seriesUID, seriesNumber: "1",
                                    seriesDescription: "S", modality: "CT", instances: [inst])
        let study = StudyMetadata(studyInstanceUID: studyUID, studyDate: nil, studyTime: nil,
                                  studyDescription: nil, patientName: nil, patientID: nil,
                                  accessionNumber: nil, series: [series])
        let cmp = StudyReport.compareStudies(study, study)
        XCTAssertEqual(cmp.commonSeriesCount, 1)
        XCTAssertEqual(cmp.onlyInStudy1Count, 0)
        XCTAssertEqual(cmp.onlyInStudy2Count, 0)
        XCTAssertTrue(cmp.seriesDifferences.isEmpty)

        let text = try StudyReport.renderComparison(cmp, format: "text", verbose: false)
        XCTAssertTrue(text.contains("structurally identical"))
    }

    // Oracle (plan): study 2 has one extra instance in a common series → reported
    // as an instance-count difference on that series UID.
    func testCompareExtraInstanceDetected() throws {
        let studyUID1 = rtUID()
        let studyUID2 = rtUID()
        let seriesUID = "1.2.31.1"

        func inst() -> InstanceMetadata {
            InstanceMetadata(sopInstanceUID: rtUID(), instanceNumber: nil,
                             filePath: "/x/\(UUID().uuidString).dcm", fileSize: 10)
        }
        let s1 = SeriesMetadata(seriesInstanceUID: seriesUID, seriesNumber: "1",
                                seriesDescription: "S", modality: "CT", instances: [inst()])
        let s2 = SeriesMetadata(seriesInstanceUID: seriesUID, seriesNumber: "1",
                                seriesDescription: "S", modality: "CT", instances: [inst(), inst()])
        let study1 = StudyMetadata(studyInstanceUID: studyUID1, studyDate: nil, studyTime: nil,
                                   studyDescription: nil, patientName: nil, patientID: nil,
                                   accessionNumber: nil, series: [s1])
        let study2 = StudyMetadata(studyInstanceUID: studyUID2, studyDate: nil, studyTime: nil,
                                   studyDescription: nil, patientName: nil, patientID: nil,
                                   accessionNumber: nil, series: [s2])

        let cmp = StudyReport.compareStudies(study1, study2)
        XCTAssertEqual(cmp.commonSeriesCount, 1)
        XCTAssertEqual(cmp.seriesDifferences.count, 1)
        let diff = try XCTUnwrap(cmp.seriesDifferences.first)
        XCTAssertEqual(diff.seriesUID, seriesUID)
        XCTAssertEqual(diff.instanceCountStudy1, 1)
        XCTAssertEqual(diff.instanceCountStudy2, 2)
        XCTAssertEqual(cmp.study2InstanceCount - cmp.study1InstanceCount, 1)
    }

    // Oracle: a series present only in one study counts toward onlyInStudyN, not
    // common, and is not a "difference" (differences are for common series only).
    func testCompareSeriesOnlyInOneStudy() {
        func series(_ uid: String) -> SeriesMetadata {
            SeriesMetadata(seriesInstanceUID: uid, seriesNumber: nil, seriesDescription: nil,
                           modality: nil, instances: [InstanceMetadata(
                               sopInstanceUID: rtUID(), instanceNumber: nil,
                               filePath: "/x", fileSize: 1)])
        }
        let shared = "1.2.40.1"
        let onlyIn2 = "1.2.40.2"
        let study1 = StudyMetadata(studyInstanceUID: rtUID(), studyDate: nil, studyTime: nil,
                                   studyDescription: nil, patientName: nil, patientID: nil,
                                   accessionNumber: nil, series: [series(shared)])
        let study2 = StudyMetadata(studyInstanceUID: rtUID(), studyDate: nil, studyTime: nil,
                                   studyDescription: nil, patientName: nil, patientID: nil,
                                   accessionNumber: nil, series: [series(shared), series(onlyIn2)])
        let cmp = StudyReport.compareStudies(study1, study2)
        XCTAssertEqual(cmp.commonSeriesCount, 1)
        XCTAssertEqual(cmp.onlyInStudy1Count, 0)
        XCTAssertEqual(cmp.onlyInStudy2Count, 1)
        // Common series have equal instance counts → no differences.
        XCTAssertTrue(cmp.seriesDifferences.isEmpty)
    }

    // MARK: - organize oracles

    // Oracle (plan): descriptive pattern builds a nested Study/Series tree; a
    // study-dir name contains the patient name; all files land under one series leaf.
    func testOrganizeDescriptiveHierarchy() throws {
        let input = try makeTempDir()
        let output = try makeTempDir().appendingPathComponent("out")
        let studyUID = rtUID()
        let seriesUID = "1.2.50.1"
        for i in 0..<3 {
            try write(makeInstance(studyUID: studyUID, seriesUID: seriesUID,
                                   patientName: "JONES^BOB", studyDescription: "HEAD",
                                   seriesNumber: "1", seriesDescription: "AXIAL", modality: "CT"),
                      to: input, name: "f\(i).dcm")
        }
        let organizer = StudyOrganizer()
        let result = try organizer.organize(inputPath: input.path, outputPath: output.path,
                                             pattern: "descriptive", copy: true, verbose: false,
                                             log: { _ in })
        XCTAssertEqual(result.copied, 3)
        XCTAssertEqual(result.studies, 1)

        // A study-level subdir name contains the patient name.
        let studyDirs = subdirNames(of: output)
        XCTAssertEqual(studyDirs.count, 1)
        XCTAssertTrue(studyDirs[0].contains("JONES"))

        // All 3 files present under the tree.
        XCTAssertEqual(recursiveFileCount(in: output, ext: "dcm"), 3)
    }

    // Oracle (plan): uid pattern uses the study/series UID strings as dir names.
    func testOrganizeUIDPatternUsesUIDDirNames() throws {
        let input = try makeTempDir()
        let output = try makeTempDir().appendingPathComponent("out")
        let studyUID = rtUID()
        let seriesUID = rtUID()
        try write(makeInstance(studyUID: studyUID, seriesUID: seriesUID), to: input, name: "a.dcm")

        let organizer = StudyOrganizer()
        _ = try organizer.organize(inputPath: input.path, outputPath: output.path,
                                   pattern: "uid", copy: true, verbose: false, log: { _ in })

        let studyDirs = subdirNames(of: output)
        XCTAssertEqual(studyDirs, [studyUID])
        let seriesDirs = subdirNames(of: output.appendingPathComponent(studyUID))
        XCTAssertEqual(seriesDirs, [seriesUID])
    }

    // Oracle (plan): --copy leaves the original source files present in the input dir.
    func testOrganizeCopyPreservesSources() throws {
        let input = try makeTempDir()
        let output = try makeTempDir().appendingPathComponent("out")
        try write(makeInstance(studyUID: rtUID(), seriesUID: rtUID()), to: input, name: "src.dcm")

        let organizer = StudyOrganizer()
        _ = try organizer.organize(inputPath: input.path, outputPath: output.path,
                                   pattern: "uid", copy: true, verbose: false, log: { _ in })

        XCTAssertTrue(FileManager.default.fileExists(atPath: input.appendingPathComponent("src.dcm").path))
        XCTAssertEqual(recursiveFileCount(in: input, ext: "dcm"), 1)
        XCTAssertEqual(recursiveFileCount(in: output, ext: "dcm"), 1)
    }

    // Oracle (plan): move (copy:false) removes the source file from the input dir.
    func testOrganizeMoveRemovesSources() throws {
        let input = try makeTempDir()
        let output = try makeTempDir().appendingPathComponent("out")
        try write(makeInstance(studyUID: rtUID(), seriesUID: rtUID()), to: input, name: "src.dcm")

        let organizer = StudyOrganizer()
        _ = try organizer.organize(inputPath: input.path, outputPath: output.path,
                                   pattern: "uid", copy: false, verbose: false, log: { _ in })

        XCTAssertFalse(FileManager.default.fileExists(atPath: input.appendingPathComponent("src.dcm").path))
        XCTAssertEqual(recursiveFileCount(in: output, ext: "dcm"), 1)
    }

    // Oracle: invalid pattern throws StudyError (never partially organizes).
    func testOrganizeInvalidPatternThrows() throws {
        let input = try makeTempDir()
        let output = try makeTempDir().appendingPathComponent("out")
        try write(makeInstance(studyUID: rtUID(), seriesUID: rtUID()), to: input, name: "a.dcm")
        let organizer = StudyOrganizer()
        XCTAssertThrowsError(try organizer.organize(inputPath: input.path, outputPath: output.path,
                                                    pattern: "bogus", copy: true, verbose: false,
                                                    log: { _ in }))
    }

    // Oracle: organizing an empty directory throws noFilesFound.
    func testOrganizeEmptyDirThrows() throws {
        let input = try makeTempDir()
        let output = try makeTempDir().appendingPathComponent("out")
        let organizer = StudyOrganizer()
        XCTAssertThrowsError(try organizer.organize(inputPath: input.path, outputPath: output.path,
                                                    pattern: "uid", copy: true, verbose: false,
                                                    log: { _ in }))
    }

    // MARK: - Corpus realism

    // Oracle: a real Explicit-VR CT file scans into exactly one study with a
    // non-empty studyInstanceUID and one instance.
    func testCorpusCTScansIntoOneStudy() throws {
        guard let url = corpusURL(.ct) else { throw XCTSkip("corpus absent") }
        let dir = try makeTempDir()
        let data = try Data(contentsOf: url)
        try data.write(to: dir.appendingPathComponent("CT.dcm"))

        let studies = StudyScanner.scanStudies(at: dir.path)
        XCTAssertEqual(studies.count, 1)
        XCTAssertFalse(studies[0].studyInstanceUID.isEmpty)
        XCTAssertEqual(studies[0].totalInstances, 1)
        // fileSize oracle on real bytes.
        let inst = try XCTUnwrap(studies[0].series.first?.instances.first)
        XCTAssertEqual(inst.fileSize, Int64(data.count))
    }

    // MARK: - check --expected-instances / compare --format json

    // Oracle: --expected-instances flags an instance shortfall — a study with fewer
    // instances than expected is incomplete and the issue names both counts; meeting
    // the expectation is complete.
    func testCheckExpectedInstancesDetectsShortfall() throws {
        let dir = try makeTempDir()
        let studyUID = rtUID()
        let seriesUID = "1.2.24.1"
        for n in 1...2 {
            try write(makeInstance(studyUID: studyUID, seriesUID: seriesUID, instanceNumber: "\(n)"),
                      to: dir, name: "n\(n).dcm")
        }
        let study = try XCTUnwrap(StudyScanner.scanStudies(at: dir.path).first)

        let short = StudyReport.evaluateCompleteness(study: study, expectedSeries: nil, expectedInstances: 5)
        XCTAssertFalse(short.isComplete)
        let joined = short.issues.joined(separator: " | ")
        XCTAssertTrue(joined.contains("5"), "issue must name the expected instance count")
        XCTAssertTrue(joined.contains("2"), "issue must name the found instance count")

        let ok = StudyReport.evaluateCompleteness(study: study, expectedSeries: nil, expectedInstances: 2)
        XCTAssertTrue(ok.isComplete, "meeting the expected instance count is complete")
    }

    // Oracle: compare --format json renders valid JSON (distinct from the text render),
    // proving the JSON comparison renderer — the tool's own advertised option — works.
    func testCompareRendersValidJSON() throws {
        func inst() -> InstanceMetadata {
            InstanceMetadata(sopInstanceUID: rtUID(), instanceNumber: nil,
                             filePath: "/x/\(UUID().uuidString).dcm", fileSize: 10)
        }
        let common = SeriesMetadata(seriesInstanceUID: "1.2.32.1", seriesNumber: "1",
                                    seriesDescription: "S", modality: "CT", instances: [inst()])
        let extra = SeriesMetadata(seriesInstanceUID: "1.2.32.2", seriesNumber: "2",
                                   seriesDescription: "X", modality: "CT", instances: [inst()])
        let study1 = StudyMetadata(studyInstanceUID: rtUID(), studyDate: nil, studyTime: nil,
                                   studyDescription: nil, patientName: nil, patientID: nil,
                                   accessionNumber: nil, series: [common])
        let study2 = StudyMetadata(studyInstanceUID: rtUID(), studyDate: nil, studyTime: nil,
                                   studyDescription: nil, patientName: nil, patientID: nil,
                                   accessionNumber: nil, series: [common, extra])

        let cmp = StudyReport.compareStudies(study1, study2)
        let json = try StudyReport.renderComparison(cmp, format: "json", verbose: false)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(json.utf8)),
                         "compare --format json must emit valid JSON")
        let text = try StudyReport.renderComparison(cmp, format: "text", verbose: false)
        XCTAssertNotEqual(json, text, "json format must differ from the text render")
    }
}
