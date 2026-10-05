//
// VideoConformanceValidatorTests.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
@testable import DICOMKit
@testable import DICOMCore

/// One rejection test per constraint, each asserting the specific message.
///
/// Video DICOM is unusually strict, and a rejection is only useful if it names the
/// violated constraint, the observed value and the expected value.
///
/// Reference: PS3.5 Sections 8.2.5 - 8.2.11, Table 8-4
final class VideoConformanceValidatorTests: XCTestCase {

    // MARK: - Helpers

    private func h264Stream(
        width: Int = 1920,
        height: Int = 1080,
        profileIDC: Int = 100,
        levelTimesTen: Int = 41,
        chroma: ChromaFormat = .yuv420,
        bitDepth: Int = 8,
        frameRate: Double? = 30.0,
        isProgressive: Bool = true,
        sar: (width: Int, height: Int)? = nil
    ) -> VideoStreamInfo {
        VideoStreamInfo(
            codec: .h264, width: width, height: height,
            profileIDC: profileIDC, levelTimesTen: levelTimesTen,
            chromaFormat: chroma, bitDepthLuma: bitDepth, bitDepthChroma: bitDepth,
            frameRate: frameRate, isProgressive: isProgressive, sampleAspectRatio: sar
        )
    }

    private func hevcStream(
        profileIDC: Int = 1,
        levelTimesTen: Int = 51,
        bitDepth: Int = 8
    ) -> VideoStreamInfo {
        VideoStreamInfo(
            codec: .h265, width: 1920, height: 1080,
            profileIDC: profileIDC, levelTimesTen: levelTimesTen,
            chromaFormat: .yuv420, bitDepthLuma: bitDepth, bitDepthChroma: bitDepth,
            frameRate: 30.0, isProgressive: true
        )
    }

    private func mpeg2Stream(
        width: Int = 720,
        height: Int = 576,
        profileIDC: Int = 4,
        level: Int = 8
    ) -> VideoStreamInfo {
        VideoStreamInfo(
            codec: .mpeg2, width: width, height: height,
            profileIDC: profileIDC, levelTimesTen: level,
            chromaFormat: .yuv420, bitDepthLuma: 8, bitDepthChroma: 8,
            frameRate: 25.0, isProgressive: true
        )
    }

    // MARK: - The conformant baseline

    func test_conformantH264_passes() {
        let result = VideoConformanceValidator.validate(
            stream: h264Stream(),
            transferSyntax: .mpeg4AVCHP41,
            numberOfFrames: 300
        )
        XCTAssertTrue(result.isConformant, result.report)
        XCTAssertTrue(result.violations.isEmpty)
        XCTAssertEqual(result.report, "")
    }

    func test_conformantHEVCMain_passes() {
        let result = VideoConformanceValidator.validate(
            stream: hevcStream(),
            transferSyntax: .hevcH265MainProfile
        )
        XCTAssertTrue(result.isConformant, result.report)
    }

    func test_conformantHEVCMain10_passes() {
        let result = VideoConformanceValidator.validate(
            stream: hevcStream(profileIDC: 2, bitDepth: 10),
            transferSyntax: .hevcH265Main10Profile
        )
        XCTAssertTrue(result.isConformant, result.report)
    }

    func test_conformantMPEG2MainLevel_passes() {
        let result = VideoConformanceValidator.validate(
            stream: mpeg2Stream(),
            transferSyntax: .mpeg2MainProfile
        )
        XCTAssertTrue(result.isConformant, result.report)
    }

    // MARK: - Profile

    func test_baselineProfile_isRejectedWithBothIDCs() {
        let result = VideoConformanceValidator.validate(
            stream: h264Stream(profileIDC: 66),
            transferSyntax: .mpeg4AVCHP41
        )
        XCTAssertFalse(result.isConformant)

        let message = result.report
        XCTAssertTrue(message.contains("profile_idc 66"), message)
        XCTAssertTrue(message.contains("Baseline"), message)
        XCTAssertTrue(message.contains("High Profile (100)"), message)
        XCTAssertTrue(message.contains("ffmpeg"), "a rejection must give a remedy")
    }

    func test_mainProfile_isRejected() {
        let result = VideoConformanceValidator.validate(
            stream: h264Stream(profileIDC: 77),
            transferSyntax: .mpeg4AVCHP41
        )
        XCTAssertFalse(result.isConformant)
        XCTAssertTrue(result.report.contains("Main"), result.report)
    }

