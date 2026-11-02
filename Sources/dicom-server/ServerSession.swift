// NEMA-verified: 2026a, checked 2026-10-01 — UID literals and names are those of ServerProtocol (PS3.6 2026a Table A-1); A-ASSOCIATE-RJ result/source/reason 1/1/3 and 2/2/1 and presentation-context results 0/3/4 match PS3.8 2026a Tables 9-21 / 9-18; the A-ASSOCIATE-AC carries the server's Maximum Length and DICOMKit's Implementation Class UID and answers SCP/SCU Role Selection (PS3.8 D.1, PS3.7 D.3.3.2 / D.3.3.4) and outgoing P-DATA is fragmented to the peer's Maximum Length (D95); C-STORE stores PS3.10 files with the negotiated transfer syntax (D102); C-FIND / C-MOVE / C-GET fail with A900 when Query/Retrieve Level is missing (Tables C.4-1..C.4-3, D101); unknown Move Destination gets A801 (Table C.4-2, D96); C-GET sub-operations await each C-STORE-RSP and count Completed / Warning / Failed from its status, final status per C.4.3.3.1 (D97); failure statuses are the Cxxx / A7xx / A9xx rows of Tables B.2-1 and C.4-1..C.4-3; C-MOVE sub-operation C-STORE-RQs carry Move Originator AE Title / Message ID (0000,1030/1031) per PS3.7 9.1.1.1.6 / 9.1.1.1.7 (D156)
import Foundation
import DICOMCore
import DICOMKit
import DICOMNetwork

#if canImport(Network)
import Network

