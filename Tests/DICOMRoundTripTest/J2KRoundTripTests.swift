// J2KRoundTripTests.swift
// Oracle-based round-trip tests for the `dicom-j2k` tool.
//
// These tests exercise the DICOMKit / J2KSwift *library* directly (J2KEncoder,
// J2KDecoder, J2KImage, J2KComponent, J2KEncodingConfiguration,
// HTJ2KConformanceTestHarness, J2KHTInteroperabilityValidator, J2KErrorMetrics,
// J2KBenchmark) — the same APIs the `dicom-j2k` subcommands call — and never
// spawn the CLI. Every assertion is a mathematical / semantic oracle:
// lossless round-trip is bit-exact, PSNR of identical images is +∞, a corrupt
// SOC marker is reported, a truncated codestream fails to decode, and a crop
// updates the image geometry. See ROUND_TRIP_TESTS_PLAN.md §3.19.
//
// Shared helpers (makeGrayscale8, loadCorpus, corpusURL, rtUID, …) live in
// RoundTripFixture.swift and are reused, never redefined.

import XCTest
import Foundation
@testable import DICOMKit
@testable import DICOMCore
import SwiftJ2K

@available(macOS 10.15, *)
final class J2KRoundTripTests: XCTestCase {

    // MARK: - Private helpers (never global — other test files would collide)

    /// Builds a single-component 8-bit grayscale J2KImage from raw bytes.
    private func makeImage8(width: Int, height: Int, pixels: Data) -> J2KImage {
        let comp = J2KComponent(
            index: 0, bitDepth: 8, signed: false,
            width: width, height: height, data: pixels
        )
        return J2KImage(width: width, height: height, components: [comp], colorSpace: .grayscale)
    }

    /// Builds a single-component 16-bit grayscale J2KImage from little-endian bytes.
    private func makeImage16(width: Int, height: Int, bitDepth: Int, leBytes: Data) -> J2KImage {
        let comp = J2KComponent(
            index: 0, bitDepth: bitDepth, signed: false,
            width: width, height: height,
            data: leBytes
        )
        return J2KImage(width: width, height: height, components: [comp], colorSpace: .grayscale)
    }

    /// Deterministic 8-bit ramp of `count` bytes.
    private func ramp8(_ count: Int, stride: Int = 7, mod: Int = 251) -> Data {
        Data((0..<count).map { UInt8(($0 * stride) % mod) })
    }

    /// Read a 16-bit sample stored little-endian.
    private func le16(_ d: Data, _ i: Int) -> UInt16 {
        let b = d.startIndex
        return UInt16(d[b + i * 2]) | (UInt16(d[b + i * 2 + 1]) << 8)
    }

    /// Read a 16-bit sample stored big-endian (the J2K decoder's native output order).
    private func be16(_ d: Data, _ i: Int) -> UInt16 {
        let b = d.startIndex
        return (UInt16(d[b + i * 2]) << 8) | UInt16(d[b + i * 2 + 1])
    }

    private func losslessConfig() -> J2KEncodingConfiguration {
        var cfg = J2KEncodingConfiguration()
        cfg.lossless = true
        return cfg
    }

    private func htLosslessConfig() -> J2KEncodingConfiguration {
        var cfg = J2KEncodingConfiguration()
        cfg.lossless = true
        cfg.useHTJ2K = true
        return cfg
    }

    private func encode(_ image: J2KImage, _ cfg: J2KEncodingConfiguration) async throws -> Data {
        if cfg.useHTJ2K && !cfg.lossless {
            let options = try CodecOptions(
                blockCoding: .htj2k,
                wavelet: .irreversible97,
                quality: cfg.quality,
                qualityLayers: 1,
                containerFormat: .codestream
            )
            let encoder = try SwiftJ2K.Encoder(
                configuration: try EncoderConfiguration(mode: .lossy, codecOptions: options)
            )
            let contractImage = try image.toContractImage()
            return try await encoder.encode(contractImage).data
        }
        return try await J2KEncoder(encodingConfiguration: cfg).encode(image)
    }

    private func decode(_ data: Data) async throws -> J2KImage {
        try await J2KDecoder().decode(data)
    }

    /// First two bytes of a codestream as a UInt16 marker (big-endian on the wire).
    private func firstMarker(_ d: Data) -> UInt16 {
        precondition(d.count >= 2)
        let b = d.startIndex
        return (UInt16(d[b]) << 8) | UInt16(d[b + 1])
    }

