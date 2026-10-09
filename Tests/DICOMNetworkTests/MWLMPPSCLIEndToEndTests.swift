//
// MWLMPPSCLIEndToEndTests.swift
// DICOMNetworkTests
//
// Spawn-based tests for the dicom-mwl and dicom-mpps executables: the
// standard-derived help text and the validations that run before any
// association is opened (so no SCP is needed).
//
// NEMA-verified: 2026a, checked 2026-10-01 — the expected strings are the PS3.3
// Table C.4-10 (0040,0020) Defined Terms, the Table C.4-14 (0040,0252) Enumerated
// Values, the Table C.2-3 (0010,0040) Enumerated Values, the PS3.16 CID 9300 / CID
// 9301 code meanings (110513, 110500, 110501, 110507) and the PS3.4 Table F.7.2-1
// usage of Modality (0008,0060) and Performed Series Sequence (0040,0340).
//

import XCTest
import Foundation
@testable import DICOMNetwork

#if os(macOS)

final class MWLMPPSCLIEndToEndTests: XCTestCase {

    private var productsDirectory: URL {
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("test bundle not found")
    }

    private struct RunResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        var all: String { stdout + stderr }
    }

    private func run(_ tool: String, _ arguments: [String], timeout: TimeInterval = 30) throws -> RunResult {
        let binary = productsDirectory.appendingPathComponent(tool)
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: binary.path),
                          "\(tool) binary not present in products directory (build executables first)")
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        let stdoutPipe = Pipe(), stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            process.terminate()
            XCTFail("\(tool) did not exit within \(timeout)s: \(arguments)")
        }
        process.waitUntilExit()
        return RunResult(exitCode: process.terminationStatus,
                         stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                         stderr: String(data: stderrData, encoding: .utf8) ?? "")
    }

    // MARK: - dicom-mwl

    /// PS3.3 Table C.4-10: Scheduled Procedure Step Status (0040,0020) Defined Terms.
    func testMWL_helpListsTheScheduledProcedureStepStatusDefinedTerms() throws {
        let result = try run("dicom-mwl", ["query", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        for term in ["SCHEDULED", "ARRIVED", "READY", "STARTED", "DEPARTED"] {
            XCTAssertTrue(result.stdout.contains(term), "help lacks Defined Term \(term)")
        }
        XCTAssertTrue(result.stdout.contains("C.4-10"))
    }

    /// The PPS Status words (Table C.4-14) are not SPS Status Defined Terms; the
    /// value is still sent, with a warning, because Defined Terms may be extended.
    func testMWL_ppsStatusWordAsSPSStatusWarnsBeforeTheQuery() throws {
        // An over-long Scheduled Station AE Title fails validation before any
        // connection, so the run ends without an SCP — after the warning.
        let result = try run("dicom-mwl", [
            "query", "localhost", "--aet", "T", "--sps-status", "COMPLETED",
            "--station", "THIS_AE_TITLE_IS_TOO_LONG_X"])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("warning: --sps-status 'COMPLETED' is not a Scheduled Procedure Step Status Defined Term"),
                      "stderr: \(result.stderr)")
        XCTAssertTrue(result.stderr.contains("SCHEDULED, ARRIVED, READY, STARTED, DEPARTED"))
    }

    func testMWL_definedTermDoesNotWarn() throws {
        let result = try run("dicom-mwl", [
            "query", "localhost", "--aet", "T", "--sps-status", "SCHEDULED",
            "--station", "THIS_AE_TITLE_IS_TOO_LONG_X"])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertFalse(result.stderr.contains("warning: --sps-status"), "stderr: \(result.stderr)")
    }

    /// PS3.4 C.2.2.2.5.1/.2 and the combined date-time remark of Table K.6-1.
    func testMWL_helpCitesRangeMatchingClauses() throws {
        let result = try run("dicom-mwl", ["--help"])
        XCTAssertTrue(result.stdout.contains("C.2.2.2.5.1"))
        XCTAssertTrue(result.stdout.contains("C.2.2.2.5.2"))
        XCTAssertTrue(result.stdout.contains("Table K.6-1"))
        XCTAssertFalse(result.stdout.contains("IN PROGRESS, DISCONTINUED, COMPLETED"))
    }

    // MARK: - dicom-mpps create

    /// PS3.4 F.7.2.1.2: N-CREATE carries only IN PROGRESS.
    func testMPPS_createRejectsTerminalStatus() throws {
        let result = try run("dicom-mpps", [
            "create", "localhost", "--aet", "T", "--study-uid", "1.2.3", "--modality", "CT",
            "--status", "COMPLETED"])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("IN PROGRESS"), "stderr: \(result.stderr)")
    }

    func testMPPS_createRejectsUnknownStatusWord() throws {
        let result = try run("dicom-mpps", [
            "create", "localhost", "--aet", "T", "--study-uid", "1.2.3", "--modality", "CT",
            "--status", "STARTED"])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("'IN PROGRESS', 'COMPLETED', or 'DISCONTINUED'"), "stderr: \(result.stderr)")
    }

    /// PS3.4 Table F.7.2-1: Modality (0008,0060) is 1/1 in the N-CREATE.
    func testMPPS_createRequiresModality() throws {
        let result = try run("dicom-mpps", [
            "create", "localhost", "--aet", "T", "--study-uid", "1.2.3"])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("--modality is required"), "stderr: \(result.stderr)")
        XCTAssertTrue(result.stderr.contains("(0008,0060)"))
        XCTAssertTrue(result.stderr.contains("Table F.7.2-1"))
    }

    /// PS3.3 Table C.2-3: Patient's Sex (0010,0040) Enumerated Values M, F, O.
    func testMPPS_createRejectsPatientSexOutsideEnumeratedValues() throws {
        let result = try run("dicom-mpps", [
            "create", "localhost", "--aet", "T", "--study-uid", "1.2.3", "--modality", "CT",
            "--patient-sex", "X"])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("M, F, O"), "stderr: \(result.stderr)")
        XCTAssertTrue(result.stderr.contains("(0010,0040)"))
    }

    /// PS3.5 Table 6.2-1: DA is YYYYMMDD, 8 bytes fixed.
    func testMPPS_createRejectsNonDABirthDate() throws {
        let result = try run("dicom-mpps", [
            "create", "localhost", "--aet", "T", "--study-uid", "1.2.3", "--modality", "CT",
            "--patient-birth-date", "1970-01-01"])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("YYYYMMDD"), "stderr: \(result.stderr)")
        XCTAssertTrue(result.stderr.contains("VR DA"))
    }

    // MARK: - dicom-mpps update

    /// PS3.4 F.7.2.1.3 / F.7.2.2.2: N-SET reaches COMPLETED or DISCONTINUED only.
    func testMPPS_updateRejectsInProgress() throws {
        let result = try run("dicom-mpps", [
            "update", "localhost", "--aet", "T", "--mpps-uid", "1.2.3", "--status", "IN PROGRESS"])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("COMPLETED or DISCONTINUED"), "stderr: \(result.stderr)")
    }

    /// The status words are the Table C.4-14 Enumerated Values; the space in
    /// IN PROGRESS may be written as `_` or omitted, case-insensitively.
    func testMPPS_updateAcceptsStatusWordSpellings() throws {
        for word in ["in_progress", "INPROGRESS", "In Progress"] {
            let result = try run("dicom-mpps", [
                "update", "localhost", "--aet", "T", "--mpps-uid", "1.2.3", "--status", word])
            XCTAssertTrue(result.stderr.contains("Update status must be COMPLETED or DISCONTINUED"),
                          "\(word) was not parsed as IN PROGRESS: \(result.stderr)")
        }
    }

    /// Referenced Image Sequence items live in a Performed Series item (Table F.7.2-1).
    func testMPPS_updateRejectsImageUIDWithoutSeries() throws {
        let result = try run("dicom-mpps", [
            "update", "localhost", "--aet", "T", "--mpps-uid", "1.2.3", "--status", "COMPLETED",
            "--image-uid", "1.2.3.4"])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("--image-uid needs --study-uid and --series-uid"), "stderr: \(result.stderr)")
        XCTAssertTrue(result.stderr.contains("(0040,0340)"))
    }

    /// PS3.4 Table F.7.2-1: COMPLETED needs a Performed Series item (final state 1);
    /// the engine refuses before connecting.
    func testMPPS_updateCompletedWithoutSeriesFailsBeforeConnecting() throws {
        let result = try run("dicom-mpps", [
            "update", "localhost", "--aet", "T", "--mpps-uid", "1.2.3", "--status", "COMPLETED"])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("Performed Series Sequence (0040,0340)"), "stderr: \(result.stderr)")
    }

    func testMPPS_discontinuationReasonOnlyWithDiscontinued() throws {
        let result = try run("dicom-mpps", [
            "update", "localhost", "--aet", "T", "--mpps-uid", "1.2.3", "--status", "COMPLETED",
            "--discontinuation-reason", "110513|DCM|Discontinued for unspecified reason"])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("only valid with --status DISCONTINUED"), "stderr: \(result.stderr)")
    }

    /// PS3.16 CID 9300 / CID 9301 (Table D-1): 110513 is "Discontinued for unspecified
    /// reason"; the old example paired it with the meaning of 110500.
    func testMPPS_helpCitesCID9300CodesWithTheirTableD1Meanings() throws {
        let result = try run("dicom-mpps", ["update", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        // ArgumentParser wraps help text; collapse every whitespace run to one space.
        let help = result.stdout.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        XCTAssertTrue(help.contains("110513|DCM|Discontinued for unspecified reason"), "help: \(help)")
        XCTAssertTrue(help.contains("110500|DCM|Doctor canceled procedure"))
        XCTAssertTrue(help.contains("110501|DCM|Equipment failure"))
        XCTAssertTrue(help.contains("110507|DCM|Patient did not arrive"))
        XCTAssertFalse(help.contains("110513|DCM|Doctor cancelled procedure"))
        XCTAssertFalse(help.contains("110518"))
    }

    // MARK: - dicom-mpps response status wording (D220)

    /// The CLI words N-CREATE statuses with DICOMNetwork's DIMSEServiceStatusText
    /// (PS3.7 2026a Annex C; MPPS N-CREATE has no specific codes, PS3.4 F.7.2.1.4):
    /// a failure arrives as `mppsOperationFailed`, a warning is printed from the
    /// same table. Before D220 it kept its own copy of the Annex C names.
    func testMPPS_createFailureAndWarningAreWordedPerAnnexC() async throws {
        #if canImport(Network)
        for (code, expected, failed) in [
            (UInt16(0x0106), "Failure (0x0106): Invalid Attribute Value", true),
            (UInt16(0x0107), "Warning (0x0107): Attribute List warning", false),
        ] {
            let scp = MockPrintSCP(behavior: MockPrintSCPBehavior(
                failOn: .nCreateRequest, failStatus: DIMSEStatus.from(code)))
            try await scp.start()
            let port = await scp.port
            let result = try run("dicom-mpps", [
                "create", "127.0.0.1", "--port", String(port), "--aet", "T",
                "--study-uid", "1.2.3", "--modality", "CT", "--timeout", "10"])
            await scp.stop()
            XCTAssertEqual(result.exitCode != 0, failed, "exit \(result.exitCode): \(result.all)")
            XCTAssertTrue(result.all.contains(expected), "output: \(result.all)")
            XCTAssertFalse(result.all.contains("(PS3.7 C.5.11)"), "the CLI's own table is gone")
        }
        #endif
    }

    func testMPPS_rootHelpNamesTheEnumeratedStatusValues() throws {
        let result = try run("dicom-mpps", ["--help"])
        XCTAssertTrue(result.stdout.contains("Table C.4-14"))
        XCTAssertTrue(result.stdout.contains("\"IN PROGRESS\""))
        XCTAssertTrue(result.stdout.contains("COMPLETED | DISCONTINUED"))
    }
}

#endif
