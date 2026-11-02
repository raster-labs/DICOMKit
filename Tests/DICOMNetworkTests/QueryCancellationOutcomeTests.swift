import XCTest
import DICOMCore
@testable import DICOMNetwork

final class QueryCancellationOutcomeTests: XCTestCase {
    func testCancellationRetainsPartialIdentityAndWarnsThatResultsAreIncomplete() {
        let partial = GenericQueryResult(attributes: [.studyInstanceUID: Data("2.25.404".utf8)], level: .study)
        let error = QueryCancelledError(partialResults: [partial])
        XCTAssertEqual(error.partialResults.first?.uid(for: .studyInstanceUID), "2.25.404")
        XCTAssertTrue(error.localizedDescription.contains("FE00"))
        XCTAssertTrue(error.description.contains("1 partial result(s)"))
        XCTAssertTrue(error.description.contains("incomplete"))
        XCTAssertTrue(QueryCancelledError(partialResults: []).description.contains("0 partial result(s)"))
    }

    func testCancelledGetDoesNotReportSuccessOrBlamePresentationContexts() {
        for received in [0, 2] {
            let summary = NetworkConsole.cGetSummary(received: received, status: .cancel)
            XCTAssertTrue(summary.contains("cancelled"))
            XCTAssertTrue(summary.contains("\(received) file(s) received"))
            XCTAssertFalse(summary.contains("completed"))
            XCTAssertFalse(summary.contains("presentation context"))
        }
        XCTAssertEqual(NetworkConsole.cGetSummary(received: 2, status: .success), NetworkConsole.cGetSummary(received: 2))
    }

    func testCancelledLaterGetPassPreservesRemainingAndFailedIdentity() {
        let previous = RetrieveResult(status: .warningCoercionOfDataElements,
            progress: .init(completed: 3, failed: 5, warning: 1))
        let next = RetrieveResult(status: .cancel, progress: .init(remaining: 2, completed: 1, failed: 1, warning: 1),
            failedSOPInstanceUIDs: ["2.25.404.9"])
        let merged = DICOMRetrieveService.mergeGetPassResults(previous: previous, next: next)
        XCTAssertEqual(merged.status, .cancel)
        XCTAssertEqual(merged.progress, .init(remaining: 2, completed: 4, failed: 1, warning: 2))
        XCTAssertEqual(merged.failedSOPInstanceUIDs, ["2.25.404.9"])
        let output = NetworkConsole.retrieveFinalResponse(merged, service: .cGet)
        XCTAssertTrue(output.failure?.contains("Number of Remaining Sub-operations: 2") == true)
    }
}
