import Testing
import Foundation
import DICOMCore
@testable import DICOMKit

// MARK: - BasicTextSRBuilder Tests

@Suite("BasicTextSRBuilder Tests")
struct BasicTextSRBuilderTests {
    
    // MARK: - Basic Builder Tests
    
    @Test("Builder initialization with default values")
    func testBuilderInitialization() {
        let builder = BasicTextSRBuilder()
        
        #expect(builder.validateOnBuild == true)
        #expect(builder.completionFlag == .partial)
        #expect(builder.verificationFlag == .unverified)
        #expect(builder.contentItems.isEmpty)
    }
    
    @Test("Builder initialization with validation disabled")
    func testBuilderWithValidationDisabled() {
        let builder = BasicTextSRBuilder(validateOnBuild: false)
        #expect(builder.validateOnBuild == false)
    }
    
    @Test("Build minimal document")
    func testBuildMinimalDocument() throws {
        let document = try BasicTextSRBuilder()
            .build()
        
        #expect(!document.sopInstanceUID.isEmpty)
        #expect(document.sopClassUID == SRDocumentType.basicTextSR.sopClassUID)
        #expect(document.documentType == .basicTextSR)
        #expect(document.modality == "SR")
    }
    
    // MARK: - Document Identification Tests
    
    @Test("Set SOP Instance UID")
    func testSetSOPInstanceUID() throws {
        let uid = "1.2.3.4.5.6.7.8.9"
        let document = try BasicTextSRBuilder()
            .withSOPInstanceUID(uid)
            .build()
        
        #expect(document.sopInstanceUID == uid)
    }
    
    @Test("Set Study Instance UID")
    func testSetStudyInstanceUID() throws {
        let uid = "1.2.3.4.5.6.7.8.9.10"
        let document = try BasicTextSRBuilder()
            .withStudyInstanceUID(uid)
            .build()
        
        #expect(document.studyInstanceUID == uid)
    }
    
    @Test("Set Series Instance UID")
    func testSetSeriesInstanceUID() throws {
        let uid = "1.2.3.4.5.6.7.8.9.11"
        let document = try BasicTextSRBuilder()
            .withSeriesInstanceUID(uid)
            .build()
        
        #expect(document.seriesInstanceUID == uid)
    }
    
    @Test("Set Instance Number")
    func testSetInstanceNumber() throws {
        let document = try BasicTextSRBuilder()
            .withInstanceNumber("1")
            .build()
        
        #expect(document.instanceNumber == "1")
    }
    
    // MARK: - Patient Information Tests
    
    @Test("Set patient information")
    func testSetPatientInformation() throws {
        let document = try BasicTextSRBuilder()
            .withPatientID("PAT001")
            .withPatientName("Doe^John")
            .withPatientBirthDate("19800115")
            .withPatientSex("M")
            .build()
        
        #expect(document.patientID == "PAT001")
        #expect(document.patientName == "Doe^John")
    }
    
    // MARK: - Study Information Tests
    
    @Test("Set study information")
    func testSetStudyInformation() throws {
        let document = try BasicTextSRBuilder()
            .withStudyDate("20240115")
            .withStudyTime("143022")
            .withStudyDescription("CT Chest")
            .withAccessionNumber("ACC001")
            .withReferringPhysicianName("Smith^Jane")
            .build()
        
        #expect(document.studyDate == "20240115")
        #expect(document.studyTime == "143022")
        #expect(document.accessionNumber == "ACC001")
    }
    
    // MARK: - Series Information Tests
    
    @Test("Set series information")
    func testSetSeriesInformation() throws {
        let document = try BasicTextSRBuilder()
            .withSeriesNumber("1")
            .withSeriesDescription("CT Report")
            .build()
        
        #expect(document.seriesNumber == "1")
    }
    
    // MARK: - Document Information Tests
    
    @Test("Set document title with coded concept")
    func testSetDocumentTitleCodedConcept() throws {
        let title = CodedConcept(
            codeValue: "126001",
            codingSchemeDesignator: "DCM",
            codeMeaning: "Imaging Report"
        )
        
        let document = try BasicTextSRBuilder()
            .withDocumentTitle(title)
            .build()
        
        #expect(document.documentTitle == title)
    }
    
    @Test("Set document title with string")
    func testSetDocumentTitleString() throws {
        let document = try BasicTextSRBuilder()
            .withDocumentTitle("Radiology Report")
            .build()
        
        #expect(document.documentTitle?.codeMeaning == "Radiology Report")
        #expect(document.documentTitle?.codeValue == "121060")
    }
    
