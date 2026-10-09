/// Tests for ChestCADSRBuilder
///
/// Validates the creation and validation of Chest CAD SR documents and walks the produced
/// content tree against PS3.16 2026a TID 4100, 1204, 4020, 4101, 4104, 4105, 4107, 4015,
/// 4017, 4016, 4018 and 4019 (Type M rows), with the CID 6101, 6102/6104, 6034, 6042, 6047
/// and 6137 values.

import XCTest
@testable import DICOMKit
@testable import DICOMCore

final class ChestCADSRBuilderTests: XCTestCase {

    // MARK: - Helper Methods

    private func createBasicBuilder() -> ChestCADSRBuilder {
        ChestCADSRBuilder()
            .withPatientID("12345")
            .withPatientName("Doe^John")
            .withStudyInstanceUID("1.2.3.4.5")
            .withCADProcessingSummary(
                algorithmName: "ChestCAD",
                algorithmVersion: "3.2.0",
                manufacturer: "Example Medical Systems"
            )
    }

    private func createSampleImageReference() -> ImageReference {
        ImageReference(
            sopReference: ReferencedSOP(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2", // CT Image Storage
                sopInstanceUID: "1.2.3.4.5.6.7.8.9"
            ),
            frameNumbers: nil,
            segmentNumbers: nil,
            purposeOfReference: nil
        )
    }

    private func assertRow(
        _ item: AnyContentItem, _ relationship: RelationshipType?, _ valueType: ContentItemValueType, _ concept: String?,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(item.relationshipType, relationship, "relationship of \(item)", file: file, line: line)
        XCTAssertEqual(item.valueType, valueType, "value type of \(item)", file: file, line: line)
        XCTAssertEqual(item.conceptName?.codeValue, concept, "concept name of \(item)", file: file, line: line)
    }

    /// The items and all their descendants in document order: CONTAINER contents and the
    /// Content Sequence of CODE/IMAGE/SCOORD items (PS3.3 Table C.17-6)
    private func descendants(_ items: [AnyContentItem]) -> [AnyContentItem] {
        items.flatMap { [$0] + descendants($0.contentItems) }
    }

    // MARK: - Initialization Tests

    func testBuilderInitialization() {
        let builder = ChestCADSRBuilder()
        XCTAssertTrue(builder.validateOnBuild)
        XCTAssertNil(builder.sopInstanceUID)
        XCTAssertNil(builder.patientID)
        XCTAssertEqual(builder.findings.count, 0)
        XCTAssertEqual(builder.completionFlag, .complete)
        XCTAssertEqual(builder.verificationFlag, .unverified)
        XCTAssertEqual(builder.language.codingSchemeDesignator, "RFC5646")
    }

    func testBuilderInitializationWithoutValidation() {
        let builder = ChestCADSRBuilder(validateOnBuild: false)
        XCTAssertFalse(builder.validateOnBuild)
    }

    // MARK: - Patient Information Tests

    func testWithPatientID() {
        let builder = ChestCADSRBuilder()
            .withPatientID("12345")
        XCTAssertEqual(builder.patientID, "12345")
    }

    func testWithPatientName() {
        let builder = ChestCADSRBuilder()
            .withPatientName("Doe^John")
        XCTAssertEqual(builder.patientName, "Doe^John")
    }

    func testWithPatientBirthDate() {
        let builder = ChestCADSRBuilder()
            .withPatientBirthDate("19700101")
        XCTAssertEqual(builder.patientBirthDate, "19700101")
    }

    func testWithPatientSex() {
        let builder = ChestCADSRBuilder()
            .withPatientSex("M")
        XCTAssertEqual(builder.patientSex, "M")
    }

    // MARK: - Study Information Tests

    func testWithStudyInstanceUID() {
        let builder = ChestCADSRBuilder()
            .withStudyInstanceUID("1.2.3.4.5")
        XCTAssertEqual(builder.studyInstanceUID, "1.2.3.4.5")
    }

    func testWithStudyDate() {
        let builder = ChestCADSRBuilder()
            .withStudyDate("20240101")
        XCTAssertEqual(builder.studyDate, "20240101")
    }

    func testWithStudyTime() {
        let builder = ChestCADSRBuilder()
            .withStudyTime("120000")
        XCTAssertEqual(builder.studyTime, "120000")
    }

    func testWithStudyDescription() {
        let builder = ChestCADSRBuilder()
            .withStudyDescription("Chest CT")
        XCTAssertEqual(builder.studyDescription, "Chest CT")
    }

