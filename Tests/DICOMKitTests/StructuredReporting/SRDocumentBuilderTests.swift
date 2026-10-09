import Testing
import Foundation
import DICOMCore
@testable import DICOMKit

// MARK: - SRDocumentBuilder Tests

@Suite("SRDocumentBuilder Tests")
struct SRDocumentBuilderTests {
    
    // MARK: - Basic Builder Tests
    
    @Test("Builder initialization with default values")
    func testBuilderInitialization() {
        let builder = SRDocumentBuilder()
        
        #expect(builder.documentType == .comprehensiveSR)
        #expect(builder.validateOnBuild == true)
        #expect(builder.completionFlag == .partial)
        #expect(builder.verificationFlag == .unverified)
        #expect(builder.modality == "SR")
        #expect(builder.contentItems.isEmpty)
    }
    
    @Test("Builder initialization with custom document type")
    func testBuilderWithDocumentType() {
        let builder = SRDocumentBuilder(documentType: .basicTextSR)
        #expect(builder.documentType == .basicTextSR)
        
        let enhancedBuilder = SRDocumentBuilder(documentType: .enhancedSR)
        #expect(enhancedBuilder.documentType == .enhancedSR)
    }
    
    @Test("Build minimal document")
    func testBuildMinimalDocument() throws {
        let document = try SRDocumentBuilder()
            .build()
        
        #expect(!document.sopInstanceUID.isEmpty)
        #expect(document.sopClassUID == SRDocumentType.comprehensiveSR.sopClassUID)
        #expect(document.documentType == .comprehensiveSR)
    }
    
    // MARK: - Document Identification Tests
    
    @Test("Set SOP Instance UID")
    func testSetSOPInstanceUID() throws {
        let uid = "1.2.3.4.5.6.7.8.9"
        let document = try SRDocumentBuilder()
            .withSOPInstanceUID(uid)
            .build()
        
        #expect(document.sopInstanceUID == uid)
    }
    
    @Test("Set Study Instance UID")
    func testSetStudyInstanceUID() throws {
        let uid = "1.2.3.4.5.6.7.8.9.10"
        let document = try SRDocumentBuilder()
            .withStudyInstanceUID(uid)
            .build()
        
        #expect(document.studyInstanceUID == uid)
    }
    
    @Test("Set Series Instance UID")
    func testSetSeriesInstanceUID() throws {
        let uid = "1.2.3.4.5.6.7.8.9.11"
        let document = try SRDocumentBuilder()
            .withSeriesInstanceUID(uid)
            .build()
        
        #expect(document.seriesInstanceUID == uid)
    }
    
    // MARK: - Patient Information Tests
    
    @Test("Set patient information")
    func testSetPatientInformation() throws {
        let document = try SRDocumentBuilder()
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
        let document = try SRDocumentBuilder()
            .withStudyDate("20240115")
            .withStudyTime("143022")
            .withStudyDescription("CT Chest")
            .withAccessionNumber("ACC001")
            .build()
        
        #expect(document.studyDate == "20240115")
        #expect(document.studyTime == "143022")
        #expect(document.accessionNumber == "ACC001")
    }
    
    // MARK: - Series Information Tests
    
    @Test("Set series information")
    func testSetSeriesInformation() throws {
        let document = try SRDocumentBuilder()
            .withSeriesNumber("1")
            .withSeriesDescription("CT Report")
            .withModality("SR")
            .build()
        
        #expect(document.seriesNumber == "1")
        #expect(document.modality == "SR")
    }
    
    // MARK: - Document Information Tests
    
    @Test("Set document information")
    func testSetDocumentInformation() throws {
        let title = CodedConcept(
            codeValue: "126001",
            codingSchemeDesignator: "DCM",
            codeMeaning: "Imaging Report"
        )
        
        let document = try SRDocumentBuilder()
            .withContentDate("20240115")
            .withContentTime("143022")
            .withDocumentTitle(title)
            .withCompletionFlag(.complete)
            .withVerificationFlag(.verified)
            .withPreliminaryFlag(.final)
            .build()
        
        #expect(document.contentDate == "20240115")
        #expect(document.contentTime == "143022")
        #expect(document.documentTitle == title)
        #expect(document.completionFlag == .complete)
        #expect(document.verificationFlag == .verified)
        #expect(document.preliminaryFlag == .final)
    }
    
