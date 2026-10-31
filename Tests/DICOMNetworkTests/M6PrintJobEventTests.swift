import XCTest
import Foundation
import DICOMCore
@testable import DICOMNetwork

#if canImport(Network)

/// Raw DIMSE loopback tests: the client deliberately gives the film and the
/// optional Print Job different contexts/transfer syntaxes. Dataset bytes are
/// checked against literal encodings, not a round-trip through the same writer.
final class M6PrintJobEventTests: XCTestCase {
    private let calledAE = "M6PRINT"

    private func withPeer(
        filmExplicit: Bool = true,
        jobSyntax: String? = implicitVRLittleEndianTransferSyntaxUID,
        pushEvents: Bool = true,
        operation: (M6PrintEventSCU, DICOMPrintServer) async throws -> Void
    ) async throws {
        let server = DICOMPrintServer(configuration: PrintSCPConfiguration(
            aeTitle: try AETitle(calledAE), port: 0, printerName: "M6-PRINTER",
            associationIdleTimeout: 5, pushPrintJobEvents: pushEvents),
            delegate: CollectingPrintHandler())
        try await server.start()
        let peer = try M6PrintEventSCU(port: await server.boundPort, calledAE: calledAE,
                                      filmExplicit: filmExplicit, jobSyntax: jobSyntax)
        do {
            try await peer.connect()
            try await operation(peer, server)
            try await peer.release()
            await server.stop()
        } catch {
            await peer.abort()
            await server.stop()
            throw error
        }
    }

    private func checkRouting(filmExplicit: Bool, jobExplicit: Bool) async throws {
        try await withPeer(filmExplicit: filmExplicit,
                           jobSyntax: jobExplicit ? explicitVRLittleEndianTransferSyntaxUID : implicitVRLittleEndianTransferSyntaxUID) { peer, _ in
            let job = try await peer.createPrintedJob()
            let event = try await peer.receiveEvent()
            XCTAssertEqual(event.presentationContextID, 3)
            XCTAssertEqual(event.commandSet.command, .nEventReportRequest)
            XCTAssertEqual(event.commandSet.affectedSOPClassUID, printJobSOPClassUID)
            XCTAssertEqual(event.commandSet.affectedSOPInstanceUID, job.uid)
            XCTAssertEqual(event.commandSet.eventTypeID, 3)
            XCTAssertNotNil(event.commandSet.messageID)
            XCTAssertEqual(event.dataSet, Self.expectedEventBytes(explicitVR: jobExplicit))
            let before = try await peer.queryJob(job.uid)
            XCTAssertEqual(before.commandSet.status?.rawValue, 0x0000)
            // Class/instance/type fields are optional in N-EVENT-REPORT-RSP.
            try await peer.acknowledge(event, includeOptionalFields: false)
            let after = try await peer.queryJob(job.uid)
            XCTAssertEqual(after.commandSet.status?.rawValue, 0x0112)
            let printer = try await peer.queryPrinter()
            XCTAssertEqual(printer.commandSet.status?.rawValue, 0x0000)
        }
    }

    func testDoneEventUsesImplicitJobContextWhenFilmIsExplicit() async throws {
        try await checkRouting(filmExplicit: true, jobExplicit: false)
    }

    func testDoneEventUsesExplicitJobContextWhenFilmIsImplicit() async throws {
        try await checkRouting(filmExplicit: false, jobExplicit: true)
    }

    func testNoEventWhenPrintJobContextWasNotProposed() async throws {
        try await withPeer(jobSyntax: nil) { peer, _ in
            _ = try await peer.createPrintedJob()
            let printer = try await peer.queryPrinter()
            XCTAssertEqual(printer.commandSet.status?.rawValue, 0x0000)
            let events = await peer.eventsSeenWhileAwaitingResponses
            XCTAssertTrue(events.isEmpty, "No event may be sent on a meta context in place of Print Job")
        }
    }

    func testNoEventWhenPrintJobTransferSyntaxWasRejected() async throws {
        try await withPeer(jobSyntax: "1.2.840.10008.1.2.2") { peer, _ in
            let accepted = await peer.jobContextAccepted
            XCTAssertFalse(accepted)
            _ = try await peer.createPrintedJob()
            _ = try await peer.queryPrinter()
            let events = await peer.eventsSeenWhileAwaitingResponses
            XCTAssertTrue(events.isEmpty)
        }
    }

