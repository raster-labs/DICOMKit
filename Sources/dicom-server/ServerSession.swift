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
    /// Message ID of a C-GET for which a C-CANCEL-RQ arrived
    private var cancelledMessageIDs: Set<UInt16> = []

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
        logger: ServerLogger
    ) {
        self.id = id
        self.connection = connection
        self.configuration = configuration
        self.storage = storage
        self.database = database
        self.statistics = statistics
        self.logger = logger
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

        // Handle incoming messages
        await receiveLoop()
    }

    /// Cancel the session
    func cancel() async {
        isActive = false
        isEstablished = false
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
            if let message = try messageAssembler.addPDVs(from: data) {
                try await handleDIMSEMessage(message)
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
        try await sendPDU(ReleaseResponsePDU())
        log("Sent A-RELEASE-RP")
        await cancel()
    }

    // MARK: - DIMSE

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
        case .cCancelRequest:
            // Nothing in progress: C-FIND results are sent at once; C-GET handles its own cancel.
            break
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
            try await db.index(filePath: stored.filePath, metadata: metadata)
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
            for result in results {
                try await sendDIMSE(response(pending, hasDataSet: true),
                                    dataSet: ServerProtocol.encodeDataSet(result, transferSyntaxUID: ts),
                                    contextID: contextID)
            }
            try await sendDIMSE(response(.success), dataSet: nil, contextID: contextID)
            await statistics.recordFindRequest(success: true)
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

            for metadata in instances {
                let status = await storeToDestination(metadata: metadata, destination: destination,
                                                      priority: request.priority,
                                                      moveOriginatorMessageID: request.messageID)
                counts.record(status, sopInstanceUID: metadata.sopInstanceUID)
                if counts.remaining > 0 {
                    try await sendDIMSE(response(.pending(warningOptionalKeys: false), counts, includeRemaining: true),
                                        dataSet: nil, contextID: contextID)
                }
            }

            try await sendFinalRetrieveResponse(response(ServerProtocol.finalRetrieveStatus(counts), counts, includeRemaining: false),
                                                counts: counts, contextID: contextID)
            await statistics.recordMoveRequest(success: counts.failed == 0, instancesSent: Int(counts.completed))
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
            let result = try await DICOMStorageService.store(
                fileData: fileData, to: destination.host, port: destination.port, configuration: config)
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
        cancelledMessageIDs.remove(request.messageID)
        for metadata in instances {
            if cancelledMessageIDs.contains(request.messageID) { break }
            let (status, size) = try await storeOnThisAssociation(
                metadata: metadata, priority: request.priority, getMessageID: request.messageID)
            counts.record(status, sopInstanceUID: metadata.sopInstanceUID)
            bytesSent += Int64(size)
            if counts.remaining > 0 && !cancelledMessageIDs.contains(request.messageID) {
                try await sendDIMSE(response(.pending(warningOptionalKeys: false), counts, includeRemaining: true),
                                    dataSet: nil, contextID: contextID)
            }
        }

        // C.4.3.3.1: Cancel carries the counts; Remaining = sub-operations not initiated
        let cancelled = cancelledMessageIDs.remove(request.messageID) != nil
        try await sendFinalRetrieveResponse(
            response(ServerProtocol.finalRetrieveStatus(counts, cancelled: cancelled), counts, includeRemaining: cancelled),
            counts: counts, contextID: contextID)
        await statistics.recordGetRequest(success: counts.failed == 0, bytesSent: bytesSent)
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
        try await sendDIMSE(storeRequest.commandSet, dataSet: dataSetData, contextID: pcID)

        // Await the C-STORE-RSP; a C-CANCEL-RQ for the C-GET may arrive meanwhile.
        while true {
            let message = try await receiveDIMSEMessage()
            switch message.command {
            case .cStoreResponse:
                if let rsp = message.asCStoreResponse(), rsp.messageIDBeingRespondedTo == messageID {
                    return (rsp.status, dataSetData.count)
                }
                log("Ignoring C-STORE-RSP for another message")
            case .cCancelRequest:
                if message.asCCancelRequest()?.messageIDBeingCancelled == getMessageID {
                    cancelledMessageIDs.insert(getMessageID)
                }
            default:
                log("Ignoring \(String(describing: message.command)) during a C-GET")
            }
        }
    }

    /// Reads PDUs until a complete DIMSE message has been assembled.
    private func receiveDIMSEMessage() async throws -> AssembledMessage {
        while isActive {
            let pdu = try await receivePDU()
            switch pdu {
            case let data as DataTransferPDU:
                if let message = try messageAssembler.addPDVs(from: data) { return message }
            case is AbortPDU:
                await cancel()
                throw SessionError.associationAborted
            case is ReleaseRequestPDU:
                throw SessionError.unexpectedRelease
            default:
                log("Unexpected PDU during a C-GET: \(pdu.pduType)")
            }
        }
        throw SessionError.connectionClosed
    }

    // MARK: - Helper Methods

    /// Sends a DIMSE message fragmented to the peer's Maximum Length (PS3.8 D.1).
    private func sendDIMSE(_ commandSet: CommandSet, dataSet: Data?, contextID: UInt8) async throws {
        let fragmenter = MessageFragmenter(maxPDUSize: outgoingMaxPDUSize)
        for pdu in fragmenter.fragmentMessage(commandSet: commandSet, dataSet: dataSet, presentationContextID: contextID) {
            try await send(try pdu.encode())
        }
    }
}

#endif