    // MARK: - Content Item Addition Tests
    
    @Test("Add text content item")
    func testAddTextContentItem() throws {
        let conceptName = CodedConcept(
            codeValue: "121071",
            codingSchemeDesignator: "DCM",
            codeMeaning: "Finding"
        )
        
        let document = try SRDocumentBuilder()
            .addText(conceptName: conceptName, value: "Normal appearance")
            .build()
        
        #expect(document.contentItemCount == 1)
        let textItems = document.findTextItems()
        #expect(textItems.count == 1)
        #expect(textItems.first?.textValue == "Normal appearance")
        #expect(textItems.first?.conceptName == conceptName)
    }
    
    @Test("Add code content item")
    func testAddCodeContentItem() throws {
        let conceptName = CodedConcept.finding
        let codeValue = CodedConcept(
            codeValue: "111001",
            codingSchemeDesignator: "DCM",
            codeMeaning: "Present"
        )
        
        let document = try SRDocumentBuilder()
            .addCode(conceptName: conceptName, value: codeValue)
            .build()
        
        let codeItems = document.findCodeItems()
        #expect(codeItems.count == 1)
        #expect(codeItems.first?.conceptCode == codeValue)
    }
    
    @Test("Add numeric content item")
    func testAddNumericContentItem() throws {
        let conceptName = CodedConcept.measurement
        let units = CodedConcept.unitMillimeter
        
        let document = try SRDocumentBuilder()
            .addNumeric(conceptName: conceptName, value: 42.5, units: units)
            .build()
        
        let numericItems = document.findNumericItems()
        #expect(numericItems.count == 1)
        #expect(numericItems.first?.value == 42.5)
        #expect(numericItems.first?.measurementUnits == units)
    }
    
    @Test("Add date content item")
    func testAddDateContentItem() throws {
        let document = try SRDocumentBuilder()
            .addDate(value: "20240115")
            .build()
        
        let dateItems = document.findContentItems(ofType: .date)
        #expect(dateItems.count == 1)
    }
    
    @Test("Add time content item")
    func testAddTimeContentItem() throws {
        let document = try SRDocumentBuilder()
            .addTime(value: "143022")
            .build()
        
        let timeItems = document.findContentItems(ofType: .time)
        #expect(timeItems.count == 1)
    }
    
    @Test("Add datetime content item")
    func testAddDateTimeContentItem() throws {
        let document = try SRDocumentBuilder()
            .addDateTime(value: "20240115143022")
            .build()
        
        let dateTimeItems = document.findContentItems(ofType: .datetime)
        #expect(dateTimeItems.count == 1)
    }
    
    @Test("Add person name content item")
    func testAddPersonNameContentItem() throws {
        let document = try SRDocumentBuilder()
            .addPersonName(value: "Smith^John")
            .build()
        
        let pnameItems = document.findContentItems(ofType: .pname)
        #expect(pnameItems.count == 1)
    }
    
    @Test("Add UID reference content item")
    func testAddUIDRefContentItem() throws {
        let uid = "1.2.3.4.5.6.7"
        let document = try SRDocumentBuilder()
            .addUIDRef(value: uid)
            .build()
        
        let uidRefItems = document.findContentItems(ofType: .uidref)
        #expect(uidRefItems.count == 1)
    }
    
    @Test("Add image reference content item")
    func testAddImageReferenceContentItem() throws {
        let document = try SRDocumentBuilder()
            .addImageReference(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: "1.2.3.4.5.6.7.8",
                frameNumbers: [1, 2, 3]
            )
            .build()
        
        let imageItems = document.findImageItems()
        #expect(imageItems.count == 1)
        #expect(imageItems.first?.imageReference.sopReference.sopClassUID == "1.2.840.10008.5.1.4.1.1.2")
        #expect(imageItems.first?.imageReference.frameNumbers == [1, 2, 3])
    }
    
    @Test("Add composite reference content item")
    func testAddCompositeReferenceContentItem() throws {
        let document = try SRDocumentBuilder()
            .addCompositeReference(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: "1.2.3.4.5.6.7.8"
            )
            .build()
        
        let compositeItems = document.findContentItems(ofType: .composite)
        #expect(compositeItems.count == 1)
    }
    