    func testDisabledEventsDoNotRetireTheCompletedJob() async throws {
        try await withPeer(pushEvents: false) { peer, _ in
            let job = try await peer.createPrintedJob()
            let response = try await peer.queryJob(job.uid)
            XCTAssertEqual(response.commandSet.status?.rawValue, 0x0000)
            let events = await peer.eventsSeenWhileAwaitingResponses
            XCTAssertTrue(events.isEmpty)
        }
    }

    func testStrayAndMalformedAcknowledgementsCannotDeleteTheJob() async throws {
        try await withPeer { peer, _ in
            let job = try await peer.createPrintedJob()
            let event = try await peer.receiveEvent()
            let eventID = try XCTUnwrap(event.commandSet.messageID)
            let invalid: [(UInt8, UInt16, String?, String?, UInt16?, UInt16?)] = [
                (1, eventID, printJobSOPClassUID, job.uid, 3, 0), // wrong accepted context
                (3, eventID &+ 1000, printJobSOPClassUID, job.uid, 3, 0),
                (3, eventID, printerSOPClassUID, job.uid, 3, 0),
                (3, eventID, printJobSOPClassUID, "1.2.826.0.1.3680043.10.543.6.999", 3, 0),
                (3, eventID, printJobSOPClassUID, job.uid, 1, 0), // wrong event type
                (3, eventID, printJobSOPClassUID, job.uid, 3, nil) // missing mandatory status
            ]
            for (context, id, sopClass, instance, type, status) in invalid {
                try await peer.sendAcknowledgement(contextID: context, messageID: id,
                    sopClass: sopClass, instance: instance, eventType: type, status: status)
                let response = try await peer.queryJob(job.uid)
                XCTAssertEqual(response.commandSet.status?.rawValue, 0x0000)
            }
            // PS3.7 10.1.1.1: Event Reply requires success and Event Type ID.
            let reply = Data([0, 0x21, 0x30, 0, 6, 0, 0, 0]) + Data("NORMAL".utf8)
            let malformedReplies: [(UInt16?, UInt16)] = [(nil, 0), (3, 0x0110)]
            for (type, status) in malformedReplies {
                try await peer.sendAcknowledgement(contextID: 3, messageID: eventID,
                    sopClass: printJobSOPClassUID, instance: job.uid, eventType: type, status: status,
                    dataSet: reply)
                let response = try await peer.queryJob(job.uid)
                XCTAssertEqual(response.commandSet.status?.rawValue, 0x0000)
            }
            try await peer.acknowledge(event)
            let deleted = try await peer.queryJob(job.uid)
            XCTAssertEqual(deleted.commandSet.status?.rawValue, 0x0112)
        }
    }

    func testFailedStatusIsStillATerminalEventConfirmation() async throws {
        try await withPeer { peer, _ in
            let job = try await peer.createPrintedJob()
            let event = try await peer.receiveEvent()
            try await peer.acknowledge(event, status: 0x0110, includeOptionalFields: false)
            let response = try await peer.queryJob(job.uid)
            XCTAssertEqual(response.commandSet.status?.rawValue, 0x0112,
                           "H.4.5.2.1.2 requires deletion after confirmation, including a failure response")
        }
    }

    func testConfirmationAndNextRequestInOnePDUAreBothHandled() async throws {
        try await withPeer { peer, _ in
            let job = try await peer.createPrintedJob()
            let event = try await peer.receiveEvent()
            let response = try await peer.acknowledgeAndQueryInOnePDU(event, jobUID: job.uid)
            XCTAssertEqual(response.commandSet.status?.rawValue, 0x0112)
            // A duplicated confirmation produces no response and cannot poison
            // the following request or prevent normal association release.
            let duplicate = try await peer.acknowledgeAndQueryInOnePDU(event, jobUID: job.uid)
            XCTAssertEqual(duplicate.commandSet.status?.rawValue, 0x0112)
        }
    }

    func testOutstandingEventsHaveDistinctIDsAndRetireOnlyTheirOwnJob() async throws {
        try await withPeer { peer, _ in
            let first = try await peer.createPrintedJob()
            let firstEvent = try await peer.receiveEvent()
            let second = try await peer.printFilm(first.filmUID)
            let secondEvent = try await peer.receiveEvent()
            XCTAssertNotEqual(firstEvent.commandSet.messageID, secondEvent.commandSet.messageID)
            XCTAssertNotEqual(first.uid, second.uid)
            try await peer.acknowledge(firstEvent)
            let removed = try await peer.queryJob(first.uid)
            let retained = try await peer.queryJob(second.uid)
            XCTAssertEqual(removed.commandSet.status?.rawValue, 0x0112)
            XCTAssertEqual(retained.commandSet.status?.rawValue, 0x0000)
            try await peer.acknowledge(secondEvent)
            let secondRemoved = try await peer.queryJob(second.uid)
            XCTAssertEqual(secondRemoved.commandSet.status?.rawValue, 0x0112)
        }
    }

