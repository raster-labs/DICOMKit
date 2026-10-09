//
// RetrievePriorityExtendedNegotiationTests.swift
// DICOMNetworkTests
//
// P-RETRIEVE-PRIORITY / P-RETRIEVE-EXTNEG (2026-10-01): the C-MOVE / C-GET
// engine sends the requested Priority (0000,0700) — PS3.7 2026a Tables 9.3-9 /
// 9.3-6: LOW 0002H, MEDIUM 0000H, HIGH 0001H — and can propose
// relational-retrieval in a SOP Class Extended Negotiation Sub-Item
// (PS3.7 Table D.3-11, PS3.4 C.5.2.1 / C.5.3.1, Tables C.5-3 / C.5-4).
// Checked on the wire against a minimal in-process Query/Retrieve SCP.
//

import XCTest
import Foundation
import DICOMCore
@testable import DICOMNetwork

final class RetrievePriorityExtendedNegotiationTests: XCTestCase {

    private let studyRootMove = "1.2.840.10008.5.1.4.1.2.2.2"
    private let studyRootGet = "1.2.840.10008.5.1.4.1.2.2.3"

    // MARK: - Sub-item encoding (no network)

    /// PS3.7 Table D.3-11: 56H, reserved, item length, uid length, uid, info.
    func testExtendedNegotiationSubItemLayoutAndRoundTrip() throws {
        let item = RetrieveExtendedNegotiation(relationalRetrieval: true).subItem(for: "1.2.3").encode()
        XCTAssertEqual(item[0], 0x56)
        XCTAssertEqual(item[1], 0x00)
        XCTAssertEqual(Int(item[2]) << 8 | Int(item[3]), 2 + 5 + 1)
        XCTAssertEqual(Int(item[4]) << 8 | Int(item[5]), 5)
        XCTAssertEqual(String(data: item[6..<11], encoding: .ascii), "1.2.3")
        XCTAssertEqual(Array(item[11...]), [1], "Table C.5-3 byte 1 only: relational-retrieval")
        let decoded = try SOPClassExtendedNegotiation.decode(from: item.dropFirst(4))
        XCTAssertEqual(decoded.sopClassUID, "1.2.3")
        XCTAssertEqual(decoded.serviceClassApplicationInformation, Data([1]))
    }

    /// Table C.5-3 byte 2 is sent only when asked; Table C.5-4 missing bytes are 0;
    /// the acceptor can only turn an offer down (C.5.2.1).
    func testRetrieveExtendedNegotiationBytesAndNegotiatedResult() {
        XCTAssertEqual(RetrieveExtendedNegotiation(relationalRetrieval: true, enhancedMultiFrameImageConversion: true)
            .serviceClassApplicationInformation, Data([1, 1]))
        let oneByte = RetrieveExtendedNegotiation(serviceClassApplicationInformation: Data([1]))
        XCTAssertTrue(oneByte.relationalRetrieval)
        XCTAssertFalse(oneByte.enhancedMultiFrameImageConversion)

        let proposed = RetrieveExtendedNegotiation(relationalRetrieval: true)
        XCTAssertEqual(RetrieveExtendedNegotiation.negotiated(proposed: proposed, accepted: [], sopClassUID: studyRootMove),
                       .baseline, "no answer = default condition")
        let turnedDown = SOPClassExtendedNegotiation(sopClassUID: studyRootMove, serviceClassApplicationInformation: Data([0]))
        XCTAssertFalse(RetrieveExtendedNegotiation.negotiated(proposed: proposed, accepted: [turnedDown],
                                                              sopClassUID: studyRootMove).relationalRetrieval)
        let accepted = SOPClassExtendedNegotiation(sopClassUID: studyRootMove, serviceClassApplicationInformation: Data([1]))
        XCTAssertTrue(RetrieveExtendedNegotiation.negotiated(proposed: proposed, accepted: [accepted],
                                                             sopClassUID: studyRootMove).relationalRetrieval)
        XCTAssertFalse(RetrieveExtendedNegotiation.negotiated(proposed: nil, accepted: [accepted],
                                                              sopClassUID: studyRootMove).relationalRetrieval)
    }

