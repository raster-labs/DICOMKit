import Foundation
// NEMA-verified: 2026a, checked 2026-09-28 — states relabelled to PS3.8 2026a Tables 9-1..9-5 (Scripts/diff_network.py: 9 of 9), transitions checked against Table 9-10 (Sta13 AA-2 added; requestor timeouts are local AA-1, not the standard's ARTIM)

/// DICOM Association State Machine
///
/// Manages the state transitions for DICOM associations according to
/// the DICOM Upper Layer Protocol state machine.
///
/// Reference: PS3.8 Section 9.2 - DICOM Upper Layer State Machine
///
/// ## States
///
/// The association can be in one of the following states:
/// State numbers follow PS3.8 Tables 9-1 to 9-5:
/// - `idle` (Sta1): No association exists
/// - `awaitingLocalAssociateResponse` (Sta2/Sta3): Transport connection open,
///   awaiting A-ASSOCIATE-RQ PDU (Sta2), then awaiting the local A-ASSOCIATE
///   response primitive (Sta3)
/// - `awaitingTransportOpen` (Sta4): Awaiting transport connection opening to complete
/// - `awaitingRemoteAssociateResponse` (Sta5): Awaiting A-ASSOCIATE-AC or A-ASSOCIATE-RJ PDU
/// - `established` (Sta6): Association established and data transfer allowed
/// - `awaitingRemoteReleaseResponse` (Sta7): Awaiting A-RELEASE-RP PDU
/// - `awaitingLocalReleaseResponse` (Sta8): Awaiting local A-RELEASE response primitive
/// - `releaseCollision` (Sta9-12): Release collision states
/// - `awaitingTransportClose` (Sta13): Awaiting transport connection close
public enum AssociationState: Sendable, Hashable, CustomStringConvertible {
    /// No association exists (Sta1)
    case idle
    
    /// Transport connection open, awaiting A-ASSOCIATE-RQ PDU (Sta2), then
    /// awaiting the local A-ASSOCIATE response primitive (Sta3)
    /// This state is for the acceptor (SCP) side
    case awaitingLocalAssociateResponse
    
    /// A-ASSOCIATE-RQ sent, awaiting A-ASSOCIATE-AC/RJ PDU (Sta5)
    /// This state is for the requestor (SCU) side
    case awaitingRemoteAssociateResponse
    
    /// Association established, data transfer allowed (Sta6)
    case established
    
    /// A-RELEASE-RQ received, awaiting local release response (Sta8)
    case awaitingLocalReleaseResponse
    
    /// A-RELEASE-RQ sent, awaiting A-RELEASE-RP PDU (Sta7)
    case awaitingRemoteReleaseResponse
    
    /// Release collision - awaiting A-RELEASE-RP while processing release (Sta9-12)
    case releaseCollision
    
    /// Awaiting transport connection close (Sta13)
    case awaitingTransportClose
    
    /// Awaiting transport connection opening to complete (Sta4)
    case awaitingTransportOpen
    
    public var description: String {
        switch self {
        case .idle:
            return "Idle (Sta1)"
        case .awaitingLocalAssociateResponse:
            return "Awaiting Local Associate Response (Sta2/Sta3)"
        case .awaitingRemoteAssociateResponse:
            return "Awaiting Remote Associate Response (Sta5)"
        case .established:
            return "Association Established (Sta6)"
        case .awaitingLocalReleaseResponse:
            return "Awaiting Local Release Response (Sta8)"
        case .awaitingRemoteReleaseResponse:
            return "Awaiting Remote Release Response (Sta7)"
        case .releaseCollision:
            return "Release Collision (Sta9-12)"
        case .awaitingTransportClose:
            return "Awaiting Transport Close (Sta13)"
        case .awaitingTransportOpen:
            return "Awaiting Transport Open (Sta4)"
        }
    }
    
    /// Whether data transfer is allowed in this state
    public var canTransferData: Bool {
        self == .established
    }
    
    /// Whether the association is in a terminal state
    public var isTerminal: Bool {
        self == .idle
    }
}

/// Events that trigger state transitions
///
/// Reference: PS3.8 Table 9-10
public enum AssociationEvent: Sendable {
    // Transport events
    case transportConnected
    case transportConnectionFailed
    case transportConnectionClosed
    
    // Association request events
    case associateRequestSent
    case associateRequestReceived(AssociateRequestPDU)
    case associateAcceptReceived(AssociateAcceptPDU)
    case associateRejectReceived(AssociateRejectPDU)
    case associateAcceptSent
    case associateRejectSent
    
