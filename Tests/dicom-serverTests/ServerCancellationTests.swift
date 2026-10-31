import Foundation
import XCTest
import DICOMCore
import DICOMKit
import DICOMNetwork
@testable import dicom_server
#if canImport(Network)

/// PS3.4 2026a C.4.1.3.1 / C.4.2.3.1 / C.4.3.3.1; PS3.7 9.3.2.3–9.3.4.3.
/// The server is real, barriers choose race boundaries, and assertions inspect
/// original DIMSE command/identifier bytes as well as decoded responses.
final class ServerCancellationTests: XCTestCase {
    private let findSOP = "1.2.840.10008.5.1.4.1.2.2.1"
    private let moveSOP = "1.2.840.10008.5.1.4.1.2.2.2"
    private let getSOP = "1.2.840.10008.5.1.4.1.2.2.3"

    private func identifier(level: String = "IMAGE") -> Data {
        var data = DataSet()
        data.setString(level, for: .queryRetrieveLevel, vr: .CS)
        data.setString(CancellationSessionPeer.study, for: .studyInstanceUID, vr: .UI)
        if level == "IMAGE" {
            data.setString(CancellationSessionPeer.series, for: .seriesInstanceUID, vr: .UI)
            data.setString("", for: .sopInstanceUID, vr: .UI)
        }
        return ServerProtocol.encodeDataSet(data, transferSyntaxUID: explicitVRLittleEndianTransferSyntaxUID)
    }
    private func find(_ id: UInt16) -> CommandSet {
        CFindRequest(messageID: id, affectedSOPClassUID: findSOP, presentationContextID: 3).commandSet
    }
    private func move(_ id: UInt16) -> CommandSet {
        CMoveRequest(messageID: id, affectedSOPClassUID: moveSOP, moveDestination: "M4DEST", presentationContextID: 5).commandSet
    }
    private func get(_ id: UInt16) -> CommandSet {
        CGetRequest(messageID: id, affectedSOPClassUID: getSOP, presentationContextID: 7).commandSet
    }
    private func withSession(_ name: String, gate: CancellationGate, destination: CancellationStoragePeer? = nil,
                             settlementTimeout: TimeInterval = 30, body: (CancellationTestClient) async throws -> Void) async throws {
        let peer = try CancellationSessionPeer(gate: gate, settlementTimeout: settlementTimeout)
        if let destination { try await destination.start() }
        try await peer.start(destinationPort: await destination?.port ?? 1)
        let client = try CancellationTestClient(port: await peer.port)
        do {
            try await client.connect()
            try await body(client)
            try await client.saveEvidence(name)
            try await client.release()
        } catch {
            try? await client.saveEvidence(name)
            await client.abort(); await gate.releaseAll(); await peer.stop(); await destination?.stop()
            throw error
        }
        await gate.releaseAll(); await peer.stop(); await destination?.stop()
    }
    private func echo(_ client: CancellationTestClient) async throws {
        try await client.send(CEchoRequest(messageID: 99, presentationContextID: 1).commandSet, context: 1)
        let response = try await client.receive()
        XCTAssertEqual(response.command, .cEchoResponse)
        XCTAssertEqual(response.commandSet.status?.rawValue, 0)
    }
    private func final(_ client: CancellationTestClient, command: DIMSECommand) async throws -> (AssembledMessage, Int) {
        var pending = 0
        for _ in 0..<12 {
            let message = try await client.receive()
            XCTAssertEqual(message.command, command)
            if message.commandSet.status?.isPending == true { pending += 1 } else { return (message, pending) }
        }
        throw DICOMNetworkError.timeout
    }
    private func checkWire(_ client: CancellationTestClient, command: UInt16, status: UInt16,
                           remaining: UInt16? = nil, completed: UInt16? = nil, failed: UInt16? = nil, warning: UInt16? = nil) async throws {
        let wire = await client.wireMessages
        let elements = try XCTUnwrap(wire.last.map { commandElements($0.command) })
        func value(_ tag: UInt32) -> UInt16? {
            guard let bytes = elements[tag], bytes.count == 2 else { return nil }
            return UInt16(bytes[0]) | UInt16(bytes[1]) << 8
        }
        XCTAssertEqual(value(0x00000100), command)
        XCTAssertEqual(value(0x00000900), status)
        XCTAssertEqual(value(0x00001020), remaining)
        XCTAssertEqual(value(0x00001021), completed)
        XCTAssertEqual(value(0x00001022), failed)
        XCTAssertEqual(value(0x00001023), warning)
    }
    /// Independent Implicit VR command reader; no production CommandSet decoder.
    private func commandElements(_ data: Data) -> [UInt32: Data] {
        let bytes = [UInt8](data)
        func u16(_ p: Int) -> UInt32 { UInt32(bytes[p]) | UInt32(bytes[p + 1]) << 8 }
        var result: [UInt32: Data] = [:]; var offset = 0
        while offset + 8 <= bytes.count {
            let tag = u16(offset) << 16 | u16(offset + 2)
            let length = Int(u16(offset + 4) | u16(offset + 6) << 16)
            offset += 8
            guard offset + length <= bytes.count else { XCTFail("Truncated command bytes"); return [:] }
            result[tag] = Data(bytes[offset..<(offset + length)]); offset += length
        }
        XCTAssertEqual(offset, bytes.count)
        return result
    }

