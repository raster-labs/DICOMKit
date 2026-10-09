//
// AIOutputObjectsTests.swift
// dicom-ai
//
// The objects `dicom-ai` writes besides the Segmentation (SegmentationOutputTests), checked
// against DICOM 2026a:
// - classify/detect --format dicom-sr: a PS3.16 TID 1500 Measurement Report (Comprehensive SR,
//   PS3.3 Table A.35.3-1), built by MeasurementReportBuilder, validated row by row by
//   TemplateValidator against TID 1500; root title (126000, DCM, "Imaging Measurement Report")
//   (CID 7021); TID 4019 rows 1-2 (111001 / 111003, DCM) under Imaging Measurements (TID 1500
//   row 6b); NUM (111012, DCM, "Certainty of Finding") in (%, UCUM, "Percent"), Value 0-100
//   (the units TID 4006 row 6 / TID 4104 row 12 / TID 4127 row 8 give it); Content Template
//   Sequence DCMR 1500 (PS3.3 Table C.18.8-1); written as a PS3.10 file.
// - enhance: a PS3.10 file of the source SOP Class, Image Type DERIVED\SECONDARY
//   (PS3.3 C.7.6.1.1.2), Source Image Sequence with (121322, DCM, "Source image for image
//   processing operation") (CID 7202), Derivation Description (Table C.12-10).
// - the GSPS generator: GrayscalePresentationStateBuilder output (PS3.3 A.33.1).
//

import XCTest
import DICOMKit
import DICOMCore
@testable import dicom_ai

final class AIOutputObjectsTests: XCTestCase {

