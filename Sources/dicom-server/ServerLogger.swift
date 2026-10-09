// NEMA-verified: 2026a, checked 2026-10-01 — carries no DICOM-standard data (log levels, timestamps, file output)
import Foundation

/// Log level for server logging
enum LogLevel: String, Comparable, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        let order: [LogLevel] = [.debug, .info, .warning, .error]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}

/// Thread-safe server logger
actor ServerLogger {
    private let minimumLevel: LogLevel
    private let includeTimestamp: Bool
    private let includeLevel: Bool
    private var logFileHandle: FileHandle?
    
    init(
        minimumLevel: LogLevel = .info,
        includeTimestamp: Bool = true,
        includeLevel: Bool = true,
        logFilePath: String? = nil
    ) throws {
        self.minimumLevel = minimumLevel
        self.includeTimestamp = includeTimestamp
        self.includeLevel = includeLevel
        
        // Open log file if specified
        if let logPath = logFilePath {
            let logURL = URL(fileURLWithPath: logPath)
            
            // Create file if it doesn't exist
            if !FileManager.default.fileExists(atPath: logPath) {
                _ = FileManager.default.createFile(atPath: logPath, contents: nil)
            }
            
            self.logFileHandle = try FileHandle(forWritingTo: logURL)
            try self.logFileHandle?.seekToEnd()
        }
    }
    
    deinit {
        try? logFileHandle?.close()
    }
    
    /// Log a message at the specified level
    func log(_ message: String, level: LogLevel = .info, context: String? = nil) {
        guard level >= minimumLevel else { return }
        
        var components: [String] = []
        
        // Add timestamp
        if includeTimestamp {
            let timestamp = formatTimestamp(Date())
            components.append(timestamp)
        }
        
        // Add log level
        if includeLevel {
            components.append("[\(level.rawValue)]")
        }
        
        // Add context if provided
        if let ctx = context {
            components.append("[\(ctx)]")
        }
        
        // Add message
        components.append(message)
        
        let logLine = components.joined(separator: " ")
        
        // Write to console
        print(logLine)
        
        // Write to file if configured
        if let fileHandle = logFileHandle,
           let data = (logLine + "\n").data(using: .utf8) {
            try? fileHandle.write(contentsOf: data)
        }
    }
    
    /// Log debug message
    func debug(_ message: String, context: String? = nil) {
        log(message, level: .debug, context: context)
    }
    
    /// Log info message
    func info(_ message: String, context: String? = nil) {
        log(message, level: .info, context: context)
    }
    
    /// Log warning message
    func warning(_ message: String, context: String? = nil) {
        log(message, level: .warning, context: context)
    }
    
    /// Log error message
    func error(_ message: String, context: String? = nil) {
        log(message, level: .error, context: context)
    }
    
    /// Log error with exception
    func error(_ message: String, error: Error, context: String? = nil) {
        log("\(message): \(error.localizedDescription)", level: .error, context: context)
    }
    
    /// Flush log file to disk
    func flush() {
        try? logFileHandle?.synchronize()
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
