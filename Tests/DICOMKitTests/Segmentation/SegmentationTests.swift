//
// SegmentationTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
import DICOMCore
@testable import DICOMKit

final class SegmentationTests: XCTestCase {
    
    // MARK: - Segmentation Initialization Tests
    
    func test_segmentation_initialization_withRequiredParameters_succeeds() {
        let segmentation = Segmentation(
            sopInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4",
            studyInstanceUID: "1.2.3",
            segmentationType: .binary,
            numberOfSegments: 1,
            segments: [],
            numberOfFrames: 1,
            rows: 512,
            columns: 512,
            bitsAllocated: 1,
            bitsStored: 1,
            highBit: 0
        )
        
        XCTAssertEqual(segmentation.sopInstanceUID, "1.2.3.4.5")
        XCTAssertEqual(segmentation.seriesInstanceUID, "1.2.3.4")
        XCTAssertEqual(segmentation.studyInstanceUID, "1.2.3")
        XCTAssertEqual(segmentation.segmentationType, .binary)
        XCTAssertEqual(segmentation.numberOfSegments, 1)
        XCTAssertEqual(segmentation.numberOfFrames, 1)
        XCTAssertEqual(segmentation.rows, 512)
        XCTAssertEqual(segmentation.columns, 512)
        XCTAssertEqual(segmentation.bitsAllocated, 1)
        XCTAssertEqual(segmentation.bitsStored, 1)
        XCTAssertEqual(segmentation.highBit, 0)
        
        // Default values
        XCTAssertEqual(segmentation.sopClassUID, "1.2.840.10008.5.1.4.1.1.66.4")
        XCTAssertEqual(segmentation.samplesPerPixel, 1)
        XCTAssertEqual(segmentation.photometricInterpretation, "MONOCHROME2")
        XCTAssertEqual(segmentation.pixelRepresentation, 0)
    }
    
    func test_segmentation_initialization_withAllParameters_succeeds() {
        let personName = DICOMPersonName.parse("Doe^John")!
        let contentDate = DICOMDate(year: 2024, month: 2, day: 5)
        let contentTime = DICOMTime(hour: 14, minute: 30, second: 0)
        
        let segment = Segment(segmentNumber: 1, segmentLabel: "Test Segment")
        let referencedSeries = SegmentationReferencedSeries(seriesInstanceUID: "1.2.3.4.5")
        let sharedFG = FunctionalGroup()
        let perFrameFG = FunctionalGroup()
        
        let segmentation = Segmentation(
            sopInstanceUID: "1.2.3.4.5.6",
            sopClassUID: "1.2.840.10008.5.1.4.1.1.66.4",
            seriesInstanceUID: "1.2.3.4.5",
            studyInstanceUID: "1.2.3.4",
            instanceNumber: 42,
            contentLabel: "AI Segmentation",
            contentDescription: "Automated tumor detection",
            contentCreatorName: personName,
            contentDate: contentDate,
            contentTime: contentTime,
            segmentationType: .fractional,
            segmentationFractionalType: .probability,
            maxFractionalValue: 255,
            numberOfSegments: 1,
            segments: [segment],
            frameOfReferenceUID: "1.2.3.4.5.6.7",
            dimensionOrganizationUID: "1.2.3.4.5.6.7.8",
            referencedSeries: [referencedSeries],
            numberOfFrames: 1,
            rows: 512,
            columns: 512,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            samplesPerPixel: 1,
            photometricInterpretation: "MONOCHROME2",
            pixelRepresentation: 0,
            sharedFunctionalGroups: sharedFG,
            perFrameFunctionalGroups: [perFrameFG]
        )
        
        XCTAssertEqual(segmentation.instanceNumber, 42)
        XCTAssertEqual(segmentation.contentLabel, "AI Segmentation")
        XCTAssertEqual(segmentation.contentDescription, "Automated tumor detection")
        XCTAssertEqual(segmentation.contentCreatorName, personName)
        XCTAssertEqual(segmentation.contentDate, contentDate)
        XCTAssertEqual(segmentation.contentTime, contentTime)
        XCTAssertEqual(segmentation.segmentationFractionalType, .probability)
        XCTAssertEqual(segmentation.maxFractionalValue, 255)
        XCTAssertEqual(segmentation.frameOfReferenceUID, "1.2.3.4.5.6.7")
        XCTAssertEqual(segmentation.dimensionOrganizationUID, "1.2.3.4.5.6.7.8")
        XCTAssertEqual(segmentation.referencedSeries.count, 1)
        XCTAssertNotNil(segmentation.sharedFunctionalGroups)
        XCTAssertEqual(segmentation.perFrameFunctionalGroups.count, 1)
    }
    
