//
// MPEG2FrameRateTableTests.swift
// DICOMKit
//
// PS3.5 2026a 8.2.5 Table 8-1 (MPEG2 Main Profile / Main Level: 525-line NTSC 30 fps, maximum
// 480 x 720; 625-line PAL 25 fps, maximum 576 x 720; Note 4: NTSC is approximately 29.97),
// Table 8-2 (Main Profile / High Level frame rates 30, 25, 60, 50; Note 2: 30/1.001 and 60/1.001)
// and 8.2.6 Note 4 / Table 8-3 ("Frame rates of 50 Hz and 60 Hz (progressive) at the maximum
// resolution of 1080 by 1920 are not supported by Main Profile / High Level") (D238).
// The tables themselves are diffed against the 2026a DocBook by Scripts/diff_kit.py
// (check mpeg2-frame-rates).
//

import XCTest
@testable import DICOMKit

final class MPEG2FrameRateTableTests: XCTestCase {

    private func mpeg2(_ width: Int, _ height: Int, fps: Double?, level: Int, progressive: Bool = true) -> VideoStreamInfo {
        VideoStreamInfo(
            codec: .mpeg2, width: width, height: height, profileIDC: 4, levelTimesTen: level,
            chromaFormat: .yuv420, bitDepthLuma: 8, bitDepthChroma: 8, frameRate: fps,
            isProgressive: progressive, mpeg2AspectRatioInformation: level == 4 ? 3 : nil)
    }

    // MARK: - Pinned table values

    func testTableValuesArePinned() {
        XCTAssertEqual(VideoConformanceValidator.mpeg2MainLevelFormats.map { "\($0.videoType) \($0.frameRate) \($0.maximumRows)x\($0.maximumColumns)" },
                       ["525-line NTSC 30.0 480x720", "625-line PAL 25.0 576x720"])
        XCTAssertEqual(VideoConformanceValidator.mpeg2HighLevelFrameRates.map(\.frameRate), [30, 25, 60, 50])
        XCTAssertEqual(VideoConformanceValidator.mpeg2HighLevel1080FrameRates, [25, 30])
    }

    // MARK: - Main Level (Table 8-1)

    func testMainLevelAcceptsTheTwoVideoTypes() {
        for (w, h, fps) in [(720, 576, 25.0), (720, 480, 30000.0 / 1001.0), (720, 480, 30.0), (352, 288, 25.0), (352, 240, 29.97)] {
            let r = VideoConformanceValidator.validate(stream: mpeg2(w, h, fps: fps, level: 8), transferSyntax: .mpeg2MainProfile)
            XCTAssertTrue(r.isConformant, "\(w)x\(h)@\(fps): \(r.report)")
            XCTAssertEqual(VideoConformanceValidator.selectTransferSyntax(for: mpeg2(w, h, fps: fps, level: 8)), .mpeg2MainProfile)
        }
    }

    func testMainLevelRefusesNTSCRateAbove480Rows() {
        let r = VideoConformanceValidator.validate(stream: mpeg2(720, 576, fps: 29.97, level: 8), transferSyntax: .mpeg2MainProfile)
        XCTAssertEqual(r.violations, [.mpeg2MainLevelGeometryExceedsMaximum(
            rows: 576, columns: 720, frameRate: 29.97, maximumRows: 480, maximumColumns: 720)])
        XCTAssertTrue(r.report.contains("Table 8-1"), r.report)
        XCTAssertNil(VideoConformanceValidator.selectTransferSyntax(for: mpeg2(720, 576, fps: 29.97, level: 8)))
    }

    func testMainLevelRefusesOtherFrameRates() {
        for fps in [24.0, 24000.0 / 1001.0, 50.0, 60.0, 15.0] {
            let r = VideoConformanceValidator.validate(stream: mpeg2(720, 480, fps: fps, level: 8), transferSyntax: .mpeg2MainProfile)
            XCTAssertEqual(r.violations, [.mpeg2FrameRateNotPermitted(frameRate: fps, rows: 480, columns: 720, maximumLevel: "Main")], "\(fps)")
            XCTAssertNil(VideoConformanceValidator.selectTransferSyntax(for: mpeg2(720, 480, fps: fps, level: 8)))
        }
        // 25/1.001 is not a Table 8-1 rate (only NTSC carries the 1/1.001 variant)
        XCTAssertFalse(VideoConformanceValidator.validate(
            stream: mpeg2(720, 576, fps: 25000.0 / 1001.0, level: 8), transferSyntax: .mpeg2MainProfile).isConformant)
    }

    func testUnknownFrameRateIsNotRefused() {
        XCTAssertTrue(VideoConformanceValidator.validate(
            stream: mpeg2(720, 576, fps: nil, level: 8), transferSyntax: .mpeg2MainProfile).isConformant)
    }

    // MARK: - High Level (Table 8-2, 8.2.6 Note 4, Table 8-3)

    func testHighLevelAcceptsTable8_3Examples() {
        let rows: [(Int, Int, Double, Bool)] = [
            (1920, 1080, 25, true), (1920, 1080, 29.97, true), (1920, 1080, 30, true),
            (1920, 1080, 25, false), (1920, 1080, 30000.0 / 1001.0, false),
            (1280, 720, 25, true), (1280, 720, 29.97, true), (1280, 720, 30, true),
            (1280, 720, 50, true), (1280, 720, 60000.0 / 1001.0, true), (1280, 720, 60, true),
        ]
        for (w, h, fps, p) in rows {
            let s = mpeg2(w, h, fps: fps, level: 4, progressive: p)
            let r = VideoConformanceValidator.validate(stream: s, transferSyntax: .mpeg2MainProfileHighLevel)
            XCTAssertTrue(r.isConformant, "\(w)x\(h)@\(fps): \(r.report)")
            XCTAssertEqual(VideoConformanceValidator.selectTransferSyntax(for: s), .mpeg2MainProfileHighLevel)
        }
    }

    func testHighLevel1080At50Or60IsRefused() {
        for (fps, progressive) in [(50.0, true), (60.0, true), (59.94, true), (50.0, false)] {
            let s = mpeg2(1920, 1080, fps: fps, level: 4, progressive: progressive)
            let r = VideoConformanceValidator.validate(stream: s, transferSyntax: .mpeg2MainProfileHighLevel)
            XCTAssertEqual(r.violations, [.mpeg2FrameRateNotPermitted(frameRate: fps, rows: 1080, columns: 1920, maximumLevel: "High")])
            XCTAssertTrue(r.report.contains("Table 8-3"), r.report)
            XCTAssertNil(VideoConformanceValidator.selectTransferSyntax(for: s))
        }
    }

    func testHighLevelRefusesRatesOutsideTable8_2() {
        for fps in [24.0, 23.976, 15.0, 120.0] {
            let s = mpeg2(1280, 720, fps: fps, level: 4)
            let r = VideoConformanceValidator.validate(stream: s, transferSyntax: .mpeg2MainProfileHighLevelFragmentable)
            XCTAssertEqual(r.violations, [.mpeg2FrameRateNotPermitted(frameRate: fps, rows: 720, columns: 1280, maximumLevel: "High")])
            XCTAssertTrue(r.report.contains("Table 8-2"), r.report)
        }
    }
}
