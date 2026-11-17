import XCTest
import SwiftJ2K
@testable import DICOMCore

/// Covers the Part-2 multi-component transform decode guard.
///
/// The pinned J2KSwift decoder skips MCT/MCC/MCO marker segments instead of
/// inverting them, so DICOMKit must detect them itself and refuse the frame rather
/// than hand back silently-wrong pixels.
final class J2KCodestreamInspectorTests: XCTestCase {

    // MARK: - Codestream builders

    private static func be16(_ value: UInt16) -> [UInt8] { [UInt8(value >> 8), UInt8(value & 0xFF)] }
    private static func be32(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    /// A marker segment: marker code + 2-byte length (counting itself) + payload.
    private static func segment(_ marker: UInt16, payload: [UInt8]) -> [UInt8] {
        be16(marker) + be16(UInt16(payload.count + 2)) + payload
    }

    /// SIZ content is only read for Csiz (the last two payload bytes) by the wavelet check.
    private static var siz: [UInt8] { segment(0xFF51, payload: [UInt8](repeating: 0x00, count: 36)) }
    private static func siz(components: UInt16) -> [UInt8] {
        segment(0xFF51, payload: [UInt8](repeating: 0x00, count: 34) + be16(components))
    }
    /// COD payload: Scod(1) SGcod(4) SPcod NL xcb ycb cbstyle transformation — all zero
    /// selects the irreversible 9/7 filter (transformation 0).
    private static var cod: [UInt8] { segment(0xFF52, payload: [UInt8](repeating: 0x00, count: 10)) }
    private static func cod(transformation: UInt8) -> [UInt8] {
        segment(0xFF52, payload: [UInt8](repeating: 0x00, count: 9) + [transformation])
    }
    private static func coc(componentIndexWidth: Int, transformation: UInt8) -> [UInt8] {
        segment(0xFF53, payload: [UInt8](repeating: 0x00, count: componentIndexWidth + 5) + [transformation])
    }
    private static var qcd: [UInt8] { segment(0xFF5C, payload: [UInt8](repeating: 0x00, count: 4)) }

    /// SOC + main header + optional extra segments, then a tile-part running to EOC.
    private static func codestream(
        siz: [UInt8] = siz, cod: [UInt8] = cod, mainHeaderExtras: [UInt8] = [], tileHeaderExtras: [UInt8] = []
    ) -> Data {
        var bytes: [UInt8] = be16(0xFF4F)          // SOC
        bytes += siz + cod + qcd
        bytes += mainHeaderExtras
        // SOT: Lsot=10, Isot=0, Psot=0 (runs to EOC), TPsot=0, TNsot=1
        bytes += be16(0xFF90) + be16(10) + be16(0) + be32(0) + [0x00, 0x01]
        bytes += tileHeaderExtras
        bytes += be16(0xFF93)                      // SOD
        bytes += [0xDE, 0xAD, 0xBE, 0xEF]          // packet body
        bytes += be16(0xFFD9)                      // EOC
        return Data(bytes)
    }

    private static var mctSegment: [UInt8] { segment(0xFF74, payload: [0x00, 0x00, 0x00, 0x01]) }
    private static var mccSegment: [UInt8] { segment(0xFF75, payload: [0x00, 0x00, 0x03]) }
    private static var mcoSegment: [UInt8] { segment(0xFF77, payload: [0x00, 0x01]) }

    // MARK: - Negative cases: clean codestreams must still decode

    func test_plainPart1Codestream_hasNoPart2Markers() {
        let data = Self.codestream()
        XCTAssertEqual(J2KCodestreamInspector.part2MultiComponentMarkers(in: data), [])
        XCTAssertFalse(J2KCodestreamInspector.containsPart2MultiComponentTransform(in: data))
        XCTAssertNil(J2KRoutePlanner.unsupportedDecodeReason(frameData: data))
    }

    /// The Part-1-compatible codestreams DICOMKit writes under a `.92`/`.93` UID carry
    /// no MCT markers and must keep opening — the guard is codestream-level, not
    /// UID-level.
    func test_part2UIDWithoutMCTMarkers_isNotRejected() {
        XCTAssertNil(J2KRoutePlanner.unsupportedDecodeReason(frameData: Self.codestream()))
    }

    /// A marker whose code merely sits near the Part-2 range must not trip the guard.
    func test_unrelatedMarker_isNotMistakenForMCT() {
        // 0xFF76 is NLT in ISO/IEC 15444-2 — deliberately not in our reject set, and
        // notably the code J2KSwift's own enum mislabels as `mco`.
        let data = Self.codestream(mainHeaderExtras: Self.segment(0xFF76, payload: [0x00, 0x01]))
        XCTAssertEqual(J2KCodestreamInspector.part2MultiComponentMarkers(in: data), [])
    }

    func test_emptyAndGarbageData_areNotRejected() {
        XCTAssertNil(J2KRoutePlanner.unsupportedDecodeReason(frameData: Data()))
        XCTAssertNil(J2KRoutePlanner.unsupportedDecodeReason(frameData: Data([0x00, 0x01, 0x02, 0x03])))
        // Truncated mid-header: scanning must stop cleanly, not trap.
        let truncated = Self.codestream().prefix(9)
        XCTAssertNil(J2KRoutePlanner.unsupportedDecodeReason(frameData: Data(truncated)))
    }

    // MARK: - Positive cases: real Part-2 MCT must be refused

    func test_mctInMainHeader_isDetected() {
        let data = Self.codestream(mainHeaderExtras: Self.mctSegment)
        XCTAssertEqual(J2KCodestreamInspector.part2MultiComponentMarkers(in: data), [.mct])
        XCTAssertTrue(J2KCodestreamInspector.containsPart2MultiComponentTransform(in: data))
    }

    func test_allThreeMarkers_areReportedInOrder() {
        let data = Self.codestream(mainHeaderExtras: Self.mctSegment + Self.mccSegment + Self.mcoSegment)
        XCTAssertEqual(J2KCodestreamInspector.part2MultiComponentMarkers(in: data), [.mct, .mcc, .mco])
        XCTAssertNil(J2KRoutePlanner.unsupportedDecodeReason(frameData: data))
    }

    /// MCT/MCC/MCO are legal in a tile-part header too, not just the main header.
    func test_mctInTilePartHeader_isDetected() {
        let data = Self.codestream(tileHeaderExtras: Self.mccSegment)
        XCTAssertEqual(J2KCodestreamInspector.part2MultiComponentMarkers(in: data), [.mcc])
    }

    func test_part2DecodeReason_isNilWhenPart2MCTSupported() {
        XCTAssertNil(J2KRoutePlanner.unsupportedDecodeReason(frameData: Self.codestream(mainHeaderExtras: Self.mctSegment)))
    }

    // MARK: - Marker codes

    /// Regression guard: J2KSwift's `J2KMarker` enum assigns MCT/MCC/MCO to
    /// 0xFF75/0xFF77/0xFF76, which contradicts ISO/IEC 15444-2 and the OpenJPEG
    /// reference (`J2K_MS_MCT 0xff74`, `J2K_MS_MCC 0xff75`, `J2K_MS_MCO 0xff77`).
    /// We must follow the standard so third-party codestreams are recognised.
    func test_markerCodes_matchTheStandardNotJ2KSwift() {
        XCTAssertEqual(J2KCodestreamInspector.Part2MultiComponentMarker.mct.rawValue, 0xFF74)
        XCTAssertEqual(J2KCodestreamInspector.Part2MultiComponentMarker.mcc.rawValue, 0xFF75)
        XCTAssertEqual(J2KCodestreamInspector.Part2MultiComponentMarker.mco.rawValue, 0xFF77)
    }

    // MARK: - JP2 container

    func test_jp2WrappedCodestream_isUnwrappedAndScanned() {
        let inner = [UInt8](Self.codestream(mainHeaderExtras: Self.mctSegment))
        var bytes: [UInt8] = []
        // JP2 signature box.
        bytes += Self.be32(12) + Self.be32(0x6A50_2020) + [0x0D, 0x0A, 0x87, 0x0A]
        // jp2c box carrying the codestream.
        bytes += Self.be32(UInt32(inner.count + 8)) + Self.be32(0x6A70_3263) + inner
        XCTAssertEqual(J2KCodestreamInspector.part2MultiComponentMarkers(in: Data(bytes)), [.mct])
    }

    // MARK: - Codec integration

    func test_decodeFrame_roundTripsRealPart2MCT() throws {
        let descriptor = PixelDataDescriptor(
            rows: 16,
            columns: 16,
            numberOfFrames: 1,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            isSigned: false,
            samplesPerPixel: 3,
            photometricInterpretation: .rgb,
            planarConfiguration: 0
        )
        let original = Data((0..<descriptor.bytesPerFrame).map { UInt8(($0 * 19 + 7) & 0xFF) })
        let codec = J2KSwiftCodec(encodingTransferSyntaxUID: TransferSyntax.jpeg2000Part2Lossless.uid)
        let encoded = try codec.encodeFrame(original, descriptor: descriptor, frameIndex: 0, configuration: .lossless)
        XCTAssertTrue(J2KCodestreamInspector.containsPart2MultiComponentTransform(in: encoded))

        let decoded = try codec.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0)
        XCTAssertEqual(decoded, original)
    }

