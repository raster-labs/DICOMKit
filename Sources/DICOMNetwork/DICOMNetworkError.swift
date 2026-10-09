import Foundation
// NEMA-verified: 2026a, checked 2026-10-01 — AssociateRejectResult/Source and AbortSource/AbortReason values text-diffed against PS3.8 2026a Tables 9-21 and 9-26 (Scripts/diff_network.py): 14 of 14 match; ARTIM citation §9.1.5; print failures worded per PS3.4 Annex H / PS3.7 Annex C (D91); MPPS N-CREATE / N-SET failures per PS3.4 Table F.7.2-2 and PS3.7 Annex C with Error ID / Error Comment (D83)

// MARK: - Error Category

/// Category classification for DICOM network errors
///
/// Error categories help determine the appropriate response to network failures:
/// - **transient**: Temporary failures that may succeed on retry (network hiccups, server busy)
/// - **permanent**: Failures that won't succeed on retry without intervention (invalid credentials, unsupported features)
/// - **configuration**: Errors due to misconfigured client or server settings
/// - **protocol**: Errors in DICOM protocol handling or unexpected peer behavior
/// - **timeout**: Time-based failures (connection or operation timeouts)
/// - **resource**: Resource availability issues (rate limiting, circuit breaker)
///
/// Reference: DICOM PS3.8 - Network Communication Support
public enum ErrorCategory: String, Sendable, Hashable, CaseIterable {
    /// Transient error that may succeed on retry
    ///
    /// Examples: Network hiccup, server temporarily unavailable, connection reset
    case transient
    
    /// Permanent error that will not succeed on retry without intervention
    ///
    /// Examples: Invalid AE title, SOP class not supported, authentication failure
    case permanent
    
    /// Configuration error requiring settings change
    ///
    /// Examples: Invalid PDU size, incorrect port, wrong AE title format
    case configuration
    
    /// Protocol error indicating unexpected DICOM communication behavior
    ///
    /// Examples: Invalid PDU format, unexpected PDU type, encoding/decoding failures
    case `protocol`
    
    /// Timeout error when operation exceeded time limits
    ///
    /// Examples: Connection timeout, operation timeout, ARTIM timer expired
    case timeout
    
    /// Resource error due to rate limiting or protection mechanisms
    ///
    /// Examples: Circuit breaker open, too many concurrent connections
    case resource
}

extension ErrorCategory: CustomStringConvertible {
    public var description: String {
        switch self {
        case .transient:
            return "Transient"
        case .permanent:
            return "Permanent"
        case .configuration:
            return "Configuration"
        case .protocol:
            return "Protocol"
        case .timeout:
            return "Timeout"
        case .resource:
            return "Resource"
        }
    }
}

// MARK: - Recovery Suggestion

/// Suggested recovery actions for DICOM network errors
///
/// Recovery suggestions provide actionable guidance for handling errors:
/// - **retry**: Simple retry may succeed (with exponential backoff)
/// - **retryWithBackoff**: Retry after a delay with increasing intervals
/// - **checkConfiguration**: Review client/server configuration settings
/// - **contactAdministrator**: Escalate to system administrator
/// - **waitAndRetry**: Wait for external condition to change (circuit breaker, rate limit)
/// - **useAlternateServer**: Try a different PACS server if available
/// - **noRecovery**: Error cannot be recovered programmatically
public enum RecoverySuggestion: Sendable, Hashable {
    /// Retry the operation immediately
    case retry
    
    /// Retry the operation after waiting with exponential backoff
    case retryWithBackoff(initialDelay: TimeInterval)
    
    /// Check and fix client or server configuration
    case checkConfiguration(details: String)
    
    /// Contact system administrator for assistance
    case contactAdministrator(reason: String)
    
    /// Wait for specified duration before retrying
    case waitAndRetry(duration: TimeInterval)
    
    /// Try an alternate server or endpoint
    case useAlternateServer
    
    /// No automatic recovery possible
    case noRecovery(reason: String)
}

extension RecoverySuggestion: CustomStringConvertible {
    public var description: String {
        switch self {
        case .retry:
            return "Retry the operation"
        case .retryWithBackoff(let delay):
            return "Retry with exponential backoff starting at \(delay)s"
        case .checkConfiguration(let details):
            return "Check configuration: \(details)"
        case .contactAdministrator(let reason):
            return "Contact administrator: \(reason)"
        case .waitAndRetry(let duration):
            return "Wait \(Int(duration))s and retry"
        case .useAlternateServer:
            return "Try an alternate server"
        case .noRecovery(let reason):
            return "No recovery possible: \(reason)"
        }
    }
}

// MARK: - Timeout Configuration

/// Configuration for different types of network timeouts
///
/// Allows fine-grained control over timeout behavior for different phases
/// of DICOM network operations.
///
/// ## Timeout Types
///
/// - **connect**: Time allowed to establish TCP connection
/// - **read**: Time allowed for reading data from the network
/// - **write**: Time allowed for writing data to the network
/// - **operation**: Total time allowed for completing a DICOM operation (e.g., C-FIND, C-STORE)
/// - **association**: Time allowed for ARTIM (Association Request/Release Timer)
///
/// ## Usage
///
/// ```swift
/// // Default configuration
/// let defaults = TimeoutConfiguration.default
///
/// // Fast local network
/// let fast = TimeoutConfiguration(
///     connect: 5,
///     read: 10,
///     write: 10,
///     operation: 60,
///     association: 15
/// )
///
/// // Slow WAN connection
/// let slow = TimeoutConfiguration(
///     connect: 30,
///     read: 60,
///     write: 60,
///     operation: 300,
///     association: 45
/// )
/// ```
///
/// Reference: PS3.8 Section 9.1.5 - ARTIM Timer
public struct TimeoutConfiguration: Sendable, Hashable {
    /// Time allowed to establish TCP connection (in seconds)
    public let connect: TimeInterval
    
    /// Time allowed for reading data from the network (in seconds)
    public let read: TimeInterval
    
    /// Time allowed for writing data to the network (in seconds)
    public let write: TimeInterval
    
    /// Total time allowed for completing a DICOM operation (in seconds)
    ///
    /// This covers the entire duration of an operation like C-FIND or C-STORE,
    /// including multiple PDU exchanges.
    public let operation: TimeInterval
    
    /// Time allowed for ARTIM timer - association establishment/release (in seconds)
    ///
    /// Reference: PS3.8 Section 9.1.5 - ARTIM Timer
    public let association: TimeInterval
    
    /// Creates a timeout configuration with specified values
    ///
    /// - Parameters:
    ///   - connect: Connection timeout in seconds (default: 30)
    ///   - read: Read timeout in seconds (default: 30)
    ///   - write: Write timeout in seconds (default: 30)
    ///   - operation: Operation timeout in seconds (default: 120)
    ///   - association: Association/ARTIM timeout in seconds (default: 30)
    public init(
        connect: TimeInterval = 30,
        read: TimeInterval = 30,
        write: TimeInterval = 30,
        operation: TimeInterval = 120,
        association: TimeInterval = 30
    ) {
        self.connect = connect
        self.read = read
        self.write = write
        self.operation = operation
        self.association = association
    }
    