    @Test("Set document flags")
    func testSetDocumentFlags() throws {
        let document = try BasicTextSRBuilder()
            .withCompletionFlag(.complete)
            .withVerificationFlag(.verified)
            .withPreliminaryFlag(.final)
            .build()
        
        #expect(document.completionFlag == .complete)
        #expect(document.verificationFlag == .verified)
        #expect(document.preliminaryFlag == .final)
    }
    
    @Test("Set content date and time")
    func testSetContentDateTime() throws {
        let document = try BasicTextSRBuilder()
            .withContentDate("20240115")
            .withContentTime("143022")
            .build()
        
        #expect(document.contentDate == "20240115")
        #expect(document.contentTime == "143022")
    }
    
    // MARK: - Content Item Addition Tests
    
    @Test("Add text content item")
    func testAddTextContent() throws {
        let document = try BasicTextSRBuilder()
            .addText("This is a test finding.")
            .build()
        
        #expect(document.rootContent.contentItems.count == 1)
        let textItem = document.rootContent.contentItems.first?.asText
        #expect(textItem?.textValue == "This is a test finding.")
    }
    
    @Test("Add text with concept name")
    func testAddTextWithConceptName() throws {
        let conceptName = CodedConcept(
            codeValue: "121070",
            codingSchemeDesignator: "DCM",
            codeMeaning: "Finding"
        )
        
        let document = try BasicTextSRBuilder()
            .addText("Normal appearance", conceptName: conceptName)
            .build()
        
        let textItem = document.rootContent.contentItems.first?.asText
        #expect(textItem?.textValue == "Normal appearance")
        #expect(textItem?.conceptName == conceptName)
    }
    
    @Test("Add labeled text")
    func testAddLabeledText() throws {
        let document = try BasicTextSRBuilder()
            .addLabeledText(label: "Comment", value: "No acute findings")
            .build()
        
        let textItem = document.rootContent.contentItems.first?.asText
        #expect(textItem?.textValue == "No acute findings")
        #expect(textItem?.conceptName?.codeMeaning == "Comment")
    }
    
    @Test("Add section with string title")
    func testAddSectionWithStringTitle() throws {
        let document = try BasicTextSRBuilder()
            .addSection("Findings") {
                SectionContent.text("Normal chest appearance")
            }
            .build()
        
        #expect(document.rootContent.contentItems.count == 1)
        let section = document.rootContent.contentItems.first?.asContainer
        #expect(section != nil)
        #expect(section?.conceptName?.codeMeaning == "Findings")
        #expect(section?.contentItems.count == 1)
    }
    
    @Test("Add section with coded concept title")
    func testAddSectionWithCodedTitle() throws {
        let document = try BasicTextSRBuilder()
            .addSection(CodedConcept.findings) {
                SectionContent.text("No acute findings")
            }
            .build()
        
        let section = document.rootContent.contentItems.first?.asContainer
        #expect(section?.conceptName == CodedConcept.findings)
    }
    
    @Test("Add nested sections")
    func testAddNestedSections() throws {
        let document = try BasicTextSRBuilder()
            .addSection("Findings") {
                SectionContent.subsection(title: "Lungs", items: [
                    SectionContent.text("Clear bilaterally")
                ])
                SectionContent.subsection(title: "Heart", items: [
                    SectionContent.text("Normal size and configuration")
                ])
            }
            .build()
        
        let mainSection = document.rootContent.contentItems.first?.asContainer
        #expect(mainSection?.contentItems.count == 2)
        
        let lungsSection = mainSection?.contentItems.first?.asContainer
        #expect(lungsSection?.conceptName?.codeMeaning == "Lungs")
        
        let heartSection = mainSection?.contentItems.last?.asContainer
        #expect(heartSection?.conceptName?.codeMeaning == "Heart")
    }
    
    @Test("Add code content")
    func testAddCodeContent() throws {
        let value = CodedConcept(
            codeValue: "112224",
            codingSchemeDesignator: "DCM",
            codeMeaning: "Normal"
        )
        
        let document = try BasicTextSRBuilder()
            .addCode(conceptName: CodedConcept.findings, value: value)
            .build()
        
        let codeItem = document.rootContent.contentItems.first?.asCode
        #expect(codeItem?.conceptCode == value)
    }
    
    @Test("Add person name content")
    func testAddPersonNameContent() throws {
        let document = try BasicTextSRBuilder()
            .addPersonName(name: "Smith^Jane^Dr")
            .build()
        
        let pnameItem = document.rootContent.contentItems.first?.asPersonName
        #expect(pnameItem?.personName == "Smith^Jane^Dr")
    }
    
