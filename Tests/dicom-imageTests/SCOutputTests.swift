import XCTest
import ArgumentParser
import DICOMCore
import DICOMKit
@testable import dicom_image

#if canImport(CoreGraphics)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#endif

/// dicom-image against DICOM 2026a: PS3.3 Table A.8-1 (Secondary Capture Image IOD),
/// Table C.8-24 (Conversion Type), Table C.12-1/C.12-5 (Specific Character Set),
/// PS3.10 Table 7.1-1 (File Meta Information), PS3.5 Table 6.2-1 (VR limits).
final class SCOutputTests: XCTestCase {

    // PS3.3 2026a Table C.8-24, Conversion Type (0008,0064) Defined Terms, dumped by script.
    private let tableC824 = ["DV", "DI", "DF", "WSD", "SD", "SI", "DRW", "SYN"]

    func testConversionTypeAcceptsTheEightDefinedTerms() {
        for term in tableC824 {
            XCTAssertEqual(ImageConverter.OutputRules.conversionType(term)?.rawValue, term)
            XCTAssertEqual(ImageConverter.OutputRules.conversionType(term.lowercased())?.rawValue, term)
        }
        XCTAssertEqual(ImageConverter.OutputRules.conversionType(nil), .workstation, "default WSD")
        XCTAssertNil(ImageConverter.OutputRules.conversionType("XYZ"))
        XCTAssertNil(ImageConverter.OutputRules.conversionType(""))
    }

    func testValueViolationsFollowPS35Table621() {
        XCTAssertTrue(ImageConverter.OutputRules.valueViolations(
            patientName: "DOE^JOHN", patientID: "P1", studyDescription: "d", seriesDescription: nil,
            studyUID: "1.2.840.10008.1", seriesUID: "1.2.3", seriesNumber: 1, instanceNumber: 1).isEmpty)
        let w = ImageConverter.OutputRules.valueViolations(
            patientName: String(repeating: "A", count: 65), patientID: String(repeating: "9", count: 65),
            studyDescription: "a\\b", seriesDescription: nil,
            studyUID: "1.02.3", seriesUID: "1..2", seriesNumber: Int(Int32.max) + 1, instanceNumber: Int(Int32.min))
        XCTAssertEqual(w.filter { $0.contains("not a valid UID") }.count, 2)          // UI, PS3.5 9.1
        XCTAssertEqual(w.filter { $0.contains("LO allows at most 64") }.count, 1)
        XCTAssertEqual(w.filter { $0.contains("PN allows at most 64") }.count, 1)
        XCTAssertEqual(w.filter { $0.contains("backslash") }.count, 1)
        XCTAssertEqual(w.filter { $0.contains("IS range") }.count, 1, "Int32.min is inside the IS range")
    }

    func testFinalizeAlignsMediaStorageSOPInstanceUIDAndSetsCharacterSet() throws {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4.5", for: .sopInstanceUID, vr: .UI)
        ds.setString("Müller^Jörg", for: .patientName, vr: .PN)
        // Since D175 (2026-10-01) DICOMFile.create takes (0002,0003) from (0008,0018) when none is
        // passed — as ImageConverter does — so the engine output already agrees.
        let created = DICOMFile.create(dataSet: ds, transferSyntaxUID: "1.2.840.10008.1.2.1")
        XCTAssertEqual(created.fileMetaInformation.string(for: .mediaStorageSOPInstanceUID), "1.2.3.4.5")
        // finalize still re-aligns a File Meta carried over with a different UID.
        var staleMeta = created.fileMetaInformation
        staleMeta.setString("1.2.3.4.999", for: .mediaStorageSOPInstanceUID, vr: .UI)
        staleMeta.remove(tag: .fileMetaInformationGroupLength)
        let data = try DICOMFile(fileMetaInformation: staleMeta, dataSet: ds).write()
        let before = try DICOMFile.read(from: data)
        XCTAssertNotEqual(before.fileMetaInformation.string(for: .mediaStorageSOPInstanceUID), "1.2.3.4.5")

        let after = try DICOMFile.read(from: ImageConverter.OutputRules.finalize(data))
        XCTAssertEqual(after.fileMetaInformation.string(for: .mediaStorageSOPInstanceUID), "1.2.3.4.5")
        // PS3.3 2026a Table C.12-5: "Unicode in UTF-8" = ISO_IR 192.
        XCTAssertEqual(after.dataSet.string(for: .specificCharacterSet), "ISO_IR 192")
        XCTAssertEqual(after.dataSet.string(for: .patientName), "Müller^Jörg")
    }

    func testFinalizeLeavesASCIIDataSetWithoutCharacterSet() throws {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4.6", for: .sopInstanceUID, vr: .UI)
        ds.setString("DOE^JOHN", for: .patientName, vr: .PN)
        let data = try DICOMFile.create(dataSet: ds, sopInstanceUID: "1.2.3.4.6",
                                        transferSyntaxUID: "1.2.840.10008.1.2.1").write()
        let after = try DICOMFile.read(from: ImageConverter.OutputRules.finalize(data))
        XCTAssertNil(after.dataSet[.specificCharacterSet])
        XCTAssertEqual(after.fileMetaInformation.string(for: .mediaStorageSOPInstanceUID), "1.2.3.4.6")
    }

