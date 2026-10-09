// NEMA-verified: 2026a, checked 2026-09-29 — Real World Value Mapping reads per PS3.3 2026a C.7.6.16.2.11
//
// RealWorldValueLUTParser.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Parser for Real World Value LUT information from DICOM data sets
///
/// Reference: PS3.3 C.7.6.16.2.11 - Real World Value Mapping Functional Group
/// Reference: PS3.3 C.11.1 - Modality LUT Module
public struct RealWorldValueLUTParser {
    
    /// Parse Real World Value LUT from a data set
    ///
    /// This method supports both:
    /// - Legacy Modality LUT (Rescale Slope/Intercept)
    /// - Modern Real World Value Mapping Sequence
    ///
    /// - Parameter dataSet: DataSet (DICOM data set wrapper)
    /// - Returns: Array of parsed RealWorldValueLUT objects
    public static func parse(from dataSet: DataSet) -> [RealWorldValueLUT] {
        var luts: [RealWorldValueLUT] = []
        
        // Try parsing from Real World Value Mapping Sequence first (modern approach)
        if let rwvMappingLUTs = parseRealWorldValueMappingSequence(from: dataSet) {
            luts.append(contentsOf: rwvMappingLUTs)
        }
        
        // Fall back to Modality LUT (Rescale Slope/Intercept) if no RWV mapping found
        if luts.isEmpty, let modalityLUT = parseModalityLUT(from: dataSet) {
            luts.append(modalityLUT)
        }
        
        return luts
    }
    
    // MARK: - Real World Value Mapping Sequence Parsing
    
    /// Parse Real World Value Mapping Sequence
    ///
    /// - Parameter dataSet: The DICOM data set
    /// - Returns: Array of RealWorldValueLUT objects, or nil if not present
    private static func parseRealWorldValueMappingSequence(
        from dataSet: DataSet
    ) -> [RealWorldValueLUT]? {
        // Real World Value Mapping Sequence is typically in Shared or Per-Frame Functional Groups
        // First check Shared Functional Groups
        if let sharedGroups = dataSet.sequence(for: Tag.sharedFunctionalGroupsSequence),
           let firstGroup = sharedGroups.first,
           let rwvLUTs = parseRWVMappingFromFunctionalGroup(firstGroup) {
            return rwvLUTs
        }
        
        // If not in shared, check Per-Frame Functional Groups (frame 1)
        if let perFrameGroups = dataSet.sequence(for: Tag.perFrameFunctionalGroupsSequence),
           let firstFrame = perFrameGroups.first,
           let rwvLUTs = parseRWVMappingFromFunctionalGroup(firstFrame) {
            return rwvLUTs
        }
        
        return nil
    }
    
    /// Parse RWV Mapping from a functional group item
    ///
    /// - Parameter functionalGroup: Functional group sequence item
    /// - Returns: Array of RealWorldValueLUT objects, or nil if not present
    private static func parseRWVMappingFromFunctionalGroup(
        _ functionalGroup: SequenceItem
    ) -> [RealWorldValueLUT]? {
        // Real World Value Mapping Sequence (0040,9096)
        guard let rwvSequence = functionalGroup[Tag(group: 0x0040, element: 0x9096)]?.sequenceItems else {
            return nil
        }
        
        return rwvSequence.compactMap { item in
            parseRWVMappingItem(item)
        }
    }
    
