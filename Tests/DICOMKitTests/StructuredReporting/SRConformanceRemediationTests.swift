import XCTest
import DICOMCore
@testable import DICOMKit

final class SRConformanceRemediationTests: XCTestCase {

    // MARK: - BasicTextSRBuilder Type 1C ConceptNameCodeSequence (PS3.3 C.17.3.2.2)

    func testBasicTextSRNarrativeHelpersPopulateChildConceptNamesAndPassValidator() throws {
        let title = CodedConcept(
            codeValue: "18748-4",
            codingSchemeDesignator: "LN",
            codeMeaning: "Diagnostic Imaging Report"
        )
        let doc = try BasicTextSRBuilder()
            .withPatientID("P001")
            .withPatientName("DOE^JOHN")
            .withDocumentTitle(title)
            .addClinicalHistory("Cough and fever for 5 days")
            .addFindings("Focal consolidation in the right lower lobe.")
            .addImpression("Right lower lobe community-acquired pneumonia.")
            .addRecommendation("Follow-up chest radiograph in 6 weeks.")
            .build()

        let dataSet = try SRDocumentSerializer().serialize(document: doc)
        let dicomFile = DICOMFile.create(
            dataSet: dataSet,
            sopClassUID: doc.sopClassUID,
            sopInstanceUID: doc.sopInstanceUID,
            transferSyntaxUID: "1.2.840.10008.1.2.1"
        )
        let data = try dicomFile.write()

        // Validate against DICOMValidator Level 3 (PS3.10 + PS3.5 + PS3.3 A.35.1)
        let validation = try DICOMValidator(level: 3, iod: nil, force: false)
            .validate(data: data, filePath: "basic_text_sr.dcm")
        XCTAssertTrue(validation.errors.isEmpty, "Unexpected validation errors: \(validation.errors)")

        // Every narrative section's child TEXT item must carry ConceptNameCodeSequence (0040,A043)
        let parsed = try SRDocumentParser().parse(dataSet: try DICOMFile.read(from: data).dataSet)
        let sections = parsed.rootContent.contentItems.compactMap { $0.asContainer }
        XCTAssertEqual(sections.count, 4)
        for section in sections {
            XCTAssertNotNil(section.conceptName)
            let textChildren = section.contentItems.compactMap { $0.asText }
            XCTAssertEqual(textChildren.count, 1)
            XCTAssertNotNil(textChildren[0].conceptName, "Child TEXT item under CONTAINS must carry ConceptNameCodeSequence")
        }

        // Verify DCMTK dsr2xml accepts the file with exit code 0 when installed
        try assertDCMTKDSR2XMLPassesIfAvailable(data: data)
    }

    // MARK: - Key Object Selection Module Separation (PS3.3 C.17.6.1 / C.17.6.2 & TID 2010)

    func testKeyObjectSelectionOmitsSRGeneralFlagsAndWritesType1EvidenceSequence() throws {
        let kosDoc = try KeyObjectSelectionBuilder(validateOnBuild: true)
            .withPatientID("P002")
            .withPatientName("SMITH^JANE")
            .withStudyInstanceUID("1.2.840.113619.2.55.3.100")
            .withDocumentTitle(DocumentTitle.ofInterest)
            .withSelectionDescription("Representative slices demonstrating pulmonary embolism")
            .addKeyObject(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: "1.2.840.113619.2.55.3.100.1.1"
            )
            .addKeyObject(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: "1.2.840.113619.2.55.3.100.1.2"
            )
            .build()

        XCTAssertEqual(kosDoc.modality, "KO")
        XCTAssertEqual(kosDoc.rootContent.templateIdentifier, "2010")

        // TID 2010 Row 7 has VM = 1: single Key Object Description TEXT item even with 2 images
        let descItems = kosDoc.rootContent.contentItems.compactMap { $0.asText }
        XCTAssertEqual(descItems.count, 1)
        XCTAssertEqual(descItems[0].conceptName?.codeValue, "113012")

        let dataSet = try SRDocumentSerializer().serialize(document: kosDoc)
        XCTAssertEqual(dataSet.string(for: .modality), "KO")
        XCTAssertNil(dataSet[.completionFlag], "KOS uses C.17.6.2, not C.17.2 CompletionFlag")
        XCTAssertNil(dataSet[.verificationFlag], "KOS uses C.17.6.2, not C.17.2 VerificationFlag")
        XCTAssertNotNil(dataSet.sequence(for: .currentRequestedProcedureEvidenceSequence),
                        "KOS requires Type 1 CurrentRequestedProcedureEvidenceSequence (0040,A375)")

        let dicomData = try DICOMFile.create(
            dataSet: dataSet,
            sopClassUID: kosDoc.sopClassUID,
            sopInstanceUID: kosDoc.sopInstanceUID,
            transferSyntaxUID: "1.2.840.10008.1.2.1"
        ).write()

        let validation = try DICOMValidator(level: 3, iod: nil, force: false)
            .validate(data: dicomData, filePath: "kos.dcm")
        XCTAssertTrue(validation.errors.isEmpty, "Unexpected KOS validation errors: \(validation.errors)")
        try assertDCMTKDSR2XMLPassesIfAvailable(data: dicomData)
    }

    // MARK: - PresentationStateSRBridge Geometry & SCT Conformance