    func test_hevcMain10Stream_rejectedByMainProfileSyntax() {
        // Main 10 content cannot be labelled as .107; the profile and the bit
        // depth both disagree.
        let result = VideoConformanceValidator.validate(
            stream: hevcStream(profileIDC: 2, bitDepth: 10),
            transferSyntax: .hevcH265MainProfile
        )
        XCTAssertFalse(result.isConformant)
        XCTAssertTrue(result.violations.contains { violation in
            if case .bitDepthMismatch = violation { return true }
            return false
        }, result.report)
    }

    // MARK: - Level

    func test_levelAboveCeiling_isRejected() {
        // Level 5.0 exceeds the 4.1 ceiling of transfer syntax .102.
        let result = VideoConformanceValidator.validate(
            stream: h264Stream(levelTimesTen: 50),
            transferSyntax: .mpeg4AVCHP41
        )
        XCTAssertFalse(result.isConformant)
        XCTAssertTrue(result.report.contains("level 5.0"), result.report)
        XCTAssertTrue(result.report.contains("4.1"), result.report)
    }

    func test_level42_isRejectedBy41SyntaxButAcceptedBy42() {
        let stream = h264Stream(levelTimesTen: 42, frameRate: 60.0)

        let rejected = VideoConformanceValidator.validate(
            stream: stream, transferSyntax: .mpeg4AVCHP41
        )
        XCTAssertFalse(rejected.isConformant, "Level 4.2 exceeds the 4.1 ceiling")

        let accepted = VideoConformanceValidator.validate(
            stream: stream, transferSyntax: .mpeg4AVCHP42For2DVideo
        )
        XCTAssertTrue(accepted.isConformant, accepted.report)
    }

    func test_hevcLevelAboveFiveOne_isRejected() {
        let result = VideoConformanceValidator.validate(
            stream: hevcStream(levelTimesTen: 61),
            transferSyntax: .hevcH265MainProfile
        )
        XCTAssertFalse(result.isConformant)
        XCTAssertTrue(result.report.contains("6.1"), result.report)
    }

    func test_mpeg2LevelComparison_inverts() {
        // MPEG-2 level identifiers descend: High is 4, Main is 8. High Level
        // content therefore does not fit the Main Level transfer syntax.
        let highLevel = mpeg2Stream(width: 1920, height: 1080, level: 4)

        let onHighLevelSyntax = VideoConformanceValidator.validate(
            stream: highLevel, transferSyntax: .mpeg2MainProfileHighLevel
        )
        XCTAssertTrue(onHighLevelSyntax.isConformant, onHighLevelSyntax.report)

        let mainLevelContent = mpeg2Stream(level: 8)
        let onMainLevelSyntax = VideoConformanceValidator.validate(
            stream: mainLevelContent, transferSyntax: .mpeg2MainProfile
        )
        XCTAssertTrue(onMainLevelSyntax.isConformant, onMainLevelSyntax.report)

        // High Level content on the Main Level syntax exceeds its ceiling (the
        // comparison used to run the wrong way and let it through).
        let mismatch = VideoConformanceValidator.validate(
            stream: highLevel, transferSyntax: .mpeg2MainProfile
        )
        XCTAssertTrue(mismatch.violations.contains(.levelExceedsMaximum(
            observed: "High", maximum: "Main", codec: .mpeg2, pictureFitsMaximum: false)),
                      mismatch.report)

        // Main Level is below the High Level ceiling: "An MPEG2 Main Profile / High Level
        // decoder is able to decode bit streams conforming to lower levels" (PS3.5 2026a
        // 8.2.6), so it is no level violation. (8.2.6 also fixes Rows/Columns at 720/1280
        // or 1080/1920, which this validator does not check yet.)
        let lower = VideoConformanceValidator.validate(
            stream: mainLevelContent, transferSyntax: .mpeg2MainProfileHighLevel
        )
        XCTAssertFalse(lower.violations.contains { if case .levelExceedsMaximum = $0 { return true }; return false },
                       lower.report)
    }

    // MARK: - Chroma format

