/// Tests for MeasurementReport Extraction API
///
/// Validates extraction of TID 1500 Measurement Report data from SR documents.

import XCTest
@testable import DICOMKit
@testable import DICOMCore

final class MeasurementReportExtractorTests: XCTestCase {
    
    // MARK: - Helper Methods
    
    private func createBasicReport() throws -> SRDocument {
        let document = try MeasurementReportBuilder()
            .withPatientID("12345")
            .withPatientName("Doe^John")
            .withStudyInstanceUID("1.2.3.4.5")
            .build()
        return document
    }
    
    private func serializeAndParse(_ document: SRDocument) throws -> SRDocument {
        let serializer = SRDocumentSerializer()
        let dataSet = try serializer.serialize(document: document)
        
        let parser = SRDocumentParser()
        return try parser.parse(dataSet: dataSet)
    }
    
    private func createImageReference() -> ImageReference {
        ImageReference(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9"
        )
    }
    
    // MARK: - Basic Extraction Tests
    
    func testExtractMinimalReport() throws {
        let original = try createBasicReport()
        let parsed = try serializeAndParse(original)
        
        let report = try MeasurementReport.extract(from: parsed)
        
        XCTAssertEqual(report.document.sopClassUID, SRDocumentType.comprehensiveSR.sopClassUID)
        XCTAssertEqual(report.measurementGroups.count, 0)
        XCTAssertEqual(report.imageLibraryEntries.count, 0)
        XCTAssertEqual(report.proceduresReported.count, 0)
        XCTAssertEqual(report.qualitativeEvaluations.count, 0)
    }
    
    func testExtractDocumentTitle() throws {
        let original = try MeasurementReportBuilder()
            .withDocumentTitle(MeasurementReportDocumentTitle.imagingMeasurementReport)
            .build()
        let parsed = try serializeAndParse(original)
        
        let report = try MeasurementReport.extract(from: parsed)
        
        XCTAssertNotNil(report.documentTitle)
        XCTAssertEqual(report.documentTitle?.codeValue, "126000")
        XCTAssertEqual(report.documentTitle?.codeMeaning, "Imaging Measurement Report")
    }
    
    func testExtractWithCustomDocumentTitle() throws {
        let customTitle = CodedConcept(
            codeValue: "CUSTOM",
            codingSchemeDesignator: "99TEST",
            codeMeaning: "Custom Report"
        )
        let original = try MeasurementReportBuilder()
            .withDocumentTitle(customTitle)
            .build()
        let parsed = try serializeAndParse(original)
        
        let report = try MeasurementReport.extract(from: parsed)
        
        XCTAssertEqual(report.documentTitle?.codeValue, "CUSTOM")
        XCTAssertEqual(report.documentTitle?.codeMeaning, "Custom Report")
    }
    
    // MARK: - Procedure Reported Tests
    
    func testExtractSingleProcedureReported() throws {
        let procedure = CodedConcept(
            codeValue: "71020",
            codingSchemeDesignator: "DCM",
            codeMeaning: "CT Chest"
        )
        
        let original = try MeasurementReportBuilder()
            .addProcedureReported(procedure)
            .build()
        let parsed = try serializeAndParse(original)
        
        let report = try MeasurementReport.extract(from: parsed)
        
        XCTAssertEqual(report.proceduresReported.count, 1)
        XCTAssertEqual(report.proceduresReported[0].codeValue, "71020")
        XCTAssertEqual(report.proceduresReported[0].codeMeaning, "CT Chest")
    }
    
    func testExtractMultipleProceduresReported() throws {
        let proc1 = CodedConcept(codeValue: "71020", codingSchemeDesignator: "DCM", codeMeaning: "CT Chest")
        let proc2 = CodedConcept(codeValue: "71021", codingSchemeDesignator: "DCM", codeMeaning: "CT Abdomen")
        
        let original = try MeasurementReportBuilder()
            .addProcedureReported(proc1)
            .addProcedureReported(proc2)
            .build()
        let parsed = try serializeAndParse(original)
        
        let report = try MeasurementReport.extract(from: parsed)
        
        XCTAssertEqual(report.proceduresReported.count, 2)
        XCTAssertEqual(report.proceduresReported[0].codeMeaning, "CT Chest")
        XCTAssertEqual(report.proceduresReported[1].codeMeaning, "CT Abdomen")
    }
    
