import Foundation
#if canImport(os)
import os
#endif

// NEMA-verified: 2026a, checked 2026-09-28 — carries no DICOM-standard data (request/response logging)
/// Protocol for logging DICOMweb requests and responses
public protocol DICOMwebRequestLogger: Sendable {
    /// Logs a request about to be sent
    /// - Parameter request: The request to log
    func logRequest(_ request: RequestLogEntry) async
    
    /// Logs a response received
    /// - Parameter response: The response to log
    func logResponse(_ response: ResponseLogEntry) async
    
    /// Logs an error
    /// - Parameter error: The error to log
    func logError(_ error: ErrorLogEntry) async
}

// MARK: - Log Entry Types

/// Information about a logged request
public struct RequestLogEntry: Sendable {
    /// Unique request identifier
    public let requestID: String
    
    /// The request URL
    public let url: URL
    
    /// The HTTP method
    public let method: String
    
    /// Request headers
    public let headers: [String: String]
    
    /// Size of the request body in bytes
    public let bodySize: Int?
    
    /// Timestamp when the request was made
    public let timestamp: Date
    
    /// Optional context information
    public let context: [String: String]
    
    public init(
        requestID: String = UUID().uuidString,
        url: URL,
        method: String,
        headers: [String: String] = [:],
        bodySize: Int? = nil,
        timestamp: Date = Date(),
        context: [String: String] = [:]
    ) {
        self.requestID = requestID
        self.url = url
        self.method = method
        self.headers = headers
        self.bodySize = bodySize
        self.timestamp = timestamp
        self.context = context
    }
}

/// Information about a logged response
public struct ResponseLogEntry: Sendable {
    /// The request ID this response corresponds to
    public let requestID: String
    
    /// The response URL (may differ from request due to redirects)
    public let url: URL
    
    /// HTTP status code
    public let statusCode: Int
    
    /// Response headers
    public let headers: [String: String]
    
    /// Size of the response body in bytes
    public let bodySize: Int?
    
    /// Time taken to receive the response
    public let duration: TimeInterval
    
    /// Timestamp when the response was received
    public let timestamp: Date
    
    /// Whether the response was from cache
    public let fromCache: Bool
    
    public init(
        requestID: String,
        url: URL,
        statusCode: Int,
        headers: [String: String] = [:],
        bodySize: Int? = nil,
        duration: TimeInterval,
        timestamp: Date = Date(),
        fromCache: Bool = false
    ) {
        self.requestID = requestID
        self.url = url
        self.statusCode = statusCode
        self.headers = headers
        self.bodySize = bodySize
        self.duration = duration
        self.timestamp = timestamp
        self.fromCache = fromCache
    }
}

/// Information about a logged error
public struct ErrorLogEntry: Sendable {
    /// The request ID this error corresponds to
    public let requestID: String
    
    /// The request URL
    public let url: URL
    
    /// The error description
    public let errorDescription: String
    
    /// The error code (if applicable)
    public let errorCode: Int?
    
    /// Time taken before the error occurred
    public let duration: TimeInterval?
    
    /// Timestamp when the error occurred
    public let timestamp: Date
    
    /// Additional error context
    public let context: [String: String]
    
    public init(
        requestID: String,
        url: URL,
        errorDescription: String,
        errorCode: Int? = nil,
        duration: TimeInterval? = nil,
        timestamp: Date = Date(),
        context: [String: String] = [:]
    ) {
        self.requestID = requestID
        self.url = url
        self.errorDescription = errorDescription
        self.errorCode = errorCode
        self.duration = duration
        self.timestamp = timestamp
        self.context = context
    }
}

// MARK: - OSLog Request Logger

#if canImport(os)
/// Request logger that uses OSLog for Apple platforms
///
/// Integrates with Console.app and Instruments for debugging.
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, visionOS 1.0, *)
public final class OSLogRequestLogger: DICOMwebRequestLogger, @unchecked Sendable {
    
    private let logger: os.Logger
    private let logLevel: LogLevel
    private let includeHeaders: Bool
    
    /// Log levels
    public enum LogLevel: Int, Sendable {
        case debug = 0
        case info = 1
        case notice = 2
        case error = 3
        case fault = 4
    }
    
    /// Creates an OSLog request logger
    /// - Parameters:
    ///   - subsystem: The subsystem identifier (default: "com.dicomkit")
    ///   - category: The log category (default: "network")
    ///   - logLevel: Minimum log level (default: .info)
    ///   - includeHeaders: Whether to log headers (default: false)
    public init(
        subsystem: String = "com.dicomkit",
        category: String = "network",
        logLevel: LogLevel = .info,
        includeHeaders: Bool = false
    ) {
        self.logger = os.Logger(subsystem: subsystem, category: category)
        self.logLevel = logLevel
        self.includeHeaders = includeHeaders
    }
    
    public func logRequest(_ request: RequestLogEntry) async {
        guard logLevel.rawValue <= LogLevel.info.rawValue else { return }
        
        var message = "→ \(request.method) \(request.url.absoluteString)"
        
        if let size = request.bodySize {
            message += " (\(formatBytes(size)))"
        }
        
        if includeHeaders && !request.headers.isEmpty {
            message += " headers: \(request.headers)"
        }
        
        logger.info("\(message, privacy: .public)")
    }
    
