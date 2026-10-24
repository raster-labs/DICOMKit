//
// PrintCLIEndToEndTests.swift
// DICOMNetworkTests
//
// Spawn-based end-to-end tests for the dicom-print executable: exit codes,
// the stdout/stderr output contract, and a full print against the in-process
// MockPrintSCP. (Post-plan pending-work item #7.)
//

import XCTest
import Foundation
import DICOMCore
import DICOMKit
@testable import DICOMNetwork

#if os(macOS)
import Darwin

final class PrintCLIEndToEndTests: XCTestCase {

    // MARK: - Helpers

    /// Directory containing the built products (…/debug), derived from the
    /// test bundle location.
    private var productsDirectory: URL {
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("test bundle not found")
    }

    private var binaryURL: URL {
        productsDirectory.appendingPathComponent("dicom-print")
    }

    private struct RunResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private enum ProcessRunError: Error {
        case timeout(arguments: [String], stdout: String, stderr: String)
    }

    @discardableResult
    private func runCLI(
        _ arguments: [String], timeout: TimeInterval = 30,
        executable: URL? = nil
    ) throws -> RunResult {
        // Files keep either output stream from blocking the child while the
        // deadline is being observed. Sequential Pipe reads cannot do that.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dicom-print-process-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdoutURL = directory.appendingPathComponent("stdout.txt")
        let stderrURL = directory.appendingPathComponent("stderr.txt")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdoutFile = try FileHandle(forWritingTo: stdoutURL)
        let stderrFile = try FileHandle(forWritingTo: stderrURL)
        defer { try? stdoutFile.close(); try? stderrFile.close() }

        let process = Process()
        process.executableURL = executable ?? binaryURL
        process.arguments = arguments
        process.standardOutput = stdoutFile
        process.standardError = stderrFile
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        try process.run()
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        let timedOut = process.isRunning
        if timedOut {
            process.terminate()
            let grace = ProcessInfo.processInfo.systemUptime + 1
            while process.isRunning && ProcessInfo.processInfo.systemUptime < grace {
                Thread.sleep(forTimeInterval: 0.01)
            }
            if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
            let killDeadline = ProcessInfo.processInfo.systemUptime + 1
            while process.isRunning && ProcessInfo.processInfo.systemUptime < killDeadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        // Never waitUntilExit unconditionally: the timeout itself must remain bounded.
        try stdoutFile.synchronize()
        try stderrFile.synchronize()
        let stdout = String(data: try Data(contentsOf: stdoutURL), encoding: .utf8) ?? ""
        let stderr = String(data: try Data(contentsOf: stderrURL), encoding: .utf8) ?? ""
        if timedOut { throw ProcessRunError.timeout(arguments: arguments, stdout: stdout, stderr: stderr) }
        return RunResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    func testProcessDeadlineThrowsInsteadOfWaitingForOutputEOF() throws {
        let started = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try runCLI(
            ["5"], timeout: 0.1, executable: URL(fileURLWithPath: "/bin/sleep")
        )) { error in
            guard case ProcessRunError.timeout = error else {
                return XCTFail("Expected explicit timeout, got \(error)")
            }
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 3)
    }

    /// Writes a minimal but valid Explicit VR LE DICOM file (2×2 8-bit
    /// MONOCHROME2) and returns its path.
    private func writeFixtureFile() throws -> String {
        var meta = DataSet()
        meta.setString("1.2.840.10008.1.2.1", for: Tag(group: 0x0002, element: 0x0010), vr: .UI) // Transfer Syntax
        meta.setString("1.2.840.10008.5.1.4.1.1.7", for: Tag(group: 0x0002, element: 0x0002), vr: .UI) // SC Storage
        meta.setString("1.2.826.0.1.3680043.9.9002.1", for: Tag(group: 0x0002, element: 0x0003), vr: .UI)

        var dataSet = DataSet()
        dataSet.setString("1.2.840.10008.5.1.4.1.1.7", for: Tag(group: 0x0008, element: 0x0016), vr: .UI)
        dataSet.setString("1.2.826.0.1.3680043.9.9002.1", for: Tag(group: 0x0008, element: 0x0018), vr: .UI)
        dataSet.setUInt16(2, for: .rows)
        dataSet.setUInt16(2, for: .columns)
        dataSet.setUInt16(8, for: .bitsAllocated)
        dataSet.setUInt16(8, for: .bitsStored)
        dataSet.setUInt16(7, for: .highBit)
        dataSet.setUInt16(0, for: .pixelRepresentation)
        dataSet.setUInt16(1, for: .samplesPerPixel)
        dataSet.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        dataSet[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: Data([0, 64, 128, 255]))

        let file = DICOMFile(fileMetaInformation: meta, dataSet: dataSet)
        let bytes = try file.write()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dicom-print-e2e-\(UUID().uuidString).dcm")
        try bytes.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url.path
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(
            FileManager.default.isExecutableFile(atPath: binaryURL.path),
            "dicom-print binary not present in products directory (build executables first)")
    }

    // MARK: - Basic exit codes

    func testVersionExitsZero() throws {
        let result = try runCLI(["--version"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.stdout.isEmpty)
    }

    func testOutOfRangePortFailsValidation() throws {
        let fixture = try writeFixtureFile()
        let result = try runCLI(["send", "pacs://localhost:99999", fixture, "--aet", "TEST"])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("out of range"), "stderr: \(result.stderr)")
    }

    func testConflictingRawAndBitDepthFailsValidation() throws {
        let fixture = try writeFixtureFile()
        let result = try runCLI([
            "send", "pacs://localhost:11112", fixture, "--aet", "TEST",
            "--raw", "--bit-depth", "12"
        ])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("--raw"), "stderr: \(result.stderr)")
    }

