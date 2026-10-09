// NEMA-verified: 2026a, checked 2026-09-29 — RT General Plan (Table C.8-45), RT Prescription (C.8-46), RT Fraction Scheme (C.8-49; Fraction Pattern (300A,007B) is LT per PS3.6), RT Beams (C.8-50) and Brachy Application Setup (C.8-51) reads per PS3.3 2026a
//
// RTPlanParser.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Parser for DICOM RT Plan objects
///
/// Parses RT Plan IODs from DICOM data sets, extracting plan metadata,
/// fraction groups, beam definitions, and dose references.
///
/// Reference: PS3.3 A.20 - RT Plan IOD
public struct RTPlanParser {
    
    /// Parse RT Plan from a DICOM data set
    ///
    /// - Parameter dataSet: DICOM data set containing RT Plan
    /// - Returns: Parsed RT Plan
    /// - Throws: DICOMError if parsing fails
    public static func parse(from dataSet: DataSet) throws -> RTPlan {
        // Parse SOP Instance UID and SOP Class UID
        guard let sopInstanceUID = dataSet.string(for: .sopInstanceUID) else {
            throw DICOMError.parsingFailed("Missing SOP Instance UID")
        }
        
        let sopClassUID = dataSet.string(for: .sopClassUID) ?? "1.2.840.10008.5.1.4.1.1.481.5"
        
        // Parse RT Plan identification
        let label = dataSet.string(for: .rtPlanLabel)
        let name = dataSet.string(for: .rtPlanName)
        let description = dataSet.string(for: .rtPlanDescription)
        let date = dataSet.date(for: .rtPlanDate)
        let time = dataSet.time(for: .rtPlanTime)
        let geometry = dataSet.string(for: .rtPlanGeometry)
        
        // Parse referenced objects
        let referencedStructureSetUID = parseReferencedStructureSetUID(from: dataSet)
        let referencedDoseUID = parseReferencedDoseUID(from: dataSet)
        
        // Parse prescription
        let prescriptionDescription = dataSet.string(for: .prescriptionDescription)
        let doseReferences = parseDoseReferences(from: dataSet)
        
        // Parse fraction groups
        let fractionGroups = parseFractionGroups(from: dataSet)
        
        // Parse beams
        let beams = parseBeams(from: dataSet)
        
        // Parse brachy application setups
        let brachyApplicationSetups = parseBrachyApplicationSetups(from: dataSet)
        
        return RTPlan(
            sopInstanceUID: sopInstanceUID,
            sopClassUID: sopClassUID,
            label: label,
            name: name,
            description: description,
            date: date,
            time: time,
            geometry: geometry,
            referencedStructureSetUID: referencedStructureSetUID,
            referencedDoseUID: referencedDoseUID,
            prescriptionDescription: prescriptionDescription,
            doseReferences: doseReferences,
            fractionGroups: fractionGroups,
            beams: beams,
            brachyApplicationSetups: brachyApplicationSetups
        )
    }
    
    // MARK: - Private Parsing Methods
    
    /// Parse Referenced Structure Set SOP Instance UID
    private static func parseReferencedStructureSetUID(from dataSet: DataSet) -> String? {
        guard let sequence = dataSet.sequence(for: .referencedStructureSetSequence),
              let firstItem = sequence.first,
              let uid = firstItem.string(for: .referencedSOPInstanceUID) else {
            return nil
        }
        return uid
    }
    
    /// Parse Referenced Dose SOP Instance UID
    private static func parseReferencedDoseUID(from dataSet: DataSet) -> String? {
        guard let sequence = dataSet.sequence(for: .referencedDoseSequence),
              let firstItem = sequence.first,
              let uid = firstItem.string(for: .referencedSOPInstanceUID) else {
            return nil
        }
        return uid
    }
    
    /// Parse Dose Reference Sequence
    private static func parseDoseReferences(from dataSet: DataSet) -> [DoseReference] {
        guard let sequence = dataSet.sequence(for: .doseReferenceSequence) else {
            return []
        }
        
        return sequence.compactMap { item in
            guard let number = item[.doseReferenceNumber]?.integerStringValue?.value else {
                return nil
            }
            
            let uid = item.string(for: .doseReferenceUID)
            let structureType = item.string(for: .doseReferenceStructureType)
            let description = item.string(for: .doseReferenceDescription)
            let type = item.string(for: .doseReferenceType)
            
            let targetPrescriptionDose = item[.targetPrescriptionDose]?.decimalStringValue?.value
            let targetMaximumDose = item[.targetMaximumDose]?.decimalStringValue?.value
            let targetMinimumDose = item[.targetMinimumDose]?.decimalStringValue?.value
            let organAtRiskFullVolumeDose = item[.organAtRiskFullVolumeDose]?.decimalStringValue?.value
            let organAtRiskMaximumDose = item[.organAtRiskMaximumDose]?.decimalStringValue?.value
            
            let referencedROINumber = item[.referencedROINumber]?.integerStringValue?.value
            
            return DoseReference(
                number: number,
                uid: uid,
                structureType: structureType,
                description: description,
                type: type,
                targetPrescriptionDose: targetPrescriptionDose,
                targetMaximumDose: targetMaximumDose,
                targetMinimumDose: targetMinimumDose,
                organAtRiskFullVolumeDose: organAtRiskFullVolumeDose,
                organAtRiskMaximumDose: organAtRiskMaximumDose,
                referencedROINumber: referencedROINumber
            )
        }
    }
    
