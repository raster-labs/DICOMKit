/// Tests for MammographyCADSRBuilder
///
/// Validates the creation and validation of Mammography CAD SR documents and walks the
/// produced content tree against PS3.16 2026a TID 4000, 1204, 4020, 4001, 4003, 4006, 4011,
/// 4015, 4017, 4016, 4018, 4019 and 4021 (Type M rows), with the CID 6014, 6034, 6042 and
/// 6047 values.

import XCTest
@testable import DICOMKit
@testable import DICOMCore

final class MammographyCADSRBuilderTests: XCTestCase {

    // MARK: - Helper Methods

    private func createBasicBuilder() -> MammographyCADSRBuilder {
        MammographyCADSRBuilder()
            .withPatientID("12345")
            .withPatientName("Doe^Jane")
            .withStudyInstanceUID("1.2.3.4.5")
            .withCADProcessingSummary(
                algorithmName: "MammoCAD",
                algorithmVersion: "2.1.0",
                manufacturer: "Example Medical Systems"
            )
    }

    private func createSampleImageReference() -> ImageReference {
        ImageReference(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.1.2", // Digital Mammography X-Ray Image Storage
            sopInstanceUID: "1.2.3.4.5.6.7.8.9"
        )
    }

    /// A content item's (relationship, value type, concept name code value)
    private func row(_ item: AnyContentItem) -> (RelationshipType?, ContentItemValueType, String?) {
        (item.relationshipType, item.valueType, item.conceptName?.codeValue)
    }

    private func assertRow(
        _ item: AnyContentItem, _ relationship: RelationshipType?, _ valueType: ContentItemValueType, _ concept: String?,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let actual = row(item)
        XCTAssertEqual(actual.0, relationship, "relationship of \(item)", file: file, line: line)
        XCTAssertEqual(actual.1, valueType, "value type of \(item)", file: file, line: line)
        XCTAssertEqual(actual.2, concept, "concept name of \(item)", file: file, line: line)
    }

    /// The items and all their descendants in document order: CONTAINER contents and the
    /// Content Sequence of CODE/IMAGE/SCOORD items (PS3.3 Table C.17-6)
    private func descendants(_ items: [AnyContentItem]) -> [AnyContentItem] {
        items.flatMap { [$0] + descendants($0.contentItems) }
    }

    /// The (111034, DCM) Individual Impression/Recommendation containers: TID 4001 row 3,
    /// INFERRED FROM children of the (111017, DCM) CODE (TID 4000 row 5)
    private func impressions(_ document: SRDocument) -> [ContainerContentItem] {
        let summary = document.rootContent.contentItems.first { $0.conceptName?.codeValue == "111017" }
        return (summary?.contentItems ?? []).compactMap { $0.asContainer }.filter { $0.conceptName?.codeValue == "111034" }
    }

    // MARK: - Initialization Tests

    func testBuilderInitialization() {
        let builder = MammographyCADSRBuilder()
        XCTAssertTrue(builder.validateOnBuild)
        XCTAssertNil(builder.sopInstanceUID)
        XCTAssertNil(builder.patientID)
        XCTAssertEqual(builder.findings.count, 0)
        XCTAssertEqual(builder.completionFlag, .complete)
        XCTAssertEqual(builder.verificationFlag, .unverified)
        // TID 1204 row 1 is Type M: the language defaults to an RFC 5646 tag (CID 5000)
        XCTAssertEqual(builder.language.codingSchemeDesignator, "RFC5646")
        XCTAssertEqual(builder.language.codeValue, "en")
    }

    func testBuilderInitializationWithoutValidation() {
        let builder = MammographyCADSRBuilder(validateOnBuild: false)
        XCTAssertFalse(builder.validateOnBuild)
    }

    // MARK: - Patient Information Tests

    func testWithPatientID() {
        let builder = MammographyCADSRBuilder()
            .withPatientID("12345")
        XCTAssertEqual(builder.patientID, "12345")
    }

    func testWithPatientName() {
        let builder = MammographyCADSRBuilder()
            .withPatientName("Doe^Jane")
        XCTAssertEqual(builder.patientName, "Doe^Jane")
    }

    func testWithPatientBirthDate() {
        let builder = MammographyCADSRBuilder()
            .withPatientBirthDate("19700101")
        XCTAssertEqual(builder.patientBirthDate, "19700101")
    }

    func testWithPatientSex() {
        let builder = MammographyCADSRBuilder()
            .withPatientSex("F")
        XCTAssertEqual(builder.patientSex, "F")
    }

    // MARK: - Study Information Tests

    func testWithStudyInstanceUID() {
        let builder = MammographyCADSRBuilder()
            .withStudyInstanceUID("1.2.3.4.5")
        XCTAssertEqual(builder.studyInstanceUID, "1.2.3.4.5")
    }

    func testWithStudyDate() {
        let builder = MammographyCADSRBuilder()
            .withStudyDate("20240101")
        XCTAssertEqual(builder.studyDate, "20240101")
    }

    func testWithStudyTime() {
        let builder = MammographyCADSRBuilder()
            .withStudyTime("120000")
        XCTAssertEqual(builder.studyTime, "120000")
    }

    func testWithStudyDescription() {
        let builder = MammographyCADSRBuilder()
            .withStudyDescription("Screening Mammography")
        XCTAssertEqual(builder.studyDescription, "Screening Mammography")
    }

    func testWithAccessionNumber() {
        let builder = MammographyCADSRBuilder()
            .withAccessionNumber("ACC123")
        XCTAssertEqual(builder.accessionNumber, "ACC123")
    }

    func testWithReferringPhysicianName() {
        let builder = MammographyCADSRBuilder()
            .withReferringPhysicianName("Smith^John")
        XCTAssertEqual(builder.referringPhysicianName, "Smith^John")
    }

