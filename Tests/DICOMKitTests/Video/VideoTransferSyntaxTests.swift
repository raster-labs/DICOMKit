//
// VideoTransferSyntaxTests.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
@testable import DICOMKit
@testable import DICOMCore

/// Covers all 16 registered video transfer syntaxes.
///
/// The repository previously defined only 6, omitting the H.264 Level 4.2 UIDs that
/// IHE Endoscopy Image Archiving Table 3.10.4.1.3.1-2 requires of an endoscopy
/// archive, plus the 7 fragmentable variants. HEVC has no ".1" variants: .107
/// and .108 are each a Fragmentable Encapsulated Transfer Syntax already.
///
/// Reference: PS3.6 Annex A - UID registry (DICOM 2026d)
/// Reference: PS3.5 Sections 8.2.5 - 8.2.11, A.4.5 - A.4.7
final class VideoTransferSyntaxTests: XCTestCase {

    /// Every video transfer syntax UID in the registry, with its expected codec.
    private static let allVideoSyntaxes: [(uid: String, codec: VideoCodec, fragmentable: Bool)] = [
        ("1.2.840.10008.1.2.4.100",   .mpeg2, false),
        ("1.2.840.10008.1.2.4.100.1", .mpeg2, true),
        ("1.2.840.10008.1.2.4.101",   .mpeg2, false),
        ("1.2.840.10008.1.2.4.101.1", .mpeg2, true),
        ("1.2.840.10008.1.2.4.102",   .h264,  false),
        ("1.2.840.10008.1.2.4.102.1", .h264,  true),
        ("1.2.840.10008.1.2.4.103",   .h264,  false),
        ("1.2.840.10008.1.2.4.103.1", .h264,  true),
        ("1.2.840.10008.1.2.4.104",   .h264,  false),
        ("1.2.840.10008.1.2.4.104.1", .h264,  true),
        ("1.2.840.10008.1.2.4.105",   .h264,  false),
        ("1.2.840.10008.1.2.4.105.1", .h264,  true),
        ("1.2.840.10008.1.2.4.106",   .h264,  false),
        ("1.2.840.10008.1.2.4.106.1", .h264,  true),
        ("1.2.840.10008.1.2.4.107",   .h265,  true),
        ("1.2.840.10008.1.2.4.108",   .h265,  true),
    ]

    func test_allSixteenVideoSyntaxes_areDefined() {
        // PS3.6 Table A-1 lists 16 video UIDs: seven MPEG-2/H.264 base UIDs and
        // their seven ".1" twins, plus the two HEVC UIDs.
        XCTAssertEqual(Self.allVideoSyntaxes.count, 16)

        for entry in Self.allVideoSyntaxes {
            let ts = TransferSyntax.from(uid: entry.uid)
            XCTAssertNotNil(ts, "\(entry.uid) must be a recognized transfer syntax")
        }
    }

    func test_everyVideoSyntax_isVideoAndEncapsulated() throws {
        for entry in Self.allVideoSyntaxes {
            let ts = try XCTUnwrap(TransferSyntax.from(uid: entry.uid))
            XCTAssertTrue(ts.isVideo, "\(entry.uid) must report isVideo")
            XCTAssertTrue(ts.isEncapsulated, "\(entry.uid) must be encapsulated")
            XCTAssertTrue(ts.isExplicitVR, "\(entry.uid) is Explicit VR")
            XCTAssertEqual(ts.byteOrder, .littleEndian)
        }
    }

    func test_everyVideoSyntax_mapsToItsCodec() throws {
        for entry in Self.allVideoSyntaxes {
            let ts = try XCTUnwrap(TransferSyntax.from(uid: entry.uid))
            switch entry.codec {
            case .mpeg2:
                XCTAssertTrue(ts.isMPEG2, "\(entry.uid) is MPEG-2")
                XCTAssertFalse(ts.isH264)
                XCTAssertFalse(ts.isH265)
            case .h264:
                XCTAssertTrue(ts.isH264, "\(entry.uid) is H.264")
                XCTAssertFalse(ts.isMPEG2)
                XCTAssertFalse(ts.isH265)
            case .h265:
                XCTAssertTrue(ts.isH265, "\(entry.uid) is HEVC")
                XCTAssertFalse(ts.isMPEG2)
                XCTAssertFalse(ts.isH264)
            case .unknown:
                XCTFail("no video syntax maps to .unknown")
            }

            XCTAssertEqual(VideoCodec(transferSyntaxUID: entry.uid), entry.codec,
                           "VideoCodec must recognize \(entry.uid)")
        }
    }

    func test_allowsMultipleFragments_onlyForFragmentableVariants() throws {
        for entry in Self.allVideoSyntaxes {
            let ts = try XCTUnwrap(TransferSyntax.from(uid: entry.uid))
            XCTAssertEqual(ts.allowsMultipleFragments, entry.fragmentable,
                           "\(entry.uid) fragmentability")
        }
    }

