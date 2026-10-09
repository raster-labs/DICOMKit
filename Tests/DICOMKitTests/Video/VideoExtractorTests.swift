//
// VideoExtractorTests.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
@testable import DICOMKit
@testable import DICOMCore

/// The reverse direction: DICOM object back to a playable bit stream.
///
/// The exit criterion is that convert then extract returns the original bytes
/// unchanged, which is only true because encapsulation preserves them.
final class VideoExtractorTests: XCTestCase {

    // MARK: - Helpers

    private func makeBitstream(byteCount: Int) -> Data {
        var data = Data(capacity: byteCount)
        for index in 0..<byteCount {
            data.append(UInt8((index &* 37 &+ 11) % 251))
        }
        return data
    }

    /// Builds a video, writes it as a real file, and reads it back.
    private func roundTripFile(
        bitstream: Data,
        transferSyntax: TransferSyntax = .mpeg4AVCHP41
    ) throws -> DICOMFile {
        let video = try VideoBuilder(
            videoType: .endoscopic,
            rows: 1080,
            columns: 1920,
            numberOfFrames: 300,
            studyInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4.5.6"
        )
        .setFrameRate(30)
        .setPixelData(bitstream)
        .build()

        let file = DICOMFile.create(
            dataSet: video.toDataSet(),
            sopClassUID: video.sopClassUID,
            sopInstanceUID: video.sopInstanceUID,
            transferSyntaxUID: transferSyntax.uid
        )
        return try DICOMFile.read(from: try file.write())
    }

    // MARK: - The round trip

    func test_convertThenExtract_isByteIdentical() throws {
        let original = makeBitstream(byteCount: 4096)
        let file = try roundTripFile(bitstream: original)

        let extracted = try VideoExtractor.extract(from: file)

        XCTAssertEqual(extracted.bitstream, original,
                       "extraction must return exactly what was encapsulated")
        XCTAssertEqual(extracted.fragmentCount, 1)
        XCTAssertEqual(extracted.codec, .h264)
    }

    func test_convertThenExtract_perCodec() throws {
        let cases: [(TransferSyntax, VideoCodec)] = [
            (.mpeg2MainProfile, .mpeg2),
            (.mpeg2MainProfileHighLevel, .mpeg2),
            (.mpeg4AVCHP41, .h264),
            (.mpeg4AVCHP41BD, .h264),
            (.mpeg4AVCHP42For2DVideo, .h264),
            (.mpeg4AVCStereoHP42, .h264),
            (.hevcH265MainProfile, .h265),
            (.hevcH265Main10Profile, .h265),
        ]

        for (syntax, expectedCodec) in cases {
            let original = makeBitstream(byteCount: 2048)
            let file = try roundTripFile(bitstream: original, transferSyntax: syntax)
            let extracted = try VideoExtractor.extract(from: file)

            XCTAssertEqual(extracted.bitstream, original, "round trip failed for \(syntax.uid)")
            XCTAssertEqual(extracted.codec, expectedCodec)
            XCTAssertEqual(extracted.transferSyntax.uid, syntax.uid)
        }
    }

    func test_oddLengthBitstream_extractsWithPadByte() throws {
        // The writer pads an odd fragment to an even length. These bytes have no
        // container framing to measure them against, so the pad cannot be told
        // apart from stream data and comes back with it — callers who need the
        // exact original length must track it themselves. An MP4 payload does
        // carry that framing, and is trimmed; see the box-extent tests below.
        let original = makeBitstream(byteCount: 1023)
        let file = try roundTripFile(bitstream: original)

        let extracted = try VideoExtractor.extract(from: file)
        XCTAssertEqual(extracted.bitstream.count, 1024, "one pad byte, even length")
        XCTAssertEqual(extracted.bitstream.prefix(1023), original,
                       "the original bytes are unchanged ahead of the pad")
    }

