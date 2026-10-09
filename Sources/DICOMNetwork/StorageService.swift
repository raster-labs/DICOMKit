import Foundation
import DICOMCore
// NEMA-verified: 2026a, checked 2026-10-01 — C-STORE fields per PS3.7 2026a Table 9.3-1 (Move Originator AE Title / Message ID (0000,1030/1031) per 9.1.1.1.6 / 9.1.1.1.7, D156), statuses per PS3.4 Table B.2-1 (StoreResult.success / isStored true for the Success and Warning classes, D72); presentation-context IDs bounded per PS3.8 §9.3.2.2; File Meta Information parse per PS3.10 §7.1

// MARK: - Store Result

/// Result of a DICOM storage operation (C-STORE)
///
/// Contains information about the completed C-STORE operation.
///
/// A C-STORE-RSP in the Failure class (PS3.4 Table B.2-1: A7xx, A9xx, Cxxx, or
/// 0122 per PS3.7 9.1.1.1.9) is **returned**, not thrown: `DICOMStorageService.store`
/// throws only when no response was received (association, transport or
/// negotiation errors). Test ``isStored`` (or ``isFailure``), not just the status.
///
/// Reference: PS3.4 Annex B - Storage Service Class
public struct StoreResult: Sendable, Hashable {
    /// Whether the SCP stored the instance: true for the Success **and** Warning
    /// classes of PS3.4 Table B.2-1 (0000; B000 Coercion of Data Elements, B006
    /// Elements Discarded, B007 Data Set does not match SOP Class), false for a
    /// Failure — the same meaning as ``FileStoreResult/success``.
    ///
    /// Before 2026-10-01 `DICOMStorageService.store` set it true only for 0000, so a
    /// Warning read as not stored (D72). Prefer ``isStored``, ``isSuccess``,
    /// ``isWarning`` and ``isFailure``, which are derived from ``status``.
    public let success: Bool
    
    /// The DIMSE status from the response
    public let status: DIMSEStatus
    
    /// The affected SOP Class UID
    public let affectedSOPClassUID: String
    
    /// The affected SOP Instance UID
    public let affectedSOPInstanceUID: String
    
    /// Round-trip time in seconds
    public let roundTripTime: TimeInterval
    
    /// The remote Application Entity title
    public let remoteAETitle: String
    
    /// Whether the store completed with a warning
    public var hasWarning: Bool {
        status.isWarning
    }

    /// Whether the instance was stored: Success or Warning class (PS3.4 Table B.2-1).
    public var isStored: Bool {
        status.isSuccessOrWarning
    }

    /// Whether the response status is Success (0000) — no warning.
    public var isSuccess: Bool {
        status.isSuccess
    }

    /// Whether the response status is in the Warning class (B000, B006, B007, other Bxxx):
    /// the instance was stored with a deviation.
    public var isWarning: Bool {
        status.isWarning
    }

    /// Whether the response status is in the Failure class (A7xx, A9xx, Cxxx, 0122, …):
    /// the instance was not stored.
    public var isFailure: Bool {
        !status.isSuccessOrWarning
    }
    
    /// Creates a store result
    public init(
        success: Bool,
        status: DIMSEStatus,
        affectedSOPClassUID: String,
        affectedSOPInstanceUID: String,
        roundTripTime: TimeInterval,
        remoteAETitle: String
    ) {
        self.success = success
        self.status = status
        self.affectedSOPClassUID = affectedSOPClassUID
        self.affectedSOPInstanceUID = affectedSOPInstanceUID
        self.roundTripTime = roundTripTime
        self.remoteAETitle = remoteAETitle
    }
}

extension StoreResult: CustomStringConvertible {
    public var description: String {
        let statusStr = status.isWarning ? "WARNING" : (success ? "SUCCESS" : "FAILED")
        return "StoreResult(\(statusStr), status=\(status), sop=\(affectedSOPClassUID), rtt=\(String(format: "%.3f", roundTripTime))s, ae=\(remoteAETitle))"
    }
}

// MARK: - Storage Status Category

/// Categories of C-STORE status codes
///
/// Reference: PS3.4 Annex B.2.3 - Status
public enum StoreStatusCategory: Sendable, Hashable {
    /// Operation completed successfully (0x0000)
    case success
    
    /// Operation completed with a warning
    case warning
    
    /// Operation failed
    case failure
    
    /// Unknown status
    case unknown
    
    /// Creates a status category from a DIMSE status
    public init(from status: DIMSEStatus) {
        if status.isSuccess {
            self = .success
        } else if status.isWarning {
            self = .warning
        } else if status.isFailure {
            self = .failure
        } else {
            self = .unknown
        }
    }
}

// MARK: - Storage Configuration

/// Configuration for the DICOM Storage Service
public struct StorageConfiguration: Sendable, Hashable {
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
    
    /// Priority for the store operation
    public let priority: DIMSEPriority

#if canImport(Network)
    /// Complete TLS transport policy, or `nil` for plain TCP
    public let tlsConfiguration: TLSConfiguration?
#endif
    
    /// User identity for authentication (optional)
    public let userIdentity: UserIdentity?
    
    /// Transcoding configuration for automatic transfer syntax conversion
    ///
    /// When enabled, the storage service will automatically transcode data
    /// if the remote server doesn't support the source transfer syntax.
    public let transcodingConfiguration: TranscodingConfiguration?
    
    /// Default Implementation Class UID for DICOMKit
    public static let defaultImplementationClassUID = DICOMNetworkImplementation.classUID
    
    /// Default Implementation Version Name for DICOMKit
    public static let defaultImplementationVersionName = "DICOMKIT_001"

    /// Move Originator Application Entity Title (0000,1030) put on every C-STORE-RQ,
    /// or nil (the default) to omit it.
    ///
    /// PS3.7 2026a 9.1.1.1.6: set when the C-STORE is a sub-operation of a C-MOVE,
    /// to the AE Title of the SCU that issued the C-MOVE; with
    /// ``moveOriginatorMessageID`` it lets the Move Destination tie the instance to
    /// the originating C-MOVE (Table 9.3-1, both U). Set both with
    /// ``withMoveOriginator(aeTitle:messageID:)`` (D156, 2026-10-01).
    public var moveOriginatorAETitle: String? = nil

    /// Move Originator Message ID (0000,1031) put on every C-STORE-RQ, or nil to
    /// omit it — the Message ID (0000,0110) of the C-MOVE-RQ this store is a
    /// sub-operation of (PS3.7 2026a 9.1.1.1.7).
    public var moveOriginatorMessageID: UInt16? = nil

    /// This configuration with Move Originator AE Title (0000,1030) and Move
    /// Originator Message ID (0000,1031) set, for the C-STORE sub-operations of a
    /// C-MOVE (PS3.7 2026a 9.1.1.1.6 / 9.1.1.1.7).
    public func withMoveOriginator(aeTitle: String, messageID: UInt16) -> StorageConfiguration {
        var copy = self
        copy.moveOriginatorAETitle = aeTitle
        copy.moveOriginatorMessageID = messageID
        return copy
    }
    
