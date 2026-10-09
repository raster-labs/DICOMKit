/// Tests for AIInferenceResult
///
/// Validates AI/ML inference result types and utilities.

import XCTest
@testable import DICOMKit
@testable import DICOMCore

final class AIInferenceResultTests: XCTestCase {
    
    // MARK: - AIDetection Tests
    
    func testAIDetectionInitialization() {
        let imageRef = AIImageReference(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5"
        )
        
        let location = AIDetectionLocation.point2D(x: 100.0, y: 200.0, imageReference: imageRef)
        
        let detection = AIDetection(
            type: .lungNodule,
            confidence: 0.95,
            location: location,
            attributes: ["size": "small"]
        )
        
        XCTAssertEqual(detection.type, .lungNodule)
        XCTAssertEqual(detection.confidence, 0.95)
        if case .point2D(let x, let y, _) = detection.location {
            XCTAssertEqual(x, 100.0)
            XCTAssertEqual(y, 200.0)
        } else {
            XCTFail("Expected point2D location")
        }
        XCTAssertEqual(detection.attributes?["size"], "small")
    }
    
    func testAIDetectionWithoutAttributes() {
        let imageRef = AIImageReference(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5"
        )
        
        let location = AIDetectionLocation.point2D(x: 100.0, y: 200.0, imageReference: imageRef)
        
        let detection = AIDetection(
            type: .mass,
            confidence: 0.85,
            location: location
        )
        
        XCTAssertNil(detection.attributes)
    }
    
    // MARK: - AIDetectionType Tests
    
    func testLungNoduleType() {
        let type = AIDetectionType.lungNodule
        let concept = type.concept
        
        // PS3.16 CID 6104
        XCTAssertEqual(concept.codeValue, "27925004")
        XCTAssertEqual(concept.codingSchemeDesignator, "SCT")
        XCTAssertEqual(concept.codeMeaning, "Nodule")
    }

    func testMassType() {
        let type = AIDetectionType.mass
        let concept = type.concept

        // PS3.16 2026a CID 6104 "Abnormal Opacity Finding or Feature": SCT | 4147007 | Mass
        XCTAssertEqual(concept.codeValue, "4147007")
        XCTAssertEqual(concept.codingSchemeDesignator, "SCT")
        XCTAssertEqual(concept.codeMeaning, "Mass")
    }
    
    func testCalcificationTypeIsPrivateCode() {
        // PS3.16 2026a has no general "Calcification" concept in Table D-1 or any CID
        // (only (309587003, SCT, "Calcification of breast") in CID 6054 and
        // (129769006, SCT, "Calcification Cluster") in CID 6015), so the case is deprecated
        // and emits the private scheme 99DICOMKIT (PS3.16 2026a Section 8: private schemes start with "99").
        @available(*, deprecated) func legacy() -> CodedConcept { AIDetectionType.calcification.concept }
        let concept = legacy()
        XCTAssertEqual(concept.codeValue, "CALCIFICATION")
        XCTAssertEqual(concept.codingSchemeDesignator, "99DICOMKIT")
        XCTAssertEqual(concept.codeMeaning, "Calcification")
        XCTAssertNotEqual(concept.codingSchemeDesignator, "SRT")
    }
    
    func testLesionType() {
        let type = AIDetectionType.lesion
        let concept = type.concept
        
        // PS3.16 2026a CID 7159 "Lesion Segmentation Type": SCT | 52988006 | Lesion
        XCTAssertEqual(concept.codeValue, "52988006")
        XCTAssertEqual(concept.codingSchemeDesignator, "SCT")
        XCTAssertEqual(concept.codeMeaning, "Lesion")
    }
    
    func testFractureTypeIsPrivateCode() {
        // PS3.16 2026a CID rows: only (46866001, SCT, "Fracture of lower limb") in CID 3205; no "Fracture".
        @available(*, deprecated) func legacy() -> CodedConcept { AIDetectionType.fracture.concept }
        let concept = legacy()
        XCTAssertEqual(concept.codeValue, "FRACTURE")
        XCTAssertEqual(concept.codingSchemeDesignator, "99DICOMKIT")
        XCTAssertEqual(concept.codeMeaning, "Fracture")
    }
    
