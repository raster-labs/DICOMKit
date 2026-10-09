import Testing
import Foundation
import DICOMCore
@testable import DICOMKit

// MARK: - KeyObjectSelectionBuilder Tests

@Suite("KeyObjectSelectionBuilder Tests")
struct KeyObjectSelectionBuilderTests {
    
    // MARK: - Basic Builder Tests
    
    @Test("Builder initialization with default values")
    func testBuilderInitialization() {
        let builder = KeyObjectSelectionBuilder()
        
        #expect(builder.validateOnBuild == true)
        #expect(builder.completionFlag == .complete)
        #expect(builder.verificationFlag == .unverified)
        #expect(builder.keyObjects.isEmpty)
    }
    
    @Test("Builder initialization with validation disabled")
    func testBuilderWithValidationDisabled() {
        let builder = KeyObjectSelectionBuilder(validateOnBuild: false)
        #expect(builder.validateOnBuild == false)
    }
    
    @Test("Build validation fails with no key objects")
    func testBuildValidationFailsWithNoKeyObjects() {
        let builder = KeyObjectSelectionBuilder()
        
        #expect(throws: KeyObjectSelectionBuilder.BuildError.self) {
            try builder.build()
        }
    }
    
    @Test("Build succeeds with validation disabled and no key objects")
    func testBuildSucceedsWithValidationDisabled() throws {
        let document = try KeyObjectSelectionBuilder(validateOnBuild: false)
            .build()
        
        #expect(document.sopClassUID == SRDocumentType.keyObjectSelectionDocument.sopClassUID)
        #expect(document.documentType == .keyObjectSelectionDocument)
    }
    
    // MARK: - Document Identification Tests
    
    @Test("Set SOP Instance UID")
    func testSetSOPInstanceUID() throws {
        let uid = "1.2.3.4.5.6.7.8.9"
        let document = try KeyObjectSelectionBuilder()
            .withSOPInstanceUID(uid)
            .addKeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3")
            .build()
        
        #expect(document.sopInstanceUID == uid)
    }
    
    @Test("Set Study Instance UID")
    func testSetStudyInstanceUID() throws {
        let uid = "1.2.3.4.5.6.7.8.9.10"
        let document = try KeyObjectSelectionBuilder()
            .withStudyInstanceUID(uid)
            .addKeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3")
            .build()
        
        #expect(document.studyInstanceUID == uid)
    }
    
    @Test("Set Series Instance UID")
    func testSetSeriesInstanceUID() throws {
        let uid = "1.2.3.4.5.6.7.8.9.11"
        let document = try KeyObjectSelectionBuilder()
            .withSeriesInstanceUID(uid)
            .addKeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3")
            .build()
        
        #expect(document.seriesInstanceUID == uid)
    }
    
    @Test("Set Instance Number")
    func testSetInstanceNumber() throws {
        let document = try KeyObjectSelectionBuilder()
            .withInstanceNumber("1")
            .addKeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3")
            .build()
        
        #expect(document.instanceNumber == "1")
    }
    
    // MARK: - Patient Information Tests
    
    @Test("Set patient information")
    func testSetPatientInformation() throws {
        let document = try KeyObjectSelectionBuilder()
            .withPatientID("PAT001")
            .withPatientName("Doe^John")
            .withPatientBirthDate("19800115")
            .withPatientSex("M")
            .addKeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3")
            .build()
        
        #expect(document.patientID == "PAT001")
        #expect(document.patientName == "Doe^John")
    }
    
    // MARK: - Study Information Tests
    
    @Test("Set study information")
    func testSetStudyInformation() throws {
        let document = try KeyObjectSelectionBuilder()
            .withStudyDate("20240115")
            .withStudyTime("143022")
            .withStudyDescription("CT Chest")
            .withAccessionNumber("ACC001")
            .withReferringPhysicianName("Smith^Jane")
            .addKeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3")
            .build()
        
        #expect(document.studyDate == "20240115")
        #expect(document.studyTime == "143022")
        #expect(document.accessionNumber == "ACC001")
    }
    
    // MARK: - Series Information Tests
    
    @Test("Set series information")
    func testSetSeriesInformation() throws {
        let document = try KeyObjectSelectionBuilder()
            .withSeriesNumber("1")
            .withSeriesDescription("Key Images")
            .addKeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3")
            .build()
        
        #expect(document.seriesNumber == "1")
    }
    
    // MARK: - Document Information Tests
    
    @Test("Set content date and time")
    func testSetContentDateAndTime() throws {
        let document = try KeyObjectSelectionBuilder()
            .withContentDate("20240115")
            .withContentTime("143022")
            .addKeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3")
            .build()
        
        #expect(document.contentDate == "20240115")
        #expect(document.contentTime == "143022")
    }
    
    @Test("Set completion flag")
    func testSetCompletionFlag() throws {
        let document = try KeyObjectSelectionBuilder()
            .withCompletionFlag(.partial)
            .addKeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3")
            .build()
        
        #expect(document.completionFlag == .partial)
    }
    
    @Test("Set verification flag")
    func testSetVerificationFlag() throws {
        let document = try KeyObjectSelectionBuilder()
            .withVerificationFlag(.verified)
            .addKeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3")
            .build()
        
        #expect(document.verificationFlag == .verified)
    }
    
    // MARK: - Document Title Tests
    
    @Test("Set document title - For Teaching")
    func testSetDocumentTitleForTeaching() throws {
        let document = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.forTeaching)
            .addKeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3")
            .build()
        
        #expect(document.documentTitle?.codeValue == "113004")
        #expect(document.documentTitle?.codingSchemeDesignator == "DCM")
        #expect(document.documentTitle?.codeMeaning == "For Teaching")
    }
    
    @Test("Set document title - Rejected for Quality")
    func testSetDocumentTitleRejectedForQuality() throws {
        let document = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.rejectedForQuality)
            .addKeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3")
            .build()
        
        #expect(document.documentTitle?.codeValue == "113001")
        #expect(document.documentTitle?.codeMeaning == "Rejected for Quality Reasons")
    }
    
    @Test("Set document title - For Referring Provider")
    func testSetDocumentTitleForReferringProvider() throws {
        let document = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.forReferringProvider)
            .addKeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3")
            .build()
        
        #expect(document.documentTitle?.codeValue == "113002")
        #expect(document.documentTitle?.codeMeaning == "For Referring Provider")
    }
    
    @Test("Set document title - For Surgery")
    func testSetDocumentTitleForSurgery() throws {
        let document = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.forSurgery)
            .addKeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3")
            .build()
        
        #expect(document.documentTitle?.codeValue == "113003")
        #expect(document.documentTitle?.codeMeaning == "For Surgery")
    }
    
    @Test("Set document title - Quality Issue")
    func testSetDocumentTitleQualityIssue() throws {
        let document = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.qualityIssue)
            .addKeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3")
            .build()
        
        #expect(document.documentTitle?.codeValue == "113010")
        #expect(document.documentTitle?.codeMeaning == "Quality Issue")
    }
    
    @Test("Set document title - Of Interest (default)")
    func testSetDocumentTitleOfInterest() throws {
        let document = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.ofInterest)
            .addKeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3")
            .build()
        
        #expect(document.documentTitle?.codeValue == "113000")
        #expect(document.documentTitle?.codeMeaning == "Of Interest")
    }
    
    @Test("Set document title - Best In Set")
    func testSetDocumentTitleBestInSet() throws {
        let document = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.bestInSet)
            .addKeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3")
            .build()
        
        #expect(document.documentTitle?.codeValue == "113013")   // CID 7010
        #expect(document.documentTitle?.codeMeaning == "Best In Set")
    }
    
    @Test("Set document title - For Printing")
    func testSetDocumentTitleForPrinting() throws {
        let document = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.forPrinting)
            .addKeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3")
            .build()
        
        #expect(document.documentTitle?.codeValue == "113018")
        #expect(document.documentTitle?.codeMeaning == "For Printing")
    }
    
    @Test("Set document title - For Report Attachment")
    func testSetDocumentTitleForReportAttachment() throws {
        let document = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.forReportAttachment)
            .addKeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3")
            .build()
        
        #expect(document.documentTitle?.codeValue == "113020")
        #expect(document.documentTitle?.codeMeaning == "For Report Attachment")
    }
    
    @Test("Set document title - Custom")
    func testSetDocumentTitleCustom() throws {
        let customConcept = CodedConcept(
            codeValue: "99999",
            codingSchemeDesignator: "CUSTOM",
            codeMeaning: "Custom Purpose"
        )
        
        let document = try KeyObjectSelectionBuilder()
            .withDocumentTitle(customConcept)
            .addKeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3")
            .build()
        
        #expect(document.documentTitle?.codeValue == "99999")
        #expect(document.documentTitle?.codeMeaning == "Custom Purpose")
    }
    
    @Test("Default document title when not set")
    func testDefaultDocumentTitle() throws {
        let document = try KeyObjectSelectionBuilder()
            .addKeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3")
            .build()
        
        // Should default to "Of Interest"
        #expect(document.documentTitle?.codeValue == "113000")
        #expect(document.documentTitle?.codeMeaning == "Of Interest")
    }
    
    // MARK: - Key Object Management Tests
    
    @Test("Add single key object")
    func testAddSingleKeyObject() throws {
        let document = try KeyObjectSelectionBuilder()
            .addKeyObject(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: "1.2.3.4.5"
            )
            .build()
        
        #expect(document.rootContent.contentItems.count > 0)
    }
    
    @Test("Add key object with description")
    func testAddKeyObjectWithDescription() throws {
        let document = try KeyObjectSelectionBuilder()
            .addKeyObject(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: "1.2.3.4.5",
                description: "Excellent demonstration of pathology"
            )
            .build()
        
        // Should have both text description and image reference
        #expect(document.rootContent.contentItems.count == 2)
        
        // First item should be text description
        let firstItem = document.rootContent.contentItems.first
        #expect(firstItem?.valueType == .text)
    }
    
    @Test("Add key object with frame numbers")
    func testAddKeyObjectWithFrames() throws {
        let document = try KeyObjectSelectionBuilder()
            .addKeyObject(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: "1.2.3.4.5",
                frames: [1, 3, 5]
            )
            .build()
        
        #expect(document.rootContent.contentItems.count > 0)
    }
    
    @Test("Add multiple key objects")
    func testAddMultipleKeyObjects() throws {
        let document = try KeyObjectSelectionBuilder()
            .addKeyObject(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: "1.2.3.4.5"
            )
            .addKeyObject(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.4",
                sopInstanceUID: "1.2.3.4.6"
            )
            .addKeyObject(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: "1.2.3.4.7",
                description: "Important finding"
            )
            .build()
        
        // Should have 4 items: 2 plain references + 1 with description (text + ref = 2)
        #expect(document.rootContent.contentItems.count == 4)
    }
    
    @Test("Add key objects using array")
    func testAddKeyObjectsArray() throws {
        let objects = [
            KeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.4.5"),
            KeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.4", sopInstanceUID: "1.2.3.4.6"),
            KeyObject(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.4.7")
        ]
        
        let document = try KeyObjectSelectionBuilder()
            .addKeyObjects(objects)
            .build()
        
        #expect(document.rootContent.contentItems.count == 3)
    }
    
    // MARK: - Complete Document Tests
    
    @Test("Build complete teaching file document")
    func testBuildCompleteTeachingFileDocument() throws {
        let document = try KeyObjectSelectionBuilder()
            .withPatientID("PAT12345")
            .withPatientName("Teaching^Case^^^")
            .withPatientBirthDate("19750601")
            .withPatientSex("F")
            .withStudyInstanceUID("1.2.840.10008.999.1")
            .withStudyDate("20240115")
            .withStudyTime("103045")
            .withStudyDescription("CT Abdomen with Contrast")
            .withAccessionNumber("ACC2024001")
            .withSeriesInstanceUID("1.2.840.10008.999.1.1")
            .withSeriesNumber("999")
            .withSeriesDescription("Key Images for Teaching")
            .withContentDate("20240116")
            .withContentTime("090000")
            .withDocumentTitle(.forTeaching)
            .withCompletionFlag(.complete)
            .withVerificationFlag(.verified)
            .addKeyObject(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: "1.2.840.10008.999.1.1.1",
                description: "Classic presentation of hepatic lesion",
                frames: nil
            )
            .addKeyObject(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: "1.2.840.10008.999.1.1.2",
                description: "Portal venous phase showing washout"
            )
            .addKeyObject(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: "1.2.840.10008.999.1.1.3"
            )
            .build()
        
        // Verify document properties
        #expect(document.sopClassUID == SRDocumentType.keyObjectSelectionDocument.sopClassUID)
        #expect(document.documentType == .keyObjectSelectionDocument)
        #expect(document.modality == "KO")   // PS3.3 C.17.6.1 Key Object Document Series: Enumerated Value KO
        #expect(document.patientID == "PAT12345")
        #expect(document.documentTitle?.codeValue == "113004")
        #expect(document.completionFlag == .complete)
        #expect(document.verificationFlag == .verified)
        
        // Should have 5 content items: 2 descriptions + 3 references
        #expect(document.rootContent.contentItems.count == 5)
    }
    
    @Test("Build quality control document")
    func testBuildQualityControlDocument() throws {
        let document = try KeyObjectSelectionBuilder()
            .withPatientID("QC001")
            .withPatientName("Quality^Control")
            .withStudyDate("20240115")
            .withDocumentTitle(.rejectedForQuality)
            .addKeyObject(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.1",
                sopInstanceUID: "1.2.3.4.5.6",
                description: "Motion artifact - reject"
            )
            .addKeyObject(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.1",
                sopInstanceUID: "1.2.3.4.5.7",
                description: "Incorrect positioning"
            )
            .build()
        
        #expect(document.documentTitle?.codeValue == "113001")
        #expect(document.documentTitle?.codeMeaning == "Rejected for Quality Reasons")
        #expect(document.rootContent.contentItems.count == 4) // 2 descriptions + 2 references
    }
    
    @Test("Build referral document")
    func testBuildReferralDocument() throws {
        let document = try KeyObjectSelectionBuilder()
            .withPatientID("REF001")
            .withPatientName("Referral^Patient")
            .withReferringPhysicianName("Smith^John^^^Dr.")
            .withDocumentTitle(.forReferringProvider)
            .addKeyObject(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: "1.2.3.4.5"
            )
            .build()
        
        #expect(document.documentTitle?.codeValue == "113002")
    }
    
    @Test("Build surgical planning document")
    func testBuildSurgicalPlanningDocument() throws {
        let document = try KeyObjectSelectionBuilder()
            .withPatientID("SURG001")
            .withPatientName("Surgery^Patient")
            .withStudyDescription("MRI Brain for surgical planning")
            .withDocumentTitle(.forSurgery)
            .addKeyObject(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.4",
                sopInstanceUID: "1.2.3.4.5",
                description: "Tumor boundaries on T1"
            )
            .addKeyObject(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.4",
                sopInstanceUID: "1.2.3.4.6",
                description: "Vascular anatomy"
            )
            .build()
        
        #expect(document.documentTitle?.codeValue == "113003")
    }
    
    // MARK: - KeyObject Structure Tests
    
    @Test("KeyObject equality")
    func testKeyObjectEquality() {
        let obj1 = KeyObject(
            sopClassUID: "1.2.3",
            sopInstanceUID: "1.2.3.4",
            description: "Test",
            frames: [1, 2]
        )
        
        let obj2 = KeyObject(
            sopClassUID: "1.2.3",
            sopInstanceUID: "1.2.3.4",
            description: "Test",
            frames: [1, 2]
        )
        
        let obj3 = KeyObject(
            sopClassUID: "1.2.3",
            sopInstanceUID: "1.2.3.5",
            description: "Test",
            frames: [1, 2]
        )
        
        #expect(obj1 == obj2)
        #expect(obj1 != obj3)
    }
    
    @Test("KeyObject without optional fields")
    func testKeyObjectWithoutOptionalFields() {
        let obj = KeyObject(
            sopClassUID: "1.2.3",
            sopInstanceUID: "1.2.3.4"
        )
        
        #expect(obj.description == nil)
        #expect(obj.frames == nil)
    }
    
    // MARK: - DocumentTitle Concept Tests
    
    @Test("DocumentTitle enum concept mapping")
    func testDocumentTitleConceptMapping() {
        #expect(DocumentTitle.ofInterest.concept.codeValue == "113000")
        #expect(DocumentTitle.rejectedForQuality.concept.codeValue == "113001")
        #expect(DocumentTitle.forReferringProvider.concept.codeValue == "113002")
        #expect(DocumentTitle.forSurgery.concept.codeValue == "113003")
        #expect(DocumentTitle.forTeaching.concept.codeValue == "113004")
        #expect(DocumentTitle.qualityIssue.concept.codeValue == "113010")
        // PS3.16 CID 7010
        #expect(DocumentTitle.bestInSet.concept.codeValue == "113013")
        #expect(DocumentTitle.forPrinting.concept.codeValue == "113018")
        #expect(DocumentTitle.forReportAttachment.concept.codeValue == "113020")
        
        // All should use DCM coding scheme
        #expect(DocumentTitle.ofInterest.concept.codingSchemeDesignator == "DCM")
        #expect(DocumentTitle.forTeaching.concept.codingSchemeDesignator == "DCM")
    }
    
    @Test("DocumentTitle custom concept")
    func testDocumentTitleCustomConcept() {
        let customConcept = CodedConcept(
            codeValue: "CUSTOM001",
            codingSchemeDesignator: "LOCAL",
            codeMeaning: "Local Custom Code"
        )
        
        let title = DocumentTitle.custom(customConcept)
        #expect(title.concept.codeValue == "CUSTOM001")
        #expect(title.concept.codingSchemeDesignator == "LOCAL")
        #expect(title.concept.codeMeaning == "Local Custom Code")
    }
}