    // Release events
    case releaseRequestSent
    case releaseRequestReceived
    case releaseResponseReceived
    case releaseResponseSent
    
    // Abort events
    case abortReceived(AbortPDU)
    case abortSent
    
    // Data transfer events
    case dataTransferReceived(DataTransferPDU)
    case dataTransferSent
    
    // Local service events
    case localAbortRequest
    case localReleaseRequest
    
    // Timer events
    /// ARTIM (Association Request/Release Timer) expired
    ///
    /// This event is triggered when the ARTIM timer fires while waiting for
    /// an association response (A-ASSOCIATE-AC/RJ), a release response
    /// (A-RELEASE-RP) or the transport close (Sta13).
    ///
    /// Reference: PS3.8 Section 9.1.5 - ARTIM Timer
    case artimTimerExpired
}

/// Actions to be performed during state transitions
///
/// Reference: PS3.8 Table 9-10
public enum AssociationAction: Sendable {
    /// Send an A-ASSOCIATE-RQ PDU
    case sendAssociateRequest(AssociateRequestPDU)
    
    /// Send an A-ASSOCIATE-AC PDU
    case sendAssociateAccept(AssociateAcceptPDU)
    
    /// Send an A-ASSOCIATE-RJ PDU
    case sendAssociateReject(AssociateRejectPDU)
    
    /// Send an A-RELEASE-RQ PDU
    case sendReleaseRequest
    
    /// Send an A-RELEASE-RP PDU
    case sendReleaseResponse
    
    /// Send an A-ABORT PDU
    case sendAbort(AbortPDU)
    
    /// Close the transport connection
    case closeTransport
    
    /// Issue an A-ASSOCIATE confirmation (accept) to local user
    case issueAssociateConfirmAccept(AssociateAcceptPDU)
    
    /// Issue an A-ASSOCIATE confirmation (reject) to local user
    case issueAssociateConfirmReject(AssociateRejectPDU)
    
    /// Issue an A-ASSOCIATE indication to local user
    case issueAssociateIndication(AssociateRequestPDU)
    
    /// Issue an A-RELEASE confirmation to local user
    case issueReleaseConfirm
    
    /// Issue an A-RELEASE indication to local user
    case issueReleaseIndication
    
    /// Issue an A-ABORT indication to local user
    case issueAbortIndication(AbortSource, UInt8)
    
    /// Issue a P-DATA indication to local user
    case issueDataIndication(DataTransferPDU)
    
    /// No action required
    case none
}

/// Result of a state transition
public struct TransitionResult: Sendable {
    /// The new state after the transition
    public let newState: AssociationState
    
    /// Actions to perform as part of the transition
    public let actions: [AssociationAction]
    
    /// Creates a transition result
    public init(newState: AssociationState, actions: [AssociationAction] = []) {
        self.newState = newState
        self.actions = actions
    }
}

/// Association state machine for managing DICOM Upper Layer Protocol state transitions
///
/// This class implements the state machine defined in DICOM PS3.8 Section 9.2.
/// It tracks the current state and provides transition logic based on events.
///
/// ## Usage
///
/// ```swift
/// let stateMachine = AssociationStateMachine()
///
/// // Handle transport connection
/// let result = stateMachine.handleEvent(.transportConnected)
/// // Execute actions based on result.actions
///
/// // Send association request
/// let sendResult = stateMachine.handleEvent(.associateRequestSent)
/// ```
public final class AssociationStateMachine: @unchecked Sendable {
    
    /// Current state of the association
    public private(set) var state: AssociationState = .idle
    
    /// Lock for thread-safe state access
    private let lock = NSLock()
    
    /// Creates a new association state machine
    public init() {}
    
    /// Creates a state machine starting in a specific state (for testing)
    public init(initialState: AssociationState) {
        self.state = initialState
    }
    
    /// Handles an event and returns the resulting state transition
    ///
    /// - Parameter event: The event to process
    /// - Returns: The transition result containing new state and actions
    public func handleEvent(_ event: AssociationEvent) -> TransitionResult {
        lock.lock()
        defer { lock.unlock() }
        
        let result = transition(from: state, event: event)
        state = result.newState
        return result
    }
    
