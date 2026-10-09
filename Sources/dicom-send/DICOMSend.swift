import Foundation
import ArgumentParser
import DICOMCore
import DICOMNetwork
// NEMA-verified: 2026a, checked 2026-10-01 — --priority values diffed against PS3.7 2026a Table 9.3-1 (C-STORE-RQ Priority: LOW 0002H, MEDIUM 0000H, HIGH 0001H: 3 of 3 match via DIMSEPriority); --transfer-syntax accepts a PS3.6 Table A-1 UID or a DICOMCore.TransferSyntax alias; port 11112 is the registered DICOM port of PS3.8 2026a 9.1.1; AE Titles are PS3.5 Table 6.2-1 VR AE (16 bytes), checked by DICOMNetwork.AETitle

@main
struct DICOMSend: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-send",
        abstract: "Send DICOM files to PACS using C-STORE protocol",
        discussion: """
            Transfers DICOM files to PACS servers using the C-STORE service.
            Supports single files, multiple files, and recursive directory traversal.
            
            The host argument accepts a hostname or IP address, optionally with a
            port suffix (host:port). Use --port to specify the port separately.
            If no port is given, the default is 11112.
            
            Examples:
              dicom-send server --port 11112 --aet SENDER file.dcm
              dicom-send server:11112 --aet SENDER study/ --recursive
              dicom-send server --port 11112 --aet SENDER *.dcm --verify
              dicom-send 192.168.1.100 --port 11112 --aet SENDER files/ --recursive --dry-run
              dicom-send server --port 11112 --aet SENDER study/ --retry 3 --verbose
            """,
        version: "1.0.0"
    )
    
    @Argument(help: "PACS server hostname or IP address, optionally with port (host:port)")
    var host: String
    
    @Option(name: .long, help: "PACS server port (default: 11112)")
    var port: UInt16?
    
    @Option(name: .long, help: "Local Application Entity Title (calling AE)")
    var aet: String
    
    @Option(name: .long, help: "Remote Application Entity Title (default: ANY-SCP)")
    var calledAet: String = "ANY-SCP"
    
    @Argument(help: "DICOM files or directories to send")
    var paths: [String]
    
    @Flag(name: .shortAndLong, help: "Recursively scan directories for DICOM files")
    var recursive: Bool = false
    
    @Flag(name: .long, help: "Verify connection with C-ECHO before sending")
    var verify: Bool = false
    
    @Option(name: .long, help: "Number of retry attempts on failure (default: 0)")
    var retry: Int = 0
    
    @Flag(name: .long, help: "Show what would be sent without actually sending")
    var dryRun: Bool = false
    
    @Flag(name: .shortAndLong, help: "Show verbose output including progress")
    var verbose: Bool = false
    
    @Option(name: .long, help: "Connection timeout in seconds (default: 60)")
    var timeout: Int = 60
    
    @Option(name: .long, help: "C-STORE Priority (0000,0700): low (0002H), medium (0000H), high (0001H) — PS3.7 Table 9.3-1 (default: medium)")
    var priority: PriorityOption = .medium

    @Option(name: .long, help: "Transfer syntax to negotiate for the C-STORE presentation context. dicom-send sends files as-is and never transcodes, so this must match the file's own transfer syntax (the send fails otherwise — use dicom-convert to change it). Omit to send the file unchanged.")
    var transferSyntax: String?

    mutating func run() async throws {
        #if canImport(Network)
        // --retry drives `0...retryAttempts`; a negative value would trap that range.
        guard retry >= 0 else {
            throw ValidationError("--retry must be zero or greater")
        }

        let serverInfo = resolveHostPort()

        let preferredTransferSyntaxUID: String?
        if let transferSyntax, !transferSyntax.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let syntax = TransferSyntax.parse(transferSyntax) else {
                throw ValidationError("Unknown transfer syntax: \(transferSyntax)")
            }
            preferredTransferSyntaxUID = syntax.uid
        } else {
            preferredTransferSyntaxUID = nil
        }
        
        // Gather files to send. Uses the SHARED DICOMSendFileGatherer (DICOMNetwork)
        // so the CLI and the CLI-parity reference enumerate a directory identically.
        let filesToSend = DICOMSendFileGatherer.gather(
            paths: paths, recursive: recursive,
            warn: verbose ? { fprintln("Warning: \($0)") } : nil)

        if filesToSend.isEmpty {
            throw ValidationError("No DICOM files found to send")
        }

        // Header via the SHARED NetworkConsole formatter (DICOMNetwork), printed to
        // STDOUT so its order/wording matches DICOMStudio's in-process console.
        print(NetworkConsole.sendHeader(
            host: serverInfo.host, port: serverInfo.port,
            callingAE: aet, calledAE: calledAet,
            priority: priority.rawValue, timeout: timeout, fileCount: filesToSend.count,
            retryAttempts: retry, transferSyntax: preferredTransferSyntaxUID, dryRun: dryRun),
            terminator: "")

        if dryRun {
            for (index, path) in filesToSend.enumerated() {
                let size = (try? Data(contentsOf: URL(fileURLWithPath: path)).count) ?? 0
                print(NetworkConsole.sendDryRunLine(
                    index: index + 1, total: filesToSend.count,
                    filename: (path as NSString).lastPathComponent, size: size), terminator: "")
            }
            print("\nDry run complete. No files were sent.")
            return
        }

        // Create executor
        let executor = SendExecutor(
            host: serverInfo.host,
            port: serverInfo.port,
            callingAE: aet,
            calledAE: calledAet,
            timeout: TimeInterval(timeout),
            priority: priority.dimseValue,
            retryAttempts: retry,
            verbose: verbose,
            preferredTransferSyntaxUID: preferredTransferSyntaxUID
        )

        // Verify connection if requested (shown unconditionally on both sides).
        if verify {
            print("Verifying connection with C-ECHO...")
            do {
                try await executor.verifyConnection()
                print("  ✅ Connection verified\n")
            } catch {
                print("  ❌ C-ECHO failed — aborting send")
                throw error
            }
        }

        // Send files
        try await executor.sendFiles(filesToSend)

        #else
        throw ValidationError("Network functionality is not available on this platform")
        #endif
    }
    
    /// Resolves the final host and port from ``--host`` and ``--port`` options.
    func resolveHostPort() -> (host: String, port: UInt16) {
        var resolvedHost = host
        var resolvedPort: UInt16 = port ?? 11112

        if resolvedHost.hasPrefix("pacs://") {
            resolvedHost = String(resolvedHost.dropFirst(7))
        }

        if let lastColon = resolvedHost.lastIndex(of: ":") {
            let portString = String(resolvedHost[resolvedHost.index(after: lastColon)...])
            if let embeddedPort = UInt16(portString) {
                resolvedHost = String(resolvedHost[..<lastColon])
                if port == nil {
                    resolvedPort = embeddedPort
                }
            }
        }

        return (resolvedHost, resolvedPort)
    }
    
}

/// The `--priority` values, mapped to the Priority (0000,0700) values of PS3.7
/// Table 9.3-1: LOW = 0002H, MEDIUM = 0000H, HIGH = 0001H.
enum PriorityOption: String, ExpressibleByArgument, CaseIterable {
    case low
    case medium
    case high
    
    var dimseValue: DIMSEPriority {
        switch self {
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        }
    }
}

/// Prints to stderr
private func fprintln(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8) ?? Data())
}