    func testWithAccessionNumber() {
        let builder = ChestCADSRBuilder()
            .withAccessionNumber("ACC123456")
        XCTAssertEqual(builder.accessionNumber, "ACC123456")
    }

    func testWithReferringPhysicianName() {
        let builder = ChestCADSRBuilder()
            .withReferringPhysicianName("Smith^Jane")
        XCTAssertEqual(builder.referringPhysicianName, "Smith^Jane")
    }

    // MARK: - Series Information Tests

    func testWithSeriesInstanceUID() {
        let builder = ChestCADSRBuilder()
            .withSeriesInstanceUID("1.2.3.4.5.6")
        XCTAssertEqual(builder.seriesInstanceUID, "1.2.3.4.5.6")
    }

    func testWithSeriesNumber() {
        let builder = ChestCADSRBuilder()
            .withSeriesNumber("2")
        XCTAssertEqual(builder.seriesNumber, "2")
    }

    func testWithSeriesDescription() {
        let builder = ChestCADSRBuilder()
            .withSeriesDescription("CAD Analysis")
        XCTAssertEqual(builder.seriesDescription, "CAD Analysis")
    }

    // MARK: - Document Information Tests

    func testWithSOPInstanceUID() {
        let builder = ChestCADSRBuilder()
            .withSOPInstanceUID("1.2.3.4.5.6.7")
        XCTAssertEqual(builder.sopInstanceUID, "1.2.3.4.5.6.7")
    }

    func testWithInstanceNumber() {
        let builder = ChestCADSRBuilder()
            .withInstanceNumber("1")
        XCTAssertEqual(builder.instanceNumber, "1")
    }

    func testWithContentDate() {
        let builder = ChestCADSRBuilder()
            .withContentDate("20240101")
        XCTAssertEqual(builder.contentDate, "20240101")
    }

    func testWithContentTime() {
        let builder = ChestCADSRBuilder()
            .withContentTime("120000")
        XCTAssertEqual(builder.contentTime, "120000")
    }

    func testWithCompletionFlag() {
        let builder = ChestCADSRBuilder()
            .withCompletionFlag(.partial)
        XCTAssertEqual(builder.completionFlag, .partial)
    }

    func testWithVerificationFlag() {
        let builder = ChestCADSRBuilder()
            .withVerificationFlag(.verified)
        XCTAssertEqual(builder.verificationFlag, .verified)
    }

    // MARK: - CAD Processing Information Tests

    func testWithCADProcessingSummary() {
        let builder = ChestCADSRBuilder()
            .withCADProcessingSummary(
                algorithmName: "ChestCAD",
                algorithmVersion: "3.2.0",
                manufacturer: "Example Medical Systems",
                processingDateTime: "20240101120000"
            )

        XCTAssertEqual(builder.algorithmName, "ChestCAD")
        XCTAssertEqual(builder.algorithmVersion, "3.2.0")
        XCTAssertEqual(builder.manufacturer, "Example Medical Systems")
        XCTAssertEqual(builder.algorithmIdentification?.name, "ChestCAD")
    }

    // MARK: - Finding Management Tests

    func testAddFindingWithFindingStruct() {
        let imageRef = createSampleImageReference()
        let finding = ChestCADFinding(
            type: .nodule,
            probability: 0.92,
            location: .point2D(x: 256.5, y: 384.7, imageReference: imageRef)
        )

        let builder = ChestCADSRBuilder()
            .addFinding(finding)

        XCTAssertEqual(builder.findings.count, 1)
        XCTAssertEqual(builder.findings[0], finding)
    }

    func testAddFindingWithParameters() {
        let imageRef = createSampleImageReference()

        let builder = ChestCADSRBuilder()
            .addFinding(
                type: .nodule,
                probability: 0.92,
                location: .point2D(x: 256.5, y: 384.7, imageReference: imageRef)
            )

        XCTAssertEqual(builder.findings.count, 1)
        XCTAssertEqual(builder.findings[0].probability, 0.92)
    }

    func testAddMultipleFindings() {
        let imageRef = createSampleImageReference()

        let builder = ChestCADSRBuilder()
            .addFinding(type: .nodule, probability: 0.92, location: .point2D(x: 256.5, y: 384.7, imageReference: imageRef))
            .addFinding(type: .mass, probability: 0.75, location: .point2D(x: 128.3, y: 192.1, imageReference: imageRef))

        XCTAssertEqual(builder.findings.count, 2)
    }