    func test_chroma422_isRejected() {
        let result = VideoConformanceValidator.validate(
            stream: h264Stream(profileIDC: 122, chroma: .yuv422),
            transferSyntax: .mpeg4AVCHP41
        )
        XCTAssertFalse(result.isConformant)
        XCTAssertTrue(result.report.contains("4:2:2"), result.report)
        XCTAssertTrue(result.report.contains("4:2:0"), result.report)
    }

    func test_chroma444_isRejected() {
        let result = VideoConformanceValidator.validate(
            stream: h264Stream(chroma: .yuv444),
            transferSyntax: .mpeg4AVCHP41
        )
        XCTAssertFalse(result.isConformant)
        XCTAssertTrue(result.report.contains("4:4:4"), result.report)
    }

    func test_monochrome_isRejected() {
        let result = VideoConformanceValidator.validate(
            stream: h264Stream(chroma: .monochrome),
            transferSyntax: .mpeg4AVCHP41
        )
        XCTAssertFalse(result.isConformant)
        XCTAssertTrue(result.report.contains("monochrome"), result.report)
    }

    // MARK: - Bit depth

    func test_twelveBit_isRejectedAsUnrepresentable() {
        let result = VideoConformanceValidator.validate(
            stream: hevcStream(profileIDC: 2, bitDepth: 12),
            transferSyntax: .hevcH265Main10Profile
        )
        XCTAssertFalse(result.isConformant)
        XCTAssertTrue(result.report.contains("12-bit"), result.report)
    }

    func test_eightBitOnMain10Syntax_isRejected() {
        let result = VideoConformanceValidator.validate(
            stream: hevcStream(profileIDC: 2, bitDepth: 8),
            transferSyntax: .hevcH265Main10Profile
        )
        XCTAssertFalse(result.isConformant)
        XCTAssertTrue(result.report.contains("10-bit"), result.report)
    }

    // MARK: - Anamorphic pixels

    func test_anamorphicPixels_areRejected() {
        // PS3.5 8.2.7 requires Pixel Aspect Ratio to be absent, i.e. SAR 1:1.
        let result = VideoConformanceValidator.validate(
            stream: h264Stream(width: 1440, sar: (4, 3)),
            transferSyntax: .mpeg4AVCHP41
        )
        XCTAssertFalse(result.isConformant)
        XCTAssertTrue(result.report.contains("4:3"), result.report)
        XCTAssertTrue(result.report.contains("Pixel Aspect Ratio"), result.report)
    }

    func test_squareSampleAspectRatio_isAccepted() {
        let result = VideoConformanceValidator.validate(
            stream: h264Stream(sar: (1, 1)),
            transferSyntax: .mpeg4AVCHP41
        )
        XCTAssertTrue(result.isConformant, result.report)
    }

    func test_oddDimensionsAreNotRejected() {
        // The standard does NOT require Rows and Columns to be even; an earlier
        // draft of this work asserted that and was wrong.
        let result = VideoConformanceValidator.validate(
            stream: h264Stream(width: 1919, height: 1079),
            transferSyntax: .mpeg4AVCHP41
        )
        XCTAssertTrue(result.isConformant,
                      "odd dimensions are legal; only SAR 1:1 and codec limits apply")
    }

    // MARK: - Dimension cross-check

    func test_declaredDimensionsMustMatchBitstream() {
        // The 1088-vs-1080 case: a caller who skipped frame cropping.
        let result = VideoConformanceValidator.validate(
            stream: h264Stream(width: 1920, height: 1080),
            transferSyntax: .mpeg4AVCHP41,
            declaredRows: 1088,
            declaredColumns: 1920
        )
        XCTAssertFalse(result.isConformant)
        XCTAssertTrue(result.report.contains("1920x1088"), result.report)
        XCTAssertTrue(result.report.contains("1920x1080"), result.report)
    }

    func test_matchingDeclaredDimensions_pass() {
        let result = VideoConformanceValidator.validate(
            stream: h264Stream(),
            transferSyntax: .mpeg4AVCHP41,
            declaredRows: 1080,
            declaredColumns: 1920
        )
        XCTAssertTrue(result.isConformant, result.report)
    }

    // MARK: - Frame count

    func test_zeroFrames_isRejected() {
        let result = VideoConformanceValidator.validate(
            stream: h264Stream(),
            transferSyntax: .mpeg4AVCHP41,
            numberOfFrames: 0
        )
        XCTAssertFalse(result.isConformant)
        XCTAssertTrue(result.report.contains("at least 1"), result.report)
    }

