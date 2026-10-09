//
// LUTColorTransformTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
@testable import DICOMKit

final class LUTColorTransformTests: XCTestCase {
    
    // MARK: - LUT1D Tests
    
    func test_lut1d_identity() {
        let lut = LUT1D.identity
        
        XCTAssertEqual(lut.lookup(0.0), 0.0)
        XCTAssertEqual(lut.lookup(0.5), 0.5)
        XCTAssertEqual(lut.lookup(1.0), 1.0)
    }
    
    func test_lut1d_customValues() {
        let values = [0.0, 0.25, 0.75, 1.0]
        let lut = LUT1D(values: values)
        
        XCTAssertEqual(lut.lookup(0.0), 0.0)
        XCTAssertEqual(lut.lookup(1.0), 1.0)
        
        // Test interpolation at 0.5 (midpoint between index 1 and 2)
        // Should be (0.25 + 0.75) / 2 = 0.5
        let mid = lut.lookup(0.5)
        XCTAssertEqual(mid, 0.5, accuracy: 0.01)
    }
    
    func test_lut1d_gamma() {
        let lut = LUT1D.gamma(2.2, points: 256)
        
        XCTAssertEqual(lut.values.count, 256)
        XCTAssertEqual(lut.lookup(0.0), 0.0, accuracy: 0.01)
        XCTAssertEqual(lut.lookup(1.0), 1.0, accuracy: 0.01)
        
        // Test gamma curve property: output < input for gamma > 1
        let mid = lut.lookup(0.5)
        XCTAssertLessThan(mid, 0.5)
    }
    
    func test_lut1d_gammaInverse() {
        let lut = LUT1D.gamma(1.0 / 2.2, points: 256)
        
        // Test inverse gamma curve property: output > input for gamma < 1
        let mid = lut.lookup(0.5)
        XCTAssertGreaterThan(mid, 0.5)
    }
    
    func test_lut1d_interpolation() {
        let values = [0.0, 1.0]
        let lut = LUT1D(values: values)
        
        XCTAssertEqual(lut.lookup(0.25), 0.25, accuracy: 0.01)
        XCTAssertEqual(lut.lookup(0.75), 0.75, accuracy: 0.01)
    }
    
    func test_lut1d_outOfBounds_above() {
        let lut = LUT1D(values: [0.2, 0.8])
        XCTAssertEqual(lut.lookup(1.5), 0.8)
    }

    func test_lut1d_outOfBounds_below() {
        // D48: inputs in (-1/(n-1), 0) used to truncate to index 0 and
        // extrapolate below the first entry (lookup(-0.5) gave -0.1).
        let lut = LUT1D(values: [0.2, 0.8])
        XCTAssertEqual(lut.lookup(-0.5), 0.2)
        XCTAssertEqual(lut.lookup(-0.0001), 0.2)
        XCTAssertEqual(lut.lookup(-1.5), 0.2)
        XCTAssertEqual(lut.lookup(0), 0.2)
        let longer = LUT1D(values: [0.1, 0.4, 0.6, 0.9])
        XCTAssertEqual(longer.lookup(-0.2), 0.1)
    }

    func test_lut1d_nonFiniteInputs() {
        // Int(_:) traps on NaN and infinity; the clip keeps them in the table.
        let lut = LUT1D(values: [0.2, 0.8])
        XCTAssertEqual(lut.lookup(.nan), 0.2)
        XCTAssertEqual(lut.lookup(-.infinity), 0.2)
        XCTAssertEqual(lut.lookup(.infinity), 0.8)
        XCTAssertEqual(lut.lookup(1e300), 0.8)
        XCTAssertEqual(lut.lookup(-1e300), 0.2)
        XCTAssertEqual(lut.lookup(1), 0.8)
        XCTAssertEqual(lut.lookup(0.5), 0.5, accuracy: 1e-12)
    }
    
    func test_lut1d_emptyValues() {
        let lut = LUT1D(values: [])
        
        // Should return input unchanged
        XCTAssertEqual(lut.lookup(0.5), 0.5)
    }
    
    func test_lut1d_singleValue() {
        let lut = LUT1D(values: [0.7])
        
        // Should return the single value
        XCTAssertEqual(lut.lookup(0.0), 0.7)
        XCTAssertEqual(lut.lookup(1.0), 0.7)
    }
    
    // MARK: - ColorLUT Tests
    