    private func source(frames: Int? = nil) -> DataSet {
        var dataSet = DataSet()
        dataSet.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        dataSet.setString("1.2.3.4.5", for: .sopInstanceUID, vr: .UI)
        dataSet.setString("1.2.3", for: .studyInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4", for: .seriesInstanceUID, vr: .UI)
        dataSet.setString("Doe^Jane", for: .patientName, vr: .PN)
        dataSet.setString("P001", for: .patientID, vr: .LO)
        dataSet.setString("19700101", for: .patientBirthDate, vr: .DA)
        dataSet.setString("F", for: .patientSex, vr: .CS)
        dataSet.setString("ORIGINAL\\PRIMARY\\AXIAL", for: .imageType, vr: .CS)
        dataSet.setString("120", for: .kvp, vr: .DS)
        dataSet.setUInt16(4, for: .rows)
        dataSet.setUInt16(4, for: .columns)
        if let frames { dataSet.setString(String(frames), for: .numberOfFrames, vr: .IS) }
        return dataSet
    }

    private func dcm(_ value: String, _ meaning: String) -> CodedConcept {
        CodedConcept(codeValue: value, codingSchemeDesignator: "DCM", codeMeaning: meaning)
    }

    /// Writes the SR as a PS3.10 file, reads it back, and parses the content tree
    private func roundTrip(_ dataSet: DataSet) throws -> (DICOMFile, SRDocument) {
        let file = try DICOMFile.read(from: try AIDICOMOutputGenerator.partTenFile(dataSet))
        XCTAssertEqual(file.fileMetaInformation.string(for: .mediaStorageSOPClassUID), "1.2.840.10008.5.1.4.1.1.88.33",
                       "Comprehensive SR Storage, PS3.6 Table A-1")
        return (file, try SRDocumentParser().parse(dataSet: file.dataSet))
    }

    private func assertConformsToTID1500(_ document: SRDocument, file: StaticString = #filePath, line: UInt = #line) {
        let result = TemplateValidator(mode: .strict).validate(AnyContentItem(document.rootContent), against: .measurementReport)
        XCTAssertTrue(result.errors.isEmpty, result.violations.map(\.description).joined(separator: "\n"), file: file, line: line)
    }

    private func imagingMeasurements(_ document: SRDocument) throws -> ContainerContentItem {
        try XCTUnwrap(document.rootContent.contentItems.first { $0.conceptName == dcm("126010", "Imaging Measurements") }?.asContainer)
    }

    func testClassificationSRIsTID1500() throws {
        let dataSet = try AIDICOMOutputGenerator.createSRFromClassification(
            predictions: [Prediction(label: "pneumonia", confidence: 0.875), Prediction(label: "normal", confidence: 0.1)],
            sourceDataSet: source(), modelName: "chest.mlmodel", algorithmVersion: "2.1")
        let (file, document) = try roundTrip(dataSet)
        assertConformsToTID1500(document)

        XCTAssertEqual(document.documentTitle, dcm("126000", "Imaging Measurement Report"))
        let template = try XCTUnwrap(file.dataSet.sequence(for: .contentTemplateSequence)?.first)
        XCTAssertEqual(template.string(for: .templateIdentifier), "1500")
        XCTAssertEqual(template.string(for: .mappingResource), "DCMR")

        // TID 1500 row 6b → TID 4019 rows 1, 2
        let measurements = try imagingMeasurements(document)
        let algorithm = measurements.contentItems.prefix(2)
        XCTAssertEqual(algorithm.map(\.conceptName), [dcm("111001", "Algorithm Name"), dcm("111003", "Algorithm Version")])
        XCTAssertEqual(algorithm.map(\.relationshipType), [.hasConceptMod, .hasConceptMod])
        XCTAssertEqual(algorithm.compactMap { $0.asText?.textValue }, ["chest.mlmodel", "2.1"])

        // TID 1501, one group per prediction
        let groups = measurements.contentItems.compactMap(\.asContainer)
        XCTAssertEqual(groups.count, 2)
        let first = try XCTUnwrap(groups.first)
        XCTAssertEqual(first.conceptName, dcm("125007", "Measurement Group"))
        XCTAssertTrue(first.contentItems.contains { $0.conceptName == dcm("112039", "Tracking Identifier") })
        XCTAssertTrue(first.contentItems.contains { $0.conceptName == dcm("112040", "Tracking Unique Identifier") })
        let num = try XCTUnwrap(first.contentItems.first { $0.valueType == .num }?.asNumeric)
        XCTAssertEqual(num.conceptName, dcm("111012", "Certainty of Finding"))
        XCTAssertEqual(num.measurementUnits, CodedConcept(codeValue: "%", codingSchemeDesignator: "UCUM", codeMeaning: "Percent"))
        XCTAssertEqual(try XCTUnwrap(num.numericValues.first), 87.5, accuracy: 1e-9, "Value 0 - 100")
        let inferred = try XCTUnwrap(num.contentItems.first?.asImage)
        XCTAssertEqual(inferred.relationshipType, .inferredFrom)
        XCTAssertEqual(inferred.imageReference.sopReference.sopInstanceUID, "1.2.3.4.5")
        let label = try XCTUnwrap(first.contentItems.first { $0.valueType == .text && $0.conceptName == dcm("121071", "Finding") }?.asText)
        XCTAssertEqual(label.textValue, "pneumonia")

        // Type 2 Patient / General Study / General Equipment attributes (Table A.35.3-1)
        XCTAssertEqual(file.dataSet.string(for: .patientBirthDate), "19700101")
        XCTAssertEqual(file.dataSet.string(for: .patientSex), "F")
        for tag in [Tag.referringPhysicianName, .studyID, .accessionNumber, .manufacturer] {
            XCTAssertNotNil(file.dataSet[tag], "\(tag) is Type 2")
        }
        XCTAssertEqual(file.dataSet.string(for: .studyInstanceUID), "1.2.3")
    }

    func testDetectionSRCarriesBoundingBoxSCOORD() throws {
        let dataSet = try AIDICOMOutputGenerator.createSRFromDetections(
            detections: [Detection(label: "nodule", confidence: 0.9, bbox: BoundingBox(x: 10, y: 20, width: 30, height: 40))],
            sourceDataSet: source(frames: 3), modelName: "lesion.mlmodel", frameIndex: 1)
        let (_, document) = try roundTrip(dataSet)
        assertConformsToTID1500(document)
        let group = try XCTUnwrap(try imagingMeasurements(document).contentItems.compactMap(\.asContainer).first)
        let num = try XCTUnwrap(group.contentItems.first { $0.valueType == .num }?.asNumeric)
        let scoord = try XCTUnwrap(num.contentItems.first?.asSpatialCoordinates)
        XCTAssertEqual(scoord.relationshipType, .inferredFrom)
        XCTAssertEqual(scoord.graphicType, .polyline)
        XCTAssertEqual(scoord.graphicData, [10, 20, 40, 20, 40, 60, 10, 60, 10, 20], "closed: first point = last point (C.18.6.1.2)")
        let selected = try XCTUnwrap(scoord.contentItems.first?.asImage)
        XCTAssertEqual(selected.relationshipType, .selectedFrom)
        XCTAssertEqual(selected.imageReference.frameNumbers, [2], "Referenced Frame Number is 1-based")
        let measurements = try imagingMeasurements(document)
        XCTAssertEqual(measurements.contentItems.compactMap { $0.asText?.textValue }.prefix(2), ["lesion.mlmodel", "unknown"],
                       "TID 4019 row 2 is M: written as 'unknown' when no version is known")
    }

    /// TID 1500 row 6 is MC "IF Row 10 and Row 12 are absent": with nothing above the
    /// threshold the container still carries the algorithm identification
    func testEmptyResultStillHasImagingMeasurements() throws {
        let dataSet = try AIDICOMOutputGenerator.createSRFromClassification(
            predictions: [], sourceDataSet: source(), modelName: "m.mlmodel", algorithmVersion: "1")
        let (_, document) = try roundTrip(dataSet)
        assertConformsToTID1500(document)
        XCTAssertEqual(try imagingMeasurements(document).contentItems.count, 2)
    }

    func testAlgorithmVersionOption() throws {
        let explicit = try CommonOptions.parse(["in.dcm", "--model", "m.mlmodel", "--algorithm-version", "3.0.1"])
        XCTAssertEqual(explicit.resolvedAlgorithmVersion(modelVersion: "9"), "3.0.1")
        let none = try CommonOptions.parse(["in.dcm", "--model", "m.mlmodel"])
        XCTAssertEqual(none.resolvedAlgorithmVersion(modelVersion: "9"), "9")
        XCTAssertEqual(none.resolvedAlgorithmVersion(modelVersion: nil), "unknown")
    }

    func testEnhancedImageIsDerivedPartTenFile() throws {
        var src = source(frames: 2)
        src.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        let image = ProcessedImage(width: 4, height: 4, bitsPerPixel: 16, samplesPerPixel: 1,
                                   photometricInterpretation: "MONOCHROME2", pixelData: Data(count: 32))
        let data = try AIDICOMOutputGenerator.createEnhancedDICOMFile(
            sourceDataSet: src, enhancedImage: image, frameIndex: 1, modelName: "denoise.mlmodel")
        let file = try DICOMFile.read(from: data)
        let out = file.dataSet
        XCTAssertEqual(file.fileMetaInformation.string(for: .mediaStorageSOPClassUID), "1.2.840.10008.5.1.4.1.1.2")
        XCTAssertEqual(file.fileMetaInformation.string(for: .mediaStorageSOPInstanceUID), out.string(for: .sopInstanceUID))
        XCTAssertNotEqual(out.string(for: .sopInstanceUID), "1.2.3.4.5", "C.7.6.1.1.2: new SOP Instance UID")
        XCTAssertNotEqual(out.string(for: .seriesInstanceUID), "1.2.3.4")
        XCTAssertEqual(out.strings(for: .imageType), ["DERIVED", "SECONDARY", "AXIAL"])
        XCTAssertEqual(out.string(for: .kvp), "120", "the source IOD's other attributes are kept")
        XCTAssertEqual(out.string(for: .numberOfFrames), "1")
        XCTAssertEqual(out.uint16(for: .bitsStored), 16)
        XCTAssertNotNil(out.string(for: .derivationDescription))
        let item = try XCTUnwrap(out.sequence(for: .sourceImageSequence)?.first)
        XCTAssertEqual(item.string(for: .referencedSOPInstanceUID), "1.2.3.4.5")
        XCTAssertEqual(item.string(for: .referencedFrameNumber), "2")
        let purpose = try XCTUnwrap(item[.purposeOfReferenceCodeSequence]?.sequenceItems?.first)
        XCTAssertEqual(purpose.string(for: .codeValue), "121322")
        XCTAssertEqual(purpose.string(for: .codingSchemeDesignator), "DCM")
        XCTAssertEqual(purpose.string(for: .codeMeaning), "Source image for image processing operation")
    }

    func testGSPSThroughPresentationStateBuilder() throws {
        let gsps = try AIDICOMOutputGenerator.createGSPSWithAnnotations(
            detections: [Detection(label: "nodule", confidence: 0.9, bbox: BoundingBox(x: 10, y: 20, width: 30, height: 40))],
            sourceDataSet: source(), modelName: "m")
        XCTAssertEqual(gsps.string(for: .sopClassUID), "1.2.840.10008.5.1.4.1.1.11.1")
        XCTAssertEqual(gsps.string(for: .modality), "PR")
        XCTAssertNotNil(gsps.string(for: .presentationCreationDate), "Type 1, Table C.11.10-1")
        XCTAssertNotNil(gsps.sequence(for: .displayedAreaSelectionSequence), "Type 1, Table C.10-4")
        let annotation = try XCTUnwrap(gsps.sequence(for: .graphicAnnotationSequence)?.first)
        XCTAssertEqual(annotation.string(for: .graphicLayer), "AI_DETECTIONS")
        let graphic = try XCTUnwrap(annotation[.graphicObjectSequence]?.sequenceItems?.first)
        XCTAssertEqual(graphic.string(for: .graphicType), "POLYLINE")
        XCTAssertEqual(graphic.string(for: .graphicAnnotationUnits), "PIXEL")
        let text = try XCTUnwrap(annotation[.textObjectSequence]?.sequenceItems?.first)
        XCTAssertEqual(text.string(for: .boundingBoxAnnotationUnits), "PIXEL", "(0070,0003) in a Text Object, Table C.10-5")
        XCTAssertNil(text[.graphicAnnotationUnits])
    }
}
