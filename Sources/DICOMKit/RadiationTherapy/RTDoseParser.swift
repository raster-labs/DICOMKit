// NEMA-verified: 2026a, checked 2026-09-29 — RT Dose Module reads per PS3.3 2026a Table C.8-39; DVH Sequence reads (incl. DVH Volume Units (3004,0054)) per Table C.8-40
//
// RTDoseParser.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Parser for DICOM RT Dose objects
///
/// Parses RT Dose IODs from DICOM data sets, extracting dose grid geometry,
/// dose values, scaling factors, and DVH data.
///
/// Reference: PS3.3 A.18 - RT Dose IOD
public struct RTDoseParser {
    
    /// Parse RT Dose from a DICOM data set
    ///
    /// - Parameter dataSet: DICOM data set containing RT Dose
    /// - Returns: Parsed RT Dose
    /// - Throws: DICOMError if parsing fails
    public static func parse(from dataSet: DataSet) throws -> RTDose {
        // Parse SOP Instance UID and SOP Class UID
        guard let sopInstanceUID = dataSet.string(for: .sopInstanceUID) else {
            throw DICOMError.parsingFailed("Missing SOP Instance UID")
        }
        
        let sopClassUID = dataSet.string(for: .sopClassUID) ?? "1.2.840.10008.5.1.4.1.1.481.2"
        
        // Parse dose identification
        let comment = dataSet.string(for: .doseComment)
        let summationType = dataSet.string(for: .doseSummationType)
        let type = dataSet.string(for: .doseType)
        let units = dataSet.string(for: .doseUnits)
        
        // Parse referenced objects
        let referencedRTPlanUID = parseReferencedRTPlanUID(from: dataSet)
        let referencedStructureSetUID = parseReferencedStructureSetUID(from: dataSet)
        let referencedFractionGroupNumber = parseReferencedFractionGroupNumber(from: dataSet)
        let referencedBeamNumber = parseReferencedBeamNumber(from: dataSet)
        
        // Parse dose grid geometry
        let frameOfReferenceUID = dataSet.string(for: .frameOfReferenceUID)
        let imagePosition = parsePoint3D(from: dataSet, tag: .imagePositionPatient)
        let imageOrientation = parseDoubleArray(from: dataSet, tag: .imageOrientationPatient)
        let gridFrameOffsetVector = parseDoubleArray(from: dataSet, tag: .gridFrameOffsetVector)
        let pixelSpacing = parsePixelSpacing(from: dataSet)
        let sliceThickness = dataSet[.sliceThickness]?.decimalStringValue?.value
        
        // Parse dose grid dimensions
        guard let rows = dataSet.uint16(for: .rows),
              let columns = dataSet.uint16(for: .columns) else {
            throw DICOMError.parsingFailed("Missing rows or columns")
        }
        
        let numberOfFrames = dataSet[.numberOfFrames]?.integerStringValue?.value ?? 1
        let bitsAllocated = dataSet.uint16(for: .bitsAllocated) ?? 16
        let bitsStored = dataSet.uint16(for: .bitsStored) ?? 16
        let highBit = dataSet.uint16(for: .highBit) ?? 15
        
        // Parse dose scaling
        guard let doseGridScaling = dataSet[.doseGridScaling]?.decimalStringValue?.value else {
            throw DICOMError.parsingFailed("Missing Dose Grid Scaling")
        }
        
        let tissueHeterogeneityCorrection = dataSet.string(for: .tissueHeterogeneityCorrection)
        
        // Parse dose statistics (if available)
        let maximumDose: Double? = nil  // Could be calculated from pixel data
        let minimumDose: Double? = nil  // Could be calculated from pixel data
        let meanDose: Double? = nil     // Could be calculated from pixel data
        
        // Parse DVH data
        let dvhData = parseDVHData(from: dataSet)
        
        // Parse pixel data (optional - can be large)
        let (pixelData16, pixelData32) = try parsePixelData(
            from: dataSet,
            rows: Int(rows),
            columns: Int(columns),
            frames: numberOfFrames,
            bitsAllocated: Int(bitsAllocated)
        )
        
        return RTDose(
            sopInstanceUID: sopInstanceUID,
            sopClassUID: sopClassUID,
            comment: comment,
            summationType: summationType,
            type: type,
            units: units,
            referencedRTPlanUID: referencedRTPlanUID,
            referencedStructureSetUID: referencedStructureSetUID,
            referencedFractionGroupNumber: referencedFractionGroupNumber,
            referencedBeamNumber: referencedBeamNumber,
            frameOfReferenceUID: frameOfReferenceUID,
            imagePosition: imagePosition,
            imageOrientation: imageOrientation,
            gridFrameOffsetVector: gridFrameOffsetVector,
            pixelSpacing: pixelSpacing,
            sliceThickness: sliceThickness,
            rows: Int(rows),
            columns: Int(columns),
            numberOfFrames: numberOfFrames,
            bitsAllocated: Int(bitsAllocated),
            bitsStored: Int(bitsStored),
            highBit: Int(highBit),
            doseGridScaling: doseGridScaling,
            tissueHeterogeneityCorrection: tissueHeterogeneityCorrection,
            maximumDose: maximumDose,
            minimumDose: minimumDose,
            meanDose: meanDose,
            dvhData: dvhData,
            pixelData: pixelData16,
            pixelData32: pixelData32
        )
    }
    
