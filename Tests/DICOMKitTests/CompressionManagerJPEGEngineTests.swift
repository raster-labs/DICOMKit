import XCTest
import Foundation
@testable import DICOMKit
import DICOMCore

/// End-to-end coverage for the `jpegEngine` parameter on `CompressionManager`'s
/// compress entry points: JPEG Baseline can be encoded by either JLICodec or Apple's
/// ImageIO codec, every other codec ignores the parameter, and the `.jli` default
/// keeps `dicom-compress` output unchanged.
final class CompressionManagerJPEGEngineTests: XCTestCase {

    /// 32×32, 8-bit MONOCHROME2 uncompressed file — the configuration both the
    /// JLICodec and the native ImageIO Baseline encoders accept.
    private func makeUncompressed8BitFile() throws -> Data {
        var els: [DataElement] = []
        els.append(.uint16(tag: .rows, value: 32))
        els.append(.uint16(tag: .columns, value: 32))
        els.append(.uint16(tag: .bitsAllocated, value: 8))
        els.append(.uint16(tag: .bitsStored, value: 8))
        els.append(.uint16(tag: .highBit, value: 7))
        els.append(.uint16(tag: .pixelRepresentation, value: 0))
        els.append(.uint16(tag: .samplesPerPixel, value: 1))
        els.append(.string(tag: .photometricInterpretation, vr: .CS, value: "MONOCHROME2"))
        els.append(.string(tag: .sopClassUID, vr: .UI, value: "1.2.840.10008.5.1.4.1.1.7"))
        els.append(.string(tag: .sopInstanceUID, vr: .UI, value: "1.2.3.4.5.6.7.8.9"))
        // A smooth gradient + a hard edge, so the two DCT encoders have something
        // non-trivial to disagree about.
        var pixels = Data()
        for y in 0..<32 {
            for x in 0..<32 {
                pixels.append(UInt8((x * 8 + y * 3) % 256))
            }
        }
        els.append(DataElement(tag: .pixelData, vr: .OB, length: UInt32(pixels.count), valueData: pixels))
        let ds = DataSet(elements: els)
        return try DICOMFile.create(dataSet: ds,
                                    transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid).write()
    }

    /// The encapsulated fragments of a compressed output.
    private func fragments(of data: Data) throws -> [Data] {
        let file = try DICOMFile.read(from: data)
        return try XCTUnwrap(file.dataSet[.pixelData]?.encapsulatedFragments)
    }

    /// Asserts the fragment carries a real JPEG codestream (SOI … EOI).
    private func assertIsJPEG(_ fragment: Data, _ label: String) {
        XCTAssertGreaterThan(fragment.count, 4, "\(label): empty codestream")
        XCTAssertEqual([fragment[0], fragment[1]], [0xFF, 0xD8], "\(label): missing JPEG SOI marker")
    }

    /// Same image, but 16-bit / 12-bit-stored — the shape of a real CT/CR frame.
    private func makeUncompressed16BitFile() throws -> Data {
        var els: [DataElement] = []
        els.append(.uint16(tag: .rows, value: 32))
        els.append(.uint16(tag: .columns, value: 32))
        els.append(.uint16(tag: .bitsAllocated, value: 16))
        els.append(.uint16(tag: .bitsStored, value: 12))
        els.append(.uint16(tag: .highBit, value: 11))
        els.append(.uint16(tag: .pixelRepresentation, value: 0))
        els.append(.uint16(tag: .samplesPerPixel, value: 1))
        els.append(.string(tag: .photometricInterpretation, vr: .CS, value: "MONOCHROME2"))
        els.append(.string(tag: .sopClassUID, vr: .UI, value: "1.2.840.10008.5.1.4.1.1.7"))
        els.append(.string(tag: .sopInstanceUID, vr: .UI, value: "1.2.3.4.5.6.7.8.9"))
        var pixels = Data()
        for i in 0..<(32 * 32) {
            let v = UInt16((i * 3) % 4096)
            pixels.append(UInt8(v & 0xFF)); pixels.append(UInt8((v >> 8) & 0xFF))
        }
        els.append(DataElement(tag: .pixelData, vr: .OW, length: UInt32(pixels.count), valueData: pixels))
        let ds = DataSet(elements: els)
        return try DICOMFile.create(dataSet: ds,
                                    transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid).write()
    }

    // MARK: - Error reporting

