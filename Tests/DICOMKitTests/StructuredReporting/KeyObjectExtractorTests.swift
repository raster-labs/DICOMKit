/// Tests for KeyObjects Extraction API
///
/// Validates extraction of Key Object Selection data from KOS documents.

import XCTest
@testable import DICOMKit
@testable import DICOMCore

final class KeyObjectExtractorTests: XCTestCase {
    
    // MARK: - Helper Methods
    
    private func createBasicKeyObjectDocument() throws -> SRDocument {
        let keyObject = KeyObject(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9"
        )
        
        let document = try KeyObjectSelectionBuilder()
            .withPatientID("12345")
            .withPatientName("Doe^John")
            .withStudyInstanceUID("1.2.3.4.5")
            .withDocumentTitle(.ofInterest)
            .addKeyObject(sopClassUID: keyObject.sopClassUID, sopInstanceUID: keyObject.sopInstanceUID, description: keyObject.description, frames: keyObject.frames)
            .build()
        
        return document
    }
    
    private func serializeAndParse(_ document: SRDocument) throws -> SRDocument {
        let serializer = SRDocumentSerializer()
        let dataSet = try serializer.serialize(document: document)
        
        let parser = SRDocumentParser()
        return try parser.parse(dataSet: dataSet)
    }
    
    private func createSampleKeyObject(uid: String = "1.2.3.4.5.6.7.8.9") -> KeyObject {
        KeyObject(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: uid
        )
    }
    
    // MARK: - Basic Extraction Tests
    
    func testExtractMinimalKeyObjects() throws {
        let original = try createBasicKeyObjectDocument()
        let parsed = try serializeAndParse(original)
        
        let keyObjects = try KeyObjects.extract(from: parsed)
        
        XCTAssertEqual(keyObjects.document.sopClassUID, SRDocumentType.keyObjectSelectionDocument.sopClassUID)
        XCTAssertEqual(keyObjects.objects.count, 1)
    }
    
    func testExtractDocumentTitle() throws {
        let keyObject = createSampleKeyObject()
        
        let original = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.ofInterest)
            .addKeyObject(sopClassUID: keyObject.sopClassUID, sopInstanceUID: keyObject.sopInstanceUID, description: keyObject.description, frames: keyObject.frames)
            .build()
        let parsed = try serializeAndParse(original)
        
        let keyObjects = try KeyObjects.extract(from: parsed)
        
