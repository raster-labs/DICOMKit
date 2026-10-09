//
// SegmentationPixelDataExtractorTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
import DICOMCore
@testable import DICOMKit

final class SegmentationPixelDataExtractorTests: XCTestCase {
    
    // MARK: - Binary Frame Extraction Tests
    
    func test_extractBinaryFrame_simplePattern_succeeds() {
        // Given: A 4x4 binary pattern (16 pixels)
        // Pattern:
        // 1 1 0 0
        // 1 1 0 0
        // 0 0 1 1
        // 0 0 1 1
        
        // Packed as PS3.5 8.1.1 / D.1 describe: the first pixel in the least
        // significant bit of the first byte.
        // First byte: pixels 1,1,0,0,1,1,0,0 in bits 0...7 = 0x33
        // Second byte: pixels 0,0,1,1,0,0,1,1 in bits 0...7 = 0xCC
        let pixelData = Data([0x33, 0xCC])
        
        // When: Extracting the binary frame
        let mask = SegmentationPixelDataExtractor.extractBinaryFrame(
            from: pixelData,
            frameIndex: 0,
            rows: 4,
            columns: 4
        )
        
        // Then: Mask should match expected pattern
        XCTAssertNotNil(mask)
        let expected: [UInt8] = [
            1, 1, 0, 0,
            1, 1, 0, 0,
            0, 0, 1, 1,
            0, 0, 1, 1
        ]
        XCTAssertEqual(mask, expected)
    }
    
    func test_extractBinaryFrame_allZeros_succeeds() {
        // Given: All zeros (2x2 = 4 pixels = 1 byte)
        let pixelData = Data([0x00])
        
        // When: Extracting the binary frame
        let mask = SegmentationPixelDataExtractor.extractBinaryFrame(
            from: pixelData,
            frameIndex: 0,
            rows: 2,
            columns: 2
        )
        
        // Then: All pixels should be 0
        XCTAssertNotNil(mask)
        XCTAssertEqual(mask, [0, 0, 0, 0])
    }
    
    func test_extractBinaryFrame_allOnes_succeeds() {
        // Given: All ones (2x2 = 4 pixels, the four least significant bits set)
        // Byte: bits 0...3 set = 0x0F
        let pixelData = Data([0x0F])
        
        // When: Extracting the binary frame
        let mask = SegmentationPixelDataExtractor.extractBinaryFrame(
            from: pixelData,
            frameIndex: 0,
            rows: 2,
            columns: 2
        )
        
        // Then: All pixels should be 1
        XCTAssertNotNil(mask)
        XCTAssertEqual(mask, [1, 1, 1, 1])
    }
    
    func test_extractBinaryFrame_multipleFrames_succeeds() {
        // Given: Two frames of 2x2 pixels each, least significant bit first
        // Frame 0: 1,0,1,0 in bits 0...3 = 0x05
        // Frame 1: 0,1,0,1 in bits 0...3 = 0x0A
        let pixelData = Data([0x05, 0x0A])

        // When: Extracting frame 0
        let mask0 = SegmentationPixelDataExtractor.extractBinaryFrame(
            from: pixelData,
            frameIndex: 0,
            rows: 2,
            columns: 2
        )
        
        // Then: Frame 0 should be correct
        XCTAssertEqual(mask0, [1, 0, 1, 0])
        
        // When: Extracting frame 1
        let mask1 = SegmentationPixelDataExtractor.extractBinaryFrame(
            from: pixelData,
            frameIndex: 1,
            rows: 2,
            columns: 2
        )
        
        // Then: Frame 1 should be correct
        XCTAssertEqual(mask1, [0, 1, 0, 1])
    }
    
    func test_extractBinaryFrame_oddPixelCount_succeeds() {
        // Given: 3x3 = 9 pixels, needs 2 bytes (last 7 bits unused)
        // Pattern: 1,1,1,0,0,0,1,1,1 (first 9 pixels), least significant bit first
        // Byte 0: pixels 1,1,1,0,0,0,1,1 in bits 0...7 = 0xC7
        // Byte 1: pixel 9 in bit 0 = 0x01 (the other 7 bits unused)
        let pixelData = Data([0xC7, 0x01])
        
        // When: Extracting the binary frame
        let mask = SegmentationPixelDataExtractor.extractBinaryFrame(
            from: pixelData,
            frameIndex: 0,
            rows: 3,
            columns: 3
        )
        
        // Then: Should extract 9 pixels correctly
        XCTAssertNotNil(mask)
        XCTAssertEqual(mask?.count, 9)
        XCTAssertEqual(mask, [1, 1, 1, 0, 0, 0, 1, 1, 1])
    }
    
