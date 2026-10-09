import Foundation
import DICOMCore

// MARK: - Storage Commitment SOP Class UIDs

/// Storage Commitment Push Model SOP Class UID
///
/// Used for Storage Commitment requests via N-ACTION and N-EVENT-REPORT.
///
/// Reference: PS3.4 Annex J - Storage Commitment Service Class
public let storageCommitmentPushModelSOPClassUID = "1.2.840.10008.1.20.1"

/// Storage Commitment Push Model SOP Instance UID (Well-Known)
///
/// The well-known SOP Instance UID for the Storage Commitment Push Model.
///
/// Reference: PS3.4 Annex J.3
public let storageCommitmentPushModelSOPInstanceUID = "1.2.840.10008.1.20.1.1"

// MARK: - Storage Commitment Action/Event Type IDs

/// Action Type ID for Storage Commitment Request
///
/// Used in N-ACTION-RQ to request storage commitment.
/// Value: 1 (Request Storage Commitment)
///
/// Reference: PS3.4 Table J.3-1
public let storageCommitmentRequestActionTypeID: UInt16 = 1

/// Event Type ID for Storage Commitment Result - Success
///
/// Used in N-EVENT-REPORT-RQ when all instances are committed.
/// Value: 1 (Storage Commitment Request Successful)
///
/// Reference: PS3.4 Table J.3-2
public let storageCommitmentSuccessEventTypeID: UInt16 = 1

/// Event Type ID for Storage Commitment Result - Failure
///
/// Used in N-EVENT-REPORT-RQ when some instances failed commitment.
/// Value: 2 (Storage Commitment Request Complete - Failures Exist)
///
/// Reference: PS3.4 Table J.3-2
public let storageCommitmentFailureEventTypeID: UInt16 = 2

// MARK: - Storage Commitment Failure Reasons

/// Failure Reason (0008,1197) values for the Failed SOP Sequence of a
/// Storage Commitment N-EVENT-REPORT.
///
/// Reference: PS3.4 Table J.3-3
public enum StorageCommitmentFailureReason {
    /// Processing failure (0110H): a general failure in processing the operation
    public static let processingFailure: UInt16 = 0x0110
    /// No such object instance (0112H): one or more of the elements in the
    /// Referenced SOP Instance UID were not available
    public static let noSuchObjectInstance: UInt16 = 0x0112
    /// Resource limitation (0213H): the SCP does not currently have enough
    /// resources to store the requested SOP Instance(s)
    public static let resourceLimitation: UInt16 = 0x0213
    /// Referenced SOP Class not supported (0122H)
    public static let referencedSOPClassNotSupported: UInt16 = 0x0122
    /// Class/Instance conflict (0119H): the SOP Class of an element in the
    /// Referenced SOP Instance UID did not correspond to the SOP Class registered
    /// for this SOP Instance UID at the SCP
    public static let classInstanceConflict: UInt16 = 0x0119
    /// Duplicate transaction UID (0131H): the Transaction UID of the Storage
    /// Commitment Request is already in use
    public static let duplicateTransactionUID: UInt16 = 0x0131
}

// MARK: - SOP Reference

/// A reference to a stored SOP Instance
///
/// Represents a single DICOM object by its SOP Class and Instance UIDs.
/// Used in Storage Commitment requests to identify instances to commit.
///
/// Reference: PS3.4 Table J.3-1
public struct SOPReference: Sendable, Hashable {
    /// The SOP Class UID of the referenced instance
    public let sopClassUID: String
    
    /// The SOP Instance UID of the referenced instance
    public let sopInstanceUID: String
    
    /// Creates a SOP reference
    ///
    /// - Parameters:
    ///   - sopClassUID: The SOP Class UID
    ///   - sopInstanceUID: The SOP Instance UID
    public init(sopClassUID: String, sopInstanceUID: String) {
        self.sopClassUID = sopClassUID
        self.sopInstanceUID = sopInstanceUID
    }
}

extension SOPReference: CustomStringConvertible {
    public var description: String {
        "SOPReference(class: \(sopClassUID), instance: \(sopInstanceUID))"
    }
}

// MARK: - Failed SOP Reference

/// A SOP reference with failure information
///
/// Represents a SOP Instance that failed storage commitment, including
/// the reason for failure.
///
/// Reference: PS3.4 Table J.3-2
public struct FailedSOPReference: Sendable, Hashable {
    /// The SOP reference that failed
    public let reference: SOPReference
    
    /// The failure reason code
    ///
    /// Common failure reasons:
    /// - 0x0110: Processing failure
    /// - 0x0112: No such object instance
    /// - 0x0213: Resource limitation
    /// - 0x0122: Referenced SOP Class not supported
    ///
    /// Reference: PS3.4 Table J.3-2
    public let failureReason: UInt16
    
    /// Creates a failed SOP reference
    ///
    /// - Parameters:
    ///   - reference: The SOP reference that failed
    ///   - failureReason: The failure reason code
    public init(reference: SOPReference, failureReason: UInt16) {
        self.reference = reference
        self.failureReason = failureReason
    }
    
    /// Human-readable failure reason description
    public var failureReasonDescription: String {
        switch failureReason {
        case 0x0110:
            return "Processing failure"
        case 0x0112:
            return "No such object instance"
        case 0x0213:
            return "Resource limitation"
        case 0x0122:
            return "Referenced SOP Class not supported"
        case 0x0119:
            return "Class/Instance conflict"
        case 0x0131:
            return "Duplicate transaction UID"
        default:
            return "Unknown failure reason (0x\(String(format: "%04X", failureReason)))"
        }
    }
}

extension FailedSOPReference: CustomStringConvertible {
    public var description: String {
        "FailedSOPReference(\(reference), reason: \(failureReasonDescription))"
    }
}

// MARK: - Commitment Request

/// A Storage Commitment request
///
/// Represents an outstanding request for storage commitment.
/// Contains the transaction UID and the instances being committed.
///
/// Reference: PS3.4 Annex J.3
public struct CommitmentRequest: Sendable, Hashable {
    /// The unique Transaction UID for this commitment request
    ///
    /// Generated by the SCU and used to correlate requests with results.
    public let transactionUID: String
    
    /// The SOP references being committed
    public let references: [SOPReference]
    
    /// The timestamp when the request was created
    public let timestamp: Date
    
    /// The remote AE title that received the request
    public let remoteAETitle: String

    /// The commitment result, if the SCP delivered it on the same association
    /// the request was sent on (PS3.4 J.3.3)
    ///
    /// When nil, the result will arrive on a separate association opened by the
    /// SCP; use `StorageCommitmentService.waitForCommitment(request:timeout:listener:)`.
    public let result: CommitmentResult?

    /// Creates a commitment request
    ///
    /// - Parameters:
    ///   - transactionUID: The transaction UID
    ///   - references: The SOP references to commit
    ///   - timestamp: The timestamp (default: now)
    ///   - remoteAETitle: The remote AE title
    ///   - result: The result if it was received on the same association (default: nil)
    public init(
        transactionUID: String,
        references: [SOPReference],
        timestamp: Date = Date(),
        remoteAETitle: String,
        result: CommitmentResult? = nil
    ) {
        self.transactionUID = transactionUID
        self.references = references
        self.timestamp = timestamp
        self.remoteAETitle = remoteAETitle
        self.result = result
    }
}

extension CommitmentRequest: CustomStringConvertible {
    public var description: String {
        "CommitmentRequest(txn: \(transactionUID), count: \(references.count), ae: \(remoteAETitle))"
    }
}

// MARK: - Commitment Result

/// The result of a Storage Commitment request
///
/// Contains information about which instances were successfully committed
/// and which failed, along with the transaction UID for correlation.
///
/// Reference: PS3.4 Annex J.3
public struct CommitmentResult: Sendable, Hashable {
    /// The Transaction UID that correlates this result with a request
    public let transactionUID: String
    
    /// The SOP references that were successfully committed
    public let committedReferences: [SOPReference]
    
    /// The SOP references that failed commitment
    public let failedReferences: [FailedSOPReference]
    
    /// The timestamp when the result was received
    public let timestamp: Date
    
    /// The remote AE title that sent the result
    public let remoteAETitle: String
    
    /// Whether all instances were successfully committed
    public var isSuccess: Bool {
        failedReferences.isEmpty
    }
    
    /// Whether the commitment was partially successful (some instances committed)
    public var isPartialSuccess: Bool {
        !committedReferences.isEmpty && !failedReferences.isEmpty
    }
    
    /// Whether all instances failed commitment
    public var isFailure: Bool {
        committedReferences.isEmpty && !failedReferences.isEmpty
    }
    
