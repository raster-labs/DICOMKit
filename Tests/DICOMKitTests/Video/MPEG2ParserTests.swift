//
// MPEG2ParserTests.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
@testable import DICOMKit

/// MPEG-2 sequence header parsing against hand-built vectors.
///
/// Reference: ITU-T H.262 Sections 6.2.2.1, 6.2.2.3, Tables 6-4 and 8-11
final class MPEG2ParserTests: XCTestCase {

    // MARK: - Vectors

    /// Main Profile @ Main Level, 720x576 at 25 fps — the constraint of transfer
    /// syntax 1.2.840.10008.1.2.4.100.
    private static let mpML720x576: [UInt8] = [
        0x00, 0x00, 0x01, 0xB3, 0x2D, 0x02, 0x40, 0x33, 0x13, 0x88, 0x23, 0x80,
        0x80, 0x00, 0x00, 0x01, 0xB5, 0x14, 0x8A, 0x00, 0x01, 0x00, 0x00, 0x80,
    ]

    /// Main Profile @ High Level, 1920x1080 at 29.97 fps — the constraint of
    /// transfer syntax 1.2.840.10008.1.2.4.101.
    private static let mpHL1920x1080: [UInt8] = [
        0x00, 0x00, 0x01, 0xB3, 0x78, 0x04, 0x38, 0x34, 0x13, 0x88, 0x23, 0x80,
        0x80, 0x00, 0x00, 0x01, 0xB5, 0x14, 0x4A, 0x00, 0x01, 0x00, 0x00, 0x80,
    ]

    /// Main Profile @ Main Level, 720x480 at 29.97 fps.
    private static let mpML720x480: [UInt8] = [
        0x00, 0x00, 0x01, 0xB3, 0x2D, 0x01, 0xE0, 0x34, 0x13, 0x88, 0x23, 0x80,
        0x80, 0x00, 0x00, 0x01, 0xB5, 0x14, 0x8A, 0x00, 0x01, 0x00, 0x00, 0x80,
    ]

    /// A sequence header with no sequence extension — an MPEG-1 style stream,
    /// which carries no profile or level at all.
    private static let mpeg1Style352x288: [UInt8] = [
        0x00, 0x00, 0x01, 0xB3, 0x16, 0x01, 0x20, 0x33, 0x13, 0x88, 0x23, 0x80, 0x80,
    ]

    /// 4:2:2 chroma — not DICOM-legal, but must parse so the rejection can name it.
    private static let mp422: [UInt8] = [
        0x00, 0x00, 0x01, 0xB3, 0x2D, 0x02, 0x40, 0x33, 0x13, 0x88, 0x23, 0x80,
        0x80, 0x00, 0x00, 0x01, 0xB5, 0x14, 0x8C, 0x00, 0x01, 0x00, 0x00, 0x80,
    ]

    // MARK: - Geometry

    func test_mainLevel_dimensions() throws {
        let header = try XCTUnwrap(MPEG2Parser.parseSequenceHeader(Data(Self.mpML720x576)))
        XCTAssertEqual(header.width, 720)
        XCTAssertEqual(header.height, 576)
    }

    func test_highLevel_dimensionsUseExtensionBits() throws {
        // 1920 exceeds the 12-bit base field only in combination with the
        // extension bits; 1080 fits, but both paths must agree.
        let header = try XCTUnwrap(MPEG2Parser.parseSequenceHeader(Data(Self.mpHL1920x1080)))
        XCTAssertEqual(header.width, 1920)
        XCTAssertEqual(header.height, 1080)
    }

    func test_ntscMainLevel_dimensions() throws {
        let header = try XCTUnwrap(MPEG2Parser.parseSequenceHeader(Data(Self.mpML720x480)))
        XCTAssertEqual(header.width, 720)
        XCTAssertEqual(header.height, 480)
    }

    func test_mpeg1StyleHeader_dimensions() throws {
        let header = try XCTUnwrap(MPEG2Parser.parseSequenceHeader(Data(Self.mpeg1Style352x288)))
        XCTAssertEqual(header.width, 352)
        XCTAssertEqual(header.height, 288)
    }

    // MARK: - Frame rate table

    func test_frameRateCode_twentyFive() throws {
        let header = try XCTUnwrap(MPEG2Parser.parseSequenceHeader(Data(Self.mpML720x576)))
        XCTAssertEqual(header.frameRate, 25.0, accuracy: 0.0001)
    }

    func test_frameRateCode_twentyNineNineSeven() throws {
        let header = try XCTUnwrap(MPEG2Parser.parseSequenceHeader(Data(Self.mpHL1920x1080)))
        XCTAssertEqual(header.frameRate, 30000.0 / 1001.0, accuracy: 0.0001,
                       "frame_rate_code 4 is 29.97, not 30")
    }

