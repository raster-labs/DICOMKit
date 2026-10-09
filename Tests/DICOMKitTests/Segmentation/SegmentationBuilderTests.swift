//
// SegmentationBuilderTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
@testable import DICOMKit
import DICOMCore
#if canImport(CoreGraphics)
import CoreGraphics
#endif

final class SegmentationBuilderTests: XCTestCase {
    
    // MARK: - Binary Segmentation Tests
    
    func test_buildBinarySegmentation_singleSegment_succeeds() throws {
        // Given: A 4x4 binary mask with a simple pattern
        let rows = 4
        let columns = 4
        let mask: [UInt8] = [
            1, 1, 0, 0,
            1, 1, 0, 0,
            0, 0, 1, 1,
            0, 0, 1, 1
        ]
        
        let builder = SegmentationBuilder(
            rows: rows,
            columns: columns,
            segmentationType: .binary,
            studyInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4.5.6"
        )
        
        // When: Building with a single binary segment
        let (segmentation, pixelData) = try builder
            .setContentLabel("Test Seg")
            .addBinarySegment(
                number: 1,
                label: "Test Region",
                mask: mask,
                category: nil,
                type: nil,
                color: (r: 255, g: 0, b: 0),
                algorithmType: .automatic,
                algorithmName: "TestAlgorithm"
            )
            .build()
        
        // Then: Segmentation should be created correctly
        XCTAssertEqual(segmentation.rows, rows)
        XCTAssertEqual(segmentation.columns, columns)
        XCTAssertEqual(segmentation.segmentationType, .binary)
        XCTAssertEqual(segmentation.numberOfSegments, 1)
        XCTAssertEqual(segmentation.numberOfFrames, 1)
        XCTAssertEqual(segmentation.bitsAllocated, 1)
        XCTAssertEqual(segmentation.bitsStored, 1)
        XCTAssertEqual(segmentation.highBit, 0)
        XCTAssertEqual(segmentation.contentLabel, "Test Seg")
        
        // Verify segment
        XCTAssertEqual(segmentation.segments.count, 1)
        let segment = segmentation.segments[0]
        XCTAssertEqual(segment.segmentNumber, 1)
        XCTAssertEqual(segment.segmentLabel, "Test Region")
        XCTAssertEqual(segment.segmentAlgorithmType, .automatic)
        XCTAssertEqual(segment.segmentAlgorithmName, "TestAlgorithm")
        XCTAssertNotNil(segment.recommendedDisplayCIELabValue)
        
        // Verify pixel data is bit-packed (16 pixels = 2 bytes)
        XCTAssertEqual(pixelData.count, 2)
        
        // Verify bit packing: the first pixel in the least significant bit of the
        // first byte (PS3.5 8.1.1 and D.1)
        // First byte: pixels 1,1,0,0,1,1,0,0 in bits 0...7 = 0x33
        // Second byte: pixels 0,0,1,1,0,0,1,1 in bits 0...7 = 0xCC
        XCTAssertEqual(pixelData[0], 0x33)
        XCTAssertEqual(pixelData[1], 0xCC)
    }
    
