// NEMA-verified: 2026a, checked 2026-09-30 — Segmentation Image Module reads per PS3.3 2026a Table C.8.20-2 (Segmentation Type incl. LABELMAP, Segments Overlap, Pixel Padding Value per A.51.4); Dimension Index Values (0020,9157) and In-Stack Position Number (0020,9057) read as UL per PS3.6 Table 6-1; SOP Class per PS3.4 B.5.1.25; Palette Color Lookup Table (C.7.9) and ICC Profile (C.11.15) Modules read with PALETTE COLOR per Table A.51-1 (D37b)
//
// SegmentationParser.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Parser for DICOM Segmentation objects
///
/// Parses Segmentation IODs from DICOM data sets, extracting segment definitions,
/// multi-frame pixel data properties, and functional groups.
///
/// Reference: PS3.3 A.51 - Segmentation IOD
/// Reference: PS3.3 C.8.20 - Segmentation Modules
public struct SegmentationParser {
    
    /// Parse Segmentation from a DICOM data set
    ///
    /// - Parameter dataSet: DICOM data set containing Segmentation
    /// - Returns: Parsed Segmentation
    /// - Throws: DICOMError if parsing fails
    public static func parse(from dataSet: DataSet) throws -> Segmentation {
        // Parse SOP Instance UID and SOP Class UID
        guard let sopInstanceUID = dataSet.string(for: .sopInstanceUID) else {
            throw DICOMError.parsingFailed("Missing SOP Instance UID")
        }
        
        let explicitSOPClassUID = dataSet.string(for: .sopClassUID)

        // Parse Series and Study UIDs
        guard let seriesInstanceUID = dataSet.string(for: .seriesInstanceUID) else {
            throw DICOMError.parsingFailed("Missing Series Instance UID")
        }
        
        guard let studyInstanceUID = dataSet.string(for: .studyInstanceUID) else {
            throw DICOMError.parsingFailed("Missing Study Instance UID")
        }
        
        // Parse Content Identification
        let instanceNumber = dataSet[.instanceNumber]?.integerStringValue?.value
        let seriesNumber = dataSet[.seriesNumber]?.integerStringValue?.value
        let contentLabel = dataSet.string(for: .contentLabel)
        let contentDescription = dataSet.string(for: .contentDescription)
        let contentCreatorName = dataSet.personName(for: .contentCreatorName)
        let contentDate = dataSet.date(for: .contentDate)
        let contentTime = dataSet.time(for: .contentTime)
        
        // Parse Segmentation Type and Properties
        guard let segmentationTypeString = dataSet.string(for: .segmentationType),
              let segmentationType = SegmentationType(rawValue: segmentationTypeString) else {
            throw DICOMError.parsingFailed("Missing or invalid Segmentation Type")
        }
        
        // PS3.4 B.5.1.25: Segmentation Storage carries BINARY/FRACTIONAL, Label Map
        // Segmentation Storage carries LABELMAP. Default from the type when the data set
        // has no SOP Class UID.
        let sopClassUID = explicitSOPClassUID ?? Segmentation.sopClassUID(for: segmentationType)

        var segmentationFractionalType: SegmentationFractionalType? = nil
        var maxFractionalValue: Int? = nil

        if segmentationType == .fractional {
            if let fractionalTypeString = dataSet.string(for: .segmentationFractionalType) {
                segmentationFractionalType = SegmentationFractionalType(rawValue: fractionalTypeString)
            }
            if let maxFracValue = dataSet.uint16(for: .maximumFractionalValue) {
                maxFractionalValue = Int(maxFracValue)
            }
        }

        // Segments Overlap (0062,0013), Type 3 (Table C.8.20-2)
        let segmentsOverlap = dataSet.string(for: Tag(group: 0x0062, element: 0x0013))
            .flatMap { SegmentsOverlap(rawValue: $0.trimmingCharacters(in: .whitespaces)) }

        // Pixel Padding Value (0028,0120): the background Segment Number of a LABELMAP
        // (A.51.4); Pixel Representation is 0 for every Segmentation Type, so unsigned.
        var pixelPaddingValue: Int? = nil
        if segmentationType == .labelmap, let padding = dataSet.uint16(for: .pixelPaddingValue) {
            pixelPaddingValue = Int(padding)
        }
        
        // Parse Segment Sequence
        let segments = parseSegments(from: dataSet)
        let numberOfSegments = segments.count
        
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

        // Palette Color Lookup Table (C.7.9) and ICC Profile (C.11.15) Modules, required
        // with PALETTE COLOR (PS3.3 2026a Table A.51-1)
        let isPaletteColor = photometricInterpretation.trimmingCharacters(in: .whitespaces) == "PALETTE COLOR"
        let paletteColorLookupTable = isPaletteColor ? dataSet.paletteColorLUT() : nil
        let iccProfile = isPaletteColor ? dataSet[.iccProfile]?.valueData : nil
        let colorSpace = isPaletteColor ? dataSet.string(for: .colorSpace) : nil
        
        // Parse Functional Groups
        let sharedFunctionalGroups = parseSharedFunctionalGroups(from: dataSet)
        let perFrameFunctionalGroups = parsePerFrameFunctionalGroups(from: dataSet)
        
        return Segmentation(
            sopInstanceUID: sopInstanceUID,
            sopClassUID: sopClassUID,
            seriesInstanceUID: seriesInstanceUID,
            studyInstanceUID: studyInstanceUID,
            instanceNumber: instanceNumber,
            seriesNumber: seriesNumber,
            contentLabel: contentLabel,
            contentDescription: contentDescription,
            contentCreatorName: contentCreatorName,
            contentDate: contentDate,
            contentTime: contentTime,
            segmentationType: segmentationType,
            segmentationFractionalType: segmentationFractionalType,
            maxFractionalValue: maxFractionalValue,
            segmentsOverlap: segmentsOverlap,
            pixelPaddingValue: pixelPaddingValue,
            numberOfSegments: numberOfSegments,
            segments: segments,
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
            perFrameFunctionalGroups: perFrameFunctionalGroups,
            paletteColorLookupTable: paletteColorLookupTable,
            iccProfile: iccProfile,
            colorSpace: colorSpace
        )
    }
    
