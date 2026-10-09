import Testing
import Foundation
import DICOMCore
@testable import DICOMKit

// MARK: - EnhancedSRBuilder Tests

@Suite("EnhancedSRBuilder Tests")
struct EnhancedSRBuilderTests {
    
    // MARK: - Basic Builder Tests
    
    @Test("Builder initialization with default values")
    func testBuilderInitialization() {
        let builder = EnhancedSRBuilder()
        
        #expect(builder.validateOnBuild == true)
        #expect(builder.completionFlag == .partial)
        #expect(builder.verificationFlag == .unverified)
        #expect(builder.contentItems.isEmpty)
    }
    
    @Test("Builder initialization with validation disabled")
    func testBuilderWithValidationDisabled() {
        let builder = EnhancedSRBuilder(validateOnBuild: false)
        #expect(builder.validateOnBuild == false)
    }
    
    @Test("Build minimal document")
    func testBuildMinimalDocument() throws {
        let document = try EnhancedSRBuilder()
            .build()
        
        #expect(!document.sopInstanceUID.isEmpty)
        #expect(document.sopClassUID == SRDocumentType.enhancedSR.sopClassUID)
        #expect(document.documentType == .enhancedSR)
        #expect(document.modality == "SR")
    }
    
    // MARK: - Document Identification Tests
    
    @Test("Set SOP Instance UID")
    func testSetSOPInstanceUID() throws {
        let uid = "1.2.3.4.5.6.7.8.9"
        let document = try EnhancedSRBuilder()
            .withSOPInstanceUID(uid)
            .build()
        
        #expect(document.sopInstanceUID == uid)
    }
    
    @Test("Set Study Instance UID")
    func testSetStudyInstanceUID() throws {
        let uid = "1.2.3.4.5.6.7.8.10"
        let document = try EnhancedSRBuilder()
            .withStudyInstanceUID(uid)
            .build()
        
        #expect(document.studyInstanceUID == uid)
    }
    
    @Test("Set Series Instance UID")
    func testSetSeriesInstanceUID() throws {
        let uid = "1.2.3.4.5.6.7.8.11"
        let document = try EnhancedSRBuilder()
            .withSeriesInstanceUID(uid)
            .build()
        
        #expect(document.seriesInstanceUID == uid)
    }
    
    @Test("Set Instance Number")
    func testSetInstanceNumber() throws {
        let builder = EnhancedSRBuilder()
            .withInstanceNumber("5")
        
        #expect(builder.instanceNumber == "5")
    }
    
    // MARK: - Patient Information Tests
    
    @Test("Set Patient ID")
    func testSetPatientID() throws {
        let document = try EnhancedSRBuilder()
            .withPatientID("PAT123")
            .build()
        
        #expect(document.patientID == "PAT123")
    }
    
    @Test("Set Patient Name")
    func testSetPatientName() throws {
        let document = try EnhancedSRBuilder()
            .withPatientName("Doe^John")
            .build()
        
        #expect(document.patientName == "Doe^John")
    }
    
    @Test("Set Patient Birth Date")
    func testSetPatientBirthDate() throws {
        let builder = EnhancedSRBuilder()
            .withPatientBirthDate("19800101")
        
        #expect(builder.patientBirthDate == "19800101")
    }
    
    @Test("Set Patient Sex")
    func testSetPatientSex() throws {
        let builder = EnhancedSRBuilder()
            .withPatientSex("M")
        
        #expect(builder.patientSex == "M")
    }
    
    // MARK: - Study Information Tests
    
    @Test("Set Study Date")
    func testSetStudyDate() throws {
        let document = try EnhancedSRBuilder()
            .withStudyDate("20240115")
            .build()
        
        #expect(document.studyDate == "20240115")
    }
    
    @Test("Set Study Time")
    func testSetStudyTime() throws {
        let document = try EnhancedSRBuilder()
            .withStudyTime("143025")
            .build()
        
        #expect(document.studyTime == "143025")
    }
    
    @Test("Set Study Description")
    func testSetStudyDescription() throws {
        let builder = EnhancedSRBuilder()
            .withStudyDescription("CT Chest")
        
        #expect(builder.studyDescription == "CT Chest")
    }
    
    @Test("Set Accession Number")
    func testSetAccessionNumber() throws {
        let document = try EnhancedSRBuilder()
            .withAccessionNumber("ACC123")
            .build()
        
        #expect(document.accessionNumber == "ACC123")
    }
    
