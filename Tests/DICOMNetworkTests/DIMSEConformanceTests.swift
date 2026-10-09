import XCTest
import DICOMCore
@testable import DICOMNetwork

/// DIMSE / Query-Retrieve conformance fixes verified against DICOM 2026a
/// (PS3.4, PS3.5, PS3.7, PS3.8). Each test pins the standard's value.
final class DIMSEConformanceTests: XCTestCase {

    // MARK: - C-GET storage contexts are batched (PS3.8 9.3.2.2)

    func test_cget_storageContextBatches_170ClassesSplitInto127And43() {
        let uids = (0..<170).map { "1.2.840.10008.5.1.4.1.1.\($0)" }
        let batches = DICOMRetrieveService.storageContextBatches(uids)
        XCTAssertEqual(DICOMRetrieveService.maxStorageContextsPerAssociation, 127,
                       "odd IDs 1...255 give 128 contexts, ID 1 is the C-GET class")
        XCTAssertEqual(batches.map(\.count), [127, 43])
        XCTAssertEqual(batches.flatMap { $0 }, uids, "order is preserved")
        XCTAssertEqual(Set(batches.flatMap { $0 }).count, 170, "no duplicates")
    }

    func test_cget_storageContextBatches_tenClassesAreOneBatch() {
        let uids = (0..<10).map { "1.2.840.10008.5.1.4.1.1.\($0)" }
        XCTAssertEqual(DICOMRetrieveService.storageContextBatches(uids), [uids])
    }

    func test_cget_storageContextBatches_deduplicatesKeepingFirstPosition() {
        let batches = DICOMRetrieveService.storageContextBatches(["a", "b", "a", "c", "b"])
        XCTAssertEqual(batches, [["a", "b", "c"]])
        XCTAssertEqual(DICOMRetrieveService.storageContextBatches([]), [])
    }

    func test_cget_allStorageClassesFitTwoBatches() {
        // The package-wide registry (PS3.4 Table B.5-1) exceeds one association.
        let batches = DICOMRetrieveService.storageContextBatches(commonStorageSOPClassUIDs)
        XCTAssertGreaterThan(commonStorageSOPClassUIDs.count, 127)
        XCTAssertEqual(batches.count, 2)
        XCTAssertTrue(batches.allSatisfy { $0.count <= 127 })
    }

    func test_cget_mergeGetPassResults_sumsCompletedKeepsLastFailures() {
        let first = RetrieveResult(
            status: .warningCoercionOfDataElements,
            progress: RetrieveProgress(remaining: 0, completed: 10, failed: 3, warning: 1),
            failedSOPInstanceUIDs: ["1.1", "1.2", "1.3"])
        let second = RetrieveResult(
            status: .success,
            progress: RetrieveProgress(remaining: 0, completed: 3, failed: 0, warning: 0),
            failedSOPInstanceUIDs: [])
        let merged = DICOMRetrieveService.mergeGetPassResults(previous: first, next: second)
        XCTAssertEqual(merged.progress.completed, 13)
        XCTAssertEqual(merged.progress.failed, 0, "failures of the first pass were classes not yet proposed")
        XCTAssertEqual(merged.progress.warning, 1)
        XCTAssertEqual(merged.progress.remaining, 0)
        XCTAssertEqual(merged.failedSOPInstanceUIDs, [])
        XCTAssertTrue(merged.status.isSuccess)
        XCTAssertTrue(merged.isSuccess)
        // A first pass is returned unchanged.
        XCTAssertEqual(DICOMRetrieveService.mergeGetPassResults(previous: nil, next: first), first)
    }

    // MARK: - Rows / Columns are VR US (PS3.5 Table 6.2-1)

    func test_instanceResult_rowsAndColumnsDecodeTwoByteUnsignedLittleEndian() {
        let result = InstanceResult(attributes: [
            .rows: Data([0x00, 0x02]),      // 512
            .columns: Data([0x00, 0x01])    // 256
        ])
        XCTAssertEqual(result.rows, 512)
        XCTAssertEqual(result.columns, 256)
    }