    func testExtractNoProceduresReported() throws {
        let original = try createBasicReport()
        let parsed = try serializeAndParse(original)
        
        let report = try MeasurementReport.extract(from: parsed)
        
        XCTAssertEqual(report.proceduresReported.count, 0)
    }
    
    // MARK: - Language Tests
    
    func testExtractLanguageOfContent() throws {
        let language = CodedConcept(
            codeValue: "en-US",
            codingSchemeDesignator: "RFC5646",
            codeMeaning: "English (United States)"
        )
        
        let original = try MeasurementReportBuilder()
            .withLanguage(language)
            .build()
        let parsed = try serializeAndParse(original)
        
        let report = try MeasurementReport.extract(from: parsed)
        
        XCTAssertNotNil(report.languageOfContent)
        XCTAssertEqual(report.languageOfContent?.codeValue, "en-US")
    }
    
    func testExtractNoLanguageOfContent() throws {
        let original = try createBasicReport()
        let parsed = try serializeAndParse(original)
        
        let report = try MeasurementReport.extract(from: parsed)
        
        XCTAssertNil(report.languageOfContent)
    }
    
    // MARK: - Image Library Tests
    
    func testExtractSingleImageLibraryEntry() throws {
        let imageRef = createImageReference()
        
        let original = try MeasurementReportBuilder()
            .addImageLibraryEntry(sopClassUID: imageRef.sopReference.sopClassUID, sopInstanceUID: imageRef.sopReference.sopInstanceUID)
            .build()
        let parsed = try serializeAndParse(original)
        
        let report = try MeasurementReport.extract(from: parsed)
        
        XCTAssertEqual(report.imageLibraryEntries.count, 1)
        XCTAssertEqual(report.imageLibraryEntries[0].sopReference.sopInstanceUID, imageRef.sopReference.sopInstanceUID)
    }
    
    func testExtractMultipleImageLibraryEntries() throws {
        let imageRef1 = ImageReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.4.5.1")
        let imageRef2 = ImageReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.4.5.2")
        let imageRef3 = ImageReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.4.5.3")
        
        let original = try MeasurementReportBuilder()
            .addImageLibraryEntry(sopClassUID: imageRef1.sopReference.sopClassUID, sopInstanceUID: imageRef1.sopReference.sopInstanceUID)
            .addImageLibraryEntry(sopClassUID: imageRef2.sopReference.sopClassUID, sopInstanceUID: imageRef2.sopReference.sopInstanceUID)
            .addImageLibraryEntry(sopClassUID: imageRef3.sopReference.sopClassUID, sopInstanceUID: imageRef3.sopReference.sopInstanceUID)
            .build()
        let parsed = try serializeAndParse(original)
        
        let report = try MeasurementReport.extract(from: parsed)
        
        XCTAssertEqual(report.imageLibraryEntries.count, 3)
        XCTAssertEqual(report.imageLibraryEntries[0].sopReference.sopInstanceUID, "1.2.3.4.5.1")
        XCTAssertEqual(report.imageLibraryEntries[1].sopReference.sopInstanceUID, "1.2.3.4.5.2")
        XCTAssertEqual(report.imageLibraryEntries[2].sopReference.sopInstanceUID, "1.2.3.4.5.3")
    }
    
    func testExtractNoImageLibraryEntries() throws {
        let original = try createBasicReport()
        let parsed = try serializeAndParse(original)
        
        let report = try MeasurementReport.extract(from: parsed)
        
        XCTAssertEqual(report.imageLibraryEntries.count, 0)
    }
    
    // MARK: - Measurement Group Tests
    