    // MARK: - Private Parsing Methods
    
    /// Parse Referenced RT Plan SOP Instance UID
    private static func parseReferencedRTPlanUID(from dataSet: DataSet) -> String? {
        guard let sequence = dataSet.sequence(for: .referencedRTPlanSequence),
              let firstItem = sequence.first,
              let uid = firstItem.string(for: .referencedSOPInstanceUID) else {
            return nil
        }
        return uid
    }
    
    /// Parse Referenced Structure Set SOP Instance UID
    private static func parseReferencedStructureSetUID(from dataSet: DataSet) -> String? {
        guard let sequence = dataSet.sequence(for: .referencedStructureSetSequence),
              let firstItem = sequence.first,
              let uid = firstItem.string(for: .referencedSOPInstanceUID) else {
            return nil
        }
        return uid
    }
    
    /// Parse Referenced Fraction Group Number
    private static func parseReferencedFractionGroupNumber(from dataSet: DataSet) -> Int? {
        guard let sequence = dataSet.sequence(for: .referencedRTPlanSequence),
              let firstItem = sequence.first,
              let number = firstItem[.referencedFractionGroupNumber]?.integerStringValue?.value else {
            return nil
        }
        return number
    }
    
    /// Parse Referenced Beam Number
    private static func parseReferencedBeamNumber(from dataSet: DataSet) -> Int? {
        guard let sequence = dataSet.sequence(for: .referencedRTPlanSequence),
              let firstItem = sequence.first,
              let beamSeq = firstItem[Tag(group: 0x300C, element: 0x0004)]?.sequenceItems,
              let beamItem = beamSeq.first,
              let number = beamItem[.referencedBeamNumber]?.integerStringValue?.value else {
            return nil
        }
        return number
    }
    
    /// Parse Point3D from decimal string array
    private static func parsePoint3D(from dataSet: DataSet, tag: Tag) -> Point3D? {
        guard let data = dataSet[tag]?.valueData else {
            return nil
        }
        
        let values = parseDecimalStringArray(from: data)
        guard values.count == 3 else {
            return nil
        }
        
        return Point3D(
            x: values[0],
            y: values[1],
            z: values[2]
        )
    }
    