    // MARK: - Series Information Tests

    func testWithSeriesInstanceUID() {
        let builder = MammographyCADSRBuilder()
            .withSeriesInstanceUID("1.2.3.4.5.6")
        XCTAssertEqual(builder.seriesInstanceUID, "1.2.3.4.5.6")
    }

    func testWithSeriesNumber() {
        let builder = MammographyCADSRBuilder()
            .withSeriesNumber("2")
        XCTAssertEqual(builder.seriesNumber, "2")
    }

    func testWithSeriesDescription() {
        let builder = MammographyCADSRBuilder()
            .withSeriesDescription("CAD Analysis")
        XCTAssertEqual(builder.seriesDescription, "CAD Analysis")
    }

    // MARK: - Document Information Tests

    func testWithSOPInstanceUID() {
        let builder = MammographyCADSRBuilder()
            .withSOPInstanceUID("1.2.3.4.5.6.7")
        XCTAssertEqual(builder.sopInstanceUID, "1.2.3.4.5.6.7")
    }

    func testWithInstanceNumber() {
        let builder = MammographyCADSRBuilder()
            .withInstanceNumber("1")
        XCTAssertEqual(builder.instanceNumber, "1")
    }

    func testWithContentDate() {
        let builder = MammographyCADSRBuilder()
            .withContentDate("20240101")
        XCTAssertEqual(builder.contentDate, "20240101")
    }

    func testWithContentTime() {
        let builder = MammographyCADSRBuilder()
            .withContentTime("120000")
        XCTAssertEqual(builder.contentTime, "120000")
    }

    func testWithCompletionFlag() {
        let builder = MammographyCADSRBuilder()
            .withCompletionFlag(.partial)
        XCTAssertEqual(builder.completionFlag, .partial)
    }

    func testWithVerificationFlag() {
        let builder = MammographyCADSRBuilder()
            .withVerificationFlag(.verified)
        XCTAssertEqual(builder.verificationFlag, .verified)
    }

    // MARK: - CAD Processing Summary Tests

    func testWithCADProcessingSummary() {
        let builder = MammographyCADSRBuilder()
            .withCADProcessingSummary(
                algorithmName: "MammoCAD",
                algorithmVersion: "2.1.0",
                manufacturer: "Example Medical Systems",
                processingDateTime: "20240101120000"
            )

        XCTAssertEqual(builder.algorithmName, "MammoCAD")
        XCTAssertEqual(builder.algorithmVersion, "2.1.0")
        XCTAssertEqual(builder.manufacturer, "Example Medical Systems")
        // TID 4019
        XCTAssertEqual(builder.algorithmIdentification, CADAlgorithmIdentification(name: "MammoCAD", version: "2.1.0", manufacturer: "Example Medical Systems"))
    }

    func testWithLanguage() {
        let french = CodedConcept(codeValue: "fr", codingSchemeDesignator: "RFC5646", codeMeaning: "French")
        let canada = CodedConcept(codeValue: "CA", codingSchemeDesignator: "ISO3166_1", codeMeaning: "Canada")
        let builder = MammographyCADSRBuilder().withLanguage(french, country: canada)
        XCTAssertEqual(builder.language, french)
        XCTAssertEqual(builder.countryOfLanguage, canada)
    }

    // MARK: - Finding Management Tests

    func testAddFindingWithStruct() {
        let imageRef = createSampleImageReference()
        let finding = CADFinding(
            type: .mass,
            probability: 0.85,
            location: .point2D(x: 128.5, y: 256.3, imageReference: imageRef)
        )

        let builder = createBasicBuilder()
            .addFinding(finding)

        XCTAssertEqual(builder.findings.count, 1)
        XCTAssertEqual(builder.findings[0], finding)
        XCTAssertEqual(builder.findings[0].renderingIntent, .presentationRequired)
    }

    func testAddFindingWithParameters() {
        let imageRef = createSampleImageReference()
        let builder = createBasicBuilder()
            .addFinding(
                type: .mass,
                probability: 0.85,
                location: .point2D(x: 128.5, y: 256.3, imageReference: imageRef)
            )

        XCTAssertEqual(builder.findings.count, 1)
        XCTAssertEqual(builder.findings[0].type, .mass)
        XCTAssertEqual(builder.findings[0].probability, 0.85, accuracy: 0.001)
    }

    func testAddMultipleFindings() {
        let imageRef = createSampleImageReference()
        let builder = createBasicBuilder()
            .addFinding(
                type: .mass,
                probability: 0.85,
                location: .point2D(x: 128.5, y: 256.3, imageReference: imageRef)
            )
            .addFinding(
                type: .calcification,
                probability: 0.72,
                location: .point2D(x: 64.2, y: 128.7, imageReference: imageRef)
            )

        XCTAssertEqual(builder.findings.count, 2)
        XCTAssertEqual(builder.findings[0].type, .mass)
        XCTAssertEqual(builder.findings[1].type, .calcification)
    }

    func testClearFindings() {
        let imageRef = createSampleImageReference()
        let builder = createBasicBuilder()
            .addFinding(
                type: .mass,
                probability: 0.85,
                location: .point2D(x: 128.5, y: 256.3, imageReference: imageRef)
            )
            .clearFindings()

        XCTAssertEqual(builder.findings.count, 0)
    }

    // MARK: - Finding Type Tests (TID 4006 row 1 values, CID 6014 / CID 6015)

    func testFindingTypeMass() {
        let concept = FindingType.mass.concept
        // PS3.16 CID 6015 Single Image Finding from BI-RADS
        XCTAssertEqual(concept.codeValue, "129793001")
        XCTAssertEqual(concept.codingSchemeDesignator, "SCT")
        XCTAssertEqual(concept.codeMeaning, "Mammography breast density")
    }

