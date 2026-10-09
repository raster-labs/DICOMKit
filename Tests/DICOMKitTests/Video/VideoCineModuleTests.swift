//
// VideoCineModuleTests.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
@testable import DICOMKit
@testable import DICOMCore

/// Pins `VideoBuilder` / `Video.toDataSet()` to PS3.3 Table C.7-13 (Cine Module),
/// Table C.7-14 (Multi-frame Module), C.7.6.1.1.5.1 (Lossy Image Compression
/// Method Defined Terms) and the PS3.5 8.2.5–8.2.12 encapsulation and audio rules.
final class VideoCineModuleTests: XCTestCase {

    private func makeBuilder(frames: Int = 4) -> VideoBuilder {
        VideoBuilder(
            videoType: .endoscopic,
            rows: 1080,
            columns: 1920,
            numberOfFrames: frames,
            studyInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4.5.6"
        )
    }

    // MARK: - Frame Time vs Frame Time Vector (Type 1C, Table C.7-13)

    func test_frameTimeVector_pointerPointsAtVector_andFrameTimeIsAbsent() throws {
        let dataSet = try makeBuilder(frames: 4)
            .setFrameTimeVector([0, 40, 40, 40])
            .buildDataSet()
        XCTAssertEqual(dataSet[.frameIncrementPointer]?.attributeTagValue, .frameTimeVector)
        XCTAssertEqual(dataSet.strings(for: .frameTimeVector), ["0", "40", "40", "40"])
        XCTAssertNil(dataSet[.frameTime], "Frame Time is required only when the pointer points at it")
        XCTAssertEqual(dataSet.string(for: .numberOfFrames), "4")
    }

    func test_frameTime_pointerPointsAtFrameTime_whenNoVector() throws {
        let dataSet = try makeBuilder().setFrameRate(25).buildDataSet()
        XCTAssertEqual(dataSet[.frameIncrementPointer]?.attributeTagValue, .frameTime)
        XCTAssertNotNil(dataSet[.frameTime])
        XCTAssertNil(dataSet[.frameTimeVector])
    }

    func test_frameTimeVector_firstIncrementMustBeZero() {
        // C.7.6.5.1.2: "The first Frame always has a time increment of 0."
        XCTAssertThrowsError(try makeBuilder(frames: 3).setFrameTimeVector([40, 40, 40]).build())
    }

    func test_frameTimeVector_mustHaveOneIncrementPerFrame() {
        XCTAssertThrowsError(try makeBuilder(frames: 3).setFrameTimeVector([0, 40]).build())
    }

    // MARK: - Type 3 Cine attributes

    func test_preferredPlaybackSequencing_enumeratedValues() throws {
        let looping = try makeBuilder().setPreferredPlaybackSequencing(0).buildDataSet()
        XCTAssertEqual(looping[.preferredPlaybackSequencing]?.uint16Value, 0)
        let sweeping = try makeBuilder().setPreferredPlaybackSequencing(1).buildDataSet()
        XCTAssertEqual(sweeping[.preferredPlaybackSequencing]?.uint16Value, 1)
        XCTAssertThrowsError(try makeBuilder().setPreferredPlaybackSequencing(2).build())
        XCTAssertNil(try makeBuilder().buildDataSet()[.preferredPlaybackSequencing])
    }

    func test_effectiveDuration_andImageTriggerDelay_writtenAsDS() throws {
        let dataSet = try makeBuilder()
            .setEffectiveDuration(12.5)
            .setImageTriggerDelay(3.25)
            .buildDataSet()
        XCTAssertEqual(dataSet.string(for: Video.effectiveDurationTag), "12.5")
        XCTAssertEqual(dataSet[Video.effectiveDurationTag]?.vr, .DS)
        XCTAssertEqual(dataSet.string(for: Video.imageTriggerDelayTag), "3.25")
        XCTAssertEqual(Video.effectiveDurationTag, Tag(group: 0x0018, element: 0x0072))
        XCTAssertEqual(Video.imageTriggerDelayTag, Tag(group: 0x0018, element: 0x1067))
    }

    // MARK: - Parser round trip (D60)

