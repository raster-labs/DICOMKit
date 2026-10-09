import Foundation

/// Default DICOM port number
public let dicomDefaultPort: UInt16 = 104

/// Alternative DICOM port (commonly used in testing)
public let dicomAlternativePort: UInt16 = 11112

/// Configuration for a DICOM Association
///
/// Contains all the parameters needed to establish and maintain a DICOM association.
public struct AssociationConfiguration: Sendable, Hashable {
    /// The local Application Entity title (calling AE)
    public let callingAETitle: AETitle
    
    /// The remote Application Entity title (called AE)
    public let calledAETitle: AETitle
    
    /// The remote host address
    public let host: String
    
    /// The remote port number
    public let port: UInt16
    
    /// Maximum PDU size to propose
    public let maxPDUSize: UInt32
    
    /// Implementation Class UID
    public let implementationClassUID: String
    
    /// Implementation Version Name (optional)
    public let implementationVersionName: String?
    
    /// Connection timeout in seconds
    public let timeout: TimeInterval
    
    /// ARTIM (Association Request/Release Timer) timeout in seconds
    ///
    /// This timer is started when an A-ASSOCIATE-RQ or A-RELEASE-RQ is sent
    /// and should be stopped when the response is received. If the timer expires,
    /// the association is aborted.
    ///
    /// Reference: PS3.8 Section 9.1.5 - ARTIM Timer
    ///
    /// Set to `nil` to disable the ARTIM timer (not recommended for production).
    /// Default is 30 seconds.
    public let artimTimeout: TimeInterval?
    
    /// Whether TLS is enabled.
    ///
    /// This stored compatibility value remains available on platforms where
    /// Network.framework (and therefore `TLSConfiguration`) is unavailable.
    public let tlsEnabled: Bool
    
    #if canImport(Network)
    /// The complete TLS policy for the transport, or `nil` for plain TCP.
    ///
    /// Keeping the policy here is security-critical: reducing it to a Boolean would
    /// discard certificate pinning, private trust roots, protocol-version limits,
    /// and client identity settings before the connection is created.
    public let tlsConfiguration: TLSConfiguration?
    #endif

    /// User identity for authentication (optional)
    ///
    /// When set, user identity information will be included in the A-ASSOCIATE-RQ PDU
    /// for authentication with the remote SCP.
    ///
    /// Reference: PS3.7 Section D.3.3.7 - User Identity Negotiation
    public let userIdentity: UserIdentity?
    
    /// Creates association configuration
    ///
    /// - Parameters:
    ///   - callingAETitle: Local AE title
    ///   - calledAETitle: Remote AE title
    ///   - host: Remote host address
    ///   - port: Remote port (default: 104)
    ///   - maxPDUSize: Maximum PDU size (default: 64 KB (`defaultMaxPDUSize`))
    ///   - implementationClassUID: Implementation Class UID
    ///   - implementationVersionName: Implementation Version Name
    ///   - timeout: Connection timeout (default: 30 seconds)
    ///   - artimTimeout: ARTIM timer timeout in seconds (default: 30 seconds, nil to disable)
    ///   - tlsEnabled: Use TLS (default: false)
    ///   - userIdentity: User identity for authentication (optional)
    public init(
        callingAETitle: AETitle,
        calledAETitle: AETitle,
        host: String,
        port: UInt16 = dicomDefaultPort,
        maxPDUSize: UInt32 = defaultMaxPDUSize,
        implementationClassUID: String,
        implementationVersionName: String? = nil,
        timeout: TimeInterval = 30,
        artimTimeout: TimeInterval? = 30,
        tlsEnabled: Bool = false,
        userIdentity: UserIdentity? = nil
    ) {
        self.callingAETitle = callingAETitle
        self.calledAETitle = calledAETitle
        self.host = host
        self.port = port
        self.maxPDUSize = maxPDUSize
        self.implementationClassUID = implementationClassUID
        self.implementationVersionName = implementationVersionName
        self.timeout = timeout
        self.artimTimeout = artimTimeout
        self.tlsEnabled = tlsEnabled
        #if canImport(Network)
        self.tlsConfiguration = tlsEnabled ? .default : nil
        #endif
        self.userIdentity = userIdentity
    }

