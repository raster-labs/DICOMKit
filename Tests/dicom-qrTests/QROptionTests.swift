import XCTest
import DICOMNetwork
@testable import dicom_qr

/// dicom-qr P-items (2026-10-01): `--priority` (PS3.7 2026a Tables 9.3-9 / 9.3-6),
/// `--parallel` implemented (P-QR-PARALLEL), and the state file's
/// `ModalitiesInStudy` key (PS3.6 keyword of (0008,0061), PS3.4 Table C.6-5).
final class QROptionTests: XCTestCase {

    func testPriorityValuesMatchPS37() {
        XCTAssertEqual(QRPriorityOption.low.dimseValue.rawValue, 0x0002)
        XCTAssertEqual(QRPriorityOption.medium.dimseValue.rawValue, 0x0000)
        XCTAssertEqual(QRPriorityOption.high.dimseValue.rawValue, 0x0001)
    }

    func testQueryAndResumeAcceptPriority() throws {
        let query = try DICOMQR.Query.parse(["host", "--aet", "SCU", "--review", "--priority", "low"])
        XCTAssertEqual(query.priority, .low)
        XCTAssertEqual(try DICOMQR.Query.parse(["host", "--aet", "SCU", "--review"]).priority, .medium)
        let resume = try DICOMQR.Resume.parse(["--state", "x.state", "--priority", "high"])
        XCTAssertEqual(resume.priority, .high)
    }

    func testParallelHelpNoLongerSaysCompatibilityOnly() {
        let help = DICOMQR.Query.helpMessage().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        XCTAssertTrue(help.contains("up to N studies are retrieved at once"), help)
    }

    #if canImport(Network)
    func testExecutorConfigurationCarriesPriority() throws {
        let executor = RetrieveExecutor(
            host: "h", port: 104, callingAE: "SCU", calledAE: "PACS", moveDestination: nil, timeout: 5,
            outputPath: ".", hierarchical: false, verbose: false, preferredTransferSyntaxUID: nil, priority: .high)
        let config = try executor.retrieveConfiguration()
        XCTAssertEqual(config.priority, .high)
        XCTAssertNil(config.extendedNegotiation, "STUDY-level retrieve: no relational-retrieval offered")
    }

    /// A study without a Study Instance UID is reported, never retrieved.
    func testRetrieveOutcomeForMissingStudyUID() async {
        let executor = RetrieveExecutor(
            host: "127.0.0.1", port: 1, callingAE: "SCU", calledAE: "PACS", moveDestination: nil, timeout: 1,
            outputPath: ".", hierarchical: false, verbose: false, preferredTransferSyntaxUID: nil)
        let outcome = await DICOMQR.Query.retrieve(GenericQueryResult(attributes: [:], level: .study),
                                                   executor: executor, method: .cGet)
        guard case .missingStudyUID = outcome else { return XCTFail("\(outcome)") }
    }
    #endif

    /// P-QR-STATE-MODALITIES: the PS3.6 keyword key is written next to the old one,
    /// and a state file without it still decodes.
    func testStateWritesModalitiesInStudyKeyword() throws {
        let result = GenericQueryResult(attributes: [
            .studyInstanceUID: Data("1.2.3".utf8),
            .modalitiesInStudy: Data("CT\\PR".utf8),
        ], level: .study)
        let data = try QRSessionState.encode(QRQueryState(results: [result]))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let study = try XCTUnwrap((json["studies"] as? [[String: Any]])?.first)
        XCTAssertEqual(study["ModalitiesInStudy"] as? String, "CT\\PR")
        XCTAssertNil(study["modality"], "no (0008,0060) in the response: old key stays absent as before")

        let old = Data(#"{"studies":[{"studyInstanceUID":"1.2.3","modality":"CT"}]}"#.utf8)
        let decoded = try QRSessionState.decodeQueryState(old)
        XCTAssertEqual(decoded.studies.first?.modality, "CT")
        XCTAssertNil(decoded.studies.first?.modalitiesInStudy)
    }

    // D262: dicom-qr reports a non-success C-MOVE / C-GET final response with the
    // shared NetworkConsole.retrieveFinalResponse, in dicom-retrieve's wording
    // (formerly "Retrieval failed: …" and an indented UID block).
    #if canImport(Network)
    func testRetrievalFailureUsesTheSharedWording() {
        let result = RetrieveResult(status: .from(0xA702), progress: RetrieveProgress(completed: 0, failed: 2),
                                    failedSOPInstanceUIDs: ["1.2.3", "1.2.4"])
        let shared = NetworkConsole.retrieveFinalResponse(result, service: .cGet).failure
        XCTAssertNotNil(shared)
        XCTAssertTrue(shared?.hasPrefix("C-GET final response ") ?? false, shared ?? "")
        XCTAssertThrowsError(try RetrieveExecutor.checkRetrieveResult(result, service: .cGet)) { error in
            XCTAssertEqual(error.localizedDescription, shared)
            XCTAssertFalse(error.localizedDescription.hasPrefix("Retrieval failed: "))
        }
        XCTAssertNoThrow(try RetrieveExecutor.checkRetrieveResult(
            RetrieveResult(status: .success, progress: RetrieveProgress(completed: 1)), service: .cMove))
    }
    #endif
}
