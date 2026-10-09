import Foundation
import DICOMCore

// MARK: - Storage Commitment SCP Configuration

/// Configuration for the DICOM Storage Commitment SCP (Service Class Provider)
///
/// Defines the settings for a Storage Commitment SCP that can receive commitment requests
/// and send commitment results.
///
/// Reference: PS3.4 Annex J - Storage Commitment Service Class
public struct StorageCommitmentSCPConfiguration: Sendable, Hashable {
    /// The local Application Entity title
    public let aeTitle: AETitle
    
    /// The port to listen on
    public let port: UInt16
    
    /// Maximum PDU size to accept
    public let maxPDUSize: UInt32
    
    /// Implementation Class UID for this DICOM implementation
    public let implementationClassUID: String
    
    /// Implementation Version Name (optional)
    public let implementationVersionName: String?
    
    /// Maximum number of concurrent associations
    public let maxConcurrentAssociations: Int
    
    /// Calling AE Title whitelist
    /// If nil, all calling AE titles are accepted
    public let callingAEWhitelist: Set<String>?
    
    /// Calling AE Title blacklist
    /// Takes precedence over whitelist
    public let callingAEBlacklist: Set<String>?

    /// Resolver for the N-EVENT-REPORT destination of a requesting AE
    ///
    /// When the requestor did not negotiate the SCP role for the Storage
    /// Commitment Push Model SOP Class, the result must be delivered on a new
    /// association opened by this SCP to the requestor's AE (PS3.4 J.3.3).
    /// The closure maps a calling AE title to the host and port to connect to;
    /// returning nil means the destination is unknown and the result is dropped
    /// (an `.error` event is emitted).
    ///
    /// Not part of the configuration's equality or hash.
    public let eventReportDestination: (@Sendable (String) -> (host: String, port: UInt16)?)?

    /// Connection timeout in seconds for the reverse association (default: 30)
    public let reverseAssociationTimeout: TimeInterval

    /// Default Implementation Class UID for DICOMKit Storage Commitment SCP
    public static let defaultImplementationClassUID = DICOMNetworkImplementation.classUID

    /// Default Implementation Version Name for DICOMKit Storage Commitment SCP
    public static let defaultImplementationVersionName = "DICOMKIT_SCSCP"

    /// Creates a Storage Commitment SCP configuration
    ///
    /// - Parameters:
    ///   - aeTitle: The local AE title
    ///   - port: The port to listen on (default: 11112)
    ///   - maxPDUSize: Maximum PDU size (default: 64 KB (`defaultMaxPDUSize`))
    ///   - implementationClassUID: Implementation Class UID
    ///   - implementationVersionName: Implementation Version Name
    ///   - maxConcurrentAssociations: Maximum concurrent associations (default: 10)
    ///   - callingAEWhitelist: Whitelist of calling AE titles
    ///   - callingAEBlacklist: Blacklist of calling AE titles
    ///   - eventReportDestination: Maps a calling AE title to the host/port for
    ///     reverse-association N-EVENT-REPORT delivery (default: nil)
    ///   - reverseAssociationTimeout: Connection timeout for the reverse association (default: 30)
    public init(
        aeTitle: AETitle,
        port: UInt16 = dicomAlternativePort,
        maxPDUSize: UInt32 = defaultMaxPDUSize,
        implementationClassUID: String = defaultImplementationClassUID,
        implementationVersionName: String? = defaultImplementationVersionName,
        maxConcurrentAssociations: Int = 10,
        callingAEWhitelist: Set<String>? = nil,
        callingAEBlacklist: Set<String>? = nil,
        eventReportDestination: (@Sendable (String) -> (host: String, port: UInt16)?)? = nil,
        reverseAssociationTimeout: TimeInterval = 30
    ) {
        self.aeTitle = aeTitle
        self.port = port
        self.maxPDUSize = maxPDUSize
        self.implementationClassUID = implementationClassUID
        self.implementationVersionName = implementationVersionName
        self.maxConcurrentAssociations = max(1, maxConcurrentAssociations)
        self.callingAEWhitelist = callingAEWhitelist
        self.callingAEBlacklist = callingAEBlacklist
        self.eventReportDestination = eventReportDestination
        self.reverseAssociationTimeout = reverseAssociationTimeout
    }

    // Hashable/Equatable over the value fields only (the resolver closure is excluded)

    public static func == (lhs: StorageCommitmentSCPConfiguration, rhs: StorageCommitmentSCPConfiguration) -> Bool {
        lhs.aeTitle == rhs.aeTitle &&
        lhs.port == rhs.port &&
        lhs.maxPDUSize == rhs.maxPDUSize &&
        lhs.implementationClassUID == rhs.implementationClassUID &&
        lhs.implementationVersionName == rhs.implementationVersionName &&
        lhs.maxConcurrentAssociations == rhs.maxConcurrentAssociations &&
        lhs.callingAEWhitelist == rhs.callingAEWhitelist &&
        lhs.callingAEBlacklist == rhs.callingAEBlacklist &&
        lhs.reverseAssociationTimeout == rhs.reverseAssociationTimeout
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(aeTitle)
        hasher.combine(port)
        hasher.combine(maxPDUSize)
        hasher.combine(implementationClassUID)
        hasher.combine(implementationVersionName)
        hasher.combine(maxConcurrentAssociations)
        hasher.combine(callingAEWhitelist)
        hasher.combine(callingAEBlacklist)
        hasher.combine(reverseAssociationTimeout)
    }
    