    // MARK: - SegmentationType Tests
    
    /// PS3.3 2026a Table C.8.20-2: Segmentation Type (0062,0001) Enumerated Values
    /// BINARY, FRACTIONAL, LABELMAP
    func test_segmentationType_rawValues() {
        XCTAssertEqual(SegmentationType.binary.rawValue, "BINARY")
        XCTAssertEqual(SegmentationType.fractional.rawValue, "FRACTIONAL")
        XCTAssertEqual(SegmentationType.labelmap.rawValue, "LABELMAP")
        XCTAssertEqual(SegmentationType.allCases.count, 3)
    }

    func test_segmentationType_fromString() {
        XCTAssertEqual(SegmentationType(rawValue: "BINARY"), .binary)
        XCTAssertEqual(SegmentationType(rawValue: "FRACTIONAL"), .fractional)
        XCTAssertEqual(SegmentationType(rawValue: "LABELMAP"), .labelmap)
        XCTAssertNil(SegmentationType(rawValue: "INVALID"))
        XCTAssertNil(SegmentationType(rawValue: "LABEL_MAP"))
    }

    /// Table C.8.20-2 Enumerated Values per Segmentation Type
    func test_segmentationType_pixelConstraints() {
        XCTAssertEqual(SegmentationType.binary.allowedBitsAllocated, [1])
        XCTAssertEqual(SegmentationType.fractional.allowedBitsAllocated, [8])
        XCTAssertEqual(SegmentationType.labelmap.allowedBitsAllocated, [8, 16])
        XCTAssertEqual(SegmentationType.binary.allowedPhotometricInterpretations, ["MONOCHROME2"])
        XCTAssertEqual(SegmentationType.labelmap.allowedPhotometricInterpretations, ["MONOCHROME2", "PALETTE COLOR"])
    }

    /// Table C.8.20-2: Segments Overlap (0062,0013) Enumerated Values YES, UNDEFINED, NO
    func test_segmentsOverlap_rawValues() {
        XCTAssertEqual(SegmentsOverlap.yes.rawValue, "YES")
        XCTAssertEqual(SegmentsOverlap.undefined.rawValue, "UNDEFINED")
        XCTAssertEqual(SegmentsOverlap.no.rawValue, "NO")
        XCTAssertEqual(SegmentsOverlap.allCases.count, 3)
    }

    /// PS3.6 Table A-1 and PS3.4 B.5.1.25: SOP Class per Segmentation Type
    func test_sopClassUID_perSegmentationType() {
        XCTAssertEqual(Segmentation.segmentationStorageUID, "1.2.840.10008.5.1.4.1.1.66.4")
        XCTAssertEqual(Segmentation.labelMapSegmentationStorageUID, "1.2.840.10008.5.1.4.1.1.66.7")
        XCTAssertEqual(Segmentation.sopClassUID(for: .binary), Segmentation.segmentationStorageUID)
        XCTAssertEqual(Segmentation.sopClassUID(for: .fractional), Segmentation.segmentationStorageUID)
        XCTAssertEqual(Segmentation.sopClassUID(for: .labelmap), Segmentation.labelMapSegmentationStorageUID)
    }
    
    // MARK: - SegmentationFractionalType Tests
    
    func test_segmentationFractionalType_rawValues() {
        XCTAssertEqual(SegmentationFractionalType.probability.rawValue, "PROBABILITY")
        XCTAssertEqual(SegmentationFractionalType.occupancy.rawValue, "OCCUPANCY")
    }
    
    func test_segmentationFractionalType_fromString() {
        XCTAssertEqual(SegmentationFractionalType(rawValue: "PROBABILITY"), .probability)
        XCTAssertEqual(SegmentationFractionalType(rawValue: "OCCUPANCY"), .occupancy)
        XCTAssertNil(SegmentationFractionalType(rawValue: "INVALID"))
    }
    
    // MARK: - Segment Tests
    