    /// Creates a storage configuration
    ///
    /// - Parameters:
    ///   - callingAETitle: The local AE title
    ///   - calledAETitle: The remote AE title
    ///   - timeout: Connection timeout in seconds (default: 60)
    ///   - maxPDUSize: Maximum PDU size (default: 64 KB (`defaultMaxPDUSize`))
    ///   - implementationClassUID: Implementation Class UID
    ///   - implementationVersionName: Implementation Version Name
    ///   - priority: Operation priority (default: medium)
    ///   - userIdentity: User identity for authentication (optional)
    ///   - transcodingConfiguration: Transcoding configuration (default: nil - no transcoding)
    public init(
        callingAETitle: AETitle,
        calledAETitle: AETitle,
        timeout: TimeInterval = 60,
        maxPDUSize: UInt32 = defaultMaxPDUSize,
        implementationClassUID: String = defaultImplementationClassUID,
        implementationVersionName: String? = defaultImplementationVersionName,
        priority: DIMSEPriority = .medium,
        userIdentity: UserIdentity? = nil,
        transcodingConfiguration: TranscodingConfiguration? = nil
    ) {
        self.callingAETitle = callingAETitle
        self.calledAETitle = calledAETitle
        self.timeout = timeout
        self.maxPDUSize = maxPDUSize
        self.implementationClassUID = implementationClassUID
        self.implementationVersionName = implementationVersionName
        self.priority = priority
#if canImport(Network)
        self.tlsConfiguration = nil
#endif
        self.userIdentity = userIdentity
        self.transcodingConfiguration = transcodingConfiguration
    }

#if canImport(Network)
    /// Creates a storage configuration with an exact TLS transport policy.
    public init(
        callingAETitle: AETitle,
        calledAETitle: AETitle,
        timeout: TimeInterval = 60,
        maxPDUSize: UInt32 = defaultMaxPDUSize,
        implementationClassUID: String = defaultImplementationClassUID,
        implementationVersionName: String? = defaultImplementationVersionName,
        priority: DIMSEPriority = .medium,
        tlsConfiguration: TLSConfiguration?,
        userIdentity: UserIdentity? = nil,
        transcodingConfiguration: TranscodingConfiguration? = nil
    ) {
        self.callingAETitle = callingAETitle
        self.calledAETitle = calledAETitle
        self.timeout = timeout
        self.maxPDUSize = maxPDUSize
        self.implementationClassUID = implementationClassUID
        self.implementationVersionName = implementationVersionName
        self.priority = priority
        self.tlsConfiguration = tlsConfiguration
        self.userIdentity = userIdentity
        self.transcodingConfiguration = transcodingConfiguration
    }

    /// Builds the exact association configuration used by storage operations.
    func associationConfiguration(host: String, port: UInt16) -> AssociationConfiguration {
        AssociationConfiguration(
            callingAETitle: callingAETitle,
            calledAETitle: calledAETitle,
            host: host,
            port: port,
            maxPDUSize: maxPDUSize,
            implementationClassUID: implementationClassUID,
            implementationVersionName: implementationVersionName,
            timeout: timeout,
            tlsConfiguration: tlsConfiguration,
            userIdentity: userIdentity
        )
    }
#endif
}

// MARK: - Batch Store Progress

/// Progress information for batch storage operations
public struct BatchStoreProgress: Sendable, Hashable {
    /// Total number of instances to store
    public let total: Int
    
    /// Number of instances stored successfully
    public let succeeded: Int
    
    /// Number of instances that failed
    public let failed: Int
    
    /// Number of instances with warnings
    public let warnings: Int
    
    /// The fraction of operations complete (0.0 to 1.0)
    public var fractionComplete: Double {
        guard total > 0 else { return 0.0 }
        return Double(succeeded + failed + warnings) / Double(total)
    }
    
    /// Whether all operations have completed (regardless of success/failure)
    public var isComplete: Bool {
        succeeded + failed + warnings >= total
    }
    
    /// Creates batch store progress information
    public init(total: Int, succeeded: Int = 0, failed: Int = 0, warnings: Int = 0) {
        self.total = total
        self.succeeded = succeeded
        self.failed = failed
        self.warnings = warnings
    }
}

extension BatchStoreProgress: CustomStringConvertible {
    public var description: String {
        "BatchProgress: \(succeeded + failed + warnings)/\(total) completed (\(succeeded) succeeded, \(failed) failed, \(warnings) warnings)"
    }
}

// MARK: - Storage Progress Event

/// Events emitted during batch storage operations
///
/// Used with `AsyncThrowingStream` to report progress of batch storage operations.
///
/// Reference: PS3.4 Annex B - Storage Service Class
public enum StorageProgressEvent: Sendable {
    /// Progress update with current counts
    case progress(BatchStoreProgress)
    
    /// An individual file was stored (success, warning, or failure)
    case fileResult(FileStoreResult)
    
    /// All files have been processed
    case completed(BatchStoreResult)
    
    /// An error occurred that prevented the operation from continuing
    case error(Error)
}

// MARK: - File Store Result

/// Result of storing a single file within a batch operation
///
/// Contains detailed information about an individual C-STORE operation.
public struct FileStoreResult: Sendable, Hashable {
    /// The index of the file in the batch (0-based)
    public let index: Int
    
    /// The SOP Instance UID of the stored instance
    public let sopInstanceUID: String
    
    /// The SOP Class UID of the stored instance
    public let sopClassUID: String
    
    /// Whether the storage was successful
    public let success: Bool
    
    /// The DIMSE status from the response
    public let status: DIMSEStatus
    
    /// Round-trip time in seconds for this file
    public let roundTripTime: TimeInterval
    
    /// Size of the file in bytes
    public let fileSize: Int
    
    /// Error message if the store failed (nil if successful)
    public let errorMessage: String?
    
    /// Whether the store completed with a warning
    public var hasWarning: Bool {
        status.isWarning
    }
    
    /// Creates a file store result
    public init(
        index: Int,
        sopInstanceUID: String,
        sopClassUID: String,
        success: Bool,
        status: DIMSEStatus,
        roundTripTime: TimeInterval,
        fileSize: Int,
        errorMessage: String? = nil
    ) {
        self.index = index
        self.sopInstanceUID = sopInstanceUID
        self.sopClassUID = sopClassUID
        self.success = success
        self.status = status
        self.roundTripTime = roundTripTime
        self.fileSize = fileSize
        self.errorMessage = errorMessage
    }
    
    /// Creates a success result
    public static func success(
        index: Int,
        sopInstanceUID: String,
        sopClassUID: String,
        status: DIMSEStatus,
        roundTripTime: TimeInterval,
        fileSize: Int
    ) -> FileStoreResult {
        FileStoreResult(
            index: index,
            sopInstanceUID: sopInstanceUID,
            sopClassUID: sopClassUID,
            success: true,
            status: status,
            roundTripTime: roundTripTime,
            fileSize: fileSize
        )
    }
    
    /// Creates a failure result
    public static func failure(
        index: Int,
        sopInstanceUID: String,
        sopClassUID: String,
        status: DIMSEStatus,
        roundTripTime: TimeInterval,
        fileSize: Int,
        errorMessage: String
    ) -> FileStoreResult {
        FileStoreResult(
            index: index,
            sopInstanceUID: sopInstanceUID,
            sopClassUID: sopClassUID,
            success: false,
            status: status,
            roundTripTime: roundTripTime,
            fileSize: fileSize,
            errorMessage: errorMessage
        )
    }
}

