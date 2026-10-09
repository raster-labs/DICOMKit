import XCTest
import Foundation
@testable import DICOMKit
import DICOMCore
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Regression: the rendered preview of a freshly *compressed* file must match the
/// render of the *decompressed* version of that same file, for every codec.
///
/// This pins the fix for a colour-preview corruption bug: `DICOMFile.pixelData()`
/// used to relabel YBR pixel data as RGB for the transfer syntaxes that the retired
/// ImageIO codecs once handled (JPEG 50/51/57/70, JPEG 2000 90/91). The current
/// registry uses pure-Swift codecs that decode to the *source* photometric, so the
/// relabel suppressed the renderer's YBR→RGB conversion and washed out / blanked the
/// preview — while a round-trip decompress (which renders the un-encapsulated bytes
/// directly) looked correct. The two paths must agree.
final class CompressedPreviewRenderParityTests: XCTestCase {

    private func grayElements(dim: Int = 16, bitsStored: UInt16 = 12) -> [DataElement] {
        var els: [DataElement] = []
        els.append(.uint16(tag: .rows, value: UInt16(dim)))
        els.append(.uint16(tag: .columns, value: UInt16(dim)))
        els.append(.uint16(tag: .bitsAllocated, value: 16))
        els.append(.uint16(tag: .bitsStored, value: bitsStored))
        els.append(.uint16(tag: .highBit, value: bitsStored - 1))
        els.append(.uint16(tag: .pixelRepresentation, value: 0))
        els.append(.uint16(tag: .samplesPerPixel, value: 1))
        els.append(.string(tag: .photometricInterpretation, vr: .CS, value: "MONOCHROME2"))
        els.append(.string(tag: .sopClassUID, vr: .UI, value: "1.2.840.10008.5.1.4.1.1.7"))
        els.append(.string(tag: .sopInstanceUID, vr: .UI, value: "1.2.3.4.5.6.7.8.9"))
        let maxV = (1 << Int(bitsStored)) - 1
        var pixels = Data()
        for y in 0..<dim {
            for x in 0..<dim {
                var v = ((x + y) * maxV / (2 * dim))
                if x > dim/4 && x < 3*dim/4 && y > dim/4 && y < 3*dim/4 { v = maxV }
                let vv = UInt16(min(maxV, v))
                pixels.append(UInt8(vv & 0xFF))
                pixels.append(UInt8((vv >> 8) & 0xFF))
            }
        }
        els.append(DataElement(tag: .pixelData, vr: .OW, length: UInt32(pixels.count), valueData: pixels))
        return els
    }

    private func rgbElements(photometric: String) -> [DataElement] {
        var els: [DataElement] = []
        els.append(.uint16(tag: .rows, value: 16))
        els.append(.uint16(tag: .columns, value: 16))
        els.append(.uint16(tag: .bitsAllocated, value: 8))
        els.append(.uint16(tag: .bitsStored, value: 8))
        els.append(.uint16(tag: .highBit, value: 7))
        els.append(.uint16(tag: .pixelRepresentation, value: 0))
        els.append(.uint16(tag: .samplesPerPixel, value: 3))
        els.append(.uint16(tag: .planarConfiguration, value: 0))
        els.append(.string(tag: .photometricInterpretation, vr: .CS, value: photometric))
        els.append(.string(tag: .sopClassUID, vr: .UI, value: "1.2.840.10008.5.1.4.1.1.7"))
        els.append(.string(tag: .sopInstanceUID, vr: .UI, value: "1.2.3.4.5.6.7.8.9"))
        var pixels = Data()
        for i in 0..<256 {
            pixels.append(UInt8(i % 256))
            pixels.append(UInt8((i * 3) % 256))
            pixels.append(UInt8((i * 7) % 256))
        }
        els.append(DataElement(tag: .pixelData, vr: .OB, length: UInt32(pixels.count), valueData: pixels))
        return els
    }

    private func makeFile(_ els: [DataElement]) throws -> Data {
        let ds = DataSet(elements: els)
        return try DICOMFile.create(dataSet: ds,
                                    transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid).write()
    }

    #if canImport(CoreGraphics)
    /// Raw RGBA bytes of the rendered first frame (using the file's stored window).
    private func renderRGBA(_ data: Data) throws -> [UInt8] {
        let file = try DICOMFile.read(from: data)
        guard let img = file.renderFrameWithStoredWindow(0) ?? file.renderFrame(0),
              let cg = img.copy(), let provider = cg.dataProvider, let px = provider.data else {
            return []
        }
        let len = CFDataGetLength(px)
        let ptr = CFDataGetBytePtr(px)!
        return Array(UnsafeBufferPointer(start: ptr, count: len))
    }

    private func distinctLuma(_ rgba: [UInt8]) -> Int {
        var seen = Set<UInt8>()
        var i = 0
        while i + 2 < rgba.count { seen.insert(rgba[i]); i += 4 }
        return seen.count
    }
    #endif

    // Every codec the in-process registry can both encode and decode.
    // (JPEG 2000 Part-2 is intentionally excluded — it is decode-only: the library
    // cannot invert its multi-component transform, so encoding is rejected.)
    private let losslessCodecs = [
        "jpeg2000-lossless", "htj2k-lossless", "htj2k-rpcl",
        "jpeg-lossless", "jpeg-ls-lossless", "rle",
    ]

    func testCompressedPreviewMatchesDecompressedRender() throws {
        #if canImport(CoreGraphics)
        let sources: [(label: String, data: Data)] = [
            ("gray16", try makeFile(grayElements())),
            ("gray16-256", try makeFile(grayElements(dim: 256, bitsStored: 12))),
            ("rgb8", try makeFile(rgbElements(photometric: "RGB"))),
            ("ybrFull", try makeFile(rgbElements(photometric: "YBR_FULL"))),
            ("ybrICT", try makeFile(rgbElements(photometric: "YBR_ICT"))),
            ("ybrRCT", try makeFile(rgbElements(photometric: "YBR_RCT"))),
        ]
        let mgr = CompressionManager()

        for src in sources {
            for codec in losslessCodecs {
                // YBR_FULL needs SGcod MCT 0, which J2KSwift cannot write, and its conversion to
                // RGB is not bit-preserving, so a reversible J2K / HTJ2K encode is refused
                // (PS3.5 2026a 8.2.4, Table 8.2.4-1; D-CORE-3).
                if src.label == "ybrFull", codec.hasPrefix("jpeg2000") || codec.hasPrefix("htj2k") {
                    XCTAssertThrowsError(try mgr.compressData(src.data, codec: codec, quality: nil), codec)
                    continue
                }
                let compressed = try mgr.compressData(src.data, codec: codec, quality: nil)
                let decompressed = try mgr.decompressData(compressed, syntax: .explicitVRLittleEndian)

                let cRGBA = try renderRGBA(compressed)
                let dRGBA = try renderRGBA(decompressed)

                XCTAssertFalse(cRGBA.isEmpty, "[\(src.label)/\(codec)] compressed render produced no image")
                XCTAssertFalse(dRGBA.isEmpty, "[\(src.label)/\(codec)] decompressed render produced no image")
                // The compressed-file preview and the decompressed render must be
                // byte-for-byte identical — lossless codecs preserve pixels and both
                // paths must interpret photometric the same way.
                XCTAssertEqual(cRGBA, dRGBA,
                    "[\(src.label)/\(codec)] compressed preview differs from decompressed render "
                    + "(compressed distinctLuma=\(distinctLuma(cRGBA)), decompressed distinctLuma=\(distinctLuma(dRGBA)))")
            }
        }
        #endif
    }
}