    func testFindCancelBeforeFirstResultIncludingSamePDUMessages() async throws {
        let point = CancellationGate.Event.checkpoint(.beforeFindResult(messageID: 10, index: 0))
        let gate = CancellationGate(blocked: [point])
        try await withSession("find-before-first", gate: gate) { client in
            let cancel = CCancelRequest(messageIDBeingCancelled: 10, presentationContextID: 3).commandSet
            try await client.send(self.find(10), data: self.identifier(), context: 3, tail: cancel)
            try await gate.wait(.checkpoint(.cancelProcessed(messageID: 10, accepted: true)))
            await gate.release(point)
            let (response, pending) = try await self.final(client, command: .cFindResponse)
            XCTAssertEqual(pending, 0); XCTAssertNil(response.dataSet)
            try await self.checkWire(client, command: 0x8020, status: 0xFE00)
            try await self.echo(client)
        }
    }

    func testFindCancelMidStreamStopsAfterProcessedBoundary() async throws {
        let point = CancellationGate.Event.checkpoint(.beforeFindResult(messageID: 11, index: 1))
        let gate = CancellationGate(blocked: [point])
        try await withSession("find-midstream", gate: gate) { client in
            try await client.send(self.find(11), data: self.identifier(), context: 3)
            let first = try await client.receive(); XCTAssertTrue(first.commandSet.status?.isPending == true)
            try await gate.wait(point)
            try await client.cancel(11, context: 3)
            try await gate.wait(.checkpoint(.cancelProcessed(messageID: 11, accepted: true)))
            await gate.release(point)
            let (_, extra) = try await self.final(client, command: .cFindResponse)
            XCTAssertEqual(extra, 0, "Barrier is after the first complete send; none was in flight when cancel was processed")
            try await self.checkWire(client, command: 0x8020, status: 0xFE00)
            try await self.echo(client)
        }
    }

    func testWrongIDAndContextIgnoredAndLateCancelDoesNotPoisonReusedID() async throws {
        let point = CancellationGate.Event.checkpoint(.beforeFindResult(messageID: 12, index: 0))
        let gate = CancellationGate(blocked: [point])
        try await withSession("find-wrong-and-reused-id", gate: gate) { client in
            try await client.send(self.find(12), data: self.identifier(), context: 3)
            try await gate.wait(point)
            try await client.cancel(999, context: 3)
            try await gate.wait(.checkpoint(.cancelProcessed(messageID: 999, accepted: false)))
            try await client.cancel(12, context: 1)
            try await gate.wait(.checkpoint(.cancelProcessed(messageID: 12, accepted: false)))
            await gate.release(point)
            let (response, pending) = try await self.final(client, command: .cFindResponse)
            XCTAssertEqual(response.commandSet.status?.rawValue, 0); XCTAssertEqual(pending, 5)
            try await client.cancel(12, context: 3) // Completed; no C-CANCEL response should be sent.
            try await self.echo(client) // Ordering fence: reader consumed the late cancel.
            try await client.send(self.find(12), data: self.identifier(), context: 3)
            let (again, count) = try await self.final(client, command: .cFindResponse)
            XCTAssertEqual(again.commandSet.status?.rawValue, 0); XCTAssertEqual(count, 5)
        }
    }