    #if canImport(CoreGraphics)
    /// Every Type 1 and Type 2 attribute of the M modules of PS3.3 2026a Table A.8-1
    /// (dumped by script: Tables C.7-1, C.7-3, C.7-5a, C.8-24, C.7.10.1-1, C.7-9,
    /// C.7-11a/C.7-11c, C.8-25, C.12-1), plus the applicable 1C/2C rows.
    func testConvertedPNGCarriesEveryType1And2AttributeOfTheSCImageIOD() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sc-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeRGBPNG(to: url, width: 6, height: 4)

        let meta = ImageConverter.Metadata(
            patientName: "Ünïcode^Name", patientID: "P1", studyUID: "1.2.3", seriesUID: "1.2.3.4",
            instanceNumber: 1, conversionType: ImageConverter.OutputRules.conversionType("drw")!)
        let data = try ImageConverter.OutputRules.finalize(
            ImageConverter.secondaryCaptureData(imageURL: url, metadata: meta, useExif: false))
        let file = try DICOMFile.read(from: data)
        let ds = file.dataSet

        let type1: [Tag] = [.studyInstanceUID, .modality, .seriesInstanceUID, .conversionType,
                            .samplesPerPixel, .photometricInterpretation, .rows, .columns,
                            .bitsAllocated, .bitsStored, .highBit, .pixelRepresentation,
                            .sopClassUID, .sopInstanceUID,
                            .planarConfiguration, .pixelData, .specificCharacterSet]   // 1C that apply
        let type2: [Tag] = [.patientName, .patientID, .patientBirthDate, .patientSex,
                            .studyDate, .studyTime, .referringPhysicianName, .studyID, .accessionNumber,
                            .seriesNumber, .instanceNumber, .patientOrientation]        // 2C that applies
        for tag in type1 { XCTAssertNotNil(ds[tag], "Type 1 \(tag) missing"); XCTAssertFalse(ds[tag]?.valueData.isEmpty ?? true, "Type 1 \(tag) empty") }
        for tag in type2 { XCTAssertNotNil(ds[tag], "Type 2 \(tag) missing") }

        XCTAssertEqual(ds.string(for: .sopClassUID), "1.2.840.10008.5.1.4.1.1.7") // PS3.6 Table A-1
        XCTAssertEqual(ds.string(for: .conversionType), "DRW")
        XCTAssertEqual(ds.string(for: .photometricInterpretation), "RGB")
        XCTAssertEqual(ds.uint16(for: .planarConfiguration), 0)
        XCTAssertEqual(file.fileMetaInformation.string(for: .mediaStorageSOPInstanceUID),
                       ds.string(for: .sopInstanceUID), "PS3.10 Table 7.1-1")
        XCTAssertEqual(ds.string(for: .specificCharacterSet), "ISO_IR 192")
    }

    /// P-IMAGE-VR: a value the VR cannot hold is refused with exit 1 and nothing is written.
    func testInvalidValuesAreRefusedWithExitOneAndNoOutput() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = dir.appendingPathComponent("in.png")
        try writeRGBPNG(to: png, width: 4, height: 4)
        for bad in [["--study-uid", "1.02.3"], ["--series-uid", "1..2"],
                    ["--patient-id", String(repeating: "9", count: 65)], ["--study-description", "a\\b"],
                    ["--patient-name", String(repeating: "A", count: 65)],
                    ["--series-number", "2147483648"], ["--instance-number=-2147483649"]] {
            let out = dir.appendingPathComponent("out-\(bad[0].prefix(18)).dcm")
            var command = try XCTUnwrap(DICOMImage.parseAsRoot([png.path, "--output", out.path] + bad) as? DICOMImage)
            XCTAssertThrowsError(try command.run(), "\(bad)") { error in
                XCTAssertEqual((error as? ExitCode)?.rawValue, 1, "\(bad)")
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: out.path), "\(bad) wrote output")
        }
        let good = dir.appendingPathComponent("good.dcm")
        var command = try XCTUnwrap(DICOMImage.parseAsRoot(
            [png.path, "--output", good.path, "--study-uid", "1.2.3", "--patient-name", "DOE^JOHN", "--patient-id", "P1"]) as? DICOMImage)
        try command.run()
        XCTAssertTrue(FileManager.default.fileExists(atPath: good.path))
    }

    private func writeRGBPNG(to url: URL, width: Int, height: Int) throws {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) { bytes[i * 4] = UInt8(i * 10 % 256); bytes[i * 4 + 1] = 200; bytes[i * 4 + 3] = 255 }
        let ctx = try XCTUnwrap(CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(ctx.makeImage())
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }
    #endif
}
