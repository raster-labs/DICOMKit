import Testing
import Foundation
import DICOMCore
@testable import DICOMKit

// MARK: - MeasurementReportBuilder Tests

@Suite("MeasurementReportBuilder Tests")
struct MeasurementReportBuilderTests {
    
    // MARK: - Basic Builder Tests
    
    @Test("Builder initialization with default values")
    func testBuilderInitialization() {
        let builder = MeasurementReportBuilder()
        
        #expect(builder.validateOnBuild == true)
        #expect(builder.completionFlag == .partial)
        #expect(builder.verificationFlag == .unverified)
        #expect(builder.imageLibraryEntries.isEmpty)
        #expect(builder.measurementGroups.isEmpty)
    }
    
    @Test("Builder initialization with validation disabled")
    func testBuilderWithValidationDisabled() {
        let builder = MeasurementReportBuilder(validateOnBuild: false)
        #expect(builder.validateOnBuild == false)
    }
    
    @Test("Build minimal document")
    func testBuildMinimalDocument() throws {
        let document = try MeasurementReportBuilder()
            .build()
        
        #expect(!document.sopInstanceUID.isEmpty)
        #expect(document.sopClassUID == SRDocumentType.comprehensiveSR.sopClassUID)
        #expect(document.modality == "SR")
        // Default title should be Imaging Measurement Report
        #expect(document.documentTitle?.codeValue == "126000")
    }
    
    // MARK: - Document Identification Tests
    
    @Test("Set SOP Instance UID")
    func testSetSOPInstanceUID() throws {
        let uid = "1.2.3.4.5.6.7.8.9"
        let document = try MeasurementReportBuilder()
            .withSOPInstanceUID(uid)
            .build()
        
        #expect(document.sopInstanceUID == uid)
    }
    
    @Test("Set Study Instance UID")
    func testSetStudyInstanceUID() throws {
        let uid = "1.2.3.4.5.6.7.8.10"
        let document = try MeasurementReportBuilder()
            .withStudyInstanceUID(uid)
            .build()
        
        #expect(document.studyInstanceUID == uid)
    }
    
    @Test("Set Series Instance UID")
    func testSetSeriesInstanceUID() throws {
        let uid = "1.2.3.4.5.6.7.8.11"
        let document = try MeasurementReportBuilder()
            .withSeriesInstanceUID(uid)
            .build()
        
        #expect(document.seriesInstanceUID == uid)
    }
    
    @Test("Set Instance Number")
    func testSetInstanceNumber() {
        let builder = MeasurementReportBuilder()
            .withInstanceNumber("5")
        
        #expect(builder.instanceNumber == "5")
    }
    
    // MARK: - Patient Information Tests
    
    @Test("Set Patient ID")
    func testSetPatientID() throws {
        let document = try MeasurementReportBuilder()
            .withPatientID("PAT123")
            .build()
        
        #expect(document.patientID == "PAT123")
    }
    
    @Test("Set Patient Name")
    func testSetPatientName() throws {
        let document = try MeasurementReportBuilder()
            .withPatientName("Doe^John")
            .build()
        
        #expect(document.patientName == "Doe^John")
    }
    
    @Test("Set Patient Birth Date")
    func testSetPatientBirthDate() {
        let builder = MeasurementReportBuilder()
            .withPatientBirthDate("19800101")
        
        #expect(builder.patientBirthDate == "19800101")
    }
    
    @Test("Set Patient Sex")
    func testSetPatientSex() {
        let builder = MeasurementReportBuilder()
            .withPatientSex("M")
        
        #expect(builder.patientSex == "M")
    }
    
    // MARK: - Study Information Tests
    
    @Test("Set Study Date")
    func testSetStudyDate() throws {
        let document = try MeasurementReportBuilder()
            .withStudyDate("20240115")
            .build()
        
        #expect(document.studyDate == "20240115")
    }
    
    @Test("Set Study Time")
    func testSetStudyTime() throws {
        let document = try MeasurementReportBuilder()
            .withStudyTime("143025")
            .build()
        
        #expect(document.studyTime == "143025")
    }
    
    @Test("Set Study Description")
    func testSetStudyDescription() {
        let builder = MeasurementReportBuilder()
            .withStudyDescription("CT Chest")
        
        #expect(builder.studyDescription == "CT Chest")
    }
    
    @Test("Set Accession Number")
    func testSetAccessionNumber() throws {
        let document = try MeasurementReportBuilder()
            .withAccessionNumber("ACC123")
            .build()
        
        #expect(document.accessionNumber == "ACC123")
    }
    
    // MARK: - Document Title Tests
    
    @Test("Set document title with coded concept")
    func testSetDocumentTitleCoded() throws {
        let title = MeasurementReportDocumentTitle.dynamicContrastMRMeasurementReport
        let document = try MeasurementReportBuilder()
            .withDocumentTitle(title)
            .build()

        #expect(document.documentTitle?.codeValue == "126002")
        #expect(document.documentTitle?.codeMeaning == "Dynamic Contrast MR Measurement Report")
    }
    
    @Test("Set imaging measurement report title convenience")
    func testSetImagingMeasurementReportTitle() throws {
        let document = try MeasurementReportBuilder()
            .withImagingMeasurementReportTitle()
            .build()
        
        #expect(document.documentTitle?.codeValue == "126000")
        #expect(document.documentTitle?.codingSchemeDesignator == "DCM")
    }
    
    // MARK: - Document Status Tests
    