    /// The total number of instances in the result
    public var totalCount: Int {
        committedReferences.count + failedReferences.count
    }
    
    /// Creates a commitment result
    ///
    /// - Parameters:
    ///   - transactionUID: The transaction UID
    ///   - committedReferences: Successfully committed references
    ///   - failedReferences: Failed references with reasons
    ///   - timestamp: The timestamp (default: now)
    ///   - remoteAETitle: The remote AE title
    public init(
        transactionUID: String,
        committedReferences: [SOPReference],
        failedReferences: [FailedSOPReference],
        timestamp: Date = Date(),
        remoteAETitle: String
    ) {
        self.transactionUID = transactionUID
        self.committedReferences = committedReferences
        self.failedReferences = failedReferences
        self.timestamp = timestamp
        self.remoteAETitle = remoteAETitle
    }
}

extension CommitmentResult: CustomStringConvertible {
    public var description: String {
        let status = isSuccess ? "SUCCESS" : (isPartialSuccess ? "PARTIAL" : "FAILED")
        return "CommitmentResult(\(status), txn: \(transactionUID), committed: \(committedReferences.count), failed: \(failedReferences.count))"
    }
}

// MARK: - Storage Commitment Configuration

/// Configuration for the Storage Commitment Service
public struct StorageCommitmentConfiguration: Sendable, Hashable {
    /// The local Application Entity title (calling AE)
    public let callingAETitle: AETitle
    
    /// The remote Application Entity title (called AE)
    public let calledAETitle: AETitle
    
    /// Connection timeout in seconds
    public let timeout: TimeInterval
    
    /// Maximum PDU size to propose
    public let maxPDUSize: UInt32
    
    /// Implementation Class UID for this DICOM implementation
    public let implementationClassUID: String
    
    /// Implementation Version Name (optional)
    public let implementationVersionName: String?
    
    /// User identity for authentication (optional)
    public let userIdentity: UserIdentity?
    
    /// Retry policy for commitment requests
    ///
    /// Configures how commitment requests should be retried on transient failures.
    /// Default is `RetryPolicy.default` which provides exponential backoff with jitter.
    public let retryPolicy: RetryPolicy

    /// Whether to propose the SCP role for the Storage Commitment Push Model SOP
    /// Class so the SCP may deliver the N-EVENT-REPORT on the same association
    /// (PS3.4 J.3.3, PS3.7 D.3.3.4). Default: true.
    public let allowSameAssociationEventReport: Bool

    /// How long to keep the association open waiting for a same-association
    /// N-EVENT-REPORT after the N-ACTION-RSP, in seconds (default: 30).
    ///
    /// Only used when the SCP granted the SCP role. When it expires the request
    /// falls back to the `CommitmentNotificationListener` path.
    public let sameAssociationEventReportTimeout: TimeInterval

    /// Default Implementation Class UID for DICOMKit
    public static let defaultImplementationClassUID = DICOMNetworkImplementation.classUID

    /// Default Implementation Version Name for DICOMKit
    public static let defaultImplementationVersionName = "DICOMKIT_001"

    /// Creates a storage commitment configuration
    ///
    /// - Parameters:
    ///   - callingAETitle: The local AE title
    ///   - calledAETitle: The remote AE title
    ///   - timeout: Connection timeout in seconds (default: 60)
    ///   - maxPDUSize: Maximum PDU size (default: 64 KB (`defaultMaxPDUSize`))
    ///   - implementationClassUID: Implementation Class UID
    ///   - implementationVersionName: Implementation Version Name
    ///   - userIdentity: User identity for authentication (optional)
    ///   - retryPolicy: Retry policy for commitment requests (default: .default)
    ///   - allowSameAssociationEventReport: Propose the SCP role so the result may
    ///     be delivered on the same association (default: true)
    ///   - sameAssociationEventReportTimeout: Seconds to wait for a same-association
    ///     N-EVENT-REPORT (default: 30)
    public init(
        callingAETitle: AETitle,
        calledAETitle: AETitle,
        timeout: TimeInterval = 60,
        maxPDUSize: UInt32 = defaultMaxPDUSize,
        implementationClassUID: String = defaultImplementationClassUID,
        implementationVersionName: String? = defaultImplementationVersionName,
        userIdentity: UserIdentity? = nil,
        retryPolicy: RetryPolicy = .default,
        allowSameAssociationEventReport: Bool = true,
        sameAssociationEventReportTimeout: TimeInterval = 30
    ) {
        self.callingAETitle = callingAETitle
        self.calledAETitle = calledAETitle
        self.timeout = timeout
        self.maxPDUSize = maxPDUSize
        self.implementationClassUID = implementationClassUID
        self.implementationVersionName = implementationVersionName
        self.userIdentity = userIdentity
        self.retryPolicy = retryPolicy
        self.allowSameAssociationEventReport = allowSameAssociationEventReport
        self.sameAssociationEventReportTimeout = sameAssociationEventReportTimeout
    }
}

// MARK: - Commitment Notification Listener Configuration

/// Configuration for the Commitment Notification Listener
///
/// Defines the settings for receiving N-EVENT-REPORT notifications for storage commitment.
///
/// Reference: PS3.4 Annex J - Storage Commitment Service Class
public struct CommitmentNotificationListenerConfiguration: Sendable, Hashable {
    /// The local Application Entity title
    public let aeTitle: AETitle
    
    /// The port to listen on for incoming N-EVENT-REPORT
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
    
    /// Default Implementation Class UID for DICOMKit Commitment Listener
    public static let defaultImplementationClassUID = DICOMNetworkImplementation.classUID
    
    /// Default Implementation Version Name for DICOMKit Commitment Listener
    public static let defaultImplementationVersionName = "DICOMKIT_CMTLSN"
    
    /// Creates a commitment notification listener configuration
    ///
    /// - Parameters:
    ///   - aeTitle: The local AE title
    ///   - port: The port to listen on (default: 11113)
    ///   - maxPDUSize: Maximum PDU size (default: 64 KB (`defaultMaxPDUSize`))
    ///   - implementationClassUID: Implementation Class UID
    ///   - implementationVersionName: Implementation Version Name
    ///   - maxConcurrentAssociations: Maximum concurrent associations (default: 5)
    ///   - callingAEWhitelist: Whitelist of calling AE titles
    public init(
        aeTitle: AETitle,
        port: UInt16 = 11113,
        maxPDUSize: UInt32 = defaultMaxPDUSize,
        implementationClassUID: String = defaultImplementationClassUID,
        implementationVersionName: String? = defaultImplementationVersionName,
        maxConcurrentAssociations: Int = 5,
        callingAEWhitelist: Set<String>? = nil
    ) {
        self.aeTitle = aeTitle
        self.port = port
        self.maxPDUSize = maxPDUSize
        self.implementationClassUID = implementationClassUID
        self.implementationVersionName = implementationVersionName
        self.maxConcurrentAssociations = max(1, maxConcurrentAssociations)
        self.callingAEWhitelist = callingAEWhitelist
    }
    
    /// Checks if a calling AE title is allowed
    ///
    /// - Parameter callingAE: The calling AE title to check
    /// - Returns: True if the calling AE is allowed
    public func isCallingAEAllowed(_ callingAE: String) -> Bool {
        if let whitelist = callingAEWhitelist {
            return whitelist.contains(callingAE)
        }
        return true
    }
}

// MARK: - Commitment Notification Listener Event

/// Events emitted by the Commitment Notification Listener
public enum CommitmentNotificationListenerEvent: Sendable {
    /// Listener started
    case started(port: UInt16)
    
    /// Listener stopped
    case stopped
    
    /// An association was established
    case associationEstablished(callingAE: String)
    
    /// An association was released
    case associationReleased(callingAE: String)
    
    /// An association was rejected
    case associationRejected(callingAE: String, reason: String)
    
    /// A commitment result was received
    case resultReceived(CommitmentResult)
    
    /// An error occurred
    case error(Error)
}

#if canImport(Network)

// MARK: - Storage Commitment Service

/// Service for requesting Storage Commitment from a DICOM SCP
///
/// The Storage Commitment Service provides functionality for:
/// - Requesting storage commitment for stored DICOM instances (N-ACTION)
/// - Processing commitment notifications (N-EVENT-REPORT)
/// - Tracking pending commitment requests
///
/// ## Example Usage
///
/// ```swift
/// let callingAE = try AETitle("MY_SCU")
/// let calledAE = try AETitle("PACS")
/// let config = StorageCommitmentConfiguration(
///     callingAETitle: callingAE,
///     calledAETitle: calledAE
/// )
///
/// // Request commitment for stored instances
/// let request = try await StorageCommitmentService.requestCommitment(
///     for: [
///         SOPReference(sopClassUID: ctImageStorageSOPClassUID, sopInstanceUID: "1.2.3.4.5")
///     ],
///     host: "pacs.example.com",
///     port: 104,
///     configuration: config
/// )
///
/// print("Commitment requested: \(request.transactionUID)")
/// ```
///
/// Reference: PS3.4 Annex J - Storage Commitment Service Class
public enum StorageCommitmentService {
    
