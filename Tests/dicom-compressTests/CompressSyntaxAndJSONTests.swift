//
// CompressSyntaxAndJSONTests.swift
// dicom-compress
//
// P-COMPRESS-SYNTAX: decompress / batch --syntax accept only the native Transfer Syntaxes
// (PS3.5 2026a A.1 Implicit VR Little Endian, A.2 Explicit VR Little Endian, A.5 Deflated
// Explicit VR Little Endian; UIDs per PS3.6 2026a Table A-1) and the retired A.3 Explicit VR
// Big Endian (accepted again once the engine byte-swapped values, D206); every encapsulated
// codec name is refused with exit 1.
// P-COMPRESS-JSON: info --json carries the PS3.6 2026a Table 6-1 keyword keys next to the
// deprecated camelCase keys.
//

import XCTest
import DICOMCore
import DICOMKit
@testable import dicom_compress

final class CompressSyntaxAndJSONTests: XCTestCase {

    /// PS3.6 2026a Table A-1 UIDs of the native targets (dumped from part06_2026a.xml).
    private static let native: [String: String] = [
        "explicit-le": "1.2.840.10008.1.2.1",
        "implicit-le": "1.2.840.10008.1.2",
        "deflate": "1.2.840.10008.1.2.1.99",
        "explicit-be": "1.2.840.10008.1.2.2",
    ]

    func test_nativeTargets_resolveToTheirTableA1UIDs() throws {
        XCTAssertEqual(NativeTargetSyntax.accepted.map(\.name), ["explicit-le", "implicit-le", "deflate", "explicit-be"])
        for (name, uid) in Self.native {
            XCTAssertEqual(try NativeTargetSyntax.resolve(name).uid, uid, name)
            XCTAssertEqual(try NativeTargetSyntax.resolve(name.uppercased()).uid, uid, name)
            XCTAssertFalse(try NativeTargetSyntax.resolve(name).isEncapsulated, name)
        }
    }

    func test_everyCompressedCodecName_isRefused() {
        let encapsulated = CompressionManager.supportedCodecs()
            .filter { $0.syntax.isEncapsulated }
            .flatMap { [$0.name] + $0.aliases }
        XCTAssertGreaterThan(encapsulated.count, 20)
        for name in encapsulated {
            XCTAssertThrowsError(try NativeTargetSyntax.resolve(name), name) { error in
                XCTAssertTrue(error is NativeTargetSyntax.Refused, name)
                XCTAssertTrue("\(error)".contains("Table A-1"), name)
            }
        }
    }

    func test_unknown_isRefused() {
        for name in ["big-endian", "bogus"] {
            XCTAssertThrowsError(try NativeTargetSyntax.resolve(name), name) { error in
                XCTAssertTrue(error is NativeTargetSyntax.Refused, name)
            }
        }
    }