    @Test("Set completion flag to complete")
    func testSetCompletionFlag() throws {
        let document = try MeasurementReportBuilder()
            .withCompletionFlag(.complete)
            .build()
        
        #expect(document.completionFlag == .complete)
    }
    
    @Test("Set verification flag to verified")
    func testSetVerificationFlag() throws {
        let document = try MeasurementReportBuilder()
            .withVerificationFlag(.verified)
            .build()
        
        #expect(document.verificationFlag == .verified)
    }
    
    @Test("Set preliminary flag")
    func testSetPreliminaryFlag() {
        let builder = MeasurementReportBuilder()
            .withPreliminaryFlag(.preliminary)
        
        #expect(builder.preliminaryFlag == .preliminary)
    }
    
    // MARK: - Image Library Tests
    
    @Test("Add image library entry")
    func testAddImageLibraryEntry() throws {
        let document = try MeasurementReportBuilder()
            .addImageLibraryEntry(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: "1.2.3.4.5.6.7.8.9"
            )
            .build()
        
        // Verify the document has an image library container
        let imageLibraryContainer = document.rootContent.contentItems.first { item in
            item.asContainer?.conceptName?.codeValue == "111028"
        }
        #expect(imageLibraryContainer != nil)
    }
    
    @Test("Add image library entry with modality")
    func testAddImageLibraryEntryWithModality() {
        let modality = CodedConcept(
            codeValue: "CT",
            codingSchemeDesignator: "DCM",
            codeMeaning: "Computed Tomography"
        )
        
        let builder = MeasurementReportBuilder()
            .addImageLibraryEntry(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: "1.2.3.4.5.6.7.8.9",
                modality: modality
            )
        
        #expect(builder.imageLibraryEntries.count == 1)
        #expect(builder.imageLibraryEntries[0].modality?.codeValue == "CT")
    }
    
    @Test("Add multiple image library entries")
    func testAddMultipleImageLibraryEntries() throws {
        let entries = [
            ImageLibraryEntry(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: "1.2.3.4.5.6.7.8.9"
            ),
            ImageLibraryEntry(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: "1.2.3.4.5.6.7.8.10"
            )
        ]
        
        let builder = MeasurementReportBuilder()
            .addImageLibraryEntries(entries)
        
        #expect(builder.imageLibraryEntries.count == 2)
    }
    
    // MARK: - Measurement Group Tests
    
    @Test("Add measurement group with tracking")
    func testAddMeasurementGroupWithTracking() throws {
        let document = try MeasurementReportBuilder()
            .addMeasurementGroup(
                trackingIdentifier: "Lesion 1",
                trackingUID: "1.2.3.4.5.6.7.8.100"
            ) {
                MeasurementGroupContent.measurement(
                    conceptName: CodedConcept(
                        codeValue: "410668003",
                        codingSchemeDesignator: "SCT",
                        codeMeaning: "Length"
                    ),
                    value: 25.5,
                    units: UCUMUnit.millimeter.concept
                )
            }
            .build()
        
        // Verify imaging measurements container exists
        let imagingMeasurements = document.rootContent.contentItems.first { item in
            item.asContainer?.conceptName?.codeValue == "126010"
        }
        #expect(imagingMeasurements != nil)
    }
    
    @Test("Add measurement group with auto-generated UID")
    func testAddMeasurementGroupAutoUID() {
        let builder = MeasurementReportBuilder()
            .addMeasurementGroup(
                trackingIdentifier: "Lesion 2"
            ) {
                MeasurementGroupContentHelper.lengthMM(value: 15.0)
            }
        
        #expect(builder.measurementGroups.count == 1)
        #expect(builder.measurementGroups[0].trackingIdentifier == "Lesion 2")
        #expect(!builder.measurementGroups[0].trackingUID.isEmpty)
    }
    
    @Test("Add measurement group with finding")
    func testAddMeasurementGroupWithFinding() {
        let finding = CodedConcept(
            codeValue: "4147007",
            codingSchemeDesignator: "SCT",
            codeMeaning: "Mass"
        )
        
        let group = MeasurementGroupData(
            trackingIdentifier: "Mass 1",
            trackingUID: "1.2.3.4.5.6.7.8.200",
            finding: finding
        )
        
        let builder = MeasurementReportBuilder()
            .addMeasurementGroup(group)
        
        #expect(builder.measurementGroups.count == 1)
        #expect(builder.measurementGroups[0].finding?.codeValue == "4147007")
    }
    
    // MARK: - Measurement Group Content Tests
    
    @Test("Measurement group content - length measurement")
    func testMeasurementGroupContentLength() {
        let content = MeasurementGroupContentHelper.lengthMM(value: 10.5)
        let item = content.toContentItem()
        
        #expect(item.valueType == .num)
    }
    
    @Test("Measurement group content - long axis measurement")
    func testMeasurementGroupContentLongAxis() {
        let content = MeasurementGroupContentHelper.longAxisMM(value: 25.0)
        _ = content.toContentItem()
        
        if case .measurement(let conceptName, let value, let units) = content {
            #expect(conceptName?.codeValue == "103339001")
            #expect(value == 25.0)
            #expect(units?.codeValue == "mm")
        } else {
            Issue.record("Expected measurement case")
        }
    }
    
    @Test("Measurement group content - short axis measurement")
    func testMeasurementGroupContentShortAxis() {
        let content = MeasurementGroupContentHelper.shortAxisMM(value: 15.0)
        
        if case .measurement(let conceptName, let value, _) = content {
            #expect(conceptName?.codeValue == "103340004")
            #expect(value == 15.0)
        } else {
            Issue.record("Expected measurement case")
        }
    }
    