    func test_segment_initialization_withRequiredParameters_succeeds() {
        let segment = Segment(segmentNumber: 1, segmentLabel: "Liver")
        
        XCTAssertEqual(segment.segmentNumber, 1)
        XCTAssertEqual(segment.segmentLabel, "Liver")
        XCTAssertNil(segment.segmentDescription)
        XCTAssertNil(segment.segmentAlgorithmType)
        XCTAssertNil(segment.segmentAlgorithmName)
        XCTAssertNil(segment.category)
        XCTAssertNil(segment.type)
        XCTAssertNil(segment.anatomicRegion)
        XCTAssertNil(segment.anatomicRegionModifier)
        XCTAssertNil(segment.recommendedDisplayCIELabValue)
        XCTAssertNil(segment.trackingID)
        XCTAssertNil(segment.trackingUID)
    }
    
    func test_segment_initialization_withAllParameters_succeeds() {
        let category = CodedConcept(codeValue: "123037004", codingSchemeDesignator: "SCT", codeMeaning: "Anatomical Structure")
        let type = CodedConcept(codeValue: "10200004", codingSchemeDesignator: "SCT", codeMeaning: "Liver")
        let anatomicRegion = CodedConcept(codeValue: "818981001", codingSchemeDesignator: "SCT", codeMeaning: "Abdomen")
        let anatomicModifier = CodedConcept(codeValue: "7771000", codingSchemeDesignator: "SCT", codeMeaning: "Left")
        let color = CIELabColor(l: 32768, a: 40000, b: 25000)
        
        let segment = Segment(
            segmentNumber: 2,
            segmentLabel: "Left Liver Lobe",
            segmentDescription: "AI-detected left hepatic lobe",
            segmentAlgorithmType: .automatic,
            segmentAlgorithmName: "LiverNet v2.0",
            category: category,
            type: type,
            anatomicRegion: anatomicRegion,
            anatomicRegionModifier: anatomicModifier,
            recommendedDisplayCIELabValue: color,
            trackingID: "LIVER_001",
            trackingUID: "1.2.3.4.5.6.7.8.9"
        )
        
        XCTAssertEqual(segment.segmentNumber, 2)
        XCTAssertEqual(segment.segmentLabel, "Left Liver Lobe")
        XCTAssertEqual(segment.segmentDescription, "AI-detected left hepatic lobe")
        XCTAssertEqual(segment.segmentAlgorithmType, .automatic)
        XCTAssertEqual(segment.segmentAlgorithmName, "LiverNet v2.0")
        XCTAssertEqual(segment.category, category)
        XCTAssertEqual(segment.type, type)
        XCTAssertEqual(segment.anatomicRegion, anatomicRegion)
        XCTAssertEqual(segment.anatomicRegionModifier, anatomicModifier)
        XCTAssertEqual(segment.recommendedDisplayCIELabValue, color)
        XCTAssertEqual(segment.trackingID, "LIVER_001")
        XCTAssertEqual(segment.trackingUID, "1.2.3.4.5.6.7.8.9")
    }
    
    func test_segment_identifiable_conformance() {
        let segment = Segment(segmentNumber: 5, segmentLabel: "Test")
        XCTAssertEqual(segment.id, 5)
    }
    
    func test_segment_hashable_conformance() {
        let segment1 = Segment(segmentNumber: 1, segmentLabel: "Segment A")
        let segment2 = Segment(segmentNumber: 1, segmentLabel: "Segment A")
        let segment3 = Segment(segmentNumber: 2, segmentLabel: "Segment B")
        
        XCTAssertEqual(segment1, segment2)
        XCTAssertNotEqual(segment1, segment3)
        
        var set = Set<Segment>()
        set.insert(segment1)
        set.insert(segment2)
        set.insert(segment3)
        
        XCTAssertEqual(set.count, 2)
    }
    
    // MARK: - SegmentAlgorithmType Tests
    
    func test_segmentAlgorithmType_rawValues() {
        XCTAssertEqual(SegmentAlgorithmType.automatic.rawValue, "AUTOMATIC")
        XCTAssertEqual(SegmentAlgorithmType.semiautomatic.rawValue, "SEMIAUTOMATIC")
        XCTAssertEqual(SegmentAlgorithmType.manual.rawValue, "MANUAL")
    }
    