    /// Default timeout configuration suitable for most networks
    ///
    /// - connect: 30 seconds
    /// - read: 30 seconds
    /// - write: 30 seconds
    /// - operation: 120 seconds
    /// - association: 30 seconds
    public static let `default` = TimeoutConfiguration()
    
    /// Fast timeout configuration for local networks or testing
    ///
    /// - connect: 5 seconds
    /// - read: 10 seconds
    /// - write: 10 seconds
    /// - operation: 30 seconds
    /// - association: 10 seconds
    public static let fast = TimeoutConfiguration(
        connect: 5,
        read: 10,
        write: 10,
        operation: 30,
        association: 10
    )
    
    /// Slow timeout configuration for WAN or high-latency connections
    ///
    /// - connect: 60 seconds
    /// - read: 120 seconds
    /// - write: 120 seconds
    /// - operation: 600 seconds
    /// - association: 90 seconds
    public static let slow = TimeoutConfiguration(
        connect: 60,
        read: 120,
        write: 120,
        operation: 600,
        association: 90
    )
}

extension TimeoutConfiguration: CustomStringConvertible {
    public var description: String {
        "TimeoutConfiguration(connect: \(connect)s, read: \(read)s, write: \(write)s, operation: \(operation)s, association: \(association)s)"
    }
}

// MARK: - Timeout Type

/// Type of timeout that occurred
///
/// Used to provide specific information about which phase of an operation timed out.
public enum TimeoutType: String, Sendable, Hashable, CaseIterable {
    /// Connection establishment timed out
    case connect
    
    /// Reading from network timed out
    case read
    
    /// Writing to network timed out
    case write
    
    /// Overall operation timed out
    case operation
    
    /// Association (ARTIM timer) timed out
    case association
}

extension TimeoutType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .connect:
            return "Connection"
        case .read:
            return "Read"
        case .write:
            return "Write"
        case .operation:
            return "Operation"
        case .association:
            return "Association"
        }
    }
}

// MARK: - DICOM Network Error

/// Errors that can occur during DICOM network operations
///
/// Reference: DICOM PS3.8 - Network Communication Support
public enum DICOMNetworkError: Error, Sendable {
    /// Connection to remote host failed
    case connectionFailed(String)
    
    /// Connection timed out
    case timeout
    
    /// Invalid PDU received
    case invalidPDU(String)
    
    /// PDU too large for buffer
    case pduTooLarge(received: UInt32, maximum: UInt32)
    
    /// Unexpected PDU type received
    case unexpectedPDUType(expected: PDUType, received: PDUType)
    
    /// Association was rejected by the remote peer
    ///
    /// - Parameters:
    ///   - result: The rejection result code
    ///   - source: The source of the rejection
    ///   - reason: The reason for rejection
    case associationRejected(result: AssociateRejectResult, source: AssociateRejectSource, reason: UInt8)
    
    /// Association was aborted
    ///
    /// - Parameters:
    ///   - source: The source of the abort
    ///   - reason: The reason for abort
    case associationAborted(source: AbortSource, reason: UInt8)
    
    /// No presentation context was accepted for the requested operation
    case noPresentationContextAccepted
    
    /// The requested SOP Class is not supported
    case sopClassNotSupported(String)
    
    /// Invalid Application Entity title
    ///
    /// AE titles must be 1-16 ASCII characters
    case invalidAETitle(String)
    
    /// Network connection was closed unexpectedly
    case connectionClosed
    
    /// Invalid protocol state for the requested operation
    case invalidState(String)
    
    /// Encoding error when serializing PDU
    case encodingFailed(String)
    
    /// Decoding error when deserializing PDU
    case decodingFailed(String)

    /// A declared size or count in a received PDU exceeds a protocol resource limit
    ///
    /// Structured counterpart of `DICOMError.limitExceeded` for the network layer:
    /// distinguishes "the peer declared something absurdly large" (allocation-DoS
    /// guard, e.g. `PDUDecoder.maximumPDULength`) from a merely malformed PDU.
    case limitExceeded(String)
    
    /// Query operation failed with a DIMSE status
    case queryFailed(DIMSEStatus)
    
    /// Retrieve operation failed with a DIMSE status
    case retrieveFailed(DIMSEStatus)
    
    /// ARTIM timer expired while waiting for association response
    ///
    /// The ARTIM (Association Request/Release Timer) fires when waiting
    /// for an A-ASSOCIATE-AC/RJ or A-RELEASE-RP response takes too long.
    ///
    /// Reference: PS3.8 Section 9.1.5 - ARTIM Timer
    case artimTimerExpired
    
    /// Circuit breaker is open for this server
    ///
    /// The server has failed repeatedly and the circuit breaker has tripped
    /// to prevent further requests. Wait for the reset timeout before retrying.
    ///
    /// - Parameters:
    ///   - host: The server host
    ///   - port: The server port
    ///   - retryAfter: When the circuit may allow requests again
    case circuitBreakerOpen(host: String, port: UInt16, retryAfter: Date)
    
    /// Detailed timeout with specific timeout type
    ///
    /// Provides more granular information about which phase of the operation timed out.
    ///
    /// - Parameters:
    ///   - type: The type of timeout that occurred
    ///   - duration: The timeout duration that was exceeded
    ///   - operation: Optional description of the operation that timed out
    case operationTimeout(type: TimeoutType, duration: TimeInterval, operation: String?)
    
    /// Store operation failed with a DIMSE status
    case storeFailed(DIMSEStatus)
    
    /// Partial operation failure
    ///
    /// Some operations succeeded while others failed. Used for batch operations.
    ///
    /// - Parameters:
    ///   - succeeded: Number of operations that succeeded
    ///   - failed: Number of operations that failed
    ///   - details: Optional details about the failures
    case partialFailure(succeeded: Int, failed: Int, details: String?)
    
    /// Print operation failed with a DIMSE status
    ///
    /// Used for Print Management Service failures (Film Session, Film Box, Print Job operations).
    /// `detail` carries peer-supplied diagnostic text — Error Comment (0000,0902) and,
    /// when present, Error ID (0000,0903) — so users see e.g. "OUT OF FILM" instead of
    /// only a numeric status.
    case printOperationFailed(DIMSEStatus, detail: String?)

    /// A Modality Performed Procedure Step N-CREATE or N-SET was answered with a
    /// Failure status (PS3.4 F.7.2.1.4 / F.7.2.2.4, Table F.7.2-2; PS3.7 Annex C).
    ///
    /// - Parameters:
    ///   - operation: "N-CREATE" or "N-SET"
    ///   - status: the response Status (0000,0900)
    ///   - errorComment: the response Error Comment (0000,0902), when present
    ///   - errorID: the response Error ID (0000,0903), when present — e.g. 0xA710
    ///     "Performed Procedure Step Object may no longer be updated" (Table F.7.2-2)
    ///
    /// Before 2026-10-01 these failures were thrown as ``storeFailed(_:)`` and read
    /// "Store failed: …", a C-STORE wording (D83).
    case mppsOperationFailed(operation: String, status: DIMSEStatus, errorComment: String?, errorID: UInt16?)

