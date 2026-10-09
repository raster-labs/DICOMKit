// DeferredRowsB6aCodecTests.swift
// DICOMKitTests
//
// Deferred-row closure, batch b6a-codec (2026-10-01). Each test pins a value of the 2026a text:
// - D184 / D192: PS3.3 C.7.6.1.1.5 — a lossy compressed version of a DICOM image gets Lossy Image
//   Compression "01", Image Type Value 1 DERIVED and "a new SOP Instance UID"; C.7.6.1.1.5.2 —
//   the ratio "should also be described in Derivation Description (0008,2111)".
// - D185 / D186 / D-KIT-1: PS3.5 8.2.4, 8.2.14 — SGcod MCT = 1 → YBR_RCT / YBR_ICT; after
//   decompression to native the Photometric Interpretation "will be changed to RGB".
// - D-CORE-3: YBR_FULL needs MCT 0, which J2KSwift cannot write → converted to RGB (lossy only).
// - D190 / D-CORE-2: PS3.5 Table 8.2.1-1 — 3-sample JPEG Baseline only as YBR_FULL_422 | RGB.
// - D188: PS3.5 6.2 / 7.1 — UI values even length, NULL padded.
// - D206: PS3.5 7.3 — Explicit VR Big Endian values byte-swapped.
// - D191: PS3.5 7.8.1 — Private Data Elements inside Sequence Items.
// - D197: PS3.3 C.7.6.16.2.9 — per-frame Pixel Value Transformation.
// - D183: PS3.3 C.7.6.1.1.5.2 ratio notation; PS3.6 (0028,0002) "Samples per Pixel".

import XCTest
import Foundation
@testable import DICOMKit
import DICOMCore

final class DeferredRowsB6aCodecTests: XCTestCase {

    private static let sourceUID = "1.2.3.4.5.6.7.8.9"   // odd length (17)

    private func trimmed(_ s: String?) -> String? {
        s?.trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
    }

    /// 16x16 8-bit colour (or 16-bit monochrome) Explicit VR LE file.
    private func makeFile(photometric: String = "RGB", samples: Int = 3, bits: Int = 8,
                          frames: Int = 1, extra: [DataElement] = []) throws -> Data {
        var els: [DataElement] = [
            .uint16(tag: .rows, value: 16), .uint16(tag: .columns, value: 16),
            .uint16(tag: .bitsAllocated, value: UInt16(bits)), .uint16(tag: .bitsStored, value: UInt16(bits)),
            .uint16(tag: .highBit, value: UInt16(bits - 1)), .uint16(tag: .pixelRepresentation, value: 0),
            .uint16(tag: .samplesPerPixel, value: UInt16(samples)),
            .string(tag: .photometricInterpretation, vr: .CS, value: photometric),
            .string(tag: .sopClassUID, vr: .UI, value: "1.2.840.10008.5.1.4.1.1.7"),
            .string(tag: .sopInstanceUID, vr: .UI, value: Self.sourceUID),
            .strings(tag: .imageType, vr: .CS, values: ["ORIGINAL", "PRIMARY"]),
        ]
        if samples == 3 { els.append(.uint16(tag: .planarConfiguration, value: 0)) }
        if frames > 1 { els.append(.string(tag: .numberOfFrames, vr: .IS, value: "\(frames)")) }
        els.append(contentsOf: extra)
        var pixels = Data()
        for f in 0..<frames {
            for y in 0..<16 {
                for x in 0..<16 {
                    if samples == 3 {
                        pixels.append(UInt8((x * 16) % 256))
                        pixels.append(UInt8((y * 16) % 256))
                        pixels.append(UInt8(((x + y) * 8 + f) % 256))
                    } else if bits == 16 {
                        let v = UInt16(x * 300 + y * 7 + f)
                        pixels.append(UInt8(v & 0xFF)); pixels.append(UInt8(v >> 8))
                    } else {
                        pixels.append(UInt8((x * 16 + y) % 256))
                    }
                }
            }
        }
        els.append(DataElement(tag: .pixelData, vr: bits == 16 ? .OW : .OB,
                               length: UInt32(pixels.count), valueData: pixels))
        return try DICOMFile.create(dataSet: DataSet(elements: els),
                                    transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid).write()
    }