    @Test("Add date content")
    func testAddDateContent() throws {
        let document = try BasicTextSRBuilder()
            .addDate(date: "20240115")
            .build()
        
        let dateItem = document.rootContent.contentItems.first?.asDate
        #expect(dateItem?.dateValue == "20240115")
    }
    
    @Test("Add time content")
    func testAddTimeContent() throws {
        let document = try BasicTextSRBuilder()
            .addTime(time: "143022")
            .build()
        
        let timeItem = document.rootContent.contentItems.first?.asTime
        #expect(timeItem?.timeValue == "143022")
    }
    
    @Test("Add datetime content")
    func testAddDateTimeContent() throws {
        let document = try BasicTextSRBuilder()
            .addDateTime(datetime: "20240115143022")
            .build()
        
        let dtItem = document.rootContent.contentItems.first?.asDateTime
        #expect(dtItem?.dateTimeValue == "20240115143022")
    }
    
    @Test("Add UID reference content")
    func testAddUIDRefContent() throws {
        let uid = "1.2.3.4.5.6.7"
        let document = try BasicTextSRBuilder()
            .addUIDRef(uid: uid)
            .build()
        
        let uidItem = document.rootContent.contentItems.first?.asUIDRef
        #expect(uidItem?.uidValue == uid)
    }
    
    @Test("Add image reference content")
    func testAddImageReferenceContent() throws {
        let document = try BasicTextSRBuilder()
            .addImageReference(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: "1.2.3.4.5.6.7.8"
            )
            .build()
        
        let imageItem = document.rootContent.contentItems.first?.asImage
        #expect(imageItem?.imageReference.sopReference.sopClassUID == "1.2.840.10008.5.1.4.1.1.2")
        #expect(imageItem?.imageReference.sopReference.sopInstanceUID == "1.2.3.4.5.6.7.8")
    }
    
    // MARK: - Common Section Helpers Tests
    
    @Test("Add findings section helper")
    func testAddFindingsHelper() throws {
        let document = try BasicTextSRBuilder()
            .addFindings("Normal chest radiograph")
            .build()
        
        let section = document.rootContent.contentItems.first?.asContainer
        #expect(section?.conceptName == CodedConcept.findings)
        
        let textItem = section?.contentItems.first?.asText
        #expect(textItem?.textValue == "Normal chest radiograph")
    }
    
    @Test("Add impression section helper")
    func testAddImpressionHelper() throws {
        let document = try BasicTextSRBuilder()
            .addImpression("No acute findings")
            .build()
        
        let section = document.rootContent.contentItems.first?.asContainer
        #expect(section?.conceptName == CodedConcept.impression)
    }
    
    @Test("Add clinical history section helper")
    func testAddClinicalHistoryHelper() throws {
        let document = try BasicTextSRBuilder()
            .addClinicalHistory("Cough and shortness of breath")
            .build()
        
        let section = document.rootContent.contentItems.first?.asContainer
        #expect(section?.conceptName == CodedConcept.clinicalHistory)
    }
    
    @Test("Add conclusion section helper")
    func testAddConclusionHelper() throws {
        let document = try BasicTextSRBuilder()
            .addConclusion("Normal examination")
            .build()
        
        let section = document.rootContent.contentItems.first?.asContainer
        #expect(section?.conceptName == CodedConcept.conclusion)
    }
    
    @Test("Add recommendation section helper")
    func testAddRecommendationHelper() throws {
        let document = try BasicTextSRBuilder()
            .addRecommendation("Follow-up in 6 months")
            .build()
        
        let section = document.rootContent.contentItems.first?.asContainer
        #expect(section?.conceptName == CodedConcept.recommendation)
    }
    
    @Test("Add procedure description section helper")
    func testAddProcedureDescriptionHelper() throws {
        let document = try BasicTextSRBuilder()
            .addProcedureDescription("CT chest without contrast")
            .build()
        
        let section = document.rootContent.contentItems.first?.asContainer
        #expect(section?.conceptName == CodedConcept.procedureDescription)
    }
    
    @Test("Add comparison section helper")
    func testAddComparisonHelper() throws {
        let document = try BasicTextSRBuilder()
            .addComparison("Prior chest X-ray from 2023-01-01")
            .build()
        
        let section = document.rootContent.contentItems.first?.asContainer
        #expect(section?.conceptName == CodedConcept.comparison)
    }
    
    // MARK: - Complete Report Tests
    