    func testFindingTypeCalcification() {
        let concept = FindingType.calcification.concept
        XCTAssertEqual(concept.codeValue, "129770007")
        XCTAssertEqual(concept.codingSchemeDesignator, "SCT")
        XCTAssertEqual(concept.codeMeaning, "Individual Calcification")
    }

    func testFindingTypeArchitecturalDistortion() {
        let concept = FindingType.architecturalDistortion.concept
        XCTAssertEqual(concept.codeValue, "129792006")
        XCTAssertEqual(concept.codingSchemeDesignator, "SCT")
        XCTAssertEqual(concept.codeMeaning, "Architectural distortion of breast")
    }

    func testCompositeFeatureValuesAreRejectedAsSingleImageFindings() {
        // CID 6017 (Composite Feature) values are not in CID 6014 (TID 4006 row 1)
        let imageRef = createSampleImageReference()
        let asymmetric = CodedConcept(codeValue: "129790003", codingSchemeDesignator: "SCT", codeMeaning: "Asymmetric breast tissue")
        let builder = createBasicBuilder()
            .addFinding(type: .custom(asymmetric), probability: 0.4, location: .point2D(x: 1, y: 1, imageReference: imageRef))
        XCTAssertThrowsError(try builder.build()) { error in
            guard case MammographyCADSRBuilder.BuildError.validationError(let message) = error else {
                return XCTFail("Expected validationError")
            }
            XCTAssertTrue(message.contains("CID 6014"))
        }
    }

    func testFindingTypeCustom() {
        let customConcept = CodedConcept(
            codeValue: "CUSTOM-001",
            codingSchemeDesignator: "99TEST",
            codeMeaning: "Custom Finding"
        )
        let concept = FindingType.custom(customConcept).concept
        XCTAssertEqual(concept.codeValue, "CUSTOM-001")
        XCTAssertEqual(concept.codingSchemeDesignator, "99TEST")
        XCTAssertEqual(concept.codeMeaning, "Custom Finding")
    }

    // MARK: - Finding Location Tests

    func testFindingLocationPoint2D() {
        let imageRef = createSampleImageReference()
        let location = FindingLocation.point2D(x: 128.5, y: 256.3, imageReference: imageRef)

        switch location {
        case .point2D(let x, let y, let ref):
            XCTAssertEqual(x, 128.5, accuracy: 0.001)
            XCTAssertEqual(y, 256.3, accuracy: 0.001)
            XCTAssertEqual(ref, imageRef)
        default:
            XCTFail("Expected point2D location")
        }
        XCTAssertEqual(location.imageReference, imageRef)
    }

    func testFindingLocationROI2D() {
        let imageRef = createSampleImageReference()
        let points = [10.0, 20.0, 30.0, 40.0, 50.0, 60.0]
        let location = FindingLocation.roi2D(points: points, imageReference: imageRef)

        switch location {
        case .roi2D(let pts, let ref):
            XCTAssertEqual(pts, points)
            XCTAssertEqual(ref, imageRef)
        default:
            XCTFail("Expected roi2D location")
        }
    }

    func testFindingLocationCircle2D() {
        let imageRef = createSampleImageReference()
        let location = FindingLocation.circle2D(
            centerX: 128.0,
            centerY: 256.0,
            radius: 30.0,
            imageReference: imageRef
        )

        switch location {
        case .circle2D(let cx, let cy, let r, let ref):
            XCTAssertEqual(cx, 128.0, accuracy: 0.001)
            XCTAssertEqual(cy, 256.0, accuracy: 0.001)
            XCTAssertEqual(r, 30.0, accuracy: 0.001)
            XCTAssertEqual(ref, imageRef)
        default:
            XCTFail("Expected circle2D location")
        }
    }

    // MARK: - Build Tests

    func testBuildBasicDocument() throws {
        let imageRef = createSampleImageReference()
        let builder = createBasicBuilder()
            .addFinding(
                type: .mass,
                probability: 0.85,
                location: .point2D(x: 128.5, y: 256.3, imageReference: imageRef)
            )

        let document = try builder.build()

        XCTAssertEqual(document.sopClassUID, SRDocumentType.mammographyCADSR.sopClassUID)
        XCTAssertEqual(document.patientID, "12345")
        XCTAssertEqual(document.patientName, "Doe^Jane")
        XCTAssertEqual(document.modality, "SR")
        // TID 4000 row 1
        XCTAssertEqual(document.documentTitle?.codeValue, "111036")
        XCTAssertEqual(document.documentTitle?.codeMeaning, "Mammography CAD Report")
    }

    // MARK: - Template walk (TID 4000 and the templates it includes)