    func test_colorLUT_initialization() {
        let data = Array(repeating: 0.5, count: 17 * 17 * 17 * 3)
        let lut = ColorLUT(gridSize: 17, inputChannels: 3, outputChannels: 3, data: data)
        
        XCTAssertEqual(lut.gridSize, 17)
        XCTAssertEqual(lut.inputChannels, 3)
        XCTAssertEqual(lut.outputChannels, 3)
        XCTAssertEqual(lut.data.count, 17 * 17 * 17 * 3)
    }
    
    func test_colorLUT_lookup_identity() {
        // Create a simple identity CLUT (nearest neighbor, so not perfect identity)
        var data: [Double] = []
        let gridSize = 3
        
        for r in 0..<gridSize {
            for g in 0..<gridSize {
                for b in 0..<gridSize {
                    data.append(Double(r) / Double(gridSize - 1))
                    data.append(Double(g) / Double(gridSize - 1))
                    data.append(Double(b) / Double(gridSize - 1))
                }
            }
        }
        
        let lut = ColorLUT(gridSize: gridSize, inputChannels: 3, outputChannels: 3, data: data)
        
        // Test corners
        let result1 = lut.lookup(0.0, 0.0, 0.0)
        XCTAssertEqual(result1.0, 0.0, accuracy: 0.01)
        XCTAssertEqual(result1.1, 0.0, accuracy: 0.01)
        XCTAssertEqual(result1.2, 0.0, accuracy: 0.01)
        
        let result2 = lut.lookup(1.0, 1.0, 1.0)
        XCTAssertEqual(result2.0, 1.0, accuracy: 0.01)
        XCTAssertEqual(result2.1, 1.0, accuracy: 0.01)
        XCTAssertEqual(result2.2, 1.0, accuracy: 0.01)
    }
    
    func test_colorLUT_lookup_outOfBounds() {
        let data = Array(repeating: 0.5, count: 3 * 3 * 3 * 3)
        let lut = ColorLUT(gridSize: 3, inputChannels: 3, outputChannels: 3, data: data)
        
        // Should handle out of bounds gracefully
        let result = lut.lookup(-0.5, 1.5, 0.5)
        XCTAssertNotNil(result)
    }
    
    func test_colorLUT_nonFiniteInputs() {
        // D54: Int(_:) trapped on NaN and infinity; each channel is clipped to 0...1 first.
        // A 2-point grid whose output is the grid position of each channel.
        var data: [Double] = []
        for r in 0..<2 { for g in 0..<2 { for b in 0..<2 { data += [Double(r), Double(g), Double(b)] } } }
        let lut = ColorLUT(gridSize: 2, inputChannels: 3, outputChannels: 3, data: data)
        XCTAssertTrue(lut.lookup(.nan, .nan, .nan) == (0, 0, 0))
        XCTAssertTrue(lut.lookup(-.infinity, .infinity, .nan) == (0, 1, 0))
        XCTAssertTrue(lut.lookup(.infinity, -.infinity, .infinity) == (1, 0, 1))
        XCTAssertTrue(lut.lookup(1e300, -1e300, 2) == (1, 0, 1))
        XCTAssertTrue(lut.lookup(-0.5, 1.5, 0.25) == (0, 1, 0))
        XCTAssertTrue(lut.lookup(1, 0, 0.999) == (1, 0, 0))
        // A zero grid returns the input instead of indexing before the data
        let empty = ColorLUT(gridSize: 0, inputChannels: 3, outputChannels: 3, data: [0.5, 0.5, 0.5])
        XCTAssertTrue(empty.lookup(0.1, 0.2, 0.3) == (0.1, 0.2, 0.3))
    }
    
    // MARK: - LUTColorTransform Tests
    
    func test_lutTransform_identity() {
        let transform = LUTColorTransform(
            type: .aToB,
            inputTables: [LUT1D.identity, LUT1D.identity, LUT1D.identity],
            colorLUT: nil,
            outputTables: [LUT1D.identity, LUT1D.identity, LUT1D.identity],
            matrix: nil
        )
        
        let result = transform.apply(to: (0.5, 0.6, 0.7))
        XCTAssertEqual(result.0, 0.5, accuracy: 0.01)
        XCTAssertEqual(result.1, 0.6, accuracy: 0.01)
        XCTAssertEqual(result.2, 0.7, accuracy: 0.01)
    }
    
    func test_lutTransform_withInputTables() {
        let gamma = LUT1D.gamma(2.2, points: 256)
        
        let transform = LUTColorTransform(
            type: .aToB,
            inputTables: [gamma, gamma, gamma],
            colorLUT: nil,
            outputTables: [LUT1D.identity, LUT1D.identity, LUT1D.identity],
            matrix: nil
        )
        
        let result = transform.apply(to: (0.5, 0.5, 0.5))
        
        // Gamma 2.2 should darken midtones
        XCTAssertLessThan(result.0, 0.5)
        XCTAssertLessThan(result.1, 0.5)
        XCTAssertLessThan(result.2, 0.5)
    }
    