    func testClearFindings() {
        let imageRef = createSampleImageReference()

        let builder = ChestCADSRBuilder()
            .addFinding(type: .nodule, probability: 0.92, location: .point2D(x: 256.5, y: 384.7, imageReference: imageRef))
            .clearFindings()

        XCTAssertEqual(builder.findings.count, 0)
    }

    // MARK: - Finding Type Tests (TID 4104 row 1 CID 6101, row 2 CID 6102/6104)

    func testNoduleFindingType() {
        // Row 1: (112033, DCM, "Abnormal opacity") (CID 6101); row 2: (27925004, SCT, "Nodule") (CID 6104)
        XCTAssertEqual(ChestFindingType.nodule.singleImageFinding.codeValue, "112033")
        XCTAssertEqual(ChestFindingType.nodule.singleImageFinding.codingSchemeDesignator, "DCM")
        XCTAssertEqual(ChestFindingType.nodule.singleImageFinding.codeMeaning, "Abnormal opacity")
        let concept = ChestFindingType.nodule.concept
        XCTAssertEqual(concept.codeValue, "27925004")
        XCTAssertEqual(concept.codingSchemeDesignator, "SCT")
        XCTAssertEqual(concept.codeMeaning, "Nodule")
        XCTAssertEqual(ChestFindingType.nodule.modifier, concept)
    }

    func testMassFindingType() {
        let concept = ChestFindingType.mass.concept
        XCTAssertEqual(concept.codeValue, "4147007")
        XCTAssertEqual(concept.codingSchemeDesignator, "SCT")
        XCTAssertEqual(concept.codeMeaning, "Mass")
        XCTAssertEqual(ChestFindingType.mass.singleImageFinding.codeValue, "112033")
    }

    func testTreeInBudFindingType() {
        let concept = ChestFindingType.treeInBud.concept
        XCTAssertEqual(concept.codeValue, "112127")
        XCTAssertEqual(concept.codingSchemeDesignator, "DCM")
        XCTAssertEqual(concept.codeMeaning, "Tree-in-bud sign")
        XCTAssertEqual(ChestFindingType.treeInBud.singleImageFinding.codeValue, "112033")
    }

    func testCustomFindingType() {
        // A custom concept is the row 1 value itself, without modifier
        let customConcept = CodedConcept(codeValue: "112062", codingSchemeDesignator: "DCM", codeMeaning: "Abnormal lucency")
        let findingType = ChestFindingType.custom(customConcept)
        XCTAssertEqual(findingType.concept, customConcept)
        XCTAssertEqual(findingType.singleImageFinding, customConcept)
        XCTAssertNil(findingType.modifier)
    }

    func testModifiedFindingType() {
        let finding = CodedConcept(codeValue: "112033", codingSchemeDesignator: "DCM", codeMeaning: "Abnormal opacity")
        let modifier = CodedConcept(codeValue: "112120", codingSchemeDesignator: "DCM", codeMeaning: "Ground glass opacity")
        let type = ChestFindingType.modified(finding: finding, modifier: modifier)
        XCTAssertEqual(type.singleImageFinding, finding)
        XCTAssertEqual(type.modifier, modifier)
        XCTAssertEqual(type.concept, modifier)
    }

    // MARK: - Finding Location Tests

    func testPoint2DLocation() {
        let imageRef = createSampleImageReference()
        let location = ChestFindingLocation.point2D(x: 256.5, y: 384.7, imageReference: imageRef)

        if case .point2D(let x, let y, let ref) = location {
            XCTAssertEqual(x, 256.5)
            XCTAssertEqual(y, 384.7)
            XCTAssertEqual(ref.sopReference.sopInstanceUID, imageRef.sopReference.sopInstanceUID)
        } else {
            XCTFail("Expected point2D location")
        }
    }

    func testROI2DLocation() {
        let imageRef = createSampleImageReference()
        let points = [100.0, 100.0, 200.0, 100.0, 200.0, 200.0, 100.0, 200.0]
        let location = ChestFindingLocation.roi2D(points: points, imageReference: imageRef)

        if case .roi2D(let pts, let ref) = location {
            XCTAssertEqual(pts, points)
            XCTAssertEqual(ref.sopReference.sopInstanceUID, imageRef.sopReference.sopInstanceUID)
        } else {
            XCTFail("Expected roi2D location")
        }
    }