    func testContentTreeFollowsTID4000() throws {
        let imageRef = createSampleImageReference()
        let document = try createBasicBuilder()
            .addFinding(type: .mass, probability: 0.85, location: .point2D(x: 128.5, y: 256.3, imageReference: imageRef))
            .build()

        let root = document.rootContent
        // TID 4000 row 1: CONTAINER EV (111036, DCM, "Mammography CAD Report"), root node
        XCTAssertNil(root.relationshipType)
        XCTAssertEqual(root.conceptName?.codeValue, "111036")
        XCTAssertEqual(root.templateIdentifier, "4000")
        XCTAssertEqual(root.mappingResource, "DCMR")

        let items = root.contentItems
        XCTAssertEqual(items.count, 5, "\(items)")

        // Row 2: HAS CONCEPT MOD INCLUDE TID 1204 -> row 1 CODE (121049, DCM), DCID 5000
        assertRow(items[0], .hasConceptMod, .code, "121049")
        XCTAssertEqual(items[0].asCode?.conceptCode.codingSchemeDesignator, "RFC5646")

        // Row 3: CONTAINS CONTAINER (111028, DCM, "Image Library"); row 4: CONTAINS INCLUDE TID 4020 (IMAGE)
        assertRow(items[1], .contains, .container, "111028")
        let library = try XCTUnwrap(items[1].asContainer)
        XCTAssertEqual(library.contentItems.count, 1)
        assertRow(library.contentItems[0], .contains, .image, nil)
        XCTAssertEqual(library.contentItems[0].asImage?.imageReference, imageRef)

        // Row 5: CONTAINS INCLUDE TID 4001 -> row 1 CODE (111017, DCM), DCID 6047
        assertRow(items[2], .contains, .code, "111017")
        XCTAssertEqual(items[2].asCode?.conceptCode.codeValue, "111242") // All algorithms succeeded; with findings

        // TID 4001 row 3 (">"): INFERRED FROM INCLUDE TID 4003 -> CONTAINER (111034, DCM),
        // nested in the Content Sequence of the row 1 CODE (PS3.3 Table C.17-6)
        XCTAssertEqual(items[2].contentItems.count, 1)
        assertRow(items[2].contentItems[0], .inferredFrom, .container, "111034")
        let impression = try XCTUnwrap(items[2].contentItems[0].asContainer)
        XCTAssertEqual(impression.contentItems.count, 2)
        // TID 4003 row 2: HAS CONCEPT MOD CODE (111056, DCM, "Rendering Intent"), DCID 6034
        assertRow(impression.contentItems[0], .hasConceptMod, .code, "111056")
        XCTAssertEqual(impression.contentItems[0].asCode?.conceptCode.codeValue, "111150")
        // TID 4003 row 5: CONTAINS INCLUDE TID 4006 -> row 1 CODE (111059, DCM), DCID 6014
        assertRow(impression.contentItems[1], .contains, .code, "111059")
        XCTAssertEqual(impression.contentItems[1].asCode?.conceptCode, FindingType.mass.concept)

        // TID 4006 rows 2-8 (">"), nested in the 111059 CODE's Content Sequence
        let findingRows = impression.contentItems[1].contentItems
        XCTAssertEqual(findingRows.count, 6, "\(findingRows)")
        // Row 2: HAS CONCEPT MOD CODE Rendering Intent
        assertRow(findingRows[0], .hasConceptMod, .code, "111056")
        // Row 5: HAS PROPERTIES INCLUDE TID 4019 -> TEXT 111001, TEXT 111003, TEXT 122405
        assertRow(findingRows[1], .hasProperties, .text, "111001")
        XCTAssertEqual(findingRows[1].asText?.textValue, "MammoCAD")
        assertRow(findingRows[2], .hasProperties, .text, "111003")
        XCTAssertEqual(findingRows[2].asText?.textValue, "2.1.0")
        assertRow(findingRows[3], .hasProperties, .text, "122405")
        XCTAssertEqual(findingRows[3].asText?.textValue, "Example Medical Systems")
        // Row 7: HAS PROPERTIES NUM (111047, DCM, "Probability of cancer"), UNITS (%, UCUM), 0-100
        assertRow(findingRows[4], .hasProperties, .num, "111047")
        XCTAssertEqual(findingRows[4].asNumeric?.value ?? 0, 85, accuracy: 0.0001)
        XCTAssertEqual(findingRows[4].asNumeric?.measurementUnits?.codeValue, "%")
        XCTAssertEqual(findingRows[4].asNumeric?.measurementUnits?.codingSchemeDesignator, "UCUM")
        // Row 8: HAS PROPERTIES INCLUDE TID 4021 -> row 1 SCOORD (111010, DCM, "Center"), POINT;
        // row 2 (">") SELECTED FROM IMAGE, nested in the SCOORD
        assertRow(findingRows[5], .hasProperties, .scoord, "111010")
        XCTAssertEqual(findingRows[5].asSpatialCoordinates?.graphicType, .point)
        XCTAssertEqual(findingRows[5].asSpatialCoordinates?.graphicData, [128.5, 256.3])
        XCTAssertEqual(findingRows[5].contentItems.count, 1)
        assertRow(findingRows[5].contentItems[0], .selectedFrom, .image, nil)
        XCTAssertEqual(findingRows[5].contentItems[0].asImage?.imageReference, imageRef)
        // Row 6: CONTAINS CODE (111064, DCM, "Summary of Detections"), DCID 6042
        assertRow(items[3], .contains, .code, "111064")
        XCTAssertEqual(items[3].asCode?.conceptCode.codeValue, "111222") // Succeeded
        // Row 7 (">>"): INFERRED FROM INCLUDE TID 4015 -> row 1 CONTAINER (111063, DCM,
        // "Successful Detections"), nested in the Summary of Detections CODE
        XCTAssertEqual(items[3].contentItems.count, 1)
        assertRow(items[3].contentItems[0], .inferredFrom, .container, "111063")
        let detections = try XCTUnwrap(items[3].contentItems[0].asContainer)
        // TID 4015 row 2: CONTAINS INCLUDE TID 4017 -> row 1 CODE (111022, DCM, "Detection Performed") = $DetectionCode (DCID 6014)
        XCTAssertEqual(detections.contentItems.count, 1)
        assertRow(detections.contentItems[0], .contains, .code, "111022")
        XCTAssertEqual(detections.contentItems[0].asCode?.conceptCode, FindingType.mass.concept)
        // TID 4017 rows 2-3 (">"), nested in the Detection Performed CODE: HAS PROPERTIES
        // INCLUDE TID 4019; HAS PROPERTIES IMAGE
        let detectionRows = detections.contentItems[0].contentItems
        XCTAssertEqual(detectionRows.count, 4)
        assertRow(detectionRows[0], .hasProperties, .text, "111001")
        assertRow(detectionRows[1], .hasProperties, .text, "111003")
        assertRow(detectionRows[2], .hasProperties, .text, "122405")
        assertRow(detectionRows[3], .hasProperties, .image, nil)

        // Row 8: CONTAINS CODE (111065, DCM, "Summary of Analyses"), DCID 6042: Not Attempted, so no TID 4016 (row 9 condition)
        assertRow(items[4], .contains, .code, "111065")
        XCTAssertEqual(items[4].asCode?.conceptCode.codeValue, "111225")
        XCTAssertTrue(items[4].contentItems.isEmpty)
    }