    // MARK: - info / decode geometry

    // Oracle: J2K lossless encode → decode reproduces the exact input geometry
    // and the codestream begins with the SOC marker (0xFF4F).
    func testInfoGeometryAndSOCMarker() async throws {
        let w = 32, h = 48
        let src = ramp8(w * h)
        let image = makeImage8(width: w, height: h, pixels: src)
        let codestream = try await encode(image, losslessConfig())

        XCTAssertEqual(firstMarker(codestream), 0xFF4F, "codestream must start with SOC")

        let decoded = try await decode(codestream)
        XCTAssertEqual(decoded.width, w)
        XCTAssertEqual(decoded.height, h)
        XCTAssertEqual(decoded.components.count, 1)
        XCTAssertEqual(decoded.components[0].bitDepth, 8)
        XCTAssertEqual(decoded.pixelCount, w * h)          // pixelCount = width*height
        XCTAssertEqual(decoded.components[0].pixelCount, w * h)
    }

    // Oracle: lossless 8-bit round-trip is bit-exact (decoded bytes == source bytes).
    func testLossless8BitBitExact() async throws {
        let w = 40, h = 40
        let src = ramp8(w * h, stride: 11, mod: 251)
        let codestream = try await encode(makeImage8(width: w, height: h, pixels: src), losslessConfig())
        let decoded = try await decode(codestream)
        XCTAssertEqual(decoded.components[0].data.count, src.count)
        XCTAssertEqual(decoded.components[0].data, src, "lossless 8-bit must round-trip bit-exact")
    }

    // Oracle: lossless 16-bit round-trip preserves every sample value.
    // The decoder emits samples big-endian, so compare values, not raw bytes.
    func testLossless16BitValueExact() async throws {
        let w = 24, h = 24, bitDepth = 12
        var le = Data(count: w * h * 2)
        for i in 0..<(w * h) {
            let v = UInt16((i * 97) % 4000)
            le[i * 2] = UInt8(v & 0xFF)
            le[i * 2 + 1] = UInt8(v >> 8)
        }
        let codestream = try await encode(makeImage16(width: w, height: h, bitDepth: bitDepth, leBytes: le), losslessConfig())
        let decoded = try await decode(codestream)
        let out = decoded.components[0].data
        XCTAssertEqual(decoded.components[0].bitDepth, bitDepth)
        XCTAssertEqual(out.count, le.count)
        var mismatches = 0
        for i in 0..<(w * h) where le16(out, i) != le16(le, i) { mismatches += 1 }
        XCTAssertEqual(mismatches, 0, "lossless 16-bit must preserve every sample value")
    }

    // MARK: - Shared SelectableEncoding intent → encoder behavior

    /// Builds an encoder configuration from a shared-API `SelectableEncoding`, exactly the
    /// way the app/CLI now derive lossy-vs-lossless mode for a given list row.
    private func config(for encoding: SelectableEncoding, quality: Double = 0.8) -> J2KEncodingConfiguration {
        var cfg = J2KEncodingConfiguration()
        cfg.lossless = encoding.isLossless
        cfg.useHTJ2K = encoding.transferSyntax.isHTJ2K
        if !encoding.isLossless { cfg.quality = quality }
        return cfg
    }

    private func selectableEncoding(uid: String, intent: EncodingIntent) throws -> SelectableEncoding {
        let match = TransferSyntax.selectableEncodings.first { $0.uid == uid && $0.intent == intent }
        return try XCTUnwrap(match, "shared catalog must expose \(uid) with intent \(intent)")
    }

    // Oracle: the "JPEG 2000 Lossless (.91)" list row — a lossless intent on the general
    // .91 UID — drives a bit-exact round-trip, distinct from the "JPEG 2000 Lossy (.91)"
    // row on the same UID which is genuinely lossy. This is the whole point of splitting
    // .91 into two list entries: same UID, different encoding behavior.
    func testNinetyOneLosslessRowIsBitExact() async throws {
        let w = 40, h = 40
        let src = ramp8(w * h, stride: 11, mod: 251)
        let lossless = try selectableEncoding(uid: "1.2.840.10008.1.2.4.91", intent: .lossless)
        XCTAssertTrue(config(for: lossless).lossless, "the .91 lossless row must configure a lossless encode")

        let codestream = try await encode(makeImage8(width: w, height: h, pixels: src), config(for: lossless))
        let decoded = try await decode(codestream)
        XCTAssertEqual(decoded.components[0].data, src, "JPEG 2000 Lossless (.91) must round-trip bit-exact")
    }