    // MARK: - D184 (dicom-compress) / D192 (dicom-convert): new SOP Instance UID

    func test_D184_lossyCompress_getsNewSOPInstanceUID_DERIVED_andDerivationDescription() throws {
        let input = try makeFile()
        for codec in ["jpeg", "jpeg2000", "htj2k", "jpeg-ls", "jpeg-xl"] {
            let out = try CompressionManager().compressData(input, codec: codec, quality: .medium)
            let file = try DICOMFile.read(from: out)
            let ds = file.dataSet
            let uid = try XCTUnwrap(trimmed(ds.string(for: .sopInstanceUID)), codec)
            XCTAssertNotEqual(uid, Self.sourceUID, "\(codec): PS3.3 C.7.6.1.1.5 requires a new SOP Instance UID")
            XCTAssertEqual(trimmed(file.fileMetaInformation.string(for: .mediaStorageSOPInstanceUID)), uid, codec)
            XCTAssertEqual(trimmed(ds.string(for: .lossyImageCompression)), "01", codec)
            XCTAssertEqual(ds.strings(for: .imageType)?.first, "DERIVED", codec)
            let derivation = try XCTUnwrap(ds.string(for: .derivationDescription), codec)
            XCTAssertTrue(derivation.contains("Lossy compression"), codec)
            XCTAssertTrue(derivation.contains(":1"), codec)
        }
    }

    func test_D184_losslessCompress_keepsSOPInstanceUID() throws {
        let input = try makeFile()
        for codec in ["jpeg-lossless", "jpeg2000-lossless", "rle"] {
            let out = try CompressionManager().compressData(input, codec: codec, quality: nil)
            let ds = try DICOMFile.read(from: out).dataSet
            XCTAssertEqual(trimmed(ds.string(for: .sopInstanceUID)), Self.sourceUID, codec)
            XCTAssertNil(ds.string(for: .derivationDescription), codec)
        }
    }

    func test_D192_lossyConvert_getsNewSOPInstanceUID() throws {
        let source = try DICOMFile.read(from: try makeFile())
        let encoding = try XCTUnwrap(DICOMConverter.resolveTargetEncoding("1.2.840.10008.1.2.4.50"))
        let outcome = try DICOMConverter.convertToDICOM(dicomFile: source, to: encoding, stripPrivate: false)
        let file = try DICOMFile.read(from: outcome.data)
        let uid = try XCTUnwrap(trimmed(file.dataSet.string(for: .sopInstanceUID)))
        XCTAssertNotEqual(uid, Self.sourceUID)
        XCTAssertEqual(trimmed(file.fileMetaInformation.string(for: .mediaStorageSOPInstanceUID)), uid)
        XCTAssertEqual(trimmed(file.dataSet.string(for: .lossyImageCompression)), "01")
    }

    // MARK: - D185 / D186 / D-KIT-1: J2K colour labels

