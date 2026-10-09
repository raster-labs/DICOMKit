import XCTest
@testable import DICOMKit

#if canImport(Accelerate)

final class SIMDImageProcessorTests: XCTestCase {
    
    func testWindowLevelTransformation() {
        // Create test data: 100 pixels with values 0-99
        let pixelData: [UInt16] = (0..<100).map { UInt16($0) }
        
        // Apply window/level: center=50, width=50
        let result = SIMDImageProcessor.applyWindowLevel(
            to: pixelData,
            windowCenter: 50,
            windowWidth: 50,
            bitsStored: 16
        )
        
        // Check output length
        XCTAssertEqual(result.count, pixelData.count)
        
        // Values below window should be 0
        XCTAssertEqual(result[0], 0)
        XCTAssertEqual(result[24], 0)
        
        // Values above window should be 255
        XCTAssertEqual(result[99], 255)
        
        // Values in window should be mapped linearly
        // At center (index 50), should be around 127-128
        XCTAssertGreaterThan(result[50], 120)
        XCTAssertLessThan(result[50], 135)
    }
    
    func testWindowLevelZeroWidth() {
        let pixelData: [UInt16] = [0, 50, 100, 150, 200]

        // PS3.3 C.11.2.1.2.1: "Window Width (0028,1051) shall always be greater
        // than or equal to 1". A width below 1 is clamped to 1 exactly as
        // WindowSettings.init does, which makes the window a threshold at
        // c - 0.5 = 99.5: x <= 99.5 → 0, x > 99.5 → 255.
        let result = SIMDImageProcessor.applyWindowLevel(
            to: pixelData,
            windowCenter: 100,
            windowWidth: 0,
            bitsStored: 16
        )

        XCTAssertEqual(result, [0, 0, 255, 255, 255])
    }
    
    func testInvertPixels() {
        let pixelData: [UInt8] = [0, 64, 128, 192, 255]
        
        let result = SIMDImageProcessor.invertPixels(pixelData)
        
        XCTAssertEqual(result.count, pixelData.count)
        XCTAssertEqual(result[0], 255)
        XCTAssertEqual(result[4], 0)
        
        // Middle values should also be inverted
        XCTAssertEqual(result[1], 255 - 64, accuracy: 1)
        XCTAssertEqual(result[2], 255 - 128, accuracy: 1)
        XCTAssertEqual(result[3], 255 - 192, accuracy: 1)
    }
    
    func testInvertPixelsRoundtrip() {
        let original: [UInt8] = [0, 50, 100, 150, 200, 255]
        
        // Invert twice should get back to original
        let inverted = SIMDImageProcessor.invertPixels(original)
        let restored = SIMDImageProcessor.invertPixels(inverted)
        
        for i in 0..<original.count {
            XCTAssertEqual(restored[i], original[i], accuracy: 1)
        }
    }
    
    func testNormalize() {
        let pixelData: [UInt16] = [100, 200, 300, 400, 500]
        
        // Normalize from [100, 500] to [0, 255]
        let result = SIMDImageProcessor.normalize(
            pixelData,
            minValue: 100,
            maxValue: 500
        )
        
        XCTAssertEqual(result.count, pixelData.count)
        XCTAssertEqual(result[0], 0)
        XCTAssertEqual(result[4], 255)
        
        // Middle value should be around 127
        XCTAssertGreaterThan(result[2], 120)
        XCTAssertLessThan(result[2], 135)
    }
    
    func testNormalizeZeroRange() {
        let pixelData: [UInt16] = [100, 100, 100]
        
        // Same min and max should return zeros
        let result = SIMDImageProcessor.normalize(
            pixelData,
            minValue: 100,
            maxValue: 100
        )
        
        XCTAssertEqual(result, [0, 0, 0])
    }
    
    func testFindMinMax() {
        let pixelData: [UInt16] = [500, 200, 1000, 50, 750, 300]
        
        let (min, max) = SIMDImageProcessor.findMinMax(pixelData)
        
        XCTAssertEqual(min, 50)
        XCTAssertEqual(max, 1000)
    }
    
    func testFindMinMaxEmpty() {
        let pixelData: [UInt16] = []
        
        let (min, max) = SIMDImageProcessor.findMinMax(pixelData)
        
        XCTAssertEqual(min, 0)
        XCTAssertEqual(max, 0)
    }
    