    func test_instanceResult_rowsAcceptsASCIIDigitsFromLenientSCPs() {
        // Only strings that cannot be a 2-byte US value are read as digits.
        let result = InstanceResult(attributes: [.rows: Data("512 ".utf8), .columns: Data("640".utf8)])
        XCTAssertEqual(result.rows, 512)
        XCTAssertEqual(result.columns, 640)
        XCTAssertNil(InstanceResult(attributes: [:]).rows)
    }

    // MARK: - Store-and-forward dequeues HIGH before MEDIUM before LOW (PS3.7 Table E.1-1)

    func test_dimsePriority_rawValuesAreThoseOfTableE1_1() {
        XCTAssertEqual(DIMSEPriority.low.rawValue, 0x0002)
        XCTAssertEqual(DIMSEPriority.medium.rawValue, 0x0000)
        XCTAssertEqual(DIMSEPriority.high.rawValue, 0x0001)
        XCTAssertLessThan(DIMSEPriority.high.schedulingRank, DIMSEPriority.medium.schedulingRank)
        XCTAssertLessThan(DIMSEPriority.medium.schedulingRank, DIMSEPriority.low.schedulingRank)
    }

    func test_storeAndForward_prioritySortedProcessesHighMediumLow() {
        func item(_ priority: DIMSEPriority, _ uid: String) -> QueuedStoreItem {
            QueuedStoreItem(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: uid,
                transferSyntaxUID: "1.2.840.10008.1.2.1", host: "localhost", port: 104,
                callingAETitle: "SCU", calledAETitle: "SCP", priority: priority, fileSize: 1)
        }
        let queued = [item(.low, "L"), item(.medium, "M"), item(.high, "H")]
        let order = StoreAndForwardQueue.prioritySorted(queued).map(\.sopInstanceUID)
        XCTAssertEqual(order, ["H", "M", "L"], "rawValue order (LOW=2 first) is not urgency order")
    }

    // MARK: - Command element padding follows the VR (PS3.5 Table 6.2-1, PS3.7 Table E.1-1)

    func test_cmoveRequest_oddLengthMoveDestinationIsSpacePadded() {
        let request = CMoveRequest(
            messageID: 1,
            affectedSOPClassUID: "1.2.840.10008.5.1.4.1.2.2.2",
            moveDestination: "DEST1",          // 5 characters, AE
            presentationContextID: 1)
        let bytes = request.commandSet.getData(.moveDestination)!
        XCTAssertEqual(bytes, Data("DEST1 ".utf8), "AE is padded with SPACE (20H)")
        XCTAssertEqual(request.commandSet.moveDestination, "DEST1")
    }

    func test_commandSet_moveOriginatorAETAndErrorCommentAreSpacePadded() {
        var cmd = CommandSet()
        cmd.setString("ORIGIN1", for: .moveOriginatorApplicationEntityTitle)
        cmd.setString("bad", for: .errorComment)
        XCTAssertEqual(cmd.getData(.moveOriginatorApplicationEntityTitle)!.last, 0x20)
        XCTAssertEqual(cmd.getData(.errorComment)!.last, 0x20, "LO is padded with SPACE (20H)")
        XCTAssertEqual(cmd.getString(.errorComment), "bad")
    }

    func test_commandSet_oddLengthUIDsKeepNullPadding() {
        var cmd = CommandSet()
        cmd.setAffectedSOPClassUID("1.2.840.10008.3.1.2.3.3")   // 23 characters
        let bytes = cmd.getData(.affectedSOPClassUID)!
        XCTAssertEqual(bytes.count, 24)
        XCTAssertEqual(bytes.last, 0x00, "UI is padded with NULL (00H)")
        XCTAssertEqual(cmd.getString(.affectedSOPClassUID), "1.2.840.10008.3.1.2.3.3")
    }

    // MARK: - DIMSEStatus classification (PS3.7 Annex C, PS3.4 Tables B.2-1 / F.8.2-2)