    #if canImport(Network)
    /// Creates association configuration with an exact TLS policy.
    ///
    /// - Parameters:
    ///   - callingAETitle: Local AE title
    ///   - calledAETitle: Remote AE title
    ///   - host: Remote host address
    ///   - port: Remote port (default: 104)
    ///   - maxPDUSize: Maximum PDU size (default: 64 KB (`defaultMaxPDUSize`))
    ///   - implementationClassUID: Implementation Class UID
    ///   - implementationVersionName: Implementation Version Name
    ///   - timeout: Connection timeout (default: 30 seconds)
    ///   - artimTimeout: ARTIM timer timeout in seconds (default: 30 seconds, nil to disable)
    ///   - tlsConfiguration: Complete TLS policy, or `nil` for plain TCP
    ///   - userIdentity: User identity for association negotiation (optional)
    public init(
        callingAETitle: AETitle,
        calledAETitle: AETitle,
        host: String,
        port: UInt16 = dicomDefaultPort,
        maxPDUSize: UInt32 = defaultMaxPDUSize,
        implementationClassUID: String,
        implementationVersionName: String? = nil,
        timeout: TimeInterval = 30,
        artimTimeout: TimeInterval? = 30,
        tlsConfiguration: TLSConfiguration?,
        userIdentity: UserIdentity? = nil
    ) {
        self.callingAETitle = callingAETitle
        self.calledAETitle = calledAETitle
        self.host = host
        self.port = port
        self.maxPDUSize = maxPDUSize
        self.implementationClassUID = implementationClassUID
        self.implementationVersionName = implementationVersionName
        self.timeout = timeout
        self.artimTimeout = artimTimeout
        self.tlsConfiguration = tlsConfiguration
        self.tlsEnabled = tlsConfiguration != nil
        self.userIdentity = userIdentity
    }
    #endif
}

/// Negotiated association parameters after successful association establishment
public struct NegotiatedAssociation: Sendable {
    /// The accepted presentation contexts
    public let acceptedPresentationContexts: [AcceptedPresentationContext]
    
    /// The negotiated maximum PDU size (minimum of local and remote; a peer
    /// value of 0 means unlimited, PS3.8 Annex D.1, and the local value is used)
    public let maxPDUSize: UInt32
    
    /// Remote implementation class UID
    public let remoteImplementationClassUID: String
    
    /// Remote implementation version name
    public let remoteImplementationVersionName: String?
    
    /// User identity server response (if user identity was requested and accepted)
    ///
    /// Reference: PS3.7 Section D.3.3.7.2 - Server Response
    public let userIdentityServerResponse: UserIdentityServerResponse?
    
    /// The raw A-ASSOCIATE-AC PDU
    public let acceptPDU: AssociateAcceptPDU
    
    /// Role selections proposed in the A-ASSOCIATE-RQ
    public let proposedRoleSelections: [SCPSCURoleSelection]
    
    /// Creates negotiated association info
    init(acceptPDU: AssociateAcceptPDU, localMaxPDUSize: UInt32,
         proposedRoleSelections: [SCPSCURoleSelection] = []) {
        self.acceptPDU = acceptPDU
        self.proposedRoleSelections = proposedRoleSelections
        self.acceptedPresentationContexts = acceptPDU.presentationContexts
        // PS3.8 Annex D.1: 0 from the peer means "no maximum length is specified"
        self.maxPDUSize = negotiatedMaxPDUSize(local: localMaxPDUSize, remote: acceptPDU.maxPDUSize)
        self.remoteImplementationClassUID = acceptPDU.implementationClassUID
        self.remoteImplementationVersionName = acceptPDU.implementationVersionName
        self.userIdentityServerResponse = acceptPDU.userIdentityServerResponse
    }
    
    /// Gets the accepted transfer syntax for a presentation context ID
    ///
    /// - Parameter contextID: The presentation context ID
    /// - Returns: The accepted transfer syntax, or nil if not accepted
    public func acceptedTransferSyntax(forContextID contextID: UInt8) -> String? {
        acceptedPresentationContexts.first {
            $0.id == contextID && $0.isAccepted
        }?.transferSyntax
    }
    
    /// Whether a specific presentation context was accepted
    ///
    /// - Parameter contextID: The presentation context ID
    /// - Returns: True if the context was accepted
    public func isContextAccepted(_ contextID: UInt8) -> Bool {
        acceptedPresentationContexts.contains { $0.id == contextID && $0.isAccepted }
    }
    