    /// The sub-item survives A-ASSOCIATE-RQ / -AC encode → PDUDecoder.
    func testAssociatePDUsCarryExtendedNegotiation() throws {
        let sub = RetrieveExtendedNegotiation(relationalRetrieval: true).subItem(for: studyRootMove)
        let rq = AssociateRequestPDU(
            calledAETitle: try AETitle("PACS"), callingAETitle: try AETitle("SCU"),
            presentationContexts: [try PresentationContext(id: 1, abstractSyntax: studyRootMove,
                                                           transferSyntaxes: [explicitVRLittleEndianTransferSyntaxUID])],
            implementationClassUID: "1.2.3.4", extendedNegotiations: [sub])
        let decodedRQ = try XCTUnwrap(try PDUDecoder.decode(from: try rq.encode()) as? AssociateRequestPDU)
        XCTAssertEqual(decodedRQ.extendedNegotiations, [sub])

        let ac = AssociateAcceptPDU(
            calledAETitle: try AETitle("PACS"), callingAETitle: try AETitle("SCU"),
            presentationContexts: [AcceptedPresentationContext(id: 1, result: .acceptance,
                                                               transferSyntax: explicitVRLittleEndianTransferSyntaxUID)],
            maxPDUSize: 16384, implementationClassUID: "1.2.3.4", extendedNegotiations: [sub])
        let decodedAC = try XCTUnwrap(try PDUDecoder.decode(from: try ac.encode()) as? AssociateAcceptPDU)
        XCTAssertEqual(decodedAC.extendedNegotiation(for: studyRootMove), sub)
    }

    /// Relational-retrieval relaxes only the above-level Unique Keys (PS3.4 C.4.2.2.2.1).
    func testRelationalValidationRelaxesOnlyAboveLevelKeys() {
        let seriesOnly = RetrieveKeys(level: .series).seriesInstanceUID("1.2.3.4")
        XCTAssertThrowsError(try DICOMRetrieveService.validateRetrieveKeys(seriesOnly, informationModel: .studyRoot))
        XCTAssertNoThrow(try DICOMRetrieveService.validateRetrieveKeys(seriesOnly, informationModel: .studyRoot,
                                                                       relationalRetrieval: true))
        let imageWithoutSOP = RetrieveKeys(level: .image).seriesInstanceUID("1.2.3.4")
        XCTAssertThrowsError(try DICOMRetrieveService.validateRetrieveKeys(imageWithoutSOP, informationModel: .studyRoot,
                                                                           relationalRetrieval: true))
        XCTAssertTrue(DICOMRetrieveService.identifierNeedsRelationalRetrieval(seriesOnly, informationModel: .studyRoot))
        XCTAssertFalse(DICOMRetrieveService.identifierNeedsRelationalRetrieval(
            RetrieveKeys.forSeries(studyUID: "1.2", seriesUID: "1.2.3"), informationModel: .studyRoot))
    }

    func testConfigurationDefaultsAreBaseline() throws {
        let config = RetrieveConfiguration(callingAETitle: try AETitle("SCU"), calledAETitle: try AETitle("PACS"))
        XCTAssertEqual(config.priority, .medium)
        XCTAssertNil(config.extendedNegotiation)
    }

    #if canImport(Network)
    // MARK: - On the wire

    private func configuration(port: UInt16, priority: DIMSEPriority,
                               relational: Bool = false) throws -> RetrieveConfiguration {
        RetrieveConfiguration(
            callingAETitle: try AETitle("SCU"), calledAETitle: try AETitle("PACS"), timeout: 10,
            priority: priority,
            extendedNegotiation: relational ? RetrieveExtendedNegotiation(relationalRetrieval: true) : nil)
    }

    /// PS3.7 Table 9.3-9: the C-MOVE-RQ carries the requested Priority; no
    /// extended negotiation sub-item is sent by default.
    func testCMoveSendsRequestedPriority() async throws {
        for priority in [DIMSEPriority.low, .medium, .high] {
            let scp = MockQRSCP(relationalAnswer: nil)
            try await scp.start()
            defer { Task { await scp.stop() } }
            let result = try await DICOMRetrieveService.move(
                host: "127.0.0.1", port: await scp.port,
                configuration: try configuration(port: 0, priority: priority),
                keys: .forStudy("1.2.3"), moveDestination: "DEST")
            XCTAssertTrue(result.isSuccess)
            let seen = await scp.priorities
            XCTAssertEqual(seen, [priority.rawValue], "Priority (0000,0700) on the wire")
            let ext = await scp.proposedExtendedNegotiations
            XCTAssertEqual(ext, [], "baseline: no SOP Class Extended Negotiation Sub-Item")
        }
    }