    /// Unexpected response received
    ///
    /// The response received did not match the expected format or content.
    case unexpectedResponse
}

extension DICOMNetworkError {
    /// "Failure (0x0110): Processing Failure — Error ID A710H: Performed Procedure Step
    /// Object may no longer be updated": the status worded per PS3.4 Table F.7.2-2
    /// (N-SET) or PS3.7 Annex C, then the Error ID (with its Table F.7.2-2 Error
    /// Comment when listed) and the SCP's own Error Comment.
    static func mppsFailureText(operation: String, status: DIMSEStatus, errorComment: String?, errorID: UInt16?) -> String {
        var text = status.description(for: operation == "N-SET" ? .mppsNSet : .dimseN)
        var details: [String] = []
        if let errorID {
            var idText = "Error ID " + String(format: "%04X", errorID) + "H"
            if operation == "N-SET", let meaning = DIMSEServiceStatusText.mppsNSetErrorComment(errorID: errorID) {
                idText += ": " + meaning
            }
            details.append(idText)
        }
        if let comment = errorComment?.trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")), !comment.isEmpty {
            details.append("Error Comment: " + comment)
        }
        if !details.isEmpty { text += " — " + details.joined(separator: "; ") }
        return text
    }

    /// Backward-compatible factory for ``printOperationFailed(_:detail:)`` without detail text.
    public static func printOperationFailed(_ status: DIMSEStatus) -> DICOMNetworkError {
        .printOperationFailed(status, detail: nil)
    }
}

// MARK: - CustomStringConvertible
extension DICOMNetworkError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .timeout:
            return "Connection timed out"
        case .invalidPDU(let message):
            return "Invalid PDU: \(message)"
        case .pduTooLarge(let received, let maximum):
            return "PDU too large: received \(received) bytes, maximum is \(maximum) bytes"
        case .unexpectedPDUType(let expected, let received):
            return "Unexpected PDU type: expected \(expected), received \(received)"
        case .associationRejected(let result, let source, let reason):
            return "Association rejected: result=\(result), source=\(source), reason=\(reason)"
        case .associationAborted(let source, let reason):
            return "Association aborted: source=\(source), reason=\(reason)"
        case .noPresentationContextAccepted:
            return "No presentation context was accepted"
        case .sopClassNotSupported(let uid):
            return "SOP Class not supported: \(uid)"
        case .invalidAETitle(let ae):
            return "Invalid AE Title: '\(ae)'"
        case .connectionClosed:
            return "Connection was closed unexpectedly"
        case .invalidState(let message):
            return "Invalid protocol state: \(message)"
        case .encodingFailed(let message):
            return "Encoding failed: \(message)"
        case .decodingFailed(let message):
            return "Decoding failed: \(message)"
        case .limitExceeded(let message):
            return "Protocol limit exceeded: \(message)"
        case .queryFailed(let status):
            return "Query failed: \(status)"
        case .retrieveFailed(let status):
            return "Retrieve failed: \(status)"
        case .artimTimerExpired:
            return "ARTIM timer expired: remote peer did not respond in time"
        case .circuitBreakerOpen(let host, let port, let retryAfter):
            let retryInSeconds = max(0, Int(retryAfter.timeIntervalSinceNow))
            return "Circuit breaker open for \(host):\(port). Retry in \(retryInSeconds) seconds."
        case .operationTimeout(let type, let duration, let operation):
            if let op = operation {
                return "\(type) timeout after \(Int(duration))s during \(op)"
            }
            return "\(type) timeout after \(Int(duration))s"
        case .storeFailed(let status):
            return "Store failed: \(status)"
        case .partialFailure(let succeeded, let failed, let details):
            var message = "Partial failure: \(succeeded) succeeded, \(failed) failed"
            if let details = details {
                message += ". \(details)"
            }
            return message
        case .printOperationFailed(let status, let detail):
            // PS3.4 Annex H / PS3.7 Annex C wording (D91)
            let statusText = DIMSEServiceStatusText.describePrintStatus(status)
            if let detail = detail, !detail.isEmpty {
                return "Print operation failed: \(statusText) — \(detail)"
            }
            return "Print operation failed: \(statusText)"
        case .mppsOperationFailed(let operation, let status, let errorComment, let errorID):
            return "MPPS \(operation) failed: "
                + Self.mppsFailureText(operation: operation, status: status, errorComment: errorComment, errorID: errorID)
        case .unexpectedResponse:
            return "Unexpected response received"
        }
    }
}

// MARK: - LocalizedError
extension DICOMNetworkError: LocalizedError {
    public var errorDescription: String? { description }
}

// MARK: - Error Helpers

extension DICOMNetworkError {
    /// Returns true if this error is an ARTIM timer expiration
    public var isARTIMExpired: Bool {
        if case .artimTimerExpired = self {
            return true
        }
        return false
    }
    
    /// The category of this error
    ///
    /// Use this to determine the general class of error and make decisions
    /// about retry strategies and user notifications.
    ///
    /// ## Example
    ///
    /// ```swift
    /// do {
    ///     try await client.verify()
    /// } catch let error as DICOMNetworkError {
    ///     switch error.category {
    ///     case .transient:
    ///         // Retry with exponential backoff
    ///         break
    ///     case .configuration:
    ///         // Display configuration error to user
    ///         break
    ///     case .timeout:
    ///         // Offer to increase timeout or retry
    ///         break
    ///     default:
    ///         break
    ///     }
    /// }
    /// ```
    public var category: ErrorCategory {
        switch self {
        case .connectionFailed:
            return .transient
        case .timeout:
            return .timeout
        case .invalidPDU:
            return .protocol
        case .pduTooLarge:
            return .configuration
        case .unexpectedPDUType:
            return .protocol
        case .associationRejected(let result, _, _):
            return result == .rejectedTransient ? .transient : .permanent
        case .associationAborted:
            return .transient
        case .noPresentationContextAccepted:
            return .configuration
        case .sopClassNotSupported:
            return .permanent
        case .invalidAETitle:
            return .configuration
        case .connectionClosed:
            return .transient
        case .invalidState:
            return .protocol
        case .encodingFailed:
            return .protocol
        case .decodingFailed:
            return .protocol
        case .limitExceeded:
            return .protocol
        case .queryFailed:
            return .permanent
        case .retrieveFailed:
            return .permanent
        case .artimTimerExpired:
            return .timeout
        case .circuitBreakerOpen:
            return .resource
        case .operationTimeout:
            return .timeout
        case .storeFailed:
            return .permanent
        case .partialFailure:
            return .transient
        case .printOperationFailed:
            return .permanent
        case .mppsOperationFailed:
            return .permanent
        case .unexpectedResponse:
            return .protocol
        }
    }
    
