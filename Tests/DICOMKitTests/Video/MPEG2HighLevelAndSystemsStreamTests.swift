//
// MPEG2HighLevelAndSystemsStreamTests.swift
// DICOMKit
//
// PS3.5 2026a 8.2.6 (MPEG2 Main Profile / High Level): "Rows (0028,0010) shall be either 720
// or 1080", "Columns (0028,0011) shall be 1280 if Rows is 720, or shall be 1920 if Rows is
// 1080", "The value of MPEG2 aspect_ratio_information shall be 0011" (D226).
// PS3.5 2026a 8.2.5 / 8.2.6: "The container format for the video bit stream is not constrained.
// For example, it may MPEG-2 Transport Stream (MPEG-TS), MPEG-2 Program Stream (MPEG-PS),
// MPEG-2 Elementary Stream (MPEG-ES), MPEG-2 Packetized Elementary Stream (MPEG-PES) … or
// MPEG-4 (MP4) container" (D227).
//

import XCTest
@testable import DICOMKit

final class MPEG2HighLevelAndSystemsStreamTests: XCTestCase {

    /// MP@HL 1920x1080, aspect_ratio_information 0011, 29.97 fps (MPEG2ParserTests vector).
    private static let mpHL1920x1080: [UInt8] = [
        0x00, 0x00, 0x01, 0xB3, 0x78, 0x04, 0x38, 0x34, 0x13, 0x88, 0x23, 0x80,
        0x80, 0x00, 0x00, 0x01, 0xB5, 0x14, 0x4A, 0x00, 0x01, 0x00, 0x00, 0x80,
    ]
    /// MP@ML 720x576, 25 fps.
    private static let mpML720x576: [UInt8] = [
        0x00, 0x00, 0x01, 0xB3, 0x2D, 0x02, 0x40, 0x33, 0x13, 0x88, 0x23, 0x80,
        0x80, 0x00, 0x00, 0x01, 0xB5, 0x14, 0x8A, 0x00, 0x01, 0x00, 0x00, 0x80,
    ]

    private func stream(_ bytes: [UInt8]) throws -> VideoStreamInfo {
        try XCTUnwrap(MPEG2Parser.parseSequenceHeader(Data(bytes))).streamInfo
    }

    private func withAspect(_ bytes: [UInt8], _ aspect: UInt8) -> [UInt8] {
        var b = bytes
        b[7] = (aspect << 4) | (b[7] & 0x0F)
        return b
    }

    // MARK: - D226

    func testHighLevel1080IsAccepted() throws {
        let result = VideoConformanceValidator.validate(
            stream: try stream(Self.mpHL1920x1080), transferSyntax: .mpeg2MainProfileHighLevel, numberOfFrames: 1)
        XCTAssertTrue(result.isConformant, result.report)
    }

    func testMainLevelGeometryIsRefusedUnderHighLevelSyntax() throws {
        for syntax in [TransferSyntax.mpeg2MainProfileHighLevel, .mpeg2MainProfileHighLevelFragmentable] {
            let result = VideoConformanceValidator.validate(
                stream: try stream(Self.mpML720x576), transferSyntax: syntax, numberOfFrames: 1)
            XCTAssertTrue(result.violations.contains(.mpeg2HighLevelGeometryNotPermitted(rows: 576, columns: 720)),
                          "\(syntax.uid): \(result.violations)")
            XCTAssertTrue(result.report.contains("PS3.5 8.2.6"), result.report)
        }
        // Main Level syntax is unaffected
        let main = VideoConformanceValidator.validate(
            stream: try stream(Self.mpML720x576), transferSyntax: .mpeg2MainProfile, numberOfFrames: 1)
        XCTAssertTrue(main.isConformant, main.report)
    }

    func testRowsAndColumnsMustPair() {
        let info = VideoStreamInfo(
            codec: .mpeg2, width: 1920, height: 720, profileIDC: 4, levelTimesTen: 4,
            chromaFormat: .yuv420, bitDepthLuma: 8, bitDepthChroma: 8, frameRate: 25,
            isProgressive: true, mpeg2AspectRatioInformation: 3)
        let result = VideoConformanceValidator.validate(stream: info, transferSyntax: .mpeg2MainProfileHighLevel)
        XCTAssertEqual(result.violations, [.mpeg2HighLevelGeometryNotPermitted(rows: 720, columns: 1920)])
        let hd720 = VideoStreamInfo(
            codec: .mpeg2, width: 1280, height: 720, profileIDC: 4, levelTimesTen: 4,
            chromaFormat: .yuv420, bitDepthLuma: 8, bitDepthChroma: 8, frameRate: 50,
            isProgressive: true, mpeg2AspectRatioInformation: 3)
        XCTAssertTrue(VideoConformanceValidator.validate(stream: hd720, transferSyntax: .mpeg2MainProfileHighLevel).isConformant)
    }

