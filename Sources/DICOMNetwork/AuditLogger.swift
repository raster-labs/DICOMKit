import Foundation
#if canImport(os)
import os
// NEMA-verified: 2026a, checked 2026-09-28 — carries no DICOM-standard data: event names and JSON-Lines schema are DICOMKit's own, not the PS3.15 2026a Annex A.5 audit message format (header says so)
#endif

// MARK: - Audit Event Type

/// Types of auditable DICOM network events
///
/// These are DICOMKit's own event names for a local JSON-Lines / OSLog audit trail. They
/// are *not* the PS3.15 Annex A.5 Audit Trail Message Format (the DCM 1101xx EventID /
/// EventTypeCode codes, ActiveParticipant and ParticipantObjectIdentification of the
/// RFC 3881 schema used by IHE ATNA); the outcome names mirror the A.5.1
/// EventOutcomeIndicator meanings only. Producing conformant ATNA messages is a separate
/// feature; nothing here claims it.
///
/// Reference: DICOM PS3.15 Annex A.5 (for what an audit message would have to carry)
/// Reference: IHE ITI TF-2a - Audit Trail and Node Authentication
public enum AuditEventType: String, Sendable, CaseIterable {
    /// Association establishment (successful or failed)
    case associationEstablished = "ASSOCIATION_ESTABLISHED"
    
    /// Association rejection
    case associationRejected = "ASSOCIATION_REJECTED"
    
    /// Association release (graceful disconnection)
    case associationReleased = "ASSOCIATION_RELEASED"
    
    /// Association abort (abnormal termination)
    case associationAborted = "ASSOCIATION_ABORTED"
    
    /// C-STORE operation (sending DICOM object)
    case storeSent = "STORE_SENT"
    
    /// C-STORE operation (receiving DICOM object)
    case storeReceived = "STORE_RECEIVED"
    
    /// C-FIND query operation
    case queryExecuted = "QUERY_EXECUTED"
    
    /// C-MOVE retrieve operation
    case retrieveMoveStarted = "RETRIEVE_MOVE_STARTED"
    
    /// C-MOVE retrieve completed
    case retrieveMoveCompleted = "RETRIEVE_MOVE_COMPLETED"
    
    /// C-GET retrieve operation
    case retrieveGetStarted = "RETRIEVE_GET_STARTED"
    
    /// C-GET retrieve completed
    case retrieveGetCompleted = "RETRIEVE_GET_COMPLETED"
    
    /// C-ECHO verification operation
    case verificationPerformed = "VERIFICATION_PERFORMED"
    
    /// Storage commitment requested
    case commitmentRequested = "COMMITMENT_REQUESTED"
    
    /// Storage commitment result received
    case commitmentResultReceived = "COMMITMENT_RESULT_RECEIVED"
    
    /// Connection established
    case connectionEstablished = "CONNECTION_ESTABLISHED"
    
    /// Connection failed
    case connectionFailed = "CONNECTION_FAILED"
    
    /// Security event (e.g., authentication failure)
    case securityEvent = "SECURITY_EVENT"
}

extension AuditEventType: CustomStringConvertible {
    public var description: String {
        rawValue
    }
}

// MARK: - Audit Event Outcome

/// Outcome of an auditable event
///
/// Indicates whether the operation succeeded, failed, or completed with warnings.
public enum AuditEventOutcome: String, Sendable, Hashable {
    /// Operation completed successfully
    case success = "SUCCESS"
    
    /// Operation completed with minor errors or warnings
    case minorFailure = "MINOR_FAILURE"
    
    /// Operation completed with serious warnings
    case seriousFailure = "SERIOUS_FAILURE"
    
    /// Operation failed completely
    case majorFailure = "MAJOR_FAILURE"
}

extension AuditEventOutcome: CustomStringConvertible {
    public var description: String {
        rawValue
    }
}

// MARK: - Audit Participant

/// Information about a participant in an auditable event
///
/// Represents either the source (initiator) or destination (responder) of a DICOM operation.
public struct AuditParticipant: Sendable, Hashable {
    /// Application Entity Title
    public let aeTitle: String
    
    /// Host address (IP or hostname)
    public let host: String
    
    /// Port number
    public let port: UInt16
    
    /// Whether this participant is the requestor/initiator
    public let isRequestor: Bool
    
    /// User identity information (if available)
    public let userIdentity: String?
    
    /// Creates an audit participant
    ///
    /// - Parameters:
    ///   - aeTitle: The Application Entity Title
    ///   - host: The host address
    ///   - port: The port number
    ///   - isRequestor: Whether this is the initiating party
    ///   - userIdentity: Optional user identity information
    public init(
        aeTitle: String,
        host: String,
        port: UInt16,
        isRequestor: Bool,
        userIdentity: String? = nil
    ) {
        self.aeTitle = aeTitle
        self.host = host
        self.port = port
        self.isRequestor = isRequestor
        self.userIdentity = userIdentity
    }
}

extension AuditParticipant: CustomStringConvertible {
    public var description: String {
        let role = isRequestor ? "requestor" : "responder"
        let identity = userIdentity.map { " user=\($0)" } ?? ""
        return "\(aeTitle)@\(host):\(port) (\(role))\(identity)"
    }
}

// MARK: - Audit Log Entry