extension FileStoreResult: CustomStringConvertible {
    public var description: String {
        let statusStr = success ? (hasWarning ? "WARNING" : "SUCCESS") : "FAILED"
        let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
        return "FileStoreResult[\(index)](\(statusStr), sop=\(sopInstanceUID), size=\(sizeStr), rtt=\(String(format: "%.3f", roundTripTime))s)"
    }
}

// MARK: - Batch Store Result

/// Result of a batch storage operation
///
/// Contains summary information about the batch operation and individual file results.
public struct BatchStoreResult: Sendable {
    /// Final progress counts
    public let progress: BatchStoreProgress
    
    /// Individual results for each file
    public let fileResults: [FileStoreResult]
    
    /// Total bytes transferred
    public let totalBytesTransferred: Int
    
    /// Total time for the batch operation in seconds
    public let totalTime: TimeInterval
    
    /// Average transfer rate in bytes per second
    public var averageTransferRate: Double {
        guard totalTime > 0 else { return 0 }
        return Double(totalBytesTransferred) / totalTime
    }
    
    /// Whether all files were stored successfully
    public var allSucceeded: Bool {
        progress.failed == 0 && progress.warnings == 0
    }
    
    /// Whether any files failed to store
    public var hasFailures: Bool {
        progress.failed > 0
    }
    
    /// The failed file results
    public var failedFiles: [FileStoreResult] {
        fileResults.filter { !$0.success }
    }
    
    /// The successful file results
    public var successfulFiles: [FileStoreResult] {
        fileResults.filter { $0.success && !$0.hasWarning }
    }
    
    /// Creates a batch store result
    public init(
        progress: BatchStoreProgress,
        fileResults: [FileStoreResult],
        totalBytesTransferred: Int,
        totalTime: TimeInterval
    ) {
        self.progress = progress
        self.fileResults = fileResults
        self.totalBytesTransferred = totalBytesTransferred
        self.totalTime = totalTime
    }
}

extension BatchStoreResult: CustomStringConvertible {
    public var description: String {
        let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(totalBytesTransferred), countStyle: .file)
        let rateStr = ByteCountFormatter.string(fromByteCount: Int64(averageTransferRate), countStyle: .file)
        return "BatchStoreResult(\(progress.succeeded) succeeded, \(progress.failed) failed, \(progress.warnings) warnings, \(sizeStr) in \(String(format: "%.2f", totalTime))s @ \(rateStr)/s)"
    }
}

// MARK: - Batch Storage Configuration

/// Configuration for batch storage operations
///
/// Defines behavior for storing multiple DICOM files in a single operation.
public struct BatchStorageConfiguration: Sendable, Hashable {
    /// Whether to continue storing files after a failure
    public let continueOnError: Bool
    
    /// Maximum number of files to store over a single association
    /// If exceeded, a new association will be created
    /// Set to 0 for unlimited (single association)
    public let maxFilesPerAssociation: Int
    
    /// Delay between files in seconds (for rate limiting)
    public let delayBetweenFiles: TimeInterval
    
    /// Creates a batch storage configuration
    ///
    /// - Parameters:
    ///   - continueOnError: Whether to continue after failures (default: true)
    ///   - maxFilesPerAssociation: Max files per association, 0 for unlimited (default: 0)
    ///   - delayBetweenFiles: Delay between files in seconds (default: 0)
    public init(
        continueOnError: Bool = true,
        maxFilesPerAssociation: Int = 0,
        delayBetweenFiles: TimeInterval = 0
    ) {
        self.continueOnError = continueOnError
        self.maxFilesPerAssociation = max(0, maxFilesPerAssociation)
        self.delayBetweenFiles = max(0, delayBetweenFiles)
    }
    
    /// Default configuration: continue on error, single association, no delay
    public static let `default` = BatchStorageConfiguration()
    
    /// Configuration that stops on first error
    public static let failFast = BatchStorageConfiguration(continueOnError: false)
}

#if canImport(Network)

// MARK: - DICOM Storage Service

/// DICOM Storage Service (C-STORE SCU)
///
/// Implements the DICOM Storage Service Class as a Service Class User (SCU).
/// This enables sending DICOM files to remote Storage Service Class Providers (SCPs)
/// such as PACS systems, workstations, or other DICOM nodes.
///
/// Reference: PS3.4 Annex B - Storage Service Class
/// Reference: PS3.7 Section 9.1.1 - C-STORE Service
///
/// ## Usage
///
/// ```swift
/// // Store a DICOM file
/// let result = try await DICOMStorageService.store(
///     file: dicomFile,
///     to: "pacs.hospital.com",
///     port: 11112,
///     callingAE: "MY_SCU",
///     calledAE: "PACS"
/// )
///
/// if result.success {
///     print("Stored successfully: \(result.affectedSOPInstanceUID)")
/// }
///
/// // Store raw DICOM data
/// let dataResult = try await DICOMStorageService.store(
///     data: dicomData,
///     sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
///     sopInstanceUID: "1.2.3.4.5.6.7.8.9",
///     to: "pacs.hospital.com",
///     port: 11112,
///     callingAE: "MY_SCU",
///     calledAE: "PACS"
/// )
/// ```
public enum DICOMStorageService {
    
    // MARK: - Store File
    
    /// Stores a DICOM file to a remote SCP
    ///
    /// Extracts the SOP Class UID and SOP Instance UID from the file's data set
    /// and sends it to the specified destination.
    ///
    /// - Parameters:
    ///   - data: The complete DICOM file data (including file meta information)
    ///   - host: The remote host address (IP or hostname)
    ///   - port: The remote port number (default: 104)
    ///   - callingAE: The local Application Entity title
    ///   - calledAE: The remote Application Entity title
    ///   - priority: Operation priority (default: medium)
    ///   - timeout: Connection timeout in seconds (default: 60)
    /// - Returns: A `StoreResult` with detailed information
    /// - Throws: `DICOMNetworkError` for connection or protocol errors
    /// - Throws: `DICOMError` if the file cannot be parsed or is missing required attributes
    public static func store(
        fileData data: Data,
        to host: String,
        port: UInt16 = dicomDefaultPort,
        callingAE: String,
        calledAE: String,
        priority: DIMSEPriority = .medium,
        timeout: TimeInterval = 60
    ) async throws -> StoreResult {
        let callingAETitle = try AETitle(callingAE)
        let calledAETitle = try AETitle(calledAE)
        
        // Parse the DICOM file to get SOP Class and Instance UIDs
        let parser = DICOMFileParser(data: data)
        let fileInfo = try parser.parseForStorage()
        
        let config = StorageConfiguration(
            callingAETitle: callingAETitle,
            calledAETitle: calledAETitle,
            timeout: timeout,
            priority: priority
        )
        
        return try await performStore(
            host: host,
            port: port,
            configuration: config,
            sopClassUID: fileInfo.sopClassUID,
            sopInstanceUID: fileInfo.sopInstanceUID,
            transferSyntaxUID: fileInfo.transferSyntaxUID,
            dataSetData: fileInfo.dataSetData
        )
    }