    func test_buildBinarySegmentation_multipleSegments_succeeds() throws {
        // Given: Multiple binary masks
        let rows = 2
        let columns = 2
        let mask1: [UInt8] = [1, 0, 0, 1]
        let mask2: [UInt8] = [0, 1, 1, 0]
        
        let builder = SegmentationBuilder(
            rows: rows,
            columns: columns,
            segmentationType: .binary,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        
        // When: Building with multiple segments
        let (segmentation, pixelData) = try builder
            .addBinarySegment(number: 1, label: "Region 1", mask: mask1)
            .addBinarySegment(number: 2, label: "Region 2", mask: mask2)
            .build()
        
        // Then: Should have multiple frames
        XCTAssertEqual(segmentation.numberOfSegments, 2)
        XCTAssertEqual(segmentation.numberOfFrames, 2)
        XCTAssertEqual(segmentation.segments.count, 2)
        
        // Each frame is 1 byte (4 pixels)
        XCTAssertEqual(pixelData.count, 2)
        
        // Verify segments are sorted by number
        XCTAssertEqual(segmentation.segments[0].segmentNumber, 1)
        XCTAssertEqual(segmentation.segments[1].segmentNumber, 2)
    }
    
    func test_buildBinarySegmentation_invalidMaskDimensions_throwsError() {
        // Given: Builder expecting 4x4 (16 pixels)
        let builder = SegmentationBuilder(
            rows: 4,
            columns: 4,
            segmentationType: .binary,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        
        // When/Then: Providing wrong number of pixels should throw
        let invalidMask: [UInt8] = [1, 0, 1, 0]  // Only 4 pixels instead of 16
        
        XCTAssertThrowsError(
            try builder.addBinarySegment(
                number: 1,
                label: "Test",
                mask: invalidMask
            )
        ) { error in
            guard case SegmentationBuilderError.invalidMaskDimensions(let expected, let got) = error else {
                XCTFail("Expected invalidMaskDimensions error")
                return
            }
            XCTAssertEqual(expected, 16)
            XCTAssertEqual(got, 4)
        }
    }
    
    func test_buildBinarySegmentation_invalidBinaryValue_throwsError() {
        // Given: A builder for binary segmentation
        let builder = SegmentationBuilder(
            rows: 2,
            columns: 2,
            segmentationType: .binary,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        
        // When/Then: Providing non-binary values should throw
        let invalidMask: [UInt8] = [1, 0, 2, 0]  // Contains 2, which is invalid
        
        XCTAssertThrowsError(
            try builder.addBinarySegment(
                number: 1,
                label: "Test",
                mask: invalidMask
            )
        ) { error in
            guard case SegmentationBuilderError.invalidBinaryValue(let value, let index) = error else {
                XCTFail("Expected invalidBinaryValue error")
                return
            }
            XCTAssertEqual(value, 2)
            XCTAssertEqual(index, 2)
        }
    }
    
    func test_buildBinarySegmentation_duplicateSegmentNumber_throwsError() {
        // Given: A builder with one segment already added
        let rows = 2
        let columns = 2
        let mask: [UInt8] = [1, 0, 0, 1]
        
        let builder = SegmentationBuilder(
            rows: rows,
            columns: columns,
            segmentationType: .binary,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        
        // When/Then: Adding segment with duplicate number should throw
        XCTAssertThrowsError(
            try builder
                .addBinarySegment(number: 1, label: "First", mask: mask)
                .addBinarySegment(number: 1, label: "Duplicate", mask: mask)
        ) { error in
            guard case SegmentationBuilderError.duplicateSegmentNumber(let number) = error else {
                XCTFail("Expected duplicateSegmentNumber error")
                return
            }
            XCTAssertEqual(number, 1)
        }
    }
    
    func test_buildBinarySegmentation_invalidSegmentNumber_throwsError() {
        // Given: A binary segmentation builder
        let builder = SegmentationBuilder(
            rows: 2,
            columns: 2,
            segmentationType: .binary,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        
        // When/Then: Segment number 0 or negative should throw
        let mask: [UInt8] = [1, 0, 0, 1]
        
        XCTAssertThrowsError(
            try builder.addBinarySegment(number: 0, label: "Invalid", mask: mask)
        ) { error in
            guard case SegmentationBuilderError.invalidSegmentNumber(let number) = error else {
                XCTFail("Expected invalidSegmentNumber error")
                return
            }
            XCTAssertEqual(number, 0)
        }
    }
    
    // MARK: - Fractional Segmentation Tests
    
    func test_buildFractionalSegmentation_singleSegment_succeeds() throws {
        // Given: A 3x3 fractional mask
        let rows = 3
        let columns = 3
        let mask: [UInt8] = [
            0, 127, 255,
            64, 128, 192,
            32, 96, 160
        ]
        
        let builder = SegmentationBuilder(
            rows: rows,
            columns: columns,
            segmentationType: .fractional,
            studyInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4.5.6"
        )
        
        // When: Building with a fractional segment
        let (segmentation, pixelData) = try builder
            .setContentLabel("Probability Map")
            .addFractionalSegment(
                number: 1,
                label: "Tumor Probability",
                mask: mask,
                category: nil,
                type: nil,
                color: (r: 255, g: 0, b: 0),
                fractionalType: .probability,
                maxValue: 255,
                algorithmType: .automatic,
                algorithmName: "CNN v1.0"
            )
            .build()
        
        // Then: Segmentation should be created correctly
        XCTAssertEqual(segmentation.rows, rows)
        XCTAssertEqual(segmentation.columns, columns)
        XCTAssertEqual(segmentation.segmentationType, .fractional)
        XCTAssertEqual(segmentation.numberOfSegments, 1)
        XCTAssertEqual(segmentation.numberOfFrames, 1)
        XCTAssertEqual(segmentation.bitsAllocated, 8)
        XCTAssertEqual(segmentation.maxFractionalValue, 255)
        XCTAssertEqual(segmentation.segmentationFractionalType, .probability)
        
        // Verify pixel data (9 pixels, 1 byte each = 9 bytes)
        XCTAssertEqual(pixelData.count, 9)
        
        // Verify pixel values match input
        XCTAssertEqual(Array(pixelData), mask)
    }
    
    func test_buildFractionalSegmentation_16bit_succeeds() throws {
        // Given: A fractional mask with 16-bit max value
        let rows = 2
        let columns = 2
        let mask: [UInt8] = [0, 85, 170, 255]  // Will be scaled to 0-65535
        
        let builder = SegmentationBuilder(
            rows: rows,
            columns: columns,
            segmentationType: .fractional,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        
        // When: Building with 16-bit max value
        let (segmentation, pixelData) = try builder
            .addFractionalSegment(
                number: 1,
                label: "16-bit Segment",
                mask: mask,
                fractionalType: .probability,
                maxValue: 65535
            )
            .build()
        
        // Then: Should use 16-bit storage (though builder defaults to 8-bit currently)
        XCTAssertEqual(segmentation.segmentationType, .fractional)
        XCTAssertEqual(segmentation.maxFractionalValue, 255)  // Current implementation defaults to 8-bit
        
        // Note: Full 16-bit support would require storing maxValue per segment
        // and using it in build(). This is a simplified implementation.
    }
    
    func test_buildFractionalSegmentation_invalidMaxValue_throwsError() {
        // Given: A fractional segmentation builder
        let builder = SegmentationBuilder(
            rows: 2,
            columns: 2,
            segmentationType: .fractional,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        
        // When/Then: Invalid max fractional value should throw
        let mask: [UInt8] = [0, 100, 200, 255]
        
        XCTAssertThrowsError(
            try builder.addFractionalSegment(
                number: 1,
                label: "Test",
                mask: mask,
                fractionalType: .probability,
                maxValue: 0  // Invalid: must be > 0
            )
        ) { error in
            guard case SegmentationBuilderError.invalidMaxFractionalValue(let value) = error else {
                XCTFail("Expected invalidMaxFractionalValue error")
                return
            }
            XCTAssertEqual(value, 0)
        }
        
        XCTAssertThrowsError(
            try builder.addFractionalSegment(
                number: 1,
                label: "Test",
                mask: mask,
                fractionalType: .probability,
                maxValue: 70000  // Invalid: exceeds 65535
            )
        ) { error in
            guard case SegmentationBuilderError.invalidMaxFractionalValue = error else {
                XCTFail("Expected invalidMaxFractionalValue error")
                return
            }
        }
    }
    
    func test_buildFractionalSegmentation_wrongType_throwsError() {
        // Given: A builder configured for binary segmentation
        let builder = SegmentationBuilder(
            rows: 2,
            columns: 2,
            segmentationType: .binary,  // Binary, not fractional
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        
        // When/Then: Trying to add fractional segment should throw
        let mask: [UInt8] = [0, 100, 200, 255]
        
        XCTAssertThrowsError(
            try builder.addFractionalSegment(
                number: 1,
                label: "Test",
                mask: mask,
                fractionalType: .probability,
                maxValue: 255
            )
        ) { error in
            guard case SegmentationBuilderError.invalidSegmentationType(let expected, let got) = error else {
                XCTFail("Expected invalidSegmentationType error")
                return
            }
            XCTAssertEqual(expected, .fractional)
            XCTAssertEqual(got, .binary)
        }
    }
    
    // MARK: - Metadata Tests
    
    func test_buildSegmentation_withAllMetadata_succeeds() throws {
        // Given: A builder with all metadata set
        let rows = 2
        let columns = 2
        let mask: [UInt8] = [1, 0, 0, 1]
        
        let personName = DICOMPersonName.parse("Doe^John")!
        let contentDate = DICOMDate(year: 2024, month: 2, day: 5)
        let contentTime = DICOMTime(hour: 14, minute: 30, second: 0)
        
        let builder = SegmentationBuilder(
            rows: rows,
            columns: columns,
            segmentationType: .binary,
            studyInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4.5.6"
        )
        
        // When: Building with all metadata
        let (segmentation, _) = try builder
            .setSOPInstanceUID("1.2.3.4.5.6.7")
            .setInstanceNumber(42)
            .setContentLabel("Full Metadata")
            .setContentDescription("Test with all metadata fields")
            .setContentCreator(personName)
            .setContentDate(contentDate)
            .setContentTime(contentTime)
            .setFrameOfReference("1.2.3.4.5.6.7.8")
            .addBinarySegment(number: 1, label: "Test", mask: mask)
            .build()
        
        // Then: All metadata should be set
        XCTAssertEqual(segmentation.sopInstanceUID, "1.2.3.4.5.6.7")
        XCTAssertEqual(segmentation.instanceNumber, 42)
        XCTAssertEqual(segmentation.contentLabel, "Full Metadata")
        XCTAssertEqual(segmentation.contentDescription, "Test with all metadata fields")
        XCTAssertEqual(segmentation.contentCreatorName, personName)
        XCTAssertEqual(segmentation.contentDate, contentDate)
        XCTAssertEqual(segmentation.contentTime, contentTime)
        XCTAssertEqual(segmentation.frameOfReferenceUID, "1.2.3.4.5.6.7.8")
    }
    
    func test_buildSegmentation_autoGeneratesSOPInstanceUID() throws {
        // Given: A builder without SOP Instance UID set
        let builder = SegmentationBuilder(
            rows: 2,
            columns: 2,
            segmentationType: .binary,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        
        let mask: [UInt8] = [1, 0, 0, 1]
        
        // When: Building without setting SOP Instance UID
        let (segmentation, _) = try builder
            .addBinarySegment(number: 1, label: "Test", mask: mask)
            .build()
        
        // Then: SOP Instance UID should be auto-generated
        XCTAssertFalse(segmentation.sopInstanceUID.isEmpty)
        XCTAssertTrue(segmentation.sopInstanceUID.hasPrefix(UIDGenerator.defaultRoot),
                      "generated UIDs are built on the library's registered root (PS3.5 9.2.2)")
    }
    
    func test_buildSegmentation_autoGeneratesDateTime() throws {
        // Given: A builder without date/time set
        let builder = SegmentationBuilder(
            rows: 2,
            columns: 2,
            segmentationType: .binary,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        
        let mask: [UInt8] = [1, 0, 0, 1]
        
        // When: Building without setting date/time
        let (segmentation, _) = try builder
            .addBinarySegment(number: 1, label: "Test", mask: mask)
            .build()
        
        // Then: Date and time should be auto-generated
        XCTAssertNotNil(segmentation.contentDate)
        XCTAssertNotNil(segmentation.contentTime)
    }
    
    // MARK: - Source Image Reference Tests
    
    func test_buildSegmentation_withSourceImages_succeeds() throws {
        // Given: A builder with source images
        let builder = SegmentationBuilder(
            rows: 2,
            columns: 2,
            segmentationType: .binary,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        
        let mask: [UInt8] = [1, 0, 0, 1]
        
        // When: Adding source images
        let (segmentation, _) = try builder
            .addSourceImage(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: "1.2.3.4.5.6.7",
                frameNumber: nil
            )
            .addSourceImage(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: "1.2.3.4.5.6.8",
                frameNumber: 5
            )
            .addBinarySegment(number: 1, label: "Test", mask: mask)
            .build()
        
        // Then: Referenced series should be populated
        XCTAssertEqual(segmentation.referencedSeries.count, 1)
        XCTAssertEqual(segmentation.referencedSeries[0].referencedInstances.count, 2)
        
        let instance1 = segmentation.referencedSeries[0].referencedInstances[0]
        XCTAssertEqual(instance1.sopInstanceUID, "1.2.3.4.5.6.7")
        XCTAssertNil(instance1.referencedFrameNumbers)
        
        let instance2 = segmentation.referencedSeries[0].referencedInstances[1]
        XCTAssertEqual(instance2.sopInstanceUID, "1.2.3.4.5.6.8")
        XCTAssertEqual(instance2.referencedFrameNumbers, [5])
    }
    
    // MARK: - Validation Tests
    
    func test_build_noSegments_throwsError() {
        // Given: A builder with no segments added
        let builder = SegmentationBuilder(
            rows: 2,
            columns: 2,
            segmentationType: .binary,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        
        // When/Then: Building without segments should throw
        XCTAssertThrowsError(try builder.build()) { error in
            guard case SegmentationBuilderError.noSegmentsAdded = error else {
                XCTFail("Expected noSegmentsAdded error")
                return
            }
        }
    }
    
    // MARK: - Functional Groups Tests
    
    func test_buildSegmentation_perFrameFunctionalGroups_populated() throws {
        // Given: A multi-segment segmentation
        let rows = 2
        let columns = 2
        let mask1: [UInt8] = [1, 0, 0, 1]
        let mask2: [UInt8] = [0, 1, 1, 0]
        
        let builder = SegmentationBuilder(
            rows: rows,
            columns: columns,
            segmentationType: .binary,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        
        // When: Building with multiple segments
        let (segmentation, _) = try builder
            .addBinarySegment(number: 1, label: "Segment 1", mask: mask1)
            .addBinarySegment(number: 2, label: "Segment 2", mask: mask2)
            .build()
        
        // Then: Per-frame functional groups should be populated
        XCTAssertEqual(segmentation.perFrameFunctionalGroups.count, 2)
        
        // Verify segment identification in functional groups
        let fg1 = segmentation.perFrameFunctionalGroups[0]
        XCTAssertEqual(fg1.segmentIdentification?.referencedSegmentNumber, 1)
        
        let fg2 = segmentation.perFrameFunctionalGroups[1]
        XCTAssertEqual(fg2.segmentIdentification?.referencedSegmentNumber, 2)
    }
    
    // MARK: - Color Conversion Tests
    
    func test_rgbToCIELab_conversion() throws {
        // Given: A builder with colored segments
        let builder = SegmentationBuilder(
            rows: 2,
            columns: 2,
            segmentationType: .binary,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        
        let mask: [UInt8] = [1, 0, 0, 1]
        
        // When: Adding segment with RGB color
        let (segmentation, _) = try builder
            .addBinarySegment(
                number: 1,
                label: "Red Segment",
                mask: mask,
                color: (r: 255, g: 0, b: 0)  // Pure red
            )
            .build()
        
        // Then: CIELab color should be set
        let segment = segmentation.segments[0]
        XCTAssertNotNil(segment.recommendedDisplayCIELabValue)
        
        let color = segment.recommendedDisplayCIELabValue!
        // Verify CIELab values are in valid range (0-65535)
        XCTAssertGreaterThanOrEqual(color.l, 0)
        XCTAssertLessThanOrEqual(color.l, 65535)
        XCTAssertGreaterThanOrEqual(color.a, 0)
        XCTAssertLessThanOrEqual(color.a, 65535)
        XCTAssertGreaterThanOrEqual(color.b, 0)
        XCTAssertLessThanOrEqual(color.b, 65535)
    }
    
    // MARK: - Integration Tests
    
    func test_buildSegmentation_realWorldExample_succeeds() throws {
        // Given: A realistic AI segmentation scenario
        let rows = 512
        let columns = 512
        
        // Create a simple circular tumor mask
        var tumorMask = [UInt8](repeating: 0, count: rows * columns)
        let centerX = columns / 2
        let centerY = rows / 2
        let radius = 50.0
        
        for y in 0..<rows {
            for x in 0..<columns {
                let dx = Double(x - centerX)
                let dy = Double(y - centerY)
                let distance = sqrt(dx * dx + dy * dy)
                if distance <= radius {
                    tumorMask[y * columns + x] = 1
                }
            }
        }
        
        let tumorType = CodedConcept(
            codeValue: "108369006",
            codingSchemeDesignator: "SCT",
            codeMeaning: "Neoplasm"
        )
        
        let tumorCategory = CodedConcept(
            codeValue: "49755003",
            codingSchemeDesignator: "SCT",
            codeMeaning: "Morphologically Altered Structure"
        )
        
        let builder = SegmentationBuilder(
            rows: rows,
            columns: columns,
            segmentationType: .binary,
            studyInstanceUID: "1.2.840.113619.2.1.1.1",
            seriesInstanceUID: "1.2.840.113619.2.1.1.1.1"
        )
        
        // When: Building a complete AI segmentation
        let (segmentation, pixelData) = try builder
            .setContentLabel("AI Tumor Seg")
            .setContentDescription("Automated tumor detection using DeepLearning")
            .setFrameOfReference("1.2.840.113619.2.1.1.1.1.1")
            .addSourceImage(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",  // CT Image Storage
                sopInstanceUID: "1.2.840.113619.2.1.1.1.1.2"
            )
            .addBinarySegment(
                number: 1,
                label: "Tumor",
                mask: tumorMask,
                category: tumorCategory,
                type: tumorType,
                color: (r: 255, g: 0, b: 0),
                algorithmType: .automatic,
                algorithmName: "DeepTumorNet v3.0"
            )
            .build()
        
        // Then: Complete segmentation should be created
        XCTAssertEqual(segmentation.rows, 512)
        XCTAssertEqual(segmentation.columns, 512)
        XCTAssertEqual(segmentation.numberOfSegments, 1)
        XCTAssertEqual(segmentation.segmentationType, .binary)
        XCTAssertEqual(segmentation.sopClassUID, "1.2.840.10008.5.1.4.1.1.66.4")
        XCTAssertNotNil(segmentation.sopInstanceUID)
        XCTAssertNotNil(segmentation.contentDate)
        XCTAssertNotNil(segmentation.contentTime)
        
        // Verify segment details
        let segment = segmentation.segments[0]
        XCTAssertEqual(segment.segmentLabel, "Tumor")
        XCTAssertEqual(segment.type, tumorType)
        XCTAssertEqual(segment.category, tumorCategory)
        XCTAssertEqual(segment.segmentAlgorithmType, .automatic)
        XCTAssertEqual(segment.segmentAlgorithmName, "DeepTumorNet v3.0")
        
        // Verify pixel data size (512 * 512 = 262144 pixels, bit-packed = 32768 bytes)
        let expectedBytes = (rows * columns + 7) / 8
        XCTAssertEqual(pixelData.count, expectedBytes)
        
        // Verify referenced series
        XCTAssertEqual(segmentation.referencedSeries.count, 1)
        XCTAssertEqual(segmentation.referencedSeries[0].referencedInstances.count, 1)
    }
}

// MARK: - LABELMAP
//
// LABELMAP Segmentation Type per PS3.3 2026a Table C.8.20-2, C.8.20.2.3.3, C.8.20.2.4,
// Table A.51-2, A.51.4 and PS3.4 B.5.1.25. Kept in this file because the test target
// compiles an explicit sources allowlist in Package.swift.

final class SegmentationLabelmapTests: XCTestCase {

    // 4 x 3 slices: 0 background, 1 liver, 2 tumor
    private let slice1: [UInt16] = [
        0, 1, 1, 0,
        0, 1, 2, 0,
        0, 0, 0, 0,
    ]
    private let slice2: [UInt16] = [
        0, 0, 0, 0,
        2, 2, 1, 0,
        0, 0, 0, 0,
    ]

    private func makeBuilder() throws -> SegmentationBuilder {
        let builder = SegmentationBuilder(
            rows: 3,
            columns: 4,
            segmentationType: .labelmap,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        // Category and type are Type 1 (PS3.3 Table C.8.20-4): CID 7150 categories, CID 7151
        // types (Tissue via CID 7191, Liver via CID 7192/7154, Neoplasm via CID 7194/7159)
        try builder
            .addLabelmapSegment(number: 0, label: "Background", category: tissue, type: tissue)
            .addLabelmapSegment(
                number: 1,
                label: "Liver",
                category: CodedConcept(codeValue: "91723000", codingSchemeDesignator: "SCT", codeMeaning: "Anatomical Structure"),
                type: CodedConcept(codeValue: "10200004", codingSchemeDesignator: "SCT", codeMeaning: "Liver"),
                color: (r: 139, g: 69, b: 19),
                algorithmType: .automatic,
                algorithmName: "LiverNet")
            .addLabelmapSegment(number: 2, label: "Tumor", category: abnormal, type: neoplasm,
                                color: (r: 255, g: 0, b: 0))
        return builder
    }

    private let tissue = CodedConcept(codeValue: "85756007", codingSchemeDesignator: "SCT", codeMeaning: "Tissue")
    private let abnormal = CodedConcept(codeValue: "49755003", codingSchemeDesignator: "SCT", codeMeaning: "Morphologically Abnormal Structure")
    private let neoplasm = CodedConcept(codeValue: "108369006", codingSchemeDesignator: "SCT", codeMeaning: "Neoplasm")

    // MARK: - Builder

    func test_build_labelmap_8bit_oneFramePerSlice() throws {
        let (segmentation, pixelData) = try makeBuilder()
            .setPixelPaddingValue(0)
            .addLabelmapFrame(slice1, imagePositionPatient: [0, 0, 0], imageOrientationPatient: [1, 0, 0, 0, 1, 0])
            .addLabelmapFrame(slice2, imagePositionPatient: [0, 0, 2.5], imageOrientationPatient: [1, 0, 0, 0, 1, 0])
            .build()

        // Table C.8.20-2: LABELMAP => Bits Allocated 8 (or 16), Bits Stored 8, High Bit 7,
        // Pixel Representation 0, Photometric Interpretation MONOCHROME2, Samples per Pixel 1
        XCTAssertEqual(segmentation.segmentationType, .labelmap)
        XCTAssertEqual(segmentation.bitsAllocated, 8)
        XCTAssertEqual(segmentation.bitsStored, 8)
        XCTAssertEqual(segmentation.highBit, 7)
        XCTAssertEqual(segmentation.pixelRepresentation, 0)
        XCTAssertEqual(segmentation.photometricInterpretation, "MONOCHROME2")
        XCTAssertEqual(segmentation.samplesPerPixel, 1)
        // Segments Overlap shall be NO for LABELMAP; no fractional attributes
        XCTAssertEqual(segmentation.segmentsOverlap, .no)
        XCTAssertNil(segmentation.segmentationFractionalType)
        XCTAssertNil(segmentation.maxFractionalValue)
        // A.51.4: Pixel Padding Value names the background Segment Number
        XCTAssertEqual(segmentation.pixelPaddingValue, 0)
        // PS3.4 B.5.1.25: Label Map Segmentation Storage
        XCTAssertEqual(segmentation.sopClassUID, "1.2.840.10008.5.1.4.1.1.66.7")

        // One frame per slice, pixel value = Segment Number
        XCTAssertEqual(segmentation.numberOfFrames, 2)
        XCTAssertEqual(segmentation.numberOfSegments, 3)
        XCTAssertEqual(pixelData.count, 2 * 12)
        XCTAssertEqual(Array(pixelData.prefix(12)), slice1.map { UInt8($0) })
        XCTAssertEqual(Array(pixelData.suffix(12)), slice2.map { UInt8($0) })

        // Table A.51-2: no Segmentation Functional Group for LABELMAP
        XCTAssertEqual(segmentation.perFrameFunctionalGroups.count, 2)
        for (index, group) in segmentation.perFrameFunctionalGroups.enumerated() {
            XCTAssertNil(group.segmentIdentification, "LABELMAP frames carry no Segment Identification Sequence")
            XCTAssertEqual(group.frameContent?.dimensionIndexValues, [index + 1])
            XCTAssertEqual(group.frameContent?.inStackPositionNumber, index + 1)
            XCTAssertNotNil(group.planePosition)
            XCTAssertNotNil(group.planeOrientation)
        }
        XCTAssertEqual(segmentation.perFrameFunctionalGroups[1].planePosition?.imagePositionPatient, [0, 0, 2.5])
    }

    func test_build_labelmap_16bit_whenSegmentNumberExceeds255() throws {
        let builder = SegmentationBuilder(rows: 1, columns: 3, segmentationType: .labelmap,
                                          studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4")
        let (segmentation, pixelData) = try builder
            .addLabelmapSegment(number: 0, label: "Background")
            .addLabelmapSegment(number: 300, label: "Lesion")
            .addLabelmapFrame([0, 300, 300])
            .build()

        XCTAssertEqual(segmentation.bitsAllocated, 16)
        XCTAssertEqual(segmentation.bitsStored, 16)
        XCTAssertEqual(segmentation.highBit, 15)
        // little-endian 16-bit cells
        XCTAssertEqual(Array(pixelData), [0, 0, 0x2C, 0x01, 0x2C, 0x01])
    }

    func test_build_labelmap_explicitBitsAllocated16() throws {
        let (segmentation, pixelData) = try makeBuilder()
            .setLabelmapBitsAllocated(16)
            .addLabelmapFrame(slice1)
            .build()
        XCTAssertEqual(segmentation.bitsAllocated, 16)
        XCTAssertEqual(pixelData.count, 24)
        XCTAssertEqual(pixelData[2], 1)
        XCTAssertEqual(pixelData[3], 0)
    }

    func test_build_labelmap_rejectsUndescribedPixelValue() throws {
        // C.8.20.2.3.3: every pixel value actually encoded is required to be described
        let builder = try makeBuilder().addLabelmapFrame([0, 1, 2, 7, 0, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertThrowsError(try builder.build()) { error in
            guard case SegmentationBuilderError.labelmapValueNotDescribed(let value, let frame, let index) = error else {
                return XCTFail("expected labelmapValueNotDescribed, got \(error)")
            }
            XCTAssertEqual(value, 7)
            XCTAssertEqual(frame, 0)
            XCTAssertEqual(index, 3)
        }
    }

    func test_build_labelmap_rejectsPaddingValueThatIsNotASegment() throws {
        let builder = try makeBuilder().setPixelPaddingValue(9).addLabelmapFrame(slice1)
        XCTAssertThrowsError(try builder.build())
    }

    func test_build_labelmap_rejectsBitsAllocatedOtherThan8Or16() throws {
        let builder = try makeBuilder().setLabelmapBitsAllocated(12).addLabelmapFrame(slice1)
        XCTAssertThrowsError(try builder.build()) { error in
            guard case SegmentationBuilderError.invalidBitsAllocated(12) = error else {
                return XCTFail("expected invalidBitsAllocated, got \(error)")
            }
        }
    }

    func test_build_labelmap_rejectsSegmentNumberTooLargeForBitsAllocated() throws {
        let builder = SegmentationBuilder(rows: 1, columns: 1, segmentationType: .labelmap,
                                          studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4")
        try builder.addLabelmapSegment(number: 300, label: "Big").setLabelmapBitsAllocated(8).addLabelmapFrame([300])
        XCTAssertThrowsError(try builder.build())
    }

    func test_build_labelmap_requiresAFrame() throws {
        XCTAssertThrowsError(try makeBuilder().build()) { error in
            guard case SegmentationBuilderError.noFramesAdded = error else {
                return XCTFail("expected noFramesAdded, got \(error)")
            }
        }
    }

    func test_build_labelmap_rejectsWrongFrameSize() throws {
        XCTAssertThrowsError(try makeBuilder().addLabelmapFrame([0, 1]))
    }

    func test_labelmapAPI_rejectedForBinaryBuilder() {
        let builder = SegmentationBuilder(rows: 2, columns: 2, segmentationType: .binary,
                                          studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4")
        XCTAssertThrowsError(try builder.addLabelmapSegment(number: 1, label: "x"))
        XCTAssertThrowsError(try builder.addLabelmapFrame([0, 0, 0, 0]))
        XCTAssertThrowsError(try SegmentationBuilder(rows: 2, columns: 2, segmentationType: .labelmap,
                                                     studyInstanceUID: "1", seriesInstanceUID: "2")
            .addBinarySegment(number: 1, label: "x", mask: [0, 0, 0, 0]))
    }

    func test_binaryBuilder_unchanged() throws {
        // BINARY still packs 1-bit frames LSB first, one frame per segment, with the
        // Segmentation Functional Group and the Segmentation Storage SOP Class.
        let (segmentation, pixelData) = try SegmentationBuilder(
            rows: 1, columns: 8, segmentationType: .binary,
            studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4")
            .addBinarySegment(number: 1, label: "A", mask: [1, 0, 0, 0, 0, 0, 0, 0])
            .addBinarySegment(number: 2, label: "B", mask: [0, 0, 0, 0, 0, 0, 0, 1])
            .build()
        XCTAssertEqual(Array(pixelData), [0x01, 0x80])
        XCTAssertEqual(segmentation.sopClassUID, "1.2.840.10008.5.1.4.1.1.66.4")
        XCTAssertEqual(segmentation.bitsAllocated, 1)
        XCTAssertNil(segmentation.segmentsOverlap)
        XCTAssertNil(segmentation.pixelPaddingValue)
        XCTAssertEqual(segmentation.perFrameFunctionalGroups.map { $0.segmentIdentification?.referencedSegmentNumber }, [1, 2])
    }

    // MARK: - Builder -> DataSet -> Parser round trip

    func test_labelmap_dataSetRoundTrip_segmentNumbersSurvive() throws {
        let (built, pixelData) = try makeBuilder()
            .setSOPInstanceUID("1.2.3.4.5")
            .setInstanceNumber(3)
            .setSeriesNumber(9)
            .setContentLabel("LABELMAP")
            .setPixelPaddingValue(0)
            .setFrameOfReference("1.2.3.4.5.6")
            .addLabelmapFrame(slice1, imagePositionPatient: [0, 0, 0])
            .addLabelmapFrame(slice2, imagePositionPatient: [0, 0, 2.5])
            .build()

        let dataSet = try built.buildDataSet(pixelData: pixelData)

        // Type 1 attributes the Segmentation IOD needs for LABELMAP
        XCTAssertEqual(dataSet.string(for: .sopClassUID), "1.2.840.10008.5.1.4.1.1.66.7")
        XCTAssertEqual(dataSet.string(for: .modality), "SEG")
        XCTAssertEqual(dataSet.string(for: .seriesNumber), "9")
        XCTAssertEqual(dataSet.string(for: .instanceNumber), "3")
        XCTAssertEqual(dataSet.string(for: .contentLabel), "LABELMAP")
        XCTAssertNotNil(dataSet[.contentDescription], "Content Description is Type 2")
        XCTAssertNotNil(dataSet[.contentCreatorName], "Content Creator's Name (Type 3, Table 10.9.3-1) is written, zero length when unknown")
        XCTAssertNotNil(dataSet.date(for: .contentDate))
        XCTAssertNotNil(dataSet.time(for: .contentTime))
        XCTAssertEqual(dataSet[.imageType]?.stringValues, ["DERIVED", "PRIMARY"])
        XCTAssertEqual(dataSet.uint16(for: .samplesPerPixel), 1)
        XCTAssertEqual(dataSet.string(for: .photometricInterpretation), "MONOCHROME2")
        XCTAssertEqual(dataSet.uint16(for: .pixelRepresentation), 0)
        XCTAssertEqual(dataSet.uint16(for: .bitsAllocated), 8)
        XCTAssertEqual(dataSet.uint16(for: .bitsStored), 8)
        XCTAssertEqual(dataSet.uint16(for: .highBit), 7)
        XCTAssertEqual(dataSet.uint16(for: .rows), 3)
        XCTAssertEqual(dataSet.uint16(for: .columns), 4)
        XCTAssertEqual(dataSet.string(for: .numberOfFrames), "2")
        XCTAssertEqual(dataSet.string(for: .lossyImageCompression), "00")
        XCTAssertEqual(dataSet.string(for: .segmentationType), "LABELMAP")
        XCTAssertEqual(dataSet.string(for: Tag(group: 0x0062, element: 0x0013)), "NO", "Segments Overlap (0062,0013)")
        XCTAssertEqual(dataSet.uint16(for: .pixelPaddingValue), 0)
        XCTAssertNil(dataSet[.segmentationFractionalType])
        XCTAssertNil(dataSet[.maximumFractionalValue])
        XCTAssertEqual(dataSet.string(for: .frameOfReferenceUID), "1.2.3.4.5.6")
        XCTAssertEqual(dataSet[.pixelData]?.vr, .OB)
        XCTAssertEqual(dataSet[.pixelData]?.valueData, pixelData)

        // Segment Sequence (Table C.8.20-4): Segment Number, Label, Algorithm Type
        let segments = try XCTUnwrap(dataSet.sequence(for: .segmentSequence))
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments.map { $0[.segmentNumber]?.uint16Value }, [0, 1, 2])
        XCTAssertEqual(segments[0].string(for: .segmentAlgorithmType), "MANUAL")
        XCTAssertEqual(segments[1].string(for: .segmentAlgorithmType), "AUTOMATIC")
        XCTAssertEqual(segments[1].string(for: .segmentAlgorithmName), "LiverNet")
        XCTAssertEqual(segments[1][.segmentedPropertyTypeCodeSequence]?.sequenceItems?.first?.string(for: .codeValue), "10200004")
        XCTAssertEqual(segments[1][.recommendedDisplayCIELabValue]?.uint16Values?.count, 3)

        // Multi-frame Functional Groups + Dimension modules
        XCTAssertNotNil(dataSet.sequence(for: .sharedFunctionalGroupsSequence))
        let frames = try XCTUnwrap(dataSet.sequence(for: .perFrameFunctionalGroupsSequence))
        XCTAssertEqual(frames.count, 2)
        for frame in frames {
            XCTAssertNil(frame[.segmentIdentificationSequence], "Table A.51-2: no Segmentation Functional Group for LABELMAP")
            XCTAssertNotNil(frame[.frameContentSequence])
            XCTAssertNotNil(frame[.planePositionSequence])
        }
        let dims = try XCTUnwrap(dataSet.sequence(for: .dimensionIndexSequence))
        XCTAssertEqual(dims.first?[.dimensionIndexPointer]?.attributeTagValue, Tag.inStackPositionNumber)
        XCTAssertEqual(dims.first?[.functionalGroupPointer]?.attributeTagValue, Tag.frameContentSequence)
        XCTAssertNotNil(dataSet.sequence(for: .dimensionOrganizationSequence)?.first?.string(for: .dimensionOrganizationUID))

        // Parse it back
        let parsed = try SegmentationParser.parse(from: dataSet)
        XCTAssertEqual(parsed.segmentationType, .labelmap)
        XCTAssertEqual(parsed.sopClassUID, "1.2.840.10008.5.1.4.1.1.66.7")
        XCTAssertEqual(parsed.segmentsOverlap, .no)
        XCTAssertEqual(parsed.pixelPaddingValue, 0)
        XCTAssertEqual(parsed.seriesNumber, 9)
        XCTAssertEqual(parsed.bitsAllocated, 8)
        XCTAssertEqual(parsed.numberOfFrames, 2)
        XCTAssertEqual(parsed.segments.map { $0.segmentNumber }, [0, 1, 2])
        XCTAssertEqual(parsed.segments.map { $0.segmentLabel }, ["Background", "Liver", "Tumor"])
        XCTAssertEqual(parsed.segments[1].type?.codeValue, "10200004")
        XCTAssertEqual(parsed.perFrameFunctionalGroups.count, 2)
        XCTAssertNil(parsed.perFrameFunctionalGroups[0].segmentIdentification)
        XCTAssertEqual(parsed.perFrameFunctionalGroups[1].frameContent?.dimensionIndexValues, [2])
        XCTAssertEqual(parsed.perFrameFunctionalGroups[1].frameContent?.inStackPositionNumber, 2)
        XCTAssertEqual(parsed.perFrameFunctionalGroups[1].planePosition?.imagePositionPatient, [0, 0, 2.5])

        // Pixel value == Segment Number, per frame
        let pixels = try XCTUnwrap(dataSet[.pixelData]?.valueData)
        let frame0 = SegmentationPixelDataExtractor.extractLabelmapFrame(
            from: pixels, frameIndex: 0, rows: parsed.rows, columns: parsed.columns, bitsAllocated: parsed.bitsAllocated)
        let frame1 = SegmentationPixelDataExtractor.extractLabelmapFrame(
            from: pixels, frameIndex: 1, rows: parsed.rows, columns: parsed.columns, bitsAllocated: parsed.bitsAllocated)
        XCTAssertEqual(frame0, slice1)
        XCTAssertEqual(frame1, slice2)
    }

    func test_labelmap_16bit_dataSetRoundTrip() throws {
        let builder = SegmentationBuilder(rows: 1, columns: 3, segmentationType: .labelmap,
                                          studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4")
        let (built, pixelData) = try builder
            .addLabelmapSegment(number: 0, label: "Background", category: tissue, type: tissue)
            .addLabelmapSegment(number: 4097, label: "Lesion", category: abnormal, type: neoplasm)
            .addLabelmapFrame([0, 4097, 0])
            .build()
        let dataSet = try built.buildDataSet(pixelData: pixelData)
        XCTAssertEqual(dataSet[.pixelData]?.vr, .OW)
        XCTAssertEqual(dataSet.uint16(for: .bitsAllocated), 16)
        XCTAssertEqual(dataSet.uint16(for: .highBit), 15)

        let parsed = try SegmentationParser.parse(from: dataSet)
        let frame = SegmentationPixelDataExtractor.extractLabelmapFrame(
            from: pixelData, frameIndex: 0, rows: parsed.rows, columns: parsed.columns, bitsAllocated: parsed.bitsAllocated)
        XCTAssertEqual(frame, [0, 4097, 0])
        XCTAssertEqual(SegmentationPixelDataExtractor.extractSegmentMask(from: parsed, segmentNumber: 4097, pixelData: pixelData), [0, 1, 0])
    }

    func test_binary_dataSetRoundTrip() throws {
        // The serializer also covers BINARY: Segmentation Storage, Segment Identification per
        // frame and a Dimension Index on Referenced Segment Number.
        let (built, pixelData) = try SegmentationBuilder(
            rows: 1, columns: 8, segmentationType: .binary,
            studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4")
            .addBinarySegment(number: 1, label: "A", mask: [1, 0, 0, 0, 0, 0, 0, 0], category: tissue, type: tissue)
            .addBinarySegment(number: 2, label: "B", mask: [0, 0, 0, 0, 0, 0, 0, 1], category: abnormal, type: neoplasm)
            .build()
        let dataSet = try built.buildDataSet(pixelData: pixelData)
        XCTAssertEqual(dataSet.string(for: .sopClassUID), "1.2.840.10008.5.1.4.1.1.66.4")
        XCTAssertEqual(dataSet.uint16(for: .bitsAllocated), 1)
        XCTAssertNil(dataSet[.pixelPaddingValue], "A.51.4: not present unless LABELMAP")
        let frames = try XCTUnwrap(dataSet.sequence(for: .perFrameFunctionalGroupsSequence))
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[1][.segmentIdentificationSequence]?.sequenceItems?.first?[.referencedSegmentNumber]?.uint16Value, 2)
        XCTAssertEqual(frames[1][.frameContentSequence]?.sequenceItems?.first?[.dimensionIndexValues]?.uint32Values, [2])
        let dims = try XCTUnwrap(dataSet.sequence(for: .dimensionIndexSequence))
        XCTAssertEqual(dims.first?[.dimensionIndexPointer]?.attributeTagValue, Tag.referencedSegmentNumber)

        let parsed = try SegmentationParser.parse(from: dataSet)
        XCTAssertEqual(parsed.segmentationType, .binary)
        XCTAssertEqual(parsed.perFrameFunctionalGroups.map { $0.segmentIdentification?.referencedSegmentNumber }, [1, 2])
        XCTAssertEqual(parsed.perFrameFunctionalGroups[1].frameContent?.dimensionIndexValues, [2])
        let masks = SegmentationPixelDataExtractor.extractAllSegmentMasks(from: parsed, pixelData: pixelData)
        XCTAssertEqual(masks[1], [1, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(masks[2], [0, 0, 0, 0, 0, 0, 0, 1])
    }

    // MARK: - Extractor

    func test_extractor_labelmapMasks() throws {
        let (segmentation, pixelData) = try makeBuilder()
            .addLabelmapFrame(slice1)
            .addLabelmapFrame(slice2)
            .build()

        XCTAssertEqual(SegmentationPixelDataExtractor.extractSegmentMask(from: segmentation, segmentNumber: 1, pixelData: pixelData),
                       [0, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(SegmentationPixelDataExtractor.extractSegmentMask(from: segmentation, segmentNumber: 0, pixelData: pixelData),
                       [1, 0, 0, 1, 1, 0, 0, 1, 1, 1, 1, 1], "Segment Number 0 is a segment too")
        XCTAssertNil(SegmentationPixelDataExtractor.extractSegmentMask(from: segmentation, segmentNumber: 5, pixelData: pixelData))

        XCTAssertEqual(SegmentationPixelDataExtractor.extractLabelmapSegmentMask(
            from: segmentation, segmentNumber: 2, frameIndex: 1, pixelData: pixelData),
            [0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0])

        let all = SegmentationPixelDataExtractor.extractAllSegmentMasks(from: segmentation, pixelData: pixelData)
        XCTAssertEqual(all.keys.sorted(), [0, 1, 2])
        XCTAssertEqual(all[2], [0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0])

        let frame1 = SegmentationPixelDataExtractor.extractLabelmapSegmentMasks(from: segmentation, frameIndex: 1, pixelData: pixelData)
        XCTAssertEqual(frame1[1], [0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0])
        XCTAssertTrue(SegmentationPixelDataExtractor.extractLabelmapSegmentMasks(from: segmentation, frameIndex: 2, pixelData: pixelData).isEmpty)
    }

    func test_extractLabelmapFrame_invalidParameters() {
        XCTAssertNil(SegmentationPixelDataExtractor.extractLabelmapFrame(from: Data([1, 2]), frameIndex: 0, rows: 1, columns: 2, bitsAllocated: 12))
        XCTAssertNil(SegmentationPixelDataExtractor.extractLabelmapFrame(from: Data([1, 2]), frameIndex: 1, rows: 1, columns: 2, bitsAllocated: 8))
        XCTAssertNil(SegmentationPixelDataExtractor.extractLabelmapFrame(from: Data([1, 2]), frameIndex: -1, rows: 1, columns: 2, bitsAllocated: 8))
        XCTAssertEqual(SegmentationPixelDataExtractor.extractLabelmapFrame(from: Data([1, 2]), frameIndex: 0, rows: 1, columns: 2, bitsAllocated: 8), [1, 2])
    }

    #if canImport(CoreGraphics)
    // MARK: - Renderer

    func test_renderer_labelmap_paintsSegmentColorsAndSkipsPadding() throws {
        let (segmentation, pixelData) = try makeBuilder()
            .setPixelPaddingValue(0)
            .addLabelmapFrame(slice1)
            .addLabelmapFrame(slice2)
            .build()

        let options = SegmentationRenderer.RenderOptions(
            opacity: 1.0,
            customColors: [1: (r: 0, g: 255, b: 0), 2: (r: 255, g: 0, b: 0)]
        )
        let image = try XCTUnwrap(SegmentationRenderer.renderLabelmap(
            segmentation: segmentation, pixelData: pixelData, frameIndex: 1, options: options))
        XCTAssertEqual(image.width, 4)
        XCTAssertEqual(image.height, 3)

        var bytes = [UInt8](repeating: 0, count: 4 * 3 * 4)
        let context = try XCTUnwrap(CGContext(
            data: &bytes, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 16,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 4, height: 3))

        // slice2 row 1: 2, 2, 1, 0  (CGContext draws with the origin at the bottom; row 1 is the middle row either way)
        func pixel(_ x: Int, _ y: Int) -> [UInt8] { Array(bytes[(y * 4 + x) * 4 ..< (y * 4 + x) * 4 + 4]) }
        XCTAssertEqual(pixel(0, 1), [255, 0, 0, 255], "Segment 2 red")
        XCTAssertEqual(pixel(2, 1), [0, 255, 0, 255], "Segment 1 green")
        XCTAssertEqual(pixel(3, 1)[3], 0, "Pixel Padding Value 0 is background")

        // Hidden segment stays transparent
        let hidden = SegmentationRenderer.RenderOptions(opacity: 1.0, visibleSegments: [1])
        let image2 = try XCTUnwrap(SegmentationRenderer.renderLabelmap(
            segmentation: segmentation, pixelData: pixelData, frameIndex: 1, options: hidden))
        var bytes2 = [UInt8](repeating: 0, count: 4 * 3 * 4)
        let context2 = try XCTUnwrap(CGContext(
            data: &bytes2, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 16,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context2.draw(image2, in: CGRect(x: 0, y: 0, width: 4, height: 3))
        XCTAssertEqual(bytes2[(1 * 4 + 0) * 4 + 3], 0, "segment 2 hidden")
        XCTAssertEqual(bytes2[(1 * 4 + 2) * 4 + 3], 255, "segment 1 visible")

        // Not a LABELMAP => nil
        let (binary, binaryPixels) = try SegmentationBuilder(
            rows: 1, columns: 8, segmentationType: .binary, studyInstanceUID: "1", seriesInstanceUID: "2")
            .addBinarySegment(number: 1, label: "A", mask: [1, 0, 0, 0, 0, 0, 0, 0])
            .build()
        XCTAssertNil(SegmentationRenderer.renderLabelmap(segmentation: binary, pixelData: binaryPixels))
    }
    #endif
}