    func testHemorrhageType() {
        let type = AIDetectionType.hemorrhage
        let concept = type.concept
        
        // PS3.16 2026a CID 7159 "Lesion Segmentation Type": SCT | 50960005 | Hemorrhage
        XCTAssertEqual(concept.codeValue, "50960005")
        XCTAssertEqual(concept.codingSchemeDesignator, "SCT")
        XCTAssertEqual(concept.codeMeaning, "Hemorrhage")
    }
    
    func testPneumoniaTypeIsPrivateCode() {
        // PS3.16 2026a Table D-1 and CIDs contain no "Pneumonia" or "Consolidation" concept;
        // M-40000 (SRT) is (23583003, SCT, "Inflammation (morphologic abnormality)") per Table O-1.
        @available(*, deprecated) func legacy() -> CodedConcept { AIDetectionType.pneumonia.concept }
        let concept = legacy()
        XCTAssertEqual(concept.codeValue, "PNEUMONIA")
        XCTAssertEqual(concept.codingSchemeDesignator, "99DICOMKIT")
        XCTAssertEqual(concept.codeMeaning, "Pneumonia")
    }
    
    func testPulmonaryEmbolismType() {
        let type = AIDetectionType.pulmonaryEmbolism
        let concept = type.concept
        
        // PS3.16 2026a CID 6104 "Abnormal Opacity Finding or Feature": SCT | 59282003 | Pulmonary embolism
        XCTAssertEqual(concept.codeValue, "59282003")
        XCTAssertEqual(concept.codingSchemeDesignator, "SCT")
        XCTAssertEqual(concept.codeMeaning, "Pulmonary embolism")
    }
    
    func testAnatomicalStructureTypeTakesRealAnatomyCode() {
        // PS3.16 2026a CID 4030 "CT, MR and PET Anatomy Imaged": SCT | 10200004 | Liver
        let type = AIDetectionType.anatomicalStructure(AIAnatomicRegion.liver)
        let concept = type.concept

        XCTAssertEqual(type, .anatomy(AIAnatomicRegion.liver))
        XCTAssertEqual(concept.codeValue, "10200004")
        XCTAssertEqual(concept.codingSchemeDesignator, "SCT")
        XCTAssertEqual(concept.codeMeaning, "Liver")
    }
    
    func testAnatomicalStructureNameIsPrivateCode() {
        // (T-D0050, SRT) is (85756007, SCT, "Body tissue structure (body structure)") per PS3.16 2026a
        // Table O-1 and never identified a named structure; the name-only overload is deprecated and
        // emits the private 99DICOMKIT scheme.
        @available(*, deprecated) func legacy() -> CodedConcept { AIDetectionType.anatomicalStructure(name: "Liver").concept }
        let concept = legacy()
        XCTAssertEqual(concept.codeValue, "ANATOMY")
        XCTAssertEqual(concept.codingSchemeDesignator, "99DICOMKIT")
        XCTAssertEqual(concept.codeMeaning, "Liver")
        XCTAssertNotEqual(concept.codeValue, "T-D0050")
    }
    