    func testCircleLocationWritesCenterAndOutline() throws {
        let imageRef = createSampleImageReference()
        let document = try createBasicBuilder()
            .addFinding(type: .mass, probability: 0.5, location: .circle2D(centerX: 200, centerY: 300, radius: 25, imageReference: imageRef))
            .build()
        let impression = try XCTUnwrap(impressions(document).first)
        let finding = try XCTUnwrap(impression.contentItems.first { $0.conceptName?.codeValue == "111059" })
        let scoords = finding.contentItems.compactMap { $0.asSpatialCoordinates }
        // TID 4021 row 1: Center POINT; row 3: Outline (CIRCLE: centre and a point on the circumference, PS3.3 C.18.6.1.2)
        XCTAssertEqual(scoords.map { $0.conceptName?.codeValue }, ["111010", "111041"])
        XCTAssertEqual(scoords[0].graphicType, .point)
        XCTAssertEqual(scoords[0].graphicData, [200, 300])
        XCTAssertEqual(scoords[1].graphicType, .circle)
        XCTAssertEqual(scoords[1].graphicData, [200, 300, 225, 300])
        // Rows 2 and 4 (">"): each SELECTED FROM the same image, nested in its SCOORD
        XCTAssertTrue(scoords.allSatisfy { $0.contentItems.count == 1 })
        let images = scoords.flatMap { $0.contentItems }.filter { $0.asImage != nil }
        XCTAssertEqual(images.count, 2)
        XCTAssertTrue(images.allSatisfy { $0.relationshipType == .selectedFrom && $0.asImage?.imageReference == imageRef })
    }

    func testROILocationWritesCentroidAndPolylineOutline() throws {
        let imageRef = createSampleImageReference()
        let document = try createBasicBuilder()
            .addFinding(type: .mass, probability: 0.5, location: .roi2D(points: [0, 0, 10, 0, 10, 10, 0, 10], imageReference: imageRef))
            .build()
        let impression = try XCTUnwrap(impressions(document).first)
        let scoords = descendants(impression.contentItems).compactMap { $0.asSpatialCoordinates }
        XCTAssertEqual(scoords.map { $0.conceptName?.codeValue }, ["111010", "111041"])
        XCTAssertEqual(scoords[0].graphicData, [5, 5])
        XCTAssertEqual(scoords[1].graphicType, .polyline)
        XCTAssertEqual(scoords[1].graphicData, [0, 0, 10, 0, 10, 10, 0, 10])
    }

    func testDescriptorsAreWrittenOnlyForBreastDensity() throws {
        // TID 4006 row 14: TID 4011 only for (129793001, SCT, "Mammography breast density")
        let imageRef = createSampleImageReference()
        let shape = CADDescriptor(
            conceptName: CodedConcept(codeValue: "107644003", codingSchemeDesignator: "SCT", codeMeaning: "Shape"),
            value: CodedConcept(codeValue: "129734002", codingSchemeDesignator: "SCT", codeMeaning: "Irregular")
        )
        let density = CADFinding(type: .mass, probability: 0.5, location: .point2D(x: 1, y: 1, imageReference: imageRef), descriptors: [shape])
        let calcification = CADFinding(type: .calcification, probability: 0.5, location: .point2D(x: 1, y: 1, imageReference: imageRef), descriptors: [shape])
        let document = try createBasicBuilder().addFinding(density).addFinding(calcification).build()

        let impressions = impressions(document)
        XCTAssertEqual(impressions.count, 2)
        let densityShape = descendants(impressions[0].contentItems).first { $0.conceptName?.codeValue == "107644003" }
        XCTAssertNotNil(densityShape)
        XCTAssertEqual(densityShape?.relationshipType, .hasProperties)
        XCTAssertEqual(densityShape?.asCode?.conceptCode.codeValue, "129734002")
        XCTAssertNil(descendants(impressions[1].contentItems).first { $0.conceptName?.codeValue == "107644003" })
    }

    func testCertaintyAndRenderingIntent() throws {
        let imageRef = createSampleImageReference()
        let finding = CADFinding(type: .mass, probability: 0.5, location: .point2D(x: 1, y: 1, imageReference: imageRef),
                                 renderingIntent: .notForPresentation, certainty: 0.9)
        let document = try createBasicBuilder().addFinding(finding).build()
        let impression = try XCTUnwrap(impressions(document).first)
        // TID 4003 row 2 and TID 4006 row 2 carry the intent (CID 6034)
        let intents = descendants(impression.contentItems).filter { $0.conceptName?.codeValue == "111056" }
        XCTAssertEqual(intents.count, 2)
        XCTAssertTrue(intents.allSatisfy { $0.asCode?.conceptCode.codeValue == "111152" && $0.relationshipType == .hasConceptMod })
        // TID 4006 row 6: HAS PROPERTIES NUM (111012, DCM, "Certainty of Finding"), %
        let certainty = try XCTUnwrap(descendants(impression.contentItems).first { $0.conceptName?.codeValue == "111012" })
        XCTAssertEqual(certainty.relationshipType, .hasProperties)
        XCTAssertEqual(certainty.asNumeric?.value ?? 0, 90, accuracy: 0.0001)
        XCTAssertEqual(certainty.asNumeric?.measurementUnits?.codeValue, "%")
    }

