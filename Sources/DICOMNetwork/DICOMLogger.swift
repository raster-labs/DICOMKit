import Foundation
#if canImport(os)
import os
// NEMA-verified: 2026a, checked 2026-09-28 — carries no DICOM-standard data (log categories and formatting only)
#endif

// MARK: - Log Level

/// Log levels for DICOM networking operations
///
/// Log levels follow standard severity ordering from least to most severe.
/// When a minimum log level is set, only messages at that level or higher are emitted.
///
/// Reference: Apple Unified Logging System
public enum DICOMLogLevel: Int, Sendable, Comparable, CustomStringConvertible {
    /// Detailed diagnostic information useful for debugging
    /// Includes PDU contents, message details, timing information
    case debug = 0
    
    /// General informational messages about normal operation
    /// Includes connection events, successful operations, state changes
    case info = 1
    
    /// Potentially harmful situations that aren't errors
    /// Includes retry attempts, deprecated features, performance concerns
    case warning = 2
    
    /// Error conditions that the system can recover from
    /// Includes connection failures, timeouts, rejected associations
    case error = 3
    
    public static func < (lhs: DICOMLogLevel, rhs: DICOMLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    public var description: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        }
    }
    
    #if canImport(os)
    /// Maps to OSLogType for Apple's unified logging
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }
    #endif
}

// MARK: - Log Category

/// Categories for DICOM networking log messages
///
/// Categories help filter and organize log output by functional area.
public enum DICOMLogCategory: String, Sendable, CaseIterable {
    /// Network connection events (connect, disconnect, data transfer)
    case connection = "Connection"
    
    /// Association lifecycle events (request, accept, reject, release, abort)
    case association = "Association"
    
    /// Protocol Data Unit (PDU) encoding and decoding
    case pdu = "PDU"
    
    /// DIMSE message handling (commands, responses)
    case dimse = "DIMSE"
    
    /// Query operations (C-FIND)
    case query = "Query"
    
    /// Retrieve operations (C-MOVE, C-GET)
    case retrieve = "Retrieve"
    
    /// Verification operations (C-ECHO)
    case verification = "Verification"
    
    /// State machine transitions
    case stateMachine = "StateMachine"
    
    /// Performance metrics and timing
    case performance = "Performance"
    
    /// Storage operations (C-STORE send/receive)
    case storage = "Storage"
    
    /// Audit trail events
    case audit = "Audit"
}

// MARK: - Log Message

/// A structured log message for DICOM networking
public struct DICOMLogMessage: Sendable {
    /// The log level
    public let level: DICOMLogLevel
    
    /// The category of the log message
    public let category: DICOMLogCategory
    
    /// The main message text
    public let message: String
    
    /// Additional context information
    public let context: [String: String]
    
    /// The timestamp when the log was created
    public let timestamp: Date
    
    /// Creates a new log message
    ///
    /// - Parameters:
    ///   - level: The severity level
    ///   - category: The functional category
    ///   - message: The main message text
    ///   - context: Additional key-value context
    public init(
        level: DICOMLogLevel,
        category: DICOMLogCategory,
        message: String,
        context: [String: String] = [:]
    ) {
        self.level = level
        self.category = category
        self.message = message
        self.context = context
        self.timestamp = Date()
    }
}

// MARK: - Logger Protocol

/// Protocol for DICOM logging handlers
///
/// Implement this protocol to receive log messages from DICOM networking operations.
/// Multiple handlers can be registered to route logs to different destinations.
///
/// ## Example Implementation
///
/// ```swift
/// final class ConsoleLogger: DICOMLogHandler {
///     func log(_ message: DICOMLogMessage) {
///         print("[\(message.level)] [\(message.category.rawValue)] \(message.message)")
///     }
/// }
/// ```
public protocol DICOMLogHandler: Sendable {
    /// Handles a log message
    ///
    /// - Parameter message: The log message to handle
    func log(_ message: DICOMLogMessage)
}

// MARK: - Default Log Handler (OSLog)

#if canImport(os)

/// Default log handler using Apple's Unified Logging System (OSLog)
///
/// This handler uses OSLog with the subsystem "com.dicomkit.network"
/// and creates separate log objects for each category.
///
/// ## Usage
///
/// ```swift
/// DICOMLogger.shared.addHandler(OSLogHandler())
/// ```
public final class OSLogHandler: DICOMLogHandler {
    /// The subsystem for OSLog
    private let subsystem: String
    