    /// Whether this error is potentially recoverable through retry
    ///
    /// Returns `true` if retrying the operation might succeed.
    /// For transient errors, retrying with exponential backoff is recommended.
    ///
    /// ## Example
    ///
    /// ```swift
    /// do {
    ///     try await client.verify()
    /// } catch let error as DICOMNetworkError where error.isRetryable {
    ///     // Retry with exponential backoff
    ///     try await Task.sleep(for: .seconds(1))
    ///     try await client.verify()
    /// }
    /// ```
    public var isRetryable: Bool {
        switch self {
        case .connectionFailed,
             .timeout,
             .connectionClosed,
             .artimTimerExpired,
             .partialFailure:
            return true
        case .associationRejected(let result, _, _):
            return result == .rejectedTransient
        case .associationAborted:
            return true
        case .circuitBreakerOpen:
            return true // After waiting
        case .operationTimeout:
            return true
        case .invalidPDU,
             .pduTooLarge,
             .unexpectedPDUType,
             .noPresentationContextAccepted,
             .sopClassNotSupported,
             .invalidAETitle,
             .invalidState,
             .encodingFailed,
             .decodingFailed,
             .limitExceeded,
             .queryFailed,
             .retrieveFailed,
             .storeFailed,
             .printOperationFailed,
             .mppsOperationFailed,
             .unexpectedResponse:
            return false
        }
    }
    
    /// Recovery suggestion for this error
    ///
    /// Provides actionable guidance for handling the error, including
    /// whether to retry, check configuration, or escalate to an administrator.
    ///
    /// ## Example
    ///
    /// ```swift
    /// do {
    ///     try await client.verify()
    /// } catch let error as DICOMNetworkError {
    ///     print("Error: \(error.description)")
    ///     print("Suggestion: \(error.recoverySuggestion)")
    /// }
    /// ```
    public var recoverySuggestion: RecoverySuggestion {
        switch self {
        case .connectionFailed:
            return .retryWithBackoff(initialDelay: 1.0)
        case .timeout:
            return .retryWithBackoff(initialDelay: 2.0)
        case .invalidPDU(let message):
            return .checkConfiguration(details: "Invalid PDU received: \(message). Check protocol compatibility.")
        case .pduTooLarge(let received, let maximum):
            return .checkConfiguration(details: "Increase maxPDUSize (currently \(maximum) bytes) or configure remote to send smaller PDUs (received \(received) bytes)")
        case .unexpectedPDUType:
            return .checkConfiguration(details: "Unexpected PDU type. Check protocol version compatibility.")
        case .associationRejected(let result, let source, _):
            if result == .rejectedTransient {
                return .retryWithBackoff(initialDelay: 5.0)
            }
            return .checkConfiguration(details: "Association rejected by \(source). Verify AE titles and presentation contexts.")
        case .associationAborted:
            return .retryWithBackoff(initialDelay: 1.0)
        case .noPresentationContextAccepted:
            return .checkConfiguration(details: "No presentation context accepted. Verify SOP classes and transfer syntaxes are supported by the remote peer.")
        case .sopClassNotSupported(let uid):
            return .noRecovery(reason: "SOP Class \(uid) is not supported by the remote peer")
        case .invalidAETitle(let ae):
            return .checkConfiguration(details: "AE Title '\(ae)' is invalid. Must be 1-16 ASCII characters.")
        case .connectionClosed:
            return .retry
        case .invalidState:
            return .checkConfiguration(details: "Operation attempted in invalid state. Reset connection and try again.")
        case .encodingFailed(let message):
            return .contactAdministrator(reason: "PDU encoding failed: \(message)")
        case .decodingFailed(let message):
            return .checkConfiguration(details: "PDU decoding failed: \(message). Check protocol compatibility.")
        case .limitExceeded(let message):
            return .contactAdministrator(reason: "A protocol resource limit was exceeded: \(message). The peer may be misbehaving or hostile.")
        case .queryFailed(let status):
            return .noRecovery(reason: "Query failed with status: \(status)")
        case .retrieveFailed(let status):
            return .noRecovery(reason: "Retrieve failed with status: \(status)")
        case .artimTimerExpired:
            return .retryWithBackoff(initialDelay: 5.0)
        case .circuitBreakerOpen(_, _, let retryAfter):
            let waitTime = max(1.0, retryAfter.timeIntervalSinceNow)
            return .waitAndRetry(duration: waitTime)
        case .operationTimeout(let type, let duration, _):
            switch type {
            case .connect:
                return .checkConfiguration(details: "Connection timeout (\(Int(duration))s). Check host/port or increase connect timeout.")
            case .read, .write:
                return .retryWithBackoff(initialDelay: 2.0)
            case .operation:
                return .checkConfiguration(details: "Operation timeout (\(Int(duration))s). Consider increasing operation timeout for large transfers.")
            case .association:
                return .retryWithBackoff(initialDelay: 5.0)
            }
        case .storeFailed(let status):
            return .noRecovery(reason: "Store failed with status: \(status)")
        case .partialFailure(_, let failed, _):
            if failed > 0 {
                return .retry
            }
            return .noRecovery(reason: "Partial operation completed with failures")
        case .printOperationFailed(let status, let detail):
            if let detail = detail, !detail.isEmpty {
                return .noRecovery(reason: "Print operation failed with status: \(DIMSEServiceStatusText.describePrintStatus(status)) — \(detail)")
            }
            return .noRecovery(reason: "Print operation failed with status: \(DIMSEServiceStatusText.describePrintStatus(status))")
        case .mppsOperationFailed(let operation, let status, let errorComment, let errorID):
            return .noRecovery(reason: "MPPS \(operation) failed with status: "
                + Self.mppsFailureText(operation: operation, status: status, errorComment: errorComment, errorID: errorID))
        case .unexpectedResponse:
            return .checkConfiguration(details: "Verify server compatibility and presentation context negotiation")
        }
    }
    
