import XCTest
import DICOMNetwork
import DICOMPrintKit
@testable import dicom_printscp

/// P-PRINT-JSON: `dicom-printscp status --format json` keys each attribute the emulator
/// would answer an N-GET with by its PS3.6 2026a Table 6-1 keyword, beside the older
/// tool keys (kept, deprecated, same value).
final class PrinterStatusJSONTests: XCTestCase {

    func testStatusJSONHasKeywordAndDeprecatedKeys() throws {
        let text = try XCTUnwrap(PrintSCPConsole.printerStatusJSON(settings: PrintSCPSettings()))
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertNotNil(dict["PrinterStatus"] as? String)
        XCTAssertEqual(dict["PrinterStatus"] as? String, dict["status"] as? String)
        for (keyword, old) in [("PrinterStatusInfo", "statusInfo"), ("PrinterName", "name"),
                               ("Manufacturer", "manufacturer"), ("ManufacturerModelName", "model")] {
            XCTAssertEqual(dict[keyword] as? String, dict[old] as? String, keyword)
        }
        XCTAssertTrue(["NORMAL", "WARNING", "FAILURE"].contains(dict["PrinterStatus"] as? String ?? ""))
    }

    func testHelpSaysTheOldKeysAreDeprecated() {
        let help = StatusCommand.helpMessage().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        XCTAssertTrue(help.contains("PS3.6 keyword (PrinterStatus,"))
        XCTAssertTrue(help.contains("are deprecated"))
    }
}