    @Test("Set Referring Physician Name")
    func testSetReferringPhysicianName() throws {
        let builder = EnhancedSRBuilder()
            .withReferringPhysicianName("Smith^Jane^Dr")
        
        #expect(builder.referringPhysicianName == "Smith^Jane^Dr")
    }
    
    // MARK: - Series Information Tests
    
    @Test("Set Series Number")
    func testSetSeriesNumber() throws {
        let document = try EnhancedSRBuilder()
            .withSeriesNumber("3")
            .build()
        
        #expect(document.seriesNumber == "3")
    }
    
    @Test("Set Series Description")
    func testSetSeriesDescription() throws {
        let builder = EnhancedSRBuilder()
            .withSeriesDescription("SR Report")
        
        #expect(builder.seriesDescription == "SR Report")
    }
    
    // MARK: - Document Information Tests
    
    @Test("Set Content Date")
    func testSetContentDate() throws {
        let document = try EnhancedSRBuilder()
            .withContentDate("20240115")
            .build()
        
        #expect(document.contentDate == "20240115")
    }
    
    @Test("Set Content Time")
    func testSetContentTime() throws {
        let document = try EnhancedSRBuilder()
            .withContentTime("150000")
            .build()
        
        #expect(document.contentTime == "150000")
    }
    
    @Test("Set Document Title with coded concept")
    func testSetDocumentTitleCodedConcept() throws {
        let title = CodedConcept(
            codeValue: "18782-3",
            codingSchemeDesignator: "LN",
            codeMeaning: "Radiology Study Observation"
        )
        let document = try EnhancedSRBuilder()
            .withDocumentTitle(title)
            .build()
        
        #expect(document.documentTitle == title)
    }
    
    @Test("Set Document Title with string")
    func testSetDocumentTitleString() throws {
        let document = try EnhancedSRBuilder()
            .withDocumentTitle("CT Measurement Report")
            .build()
        
        #expect(document.documentTitle?.codeMeaning == "CT Measurement Report")
    }
    
    @Test("Set Completion Flag")
    func testSetCompletionFlag() throws {
        let document = try EnhancedSRBuilder()
            .withCompletionFlag(.complete)
            .build()
        
        #expect(document.completionFlag == .complete)
    }
    
    @Test("Set Verification Flag")
    func testSetVerificationFlag() throws {
        let document = try EnhancedSRBuilder()
            .withVerificationFlag(.verified)
            .build()
        
        #expect(document.verificationFlag == .verified)
    }
    
    @Test("Set Preliminary Flag")
    func testSetPreliminaryFlag() throws {
        let document = try EnhancedSRBuilder()
            .withPreliminaryFlag(.preliminary)
            .build()
        
        #expect(document.preliminaryFlag == .preliminary)
    }
    
    // MARK: - Text Content Tests
    
    @Test("Add text content")
    func testAddText() throws {
        let document = try EnhancedSRBuilder()
            .addText("Normal chest radiograph")
            .build()
        
        #expect(document.rootContent.contentItems.count == 1)
        let item = document.rootContent.contentItems[0]
        #expect(item.valueType == .text)
        #expect(item.asText?.textValue == "Normal chest radiograph")
    }
    
