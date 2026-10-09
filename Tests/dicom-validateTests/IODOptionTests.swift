import XCTest
import DICOMCore
import DICOMKit
import DICOMDictionary
@testable import dicom_validate

/// `--iod` values: PS3.6 2026a Table A-1 keywords and UIDs map to the IODs DICOMValidator implements.
final class IODOptionTests: XCTestCase {

    func testTableA1KeywordsAndUIDsReachTheEngineIOD() {
        let cases: [(String, String)] = [
            ("CTImageStorage", "CTImageStorage"),
            ("MRImageStorage", "MRImageStorage"),
            ("ComputedRadiographyImageStorage", "CRImageStorage"),
            ("UltrasoundImageStorage", "USImageStorage"),
            ("SecondaryCaptureImageStorage", "SecondaryCaptureImageStorage"),
            ("GrayscaleSoftcopyPresentationStateStorage", "GrayscaleSoftcopyPresentationState"),
            ("PseudoColorSoftcopyPresentationStateStorage", "PseudoColorSoftcopyPresentationState"),
            ("ComprehensiveSRStorage", "StructuredReport"),
            ("KeyObjectSelectionDocumentStorage", "StructuredReport"),
            ("1.2.840.10008.5.1.4.1.1.1", "CRImageStorage"),
            ("1.2.840.10008.5.1.4.1.1.88.11", "StructuredReport"),
            ("ultrasoundimagestorage", "USImageStorage"),
            ("US", "USImageStorage"),
        ]
        for (value, engine) in cases { XCTAssertEqual(IODOption.engineName(for: value), engine, value) }
    }

    func testEngineShortNamesAndUnsupportedIODsPassThrough() {
        for v in ["ct", "mr", "cr", "sc", "gsps", "sr", "kos", "CTImageStorage"] {
            XCTAssertEqual(IODOption.engineName(for: v).lowercased(), v == "CTImageStorage" ? "ctimagestorage" : v)
        }
        XCTAssertEqual(IODOption.engineName(for: "EnhancedCTImageStorage"), "EnhancedCTImageStorage")
    }

    func testEngineUIDsAreTableA1SOPClasses() {
        let a1 = Set(UIDDictionary.sopClasses.map(\.uid))
        XCTAssertTrue(Set(IODOption.engineNameBySOPClassUID.keys).isSubset(of: a1))
    }

    func testTableA1KeywordValidatesLikeTheEngineName() throws {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.1", for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4", for: .sopInstanceUID, vr: .UI)
        let data = try DICOMFile.create(dataSet: ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.1", sopInstanceUID: "1.2.3.4").write()
        let viaKeyword = try DICOMValidator(level: 3, iod: IODOption.engineName(for: "ComputedRadiographyImageStorage"), force: false)
            .validate(data: data, filePath: "x")
        XCTAssertFalse(viaKeyword.warnings.contains { $0.message.contains("IOD validation not implemented") })
        XCTAssertTrue(viaKeyword.errors.contains { $0.message.contains("Missing Type 2 attribute View Position [PS3.3 C.8.1.1 CR Series (Table C.8-1)") })
    }
}