    /// Checks if a calling AE title is allowed
    ///
    /// - Parameter callingAE: The calling AE title to check
    /// - Returns: True if the calling AE is allowed
    public func isCallingAEAllowed(_ callingAE: String) -> Bool {
        // Blacklist takes precedence
        if let blacklist = callingAEBlacklist, blacklist.contains(callingAE) {
            return false
        }
        
        // If whitelist exists, calling AE must be in it
        if let whitelist = callingAEWhitelist {
            return whitelist.contains(callingAE)
        }
        
        // No whitelist means all are allowed
        return true
    }
}

// MARK: - Commitment Request Info

/// Information about a received storage commitment request
public struct CommitmentRequestInfo: Sendable {
    /// The Transaction UID for this commitment request
    public let transactionUID: String
    
    /// The SOP references requested for commitment
    public let references: [SOPReference]
    
    /// The calling AE title that made the request
    public let callingAETitle: String
    
    /// The timestamp when the request was received
    public let timestamp: Date
    
    /// Creates a commitment request info
    public init(
        transactionUID: String,
        references: [SOPReference],
        callingAETitle: String,
        timestamp: Date = Date()
    ) {
        self.transactionUID = transactionUID
        self.references = references
        self.callingAETitle = callingAETitle
        self.timestamp = timestamp
    }
}

extension CommitmentRequestInfo: CustomStringConvertible {
    public var description: String {
        "CommitmentRequestInfo(txn: \(transactionUID), count: \(references.count), from: \(callingAETitle))"
    }
}

// MARK: - Storage Commitment Delegate Protocol

/// Protocol for handling storage commitment requests
///
/// Implement this protocol to customize how commitment requests are processed.
public protocol StorageCommitmentDelegate: Sendable {
    /// Called when an association request is received
    ///
    /// - Parameter info: Information about the requesting association
    /// - Returns: True to accept the association, false to reject
    func shouldAcceptAssociation(from info: AssociationInfo) async -> Bool
    
    /// Called when a storage commitment request is received
    ///
    /// The delegate should verify that the referenced instances exist and are safe
    /// to commit (e.g., stored on reliable media). Return a CommitmentResult with
    /// the appropriate committed and failed references.
    ///
    /// - Parameter request: The commitment request information
    /// - Returns: The commitment result indicating success/failure for each instance
    func processCommitmentRequest(_ request: CommitmentRequestInfo) async throws -> CommitmentResult
}

/// Default implementation of StorageCommitmentDelegate
extension StorageCommitmentDelegate {
    public func shouldAcceptAssociation(from info: AssociationInfo) async -> Bool {
        true
    }
}

// MARK: - Storage Commitment Server Event

/// Events emitted by the Storage Commitment SCP
public enum StorageCommitmentServerEvent: Sendable {
    /// Server started listening
    case started(port: UInt16)
    
    /// Server stopped
    case stopped
    
    /// A new association was established
    case associationEstablished(AssociationInfo)
    
    /// An association was released
    case associationReleased(callingAE: String)
    
    /// An association was rejected
    case associationRejected(callingAE: String, reason: String)
    
    /// A commitment request was received
    case commitmentRequestReceived(CommitmentRequestInfo)
    
    /// A commitment result was sent
    case commitmentResultSent(transactionUID: String, success: Bool)
    
    /// An error occurred
    case error(Error)
}

// MARK: - Default Commitment Handler

/// Default commitment handler that commits all requested instances
///
/// This handler always reports success for all instances. In production use,
/// you should implement a custom delegate that verifies instance storage.
public actor DefaultCommitmentHandler: StorageCommitmentDelegate {
    
    public init() {}
    
    public func shouldAcceptAssociation(from info: AssociationInfo) async -> Bool {
        true
    }
    
    public func processCommitmentRequest(_ request: CommitmentRequestInfo) async throws -> CommitmentResult {
        // Default implementation: commit all instances successfully
        CommitmentResult(
            transactionUID: request.transactionUID,
            committedReferences: request.references,
            failedReferences: [],
            remoteAETitle: request.callingAETitle
        )
    }
}

#if canImport(Network)
import Network
// NEMA-verified: 2026a, checked 2026-09-28 — N-ACTION handling per PS3.4 2026a J.3.2 and PS3.7 §10.1.4.1.10 (0118H, 0123H); N-EVENT-REPORT per J.3.3 and Table J.3-2; PDU length per PS3.8 §9.3.1 (D13); reject reasons per Table 9-21

// MARK: - Storage Commitment Server