    @Test("Add spatial coordinates content item")
    func testAddSpatialCoordinatesContentItem() throws {
        let document = try SRDocumentBuilder()
            .addSpatialCoordinates(
                graphicType: .point,
                graphicData: [100.0, 200.0]
            )
            .build()
        
        let scoordItems = document.findSpatialCoordinateItems()
        #expect(scoordItems.count == 1)
        #expect(scoordItems.first?.graphicType == .point)
        #expect(scoordItems.first?.graphicData == [100.0, 200.0])
    }
    
    @Test("Add 3D spatial coordinates content item")
    func testAddSpatialCoordinates3DContentItem() throws {
        // SCOORD3D is a Comprehensive 3D SR value type (PS3.3 Table A.35.13-2), not Comprehensive SR
        let document = try SRDocumentBuilder(documentType: .comprehensive3DSR)
            .addSpatialCoordinates3D(
                graphicType: .point,
                graphicData: [100.0, 200.0, 50.0],
                frameOfReferenceUID: "1.2.3.4.5"
            )
            .build()
        
        let scoord3DItems = document.findContentItems(ofType: .scoord3D)
        #expect(scoord3DItems.count == 1)
    }
    
    @Test("Add temporal coordinates content item")
    func testAddTemporalCoordinatesContentItem() throws {
        let document = try SRDocumentBuilder()
            .addTemporalCoordinates(
                temporalRangeType: .point,
                samplePositions: [1, 2, 3]
            )
            .build()
        
        let tcoordItems = document.findContentItems(ofType: .tcoord)
        #expect(tcoordItems.count == 1)
    }
    
    // MARK: - Container Tests
    
    @Test("Add container with items")
    func testAddContainerWithItems() throws {
        let containerConcept = CodedConcept(
            codeValue: "121070",
            codingSchemeDesignator: "DCM",
            codeMeaning: "Findings"
        )
        
        let document = try SRDocumentBuilder()
            .addContainer(conceptName: containerConcept, items: [
                .text(value: "Finding 1"),
                .text(value: "Finding 2")
            ])
            .build()
        
        let containers = document.findContainerItems()
        #expect(containers.count == 1)
        #expect(containers.first?.contentItems.count == 2)
    }
    
    @Test("Add container with builder")
    func testAddContainerWithBuilder() throws {
        let document = try SRDocumentBuilder()
            .addContainer(conceptName: CodedConcept.finding) {
                AnyContentItem(TextContentItem(textValue: "Test finding"))
            }
            .build()
        
        let containers = document.findContainerItems()
        #expect(containers.count == 1)
    }
    
    // MARK: - Multiple Content Items
    
    @Test("Add multiple content items")
    func testAddMultipleContentItems() throws {
        let document = try SRDocumentBuilder()
            .addText(value: "Text 1")
            .addText(value: "Text 2")
            .addNumeric(value: 42.0)
            .addCode(value: CodedConcept.finding)
            .build()
        
        #expect(document.contentItemCount == 4)
        #expect(document.findTextItems().count == 2)
        #expect(document.findNumericItems().count == 1)
        #expect(document.findCodeItems().count == 1)
    }
    
    @Test("Chained builder calls")
    func testChainedBuilderCalls() throws {
        let document = try SRDocumentBuilder(documentType: .enhancedSR)
            .withPatientID("PAT001")
            .withPatientName("Doe^John")
            .withStudyDate("20240115")
            .withContentDate("20240115")
            .withCompletionFlag(.complete)
            .addText(value: "Report content")
            .build()
        
        #expect(document.patientID == "PAT001")
        #expect(document.patientName == "Doe^John")
        #expect(document.studyDate == "20240115")
        #expect(document.contentDate == "20240115")
        #expect(document.completionFlag == .complete)
        #expect(document.findTextItems().count == 1)
    }
    
    // MARK: - Validation Tests
    
    @Test("Basic Text SR allows text items")
    func testBasicTextSRAllowsText() throws {
        // Basic Text SR should allow TEXT items
        let document = try SRDocumentBuilder(documentType: .basicTextSR)
            .addText(value: "Test text")
            .build()
        
        #expect(document.findTextItems().count == 1)
    }
    
