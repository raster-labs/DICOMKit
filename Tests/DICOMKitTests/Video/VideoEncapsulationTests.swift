//
// VideoEncapsulationTests.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
@testable import DICOMKit
@testable import DICOMCore

/// Tests that video pixel data survives a real write -> read cycle byte-identically.
///
/// The pre-existing `test_video_toDataSet_roundTrip` is in-memory only: it builds a
/// `DataSet` and reads attributes straight back, never serializing through
/// `DICOMWriter` nor re-parsing through `DICOMParser`. That makes the
/// native-vs-encapsulated distinction invisible to it, which is exactly how a
/// blocking encapsulation bug went unnoticed. These tests close that hole.
///
/// Reference: PS3.5 Section A.4 - Encapsulation of Encoded Pixel Data
final class VideoEncapsulationTests: XCTestCase {

    // MARK: - Helpers

    /// A deterministic pseudo-video payload. The content is irrelevant to
    /// encapsulation; only that it survives byte-for-byte matters.
    private func makeBitstream(byteCount: Int) -> Data {
        var data = Data(capacity: byteCount)
        var value: UInt8 = 0
        for index in 0..<byteCount {
            // A non-trivial pattern, so an off-by-one or truncation is visible.
            value = UInt8((index &* 37 &+ 11) % 251)
            data.append(value)
        }
        return data
    }

    private func makeVideo(
        bitstream: Data,
        transferSyntaxUID: String = TransferSyntax.mpeg4AVCHP41.uid
    ) throws -> Video {
        return try VideoBuilder(
            videoType: .endoscopic,
            rows: 1080,
            columns: 1920,
            numberOfFrames: 300,
            studyInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4.5.6"
        )
        .setPatientName("Test^Patient")
        .setPatientID("TEST001")
        .setFrameRate(30)
        .setLossyCompression(codec: .h264)
        .setPixelData(bitstream)
        .build()
    }

    /// Writes a video as a real DICOM file with a video transfer syntax and reads it
    /// back through `DICOMParser`.
    private func roundTripThroughFile(
        _ video: Video,
        transferSyntaxUID: String = TransferSyntax.mpeg4AVCHP41.uid
    ) throws -> DICOMFile {
        let file = DICOMFile.create(
            dataSet: video.toDataSet(),
            sopClassUID: video.sopClassUID,
            sopInstanceUID: video.sopInstanceUID,
            transferSyntaxUID: transferSyntaxUID
        )
        let bytes = try file.write()
        return try DICOMFile.read(from: bytes)
    }

    // MARK: - The test that would have caught the bug

    func test_video_fileRoundTrip_bitstreamIdentical() throws {
        let bitstream = makeBitstream(byteCount: 4096)
        let video = try makeVideo(bitstream: bitstream)

        let readFile = try roundTripThroughFile(video)
        let parsed = try VideoParser.parse(from: readFile.dataSet)

        XCTAssertEqual(parsed.pixelData, bitstream,
                       "Bitstream must survive write -> read byte-identically")
        XCTAssertEqual(parsed.rows, 1080)
        XCTAssertEqual(parsed.columns, 1920)
        XCTAssertEqual(parsed.numberOfFrames, 300)
        XCTAssertEqual(parsed.patientName, "Test^Patient")
    }

    func test_video_fileRoundTrip_bitstreamIdentical_perCodec() throws {
        let cases: [(uid: String, codec: VideoCodec)] = [
            (TransferSyntax.mpeg2MainProfile.uid, .mpeg2),
            (TransferSyntax.mpeg2MainProfileHighLevel.uid, .mpeg2),
            (TransferSyntax.mpeg4AVCHP41.uid, .h264),
            (TransferSyntax.mpeg4AVCHP41BD.uid, .h264),
            (TransferSyntax.mpeg4AVCHP42For2DVideo.uid, .h264),
            (TransferSyntax.hevcH265MainProfile.uid, .h265),
            (TransferSyntax.hevcH265Main10Profile.uid, .h265),
        ]

        for testCase in cases {
            let bitstream = makeBitstream(byteCount: 2048)
            let video = try makeVideo(bitstream: bitstream, transferSyntaxUID: testCase.uid)
            let readFile = try roundTripThroughFile(video, transferSyntaxUID: testCase.uid)
            let parsed = try VideoParser.parse(from: readFile.dataSet)

            XCTAssertEqual(parsed.pixelData, bitstream,
                           "Bitstream must round-trip for \(testCase.uid)")
        }
    }

