//
// NetworkDeferredRows2026aTests.swift
// DICOMNetworkTests
//
// Deferred rows D72, D74, D75, D77, D81 (see WorklistQueryKeysTests), D155, D156 and
// D210 (2026-10-01), each pinned to its DICOM 2026a reference.
//

import XCTest
import Foundation
import DICOMCore
import DICOMKit
@testable import DICOMNetwork

final class NetworkDeferredRows2026aTests: XCTestCase {

    // MARK: - D72: C-STORE Warning class is a stored result (PS3.4 Table B.2-1)

    private func storeResult(_ status: DIMSEStatus, success: Bool) -> StoreResult {
        StoreResult(success: success, status: status, affectedSOPClassUID: "1.2.840.10008.5.1.4.1.1.7",
                    affectedSOPInstanceUID: "1.2.3", roundTripTime: 0, remoteAETitle: "SCP")
    }

    func testStoreResultClassesFollowTableB21() {
        for code: UInt16 in [0xB000, 0xB006, 0xB007] {
            let result = storeResult(.from(code), success: true)
            XCTAssertTrue(result.isStored, String(format: "%04X stored", code))
            XCTAssertTrue(result.isWarning)
            XCTAssertFalse(result.isSuccess)
            XCTAssertFalse(result.isFailure)
            XCTAssertTrue(result.description.contains("WARNING"), result.description)
        }
        for code: UInt16 in [0xA700, 0xA900, 0xC000, 0x0122] {
            let result = storeResult(.from(code), success: false)
            XCTAssertFalse(result.isStored, String(format: "%04X not stored", code))
            XCTAssertTrue(result.isFailure)
        }
        let ok = storeResult(.success, success: true)
        XCTAssertTrue(ok.isSuccess && ok.isStored && !ok.isWarning && !ok.isFailure)
    }

    // MARK: - D75: one call renders the three Table B.2-1 classes

    func testSendFileResultRendersEveryClass() {
        XCTAssertEqual(NetworkConsole.sendFileResult(status: .success, rtt: 0.012), " ✅ (12 ms)\n")
        XCTAssertEqual(NetworkConsole.sendFileResult(status: .from(0xB007), rtt: 0.012),
                       " ✅ (12 ms)\n    ⚠️ Stored with warning: Warning (0xB007): Data Set does not match SOP Class\n")
        XCTAssertEqual(NetworkConsole.sendFileResult(status: .from(0xA700), rtt: 0.012),
                       " ❌ C-STORE response status Failure (0xA700): Refused: Out of resources — not stored (PS3.4 Table B.2-1)\n")
    }

    // MARK: - D74 / D77: Query/Retrieve Level values and PS3.7 sub-operation names

    func testLevelsPrintQueryRetrieveLevelValues() {
        XCTAssertEqual(QueryLevel.allCases.map(NetworkConsole.levelName), ["PATIENT", "STUDY", "SERIES", "IMAGE"])
        XCTAssertEqual(NetworkConsole.queryRetrieveLevelValue("Instance"), "IMAGE")
        XCTAssertEqual(NetworkConsole.queryRetrieveLevelValue("Series"), "SERIES")
        let header = NetworkConsole.retrieveHeader(
            method: "C-GET", host: "h", port: 104, callingAE: "SCU", calledAE: "PACS", moveDestination: nil,
            level: "Instance", studyUID: "1.2", seriesUID: "1.2.3", instanceUID: "1.2.3.4",
            output: ".", hierarchical: false, timeout: 60, transferSyntax: nil)
        XCTAssertTrue(header.contains("  Level:             IMAGE\n"), header)
        let query = NetworkConsole.queryHeader(host: "h", port: 104, callingAE: "SCU", calledAE: "PACS",
                                               level: .image, informationModel: "Study Root", timeout: 60, filters: [])
        XCTAssertTrue(query.contains("Query Level:       IMAGE\n"), query)
    }

    func testCMoveResultUsesPS37CounterNames() {
        let block = NetworkConsole.cMoveResult(status: "Success", completed: 3, failed: 1, warning: 2, isSuccess: false)
        XCTAssertTrue(block.contains("  Number of Completed Sub-operations: 3\n"), block)
        XCTAssertTrue(block.contains("  Number of Failed Sub-operations: 1\n"), block)
        XCTAssertTrue(block.contains("  Number of Warning Sub-operations: 2\n"), block)
    }

    func testStudyEntryLabelsModalitiesInStudy() {
        let entry = NetworkConsole.qrStudyEntry(index: 1, patientName: "DOE^J", patientID: "P1",
                                                studyDescription: "CT", studyDate: "20260101",
                                                modality: "CT\\SR", studyUID: nil)
        XCTAssertTrue(entry.contains("Modalities in Study: CT\\SR"), entry)
    }

    // MARK: - D155: Implementation Class UID under DICOMKit's root (PS3.7 D.3.3.2, PS3.5 9.2.2)