    func test_decodeFrameAtResolution_decodesPart2MCTPreview() async throws {
        let descriptor = PixelDataDescriptor(
            rows: 32,
            columns: 32,
            numberOfFrames: 1,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            isSigned: false,
            samplesPerPixel: 3,
            photometricInterpretation: .rgb,
            planarConfiguration: 0
        )
        let original = Data((0..<descriptor.bytesPerFrame).map { UInt8(($0 * 13 + 3) & 0xFF) })
        let codec = J2KSwiftCodec(encodingTransferSyntaxUID: TransferSyntax.jpeg2000Part2Lossless.uid)
        let encoded = try codec.encodeFrame(original, descriptor: descriptor, frameIndex: 0, configuration: .lossless)
        let preview = try await codec.decodeFrameAtResolution(encoded, descriptor: descriptor, level: 1)
        XCTAssertEqual(preview.rows, 16)
        XCTAssertEqual(preview.columns, 16)
        XCTAssertEqual(preview.data.count, 16 * 16 * 3)
    }
}


// MARK: - Irreversible wavelet detection

extension J2KCodestreamInspectorTests {

    func testReversibleCODIsNotIrreversible() {
        let stream = Self.codestream(siz: Self.siz(components: 1), cod: Self.cod(transformation: 1))
        XCTAssertFalse(J2KCodestreamInspector.usesIrreversibleWavelet(in: stream))
    }