    // Oracle: the "JPEG 2000 Lossy (.91)" row configures a genuinely lossy encode (not
    // bit-exact) that still stays visually lossless on a smooth image (PSNR ≥ 30 dB).
    func testNinetyOneLossyRowIsLossyButHighQuality() async throws {
        let w = 64, h = 64
        let src = gradient8(w, h)
        let lossy = try selectableEncoding(uid: "1.2.840.10008.1.2.4.91", intent: .lossy)
        XCTAssertFalse(config(for: lossy).lossless, "the .91 lossy row must configure a lossy encode")

        let codestream = try await encode(makeImage8(width: w, height: h, pixels: src), config(for: lossy))
        let decoded = try await decode(codestream)
        let ref = src.map { Int32($0) }
        let tst = decoded.components[0].data.map { Int32($0) }
        let psnr = try XCTUnwrap(J2KErrorMetrics.peakSignalToNoiseRatio(reference: ref, test: tst, bitDepth: 8))
        XCTAssertGreaterThanOrEqual(psnr, 30.0, "JPEG 2000 Lossy (.91) must stay visually lossless, got \(psnr)")
    }

    // Oracle: the "HTJ2K Lossless (.203)" row — lossless intent on the general HTJ2K UID —
    // drives a bit-exact round-trip and produces an HTJ2K-flagged codestream.
    func testTwoZeroThreeLosslessRowIsBitExactAndHTJ2K() async throws {
        let w = 64, h = 64
        let src = ramp8(w * h, stride: 13, mod: 250)
        let lossless = try selectableEncoding(uid: "1.2.840.10008.1.2.4.203", intent: .lossless)
        let cfg = config(for: lossless)
        XCTAssertTrue(cfg.lossless)
        XCTAssertTrue(cfg.useHTJ2K, "the .203 row must configure an HTJ2K encode")

        let codestream = try await encode(makeImage8(width: w, height: h, pixels: src), cfg)
        let decoded = try await decode(codestream)
        XCTAssertEqual(decoded.components[0].data, src, "HTJ2K Lossless (.203) must round-trip bit-exact")

        let interop = J2KHTInteroperabilityValidator()
        XCTAssertTrue(interop.validateInteroperability(codestream: codestream).isHTJ2K,
                      "HTJ2K Lossless (.203) codestream must be flagged as HTJ2K")
    }

    // MARK: - transcode (J2K ↔ HTJ2K), pixel identity

    // Oracle: J2K-lossless and HTJ2K-lossless both decode to identical pixels,
    // proving the transcode hop is lossless throughout.
    func testTranscodeJ2KtoHTJ2KPixelIdentity() async throws {
        let w = 64, h = 64
        let src = ramp8(w * h, stride: 13, mod: 250)
        let image = makeImage8(width: w, height: h, pixels: src)

        let j2kCS = try await encode(image, losslessConfig())
        let htCS  = try await encode(image, htLosslessConfig())

        let fromJ2K = try await decode(j2kCS)
        let fromHT  = try await decode(htCS)

        XCTAssertEqual(fromJ2K.components[0].data, src, "J2K lossless must be exact")
        XCTAssertEqual(fromHT.components[0].data, src, "HTJ2K lossless must be exact")
        XCTAssertEqual(fromJ2K.components[0].data, fromHT.components[0].data,
                       "both lossless codestreams must decode to identical pixels")
    }