    @Test("Measurement group content - area measurement")
    func testMeasurementGroupContentArea() {
        let content = MeasurementGroupContentHelper.areaMM2(value: 100.0)
        
        if case .measurement(let conceptName, let value, let units) = content {
            #expect(conceptName?.codeValue == "42798000")
            #expect(value == 100.0)
            #expect(units?.codeValue == "mm2")
        } else {
            Issue.record("Expected measurement case")
        }
    }
    
    @Test("Measurement group content - volume measurement")
    func testMeasurementGroupContentVolume() {
        let content = MeasurementGroupContentHelper.volumeMM3(value: 1000.0)
        
        if case .measurement(let conceptName, let value, _) = content {
            #expect(conceptName?.codeValue == "118565006")
            #expect(value == 1000.0)
        } else {
            Issue.record("Expected measurement case")
        }
    }
    
    @Test("Measurement group content - image reference")
    func testMeasurementGroupContentImageReference() {
        let content = MeasurementGroupContentHelper.imageReference(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9"
        )
        let item = content.toContentItem()
        
        #expect(item.valueType == .image)
    }
    
    @Test("Measurement group content - spatial coordinates")
    func testMeasurementGroupContentCoordinates() {
        let content = MeasurementGroupContentHelper.coordinates(
            graphicType: .circle,
            graphicData: [100.0, 100.0, 120.0, 100.0]
        )
        let item = content.toContentItem()
        
        #expect(item.valueType == .scoord)
    }
    
    // MARK: - Qualitative Evaluation Tests
    
    @Test("Add qualitative evaluation")
    func testAddQualitativeEvaluation() {
        let evaluation = CodedConcept(
            codeValue: "260415000",
            codingSchemeDesignator: "SCT",
            codeMeaning: "Not detected"
        )
        
        let builder = MeasurementReportBuilder()
            .addQualitativeEvaluation(
                conceptName: CodedConcept(
                    codeValue: "121071",
                    codingSchemeDesignator: "DCM",
                    codeMeaning: "Finding"
                ),
                value: evaluation
            )
        
        #expect(builder.qualitativeEvaluations.count == 1)
    }
    
    // MARK: - Procedure Reported Tests
    
    @Test("Add procedure reported")
    func testAddProcedureReported() {
        let procedure = CodedConcept(
            codeValue: "77477000",
            codingSchemeDesignator: "SCT",
            codeMeaning: "CT of abdomen"
        )
        
        let builder = MeasurementReportBuilder()
            .addProcedureReported(procedure)
        
        #expect(builder.proceduresReported.count == 1)
        #expect(builder.proceduresReported[0].codeValue == "77477000")
    }
    
    // MARK: - Language Tests
    
    @Test("Set language of content")
    func testSetLanguage() {
        let language = CodedConcept(
            codeValue: "en",
            codingSchemeDesignator: "RFC5646",
            codeMeaning: "English"
        )
        
        let builder = MeasurementReportBuilder()
            .withLanguage(language)
        
        #expect(builder.languageOfContent?.codeValue == "en")
    }
    
    @Test("Set language with country")
    func testSetLanguageWithCountry() {
        let language = CodedConcept(
            codeValue: "en",
            codingSchemeDesignator: "RFC5646",
            codeMeaning: "English"
        )
        let country = CodedConcept(
            codeValue: "US",
            codingSchemeDesignator: "ISO3166_1",
            codeMeaning: "United States"
        )
        
        let builder = MeasurementReportBuilder()
            .withLanguage(language, country: country)
        
        #expect(builder.languageOfContent?.codeValue == "en")
        #expect(builder.countryOfLanguage?.codeValue == "US")
    }
    
    // MARK: - Validation Tests
    
    @Test("Validation passes with valid tracking")
    func testValidationPassesWithValidTracking() throws {
        // Should not throw
        _ = try MeasurementReportBuilder()
            .addMeasurementGroup(
                trackingIdentifier: "Lesion 1",
                trackingUID: "1.2.3.4.5.6.7.8.100"
            ) {
                MeasurementGroupContentHelper.lengthMM(value: 10.0)
            }
            .build()
    }
    