        XCTAssertNotNil(keyObjects.documentTitle)
        XCTAssertEqual(keyObjects.documentTitle?.codeValue, "113000")
        XCTAssertEqual(keyObjects.documentTitle?.codeMeaning, "Of Interest")
    }
    
    func testExtractSelectionPurpose() throws {
        let keyObject = createSampleKeyObject()
        
        let original = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.forTeaching)
            .addKeyObject(sopClassUID: keyObject.sopClassUID, sopInstanceUID: keyObject.sopInstanceUID, description: keyObject.description, frames: keyObject.frames)
            .build()
        let parsed = try serializeAndParse(original)
        
        let keyObjects = try KeyObjects.extract(from: parsed)
        
        XCTAssertNotNil(keyObjects.selectionPurpose)
        XCTAssertEqual(keyObjects.selectionPurpose?.codeValue, "113004")
        XCTAssertEqual(keyObjects.selectionPurpose?.codeMeaning, "For Teaching")
    }
    
    func testExtractWithCustomDocumentTitle() throws {
        let keyObject = createSampleKeyObject()
        let customTitle = CodedConcept(
            codeValue: "CUSTOM-001",
            codingSchemeDesignator: "99TEST",
            codeMeaning: "Custom Purpose"
        )
        
        let original = try KeyObjectSelectionBuilder()
            .withDocumentTitle(customTitle)
            .addKeyObject(sopClassUID: keyObject.sopClassUID, sopInstanceUID: keyObject.sopInstanceUID, description: keyObject.description, frames: keyObject.frames)
            .build()
        let parsed = try serializeAndParse(original)
        
        let keyObjects = try KeyObjects.extract(from: parsed)
        
        XCTAssertEqual(keyObjects.documentTitle?.codeValue, "CUSTOM-001")
        XCTAssertEqual(keyObjects.documentTitle?.codeMeaning, "Custom Purpose")
    }
    
    // MARK: - Single Key Object Tests
    
    func testExtractSingleKeyObject() throws {
        let keyObject = KeyObject(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9"
        )
        
        let original = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.ofInterest)
            .addKeyObject(sopClassUID: keyObject.sopClassUID, sopInstanceUID: keyObject.sopInstanceUID, description: keyObject.description, frames: keyObject.frames)
            .build()
        let parsed = try serializeAndParse(original)
        
        let keyObjects = try KeyObjects.extract(from: parsed)
        
        XCTAssertEqual(keyObjects.objects.count, 1)
        XCTAssertEqual(keyObjects.objects[0].sopInstanceUID, "1.2.3.4.5.6.7.8.9")
        XCTAssertEqual(keyObjects.objects[0].sopClassUID, "1.2.840.10008.5.1.4.1.1.2")
        XCTAssertNil(keyObjects.objects[0].description)
        XCTAssertNil(keyObjects.objects[0].frames)
    }
    
    func testExtractKeyObjectWithDescription() throws {
        let keyObject = KeyObject(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9",
            description: "Representative image showing pathology"
        )
        
        let original = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.ofInterest)
            .addKeyObject(sopClassUID: keyObject.sopClassUID, sopInstanceUID: keyObject.sopInstanceUID, description: keyObject.description, frames: keyObject.frames)
            .build()
        let parsed = try serializeAndParse(original)
        
        let keyObjects = try KeyObjects.extract(from: parsed)
        
        XCTAssertEqual(keyObjects.objects.count, 1)
        XCTAssertEqual(keyObjects.objects[0].description, "Representative image showing pathology")
    }
    
    func testExtractKeyObjectWithFrames() throws {
        let keyObject = KeyObject(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9",
            frames: [1, 5, 10, 15]
        )
        
        let original = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.ofInterest)
            .addKeyObject(sopClassUID: keyObject.sopClassUID, sopInstanceUID: keyObject.sopInstanceUID, description: keyObject.description, frames: keyObject.frames)
            .build()
        let parsed = try serializeAndParse(original)
        
        let keyObjects = try KeyObjects.extract(from: parsed)
        
        XCTAssertEqual(keyObjects.objects.count, 1)
        XCTAssertNotNil(keyObjects.objects[0].frames)
        XCTAssertEqual(keyObjects.objects[0].frames?.count, 4)
        XCTAssertEqual(keyObjects.objects[0].frames, [1, 5, 10, 15])
    }
    
    func testExtractKeyObjectWithDescriptionAndFrames() throws {
        let keyObject = KeyObject(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9",
            description: "Key frames from cine study",
            frames: [1, 10, 20]
        )
        
        let original = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.ofInterest)
            .addKeyObject(sopClassUID: keyObject.sopClassUID, sopInstanceUID: keyObject.sopInstanceUID, description: keyObject.description, frames: keyObject.frames)
            .build()
        let parsed = try serializeAndParse(original)
        
        let keyObjects = try KeyObjects.extract(from: parsed)
        
        XCTAssertEqual(keyObjects.objects.count, 1)
        XCTAssertEqual(keyObjects.objects[0].description, "Key frames from cine study")
        XCTAssertEqual(keyObjects.objects[0].frames, [1, 10, 20])
    }
    
    // MARK: - Multiple Key Objects Tests
    
    func testExtractMultipleKeyObjects() throws {
        let obj1 = KeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.4.5.1")
        let obj2 = KeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.4.5.2")
        let obj3 = KeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.4.5.3")
        
        let original = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.ofInterest)
            .addKeyObject(sopClassUID: obj1.sopClassUID, sopInstanceUID: obj1.sopInstanceUID, description: obj1.description, frames: obj1.frames)
            .addKeyObject(sopClassUID: obj2.sopClassUID, sopInstanceUID: obj2.sopInstanceUID, description: obj2.description, frames: obj2.frames)
            .addKeyObject(sopClassUID: obj3.sopClassUID, sopInstanceUID: obj3.sopInstanceUID, description: obj3.description, frames: obj3.frames)
            .build()
        let parsed = try serializeAndParse(original)
        
        let keyObjects = try KeyObjects.extract(from: parsed)
        
        XCTAssertEqual(keyObjects.objects.count, 3)
        XCTAssertEqual(keyObjects.objects[0].sopInstanceUID, "1.2.3.4.5.1")
        XCTAssertEqual(keyObjects.objects[1].sopInstanceUID, "1.2.3.4.5.2")
        XCTAssertEqual(keyObjects.objects[2].sopInstanceUID, "1.2.3.4.5.3")
    }
    
    func testExtractMultipleKeyObjectsWithDescriptions() throws {
        let obj1 = KeyObject(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.1",
            description: "Baseline study"
        )
        let obj2 = KeyObject(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.2",
            description: "Follow-up study"
        )
        let obj3 = KeyObject(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.3",
            description: "Post-treatment study"
        )
        
        let original = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.ofInterest)
            .addKeyObject(sopClassUID: obj1.sopClassUID, sopInstanceUID: obj1.sopInstanceUID, description: obj1.description, frames: obj1.frames)
            .addKeyObject(sopClassUID: obj2.sopClassUID, sopInstanceUID: obj2.sopInstanceUID, description: obj2.description, frames: obj2.frames)
            .addKeyObject(sopClassUID: obj3.sopClassUID, sopInstanceUID: obj3.sopInstanceUID, description: obj3.description, frames: obj3.frames)
            .build()
        let parsed = try serializeAndParse(original)
        
        let keyObjects = try KeyObjects.extract(from: parsed)
        
        XCTAssertEqual(keyObjects.objects.count, 3)
        XCTAssertEqual(keyObjects.objects[0].description, "Baseline study")
        XCTAssertEqual(keyObjects.objects[1].description, "Follow-up study")
        XCTAssertEqual(keyObjects.objects[2].description, "Post-treatment study")
    }
    
    func testExtractManyKeyObjects() throws {
        var builder = KeyObjectSelectionBuilder()
            .withDocumentTitle(.ofInterest)
        
        for i in 1...20 {
            let obj = KeyObject(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: "1.2.3.4.5.6.7.8.\(i)",
                description: "Object \(i)"
            )
            builder = builder.addKeyObject(sopClassUID: obj.sopClassUID, sopInstanceUID: obj.sopInstanceUID, description: obj.description, frames: obj.frames)
        }
        
        let original = try builder.build()
        let parsed = try serializeAndParse(original)
        let keyObjects = try KeyObjects.extract(from: parsed)
        
        XCTAssertEqual(keyObjects.objects.count, 20)
    }
    
    // MARK: - Document Title Variations Tests
    
    func testExtractWithOfInterestTitle() throws {
        let keyObject = createSampleKeyObject()
        
        let original = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.ofInterest)
            .addKeyObject(sopClassUID: keyObject.sopClassUID, sopInstanceUID: keyObject.sopInstanceUID, description: keyObject.description, frames: keyObject.frames)
            .build()
        let parsed = try serializeAndParse(original)
        
        let keyObjects = try KeyObjects.extract(from: parsed)
        
        XCTAssertEqual(keyObjects.documentTitle?.codeValue, "113000")
    }
    
    func testExtractWithRejectedForQualityTitle() throws {
        let keyObject = createSampleKeyObject()
        
        let original = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.rejectedForQuality)
            .addKeyObject(sopClassUID: keyObject.sopClassUID, sopInstanceUID: keyObject.sopInstanceUID, description: keyObject.description, frames: keyObject.frames)
            .build()
        let parsed = try serializeAndParse(original)
        
        let keyObjects = try KeyObjects.extract(from: parsed)
        
        XCTAssertEqual(keyObjects.documentTitle?.codeValue, "113001")
    }
    
    func testExtractWithForReferringProviderTitle() throws {
        let keyObject = createSampleKeyObject()
        
        let original = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.forReferringProvider)
            .addKeyObject(sopClassUID: keyObject.sopClassUID, sopInstanceUID: keyObject.sopInstanceUID, description: keyObject.description, frames: keyObject.frames)
            .build()
        let parsed = try serializeAndParse(original)
        
        let keyObjects = try KeyObjects.extract(from: parsed)
        
        XCTAssertEqual(keyObjects.documentTitle?.codeValue, "113002")
    }
    
    func testExtractWithForSurgeryTitle() throws {
        let keyObject = createSampleKeyObject()
        
        let original = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.forSurgery)
            .addKeyObject(sopClassUID: keyObject.sopClassUID, sopInstanceUID: keyObject.sopInstanceUID, description: keyObject.description, frames: keyObject.frames)
            .build()
        let parsed = try serializeAndParse(original)
        
        let keyObjects = try KeyObjects.extract(from: parsed)
        
        XCTAssertEqual(keyObjects.documentTitle?.codeValue, "113003")
    }
    
    func testExtractWithForTeachingTitle() throws {
        let keyObject = createSampleKeyObject()
        
        let original = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.forTeaching)
            .addKeyObject(sopClassUID: keyObject.sopClassUID, sopInstanceUID: keyObject.sopInstanceUID, description: keyObject.description, frames: keyObject.frames)
            .build()
        let parsed = try serializeAndParse(original)
        
        let keyObjects = try KeyObjects.extract(from: parsed)
        
        XCTAssertEqual(keyObjects.documentTitle?.codeValue, "113004")
    }
    
    func testExtractWithQualityIssueTitle() throws {
        let keyObject = createSampleKeyObject()
        
        let original = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.qualityIssue)
            .addKeyObject(sopClassUID: keyObject.sopClassUID, sopInstanceUID: keyObject.sopInstanceUID, description: keyObject.description, frames: keyObject.frames)
            .build()
        let parsed = try serializeAndParse(original)
        
        let keyObjects = try KeyObjects.extract(from: parsed)
        
        XCTAssertEqual(keyObjects.documentTitle?.codeValue, "113010")
    }
    
    func testExtractWithBestInSetTitle() throws {
        let keyObject = createSampleKeyObject()
        
        let original = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.bestInSet)
            .addKeyObject(sopClassUID: keyObject.sopClassUID, sopInstanceUID: keyObject.sopInstanceUID, description: keyObject.description, frames: keyObject.frames)
            .build()
        let parsed = try serializeAndParse(original)
        
        let keyObjects = try KeyObjects.extract(from: parsed)
        
        XCTAssertEqual(keyObjects.documentTitle?.codeValue, "113013")   // (113013, DCM, "Best In Set"), CID 7010
    }
    
    // MARK: - SOP Class Variations Tests
    
    func testExtractWithCTImageSOPClass() throws {
        let keyObject = KeyObject(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9"
        )
        
        let original = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.ofInterest)
            .addKeyObject(sopClassUID: keyObject.sopClassUID, sopInstanceUID: keyObject.sopInstanceUID, description: keyObject.description, frames: keyObject.frames)
            .build()
        let parsed = try serializeAndParse(original)
        
        let keyObjects = try KeyObjects.extract(from: parsed)
        
        XCTAssertEqual(keyObjects.objects[0].sopClassUID, "1.2.840.10008.5.1.4.1.1.2")
    }
    
    func testExtractWithMRImageSOPClass() throws {
        let keyObject = KeyObject(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.4",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9"
        )
        
        let original = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.ofInterest)
            .addKeyObject(sopClassUID: keyObject.sopClassUID, sopInstanceUID: keyObject.sopInstanceUID, description: keyObject.description, frames: keyObject.frames)
            .build()
        let parsed = try serializeAndParse(original)
        
        let keyObjects = try KeyObjects.extract(from: parsed)
        
        XCTAssertEqual(keyObjects.objects[0].sopClassUID, "1.2.840.10008.5.1.4.1.1.4")
    }
    
    func testExtractWithMultipleDifferentSOPClasses() throws {
        let ctImage = KeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.4.5.1")
        let mrImage = KeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.4", sopInstanceUID: "1.2.3.4.5.2")
        let usImage = KeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.6.1", sopInstanceUID: "1.2.3.4.5.3")
        
        let original = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.ofInterest)
            .addKeyObject(sopClassUID: ctImage.sopClassUID, sopInstanceUID: ctImage.sopInstanceUID)
            .addKeyObject(sopClassUID: mrImage.sopClassUID, sopInstanceUID: mrImage.sopInstanceUID)
            .addKeyObject(sopClassUID: usImage.sopClassUID, sopInstanceUID: usImage.sopInstanceUID)
            .build()
        let parsed = try serializeAndParse(original)
        
        let keyObjects = try KeyObjects.extract(from: parsed)
        
        XCTAssertEqual(keyObjects.objects.count, 3)
        XCTAssertEqual(keyObjects.objects[0].sopClassUID, "1.2.840.10008.5.1.4.1.1.2")
        XCTAssertEqual(keyObjects.objects[1].sopClassUID, "1.2.840.10008.5.1.4.1.1.4")
        XCTAssertEqual(keyObjects.objects[2].sopClassUID, "1.2.840.10008.5.1.4.1.1.6.1")
    }
    
    // MARK: - Error Cases Tests
    
    func testExtractFromInvalidDocumentType() throws {
        let document = try BasicTextSRBuilder()
            .build()
        let parsed = try serializeAndParse(document)
        
        XCTAssertThrowsError(try KeyObjects.extract(from: parsed)) { error in
            guard case ExtractionError.invalidDocumentType = error else {
                XCTFail("Expected invalidDocumentType error")
                return
            }
        }
    }
    
    func testExtractFromMeasurementReport() throws {
        let document = try MeasurementReportBuilder()
            .addMeasurementGroup(trackingIdentifier: "Lesion 1") {
                MeasurementGroupContentHelper.longAxisMM(value: 10.0)
            }
            .build()
        let parsed = try serializeAndParse(document)
        
        XCTAssertThrowsError(try KeyObjects.extract(from: parsed)) { error in
            guard case ExtractionError.invalidDocumentType = error else {
                XCTFail("Expected invalidDocumentType error")
                return
            }
        }
    }
    
    func testExtractFromMammographyCAD() throws {
        let imageRef = ImageReference(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9"
        )
        
        let document = try MammographyCADSRBuilder()
            .withCADProcessingSummary(algorithmName: "MammoCAD", algorithmVersion: "2.0", manufacturer: "Vendor")
            .addFinding(
                type: .mass,
                probability: 0.8,
                location: .point2D(x: 100.0, y: 100.0, imageReference: imageRef)
            )
            .build()
        let parsed = try serializeAndParse(document)
        
        XCTAssertThrowsError(try KeyObjects.extract(from: parsed)) { error in
            guard case ExtractionError.invalidDocumentType = error else {
                XCTFail("Expected invalidDocumentType error")
                return
            }
        }
    }
    
    func testExtractFromEmptyKeyObjectDocument() throws {
        let document = try KeyObjectSelectionBuilder(validateOnBuild: false)
            .withDocumentTitle(.ofInterest)
            .build()
        let parsed = try serializeAndParse(document)
        
        XCTAssertThrowsError(try KeyObjects.extract(from: parsed)) { error in
            guard case ExtractionError.invalidStructure = error else {
                XCTFail("Expected invalidStructure error")
                return
            }
        }
    }
    
    // MARK: - Complete Workflow Tests
    
    func testCompleteWorkflowSimple() throws {
        let keyObject = KeyObject(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9",
            description: "Key image for review"
        )
        
        let original = try KeyObjectSelectionBuilder()
            .withPatientID("KOS-2024-001")
            .withPatientName("Smith^John")
            .withStudyInstanceUID("1.2.840.113619.2.5.1762583153.215519.978957063.100")
            .withDocumentTitle(.ofInterest)
            .addKeyObject(sopClassUID: keyObject.sopClassUID, sopInstanceUID: keyObject.sopInstanceUID, description: keyObject.description, frames: keyObject.frames)
            .build()
        
        let parsed = try serializeAndParse(original)
        let extracted = try KeyObjects.extract(from: parsed)
        
        // Verify roundtrip
        XCTAssertEqual(extracted.document.patientID, "KOS-2024-001")
        XCTAssertEqual(extracted.objects.count, 1)
        XCTAssertEqual(extracted.objects[0].sopInstanceUID, "1.2.3.4.5.6.7.8.9")
        XCTAssertEqual(extracted.objects[0].description, "Key image for review")
    }
    
    func testCompleteWorkflowComplex() throws {
        let obj1 = KeyObject(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7.8.1",
            description: "Baseline CT chest",
            frames: [5, 10, 15]
        )
        let obj2 = KeyObject(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7.8.2",
            description: "Follow-up CT chest"
        )
        let obj3 = KeyObject(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.4",
            sopInstanceUID: "1.2.3.4.5.6.7.8.3",
            description: "MR brain for correlation",
            frames: [1]
        )
        
        let original = try KeyObjectSelectionBuilder()
            .withPatientID("KOS-2024-002")
            .withPatientName("Doe^Jane")
            .withPatientBirthDate("19800515")
            .withPatientSex("F")
            .withStudyInstanceUID("1.2.840.113619.2.5.1762583153.215519.978957063.200")
            .withStudyDate("20240115")
            .withStudyTime("143000")
            .withDocumentTitle(.forReferringProvider)
            .addKeyObject(sopClassUID: obj1.sopClassUID, sopInstanceUID: obj1.sopInstanceUID, description: obj1.description, frames: obj1.frames)
            .addKeyObject(sopClassUID: obj2.sopClassUID, sopInstanceUID: obj2.sopInstanceUID, description: obj2.description, frames: obj2.frames)
            .addKeyObject(sopClassUID: obj3.sopClassUID, sopInstanceUID: obj3.sopInstanceUID, description: obj3.description, frames: obj3.frames)
            .build()
        
        let parsed = try serializeAndParse(original)
        let extracted = try KeyObjects.extract(from: parsed)
        
        // Verify all data
        XCTAssertEqual(extracted.document.patientID, "KOS-2024-002")
        XCTAssertEqual(extracted.documentTitle?.codeMeaning, "For Referring Provider")
        XCTAssertEqual(extracted.objects.count, 3)
        
        // Verify first object
        XCTAssertEqual(extracted.objects[0].description, "Baseline CT chest")
        XCTAssertEqual(extracted.objects[0].frames, [5, 10, 15])
        
        // Verify second object
        XCTAssertEqual(extracted.objects[1].description, "Follow-up CT chest")
        XCTAssertNil(extracted.objects[1].frames)
        
        // Verify third object
        XCTAssertEqual(extracted.objects[2].description, "MR brain for correlation")
        XCTAssertEqual(extracted.objects[2].frames, [1])
    }
    
    // MARK: - Edge Cases Tests
    
    func testExtractKeyObjectWithEmptyDescription() throws {
        let keyObject = KeyObject(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9",
            description: ""
        )
        
        let original = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.ofInterest)
            .addKeyObject(sopClassUID: keyObject.sopClassUID, sopInstanceUID: keyObject.sopInstanceUID, description: keyObject.description, frames: keyObject.frames)
            .build()
        let parsed = try serializeAndParse(original)
        
        let keyObjects = try KeyObjects.extract(from: parsed)
        
        XCTAssertEqual(keyObjects.objects.count, 1)
        // Empty description may be preserved or converted to nil
        XCTAssertTrue(keyObjects.objects[0].description == "" || keyObjects.objects[0].description == nil)
    }
    
    func testExtractKeyObjectWithSingleFrame() throws {
        let keyObject = KeyObject(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9",
            frames: [1]
        )
        
        let original = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.ofInterest)
            .addKeyObject(sopClassUID: keyObject.sopClassUID, sopInstanceUID: keyObject.sopInstanceUID, description: keyObject.description, frames: keyObject.frames)
            .build()
        let parsed = try serializeAndParse(original)
        
        let keyObjects = try KeyObjects.extract(from: parsed)
        
        XCTAssertEqual(keyObjects.objects.count, 1)
        XCTAssertEqual(keyObjects.objects[0].frames, [1])
    }
    
    func testExtractKeyObjectWithManyFrames() throws {
        let frames = Array(1...100)
        let keyObject = KeyObject(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9",
            frames: frames
        )
        
        let original = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.ofInterest)
            .addKeyObject(sopClassUID: keyObject.sopClassUID, sopInstanceUID: keyObject.sopInstanceUID, description: keyObject.description, frames: keyObject.frames)
            .build()
        let parsed = try serializeAndParse(original)
        
        let keyObjects = try KeyObjects.extract(from: parsed)
        
        XCTAssertEqual(keyObjects.objects.count, 1)
        XCTAssertEqual(keyObjects.objects[0].frames?.count, 100)
    }
    
    func testExtractKeyObjectWithVeryLongDescription() throws {
        let longDescription = String(repeating: "A", count: 1000)
        let keyObject = KeyObject(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9",
            description: longDescription
        )
        
        let original = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.ofInterest)
            .addKeyObject(sopClassUID: keyObject.sopClassUID, sopInstanceUID: keyObject.sopInstanceUID, description: keyObject.description, frames: keyObject.frames)
            .build()
        let parsed = try serializeAndParse(original)
        
        let keyObjects = try KeyObjects.extract(from: parsed)
        
        XCTAssertEqual(keyObjects.objects.count, 1)
        XCTAssertEqual(keyObjects.objects[0].description?.count, 1000)
    }
    
    func testExtractPreservesObjectOrder() throws {
        var builder = KeyObjectSelectionBuilder()
            .withDocumentTitle(.ofInterest)
        
        for i in 1...10 {
            let obj = KeyObject(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: "1.2.3.4.5.6.7.8.\(i)",
                description: "Object \(i)"
            )
            builder = builder.addKeyObject(sopClassUID: obj.sopClassUID, sopInstanceUID: obj.sopInstanceUID, description: obj.description, frames: obj.frames)
        }
        
        let original = try builder.build()
        let parsed = try serializeAndParse(original)
        let keyObjects = try KeyObjects.extract(from: parsed)
        
        XCTAssertEqual(keyObjects.objects.count, 10)
        
        // Verify order is preserved
        for i in 0..<10 {
            XCTAssertEqual(keyObjects.objects[i].description, "Object \(i + 1)")
        }
    }
    
    func testExtractWithMixedDescribedAndUndescribedObjects() throws {
        let obj1 = KeyObject(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.1",
            description: "First image"
        )
        let obj2 = KeyObject(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.2"
        )
        let obj3 = KeyObject(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.3",
            description: "Third image"
        )
        
        let original = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.ofInterest)
            .addKeyObject(sopClassUID: obj1.sopClassUID, sopInstanceUID: obj1.sopInstanceUID, description: obj1.description, frames: obj1.frames)
            .addKeyObject(sopClassUID: obj2.sopClassUID, sopInstanceUID: obj2.sopInstanceUID, description: obj2.description, frames: obj2.frames)
            .addKeyObject(sopClassUID: obj3.sopClassUID, sopInstanceUID: obj3.sopInstanceUID, description: obj3.description, frames: obj3.frames)
            .build()
        let parsed = try serializeAndParse(original)
        
        let keyObjects = try KeyObjects.extract(from: parsed)
        
        XCTAssertEqual(keyObjects.objects.count, 3)
        XCTAssertNotNil(keyObjects.objects[0].description)
        XCTAssertNil(keyObjects.objects[1].description)
        XCTAssertNotNil(keyObjects.objects[2].description)
    }
}
