//
// VideoStandard2026dConformanceTests.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
@testable import DICOMKit
@testable import DICOMCore

/// Covers the PS3.5 (DICOM 2026d) video rules beyond codec, profile and level
/// number: the level's actual picture-size and throughput limits, HEVC tier,
/// the MPEG-2 picture tables, frame packing and Stereo High, the audio that may
/// travel with the video, fragmentation, and the attributes those imply.
///
/// Reference: PS3.5 Sections 8.2.5 - 8.2.12, A.4
final class VideoStandard2026dConformanceTests: XCTestCase {

    // MARK: - Fixtures

    private func h264(
        width: Int = 1920, height: Int = 1080, level: Int = 41,
        frameRate: Double? = 30, progressive: Bool = true,
        profile: Int = 100, framePacking: Bool? = false
    ) -> VideoStreamInfo {
        VideoStreamInfo(
            codec: .h264, width: width, height: height,
            profileIDC: profile, levelTimesTen: level,
            chromaFormat: .yuv420, bitDepthLuma: 8, bitDepthChroma: 8,
            frameRate: frameRate, isProgressive: progressive,
            hasFramePacking: framePacking
        )
    }

    private func hevc(
        width: Int = 3840, height: Int = 2160, level: Int = 51,
        frameRate: Double? = 60, bitDepth: Int = 8, highTier: Bool = false
    ) -> VideoStreamInfo {
        VideoStreamInfo(
            codec: .h265, width: width, height: height,
            profileIDC: bitDepth == 10 ? 2 : 1, levelTimesTen: level,
            chromaFormat: .yuv420, bitDepthLuma: bitDepth, bitDepthChroma: bitDepth,
            frameRate: frameRate, isProgressive: true, isHighTier: highTier
        )
    }

    private func mpeg2(
        width: Int, height: Int, level: Int, frameRate: Double = 25,
        progressive: Bool = false, aspect: Int? = 3
    ) -> VideoStreamInfo {
        VideoStreamInfo(
            codec: .mpeg2, width: width, height: height,
            profileIDC: 4, levelTimesTen: level,
            chromaFormat: .yuv420, bitDepthLuma: 8, bitDepthChroma: 8,
            frameRate: frameRate, isProgressive: progressive,
            mpeg2AspectRatioInformation: aspect
        )
    }

    private func probe(
        _ stream: VideoStreamInfo,
        container: VideoContainer = .mp4,
        audio: [AudioStreamInfo] = []
    ) -> VideoProbeResult {
        VideoProbeResult(
            container: container, stream: stream, frameCount: 100,
            frameCountSource: .sampleTable, audioTrackCount: audio.count,
            suggestedTransferSyntax: nil, frameRate: stream.frameRate,
            audioTracks: audio
        )
    }

    private func violations(_ stream: VideoStreamInfo, _ syntax: TransferSyntax) -> [VideoConformanceViolation] {
        VideoConformanceValidator.validate(stream: stream, transferSyntax: syntax).violations
    }

    // MARK: - Level limits (H.264 Table A-1, H.265 Table A.8)

    /// A 4K picture signalled as Level 4.1 - which x264 writes, with a warning,
    /// when asked for "-level 4.1" - is not a Level 4.1 stream.
    func test_h264_4KLabelledLevel41_isRejectedOnItsGeometry() {
        let found = violations(h264(width: 3840, height: 2160, level: 41, frameRate: 25), .mpeg4AVCHP41)
        guard case let .levelLimitsExceeded(codec, _, _, _, level, excesses)? = found.first else {
            return XCTFail("expected a level-limit violation, got \(found)")
        }
        XCTAssertEqual(codec, .h264)
        XCTAssertEqual(level, "4.1")
        XCTAssertTrue(excesses.contains(.pictureSize(observed: 32_400, maximum: 8_192, unit: "macroblocks")))
        XCTAssertNotNil(found.first?.remedy?.range(of: "libx265"), "4K should be pointed at HEVC")
    }

