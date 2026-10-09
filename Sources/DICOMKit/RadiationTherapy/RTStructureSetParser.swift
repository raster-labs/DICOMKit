// NEMA-verified: 2026a, checked 2026-09-29 — RT Structure Set module reads per PS3.3 2026a C.8.8.5-C.8.8.8
//
// RTStructureSetParser.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Parser for DICOM RT Structure Set objects
///
/// Parses RT Structure Set IODs from DICOM data sets, extracting structure set metadata,
/// ROI definitions, contour geometries, and clinical observations.
///
/// Reference: PS3.3 A.19 - RT Structure Set IOD
public struct RTStructureSetParser {
    
    /// Parse RT Structure Set from a DICOM data set
    ///
    /// - Parameter dataSet: DICOM data set containing RT Structure Set
    /// - Returns: Parsed RT Structure Set
    /// - Throws: DICOMError if parsing fails
    public static func parse(from dataSet: DataSet) throws -> RTStructureSet {
        // Parse SOP Instance UID and SOP Class UID
        guard let sopInstanceUID = dataSet.string(for: .sopInstanceUID) else {
            throw DICOMError.parsingFailed("Missing SOP Instance UID")
        }
        
        let sopClassUID = dataSet.string(for: .sopClassUID) ?? "1.2.840.10008.5.1.4.1.1.481.3"
        
        // Parse Structure Set identification
        let label = dataSet.string(for: .structureSetLabel)
        let name = dataSet.string(for: .structureSetName)
        let description = dataSet.string(for: .structureSetDescription)
        let date = dataSet.date(for: .structureSetDate)
        let time = dataSet.time(for: .structureSetTime)
        
        // Parse Referenced Frame of Reference
        let frameOfReferenceUID = parseFrameOfReferenceUID(from: dataSet)
        let referencedStudyInstanceUID = parseReferencedStudyUID(from: dataSet)
        let referencedSeriesInstanceUIDs = parseReferencedSeriesUIDs(from: dataSet)
        
        // Parse Structure Set ROI Sequence
        let rois = parseStructureSetROIs(from: dataSet)
        
        // Parse ROI Contour Sequence
        let roiContours = parseROIContours(from: dataSet)
        
        // Parse RT ROI Observations Sequence
        let roiObservations = parseRTROIObservations(from: dataSet)
        
        return RTStructureSet(
            sopInstanceUID: sopInstanceUID,
            sopClassUID: sopClassUID,
            label: label,
            name: name,
            description: description,
            date: date,
            time: time,
            frameOfReferenceUID: frameOfReferenceUID,
            referencedStudyInstanceUID: referencedStudyInstanceUID,
            referencedSeriesInstanceUIDs: referencedSeriesInstanceUIDs,
            rois: rois,
            roiContours: roiContours,
            roiObservations: roiObservations
        )
    }
    
    // MARK: - Private Parsing Methods
    
    /// Parse Frame of Reference UID from Referenced Frame of Reference Sequence
    private static func parseFrameOfReferenceUID(from dataSet: DataSet) -> String? {
        guard let sequence = dataSet.sequence(for: .referencedFrameOfReferenceSequence),
              let firstItem = sequence.first else {
            return nil
        }
        
        return firstItem.string(for: .frameOfReferenceUID)
    }
    
    /// Parse Referenced Study Instance UID
    private static func parseReferencedStudyUID(from dataSet: DataSet) -> String? {
        guard let frameRefSequence = dataSet.sequence(for: .referencedFrameOfReferenceSequence),
              let frameRefItem = frameRefSequence.first,
              let studySequence = frameRefItem[.rtReferencedStudySequence]?.sequenceItems,
              let studyItem = studySequence.first else {
            return nil
        }
        
        return studyItem.string(for: .referencedSOPInstanceUID)
    }
    
    /// Parse Referenced Series Instance UIDs
    private static func parseReferencedSeriesUIDs(from dataSet: DataSet) -> [String] {
        var seriesUIDs: [String] = []
        
        guard let frameRefSequence = dataSet.sequence(for: .referencedFrameOfReferenceSequence) else {
            return seriesUIDs
        }
        
        for frameRefItem in frameRefSequence {
            guard let studySequence = frameRefItem[.rtReferencedStudySequence]?.sequenceItems else {
                continue
            }
            
            for studyItem in studySequence {
                guard let seriesSequence = studyItem[.rtReferencedSeriesSequence]?.sequenceItems else {
                    continue
                }
                
                for seriesItem in seriesSequence {
                    if let seriesUID = seriesItem.string(for: .seriesInstanceUID) {
                        seriesUIDs.append(seriesUID)
                    }
                }
            }
        }
        
        return seriesUIDs
    }
    
    /// Parse Structure Set ROI Sequence
    private static func parseStructureSetROIs(from dataSet: DataSet) -> [RTRegionOfInterest] {
        guard let sequence = dataSet.sequence(for: .structureSetROISequence) else {
            return []
        }
        
        return sequence.compactMap { item in
            guard let number = item[.roiNumber]?.integerStringValue?.value,
                  let name = item.string(for: .roiName) else {
                return nil
            }
            
            let description = item.string(for: .roiDescription)
            let frameOfReferenceUID = item.string(for: .referencedFrameOfReferenceUID)
            let generationAlgorithm = item.string(for: .roiGenerationAlgorithm)
            let generationDescription = item.string(for: .roiGenerationDescription)
            
            return RTRegionOfInterest(
                number: number,
                name: name,
                description: description,
                frameOfReferenceUID: frameOfReferenceUID,
                generationAlgorithm: generationAlgorithm,
                generationDescription: generationDescription
            )
        }
    }
    