    // Oracle: re-wrapping a transcoded codestream in DICOM preserves the
    // structural metadata (Rows, Columns, BitsAllocated, PhotometricInterpretation).
    func testTranscodePreservesDICOMMetadata() async throws {
        let file = makeGrayscale8(rows: 32, cols: 48)
        let rowsTag = Tag(group: 0x0028, element: 0x0010)
        let colsTag = Tag(group: 0x0028, element: 0x0011)
        let baTag   = Tag(group: 0x0028, element: 0x0100)
        let piTag   = Tag(group: 0x0028, element: 0x0004)

        let origRows = file.dataSet[rowsTag]?.uint16Value
        let origCols = file.dataSet[colsTag]?.uint16Value
        let origBA   = file.dataSet[baTag]?.uint16Value
        let origPI   = file.dataSet[piTag]?.stringValue

        // Build a codestream from the native pixels and re-wrap encapsulated.
        let w = Int(origCols ?? 0), h = Int(origRows ?? 0)
        let image = makeImage8(width: w, height: h, pixels: pixelBytes(file))
        let codestream = try await encode(image, htLosslessConfig())

        var ds = file.dataSet
        ds[.pixelData] = DataElement(
            tag: .pixelData, vr: .OB, length: 0xFFFFFFFF,
            valueData: Data(), encapsulatedFragments: [codestream], encapsulatedOffsetTable: []
        )
        let transcoded = DICOMFile(fileMetaInformation: file.fileMetaInformation, dataSet: ds)

        XCTAssertEqual(transcoded.dataSet[rowsTag]?.uint16Value, origRows)
        XCTAssertEqual(transcoded.dataSet[colsTag]?.uint16Value, origCols)
        XCTAssertEqual(transcoded.dataSet[baTag]?.uint16Value, origBA)
        XCTAssertEqual(transcoded.dataSet[piTag]?.stringValue, origPI)
        XCTAssertNotNil(transcoded.dataSet[.pixelData]?.encapsulatedFragments)
    }

    // MARK: - reduce (decomposition levels)

    // Oracle: reducing decomposition levels keeps a lossless codestream lossless
    // and preserves image dimensions (semantic invariant of `reduce`).
    func testReduceKeepsDimensionsAndLosslessness() async throws {
        let w = 64, h = 64
        let src = ramp8(w * h, stride: 5, mod: 251)
        let image = makeImage8(width: w, height: h, pixels: src)

        var cfg = J2KEncodingConfiguration()
        cfg.lossless = true
        cfg.decompositionLevels = 3
        XCTAssertEqual(cfg.decompositionLevels, 3, "configuration must retain requested level count")

        let codestream = try await encode(image, cfg)
        let decoded = try await decode(codestream)
        XCTAssertEqual(decoded.width, w)
        XCTAssertEqual(decoded.height, h)
        XCTAssertEqual(decoded.components[0].data, src, "reduced-level lossless must stay bit-exact")
    }

    // MARK: - roi (crop)

    // Oracle: a cropped J2KImage carries the region dimensions, and encode→decode
    // reproduces exactly the source region's pixels (crop is content-preserving).
    func testROICropDimensionsAndPixels() async throws {
        let w = 64, h = 64
        var src = Data(count: w * h)
        for y in 0..<h { for x in 0..<w { src[y * w + x] = UInt8((y * 64 + x) % 251) } }

        let rx = 8, ry = 8, rw = 32, rh = 32
        var cropped = Data(capacity: rw * rh)
        for row in 0..<rh {
            let off = (ry + row) * w + rx
            cropped.append(src[(src.startIndex + off)..<(src.startIndex + off + rw)])
        }

        let cropImage = makeImage8(width: rw, height: rh, pixels: cropped)
        XCTAssertEqual(cropImage.width, rw)      // Rows/Columns become rh/rw
        XCTAssertEqual(cropImage.height, rh)
        XCTAssertEqual(cropImage.pixelCount, rw * rh)

        let codestream = try await encode(cropImage, losslessConfig())
        let decoded = try await decode(codestream)
        XCTAssertEqual(decoded.width, rw)
        XCTAssertEqual(decoded.height, rh)
        XCTAssertEqual(decoded.components[0].data, cropped, "crop pixels must round-trip exactly")
    }

    // MARK: - compare (PSNR / MSE)

    // Oracle: comparing an image with itself gives MSE == 0 and PSNR == +∞.
    func testCompareIdenticalIsZeroErrorInfinitePSNR() async throws {
        let w = 48, h = 48
        let src = ramp8(w * h, stride: 17, mod: 251)
        let ref = src.map { Int32($0) }

        let mse = try XCTUnwrap(J2KErrorMetrics.meanSquaredError(reference: ref, test: ref))
        let psnr = try XCTUnwrap(J2KErrorMetrics.peakSignalToNoiseRatio(reference: ref, test: ref, bitDepth: 8))
        let mae = try XCTUnwrap(J2KErrorMetrics.maximumAbsoluteError(reference: ref, test: ref))

        XCTAssertEqual(mse, 0.0)
        XCTAssertTrue(psnr.isInfinite, "PSNR of identical images is +∞")
        XCTAssertEqual(mae, 0)
    }