    /// Every Cine and Multi-frame attribute the builder writes is read back by
    /// `VideoParser`, both from the DataSet and from the written file bytes.
    func test_parser_readsEveryCineAttribute_builderWrites() throws {
        let vector = [0, 33.3, 33.4, 33.3]
        let video = try makeBuilder()
            .setFrameTimeVector(vector)
            .setPreferredPlaybackSequencing(1)
            .setImageTriggerDelay(3.25)
            .setEffectiveDuration(12.5)
            .setCineRate(30)
            .setRecommendedDisplayFrameRate(25)
            .setFrameDelay(1.5)
            .setActualFrameDuration(33)
            .setStartTrim(1)
            .setStopTrim(4)
            .setPixelData(Data(repeating: 0xAB, count: 64))
            .build()
        let dataSet = video.toDataSet()
        let file = DICOMFile.create(
            dataSet: dataSet, sopClassUID: video.sopClassUID,
            sopInstanceUID: video.sopInstanceUID,
            transferSyntaxUID: TransferSyntax.mpeg4AVCHP41.uid)
        let fromFile = try DICOMFile.read(from: try file.write()).dataSet
        for source in [dataSet, fromFile] {
            let parsed = try VideoParser.parse(from: source)
            XCTAssertEqual(parsed.frameTimeVector, vector)
            XCTAssertNil(parsed.frameTime)
            XCTAssertEqual(parsed.preferredPlaybackSequencing, 1)
            XCTAssertEqual(parsed.imageTriggerDelay, 3.25)
            XCTAssertEqual(parsed.effectiveDuration, 12.5)
            XCTAssertEqual(parsed.cineRate, 30)
            XCTAssertEqual(parsed.recommendedDisplayFrameRate, 25)
            XCTAssertEqual(parsed.frameDelay, 1.5)
            XCTAssertEqual(parsed.actualFrameDuration, 33)
            XCTAssertEqual(parsed.startTrim, 1)
            XCTAssertEqual(parsed.stopTrim, 4)
            XCTAssertEqual(parsed.numberOfFrames, 4)
            // Rewriting keeps the Frame Increment Pointer on the vector.
            let rewritten = parsed.toDataSet()
            XCTAssertEqual(rewritten[.frameIncrementPointer]?.attributeTagValue, .frameTimeVector)
            XCTAssertNil(rewritten[.frameTime])
        }
    }

    /// Parse and rewrite yields the same tag set, and the same Cine and
    /// Multi-frame values, as the builder wrote — nothing is dropped.
    func test_parseAndRewrite_keepsTheBuilderTagSet() throws {
        for builder in [
            makeBuilder().setFrameTimeVector([0, 40, 40, 40]).setPreferredPlaybackSequencing(0)
                .setImageTriggerDelay(7).setEffectiveDuration(0.12),
            makeBuilder().setFrameTime(33.366667).setPreferredPlaybackSequencing(1)
                .setImageTriggerDelay(0.5).setEffectiveDuration(2),
        ] {
            let written = try builder.setPixelData(Data([1, 2, 3, 4])).buildDataSet()
            let rewritten = try VideoParser.parse(from: written).toDataSet()
            XCTAssertEqual(Set(rewritten.tags), Set(written.tags))
            for tag in [Tag.numberOfFrames, .frameTime, .frameTimeVector,
                        Video.imageTriggerDelayTag, Video.effectiveDurationTag] {
                XCTAssertEqual(rewritten.strings(for: tag), written.strings(for: tag), "\(tag)")
            }
            XCTAssertEqual(rewritten[.frameIncrementPointer]?.attributeTagValue,
                           written[.frameIncrementPointer]?.attributeTagValue)
            XCTAssertEqual(rewritten[.preferredPlaybackSequencing]?.uint16Value,
                           written[.preferredPlaybackSequencing]?.uint16Value)
        }
    }

    func test_parser_leavesAbsentType3CineAttributesNil() throws {
        let parsed = try VideoParser.parse(from: makeBuilder().buildDataSet())
        XCTAssertNil(parsed.frameTimeVector)
        XCTAssertNil(parsed.preferredPlaybackSequencing)
        XCTAssertNil(parsed.imageTriggerDelay)
        XCTAssertNil(parsed.effectiveDuration)
        XCTAssertNotNil(parsed.frameTime)
    }

    // MARK: - Multiplexed audio (Type 2C, Table C.7-13, C.7.6.5.1.3)