    func test_D185_D186_j2kColour_labelledFromMCT_andRGBAfterDecode() throws {
        let input = try makeFile()
        let cases: [(codec: String, pi: String)] = [
            ("jpeg2000", "YBR_ICT"), ("jpeg2000-lossless", "YBR_RCT"), ("jpeg2000-lossless-only", "YBR_RCT"),
            ("htj2k", "YBR_ICT"), ("htj2k-lossless-only", "YBR_RCT"), ("htj2k-rpcl", "YBR_RCT"),
        ]
        for (codec, pi) in cases {
            let mgr = CompressionManager()
            let out = try mgr.compressData(input, codec: codec, quality: nil)
            let ds = try DICOMFile.read(from: out).dataSet
            let frame = try XCTUnwrap(ds[.pixelData]?.encapsulatedFragments?.first, codec)
            let style = try XCTUnwrap(J2KCodestreamInspector.codingStyle(in: frame), codec)
            XCTAssertEqual(style.multipleComponentTransform, 1, codec)
            XCTAssertEqual(trimmed(ds.string(for: .photometricInterpretation)), pi,
                           "\(codec): PS3.5 8.2.4 / 8.2.14 — MCT = 1 → \(pi)")
            XCTAssertEqual(ds.uint16(for: .planarConfiguration), 0, codec)

            let native = try mgr.decompressData(out, syntax: .explicitVRLittleEndian)
            let nds = try DICOMFile.read(from: native).dataSet
            XCTAssertEqual(trimmed(nds.string(for: .photometricInterpretation)), "RGB",
                           "\(codec): PS3.5 8.2.4 — changed to RGB after decompression")
            if pi == "YBR_RCT" {
                XCTAssertEqual(nds[.pixelData]?.valueData,
                               try DICOMFile.read(from: input).dataSet[.pixelData]?.valueData, codec)
            }
        }
    }

    // MARK: - D-CORE-3: YBR_FULL → J2K

    func test_DCORE3_ybrFull_lossyJ2K_convertedToRGB_labelledYBRICT() throws {
        let input = try makeFile(photometric: "YBR_FULL")
        let mgr = CompressionManager()
        let out = try mgr.compressData(input, codec: "jpeg2000", quality: .high)
        let ds = try DICOMFile.read(from: out).dataSet
        XCTAssertEqual(trimmed(ds.string(for: .photometricInterpretation)), "YBR_ICT")
        let native = try DICOMFile.read(from: try mgr.decompressData(out, syntax: .explicitVRLittleEndian)).dataSet
        XCTAssertEqual(trimmed(native.string(for: .photometricInterpretation)), "RGB")
        // The decoded RGB is the PS3.3 C.7.6.3.1.2 inverse of the source YBR_FULL samples.
        let source = try XCTUnwrap(try DICOMFile.read(from: input).dataSet[.pixelData]?.valueData)
        let decoded = try XCTUnwrap(native[.pixelData]?.valueData)
        // Mean absolute error against the RGB the samples represent is lossy-codec noise; against
        // the unconverted YBR samples it is large.
        var errorRGB = 0, errorYBR = 0
        for p in 0..<(16 * 16) {
            let y = Double(source[p * 3]), cb = Double(source[p * 3 + 1]) - 128, cr = Double(source[p * 3 + 2]) - 128
            let rgb = [y + 1.402 * cr, y - 0.344136 * cb - 0.714136 * cr, y + 1.772 * cb]
            for k in 0..<3 {
                let expected = Int(min(255, max(0, rgb[k].rounded())))
                errorRGB += abs(Int(decoded[p * 3 + k]) - expected)
                errorYBR += abs(Int(decoded[p * 3 + k]) - Int(source[p * 3 + k]))
            }
        }
        XCTAssertLessThan(errorRGB * 10, errorYBR, "decoded samples are RGB, not YBR")
        XCTAssertLessThan(Double(errorRGB) / 768, 4)
    }

    func test_DCORE3_ybrFull_reversibleJ2K_isRefused() {
        XCTAssertThrowsError(try CompressionManager().compressData(
            try makeFile(photometric: "YBR_FULL"), codec: "jpeg2000-lossless", quality: nil)) { error in
            XCTAssertTrue("\(error)".contains("8.2.4"), "\(error)")
        }
    }

    // MARK: - D190 / D-CORE-2: JPEG colour = YBR_FULL_422