    func testExtractSingleMeasurementGroupMinimal() throws {
        let original = try MeasurementReportBuilder()
            .addMeasurementGroup(trackingIdentifier: "Lesion 1") {
                // Empty group
            }
            .build()
        let parsed = try serializeAndParse(original)
        
        let report = try MeasurementReport.extract(from: parsed)
        
        XCTAssertEqual(report.measurementGroups.count, 1)
        XCTAssertEqual(report.measurementGroups[0].trackingIdentifier, "Lesion 1")
        XCTAssertNotNil(report.measurementGroups[0].trackingUID,
                        "TID 1411 requires a Tracking Unique Identifier; the builder generates one")
        XCTAssertNil(report.measurementGroups[0].findingType)
        XCTAssertNil(report.measurementGroups[0].findingSite)
        XCTAssertEqual(report.measurementGroups[0].measurements.count, 0)
    }
    
    func testExtractMeasurementGroupWithTrackingUID() throws {
        let trackingUID = "1.2.3.4.5.6.7.8.9.10"
        
        let original = try MeasurementReportBuilder()
            .addMeasurementGroup(
                trackingIdentifier: "Lesion 1",
                trackingUID: trackingUID
            ) {
                // Empty group
            }
            .build()
        let parsed = try serializeAndParse(original)
        
        let report = try MeasurementReport.extract(from: parsed)
        
        XCTAssertEqual(report.measurementGroups.count, 1)
        XCTAssertEqual(report.measurementGroups[0].trackingUID, trackingUID)
    }
    
    func testExtractMeasurementGroupWithFindingType() throws {
        let original = try MeasurementReportBuilder()
            .addMeasurementGroup(trackingIdentifier: "Lesion 1", finding: CodedConcept(codeValue: "108369006", codingSchemeDesignator: "SCT", codeMeaning: "Tumor")) {}
            .build()
        let parsed = try serializeAndParse(original)
        
        let report = try MeasurementReport.extract(from: parsed)
        
        XCTAssertEqual(report.measurementGroups.count, 1)
        XCTAssertNotNil(report.measurementGroups[0].findingType)
        XCTAssertEqual(report.measurementGroups[0].findingType?.codeValue, "108369006")
        XCTAssertEqual(report.measurementGroups[0].findingType?.codeMeaning, "Tumor")
    }
    
    func testExtractMeasurementGroupWithFindingSite() throws {
        // TID 1501 row 8: Finding Site is a concept modifier of the Finding.
        let original = try MeasurementReportBuilder()
            .addMeasurementGroup(trackingIdentifier: "Lesion 1", finding: CodedConcept(codeValue: "108369006", codingSchemeDesignator: "SCT", codeMeaning: "Tumor"), findingSite: CodedConcept(codeValue: "39607008", codingSchemeDesignator: "SCT", codeMeaning: "Lung")) {}
            .build()
        let parsed = try serializeAndParse(original)
        
        let report = try MeasurementReport.extract(from: parsed)
        
        XCTAssertEqual(report.measurementGroups.count, 1)
        XCTAssertNotNil(report.measurementGroups[0].findingSite)
        XCTAssertEqual(report.measurementGroups[0].findingSite?.codeValue, "39607008")
        XCTAssertEqual(report.measurementGroups[0].findingSite?.codeMeaning, "Lung")
    }
    
