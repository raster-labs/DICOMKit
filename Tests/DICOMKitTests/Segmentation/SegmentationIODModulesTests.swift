//
// SegmentationIODModulesTests.swift
// DICOMKit
//
// D71 (2026-10-01): `Segmentation.buildDataSet(pixelData:)` writes the Patient (PS3.3 2026a
// Table C.7-1) and General Study (Table C.7-3) Type 2 attributes and the Enhanced General
// Equipment Module (Table C.7-8b: Manufacturer, Manufacturer's Model Name, Device Serial
// Number, Software Versions, all Type 1), the Modules Table A.51-1 lists as M.
//

import XCTest
@testable import DICOMKit
import DICOMCore

final class SegmentationIODModulesTests: XCTestCase {

    private let category = CodedConcept(codeValue: "91723000", codingSchemeDesignator: "SCT", codeMeaning: "Anatomical Structure")
    private let liver = CodedConcept(codeValue: "10200004", codingSchemeDesignator: "SCT", codeMeaning: "Liver")

    private func builder() throws -> SegmentationBuilder {
        let builder = SegmentationBuilder(rows: 2, columns: 4, segmentationType: .binary,
                                          studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4")
        try builder.addBinarySegment(number: 1, label: "Liver", mask: [1, 0, 0, 1, 0, 1, 1, 0],
                                     category: category, type: liver)
        return builder
    }

    private let type2PatientAndStudy: [(Tag, VR)] = [
        (.patientName, .PN), (.patientID, .LO), (.patientBirthDate, .DA), (.patientSex, .CS),
        (.studyDate, .DA), (.studyTime, .TM), (.referringPhysicianName, .PN), (.studyID, .SH),
        (.accessionNumber, .SH),
    ]

    func testDefaultsWriteEveryMandatoryModuleAttribute() throws {
        let (segmentation, pixelData) = try builder().build()
        let dataSet = try segmentation.buildDataSet(pixelData: pixelData)

        // Type 2: present, zero length when unknown
        for (tag, vr) in type2PatientAndStudy {
            let element = try XCTUnwrap(dataSet[tag], "\(tag) missing")
            XCTAssertEqual(element.vr, vr, "\(tag)")
            XCTAssertEqual(element.valueData.count, 0, "\(tag)")
        }
        // Type 1: present with a value
        for tag: Tag in [.manufacturer, .manufacturerModelName, .deviceSerialNumber, .softwareVersions] {
            let value = try XCTUnwrap(dataSet.string(for: tag), "\(tag) missing")
            XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, "\(tag) empty")
            XCTAssertEqual(dataSet[tag]?.vr, .LO, "\(tag)")
        }
        XCTAssertEqual(dataSet.string(for: .manufacturer), "DICOMKit")
        XCTAssertEqual(dataSet.string(for: .softwareVersions), DICOMFile.implementationVersionName)
    }

    func testValuesFromTheBuilderAreWritten() throws {
        var source = DataSet()
        source.setString("Doe^Jane", for: .patientName, vr: .PN)
        source.setString("P7", for: .patientID, vr: .LO)
        source.setString("19700101", for: .patientBirthDate, vr: .DA)
        source.setString("F", for: .patientSex, vr: .CS)
        source.setString("20260101", for: .studyDate, vr: .DA)
        source.setString("S1", for: .studyID, vr: .SH)
        source.setString("ACC9", for: .accessionNumber, vr: .SH)

        let equipment = SegmentationEquipment(manufacturer: "ACME", manufacturerModelName: "Seg",
                                              deviceSerialNumber: "SN1", softwareVersions: "3.0")
        let (segmentation, pixelData) = try builder()
            .setPatientAndStudy(SegmentationPatientAndStudy(copyingFrom: source))
            .setEquipment(equipment)
            .build()
        XCTAssertEqual(segmentation.equipment, equipment)
        let dataSet = try segmentation.buildDataSet(pixelData: pixelData)

        XCTAssertEqual(dataSet.string(for: .patientName), "Doe^Jane")
        XCTAssertEqual(dataSet.string(for: .patientID), "P7")
        XCTAssertEqual(dataSet.string(for: .patientBirthDate), "19700101")
        XCTAssertEqual(dataSet.string(for: .patientSex), "F")
        XCTAssertEqual(dataSet.string(for: .studyDate), "20260101")
        XCTAssertEqual(dataSet.string(for: .studyID), "S1")
        XCTAssertEqual(dataSet.string(for: .accessionNumber), "ACC9")
        XCTAssertEqual(dataSet[.studyTime]?.valueData.count, 0)
        XCTAssertEqual(dataSet.string(for: .manufacturer), "ACME")
        XCTAssertEqual(dataSet.string(for: .manufacturerModelName), "Seg")
        XCTAssertEqual(dataSet.string(for: .deviceSerialNumber), "SN1")
        XCTAssertEqual(dataSet.string(for: .softwareVersions), "3.0")
    }
}