    func test_frameRateTable_matchesSpecification() {
        // ITU-T H.262 Table 6-4. Index 0 is forbidden and 9-15 are reserved.
        XCTAssertNil(MPEG2Parser.frameRateTable[0])
        XCTAssertEqual(MPEG2Parser.frameRateTable[1]!, 24000.0 / 1001.0, accuracy: 0.0001)
        XCTAssertEqual(MPEG2Parser.frameRateTable[2]!, 24.0)
        XCTAssertEqual(MPEG2Parser.frameRateTable[3]!, 25.0)
        XCTAssertEqual(MPEG2Parser.frameRateTable[4]!, 30000.0 / 1001.0, accuracy: 0.0001)
        XCTAssertEqual(MPEG2Parser.frameRateTable[5]!, 30.0)
        XCTAssertEqual(MPEG2Parser.frameRateTable[6]!, 50.0)
        XCTAssertEqual(MPEG2Parser.frameRateTable[7]!, 60000.0 / 1001.0, accuracy: 0.0001)
        XCTAssertEqual(MPEG2Parser.frameRateTable[8]!, 60.0)
        for reserved in 9...15 {
            XCTAssertNil(MPEG2Parser.frameRateTable[reserved])
        }
    }

    // MARK: - Profile and level

    func test_mainProfileMainLevel_isIdentified() throws {
        let header = try XCTUnwrap(MPEG2Parser.parseSequenceHeader(Data(Self.mpML720x576)))
        XCTAssertEqual(header.profileIdentifier, 4, "Main Profile")
        XCTAssertEqual(header.levelIdentifier, 8, "Main Level")
        XCTAssertTrue(header.isMainProfileMainLevel)
        XCTAssertFalse(header.isMainProfileHighLevel)
    }

    func test_mainProfileHighLevel_isIdentified() throws {
        let header = try XCTUnwrap(MPEG2Parser.parseSequenceHeader(Data(Self.mpHL1920x1080)))
        XCTAssertEqual(header.profileIdentifier, 4, "Main Profile")
        XCTAssertEqual(header.levelIdentifier, 4, "High Level")
        XCTAssertTrue(header.isMainProfileHighLevel)
        XCTAssertFalse(header.isMainProfileMainLevel)
    }

    /// D178: PS3.5 2026a 8.2.5 / 8.2.6 name the levels "Main Level" / "High Level".
    func test_levelDescription_namesTheLevel() throws {
        let main = try XCTUnwrap(MPEG2Parser.parseSequenceHeader(Data(Self.mpML720x576))).streamInfo
        let high = try XCTUnwrap(MPEG2Parser.parseSequenceHeader(Data(Self.mpHL1920x1080))).streamInfo
        XCTAssertEqual(main.levelDescription, "Main")
        XCTAssertEqual(high.levelDescription, "High")
        XCTAssertEqual(main.profileName, "Main")
    }

    /// The level ceiling compares level_identification values, where a higher level is a
    /// smaller number: MP@HL is above the Main Level ceiling of MP@ML, not below it.
    func test_levelCeiling_comparesLevelIdentifiers() throws {
        let main = try XCTUnwrap(MPEG2Parser.parseSequenceHeader(Data(Self.mpML720x576))).streamInfo
        let high = try XCTUnwrap(MPEG2Parser.parseSequenceHeader(Data(Self.mpHL1920x1080))).streamInfo
        let highInMainSyntax = VideoConformanceValidator.validate(
            stream: high, transferSyntax: .mpeg2MainProfile, numberOfFrames: 1)
        XCTAssertTrue(highInMainSyntax.violations.contains(.levelExceedsMaximum(
            observed: "High", maximum: "Main", codec: .mpeg2, pictureFitsMaximum: false)),
                      "\(highInMainSyntax.violations)")
        let mainInHighSyntax = VideoConformanceValidator.validate(
            stream: main, transferSyntax: .mpeg2MainProfileHighLevel, numberOfFrames: 1)
        XCTAssertFalse(mainInHighSyntax.violations.contains { if case .levelExceedsMaximum = $0 { return true }; return false },
                       "\(mainInHighSyntax.violations)")
    }

    func test_mpeg1StyleHeader_hasNoProfileOrLevel() throws {
        // Without a sequence extension there is no profile_and_level_indication,
        // so neither DICOM MPEG-2 transfer syntax's constraint can be satisfied.
        let header = try XCTUnwrap(MPEG2Parser.parseSequenceHeader(Data(Self.mpeg1Style352x288)))
        XCTAssertNil(header.profileAndLevel)
        XCTAssertNil(header.profileIdentifier)
        XCTAssertNil(header.levelIdentifier)
        XCTAssertFalse(header.isMainProfileMainLevel)
        XCTAssertFalse(header.isMainProfileHighLevel)
    }

    // MARK: - Chroma format

    func test_chromaFormat_defaultsTo420() throws {
        let header = try XCTUnwrap(MPEG2Parser.parseSequenceHeader(Data(Self.mpML720x576)))
        XCTAssertEqual(header.chromaFormat, 1)
        XCTAssertEqual(header.streamInfo.chromaFormat, .yuv420)
    }