    @Test("Validation fails with empty tracking identifier")
    func testValidationFailsEmptyTrackingIdentifier() {
        let group = MeasurementGroupData(
            trackingIdentifier: "",
            trackingUID: "1.2.3.4.5.6.7.8.100"
        )
        
        let builder = MeasurementReportBuilder()
            .addMeasurementGroup(group)
        
        #expect(throws: MeasurementReportBuilder.BuildError.missingTrackingIdentifier) {
            try builder.build()
        }
    }
    
    @Test("Validation fails with empty tracking UID")
    func testValidationFailsEmptyTrackingUID() {
        let group = MeasurementGroupData(
            trackingIdentifier: "Lesion 1",
            trackingUID: ""
        )
        
        let builder = MeasurementReportBuilder()
            .addMeasurementGroup(group)
        
        #expect(throws: MeasurementReportBuilder.BuildError.missingTrackingUID) {
            try builder.build()
        }
    }
    
    @Test("Validation disabled allows empty tracking")
    func testValidationDisabledAllowsEmptyTracking() throws {
        let group = MeasurementGroupData(
            trackingIdentifier: "",
            trackingUID: ""
        )
        
        // Should not throw when validation is disabled
        _ = try MeasurementReportBuilder(validateOnBuild: false)
            .addMeasurementGroup(group)
            .build()
    }
    
    // MARK: - Complete Report Tests
    
    @Test("Build complete measurement report")
    func testBuildCompleteMeasurementReport() throws {
        let document = try MeasurementReportBuilder()
            .withPatientID("12345")
            .withPatientName("Doe^John")
            .withStudyDate("20240115")
            .withAccessionNumber("ACC001")
            .withImagingMeasurementReportTitle()
            .withCompletionFlag(.complete)
            .withVerificationFlag(.verified)
            .addImageLibraryEntry(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: "1.2.3.4.5.6.7.8.9",
                modality: CodedConcept(
                    codeValue: "CT",
                    codingSchemeDesignator: "DCM",
                    codeMeaning: "Computed Tomography"
                )
            )
            .addMeasurementGroup(
                trackingIdentifier: "Liver Lesion",
                trackingUID: "1.2.3.4.5.6.7.8.100"
            ) {
                MeasurementGroupContentHelper.longAxisMM(value: 25.5)
                MeasurementGroupContentHelper.shortAxisMM(value: 18.2)
                MeasurementGroupContentHelper.areaMM2(value: 363.15)
                MeasurementGroupContentHelper.imageReference(
                    sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                    sopInstanceUID: "1.2.3.4.5.6.7.8.9",
                    frameNumbers: [1]
                )
            }
            .build()
        
        #expect(document.patientID == "12345")
        #expect(document.patientName == "Doe^John")
        #expect(document.studyDate == "20240115")
        #expect(document.accessionNumber == "ACC001")
        #expect(document.completionFlag == .complete)
        #expect(document.verificationFlag == .verified)
        #expect(document.documentTitle?.codeValue == "126000")
        
        // Check that image library exists
        let hasImageLibrary = document.rootContent.contentItems.contains { item in
            item.asContainer?.conceptName?.codeValue == "111028"
        }
        #expect(hasImageLibrary)
        
        // Check that imaging measurements exists
        let hasImagingMeasurements = document.rootContent.contentItems.contains { item in
            item.asContainer?.conceptName?.codeValue == "126010"
        }
        #expect(hasImagingMeasurements)
    }
    
    @Test("Build report with multiple measurement groups")
    func testBuildReportWithMultipleMeasurementGroups() throws {
        let document = try MeasurementReportBuilder()
            .addMeasurementGroup(
                trackingIdentifier: "Lesion 1",
                trackingUID: "1.2.3.4.5.6.7.8.100"
            ) {
                MeasurementGroupContentHelper.longAxisMM(value: 20.0)
            }
            .addMeasurementGroup(
                trackingIdentifier: "Lesion 2",
                trackingUID: "1.2.3.4.5.6.7.8.101"
            ) {
                MeasurementGroupContentHelper.longAxisMM(value: 15.0)
            }
            .addMeasurementGroup(
                trackingIdentifier: "Lesion 3",
                trackingUID: "1.2.3.4.5.6.7.8.102"
            ) {
                MeasurementGroupContentHelper.longAxisMM(value: 10.0)
            }
            .build()
        
        // Count measurement groups in the imaging measurements container
        let imagingMeasurements = document.rootContent.contentItems.first { item in
            item.asContainer?.conceptName?.codeValue == "126010"
        }
        let measurementGroupCount = imagingMeasurements?.asContainer?.contentItems.filter { item in
            item.asContainer?.conceptName?.codeValue == "125007"
        }.count ?? 0
        
        #expect(measurementGroupCount == 3)
    }
}

// MARK: - MeasurementReportDocumentTitle Tests

@Suite("MeasurementReportDocumentTitle Tests")
struct MeasurementReportDocumentTitleTests {

    // PS3.16 2026a Table CID 7021 Measurement Report Document Title, all four rows.

    @Test("CID 7021 row: (126000, DCM, Imaging Measurement Report)")
    func testImagingMeasurementReportTitle() {
        let title = MeasurementReportDocumentTitle.imagingMeasurementReport
        #expect(title.codeValue == "126000")
        #expect(title.codingSchemeDesignator == "DCM")
        #expect(title.codeMeaning == "Imaging Measurement Report")
    }

    @Test("CID 7021 row: (126001, DCM, Oncology Measurement Report)")
    func testOncologyMeasurementReportTitle() {
        let title = MeasurementReportDocumentTitle.oncologyMeasurementReport
        #expect(title.codeValue == "126001")
        #expect(title.codingSchemeDesignator == "DCM")
        #expect(title.codeMeaning == "Oncology Measurement Report")
    }

    @Test("CID 7021 row: (126002, DCM, Dynamic Contrast MR Measurement Report)")
    func testDynamicContrastMRMeasurementReportTitle() {
        let title = MeasurementReportDocumentTitle.dynamicContrastMRMeasurementReport
        #expect(title.codeValue == "126002")
        #expect(title.codingSchemeDesignator == "DCM")
        #expect(title.codeMeaning == "Dynamic Contrast MR Measurement Report")
    }

    @Test("CID 7021 row: (126003, DCM, PET Measurement Report)")
    func testPETMeasurementReportTitle() {
        let title = MeasurementReportDocumentTitle.petMeasurementReport
        #expect(title.codeValue == "126003")
        #expect(title.codingSchemeDesignator == "DCM")
        #expect(title.codeMeaning == "PET Measurement Report")
    }

