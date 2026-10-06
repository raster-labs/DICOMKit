import XCTest
@testable import DICOMWeb

/// Pins the DICOMweb option rules lifted from dicom-wado (D265) to the DICOM 2026a text:
/// PS3.18 9.1.2.2.1 / Table 8.7.4-1 (contentType), 9.5.1.2.1 (frameNumber), 9.5.1.2.5 (region),
/// Tables 9.4.1-1 / 9.5.1-1 (parameter warnings), 8.3.4.4 (limit / offset), 11.7 (--update alias).
final class DICOMwebOptionRulesValuesTests: XCTestCase {

    func testContentTypesAreApplicationDicomPlusTable8_7_4_1() throws {
        XCTAssertEqual(DICOMwebOptionRules.uriContentTypes,
                       ["application/dicom", "image/jpeg", "image/gif", "image/png", "image/jp2", "image/jph", "image/jxl",
                        "video/mpeg", "video/mp4", "video/H265",
                        "text/html", "text/plain", "text/xml", "text/rtf", "application/pdf"])
        for value in DICOMwebOptionRules.uriContentTypes {
            XCTAssertEqual(try DICOMwebOptionRules.uriContentType(value).rawValue, value)
        }
        XCTAssertEqual(try DICOMwebOptionRules.uriContentType(nil), .dicom)
        XCTAssertEqual(try DICOMwebOptionRules.uriContentType("  "), .dicom)
        XCTAssertThrowsError(try DICOMwebOptionRules.uriContentType("image/bmp")) { error in
            let r = error as? DICOMwebOptionRefusal
            XCTAssertEqual(r?.kind, .usage)
            XCTAssertEqual(r?.message, "--content-type 'image/bmp' cannot be requested over WADO-URI. Use one of: "
                + DICOMwebOptionRules.uriContentTypes.joined(separator: ", ")
                + " (PS3.18 9.1.2.2.1: application/dicom or a Rendered Media Type of Table 8.7.4-1)")
        }
    }

    func testFrameNumberIsASinglePositiveInteger() throws {
        XCTAssertNil(try DICOMwebOptionRules.uriFrameNumber(nil))
        let f = try XCTUnwrap(DICOMwebOptionRules.uriFrameNumber("3, 4,5"))
        XCTAssertEqual(f.frame, 3)
        XCTAssertEqual(f.notSent, 2)
        for bad in ["0", "-1", "x", ""] {
            XCTAssertThrowsError(try DICOMwebOptionRules.uriFrameNumber(bad)) {
                XCTAssertEqual(($0 as? DICOMwebOptionRefusal)?.kind, .usage, bad)
                XCTAssertTrue(($0 as? DICOMwebOptionRefusal)?.message.contains("PS3.18 9.5.1.2.1") ?? false)
            }
        }
    }

    func testRegionAndAnnotation() throws {
        XCTAssertNil(try DICOMwebOptionRules.uriRegion(nil))
        XCTAssertNotNil(try DICOMwebOptionRules.uriRegion("0,0,0.5,0.5"))
        XCTAssertThrowsError(try DICOMwebOptionRules.uriRegion("1,2,3")) {
            XCTAssertEqual(($0 as? DICOMwebOptionRefusal)?.message,
                           "--region takes xmin,ymin,xmax,ymax, four decimal numbers (PS3.18 9.5.1.2.5); got '1,2,3'")
        }
        XCTAssertEqual(DICOMwebOptionRules.uriAnnotation(" patient, ,technique"), ["patient", "technique"])
        XCTAssertEqual(DICOMwebOptionRules.uriAnnotation(nil), [])
    }

    func testParametersOutsideTheirTransactionWarn() {
        // Table 9.5.1-1 parameters with application/dicom (Table 9.4.1-1)
        XCTAssertEqual(DICOMwebOptionRules.uriParameterWarnings(contentType: .dicom, frame: 2, rows: nil, columns: nil,
                                                                transferSyntax: nil, anonymize: false),
                       ["frameNumber (--frames) is a Retrieve Rendered Instance parameter (PS3.18 Table 9.5.1-1), "
                        + "not defined for application/dicom (Table 9.4.1-1); the server may ignore it"])
        // Table 9.4.1-1 parameters with a Rendered Media Type (Table 9.5.1-1)
        XCTAssertEqual(DICOMwebOptionRules.uriParameterWarnings(contentType: .png, frame: nil, rows: nil, columns: nil,
                                                                transferSyntax: "1.2.840.10008.1.2.1", anonymize: true),
                       ["transferSyntax (--transfer-syntax), anonymize (--anonymize) are Retrieve DICOM Instance parameters "
                        + "(PS3.18 Table 9.4.1-1), not defined for image/png (Table 9.5.1-1); the server may ignore them"])
        XCTAssertTrue(DICOMwebOptionRules.uriParameterWarnings(contentType: .jpeg, frame: 2, rows: 64, columns: 64,
                                                               transferSyntax: nil, anonymize: false).isEmpty)
    }

    func testLimitAndOffsetAreUint() {
        XCTAssertNil(DICOMwebOptionRules.pagingProblem(limit: 0, offset: 0))
        XCTAssertEqual(DICOMwebOptionRules.pagingProblem(limit: -1, offset: 0),
                       "--limit must be 0 or more (PS3.18 8.3.4.4: limit is an unsigned integer)")
        XCTAssertEqual(DICOMwebOptionRules.pagingProblem(limit: 0, offset: -1),
                       "--offset must be 0 or more (PS3.18 8.3.4.4: offset is an unsigned integer)")
        XCTAssertThrowsError(try DICOMwebOptionRules.validatePaging(limit: -1, offset: 0)) {
            XCTAssertEqual(($0 as? DICOMwebOptionRefusal)?.exitCode, 64)
        }
    }

    func testUpdateIsAnAliasOfChangeWorkitemState() throws {
        XCTAssertEqual(try DICOMwebOptionRules.changeStateWorkitem(changeState: "1.2", update: nil), "1.2")
        XCTAssertEqual(try DICOMwebOptionRules.changeStateWorkitem(changeState: nil, update: "1.3"), "1.3")
        XCTAssertNil(try DICOMwebOptionRules.changeStateWorkitem(changeState: nil, update: nil))
        XCTAssertThrowsError(try DICOMwebOptionRules.changeStateWorkitem(changeState: "1", update: "1")) {
            XCTAssertEqual(($0 as? DICOMwebOptionRefusal)?.kind, .refused)
            XCTAssertTrue(($0 as? DICOMwebOptionRefusal)?.message.contains("PS3.18 2026a 11.7") ?? false)
        }
        XCTAssertEqual(DICOMwebOptionRules.updateDeprecationNote,
                       "Note: --update is deprecated; use --change-state (it performs Change Workitem State, "
                       + "PS3.18 2026a 11.7, not Update Workitem, 11.6)")
    }

    func testTimeouts() {
        let t = DICOMwebOptionRules.timeouts(seconds: 600)
        XCTAssertEqual(t.connectTimeout, 600)
        XCTAssertEqual(t.readTimeout, 600)
        XCTAssertEqual(t.resourceTimeout, 600)
        XCTAssertEqual(t.operationTimeout, 600)
        let short = DICOMwebOptionRules.timeouts(seconds: 0)
        XCTAssertEqual(short.readTimeout, 1)
        XCTAssertEqual(short.resourceTimeout, DICOMwebConfiguration.TimeoutConfiguration.default.resourceTimeout)
    }
}
