// NEMA-verified: 2026a, checked 2026-09-29 — Parametric Map module reads per PS3.3 2026a C.8.32
//
// ParametricMapParser.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Parser for DICOM Parametric Map objects
///
/// Parses Parametric Map IODs from DICOM data sets, extracting real world value mappings,
/// quantity definitions, multi-frame pixel data properties, and functional groups.
///
/// Reference: PS3.3 A.75 - Parametric Map IOD
/// Reference: PS3.3 C.8.23 - Parametric Map Modules
/// Reference: PS3.3 C.7.6.16.2.11 - Real World Value Mapping Functional Group
public struct ParametricMapParser {
    
    /// Parse Parametric Map from a DICOM data set
    ///
    /// - Parameter dataSet: DICOM data set containing Parametric Map
    /// - Returns: Parsed Parametric Map
    /// - Throws: DICOMError if parsing fails
    public static func parse(from dataSet: DataSet) throws -> ParametricMap {
        // Parse SOP Instance UID and SOP Class UID
        guard let sopInstanceUID = dataSet.string(for: .sopInstanceUID) else {
            throw DICOMError.parsingFailed("Missing SOP Instance UID")
        }
        
        let sopClassUID = dataSet.string(for: .sopClassUID) ?? "1.2.840.10008.5.1.4.1.1.30"
        
        // Parse Series and Study UIDs
        guard let seriesInstanceUID = dataSet.string(for: .seriesInstanceUID) else {
            throw DICOMError.parsingFailed("Missing Series Instance UID")
        }
        
        guard let studyInstanceUID = dataSet.string(for: .studyInstanceUID) else {
            throw DICOMError.parsingFailed("Missing Study Instance UID")
        }
        
        // Parse Content Identification
        let instanceNumber = dataSet[.instanceNumber]?.integerStringValue?.value
        let contentLabel = dataSet.string(for: .contentLabel)
        let contentDescription = dataSet.string(for: .contentDescription)
        let contentCreatorName = dataSet.personName(for: .contentCreatorName)
        let contentDate = dataSet.date(for: .contentDate)
        let contentTime = dataSet.time(for: .contentTime)
        
        // Parse Derivation Information
        let derivationDescription = dataSet.string(for: .derivationDescription)
        let derivationCodeSequence = parseCodedEntries(from: dataSet, tag: .derivationCodeSequence)
        
        // Parse Real World Value Mappings (required for Parametric Maps)
        let realWorldValueMappings = parseRealWorldValueMappings(from: dataSet)
        
        // Parse Frame of Reference and Dimension Organization
        let frameOfReferenceUID = dataSet.string(for: .frameOfReferenceUID)
        let dimensionOrganizationUID = dataSet.string(for: .dimensionOrganizationUID)
        
        // Parse Referenced Series
        let referencedSeries = parseReferencedSeries(from: dataSet)
        
        // Parse Pixel Data Properties (required for multi-frame images)
        guard let numberOfFrames = dataSet[.numberOfFrames]?.integerStringValue?.value else {
            throw DICOMError.parsingFailed("Missing Number of Frames")
        }
        
        guard let rows = dataSet.uint16(for: .rows) else {
            throw DICOMError.parsingFailed("Missing Rows")
        }
        
        guard let columns = dataSet.uint16(for: .columns) else {
            throw DICOMError.parsingFailed("Missing Columns")
        }
        
        guard let bitsAllocated = dataSet.uint16(for: .bitsAllocated) else {
            throw DICOMError.parsingFailed("Missing Bits Allocated")
        }
        
        guard let bitsStored = dataSet.uint16(for: .bitsStored) else {
            throw DICOMError.parsingFailed("Missing Bits Stored")
        }
        
        guard let highBit = dataSet.uint16(for: .highBit) else {
            throw DICOMError.parsingFailed("Missing High Bit")
        }
        
        let samplesPerPixel = dataSet.uint16(for: .samplesPerPixel) ?? 1
        let photometricInterpretation = dataSet.string(for: .photometricInterpretation) ?? "MONOCHROME2"
        let pixelRepresentation = dataSet.uint16(for: .pixelRepresentation) ?? 0
        
        // Parse Functional Groups
        let sharedFunctionalGroups = parseSharedFunctionalGroups(from: dataSet)
        let perFrameFunctionalGroups = parsePerFrameFunctionalGroups(from: dataSet)
        
        return ParametricMap(
            sopInstanceUID: sopInstanceUID,
            sopClassUID: sopClassUID,
            seriesInstanceUID: seriesInstanceUID,
            studyInstanceUID: studyInstanceUID,
            instanceNumber: instanceNumber,
            contentLabel: contentLabel,
            contentDescription: contentDescription,
            contentCreatorName: contentCreatorName,
            contentDate: contentDate,
            contentTime: contentTime,
            derivationDescription: derivationDescription,
            derivationCodeSequence: derivationCodeSequence,
            realWorldValueMappings: realWorldValueMappings,
            frameOfReferenceUID: frameOfReferenceUID,
            dimensionOrganizationUID: dimensionOrganizationUID,
            referencedSeries: referencedSeries,
            numberOfFrames: numberOfFrames,
            rows: Int(rows),
            columns: Int(columns),
            bitsAllocated: Int(bitsAllocated),
            bitsStored: Int(bitsStored),
            highBit: Int(highBit),
            samplesPerPixel: Int(samplesPerPixel),
            photometricInterpretation: photometricInterpretation,
            pixelRepresentation: Int(pixelRepresentation),
            sharedFunctionalGroups: sharedFunctionalGroups,
            perFrameFunctionalGroups: perFrameFunctionalGroups
        )
    }
    