    /// Stores a DICOM file with full transport, identity, and association configuration.
    public static func store(
        fileData data: Data,
        to host: String,
        port: UInt16 = dicomDefaultPort,
        configuration: StorageConfiguration
    ) async throws -> StoreResult {
        let fileInfo = try DICOMFileParser(data: data).parseForStorage()
        return try await performStore(
            host: host,
            port: port,
            configuration: configuration,
            sopClassUID: fileInfo.sopClassUID,
            sopInstanceUID: fileInfo.sopInstanceUID,
            transferSyntaxUID: fileInfo.transferSyntaxUID,
            dataSetData: fileInfo.dataSetData
        )
    }

    /// Stores a DICOM file to a remote SCP, proposing a specific transfer syntax as the preferred
    /// transfer syntax in the presentation context negotiation. The file's own transfer syntax and
    /// Explicit/Implicit VR Little Endian are also proposed as fallbacks.
    ///
    /// - Parameters:
    ///   - data: The raw DICOM file data (including the 128-byte preamble and DICM prefix)
    ///   - preferredTransferSyntaxUID: The transfer syntax UID to propose as first choice
    ///   - host: The remote host address (IP or hostname)
    ///   - port: The remote port number (default: 104)
    ///   - callingAE: The local Application Entity title
    ///   - calledAE: The remote Application Entity title
    ///   - priority: Operation priority (default: medium)
    ///   - timeout: Connection timeout in seconds (default: 60)
    /// - Returns: A `StoreResult` with detailed information
    /// - Throws: `DICOMNetworkError` for connection or protocol errors
    /// - Throws: `DICOMError` if the file cannot be parsed or is missing required attributes
    public static func store(
        fileData data: Data,
        preferredTransferSyntaxUID: String,
        to host: String,
        port: UInt16 = dicomDefaultPort,
        callingAE: String,
        calledAE: String,
        priority: DIMSEPriority = .medium,
        timeout: TimeInterval = 60
    ) async throws -> StoreResult {
        let callingAETitle = try AETitle(callingAE)
        let calledAETitle = try AETitle(calledAE)

        let parser = DICOMFileParser(data: data)
        let fileInfo = try parser.parseForStorage()

        let config = StorageConfiguration(
            callingAETitle: callingAETitle,
            calledAETitle: calledAETitle,
            timeout: timeout,
            priority: priority
        )

        // Build deduplicated TS list: preferred first, then file's own TS, then standard fallbacks
        var transferSyntaxes: [String] = [preferredTransferSyntaxUID]
        for ts in [fileInfo.transferSyntaxUID,
                   explicitVRLittleEndianTransferSyntaxUID,
                   implicitVRLittleEndianTransferSyntaxUID]
            where !transferSyntaxes.contains(ts) {
            transferSyntaxes.append(ts)
        }

        return try await performStoreWithSyntaxList(
            host: host,
            port: port,
            configuration: config,
            sopClassUID: fileInfo.sopClassUID,
            sopInstanceUID: fileInfo.sopInstanceUID,
            transferSyntaxes: transferSyntaxes,
            dataTransferSyntaxUID: fileInfo.transferSyntaxUID,
            dataSetData: fileInfo.dataSetData
        )
    }
    
    // MARK: - Store Data Set
    
    /// Stores a DICOM data set to a remote SCP
    ///
    /// Sends the provided data set with the specified SOP Class and Instance UIDs.
    /// The data should be encoded in the specified transfer syntax.
    ///
    /// - Parameters:
    ///   - data: The DICOM data set (without file meta information preamble)
    ///   - sopClassUID: The SOP Class UID
    ///   - sopInstanceUID: The SOP Instance UID  
    ///   - transferSyntaxUID: The transfer syntax of the data (default: Explicit VR Little Endian)
    ///   - host: The remote host address (IP or hostname)
    ///   - port: The remote port number (default: 104)
    ///   - callingAE: The local Application Entity title
    ///   - calledAE: The remote Application Entity title
    ///   - priority: Operation priority (default: medium)
    ///   - timeout: Connection timeout in seconds (default: 60)
    /// - Returns: A `StoreResult` with detailed information
    /// - Throws: `DICOMNetworkError` for connection or protocol errors
    public static func store(
        dataSetData data: Data,
        sopClassUID: String,
        sopInstanceUID: String,
        transferSyntaxUID: String = explicitVRLittleEndianTransferSyntaxUID,
        to host: String,
        port: UInt16 = dicomDefaultPort,
        callingAE: String,
        calledAE: String,
        priority: DIMSEPriority = .medium,
        timeout: TimeInterval = 60
    ) async throws -> StoreResult {
        let callingAETitle = try AETitle(callingAE)
        let calledAETitle = try AETitle(calledAE)
        
        let config = StorageConfiguration(
            callingAETitle: callingAETitle,
            calledAETitle: calledAETitle,
            timeout: timeout,
            priority: priority
        )
        
        return try await performStore(
            host: host,
            port: port,
            configuration: config,
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            transferSyntaxUID: transferSyntaxUID,
            dataSetData: data
        )
    }
    
    // MARK: - Store with Configuration
    
    /// Stores a DICOM data set with full configuration control
    ///
    /// - Parameters:
    ///   - data: The DICOM data set (without file meta information preamble)
    ///   - sopClassUID: The SOP Class UID
    ///   - sopInstanceUID: The SOP Instance UID
    ///   - transferSyntaxUID: The transfer syntax of the data
    ///   - host: The remote host address
    ///   - port: The remote port number (default: 104)
    ///   - configuration: The storage configuration
    /// - Returns: A `StoreResult` with detailed information
    /// - Throws: `DICOMNetworkError` for connection or protocol errors
    public static func store(
        dataSetData data: Data,
        sopClassUID: String,
        sopInstanceUID: String,
        transferSyntaxUID: String,
        to host: String,
        port: UInt16 = dicomDefaultPort,
        configuration: StorageConfiguration
    ) async throws -> StoreResult {
        return try await performStore(
            host: host,
            port: port,
            configuration: configuration,
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            transferSyntaxUID: transferSyntaxUID,
            dataSetData: data
        )
    }
    
    // MARK: - Private Implementation
    