    func test_extractBinaryFrame_invalidFrameIndex_returnsNil() {
        let pixelData = Data([0xFF])
        
        let mask = SegmentationPixelDataExtractor.extractBinaryFrame(
            from: pixelData,
            frameIndex: 10,
            rows: 2,
            columns: 2
        )
        
        XCTAssertNil(mask)
    }
    
    func test_extractBinaryFrame_insufficientData_returnsNil() {
        // Given: Only 1 byte, but we need 2 for 16 pixels
        let pixelData = Data([0xFF])
        
        let mask = SegmentationPixelDataExtractor.extractBinaryFrame(
            from: pixelData,
            frameIndex: 0,
            rows: 4,
            columns: 4
        )
        
        XCTAssertNil(mask)
    }
    
    func test_extractBinaryFrame_invalidDimensions_returnsNil() {
        let pixelData = Data([0xFF])
        
        // Zero rows
        XCTAssertNil(SegmentationPixelDataExtractor.extractBinaryFrame(
            from: pixelData,
            frameIndex: 0,
            rows: 0,
            columns: 4
        ))
        
        // Zero columns
        XCTAssertNil(SegmentationPixelDataExtractor.extractBinaryFrame(
            from: pixelData,
            frameIndex: 0,
            rows: 4,
            columns: 0
        ))
        
        // Negative frame index
        XCTAssertNil(SegmentationPixelDataExtractor.extractBinaryFrame(
            from: pixelData,
            frameIndex: -1,
            rows: 2,
            columns: 2
        ))
    }
    
    // MARK: - Fractional Frame Extraction Tests (8-bit)
    
    func test_extractFractionalFrame_8bit_succeeds() {
        // Given: 2x2 frame with 8-bit values
        let pixelData = Data([0, 85, 170, 255])
        
        // When: Extracting with max value 255
        let mask = SegmentationPixelDataExtractor.extractFractionalFrame(
            from: pixelData,
            frameIndex: 0,
            rows: 2,
            columns: 2,
            bitsAllocated: 8,
            maxValue: 255
        )
        
        // Then: Values should be normalized to 0-255
        XCTAssertNotNil(mask)
        XCTAssertEqual(mask, [0, 85, 170, 255])
    }
    
    func test_extractFractionalFrame_8bit_withScaling_succeeds() {
        // Given: 2x2 frame with 8-bit values, max value 100
        let pixelData = Data([0, 25, 50, 100])
        
        // When: Extracting with max value 100 (should scale to 0-255)
        let mask = SegmentationPixelDataExtractor.extractFractionalFrame(
            from: pixelData,
            frameIndex: 0,
            rows: 2,
            columns: 2,
            bitsAllocated: 8,
            maxValue: 100
        )
        
        // Then: Values should be scaled
        // 0 -> 0, 25 -> 63.75 (63), 50 -> 127.5 (127), 100 -> 254 or 255 (rounding)
        XCTAssertNotNil(mask)
        XCTAssertEqual(mask?[0], 0)
        XCTAssertEqual(mask?[1], 63)
        XCTAssertEqual(mask?[2], 127)
        // Accept both 254 and 255 due to rounding
        XCTAssertGreaterThanOrEqual(mask?[3] ?? 0, 254)
    }
    
    func test_extractFractionalFrame_8bit_multipleFrames_succeeds() {
        // Given: Two 2x2 frames
        let pixelData = Data([
            // Frame 0
            0, 64, 128, 192,
            // Frame 1
            32, 96, 160, 224
        ])
        
        // When: Extracting frame 1
        let mask = SegmentationPixelDataExtractor.extractFractionalFrame(
            from: pixelData,
            frameIndex: 1,
            rows: 2,
            columns: 2,
            bitsAllocated: 8,
            maxValue: 255
        )
        
        // Then: Should get frame 1 data
        XCTAssertNotNil(mask)
        XCTAssertEqual(mask, [32, 96, 160, 224])
    }
    
    // MARK: - Fractional Frame Extraction Tests (16-bit)
    
    func test_extractFractionalFrame_16bit_succeeds() {
        // Given: 2x2 frame with 16-bit values (little-endian)
        var pixelData = Data()
        let values: [UInt16] = [0, 16383, 32767, 65535]
        for value in values {
            var v = value
            pixelData.append(contentsOf: withUnsafeBytes(of: &v) { Data($0) })
        }
        
        // When: Extracting with max value 65535
        let mask = SegmentationPixelDataExtractor.extractFractionalFrame(
            from: pixelData,
            frameIndex: 0,
            rows: 2,
            columns: 2,
            bitsAllocated: 16,
            maxValue: 65535
        )
        
        // Then: Values should be normalized to 0-255
        XCTAssertNotNil(mask)
        XCTAssertEqual(mask?[0], 0)
        XCTAssertEqual(mask?[1], 63)  // 16383 / 65535 * 255 ≈ 63
        XCTAssertEqual(mask?[2], 127) // 32767 / 65535 * 255 ≈ 127
        XCTAssertEqual(mask?[3], 255)
    }
    
