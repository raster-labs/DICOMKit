//
// SegmentationOutputTests.swift
// dicom-ai
//
// D44: the Segmentation object `dicom-ai segment --format dicom-seg` writes carries, in every
// Segment Sequence (0062,0002) Item, one Segmented Property Category Code Sequence (0062,0003)
// Item and one Segmented Property Type Code Sequence (0062,000F) Item, both Type 1 (PS3.3 2026a
// Table C.8.20-4; Baseline CID 7150 / CID 7151), with the other Type 1 rows of Tables C.8.20-2
// and C.8.20-4 and the Type 1C Segment Algorithm Name (AUTOMATIC). Codes: (85756007, SCT,
// "Tissue") is a row of CID 7150 and of CID 7166 (in CID 7151 through CID 7191);
// (49755003, SCT, "Morphologically Abnormal Structure") is a row of CID 7150; (52988006, SCT,
// "Lesion") is a row of CID 7159 (in CID 7151 through CID 7194). PS3.16 2026a.
//

import XCTest
import DICOMKit
import DICOMCore
@testable import dicom_ai

final class SegmentationOutputTests: XCTestCase {

    private func source() -> DataSet {
        var dataSet = DataSet()
        dataSet.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        dataSet.setString("1.2.3.4.5", for: .sopInstanceUID, vr: .UI)
        dataSet.setString("1.2.3", for: .studyInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4.5.6", for: .frameOfReferenceUID, vr: .UI)
        dataSet.setString("Doe^Jane", for: .patientName, vr: .PN)
        dataSet.setString("P001", for: .patientID, vr: .LO)
        return dataSet
    }

    private func mask() -> SegmentationMask {
        // 2 rows × 8 columns, class 0 left half, class 1 right half
        SegmentationMask(width: 8, height: 2, data: Data([0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1]), numClasses: 2)
    }

    private func write(category: CodedConcept = SegmentPropertyCodes.defaultCategory,
                       type: CodedConcept = SegmentPropertyCodes.defaultType) throws -> DataSet {
        let data = try AIDICOMOutputGenerator.createSegmentationObject(
            sourceDataSet: source(), segmentationMask: mask(), labels: ["Background", "Organ"],
            modelName: "TestNet 1.0", category: category, type: type)
        let file = try DICOMFile.read(from: data)
        XCTAssertEqual(file.fileMetaInformation.string(for: .mediaStorageSOPClassUID), Segmentation.segmentationStorageUID)
        return file.dataSet
    }

    private func code(_ item: SequenceItem, _ tag: Tag) throws -> (String, String, String) {
        let element = try XCTUnwrap(item[tag])
        XCTAssertEqual(element.vr, .SQ)
        XCTAssertEqual(element.sequenceItems?.count, 1, "Table C.8.20-4: only a single Item")
        let code = try XCTUnwrap(element.sequenceItems?.first)
        return (try XCTUnwrap(code.string(for: .codeValue)),
                try XCTUnwrap(code.string(for: .codingSchemeDesignator)),
                try XCTUnwrap(code.string(for: .codeMeaning)))
    }

    func testEverySegmentCarriesDefaultCategoryAndType() throws {
        let dataSet = try write()
        let segments = try XCTUnwrap(dataSet.sequence(for: .segmentSequence))
        XCTAssertEqual(segments.count, 2)
        for item in segments {
            let category = try code(item, .segmentedPropertyCategoryCodeSequence)
            XCTAssertEqual(category.0, "85756007"); XCTAssertEqual(category.1, "SCT"); XCTAssertEqual(category.2, "Tissue")
            let type = try code(item, .segmentedPropertyTypeCodeSequence)
            XCTAssertEqual(type.0, "85756007"); XCTAssertEqual(type.1, "SCT"); XCTAssertEqual(type.2, "Tissue")
        }
    }

    func testChosenCodesAreWritten() throws {
        let dataSet = try write(
            category: try SegmentPropertyCodes.parse("abnormal-structure", from: SegmentPropertyCodes.categories, option: "--segment-category"),
            type: try SegmentPropertyCodes.parse("SCT:52988006", from: SegmentPropertyCodes.types, option: "--segment-type"))
        let item = try XCTUnwrap(dataSet.sequence(for: .segmentSequence)?.first)
        let category = try code(item, .segmentedPropertyCategoryCodeSequence)
        XCTAssertEqual(category.0, "49755003"); XCTAssertEqual(category.2, "Morphologically Abnormal Structure")
        let type = try code(item, .segmentedPropertyTypeCodeSequence)
        XCTAssertEqual(type.0, "52988006"); XCTAssertEqual(type.1, "SCT"); XCTAssertEqual(type.2, "Lesion")
    }

    /// Type 1 rows of Tables C.8.20-2 and C.8.20-4, and Segment Algorithm Name (1C, AUTOMATIC)
    func testType1RowsOfSegmentationImageModule() throws {
        let dataSet = try write()
        XCTAssertEqual(dataSet.strings(for: .imageType), ["DERIVED", "PRIMARY"])
        XCTAssertEqual(dataSet.string(for: .contentLabel), "AI_SEGMENTATION")
        XCTAssertEqual(dataSet.string(for: .photometricInterpretation), "MONOCHROME2")
        XCTAssertEqual(dataSet.string(for: .lossyImageCompression), "00")
        XCTAssertEqual(dataSet.string(for: .segmentationType), "BINARY")
        XCTAssertEqual(dataSet.uint16(for: .bitsAllocated), 1)
        XCTAssertEqual(dataSet.uint16(for: .bitsStored), 1)
        XCTAssertEqual(dataSet.uint16(for: .highBit), 0)
        XCTAssertEqual(dataSet.uint16(for: .samplesPerPixel), 1)
        XCTAssertEqual(dataSet.uint16(for: .pixelRepresentation), 0)
        XCTAssertNotNil(dataSet[.pixelData])
        XCTAssertEqual(dataSet.string(for: .frameOfReferenceUID), "1.2.3.4.5.6")
        XCTAssertEqual(dataSet.string(for: .patientName), "Doe^Jane")
        for tag in [Tag.manufacturer, .manufacturerModelName, .deviceSerialNumber, .softwareVersions] {
            XCTAssertFalse(dataSet.string(for: tag)?.isEmpty ?? true, "\(tag) is Type 1 in Enhanced General Equipment")
        }
        let segments = try XCTUnwrap(dataSet.sequence(for: .segmentSequence))
        for (index, item) in segments.enumerated() {
            XCTAssertEqual(item[.segmentNumber]?.uint16Value, UInt16(index + 1))
            XCTAssertEqual(item.string(for: .segmentLabel), ["Background", "Organ"][index])
            XCTAssertEqual(item.string(for: .segmentAlgorithmType), "AUTOMATIC")
            XCTAssertEqual(item.string(for: .segmentAlgorithmName), "TestNet 1.0")
        }
    }

    /// The object passes D37d: parsed back and rebuilt through `Segmentation.buildDataSet`
    func testPassesSegmentationDataSetValidation() throws {
        let dataSet = try write()
        let parsed = try SegmentationParser.parse(from: dataSet)
        XCTAssertEqual(parsed.segments.count, 2)
        XCTAssertEqual(parsed.segments.first?.category, SegmentPropertyCodes.defaultCategory)
        XCTAssertEqual(parsed.segments.first?.type, SegmentPropertyCodes.defaultType)
        let pixelData = try XCTUnwrap(dataSet[.pixelData]?.valueData)
        XCTAssertNoThrow(try parsed.buildDataSet(pixelData: pixelData))
    }

    func testOptionParsing() throws {
        XCTAssertEqual(try SegmentPropertyCodes.parse("Tissue", from: SegmentPropertyCodes.categories, option: "x").codeValue, "85756007")
        let custom = try SegmentPropertyCodes.parse("SCT:10200004:Liver", from: SegmentPropertyCodes.types, option: "x")
        XCTAssertEqual(custom, CodedConcept(codeValue: "10200004", codingSchemeDesignator: "SCT", codeMeaning: "Liver"))
        XCTAssertThrowsError(try SegmentPropertyCodes.parse("SCT:99999999", from: SegmentPropertyCodes.types, option: "x"))
        XCTAssertThrowsError(try SegmentPropertyCodes.parse("nonsense", from: SegmentPropertyCodes.categories, option: "x"))
        XCTAssertEqual(SegmentPropertyCodes.categories.count, 8, "CID 7150 has 8 rows")
    }
}
