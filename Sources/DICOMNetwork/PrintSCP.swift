//
// PrintSCP.swift
// DICOMNetwork
//
// DICOM Print SCP — a printer emulator. Listens for Print SCUs (modalities,
// workstations, third-party tools), accepts film sessions / film boxes / image
// boxes, and hands each printed film to a ``PrintSCPDelegate`` as a
// ``ReceivedFilm``.
//
// This file is the protocol machine only: no CoreGraphics, no rasterization,
// no printing — exactly as `StorageSCP.swift` is free of imaging. Composition
// and output sinks live above it.
//
// Reference: PS3.4 Annex H — Print Management Service Class.
//

import Foundation
import DICOMCore

#if canImport(Network)
import Network
// NEMA-verified: 2026a, checked 2026-09-28 — N-ACTION/N-CREATE/N-SET/N-GET/N-DELETE handling and statuses checked against PS3.4 2026a Tables H.4-3, H.4-4, H.4-8, H.4-9, H.4.2.2.1.2-1 and PS3.7 §10.1.4.1.10 / Annex C (0123H, 0211H); A-ASSOCIATE-RJ reasons per PS3.8 Table 9-21

/// Thrown when an established association sits idle past its deadline.
private struct AssociationIdleTimeout: Error {}

/// Resumes an `NWListener`/`NWConnection` state continuation exactly once.
///
/// Network.framework may deliver several terminal transitions; a checked
/// continuation traps on a second resume. Same guard as `StorageSCP.swift`.
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isSet = false

    func trySet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if isSet { return false }
        isSet = true
        return true
    }
}

// MARK: - Print job store

/// Print Job SOP Instances, shared by every association of one server.
///
/// Film session state dies with its association (PS3.4 H.4), but a Print Job
/// SOP Instance is exactly the part that must not: an SCU prints, releases,
/// and N-GETs the job's execution status over a later association. Keeping
/// jobs on the association made that query answer 0x0112 (no such SOP
/// Instance) the moment the print association closed.
///
/// Bounded, newest kept, so a long-running emulator does not grow forever.
actor PrintSCPJobStore {

    /// The most recent jobs retained.
    static let retentionLimit = 100

    private var jobs: [String: PrintSCPJobRecord] = [:]
    /// Originator (2100,0070) per job: the calling AE title of the
    /// association that issued the print (PS3.3 Table C.13-8).
    private var originators: [String: String] = [:]
    /// Insertion order, oldest first, for eviction.
    private var order: [String] = []

    /// Inserts or updates a job record, evicting the oldest past the limit.
    ///
    /// `originator` is recorded on first insertion and kept on updates.
    func set(_ job: PrintSCPJobRecord, originator: String? = nil) {
        if jobs[job.printJobUID] == nil {
            order.append(job.printJobUID)
            while order.count > Self.retentionLimit {
                let evicted = order.removeFirst()
                jobs.removeValue(forKey: evicted)
                originators.removeValue(forKey: evicted)
            }
        }
        jobs[job.printJobUID] = job
        if let originator { originators[job.printJobUID] = originator }
    }

    /// The job for a Print Job SOP Instance UID, if still retained.
    func job(for uid: String) -> PrintSCPJobRecord? {
        jobs[uid]
    }

    /// The AE title that issued the print for a job, if recorded.
    func originator(for uid: String) -> String? {
        originators[uid]
    }
}

// MARK: - Server

/// DICOM Print Server (SCP) — a printer emulator.
///
/// ## Usage
///
/// ```swift
/// let handler = CollectingPrintHandler()
/// let server = DICOMPrintServer(
///     configuration: PrintSCPConfiguration(aeTitle: try AETitle("DCMPRINT"), port: 11112),
///     delegate: handler)
/// try await server.start()
///
/// for await event in server.events {
///     if case .filmPrinted(let film) = event { print(film) }
/// }
/// ```
public actor DICOMPrintServer {

    /// Server configuration.
    public let configuration: PrintSCPConfiguration

    /// Receives the films this printer produces.
    private let delegate: any PrintSCPDelegate

    /// The network listener.
    private var listener: NWListener?

    /// Active associations, keyed by identity.
    private var activeAssociations: [ObjectIdentifier: PrintSCPAssociation] = [:]

    /// Print jobs across all associations, so status is queryable after release.
    private let jobStore = PrintSCPJobStore()

    /// Event stream continuation.
    private var eventContinuation: AsyncStream<PrintServerEvent>.Continuation?

    /// Whether the server is running.
    public private(set) var isRunning: Bool = false

    /// How long `start()` waits for the listener to reach `.ready`/`.failed`
    /// before giving up on a listener stuck in `.waiting`.
    private static let listenerStartTimeout: TimeInterval = 10

    public init(configuration: PrintSCPConfiguration, delegate: any PrintSCPDelegate) {
        self.configuration = configuration
        self.delegate = delegate
    }

    /// Event stream for monitoring printer activity.
    public var events: AsyncStream<PrintServerEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                Task { await self.handleStreamTermination() }
            }
        }
    }

    /// The port the listener actually bound.
    ///
    /// Differs from `configuration.port` when it was 0 (ephemeral port), which
    /// is how tests bind without racing for a fixed port.
    public private(set) var boundPort: UInt16 = 0

    /// Starts listening.
    ///
    /// - Throws: `DICOMNetworkError.connectionFailed` when the port cannot be bound.
    public func start() async throws {
        guard !isRunning else {
            throw DICOMNetworkError.invalidState("Print server is already running")
        }

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        parameters.allowLocalEndpointReuse = true

        let listener: NWListener
        if configuration.port == 0 {
            listener = try NWListener(using: parameters, on: .any)
        } else {
            guard let port = NWEndpoint.Port(rawValue: configuration.port) else {
                throw DICOMNetworkError.invalidPDU("Invalid port: \(configuration.port)")
            }
            listener = try NWListener(using: parameters, on: port)
        }
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { await self.handleNewConnection(connection) }
        }

        // NWListener.start() is asynchronous: binding failures (EADDRINUSE and
        // friends) surface via the state handler, not by throwing here. Wait for
        // `.ready`/`.failed` so callers never see "started" for a listener that
        // never bound. `.waiting` is NOT terminal — Network.framework retries it
        // indefinitely — so race the wait against a fixed timeout.
        // (Both behaviors were hard-won in `StorageSCP.start()`; keep them in step.)
        let resumed = LockedFlag()
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        listener.stateUpdateHandler = { state in
                            switch state {
                            case .ready:
                                guard resumed.trySet() else { return }
                                continuation.resume()
                            case .failed(let error):
                                guard resumed.trySet() else { return }
                                listener.cancel()
                                continuation.resume(
                                    throwing: DICOMNetworkError.connectionFailed(error.localizedDescription))
                            default:
                                break
                            }
                        }
                        listener.start(queue: .global(qos: .userInitiated))
                    }
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(Self.listenerStartTimeout))
                    throw DICOMNetworkError.timeout
                }
                try await group.next()
                group.cancelAll()
            }
        } catch {
            if resumed.trySet() {
                listener.cancel()
            }
            throw error
        }

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { await self.handleListenerState(state) }
        }

        boundPort = listener.port?.rawValue ?? configuration.port
        isRunning = true
        eventContinuation?.yield(.started(port: boundPort))
    }

    /// Stops listening and closes every open association.
    public func stop() async {
        guard isRunning else { return }

        if let listener = listener {
            // Wait for full cancellation so the port is released before a restart.
            let resumed = LockedFlag()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                listener.stateUpdateHandler = { state in
                    if case .cancelled = state {
                        guard resumed.trySet() else { return }
                        continuation.resume()
                    }
                }
                listener.cancel()
            }
        }
        listener = nil

        for association in activeAssociations.values {
            await association.abort()
        }
        activeAssociations.removeAll()

        isRunning = false
        eventContinuation?.yield(.stopped)
        eventContinuation?.finish()
    }

    /// Number of active associations.
    public var activeAssociationCount: Int { activeAssociations.count }

    // MARK: Private

    private func handleStreamTermination() {
        eventContinuation = nil
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .failed(let error):
            listener?.cancel()
            listener = nil
            isRunning = false
            eventContinuation?.yield(.error(DICOMNetworkError.connectionFailed(error.localizedDescription)))
        case .cancelled:
            isRunning = false
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) async {
        // At capacity, still read the A-ASSOCIATE-RQ and answer with a proper
        // A-ASSOCIATE-RJ (transient / local-limit-exceeded). Dropping the socket
        // instead surfaces on the modality as "connection reset by printer",
        // which its retry logic cannot act on — a rejection it understands.
        let atCapacity = activeAssociations.count >= configuration.maxConcurrentAssociations

        let association = PrintSCPAssociation(
            connection: connection,
            configuration: configuration,
            delegate: delegate,
            jobStore: jobStore,
            rejectAtCapacity: atCapacity,
            eventHandler: { [weak self] event in
                await self?.handleAssociationEvent(event)
            },
            completionHandler: { [weak self] finished in
                await self?.removeAssociation(finished)
            }
        )

        // A rejected association never counts against the limit.
        if !atCapacity {
            activeAssociations[ObjectIdentifier(association)] = association
        }
        await association.start()
    }

    private func handleAssociationEvent(_ event: PrintServerEvent) {
        eventContinuation?.yield(event)
    }

    private func removeAssociation(_ association: PrintSCPAssociation) {
        activeAssociations.removeValue(forKey: ObjectIdentifier(association))
    }
}