/// DICOM Storage Commitment Server (SCP)
///
/// Implements the DICOM Storage Commitment Service Class as a Service Class Provider (SCP).
/// This enables receiving storage commitment requests (N-ACTION) and sending
/// commitment results (N-EVENT-REPORT) to remote Service Class Users (SCUs).
///
/// Reference: PS3.4 Annex J - Storage Commitment Service Class
/// Reference: PS3.7 Section 10.1 - N-ACTION Service
/// Reference: PS3.7 Section 10.3 - N-EVENT-REPORT Service
///
/// ## Usage
///
/// ```swift
/// // Create configuration
/// let config = StorageCommitmentSCPConfiguration(
///     aeTitle: try AETitle("MY_SCP"),
///     port: 11112
/// )
///
/// // Create handler
/// let handler = DefaultCommitmentHandler()
///
/// // Create and start server
/// let server = StorageCommitmentServer(configuration: config, delegate: handler)
/// try await server.start()
///
/// // Listen for events
/// for await event in server.events {
///     switch event {
///     case .commitmentRequestReceived(let request):
///         print("Received commitment request: \(request.transactionUID)")
///     case .commitmentResultSent(let txn, let success):
///         print("Sent result for \(txn): \(success ? "success" : "with failures")")
///     case .error(let error):
///         print("Error: \(error)")
///     default:
///         break
///     }
/// }
///
/// // Stop server
/// await server.stop()
/// ```
public actor StorageCommitmentServer {
    
    /// Server configuration
    public let configuration: StorageCommitmentSCPConfiguration
    
    /// Commitment delegate for handling requests
    private let delegate: any StorageCommitmentDelegate
    
    /// The network listener
    private var listener: NWListener?
    
    /// Active associations
    private var activeAssociations: [ObjectIdentifier: CommitmentSCPAssociation] = [:]
    
    /// Event stream continuation
    private var eventContinuation: AsyncStream<StorageCommitmentServerEvent>.Continuation?
    
    /// Whether the server is running
    public private(set) var isRunning: Bool = false

    /// Recently seen Transaction UIDs, oldest first, used to reject duplicates
    private var recentTransactionUIDs: [String] = []
    private var recentTransactionUIDSet: Set<String> = []

    /// Maximum number of Transaction UIDs remembered for duplicate detection
    static let maxRememberedTransactionUIDs = 1000

    /// Creates a Storage Commitment SCP server
    ///
    /// - Parameters:
    ///   - configuration: Server configuration
    ///   - delegate: Commitment delegate for handling requests
    public init(configuration: StorageCommitmentSCPConfiguration, delegate: any StorageCommitmentDelegate) {
        self.configuration = configuration
        self.delegate = delegate
    }
    
    /// Event stream for monitoring server activity
    public var events: AsyncStream<StorageCommitmentServerEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                Task { await self.handleStreamTermination() }
            }
        }
    }
    
    /// Starts the server
    ///
    /// - Throws: `DICOMNetworkError.connectionFailed` if server fails to start
    public func start() async throws {
        guard !isRunning else {
            throw DICOMNetworkError.invalidState("Server is already running")
        }
        
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = nil
        
        guard let port = NWEndpoint.Port(rawValue: configuration.port) else {
            throw DICOMNetworkError.invalidPDU("Invalid port: \(configuration.port)")
        }
        
        let listener = try NWListener(using: parameters, on: port)
        self.listener = listener
        
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { await self.handleListenerState(state) }
        }
        
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { await self.handleNewConnection(connection) }
        }
        
        listener.start(queue: .global(qos: .userInitiated))
        isRunning = true
        
        eventContinuation?.yield(.started(port: configuration.port))
    }
    
    /// Stops the server
    public func stop() async {
        guard isRunning else { return }
        
        if let listener = listener {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                listener.stateUpdateHandler = { state in
                    if case .cancelled = state {
                        continuation.resume()
                    }
                }
                listener.cancel()
            }
        }
        listener = nil
        
        // Close all active associations
        for association in activeAssociations.values {
            await association.abort()
        }
        activeAssociations.removeAll()
        
        isRunning = false
        eventContinuation?.yield(.stopped)
        eventContinuation?.finish()
    }
    
    /// Number of active associations
    public var activeAssociationCount: Int {
        activeAssociations.count
    }
    
    /// Registers a Transaction UID; returns false if it was seen recently
    ///
    /// Reference: PS3.4 J.3.1 - the Transaction UID uniquely identifies a request
    func registerTransactionUID(_ transactionUID: String) -> Bool {
        guard !recentTransactionUIDSet.contains(transactionUID) else {
            return false
        }
        recentTransactionUIDSet.insert(transactionUID)
        recentTransactionUIDs.append(transactionUID)
        if recentTransactionUIDs.count > StorageCommitmentServer.maxRememberedTransactionUIDs {
            let evicted = recentTransactionUIDs.removeFirst()
            recentTransactionUIDSet.remove(evicted)
        }
        return true
    }

    // MARK: - Private Methods

    private func handleStreamTermination() {
        eventContinuation = nil
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .failed(let error):
            eventContinuation?.yield(.error(DICOMNetworkError.connectionFailed(error.localizedDescription)))
        case .cancelled:
            isRunning = false
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) async {
        // Check if we've reached the maximum number of associations
        guard activeAssociations.count < configuration.maxConcurrentAssociations else {
            connection.cancel()
            return
        }

        // Create a new SCP association handler
        let association = CommitmentSCPAssociation(
            connection: connection,
            configuration: configuration,
            delegate: delegate,
            eventHandler: { [weak self] event in
                await self?.handleAssociationEvent(event)
            },
            transactionRegistrar: { [weak self] transactionUID in
                await self?.registerTransactionUID(transactionUID) ?? true
            },
            completionHandler: { [weak self] completedAssociation in
                await self?.removeAssociationAsync(completedAssociation)
            }
        )
        
        let id = ObjectIdentifier(association)
        activeAssociations[id] = association
        
        // Start handling the association
        await association.start()
    }
    
    private func handleAssociationEvent(_ event: StorageCommitmentServerEvent) {
        eventContinuation?.yield(event)
    }
    
    nonisolated func removeAssociation(_ association: CommitmentSCPAssociation) {
        Task {
            await removeAssociationAsync(association)
        }
    }
    
    private func removeAssociationAsync(_ association: CommitmentSCPAssociation) {
        let id = ObjectIdentifier(association)
        activeAssociations.removeValue(forKey: id)
    }
}

// MARK: - Commitment SCP Association

/// A thread-safe one-shot guard so a continuation backed by an `NWConnection`
/// state-update handler is resumed exactly once even if the handler fires for
/// several terminal transitions.
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isSet = false

    /// Returns `true` the first time it's called, `false` on every call after.
    func trySet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if isSet { return false }
        isSet = true
        return true
    }
}