    /// The roles in effect for a SOP Class after SCP/SCU Role Selection
    /// Negotiation (PS3.7 D.3.3.4). Without a negotiated answer the default
    /// roles apply: this side is SCU only.
    public func negotiatedRoles(for sopClassUID: String) -> NegotiatedRoles {
        NegotiatedRoles.resolve(
            proposed: proposedRoleSelections,
            accepted: acceptPDU.roleSelections,
            sopClassUID: sopClassUID
        )
    }
    
    /// Whether this side (the requestor) was granted the SCP role for a SOP Class
    public func isSCPRoleAccepted(for sopClassUID: String) -> Bool {
        negotiatedRoles(for: sopClassUID).requestorIsSCP
    }

    /// The acceptor's SOP Class Extended Negotiation answer for a SOP Class
    /// (PS3.7 D.3.3.5), or nil when it returned none (Service Class default).
    public func acceptedExtendedNegotiation(for sopClassUID: String) -> SOPClassExtendedNegotiation? {
        acceptPDU.extendedNegotiation(for: sopClassUID)
    }
}

#if canImport(Network)
import Network
// NEMA-verified: 2026a, checked 2026-09-28 — release, abort and ARTIM behaviour compared with PS3.8 2026a Table 9-10 (AR-2/AR-4 on A-RELEASE-RQ, AR-8/AR-9/AR-3 on collision, AA-1 on local timeout) and §7.2.2; maximum length per Annex D.1 (0 = unlimited); 2026-10-01: request(…extendedNegotiations:) proposes PS3.7 D.3.3.5 sub-items

/// DICOM Association for Service Class User (SCU) operations
///
/// Manages the lifecycle of a DICOM association including establishment,
/// data transfer, and release.
///
/// Reference: PS3.8 Section 7 - DICOM Upper Layer Service
///
/// ## Usage
///
/// ```swift
/// let config = AssociationConfiguration(
///     callingAETitle: try AETitle("MY_SCU"),
///     calledAETitle: try AETitle("PACS"),
///     host: "pacs.hospital.com",
///     port: 11112,
///     implementationClassUID: "1.2.3.4.5.6.7.8.9"
/// )
///
/// let association = Association(configuration: config)
///
/// // Request presentation contexts
/// let context = try PresentationContext(
///     id: 1,
///     abstractSyntax: "1.2.840.10008.5.1.4.1.1.7",
///     transferSyntaxes: ["1.2.840.10008.1.2.1"]
/// )
///
/// // Establish association
/// let negotiated = try await association.request(presentationContexts: [context])
///
/// // Send data
/// let pdv = PresentationDataValue(
///     presentationContextID: 1,
///     isCommand: true,
///     isLastFragment: true,
///     data: commandData
/// )
/// try await association.send(pdv: pdv)
///
/// // Receive response
/// let response = try await association.receive()
///
/// // Release association
/// try await association.release()
/// ```
public final class Association: @unchecked Sendable {
    
    /// The association configuration
    public let configuration: AssociationConfiguration
    
    /// The current association state
    public var state: AssociationState {
        stateMachine.state
    }
    
    /// The negotiated association parameters (available after successful establishment)
    public private(set) var negotiated: NegotiatedAssociation?
    
    /// The underlying TCP connection
    private var connection: DICOMConnection?
    
    /// The association state machine
    private let stateMachine = AssociationStateMachine()
    
    /// Transport construction seam. Public callers always receive the production
    /// Network.framework transport; tests can inject a controllable connection.
    private let connectionFactory: @Sendable (AssociationConfiguration) throws -> DICOMConnection

    /// Lock for thread-safe operations
    private let lock = NSLock()
    
    /// Creates a new association
    ///
    /// - Parameter configuration: The association configuration
    public init(configuration: AssociationConfiguration) {
        self.configuration = configuration
        self.connectionFactory = { configuration in
            try DICOMConnection(
                host: configuration.host,
                port: configuration.port,
                maxPDUSize: configuration.maxPDUSize,
                timeout: configuration.timeout,
                tlsConfiguration: configuration.tlsConfiguration
            )
        }
    }

    /// Internal test seam for deterministic connection lifecycle tests.
    init(
        configuration: AssociationConfiguration,
        connectionFactory: @escaping @Sendable (AssociationConfiguration) throws -> DICOMConnection
    ) {
        self.configuration = configuration
        self.connectionFactory = connectionFactory
    }