// MARK: - Association

/// Handles a single Print SCP association and owns its N-service state.
///
/// Print state (film session → film boxes → image boxes) is scoped to the
/// association by PS3.4 H.4: a Film Session UID does not survive a release.
actor PrintSCPAssociation {

    // MARK: Transport

    private let connection: NWConnection
    private let configuration: PrintSCPConfiguration
    private let delegate: any PrintSCPDelegate
    private let eventHandler: @Sendable (PrintServerEvent) async -> Void
    private let completionHandler: @Sendable (PrintSCPAssociation) async -> Void

    /// When set, the association is rejected as soon as the request is read:
    /// the server was already at `maxConcurrentAssociations`.
    private let rejectAtCapacity: Bool

    /// Negotiated contexts: id → (abstract syntax, transfer syntax).
    private var acceptedContexts: [UInt8: (abstractSyntax: String, transferSyntax: String)] = [:]

    private var callingAETitle: String = ""
    private var maxPDUSize: UInt32 = defaultMaxPDUSize
    private var messageAssembler = MessageAssembler()
    private var isEstablished = false

    /// Set by the idle watchdog so the failed read is reported as a timeout
    /// rather than as a transport error.
    private var idleTimedOut = false

    // MARK: Print state

    private var filmSession: FilmSession?
    private var filmSessionUID: String?
    private var filmBoxes: [String: PrintSCPParser.FilmBoxAttributes] = [:]
    private var filmBoxOrder: [String] = []
    private var filmBoxImageBoxUIDs: [String: [String]] = [:]
    private var imageBoxes: [String: ReceivedImageBox] = [:]
    private var presentationLUTs: [String: PresentationLUTShape?] = [:]
    private var annotationBoxes: [String: PrintAnnotation] = [:]

    /// Server-wide: a Print Job SOP Instance outlives this association
    /// (PS3.4 H.4.5), so status queries on later associations can find it.
    private let jobStore: PrintSCPJobStore

    /// UID allocator; a dedicated root keeps emulator UIDs recognizable.
    private let uidGenerator = UIDGenerator()

    init(
        connection: NWConnection,
        configuration: PrintSCPConfiguration,
        delegate: any PrintSCPDelegate,
        jobStore: PrintSCPJobStore,
        rejectAtCapacity: Bool = false,
        eventHandler: @escaping @Sendable (PrintServerEvent) async -> Void,
        completionHandler: @escaping @Sendable (PrintSCPAssociation) async -> Void
    ) {
        self.connection = connection
        self.configuration = configuration
        self.delegate = delegate
        self.jobStore = jobStore
        self.rejectAtCapacity = rejectAtCapacity
        self.eventHandler = eventHandler
        self.completionHandler = completionHandler
    }

    // MARK: Lifecycle

    func start() async {
        connection.start(queue: .global(qos: .userInitiated))

        let resumed = LockedFlag()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready, .failed, .cancelled:
                    guard resumed.trySet() else { return }
                    continuation.resume()
                default:
                    break
                }
            }
        }
        connection.stateUpdateHandler = nil

        guard connection.state == .ready else {
            await completionHandler(self)
            return
        }

        do {
            try await handleAssociation()
        } catch {
            // A peer that drops the socket instead of releasing is routine; only
            // surface errors while the association was actually established.
            if isEstablished {
                await eventHandler(.error(error))
            }
            connection.cancel()
        }

        await completionHandler(self)
    }

    func abort() async {
        let abortPDU = AbortPDU(source: .serviceProvider, reason: AbortReason.notSpecified.rawValue)
        try? await send(pdu: abortPDU)
        connection.cancel()
        isEstablished = false
    }

    // MARK: Association negotiation

    private func handleAssociation() async throws {
        guard let request = try await receivePDU() as? AssociateRequestPDU else {
            try await sendAbort(reason: .unexpectedPDU)
            return
        }

        callingAETitle = request.callingAETitle.value

        guard !rejectAtCapacity else {
            // PS3.8 9.3.4: source = DICOM UL service-provider (presentation
            // related), reason 2 = local-limit-exceeded. Transient, so the SCU
            // knows to retry rather than treating the printer as misconfigured.
            try await sendAssociateReject(
                result: .rejectedTransient, source: .serviceProviderPresentation, reason: 2)
            await eventHandler(.associationRejected(
                callingAE: callingAETitle,
                reason: "Maximum concurrent associations "
                    + "(\(configuration.maxConcurrentAssociations)) reached"))
            return
        }

        guard request.isProtocolVersionSupported else {
            // PS3.8 Table 9-11: only bit 0 of Protocol-version is tested;
            // source 2 (ACSE), reason 2 = protocol-version-not-supported.
            try await sendAssociateReject(result: .rejectedPermanent, source: .serviceProviderACSE, reason: 2)
            await eventHandler(.associationRejected(callingAE: callingAETitle, reason: "Protocol version not supported"))
            return
        }

        guard configuration.isCallingAEAllowed(callingAETitle) else {
            // PS3.8 Table 9-21: source 1, reason 3 = calling-AE-title-not-recognized.
            try await sendAssociateReject(result: .rejectedPermanent, source: .serviceUser, reason: 3)
            await eventHandler(.associationRejected(callingAE: callingAETitle, reason: "Calling AE not allowed"))
            return
        }

        let calledAE = request.calledAETitle.value
        guard calledAE == configuration.aeTitle.value else {
            try await sendAssociateReject(result: .rejectedPermanent, source: .serviceUser, reason: 7)
            await eventHandler(.associationRejected(callingAE: callingAETitle, reason: "Called AE mismatch"))
            return
        }

        let info = AssociationInfo(
            callingAETitle: callingAETitle,
            calledAETitle: calledAE,
            remoteHost: connection.endpoint.debugDescription,
            remotePort: 0,
            proposedSOPClasses: request.presentationContexts.map { $0.abstractSyntax },
            proposedTransferSyntaxes: request.presentationContexts.flatMap { $0.transferSyntaxes }
        )

        guard await delegate.shouldAcceptAssociation(from: info) else {
            try await sendAssociateReject(result: .rejectedPermanent, source: .serviceUser, reason: 1)
            await eventHandler(.associationRejected(callingAE: callingAETitle, reason: "Rejected by delegate"))
            return
        }

        let accepted = negotiate(request.presentationContexts)
        // PS3.8 Annex D.1: a peer value of 0 means no maximum length was specified.
        maxPDUSize = negotiatedMaxPDUSize(local: configuration.maxPDUSize, remote: request.maxPDUSize)

        let acceptPDU = AssociateAcceptPDU(
            calledAETitle: configuration.aeTitle,
            callingAETitle: request.callingAETitle,
            presentationContexts: accepted,
            maxPDUSize: configuration.maxPDUSize,
            implementationClassUID: configuration.implementationClassUID,
            implementationVersionName: configuration.implementationVersionName
        )
        try await send(pdu: acceptPDU)
        isEstablished = true
        await eventHandler(.associationEstablished(info))

        try await processMessages()
    }

    /// Accepts the Print Management (and Verification) abstract syntaxes,
    /// preferring Explicit VR LE but accepting an implicit-only proposal.
    private func negotiate(_ proposed: [PresentationContext]) -> [AcceptedPresentationContext] {
        var accepted: [AcceptedPresentationContext] = []
        let supported = configuration.effectiveSOPClasses

        for context in proposed {
            guard supported.contains(context.abstractSyntax) else {
                accepted.append(AcceptedPresentationContext(
                    id: context.id, result: .abstractSyntaxNotSupported))
                continue
            }
            let selected = PrintSCPConfiguration.acceptedTransferSyntaxes
                .first { context.transferSyntaxes.contains($0) }
            guard let transferSyntax = selected else {
                accepted.append(AcceptedPresentationContext(
                    id: context.id, result: .transferSyntaxesNotSupported))
                continue
            }
            accepted.append(AcceptedPresentationContext(
                id: context.id, result: .acceptance, transferSyntax: transferSyntax))
            acceptedContexts[context.id] = (context.abstractSyntax, transferSyntax)
        }
        return accepted
    }

    /// Whether the context negotiated Explicit VR LE.
    private func usesExplicitVR(_ contextID: UInt8) -> Bool {
        acceptedContexts[contextID]?.transferSyntax != implicitVRLittleEndianTransferSyntaxUID
    }

    // MARK: Message loop

    private func processMessages() async throws {
        while isEstablished {
            let pdu: any PDU
            do {
                pdu = try await receiveNextPDU()
            } catch is AssociationIdleTimeout {
                // The peer went quiet mid-association; the watchdog has already
                // aborted and closed it. Report and free the slot.
                await eventHandler(.associationTimedOut(
                    callingAE: callingAETitle,
                    afterSeconds: configuration.associationIdleTimeout))
                isEstablished = false
                return
            }

            switch pdu {
            case let dataPDU as DataTransferPDU:
                if let message = try messageAssembler.addPDVs(from: dataPDU) {
                    messageAssembler = MessageAssembler()
                    try await handle(message: message)
                }

            case _ as ReleaseRequestPDU:
                try await send(pdu: ReleaseResponsePDU())
                isEstablished = false
                connection.cancel()
                await eventHandler(.associationReleased(callingAE: callingAETitle))

            case let abortPDU as AbortPDU:
                isEstablished = false
                connection.cancel()
                await eventHandler(.error(DICOMNetworkError.associationAborted(
                    source: abortPDU.source, reason: abortPDU.reason)))

            default:
                try await sendAbort(reason: .unexpectedPDU)
                isEstablished = false
            }
        }
    }

    private func handle(message: AssembledMessage) async throws {
        guard let command = message.commandSet.command else { return }

        // The SCU's acknowledgement of a pushed N-EVENT-REPORT needs no reply.
        if command == .nEventReportResponse { return }

        let contextID = message.presentationContextID
        let messageID = message.commandSet.messageID ?? 0
        let sopClass = message.commandSet.requestedSOPClassUID
            ?? message.commandSet.affectedSOPClassUID ?? ""
        let sopInstance = message.commandSet.requestedSOPInstanceUID
            ?? message.commandSet.affectedSOPInstanceUID ?? ""

        if command == .cEchoRequest {
            let response = CEchoResponse(
                messageIDBeingRespondedTo: messageID,
                affectedSOPClassUID: sopClass.isEmpty ? verificationSOPClassUID : sopClass,
                status: .success,
                presentationContextID: contextID)
            try await send(commandSet: response.commandSet, dataSet: nil, contextID: contextID)
            return
        }

        let attributes: PrintAttributeSet
        do {
            if let dataSet = message.dataSet, !dataSet.isEmpty {
                attributes = try PrintDatasetReader(explicitVR: usesExplicitVR(contextID)).parse(dataSet)
            } else {
                attributes = PrintAttributeSet()
            }
        } catch {
            try await respond(
                to: command, messageID: messageID, sopClass: sopClass, sopInstance: sopInstance,
                failure: PrintSCPFailure(.processingFailure, comment: "Malformed data set: \(error)"),
                contextID: contextID)
            return
        }

        do {
            let outcome = try await perform(
                command: command, sopClass: sopClass, sopInstance: sopInstance,
                actionTypeID: message.commandSet.actionTypeID,
                attributes: attributes, contextID: contextID)
            try await respond(
                to: command, messageID: messageID,
                sopClass: outcome.sopClass ?? sopClass,
                sopInstance: outcome.sopInstance ?? sopInstance,
                status: outcome.status, comment: nil,
                actionTypeID: outcome.actionTypeID,
                dataSet: outcome.dataSet, contextID: contextID)
            for event in outcome.events { await eventHandler(event) }
            for push in outcome.pushEvents {
                try await pushEvent(push, contextID: contextID)
            }
        } catch let failure as PrintSCPFailure {
            await eventHandler(.requestFailed(
                command: command, status: failure.status, detail: failure.comment))
            try await respond(
                to: command, messageID: messageID, sopClass: sopClass, sopInstance: sopInstance,
                failure: failure, contextID: contextID)
        } catch let failure as PrintSCPRawFailure {
            // A code with no public `PrintSCPStatus` case: the event carries
            // the nearest case, the detail carries the exact code.
            let detail = String(format: "0x%04X: ", failure.code) + failure.comment
            await eventHandler(.requestFailed(
                command: command, status: failure.reportedAs, detail: detail))
            try await respond(
                to: command, messageID: messageID, sopClass: sopClass, sopInstance: sopInstance,
                status: failure.code, comment: failure.comment,
                actionTypeID: nil, dataSet: nil, contextID: contextID)
        }
    }

    // MARK: N-service dispatch

    /// What a handled N-service produced.
    private struct Outcome {
        /// The wire status: a ``PrintSCPStatus`` raw value or one of
        /// ``PrintSCPWireStatus``.
        var status: UInt16 = PrintSCPStatus.success.rawValue
        var sopClass: String?
        var sopInstance: String?
        var actionTypeID: UInt16?
        var dataSet: Data?
        var events: [PrintServerEvent] = []
        var pushEvents: [PushedEvent] = []
    }

    /// An N-EVENT-REPORT to push after the current response.
    private struct PushedEvent {
        let sopClassUID: String
        let sopInstanceUID: String
        let eventTypeID: UInt16
        let dataSet: Data?
    }

    private func perform(
        command: DIMSECommand,
        sopClass: String,
        sopInstance: String,
        actionTypeID: UInt16?,
        attributes: PrintAttributeSet,
        contextID: UInt8
    ) async throws -> Outcome {
        switch command {
        case .nCreateRequest:
            return try nCreate(
                sopClass: sopClass, requestedSOPInstance: sopInstance,
                attributes: attributes, contextID: contextID)
        case .nSetRequest:
            return try nSet(sopClass: sopClass, sopInstance: sopInstance, attributes: attributes)
        case .nActionRequest:
            return try await nAction(
                sopClass: sopClass, sopInstance: sopInstance,
                actionTypeID: actionTypeID ?? 1, contextID: contextID)
        case .nDeleteRequest:
            return try nDelete(sopClass: sopClass, sopInstance: sopInstance)
        case .nGetRequest:
            return try await nGet(sopClass: sopClass, sopInstance: sopInstance, contextID: contextID)
        default:
            // PS3.7 Annex C: "Unrecognized operation" (0211H) — the SCU sent
            // a DIMSE operation this Service Class does not define.
            throw PrintSCPRawFailure(
                PrintSCPWireStatus.unrecognizedOperation,
                comment: "Unrecognized DIMSE operation: \(command)",
                reportedAs: .sopClassNotSupported)
        }
    }

    // MARK: N-CREATE

    /// The SOP Instance UID to assign to a newly created object.
    ///
    /// PS3.7 10.1.5 lets the SCU supply the Affected SOP Instance UID on
    /// N-CREATE, and several Print SCUs (dcm4che-based ones in particular) do
    /// exactly that, then keep using *their* UID for the follow-up N-SET /
    /// N-ACTION regardless of what the response carries. Minting our own UID
    /// unconditionally made those jobs fail at N-ACTION with "Unknown Film
    /// Session", so honor the requested UID whenever the SCU offers one.
    private func assignedUID(requested: String) -> String {
        let trimmed = requested.trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
        guard !trimmed.isEmpty, trimmed.count <= 64,
              trimmed.allSatisfy({ $0.isNumber || $0 == "." })
        else { return uidGenerator.generate().value }
        return trimmed
    }

    private func nCreate(
        sopClass: String,
        requestedSOPInstance: String,
        attributes: PrintAttributeSet,
        contextID: UInt8
    ) throws -> Outcome {
        switch sopClass {
        case basicFilmSessionSOPClassUID:
            guard filmSessionUID == nil else {
                throw PrintSCPFailure(
                    .duplicateSOPInstance,
                    comment: "A Film Session already exists on this association")
            }
            let uid = assignedUID(requested: requestedSOPInstance)
            var session = FilmSession(sopInstanceUID: uid)
            try PrintSCPParser.applyFilmSession(attributes, to: &session, configuration: configuration)
            filmSession = session
            filmSessionUID = uid
            return Outcome(
                sopClass: basicFilmSessionSOPClassUID,
                sopInstance: uid,
                events: [.filmSessionCreated(uid: uid, callingAE: callingAETitle)])

        case basicFilmBoxSOPClassUID:
            guard let sessionUID = filmSessionUID else {
                throw PrintSCPFailure(
                    .unableToProcess,
                    comment: "Film Box N-CREATE before a Film Session was created")
            }
            let rawFormat = try PrintSCPParser.imageDisplayFormat(in: attributes)
            let format = PrintImageDisplayFormat.parse(rawFormat)
            guard format.imageBoxCount <= configuration.maxImageBoxesPerFilm else {
                throw PrintSCPFailure(
                    .unableToProcess,
                    comment: "Image Display Format requests \(format.imageBoxCount) image boxes; "
                        + "this printer supports \(configuration.maxImageBoxesPerFilm)")
            }

            let filmBoxUID = assignedUID(requested: requestedSOPInstance)
            guard filmBoxes[filmBoxUID] == nil else {
                throw PrintSCPFailure(
                    .duplicateSOPInstance, comment: "Film Box \(filmBoxUID) already exists")
            }
            let imageBoxUIDs = (0..<format.imageBoxCount).map { _ in uidGenerator.generate().value }
            let imageBoxSOPClass = imageBoxSOPClassUID(forContext: contextID)

            var box = PrintSCPParser.FilmBoxAttributes(filmBox: FilmBox(
                sopInstanceUID: filmBoxUID,
                imageDisplayFormat: format.raw,
                imageBoxSOPInstanceUIDs: imageBoxUIDs))
            try PrintSCPParser.applyFilmBox(attributes, to: &box, configuration: configuration)

            // A film box that names an Annotation Display Format gets a set of
            // Basic Annotation Boxes to fill: the SCU reads their UIDs out of
            // the Referenced Basic Annotation Box Sequence in this response and
            // N-SETs the ones it needs (PS3.4 H.4.4).
            var annotationBoxUIDs: [String] = []
            if configuration.acceptAnnotationBox,
               box.annotationDisplayFormatID != nil,
               configuration.annotationBoxesPerFilm > 0 {
                annotationBoxUIDs = (0..<configuration.annotationBoxesPerFilm)
                    .map { _ in uidGenerator.generate().value }
                for (index, uid) in annotationBoxUIDs.enumerated() {
                    annotationBoxes[uid] = PrintAnnotation(position: UInt16(index + 1), text: "")
                }
                box.referencedAnnotationBoxUIDs = annotationBoxUIDs
            }

            filmBoxes[filmBoxUID] = box
            filmBoxOrder.append(filmBoxUID)
            filmBoxImageBoxUIDs[filmBoxUID] = imageBoxUIDs
            for (index, uid) in imageBoxUIDs.enumerated() {
                imageBoxes[uid] = ReceivedImageBox(
                    sopInstanceUID: uid,
                    sopClassUID: imageBoxSOPClass,
                    content: ImageBoxContent(
                        sopInstanceUID: uid, imagePosition: UInt16(index + 1)),
                    image: nil)
            }

            return Outcome(
                sopClass: basicFilmBoxSOPClassUID,
                sopInstance: filmBoxUID,
                dataSet: PrintSCPEncoder.filmBoxCreateResponse(
                    filmSessionUID: sessionUID,
                    imageBoxSOPClassUID: imageBoxSOPClass,
                    imageBoxUIDs: imageBoxUIDs,
                    annotationBoxUIDs: annotationBoxUIDs,
                    explicitVR: usesExplicitVR(contextID)),
                events: [.filmBoxCreated(
                    uid: filmBoxUID, layout: format.layout, imageBoxUIDs: imageBoxUIDs)])

        case presentationLUTSOPClassUID:
            guard configuration.acceptPresentationLUT else {
                throw PrintSCPFailure(
                    .sopClassNotSupported, comment: "Presentation LUT is not supported")
            }
            let uid = assignedUID(requested: requestedSOPInstance)
            // Only the shape is honored during composition; LUT *data* tables are
            // a documented gap (see PRINT_SCP_CONFORMANCE).
            presentationLUTs[uid] = try PrintSCPParser.presentationLUTShape(in: attributes)
            return Outcome(sopClass: presentationLUTSOPClassUID, sopInstance: uid)

        case basicAnnotationBoxSOPClassUID:
            guard configuration.acceptAnnotationBox else {
                throw PrintSCPFailure(
                    .sopClassNotSupported, comment: "Basic Annotation Box is not supported")
            }
            let uid = assignedUID(requested: requestedSOPInstance)
            if let annotation = PrintSCPParser.annotation(in: attributes) {
                annotationBoxes[uid] = annotation
            }
            return Outcome(sopClass: basicAnnotationBoxSOPClassUID, sopInstance: uid)

        default:
            throw PrintSCPFailure(
                .sopClassNotSupported, comment: "N-CREATE not supported for SOP Class \(sopClass)")
        }
    }

    /// The Image Box SOP Class to hand back for a film box created on `contextID`.
    private func imageBoxSOPClassUID(forContext contextID: UInt8) -> String {
        let abstractSyntax = acceptedContexts[contextID]?.abstractSyntax ?? ""
        let isColor = abstractSyntax == basicColorPrintManagementMetaSOPClassUID
            || abstractSyntax == basicColorImageBoxSOPClassUID
        return isColor && configuration.supportsColor
            ? basicColorImageBoxSOPClassUID
            : basicGrayscaleImageBoxSOPClassUID
    }

    // MARK: N-SET

    private func nSet(
        sopClass: String,
        sopInstance: String,
        attributes: PrintAttributeSet
    ) throws -> Outcome {
        switch sopClass {
        case basicFilmSessionSOPClassUID:
            guard var session = filmSession, session.sopInstanceUID == sopInstance else {
                throw PrintSCPFailure(.noSuchSOPInstance, comment: "Unknown Film Session \(sopInstance)")
            }
            try PrintSCPParser.applyFilmSession(attributes, to: &session, configuration: configuration)
            filmSession = session
            return Outcome(sopClass: sopClass, sopInstance: sopInstance)

        case basicFilmBoxSOPClassUID:
            guard var box = filmBoxes[sopInstance] else {
                throw PrintSCPFailure(.noSuchSOPInstance, comment: "Unknown Film Box \(sopInstance)")
            }
            try PrintSCPParser.applyFilmBox(attributes, to: &box, configuration: configuration)
            filmBoxes[sopInstance] = box
            return Outcome(sopClass: sopClass, sopInstance: sopInstance)

        case basicGrayscaleImageBoxSOPClassUID, basicColorImageBoxSOPClassUID:
            guard let existing = imageBoxes[sopInstance] else {
                throw PrintSCPFailure(.noSuchSOPInstance, comment: "Unknown Image Box \(sopInstance)")
            }
            let isColor = sopClass == basicColorImageBoxSOPClassUID
            let parsed = try PrintSCPParser.parseImageBox(
                attributes,
                sopInstanceUID: sopInstance,
                isColor: isColor,
                existing: existing.content,
                configuration: configuration)
            imageBoxes[sopInstance] = ReceivedImageBox(
                sopInstanceUID: sopInstance,
                sopClassUID: sopClass,
                content: parsed.content,
                image: parsed.image ?? existing.image)

            var outcome = Outcome(sopClass: sopClass, sopInstance: sopInstance)
            if let image = parsed.image {
                outcome.events = [.imageBoxReceived(
                    uid: sopInstance, position: parsed.content.imagePosition,
                    rows: image.rows, columns: image.columns)]
                // Corrections are reported after the box itself, so the log
                // reads in the order things happened: the box arrived, and then
                // this is what had to be changed about it.
                outcome.events.append(contentsOf: parsed.conformanceNotes.map {
                    .imageBoxCorrected(
                        uid: sopInstance,
                        position: parsed.content.imagePosition,
                        detail: $0)
                })
            }
            return outcome

        case basicAnnotationBoxSOPClassUID:
            guard annotationBoxes[sopInstance] != nil else {
                throw PrintSCPFailure(.noSuchSOPInstance, comment: "Unknown Annotation Box \(sopInstance)")
            }
            if let annotation = PrintSCPParser.annotation(in: attributes) {
                annotationBoxes[sopInstance] = annotation
            }
            return Outcome(sopClass: sopClass, sopInstance: sopInstance)

        default:
            throw PrintSCPFailure(
                .sopClassNotSupported, comment: "N-SET not supported for SOP Class \(sopClass)")
        }
    }

    // MARK: N-ACTION (print)

    /// Film Session (PS3.4 H.4.1.2.4) and Film Box (H.4.2.2.4) N-ACTION,
    /// Action Type ID 1 "Print".
    ///
    /// The response identifies the instance the action was invoked on (PS3.7
    /// N-ACTION-RSP: Affected SOP Class / Instance UID), and the Print Job it
    /// created travels in the data set as Referenced Print Job Sequence
    /// (2100,0500) — Tables H.4-3 and H.4-8.
    private func nAction(
        sopClass: String,
        sopInstance: String,
        actionTypeID: UInt16,
        contextID: UInt8
    ) async throws -> Outcome {
        guard actionTypeID == 1 else {
            // PS3.7 §10.1.4.1.10: "No such Action" — the Action Type ID
            // specified was not supported.
            throw PrintSCPRawFailure(
                PrintSCPWireStatus.noSuchAction,
                comment: "Unsupported Action Type ID \(actionTypeID)",
                reportedAs: .invalidAttributeValue)
        }

        let filmBoxUIDs: [String]
        let emptyPageWarning: UInt16
        switch sopClass {
        case basicFilmBoxSOPClassUID:
            guard filmBoxes[sopInstance] != nil else {
                throw PrintSCPFailure(.noSuchSOPInstance, comment: "Unknown Film Box \(sopInstance)")
            }
            filmBoxUIDs = [sopInstance]
            emptyPageWarning = PrintSCPWireStatus.filmBoxEmptyPage

        case basicFilmSessionSOPClassUID:
            guard let sessionUID = filmSessionUID, sessionUID == sopInstance else {
                throw PrintSCPFailure(.noSuchSOPInstance, comment: "Unknown Film Session \(sopInstance)")
            }
            // PS3.4 Table H.4-4, C600: "Film Session SOP Instance hierarchy
            // does not contain Film Box SOP Instances".
            guard !filmBoxOrder.isEmpty else {
                throw PrintSCPFailure(.filmSessionPrinting)
            }
            filmBoxUIDs = filmBoxOrder
            emptyPageWarning = PrintSCPWireStatus.filmSessionEmptyPage

        default:
            throw PrintSCPFailure(
                .sopClassNotSupported, comment: "N-ACTION not supported for SOP Class \(sopClass)")
        }

        var outcome = Outcome()
        var lastJobUID: String?
        var printedEmptyPage = false

        for filmBoxUID in filmBoxUIDs {
            let printed = try await print(filmBoxUID: filmBoxUID, contextID: contextID, into: &outcome)
            lastJobUID = printed.jobUID
            printedEmptyPage = printedEmptyPage || printed.isEmptyPage
        }

        // Tables H.4-4 (B602) / H.4-9 (B603): a hierarchy without Image Box
        // content is printed as an empty page and answered with a warning,
        // not refused.
        if printedEmptyPage {
            outcome.status = emptyPageWarning
        }
        outcome.sopClass = sopClass
        outcome.sopInstance = sopInstance
        outcome.actionTypeID = actionTypeID
        if let lastJobUID {
            outcome.dataSet = PrintSCPEncoder.printJobReference(
                printJobUID: lastJobUID, explicitVR: usesExplicitVR(contextID))
        }
        return outcome
    }

    /// What ``print(filmBoxUID:contextID:into:)`` produced.
    private struct PrintedFilm {
        /// The Print Job SOP Instance UID allocated for the film.
        let jobUID: String
        /// Whether no image box carried pixels, so the film is an empty page.
        let isEmptyPage: Bool
    }

    /// Composes one film's ``ReceivedFilm`` and hands it to the delegate.
    ///
    /// A film box whose image boxes were never filled is still printed — as
    /// an empty page showing Empty Image Density — because PS3.4 Table H.4-9
    /// makes that a warning (B603), not a failure. The caller turns
    /// `isEmptyPage` into that status.
    private func print(
        filmBoxUID: String,
        contextID: UInt8,
        into outcome: inout Outcome
    ) async throws -> PrintedFilm {
        guard let box = filmBoxes[filmBoxUID] else {
            throw PrintSCPFailure(.noSuchSOPInstance, comment: "Unknown Film Box \(filmBoxUID)")
        }
        let session = filmSession ?? FilmSession(sopInstanceUID: filmSessionUID ?? "")
        let boxUIDs = filmBoxImageBoxUIDs[filmBoxUID] ?? []
        let boxes = boxUIDs.compactMap { imageBoxes[$0] }
            .sorted { $0.content.imagePosition < $1.content.imagePosition }
        let isEmptyPage = !boxes.contains(where: { $0.image != nil })

        let jobUID = uidGenerator.generate().value
        var job = PrintSCPJobRecord(
            printJobUID: jobUID,
            filmBoxUID: filmBoxUID,
            filmSessionUID: session.sopInstanceUID,
            executionStatus: "PRINTING",
            printPriority: session.printPriority,
            numberOfCopies: session.numberOfCopies)
        await jobStore.set(job, originator: callingAETitle)

        // Annotation boxes the SCU never filled stay empty; drop them rather
        // than handing the composer blank text boxes.
        let annotations = box.referencedAnnotationBoxUIDs
            .compactMap { annotationBoxes[$0] }
            .filter { !$0.text.isEmpty }
            .sorted { $0.position < $1.position }
        let lutShape = box.referencedPresentationLUTUID.flatMap { presentationLUTs[$0] ?? nil }

        let film = ReceivedFilm(
            printJobUID: jobUID,
            filmSession: session,
            filmBox: box.filmBox,
            layout: PrintImageDisplayFormat.parse(box.filmBox.imageDisplayFormat).layout,
            imageBoxes: boxes,
            minDensity: box.minDensity,
            maxDensity: box.maxDensity,
            presentationLUTShape: lutShape,
            annotationDisplayFormatID: box.annotationDisplayFormatID,
            annotations: annotations,
            callingAETitle: callingAETitle)

        do {
            try await delegate.didReceiveFilm(film)
        } catch {
            job.executionStatus = "FAILURE"
            // Execution Status Info (2100,0030) is CS: a Defined Term from
            // PS3.3 C.13.8, not the error's free text. The full error goes to
            // the delegate and to the Error Comment / event below.
            job.executionStatusInfo = Self.executionStatusInfo(for: error)
            await jobStore.set(job)
            await delegate.didFail(error: error, forPrintJob: jobUID)
            throw PrintSCPFailure(
                .processingFailure, comment: "Failed to print film: \(error)")
        }

        job.executionStatus = "DONE"
        job.executionStatusInfo = "NORMAL"
        await jobStore.set(job)

        outcome.events.append(.filmPrinted(film))
        if configuration.pushPrintJobEvents {
            outcome.pushEvents.append(PushedEvent(
                sopClassUID: printJobSOPClassUID,
                sopInstanceUID: jobUID,
                eventTypeID: PrintJobEventType.done.rawValue,
                dataSet: PrintSCPEncoder.printJobEventAttributes(
                    executionStatusInfo: "NORMAL",
                    filmSessionLabel: session.filmSessionLabel,
                    printerName: configuration.printerName,
                    explicitVR: usesExplicitVR(contextID))))
        }
        return PrintedFilm(jobUID: jobUID, isEmptyPage: isEmptyPage)
    }

    /// The Execution Status Info (2100,0030) term for a failed print.
    ///
    /// PS3.3 Table C.13-8 defines INVALID PAGE DES and INSUFFIC MEMORY for a
    /// FAILURE status and allows implementation-specific terms; the value is
    /// CS, so it must be uppercase letters, digits, space or underscore and at
    /// most 16 characters. A memory error is reported with the standard term;
    /// anything else gets the implementation term PRINT FAILURE.
    static func executionStatusInfo(for error: Error) -> String {
        let description = "\(error)".lowercased()
        if description.contains("memory") || description.contains("out of resources") {
            return "INSUFFIC MEMORY"
        }
        return "PRINT FAILURE"
    }

    // MARK: N-DELETE

    private func nDelete(sopClass: String, sopInstance: String) throws -> Outcome {
        switch sopClass {
        case basicFilmSessionSOPClassUID:
            guard let sessionUID = filmSessionUID, sessionUID == sopInstance else {
                throw PrintSCPFailure(.noSuchSOPInstance, comment: "Unknown Film Session \(sopInstance)")
            }
            for filmBoxUID in filmBoxOrder {
                deleteFilmBox(filmBoxUID)
            }
            filmBoxOrder.removeAll()
            filmSession = nil
            filmSessionUID = nil
            return Outcome(sopClass: sopClass, sopInstance: sopInstance, events: [.deleted(uid: sopInstance)])

        case basicFilmBoxSOPClassUID:
            guard filmBoxes[sopInstance] != nil else {
                throw PrintSCPFailure(.noSuchSOPInstance, comment: "Unknown Film Box \(sopInstance)")
            }
            deleteFilmBox(sopInstance)
            filmBoxOrder.removeAll { $0 == sopInstance }
            return Outcome(sopClass: sopClass, sopInstance: sopInstance, events: [.deleted(uid: sopInstance)])

        case basicAnnotationBoxSOPClassUID:
            guard annotationBoxes.removeValue(forKey: sopInstance) != nil else {
                throw PrintSCPFailure(.noSuchSOPInstance, comment: "Unknown Annotation Box \(sopInstance)")
            }
            return Outcome(sopClass: sopClass, sopInstance: sopInstance, events: [.deleted(uid: sopInstance)])

        case presentationLUTSOPClassUID:
            guard presentationLUTs.removeValue(forKey: sopInstance) != nil else {
                throw PrintSCPFailure(.noSuchSOPInstance, comment: "Unknown Presentation LUT \(sopInstance)")
            }
            return Outcome(sopClass: sopClass, sopInstance: sopInstance, events: [.deleted(uid: sopInstance)])

        default:
            throw PrintSCPFailure(
                .sopClassNotSupported, comment: "N-DELETE not supported for SOP Class \(sopClass)")
        }
    }

    /// Removes a film box and cascades to its image boxes (PS3.4 H.4.2.2.3,
    /// Film Box N-DELETE).
    private func deleteFilmBox(_ filmBoxUID: String) {
        for imageBoxUID in filmBoxImageBoxUIDs[filmBoxUID] ?? [] {
            imageBoxes.removeValue(forKey: imageBoxUID)
        }
        filmBoxImageBoxUIDs.removeValue(forKey: filmBoxUID)
        filmBoxes.removeValue(forKey: filmBoxUID)
    }

    // MARK: N-GET

    private func nGet(sopClass: String, sopInstance: String, contextID: UInt8) async throws -> Outcome {
        let explicitVR = usesExplicitVR(contextID)

        switch sopClass {
        case printerSOPClassUID:
            // The Printer SOP Instance is well-known; tolerate an SCU that sends
            // an empty instance UID rather than the standard one.
            guard sopInstance.isEmpty || sopInstance == printerSOPInstanceUID else {
                throw PrintSCPFailure(
                    .noSuchSOPInstance, comment: "Unknown Printer SOP Instance \(sopInstance)")
            }
            let status = await delegate.printerStatus()
            return Outcome(
                sopClass: printerSOPClassUID,
                sopInstance: printerSOPInstanceUID,
                dataSet: PrintSCPEncoder.printerAttributes(
                    configuration: configuration, status: status, explicitVR: explicitVR))

        case printJobSOPClassUID:
            guard let job = await jobStore.job(for: sopInstance) else {
                throw PrintSCPFailure(.noSuchSOPInstance, comment: "Unknown Print Job \(sopInstance)")
            }
            let originator = await jobStore.originator(for: sopInstance)
            return Outcome(
                sopClass: printJobSOPClassUID,
                sopInstance: sopInstance,
                dataSet: PrintSCPEncoder.printJobAttributes(
                    job, printerName: configuration.printerName,
                    originator: originator, explicitVR: explicitVR))

        case basicFilmSessionSOPClassUID:
            guard let session = filmSession, session.sopInstanceUID == sopInstance else {
                throw PrintSCPFailure(.noSuchSOPInstance, comment: "Unknown Film Session \(sopInstance)")
            }
            return Outcome(
                sopClass: sopClass,
                sopInstance: sopInstance,
                dataSet: PrintSCPEncoder.filmSessionAttributes(
                    session, filmBoxUIDs: filmBoxOrder, explicitVR: explicitVR))

        default:
            throw PrintSCPFailure(
                .sopClassNotSupported, comment: "N-GET not supported for SOP Class \(sopClass)")
        }
    }

    // MARK: Responses

    private func respond(
        to command: DIMSECommand,
        messageID: UInt16,
        sopClass: String,
        sopInstance: String,
        failure: PrintSCPFailure,
        contextID: UInt8
    ) async throws {
        try await respond(
            to: command, messageID: messageID, sopClass: sopClass, sopInstance: sopInstance,
            status: failure.status.rawValue, comment: failure.effectiveComment,
            actionTypeID: nil, dataSet: nil, contextID: contextID)
    }

    private func respond(
        to command: DIMSECommand,
        messageID: UInt16,
        sopClass: String,
        sopInstance: String,
        status: UInt16,
        comment: String?,
        actionTypeID: UInt16?,
        dataSet: Data?,
        contextID: UInt8
    ) async throws {
        guard let responseCommand = Self.responseCommand(for: command) else { return }

        let dimseStatus = DIMSEStatus.from(status)
        var commandSet = CommandSet()
        commandSet.setCommand(responseCommand)
        commandSet.setMessageIDBeingRespondedTo(messageID)
        if !sopClass.isEmpty { commandSet.setAffectedSOPClassUID(sopClass) }
        if !sopInstance.isEmpty { commandSet.setAffectedSOPInstanceUID(sopInstance) }
        if let actionTypeID { commandSet.setActionTypeID(actionTypeID) }
        commandSet.setStatus(dimseStatus)
        commandSet.setHasDataSet(dataSet != nil)
        if !dimseStatus.isSuccessOrWarning, let comment, !comment.isEmpty {
            commandSet.setErrorComment(Self.errorComment(from: comment))
        }

        try await send(commandSet: commandSet, dataSet: dataSet, contextID: contextID)
    }

    /// Prepares a string for Error Comment (0000,0902), which is LO in the
    /// default character repertoire and capped at 64 characters.
    ///
    /// Non-ASCII is transliterated rather than dropped: `CommandSet.setString`
    /// encodes as ASCII and silently yields an empty value otherwise, which
    /// would throw away the only diagnostic an SCU developer gets — and error
    /// text routinely picks up "×", "—" and friends from higher layers.
    static func errorComment(from comment: String) -> String {
        let ascii = comment.unicodeScalars.map { scalar -> Character in
            switch scalar {
            case "\u{00D7}": return "x"        // ×
            case "\u{2013}", "\u{2014}": return "-"
            case "\u{2018}", "\u{2019}": return "'"
            case "\u{201C}", "\u{201D}": return "\""
            default: return scalar.isASCII ? Character(scalar) : "?"
            }
        }
        return String(String(ascii).prefix(64))
    }

    private static func responseCommand(for command: DIMSECommand) -> DIMSECommand? {
        switch command {
        case .nCreateRequest: return .nCreateResponse
        case .nSetRequest: return .nSetResponse
        case .nActionRequest: return .nActionResponse
        case .nDeleteRequest: return .nDeleteResponse
        case .nGetRequest: return .nGetResponse
        case .nEventReportRequest: return .nEventReportResponse
        default: return nil
        }
    }

    /// Pushes an N-EVENT-REPORT to the SCU.
    ///
    /// The SCU acknowledges with N-EVENT-REPORT-RSP, which the message loop
    /// discards; we do not block waiting for it.
    private func pushEvent(_ event: PushedEvent, contextID: UInt8) async throws {
        let request = NEventReportRequest(
            messageID: UInt16.random(in: 1000...65000),
            affectedSOPClassUID: event.sopClassUID,
            affectedSOPInstanceUID: event.sopInstanceUID,
            eventTypeID: event.eventTypeID,
            hasDataSet: event.dataSet != nil,
            presentationContextID: contextID)
        try await send(commandSet: request.commandSet, dataSet: event.dataSet, contextID: contextID)
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

    private func sendAssociateReject(
        result: AssociateRejectResult,
        source: AssociateRejectSource,
        reason: UInt8
    ) async throws {
        try await send(pdu: AssociateRejectPDU(result: result, source: source, reason: reason))
        connection.cancel()
    }

    private func sendAbort(reason: AbortReason) async throws {
        try await send(pdu: AbortPDU(source: .serviceProvider, reason: reason.rawValue))
        connection.cancel()
        isEstablished = false
    }

    private func send(pdu: any PDU) async throws {
        let data = try pdu.encode()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(
                        throwing: DICOMNetworkError.connectionFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// Reads the next PDU, bounded by the configured idle timeout.
    ///
    /// The clock covers the gap *between* messages, so a printer-side pause
    /// (composition, a slow sink) never trips it — only a peer that has stopped
    /// speaking does.
    ///
    /// A watchdog task, rather than a task-group race: the pending
    /// `NWConnection.receive` is not cancellation-aware, so a group would wait
    /// forever for a child that can never finish. The watchdog instead *unblocks*
    /// the read by tearing the connection down, which resumes it with an error.
    private func receiveNextPDU() async throws -> any PDU {
        let timeout = configuration.associationIdleTimeout
        guard timeout > 0 else { return try await receivePDU() }

        idleTimedOut = false
        let watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            await self?.expireIdleAssociation()
        }
        defer { watchdog.cancel() }

        do {
            return try await receivePDU()
        } catch {
            // The read failed because the watchdog closed the connection, not
            // because the peer did something interesting.
            if idleTimedOut { throw AssociationIdleTimeout() }
            throw error
        }
    }

    /// Called by the watchdog: abort the association and unblock the read.
    private func expireIdleAssociation() async {
        guard isEstablished, !idleTimedOut else { return }
        idleTimedOut = true
        // Best effort — a peer that has genuinely vanished will never see it.
        try? await send(pdu: AbortPDU(source: .serviceProvider, reason: AbortReason.notSpecified.rawValue))
        connection.cancel()
    }

    private func receivePDU() async throws -> any PDU {
        let headerData = try await receive(length: 6)
        let (pduType, pduLength) = try PDUDecoder.readHeader(from: headerData)
        // PS3.8 Annex D.1: the negotiated limit applies to P-DATA-TF only
        try checkPDULength(type: pduType, length: pduLength, maxPDUSize: configuration.maxPDUSize)
        let bodyData = try await receive(length: Int(pduLength))
        return try PDUDecoder.decode(from: headerData + bodyData)
    }

    private func receive(length: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: length, maximumLength: length) { data, _, isComplete, error in
                if let error = error {
                    continuation.resume(
                        throwing: DICOMNetworkError.connectionFailed(error.localizedDescription))
                } else if let data = data, data.count >= length {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: DICOMNetworkError.connectionClosed)
                } else {
                    continuation.resume(
                        throwing: DICOMNetworkError.decodingFailed("Incomplete data received"))
                }
            }
        }
    }
}

#endif