    @Test("Build validation skipped when disabled")
    func testValidationDisabled() throws {
        // Even with invalid content for Basic Text SR, should build when validation disabled
        let document = try SRDocumentBuilder(documentType: .basicTextSR, validateOnBuild: false)
            .addSpatialCoordinates(graphicType: .point, graphicData: [100, 200])
            .build()
        
        #expect(document.findSpatialCoordinateItems().count == 1)
    }
    
    @Test("Comprehensive SR allows all value types")
    func testComprehensiveSRAllowsAll() throws {
        let document = try SRDocumentBuilder(documentType: .comprehensiveSR)
            .addText(value: "Text")
            .addNumeric(value: 42.0)
            .addSpatialCoordinates(graphicType: .point, graphicData: [100, 200])
            .build()
        
        #expect(document.contentItemCount == 3)
    }
    
    // MARK: - Template Support Tests
    
    @Test("Set template identifier")
    func testSetTemplateIdentifier() throws {
        let document = try SRDocumentBuilder()
            .withTemplate(identifier: "1500", mappingResource: "DCMR")
            .build()
        
        #expect(document.rootContent.templateIdentifier == "1500")
        #expect(document.rootContent.mappingResource == "DCMR")
    }
    
    // MARK: - Continuity of Content Tests
    
    @Test("Set continuity of content")
    func testSetContinuityOfContent() throws {
        let documentSeparate = try SRDocumentBuilder()
            .withContinuityOfContent(.separate)
            .build()
        
        let documentContinuous = try SRDocumentBuilder()
            .withContinuityOfContent(.continuous)
            .build()
        
        #expect(documentSeparate.rootContent.continuityOfContent == .separate)
        #expect(documentContinuous.rootContent.continuityOfContent == .continuous)
    }
    
    // MARK: - Generated UID Tests
    
    @Test("UIDs are generated when not provided")
    func testUIDsGenerated() throws {
        let document = try SRDocumentBuilder().build()
        
        #expect(!document.sopInstanceUID.isEmpty)
        #expect(document.studyInstanceUID != nil)
        #expect(!document.studyInstanceUID!.isEmpty)
        #expect(document.seriesInstanceUID != nil)
        #expect(!document.seriesInstanceUID!.isEmpty)
    }
    
    @Test("Custom UIDs are preserved")
    func testCustomUIDsPreserved() throws {
        let sopUID = "1.2.3.4.5"
        let studyUID = "1.2.3.4.6"
        let seriesUID = "1.2.3.4.7"
        
        let document = try SRDocumentBuilder()
            .withSOPInstanceUID(sopUID)
            .withStudyInstanceUID(studyUID)
            .withSeriesInstanceUID(seriesUID)
            .build()
        
        #expect(document.sopInstanceUID == sopUID)
        #expect(document.studyInstanceUID == studyUID)
        #expect(document.seriesInstanceUID == seriesUID)
    }
}

// MARK: - SRDocumentSerializer Tests

@Suite("SRDocumentSerializer Tests")
struct SRDocumentSerializerTests {
    
    @Test("Serialize minimal document")
    func testSerializeMinimalDocument() throws {
        let document = try SRDocumentBuilder()
            .withSOPInstanceUID("1.2.3.4.5")
            .build()
        
        let dataSet = try document.toDataSet()
        
        #expect(dataSet.string(for: .sopClassUID) == SRDocumentType.comprehensiveSR.sopClassUID)
        #expect(dataSet.string(for: .sopInstanceUID) == "1.2.3.4.5")
    }
    
    @Test("Serialize document with patient information")
    func testSerializePatientInformation() throws {
        let document = try SRDocumentBuilder()
            .withPatientID("PAT001")
            .withPatientName("Doe^John")
            .build()
        
        let dataSet = try document.toDataSet()
        
        #expect(dataSet.string(for: .patientID) == "PAT001")
        #expect(dataSet.string(for: .patientName) == "Doe^John")
    }
    
