import XCTest
import DICOMCore
@testable import DICOMNetwork

/// NET-08-A: independent literal byte expectations follow PS3.4 2026a
/// Table F.7.2-1 and F.7.2.2.1/.2. No production encoder builds expected bytes.
final class MPPSIntermediateUpdateTests: XCTestCase {
    private let explicitLE = "1.2.840.10008.1.2.1"
    private let implicitLE = "1.2.840.10008.1.2"

    func testStatusOmittedSendsOnlyRequestedDescription() throws {
        let step = MPPSProcedureStep(sopInstanceUID: "2.25.801", status: .inProgress,
            procedureStepDescription: "Updated", includeStatus: false)
        try DICOMMPPSService.validate(step, for: .nSet)
        // (0040,0254) LO length 8; neither status, end values nor empty sequences.
        XCTAssertEqual(DICOMMPPSService.buildNSetAttributes(procedureStep: step, includeScheduledStepAttributes: false, transferSyntax: explicitLE),
                       Data([0x40, 0, 0x54, 2, 0x4c, 0x4f, 8, 0] + Array("Updated ".utf8)))
        XCTAssertEqual(DICOMMPPSService.buildNSetAttributes(procedureStep: step, includeScheduledStepAttributes: false, transferSyntax: implicitLE),
                       Data([0x40, 0, 0x54, 2, 8, 0, 0, 0] + Array("Updated ".utf8)))
    }

    func testExplicitInProgressHasStatusAndNoEndValues() throws {
        let step = MPPSProcedureStep(sopInstanceUID: "2.25.802", status: .inProgress)
        try DICOMMPPSService.validate(step, for: .nSet)
        XCTAssertEqual(DICOMMPPSService.buildNSetAttributes(procedureStep: step, includeScheduledStepAttributes: false, transferSyntax: explicitLE),
                       Data([0x40, 0, 0x52, 2, 0x43, 0x53, 12, 0] + Array("IN PROGRESS ".utf8)))
    }

    func testEmptyDescriptionIsAnExplicitClearNotOmission() throws {
        let step = MPPSProcedureStep(sopInstanceUID: "2.25.803", status: .inProgress,
            procedureStepDescription: "", includeStatus: false)
        try DICOMMPPSService.validate(step, for: .nSet)
        XCTAssertEqual(DICOMMPPSService.buildNSetAttributes(procedureStep: step, includeScheduledStepAttributes: false, transferSyntax: explicitLE),
                       Data([0x40, 0, 0x54, 2, 0x4c, 0x4f, 0, 0]))
    }

    func testDescriptionRejectsInvalidLengthMultiplicityAndControls() {
        for value in [String(repeating: "A", count: 65), "One\\Two", "Line\nBreak"] {
            let step = MPPSProcedureStep(sopInstanceUID: "2.25.812", status: .inProgress,
                procedureStepDescription: value, includeStatus: false)
            XCTAssertThrowsError(try DICOMMPPSService.validate(step, for: .nSet))
        }
        let boundary = MPPSProcedureStep(sopInstanceUID: "2.25.812", status: .inProgress,
            procedureStepDescription: String(repeating: "é", count: 64), includeStatus: false)
        XCTAssertNoThrow(try DICOMMPPSService.validate(boundary, for: .nSet), "LO limit counts characters, not UTF-8 bytes")
    }

    func testIntermediateRejectsRawBypassesAndEmptyModificationList() {
        let endTag = Tag(group: 0x0040, element: 0x0250)
        let patientTag = Tag(group: 0x0010, element: 0x0010)
        for tag in [endTag, patientTag] {
            let step = MPPSProcedureStep(sopInstanceUID: "2.25.804", status: .inProgress,
                attributes: [tag: Data("BAD ".utf8)])
            XCTAssertThrowsError(try DICOMMPPSService.validate(step, for: .nSet))
        }
        XCTAssertThrowsError(try DICOMMPPSService.validate(
            MPPSProcedureStep(sopInstanceUID: "2.25.804", status: .inProgress, includeStatus: false), for: .nSet))
    }

    func testBothFinalStatesRequireStatusEndAndSeriesButMayHaveNoInstances() throws {
        for status in [MPPSStatus.completed, .discontinued] {
            XCTAssertThrowsError(try DICOMMPPSService.validate(
                MPPSProcedureStep(sopInstanceUID: "2.25.805", status: status, endDateTime: Date()), for: .nSet))
            let series = [MPPSPerformedSeries(seriesInstanceUID: "2.25.806", protocolName: "No acquisition")]
            XCTAssertThrowsError(try DICOMMPPSService.validate(
                MPPSProcedureStep(sopInstanceUID: "2.25.805", status: status, performedSeries: series), for: .nSet))
            XCTAssertThrowsError(try DICOMMPPSService.validate(
                MPPSProcedureStep(sopInstanceUID: "2.25.805", status: status, endDateTime: Date(),
                                  performedSeries: series, includeStatus: false), for: .nSet))
            try DICOMMPPSService.validate(MPPSProcedureStep(sopInstanceUID: "2.25.805", status: status,
                endDateTime: Date(), performedSeries: series), for: .nSet)
        }
    }