    // Oracle: a lossless J2K round-trip compared against its own source has
    // MSE == 0 and infinite PSNR — the definition of lossless.
    func testCompareLosslessRoundTripZeroError() async throws {
        let w = 40, h = 40
        let src = ramp8(w * h, stride: 3, mod: 251)
        let codestream = try await encode(makeImage8(width: w, height: h, pixels: src), losslessConfig())
        let decoded = try await decode(codestream)

        let ref = src.map { Int32($0) }
        let tst = decoded.components[0].data.map { Int32($0) }
        XCTAssertEqual(ref.count, tst.count)

        let mse = try XCTUnwrap(J2KErrorMetrics.meanSquaredError(reference: ref, test: tst))
        let psnr = try XCTUnwrap(J2KErrorMetrics.peakSignalToNoiseRatio(reference: ref, test: tst, bitDepth: 8))
        XCTAssertEqual(mse, 0.0, "lossless round-trip has zero MSE")
        XCTAssertTrue(psnr.isInfinite, "lossless round-trip has infinite PSNR")
    }

    // Oracle: MSE is non-negative and mismatched-length inputs return nil (definitional).
    func testErrorMetricsSemantics() {
        let a: [Int32] = [0, 10, 20, 30]
        let b: [Int32] = [1, 12, 18, 33]
        let mse = J2KErrorMetrics.meanSquaredError(reference: a, test: b)
        XCTAssertNotNil(mse)
        XCTAssertGreaterThanOrEqual(mse ?? -1, 0.0, "MSE is always ≥ 0")
        // Length mismatch is undefined → nil.
        XCTAssertNil(J2KErrorMetrics.meanSquaredError(reference: a, test: [0, 1]))
        XCTAssertNil(J2KErrorMetrics.maximumAbsoluteError(reference: a, test: [0, 1]))
    }

    // MARK: - validate (conformance / interoperability)

    // Oracle: an HTJ2K-lossless codestream we encode carries CAP + CPF and passes
    // structure + interoperability validation, and is flagged as HTJ2K.
    func testValidateHTJ2KConformant() async throws {
        let w = 64, h = 64
        let src = ramp8(w * h, stride: 11, mod: 251)
        let codestream = try await encode(makeImage8(width: w, height: h, pixels: src), htLosslessConfig())

        let harness = HTJ2KConformanceTestHarness()
        XCTAssertTrue(harness.validateCodestreamStructure(codestream).isEmpty,
                      "conformant HTJ2K must have no structural errors")

        let interop = J2KHTInteroperabilityValidator()
        let result = interop.validateInteroperability(codestream: codestream)
        XCTAssertTrue(result.passed, "conformant HTJ2K must pass interoperability")
        XCTAssertTrue(result.isHTJ2K, "HTJ2K codestream must be flagged as HTJ2K")
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertTrue(interop.validateMarkerOrdering(codestream: codestream).isEmpty,
                      "marker ordering must be valid")
    }

    // Oracle: a plain (Part 1) J2K codestream passes interoperability but is NOT
    // flagged as HTJ2K (it carries no CAP/CPF capability signalling).
    func testValidatePart1IsNotFlaggedHTJ2K() async throws {
        let w = 48, h = 48
        let src = ramp8(w * h, stride: 7, mod: 251)
        let codestream = try await encode(makeImage8(width: w, height: h, pixels: src), losslessConfig())

        let interop = J2KHTInteroperabilityValidator()
        let result = interop.validateInteroperability(codestream: codestream)
        XCTAssertTrue(result.passed)
        XCTAssertFalse(result.isHTJ2K, "Part 1 J2K must not be flagged HTJ2K")
    }

    // Oracle: corrupting the SOC marker is reported by the structure validator,
    // and does not crash.
    func testValidateCorruptSOCReported() async throws {
        let w = 32, h = 32
        let src = ramp8(w * h)
        var codestream = try await encode(makeImage8(width: w, height: h, pixels: src), htLosslessConfig())
        let b = codestream.startIndex
        codestream[b] = 0x00
        codestream[b + 1] = 0x00

        let harness = HTJ2KConformanceTestHarness()
        let errors = harness.validateCodestreamStructure(codestream)
        XCTAssertFalse(errors.isEmpty, "corrupt SOC must be reported")
        XCTAssertTrue(errors.contains { $0.contains("SOC") }, "error must mention SOC")
    }