    /// Cached log objects per category
    private let logObjects: [DICOMLogCategory: OSLog]
    
    /// Creates an OSLog handler
    ///
    /// - Parameter subsystem: The OSLog subsystem (default: "com.dicomkit.network")
    public init(subsystem: String = "com.dicomkit.network") {
        self.subsystem = subsystem
        
        // Pre-create log objects for each category
        var logs: [DICOMLogCategory: OSLog] = [:]
        for category in DICOMLogCategory.allCases {
            logs[category] = OSLog(subsystem: subsystem, category: category.rawValue)
        }
        self.logObjects = logs
    }
    
    public func log(_ message: DICOMLogMessage) {
        guard let log = logObjects[message.category] else { return }
        
        // Build context string
        let contextString = message.context.isEmpty
            ? ""
            : " | " + message.context.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        
        let fullMessage = "\(message.message)\(contextString)"
        
        os_log("%{public}@", log: log, type: message.level.osLogType, fullMessage)
    }
}

#endif

// MARK: - Console Log Handler

/// Simple console log handler for debugging
///
/// Outputs formatted log messages to standard output.
/// Useful for development and debugging when OSLog is not practical.
///
/// ## Usage
///
/// ```swift
/// DICOMLogger.shared.addHandler(ConsoleLogHandler())
/// ```
public final class ConsoleLogHandler: DICOMLogHandler {
    /// Whether to include timestamps in output
    public let includeTimestamp: Bool
    
    /// Date formatter for timestamps
    private let dateFormatter: DateFormatter
    
    /// Creates a console log handler
    ///
    /// - Parameter includeTimestamp: Whether to include timestamps (default: true)
    public init(includeTimestamp: Bool = true) {
        self.includeTimestamp = includeTimestamp
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "HH:mm:ss.SSS"
    }
    
    public func log(_ message: DICOMLogMessage) {
        var output = ""
        
        if includeTimestamp {
            output += "[\(dateFormatter.string(from: message.timestamp))] "
        }
        
        output += "[\(message.level)] [\(message.category.rawValue)] \(message.message)"
        
        if !message.context.isEmpty {
            let contextString = message.context.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            output += " | \(contextString)"
        }
        
        print(output)
    }
}

// MARK: - DICOM Logger