    func test_h264_1080p60_needsLevel42() {
        let stream = h264(level: 42, frameRate: 60)
        XCTAssertTrue(violations(stream, .mpeg4AVCHP42For2DVideo).isEmpty)
        XCTAssertEqual(VideoConformanceValidator.selectTransferSyntax(for: stream), .mpeg4AVCHP42For2DVideo)

        // Signalled 4.1, but 8160 MBs x 60 fps exceeds Level 4.1's 245760 MB/s.
        let mislabelled = h264(level: 41, frameRate: 60)
        guard case let .levelLimitsExceeded(_, _, _, _, _, excesses)? =
                violations(mislabelled, .mpeg4AVCHP41).first else {
            return XCTFail("expected a throughput violation")
        }
        XCTAssertTrue(excesses.contains(.throughput(observed: 489_600, maximum: 245_760, unit: "macroblocks")))
    }

    func test_h264_levelTooHighButPictureFits_suggestsResignalling() {
        let found = violations(h264(level: 51, frameRate: 25), .mpeg4AVCHP41)
        XCTAssertEqual(found.first, .levelExceedsMaximum(
            observed: "5.1", maximum: "4.1", codec: .h264, pictureFitsMaximum: true))
        XCTAssertTrue(found.first?.remedy?.contains("The picture fits Level 4.1") == true)
    }

    /// The user-visible case: an iPhone 4K clip at Level 5.1 is reported against
    /// the highest H.264 ceiling, 4.2, and pointed at HEVC.
    func test_closestCandidate_forOversizedH264_isLevel42() {
        let stream = h264(width: 3840, height: 2160, level: 51, frameRate: 25)
        XCTAssertNil(VideoConformanceValidator.selectTransferSyntax(for: stream))
        XCTAssertEqual(VideoConformanceValidator.closestCandidate(for: stream), .mpeg4AVCHP42For2DVideo)
        let found = violations(stream, .mpeg4AVCHP42For2DVideo)
        XCTAssertEqual(found.first, .levelExceedsMaximum(
            observed: "5.1", maximum: "4.2", codec: .h264, pictureFitsMaximum: false))
    }

    func test_hevc_4K60_fitsLevel51_but4K120_doesNot() {
        XCTAssertTrue(violations(hevc(frameRate: 60), .hevcH265MainProfile).isEmpty)
        let found = violations(hevc(frameRate: 120), .hevcH265MainProfile)
        guard case let .levelLimitsExceeded(_, _, _, _, _, excesses)? = found.first else {
            return XCTFail("expected a throughput violation, got \(found)")
        }
        XCTAssertTrue(excesses.contains { if case .throughput = $0 { return true }; return false })
    }

    func test_hevc_8K_exceedsLevel51PictureSize() {
        let found = violations(hevc(width: 7680, height: 4320, level: 51, frameRate: 30), .hevcH265MainProfile)
        guard case let .levelLimitsExceeded(_, _, _, _, _, excesses)? = found.first else {
            return XCTFail("expected a picture-size violation, got \(found)")
        }
        XCTAssertTrue(excesses.contains(.pictureSize(observed: 33_177_600, maximum: 8_912_896, unit: "luma samples")))
    }

    func test_codedSize_isWhatCountsAgainstTheLevel() {
        // 1920x1088 coded (1080 displayed) is 8160 macroblocks: inside 8192.
        let stream = VideoStreamInfo(
            codec: .h264, width: 1920, height: 1080, profileIDC: 100, levelTimesTen: 41,
            chromaFormat: .yuv420, bitDepthLuma: 8, bitDepthChroma: 8,
            frameRate: 30, isProgressive: true, codedWidth: 1920, codedHeight: 1088)
        XCTAssertTrue(VideoLevelLimits.excesses(of: stream, levelTimesTen: 41).isEmpty)
    }

    // MARK: - HEVC tier (PS3.5 8.2.10 - 8.2.11)

    func test_hevcHighTier_isRejected() {
        let found = violations(hevc(highTier: true), .hevcH265MainProfile)
        XCTAssertEqual(found, [.highTierNotPermitted(transferSyntax: "1.2.840.10008.1.2.4.107")])
        XCTAssertNil(VideoConformanceValidator.selectTransferSyntax(for: hevc(highTier: true)))
    }

    func test_hevcMain10_selectsItsOwnSyntax() {
        XCTAssertEqual(VideoConformanceValidator.selectTransferSyntax(for: hevc(bitDepth: 10)),
                       .hevcH265Main10Profile)
    }

