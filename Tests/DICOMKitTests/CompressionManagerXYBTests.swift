import XCTest
import Foundation
@testable import DICOMKit
import DICOMCore

/// PS3.3 2026a C.7.6.3.1.2: "Images in XYB transcoded to other Transfer Syntaxes will use RGB".
/// The JPEG XL decoder returns RGB samples, so a decompressed object that declared XYB must be
/// relabelled RGB, as `TransferSyntaxConverter` does (D12).
final class CompressionManagerXYBTests: XCTestCase {

    private func makeRGBFile() throws -> Data {
        var els: [DataElement] = []
        els.append(.uint16(tag: .rows, value: 16))
        els.append(.uint16(tag: .columns, value: 16))
        els.append(.uint16(tag: .bitsAllocated, value: 8))
        els.append(.uint16(tag: .bitsStored, value: 8))
        els.append(.uint16(tag: .highBit, value: 7))
        els.append(.uint16(tag: .pixelRepresentation, value: 0))
        els.append(.uint16(tag: .samplesPerPixel, value: 3))
        els.append(.uint16(tag: .planarConfiguration, value: 0))
        els.append(.string(tag: .photometricInterpretation, vr: .CS, value: "RGB"))
        els.append(.string(tag: .sopClassUID, vr: .UI, value: "1.2.840.10008.5.1.4.1.1.7"))
        els.append(.string(tag: .sopInstanceUID, vr: .UI, value: "1.2.3.4.5.6.7.8.9"))
        var pixels = Data()
        for y in 0..<16 {
            for x in 0..<16 {
                pixels.append(UInt8((x * 16) % 256))
                pixels.append(UInt8((y * 16) % 256))
                pixels.append(UInt8(((x + y) * 8) % 256))
            }
        }
        els.append(DataElement(tag: .pixelData, vr: .OB, length: UInt32(pixels.count), valueData: pixels))
        return try DICOMFile.create(dataSet: DataSet(elements: els),
                                    transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid).write()
    }

    func testDecompressingJPEGXLRewritesXYBTagToRGB() throws {
        let mgr = CompressionManager()
        let compressed: Data
        do {
            compressed = try mgr.compressData(try makeRGBFile(), codec: "jpeg-xl", quality: .high)
        } catch {
            throw XCTSkip("JPEG XL encoder not available: \(error)")
        }

        // Declare the codestream's colour model as XYB, as a JPEG XL encoder that uses the
        // XYB transform would (PS3.5 Table 8.2.15-1).
        let file = try DICOMFile.read(from: compressed)
        var dataSet = file.dataSet
        dataSet.setString("XYB", for: .photometricInterpretation, vr: .CS)
        let xyb = try DICOMFile.create(dataSet: dataSet, transferSyntaxUID: TransferSyntax.jpegXL.uid).write()

        let decompressed = try mgr.decompressData(xyb, syntax: .explicitVRLittleEndian)
        let pi = try DICOMFile.read(from: decompressed).dataSet
            .string(for: .photometricInterpretation)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
        XCTAssertEqual(pi, "RGB", "decoded JPEG XL samples are RGB; the XYB label must not survive transcoding")
    }
}
