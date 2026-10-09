import Testing
import Foundation
import DICOMCore
@testable import DICOMKit

// MARK: - ComprehensiveSRBuilder Tests

@Suite("ComprehensiveSRBuilder Tests")
struct ComprehensiveSRBuilderTests {
    
    // MARK: - Basic Builder Tests
    
    @Test("Builder initialization with default values")
    func testBuilderInitialization() {
        let builder = ComprehensiveSRBuilder()
        
        #expect(builder.validateOnBuild == true)
        #expect(builder.completionFlag == .partial)
        #expect(builder.verificationFlag == .unverified)
        #expect(builder.contentItems.isEmpty)
    }
    
    @Test("Builder initialization with validation disabled")
    func testBuilderWithValidationDisabled() {
        let builder = ComprehensiveSRBuilder(validateOnBuild: false)
        #expect(builder.validateOnBuild == false)
    }
    
    @Test("Build minimal document")
    func testBuildMinimalDocument() throws {
        let document = try ComprehensiveSRBuilder()
            .build()
        
        #expect(!document.sopInstanceUID.isEmpty)
        #expect(document.sopClassUID == SRDocumentType.comprehensiveSR.sopClassUID)
        #expect(document.documentType == .comprehensiveSR)
        #expect(document.modality == "SR")
    }
    
    // MARK: - Document Identification Tests
    
    @Test("Set SOP Instance UID")
    func testSetSOPInstanceUID() throws {
        let uid = "1.2.3.4.5.6.7.8.9"
        let document = try ComprehensiveSRBuilder()
            .withSOPInstanceUID(uid)
            .build()
        
        #expect(document.sopInstanceUID == uid)
    }
    
    @Test("Set Study Instance UID")
    func testSetStudyInstanceUID() throws {
        let uid = "1.2.3.4.5.6.7.8.10"
        let document = try ComprehensiveSRBuilder()
            .withStudyInstanceUID(uid)
            .build()
        
        #expect(document.studyInstanceUID == uid)
    }
    
    @Test("Set Series Instance UID")
    func testSetSeriesInstanceUID() throws {
        let uid = "1.2.3.4.5.6.7.8.11"
        let document = try ComprehensiveSRBuilder()
            .withSeriesInstanceUID(uid)
            .build()
        
        #expect(document.seriesInstanceUID == uid)
    }
    
    @Test("Set Instance Number")
    func testSetInstanceNumber() throws {
        let builder = ComprehensiveSRBuilder()
            .withInstanceNumber("5")
        
        #expect(builder.instanceNumber == "5")
    }
    
    // MARK: - Patient Information Tests
    
    @Test("Set Patient ID")
    func testSetPatientID() throws {
        let document = try ComprehensiveSRBuilder()
            .withPatientID("PAT123")
            .build()
        
        #expect(document.patientID == "PAT123")
    }
    
    @Test("Set Patient Name")
    func testSetPatientName() throws {
        let document = try ComprehensiveSRBuilder()
            .withPatientName("Doe^John")
            .build()
        
        #expect(document.patientName == "Doe^John")
    }
    
    @Test("Set Patient Birth Date")
    func testSetPatientBirthDate() throws {
        let builder = ComprehensiveSRBuilder()
            .withPatientBirthDate("19800101")
        
        #expect(builder.patientBirthDate == "19800101")
    }
    
    @Test("Set Patient Sex")
    func testSetPatientSex() throws {
        let builder = ComprehensiveSRBuilder()
            .withPatientSex("M")
        
        #expect(builder.patientSex == "M")
    }
    
    // MARK: - Study Information Tests
    
    @Test("Set Study Date")
    func testSetStudyDate() throws {
        let document = try ComprehensiveSRBuilder()
            .withStudyDate("20240115")
            .build()
        
        #expect(document.studyDate == "20240115")
    }
    
    @Test("Set Study Time")
    func testSetStudyTime() throws {
        let document = try ComprehensiveSRBuilder()
            .withStudyTime("143025")
            .build()
        
        #expect(document.studyTime == "143025")
    }
    
    @Test("Set Study Description")
    func testSetStudyDescription() throws {
        let builder = ComprehensiveSRBuilder()
            .withStudyDescription("CT Chest")
        
        #expect(builder.studyDescription == "CT Chest")
    }
    