    /// Parse Point3D from sequence item
    private static func parsePoint3DFromItem(_ item: SequenceItem, tag: Tag) -> Point3D? {
        guard let data = item[tag]?.valueData else {
            return nil
        }
        
        let values = parseDecimalStringArray(from: data)
        guard values.count == 3 else {
            return nil
        }
        
        return Point3D(
            x: values[0],
            y: values[1],
            z: values[2]
        )
    }
    
    /// Parse double array from decimal string array
    private static func parseDoubleArray(from dataSet: DataSet, tag: Tag) -> [Double]? {
        guard let data = dataSet[tag]?.valueData else {
            return nil
        }
        
        return parseDecimalStringArray(from: data)
    }
    
    /// Parse decimal string array from raw data
    private static func parseDecimalStringArray(from data: Data) -> [Double] {
        guard let dataString = String(data: data, encoding: .ascii) else {
            return []
        }
        
        return dataString.split(separator: "\\").compactMap { Double($0) }
    }
    
    /// Parse pixel spacing (row spacing, column spacing)
    private static func parsePixelSpacing(from dataSet: DataSet) -> (row: Double, column: Double)? {
        guard let data = dataSet[.pixelSpacing]?.valueData else {
            return nil
        }
        
        let values = parseDecimalStringArray(from: data)
        guard values.count == 2 else {
            return nil
        }
        
        return (row: values[0], column: values[1])
    }
    
    /// Parse DVH (Dose Volume Histogram) Data
    private static func parseDVHData(from dataSet: DataSet) -> [DVHData] {
        guard let sequence = dataSet.sequence(for: .dvhSequence) else {
            return []
        }
        
        return sequence.compactMap { item in
            let type = item.string(for: .dvhType)
            let doseUnits = item.string(for: .doseUnits)
            let doseType = item.string(for: .doseType)
            // DVH Volume Units (3004,0054), CS, Type 1 in the DVH Sequence (PS3.3 Table C.8-40)
            let volumeUnits = item.string(for: .dvhVolumeUnits)
            let referencedROINumber = item[.referencedROINumber]?.integerStringValue?.value
            
            let normalizationPoint = parsePoint3DFromItem(item, tag: .dvhNormalizationPoint)
            let normalizationDoseValue = item[.dvhNormalizationDoseValue]?.decimalStringValue?.value
            let minimumDose = item[.dvhMinimumDose]?.decimalStringValue?.value
            let maximumDose = item[.dvhMaximumDose]?.decimalStringValue?.value
            let meanDose = item[.dvhMeanDose]?.decimalStringValue?.value
            
            // Parse DVH data pairs
            var dataPairs: [(dose: Double, volume: Double)] = []
            if let dvhDataRaw = item[.dvhData]?.valueData {
                let dvhDataValues = parseDecimalStringArray(from: dvhDataRaw)
                // DVH data comes as alternating dose/volume pairs
                for i in stride(from: 0, to: dvhDataValues.count - 1, by: 2) {
                    let dose = dvhDataValues[i]
                    let volume = dvhDataValues[i + 1]
                    dataPairs.append((dose: dose, volume: volume))
                }
            }
            
            return DVHData(
                type: type,
                doseUnits: doseUnits,
                doseType: doseType,
                volumeUnits: volumeUnits,
                referencedROINumber: referencedROINumber,
                normalizationPoint: normalizationPoint,
                normalizationDoseValue: normalizationDoseValue,
                minimumDose: minimumDose,
                maximumDose: maximumDose,
                meanDose: meanDose,
                data: dataPairs
            )
        }
    }
    
    /// Parse pixel data for dose grid
    private static func parsePixelData(
        from dataSet: DataSet,
        rows: Int,
        columns: Int,
        frames: Int,
        bitsAllocated: Int
    ) throws -> (pixelData16: [[[UInt16]]]?, pixelData32: [[[UInt32]]]?) {
        // For now, return nil - pixel data parsing would require accessing raw bytes
        // This would be implemented similar to PixelData parsing in DICOMKit
        // But is optional for the basic structure
        return (nil, nil)
    }
}