    /// JPEG Baseline is 8-bit-only (ITU-T T.81 SOF0 / PS3.5 A.4.1), so a 16-bit source is
    /// rejected by BOTH engines. The failure must be an actionable message, not Foundation's
    /// opaque "(DICOMKit.CompressionError error N.)" bridge string — DICOMStudio's console
    /// prints `error.localizedDescription`, which needs the `LocalizedError` conformance.
    func testSixteenBitBaselineFailsWithReadableMessage() throws {
        let input = try makeUncompressed16BitFile()
        for engine in JPEGCodecEngine.allCases {
            XCTAssertThrowsError(
                try CompressionManager().compressData(
                    input, codec: "jpeg", quality: .high, jpegEngine: engine)
            ) { error in
                // What the CLI prints, via CustomStringConvertible.
                let interpolated = "\(error)"
                // What DICOMStudio prints. Must now say the same thing.
                let localized = error.localizedDescription

                for message in [interpolated, localized] {
                    XCTAssertTrue(message.contains("bitsAllocated=16"),
                                  "\(engine.rawValue): unhelpful message: \(message)")
                    XCTAssertFalse(message.contains("couldn't be completed"),
                                   "\(engine.rawValue): opaque NSError bridge string: \(message)")
                }
                XCTAssertEqual(interpolated, localized,
                               "\(engine.rawValue): CLI and app report different text")
            }
        }
    }

    /// Every `CompressionError` case must round-trip through `localizedDescription`.
    func testAllCompressionErrorsAreReadable() {
        let errors: [CompressionError] = [
            .unknownCodec("bogus"),
            .noPixelData,
            .encoderNotAvailable("1.2.3"),
            .decoderNotAvailable("1.2.3"),
            .unsupportedPixelDataConfiguration("bitsAllocated=16"),
            .invalidQuality("nope"),
        ]
        for error in errors {
            XCTAssertEqual(error.localizedDescription, error.description)
            XCTAssertFalse(error.localizedDescription.contains("couldn't be completed"))
        }
    }

    // MARK: - Default engine is unchanged

    /// The `.jli` default must be byte-for-byte what an engine-less call produces —
    /// this is what guarantees the `dicom-compress` CLI (which never passes the
    /// parameter) keeps its exact current output.
    func testDefaultEngineMatchesEnginelessCall() throws {
        let input = try makeUncompressed8BitFile()
        let mgr = CompressionManager()
        let implicitDefault = try mgr.compressData(input, codec: "jpeg", quality: .high)
        let explicitJLI = try mgr.compressData(input, codec: "jpeg", quality: .high, jpegEngine: .jli)
        // Each lossy output gets its own new SOP Instance UID (PS3.3 2026a C.7.6.1.1.5, D184),
        // so the codestreams are compared, not the whole files.
        XCTAssertEqual(try fragments(of: implicitDefault), try fragments(of: explicitJLI))
    }

    // MARK: - Baseline: the two engines really are different encoders

    func testBaselineJLIEngineProducesValidJPEG() throws {
        let input = try makeUncompressed8BitFile()
        let out = try CompressionManager().compressData(
            input, codec: "jpeg", quality: .high, jpegEngine: .jli)
        let frags = try fragments(of: out)
        XCTAssertEqual(frags.count, 1)
        assertIsJPEG(frags[0], "jli")
    }

    #if canImport(ImageIO)
    func testBaselineNativeEngineProducesValidJPEG() throws {
        let input = try makeUncompressed8BitFile()
        let out = try CompressionManager().compressData(
            input, codec: "jpeg", quality: .high, jpegEngine: .native)
        let frags = try fragments(of: out)
        XCTAssertEqual(frags.count, 1)
        assertIsJPEG(frags[0], "native")
    }

    /// The point of the whole feature: selecting `.native` must actually route to a
    /// different encoder, not silently fall back to JLICodec. Two independent JPEG
    /// encoders never emit identical bytes for the same input (different quantisation
    /// tables, Huffman tables, and APPn segments).
    func testBaselineEnginesProduceDifferentCodestreams() throws {
        let input = try makeUncompressed8BitFile()
        let mgr = CompressionManager()
        let jliFrag = try fragments(of: mgr.compressData(
            input, codec: "jpeg", quality: .high, jpegEngine: .jli))[0]
        let nativeFrag = try fragments(of: mgr.compressData(
            input, codec: "jpeg", quality: .high, jpegEngine: .native))[0]
        XCTAssertNotEqual(jliFrag, nativeFrag,
                          "native engine silently fell back to the JLICodec encoder")
    }

