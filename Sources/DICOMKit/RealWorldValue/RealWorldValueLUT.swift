// NEMA-verified: 2026a, checked 2026-09-29 — quantity codes diffed by Scripts/diff_kit.py against PS3.16 2026a Table D-1 (T1, T2, T2*, ve, Vp, rCBF, rCBV, MTT and SUV corrected)
//
// RealWorldValueLUT.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Real World Value Lookup Table
///
/// Transforms stored pixel values to physical quantity values with units.
/// Supports both linear transformation (slope/intercept) and explicit LUT data.
///
/// Reference: PS3.3 C.7.6.16.2.11 - Real World Value Mapping Functional Group
/// Reference: PS3.3 C.11.1 - Modality LUT Module (Rescale Slope/Intercept)
public struct RealWorldValueLUT: Sendable, Hashable {
    
    // MARK: - Properties
    
    /// Label for this LUT
    public let label: String?
    
    /// Explanation of the LUT
    public let explanation: String?
    
    /// Measurement units (UCUM coded entry)
    public let measurementUnits: RealWorldValueUnits
    
    /// Quantity definition (what physical quantity is being mapped)
    public let quantityDefinition: DICOMCore.CodedConcept?
    
    /// Transformation method
    public let transformation: Transformation
    
    /// Scope of this mapping (first frame only or all frames)
    public let frameScope: FrameScope
    
    // MARK: - Initialization
    
    /// Initialize a Real World Value LUT
    ///
    /// - Parameters:
    ///   - label: Optional label for this LUT
    ///   - explanation: Optional explanation
    ///   - measurementUnits: Units of measurement (UCUM)
    ///   - quantityDefinition: Optional quantity definition
    ///   - transformation: The transformation method (linear or LUT)
    ///   - frameScope: Scope of mapping (first frame or all frames)
    public init(
        label: String? = nil,
        explanation: String? = nil,
        measurementUnits: RealWorldValueUnits,
        quantityDefinition: DICOMCore.CodedConcept? = nil,
        transformation: Transformation,
        frameScope: FrameScope = .allFrames
    ) {
        self.label = label
        self.explanation = explanation
        self.measurementUnits = measurementUnits
        self.quantityDefinition = quantityDefinition
        self.transformation = transformation
        self.frameScope = frameScope
    }
    
    // MARK: - Transformation Application
    
    /// Apply the transformation to a stored pixel value
    ///
    /// - Parameter storedValue: The stored pixel value
    /// - Returns: The real world value with physical units
    public func apply(to storedValue: Int) -> Double {
        transformation.apply(to: storedValue)
    }
    
    /// Apply the transformation to a stored pixel value (Double precision)
    ///
    /// - Parameter storedValue: The stored pixel value
    /// - Returns: The real world value with physical units
    public func apply(to storedValue: Double) -> Double {
        transformation.apply(to: storedValue)
    }
}

// MARK: - Transformation

extension RealWorldValueLUT {
    
    /// Transformation method for mapping stored values to real world values
    public enum Transformation: Sendable, Hashable {
        /// Linear transformation: RealWorldValue = slope * StoredValue + intercept
        case linear(slope: Double, intercept: Double)
        
        /// Explicit LUT data mapping
        case lut(LUTDescriptor, data: [Double])
        
        /// Apply the transformation to a stored value
        ///
        /// - Parameter storedValue: The stored pixel value
        /// - Returns: The real world value
        public func apply(to storedValue: Int) -> Double {
            apply(to: Double(storedValue))
        }
        
        /// Apply the transformation to a stored value (Double precision)
        ///
        /// - Parameter storedValue: The stored pixel value
        /// - Returns: The real world value
        public func apply(to storedValue: Double) -> Double {
            switch self {
            case .linear(let slope, let intercept):
                return storedValue * slope + intercept
                
            case .lut(let descriptor, let data):
                return descriptor.lookup(storedValue, in: data)
            }
        }
    }
}

// MARK: - LUT Descriptor

extension RealWorldValueLUT {
    
    /// LUT descriptor for explicit LUT mapping
    public struct LUTDescriptor: Sendable, Hashable {
        /// First stored value mapped by the LUT
        public let firstValueMapped: Double
        
        /// Last stored value mapped by the LUT
        public let lastValueMapped: Double
        
