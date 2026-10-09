import XCTest
import DICOMCore
@testable import DICOMNetwork

/// Conformance tests for Storage Commitment encoding, role selection and
/// same-/reverse-association N-EVENT-REPORT delivery.
///
/// Reference: PS3.4 Annex J, PS3.7 D.3.3.4, PS3.5 7.1
final class StorageCommitmentConformanceTests: XCTestCase {

    private typealias Codec = StorageCommitmentDataSetCodec

    private let transactionUIDTag = Tag(group: 0x0008, element: 0x1195)
    private let referencedSOPSequenceTag = Tag(group: 0x0008, element: 0x1199)
    private let failedSOPSequenceTag = Tag(group: 0x0008, element: 0x1198)
    private let referencedSOPClassTag = Tag(group: 0x0008, element: 0x1150)
    private let referencedSOPInstanceTag = Tag(group: 0x0008, element: 0x1155)
    private let failureReasonTag = Tag(group: 0x0008, element: 0x1197)

    // MARK: - Element Encoding (PS3.5 7.1)

    func testEncodeUIExplicitVRLittleEndian() {
        let data = Codec.encodeUI(tag: transactionUIDTag, value: "1.2.3", explicit: true)

        // Tag (0008,1195) LE, VR "UI", 2-byte length (6: "1.2.3" + NULL pad), value
        let expected: [UInt8] = [
            0x08, 0x00, 0x95, 0x11,
            0x55, 0x49,             // "UI"
            0x06, 0x00,
            0x31, 0x2E, 0x32, 0x2E, 0x33, 0x00
        ]
        XCTAssertEqual(Array(data), expected)
    }

    func testEncodeUIImplicitVRLittleEndianHasNoVRBytes() {
        let data = Codec.encodeUI(tag: transactionUIDTag, value: "1.2.3", explicit: false)

        // Tag (0008,1195) LE, 4-byte length (6), value - no VR bytes
        let expected: [UInt8] = [
            0x08, 0x00, 0x95, 0x11,
            0x06, 0x00, 0x00, 0x00,
            0x31, 0x2E, 0x32, 0x2E, 0x33, 0x00
        ]
        XCTAssertEqual(Array(data), expected)
    }

    func testEncodeUSExplicitAndImplicit() {
        let explicit = Codec.encodeUS(tag: failureReasonTag, value: 0x0131, explicit: true)
        XCTAssertEqual(Array(explicit), [
            0x08, 0x00, 0x97, 0x11,
            0x55, 0x53,             // "US"
            0x02, 0x00,
            0x31, 0x01
        ])

        let implicit = Codec.encodeUS(tag: failureReasonTag, value: 0x0131, explicit: false)
        XCTAssertEqual(Array(implicit), [
            0x08, 0x00, 0x97, 0x11,
            0x02, 0x00, 0x00, 0x00,
            0x31, 0x01
        ])
    }