    func testExtractMeasurementGroupWithMeasurements() throws {
        let original = try MeasurementReportBuilder()
            .addMeasurementGroup(
                trackingIdentifier: "Lesion 1"
            ) {
                MeasurementGroupContentHelper.longAxisMM(value: 25.5)
                MeasurementGroupContentHelper.shortAxisMM(value: 18.2)
            }
            .build()
        let parsed = try serializeAndParse(original)
        
        let report = try MeasurementReport.extract(from: parsed)
        
        XCTAssertEqual(report.measurementGroups.count, 1)
        XCTAssertEqual(report.measurementGroups[0].measurements.count, 2)
        
        // Verify measurements
        let longAxis = report.measurementGroups[0].measurements.first { m in
            m.conceptName?.codeMeaning.contains("Long Axis") ?? false
        }
        XCTAssertNotNil(longAxis)
        XCTAssertEqual(longAxis?.value ?? 0.0, 25.5, accuracy: 0.01)
        
        let shortAxis = report.measurementGroups[0].measurements.first { m in
            m.conceptName?.codeMeaning.contains("Short Axis") ?? false
        }
        XCTAssertNotNil(shortAxis)
        XCTAssertEqual(shortAxis?.value ?? 0.0, 18.2, accuracy: 0.01)
    }
    
    func testExtractMultipleMeasurementGroups() throws {
        let original = try MeasurementReportBuilder()
            .addMeasurementGroup(trackingIdentifier: "Lesion 1") {
                MeasurementGroupContentHelper.longAxisMM(value: 25.5)
            }
            .addMeasurementGroup(trackingIdentifier: "Lesion 2") {
                MeasurementGroupContentHelper.longAxisMM(value: 15.3)
            }
            .addMeasurementGroup(trackingIdentifier: "Lesion 3") {
                MeasurementGroupContentHelper.longAxisMM(value: 10.1)
            }
            .build()
        let parsed = try serializeAndParse(original)
        
        let report = try MeasurementReport.extract(from: parsed)
        
        XCTAssertEqual(report.measurementGroups.count, 3)
        XCTAssertEqual(report.measurementGroups[0].trackingIdentifier, "Lesion 1")
        XCTAssertEqual(report.measurementGroups[1].trackingIdentifier, "Lesion 2")
        XCTAssertEqual(report.measurementGroups[2].trackingIdentifier, "Lesion 3")
    }
    
    func testExtractMeasurementGroupWithFullData() throws {
        let trackingUID = "1.2.3.4.5.6.7.8.9.10"
        
        let original = try MeasurementReportBuilder()
            .addMeasurementGroup(
                trackingIdentifier: "Lesion 1",
                trackingUID: trackingUID,
                finding: CodedConcept(codeValue: "108369006", codingSchemeDesignator: "SCT", codeMeaning: "Tumor"),
                findingSite: CodedConcept(codeValue: "39607008", codingSchemeDesignator: "SCT", codeMeaning: "Lung")
            ) {
                MeasurementGroupContentHelper.longAxisMM(value: 25.5)
                MeasurementGroupContentHelper.shortAxisMM(value: 18.2)
                MeasurementGroupContentHelper.volumeMM3(value: 4.2)
            }
            .build()
        let parsed = try serializeAndParse(original)
        
        let report = try MeasurementReport.extract(from: parsed)
        
        XCTAssertEqual(report.measurementGroups.count, 1)
        let group = report.measurementGroups[0]
        
        XCTAssertEqual(group.trackingIdentifier, "Lesion 1")
        XCTAssertEqual(group.trackingUID, trackingUID)
        XCTAssertEqual(group.findingType?.codeMeaning, "Tumor")
        XCTAssertEqual(group.findingSite?.codeMeaning, "Lung")
        XCTAssertEqual(group.measurements.count, 3)
    }
    
    // MARK: - Qualitative Evaluations Tests
    
    func testExtractQualitativeEvaluations() throws {
        let evaluation = CodedConcept(
            codeValue: "121071",
            codingSchemeDesignator: "DCM",
            codeMeaning: "Finding"
        )
        
        let original = try MeasurementReportBuilder()
            .addQualitativeEvaluation(conceptName: CodedConcept(codeValue: "121071", codingSchemeDesignator: "DCM", codeMeaning: "Finding"), value: evaluation)
            .build()
        let parsed = try serializeAndParse(original)
        
        let report = try MeasurementReport.extract(from: parsed)
        
        XCTAssertGreaterThanOrEqual(report.qualitativeEvaluations.count, 1)
    }
    