    func test_hevcIsFragmentableInItsOwnRight_andTheUnregisteredTwinsAreOnlyKept() {
        // PS3.5 8.2.10 / 8.2.11: .107 and .108 are Fragmentable Encapsulated Transfer Syntaxes
        // in their own right.
        XCTAssertTrue(TransferSyntax.hevcH265MainProfile.allowsMultipleFragments)
        XCTAssertTrue(TransferSyntax.hevcH265Main10Profile.allowsMultipleFragments)
        // ".107.1" and ".108.1" are not registered UIDs (PS3.6 Table A-1). Origin/main removed
        // the constants; this branch keeps them by decision (TransferSyntax.swift, Standard2026aTests)
        // and `dicom-video` refuses them, so the library only recognises them, never offers them.
        XCTAssertEqual(TransferSyntax.from(uid: "1.2.840.10008.1.2.4.107.1"), .hevcH265MainProfileFragmentable)
        XCTAssertEqual(TransferSyntax.from(uid: "1.2.840.10008.1.2.4.108.1"), .hevcH265Main10ProfileFragmentable)
        XCTAssertFalse(VideoConformanceValidator.candidates(for: VideoStreamInfo(
            codec: .h265, width: 1920, height: 1080, profileIDC: 1, levelTimesTen: 51,
            chromaFormat: .yuv420, bitDepthLuma: 8, bitDepthChroma: 8, frameRate: 30,
            isProgressive: true)).contains(.hevcH265MainProfileFragmentable))
    }

    func test_allowsMultipleFragments_isFalseForNonVideoSyntaxes() {
        // The property models the video fragmentation rule specifically; JPEG-family
        // fragmentation is governed by different rules.
        XCTAssertFalse(TransferSyntax.jpegBaseline.allowsMultipleFragments)
        XCTAssertFalse(TransferSyntax.jpeg2000.allowsMultipleFragments)
        XCTAssertFalse(TransferSyntax.explicitVRLittleEndian.allowsMultipleFragments)
        XCTAssertFalse(TransferSyntax.rleLossless.allowsMultipleFragments)
    }

    func test_ihe_requiredEndoscopySyntaxes_arePresent() throws {
        // IHE ENDO Table 3.10.4.1.3.1-2 lists .100 through .106 as the transfer
        // syntaxes an endoscopy Image Archive must support.
        let required = [
            "1.2.840.10008.1.2.4.100",
            "1.2.840.10008.1.2.4.101",
            "1.2.840.10008.1.2.4.102",
            "1.2.840.10008.1.2.4.103",
            "1.2.840.10008.1.2.4.104",
            "1.2.840.10008.1.2.4.105",
            "1.2.840.10008.1.2.4.106",
        ]
        for uid in required {
            let ts = try XCTUnwrap(TransferSyntax.from(uid: uid),
                                   "IHE requires \(uid) for endoscopy archives")
            XCTAssertTrue(ts.isVideo)
        }
    }

    func test_allVideoSyntaxes_areListedInAllKnown() {
        let listed = Set(TransferSyntax.allKnown.map { $0.uid })
        for entry in Self.allVideoSyntaxes {
            XCTAssertTrue(listed.contains(entry.uid),
                          "\(entry.uid) missing from allKnown")
        }
    }

    func test_allVideoSyntaxes_haveDistinctDisplayNames() {
        var seen: Set<String> = []
        for entry in Self.allVideoSyntaxes {
            guard let ts = TransferSyntax.from(uid: entry.uid) else {
                XCTFail("\(entry.uid) unresolved")
                continue
            }
            let name = ts.displayName
            XCTAssertFalse(name.isEmpty)
            XCTAssertFalse(name.contains(entry.uid),
                           "\(entry.uid) fell through to the generic description")
            XCTAssertTrue(seen.insert(name).inserted,
                          "display name '\(name)' is duplicated")
        }
    }

    func test_videoSyntaxes_areAllLossy() {
        // Every video transfer syntax carries irreversibly compressed data.
        for entry in Self.allVideoSyntaxes {
            guard let ts = TransferSyntax.from(uid: entry.uid) else { continue }
            XCTAssertFalse(ts.isLossless, "\(entry.uid) must not report isLossless")
        }
    }

    func test_nonVideoSyntaxes_areNotVideo() {
        XCTAssertFalse(TransferSyntax.jpegBaseline.isVideo)
        XCTAssertFalse(TransferSyntax.jpeg2000.isVideo)
        XCTAssertFalse(TransferSyntax.rleLossless.isVideo)
        XCTAssertFalse(TransferSyntax.explicitVRLittleEndian.isVideo)
        XCTAssertFalse(TransferSyntax.implicitVRLittleEndian.isVideo)
        XCTAssertEqual(VideoCodec(transferSyntaxUID: TransferSyntax.jpegBaseline.uid), .unknown)
        XCTAssertEqual(VideoCodec(transferSyntaxUID: "not-a-uid"), .unknown)
    }
}