    func test_oddLengthMP4_dropsThePadByteUsingTheBoxExtent() throws {
        // Unlike an opaque stream, an MP4 says how long it is: its top-level boxes
        // account for every byte. So when the writer pads an odd-length MP4, the
        // trailing byte falls outside the box structure and can be identified as
        // padding rather than pixel data.
        var mp4 = Data()
        mp4.append(contentsOf: [0x00, 0x00, 0x00, 0x10])            // ftyp, 16 bytes
        mp4.append(contentsOf: Array("ftypisom".utf8))
        mp4.append(contentsOf: Array("isom".utf8))
        mp4.append(contentsOf: [0x00, 0x00, 0x00, 0x0B])            // mdat, 11 bytes
        mp4.append(contentsOf: Array("mdat".utf8))
        mp4.append(contentsOf: [0xAA, 0xBB, 0xCC])
        XCTAssertEqual(mp4.count, 27, "an odd total, so the writer must pad it")

        let file = try roundTripFile(bitstream: mp4)
        let extracted = try VideoExtractor.extract(from: file)

        XCTAssertEqual(extracted.bitstream, mp4,
                       "the pad byte is dropped, recovering the camera's file exactly")
        XCTAssertEqual(extracted.container, .mp4)
    }

    func test_evenLengthMP4_isNeverTrimmed() throws {
        // Nothing was padded here, so every byte is the container's own.
        var mp4 = Data()
        mp4.append(contentsOf: [0x00, 0x00, 0x00, 0x10])
        mp4.append(contentsOf: Array("ftypisom".utf8))
        mp4.append(contentsOf: Array("isom".utf8))
        mp4.append(contentsOf: [0x00, 0x00, 0x00, 0x0C])
        mp4.append(contentsOf: Array("mdat".utf8))
        mp4.append(contentsOf: [0xAA, 0xBB, 0xCC, 0xDD])
        XCTAssertEqual(mp4.count, 28)

        let extracted = try VideoExtractor.extract(from: try roundTripFile(bitstream: mp4))
        XCTAssertEqual(extracted.bitstream, mp4)
    }

    func test_trailingByteInsideTheBoxExtentIsKept() throws {
        // The parity is odd-looking the same way, but here the boxes account for
        // the final byte, so it is stream data. Trimming it would corrupt the
        // pixel data, which is exactly what remuxing exists to avoid.
        var mp4 = Data()
        mp4.append(contentsOf: [0x00, 0x00, 0x00, 0x10])
        mp4.append(contentsOf: Array("ftypisom".utf8))
        mp4.append(contentsOf: Array("isom".utf8))
        mp4.append(contentsOf: [0x00, 0x00, 0x00, 0x0C])
        mp4.append(contentsOf: Array("mdat".utf8))
        mp4.append(contentsOf: [0xAA, 0xBB, 0xCC, 0xDD])

        XCTAssertEqual(VideoExtractor.trimmingEncapsulationPadding(mp4), mp4)
    }

    // MARK: - Container detection and file extension

    func test_extractedMP4_reportsMP4Container() throws {
        // An MP4 payload retains its container through encapsulation, so the
        // extracted bytes are still an MP4.
        var mp4 = Data()
        mp4.append(contentsOf: [0x00, 0x00, 0x00, 0x18])
        mp4.append(contentsOf: Array("ftyp".utf8))
        mp4.append(contentsOf: Array("isom".utf8))
        mp4.append(contentsOf: [0x00, 0x00, 0x02, 0x00])
        mp4.append(contentsOf: Array("isom".utf8))
        mp4.append(contentsOf: Array("mp41".utf8))
        mp4.append(contentsOf: [0x00, 0x00, 0x00, 0x10])
        mp4.append(contentsOf: Array("mdat".utf8))
        mp4.append(Data(repeating: 0xAB, count: 8))

        let file = try roundTripFile(bitstream: mp4)
        let extracted = try VideoExtractor.extract(from: file)

        XCTAssertEqual(extracted.container, .mp4)
        XCTAssertEqual(extracted.suggestedFileExtension, "mp4")
    }

    func test_extractedElementaryStream_suggestsCodecExtension() throws {
        let annexB = Data([0x00, 0x00, 0x00, 0x01, 0x67, 0x64, 0x00, 0x29, 0xAC, 0xB4])

        let h264File = try roundTripFile(bitstream: annexB, transferSyntax: .mpeg4AVCHP41)
        XCTAssertEqual(try VideoExtractor.extract(from: h264File).suggestedFileExtension, "264")

        let hevcFile = try roundTripFile(bitstream: annexB, transferSyntax: .hevcH265MainProfile)
        XCTAssertEqual(try VideoExtractor.extract(from: hevcFile).suggestedFileExtension, "265")

        let mpeg2Stream = Data([0x00, 0x00, 0x01, 0xB3, 0x2D, 0x02, 0x40, 0x33])
        let mpeg2File = try roundTripFile(bitstream: mpeg2Stream, transferSyntax: .mpeg2MainProfile)
        XCTAssertEqual(try VideoExtractor.extract(from: mpeg2File).suggestedFileExtension, "m2v")
    }