    /// Requests storage commitment for the specified SOP instances
    ///
    /// Sends an N-ACTION-RQ to the remote SCP requesting commitment for
    /// the specified instances. The SCP will later send an N-EVENT-REPORT
    /// (potentially on a new association) with the commitment result.
    ///
    /// If configured with a retry policy, this method will automatically
    /// retry transient failures according to the policy parameters.
    ///
    /// - Parameters:
    ///   - references: The SOP references to commit
    ///   - host: The remote host address
    ///   - port: The remote port number (default: 104)
    ///   - configuration: The service configuration
    /// - Returns: A `CommitmentRequest` representing the pending commitment
    /// - Throws: `DICOMNetworkError` if the request fails after all retry attempts
    ///
    /// Reference: PS3.4 Section J.3.1 - N-ACTION Service
    public static func requestCommitment(
        for references: [SOPReference],
        host: String,
        port: UInt16 = dicomDefaultPort,
        configuration: StorageCommitmentConfiguration
    ) async throws -> CommitmentRequest {
        guard !references.isEmpty else {
            throw DICOMNetworkError.encodingFailed("At least one SOP reference is required")
        }
        
        // Create retry executor with configured policy
        let executor = RetryExecutor(policy: configuration.retryPolicy)
        
        // Execute with retry
        return try await executor.execute {
            try await performCommitmentRequest(
                references: references,
                host: host,
                port: port,
                configuration: configuration
            )
        }
    }
    
    /// Internal method that performs the actual commitment request
    ///
    /// This is separated from `requestCommitment` to allow retry wrapping.
    private static func performCommitmentRequest(
        references: [SOPReference],
        host: String,
        port: UInt16,
        configuration: StorageCommitmentConfiguration
    ) async throws -> CommitmentRequest {
        // Generate a unique Transaction UID
        let transactionUID = UIDGenerator.generateUID().value
        
        // Create association configuration
        let associationConfig = AssociationConfiguration(
            callingAETitle: configuration.callingAETitle,
            calledAETitle: configuration.calledAETitle,
            host: host,
            port: port,
            maxPDUSize: configuration.maxPDUSize,
            implementationClassUID: configuration.implementationClassUID,
            implementationVersionName: configuration.implementationVersionName,
            timeout: configuration.timeout,
            userIdentity: configuration.userIdentity
        )
        
        // Create association
        let association = Association(configuration: associationConfig)
        
        // Create presentation context for Storage Commitment
        let presentationContext = try PresentationContext(
            id: 1,
            abstractSyntax: storageCommitmentPushModelSOPClassUID,
            transferSyntaxes: [
                explicitVRLittleEndianTransferSyntaxUID,
                implicitVRLittleEndianTransferSyntaxUID
            ]
        )
        
        // Propose both roles for the commitment SOP Class: SCU to send the
        // N-ACTION, SCP to receive the N-EVENT-REPORT on this association
        // (PS3.4 J.3.3, PS3.7 D.3.3.4).
        let roleSelections: [SCPSCURoleSelection] = configuration.allowSameAssociationEventReport
            ? [.both(storageCommitmentPushModelSOPClassUID)]
            : []

        do {
            // Establish association
            let negotiated = try await association.request(
                presentationContexts: [presentationContext],
                roleSelections: roleSelections
            )

            // Verify that Storage Commitment was accepted
            guard negotiated.isContextAccepted(1) else {
                try await association.abort()
                throw DICOMNetworkError.sopClassNotSupported(storageCommitmentPushModelSOPClassUID)
            }

            let transferSyntaxUID = negotiated.acceptedTransferSyntax(forContextID: 1)
                ?? explicitVRLittleEndianTransferSyntaxUID
            let mayReceiveOnSameAssociation = negotiated.isSCPRoleAccepted(for: storageCommitmentPushModelSOPClassUID)

            // Perform the N-ACTION request
            let exchange = try await performNAction(
                association: association,
                presentationContextID: 1,
                maxPDUSize: negotiated.maxPDUSize,
                transferSyntaxUID: transferSyntaxUID,
                transactionUID: transactionUID,
                references: references,
                remoteAETitle: configuration.calledAETitle.value
            )

            // Check response status
            guard exchange.response.status.isSuccess else {
                try await association.abort()
                throw DICOMNetworkError.queryFailed(exchange.response.status)
            }

            // The SCP may deliver the result on this association only when it
            // granted us the SCP role; otherwise it will open its own association
            // to our notification listener.
            var result = exchange.earlyResult
            if result == nil && mayReceiveOnSameAssociation {
                result = try await awaitSameAssociationEventReport(
                    association: association,
                    maxPDUSize: negotiated.maxPDUSize,
                    transferSyntaxUID: transferSyntaxUID,
                    transactionUID: transactionUID,
                    remoteAETitle: configuration.calledAETitle.value,
                    timeout: configuration.sameAssociationEventReportTimeout
                )
            }

            // Release association gracefully (unless the wait already closed it)
            if association.state == .established {
                try await association.release()
            } else {
                try? await association.abort()
            }

            // Return the commitment request
            return CommitmentRequest(
                transactionUID: transactionUID,
                references: references,
                remoteAETitle: configuration.calledAETitle.value,
                result: result
            )

        } catch {
            // Attempt to abort on error
            try? await association.abort()
            throw error
        }
    }
    
    /// Waits for a commitment result for a previously requested commitment
    ///
    /// This method starts or uses an existing notification listener to wait for
    /// the N-EVENT-REPORT from the remote SCP containing the commitment result.
    /// The listener must be started before calling this method.
    ///
    /// - Parameters:
    ///   - request: The commitment request to wait for
    ///   - timeout: Maximum time to wait for the result
    ///   - listener: The notification listener to use for receiving results
    /// - Returns: The commitment result
    /// - Throws: `DICOMNetworkError.timeout` if the timeout expires before receiving a result
    ///
    /// ## Example Usage
    ///
    /// ```swift
    /// // Create and start the listener
    /// let listenerConfig = CommitmentNotificationListenerConfiguration(
    ///     aeTitle: try AETitle("MY_SCU"),
    ///     port: 11113
    /// )
    /// let listener = CommitmentNotificationListener(configuration: listenerConfig)
    /// try await listener.start()
    ///
    /// // Request commitment
    /// let request = try await StorageCommitmentService.requestCommitment(
    ///     for: references,
    ///     host: "pacs.example.com",
    ///     port: 104,
    ///     configuration: config
    /// )
    ///
    /// // Wait for the result
    /// let result = try await StorageCommitmentService.waitForCommitment(
    ///     request: request,
    ///     timeout: .seconds(300),
    ///     listener: listener
    /// )
    /// ```
    ///
    /// Reference: PS3.4 Section J.3.2 - N-EVENT-REPORT Service
    public static func waitForCommitment(
        request: CommitmentRequest,
        timeout: Duration,
        listener: CommitmentNotificationListener
    ) async throws -> CommitmentResult {
        // Already delivered on the N-ACTION association
        if let result = request.result {
            return result
        }
        return try await listener.waitForResult(transactionUID: request.transactionUID, timeout: timeout)
    }
    
