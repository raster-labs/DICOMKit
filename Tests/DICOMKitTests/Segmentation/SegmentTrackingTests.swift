//
// SegmentTrackingTests.swift
// DICOMKit
//
// Tracking ID (0062,0020) and Tracking UID (0062,0021) in the Segment Description Macro are
// each Type 1C: Tracking ID "Required if Tracking UID (0062,0021) is present", Tracking UID
// "Required if Tracking ID (0062,0020) is present" (PS3.3 2026a Table C.8.20-4). D45:
// `Segmentation.buildDataSet(pixelData:)` throws when a segment carries only one of them.
// Tags and VRs (UT, UI) per PS3.6 2026a Table 6-1.
//

import XCTest
@testable import DICOMKit
import DICOMCore

final class SegmentTrackingTests: XCTestCase {

    private let anatomicalStructure = CodedConcept(codeValue: "91723000", codingSchemeDesignator: "SCT", codeMeaning: "Anatomical Structure")
    private let liver = CodedConcept(codeValue: "10200004", codingSchemeDesignator: "SCT", codeMeaning: "Liver")
    private let trackingUID = "1.2.826.0.1.3680043.8.498.1"

    func testTagsMatchPS36() {
        XCTAssertEqual(Tag.trackingID, Tag(group: 0x0062, element: 0x0020))
        XCTAssertEqual(Tag.trackingUID, Tag(group: 0x0062, element: 0x0021))
    }

    private func segment(_ number: Int, trackingID: String? = nil, trackingUID: String? = nil) -> Segment {
        Segment(segmentNumber: number, segmentLabel: "S\(number)",
                category: anatomicalStructure, type: liver,
                trackingID: trackingID, trackingUID: trackingUID)
    }

    private func segmentation(_ type: SegmentationType, segments: [Segment]) -> Segmentation {
        Segmentation(
            sopInstanceUID: "1.2.3.9", seriesInstanceUID: "1.2.3.4", studyInstanceUID: "1.2.3",
            segmentationType: type,
            numberOfSegments: segments.count, segments: segments,
            numberOfFrames: 1, rows: 1, columns: 8,
            bitsAllocated: type == .binary ? 1 : 8, bitsStored: type == .binary ? 1 : 8,
            highBit: type == .binary ? 0 : 7)
    }

    // MARK: - Both present: both written, both read back

    func testBothWrittenAndParsed() throws {
        for type in SegmentationType.allCases {
            let model = segmentation(type, segments: [
                segment(1, trackingID: "Lesion 1", trackingUID: trackingUID),
            ])
            let dataSet = try model.buildDataSet(pixelData: Data(count: 8))
            let item = try XCTUnwrap(dataSet.sequence(for: .segmentSequence)?.first, "\(type)")

            let id = try XCTUnwrap(item[.trackingID], "\(type)")
            XCTAssertEqual(id.vr, .UT)
            XCTAssertEqual(item.string(for: .trackingID), "Lesion 1")
            let uid = try XCTUnwrap(item[.trackingUID], "\(type)")
            XCTAssertEqual(uid.vr, .UI)
            XCTAssertEqual(item.string(for: .trackingUID), trackingUID)

            let parsed = try SegmentationParser.parse(from: dataSet)
            XCTAssertEqual(parsed.segments.first?.trackingID, "Lesion 1", "\(type)")
            XCTAssertEqual(parsed.segments.first?.trackingUID, trackingUID, "\(type)")
        }
    }

    func testNeitherIsAccepted() throws {
        let dataSet = try segmentation(.binary, segments: [segment(1)])
            .buildDataSet(pixelData: Data(count: 8))
        let item = try XCTUnwrap(dataSet.sequence(for: .segmentSequence)?.first)
        XCTAssertNil(item[.trackingID])
        XCTAssertNil(item[.trackingUID])
    }

    // MARK: - One without the other throws, for every Segmentation Type

    func testTrackingIDWithoutUIDThrows() {
        for type in SegmentationType.allCases {
            let model = segmentation(type, segments: [
                segment(1, trackingID: "Lesion 1", trackingUID: trackingUID),
                segment(2, trackingID: "Lesion 2"),
            ])
            XCTAssertThrowsError(try model.buildDataSet(pixelData: Data(count: 8))) { error in
                XCTAssertEqual(error as? SegmentationDataSetError,
                               .missingTrackingUID(segmentNumber: 2), "\(type)")
            }
        }
    }

    func testTrackingUIDWithoutIDThrows() {
        for type in SegmentationType.allCases {
            let model = segmentation(type, segments: [
                segment(3, trackingUID: trackingUID),
            ])
            XCTAssertThrowsError(try model.buildDataSet(pixelData: Data(count: 8))) { error in
                XCTAssertEqual(error as? SegmentationDataSetError,
                               .missingTrackingID(segmentNumber: 3), "\(type)")
            }
        }
    }

    /// A Type 1C attribute that is present has the Type 1 requirements, a non-empty Value (PS3.5 2026a 7.4.2, 7.4.1), so an empty or
    /// all-space partner does not satisfy the condition.
    func testBlankPartnerDoesNotCount() {
        let blankUID = segmentation(.binary, segments: [segment(1, trackingID: "Lesion 1", trackingUID: "  ")])
        XCTAssertThrowsError(try blankUID.buildDataSet(pixelData: Data(count: 8))) { error in
            XCTAssertEqual(error as? SegmentationDataSetError, .missingTrackingUID(segmentNumber: 1))
        }
        let blankID = segmentation(.binary, segments: [segment(1, trackingID: "", trackingUID: trackingUID)])
        XCTAssertThrowsError(try blankID.buildDataSet(pixelData: Data(count: 8))) { error in
            XCTAssertEqual(error as? SegmentationDataSetError, .missingTrackingID(segmentNumber: 1))
        }
    }

    func testDescriptionsCiteTable() {
        XCTAssertTrue(SegmentationDataSetError.missingTrackingUID(segmentNumber: 2).description
            .contains("Tracking UID (0062,0021) is required when Tracking ID (0062,0020) is present (PS3.3 Table C.8.20-4)"))
        XCTAssertTrue(SegmentationDataSetError.missingTrackingID(segmentNumber: 2).description
            .contains("Tracking ID (0062,0020) is required when Tracking UID (0062,0021) is present (PS3.3 Table C.8.20-4)"))
    }
}