    func testIrreversibleCODInMainHeader() {
        let stream = Self.codestream(siz: Self.siz(components: 1), cod: Self.cod(transformation: 0))
        XCTAssertTrue(J2KCodestreamInspector.usesIrreversibleWavelet(in: stream))
    }

    func testIrreversibleCOCOverridesReversibleCOD() {
        let oneByte = Self.codestream(
            siz: Self.siz(components: 3), cod: Self.cod(transformation: 1),
            mainHeaderExtras: Self.coc(componentIndexWidth: 1, transformation: 0))
        XCTAssertTrue(J2KCodestreamInspector.usesIrreversibleWavelet(in: oneByte))
        let twoByte = Self.codestream(
            siz: Self.siz(components: 300), cod: Self.cod(transformation: 1),
            mainHeaderExtras: Self.coc(componentIndexWidth: 2, transformation: 0))
        XCTAssertTrue(J2KCodestreamInspector.usesIrreversibleWavelet(in: twoByte))
        let reversibleCOC = Self.codestream(
            siz: Self.siz(components: 3), cod: Self.cod(transformation: 1),
            mainHeaderExtras: Self.coc(componentIndexWidth: 1, transformation: 1))
        XCTAssertFalse(J2KCodestreamInspector.usesIrreversibleWavelet(in: reversibleCOC))
    }

    func testIrreversibleCODInTileHeader() {
        let stream = Self.codestream(
            siz: Self.siz(components: 1), cod: Self.cod(transformation: 1),
            tileHeaderExtras: Self.cod(transformation: 0))
        XCTAssertTrue(J2KCodestreamInspector.usesIrreversibleWavelet(in: stream))
    }

    func testIrreversibleInsideJP2Container() {
        let stream = Self.codestream(siz: Self.siz(components: 1), cod: Self.cod(transformation: 0))
        var jp2: [UInt8] = Self.be32(12) + Array("jP  ".utf8) + [0x0D, 0x0A, 0x87, 0x0A]
        jp2 += Self.be32(UInt32(8 + stream.count)) + Array("jp2c".utf8) + [UInt8](stream)
        XCTAssertTrue(J2KCodestreamInspector.usesIrreversibleWavelet(in: Data(jp2)))
    }

    func testMalformedInputIsNotIrreversible() {
        XCTAssertFalse(J2KCodestreamInspector.usesIrreversibleWavelet(in: Data()))
        XCTAssertFalse(J2KCodestreamInspector.usesIrreversibleWavelet(in: Data([0xFF, 0x4F, 0xFF])))
        XCTAssertFalse(J2KCodestreamInspector.usesIrreversibleWavelet(in: Data([0x00, 0x01, 0x02])))
        // A COD too short to hold the transformation byte is not read past its length.
        let short = Self.codestream(siz: Self.siz(components: 1), cod: Self.segment(0xFF52, payload: [0x00, 0x00]))
        XCTAssertFalse(J2KCodestreamInspector.usesIrreversibleWavelet(in: short))
    }