        /// Number of entries in the LUT
        public var numberOfEntries: Int {
            Int(lastValueMapped - firstValueMapped) + 1
        }
        
        /// Initialize a LUT descriptor
        ///
        /// - Parameters:
        ///   - firstValueMapped: First stored value mapped
        ///   - lastValueMapped: Last stored value mapped
        public init(firstValueMapped: Double, lastValueMapped: Double) {
            self.firstValueMapped = firstValueMapped
            self.lastValueMapped = lastValueMapped
        }
        
        /// Look up a stored value in the LUT data
        ///
        /// - Parameters:
        ///   - storedValue: The stored pixel value
        ///   - data: The LUT data array
        /// - Returns: The mapped real world value
        public func lookup(_ storedValue: Double, in data: [Double]) -> Double {
            // Clamp to valid range
            let clampedValue = max(firstValueMapped, min(lastValueMapped, storedValue))
            
            // Calculate index
            let index = Int((clampedValue - firstValueMapped))
            
            // Bounds check
            guard index >= 0 && index < data.count else {
                // Return edge value if out of bounds
                return index < 0 ? data.first ?? 0.0 : data.last ?? 0.0
            }
            
            return data[index]
        }
    }
}

// MARK: - Frame Scope

extension RealWorldValueLUT {
    
    /// Scope of the real world value mapping
    public enum FrameScope: Sendable, Hashable {
        /// Mapping applies to first frame only
        case firstFrame
        
        /// Mapping applies to all frames
        case allFrames
        
        /// Mapping applies to specific frames
        case specificFrames([Int])
    }
}

// MARK: - RealWorldValueUnits

/// Real World Value Units using UCUM (Unified Code for Units of Measure)
///
/// Reference: PS3.16 CID 83 - Units of Measurement
public struct RealWorldValueUnits: Sendable, Hashable {
    
    /// Code value (UCUM unit code)
    public let codeValue: String
    
    /// Coding scheme designator (should be "UCUM")
    public let codingSchemeDesignator: String
    
    /// Code meaning (human-readable unit description)
    public let codeMeaning: String
    
    /// Initialize Real World Value Units
    ///
    /// - Parameters:
    ///   - codeValue: UCUM unit code
    ///   - codingSchemeDesignator: Coding scheme (default "UCUM")
    ///   - codeMeaning: Human-readable unit description
    public init(
        codeValue: String,
        codingSchemeDesignator: String = "UCUM",
        codeMeaning: String
    ) {
        self.codeValue = codeValue
        self.codingSchemeDesignator = codingSchemeDesignator
        self.codeMeaning = codeMeaning
    }
}

// MARK: - Common Units

extension RealWorldValueUnits {
    
    // MARK: Hounsfield Units
    
    /// Hounsfield Units (HU) for CT
    public static let hounsfield = RealWorldValueUnits(
        codeValue: "[hnsf'U]",
        codeMeaning: "Hounsfield unit"
    )
    
    // MARK: Diffusion
    
    /// mm²/s (for ADC maps)
    public static let mm2PerSecond = RealWorldValueUnits(
        codeValue: "mm2/s",
        codeMeaning: "square millimeter per second"
    )
    
    // MARK: Time
    
    /// ms (for T1/T2 relaxation maps)
    public static let millisecond = RealWorldValueUnits(
        codeValue: "ms",
        codeMeaning: "millisecond"
    )
    
    /// s (for time measurements)
    public static let second = RealWorldValueUnits(
        codeValue: "s",
        codeMeaning: "second"
    )
    
    // MARK: SUV Units
    
    /// g/ml (for SUV maps - standardized uptake value)
    public static let gPerML = RealWorldValueUnits(
        codeValue: "g/ml",
        codeMeaning: "gram per milliliter"
    )
    
    /// Bq/ml (becquerel per milliliter - PET activity concentration)
    public static let bqPerML = RealWorldValueUnits(
        codeValue: "Bq/ml",
        codeMeaning: "becquerel per milliliter"
    )
    
    // MARK: Perfusion
    
    /// 1/min (for perfusion Ktrans)
    public static let perMinute = RealWorldValueUnits(
        codeValue: "/min",
        codeMeaning: "per minute"
    )
    