/// Central logger for DICOM networking operations
///
/// DICOMLogger is the main entry point for logging in the DICOM networking module.
/// It manages log handlers and provides convenient methods for logging at different levels.
///
/// ## Thread Safety
///
/// DICOMLogger is thread-safe and uses actors for internal state management.
///
/// ## Configuration
///
/// Configure the logger at app startup:
///
/// ```swift
/// // Enable logging with OSLog handler
/// await DICOMLogger.shared.addHandler(OSLogHandler())
///
/// // Set minimum log level to info (default)
/// await DICOMLogger.shared.setMinimumLevel(.info)
///
/// // Or use console output for debugging
/// await DICOMLogger.shared.addHandler(ConsoleLogHandler())
/// ```
///
/// ## Usage
///
/// Log messages using the static convenience methods:
///
/// ```swift
/// // Debug information
/// DICOMLogger.debug(.connection, "Connecting to \(host):\(port)")
///
/// // Informational messages
/// DICOMLogger.info(.association, "Association established")
///
/// // Warnings
/// DICOMLogger.warning(.retrieve, "Retry attempt \(attempt)")
///
/// // Errors
/// DICOMLogger.error(.connection, "Connection failed", context: ["error": error.localizedDescription])
/// ```
public actor DICOMLogger {
    /// Shared singleton instance
    public static let shared = DICOMLogger()
    
    /// Registered log handlers
    private var handlers: [any DICOMLogHandler] = []
    
    /// Minimum log level to emit
    private var minimumLevel: DICOMLogLevel = .info
    
    /// Whether logging is enabled
    private var isEnabled: Bool = false
    
    /// Categories to include (empty = all categories)
    private var enabledCategories: Set<DICOMLogCategory> = []
    
    private init() {}
    
    // MARK: - Configuration
    
    /// Adds a log handler
    ///
    /// - Parameter handler: The handler to add
    public func addHandler(_ handler: any DICOMLogHandler) {
        handlers.append(handler)
        isEnabled = !handlers.isEmpty
    }
    
    /// Removes all log handlers
    public func removeAllHandlers() {
        handlers.removeAll()
        isEnabled = false
    }
    
    /// Sets the minimum log level
    ///
    /// Only messages at this level or higher will be emitted.
    ///
    /// - Parameter level: The minimum log level
    public func setMinimumLevel(_ level: DICOMLogLevel) {
        minimumLevel = level
    }
    
    /// Enables specific log categories
    ///
    /// Pass an empty set to enable all categories.
    ///
    /// - Parameter categories: Categories to enable
    public func setEnabledCategories(_ categories: Set<DICOMLogCategory>) {
        enabledCategories = categories
    }
    
    /// Returns current configuration status
    public var isLoggingEnabled: Bool {
        isEnabled
    }
    
    // MARK: - Logging
    
    /// Logs a message
    ///
    /// - Parameter message: The message to log
    public func log(_ message: DICOMLogMessage) {
        guard isEnabled else { return }
        guard message.level >= minimumLevel else { return }
        guard enabledCategories.isEmpty || enabledCategories.contains(message.category) else { return }
        
        for handler in handlers {
            handler.log(message)
        }
    }
    
    /// Logs a debug message
    ///
    /// - Parameters:
    ///   - category: The log category
    ///   - message: The message text
    ///   - context: Additional context
    public func debug(
        _ category: DICOMLogCategory,
        _ message: String,
        context: [String: String] = [:]
    ) {
        log(DICOMLogMessage(level: .debug, category: category, message: message, context: context))
    }
    
    /// Logs an info message
    ///
    /// - Parameters:
    ///   - category: The log category
    ///   - message: The message text
    ///   - context: Additional context
    public func info(
        _ category: DICOMLogCategory,
        _ message: String,
        context: [String: String] = [:]
    ) {
        log(DICOMLogMessage(level: .info, category: category, message: message, context: context))
    }
    
    /// Logs a warning message
    ///
    /// - Parameters:
    ///   - category: The log category
    ///   - message: The message text
    ///   - context: Additional context
    public func warning(
        _ category: DICOMLogCategory,
        _ message: String,
        context: [String: String] = [:]
    ) {
        log(DICOMLogMessage(level: .warning, category: category, message: message, context: context))
    }
    
    /// Logs an error message
    ///
    /// - Parameters:
    ///   - category: The log category
    ///   - message: The message text
    ///   - context: Additional context
    public func error(
        _ category: DICOMLogCategory,
        _ message: String,
        context: [String: String] = [:]
    ) {
        log(DICOMLogMessage(level: .error, category: category, message: message, context: context))
    }
    
    // MARK: - Static Convenience Methods (Non-async)
    
    /// Static logging that dispatches to the shared instance
    /// These methods create a Task internally for fire-and-forget logging
    
    /// Logs a debug message
    public static func debug(
        _ category: DICOMLogCategory,
        _ message: String,
        context: [String: String] = [:]
    ) {
        Task {
            await shared.debug(category, message, context: context)
        }
    }
    
    /// Logs an info message
    public static func info(
        _ category: DICOMLogCategory,
        _ message: String,
        context: [String: String] = [:]
    ) {
        Task {
            await shared.info(category, message, context: context)
        }
    }
    
    /// Logs a warning message
    public static func warning(
        _ category: DICOMLogCategory,
        _ message: String,
        context: [String: String] = [:]
    ) {
        Task {
            await shared.warning(category, message, context: context)
        }
    }
    
    /// Logs an error message
    public static func error(
        _ category: DICOMLogCategory,
        _ message: String,
        context: [String: String] = [:]
    ) {
        Task {
            await shared.error(category, message, context: context)
        }
    }
}

// MARK: - Diagnostic Extensions

extension DICOMLogger {
    /// Logs the start of an operation and returns a timestamp for duration calculation
    ///
    /// - Parameters:
    ///   - operation: Description of the operation
    ///   - category: The log category
    /// - Returns: Start time for duration calculation
    public func operationStart(
        _ operation: String,
        category: DICOMLogCategory
    ) -> Date {
        let start = Date()
        debug(category, "Starting: \(operation)")
        return start
    }
    