    /// Creates the transport used by `request(presentationContexts:)`.
    ///
    /// Kept internal so regression tests can inspect the exact transport policy
    /// without opening a socket.
    func makeConnection() throws -> DICOMConnection {
        try connectionFactory(configuration)
    }
    
    /// Requests an association with the remote peer
    ///
    /// - Parameter presentationContexts: The presentation contexts to propose
    /// - Returns: The negotiated association parameters
    /// - Throws: `DICOMNetworkError.connectionFailed` if connection fails
    /// - Throws: `DICOMNetworkError.associationRejected` if association is rejected
    /// - Throws: `DICOMNetworkError.artimTimerExpired` if ARTIM timer expires
    ///   - roleSelections: SCP/SCU Role Selections to propose (PS3.7 D.3.3.4).
    ///     Required when this side must receive requests on the association,
    ///     e.g. C-STORE sub-operations of a C-GET.
    ///   - extendedNegotiations: SOP Class Extended Negotiation sub-items to
    ///     propose (PS3.7 D.3.3.5), e.g. relational-retrieval for a Query/Retrieve
    ///     SOP Class (PS3.4 C.5.2.1). The acceptor's answers are in
    ///     `NegotiatedAssociation.acceptPDU.extendedNegotiations`.
    public func request(
        presentationContexts: [PresentationContext],
        roleSelections: [SCPSCURoleSelection] = []
    ) async throws -> NegotiatedAssociation {
        try await request(presentationContexts: presentationContexts,
                          roleSelections: roleSelections,
                          extendedNegotiations: [])
    }

    /// Requests an association proposing SOP Class Extended Negotiation
    /// sub-items as well (PS3.7 D.3.3.5; added 2026-10-01). See
    /// ``request(presentationContexts:roleSelections:)``.
    public func request(
        presentationContexts: [PresentationContext],
        roleSelections: [SCPSCURoleSelection] = [],
        extendedNegotiations: [SOPClassExtendedNegotiation]
    ) async throws -> NegotiatedAssociation {
        // Ensure we're in idle state
        guard state == .idle else {
            throw DICOMNetworkError.invalidState(
                "Cannot request association: current state is \(state)")
        }
        
        // Create and establish TCP connection
        let conn = try makeConnection()
        connection = conn

        try await conn.connect()

        // A-ASSOCIATE-RQ can contain a username, passcode, JWT, SAML assertion,
        // or Kerberos ticket. Never construct or submit it after cancellation.
        if Task.isCancelled {
            conn.abort()
            _ = stateMachine.handleEvent(.transportConnectionClosed)
            throw CancellationError()
        }
        _ = stateMachine.handleEvent(.transportConnected)
        
        // Build and send A-ASSOCIATE-RQ
        let associateRequest = AssociateRequestPDU(
            calledAETitle: configuration.calledAETitle,
            callingAETitle: configuration.callingAETitle,
            presentationContexts: presentationContexts,
            maxPDUSize: configuration.maxPDUSize,
            implementationClassUID: configuration.implementationClassUID,
            implementationVersionName: configuration.implementationVersionName,
            userIdentity: configuration.userIdentity,
            roleSelections: roleSelections,
            extendedNegotiations: extendedNegotiations
        )
        
        if Task.isCancelled {
            conn.abort()
            _ = stateMachine.handleEvent(.transportConnectionClosed)
            throw CancellationError()
        }

        do {
            try await conn.send(pdu: associateRequest)
        } catch is CancellationError {
            conn.abort()
            _ = stateMachine.handleEvent(.transportConnectionClosed)
            throw CancellationError()
        }
        _ = stateMachine.handleEvent(.associateRequestSent)
        
        // Wait for response with ARTIM timer
        let responsePDU: any PDU
        do {
            responsePDU = try await receiveWithARTIMTimer(conn: conn)
        } catch let error as DICOMNetworkError where error.isARTIMExpired {
            try await abortOnARTIMExpiry(conn: conn)
            throw error
        }
        
        switch responsePDU {
        case let acceptPDU as AssociateAcceptPDU:
            _ = stateMachine.handleEvent(.associateAcceptReceived(acceptPDU))
            
            // Check if any presentation context was accepted
            guard acceptPDU.acceptedContextIDs.count > 0 else {
                try await performAbort(reason: .notSpecified)
                throw DICOMNetworkError.noPresentationContextAccepted
            }
            
            let negotiatedAssoc = NegotiatedAssociation(
                acceptPDU: acceptPDU,
                localMaxPDUSize: configuration.maxPDUSize,
                proposedRoleSelections: roleSelections
            )
            self.negotiated = negotiatedAssoc
            return negotiatedAssoc

        case let rejectPDU as AssociateRejectPDU:
            _ = stateMachine.handleEvent(.associateRejectReceived(rejectPDU))
            await conn.disconnect()
            throw DICOMNetworkError.associationRejected(
                result: rejectPDU.result,
                source: rejectPDU.source,
                reason: rejectPDU.reason
            )

        case let abortPDU as AbortPDU:
            _ = stateMachine.handleEvent(.abortReceived(abortPDU))
            await conn.disconnect()
            throw DICOMNetworkError.associationAborted(
                source: abortPDU.source,
                reason: abortPDU.reason
            )

        default:
            try await performAbort(reason: .unexpectedPDU)
            throw DICOMNetworkError.unexpectedPDUType(
                expected: .associateAccept,
                received: responsePDU.pduType
            )
        }
    }
    
