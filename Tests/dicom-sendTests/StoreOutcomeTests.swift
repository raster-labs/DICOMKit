import XCTest
import DICOMNetwork
@testable import dicom_send

/// C-STORE response handling against PS3.4 2026a Table B.2-1 (C-STORE Response
/// Status Values) and PS3.7 2026a Table 9.3-1 (C-STORE-RQ Priority values).
final class StoreOutcomeTests: XCTestCase {

    // PS3.4 Table B.2-1, 2026a: Success 0000; Warning B000 / B007 / B006;
    // Failure A7xx / A9xx / Cxxx. PS3.7 9.1.1.1.9 adds 0122 Refused: SOP Class not supported.
    func testSuccessIsStored() {
        XCTAssertEqual(StoreOutcome(status: .from(0x0000)), .stored)
    }

    func testWarningClassIsStoredWithWarning() {
        for code: UInt16 in [0xB000, 0xB006, 0xB007, 0xB001, 0xBFFF] {
            XCTAssertEqual(StoreOutcome(status: .from(code)), .storedWithWarning, String(format: "%04X", code))
        }
    }

    func testFailureClassIsNotStored() {
        for code: UInt16 in [0xA700, 0xA701, 0xA7FF, 0xA900, 0xA901, 0xA9FF, 0xC000, 0xC123, 0xCFFF, 0x0122] {
            XCTAssertEqual(StoreOutcome(status: .from(code)), .failed, String(format: "%04X", code))
        }
    }

    func testFailureStatusErrorNamesTheStatus() {
        let error = SendError.storeFailed(.from(0xA700))
        let text = error.errorDescription ?? ""
        XCTAssertTrue(text.contains("0xA700"), text)
        XCTAssertTrue(text.contains("Out of resources"), text)
    }

    // D261: the classes, the per-file ✅ / warning line and the partial-failure text
    // are the shared NetworkConsole ones, and so is the ❌ text (PS3.4 Table B.2-1 wording).
    func testSharedOutcomeAndTexts() {
        XCTAssertEqual(NetworkConsole.CStoreOutcome(status: .from(0x0000)), .stored)
        XCTAssertEqual(NetworkConsole.CStoreOutcome(status: .from(0xB000)), .storedWithWarning)
        XCTAssertEqual(NetworkConsole.CStoreOutcome(status: .from(0xA700)), .failed)
        XCTAssertEqual(NetworkConsole.sendFileResult(status: .success, rtt: 0.012),
                       NetworkConsole.sendFileResultSuffix(success: true, rtt: 0.012, error: nil))
        XCTAssertEqual(NetworkConsole.sendFileResult(status: .from(0xB007), rtt: 0.012),
                       NetworkConsole.sendFileResultSuffix(success: true, rtt: 0.012, error: nil)
                       + NetworkConsole.sendFileWarningLine(status: .from(0xB007)))
        XCTAssertEqual(SendError.storeFailed(.from(0xA700)).errorDescription,
                       NetworkConsole.sendStoreFailedText(status: .from(0xA700)))
        // D261 completion: the per-file ❌ line is the engine's PS3.4 Table B.2-1 wording.
        XCTAssertEqual(NetworkConsole.sendFileResultSuffix(
                           success: false, rtt: 0, error: SendError.storeFailed(.from(0xA700)).errorDescription),
                       " ❌ C-STORE response status Failure (0xA700): Refused: Out of resources — not stored (PS3.4 Table B.2-1)\n")
        XCTAssertEqual(NetworkConsole.sendFileResult(status: .from(0xA700), rtt: 0.012),
                       " ❌ C-STORE response status Failure (0xA700): Refused: Out of resources — not stored (PS3.4 Table B.2-1)\n")
        XCTAssertEqual(SendError.partialFailure(succeeded: 2, failed: 1).errorDescription,
                       NetworkConsole.sendPartialFailureText(succeeded: 2, failed: 1))
        XCTAssertEqual(NetworkConsole.sendPartialFailureText(succeeded: 2, failed: 1),
                       "Send completed with 2 succeeded and 1 failed")
    }

    // PS3.7 Table 9.3-1: LOW = 0002H, MEDIUM = 0000H, HIGH = 0001H.
    func testPriorityOptionValuesMatchPS37() {
        XCTAssertEqual(PriorityOption.low.dimseValue.rawValue, 0x0002)
        XCTAssertEqual(PriorityOption.medium.dimseValue.rawValue, 0x0000)
        XCTAssertEqual(PriorityOption.high.dimseValue.rawValue, 0x0001)
        XCTAssertEqual(PriorityOption.allCases.map(\.rawValue), ["low", "medium", "high"])
    }

    func testPriorityHelpCitesTheStandardValues() {
        let help = DICOMSend.helpMessage()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        XCTAssertTrue(help.contains("low (0002H), medium (0000H), high (0001H)"), help)
    }

    // P-SEND-SUMMARY: the Warning class of PS3.4 Table B.2-1 is counted in the
    // SHARED NetworkConsole summary (so the DICOMStudio Workshop renders it too).
    func testSharedSummaryCountsWarnings() {
        let withWarnings = NetworkConsole.sendSummary(total: 3, succeeded: 3, failed: 0, bytes: 10,
                                                      duration: 0.5, warnings: 2)
        XCTAssertTrue(withWarnings.contains("Warnings:          2 (stored; PS3.4 Table B.2-1 Warning class)"), withWarnings)
        let lines = withWarnings.components(separatedBy: "\n")
        let succeeded = lines.firstIndex { $0.contains("Succeeded:") } ?? -1
        let warnings = lines.firstIndex { $0.contains("Warnings:") } ?? -1
        let failed = lines.firstIndex { $0.contains("Failed:") } ?? -1
        XCTAssertTrue(succeeded < warnings && warnings < failed, withWarnings)

        // No warnings: byte-identical to the summary without the parameter.
        XCTAssertEqual(NetworkConsole.sendSummary(total: 1, succeeded: 1, failed: 0, bytes: 10, duration: 0.5, warnings: 0),
                       NetworkConsole.sendSummary(total: 1, succeeded: 1, failed: 0, bytes: 10, duration: 0.5))
        XCTAssertFalse(NetworkConsole.sendSummary(total: 1, succeeded: 1, failed: 0, bytes: 10, duration: 0.5)
            .contains("Warnings:"))
    }

    func testWarningLineUsesTableB21Wording() {
        XCTAssertEqual(NetworkConsole.sendFileWarningLine(status: .from(0xB000)),
                       "    ⚠️ Stored with warning: Warning (0xB000): Coercion of Data Elements\n")
        XCTAssertEqual(NetworkConsole.sendFileWarningLine(status: .from(0xB006)),
                       "    ⚠️ Stored with warning: Warning (0xB006): Elements Discarded\n")
        XCTAssertEqual(NetworkConsole.sendFileWarningLine(status: .from(0xB007)),
                       "    ⚠️ Stored with warning: Warning (0xB007): Data Set does not match SOP Class\n")
    }
}