    /// SOF component sampling factors, parsed here independently of the library helper.
    private func sofSampling(_ jpeg: Data) -> [String] {
        let b = [UInt8](jpeg)
        var i = 2
        while i + 4 < b.count, b[i] == 0xFF {
            let m = b[i + 1]
            let len = Int(b[i + 2]) << 8 | Int(b[i + 3])
            if m == 0xC0 || m == 0xC1 {
                let n = Int(b[i + 9])
                return (0..<n).map { c in "\(b[i + 11 + c * 3] >> 4)x\(b[i + 11 + c * 3] & 0x0F)" }
            }
            i += 2 + len
        }
        return []
    }

    func test_D190_jpegBaselineColour_is422_labelledYBRFULL422() throws {
        let out = try CompressionManager().compressData(try makeFile(), codec: "jpeg", quality: .high)
        let ds = try DICOMFile.read(from: out).dataSet
        let frame = try XCTUnwrap(ds[.pixelData]?.encapsulatedFragments?.first)
        XCTAssertEqual(sofSampling(frame), ["2x1", "1x1", "1x1"], "CB, CR at half the horizontal Y rate")
        XCTAssertEqual(trimmed(ds.string(for: .photometricInterpretation)), "YBR_FULL_422")
        XCTAssertEqual(ds.uint16(for: .planarConfiguration), 0)

        let converted = try DICOMConverter.convertToDICOM(
            dicomFile: try DICOMFile.read(from: try makeFile()),
            to: try XCTUnwrap(DICOMConverter.resolveTargetEncoding("1.2.840.10008.1.2.4.50")),
            stripPrivate: false)
        let cds = try DICOMFile.read(from: converted.data).dataSet
        XCTAssertEqual(trimmed(cds.string(for: .photometricInterpretation)), "YBR_FULL_422")
        XCTAssertEqual(sofSampling(try XCTUnwrap(cds[.pixelData]?.encapsulatedFragments?.first)),
                       ["2x1", "1x1", "1x1"])
    }

    func test_D190_extendedColour_andImageIOColour_areRefused() throws {
        // Table 8.2.1-1 has no 3-sample row for .51.
        XCTAssertThrowsError(try CompressionManager().compressData(try makeFile(), codec: "jpeg-extended", quality: .high))
        // ImageIO writes 4:2:0 / 4:4:4 YCbCr — neither YBR_FULL_422 nor RGB components.
        XCTAssertThrowsError(try CompressionManager().compressData(try makeFile(), codec: "jpeg", quality: .high,
                                                                   jpegEngine: .native))
        XCTAssertNoThrow(try CompressionManager().compressData(try makeFile(photometric: "MONOCHROME2", samples: 1),
                                                               codec: "jpeg", quality: .high, jpegEngine: .native))
    }

    // MARK: - D188: File Meta UI padding

    func test_D188_fileMetaUIs_areEvenLength_NULLPadded() throws {
        let out = try CompressionManager().compressData(try makeFile(), codec: "rle", quality: nil)
        let meta = try DICOMFile.read(from: out).fileMetaInformation
        for tag in [Tag.mediaStorageSOPClassUID, .mediaStorageSOPInstanceUID, .transferSyntaxUID, .implementationClassUID] {
            let value = try XCTUnwrap(meta[tag]?.valueData, "\(tag)")
            XCTAssertEqual(value.count % 2, 0, "\(tag)")
        }
        let instance = try XCTUnwrap(meta[.mediaStorageSOPInstanceUID]?.valueData)
        XCTAssertEqual(instance, Data((Self.sourceUID + "\0").utf8))
        XCTAssertEqual(try XCTUnwrap(meta[.transferSyntaxUID]?.valueData), Data("1.2.840.10008.1.2.5\0".utf8))
    }

    // MARK: - D206: Explicit VR Big Endian