    /// Whichever engine encoded it, the result must be decodable by the registry's
    /// Baseline decoder and round-trip to the right pixel count.
    func testNativeEncodedBaselineDecodesBackToCorrectDimensions() throws {
        let input = try makeUncompressed8BitFile()
        let compressed = try CompressionManager().compressData(
            input, codec: "jpeg", quality: .high, jpegEngine: .native)
        let restored = try CompressionManager().decompressData(
            compressed, syntax: .explicitVRLittleEndian)
        let file = try DICOMFile.read(from: restored)
        let pixels = try XCTUnwrap(file.dataSet[.pixelData]?.valueData)
        XCTAssertEqual(pixels.count, 32 * 32, "decoded pixel buffer has the wrong size")
        XCTAssertEqual(file.dataSet.uint16(for: .rows), 32)
        XCTAssertEqual(file.dataSet.uint16(for: .columns), 32)
    }

    /// Baseline is lossy, so both engines must record the lossy-compression provenance
    /// attributes (PS3.3 C.7.6.1.1.5) — the engine choice must not change that.
    func testBothEnginesRecordLossyProvenance() throws {
        let input = try makeUncompressed8BitFile()
        for engine in JPEGCodecEngine.allCases {
            let out = try CompressionManager().compressData(
                input, codec: "jpeg", quality: .high, jpegEngine: engine)
            let ds = try DICOMFile.read(from: out).dataSet
            XCTAssertEqual(ds.string(for: .lossyImageCompression)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")), "01",
                "\(engine.rawValue): missing lossy flag")
        }
    }
    #endif

    // MARK: - Every other codec ignores the engine

    /// The three other JPEG syntaxes have no ImageIO encoder, so `.native` must be a
    /// no-op for them — identical bytes, not an error and not a different encoder.
    func testOtherJPEGSyntaxesIgnoreEngine() throws {
        let input = try makeUncompressed8BitFile()
        let mgr = CompressionManager()
        for codec in ["jpeg-extended", "jpeg-lossless", "jpeg-lossless-sv1"] {
            let jli = try mgr.compressData(input, codec: codec, quality: .high, jpegEngine: .jli)
            let native = try mgr.compressData(input, codec: codec, quality: .high, jpegEngine: .native)
            // Codestreams, not files: lossy output has a fresh SOP Instance UID per run (D184).
            XCTAssertEqual(try fragments(of: jli), try fragments(of: native),
                           "\(codec) was diverted off JLICodec by the native engine")
        }
    }

    func testNonJPEGCodecsIgnoreEngine() throws {
        let input = try makeUncompressed8BitFile()
        let mgr = CompressionManager()
        for codec in ["rle", "jpeg-ls-lossless", "jpeg2000-lossless"] {
            let jli = try mgr.compressData(input, codec: codec, quality: nil, jpegEngine: .jli)
            let native = try mgr.compressData(input, codec: codec, quality: nil, jpegEngine: .native)
            XCTAssertEqual(jli, native, "\(codec) was affected by the JPEG engine parameter")
        }
    }

    // MARK: - Metrics entry point threads the engine through

    func testCompressDataWithMetricsHonoursEngine() throws {
        let input = try makeUncompressed8BitFile()
        let mgr = CompressionManager()
        let (jliOut, jliMetrics) = try mgr.compressDataWithMetrics(
            input, codec: "jpeg", quality: .high, jpegEngine: .jli)
        XCTAssertFalse(jliMetrics.isRecompression)
        XCTAssertEqual(jliMetrics.outputSize, jliOut.count)

        #if canImport(ImageIO)
        let (nativeOut, nativeMetrics) = try mgr.compressDataWithMetrics(
            input, codec: "jpeg", quality: .high, jpegEngine: .native)
        XCTAssertEqual(nativeMetrics.outputSize, nativeOut.count)
        XCTAssertNotEqual(jliOut, nativeOut, "metrics path ignored the engine parameter")
        #endif
    }