    /// PS3.7 Table 9.3-6: the C-GET-RQ carries the requested Priority.
    func testCGetSendsRequestedPriority() async throws {
        let scp = MockQRSCP(relationalAnswer: nil)
        try await scp.start()
        defer { Task { await scp.stop() } }
        let stream = DICOMRetrieveService.get(
            host: "127.0.0.1", port: await scp.port,
            configuration: try configuration(port: 0, priority: .high),
            keys: .forStudy("1.2.3"), storageSopClasses: ["1.2.840.10008.5.1.4.1.1.2"])
        var completed: RetrieveResult?
        for await event in stream {
            if case .completed(let r) = event { completed = r }
            if case .error(let e) = event { XCTFail("\(e)") }
        }
        XCTAssertEqual(completed?.isSuccess, true)
        let seen = await scp.priorities
        XCTAssertEqual(seen, [DIMSEPriority.high.rawValue])
    }

    /// Relational-retrieval proposed and accepted: a SERIES retrieve by Series
    /// Instance UID alone is sent (PS3.4 C.4.2.2.2.1).
    func testRelationalRetrieveAcceptedSendsSeriesOnlyIdentifier() async throws {
        let scp = MockQRSCP(relationalAnswer: 1)
        try await scp.start()
        defer { Task { await scp.stop() } }
        let result = try await DICOMRetrieveService.move(
            host: "127.0.0.1", port: await scp.port,
            configuration: try configuration(port: 0, priority: .medium, relational: true),
            keys: RetrieveKeys(level: .series).seriesInstanceUID("1.2.3.4"), moveDestination: "DEST")
        XCTAssertTrue(result.isSuccess)
        let ext = await scp.proposedExtendedNegotiations
        XCTAssertEqual(ext, [SOPClassExtendedNegotiation(sopClassUID: studyRootMove,
                                                         serviceClassApplicationInformation: Data([1]))])
        let count = await scp.priorities.count
        XCTAssertEqual(count, 1, "the C-MOVE-RQ was sent")
    }

    /// Relational-retrieval turned down (byte 1 = 0) or not answered: the
    /// series-only request is not sent and the call throws (PS3.4 C.5.2.1).
    func testRelationalRetrieveRefusedDoesNotSendRequest() async throws {
        for answer: UInt8? in [0, nil] {
            let scp = MockQRSCP(relationalAnswer: answer)
            try await scp.start()
            defer { Task { await scp.stop() } }
            do {
                _ = try await DICOMRetrieveService.move(
                    host: "127.0.0.1", port: await scp.port,
                    configuration: try configuration(port: 0, priority: .medium, relational: true),
                    keys: RetrieveKeys(level: .series).seriesInstanceUID("1.2.3.4"), moveDestination: "DEST")
                XCTFail("expected a refusal when the SCP answers \(String(describing: answer))")
            } catch {
                XCTAssertTrue("\(error)".contains("relational-retrieval"), "\(error)")
            }
            let count = await scp.priorities.count
            XCTAssertEqual(count, 0, "no C-MOVE-RQ may be sent")
        }
    }
    #endif
}

#if canImport(Network)
import Network