    /// Parses a commitment result from an N-EVENT-REPORT data set
    ///
    /// This method parses the data set received in an N-EVENT-REPORT request
    /// to extract the commitment result information.
    ///
    /// - Parameters:
    ///   - eventTypeID: The event type ID (1 = success, 2 = failures exist)
    ///   - dataSet: The data set containing commitment results
    ///   - remoteAETitle: The AE title of the sender
    ///   - transferSyntaxUID: The negotiated transfer syntax the data set is encoded
    ///     in. When nil the VR encoding is detected heuristically.
    /// - Returns: The parsed commitment result
    /// - Throws: `DICOMNetworkError.decodingFailed` if parsing fails
    public static func parseCommitmentResult(
        eventTypeID: UInt16,
        dataSet: Data,
        remoteAETitle: String,
        transferSyntaxUID: String? = nil
    ) throws -> CommitmentResult {
        typealias Codec = StorageCommitmentDataSetCodec
        let explicit: Bool? = transferSyntaxUID.map { Codec.isExplicitVR(transferSyntaxUID: $0) }

        // Parse Transaction UID (0008,1195)
        guard let transactionUID = Codec.extractUIValue(
            from: dataSet, tag: Tag(group: 0x0008, element: 0x1195), explicit: explicit) else {
            throw DICOMNetworkError.decodingFailed("Missing Transaction UID in commitment result")
        }

        var committedReferences: [SOPReference] = []
        var failedReferences: [FailedSOPReference] = []

        // Parse Referenced SOP Sequence (0008,1199) - committed instances
        if let sequenceItems = Codec.extractSequenceItems(
            from: dataSet, tag: Tag(group: 0x0008, element: 0x1199), explicit: explicit) {
            for item in sequenceItems {
                if let sopClassUID = Codec.extractUIValue(from: item, tag: Tag(group: 0x0008, element: 0x1150), explicit: explicit),
                   let sopInstanceUID = Codec.extractUIValue(from: item, tag: Tag(group: 0x0008, element: 0x1155), explicit: explicit) {
                    committedReferences.append(SOPReference(
                        sopClassUID: sopClassUID,
                        sopInstanceUID: sopInstanceUID
                    ))
                }
            }
        }

        // Parse Failed SOP Sequence (0008,1198) - failed instances
        if let sequenceItems = Codec.extractSequenceItems(
            from: dataSet, tag: Tag(group: 0x0008, element: 0x1198), explicit: explicit) {
            for item in sequenceItems {
                if let sopClassUID = Codec.extractUIValue(from: item, tag: Tag(group: 0x0008, element: 0x1150), explicit: explicit),
                   let sopInstanceUID = Codec.extractUIValue(from: item, tag: Tag(group: 0x0008, element: 0x1155), explicit: explicit) {
                    let failureReason = Codec.extractUSValue(from: item, tag: Tag(group: 0x0008, element: 0x1197), explicit: explicit)
                        ?? StorageCommitmentFailureReason.processingFailure
                    failedReferences.append(FailedSOPReference(
                        reference: SOPReference(
                            sopClassUID: sopClassUID,
                            sopInstanceUID: sopInstanceUID
                        ),
                        failureReason: failureReason
                    ))
                }
            }
        }
        
        return CommitmentResult(
            transactionUID: transactionUID,
            committedReferences: committedReferences,
            failedReferences: failedReferences,
            remoteAETitle: remoteAETitle
        )
    }
    
    // MARK: - Private Helpers
    
    /// Builds the data set for a storage commitment request
    ///
    /// - Parameters:
    ///   - transactionUID: The Transaction UID (0008,1195)
    ///   - references: The Referenced SOP Sequence (0008,1199) items
    ///   - transferSyntaxUID: The negotiated transfer syntax of the presentation
    ///     context the data set will be sent on (PS3.8 7.6 / PS3.5 7.1)
    static func buildCommitmentRequestDataSet(
        transactionUID: String,
        references: [SOPReference],
        transferSyntaxUID: String = explicitVRLittleEndianTransferSyntaxUID
    ) -> Data {
        let explicit = StorageCommitmentDataSetCodec.isExplicitVR(transferSyntaxUID: transferSyntaxUID)
        var dataSet = Data()
        
        // Transaction UID (0008,1195) - UI
        dataSet.append(StorageCommitmentDataSetCodec.encodeUI(
            tag: Tag(group: 0x0008, element: 0x1195), value: transactionUID, explicit: explicit))
        
        // Referenced SOP Sequence (0008,1199) - SQ
        let items = references.map { reference -> Data in
            var itemData = Data()
            itemData.append(StorageCommitmentDataSetCodec.encodeUI(
                tag: Tag(group: 0x0008, element: 0x1150), value: reference.sopClassUID, explicit: explicit))
            itemData.append(StorageCommitmentDataSetCodec.encodeUI(
                tag: Tag(group: 0x0008, element: 0x1155), value: reference.sopInstanceUID, explicit: explicit))
            return itemData
        }
        dataSet.append(StorageCommitmentDataSetCodec.encodeSequence(
            tag: Tag(group: 0x0008, element: 0x1199), items: items, explicit: explicit))
        
        return dataSet
    }
    
    /// Builds the data set for a storage commitment result (N-EVENT-REPORT)
    ///
    /// Shared by the Storage Commitment SCP (same-association and reverse-association
    /// delivery) so the encoding always follows the negotiated transfer syntax.
    ///
    /// Reference: PS3.4 Table J.3-3
    static func buildCommitmentResultDataSet(
        _ result: CommitmentResult,
        transferSyntaxUID: String = explicitVRLittleEndianTransferSyntaxUID
    ) -> Data {
        let explicit = StorageCommitmentDataSetCodec.isExplicitVR(transferSyntaxUID: transferSyntaxUID)
        var data = Data()
        
        // Transaction UID (0008,1195)
        data.append(StorageCommitmentDataSetCodec.encodeUI(
            tag: Tag(group: 0x0008, element: 0x1195), value: result.transactionUID, explicit: explicit))
        
        // Referenced SOP Sequence (0008,1199) - committed references
        if !result.committedReferences.isEmpty {
            let items = result.committedReferences.map { ref -> Data in
                var itemData = Data()
                itemData.append(StorageCommitmentDataSetCodec.encodeUI(
                    tag: Tag(group: 0x0008, element: 0x1150), value: ref.sopClassUID, explicit: explicit))
                itemData.append(StorageCommitmentDataSetCodec.encodeUI(
                    tag: Tag(group: 0x0008, element: 0x1155), value: ref.sopInstanceUID, explicit: explicit))
                return itemData
            }
            data.append(StorageCommitmentDataSetCodec.encodeSequence(
                tag: Tag(group: 0x0008, element: 0x1199), items: items, explicit: explicit))
        }
        
        // Failed SOP Sequence (0008,1198) - failed references
        if !result.failedReferences.isEmpty {
            let items = result.failedReferences.map { failedRef -> Data in
                var itemData = Data()
                itemData.append(StorageCommitmentDataSetCodec.encodeUI(
                    tag: Tag(group: 0x0008, element: 0x1150), value: failedRef.reference.sopClassUID, explicit: explicit))
                itemData.append(StorageCommitmentDataSetCodec.encodeUI(
                    tag: Tag(group: 0x0008, element: 0x1155), value: failedRef.reference.sopInstanceUID, explicit: explicit))
                // Failure Reason (0008,1197)
                itemData.append(StorageCommitmentDataSetCodec.encodeUS(
                    tag: Tag(group: 0x0008, element: 0x1197), value: failedRef.failureReason, explicit: explicit))
                return itemData
            }
            data.append(StorageCommitmentDataSetCodec.encodeSequence(
                tag: Tag(group: 0x0008, element: 0x1198), items: items, explicit: explicit))
        }
        
        return data
    }
    
    /// Parses an N-EVENT-REPORT-RQ carrying a commitment result and answers it
    /// with an N-EVENT-REPORT-RSP on the given association.
    ///
    /// Used by the SCU when the SCP delivers the result on the same association
    /// it received the N-ACTION on (PS3.4 J.3.3). The response echoes the
    /// Affected SOP Class/Instance UIDs and the Event Type ID and carries the
    /// Message ID Being Responded To (PS3.7 10.1.1).
    ///
    /// - Returns: The parsed result, or nil if the data set could not be parsed
    ///   (a failure status is then sent to the SCP).
    static func answerSameAssociationEventReport(
        _ message: AssembledMessage,
        association: Association,
        maxPDUSize: UInt32,
        transferSyntaxUID: String,
        remoteAETitle: String
    ) async throws -> CommitmentResult? {
        let commandSet = message.commandSet
        let messageID = commandSet.messageID ?? 0
        let eventTypeID = commandSet.eventTypeID ?? storageCommitmentSuccessEventTypeID
        let affectedSOPClassUID = commandSet.affectedSOPClassUID ?? storageCommitmentPushModelSOPClassUID
        let affectedSOPInstanceUID = commandSet.affectedSOPInstanceUID ?? storageCommitmentPushModelSOPInstanceUID
        
        var result: CommitmentResult? = nil
        if let dataSet = message.dataSet {
            result = try? parseCommitmentResult(
                eventTypeID: eventTypeID,
                dataSet: dataSet,
                remoteAETitle: remoteAETitle,
                transferSyntaxUID: transferSyntaxUID
            )
        }
        
        let response = NEventReportResponse(
            messageIDBeingRespondedTo: messageID,
            affectedSOPClassUID: affectedSOPClassUID,
            affectedSOPInstanceUID: affectedSOPInstanceUID,
            eventTypeID: eventTypeID,
            status: result != nil ? .success : .failedUnableToProcess,
            hasDataSet: false,
            presentationContextID: message.presentationContextID
        )
        
        let fragmenter = MessageFragmenter(maxPDUSize: maxPDUSize)
        let pdus = fragmenter.fragmentMessage(
            commandSet: response.commandSet,
            dataSet: nil,
            presentationContextID: message.presentationContextID
        )
        for pdu in pdus {
            for pdv in pdu.presentationDataValues {
                try await association.send(pdv: pdv)
            }
        }
        
        return result
    }
    