    func testAnatomicRegionConstantsMatchCIDRows() {
        // PS3.16 2026a CID 4 "Anatomic Region" rows
        XCTAssertEqual(AIAnatomicRegion.lung, CodedConcept(codeValue: "39607008", codingSchemeDesignator: "SCT", codeMeaning: "Lung"))
        XCTAssertEqual(AIAnatomicRegion.ovary, CodedConcept(codeValue: "15497006", codingSchemeDesignator: "SCT", codeMeaning: "Ovary"))
        XCTAssertEqual(AIAnatomicRegion.chest, CodedConcept(codeValue: "816094009", codingSchemeDesignator: "SCT", codeMeaning: "Chest"))
        // CID 4030 "CT, MR and PET Anatomy Imaged" rows
        XCTAssertEqual(AIAnatomicRegion.adrenalGland, CodedConcept(codeValue: "23451007", codingSchemeDesignator: "SCT", codeMeaning: "Adrenal gland"))
        XCTAssertEqual(AIAnatomicRegion.brain, CodedConcept(codeValue: "12738006", codingSchemeDesignator: "SCT", codeMeaning: "Brain"))
        XCTAssertEqual(AIAnatomicRegion.kidney, CodedConcept(codeValue: "64033007", codingSchemeDesignator: "SCT", codeMeaning: "Kidney"))
        XCTAssertEqual(AIAnatomicRegion.liver, CodedConcept(codeValue: "10200004", codingSchemeDesignator: "SCT", codeMeaning: "Liver"))
        XCTAssertEqual(AIAnatomicRegion.spleen, CodedConcept(codeValue: "78961009", codingSchemeDesignator: "SCT", codeMeaning: "Spleen"))
        XCTAssertEqual(AIAnatomicRegion.thyroid, CodedConcept(codeValue: "69748006", codingSchemeDesignator: "SCT", codeMeaning: "Thyroid"))
        XCTAssertEqual(AIAnatomicRegion.uterus, CodedConcept(codeValue: "35039007", codingSchemeDesignator: "SCT", codeMeaning: "Uterus"))
        // CID 4031 "Common Anatomic Region" rows
        XCTAssertEqual(AIAnatomicRegion.abdomen, CodedConcept(codeValue: "818981001", codingSchemeDesignator: "SCT", codeMeaning: "Abdomen"))
        XCTAssertEqual(AIAnatomicRegion.abdomenAndPelvis, CodedConcept(codeValue: "818982008", codingSchemeDesignator: "SCT", codeMeaning: "Abdomen and Pelvis"))
        XCTAssertEqual(AIAnatomicRegion.bladder, CodedConcept(codeValue: "89837001", codingSchemeDesignator: "SCT", codeMeaning: "Bladder"))
        XCTAssertEqual(AIAnatomicRegion.breast, CodedConcept(codeValue: "76752008", codingSchemeDesignator: "SCT", codeMeaning: "Breast"))
        XCTAssertEqual(AIAnatomicRegion.bronchus, CodedConcept(codeValue: "955009", codingSchemeDesignator: "SCT", codeMeaning: "Bronchus"))
        XCTAssertEqual(AIAnatomicRegion.cervicalSpine, CodedConcept(codeValue: "122494005", codingSchemeDesignator: "SCT", codeMeaning: "Cervical spine"))
        XCTAssertEqual(AIAnatomicRegion.colon, CodedConcept(codeValue: "71854001", codingSchemeDesignator: "SCT", codeMeaning: "Colon"))
        XCTAssertEqual(AIAnatomicRegion.esophagus, CodedConcept(codeValue: "32849002", codingSchemeDesignator: "SCT", codeMeaning: "Esophagus"))
        XCTAssertEqual(AIAnatomicRegion.femur, CodedConcept(codeValue: "71341001", codingSchemeDesignator: "SCT", codeMeaning: "Femur"))
        XCTAssertEqual(AIAnatomicRegion.foot, CodedConcept(codeValue: "56459004", codingSchemeDesignator: "SCT", codeMeaning: "Foot"))
        XCTAssertEqual(AIAnatomicRegion.gallbladder, CodedConcept(codeValue: "28231008", codingSchemeDesignator: "SCT", codeMeaning: "Gallbladder"))
        XCTAssertEqual(AIAnatomicRegion.hand, CodedConcept(codeValue: "85562004", codingSchemeDesignator: "SCT", codeMeaning: "Hand"))
        XCTAssertEqual(AIAnatomicRegion.head, CodedConcept(codeValue: "69536005", codingSchemeDesignator: "SCT", codeMeaning: "Head"))
        XCTAssertEqual(AIAnatomicRegion.heart, CodedConcept(codeValue: "80891009", codingSchemeDesignator: "SCT", codeMeaning: "Heart"))
        XCTAssertEqual(AIAnatomicRegion.hip, CodedConcept(codeValue: "29836001", codingSchemeDesignator: "SCT", codeMeaning: "Hip"))
        XCTAssertEqual(AIAnatomicRegion.humerus, CodedConcept(codeValue: "85050009", codingSchemeDesignator: "SCT", codeMeaning: "Humerus"))
        XCTAssertEqual(AIAnatomicRegion.knee, CodedConcept(codeValue: "72696002", codingSchemeDesignator: "SCT", codeMeaning: "Knee"))
        XCTAssertEqual(AIAnatomicRegion.lumbarSpine, CodedConcept(codeValue: "122496007", codingSchemeDesignator: "SCT", codeMeaning: "Lumbar spine"))
        XCTAssertEqual(AIAnatomicRegion.mediastinum, CodedConcept(codeValue: "72410000", codingSchemeDesignator: "SCT", codeMeaning: "Mediastinum"))
        XCTAssertEqual(AIAnatomicRegion.neck, CodedConcept(codeValue: "45048000", codingSchemeDesignator: "SCT", codeMeaning: "Neck"))
        XCTAssertEqual(AIAnatomicRegion.pancreas, CodedConcept(codeValue: "15776009", codingSchemeDesignator: "SCT", codeMeaning: "Pancreas"))
        XCTAssertEqual(AIAnatomicRegion.pelvis, CodedConcept(codeValue: "816092008", codingSchemeDesignator: "SCT", codeMeaning: "Pelvis"))
        XCTAssertEqual(AIAnatomicRegion.prostate, CodedConcept(codeValue: "41216001", codingSchemeDesignator: "SCT", codeMeaning: "Prostate"))
        XCTAssertEqual(AIAnatomicRegion.rib, CodedConcept(codeValue: "113197003", codingSchemeDesignator: "SCT", codeMeaning: "Rib"))
        XCTAssertEqual(AIAnatomicRegion.shoulder, CodedConcept(codeValue: "16982005", codingSchemeDesignator: "SCT", codeMeaning: "Shoulder"))
        XCTAssertEqual(AIAnatomicRegion.skull, CodedConcept(codeValue: "89546000", codingSchemeDesignator: "SCT", codeMeaning: "Skull"))
        XCTAssertEqual(AIAnatomicRegion.spine, CodedConcept(codeValue: "421060004", codingSchemeDesignator: "SCT", codeMeaning: "Spine"))
        XCTAssertEqual(AIAnatomicRegion.stomach, CodedConcept(codeValue: "69695003", codingSchemeDesignator: "SCT", codeMeaning: "Stomach"))
        XCTAssertEqual(AIAnatomicRegion.thoracicSpine, CodedConcept(codeValue: "122495006", codingSchemeDesignator: "SCT", codeMeaning: "Thoracic spine"))
        XCTAssertEqual(AIAnatomicRegion.trachea, CodedConcept(codeValue: "44567001", codingSchemeDesignator: "SCT", codeMeaning: "Trachea"))
    }
    
