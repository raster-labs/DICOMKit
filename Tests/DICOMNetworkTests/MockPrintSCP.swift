//
// MockPrintSCP.swift
// DICOMNetworkTests
//
// In-process, scriptable DICOM Print SCP for integration tests
// (enhancement plan P3-4 / Milestone D).
//
// Implements just enough of PS3.4 Annex H to exercise the SCU:
// A-ASSOCIATE accept/reject, N-GET (printer status), N-CREATE (film
// session / film box with Referenced Image Box Sequence), N-SET,
// N-ACTION (print → job UID), N-DELETE, A-RELEASE — with scriptable
// failure injection, silence (for timeout tests), and an optional
// pushed N-EVENT-REPORT.
//

import Foundation
import DICOMCore
@testable import DICOMNetwork

#if canImport(Network)
import Network

/// Once-only flag guarding continuation resumes across NW state callbacks.
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isSet = false

    func trySet() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !isSet else { return false }
        isSet = true
        return true
    }
}

/// Scriptable behavior for a `MockPrintSCP` run.
struct MockPrintSCPBehavior: Sendable {
    /// Fail the first DIMSE request of this kind with `failStatus`/`errorComment`.
    var failOn: DIMSECommand? = nil
    var failStatus: DIMSEStatus = .failedUnableToProcess
    var errorComment: String? = nil
    var errorID: UInt16? = nil

    /// Accept the association, then never answer any DIMSE request (timeout tests).
    var silentAfterAccept: Bool = false

    /// Reject every proposed presentation context (zero-context tests).
    var rejectAllContexts: Bool = false

    /// Accept only Implicit VR LE (implicit-only printer emulation, P1-3 full).
    var acceptOnlyImplicitVR: Bool = false

    /// Printer status returned by N-GET (2110,0010 / 0020 / 0030).
    var printerStatus: String = "NORMAL"
    var printerStatusInfo: String? = nil
    var printerName: String? = "MOCK-PRINTER"

    /// Omit the Referenced Print Job Sequence (2100,0500) — and with it the
    /// data set — from the N-ACTION response, as a printer without Print Job
    /// support does (PS3.4 Table H.4-8, "-/MC").
    var omitPrintJobUID: Bool = false

    /// Answer the Printer N-GET with no data set at all.
    var omitPrinterStatusDataSet: Bool = false

    /// Push a Printer SOP Class N-EVENT-REPORT (WARNING) immediately before
    /// responding to the first film-session N-CREATE (interleave test).
    var pushEventBeforeFirstResponse: Bool = false

    /// Push an N-EVENT-REPORT after receiving A-RELEASE-RQ, before sending
    /// A-RELEASE-RP (release-window test, plan P2-7).
    var pushEventDuringRelease: Bool = false
}

/// Minimal in-process Print SCP. One instance handles any number of
/// sequential associations; counters record what the SCU actually did.
actor MockPrintSCP {
    let behavior: MockPrintSCPBehavior

    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private(set) var associationCount = 0
    private(set) var commandLog: [DIMSECommand] = []
    private(set) var releasedCleanly = false

    private var didInjectFailure = false
    private var didPushEvent = false
    private var filmBoxCounter = 0
    private var handlerTasks: [Task<Void, Never>] = []

    init(behavior: MockPrintSCPBehavior = MockPrintSCPBehavior()) {
        self.behavior = behavior
    }

    // MARK: - Lifecycle

    func start() async throws {
        let parameters = NWParameters.tcp
        let listener = try NWListener(using: parameters, on: .any)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            guard let self = self else { return }
            Task { await self.handle(connection: connection) }
        }

        let resumed = LockedFlag()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard resumed.trySet() else { return }
                    cont.resume()
                case .failed(let error):
                    guard resumed.trySet() else { return }
                    cont.resume(throwing: error)
                case .cancelled:
                    guard resumed.trySet() else { return }
                    cont.resume(throwing: DICOMNetworkError.connectionClosed)
                default:
                    break
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
        }
        listener.stateUpdateHandler = nil
        port = listener.port?.rawValue ?? 0
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for task in handlerTasks { task.cancel() }
        handlerTasks.removeAll()
    }

    // MARK: - Connection handling

    private func handle(connection: NWConnection) {
        associationCount += 1
        let task = Task { [behavior] in
            let peer = MockPrintSCPConnection(connection: connection, behavior: behavior, owner: self)
            await peer.run()
        }
        handlerTasks.append(task)
    }

    // Callbacks from the per-connection handler.
    func record(command: DIMSECommand) { commandLog.append(command) }
    func recordCleanRelease() { releasedCleanly = true }
    func nextFilmBoxIndex() -> Int { filmBoxCounter += 1; return filmBoxCounter }
    func shouldInjectFailure(for command: DIMSECommand) -> Bool {
        guard behavior.failOn == command, !didInjectFailure else { return false }
        didInjectFailure = true
        return true
    }
    func shouldPushEvent() -> Bool {
        guard behavior.pushEventBeforeFirstResponse, !didPushEvent else { return false }
        didPushEvent = true
        return true
    }
}