    // MARK: - MPEG-2 (PS3.5 8.2.5 - 8.2.6)

    /// MPEG-2 level identifiers descend as levels rise; a High Level stream must
    /// not pass the Main Level ceiling.
    func test_mpeg2HighLevel_isRejectedByMainLevelSyntax() {
        let found = violations(mpeg2(width: 1920, height: 1080, level: 4), .mpeg2MainProfile)
        XCTAssertEqual(found.first, .levelExceedsMaximum(
            observed: "High", maximum: "Main", codec: .mpeg2, pictureFitsMaximum: false))
    }

    func test_mpeg2LowLevel_fitsMainLevel() {
        XCTAssertTrue(violations(mpeg2(width: 352, height: 288, level: 10, aspect: 2), .mpeg2MainProfile).isEmpty)
    }

    func test_mpeg2MainLevel_allowsNonSquarePixels_butNotOversizedPictures() {
        XCTAssertTrue(violations(mpeg2(width: 720, height: 576, level: 8, aspect: 2), .mpeg2MainProfile).isEmpty)
        // 576 rows is the 25 Hz limit; at 29.97 Hz it is 480.
        let found = violations(mpeg2(width: 720, height: 576, level: 8, frameRate: 30000.0 / 1001.0, aspect: 2),
                               .mpeg2MainProfile)
        guard case .mpeg2MainLevelGeometryExceedsMaximum? = found.first else {
            return XCTFail("expected a Table 8-1 violation, got \(found)")
        }
    }

    func test_mpeg2HighLevel_requiresTheHDSizesAnd16by9() {
        XCTAssertTrue(violations(mpeg2(width: 1920, height: 1080, level: 4), .mpeg2MainProfileHighLevel).isEmpty)
        XCTAssertTrue(violations(mpeg2(width: 1280, height: 720, level: 4, frameRate: 50, progressive: true),
                                 .mpeg2MainProfileHighLevel).isEmpty)

        guard case .mpeg2HighLevelGeometryNotPermitted? =
                violations(mpeg2(width: 1440, height: 1080, level: 4), .mpeg2MainProfileHighLevel).first else {
            return XCTFail("1440x1080 is not 1280x720 or 1920x1080")
        }
        XCTAssertEqual(violations(mpeg2(width: 1920, height: 1080, level: 4, aspect: 2), .mpeg2MainProfileHighLevel),
                       [.mpeg2AspectRatioNotPermitted(observed: 2)])
        // 1080p50 is beyond Main Profile / High Level (PS3.5 8.2.6 note).
        guard case .mpeg2FrameRateNotPermitted? =
                violations(mpeg2(width: 1920, height: 1080, level: 4, frameRate: 50, progressive: true),
                           .mpeg2MainProfileHighLevel).first else {
            return XCTFail("1080p50 must be rejected")
        }
    }

    func test_mpeg2Selection_followsThePicture() {
        XCTAssertEqual(VideoConformanceValidator.selectTransferSyntax(for: mpeg2(width: 720, height: 576, level: 8)),
                       .mpeg2MainProfile)
        XCTAssertEqual(VideoConformanceValidator.selectTransferSyntax(for: mpeg2(width: 1920, height: 1080, level: 4)),
                       .mpeg2MainProfileHighLevel)
    }

    func test_mpeg2LevelIsReportedByName() {
        XCTAssertEqual(mpeg2(width: 720, height: 576, level: 8).levelDescription, "Main")
        XCTAssertEqual(mpeg2(width: 1920, height: 1080, level: 4).levelDescription, "High")
    }

    // MARK: - Frame packing and Stereo High (PS3.5 Table 8-8, 8.2.9)

    func test_framePackedStream_selectsFor3DVideo_andIsRefusedFor2D() {
        let packed = h264(level: 42, frameRate: 25, framePacking: true)
        XCTAssertEqual(VideoConformanceValidator.selectTransferSyntax(for: packed), .mpeg4AVCHP42For3DVideo)
        XCTAssertEqual(violations(packed, .mpeg4AVCHP42For2DVideo),
                       [.framePackingNotPermitted(transferSyntax: "1.2.840.10008.1.2.4.104")])
        XCTAssertEqual(violations(h264(level: 42, frameRate: 25), .mpeg4AVCHP42For3DVideo),
                       [.framePackingRequired(transferSyntax: "1.2.840.10008.1.2.4.105")])
    }