    func testPrivateCodingSchemeDesignatorStartsWith99() {
        // PS3.16 2026a Section 8 "Coding Schemes": local or private Coding Schemes shall be identified
        // by an alphanumeric identifier beginning with the characters "99" (HL7 v2 Table 0396).
        XCTAssertEqual(DICOMKitPrivateCodingScheme.designator, "99DICOMKIT")
        XCTAssertTrue(DICOMKitPrivateCodingScheme.designator.hasPrefix("99"))
        XCTAssertLessThanOrEqual(DICOMKitPrivateCodingScheme.designator.count, 16)   // SH VR
        let c = DICOMKitPrivateCodingScheme.concept("X", meaning: "x")
        XCTAssertEqual(c.codingSchemeDesignator, "99DICOMKIT")
        XCTAssertEqual(c.codeValue, "X")
    }
    
    func testCustomDetectionType() {
        let customConcept = CodedConcept(
            codeValue: "123456",
            codingSchemeDesignator: "CUSTOM",
            codeMeaning: "Custom Finding"
        )
        let type = AIDetectionType.custom(customConcept)
        let concept = type.concept
        
        XCTAssertEqual(concept.codeValue, "123456")
        XCTAssertEqual(concept.codingSchemeDesignator, "CUSTOM")
        XCTAssertEqual(concept.codeMeaning, "Custom Finding")
    }
    