    /// Performs a strictly **as-is** C-STORE: the data set is transmitted in its OWN
    /// transfer syntax and is never transcoded, re-encoded, compressed, or decompressed.
    ///
    /// A single presentation context proposing only `transferSyntaxUID` is negotiated.
    /// If the SCP accepts it, the original bytes are sent unchanged. If the SCP does not
    /// accept the file's transfer syntax for this SOP class, the operation fails with a
    /// clear, actionable error — conversion is intentionally out of scope for dicom-send
    /// (convert the file first, e.g. with dicom-convert).
    private static func performAsIsStore(
        host: String,
        port: UInt16,
        configuration: StorageConfiguration,
        sopClassUID: String,
        sopInstanceUID: String,
        transferSyntaxUID: String,
        dataSetData: Data
    ) async throws -> StoreResult {
        let startTime = Date()

        let associationConfig = configuration.associationConfiguration(host: host, port: port)

        let association = Association(configuration: associationConfig)

        // Propose ONLY the file's own transfer syntax — it is transmitted verbatim.
        let presentationContext = try PresentationContext(
            id: 1,
            abstractSyntax: sopClassUID,
            transferSyntaxes: [transferSyntaxUID]
        )

        // Built once so both the "no context accepted" rejection (thrown by request())
        // and the defensive transfer-syntax-mismatch guard surface the same guidance.
        let tsName = TransferSyntax.from(uid: transferSyntaxUID)?.displayName ?? "unknown"
        let notAcceptedError = DICOMNetworkError.invalidState(
            "Destination AE '\(configuration.calledAETitle.value)' did not accept the file's transfer "
            + "syntax \(transferSyntaxUID) (\(tsName)) for SOP Class \(sopClassUID). dicom-send transmits "
            + "files as-is and does not transcode — convert the file to a supported transfer syntax first "
            + "(e.g. with dicom-convert), or send to a destination that accepts this one."
        )

        do {
            let negotiated: NegotiatedAssociation
            do {
                negotiated = try await association.request(presentationContexts: [presentationContext])
            } catch DICOMNetworkError.noPresentationContextAccepted {
                // The SCP rejected the only context we proposed — it does not support the
                // file's transfer syntax. Surface the actionable error, not the generic one.
                try? await association.abort()
                throw notAcceptedError
            }

            // Defensive: with a single proposed transfer syntax an accepted context can
            // only carry that syntax, but verify before transmitting as-is regardless.
            guard negotiated.acceptedTransferSyntax(forContextID: 1) == transferSyntaxUID else {
                try await association.abort()
                throw notAcceptedError
            }

            let response = try await performCStore(
                association: association,
                presentationContextID: 1,
                maxPDUSize: negotiated.maxPDUSize,
                sopClassUID: sopClassUID,
                sopInstanceUID: sopInstanceUID,
                priority: configuration.priority,
                dataSetData: dataSetData,
                moveOriginatorAETitle: configuration.moveOriginatorAETitle,
                moveOriginatorMessageID: configuration.moveOriginatorMessageID
            )

            try await association.release()

            let roundTripTime = Date().timeIntervalSince(startTime)
            return StoreResult(
                // Stored for Success and Warning, PS3.4 Table B.2-1 (D72)
                success: response.status.isSuccessOrWarning,
                status: response.status,
                affectedSOPClassUID: response.affectedSOPClassUID,
                affectedSOPInstanceUID: response.affectedSOPInstanceUID,
                roundTripTime: roundTripTime,
                remoteAETitle: configuration.calledAETitle.value
            )
        } catch {
            try? await association.abort()
            throw error
        }
    }

    /// Performs the C-STORE operation. dicom-send is strictly as-is: the data set is
    /// transmitted in its own transfer syntax (no transcoding). See `performAsIsStore`.
    private static func performStore(
        host: String,
        port: UInt16,
        configuration: StorageConfiguration,
        sopClassUID: String,
        sopInstanceUID: String,
        transferSyntaxUID: String,
        dataSetData: Data
    ) async throws -> StoreResult {
        return try await performAsIsStore(
            host: host,
            port: port,
            configuration: configuration,
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            transferSyntaxUID: transferSyntaxUID,
            dataSetData: dataSetData
        )
    }

    /// C-STORE for the `--transfer-syntax` path. dicom-send is strictly as-is, so a
    /// requested transfer syntax is only honoured when it matches the file's own; a
    /// request to send in a DIFFERENT syntax would require transcoding, which is out of
    /// scope (convert the file first, e.g. with dicom-convert). `transferSyntaxes.first`
    /// is the caller's requested syntax; `dataTransferSyntaxUID` is the file's actual
    /// encoding, which is always what gets transmitted.
    private static func performStoreWithSyntaxList(
        host: String,
        port: UInt16,
        configuration: StorageConfiguration,
        sopClassUID: String,
        sopInstanceUID: String,
        transferSyntaxes: [String],
        dataTransferSyntaxUID: String,
        dataSetData: Data
    ) async throws -> StoreResult {
        if let requested = transferSyntaxes.first, requested != dataTransferSyntaxUID {
            let requestedName = TransferSyntax.from(uid: requested)?.displayName ?? "unknown"
            let actualName = TransferSyntax.from(uid: dataTransferSyntaxUID)?.displayName ?? "unknown"
            throw DICOMNetworkError.invalidState(
                "Requested transfer syntax \(requested) (\(requestedName)) differs from the file's "
                + "actual transfer syntax \(dataTransferSyntaxUID) (\(actualName)). dicom-send transmits "
                + "files as-is and does not transcode — convert the file first (e.g. with dicom-convert), "
                + "or omit --transfer-syntax to send it unchanged."
            )
        }
        return try await performAsIsStore(
            host: host,
            port: port,
            configuration: configuration,
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            transferSyntaxUID: dataTransferSyntaxUID,
            dataSetData: dataSetData
        )
    }
    ///
    /// - Parameters:
    ///   - association: The established association
    ///   - presentationContextID: The accepted presentation context ID
    ///   - maxPDUSize: The negotiated maximum PDU size
    ///   - sopClassUID: The SOP Class UID
    ///   - sopInstanceUID: The SOP Instance UID
    ///   - priority: The operation priority
    ///   - dataSetData: The data set to store
    /// - Returns: The C-STORE response
    /// - Throws: `DICOMNetworkError` for protocol errors
    private static func performCStore(
        association: Association,
        presentationContextID: UInt8,
        maxPDUSize: UInt32,
        sopClassUID: String,
        sopInstanceUID: String,
        priority: DIMSEPriority,
        dataSetData: Data,
        moveOriginatorAETitle: String? = nil,
        moveOriginatorMessageID: UInt16? = nil
    ) async throws -> CStoreResponse {
        // Create C-STORE request
        let request = cStoreRequest(
            messageID: 1,
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            priority: priority,
            moveOriginatorAETitle: moveOriginatorAETitle,
            moveOriginatorMessageID: moveOriginatorMessageID,
            presentationContextID: presentationContextID
        )
        
        // Fragment and send the command and data set
        let fragmenter = MessageFragmenter(maxPDUSize: maxPDUSize)
        let pdus = fragmenter.fragmentMessage(
            commandSet: request.commandSet,
            dataSet: dataSetData,
            presentationContextID: presentationContextID
        )
        
        // Send all PDUs
        for pdu in pdus {
            for pdv in pdu.presentationDataValues {
                try await association.send(pdv: pdv)
            }
        }
        
        // Receive response
        let assembler = MessageAssembler()
        
        while true {
            let responsePDU = try await association.receive()
            
            if let message = try assembler.addPDVs(from: responsePDU) {
                guard let storeResponse = message.asCStoreResponse() else {
                    throw DICOMNetworkError.decodingFailed(
                        "Expected C-STORE-RSP, got \(message.command?.description ?? "unknown")"
                    )
                }
                return storeResponse
            }
        }
    }
    
    // MARK: - Batch Storage
    