    func testFindCancelAtCompletionRaceHasOneFinalResponse() async throws {
        let point = CancellationGate.Event.checkpoint(.beforeFinalResponse(messageID: 13))
        let gate = CancellationGate(blocked: [point])
        try await withSession("find-completion-race", gate: gate) { client in
            try await client.send(self.find(13), data: self.identifier(), context: 3)
            for _ in 0..<5 { let message = try await client.receive(); XCTAssertTrue(message.commandSet.status?.isPending == true) }
            try await gate.wait(point)
            try await client.cancel(13, context: 3)
            try await gate.wait(.checkpoint(.cancelProcessed(messageID: 13, accepted: true)))
            await gate.release(point)
            let (_, pending) = try await self.final(client, command: .cFindResponse)
            XCTAssertEqual(pending, 0)
            try await self.checkWire(client, command: 0x8020, status: 0xFE00)
            try await self.echo(client) // An extra final response would fail the echo assertion.
        }
    }

    func testMoveCancelBeforeFirstStoreReportsAllRemaining() async throws {
        let point = CancellationGate.Event.checkpoint(.beforeStore(messageID: 20, index: 0))
        let gate = CancellationGate(blocked: [point])
        let destination = CancellationStoragePeer(statuses: [0], gate: gate)
        try await withSession("move-before-first", gate: gate, destination: destination) { client in
            try await client.send(self.move(20), data: self.identifier(level: "STUDY"), context: 5)
            try await gate.wait(point); try await client.cancel(20, context: 5)
            try await gate.wait(.checkpoint(.cancelProcessed(messageID: 20, accepted: true)))
            await gate.release(point)
            let (response, _) = try await self.final(client, command: .cMoveResponse)
            XCTAssertNil(response.dataSet)
            try await self.checkWire(client, command: 0x8021, status: 0xFE00, remaining: 5, completed: 0, failed: 0, warning: 0)
            let stores = await destination.storedUIDs; XCTAssertTrue(stores.isEmpty)
            try await self.echo(client)
        }
    }

    func testMoveCancelDuringMixedStoreOutcomesPreservesCountersAndFailedUIDs() async throws {
        let gate = CancellationGate(blocked: [.storeArrived(3)])
        let destination = CancellationStoragePeer(statuses: [0, 0xB000, 0xA700, 0, 0], gate: gate)
        try await withSession("move-mixed-midstream", gate: gate, destination: destination) { client in
            try await client.send(self.move(21), data: self.identifier(level: "STUDY"), context: 5)
            try await gate.wait(.storeArrived(3))
            try await client.cancel(21, context: 5)
            try await gate.wait(.checkpoint(.cancelProcessed(messageID: 21, accepted: true)))
            await gate.release(.storeArrived(3))
            let (response, pending) = try await self.final(client, command: .cMoveResponse)
            XCTAssertEqual(pending, 2, "Two already-sent pending responses are valid before FE00")
            try await self.checkWire(client, command: 0x8021, status: 0xFE00, remaining: 2, completed: 1, failed: 1, warning: 1)
            let bytes = try XCTUnwrap(response.dataSet)
            let identifier = try ServerProtocol.decodeDataSet(bytes, transferSyntaxUID: explicitVRLittleEndianTransferSyntaxUID)
            XCTAssertEqual(identifier.strings(for: .failedSOPInstanceUIDList), [CancellationSessionPeer.series + ".3"])
            XCTAssertNil(identifier[.specificCharacterSet])
            // Independent byte check of the sole response Identifier attribute.
            XCTAssertEqual(Array(bytes.prefix(6)), [0x08, 0, 0x58, 0, 0x55, 0x49])
            XCTAssertEqual(String(data: bytes.dropFirst(8), encoding: .ascii)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")),
                           CancellationSessionPeer.series + ".3")
            let stores = await destination.storedUIDs; XCTAssertEqual(stores.count, 3)
            try await self.echo(client)
        }
    }