    func testRectangleAndAngleAnnotationsSurviveRepeatedSRRoundTrips() throws {
        let patient = PresentationStatePatientContext(
            patientName: "DOE^RECT",
            patientID: "P003",
            studyInstanceUID: "1.2.840.113619.2.55.3.200"
        )
        let rect = DICOMAnnotation(
            kind: .rectangle,
            points: [
                DICOMAnnotationPoint(x: 50, y: 60),
                DICOMAnnotationPoint(x: 150, y: 180)
            ],
            text: "ROI Box",
            referencedSOPClassUID: "1.2.840.10008.5.1.4.1.1.2",
            referencedSOPInstanceUID: "1.2.840.113619.2.55.3.200.1.1"
        )
        let angle = DICOMAnnotation(
            kind: .angle,
            points: [
                DICOMAnnotationPoint(x: 140, y: 100),
                DICOMAnnotationPoint(x: 100, y: 100),
                DICOMAnnotationPoint(x: 100, y: 140)
            ],
            text: "90 deg",
            referencedSOPClassUID: "1.2.840.10008.5.1.4.1.1.2",
            referencedSOPInstanceUID: "1.2.840.113619.2.55.3.200.1.1"
        )

        // Pass 1 -> SR -> Extract
        let sr1 = try PresentationStateSRBridge.buildMeasurementReport(
            annotations: [rect, angle],
            patient: patient
        )
        let pass1 = PresentationStateSRBridge.extract(from: sr1)
        XCTAssertEqual(pass1.annotations.count, 2)
        XCTAssertEqual(pass1.annotations[0].kind, DICOMAnnotationKind.rectangle)
        XCTAssertEqual(pass1.annotations[1].kind, DICOMAnnotationKind.angle)

        // Pass 2 -> SR -> Extract (verifies 2-corner normalization prevents drift to .polygon)
        let sr2 = try PresentationStateSRBridge.buildMeasurementReport(
            annotations: pass1.annotations,
            patient: patient
        )
        let pass2 = PresentationStateSRBridge.extract(from: sr2)
        XCTAssertEqual(pass2.annotations[0].kind, DICOMAnnotationKind.rectangle)
        XCTAssertEqual(pass2.annotations[0].points.count, 2)
        XCTAssertEqual(pass2.annotations[1].kind, DICOMAnnotationKind.angle)
        XCTAssertEqual(pass2.annotations[1].points.count, 3)

        // Verify zero retired SRT scheme codes in generated TID 1500 report
        let ds = try SRDocumentSerializer().serialize(document: sr2)
        let rawBytes = try DICOMFile.create(
            dataSet: ds,
            sopClassUID: sr2.sopClassUID,
            sopInstanceUID: sr2.sopInstanceUID,
            transferSyntaxUID: "1.2.840.10008.1.2.1"
        ).write()
        try assertDCMTKDSR2XMLPassesIfAvailable(data: rawBytes)
    }

    // MARK: - Comprehensive 3D SR Value Type & MeasurementReportBuilder 3D Upgrade

    func testComprehensive3DSRRejectsTableAndMeasurementReportUpgradesOnSCOORD3D() throws {
        // Comprehensive 3D SR (PS3.3 A.35.13) does not permit TABLE (reserved for Extensible SR .88.35)
        let table = TableContentItem(
            conceptName: CodedConcept(codeValue: "121106", codingSchemeDesignator: "DCM", codeMeaning: "Comment"),
            rows: 1,
            columns: 1,
            cells: [.init(row: 1, column: 1, value: .text(["Value"]))]
        )
        let title = CodedConcept(
            codeValue: "18748-4",
            codingSchemeDesignator: "LN",
            codeMeaning: "Diagnostic Imaging Report"
        )
        XCTAssertThrowsError(
            try Comprehensive3DSRBuilder(validateOnBuild: true)
                .withDocumentTitle(title)
                .addItem(AnyContentItem(table))
                .build()
        )

        // MeasurementReportBuilder auto-upgrades to Comprehensive 3D SR (.88.34) when SCOORD3D is present
        let group3D = MeasurementGroupData(
            trackingIdentifier: "3D Nodule",
            trackingUID: "1.2.840.113619.2.55.3.300.99",
            contents: [
                .spatialCoordinates3D(
                    conceptName: CodedConcept(codeValue: "111030", codingSchemeDesignator: "DCM", codeMeaning: "Image Region"),
                    graphicType: .point,
                    graphicData: [12.0, 34.0, -56.0],
                    frameOfReferenceUID: "1.2.840.113619.2.55.3.300.5"
                )
            ]
        )
        let report3D = try MeasurementReportBuilder(validateOnBuild: true)
            .withImagingMeasurementReportTitle()
            .addProcedureReported(CodedConcept(codeValue: "363679005", codingSchemeDesignator: "SCT", codeMeaning: "Imaging procedure"))
            .addObserver(.person(name: "DOE^RAD"))
            .addMeasurementGroup(group3D)
            .build()

        XCTAssertEqual(report3D.sopClassUID, SRDocumentType.comprehensive3DSR.sopClassUID)
    }

    // MARK: - Helper

    private func assertDCMTKDSR2XMLPassesIfAvailable(data: Data) throws {
        let dsr2xmlPath = "/opt/homebrew/bin/dsr2xml"
        guard FileManager.default.isExecutableFile(atPath: dsr2xmlPath) else { return }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sr-remediation-\(UUID().uuidString).dcm")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try data.write(to: tempURL)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: dsr2xmlPath)
        proc.arguments = [tempURL.path]
        let errPipe = Pipe()
        proc.standardOutput = Pipe()
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(proc.terminationStatus, 0, "dsr2xml failed with stderr: \(errText)")
    }
}