    /// Stores multiple DICOM files to a remote SCP
    ///
    /// Returns an async stream that emits progress events as files are stored.
    /// Files are sent over a single association for efficiency.
    ///
    /// - Parameters:
    ///   - files: Array of DICOM file data to store
    ///   - host: The remote host address
    ///   - port: The remote port number (default: 104)
    ///   - callingAE: The local Application Entity title
    ///   - calledAE: The remote Application Entity title
    ///   - priority: Operation priority (default: medium)
    ///   - timeout: Connection timeout in seconds (default: 60)
    ///   - configuration: Batch configuration options (default: continue on error)
    /// - Returns: An async stream of `StorageProgressEvent` values
    /// - Throws: `DICOMNetworkError` for connection errors during setup
    public static func storeBatch(
        files: [Data],
        to host: String,
        port: UInt16 = dicomDefaultPort,
        callingAE: String,
        calledAE: String,
        priority: DIMSEPriority = .medium,
        timeout: TimeInterval = 60,
        configuration: BatchStorageConfiguration = .default
    ) async throws -> AsyncThrowingStream<StorageProgressEvent, Error> {
        let callingAETitle = try AETitle(callingAE)
        let calledAETitle = try AETitle(calledAE)
        
        let storageConfig = StorageConfiguration(
            callingAETitle: callingAETitle,
            calledAETitle: calledAETitle,
            timeout: timeout,
            priority: priority
        )
        
        return makeBatchStoreStream(
            files: files,
            host: host,
            port: port,
            configuration: storageConfig,
            batchConfiguration: configuration
        )
    }

    /// Stores multiple DICOM files with full transport, identity, and association configuration.
    public static func storeBatch(
        files: [Data],
        to host: String,
        port: UInt16 = dicomDefaultPort,
        storageConfiguration: StorageConfiguration,
        configuration batchConfiguration: BatchStorageConfiguration = .default
    ) -> AsyncThrowingStream<StorageProgressEvent, Error> {
        makeBatchStoreStream(
            files: files,
            host: host,
            port: port,
            configuration: storageConfiguration,
            batchConfiguration: batchConfiguration
        )
    }