    func testProbabilityOfCancerOmittedForNonLesionFindings() throws {
        // TID 4006 row 7: not for (111102, DCM, "Non-lesion"); row 8 geometry still required
        let imageRef = createSampleImageReference()
        let nonLesion = CodedConcept(codeValue: "111102", codingSchemeDesignator: "DCM", codeMeaning: "Non-lesion")
        let document = try createBasicBuilder()
            .addFinding(type: .custom(nonLesion), probability: 0.5, location: .point2D(x: 1, y: 1, imageReference: imageRef))
            .build()
        let impression = try XCTUnwrap(impressions(document).first)
        XCTAssertNil(descendants(impression.contentItems).first { $0.conceptName?.codeValue == "111047" })
        XCTAssertNotNil(descendants(impression.contentItems).first { $0.conceptName?.codeValue == "111010" })
    }

    func testImageLibraryEntryAcquisitionContext() throws {
        // TID 4020 rows 2-12 (HAS ACQ CONTEXT laterality DCID 6022, view DCID 4014, HAS CONCEPT MOD modifier DCID 4015, ...)
        let imageRef = createSampleImageReference()
        let entry = CADImageLibraryEntry(
            image: imageRef,
            laterality: CodedConcept(codeValue: "80248007", codingSchemeDesignator: "SCT", codeMeaning: "Left breast"),
            view: CodedConcept(codeValue: "399368009", codingSchemeDesignator: "SCT", codeMeaning: "medio-lateral oblique"),
            viewModifiers: [CodedConcept(codeValue: "399163009", codingSchemeDesignator: "SCT", codeMeaning: "Magnification")],
            patientOrientationRow: "A", patientOrientationColumn: "FR",
            studyDate: "20240115", studyTime: "143000", contentDate: "20240115", contentTime: "143001",
            horizontalPixelSpacingMM: 0.07, verticalPixelSpacingMM: 0.07
        )
        let document = try createBasicBuilder()
            .addImageLibraryEntry(entry)
            .addFinding(type: .mass, probability: 0.5, location: .point2D(x: 1, y: 1, imageReference: imageRef))
            .build()
        let library = try XCTUnwrap(document.rootContent.contentItems[1].asContainer)
        // Row 1: the IMAGE; rows 2-12 (">") nested in its Content Sequence; row 4 (">>")
        // nested in the row 3 Image View CODE
        XCTAssertEqual(library.contentItems.count, 1)
        assertRow(library.contentItems[0], .contains, .image, nil)
        let rows = library.contentItems[0].contentItems
        XCTAssertEqual(rows.count, 10, "\(rows)")
        assertRow(rows[0], .hasAcqContext, .code, "111027")
        assertRow(rows[1], .hasAcqContext, .code, "111031")
        XCTAssertEqual(rows[1].contentItems.count, 1)
        assertRow(rows[1].contentItems[0], .hasConceptMod, .code, "111032")
        assertRow(rows[2], .hasAcqContext, .text, "111044")
        assertRow(rows[3], .hasAcqContext, .text, "111043")
        assertRow(rows[4], .hasAcqContext, .date, "111060")
        assertRow(rows[5], .hasAcqContext, .time, "111061")
        assertRow(rows[6], .hasAcqContext, .date, "111018")
        assertRow(rows[7], .hasAcqContext, .time, "111019")
        assertRow(rows[8], .hasAcqContext, .num, "111026")
        XCTAssertEqual(rows[8].asNumeric?.measurementUnits?.codeValue, "mm")
        assertRow(rows[9], .hasAcqContext, .num, "111066")
    }

    func testFailedDetectionAndAnalysisContainers() throws {
        // TID 4015 rows 1/3 and TID 4016 rows 1/3 by CID 6042 status; TID 4018 row 1 from CID 6043
        let imageRef = createSampleImageReference()
        let failed = CADAlgorithmRun(code: FindingType.calcification.concept, images: [imageRef], succeeded: false)
        let ok = CADAlgorithmRun(code: FindingType.mass.concept, images: [imageRef])
        let analysis = CADAlgorithmRun(
            code: CodedConcept(codeValue: "133887000", codingSchemeDesignator: "SCT", codeMeaning: "Image quality analysis"),
            seriesInstanceUIDs: ["1.2.3.4.5.6"]
        )
        let builder = createBasicBuilder()
            .addDetectionPerformed(ok)
            .addDetectionPerformed(failed)
            .addAnalysisPerformed(analysis)
        XCTAssertEqual(builder.effectiveSummaryOfDetections, .partiallySucceeded)
        XCTAssertEqual(builder.effectiveSummaryOfAnalyses, .succeeded)
        XCTAssertEqual(builder.effectiveProcessingAndFindingsSummary, .notAllAlgorithmsSucceededWithoutFindings)

        let items = try builder.build().rootContent.contentItems
        let concepts = items.map { $0.conceptName?.codeValue }
        XCTAssertEqual(concepts, ["121049", "111028", "111017", "111064", "111065"])
        XCTAssertEqual(items[2].asCode?.conceptCode.codeValue, "111243")
        XCTAssertEqual(items[3].asCode?.conceptCode.codeValue, "111223")
        // TID 4000 rows 7 and 9 (">>" INFERRED FROM TID 4015 / TID 4016), nested in the
        // Summary of Detections / Summary of Analyses CODEs
        XCTAssertEqual(items[3].contentItems.map { $0.conceptName?.codeValue }, ["111063", "111025"])
        XCTAssertTrue(items[3].contentItems.allSatisfy { $0.relationshipType == .inferredFrom })
        XCTAssertEqual(items[3].contentItems[0].asContainer?.contentItems[0].asCode?.conceptCode, FindingType.mass.concept)
        XCTAssertEqual(items[3].contentItems[1].asContainer?.contentItems[0].asCode?.conceptCode, FindingType.calcification.concept)
        XCTAssertEqual(items[4].contentItems.map { $0.conceptName?.codeValue }, ["111062"])
        let analyses = try XCTUnwrap(items[4].contentItems[0].asContainer)
        assertRow(analyses.contentItems[0], .contains, .code, "111004")
        XCTAssertEqual(analyses.contentItems[0].asCode?.conceptCode.codeValue, "133887000")
        // TID 4018 row 5 (">"): HAS PROPERTIES UIDREF (112002, DCM, "Series Instance UID"),
        // nested in the row 1 Analysis Performed CODE
        let uidref = try XCTUnwrap(analyses.contentItems[0].contentItems.first { $0.valueType == .uidref })
        assertRow(uidref, .hasProperties, .uidref, "112002")
    }