    /// Human-readable explanation of the error
    ///
    /// Provides a detailed, user-friendly explanation of what went wrong.
    public var explanation: String {
        switch self {
        case .connectionFailed(let message):
            return "Failed to establish a connection to the remote DICOM server. \(message)"
        case .timeout:
            return "The operation timed out waiting for a response from the remote server."
        case .invalidPDU(let message):
            return "Received an invalid Protocol Data Unit from the remote server. \(message)"
        case .pduTooLarge(let received, let maximum):
            return "The remote server sent a PDU (\(received) bytes) larger than the maximum allowed size (\(maximum) bytes)."
        case .unexpectedPDUType(let expected, let received):
            return "Expected \(expected) but received \(received). The remote server may be in an unexpected state."
        case .associationRejected(let result, let source, let reason):
            return "The remote server (\(source)) rejected the association request. Result: \(result), Reason code: \(reason)."
        case .associationAborted(let source, let reason):
            return "The association was aborted by \(source). Reason code: \(reason)."
        case .noPresentationContextAccepted:
            return "The remote server did not accept any of the proposed presentation contexts (SOP classes or transfer syntaxes)."
        case .sopClassNotSupported(let uid):
            return "The SOP Class (\(uid)) is not supported by the remote DICOM server."
        case .invalidAETitle(let ae):
            return "The Application Entity title '\(ae)' is not valid. AE titles must be 1-16 ASCII characters."
        case .connectionClosed:
            return "The network connection was closed unexpectedly by the remote server or due to a network issue."
        case .invalidState(let message):
            return "The operation cannot be performed in the current connection state. \(message)"
        case .encodingFailed(let message):
            return "Failed to encode the DICOM message for transmission. \(message)"
        case .decodingFailed(let message):
            return "Failed to decode the DICOM message received from the server. \(message)"
        case .limitExceeded(let message):
            return "The DICOM message declared a size beyond this implementation's limits. \(message)"
        case .queryFailed(let status):
            return "The query operation failed with DIMSE status: \(status)."
        case .retrieveFailed(let status):
            return "The retrieve operation failed with DIMSE status: \(status)."
        case .artimTimerExpired:
            return "The ARTIM (Association Request/Release Timer) expired. The remote server did not respond to the association request in time."
        case .circuitBreakerOpen(let host, let port, let retryAfter):
            let seconds = max(0, Int(retryAfter.timeIntervalSinceNow))
            return "The circuit breaker is open for \(host):\(port) due to repeated failures. Requests will be allowed again in \(seconds) seconds."
        case .operationTimeout(let type, let duration, let operation):
            var base = "\(type) timeout occurred after \(Int(duration)) seconds"
            if let op = operation {
                base += " during \(op)"
            }
            return base + "."
        case .storeFailed(let status):
            return "The store operation failed with DIMSE status: \(status)."
        case .partialFailure(let succeeded, let failed, let details):
            var base = "The operation partially completed: \(succeeded) items succeeded, \(failed) items failed"
            if let d = details {
                base += ". \(d)"
            }
            return base + "."
        case .printOperationFailed(let status, let detail):
            if let detail = detail, !detail.isEmpty {
                return "The print operation failed with DIMSE status: \(DIMSEServiceStatusText.describePrintStatus(status)). Printer reported: \(detail)."
            }
            return "The print operation failed with DIMSE status: \(DIMSEServiceStatusText.describePrintStatus(status))."
        case .mppsOperationFailed(let operation, let status, let errorComment, let errorID):
            return "The MPPS \(operation) request failed: "
                + Self.mppsFailureText(operation: operation, status: status, errorComment: errorComment, errorID: errorID) + "."
        case .unexpectedResponse:
            return "The server sent an unexpected response. Verify server compatibility and protocol version."
        }
    }
}

// MARK: - Association Reject Types

/// Result code for A-ASSOCIATE-RJ PDU
///
/// Reference: PS3.8 Section 9.3.4
public enum AssociateRejectResult: UInt8, Sendable, Hashable {
    /// Rejected permanent - no retry possible
    case rejectedPermanent = 1
    
    /// Rejected transient - retry may be possible
    case rejectedTransient = 2
}

extension AssociateRejectResult: CustomStringConvertible {
    public var description: String {
        switch self {
        case .rejectedPermanent:
            return "Rejected (Permanent)"
        case .rejectedTransient:
            return "Rejected (Transient)"
        }
    }
}

/// Source of A-ASSOCIATE-RJ PDU
///
/// Reference: PS3.8 Section 9.3.4
public enum AssociateRejectSource: UInt8, Sendable, Hashable {
    /// DICOM UL service-user
    case serviceUser = 1
    
    /// DICOM UL service-provider (ACSE related function)
    case serviceProviderACSE = 2
    
    /// DICOM UL service-provider (Presentation related function)
    case serviceProviderPresentation = 3
}

extension AssociateRejectSource: CustomStringConvertible {
    public var description: String {
        switch self {
        case .serviceUser:
            return "Service User"
        case .serviceProviderACSE:
            return "Service Provider (ACSE)"
        case .serviceProviderPresentation:
            return "Service Provider (Presentation)"
        }
    }
}

// MARK: - Abort Types

/// Source of A-ABORT PDU
///
/// Reference: PS3.8 Section 9.3.8
public enum AbortSource: UInt8, Sendable, Hashable {
    /// DICOM UL service-user initiated abort
    case serviceUser = 0
    
    /// DICOM UL service-provider initiated abort
    case serviceProvider = 2
}

extension AbortSource: CustomStringConvertible {
    public var description: String {
        switch self {
        case .serviceUser:
            return "Service User"
        case .serviceProvider:
            return "Service Provider"
        }
    }
}

/// Reason for service-provider initiated abort
///
/// Reference: PS3.8 Section 9.3.8
public enum AbortReason: UInt8, Sendable, Hashable {
    /// Reason not specified
    case notSpecified = 0
    
    /// Unrecognized PDU
    case unrecognizedPDU = 1
    
    /// Unexpected PDU
    case unexpectedPDU = 2
    
    /// Reserved
    case reserved = 3
    
    /// Unrecognized PDU parameter
    case unrecognizedPDUParameter = 4
    
    /// Unexpected PDU parameter
    case unexpectedPDUParameter = 5
    
    /// Invalid PDU parameter value
    case invalidPDUParameterValue = 6
}

extension AbortReason: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notSpecified:
            return "Reason not specified"
        case .unrecognizedPDU:
            return "Unrecognized PDU"
        case .unexpectedPDU:
            return "Unexpected PDU"
        case .reserved:
            return "Reserved"
        case .unrecognizedPDUParameter:
            return "Unrecognized PDU parameter"
        case .unexpectedPDUParameter:
            return "Unexpected PDU parameter"
        case .invalidPDUParameterValue:
            return "Invalid PDU parameter value"
        }
    }
}

// MARK: - Error Level

/// Level at which a DICOM network error occurred
///
/// Distinguishes between errors that occur during association management
/// (connection, negotiation, release) versus errors that occur during
/// individual file/operation processing within an established association.
///
/// ## Usage
///
/// ```swift
/// do {
///     try await client.storeBatch(files: files)
/// } catch let error as DICOMNetworkError {
///     switch error.level {
///     case .association:
///         // Connection-level error - may need to wait and reconnect
///         print("Association error: \(error)")
///     case .operation:
///         // File-level error - other files may still succeed
///         print("Operation error: \(error)")
///     }
/// }
/// ```
///
/// Reference: PS3.8 - Network Communication Support
public enum ErrorLevel: String, Sendable, Hashable, CaseIterable {
    /// Error occurred at the association level
    ///
    /// These errors affect the entire connection and typically require
    /// re-establishing the association. Examples include:
    /// - Connection failures
    /// - Association rejection
    /// - Association abort
    /// - Presentation context negotiation failures
    /// - ARTIM timer expiration
    case association
    
    /// Error occurred at the operation level
    ///
    /// These errors affect individual operations (like C-STORE, C-FIND)
    /// but the association may still be usable for other operations.
    /// Examples include:
    /// - Individual C-STORE failures
    /// - Query failures
    /// - Retrieve failures
    /// - DIMSE status errors
    case operation
}

extension ErrorLevel: CustomStringConvertible {
    public var description: String {
        switch self {
        case .association:
            return "Association"
        case .operation:
            return "Operation"
        }
    }
}

// MARK: - Error Level Extension