    /// Parse Fraction Group Sequence
    private static func parseFractionGroups(from dataSet: DataSet) -> [FractionGroup] {
        guard let sequence = dataSet.sequence(for: .fractionGroupSequence) else {
            return []
        }
        
        var fractionGroups: [FractionGroup] = []
        for item in sequence {
            guard let number = item[.fractionGroupNumber]?.integerStringValue?.value else {
                continue
            }
            
            let description = item.string(for: .fractionGroupDescription)
            let numberOfFractionsPlanned = item[.numberOfFractionsPlanned]?.integerStringValue?.value
            let numberOfFractionsPerDay = item[.numberOfFractionPatternDigitsPerDay]?.integerStringValue?.value
            let repeatFractionCycleLength = item[.repeatFractionCycleLength]?.integerStringValue?.value
            let fractionPattern = item.string(for: .fractionPattern)
            let numberOfBeams = item[.numberOfBeams]?.integerStringValue?.value
            
            // Parse referenced beam numbers
            var referencedBeamNumbers: [Int] = []
            if let beamSeq = item[Tag(group: 0x300C, element: 0x0004)]?.sequenceItems {
                referencedBeamNumbers = beamSeq.compactMap { beamItem in
                    beamItem[.referencedBeamNumber]?.integerStringValue?.value
                }
            }
            
            let numberOfBrachySetups = item[.numberOfBrachyApplicationSetups]?.integerStringValue?.value
            let referencedBrachyNumbers: [Int] = []
            
            fractionGroups.append(FractionGroup(
                number: number,
                description: description,
                numberOfFractionsPlanned: numberOfFractionsPlanned,
                numberOfFractionsPerDay: numberOfFractionsPerDay,
                repeatFractionCycleLength: repeatFractionCycleLength,
                fractionPattern: fractionPattern,
                numberOfBeams: numberOfBeams,
                referencedBeamNumbers: referencedBeamNumbers,
                numberOfBrachyApplicationSetups: numberOfBrachySetups,
                referencedBrachyApplicationSetupNumbers: referencedBrachyNumbers
            ))
        }
        
        return fractionGroups
    }
    
    /// Parse Beam Sequence
    private static func parseBeams(from dataSet: DataSet) -> [RTBeam] {
        guard let sequence = dataSet.sequence(for: .beamSequence) else {
            return []
        }
        
        var beams: [RTBeam] = []
        for item in sequence {
            guard let number = item[.beamNumber]?.integerStringValue?.value else {
                continue
            }
            
            let name = item.string(for: .beamName)
            let description = item.string(for: .beamDescription)
            let type = item.string(for: .beamType)
            let radiationType = item.string(for: .radiationType)
            let treatmentMachineName = item.string(for: .treatmentMachineName)
            let manufacturer = item.string(for: .manufacturer)
            let institutionName = item.string(for: .institutionName)
            let primaryDosimeterUnit = item.string(for: .primaryDosimeterUnit)
            let sourceAxisDistance = item[.sourceAxisDistance]?.decimalStringValue?.value
            let finalCumulativeMetersetWeight = item[.finalCumulativeMetersetWeight]?.decimalStringValue?.value
            // Treatment Delivery Type (300A,00CE) CS Type 3 and High-Dose Technique Type (300A,00C7) CS Type 1C
            // (PS3.3 Table C.8-50)
            let treatmentDeliveryType = item.string(for: .treatmentDeliveryType)
            let highDoseTechniqueType = item.string(for: .highDoseTechniqueType)

            // Parse control points
            let controlPoints = parseControlPoints(from: item)

            beams.append(RTBeam(
                number: number,
                name: name,
                description: description,
                type: type,
                radiationType: radiationType,
                treatmentMachineName: treatmentMachineName,
                manufacturer: manufacturer,
                institutionName: institutionName,
                primaryDosimeterUnit: primaryDosimeterUnit,
                sourceAxisDistance: sourceAxisDistance,
                controlPoints: controlPoints,
                finalCumulativeMetersetWeight: finalCumulativeMetersetWeight,
                treatmentDeliveryType: treatmentDeliveryType,
                highDoseTechniqueType: highDoseTechniqueType
            ))
        }
        
        return beams
    }
    
