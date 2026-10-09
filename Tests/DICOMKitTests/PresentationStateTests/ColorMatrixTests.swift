//
// ColorMatrixTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
@testable import DICOMKit

final class ColorMatrixTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func test_init_3x3Matrix() {
        let matrix = ColorMatrix(matrix: [
            [1, 0, 0],
            [0, 1, 0],
            [0, 0, 1]
        ])
        
        XCTAssertEqual(matrix.matrix.count, 3)
        XCTAssertEqual(matrix.matrix[0].count, 3)
        XCTAssertEqual(matrix.matrix[0][0], 1)
        XCTAssertEqual(matrix.matrix[1][1], 1)
        XCTAssertEqual(matrix.matrix[2][2], 1)
    }
    
    func test_init_invalidMatrix_crashes() {
        // This should trigger a precondition failure
        // We can't easily test precondition failures in XCTest
        // So we just document the expected behavior
        
        // Invalid: Not 3x3
        // ColorMatrix(matrix: [[1, 0], [0, 1]])
    }
    
    // MARK: - Identity Matrix Tests
    
    func test_identity_noTransformation() {
        let identity = ColorMatrix.identity
        
        let testColors = [
            (red: 0.0, green: 0.0, blue: 0.0),
            (red: 1.0, green: 0.0, blue: 0.0),
            (red: 0.0, green: 1.0, blue: 0.0),
            (red: 0.0, green: 0.0, blue: 1.0),
            (red: 1.0, green: 1.0, blue: 1.0),
            (red: 0.5, green: 0.6, blue: 0.7)
        ]
        
        for color in testColors {
            let result = identity.apply(to: color)
            XCTAssertEqual(result.red, color.red, accuracy: 1e-10)
            XCTAssertEqual(result.green, color.green, accuracy: 1e-10)
            XCTAssertEqual(result.blue, color.blue, accuracy: 1e-10)
        }
    }
    
    // MARK: - sRGB to XYZ Matrix Tests
    
    func test_sRGBToXYZ_black() {
        let result = ColorMatrix.sRGBToXYZ.apply(to: (red: 0, green: 0, blue: 0))
        XCTAssertEqual(result.red, 0.0, accuracy: 1e-6)
        XCTAssertEqual(result.green, 0.0, accuracy: 1e-6)
        XCTAssertEqual(result.blue, 0.0, accuracy: 1e-6)
    }
    
    func test_sRGBToXYZ_white() {
        let result = ColorMatrix.sRGBToXYZ.apply(to: (red: 1, green: 1, blue: 1))
        // D65 white is (0.9505, 1.0, 1.089), but apply(to:) clamps every output
        // component to 0...1 (pinned by test_xyzToSRGB_clampingOutOfRange), so
        // Z comes back as 1.0. The unclamped XYZ path is ColorTransform.rgbToXYZ
        // (ColorTransformTests.test_rgbToXYZ_white). Not DICOM-governed (IEC 61966-2-1).
        XCTAssertEqual(result.red, 0.9505, accuracy: 0.001)
        XCTAssertEqual(result.green, 1.0, accuracy: 0.001)
        XCTAssertEqual(result.blue, 1.0, accuracy: 0.001)
    }
    
    func test_sRGBToXYZ_red() {
        let result = ColorMatrix.sRGBToXYZ.apply(to: (red: 1, green: 0, blue: 0))
        XCTAssertEqual(result.red, 0.4124564, accuracy: 1e-6)
        XCTAssertEqual(result.green, 0.2126729, accuracy: 1e-6)
        XCTAssertEqual(result.blue, 0.0193339, accuracy: 1e-6)
    }
    
    func test_sRGBToXYZ_green() {
        let result = ColorMatrix.sRGBToXYZ.apply(to: (red: 0, green: 1, blue: 0))
        XCTAssertEqual(result.red, 0.3575761, accuracy: 1e-6)
        XCTAssertEqual(result.green, 0.7151522, accuracy: 1e-6)
        XCTAssertEqual(result.blue, 0.1191920, accuracy: 1e-6)
    }
    
    func test_sRGBToXYZ_blue() {
        let result = ColorMatrix.sRGBToXYZ.apply(to: (red: 0, green: 0, blue: 1))
        XCTAssertEqual(result.red, 0.1804375, accuracy: 1e-6)
        XCTAssertEqual(result.green, 0.0721750, accuracy: 1e-6)
        XCTAssertEqual(result.blue, 0.9503041, accuracy: 1e-6)
    }
    
    // MARK: - XYZ to sRGB Matrix Tests
    
    func test_xyzToSRGB_black() {
        let result = ColorMatrix.xyzToSRGB.apply(to: (red: 0, green: 0, blue: 0))
        XCTAssertEqual(result.red, 0.0, accuracy: 1e-6)
        XCTAssertEqual(result.green, 0.0, accuracy: 1e-6)
        XCTAssertEqual(result.blue, 0.0, accuracy: 1e-6)
    }
    
    func test_xyzToSRGB_white() {
        let result = ColorMatrix.xyzToSRGB.apply(to: (red: 0.9505, green: 1.0, blue: 1.089))
        XCTAssertEqual(result.red, 1.0, accuracy: 0.01)
        XCTAssertEqual(result.green, 1.0, accuracy: 0.01)
        XCTAssertEqual(result.blue, 1.0, accuracy: 0.01)
    }
    
    func test_xyzToSRGB_clampingOutOfRange() {
        // Test that values outside [0, 1] are clamped
        let matrix = ColorMatrix(matrix: [
            [2, 0, 0],  // Would produce 2.0 for red=1
            [0, 1, 0],
            [0, 0, 1]
        ])
        
        let result = matrix.apply(to: (red: 1, green: 0, blue: 0))
        XCTAssertEqual(result.red, 1.0) // Clamped to 1.0
        
        let matrix2 = ColorMatrix(matrix: [
            [-1, 0, 0],  // Would produce -1.0 for red=1
            [0, 1, 0],
            [0, 0, 1]
        ])
        
        let result2 = matrix2.apply(to: (red: 1, green: 0, blue: 0))
        XCTAssertEqual(result2.red, 0.0) // Clamped to 0.0
    }
    
    // MARK: - Round-Trip Tests
    
    func test_roundTrip_sRGBToXYZToSRGB() {
        // White is left out: its Z (1.089) is clamped to 1.0 by apply(to:), so it
        // cannot round-trip through ColorMatrix (see test_sRGBToXYZ_white).
        let originalColors = [
            (red: 0.0, green: 0.0, blue: 0.0),
            (red: 1.0, green: 0.0, blue: 0.0),
            (red: 0.0, green: 1.0, blue: 0.0),
            (red: 0.0, green: 0.0, blue: 1.0),
            (red: 0.5, green: 0.5, blue: 0.5),
            (red: 0.25, green: 0.75, blue: 0.5)
        ]
        
        for original in originalColors {
            let xyz = ColorMatrix.sRGBToXYZ.apply(to: original)
            let backToRGB = ColorMatrix.xyzToSRGB.apply(to: xyz)
            
            XCTAssertEqual(backToRGB.red, original.red, accuracy: 0.001)
            XCTAssertEqual(backToRGB.green, original.green, accuracy: 0.001)
            XCTAssertEqual(backToRGB.blue, original.blue, accuracy: 0.001)
        }
    }
    
    // MARK: - Custom Matrix Tests
    
    func test_customMatrix_scaleTransform() {
        // Create a matrix that scales all components by 0.5
        let scaleMatrix = ColorMatrix(matrix: [
            [0.5, 0, 0],
            [0, 0.5, 0],
            [0, 0, 0.5]
        ])
        
        let result = scaleMatrix.apply(to: (red: 1, green: 1, blue: 1))
        XCTAssertEqual(result.red, 0.5, accuracy: 1e-10)
        XCTAssertEqual(result.green, 0.5, accuracy: 1e-10)
        XCTAssertEqual(result.blue, 0.5, accuracy: 1e-10)
    }
    
    func test_customMatrix_channelSwap() {
        // Swap red and blue channels
        let swapMatrix = ColorMatrix(matrix: [
            [0, 0, 1],  // Red from blue
            [0, 1, 0],  // Green from green
            [1, 0, 0]   // Blue from red
        ])
        
        let result = swapMatrix.apply(to: (red: 1, green: 0.5, blue: 0))
        XCTAssertEqual(result.red, 0.0, accuracy: 1e-10)  // Was blue
        XCTAssertEqual(result.green, 0.5, accuracy: 1e-10)  // Stays green
        XCTAssertEqual(result.blue, 1.0, accuracy: 1e-10)  // Was red
    }
    
    func test_customMatrix_grayscale() {
        // Convert to grayscale using luminance weights
        let grayscaleMatrix = ColorMatrix(matrix: [
            [0.2126, 0.7152, 0.0722],
            [0.2126, 0.7152, 0.0722],
            [0.2126, 0.7152, 0.0722]
        ])
        
        let result = grayscaleMatrix.apply(to: (red: 1, green: 0, blue: 0))
        // Red converts to approximately 0.2126 gray
        XCTAssertEqual(result.red, 0.2126, accuracy: 1e-4)
        XCTAssertEqual(result.green, 0.2126, accuracy: 1e-4)
        XCTAssertEqual(result.blue, 0.2126, accuracy: 1e-4)
    }
    
    // MARK: - Hashable Tests
    
    func test_hashable() {
        let matrix1 = ColorMatrix.identity
        let matrix2 = ColorMatrix.identity
        let matrix3 = ColorMatrix.sRGBToXYZ
        
        XCTAssertEqual(matrix1, matrix2)
        XCTAssertNotEqual(matrix1, matrix3)
        
        let set: Set = [matrix1, matrix2, matrix3]
        XCTAssertEqual(set.count, 2)
    }
    
    func test_hashable_differentMatrices() {
        let matrix1 = ColorMatrix(matrix: [
            [1, 0, 0],
            [0, 1, 0],
            [0, 0, 1]
        ])
        
        let matrix2 = ColorMatrix(matrix: [
            [1, 0, 0],
            [0, 1, 0],
            [0, 0, 2]  // Different
        ])
        
        XCTAssertNotEqual(matrix1, matrix2)
    }
}