    // MARK: - Private Parsing Methods
    
    /// Parse Real World Value Mapping Sequence
    private static func parseRealWorldValueMappings(from dataSet: DataSet) -> [RealWorldValueMapping] {
        // Check for mappings in shared functional groups
        if let sharedGroups = dataSet.sequence(for: .sharedFunctionalGroupsSequence)?.first {
            if let mappingSequence = sharedGroups[.realWorldValueMappingSequence]?.sequenceItems {
                return mappingSequence.compactMap { parseRealWorldValueMapping(from: $0) }
            }
        }
        
        // Check for mappings at the dataset level
        if let mappingSequence = dataSet.sequence(for: .realWorldValueMappingSequence) {
            return mappingSequence.compactMap { parseRealWorldValueMapping(from: $0) }
        }
        
        return []
    }
    
    /// Parse a single Real World Value Mapping item
    private static func parseRealWorldValueMapping(from item: SequenceItem) -> RealWorldValueMapping? {
        // Parse label and explanation
        let label = item.string(for: .lutLabel)
        let explanation = item.string(for: .lutExplanation)
        
        // Parse measurement units (required)
        guard let measurementUnits = parseMeasurementUnits(from: item) else {
            return nil
        }
        
        // Parse quantity definition (optional)
        let quantityDefinition = parseQuantityDefinition(from: item)
        
        // Determine mapping method (linear or LUT)
        let mapping: MappingMethod
        
        // Linear transformation: Real World Value Slope (0040,9225) and
        // Intercept (0040,9224) are FD (PS3.6); a DS encoding is tolerated.
        if let slope = item[.realWorldValueSlope].flatMap(parseFlexibleDouble),
           let intercept = item[.realWorldValueIntercept].flatMap(parseFlexibleDouble) {
            mapping = .linear(slope: slope, intercept: intercept)
        }
        // Check for explicit LUT data - would be FD VR
        else if let lutDataElement = item[.realWorldValueLUTData],
                let lutData = extractDoubleArray(from: lutDataElement),
                !lutData.isEmpty {
            // Get first and last values mapped - might be DS or FD
            let firstValue: Double
            if let fdFirst = item[.doubleFloatRealWorldValueFirstValueMapped],
               let value = extractDouble(from: fdFirst) {
                firstValue = value
            } else if let dsFirst = item[.realWorldValueFirstValueMapped]?.decimalStringValue?.value {
                firstValue = dsFirst
            } else {
                firstValue = 0.0
            }
            
            let lastValue: Double
            if let fdLast = item[.doubleFloatRealWorldValueLastValueMapped],
               let value = extractDouble(from: fdLast) {
                lastValue = value
            } else if let dsLast = item[.realWorldValueLastValueMapped]?.decimalStringValue?.value {
                lastValue = dsLast
            } else {
                lastValue = Double(lutData.count - 1)
            }
            
            mapping = .lut(firstValueMapped: firstValue, lastValueMapped: lastValue, lutData: lutData)
        }
        else {
            // No valid mapping found
            return nil
        }
        
        return RealWorldValueMapping(
            label: label,
            explanation: explanation,
            measurementUnits: measurementUnits,
            quantityDefinition: quantityDefinition,
            mapping: mapping
        )
    }
    
    /// Extract a double value from a DataElement (handles FD VR)
    /// FD as binary, otherwise DS text.
    private static func parseFlexibleDouble(_ element: DataElement) -> Double? {
        if element.vr == .FD { return element.float64Value }
        return element.decimalStringValue?.value
    }
    
