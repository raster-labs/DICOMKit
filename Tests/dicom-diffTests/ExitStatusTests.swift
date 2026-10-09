import XCTest
import Foundation
import ArgumentParser
import DICOMCore
import DICOMKit
@testable import dicom_diff

/// P-DIFF-1 (approved 2026-10-01): exit 0 identical, 1 different, 2 when a file is missing or
/// cannot be read or parsed as DICOM (the diff(1)/cmp(1) convention).
final class ExitStatusTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("dicom-diff-exit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(patientID: String, name: String) throws -> String {
        var dataSet = DataSet()
        dataSet.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
        dataSet.setString("1.2.826.0.1.3680043.10.999.4.1", for: .sopInstanceUID, vr: .UI)
        dataSet.setString(patientID, for: .patientID, vr: .LO)
        let url = dir.appendingPathComponent(name)
        try DICOMFile.create(dataSet: dataSet).write().write(to: url)
        return url.path
    }

    private func exitCode(_ arguments: [String]) -> Int32 {
        do {
            var command = try DICOMDiff.parse(arguments + ["--format", "summary"])
            try command.run()
            return 0
        } catch let code as ExitCode {
            return code.rawValue
        } catch {
            return DICOMDiff.exitCode(for: error).rawValue
        }
    }

    func testIdenticalIsZeroDifferentIsOne() throws {
        let a = try write(patientID: "P1", name: "a.dcm")
        let b = try write(patientID: "P1", name: "b.dcm")
        let c = try write(patientID: "P2", name: "c.dcm")
        XCTAssertEqual(exitCode([a, b]), 0)
        XCTAssertEqual(exitCode([a, c]), 1)
    }

    func testMissingFileIsTwo() throws {
        let a = try write(patientID: "P1", name: "a.dcm")
        XCTAssertEqual(exitCode([a, dir.appendingPathComponent("missing.dcm").path]), 2)
        XCTAssertEqual(exitCode([dir.appendingPathComponent("missing.dcm").path, a]), 2)
    }

    func testUnparsableFileIsTwo() throws {
        let a = try write(patientID: "P1", name: "a.dcm")
        let junk = dir.appendingPathComponent("junk.dcm")
        try Data("not a DICOM file".utf8).write(to: junk)
        XCTAssertEqual(exitCode([a, junk.path]), 2)
    }

    func testInvalidIgnoreTagStaysAUsageError() throws {
        let a = try write(patientID: "P1", name: "a.dcm")
        XCTAssertEqual(exitCode([a, a, "--ignore-tag", "NotAKeyword"]), ExitCode.validationFailure.rawValue)
    }

    func testHelpDocumentsTheExitStatus() {
        XCTAssertTrue(DICOMDiff.helpMessage().contains("2 a file is missing"))
    }
}