    func testCircle2DLocation() {
        let imageRef = createSampleImageReference()
        let location = ChestFindingLocation.circle2D(centerX: 256.0, centerY: 384.0, radius: 50.0, imageReference: imageRef)

        if case .circle2D(let cx, let cy, let r, let ref) = location {
            XCTAssertEqual(cx, 256.0)
            XCTAssertEqual(cy, 384.0)
            XCTAssertEqual(r, 50.0)
            XCTAssertEqual(ref.sopReference.sopInstanceUID, imageRef.sopReference.sopInstanceUID)
        } else {
            XCTFail("Expected circle2D location")
        }
    }

    // MARK: - Build Tests

    func testBuildBasicDocument() throws {
        let imageRef = createSampleImageReference()

        let builder = createBasicBuilder()
            .addFinding(type: .nodule, probability: 0.92, location: .point2D(x: 256.5, y: 384.7, imageReference: imageRef))

        let document = try builder.build()

        XCTAssertEqual(document.sopClassUID, "1.2.840.10008.5.1.4.1.1.88.65")
        XCTAssertEqual(document.documentType, .chestCADSR)
        XCTAssertEqual(document.patientID, "12345")
        XCTAssertEqual(document.patientName, "Doe^John")
        XCTAssertEqual(document.studyInstanceUID, "1.2.3.4.5")
        XCTAssertNotNil(document.sopInstanceUID)
        XCTAssertNotNil(document.seriesInstanceUID)
        // TID 4100 row 1
        XCTAssertEqual(document.documentTitle?.codeValue, "112000")
        XCTAssertEqual(document.documentTitle?.codeMeaning, "Chest CAD Report")
    }

    // MARK: - Template walk (TID 4100 and the templates it includes)

    func testContentTreeFollowsTID4100() throws {
        let imageRef = createSampleImageReference()
        let document = try createBasicBuilder()
            .addFinding(type: .nodule, probability: 0.92, location: .point2D(x: 256.5, y: 384.7, imageReference: imageRef))
            .build()

        let root = document.rootContent
        // TID 4100 row 1: CONTAINER EV (112000, DCM, "Chest CAD Report"), root node
        XCTAssertNil(root.relationshipType)
        XCTAssertEqual(root.conceptName?.codeValue, "112000")
        XCTAssertEqual(root.templateIdentifier, "4100")

        let items = root.contentItems
        // Root rows 2, 3, 5, 6, 8; each template's ">" rows are nested in their parent item
        XCTAssertEqual(items.map { $0.conceptName?.codeValue }, ["121049", "111028", "111017", "111064", "111065"])

        // Row 2: HAS CONCEPT MOD INCLUDE TID 1204
        assertRow(items[0], .hasConceptMod, .code, "121049")
        // Row 3: CONTAINS CONTAINER (111028, DCM, "Image Library"); row 4: TID 4020 IMAGE
        assertRow(items[1], .contains, .container, "111028")
        assertRow(try XCTUnwrap(items[1].asContainer?.contentItems.first), .contains, .image, nil)
        // Row 5: CONTAINS INCLUDE TID 4101 -> row 1 CODE (111017, DCM), DCID 6047
        assertRow(items[2], .contains, .code, "111017")
        XCTAssertEqual(items[2].asCode?.conceptCode.codeValue, "111242")

        // TID 4101 row 3 (">"): INFERRED FROM INCLUDE TID 4104 -> row 1 CODE (111059, DCM),
        // DCID 6101, nested in the Content Sequence of the 111017 CODE (PS3.3 Table C.17-6)
        XCTAssertEqual(items[2].contentItems.count, 1)
        let finding = items[2].contentItems[0]
        assertRow(finding, .inferredFrom, .code, "111059")
        XCTAssertEqual(finding.asCode?.conceptCode.codeValue, "112033")
        // TID 4104 rows 2, 6, 11, 12, 14 nested in the 111059 CODE; TID 4107 row 2 in the SCOORD
        XCTAssertEqual(finding.contentItems.map { $0.conceptName?.codeValue }, [
            "112024", "111056", "111001", "111003", "122405", "111012", "111010"
        ])
        XCTAssertEqual(finding.contentItems[6].contentItems.map { $0.valueType }, [.image])

        // Row 6: CONTAINS CODE (111064, DCM, "Summary of Detections"); row 7 (">>"): TID 4015
        // CONTAINER nested in it; row 8: CODE (111065, DCM)
        assertRow(items[3], .contains, .code, "111064")
        XCTAssertEqual(items[3].contentItems.count, 1)
        assertRow(items[3].contentItems[0], .inferredFrom, .container, "111063")
        assertRow(items[4], .contains, .code, "111065")
        XCTAssertTrue(items[4].contentItems.isEmpty)
    }