    // MARK: - Encapsulation structure

    func test_video_pixelData_isEncapsulated() throws {
        let bitstream = makeBitstream(byteCount: 512)
        let video = try makeVideo(bitstream: bitstream)
        let dataSet = video.toDataSet()

        let element = try XCTUnwrap(dataSet[.pixelData])
        XCTAssertTrue(element.isEncapsulated,
                      "Video pixel data must be encapsulated, not a native OB value")
        XCTAssertEqual(element.length, 0xFFFFFFFF,
                       "Encapsulated pixel data must have undefined length")
        XCTAssertEqual(element.vr, .OB)
        XCTAssertTrue(element.valueData.isEmpty,
                      "Encapsulated pixel data carries no native value")
        XCTAssertEqual(element.encapsulatedFragmentCount, 1,
                       "The whole bit stream belongs in exactly one fragment")
    }

    func test_video_pixelData_isEncapsulated_afterFileRoundTrip() throws {
        let bitstream = makeBitstream(byteCount: 512)
        let video = try makeVideo(bitstream: bitstream)

        let readFile = try roundTripThroughFile(video)
        let element = try XCTUnwrap(readFile.dataSet[.pixelData])

        XCTAssertTrue(element.isEncapsulated)
        XCTAssertEqual(element.length, 0xFFFFFFFF)
        XCTAssertEqual(element.encapsulatedFragmentCount, 1)
    }

    func test_video_singleFragment_notSplitPerFrame() throws {
        // MPEG-family streams are inter-coded: frame boundaries are not
        // independently decodable, so splitting per frame yields an undecodable
        // object. 300 frames must still produce exactly one fragment.
        let bitstream = makeBitstream(byteCount: 8192)
        let video = try makeVideo(bitstream: bitstream)

        let readFile = try roundTripThroughFile(video)
        let element = try XCTUnwrap(readFile.dataSet[.pixelData])

        XCTAssertEqual(element.encapsulatedFragmentCount, 1)
        XCTAssertEqual(element.encapsulatedFragments?.first, bitstream)
    }

    func test_fragmentableVideoWritesOneContinuousStream() throws {
        let stream = makeBitstream(byteCount: 128)
        let video = try makeVideo(bitstream: stream)
        var dataSet = video.toDataSet()
        func pixelData(split: Int) -> DataElement {
            DataElement(tag: .pixelData, vr: .OB, length: UInt32.max, valueData: Data(),
                        encapsulatedFragments: [Data(stream.prefix(split)), Data(stream.dropFirst(split))],
                        encapsulatedOffsetTable: [])
        }

        dataSet[.pixelData] = pixelData(split: 64)
        let syntax = TransferSyntax.mpeg4AVCHP41Fragmentable
        let file = DICOMFile.create(dataSet: dataSet, transferSyntaxUID: syntax.uid)
        let parsed = try DICOMFile.read(from: file.write())
        XCTAssertEqual(parsed.dataSet[.pixelData]?.encapsulatedFragmentCount, 2)
        XCTAssertEqual(try VideoExtractor.extract(from: parsed).bitstream, stream)

        // The same stream is too large for this cap, and its two fragments cannot
        // be written with the corresponding non-fragmentable transfer syntax.
        XCTAssertThrowsError(try dataSet.writeChecked(maxEncapsulatedBytes: 64, transferSyntax: syntax))
        XCTAssertThrowsError(try dataSet.writeChecked(transferSyntax: .mpeg4AVCHP41))
        dataSet[.pixelData] = pixelData(split: 63)
        XCTAssertThrowsError(try dataSet.writeChecked(transferSyntax: syntax))
    }

    func test_video_basicOffsetTable_singleEntry() throws {
        let bitstream = makeBitstream(byteCount: 1024)
        let video = try makeVideo(bitstream: bitstream)
        let dataSet = video.toDataSet()

        let element = try XCTUnwrap(dataSet[.pixelData])
        let bot = try XCTUnwrap(element.encapsulatedOffsetTable)

        // A single zero entry, or an empty table. Never fabricated per-frame
        // offsets that cannot be honoured.
        XCTAssertTrue(bot.isEmpty || bot == [0],
                      "Basic Offset Table must be empty or a single 0 entry, got \(bot)")
    }