    @Test("Deprecated misnamed titles resolve to the CID 7021 concepts")
    @available(*, deprecated)
    func testDeprecatedTitlesCarryStandardValues() {
        #expect(MeasurementReportDocumentTitle.lesionMeasurementReport
                == MeasurementReportDocumentTitle.dynamicContrastMRMeasurementReport)
        #expect(MeasurementReportDocumentTitle.ctPerfusionReport
                == MeasurementReportDocumentTitle.petMeasurementReport)
    }
}

// MARK: - TID 1500 Structure Tests

/// Pins the rows of PS3.16 2026a Tables TID 1500, TID 1204, TID 1600/1601/1602, TID 1501
/// and TID 1502 that the builder can express: relationship type, value type, concept name
/// and nesting.
@Suite("TID 1500 Structure Tests")
struct MeasurementReportTID1500StructureTests {

    private func code(_ v: String, _ s: String, _ m: String) -> CodedConcept {
        CodedConcept(codeValue: v, codingSchemeDesignator: s, codeMeaning: m)
    }

    private func buildFullReport() throws -> SRDocument {
        try MeasurementReportBuilder()
            .withLanguage(code("en", "RFC5646", "English"), country: code("US", "ISO3166_1", "United States"))
            .addProcedureReported(code("77477000", "SCT", "CT of abdomen"))
            .addImageLibraryEntry(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.1",
                modality: code("CT", "DCM", "Computed Tomography"))
            .addImageLibraryEntry(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.2",
                modality: code("CT", "DCM", "Computed Tomography"))
            .addImageLibraryEntry(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.4", sopInstanceUID: "1.2.3.3",
                modality: code("MR", "DCM", "Magnetic Resonance"),
                laterality: code("24028007", "SCT", "Right"))
            .addMeasurementGroup(MeasurementGroupData(
                trackingIdentifier: "Lesion 1",
                trackingUID: "1.2.3.4.5",
                activitySession: "1",
                timePoint: "Baseline",
                finding: nil,
                findingSite: code("10200004", "SCT", "Liver"),
                laterality: code("7771000", "SCT", "Left"),
                contents: [
                    MeasurementGroupContentHelper.longAxisMM(value: 25.5),
                    MeasurementGroupContentHelper.imageReference(
                        sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.1"),
                    .qualitativeEvaluation(conceptName: code("C0034375", "UMLS", "Qualitative Evaluations"),
                                           value: code("2", "99TEST", "Stable")),
                ]))
            .addQualitativeEvaluation(conceptName: code("121071", "DCM", "Finding"),
                                      value: code("260415000", "SCT", "Not detected"))
            .build()
    }

    @Test("TID 1500 row 1: root CONTAINER titled from CID 7021, SEPARATE")
    func testRoot() throws {
        let document = try buildFullReport()
        #expect(document.rootContent.conceptName == MeasurementReportDocumentTitle.imagingMeasurementReport)
        #expect(document.rootContent.continuityOfContent == .separate)
        #expect(document.sopClassUID == SRDocumentType.comprehensiveSR.sopClassUID)
        #expect(document.modality == "SR")
    }

    @Test("TID 1500 row 2 / TID 1204 row 1: HAS CONCEPT MOD CODE (121049, DCM)")
    func testLanguageRows() throws {
        let items = try buildFullReport().rootContent.contentItems
        let language = try #require(items.first { $0.conceptName?.codeValue == "121049" })
        #expect(language.valueType == .code)
        #expect(language.relationshipType == .hasConceptMod)
        #expect(language.conceptName?.codeMeaning == "Language of Content Item and Descendants")
        #expect(language.asCode?.conceptCode.codeValue == "en")

        // TID 1204 row 2 (">"): HAS CONCEPT MOD CODE (121046, DCM), nested in the language
        // item's Content Sequence (PS3.3 Table C.17-6), not a root-level sibling
        #expect(!items.contains { $0.conceptName?.codeValue == "121046" })
        #expect(language.contentItems.count == 1)
        let country = try #require(language.contentItems.first)
        #expect(country.conceptName?.codeValue == "121046")
        #expect(country.conceptName?.codeMeaning == "Country of Language")
        #expect(country.valueType == .code)
        #expect(country.relationshipType == .hasConceptMod)
    }

    @Test("TID 1500 row 4: HAS CONCEPT MOD CODE (121058, DCM, Procedure reported)")
    func testProcedureReportedRow() throws {
        let items = try buildFullReport().rootContent.contentItems
        let procedure = try #require(items.first { $0.conceptName?.codeValue == "121058" })
        #expect(procedure.valueType == .code)
        #expect(procedure.relationshipType == .hasConceptMod)
        #expect(procedure.conceptName?.codingSchemeDesignator == "DCM")
        #expect(procedure.conceptName?.codeMeaning == "Procedure reported")
    }

    @Test("TID 1500 row 5 / TID 1600 rows 1-4 / TID 1601 row 1 / TID 1602 rows 1, 3")
    func testImageLibraryRows() throws {
        let items = try buildFullReport().rootContent.contentItems
        let library = try #require(items.first { $0.conceptName?.codeValue == "111028" })
        #expect(library.valueType == .container)
        #expect(library.relationshipType == .contains)
        #expect(library.conceptName?.codeMeaning == "Image Library")

        // TID 1600 row 2: every child is an Image Library Group container, CONTAINS
        let groups = try #require(library.asContainer?.contentItems)
        #expect(groups.count == 2)
        for group in groups {
            #expect(group.valueType == .container)
            #expect(group.relationshipType == .contains)
            #expect(group.conceptName == CodedConcept(codeValue: "126200", codingSchemeDesignator: "DCM", codeMeaning: "Image Library Group"))
        }

        // Group 1: two CT images share one Modality descriptor
        let ctGroup = try #require(groups[0].asContainer)
        let ctDescriptors = ctGroup.contentItems.filter { $0.valueType == .code }
        let ctImages = ctGroup.contentItems.filter { $0.valueType == .image }
        #expect(ctDescriptors.count == 1)
        #expect(ctImages.count == 2)
        // TID 1600 row 3 → TID 1602 row 1: HAS ACQ CONTEXT CODE (121139, DCM, "Modality")
        #expect(ctDescriptors[0].relationshipType == .hasAcqContext)
        #expect(ctDescriptors[0].conceptName == CodedConcept(codeValue: "121139", codingSchemeDesignator: "DCM", codeMeaning: "Modality"))
        #expect(ctDescriptors[0].asCode?.conceptCode.codeValue == "CT")
        // TID 1600 row 4 → TID 1601 row 1: CONTAINS IMAGE, no concept name
        for image in ctImages {
            #expect(image.relationshipType == .contains)
            #expect(image.conceptName == nil)
        }
        #expect(ctImages.map { $0.asImage?.imageReference.sopReference.sopInstanceUID } == ["1.2.3.1", "1.2.3.2"])

        // Group 2: MR image with Modality and Image Laterality (TID 1602 rows 1 and 3)
        let mrGroup = try #require(groups[1].asContainer)
        let mrDescriptorNames = mrGroup.contentItems.compactMap { $0.asCode }.map { $0.conceptName?.codeValue }
        #expect(mrDescriptorNames == ["121139", "111027"])
        #expect(mrGroup.contentItems.compactMap { $0.asCode }.allSatisfy { $0.relationshipType == .hasAcqContext })
        #expect(mrGroup.contentItems.filter { $0.valueType == .image }.count == 1)
    }

    @Test("TID 1500 rows 6, 9 / TID 1501 rows 1, 1b, 2, 3, 4, 6, 10, 10b, 11")
    func testMeasurementGroupRows() throws {
        let items = try buildFullReport().rootContent.contentItems
        let measurements = try #require(items.first { $0.conceptName?.codeValue == "126010" })
        #expect(measurements.valueType == .container)
        #expect(measurements.relationshipType == .contains)
        #expect(measurements.conceptName?.codeMeaning == "Imaging Measurements")

        let group = try #require(measurements.asContainer?.contentItems.first)
        #expect(group.valueType == .container)
        #expect(group.relationshipType == .contains)
        #expect(group.conceptName == CodedConcept(codeValue: "125007", codingSchemeDesignator: "DCM", codeMeaning: "Measurement Group"))

        let rows = try #require(group.asContainer?.contentItems)
        // (relationship, value type, concept name code value) in template order
        let observed = rows.map { ($0.relationshipType, $0.valueType, $0.conceptName?.codeValue) }
        let expected: [(RelationshipType?, ContentItemValueType, String?)] = [
            (.hasObsContext, .text, "C67447"),        // 1b Activity Session
            (.hasObsContext, .text, "112039"),        // 2  Tracking Identifier
            (.hasObsContext, .uidref, "112040"),      // 3  Tracking Unique Identifier
            (.hasObsContext, .text, "C2348792"),      // 4  → TID 1502 row 3 Time Point
            (.hasConceptMod, .code, "363698007"),     // 6  Finding Site (row 7 nested in it)
            (.contains, .num, "103339001"),           // 10 → TID 300 row 1 NUM
            (.contains, .image, nil),                 // 10b IMAGE
            (.contains, .code, "C0034375"),           // 11 CODE $QualType
        ]
        #expect(observed.count == expected.count)
        for (o, e) in zip(observed, expected) {
            #expect(o.0 == e.0)
            #expect(o.1 == e.1)
            #expect(o.2 == e.2)
        }

        // Finding Site is written without a Finding (TID 1501 row 6 does not depend on row 3b)
        #expect(rows.contains { $0.conceptName?.codeValue == "363698007" })
        #expect(!rows.contains { $0.conceptName?.codeValue == "121071" })

        // Concept names carry the Table D-1 / SNOMED meanings the template prints
        #expect(rows[1].conceptName?.codeMeaning == "Tracking Identifier")
        #expect(rows[2].conceptName?.codeMeaning == "Tracking Unique Identifier")
        #expect(rows[4].conceptName == CodedConcept(codeValue: "363698007", codingSchemeDesignator: "SCT", codeMeaning: "Finding Site"))
        // Row 7 (">>"): HAS CONCEPT MOD CODE (272741003, SCT, "Laterality"), nested in the
        // Finding Site CODE's Content Sequence (PS3.3 Table C.17-6)
        #expect(!rows.contains { $0.conceptName?.codeValue == "272741003" })
        let laterality = try #require(rows[4].contentItems.first)
        #expect(rows[4].contentItems.count == 1)
        #expect(laterality.relationshipType == .hasConceptMod)
        #expect(laterality.valueType == .code)
        #expect(laterality.conceptName == CodedConcept(codeValue: "272741003", codingSchemeDesignator: "SCT", codeMeaning: "Laterality"))
        #expect(laterality.asCode?.conceptCode.codeValue == "7771000")
    }

    @Test("TID 1501 row 3b: CONTAINS CODE (121071, DCM, Finding)")
    func testFindingRow() throws {
        let document = try MeasurementReportBuilder()
            .addMeasurementGroup(trackingIdentifier: "L", trackingUID: "1.2.3",
                                 finding: code("4147007", "SCT", "Mass")) {
                MeasurementGroupContentHelper.lengthMM(value: 1)
            }
            .build()
        let group = try #require(document.rootContent.contentItems
            .first { $0.conceptName?.codeValue == "126010" }?.asContainer?.contentItems.first?.asContainer)
        let finding = try #require(group.contentItems.first { $0.conceptName?.codeValue == "121071" })
        #expect(finding.valueType == .code)
        #expect(finding.relationshipType == .contains)
        #expect(finding.conceptName?.codeMeaning == "Finding")
    }