    func testSingleImageFindingRowsFollowTID4104() throws {
        let imageRef = createSampleImageReference()
        let document = try createBasicBuilder()
            .addFinding(type: .nodule, probability: 0.92, location: .circle2D(centerX: 10, centerY: 20, radius: 5, imageReference: imageRef))
            .build()
        let items = document.rootContent.contentItems
        let summary = try XCTUnwrap(items.first { $0.conceptName?.codeValue == "111017" })
        let finding = try XCTUnwrap(summary.contentItems.first { $0.conceptName?.codeValue == "111059" })
        // TID 4104 rows 2-18 (">") are the 111059 CODE's Content Sequence
        let rows = finding.contentItems
        XCTAssertEqual(rows.count, 8, "\(rows)")
        // Row 2: HAS CONCEPT MOD CODE (112024, DCM, "Single Image Finding Modifier"), DCID 6102
        assertRow(rows[0], .hasConceptMod, .code, "112024")
        XCTAssertEqual(rows[0].asCode?.conceptCode.codeValue, "27925004")
        // Row 6: HAS CONCEPT MOD CODE (111056, DCM, "Rendering Intent"), DCID 6034
        assertRow(rows[1], .hasConceptMod, .code, "111056")
        XCTAssertEqual(rows[1].asCode?.conceptCode.codeValue, "111150")
        // Row 11: HAS OBS CONTEXT INCLUDE TID 4019
        assertRow(rows[2], .hasObsContext, .text, "111001")
        assertRow(rows[3], .hasObsContext, .text, "111003")
        assertRow(rows[4], .hasObsContext, .text, "122405")
        // Row 12: HAS PROPERTIES NUM (111012, DCM, "Certainty of Finding"), UNITS (%, UCUM)
        assertRow(rows[5], .hasProperties, .num, "111012")
        XCTAssertEqual(rows[5].asNumeric?.value ?? 0, 92, accuracy: 0.0001)
        XCTAssertEqual(rows[5].asNumeric?.measurementUnits?.codeValue, "%")
        // Row 14: HAS PROPERTIES INCLUDE TID 4107 -> row 1 SCOORD Center POINT with row 2 (">")
        // SELECTED FROM IMAGE nested in it; row 4 SCOORD Outline with row 5 (">") nested
        assertRow(rows[6], .hasProperties, .scoord, "111010")
        XCTAssertEqual(rows[6].asSpatialCoordinates?.graphicType, .point)
        XCTAssertEqual(rows[6].contentItems.count, 1)
        assertRow(rows[6].contentItems[0], .selectedFrom, .image, nil)
        assertRow(rows[7], .hasProperties, .scoord, "111041")
        XCTAssertEqual(rows[7].asSpatialCoordinates?.graphicType, .circle)
        XCTAssertEqual(rows[7].asSpatialCoordinates?.graphicData, [10, 20, 15, 20])
        XCTAssertEqual(rows[7].contentItems.count, 1)
        assertRow(rows[7].contentItems[0], .selectedFrom, .image, nil)

        // TID 4100 row 6: CODE (111064, DCM) Succeeded; row 7 (">>"): TID 4015 -> CONTAINER (111063, DCM) with TID 4017
        let end = try XCTUnwrap(items.firstIndex { $0.conceptName?.codeValue == "111064" })
        XCTAssertEqual(items[end].asCode?.conceptCode.codeValue, "111222")
        let detectionsItem = try XCTUnwrap(items[end].contentItems.first)
        assertRow(detectionsItem, .inferredFrom, .container, "111063")
        let detections = try XCTUnwrap(detectionsItem.asContainer)
        // TID 4017 row 1: $DetectionCode from DCID 6101/6102: the modifier (Nodule); row 2 (">") nested
        assertRow(detections.contentItems[0], .contains, .code, "111022")
        XCTAssertEqual(detections.contentItems[0].asCode?.conceptCode.codeValue, "27925004")
        assertRow(try XCTUnwrap(detections.contentItems[0].contentItems.first), .hasProperties, .text, "111001")
        // TID 4100 row 8: CODE (111065, DCM) Not Attempted
        XCTAssertEqual(items[end + 1].asCode?.conceptCode.codeValue, "111225")
    }

