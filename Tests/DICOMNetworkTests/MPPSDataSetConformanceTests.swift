import XCTest
import DICOMCore
@testable import DICOMNetwork

/// MPPS N-CREATE / N-SET data sets against PS3.4 Table F.7.2-1
/// (DICOM_TAG_AUDIT_PHASE2_FINDINGS.md §2). The data sets are inspected at the
/// byte level: a tag is "present" when its little-endian (group, element) pair
/// occurs in the encoded stream.
final class MPPSDataSetConformanceTests: XCTestCase {

    private let explicitLE = "1.2.840.10008.1.2.1"

    private func bytes(_ g: UInt16, _ e: UInt16) -> [UInt8] {
        [UInt8(g & 0xFF), UInt8(g >> 8), UInt8(e & 0xFF), UInt8(e >> 8)]
    }

    private func contains(_ data: Data, _ g: UInt16, _ e: UInt16) -> Bool {
        data.range(of: Data(bytes(g, e))) != nil
    }

    private func occurrences(_ data: Data, _ g: UInt16, _ e: UInt16) -> Int {
        let needle = Data(bytes(g, e))
        var count = 0
        var searchRange = data.startIndex..<data.endIndex
        while let r = data.range(of: needle, in: searchRange) {
            count += 1
            searchRange = r.upperBound..<data.endIndex
        }
        return count
    }

    /// The bytes that follow a tag's explicit-VR header, as ASCII.
    private func asciiValue(_ data: Data, _ g: UInt16, _ e: UInt16) -> String? {
        guard let r = data.range(of: Data(bytes(g, e))) else { return nil }
        let vrStart = r.upperBound
        guard vrStart + 4 <= data.count else { return nil }
        let vr = String(bytes: data[vrStart..<vrStart + 2], encoding: .ascii) ?? ""
        let uses4 = ["OB", "OD", "OF", "OL", "OW", "SQ", "UC", "UN", "UR", "UT"].contains(vr)
        let lengthStart = vrStart + (uses4 ? 4 : 2)
        let length: Int
        if uses4 {
            length = Int(data[lengthStart]) | Int(data[lengthStart + 1]) << 8
                | Int(data[lengthStart + 2]) << 16 | Int(data[lengthStart + 3]) << 24
            return String(bytes: data[(lengthStart + 4)..<(lengthStart + 4 + length)], encoding: .ascii)
        }
        length = Int(data[lengthStart]) | Int(data[lengthStart + 1]) << 8
        return String(bytes: data[(lengthStart + 2)..<(lengthStart + 2 + length)], encoding: .ascii)
    }

    private func inProgressStep() -> MPPSProcedureStep {
        MPPSProcedureStep(
            sopInstanceUID: "1.2.3.4",
            status: .inProgress,
            studyInstanceUID: "1.2.3",
            startDateTime: Date(),
            patientName: "DOE^JOHN",
            patientID: "P1",
            modality: "CT",
            procedureStepID: "PPS1",
            performedStationAETitle: "CT1",
            performingPhysicianName: "SMITH^A",
            accessionNumber: "ACC1",
            scheduledProcedureStepID: "SPS1",
            requestedProcedureID: "RP1")
    }

    // MARK: - N-CREATE

    func test_nCreate_carriesEveryType1And2AttributeOfF72_1() {
        let data = DICOMMPPSService.buildMPPSAttributes(procedureStep: inProgressStep(), transferSyntax: explicitLE)

        // Relationship module
        for (g, e) in [(0x0008, 0x1120), (0x0010, 0x0010), (0x0010, 0x0020), (0x0010, 0x0030), (0x0010, 0x0040),
                       (0x0040, 0x0270)] as [(UInt16, UInt16)] {
            XCTAssertTrue(contains(data, g, e), "missing (\(String(format: "%04X,%04X", g, e)))")
        }
        // Scheduled Step Attributes items
        for (g, e) in [(0x0008, 0x0050), (0x0008, 0x1110), (0x0020, 0x000D), (0x0032, 0x1060),
                       (0x0040, 0x0007), (0x0040, 0x0008), (0x0040, 0x0009), (0x0040, 0x1001)] as [(UInt16, UInt16)] {
            XCTAssertTrue(contains(data, g, e), "missing nested (\(String(format: "%04X,%04X", g, e)))")
        }
        // Information module
        for (g, e) in [(0x0040, 0x0241), (0x0040, 0x0242), (0x0040, 0x0243), (0x0040, 0x0244), (0x0040, 0x0245),
                       (0x0040, 0x0250), (0x0040, 0x0251), (0x0040, 0x0252), (0x0040, 0x0253), (0x0040, 0x0254),
                       (0x0040, 0x0255), (0x0008, 0x1032)] as [(UInt16, UInt16)] {
            XCTAssertTrue(contains(data, g, e), "missing (\(String(format: "%04X,%04X", g, e)))")
        }
        // Image Acquisition Results module
        for (g, e) in [(0x0008, 0x0060), (0x0020, 0x0010), (0x0040, 0x0260), (0x0040, 0x0340)] as [(UInt16, UInt16)] {
            XCTAssertTrue(contains(data, g, e), "missing (\(String(format: "%04X,%04X", g, e)))")
        }
    }