    /// Recompression (already-compressed source → JPEG Baseline) must route the
    /// *encode* half of the transcode through the selected engine too.
    #if canImport(ImageIO)
    func testRecompressionHonoursEngine() throws {
        let input = try makeUncompressed8BitFile()
        let mgr = CompressionManager()
        let rleSource = try mgr.compressData(input, codec: "rle", quality: nil)

        let viaJLI = try mgr.compressDataWithMetrics(
            rleSource, codec: "jpeg", quality: .high, jpegEngine: .jli)
        let viaNative = try mgr.compressDataWithMetrics(
            rleSource, codec: "jpeg", quality: .high, jpegEngine: .native)

        XCTAssertTrue(viaJLI.metrics.isRecompression)
        XCTAssertTrue(viaNative.metrics.isRecompression)
        XCTAssertNotEqual(viaJLI.data, viaNative.data,
                          "recompression encode phase ignored the engine parameter")
    }
    #endif

    // MARK: - Compressed-domain fast paths in CompressionManager

    /// Lossless J2K Part 1 (.90 / reversible .91) <-> HTJ2K (.201 / .202 / reversible .203) in
    /// `CompressionManager.compressData` uses `SwiftJ2KDICOMTranscoder` in the compressed domain
    /// and preserves exact pixels.
    func testLosslessJ2KToHTJ2KUsesCompressedDomainFastPathAndPreservesPixels() throws {
        let input = try makeUncompressed16BitFile()
        let mgr = CompressionManager()
        let expectedPixels = try DICOMFile.read(from: input).tryPixelData().data

        let j2kData = try mgr.compressData(input, codec: "j2k-lossless-only", quality: nil)
        let htj2kData = try mgr.compressData(j2kData, codec: "htj2k-lossless-only", quality: nil)
        let htj2kRPCLData = try mgr.compressData(htj2kData, codec: "htj2k-rpcl", quality: nil)
        let backToJ2K = try mgr.compressData(htj2kRPCLData, codec: "j2k-lossless-only", quality: nil)

        let htj2kFile = try DICOMFile.read(from: htj2kData)
        XCTAssertEqual(htj2kFile.transferSyntaxUID, TransferSyntax.htj2kLossless.uid)
        XCTAssertEqual(try htj2kFile.tryPixelData().data, expectedPixels)

        let rpclFile = try DICOMFile.read(from: htj2kRPCLData)
        XCTAssertEqual(rpclFile.transferSyntaxUID, TransferSyntax.htj2kRPCLLossless.uid)
        XCTAssertEqual(try rpclFile.tryPixelData().data, expectedPixels)

        let roundTripFile = try DICOMFile.read(from: backToJ2K)
        XCTAssertEqual(roundTripFile.transferSyntaxUID, TransferSyntax.jpeg2000Lossless.uid)
        XCTAssertEqual(try roundTripFile.tryPixelData().data, expectedPixels)

        // General UIDs (.91 reversible -> .203 reversible) also preserve exact pixels.
        let j2kGeneral = try mgr.compressData(input, codec: "j2k-lossless", quality: nil)
        let htj2kGeneral = try mgr.compressData(j2kGeneral, codec: "htj2k-lossless", quality: nil)
        let generalFile = try DICOMFile.read(from: htj2kGeneral)
        XCTAssertEqual(generalFile.transferSyntaxUID, TransferSyntax.htj2kLossy.uid)
        XCTAssertEqual(try generalFile.tryPixelData().data, expectedPixels)
    }

    /// Reconstructing JPEG Baseline (.50) from a JPEG XL Recompression (.111) dataset via
    /// `CompressionManager.compressData(..., codec: "jpeg", quality: nil)` recovers the exact
    /// original JPEG bitstream byte-for-byte without re-quantizing pixels.
    func testJPEGXLRecompressionReverseReconstructsExactJPEGFragment() throws {
        let input = try makeUncompressed8BitFile()
        let mgr = CompressionManager()

        let baselineData = try mgr.compressData(input, codec: "jpeg", quality: .high, jpegEngine: .jli)
        let originalJPEGFrag = try fragments(of: baselineData)[0]

        let baselineFile = try DICOMFile.read(from: baselineData)
        let jxlRecompData = try DICOMConverter.convertToDICOM(
            dicomFile: baselineFile,
            to: .jpegXLRecompression,
            stripPrivate: false
        ).data

        let reconstructedData = try mgr.compressData(
            jxlRecompData, codec: "jpeg", quality: nil, jpegEngine: .jli
        )
        let reconstructedJPEGFrag = try fragments(of: reconstructedData)[0]
        XCTAssertEqual(reconstructedJPEGFrag, originalJPEGFrag,
                       "Expected byte-for-byte JPEG reconstruction from .111 via JXLCodec.reconstructJPEGFragment")
    }
}