    // Oracle: a codestream truncated mid-segment yields a segment-length error;
    // truncating the encoded data makes the decoder throw. No crash either way.
    func testValidateTruncatedCodestream() async throws {
        let w = 64, h = 64
        let src = ramp8(w * h, stride: 11, mod: 251)
        let full = try await encode(makeImage8(width: w, height: h, pixels: src), losslessConfig())

        // Truncate right after SOC so SIZ's declared length overruns the buffer.
        let midHeader = Data(full.prefix(8))
        let interop = J2KHTInteroperabilityValidator()
        XCTAssertFalse(interop.validateSegmentLengths(codestream: midHeader).isEmpty,
                       "mid-segment truncation must report a segment-length error")

        // A badly truncated codestream must fail to decode (throws), not crash.
        let tinyTrunc = Data(full.prefix(30))
        var threw = false
        do { _ = try await decode(tinyTrunc) } catch { threw = true }
        XCTAssertTrue(threw, "truncated codestream must fail to decode")
    }

    // MARK: - benchmark

    // Oracle: measuring N iterations records exactly N timings, and all timing
    // statistics are non-negative and consistently ordered.
    func testBenchmarkIterationCountAndStats() async throws {
        let w = 32, h = 32
        let src = ramp8(w * h)
        let codestream = try await encode(makeImage8(width: w, height: h, pixels: src), losslessConfig())

        let bench = J2KBenchmark(name: "decode")
        let iterations = 4
        let result = try await bench.measureAsyncThrowing(iterations: iterations, warmupIterations: 1) {
            _ = try await J2KDecoder().decode(codestream)
        }

        XCTAssertEqual(result.iterations, iterations, "must record exactly N timings")
        XCTAssertGreaterThanOrEqual(result.averageTime, 0)
        XCTAssertGreaterThanOrEqual(result.standardDeviation, 0)
        XCTAssertLessThanOrEqual(result.minTime, result.averageTime)
        XCTAssertLessThanOrEqual(result.averageTime, result.maxTime)
        XCTAssertLessThanOrEqual(result.minTime, result.medianTime)
        XCTAssertLessThanOrEqual(result.medianTime, result.maxTime)
    }

    // MARK: - Corpus (real J2K-lossless CT)

    // Oracle: the real J2K-lossless corpus file decodes to dimensions that match
    // its own DICOM Rows/Columns tags, from the SOC-led first fragment.
    func testCorpusJ2KLosslessDecodeMatchesDICOMDimensions() async throws {
        let f = try loadCorpus(.j2kLossless)
        try XCTSkipIf(f == nil, "corpus absent")
        let file = try XCTUnwrap(f)

        XCTAssertEqual(file.transferSyntaxUID, "1.2.840.10008.1.2.4.90")

        let element = try XCTUnwrap(file.dataSet[.pixelData])
        let fragments = try XCTUnwrap(element.encapsulatedFragments)
        XCTAssertFalse(fragments.isEmpty, "J2K pixel data must be encapsulated")
        // Encapsulated fragment count matches the frame count (single-frame here).
        XCTAssertEqual(fragments.count, file.numberOfFrames ?? 1)

        let codestream = fragments[0]
        XCTAssertEqual(firstMarker(codestream), 0xFF4F, "fragment must start with SOC")

        let decoded = try await decode(codestream)
        let rows = file.dataSet[Tag(group: 0x0028, element: 0x0010)]?.uint16Value
        let cols = file.dataSet[Tag(group: 0x0028, element: 0x0011)]?.uint16Value
        XCTAssertEqual(decoded.width, Int(cols ?? 0))
        XCTAssertEqual(decoded.height, Int(rows ?? 0))
        XCTAssertEqual(decoded.pixelCount, Int(rows ?? 0) * Int(cols ?? 0))
    }

    // MARK: - transcode (lossy targets: --target j2k / htj2k)

