//
// QueryRetrieveCLIStandardTests.swift
// DICOMNetworkTests
//
// DICOM 2026a verification of dicom-retrieve and dicom-qr (2026-10-01).
// Tests/DICOMToolsTests is not compiled by any target, so this lives beside
// PrintCLIEndToEndTests: the status table is DICOMNetwork.DIMSEServiceStatusText
// and the behaviour is checked by spawning the built products.
//

import XCTest
import Foundation
@testable import DICOMNetwork

final class QueryRetrieveCLIStandardTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// PS3.4 2026a Table C.4-2 (C-MOVE, 9 rows) and Table C.4-3 (C-GET, 8 rows),
    /// dumped by Scripts/nema_docbook.py: Status Code, Service Status, Further Meaning.
    private static let ps34StatusRows: [(table: String, code: String, serviceStatus: String, furtherMeaning: String)] = [
        ("C.4-2", "A701", "Failure", "Refused: Out of resources - Unable to calculate number of matches"),
        ("C.4-2", "A702", "Failure", "Refused: Out of resources - Unable to perform sub-operations"),
        ("C.4-2", "A801", "Failure", "Refused: Move Destination unknown"),
        ("C.4-2", "A900", "Failure", "Error: Data Set does not match SOP Class"),
        ("C.4-2", "Cxxx", "Failure", "Failed: Unable to process"),
        ("C.4-2", "FE00", "Cancel", "Sub-operations terminated due to Cancel Indication"),
        ("C.4-2", "B000", "Warning", "Sub-operations Complete - One or more Failures"),
        ("C.4-2", "0000", "Success", "Sub-operations Complete - No Failures"),
        ("C.4-2", "FF00", "Pending", "Sub-operations are continuing"),
        ("C.4-3", "A701", "Failure", "Refused: Out of resources - Unable to calculate number of matches"),
        ("C.4-3", "A702", "Failure", "Refused: Out of resources - Unable to perform sub-operations"),
        ("C.4-3", "A900", "Failure", "Error: Data Set does not match SOP Class"),
        ("C.4-3", "Cxxx", "Failure", "Failed: Unable to process"),
        ("C.4-3", "FE00", "Cancel", "Sub-operations terminated due to Cancel Indication"),
        ("C.4-3", "B000", "Warning", "Sub-operations Complete - One or more Failures or Warnings"),
        ("C.4-3", "0000", "Success", "Sub-operations Complete - No Failures or Warnings"),
        ("C.4-3", "FF00", "Pending", "Sub-operations are continuing"),
    ]

    // MARK: - DIMSEServiceStatusText (PS3.4 Tables B.2-1, C.4-1, C.4-2, C.4-3)

    /// Every row of PS3.4 2026a Tables C.4-2 / C.4-3 is carried verbatim by the
    /// DICOMNetwork table the CLI tools now use (hoisted from the tools' former
    /// RetrieveStatusText copies, P-QR-STATUS-TEXT), and nothing else is.
    func testServiceStatusTextCarriesPS34RetrieveTables2026a() {
        for (service, table) in [(DIMSEStatusService.cMove, "C.4-2"), (.cGet, "C.4-3")] {
            let expected = Self.ps34StatusRows.filter { $0.table == table }
                .map { DIMSEServiceStatusRow(code: $0.code, serviceStatus: $0.serviceStatus, furtherMeaning: $0.furtherMeaning) }
            XCTAssertEqual(DIMSEServiceStatusText.rows(for: service), expected, "Table \(table)")
            XCTAssertEqual(service.statusTable, table)
        }
    }

    /// PS3.4 2026a Table B.2-1 (C-STORE, 7 rows) and Table C.4-1 (C-FIND, 7 rows),
    /// dumped by Scripts/nema_docbook.py.
    func testServiceStatusTextCarriesPS34StoreAndFindTables2026a() {
        let store: [(String, String, String)] = [
            ("A7xx", "Failure", "Refused: Out of resources"),
            ("A9xx", "Failure", "Error: Data Set does not match SOP Class"),
            ("Cxxx", "Failure", "Error: Cannot understand"),
            ("B000", "Warning", "Coercion of Data Elements"),
            ("B007", "Warning", "Data Set does not match SOP Class"),
            ("B006", "Warning", "Elements Discarded"),
            ("0000", "Success", "Success"),
        ]
        let find: [(String, String, String)] = [
            ("A700", "Failure", "Refused: Out of resources"),
            ("A900", "Failure", "Error: Data Set does not match SOP Class"),
            ("Cxxx", "Failure", "Failed: Unable to process"),
            ("FE00", "Cancel", "Matching terminated due to Cancel request"),
            ("0000", "Success", "Matching is complete - No final Identifier is supplied."),
            ("FF00", "Pending", "Matches are continuing - Current Match is supplied and any Optional Keys were supported in the same manner as Required Keys."),
            ("FF01", "Pending", "Matches are continuing - Warning that one or more Optional Keys were not supported for existence and/or matching for this Identifier."),
        ]
        XCTAssertEqual(DIMSEServiceStatusText.rows(for: .cStore),
                       store.map { DIMSEServiceStatusRow(code: $0.0, serviceStatus: $0.1, furtherMeaning: $0.2) })
        XCTAssertEqual(DIMSEServiceStatusText.rows(for: .cFind),
                       find.map { DIMSEServiceStatusRow(code: $0.0, serviceStatus: $0.1, furtherMeaning: $0.2) })
    }

    /// The service decides the wording (D76): 0xB000, 0xA701, 0xA801, 0xA900 and
    /// Cxxx read as PS3.4 names them for the service that answered; ranges match
    /// and codes outside the table fall back to DIMSEStatus.description.
    func testServiceAwareDescriptionsPerPS34() {
        XCTAssertEqual(DIMSEStatus.from(0xB000).description(for: .cMove),
                       "Warning (0xB000): Sub-operations Complete - One or more Failures")
        XCTAssertEqual(DIMSEStatus.from(0xB000).description(for: .cGet),
                       "Warning (0xB000): Sub-operations Complete - One or more Failures or Warnings")
        XCTAssertEqual(DIMSEStatus.from(0xB000).description(for: .cStore),
                       "Warning (0xB000): Coercion of Data Elements")
        XCTAssertEqual(DIMSEStatus.from(0xA701).description(for: .cMove),
                       "Failure (0xA701): Refused: Out of resources - Unable to calculate number of matches")
        XCTAssertEqual(DIMSEStatus.from(0xA801).description(for: .cMove),
                       "Failure (0xA801): Refused: Move Destination unknown")
        XCTAssertEqual(DIMSEStatus.from(0xC123).description(for: .cGet),
                       "Failure (0xC123): Failed: Unable to process")
        XCTAssertEqual(DIMSEStatus.from(0xC123).description(for: .cStore),
                       "Failure (0xC123): Error: Cannot understand")
        XCTAssertEqual(DIMSEStatus.from(0xA7FE).description(for: .cStore),
                       "Failure (0xA7FE): Refused: Out of resources")
        XCTAssertEqual(DIMSEStatus.from(0xA900).description(for: .cStore),
                       "Failure (0xA900): Error: Data Set does not match SOP Class")
        XCTAssertEqual(DIMSEStatus.from(0xA801).description(for: .cGet),
                       "Refused: Move Destination unknown (0xA801) (not listed in PS3.4 Table C.4-3)")
        XCTAssertEqual(DIMSEServiceStatusText.subOperationCounts(RetrieveProgress(completed: 3, failed: 1, warning: 2)),
                       "Number of Completed Sub-operations: 3, Number of Failed Sub-operations: 1, Number of Warning Sub-operations: 2")
    }

    /// The tools no longer carry a private copy of the table.
    func testToolsUseTheSharedStatusTable() {
        for tool in ["dicom-retrieve", "dicom-qr"] {
            let copy = Self.repoRoot.appendingPathComponent("Sources/\(tool)/RetrieveStatusText.swift")
            XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path), "\(tool) still has its own status table")
        }
    }

    #if os(macOS)
    // MARK: - dicom-retrieve (spawned)

    /// Help names the Query/Retrieve Level values of PS3.4 Table C.6.1-1 and the
    /// Move Destination of PS3.7 Table 9.3-9.
    func testRetrieveHelpNamesStandardConcepts() throws {
        guard let run = try runBuiltProduct("dicom-retrieve", ["--help"]) else {
            throw XCTSkip("dicom-retrieve is not built in the products directory")
        }
        XCTAssertEqual(run.exitCode, 0)
        let help = squeezed(run.stdout)
        for needle in ["Query/Retrieve Level STUDY", "Query/Retrieve Level SERIES",
                       "Query/Retrieve Level IMAGE", "Move Destination (0000,0600)",
                       "Study Root Query/Retrieve Information Model - MOVE",
                       "Study Root Query/Retrieve Information Model - GET"] {
            XCTAssertTrue(help.contains(needle), "help lacks \(needle)")
        }
    }

    /// Exit codes: 64 for a usage error (C-MOVE without a move destination,
    /// PS3.4 C.4.2.2.1), 1 when the retrieve cannot complete.
    func testRetrieveExitCodesForUsageAndTransportFailure() throws {
        guard let usage = try runBuiltProduct("dicom-retrieve",
            ["127.0.0.1:1", "--aet", "TEST", "--study-uid", "1.2.3"]) else {
            throw XCTSkip("dicom-retrieve is not built in the products directory")
        }
        XCTAssertEqual(usage.exitCode, 64, usage.stderr)
        XCTAssertTrue(usage.stderr.contains("--move-dest"), usage.stderr)

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("dicom-retrieve-e2e-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let failed = try XCTUnwrap(runBuiltProduct("dicom-retrieve",
            ["127.0.0.1:1", "--aet", "TEST", "--method", "c-get", "--study-uid", "1.2.3",
             "--timeout", "2", "--output", tmp.path]))
        XCTAssertEqual(failed.exitCode, 1, failed.stderr)
        XCTAssertTrue(failed.stdout.contains("Level:"), failed.stdout)
    }

    // MARK: - dicom-qr (spawned)

    /// Help names the match keys with their PS3.6 tags and the Move Destination
    /// of PS3.7 Table 9.3-9.
    func testQRQueryHelpNamesStandardConcepts() throws {
        guard let run = try runBuiltProduct("dicom-qr", ["query", "--help"]) else {
            throw XCTSkip("dicom-qr is not built in the products directory")
        }
        XCTAssertEqual(run.exitCode, 0)
        let help = squeezed(run.stdout)
        for needle in ["Patient's Name (0010,0010)", "Patient ID (0010,0020)", "Study Date (0008,0020)",
                       "Study Instance UID (0020,000D)", "Accession Number (0008,0050)",
                       "Study Description (0008,1030)", "Move Destination (0000,0600)",
                       "-YYYYMMDD or YYYYMMDD-"] {
            XCTAssertTrue(help.contains(needle), "help lacks \(needle)")
        }
    }

    /// `resume` exits non-zero when a study could not be retrieved (previously it
    /// printed "Failed: 1" and exited 0), and honours the new --timeout.
    func testQRResumeExitsNonZeroWhenAStudyFails() throws {
        let state = QRRetrievalState(
            studies: [], host: "127.0.0.1", port: 1, callingAE: "TEST", calledAE: "ANY-SCP",
            moveDestination: nil, method: .cGet, outputPath: FileManager.default.temporaryDirectory.path,
            hierarchical: false)
        // One study row on top of the shared encoder's output, so the file is what --save-state writes.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: QRSessionState.encode(state)) as? [String: Any])
        json["studies"] = [["studyInstanceUID": "1.2.3", "patientName": "E2E^TEST"]]
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("dicom-qr-e2e-\(UUID().uuidString).state")
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        guard let run = try runBuiltProduct("dicom-qr", ["resume", "--state", file.path, "--timeout", "2"]) else {
            throw XCTSkip("dicom-qr is not built in the products directory")
        }
        XCTAssertEqual(run.exitCode, 1, run.stderr)
        XCTAssertTrue(run.stdout.contains("Failed: 1"), run.stdout)
        XCTAssertTrue(run.stderr.contains("Retrieval incomplete: 0 study(ies) succeeded, 1 failed"), run.stderr)
    }

    // MARK: - Spawn helper (pattern of PrintCLIEndToEndTests)

    private struct RunResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private func squeezed(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
    }

    /// Runs a built product from the test bundle's products directory, or returns
    /// nil when the executable has not been built there (the caller skips).
    private func runBuiltProduct(_ name: String, _ arguments: [String], timeout: TimeInterval = 60) throws -> RunResult? {
        var productsDirectory: URL?
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            productsDirectory = bundle.bundleURL.deletingLastPathComponent()
        }
        guard let binary = productsDirectory?.appendingPathComponent(name),
              FileManager.default.isExecutableFile(atPath: binary.path) else { return nil }

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
            XCTFail("\(name) did not exit within \(timeout)s: \(arguments)")
        }
        process.waitUntilExit()
        return RunResult(exitCode: process.terminationStatus,
                         stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                         stderr: String(data: stderrData, encoding: .utf8) ?? "")
    }
    #endif
}