    @Test("Set Accession Number")
    func testSetAccessionNumber() throws {
        let document = try ComprehensiveSRBuilder()
            .withAccessionNumber("ACC123")
            .build()
        
        #expect(document.accessionNumber == "ACC123")
    }
    
    @Test("Set Referring Physician Name")
    func testSetReferringPhysicianName() throws {
        let builder = ComprehensiveSRBuilder()
            .withReferringPhysicianName("Smith^Jane^Dr")
        
        #expect(builder.referringPhysicianName == "Smith^Jane^Dr")
    }
    
    // MARK: - Series Information Tests
    
    @Test("Set Series Number")
    func testSetSeriesNumber() throws {
        let document = try ComprehensiveSRBuilder()
            .withSeriesNumber("3")
            .build()
        
        #expect(document.seriesNumber == "3")
    }
    
    @Test("Set Series Description")
    func testSetSeriesDescription() throws {
        let builder = ComprehensiveSRBuilder()
            .withSeriesDescription("SR Report")
        
        #expect(builder.seriesDescription == "SR Report")
    }
    
    // MARK: - Document Information Tests
    
    @Test("Set Content Date")
    func testSetContentDate() throws {
        let document = try ComprehensiveSRBuilder()
            .withContentDate("20240115")
            .build()
        
        #expect(document.contentDate == "20240115")
    }
    
    @Test("Set Content Time")
    func testSetContentTime() throws {
        let document = try ComprehensiveSRBuilder()
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
        let document = try ComprehensiveSRBuilder()
            .withDocumentTitle(title)
            .build()
        
        #expect(document.documentTitle == title)
    }
    
    @Test("Set Document Title with string")
    func testSetDocumentTitleString() throws {
        let document = try ComprehensiveSRBuilder()
            .withDocumentTitle("CT Measurement Report")
            .build()
        
        #expect(document.documentTitle?.codeMeaning == "CT Measurement Report")
    }
    
    @Test("Set Completion Flag")
    func testSetCompletionFlag() throws {
        let document = try ComprehensiveSRBuilder()
            .withCompletionFlag(.complete)
            .build()
        
        #expect(document.completionFlag == .complete)
    }
    
    @Test("Set Verification Flag")
    func testSetVerificationFlag() throws {
        let document = try ComprehensiveSRBuilder()
            .withVerificationFlag(.verified)
            .build()
        
        #expect(document.verificationFlag == .verified)
    }
    
    @Test("Set Preliminary Flag")
    func testSetPreliminaryFlag() throws {
        let document = try ComprehensiveSRBuilder()
            .withPreliminaryFlag(.preliminary)
            .build()
        
        #expect(document.preliminaryFlag == .preliminary)
    }
    
    // MARK: - Text Content Tests
    