    func testDescriptorsFollowTID4105() throws {
        let imageRef = createSampleImageReference()
        let size = CADDescriptor(
            conceptName: CodedConcept(codeValue: "112025", codingSchemeDesignator: "DCM", codeMeaning: "Size Descriptor"),
            value: CodedConcept(codeValue: "255507004", codingSchemeDesignator: "SCT", codeMeaning: "Small")
        )
        let location = CADDescriptor(
            conceptName: CodedConcept(codeValue: "112013", codingSchemeDesignator: "DCM", codeMeaning: "Location in Chest"),
            value: CodedConcept(codeValue: "39607008", codingSchemeDesignator: "SCT", codeMeaning: "Lung")
        )
        let notInTemplate = CADDescriptor(
            conceptName: CodedConcept(codeValue: "121071", codingSchemeDesignator: "DCM", codeMeaning: "Finding"),
            value: CodedConcept(codeValue: "X", codingSchemeDesignator: "99TEST", codeMeaning: "X")
        )
        let finding = ChestCADFinding(type: .nodule, probability: 0.5, location: .point2D(x: 1, y: 1, imageReference: imageRef),
                                      renderingIntent: .presentationOptional, descriptors: [size, location, notInTemplate])
        let items = descendants(try createBasicBuilder().addFinding(finding).build().rootContent.contentItems)
        let descriptors = items.filter { ["112025", "112013", "121071"].contains($0.conceptName?.codeValue ?? "") }
        XCTAssertEqual(descriptors.map { $0.conceptName?.codeValue }, ["112025", "112013"])
        XCTAssertTrue(descriptors.allSatisfy { $0.relationshipType == .hasProperties && $0.valueType == .code })
        XCTAssertEqual(items.first { $0.conceptName?.codeValue == "111056" }?.asCode?.conceptCode.codeValue, "111151")
    }

    func testImageQualityFindingHasNoGeometry() throws {
        // TID 4104 row 14: TID 4107 shall be present unless the value is (111101, DCM, "Image quality")
        let imageRef = createSampleImageReference()
        let quality = CodedConcept(codeValue: "111101", codingSchemeDesignator: "DCM", codeMeaning: "Image quality")
        let items = descendants(try createBasicBuilder()
            .addFinding(type: .custom(quality), probability: 0.5, location: .point2D(x: 1, y: 1, imageReference: imageRef))
            .build().rootContent.contentItems)
        XCTAssertNotNil(items.first { $0.conceptName?.codeValue == "111059" })
        XCTAssertNil(items.first { $0.conceptName?.codeValue == "111010" })
    }

    func testImageLibraryOmittedWithoutImages() throws {
        // TID 4100 row 3 is Type U: no Image Library when nothing references an image
        let items = try createBasicBuilder().build().rootContent.contentItems
        XCTAssertEqual(items.map { $0.conceptName?.codeValue }, ["121049", "111017", "111064", "111065"])
        XCTAssertEqual(items[1].asCode?.conceptCode.codeValue, "111241")
    }

    func testAnalysisPerformedFromCID6137() throws {
        let analysis = CADAlgorithmRun(
            code: CodedConcept(codeValue: "133886009", codingSchemeDesignator: "SCT", codeMeaning: "Temporal correlation")
        )
        let builder = createBasicBuilder().addAnalysisPerformed(analysis)
        XCTAssertEqual(builder.effectiveSummaryOfAnalyses, .succeeded)
        let items = try builder.build().rootContent.contentItems
        XCTAssertEqual(items.map { $0.conceptName?.codeValue }, ["121049", "111017", "111064", "111065"])
        // TID 4100 row 9 (">>"): INFERRED FROM TID 4016, nested in the Summary of Analyses CODE
        assertRow(try XCTUnwrap(items[3].contentItems.first), .inferredFrom, .container, "111062")
        let analyses = try XCTUnwrap(items[3].contentItems.first?.asContainer)
        assertRow(analyses.contentItems[0], .contains, .code, "111004")
        XCTAssertEqual(analyses.contentItems[0].asCode?.conceptCode.codeValue, "133886009")
    }

    func testValueTypesAreThoseOfTableA35_6_2() throws {
        let imageRef = createSampleImageReference()
        let document = try createBasicBuilder()
            .addImageLibraryEntry(CADImageLibraryEntry(
                image: imageRef,
                laterality: CodedConcept(codeValue: "51440002", codingSchemeDesignator: "SCT", codeMeaning: "Bilateral"),
                view: CodedConcept(codeValue: "272479007", codingSchemeDesignator: "SCT", codeMeaning: "postero-anterior"),
                studyDate: "20240101", studyTime: "120000"
            ))
            .addFinding(type: .nodule, probability: 0.92, location: .roi2D(points: [0, 0, 1, 0, 1, 1], imageReference: imageRef))
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
        XCTAssertTrue(valueTypes.isSubset(of: SRDocumentType.chestCADSR.allowedValueTypes))
    }