extension DICOMNetworkError {
    /// The level at which this error occurred
    ///
    /// Helps determine whether the error affects the entire association
    /// or just the current operation. Association-level errors typically
    /// require reconnection, while operation-level errors may allow
    /// continuing with other operations on the same association.
    ///
    /// ## Example
    ///
    /// ```swift
    /// do {
    ///     try await client.store(fileData: data)
    /// } catch let error as DICOMNetworkError {
    ///     if error.level == .association {
    ///         // Need to reconnect
    ///         try await client.reconnect()
    ///     } else {
    ///         // Can retry this specific operation
    ///         // or continue with other operations
    ///     }
    /// }
    /// ```
    public var level: ErrorLevel {
        switch self {
        case .connectionFailed,
             .timeout,
             .associationRejected,
             .associationAborted,
             .noPresentationContextAccepted,
             .invalidAETitle,
             .connectionClosed,
             .artimTimerExpired,
             .circuitBreakerOpen:
            return .association
            
        case .invalidPDU,
             .pduTooLarge,
             .unexpectedPDUType,
             .sopClassNotSupported,
             .invalidState,
             .encodingFailed,
             .decodingFailed,
             .limitExceeded,
             .queryFailed,
             .retrieveFailed,
             .storeFailed,
             .partialFailure,
             .printOperationFailed,
             .mppsOperationFailed,
             .unexpectedResponse:
            return .operation
            
        case .operationTimeout(let type, _, _):
            // Connection and association timeouts are association-level
            // Read/write/operation timeouts are typically operation-level
            switch type {
            case .connect, .association:
                return .association
            case .read, .write, .operation:
                return .operation
            }
        }
    }
    
    /// Whether the error requires reconnection to recover
    ///
    /// Returns `true` if the association is no longer usable and a new
    /// connection must be established to continue operations.
    public var requiresReconnection: Bool {
        level == .association && isRetryable
    }
    
    /// Whether the error allows continuing with other operations
    ///
    /// Returns `true` if the current association is still usable and
    /// other operations can be attempted without reconnecting.
    public var allowsContinuation: Bool {
        level == .operation
    }
}

// MARK: - Storage Error

/// Enhanced error type for DICOM storage operations
///
/// Provides additional context about storage operation failures,
/// including the error level, affected file information, and
/// whether the operation can be retried.
///
/// ## Usage
///
/// ```swift
/// do {
///     try await client.store(fileData: data)
/// } catch let error as StorageError {
///     print("Error level: \(error.level)")
///     print("Affected file: \(error.sopInstanceUID ?? "unknown")")
///     print("Can retry: \(error.canRetry)")
///     print("Needs reconnection: \(error.needsReconnection)")
/// }
/// ```
public struct StorageError: Error, Sendable {
    /// The underlying error
    public let underlyingError: Error
    
    /// The level at which the error occurred
    public let level: ErrorLevel
    
    /// The SOP Instance UID of the affected file (if applicable)
    public let sopInstanceUID: String?
    
    /// The SOP Class UID of the affected file (if applicable)
    public let sopClassUID: String?
    
    /// The index of the file in a batch operation (if applicable)
    public let fileIndex: Int?
    
    /// The host where the error occurred
    public let host: String?
    
    /// The port where the error occurred
    public let port: UInt16?
    
    /// Timestamp when the error occurred
    public let timestamp: Date
    
    /// Additional context information
    public let context: String?
    
    /// Whether this error can be retried
    public var canRetry: Bool {
        if let networkError = underlyingError as? DICOMNetworkError {
            return networkError.isRetryable
        }
        return false
    }
    
    /// Whether reconnection is needed before retrying
    public var needsReconnection: Bool {
        if let networkError = underlyingError as? DICOMNetworkError {
            return networkError.requiresReconnection
        }
        return level == .association
    }
    
    /// The error category (if the underlying error is a DICOMNetworkError)
    public var category: ErrorCategory? {
        (underlyingError as? DICOMNetworkError)?.category
    }
    
    /// Recovery suggestion object (if the underlying error is a DICOMNetworkError)
    public var suggestion: RecoverySuggestion? {
        (underlyingError as? DICOMNetworkError)?.recoverySuggestion
    }
    
    /// Creates a storage error for an association-level failure
    ///
    /// - Parameters:
    ///   - error: The underlying error
    ///   - host: The remote host
    ///   - port: The remote port
    ///   - context: Additional context information
    public static func associationError(
        _ error: Error,
        host: String? = nil,
        port: UInt16? = nil,
        context: String? = nil
    ) -> StorageError {
        StorageError(
            underlyingError: error,
            level: .association,
            sopInstanceUID: nil,
            sopClassUID: nil,
            fileIndex: nil,
            host: host,
            port: port,
            timestamp: Date(),
            context: context
        )
    }
    
    /// Creates a storage error for a file-level failure
    ///
    /// - Parameters:
    ///   - error: The underlying error
    ///   - sopInstanceUID: The SOP Instance UID of the affected file
    ///   - sopClassUID: The SOP Class UID of the affected file
    ///   - fileIndex: The index of the file in a batch operation
    ///   - host: The remote host
    ///   - port: The remote port
    ///   - context: Additional context information
    public static func fileError(
        _ error: Error,
        sopInstanceUID: String? = nil,
        sopClassUID: String? = nil,
        fileIndex: Int? = nil,
        host: String? = nil,
        port: UInt16? = nil,
        context: String? = nil
    ) -> StorageError {
        StorageError(
            underlyingError: error,
            level: .operation,
            sopInstanceUID: sopInstanceUID,
            sopClassUID: sopClassUID,
            fileIndex: fileIndex,
            host: host,
            port: port,
            timestamp: Date(),
            context: context
        )
    }
    
    /// Creates a storage error with automatic level detection
    ///
    /// - Parameters:
    ///   - error: The underlying error
    ///   - sopInstanceUID: The SOP Instance UID (if applicable)
    ///   - sopClassUID: The SOP Class UID (if applicable)
    ///   - fileIndex: The file index (if applicable)
    ///   - host: The remote host
    ///   - port: The remote port
    ///   - context: Additional context information
    public init(
        _ error: Error,
        sopInstanceUID: String? = nil,
        sopClassUID: String? = nil,
        fileIndex: Int? = nil,
        host: String? = nil,
        port: UInt16? = nil,
        context: String? = nil
    ) {
        // Auto-detect level from DICOMNetworkError
        let detectedLevel: ErrorLevel
        if let networkError = error as? DICOMNetworkError {
            detectedLevel = networkError.level
        } else {
            // Default to operation level for unknown errors
            detectedLevel = .operation
        }
        
        self.underlyingError = error
        self.level = detectedLevel
        self.sopInstanceUID = sopInstanceUID
        self.sopClassUID = sopClassUID
        self.fileIndex = fileIndex
        self.host = host
        self.port = port
        self.timestamp = Date()
        self.context = context
    }
    
    /// Internal initializer with explicit level
    private init(
        underlyingError: Error,
        level: ErrorLevel,
        sopInstanceUID: String?,
        sopClassUID: String?,
        fileIndex: Int?,
        host: String?,
        port: UInt16?,
        timestamp: Date,
        context: String?
    ) {
        self.underlyingError = underlyingError
        self.level = level
        self.sopInstanceUID = sopInstanceUID
        self.sopClassUID = sopClassUID
        self.fileIndex = fileIndex
        self.host = host
        self.port = port
        self.timestamp = timestamp
        self.context = context
    }
}