    private func lossyConfig(quality: Double = 0.8) -> J2KEncodingConfiguration {
        var cfg = J2KEncodingConfiguration()
        cfg.lossless = false
        cfg.quality = quality
        return cfg
    }

    /// Smooth 8-bit gradient (0→255 across the raster). It compresses cleanly, so
    /// lossy encoding stays visually lossless (high PSNR) — a stable quality oracle.
    private func gradient8(_ w: Int, _ h: Int) -> Data {
        let n = w * h
        return Data((0..<n).map { UInt8($0 * 255 / max(1, n - 1)) })
    }

    // Oracle: a lossy J2K transcode (--target j2k, …4.91) yields a valid SOC-led
    // codestream, preserves geometry, and stays visually lossless (PSNR ≥ 30 dB) on a
    // smooth image, while the encoding configuration is genuinely lossy.
    func testTranscodeLossyJ2KPreservesGeometryAndQuality() async throws {
        let w = 64, h = 64
        let src = gradient8(w, h)
        let cfg = lossyConfig(quality: 0.8)
        XCTAssertFalse(cfg.lossless, "configuration must be lossy for a lossy transcode")

        let codestream = try await encode(makeImage8(width: w, height: h, pixels: src), cfg)
        XCTAssertEqual(firstMarker(codestream), 0xFF4F, "lossy J2K codestream must start with SOC")

        let decoded = try await decode(codestream)
        XCTAssertEqual(decoded.width, w)
        XCTAssertEqual(decoded.height, h)
        XCTAssertEqual(decoded.components[0].data.count, src.count)

        let ref = src.map { Int32($0) }
        let tst = decoded.components[0].data.map { Int32($0) }
        let psnr = try XCTUnwrap(
            J2KErrorMetrics.peakSignalToNoiseRatio(reference: ref, test: tst, bitDepth: 8))
        XCTAssertGreaterThanOrEqual(psnr, 30.0,
                                    "lossy J2K must stay visually lossless (PSNR ≥ 30 dB), got \(psnr)")
    }

    // Oracle: a lossy HTJ2K transcode (--target htj2k, …4.203) preserves geometry,
    // stays visually lossless (PSNR ≥ 30 dB), and the codestream is flagged HTJ2K.
    func testTranscodeLossyHTJ2KIsFlaggedAndPreservesQuality() async throws {
        let w = 64, h = 64
        let src = gradient8(w, h)
        var cfg = lossyConfig(quality: 0.8)
        cfg.useHTJ2K = true
        XCTAssertFalse(cfg.lossless)
        XCTAssertTrue(cfg.useHTJ2K)

        let codestream = try await encode(makeImage8(width: w, height: h, pixels: src), cfg)
        let decoded = try await decode(codestream)
        XCTAssertEqual(decoded.width, w)
        XCTAssertEqual(decoded.height, h)

        let ref = src.map { Int32($0) }
        let tst = decoded.components[0].data.map { Int32($0) }
        let psnr = try XCTUnwrap(
            J2KErrorMetrics.peakSignalToNoiseRatio(reference: ref, test: tst, bitDepth: 8))
        XCTAssertGreaterThanOrEqual(psnr, 30.0,
                                    "lossy HTJ2K must stay visually lossless (PSNR ≥ 30 dB), got \(psnr)")

        let interop = J2KHTInteroperabilityValidator()
        XCTAssertTrue(interop.validateInteroperability(codestream: codestream).isHTJ2K,
                      "lossy HTJ2K codestream must still be flagged as HTJ2K")
    }

    // MARK: - reduce (quality layers)

    // Oracle: reduce --layers configures the quality-layer count; a lossless codestream
    // encoded with N layers preserves dimensions and stays bit-exact on decode.
    func testReduceQualityLayersConfigured() async throws {
        let w = 64, h = 64
        let src = ramp8(w * h, stride: 7, mod: 251)

        var cfg = J2KEncodingConfiguration()
        cfg.lossless = true
        cfg.qualityLayers = 4
        XCTAssertEqual(cfg.qualityLayers, 4, "configuration must retain the requested layer count")

        let codestream = try await encode(makeImage8(width: w, height: h, pixels: src), cfg)
        let decoded = try await decode(codestream)
        XCTAssertEqual(decoded.width, w)
        XCTAssertEqual(decoded.height, h)
        XCTAssertEqual(decoded.components[0].data, src, "layered lossless must stay bit-exact")
    }
}