    func testCancelledMoveToSilentDestinationHasBoundedSettlementAndCleanup() async throws {
        let gate = CancellationGate(blocked: [.storeArrived(1)])
        let destination = CancellationStoragePeer(statuses: [0], gate: gate)
        try await withSession("move-silent-destination", gate: gate, destination: destination, settlementTimeout: 0.1) { client in
            try await client.send(self.move(23), data: self.identifier(level: "STUDY"), context: 5)
            try await gate.wait(.storeArrived(1))
            try await client.cancel(23, context: 5)
            try await gate.wait(.checkpoint(.cancelProcessed(messageID: 23, accepted: true)))
            // The Storage SCP deliberately never releases its response. The
            // cancellation deadline must abort that attempted store and finish.
            let (response, pending) = try await self.final(client, command: .cMoveResponse)
            XCTAssertEqual(pending, 0)
            try await self.checkWire(client, command: 0x8021, status: 0xFE00, remaining: 4, completed: 0, failed: 1, warning: 0)
            let identifier = try ServerProtocol.decodeDataSet(try XCTUnwrap(response.dataSet), transferSyntaxUID: explicitVRLittleEndianTransferSyntaxUID)
            XCTAssertEqual(identifier.strings(for: .failedSOPInstanceUIDList), [CancellationSessionPeer.series + ".1"])
            let stores = await destination.storedUIDs; XCTAssertEqual(stores.count, 1)
            try await self.echo(client)
        }
    }

    func testMoveWrongIDIgnoredAndCancelAtCompletionPreservesAllCompleted() async throws {
        let before = CancellationGate.Event.checkpoint(.beforeStore(messageID: 22, index: 0))
        let final = CancellationGate.Event.checkpoint(.beforeFinalResponse(messageID: 22))
        let gate = CancellationGate(blocked: [before, final])
        let destination = CancellationStoragePeer(statuses: [0], gate: gate)
        try await withSession("move-completion-race", gate: gate, destination: destination) { client in
            try await client.send(self.move(22), data: self.identifier(level: "STUDY"), context: 5)
            try await gate.wait(before); try await client.cancel(999, context: 5)
            try await gate.wait(.checkpoint(.cancelProcessed(messageID: 999, accepted: false)))
            await gate.release(before); try await gate.wait(final)
            try await client.cancel(22, context: 5)
            try await gate.wait(.checkpoint(.cancelProcessed(messageID: 22, accepted: true)))
            await gate.release(final)
            let (response, pending) = try await self.final(client, command: .cMoveResponse)
            XCTAssertEqual(pending, 4); XCTAssertNil(response.dataSet)
            try await self.checkWire(client, command: 0x8021, status: 0xFE00, remaining: 0, completed: 5, failed: 0, warning: 0)
            let stores = await destination.storedUIDs; XCTAssertEqual(stores.count, 5)
            try await self.echo(client)
        }
    }

    func testGetCancellationStillWaitsForActualStoreResponseAndAllowsReuse() async throws {
        let gate = CancellationGate()
        try await withSession("get-cancel-reuse", gate: gate) { client in
            try await client.send(self.get(30), data: self.identifier(level: "STUDY"), context: 7)
            let message = try await client.receive()
            let store = try XCTUnwrap(message.asCStoreRequest())
            try await client.cancel(30, context: 7)
            try await gate.wait(.checkpoint(.cancelProcessed(messageID: 30, accepted: true)))
            let response = CStoreResponse(messageIDBeingRespondedTo: store.messageID, affectedSOPClassUID: store.affectedSOPClassUID,
                affectedSOPInstanceUID: store.affectedSOPInstanceUID, status: .warningElementsDiscarded, presentationContextID: message.presentationContextID)
            try await client.send(response.commandSet, context: message.presentationContextID)
            let (done, pending) = try await self.final(client, command: .cGetResponse)
            XCTAssertEqual(pending, 0); XCTAssertNil(done.dataSet)
            try await self.checkWire(client, command: 0x8010, status: 0xFE00, remaining: 4, completed: 0, failed: 0, warning: 1)
            try await self.echo(client)
        }
    }