    /// D206: `--syntax explicit-be` writes Explicit VR Big Endian with byte-swapped values
    /// (PS3.5 2026a 7.3) that read back to the source values.
    func test_explicitBE_decompressRoundTrips() throws {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4.5.6.7.8", for: .sopInstanceUID, vr: .UI)
        ds.setUInt16(2, for: .rows)
        ds.setUInt16(3, for: .columns)
        ds.setUInt16(16, for: .bitsAllocated)
        ds.setUInt16(16, for: .bitsStored)
        ds.setUInt16(15, for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        let pixels = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C])
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: pixels)
        let input = try DICOMFile.create(dataSet: ds, transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid).write()

        let syntax = try NativeTargetSyntax.resolve("explicit-be")
        let be = try CompressionManager().decompressData(input, syntax: syntax)
        let file = try DICOMFile.read(from: be)
        XCTAssertEqual(file.dataSet.uint16(for: .columns), 3)
        XCTAssertEqual(file.dataSet[.pixelData]?.valueData,
                       Data([0x02, 0x01, 0x04, 0x03, 0x06, 0x05, 0x08, 0x07, 0x0A, 0x09, 0x0C, 0x0B]))
        let le = try DICOMFile.read(from: try CompressionManager().decompressData(be, syntax: .explicitVRLittleEndian))
        XCTAssertEqual(le.dataSet[.pixelData]?.valueData, pixels)
    }

    /// The refusal is not a ValidationError, so ArgumentParser exits 1 (not 64).
    func test_refusal_exits1() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("syntax-\(UUID().uuidString).dcm")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertThrowsError(try DICOMCompress.Decompress.parse([file.path, "-o", "o.dcm", "--syntax", "jpeg2000"])) { error in
            XCTAssertEqual(DICOMCompress.Decompress.exitCode(for: error), .failure)
        }
        XCTAssertNoThrow(try DICOMCompress.Decompress.parse([file.path, "-o", "o.dcm", "--syntax", "deflate"]))
        let dir = FileManager.default.temporaryDirectory.path
        XCTAssertThrowsError(try DICOMCompress.Batch.parse([dir, "-o", "out", "--decompress", "--syntax", "htj2k"])) { error in
            XCTAssertEqual(DICOMCompress.Batch.exitCode(for: error), .failure)
        }
    }

    // MARK: - info --json keys (PS3.6 2026a Table 6-1)

    func test_infoJSON_hasKeywordKeys_andKeepsOldKeys() throws {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4.5.6.7.8", for: .sopInstanceUID, vr: .UI)
        ds.setUInt16(4, for: .rows)
        ds.setUInt16(6, for: .columns)
        ds.setUInt16(16, for: .bitsAllocated)
        ds.setUInt16(12, for: .bitsStored)
        ds.setUInt16(11, for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        ds.setString("2", for: .numberOfFrames, vr: .IS)
        ds.setString("00", for: .lossyImageCompression, vr: .CS)
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: Data(count: 4 * 6 * 2 * 2))
        let data = try DICOMFile.create(dataSet: ds, transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid).write()
        let info = try CompressionManager().getCompressionInfo(data: data)
        let text = try CompressionConsole.infoJSON(info, filePath: "f.dcm")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])

        // Table 6-1 keywords (dumped from part06_2026a.xml): (0002,0010) TransferSyntaxUID,
        // (0028,0010) Rows, (0028,0011) Columns, (0028,0100) BitsAllocated, (0028,0101)
        // BitsStored, (0028,0002) SamplesPerPixel, (0028,0004) PhotometricInterpretation,
        // (0028,0008) NumberOfFrames, (0028,2110) LossyImageCompression.
        XCTAssertEqual(json["TransferSyntaxUID"] as? String, "1.2.840.10008.1.2.1")
        XCTAssertEqual(json["Rows"] as? Int, 4)
        XCTAssertEqual(json["Columns"] as? Int, 6)
        XCTAssertEqual(json["BitsAllocated"] as? Int, 16)
        XCTAssertEqual(json["BitsStored"] as? Int, 12)
        XCTAssertEqual(json["SamplesPerPixel"] as? Int, 1)
        XCTAssertEqual(json["PhotometricInterpretation"] as? String, "MONOCHROME2")
        XCTAssertEqual(json["NumberOfFrames"] as? Int, 2)
        XCTAssertEqual(json["LossyImageCompression"] as? String, "00")

        // Deprecated keys keep their old values.
        XCTAssertEqual(json["transferSyntaxUID"] as? String, "1.2.840.10008.1.2.1")
        XCTAssertEqual(json["rows"] as? Int, 4)
        XCTAssertEqual(json["numberOfFrames"] as? String, "2")
        XCTAssertEqual(json["samplesPerPixel"] as? Int, 1)
    }

    func test_infoHelp_namesKeywordKeys_andDeprecatedKeys() {
        let help = DICOMCompress.Info.configuration.discussion
        for key in ["TransferSyntaxUID", "Rows", "Columns", "BitsAllocated", "BitsStored", "SamplesPerPixel",
                    "PhotometricInterpretation", "NumberOfFrames", "LossyImageCompression"] {
            XCTAssertTrue(help.contains(key), key)
        }
        XCTAssertTrue(help.contains("deprecated"))
    }
}