    func test_multiplexedAudioChannels_writtenWithStandardTerms() throws {
        let dataSet = try makeBuilder()
            .setMultiplexedAudioChannels([
                VideoAudioChannel(channelIdentificationCode: 1, mode: .stereo, source: .operatorsNarrative),
                VideoAudioChannel(channelIdentificationCode: 2, mode: .mono, source: .dopplerAudio),
            ])
            .buildDataSet()

        let sequence = try XCTUnwrap(dataSet[Tag(group: 0x003A, element: 0x0300)])
        XCTAssertEqual(sequence.vr, .SQ)
        let items = try XCTUnwrap(sequence.sequenceItems)
        XCTAssertEqual(items.count, 2)

        XCTAssertEqual(items[0].string(for: Tag(group: 0x003A, element: 0x0301)), "1")
        XCTAssertEqual(items[0].string(for: Tag(group: 0x003A, element: 0x0302)), "STEREO")
        XCTAssertEqual(items[1].string(for: Tag(group: 0x003A, element: 0x0301)), "2")
        XCTAssertEqual(items[1].string(for: Tag(group: 0x003A, element: 0x0302)), "MONO")

        let source = try XCTUnwrap(items[0][.channelSourceSequence]?.sequenceItems?.first)
        XCTAssertEqual(source.string(for: .codeValue), "109111")
        XCTAssertEqual(source.string(for: .codingSchemeDesignator), "DCM")
        XCTAssertEqual(source.string(for: .codeMeaning), "Operator's narrative")
    }

    func test_multiplexedAudioChannels_absentWhenNoAudio() throws {
        XCTAssertNil(try makeBuilder().buildDataSet()[Tag(group: 0x003A, element: 0x0300)])
    }

    /// Audio present but not described: the Type 2C condition holds, and Table
    /// C.7-13 allows "Zero or more Items", so the sequence is written empty (D34).
    func test_multiplexedAudioChannels_emptyWhenAudioIsUndescribed() throws {
        var video = try makeBuilder().build()
        video.containsUndescribedMultiplexedAudio = true
        let sequence = try XCTUnwrap(video.toDataSet()[Tag(group: 0x003A, element: 0x0300)])
        XCTAssertEqual(sequence.vr, .SQ)
        XCTAssertEqual(sequence.sequenceItems?.count ?? 0, 0)
    }

    /// Described channels win over the undescribed-audio flag.
    func test_multiplexedAudioChannels_describedItemsKeptWhenFlagAlsoSet() throws {
        var video = try makeBuilder()
            .setMultiplexedAudioChannels([
                VideoAudioChannel(channelIdentificationCode: 1, mode: .stereo, source: .voice),
            ])
            .build()
        video.containsUndescribedMultiplexedAudio = true
        let sequence = try XCTUnwrap(video.toDataSet()[Tag(group: 0x003A, element: 0x0300)])
        XCTAssertEqual(sequence.sequenceItems?.count, 1)
    }

    /// PS3.5 8.2.5-8.2.12 permit audio; the console text must not say otherwise (D34).
    func test_audioConsoleText_doesNotClaimDICOMVideoHasNoAudio() {
        let one = VideoConsole.audioCarriedLine(trackCount: 1)
        XCTAssertEqual(one, """
            warning: input has 1 audio track, kept in the bit stream; DICOMKit does not \
            check it against PS3.5 8.2.5/8.2.12 or describe its channels in (003A,0300).
            """)
        XCTAssertEqual(VideoConsole.audioTrackNote,
                       "(carried in the bit stream; not checked against PS3.5 8.2.5/8.2.12)")
        for text in [one, VideoConsole.audioCarriedLine(trackCount: 2), VideoConsole.audioTrackNote] {
            XCTAssertFalse(text.contains("no audio"), text)
            XCTAssertFalse(text.contains("discard"), text)
        }
    }

    func test_cid3000_codeMeanings() {
        XCTAssertEqual(VideoAudioChannel.Source.voice.codeMeaning, "Voice")
        XCTAssertEqual(VideoAudioChannel.Source.ambientRoomEnvironment.codeValue, "109112")
        XCTAssertEqual(VideoAudioChannel.Source.phonocardiogram.codeValue, "109114")
        XCTAssertEqual(VideoAudioChannel.Source.physiologicalAudioSignal.codeMeaning, "Physiological audio signal")
        // PS3.16 2026a CID 3000: six DCM codes, 109110-109115, in table order.
        XCTAssertEqual(VideoAudioChannel.Source.cid3000.map(\.codeValue),
                       ["109110", "109111", "109112", "109113", "109114", "109115"])
        XCTAssertTrue(VideoAudioChannel.Source.cid3000.allSatisfy { $0.codingSchemeDesignator == "DCM" && $0.isCID3000Member })
    }