    @Test("TID 1500 rows 12-13: CONTAINS CONTAINER (C0034375, UMLS) with CONTAINS CODE children")
    func testQualitativeEvaluationsRows() throws {
        let items = try buildFullReport().rootContent.contentItems
        let evaluations = try #require(items.first { $0.conceptName?.codeValue == "C0034375" })
        #expect(evaluations.valueType == .container)
        #expect(evaluations.relationshipType == .contains)
        #expect(evaluations.conceptName?.codingSchemeDesignator == "UMLS")
        let children = try #require(evaluations.asContainer?.contentItems)
        #expect(children.count == 1)
        #expect(children[0].valueType == .code)
        #expect(children[0].relationshipType == .contains)
    }

    @Test("Root row order follows TID 1500: 2, 4, 5, 6, 12")
    func testRootRowOrder() throws {
        let items = try buildFullReport().rootContent.contentItems
        let order = items.map { $0.conceptName?.codeValue }
        #expect(order == ["121049", "121058", "111028", "126010", "C0034375"])
    }

    @Test("Round trip through the serializer and parser keeps the TID 1500 structure and reads back the extractor fields")
    func testRoundTripAndExtraction() throws {
        let original = try buildFullReport()
        let dataSet = try SRDocumentSerializer().serialize(document: original)
        let parsed = try SRDocumentParser().parse(dataSet: dataSet)
        #expect(parsed.rootContent == original.rootContent)

        let report = try MeasurementReport.extract(from: parsed)
        #expect(report.languageOfContent?.codeValue == "en")
        #expect(report.countryOfLanguage?.codeValue == "US")
        #expect(report.proceduresReported.map(\.codeValue) == ["77477000"])
        #expect(report.imageLibraryEntries.map(\.sopReference.sopInstanceUID) == ["1.2.3.1", "1.2.3.2", "1.2.3.3"])
        #expect(report.measurementGroups.count == 1)
        let group = try #require(report.measurementGroups.first)
        #expect(group.findingSite?.codeValue == "10200004")
        #expect(group.findingType == nil)
        #expect(group.measurements.map(\.value) == [25.5])
        // Laterality (HAS CONCEPT MOD) is not an evaluation; the CONTAINS CODE is
        #expect(group.qualitativeEvaluations.map(\.codeValue) == ["2"])
        #expect(report.qualitativeEvaluations.map(\.codeValue) == ["260415000"])
    }

