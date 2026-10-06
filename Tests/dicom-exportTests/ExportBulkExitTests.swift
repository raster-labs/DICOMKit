import XCTest
import DICOMCore
@testable import DICOMKit
@testable import dicom_export

/// D251: `dicom-export bulk` exits 1 after its summary line when any file failed, like
/// dicom-convert's directory run (P-CONVERT-EXIT); a run with no failed file exits 0.
/// (Tool contract; no DICOM rule.)
final class ExportBulkExitTests: XCTestCase {

    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dicom-export-bulk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    #if canImport(CoreGraphics)
    func testBulkWithAFailedFileExitsOne() throws {
        let input = try tempDir(), output = try tempDir()
        try Data("not a DICOM file".utf8).write(to: input.appendingPathComponent("broken.dcm"))
        var command = try DICOMExport.Bulk.parse([input.path, "-o", output.path])
        XCTAssertThrowsError(try command.run()) { error in
            XCTAssertEqual(DICOMExport.exitCode(for: error).rawValue, 1)
        }
    }

    func testBulkWithNoFailedFileExitsZero() throws {
        let input = try tempDir(), output = try tempDir()
        var command = try DICOMExport.Bulk.parse([input.path, "-o", output.path])
        XCTAssertNoThrow(try command.run())
    }
    #endif

    // MARK: - D252: the CLI names forward to the DICOMKit types

    @available(*, deprecated)
    func testCLINamesForwardToTheEngine() {
        XCTAssertTrue(CineFrameRate.self == DICOMImageExporter.CineFrameRate.self)
        XCTAssertTrue(ExportFrameSelectionConflict.self == DICOMImageExporter.FrameSelectionConflict.self)
        XCTAssertEqual(ExportFrameSelection.reference, DICOMImageExporter.FrameSelection.reference)
        XCTAssertEqual(ExportApplyWindowDeprecation.note(subcommand: "bulk"),
                       DICOMImageExporter.ApplyWindowDeprecation.note(subcommand: "bulk"))
        XCTAssertEqual(BurnedInAnnotation.summaryWarning(count: 2),
                       DICOMImageExporter.BurnedInAnnotation.summaryWarning(count: 2))
    }
}