extension StorageError: CustomStringConvertible {
    public var description: String {
        var parts: [String] = ["StorageError(\(level))"]
        
        if let sopUID = sopInstanceUID {
            parts.append("sop=\(sopUID)")
        }
        
        if let idx = fileIndex {
            parts.append("index=\(idx)")
        }
        
        if let h = host, let p = port {
            parts.append("server=\(h):\(p)")
        }
        
        parts.append("error=\(underlyingError)")
        
        if let ctx = context {
            parts.append("context=\(ctx)")
        }
        
        return parts.joined(separator: ", ")
    }
}

extension StorageError: LocalizedError {
    public var errorDescription: String? {
        var desc = "Storage \(level) error"
        
        if let sopUID = sopInstanceUID {
            desc += " for instance \(sopUID)"
        }
        
        if let idx = fileIndex {
            desc += " (file \(idx))"
        }
        
        desc += ": \(underlyingError.localizedDescription)"
        
        return desc
    }
    
    public var failureReason: String? {
        if let networkError = underlyingError as? DICOMNetworkError {
            return networkError.explanation
        }
        return (underlyingError as? LocalizedError)?.failureReason
    }
    
    public var recoverySuggestion: String? {
        if let sug = self.suggestion {
            return sug.description
        }
        return (underlyingError as? LocalizedError)?.recoverySuggestion
    }
}

// MARK: - Reconnection Configuration

/// Configuration for automatic reconnection behavior
///
/// Defines how the system should handle reconnection attempts after
/// transient connection failures.
///
/// ## Usage
///
/// ```swift
/// // Default configuration
/// let config = ReconnectionConfiguration.default
///
/// // Aggressive reconnection for critical operations
/// let aggressiveConfig = ReconnectionConfiguration(
///     enabled: true,
///     maxAttempts: 5,
///     initialDelay: 0.5,
///     maxDelay: 30.0,
///     backoffMultiplier: 2.0
/// )
///
/// // Disabled reconnection
/// let noReconnect = ReconnectionConfiguration.disabled
/// ```
public struct ReconnectionConfiguration: Sendable, Hashable {
    /// Whether automatic reconnection is enabled
    public let enabled: Bool
    
    /// Maximum number of reconnection attempts
    public let maxAttempts: Int
    
    /// Initial delay before first reconnection attempt (in seconds)
    public let initialDelay: TimeInterval
    
    /// Maximum delay between reconnection attempts (in seconds)
    public let maxDelay: TimeInterval
    
    /// Multiplier for exponential backoff
    public let backoffMultiplier: Double
    
    /// Whether to use jitter in backoff delays
    public let useJitter: Bool
    
    /// Jitter range as a fraction of the delay (0.0 to 1.0)
    public let jitterRange: Double
    
    /// Creates a reconnection configuration
    ///
    /// - Parameters:
    ///   - enabled: Whether reconnection is enabled (default: true)
    ///   - maxAttempts: Maximum reconnection attempts (default: 3)
    ///   - initialDelay: Initial delay in seconds (default: 1.0)
    ///   - maxDelay: Maximum delay in seconds (default: 30.0)
    ///   - backoffMultiplier: Backoff multiplier (default: 2.0)
    ///   - useJitter: Use jitter in delays (default: true)
    ///   - jitterRange: Jitter range (default: 0.25)
    public init(
        enabled: Bool = true,
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 30.0,
        backoffMultiplier: Double = 2.0,
        useJitter: Bool = true,
        jitterRange: Double = 0.25
    ) {
        self.enabled = enabled
        self.maxAttempts = max(0, maxAttempts)
        self.initialDelay = max(0.1, initialDelay)
        self.maxDelay = max(initialDelay, maxDelay)
        self.backoffMultiplier = max(1.0, backoffMultiplier)
        self.useJitter = useJitter
        self.jitterRange = min(1.0, max(0.0, jitterRange))
    }
    
    /// Default reconnection configuration
    ///
    /// - enabled: true
    /// - maxAttempts: 3
    /// - initialDelay: 1.0 seconds
    /// - maxDelay: 30.0 seconds
    /// - backoffMultiplier: 2.0
    /// - useJitter: true
    public static let `default` = ReconnectionConfiguration()
    
    /// Disabled reconnection
    public static let disabled = ReconnectionConfiguration(enabled: false, maxAttempts: 0)
    
    /// Aggressive reconnection for critical operations
    ///
    /// - enabled: true
    /// - maxAttempts: 5
    /// - initialDelay: 0.5 seconds
    /// - maxDelay: 60.0 seconds
    /// - backoffMultiplier: 2.0
    public static let aggressive = ReconnectionConfiguration(
        enabled: true,
        maxAttempts: 5,
        initialDelay: 0.5,
        maxDelay: 60.0,
        backoffMultiplier: 2.0
    )
    
    /// Conservative reconnection
    ///
    /// - enabled: true
    /// - maxAttempts: 2
    /// - initialDelay: 2.0 seconds
    /// - maxDelay: 15.0 seconds
    /// - backoffMultiplier: 1.5
    public static let conservative = ReconnectionConfiguration(
        enabled: true,
        maxAttempts: 2,
        initialDelay: 2.0,
        maxDelay: 15.0,
        backoffMultiplier: 1.5
    )
    
    /// Calculates the delay for a given reconnection attempt
    ///
    /// - Parameter attempt: The attempt number (0-based)
    /// - Returns: The delay in seconds before the next attempt
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        let baseDelay = initialDelay * pow(backoffMultiplier, Double(attempt))
        let cappedDelay = min(baseDelay, maxDelay)
        
        if useJitter {
            let jitter = Double.random(in: -jitterRange...jitterRange)
            return cappedDelay * (1.0 + jitter)
        }
        
        return cappedDelay
    }
}

extension ReconnectionConfiguration: CustomStringConvertible {
    public var description: String {
        if !enabled {
            return "ReconnectionConfiguration(disabled)"
        }
        return "ReconnectionConfiguration(maxAttempts: \(maxAttempts), initialDelay: \(initialDelay)s, maxDelay: \(maxDelay)s)"
    }
}

// MARK: - Reconnection State

/// State of a reconnection attempt
///
/// Provides information about the current reconnection progress,
/// useful for logging, monitoring, and UI feedback.
public struct ReconnectionState: Sendable {
    /// The current attempt number (1-based)
    public let attemptNumber: Int
    
    /// Maximum number of attempts allowed
    public let maxAttempts: Int
    
    /// The delay before this attempt (in seconds)
    public let delayBeforeAttempt: TimeInterval
    
    /// The error that triggered reconnection
    public let triggeringError: Error?
    
    /// Total time elapsed since first reconnection attempt
    public let elapsedTime: TimeInterval
    
    /// Whether there are more attempts available
    public var hasMoreAttempts: Bool {
        attemptNumber < maxAttempts
    }
    
