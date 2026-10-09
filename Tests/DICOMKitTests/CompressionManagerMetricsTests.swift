import XCTest
import Foundation
@testable import DICOMKit
import DICOMCore

/// Tests for `CompressionManager.compressDataWithMetrics` — the metrics-returning
/// entry point that powers the `dicom-compress` console (per-phase sizes + timings).
/// Covers plain compress, recompression (already-compressed source → a *different*
/// codec, which the engine performs as an explicit decompress phase + compress
/// phase), and the same-syntax passthrough (NOT a recompression).
final class CompressionManagerMetricsTests: XCTestCase {

    /// 8×8, 16-bit, 12-bit-stored MONOCHROME2 uncompressed file + its native pixels.
    private func makeUncompressedFile() throws -> (data: Data, pixels: Data) {
        var els: [DataElement] = []
        els.append(.uint16(tag: .rows, value: 8))
        els.append(.uint16(tag: .columns, value: 8))
        els.append(.uint16(tag: .bitsAllocated, value: 16))
        els.append(.uint16(tag: .bitsStored, value: 12))
        els.append(.uint16(tag: .highBit, value: 11))
        els.append(.uint16(tag: .pixelRepresentation, value: 0))
        els.append(.uint16(tag: .samplesPerPixel, value: 1))
        els.append(.string(tag: .photometricInterpretation, vr: .CS, value: "MONOCHROME2"))
        els.append(.string(tag: .sopClassUID, vr: .UI, value: "1.2.840.10008.5.1.4.1.1.7"))
        els.append(.string(tag: .sopInstanceUID, vr: .UI, value: "1.2.3.4.5.6.7.8.9"))
        var pixels = Data()
        for i in 0..<64 {
            let v = UInt16((i * 60) % 4096)
            pixels.append(UInt8(v & 0xFF)); pixels.append(UInt8((v >> 8) & 0xFF))
        }
        els.append(DataElement(tag: .pixelData, vr: .OW, length: UInt32(pixels.count), valueData: pixels))
        let ds = DataSet(elements: els)
        let data = try DICOMFile.create(dataSet: ds,
                                        transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid).write()
        return (data, pixels)
    }

    /// Plain compress (uncompressed source): single compression phase, no
    /// decompression metrics.
    func testPlainCompressMetrics() throws {
        let (uncompressed, _) = try makeUncompressedFile()
        let mgr = CompressionManager()
        let (out, m) = try mgr.compressDataWithMetrics(uncompressed, codec: "jpeg2000-lossless", quality: nil)

        XCTAssertFalse(m.isRecompression)
        XCTAssertNil(m.intermediateSize)
        XCTAssertNil(m.decompressElapsed)
        XCTAssertNil(m.sourceTransferSyntaxName)
        XCTAssertEqual(m.inputSize, uncompressed.count)
        XCTAssertEqual(m.outputSize, out.count)
        XCTAssertGreaterThanOrEqual(m.compressElapsed, 0)

        let f = try DICOMFile.read(from: out)
        XCTAssertNotNil(f.dataSet[.pixelData]?.encapsulatedFragments, "output should be encapsulated")
    }