    /// CID 3000 is Extensible (D57): any code can be a Channel Source; identity is
    /// designator + value, so a different Code Meaning still matches a member.
    func test_channelSource_isAnyCode() {
        let local = VideoAudioChannel.Source(CodedConcept(
            codeValue: "99999", codingSchemeDesignator: "99LOCAL", codeMeaning: "Local"))
        XCTAssertFalse(local.isCID3000Member)
        XCTAssertNil(local.cid3000Member)
        let voice = VideoAudioChannel.Source(dcmCodeValue: "109110", codeMeaning: "voice")
        XCTAssertEqual(voice, .voice)
        XCTAssertEqual(voice.cid3000Member?.codeMeaning, "Voice")
        XCTAssertTrue(voice.isCID3000Member)
    }

    // MARK: - Lossy Image Compression Method (C.7.6.1.1.5.1)

    func test_lossyImageCompressionMethod_perTransferSyntax() throws {
        let expectations: [(TransferSyntax, String)] = [
            (.mpeg2MainProfile, "ISO_13818_2"),
            (.mpeg2MainProfileHighLevel, "ISO_13818_2"),
            (.mpeg2MainProfileFragmentable, "ISO_13818_2"),
            (.mpeg2MainProfileHighLevelFragmentable, "ISO_13818_2"),
            (.mpeg4AVCHP41, "ISO_14496_10"),
            (.mpeg4AVCHP41BD, "ISO_14496_10"),
            (.mpeg4AVCHP42For2DVideo, "ISO_14496_10"),
            (.mpeg4AVCHP42For3DVideo, "ISO_14496_10"),
            (.mpeg4AVCStereoHP42, "ISO_14496_10"),
            (.mpeg4AVCHP41Fragmentable, "ISO_14496_10"),
            (.mpeg4AVCHP41BDFragmentable, "ISO_14496_10"),
            (.mpeg4AVCHP42For2DVideoFragmentable, "ISO_14496_10"),
            (.mpeg4AVCHP42For3DVideoFragmentable, "ISO_14496_10"),
            (.mpeg4AVCStereoHP42Fragmentable, "ISO_14496_10"),
            (.hevcH265MainProfile, "ISO_23008_2"),
            (.hevcH265Main10Profile, "ISO_23008_2"),
            (.hevcH265MainProfileFragmentable, "ISO_23008_2"),
            (.hevcH265Main10ProfileFragmentable, "ISO_23008_2"),
        ]
        for (syntax, method) in expectations {
            let dataSet = try makeBuilder()
                .setLossyCompression(transferSyntaxUID: syntax.uid, ratio: 20)
                .buildDataSet()
            XCTAssertEqual(dataSet.string(for: .lossyImageCompressionMethod), method, syntax.uid)
            XCTAssertEqual(dataSet.string(for: .lossyImageCompression), "01", syntax.uid)
            XCTAssertEqual(VideoCodec.compressionMethod(forTransferSyntaxUID: syntax.uid), method)
        }
    }

    func test_lossyImageCompressionMethod_nonVideoSyntax_isNotWritten() throws {
        let dataSet = try makeBuilder()
            .setLossyCompression(transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid)
            .buildDataSet()
        XCTAssertNil(dataSet[.lossyImageCompressionMethod])
        XCTAssertNil(VideoCodec.compressionMethod(forTransferSyntaxUID: TransferSyntax.jpegBaseline.uid))
    }

    func test_lossyImageCompressionMethod_rejectsNonStandardTerm() {
        XCTAssertThrowsError(try makeBuilder().setLossyCompression(ratio: 10, method: "H264").build())
        XCTAssertNoThrow(try makeBuilder().setLossyCompression(ratio: 10, method: "ISO_23008_2").build())
    }

    func test_definedTerms_matchC76115_1() {
        XCTAssertEqual(Video.lossyImageCompressionMethodTerms, [
            "ISO_10918_1", "ISO_14495_1", "ISO_15444_1", "ISO_15444_15",
            "ISO_18181_1", "ISO_13818_2", "ISO_14496_10", "ISO_23008_2",
        ])
    }

    // MARK: - Encapsulation (PS3.5 8.2.5 / 8.2.6 / A.4)

    func test_basicOffsetTable_isEmpty_perMPEG2Rule() throws {
        // "The Basic Offset Table shall be empty (present but zero length)"
        let dataSet = try makeBuilder().setPixelData(Data(repeating: 0xAB, count: 512)).buildDataSet()
        let element = try XCTUnwrap(dataSet[.pixelData])
        XCTAssertEqual(element.encapsulatedOffsetTable, [])
        XCTAssertEqual(element.encapsulatedFragmentCount, 1)
    }
}