    func testPart2ScanUnchangedByWaveletWalk() {
        let stream = Self.codestream(siz: Self.siz(components: 1), cod: Self.cod(transformation: 1),
                                     mainHeaderExtras: Self.segment(0xFF74, payload: [0x00, 0x00]))
        XCTAssertEqual(J2KCodestreamInspector.part2MultiComponentMarkers(in: stream), [.mct])
        XCTAssertFalse(J2KCodestreamInspector.usesIrreversibleWavelet(in: stream))
    }

    func testMinimumDecompositionLevelsResolvesTileOverrides() {
        // Single-tile stream where Tile 0 overrides main COD NL=2 upward to NL=5:
        // effective minimum NL across active tiles must be 5, not 2.
        let mainCOD2: [UInt8] = Self.segment(0xFF52, payload: [
            0x00,             // Scod
            0x00, 0x00, 0x01, 0x00, // SGcod
            0x02, 0x04, 0x04, 0x00, 0x01 // SPcod: NL=2
        ])
        let tileCOD5: [UInt8] = Self.segment(0xFF52, payload: [
            0x00,
            0x00, 0x00, 0x01, 0x00,
            0x05, 0x04, 0x04, 0x00, 0x01 // SPcod: NL=5
        ])
        let singleTileStream = Self.codestream(
            siz: Self.siz(components: 1),
            cod: mainCOD2,
            tileHeaderExtras: tileCOD5
        )
        XCTAssertEqual(J2KCodestreamInspector.minimumDecompositionLevels(in: singleTileStream), 5)
    }

    func testDecodeFrameAtResolutionHandlesNonZeroOriginCanvas() async throws {
        let descriptor = PixelDataDescriptor(
            rows: 3,
            columns: 3,
            numberOfFrames: 1,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2,
            planarConfiguration: 0
        )
        let codec = SwiftJ2KDICOMCodec(
            encodingTransferSyntaxUID: TransferSyntax.jpeg2000Lossless.uid,
            decodingTransferSyntaxUID: TransferSyntax.jpeg2000Lossless.uid
        )
        // Pure ISO/IEC 15444-1 Annex A lossless 5/3 (NL=1) 8-bit codestream on canvas [1, 4) x [1, 4) (3x3 full,
        // reducing to [ceil(1/2), ceil(4/2)) = [1, 2) -> 1x1 at level 1 rather than ceil(3/2)=2x2), sample value 128.
        let shiftedStream = Data([
            0xFF, 0x4F,
            0xFF, 0x51, 0x00, 0x29, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x04,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x03,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x00, 0x01, 0x07, 0x01, 0x01,
            0xFF, 0x52, 0x00, 0x0C, 0x00,
            0x00, 0x00, 0x01, 0x00,
            0x01, 0x04, 0x04, 0x00, 0x01,
            0xFF, 0x5C, 0x00, 0x07, 0x20, 0x48, 0x48, 0x48, 0x50,
            0xFF, 0x90, 0x00, 0x0A, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x10, 0x00, 0x01,
            0xFF, 0x93, 0x80, 0x80,
            0xFF, 0xD9
        ])

        let preview = try await codec.decodeFrameAtResolution(
            shiftedStream,
            descriptor: descriptor,
            level: 1
        )
        XCTAssertEqual(preview.rows, 1)
        XCTAssertEqual(preview.columns, 1)
        XCTAssertEqual(preview.data, Data([128]))
    }