    @Test("Extractor tolerates the pre-2026-09-29 flat Image Library")
    func testExtractorReadsFlatImageLibrary() throws {
        let flatLibrary = ContainerContentItem(
            conceptName: code("111028", "DCM", "Image Library"),
            continuityOfContent: .separate,
            contentItems: [
                AnyContentItem(ImageContentItem(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "9.9.9", relationshipType: .contains)),
                AnyContentItem(CodeContentItem(conceptName: code("121139", "DCM", "Modality"), conceptCode: code("CT", "DCM", "Computed Tomography"), relationshipType: .hasAcqContext)),
            ],
            relationshipType: .contains)
        let root = ContainerContentItem(
            conceptName: MeasurementReportDocumentTitle.imagingMeasurementReport,
            continuityOfContent: .separate,
            contentItems: [AnyContentItem(flatLibrary)])
        let document = SRDocument(sopClassUID: SRDocumentType.comprehensiveSR.sopClassUID, sopInstanceUID: "1.2.3", rootContent: root)
        let report = try MeasurementReport.extract(from: document)
        #expect(report.imageLibraryEntries.map(\.sopReference.sopInstanceUID) == ["9.9.9"])
    }

    @Test("Extractor tolerates the pre-D31 Country of Language written beside the language item")
    func testExtractorReadsSiblingCountryOfLanguage() throws {
        // Before 2026-09-29 (D31) TID 1204 row 2 was written as the root-level sibling after row 1
        let root = ContainerContentItem(
            conceptName: MeasurementReportDocumentTitle.imagingMeasurementReport,
            continuityOfContent: .separate,
            contentItems: [
                AnyContentItem(CodeContentItem(conceptName: .languageOfContentItemAndDescendants,
                                               conceptCode: code("en", "RFC5646", "English"), relationshipType: .hasConceptMod)),
                AnyContentItem(CodeContentItem(conceptName: .countryOfLanguage,
                                               conceptCode: code("US", "ISO3166_1", "United States"), relationshipType: .hasConceptMod)),
            ])
        let document = SRDocument(sopClassUID: SRDocumentType.comprehensiveSR.sopClassUID, sopInstanceUID: "1.2.3", rootContent: root)
        let report = try MeasurementReport.extract(from: document)
        #expect(report.languageOfContent?.codeValue == "en")
        #expect(report.countryOfLanguage?.codeValue == "US")
    }
}

