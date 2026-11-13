import Foundation
import XCTest
import DICOMCore
@testable import DICOMKit

final class SegmentationNativeGeometryTests: XCTestCase {
    private func builder(rows: Int = 3, columns: Int = 3) -> SegmentationBuilder {
        SegmentationBuilder(rows: rows, columns: columns, segmentationType: .binary,
                            studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4")
    }

    private func add(_ builder: SegmentationBuilder, number: Int, mask: [UInt8]) throws {
        _ = try builder.addBinarySegment(number: number, label: "Synthetic \(number)", mask: mask,
            category: CodedConcept(codeValue: "49755003", codingSchemeDesignator: "SCT", codeMeaning: "Morphologically Abnormal Structure"),
            type: CodedConcept(codeValue: "108369006", codingSchemeDesignator: "SCT", codeMeaning: "Tumor"))
    }

    func testContinuousNineBitFrames() throws {
        // Independent PS3.5 bitstream: 18 set bits, followed by value-field padding.
        let data = Data([0xff, 0xff, 0x03, 0x00])
        for frame in 0..<2 {
            XCTAssertEqual(SegmentationPixelDataExtractor.extractBinaryFrame(from: data,
                frameIndex: frame, rows: 3, columns: 3), Array(repeating: 1, count: 9))
        }
    }

    func testBuilderConcatenatesBitsAcrossSegments() throws {
        let b = builder()
        try add(b, number: 2, mask: Array(repeating: 1, count: 9))
        try add(b, number: 1, mask: Array(repeating: 1, count: 9))
        let (segmentation, data) = try b.build()
        XCTAssertEqual(data, Data([0xff, 0xff, 0x03, 0x00]))
        XCTAssertEqual(segmentation.perFrameFunctionalGroups.map { $0.segmentIdentification?.referencedSegmentNumber }, [1, 2])
    }

    func testAllBitOffsetsAndSegmentOrder() throws {
        // Nine frames walk all eight start-bit offsets. Build expected bytes
        // independently from masks, then verify every frame and segment mapping.
        for dimensions in [(1, 1), (1, 7), (3, 3), (1, 15), (2, 8)] {
            let (rows, columns) = dimensions, pixels = rows * columns
            let masks = (0..<9).map { frame in
                (0..<pixels).map { UInt8(($0 + frame) % 3 == 0 ? 1 : 0) }
            }
            let b = builder(rows: rows, columns: columns)
            for frame in (0..<9).reversed() { try add(b, number: frame + 1, mask: masks[frame]) }
            let (seg, data) = try b.build()
            var expected = Data(repeating: 0, count: ((pixels * 9 + 15) / 16) * 2)
            for (bit, value) in masks.flatMap({ $0 }).enumerated() where value == 1 {
                expected[bit / 8] |= UInt8(1 << (bit % 8))
            }
            XCTAssertEqual(data, expected)
            for frame in 0..<9 {
                XCTAssertEqual(SegmentationPixelDataExtractor.extractBinaryFrame(from: data,
                    frameIndex: frame, rows: rows, columns: columns), masks[frame])
                XCTAssertEqual(SegmentationPixelDataExtractor.extractSegmentMask(from: seg,
                    segmentNumber: frame + 1, pixelData: data), masks[frame])
            }
        }
    }

    func testBinaryBoundsAndSlicedData() throws {
        let data = Data([0x12, 0xff, 0xff, 0x03, 0x00]).dropFirst()
        XCTAssertEqual(SegmentationPixelDataExtractor.extractBinaryFrame(from: data,
            frameIndex: 1, rows: 3, columns: 3), Array(repeating: 1, count: 9))
        for args in [(Int.max, 2, 0), (3, 3, Int.max), (1, 1, Int.max), (0, 3, 0), (3, 3, -1)] {
            XCTAssertNil(SegmentationPixelDataExtractor.extractBinaryFrame(from: data,
                frameIndex: args.2, rows: args.0, columns: args.1))
        }
        XCTAssertNil(SegmentationPixelDataExtractor.extractBinaryFrame(from: Data([0xff, 0xff]),
            frameIndex: 1, rows: 3, columns: 3))
        XCTAssertThrowsError(try add(builder(rows: Int.max, columns: 2), number: 1, mask: []))
        XCTAssertThrowsError(try add(builder(rows: -3, columns: -3), number: 1, mask: Array(repeating: 0, count: 9)))
    }

    private func serialized(_ dataSet: DataSet) throws -> DataSet {
        let file = try DICOMFile.create(dataSet: dataSet)
        return try DICOMFile.read(from: file.write()).dataSet
    }

    func testSharedPixelMeasuresFileRoundTrip() throws {
        let measures = PixelMeasures(pixelSpacing: [0.625, 0.9375], sliceThickness: 2.5,
                                     spacingBetweenSlices: 3.25)
        let b = builder().setFrameOfReference("1.2.3.5").setPixelMeasures(measures)
        try add(b, number: 1, mask: Array(repeating: 1, count: 9))
        try add(b, number: 2, mask: Array(repeating: 1, count: 9))
        let (seg, pixels) = try b.build()
        XCTAssertEqual(seg.sharedFunctionalGroups?.pixelMeasures, measures)
        let ds = try serialized(seg.buildDataSet(pixelData: pixels))
        let shared = try XCTUnwrap(ds.sequence(for: .sharedFunctionalGroupsSequence)?.first)
        let item = try XCTUnwrap(shared[.pixelMeasuresSequence]?.sequenceItems?.first)
        XCTAssertEqual(item[.pixelSpacing]?.vr, .DS)
        XCTAssertEqual(item[.pixelSpacing]?.decimalStringValues?.map(\.value), [0.625, 0.9375])
        let parsed = try SegmentationParser.parse(from: ds)
        XCTAssertEqual(parsed.sharedFunctionalGroups?.pixelMeasures, measures)
        XCTAssertEqual(parsed.frameOfReferenceUID, "1.2.3.5")
        XCTAssertEqual(ds[.pixelData]?.valueData, Data([0xff, 0xff, 0x03, 0]))
    }

    func testPerFramePixelMeasuresSurviveDimensionContentCompletion() throws {
        let b = builder()
        try add(b, number: 1, mask: Array(repeating: 0, count: 9))
        try add(b, number: 2, mask: Array(repeating: 1, count: 9))
        let (original, pixels) = try b.build()
        var ds = try original.buildDataSet(pixelData: pixels)
        let measures = [PixelMeasures(pixelSpacing: [0.5, 0.75], sliceThickness: 1),
                        PixelMeasures(pixelSpacing: [1.5, 2.25], sliceThickness: 2, spacingBetweenSlices: 0)]
        ds.setSequence(try measures.enumerated().map { index, value in
            let groupBuilder = builder().setPixelMeasures(value)
            try add(groupBuilder, number: index + 1, mask: Array(repeating: 0, count: 9))
            let (seg, data) = try groupBuilder.build()
            let groupDS = try seg.buildDataSet(pixelData: data)
            let calibration = try XCTUnwrap(groupDS.sequence(for: .sharedFunctionalGroupsSequence)?.first?[.pixelMeasuresSequence])
            return SequenceItem(elements: [calibration,
                DataElement(tag: .segmentIdentificationSequence, vr: .SQ, length: 0, valueData: Data(),
                            sequenceItems: [SequenceItem(elements: [DataElement.uint16(tag: .referencedSegmentNumber, value: UInt16(index + 1))])])])
        }, for: .perFrameFunctionalGroupsSequence)
        // Parsing has no dimension content, so the writer's reconstruction path must carry calibration.
        let parsed = try SegmentationParser.parse(from: ds)
        let reread = try SegmentationParser.parse(from: serialized(parsed.buildDataSet(pixelData: pixels)))
        XCTAssertNil(reread.sharedFunctionalGroups?.pixelMeasures)
        XCTAssertEqual(reread.perFrameFunctionalGroups.map(\.pixelMeasures), measures.map(Optional.some))
        XCTAssertEqual(reread.perFrameFunctionalGroups.map { $0.frameContent?.dimensionIndexValues }, [[1], [2]])
    }

    func testPixelMeasuresRejectInvalidModelValues() throws {
        for measures in [PixelMeasures(pixelSpacing: [1]), PixelMeasures(pixelSpacing: [1, 2, 3]),
                         PixelMeasures(pixelSpacing: [.nan, 1]), PixelMeasures(pixelSpacing: [0, 1]),
                         PixelMeasures(pixelSpacing: [1, -1]), PixelMeasures(sliceThickness: 0),
                         PixelMeasures(sliceThickness: .infinity), PixelMeasures(spacingBetweenSlices: -1)] {
            let b = builder().setPixelMeasures(measures)
            try add(b, number: 1, mask: Array(repeating: 0, count: 9))
            XCTAssertThrowsError(try b.build())
        }
        let b = builder(rows: 1, columns: 1).setPixelMeasures(PixelMeasures(pixelSpacing: [0, 0]))
        try add(b, number: 1, mask: [0])
        let (seg, data) = try b.build()
        let parsed = try SegmentationParser.parse(from: serialized(seg.buildDataSet(pixelData: data)))
        XCTAssertEqual(parsed.sharedFunctionalGroups?.pixelMeasures?.pixelSpacing, [0, 0])
        XCTAssertNil(parsed.sharedFunctionalGroups?.pixelMeasures?.sliceThickness)
    }

    func testPixelMeasuresRejectMalformedSequenceAndDecimalValues() throws {
        let b = builder()
        try add(b, number: 1, mask: Array(repeating: 0, count: 9))
        let (seg, data) = try b.build()
        let original = try seg.buildDataSet(pixelData: data)
        for text in ["0.5\\BAD", "0.5\\", "0.5\\0.75\\1", "0.5\\NaN", "0.5\\-1", "0\\1", "0.5\\0x1p0"] {
            var ds = original
            let item = SequenceItem(elements: [DataElement.string(tag: .pixelSpacing, vr: .DS, value: text)])
            ds.setSequence([SequenceItem(elements: [DataElement(tag: .pixelMeasuresSequence, vr: .SQ,
                length: 0, valueData: Data(), sequenceItems: [item])])], for: .sharedFunctionalGroupsSequence)
            XCTAssertThrowsError(try SegmentationParser.parse(from: ds), text)
        }
        for items in [[], [SequenceItem(), SequenceItem()]] {
            var ds = original
            ds.setSequence([SequenceItem(elements: [DataElement(tag: .pixelMeasuresSequence, vr: .SQ,
                length: 0, valueData: Data(), sequenceItems: items)])], for: .sharedFunctionalGroupsSequence)
            XCTAssertThrowsError(try SegmentationParser.parse(from: ds))
        }
    }
}