    /// Logs the end of an operation with duration
    ///
    /// - Parameters:
    ///   - operation: Description of the operation
    ///   - startTime: The start time from operationStart
    ///   - category: The log category
    ///   - success: Whether the operation succeeded
    public func operationEnd(
        _ operation: String,
        startTime: Date,
        category: DICOMLogCategory,
        success: Bool = true
    ) {
        let duration = Date().timeIntervalSince(startTime)
        let durationMs = String(format: "%.2f", duration * 1000)
        
        if success {
            info(category, "Completed: \(operation)", context: ["duration_ms": durationMs])
        } else {
            warning(category, "Failed: \(operation)", context: ["duration_ms": durationMs])
        }
    }
}

// MARK: - PDU Logging Helpers

extension DICOMLogger {
    /// Logs a PDU event
    ///
    /// - Parameters:
    ///   - pduType: The type of PDU
    ///   - direction: "sent" or "received"
    ///   - size: Size in bytes
    ///   - additionalContext: Additional context
    public func logPDU(
        type pduType: String,
        direction: String,
        size: Int,
        additionalContext: [String: String] = [:]
    ) {
        var context = additionalContext
        context["type"] = pduType
        context["direction"] = direction
        context["size_bytes"] = String(size)
        
        debug(.pdu, "PDU \(direction): \(pduType)", context: context)
    }
}

// MARK: - Association Logging Helpers

extension DICOMLogger {
    /// Logs an association state transition
    ///
    /// - Parameters:
    ///   - fromState: The previous state
    ///   - toState: The new state
    ///   - event: The event that triggered the transition
    public func logStateTransition(
        from fromState: String,
        to toState: String,
        event: String
    ) {
        debug(.stateMachine, "State transition: \(fromState) → \(toState)", context: [
            "from": fromState,
            "to": toState,
            "event": event
        ])
    }
    
    /// Logs an association request
    ///
    /// - Parameters:
    ///   - callingAE: The calling AE title
    ///   - calledAE: The called AE title
    ///   - host: The remote host
    ///   - port: The remote port
    public func logAssociationRequest(
        callingAE: String,
        calledAE: String,
        host: String,
        port: UInt16
    ) {
        info(.association, "Requesting association", context: [
            "callingAE": callingAE,
            "calledAE": calledAE,
            "host": host,
            "port": String(port)
        ])
    }
    
    /// Logs an association establishment
    ///
    /// - Parameter acceptedContexts: Number of accepted presentation contexts
    public func logAssociationEstablished(acceptedContexts: Int) {
        info(.association, "Association established", context: [
            "acceptedContexts": String(acceptedContexts)
        ])
    }
    
    /// Logs an association rejection
    ///
    /// - Parameters:
    ///   - result: The rejection result
    ///   - source: The rejection source
    ///   - reason: The rejection reason
    public func logAssociationRejected(
        result: String,
        source: String,
        reason: String
    ) {
        warning(.association, "Association rejected", context: [
            "result": result,
            "source": source,
            "reason": reason
        ])
    }
    
    /// Logs an association release
    public func logAssociationReleased() {
        info(.association, "Association released gracefully")
    }
    
    /// Logs an association abort
    ///
    /// - Parameters:
    ///   - source: The abort source
    ///   - reason: The abort reason
    public func logAssociationAborted(source: String, reason: String) {
        warning(.association, "Association aborted", context: [
            "source": source,
            "reason": reason
        ])
    }
}

// MARK: - Connection Logging Helpers

extension DICOMLogger {
    /// Logs a connection attempt
    ///
    /// - Parameters:
    ///   - host: The remote host
    ///   - port: The remote port
    public func logConnectionAttempt(host: String, port: UInt16) {
        debug(.connection, "Attempting connection", context: [
            "host": host,
            "port": String(port)
        ])
    }
    
    /// Logs a successful connection
    ///
    /// - Parameters:
    ///   - host: The remote host
    ///   - port: The remote port
    public func logConnectionEstablished(host: String, port: UInt16) {
        info(.connection, "Connection established", context: [
            "host": host,
            "port": String(port)
        ])
    }
    
    /// Logs a connection failure
    ///
    /// - Parameters:
    ///   - host: The remote host
    ///   - port: The remote port
    ///   - errorDescription: The error description
    public func logConnectionFailed(host: String, port: UInt16, errorDescription: String) {
        error(.connection, "Connection failed", context: [
            "host": host,
            "port": String(port),
            "error": errorDescription
        ])
    }
    
    /// Logs a connection close
    ///
    /// - Parameter graceful: Whether the close was graceful
    public func logConnectionClosed(graceful: Bool) {
        if graceful {
            info(.connection, "Connection closed gracefully")
        } else {
            warning(.connection, "Connection closed unexpectedly")
        }
    }
}