/// Handles a single association for the Storage Commitment SCP
actor CommitmentSCPAssociation {
    private let connection: NWConnection
    private let configuration: StorageCommitmentSCPConfiguration
    private let delegate: any StorageCommitmentDelegate
    private let eventHandler: @Sendable (StorageCommitmentServerEvent) async -> Void
    private let transactionRegistrar: @Sendable (String) async -> Bool
    private let completionHandler: @Sendable (CommitmentSCPAssociation) async -> Void

    private var callingAETitle: String = ""
    private var calledAETitle: String = ""
    private var remoteHost: String = ""
    private var remotePort: UInt16 = 0
    private var maxPDUSize: UInt32 = defaultMaxPDUSize
    private var acceptedContexts: [UInt8: String] = [:] // Context ID -> Transfer Syntax
    /// Whether the requestor proposed and was granted the SCP role for the
    /// Storage Commitment Push Model SOP Class (same-association N-EVENT-REPORT)
    private var requestorIsSCPForCommitment = false
    private var messageAssembler = MessageAssembler()
    private var isReleasing = false
    private var currentMessageID: UInt16 = 1

    init(
        connection: NWConnection,
        configuration: StorageCommitmentSCPConfiguration,
        delegate: any StorageCommitmentDelegate,
        eventHandler: @escaping @Sendable (StorageCommitmentServerEvent) async -> Void,
        transactionRegistrar: @escaping @Sendable (String) async -> Bool = { _ in true },
        completionHandler: @escaping @Sendable (CommitmentSCPAssociation) async -> Void
    ) {
        self.connection = connection
        self.configuration = configuration
        self.delegate = delegate
        self.eventHandler = eventHandler
        self.transactionRegistrar = transactionRegistrar
        self.completionHandler = completionHandler
        
        // Extract remote address info
        if case .hostPort(let host, let port) = connection.endpoint {
            self.remoteHost = "\(host)"
            self.remotePort = port.rawValue
        }
    }
    
    func start() async {
        connection.start(queue: .global(qos: .userInitiated))

        // Wait for the accepted connection to be ready before any I/O; writes
        // issued earlier are not delivered. Guard the resume so a terminal
        // transition right after .ready cannot resume the continuation twice.
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
            connection.cancel()
            await completionHandler(self)
            return
        }

        do {
            try await handleAssociation()
        } catch {
            await eventHandler(.error(error))
        }

        connection.cancel()
        await completionHandler(self)
    }
    
    func abort() async {
        try? await sendAbort(reason: .unexpectedPDU)
        connection.cancel()
    }
    
    // MARK: - Association Handling
    
    private func handleAssociation() async throws {
        // Wait for and process A-ASSOCIATE-RQ
        let firstPDU = try await receivePDU()
        
        guard let associateRequest = firstPDU as? AssociateRequestPDU else {
            try await sendAbort(reason: .unexpectedPDU)
            throw DICOMNetworkError.decodingFailed("Expected A-ASSOCIATE-RQ, got \(type(of: firstPDU))")
        }
        
        // Extract association info
        callingAETitle = associateRequest.callingAETitle.value
        calledAETitle = associateRequest.calledAETitle.value
        
        // PS3.8 Table 9-11: only bit 0 of Protocol-version is tested; reject
        // with source 2 (ACSE), reason 2 (protocol-version-not-supported)
        guard associateRequest.isProtocolVersionSupported else {
            await eventHandler(.associationRejected(callingAE: callingAETitle, reason: "Protocol version not supported"))
            try await sendAssociateReject(
                result: .rejectedPermanent,
                source: .serviceProviderACSE,
                reason: 2 // Protocol version not supported
            )
            throw DICOMNetworkError.associationRejected(result: .rejectedPermanent, source: .serviceProviderACSE, reason: 2)
        }
        
        // Check calling AE is allowed
        guard configuration.isCallingAEAllowed(callingAETitle) else {
            await eventHandler(.associationRejected(callingAE: callingAETitle, reason: "Calling AE not allowed"))
            try await sendAssociateReject(
                result: .rejectedPermanent,
                source: .serviceUser,
                reason: 3 // Calling AE Title not recognized
            )
            throw DICOMNetworkError.associationRejected(result: .rejectedPermanent, source: .serviceUser, reason: 3)
        }
        
        // Check called AE matches our AE
        if calledAETitle != configuration.aeTitle.value {
            await eventHandler(.associationRejected(callingAE: callingAETitle, reason: "Called AE mismatch"))
            try await sendAssociateReject(
                result: .rejectedPermanent,
                source: .serviceUser,
                reason: 7 // Called AE Title not recognized
            )
            throw DICOMNetworkError.associationRejected(result: .rejectedPermanent, source: .serviceUser, reason: 7)
        }
        
        // Create association info for delegate
        let proposedSOPClasses = associateRequest.presentationContexts.map { $0.abstractSyntax }
        let proposedTransferSyntaxes = associateRequest.presentationContexts.flatMap { $0.transferSyntaxes }
        
        let associationInfo = AssociationInfo(
            callingAETitle: callingAETitle,
            calledAETitle: calledAETitle,
            remoteHost: remoteHost,
            remotePort: remotePort,
            proposedSOPClasses: proposedSOPClasses,
            proposedTransferSyntaxes: Array(Set(proposedTransferSyntaxes))
        )
        
        // Ask delegate if we should accept
        let shouldAccept = await delegate.shouldAcceptAssociation(from: associationInfo)
        guard shouldAccept else {
            await eventHandler(.associationRejected(callingAE: callingAETitle, reason: "Rejected by delegate"))
            try await sendAssociateReject(
                result: .rejectedPermanent,
                source: .serviceUser,
                reason: 1 // No reason given
            )
            throw DICOMNetworkError.associationRejected(result: .rejectedPermanent, source: .serviceUser, reason: 1)
        }
        
        // Negotiate presentation contexts
        let acceptedContextList = negotiatePresentationContexts(associateRequest.presentationContexts)
        
        // Check if at least one context was accepted
        guard !acceptedContextList.isEmpty else {
            await eventHandler(.associationRejected(callingAE: callingAETitle, reason: "No presentation contexts accepted"))
            // PS3.8 Table 9-21: "no presentation context acceptable" is not a
            // UL-provider condition, so reject as service-user, reason 1
            // (no-reason-given).
            try await sendAssociateReject(
                result: .rejectedPermanent,
                source: .serviceUser,
                reason: 1 // No reason given
            )
            throw DICOMNetworkError.noPresentationContextAccepted
        }
        
        // Store accepted contexts
        for context in acceptedContextList {
            acceptedContexts[context.id] = context.transferSyntax
        }
        
        // Set max PDU size from request (PS3.8 Annex D.1: 0 = unlimited)
        maxPDUSize = negotiatedMaxPDUSize(local: configuration.maxPDUSize, remote: associateRequest.maxPDUSize)
        
        // Answer the proposed SCP/SCU Role Selections (PS3.7 D.3.3.4.2): for the
        // commitment class we can act as SCP (N-ACTION) and as SCU (sending the
        // N-EVENT-REPORT to a requestor that takes the SCP role).
        let acceptedSOPClasses = Set(associateRequest.presentationContexts
            .filter { proposed in acceptedContextList.contains { $0.id == proposed.id } }
            .map { $0.abstractSyntax })
        let roleSelections = associateRequest.roleSelections.acceptorResponse(
            acceptSCURoleFor: { acceptedSOPClasses.contains($0) },
            acceptSCPRoleFor: { acceptedSOPClasses.contains($0) }
        )
        requestorIsSCPForCommitment = NegotiatedRoles.resolve(
            proposed: associateRequest.roleSelections,
            accepted: roleSelections,
            sopClassUID: storageCommitmentPushModelSOPClassUID
        ).requestorIsSCP

        // Build and send A-ASSOCIATE-AC
        let acceptPDU = try buildAssociateAccept(
            calledAE: calledAETitle,
            callingAE: callingAETitle,
            acceptedContexts: acceptedContextList,
            applicationContext: associateRequest.applicationContextName,
            roleSelections: roleSelections
        )
        
        try await send(pdu: acceptPDU)
        
        await eventHandler(.associationEstablished(associationInfo))
        
        // Process messages until release or abort
        try await processMessages()
        
        await eventHandler(.associationReleased(callingAE: callingAETitle))
    }
    
    private func negotiatePresentationContexts(_ proposed: [PresentationContext]) -> [AcceptedPresentationContext] {
        var accepted: [AcceptedPresentationContext] = []
        
        for context in proposed {
            // Check if this is the Storage Commitment SOP Class
            if context.abstractSyntax == storageCommitmentPushModelSOPClassUID {
                // Find a transfer syntax we support
                let supportedTS = [
                    explicitVRLittleEndianTransferSyntaxUID,
                    implicitVRLittleEndianTransferSyntaxUID
                ]
                
                for ts in context.transferSyntaxes {
                    if supportedTS.contains(ts) {
                        let acceptedContext = AcceptedPresentationContext(
                            id: context.id,
                            result: .acceptance,
                            transferSyntax: ts
                        )
                        accepted.append(acceptedContext)
                        break
                    }
                }
            }
        }
        
        return accepted
    }
    
    private func processMessages() async throws {
        while !isReleasing {
            let pdu = try await receivePDU()
            
            switch pdu {
            case let releasePDU as ReleaseRequestPDU:
                _ = releasePDU // Acknowledge we received it
                isReleasing = true
                let releaseResponse = ReleaseResponsePDU()
                try await send(pdu: releaseResponse)
                
            case let abortPDU as AbortPDU:
                _ = abortPDU // Acknowledge we received it
                throw DICOMNetworkError.associationAborted(source: .serviceUser, reason: abortPDU.reason)
                
            case let dataPDU as DataTransferPDU:
                try await handleDataTransfer(dataPDU)
                
            default:
                throw DICOMNetworkError.decodingFailed("Unexpected PDU type: \(type(of: pdu))")
            }
        }
    }
    
    private func handleDataTransfer(_ dataPDU: DataTransferPDU) async throws {
        // Add PDVs to the assembler
        for pdv in dataPDU.presentationDataValues {
            if let message = try messageAssembler.addPDV(pdv) {
                try await handleAssembledMessage(message)
            }
        }
    }
    
    private func handleAssembledMessage(_ message: AssembledMessage) async throws {
        // Get the command from the assembled message
        guard let commandType = message.command else {
            throw DICOMNetworkError.invalidPDU("Failed to parse command field")
        }
        
        switch commandType {
        case .nActionRequest:
            try await handleNAction(message)
        default:
            // Unsupported command
            throw DICOMNetworkError.decodingFailed("Unsupported command: \(commandType)")
        }
    }
    
    private func handleNAction(_ message: AssembledMessage) async throws {
        // Parse the N-ACTION request
        let commandSet = message.commandSet
        let request = NActionRequest(commandSet: commandSet, presentationContextID: message.presentationContextID)
        
        func fail(_ status: DIMSEStatus) async throws {
            let response = NActionResponse(
                messageIDBeingRespondedTo: request.messageID,
                affectedSOPClassUID: request.requestedSOPClassUID,
                affectedSOPInstanceUID: request.requestedSOPInstanceUID,
                actionTypeID: request.actionTypeID,
                status: status,
                presentationContextID: message.presentationContextID
            )
            try await sendDIMSEResponse(response)
        }
        
        // Validate it's a Storage Commitment request
        // PS3.7 §10.1.4.1.10: No such SOP Class (0118H)
        guard request.requestedSOPClassUID == storageCommitmentPushModelSOPClassUID else {
            try await fail(.failedNoSuchSOPClass)
            return
        }
        
        // The Push Model has exactly one well-known SOP Instance (PS3.4 J.3.5)
        guard request.requestedSOPInstanceUID == storageCommitmentPushModelSOPInstanceUID else {
            try await fail(.failedNoSuchSOPInstance)
            return
        }
        
        // PS3.7 §10.1.4.1.10: No such Action (0123H) - "the Action Type
        // specified was not supported"
        guard request.actionTypeID == storageCommitmentRequestActionTypeID else {
            try await fail(DIMSEStatus.from(0x0123))
            return
        }
        
        // Parse the data set to extract Transaction UID and Referenced SOP Sequence,
        // in the transfer syntax negotiated for this presentation context
        guard let dataSetData = message.dataSet else {
            try await fail(.failedUnableToProcess)
            return
        }
        
        let transferSyntaxUID = acceptedContexts[message.presentationContextID]
            ?? explicitVRLittleEndianTransferSyntaxUID
        let explicit = StorageCommitmentDataSetCodec.isExplicitVR(transferSyntaxUID: transferSyntaxUID)
        
        // Extract transaction UID and references
        guard let transactionUID = StorageCommitmentDataSetCodec.extractUIValue(
            from: dataSetData, tag: Tag(group: 0x0008, element: 0x1195), explicit: explicit) else {
            try await fail(.failedUnableToProcess)
            return
        }
        
        // A Transaction UID must be unique per request (PS3.4 J.3.1)
        guard await transactionRegistrar(transactionUID) else {
            await eventHandler(.error(DICOMNetworkError.decodingFailed(
                "Duplicate Storage Commitment Transaction UID \(transactionUID) from \(callingAETitle)")))
            try await fail(.failedUnableToProcess)
            return
        }
        
        let references = extractSOPReferences(from: dataSetData, explicit: explicit)
        
        // Create commitment request info
        let requestInfo = CommitmentRequestInfo(
            transactionUID: transactionUID,
            references: references,
            callingAETitle: callingAETitle
        )
        
        await eventHandler(.commitmentRequestReceived(requestInfo))
        
        // Send N-ACTION response (acknowledgment that request was received)
        let actionResponse = NActionResponse(
            messageIDBeingRespondedTo: request.messageID,
            affectedSOPClassUID: request.requestedSOPClassUID,
            affectedSOPInstanceUID: request.requestedSOPInstanceUID,
            actionTypeID: request.actionTypeID,
            status: .success,
            presentationContextID: message.presentationContextID
        )
        try await sendDIMSEResponse(actionResponse)
        
        // Process the commitment request via delegate
        let result: CommitmentResult
        do {
            result = try await delegate.processCommitmentRequest(requestInfo)
        } catch {
            await eventHandler(.error(error))
            return
        }
        
        if requestorIsSCPForCommitment {
            // The requestor proposed and was granted the SCP role for the
            // commitment class: deliver the N-EVENT-REPORT on this association
            // (PS3.4 J.3.3).
            do {
                try await sendCommitmentResult(
                    result,
                    presentationContextID: message.presentationContextID,
                    transferSyntaxUID: transferSyntaxUID
                )
                await eventHandler(.commitmentResultSent(transactionUID: transactionUID, success: result.isSuccess))
            } catch {
                await eventHandler(.error(error))
            }
        } else {
            // Default roles: the requestor cannot receive N-EVENT-REPORT here.
            // Deliver it on a new association to the requestor's AE while this
            // association completes normally (A-RELEASE-RQ -> A-RELEASE-RP).
            guard let destination = configuration.eventReportDestination?(callingAETitle) else {
                await eventHandler(.error(DICOMNetworkError.connectionFailed(
                    "No N-EVENT-REPORT destination known for AE \(callingAETitle); commitment result for \(transactionUID) dropped")))
                return
            }
            
            let calledAETitle = callingAETitle
            let eventHandler = self.eventHandler
            let configuration = self.configuration
            Task.detached {
                do {
                    try await CommitmentSCPAssociation.sendCommitmentResultOnReverseAssociation(
                        result,
                        to: calledAETitle,
                        host: destination.host,
                        port: destination.port,
                        configuration: configuration
                    )
                    await eventHandler(.commitmentResultSent(transactionUID: transactionUID, success: result.isSuccess))
                } catch {
                    await eventHandler(.error(error))
                }
            }
        }
    }
    
    /// Sends the N-EVENT-REPORT on the association the N-ACTION arrived on and
    /// waits for the N-EVENT-REPORT-RSP.
    ///
    /// The requestor may release the association at any point after the
    /// N-ACTION-RSP; an A-RELEASE-RQ received here is answered with A-RELEASE-RP
    /// and ends the association instead of being treated as an error.
    private func sendCommitmentResult(
        _ result: CommitmentResult,
        presentationContextID: UInt8,
        transferSyntaxUID: String
    ) async throws {
        // Determine event type based on result
        let eventTypeID: UInt16 = result.failedReferences.isEmpty ?
            storageCommitmentSuccessEventTypeID : storageCommitmentFailureEventTypeID
        
        // Build the N-EVENT-REPORT data set in the negotiated transfer syntax
        let dataSetData = StorageCommitmentService.buildCommitmentResultDataSet(
            result, transferSyntaxUID: transferSyntaxUID)
        
        // Create N-EVENT-REPORT request
        let eventReport = NEventReportRequest(
            messageID: currentMessageID,
            affectedSOPClassUID: storageCommitmentPushModelSOPClassUID,
            affectedSOPInstanceUID: storageCommitmentPushModelSOPInstanceUID,
            eventTypeID: eventTypeID,
            hasDataSet: true,
            presentationContextID: presentationContextID
        )
        currentMessageID += 1
        
        // Send the event report with data set
        try await sendDIMSERequest(eventReport, dataSetData: dataSetData)
        
        // Wait for the N-EVENT-REPORT-RSP, tolerating a release in the meantime
        while true {
            let pdu = try await receivePDU()
            
            switch pdu {
            case let dataPDU as DataTransferPDU:
                for pdv in dataPDU.presentationDataValues {
                    guard let message = try messageAssembler.addPDV(pdv) else { continue }
                    guard message.command == .nEventReportResponse else {
                        throw DICOMNetworkError.decodingFailed(
                            "Expected N-EVENT-REPORT-RSP, got \(message.command?.description ?? "unknown")")
                    }
                    let response = NEventReportResponse(
                        commandSet: message.commandSet,
                        presentationContextID: message.presentationContextID)
                    if !response.status.isSuccess {
                        throw DICOMNetworkError.storeFailed(response.status)
                    }
                    return
                }
                
            case _ as ReleaseRequestPDU:
                // The requestor released without answering: complete the release
                isReleasing = true
                try await send(pdu: ReleaseResponsePDU())
                throw DICOMNetworkError.connectionClosed
                
            case let abortPDU as AbortPDU:
                isReleasing = true
                throw DICOMNetworkError.associationAborted(source: .serviceUser, reason: abortPDU.reason)
                
            default:
                throw DICOMNetworkError.decodingFailed("Unexpected PDU type: \(type(of: pdu))")
            }
        }
    }
    
    /// Delivers a commitment result by opening a new association to the
    /// requestor's AE (the "reverse" association of PS3.4 J.3.3).
    ///
    /// The Storage Commitment Push Model SOP Class is proposed with role
    /// selection scuRole=false / scpRole=true, since this side acts as SCP
    /// sending the N-EVENT-REPORT; the peer must grant the SCP role.
    static func sendCommitmentResultOnReverseAssociation(
        _ result: CommitmentResult,
        to calledAETitle: String,
        host: String,
        port: UInt16,
        configuration: StorageCommitmentSCPConfiguration
    ) async throws {
        let associationConfig = AssociationConfiguration(
            callingAETitle: configuration.aeTitle,
            calledAETitle: try AETitle(calledAETitle),
            host: host,
            port: port,
            maxPDUSize: configuration.maxPDUSize,
            implementationClassUID: configuration.implementationClassUID,
            implementationVersionName: configuration.implementationVersionName,
            timeout: configuration.reverseAssociationTimeout
        )
        let association = Association(configuration: associationConfig)
        
        let presentationContext = try PresentationContext(
            id: 1,
            abstractSyntax: storageCommitmentPushModelSOPClassUID,
            transferSyntaxes: [
                explicitVRLittleEndianTransferSyntaxUID,
                implicitVRLittleEndianTransferSyntaxUID
            ]
        )
        
        do {
            let negotiated = try await association.request(
                presentationContexts: [presentationContext],
                roleSelections: [.scpOnly(storageCommitmentPushModelSOPClassUID)]
            )
            
            guard negotiated.isContextAccepted(1) else {
                try await association.abort()
                throw DICOMNetworkError.sopClassNotSupported(storageCommitmentPushModelSOPClassUID)
            }
            
            // An explicit refusal of the SCP role means the peer will not accept
            // N-EVENT-REPORT; a missing answer is tolerated for lenient peers.
            if let answer = negotiated.acceptPDU.roleSelection(for: storageCommitmentPushModelSOPClassUID),
               !answer.scpRole {
                try await association.abort()
                throw DICOMNetworkError.decodingFailed(
                    "Peer \(calledAETitle) refused the SCP role for Storage Commitment N-EVENT-REPORT")
            }
            
            let transferSyntaxUID = negotiated.acceptedTransferSyntax(forContextID: 1)
                ?? explicitVRLittleEndianTransferSyntaxUID
            let eventTypeID: UInt16 = result.failedReferences.isEmpty ?
                storageCommitmentSuccessEventTypeID : storageCommitmentFailureEventTypeID
            let dataSetData = StorageCommitmentService.buildCommitmentResultDataSet(
                result, transferSyntaxUID: transferSyntaxUID)
            
            let eventReport = NEventReportRequest(
                messageID: 1,
                affectedSOPClassUID: storageCommitmentPushModelSOPClassUID,
                affectedSOPInstanceUID: storageCommitmentPushModelSOPInstanceUID,
                eventTypeID: eventTypeID,
                hasDataSet: true,
                presentationContextID: 1
            )
            
            let fragmenter = MessageFragmenter(maxPDUSize: negotiated.maxPDUSize)
            let pdus = fragmenter.fragmentMessage(
                commandSet: eventReport.commandSet,
                dataSet: dataSetData,
                presentationContextID: 1
            )
            for pdu in pdus {
                for pdv in pdu.presentationDataValues {
                    try await association.send(pdv: pdv)
                }
            }
            
            // Wait for N-EVENT-REPORT-RSP
            let assembler = MessageAssembler()
            responseLoop: while true {
                let responsePDU = try await association.receive()
                guard let message = try assembler.addPDVs(from: responsePDU) else { continue }
                guard message.command == .nEventReportResponse else {
                    throw DICOMNetworkError.decodingFailed(
                        "Expected N-EVENT-REPORT-RSP, got \(message.command?.description ?? "unknown")")
                }
                let response = NEventReportResponse(commandSet: message.commandSet, presentationContextID: 1)
                guard response.status.isSuccess else {
                    throw DICOMNetworkError.storeFailed(response.status)
                }
                break responseLoop
            }
            
            try await association.release()
        } catch {
            try? await association.abort()
            throw error
        }
    }
    
    // MARK: - Helper Methods for Data Extraction
    
    private func extractSOPReferences(from data: Data, explicit: Bool) -> [SOPReference] {
        typealias Codec = StorageCommitmentDataSetCodec
        var references: [SOPReference] = []
        
        // Find Referenced SOP Sequence (0008,1199)
        guard let sequenceItems = Codec.extractSequenceItems(
            from: data, tag: Tag(group: 0x0008, element: 0x1199), explicit: explicit) else {
            return references
        }
        
        for itemData in sequenceItems {
            guard let sopClassUID = Codec.extractUIValue(from: itemData, tag: Tag(group: 0x0008, element: 0x1150), explicit: explicit),
                  let sopInstanceUID = Codec.extractUIValue(from: itemData, tag: Tag(group: 0x0008, element: 0x1155), explicit: explicit) else {
                continue
            }
            
            references.append(SOPReference(sopClassUID: sopClassUID, sopInstanceUID: sopInstanceUID))
        }
        
        return references
    }
    
    // MARK: - PDU Communication
    
    private func sendDIMSEResponse(_ response: DIMSEResponse) async throws {
        let commandData = response.commandSet.encode()
        let pdv = PresentationDataValue(
            presentationContextID: response.presentationContextID,
            isCommand: true,
            isLastFragment: true,
            data: commandData
        )
        
        let dataPDU = DataTransferPDU(presentationDataValues: [pdv])
        try await send(pdu: dataPDU)
    }
    
    private func sendDIMSERequest(_ request: DIMSERequest, dataSetData: Data?) async throws {
        // Fragment by the negotiated maximum PDU size
        let fragmenter = MessageFragmenter(maxPDUSize: maxPDUSize)
        let pdus = fragmenter.fragmentMessage(
            commandSet: request.commandSet,
            dataSet: dataSetData,
            presentationContextID: request.presentationContextID
        )
        for pdu in pdus {
            try await send(pdu: pdu)
        }
    }
    
    private func sendAssociateReject(result: AssociateRejectResult, source: AssociateRejectSource, reason: UInt8) async throws {
        let rejectPDU = AssociateRejectPDU(result: result, source: source, reason: reason)
        try await send(pdu: rejectPDU)
    }
    
    private func sendAbort(reason: AbortReason) async throws {
        let abortPDU = AbortPDU(source: .serviceProvider, reason: reason)
        try await send(pdu: abortPDU)
    }
    
    private func send(pdu: any PDU) async throws {
        let data = try pdu.encode()
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: DICOMNetworkError.connectionFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }
    
    private func receivePDU() async throws -> any PDU {
        // First read the 6-byte PDU header
        let headerData = try await receive(length: 6)
        
        guard headerData.count == 6 else {
            throw DICOMNetworkError.connectionClosed
        }
        
        // PDU-length is a big-endian unsigned 32-bit number (PS3.8 §9.3.1, Table 9-11
        // bytes 3-6). This used to be read little-endian, so a 259-byte A-ASSOCIATE-RQ
        // was taken for a 50 MB PDU and the read only returned when the peer gave up
        // (the two "ARTIM" failures of D13 in the DICOMCore report).
        let (pduType, declaredLength) = try PDUDecoder.readHeader(from: headerData)
        // PS3.8 Annex D.1: the negotiated limit applies to P-DATA-TF only
        try checkPDULength(type: pduType, length: declaredLength, maxPDUSize: configuration.maxPDUSize)
        let pduLength = Int(declaredLength)
        
        // Read the PDU body
        var fullData = headerData
        if pduLength > 0 {
            let bodyData = try await receive(length: pduLength)
            fullData.append(bodyData)
        }
        
        // Decode the PDU
        return try PDUDecoder.decode(from: fullData)
    }
    
    private func receive(length: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: length, maximumLength: length) { content, _, isComplete, error in
                if let error = error {
                    continuation.resume(throwing: DICOMNetworkError.connectionFailed(error.localizedDescription))
                } else if let data = content {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: DICOMNetworkError.connectionClosed)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }
    
    private func buildAssociateAccept(
        calledAE: String,
        callingAE: String,
        acceptedContexts: [AcceptedPresentationContext],
        applicationContext: String,
        roleSelections: [SCPSCURoleSelection] = []
    ) throws -> AssociateAcceptPDU {
        return AssociateAcceptPDU(
            calledAETitle: try AETitle(calledAE),
            callingAETitle: try AETitle(callingAE),
            applicationContextName: applicationContext,
            presentationContexts: acceptedContexts,
            maxPDUSize: maxPDUSize,
            implementationClassUID: configuration.implementationClassUID,
            implementationVersionName: configuration.implementationVersionName,
            roleSelections: roleSelections
        )
    }
}

#endif