    func testAspectRatioInformationMustBe0011() throws {
        let fourByThree = try stream(withAspect(Self.mpHL1920x1080, 0b0010))
        XCTAssertEqual(fourByThree.mpeg2AspectRatioInformation, 2)
        let result = VideoConformanceValidator.validate(stream: fourByThree, transferSyntax: .mpeg2MainProfileHighLevel)
        XCTAssertEqual(result.violations, [.mpeg2AspectRatioNotPermitted(observed: 2)])
        XCTAssertTrue(result.report.contains("aspect_ratio_information is 0010"), result.report)
        XCTAssertTrue(result.report.contains("0011"), result.report)
    }

    func testSelectionDoesNotOfferHighLevelSyntaxOutsideItsGeometry() {
        // MP@H-14 (level_identification 6) "is not supported by this Transfer Syntax" (8.2.6)
        let h14 = VideoStreamInfo(
            codec: .mpeg2, width: 1440, height: 1080, profileIDC: 4, levelTimesTen: 6,
            chromaFormat: .yuv420, bitDepthLuma: 8, bitDepthChroma: 8, frameRate: 25, isProgressive: false)
        XCTAssertNil(VideoConformanceValidator.selectTransferSyntax(for: h14))
        let hl = VideoStreamInfo(
            codec: .mpeg2, width: 1920, height: 1080, profileIDC: 4, levelTimesTen: 4,
            chromaFormat: .yuv420, bitDepthLuma: 8, bitDepthChroma: 8, frameRate: 25, isProgressive: false)
        XCTAssertEqual(VideoConformanceValidator.selectTransferSyntax(for: hl), .mpeg2MainProfileHighLevel)
    }

    // MARK: - D227

    /// The elementary stream: sequence header + extension, then three pictures.
    private static var elementary: [UInt8] {
        var es = mpHL1920x1080
        for n in 0..<3 { es += [0x00, 0x00, 0x01, 0x00, UInt8(n), 0x0F, 0xFF, 0xF8] }
        return es
    }

    /// An MPEG-2 PES packet: stream_id, '10' marker byte, PTS flag, 5-byte PTS.
    private static func pes(_ streamID: UInt8, _ payload: [UInt8]) -> [UInt8] {
        let header: [UInt8] = [0x81, 0x80, 0x05, 0x21, 0x00, 0x01, 0x00, 0x01]
        let length = header.count + payload.count
        return [0x00, 0x00, 0x01, streamID, UInt8(length >> 8), UInt8(length & 0xFF)] + header + payload
    }

    /// MPEG-2 pack header with pack_stuffing_length 2.
    private static let pack: [UInt8] = [
        0x00, 0x00, 0x01, 0xBA, 0x44, 0x00, 0x04, 0x00, 0x04, 0x01, 0x01, 0x89, 0xC3, 0xFA, 0xFF, 0xFF,
    ]

    /// Program Stream: pack, system header, the video split across two PES packets (inside
    /// a start code), an MPEG audio packet, padding, then MPEG_program_end_code.
    private static var programStream: Data {
        let es = elementary
        let cut = mpHL1920x1080.count + 2   // splits the first picture start code
        var ps = pack
        ps += [0x00, 0x00, 0x01, 0xBB, 0x00, 0x03, 0x80, 0x00, 0x01]
        ps += pes(0xE0, Array(es[..<cut]))
        ps += pes(0xC0, [0xFF, 0xFB, 0x90, 0x00])
        ps += pack
        ps += [0x00, 0x00, 0x01, 0xBE, 0x00, 0x02, 0xFF, 0xFF]
        ps += pes(0xE0, Array(es[cut...]))
        ps += [0x00, 0x00, 0x01, 0xB9]
        return Data(ps)
    }