    func test_oneFrame_isAccepted() {
        let result = VideoConformanceValidator.validate(
            stream: h264Stream(),
            transferSyntax: .mpeg4AVCHP41,
            numberOfFrames: 1
        )
        XCTAssertTrue(result.isConformant, result.report)
    }

    // MARK: - Codec mismatch

    func test_hevcStreamOnH264Syntax_isRejected() {
        let result = VideoConformanceValidator.validate(
            stream: hevcStream(),
            transferSyntax: .mpeg4AVCHP41
        )
        XCTAssertFalse(result.isConformant)
        XCTAssertTrue(result.report.contains("H.265/HEVC"), result.report)
        XCTAssertTrue(result.report.contains("H.264/AVC"), result.report)
    }

    func test_nonVideoTransferSyntax_isRejected() {
        let result = VideoConformanceValidator.validate(
            stream: h264Stream(),
            transferSyntax: .jpegBaseline
        )
        XCTAssertFalse(result.isConformant)
        XCTAssertNil(VideoConformanceValidator.constraints(for: .jpegBaseline))
    }

    // MARK: - Blu-ray compatibility, PS3.5 Table 8-4

    func test_bluRayTable_matchesSpecification() {
        // Exactly eight rows, and 1920x1080 only interlaced at 25 / 29.97.
        XCTAssertEqual(VideoConformanceValidator.bluRayFormats.count, 8)

        XCTAssertTrue(VideoConformanceValidator.isBluRayCompatible(
            width: 1920, height: 1080, frameRate: 25.0, isProgressive: false))
        XCTAssertTrue(VideoConformanceValidator.isBluRayCompatible(
            width: 1920, height: 1080, frameRate: 30000.0 / 1001.0, isProgressive: false))
        XCTAssertTrue(VideoConformanceValidator.isBluRayCompatible(
            width: 1920, height: 1080, frameRate: 24.0, isProgressive: true))
        XCTAssertTrue(VideoConformanceValidator.isBluRayCompatible(
            width: 1920, height: 1080, frameRate: 24000.0 / 1001.0, isProgressive: true))
        XCTAssertTrue(VideoConformanceValidator.isBluRayCompatible(
            width: 1280, height: 720, frameRate: 50.0, isProgressive: true))
        XCTAssertTrue(VideoConformanceValidator.isBluRayCompatible(
            width: 1280, height: 720, frameRate: 60000.0 / 1001.0, isProgressive: true))
        XCTAssertTrue(VideoConformanceValidator.isBluRayCompatible(
            width: 1280, height: 720, frameRate: 24.0, isProgressive: true))
        XCTAssertTrue(VideoConformanceValidator.isBluRayCompatible(
            width: 1280, height: 720, frameRate: 24000.0 / 1001.0, isProgressive: true))
    }

    func test_progressive1080p25_isNotBluRayCompatible() {
        // 1920x1080 at 25 is permitted only interlaced. This is the detail an
        // earlier guess at the table got wrong.
        XCTAssertFalse(VideoConformanceValidator.isBluRayCompatible(
            width: 1920, height: 1080, frameRate: 25.0, isProgressive: true))

        let result = VideoConformanceValidator.validate(
            stream: h264Stream(frameRate: 25.0, isProgressive: true),
            transferSyntax: .mpeg4AVCHP41BD
        )
        XCTAssertFalse(result.isConformant)
        XCTAssertTrue(result.report.contains("Table 8-4"), result.report)
        XCTAssertTrue(result.report.contains("progressive"), result.report)
    }

    func test_standardDefinitionIsNotBluRayCompatible() {
        // 720x576 and 720x480 are NOT in Table 8-4, despite being plausible.
        XCTAssertFalse(VideoConformanceValidator.isBluRayCompatible(
            width: 720, height: 576, frameRate: 25.0, isProgressive: false))
        XCTAssertFalse(VideoConformanceValidator.isBluRayCompatible(
            width: 720, height: 480, frameRate: 30000.0 / 1001.0, isProgressive: false))
    }