    /// Sends a Presentation Data Value (PDV) to the remote peer
    ///
    /// - Parameter pdv: The PDV to send
    /// - Throws: `DICOMNetworkError.invalidState` if not in established state
    public func send(pdv: PresentationDataValue) async throws {
        guard state == .established else {
            throw DICOMNetworkError.invalidState("Cannot send data: association not established")
        }
        
        guard let conn = connection else {
            throw DICOMNetworkError.connectionClosed
        }
        
        // Verify the presentation context is accepted
        guard negotiated?.isContextAccepted(pdv.presentationContextID) == true else {
            throw DICOMNetworkError.noPresentationContextAccepted
        }
        
        let dataPDU = DataTransferPDU(pdv: pdv)
        try await conn.send(pdu: dataPDU)
        _ = stateMachine.handleEvent(.dataTransferSent)
    }
    
    /// Sends multiple PDVs in a single P-DATA-TF PDU
    ///
    /// - Parameter pdvs: The PDVs to send
    /// - Throws: `DICOMNetworkError.invalidState` if not in established state
    public func send(pdvs: [PresentationDataValue]) async throws {
        guard state == .established else {
            throw DICOMNetworkError.invalidState("Cannot send data: association not established")
        }
        
        guard let conn = connection else {
            throw DICOMNetworkError.connectionClosed
        }
        
        let dataPDU = DataTransferPDU(presentationDataValues: pdvs)
        try await conn.send(pdu: dataPDU)
        _ = stateMachine.handleEvent(.dataTransferSent)
    }
    
    /// Receives data from the remote peer
    ///
    /// - Returns: The received P-DATA-TF PDU
    /// - Throws: `DICOMNetworkError.invalidState` if not in established state
    /// - Throws: `DICOMNetworkError.associationAborted` if abort is received
    /// - Throws: `DICOMNetworkError.connectionClosed` if release is received
    public func receive() async throws -> DataTransferPDU {
        guard state == .established else {
            throw DICOMNetworkError.invalidState("Cannot receive data: association not established")
        }
        
        guard let conn = connection else {
            throw DICOMNetworkError.connectionClosed
        }
        
        let pdu = try await conn.receivePDU()
        
        switch pdu {
        case let dataPDU as DataTransferPDU:
            _ = stateMachine.handleEvent(.dataTransferReceived(dataPDU))
            return dataPDU

        case _ as ReleaseRequestPDU:
            // PS3.8 Table 9-10: Sta6 + A-RELEASE-RQ PDU → AR-2 (issue A-RELEASE
            // indication) → Sta8. There is no application-level consumer for the
            // indication here, so the local A-RELEASE response is issued at once:
            // AR-4 (send A-RELEASE-RP, start ARTIM) → Sta13, then the transport
            // is closed: AR-5 → Sta1.
            _ = stateMachine.handleEvent(.releaseRequestReceived)
            try? await conn.send(pdu: ReleaseResponsePDU())
            _ = stateMachine.handleEvent(.releaseResponseSent)
            await conn.disconnect()
            _ = stateMachine.handleEvent(.transportConnectionClosed)
            throw DICOMNetworkError.connectionClosed

        case let abortPDU as AbortPDU:
            _ = stateMachine.handleEvent(.abortReceived(abortPDU))
            await conn.disconnect()
            throw DICOMNetworkError.associationAborted(
                source: abortPDU.source,
                reason: abortPDU.reason
            )

        default:
            try await performAbort(reason: .unexpectedPDU)
            throw DICOMNetworkError.unexpectedPDUType(
                expected: .dataTransfer,
                received: pdu.pduType
            )
        }
    }
    