/// Per-connection protocol machine for `MockPrintSCP`.
private final class MockPrintSCPConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let behavior: MockPrintSCPBehavior
    private let owner: MockPrintSCP
    private var assembler = MessageAssembler()
    private var maxPDUSize: UInt32 = 16384
    private var negotiatedExplicitVR = true

    init(connection: NWConnection, behavior: MockPrintSCPBehavior, owner: MockPrintSCP) {
        self.connection = connection
        self.behavior = behavior
        self.owner = owner
    }

    func run() async {
        connection.start(queue: .global(qos: .userInitiated))
        let resumed = LockedFlag()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready, .failed, .cancelled:
                    guard resumed.trySet() else { return }
                    cont.resume()
                default:
                    break
                }
            }
        }
        connection.stateUpdateHandler = nil
        guard connection.state == .ready else { return }

        do {
            try await acceptAssociation()
            try await messageLoop()
        } catch {
            connection.cancel()
        }
    }

    // MARK: Association

    private func acceptAssociation() async throws {
        guard let request = try await receivePDU() as? AssociateRequestPDU else {
            throw DICOMNetworkError.unexpectedResponse
        }
        maxPDUSize = min(16384, request.maxPDUSize)

        let accepted: [AcceptedPresentationContext] = request.presentationContexts.map { context in
            if behavior.rejectAllContexts {
                return AcceptedPresentationContext(id: context.id, result: .abstractSyntaxNotSupported)
            }
            let ts: String?
            if behavior.acceptOnlyImplicitVR {
                ts = context.transferSyntaxes.first { $0 == implicitVRLittleEndianTransferSyntaxUID }
            } else {
                ts = context.transferSyntaxes.first
            }
            guard let selected = ts else {
                return AcceptedPresentationContext(id: context.id, result: .transferSyntaxesNotSupported)
            }
            self.negotiatedExplicitVR = selected != implicitVRLittleEndianTransferSyntaxUID
            return AcceptedPresentationContext(id: context.id, result: .acceptance, transferSyntax: selected)
        }

        let accept = AssociateAcceptPDU(
            calledAETitle: request.calledAETitle,
            callingAETitle: request.callingAETitle,
            presentationContexts: accepted,
            maxPDUSize: 16384,
            implementationClassUID: "1.2.826.0.1.3680043.9.7433.99.1",
            implementationVersionName: "MOCK_SCP"
        )
        try await send(pdu: accept)
    }

    // MARK: DIMSE loop

    private func messageLoop() async throws {
        while true {
            let pdu = try await receivePDU()
            switch pdu {
            case let dataPDU as DataTransferPDU:
                if let message = try assembler.addPDVs(from: dataPDU) {
                    assembler = MessageAssembler()
                    try await handle(message: message)
                }
            case _ as ReleaseRequestPDU:
                if behavior.pushEventDuringRelease {
                    // P2-7: a late event lands between A-RELEASE-RQ and
                    // A-RELEASE-RP — the SCU must discard it, not abort.
                    try await pushPrinterEvent(contextID: 1)
                }
                try await send(pdu: ReleaseResponsePDU())
                await owner.recordCleanRelease()
                connection.cancel()
                return
            case _ as AbortPDU:
                connection.cancel()
                return
            default:
                connection.cancel()
                return
            }
        }
    }

    private func handle(message: AssembledMessage) async throws {
        guard let command = message.commandSet.command else { return }
        await owner.record(command: command)

        if behavior.silentAfterAccept {
            return // swallow the request — the SCU's timeout must fire
        }

        // N-EVENT-REPORT-RSP acknowledgements from the SCU need no reply.
        if command == .nEventReportResponse { return }

        let contextID = message.presentationContextID
        let messageID = message.commandSet.messageID ?? 0
        let sopClass = message.commandSet.affectedSOPClassUID
            ?? message.commandSet.requestedSOPClassUID ?? ""
        let sopInstance = message.commandSet.affectedSOPInstanceUID
            ?? message.commandSet.requestedSOPInstanceUID ?? ""

        if await owner.shouldInjectFailure(for: command) {
            try await sendFailure(for: command, messageID: messageID,
                                  sopClass: sopClass, sopInstance: sopInstance,
                                  contextID: contextID)
            return
        }

        switch command {
        case .nGetRequest:
            try await respondPrinterStatus(messageID: messageID, contextID: contextID)

        case .nCreateRequest where sopClass == basicFilmSessionSOPClassUID:
            if await owner.shouldPushEvent() {
                try await pushPrinterEvent(contextID: contextID)
            }
            let response = NCreateResponse(
                messageIDBeingRespondedTo: messageID,
                affectedSOPClassUID: sopClass,
                affectedSOPInstanceUID: "1.2.826.0.1.3680043.9.mock.session.1",
                status: .success,
                hasDataSet: false,
                presentationContextID: contextID
            )
            try await send(commandSet: response.commandSet, dataSet: nil, contextID: contextID)

        case .nCreateRequest where sopClass == basicFilmBoxSOPClassUID:
            let boxIndex = await owner.nextFilmBoxIndex()
            let imageBoxCount = imageBoxCount(fromFilmBoxRequest: message.dataSet,
                                              explicitVR: negotiatedExplicitVR)
            let uids = (1...imageBoxCount).map {
                "1.2.826.0.1.3680043.9.mock.imagebox.\(boxIndex).\($0)"
            }
            let response = NCreateResponse(
                messageIDBeingRespondedTo: messageID,
                affectedSOPClassUID: sopClass,
                affectedSOPInstanceUID: "1.2.826.0.1.3680043.9.mock.filmbox.\(boxIndex)",
                status: .success,
                hasDataSet: true,
                presentationContextID: contextID
            )
            try await send(commandSet: response.commandSet,
                           dataSet: referencedImageBoxSequence(uids: uids),
                           contextID: contextID)

        case .nCreateRequest:
            // Presentation LUT or other instances — succeed with a generated UID.
            let response = NCreateResponse(
                messageIDBeingRespondedTo: messageID,
                affectedSOPClassUID: sopClass,
                affectedSOPInstanceUID: "1.2.826.0.1.3680043.9.mock.other.1",
                status: .success,
                hasDataSet: false,
                presentationContextID: contextID
            )
            try await send(commandSet: response.commandSet, dataSet: nil, contextID: contextID)

        case .nSetRequest:
            let response = NSetResponse(
                messageIDBeingRespondedTo: messageID,
                affectedSOPClassUID: sopClass,
                affectedSOPInstanceUID: sopInstance,
                status: .success,
                hasDataSet: false,
                presentationContextID: contextID
            )
            try await send(commandSet: response.commandSet, dataSet: nil, contextID: contextID)

        case .nActionRequest:
            // PS3.7 N-ACTION-RSP: Affected SOP Class / Instance are the Film
            // Box (or Film Session) the action was invoked on. The Print Job
            // is named in the data set by Referenced Print Job Sequence
            // (2100,0500) — PS3.4 Table H.4-8 — unless this printer has no
            // Print Job support, in which case there is no data set at all.
            let dataSet: Data? = behavior.omitPrintJobUID
                ? nil
                : PrintSCPEncoder.printJobReference(
                    printJobUID: "1.2.826.0.1.3680043.9.mock.job.1",
                    explicitVR: negotiatedExplicitVR)
            let response = NActionResponse(
                messageIDBeingRespondedTo: messageID,
                affectedSOPClassUID: sopClass,
                affectedSOPInstanceUID: sopInstance,
                actionTypeID: 1,
                status: .success,
                hasDataSet: dataSet != nil,
                presentationContextID: contextID
            )
            try await send(commandSet: response.commandSet, dataSet: dataSet, contextID: contextID)

        case .nDeleteRequest:
            let response = NDeleteResponse(
                messageIDBeingRespondedTo: messageID,
                affectedSOPClassUID: sopClass,
                affectedSOPInstanceUID: sopInstance,
                status: .success,
                presentationContextID: contextID
            )
            try await send(commandSet: response.commandSet, dataSet: nil, contextID: contextID)

        default:
            break
        }
    }

    // MARK: Responses

    private func sendFailure(
        for command: DIMSECommand,
        messageID: UInt16,
        sopClass: String,
        sopInstance: String,
        contextID: UInt8
    ) async throws {
        var cmd = CommandSet()
        switch command {
        case .nGetRequest: cmd.setCommand(.nGetResponse)
        case .nCreateRequest: cmd.setCommand(.nCreateResponse)
        case .nSetRequest: cmd.setCommand(.nSetResponse)
        case .nActionRequest: cmd.setCommand(.nActionResponse)
        case .nDeleteRequest: cmd.setCommand(.nDeleteResponse)
        default: cmd.setCommand(.nSetResponse)
        }
        cmd.setMessageIDBeingRespondedTo(messageID)
        cmd.setAffectedSOPClassUID(sopClass)
        if !sopInstance.isEmpty { cmd.setAffectedSOPInstanceUID(sopInstance) }
        cmd.setStatus(behavior.failStatus)
        cmd.setHasDataSet(false)
        if let comment = behavior.errorComment { cmd.setErrorComment(comment) }
        if let id = behavior.errorID { cmd.setErrorID(id) }
        try await send(commandSet: cmd, dataSet: nil, contextID: contextID)
    }

    private func respondPrinterStatus(messageID: UInt16, contextID: UInt8) async throws {
        if behavior.omitPrinterStatusDataSet {
            let response = NGetResponse(
                messageIDBeingRespondedTo: messageID,
                affectedSOPClassUID: printerSOPClassUID,
                affectedSOPInstanceUID: printerSOPInstanceUID,
                status: .success,
                hasDataSet: false,
                presentationContextID: contextID
            )
            try await send(commandSet: response.commandSet, dataSet: nil, contextID: contextID)
            return
        }
        var elements: [DataElement] = [
            DataElement.string(tag: Tag(group: 0x2110, element: 0x0010), vr: .CS, value: behavior.printerStatus)
        ]
        if let info = behavior.printerStatusInfo {
            elements.append(DataElement.string(tag: Tag(group: 0x2110, element: 0x0020), vr: .CS, value: info))
        }
        if let name = behavior.printerName {
            elements.append(DataElement.string(tag: Tag(group: 0x2110, element: 0x0030), vr: .LO, value: name))
        }
        let writer = DICOMWriter(explicitVR: negotiatedExplicitVR)
        var dataSet = Data()
        for element in elements { dataSet.append(writer.serializeElement(element)) }

        let response = NGetResponse(
            messageIDBeingRespondedTo: messageID,
            affectedSOPClassUID: printerSOPClassUID,
            affectedSOPInstanceUID: printerSOPInstanceUID,
            status: .success,
            hasDataSet: true,
            presentationContextID: contextID
        )
        try await send(commandSet: response.commandSet, dataSet: dataSet, contextID: contextID)
    }

    private func pushPrinterEvent(contextID: UInt8) async throws {
        let request = NEventReportRequest(
            messageID: 999,
            affectedSOPClassUID: printerSOPClassUID,
            affectedSOPInstanceUID: printerSOPInstanceUID,
            eventTypeID: 2, // WARNING
            hasDataSet: false,
            presentationContextID: contextID
        )
        try await send(commandSet: request.commandSet, dataSet: nil, contextID: contextID)
    }

    // MARK: Encoding helpers

    /// Explicit VR LE Referenced Image Box Sequence (2010,0510) with one item
    /// per UID, each carrying Referenced SOP Instance UID (0008,1155).
    private func referencedImageBoxSequence(uids: [String]) -> Data {
        let explicitVR = negotiatedExplicitVR
        func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        func uiElement(_ value: String) -> Data {
            var v = value.data(using: .ascii)!
            if v.count % 2 != 0 { v.append(0x00) }
            var d = le16(0x0008) + le16(0x1155)
            if explicitVR {
                d.append(contentsOf: [0x55, 0x49]) // "UI"
                d += le16(UInt16(v.count))
            } else {
                d += le32(UInt32(v.count))
            }
            d += v
            return d
        }
        var items = Data()
        for uid in uids {
            let content = uiElement(uid)
            items += le16(0xFFFE) + le16(0xE000) + le32(UInt32(content.count)) + content
        }
        var d = le16(0x2010) + le16(0x0510)
        if explicitVR {
            d.append(contentsOf: [0x53, 0x51]) // "SQ"
            d += le16(0) // reserved
        }
        d += le32(UInt32(items.count)) + items
        return d
    }

    /// Rows × columns from the film-box N-CREATE's Image Display Format
    /// (2010,0010), "STANDARD\r,c"; defaults to 1.
    private func imageBoxCount(fromFilmBoxRequest dataSet: Data?, explicitVR: Bool) -> Int {
        guard let data = dataSet,
              let format = Self.extractString(from: data, group: 0x2010, element: 0x0010,
                                              explicitVR: explicitVR) else {
            return 1
        }
        let layout = DICOMPrintService.layout(fromImageDisplayFormat: format)
        return max(1, layout.rows * layout.columns)
    }

    /// Minimal Explicit VR LE walk for short-form string elements.
    private static func extractString(from data: Data, group: UInt16, element: UInt16,
                                      explicitVR: Bool = true) -> String? {
        var offset = 0
        let bytes = [UInt8](data)
        let longVRs: Set<String> = ["OB", "OD", "OF", "OL", "OW", "SQ", "UC", "UN", "UR", "UT"]
        func u16(_ i: Int) -> UInt16 { UInt16(bytes[i]) | (UInt16(bytes[i + 1]) << 8) }
        func u32(_ i: Int) -> UInt32 {
            UInt32(bytes[i]) | (UInt32(bytes[i + 1]) << 8)
                | (UInt32(bytes[i + 2]) << 16) | (UInt32(bytes[i + 3]) << 24)
        }
        while offset + 8 <= bytes.count {
            let g = u16(offset), e = u16(offset + 2)
            let headerSize: Int
            let length: Int
            if !explicitVR {
                length = Int(u32(offset + 4))
                headerSize = 8
            } else if longVRs.contains(String(bytes: bytes[(offset + 4)...(offset + 5)], encoding: .ascii) ?? "") {
                guard offset + 12 <= bytes.count else { return nil }
                length = Int(u32(offset + 8))
                headerSize = 12
            } else {
                length = Int(u16(offset + 6))
                headerSize = 8
            }
            guard length != 0xFFFF_FFFF, offset + headerSize + length <= bytes.count else { return nil }
            if g == group && e == element {
                let value = Data(bytes[(offset + headerSize)..<(offset + headerSize + length)])
                return String(data: value, encoding: .ascii)?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
            }
            offset += headerSize + length
        }
        return nil
    }

    // MARK: Transport

    private func send(commandSet: CommandSet, dataSet: Data?, contextID: UInt8) async throws {
        let fragmenter = MessageFragmenter(maxPDUSize: maxPDUSize)
        let pdus = fragmenter.fragmentMessage(
            commandSet: commandSet, dataSet: dataSet, presentationContextID: contextID)
        for pdu in pdus {
            try await send(pdu: pdu)
        }
    }

    private func send(pdu: any PDU) async throws {
        let data = try pdu.encode()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    cont.resume(throwing: DICOMNetworkError.connectionFailed(error.localizedDescription))
                } else {
                    cont.resume()
                }
            })
        }
    }

    private func receivePDU() async throws -> any PDU {
        let header = try await receive(length: 6)
        let (_, pduLength) = try PDUDecoder.readHeader(from: header)
        let body = try await receive(length: Int(pduLength))
        return try PDUDecoder.decode(from: header + body)
    }

    private func receive(length: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: length, maximumLength: length) { data, _, _, error in
                if let error = error {
                    cont.resume(throwing: DICOMNetworkError.connectionFailed(error.localizedDescription))
                } else if let data = data, data.count >= length {
                    cont.resume(returning: data)
                } else {
                    cont.resume(throwing: DICOMNetworkError.connectionClosed)
                }
            }
        }
    }
}

#endif