    func testGetDisconnectResumesOutstandingStoreWaiter() async throws {
        let gate = CancellationGate()
        let peer = try CancellationSessionPeer(gate: gate)
        try await peer.start()
        let client = try CancellationTestClient(port: await peer.port)
        do {
            try await client.connect()
            try await client.send(get(31), data: identifier(level: "STUDY"), context: 7)
            let message = try await client.receive(); XCTAssertEqual(message.command, .cStoreRequest)
            await client.abort()
            try await gate.wait(.checkpoint(.operationFinished(messageID: 31)))
            try await client.saveEvidence("get-disconnect-cleanup")
        } catch { await client.abort(); await peer.stop(); throw error }
        await peer.stop()
    }

    func testCancelledGetWithSilentStoreResponseFinishesAndAllowsReuse() async throws {
        let gate = CancellationGate()
        try await withSession("get-silent-response", gate: gate, settlementTimeout: 0.1) { client in
            try await client.send(self.get(32), data: self.identifier(level: "STUDY"), context: 7)
            let store = try await client.receive(); XCTAssertEqual(store.command, .cStoreRequest)
            try await client.cancel(32, context: 7)
            try await gate.wait(.checkpoint(.cancelProcessed(messageID: 32, accepted: true)))
            // No C-STORE-RSP: the initiated store fails when settlement expires.
            let (response, pending) = try await self.final(client, command: .cGetResponse)
            XCTAssertEqual(pending, 0)
            try await self.checkWire(client, command: 0x8010, status: 0xFE00, remaining: 4, completed: 0, failed: 1, warning: 0)
            let identifier = try ServerProtocol.decodeDataSet(try XCTUnwrap(response.dataSet), transferSyntaxUID: explicitVRLittleEndianTransferSyntaxUID)
            XCTAssertEqual(identifier.strings(for: .failedSOPInstanceUIDList), [CancellationSessionPeer.series + ".1"])
            try await self.echo(client)
        }
    }

    func testCancelledGetDuringIncompleteStoreSendClosesAndDrainsWorker() async throws {
        let point = CancellationGate.Event.checkpoint(.duringGetStoreSend(messageID: 33))
        let gate = CancellationGate(blocked: [point])
        let peer = try CancellationSessionPeer(gate: gate, settlementTimeout: 0.1)
        try await peer.start()
        let client = try CancellationTestClient(port: await peer.port)
        do {
            try await client.connect()
            try await client.send(get(33), data: identifier(level: "STUDY"), context: 7)
            // One C-STORE command fragment has been transmitted; its data set
            // is deliberately held, modelling a send blocked by a nonreader.
            try await gate.wait(point)
            try await client.cancel(33, context: 7)
            try await gate.wait(.checkpoint(.cancelProcessed(messageID: 33, accepted: true)))
            try await gate.wait(.checkpoint(.operationFinished(messageID: 33)))
            do {
                _ = try await client.receive()
                XCTFail("An incomplete store must close; FE00 cannot interrupt its data set")
            } catch let error as DICOMNetworkError {
                if case .timeout = error { XCTFail("Transport must close instead of reaching the receive timeout") }
            } catch { /* A closed Network.framework transport can report its native error. */ }
            let messages = await client.wireMessages
            XCTAssertTrue(messages.isEmpty, "No incomplete store or spliced final response may decode as a complete DIMSE message")
        } catch { await client.abort(); await peer.stop(); throw error }
        await client.abort(); await peer.stop()
    }
}
#endif
