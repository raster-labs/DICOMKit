import XCTest
import DICOMNetwork
@testable import dicom_retrieve

/// P-RETRIEVE-PRIORITY / P-RETRIEVE-EXTNEG (2026-10-01): `--priority` maps to the
/// Priority (0000,0700) values of PS3.7 2026a Tables 9.3-9 (C-MOVE-RQ) / 9.3-6
/// (C-GET-RQ); `--relational-retrieve` proposes relational-retrieval (PS3.4 2026a
/// C.5.2.1 / C.5.3.1, Table C.5-3 byte 1) and relaxes the above-level UIDs
/// (PS3.4 C.4.2.2.2.1 / C.4.3.2.2.1).
final class RetrieveOptionTests: XCTestCase {

    func testPriorityValuesMatchPS37() {
        XCTAssertEqual(RetrievePriorityOption.low.dimseValue.rawValue, 0x0002)
        XCTAssertEqual(RetrievePriorityOption.medium.dimseValue.rawValue, 0x0000)
        XCTAssertEqual(RetrievePriorityOption.high.dimseValue.rawValue, 0x0001)
        XCTAssertEqual(RetrievePriorityOption.allCases.map(\.rawValue), ["low", "medium", "high"])
    }

    func testPriorityDefaultsToMediumAndParses() throws {
        let base = ["host", "--aet", "SCU", "--study-uid", "1.2", "--method", "c-get"]
        XCTAssertEqual(try DICOMRetrieve.parse(base).priority, .medium)
        XCTAssertEqual(try DICOMRetrieve.parse(base + ["--priority", "high"]).priority, .high)
        XCTAssertThrowsError(try DICOMRetrieve.parse(base + ["--priority", "urgent"]))
    }

    func testHelpCitesTheStandardValues() {
        let help = DICOMRetrieve.helpMessage().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        XCTAssertTrue(help.contains("low (0002H), medium (0000H), high (0001H)"), help)
        XCTAssertTrue(help.contains("Table C.5-3 byte 1"), help)
    }

    func testBaselineStillNeedsAboveLevelUIDs() throws {
        let series = try DICOMRetrieve.parse(["host", "--aet", "SCU", "--series-uid", "1.2.3", "--method", "c-get"])
        XCTAssertThrowsError(try series.validateUIDOptions())
        let instance = try DICOMRetrieve.parse(["host", "--aet", "SCU", "--study-uid", "1.2",
                                                "--instance-uid", "1.2.3.4", "--method", "c-get"])
        XCTAssertThrowsError(try instance.validateUIDOptions())
    }

    func testRelationalRetrieveAcceptsTheLevelUIDAlone() throws {
        for args in [["--series-uid", "1.2.3"], ["--instance-uid", "1.2.3.4"], ["--study-uid", "1.2"]] {
            let cmd = try DICOMRetrieve.parse(["host", "--aet", "SCU", "--relational-retrieve", "--method", "c-get"] + args)
            XCTAssertNoThrow(try cmd.validateUIDOptions(), "\(args)")
        }
        let none = try DICOMRetrieve.parse(["host", "--aet", "SCU", "--relational-retrieve", "--method", "c-get"])
        XCTAssertThrowsError(try none.validateUIDOptions())
    }

    #if canImport(Network)
    /// The Identifier carries the level of the most specific UID and only the UIDs given.
    func testRetrieveKeysFromGivenUIDs() {
        let series = RetrieveExecutor.retrieveKeys(studyUID: nil, seriesUID: "1.2.3", sopUID: nil)
        XCTAssertEqual(series.level, .series)
        XCTAssertEqual(series.keys.map(\.tag), [.seriesInstanceUID])
        XCTAssertEqual(series.keys.map(\.value), ["1.2.3"])
        let image = RetrieveExecutor.retrieveKeys(studyUID: "1.2", seriesUID: "1.2.3", sopUID: "1.2.3.4")
        XCTAssertEqual(image.level, .image)
        XCTAssertEqual(Set(image.keys.map(\.tag)), [.studyInstanceUID, .seriesInstanceUID, .sopInstanceUID])
    }