    func test_dimseStatus_failureWarningPendingCancelRanges() {
        for code: UInt16 in [0xA7FF, 0xA9FF, 0xC001, 0x0123, 0x0211] {
            XCTAssertTrue(DIMSEStatus.from(code).isFailure, String(format: "0x%04X is a failure", code))
            XCTAssertFalse(DIMSEStatus.from(code).isWarning, String(format: "0x%04X is not a warning", code))
        }
        for code: UInt16 in [0x0107, 0x0116, 0xB000] {
            XCTAssertTrue(DIMSEStatus.from(code).isWarning, String(format: "0x%04X is a warning", code))
            XCTAssertFalse(DIMSEStatus.from(code).isFailure, String(format: "0x%04X is not a failure", code))
        }
        XCTAssertTrue(DIMSEStatus.from(0x0001).isWarning, "PS3.4 Table F.8.2-2: optional Attributes not supported")
        XCTAssertTrue(DIMSEStatus.from(0xFF00).isPending)
        XCTAssertTrue(DIMSEStatus.from(0xFF01).isPending)
        XCTAssertTrue(DIMSEStatus.from(0xFE00).isCancel)
        // A7xx / A9xx codes other than the named ones keep their code.
        XCTAssertEqual(DIMSEStatus.from(0xA7FF).rawValue, 0xA7FF)
        XCTAssertEqual(DIMSEStatus.from(0xA9FF).rawValue, 0xA9FF)
    }

    func test_dimseStatus_cxxxDescriptionNamesBothTableWordings() {
        let description = DIMSEStatus.errorCannotUnderstand(0xC001).description
        XCTAssertTrue(description.contains("Failed: unable to process / cannot understand (Cxxx)"), description)
        XCTAssertTrue(description.contains("0xC001"), description)
    }

    // MARK: - Modality Worklist Specific Character Set (PS3.4 C.2.2.2, K.4.1.1.3.1; PS3.5 6.1.2)

    private func parseMWL(_ data: Data) -> [Tag: Data] {
        var offset = 0
        var parsed = DICOMModalityWorklistService.MWLParsedDataSet()
        DICOMModalityWorklistService.parseMWLDataSet(
            data: data, offset: &offset, end: data.count, isExplicitVR: false, into: &parsed)
        return parsed.attributes
    }

    func test_mwlIdentifier_defaultRepertoireOmitsSpecificCharacterSetEvenAsReturnKey() {
        let keys = WorklistQueryKeys.default().patientName("DOE^JOHN").specificCharacterSet("")
        let data = DICOMModalityWorklistService.buildQueryIdentifier(
            queryKeys: keys, transferSyntax: implicitVRLittleEndianTransferSyntaxUID)
        let attrs = parseMWL(data)
        XCTAssertNil(attrs[.specificCharacterSet],
                     "PS3.4 K.4.1.1.3.1: not included unless an expanded/replacement set is used; C.2.2.2: never zero length")
    }

    func test_mwlIdentifier_latin1KeyDeclaresISOIR100() {
        let keys = WorklistQueryKeys.default().patientName("MÜLLER^HANS")
        let data = DICOMModalityWorklistService.buildQueryIdentifier(
            queryKeys: keys, transferSyntax: implicitVRLittleEndianTransferSyntaxUID)
        let attrs = parseMWL(data)
        XCTAssertEqual(attrs[.specificCharacterSet].flatMap { String(data: $0, encoding: .ascii) }, "ISO_IR 100")
    }

    func test_worklistItem_noCharacterSetDecodesAsDefaultRepertoire() {
        let item = WorklistItem(attributes: [.patientName: Data("DOE^JOHN ".utf8)])
        XCTAssertNil(item.attributes[.specificCharacterSet])
        XCTAssertEqual(item.patientName, "DOE^JOHN", "absent (0008,0005) means ISO-IR 6 (PS3.5 6.1.2)")
    }

    func test_worklistItem_undeclaredHighBytesFallBackToLatin1Leniently() {
        let latin1 = "MÜLLER^HANS".data(using: .isoLatin1)!
        let item = WorklistItem(attributes: [.patientName: latin1])
        XCTAssertEqual(item.patientName, "MÜLLER^HANS", "deliberate leniency for SCPs that omit (0008,0005)")
        // Declared UTF-8 wins over the leniency.
        let utf8Item = WorklistItem(attributes: [
            .specificCharacterSet: Data("ISO_IR 192".utf8),
            .patientName: Data("山田^太郎".utf8) + Data([0x20])
        ])
        XCTAssertEqual(utf8Item.patientName, "山田^太郎")
    }

    // MARK: - MPPS (PS3.4 Table F.7.2-1; PS3.5 Table 6.2-1)