    func test_segmentAlgorithmType_fromString() {
        XCTAssertEqual(SegmentAlgorithmType(rawValue: "AUTOMATIC"), .automatic)
        XCTAssertEqual(SegmentAlgorithmType(rawValue: "SEMIAUTOMATIC"), .semiautomatic)
        XCTAssertEqual(SegmentAlgorithmType(rawValue: "MANUAL"), .manual)
        XCTAssertNil(SegmentAlgorithmType(rawValue: "INVALID"))
    }
    
    // MARK: - CodedConcept Tests
    
    func test_codedConcept_initialization_succeeds() {
        let concept = CodedConcept(
            codeValue: "108369006",
            codingSchemeDesignator: "SCT",
            codeMeaning: "Tumor"
        )
        
        XCTAssertEqual(concept.codeValue, "108369006")
        XCTAssertEqual(concept.codingSchemeDesignator, "SCT")
        XCTAssertEqual(concept.codeMeaning, "Tumor")
        XCTAssertNil(concept.codingSchemeVersion)
    }
    
    func test_codedConcept_equality() {
        let concept1 = CodedConcept(codeValue: "123", codingSchemeDesignator: "SCT", codeMeaning: "Test")
        let concept2 = CodedConcept(codeValue: "123", codingSchemeDesignator: "SCT", codeMeaning: "Test")
        let concept3 = CodedConcept(codeValue: "456", codingSchemeDesignator: "SCT", codeMeaning: "Different")
        
        XCTAssertEqual(concept1, concept2)
        XCTAssertNotEqual(concept1, concept3)
    }
    
    // MARK: - CIELabColor Tests
    
    func test_cielabColor_initialization_succeeds() {
        let color = CIELabColor(l: 32768, a: 40000, b: 25000)
        
        XCTAssertEqual(color.l, 32768)
        XCTAssertEqual(color.a, 40000)
        XCTAssertEqual(color.b, 25000)
    }
    
    func test_cielabColor_hashable_conformance() {
        let color1 = CIELabColor(l: 100, a: 200, b: 300)
        let color2 = CIELabColor(l: 100, a: 200, b: 300)
        let color3 = CIELabColor(l: 100, a: 200, b: 301)
        
        XCTAssertEqual(color1, color2)
        XCTAssertNotEqual(color1, color3)
        
        var set = Set<CIELabColor>()
        set.insert(color1)
        set.insert(color2)
        set.insert(color3)
        
        XCTAssertEqual(set.count, 2)
    }
    
    // MARK: - SegmentationReferencedSeries Tests
    
    func test_referencedSeries_initialization_succeeds() {
        let instance = SegmentationReferencedInstance(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5"
        )
        
        let series = SegmentationReferencedSeries(
            seriesInstanceUID: "1.2.3.4",
            referencedInstances: [instance]
        )
        
        XCTAssertEqual(series.seriesInstanceUID, "1.2.3.4")
        XCTAssertEqual(series.referencedInstances.count, 1)
        XCTAssertEqual(series.referencedInstances[0].sopInstanceUID, "1.2.3.4.5")
    }
    
    // MARK: - SegmentationReferencedInstance Tests
    
    func test_referencedInstance_initialization_succeeds() {
        let instance = SegmentationReferencedInstance(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5",
            referencedFrameNumbers: [1, 2, 3]
        )
        
        XCTAssertEqual(instance.sopClassUID, "1.2.840.10008.5.1.4.1.1.2")
        XCTAssertEqual(instance.sopInstanceUID, "1.2.3.4.5")
        XCTAssertEqual(instance.referencedFrameNumbers, [1, 2, 3])
    }
    
    func test_referencedInstance_hashable_conformance() {
        let instance1 = SegmentationReferencedInstance(
            sopClassUID: "1.2.3",
            sopInstanceUID: "1.2.3.4"
        )
        let instance2 = SegmentationReferencedInstance(
            sopClassUID: "1.2.3",
            sopInstanceUID: "1.2.3.4"
        )
        let instance3 = SegmentationReferencedInstance(
            sopClassUID: "1.2.3",
            sopInstanceUID: "1.2.3.5"
        )
        
        XCTAssertEqual(instance1, instance2)
        XCTAssertNotEqual(instance1, instance3)
    }
    
    // MARK: - FunctionalGroup Tests
    
    func test_functionalGroup_initialization_empty() {
        let fg = FunctionalGroup()
        
        XCTAssertNil(fg.segmentIdentification)
        XCTAssertNil(fg.derivationImage)
        XCTAssertNil(fg.frameContent)
        XCTAssertNil(fg.planePosition)
        XCTAssertNil(fg.planeOrientation)
    }
    