    func testProgramStreamIsRecognisedAndItsVideoRead() throws {
        let ps = Self.programStream
        XCTAssertEqual(MP4ContainerParser.mpeg2SystemsLayer(ps), .programStream)
        XCTAssertEqual(MP4ContainerParser.detectContainer(ps), .mpegPS, "D237: its own VideoContainer case")
        XCTAssertEqual(MP4ContainerParser.mpeg2VideoElementaryStream(ps), Data(Self.elementary))
        XCTAssertEqual(MP4ContainerParser.mpeg2AudioStreamIDs(ps), [0xC0])

        let probe = try VideoProbe.probe(ps)
        XCTAssertEqual(probe.mpeg2SystemsLayer, .programStream)
        XCTAssertEqual(probe.container, .mpegPS)
        XCTAssertEqual(probe.containerDisplayName, "MPEG-2 Program Stream (MPEG-PS)")
        XCTAssertEqual(VideoContainer.mpegPS.displayName, MPEG2SystemsLayer.programStream.displayName)
        XCTAssertFalse(probe.container.isPermittedByDICOM(for: .h265), "PS3.5 8.2.9: MPEG-TS or MP4 only")
        XCTAssertTrue(VideoConsole.describe(probe, transferSyntax: nil)
            .contains("Container:        MPEG-2 Program Stream (MPEG-PS)"))
        XCTAssertEqual(probe.stream.codec, .mpeg2)
        XCTAssertEqual(probe.stream.width, 1920)
        XCTAssertEqual(probe.frameCount, 3)
        XCTAssertEqual(probe.audioTrackCount, 1)
        XCTAssertEqual(probe.suggestedTransferSyntax, .mpeg2MainProfileHighLevel)
        XCTAssertTrue(probe.container.isPermittedByDICOM(for: .mpeg2))
        XCTAssertTrue(VideoConsole.describe(probe, transferSyntax: nil).contains("MPEG-2 Program Stream"))
    }

    func testPESStreamIsRecognised() throws {
        let es = Self.elementary
        let pesStream = Data(Self.pes(0xE0, Array(es[..<10])) + Self.pes(0xE0, Array(es[10...])))
        XCTAssertEqual(MP4ContainerParser.mpeg2SystemsLayer(pesStream), .packetizedElementaryStream)
        XCTAssertEqual(MP4ContainerParser.detectContainer(pesStream), .mpegPES, "D237: its own VideoContainer case")
        let probe = try VideoProbe.probe(pesStream)
        XCTAssertEqual(probe.mpeg2SystemsLayer, .packetizedElementaryStream)
        XCTAssertEqual(probe.container, .mpegPES)
        XCTAssertEqual(probe.containerDisplayName, "MPEG-2 Packetized Elementary Stream (MPEG-PES)")
        XCTAssertFalse(probe.container.isPermittedByDICOM(for: .h264), "PS3.5 8.2.7: MPEG-TS or MP4 only")
        XCTAssertTrue(VideoConsole.describe(probe, transferSyntax: nil)
            .contains("Container:        MPEG-2 Packetized Elementary Stream (MPEG-PES)"))
        XCTAssertEqual(probe.frameCount, 3)
        XCTAssertEqual(probe.stream.height, 1080)
    }

    func testUnboundedVideoPESPacketRunsToTheNextPacket() {
        // PES_packet_length 0 (ISO/IEC 13818-1 2.4.3.7: video only)
        var bytes = Self.pes(0xE0, Self.elementary)
        bytes[4] = 0; bytes[5] = 0
        bytes += [0x00, 0x00, 0x01, 0xB9]
        XCTAssertEqual(MP4ContainerParser.mpeg2VideoElementaryStream(Data(bytes)), Data(Self.elementary))
    }

    func testElementaryStreamAndTransportStreamAreNotSystemsLayers() {
        XCTAssertNil(MP4ContainerParser.mpeg2SystemsLayer(Data(Self.elementary)))
        var ts = Data(count: 188 * 4)
        for i in 0..<4 { ts[i * 188] = 0x47 }
        XCTAssertNil(MP4ContainerParser.mpeg2SystemsLayer(ts))
        XCTAssertNil(MP4ContainerParser.mpeg2SystemsLayer(Data([0x00, 0x00, 0x01, 0xBA, 0x00, 0x00])),
                     "pack header without the MPEG-1/MPEG-2 marker bits")
    }
}