    func test_bluRayCompatibleStream_passesOnBDSyntax() {
        let result = VideoConformanceValidator.validate(
            stream: h264Stream(width: 1280, height: 720, frameRate: 50.0, isProgressive: true),
            transferSyntax: .mpeg4AVCHP41BD
        )
        XCTAssertTrue(result.isConformant, result.report)
    }

    func test_bluRayConstraintsDoNotApplyToOtherSyntaxes() {
        // The same stream that fails .103 passes .102, which has no Table 8-4
        // constraint.
        let stream = h264Stream(frameRate: 25.0, isProgressive: true)
        XCTAssertFalse(VideoConformanceValidator.validate(
            stream: stream, transferSyntax: .mpeg4AVCHP41BD).isConformant)
        XCTAssertTrue(VideoConformanceValidator.validate(
            stream: stream, transferSyntax: .mpeg4AVCHP41).isConformant)
    }

    // MARK: - Fragmentable variants share their twin's constraints

    func test_fragmentableVariant_hasSameConstraintsAsBase() throws {
        let base = try XCTUnwrap(VideoConformanceValidator.constraints(for: .mpeg4AVCHP41))
        let fragmentable = try XCTUnwrap(
            VideoConformanceValidator.constraints(for: .mpeg4AVCHP41Fragmentable))

        XCTAssertEqual(base.codec, fragmentable.codec)
        XCTAssertEqual(base.requiredProfileIDC, fragmentable.requiredProfileIDC)
        XCTAssertEqual(base.maximumLevelTimesTen, fragmentable.maximumLevelTimesTen)
        XCTAssertEqual(base.requiredBitDepth, fragmentable.requiredBitDepth)
    }

    func test_fragmentableVariant_validatesTheSame() {
        let result = VideoConformanceValidator.validate(
            stream: h264Stream(),
            transferSyntax: .mpeg4AVCHP41Fragmentable
        )
        XCTAssertTrue(result.isConformant, result.report)
    }

    func test_everyVideoSyntaxHasConstraints() {
        for syntax in TransferSyntax.allKnown where syntax.isVideo {
            XCTAssertNotNil(VideoConformanceValidator.constraints(for: syntax),
                            "\(syntax.uid) must have declared constraints")
        }
    }

    // MARK: - Transfer syntax selection

    func test_selectTransferSyntax_prefersLevel41ForH264() {
        let selected = VideoConformanceValidator.selectTransferSyntax(
            for: h264Stream(levelTimesTen: 41))
        XCTAssertEqual(selected?.uid, TransferSyntax.mpeg4AVCHP41.uid)
    }

    func test_selectTransferSyntax_fallsBackToLevel42() {
        // 1080p60 is Level 4.2 and legal; it must not be rejected outright.
        let selected = VideoConformanceValidator.selectTransferSyntax(
            for: h264Stream(levelTimesTen: 42, frameRate: 60.0))
        XCTAssertEqual(selected?.uid, TransferSyntax.mpeg4AVCHP42For2DVideo.uid)
    }

    func test_selectTransferSyntax_neverChoosesBluRayUID() {
        // .103 adds Table 8-4 constraints without adding capability, so it is
        // never selected automatically.
        for level in [41, 42] {
            let selected = VideoConformanceValidator.selectTransferSyntax(
                for: h264Stream(levelTimesTen: level, frameRate: 24.0))
            XCTAssertNotEqual(selected?.uid, TransferSyntax.mpeg4AVCHP41BD.uid)
        }
    }

    func test_selectTransferSyntax_choosesMain10ForTenBitHEVC() {
        let selected = VideoConformanceValidator.selectTransferSyntax(
            for: hevcStream(profileIDC: 2, bitDepth: 10))
        XCTAssertEqual(selected?.uid, TransferSyntax.hevcH265Main10Profile.uid)
    }

    func test_selectTransferSyntax_choosesMainForEightBitHEVC() {
        let selected = VideoConformanceValidator.selectTransferSyntax(for: hevcStream())
        XCTAssertEqual(selected?.uid, TransferSyntax.hevcH265MainProfile.uid)
    }

    func test_selectTransferSyntax_choosesMPEG2ByLevel() {
        XCTAssertEqual(
            VideoConformanceValidator.selectTransferSyntax(for: mpeg2Stream(level: 8))?.uid,
            TransferSyntax.mpeg2MainProfile.uid)
        XCTAssertEqual(
            VideoConformanceValidator.selectTransferSyntax(
                for: mpeg2Stream(width: 1920, height: 1080, level: 4))?.uid,
            TransferSyntax.mpeg2MainProfileHighLevel.uid)
    }