    func test_lutTransform_withMatrix() {
        let matrix = ColorMatrix.identity
        
        let transform = LUTColorTransform(
            type: .aToB,
            inputTables: [LUT1D.identity, LUT1D.identity, LUT1D.identity],
            colorLUT: nil,
            outputTables: [LUT1D.identity, LUT1D.identity, LUT1D.identity],
            matrix: matrix
        )
        
        let result = transform.apply(to: (0.5, 0.6, 0.7))
        XCTAssertEqual(result.0, 0.5, accuracy: 0.01)
        XCTAssertEqual(result.1, 0.6, accuracy: 0.01)
        XCTAssertEqual(result.2, 0.7, accuracy: 0.01)
    }
    
    func test_lutTransform_types() {
        XCTAssertEqual(LUTType.lut8.rawValue, "lut8")
        XCTAssertEqual(LUTType.lut16.rawValue, "lut16")
        XCTAssertEqual(LUTType.aToB.rawValue, "aToB")
        XCTAssertEqual(LUTType.bToA.rawValue, "bToA")
    }
    
    func test_lutTransform_parse_insufficientData() {
        let data = Data([0x00, 0x01])
        let result = LUTColorTransform.parse(from: data)
        
        XCTAssertNil(result)
    }
    
    func test_lutTransform_parse_lut8Type() {
        var data = Data(count: 48)
        
        // Type signature 'mft1' for lut8Type
        data.writeUInt32BE(0x6D667431, at: 0)
        
        // Reserved
        data.writeUInt32BE(0, at: 4)
        
        // Input channels: 3
        data[8] = 3
        
        // Output channels: 3
        data[9] = 3
        
        // CLUT grid points: 17
        data[10] = 17
        
        let result = LUTColorTransform.parse(from: data)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.type, .lut8)
        XCTAssertEqual(result?.inputTables.count, 3)
        XCTAssertEqual(result?.outputTables.count, 3)
    }
    
    func test_lutTransform_parse_lut16Type() {
        var data = Data(count: 48)
        
        // Type signature 'mft2' for lut16Type
        data.writeUInt32BE(0x6D667432, at: 0)
        
        let result = LUTColorTransform.parse(from: data)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.type, .lut16)
    }
    
    func test_lutTransform_parse_lutAToBType() {
        var data = Data(count: 32)
        
        // Type signature 'mAB ' for lutAToBType
        data.writeUInt32BE(0x6D414220, at: 0)
        
        let result = LUTColorTransform.parse(from: data)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.type, .aToB)
    }
    
    func test_lutTransform_parse_lutBToAType() {
        var data = Data(count: 32)
        
        // Type signature 'mBA ' for lutBToAType
        data.writeUInt32BE(0x6D424120, at: 0)
        
        let result = LUTColorTransform.parse(from: data)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.type, .bToA)
    }
    
    func test_lutTransform_parse_unknownType() {
        var data = Data(count: 32)
        
        // Unknown type signature
        data.writeUInt32BE(0x12345678, at: 0)
        
        let result = LUTColorTransform.parse(from: data)
        
        XCTAssertNil(result)
    }
    
    // MARK: - Integration Tests
    
    func test_lutTransform_fullPipeline() {
        // Create a realistic transform with all components
        let inputGamma = LUT1D.gamma(2.2, points: 256)
        let outputGamma = LUT1D.gamma(1.0 / 2.2, points: 256)
        
        let transform = LUTColorTransform(
            type: .aToB,
            inputTables: [inputGamma, inputGamma, inputGamma],
            colorLUT: nil,
            outputTables: [outputGamma, outputGamma, outputGamma],
            matrix: ColorMatrix.identity
        )
        
        // Apply full pipeline
        let result = transform.apply(to: (0.5, 0.5, 0.5))
        
        // After gamma 2.2 and inverse gamma (1/2.2), should be close to original
        XCTAssertEqual(result.0, 0.5, accuracy: 0.05)
        XCTAssertEqual(result.1, 0.5, accuracy: 0.05)
        XCTAssertEqual(result.2, 0.5, accuracy: 0.05)
    }
}

// MARK: - Data Extension Helper

extension Data {
    fileprivate mutating func writeUInt32BE(_ value: UInt32, at offset: Int) {
        let bytes = value.bigEndian
        Swift.withUnsafeBytes(of: bytes) { ptr in
            self.replaceSubrange(offset..<(offset + 4), with: ptr)
        }
    }
}