    func testBuildGeneratesUIDsWhenNotSet() throws {
        let imageRef = createSampleImageReference()

        let builder = ChestCADSRBuilder()
            .withPatientID("12345")
            .withCADProcessingSummary(algorithmName: "ChestCAD", algorithmVersion: "3.2.0", manufacturer: "Example Medical Systems")
            .addFinding(type: .nodule, probability: 0.92, location: .point2D(x: 256.5, y: 384.7, imageReference: imageRef))

        let document = try builder.build()

        XCTAssertFalse(document.sopInstanceUID.isEmpty)
        XCTAssertFalse(document.seriesInstanceUID?.isEmpty ?? true)
    }

    func testBuildWithAllPropertiesSet() throws {
        let imageRef = createSampleImageReference()

        let builder = ChestCADSRBuilder()
            .withSOPInstanceUID("1.2.3.4.5.6.7")
            .withStudyInstanceUID("1.2.3.4.5")
            .withSeriesInstanceUID("1.2.3.4.5.6")
            .withInstanceNumber("1")
            .withPatientID("12345")
            .withPatientName("Doe^John")
            .withPatientBirthDate("19700101")
            .withPatientSex("M")
            .withStudyDate("20240101")
            .withStudyTime("120000")
            .withStudyDescription("Chest CT")
            .withAccessionNumber("ACC123456")
            .withReferringPhysicianName("Smith^Jane")
            .withSeriesNumber("2")
            .withSeriesDescription("CAD Analysis")
            .withContentDate("20240101")
            .withContentTime("120000")
            .withCompletionFlag(.complete)
            .withVerificationFlag(.verified)
            .withCADProcessingSummary(
                algorithmName: "ChestCAD",
                algorithmVersion: "3.2.0",
                manufacturer: "Example Medical Systems",
                processingDateTime: "20240101120000"
            )
            .addFinding(type: .nodule, probability: 0.92, location: .point2D(x: 256.5, y: 384.7, imageReference: imageRef))

        let document = try builder.build()

        XCTAssertEqual(document.sopInstanceUID, "1.2.3.4.5.6.7")
        XCTAssertEqual(document.studyInstanceUID, "1.2.3.4.5")
        XCTAssertEqual(document.seriesInstanceUID, "1.2.3.4.5.6")
        XCTAssertEqual(document.instanceNumber, "1")
        XCTAssertEqual(document.patientID, "12345")
        XCTAssertEqual(document.patientName, "Doe^John")
        XCTAssertEqual(document.studyDate, "20240101")
        XCTAssertEqual(document.studyTime, "120000")
        XCTAssertEqual(document.accessionNumber, "ACC123456")
        XCTAssertEqual(document.seriesNumber, "2")
        XCTAssertEqual(document.contentDate, "20240101")
        XCTAssertEqual(document.contentTime, "120000")
        XCTAssertEqual(document.completionFlag, .complete)
        XCTAssertEqual(document.verificationFlag, .verified)
    }

    func testBuildWithMultipleFindings() throws {
        let imageRef = createSampleImageReference()

        let document = try createBasicBuilder()
            .addFinding(type: .nodule, probability: 0.92, location: .point2D(x: 256.5, y: 384.7, imageReference: imageRef))
            .addFinding(type: .mass, probability: 0.75,
                        location: .roi2D(points: [100.0, 100.0, 200.0, 100.0, 200.0, 200.0, 100.0, 200.0], imageReference: imageRef))
            .addFinding(type: .treeInBud, probability: 0.88,
                        location: .circle2D(centerX: 128.0, centerY: 192.0, radius: 25.0, imageReference: imageRef))
            .build()

        // TID 4101 row 3: one (111059, DCM) CODE per finding, each INFERRED FROM the summary
        // CODE and nested in its Content Sequence
        let summary = try XCTUnwrap(document.rootContent.contentItems.first { $0.conceptName?.codeValue == "111017" })
        let findings = summary.contentItems.filter { $0.conceptName?.codeValue == "111059" }
        XCTAssertEqual(findings.count, 3)
        XCTAssertTrue(findings.allSatisfy { $0.relationshipType == .inferredFrom })
        XCTAssertEqual(findings.compactMap { $0.asCode?.conceptCode.codeValue }, ["112033", "112033", "112033"])
    }

    // MARK: - Validation Tests