    func test_extractFractionalFrame_16bit_withScaling_succeeds() {
        // Given: 2x2 frame with 16-bit values, max value 1000
        var pixelData = Data()
        let values: [UInt16] = [0, 250, 500, 1000]
        for value in values {
            var v = value
            pixelData.append(contentsOf: withUnsafeBytes(of: &v) { Data($0) })
        }
        
        // When: Extracting with max value 1000
        let mask = SegmentationPixelDataExtractor.extractFractionalFrame(
            from: pixelData,
            frameIndex: 0,
            rows: 2,
            columns: 2,
            bitsAllocated: 16,
            maxValue: 1000
        )
        
        // Then: Values should be scaled to 0-255
        XCTAssertNotNil(mask)
        XCTAssertEqual(mask?[0], 0)
        XCTAssertEqual(mask?[1], 63)  // 250 / 1000 * 255 ≈ 63
        XCTAssertEqual(mask?[2], 127) // 500 / 1000 * 255 ≈ 127
        XCTAssertEqual(mask?[3], 255)
    }
    
    func test_extractFractionalFrame_invalidBitsAllocated_returnsNil() {
        let pixelData = Data([0, 1, 2, 3])
        
        // Invalid bits allocated
        let mask = SegmentationPixelDataExtractor.extractFractionalFrame(
            from: pixelData,
            frameIndex: 0,
            rows: 2,
            columns: 2,
            bitsAllocated: 32,
            maxValue: 255
        )
        
        XCTAssertNil(mask)
    }
    
    func test_extractFractionalFrame_invalidMaxValue_returnsNil() {
        let pixelData = Data([0, 1, 2, 3])
        
        // Zero max value
        let mask = SegmentationPixelDataExtractor.extractFractionalFrame(
            from: pixelData,
            frameIndex: 0,
            rows: 2,
            columns: 2,
            bitsAllocated: 8,
            maxValue: 0
        )
        
        XCTAssertNil(mask)
    }
    
    func test_extractFractionalFrame_insufficientData_returnsNil() {
        // Given: Only 2 bytes, but we need 4 for 2x2 8-bit frame
        let pixelData = Data([0, 1])
        
        let mask = SegmentationPixelDataExtractor.extractFractionalFrame(
            from: pixelData,
            frameIndex: 0,
            rows: 2,
            columns: 2,
            bitsAllocated: 8,
            maxValue: 255
        )
        
        XCTAssertNil(mask)
    }
    
    // MARK: - Segment Mask Extraction Tests
    
    func test_extractSegmentMask_binarySegmentation_succeeds() {
        // Given: Binary segmentation with one segment
        let segment = Segment(segmentNumber: 1, segmentLabel: "Test")
        let segID = SegmentIdentification(referencedSegmentNumber: 1)
        let fg = FunctionalGroup(segmentIdentification: segID)
        
        let segmentation = Segmentation(
            sopInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4",
            studyInstanceUID: "1.2.3.4.5",
            segmentationType: .binary,
            numberOfSegments: 1,
            segments: [segment],
            numberOfFrames: 1,
            rows: 2,
            columns: 2,
            bitsAllocated: 1,
            bitsStored: 1,
            highBit: 0,
            perFrameFunctionalGroups: [fg]
        )
        
        // Pixel data: 1,0,1,0 in bits 0...3 (least significant bit first) = 0x05
        let pixelData = Data([0x05])
        
        // When: Extracting segment 1
        let mask = SegmentationPixelDataExtractor.extractSegmentMask(
            from: segmentation,
            segmentNumber: 1,
            pixelData: pixelData
        )
        
        // Then: Should extract the binary mask
        XCTAssertNotNil(mask)
        XCTAssertEqual(mask, [1, 0, 1, 0])
    }
    
    func test_extractSegmentMask_fractionalSegmentation_succeeds() {
        // Given: Fractional segmentation with one segment
        let segment = Segment(segmentNumber: 1, segmentLabel: "Test")
        let segID = SegmentIdentification(referencedSegmentNumber: 1)
        let fg = FunctionalGroup(segmentIdentification: segID)
        
        let segmentation = Segmentation(
            sopInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4",
            studyInstanceUID: "1.2.3.4.5",
            segmentationType: .fractional,
            maxFractionalValue: 255,
            numberOfSegments: 1,
            segments: [segment],
            numberOfFrames: 1,
            rows: 2,
            columns: 2,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            perFrameFunctionalGroups: [fg]
        )
        
        let pixelData = Data([0, 64, 128, 255])
        
        // When: Extracting segment 1
        let mask = SegmentationPixelDataExtractor.extractSegmentMask(
            from: segmentation,
            segmentNumber: 1,
            pixelData: pixelData
        )
        
        // Then: Should extract the fractional mask
        XCTAssertNotNil(mask)
        XCTAssertEqual(mask, [0, 64, 128, 255])
    }
    