    func testConformingToHTJ2KRPCLHandlesWideTileIndicesDataSlicesAndShortCOD() {
        // 1. > 255 tile-parts (260 tiles) + non-zero Data slice (`startIndex == 37`):
        //    must emit wide 16-bit Ttlm + 32-bit Ptlm (`Stlm == 0x60`), patch LRCP -> RPCL (2),
        //    and preserve zero RPCL violations.
        let validSiz = Self.segment(0xFF51, payload:
            Self.be16(0x4000) + Self.be32(64) + Self.be32(64) + Self.be32(0) + Self.be32(0) +
            Self.be32(4) + Self.be32(4) + Self.be32(0) + Self.be32(0) + Self.be16(1) + [0x07, 0x01, 0x01]
        )
        let lrcpCod = Self.segment(0xFF52, payload: [
            0x00,                   // Scod = 0 (default precincts)
            0x00, 0x00, 0x01, 0x00, // SGcod: LRCP (0), 1 layer, MCT=0
            0x01, 0x04, 0x04, 0x40, 0x01 // SPcod: NL=1, 64x64, HT, 5/3
        ])
        var multiTileBytes: [UInt8] = Self.be16(0xFF4F) + validSiz + lrcpCod + Self.qcd
        for isot in 0..<260 {
            // Each tile-part: SOT (12 bytes) + SOD (2 bytes) + 1-byte body = 15 bytes (`Psot = 15`)
            multiTileBytes += Self.be16(0xFF90) + Self.be16(10) + Self.be16(UInt16(isot)) + Self.be32(15) + [0x00, 0x01]
            multiTileBytes += Self.be16(0xFF93) + [0x80]
        }
        multiTileBytes += Self.be16(0xFFD9)

        var padded = Data(repeating: 0xAA, count: 37)
        padded.append(contentsOf: multiTileBytes)
        padded.append(contentsOf: [0xBB, 0xCC, 0xDD])
        let slice = padded[37..<(37 + multiTileBytes.count)]
        XCTAssertEqual(slice.startIndex, 37)

        let conformedWide = J2KCodestreamInspector.conformingToHTJ2KRPCL(slice)
        XCTAssertEqual(J2KCodestreamInspector.htj2kRPCLViolations(in: conformedWide, rows: 64, columns: 64), [])
        // Verify TLM segment carries Stlm = 0x60 (16-bit Ttlm | 32-bit Ptlm) and 260 * 6 + 4 = 1564 length:
        let wideBytes = [UInt8](conformedWide)
        let firstHeaderEnd = 2 + validSiz.count + lrcpCod.count + Self.qcd.count
        XCTAssertEqual(wideBytes[firstHeaderEnd], 0xFF)
        XCTAssertEqual(wideBytes[firstHeaderEnd + 1], 0x55)
        XCTAssertEqual(Int(wideBytes[firstHeaderEnd + 2]) << 8 | Int(wideBytes[firstHeaderEnd + 3]), 4 + 260 * 6)
        XCTAssertEqual(wideBytes[firstHeaderEnd + 5], 0x60)

        // 2. Truncated dummy COD (`Lcod = 4 < 12`) preceding valid LRCP COD:
        //    must patch the valid COD's progression byte rather than corrupting the marker after the short COD.
        let dummyShortCod = Self.segment(0xFF52, payload: [0x00, 0x00])
        var shortPlusValidBytes: [UInt8] = Self.be16(0xFF4F) + validSiz + dummyShortCod + lrcpCod + Self.qcd
        shortPlusValidBytes += Self.be16(0xFF90) + Self.be16(10) + Self.be16(0) + Self.be32(15) + [0x00, 0x01]
        shortPlusValidBytes += Self.be16(0xFF93) + [0x80]
        shortPlusValidBytes += Self.be16(0xFFD9)

        let conformedShort = J2KCodestreamInspector.conformingToHTJ2KRPCL(Data(shortPlusValidBytes))
        let outShort = [UInt8](conformedShort)
        let validCodStart = 2 + validSiz.count + dummyShortCod.count
        XCTAssertEqual(outShort[validCodStart], 0xFF)
        XCTAssertEqual(outShort[validCodStart + 1], 0x52, "Valid COD marker code must not be overwritten")
        XCTAssertEqual(outShort[validCodStart + 5], 0x02, "Valid COD progression order must be patched to RPCL (2)")
        XCTAssertEqual(J2KCodestreamInspector.htj2kRPCLViolations(in: conformedShort, rows: 64, columns: 64), [])
    }