    @Test("Build complete radiology report")
    func testBuildCompleteRadiologyReport() throws {
        let document = try BasicTextSRBuilder()
            .withPatientID("PAT12345")
            .withPatientName("Doe^John")
            .withStudyDate("20240115")
            .withStudyDescription("CT Chest")
            .withAccessionNumber("ACC-2024-001")
            .withDocumentTitle("CT Chest Report")
            .withCompletionFlag(.complete)
            .withVerificationFlag(.verified)
            .addClinicalHistory("Chronic cough for 3 weeks")
            .addComparison("CT Chest from 2023-06-15")
            .addFindings("The lungs are clear bilaterally without evidence of consolidation, mass, or nodule. Heart size is normal. No pleural effusion.")
            .addImpression("Normal CT chest examination.")
            .addRecommendation("No follow-up imaging required.")
            .build()
        
        #expect(document.documentType == .basicTextSR)
        #expect(document.patientID == "PAT12345")
        #expect(document.patientName == "Doe^John")
        #expect(document.documentTitle?.codeMeaning == "CT Chest Report")
        #expect(document.completionFlag == .complete)
        #expect(document.verificationFlag == .verified)
        #expect(document.rootContent.contentItems.count == 5) // 5 sections
    }
    
    // MARK: - Validation Tests
    