    /// Parse Control Point Sequence
    private static func parseControlPoints(from beamItem: SequenceItem) -> [BeamControlPoint] {
        guard let sequence = beamItem[.controlPointSequence]?.sequenceItems else {
            return []
        }
        
        var controlPoints: [BeamControlPoint] = []
        for item in sequence {
            guard let index = item[.controlPointIndex]?.integerStringValue?.value else {
                continue
            }
            
            let cumulativeMetersetWeight = item[.cumulativeMetersetWeight]?.decimalStringValue?.value
            let gantryAngle = item[.gantryAngle]?.decimalStringValue?.value
            let gantryRotationDirection = item.string(for: .gantryRotationDirection)
            let beamLimitingDeviceAngle = item[.beamLimitingDeviceAngle]?.decimalStringValue?.value
            let beamLimitingDeviceRotationDirection = item.string(for: .beamLimitingDeviceRotationDirection)
            let patientSupportAngle = item[.patientSupportAngle]?.decimalStringValue?.value
            let patientSupportRotationDirection = item.string(for: .patientSupportRotationDirection)
            
            let tableTopVerticalPosition = item[.tableTopVerticalPosition]?.decimalStringValue?.value
            let tableTopLongitudinalPosition = item[.tableTopLongitudinalPosition]?.decimalStringValue?.value
            let tableTopLateralPosition = item[.tableTopLateralPosition]?.decimalStringValue?.value
            
            // Parse isocenter position
            let isocenterPosition = parsePoint3DFromItem(item, tag: .isocenterPosition)
            let surfaceEntryPoint = parsePoint3DFromItem(item, tag: .surfaceEntryPoint)
            
            let sourceToSurfaceDistance = item[.sourceToSurfaceDistance]?.decimalStringValue?.value
            let nominalBeamEnergy = item[.nominalBeamEnergy]?.decimalStringValue?.value
            let doseRateSet = item[.doseRateSet]?.decimalStringValue?.value
            
            // Parse beam limiting device positions
            let beamLimitingDevicePositions = parseBeamLimitingDevicePositions(from: item)
            
            controlPoints.append(BeamControlPoint(
                index: index,
                cumulativeMetersetWeight: cumulativeMetersetWeight,
                gantryAngle: gantryAngle,
                gantryRotationDirection: gantryRotationDirection,
                beamLimitingDeviceAngle: beamLimitingDeviceAngle,
                beamLimitingDeviceRotationDirection: beamLimitingDeviceRotationDirection,
                patientSupportAngle: patientSupportAngle,
                patientSupportRotationDirection: patientSupportRotationDirection,
                tableTopVerticalPosition: tableTopVerticalPosition,
                tableTopLongitudinalPosition: tableTopLongitudinalPosition,
                tableTopLateralPosition: tableTopLateralPosition,
                isocenterPosition: isocenterPosition,
                surfaceEntryPoint: surfaceEntryPoint,
                sourceToSurfaceDistance: sourceToSurfaceDistance,
                beamLimitingDevicePositions: beamLimitingDevicePositions,
                nominalBeamEnergy: nominalBeamEnergy,
                doseRateSet: doseRateSet
            ))
        }
        
        return controlPoints
    }
    
    /// Parse Beam Limiting Device Position Sequence
    private static func parseBeamLimitingDevicePositions(from controlPointItem: SequenceItem) -> [BeamLimitingDevicePosition] {
        guard let sequence = controlPointItem[.beamLimitingDevicePositionSequence]?.sequenceItems else {
            return []
        }
        
        var devicePositions: [BeamLimitingDevicePosition] = []
        for item in sequence {
            guard let type = item.string(for: .rtBeamLimitingDeviceType) else {
                continue
            }
            
            // Parse leaf/jaw positions
            var positions: [Double] = []
            if let posData = item[.leafJawPositions]?.valueData {
                positions = parseDecimalStringArray(from: posData)
            }
            
            devicePositions.append(BeamLimitingDevicePosition(
                type: type,
                positions: positions
            ))
        }
        
        return devicePositions
    }
    
    /// Parse Brachy Application Setup Sequence
    private static func parseBrachyApplicationSetups(from dataSet: DataSet) -> [BrachyApplicationSetup] {
        guard let sequence = dataSet.sequence(for: .brachyApplicationSetupSequence) else {
            return []
        }
        
        return sequence.compactMap { item in
            guard let number = item[.applicationSetupNumber]?.integerStringValue?.value else {
                return nil
            }
            
            let type = item.string(for: .applicationSetupType)
            
            return BrachyApplicationSetup(
                number: number,
                type: type
            )
        }
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
    
    /// Parse decimal string array from raw data
    private static func parseDecimalStringArray(from data: Data) -> [Double] {
        guard let dataString = String(data: data, encoding: .ascii) else {
            return []
        }
        
        return dataString.split(separator: "\\").compactMap { Double($0) }
    }
}