    func test_extractedTransportStream_suggestsTSExtension() throws {
        var ts = Data()
        for index in 0..<8 {
            ts.append(0x47)
            ts.append(Data(repeating: UInt8(index), count: 187))
        }
        let file = try roundTripFile(bitstream: ts)
        let extracted = try VideoExtractor.extract(from: file)

        XCTAssertEqual(extracted.container, .mpegTS)
        XCTAssertEqual(extracted.suggestedFileExtension, "ts")
    }

    func test_extractedProgramStreamAndPES_areTheirOwnContainers() throws {
        // PS3.5 2026a 8.2.5 / 8.2.6: an MPEG-2 bit stream may arrive as MPEG-PS or
        // MPEG-PES; both are reported by their own VideoContainer case (D237).
        let pack: [UInt8] = [0x00, 0x00, 0x01, 0xBA, 0x44, 0x00, 0x04, 0x00, 0x04, 0x01, 0x01, 0x89, 0xC3, 0xF8]
        let pes: [UInt8] = [0x00, 0x00, 0x01, 0xE0, 0x00, 0x0B, 0x80, 0x00, 0x00,
                            0x00, 0x00, 0x01, 0xB3, 0x2D, 0x02, 0x40, 0x33]
        let psFile = try roundTripFile(bitstream: Data(pack + pes), transferSyntax: .mpeg2MainProfile)
        let ps = try VideoExtractor.extract(from: psFile)
        XCTAssertEqual(ps.container, .mpegPS)
        XCTAssertEqual(ps.containerDisplayName, "MPEG-2 Program Stream (MPEG-PS)")
        XCTAssertEqual(ps.suggestedFileExtension, "mpg")
        XCTAssertTrue(ps.container.isPermittedByDICOM(for: .mpeg2), "8.2.5: container not constrained")

        let pesFile = try roundTripFile(bitstream: Data(pes), transferSyntax: .mpeg2MainProfile)
        let pesVideo = try VideoExtractor.extract(from: pesFile)
        XCTAssertEqual(pesVideo.container, .mpegPES)
        XCTAssertEqual(pesVideo.containerDisplayName, "MPEG-2 Packetized Elementary Stream (MPEG-PES)")
        XCTAssertEqual(pesVideo.suggestedFileExtension, "mpg")
        XCTAssertTrue(VideoConsole.extractSummary(pesVideo).contains("Container:        MPEG-2 Packetized Elementary Stream (MPEG-PES)"))
    }

    // MARK: - Fragmentable variants

    func test_fragmentableVariant_concatenatesFragmentsInOrder() throws {
        // The ".1" UIDs permit the bit stream to span fragments; the payload is
        // their concatenation.
        let partA = Data(repeating: 0xAA, count: 64)
        let partB = Data(repeating: 0xBB, count: 64)
        let partC = Data(repeating: 0xCC, count: 64)

        var dataSet = DataSet()
        dataSet[.pixelData] = DataElement(
            tag: .pixelData, vr: .OB, length: 0xFFFFFFFF, valueData: Data(),
            encapsulatedFragments: [partA, partB, partC],
            encapsulatedOffsetTable: [0]
        )

        let extracted = try VideoExtractor.extract(
            from: dataSet, transferSyntax: .mpeg4AVCHP41Fragmentable)

        XCTAssertEqual(extracted.bitstream, partA + partB + partC)
        XCTAssertEqual(extracted.fragmentCount, 3)
    }

    func test_nonFragmentableSyntaxWithManyFragments_isRejected() {
        // A non-fragmentable UID requires the whole stream in one fragment.
        // Silently concatenating would hide an object that contradicts itself.
        var dataSet = DataSet()
        dataSet[.pixelData] = DataElement(
            tag: .pixelData, vr: .OB, length: 0xFFFFFFFF, valueData: Data(),
            encapsulatedFragments: [Data(repeating: 0xAA, count: 32),
                                    Data(repeating: 0xBB, count: 32)],
            encapsulatedOffsetTable: [0]
        )

        XCTAssertThrowsError(
            try VideoExtractor.extract(from: dataSet, transferSyntax: .mpeg4AVCHP41)
        ) { error in
            XCTAssertEqual(error as? VideoExtractionError,
                           .unexpectedFragmentCount(count: 2,
                                                    transferSyntax: TransferSyntax.mpeg4AVCHP41.uid))
        }
    }