    // MARK: - AIDetectionLocation Tests
    
    func testPoint2DLocation() {
        let imageRef = AIImageReference(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5"
        )
        
        let location = AIDetectionLocation.point2D(x: 150.5, y: 250.3, imageReference: imageRef)
        
        if case .point2D(let x, let y, let ref) = location {
            XCTAssertEqual(x, 150.5)
            XCTAssertEqual(y, 250.3)
            XCTAssertEqual(ref.sopClassUID, "1.2.840.10008.5.1.4.1.1.2")
            XCTAssertEqual(ref.sopInstanceUID, "1.2.3.4.5")
        } else {
            XCTFail("Expected point2D location")
        }
    }
    
    func testBoundingBox2DLocation() {
        let imageRef = AIImageReference(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5"
        )
        
        let location = AIDetectionLocation.boundingBox2D(
            x: 100.0, y: 100.0, width: 50.0, height: 75.0,
            imageReference: imageRef
        )
        
        if case .boundingBox2D(let x, let y, let width, let height, _) = location {
            XCTAssertEqual(x, 100.0)
            XCTAssertEqual(y, 100.0)
            XCTAssertEqual(width, 50.0)
            XCTAssertEqual(height, 75.0)
        } else {
            XCTFail("Expected boundingBox2D location")
        }
    }
    
    func testPolygon2DLocation() {
        let imageRef = AIImageReference(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5"
        )
        
        let points = [10.0, 20.0, 30.0, 40.0, 50.0, 60.0]
        let location = AIDetectionLocation.polygon2D(points: points, imageReference: imageRef)
        
        if case .polygon2D(let p, _) = location {
            XCTAssertEqual(p, points)
        } else {
            XCTFail("Expected polygon2D location")
        }
    }
    
    func testCircle2DLocation() {
        let imageRef = AIImageReference(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5"
        )
        
        let location = AIDetectionLocation.circle2D(
            centerX: 200.0, centerY: 300.0, radius: 25.0,
            imageReference: imageRef
        )
        
        if case .circle2D(let cx, let cy, let r, _) = location {
            XCTAssertEqual(cx, 200.0)
            XCTAssertEqual(cy, 300.0)
            XCTAssertEqual(r, 25.0)
        } else {
            XCTFail("Expected circle2D location")
        }
    }
    
    func testPoint3DLocation() {
        let imageRef = AIImageReference(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5"
        )
        
        let location = AIDetectionLocation.point3D(
            x: 100.0, y: 150.0, z: 200.0,
            frameOfReferenceUID: "1.2.3.4.5.6",
            imageReference: imageRef
        )
        
        if case .point3D(let x, let y, let z, let frameUID, _) = location {
            XCTAssertEqual(x, 100.0)
            XCTAssertEqual(y, 150.0)
            XCTAssertEqual(z, 200.0)
            XCTAssertEqual(frameUID, "1.2.3.4.5.6")
        } else {
            XCTFail("Expected point3D location")
        }
    }
    
    func testBoundingBox3DLocation() {
        let location = AIDetectionLocation.boundingBox3D(
            x: 10.0, y: 20.0, z: 30.0,
            width: 50.0, height: 60.0, depth: 70.0,
            frameOfReferenceUID: "1.2.3.4.5.6",
            imageReference: nil
        )
        
        if case .boundingBox3D(let x, let y, let z, let width, let height, let depth, let frameUID, _) = location {
            XCTAssertEqual(x, 10.0)
            XCTAssertEqual(y, 20.0)
            XCTAssertEqual(z, 30.0)
            XCTAssertEqual(width, 50.0)
            XCTAssertEqual(height, 60.0)
            XCTAssertEqual(depth, 70.0)
            XCTAssertEqual(frameUID, "1.2.3.4.5.6")
        } else {
            XCTFail("Expected boundingBox3D location")
        }
    }
    