    @Test("Serialize document with study information")
    func testSerializeStudyInformation() throws {
        let document = try SRDocumentBuilder()
            .withStudyInstanceUID("1.2.3.4.5.6")
            .withStudyDate("20240115")
            .withStudyTime("143022")
            .withAccessionNumber("ACC001")
            .build()
        
        let dataSet = try document.toDataSet()
        
        #expect(dataSet.string(for: .studyInstanceUID) == "1.2.3.4.5.6")
        #expect(dataSet.string(for: .studyDate) == "20240115")
        #expect(dataSet.string(for: .studyTime) == "143022")
        #expect(dataSet.string(for: .accessionNumber) == "ACC001")
    }
    
    @Test("Serialize document with series information")
    func testSerializeSeriesInformation() throws {
        let document = try SRDocumentBuilder()
            .withSeriesInstanceUID("1.2.3.4.5.6.7")
            .withSeriesNumber("1")
            .withModality("SR")
            .build()
        
        let dataSet = try document.toDataSet()
        
        #expect(dataSet.string(for: .seriesInstanceUID) == "1.2.3.4.5.6.7")
        #expect(dataSet.string(for: .seriesNumber) == "1")
        #expect(dataSet.string(for: .modality) == "SR")
    }
    
    @Test("Serialize document with flags")
    func testSerializeFlags() throws {
        let document = try SRDocumentBuilder()
            .withCompletionFlag(.complete)
            .withVerificationFlag(.verified)
            .withPreliminaryFlag(.final)
            .build()
            // VERIFIED requires the Verifying Observer Sequence (PS3.3 Table C.17-2, Type 1C)
            .withVerifyingObservers([VerifyingObserver(
                name: "Smith^Jane", organization: "Radiology", verificationDateTime: "20260929101500")])
        
        let dataSet = try document.toDataSet()
        
        #expect(dataSet.string(for: .completionFlag) == "COMPLETE")
        #expect(dataSet.string(for: .verificationFlag) == "VERIFIED")
        #expect(dataSet.string(for: .preliminaryFlag) == "FINAL")
    }
    
    @Test("Serialize document with content date/time")
    func testSerializeContentDateTime() throws {
        let document = try SRDocumentBuilder()
            .withContentDate("20240115")
            .withContentTime("143022")
            .build()
        
        let dataSet = try document.toDataSet()
        
        #expect(dataSet.string(for: .contentDate) == "20240115")
        #expect(dataSet.string(for: .contentTime) == "143022")
    }
    
    @Test("Serialize document with document title")
    func testSerializeDocumentTitle() throws {
        let title = CodedConcept(
            codeValue: "126001",
            codingSchemeDesignator: "DCM",
            codeMeaning: "Imaging Report"
        )
        
        let document = try SRDocumentBuilder()
            .withDocumentTitle(title)
            .build()
        
        let dataSet = try document.toDataSet()
        
        // Check that Concept Name Code Sequence exists
        let conceptNameSeq = dataSet.sequence(for: .conceptNameCodeSequence)
        #expect(conceptNameSeq != nil)
        #expect(conceptNameSeq?.count == 1)
        
        let firstItem = conceptNameSeq?.first
        #expect(firstItem?.string(for: .codeValue) == "126001")
        #expect(firstItem?.string(for: .codingSchemeDesignator) == "DCM")
        #expect(firstItem?.string(for: .codeMeaning) == "Imaging Report")
    }
    
    @Test("Serialize document with text content")
    func testSerializeTextContent() throws {
        let conceptName = CodedConcept.finding
        
        let document = try SRDocumentBuilder()
            .addText(conceptName: conceptName, value: "Normal appearance")
            .build()
        
        let dataSet = try document.toDataSet()
        
        // Check Content Sequence exists
        let contentSeq = dataSet.sequence(for: .contentSequence)
        #expect(contentSeq != nil)
        #expect(contentSeq?.count == 1)
        
        let firstItem = contentSeq?.first
        #expect(firstItem?.string(for: .valueType) == "TEXT")
        #expect(firstItem?.string(for: .textValue) == "Normal appearance")
    }
    
    @Test("Serialize document with numeric content")
    func testSerializeNumericContent() throws {
        let units = CodedConcept.unitMillimeter
        
        let document = try SRDocumentBuilder()
            .addNumeric(value: 42.5, units: units)
            .build()
        
        let dataSet = try document.toDataSet()
        
        let contentSeq = dataSet.sequence(for: .contentSequence)
        #expect(contentSeq != nil)
        #expect(contentSeq?.count == 1)
        
        let firstItem = contentSeq?.first
        #expect(firstItem?.string(for: .valueType) == "NUM")
        
        // Check Measured Value Sequence
        let measuredValueSeq = firstItem?[.measuredValueSequence]?.sequenceItems
        #expect(measuredValueSeq != nil)
    }
    