    func testFindMinMaxSingleValue() {
        let pixelData: [UInt16] = [42]
        
        let (min, max) = SIMDImageProcessor.findMinMax(pixelData)
        
        XCTAssertEqual(min, 42)
        XCTAssertEqual(max, 42)
    }
    
    func testAdjustContrast() {
        let pixelData: [UInt8] = [0, 64, 128, 192, 255]
        
        // Increase contrast (alpha > 1.0)
        let result = SIMDImageProcessor.adjustContrast(
            pixelData,
            alpha: 1.5,
            beta: 0
        )
        
        XCTAssertEqual(result.count, pixelData.count)
        XCTAssertEqual(result[0], 0) // 0 * 1.5 = 0
        XCTAssertEqual(result[4], 255) // 255 * 1.5 = 382.5 -> clipped to 255
        
        // Middle value should be increased
        XCTAssertGreaterThan(result[2], 128)
    }
    
    func testAdjustBrightness() {
        let pixelData: [UInt8] = [0, 64, 128, 192, 255]
        
        // Increase brightness (beta > 0, alpha = 1.0)
        let result = SIMDImageProcessor.adjustContrast(
            pixelData,
            alpha: 1.0,
            beta: 50
        )
        
        XCTAssertEqual(result.count, pixelData.count)
        XCTAssertEqual(result[0], 50) // 0 + 50 = 50
        XCTAssertEqual(result[4], 255) // 255 + 50 = 305 -> clipped to 255
        
        // Middle value should be increased by 50
        XCTAssertEqual(result[2], 128 + 50, accuracy: 1)
    }
    
    func testAdjustContrastWithBrightness() {
        let pixelData: [UInt8] = [50, 100, 150]
        
        // Combine contrast and brightness
        let result = SIMDImageProcessor.adjustContrast(
            pixelData,
            alpha: 2.0,
            beta: 10
        )
        
        XCTAssertEqual(result.count, pixelData.count)
        
        // First value: 50 * 2.0 + 10 = 110
        XCTAssertEqual(result[0], 110, accuracy: 1)
        
        // Second value: 100 * 2.0 + 10 = 210
        XCTAssertEqual(result[1], 210, accuracy: 1)
        
        // Third value: 150 * 2.0 + 10 = 310 -> clipped to 255
        XCTAssertEqual(result[2], 255)
    }
    
    func testLargeArrayPerformance() {
        // Test with larger array to verify SIMD benefits
        let size = 512 * 512 // Typical small DICOM image
        let pixelData = (0..<size).map { UInt16($0 % 4096) }
        
        measure {
            _ = SIMDImageProcessor.applyWindowLevel(
                to: pixelData,
                windowCenter: 2048,
                windowWidth: 4096,
                bitsStored: 12
            )
        }
    }
    
    func testWindowLevelClinicalScenario() {
        // Simulate a CT scan scenario
        // CT values typically range from -1024 to 3071 (12-bit signed)
        // But stored as unsigned by adding 1024
        let ctData: [UInt16] = [
            0,      // -1024 HU (air)
            1024,   // 0 HU (water)
            1074,   // 50 HU (soft tissue)
            3095    // 2071 HU (bone)
        ]
        
        // Soft tissue window: Center=40, Width=400
        let result = SIMDImageProcessor.applyWindowLevel(
            to: ctData,
            windowCenter: 1064,  // 40 HU + 1024 offset
            windowWidth: 400,
            bitsStored: 12
        )
        
        XCTAssertEqual(result.count, ctData.count)
        
        // Air should be black (below window)
        XCTAssertLessThan(result[0], 10)
        
        // Water should be in mid-range
        XCTAssertGreaterThan(result[1], 100)
        XCTAssertLessThan(result[1], 155)
        
        // Soft tissue (50 HU) is only 10 units above the 1064 center within a
        // 400-wide window, so it maps just above mid-gray: (1074-864)*255/400 ≈ 134.
        XCTAssertGreaterThan(result[2], 127)
        
        // Bone should be white (above window)
        XCTAssertGreaterThan(result[3], 245)
    }
}
#endif