    /// Outcome of the N-ACTION exchange
    struct NActionExchange {
        /// The N-ACTION-RSP
        let response: NActionResponse
        /// A commitment result that arrived on the same association before the
        /// N-ACTION-RSP (permitted by PS3.4 J.3.3)
        let earlyResult: CommitmentResult?
    }
    
    /// Performs the N-ACTION request/response exchange
    ///
    /// An N-EVENT-REPORT-RQ that arrives before the N-ACTION-RSP is answered and
    /// returned as `earlyResult`.
    static func performNAction(
        association: Association,
        presentationContextID: UInt8,
        maxPDUSize: UInt32,
        transferSyntaxUID: String,
        transactionUID: String,
        references: [SOPReference],
        remoteAETitle: String
    ) async throws -> NActionExchange {
        // Build the action data set in the negotiated transfer syntax
        let actionDataSet = buildCommitmentRequestDataSet(
            transactionUID: transactionUID,
            references: references,
            transferSyntaxUID: transferSyntaxUID
        )
        
        // Create N-ACTION request
        let request = NActionRequest(
            messageID: 1,
            requestedSOPClassUID: storageCommitmentPushModelSOPClassUID,
            requestedSOPInstanceUID: storageCommitmentPushModelSOPInstanceUID,
            actionTypeID: storageCommitmentRequestActionTypeID,
            hasDataSet: true,
            presentationContextID: presentationContextID
        )
        
        // Fragment and send the command and data
        let fragmenter = MessageFragmenter(maxPDUSize: maxPDUSize)
        let pdus = fragmenter.fragmentMessage(
            commandSet: request.commandSet,
            dataSet: actionDataSet,
            presentationContextID: presentationContextID
        )
        
        // Send all PDVs
        for pdu in pdus {
            for pdv in pdu.presentationDataValues {
                try await association.send(pdv: pdv)
            }
        }
        
        // Receive response
        let assembler = MessageAssembler()
        var earlyResult: CommitmentResult? = nil
        
        while true {
            let responsePDU = try await association.receive()
            
            guard let message = try assembler.addPDVs(from: responsePDU) else { continue }
            
            switch message.command {
            case .nActionResponse:
                return NActionExchange(
                    response: NActionResponse(commandSet: message.commandSet, presentationContextID: presentationContextID),
                    earlyResult: earlyResult
                )
            case .nEventReportRequest:
                // The SCP may report the result before answering the N-ACTION
                let result = try await answerSameAssociationEventReport(
                    message,
                    association: association,
                    maxPDUSize: maxPDUSize,
                    transferSyntaxUID: transferSyntaxUID,
                    remoteAETitle: remoteAETitle
                )
                if let result, result.transactionUID == transactionUID {
                    earlyResult = result
                }
            default:
                throw DICOMNetworkError.decodingFailed(
                    "Expected N-ACTION-RSP, got \(message.command?.description ?? "unknown")"
                )
            }
        }
    }
    
    /// Outcome of waiting for a same-association N-EVENT-REPORT
    private enum SameAssociationWaitOutcome {
        case received(CommitmentResult?)
        case timedOut
    }
    
    /// Waits for the N-EVENT-REPORT-RQ on the association the N-ACTION was sent on
    ///
    /// Only meaningful when the SCP granted the SCU the SCP role for the Storage
    /// Commitment Push Model SOP Class. On timeout the association is aborted
    /// (the pending read holds the socket, so a graceful release is not possible)
    /// and nil is returned so the caller can fall back to the notification listener.
    ///
    /// - Returns: The result, or nil if it did not arrive within `timeout`
    static func awaitSameAssociationEventReport(
        association: Association,
        maxPDUSize: UInt32,
        transferSyntaxUID: String,
        transactionUID: String,
        remoteAETitle: String,
        timeout: TimeInterval
    ) async throws -> CommitmentResult? {
        let assembler = MessageAssembler()
        
        return await withThrowingTaskGroup(of: SameAssociationWaitOutcome.self) { group in
            group.addTask {
                while true {
                    let pdu = try await association.receive()
                    guard let message = try assembler.addPDVs(from: pdu) else { continue }
                    guard message.command == .nEventReportRequest else { continue }
                    
                    let result = try await answerSameAssociationEventReport(
                        message,
                        association: association,
                        maxPDUSize: maxPDUSize,
                        transferSyntaxUID: transferSyntaxUID,
                        remoteAETitle: remoteAETitle
                    )
                    if let result, result.transactionUID != transactionUID {
                        continue // A result for another transaction; keep waiting
                    }
                    return .received(result)
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                return .timedOut
            }
            
            let outcome: SameAssociationWaitOutcome
            do {
                outcome = try await group.next() ?? .timedOut
            } catch {
                // The read failed (peer released or aborted, or the connection dropped)
                group.cancelAll()
                while let _ = try? await group.next() {}
                return nil
            }
            
            switch outcome {
            case .received(let result):
                group.cancelAll()
                while let _ = try? await group.next() {}
                return result
            case .timedOut:
                // Unblock the pending read by aborting; the listener path takes over.
                try? await association.abort()
                group.cancelAll()
                while let _ = try? await group.next() {}
                return nil
            }
        }
    }
}

// MARK: - Storage Commitment Data Set Codec

/// Minimal DICOM data set encoder/decoder for the Storage Commitment data sets
///
/// Encodes and decodes the handful of elements used by N-ACTION (request) and
/// N-EVENT-REPORT (result) data sets in either Implicit VR Little Endian or
/// Explicit VR Little Endian, as negotiated for the presentation context.
///
/// Reference: PS3.5 Section 7.1 - Data Element Structure
/// Reference: PS3.8 Section 7.6 - Transfer syntax of the data set
enum StorageCommitmentDataSetCodec {
    
    /// Whether a transfer syntax uses explicit VR encoding
    ///
    /// Implicit VR Little Endian is the only implicit VR transfer syntax; every
    /// other transfer syntax the service negotiates is Explicit VR Little Endian.
    static func isExplicitVR(transferSyntaxUID: String) -> Bool {
        transferSyntaxUID != implicitVRLittleEndianTransferSyntaxUID
    }
    
    // MARK: Encoding
    
    /// Encodes a UI element
    static func encodeUI(tag: Tag, value: String, explicit: Bool) -> Data {
        var valueData = value.data(using: .ascii) ?? Data()
        if valueData.count % 2 != 0 {
            valueData.append(0x00) // UI pads with NULL
        }
        return encodeElement(tag: tag, vr: .UI, value: valueData, explicit: explicit)
    }
    
    /// Encodes a US element
    static func encodeUS(tag: Tag, value: UInt16, explicit: Bool) -> Data {
        encodeElement(tag: tag, vr: .US, value: le16(value), explicit: explicit)
    }
    
    /// Encodes an element with a defined length
    static func encodeElement(tag: Tag, vr: VR, value: Data, explicit: Bool) -> Data {
        var data = encodeTag(tag)
        if explicit {
            data.append(vr.rawValue.data(using: .ascii) ?? Data([0x55, 0x4E]))
            if vr.uses32BitLength {
                data.append(contentsOf: [0x00, 0x00]) // reserved
                data.append(le32(UInt32(value.count)))
            } else {
                data.append(le16(UInt16(value.count)))
            }
        } else {
            data.append(le32(UInt32(value.count)))
        }
        data.append(value)
        return data
    }
    
    /// Encodes a sequence with undefined length; each item has an explicit
    /// length and the sequence ends with a Sequence Delimitation Item.
    static func encodeSequence(tag: Tag, items: [Data], explicit: Bool) -> Data {
        var data = encodeTag(tag)
        if explicit {
            data.append(contentsOf: [0x53, 0x51]) // "SQ"
            data.append(contentsOf: [0x00, 0x00]) // reserved
        }
        data.append(le32(0xFFFFFFFF)) // undefined length
        for item in items {
            data.append(encodeSequenceItem(item))
        }
        data.append(encodeSequenceDelimiter())
        return data
    }
    
    /// Encodes a sequence item (FFFE,E000) with an explicit length
    static func encodeSequenceItem(_ itemData: Data) -> Data {
        var data = Data([0xFE, 0xFF, 0x00, 0xE0])
        data.append(le32(UInt32(itemData.count)))
        data.append(itemData)
        return data
    }
    