    func testEncodeSequenceExplicitVRHasSQAndReservedBytes() {
        let item = Codec.encodeUI(tag: referencedSOPClassTag, value: "1.2", explicit: true)
        let data = Codec.encodeSequence(tag: referencedSOPSequenceTag, items: [item], explicit: true)

        var expected: [UInt8] = [
            0x08, 0x00, 0x99, 0x11,
            0x53, 0x51,             // "SQ"
            0x00, 0x00,             // reserved
            0xFF, 0xFF, 0xFF, 0xFF, // undefined length
            0xFE, 0xFF, 0x00, 0xE0, // Item
            UInt8(item.count), 0x00, 0x00, 0x00
        ]
        expected.append(contentsOf: item)
        expected.append(contentsOf: [0xFE, 0xFF, 0xDD, 0xE0, 0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(Array(data), expected)
    }

    func testEncodeSequenceImplicitVROmitsVRAndReserved() {
        let item = Codec.encodeUI(tag: referencedSOPClassTag, value: "1.2", explicit: false)
        let data = Codec.encodeSequence(tag: referencedSOPSequenceTag, items: [item], explicit: false)

        var expected: [UInt8] = [
            0x08, 0x00, 0x99, 0x11,
            0xFF, 0xFF, 0xFF, 0xFF, // undefined length directly after the tag
            0xFE, 0xFF, 0x00, 0xE0,
            UInt8(item.count), 0x00, 0x00, 0x00
        ]
        expected.append(contentsOf: item)
        expected.append(contentsOf: [0xFE, 0xFF, 0xDD, 0xE0, 0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(Array(data), expected)
    }

    // MARK: - Data Set Round Trips in Both Transfer Syntaxes

    func testCommitmentRequestDataSetRoundTripsInImplicitVR() {
        let references = [
            SOPReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.4.5"),
            SOPReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.4", sopInstanceUID: "1.2.3.4.6")
        ]
        let dataSet = StorageCommitmentService.buildCommitmentRequestDataSet(
            transactionUID: "1.2.3.4.5.6.7",
            references: references,
            transferSyntaxUID: implicitVRLittleEndianTransferSyntaxUID
        )

        // No "UI" VR bytes anywhere after the first tag
        XCTAssertEqual(Array(dataSet[4..<6]), [0x0E, 0x00]) // 4-byte length of "1.2.3.4.5.6.7\0"
        XCTAssertNotEqual(Array(dataSet[4..<6]), [0x55, 0x49])

        XCTAssertEqual(Codec.extractUIValue(from: dataSet, tag: transactionUIDTag, explicit: false), "1.2.3.4.5.6.7")
        let items = Codec.extractSequenceItems(from: dataSet, tag: referencedSOPSequenceTag, explicit: false)
        XCTAssertEqual(items?.count, 2)
        XCTAssertEqual(Codec.extractUIValue(from: items![1], tag: referencedSOPInstanceTag, explicit: false), "1.2.3.4.6")
    }

    func testCommitmentRequestDataSetRoundTripsInExplicitVR() {
        let references = [SOPReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.4.5")]
        let dataSet = StorageCommitmentService.buildCommitmentRequestDataSet(
            transactionUID: "1.2.3.4.5.6.7",
            references: references,
            transferSyntaxUID: explicitVRLittleEndianTransferSyntaxUID
        )

        XCTAssertEqual(Array(dataSet[4..<6]), [0x55, 0x49]) // "UI"
        XCTAssertEqual(Codec.extractUIValue(from: dataSet, tag: transactionUIDTag, explicit: true), "1.2.3.4.5.6.7")
        let items = Codec.extractSequenceItems(from: dataSet, tag: referencedSOPSequenceTag, explicit: true)
        XCTAssertEqual(items?.count, 1)
        XCTAssertEqual(Codec.extractUIValue(from: items![0], tag: referencedSOPClassTag, explicit: true), "1.2.840.10008.5.1.4.1.1.2")
    }

    func testCommitmentResultDataSetRoundTripsInBothTransferSyntaxes() throws {
        let result = CommitmentResult(
            transactionUID: "1.2.3.4.5.6.7",
            committedReferences: [SOPReference(sopClassUID: "1.2", sopInstanceUID: "1.2.1")],
            failedReferences: [FailedSOPReference(
                reference: SOPReference(sopClassUID: "1.2", sopInstanceUID: "1.2.2"),
                failureReason: StorageCommitmentFailureReason.duplicateTransactionUID)],
            remoteAETitle: "SCP"
        )

        for transferSyntax in [implicitVRLittleEndianTransferSyntaxUID, explicitVRLittleEndianTransferSyntaxUID] {
            let dataSet = StorageCommitmentService.buildCommitmentResultDataSet(result, transferSyntaxUID: transferSyntax)

            let parsed = try StorageCommitmentService.parseCommitmentResult(
                eventTypeID: storageCommitmentFailureEventTypeID,
                dataSet: dataSet,
                remoteAETitle: "SCP",
                transferSyntaxUID: transferSyntax
            )

            XCTAssertEqual(parsed.transactionUID, "1.2.3.4.5.6.7", transferSyntax)
            XCTAssertEqual(parsed.committedReferences, result.committedReferences, transferSyntax)
            XCTAssertEqual(parsed.failedReferences, result.failedReferences, transferSyntax)
            XCTAssertEqual(parsed.failedReferences.first?.failureReason, 0x0131, transferSyntax)
        }
    }

    func testImplicitVRResultDataSetFailureReasonHasNoVRBytes() {
        let result = CommitmentResult(
            transactionUID: "1.2",
            committedReferences: [],
            failedReferences: [FailedSOPReference(
                reference: SOPReference(sopClassUID: "1.2", sopInstanceUID: "1.2.2"),
                failureReason: 0x0110)],
            remoteAETitle: "SCP"
        )
        let dataSet = StorageCommitmentService.buildCommitmentResultDataSet(
            result, transferSyntaxUID: implicitVRLittleEndianTransferSyntaxUID)

        // Locate (0008,1197) and check the 4 bytes after it are a 4-byte length of 2
        let bytes = Array(dataSet)
        var found = false
        for i in 0..<(bytes.count - 9) where bytes[i] == 0x08 && bytes[i + 1] == 0x00 && bytes[i + 2] == 0x97 && bytes[i + 3] == 0x11 {
            XCTAssertEqual(Array(bytes[(i + 4)..<(i + 8)]), [0x02, 0x00, 0x00, 0x00])
            XCTAssertEqual(Array(bytes[(i + 8)..<(i + 10)]), [0x10, 0x01])
            found = true
        }
        XCTAssertTrue(found, "Failure Reason element not found")
    }

    // MARK: - extractUIValue with a Leading Long-VR Element

    func testExtractUIValueSkipsLeadingLongVRElementInExplicitVR() {
        // (0008,1190) UN with 2 reserved bytes + 4-byte length, followed by the Transaction UID
        var dataSet = Data()
        let unknownValue: [UInt8] = [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]
        dataSet.append(Codec.encodeElement(
            tag: Tag(group: 0x0008, element: 0x1190), vr: .UN, value: Data(unknownValue), explicit: true))
        // Sanity: long VR header is 12 bytes
        XCTAssertEqual(dataSet.count, 12 + unknownValue.count)
        XCTAssertEqual(Array(dataSet[4..<6]), [0x55, 0x4E]) // "UN"
        XCTAssertEqual(Array(dataSet[6..<8]), [0x00, 0x00]) // reserved

        dataSet.append(Codec.encodeUI(tag: transactionUIDTag, value: "1.2.3.4", explicit: true))

        // Known transfer syntax
        XCTAssertEqual(Codec.extractUIValue(from: dataSet, tag: transactionUIDTag, explicit: true), "1.2.3.4")
        // Heuristic detection (transfer syntax unknown)
        XCTAssertEqual(Codec.extractUIValue(from: dataSet, tag: transactionUIDTag, explicit: nil), "1.2.3.4")

        // Same with OB, and with a leading undefined-length SQ
        var withOB = Data()
        withOB.append(Codec.encodeElement(
            tag: Tag(group: 0x0008, element: 0x1190), vr: .OB, value: Data([0x01, 0x02]), explicit: true))
        withOB.append(Codec.encodeUI(tag: transactionUIDTag, value: "1.2.3.4", explicit: true))
        XCTAssertEqual(Codec.extractUIValue(from: withOB, tag: transactionUIDTag, explicit: true), "1.2.3.4")

        var withSQ = Data()
        let item = Codec.encodeUI(tag: referencedSOPClassTag, value: "9.9", explicit: true)
        withSQ.append(Codec.encodeSequence(tag: referencedSOPSequenceTag, items: [item], explicit: true))
        withSQ.append(Codec.encodeUI(tag: transactionUIDTag, value: "1.2.3.4", explicit: true))
        XCTAssertEqual(Codec.extractUIValue(from: withSQ, tag: transactionUIDTag, explicit: true), "1.2.3.4")
        XCTAssertEqual(Codec.extractUIValue(from: withSQ, tag: transactionUIDTag, explicit: nil), "1.2.3.4")
    }

    func testExtractSequenceItemsHandlesUndefinedLengthItems() {
        // Item with undefined length and an Item Delimitation Item
        var dataSet = Data([0x08, 0x00, 0x99, 0x11, 0x53, 0x51, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF])
        dataSet.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0, 0xFF, 0xFF, 0xFF, 0xFF])
        dataSet.append(Codec.encodeUI(tag: referencedSOPInstanceTag, value: "5.5.5", explicit: true))
        dataSet.append(contentsOf: [0xFE, 0xFF, 0x0D, 0xE0, 0x00, 0x00, 0x00, 0x00])
        dataSet.append(contentsOf: [0xFE, 0xFF, 0xDD, 0xE0, 0x00, 0x00, 0x00, 0x00])
        dataSet.append(Codec.encodeUI(tag: transactionUIDTag, value: "7.7", explicit: true))

        let items = Codec.extractSequenceItems(from: dataSet, tag: referencedSOPSequenceTag, explicit: true)
        XCTAssertEqual(items?.count, 1)
        XCTAssertEqual(Codec.extractUIValue(from: items![0], tag: referencedSOPInstanceTag, explicit: true), "5.5.5")
        XCTAssertEqual(Codec.extractUIValue(from: dataSet, tag: transactionUIDTag, explicit: true), "7.7")
    }

    // MARK: - Failure Reasons (PS3.4 Table J.3-3)

    func testFailureReason0x0131IsDuplicateTransactionUID() {
        let failed = FailedSOPReference(
            reference: SOPReference(sopClassUID: "1.2", sopInstanceUID: "1.2.3"),
            failureReason: StorageCommitmentFailureReason.duplicateTransactionUID
        )
        XCTAssertEqual(failed.failureReason, 0x0131)
        XCTAssertEqual(failed.failureReasonDescription, "Duplicate transaction UID")
    }

    // MARK: - SCP/SCU Role Selection Answers (PS3.7 D.3.3.4.2)

    func testAcceptorResponseGrantsCommitmentRolesAndRefusesUnknownClasses() {
        let proposed: [SCPSCURoleSelection] = [
            .both(storageCommitmentPushModelSOPClassUID),
            .both("1.2.840.10008.5.1.4.1.1.2")
        ]

        let answer = proposed.acceptorResponse(
            acceptSCURoleFor: { $0 == storageCommitmentPushModelSOPClassUID },
            acceptSCPRoleFor: { $0 == storageCommitmentPushModelSOPClassUID }
        )

        XCTAssertEqual(answer.count, 2)
        XCTAssertEqual(answer[0], SCPSCURoleSelection(
            sopClassUID: storageCommitmentPushModelSOPClassUID, scuRole: true, scpRole: true))
        XCTAssertEqual(answer[1], SCPSCURoleSelection(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2", scuRole: false, scpRole: false))

        let roles = NegotiatedRoles.resolve(
            proposed: proposed, accepted: answer, sopClassUID: storageCommitmentPushModelSOPClassUID)
        XCTAssertTrue(roles.requestorIsSCP)
        XCTAssertTrue(roles.requestorIsSCU)
    }

    func testAcceptorResponseEchoesReverseAssociationProposal() {
        // The commitment SCP proposes scuRole=false, scpRole=true on the reverse association
        let proposed: [SCPSCURoleSelection] = [.scpOnly(storageCommitmentPushModelSOPClassUID)]

        let answer = proposed.acceptorResponse(
            acceptSCURoleFor: { _ in true },
            acceptSCPRoleFor: { _ in true }
        )

        XCTAssertEqual(answer, [SCPSCURoleSelection(
            sopClassUID: storageCommitmentPushModelSOPClassUID, scuRole: false, scpRole: true)])
        XCTAssertTrue(NegotiatedRoles.resolve(
            proposed: proposed, accepted: answer, sopClassUID: storageCommitmentPushModelSOPClassUID).requestorIsSCP)
    }

    func testAcceptorResponseCanOnlyReduceProposedRoles() {
        let proposed: [SCPSCURoleSelection] = [
            SCPSCURoleSelection(sopClassUID: storageCommitmentPushModelSOPClassUID, scuRole: true, scpRole: false)
        ]
        let answer = proposed.acceptorResponse(acceptSCURoleFor: { _ in true }, acceptSCPRoleFor: { _ in true })
        XCTAssertFalse(answer[0].scpRole)
        XCTAssertFalse(NegotiatedRoles.resolve(
            proposed: proposed, accepted: answer, sopClassUID: storageCommitmentPushModelSOPClassUID).requestorIsSCP)
    }

    // MARK: - Configuration

    func testSCUConfigurationSameAssociationDefaults() throws {
        let config = StorageCommitmentConfiguration(
            callingAETitle: AETitle(stringLiteral: "SCU"),
            calledAETitle: AETitle(stringLiteral: "SCP")
        )
        XCTAssertTrue(config.allowSameAssociationEventReport)
        XCTAssertEqual(config.sameAssociationEventReportTimeout, 30)
    }

    func testSCPConfigurationEqualityIgnoresDestinationResolver() throws {
        let aeTitle = AETitle(stringLiteral: "SCP")
        let config1 = StorageCommitmentSCPConfiguration(aeTitle: aeTitle, port: 11112)
        let config2 = StorageCommitmentSCPConfiguration(
            aeTitle: aeTitle, port: 11112,
            eventReportDestination: { _ in ("127.0.0.1", 11113) })
        XCTAssertEqual(config1, config2)
        XCTAssertEqual(config1.hashValue, config2.hashValue)
        XCTAssertEqual(config2.eventReportDestination?("ANY")?.port, 11113)
    }

    #if canImport(Network)

    // MARK: - Duplicate Transaction UID Tracking

    func testServerRejectsDuplicateTransactionUID() async throws {
        let server = StorageCommitmentServer(
            configuration: StorageCommitmentSCPConfiguration(aeTitle: AETitle(stringLiteral: "SCP"), port: 19140),
            delegate: DefaultCommitmentHandler()
        )
        let accepted = await server.registerTransactionUID("1.2.3")
        let duplicate = await server.registerTransactionUID("1.2.3")
        let other = await server.registerTransactionUID("1.2.4")
        XCTAssertTrue(accepted)
        XCTAssertFalse(duplicate)
        XCTAssertTrue(other)
    }

    // MARK: - Loopback: Same-Association N-EVENT-REPORT (PS3.4 J.3.3)

    func testLoopbackCommitmentResultOnSameAssociation() async throws {
        let scpPort: UInt16 = 19141
        let server = StorageCommitmentServer(
            configuration: StorageCommitmentSCPConfiguration(aeTitle: AETitle(stringLiteral: "SC_SCP"), port: scpPort),
            delegate: DefaultCommitmentHandler()
        )
        try await server.start()
        defer { Task { await server.stop() } }
        try await Task.sleep(for: .milliseconds(300))

        let references = [
            SOPReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.4.5"),
            SOPReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.4.6")
        ]
        let config = StorageCommitmentConfiguration(
            callingAETitle: AETitle(stringLiteral: "SC_SCU"),
            calledAETitle: AETitle(stringLiteral: "SC_SCP"),
            timeout: 5,
            retryPolicy: .noRetry,
            sameAssociationEventReportTimeout: 5
        )

        let request = try await StorageCommitmentService.requestCommitment(
            for: references,
            host: "127.0.0.1",
            port: scpPort,
            configuration: config
        )

        let result = try XCTUnwrap(request.result, "Expected the result on the same association")
        XCTAssertEqual(result.transactionUID, request.transactionUID)
        XCTAssertEqual(result.committedReferences, references)
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.remoteAETitle, "SC_SCP")

        await server.stop()
    }

    // MARK: - Loopback: Reverse-Association N-EVENT-REPORT (PS3.4 J.3.3)

    func testLoopbackCommitmentResultOnReverseAssociation() async throws {
        let scpPort: UInt16 = 19142
        let listenerPort: UInt16 = 19143

        let listener = CommitmentNotificationListener(
            configuration: CommitmentNotificationListenerConfiguration(
                aeTitle: AETitle(stringLiteral: "SC_SCU"), port: listenerPort))
        try await listener.start()

        let server = StorageCommitmentServer(
            configuration: StorageCommitmentSCPConfiguration(
                aeTitle: AETitle(stringLiteral: "SC_SCP"),
                port: scpPort,
                eventReportDestination: { aeTitle in
                    aeTitle == "SC_SCU" ? ("127.0.0.1", listenerPort) : nil
                }),
            delegate: DefaultCommitmentHandler()
        )
        try await server.start()
        try await Task.sleep(for: .milliseconds(300))

        let references = [SOPReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.4", sopInstanceUID: "1.2.3.4.7")]
        // Do not propose the SCP role: the SCP must use a reverse association
        let config = StorageCommitmentConfiguration(
            callingAETitle: AETitle(stringLiteral: "SC_SCU"),
            calledAETitle: AETitle(stringLiteral: "SC_SCP"),
            timeout: 5,
            retryPolicy: .noRetry,
            allowSameAssociationEventReport: false
        )

        let request = try await StorageCommitmentService.requestCommitment(
            for: references,
            host: "127.0.0.1",
            port: scpPort,
            configuration: config
        )
        XCTAssertNil(request.result)

        let result = try await StorageCommitmentService.waitForCommitment(
            request: request,
            timeout: .seconds(5),
            listener: listener
        )

        XCTAssertEqual(result.transactionUID, request.transactionUID)
        XCTAssertEqual(result.committedReferences, references)
        XCTAssertEqual(result.remoteAETitle, "SC_SCP")

        await server.stop()
        await listener.stop()
    }

    #endif
}