    /// Releases the association gracefully
    ///
    /// Sends an A-RELEASE-RQ and waits for A-RELEASE-RP.
    ///
    /// - Throws: `DICOMNetworkError.invalidState` if not in established state
    /// - Throws: `DICOMNetworkError.artimTimerExpired` if ARTIM timer expires
    public func release() async throws {
        guard state == .established else {
            throw DICOMNetworkError.invalidState("Cannot release: association not established")
        }
        
        guard let conn = connection else {
            throw DICOMNetworkError.connectionClosed
        }
        
        // Send A-RELEASE-RQ
        let releaseRequest = ReleaseRequestPDU()
        try await conn.send(pdu: releaseRequest)
        _ = stateMachine.handleEvent(.localReleaseRequest)
        
        // Wait for A-RELEASE-RP with ARTIM timer
        var responsePDU: any PDU
        while true {
            do {
                responsePDU = try await receiveWithARTIMTimer(conn: conn)
            } catch let error as DICOMNetworkError where error.isARTIMExpired {
                try await abortOnARTIMExpiry(conn: conn)
                throw error
            }

            // P-DATA arriving in the release window (e.g. a late N-EVENT-REPORT
            // pushed by a Print SCP) is legal: PS3.8 §7.2.2 lets the acceptor
            // keep issuing P-DATA requests until it responds to the release, and
            // Table 9-10 Sta7 + P-DATA-TF → AR-6 "issue P-DATA indication".
            // release() has no consumer for that indication, so this
            // implementation discards it and keeps waiting for A-RELEASE-RP.
            if let dataPDU = responsePDU as? DataTransferPDU {
                _ = stateMachine.handleEvent(.dataTransferReceived(dataPDU))
                continue
            }
            break
        }

        switch responsePDU {
        case _ as ReleaseResponsePDU:
            _ = stateMachine.handleEvent(.releaseResponseReceived)
            await conn.disconnect()

        case let abortPDU as AbortPDU:
            _ = stateMachine.handleEvent(.abortReceived(abortPDU))
            await conn.disconnect()
            throw DICOMNetworkError.associationAborted(
                source: abortPDU.source,
                reason: abortPDU.reason
            )

        case _ as ReleaseRequestPDU:
            // Release collision - both sides requested release simultaneously.
            // PS3.8 Table 9-10 (requestor side): Sta7 + A-RELEASE-RQ PDU → AR-8
            // (issue A-RELEASE indication) → Sta9; local A-RELEASE response →
            // AR-9 (send A-RELEASE-RP) → Sta11; Sta11 + A-RELEASE-RP PDU → AR-3
            // (issue A-RELEASE confirmation, close transport) → Sta1.
            _ = stateMachine.handleEvent(.releaseRequestReceived)
            let releaseResponse = ReleaseResponsePDU()
            try await conn.send(pdu: releaseResponse)
            _ = stateMachine.handleEvent(.releaseResponseSent)

            let collisionPDU: any PDU
            do {
                collisionPDU = try await receiveWithARTIMTimer(conn: conn)
            } catch let error as DICOMNetworkError where error.isARTIMExpired {
                try await abortOnARTIMExpiry(conn: conn)
                throw error
            }

            switch collisionPDU {
            case _ as ReleaseResponsePDU:
                _ = stateMachine.handleEvent(.releaseResponseReceived)
                await conn.disconnect()

            case let abortPDU as AbortPDU:
                _ = stateMachine.handleEvent(.abortReceived(abortPDU))
                await conn.disconnect()
                throw DICOMNetworkError.associationAborted(
                    source: abortPDU.source,
                    reason: abortPDU.reason
                )

            default:
                // Table 9-10: any other PDU in Sta11 → AA-8
                try await performAbort(reason: .unexpectedPDU)
                throw DICOMNetworkError.unexpectedPDUType(
                    expected: .releaseResponse,
                    received: collisionPDU.pduType
                )
            }

        default:
            try await performAbort(reason: .unexpectedPDU)
            throw DICOMNetworkError.unexpectedPDUType(
                expected: .releaseResponse,
                received: responsePDU.pduType
            )
        }
    }
    