    /// Encodes a Sequence Delimitation Item (FFFE,E0DD)
    static func encodeSequenceDelimiter() -> Data {
        Data([0xFE, 0xFF, 0xDD, 0xE0, 0x00, 0x00, 0x00, 0x00])
    }
    
    private static func encodeTag(_ tag: Tag) -> Data {
        var data = le16(tag.group)
        data.append(le16(tag.element))
        return data
    }
    
    private static func le16(_ v: UInt16) -> Data {
        Data([UInt8(v & 0xFF), UInt8(v >> 8)])
    }
    
    private static func le32(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF),
              UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)])
    }
    
    // MARK: Decoding
    
    /// A decoded element header
    struct ElementHeader {
        let group: UInt16
        let element: UInt16
        /// Value length; 0xFFFFFFFF for undefined length
        let length: Int
        /// Offset of the first value byte
        let valueOffset: Int
        
        var isUndefinedLength: Bool { length == 0xFFFFFFFF }
    }
    
    /// Reads the element header at `offset`
    ///
    /// - Parameter explicit: true for Explicit VR, false for Implicit VR, nil to
    ///   detect the encoding from the two bytes following the tag (the legacy
    ///   behaviour used when the transfer syntax is unknown).
    static func readHeader(from data: Data, at offset: Int, explicit: Bool?) -> ElementHeader? {
        guard offset + 8 <= data.count else { return nil }
        let group = readUInt16(data, offset)
        let element = readUInt16(data, offset + 2)
        
        // Item / delimiter tags never carry a VR (PS3.5 7.5)
        if group == 0xFFFE {
            return ElementHeader(group: group, element: element,
                                 length: Int(readUInt32(data, offset + 4)), valueOffset: offset + 8)
        }
        
        let hasVR: Bool
        if let explicit {
            hasVR = explicit
        } else {
            hasVR = looksLikeVR(data[offset + 4], data[offset + 5])
        }
        
        guard hasVR else {
            return ElementHeader(group: group, element: element,
                                 length: Int(readUInt32(data, offset + 4)), valueOffset: offset + 8)
        }
        
        let vrString = String(bytes: [data[offset + 4], data[offset + 5]], encoding: .ascii) ?? ""
        let vr = VR(rawValue: vrString)
        if vr?.uses32BitLength ?? false {
            // 2 byte VR + 2 reserved + 4 byte length
            guard offset + 12 <= data.count else { return nil }
            return ElementHeader(group: group, element: element,
                                 length: Int(readUInt32(data, offset + 8)), valueOffset: offset + 12)
        }
        // 2 byte VR + 2 byte length
        return ElementHeader(group: group, element: element,
                             length: Int(readUInt16(data, offset + 6)), valueOffset: offset + 8)
    }
    
    /// Extracts the value bytes of the first top-level element with the given tag
    static func extractValue(from data: Data, tag: Tag, explicit: Bool?) -> Data? {
        var offset = 0
        while let header = readHeader(from: data, at: offset, explicit: explicit) {
            if header.group == tag.group && header.element == tag.element {
                guard !header.isUndefinedLength,
                      header.valueOffset + header.length <= data.count else { return nil }
                return data.subdata(in: header.valueOffset..<(header.valueOffset + header.length))
            }
            offset = endOfElement(header, in: data, explicit: explicit)
        }
        return nil
    }
    
    /// Extracts a UI value (trailing NULL/space padding removed)
    static func extractUIValue(from data: Data, tag: Tag, explicit: Bool? = nil) -> String? {
        guard let value = extractValue(from: data, tag: tag, explicit: explicit), !value.isEmpty else {
            return nil
        }
        return String(data: value, encoding: .ascii)?
            .trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
    }
    
    /// Extracts a US value
    static func extractUSValue(from data: Data, tag: Tag, explicit: Bool? = nil) -> UInt16? {
        guard let value = extractValue(from: data, tag: tag, explicit: explicit), value.count >= 2 else {
            return nil
        }
        return readUInt16(value, value.startIndex)
    }
    
    /// Extracts the items of the first top-level sequence with the given tag
    ///
    /// Handles both defined and undefined sequence lengths and both defined and
    /// undefined item lengths.
    static func extractSequenceItems(from data: Data, tag: Tag, explicit: Bool? = nil) -> [Data]? {
        var offset = 0
        while let header = readHeader(from: data, at: offset, explicit: explicit) {
            if header.group == tag.group && header.element == tag.element {
                var items: [Data] = []
                var cursor = header.valueOffset
                let sequenceEnd = header.isUndefinedLength
                    ? data.count
                    : min(data.count, header.valueOffset + header.length)
                
                while cursor + 8 <= sequenceEnd {
                    let itemGroup = readUInt16(data, cursor)
                    let itemElement = readUInt16(data, cursor + 2)
                    guard itemGroup == 0xFFFE else { break }
                    if itemElement == 0xE0DD { break } // Sequence Delimitation Item
                    guard itemElement == 0xE000 else { break }
                    
                    let itemLength = Int(readUInt32(data, cursor + 4))
                    let itemStart = cursor + 8
                    if itemLength == 0xFFFFFFFF {
                        let itemEnd = endOfUndefinedLengthItem(in: data, from: itemStart, explicit: explicit)
                        let contentEnd = max(itemStart, itemEnd - 8)
                        items.append(data.subdata(in: itemStart..<contentEnd))
                        cursor = itemEnd
                    } else if itemStart + itemLength <= data.count {
                        items.append(data.subdata(in: itemStart..<(itemStart + itemLength)))
                        cursor = itemStart + itemLength
                    } else {
                        break
                    }
                }
                return items.isEmpty ? nil : items
            }
            offset = endOfElement(header, in: data, explicit: explicit)
        }
        return nil
    }
    
    // MARK: Walking helpers
    
    /// Offset just past an element (skipping undefined-length sequences properly)
    private static func endOfElement(_ header: ElementHeader, in data: Data, explicit: Bool?) -> Int {
        if header.isUndefinedLength {
            return endOfUndefinedLengthSequence(in: data, from: header.valueOffset, explicit: explicit)
        }
        return header.valueOffset + header.length
    }
    
    /// Offset just past the Sequence Delimitation Item of an undefined-length sequence
    private static func endOfUndefinedLengthSequence(in data: Data, from start: Int, explicit: Bool?) -> Int {
        var cursor = start
        while cursor + 8 <= data.count {
            let group = readUInt16(data, cursor)
            let element = readUInt16(data, cursor + 2)
            let length = Int(readUInt32(data, cursor + 4))
            guard group == 0xFFFE else { return data.count }
            if element == 0xE0DD { return cursor + 8 }
            guard element == 0xE000 else { return data.count }
            if length == 0xFFFFFFFF {
                cursor = endOfUndefinedLengthItem(in: data, from: cursor + 8, explicit: explicit)
            } else {
                cursor += 8 + length
            }
        }
        return data.count
    }
    
    /// Offset just past the Item Delimitation Item of an undefined-length item
    private static func endOfUndefinedLengthItem(in data: Data, from start: Int, explicit: Bool?) -> Int {
        var cursor = start
        while let header = readHeader(from: data, at: cursor, explicit: explicit) {
            if header.group == 0xFFFE && header.element == 0xE00D {
                return header.valueOffset
            }
            cursor = endOfElement(header, in: data, explicit: explicit)
        }
        return data.count
    }
    
    private static func looksLikeVR(_ b0: UInt8, _ b1: UInt8) -> Bool {
        guard (0x41...0x5A).contains(b0), (0x41...0x5A).contains(b1) else { return false }
        let vrString = String(bytes: [b0, b1], encoding: .ascii) ?? ""
        return VR(rawValue: vrString) != nil
    }
    
    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }
    
    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) |
        (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }
}

import Network
// NEMA-verified: 2026a, checked 2026-09-28 — Push Model UIDs per PS3.4 2026a J.3.4/J.3.5, action/event information per Tables J.3-1/J.3-2, failure reasons per PS3.3 C.14.1.1 (Scripts/diff_network.py: 6 of 6); listener answers every N-EVENT-REPORT-RQ (J.3.3.1.3); PDU length per PS3.8 §9.3.1 (D13)

// MARK: - Commitment Notification Listener

