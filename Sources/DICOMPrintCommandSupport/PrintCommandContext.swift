import Foundation
import ArgumentParser

/// Per-invocation effects shared by the terminal and Workshop. No process-wide
/// stdout replacement, user-default mutation, or shell evaluation is involved.
public struct PrintCommandContext: Sendable {
    public let printersURL: URL
    public let defaultSCPConfigURL: URL
    public let output: @Sendable (String) -> Void
    public let diagnostic: @Sendable (String) -> Void
    public let openFile: @Sendable (URL) -> Void
    public let handlesProcessSignals: Bool
    public let listenerState: @Sendable (UInt16?) -> Void

    public static var defaultSettingsDirectory: URL {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["DICOMKIT_PRINT_TEST_SETTINGS_DIRECTORY"],
           path.hasPrefix("/"), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/dicomkit", isDirectory: true)
    }

    public init(
        printersURL: URL = defaultSettingsDirectory.appendingPathComponent("printers.json"),
        defaultSCPConfigURL: URL = defaultSettingsDirectory.appendingPathComponent("printscp.json"),
        output: @escaping @Sendable (String) -> Void,
        diagnostic: @escaping @Sendable (String) -> Void,
        openFile: @escaping @Sendable (URL) -> Void = { _ in },
        handlesProcessSignals: Bool = false,
        listenerState: @escaping @Sendable (UInt16?) -> Void = { _ in }
    ) {
        self.printersURL = printersURL
        self.defaultSCPConfigURL = defaultSCPConfigURL
        self.output = output
        self.diagnostic = diagnostic
        self.openFile = openFile
        self.handlesProcessSignals = handlesProcessSignals
        self.listenerState = listenerState
    }

    public static var process: PrintCommandContext {
        PrintCommandContext(
            output: { print($0) },
            diagnostic: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) },
            openFile: { url in
                #if os(macOS)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = [url.path]
                try? process.run()
                #endif
            },
            handlesProcessSignals: true
        )
    }

    /// Matches the terminal's parser/validation versus runtime failure codes.
    public static func exitCode(for error: Error) -> Int {
        Int(PrintSCUCommand.exitCode(for: error).rawValue)
    }
}

public protocol PrintExecutableCommand: AsyncParsableCommand {
    func execute(context: PrintCommandContext) async throws
}

extension PrintExecutableCommand {
    public mutating func run() async throws {
        try await execute(context: .process)
    }
}