// MARK: - ImageLibraryEntry Tests

@Suite("ImageLibraryEntry Tests")
struct ImageLibraryEntryTests {
    
    @Test("Create basic entry")
    func testCreateBasicEntry() {
        let entry = ImageLibraryEntry(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9"
        )
        
        #expect(entry.sopClassUID == "1.2.840.10008.5.1.4.1.1.2")
        #expect(entry.sopInstanceUID == "1.2.3.4.5.6.7.8.9")
        #expect(entry.frameNumbers == nil)
        #expect(entry.modality == nil)
    }
    
    @Test("Create entry with all attributes")
    func testCreateEntryWithAllAttributes() {
        let modality = CodedConcept(
            codeValue: "CT",
            codingSchemeDesignator: "DCM",
            codeMeaning: "Computed Tomography"
        )
        let targetRegion = CodedConcept(
            codeValue: "818981001",
            codingSchemeDesignator: "SCT",
            codeMeaning: "Abdomen"
        )
        let laterality = CodedConcept(
            codeValue: "24028007",
            codingSchemeDesignator: "SCT",
            codeMeaning: "Right"
        )
        
        let entry = ImageLibraryEntry(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9",
            frameNumbers: [1, 2, 3],
            modality: modality,
            targetRegion: targetRegion,
            laterality: laterality
        )
        
        #expect(entry.frameNumbers == [1, 2, 3])
        #expect(entry.modality?.codeValue == "CT")
        #expect(entry.targetRegion?.codeValue == "818981001")
        #expect(entry.laterality?.codeValue == "24028007")
    }
}

// MARK: - MeasurementGroupData Tests

@Suite("MeasurementGroupData Tests")
struct MeasurementGroupDataTests {
    
    @Test("Create basic measurement group")
    func testCreateBasicGroup() {
        let group = MeasurementGroupData(
            trackingIdentifier: "Lesion 1",
            trackingUID: "1.2.3.4.5.6.7.8.100"
        )
        
        #expect(group.trackingIdentifier == "Lesion 1")
        #expect(group.trackingUID == "1.2.3.4.5.6.7.8.100")
        #expect(group.contents.isEmpty)
    }
    
    @Test("Create measurement group with all attributes")
    func testCreateGroupWithAllAttributes() {
        let finding = CodedConcept(
            codeValue: "4147007",
            codingSchemeDesignator: "SCT",
            codeMeaning: "Mass"
        )
        let findingSite = CodedConcept(
            codeValue: "10200004",
            codingSchemeDesignator: "SCT",
            codeMeaning: "Liver"
        )
        let laterality = CodedConcept(
            codeValue: "24028007",
            codingSchemeDesignator: "SCT",
            codeMeaning: "Right"
        )
        
        let group = MeasurementGroupData(
            trackingIdentifier: "Liver Lesion",
            trackingUID: "1.2.3.4.5.6.7.8.100",
            activitySession: "Session1",
            timePoint: "Baseline",
            finding: finding,
            findingSite: findingSite,
            laterality: laterality,
            contents: [
                .measurement(
                    conceptName: nil,
                    value: 25.0,
                    units: UCUMUnit.millimeter.concept
                )
            ]
        )
        
        #expect(group.activitySession == "Session1")
        #expect(group.timePoint == "Baseline")
        #expect(group.finding?.codeValue == "4147007")
        #expect(group.findingSite?.codeValue == "10200004")
        #expect(group.laterality?.codeValue == "24028007")
        #expect(group.contents.count == 1)
    }
}

// MARK: - TID Template Tests

@Suite("TID 1500/1501/1600 Template Definition Tests")
struct TIDTemplateDefinitionTests {
    
    @Test("TID 1500 identifier")
    func testTID1500Identifier() {
        #expect(TID1500MeasurementReport.identifier.templateID == "1500")
        #expect(TID1500MeasurementReport.displayName == "Measurement Report")
    }
    
    @Test("TID 1501 identifier")
    func testTID1501Identifier() {
        #expect(TID1501MeasurementGroup.identifier.templateID == "1501")
        #expect(TID1501MeasurementGroup.displayName == "Measurement and Qualitative Evaluation Group")
    }
    
    @Test("TID 1600 identifier")
    func testTID1600Identifier() {
        #expect(TID1600ImageLibrary.identifier.templateID == "1600")
        #expect(TID1600ImageLibrary.displayName == "Image Library")
    }
    
    @Test("TID 1500 has rows defined")
    func testTID1500HasRows() {
        #expect(!TID1500MeasurementReport.rows.isEmpty)
    }
    
    @Test("TID 1501 has rows defined")
    func testTID1501HasRows() {
        #expect(!TID1501MeasurementGroup.rows.isEmpty)
    }
    
    @Test("TID 1600 has rows defined")
    func testTID1600HasRows() {
        #expect(!TID1600ImageLibrary.rows.isEmpty)
    }
    
    @Test("Templates are registered in registry")
    func testTemplatesRegistered() {
        let registry = TemplateRegistry.shared
        
        #expect(registry.template(tid: 1500) != nil)
        #expect(registry.template(tid: 1501) != nil)
        #expect(registry.template(tid: 1600) != nil)
    }
    
    @Test("TID 1500 is extensible")
    func testTID1500IsExtensible() {
        #expect(TID1500MeasurementReport.isExtensible == true)
    }
    
    @Test("TID 1500 root value type is container")
    func testTID1500RootValueType() {
        #expect(TID1500MeasurementReport.rootValueType == .container)
    }
}