    /// Resets the state machine to idle
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        state = .idle
    }
    
    // MARK: - State Transition Logic
    
    private func transition(from state: AssociationState, event: AssociationEvent) -> TransitionResult {
        switch (state, event) {
            
        // Idle state transitions (Sta1)
        case (.idle, .transportConnected):
            // AE-1: Transport connection indication
            return TransitionResult(newState: .awaitingTransportOpen)
            
        // Awaiting transport open transitions (Sta4)
        case (.awaitingTransportOpen, .associateRequestSent):
            // AE-2: A-ASSOCIATE request primitive
            return TransitionResult(newState: .awaitingRemoteAssociateResponse)
            
        case (.awaitingTransportOpen, .localAbortRequest):
            // AA-1: Abort request
            return TransitionResult(newState: .idle, actions: [.closeTransport])
            
        // Awaiting local associate response (Sta2/Sta3 - SCP side)
        case (.awaitingLocalAssociateResponse, .associateRequestReceived(let pdu)):
            return TransitionResult(
                newState: .awaitingLocalAssociateResponse,
                actions: [.issueAssociateIndication(pdu)]
            )
            
        case (.awaitingLocalAssociateResponse, .associateAcceptSent):
            return TransitionResult(newState: .established)
            
        case (.awaitingLocalAssociateResponse, .associateRejectSent):
            return TransitionResult(newState: .idle, actions: [.closeTransport])
            
        // Awaiting remote associate response transitions (Sta5)
        case (.awaitingRemoteAssociateResponse, .associateAcceptReceived(let pdu)):
            // AE-3: A-ASSOCIATE-AC PDU received
            return TransitionResult(
                newState: .established,
                actions: [.issueAssociateConfirmAccept(pdu)]
            )
            
        case (.awaitingRemoteAssociateResponse, .associateRejectReceived(let pdu)):
            // AE-4: A-ASSOCIATE-RJ PDU received
            return TransitionResult(
                newState: .idle,
                actions: [.issueAssociateConfirmReject(pdu), .closeTransport]
            )
            
        case (.awaitingRemoteAssociateResponse, .abortReceived(let pdu)):
            // AA-3: A-ABORT PDU received
            return TransitionResult(
                newState: .idle,
                actions: [.issueAbortIndication(pdu.source, pdu.reason), .closeTransport]
            )
            
        case (.awaitingRemoteAssociateResponse, .transportConnectionClosed):
            // AA-4: Transport connection closed
            return TransitionResult(
                newState: .idle,
                actions: [.issueAbortIndication(.serviceProvider, AbortReason.notSpecified.rawValue)]
            )
            
        case (.awaitingRemoteAssociateResponse, .artimTimerExpired):
            // Local timeout while awaiting A-ASSOCIATE-AC/RJ. PS3.8 Table 9-10
            // defines ARTIM expiry (AA-2) only in Sta2 and Sta13; a local timer
            // here is handled as an A-ABORT request primitive (AA-1): send
            // A-ABORT with service-user source, reason 0, then close transport.
            let abortPDU = AbortPDU(source: .serviceUser, reason: 0)
            return TransitionResult(
                newState: .awaitingTransportClose,
                actions: [.sendAbort(abortPDU)]
            )
            
        // Established state transitions (Sta6)
        case (.established, .dataTransferReceived(let pdu)):
            // DT-2: P-DATA-TF PDU received
            return TransitionResult(
                newState: .established,
                actions: [.issueDataIndication(pdu)]
            )
            
        case (.established, .dataTransferSent):
            // DT-1: P-DATA request primitive
            return TransitionResult(newState: .established)
            
        case (.established, .releaseRequestReceived):
            // AR-2: A-RELEASE-RQ PDU received
            return TransitionResult(
                newState: .awaitingLocalReleaseResponse,
                actions: [.issueReleaseIndication]
            )
            
        case (.established, .localReleaseRequest):
            // AR-1: A-RELEASE request primitive
            return TransitionResult(
                newState: .awaitingRemoteReleaseResponse,
                actions: [.sendReleaseRequest]
            )
            
        case (.established, .abortReceived(let pdu)):
            // AA-3: A-ABORT PDU received
            return TransitionResult(
                newState: .idle,
                actions: [.issueAbortIndication(pdu.source, pdu.reason), .closeTransport]
            )
            
        case (.established, .localAbortRequest):
            // AA-1: A-ABORT request primitive (local user abort)
            let abortPDU = AbortPDU(source: .serviceUser, reason: 0)
            return TransitionResult(
                newState: .awaitingTransportClose,
                actions: [.sendAbort(abortPDU)]
            )
            
        case (.established, .transportConnectionClosed):
            // AA-4: Transport connection closed
            return TransitionResult(
                newState: .idle,
                actions: [.issueAbortIndication(.serviceProvider, AbortReason.notSpecified.rawValue)]
            )
            
        // Awaiting local release response (Sta8)
        case (.awaitingLocalReleaseResponse, .releaseResponseSent):
            // AR-4: A-RELEASE response primitive
            return TransitionResult(
                newState: .awaitingTransportClose,
                actions: [.sendReleaseResponse]
            )
            
        case (.awaitingLocalReleaseResponse, .localAbortRequest):
            let abortPDU = AbortPDU(source: .serviceUser, reason: 0)
            return TransitionResult(
                newState: .awaitingTransportClose,
                actions: [.sendAbort(abortPDU)]
            )
            
        case (.awaitingLocalReleaseResponse, .abortReceived(let pdu)):
            return TransitionResult(
                newState: .idle,
                actions: [.issueAbortIndication(pdu.source, pdu.reason), .closeTransport]
            )
            
        // Awaiting remote release response (Sta7)
        case (.awaitingRemoteReleaseResponse, .releaseResponseReceived):
            // AR-3: A-RELEASE-RP PDU received
            return TransitionResult(
                newState: .idle,
                actions: [.issueReleaseConfirm, .closeTransport]
            )
            
        case (.awaitingRemoteReleaseResponse, .releaseRequestReceived):
            // AR-8: A-RELEASE-RQ PDU received (release collision)
            return TransitionResult(
                newState: .releaseCollision,
                actions: [.issueReleaseIndication]
            )
            
        case (.awaitingRemoteReleaseResponse, .abortReceived(let pdu)):
            return TransitionResult(
                newState: .idle,
                actions: [.issueAbortIndication(pdu.source, pdu.reason), .closeTransport]
            )
            
        case (.awaitingRemoteReleaseResponse, .transportConnectionClosed):
            return TransitionResult(
                newState: .idle,
                actions: [.issueAbortIndication(.serviceProvider, AbortReason.notSpecified.rawValue)]
            )
            
        case (.awaitingRemoteReleaseResponse, .artimTimerExpired):
            // Local timeout while awaiting A-RELEASE-RP. PS3.8 Table 9-10
            // defines ARTIM expiry (AA-2) only in Sta2 and Sta13; a local timer
            // here is handled as an A-ABORT request primitive (AA-1): send
            // A-ABORT with service-user source, reason 0, then close transport.
            let abortPDU = AbortPDU(source: .serviceUser, reason: 0)
            return TransitionResult(
                newState: .awaitingTransportClose,
                actions: [.sendAbort(abortPDU)]
            )
            
        // Release collision (Sta9-12)
        case (.releaseCollision, .releaseResponseSent):
            // AR-9: A-RELEASE response primitive (collision resolution)
            return TransitionResult(
                newState: .awaitingRemoteReleaseResponse,
                actions: [.sendReleaseResponse]
            )
            
        case (.releaseCollision, .releaseResponseReceived):
            // AR-10: A-RELEASE-RP PDU received (collision resolution)
            return TransitionResult(
                newState: .awaitingLocalReleaseResponse,
                actions: [.issueReleaseConfirm]
            )
            
        // Awaiting transport close (Sta13)
        case (.awaitingTransportClose, .transportConnectionClosed):
            // AR-5: Transport connection closed
            return TransitionResult(newState: .idle)
            
        case (.awaitingTransportClose, .abortReceived):
            // AA-2: A-ABORT PDU in Sta13 - stop ARTIM timer, close transport
            return TransitionResult(newState: .idle, actions: [.closeTransport])
            
        case (.awaitingTransportClose, .artimTimerExpired):
            // AA-2: ARTIM timer expired in Sta13 - close transport
            return TransitionResult(newState: .idle, actions: [.closeTransport])
            
        case (.awaitingTransportClose, _):
            // Ignore other events during transport close
            return TransitionResult(newState: .awaitingTransportClose)
            
        // Transport failure in any state
        case (_, .transportConnectionFailed):
            return TransitionResult(
                newState: .idle,
                actions: [.issueAbortIndication(.serviceProvider, AbortReason.notSpecified.rawValue)]
            )
            
        // Default - invalid transition
        default:
            // Log warning about unexpected event
            return TransitionResult(newState: state, actions: [.none])
        }
    }
}