    func test_video_basicOffsetTable_survivesFileRoundTrip() throws {
        let bitstream = makeBitstream(byteCount: 1024)
        let video = try makeVideo(bitstream: bitstream)

        let readFile = try roundTripThroughFile(video)
        let element = try XCTUnwrap(readFile.dataSet[.pixelData])
        let bot = try XCTUnwrap(element.encapsulatedOffsetTable)

        XCTAssertTrue(bot.isEmpty || bot == [0],
                      "Basic Offset Table must be empty or a single 0 entry, got \(bot)")
    }

    // MARK: - Odd-length payloads

    func test_video_oddLengthBitstream_paddedOnce() throws {
        let bitstream = makeBitstream(byteCount: 1023)
        XCTAssertEqual(bitstream.count % 2, 1, "precondition: payload is odd-length")

        let video = try makeVideo(bitstream: bitstream)

        // The builder must not pre-pad: DICOMWriter pads on serialization, and
        // double-padding would append two bytes to the bit stream.
        let element = try XCTUnwrap(video.toDataSet()[.pixelData])
        XCTAssertEqual(element.encapsulatedFragments?.first?.count, 1023,
                       "Builder must not pad; the writer pads on serialization")

        let readFile = try roundTripThroughFile(video)
        let readElement = try XCTUnwrap(readFile.dataSet[.pixelData])
        let fragment = try XCTUnwrap(readElement.encapsulatedFragments?.first)

        XCTAssertEqual(fragment.count, 1024,
                       "Exactly one pad byte, giving an even-length fragment")
        XCTAssertEqual(fragment.prefix(1023), bitstream,
                       "The original bytes are unchanged ahead of the pad")
        XCTAssertEqual(fragment.last, 0x00, "The pad byte is 0x00")
    }

    func test_video_evenLengthBitstream_notPadded() throws {
        let bitstream = makeBitstream(byteCount: 1024)
        let video = try makeVideo(bitstream: bitstream)

        let readFile = try roundTripThroughFile(video)
        let readElement = try XCTUnwrap(readFile.dataSet[.pixelData])
        let fragment = try XCTUnwrap(readElement.encapsulatedFragments?.first)

        XCTAssertEqual(fragment.count, 1024, "An even payload gains no pad byte")
        XCTAssertEqual(fragment, bitstream)
    }

    // MARK: - Legacy fallback

    func test_parser_nativeOBPixelData_stillReadable() throws {
        // Files written by the pre-fix builder stored the stream as a native OB
        // value. The parser keeps reading those rather than silently returning nil.
        var dataSet = DataSet()
        dataSet.setString("1.2.3.4.5.6.7", for: .sopInstanceUID, vr: .UI)
        dataSet.setString(Video.videoEndoscopicImageStorageUID, for: .sopClassUID, vr: .UI)
        dataSet.setString("1.2.3.4.5", for: .studyInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4.5.6", for: .seriesInstanceUID, vr: .UI)
        dataSet[.rows] = DataElement.uint16(tag: .rows, value: 480)
        dataSet[.columns] = DataElement.uint16(tag: .columns, value: 640)
        dataSet.setString("300", for: .numberOfFrames, vr: .IS)

        let legacyPayload = makeBitstream(byteCount: 256)
        dataSet[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB, data: legacyPayload)

        let parsed = try VideoParser.parse(from: dataSet)
        XCTAssertEqual(parsed.pixelData, legacyPayload)
    }

    func test_parser_missingPixelData_returnsNil() throws {
        var dataSet = DataSet()
        dataSet.setString("1.2.3.4.5.6.7", for: .sopInstanceUID, vr: .UI)
        dataSet.setString(Video.videoEndoscopicImageStorageUID, for: .sopClassUID, vr: .UI)
        dataSet.setString("1.2.3.4.5", for: .studyInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4.5.6", for: .seriesInstanceUID, vr: .UI)
        dataSet[.rows] = DataElement.uint16(tag: .rows, value: 480)
        dataSet[.columns] = DataElement.uint16(tag: .columns, value: 640)
        dataSet.setString("300", for: .numberOfFrames, vr: .IS)

        let parsed = try VideoParser.parse(from: dataSet)
        XCTAssertNil(parsed.pixelData)
    }
}