    /// Creates a cancellation-aware batch producer.
    ///
    /// Cancelling or abandoning the returned stream must stop the producer: otherwise
    /// C-STORE operations (and their credential-bearing configuration) can outlive the
    /// caller that initiated them.
    private static func makeBatchStoreStream(
        files: [Data],
        host: String,
        port: UInt16,
        configuration: StorageConfiguration,
        batchConfiguration: BatchStorageConfiguration
    ) -> AsyncThrowingStream<StorageProgressEvent, Error> {
        AsyncThrowingStream { continuation in
            let producer = Task {
                do {
                    try await performBatchStore(
                        files: files,
                        host: host,
                        port: port,
                        configuration: configuration,
                        batchConfiguration: batchConfiguration,
                        continuation: continuation
                    )
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.yield(.error(error))
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in producer.cancel() }
        }
    }
    
    /// Performs the batch C-STORE operation
    private static func performBatchStore(
        files: [Data],
        host: String,
        port: UInt16,
        configuration: StorageConfiguration,
        batchConfiguration: BatchStorageConfiguration,
        continuation: AsyncThrowingStream<StorageProgressEvent, Error>.Continuation
    ) async throws {
        try Task.checkCancellation()

        let startTime = Date()
        var fileResults: [FileStoreResult] = []
        var succeeded = 0
        var failed = 0
        var warnings = 0
        var totalBytesTransferred = 0
        let total = files.count
        
        guard !files.isEmpty else {
            let result = BatchStoreResult(
                progress: BatchStoreProgress(total: 0),
                fileResults: [],
                totalBytesTransferred: 0,
                totalTime: 0
            )
            continuation.yield(.completed(result))
            continuation.finish()
            return
        }
        
        // Parse all files first to gather SOP Class UIDs for negotiation
        var fileInfos: [(index: Int, data: Data, info: DICOMFileParser.FileInfo)] = []
        
        for (index, fileData) in files.enumerated() {
            try Task.checkCancellation()

            do {
                let parser = DICOMFileParser(data: fileData)
                let info = try parser.parseForStorage()
                fileInfos.append((index, fileData, info))
            } catch {
                // Record parse failure
                let fileResult = FileStoreResult(
                    index: index,
                    sopInstanceUID: "UNKNOWN",
                    sopClassUID: "UNKNOWN",
                    success: false,
                    status: .errorCannotUnderstand(0xC000),
                    roundTripTime: 0,
                    fileSize: fileData.count,
                    errorMessage: "Failed to parse DICOM file: \(error.localizedDescription)"
                )
                fileResults.append(fileResult)
                failed += 1
                
                continuation.yield(.fileResult(fileResult))
                continuation.yield(.progress(BatchStoreProgress(
                    total: total, succeeded: succeeded, failed: failed, warnings: warnings
                )))
                
                if !batchConfiguration.continueOnError {
                    let totalTime = Date().timeIntervalSince(startTime)
                    let result = BatchStoreResult(
                        progress: BatchStoreProgress(total: total, succeeded: succeeded, failed: failed, warnings: warnings),
                        fileResults: fileResults,
                        totalBytesTransferred: totalBytesTransferred,
                        totalTime: totalTime
                    )
                    continuation.yield(.completed(result))
                    continuation.finish()
                    return
                }
            }
        }
        
        // No valid files to store
        if fileInfos.isEmpty {
            let totalTime = Date().timeIntervalSince(startTime)
            let result = BatchStoreResult(
                progress: BatchStoreProgress(total: total, succeeded: succeeded, failed: failed, warnings: warnings),
                fileResults: fileResults,
                totalBytesTransferred: totalBytesTransferred,
                totalTime: totalTime
            )
            continuation.yield(.completed(result))
            continuation.finish()
            return
        }
        
        // Create association configuration
        let associationConfig = configuration.associationConfiguration(host: host, port: port)
        
        // Presentation context IDs are odd 1...255 (PS3.8 9.3.2.2), so one
        // association proposes at most `maxPresentationContextsPerAssociation`
        // SOP Classes; the distinct classes are partitioned into groups and
        // each group gets its own association (see `presentationContextGroups`).
        let contextGroups = Self.presentationContextGroups(fileInfos.map { $0.info.sopClassUID })
        var stopped = false

        for group in contextGroups where !stopped {
            let groupSet = Set(group)

            // Create presentation contexts for the SOP Classes of this group
            var presentationContexts: [PresentationContext] = []
            var contextID: UInt8 = 1
            var sopClassToContextID: [String: UInt8] = [:]

            for sopClassUID in group {
                let transferSyntaxes = [
                    explicitVRLittleEndianTransferSyntaxUID,
                    implicitVRLittleEndianTransferSyntaxUID
                ]
            
                do {
                    let context = try PresentationContext(
                        id: contextID,
                        abstractSyntax: sopClassUID,
                        transferSyntaxes: transferSyntaxes
                    )
                    presentationContexts.append(context)
                    sopClassToContextID[sopClassUID] = contextID
                    contextID += 2 // Presentation Context IDs must be odd numbers
                } catch {
                    // Skip invalid SOP classes
                    continue
                }
            }
        
            // Establish association
            let association = Association(configuration: associationConfig)
        
            do {
                var negotiated = try await association.request(presentationContexts: presentationContexts)
            
                var filesStoredOnAssociation = 0
                var messageID: UInt16 = 1
            
                // Store each file of this group's SOP Classes
                for (index, fileData, fileInfo) in fileInfos where groupSet.contains(fileInfo.sopClassUID) {
                    try Task.checkCancellation()

                    let fileStartTime = Date()
                
                    // Check if we need to start a new association
                    if batchConfiguration.maxFilesPerAssociation > 0 &&
                       filesStoredOnAssociation >= batchConfiguration.maxFilesPerAssociation {
                        // Release current association and create new one
                        try? await association.release()
                        negotiated = try await association.request(presentationContexts: presentationContexts)
                        filesStoredOnAssociation = 0
                        messageID = 1
                    }
                
                    // Add delay if configured
                    if batchConfiguration.delayBetweenFiles > 0 && index > 0 {
                        try await Task.sleep(for: .seconds(batchConfiguration.delayBetweenFiles))
                    }
                
                    // Get the presentation context ID for this SOP Class
                    guard let pcID = sopClassToContextID[fileInfo.sopClassUID],
                          negotiated.isContextAccepted(pcID) else {
                        // SOP Class not accepted
                        let fileResult = FileStoreResult(
                            index: index,
                            sopInstanceUID: fileInfo.sopInstanceUID,
                            sopClassUID: fileInfo.sopClassUID,
                            success: false,
                            status: .refusedSOPClassNotSupported,
                            roundTripTime: Date().timeIntervalSince(fileStartTime),
                            fileSize: fileData.count,
                            errorMessage: "SOP Class not supported: \(fileInfo.sopClassUID)"
                        )
                        fileResults.append(fileResult)
                        failed += 1
                    
                        continuation.yield(.fileResult(fileResult))
                        continuation.yield(.progress(BatchStoreProgress(
                            total: total, succeeded: succeeded, failed: failed, warnings: warnings
                        )))
                    
                        if !batchConfiguration.continueOnError {
                            try? await association.release()
                            stopped = true
                            break
                        }
                        continue
                    }
                
                    do {
                        // Perform C-STORE for this file
                        let response = try await performCStoreWithMessageID(
                            association: association,
                            presentationContextID: pcID,
                            maxPDUSize: negotiated.maxPDUSize,
                            sopClassUID: fileInfo.sopClassUID,
                            sopInstanceUID: fileInfo.sopInstanceUID,
                            priority: configuration.priority,
                            dataSetData: fileInfo.dataSetData,
                            messageID: messageID,
                            moveOriginatorAETitle: configuration.moveOriginatorAETitle,
                            moveOriginatorMessageID: configuration.moveOriginatorMessageID
                        )
                    
                        let roundTripTime = Date().timeIntervalSince(fileStartTime)
                        messageID += 1
                        filesStoredOnAssociation += 1
                        totalBytesTransferred += fileData.count
                    
                        let isSuccess = response.status.isSuccess || response.status.isWarning
                        let fileResult = FileStoreResult(
                            index: index,
                            sopInstanceUID: fileInfo.sopInstanceUID,
                            sopClassUID: fileInfo.sopClassUID,
                            success: isSuccess,
                            status: response.status,
                            roundTripTime: roundTripTime,
                            fileSize: fileData.count,
                            errorMessage: isSuccess ? nil : "Store failed with status: \(response.status)"
                        )
                        fileResults.append(fileResult)
                    
                        // Categorize by status: warnings are counted separately from pure successes
                        // Both warnings and pure successes have FileStoreResult.success = true
                        // but are tracked in different counters for reporting purposes
                        if response.status.isWarning {
                            warnings += 1
                        } else if isSuccess {
                            succeeded += 1
                        } else {
                            failed += 1
                        }
                    
                        continuation.yield(.fileResult(fileResult))
                        continuation.yield(.progress(BatchStoreProgress(
                            total: total, succeeded: succeeded, failed: failed, warnings: warnings
                        )))
                    
                        if !isSuccess && !batchConfiguration.continueOnError {
                            try? await association.release()
                            stopped = true
                            break
                        }
                    
                    } catch {
                        let roundTripTime = Date().timeIntervalSince(fileStartTime)
                        let fileResult = FileStoreResult(
                            index: index,
                            sopInstanceUID: fileInfo.sopInstanceUID,
                            sopClassUID: fileInfo.sopClassUID,
                            success: false,
                            status: .failedUnableToProcess,
                            roundTripTime: roundTripTime,
                            fileSize: fileData.count,
                            errorMessage: error.localizedDescription
                        )
                        fileResults.append(fileResult)
                        failed += 1
                    
                        continuation.yield(.fileResult(fileResult))
                        continuation.yield(.progress(BatchStoreProgress(
                            total: total, succeeded: succeeded, failed: failed, warnings: warnings
                        )))
                    
                        if !batchConfiguration.continueOnError {
                            try? await association.release()
                            stopped = true
                            break
                        }
                    }
                }
            
                // Release association
                try? await association.release()
            
            } catch {
                // Association establishment failed
                try? await association.abort()
                throw error
            }
        } // for group

        // Complete the stream
        let totalTime = Date().timeIntervalSince(startTime)
        let result = BatchStoreResult(
            progress: BatchStoreProgress(total: total, succeeded: succeeded, failed: failed, warnings: warnings),
            fileResults: fileResults,
            totalBytesTransferred: totalBytesTransferred,
            totalTime: totalTime
        )
        continuation.yield(.completed(result))
        continuation.finish()
    }
    
    /// Maximum number of presentation contexts one association can propose:
    /// PS3.8 9.3.2.2 gives presentation context IDs the odd values 1...255.
    static let maxPresentationContextsPerAssociation = 128

    /// Partitions SOP Class UIDs into groups that fit one association each
    /// (at most `maxPresentationContextsPerAssociation` distinct classes),
    /// preserving first-appearance order and dropping duplicates. Every class
    /// appears in exactly one group; an empty input yields no groups.
    static func presentationContextGroups(_ sopClassUIDs: [String]) -> [[String]] {
        var seen = Set<String>()
        var unique: [String] = []
        for uid in sopClassUIDs where seen.insert(uid).inserted {
            unique.append(uid)
        }
        let size = maxPresentationContextsPerAssociation
        return stride(from: 0, to: unique.count, by: size).map { start in
            Array(unique[start..<min(start + size, unique.count)])
        }
    }

    /// The C-STORE-RQ command (PS3.7 2026a Table 9.3-1). Move Originator AE Title
    /// (0000,1030) and Move Originator Message ID (0000,1031) are written only as a
    /// pair, when both are given (9.1.1.1.6 / 9.1.1.1.7). `internal` for unit tests.
    static func cStoreRequest(
        messageID: UInt16,
        sopClassUID: String,
        sopInstanceUID: String,
        priority: DIMSEPriority,
        moveOriginatorAETitle: String?,
        moveOriginatorMessageID: UInt16?,
        presentationContextID: UInt8
    ) -> CStoreRequest {
        let pair = moveOriginatorAETitle.flatMap { ae in moveOriginatorMessageID.map { (ae, $0) } }
        return CStoreRequest(
            messageID: messageID,
            affectedSOPClassUID: sopClassUID,
            affectedSOPInstanceUID: sopInstanceUID,
            priority: priority,
            moveOriginatorAETitle: pair?.0,
            moveOriginatorMessageID: pair?.1,
            presentationContextID: presentationContextID
        )
    }

    /// Performs the C-STORE request/response exchange with a specific message ID
    private static func performCStoreWithMessageID(
        association: Association,
        presentationContextID: UInt8,
        maxPDUSize: UInt32,
        sopClassUID: String,
        sopInstanceUID: String,
        priority: DIMSEPriority,
        dataSetData: Data,
        messageID: UInt16,
        moveOriginatorAETitle: String? = nil,
        moveOriginatorMessageID: UInt16? = nil
    ) async throws -> CStoreResponse {
        // Create C-STORE request
        let request = cStoreRequest(
            messageID: messageID,
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            priority: priority,
            moveOriginatorAETitle: moveOriginatorAETitle,
            moveOriginatorMessageID: moveOriginatorMessageID,
            presentationContextID: presentationContextID
        )
        
        // Fragment and send the command and data set
        let fragmenter = MessageFragmenter(maxPDUSize: maxPDUSize)
        let pdus = fragmenter.fragmentMessage(
            commandSet: request.commandSet,
            dataSet: dataSetData,
            presentationContextID: presentationContextID
        )
        
        // Send all PDUs
        for pdu in pdus {
            for pdv in pdu.presentationDataValues {
                try await association.send(pdv: pdv)
            }
        }
        
        // Receive response
        let assembler = MessageAssembler()
        
        while true {
            let responsePDU = try await association.receive()
            
            if let message = try assembler.addPDVs(from: responsePDU) {
                guard let storeResponse = message.asCStoreResponse() else {
                    throw DICOMNetworkError.decodingFailed(
                        "Expected C-STORE-RSP, got \(message.command?.description ?? "unknown")"
                    )
                }
                return storeResponse
            }
        }
    }
}

// MARK: - DICOM File Parser for Storage

/// Internal parser for extracting storage-relevant information from DICOM files
struct DICOMFileParser {
    let data: Data
    
