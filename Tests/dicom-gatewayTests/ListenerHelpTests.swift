import XCTest
@testable import dicom_gateway

/// D103: the listen/forward help must not claim a PS3.8 DICOM listener or a C-STORE forward
/// that the tool does not implement.
final class ListenerHelpTests: XCTestCase {
    func testForwardHelpSaysDICOMListenerIsNotImplemented() {
        let help = ForwardCommand.helpMessage().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        XCTAssertTrue(help.contains("not implemented"), help)
        XCTAssertTrue(help.contains("PS3.8"), help)
        XCTAssertFalse(help.contains("Run a DICOM listener that receives DICOM files"), help)
    }

    func testListenHelpSaysPACSForwardIsNotImplemented() {
        let help = ListenCommand.helpMessage().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        XCTAssertTrue(help.contains("Not implemented: forwarding to a PACS"), help)
        XCTAssertFalse(help.contains("forwards to a PACS server"), help)
    }
}
