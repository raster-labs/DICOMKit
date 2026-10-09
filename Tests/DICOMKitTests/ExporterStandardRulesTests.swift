// NEMA-verified: 2026a, checked 2026-10-06 — Cine Module rate attributes (PS3.3 2026a Table C.7-13: Recommended Display Frame Rate (0008,2144) Frames/second, Cine Rate (0018,0040) Frames per second, Frame Time (0018,1063) msec per Frame), Burned In Annotation (0028,0301) Enumerated Values YES / NO (Table C.7-9), "The first Frame shall be denoted as Frame number 1" (Table 10-3) (D252)
import XCTest
@testable import DICOMKit
import DICOMCore

/// D252: dicom-export's CLI-local ExportStandard rules live in DICOMKit `DICOMImageExporter`.
final class ExporterStandardRulesTests: XCTestCase {

    func testCineFrameRateOrderAndUnits() {
        typealias Rate = DICOMImageExporter.CineFrameRate
        let all = DataSet(elements: [
            .string(tag: .recommendedDisplayFrameRate, vr: .IS, value: "30"),
            .string(tag: .cineRate, vr: .IS, value: "25"),
            .string(tag: .frameTime, vr: .DS, value: "100"),
        ])
        XCTAssertEqual(Rate.resolve(explicit: 12, dataSet: all), Rate(fps: 12, source: .option))
        XCTAssertEqual(Rate.resolve(explicit: nil, dataSet: all), Rate(fps: 30, source: .recommendedDisplayFrameRate))
        let cine = DataSet(elements: [.string(tag: .cineRate, vr: .IS, value: "25"),
                                      .string(tag: .frameTime, vr: .DS, value: "100")])
        XCTAssertEqual(Rate.resolve(explicit: nil, dataSet: cine), Rate(fps: 25, source: .cineRate))
        let frameTime = DataSet(elements: [.string(tag: .frameTime, vr: .DS, value: "40")])
        XCTAssertEqual(Rate.resolve(explicit: nil, dataSet: frameTime), Rate(fps: 25, source: .frameTime), "1000 / msec")
        XCTAssertEqual(Rate.resolve(explicit: nil, dataSet: DataSet()), Rate(fps: Rate.fallbackFPS, source: .fallback))
        XCTAssertEqual(Rate.Source.frameTime.label, "Frame Time (0018,1063)")
    }

    func testBurnedInAnnotationAndFrameTexts() {
        XCTAssertTrue(DICOMImageExporter.BurnedInAnnotation.isYes(
            DataSet(elements: [.string(tag: .burnedInAnnotation, vr: .CS, value: "YES ")])))
        XCTAssertFalse(DICOMImageExporter.BurnedInAnnotation.isYes(
            DataSet(elements: [.string(tag: .burnedInAnnotation, vr: .CS, value: "NO")])))
        XCTAssertFalse(DICOMImageExporter.BurnedInAnnotation.isYes(DataSet()), "absent: may or may not")
        XCTAssertEqual(DICOMImageExporter.FrameSelection.reference, "PS3.3 Table 10-3: the first Frame is Frame number 1")
        XCTAssertEqual(DICOMImageExporter.FrameSelection.invalidFrameNumberMessage(requested: 4, total: 1),
                       "Frame number 4 does not exist. The file has 1 frame, numbered 1 to 1.")
        XCTAssertEqual(DICOMImageExporter.FrameSelectionConflict(zeroBased: "--frame", oneBased: "--frame-number").description,
                       "--frame (deprecated, 0-based) and --frame-number (numbered from 1) cannot be used together")
        XCTAssertTrue(DICOMImageExporter.ApplyWindowDeprecation.note(subcommand: "bulk")
            .hasPrefix("warning: bulk --apply-window is deprecated and has no effect"))
    }
}