// MARK: - DIMSE Operation Logging Helpers

extension DICOMLogger {
    /// Logs a DIMSE command
    ///
    /// - Parameters:
    ///   - command: The command type (C-ECHO, C-FIND, etc.)
    ///   - messageID: The message ID
    ///   - direction: "request" or "response"
    public func logDIMSECommand(
        command: String,
        messageID: UInt16,
        direction: String
    ) {
        debug(.dimse, "\(command) \(direction)", context: [
            "command": command,
            "messageID": String(messageID),
            "direction": direction
        ])
    }
    
    /// Logs a DIMSE response status
    ///
    /// - Parameters:
    ///   - command: The command type
    ///   - status: The status code
    ///   - messageID: The message ID
    public func logDIMSEStatus(
        command: String,
        status: UInt16,
        messageID: UInt16
    ) {
        let statusHex = String(format: "0x%04X", status)
        debug(.dimse, "\(command) response status: \(statusHex)", context: [
            "command": command,
            "status": statusHex,
            "messageID": String(messageID)
        ])
    }
}

// MARK: - Retrieve Operation Logging Helpers

extension DICOMLogger {
    /// Logs retrieve progress
    ///
    /// - Parameters:
    ///   - operation: The operation type (C-MOVE or C-GET)
    ///   - completed: Number of completed sub-operations
    ///   - remaining: Number of remaining sub-operations
    ///   - failed: Number of failed sub-operations
    ///   - warning: Number of sub-operations with warnings
    public func logRetrieveProgress(
        operation: String,
        completed: Int,
        remaining: Int,
        failed: Int,
        warning: Int
    ) {
        let total = completed + remaining
        debug(.retrieve, "\(operation) progress: \(completed)/\(total)", context: [
            "operation": operation,
            "completed": String(completed),
            "remaining": String(remaining),
            "failed": String(failed),
            "warning": String(warning),
            "total": String(total)
        ])
    }
    
    /// Logs retrieve completion
    ///
    /// - Parameters:
    ///   - operation: The operation type
    ///   - completed: Number of completed sub-operations
    ///   - failed: Number of failed sub-operations
    ///   - success: Whether overall operation succeeded
    public func logRetrieveComplete(
        operation: String,
        completed: Int,
        failed: Int,
        success: Bool
    ) {
        if success {
            info(.retrieve, "\(operation) completed successfully", context: [
                "completed": String(completed),
                "failed": String(failed)
            ])
        } else {
            warning(.retrieve, "\(operation) completed with failures", context: [
                "completed": String(completed),
                "failed": String(failed)
            ])
        }
    }
}

// MARK: - Query Operation Logging Helpers

extension DICOMLogger {
    /// Logs query execution
    ///
    /// - Parameters:
    ///   - level: The query level
    ///   - model: The information model
    public func logQueryStart(level: String, model: String) {
        debug(.query, "Starting C-FIND query", context: [
            "level": level,
            "model": model
        ])
    }
    
    /// Logs query results
    ///
    /// - Parameter count: Number of results
    public func logQueryResults(count: Int) {
        info(.query, "C-FIND query completed", context: [
            "resultCount": String(count)
        ])
    }
}

// MARK: - Verification Logging Helpers

extension DICOMLogger {
    /// Logs C-ECHO verification
    ///
    /// - Parameters:
    ///   - host: The remote host
    ///   - port: The remote port
    ///   - success: Whether verification succeeded
    public func logVerification(
        host: String,
        port: UInt16,
        success: Bool
    ) {
        if success {
            info(.verification, "C-ECHO verification succeeded", context: [
                "host": host,
                "port": String(port)
            ])
        } else {
            warning(.verification, "C-ECHO verification failed", context: [
                "host": host,
                "port": String(port)
            ])
        }
    }
}

// MARK: - Storage Logging Helpers

extension DICOMLogger {
    /// Logs C-STORE send operation start
    ///
    /// - Parameters:
    ///   - sopClassUID: SOP Class UID of the object being stored
    ///   - sopInstanceUID: SOP Instance UID of the object being stored
    ///   - host: Remote host
    ///   - port: Remote port
    public func logStoreSendStart(
        sopClassUID: String,
        sopInstanceUID: String,
        host: String,
        port: UInt16
    ) {
        debug(.storage, "Starting C-STORE send", context: [
            "sopClass": sopClassUID,
            "sopInstance": sopInstanceUID,
            "host": host,
            "port": String(port)
        ])
    }
    