    func testDefaultImplementationClassUIDsAreDICOMKits() {
        XCTAssertEqual(DICOMNetworkImplementation.classUID, DICOMFile.implementationClassUID)
        let defaults = [
            StorageConfiguration.defaultImplementationClassUID, StorageSCPConfiguration.defaultImplementationClassUID,
            QueryConfiguration.defaultImplementationClassUID, RetrieveConfiguration.defaultImplementationClassUID,
            VerificationConfiguration.defaultImplementationClassUID, PrintSCPConfiguration.defaultImplementationClassUID,
            StorageCommitmentConfiguration.defaultImplementationClassUID,
            StorageCommitmentSCPConfiguration.defaultImplementationClassUID,
            CommitmentNotificationListenerConfiguration.defaultImplementationClassUID,
        ]
        for uid in defaults {
            XCTAssertTrue(uid.hasPrefix("1.2.826.0.1.3680043.10.511."), uid)
            XCTAssertEqual(uid, DICOMFile.implementationClassUID)
        }
    }

    // MARK: - D156: Move Originator AE Title / Message ID (PS3.7 9.1.1.1.6 / 9.1.1.1.7)

    func testMoveOriginatorIsWrittenOnTheCStoreRequest() throws {
        let config = StorageConfiguration(callingAETitle: try AETitle("SCP"), calledAETitle: try AETitle("DEST"))
        XCTAssertNil(config.moveOriginatorAETitle)
        let move = config.withMoveOriginator(aeTitle: "ORIGIN", messageID: 42)
        XCTAssertEqual(move.moveOriginatorAETitle, "ORIGIN")
        XCTAssertEqual(move.moveOriginatorMessageID, 42)

        let request = DICOMStorageService.cStoreRequest(
            messageID: 7, sopClassUID: "1.2.840.10008.5.1.4.1.1.7", sopInstanceUID: "1.2.3", priority: .medium,
            moveOriginatorAETitle: move.moveOriginatorAETitle, moveOriginatorMessageID: move.moveOriginatorMessageID,
            presentationContextID: 1)
        XCTAssertEqual(request.moveOriginatorAETitle?.trimmingCharacters(in: .whitespaces), "ORIGIN")
        XCTAssertEqual(request.moveOriginatorMessageID, 42)

        let plain = DICOMStorageService.cStoreRequest(
            messageID: 7, sopClassUID: "1.2.840.10008.5.1.4.1.1.7", sopInstanceUID: "1.2.3", priority: .medium,
            moveOriginatorAETitle: "ORIGIN", moveOriginatorMessageID: nil, presentationContextID: 1)
        XCTAssertNil(plain.moveOriginatorAETitle, "written only as a pair")
        XCTAssertNil(plain.moveOriginatorMessageID)
    }

    // MARK: - D210: dicom-json keeps the response VR and decodes sequences (PS3.18 F.2.2)

    private func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8)]) }
    private func le32(_ v: UInt32) -> Data { Data((0..<4).map { UInt8((v >> (8 * $0)) & 0xFF) }) }

    private func explicitShort(_ g: UInt16, _ e: UInt16, _ vr: String, _ value: Data) -> Data {
        le16(g) + le16(e) + Data(vr.utf8) + le16(UInt16(value.count)) + value
    }

    func testDicomJSONElementsKeepVRAndDecodeSequences() throws {
        // (0008,1032) Procedure Code Sequence, defined length, one item with
        // (0008,0100) SH "P1" and (0008,0104) LO "Head CT"; (0028,0106) as SS.
        let item = explicitShort(0x0008, 0x0100, "SH", Data("P1".utf8))
            + explicitShort(0x0008, 0x0104, "LO", Data("Head CT ".utf8))
        let itemBytes = le16(0xFFFE) + le16(0xE000) + le32(UInt32(item.count)) + item
        let sequence = le16(0x0008) + le16(0x1032) + Data("SQ".utf8) + Data([0, 0]) + le32(UInt32(itemBytes.count)) + itemBytes
        let smallest = explicitShort(0x0028, 0x0106, "SS", Data([0xFE, 0xFF]))
        let identifier = sequence + smallest

        let parsed = DICOMQueryService.parseQueryResponseElements(
            data: identifier, transferSyntax: explicitVRLittleEndianTransferSyntaxUID)
        let result = GenericQueryResult(attributes: parsed.attributes, level: .study, vrs: parsed.vrs,
                                        transferSyntaxUID: explicitVRLittleEndianTransferSyntaxUID)
        let elements = Dictionary(uniqueKeysWithValues: result.dicomJSONElements().map { ($0.tag, $0) })

        let sq = try XCTUnwrap(elements[Tag(group: 0x0008, element: 0x1032)])
        XCTAssertEqual(sq.vr, .SQ, "a sequence is SQ with items, not UN")
        let items = try XCTUnwrap(sq.sequenceItems)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0][Tag(group: 0x0008, element: 0x0100)]?.vr, .SH)
        XCTAssertEqual(items[0][Tag(group: 0x0008, element: 0x0104)]?.stringValue, "Head CT")
        XCTAssertEqual(elements[Tag(group: 0x0028, element: 0x0106)]?.vr, .SS, "the response's VR, not the first of US or SS")

        // A result without a transfer syntax still falls back to UN for SQ.
        let legacy = GenericQueryResult(attributes: parsed.attributes, level: .study)
        XCTAssertEqual(legacy.dicomJSONElements().first { $0.tag == Tag(group: 0x0008, element: 0x1032) }?.vr, .UN)
    }
}