    func testDryRunExitsZeroWithoutNetwork() throws {
        let fixture = try writeFixtureFile()
        // Port 1 — nothing listens there; --dry-run must return before connecting.
        let result = try runCLI(["send", "pacs://127.0.0.1:1", fixture, "--aet", "TEST", "--dry-run"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("Dry run"), "stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.isEmpty, "text mode must keep stdout empty")
    }

    // MARK: - Output contract against the mock SCP

    func testSendJSONContractAndExitZero() async throws {
        let scp = MockPrintSCP()
        try await scp.start()
        defer { Task { await scp.stop() } }
        let port = await scp.port

        let fixture = try writeFixtureFile()
        let result = try runCLI([
            "send", "pacs://127.0.0.1:\(port)", fixture,
            "--aet", "TEST_SCU", "--called-aet", "MOCK_SCP",
            "--format", "json"
        ])

        XCTAssertEqual(result.exitCode, 0, "stderr: \(result.stderr)")

        // stdout must be exactly one JSON object (machine-readable contract).
        guard let data = result.stdout.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("stdout is not a JSON object: \(result.stdout)")
        }
        XCTAssertEqual(object["success"] as? Bool, true)
        XCTAssertEqual(object["printJobUID"] as? String, "1.2.826.0.1.3680043.9.9001.1.1")
        XCTAssertNotNil(object["filmSessionUID"])
    }

    func testSendFailureExitsNonZero() async throws {
        var behavior = MockPrintSCPBehavior()
        behavior.failOn = .nSetRequest
        behavior.errorComment = "OUT OF FILM"
        let scp = MockPrintSCP(behavior: behavior)
        try await scp.start()
        defer { Task { await scp.stop() } }
        let port = await scp.port

        let fixture = try writeFixtureFile()
        let result = try runCLI([
            "send", "pacs://127.0.0.1:\(port)", fixture,
            "--aet", "TEST_SCU", "--called-aet", "MOCK_SCP"
        ])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("OUT OF FILM"),
                      "printer diagnostic text must reach the user; stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.isEmpty, "failures must not write to stdout in text mode")
    }
}

#endif
