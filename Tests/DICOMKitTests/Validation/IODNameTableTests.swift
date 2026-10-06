// IODNameTableTests.swift
// DICOM 2026a deferred row D248: the SOP Class → IOD name map of `dicom-validate --iod` and the
// DICOMStudio Workshop is DICOMValidator.iodNameBySOPClassUID (PS3.6 2026a Table A-1 UIDs;
// the IODs of PS3.3 2026a A.2, A.3, A.4, A.6, A.8, A.33.1, A.33.3 per PS3.4 Table B.5-1).

import XCTest
import DICOMCore
import DICOMDictionary
@testable import DICOMKit

final class IODNameTableTests: XCTestCase {

    /// PS3.6 2026a Table A-1 (UID, Name, Keyword) rows, dumped from part06_2026a.xml by script.
    private static let tableA1: [(uid: String, name: String, keyword: String, engine: String)] = [
        ("1.2.840.10008.5.1.4.1.1.1", "Computed Radiography Image Storage", "ComputedRadiographyImageStorage", "CRImageStorage"),
        ("1.2.840.10008.5.1.4.1.1.2", "CT Image Storage", "CTImageStorage", "CTImageStorage"),
        ("1.2.840.10008.5.1.4.1.1.4", "MR Image Storage", "MRImageStorage", "MRImageStorage"),
        ("1.2.840.10008.5.1.4.1.1.6.1", "Ultrasound Image Storage", "UltrasoundImageStorage", "USImageStorage"),
        ("1.2.840.10008.5.1.4.1.1.7", "Secondary Capture Image Storage", "SecondaryCaptureImageStorage", "SecondaryCaptureImageStorage"),
        ("1.2.840.10008.5.1.4.1.1.11.1", "Grayscale Softcopy Presentation State Storage", "GrayscaleSoftcopyPresentationStateStorage", "GrayscaleSoftcopyPresentationState"),
        ("1.2.840.10008.5.1.4.1.1.11.3", "Pseudo-Color Softcopy Presentation State Storage", "PseudoColorSoftcopyPresentationStateStorage", "PseudoColorSoftcopyPresentationState"),
    ]

    func testTableIsExactlyTheSevenTableA1SOPClasses() {
        XCTAssertEqual(DICOMValidator.iodNameBySOPClassUID.count, Self.tableA1.count)
        for row in Self.tableA1 {
            XCTAssertEqual(DICOMValidator.iodNameBySOPClassUID[row.uid], row.engine, row.uid)
            // The UID is a Table A-1 SOP Class with that name and keyword (DICOMDictionary carries Table A-1).
            let entry = UIDDictionary.lookup(uid: row.uid)
            XCTAssertEqual(entry?.name, row.name, row.uid)
            XCTAssertEqual(entry?.keyword, row.keyword, row.uid)
            XCTAssertEqual(entry?.type, .sopClass, row.uid)
        }
    }

    func testSRSOPClassesMapToStructuredReportAndOthersToNil() {
        XCTAssertEqual(DICOMValidator.iodName(forSOPClassUID: "1.2.840.10008.5.1.4.1.1.88.11"), "StructuredReport") // Basic Text SR
        XCTAssertEqual(DICOMValidator.iodName(forSOPClassUID: "1.2.840.10008.5.1.4.1.1.88.59"), "StructuredReport") // Key Object Selection Document
        XCTAssertEqual(DICOMValidator.iodName(forSOPClassUID: "1.2.840.10008.5.1.4.1.1.6.1"), "USImageStorage")
        XCTAssertNil(DICOMValidator.iodName(forSOPClassUID: "1.2.840.10008.5.1.4.1.1.2.1"), "Enhanced CT is not implemented")
        XCTAssertNil(DICOMValidator.iodName(forSOPClassUID: "not a uid"))
    }

    func testIODOptionAcceptsTableA1KeywordsUIDsAndShortNames() {
        for row in Self.tableA1 {
            XCTAssertEqual(DICOMValidator.iodName(forIODOption: row.keyword), row.engine, row.keyword)
            XCTAssertEqual(DICOMValidator.iodName(forIODOption: row.keyword.lowercased()), row.engine, row.keyword)
            XCTAssertEqual(DICOMValidator.iodName(forIODOption: row.uid), row.engine, row.uid)
            XCTAssertEqual(DICOMValidator.sopClassUID(forIODOption: row.keyword.uppercased()), row.uid, row.keyword)
        }
        XCTAssertEqual(DICOMValidator.iodName(forIODOption: "ComprehensiveSRStorage"), "StructuredReport")
        XCTAssertEqual(DICOMValidator.iodName(forIODOption: "KeyObjectSelectionDocumentStorage"), "StructuredReport")
        XCTAssertEqual(DICOMValidator.iodName(forIODOption: "US"), "USImageStorage")
        XCTAssertEqual(DICOMValidator.iodName(forIODOption: "us"), "USImageStorage")
        // The engine's short names and unsupported IODs pass through unchanged.
        for v in ["ct", "mr", "cr", "sc", "gsps", "sr", "kos", "EnhancedCTImageStorage"] {
            XCTAssertEqual(DICOMValidator.iodName(forIODOption: v), v)
        }
        XCTAssertNil(DICOMValidator.sopClassUID(forIODOption: "ct"))
    }

    func testValidatorDetectsTheIODFromTheSharedTable() throws {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.1", for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4", for: .sopInstanceUID, vr: .UI)
        let data = try DICOMFile.create(dataSet: ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.1", sopInstanceUID: "1.2.3.4").write()
        let detected = try DICOMValidator(level: 3, iod: nil, force: false).validate(data: data, filePath: "x")
        let named = try DICOMValidator(level: 3, iod: DICOMValidator.iodName(forIODOption: "ComputedRadiographyImageStorage"), force: false)
            .validate(data: data, filePath: "x")
        XCTAssertFalse(detected.warnings.contains { $0.message.contains("IOD validation not implemented") })
        XCTAssertEqual(detected.errors.map(\.message), named.errors.map(\.message))
        XCTAssertTrue(named.errors.contains { $0.message.contains("Missing Type 2 attribute View Position [PS3.3 C.8.1.1 CR Series (Table C.8-1)") })
    }
}