    func testFixedCharacterSetNeverSilentlyChangesOrReplacesText() throws {
        let latin = MPPSProcedureStep(sopInstanceUID: "2.25.807", status: .inProgress,
            procedureStepDescription: "Café", specificCharacterSet: "ISO_IR 100", includeStatus: false)
        let charset = DICOMMPPSService.chooseCharacterSet(for: latin, override: nil)
        try DICOMMPPSService.validateCharacterSet(latin, characterSet: charset)
        let expected = Data([8, 0, 5, 0, 0x43, 0x53, 10, 0] + Array("ISO_IR 100".utf8)
                            + [0x40, 0, 0x54, 2, 0x4c, 0x4f, 4, 0, 0x43, 0x61, 0x66, 0xe9])
        XCTAssertEqual(DICOMMPPSService.buildNSetAttributes(procedureStep: latin, includeScheduledStepAttributes: false, transferSyntax: explicitLE), expected)
        XCTAssertThrowsError(try DICOMMPPSService.validateCharacterSet(latin,
            characterSet: DIMSECharacterSet(specificCharacterSet: nil)))
        let japanese = MPPSProcedureStep(sopInstanceUID: "2.25.807", status: .inProgress,
            procedureStepDescription: "検査")
        XCTAssertThrowsError(try DICOMMPPSService.validateCharacterSet(japanese, characterSet: charset))
        XCTAssertThrowsError(try DICOMMPPSService.validateCharacterSet(latin,
            characterSet: DIMSECharacterSet(specificCharacterSet: "NOT_A_CHARSET")))
    }

    #if canImport(Network)
    func testCreatedContextRetainsCharsetAndBlocksAnyUpdateAfterTerminalSend() async throws {
        let peer = MockPrintSCP()
        try await peer.start()
        defer { Task { await peer.stop() } }
        let port = await peer.port
        let created = try await DICOMMPPSService.createDetailed(host: "127.0.0.1", port: port,
            callingAE: "NET08", calledAE: "PEER", studyInstanceUID: "2.25.808", timeout: 5,
            patientName: "Émile^Test", modality: "CT", specificCharacterSet: "ISO_IR 100")
        _ = try await DICOMMPPSService.update(host: "127.0.0.1", port: port,
            callingAE: "NET08", calledAE: "PEER", mppsInstanceUID: created.sopInstanceUID,
            status: .inProgress, timeout: 5, procedureStepDescription: "Updated", includeStatus: false)
        let payloads = await peer.receivedDataSets
        let update = try XCTUnwrap(payloads.last)
        XCTAssertNotNil(update.range(of: Data("ISO_IR 100".utf8)), "ASCII updates retain the N-CREATE repertoire")
        for declaration in ["ISO_IR 192", ""] {
            do {
                _ = try await DICOMMPPSService.update(host: "127.0.0.1", port: port,
                    callingAE: "NET08", calledAE: "PEER", mppsInstanceUID: created.sopInstanceUID,
                    status: .inProgress, timeout: 5, specificCharacterSet: declaration,
                    procedureStepDescription: "Updated")
                XCTFail("Character-set change must refuse before connecting")
            } catch DICOMNetworkError.invalidState { }
        }
        _ = try await DICOMMPPSService.update(host: "127.0.0.1", port: port,
            callingAE: "NET08", calledAE: "PEER", mppsInstanceUID: created.sopInstanceUID,
            status: .completed, timeout: 5,
            performedSeries: [MPPSPerformedSeries(seriesInstanceUID: "2.25.809", protocolName: "No acquisition")])
        do {
            _ = try await DICOMMPPSService.update(host: "127.0.0.1", port: port,
                callingAE: "NET08", calledAE: "PEER", mppsInstanceUID: created.sopInstanceUID,
                status: .inProgress, timeout: 5)
            XCTFail("Later update must refuse locally")
        } catch DICOMNetworkError.invalidState { }
        let count = await peer.associationCount
        XCTAssertEqual(count, 3, "Only create, intermediate and terminal requests reached the peer")
    }

    func testFailedFirstIntermediateDoesNotPinAssumedCharacterSet() async {
        // Closed loopback endpoint: neither attempt reaches an SCP. A failed
        // attempt cannot establish this external instance's original charset.
        for declaration in ["", "ISO_IR 192"] {
            do {
                _ = try await DICOMMPPSService.update(host: "127.0.0.1", port: 1,
                    callingAE: "NET08", calledAE: "RETRY", mppsInstanceUID: "2.25.811",
                    status: .inProgress, timeout: 1, specificCharacterSet: declaration,
                    procedureStepDescription: "Updated")
                XCTFail("The deliberately closed endpoint should refuse connection")
            } catch DICOMNetworkError.invalidState(let message) {
                XCTFail("An unsuccessful first attempt must not pin its assumed charset: \(message)")
            } catch { /* Transport failure is expected for both declarations. */ }
        }
    }

    func testExternallyCreatedNonDefaultInstanceNeedsOriginalCharset() async {
        do {
            _ = try await DICOMMPPSService.update(host: "127.0.0.1", port: 1,
                callingAE: "NET08", calledAE: "PEER", mppsInstanceUID: "2.25.810",
                status: .inProgress, timeout: 1, procedureStepDescription: "Café")
            XCTFail("Unknown original charset defaults to ASCII and must reject non-ASCII before networking")
        } catch DICOMNetworkError.invalidState(let message) {
            XCTAssertTrue(message.contains("original Specific Character Set"))
        } catch { XCTFail("Unexpected error: \(error)") }
    }
    #endif
}
