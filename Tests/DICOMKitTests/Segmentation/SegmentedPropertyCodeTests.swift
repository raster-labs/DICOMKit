//
// SegmentedPropertyCodeTests.swift
// DICOMKit
//
// Segmented Property Category Code Sequence (0062,0003) and Segmented Property Type Code
// Sequence (0062,000F) are Type 1 in the Segment Description Macro, each with "Only a single
// Item" (PS3.3 2026a Table C.8.20-4; Baseline CID 7150 and CID 7151). D37 d:
// `Segmentation.buildDataSet(pixelData:)` throws when a segment lacks either, for every
// Segmentation Type. Tags per PS3.6 2026a Table 6-1. Codes: SCT 91723000 "Anatomical
// Structure" is in CID 7150; SCT 10200004 "Liver" is in CID 7154, included in CID 7151
// through CID 7192 (PS3.16 2026a).
//

import XCTest
@testable import DICOMKit
import DICOMCore

final class SegmentedPropertyCodeTests: XCTestCase {

    private let anatomicalStructure = CodedConcept(codeValue: "91723000", codingSchemeDesignator: "SCT", codeMeaning: "Anatomical Structure")
    private let liver = CodedConcept(codeValue: "10200004", codingSchemeDesignator: "SCT", codeMeaning: "Liver")

    func testTagsMatchPS36() {
        XCTAssertEqual(Tag.segmentedPropertyCategoryCodeSequence, Tag(group: 0x0062, element: 0x0003))
        XCTAssertEqual(Tag.segmentedPropertyTypeCodeSequence, Tag(group: 0x0062, element: 0x000F))
    }

    // MARK: - Always written, one Item each

    func testBuildDataSetWritesOneItemOfEach() throws {
        let (segmentation, pixelData) = try SegmentationBuilder(
            rows: 1, columns: 8, segmentationType: .binary,
            studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4")
            .addBinarySegment(number: 1, label: "Liver", mask: [1, 1, 0, 0, 0, 0, 0, 0],
                              category: anatomicalStructure, type: liver)
            .build()
        let dataSet = try segmentation.buildDataSet(pixelData: pixelData)
        let item = try XCTUnwrap(dataSet.sequence(for: .segmentSequence)?.first)

        let category = try XCTUnwrap(item[.segmentedPropertyCategoryCodeSequence])
        XCTAssertEqual(category.vr, .SQ)
        XCTAssertEqual(category.sequenceItems?.count, 1)
        XCTAssertEqual(category.sequenceItems?.first?.string(for: .codeValue), "91723000")
        XCTAssertEqual(category.sequenceItems?.first?.string(for: .codingSchemeDesignator), "SCT")
        XCTAssertEqual(category.sequenceItems?.first?.string(for: .codeMeaning), "Anatomical Structure")

        let type = try XCTUnwrap(item[.segmentedPropertyTypeCodeSequence])
        XCTAssertEqual(type.vr, .SQ)
        XCTAssertEqual(type.sequenceItems?.count, 1)
        XCTAssertEqual(type.sequenceItems?.first?.string(for: .codeValue), "10200004")

        let parsed = try SegmentationParser.parse(from: dataSet)
        XCTAssertEqual(parsed.segments.first?.category, anatomicalStructure)
        XCTAssertEqual(parsed.segments.first?.type, liver)
    }

    // MARK: - Missing codes throw, for every Segmentation Type

    private func segmentation(_ type: SegmentationType, segments: [Segment]) -> Segmentation {
        Segmentation(
            sopInstanceUID: "1.2.3.9", seriesInstanceUID: "1.2.3.4", studyInstanceUID: "1.2.3",
            segmentationType: type,
            numberOfSegments: segments.count, segments: segments,
            numberOfFrames: 1, rows: 1, columns: 8,
            bitsAllocated: type == .binary ? 1 : 8, bitsStored: type == .binary ? 1 : 8,
            highBit: type == .binary ? 0 : 7)
    }

    func testMissingCategoryThrows() {
        for type in SegmentationType.allCases {
            let model = segmentation(type, segments: [
                Segment(segmentNumber: 1, segmentLabel: "A", category: anatomicalStructure, type: liver),
                Segment(segmentNumber: 2, segmentLabel: "B", type: liver),
            ])
            XCTAssertThrowsError(try model.buildDataSet(pixelData: Data(count: 8))) { error in
                XCTAssertEqual(error as? SegmentationDataSetError,
                               .missingSegmentedPropertyCategory(segmentNumber: 2), "\(type)")
            }
        }
    }

    func testMissingTypeThrows() {
        for type in SegmentationType.allCases {
            let model = segmentation(type, segments: [
                Segment(segmentNumber: 1, segmentLabel: "A", category: anatomicalStructure),
            ])
            XCTAssertThrowsError(try model.buildDataSet(pixelData: Data(count: 8))) { error in
                XCTAssertEqual(error as? SegmentationDataSetError,
                               .missingSegmentedPropertyType(segmentNumber: 1), "\(type)")
            }
        }
    }

    func testBuilderWithoutCodesBuildsButCannotBeWritten() throws {
        // The builder keeps its optional parameters; the Type 1 rule is enforced where the
        // IOD is written.
        let (segmentation, pixelData) = try SegmentationBuilder(
            rows: 1, columns: 2, segmentationType: .labelmap,
            studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4")
            .addLabelmapSegment(number: 0, label: "Background")
            .addLabelmapFrame([0, 0])
            .build()
        XCTAssertNil(segmentation.segments.first?.category)
        XCTAssertThrowsError(try segmentation.buildDataSet(pixelData: pixelData)) { error in
            XCTAssertEqual(error as? SegmentationDataSetError, .missingSegmentedPropertyCategory(segmentNumber: 0))
            XCTAssertTrue("\(error)".contains("(0062,0003)"))
        }
    }
}