/// A comprehensive audit log entry for DICOM network operations
///
/// Contains all the information needed to create a compliant audit trail
/// for healthcare system monitoring and regulatory compliance.
///
/// ## Usage
///
/// ```swift
/// let entry = AuditLogEntry(
///     eventType: .storeSent,
///     outcome: .success,
///     source: AuditParticipant(aeTitle: "CLIENT_AE", host: "10.0.0.1", port: 11112, isRequestor: true),
///     destination: AuditParticipant(aeTitle: "PACS_AE", host: "10.0.0.2", port: 11112, isRequestor: false),
///     sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
///     sopInstanceUID: "1.2.3.4.5.6.7.8.9",
///     studyInstanceUID: "1.2.3.4.5",
///     patientID: "PATIENT123",
///     bytesTransferred: 524288,
///     duration: 1.5
/// )
/// ```
///
/// Reference: IHE ITI TF-2a - Audit Trail and Node Authentication
/// Reference: DICOM PS3.15 - Security and System Management Profiles
public struct AuditLogEntry: Sendable {
    // MARK: - Event Information
    
    /// Unique identifier for this audit entry
    public let id: UUID
    
    /// Type of the auditable event
    public let eventType: AuditEventType
    
    /// Outcome of the event
    public let outcome: AuditEventOutcome
    
    /// Timestamp when the event occurred
    public let timestamp: Date
    
    // MARK: - Participants
    
    /// The source (initiator) of the operation
    public let source: AuditParticipant
    
    /// The destination (responder) of the operation
    public let destination: AuditParticipant?
    
    // MARK: - DICOM Object Information
    
    /// SOP Class UID (if applicable)
    public let sopClassUID: String?
    
    /// SOP Instance UID (if applicable)
    public let sopInstanceUID: String?
    
    /// Study Instance UID (if applicable)
    public let studyInstanceUID: String?
    
    /// Series Instance UID (if applicable)
    public let seriesInstanceUID: String?
    
    /// Patient ID (if applicable, for audit purposes only)
    /// Note: Should be handled according to privacy regulations
    public let patientID: String?
    
    /// Accession Number (if applicable)
    public let accessionNumber: String?
    
    // MARK: - Transfer Information
    
    /// Number of bytes transferred
    public let bytesTransferred: Int64?
    
    /// Duration of the operation in seconds
    public let duration: TimeInterval?
    
    /// Number of instances involved (for batch/retrieve operations)
    public let instanceCount: Int?
    
    // MARK: - Status Information
    
    /// DICOM status code from the response
    public let statusCode: UInt16?
    
    /// Error message if the operation failed
    public let errorMessage: String?
    
    // MARK: - Additional Context
    
    /// Additional metadata for the event
    public let metadata: [String: String]
    
    // MARK: - Initialization
    
    /// Creates an audit log entry
    ///
    /// - Parameters:
    ///   - eventType: Type of the auditable event
    ///   - outcome: Outcome of the event
    ///   - source: The initiator of the operation
    ///   - destination: The responder of the operation (optional)
    ///   - sopClassUID: SOP Class UID (optional)
    ///   - sopInstanceUID: SOP Instance UID (optional)
    ///   - studyInstanceUID: Study Instance UID (optional)
    ///   - seriesInstanceUID: Series Instance UID (optional)
    ///   - patientID: Patient ID (optional)
    ///   - accessionNumber: Accession Number (optional)
    ///   - bytesTransferred: Bytes transferred (optional)
    ///   - duration: Operation duration in seconds (optional)
    ///   - instanceCount: Number of instances (optional)
    ///   - statusCode: DICOM status code (optional)
    ///   - errorMessage: Error message if failed (optional)
    ///   - metadata: Additional metadata (optional)
    public init(
        eventType: AuditEventType,
        outcome: AuditEventOutcome,
        source: AuditParticipant,
        destination: AuditParticipant? = nil,
        sopClassUID: String? = nil,
        sopInstanceUID: String? = nil,
        studyInstanceUID: String? = nil,
        seriesInstanceUID: String? = nil,
        patientID: String? = nil,
        accessionNumber: String? = nil,
        bytesTransferred: Int64? = nil,
        duration: TimeInterval? = nil,
        instanceCount: Int? = nil,
        statusCode: UInt16? = nil,
        errorMessage: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = UUID()
        self.eventType = eventType
        self.outcome = outcome
        self.timestamp = Date()
        self.source = source
        self.destination = destination
        self.sopClassUID = sopClassUID
        self.sopInstanceUID = sopInstanceUID
        self.studyInstanceUID = studyInstanceUID
        self.seriesInstanceUID = seriesInstanceUID
        self.patientID = patientID
        self.accessionNumber = accessionNumber
        self.bytesTransferred = bytesTransferred
        self.duration = duration
        self.instanceCount = instanceCount
        self.statusCode = statusCode
        self.errorMessage = errorMessage
        self.metadata = metadata
    }
}