    func test_stereoHighStream_selectsStereoHigh() {
        let stereo = h264(level: 42, frameRate: 25, profile: 128)
        XCTAssertEqual(VideoConformanceValidator.selectTransferSyntax(for: stereo), .mpeg4AVCStereoHP42)
    }

    /// A Stereo High stream's base view SPS says High; only the subset SPS
    /// reveals the dependent view, so the probe has to read it.
    func test_subsetSPS_makesTheStreamStereoHigh() throws {
        var subset = Self.spsH264NAL
        subset[0] = 0x6F          // nal_unit_type 15
        subset[1] = 128           // profile_idc Stereo High
        let parsed = try XCTUnwrap(H264Parser.parseSubsetSPS(nalUnit: Data(subset)))
        XCTAssertEqual(parsed.profileIDC, 128)

        let base = try XCTUnwrap(H264Parser.parseSPS(nalUnit: Data(Self.spsH264NAL))).streamInfo
        let refined = VideoProbe.refineH264(base, nalUnits: [Data(Self.spsH264NAL), Data(subset)])
        XCTAssertEqual(refined.profileIDC, 128)
        XCTAssertEqual(refined.profileName, "Stereo High")
    }

    func test_framePackingSEI_isDetected_andACancelIsNot() {
        // sei_message: payloadType 45, payloadSize 2, id ue(0)='1', cancel 0.
        let active = Data([0x06, 0x2D, 0x02, 0x81, 0x80, 0x80])
        let cancelled = Data([0x06, 0x2D, 0x02, 0xC0, 0x00, 0x80])
        let otherSEI = Data([0x06, 0x05, 0x02, 0x81, 0x80, 0x80])
        XCTAssertTrue(H264Parser.containsFramePackingSEI([active]))
        XCTAssertFalse(H264Parser.containsFramePackingSEI([cancelled]))
        XCTAssertFalse(H264Parser.containsFramePackingSEI([otherSEI]))
        XCTAssertFalse(H264Parser.containsFramePackingSEI([Data(Self.spsH264NAL)]))
    }

    // MARK: - Containers and audio (PS3.5 8.2.7, 8.2.12)

    func test_fullValidation_rejectsQuickTimeEvenWhenTheStreamFits() {
        let result = VideoConformanceValidator.validate(
            probe: probe(h264(), container: .quickTime), transferSyntax: .mpeg4AVCHP41)
        XCTAssertEqual(result.violations, [.containerNotPermitted(observed: "QuickTime (MOV)")])
    }

    func test_audioRules_forAVCAndHEVC() {
        func problems(_ audio: AudioStreamInfo, _ container: VideoContainer = .mp4) -> [String] {
            VideoAudioRules.problems(with: audio, videoCodec: .h264, container: container)
        }
        XCTAssertTrue(problems(AudioStreamInfo(format: .aac, sampleRate: 48_000, channels: 2, bitRate: 192_000)).isEmpty)
        XCTAssertTrue(problems(AudioStreamInfo(format: .aac, sampleRate: 48_000, channels: 6)).isEmpty)
        XCTAssertEqual(problems(AudioStreamInfo(format: .aac, sampleRate: 44_100, channels: 2)).count, 1)
        XCTAssertEqual(problems(AudioStreamInfo(format: .aac, sampleRate: 48_000, channels: 1)).count, 1)
        XCTAssertEqual(problems(AudioStreamInfo(format: .aac, sampleRate: 48_000, channels: 2, bitRate: 768_000)).count, 1)

        XCTAssertTrue(problems(AudioStreamInfo(format: .ac3, sampleRate: 48_000, channels: 6), .mpegTS).isEmpty)
        XCTAssertEqual(problems(AudioStreamInfo(format: .ac3, sampleRate: 48_000, channels: 2), .mp4).count, 1,
                       "AC-3 is permitted only in MPEG-TS")
        XCTAssertTrue(problems(AudioStreamInfo(format: .lpcm, sampleRate: 96_000, channels: 2,
                                               bitsPerSample: 24, bitRate: 4_608_000), .mpegTS).isEmpty)
        XCTAssertFalse(problems(AudioStreamInfo(format: .lpcm, sampleRate: 48_000, channels: 2,
                                                bitsPerSample: 16), .mp4).isEmpty)
        XCTAssertTrue(problems(AudioStreamInfo(format: .mp3, sampleRate: 44_100, channels: 2,
                                               bitRate: 320_000, isConstantBitRate: true)).isEmpty)
        XCTAssertEqual(problems(AudioStreamInfo(format: .mp3, sampleRate: 44_100, channels: 2,
                                                isConstantBitRate: false)).count, 1)
        XCTAssertTrue(problems(AudioStreamInfo(format: .mp2, sampleRate: 32_000, channels: 2,
                                               bitRate: 384_000)).isEmpty)
        XCTAssertEqual(problems(AudioStreamInfo(format: .other("Opus"), sampleRate: 48_000, channels: 2)).count, 1)
    }