    @Test("Validate rejects numeric content")
    func testValidateRejectsNumericContent() throws {
        // Create a numeric content item (not allowed in Basic Text SR)
        let numericItem = AnyContentItem(NumericContentItem(
            conceptName: nil,
            value: 42.5,
            units: nil,
            relationshipType: .contains
        ))
        
        let builder = BasicTextSRBuilder()
            .addItem(numericItem)
        
        #expect(throws: BasicTextSRBuilder.BuildError.self) {
            try builder.build()
        }
    }
    
    @Test("Validate rejects spatial coordinates")
    func testValidateRejectsSpatialCoordinates() throws {
        // Create a SCOORD content item (not allowed in Basic Text SR)
        let scoordItem = AnyContentItem(SpatialCoordinatesContentItem(
            conceptName: nil,
            graphicType: .point,
            graphicData: [100.0, 200.0],
            relationshipType: .contains
        ))
        
        let builder = BasicTextSRBuilder()
            .addItem(scoordItem)
        
        #expect(throws: BasicTextSRBuilder.BuildError.self) {
            try builder.build()
        }
    }
    
    @Test("Validate allows text content")
    func testValidateAllowsTextContent() throws {
        let document = try BasicTextSRBuilder()
            .addText("This is allowed in Basic Text SR")
            .build()
        
        #expect(document.rootContent.contentItems.count == 1)
    }
    
    @Test("Validate allows code content")
    func testValidateAllowsCodeContent() throws {
        let document = try BasicTextSRBuilder()
            .addCode(
                conceptName: nil,
                value: CodedConcept(
                    codeValue: "112224",
                    codingSchemeDesignator: "DCM",
                    codeMeaning: "Normal"
                )
            )
            .build()
        
        #expect(document.rootContent.contentItems.count == 1)
    }
    
    @Test("Validation can be disabled")
    func testValidationCanBeDisabled() throws {
        // Create a numeric content item (not allowed in Basic Text SR)
        let numericItem = AnyContentItem(NumericContentItem(
            conceptName: nil,
            value: 42.5,
            units: nil,
            relationshipType: .contains
        ))
        
        // With validation disabled, it should build without error
        let document = try BasicTextSRBuilder(validateOnBuild: false)
            .addItem(numericItem)
            .build()
        
        #expect(document.rootContent.contentItems.count == 1)
    }
    
    // MARK: - Fluent Builder Pattern Tests
    
    @Test("Builder is immutable with fluent pattern")
    func testBuilderImmutability() {
        let builder1 = BasicTextSRBuilder()
        let builder2 = builder1.withPatientID("PAT001")
        
        // Original builder should not be modified
        #expect(builder1.patientID == nil)
        #expect(builder2.patientID == "PAT001")
    }
    
    @Test("Builder chain maintains all settings")
    func testBuilderChainMaintainsSettings() throws {
        let document = try BasicTextSRBuilder()
            .withPatientID("PAT001")
            .withPatientName("Doe^John")
            .withStudyDate("20240115")
            .addText("Finding 1")
            .addText("Finding 2")
            .build()
        
        #expect(document.patientID == "PAT001")
        #expect(document.patientName == "Doe^John")
        #expect(document.studyDate == "20240115")
        #expect(document.rootContent.contentItems.count == 2)
    }
    
    // MARK: - SectionContent Helper Tests
    
    @Test("SectionContent text helper")
    func testSectionContentTextHelper() {
        let item = SectionContent.text("Test text")
        #expect(item.asText?.textValue == "Test text")
    }
    
    @Test("SectionContent labeled text helper")
    func testSectionContentLabeledTextHelper() {
        let item = SectionContent.labeledText(label: "Label", value: "Value")
        #expect(item.asText?.textValue == "Value")
        #expect(item.asText?.conceptName?.codeMeaning == "Label")
    }
    
    @Test("SectionContent code helper")
    func testSectionContentCodeHelper() {
        let code = CodedConcept(codeValue: "123", codingSchemeDesignator: "DCM", codeMeaning: "Test")
        let item = SectionContent.code(conceptName: nil, value: code)
        #expect(item.asCode?.conceptCode == code)
    }
    
    @Test("SectionContent person name helper")
    func testSectionContentPersonNameHelper() {
        let item = SectionContent.personName(name: "Smith^John")
        #expect(item.asPersonName?.personName == "Smith^John")
    }
    
    @Test("SectionContent date helper")
    func testSectionContentDateHelper() {
        let item = SectionContent.date(date: "20240115")
        #expect(item.asDate?.dateValue == "20240115")
    }
    
    @Test("SectionContent subsection helper with string title")
    func testSectionContentSubsectionStringHelper() {
        let item = SectionContent.subsection(title: "Test Section", items: [
            SectionContent.text("Test content")
        ])
        #expect(item.asContainer?.conceptName?.codeMeaning == "Test Section")
        #expect(item.asContainer?.contentItems.count == 1)
    }
    
    @Test("SectionContent subsection helper with coded title")
    func testSectionContentSubsectionCodedHelper() {
        let title = CodedConcept(codeValue: "121070", codingSchemeDesignator: "DCM", codeMeaning: "Findings")
        let item = SectionContent.subsection(title: title, items: [
            SectionContent.text("Test content")
        ])
        #expect(item.asContainer?.conceptName == title)
    }
    
    // MARK: - CodedConcept Extension Tests
    
    @Test("CodedConcept section heading helper")
    func testCodedConceptSectionHeadingHelper() {
        let concept = CodedConcept.sectionHeading("Custom Section")
        #expect(concept.codeValue == "121070")
        #expect(concept.codingSchemeDesignator == "DCM")
        #expect(concept.codeMeaning == "Custom Section")
    }
    
    @Test("CodedConcept document title helper")
    func testCodedConceptDocumentTitleHelper() {
        let concept = CodedConcept.documentTitle("My Report")
        #expect(concept.codeValue == "121060")
        #expect(concept.codingSchemeDesignator == "DCM")
        #expect(concept.codeMeaning == "My Report")
    }
    
    @Test("CodedConcept text label helper")
    func testCodedConceptTextLabelHelper() {
        let concept = CodedConcept.textLabel("Comment")
        #expect(concept.codeValue == "121050")
        #expect(concept.codingSchemeDesignator == "DCM")
        #expect(concept.codeMeaning == "Comment")
    }
    
    @Test("CodedConcept common section concepts")
    func testCodedConceptCommonSections() {
        #expect(CodedConcept.findings.codeMeaning == "Findings")
        #expect(CodedConcept.impression.codeMeaning == "Impression")
        #expect(CodedConcept.clinicalHistory.codeMeaning == "History")
        #expect(CodedConcept.conclusion.codeMeaning == "Conclusion")
        #expect(CodedConcept.recommendation.codeMeaning == "Recommendations")   // (121074, DCM) in Table D-1
        #expect(CodedConcept.procedureDescription.codeMeaning == "Procedure Description")
        #expect(CodedConcept.comparison.codeMeaning == "Comparison to previous studies")
    }

    @Test("Comparison section concept is (111424, DCM) per PS3.16 2026a CID 6052 / TID 3318 row 1")
    func testComparisonConceptPinnedToStandard() {
        // PS3.16 2026a Table D-1 / CID 6052 "Breast Imaging Report Section Title":
        //   DCM | 111424 | Comparison to previous studies
        // 121071 (the former value) is "Finding" in Table D-1.
        #expect(CodedConcept.comparison.codeValue == "111424")
        #expect(CodedConcept.comparison.codingSchemeDesignator == "DCM")
        #expect(CodedConcept.comparison.codeMeaning == "Comparison to previous studies")
        #expect(CodedConcept.comparison.codeValue != "121071")
    }
}
