import XCTest
import Foundation
import DICOMNetwork
import DICOMPrintKit

final class M6PrintWarningOutputTests: XCTestCase {
    func testWarningRemainsSuccessfulAndVisibleInSharedTextAndJSON() throws {
        let warning = PrintWarning(status: .from(0xB604), filmBoxUID: "1.2.3.4",
                                   detail: "M6 IMAGE DEMAGNIFIED")
        let result = PrintResult(success: true, status: warning.status,
                                 filmSessionUID: "1.2.3", filmBoxUID: "1.2.3.4", warnings: [warning])
        let lines = PrintConsoleFormatter.printResultText(result)
        XCTAssertTrue(lines.contains { $0.contains("submitted successfully") })
        XCTAssertTrue(lines.contains { $0.hasPrefix("Warning:") && $0.contains("0xB604") && $0.contains("M6 IMAGE DEMAGNIFIED") })
        let json = try XCTUnwrap(PrintConsoleFormatter.printResultJSON(result))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(object["success"] as? Bool, true)
        let warnings = try XCTUnwrap(object["warnings"] as? [[String: Any]])
        XCTAssertEqual(warnings.count, 1)
        XCTAssertEqual(warnings[0]["status"] as? String, "0xB604")
        XCTAssertEqual(warnings[0]["filmBoxUID"] as? String, "1.2.3.4")
        XCTAssertEqual(warnings[0]["detail"] as? String, "M6 IMAGE DEMAGNIFIED")
        XCTAssertTrue((warnings[0]["message"] as? String)?.contains("demagnified") == true)
    }

    func testPlainSuccessKeepsExistingJSONShape() throws {
        let result = PrintResult(success: true, status: .success)
        let json = try XCTUnwrap(PrintConsoleFormatter.printResultJSON(result))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["success"])
        XCTAssertFalse(PrintConsoleFormatter.printResultText(result).contains { $0.hasPrefix("Warning:") })
    }

    func testOlderWarningStatusCallerStillGetsVisibleWarningWithoutDetails() throws {
        let result = PrintResult(success: true, status: .from(0xB604))
        XCTAssertTrue(PrintConsoleFormatter.printResultText(result).contains { $0.hasPrefix("Warning:") && $0.contains("0xB604") })
        XCTAssertTrue(try XCTUnwrap(PrintConsoleFormatter.printResultJSON(result)).contains("warnings"))
    }
}