    func testPolygon3DLocation() {
        let points = [10.0, 20.0, 30.0, 40.0, 50.0, 60.0]
        let location = AIDetectionLocation.polygon3D(
            points: points,
            frameOfReferenceUID: "1.2.3.4.5.6",
            imageReference: nil
        )
        
        if case .polygon3D(let p, let frameUID, _) = location {
            XCTAssertEqual(p, points)
            XCTAssertEqual(frameUID, "1.2.3.4.5.6")
        } else {
            XCTFail("Expected polygon3D location")
        }
    }
    
    func testEllipsoid3DLocation() {
        let location = AIDetectionLocation.ellipsoid3D(
            centerX: 100.0, centerY: 150.0, centerZ: 200.0,
            radiusX: 10.0, radiusY: 15.0, radiusZ: 20.0,
            frameOfReferenceUID: "1.2.3.4.5.6",
            imageReference: nil
        )
        
        if case .ellipsoid3D(let cx, let cy, let cz, let rx, let ry, let rz, let frameUID, _) = location {
            XCTAssertEqual(cx, 100.0)
            XCTAssertEqual(cy, 150.0)
            XCTAssertEqual(cz, 200.0)
            XCTAssertEqual(rx, 10.0)
            XCTAssertEqual(ry, 15.0)
            XCTAssertEqual(rz, 20.0)
            XCTAssertEqual(frameUID, "1.2.3.4.5.6")
        } else {
            XCTFail("Expected ellipsoid3D location")
        }
    }
    
    // MARK: - ImageReference Tests
    
    func testImageReferenceInitialization() {
        let ref = AIImageReference(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5"
        )
        
        XCTAssertEqual(ref.sopClassUID, "1.2.840.10008.5.1.4.1.1.2")
        XCTAssertEqual(ref.sopInstanceUID, "1.2.3.4.5")
        XCTAssertNil(ref.frameNumber)
    }
    
    func testImageReferenceWithFrameNumber() {
        let ref = AIImageReference(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5",
            frameNumber: 5
        )
        
        XCTAssertEqual(ref.frameNumber, 5)
    }
    
    // MARK: - ConfidenceScore Tests
    
    func testConfidenceScoreToPercentageString() {
        XCTAssertEqual(ConfidenceScore.toPercentageString(0.0), "0.0")
        XCTAssertEqual(ConfidenceScore.toPercentageString(0.5), "50.0")
        XCTAssertEqual(ConfidenceScore.toPercentageString(0.855), "85.5")
        XCTAssertEqual(ConfidenceScore.toPercentageString(1.0), "100.0")
    }
    
    func testCertaintyOfFindingConceptMatchesTID4104Row12() {
        // PS3.16 2026a TID 4104 "Chest CAD Single Image Finding" row 12:
        //   HAS PROPERTIES | NUM | EV (111012, DCM, "Certainty of Finding") | UNITS = EV (%, UCUM, "Percent") | Value = 0 - 100
        // and CID 6048 "CAD Operating Point Axis Label": DCM | 111012 | Certainty of Finding
        XCTAssertEqual(ConfidenceScore.certaintyOfFindingConcept.codeValue, "111012")
        XCTAssertEqual(ConfidenceScore.certaintyOfFindingConcept.codingSchemeDesignator, "DCM")
        XCTAssertEqual(ConfidenceScore.certaintyOfFindingConcept.codeMeaning, "Certainty of Finding")
        XCTAssertEqual(ConfidenceScore.percentUnits.codeValue, "%")
        XCTAssertEqual(ConfidenceScore.percentUnits.codingSchemeDesignator, "UCUM")
        XCTAssertEqual(ConfidenceScore.percentUnits.codeMeaning, "Percent")
    }
    