    func testValueTypesAreThoseOfTableA35_5_2() throws {
        let imageRef = createSampleImageReference()
        let document = try createBasicBuilder()
            .addImageLibraryEntry(CADImageLibraryEntry(image: imageRef, studyDate: "20240101", studyTime: "120000"))
            .addFinding(type: .mass, probability: 0.85, location: .circle2D(centerX: 1, centerY: 1, radius: 1, imageReference: imageRef))
            .build()
        var valueTypes: Set<ContentItemValueType> = []
        func walk(_ items: [AnyContentItem]) {
            for item in items {
                valueTypes.insert(item.valueType)
                walk(item.contentItems)
            }
        }
        walk(document.rootContent.contentItems)
        XCTAssertFalse(valueTypes.contains(.datetime))
        XCTAssertTrue(valueTypes.isSubset(of: SRDocumentType.mammographyCADSR.allowedValueTypes))
    }
    
    func testBuildDocumentWithMultipleFindings() throws {
        let imageRef = createSampleImageReference()
        let builder = createBasicBuilder()
            .addFinding(type: .mass, probability: 0.85, location: .point2D(x: 128.5, y: 256.3, imageReference: imageRef))
            .addFinding(type: .calcification, probability: 0.72, location: .point2D(x: 64.2, y: 128.7, imageReference: imageRef))
            .addFinding(type: .architecturalDistortion, probability: 0.65,
                        location: .circle2D(centerX: 200.0, centerY: 300.0, radius: 25.0, imageReference: imageRef))
        
        let document = try builder.build()
        
        // One (111034, DCM) container per finding (TID 4001 row 3, 1-n)
        let impressions = impressions(document)
        XCTAssertEqual(impressions.count, 3)
        // One Detection Performed per distinct finding type (TID 4015 row 2, 1-n)
        XCTAssertEqual(builder.effectiveDetectionsPerformed.count, 3)
        // The shared image is listed once in the Image Library
        XCTAssertEqual(document.rootContent.contentItems[1].asContainer?.contentItems.count, 1)
    }
    
    func testBuildDocumentWithROILocation() throws {
        let imageRef = createSampleImageReference()
        let roiPoints = [10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 10.0, 20.0] // Closed polygon
        let document = try createBasicBuilder()
            .addFinding(type: .mass, probability: 0.90, location: .roi2D(points: roiPoints, imageReference: imageRef))
            .build()
        XCTAssertNotNil(document)
    }
    
    func testBuildDocumentGeneratesUIDs() throws {
        let imageRef = createSampleImageReference()
        let builder = MammographyCADSRBuilder()
            .withPatientID("12345")
            .withPatientName("Doe^Jane")
            .withCADProcessingSummary(algorithmName: "MammoCAD", algorithmVersion: "2.1.0", manufacturer: "Example Medical Systems")
            .addFinding(type: .mass, probability: 0.85, location: .point2D(x: 128.5, y: 256.3, imageReference: imageRef))
        
        let document = try builder.build()
        
        // UIDs should be auto-generated
        XCTAssertFalse(document.sopInstanceUID.isEmpty)
        XCTAssertNotNil(document.studyInstanceUID)
        XCTAssertNotNil(document.seriesInstanceUID)
    }
    
    func testBuildDocumentPreservesExplicitUIDs() throws {
        let imageRef = createSampleImageReference()
        let sopUID = "1.2.3.4.5.6.7.8.9.10"
        let studyUID = "1.2.3.4.5"
        let seriesUID = "1.2.3.4.5.6"
        
        let builder = createBasicBuilder()
            .withSOPInstanceUID(sopUID)
            .withStudyInstanceUID(studyUID)
            .withSeriesInstanceUID(seriesUID)
            .addFinding(type: .mass, probability: 0.85, location: .point2D(x: 128.5, y: 256.3, imageReference: imageRef))
        
        let document = try builder.build()
        
        XCTAssertEqual(document.sopInstanceUID, sopUID)
        XCTAssertEqual(document.studyInstanceUID, studyUID)
        XCTAssertEqual(document.seriesInstanceUID, seriesUID)
    }
    
    // MARK: - Validation Tests
    
    func testValidationFailsWithNoAlgorithmName() {
        let imageRef = createSampleImageReference()
        let builder = MammographyCADSRBuilder()
            .withPatientID("12345")
            .addFinding(type: .mass, probability: 0.85, location: .point2D(x: 128.5, y: 256.3, imageReference: imageRef))
        
        XCTAssertThrowsError(try builder.build()) { error in
            guard case MammographyCADSRBuilder.BuildError.validationError(let message) = error else {
                XCTFail("Expected validationError")
                return
            }
            XCTAssertTrue(message.contains("algorithm name"))
        }
    }
    
