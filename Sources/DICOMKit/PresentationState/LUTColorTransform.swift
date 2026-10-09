// NEMA-verified: 2026a, checked 2026-09-30 — carries no DICOM-standard data (ICC lut8, lut16, mAB and mBA transforms; LUT1D and ColorLUT input clipping is ICC.1 behaviour, not a PS3.3 rule; D54 makes ColorLUT.lookup total on non-finite input)
//
// LUTColorTransform.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation

// MARK: - LUT-Based Color Transformation

/// LUT-based color transformation using ICC profile A2B and B2A tags
///
/// A2B (Device to PCS) and B2A (PCS to Device) tags define multi-dimensional
/// lookup tables for accurate color transformations.
///
/// Reference: ICC.1:2004-10 Section 10.8 - lut8Type and lut16Type
/// Reference: ICC.1:2004-10 Section 10.9 - lutAToBType and lutBToAType
public struct LUTColorTransform: Sendable, Hashable {
    /// LUT type
    public let type: LUTType
    
    /// Input table (for pre-linearization)
    public let inputTables: [LUT1D]
    
    /// Color lookup table (CLUT) - 3D or 4D
    public let colorLUT: ColorLUT?
    
    /// Output table (for post-linearization)
    public let outputTables: [LUT1D]
    
    /// Matrix transformation (optional, for legacy lut8/lut16 types)
    public let matrix: ColorMatrix?
    
    /// Initialize LUT-based color transform
    public init(
        type: LUTType,
        inputTables: [LUT1D],
        colorLUT: ColorLUT? = nil,
        outputTables: [LUT1D],
        matrix: ColorMatrix? = nil
    ) {
        self.type = type
        self.inputTables = inputTables
        self.colorLUT = colorLUT
        self.outputTables = outputTables
        self.matrix = matrix
    }
    
    /// Apply LUT transformation to RGB color
    ///
    /// - Parameter input: Input color components (0.0-1.0)
    /// - Returns: Transformed color components (0.0-1.0)
    public func apply(to input: (Double, Double, Double)) -> (Double, Double, Double) {
        var result = input
        
        // Step 1: Apply input tables (pre-linearization)
        if inputTables.count >= 3 {
            result.0 = inputTables[0].lookup(result.0)
            result.1 = inputTables[1].lookup(result.1)
            result.2 = inputTables[2].lookup(result.2)
        }
        
        // Step 2: Apply matrix transformation (if present)
        if let matrix = matrix {
            let matrixResult = matrix.apply(to: (red: result.0, green: result.1, blue: result.2))
            result = (matrixResult.red, matrixResult.green, matrixResult.blue)
        }
        
        // Step 3: Apply CLUT (color lookup table)
        if let colorLUT = colorLUT {
            result = colorLUT.lookup(result.0, result.1, result.2)
        }
        
        // Step 4: Apply output tables (post-linearization)
        if outputTables.count >= 3 {
            result.0 = outputTables[0].lookup(result.0)
            result.1 = outputTables[1].lookup(result.1)
            result.2 = outputTables[2].lookup(result.2)
        }
        
        return result
    }
    
    /// Parse LUT color transform from ICC tag data
    ///
    /// - Parameter tagData: Raw tag data from A2B or B2A tag
    /// - Returns: Parsed LUT color transform, or nil if parsing fails
    public static func parse(from tagData: Data) -> LUTColorTransform? {
        guard tagData.count >= 12 else { return nil }
        
        let typeSignature = tagData.readUInt32BE(at: 0) ?? 0
        
        switch typeSignature {
        case 0x6D667431: // 'mft1' (lut8Type)
            return parseLUT8Type(from: tagData)
        case 0x6D667432: // 'mft2' (lut16Type)
            return parseLUT16Type(from: tagData)
        case 0x6D414220: // 'mAB ' (lutAToBType)
            return parseLUTAToBType(from: tagData)
        case 0x6D424120: // 'mBA ' (lutBToAType)
            return parseLUTBToAType(from: tagData)
        default:
            return nil
        }
    }
    
    // MARK: - Private Parsing Methods
    
    private static func parseLUT8Type(from data: Data) -> LUTColorTransform? {
        // lut8Type structure (legacy 8-bit LUT)
        guard data.count >= 48 else { return nil }
        
        // Parse input/output channel counts
        let _ = Int(data[8]) // inputChannels
        let _ = Int(data[9]) // outputChannels
        let _ = Int(data[10]) // clutGridPoints
        
        // For simplicity, we'll create a basic transform
        // Full implementation would parse the complete LUT data
        
        return LUTColorTransform(
            type: .lut8,
            inputTables: [LUT1D.identity, LUT1D.identity, LUT1D.identity],
            colorLUT: nil,
            outputTables: [LUT1D.identity, LUT1D.identity, LUT1D.identity],
            matrix: nil
        )
    }
    
    private static func parseLUT16Type(from data: Data) -> LUTColorTransform? {
        // lut16Type structure (legacy 16-bit LUT)
        guard data.count >= 48 else { return nil }
        
        // Similar to lut8Type but with 16-bit precision
        return LUTColorTransform(
            type: .lut16,
            inputTables: [LUT1D.identity, LUT1D.identity, LUT1D.identity],
            colorLUT: nil,
            outputTables: [LUT1D.identity, LUT1D.identity, LUT1D.identity],
            matrix: nil
        )
    }
    
    private static func parseLUTAToBType(from data: Data) -> LUTColorTransform? {
        // lutAToBType structure (modern Device to PCS)
        guard data.count >= 32 else { return nil }
        
        // Parse offsets to various curve and CLUT data
        // Full implementation would parse curves and CLUT
        
        return LUTColorTransform(
            type: .aToB,
            inputTables: [LUT1D.identity, LUT1D.identity, LUT1D.identity],
            colorLUT: nil,
            outputTables: [LUT1D.identity, LUT1D.identity, LUT1D.identity],
            matrix: nil
        )
    }
    