    @Test("Add text content")
    func testAddText() throws {
        let document = try ComprehensiveSRBuilder()
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
        let document = try ComprehensiveSRBuilder()
            .addText("No acute findings", conceptName: concept)
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.asText?.conceptName == concept)
    }
    
    @Test("Add labeled text")
    func testAddLabeledText() throws {
        let document = try ComprehensiveSRBuilder()
            .addLabeledText(label: "Diagnosis", value: "Normal study")
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.asText?.textValue == "Normal study")
        #expect(item.conceptName?.codeMeaning == "Diagnosis")
    }
    
    // MARK: - Numeric Content Tests
    
    @Test("Add numeric content")
    func testAddNumeric() throws {
        let document = try ComprehensiveSRBuilder()
            .addNumeric(value: 42.5)
            .build()
        
        #expect(document.rootContent.contentItems.count == 1)
        let item = document.rootContent.contentItems[0]
        #expect(item.valueType == .num)
        #expect(item.asNumeric?.value == 42.5)
    }
    
    @Test("Add numeric with concept name and units")
    func testAddNumericWithConceptAndUnits() throws {
        let concept = CodedConcept.diameter
        let units = UCUMUnit.millimeter.concept
        
        let document = try ComprehensiveSRBuilder()
            .addNumeric(conceptName: concept, value: 25.0, units: units)
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.asNumeric?.conceptName == concept)
        #expect(item.asNumeric?.measurementUnits == units)
    }
    
    @Test("Add numeric with multiple values")
    func testAddNumericMultipleValues() throws {
        let document = try ComprehensiveSRBuilder()
            .addNumeric(values: [10.0, 20.0, 30.0])
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.asNumeric?.numericValues == [10.0, 20.0, 30.0])
    }
    
    @Test("Add measurement in millimeters")
    func testAddMeasurementMM() throws {
        let document = try ComprehensiveSRBuilder()
            .addMeasurementMM(label: "Tumor Diameter", value: 25.5)
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.asNumeric?.value == 25.5)
        #expect(item.asNumeric?.measurementUnits == UCUMUnit.millimeter.concept)
    }
    
    @Test("Add measurement in centimeters")
    func testAddMeasurementCM() throws {
        let document = try ComprehensiveSRBuilder()
            .addMeasurementCM(label: "Lesion Length", value: 3.2)
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.asNumeric?.value == 3.2)
        #expect(item.asNumeric?.measurementUnits == UCUMUnit.centimeter.concept)
    }
    
    // MARK: - Spatial Coordinates Tests (2D)
    
    @Test("Add spatial coordinates (2D)")
    func testAddSpatialCoordinates() throws {
        let document = try ComprehensiveSRBuilder()
            .addSpatialCoordinates(
                graphicType: .point,
                graphicData: [100.0, 200.0]
            )
            .build()
        
        #expect(document.rootContent.contentItems.count == 1)
        let item = document.rootContent.contentItems[0]
        #expect(item.valueType == .scoord)
        
        let scoord = item.asSpatialCoordinates
        #expect(scoord?.graphicType == .point)
        #expect(scoord?.graphicData == [100.0, 200.0])
    }
    
    @Test("Add point coordinate")
    func testAddPoint() throws {
        let document = try ComprehensiveSRBuilder()
            .addPoint(column: 150.0, row: 250.0)
            .build()
        
        let item = document.rootContent.contentItems[0]
        let scoord = item.asSpatialCoordinates
        #expect(scoord?.graphicType == .point)
        #expect(scoord?.graphicData == [150.0, 250.0])
        #expect(scoord?.pointCount == 1)
    }
    
    @Test("Add polyline coordinate")
    func testAddPolyline() throws {
        let points: [(column: Float, row: Float)] = [
            (100.0, 100.0),
            (200.0, 100.0),
            (200.0, 200.0)
        ]
        
        let document = try ComprehensiveSRBuilder()
            .addPolyline(points: points)
            .build()
        
        let item = document.rootContent.contentItems[0]
        let scoord = item.asSpatialCoordinates
        #expect(scoord?.graphicType == .polyline)
        #expect(scoord?.pointCount == 3)
        #expect(scoord?.graphicData == [100.0, 100.0, 200.0, 100.0, 200.0, 200.0])
    }
    
    @Test("Add polygon coordinate")
    func testAddPolygon() throws {
        let points: [(column: Float, row: Float)] = [
            (100.0, 100.0),
            (200.0, 100.0),
            (200.0, 200.0),
            (100.0, 200.0)
        ]
        
        let document = try ComprehensiveSRBuilder()
            .addPolygon(points: points)
            .build()

        // PS3.3 C.18.6.1.2: a closed 2D shape is a POLYLINE whose last vertex repeats the first
        let item = document.rootContent.contentItems[0]
        let scoord = item.asSpatialCoordinates
        #expect(scoord?.graphicType == .polyline)
        #expect(scoord?.pointCount == 5)
        #expect(scoord?.graphicData.suffix(2) == [100.0, 100.0])
    }

    @Test("Add polygon that is already closed is not closed twice")
    func testAddClosedPolygon() throws {
        let document = try ComprehensiveSRBuilder()
            .addPolygon(points: [(0, 0), (10, 0), (10, 10), (0, 0)])
            .build()
        let scoord = document.rootContent.contentItems[0].asSpatialCoordinates
        #expect(scoord?.graphicType == .polyline)
        #expect(scoord?.pointCount == 4)
    }
    
    @Test("Add circle coordinate")
    func testAddCircle() throws {
        let document = try ComprehensiveSRBuilder()
            .addCircle(
                centerColumn: 150.0,
                centerRow: 150.0,
                edgeColumn: 170.0,
                edgeRow: 150.0
            )
            .build()
        
        let item = document.rootContent.contentItems[0]
        let scoord = item.asSpatialCoordinates
        #expect(scoord?.graphicType == .circle)
        #expect(scoord?.graphicData == [150.0, 150.0, 170.0, 150.0])
    }
    
    @Test("Add ellipse coordinate")
    func testAddEllipse() throws {
        let document = try ComprehensiveSRBuilder()
            .addEllipse(
                majorAxisEndpoint1: (column: 100.0, row: 150.0),
                majorAxisEndpoint2: (column: 200.0, row: 150.0),
                minorAxisEndpoint1: (column: 150.0, row: 130.0),
                minorAxisEndpoint2: (column: 150.0, row: 170.0)
            )
            .build()
        
        let item = document.rootContent.contentItems[0]
        let scoord = item.asSpatialCoordinates
        #expect(scoord?.graphicType == .ellipse)
        #expect(scoord?.graphicData.count == 8)
    }
    
    @Test("Add spatial coordinates with concept name")
    func testAddSpatialCoordinatesWithConcept() throws {
        let concept = CodedConcept.imageRegion
        
        let document = try ComprehensiveSRBuilder()
            .addSpatialCoordinates(
                conceptName: concept,
                graphicType: .polygon,
                graphicData: [100.0, 100.0, 200.0, 100.0, 200.0, 200.0]
            )
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.asSpatialCoordinates?.conceptName == concept)
    }
    
    // MARK: - Temporal Coordinates Tests
    
    @Test("Add temporal coordinates with sample positions")
    func testAddTemporalCoordinatesSamplePositions() throws {
        let document = try ComprehensiveSRBuilder()
            .addTemporalCoordinates(
                temporalRangeType: .point,
                samplePositions: [100, 200, 300]
            )
            .build()
        
        #expect(document.rootContent.contentItems.count == 1)
        let item = document.rootContent.contentItems[0]
        #expect(item.valueType == .tcoord)
        
        let tcoord = item.asTemporalCoordinates
        #expect(tcoord?.temporalRangeType == .point)
        #expect(tcoord?.referencedSamplePositions == [100, 200, 300])
    }
    
    @Test("Add temporal coordinates with time offsets")
    func testAddTemporalCoordinatesTimeOffsets() throws {
        let document = try ComprehensiveSRBuilder()
            .addTemporalCoordinates(
                temporalRangeType: .segment,
                timeOffsets: [0.5, 1.0, 1.5]
            )
            .build()
        
        let item = document.rootContent.contentItems[0]
        let tcoord = item.asTemporalCoordinates
        #expect(tcoord?.temporalRangeType == .segment)
        #expect(tcoord?.referencedTimeOffsets == [0.5, 1.0, 1.5])
    }
    
    @Test("Add temporal coordinates with datetime values")
    func testAddTemporalCoordinatesDateTime() throws {
        let document = try ComprehensiveSRBuilder()
            .addTemporalCoordinates(
                temporalRangeType: .multipoint,
                dateTimes: ["20240115120000", "20240115121000"]
            )
            .build()
        
        let item = document.rootContent.contentItems[0]
        let tcoord = item.asTemporalCoordinates
        #expect(tcoord?.temporalRangeType == .multipoint)
        #expect(tcoord?.referencedDateTime == ["20240115120000", "20240115121000"])
    }
    
    @Test("Add temporal coordinates with concept name")
    func testAddTemporalCoordinatesWithConcept() throws {
        let concept = CodedConcept.temporalExtent
        
        let document = try ComprehensiveSRBuilder()
            .addTemporalCoordinates(
                conceptName: concept,
                temporalRangeType: .segment,
                timeOffsets: [0.0, 2.5]
            )
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.asTemporalCoordinates?.conceptName == concept)
    }
    
    // MARK: - Section Tests
    
    @Test("Add section with string title")
    func testAddSectionWithStringTitle() throws {
        let document = try ComprehensiveSRBuilder()
            .addSection("Findings") {
                ComprehensiveSectionContent.text("No significant abnormalities")
            }
            .build()
        
        #expect(document.rootContent.contentItems.count == 1)
        let section = document.rootContent.contentItems[0]
        #expect(section.valueType == .container)
        #expect(section.conceptName?.codeMeaning == "Findings")
        #expect(section.asContainer?.contentItems.count == 1)
    }
    
    @Test("Add section with coded concept title")
    func testAddSectionWithCodedConcept() throws {
        let title = CodedConcept.findings
        
        let document = try ComprehensiveSRBuilder()
            .addSection(title) {
                ComprehensiveSectionContent.text("Normal appearance")
            }
            .build()
        
        let section = document.rootContent.contentItems[0]
        #expect(section.conceptName == title)
    }
    
    @Test("Add section with measurements and coordinates")
    func testAddSectionWithMeasurementsAndCoordinates() throws {
        let document = try ComprehensiveSRBuilder()
            .addSection("Lesion Analysis") {
                ComprehensiveSectionContent.text("Hepatic lesion identified")
                ComprehensiveSectionContent.numeric(
                    conceptName: CodedConcept.diameter,
                    value: 25.0,
                    units: UCUMUnit.millimeter.concept
                )
                ComprehensiveSectionContent.circle(
                    conceptName: CodedConcept.imageRegion,
                    centerColumn: 200.0,
                    centerRow: 200.0,
                    edgeColumn: 220.0,
                    edgeRow: 200.0
                )
            }
            .build()
        
        let section = document.rootContent.contentItems[0]
        #expect(section.asContainer?.contentItems.count == 3)
        
        let items = section.asContainer!.contentItems
        #expect(items[0].valueType == .text)
        #expect(items[1].valueType == .num)
        #expect(items[2].valueType == .scoord)
    }
    
    @Test("Add nested sections")
    func testAddNestedSections() throws {
        let document = try ComprehensiveSRBuilder()
            .addSection("Report") {
                ComprehensiveSectionContent.subsection("Findings", items: [
                    ComprehensiveSectionContent.text("Finding 1"),
                    ComprehensiveSectionContent.text("Finding 2")
                ])
            }
            .build()
        
        let section = document.rootContent.contentItems[0]
        let nestedSection = section.asContainer?.contentItems[0]
        #expect(nestedSection?.valueType == .container)
        #expect(nestedSection?.asContainer?.contentItems.count == 2)
    }
    
    // MARK: - Common Section Shortcuts
    
    @Test("Add findings section")
    func testAddFindings() throws {
        let document = try ComprehensiveSRBuilder()
            .addFindings("Normal findings")
            .build()
        
        let section = document.rootContent.contentItems[0]
        #expect(section.conceptName == CodedConcept.findings)
    }
    
    @Test("Add impression section")
    func testAddImpression() throws {
        let document = try ComprehensiveSRBuilder()
            .addImpression("No significant abnormalities")
            .build()
        
        let section = document.rootContent.contentItems[0]
        #expect(section.conceptName == CodedConcept.impression)
    }
    
    @Test("Add clinical history section")
    func testAddClinicalHistory() throws {
        let document = try ComprehensiveSRBuilder()
            .addClinicalHistory("Patient presents with chest pain")
            .build()
        
        let section = document.rootContent.contentItems[0]
        #expect(section.conceptName == CodedConcept.clinicalHistory)
    }
    
    @Test("Add measurements section")
    func testAddMeasurements() throws {
        let document = try ComprehensiveSRBuilder()
            .addMeasurements {
                ComprehensiveSectionContent.numeric(value: 10.0, units: UCUMUnit.millimeter.concept)
                ComprehensiveSectionContent.numeric(value: 20.0, units: UCUMUnit.millimeter.concept)
            }
            .build()
        
        let section = document.rootContent.contentItems[0]
        #expect(section.conceptName == CodedConcept.measurements)
        #expect(section.asContainer?.contentItems.count == 2)
    }
    
    // MARK: - Reference Content Tests
    
    @Test("Add image reference")
    func testAddImageReference() throws {
        let document = try ComprehensiveSRBuilder()
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
    func testAddImageReferenceWithFrames() throws {
        let document = try ComprehensiveSRBuilder()
            .addImageReference(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: "1.2.3.4.5",
                frameNumbers: [1, 2, 3]
            )
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.asImage?.imageReference.frameNumbers == [1, 2, 3])
    }
    
    @Test("Add waveform reference")
    func testAddWaveformReference() throws {
        let document = try ComprehensiveSRBuilder()
            .addWaveformReference(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.9.1.1",
                sopInstanceUID: "1.2.3.4.5.6.7.8.10"
            )
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.valueType == .waveform)
    }
    
    @Test("Add code content")
    func testAddCode() throws {
        let conceptName = CodedConcept(
            codeValue: "121071",
            codingSchemeDesignator: "DCM",
            codeMeaning: "Finding"
        )
        let value = CodedConcept(
            codeValue: "F-01776",
            codingSchemeDesignator: "SRT",
            codeMeaning: "Normal"
        )
        
        let document = try ComprehensiveSRBuilder()
            .addCode(conceptName: conceptName, value: value)
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.valueType == .code)
        #expect(item.asCode?.conceptCode == value)
    }
    
    // MARK: - Date/Time Content Tests
    
    @Test("Add date content")
    func testAddDate() throws {
        let document = try ComprehensiveSRBuilder()
            .addDate(date: "20240115")
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.valueType == .date)
        #expect(item.asDate?.dateValue == "20240115")
    }
    
    @Test("Add time content")
    func testAddTime() throws {
        let document = try ComprehensiveSRBuilder()
            .addTime(time: "143025")
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.valueType == .time)
        #expect(item.asTime?.timeValue == "143025")
    }
    
    @Test("Add datetime content")
    func testAddDateTime() throws {
        let document = try ComprehensiveSRBuilder()
            .addDateTime(datetime: "20240115143025")
            .build()
        
        let item = document.rootContent.contentItems[0]
        #expect(item.valueType == .datetime)
        #expect(item.asDateTime?.dateTimeValue == "20240115143025")
    }
    
    // MARK: - Validation Tests
    
    @Test("Validation passes for allowed value types")
    func testValidationPassesForAllowedTypes() throws {
        // All these types are allowed in Comprehensive SR
        let document = try ComprehensiveSRBuilder()
            .addText("Test")
            .addNumeric(value: 10.0)
            .addSpatialCoordinates(graphicType: .point, graphicData: [100.0, 100.0])
            .addTemporalCoordinates(temporalRangeType: .point, timeOffsets: [0.0])
            .build()
        
        #expect(document.rootContent.contentItems.count == 4)
    }
    
    @Test("Validation fails for SCOORD3D in Comprehensive SR")
    func testValidationFailsForSCOORD3D() throws {
        let builder = ComprehensiveSRBuilder()
            .addItem(AnyContentItem(SpatialCoordinates3DContentItem(
                graphicType: .point,
                graphicData: [100.0, 100.0, 100.0]
            )))
        
        #expect(throws: ComprehensiveSRBuilder.BuildError.self) {
            try builder.build()
        }
    }
    
    @Test("Validation can be skipped")
    func testValidationCanBeSkipped() throws {
        // With validation disabled, SCOORD3D won't cause an error
        let document = try ComprehensiveSRBuilder(validateOnBuild: false)
            .addItem(AnyContentItem(SpatialCoordinates3DContentItem(
                graphicType: .point,
                graphicData: [100.0, 100.0, 100.0]
            )))
            .build()
        
        // Document is created even with invalid content
        #expect(document.rootContent.contentItems.count == 1)
    }
    
    // MARK: - Full Document Tests
    
    @Test("Build complete measurement report")
    func testBuildCompleteMeasurementReport() throws {
        let document = try ComprehensiveSRBuilder()
            .withPatientID("PAT123")
            .withPatientName("Doe^John")
            .withStudyInstanceUID("1.2.3.4.5")
            .withSeriesInstanceUID("1.2.3.4.6")
            .withDocumentTitle("Liver Lesion Measurement Report")
            .withCompletionFlag(.complete)
            .withVerificationFlag(.verified)
            .addClinicalHistory("Patient presents for follow-up of hepatic lesion")
            .addFindings("Hepatic lesion identified in segment VII")
            .addSection("Measurements") {
                ComprehensiveSectionContent.text("Lesion measurements")
                ComprehensiveSectionContent.numeric(
                    conceptName: CodedConcept.diameter,
                    value: 25.0,
                    units: UCUMUnit.millimeter.concept
                )
                ComprehensiveSectionContent.circle(
                    conceptName: CodedConcept.imageRegion,
                    centerColumn: 200.0,
                    centerRow: 200.0,
                    edgeColumn: 225.0,
                    edgeRow: 200.0
                )
            }
            .addImpression("Stable hepatic lesion, recommend follow-up in 6 months")
            .build()
        
        #expect(document.patientID == "PAT123")
        #expect(document.patientName == "Doe^John")
        #expect(document.completionFlag == .complete)
        #expect(document.verificationFlag == .verified)
        #expect(document.documentTitle?.codeMeaning == "Liver Lesion Measurement Report")
        #expect(document.rootContent.contentItems.count == 4)
        
        // Verify section content
        let measurementsSection = document.rootContent.contentItems[2]
        #expect(measurementsSection.asContainer?.contentItems.count == 3)
    }
    
    // MARK: - ComprehensiveSectionContent Tests
    
    @Test("Section content - text creation")
    func testSectionContentText() {
        let item = ComprehensiveSectionContent.text("Test value")
        #expect(item.valueType == .text)
        #expect(item.asText?.textValue == "Test value")
    }
    
    @Test("Section content - labeled text creation")
    func testSectionContentLabeledText() {
        let item = ComprehensiveSectionContent.labeledText(label: "Label", value: "Value")
        #expect(item.asText?.textValue == "Value")
        #expect(item.conceptName?.codeMeaning == "Label")
    }
    
    @Test("Section content - numeric creation")
    func testSectionContentNumeric() {
        let item = ComprehensiveSectionContent.numeric(value: 42.0, units: UCUMUnit.millimeter.concept)
        #expect(item.valueType == .num)
        #expect(item.asNumeric?.value == 42.0)
    }
    
    @Test("Section content - measurement creation")
    func testSectionContentMeasurement() {
        let item = ComprehensiveSectionContent.measurement(
            label: "Diameter",
            value: 25.0,
            units: UCUMUnit.millimeter.concept
        )
        #expect(item.asNumeric?.value == 25.0)
        #expect(item.conceptName?.codeMeaning == "Diameter")
    }
    
    @Test("Section content - spatial coordinates creation")
    func testSectionContentSpatialCoordinates() {
        let item = ComprehensiveSectionContent.spatialCoordinates(
            graphicType: .polygon,
            graphicData: [100.0, 100.0, 200.0, 100.0, 200.0, 200.0]
        )
        #expect(item.valueType == .scoord)
        #expect(item.asSpatialCoordinates?.graphicType == .polygon)
    }
    
    @Test("Section content - point creation")
    func testSectionContentPoint() {
        let item = ComprehensiveSectionContent.point(column: 100.0, row: 200.0)
        #expect(item.asSpatialCoordinates?.graphicType == .point)
        #expect(item.asSpatialCoordinates?.graphicData == [100.0, 200.0])
    }
    
    @Test("Section content - polyline creation")
    func testSectionContentPolyline() {
        let item = ComprehensiveSectionContent.polyline(points: [(100.0, 100.0), (200.0, 200.0)])
        #expect(item.asSpatialCoordinates?.graphicType == .polyline)
    }
    
    @Test("Section content - polygon creation is a closed POLYLINE")
    func testSectionContentPolygon() {
        let item = ComprehensiveSectionContent.polygon(points: [
            (100.0, 100.0),
            (200.0, 100.0),
            (200.0, 200.0)
        ])
        #expect(item.asSpatialCoordinates?.graphicType == .polyline)
        #expect(item.asSpatialCoordinates?.graphicData == [100.0, 100.0, 200.0, 100.0, 200.0, 200.0, 100.0, 100.0])
    }
    
    @Test("Section content - circle creation")
    func testSectionContentCircle() {
        let item = ComprehensiveSectionContent.circle(
            centerColumn: 150.0,
            centerRow: 150.0,
            edgeColumn: 170.0,
            edgeRow: 150.0
        )
        #expect(item.asSpatialCoordinates?.graphicType == .circle)
    }
    
    @Test("Section content - temporal coordinates with sample positions")
    func testSectionContentTemporalSamplePositions() {
        let item = ComprehensiveSectionContent.temporalCoordinates(
            temporalRangeType: .point,
            samplePositions: [100, 200]
        )
        #expect(item.valueType == .tcoord)
        #expect(item.asTemporalCoordinates?.referencedSamplePositions == [100, 200])
    }
    
    @Test("Section content - temporal coordinates with time offsets")
    func testSectionContentTemporalTimeOffsets() {
        let item = ComprehensiveSectionContent.temporalCoordinates(
            temporalRangeType: .segment,
            timeOffsets: [0.0, 1.0]
        )
        #expect(item.asTemporalCoordinates?.referencedTimeOffsets == [0.0, 1.0])
    }
    
    @Test("Section content - temporal coordinates with datetime")
    func testSectionContentTemporalDateTime() {
        let item = ComprehensiveSectionContent.temporalCoordinates(
            temporalRangeType: .multipoint,
            dateTimes: ["20240115"]
        )
        #expect(item.asTemporalCoordinates?.referencedDateTime == ["20240115"])
    }
    
    @Test("Section content - code creation")
    func testSectionContentCode() {
        let value = CodedConcept(codeValue: "T-D4000", codingSchemeDesignator: "SRT", codeMeaning: "Liver")
        let item = ComprehensiveSectionContent.code(conceptName: nil, value: value)
        #expect(item.valueType == .code)
        #expect(item.asCode?.conceptCode == value)
    }
    
    @Test("Section content - image reference creation")
    func testSectionContentImageReference() {
        let item = ComprehensiveSectionContent.imageReference(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5"
        )
        #expect(item.valueType == .image)
    }
    
    @Test("Section content - waveform reference creation")
    func testSectionContentWaveformReference() {
        let item = ComprehensiveSectionContent.waveformReference(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.9.1.1",
            sopInstanceUID: "1.2.3.4.5"
        )
        #expect(item.valueType == .waveform)
    }
    
    @Test("Section content - subsection creation")
    func testSectionContentSubsection() {
        let item = ComprehensiveSectionContent.subsection("Nested", items: [
            ComprehensiveSectionContent.text("Nested text")
        ])
        #expect(item.valueType == .container)
        #expect(item.asContainer?.contentItems.count == 1)
    }
    
    @Test("Section content - date creation")
    func testSectionContentDate() {
        let item = ComprehensiveSectionContent.date(date: "20240115")
        #expect(item.valueType == .date)
        #expect(item.asDate?.dateValue == "20240115")
    }
    
    @Test("Section content - time creation")
    func testSectionContentTime() {
        let item = ComprehensiveSectionContent.time(time: "143025")
        #expect(item.valueType == .time)
        #expect(item.asTime?.timeValue == "143025")
    }
    
    @Test("Section content - datetime creation")
    func testSectionContentDatetime() {
        let item = ComprehensiveSectionContent.datetime(datetime: "20240115143025")
        #expect(item.valueType == .datetime)
        #expect(item.asDateTime?.dateTimeValue == "20240115143025")
    }
    
    @Test("Section content - person name creation")
    func testSectionContentPersonName() {
        let item = ComprehensiveSectionContent.personName(name: "Doe^John")
        #expect(item.valueType == .pname)
        #expect(item.asPersonName?.personName == "Doe^John")
    }

    // MARK: - Concept Constants (PS3.16 2026a)

    @Test("regionOfInterest is (130488, DCM, \"Region in Space\") per PS3.16 2026a Table D-1 / TID 1410 row 8b")
    func testRegionOfInterestConcept() {
        #expect(CodedConcept.regionOfInterest.codeValue == "130488")
        #expect(CodedConcept.regionOfInterest.codingSchemeDesignator == "DCM")
        #expect(CodedConcept.regionOfInterest.codeMeaning == "Region in Space")
    }

    @Test("measurementLocation is (363698007, SCT, \"Finding Site\") per PS3.16 2026a CID 9000 / TID 301 row 5")
    func testMeasurementLocationConcept() {
        #expect(CodedConcept.measurementLocation.codeValue == "363698007")
        #expect(CodedConcept.measurementLocation.codingSchemeDesignator == "SCT")
        #expect(CodedConcept.measurementLocation.codeMeaning == "Finding Site")
    }

    @Test("temporalExtent is (130532, DCM, \"Duration of Time Period\") per PS3.16 2026a CID 10073")
    func testTemporalExtentConcept() {
        #expect(CodedConcept.temporalExtent.codeValue == "130532")
        #expect(CodedConcept.temporalExtent.codingSchemeDesignator == "DCM")
        #expect(CodedConcept.temporalExtent.codeMeaning == "Duration of Time Period")
    }

    @Test("imageRegion is (111030, DCM, \"Image Region\") per PS3.16 2026a TID 4104 row 21")
    func testImageRegionConcept() {
        #expect(CodedConcept.imageRegion.codeValue == "111030")
        #expect(CodedConcept.imageRegion.codingSchemeDesignator == "DCM")
        #expect(CodedConcept.imageRegion.codeMeaning == "Image Region")
    }
}