    func testExecutorConfigurationCarriesPriorityAndNegotiation() throws {
        let executor = RetrieveExecutor(
            host: "h", port: 104, callingAE: "SCU", calledAE: "PACS", moveDestination: nil, timeout: 5,
            outputPath: ".", hierarchical: false, verbose: false, preferredTransferSyntaxUID: nil,
            priority: .low, relationalRetrieval: true)
        let config = try executor.retrieveConfiguration()
        XCTAssertEqual(config.priority, .low)
        XCTAssertEqual(config.extendedNegotiation, RetrieveExtendedNegotiation(relationalRetrieval: true))
        let baseline = RetrieveExecutor(
            host: "h", port: 104, callingAE: "SCU", calledAE: "PACS", moveDestination: nil, timeout: 5,
            outputPath: ".", hierarchical: false, verbose: false, preferredTransferSyntaxUID: nil)
        XCTAssertEqual(try baseline.retrieveConfiguration().priority, .medium)
        XCTAssertNil(try baseline.retrieveConfiguration().extendedNegotiation)
    }
    #endif

    /// The shared header shows Priority and the negotiation only when set.
    func testHeaderShowsPriorityOnlyWhenNotDefault() {
        func header(_ priority: DIMSEPriority?, _ relational: Bool) -> String {
            NetworkConsole.retrieveHeader(
                method: "C-MOVE", host: "h", port: 104, callingAE: "SCU", calledAE: "PACS",
                moveDestination: "DEST", level: "Study", studyUID: "1.2", seriesUID: nil, instanceUID: nil,
                output: ".", hierarchical: false, timeout: 60, transferSyntax: nil,
                priority: priority, relationalRetrieval: relational)
        }
        XCTAssertFalse(header(nil, false).contains("Priority:"))
        XCTAssertTrue(header(.high, false).contains("Priority:          HIGH (0001H)"), header(.high, false))
        XCTAssertTrue(header(nil, true).contains("relational-retrieval (PS3.4 C.5.2.1)"))
    }

    // D262: the non-success final response is DICOMNetwork's shared report, in this
    // tool's (canonical) wording — PS3.4 2026a Tables C.4-2 / C.4-3 status text, PS3.7
    // Table 9.3-10 counter names, Failed SOP Instance UID List (0008,0058).
    #if canImport(Network)
    func testFinalResponseWordingIsTheSharedReport() throws {
        let progress = RetrieveProgress(completed: 2, failed: 1, warning: 0)
        let result = RetrieveResult(status: .from(0xB000), progress: progress, failedSOPInstanceUIDs: ["1.2.3"])
        let report = NetworkConsole.retrieveFinalResponse(result, service: .cMove)
        let described = DIMSEServiceStatusText.describe(.from(0xB000), service: .cMove)
        let counts = "Number of Completed Sub-operations: 2, Number of Failed Sub-operations: 1, Number of Warning Sub-operations: 0"
        XCTAssertEqual(report.lines, ["Failed SOP Instance UID List (0008,0058), 1 UID(s):", "  1.2.3",
                                      "Final C-MOVE response: " + described + " — " + counts])
        let expected = "C-MOVE final response " + described + " (" + counts + "); Failed SOP Instance UID List (0008,0058): 1.2.3"
        XCTAssertEqual(report.failure, expected)
        XCTAssertEqual(RetrieveError.retrievalFailed(service: .cMove, status: .from(0xB000), progress: progress,
                                                     failedSOPInstanceUIDs: ["1.2.3"]).description, expected)
        XCTAssertThrowsError(try RetrieveExecutor.checkResult(result, service: .cMove))
        let ok = RetrieveResult(status: .success, progress: RetrieveProgress(completed: 3))
        XCTAssertNil(NetworkConsole.retrieveFinalResponse(ok, service: .cGet).failure)
        XCTAssertEqual(NetworkConsole.retrieveFinalResponse(ok, service: .cGet).lines, [])
        XCTAssertNoThrow(try RetrieveExecutor.checkResult(ok, service: .cGet))
    }
    #endif
}