    func testCertaintyOfFindingNumericContentItem() {
        let item = ConfidenceScore.certaintyOfFinding(0.855)
        XCTAssertEqual(item.valueType, .num)
        XCTAssertEqual(item.conceptName, ConfidenceScore.certaintyOfFindingConcept)
        XCTAssertEqual(item.measurementUnits, ConfidenceScore.percentUnits)
        XCTAssertEqual(item.relationshipType, .hasProperties)   // TID 4104 row 12
        XCTAssertEqual(item.numericValues.count, 1)
        XCTAssertEqual(item.numericValues[0], 85.5, accuracy: 1e-9)
        
        // Value = 0 - 100: out-of-range scores are clamped
        XCTAssertEqual(ConfidenceScore.certaintyOfFinding(1.5).numericValues[0], 100.0)
        XCTAssertEqual(ConfidenceScore.certaintyOfFinding(-0.2).numericValues[0], 0.0)
        XCTAssertEqual(ConfidenceScore.toPercent(1.0), 100.0)
        XCTAssertEqual(ConfidenceScore.toPercent(0.0), 0.0)
        
        let contains = ConfidenceScore.certaintyOfFinding(0.5, relationshipType: .contains)
        XCTAssertEqual(contains.relationshipType, .contains)
    }
    
    func testConfidenceScoreToCodedConceptIsPrivateCode() {
        // PS3.16 2026a Table O-1: R-00339 = (373067005, SCT, "No (qualifier value)"),
        // R-00340 = (371857005, SCT, "Normal left ventricular systolic function and wall motion (finding)"),
        // R-00341 = (373129009, SCT, "Normal overall cardiac contractility (finding)").
        // None means a confidence level; the deprecated categorical API now emits 99DICOMKIT.
        @available(*, deprecated) func legacy(_ s: Double) -> CodedConcept { ConfidenceScore.toCodedConcept(s) }
        
        let highConcept = legacy(0.95)
        XCTAssertEqual(highConcept.codeValue, "CONF_HIGH")
        XCTAssertEqual(highConcept.codingSchemeDesignator, "99DICOMKIT")
        XCTAssertEqual(highConcept.codeMeaning, "High confidence")
        
        let mediumConcept = legacy(0.80)
        XCTAssertEqual(mediumConcept.codeValue, "CONF_MEDIUM")
        XCTAssertEqual(mediumConcept.codingSchemeDesignator, "99DICOMKIT")
        XCTAssertEqual(mediumConcept.codeMeaning, "Medium confidence")
        
        let lowConcept = legacy(0.65)
        XCTAssertEqual(lowConcept.codeValue, "CONF_LOW")
        XCTAssertEqual(lowConcept.codingSchemeDesignator, "99DICOMKIT")
        XCTAssertEqual(lowConcept.codeMeaning, "Low confidence")
        
        for c in [highConcept, mediumConcept, lowConcept] {
            XCTAssertFalse(["R-00339", "R-00340", "R-00341"].contains(c.codeValue))
            XCTAssertNotEqual(c.codingSchemeDesignator, "SRT")
        }
        XCTAssertEqual(ConfidenceCategory.high.privateConcept, highConcept)
        XCTAssertEqual(ConfidenceCategory.medium.privateConcept, mediumConcept)
        XCTAssertEqual(ConfidenceCategory.low.privateConcept, lowConcept)
    }
    
    func testConfidenceScoreCategorize() {
        XCTAssertEqual(ConfidenceScore.categorize(0.95), .high)
        XCTAssertEqual(ConfidenceScore.categorize(0.90), .high)
        XCTAssertEqual(ConfidenceScore.categorize(0.85), .medium)
        XCTAssertEqual(ConfidenceScore.categorize(0.70), .medium)
        XCTAssertEqual(ConfidenceScore.categorize(0.65), .low)
        XCTAssertEqual(ConfidenceScore.categorize(0.0), .low)
    }
    
    func testConfidenceScoreBoundaries() {
        // Test boundary conditions
        XCTAssertEqual(ConfidenceScore.categorize(1.0), .high)
        XCTAssertEqual(ConfidenceScore.categorize(0.9), .high)
        XCTAssertEqual(ConfidenceScore.categorize(0.89999), .medium)
        XCTAssertEqual(ConfidenceScore.categorize(0.7), .medium)
        XCTAssertEqual(ConfidenceScore.categorize(0.69999), .low)
    }
}