    /// Logs C-STORE send operation completion
    ///
    /// - Parameters:
    ///   - sopInstanceUID: SOP Instance UID of the stored object
    ///   - success: Whether the store succeeded
    ///   - statusCode: DICOM status code
    ///   - bytesTransferred: Number of bytes transferred
    ///   - duration: Duration in seconds
    public func logStoreSendComplete(
        sopInstanceUID: String,
        success: Bool,
        statusCode: UInt16,
        bytesTransferred: Int,
        duration: TimeInterval
    ) {
        let statusHex = String(format: "0x%04X", statusCode)
        let durationMs = String(format: "%.2f", duration * 1000)
        
        if success {
            info(.storage, "C-STORE send completed", context: [
                "sopInstance": sopInstanceUID,
                "status": statusHex,
                "bytes": String(bytesTransferred),
                "duration_ms": durationMs
            ])
        } else {
            warning(.storage, "C-STORE send failed", context: [
                "sopInstance": sopInstanceUID,
                "status": statusHex,
                "bytes": String(bytesTransferred),
                "duration_ms": durationMs
            ])
        }
    }
    
    /// Logs C-STORE receive operation start
    ///
    /// - Parameters:
    ///   - sopClassUID: SOP Class UID of the object being received
    ///   - sopInstanceUID: SOP Instance UID of the object being received
    ///   - sourceAE: Source Application Entity title
    public func logStoreReceiveStart(
        sopClassUID: String,
        sopInstanceUID: String,
        sourceAE: String
    ) {
        debug(.storage, "Receiving C-STORE", context: [
            "sopClass": sopClassUID,
            "sopInstance": sopInstanceUID,
            "sourceAE": sourceAE
        ])
    }
    
    /// Logs C-STORE receive operation completion
    ///
    /// - Parameters:
    ///   - sopInstanceUID: SOP Instance UID of the received object
    ///   - success: Whether the receive succeeded
    ///   - statusCode: DICOM status code sent in response
    ///   - bytesReceived: Number of bytes received
    ///   - duration: Duration in seconds
    public func logStoreReceiveComplete(
        sopInstanceUID: String,
        success: Bool,
        statusCode: UInt16,
        bytesReceived: Int,
        duration: TimeInterval
    ) {
        let statusHex = String(format: "0x%04X", statusCode)
        let durationMs = String(format: "%.2f", duration * 1000)
        
        if success {
            info(.storage, "C-STORE received successfully", context: [
                "sopInstance": sopInstanceUID,
                "status": statusHex,
                "bytes": String(bytesReceived),
                "duration_ms": durationMs
            ])
        } else {
            warning(.storage, "C-STORE receive failed", context: [
                "sopInstance": sopInstanceUID,
                "status": statusHex,
                "bytes": String(bytesReceived),
                "duration_ms": durationMs
            ])
        }
    }
    
    /// Logs batch storage progress
    ///
    /// - Parameters:
    ///   - completed: Number of completed files
    ///   - total: Total number of files
    ///   - succeeded: Number of successful stores
    ///   - failed: Number of failed stores
    public func logBatchStoreProgress(
        completed: Int,
        total: Int,
        succeeded: Int,
        failed: Int
    ) {
        debug(.storage, "Batch store progress: \(completed)/\(total)", context: [
            "completed": String(completed),
            "total": String(total),
            "succeeded": String(succeeded),
            "failed": String(failed)
        ])
    }
    
    /// Logs batch storage completion
    ///
    /// - Parameters:
    ///   - total: Total number of files
    ///   - succeeded: Number of successful stores
    ///   - failed: Number of failed stores
    ///   - duration: Total duration in seconds
    public func logBatchStoreComplete(
        total: Int,
        succeeded: Int,
        failed: Int,
        duration: TimeInterval
    ) {
        let durationSeconds = String(format: "%.2f", duration)
        
        if failed == 0 {
            info(.storage, "Batch store completed successfully", context: [
                "total": String(total),
                "succeeded": String(succeeded),
                "duration_s": durationSeconds
            ])
        } else {
            warning(.storage, "Batch store completed with failures", context: [
                "total": String(total),
                "succeeded": String(succeeded),
                "failed": String(failed),
                "duration_s": durationSeconds
            ])
        }
    }
}