    /// Information extracted from a DICOM file for storage
    struct FileInfo {
        let sopClassUID: String
        let sopInstanceUID: String
        let transferSyntaxUID: String
        let dataSetData: Data
    }
    
    /// Parses the file and extracts information needed for C-STORE
    func parseForStorage() throws -> FileInfo {
        // Validate minimum size (128-byte preamble + 4-byte "DICM")
        guard data.count >= 132 else {
            throw DICOMError.unexpectedEndOfData
        }
        
        // Validate "DICM" prefix at offset 128
        let dicmOffset = 128
        let dicmBytes = data[dicmOffset..<dicmOffset+4]
        guard dicmBytes.elementsEqual([0x44, 0x49, 0x43, 0x4D]) else { // "DICM" in ASCII
            throw DICOMError.invalidDICMPrefix
        }
        
        // Parse File Meta Information to get:
        // - SOP Class UID from (0002,0002) Media Storage SOP Class UID
        // - SOP Instance UID from (0002,0003) Media Storage SOP Instance UID
        // - Transfer Syntax UID from (0002,0010)
        // - End of File Meta Information from (0002,0000) File Meta Information Group Length
        
        var offset = 132 // Start after "DICM"
        var sopClassUID: String?
        var sopInstanceUID: String?
        var transferSyntaxUID: String?
        var fileMetaInfoLength: UInt32?
        
        // File Meta Information uses Explicit VR Little Endian
        while offset < data.count {
            // Read tag
            guard offset + 4 <= data.count else { break }
            guard let group = data.readUInt16LE(at: offset),
                  let element = data.readUInt16LE(at: offset + 2) else { break }
            offset += 4
            
            // Stop when we exit Group 0002
            if group != 0x0002 {
                // Back up to the start of this element - this is the start of the data set
                offset -= 4
                break
            }
            
            // Read VR (2 bytes for Explicit VR)
            guard offset + 2 <= data.count else { break }
            let vrBytes = data.subdata(in: offset..<offset+2)
            let vrString = String(data: vrBytes, encoding: .ascii) ?? "UN"
            offset += 2
            
            // Determine value length
            let valueLength: UInt32
            let vr = VR(rawValue: vrString) ?? .UN
            
            if vr.uses32BitLength {
                // Skip reserved 2 bytes, read 4-byte length
                guard offset + 6 <= data.count else { break }
                offset += 2
                guard let length = data.readUInt32LE(at: offset) else { break }
                valueLength = length
                offset += 4
            } else {
                // Read 2-byte length
                guard offset + 2 <= data.count else { break }
                guard let length = data.readUInt16LE(at: offset) else { break }
                valueLength = UInt32(length)
                offset += 2
            }
            
            // Read value
            guard valueLength != 0xFFFFFFFF else { break } // Undefined length not expected in FMI
            guard offset + Int(valueLength) <= data.count else { break }
            let valueData = data.subdata(in: offset..<offset+Int(valueLength))
            offset += Int(valueLength)
            
            // Extract specific elements
            let tag = Tag(group: group, element: element)
            
            switch tag {
            case Tag(group: 0x0002, element: 0x0000): // File Meta Information Group Length
                if valueLength == 4 {
                    fileMetaInfoLength = valueData.readUInt32LE(at: 0)
                }
            case Tag(group: 0x0002, element: 0x0002): // Media Storage SOP Class UID
                sopClassUID = String(data: valueData, encoding: .ascii)?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
            case Tag(group: 0x0002, element: 0x0003): // Media Storage SOP Instance UID
                sopInstanceUID = String(data: valueData, encoding: .ascii)?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
            case Tag(group: 0x0002, element: 0x0010): // Transfer Syntax UID
                transferSyntaxUID = String(data: valueData, encoding: .ascii)?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
            default:
                break
            }
        }
        
        // If we have File Meta Info Group Length, use it to find exact data set start.
        // The (0002,0000) element itself is 12 bytes (tag 4 + VR "UL" 2 + len 2 + value 4)
        // and is NOT included in fmiLength.  Dataset starts at:
        //   preamble(128) + "DICM"(4) + (0002,0000)(12) + fmiLength = 144 + fmiLength
        if let fmiLength = fileMetaInfoLength {
            offset = 144 + Int(fmiLength)
        }
        
        // Validate required fields
        guard let finalSOPClassUID = sopClassUID, !finalSOPClassUID.isEmpty else {
            throw DICOMError.parsingFailed("Missing required element: Media Storage SOP Class UID (0002,0002)")
        }
        
        guard let finalSOPInstanceUID = sopInstanceUID, !finalSOPInstanceUID.isEmpty else {
            throw DICOMError.parsingFailed("Missing required element: Media Storage SOP Instance UID (0002,0003)")
        }
        
        let finalTransferSyntax = transferSyntaxUID ?? explicitVRLittleEndianTransferSyntaxUID
        
        // Extract data set (everything after File Meta Information)
        guard offset < data.count else {
            throw DICOMError.unexpectedEndOfData
        }
        let dataSetData = data.subdata(in: offset..<data.count)
        
        return FileInfo(
            sopClassUID: finalSOPClassUID,
            sopInstanceUID: finalSOPInstanceUID,
            transferSyntaxUID: finalTransferSyntax,
            dataSetData: dataSetData
        )
    }
}

#endif
