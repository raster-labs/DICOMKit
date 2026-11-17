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

    func testC2_LossyJPEGXLAutomaticallyLabelsXYBAndResetsPlanarConfiguration() throws {
        var els: [DataElement] = []
        els.append(.uint16(tag: .rows, value: 16))
        els.append(.uint16(tag: .columns, value: 16))
        els.append(.uint16(tag: .bitsAllocated, value: 8))
        els.append(.uint16(tag: .bitsStored, value: 8))
        els.append(.uint16(tag: .highBit, value: 7))
        els.append(.uint16(tag: .pixelRepresentation, value: 0))
        els.append(.uint16(tag: .samplesPerPixel, value: 3))
        els.append(.uint16(tag: .planarConfiguration, value: 1)) // planar source!
        els.append(.string(tag: .photometricInterpretation, vr: .CS, value: "RGB"))
        els.append(.string(tag: .sopClassUID, vr: .UI, value: "1.2.840.10008.5.1.4.1.1.7"))
        els.append(.string(tag: .sopInstanceUID, vr: .UI, value: "1.2.3.4.5.6.7.8.10"))
        let pixels = Data((0..<(16 * 16 * 3)).map { UInt8(($0 * 17) & 0xFF) })
        els.append(DataElement(tag: .pixelData, vr: .OB, length: UInt32(pixels.count), valueData: pixels))
        let planarRGB = try DICOMFile.create(
            dataSet: DataSet(elements: els),
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid
        ).write()

        let mgr = CompressionManager()
        // 1. Lossy JPEG XL (.112) sets Photometric Interpretation = XYB and Planar Configuration = 0
        let jxlLossy = try mgr.compressData(planarRGB, codec: "jpeg-xl", quality: .high)
        let jxlLossyDS = try DICOMFile.read(from: jxlLossy).dataSet
        XCTAssertEqual(jxlLossyDS.string(for: .photometricInterpretation)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")), "XYB")
        XCTAssertEqual(jxlLossyDS.uint16(for: .planarConfiguration), 0)
        XCTAssertEqual(jxlLossyDS.string(for: .lossyImageCompression)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")), "01")

        // 2. Planar Configuration = 1 -> 0 across JPEG Lossless (.57/.70), JPEG-LS (.80/.81), and JPEG XL Lossless (.110)
        for codec in ["jpeg-lossless", "jpeg-lossless-sv1", "jpeg-ls-lossless", "jpeg-ls", "jpeg-xl-lossless-only"] {
            let out = try mgr.compressData(planarRGB, codec: codec, quality: .high)
            let ds = try DICOMFile.read(from: out).dataSet
            XCTAssertEqual(ds.uint16(for: .planarConfiguration), 0, "Expected PlanarConfiguration=0 for \(codec)")
        }

        // 3. DICOMConverter path (.112 lossy RGB -> XYB + PlanarConfiguration=0; >4096 Modular fallback -> RGB + lossless)
        let sourceFile = try DICOMFile.read(from: planarRGB)
        let lossyJXLTarget = SelectableEncoding(transferSyntax: .jpegXL, intent: .lossy)
        let outcome = try DICOMConverter.convertToDICOM(dicomFile: sourceFile, to: lossyJXLTarget, stripPrivate: false)
        XCTAssertFalse(outcome.isLossless)
        let convDS = try DICOMFile.read(from: outcome.data).dataSet
        XCTAssertEqual(convDS.string(for: .photometricInterpretation)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")), "XYB")
        XCTAssertEqual(convDS.uint16(for: .planarConfiguration), 0)

        var wideEls: [DataElement] = []
        wideEls.append(.uint16(tag: .rows, value: 8))
        wideEls.append(.uint16(tag: .columns, value: 4104))
        wideEls.append(.uint16(tag: .bitsAllocated, value: 8))
        wideEls.append(.uint16(tag: .bitsStored, value: 8))
        wideEls.append(.uint16(tag: .highBit, value: 7))
        wideEls.append(.uint16(tag: .pixelRepresentation, value: 0))
        wideEls.append(.uint16(tag: .samplesPerPixel, value: 3))
        wideEls.append(.uint16(tag: .planarConfiguration, value: 1))
        wideEls.append(.string(tag: .photometricInterpretation, vr: .CS, value: "RGB"))
        wideEls.append(.string(tag: .sopClassUID, vr: .UI, value: "1.2.840.10008.5.1.4.1.1.7"))
        wideEls.append(.string(tag: .sopInstanceUID, vr: .UI, value: "1.2.3.4.5.6.7.8.11"))
        let widePixels = Data((0..<(8 * 4104 * 3)).map { UInt8(($0 * 11) & 0xFF) })
        wideEls.append(DataElement(tag: .pixelData, vr: .OB, length: UInt32(widePixels.count), valueData: widePixels))
        let wideFile = DICOMFile.create(dataSet: DataSet(elements: wideEls), transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid)
        let wideOutcome = try DICOMConverter.convertToDICOM(dicomFile: wideFile, to: lossyJXLTarget, stripPrivate: false)
        XCTAssertTrue(wideOutcome.isLossless, ">4096 Modular fallback must report lossless")
        let wideDS = try DICOMFile.read(from: wideOutcome.data).dataSet
        XCTAssertEqual(wideDS.string(for: .photometricInterpretation)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")), "RGB")
        XCTAssertNil(wideDS[.lossyImageCompression], ">4096 Modular fallback must not stamp (0028,2110)")
        XCTAssertEqual(wideDS.uint16(for: .planarConfiguration), 0)
    }
}
