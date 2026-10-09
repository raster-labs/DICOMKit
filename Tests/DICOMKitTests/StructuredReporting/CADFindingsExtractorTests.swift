/// Tests for CADFindings Extraction API
///
/// Validates extraction of CAD findings from Mammography and Chest CAD SR documents written
/// in the PS3.16 2026a TID 4000 / TID 4100 layout (round trip through the serializer and
/// parser) and from the layouts written before the 2026a check.

import XCTest
@testable import DICOMKit
@testable import DICOMCore

final class CADFindingsExtractorTests: XCTestCase {

    // MARK: - Helper Methods

    private func createBasicMammographyCAD() throws -> SRDocument {
        let imageRef = createImageReference()
        let document = try MammographyCADSRBuilder()
            .withPatientID("12345")
            .withPatientName("Doe^Jane")
            .withStudyInstanceUID("1.2.3.4.5")
            .withCADProcessingSummary(
                algorithmName: "MammoCAD",
                algorithmVersion: "2.1.0",
                manufacturer: "Example Medical Systems"
            )
            .addFinding(
                type: .mass,
                probability: 0.85,
                location: .point2D(x: 128.5, y: 256.3, imageReference: imageRef)
            )
            .build()
        return document
    }

    private func createBasicChestCAD() throws -> SRDocument {
        let imageRef = createImageReference()
        let document = try ChestCADSRBuilder()
            .withPatientID("12345")
            .withPatientName("Doe^John")
            .withStudyInstanceUID("1.2.3.4.5")
            .withCADProcessingSummary(
                algorithmName: "ChestCAD",
                algorithmVersion: "3.0.0",
                manufacturer: "Example Medical Systems"
            )
            .addFinding(
                type: .nodule,
                probability: 0.75,
                location: .point2D(x: 100.0, y: 150.0, imageReference: imageRef)
            )
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
            sopClassUID: "1.2.840.10008.5.1.4.1.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9"
        )
    }

    private func dcm(_ value: String, _ meaning: String) -> CodedConcept {
        CodedConcept(codeValue: value, codingSchemeDesignator: "DCM", codeMeaning: meaning)
    }

    // MARK: - Basic Extraction Tests - Mammography

    func testExtractMammographyCADMinimal() throws {
        let original = try createBasicMammographyCAD()
        let parsed = try serializeAndParse(original)

        let findings = try CADFindings.extract(from: parsed)

        XCTAssertEqual(findings.cadType, .mammography)
        XCTAssertNotNil(findings.processingInfo.algorithmName)
        XCTAssertGreaterThanOrEqual(findings.findings.count, 1)
    }

    func testExtractMammographyCADType() throws {
        let original = try createBasicMammographyCAD()
        let parsed = try serializeAndParse(original)

        let findings = try CADFindings.extract(from: parsed)

        XCTAssertEqual(findings.cadType, .mammography)
        XCTAssertEqual(findings.document.sopClassUID, SRDocumentType.mammographyCADSR.sopClassUID)
    }

    func testExtractChestCADType() throws {
        let original = try createBasicChestCAD()
        let parsed = try serializeAndParse(original)

        let findings = try CADFindings.extract(from: parsed)

        XCTAssertEqual(findings.cadType, .chest)
        XCTAssertEqual(findings.document.sopClassUID, SRDocumentType.chestCADSR.sopClassUID)
    }

    // MARK: - Template rows (TID 4000 / TID 4100 root rows after a round trip)

    func testExtractMammographyRootRows() throws {
        let parsed = try serializeAndParse(try createBasicMammographyCAD())
        let extracted = try CADFindings.extract(from: parsed)

        // TID 1204 row 1 (CID 5000)
        XCTAssertEqual(extracted.language?.codeValue, "en")
        XCTAssertEqual(extracted.language?.codingSchemeDesignator, "RFC5646")
        // TID 4020 row 1
        XCTAssertEqual(extracted.imageLibrary, [createImageReference()])
        // TID 4001 row 1 (CID 6047), TID 4000 rows 6 and 8 (CID 6042)
        XCTAssertEqual(extracted.processingAndFindingsSummary?.codeValue, "111242")
        XCTAssertEqual(extracted.summaryOfDetections?.codeValue, "111222")
        XCTAssertEqual(extracted.summaryOfAnalyses?.codeValue, "111225")
        XCTAssertEqual(CADProcessingStatus(concept: try XCTUnwrap(extracted.summaryOfDetections)), .succeeded)
        XCTAssertEqual(CADProcessingAndFindingsSummary(concept: try XCTUnwrap(extracted.processingAndFindingsSummary)), .allAlgorithmsSucceededWithFindings)
        // TID 4017 row 1
        XCTAssertEqual(extracted.detectionsPerformed, [FindingType.mass.concept])
        XCTAssertEqual(extracted.analysesPerformed, [])
    }

    func testExtractChestRootRowsAndModifier() throws {
        let parsed = try serializeAndParse(try createBasicChestCAD())
        let extracted = try CADFindings.extract(from: parsed)

        XCTAssertEqual(extracted.language?.codeValue, "en")
        XCTAssertEqual(extracted.imageLibrary, [createImageReference()])
        XCTAssertEqual(extracted.processingAndFindingsSummary?.codeValue, "111242")
        XCTAssertEqual(extracted.summaryOfDetections?.codeValue, "111222")
        XCTAssertEqual(extracted.detectionsPerformed.map(\.codeValue), ["27925004"])

        XCTAssertEqual(extracted.findings.count, 1)
        let finding = extracted.findings[0]
        // TID 4104 row 1 (CID 6101) and row 2 (CID 6102)
        XCTAssertEqual(finding.findingType?.codeValue, "112033")
        XCTAssertEqual(finding.modifier?.codeValue, "27925004")
        // Row 6 (CID 6034)
        XCTAssertEqual(finding.renderingIntent.flatMap(CADRenderingIntent.init(concept:)), .presentationRequired)
        // Row 12: Certainty of Finding in percent, back to a fraction
        XCTAssertEqual(finding.probability ?? 0, 0.75, accuracy: 0.001)
        XCTAssertEqual(finding.certainty ?? 0, 0.75, accuracy: 0.001)
        // TID 4107 row 1 with its SELECTED FROM image
        guard case .point2D(let x, let y, let ref)? = finding.location else { return XCTFail("Expected point2D") }
        XCTAssertEqual(x, 100, accuracy: 0.001)
        XCTAssertEqual(y, 150, accuracy: 0.001)
        XCTAssertEqual(ref, createImageReference())
    }

    // MARK: - CAD Processing Info Tests

    func testExtractProcessingInfoAlgorithmName() throws {
        let original = try createBasicMammographyCAD()
        let parsed = try serializeAndParse(original)

        let findings = try CADFindings.extract(from: parsed)

        XCTAssertEqual(findings.processingInfo.algorithmName, "MammoCAD")
    }

    func testExtractProcessingInfoAlgorithmVersion() throws {
        let original = try createBasicMammographyCAD()
        let parsed = try serializeAndParse(original)

        let findings = try CADFindings.extract(from: parsed)

        XCTAssertEqual(findings.processingInfo.algorithmVersion, "2.1.0")
    }

    func testExtractProcessingInfoManufacturer() throws {
        let original = try createBasicMammographyCAD()
        let parsed = try serializeAndParse(original)

        let findings = try CADFindings.extract(from: parsed)

        XCTAssertEqual(findings.processingInfo.manufacturer, "Example Medical Systems")
    }

    func testExtractProcessingInfoComplete() throws {
        let imageRef = createImageReference()
        let original = try MammographyCADSRBuilder()
            .withCADProcessingSummary(
                algorithmName: "Advanced MammoCAD",
                algorithmVersion: "5.2.1",
                manufacturer: "Digital Mammography Inc"
            )
            .addFinding(
                type: .mass,
                probability: 0.9,
                location: .point2D(x: 100.0, y: 200.0, imageReference: imageRef)
            )
            .build()
        let parsed = try serializeAndParse(original)

        let findings = try CADFindings.extract(from: parsed)

        XCTAssertEqual(findings.processingInfo.algorithmName, "Advanced MammoCAD")
        XCTAssertEqual(findings.processingInfo.algorithmVersion, "5.2.1")
        XCTAssertEqual(findings.processingInfo.manufacturer, "Digital Mammography Inc")
    }

    func testExtractProcessingInfoWithoutFindings() throws {
        // Without findings the algorithm identification is not written anywhere (TID 4015/4016
        // absent: Not Attempted), so the processing info is empty
        let original = try MammographyCADSRBuilder()
            .withCADProcessingSummary(algorithmName: "MammoCAD", algorithmVersion: "1.0", manufacturer: "Vendor")
            .build()
        let parsed = try serializeAndParse(original)

        let findings = try CADFindings.extract(from: parsed)

        XCTAssertNil(findings.processingInfo.algorithmName)
        XCTAssertEqual(findings.findings.count, 0)
        XCTAssertEqual(findings.processingAndFindingsSummary?.codeValue, "111241")
    }

    // MARK: - Single Finding Extraction Tests

    func testExtractSingleFindingMass() throws {
        let imageRef = createImageReference()
        let original = try MammographyCADSRBuilder()
            .withCADProcessingSummary(
                algorithmName: "MammoCAD",
                algorithmVersion: "2.0",
                manufacturer: "Vendor"
            )
            .addFinding(
                type: .mass,
                probability: 0.87,
                location: .point2D(x: 150.5, y: 250.3, imageReference: imageRef)
            )
            .build()
        let parsed = try serializeAndParse(original)

        let findings = try CADFindings.extract(from: parsed)

        XCTAssertEqual(findings.findings.count, 1)
        let finding = findings.findings[0]

        XCTAssertNotNil(finding.findingType)
        XCTAssertEqual(finding.findingType?.codeValue, FindingType.mass.concept.codeValue)
        XCTAssertEqual(finding.probability ?? 0.0, 0.87, accuracy: 0.01)
        XCTAssertNil(finding.certainty)
        XCTAssertEqual(finding.renderingIntent?.codeValue, "111150")
    }

    func testExtractSingleFindingCalcification() throws {
        let imageRef = createImageReference()
        let original = try MammographyCADSRBuilder()
            .withCADProcessingSummary(algorithmName: "MammoCAD", algorithmVersion: "2.0", manufacturer: "Test Vendor")
            .addFinding(
                type: .calcification,
                probability: 0.65,
                location: .point2D(x: 75.0, y: 125.0, imageReference: imageRef)
            )
            .build()
        let parsed = try serializeAndParse(original)

        let findings = try CADFindings.extract(from: parsed)

        XCTAssertEqual(findings.findings.count, 1)
        XCTAssertEqual(findings.findings[0].findingType?.codeValue, FindingType.calcification.concept.codeValue)
        XCTAssertEqual(findings.findings[0].probability ?? 0.0, 0.65, accuracy: 0.01)
    }

    func testExtractSingleFindingArchitecturalDistortion() throws {
        let imageRef = createImageReference()
        let original = try MammographyCADSRBuilder()
            .withCADProcessingSummary(algorithmName: "MammoCAD", algorithmVersion: "2.0", manufacturer: "Test Vendor")
            .addFinding(
                type: .architecturalDistortion,
                probability: 0.55,
                location: .point2D(x: 200.0, y: 300.0, imageReference: imageRef)
            )
            .build()
        let parsed = try serializeAndParse(original)

        let findings = try CADFindings.extract(from: parsed)

        XCTAssertEqual(findings.findings.count, 1)
        XCTAssertEqual(findings.findings[0].findingType?.codeValue, FindingType.architecturalDistortion.concept.codeValue)
    }

    func testExtractCertaintyAndProbabilitySeparately() throws {
        // TID 4006 rows 6 and 7 both present: probability is (111047, DCM), certainty (111012, DCM)
        let imageRef = createImageReference()
        let finding = CADFinding(type: .mass, probability: 0.3, location: .point2D(x: 1, y: 2, imageReference: imageRef), certainty: 0.9)
        let original = try MammographyCADSRBuilder()
            .withCADProcessingSummary(algorithmName: "MammoCAD", algorithmVersion: "2.0", manufacturer: "Test Vendor")
            .addFinding(finding)
            .build()
        let extracted = try CADFindings.extract(from: try serializeAndParse(original))
        XCTAssertEqual(extracted.findings.count, 1)
        XCTAssertEqual(extracted.findings[0].probability ?? 0, 0.3, accuracy: 0.001)
        XCTAssertEqual(extracted.findings[0].certainty ?? 0, 0.9, accuracy: 0.001)
    }

    // MARK: - Multiple Findings Tests

    func testExtractMultipleFindings() throws {
        let imageRef = createImageReference()
        let original = try MammographyCADSRBuilder()
            .withCADProcessingSummary(algorithmName: "MammoCAD", algorithmVersion: "2.0", manufacturer: "Test Vendor")
            .addFinding(type: .mass, probability: 0.87, location: .point2D(x: 150.0, y: 250.0, imageReference: imageRef))
            .addFinding(type: .calcification, probability: 0.65, location: .point2D(x: 75.0, y: 125.0, imageReference: imageRef))
            .addFinding(type: .architecturalDistortion, probability: 0.55, location: .point2D(x: 200.0, y: 300.0, imageReference: imageRef))
            .build()
        let parsed = try serializeAndParse(original)

        let findings = try CADFindings.extract(from: parsed)

        XCTAssertEqual(findings.findings.count, 3)
        XCTAssertEqual(findings.findings[0].findingType?.codeValue, FindingType.mass.concept.codeValue)
        XCTAssertEqual(findings.findings[1].findingType?.codeValue, FindingType.calcification.concept.codeValue)
        XCTAssertEqual(findings.findings[2].findingType?.codeValue, FindingType.architecturalDistortion.concept.codeValue)
        XCTAssertEqual(findings.detectionsPerformed.count, 3)
    }

    func testExtractManyFindings() throws {
        let imageRef = createImageReference()
        var builder = MammographyCADSRBuilder()
            .withCADProcessingSummary(algorithmName: "MammoCAD", algorithmVersion: "2.0", manufacturer: "Test Vendor")

        for i in 1...10 {
            builder = builder.addFinding(
                type: .mass,
                probability: Double(i) * 0.1,
                location: .point2D(x: Double(i) * 10.0, y: Double(i) * 20.0, imageReference: imageRef)
            )
        }

        let original = try builder.build()
        let parsed = try serializeAndParse(original)
        let findings = try CADFindings.extract(from: parsed)

        XCTAssertEqual(findings.findings.count, 10)
        XCTAssertEqual(findings.findings.map { $0.probability ?? 0 }.map { ($0 * 10).rounded() }, (1...10).map(Double.init))
    }

    // MARK: - Finding Location Tests

    func testExtractFindingLocationPoint2D() throws {
        let imageRef = createImageReference()
        let original = try MammographyCADSRBuilder()
            .withCADProcessingSummary(algorithmName: "MammoCAD", algorithmVersion: "2.0", manufacturer: "Test Vendor")
            .addFinding(type: .mass, probability: 0.9, location: .point2D(x: 123.45, y: 234.56, imageReference: imageRef))
            .build()
        let parsed = try serializeAndParse(original)

        let findings = try CADFindings.extract(from: parsed)

        XCTAssertEqual(findings.findings.count, 1)
        XCTAssertNotNil(findings.findings[0].location)
        XCTAssertNil(findings.findings[0].outline)

        if case .point2D(let x, let y, let ref) = findings.findings[0].location {
            XCTAssertEqual(x, 123.45, accuracy: 0.01)
            XCTAssertEqual(y, 234.56, accuracy: 0.01)
            XCTAssertNotNil(ref)
        } else {
            XCTFail("Expected point2D location")
        }
    }

    func testExtractFindingLocationCircle() throws {
        let imageRef = createImageReference()
        let original = try MammographyCADSRBuilder()
            .withCADProcessingSummary(algorithmName: "MammoCAD", algorithmVersion: "2.0", manufacturer: "Test Vendor")
            .addFinding(type: .mass, probability: 0.85, location: .circle2D(centerX: 150.0, centerY: 200.0, radius: 25.0, imageReference: imageRef))
            .build()
        let parsed = try serializeAndParse(original)

        let findings = try CADFindings.extract(from: parsed)

        XCTAssertEqual(findings.findings.count, 1)
        // TID 4021 row 1: the Center is the location
        if case .point2D(let x, let y, _) = findings.findings[0].location {
            XCTAssertEqual(x, 150.0, accuracy: 0.01)
            XCTAssertEqual(y, 200.0, accuracy: 0.01)
        } else {
            XCTFail("Expected point2D location, got \(String(describing: findings.findings[0].location))")
        }
        // TID 4021 row 3: the Outline is the CIRCLE
        if case .circle(let cx, let cy, let rx, let ry, let ref) = findings.findings[0].outline {
            XCTAssertEqual(cx, 150.0, accuracy: 0.01)
            XCTAssertEqual(cy, 200.0, accuracy: 0.01)
            XCTAssertEqual(rx, 25.0, accuracy: 0.01)
            XCTAssertEqual(ry, 25.0, accuracy: 0.01)
            XCTAssertEqual(ref, imageRef)
        } else {
            XCTFail("Expected circle outline")
        }
    }

    func testExtractFindingLocationROI() throws {
        let imageRef = createImageReference()
        let roiPoints = [10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 10.0, 20.0]

        let original = try MammographyCADSRBuilder()
            .withCADProcessingSummary(algorithmName: "MammoCAD", algorithmVersion: "2.0", manufacturer: "Test Vendor")
            .addFinding(type: .mass, probability: 0.8, location: .roi2D(points: roiPoints, imageReference: imageRef))
            .build()
        let parsed = try serializeAndParse(original)

        let findings = try CADFindings.extract(from: parsed)

        XCTAssertEqual(findings.findings.count, 1)
        XCTAssertNotNil(findings.findings[0].location)

        if case .polyline(let points, _) = findings.findings[0].outline {
            XCTAssertEqual(points.count, 4)
        } else {
            XCTFail("Expected polyline outline")
        }
        if case .point2D(let x, let y, _) = findings.findings[0].location {
            XCTAssertEqual(x, 25, accuracy: 0.01)
            XCTAssertEqual(y, 35, accuracy: 0.01)
        } else {
            XCTFail("Expected point2D centre")
        }
    }

    // MARK: - Finding Descriptor Tests

    func testExtractFindingWithDescriptors() throws {
        // TID 4011 rows 1-3 under a Mammography breast density finding
        let imageRef = createImageReference()
        let shape = CADDescriptor(
            conceptName: CodedConcept(codeValue: "107644003", codingSchemeDesignator: "SCT", codeMeaning: "Shape"),
            value: CodedConcept(codeValue: "129734002", codingSchemeDesignator: "SCT", codeMeaning: "Irregular")
        )
        let margin = CADDescriptor(
            conceptName: CodedConcept(codeValue: "112233002", codingSchemeDesignator: "SCT", codeMeaning: "Margin"),
            value: CodedConcept(codeValue: "129740001", codingSchemeDesignator: "SCT", codeMeaning: "Spiculated")
        )
        let finding = CADFinding(type: .mass, probability: 0.92, location: .point2D(x: 150.0, y: 200.0, imageReference: imageRef),
                                 descriptors: [shape, margin])

        let original = try MammographyCADSRBuilder()
            .withCADProcessingSummary(algorithmName: "MammoCAD", algorithmVersion: "2.0", manufacturer: "Test Vendor")
            .addFinding(finding)
            .build()
        let parsed = try serializeAndParse(original)

        let findings = try CADFindings.extract(from: parsed)

        XCTAssertEqual(findings.findings.count, 1)
        XCTAssertEqual(findings.findings[0].descriptors, [shape, margin])
        XCTAssertEqual(findings.findings[0].characteristics, [shape.value, margin.value])
    }

    func testExtractFindingWithoutCharacteristics() throws {
        let imageRef = createImageReference()
        let original = try MammographyCADSRBuilder()
            .withCADProcessingSummary(algorithmName: "MammoCAD", algorithmVersion: "2.0", manufacturer: "Test Vendor")
            .addFinding(type: .mass, probability: 0.7, location: .point2D(x: 100.0, y: 150.0, imageReference: imageRef))
            .build()
        let parsed = try serializeAndParse(original)

        let findings = try CADFindings.extract(from: parsed)

        XCTAssertEqual(findings.findings.count, 1)
        XCTAssertEqual(findings.findings[0].characteristics.count, 0)
        XCTAssertEqual(findings.findings[0].descriptors.count, 0)
    }

    // MARK: - Probability Tests

    func testExtractFindingWithZeroProbability() throws {
        let imageRef = createImageReference()
        let original = try MammographyCADSRBuilder()
            .withCADProcessingSummary(algorithmName: "MammoCAD", algorithmVersion: "2.0", manufacturer: "Test Vendor")
            .addFinding(type: .mass, probability: 0.0, location: .point2D(x: 100.0, y: 100.0, imageReference: imageRef))
            .build()
        let parsed = try serializeAndParse(original)

        let findings = try CADFindings.extract(from: parsed)

        XCTAssertEqual(findings.findings.count, 1)
        XCTAssertEqual(findings.findings[0].probability ?? 0.0, 0.0)
    }

    func testExtractFindingWithMaxProbability() throws {
        let imageRef = createImageReference()
        let original = try MammographyCADSRBuilder()
            .withCADProcessingSummary(algorithmName: "MammoCAD", algorithmVersion: "2.0", manufacturer: "Test Vendor")
            .addFinding(type: .mass, probability: 1.0, location: .point2D(x: 100.0, y: 100.0, imageReference: imageRef))
            .build()
        let parsed = try serializeAndParse(original)

        let findings = try CADFindings.extract(from: parsed)

        XCTAssertEqual(findings.findings.count, 1)
        XCTAssertEqual(findings.findings[0].probability ?? 0.0, 1.0)
    }

    func testExtractFindingWithMidRangeProbability() throws {
        let imageRef = createImageReference()
        let original = try MammographyCADSRBuilder()
            .withCADProcessingSummary(algorithmName: "MammoCAD", algorithmVersion: "2.0", manufacturer: "Test Vendor")
            .addFinding(type: .mass, probability: 0.5432, location: .point2D(x: 100.0, y: 100.0, imageReference: imageRef))
            .build()
        let parsed = try serializeAndParse(original)

        let findings = try CADFindings.extract(from: parsed)

        XCTAssertEqual(findings.findings.count, 1)
        XCTAssertEqual(findings.findings[0].probability ?? 0.0, 0.5432, accuracy: 0.0001)
    }

    // MARK: - Error Cases Tests

    func testExtractFromInvalidDocumentType() throws {
        let document = try BasicTextSRBuilder()
            .build()
        let parsed = try serializeAndParse(document)

        XCTAssertThrowsError(try CADFindings.extract(from: parsed)) { error in
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

        XCTAssertThrowsError(try CADFindings.extract(from: parsed)) { error in
            guard case ExtractionError.invalidDocumentType = error else {
                XCTFail("Expected invalidDocumentType error")
                return
            }
        }
    }

    func testExtractFromKeyObjectSelection() throws {
        let keyObject = KeyObject(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9"
        )

        let document = try KeyObjectSelectionBuilder()
            .withDocumentTitle(.ofInterest)
            .addKeyObject(
                sopClassUID: keyObject.sopClassUID,
                sopInstanceUID: keyObject.sopInstanceUID
            )
            .build()
        let parsed = try serializeAndParse(document)

        XCTAssertThrowsError(try CADFindings.extract(from: parsed)) { error in
            guard case ExtractionError.invalidDocumentType = error else {
                XCTFail("Expected invalidDocumentType error")
                return
            }
        }
    }

    // MARK: - Chest CAD Specific Tests

    func testExtractChestCADNodule() throws {
        let imageRef = createImageReference()
        let original = try ChestCADSRBuilder()
            .withCADProcessingSummary(algorithmName: "ChestCAD", algorithmVersion: "3.0.0", manufacturer: "Example Medical Systems")
            .addFinding(type: .nodule, probability: 0.85, location: .point2D(x: 100.0, y: 150.0, imageReference: imageRef))
            .build()
        let parsed = try serializeAndParse(original)

        let findings = try CADFindings.extract(from: parsed)

        XCTAssertEqual(findings.cadType, .chest)
        XCTAssertEqual(findings.findings.count, 1)
        XCTAssertEqual(findings.findings[0].findingType?.codeValue, "112033")
        XCTAssertEqual(findings.findings[0].modifier?.codeValue, "27925004")
        XCTAssertEqual(findings.processingInfo.algorithmName, "ChestCAD")
        XCTAssertEqual(findings.processingInfo.manufacturer, "Example Medical Systems")
    }

    func testExtractChestCADMultipleFindings() throws {
        let imageRef = createImageReference()
        let size = CADDescriptor(
            conceptName: CodedConcept(codeValue: "112025", codingSchemeDesignator: "DCM", codeMeaning: "Size Descriptor"),
            value: CodedConcept(codeValue: "255507004", codingSchemeDesignator: "SCT", codeMeaning: "Small")
        )
        let original = try ChestCADSRBuilder()
            .withCADProcessingSummary(algorithmName: "ChestCAD", algorithmVersion: "3.0", manufacturer: "Test Vendor")
            .addFinding(ChestCADFinding(type: .nodule, probability: 0.85, location: .point2D(x: 100.0, y: 150.0, imageReference: imageRef), descriptors: [size]))
            .addFinding(type: .mass, probability: 0.72, location: .circle2D(centerX: 200.0, centerY: 250.0, radius: 10, imageReference: imageRef))
            .build()
        let parsed = try serializeAndParse(original)

        let findings = try CADFindings.extract(from: parsed)

        XCTAssertEqual(findings.findings.count, 2)
        XCTAssertEqual(findings.findings[0].descriptors, [size])
        XCTAssertEqual(findings.findings[0].probability ?? 0, 0.85, accuracy: 0.001)
        XCTAssertEqual(findings.findings[1].modifier?.codeValue, "4147007")
        XCTAssertEqual(findings.findings[1].probability ?? 0, 0.72, accuracy: 0.001)
        XCTAssertNotNil(findings.findings[1].outline)
        XCTAssertEqual(findings.detectionsPerformed.map(\.codeValue), ["27925004", "4147007"])
    }

    // MARK: - Complete Workflow Tests

    func testCompleteWorkflowMammography() throws {
        let imageRef = createImageReference()

        let original = try MammographyCADSRBuilder()
            .withPatientID("CAD-2024-001")
            .withPatientName("Smith^Jane")
            .withPatientBirthDate("19750615")
            .withPatientSex("F")
            .withStudyInstanceUID("1.2.840.113619.2.5.1762583153.215519.978957063.100")
            .withStudyDate("20240115")
            .withCADProcessingSummary(
                algorithmName: "MammoCare CAD",
                algorithmVersion: "3.2.1",
                manufacturer: "Digital Mammography Systems Inc"
            )
            .addFinding(type: .mass, probability: 0.87,
                        location: .circle2D(centerX: 245.5, centerY: 389.2, radius: 18.5, imageReference: imageRef))
            .addFinding(type: .calcification, probability: 0.64,
                        location: .point2D(x: 156.3, y: 425.8, imageReference: imageRef))
            .build()

        let parsed = try serializeAndParse(original)
        let extracted = try CADFindings.extract(from: parsed)

        // Verify document information
        XCTAssertEqual(extracted.cadType, .mammography)
        XCTAssertEqual(extracted.document.patientID, "CAD-2024-001")

        // Verify processing info
        XCTAssertEqual(extracted.processingInfo.algorithmName, "MammoCare CAD")
        XCTAssertEqual(extracted.processingInfo.algorithmVersion, "3.2.1")
        XCTAssertEqual(extracted.processingInfo.manufacturer, "Digital Mammography Systems Inc")

        // Verify findings
        XCTAssertEqual(extracted.findings.count, 2)

        // The finding types round-trip as the CID 6015 concepts the builder writes
        let massFindings = extracted.findings.filter { $0.findingType?.codeValue == FindingType.mass.concept.codeValue }
        XCTAssertEqual(massFindings.count, 1)
        XCTAssertEqual(massFindings.first?.probability ?? 0.0, 0.87, accuracy: 0.01)

        let calcFindings = extracted.findings.filter { $0.findingType?.codeValue == FindingType.calcification.concept.codeValue }
        XCTAssertEqual(calcFindings.count, 1)
        XCTAssertEqual(calcFindings.first?.probability ?? 0.0, 0.64, accuracy: 0.01)
    }

    func testCompleteWorkflowChest() throws {
        let imageRef = createImageReference()

        let original = try ChestCADSRBuilder()
            .withPatientID("CHEST-2024-001")
            .withPatientName("Doe^John")
            .withStudyInstanceUID("1.2.840.113619.2.5.1762583153.215519.978957063.200")
            .withCADProcessingSummary(algorithmName: "LungCAD Pro", algorithmVersion: "4.1.0", manufacturer: "Pulmonary Imaging Systems")
            .addFinding(type: .nodule, probability: 0.92, location: .point2D(x: 150.0, y: 200.0, imageReference: imageRef))
            .addFinding(type: .nodule, probability: 0.68, location: .point2D(x: 100.0, y: 150.0, imageReference: imageRef))
            .build()

        let parsed = try serializeAndParse(original)
        let extracted = try CADFindings.extract(from: parsed)

        XCTAssertEqual(extracted.cadType, .chest)
        XCTAssertEqual(extracted.document.patientID, "CHEST-2024-001")
        XCTAssertEqual(extracted.processingInfo.algorithmName, "LungCAD Pro")
        XCTAssertEqual(extracted.findings.count, 2)
        XCTAssertEqual(extracted.findings.map { ($0.probability ?? 0) * 100 }.map { $0.rounded() }, [92, 68])
    }

    // MARK: - Edge Cases Tests

    func testExtractWithNoFindings() throws {
        let original = try MammographyCADSRBuilder(validateOnBuild: false)
            .withCADProcessingSummary(algorithmName: "MammoCAD", algorithmVersion: "2.0", manufacturer: "Test Vendor")
            .build()
        let parsed = try serializeAndParse(original)

        let findings = try CADFindings.extract(from: parsed)

        // Should extract successfully but have no findings
        XCTAssertEqual(findings.findings.count, 0)
    }

    func testExtractWithCustomFindingType() throws {
        let imageRef = createImageReference()
        let customType = CodedConcept(
            codeValue: "CUSTOM-001",
            codingSchemeDesignator: "99TEST",
            codeMeaning: "Custom Finding Type"
        )

        let original = try MammographyCADSRBuilder()
            .withCADProcessingSummary(algorithmName: "MammoCAD", algorithmVersion: "2.0", manufacturer: "Test Vendor")
            .addFinding(type: .custom(customType), probability: 0.75, location: .point2D(x: 100.0, y: 150.0, imageReference: imageRef))
            .build()
        let parsed = try serializeAndParse(original)

        let findings = try CADFindings.extract(from: parsed)

        XCTAssertEqual(findings.findings.count, 1)
        XCTAssertEqual(findings.findings[0].findingType?.codeValue, "CUSTOM-001")
    }

    func testExtractFindingWithImageReference() throws {
        let imageRef = ImageReference(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9.10"
        )

        let original = try MammographyCADSRBuilder()
            .withCADProcessingSummary(algorithmName: "MammoCAD", algorithmVersion: "2.0", manufacturer: "Test Vendor")
            .addFinding(type: .mass, probability: 0.8, location: .point2D(x: 100.0, y: 150.0, imageReference: imageRef))
            .build()
        let parsed = try serializeAndParse(original)

        let findings = try CADFindings.extract(from: parsed)

        XCTAssertEqual(findings.findings.count, 1)
        XCTAssertNotNil(findings.findings[0].imageReference)
        XCTAssertEqual(findings.findings[0].imageReference?.sopReference.sopInstanceUID, "1.2.3.4.5.6.7.8.9.10")
    }

    // MARK: - Layout written before the 2026a check

    func testExtractLegacyContainerLayout() throws {
        // Before the 2026a check each finding was a CONTAINER (111034, DCM) of CONTAINS items:
        // CODE (111059, DCM) type, NUM (111047, DCM) 0-1 with (1, UCUM), SCOORD (111010, DCM),
        // IMAGE SELECTED FROM, CODE (121071, DCM) characteristics; the algorithm sat in a
        // CONTAINER (111017, DCM) of CONTAINS TEXT items.
        let imageRef = createImageReference()
        let spiculated = CodedConcept(codeValue: "M-78060", codingSchemeDesignator: "SRT", codeMeaning: "Spiculated margin")
        let summary = ContainerContentItem(
            conceptName: dcm("111017", "CAD Processing and Findings Summary"),
            contentItems: [
                AnyContentItem(TextContentItem(conceptName: dcm("111001", "Algorithm Name"), textValue: "OldCAD", relationshipType: .contains)),
                AnyContentItem(TextContentItem(conceptName: dcm("111003", "Algorithm Version"), textValue: "1.0", relationshipType: .contains)),
                AnyContentItem(TextContentItem(conceptName: dcm("122405", "Algorithm Manufacturer"), textValue: "Old Vendor", relationshipType: .contains))
            ],
            relationshipType: .contains
        )
        let finding = ContainerContentItem(
            conceptName: dcm("111034", "Individual Impression/Recommendation"),
            contentItems: [
                AnyContentItem(CodeContentItem(conceptName: dcm("111059", "Single Image Finding"), conceptCode: FindingType.mass.concept, relationshipType: .contains)),
                AnyContentItem(NumericContentItem(conceptName: dcm("111047", "Probability of cancer"), value: 0.85,
                                                  units: CodedConcept(codeValue: "1", codingSchemeDesignator: "UCUM", codeMeaning: "no units"),
                                                  relationshipType: .contains)),
                AnyContentItem(SpatialCoordinatesContentItem(conceptName: dcm("111010", "Center"), graphicType: .point, graphicData: [10, 20], relationshipType: .contains)),
                AnyContentItem(ImageContentItem(conceptName: nil, imageReference: imageRef, relationshipType: .selectedFrom)),
                AnyContentItem(CodeContentItem(conceptName: dcm("121071", "Finding"), conceptCode: spiculated, relationshipType: .contains))
            ],
            relationshipType: .contains
        )
        let root = ContainerContentItem(conceptName: dcm("111036", "Mammography CAD Report"), contentItems: [AnyContentItem(summary), AnyContentItem(finding)])
        let document = SRDocument(sopClassUID: SRDocumentType.mammographyCADSR.sopClassUID, sopInstanceUID: "1.2.3", modality: "SR",
                                  documentTitle: dcm("111036", "Mammography CAD Report"), rootContent: root)

        let extracted = try CADFindings.extract(from: try serializeAndParse(document))
        XCTAssertEqual(extracted.processingInfo.algorithmName, "OldCAD")
        XCTAssertEqual(extracted.processingInfo.algorithmVersion, "1.0")
        XCTAssertEqual(extracted.processingInfo.manufacturer, "Old Vendor")
        XCTAssertEqual(extracted.findings.count, 1)
        XCTAssertEqual(extracted.findings[0].findingType, FindingType.mass.concept)
        XCTAssertEqual(extracted.findings[0].probability ?? 0, 0.85, accuracy: 0.001)
        XCTAssertEqual(extracted.findings[0].characteristics, [spiculated])
        XCTAssertEqual(extracted.findings[0].imageReference, imageRef)
        if case .point2D(let x, let y, _) = extracted.findings[0].location {
            XCTAssertEqual(x, 10)
            XCTAssertEqual(y, 20)
        } else {
            XCTFail("Expected point2D location")
        }
        XCTAssertNil(extracted.language)
        XCTAssertEqual(extracted.imageLibrary, [])
    }
}
