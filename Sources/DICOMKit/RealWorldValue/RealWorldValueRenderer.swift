// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data (rendering)
//
// RealWorldValueRenderer.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Renderer for applying Real World Value transformations to pixel data
///
/// This renderer transforms stored pixel values to physical quantities using
/// Real World Value LUTs, enabling correct display and measurement of quantitative data.
///
/// Reference: PS3.3 C.7.6.16.2.11 - Real World Value Mapping Functional Group
public actor RealWorldValueRenderer {
    
    /// Real World Value LUTs available for rendering
    private let luts: [RealWorldValueLUT]
    
    /// Currently selected LUT index
    private var selectedLUTIndex: Int = 0
    
    // MARK: - Initialization
    
    /// Initialize renderer with Real World Value LUTs
    ///
    /// - Parameter luts: Array of Real World Value LUTs
    public init(luts: [RealWorldValueLUT]) {
        self.luts = luts
    }
    
    /// Initialize renderer with a single Real World Value LUT
    ///
    /// - Parameter lut: Real World Value LUT
    public init(lut: RealWorldValueLUT) {
        self.luts = [lut]
    }
    
    // MARK: - LUT Selection
    
    /// Get the currently selected LUT
    ///
    /// - Returns: Currently selected RealWorldValueLUT
    public func selectedLUT() -> RealWorldValueLUT? {
        guard selectedLUTIndex < luts.count else {
            return nil
        }
        return luts[selectedLUTIndex]
    }
    
    /// Select a LUT by index
    ///
    /// - Parameter index: Index of the LUT to select
    /// - Throws: If index is out of bounds
    public func selectLUT(at index: Int) throws {
        guard index >= 0 && index < luts.count else {
            throw RealWorldValueError.invalidLUTIndex(index, count: luts.count)
        }
        selectedLUTIndex = index
    }
    
    /// Get all available LUTs
    ///
    /// - Returns: Array of available RealWorldValueLUT objects
    public func availableLUTs() -> [RealWorldValueLUT] {
        luts
    }
    
    // MARK: - Pixel Value Transformation
    
    /// Apply transformation to a single pixel value
    ///
    /// - Parameter storedValue: Stored pixel value
    /// - Returns: Real world value
    public func apply(to storedValue: Int) -> Double? {
        guard let lut = selectedLUT() else {
            return nil
        }
        return lut.apply(to: storedValue)
    }
    
    /// Apply transformation to a single pixel value (Double precision)
    ///
    /// - Parameter storedValue: Stored pixel value
    /// - Returns: Real world value
    public func apply(to storedValue: Double) -> Double? {
        guard let lut = selectedLUT() else {
            return nil
        }
        return lut.apply(to: storedValue)
    }
    
    /// Apply transformation to an array of pixel values
    ///
    /// - Parameter storedValues: Array of stored pixel values
    /// - Returns: Array of real world values
    public func apply(to storedValues: [Int]) -> [Double]? {
        guard let lut = selectedLUT() else {
            return nil
        }
        return storedValues.map { lut.apply(to: $0) }
    }
    
    /// Apply transformation to an array of pixel values (Double precision)
    ///
    /// - Parameter storedValues: Array of stored pixel values
    /// - Returns: Array of real world values
    public func apply(to storedValues: [Double]) -> [Double]? {
        guard let lut = selectedLUT() else {
            return nil
        }
        return storedValues.map { lut.apply(to: $0) }
    }
    
    // MARK: - Frame-Specific Transformation
    
    /// Apply transformation for a specific frame
    ///
    /// Some LUTs have different mappings per frame (e.g., multi-energy CT).
    ///
    /// - Parameters:
    ///   - storedValue: Stored pixel value
    ///   - frameIndex: Frame index (0-based)
    /// - Returns: Real world value, or nil if no appropriate LUT exists
    public func apply(to storedValue: Int, forFrame frameIndex: Int) -> Double? {
        // Find appropriate LUT for this frame
        if let lut = findLUTForFrame(frameIndex) {
            return lut.apply(to: storedValue)
        }
        
        // Fall back to selected LUT
        return apply(to: storedValue)
    }
    
    /// Find appropriate LUT for a specific frame
    ///
    /// - Parameter frameIndex: Frame index (0-based)
    /// - Returns: RealWorldValueLUT appropriate for this frame, or nil
    private func findLUTForFrame(_ frameIndex: Int) -> RealWorldValueLUT? {
        for lut in luts {
            switch lut.frameScope {
            case .allFrames:
                return lut
                
            case .firstFrame:
                if frameIndex == 0 {
                    return lut
                }
                
            case .specificFrames(let frames):
                if frames.contains(frameIndex + 1) { // DICOM uses 1-based frame numbers
                    return lut
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Statistics
    
    /// Calculate statistics on real world values
    ///
    /// - Parameter storedValues: Array of stored pixel values
    /// - Returns: Statistics on the transformed values, or nil if no LUT selected
    public func statistics(for storedValues: [Int]) -> RealWorldValueStatistics? {
        guard let realWorldValues = apply(to: storedValues) else {
            return nil
        }
        
        guard !realWorldValues.isEmpty else {
            return nil
        }
        
        let sorted = realWorldValues.sorted()
        let count = Double(realWorldValues.count)
        
        let min = sorted.first!
        let max = sorted.last!
        let mean = realWorldValues.reduce(0.0, +) / count
        
        // Calculate standard deviation
        let variance = realWorldValues.reduce(0.0) { sum, value in
            let diff = value - mean
            return sum + diff * diff
        } / count
        let stdDev = sqrt(variance)
        
        let median: Double
        let midIndex = realWorldValues.count / 2
        if realWorldValues.count.isMultiple(of: 2) {
            median = (sorted[midIndex - 1] + sorted[midIndex]) / 2.0
        } else {
            median = sorted[midIndex]
        }
        
        return RealWorldValueStatistics(
            min: min,
            max: max,
            mean: mean,
            median: median,
            standardDeviation: stdDev,
            count: realWorldValues.count,
            units: selectedLUT()?.measurementUnits
        )
    }
}

// MARK: - RealWorldValueStatistics

/// Statistics on real world values
public struct RealWorldValueStatistics: Sendable {
    /// Minimum value
    public let min: Double
    
    /// Maximum value
    public let max: Double
    
    /// Mean (average) value
    public let mean: Double
    
    /// Median value
    public let median: Double
    
    /// Standard deviation
    public let standardDeviation: Double
    
    /// Number of values
    public let count: Int
    
    /// Measurement units
    public let units: RealWorldValueUnits?
    
    /// Initialize statistics
    public init(
        min: Double,
        max: Double,
        mean: Double,
        median: Double,
        standardDeviation: Double,
        count: Int,
        units: RealWorldValueUnits?
    ) {
        self.min = min
        self.max = max
        self.mean = mean
        self.median = median
        self.standardDeviation = standardDeviation
        self.count = count
        self.units = units
    }
}

// MARK: - RealWorldValueError

/// Errors related to Real World Value operations
public enum RealWorldValueError: Error, Sendable {
    /// Invalid LUT index
    case invalidLUTIndex(Int, count: Int)
    
    /// No LUT selected
    case noLUTSelected
    
    /// Incompatible units
    case incompatibleUnits(String, String)
}

extension RealWorldValueError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidLUTIndex(let index, let count):
            return "Invalid LUT index \(index). Available LUTs: 0..<\(count)"
            
        case .noLUTSelected:
            return "No Real World Value LUT is currently selected"
            
        case .incompatibleUnits(let unit1, let unit2):
            return "Incompatible units: \(unit1) and \(unit2)"
        }
    }
}