    func test_audioRules_forMPEG2_permitOnlyCBRMP3() {
        func problems(_ audio: AudioStreamInfo) -> [String] {
            VideoAudioRules.problems(with: audio, videoCodec: .mpeg2, container: .mpegTS)
        }
        XCTAssertTrue(problems(AudioStreamInfo(format: .mp3, sampleRate: 48_000, channels: 1,
                                               isConstantBitRate: true)).isEmpty)
        XCTAssertEqual(problems(AudioStreamInfo(format: .aac, sampleRate: 48_000, channels: 2)).count, 1)
        XCTAssertEqual(problems(AudioStreamInfo(format: .mp2, sampleRate: 48_000, channels: 2)).count, 1)
    }

    func test_audioViolation_remedyCopiesTheVideo() {
        // Audio that breaks PS3.5 8.2.12 is a warning here (`validateAudio` and the audio
        // notices), not a rejection, so `validate(probe:)` stays conformant ...
        let result = VideoConformanceValidator.validate(
            probe: probe(h264(), audio: [AudioStreamInfo(format: .aac, sampleRate: 44_100, channels: 2)]),
            transferSyntax: .mpeg4AVCHP41)
        XCTAssertTrue(result.isConformant)
        // ... while the violation, where a caller raises it, still carries the audio-only remedy.
        let raised = VideoConformanceResult(violations: [.audioNotPermitted(
            track: 1, summary: "AAC, 44.1 kHz, 2 ch",
            problem: "is sampled at 44.1 kHz; AAC must be 48 kHz (PS3.5 8.2.12)", videoCodec: .h264)])
        XCTAssertTrue(raised.report.contains("audio track 1 (AAC, 44.1 kHz, 2 ch)"))
        XCTAssertTrue(raised.report.contains("-c:v copy -c:a aac -ar 48000"))
    }

    // MARK: - Audio header parsing

    func test_mpegAudioHeaders_distinguishLayersAndJudgeCBR() throws {
        // MPEG-1 Layer III, 128 kbps, 44.1 kHz, stereo: 417-byte frames.
        var mp3 = Data()
        for _ in 0..<3 { mp3.append(Data([0xFF, 0xFB, 0x90, 0x00]) + Data(count: 413)) }
        let described = try XCTUnwrap(AudioHeaderParser.describeMPEGAudio(mp3))
        XCTAssertEqual(described.format, .mp3)
        XCTAssertEqual(described.sampleRate, 44_100)
        XCTAssertEqual(described.channels, 2)
        XCTAssertEqual(described.bitRate, 128_000)
        XCTAssertEqual(described.isConstantBitRate, true)

        // MPEG-1 Layer II, 192 kbps, 48 kHz, mono: 576-byte frames.
        var mp2 = Data()
        for _ in 0..<2 { mp2.append(Data([0xFF, 0xFD, 0xA4, 0xC0]) + Data(count: 572)) }
        let layerII = try XCTUnwrap(AudioHeaderParser.describeMPEGAudio(mp2))
        XCTAssertEqual(layerII.format, .mp2)
        XCTAssertEqual(layerII.sampleRate, 48_000)
        XCTAssertEqual(layerII.channels, 1)
    }