    /// Parse a single Real World Value Mapping item
    ///
    /// - Parameter item: Sequence item from Real World Value Mapping Sequence
    /// - Returns: RealWorldValueLUT, or nil if parsing fails
    private static func parseRWVMappingItem(_ item: SequenceItem) -> RealWorldValueLUT? {
        // LUT Label (0040,9210)
        let label = item.string(for: Tag(group: 0x0040, element: 0x9210))
        
        // LUT Explanation (0028,3003). Not (0040,9211), which is Real World
        // Value Last Value Mapped (US/SS) and belongs to the LUT branch below.
        let explanation = item.string(for: .lutExplanation)
        
        // Measurement Units Code Sequence (0040,08EA)
        guard let unitsSequence = item[Tag(group: 0x0040, element: 0x08EA)]?.sequenceItems,
              let unitsItem = unitsSequence.first else {
            return nil
        }
        
        guard let units = parseCodedConcept(from: unitsItem) else {
            return nil
        }
        
        let measurementUnits = RealWorldValueUnits(
            codeValue: units.codeValue,
            codingSchemeDesignator: units.codingSchemeDesignator,
            codeMeaning: units.codeMeaning
        )
        
        // Quantity Definition Sequence (0040,9220) - optional
        let quantityDefinition: DICOMCore.CodedConcept?
        if let quantitySequence = item[Tag(group: 0x0040, element: 0x9220)]?.sequenceItems,
           let quantityItem = quantitySequence.first {
            quantityDefinition = parseCodedConcept(from: quantityItem)
        } else {
            quantityDefinition = nil
        }
        
        // Parse transformation (linear or LUT)
        let transformation: RealWorldValueLUT.Transformation
        
        // Try linear transformation first (Real World Value Slope/Intercept)
        // Real World Value Slope (0040,9225) and Intercept (0040,9224)
        if let slope = item[Tag(group: 0x0040, element: 0x9225)]?.float64Value,
           let intercept = item[Tag(group: 0x0040, element: 0x9224)]?.float64Value {
            transformation = .linear(slope: slope, intercept: intercept)
        }
        // Try LUT Data (0040,9212). The mapped range is either the US/SS pair
        // Real World Value First/Last Value Mapped (0040,9216)/(0040,9211) or,
        // for float pixel data, the FD pair Double Float Real World Value
        // First/Last Value Mapped (0040,9214)/(0040,9213).
        else if let lutData = item[.realWorldValueLUTData]?.float64Values,
                let firstValueMapped = item[.realWorldValueFirstValueMapped]?.uint16Value.map(Double.init)
                    ?? item[.doubleFloatRealWorldValueFirstValueMapped]?.float64Value,
                let lastValueMapped = item[.realWorldValueLastValueMapped]?.uint16Value.map(Double.init)
                    ?? item[.doubleFloatRealWorldValueLastValueMapped]?.float64Value {
            let descriptor = RealWorldValueLUT.LUTDescriptor(
                firstValueMapped: firstValueMapped,
                lastValueMapped: lastValueMapped
            )
            transformation = .lut(descriptor, data: lutData)
        } else {
            return nil
        }
        
        return RealWorldValueLUT(
            label: label,
            explanation: explanation,
            measurementUnits: measurementUnits,
            quantityDefinition: quantityDefinition,
            transformation: transformation
        )
    }
    
    // MARK: - Modality LUT Parsing (Legacy)
    
    /// Parse Modality LUT (Rescale Slope/Intercept)
    ///
    /// - Parameter dataSet: The DICOM data set
    /// - Returns: RealWorldValueLUT, or nil if not present
    private static func parseModalityLUT(from dataSet: DataSet) -> RealWorldValueLUT? {
        // Rescale Slope (0028,1053) and Rescale Intercept (0028,1052)
        guard let slope = dataSet.float64(for: Tag.rescaleSlope),
              let intercept = dataSet.float64(for: Tag.rescaleIntercept) else {
            return nil
        }
        
        // Rescale Type (0028,1054) - optional, describes the units
        let rescaleType = dataSet.string(for: Tag.rescaleType)
        
        // Determine units based on rescale type
        let units: RealWorldValueUnits
        let quantity: DICOMCore.CodedConcept?
        
        switch rescaleType?.uppercased() {
        case "HU":
            units = .hounsfield
            quantity = .hounsfield
            
        case "US":
            // Unspecified - use ratio
            units = .ratio
            quantity = nil
            
        case "OD":
            // Optical density
            units = RealWorldValueUnits(codeValue: "{od}", codeMeaning: "optical density")
            quantity = nil
            
        default:
            // Default to ratio for unknown types
            units = .ratio
            quantity = nil
        }
        
        return RealWorldValueLUT(
            label: rescaleType,
            explanation: rescaleType != nil ? "Modality LUT: \(rescaleType!)" : "Modality LUT",
            measurementUnits: units,
            quantityDefinition: quantity,
            transformation: .linear(slope: slope, intercept: intercept)
        )
    }
    
    // MARK: - Helper Methods
    
    /// Parse a coded concept from a sequence item
    ///
    /// - Parameter item: Sequence item containing Code Value, Coding Scheme Designator, Code Meaning
    /// - Returns: CodedConcept, or nil if required fields are missing
    private static func parseCodedConcept(from item: SequenceItem) -> DICOMCore.CodedConcept? {
        guard let codeValue = item.string(for: Tag.codeValue),
              let codingScheme = item.string(for: Tag.codingSchemeDesignator),
              let codeMeaning = item.string(for: Tag.codeMeaning) else {
            return nil
        }
        
        return DICOMCore.CodedConcept(
            codeValue: codeValue,
            codingSchemeDesignator: codingScheme,
            codeMeaning: codeMeaning
        )
    }
}

// NOTE: sharedFunctionalGroupsSequence / perFrameFunctionalGroupsSequence are
// defined publicly in DICOMCore (Tag+Segmentation.swift) — the internal copies
// that used to live here were removed to avoid ambiguity under @testable.