extension AuditLogEntry: CustomStringConvertible {
    public var description: String {
        var parts = [String]()
        parts.append("[\(eventType.rawValue)]")
        parts.append("[\(outcome.rawValue)]")
        parts.append("source=\(source)")
        if let dest = destination {
            parts.append("dest=\(dest)")
        }
        if let sopClass = sopClassUID {
            parts.append("sopClass=\(sopClass)")
        }
        if let sopInstance = sopInstanceUID {
            parts.append("sopInstance=\(sopInstance)")
        }
        if let bytes = bytesTransferred {
            parts.append("bytes=\(bytes)")
        }
        if let dur = duration {
            parts.append("duration=\(String(format: "%.3f", dur))s")
        }
        if let status = statusCode {
            parts.append("status=0x\(String(format: "%04X", status))")
        }
        if let error = errorMessage {
            parts.append("error=\(error)")
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Audit Log Handler Protocol

/// Protocol for handling audit log entries
///
/// Implement this protocol to receive audit events and process them
/// (e.g., write to file, send to SIEM system, store in database).
///
/// ## Example Implementation
///
/// ```swift
/// final class SIEMHandler: AuditLogHandler {
///     func handleAuditEvent(_ entry: AuditLogEntry) {
///         // Forward to SIEM system
///         siemClient.send(entry.toJSON())
///     }
/// }
/// ```
public protocol AuditLogHandler: Sendable {
    /// Handles an audit log entry
    ///
    /// - Parameter entry: The audit log entry to handle
    func handleAuditEvent(_ entry: AuditLogEntry)
}

// MARK: - Console Audit Log Handler

/// Simple console-based audit log handler for debugging
///
/// Outputs formatted audit entries to standard output.
/// Useful for development and debugging.
public final class ConsoleAuditLogHandler: AuditLogHandler {
    /// Date formatter for timestamps
    private let dateFormatter: DateFormatter
    
    /// Whether to include detailed information
    public let verbose: Bool
    
    /// Creates a console audit log handler
    ///
    /// - Parameter verbose: Whether to include detailed information (default: true)
    public init(verbose: Bool = true) {
        self.verbose = verbose
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }
    
    public func handleAuditEvent(_ entry: AuditLogEntry) {
        var output = "AUDIT [\(dateFormatter.string(from: entry.timestamp))] "
        output += "[\(entry.eventType.rawValue)] [\(entry.outcome.rawValue)]"
        
        if verbose {
            output += "\n  Source: \(entry.source)"
            if let dest = entry.destination {
                output += "\n  Destination: \(dest)"
            }
            if let sopClass = entry.sopClassUID {
                output += "\n  SOP Class: \(sopClass)"
            }
            if let sopInstance = entry.sopInstanceUID {
                output += "\n  SOP Instance: \(sopInstance)"
            }
            if let study = entry.studyInstanceUID {
                output += "\n  Study: \(study)"
            }
            if let bytes = entry.bytesTransferred {
                output += "\n  Bytes: \(bytes)"
            }
            if let duration = entry.duration {
                output += "\n  Duration: \(String(format: "%.3f", duration))s"
            }
            if let status = entry.statusCode {
                output += "\n  Status: 0x\(String(format: "%04X", status))"
            }
            if let error = entry.errorMessage {
                output += "\n  Error: \(error)"
            }
            if !entry.metadata.isEmpty {
                output += "\n  Metadata: \(entry.metadata)"
            }
        }
        
        print(output)
    }
}

// MARK: - File Audit Log Handler

/// File-based audit log handler with log rotation support
///
/// Writes audit entries to a file in JSON Lines format (one JSON object per line).
/// Supports automatic log rotation based on file size.
///
/// ## Usage
///
/// ```swift
/// let handler = try FileAuditLogHandler(
///     directory: URL(fileURLWithPath: "/var/log/dicom"),
///     maxFileSize: 10 * 1024 * 1024, // 10 MB
///     maxFiles: 10
/// )
/// await AuditLogger.shared.addHandler(handler)
/// ```
///
/// ## Thread Safety
///
/// This class uses `@unchecked Sendable` because all file operations are
/// serialized through a dedicated serial `DispatchQueue` (`queue`). The
/// `queue.sync` calls in `handleAuditEvent` ensure that concurrent calls
/// to write audit entries are properly synchronized. The immutable properties
/// (directory, baseName, maxFileSize, maxFiles) are set during initialization
/// and never modified. The mutable state (fileHandle, currentFileSize) is
/// only accessed within the serialized queue operations.
public final class FileAuditLogHandler: AuditLogHandler, @unchecked Sendable {
    /// Directory where log files are stored
    public let directory: URL
    
    /// Base name for log files
    public let baseName: String
    
    /// Maximum size of a single log file in bytes before rotation
    public let maxFileSize: Int64
    
    /// Maximum number of rotated log files to keep
    public let maxFiles: Int
    
    /// File manager
    private let fileManager: FileManager
    
    /// Date formatter for JSON output
    private let dateFormatter: ISO8601DateFormatter
    
    /// Serialization queue for thread-safe file operations
    private let queue: DispatchQueue
    
    /// Current log file handle
    private var fileHandle: FileHandle?
    
    /// Current file size
    private var currentFileSize: Int64 = 0
    
    /// Creates a file audit log handler
    ///
    /// - Parameters:
    ///   - directory: Directory where log files are stored
    ///   - baseName: Base name for log files (default: "dicom_audit")
    ///   - maxFileSize: Maximum size per file in bytes (default: 50 MB)
    ///   - maxFiles: Maximum number of rotated files to keep (default: 10)
    /// - Throws: Error if directory cannot be created or accessed
    public init(
        directory: URL,
        baseName: String = "dicom_audit",
        maxFileSize: Int64 = 50 * 1024 * 1024,
        maxFiles: Int = 10
    ) throws {
        self.directory = directory
        self.baseName = baseName
        self.maxFileSize = maxFileSize
        self.maxFiles = max(1, maxFiles)
        self.fileManager = FileManager.default
        self.dateFormatter = ISO8601DateFormatter()
        self.dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.queue = DispatchQueue(label: "com.dicomkit.audit.file", qos: .utility)
        
        // Create directory if it doesn't exist
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        
        // Open initial log file
        try openLogFile()
    }
    
    deinit {
        try? fileHandle?.close()
    }
    
    public func handleAuditEvent(_ entry: AuditLogEntry) {
        queue.sync {
            writeEntry(entry)
        }
    }
    
    /// Writes an entry to the log file
    private func writeEntry(_ entry: AuditLogEntry) {
        guard let jsonData = try? encodeEntry(entry),
              var line = String(data: jsonData, encoding: .utf8) else {
            return
        }
        
        // Add newline for JSON Lines format
        line += "\n"
        
        guard let lineData = line.data(using: .utf8) else {
            return
        }
        
        // Check if rotation is needed
        if currentFileSize + Int64(lineData.count) > maxFileSize {
            rotateLogFile()
        }
        
        // Write to file
        do {
            try fileHandle?.write(contentsOf: lineData)
            currentFileSize += Int64(lineData.count)
        } catch {
            // Silently fail - audit logging should not crash the application
        }
    }
    
    /// Encodes an entry to JSON
    private func encodeEntry(_ entry: AuditLogEntry) throws -> Data {
        var dict: [String: Any] = [
            "id": entry.id.uuidString,
            "eventType": entry.eventType.rawValue,
            "outcome": entry.outcome.rawValue,
            "timestamp": dateFormatter.string(from: entry.timestamp),
            "source": [
                "aeTitle": entry.source.aeTitle,
                "host": entry.source.host,
                "port": entry.source.port,
                "isRequestor": entry.source.isRequestor
            ] as [String: Any]
        ]
        
        if let userIdentity = entry.source.userIdentity {
            var sourceDict = dict["source"] as! [String: Any]
            sourceDict["userIdentity"] = userIdentity
            dict["source"] = sourceDict
        }
        
        if let dest = entry.destination {
            var destDict: [String: Any] = [
                "aeTitle": dest.aeTitle,
                "host": dest.host,
                "port": dest.port,
                "isRequestor": dest.isRequestor
            ]
            if let userIdentity = dest.userIdentity {
                destDict["userIdentity"] = userIdentity
            }
            dict["destination"] = destDict
        }
        
        if let sopClass = entry.sopClassUID {
            dict["sopClassUID"] = sopClass
        }
        if let sopInstance = entry.sopInstanceUID {
            dict["sopInstanceUID"] = sopInstance
        }
        if let study = entry.studyInstanceUID {
            dict["studyInstanceUID"] = study
        }
        if let series = entry.seriesInstanceUID {
            dict["seriesInstanceUID"] = series
        }
        if let patient = entry.patientID {
            dict["patientID"] = patient
        }
        if let accession = entry.accessionNumber {
            dict["accessionNumber"] = accession
        }
        if let bytes = entry.bytesTransferred {
            dict["bytesTransferred"] = bytes
        }
        if let duration = entry.duration {
            dict["duration"] = duration
        }
        if let count = entry.instanceCount {
            dict["instanceCount"] = count
        }
        if let status = entry.statusCode {
            dict["statusCode"] = status
        }
        if let error = entry.errorMessage {
            dict["errorMessage"] = error
        }
        if !entry.metadata.isEmpty {
            dict["metadata"] = entry.metadata
        }
        
        return try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
    }
    
    /// Opens the current log file for writing
    private func openLogFile() throws {
        let filePath = directory.appendingPathComponent("\(baseName).jsonl")
        
        // Create file if it doesn't exist
        if !fileManager.fileExists(atPath: filePath.path) {
            _ = fileManager.createFile(atPath: filePath.path, contents: nil)
        }
        
        fileHandle = try FileHandle(forWritingTo: filePath)
        try fileHandle?.seekToEnd()
        
        // Get current file size
        if let attrs = try? fileManager.attributesOfItem(atPath: filePath.path),
           let size = attrs[.size] as? Int64 {
            currentFileSize = size
        } else {
            currentFileSize = 0
        }
    }
    
    /// Rotates log files
    private func rotateLogFile() {
        // Close current file
        try? fileHandle?.close()
        fileHandle = nil
        
        let currentPath = directory.appendingPathComponent("\(baseName).jsonl")
        
        // Delete oldest file if we have too many
        let oldestPath = directory.appendingPathComponent("\(baseName).\(maxFiles).jsonl")
        try? fileManager.removeItem(at: oldestPath)
        
        // Shift existing rotated files
        for i in stride(from: maxFiles - 1, through: 1, by: -1) {
            let from = directory.appendingPathComponent("\(baseName).\(i).jsonl")
            let to = directory.appendingPathComponent("\(baseName).\(i + 1).jsonl")
            try? fileManager.moveItem(at: from, to: to)
        }
        
        // Rotate current file
        let newPath = directory.appendingPathComponent("\(baseName).1.jsonl")
        try? fileManager.moveItem(at: currentPath, to: newPath)
        
        // Open new file
        try? openLogFile()
    }
}

// MARK: - OSLog Audit Handler

#if canImport(os)

/// Audit log handler using Apple's Unified Logging System
///
/// Integrates audit logging with the system's unified logging for
/// correlation with other system events.
public final class OSLogAuditHandler: AuditLogHandler {
    /// The OSLog instance for audit events
    private let log: OSLog
    
    /// Creates an OSLog audit handler
    ///
    /// - Parameter subsystem: The subsystem identifier (default: "com.dicomkit.audit")
    public init(subsystem: String = "com.dicomkit.audit") {
        self.log = OSLog(subsystem: subsystem, category: "Audit")
    }
    
    public func handleAuditEvent(_ entry: AuditLogEntry) {
        let logType: OSLogType = switch entry.outcome {
        case .success:
            .info
        case .minorFailure:
            .default
        case .seriousFailure:
            .error
        case .majorFailure:
            .fault
        }
        
        // Create a concise but complete log message
        var message = "[\(entry.eventType.rawValue)] [\(entry.outcome.rawValue)] "
        message += "src=\(entry.source.aeTitle)@\(entry.source.host):\(entry.source.port)"
        
        if let dest = entry.destination {
            message += " dst=\(dest.aeTitle)@\(dest.host):\(dest.port)"
        }
        
        if let sopClass = entry.sopClassUID {
            message += " sopClass=\(sopClass)"
        }
        
        if let sopInstance = entry.sopInstanceUID {
            message += " sopInstance=\(sopInstance)"
        }
        
        if let bytes = entry.bytesTransferred {
            message += " bytes=\(bytes)"
        }
        
        if let duration = entry.duration {
            message += " duration=\(String(format: "%.3f", duration))s"
        }
        
        if let status = entry.statusCode {
            message += " status=0x\(String(format: "%04X", status))"
        }
        
        if let error = entry.errorMessage {
            message += " error=\(error)"
        }
        
        os_log("%{public}@", log: log, type: logType, message)
    }
}

#endif

// MARK: - Audit Logger

/// Central audit logger for DICOM network operations
///
/// AuditLogger is the main entry point for audit logging in the DICOM networking module.
/// It manages audit handlers and provides convenient methods for logging audit events.
///
/// ## Thread Safety
///
/// AuditLogger is thread-safe and uses actors for internal state management.
///
/// ## Configuration
///
/// Configure the audit logger at app startup:
///
/// ```swift
/// // Enable audit logging with file handler
/// let fileHandler = try FileAuditLogHandler(
///     directory: URL(fileURLWithPath: "/var/log/dicom")
/// )
/// await AuditLogger.shared.addHandler(fileHandler)
///
/// // Also log to console for debugging
/// await AuditLogger.shared.addHandler(ConsoleAuditLogHandler(verbose: true))
///
/// // Enable/disable specific event types
/// await AuditLogger.shared.setEnabledEventTypes([.storeSent, .storeReceived, .queryExecuted])
/// ```
///
/// ## Usage
///
/// ```swift
/// // Log a C-STORE event
/// await AuditLogger.shared.logStoreEvent(
///     outcome: .success,
///     source: source,
///     destination: destination,
///     sopClassUID: sopClass,
///     sopInstanceUID: sopInstance,
///     bytesTransferred: data.count,
///     duration: duration
/// )
/// ```
///
/// Reference: IHE ITI TF-2a - Audit Trail and Node Authentication
/// Reference: DICOM PS3.15 - Security and System Management Profiles
public actor AuditLogger {
    /// Shared singleton instance
    public static let shared = AuditLogger()
    
    /// Registered audit handlers
    private var handlers: [any AuditLogHandler] = []
    
    /// Whether audit logging is enabled
    private var isEnabled: Bool = false
    
    /// Event types to audit (empty = all event types)
    private var enabledEventTypes: Set<AuditEventType> = []
    
    /// Minimum outcome level to log (default: logs all outcomes)
    private var minimumOutcome: AuditEventOutcome? = nil
    
    private init() {}
    
    // MARK: - Configuration
    
    /// Adds an audit log handler
    ///
    /// - Parameter handler: The handler to add
    public func addHandler(_ handler: any AuditLogHandler) {
        handlers.append(handler)
        isEnabled = !handlers.isEmpty
    }
    
    /// Removes all audit log handlers
    public func removeAllHandlers() {
        handlers.removeAll()
        isEnabled = false
    }
    
    /// Sets which event types to audit
    ///
    /// Pass an empty set to audit all event types.
    ///
    /// - Parameter eventTypes: Event types to audit
    public func setEnabledEventTypes(_ eventTypes: Set<AuditEventType>) {
        enabledEventTypes = eventTypes
    }
    
    /// Returns whether audit logging is enabled
    public var isAuditingEnabled: Bool {
        isEnabled
    }
    
    // MARK: - Core Logging
    
    /// Logs an audit entry
    ///
    /// - Parameter entry: The audit entry to log
    public func log(_ entry: AuditLogEntry) {
        guard isEnabled else { return }
        guard enabledEventTypes.isEmpty || enabledEventTypes.contains(entry.eventType) else { return }
        
        for handler in handlers {
            handler.handleAuditEvent(entry)
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Logs an association establishment event
    ///
    /// - Parameters:
    ///   - outcome: Outcome of the association
    ///   - source: The requestor
    ///   - destination: The acceptor
    ///   - acceptedContexts: Number of accepted presentation contexts
    ///   - errorMessage: Error message if failed
    public func logAssociationEstablished(
        outcome: AuditEventOutcome,
        source: AuditParticipant,
        destination: AuditParticipant,
        acceptedContexts: Int? = nil,
        errorMessage: String? = nil
    ) {
        var metadata: [String: String] = [:]
        if let contexts = acceptedContexts {
            metadata["acceptedContexts"] = String(contexts)
        }
        
        let entry = AuditLogEntry(
            eventType: .associationEstablished,
            outcome: outcome,
            source: source,
            destination: destination,
            errorMessage: errorMessage,
            metadata: metadata
        )
        log(entry)
    }
    
    /// Logs an association rejection event
    ///
    /// - Parameters:
    ///   - source: The requestor
    ///   - destination: The rejector
    ///   - reason: Rejection reason
    ///   - resultCode: DICOM result code
    public func logAssociationRejected(
        source: AuditParticipant,
        destination: AuditParticipant,
        reason: String,
        resultCode: UInt16? = nil
    ) {
        let entry = AuditLogEntry(
            eventType: .associationRejected,
            outcome: .majorFailure,
            source: source,
            destination: destination,
            statusCode: resultCode,
            errorMessage: reason
        )
        log(entry)
    }
    
    /// Logs an association release event
    ///
    /// - Parameters:
    ///   - source: The initiator
    ///   - destination: The other party
    public func logAssociationReleased(
        source: AuditParticipant,
        destination: AuditParticipant
    ) {
        let entry = AuditLogEntry(
            eventType: .associationReleased,
            outcome: .success,
            source: source,
            destination: destination
        )
        log(entry)
    }
    
    /// Logs an association abort event
    ///
    /// - Parameters:
    ///   - source: The aborting party
    ///   - destination: The other party
    ///   - reason: Abort reason
    public func logAssociationAborted(
        source: AuditParticipant,
        destination: AuditParticipant,
        reason: String
    ) {
        let entry = AuditLogEntry(
            eventType: .associationAborted,
            outcome: .seriousFailure,
            source: source,
            destination: destination,
            errorMessage: reason
        )
        log(entry)
    }
    
    /// Logs a C-STORE send event
    ///
    /// - Parameters:
    ///   - outcome: Outcome of the store operation
    ///   - source: The sender
    ///   - destination: The receiver
    ///   - sopClassUID: SOP Class UID of the stored object
    ///   - sopInstanceUID: SOP Instance UID of the stored object
    ///   - studyInstanceUID: Study Instance UID (optional)
    ///   - seriesInstanceUID: Series Instance UID (optional)
    ///   - patientID: Patient ID (optional)
    ///   - bytesTransferred: Number of bytes transferred
    ///   - duration: Duration of the operation
    ///   - statusCode: DICOM status code
    ///   - errorMessage: Error message if failed
    public func logStoreSent(
        outcome: AuditEventOutcome,
        source: AuditParticipant,
        destination: AuditParticipant,
        sopClassUID: String?,
        sopInstanceUID: String?,
        studyInstanceUID: String? = nil,
        seriesInstanceUID: String? = nil,
        patientID: String? = nil,
        bytesTransferred: Int64?,
        duration: TimeInterval?,
        statusCode: UInt16?,
        errorMessage: String? = nil
    ) {
        let entry = AuditLogEntry(
            eventType: .storeSent,
            outcome: outcome,
            source: source,
            destination: destination,
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            studyInstanceUID: studyInstanceUID,
            seriesInstanceUID: seriesInstanceUID,
            patientID: patientID,
            bytesTransferred: bytesTransferred,
            duration: duration,
            statusCode: statusCode,
            errorMessage: errorMessage
        )
        log(entry)
    }
    
    /// Logs a C-STORE receive event
    ///
    /// - Parameters:
    ///   - outcome: Outcome of the store operation
    ///   - source: The sender
    ///   - destination: The receiver
    ///   - sopClassUID: SOP Class UID of the received object
    ///   - sopInstanceUID: SOP Instance UID of the received object
    ///   - studyInstanceUID: Study Instance UID (optional)
    ///   - seriesInstanceUID: Series Instance UID (optional)
    ///   - patientID: Patient ID (optional)
    ///   - bytesTransferred: Number of bytes received
    ///   - duration: Duration of the operation
    ///   - statusCode: DICOM status code sent in response
    ///   - errorMessage: Error message if failed
    public func logStoreReceived(
        outcome: AuditEventOutcome,
        source: AuditParticipant,
        destination: AuditParticipant,
        sopClassUID: String?,
        sopInstanceUID: String?,
        studyInstanceUID: String? = nil,
        seriesInstanceUID: String? = nil,
        patientID: String? = nil,
        bytesTransferred: Int64?,
        duration: TimeInterval?,
        statusCode: UInt16?,
        errorMessage: String? = nil
    ) {
        let entry = AuditLogEntry(
            eventType: .storeReceived,
            outcome: outcome,
            source: source,
            destination: destination,
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            studyInstanceUID: studyInstanceUID,
            seriesInstanceUID: seriesInstanceUID,
            patientID: patientID,
            bytesTransferred: bytesTransferred,
            duration: duration,
            statusCode: statusCode,
            errorMessage: errorMessage
        )
        log(entry)
    }
    
    /// Logs a C-FIND query event
    ///
    /// - Parameters:
    ///   - outcome: Outcome of the query
    ///   - source: The querier
    ///   - destination: The query responder
    ///   - queryLevel: Level of the query (PATIENT, STUDY, SERIES, IMAGE)
    ///   - resultCount: Number of results returned
    ///   - duration: Duration of the query
    ///   - errorMessage: Error message if failed
    public func logQueryExecuted(
        outcome: AuditEventOutcome,
        source: AuditParticipant,
        destination: AuditParticipant,
        queryLevel: String,
        resultCount: Int?,
        duration: TimeInterval?,
        errorMessage: String? = nil
    ) {
        var metadata: [String: String] = ["queryLevel": queryLevel]
        if let count = resultCount {
            metadata["resultCount"] = String(count)
        }
        
        let entry = AuditLogEntry(
            eventType: .queryExecuted,
            outcome: outcome,
            source: source,
            destination: destination,
            duration: duration,
            instanceCount: resultCount,
            errorMessage: errorMessage,
            metadata: metadata
        )
        log(entry)
    }
    
    /// Logs a C-MOVE retrieve start event
    ///
    /// - Parameters:
    ///   - source: The retrieve requestor
    ///   - destination: The PACS server
    ///   - moveDestination: The move destination AE title
    ///   - studyInstanceUID: Study being retrieved (optional)
    ///   - seriesInstanceUID: Series being retrieved (optional)
    ///   - sopInstanceUID: Instance being retrieved (optional)
    public func logRetrieveMoveStarted(
        source: AuditParticipant,
        destination: AuditParticipant,
        moveDestination: String,
        studyInstanceUID: String? = nil,
        seriesInstanceUID: String? = nil,
        sopInstanceUID: String? = nil
    ) {
        let entry = AuditLogEntry(
            eventType: .retrieveMoveStarted,
            outcome: .success,
            source: source,
            destination: destination,
            sopInstanceUID: sopInstanceUID,
            studyInstanceUID: studyInstanceUID,
            seriesInstanceUID: seriesInstanceUID,
            metadata: ["moveDestination": moveDestination]
        )
        log(entry)
    }
    
    /// Logs a C-MOVE retrieve completion event
    ///
    /// - Parameters:
    ///   - outcome: Outcome of the retrieve
    ///   - source: The retrieve requestor
    ///   - destination: The PACS server
    ///   - completedCount: Number of successfully retrieved instances
    ///   - failedCount: Number of failed instances
    ///   - duration: Total duration of the retrieve
    ///   - errorMessage: Error message if failed
    public func logRetrieveMoveCompleted(
        outcome: AuditEventOutcome,
        source: AuditParticipant,
        destination: AuditParticipant,
        completedCount: Int,
        failedCount: Int,
        duration: TimeInterval?,
        errorMessage: String? = nil
    ) {
        let entry = AuditLogEntry(
            eventType: .retrieveMoveCompleted,
            outcome: outcome,
            source: source,
            destination: destination,
            duration: duration,
            instanceCount: completedCount,
            errorMessage: errorMessage,
            metadata: [
                "completedCount": String(completedCount),
                "failedCount": String(failedCount)
            ]
        )
        log(entry)
    }
    
    /// Logs a C-GET retrieve start event
    ///
    /// - Parameters:
    ///   - source: The retrieve requestor
    ///   - destination: The PACS server
    ///   - studyInstanceUID: Study being retrieved (optional)
    ///   - seriesInstanceUID: Series being retrieved (optional)
    ///   - sopInstanceUID: Instance being retrieved (optional)
    public func logRetrieveGetStarted(
        source: AuditParticipant,
        destination: AuditParticipant,
        studyInstanceUID: String? = nil,
        seriesInstanceUID: String? = nil,
        sopInstanceUID: String? = nil
    ) {
        let entry = AuditLogEntry(
            eventType: .retrieveGetStarted,
            outcome: .success,
            source: source,
            destination: destination,
            sopInstanceUID: sopInstanceUID,
            studyInstanceUID: studyInstanceUID,
            seriesInstanceUID: seriesInstanceUID
        )
        log(entry)
    }
    
    /// Logs a C-GET retrieve completion event
    ///
    /// - Parameters:
    ///   - outcome: Outcome of the retrieve
    ///   - source: The retrieve requestor
    ///   - destination: The PACS server
    ///   - completedCount: Number of successfully retrieved instances
    ///   - failedCount: Number of failed instances
    ///   - bytesTransferred: Total bytes received
    ///   - duration: Total duration of the retrieve
    ///   - errorMessage: Error message if failed
    public func logRetrieveGetCompleted(
        outcome: AuditEventOutcome,
        source: AuditParticipant,
        destination: AuditParticipant,
        completedCount: Int,
        failedCount: Int,
        bytesTransferred: Int64?,
        duration: TimeInterval?,
        errorMessage: String? = nil
    ) {
        let entry = AuditLogEntry(
            eventType: .retrieveGetCompleted,
            outcome: outcome,
            source: source,
            destination: destination,
            bytesTransferred: bytesTransferred,
            duration: duration,
            instanceCount: completedCount,
            errorMessage: errorMessage,
            metadata: [
                "completedCount": String(completedCount),
                "failedCount": String(failedCount)
            ]
        )
        log(entry)
    }
    
    /// Logs a C-ECHO verification event
    ///
    /// - Parameters:
    ///   - outcome: Outcome of the verification
    ///   - source: The verifier
    ///   - destination: The verification responder
    ///   - duration: Duration of the verification
    ///   - errorMessage: Error message if failed
    public func logVerificationPerformed(
        outcome: AuditEventOutcome,
        source: AuditParticipant,
        destination: AuditParticipant,
        duration: TimeInterval?,
        errorMessage: String? = nil
    ) {
        let entry = AuditLogEntry(
            eventType: .verificationPerformed,
            outcome: outcome,
            source: source,
            destination: destination,
            duration: duration,
            errorMessage: errorMessage
        )
        log(entry)
    }
    
    /// Logs a storage commitment request event
    ///
    /// - Parameters:
    ///   - source: The commitment requestor
    ///   - destination: The commitment responder
    ///   - transactionUID: Transaction UID
    ///   - instanceCount: Number of instances in the commitment request
    public func logCommitmentRequested(
        source: AuditParticipant,
        destination: AuditParticipant,
        transactionUID: String,
        instanceCount: Int
    ) {
        let entry = AuditLogEntry(
            eventType: .commitmentRequested,
            outcome: .success,
            source: source,
            destination: destination,
            instanceCount: instanceCount,
            metadata: ["transactionUID": transactionUID]
        )
        log(entry)
    }
    
    /// Logs a storage commitment result event
    ///
    /// - Parameters:
    ///   - outcome: Outcome of the commitment
    ///   - source: The commitment requestor
    ///   - destination: The commitment responder
    ///   - transactionUID: Transaction UID
    ///   - committedCount: Number of successfully committed instances
    ///   - failedCount: Number of failed instances
    ///   - errorMessage: Error message if any failures
    public func logCommitmentResultReceived(
        outcome: AuditEventOutcome,
        source: AuditParticipant,
        destination: AuditParticipant,
        transactionUID: String,
        committedCount: Int,
        failedCount: Int,
        errorMessage: String? = nil
    ) {
        let entry = AuditLogEntry(
            eventType: .commitmentResultReceived,
            outcome: outcome,
            source: source,
            destination: destination,
            instanceCount: committedCount,
            errorMessage: errorMessage,
            metadata: [
                "transactionUID": transactionUID,
                "committedCount": String(committedCount),
                "failedCount": String(failedCount)
            ]
        )
        log(entry)
    }
    
    /// Logs a connection event
    ///
    /// - Parameters:
    ///   - established: Whether the connection was established (true) or failed (false)
    ///   - source: The connection initiator
    ///   - host: Remote host
    ///   - port: Remote port
    ///   - errorMessage: Error message if connection failed
    public func logConnectionEvent(
        established: Bool,
        source: AuditParticipant,
        host: String,
        port: UInt16,
        errorMessage: String? = nil
    ) {
        let destination = AuditParticipant(
            aeTitle: "N/A",
            host: host,
            port: port,
            isRequestor: false
        )
        
        let entry = AuditLogEntry(
            eventType: established ? .connectionEstablished : .connectionFailed,
            outcome: established ? .success : .majorFailure,
            source: source,
            destination: destination,
            errorMessage: errorMessage
        )
        log(entry)
    }
    
    /// Logs a security event
    ///
    /// - Parameters:
    ///   - outcome: Outcome of the security event
    ///   - source: The party involved
    ///   - description: Description of the security event
    ///   - errorMessage: Error message if applicable
    public func logSecurityEvent(
        outcome: AuditEventOutcome,
        source: AuditParticipant,
        description: String,
        errorMessage: String? = nil
    ) {
        let entry = AuditLogEntry(
            eventType: .securityEvent,
            outcome: outcome,
            source: source,
            errorMessage: errorMessage,
            metadata: ["description": description]
        )
        log(entry)
    }
    
    // MARK: - Static Convenience Methods
    
    /// Static logging that dispatches to the shared instance
    
    /// Logs a C-STORE send event
    public static func logStoreSent(
        outcome: AuditEventOutcome,
        source: AuditParticipant,
        destination: AuditParticipant,
        sopClassUID: String?,
        sopInstanceUID: String?,
        studyInstanceUID: String? = nil,
        seriesInstanceUID: String? = nil,
        patientID: String? = nil,
        bytesTransferred: Int64?,
        duration: TimeInterval?,
        statusCode: UInt16?,
        errorMessage: String? = nil
    ) {
        Task {
            await shared.logStoreSent(
                outcome: outcome,
                source: source,
                destination: destination,
                sopClassUID: sopClassUID,
                sopInstanceUID: sopInstanceUID,
                studyInstanceUID: studyInstanceUID,
                seriesInstanceUID: seriesInstanceUID,
                patientID: patientID,
                bytesTransferred: bytesTransferred,
                duration: duration,
                statusCode: statusCode,
                errorMessage: errorMessage
            )
        }
    }
    
    /// Logs a C-STORE receive event
    public static func logStoreReceived(
        outcome: AuditEventOutcome,
        source: AuditParticipant,
        destination: AuditParticipant,
        sopClassUID: String?,
        sopInstanceUID: String?,
        studyInstanceUID: String? = nil,
        seriesInstanceUID: String? = nil,
        patientID: String? = nil,
        bytesTransferred: Int64?,
        duration: TimeInterval?,
        statusCode: UInt16?,
        errorMessage: String? = nil
    ) {
        Task {
            await shared.logStoreReceived(
                outcome: outcome,
                source: source,
                destination: destination,
                sopClassUID: sopClassUID,
                sopInstanceUID: sopInstanceUID,
                studyInstanceUID: studyInstanceUID,
                seriesInstanceUID: seriesInstanceUID,
                patientID: patientID,
                bytesTransferred: bytesTransferred,
                duration: duration,
                statusCode: statusCode,
                errorMessage: errorMessage
            )
        }
    }
}