    func test_adtsAndAudioSpecificConfig() throws {
        // AAC LC, 48 kHz, stereo; two 13-byte frames.
        let length = 13
        let frame = Data([0xFF, 0xF1, 0x4C, 0x80 | UInt8(length >> 11),
                          UInt8((length >> 3) & 0xFF), UInt8((length & 0x07) << 5) | 0x1F, 0xFC])
            + Data(count: length - 7)
        let adts = try XCTUnwrap(AudioHeaderParser.describeADTS(frame + frame))
        XCTAssertEqual(adts.format, .aac)
        XCTAssertEqual(adts.sampleRate, 48_000)
        XCTAssertEqual(adts.channels, 2)

        let config = AudioHeaderParser.describeAudioSpecificConfig(Data([0x11, 0x90]))
        XCTAssertEqual(config.sampleRate, 48_000)
        XCTAssertEqual(config.channels, 2)
    }

    func test_ac3AndHDMVLPCM() throws {
        // AC-3: 48 kHz, 192 kbps (frmsizecod 20), bsid 8, acmod 2 (stereo), no LFE.
        let ac3 = try XCTUnwrap(AudioHeaderParser.describeAC3(Data([0x0B, 0x77, 0, 0, 0x14, 0x40, 0x40, 0x00])))
        XCTAssertEqual(ac3.sampleRate, 48_000)
        XCTAssertEqual(ac3.bitRate, 192_000)
        XCTAssertEqual(ac3.channels, 2)

        // HDMV LPCM: stereo (assignment 3), 48 kHz (1), 16-bit (1).
        let lpcm = try XCTUnwrap(AudioHeaderParser.describeHDMVLPCM(Data([0x00, 0x00, 0x31, 0x40])))
        XCTAssertEqual(lpcm.format, .lpcm)
        XCTAssertEqual(lpcm.sampleRate, 48_000)
        XCTAssertEqual(lpcm.channels, 2)
        XCTAssertEqual(lpcm.bitsPerSample, 16)
        XCTAssertEqual(lpcm.bitRate, 1_536_000)
    }

    // MARK: - Fragmentation (PS3.5 8.2.5 - 8.2.11, A.4)

    func test_oversizedPayload_needsAFragmentableSyntax() {
        let bytes = 5_000_000_000
        let result = VideoConformanceValidator.validate(
            probe: probe(h264()), transferSyntax: .mpeg4AVCHP41, payloadByteCount: bytes)
        XCTAssertEqual(result.violations, [.payloadExceedsSingleFragment(
            byteCount: bytes, transferSyntax: "1.2.840.10008.1.2.4.102",
            fragmentableAlternative: "1.2.840.10008.1.2.4.102.1")])

        XCTAssertEqual(VideoConformanceValidator.selectTransferSyntax(for: h264(), payloadByteCount: bytes),
                       .mpeg4AVCHP41Fragmentable)
        XCTAssertEqual(VideoConformanceValidator.selectTransferSyntax(for: hevc(), payloadByteCount: bytes),
                       .hevcH265MainProfile, "HEVC is fragmentable already")
        XCTAssertTrue(VideoConformanceValidator.validate(
            probe: probe(hevc()), transferSyntax: .hevcH265MainProfile, payloadByteCount: bytes).isConformant)
    }

    func test_fragments_splitOnlyWhenTheyMust_atEvenBoundaries() {
        let payload = Data((0..<25).map { UInt8($0) })
        XCTAssertEqual(Video.fragments(of: payload, maximumLength: 64), [payload])
        let split = Video.fragments(of: payload, maximumLength: 11)
        XCTAssertEqual(split.map(\.count), [10, 10, 5])
        XCTAssertEqual(split.reduce(Data(), +), payload)
    }

    // MARK: - Data set attributes