    func testConformingToHTJ2KRPCLPreservesPCRLAndCPRLPacketOrderAndValidatesSOT() throws {
        func makeStream(
            width: UInt32,
            height: UInt32,
            components: UInt16,
            progression: UInt8,
            levels: UInt8,
            lsot: UInt16 = 10,
            extraMainHeader: [UInt8] = []
        ) -> Data {
            var compSpecs: [UInt8] = []
            for _ in 0..<components {
                compSpecs += [0x07, 0x01, 0x01]
            }
            let sizSeg = Self.segment(
                0xFF51,
                payload: Self.be16(0x4000)
                    + Self.be32(width) + Self.be32(height)
                    + Self.be32(0) + Self.be32(0)
                    + Self.be32(width) + Self.be32(height)
                    + Self.be32(0) + Self.be32(0)
                    + Self.be16(components) + compSpecs
            )
            let codSeg = Self.segment(0xFF52, payload: [
                0x00,                               // Scod = 0 (default 2^15 precincts)
                progression, 0x00, 0x01, components >= 3 ? 0x01 : 0x00,
                levels, 0x04, 0x04, 0x40, 0x01      // SPcod: NL=levels, 64x64, HT, 5/3
            ])
            var bytes: [UInt8] = Self.be16(0xFF4F) + sizSeg + codSeg + Self.qcd + extraMainHeader
            bytes += Self.be16(0xFF90) + Self.be16(lsot) + Self.be16(0) + Self.be32(15) + [0x00, 0x01]
            bytes += Self.be16(0xFF93) + [0x80]
            bytes += Self.be16(0xFFD9)
            return Data(bytes)
        }

        // 1. Multi-component (Csiz = 3) with NL = 1 on 64x64 grid:
        //    PCRL (3) and CPRL (4) put C outer to R, so patching COD to RPCL (2) would corrupt packet assignment.
        for prog: UInt8 in [3, 4] {
            let stream = makeStream(width: 64, height: 64, components: 3, progression: prog, levels: 1)
            let out = J2KCodestreamInspector.conformingToHTJ2KRPCL(stream)
            let style = try XCTUnwrap(J2KCodestreamInspector.codingStyle(in: out))
            XCTAssertEqual(style.progressionOrder, prog, "Multi-component PCRL/CPRL with NL>=1 must not be relabelled to RPCL")
            XCTAssertTrue(style.hasTLM)
            XCTAssertTrue(
                J2KCodestreamInspector.htj2kRPCLViolations(in: out, rows: 64, columns: 64)
                    .contains("progression order is not RPCL")
            )
        }

        // 2. Single-component (Csiz = 1) with NL = 1 on > 32768 grid (40000 x 64 => P > 1):
        //    PCRL (3) and CPRL (4) put P outer to R and must NOT be relabelled,
        //    whereas LRCP (0) and RLCP (1) have R -> (1) -> P == RPCL and DO relabel safely.
        for prog: UInt8 in [3, 4] {
            let wideGrid = makeStream(width: 40_000, height: 64, components: 1, progression: prog, levels: 1)
            let out = J2KCodestreamInspector.conformingToHTJ2KRPCL(wideGrid)
            XCTAssertEqual(J2KCodestreamInspector.codingStyle(in: out)?.progressionOrder, prog)
        }
        for prog: UInt8 in [0, 1] {
            let wideMono = makeStream(width: 40_000, height: 64, components: 1, progression: prog, levels: 1)
            let outMono = J2KCodestreamInspector.conformingToHTJ2KRPCL(wideMono)
            XCTAssertEqual(J2KCodestreamInspector.codingStyle(in: outMono)?.progressionOrder, 2)

            let wideRGB = makeStream(width: 40_000, height: 64, components: 3, progression: prog, levels: 1)
            let outRGB = J2KCodestreamInspector.conformingToHTJ2KRPCL(wideRGB)
            XCTAssertEqual(J2KCodestreamInspector.codingStyle(in: outRGB)?.progressionOrder, prog)
        }

        // 3. Safe PCRL/CPRL cases: (Csiz == 1 && grid <= 32768) with NL >= 1, and (NL == 0 && grid <= 32768) with Csiz == 3:
        for prog: UInt8 in [3, 4] {
            let safeMono = makeStream(width: 64, height: 64, components: 1, progression: prog, levels: 1)
            XCTAssertEqual(
                J2KCodestreamInspector.codingStyle(in: J2KCodestreamInspector.conformingToHTJ2KRPCL(safeMono))?.progressionOrder,
                2
            )
            let safeNL0 = makeStream(width: 64, height: 64, components: 3, progression: prog, levels: 0)
            XCTAssertEqual(
                J2KCodestreamInspector.codingStyle(in: J2KCodestreamInspector.conformingToHTJ2KRPCL(safeNL0))?.progressionOrder,
                2
            )
        }

        // 4. End-to-end real 3-component RGB HTJ2K codestream encoded with PCRL and CPRL (NL = 2):
        //    conformingToHTJ2KRPCL must preserve progressionOrder so decoding remains bit-exact.
        let rgbWidth = 32
        let rgbHeight = 32
        let limits = ResourceLimits.default
        let imgDesc = try ImageDescriptor.rgbInterleaved(
            width: rgbWidth,
            height: rgbHeight,
            storageBits: 8,
            meaningfulBits: 8,
            signed: false,
            byteOrder: .littleEndian,
            limits: limits
        )
        let imgDest = try ImageDestination.allocate(descriptor: imgDesc, limits: limits)
        let rgbImg = try imgDest.writeSamples { c, x, y in
            (x * (13 + c * 17) + y * (29 - c * 7) + c * 83) & 0xFF
        }
        let origRGB = try rgbImg.storage.withUnsafeBytes { Data($0) }
        let dicomDesc = PixelDataDescriptor(
            rows: rgbHeight,
            columns: rgbWidth,
            numberOfFrames: 1,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            isSigned: false,
            samplesPerPixel: 3,
            photometricInterpretation: .rgb,
            planarConfiguration: 0
        )
        let dicomCodec = SwiftJ2KDICOMCodec(
            encodingTransferSyntaxUID: TransferSyntax.htj2kLossless.uid,
            decodingTransferSyntaxUID: TransferSyntax.htj2kLossless.uid
        )

        for (progOpt, expectedCode): (CodecOptions.ProgressionOrder, UInt8) in [(.pcrl, 3), (.cprl, 4)] {
            let opts = try CodecOptions(
                decompositionLevels: 2,
                blockCoding: .htj2k,
                wavelet: .reversible53,
                colourTransform: .rct,
                progressionOrder: progOpt,
                containerFormat: .codestream
            )
            let encoded = try SwiftJ2K.Encoder(configuration: .init(mode: .lossless, codecOptions: opts))
                .encodeSynchronously(rgbImg, options: .init(resourceLimits: limits))
            let conformed = J2KCodestreamInspector.conformingToHTJ2KRPCL(encoded.data)
            XCTAssertEqual(J2KCodestreamInspector.codingStyle(in: conformed)?.progressionOrder, expectedCode)
            let decoded = try dicomCodec.decodeFrame(conformed, descriptor: dicomDesc, frameIndex: 0)
            XCTAssertEqual(decoded, origRGB)
        }

        // 5. Malformed SOT (`Lsot != 10`), corrupt tile-part header before a hidden COC/POC,
        //    duplicate main-header COD, user-defined precincts (`Scod = 0x01`), multi-tile tile-part
        //    COD/COC/POC overrides on `PCRL`/`CPRL`, and > 4 GiB `Psot == 0` overflow guard:
        let badLsot = makeStream(width: 64, height: 64, components: 1, progression: 0, levels: 1, lsot: 8)
        let badLsotOut = J2KCodestreamInspector.conformingToHTJ2KRPCL(badLsot)
        XCTAssertEqual(badLsotOut, badLsot, "Malformed SOT (Lsot != 10) must leave the entire codestream untouched")
        XCTAssertEqual(J2KCodestreamInspector.codingStyle(in: badLsotOut)?.progressionOrder, 0)
        XCTAssertEqual(J2KCodestreamInspector.codingStyle(in: badLsotOut)?.hasTLM, false)

        // Corrupt sync bytes inside tile-part header preceding a COC + SOD must NOT allow COD patching:
        let hiddenCocPayload = Self.coc(componentIndexWidth: 1, transformation: 1)
        let validMonoSiz = Self.segment(
            0xFF51,
            payload: Self.be16(0x4000)
                + Self.be32(64) + Self.be32(64)
                + Self.be32(0) + Self.be32(0)
                + Self.be32(32) + Self.be32(64)
                + Self.be32(0) + Self.be32(0)
                + Self.be16(1) + [0x07, 0x01, 0x01]
        )
        let pcrlMonoCod = Self.segment(0xFF52, payload: [
            0x00, 0x03, 0x00, 0x01, 0x00,
            0x01, 0x04, 0x04, 0x40, 0x01
        ])
        let corruptTileHdrPsot = UInt32(12 + 2 + hiddenCocPayload.count + 2 + 1)
        let corruptTileHdrStream = Data(
            Self.be16(0xFF4F) + validMonoSiz + pcrlMonoCod + Self.qcd
            + Self.be16(0xFF90) + Self.be16(10) + Self.be16(0) + Self.be32(corruptTileHdrPsot) + [0x00, 0x01]
            + [0x00, 0x00] + hiddenCocPayload
            + Self.be16(0xFF93) + [0x80]
            + Self.be16(0xFFD9)
        )
        XCTAssertEqual(
            J2KCodestreamInspector.conformingToHTJ2KRPCL(corruptTileHdrStream),
            corruptTileHdrStream,
            "Corrupt tile-part header hiding a COC before SOD must not be mutated"
        )

        // Scod bit 0 (`userDefinedPrecincts == true`) on 64x64 Csiz=1 NL=1 PCRL/CPRL must block COD patching:
        for prog: UInt8 in [3, 4] {
            let customPrecinctCod = Self.segment(0xFF52, payload: [
                0x01,                               // Scod = 1 (user-defined precincts)
                prog, 0x00, 0x01, 0x00,
                0x01, 0x04, 0x04, 0x40, 0x01,
                0x44, 0x44                          // PPx=4, PPy=4 (16x16 precincts)
            ])
            let customPrecinctStream = Data(
                Self.be16(0xFF4F) + validMonoSiz + customPrecinctCod + Self.qcd
                + Self.be16(0xFF90) + Self.be16(10) + Self.be16(0) + Self.be32(15) + [0x00, 0x01]
                + Self.be16(0xFF93) + [0x80]
                + Self.be16(0xFFD9)
            )
            let customOut = J2KCodestreamInspector.conformingToHTJ2KRPCL(customPrecinctStream)
            XCTAssertEqual(J2KCodestreamInspector.codingStyle(in: customOut)?.progressionOrder, prog)
            XCTAssertEqual(J2KCodestreamInspector.codingStyle(in: customOut)?.hasTLM, true)

            // Multi-tile stream where Tile 0 uses main-header PCRL/CPRL and Tile 1 overrides via tile-part COD, COC, or POC:
            let tileCodOverride = Self.segment(0xFF52, payload: [
                0x01, prog, 0x00, 0x01, 0x00, 0x01, 0x04, 0x04, 0x40, 0x01, 0x44, 0x44
            ])
            let tileCocOverride = Self.coc(componentIndexWidth: 1, transformation: 1)
            let tilePocOverride = Self.segment(0xFF5F, payload: [0x00, 0x00, 0x00, 0x01, 0x02, 0x01, 0x02])
            for overrideSeg in [tileCodOverride, tileCocOverride, tilePocOverride] {
                let mainCod = Self.segment(0xFF52, payload: [
                    0x00, prog, 0x00, 0x01, 0x00,
                    0x01, 0x04, 0x04, 0x40, 0x01
                ])
                let tile1Psot = UInt32(12 + overrideSeg.count + 2 + 1)
                let twoTileBytes: [UInt8] = Self.be16(0xFF4F) + validMonoSiz + mainCod + Self.qcd
                    + Self.be16(0xFF90) + Self.be16(10) + Self.be16(0) + Self.be32(15) + [0x00, 0x01]
                    + Self.be16(0xFF93) + [0x80]
                    + Self.be16(0xFF90) + Self.be16(10) + Self.be16(1) + Self.be32(tile1Psot) + [0x00, 0x01]
                    + overrideSeg + Self.be16(0xFF93) + [0x80]
                    + Self.be16(0xFFD9)
                let twoTileOut = J2KCodestreamInspector.conformingToHTJ2KRPCL(Data(twoTileBytes))
                XCTAssertEqual(J2KCodestreamInspector.codingStyle(in: twoTileOut)?.progressionOrder, prog)
                XCTAssertEqual(J2KCodestreamInspector.codingStyle(in: twoTileOut)?.hasTLM, true)
            }
        }

        let secondCod = Self.segment(0xFF52, payload: [
            0x00, 0x03, 0x00, 0x01, 0x00, 0x01, 0x04, 0x04, 0x40, 0x01
        ])
        let dupCod = makeStream(width: 64, height: 64, components: 3, progression: 0, levels: 1, extraMainHeader: secondCod)
        XCTAssertEqual(J2KCodestreamInspector.codingStyle(in: dupCod)?.hasCodingStyleOverride, true)
        let dupCodOut = J2KCodestreamInspector.conformingToHTJ2KRPCL(dupCod)
        XCTAssertEqual(J2KCodestreamInspector.codingStyle(in: dupCodOut)?.progressionOrder, 0)

        // Zero-allocation virtual RandomAccessCollection exercising `Psot == 0` -> `end - offset > UInt32.max` at runtime:
        struct VirtualPsotZeroStream: RandomAccessCollection {
            let prefixBytes: [UInt8]
            let totalCount: Int
            var startIndex: Int { 0 }
            var endIndex: Int { totalCount }
            subscript(position: Int) -> UInt8 {
                if position < prefixBytes.count { return prefixBytes[position] }
                if position == totalCount - 2 { return 0xFF }
                if position == totalCount - 1 { return 0xD9 }
                return 0x80
            }
        }
        let psotZeroPrefix: [UInt8] = Self.be16(0xFF4F) + validMonoSiz + pcrlMonoCod + Self.qcd
            + Self.be16(0xFF90) + Self.be16(10) + Self.be16(0) + Self.be32(0) + [0x00, 0x01]
            + Self.be16(0xFF93)
        let validPsotZero = VirtualPsotZeroStream(prefixBytes: psotZeroPrefix, totalCount: psotZeroPrefix.count + 32)
        XCTAssertEqual(J2KCodestreamInspector.tilePartLengths(validPsotZero)?.parts.count, 1)
        let over4GiBPsotZero = VirtualPsotZeroStream(
            prefixBytes: psotZeroPrefix,
            totalCount: psotZeroPrefix.count + Int(UInt32.max) + 64
        )
        XCTAssertNil(
            J2KCodestreamInspector.tilePartLengths(over4GiBPsotZero),
            "Psot == 0 expanding past UInt32.max must be rejected rather than overflowing 32-bit TLM Ptlm"
        )
    }
}
