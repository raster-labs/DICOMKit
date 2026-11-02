import Foundation
import XCTest
import DICOMCore
import DICOMKit
import DICOMNetwork
@testable import dicom_server
#if canImport(Network)
import Network

/// Bounded, event-driven barriers. No timing sleeps decide cancellation races.
actor CancellationGate {
    enum Event: Hashable, Sendable {
        case checkpoint(ServerSession.Checkpoint)
        case storeArrived(Int)
    }
    private var seen: Set<Event> = []
    private var blocked: Set<Event>
    private var pauses: [Event: CheckedContinuation<Void, Error>] = [:]
    private var observers: [UUID: (Event, CheckedContinuation<Void, Error>)] = [:]
    init(blocked: Set<Event> = []) { self.blocked = blocked }

    func hit(_ event: Event) async throws {
        seen.insert(event)
        let ready = observers.filter { $0.value.0 == event }
        for (id, pair) in ready { observers.removeValue(forKey: id); pair.1.resume() }
        guard blocked.contains(event) else { return }
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { pauses[event] = $0 }
        } onCancel: { Task { await self.release(event) } }
    }
    func wait(_ event: Event) async throws {
        if seen.contains(event) { return }
        let id = UUID()
        let timeout = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled { await self.expire(id) }
        }
        defer { timeout.cancel() }
        try await withCheckedThrowingContinuation { observers[id] = (event, $0) }
    }
    private func expire(_ id: UUID) {
        observers.removeValue(forKey: id)?.1.resume(throwing: DICOMNetworkError.timeout)
    }
    func release(_ event: Event) {
        blocked.remove(event)
        pauses.removeValue(forKey: event)?.resume()
    }
    func releaseAll() {
        blocked.removeAll()
        let values = pauses.values; pauses.removeAll()
        for value in values { value.resume() }
    }
}

private final class CancellationOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
}

func cancellationListenerReady(_ listener: NWListener) async throws {
    let once = CancellationOnce()
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: if once.claim() { continuation.resume() }
            case .failed(let error): if once.claim() { continuation.resume(throwing: error) }
            case .cancelled: if once.claim() { continuation.resume(throwing: DICOMNetworkError.connectionClosed) }
            default: break
            }
        }
        listener.start(queue: .global(qos: .userInitiated))
        // A bounded listener gate turns unavailable loopback into an explicit failure.
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            if once.claim() { listener.cancel(); continuation.resume(throwing: DICOMNetworkError.timeout) }
        }
    }
    listener.stateUpdateHandler = nil
}