    /// Parse ROI Contour Sequence
    private static func parseROIContours(from dataSet: DataSet) -> [ROIContour] {
        guard let sequence = dataSet.sequence(for: .roiContourSequence) else {
            return []
        }
        
        return sequence.compactMap { item in
            guard let roiNumber = item[.referencedROINumber]?.integerStringValue?.value else {
                return nil
            }
            
            // Parse display color (RGB, 0-255)
            var displayColor: DisplayColor? = nil
            if let colorData = item[.roiDisplayColor]?.valueData,
               colorData.count >= 3 {
                // Color is stored as Integer String (IS) with backslash separator
                if let colorString = String(data: colorData, encoding: .ascii) {
                    let components = colorString.split(separator: "\\").compactMap { Int($0) }
                    if components.count >= 3 {
                        displayColor = DisplayColor(red: components[0], green: components[1], blue: components[2])
                    }
                }
            }
            
            // Parse contour sequence
            let contours = parseContours(from: item)
            
            return ROIContour(
                roiNumber: roiNumber,
                displayColor: displayColor,
                contours: contours
            )
        }
    }
    
    /// Parse Contour Sequence
    private static func parseContours(from item: SequenceItem) -> [Contour] {
        guard let sequence = item[.contourSequence]?.sequenceItems else {
            return []
        }
        
        return sequence.compactMap { contourItem in
            guard let geometricTypeString = contourItem.string(for: .contourGeometricType),
                  let geometricType = ContourGeometricType(rawValue: geometricTypeString),
                  let numberOfPoints = contourItem[.numberOfContourPoints]?.integerStringValue?.value,
                  let contourData = contourItem[.contourData]?.valueData else {
                return nil
            }
            
            // Parse contour data (triplets of x, y, z coordinates)
            let points = parseContourPoints(from: contourData)
            
            // Parse referenced SOP Instance UID
            var referencedSOPInstanceUID: String? = nil
            if let imageSequence = contourItem[.contourImageSequence]?.sequenceItems,
               let imageItem = imageSequence.first {
                referencedSOPInstanceUID = imageItem.string(for: .referencedSOPInstanceUID)
            }
            
            // Parse optional attributes
            let slabThickness = contourItem[.contourSlabThickness]?.decimalStringValue?.value
            
            var offsetVector: Vector3D? = nil
            if let offsetData = contourItem[.contourOffsetVector]?.valueData {
                let offsets = parseDecimalStringArray(from: offsetData)
                if offsets.count >= 3 {
                    offsetVector = Vector3D(x: offsets[0], y: offsets[1], z: offsets[2])
                }
            }
            
            return Contour(
                geometricType: geometricType,
                numberOfPoints: numberOfPoints,
                points: points,
                referencedSOPInstanceUID: referencedSOPInstanceUID,
                slabThickness: slabThickness,
                offsetVector: offsetVector
            )
        }
    }
    
    /// Parse contour data points from raw data
    private static func parseContourPoints(from data: Data) -> [Point3D] {
        // Contour data is stored as Decimal String (DS) with backslash separator
        guard let dataString = String(data: data, encoding: .ascii) else {
            return []
        }
        
        let values = dataString.split(separator: "\\").compactMap { Double($0) }
        
        // Points are stored as triplets (x, y, z)
        var points: [Point3D] = []
        var index = 0
        while index + 2 < values.count {
            let point = Point3D(x: values[index], y: values[index + 1], z: values[index + 2])
            points.append(point)
            index += 3
        }
        
        return points
    }
    
    /// Parse decimal string array from raw data
    private static func parseDecimalStringArray(from data: Data) -> [Double] {
        guard let dataString = String(data: data, encoding: .ascii) else {
            return []
        }
        
        return dataString.split(separator: "\\").compactMap { Double($0) }
    }
    
    /// Parse RT ROI Observations Sequence
    private static func parseRTROIObservations(from dataSet: DataSet) -> [RTROIObservation] {
        guard let sequence = dataSet.sequence(for: .rtROIObservationsSequence) else {
            return []
        }
        
        return sequence.compactMap { item in
            guard let observationNumber = item[.observationNumber]?.integerStringValue?.value,
                  let referencedROINumber = item[.referencedROINumber]?.integerStringValue?.value else {
                return nil
            }
            
            // Parse RT ROI Interpreted Type
            var interpretedType: RTROIInterpretedType? = nil
            if let typeString = item.string(for: .rtROIInterpretedType) {
                interpretedType = RTROIInterpretedType(rawValue: typeString)
            }
            
            let interpreter = item.string(for: .roiInterpreter)
            
            // Parse ROI Physical Properties
            let physicalProperties = parseROIPhysicalProperties(from: item)
            
            return RTROIObservation(
                observationNumber: observationNumber,
                referencedROINumber: referencedROINumber,
                interpretedType: interpretedType,
                interpreter: interpreter,
                physicalProperties: physicalProperties
            )
        }
    }
    
    /// Parse ROI Physical Properties Sequence
    private static func parseROIPhysicalProperties(from item: SequenceItem) -> [ROIPhysicalProperty] {
        guard let sequence = item[.roiPhysicalPropertiesSequence]?.sequenceItems else {
            return []
        }
        
        return sequence.compactMap { propItem in
            guard let property = propItem.string(for: .roiPhysicalProperty),
                  let value = propItem[.roiPhysicalPropertyValue]?.decimalStringValue?.value else {
                return nil
            }
            
            return ROIPhysicalProperty(property: property, value: value)
        }
    }
}