    @Test("Add text with concept name")
    func testAddTextWithConceptName() throws {
        let concept = CodedConcept(
            codeValue: "121073",
            codingSchemeDesignator: "DCM",
            codeMeaning: "Finding"
        )
        let document = try EnhancedSRBuilder()
            .addText("No acute findings", conceptName: concept)
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.asText?.conceptName == concept)
    }
    
    @Test("Add labeled text")
    func testAddLabeledText() throws {
        let document = try EnhancedSRBuilder()
            .addLabeledText(label: "Diagnosis", value: "Normal study")
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.asText?.textValue == "Normal study")
        #expect(item.conceptName?.codeMeaning == "Diagnosis")
    }
    
    // MARK: - Numeric Content Tests
    
    @Test("Add numeric content")
    func testAddNumeric() throws {
        let document = try EnhancedSRBuilder()
            .addNumeric(value: 42.5)
            .build()
        
        #expect(document.rootContent.contentItems.count == 1)
        let item = document.rootContent.contentItems[0]
        #expect(item.valueType == .num)
        #expect(item.asNumeric?.value == 42.5)
    }
    
    @Test("Add numeric with concept name and units")
    func testAddNumericWithConceptNameAndUnits() throws {
        let conceptName = CodedConcept(
            codeValue: "G-D785",
            codingSchemeDesignator: "SRT",
            codeMeaning: "Diameter"
        )
        let units = UCUMUnit.millimeter.concept
        
        let document = try EnhancedSRBuilder()
            .addNumeric(conceptName: conceptName, value: 25.5, units: units)
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.asNumeric?.value == 25.5)
        #expect(item.asNumeric?.conceptName == conceptName)
        #expect(item.asNumeric?.measurementUnits == units)
    }
    
    @Test("Add numeric with multiple values")
    func testAddNumericMultipleValues() throws {
        let document = try EnhancedSRBuilder()
            .addNumeric(values: [1.0, 2.0, 3.0], units: UCUMUnit.millimeter.concept)
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.asNumeric?.numericValues == [1.0, 2.0, 3.0])
    }
    
    @Test("Add measurement in millimeters")
    func testAddMeasurementMM() throws {
        let document = try EnhancedSRBuilder()
            .addMeasurementMM(label: "Lesion Diameter", value: 15.5)
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.asNumeric?.value == 15.5)
        #expect(item.asNumeric?.measurementUnits == UCUMUnit.millimeter.concept)
    }
    
    @Test("Add measurement in centimeters")
    func testAddMeasurementCM() throws {
        let document = try EnhancedSRBuilder()
            .addMeasurementCM(label: "Tumor Length", value: 3.2)
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.asNumeric?.value == 3.2)
        #expect(item.asNumeric?.measurementUnits == UCUMUnit.centimeter.concept)
    }
    
    // MARK: - Section Tests
    
    @Test("Add section with string title")
    func testAddSectionWithStringTitle() throws {
        let document = try EnhancedSRBuilder()
            .addSection("Findings") {
                EnhancedSectionContent.text("Normal study")
            }
            .build()
        
        #expect(document.rootContent.contentItems.count == 1)
        let section = document.rootContent.contentItems[0]
        #expect(section.valueType == .container)
        #expect(section.conceptName?.codeMeaning == "Findings")
    }
    
    @Test("Add section with coded concept")
    func testAddSectionWithCodedConcept() throws {
        let title = CodedConcept.findings
        let document = try EnhancedSRBuilder()
            .addSection(title) {
                EnhancedSectionContent.text("No abnormalities")
            }
            .build()
        
        let section = document.rootContent.contentItems[0]
        #expect(section.asContainer?.conceptName == title)
    }
    
    @Test("Add section with measurements")
    func testAddSectionWithMeasurements() throws {
        let document = try EnhancedSRBuilder()
            .addSection("Measurements") {
                EnhancedSectionContent.measurement(
                    label: "Diameter",
                    value: 25.0,
                    units: UCUMUnit.millimeter.concept
                )
                EnhancedSectionContent.measurement(
                    label: "Length",
                    value: 50.0,
                    units: UCUMUnit.millimeter.concept
                )
            }
            .build()
        
        let section = document.rootContent.contentItems[0]
        #expect(section.asContainer?.contentItems.count == 2)
    }
    
    @Test("Add section with pre-built items")
    func testAddSectionWithPrebuiltItems() throws {
        let items = [
            AnyContentItem(TextContentItem(textValue: "Item 1")),
            AnyContentItem(TextContentItem(textValue: "Item 2"))
        ]
        
        let document = try EnhancedSRBuilder()
            .addSection("Test Section", items: items)
            .build()
        
        let section = document.rootContent.contentItems[0]
        #expect(section.asContainer?.contentItems.count == 2)
    }
    
    // MARK: - Code Content Tests
    
    @Test("Add code content")
    func testAddCode() throws {
        let conceptName = CodedConcept(
            codeValue: "363698007",
            codingSchemeDesignator: "SCT",
            codeMeaning: "Finding site"
        )
        let value = CodedConcept(
            codeValue: "39607008",
            codingSchemeDesignator: "SCT",
            codeMeaning: "Lung"
        )
        
        let document = try EnhancedSRBuilder()
            .addCode(conceptName: conceptName, value: value)
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.valueType == .code)
        #expect(item.asCode?.conceptCode == value)
    }
    
    // MARK: - Reference Content Tests
    
    @Test("Add person name")
    func testAddPersonName() throws {
        let document = try EnhancedSRBuilder()
            .addPersonName(name: "Doe^John^Dr")
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.valueType == .pname)
        #expect(item.asPersonName?.personName == "Doe^John^Dr")
    }
    
    @Test("Add UID reference")
    func testAddUIDRef() throws {
        let uid = "1.2.3.4.5.6.7"
        let document = try EnhancedSRBuilder()
            .addUIDRef(uid: uid)
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.valueType == .uidref)
        #expect(item.asUIDRef?.uidValue == uid)
    }
    
    @Test("Add date content")
    func testAddDate() throws {
        let document = try EnhancedSRBuilder()
            .addDate(date: "20240115")
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.valueType == .date)
        #expect(item.asDate?.dateValue == "20240115")
    }
    
    @Test("Add time content")
    func testAddTime() throws {
        let document = try EnhancedSRBuilder()
            .addTime(time: "143025")
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.valueType == .time)
        #expect(item.asTime?.timeValue == "143025")
    }
    
    @Test("Add datetime content")
    func testAddDateTime() throws {
        let document = try EnhancedSRBuilder()
            .addDateTime(datetime: "20240115143025")
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.valueType == .datetime)
        #expect(item.asDateTime?.dateTimeValue == "20240115143025")
    }
    
    @Test("Add image reference")
    func testAddImageReference() throws {
        let document = try EnhancedSRBuilder()
            .addImageReference(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: "1.2.3.4.5.6.7.8.9"
            )
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.valueType == .image)
        #expect(item.asImage?.imageReference.sopReference.sopInstanceUID == "1.2.3.4.5.6.7.8.9")
    }
    
    @Test("Add image reference with frame numbers")
    func testAddImageReferenceWithFrameNumbers() throws {
        let document = try EnhancedSRBuilder()
            .addImageReference(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: "1.2.3.4.5.6.7.8.9",
                frameNumbers: [1, 5, 10]
            )
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.asImage?.imageReference.frameNumbers == [1, 5, 10])
    }
    
    @Test("Add composite reference")
    func testAddCompositeReference() throws {
        let document = try EnhancedSRBuilder()
            .addCompositeReference(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.88.11",
                sopInstanceUID: "1.2.3.4.5.6.7.8.9"
            )
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.valueType == .composite)
    }
    
    @Test("Add waveform reference")
    func testAddWaveformReference() throws {
        let document = try EnhancedSRBuilder()
            .addWaveformReference(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.9.1.1",
                sopInstanceUID: "1.2.3.4.5.6.7.8.9"
            )
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.valueType == .waveform)
    }
    
    @Test("Add waveform reference with channel numbers")
    func testAddWaveformReferenceWithChannels() throws {
        let document = try EnhancedSRBuilder()
            .addWaveformReference(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.9.1.1",
                sopInstanceUID: "1.2.3.4.5.6.7.8.9",
                channelNumbers: [1, 2, 3]
            )
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.asWaveform?.waveformReference.channelNumbers == [1, 2, 3])
    }
    
    @Test("Add pre-built item")
    func testAddItem() throws {
        let textItem = AnyContentItem(TextContentItem(textValue: "Custom text"))
        let document = try EnhancedSRBuilder()
            .addItem(textItem)
            .build()
        
        #expect(document.rootContent.contentItems.count == 1)
        #expect(document.rootContent.contentItems[0].asText?.textValue == "Custom text")
    }
    
    // MARK: - Common Report Section Tests
    
    @Test("Add findings section")
    func testAddFindings() throws {
        let document = try EnhancedSRBuilder()
            .addFindings("Normal chest radiograph")
            .build()
        
        let section = document.rootContent.contentItems[0]
        #expect(section.valueType == .container)
        #expect(section.conceptName == CodedConcept.findings)
    }
    
    @Test("Add impression section")
    func testAddImpression() throws {
        let document = try EnhancedSRBuilder()
            .addImpression("No acute findings")
            .build()
        
        let section = document.rootContent.contentItems[0]
        #expect(section.conceptName == CodedConcept.impression)
    }
    
    @Test("Add clinical history section")
    func testAddClinicalHistory() throws {
        let document = try EnhancedSRBuilder()
            .addClinicalHistory("Patient presents with chest pain")
            .build()
        
        let section = document.rootContent.contentItems[0]
        #expect(section.conceptName == CodedConcept.clinicalHistory)
    }
    
    @Test("Add conclusion section")
    func testAddConclusion() throws {
        let document = try EnhancedSRBuilder()
            .addConclusion("Study complete")
            .build()
        
        let section = document.rootContent.contentItems[0]
        #expect(section.conceptName == CodedConcept.conclusion)
    }
    
    @Test("Add recommendation section")
    func testAddRecommendation() throws {
        let document = try EnhancedSRBuilder()
            .addRecommendation("Follow-up in 6 months")
            .build()
        
        let section = document.rootContent.contentItems[0]
        #expect(section.conceptName == CodedConcept.recommendation)
    }
    
    @Test("Add procedure description section")
    func testAddProcedureDescription() throws {
        let document = try EnhancedSRBuilder()
            .addProcedureDescription("CT scan of chest with IV contrast")
            .build()
        
        let section = document.rootContent.contentItems[0]
        #expect(section.conceptName == CodedConcept.procedureDescription)
    }
    
    @Test("Add comparison section")
    func testAddComparison() throws {
        let document = try EnhancedSRBuilder()
            .addComparison("Compared to prior study dated 2023-01-15")
            .build()
        
        let section = document.rootContent.contentItems[0]
        #expect(section.conceptName == CodedConcept.comparison)
    }
    
    @Test("Add measurements section")
    func testAddMeasurementsSection() throws {
        let document = try EnhancedSRBuilder()
            .addMeasurements {
                EnhancedSectionContent.numeric(value: 25.0, units: UCUMUnit.millimeter.concept)
                EnhancedSectionContent.numeric(value: 30.0, units: UCUMUnit.millimeter.concept)
            }
            .build()
        
        let section = document.rootContent.contentItems[0]
        #expect(section.conceptName == CodedConcept.measurements)
        #expect(section.asContainer?.contentItems.count == 2)
    }
    
    // MARK: - Validation Tests
    
    @Test("Validation passes for valid Enhanced SR content")
    func testValidationPasses() throws {
        // Enhanced SR supports TEXT, CODE, NUM, DATETIME, DATE, TIME, UIDREF, PNAME, COMPOSITE, IMAGE, WAVEFORM, CONTAINER
        let document = try EnhancedSRBuilder()
            .addText("Text content")
            .addNumeric(value: 42.0)
            .addDate(date: "20240115")
            .addTime(time: "143025")
            .addDateTime(datetime: "20240115143025")
            .addUIDRef(uid: "1.2.3.4")
            .addPersonName(name: "Doe^John")
            .addImageReference(sopClassUID: "1.2.3", sopInstanceUID: "1.2.3.4")
            .addWaveformReference(sopClassUID: "1.2.3", sopInstanceUID: "1.2.3.4")
            .build()
        
        #expect(document.rootContent.contentItems.count == 9)
    }
    
    @Test("Validation accepts SCOORD content")
    func testValidationAcceptsSCOORD() throws {
        // Enhanced SR permits SCOORD (PS3.3 2026a A.35.2 Value Type constraints)
        let spatialItem = AnyContentItem(SpatialCoordinatesContentItem(
            graphicType: .point,
            graphicData: [10.0, 20.0]
        ))
        
        let document = try EnhancedSRBuilder()
            .addItem(spatialItem)
            .build()
        #expect(document.rootContent.contentItems.count == 1)
    }
    
    @Test("Validation fails for SCOORD3D content")
    func testValidationFailsForSCOORD3D() throws {
        // Enhanced SR does NOT support SCOORD3D
        let spatial3DItem = AnyContentItem(SpatialCoordinates3DContentItem(
            graphicType: .point,
            graphicData: [10.0, 20.0, 30.0],
            frameOfReferenceUID: "1.2.3.4.5"
        ))
        
        #expect(throws: EnhancedSRBuilder.BuildError.self) {
            _ = try EnhancedSRBuilder()
                .addItem(spatial3DItem)
                .build()
        }
    }
    
    @Test("Validation accepts TCOORD content")
    func testValidationAcceptsTCOORD() throws {
        // Enhanced SR permits TCOORD (PS3.3 2026a A.35.2 Value Type constraints)
        let temporalItem = AnyContentItem(TemporalCoordinatesContentItem(
            temporalRangeType: .point,
            samplePositions: [1]
        ))
        
        let document = try EnhancedSRBuilder()
            .addItem(temporalItem)
            .build()
        #expect(document.rootContent.contentItems.count == 1)
    }
    
    @Test("Validation disabled allows unsupported content")
    func testValidationDisabledAllowsUnsupportedContent() throws {
        let spatialItem = AnyContentItem(SpatialCoordinatesContentItem(
            graphicType: .point,
            graphicData: [10.0, 20.0]
        ))
        
        // With validation disabled, it should not throw
        let document = try EnhancedSRBuilder(validateOnBuild: false)
            .addItem(spatialItem)
            .build()
        
        #expect(document.rootContent.contentItems.count == 1)
    }
    
    // MARK: - Enhanced Section Content Tests
    
    @Test("EnhancedSectionContent text helper")
    func testEnhancedSectionContentText() {
        let item = EnhancedSectionContent.text("Sample text")
        #expect(item.valueType == .text)
        #expect(item.asText?.textValue == "Sample text")
    }
    
    @Test("EnhancedSectionContent labeled text helper")
    func testEnhancedSectionContentLabeledText() {
        let item = EnhancedSectionContent.labeledText(label: "Label", value: "Value")
        #expect(item.valueType == .text)
        #expect(item.asText?.textValue == "Value")
        #expect(item.conceptName?.codeMeaning == "Label")
    }
    
    @Test("EnhancedSectionContent numeric helper")
    func testEnhancedSectionContentNumeric() {
        let item = EnhancedSectionContent.numeric(value: 42.0)
        #expect(item.valueType == .num)
        #expect(item.asNumeric?.value == 42.0)
    }
    
    @Test("EnhancedSectionContent measurement helper")
    func testEnhancedSectionContentMeasurement() {
        let item = EnhancedSectionContent.measurement(
            label: "Diameter",
            value: 25.0,
            units: UCUMUnit.millimeter.concept
        )
        #expect(item.valueType == .num)
        #expect(item.asNumeric?.value == 25.0)
        #expect(item.conceptName?.codeMeaning == "Diameter")
    }
    
    @Test("EnhancedSectionContent code helper")
    func testEnhancedSectionContentCode() {
        let value = CodedConcept(
            codeValue: "12345",
            codingSchemeDesignator: "DCM",
            codeMeaning: "Test Code"
        )
        let item = EnhancedSectionContent.code(conceptName: nil, value: value)
        #expect(item.valueType == .code)
        #expect(item.asCode?.conceptCode == value)
    }
    
    @Test("EnhancedSectionContent personName helper")
    func testEnhancedSectionContentPersonName() {
        let item = EnhancedSectionContent.personName(name: "Doe^John")
        #expect(item.valueType == .pname)
        #expect(item.asPersonName?.personName == "Doe^John")
    }
    
    @Test("EnhancedSectionContent date helper")
    func testEnhancedSectionContentDate() {
        let item = EnhancedSectionContent.date(date: "20240115")
        #expect(item.valueType == .date)
        #expect(item.asDate?.dateValue == "20240115")
    }
    
    @Test("EnhancedSectionContent time helper")
    func testEnhancedSectionContentTime() {
        let item = EnhancedSectionContent.time(time: "143025")
        #expect(item.valueType == .time)
        #expect(item.asTime?.timeValue == "143025")
    }
    
    @Test("EnhancedSectionContent datetime helper")
    func testEnhancedSectionContentDatetime() {
        let item = EnhancedSectionContent.datetime(datetime: "20240115143025")
        #expect(item.valueType == .datetime)
        #expect(item.asDateTime?.dateTimeValue == "20240115143025")
    }
    
    @Test("EnhancedSectionContent imageReference helper")
    func testEnhancedSectionContentImageReference() {
        let item = EnhancedSectionContent.imageReference(
            sopClassUID: "1.2.3",
            sopInstanceUID: "1.2.3.4"
        )
        #expect(item.valueType == .image)
    }
    
    @Test("EnhancedSectionContent waveformReference helper")
    func testEnhancedSectionContentWaveformReference() {
        let item = EnhancedSectionContent.waveformReference(
            sopClassUID: "1.2.3",
            sopInstanceUID: "1.2.3.4"
        )
        #expect(item.valueType == .waveform)
    }
    
    @Test("EnhancedSectionContent subsection helper")
    func testEnhancedSectionContentSubsection() {
        let items = [EnhancedSectionContent.text("Inner text")]
        let item = EnhancedSectionContent.subsection("Inner Section", items: items)
        #expect(item.valueType == .container)
        #expect(item.asContainer?.contentItems.count == 1)
    }
    
    // MARK: - Full Document Tests
    
    @Test("Build complete measurement report")
    func testBuildCompleteMeasurementReport() throws {
        let document = try EnhancedSRBuilder()
            .withPatientID("12345")
            .withPatientName("Doe^John")
            .withStudyDate("20240115")
            .withStudyTime("140000")
            .withDocumentTitle("CT Measurement Report")
            .withCompletionFlag(.complete)
            .withVerificationFlag(.verified)
            .addClinicalHistory("Follow-up for known liver lesion")
            .addSection("Findings") {
                EnhancedSectionContent.text("Hepatic lesion in segment 7")
                EnhancedSectionContent.subsection("Measurements", items: [
                    EnhancedSectionContent.measurement(label: "Axial Diameter", value: 25.5, units: UCUMUnit.millimeter.concept),
                    EnhancedSectionContent.measurement(label: "Craniocaudal Length", value: 30.2, units: UCUMUnit.millimeter.concept)
                ])
            }
            .addImpression("Stable hepatic lesion")
            .addRecommendation("Follow-up CT in 6 months")
            .build()
        
        #expect(document.sopClassUID == SRDocumentType.enhancedSR.sopClassUID)
        #expect(document.patientID == "12345")
        #expect(document.patientName == "Doe^John")
        #expect(document.completionFlag == .complete)
        #expect(document.verificationFlag == .verified)
        #expect(document.rootContent.contentItems.count == 4)  // ClinicalHistory, Findings, Impression, Recommendation
    }
    
    @Test("Auto-generated UIDs when not provided")
    func testAutoGeneratedUIDs() throws {
        let document = try EnhancedSRBuilder().build()
        
        #expect(!document.sopInstanceUID.isEmpty)
        #expect(document.studyInstanceUID != nil && !document.studyInstanceUID!.isEmpty)
        #expect(document.seriesInstanceUID != nil && !document.seriesInstanceUID!.isEmpty)
    }
    
    @Test("Builder chain immutability")
    func testBuilderChainImmutability() throws {
        let builder1 = EnhancedSRBuilder()
            .withPatientID("PAT1")
        
        let builder2 = builder1
            .withPatientID("PAT2")
        
        // builder1 should remain unchanged
        #expect(builder1.patientID == "PAT1")
        #expect(builder2.patientID == "PAT2")
    }
}