    func test_nCreate_doesNotCarryAttributesTheTableDoesNotAllowAtRoot() {
        let data = DICOMMPPSService.buildMPPSAttributes(procedureStep: inProgressStep(), transferSyntax: explicitLE)
        // Performing Physician's Name lives only in Performed Series items; with no
        // series yet, it must not appear at all. Study Instance UID lives only
        // inside Scheduled Step Attributes.
        XCTAssertEqual(occurrences(data, 0x0008, 0x1050), 0, "Performing Physician's Name at root")
        XCTAssertEqual(occurrences(data, 0x0020, 0x000D), 1, "Study Instance UID only inside (0040,0270)")
    }

    func test_nCreate_requestedProcedureIDIsNotThePerformedStepID() {
        let data = DICOMMPPSService.buildMPPSAttributes(procedureStep: inProgressStep(), transferSyntax: explicitLE)
        XCTAssertEqual(asciiValue(data, 0x0040, 0x1001)?.trimmingCharacters(in: .whitespaces), "RP1")
        XCTAssertEqual(asciiValue(data, 0x0040, 0x0253)?.trimmingCharacters(in: .whitespaces), "PPS1")
    }

    func test_nCreate_extraAttributesAreWritten() {
        let step = MPPSProcedureStep(
            sopInstanceUID: "1", status: .inProgress,
            attributes: [Tag(group: 0x0040, element: 0x0280): Data("Comment".utf8)])   // Comments on the PPS
        let data = DICOMMPPSService.buildMPPSAttributes(procedureStep: step, transferSyntax: explicitLE)
        XCTAssertTrue(contains(data, 0x0040, 0x0280))
        XCTAssertEqual(asciiValue(data, 0x0040, 0x0280)?.trimmingCharacters(in: .whitespaces), "Comment")
    }

    // MARK: - N-SET

    func test_nSet_omitsScheduledStepAttributesByDefault() {
        let step = MPPSProcedureStep(
            sopInstanceUID: "1", status: .completed, studyInstanceUID: "1.2.3",
            referencedSOPs: [("1.2.3", "1.2.3.4", "1.2.3.4.5")],
            referencedSOPClassUID: "1.2.840.10008.5.1.4.1.1.2", protocolName: "Chest CT")
        let data = DICOMMPPSService.buildNSetAttributes(
            procedureStep: step, includeScheduledStepAttributes: false, transferSyntax: explicitLE)
        XCTAssertFalse(contains(data, 0x0040, 0x0270), "Scheduled Step Attributes Sequence is Not allowed in N-SET")
        XCTAssertTrue(contains(data, 0x0040, 0x0252))
        XCTAssertTrue(contains(data, 0x0040, 0x0340))

        let legacy = DICOMMPPSService.buildNSetAttributes(
            procedureStep: step, includeScheduledStepAttributes: true, transferSyntax: explicitLE)
        XCTAssertTrue(contains(legacy, 0x0040, 0x0270), "opt-in flag restores the legacy behaviour")
    }