    func test_functionalGroup_initialization_withAllComponents() {
        let segID = SegmentIdentification(referencedSegmentNumber: 1)
        let sourceImage = SourceImage(sopClassUID: "1.2.3", sopInstanceUID: "1.2.3.4")
        let derivation = DerivationImage(sourceImages: [sourceImage])
        let frameContent = FrameContent(frameAcquisitionNumber: 5)
        let planePos = PlanePosition(imagePositionPatient: [0.0, 0.0, 10.0])
        let planeOrient = PlaneOrientation(imageOrientationPatient: [1.0, 0.0, 0.0, 0.0, 1.0, 0.0])
        
        let fg = FunctionalGroup(
            segmentIdentification: segID,
            derivationImage: derivation,
            frameContent: frameContent,
            planePosition: planePos,
            planeOrientation: planeOrient
        )
        
        XCTAssertNotNil(fg.segmentIdentification)
        XCTAssertNotNil(fg.derivationImage)
        XCTAssertNotNil(fg.frameContent)
        XCTAssertNotNil(fg.planePosition)
        XCTAssertNotNil(fg.planeOrientation)
    }
    
    // MARK: - SegmentIdentification Tests
    
    func test_segmentIdentification_initialization() {
        let segID = SegmentIdentification(referencedSegmentNumber: 3)
        XCTAssertEqual(segID.referencedSegmentNumber, 3)
    }
    
    // MARK: - DerivationImage Tests
    
    func test_derivationImage_initialization_succeeds() {
        let sourceImage = SourceImage(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5"
        )
        let derivationCode = CodedConcept(codeValue: "113076", codingSchemeDesignator: "DCM", codeMeaning: "Segmentation")
        
        let derivation = DerivationImage(
            sourceImages: [sourceImage],
            derivationDescription: "Automated segmentation from CT",
            derivationCode: derivationCode
        )
        
        XCTAssertEqual(derivation.sourceImages.count, 1)
        XCTAssertEqual(derivation.derivationDescription, "Automated segmentation from CT")
        XCTAssertEqual(derivation.derivationCode, derivationCode)
    }
    
    // MARK: - SourceImage Tests
    
    func test_sourceImage_initialization_succeeds() {
        let purposeCode = CodedConcept(codeValue: "121322", codingSchemeDesignator: "DCM", codeMeaning: "Source image for image processing operation")
        
        let sourceImage = SourceImage(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5",
            referencedFrameNumber: 10,
            purposeOfReference: purposeCode
        )
        
        XCTAssertEqual(sourceImage.sopClassUID, "1.2.840.10008.5.1.4.1.1.2")
        XCTAssertEqual(sourceImage.sopInstanceUID, "1.2.3.4.5")
        XCTAssertEqual(sourceImage.referencedFrameNumber, 10)
        XCTAssertEqual(sourceImage.purposeOfReference, purposeCode)
    }
    
    // MARK: - FrameContent Tests
    
    func test_frameContent_initialization_succeeds() {
        let frameContent = FrameContent(
            frameAcquisitionNumber: 42,
            frameReferenceDateTime: "20240205143000",
            frameAcquisitionDateTime: "20240205143005",
            dimensionIndexValues: [1, 2, 3]
        )
        
        XCTAssertEqual(frameContent.frameAcquisitionNumber, 42)
        XCTAssertEqual(frameContent.frameReferenceDateTime, "20240205143000")
        XCTAssertEqual(frameContent.frameAcquisitionDateTime, "20240205143005")
        XCTAssertEqual(frameContent.dimensionIndexValues, [1, 2, 3])
    }
    
    // MARK: - PlanePosition Tests
    
    func test_planePosition_initialization_succeeds() {
        let planePos = PlanePosition(imagePositionPatient: [100.5, 200.3, 50.7])
        XCTAssertEqual(planePos.imagePositionPatient, [100.5, 200.3, 50.7])
    }
    
    // MARK: - PlaneOrientation Tests
    
    func test_planeOrientation_initialization_succeeds() {
        let planeOrient = PlaneOrientation(imageOrientationPatient: [1.0, 0.0, 0.0, 0.0, 1.0, 0.0])
        XCTAssertEqual(planeOrient.imageOrientationPatient, [1.0, 0.0, 0.0, 0.0, 1.0, 0.0])
    }
}