// MARK: - CodedConcept Extensions Tests

@Suite("Enhanced SR CodedConcept Extensions Tests")
struct EnhancedSRCodedConceptTests {
    
    @Test("Measurements coded concept")
    func testMeasurementsCodedConcept() {
        let concept = CodedConcept.measurements
        #expect(concept.codeValue == "126010")
        #expect(concept.codingSchemeDesignator == "DCM")
        #expect(concept.codeMeaning == "Imaging Measurements")
    }

    // PS3.16 2026a CID 7470 (linear), 7471 (area), 7472 (volume): SCT concept ids
    @Test("Diameter coded concept")
    func testDiameterCodedConcept() {
        let concept = CodedConcept.diameter
        #expect(concept.codeValue == "81827009")
        #expect(concept.codingSchemeDesignator == "SCT")
        #expect(concept.codeMeaning == "Diameter")
    }

    @Test("Length coded concept")
    func testLengthCodedConcept() {
        let concept = CodedConcept.length
        #expect(concept.codeValue == "410668003")
        #expect(concept.codingSchemeDesignator == "SCT")
        #expect(concept.codeMeaning == "Length")
    }

    @Test("Area coded concept")
    func testAreaCodedConcept() {
        let concept = CodedConcept.area
        #expect(concept.codeValue == "42798000")
        #expect(concept.codingSchemeDesignator == "SCT")
        #expect(concept.codeMeaning == "Area")
    }

    @Test("Volume coded concept")
    func testVolumeCodedConcept() {
        let concept = CodedConcept.volume
        #expect(concept.codeValue == "118565006")
        #expect(concept.codingSchemeDesignator == "SCT")
        #expect(concept.codeMeaning == "Volume")
    }
}