    func test_chromaFormat_422IsReported() throws {
        let header = try XCTUnwrap(MPEG2Parser.parseSequenceHeader(Data(Self.mp422)))
        XCTAssertEqual(header.chromaFormat, 2)
        XCTAssertEqual(header.streamInfo.chromaFormat, .yuv422)
    }

    func test_progressiveFlag_isReported() throws {
        let header = try XCTUnwrap(MPEG2Parser.parseSequenceHeader(Data(Self.mpML720x576)))
        XCTAssertTrue(header.isProgressive)
    }

    // MARK: - Stream info projection

    func test_streamInfo_carriesParsedValues() throws {
        let header = try XCTUnwrap(MPEG2Parser.parseSequenceHeader(Data(Self.mpHL1920x1080)))
        let info = header.streamInfo

        XCTAssertEqual(info.codec, .mpeg2)
        XCTAssertEqual(info.width, 1920)
        XCTAssertEqual(info.height, 1080)
        XCTAssertEqual(info.bitDepthLuma, 8, "MPEG-2 Main Profile is 8-bit")
        XCTAssertEqual(info.chromaFormat, .yuv420)
        XCTAssertEqual(info.profileName, "Main")
        XCTAssertTrue(info.hasSquarePixels, "MPEG-2 codes no sample aspect ratio")
    }

    // MARK: - Start code scanning

    func test_parseSequenceHeader_findsHeaderAfterLeadingBytes() throws {
        var stream = Data([0xFF, 0x00, 0x11, 0x22])
        stream.append(contentsOf: Self.mpML720x576)
        let header = try XCTUnwrap(MPEG2Parser.parseSequenceHeader(stream))
        XCTAssertEqual(header.width, 720)
    }

    func test_parseSequenceHeader_returnsNilWithoutStartCode() {
        XCTAssertNil(MPEG2Parser.parseSequenceHeader(Data([0x00, 0x00, 0x01, 0xB8])))
        XCTAssertNil(MPEG2Parser.parseSequenceHeader(Data()))
        XCTAssertNil(MPEG2Parser.parseSequenceHeader(Data([0xFF, 0xFF])))
    }

    func test_parseSequenceHeader_rejectsForbiddenFrameRateCode() {
        // frame_rate_code 0 is forbidden; a header claiming it is malformed.
        var corrupt = Self.mpML720x576
        corrupt[7] = 0x30   // aspect 3, frame rate code 0
        XCTAssertNil(MPEG2Parser.parseSequenceHeader(Data(corrupt)))
    }

    func test_parseSequenceHeader_rejectsZeroDimensions() {
        var corrupt = Self.mpML720x576
        corrupt[4] = 0x00
        corrupt[5] = 0x00
        corrupt[6] = 0x00
        XCTAssertNil(MPEG2Parser.parseSequenceHeader(Data(corrupt)))
    }

    func test_parseSequenceHeader_truncatedDoesNotCrash() {
        for length in 1..<Self.mpML720x576.count {
            _ = MPEG2Parser.parseSequenceHeader(Data(Self.mpML720x576.prefix(length)))
        }
    }

    func test_parseSequenceHeader_randomBytesDoNotCrash() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            var bytes: [UInt8] = [0x00, 0x00, 0x01, 0xB3]
            for _ in 0..<32 {
                bytes.append(UInt8.random(in: 0...255, using: &generator))
            }
            _ = MPEG2Parser.parseSequenceHeader(Data(bytes))
        }
    }

    // MARK: - Frame counting

    func test_countFrames_countsPictureStartCodes() {
        var stream = Data(Self.mpML720x576)
        for _ in 0..<5 {
            stream.append(contentsOf: [0x00, 0x00, 0x01, 0x00, 0x00, 0x0F, 0xFF, 0xF8])
        }
        XCTAssertEqual(MPEG2Parser.countFrames(stream), 5)
    }

    func test_countFrames_ignoresOtherStartCodes() {
        var stream = Data()
        stream.append(contentsOf: [0x00, 0x00, 0x01, 0xB3])  // sequence header
        stream.append(contentsOf: [0x00, 0x00, 0x01, 0xB8])  // GOP
        stream.append(contentsOf: [0x00, 0x00, 0x01, 0x00])  // picture
        stream.append(contentsOf: [0x00, 0x00, 0x01, 0xB5])  // extension
        stream.append(contentsOf: [0x00, 0x00, 0x01, 0x01])  // slice
        XCTAssertEqual(MPEG2Parser.countFrames(stream), 1)
    }

    func test_countFrames_emptyStreamIsZero() {
        XCTAssertEqual(MPEG2Parser.countFrames(Data()), 0)
        XCTAssertEqual(MPEG2Parser.countFrames(Data([0x00, 0x00])), 0)
    }
}