/// Minimal Query/Retrieve SCP: accepts every context, answers the extended
/// negotiation sub-item with `relationalAnswer` (nil = no sub-item), records
/// the Priority of each C-MOVE-RQ / C-GET-RQ and answers Success with zero
/// sub-operations.
private actor MockQRSCP {
    let relationalAnswer: UInt8?
    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private(set) var priorities: [UInt16] = []
    private(set) var proposedExtendedNegotiations: [SOPClassExtendedNegotiation] = []

    init(relationalAnswer: UInt8?) { self.relationalAnswer = relationalAnswer }

    func start() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { await self.serve(MockQRConnection(connection)) }
        }
        let ready = MockQRFlag()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: if ready.trySet() { cont.resume() }
                case .failed(let e): if ready.trySet() { cont.resume(throwing: e) }
                case .cancelled: if ready.trySet() { cont.resume(throwing: DICOMNetworkError.connectionClosed) }
                default: break
                }
            }
            listener.start(queue: .global())
        }
        listener.stateUpdateHandler = nil
        port = listener.port?.rawValue ?? 0
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func serve(_ peer: MockQRConnection) async {
        do {
            try await peer.waitReady()
            guard let rq = try await peer.receivePDU() as? AssociateRequestPDU else { return }
            proposedExtendedNegotiations = rq.extendedNegotiations
            let accepted = rq.presentationContexts.map {
                AcceptedPresentationContext(id: $0.id, result: .acceptance,
                                            transferSyntax: explicitVRLittleEndianTransferSyntaxUID)
            }
            let answers: [SOPClassExtendedNegotiation] = relationalAnswer.map { byte in
                rq.extendedNegotiations.map {
                    SOPClassExtendedNegotiation(sopClassUID: $0.sopClassUID, serviceClassApplicationInformation: Data([byte]))
                }
            } ?? []
            try await peer.send(AssociateAcceptPDU(
                calledAETitle: rq.calledAETitle, callingAETitle: rq.callingAETitle,
                presentationContexts: accepted, maxPDUSize: 16384,
                implementationClassUID: "1.2.826.0.1.3680043.9.7433.99.2",
                roleSelections: rq.roleSelections, extendedNegotiations: answers))

            var assembler = MessageAssembler()
            while true {
                let pdu = try await peer.receivePDU()
                if pdu is ReleaseRequestPDU {
                    try await peer.send(ReleaseResponsePDU())
                    peer.cancel()
                    return
                }
                guard let data = pdu as? DataTransferPDU else { peer.cancel(); return }
                guard let message = try assembler.addPDVs(from: data) else { continue }
                assembler = MessageAssembler()
                let cmd = message.commandSet
                priorities.append(cmd.priority?.rawValue ?? 0xFFFF)
                let id = cmd.messageID ?? 1
                let sop = cmd.affectedSOPClassUID ?? ""
                let response: CommandSet
                if cmd.command == .cGetRequest {
                    response = CGetResponse(messageIDBeingRespondedTo: id, affectedSOPClassUID: sop, status: .success,
                                            remaining: 0, completed: 0, failed: 0, warning: 0,
                                            presentationContextID: message.presentationContextID).commandSet
                } else {
                    response = CMoveResponse(messageIDBeingRespondedTo: id, affectedSOPClassUID: sop, status: .success,
                                             remaining: 0, completed: 0, failed: 0, warning: 0,
                                             presentationContextID: message.presentationContextID).commandSet
                }
                for out in MessageFragmenter(maxPDUSize: 16384).fragmentMessage(
                    commandSet: response, dataSet: nil, presentationContextID: message.presentationContextID) {
                    try await peer.send(out)
                }
            }
        } catch {
            peer.cancel()
        }
    }
}

private final class MockQRFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var set = false
    func trySet() -> Bool { lock.lock(); defer { lock.unlock() }; if set { return false }; set = true; return true }
}

private final class MockQRConnection: @unchecked Sendable {
    private let connection: NWConnection
    init(_ connection: NWConnection) { self.connection = connection }

    func waitReady() async throws {
        connection.start(queue: .global())
        let flag = MockQRFlag()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready, .failed, .cancelled: if flag.trySet() { cont.resume() }
                default: break
                }
            }
        }
        connection.stateUpdateHandler = nil
        guard connection.state == .ready else { throw DICOMNetworkError.connectionClosed }
    }

    func cancel() { connection.cancel() }

    func send(_ pdu: any PDU) async throws {
        let data = try pdu.encode()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    func receivePDU() async throws -> any PDU {
        let header = try await receive(6)
        let (_, length) = try PDUDecoder.readHeader(from: header)
        let body = try await receive(Int(length))
        return try PDUDecoder.decode(from: header + body)
    }

    private func receive(_ length: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: length, maximumLength: length) { data, _, _, error in
                if let error { cont.resume(throwing: error) }
                else if let data, data.count >= length { cont.resume(returning: data) }
                else { cont.resume(throwing: DICOMNetworkError.connectionClosed) }
            }
        }
    }
}
#endif