    func test_D206_bigEndianWrite_swapsValues_andRoundTrips() throws {
        let input = try makeFile(photometric: "MONOCHROME2", samples: 1, bits: 16)
        let mgr = CompressionManager()
        let be = try mgr.decompressData(input, syntax: .explicitVRBigEndian)

        // Rows (0028,0010) US 16 is written 00 28 00 10 'U' 'S' 00 02 00 10.
        let rowsBE = Data([0x00, 0x28, 0x00, 0x10, 0x55, 0x53, 0x00, 0x02, 0x00, 0x10])
        XCTAssertNotNil(be.range(of: rowsBE), "US value byte-swapped (PS3.5 7.3)")

        let file = try DICOMFile.read(from: be)
        XCTAssertEqual(trimmed(file.fileMetaInformation.string(for: .transferSyntaxUID)), "1.2.840.10008.1.2.2")
        XCTAssertEqual(file.dataSet.uint16(for: .rows), 16)
        XCTAssertEqual(file.dataSet.uint16(for: .bitsAllocated), 16)
        let sourcePixels = try XCTUnwrap(try DICOMFile.read(from: input).dataSet[.pixelData]?.valueData)
        let bePixels = try XCTUnwrap(file.dataSet[.pixelData]?.valueData)
        XCTAssertEqual(bePixels.count, sourcePixels.count)
        XCTAssertEqual(bePixels[0], sourcePixels[1]); XCTAssertEqual(bePixels[1], sourcePixels[0])
        XCTAssertEqual(bePixels[34], sourcePixels[35]); XCTAssertEqual(bePixels[35], sourcePixels[34])

        // Back to Explicit VR Little Endian: identical Pixel Data.
        let le = try DICOMFile.read(from: try mgr.decompressData(be, syntax: .explicitVRLittleEndian))
        XCTAssertEqual(le.dataSet[.pixelData]?.valueData, sourcePixels)
        XCTAssertEqual(le.dataSet.uint16(for: .columns), 16)

        // A Big Endian source compresses from its native values (lossless round trip).
        let compressed = try mgr.compressData(be, codec: "jpeg-lossless", quality: nil)
        let back = try DICOMFile.read(from: try mgr.decompressData(compressed, syntax: .explicitVRLittleEndian))
        XCTAssertEqual(back.dataSet[.pixelData]?.valueData, sourcePixels)
    }

    // MARK: - D191: --strip-private inside Sequence Items

    func test_D191_stripPrivate_removesNestedPrivateElements() throws {
        let nested = SequenceItem(elements: [
            DataElement.string(tag: .referencedSOPClassUID, vr: .UI, value: "1.2.840.10008.5.1.4.1.1.7"),
            DataElement.string(tag: Tag(group: 0x0011, element: 0x0010), vr: .LO, value: "ACME"),
            DataElement.string(tag: Tag(group: 0x0011, element: 0x1001), vr: .LO, value: "secret"),
        ])
        let sq = DataElement(tag: Tag(group: 0x0008, element: 0x1140), vr: .SQ, length: 0xFFFFFFFF,
                             valueData: Data(), sequenceItems: [nested])
        let topPrivate = DataElement.string(tag: Tag(group: 0x0009, element: 0x0010), vr: .LO, value: "ACME")
        let source = try DICOMFile.read(from: try makeFile(photometric: "MONOCHROME2", samples: 1,
                                                           extra: [sq, topPrivate]))
        let encoding = try XCTUnwrap(DICOMConverter.resolveTargetEncoding("1.2.840.10008.1.2.1"))
        let outcome = try DICOMConverter.convertToDICOM(dicomFile: source, to: encoding, stripPrivate: true)
        XCTAssertEqual(outcome.strippedPrivateTagCount, 3)
        let ds = try DICOMFile.read(from: outcome.data).dataSet
        XCTAssertNil(ds[Tag(group: 0x0009, element: 0x0010)])
        let item = try XCTUnwrap(ds[Tag(group: 0x0008, element: 0x1140)]?.sequenceItems?.first)
        XCTAssertNil(item[Tag(group: 0x0011, element: 0x0010)])
        XCTAssertNil(item[Tag(group: 0x0011, element: 0x1001)])
        XCTAssertNotNil(item[.referencedSOPClassUID])
    }