    /// Recompression (JPEG 2000 Lossless → JPEG-LS Lossless): two phases are timed +
    /// sized, and the lossless chain preserves pixels exactly.
    func testRecompressionMetricsAndPixelFidelity() throws {
        let (uncompressed, originalPixels) = try makeUncompressedFile()
        let mgr = CompressionManager()
        // Reversible-only .90 source (symmetric naming: `-lossless-only` selects the .90 UID;
        // bare `jpeg2000-lossless` now encodes reversibly into the general .91).
        let j2k = try mgr.compressData(uncompressed, codec: "jpeg2000-lossless-only", quality: nil)

        let (out, m) = try mgr.compressDataWithMetrics(j2k, codec: "jpeg-ls-lossless", quality: nil)

        XCTAssertTrue(m.isRecompression, "J2K → JPEG-LS is a cross-codec recompression")
        XCTAssertEqual(m.inputSize, j2k.count)
        XCTAssertEqual(m.outputSize, out.count)
        XCTAssertNotNil(m.decompressElapsed)
        XCTAssertGreaterThanOrEqual(m.decompressElapsed ?? -1, 0)
        XCTAssertGreaterThanOrEqual(m.compressElapsed, 0)
        // The intermediate size is exactly the decompressed (native) file size. (For a
        // tiny 8×8 image it can be SMALLER than the compressed source — codec overhead
        // exceeds the pixel savings — so assert the precise invariant, not "larger".)
        let expectedIntermediate = try mgr.decompressData(j2k, syntax: .explicitVRLittleEndian).count
        XCTAssertEqual(m.intermediateSize, expectedIntermediate)
        XCTAssertGreaterThan(m.intermediateSize ?? 0, 0)
        XCTAssertEqual(m.sourceTransferSyntaxName, "JPEG 2000 Image Compression (Lossless Only)")  // PS3.6 Table A-1 (D176)

        // Output really is JPEG-LS encapsulated.
        let f = try DICOMFile.read(from: out)
        XCTAssertNotNil(f.dataSet[.pixelData]?.encapsulatedFragments)
        let outTS = f.fileMetaInformation.string(for: .transferSyntaxUID)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
        XCTAssertEqual(outTS, TransferSyntax.jpegLSLossless.uid)

        // Lossless in → lossless out: decompressing the result restores the pixels.
        let back = try mgr.decompressData(out, syntax: .explicitVRLittleEndian)
        let restored = try DICOMFile.read(from: back)
        XCTAssertEqual(restored.dataSet[.pixelData]?.valueData, originalPixels,
                       "recompressed pixels differ from original (lossless chain must round-trip)")
    }

    /// Same encapsulated syntax on both sides is a byte passthrough — NOT a
    /// recompression (no decode/re-encode, no decompression metrics).
    func testSameSyntaxIsNotRecompression() throws {
        let (uncompressed, _) = try makeUncompressedFile()
        let mgr = CompressionManager()
        let j2k = try mgr.compressData(uncompressed, codec: "jpeg2000-lossless", quality: nil)

        let (_, m) = try mgr.compressDataWithMetrics(j2k, codec: "jpeg2000-lossless", quality: nil)
        XCTAssertFalse(m.isRecompression)
        XCTAssertNil(m.intermediateSize)
        XCTAssertNil(m.decompressElapsed)
    }

    /// Re-compressing an already-JPEG 2000 file with the SAME lossy syntax but an
    /// explicit `--quality` must actually decode + re-encode (honoring the quality),
    /// not pass the existing codestream through verbatim. Regression guard for the
    /// bug where `--quality` was silently dropped on a same-syntax lossy target
    /// (input size == output size, ~0 ms, unchanged bytes).
    func testSameSyntaxLossyReencodeHonorsQuality() throws {
        let (uncompressed, _) = try makeUncompressedFile()
        let mgr = CompressionManager()

        // A lossy JPEG 2000 (.91) source.
        let lossy = try mgr.compressData(uncompressed, codec: "jpeg2000", quality: .medium)
        let sourcePixels = try DICOMFile.read(from: lossy)
            .dataSet[.pixelData]?.encapsulatedFragments?.reduce(Data()) { $0 + $1 }
        XCTAssertNotNil(sourcePixels)

        // Re-encode into the same .91 UID at a DIFFERENT (lower) quality.
        let reencoded = try mgr.compressData(lossy, codec: "jpeg2000", quality: .low)
        let outPixels = try DICOMFile.read(from: reencoded)
            .dataSet[.pixelData]?.encapsulatedFragments?.reduce(Data()) { $0 + $1 }
        XCTAssertNotNil(outPixels)

        // A real re-encode produces a different codestream than the source; a
        // silent passthrough would return the identical bytes.
        XCTAssertNotEqual(outPixels, sourcePixels,
                          "same-syntax lossy re-encode must not pass the source codestream through unchanged")

        // Via the metrics entry point it is reported as a two-phase recompression
        // (decompress → re-encode), so the console shows the two-phase note.
        let (_, m) = try mgr.compressDataWithMetrics(lossy, codec: "jpeg2000", quality: .low)
        XCTAssertTrue(m.isRecompression)
        XCTAssertNotNil(m.intermediateSize)
        XCTAssertNotNil(m.decompressElapsed)
        XCTAssertNotNil(m.sourceTransferSyntaxName)
    }
}