    func test_performedSeries_carriesRealSOPClassAndType1ProtocolName() {
        let step = MPPSProcedureStep(
            sopInstanceUID: "1", status: .completed,
            referencedSOPs: [("1.2.3", "1.2.3.4", "1.2.3.4.5"), ("1.2.3", "1.2.3.4", "1.2.3.4.6")],
            referencedSOPClassUID: "1.2.840.10008.5.1.4.1.1.2", protocolName: "Chest CT")
        let data = DICOMMPPSService.buildNSetAttributes(
            procedureStep: step, includeScheduledStepAttributes: false, transferSyntax: explicitLE)

        XCTAssertEqual(asciiValue(data, 0x0008, 0x1150)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0")),
                       "1.2.840.10008.5.1.4.1.1.2", "Referenced SOP Class UID must be the images' class, not SC")
        XCTAssertFalse(data.range(of: Data("1.2.840.10008.5.1.4.1.1.7".utf8)) != nil, "no Secondary Capture placeholder")
        XCTAssertEqual(asciiValue(data, 0x0018, 0x1030)?.trimmingCharacters(in: .whitespaces), "Chest CT")
        // Type 2 series attributes present (empty)
        for (g, e) in [(0x0008, 0x0054), (0x0008, 0x1070), (0x0008, 0x103E), (0x0040, 0x0220)] as [(UInt16, UInt16)] {
            XCTAssertTrue(contains(data, g, e), "missing series-level (\(String(format: "%04X,%04X", g, e)))")
        }
        XCTAssertEqual(occurrences(data, 0x0008, 0x1155), 2)
    }