/// Real ServerSession with deterministic synthetic files, not a mock DIMSE implementation.
actor CancellationSessionPeer {
    static let ct = "1.2.840.10008.5.1.4.1.1.2"
    static let study = "2.25.401"
    static let series = "2.25.401.1"
    let directory: URL
    let gate: CancellationGate
    private let settlementTimeout: TimeInterval
    private let storage: StorageManager
    private let database: DatabaseManager
    private var listener: NWListener?
    private var sessions: [ServerSession] = []
    private(set) var port: UInt16 = 0

    init(gate: CancellationGate, settlementTimeout: TimeInterval = 30) throws {
        self.gate = gate
        self.settlementTimeout = settlementTimeout
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("m4-cancel-\(UUID().uuidString)")
        storage = try StorageManager(dataDirectory: directory.path)
        database = try DatabaseManager(connectionString: "")
    }
    func start(instanceCount: Int = 5, destinationPort: UInt16 = 1) async throws {
        try await database.initialize()
        for index in 1...instanceCount {
            let uid = Self.series + ".\(index)"
            var data = DataSet()
            data.setString(Self.ct, for: .sopClassUID, vr: .UI)
            data.setString(uid, for: .sopInstanceUID, vr: .UI)
            data.setString(Self.study, for: .studyInstanceUID, vr: .UI)
            data.setString(Self.series, for: .seriesInstanceUID, vr: .UI)
            data.setString("CANCEL^SYNTHETIC", for: .patientName, vr: .PN)
            data.setString("M4", for: .patientID, vr: .LO)
            data.setString("CT", for: .modality, vr: .CS)
            data.setString("\(index)", for: .instanceNumber, vr: .IS)
            let stored = try await storage.storeReceived(dataSetData: ServerProtocol.encodeDataSet(data,
                transferSyntaxUID: explicitVRLittleEndianTransferSyntaxUID), sopClassUID: Self.ct,
                sopInstanceUID: uid, transferSyntaxUID: explicitVRLittleEndianTransferSyntaxUID,
                serverAETitle: "M4SCP", callingAETitle: "M4FIXTURE")
            try await database.index(filePath: stored.filePath, metadata: DICOMMetadata(dataSet: stored.dataSet,
                filePath: stored.filePath, sopInstanceUID: uid, sopClassUID: Self.ct,
                transferSyntaxUID: explicitVRLittleEndianTransferSyntaxUID))
        }
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.accept(connection, destinationPort: destinationPort) }
        }
        try await cancellationListenerReady(listener)
        port = listener.port!.rawValue
    }
    private func accept(_ connection: NWConnection, destinationPort: UInt16) {
        let configuration = ServerConfiguration(aeTitle: "M4SCP", port: port, dataDirectory: directory.path,
            databaseURL: "", knownDestinations: ["M4DEST": DestinationAE(host: "127.0.0.1", port: destinationPort, aeTitle: "M4DEST")])
        let session = ServerSession(id: UUID(), connection: connection, configuration: configuration,
            storage: storage, database: database, statistics: ServerStatistics(), logger: try! ServerLogger(),
            testHooks: .init(checkpoint: { [gate] in try await gate.hit(.checkpoint($0)) }, cancellationSettlementTimeout: settlementTimeout))
        sessions.append(session)
        Task { await session.start() }
    }
    func stop() async {
        listener?.cancel()
        for session in sessions { await session.cancel() }
        await gate.releaseAll()
        for session in sessions { await session.waitForPendingRequests() }
        sessions.removeAll()
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Test SCU captures the original Command/Data PDV payloads, not re-encoded commands.
actor CancellationTestClient {
    struct WireMessage: Sendable {
        let command: Data
        let identifier: Data?
        let contextID: UInt8
    }
    let association: Association
    private let assembler = MessageAssembler()
    private var messages: [AssembledMessage] = []
    private var commandBytes = Data()
    private var identifierBytes = Data()
    private(set) var wireMessages: [WireMessage] = []
    init(port: UInt16) throws {
        association = Association(configuration: AssociationConfiguration(callingAETitle: try AETitle("M4SCU"),
            calledAETitle: try AETitle("M4SCP"), host: "127.0.0.1", port: port,
            implementationClassUID: "2.25.400", timeout: 5))
    }
    func connect() async throws {
        let syntaxes = [explicitVRLittleEndianTransferSyntaxUID]
        _ = try await association.request(presentationContexts: [
            try PresentationContext(id: 1, abstractSyntax: "1.2.840.10008.1.1", transferSyntaxes: syntaxes),
            try PresentationContext(id: 3, abstractSyntax: "1.2.840.10008.5.1.4.1.2.2.1", transferSyntaxes: syntaxes),
            try PresentationContext(id: 5, abstractSyntax: "1.2.840.10008.5.1.4.1.2.2.2", transferSyntaxes: syntaxes),
            try PresentationContext(id: 7, abstractSyntax: "1.2.840.10008.5.1.4.1.2.2.3", transferSyntaxes: syntaxes),
            try PresentationContext(id: 9, abstractSyntax: CancellationSessionPeer.ct, transferSyntaxes: syntaxes)
        ], roleSelections: [SCPSCURoleSelection.both(CancellationSessionPeer.ct)])
    }
    func send(_ command: CommandSet, data: Data? = nil, context: UInt8, tail: CommandSet? = nil) async throws {
        let pdus = MessageFragmenter(maxPDUSize: 16384).fragmentMessage(commandSet: command, dataSet: data, presentationContextID: context)
        var pdvs = pdus.flatMap(\.presentationDataValues)
        if let tail {
            pdvs += MessageFragmenter(maxPDUSize: 16384).fragmentMessage(commandSet: tail, dataSet: nil, presentationContextID: context).flatMap(\.presentationDataValues)
        }
        try await association.send(pdvs: pdvs)
    }
    func cancel(_ id: UInt16, context: UInt8) async throws {
        try await send(CCancelRequest(messageIDBeingCancelled: id, presentationContextID: context).commandSet, context: context)
    }
    func receive() async throws -> AssembledMessage {
        if !messages.isEmpty { return messages.removeFirst() }
        return try await withThrowingTaskGroup(of: AssembledMessage.self) { group in
            group.addTask { try await self.readMessage() }
            group.addTask { try await Task.sleep(nanoseconds: 5_000_000_000); throw DICOMNetworkError.timeout }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
    private func readMessage() async throws -> AssembledMessage {
        while true {
            let pdu = try await association.receive()
            for pdv in pdu.presentationDataValues {
                if pdv.isCommand { commandBytes.append(pdv.data) } else { identifierBytes.append(pdv.data) }
                if let message = try assembler.addPDV(pdv) {
                    wireMessages.append(.init(command: commandBytes, identifier: identifierBytes.isEmpty ? nil : identifierBytes,
                        contextID: message.presentationContextID))
                    commandBytes = Data(); identifierBytes = Data(); messages.append(message)
                }
            }
            if !messages.isEmpty { return messages.removeFirst() }
        }
    }
    func release() async throws { try await association.release() }
    func abort() async { try? await association.abort() }
    func saveEvidence(_ name: String) throws {
        guard let folder = ProcessInfo.processInfo.environment["DICOMKIT_M4_CAPTURE_DIR"] else { return }
        let directory = URL(fileURLWithPath: folder).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (index, wire) in wireMessages.enumerated() {
            let base = directory.appendingPathComponent(String(format: "response-%03d", index + 1))
            try wire.command.write(to: base.appendingPathExtension("command.bin"))
            try wire.identifier?.write(to: base.appendingPathExtension("identifier.bin"))
        }
    }
}

/// Delayed, scriptable Storage SCP for MOVE. The real server opens separate
/// associations and sends complete C-STORE requests; the fixture controls status.
actor CancellationStoragePeer {
    let statuses: [UInt16]
    let gate: CancellationGate
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private(set) var port: UInt16 = 0
    private(set) var storedUIDs: [String] = []
    init(statuses: [UInt16], gate: CancellationGate) { self.statuses = statuses; self.gate = gate }
    func start() async throws {
        let listener = try NWListener(using: .tcp, on: .any); self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in Task { await self?.serve(connection) } }
        try await cancellationListenerReady(listener); port = listener.port!.rawValue
    }
    func stop() { listener?.cancel(); connections.forEach { $0.cancel() } }
    private func serve(_ connection: NWConnection) async {
        connections.append(connection)
        connection.start(queue: .global(qos: .userInitiated))
        let assembler = MessageAssembler()
        do {
            while true {
                let header = try await receive(6, from: connection)
                let (_, length) = try PDUDecoder.readHeader(from: header)
                let body = try await receive(Int(length), from: connection)
                let pdu = try PDUDecoder.decode(from: header + body)
                if let request = pdu as? AssociateRequestPDU {
                    let negotiation = ServerProtocol.negotiate(presentationContexts: request.presentationContexts, roleSelections: [])
                    try await send(AssociateAcceptPDU(calledAETitle: request.calledAETitle, callingAETitle: request.callingAETitle,
                        presentationContexts: negotiation.results, maxPDUSize: 16384,
                        implementationClassUID: "2.25.402").encode(), to: connection)
                } else if let data = pdu as? DataTransferPDU {
                    for pdv in data.presentationDataValues {
                        if let message = try assembler.addPDV(pdv), let store = message.asCStoreRequest() {
                            storedUIDs.append(store.affectedSOPInstanceUID)
                            let index = storedUIDs.count
                            try await gate.hit(.storeArrived(index))
                            let status = DIMSEStatus.from(statuses[min(index - 1, statuses.count - 1)])
                            let response = CStoreResponse(messageIDBeingRespondedTo: store.messageID,
                                affectedSOPClassUID: store.affectedSOPClassUID, affectedSOPInstanceUID: store.affectedSOPInstanceUID,
                                status: status, presentationContextID: message.presentationContextID)
                            for pdu in MessageFragmenter(maxPDUSize: 16384).fragmentMessage(commandSet: response.commandSet,
                                dataSet: nil, presentationContextID: message.presentationContextID) {
                                try await send(pdu.encode(), to: connection)
                            }
                        }
                    }
                } else if pdu is ReleaseRequestPDU {
                    try await send(ReleaseResponsePDU().encode(), to: connection); break
                } else if pdu is AbortPDU { break }
            }
        } catch { /* The test's request/response assertions diagnose transport failures. */ }
        connection.cancel()
    }
    private func receive(_ length: Int, from connection: NWConnection) async throws -> Data {
        if length == 0 { return Data() }
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: length, maximumLength: length) { data, _, _, error in
                if let error { continuation.resume(throwing: error) }
                else if let data, data.count == length { continuation.resume(returning: data) }
                else { continuation.resume(throwing: DICOMNetworkError.connectionClosed) }
            }
        }
    }
    private func send(_ data: Data, to connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }
}
#endif