    func testExtractMultipleQualitativeEvaluations() throws {
        let eval1 = CodedConcept(codeValue: "121071", codingSchemeDesignator: "DCM", codeMeaning: "Finding")
        let eval2 = CodedConcept(codeValue: "121073", codingSchemeDesignator: "DCM", codeMeaning: "Impression")
        
        let original = try MeasurementReportBuilder()
            .addQualitativeEvaluation(conceptName: CodedConcept(codeValue: "121071", codingSchemeDesignator: "DCM", codeMeaning: "Finding"), value: eval1)
            .addQualitativeEvaluation(conceptName: CodedConcept(codeValue: "121073", codingSchemeDesignator: "DCM", codeMeaning: "Impression"), value: eval2)
            .build()
        let parsed = try serializeAndParse(original)
        
        let report = try MeasurementReport.extract(from: parsed)
        
        XCTAssertGreaterThanOrEqual(report.qualitativeEvaluations.count, 2)
    }
    
    // MARK: - Error Cases Tests
    
    func testExtractFromInvalidDocumentType() throws {
        // Create a Basic Text SR instead of Comprehensive SR
        let document = try BasicTextSRBuilder()
            .build()
        let parsed = try serializeAndParse(document)
        
        XCTAssertThrowsError(try MeasurementReport.extract(from: parsed)) { error in
            guard case ExtractionError.invalidDocumentType = error else {
                XCTFail("Expected invalidDocumentType error")
                return
            }
        }
    }
    
    func testExtractFromKeyObjectDocument() throws {
        let keyObject = KeyObject(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9"
        )
        
        let document = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.ofInterest)
            .addKeyObject(sopClassUID: keyObject.sopClassUID, sopInstanceUID: keyObject.sopInstanceUID)
            .build()
        let parsed = try serializeAndParse(document)
        
