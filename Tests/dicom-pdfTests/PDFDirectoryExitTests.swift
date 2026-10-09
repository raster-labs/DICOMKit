import XCTest
import ArgumentParser
import DICOMKit
import DICOMCore
@testable import dicom_pdf

/// D271: dicom-pdf directory runs (extract and encapsulate) exit 1 after the summary when
/// any file failed, like dicom-convert's directory run (P-CONVERT-EXIT); extract skips a file
/// that is not an Encapsulated Document. D272: the option
/// refusals keep ArgumentParser's ValidationError exit code after the lift.
final class PDFDirectoryExitTests: XCTestCase {

    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dicom-pdf-dir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// A DICOM file with Encapsulated Document (0042,0011) but without the Type 1 MIME Type of
    /// Encapsulated Document (0042,0012) (PS3.3 2026a Table C.24-2): a document that fails to extract.
    private func brokenDocument() throws -> Data {
        var ds = DataSet()
        ds.setString(EncapsulatedDocument.encapsulatedPDFStorageUID, for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4.5", for: .sopInstanceUID, vr: .UI)
        ds.setString("1.2.3.4", for: .studyInstanceUID, vr: .UI)
        ds.setString("1.2.3.4.1", for: .seriesInstanceUID, vr: .UI)
        ds[.encapsulatedDocument] = DataElement.data(tag: .encapsulatedDocument, vr: .OB, data: Data("%PDF-1.4\n".utf8))
        return try DICOMFile.create(dataSet: ds).write()
    }

    /// A Secondary Capture data set: DICOM, but not an Encapsulated Document.
    private func notADocument() throws -> Data {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4.6", for: .sopInstanceUID, vr: .UI)
        return try DICOMFile.create(dataSet: ds).write()
    }

    func testExtractDirectoryWithAFailedDocumentExitsOne() throws {
        let input = try tempDir(), output = try tempDir()
        try brokenDocument().write(to: input.appendingPathComponent("broken.dcm"))
        var command = try DICOMPdf.parse([input.path, "--output", output.path, "--extract", "--recursive"])
        XCTAssertThrowsError(try command.run()) { error in
            XCTAssertEqual(DICOMPdf.exitCode(for: error).rawValue, 1)
        }
    }

    /// D271 (2026-10-06): a file that is not an Encapsulated Document is skipped, as dicom-image
    /// skips non-images and dicom-export files without pixel data; the run exits 0.
    func testExtractDirectorySkipsFilesThatAreNotEncapsulatedDocuments() throws {
        let input = try tempDir(), output = try tempDir()
        try Data("not DICOM".utf8).write(to: input.appendingPathComponent("notes.txt"))
        try notADocument().write(to: input.appendingPathComponent("sc.dcm"))
        var command = try DICOMPdf.parse([input.path, "--output", output.path, "--extract", "--recursive", "--verbose"])
        XCTAssertNoThrow(try command.run())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path), [])
        XCTAssertEqual(DICOMPdf.skippedLine(fileName: "sc.dcm"), "⊘ sc.dcm: not an Encapsulated Document (skipped)")
    }

    func testEncapsulateDirectoryWithAFailedFileExitsOne() throws {
        let input = try tempDir(), output = try tempDir()
        let unreadable = input.appendingPathComponent("locked.pdf")
        try Data("%PDF-1.4\n".utf8).write(to: unreadable)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.path) }
        try XCTSkipIf(FileManager.default.isReadableFile(atPath: unreadable.path), "running with permission to read a 000 file")
        var command = try DICOMPdf.parse([input.path, "--output", output.path, "--recursive",
                                          "--patient-name", "DOE^JOHN", "--patient-id", "P1"])
        XCTAssertThrowsError(try command.run()) { error in
            XCTAssertEqual(DICOMPdf.exitCode(for: error).rawValue, 1)
        }
    }

    func testDirectoryRunsWithNoFailedFileExitZero() throws {
        let input = try tempDir(), output = try tempDir()
        var extract = try DICOMPdf.parse([input.path, "--output", output.path, "--extract", "--recursive"])
        XCTAssertNoThrow(try extract.run())
        var encapsulate = try DICOMPdf.parse([input.path, "--output", output.path, "--recursive",
                                              "--patient-name", "DOE^JOHN", "--patient-id", "P1"])
        XCTAssertNoThrow(try encapsulate.run())
    }

    func testOptionRefusalsStayValidationErrors() {
        XCTAssertThrowsError(try PDFOptionValues.conversionType("SCAN")) { error in
            XCTAssertTrue(error is ArgumentParser.ValidationError)
            XCTAssertEqual(DICOMPdf.exitCode(for: error), ExitCode.validationFailure)
            XCTAssertEqual(DICOMPdf.message(for: error),
                           "--conversion-type SCAN is not a Conversion Type (0008,0064) Defined Term of PS3.3 Table C.8-24: DV, DI, DF, WSD, SD, SI, DRW, SYN")
        }
        XCTAssertThrowsError(try PDFOptionValues.burnedInAnnotation("Y")) { error in
            XCTAssertTrue(error is ArgumentParser.ValidationError)
        }
        XCTAssertEqual(try PDFOptionValues.burnedInAnnotation("no"), false)
    }

    @available(*, deprecated)
    func testPDFEncapsulationForwardsToTheEngine() {
        XCTAssertTrue(PDFEncapsulation.self == EncapsulatedDocumentBuilder.OptionRules.self)
    }

    /// Table C.24-2: the length "shall be equal to the Value Length if even, or one less than
    /// the Value Length if odd"; the engine cuts only the one padding byte.
    func testDocumentBytesFollowTheEngineParser() {
        var dataSet = DataSet()
        let value = Data([1, 2, 3, 4, 5, 6])
        dataSet[EncapsulatedDocumentBuilder.OptionRules.encapsulatedDocumentLength] = .uint32(
            tag: EncapsulatedDocumentBuilder.OptionRules.encapsulatedDocumentLength, value: 5)
        XCTAssertEqual(EncapsulatedDocumentBuilder.OptionRules.documentBytes(value, in: dataSet), value.prefix(5))
        XCTAssertEqual(EncapsulatedDocumentBuilder.OptionRules.documentBytes(value, in: dataSet),
                       EncapsulatedDocumentParser.documentStream(value, in: dataSet))
    }
}