    private func builtDataSet(_ syntax: TransferSyntax) throws -> DataSet {
        let builder = VideoBuilder(
            videoType: .endoscopic, rows: 1080, columns: 1920, numberOfFrames: 10,
            studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4")
        builder.setPixelData(Data(repeating: 0xAB, count: 64))
        builder.setTransferSyntax(syntax)
        return try builder.buildDataSet()
    }

    func test_stereoPairsPresent_isWrittenFor3DAndStereoHighOnly() throws {
        XCTAssertEqual(try builtDataSet(.mpeg4AVCHP42For3DVideo).string(for: .stereoPairsPresent), "YES")
        XCTAssertEqual(try builtDataSet(.mpeg4AVCStereoHP42Fragmentable).string(for: .stereoPairsPresent), "YES")
        XCTAssertNil(try builtDataSet(.mpeg4AVCHP42For2DVideo)[.stereoPairsPresent])
        XCTAssertNil(try builtDataSet(.hevcH265MainProfile)[.stereoPairsPresent])
    }

    func test_basicOffsetTable_isEmpty() throws {
        let pixelData = try XCTUnwrap(try builtDataSet(.mpeg2MainProfile)[.pixelData])
        XCTAssertEqual(pixelData.encapsulatedOffsetTable, [])
        XCTAssertEqual(pixelData.encapsulatedFragments?.count, 1)
    }

    // MARK: - Container details

    func test_lengthPrefixedSamples_splitIntoNALUnits() {
        let sample = Data([0, 0, 0, 2, 0x65, 0x88, 0, 0, 0, 3, 0x06, 0x2D, 0x00])
        XCTAssertEqual(NALUnit.splitLengthPrefixed(sample, lengthSize: 4),
                       [Data([0x65, 0x88]), Data([0x06, 0x2D, 0x00])])
        XCTAssertEqual(NALUnit.splitLengthPrefixed(sample, lengthSize: 3), [], "only 1, 2 or 4 are legal")
    }

    func test_trackHeaderRotation_isRead() {
        func trak(a: Int32, b: Int32, c: Int32, d: Int32) -> Data {
            var payload = Data(count: 40)                 // version 0 fields
            for value in [a, b, 0, c, d, 0, 0, 0, 0x4000_0000] as [Int32] {
                payload.append(contentsOf: withUnsafeBytes(of: value.bigEndian, Array.init))
            }
            payload.append(Data(count: 8))                // width, height
            var tkhd = Data()
            tkhd.append(contentsOf: withUnsafeBytes(of: UInt32(8 + payload.count).bigEndian, Array.init))
            tkhd.append(contentsOf: Array("tkhd".utf8))
            return tkhd + payload
        }
        let one: Int32 = 0x0001_0000
        XCTAssertEqual(MP4ContainerParser.rotationDegrees(trak(a: one, b: 0, c: 0, d: one), trakRange: 0..<100), 0)
        let quarter = trak(a: 0, b: one, c: -one, d: 0)
        XCTAssertEqual(MP4ContainerParser.rotationDegrees(quarter, trakRange: 0..<quarter.count), 90)
        let half = trak(a: -one, b: 0, c: 0, d: -one)
        XCTAssertEqual(MP4ContainerParser.rotationDegrees(half, trakRange: 0..<half.count), 180)
    }

    // MARK: - Transport streams

    func test_frameRate_fromPresentationTimestamps() {
        // 25 fps is 3600 ticks; B-frame reordering leaves the stream out of
        // display order, which sorting undoes.
        let timestamps: [UInt64] = [0, 10_800, 3_600, 7_200, 21_600, 14_400, 18_000]
        XCTAssertEqual(TransportStreamScanner.frameRate(fromTimestamps: timestamps), 25)
        XCTAssertNil(TransportStreamScanner.frameRate(fromTimestamps: [0, 3_600]))
    }

    /// MPEG-TS is validated like MP4 now: the PID is demultiplexed, the
    /// pictures counted, and audio PIDs described.
    func test_transportStream_isDemuxedAndValidated() throws {
        var elementary = Data([0, 0, 0, 1]) + Data(Self.spsH264NAL)
        elementary.append(contentsOf: [0, 0, 0, 1, 0x68, 0xEE, 0x3C, 0x80])
        for index in 0..<4 {
            elementary.append(contentsOf: [0, 0, 0, 1, index == 0 ? 0x65 : 0x41, 0x88, 0x84, 0x00])
        }
        let adtsLength = 13
        let adts = Data([0xFF, 0xF1, 0x4C, 0x80, UInt8(adtsLength >> 3), UInt8((adtsLength & 7) << 5) | 0x1F, 0xFC])
            + Data(count: adtsLength - 7)
        let ts = Self.transportStream(streams: [(0x1B, 0x100, elementary), (0x0F, 0x101, adts + adts)])

        let result = try VideoProbe.probe(ts)
        XCTAssertEqual(result.container, .mpegTS)
        XCTAssertEqual(result.stream.codec, .h264)
        XCTAssertEqual(result.frameCount, 4)
        XCTAssertEqual(result.frameCountSource, .accessUnitScan)
        XCTAssertEqual(result.suggestedTransferSyntax, .mpeg4AVCHP41)
        XCTAssertEqual(result.audioTracks.first?.format, .aac)
        XCTAssertEqual(result.audioTracks.first?.samplingFrequency, 48_000)
    }

    // MARK: - Shared fixtures

    /// A 1080p High@4.1 SPS NAL unit, cropped to 1080 and carrying VUI timing.
    private static let spsH264NAL: [UInt8] = [
        0x67, 0x64, 0x00, 0x29, 0xAC, 0xB4, 0x03, 0xC0, 0x11, 0x3F, 0x2C, 0x20,
        0x00, 0x00, 0x03, 0x00, 0x20, 0x00, 0x00, 0x07, 0x98,
    ]

    /// A transport stream with a PAT, a PMT and one PES per elementary stream.
    private static func transportStream(streams: [(type: UInt8, pid: Int, payload: Data)]) -> Data {
        let pmtPID = 0x1000
        func packets(pid: Int, payload: Data) -> Data {
            var out = Data()
            var remaining = payload[...]
            var first = true
            var counter: UInt8 = 0
            repeat {
                let body = remaining.prefix(184)
                remaining = remaining.dropFirst(body.count)
                out.append(0x47)
                out.append(UInt8((first ? 0x40 : 0x00) | (pid >> 8) & 0x1F))
                out.append(UInt8(pid & 0xFF))
                if body.count < 184 {
                    // Adaptation-field stuffing, so the payload ends the packet.
                    let stuffing = 184 - body.count - 1
                    out.append(0x30 | counter)
                    out.append(UInt8(stuffing))
                    if stuffing > 0 { out.append(0x00); out.append(Data(repeating: 0xFF, count: stuffing - 1)) }
                } else {
                    out.append(0x10 | counter)
                }
                out.append(body)
                counter = (counter + 1) & 0x0F
                first = false
            } while !remaining.isEmpty
            return out
        }
        func section(tableID: UInt8, body: Data) -> Data {
            let length = body.count + 4
            return Data([0x00, tableID, UInt8(0xB0 | (length >> 8) & 0x0F), UInt8(length & 0xFF)])
                + body + Data(count: 4)
        }
        var pat = Data([0x00, 0x01, 0xC1, 0x00, 0x00, 0x00, 0x01])
        pat.append(contentsOf: [UInt8(0xE0 | (pmtPID >> 8)), UInt8(pmtPID & 0xFF)])
        var pmt = Data([0x00, 0x01, 0xC1, 0x00, 0x00, 0xE1, 0x00, 0xF0, 0x00])
        for stream in streams {
            pmt.append(contentsOf: [stream.type, UInt8(0xE0 | (stream.pid >> 8)), UInt8(stream.pid & 0xFF), 0xF0, 0x00])
        }
        var ts = packets(pid: 0, payload: section(tableID: 0x00, body: pat))
            + packets(pid: pmtPID, payload: section(tableID: 0x02, body: pmt))
        for stream in streams {
            let streamID: UInt8 = stream.type == 0x1B ? 0xE0 : 0xC0
            let pes = Data([0x00, 0x00, 0x01, streamID, 0x00, 0x00, 0x80, 0x00, 0x00]) + stream.payload
            ts.append(packets(pid: stream.pid, payload: pes))
        }
        // A run of null packets so sync detection sees enough packets.
        for _ in 0..<4 { ts.append(packets(pid: 0x1FFF, payload: Data(count: 184))) }
        return ts
    }
}