    private static func extractDouble(from element: DataElement) -> Double? {
        guard element.valueData.count >= 8 else {
            return nil
        }
        return element.valueData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: Double.self) }
    }
    
    /// Extract double array from a DataElement (handles FD VR)
    private static func extractDoubleArray(from element: DataElement) -> [Double]? {
        let count = element.valueData.count / 8
        guard count > 0 else {
            return nil
        }
        
        return element.valueData.withUnsafeBytes { buffer in
            let pointer = buffer.bindMemory(to: Double.self)
            return Array(pointer.prefix(count))
        }
    }
    
    /// Parse Measurement Units Code Sequence
    private static func parseMeasurementUnits(from dataSet: SequenceItem) -> MeasurementUnits? {
        guard let sequence = dataSet[Tag(group: 0x0040, element: 0x08EA)]?.sequenceItems,  // measurementUnitsCodeSequence
              let firstItem = sequence.first else {
            return nil
        }
        
        guard let codeValue = firstItem.string(for: Tag(group: 0x0008, element: 0x0100)),  // codeValue
              let codeMeaning = firstItem.string(for: Tag(group: 0x0008, element: 0x0104)) else {  // codeMeaning
            return nil
        }
        
        let codingSchemeDesignator = firstItem.string(for: Tag(group: 0x0008, element: 0x0102)) ?? "UCUM"  // codingSchemeDesignator
        
        return MeasurementUnits(
            codeValue: codeValue,
            codingSchemeDesignator: codingSchemeDesignator,
            codeMeaning: codeMeaning
        )
    }
    
    /// Parse Quantity Definition Sequence
    private static func parseQuantityDefinition(from dataSet: SequenceItem) -> QuantityDefinition? {
        guard let sequence = dataSet[.quantityDefinitionSequence]?.sequenceItems,
              let firstItem = sequence.first else {
            return nil
        }
        
        guard let codeValue = firstItem.string(for: Tag(group: 0x0008, element: 0x0100)),  // codeValue
              let codingSchemeDesignator = firstItem.string(for: Tag(group: 0x0008, element: 0x0102)),  // codingSchemeDesignator
              let codeMeaning = firstItem.string(for: Tag(group: 0x0008, element: 0x0104)) else {  // codeMeaning
            return nil
        }
        
        return QuantityDefinition(
            codeValue: codeValue,
            codingSchemeDesignator: codingSchemeDesignator,
            codeMeaning: codeMeaning
        )
    }
    
    /// Parse coded entries from a sequence
    private static func parseCodedEntries(from dataSet: DataSet, tag: Tag) -> [CodedEntry] {
        guard let sequence = dataSet.sequence(for: tag) else {
            return []
        }
        
        return sequence.compactMap { item in
            guard let codeValue = item.string(for: .codeValue),
                  let codingSchemeDesignator = item.string(for: .codingSchemeDesignator),
                  let codeMeaning = item.string(for: .codeMeaning) else {
                return nil
            }
            
            return CodedEntry(
                codeValue: codeValue,
                codingSchemeDesignator: codingSchemeDesignator,
                codeMeaning: codeMeaning
            )
        }
    }
    
    /// Parse Referenced Series Sequence
    private static func parseReferencedSeries(from dataSet: DataSet) -> [ParametricMapReferencedSeries] {
        guard let sequence = dataSet.sequence(for: .referencedSeriesSequence) else {
            return []
        }
        
        return sequence.compactMap { seriesItem -> ParametricMapReferencedSeries? in
            guard let seriesInstanceUID = seriesItem.string(for: .seriesInstanceUID) else {
                return nil
            }
            
            let referencedInstances = parseReferencedInstances(from: seriesItem)
            
            return ParametricMapReferencedSeries(
                seriesInstanceUID: seriesInstanceUID,
                referencedInstances: referencedInstances
            )
        }
    }
    
    /// Parse Referenced Instance Sequence
    private static func parseReferencedInstances(from dataSet: SequenceItem) -> [ReferencedInstance] {
        guard let sequence = dataSet[Tag(group: 0x0008, element: 0x114A)]?.sequenceItems else {  // referencedInstanceSequence
            return []
        }
        
        return sequence.compactMap { instanceItem -> ReferencedInstance? in
            guard let sopClassUID = instanceItem.string(for: Tag(group: 0x0008, element: 0x1150)),  // referencedSOPClassUID
                  let sopInstanceUID = instanceItem.string(for: Tag(group: 0x0008, element: 0x1155)) else {  // referencedSOPInstanceUID
                return nil
            }
            
            let frameNumbers = instanceItem[Tag(group: 0x0008, element: 0x1160)]?.integerStringValues?.map { $0.value } ?? []  // referencedFrameNumber
            
            return ReferencedInstance(
                referencedSOPClassUID: sopClassUID,
                referencedSOPInstanceUID: sopInstanceUID,
                referencedFrameNumbers: frameNumbers
            )
        }
    }
    
    /// Parse Shared Functional Groups Sequence
    private static func parseSharedFunctionalGroups(from dataSet: DataSet) -> FunctionalGroup? {
        guard let sequence = dataSet.sequence(for: .sharedFunctionalGroupsSequence),
              let firstItem = sequence.first else {
            return nil
        }
        
        return parseFunctionalGroup(from: firstItem)
    }
    
    /// Parse Per-Frame Functional Groups Sequence
    private static func parsePerFrameFunctionalGroups(from dataSet: DataSet) -> [FunctionalGroup] {
        guard let sequence = dataSet.sequence(for: .perFrameFunctionalGroupsSequence) else {
            return []
        }
        
        return sequence.compactMap { parseFunctionalGroup(from: $0) }
    }
    
    /// Parse a single Functional Group (simplified for parametric maps)
    private static func parseFunctionalGroup(from item: SequenceItem) -> FunctionalGroup? {
        // For parametric maps, we don't need segment identification
        // Just create an empty functional group as a placeholder
        // In the future, we can parse frame content, plane position, etc. if needed
        return FunctionalGroup()
    }
}

