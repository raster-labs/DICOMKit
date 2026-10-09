import XCTest
import ArgumentParser
import DICOMCore
import DICOMKit
@testable import dicom_image

/// D273: a dicom-image directory run exits 1 after its summary when any file failed, like
/// dicom-convert's directory run (P-CONVERT-EXIT); a run with no failed file exits 0.
/// (Tool contract; no DICOM rule.)
final class ImageDirectoryExitTests: XCTestCase {

    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dicom-image-dir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    #if canImport(CoreGraphics)
    func testDirectoryRunWithAFailedFileExitsOne() throws {
        let input = try tempDir(), output = try tempDir()
        try Data("not a PNG".utf8).write(to: input.appendingPathComponent("broken.png"))
        var command = try DICOMImage.parse([input.path, "-o", output.path, "--recursive",
                                            "--patient-name", "DOE^JOHN", "--patient-id", "P1"])
        XCTAssertThrowsError(try command.run()) { error in
            XCTAssertEqual(DICOMImage.exitCode(for: error).rawValue, 1)
        }
    }

    func testDirectoryRunWithNoFailedFileExitsZero() throws {
        let input = try tempDir(), output = try tempDir()
        try Data("skipped, not an image".utf8).write(to: input.appendingPathComponent("notes.txt"))
        var command = try DICOMImage.parse([input.path, "-o", output.path, "--recursive",
                                            "--patient-name", "DOE^JOHN", "--patient-id", "P1"])
        XCTAssertNoThrow(try command.run())
    }
    #endif

    @available(*, deprecated)
    func testSCOutputForwardsToTheEngine() {
        XCTAssertTrue(SCOutput.self == ImageConverter.OutputRules.self)
    }
}