    func testBuildWithNoFindingsReportsAllAlgorithmsSucceededWithoutFindings() throws {
        // A report without findings is valid: TID 4001 row 1 takes (111241, DCM) from CID 6047
        // and TID 4000 rows 6/8 take (111225, DCM, "Not Attempted") so TID 4015/4016 are not required
        let builder = createBasicBuilder()
        let items = try builder.build().rootContent.contentItems
        XCTAssertEqual(items.map { $0.conceptName?.codeValue }, ["121049", "111028", "111017", "111064", "111065"])
        XCTAssertEqual(items[2].asCode?.conceptCode.codeValue, "111241")
        XCTAssertEqual(items[3].asCode?.conceptCode.codeValue, "111225")
        XCTAssertEqual(items[4].asCode?.conceptCode.codeValue, "111225")
    }

    func testValidationFailsWhenDetectionsSucceededWithoutDetectionPerformed() {
        // TID 4000 row 7: TID 4015 shall be present unless Not Attempted
        let builder = createBasicBuilder().withSummaryOfDetections(.succeeded)
        XCTAssertThrowsError(try builder.build()) { error in
            guard case MammographyCADSRBuilder.BuildError.validationError(let message) = error else {
                return XCTFail("Expected validationError")
            }
            XCTAssertTrue(message.contains("TID 4017"))
        }
    }
    
    func testValidationFailsWithInvalidProbability() {
        let imageRef = createSampleImageReference()
        let builder = createBasicBuilder()
            .addFinding(type: .mass, probability: 1.5, location: .point2D(x: 128.5, y: 256.3, imageReference: imageRef))
        
        XCTAssertThrowsError(try builder.build()) { error in
            guard case MammographyCADSRBuilder.BuildError.validationError(let message) = error else {
                XCTFail("Expected validationError")
                return
            }
            XCTAssertTrue(message.contains("probability"))
        }
    }
    
    func testValidationFailsWithNegativeProbability() {
        let imageRef = createSampleImageReference()
        let builder = createBasicBuilder()
            .addFinding(type: .mass, probability: -0.1, location: .point2D(x: 128.5, y: 256.3, imageReference: imageRef))
        
        XCTAssertThrowsError(try builder.build()) { error in
            guard case MammographyCADSRBuilder.BuildError.validationError(let message) = error else {
                XCTFail("Expected validationError")
                return
            }
            XCTAssertTrue(message.contains("probability"))
        }
    }
    
    func testValidationCanBeDisabled() throws {
        let builder = MammographyCADSRBuilder(validateOnBuild: false)
            .withPatientID("12345")
        
        // This should not throw even though it's invalid
        let document = try builder.build()
        XCTAssertNotNil(document)
    }
    
    // MARK: - Edge Case Tests
    
    func testBuildWithMinimalInformation() throws {
        let imageRef = createSampleImageReference()
        let builder = MammographyCADSRBuilder(validateOnBuild: false)
            .addFinding(type: .mass, probability: 0.5, location: .point2D(x: 100.0, y: 100.0, imageReference: imageRef))
        
        let document = try builder.build()
        XCTAssertNotNil(document)
    }
    
    func testBuildWithZeroProbability() throws {
        let imageRef = createSampleImageReference()
        let document = try createBasicBuilder()
            .addFinding(type: .mass, probability: 0.0, location: .point2D(x: 128.5, y: 256.3, imageReference: imageRef))
            .build()
        XCTAssertNotNil(document)
    }
    
    func testBuildWithMaxProbability() throws {
        let imageRef = createSampleImageReference()
        let document = try createBasicBuilder()
            .addFinding(type: .mass, probability: 1.0, location: .point2D(x: 128.5, y: 256.3, imageReference: imageRef))
            .build()
        XCTAssertNotNil(document)
    }
    
    // MARK: - Integration Tests
    
    func testCompleteWorkflow() throws {
        let imageRef = createSampleImageReference()
        
        let document = try MammographyCADSRBuilder()
            .withPatientID("MM-2024-001")
            .withPatientName("Smith^Jane^Marie")
            .withPatientBirthDate("19750615")
            .withPatientSex("F")
            .withStudyInstanceUID("1.2.840.113619.2.5.1762583153.215519.978957063.78")
            .withStudyDate("20240115")
            .withStudyTime("143000")
            .withStudyDescription("Digital Screening Mammography")
            .withAccessionNumber("MM2024001")
            .withSeriesInstanceUID("1.2.840.113619.2.5.1762583153.215519.978957063.100")
            .withSeriesNumber("501")
            .withSeriesDescription("CAD Analysis Results")
            .withInstanceNumber("1")
            .withContentDate("20240115")
            .withContentTime("144500")
            .withCADProcessingSummary(
                algorithmName: "MammoCare CAD",
                algorithmVersion: "3.2.1",
                manufacturer: "Digital Mammography Systems Inc",
                processingDateTime: "20240115144500"
            )
            .addFinding(
                type: .mass,
                probability: 0.87,
                location: .circle2D(centerX: 245.5, centerY: 389.2, radius: 18.5, imageReference: imageRef)
            )
            .addFinding(
                type: .calcification,
                probability: 0.64,
                location: .point2D(x: 156.3, y: 425.8, imageReference: imageRef)
            )
            .withCompletionFlag(.complete)
            .withVerificationFlag(.unverified)
            .build()
        
        // Verify document structure
        XCTAssertEqual(document.patientID, "MM-2024-001")
        XCTAssertEqual(document.sopClassUID, "1.2.840.10008.5.1.4.1.1.88.50")
        XCTAssertEqual(document.documentTitle?.codeMeaning, "Mammography CAD Report")
        XCTAssertEqual(document.completionFlag, .complete)
        XCTAssertEqual(document.verificationFlag, .unverified)
    }
}
