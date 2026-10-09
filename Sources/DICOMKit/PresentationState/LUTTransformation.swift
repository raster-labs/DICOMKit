// NEMA-verified: 2026a, checked 2026-09-29 — PS3.3 2026a C.11.1.1 (65536 entries written as 0), C.11.4 and C.11.6 citations; table-valued VOI output is normalised by the applicator
//
// LUTTransformation.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-04.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

// MARK: - Modality LUT

/// Modality LUT transformation
///
/// Transforms stored pixel values to modality-specific units (e.g., Hounsfield Units for CT).
///
/// Reference: PS3.3 Section C.11.1 - Modality LUT Module
public enum ModalityLUT: Sendable, Hashable {
    /// Rescale transformation using slope and intercept
    /// Output = input * slope + intercept
    case rescale(slope: Double, intercept: Double, type: String?)
    
    /// Lookup table transformation
    case lut(LUTData)
    
    /// Apply the modality LUT transformation to a pixel value
    public func apply(to value: Int) -> Double {
        switch self {
        case .rescale(let slope, let intercept, _):
            return Double(value) * slope + intercept
            
        case .lut(let lutData):
            return lutData.lookup(value)
        }
    }
}

// MARK: - VOI LUT

/// VOI (Value of Interest) LUT transformation
///
/// Applies window/level settings to select the range of modality values to display.
///
/// Reference: PS3.3 Section C.11.2 - VOI LUT Module
public enum VOILUT: Sendable, Hashable {
    /// Window/level transformation
    case window(center: Double, width: Double, explanation: String?, function: VOILUTFunction)
    
    /// Lookup table transformation
    case lut(LUTData)
    
    /// Apply the VOI LUT transformation to a modality value
    public func apply(to value: Double) -> Double {
        switch self {
        case .window(let center, let width, _, let function):
            // Use WindowSettings to apply the transformation
            let settings = WindowSettings(center: center, width: width, function: function)
            return settings.apply(to: value)
            
        case .lut(let lutData):
            return lutData.lookup(Int(value))
        }
    }
}

// MARK: - Presentation LUT

/// Presentation LUT transformation
///
/// Final transformation for display, typically IDENTITY or INVERSE for polarity.
///
/// Reference: PS3.3 Section C.11.6 - Softcopy Presentation LUT Module (C.11.4 for the Presentation LUT Module)
public enum PresentationLUT: Sendable, Hashable {
    /// Identity transformation (default)
    case identity
    
    /// Inverse transformation (invert polarity)
    case inverse
    
    /// Lookup table transformation
    case lut(LUTData)
    
    /// Apply the presentation LUT transformation to a normalized value (0.0-1.0)
    public func apply(to value: Double) -> Double {
        switch self {
        case .identity:
            return value
            
        case .inverse:
            return 1.0 - value
            
        case .lut(let lutData):
            // Scale 0.0-1.0 to LUT input range
            let scaledValue = Int(value * Double(lutData.numberOfEntries - 1))
            let lutOutput = lutData.lookup(scaledValue)
            // Normalize LUT output back to 0.0-1.0
            return lutOutput / Double(lutData.maxOutputValue)
        }
    }
}

// MARK: - LUT Data

/// Lookup table data
///
/// Generic LUT structure used by Modality, VOI, and Presentation LUTs.
///
/// Reference: PS3.3 Section C.11 - Lookup Tables and Presentation States
public struct LUTData: Sendable, Hashable {
    /// Number of entries in the LUT
    public let numberOfEntries: Int
    
    /// First input value mapped by the LUT
    public let firstValueMapped: Int
    
    /// Number of bits per LUT entry
    public let bitsPerEntry: Int
    
    /// LUT data values
    public let data: [Int]
    
    /// Explanation of the LUT
    public let explanation: String?
    
    /// Maximum output value (2^bitsPerEntry - 1)
    public var maxOutputValue: Int {
        (1 << bitsPerEntry) - 1
    }
    
    /// Initialize LUT data
    public init(
        numberOfEntries: Int,
        firstValueMapped: Int,
        bitsPerEntry: Int,
        data: [Int],
        explanation: String? = nil
    ) {
        self.numberOfEntries = numberOfEntries
        self.firstValueMapped = firstValueMapped
        self.bitsPerEntry = bitsPerEntry
        self.data = data
        self.explanation = explanation
    }
    
    /// Look up a value in the LUT
    ///
    /// - Parameter value: Input value
    /// - Returns: Mapped output value
    public func lookup(_ value: Int) -> Double {
        // Calculate index into LUT
        var index = value - firstValueMapped
        
        // Clamp to valid range
        if index < 0 {
            index = 0
        } else if index >= numberOfEntries {
            index = numberOfEntries - 1
        }
        
        // Return the LUT value
        guard index < data.count else {
            return Double(data.last ?? 0)
        }
        
        return Double(data[index])
    }
}

// MARK: - LUT Descriptor Parsing

extension LUTData {
    /// Parse LUT descriptor from DICOM data element values
    ///
    /// The LUT Descriptor is a three-value array: [numberOfEntries, firstValueMapped, bitsPerEntry]
    ///
    /// - Parameters:
    ///   - descriptor: Array of 3 integers from the LUT Descriptor element
    ///   - data: LUT data values
    ///   - explanation: Optional explanation string
    /// - Returns: Parsed LUT data, or nil if descriptor is invalid
    public static func parse(
        descriptor: [Int],
        data: [Int],
        explanation: String? = nil
    ) -> LUTData? {
        guard descriptor.count == 3 else {
            return nil
        }
        
        var numberOfEntries = descriptor[0]
        let firstValueMapped = descriptor[1]
        let bitsPerEntry = descriptor[2]
        
        // Special case: 0 means 65536 entries
        if numberOfEntries == 0 {
            numberOfEntries = 65536
        }
        
        return LUTData(
            numberOfEntries: numberOfEntries,
            firstValueMapped: firstValueMapped,
            bitsPerEntry: bitsPerEntry,
            data: data,
            explanation: explanation
        )
    }
}
