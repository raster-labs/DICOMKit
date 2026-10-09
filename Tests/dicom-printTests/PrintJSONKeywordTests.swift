import XCTest
import DICOMNetwork
import DICOMPrintKit
@testable import dicom_print

/// P-PRINT-JSON: `status` / `job --format json` key each N-GET attribute by its PS3.6
/// 2026a Table 6-1 keyword, beside the older tool keys (kept, deprecated, same value).
final class PrintJSONKeywordTests: XCTestCase {

    private func object(_ text: String?) throws -> [String: Any] {
        let text = try XCTUnwrap(text)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    // PS3.6 Table 6-1: (2110,0010) PrinterStatus, (2110,0020) PrinterStatusInfo,
    // (2110,0030) PrinterName, (0008,0070) Manufacturer, (0008,1090) ManufacturerModelName.
    func testPrinterStatusJSONHasKeywordAndDeprecatedKeys() throws {
        let status = PrinterStatus(status: "WARNING", statusInfo: "FILM JAM", printerName: "LASER1",
                                   manufacturer: "ACME", manufacturerModelName: "DryView 5")
        let dict = try object(PrintConsoleFormatter.printerStatusJSON(status))
        XCTAssertEqual(dict["PrinterStatus"] as? String, "WARNING")
        XCTAssertEqual(dict["PrinterStatusInfo"] as? String, "FILM JAM")
        XCTAssertEqual(dict["PrinterName"] as? String, "LASER1")
        XCTAssertEqual(dict["Manufacturer"] as? String, "ACME")
        XCTAssertEqual(dict["ManufacturerModelName"] as? String, "DryView 5")
        // deprecated keys keep their old values
        XCTAssertEqual(dict["status"] as? String, "WARNING")
        XCTAssertEqual(dict["statusInfo"] as? String, "FILM JAM")
        XCTAssertEqual(dict["name"] as? String, "LASER1")
        XCTAssertEqual(dict["manufacturer"] as? String, "ACME")
        XCTAssertEqual(dict["model"] as? String, "DryView 5")
        XCTAssertEqual(dict["isNormal"] as? Bool, false)
    }

    // PS3.6 Table 6-1: (2100,0020) ExecutionStatus, (2100,0030) ExecutionStatusInfo,
    // (2100,0040) CreationDate DA, (2100,0050) CreationTime TM.
    func testJobStatusJSONHasKeywordAndDeprecatedKeys() throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        let date = try XCTUnwrap(formatter.date(from: "20261001"))
        formatter.dateFormat = "HHmmss"
        let time = try XCTUnwrap(formatter.date(from: "142530"))
        let job = PrintJobStatus(printJobUID: "1.2.3", executionStatus: "PRINTING",
                                 executionStatusInfo: "NORMAL", creationDate: date, creationTime: time)
        let dict = try object(PrintConsoleFormatter.jobStatusJSON(job))
        XCTAssertEqual(dict["ExecutionStatus"] as? String, "PRINTING")
        XCTAssertEqual(dict["ExecutionStatusInfo"] as? String, "NORMAL")
        XCTAssertEqual(dict["CreationDate"] as? String, "20261001")
        XCTAssertEqual(dict["CreationTime"] as? String, "142530")
        XCTAssertEqual(dict["jobUID"] as? String, "1.2.3")
        XCTAssertEqual(dict["status"] as? String, "PRINTING")
        XCTAssertEqual(dict["statusInfo"] as? String, "NORMAL")
        XCTAssertNotNil(dict["creationDate"] as? String)   // ISO 8601, deprecated
    }

    func testHelpSaysTheOldKeysAreDeprecated() {
        let status = StatusCommand.helpMessage().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        XCTAssertTrue(status.contains("PS3.6 keyword (PrinterStatus,"))
        XCTAssertTrue(status.contains("are deprecated"))
        let job = JobCommand.helpMessage().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        XCTAssertTrue(job.contains("PS3.6 keyword (ExecutionStatus,"))
        XCTAssertTrue(job.contains("are deprecated"))
    }
}