    func testUnconfirmedJobSurvivesReleaseForLaterStatusQuery() async throws {
        try await withPeer { peer, server in
            let job = try await peer.createPrintedJob()
            _ = try await peer.receiveEvent()
            try await peer.release()
            let next = try M6PrintEventSCU(port: await server.boundPort, calledAE: "M6PRINT",
                                          filmExplicit: true, jobSyntax: explicitVRLittleEndianTransferSyntaxUID)
            do {
                try await next.connect()
                let response = try await next.queryJob(job.uid)
                XCTAssertEqual(response.commandSet.status?.rawValue, 0x0000)
                try await next.release()
            } catch {
                await next.abort()
                throw error
            }
        }
    }

    func testOnlyTerminalPrintJobEventsDeleteAfterConfirmation() {
        for type in [UInt16(0), 1, 2, 5] {
            XCTAssertFalse(PrintSCPAssociation.deletesPrintJobAfterConfirmation(
                sopClassUID: printJobSOPClassUID, eventTypeID: type))
        }
        for type in [UInt16(3), 4] {
            XCTAssertTrue(PrintSCPAssociation.deletesPrintJobAfterConfirmation(
                sopClassUID: printJobSOPClassUID, eventTypeID: type))
            XCTAssertFalse(PrintSCPAssociation.deletesPrintJobAfterConfirmation(
                sopClassUID: printerSOPClassUID, eventTypeID: type))
        }
    }

    private static func expectedEventBytes(explicitVR: Bool) -> Data {
        // Sorted tags: Film Session Label (2000,0050) LO, Execution Status Info
        // (2100,0030) CS, Printer Name (2110,0030) LO. All lengths are even.
        let headers: [[UInt8]] = explicitVR
            ? [[0, 0x20, 0x50, 0, 0x4C, 0x4F, 8, 0],
               [0, 0x21, 0x30, 0, 0x43, 0x53, 6, 0],
               [0x10, 0x21, 0x30, 0, 0x4C, 0x4F, 10, 0]]
            : [[0, 0x20, 0x50, 0, 8, 0, 0, 0],
               [0, 0x21, 0x30, 0, 6, 0, 0, 0],
               [0x10, 0x21, 0x30, 0, 10, 0, 0, 0]]
        var bytes = Data()
        for (header, value) in zip(headers, ["M6-EVENT", "NORMAL", "M6-PRINTER"]) {
            bytes.append(contentsOf: header)
            bytes.append(contentsOf: value.utf8)
        }
        return bytes
    }
}