    // MARK: - Private Parsing Methods
    
    /// Parse Segment Sequence
    private static func parseSegments(from dataSet: DataSet) -> [Segment] {
        guard let sequence = dataSet.sequence(for: .segmentSequence) else {
            return []
        }
        
        return sequence.compactMap { item in
            // Use subscript notation and get unsigned short value from data element
            guard let segmentNumberElement = item[.segmentNumber],
                  segmentNumberElement.valueData.count >= 2,
                  let segmentLabel = item.string(for: .segmentLabel) else {
                return nil
            }
            
            // Parse segment number as UInt16 from data
            let segmentNumber = Int(segmentNumberElement.valueData.withUnsafeBytes { $0.load(as: UInt16.self) })
            
            let segmentDescription = item.string(for: .segmentDescription)
            
            // Parse Segment Algorithm Type
            var segmentAlgorithmType: SegmentAlgorithmType? = nil
            if let algorithmTypeString = item.string(for: .segmentAlgorithmType) {
                segmentAlgorithmType = SegmentAlgorithmType(rawValue: algorithmTypeString)
            }
            
            let segmentAlgorithmName = item.string(for: .segmentAlgorithmName)
            
            // Parse Segmented Property Category Code Sequence
            let category = parseCodedConcept(from: item, sequenceTag: .segmentedPropertyCategoryCodeSequence)
            
            // Parse Segmented Property Type Code Sequence
            let type = parseCodedConcept(from: item, sequenceTag: .segmentedPropertyTypeCodeSequence)
            
            // Parse Anatomic Region Sequence
            let anatomicRegion = parseCodedConcept(from: item, sequenceTag: .anatomicRegionSequence)
            
            // Parse Anatomic Region Modifier Sequence
            let anatomicRegionModifier = parseCodedConcept(from: item, sequenceTag: .anatomicRegionModifierSequence)
            
            // Parse Recommended Display CIELab Value
            var recommendedDisplayCIELabValue: CIELabColor? = nil
            if let colorData = item[.recommendedDisplayCIELabValue]?.valueData,
               colorData.count >= 6 {
                // CIELab values are stored as Unsigned Short (US), 3 values of 2 bytes each
                let l = Int(colorData.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt16.self) })
                let a = Int(colorData.withUnsafeBytes { $0.load(fromByteOffset: 2, as: UInt16.self) })
                let b = Int(colorData.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt16.self) })
                recommendedDisplayCIELabValue = CIELabColor(l: l, a: a, b: b)
            }
            
            let trackingID = item.string(for: .trackingID)
            let trackingUID = item.string(for: .trackingUID)
            
            return Segment(
                segmentNumber: segmentNumber,
                segmentLabel: segmentLabel,
                segmentDescription: segmentDescription,
                segmentAlgorithmType: segmentAlgorithmType,
                segmentAlgorithmName: segmentAlgorithmName,
                category: category,
                type: type,
                anatomicRegion: anatomicRegion,
                anatomicRegionModifier: anatomicRegionModifier,
                recommendedDisplayCIELabValue: recommendedDisplayCIELabValue,
                trackingID: trackingID,
                trackingUID: trackingUID
            )
        }
    }
    
    /// Parse a CodedConcept from a sequence
    private static func parseCodedConcept(from item: SequenceItem, sequenceTag: Tag) -> CodedConcept? {
        guard let sequence = item[sequenceTag]?.sequenceItems,
              let codeItem = sequence.first else {
            return nil
        }
        
        guard let codeValue = codeItem.string(for: .codeValue),
              let codingSchemeDesignator = codeItem.string(for: .codingSchemeDesignator),
              let codeMeaning = codeItem.string(for: .codeMeaning) else {
            return nil
        }
        
        let codingSchemeVersion = codeItem.string(for: .codingSchemeVersion)
        
        return CodedConcept(
            codeValue: codeValue,
            codingSchemeDesignator: codingSchemeDesignator,
            codeMeaning: codeMeaning,
            codingSchemeVersion: codingSchemeVersion
        )
    }
    
    /// Parse Referenced Series from data set
    private static func parseReferencedSeries(from dataSet: DataSet) -> [SegmentationReferencedSeries] {
        var referencedSeries: [SegmentationReferencedSeries] = []
        
        // Look for Referenced Series Sequence in various locations
        // Typically in Derivation Image Sequence or Common Instance Reference Module
        
        // Try Common Instance Reference Module (0008,1115)
        if let seriesSequence = dataSet[Tag(group: 0x0008, element: 0x1115)]?.sequenceItems {
            for seriesItem in seriesSequence {
                guard let seriesInstanceUID = seriesItem.string(for: .seriesInstanceUID) else {
                    continue
                }
                
                var referencedInstances: [SegmentationReferencedInstance] = []
                
                // Parse Referenced Instance Sequence (0008,114A)
                if let instanceSequence = seriesItem[Tag(group: 0x0008, element: 0x114A)]?.sequenceItems {
                    for instanceItem in instanceSequence {
                        guard let sopClassUID = instanceItem.string(for: .referencedSOPClassUID),
                              let sopInstanceUID = instanceItem.string(for: .referencedSOPInstanceUID) else {
                            continue
                        }
                        
                        // Parse Referenced Frame Number (0008,1160)
                        var referencedFrameNumbers: [Int]? = nil
                        if let frameData = instanceItem[Tag(group: 0x0008, element: 0x1160)]?.valueData,
                           let frameString = String(data: frameData, encoding: .ascii) {
                            referencedFrameNumbers = frameString.split(separator: "\\").compactMap { Int($0) }
                        }
                        
                        let instance = SegmentationReferencedInstance(
                            sopClassUID: sopClassUID,
                            sopInstanceUID: sopInstanceUID,
                            referencedFrameNumbers: referencedFrameNumbers
                        )
                        referencedInstances.append(instance)
                    }
                }
                
                let series = SegmentationReferencedSeries(
                    seriesInstanceUID: seriesInstanceUID,
                    referencedInstances: referencedInstances
                )
                referencedSeries.append(series)
            }
        }
        
        return referencedSeries
    }
    
    /// Parse Shared Functional Groups Sequence
    private static func parseSharedFunctionalGroups(from dataSet: DataSet) -> FunctionalGroup? {
        guard let sequence = dataSet.sequence(for: .sharedFunctionalGroupsSequence),
              let item = sequence.first else {
            return nil
        }
        
        return parseFunctionalGroup(from: item)
    }
    
    /// Parse Per-Frame Functional Groups Sequence
    private static func parsePerFrameFunctionalGroups(from dataSet: DataSet) -> [FunctionalGroup] {
        guard let sequence = dataSet.sequence(for: .perFrameFunctionalGroupsSequence) else {
            return []
        }
        
        return sequence.compactMap { item in
            parseFunctionalGroup(from: item)
        }
    }
    
    /// Parse a single Functional Group
    private static func parseFunctionalGroup(from item: SequenceItem) -> FunctionalGroup? {
        var hasContent = false
        
        // Parse Segment Identification Sequence
        var segmentIdentification: SegmentIdentification? = nil
        if let segIdentSeq = item[.segmentIdentificationSequence]?.sequenceItems,
           let segIdentItem = segIdentSeq.first,
           let refSegNumElement = segIdentItem[.referencedSegmentNumber],
           refSegNumElement.valueData.count >= 2 {
            let refSegNumber = Int(refSegNumElement.valueData.withUnsafeBytes { $0.load(as: UInt16.self) })
            segmentIdentification = SegmentIdentification(referencedSegmentNumber: refSegNumber)
            hasContent = true
        }
        
        // Parse Derivation Image Sequence
        var derivationImage: DerivationImage? = nil
        if let derivSeq = item[.derivationImageSequence]?.sequenceItems,
           let derivItem = derivSeq.first {
            
            let derivationDescription = derivItem.string(for: .derivationDescription)
            let derivationCode = parseCodedConcept(from: derivItem, sequenceTag: .derivationCodeSequence)
            
            // Parse Source Image Sequence
            var sourceImages: [SourceImage] = []
            if let sourceSeq = derivItem[.sourceImageSequence]?.sequenceItems {
                for sourceItem in sourceSeq {
                    guard let sopClassUID = sourceItem.string(for: .referencedSOPClassUID),
                          let sopInstanceUID = sourceItem.string(for: .referencedSOPInstanceUID) else {
                        continue
                    }
                    
                    let referencedFrameNumber = sourceItem[Tag(group: 0x0008, element: 0x1160)]?.integerStringValue?.value
                    let purposeOfReference = parseCodedConcept(from: sourceItem, sequenceTag: .purposeOfReferenceCodeSequence)
                    
                    let sourceImage = SourceImage(
                        sopClassUID: sopClassUID,
                        sopInstanceUID: sopInstanceUID,
                        referencedFrameNumber: referencedFrameNumber,
                        purposeOfReference: purposeOfReference
                    )
                    sourceImages.append(sourceImage)
                }
            }
            
            if !sourceImages.isEmpty {
                derivationImage = DerivationImage(
                    sourceImages: sourceImages,
                    derivationDescription: derivationDescription,
                    derivationCode: derivationCode
                )
                hasContent = true
            }
        }
        
        // Parse Frame Content Sequence
        var frameContent: FrameContent? = nil
        if let frameSeq = item[.frameContentSequence]?.sequenceItems,
           let frameItem = frameSeq.first {
            
            let frameAcquisitionNumber = frameItem[.frameAcquisitionNumber]?.uint16Value.map { Int($0) }
                ?? frameItem[.frameAcquisitionNumber]?.integerStringValue?.value
            let frameReferenceDateTime = frameItem.string(for: .frameReferenceDateTime)
            let frameAcquisitionDateTime = frameItem.string(for: .frameAcquisitionDateTime)

            // Dimension Index Values (0020,9157) — VR UL, VM 1-n (PS3.6 Table 6-1);
            // a backslash-separated string is accepted from non-conformant writers.
            var dimensionIndexValues: [Int]? = nil
            if let dimElement = frameItem[.dimensionIndexValues] {
                if let values = dimElement.uint32Values {
                    dimensionIndexValues = values.map { Int($0) }
                } else if let dimString = String(data: dimElement.valueData, encoding: .ascii) {
                    let parsed = dimString.split(separator: "\\").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                    dimensionIndexValues = parsed.isEmpty ? nil : parsed
                }
            }

            // Stack ID (0020,9056) SH and In-Stack Position Number (0020,9057) UL
            let stackID = frameItem.string(for: .stackID)
            let inStackPositionNumber = frameItem[.inStackPositionNumber]?.uint32Value.map { Int($0) }

            frameContent = FrameContent(
                frameAcquisitionNumber: frameAcquisitionNumber,
                frameReferenceDateTime: frameReferenceDateTime,
                frameAcquisitionDateTime: frameAcquisitionDateTime,
                dimensionIndexValues: dimensionIndexValues,
                stackID: stackID,
                inStackPositionNumber: inStackPositionNumber
            )
            hasContent = true
        }
        
        // Parse Plane Position Sequence
        var planePosition: PlanePosition? = nil
        if let planeSeq = item[.planePositionSequence]?.sequenceItems,
           let planeItem = planeSeq.first,
           let posData = planeItem[.imagePositionPatient]?.valueData,
           let posString = String(data: posData, encoding: .ascii) {
            
            // DS values may carry the even-length padding space (PS3.5 6.2)
            let positions = posString.split(separator: "\\").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if positions.count >= 3 {
                planePosition = PlanePosition(imagePositionPatient: positions)
                hasContent = true
            }
        }
        
        // Parse Plane Orientation Sequence
        var planeOrientation: PlaneOrientation? = nil
        if let orientSeq = item[.planeOrientationSequence]?.sequenceItems,
           let orientItem = orientSeq.first,
           let orientData = orientItem[.imageOrientationPatient]?.valueData,
           let orientString = String(data: orientData, encoding: .ascii) {
            
            let orientations = orientString.split(separator: "\\").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if orientations.count >= 6 {
                planeOrientation = PlaneOrientation(imageOrientationPatient: orientations)
                hasContent = true
            }
        }
        
        // Only return a FunctionalGroup if we found at least some content
        guard hasContent else {
            return nil
        }
        
        return FunctionalGroup(
            segmentIdentification: segmentIdentification,
            derivationImage: derivationImage,
            frameContent: frameContent,
            planePosition: planePosition,
            planeOrientation: planeOrientation
        )
    }
}
