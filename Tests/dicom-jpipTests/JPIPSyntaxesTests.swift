import XCTest
import DICOMCore
import DICOMKit
import SwiftJ2KJPIP
@testable import dicom_jpip

/// Pins dicom-jpip to the JPIP Referenced Transfer Syntaxes of PS3.6 2026a Table A-1 and the
/// Pixel Data Provider URL (0028,7FE0) of PS3.5 2026a 8.4.1 / A.6 / A.7 / A.11 / A.12.
final class JPIPSyntaxesTests: XCTestCase {

    private let tableA1: [(String, String)] = [
        ("1.2.840.10008.1.2.4.94", "JPIP Referenced"),
        ("1.2.840.10008.1.2.4.95", "JPIP Referenced Deflate"),
        ("1.2.840.10008.1.2.4.204", "JPIP HTJ2K Referenced"),
        ("1.2.840.10008.1.2.4.205", "JPIP HTJ2K Referenced Deflate"),
    ]

    func testAllFourTableA1SyntaxesWithTheirNames() {
        XCTAssertEqual(JPIPSyntaxes.all.map(\.uid), tableA1.map(\.0))
        XCTAssertEqual(JPIPSyntaxes.all.map(\.name), tableA1.map(\.1))
        XCTAssertEqual(JPIPSyntaxes.all.map(\.annex), ["A.6", "A.7", "A.11", "A.12"])
        XCTAssertEqual(JPIPSyntaxes.all.filter(\.deflated).map(\.uid),
                       ["1.2.840.10008.1.2.4.95", "1.2.840.10008.1.2.4.205"])
    }

    func testListSyntaxesPrintsTheSameRows() {
        let rows = DICOMJpip.InfoCommand.listedSyntaxes
        XCTAssertEqual(rows.compactMap { $0["uid"] }, tableA1.map(\.0))
        XCTAssertEqual(rows.compactMap { $0["name"] }, tableA1.map(\.1))
    }

    func testHelpListsTheFourSyntaxes() {
        let help = DICOMJpip.helpMessage()
        for (uid, name) in tableA1 {
            XCTAssertTrue(help.contains(uid), uid)
            XCTAssertTrue(help.contains(name), name)
        }
        XCTAssertFalse(help.contains("Annex A.8"))  // A.8 is SMPTE ST 2110-20
    }

    func testRecognitionCoversTheHTJ2KPair() {
        for (uid, _) in tableA1 { XCTAssertTrue(JPIPSyntaxes.isJPIP(uid), uid) }
        XCTAssertFalse(JPIPSyntaxes.isJPIP("1.2.840.10008.1.2.4.90"))  // JPEG 2000 (Lossless Only)
        XCTAssertFalse(JPIPSyntaxes.isJPIP("1.2.840.10008.1.2.4.201"))  // HTJ2K (Lossless Only)
    }

    private func dataSet(url: String) -> DataSet {
        let data = Data(url.utf8)
        var ds = DataSet()
        ds[.pixelDataProviderURL] = DataElement(tag: .pixelDataProviderURL, vr: .UR,
                                                length: UInt32(data.count), valueData: data)
        return ds
    }

    func testPixelDataProviderURLIsReadForEveryJPIPSyntax() throws {
        let expected = "http://server.xxx/jpipserver.cgi?target=imgxyz.jp2"  // PS3.5 8.4.1 example
        for (uid, _) in tableA1 {
            let url = try JPIPSyntaxes.pixelDataProviderURL(from: dataSet(url: expected + " "), transferSyntaxUID: uid)
            XCTAssertEqual(url.absoluteString, expected, uid)
        }
    }

    func testMissingProviderURLAndNonJPIPSyntaxThrow() {
        XCTAssertThrowsError(try JPIPSyntaxes.pixelDataProviderURL(from: DataSet(), transferSyntaxUID: "1.2.840.10008.1.2.4.204"))
        XCTAssertThrowsError(try JPIPSyntaxes.pixelDataProviderURL(from: dataSet(url: "http://x/y"),
                                                                   transferSyntaxUID: "1.2.840.10008.1.2.1"))
    }

    func testServeAndFetchCLIRoundTripOverLoopback() async throws {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        ds.setString(UIDGenerator.generateUID().value, for: .sopInstanceUID, vr: .UI)
        ds.setUInt16(8, for: .rows)
        ds.setUInt16(8, for: .columns)
        ds.setUInt16(8, for: .bitsAllocated)
        ds.setUInt16(8, for: .bitsStored)
        ds.setUInt16(7, for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        let expected = Data((0..<64).map { UInt8($0 * 3) })
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB, data: expected)
        let dcmFile = DICOMFile.create(dataSet: ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.2")

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("dicom-jpip-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dcmURL = tempDir.appendingPathComponent("sample.dcm")
        try dcmFile.write().write(to: dcmURL)

        let server = JPIPServer(port: 0, host: "127.0.0.1")
        let count = await registerDirectoryTargets(at: tempDir, into: server, verbose: false)
        XCTAssertEqual(count, 1)
        try await server.start()
        let port = await server.listeningPort

        let rawOut = tempDir.appendingPathComponent("out.raw")
        var fetchCmd = try DICOMJpip.FetchCommand.parse([
            "http://127.0.0.1:\(port)",
            "--image", "sample",
            "--output", rawOut.path
        ])
        try fetchCmd.run()

        let fetchedBytes = try Data(contentsOf: rawOut)
        XCTAssertEqual(fetchedBytes, expected)
        try await server.stop()
    }
}