    /// Fraction of attempts used (0.0 to 1.0)
    public var fractionUsed: Double {
        guard maxAttempts > 0 else { return 1.0 }
        return Double(attemptNumber) / Double(maxAttempts)
    }
    
    /// Creates a reconnection state
    public init(
        attemptNumber: Int,
        maxAttempts: Int,
        delayBeforeAttempt: TimeInterval = 0,
        triggeringError: Error? = nil,
        elapsedTime: TimeInterval = 0
    ) {
        self.attemptNumber = attemptNumber
        self.maxAttempts = maxAttempts
        self.delayBeforeAttempt = delayBeforeAttempt
        self.triggeringError = triggeringError
        self.elapsedTime = elapsedTime
    }
}

extension ReconnectionState: CustomStringConvertible {
    public var description: String {
        var parts = ["ReconnectionState(attempt \(attemptNumber)/\(maxAttempts)"]
        if delayBeforeAttempt > 0 {
            parts.append(String(format: "delay: %.2fs", delayBeforeAttempt))
        }
        if elapsedTime > 0 {
            parts.append(String(format: "elapsed: %.2fs", elapsedTime))
        }
        parts.append(")")
        return parts.joined(separator: ", ")
    }
}

// MARK: - Reconnectable Operation

/// Executes operations with automatic reconnection on transient failures
///
/// `ReconnectableOperation` wraps network operations and automatically
/// handles reconnection when association-level errors occur. This is
/// particularly useful for long-running operations like batch storage
/// where connection drops can occur.
///
/// ## Usage
///
/// ```swift
/// let reconnectable = ReconnectableOperation(
///     configuration: .default,
///     connect: {
///         // Establish connection
///         return try await establishAssociation()
///     }
/// )
///
/// // Execute with automatic reconnection
/// let result = try await reconnectable.execute { connection in
///     try await connection.store(fileData: data)
/// }
///
/// // Execute with reconnection progress callback
/// let result = try await reconnectable.execute(
///     onReconnecting: { state in
///         print("Reconnecting: attempt \(state.attemptNumber)/\(state.maxAttempts)")
///     }
/// ) { connection in
///     try await connection.store(fileData: data)
/// }
/// ```
public actor ReconnectableOperation<Connection: Sendable> {
    
    // MARK: - Properties
    
    /// Reconnection configuration
    public let configuration: ReconnectionConfiguration
    
    /// The connection factory
    private let connect: @Sendable () async throws -> Connection
    
    /// Current connection (if established)
    private var connection: Connection?
    
    /// Whether the operation has been cancelled
    private var isCancelled: Bool = false
    
    // MARK: - Initialization
    
    /// Creates a reconnectable operation
    ///
    /// - Parameters:
    ///   - configuration: Reconnection configuration
    ///   - connect: Factory function to establish a connection
    public init(
        configuration: ReconnectionConfiguration = .default,
        connect: @escaping @Sendable () async throws -> Connection
    ) {
        self.configuration = configuration
        self.connect = connect
    }
    
    // MARK: - Execution
    
    /// Executes an operation with automatic reconnection
    ///
    /// - Parameters:
    ///   - onReconnecting: Optional callback invoked before each reconnection attempt
    ///   - operation: The operation to execute
    /// - Returns: The result of the successful operation
    /// - Throws: The last error if all reconnection attempts fail
    public func execute<T: Sendable>(
        onReconnecting: (@Sendable (ReconnectionState) async -> Void)? = nil,
        operation: @Sendable (Connection) async throws -> T
    ) async throws -> T {
        // Establish initial connection if needed
        if connection == nil {
            connection = try await connect()
        }
        
        guard let conn = connection else {
            throw DICOMNetworkError.connectionFailed("No connection available")
        }
        
        do {
            // Try the operation
            return try await operation(conn)
        } catch {
            // Check if we should reconnect
            guard configuration.enabled,
                  let networkError = error as? DICOMNetworkError,
                  networkError.requiresReconnection else {
                throw error
            }
            
            // Reconnect and retry
            return try await reconnectAndRetry(
                error: error,
                onReconnecting: onReconnecting,
                operation: operation
            )
        }
    }
    
    /// Cancels any pending reconnection attempts
    public func cancel() {
        isCancelled = true
    }
    
    /// Resets the cancellation flag
    public func reset() {
        isCancelled = false
    }
    
    /// Closes the current connection
    public func close() {
        connection = nil
    }
    
    // MARK: - Private
    
    private func reconnectAndRetry<T: Sendable>(
        error: Error,
        onReconnecting: (@Sendable (ReconnectionState) async -> Void)?,
        operation: @Sendable (Connection) async throws -> T
    ) async throws -> T {
        let startTime = Date()
        var lastError = error
        
        for attempt in 0..<configuration.maxAttempts {
            // Check cancellation
            if isCancelled {
                throw ReconnectionError.cancelled
            }
            
            // Calculate delay
            let delay = configuration.delay(forAttempt: attempt)
            let elapsedTime = Date().timeIntervalSince(startTime)
            
            // Notify about reconnection
            let state = ReconnectionState(
                attemptNumber: attempt + 1,
                maxAttempts: configuration.maxAttempts,
                delayBeforeAttempt: delay,
                triggeringError: lastError,
                elapsedTime: elapsedTime
            )
            await onReconnecting?(state)
            
            // Wait before reconnecting
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            // Check cancellation again
            if isCancelled {
                throw ReconnectionError.cancelled
            }
            
            do {
                // Re-establish connection
                connection = try await connect()
                
                guard let conn = connection else {
                    throw DICOMNetworkError.connectionFailed("Failed to establish connection")
                }
                
                // Retry the operation
                return try await operation(conn)
                
            } catch let newError {
                lastError = newError
                
                // If it's not a reconnectable error, throw immediately
                if let networkError = newError as? DICOMNetworkError,
                   !networkError.requiresReconnection {
                    throw newError
                }
                
                // Continue to next attempt
            }
        }
        
        // All attempts exhausted
        let elapsedTime = Date().timeIntervalSince(startTime)
        throw ReconnectionError.exhausted(
            attempts: configuration.maxAttempts,
            totalTime: elapsedTime,
            lastError: lastError
        )
    }
}

// MARK: - Reconnection Error

/// Errors specific to reconnection operations
public enum ReconnectionError: Error, Sendable {
    /// All reconnection attempts were exhausted
    ///
    /// - Parameters:
    ///   - attempts: Number of attempts made
    ///   - totalTime: Total time spent on reconnection
    ///   - lastError: The last error encountered
    case exhausted(attempts: Int, totalTime: TimeInterval, lastError: Error)
    
    /// Reconnection was cancelled
    case cancelled
}

extension ReconnectionError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .exhausted(let attempts, let totalTime, let lastError):
            return "Reconnection exhausted after \(attempts) attempt(s) over \(String(format: "%.1f", totalTime))s. Last error: \(lastError)"
        case .cancelled:
            return "Reconnection was cancelled"
        }
    }
}

extension ReconnectionError: LocalizedError {
    public var errorDescription: String? {
        description
    }
}
