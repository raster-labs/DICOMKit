import Foundation

/// A single entry in the command execution history
public struct CommandHistoryEntry: Identifiable, Codable, Sendable {
    public let id: UUID
    /// The tool ID that was used
    public let toolID: String
    /// The subcommand (if any)
    public let subcommand: String?
    /// The parameter values used
    public let parameterValues: [String: String]
    /// The full command string that was generated
    public let commandString: String
    /// Present for safe replay; older history contains display text only.
    public let invocation: CommandInvocation?
    public var displayCommand: String { invocation?.commandString ?? commandString }
    /// Legacy text is never offered as executable script, including when copied from history.
    public var copyableCommand: String {
        if let invocation = replayInvocation { return invocation.commandString }
        return (["# Legacy/unrecognized entry: rebuild in Toolbox before running."] +
                commandString.components(separatedBy: .newlines).map { "# " + $0 }).joined(separator: "\n")
    }
    public var replayInvocation: CommandInvocation? {
        guard let invocation, invocation.executable == toolID,
              ToolRegistry.tool(withID: toolID) != nil else { return nil }
        return invocation
    }
    /// When the command was executed
    public let timestamp: Date
    /// The exit code (nil if not yet completed)
    public let exitCode: Int?
    /// Whether the command completed successfully
    public var isSuccess: Bool {
        exitCode.map { $0 == 0 } ?? false
    }

    public init(
        id: UUID = UUID(),
        toolID: String,
        subcommand: String? = nil,
        parameterValues: [String: String],
        commandString: String,
        timestamp: Date = Date(),
        exitCode: Int? = nil,
        invocation: CommandInvocation? = nil
    ) {
        self.id = id
        self.toolID = toolID
        self.subcommand = subcommand
        self.parameterValues = parameterValues
        self.commandString = invocation?.commandString ?? commandString
        self.invocation = invocation
        self.timestamp = timestamp
        self.exitCode = exitCode
    }

    /// Creates a copy with an updated exit code
    public func withExitCode(_ code: Int) -> CommandHistoryEntry {
        CommandHistoryEntry(
            id: id,
            toolID: toolID,
            subcommand: subcommand,
            parameterValues: parameterValues,
            commandString: commandString,
            timestamp: timestamp,
            exitCode: code,
            invocation: invocation
        )
    }
}

/// Manages command execution history with persistence
public final class CommandHistory: Sendable {
    /// Maximum number of entries to keep
    public static let maxEntries = 50

    /// UserDefaults key for storing history
    private static let storageKey = "DICOMToolbox.commandHistory"

    /// Loads the saved history entries from UserDefaults
    public static func load() -> [CommandHistoryEntry] {
        #if canImport(AppKit) && os(macOS)
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([CommandHistoryEntry].self, from: data) else {
            return []
        }
        return entries
        #else
        return []
        #endif
    }

    /// Saves history entries to UserDefaults
    public static func save(_ entries: [CommandHistoryEntry]) {
        #if canImport(AppKit) && os(macOS)
        let trimmed = Array(entries.prefix(maxEntries))
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        #endif
    }

    /// Adds a new entry, trimming old entries if needed
    public static func addEntry(_ entry: CommandHistoryEntry, to entries: inout [CommandHistoryEntry]) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
    }

    /// Exports history entries as a shell script
    public static func exportAsShellScript(_ entries: [CommandHistoryEntry]) -> String {
        var lines = ["#!/bin/bash", "# DICOMToolbox Command History", "# Exported on \(ISO8601DateFormatter().string(from: Date()))", ""]
        for entry in entries.reversed() {
            let dateFormatter = ISO8601DateFormatter()
            lines.append("# \(dateFormatter.string(from: entry.timestamp))")
            lines.append(entry.copyableCommand)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Clears all saved history
    public static func clear() {
        #if canImport(AppKit) && os(macOS)
        UserDefaults.standard.removeObject(forKey: storageKey)
        #endif
    }
}