    private func nestedValue(_ data: Data, _ g: UInt16, _ e: UInt16) -> Data? {
        // Explicit VR LE: tag, VR(2), length(2), value — enough for SH.
        let tag = Data([UInt8(g & 0xFF), UInt8(g >> 8), UInt8(e & 0xFF), UInt8(e >> 8)])
        guard let r = data.range(of: tag) else { return nil }
        let lengthStart = r.upperBound + 2
        let length = Int(data[lengthStart]) | Int(data[lengthStart + 1]) << 8
        return data.subdata(in: (lengthStart + 2)..<(lengthStart + 2 + length))
    }

    func test_mpps_scheduledProcedureStepIDIsSentEmptyWhenUnknown() {
        let step = MPPSProcedureStep(
            sopInstanceUID: "1.2.3", status: .inProgress, studyInstanceUID: "1.2.3.4",
            startDateTime: Date(), modality: "CT", procedureStepID: "PPS1")
        let data = DICOMMPPSService.buildMPPSAttributes(procedureStep: step, transferSyntax: "1.2.840.10008.1.2.1")
        XCTAssertEqual(nestedValue(data, 0x0040, 0x0009), Data(),
                       "Table F.7.2-1: (0040,0009) is 2/2 in Scheduled Step Attributes Sequence — empty, not fabricated")
    }

    func test_mpps_nCreateAndNSetCommandSetsHaveEvenLengthUIDs() {
        // "1.2.840.10008.3.1.2.3.3" is 23 characters: it must be NULL-padded to 24.
        let create = DICOMMPPSService.nCreateCommandSet(sopInstanceUID: "1.2.3", presentationContextID: 1)
        let classUID = create.getData(.affectedSOPClassUID)!
        XCTAssertEqual(classUID.count % 2, 0)
        XCTAssertEqual(classUID.count, 24)
        XCTAssertEqual(classUID.last, 0x00)
        XCTAssertEqual(create.getString(.affectedSOPClassUID), modalityPerformedProcedureStepSOPClassUID)
        XCTAssertEqual(create.getData(.affectedSOPInstanceUID), Data("1.2.3\u{0}".utf8))
        XCTAssertEqual(create.command, .nCreateRequest)
        XCTAssertEqual(create.getUInt16(.commandDataSetType), 0x0000, "data set present (PS3.7 9.3.1)")

        let set = DICOMMPPSService.nSetCommandSet(sopInstanceUID: "1.2.3", presentationContextID: 1)
        XCTAssertEqual(set.getData(.requestedSOPClassUID)!.count, 24)
        XCTAssertEqual(set.getData(.requestedSOPClassUID)!.last, 0x00)
        XCTAssertEqual(set.command, .nSetRequest)
        // Round trip through the wire encoding keeps every value length even.
        let decoded = try? CommandSet.decode(from: create.encode())
        XCTAssertEqual(decoded?.getData(.affectedSOPClassUID)?.count, 24)
    }

    // MARK: - Batch C-STORE presentation contexts (PS3.8 9.3.2.2)

    func test_storage_presentationContextGroups_130ClassesNeedTwoAssociations() {
        let uids = (0..<130).map { "1.2.3.4.\($0)" }
        let groups = DICOMStorageService.presentationContextGroups(uids)
        XCTAssertEqual(DICOMStorageService.maxPresentationContextsPerAssociation, 128,
                       "odd IDs 1...255 are 128 contexts")
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map(\.count), [128, 2])
        XCTAssertEqual(groups.flatMap { $0 }, uids, "every class is proposed exactly once, in order")
        // Every group's contexts stay within the ID range.
        for group in groups {
            let lastID = 1 + 2 * (group.count - 1)
            XCTAssertLessThanOrEqual(lastID, 255)
            XCTAssertNoThrow(try PresentationContext(
                id: UInt8(lastID), abstractSyntax: group.last!,
                transferSyntaxes: [explicitVRLittleEndianTransferSyntaxUID]))
        }
    }

    func test_storage_presentationContextGroups_duplicatesCollapseAndEmptyIsEmpty() {
        XCTAssertEqual(DICOMStorageService.presentationContextGroups(["a", "a", "b"]), [["a", "b"]])
        XCTAssertEqual(DICOMStorageService.presentationContextGroups([]), [])
    }
}
