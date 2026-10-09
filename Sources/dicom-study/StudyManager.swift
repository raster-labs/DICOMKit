// NEMA-verified: 2026a, checked 2026-10-01 — thin adapters over DICOMKit StudyScanner / StudyReport; the file itself carries no DICOM-standard data (paths, error text, printing)
import Foundation
import DICOMCore
import DICOMKit
import DICOMDictionary

// StudyError, the study metadata models (StudyMetadata/SeriesMetadata/
// InstanceMetadata), the analysis result types (Statistics/StudyComparison/
// SeriesDifference), the scanner (StudyScanner) and the renderers (StudyReport)
// now live in the DICOMKit library (Sources/DICOMKit/Study/) so the CLI and
// DICOMStudio run the exact same code. ALL dicom-study subcommands are now thin
// CLI adapters over that shared code — including organize, whose StudyOrganizer
// moved to Sources/DICOMKit/Study/StudyOrganizer.swift (so file naming, ordering,
// and the copy/move "already exists" error are identical in the CLI and the app).

// MARK: - Thin CLI adapters over the shared DICOMKit study engine

struct StudyAnalyzer {
    func summarize(path: String, format: String, verbose: Bool) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw StudyError.directoryNotFound(path)
        }
        let studies = scanReportingSkipped(at: path)
        if studies.isEmpty { throw StudyError.noFilesFound }
        print(try StudyReport.renderSummary(studies: studies, format: format, verbose: verbose), terminator: "")
    }
}

struct CompletenessChecker {
    func check(
        studyPath: String,
        expectedSeries: Int?,
        expectedInstances: Int?,
        reportPath: String?,
        verbose: Bool
    ) throws {
        guard FileManager.default.fileExists(atPath: studyPath) else {
            throw StudyError.directoryNotFound(studyPath)
        }
        // The completeness result is this command's primary output, so it goes to
        // stdout (consistent with summary/stats/compare, and matching DICOMStudio).
        if verbose {
            print("Checking study completeness: \(studyPath)")
        }
        let studies = scanReportingSkipped(at: studyPath)
        guard let study = studies.first else {
            throw StudyError.noFilesFound
        }
        let result = StudyReport.evaluateCompleteness(
            study: study,
            expectedSeries: expectedSeries,
            expectedInstances: expectedInstances
        )
        print(result.output, terminator: "")
        if let reportPath = reportPath {
            let report = result.issues.joined(separator: "\n")
            try report.write(toFile: reportPath, atomically: true, encoding: .utf8)
            print("Report written to: \(reportPath)")
        }
    }
}

struct StatsCalculator {
    func calculateStats(studyPath: String, detailed: Bool, format: String) throws {
        guard FileManager.default.fileExists(atPath: studyPath) else {
            throw StudyError.directoryNotFound(studyPath)
        }
        let studies = scanReportingSkipped(at: studyPath)
        guard let study = studies.first else {
            throw StudyError.noFilesFound
        }
        let stats = StudyReport.computeStatistics(for: study, detailed: detailed)
        print(try StudyReport.renderStats(stats, detailed: detailed, format: format), terminator: "")
    }
}

struct StudyComparator {
    func compare(study1Path: String, study2Path: String, format: String, verbose: Bool) throws {
        guard FileManager.default.fileExists(atPath: study1Path) else {
            throw StudyError.directoryNotFound(study1Path)
        }
        guard FileManager.default.fileExists(atPath: study2Path) else {
            throw StudyError.directoryNotFound(study2Path)
        }
        let studies1 = scanReportingSkipped(at: study1Path)
        let studies2 = scanReportingSkipped(at: study2Path)
        guard let study1 = studies1.first else { throw StudyError.noFilesFound }
        guard let study2 = studies2.first else { throw StudyError.noFilesFound }
        let comparison = StudyReport.compareStudies(study1, study2)
        print(try StudyReport.renderComparison(comparison, format: format, verbose: verbose), terminator: "")
    }
}

// MARK: - Helper Functions

/// Scans with the shared engine and writes one warning per DICOM file it left out (no
/// Study / Series / SOP Instance UID, Type 1 in PS3.3 Tables C.7-3, C.7-5a, C.12-1; or unreadable).
func scanReportingSkipped(at path: String) -> [StudyMetadata] {
    let result = StudyScanner.scan(at: path)
    for skip in result.skipped {
        fprintln("warning: skipped \(skip.path): \(skip.reason)")
    }
    return result.studies
}

private func fprintln(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8) ?? Data())
}