    func test_selectTransferSyntax_returnsNilForUncarriableStreams() {
        // Baseline H.264 has no transfer syntax.
        XCTAssertNil(VideoConformanceValidator.selectTransferSyntax(
            for: h264Stream(profileIDC: 66)))
        // Level 5.0 H.264 exceeds every ceiling.
        XCTAssertNil(VideoConformanceValidator.selectTransferSyntax(
            for: h264Stream(levelTimesTen: 50)))
        // HEVC above level 5.1.
        XCTAssertNil(VideoConformanceValidator.selectTransferSyntax(
            for: hevcStream(levelTimesTen: 61)))
    }

    func test_selectedTransferSyntax_alwaysValidates() {
        // Whatever selection returns must itself pass validation, or selection
        // and validation disagree.
        let streams = [
            h264Stream(levelTimesTen: 41),
            h264Stream(levelTimesTen: 42, frameRate: 60.0),
            hevcStream(),
            hevcStream(profileIDC: 2, bitDepth: 10),
            mpeg2Stream(level: 8),
            mpeg2Stream(width: 1920, height: 1080, level: 4),
        ]
        for stream in streams {
            guard let syntax = VideoConformanceValidator.selectTransferSyntax(for: stream) else {
                XCTFail("no transfer syntax selected for \(stream.codec.displayName)")
                continue
            }
            let result = VideoConformanceValidator.validate(stream: stream, transferSyntax: syntax)
            XCTAssertTrue(result.isConformant,
                          "selected \(syntax.uid) but validation failed: \(result.report)")
        }
    }

    func test_selectTransferSyntax_prefersNonFragmentableForms() {
        // HEVC is left out: .107 and .108 are fragmentable in their own right.
        let streams = [h264Stream(), mpeg2Stream()]
        for stream in streams {
            let selected = VideoConformanceValidator.selectTransferSyntax(for: stream)
            XCTAssertEqual(selected?.allowsMultipleFragments, false,
                           "the non-fragmentable form is simplest and always legal")
        }
    }

    // MARK: - Multiple violations

    func test_multipleViolations_areAllReported() {
        // Baseline profile, 4:2:2 chroma, level too high, and anamorphic.
        let result = VideoConformanceValidator.validate(
            stream: h264Stream(
                profileIDC: 66, levelTimesTen: 50, chroma: .yuv422, sar: (4, 3)),
            transferSyntax: .mpeg4AVCHP41
        )
        XCTAssertFalse(result.isConformant)
        XCTAssertGreaterThanOrEqual(result.violations.count, 4,
                                    "each violated constraint is reported: \(result.report)")
    }

    func test_report_isEmptyWhenConformant() {
        let result = VideoConformanceValidator.validate(
            stream: h264Stream(), transferSyntax: .mpeg4AVCHP41)
        XCTAssertEqual(result.report, "")
    }

    func test_everyViolationHasANonEmptyMessage() {
        let violations: [VideoConformanceViolation] = [
            .profileNotPermitted(observed: "Baseline", observedIDC: 66, required: "High", requiredIDC: 100),
            .levelExceedsMaximum(observed: "5.0", maximum: "4.1"),
            .chromaFormatNotPermitted(observed: "4:2:2"),
            .bitDepthNotRepresentable(observed: 12),
            .bitDepthMismatch(observed: 8, expected: 10, transferSyntax: "1.2.840.10008.1.2.4.108"),
            .anamorphicPixels(width: 4, height: 3),
            .dimensionMismatch(declaredColumns: 1920, declaredRows: 1088, actualWidth: 1920, actualHeight: 1080),
            .codecNotSupported(observed: "VP9"),
            .codecMismatch(observed: "H.265/HEVC", expected: "H.264/AVC", transferSyntax: "1.2.840.10008.1.2.4.102"),
            .invalidFrameCount(observed: 0),
            .notBluRayCompatible(width: 1920, height: 1080, frameRate: 25.0, isProgressive: true),
            .containerNotPermitted(observed: "Matroska"),
        ]
        for violation in violations {
            XCTAssertFalse(violation.message.isEmpty, "\(violation) has no message")
        }
    }
}