    @Test("Serialize document with code content")
    func testSerializeCodeContent() throws {
        let codeValue = CodedConcept(
            codeValue: "111001",
            codingSchemeDesignator: "DCM",
            codeMeaning: "Present"
        )
        
        let document = try SRDocumentBuilder()
            .addCode(value: codeValue)
            .build()
        
        let dataSet = try document.toDataSet()
        
        let contentSeq = dataSet.sequence(for: .contentSequence)
        let firstItem = contentSeq?.first
        #expect(firstItem?.string(for: .valueType) == "CODE")
        
        // Check Concept Code Sequence
        let conceptCodeSeq = firstItem?[.conceptCodeSequence]?.sequenceItems
        #expect(conceptCodeSeq != nil)
        #expect(conceptCodeSeq?.first?.string(for: .codeValue) == "111001")
    }
    
    // MARK: - Round-Trip Tests
    
    @Test("Round-trip simple document")
    func testRoundTripSimpleDocument() throws {
        // Create a document
        let originalDocument = try SRDocumentBuilder()
            .withSOPInstanceUID("1.2.3.4.5")
            .withPatientID("PAT001")
            .withPatientName("Doe^John")
            .withStudyInstanceUID("1.2.3.4.5.6")
            .withSeriesInstanceUID("1.2.3.4.5.6.7")
            .withCompletionFlag(.complete)
            .withVerificationFlag(.verified)
            .addText(conceptName: CodedConcept.finding, value: "Normal appearance")
            .build()
            // VERIFIED requires the Verifying Observer Sequence (PS3.3 Table C.17-2, Type 1C)
            .withVerifyingObservers([VerifyingObserver(
                name: "Smith^Jane", organization: "Radiology", verificationDateTime: "20260929101500")])
        
        // Serialize to DataSet
        let dataSet = try originalDocument.toDataSet()
        
        // Parse back to SRDocument
        let parser = SRDocumentParser()
        let parsedDocument = try parser.parse(dataSet: dataSet)
        
        // Verify key properties match
        #expect(parsedDocument.sopInstanceUID == originalDocument.sopInstanceUID)
        #expect(parsedDocument.patientID == originalDocument.patientID)
        #expect(parsedDocument.patientName == originalDocument.patientName)
        #expect(parsedDocument.studyInstanceUID == originalDocument.studyInstanceUID)
        #expect(parsedDocument.seriesInstanceUID == originalDocument.seriesInstanceUID)
        #expect(parsedDocument.completionFlag == originalDocument.completionFlag)
        #expect(parsedDocument.verificationFlag == originalDocument.verificationFlag)
    }
    
    @Test("Round-trip document with multiple content types")
    func testRoundTripMultipleContentTypes() throws {
        let originalDocument = try SRDocumentBuilder()
            .withSOPInstanceUID("1.2.3.4.5")
            .addText(value: "Finding text")
            .addNumeric(value: 42.5, units: CodedConcept.unitMillimeter)
            .addCode(value: CodedConcept.finding)
            .build()
        
        let dataSet = try originalDocument.toDataSet()
        let parser = SRDocumentParser()
        let parsedDocument = try parser.parse(dataSet: dataSet)
        
        #expect(parsedDocument.findTextItems().count == 1)
        #expect(parsedDocument.findNumericItems().count == 1)
        #expect(parsedDocument.findCodeItems().count == 1)
    }
    
    @Test("Round-trip document with nested containers")
    func testRoundTripNestedContainers() throws {
        let containerConcept = CodedConcept(
            codeValue: "121070",
            codingSchemeDesignator: "DCM",
            codeMeaning: "Findings"
        )
        
        let originalDocument = try SRDocumentBuilder()
            .withSOPInstanceUID("1.2.3.4.5")
            .addContainer(conceptName: containerConcept, items: [
                .text(value: "Finding 1"),
                .text(value: "Finding 2")
            ])
            .build()
        
        let dataSet = try originalDocument.toDataSet()
        let parser = SRDocumentParser()
        let parsedDocument = try parser.parse(dataSet: dataSet)
        
        let containers = parsedDocument.findContainerItems()
        #expect(containers.count == 1)
        #expect(containers.first?.contentItems.count == 2)
    }
}