    // MARK: - Legacy objects

    func test_legacyNativeOBPixelData_isStillExtractable() throws {
        // Files written before the encapsulation fix stored the stream natively.
        let payload = makeBitstream(byteCount: 256)
        var dataSet = DataSet()
        dataSet[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB, data: payload)

        let extracted = try VideoExtractor.extract(
            from: dataSet, transferSyntax: .mpeg4AVCHP41)

        XCTAssertEqual(extracted.bitstream, payload)
        XCTAssertEqual(extracted.fragmentCount, 0, "a native value has no fragments")
    }

    // MARK: - Rejections

    func test_nonVideoTransferSyntax_isRejectedWithPointer() {
        var dataSet = DataSet()
        dataSet[.pixelData] = DataElement.data(
            tag: .pixelData, vr: .OB, data: Data(repeating: 0xFF, count: 16))

        XCTAssertThrowsError(
            try VideoExtractor.extract(from: dataSet, transferSyntax: .jpegBaseline)
        ) { error in
            guard let extractionError = error as? VideoExtractionError else {
                return XCTFail("expected a VideoExtractionError")
            }
            XCTAssertEqual(extractionError,
                           .notAVideoTransferSyntax(uid: TransferSyntax.jpegBaseline.uid))
            XCTAssertTrue(extractionError.message.contains("dicom-image"),
                          "the rejection must point at the right tool")
        }
    }

    func test_missingPixelData_isRejected() {
        let dataSet = DataSet()
        XCTAssertThrowsError(
            try VideoExtractor.extract(from: dataSet, transferSyntax: .mpeg4AVCHP41)
        ) { error in
            XCTAssertEqual(error as? VideoExtractionError, .missingPixelData)
        }
    }

    func test_emptyPixelData_isRejected() {
        var dataSet = DataSet()
        dataSet[.pixelData] = DataElement(
            tag: .pixelData, vr: .OB, length: 0, valueData: Data())

        XCTAssertThrowsError(
            try VideoExtractor.extract(from: dataSet, transferSyntax: .mpeg4AVCHP41)
        ) { error in
            XCTAssertEqual(error as? VideoExtractionError, .emptyPixelData)
        }
    }

    func test_everyExtractionError_hasAMessage() {
        let errors: [VideoExtractionError] = [
            .notAVideoTransferSyntax(uid: "1.2.840.10008.1.2.1"),
            .missingPixelData,
            .emptyPixelData,
            .unexpectedFragmentCount(count: 3, transferSyntax: "1.2.840.10008.1.2.4.102"),
        ]
        for error in errors {
            XCTAssertFalse(error.message.isEmpty)
            XCTAssertTrue(error.message.hasPrefix("error:"))
        }
    }

    // MARK: - Probe agreement

    func test_extractedStream_reProbesToTheSameGeometry() throws {
        // A full cycle: probe an elementary stream, encapsulate it, extract it,
        // and probe again. Both probes must agree, or the pipeline loses fidelity.
        var stream = Data([0x00, 0x00, 0x00, 0x01])
        stream.append(contentsOf: [
            0x67, 0x64, 0x00, 0x29, 0xAC, 0xB4, 0x03, 0xC0, 0x11, 0x3F, 0x2C, 0x20,
            0x00, 0x00, 0x03, 0x00, 0x20, 0x00, 0x00, 0x07, 0x98,
        ])
        stream.append(contentsOf: [0x00, 0x00, 0x00, 0x01, 0x65, 0x88, 0x84, 0x00])

        let before = try VideoProbe.probe(stream)
        let file = try roundTripFile(bitstream: stream)
        let extracted = try VideoExtractor.extract(from: file)

        // The writer may have appended a pad byte; probing tolerates that.
        let after = try VideoProbe.probe(extracted.bitstream)

        XCTAssertEqual(after.stream.width, before.stream.width)
        XCTAssertEqual(after.stream.height, before.stream.height)
        XCTAssertEqual(after.stream.profileIDC, before.stream.profileIDC)
        XCTAssertEqual(after.stream.levelTimesTen, before.stream.levelTimesTen)
    }
}