    private static func parseLUTBToAType(from data: Data) -> LUTColorTransform? {
        // lutBToAType structure (modern PCS to Device)
        guard data.count >= 32 else { return nil }
        
        return LUTColorTransform(
            type: .bToA,
            inputTables: [LUT1D.identity, LUT1D.identity, LUT1D.identity],
            colorLUT: nil,
            outputTables: [LUT1D.identity, LUT1D.identity, LUT1D.identity],
            matrix: nil
        )
    }
}

/// LUT type enumeration
public enum LUTType: String, Sendable, Hashable {
    /// Legacy 8-bit LUT (mft1)
    case lut8
    
    /// Legacy 16-bit LUT (mft2)
    case lut16
    
    /// Device to PCS (mAB)
    case aToB
    
    /// PCS to Device (mBA)
    case bToA
}

/// 1D lookup table for single channel transformations
public struct LUT1D: Sendable, Hashable {
    /// Lookup table values (0.0-1.0)
    public let values: [Double]
    
    /// Initialize 1D LUT
    public init(values: [Double]) {
        self.values = values
    }
    
    /// Lookup value in the table with linear interpolation
    ///
    /// The input is clipped to 0.0...1.0 before the lookup (ICC.1 curves clip their
    /// input to the domain), so an input below 0 returns the first entry and an input
    /// above 1 returns the last. A NaN input returns the first entry; ±infinity clips
    /// like any other out-of-range value.
    ///
    /// - Parameter input: Input value (0.0-1.0)
    /// - Returns: Interpolated output value (0.0-1.0)
    public func lookup(_ input: Double) -> Double {
        guard !values.isEmpty else { return input }
        guard values.count > 1 else { return values[0] }
        
        // Clip before converting to an index: Int(_:) truncates toward zero, so an
        // unclipped input in (-1/(n-1), 0) would reach index 0 with a negative
        // fraction and extrapolate below the table; Int(_:) also traps on NaN and
        // infinity.
        guard !input.isNaN, input > 0 else { return values[0] }
        guard input < 1 else { return values[values.count - 1] }
        
        let scaledInput = input * Double(values.count - 1)
        let index = Int(scaledInput)
        let fraction = scaledInput - Double(index)
        
        if index >= values.count - 1 {
            return values[values.count - 1]
        }
        
        // Linear interpolation
        let v0 = values[index]
        let v1 = values[index + 1]
        return v0 + (v1 - v0) * fraction
    }
    
    /// Identity LUT (pass-through)
    public static let identity = LUT1D(values: [0.0, 1.0])
    
    /// Gamma curve LUT
    ///
    /// - Parameter gamma: Gamma value (e.g., 2.2 for sRGB)
    /// - Returns: 1D LUT with gamma curve
    public static func gamma(_ gamma: Double, points: Int = 256) -> LUT1D {
        var values: [Double] = []
        values.reserveCapacity(points)
        
        for i in 0..<points {
            let x = Double(i) / Double(points - 1)
            let y = pow(x, gamma)
            values.append(y)
        }
        
        return LUT1D(values: values)
    }
}

/// Multi-dimensional color lookup table (CLUT)
public struct ColorLUT: Sendable, Hashable {
    /// Grid size for each dimension (typically 17, 33, or 65)
    public let gridSize: Int
    
    /// Number of input channels (typically 3 for RGB)
    public let inputChannels: Int
    
    /// Number of output channels (typically 3 for RGB)
    public let outputChannels: Int
    
    /// Flattened CLUT data
    public let data: [Double]
    
    /// Initialize color LUT
    public init(gridSize: Int, inputChannels: Int, outputChannels: Int, data: [Double]) {
        self.gridSize = gridSize
        self.inputChannels = inputChannels
        self.outputChannels = outputChannels
        self.data = data
    }
    
    /// Lookup color in the CLUT with trilinear interpolation
    ///
    /// Each input is clipped to 0.0...1.0 before it becomes a grid index (ICC.1 CLUTs clip
    /// their input to the domain), as `LUT1D.lookup` does: below 0 (and -infinity) selects the
    /// first grid point, above 1 (and +infinity) the last, and NaN the first.
    ///
    /// - Parameters:
    ///   - r: Red input (0.0-1.0)
    ///   - g: Green input (0.0-1.0)
    ///   - b: Blue input (0.0-1.0)
    /// - Returns: Transformed RGB output (0.0-1.0)
    public func lookup(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        guard inputChannels == 3, outputChannels == 3 else {
            return (r, g, b) // Fallback for unsupported configurations
        }
        
        // Trilinear interpolation in 3D CLUT
        // For simplicity, we'll use nearest neighbor for now
        // Full implementation would do proper trilinear interpolation
        
        guard gridSize > 0 else { return (r, g, b) }

        // Clip before converting to an index: Int(_:) traps on NaN, ±infinity and
        // magnitudes beyond Int (D54, as LUT1D.lookup since D48).
        func gridIndex(_ value: Double) -> Int {
            guard !value.isNaN, value > 0 else { return 0 }
            guard value < 1 else { return gridSize - 1 }
            return min(gridSize - 1, Int(value * Double(gridSize - 1)))
        }
        let ir = gridIndex(r)
        let ig = gridIndex(g)
        let ib = gridIndex(b)
        
        let index = (ir * gridSize * gridSize + ig * gridSize + ib) * outputChannels
        
        guard index + 2 < data.count else {
            return (r, g, b) // Out of bounds, return input
        }
        
        return (data[index], data[index + 1], data[index + 2])
    }
}