    /// D-CORE-5 (found in this batch): TransferSyntaxConverter dropped every defined-length
    /// sequence (PS3.5 2026a 7.5.2 "Explicit Length") on a transcode — DICOMWriter re-encodes an
    /// SQ from its Items, and the converter's parser kept none.
    func test_DCORE5_sequencesSurviveConvert() throws {
        let nested = SequenceItem(elements: [
            DataElement.string(tag: .referencedSOPClassUID, vr: .UI, value: "1.2.840.10008.5.1.4.1.1.7"),
        ])
        let sq = DataElement(tag: Tag(group: 0x0008, element: 0x1140), vr: .SQ, length: 0xFFFFFFFF,
                             valueData: Data(), sequenceItems: [nested])
        let source = try DICOMFile.read(from: try makeFile(extra: [sq]))
        for uid in ["1.2.840.10008.1.2.4.50", "1.2.840.10008.1.2.4.90", "1.2.840.10008.1.2.5", "1.2.840.10008.1.2"] {
            let outcome = try DICOMConverter.convertToDICOM(dicomFile: source, to: try XCTUnwrap(DICOMConverter.resolveTargetEncoding(uid)), stripPrivate: false)
            let ds = try DICOMFile.read(from: outcome.data).dataSet
            XCTAssertNotNil(ds[Tag(group: 0x0008, element: 0x1140)]?.sequenceItems?.first?[.referencedSOPClassUID], uid)
        }
    }

    // MARK: - D197: per-frame rescale

    func test_D197_rescale_usesThePerFramePixelValueTransformation() {
        func frame(_ slope: String, _ intercept: String) -> SequenceItem {
            let pvt = SequenceItem(elements: [
                DataElement.string(tag: .rescaleSlope, vr: .DS, value: slope),
                DataElement.string(tag: .rescaleIntercept, vr: .DS, value: intercept),
            ])
            return SequenceItem(elements: [DataElement(tag: .pixelValueTransformationSequence, vr: .SQ,
                                                       length: 0, valueData: Data(), sequenceItems: [pvt])])
        }
        let ds = DataSet(elements: [
            DataElement(tag: .perFrameFunctionalGroupsSequence, vr: .SQ, length: 0, valueData: Data(),
                        sequenceItems: [frame("1", "0"), frame("2", "-100"), frame("0.5", "10")]),
        ])
        XCTAssertEqual(ds.rescale(100, frameIndex: 0), 100)
        XCTAssertEqual(ds.rescale(100, frameIndex: 1), 100)    // 2 × 100 − 100
        XCTAssertEqual(ds.rescale(100, frameIndex: 2), 60)     // 0.5 × 100 + 10
        XCTAssertEqual(ds.rescale(100), 100)                   // no frame: the first frame's values
    }

    // MARK: - D183: console

    func test_D183_ratioLines_useNto1_andSamplesPerPixelLabel() {
        XCTAssertEqual(CompressionConsole.compressRatioLine(inputSize: 3000, outputSize: 1000),
                       "Compression ratio: 3.00:1\n")
        XCTAssertEqual(CompressionConsole.decompressRatioLine(inputSize: 1000, outputSize: 3000),
                       "Decompression ratio: 1:3.00\n")
        let info = CompressionInfo(transferSyntaxUID: "1.2.840.10008.1.2.1", transferSyntaxName: "x",
                                   isCompressed: false, isLossless: true, isJPEG: false, isJPEG2000: false,
                                   isJPEGLS: false, isJPEGXL: false, isRLE: false, isDeflated: false,
                                   pixelDataSize: 10, rows: 1, columns: 1, bitsAllocated: 8, bitsStored: 8,
                                   samplesPerPixel: 3, photometricInterpretation: "RGB", numberOfFrames: nil)
        XCTAssertTrue(CompressionConsole.infoText(info, filePath: "f").contains("Samples per Pixel: 3\n"))
    }
}
