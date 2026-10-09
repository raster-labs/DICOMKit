import XCTest
import DICOMCore
@testable import DICOMKit
#if canImport(CoreGraphics)
import ImageIO
#endif

/// `--exif-fields` against DICOM 2026a (D126): Study Date is a DA value (PS3.5 2026a Table 6.2-1,
/// "YYYYMMDD") and Study Time a TM value ("HHMMSS.FFFFFF", trailing components may be
/// unspecified); Exif DateTimeOriginal is written "YYYY:MM:DD HH:MM:SS". Patient ID, Modality and
/// Series Description have no EXIF/TIFF tag of their own and are written into Exif UserComment as
/// `<PS3.6 keyword>=<value>`.
final class ExportEXIFFieldsTests: XCTestCase {

    func testDAAndTMBecomeExifDateTime() {
        XCTAssertEqual(DICOMImageExporter.exifDateTime(fromDA: "20240115", tm: "143025.123456"), "2024:01:15 14:30:25")
        XCTAssertEqual(DICOMImageExporter.exifDateTime(fromDA: "20240115", tm: "1430"), "2024:01:15 14:30:00")
        XCTAssertEqual(DICOMImageExporter.exifDateTime(fromDA: "20240115", tm: "14"), "2024:01:15 14:00:00")
        // No (or no valid) TM: Exif's blank spelling of an unknown time, not an invented midnight
        XCTAssertEqual(DICOMImageExporter.exifDateTime(fromDA: "20240115"), "2024:01:15   :  :  ")
        XCTAssertEqual(DICOMImageExporter.exifDateTime(fromDA: "20240115", tm: "2561"), "2024:01:15   :  :  ")
    }

    func testValuesThatAreNotADAAreRefused() {
        XCTAssertNil(DICOMImageExporter.exifDateTime(fromDA: "2024.01.15"))
        XCTAssertNil(DICOMImageExporter.exifDateTime(fromDA: "2024011"))
        XCTAssertNil(DICOMImageExporter.exifDateTime(fromDA: "20240230"), "not a Gregorian date")
        XCTAssertNil(DICOMImageExporter.exifDateTime(fromDA: "20241301"))
        XCTAssertNotNil(DICOMImageExporter.exifDateTime(fromDA: "20240229"), "leap day")
    }

    func testEveryFieldThatIsReadHasAMapping() {
        XCTAssertTrue(DICOMImageExporter.supportedEXIFFields.contains("PatientID"))
        for field in DICOMImageExporter.supportedEXIFFields {
            XCTAssertNotNil(DICOMImageExporter.mapDICOMFieldToEXIF(field), field)
        }
        XCTAssertEqual(DICOMImageExporter.unsupportedEXIFFields(["PatientID", "patientname", "OperatorsName"]),
                       ["OperatorsName"])
        XCTAssertNotEqual(DICOMImageExporter.mapDICOMFieldToEXIF("Modality")?.key, "Software")
    }

    #if canImport(CoreGraphics)
    func testBuiltMetadataCarriesConvertedDateAndUserComment() throws {
        var ds = DataSet()
        ds.setString("20240115", for: .studyDate, vr: .DA)
        ds.setString("143025", for: .studyTime, vr: .TM)
        ds.setString("PID-7", for: .patientID, vr: .LO)
        ds.setString("CT", for: .modality, vr: .CS)
        ds.setString("Axial", for: .seriesDescription, vr: .LO)
        let file = DICOMFile(fileMetaInformation: DataSet(), dataSet: ds)
        let built = try XCTUnwrap(DICOMImageExporter.buildEXIFMetadata(
            from: file, fields: ["StudyDate", "PatientID", "Modality", "SeriesDescription"]) as? [String: Any])
        let exif = try XCTUnwrap(built[kCGImagePropertyExifDictionary as String] as? [String: Any])
        XCTAssertEqual(exif["DateTimeOriginal"] as? String, "2024:01:15 14:30:25")
        XCTAssertEqual(exif["UserComment"] as? String, "PatientID=PID-7; Modality=CT; SeriesDescription=Axial")
        XCTAssertNil(exif["Software"])
        let tiff = try XCTUnwrap(built[kCGImagePropertyTIFFDictionary as String] as? [String: Any])
        XCTAssertEqual(tiff["Software"] as? String, "DICOMKit dicom-export v\(DICOMImageExporter.toolVersion)")
    }

    func testAStudyDateThatIsNotADAIsNotWritten() throws {
        var ds = DataSet()
        ds.setString("2024-01-15", for: .studyDate, vr: .DA)
        let file = DICOMFile(fileMetaInformation: DataSet(), dataSet: ds)
        let built = try XCTUnwrap(DICOMImageExporter.buildEXIFMetadata(from: file, fields: ["StudyDate"]) as? [String: Any])
        let exif = built[kCGImagePropertyExifDictionary as String] as? [String: Any]
        XCTAssertNil(exif?["DateTimeOriginal"])
    }
    #endif
}