        XCTAssertThrowsError(try MeasurementReport.extract(from: parsed)) { error in
            guard case ExtractionError.invalidDocumentType = error else {
                XCTFail("Expected invalidDocumentType error")
                return
            }
        }
    }
    
    // MARK: - Complete Workflow Tests
    
    func testCompleteWorkflowSimple() throws {
        let original = try MeasurementReportBuilder()
            .withPatientID("MR-2024-001")
            .withPatientName("Smith^John")
            .withStudyInstanceUID("1.2.840.113619.2.5.1762583153.215519.978957063.78")
            .withDocumentTitle(MeasurementReportDocumentTitle.imagingMeasurementReport)
            .addMeasurementGroup(trackingIdentifier: "Lesion 1") {
                MeasurementGroupContentHelper.longAxisMM(value: 25.5)
                MeasurementGroupContentHelper.shortAxisMM(value: 18.2)
            }
            .build()
        
        let parsed = try serializeAndParse(original)
        let extracted = try MeasurementReport.extract(from: parsed)
        
        // Verify roundtrip
        XCTAssertEqual(extracted.document.patientID, "MR-2024-001")
        XCTAssertEqual(extracted.measurementGroups.count, 1)
        XCTAssertEqual(extracted.measurementGroups[0].trackingIdentifier, "Lesion 1")
        XCTAssertEqual(extracted.measurementGroups[0].measurements.count, 2)
    }
    
    func testCompleteWorkflowComplex() throws {
        let imageRef = createImageReference()
        let proc1 = CodedConcept(codeValue: "71020", codingSchemeDesignator: "DCM", codeMeaning: "CT Chest")
        let original = try MeasurementReportBuilder()
            .withPatientID("MR-2024-002")
            .withPatientName("Doe^Jane")
            .withPatientBirthDate("19750615")
            .withPatientSex("F")
            .withStudyInstanceUID("1.2.840.113619.2.5.1762583153.215519.978957063.100")
            .withStudyDate("20240115")
            .withStudyTime("143000")
            .withDocumentTitle(MeasurementReportDocumentTitle.imagingMeasurementReport)
            .addProcedureReported(proc1)
            .addImageLibraryEntry(sopClassUID: imageRef.sopReference.sopClassUID, sopInstanceUID: imageRef.sopReference.sopInstanceUID)
            .addMeasurementGroup(
                trackingIdentifier: "Lesion 1",
                trackingUID: "1.2.3.4.5.6.7.8.9.10",
            ) {
                MeasurementGroupContentHelper.longAxisMM(value: 25.5)
                MeasurementGroupContentHelper.shortAxisMM(value: 18.2)
                MeasurementGroupContentHelper.volumeMM3(value: 4.2)
            }
            .addMeasurementGroup(trackingIdentifier: "Lesion 2") {
                MeasurementGroupContentHelper.longAxisMM(value: 15.3)
            }
            .build()
        
        let parsed = try serializeAndParse(original)
        let extracted = try MeasurementReport.extract(from: parsed)
        
        // Verify all data
        XCTAssertEqual(extracted.document.patientID, "MR-2024-002")
        XCTAssertEqual(extracted.proceduresReported.count, 1)
        XCTAssertEqual(extracted.imageLibraryEntries.count, 1)
        XCTAssertEqual(extracted.measurementGroups.count, 2)
        
        // Verify first measurement group
        let group1 = extracted.measurementGroups[0]
        XCTAssertEqual(group1.trackingIdentifier, "Lesion 1")
        XCTAssertEqual(group1.trackingUID, "1.2.3.4.5.6.7.8.9.10")
        XCTAssertEqual(group1.measurements.count, 3)
        
        // Verify second measurement group
        let group2 = extracted.measurementGroups[1]
        XCTAssertEqual(group2.trackingIdentifier, "Lesion 2")
        XCTAssertEqual(group2.measurements.count, 1)
    }
    
    // MARK: - Edge Cases Tests
    
    func testExtractEmptyMeasurementGroup() throws {
        let original = try MeasurementReportBuilder()
            .addMeasurementGroup(trackingIdentifier: "Empty Group") {
                // Empty
            }
            .build()
        let parsed = try serializeAndParse(original)
        
        let report = try MeasurementReport.extract(from: parsed)
        
        XCTAssertEqual(report.measurementGroups.count, 1)
        XCTAssertEqual(report.measurementGroups[0].measurements.count, 0)
    }
    
    func testExtractManyMeasurementGroups() throws {
        var builder = MeasurementReportBuilder()
        
        for i in 1...10 {
            builder = builder.addMeasurementGroup(trackingIdentifier: "Lesion \(i)") {
                MeasurementGroupContentHelper.longAxisMM(value: Double(i) * 2.5)
            }
        }
        
        let original = try builder.build()
        let parsed = try serializeAndParse(original)
        let report = try MeasurementReport.extract(from: parsed)
        
        XCTAssertEqual(report.measurementGroups.count, 10)
    }
    
    func testExtractMeasurementWithZeroValue() throws {
        let original = try MeasurementReportBuilder()
            .addMeasurementGroup(trackingIdentifier: "Lesion 1") {
                MeasurementGroupContentHelper.longAxisMM(value: 0.0)
            }
            .build()
        let parsed = try serializeAndParse(original)
        
        let report = try MeasurementReport.extract(from: parsed)
        
        XCTAssertEqual(report.measurementGroups[0].measurements.count, 1)
        XCTAssertEqual(report.measurementGroups[0].measurements[0].value, 0.0)
    }
    
    func testExtractMeasurementWithVeryLargeValue() throws {
        let original = try MeasurementReportBuilder()
            .addMeasurementGroup(trackingIdentifier: "Lesion 1") {
                MeasurementGroupContentHelper.volumeMM3(value: 9999.99)
            }
            .build()
        let parsed = try serializeAndParse(original)
        
        let report = try MeasurementReport.extract(from: parsed)
        
        XCTAssertEqual(report.measurementGroups[0].measurements.count, 1)
        XCTAssertEqual(report.measurementGroups[0].measurements[0].value, 9999.99, accuracy: 0.01)
    }
}