    func test_performedSeries_legacyTupleWithoutClassFallsBackToSecondaryCapture() {
        let step = MPPSProcedureStep(
            sopInstanceUID: "1", status: .completed,
            referencedSOPs: [("1.2.3", "1.2.3.4", "1.2.3.4.5")])
        let series = step.effectivePerformedSeries
        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series.first?.referencedImages.first?.sopClassUID, MPPSProcedureStep.legacyReferencedSOPClassUID)
        XCTAssertEqual(series.first?.protocolName, "UNSPECIFIED", "Type 1 Protocol Name is never empty")
    }

    func test_explicitPerformedSeriesTakesPrecedence() {
        let step = MPPSProcedureStep(
            sopInstanceUID: "1", status: .completed,
            referencedSOPs: [("1.2.3", "ignored", "ignored")],
            performedSeries: [MPPSPerformedSeries(
                seriesInstanceUID: "9.9", protocolName: "Brain MR", operatorsName: "TECH^A",
                referencedImages: [MPPSReferencedInstance(sopClassUID: "1.2.840.10008.5.1.4.1.1.4", sopInstanceUID: "9.9.1")])])
        let data = DICOMMPPSService.buildNSetAttributes(
            procedureStep: step, includeScheduledStepAttributes: false, transferSyntax: explicitLE)
        XCTAssertEqual(asciiValue(data, 0x0020, 0x000E)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0")), "9.9")
        XCTAssertEqual(asciiValue(data, 0x0008, 0x1070)?.trimmingCharacters(in: .whitespaces), "TECH^A")
        XCTAssertNil(data.range(of: Data("ignored".utf8)))
    }

    // MARK: - Character set (PS3.5 6.1.2, PS3.4 Annex F)

    /// The raw value bytes that follow a tag's explicit-VR header.
    private func rawValue(_ data: Data, _ g: UInt16, _ e: UInt16) -> Data? {
        guard let r = data.range(of: Data(bytes(g, e))) else { return nil }
        let vrStart = r.upperBound
        guard vrStart + 4 <= data.count else { return nil }
        let vr = String(bytes: data[vrStart..<vrStart + 2], encoding: .ascii) ?? ""
        let uses4 = ["OB", "OD", "OF", "OL", "OW", "SQ", "UC", "UN", "UR", "UT"].contains(vr)
        let lengthStart = vrStart + (uses4 ? 4 : 2)
        if uses4 {
            let length = Int(data[lengthStart]) | Int(data[lengthStart + 1]) << 8
                | Int(data[lengthStart + 2]) << 16 | Int(data[lengthStart + 3]) << 24
            return Data(data[(lengthStart + 4)..<(lengthStart + 4 + length)])
        }
        let length = Int(data[lengthStart]) | Int(data[lengthStart + 1]) << 8
        return Data(data[(lengthStart + 2)..<(lengthStart + 2 + length)])
    }

    private func latin1Step(specificCharacterSet: String? = nil) -> MPPSProcedureStep {
        MPPSProcedureStep(
            sopInstanceUID: "1.2.3.4", status: .inProgress, studyInstanceUID: "1.2.3",
            startDateTime: Date(), patientName: "MÜLLER^JÖRG", patientID: "P1", modality: "CT",
            procedureStepID: "PPS1", performedStationAETitle: "CT1",
            specificCharacterSet: specificCharacterSet)
    }

    func test_nCreate_latin1PatientNameDeclaresISO_IR_100AndKeepsEveryByte() {
        let data = DICOMMPPSService.buildMPPSAttributes(procedureStep: latin1Step(), transferSyntax: explicitLE)
        XCTAssertEqual(asciiValue(data, 0x0008, 0x0005)?.trimmingCharacters(in: .whitespaces), "ISO_IR 100")
        let expected = "MÜLLER^JÖRG".data(using: .isoLatin1)! + Data([0x20])   // 11 bytes, space-padded to 12
        XCTAssertEqual(rawValue(data, 0x0010, 0x0010), expected,
                       "Patient's Name must be the full Latin-1 value, never a zero-length ASCII failure")
    }

    func test_nCreate_pureASCIIDoesNotForceASpecificCharacterSet() {
        let data = DICOMMPPSService.buildMPPSAttributes(procedureStep: inProgressStep(), transferSyntax: explicitLE)
        XCTAssertFalse(contains(data, 0x0008, 0x0005), "(0008,0005) is 1C: omitted when every value is ISO 646")
        XCTAssertEqual(asciiValue(data, 0x0010, 0x0010)?.trimmingCharacters(in: .whitespaces), "DOE^JOHN")
    }

    func test_nCreate_nonLatin1ValueChoosesUTF8() {
        let step = MPPSProcedureStep(
            sopInstanceUID: "1", status: .inProgress, patientName: "山田^太郎", modality: "CT")
        let data = DICOMMPPSService.buildMPPSAttributes(procedureStep: step, transferSyntax: explicitLE)
        XCTAssertEqual(asciiValue(data, 0x0008, 0x0005)?.trimmingCharacters(in: .whitespaces), "ISO_IR 192")
        // 13 UTF-8 bytes, space-padded to 14 (PS3.5 §6.2)
        XCTAssertEqual(rawValue(data, 0x0010, 0x0010), Data("山田^太郎".utf8) + Data([0x20]))
    }

    func test_nCreate_nestedTextValuesDriveTheCharacterSet() {
        // Only the Scheduled Step Attributes item carries a non-ASCII value.
        let step = MPPSProcedureStep(
            sopInstanceUID: "1", status: .inProgress, patientName: "DOE^JOHN", modality: "CT",
            requestedProcedureDescription: "Thorax – Übersicht")
        let data = DICOMMPPSService.buildMPPSAttributes(procedureStep: step, transferSyntax: explicitLE)
        XCTAssertEqual(asciiValue(data, 0x0008, 0x0005)?.trimmingCharacters(in: .whitespaces), "ISO_IR 192",
                       "an en dash is outside Latin-1, so nested values must widen the choice to UTF-8")
        // 21 UTF-8 bytes, space-padded to 22 (PS3.5 §6.2)
        XCTAssertEqual(rawValue(data, 0x0032, 0x1060), Data("Thorax – Übersicht".utf8) + Data([0x20]))
    }

    func test_nCreate_overrideForcesTheDeclaredCharacterSet() {
        let viaStep = DICOMMPPSService.buildMPPSAttributes(
            procedureStep: latin1Step(specificCharacterSet: "ISO_IR 192"), transferSyntax: explicitLE)
        XCTAssertEqual(asciiValue(viaStep, 0x0008, 0x0005)?.trimmingCharacters(in: .whitespaces), "ISO_IR 192")
        XCTAssertEqual(rawValue(viaStep, 0x0010, 0x0010), Data("MÜLLER^JÖRG".utf8) + Data([0x20]))

        let viaConfig = DICOMMPPSService.buildMPPSAttributes(
            procedureStep: latin1Step(), transferSyntax: explicitLE, specificCharacterSet: "ISO_IR 192")
        XCTAssertEqual(asciiValue(viaConfig, 0x0008, 0x0005)?.trimmingCharacters(in: .whitespaces), "ISO_IR 192")
    }

    func test_nSet_latin1OperatorsNameDeclaresCharacterSet() {
        let step = MPPSProcedureStep(
            sopInstanceUID: "1", status: .completed, endDateTime: Date(),
            performedSeries: [MPPSPerformedSeries(seriesInstanceUID: "9.9", protocolName: "Brain MR", operatorsName: "MÜLLER^A")])
        let data = DICOMMPPSService.buildNSetAttributes(
            procedureStep: step, includeScheduledStepAttributes: false, transferSyntax: explicitLE)
        XCTAssertEqual(asciiValue(data, 0x0008, 0x0005)?.trimmingCharacters(in: .whitespaces), "ISO_IR 100")
        XCTAssertEqual(rawValue(data, 0x0008, 0x1070), "MÜLLER^A".data(using: .isoLatin1)!)
    }

    // MARK: - Discontinuation Reason Code Sequence (0040,0281)

    private let reason = MPPSCodedEntry(codeValue: "110513", codingSchemeDesignator: "DCM",
                                        codeMeaning: "Doctor cancelled procedure")

    func test_nSet_discontinuedCarriesDiscontinuationReasonCodeSequence() {
        let step = MPPSProcedureStep(
            sopInstanceUID: "1", status: .discontinued, endDateTime: Date(), discontinuationReason: reason)
        let data = DICOMMPPSService.buildNSetAttributes(
            procedureStep: step, includeScheduledStepAttributes: false, transferSyntax: explicitLE)
        XCTAssertTrue(contains(data, 0x0040, 0x0281))
        guard let r = data.range(of: Data(bytes(0x0040, 0x0281))) else { return XCTFail("no (0040,0281)") }
        let after = Data(data[r.upperBound...])
        XCTAssertEqual(asciiValue(after, 0x0008, 0x0100)?.trimmingCharacters(in: .whitespaces), "110513")
        XCTAssertEqual(asciiValue(after, 0x0008, 0x0102)?.trimmingCharacters(in: .whitespaces), "DCM")
        XCTAssertEqual(asciiValue(after, 0x0008, 0x0104)?.trimmingCharacters(in: .whitespaces), "Doctor cancelled procedure")
        XCTAssertEqual(occurrences(data, 0x0040, 0x0281), 1)
    }

    func test_nSet_discontinuationReasonAbsentUnlessDiscontinued() {
        let completed = MPPSProcedureStep(
            sopInstanceUID: "1", status: .completed, endDateTime: Date(),
            performedSeries: [MPPSPerformedSeries(seriesInstanceUID: "9.9", protocolName: "P")],
            discontinuationReason: reason)
        let data = DICOMMPPSService.buildNSetAttributes(
            procedureStep: completed, includeScheduledStepAttributes: false, transferSyntax: explicitLE)
        XCTAssertFalse(contains(data, 0x0040, 0x0281), "the reason is only meaningful for DISCONTINUED")

        let noReason = MPPSProcedureStep(sopInstanceUID: "1", status: .discontinued, endDateTime: Date())
        let data2 = DICOMMPPSService.buildNSetAttributes(
            procedureStep: noReason, includeScheduledStepAttributes: false, transferSyntax: explicitLE)
        XCTAssertFalse(contains(data2, 0x0040, 0x0281), "Type 3: omitted when no reason is given")
    }

    // MARK: - State validation (PS3.4 F.7.2.1.2 / F.7.2.1.3)

    private func assertInvalidState(_ body: () throws -> Void, containing fragment: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            guard case DICOMNetworkError.invalidState(let message) = error else {
                return XCTFail("expected invalidState, got \(error)", file: file, line: line)
            }
            XCTAssertTrue(message.contains(fragment), "message '\(message)' should cite \(fragment)", file: file, line: line)
        }
    }

    func test_validate_nCreateRejectsAnyStatusButInProgress() {
        for status in [MPPSStatus.completed, .discontinued] {
            let step = MPPSProcedureStep(sopInstanceUID: "1", status: status, startDateTime: Date())
            assertInvalidState({ try DICOMMPPSService.validate(step, for: .nCreate) }, containing: "F.7.2.1.2")
        }
        XCTAssertNoThrow(try DICOMMPPSService.validate(inProgressStep(), for: .nCreate))
    }

    func test_validate_nCreateRejectsEndDateTimeWhileInProgress() {
        let step = MPPSProcedureStep(sopInstanceUID: "1", status: .inProgress, startDateTime: Date(), endDateTime: Date())
        assertInvalidState({ try DICOMMPPSService.validate(step, for: .nCreate) }, containing: "End Date/Time")
    }

    func test_validate_nSetRejectsInProgress() {
        let step = MPPSProcedureStep(sopInstanceUID: "1", status: .inProgress, endDateTime: Date())
        assertInvalidState({ try DICOMMPPSService.validate(step, for: .nSet) }, containing: "F.7.2.1.3")
    }

    func test_validate_nSetRequiresEndDateTime() {
        let step = MPPSProcedureStep(sopInstanceUID: "1", status: .discontinued)
        assertInvalidState({ try DICOMMPPSService.validate(step, for: .nSet) }, containing: "End Date/Time")
    }

    func test_validate_completedRequiresAPerformedSeriesItem() {
        let empty = MPPSProcedureStep(sopInstanceUID: "1", status: .completed, endDateTime: Date())
        assertInvalidState({ try DICOMMPPSService.validate(empty, for: .nSet) }, containing: "(0040,0340)")

        let discontinued = MPPSProcedureStep(sopInstanceUID: "1", status: .discontinued, endDateTime: Date())
        XCTAssertNoThrow(try DICOMMPPSService.validate(discontinued, for: .nSet), "DISCONTINUED may have no series")

        let withSeries = MPPSProcedureStep(
            sopInstanceUID: "1", status: .completed, endDateTime: Date(),
            referencedSOPs: [("1.2.3", "1.2.3.4", "1.2.3.4.5")], referencedSOPClassUID: "1.2.840.10008.5.1.4.1.1.2")
        XCTAssertNoThrow(try DICOMMPPSService.validate(withSeries, for: .nSet))
    }

    func test_create_withCompletedThrowsBeforeConnecting() async {
        do {
            _ = try await DICOMMPPSService.create(
                host: "127.0.0.1", port: 1, callingAE: "SCU", calledAE: "SCP",
                studyInstanceUID: "1.2.3", status: .completed, timeout: 1)
            XCTFail("expected invalidState")
        } catch DICOMNetworkError.invalidState(let message) {
            XCTAssertTrue(message.contains("F.7.2.1.2"))
        } catch {
            XCTFail("expected invalidState, got \(error)")
        }
    }

    func test_update_withInProgressThrowsBeforeConnecting() async {
        do {
            try await DICOMMPPSService.update(
                host: "127.0.0.1", port: 1, callingAE: "SCU", calledAE: "SCP",
                mppsInstanceUID: "1.2.3.4", status: .inProgress, timeout: 1)
            XCTFail("expected invalidState")
        } catch DICOMNetworkError.invalidState(let message) {
            XCTAssertTrue(message.contains("F.7.2.1.3"))
        } catch {
            XCTFail("expected invalidState, got \(error)")
        }
    }

    func test_update_completedWithoutSeriesThrowsBeforeConnecting() async {
        do {
            try await DICOMMPPSService.update(
                host: "127.0.0.1", port: 1, callingAE: "SCU", calledAE: "SCP",
                mppsInstanceUID: "1.2.3.4", status: .completed, timeout: 1)
            XCTFail("expected invalidState")
        } catch DICOMNetworkError.invalidState(let message) {
            XCTAssertTrue(message.contains("(0040,0340)"))
        } catch {
            XCTFail("expected invalidState, got \(error)")
        }
    }

    // MARK: - Warning statuses (PS3.7 Annex C, 10.1.5.1.6 / 10.1.3.1.6)

    func test_warningStatusesCountAsSuccessWithWarning() {
        for code: UInt16 in [0x0107, 0x0116, 0xB000, 0xB006, 0xBFFF] {
            let status = DIMSEStatus.from(code)
            XCTAssertTrue(status.isSuccessOrWarning, String(format: "0x%04X must be accepted", code))
            XCTAssertTrue(status.isWarning, String(format: "0x%04X is a warning", code))
            XCTAssertFalse(status.isFailure, String(format: "0x%04X is not a failure", code))
            let result = MPPSOperationResult(sopInstanceUID: "1.2", status: status)
            XCTAssertEqual(result.warning, status, "the warning must be surfaced to the caller")
        }
        for code: UInt16 in [0x0106, 0x0110, 0x0112, 0x0120, 0xA700, 0xC000] {
            XCTAssertFalse(DIMSEStatus.from(code).isSuccessOrWarning, String(format: "0x%04X must be rejected", code))
        }
        XCTAssertNil(MPPSOperationResult(sopInstanceUID: "1.2", status: .success).warning)
    }

    func test_operationResult_reportsReassignedSOPInstanceUID() {
        let result = MPPSOperationResult(sopInstanceUID: "9.9", status: .success, requestedSOPInstanceUID: "1.1")
        XCTAssertTrue(result.sopInstanceUIDWasReassigned)
        XCTAssertEqual(result.sopInstanceUID, "9.9", "the SCP's UID wins (PS3.7 10.1.5.1.4)")
        XCTAssertFalse(MPPSOperationResult(sopInstanceUID: "1.1", status: .success).sopInstanceUIDWasReassigned)
    }
}