    /// ml/100g/min (for cerebral blood flow)
    public static let mlPer100gPerMin = RealWorldValueUnits(
        codeValue: "ml/(100.g.min)",
        codeMeaning: "milliliter per 100 grams per minute"
    )
    
    // MARK: Ratios and Dimensionless
    
    /// Unitless ratio
    public static let ratio = RealWorldValueUnits(
        codeValue: "1",
        codeMeaning: "no units"
    )
    
    /// Percentage
    public static let percent = RealWorldValueUnits(
        codeValue: "%",
        codeMeaning: "percent"
    )
}

// MARK: - Common Quantity Definitions

extension DICOMCore.CodedConcept {
    
    // MARK: Diffusion Quantities
    
    /// Apparent Diffusion Coefficient (ADC)
    public static let adc = CodedConcept(
        codeValue: "113041",
        codingSchemeDesignator: "DCM",
        codeMeaning: "Apparent Diffusion Coefficient"
    )
    
    // MARK: Relaxation Times
    
    /// T1 relaxation time
    public static let t1 = CodedConcept(
        codeValue: "113063",
        codingSchemeDesignator: "DCM",
        codeMeaning: "T1"
    )

    /// T2 relaxation time
    public static let t2 = CodedConcept(
        codeValue: "113065",
        codingSchemeDesignator: "DCM",
        codeMeaning: "T2"
    )

    /// T2* relaxation time
    public static let t2Star = CodedConcept(
        codeValue: "113064",
        codingSchemeDesignator: "DCM",
        codeMeaning: "T2*"
    )
    
    // MARK: Perfusion Quantities
    
    /// Ktrans (volume transfer constant)
    public static let ktrans = CodedConcept(
        codeValue: "126312",
        codingSchemeDesignator: "DCM",
        codeMeaning: "Ktrans"
    )
    
    /// ve (extravascular extracellular volume fraction)
    public static let ve = CodedConcept(
        codeValue: "126314",
        codingSchemeDesignator: "DCM",
        codeMeaning: "ve"
    )

    /// Vp (plasma volume fraction)
    public static let vp = CodedConcept(
        codeValue: "126331",
        codingSchemeDesignator: "DCM",
        codeMeaning: "Vp"
    )

    /// Regional Cerebral Blood Flow (CBF)
    public static let cbf = CodedConcept(
        codeValue: "113055",
        codingSchemeDesignator: "DCM",
        codeMeaning: "Regional Cerebral Blood Flow"
    )

    /// Regional Cerebral Blood Volume (CBV)
    public static let cbv = CodedConcept(
        codeValue: "113056",
        codingSchemeDesignator: "DCM",
        codeMeaning: "Regional Cerebral Blood Volume"
    )

    /// Mean Transit Time (MTT)
    public static let mtt = CodedConcept(
        codeValue: "113052",
        codingSchemeDesignator: "DCM",
        codeMeaning: "Mean Transit Time"
    )
    
    // MARK: SUV Quantities
    
    /// Standardized Uptake Value (SUV)
    public static let suv = CodedConcept(
        codeValue: "126400",
        codingSchemeDesignator: "DCM",
        codeMeaning: "Standardized Uptake Value"
    )
    
    /// SUV body weight (SUVbw)
    public static let suvbw = CodedConcept(
        codeValue: "126401",
        codingSchemeDesignator: "DCM",
        codeMeaning: "SUVbw"
    )

    /// SUV lean body mass (SUVlbm)
    public static let suvlbm = CodedConcept(
        codeValue: "126402",
        codingSchemeDesignator: "DCM",
        codeMeaning: "SUVlbm"
    )

    /// SUV body surface area (SUVbsa)
    public static let suvbsa = CodedConcept(
        codeValue: "126403",
        codingSchemeDesignator: "DCM",
        codeMeaning: "SUVbsa"
    )

    /// SUV ideal body weight (SUVibw)
    public static let suvibw = CodedConcept(
        codeValue: "126404",
        codingSchemeDesignator: "DCM",
        codeMeaning: "SUVibw"
    )
    
    // MARK: CT Quantities
    
    /// Hounsfield Unit
    public static let hounsfield = CodedConcept(
        codeValue: "112031",
        codingSchemeDesignator: "DCM",
        codeMeaning: "Attenuation Coefficient"
    )
}