// MARK: - ContainerBuilder Tests

@Suite("ContainerBuilder Tests")
struct ContainerBuilderTests {
    
    @Test("Build container with single item")
    func testBuildSingleItem() {
        @ContainerBuilder
        func buildSingle() -> [AnyContentItem] {
            AnyContentItem(TextContentItem(textValue: "Test"))
        }
        
        let items = buildSingle()
        #expect(items.count == 1)
    }
    
    @Test("Build container with multiple items")
    func testBuildMultipleItems() {
        @ContainerBuilder
        func buildMultiple() -> [AnyContentItem] {
            AnyContentItem(TextContentItem(textValue: "Test 1"))
            AnyContentItem(TextContentItem(textValue: "Test 2"))
            AnyContentItem(NumericContentItem(value: 42.0))
        }
        
        let items = buildMultiple()
        #expect(items.count == 3)
    }
}

// MARK: - SRDocumentType Value Type Validation Tests

@Suite("SRDocumentType ValueType Validation Tests")
struct SRDocumentTypeValueTypeTests {

    @Test("Basic Text SR value types follow PS3.3 Table A.35.1-2")
    func testBasicTextSRValueTypes() {
        let documentType = SRDocumentType.basicTextSR

        // Table A.35.1-2 target value types
        #expect(documentType.allows(.text))
        #expect(documentType.allows(.code))
        #expect(documentType.allows(.container))
        #expect(documentType.allows(.image))
        #expect(documentType.allows(.composite))
        #expect(documentType.allows(.waveform))

        // Not in the table
        #expect(!documentType.allows(.num))
        #expect(!documentType.allows(.scoord))
        #expect(!documentType.allows(.scoord3D))
    }

    @Test("Enhanced SR value types follow PS3.3 Table A.35.2-2")
    func testEnhancedSRValueTypes() {
        let documentType = SRDocumentType.enhancedSR

        #expect(documentType.allows(.text))
        #expect(documentType.allows(.num))
        #expect(documentType.allows(.scoord))
        #expect(documentType.allows(.tcoord))
        #expect(!documentType.allows(.scoord3D))
    }

    @Test("Comprehensive SR value types follow PS3.3 Table A.35.3-2")
    func testComprehensiveSRValueTypes() {
        let documentType = SRDocumentType.comprehensiveSR

        #expect(documentType.allows(.text))
        #expect(documentType.allows(.num))
        #expect(documentType.allows(.scoord))
        #expect(!documentType.allows(.scoord3D))
    }

    @Test("Comprehensive 3D SR value types follow PS3.3 Table A.35.13-2")
    func testComprehensive3DSRValueTypes() {
        let documentType = SRDocumentType.comprehensive3DSR

        #expect(documentType.allows(.text))
        #expect(documentType.allows(.num))
        #expect(documentType.allows(.scoord))
        #expect(documentType.allows(.scoord3D))
    }

    @Test("Key Object Selection and Mammography CAD SR do not allow DATETIME (Tables A.35.4-2, A.35.5-2)")
    func testKOSAndMammoCADValueTypes() {
        #expect(!SRDocumentType.keyObjectSelectionDocument.allows(.datetime))
        #expect(!SRDocumentType.keyObjectSelectionDocument.allows(.num))
        #expect(!SRDocumentType.mammographyCADSR.allows(.datetime))
        #expect(SRDocumentType.mammographyCADSR.allows(.date))
        #expect(!SRDocumentType.chestCADSR.allows(.datetime))
    }

    @Test("The deprecated allowsValueType gives the same answer as allows")
    @available(*, deprecated)
    func testDeprecatedAllowsValueTypeForwards() {
        for type in [SRDocumentType.basicTextSR, .enhancedSR, .keyObjectSelectionDocument, .mammographyCADSR] {
            for valueType in [ContentItemValueType.text, .num, .datetime, .image, .scoord, .scoord3D] {
                #expect(type.allowsValueType(valueType) == type.allows(valueType))
            }
        }
    }
}
