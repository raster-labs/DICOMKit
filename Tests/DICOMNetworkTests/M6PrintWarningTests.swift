import XCTest
import Foundation
@testable import DICOMNetwork

#if canImport(Network)
final class M6PrintWarningTests: XCTestCase {
    /// A subsequent successful film and cleanup must not overwrite an earlier
    /// accepted-but-demagnified film warning (PS3.4 2026a Table H.4-9, B604).
    func testFilmActionWarningSurvivesLaterSuccessfulFilmAndCleanup() async throws {
        var behavior = MockPrintSCPBehavior()
        behavior.failOn = .nActionRequest
        behavior.failStatus = .from(0xB604)
        behavior.errorComment = "M6 IMAGE DEMAGNIFIED"
        let scp = MockPrintSCP(behavior: behavior)
        try await scp.start()
        do {
            let pixels = Data([0, 64, 128, 255])
            let image = PrintImageData(pixelData: pixels, rows: 2, columns: 2,
                                       bitsAllocated: 8, bitsStored: 8, highBit: 7,
                                       samplesPerPixel: 1, pixelRepresentation: 0,
                                       photometricInterpretation: "MONOCHROME2")
            let result = try await DICOMPrintService.printImages(
                configuration: PrintConfiguration(host: "127.0.0.1", port: await scp.port,
                                                   callingAETitle: "M6WARN", calledAETitle: "MOCK_SCP", timeout: 5),
                images: [pixels, pixels], imageDescriptors: [image, image], layout: .singleImage)
            XCTAssertTrue(result.success, "A DICOM warning still means the film was accepted")
            XCTAssertEqual(result.status.rawValue, 0xB604)
            XCTAssertEqual(result.filmBoxUIDs.count, 2)
            XCTAssertEqual(result.warnings.count, 1)
            let warning = try XCTUnwrap(result.warnings.first)
            XCTAssertEqual(warning.filmBoxUID, result.filmBoxUIDs.first)
            XCTAssertEqual(warning.status.rawValue, 0xB604)
            XCTAssertEqual(warning.detail, "M6 IMAGE DEMAGNIFIED")
            XCTAssertTrue(warning.message.contains("demagnified"))
            let log = await scp.commandLog
            XCTAssertEqual(log.filter { $0 == .nActionRequest }.count, 2, "No print retry/duplication")
            let released = await scp.releasedCleanly
            XCTAssertTrue(released)
            await scp.stop()
        } catch {
            await scp.stop()
            throw error
        }
    }

    func testOrdinarySuccessHasNoWarning() async throws {
        let scp = MockPrintSCP()
        try await scp.start()
        do {
            let pixels = Data([0, 64, 128, 255])
            let image = PrintImageData(pixelData: pixels, rows: 2, columns: 2,
                                       bitsAllocated: 8, bitsStored: 8, highBit: 7,
                                       samplesPerPixel: 1, pixelRepresentation: 0,
                                       photometricInterpretation: "MONOCHROME2")
            let result = try await DICOMPrintService.printImages(
                configuration: PrintConfiguration(host: "127.0.0.1", port: await scp.port,
                                                   callingAETitle: "M6WARN", calledAETitle: "MOCK_SCP", timeout: 5),
                images: [pixels], imageDescriptors: [image])
            XCTAssertTrue(result.success)
            XCTAssertEqual(result.status, .success)
            XCTAssertTrue(result.warnings.isEmpty)
            await scp.stop()
        } catch {
            await scp.stop()
            throw error
        }
    }
}
#endif