    /// Aborts the association
    ///
    /// Sends an A-ABORT PDU and closes the connection immediately.
    ///
    /// - Parameter reason: The abort reason (default: not specified)
    public func abort(reason: AbortReason = .notSpecified) async throws {
        try await performAbort(reason: reason)
    }
    
    // MARK: - Private Methods
    
    /// Finishes an ARTIM expiry after `receiveWithARTIMTimer` has sent the
    /// A-ABORT: closes the transport and returns the state machine to Sta1.
    private func abortOnARTIMExpiry(conn: DICOMConnection) async throws {
        conn.abort()
        _ = stateMachine.handleEvent(.transportConnectionClosed)
    }
    
    private func performAbort(reason: AbortReason) async throws {
        guard let conn = connection else {
            return
        }
        
        // PS3.8 Table 9-26: a plain user abort is sent with source 0
        // (service-user) and reason 0; a protocol reason (unexpected PDU,
        // invalid parameter, ...) belongs to the UL service-provider (source 2),
        // as in Table 9-9 AA-8.
        let abortPDU: AbortPDU
        if reason == .notSpecified {
            abortPDU = AbortPDU(source: .serviceUser, reason: 0)
        } else {
            abortPDU = AbortPDU(source: .serviceProvider, reason: reason)
        }
        try? await conn.send(pdu: abortPDU)
        _ = stateMachine.handleEvent(.abortSent)
        
        conn.abort()
        _ = stateMachine.handleEvent(.transportConnectionClosed)
    }
    
    /// Receives a PDU with ARTIM timer protection
    ///
    /// If artimTimeout is configured and the timer expires before receiving a PDU,
    /// sends an A-ABORT and throws `DICOMNetworkError.artimTimerExpired`.
    ///
    /// PS3.8 Table 9-10 defines ARTIM expiry (AA-2) only in Sta2 and Sta13; a
    /// local timeout in Sta5/Sta7/Sta11 is handled as a local A-ABORT request
    /// primitive (Table 9-9 AA-1): A-ABORT with service-user source, reason 0
    /// (Table 9-26). The A-ABORT is sent before the pending receive is
    /// cancelled, because cancelling it tears the transport down.
    ///
    /// - Parameter conn: The connection to receive from
    /// - Returns: The received PDU
    /// - Throws: `DICOMNetworkError.artimTimerExpired` if timer expires
    private func receiveWithARTIMTimer(conn: DICOMConnection) async throws -> any PDU {
        guard let artimTimeout = configuration.artimTimeout else {
            // ARTIM timer disabled, just receive normally
            return try await conn.receivePDU()
        }
        
        // Use task group to race between receive and timeout
        return try await withThrowingTaskGroup(of: ARTIMResult.self) { group in
            // Task 1: Receive PDU
            group.addTask {
                let pdu = try await conn.receivePDU()
                return .pdu(pdu)
            }
            
            // Task 2: ARTIM timer
            group.addTask {
                try await Task.sleep(for: .seconds(artimTimeout))
                return .timerExpired
            }
            
            // Wait for first result
            guard let result = try await group.next() else {
                throw DICOMNetworkError.artimTimerExpired
            }
            
            switch result {
            case .pdu(let pdu):
                // Cancel the timer task
                group.cancelAll()
                return pdu
            case .timerExpired:
                // AA-1: send A-ABORT (service-user, reason 0) while the
                // transport is still open, then cancel the pending receive
                _ = self.stateMachine.handleEvent(.artimTimerExpired)
                try? await conn.send(pdu: AbortPDU(source: .serviceUser, reason: 0))
                group.cancelAll()
                throw DICOMNetworkError.artimTimerExpired
            }
        }
    }
}

/// Internal enum for ARTIM timer race result
private enum ARTIMResult: Sendable {
    case pdu(any PDU)
    case timerExpired
}

// MARK: - CustomStringConvertible
extension Association: CustomStringConvertible {
    public var description: String {
        """
        Association:
          Local AE: \(configuration.callingAETitle)
          Remote AE: \(configuration.calledAETitle)
          Host: \(configuration.host):\(configuration.port)
          State: \(state)
        """
    }
}

#endif