    func test_extractSegmentMask_invalidSegmentNumber_returnsNil() {
        let segment = Segment(segmentNumber: 1, segmentLabel: "Test")
        
        let segmentation = Segmentation(
            sopInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4",
            studyInstanceUID: "1.2.3.4.5",
            segmentationType: .binary,
            numberOfSegments: 1,
            segments: [segment],
            numberOfFrames: 1,
            rows: 2,
            columns: 2,
            bitsAllocated: 1,
            bitsStored: 1,
            highBit: 0
        )
        
        let pixelData = Data([0xFF])
        
        // When: Requesting non-existent segment
        let mask = SegmentationPixelDataExtractor.extractSegmentMask(
            from: segmentation,
            segmentNumber: 99,
            pixelData: pixelData
        )
        
        // Then: Should return nil
        XCTAssertNil(mask)
    }
    
    func test_extractSegmentMask_noFramesForSegment_returnsNil() {
        // Given: Segment exists but no frames reference it
        let segment = Segment(segmentNumber: 1, segmentLabel: "Test")
        
        let segmentation = Segmentation(
            sopInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4",
            studyInstanceUID: "1.2.3.4.5",
            segmentationType: .binary,
            numberOfSegments: 1,
            segments: [segment],
            numberOfFrames: 1,
            rows: 2,
            columns: 2,
            bitsAllocated: 1,
            bitsStored: 1,
            highBit: 0,
            perFrameFunctionalGroups: [] // No functional groups
        )
        
        let pixelData = Data([0xFF])
        
        let mask = SegmentationPixelDataExtractor.extractSegmentMask(
            from: segmentation,
            segmentNumber: 1,
            pixelData: pixelData
        )
        
        XCTAssertNil(mask)
    }
    
    // MARK: - All Segments Extraction Tests
    
    func test_extractAllSegmentMasks_multipleSegments_succeeds() {
        // Given: Segmentation with 2 segments
        let segment1 = Segment(segmentNumber: 1, segmentLabel: "Segment 1")
        let segment2 = Segment(segmentNumber: 2, segmentLabel: "Segment 2")
        
        let segID1 = SegmentIdentification(referencedSegmentNumber: 1)
        let segID2 = SegmentIdentification(referencedSegmentNumber: 2)
        let fg1 = FunctionalGroup(segmentIdentification: segID1)
        let fg2 = FunctionalGroup(segmentIdentification: segID2)
        
        let segmentation = Segmentation(
            sopInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4",
            studyInstanceUID: "1.2.3.4.5",
            segmentationType: .binary,
            numberOfSegments: 2,
            segments: [segment1, segment2],
            numberOfFrames: 2,
            rows: 2,
            columns: 2,
            bitsAllocated: 1,
            bitsStored: 1,
            highBit: 0,
            perFrameFunctionalGroups: [fg1, fg2]
        )
        
        // Two frames, least significant bit first: Frame 0 = 1,0,1,0 (0x05), Frame 1 = 0,1,0,1 (0x0A)
        let pixelData = Data([0x05, 0x0A])
        
        // When: Extracting all segments
        let masks = SegmentationPixelDataExtractor.extractAllSegmentMasks(
            from: segmentation,
            pixelData: pixelData
        )
        
        // Then: Should have both segments
        XCTAssertEqual(masks.count, 2)
        XCTAssertEqual(masks[1], [1, 0, 1, 0])
        XCTAssertEqual(masks[2], [0, 1, 0, 1])
    }
    
    func test_extractAllSegmentMasks_emptySegmentation_returnsEmpty() {
        let segmentation = Segmentation(
            sopInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4",
            studyInstanceUID: "1.2.3.4.5",
            segmentationType: .binary,
            numberOfSegments: 0,
            segments: [],
            numberOfFrames: 0,
            rows: 2,
            columns: 2,
            bitsAllocated: 1,
            bitsStored: 1,
            highBit: 0
        )
        
        let pixelData = Data()
        
        let masks = SegmentationPixelDataExtractor.extractAllSegmentMasks(
            from: segmentation,
            pixelData: pixelData
        )
        
        XCTAssertTrue(masks.isEmpty)
    }
}
