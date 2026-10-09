import XCTest
import DICOMNetwork
@testable import DICOMPrintKit

/// D90: the printer / print job status blocks label each N-GET attribute with its
/// name from PS3.3 2026a Table C.13-9 (Printer Module) / Table C.13-8 (Print Job
/// Module), spelled as PS3.6 2026a Table 6-1 spells it.
final class PrintConsoleLabelTests: XCTestCase {

    func testPrinterStatusLabelsAreTheC13_9AttributeNames() {
        let status = PrinterStatus(status: "WARNING", statusInfo: "FILM JAM", printerName: "LASER1",
                                   manufacturer: "ACME", manufacturerModelName: "DryView 5")
        let lines = PrintConsoleFormatter.printerStatusText(status)
        XCTAssertTrue(lines.contains("Printer Name: LASER1"))               // (2110,0030)
        XCTAssertTrue(lines.contains("Printer Status: WARNING"))            // (2110,0010)
        XCTAssertTrue(lines.contains("Printer Status Info: FILM JAM"))      // (2110,0020)
        XCTAssertTrue(lines.contains("Manufacturer: ACME"))                 // (0008,0070)
        XCTAssertTrue(lines.contains("Manufacturer's Model Name: DryView 5")) // (0008,1090)
        XCTAssertFalse(lines.contains { $0.hasPrefix("Name:") || $0.hasPrefix("Status:") || $0.hasPrefix("Model:") })
    }

    func testJobStatusLabelsAreTheC13_8AttributeNames() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let status = PrintJobStatus(printJobUID: "1.2.3", executionStatus: "FAILURE",
                                    executionStatusInfo: "INVALID PAGE DES",
                                    creationDate: date, creationTime: date)
        let lines = PrintConsoleFormatter.jobStatusText(status)
        XCTAssertTrue(lines.contains("Execution Status: FAILURE"))                 // (2100,0020)
        XCTAssertTrue(lines.contains("Execution Status Info: INVALID PAGE DES"))   // (2100,0030)
        XCTAssertTrue(lines.contains { $0.hasPrefix("Creation Date: ") })          // (2100,0040)
        XCTAssertTrue(lines.contains { $0.hasPrefix("Creation Time: ") })          // (2100,0050)
        XCTAssertFalse(lines.contains { $0.hasPrefix("Status:") || $0.hasPrefix("Created:") })
    }
}