    func testValidationFailsWithoutAlgorithmName() {
        let imageRef = createSampleImageReference()

        let builder = ChestCADSRBuilder()
            .withPatientID("12345")
            .addFinding(type: .nodule, probability: 0.92, location: .point2D(x: 256.5, y: 384.7, imageReference: imageRef))

        XCTAssertThrowsError(try builder.build()) { error in
            if case ChestCADSRBuilder.BuildError.validationError(let message) = error {
                XCTAssertTrue(message.contains("algorithm name"))
            } else {
                XCTFail("Expected validation error")
            }
        }
    }

    func testValidationFailsWhenAnalysesSucceededWithoutAnalysisPerformed() {
        // TID 4100 row 9: TID 4016 shall be present unless Not Attempted
        let builder = createBasicBuilder().withSummaryOfAnalyses(.succeeded)
        XCTAssertThrowsError(try builder.build()) { error in
            if case ChestCADSRBuilder.BuildError.validationError(let message) = error {
                XCTAssertTrue(message.contains("TID 4018"))
            } else {
                XCTFail("Expected validation error")
            }
        }
    }

    func testValidationFailsWithInvalidProbabilityTooLow() {
        let imageRef = createSampleImageReference()

        let builder = createBasicBuilder()
            .addFinding(type: .nodule, probability: -0.1, location: .point2D(x: 256.5, y: 384.7, imageReference: imageRef))

        XCTAssertThrowsError(try builder.build()) { error in
            if case ChestCADSRBuilder.BuildError.validationError(let message) = error {
                XCTAssertTrue(message.contains("probability"))
                XCTAssertTrue(message.contains("0.0"))
                XCTAssertTrue(message.contains("1.0"))
            } else {
                XCTFail("Expected validation error")
            }
        }
    }

    func testValidationFailsWithInvalidProbabilityTooHigh() {
        let imageRef = createSampleImageReference()

        let builder = createBasicBuilder()
            .addFinding(type: .nodule, probability: 1.5, location: .point2D(x: 256.5, y: 384.7, imageReference: imageRef))

        XCTAssertThrowsError(try builder.build()) { error in
            if case ChestCADSRBuilder.BuildError.validationError(let message) = error {
                XCTAssertTrue(message.contains("probability"))
                XCTAssertTrue(message.contains("0.0"))
                XCTAssertTrue(message.contains("1.0"))
            } else {
                XCTFail("Expected validation error")
            }
        }
    }

    func testBuildWithoutValidation() throws {
        let builder = ChestCADSRBuilder(validateOnBuild: false)
            .withPatientID("12345")

        // Should not throw even without algorithm name or findings
        let document = try builder.build()
        XCTAssertNotNil(document)
    }

    // MARK: - Edge Case Tests

    func testBuildWithMinimalInformation() throws {
        let imageRef = createSampleImageReference()

        let builder = ChestCADSRBuilder()
            .withCADProcessingSummary(algorithmName: "ChestCAD", algorithmVersion: "1.0", manufacturer: "Test")
            .addFinding(type: .nodule, probability: 0.5, location: .point2D(x: 0, y: 0, imageReference: imageRef))

        let document = try builder.build()
        XCTAssertNotNil(document)
    }

    func testBuildWithProbabilityAtBoundaries() throws {
        let imageRef = createSampleImageReference()

        let document1 = try createBasicBuilder()
            .addFinding(type: .nodule, probability: 0.0, location: .point2D(x: 256.5, y: 384.7, imageReference: imageRef))
            .build()
        XCTAssertNotNil(document1)

        let document2 = try createBasicBuilder()
            .addFinding(type: .nodule, probability: 1.0, location: .point2D(x: 256.5, y: 384.7, imageReference: imageRef))
            .build()
        XCTAssertNotNil(document2)
    }

    func testBuildWithAllLocationTypes() throws {
        let imageRef = createSampleImageReference()

        let document = try createBasicBuilder()
            .addFinding(type: .nodule, probability: 0.9, location: .point2D(x: 256.5, y: 384.7, imageReference: imageRef))
            .addFinding(type: .mass, probability: 0.8,
                        location: .roi2D(points: [100.0, 100.0, 200.0, 100.0, 200.0, 200.0, 100.0, 200.0], imageReference: imageRef))
            .addFinding(type: .treeInBud, probability: 0.7,
                        location: .circle2D(centerX: 128.0, centerY: 192.0, radius: 25.0, imageReference: imageRef))
            .build()
        XCTAssertNotNil(document)
    }
}