/// Server session handling a single client connection
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
actor ServerSession {
    let id: UUID
    private let connection: NWConnection
    private let configuration: ServerConfiguration
    private let storage: StorageManager
    private let database: DatabaseManager?
    private let statistics: ServerStatistics
    private let logger: ServerLogger
    private var isActive = false
    private var isEstablished = false
    private let messageAssembler = MessageAssembler()
    private var acceptedPresentationContexts: [UInt8: ServerProtocol.AcceptedContext] = [:]
    private var messageIDCounter: UInt16 = 0
    private var callingAETitle = ""
    /// Fragment size for outgoing P-DATA-TF: the peer's Maximum Length (PS3.8 D.1)
    private var outgoingMaxPDUSize: UInt32 = defaultMaxPDUSize
    /// One receive pump owns the socket. Request handlers are serialized in a
    /// separate actor task, so cancellation and C-STORE responses remain readable
    /// while a query/retrieve handler is suspended (PS3.7 9.3.2/9.3.3/9.3.4).
    private struct ActiveOperation {
        let messageID: UInt16
        let contextID: UInt8
        var cancelled = false
        var finalCommitted = false
    }
    private var activeOperation: ActiveOperation?
    private var requestQueue: [AssembledMessage] = []
    private var handlerTask: Task<Void, Never>?
    private var expectedStoreResponse: (messageID: UInt16, contextID: UInt8)?
    private var bufferedStoreResponse: DIMSEStatus?
    private var storeResponseWaiter: CheckedContinuation<DIMSEStatus, Error>?
    private var getStoreSendInProgress = false
    private var moveStoreTask: Task<StoreResult, Error>?
    private var cancelledStoreDeadline: Task<Void, Never>?

    /// Internal test synchronization only; no public server option or wire behavior.
    enum Checkpoint: Sendable, Hashable {
        case beforeFindResult(messageID: UInt16, index: Int)
        case beforeStore(messageID: UInt16, index: Int)
        case duringGetStoreSend(messageID: UInt16)
        case beforeFinalResponse(messageID: UInt16)
        case cancelProcessed(messageID: UInt16, accepted: Bool)
        case operationFinished(messageID: UInt16)
    }
    struct TestHooks: Sendable {
        var checkpoint: @Sendable (Checkpoint) async throws -> Void
        var cancellationSettlementTimeout: TimeInterval = 30
    }
    private let testHooks: TestHooks?

    /// Errors ending the session
    private enum SessionError: Error {
        case connectionClosed
        case associationAborted
        case unexpectedRelease
    }

    init(
        id: UUID,
        connection: NWConnection,
        configuration: ServerConfiguration,
        storage: StorageManager,
        database: DatabaseManager?,
        statistics: ServerStatistics,
        logger: ServerLogger,
        testHooks: TestHooks? = nil
    ) {
        self.id = id
        self.connection = connection
        self.configuration = configuration
        self.storage = storage
        self.database = database
        self.statistics = statistics
        self.logger = logger
        self.testHooks = testHooks
    }

    /// Start the session
    func start() async {
        isActive = true

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task {
                await self.handleConnectionState(state)
            }
        }

        connection.start(queue: .global(qos: .userInitiated))

        // Handle incoming messages. Do not report the session finished while
        // an outgoing MOVE store or a GET response waiter still owns resources.
        await receiveLoop()
        await waitForPendingRequests()
    }

    /// After cancel(), drain the worker before releasing server-owned resources.
    func waitForPendingRequests() async {
        await handlerTask?.value
    }

    /// Cancel the session
    func cancel() async {
        isActive = false
        isEstablished = false
        handlerTask?.cancel()
        moveStoreTask?.cancel()
        cancelledStoreDeadline?.cancel()
        cancelledStoreDeadline = nil
        requestQueue.removeAll()
        activeOperation = nil
        expectedStoreResponse = nil
        bufferedStoreResponse = nil
        getStoreSendInProgress = false
        let waiter = storeResponseWaiter
        storeResponseWaiter = nil
        waiter?.resume(throwing: SessionError.connectionClosed)
        connection.cancel()
    }

    private func handleConnectionState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            log("Connection ready")
        case .failed(let error):
            log("Connection failed: \(error)")
            Task { await self.cancel() }
        case .cancelled:
            log("Connection cancelled")
            Task { await self.cancel() }
        default:
            break
        }
    }

    private func log(_ message: String) {
        if configuration.verbose {
            print("[ServerSession \(id)] \(message)")
        }
    }

    // MARK: - PDU transport

    private func receiveLoop() async {
        while isActive {
            do {
                let pdu = try await receivePDU()
                try await handlePDU(pdu)
            } catch {
                log("Receive loop ended: \(error)")
                break
            }
        }

        await cancel()
    }

    /// Receives one PDU. An A-ASSOCIATE-RQ that cannot be decoded is rejected 2/2/1 (PS3.8
    /// Table 9-21); a P-DATA-TF longer than the Maximum Length the server announced is aborted.
    private func receivePDU() async throws -> any PDU {
        let header = try await receive(length: 6)
        let (pduType, pduLength) = try PDUDecoder.readHeader(from: header)

        if ServerProtocol.exceedsLocalMaximum(pduType: pduType.rawValue, length: pduLength,
                                              localMax: configuration.maxPDUSize) {
            log("P-DATA-TF of \(pduLength) bytes exceeds the announced Maximum Length \(configuration.maxPDUSize)")
            try? await sendPDU(AbortPDU(source: .serviceProvider, reason: .invalidPDUParameterValue))
            throw SessionError.associationAborted
        }

        let body = try await receive(length: Int(pduLength))
        var full = header
        full.append(body)
        do {
            return try PDUDecoder.decode(from: full)
        } catch {
            if pduType == .associateRequest && !isEstablished {
                log("Error decoding A-ASSOCIATE-RQ: \(error)")
                try? await sendPDU(AssociateRejectPDU(result: .rejectedTransient, source: .serviceProviderACSE, reason: 1))
            } else {
                try? await sendPDU(AbortPDU(source: .serviceProvider, reason: .unrecognizedPDUParameter))
            }
            throw error
        }
    }

    private func receive(length: Int) async throws -> Data {
        if length == 0 { return Data() }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: length, maximumLength: length) { data, _, isComplete, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data, data.count >= length {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: SessionError.connectionClosed)
                } else {
                    continuation.resume(throwing: DICOMNetworkError.decodingFailed("Incomplete data received"))
                }
            }
        }
    }

    private func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func sendPDU(_ pdu: any PDU) async throws {
        try await send(try pdu.encode())
    }

    private func handlePDU(_ pdu: any PDU) async throws {
        switch pdu {
        case let request as AssociateRequestPDU:
            try await handleAssociationRequest(request)
        case let data as DataTransferPDU:
            // A PDU can complete more than one message; do not discard all but
            // its last message (e.g. request and immediate C-CANCEL).
            for pdv in data.presentationDataValues {
                if let message = try messageAssembler.addPDV(pdv) {
                    try await dispatchDIMSEMessage(message)
                }
            }
        case is ReleaseRequestPDU:
            try await handleReleaseRequest()
        case is AbortPDU:
            log("Received A-ABORT")
            await cancel()
        default:
            log("Unexpected PDU from the association requestor: \(pdu.pduType)")
        }
    }

    // MARK: - Association

    private func handleAssociationRequest(_ pdu: AssociateRequestPDU) async throws {
        log("Received A-ASSOCIATE-RQ")
        callingAETitle = pdu.callingAETitle.value

        // Validate calling AE Title if configured (PS3.8 Table 9-21: 1/1/3 calling-AE-title-not-recognized)
        if let allowed = configuration.allowedCallingAETitles, !allowed.isEmpty, !allowed.contains(callingAETitle) {
            log("Rejected: Calling AE '\(callingAETitle)' not in whitelist")
            try await sendPDU(AssociateRejectPDU(result: .rejectedPermanent, source: .serviceUser, reason: 3))
            await cancel()
            return
        }
        if let blocked = configuration.blockedCallingAETitles, !blocked.isEmpty, blocked.contains(callingAETitle) {
            log("Rejected: Calling AE '\(callingAETitle)' is blocked")
            try await sendPDU(AssociateRejectPDU(result: .rejectedPermanent, source: .serviceUser, reason: 3))
            await cancel()
            return
        }

        let negotiation = ServerProtocol.negotiate(
            presentationContexts: pdu.presentationContexts,
            roleSelections: pdu.roleSelections)
        acceptedPresentationContexts = negotiation.accepted
        outgoingMaxPDUSize = ServerProtocol.outgoingMaxPDUSize(peer: pdu.maxPDUSize, local: configuration.maxPDUSize)

        // PS3.8 9.3.3: the AE title fields echo the A-ASSOCIATE-RQ; the User Information carries
        // the server's own Maximum Length (D.1) and Implementation Class UID (PS3.7 D.3.3.2).
        let accept = AssociateAcceptPDU(
            calledAETitle: pdu.calledAETitle,
            callingAETitle: pdu.callingAETitle,
            presentationContexts: negotiation.results,
            maxPDUSize: configuration.maxPDUSize,
            implementationClassUID: ServerProtocol.implementationClassUID,
            implementationVersionName: ServerProtocol.implementationVersionName,
            roleSelections: negotiation.roleSelections
        )
        try await sendPDU(accept)
        isEstablished = true
        log("Sent A-ASSOCIATE-AC (\(negotiation.accepted.count) of \(pdu.presentationContexts.count) contexts accepted)")
    }

    private func handleReleaseRequest() async throws {
        log("Received A-RELEASE-RQ")
        if let activeOperation, !activeOperation.finalCommitted {
            // Releasing with an unfinished operation is not legal association
            // use. Stop the worker instead of interleaving release and DIMSE.
            try? await sendPDU(AbortPDU(source: .serviceProvider, reason: .unexpectedPDU))
            await cancel()
            return
        }
        try await sendPDU(ReleaseResponsePDU())
        log("Sent A-RELEASE-RP")
        await cancel()
    }

    // MARK: - DIMSE

    /// Cancellation and sub-operation responses bypass the serialized request
    /// worker. Only this receive pump reads PDUs, including during C-GET.
    private func dispatchDIMSEMessage(_ message: AssembledMessage) async throws {
        if let request = message.asCCancelRequest() {
            let matches = activeOperation?.messageID == request.messageIDBeingCancelled
                && activeOperation?.contextID == message.presentationContextID
                && activeOperation?.finalCommitted == false
            if matches {
                activeOperation?.cancelled = true
                startCancelledStoreDeadline(messageID: request.messageIDBeingCancelled)
            }
            try await testHooks?.checkpoint(.cancelProcessed(messageID: request.messageIDBeingCancelled, accepted: matches))
            return
        }
        if let response = message.asCStoreResponse() {
            if expectedStoreResponse?.messageID == response.messageIDBeingRespondedTo,
               expectedStoreResponse?.contextID == message.presentationContextID {
                if let waiter = storeResponseWaiter {
                    storeResponseWaiter = nil
                    waiter.resume(returning: response.status)
                } else {
                    bufferedStoreResponse = response.status
                }
            } else {
                log("Ignoring C-STORE-RSP for another sub-operation")
            }
            return
        }
        requestQueue.append(message)
        if handlerTask == nil {
            let first = requestQueue.removeFirst()
            beginOperation(first)
            handlerTask = Task { await self.processRequests(startingWith: first) }
        }
    }

    /// Permit an initiated sub-operation to settle, but do not let a silent
    /// destination keep a cancelled operation alive forever. Repeated cancels
    /// cannot reset the deadline. Timeout is a failed attempted sub-operation;
    /// Remaining therefore still counts only stores never initiated.
    private func startCancelledStoreDeadline(messageID: UInt16) {
        guard cancelledStoreDeadline == nil, moveStoreTask != nil || expectedStoreResponse != nil else { return }
        let timeout = testHooks?.cancellationSettlementTimeout ?? 30
        cancelledStoreDeadline = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(max(0.001, timeout) * 1_000_000_000))
                try Task.checkCancellation()
                guard isCancelled(messageID) else { return }
                moveStoreTask?.cancel()
                if getStoreSendInProgress {
                    // The peer may have stopped reading an incomplete C-STORE
                    // data set. A final response cannot be inserted into that
                    // unfinished DIMSE message; close the association to unblock
                    // its send and drain the worker within the same deadline.
                    log("Cancelled C-GET store transmission did not settle; closing association")
                    await cancel()
                    return
                }
                if expectedStoreResponse != nil, bufferedStoreResponse == nil {
                    if let waiter = storeResponseWaiter {
                        storeResponseWaiter = nil
                        waiter.resume(returning: .refusedOutOfResources)
                    } else {
                        bufferedStoreResponse = .refusedOutOfResources
                    }
                }
            } catch { /* Actual completion or disconnect cancelled the deadline. */ }
        }
    }

    private func beginOperation(_ message: AssembledMessage) {
        switch message.command {
        case .cFindRequest, .cMoveRequest, .cGetRequest:
            activeOperation = message.commandSet.messageID.map {
                ActiveOperation(messageID: $0, contextID: message.presentationContextID)
            }
        default:
            activeOperation = nil
        }
    }

    private func processRequests(startingWith first: AssembledMessage) async {
        var message = first
        while isActive {
            do {
                try await handleDIMSEMessage(message)
            } catch {
                log("Request handler ended: \(error)")
                await cancel()
            }
            if let messageID = message.commandSet.messageID {
                try? await testHooks?.checkpoint(.operationFinished(messageID: messageID))
            }
            activeOperation = nil
            guard isActive, !requestQueue.isEmpty else { break }
            message = requestQueue.removeFirst()
            beginOperation(message)
        }
        handlerTask = nil
    }

    private func isCancelled(_ messageID: UInt16) -> Bool {
        activeOperation?.messageID == messageID && activeOperation?.cancelled == true
    }

    /// Linearization point of the final-response/cancel race. A later cancel is
    /// ignored; it cannot contaminate another operation reusing this Message ID.
    private func commitFinalResponse(_ messageID: UInt16) -> Bool {
        guard activeOperation?.messageID == messageID else { return false }
        activeOperation?.finalCommitted = true
        return activeOperation?.cancelled == true
    }

    private func checkpoint(_ point: Checkpoint) async throws {
        try await testHooks?.checkpoint(point)
        guard isActive else { throw SessionError.connectionClosed }
        try Task.checkCancellation()
    }

    private func handleDIMSEMessage(_ message: AssembledMessage) async throws {
        guard let command = message.command else {
            log("Unknown DIMSE command")
            try? await sendPDU(AbortPDU(source: .serviceProvider, reason: .invalidPDUParameterValue))
            throw SessionError.associationAborted
        }
        log("Handling DIMSE command: \(command)")

        switch command {
        case .cEchoRequest:
            try await handleCEcho(message)
        case .cStoreRequest:
            try await handleCStore(message)
        case .cFindRequest:
            try await handleCFind(message)
        case .cMoveRequest:
            try await handleCMove(message)
        case .cGetRequest:
            try await handleCGet(message)
        default:
            try await sendUnrecognizedOperationResponse(for: message)
        }
    }

    /// Transfer syntax negotiated for a presentation context
    private func transferSyntax(for contextID: UInt8) -> String {
        acceptedPresentationContexts[contextID]?.transferSyntax ?? "1.2.840.10008.1.2"
    }

    /// Answers a request this SCP does not provide with 0211H "Unrecognized operation" (PS3.7 C.4).
    private func sendUnrecognizedOperationResponse(for message: AssembledMessage) async throws {
        guard let command = message.command, command.isRequest, let responseCommand = command.responseCommand else {
            return
        }
        var commandSet = CommandSet()
        commandSet.setCommand(responseCommand)
        commandSet.setMessageIDBeingRespondedTo(message.commandSet.messageID ?? 0)
        if let sopClassUID = message.commandSet.affectedSOPClassUID ?? message.commandSet.requestedSOPClassUID {
            commandSet.setAffectedSOPClassUID(sopClassUID)
        }
        commandSet.setHasDataSet(false)
        commandSet.setStatus(DIMSEStatus.from(0x0211))
        try await sendDIMSE(commandSet, dataSet: nil, contextID: message.presentationContextID)
    }

    // MARK: - C-ECHO Handler

    private func handleCEcho(_ message: AssembledMessage) async throws {
        await statistics.recordEchoRequest()
        guard let request = message.asCEchoRequest() else {
            await logger.warning("Invalid C-ECHO request", context: "ServerSession")
            return
        }
        let response = CEchoResponse(
            messageIDBeingRespondedTo: request.messageID,
            affectedSOPClassUID: request.affectedSOPClassUID,
            status: .success,
            presentationContextID: message.presentationContextID
        )
        try await sendDIMSE(response.commandSet, dataSet: nil, contextID: message.presentationContextID)
        log("C-ECHO response sent")
    }

    // MARK: - C-STORE Handler

    private func handleCStore(_ message: AssembledMessage) async throws {
        guard let request = message.asCStoreRequest() else {
            await logger.warning("Invalid C-STORE request", context: "ServerSession")
            await statistics.recordStoreRequest(success: false)
            return
        }
        let contextID = message.presentationContextID

        func respond(_ status: DIMSEStatus, comment: String? = nil) async throws {
            let response = CStoreResponse(
                messageIDBeingRespondedTo: request.messageID,
                affectedSOPClassUID: request.affectedSOPClassUID,
                affectedSOPInstanceUID: request.affectedSOPInstanceUID,
                status: status,
                presentationContextID: contextID
            )
            var commandSet = response.commandSet
            if let comment { commandSet.setString(String(comment.prefix(64)), for: .errorComment) }
            try await sendDIMSE(commandSet, dataSet: nil, contextID: contextID)
        }

        guard let dataSetBytes = message.dataSet else {
            // PS3.4 Table B.2-1: Cxxx "Error: Cannot understand"
            try await respond(.errorCannotUnderstand(0xC000), comment: "C-STORE request without a data set")
            await statistics.recordStoreRequest(success: false)
            return
        }
        log("C-STORE request: SOP Instance UID = \(request.affectedSOPInstanceUID)")

        let transferSyntaxUID = transferSyntax(for: contextID)
        let stored: StorageManager.StoredInstance
        do {
            stored = try await storage.storeReceived(
                dataSetData: dataSetBytes,
                sopClassUID: request.affectedSOPClassUID,
                sopInstanceUID: request.affectedSOPInstanceUID,
                transferSyntaxUID: transferSyntaxUID,
                serverAETitle: configuration.aeTitle,
                callingAETitle: callingAETitle
            )
        } catch let error as CocoaError {
            // Could not write the file: A7xx "Refused: Out of resources"
            await logger.error("C-STORE failed", error: error, context: "ServerSession")
            try await respond(.refusedOutOfResources, comment: "Could not store the instance")
            await statistics.recordStoreRequest(success: false)
            return
        } catch {
            // Data set not decodable in the negotiated transfer syntax: Cxxx "Error: Cannot understand"
            await logger.error("C-STORE failed", error: error, context: "ServerSession")
            try await respond(.errorCannotUnderstand(0xC000), comment: "Data set could not be decoded")
            await statistics.recordStoreRequest(success: false)
            return
        }
        log("Stored file: \(stored.filePath)")

        if let db = database {
            let metadata = DICOMMetadata(
                dataSet: stored.dataSet,
                filePath: stored.filePath,
                sopInstanceUID: request.affectedSOPInstanceUID,
                sopClassUID: request.affectedSOPClassUID,
                transferSyntaxUID: transferSyntaxUID)
            do {
                try await db.index(filePath: stored.filePath, metadata: metadata)
            } catch {
                await logger.error("C-STORE indexing failed", error: error, context: "ServerSession")
                try await respond(.refusedOutOfResources, comment: "Stored instance could not be indexed")
                await statistics.recordStoreRequest(success: false)
                return
            }
        }

        try await respond(.success)
        await statistics.recordStoreRequest(success: true, bytesReceived: Int64(dataSetBytes.count))
        await logger.info("C-STORE completed: \(request.affectedSOPInstanceUID)", context: "ServerSession")
    }

    // MARK: - Identifier handling (C-FIND / C-MOVE / C-GET)

    /// Decodes the request Identifier and checks Query/Retrieve Level; on failure the
    /// returned command set is the A900 / C000 response to send.
    private func identifierAndLevel(
        _ message: AssembledMessage,
        sopClassUID: String
    ) -> Result<(DataSet, QueryLevel), ServerProtocol.IdentifierError> {
        guard let bytes = message.dataSet else {
            return .failure(.init(offendingElement: .queryRetrieveLevel, comment: "Identifier missing"))
        }
        let identifier: DataSet
        do {
            identifier = try ServerProtocol.decodeDataSet(bytes, transferSyntaxUID: transferSyntax(for: message.presentationContextID))
        } catch {
            return .failure(.init(offendingElement: .queryRetrieveLevel, comment: "Identifier could not be decoded"))
        }
        return ServerProtocol.queryRetrieveLevel(in: identifier, sopClassUID: sopClassUID).map { (identifier, $0) }
    }

    // MARK: - C-FIND Handler

    private func handleCFind(_ message: AssembledMessage) async throws {
        guard let request = message.asCFindRequest() else {
            await logger.warning("Invalid C-FIND request", context: "ServerSession")
            await statistics.recordFindRequest(success: false)
            return
        }
        let contextID = message.presentationContextID
        let ts = transferSyntax(for: contextID)

        func response(_ status: DIMSEStatus, hasDataSet: Bool = false) -> CommandSet {
            CFindResponse(
                messageIDBeingRespondedTo: request.messageID,
                affectedSOPClassUID: request.affectedSOPClassUID,
                status: status,
                hasDataSet: hasDataSet,
                presentationContextID: contextID
            ).commandSet
        }

        let identifier: DataSet
        let level: QueryLevel
        switch identifierAndLevel(message, sopClassUID: request.affectedSOPClassUID) {
        case .failure(let error):
            var commandSet = response(error.status)
            ServerProtocol.addErrorFields(error, to: &commandSet)
            try await sendDIMSE(commandSet, dataSet: nil, contextID: contextID)
            await statistics.recordFindRequest(success: false)
            log("C-FIND refused: \(error.comment)")
            return
        case .success(let value):
            (identifier, level) = value
        }
        log("C-FIND query level: \(level)")

        do {
            let results = try await database?.queryForFind(
                queryDataset: identifier, level: level, retrieveAETitle: configuration.aeTitle) ?? []
            // FF01 when the request carried optional keys the server does not support (Table C.4-1)
            let pending = DIMSEStatus.pending(
                warningOptionalKeys: !QueryMatcher.unsupportedKeys(in: identifier, level: level).isEmpty)
            for (index, result) in results.enumerated() {
                try await checkpoint(.beforeFindResult(messageID: request.messageID, index: index))
                if isCancelled(request.messageID) { break }
                try await sendDIMSE(response(pending, hasDataSet: true),
                                    dataSet: ServerProtocol.encodeDataSet(result, transferSyntaxUID: ts),
                                    contextID: contextID)
            }
            try await checkpoint(.beforeFinalResponse(messageID: request.messageID))
            let cancelled = commitFinalResponse(request.messageID)
            try await sendDIMSE(response(cancelled ? .cancel : .success), dataSet: nil, contextID: contextID)
            await statistics.recordFindRequest(success: !cancelled)
            await logger.info("C-FIND completed: \(results.count) results", context: "ServerSession")
        } catch {
            await logger.error("C-FIND failed", error: error, context: "ServerSession")
            await statistics.recordFindRequest(success: false)
            var commandSet = response(.errorCannotUnderstand(0xC000)) // Cxxx "Failed: Unable to process"
            commandSet.setString("Unable to process", for: .errorComment)
            try await sendDIMSE(commandSet, dataSet: nil, contextID: contextID)
        }
    }

    // MARK: - C-MOVE Handler

    private func handleCMove(_ message: AssembledMessage) async throws {
        guard let request = message.asCMoveRequest() else {
            await logger.warning("Invalid C-MOVE request", context: "ServerSession")
            await statistics.recordMoveRequest(success: false)
            return
        }
        let contextID = message.presentationContextID

        func response(_ status: DIMSEStatus, _ counts: ServerProtocol.SubOperationCounts?, includeRemaining: Bool) -> CommandSet {
            CMoveResponse(
                messageIDBeingRespondedTo: request.messageID,
                affectedSOPClassUID: request.affectedSOPClassUID,
                status: status,
                remaining: includeRemaining ? counts?.remaining : nil,
                completed: counts?.completed,
                failed: counts?.failed,
                warning: counts?.warning,
                presentationContextID: contextID
            ).commandSet
        }

        let identifier: DataSet
        let level: QueryLevel
        switch identifierAndLevel(message, sopClassUID: request.affectedSOPClassUID) {
        case .failure(let error):
            var commandSet = response(error.status, nil, includeRemaining: false)
            ServerProtocol.addErrorFields(error, to: &commandSet)
            try await sendDIMSE(commandSet, dataSet: nil, contextID: contextID)
            await statistics.recordMoveRequest(success: false)
            return
        case .success(let value):
            (identifier, level) = value
        }

        // PS3.4 Table C.4-2: A801 "Refused: Move Destination unknown"
        guard let destination = configuration.moveDestination(for: request.moveDestination) else {
            var commandSet = response(.failedMoveDestinationUnknown, nil, includeRemaining: false)
            commandSet.setString(String("Move Destination unknown: \(request.moveDestination)".prefix(64)), for: .errorComment)
            try await sendDIMSE(commandSet, dataSet: nil, contextID: contextID)
            await statistics.recordMoveRequest(success: false)
            log("C-MOVE refused: Move Destination '\(request.moveDestination)' unknown")
            return
        }
        log("C-MOVE level \(level) to \(destination.aeTitle)@\(destination.host):\(destination.port)")

        do {
            let instances = try await database?.queryForRetrieve(queryDataset: identifier, level: level) ?? []
            var counts = ServerProtocol.SubOperationCounts(total: instances.count)

            for (index, metadata) in instances.enumerated() {
                try await checkpoint(.beforeStore(messageID: request.messageID, index: index))
                if isCancelled(request.messageID) { break }
                // An already initiated store is allowed to settle; its actual
                // response contributes to counts before the Cancel response.
                let status = await storeToDestination(metadata: metadata, destination: destination,
                                                      priority: request.priority,
                                                      moveOriginatorMessageID: request.messageID)
                counts.record(status, sopInstanceUID: metadata.sopInstanceUID)
                if counts.remaining > 0 && !isCancelled(request.messageID) {
                    try await sendDIMSE(response(.pending(warningOptionalKeys: false), counts, includeRemaining: true),
                                        dataSet: nil, contextID: contextID)
                }
            }

            try await checkpoint(.beforeFinalResponse(messageID: request.messageID))
            let cancelled = commitFinalResponse(request.messageID)
            try await sendFinalRetrieveResponse(response(ServerProtocol.finalRetrieveStatus(counts, cancelled: cancelled), counts, includeRemaining: cancelled),
                                                counts: counts, contextID: contextID)
            await statistics.recordMoveRequest(success: !cancelled && counts.failed == 0, instancesSent: Int(counts.completed))
            await logger.info("C-MOVE complete: \(counts.completed) completed, \(counts.warning) warning, \(counts.failed) failed", context: "ServerSession")
        } catch {
            await logger.error("C-MOVE failed", error: error, context: "ServerSession")
            await statistics.recordMoveRequest(success: false)
            var commandSet = response(.errorCannotUnderstand(0xC000), nil, includeRemaining: false) // Cxxx "Failed: Unable to process"
            commandSet.setString("Unable to process", for: .errorComment)
            try await sendDIMSE(commandSet, dataSet: nil, contextID: contextID)
        }
    }

    /// C-STORE sub-operation of a C-MOVE on a new association to the Move Destination.
    ///
    /// - Returns: the C-STORE-RSP status, or nil when the sub-operation could not be performed
    ///   (no file, association or presentation context: a Failure, PS3.4 C.4.2.3.1)
    /// The C-STORE-RQ carries Move Originator AE Title (0000,1030) = the calling AE of
    /// this association and Move Originator Message ID (0000,1031) = the C-MOVE-RQ
    /// Message ID (PS3.7 2026a 9.1.1.1.6 / 9.1.1.1.7, D156).
    private func storeToDestination(metadata: DICOMMetadata, destination: DestinationAE, priority: DIMSEPriority,
                                    moveOriginatorMessageID: UInt16) async -> DIMSEStatus? {
        do {
            let fileData = try Data(contentsOf: URL(fileURLWithPath: metadata.filePath))
            let config = StorageConfiguration(
                callingAETitle: try AETitle(configuration.aeTitle),
                calledAETitle: try AETitle(destination.aeTitle),
                timeout: 30,
                maxPDUSize: configuration.maxPDUSize == 0 ? defaultMaxPDUSize : configuration.maxPDUSize,
                implementationClassUID: ServerProtocol.implementationClassUID,
                implementationVersionName: ServerProtocol.implementationVersionName,
                priority: priority
            ).withMoveOriginator(aeTitle: callingAETitle, messageID: moveOriginatorMessageID)
            let task = Task {
                try await DICOMStorageService.store(
                    fileData: fileData, to: destination.host, port: destination.port, configuration: config)
            }
            moveStoreTask = task
            if isCancelled(moveOriginatorMessageID) { startCancelledStoreDeadline(messageID: moveOriginatorMessageID) }
            defer {
                moveStoreTask = nil
                cancelledStoreDeadline?.cancel()
                cancelledStoreDeadline = nil
            }
            let result = try await task.value
            log("C-STORE sub-operation \(metadata.sopInstanceUID) -> \(destination.aeTitle): \(result.status)")
            return result.status
        } catch {
            log("C-STORE sub-operation \(metadata.sopInstanceUID) failed: \(error)")
            return nil
        }
    }

    /// Final C-MOVE / C-GET response; with failures it carries the Failed SOP Instance UID List
    /// (C.4.2.1.4.2 / C.4.3.1.3.2).
    private func sendFinalRetrieveResponse(_ commandSet: CommandSet, counts: ServerProtocol.SubOperationCounts, contextID: UInt8) async throws {
        var commandSet = commandSet
        var data: Data? = nil
        if let identifier = ServerProtocol.failedInstancesIdentifier(counts) {
            commandSet.setHasDataSet(true)
            data = ServerProtocol.encodeDataSet(identifier, transferSyntaxUID: transferSyntax(for: contextID))
        }
        try await sendDIMSE(commandSet, dataSet: data, contextID: contextID)
    }

    // MARK: - C-GET Handler

    private func handleCGet(_ message: AssembledMessage) async throws {
        guard let request = message.asCGetRequest() else {
            await logger.warning("Invalid C-GET request", context: "ServerSession")
            await statistics.recordGetRequest(success: false)
            return
        }
        let contextID = message.presentationContextID

        func response(_ status: DIMSEStatus, _ counts: ServerProtocol.SubOperationCounts?, includeRemaining: Bool) -> CommandSet {
            CGetResponse(
                messageIDBeingRespondedTo: request.messageID,
                affectedSOPClassUID: request.affectedSOPClassUID,
                status: status,
                remaining: includeRemaining ? counts?.remaining : nil,
                completed: counts?.completed,
                failed: counts?.failed,
                warning: counts?.warning,
                presentationContextID: contextID
            ).commandSet
        }

        let identifier: DataSet
        let level: QueryLevel
        switch identifierAndLevel(message, sopClassUID: request.affectedSOPClassUID) {
        case .failure(let error):
            var commandSet = response(error.status, nil, includeRemaining: false)
            ServerProtocol.addErrorFields(error, to: &commandSet)
            try await sendDIMSE(commandSet, dataSet: nil, contextID: contextID)
            await statistics.recordGetRequest(success: false)
            return
        case .success(let value):
            (identifier, level) = value
        }
        log("C-GET level \(level)")

        let instances: [DICOMMetadata]
        do {
            instances = try await database?.queryForRetrieve(queryDataset: identifier, level: level) ?? []
        } catch {
            await logger.error("C-GET failed", error: error, context: "ServerSession")
            await statistics.recordGetRequest(success: false)
            var commandSet = response(.errorCannotUnderstand(0xC000), nil, includeRemaining: false)
            commandSet.setString("Unable to process", for: .errorComment)
            try await sendDIMSE(commandSet, dataSet: nil, contextID: contextID)
            return
        }

        var counts = ServerProtocol.SubOperationCounts(total: instances.count)
        var bytesSent: Int64 = 0
        for (index, metadata) in instances.enumerated() {
            try await checkpoint(.beforeStore(messageID: request.messageID, index: index))
            if isCancelled(request.messageID) { break }
            let (status, size) = try await storeOnThisAssociation(
                metadata: metadata, priority: request.priority, getMessageID: request.messageID)
            counts.record(status, sopInstanceUID: metadata.sopInstanceUID)
            bytesSent += Int64(size)
            if counts.remaining > 0 && !isCancelled(request.messageID) {
                try await sendDIMSE(response(.pending(warningOptionalKeys: false), counts, includeRemaining: true),
                                    dataSet: nil, contextID: contextID)
            }
        }

        // C.4.3.3.1: Cancel carries the counts; Remaining = sub-operations not initiated
        try await checkpoint(.beforeFinalResponse(messageID: request.messageID))
        let cancelled = commitFinalResponse(request.messageID)
        try await sendFinalRetrieveResponse(
            response(ServerProtocol.finalRetrieveStatus(counts, cancelled: cancelled), counts, includeRemaining: cancelled),
            counts: counts, contextID: contextID)
        await statistics.recordGetRequest(success: !cancelled && counts.failed == 0, bytesSent: bytesSent)
        await logger.info("C-GET complete: \(counts.completed) completed, \(counts.warning) warning, \(counts.failed) failed", context: "ServerSession")
    }

    /// C-STORE sub-operation of a C-GET on this association (PS3.4 C.4.3.3.1).
    ///
    /// Needs an accepted presentation context for the instance's SOP Class on which the
    /// requestor was granted the SCP role (PS3.7 D.3.3.4); without one the sub-operation is a
    /// Failure. The C-STORE-RQ is sent and the C-STORE-RSP awaited; its status is returned.
    private func storeOnThisAssociation(metadata: DICOMMetadata, priority: DIMSEPriority, getMessageID: UInt16) async throws -> (DIMSEStatus?, Int) {
        let stored: ServerProtocol.StoredDataSet
        do {
            stored = try ServerProtocol.readStoredFile(Data(contentsOf: URL(fileURLWithPath: metadata.filePath)))
        } catch {
            log("Cannot read \(metadata.filePath): \(error)")
            return (nil, 0)
        }

        let candidates = acceptedPresentationContexts
            .filter { $0.value.abstractSyntax == stored.sopClassUID && $0.value.requestorIsSCP }
            .sorted { $0.key < $1.key }
        guard let (pcID, context) = candidates.first(where: { $0.value.transferSyntax == stored.transferSyntaxUID }) ?? candidates.first else {
            log("No presentation context with SCP role for \(stored.sopClassUID)")
            return (nil, 0)
        }
        let dataSetData: Data
        do {
            dataSetData = try ServerProtocol.transcode(stored, to: context.transferSyntax)
        } catch {
            log("Cannot convert \(metadata.sopInstanceUID): \(error)")
            return (nil, 0)
        }

        messageIDCounter = messageIDCounter &+ 1
        let messageID = messageIDCounter
        let storeRequest = CStoreRequest(
            messageID: messageID,
            affectedSOPClassUID: stored.sopClassUID,
            affectedSOPInstanceUID: stored.sopInstanceUID,
            priority: priority,
            presentationContextID: pcID
        )
        // Register before sending: a fast peer can answer while send is
        // suspended. The receive pump buffers that response until we await it.
        expectedStoreResponse = (messageID, pcID)
        bufferedStoreResponse = nil
        getStoreSendInProgress = true
        if isCancelled(getMessageID) { startCancelledStoreDeadline(messageID: getMessageID) }
        defer {
            expectedStoreResponse = nil
            bufferedStoreResponse = nil
            getStoreSendInProgress = false
            cancelledStoreDeadline?.cancel()
            cancelledStoreDeadline = nil
        }
        try await sendDIMSE(storeRequest.commandSet, dataSet: dataSetData, contextID: pcID)
        getStoreSendInProgress = false
        let status: DIMSEStatus
        if let buffered = bufferedStoreResponse {
            status = buffered
            bufferedStoreResponse = nil
        } else {
            guard isActive else { throw SessionError.connectionClosed }
            status = try await withCheckedThrowingContinuation { continuation in
                storeResponseWaiter = continuation
            }
        }
        return (status, dataSetData.count)
    }

    // MARK: - Helper Methods

    /// Sends a DIMSE message fragmented to the peer's Maximum Length (PS3.8 D.1).
    private func sendDIMSE(_ commandSet: CommandSet, dataSet: Data?, contextID: UInt8) async throws {
        guard isActive else { throw SessionError.connectionClosed }
        if let command = commandSet.command, [.cFindResponse, .cMoveResponse, .cGetResponse].contains(command),
           let messageID = commandSet.messageIDBeingRespondedTo,
           activeOperation?.messageID == messageID {
            if commandSet.status?.isPending == true {
                if isCancelled(messageID) { return }
            } else {
                _ = commitFinalResponse(messageID)
            }
        }
        let fragmenter = MessageFragmenter(maxPDUSize: outgoingMaxPDUSize)
        for (index, pdu) in fragmenter.fragmentMessage(commandSet: commandSet, dataSet: dataSet, presentationContextID: contextID).enumerated() {
            try await send(try pdu.encode())
            if index == 0, commandSet.command == .cStoreRequest, getStoreSendInProgress,
               let getMessageID = activeOperation?.messageID {
                try await checkpoint(.duringGetStoreSend(messageID: getMessageID))
            }
        }
    }
}

#endif