    public func logResponse(_ response: ResponseLogEntry) async {
        guard logLevel.rawValue <= LogLevel.info.rawValue else { return }
        
        let cacheIndicator = response.fromCache ? " [CACHED]" : ""
        var message = "← \(response.statusCode)\(cacheIndicator) \(response.url.absoluteString)"
        
        if let size = response.bodySize {
            message += " (\(formatBytes(size)))"
        }
        
        message += " in \(formatDuration(response.duration))"
        
        if response.statusCode >= 400 {
            logger.warning("\(message, privacy: .public)")
        } else {
            logger.info("\(message, privacy: .public)")
        }
    }
    
    public func logError(_ error: ErrorLogEntry) async {
        var message = "✗ \(error.url.absoluteString): \(error.errorDescription)"
        
        if let code = error.errorCode {
            message += " (code: \(code))"
        }
        
        if let duration = error.duration {
            message += " after \(formatDuration(duration))"
        }
        
        logger.error("\(message, privacy: .public)")
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0f ms", duration * 1000)
        } else {
            return String(format: "%.2f s", duration)
        }
    }
}
#endif

// MARK: - Console Request Logger

/// Simple console logger for debugging
public final class ConsoleRequestLogger: DICOMwebRequestLogger, @unchecked Sendable {
    
    private let includeHeaders: Bool
    private let includeTimestamps: Bool
    
    /// Creates a console request logger
    /// - Parameters:
    ///   - includeHeaders: Whether to log headers (default: false)
    ///   - includeTimestamps: Whether to include timestamps (default: true)
    public init(
        includeHeaders: Bool = false,
        includeTimestamps: Bool = true
    ) {
        self.includeHeaders = includeHeaders
        self.includeTimestamps = includeTimestamps
    }
    
    public func logRequest(_ request: RequestLogEntry) async {
        var message = "[DICOMweb]"
        
        if includeTimestamps {
            message += " \(formatTimestamp(request.timestamp))"
        }
        
        message += " → \(request.method) \(request.url.absoluteString)"
        
        if let size = request.bodySize, size > 0 {
            message += " (\(formatBytes(size)))"
        }
        
        if includeHeaders && !request.headers.isEmpty {
            message += "\n  Headers: \(request.headers)"
        }
        
        print(message)
    }
    
    public func logResponse(_ response: ResponseLogEntry) async {
        var message = "[DICOMweb]"
        
        if includeTimestamps {
            message += " \(formatTimestamp(response.timestamp))"
        }
        
        let cacheIndicator = response.fromCache ? " [CACHED]" : ""
        message += " ← \(response.statusCode)\(cacheIndicator) \(response.url.absoluteString)"
        
        if let size = response.bodySize {
            message += " (\(formatBytes(size)))"
        }
        
        message += " in \(formatDuration(response.duration))"
        
        if includeHeaders && !response.headers.isEmpty {
            message += "\n  Headers: \(response.headers)"
        }
        
        print(message)
    }
    
    public func logError(_ error: ErrorLogEntry) async {
        var message = "[DICOMweb]"
        
        if includeTimestamps {
            message += " \(formatTimestamp(error.timestamp))"
        }
        
        message += " ✗ ERROR: \(error.errorDescription)"
        message += " URL: \(error.url.absoluteString)"
        
        if let code = error.errorCode {
            message += " Code: \(code)"
        }
        
        if let duration = error.duration {
            message += " after \(formatDuration(duration))"
        }
        
        print(message)
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0f ms", duration * 1000)
        } else {
            return String(format: "%.2f s", duration)
        }
    }
}

// MARK: - Null Request Logger

/// A no-op logger that discards all log entries
///
/// Useful when logging is not needed but a logger instance is required.
public final class NullRequestLogger: DICOMwebRequestLogger, @unchecked Sendable {
    
    public init() {}
    
    public func logRequest(_ request: RequestLogEntry) async {}
    
    public func logResponse(_ response: ResponseLogEntry) async {}
    
    public func logError(_ error: ErrorLogEntry) async {}
}

// MARK: - Composite Request Logger

/// A logger that forwards to multiple other loggers
public actor CompositeRequestLogger: DICOMwebRequestLogger {
    
    private var loggers: [DICOMwebRequestLogger]
    
    /// Creates a composite logger
    /// - Parameter loggers: The loggers to forward to
    public init(loggers: [DICOMwebRequestLogger]) {
        self.loggers = loggers
    }
    
    /// Adds a logger
    /// - Parameter logger: The logger to add
    public func addLogger(_ logger: DICOMwebRequestLogger) {
        loggers.append(logger)
    }
    
    public func logRequest(_ request: RequestLogEntry) async {
        for logger in loggers {
            await logger.logRequest(request)
        }
    }
    
    public func logResponse(_ response: ResponseLogEntry) async {
        for logger in loggers {
            await logger.logResponse(response)
        }
    }
    
    public func logError(_ error: ErrorLogEntry) async {
        for logger in loggers {
            await logger.logError(error)
        }
    }
}