private actor M6PrintEventSCU {
    struct Job: Sendable { let uid: String; let filmUID: String }
    private let association: Association
    private let filmExplicit: Bool
    private let jobSyntax: String?
    private var negotiated: NegotiatedAssociation!
    private var nextID: UInt16 = 100
    private let assembler = MessageAssembler()
    private var received: [AssembledMessage] = []
    private var released = false
    private(set) var eventsSeenWhileAwaitingResponses: [AssembledMessage] = []
    var jobContextAccepted: Bool { negotiated?.isContextAccepted(3) ?? false }

    init(port: UInt16, calledAE: String, filmExplicit: Bool, jobSyntax: String?) throws {
        self.filmExplicit = filmExplicit
        self.jobSyntax = jobSyntax
        association = Association(configuration: AssociationConfiguration(
            callingAETitle: try AETitle("M6EVENTSCU"), calledAETitle: try AETitle(calledAE),
            host: "127.0.0.1", port: port,
            implementationClassUID: PrintSCPConfiguration.defaultImplementationClassUID,
            timeout: 5))
    }

    func connect() async throws {
        var contexts = [try PresentationContext(id: 1,
            abstractSyntax: basicGrayscalePrintManagementMetaSOPClassUID,
            transferSyntaxes: [filmExplicit ? explicitVRLittleEndianTransferSyntaxUID : implicitVRLittleEndianTransferSyntaxUID])]
        if let jobSyntax {
            contexts.append(try PresentationContext(id: 3, abstractSyntax: printJobSOPClassUID,
                                                    transferSyntaxes: [jobSyntax]))
        }
        negotiated = try await association.request(presentationContexts: contexts)
    }

    func release() async throws {
        guard !released else { return }
        try await association.release()
        released = true
    }

    func abort() async { try? await association.abort() }

    private func readMessage() async throws -> AssembledMessage {
        while received.isEmpty {
            let association = association
            let pdu = try await withThrowingTaskGroup(of: DataTransferPDU.self) { group in
                group.addTask { try await association.receive() }
                group.addTask {
                    try await Task.sleep(for: .seconds(5))
                    throw DICOMNetworkError.timeout
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
            for pdv in pdu.presentationDataValues {
                if let message = try assembler.addPDV(pdv) { received.append(message) }
            }
        }
        return received.removeFirst()
    }

    private func fragments(_ command: CommandSet, dataSet: Data? = nil, contextID: UInt8) -> [PresentationDataValue] {
        MessageFragmenter(maxPDUSize: negotiated.maxPDUSize)
            .fragmentMessage(commandSet: command, dataSet: dataSet, presentationContextID: contextID)
            .flatMap(\.presentationDataValues)
    }

    private func send(_ command: CommandSet, dataSet: Data? = nil, contextID: UInt8) async throws {
        try await association.send(pdvs: fragments(command, dataSet: dataSet, contextID: contextID))
    }

    private func receiveResponse(to messageID: UInt16) async throws -> AssembledMessage {
        while true {
            let message = try await readMessage()
            if message.commandSet.command == .nEventReportRequest {
                eventsSeenWhileAwaitingResponses.append(message)
                continue
            }
            guard message.commandSet.messageIDBeingRespondedTo == messageID else {
                throw DICOMNetworkError.decodingFailed("Uncorrelated response in M6 event probe")
            }
            return message
        }
    }

    private func command(_ type: DIMSECommand, sopClass: String, instance: String? = nil) -> CommandSet {
        var result = CommandSet()
        result.setCommand(type)
        result.setMessageID(nextID)
        nextID += 1
        if type == .nCreateRequest {
            result.setAffectedSOPClassUID(sopClass)
        } else {
            result.setRequestedSOPClassUID(sopClass)
            if let instance { result.setRequestedSOPInstanceUID(instance) }
        }
        result.setHasDataSet(false)
        return result
    }

    private func request(_ command: CommandSet, dataSet: Data? = nil, contextID: UInt8 = 1) async throws -> AssembledMessage {
        try await send(command, dataSet: dataSet, contextID: contextID)
        return try await receiveResponse(to: command.messageID!)
    }

    private func create(sopClass: String, elements: [DataElement]) async throws -> AssembledMessage {
        var request = command(.nCreateRequest, sopClass: sopClass)
        request.setHasDataSet(true)
        let response = try await self.request(request, dataSet: PrintSCPEncoder.serialize(elements, explicitVR: filmExplicit))
        guard response.commandSet.status?.rawValue == 0 else {
            throw DICOMNetworkError.decodingFailed("M6 print fixture N-CREATE failed")
        }
        return response
    }

    func createPrintedJob() async throws -> Job {
        let session = try await create(sopClass: basicFilmSessionSOPClassUID,
            elements: [.string(tag: .filmSessionLabel, vr: .LO, value: "M6-EVENT")])
        let sessionUID = try XCTUnwrap(session.commandSet.affectedSOPInstanceUID)
        let reference = SequenceItem(elements: [
            .string(tag: .referencedSOPClassUID, vr: .UI, value: basicFilmSessionSOPClassUID),
            .string(tag: .referencedSOPInstanceUID, vr: .UI, value: sessionUID)])
        let film = try await create(sopClass: basicFilmBoxSOPClassUID, elements: [
            .string(tag: .imageDisplayFormat, vr: .ST, value: "STANDARD\\1,1"),
            DataElement(tag: .referencedFilmSessionSequence, vr: .SQ, length: 0, valueData: Data(), sequenceItems: [reference])])
        let filmUID = try XCTUnwrap(film.commandSet.affectedSOPInstanceUID)
        let fields = try PrintDatasetReader(explicitVR: filmExplicit).parse(try XCTUnwrap(film.dataSet))
        let imageUID = try XCTUnwrap(fields.firstItem(of: .referencedImageBoxSequence)?.string(for: .referencedSOPInstanceUID))
        let pixels = SequenceItem(elements: [
            .uint16(tag: .samplesPerPixel, value: 1),
            .string(tag: .photometricInterpretation, vr: .CS, value: "MONOCHROME2"),
            .uint16(tag: .rows, value: 2), .uint16(tag: .columns, value: 2),
            .uint16(tag: .bitsAllocated, value: 8), .uint16(tag: .bitsStored, value: 8),
            .uint16(tag: .highBit, value: 7), .uint16(tag: .pixelRepresentation, value: 0),
            .data(tag: .pixelData, vr: .OB, data: Data([0, 64, 128, 255]))])
        var fill = command(.nSetRequest, sopClass: basicGrayscaleImageBoxSOPClassUID, instance: imageUID)
        fill.setHasDataSet(true)
        let response = try await request(fill, dataSet: PrintSCPEncoder.serialize([
            .uint16(tag: .imageBoxPosition, value: 1),
            DataElement(tag: .preformattedGrayscaleImageSequence, vr: .SQ, length: 0, valueData: Data(), sequenceItems: [pixels])
        ], explicitVR: filmExplicit))
        guard response.commandSet.status?.rawValue == 0 else {
            throw DICOMNetworkError.decodingFailed("M6 print fixture N-SET failed")
        }
        return try await printFilm(filmUID)
    }

    func printFilm(_ uid: String) async throws -> Job {
        var action = command(.nActionRequest, sopClass: basicFilmBoxSOPClassUID, instance: uid)
        action.setActionTypeID(1)
        let response = try await request(action)
        guard response.commandSet.status?.rawValue == 0 else {
            throw DICOMNetworkError.decodingFailed("M6 print fixture N-ACTION failed")
        }
        let set = try PrintDatasetReader(explicitVR: filmExplicit).parse(try XCTUnwrap(response.dataSet))
        let jobUID = try XCTUnwrap(set.firstItem(of: .referencedPrintJobSequence)?.string(for: .referencedSOPInstanceUID))
        return Job(uid: jobUID, filmUID: uid)
    }

    func receiveEvent() async throws -> AssembledMessage {
        let message = try await readMessage()
        guard message.commandSet.command == .nEventReportRequest else {
            throw DICOMNetworkError.decodingFailed("Expected Print Job event")
        }
        return message
    }

    func queryJob(_ uid: String) async throws -> AssembledMessage {
        try await request(command(.nGetRequest, sopClass: printJobSOPClassUID, instance: uid), contextID: 3)
    }

    func queryPrinter() async throws -> AssembledMessage {
        try await request(command(.nGetRequest, sopClass: printerSOPClassUID, instance: printerSOPInstanceUID))
    }

    private func acknowledgement(messageID: UInt16, sopClass: String?, instance: String?, eventType: UInt16?, status: UInt16?) -> CommandSet {
        var response = CommandSet()
        response.setCommand(.nEventReportResponse)
        response.setMessageIDBeingRespondedTo(messageID)
        if let sopClass { response.setAffectedSOPClassUID(sopClass) }
        if let instance { response.setAffectedSOPInstanceUID(instance) }
        if let eventType { response.setEventTypeID(eventType) }
        if let status { response.setStatus(.from(status)) }
        response.setHasDataSet(false)
        return response
    }

    func sendAcknowledgement(contextID: UInt8, messageID: UInt16, sopClass: String?, instance: String?, eventType: UInt16?, status: UInt16?, dataSet: Data? = nil) async throws {
        var response = acknowledgement(messageID: messageID, sopClass: sopClass, instance: instance,
                                       eventType: eventType, status: status)
        response.setHasDataSet(dataSet != nil)
        try await send(response, dataSet: dataSet, contextID: contextID)
    }

    func acknowledge(_ event: AssembledMessage, status: UInt16 = 0, includeOptionalFields: Bool = true) async throws {
        try await sendAcknowledgement(contextID: event.presentationContextID,
            messageID: try XCTUnwrap(event.commandSet.messageID),
            sopClass: includeOptionalFields ? event.commandSet.affectedSOPClassUID : nil,
            instance: includeOptionalFields ? event.commandSet.affectedSOPInstanceUID : nil,
            eventType: includeOptionalFields ? event.commandSet.eventTypeID : nil, status: status)
    }

    func acknowledgeAndQueryInOnePDU(_ event: AssembledMessage, jobUID: String) async throws -> AssembledMessage {
        let ack = acknowledgement(messageID: try XCTUnwrap(event.commandSet.messageID),
            sopClass: event.commandSet.affectedSOPClassUID, instance: event.commandSet.affectedSOPInstanceUID,
            eventType: event.commandSet.eventTypeID, status: 0)
        let query = command(.nGetRequest, sopClass: printJobSOPClassUID, instance: jobUID)
        let pdvs = fragments(ack, contextID: event.presentationContextID) + fragments(query, contextID: 3)
        try await association.send(pdvs: pdvs)
        return try await receiveResponse(to: query.messageID!)
    }
}

#endif