/// Listener for receiving N-EVENT-REPORT notifications for storage commitment
///
/// The Commitment Notification Listener starts a DICOM SCP that listens for incoming
/// N-EVENT-REPORT messages containing storage commitment results from remote SCPs.
///
/// ## Example Usage
///
/// ```swift
/// let config = CommitmentNotificationListenerConfiguration(
///     aeTitle: try AETitle("MY_SCU"),
///     port: 11113
/// )
/// let listener = CommitmentNotificationListener(configuration: config)
///
/// // Start listening
/// try await listener.start()
///
/// // Wait for a specific commitment result
/// let result = try await listener.waitForResult(
///     transactionUID: request.transactionUID,
///     timeout: .seconds(300)
/// )
///
/// // Stop when done
/// await listener.stop()
/// ```
///
/// Reference: PS3.4 Section J.3.2 - N-EVENT-REPORT Service
public actor CommitmentNotificationListener {
    
    /// Listener configuration
    public let configuration: CommitmentNotificationListenerConfiguration
    
    /// The network listener
    private var listener: NWListener?
    
    /// Active associations
    private var activeAssociations: [ObjectIdentifier: CommitmentListenerAssociation] = [:]
    
    /// Pending commitment waiters (transaction UID -> continuation)
    private var pendingWaiters: [String: CheckedContinuation<CommitmentResult, Error>] = [:]
    
    /// Received results that haven't been waited for yet
    private var pendingResults: [String: CommitmentResult] = [:]
    
    /// Event stream continuation
    private var eventContinuation: AsyncStream<CommitmentNotificationListenerEvent>.Continuation?
    
    /// Whether the listener is running
    public private(set) var isRunning: Bool = false
    
    /// Creates a Commitment Notification Listener
    ///
    /// - Parameter configuration: The listener configuration
    public init(configuration: CommitmentNotificationListenerConfiguration) {
        self.configuration = configuration
    }
    
    /// Event stream for monitoring listener activity
    public var events: AsyncStream<CommitmentNotificationListenerEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                Task { await self.handleStreamTermination() }
            }
        }
    }
    
    /// Starts the listener
    ///
    /// - Throws: `DICOMNetworkError.connectionFailed` if listener fails to start
    public func start() async throws {
        guard !isRunning else {
            throw DICOMNetworkError.invalidState("Listener is already running")
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
    
    /// Stops the listener
    public func stop() async {
        guard isRunning else { return }
        
        if let listener = listener {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if case .cancelled = listener.state {
                    // Already cancelled — no further state callbacks will fire.
                    continuation.resume()
                    return
                }
                listener.stateUpdateHandler = { state in
                    if case .cancelled = state {
                        listener.stateUpdateHandler = nil
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
        
        // Cancel all pending waiters
        for (_, continuation) in pendingWaiters {
            continuation.resume(throwing: DICOMNetworkError.connectionClosed)
        }
        pendingWaiters.removeAll()
        pendingResults.removeAll()
        
        isRunning = false
        eventContinuation?.yield(.stopped)
        eventContinuation?.finish()
    }
    
    /// Number of active associations
    public var activeAssociationCount: Int {
        activeAssociations.count
    }
    
    /// Waits for a commitment result with the specified transaction UID
    ///
    /// - Parameters:
    ///   - transactionUID: The transaction UID to wait for
    ///   - timeout: Maximum time to wait
    /// - Returns: The commitment result
    /// - Throws: `DICOMNetworkError.timeout` if the timeout expires
    public func waitForResult(transactionUID: String, timeout: Duration) async throws -> CommitmentResult {
        // Check if result is already available
        if let result = pendingResults.removeValue(forKey: transactionUID) {
            return result
        }

        // The continuation is registered synchronously while still on the
        // actor, so it is guaranteed to be in `pendingWaiters` before either
        // the timeout task or an incoming result can try to resume it.
        // Exactly one of receiveResult / timeoutWaiter / stop resumes it.
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            await self?.timeoutWaiter(transactionUID: transactionUID)
        }
        defer { timeoutTask.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            pendingWaiters[transactionUID] = continuation
        }
    }

    // MARK: - Internal Methods

    /// Fails a pending waiter with `.timeout` if it is still waiting
    private func timeoutWaiter(transactionUID: String) {
        if let continuation = pendingWaiters.removeValue(forKey: transactionUID) {
            continuation.resume(throwing: DICOMNetworkError.timeout)
        }
    }
    
    /// Called when a commitment result is received
    func receiveResult(_ result: CommitmentResult) {
        eventContinuation?.yield(.resultReceived(result))
        
        // Check if someone is waiting for this result
        if let continuation = pendingWaiters.removeValue(forKey: result.transactionUID) {
            continuation.resume(returning: result)
        } else {
            // Store for later retrieval
            pendingResults[result.transactionUID] = result
        }
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
        
        // Create a new association handler
        let association = CommitmentListenerAssociation(
            connection: connection,
            configuration: configuration,
            eventHandler: { [weak self] event in
                await self?.handleAssociationEvent(event)
            },
            resultHandler: { [weak self] result in
                await self?.receiveResult(result)
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
    
    private func handleAssociationEvent(_ event: CommitmentNotificationListenerEvent) {
        eventContinuation?.yield(event)
    }
    
    nonisolated func removeAssociation(_ association: CommitmentListenerAssociation) {
        Task {
            await removeAssociationAsync(association)
        }
    }
    
    private func removeAssociationAsync(_ association: CommitmentListenerAssociation) {
        let id = ObjectIdentifier(association)
        activeAssociations.removeValue(forKey: id)
    }
}

// MARK: - Commitment Listener Association

/// Handles a single association for the Commitment Notification Listener
actor CommitmentListenerAssociation {
    private let connection: NWConnection
    private let configuration: CommitmentNotificationListenerConfiguration
    private let eventHandler: @Sendable (CommitmentNotificationListenerEvent) async -> Void
    private let resultHandler: @Sendable (CommitmentResult) async -> Void
    private let completionHandler: @Sendable (CommitmentListenerAssociation) async -> Void
    
    private var callingAETitle: String = ""
    private var calledAETitle: String = ""
    private var maxPDUSize: UInt32 = defaultMaxPDUSize
    private var acceptedContexts: [UInt8: String] = [:]
    private var messageAssembler = MessageAssembler()
    private var isReleasing = false
    private var currentMessageID: UInt16 = 1
    
    init(
        connection: NWConnection,
        configuration: CommitmentNotificationListenerConfiguration,
        eventHandler: @escaping @Sendable (CommitmentNotificationListenerEvent) async -> Void,
        resultHandler: @escaping @Sendable (CommitmentResult) async -> Void,
        completionHandler: @escaping @Sendable (CommitmentListenerAssociation) async -> Void
    ) {
        self.connection = connection
        self.configuration = configuration
        self.eventHandler = eventHandler
        self.resultHandler = resultHandler
        self.completionHandler = completionHandler
    }
    
    func start() async {
        connection.start(queue: .global(qos: .userInitiated))
        
        // Wait for connection to be ready. Guard the resume so a terminal
        // transition right after `.ready` cannot resume the continuation twice
        // (a trap that surfaced once the loopback tests got past association
        // establishment, see D13).
        let resumed = ListenerResumeFlag()
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
        
        // Handle the association
        do {
            try await handleAssociation()
        } catch {
            await eventHandler(.error(error))
        }
        
        await completionHandler(self)
    }
    
    func abort() async {
        connection.cancel()
    }
    
    // MARK: - Association Handling
    
    private func handleAssociation() async throws {
        // Receive and process A-ASSOCIATE-RQ
        let requestPDU = try await receivePDU()
        
        guard let associateRequest = requestPDU as? AssociateRequestPDU else {
            // Unexpected PDU type - abort
            let abortPDU = AbortPDU(source: .serviceProvider, reason: AbortReason.unexpectedPDU.rawValue)
            try await sendPDU(abortPDU)
            return
        }
        
        callingAETitle = associateRequest.callingAETitle.value
        calledAETitle = associateRequest.calledAETitle.value
        // PS3.8 Annex D.1: 0 from the peer means "no maximum length is specified"
        maxPDUSize = negotiatedMaxPDUSize(local: configuration.maxPDUSize, remote: associateRequest.maxPDUSize)
        
        // PS3.8 Table 9-11: only bit 0 of Protocol-version is tested; reject
        // with source 2 (ACSE), reason 2 (protocol-version-not-supported)
        guard associateRequest.isProtocolVersionSupported else {
            await eventHandler(.associationRejected(callingAE: callingAETitle, reason: "Protocol version not supported"))
            let rejectPDU = AssociateRejectPDU(
                result: .rejectedPermanent,
                source: .serviceProviderACSE,
                reason: 2 // Protocol version not supported
            )
            try await sendPDU(rejectPDU)
            return
        }
        
        // Check if calling AE is allowed
        if !configuration.isCallingAEAllowed(callingAETitle) {
            await eventHandler(.associationRejected(callingAE: callingAETitle, reason: "AE not allowed"))
            let rejectPDU = AssociateRejectPDU(
                result: .rejectedPermanent,
                source: .serviceUser,
                reason: 3 // PS3.8 Table 9-21: calling-AE-title-not-recognized
            )
            try await sendPDU(rejectPDU)
            return
        }
        
        // Accept the association with Storage Commitment support
        let acceptedContexts = processAssociationRequest(associateRequest)
        
        if acceptedContexts.isEmpty {
            await eventHandler(.associationRejected(callingAE: callingAETitle, reason: "No supported presentation contexts"))
            // PS3.8 Table 9-21: "no presentation context acceptable" is not a
            // UL-provider condition, so reject as service-user, reason 1
            // (no-reason-given).
            let rejectPDU = AssociateRejectPDU(
                result: .rejectedPermanent,
                source: .serviceUser,
                reason: 1 // No reason given
            )
            try await sendPDU(rejectPDU)
            return
        }
        
        self.acceptedContexts = acceptedContexts
        
        // Build and send A-ASSOCIATE-AC
        let acceptPDU = buildAssociateAcceptPDU(request: associateRequest, acceptedContexts: acceptedContexts)
        try await sendPDU(acceptPDU)
        
        await eventHandler(.associationEstablished(callingAE: callingAETitle))
        
        // Process messages until release or abort
        while !isReleasing {
            let pdu = try await receivePDU()
            
            switch pdu {
            case _ as ReleaseRequestPDU:
                // Send release response
                let releasePDU = ReleaseResponsePDU()
                try await sendPDU(releasePDU)
                isReleasing = true
                await eventHandler(.associationReleased(callingAE: callingAETitle))
                
            case _ as AbortPDU:
                isReleasing = true
                await eventHandler(.associationReleased(callingAE: callingAETitle))
                
            case let dataPDU as DataTransferPDU:
                try await processDataPDU(dataPDU)
                
            default:
                break
            }
        }
    }
    
    private func processAssociationRequest(_ request: AssociateRequestPDU) -> [UInt8: String] {
        var accepted: [UInt8: String] = [:]
        
        for context in request.presentationContexts {
            // Only accept Storage Commitment Push Model
            if context.abstractSyntax == storageCommitmentPushModelSOPClassUID {
                // Accept with first supported transfer syntax
                for transferSyntax in context.transferSyntaxes {
                    if transferSyntax == explicitVRLittleEndianTransferSyntaxUID ||
                       transferSyntax == implicitVRLittleEndianTransferSyntaxUID {
                        accepted[context.id] = transferSyntax
                        break
                    }
                }
            }
        }
        
        return accepted
    }
    
    private func buildAssociateAcceptPDU(
        request: AssociateRequestPDU,
        acceptedContexts: [UInt8: String]
    ) -> AssociateAcceptPDU {
        var acceptedPresentationContexts: [AcceptedPresentationContext] = []
        
        for context in request.presentationContexts {
            if let transferSyntax = acceptedContexts[context.id] {
                acceptedPresentationContexts.append(AcceptedPresentationContext(
                    id: context.id,
                    result: .acceptance,
                    transferSyntax: transferSyntax
                ))
            } else {
                acceptedPresentationContexts.append(AcceptedPresentationContext(
                    id: context.id,
                    result: .abstractSyntaxNotSupported,
                    transferSyntax: context.transferSyntaxes.first ?? implicitVRLittleEndianTransferSyntaxUID
                ))
            }
        }
        
        // Answer the proposed SCP/SCU Role Selections (PS3.7 D.3.3.4.2). The
        // reverse-association requester (the commitment SCP) proposes the SCP
        // role for the commitment class so it may send N-EVENT-REPORT; we grant
        // it. Strict peers treat a missing answer as "default roles" and abort.
        let acceptedSOPClasses = Set(request.presentationContexts
            .filter { acceptedContexts[$0.id] != nil }
            .map { $0.abstractSyntax })
        let roleSelections = request.roleSelections.acceptorResponse(
            acceptSCURoleFor: { acceptedSOPClasses.contains($0) },
            acceptSCPRoleFor: { acceptedSOPClasses.contains($0) }
        )

        return AssociateAcceptPDU(
            calledAETitle: request.calledAETitle,
            callingAETitle: request.callingAETitle,
            applicationContextName: request.applicationContextName,
            presentationContexts: acceptedPresentationContexts,
            maxPDUSize: maxPDUSize,
            implementationClassUID: configuration.implementationClassUID,
            implementationVersionName: configuration.implementationVersionName,
            roleSelections: roleSelections
        )
    }
    
    private func processDataPDU(_ dataPDU: DataTransferPDU) async throws {
        // Assemble the message
        guard let message = try messageAssembler.addPDVs(from: dataPDU) else {
            return // Need more PDVs
        }
        
        // Process based on command type
        switch message.command {
        case .nEventReportRequest:
            try await processNEventReportRequest(message)
        default:
            // Unsupported command - send error response
            break
        }
    }
    
    private func processNEventReportRequest(_ message: AssembledMessage) async throws {
        let commandSet = message.commandSet
        
        let eventTypeID = commandSet.eventTypeID
        let messageID = commandSet.messageID ?? 0
        let affectedSOPClassUID = commandSet.affectedSOPClassUID ?? storageCommitmentPushModelSOPClassUID
        let affectedSOPInstanceUID = commandSet.affectedSOPInstanceUID ?? storageCommitmentPushModelSOPInstanceUID
        
        // PS3.4 J.3.3.1.3: the SCU shall always return the N-EVENT-REPORT
        // response status. Success when the result parsed; otherwise
        // Processing Failure (0110H, PS3.7 §10.1.1.1.8), including a missing
        // Event Type ID or a missing/undecodable data set.
        var status: DIMSEStatus = .failedUnableToProcess
        
        // Parse the commitment result from the data set, in the transfer
        // syntax negotiated for the presentation context it arrived on
        let transferSyntaxUID = acceptedContexts[message.presentationContextID]
        if let eventTypeID, let dataSet = message.dataSet {
            do {
                let result = try StorageCommitmentService.parseCommitmentResult(
                    eventTypeID: eventTypeID,
                    dataSet: dataSet,
                    remoteAETitle: callingAETitle,
                    transferSyntaxUID: transferSyntaxUID
                )
                
                // Deliver the result
                await resultHandler(result)
                status = .success
            } catch {
                status = .failedUnableToProcess
            }
        }
                
        let response = NEventReportResponse(
            messageIDBeingRespondedTo: messageID,
            affectedSOPClassUID: affectedSOPClassUID,
            affectedSOPInstanceUID: affectedSOPInstanceUID,
            eventTypeID: eventTypeID,
            status: status,
            hasDataSet: false,
            presentationContextID: message.presentationContextID
        )
                
        try await sendNEventReportResponse(response)
    }
    
    private func sendNEventReportResponse(_ response: NEventReportResponse) async throws {
        let fragmenter = MessageFragmenter(maxPDUSize: maxPDUSize)
        let pdus = fragmenter.fragmentMessage(
            commandSet: response.commandSet,
            dataSet: nil,
            presentationContextID: response.presentationContextID
        )
        
        for pdu in pdus {
            try await sendPDU(pdu)
        }
    }
    
    // MARK: - PDU I/O
    
    /// Receives exactly one PDU (6-byte header, then the body), so that back-to-back
    /// PDUs in one TCP segment (e.g. P-DATA-TF followed by A-RELEASE-RQ) are not lost.
    private func receivePDU() async throws -> any PDU {
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

        var fullData = headerData
        if pduLength > 0 {
            let bodyData = try await receive(length: pduLength)
            guard bodyData.count == pduLength else {
                throw DICOMNetworkError.connectionClosed
            }
            fullData.append(bodyData)
        }

        return try PDUDecoder.decode(from: fullData)
    }

    private func receive(length: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: length, maximumLength: length) { content, _, isComplete, error in
                if let error = error {
                    continuation.resume(throwing: DICOMNetworkError.connectionFailed(error.localizedDescription))
                } else if let data = content, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: DICOMNetworkError.connectionClosed)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }
    
    private func sendPDU(_ pdu: any PDU) async throws {
        let data = try pdu.encode()
        
        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: DICOMNetworkError.connectionFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }
}

#endif

/// A set-once flag so an `NWConnection` state handler resumes its continuation
/// exactly once (a terminal transition right after `.ready` must not resume twice).
private final class ListenerResumeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isSet = false
    func trySet() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if isSet { return false }
        isSet = true
        return true
    }
}
