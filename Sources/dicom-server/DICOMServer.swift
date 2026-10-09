// NEMA-verified: 2026a, checked 2026-10-01 — options: 25 options of start/status/stop/stats compared (contract rows in DICOMCLI_STANDARD_IMPLEMENTATION.md; --move-destination added); --aet / --allowed-ae / --blocked-ae / --move-destination are validated as VR AE (PS3.5 2026a Table 6.2-1, D94); the Query/Retrieve Level names in the help are PS3.4 2026a Tables C.6.1-1 / C.6.2-1 (PATIENT, STUDY, SERIES, IMAGE); default port 11112 is the registered port of PS3.8 2026a 9.1.1 (104 is the well-known one); the C-ECHO status printed by `status` is rendered by DICOMNetwork.DIMSEStatus; the target builds and is tested by dicom-serverTests (D99)
import Foundation
import ArgumentParser
import DICOMKit
import DICOMCore
import DICOMNetwork

@main
struct DICOMServer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-server",
        abstract: "Lightweight PACS server supporting C-ECHO, C-FIND, C-STORE, C-MOVE, and C-GET",
        discussion: """
            Run a lightweight PACS server for development, testing, and small-scale deployments.
            
            Supported DICOM Services:
            - C-ECHO: Verification service
            - C-FIND: Query service (PATIENT/STUDY/SERIES/IMAGE levels)
            - C-STORE: Storage service with automatic indexing
            - C-MOVE: Retrieval service
            - C-GET: Direct retrieval service
            
            Storage Backends:
            - Filesystem: Simple file-based storage
            - SQLite: Lightweight database for metadata
            - PostgreSQL: Full database for large deployments (optional)
            
            Examples:
              # Start server with default settings
              dicom-server start --aet MY_PACS --port 11112
              
              # Start with custom data directory
              dicom-server start --aet MY_PACS --port 11112 --data-dir /var/lib/dicom
              
              # Start with configuration file
              dicom-server start --config /etc/dicom-server.conf
              
              # Check server status
              dicom-server status --port 11112
            """,
        version: "1.0.0",
        subcommands: [
            StartCommand.self,
            StatusCommand.self,
            StopCommand.self,
            StatsCommand.self
        ],
        defaultSubcommand: StartCommand.self
    )
}

// MARK: - Start Command

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
struct StartCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Start the DICOM server",
        discussion: """
            Start a DICOM server that accepts incoming connections and
            handles C-ECHO, C-FIND, C-STORE, C-MOVE, and C-GET requests.
            """
    )
    
    @Option(name: [.customLong("aet"), .customShort("a")], help: "Application Entity Title")
    var aeTitle: String = "DICOMKIT_SCP"
    
    @Option(name: [.customLong("port"), .customShort("p")], help: "Port to listen on")
    var port: UInt16 = 11112
    
    @Option(name: .long, help: "Data directory for storing DICOM files")
    var dataDir: String = "./dicom-data"
    
    @Option(name: .long, help: "Database type: sqlite, postgres, none")
    var database: String = "sqlite"
    
    @Option(name: .long, help: "Database connection string")
    var databaseUrl: String?
    
    @Option(name: .long, help: "Configuration file path")
    var config: String?
    
    @Option(name: .long, help: "Maximum concurrent connections")
    var maxConnections: Int = 10
    
    @Option(name: .long, help: "Maximum PDU size in bytes")
    var maxPduSize: UInt32 = 16384
    
    @Option(name: .long, help: "Allowed calling AE titles (comma-separated)")
    var allowedAE: String?
    
    @Option(name: .long, help: "Blocked calling AE titles (comma-separated)")
    var blockedAE: String?

    @Option(name: .long, parsing: .singleValue,
            help: "C-MOVE destination as AE=host:port (repeatable); an unknown Move Destination is refused with A801")
    var moveDestination: [String] = []
    
    @Flag(name: .shortAndLong, help: "Verbose logging")
    var verbose: Bool = false
    
    @Flag(name: .long, help: "Enable TLS/SSL")
    var tls: Bool = false
    
    mutating func run() async throws {
        // Load configuration from file if provided
        if let configPath = config {
            let serverConfig = try ServerConfiguration.load(from: configPath).validated()
            try await startWithConfig(serverConfig)
            return
        }
        
        // Create configuration from command-line arguments
        let serverConfig = try createConfiguration()
        try await startWithConfig(serverConfig)
    }
    
    private func createConfiguration() throws -> ServerConfiguration {
        // Parse allowed/blocked AE titles
        let allowedAEs = allowedAE?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let blockedAEs = blockedAE?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        // Determine database URL
        let dbUrl: String
        if let providedUrl = databaseUrl {
            dbUrl = providedUrl
        } else if database == "sqlite" {
            dbUrl = "sqlite://\(dataDir)/dicom-server.db"
        } else if database == "none" {
            dbUrl = ""
        } else {
            throw ServerError.invalidConfiguration("Unsupported database type: \(database)")
        }
        
        var destinations: [String: DestinationAE] = [:]
        for spec in moveDestination {
            let (ae, destination) = try ServerConfiguration.parseDestination(spec)
            destinations[ae] = destination
        }
        
        // AE titles are checked as VR AE (PS3.5 Table 6.2-1)
        return try ServerConfiguration(
            aeTitle: aeTitle,
            port: port,
            dataDirectory: dataDir,
            databaseURL: dbUrl,
            maxConcurrentConnections: maxConnections,
            maxPDUSize: maxPduSize,
            allowedCallingAETitles: allowedAEs.map { Set($0) },
            blockedCallingAETitles: blockedAEs.map { Set($0) },
            enableTLS: tls,
            verbose: verbose,
            knownDestinations: destinations
        ).validated()
    }
    
    private func startWithConfig(_ config: ServerConfiguration) async throws {
        print("Starting DICOM Server...")
        print("  AE Title: \(config.aeTitle)")
        print("  Port: \(config.port)")
        print("  Data Directory: \(config.dataDirectory)")
        print("  Database: \(config.databaseURL.isEmpty ? "None" : config.databaseURL)")
        print("  Max Connections: \(config.maxConcurrentConnections)")
        
        // Create data directory if it doesn't exist
        try FileManager.default.createDirectory(
            atPath: config.dataDirectory,
            withIntermediateDirectories: true
        )
        
        // Initialize server components
        let server = try PACSServer(configuration: config)
        
        if config.verbose {
            print("\nServer Configuration:")
            print("  Max PDU Size: \(config.maxPDUSize) bytes")
            print("  TLS Enabled: \(config.enableTLS)")
            if let allowed = config.allowedCallingAETitles {
                print("  Allowed AE Titles: \(allowed.joined(separator: ", "))")
            }
            if let blocked = config.blockedCallingAETitles {
                print("  Blocked AE Titles: \(blocked.joined(separator: ", "))")
            }
        }
        
        print("\n✓ DICOM Server started successfully")
        print("Listening on port \(config.port)...")
        print("Press Ctrl+C to stop the server")
        
        // Start the server
        try await server.start()
        
        // Keep running until interrupted
        try await withTaskCancellationHandler {
            try await Task.sleep(nanoseconds: UInt64.max)
        } onCancel: {
            Task {
                await server.stop()
            }
        }
    }
}

// MARK: - Status Command

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Check server status",
        discussion: """
            Check if the DICOM server is running and responsive.
            """
    )
    
    @Option(name: [.customLong("host"), .customShort("h")], help: "Server host")
    var host: String = "localhost"
    
    @Option(name: [.customLong("port"), .customShort("p")], help: "Server port")
    var port: UInt16 = 11112
    
    @Option(name: .long, help: "Calling AE Title")
    var callingAE: String = "DICOM_ECHO"
    
    @Option(name: .long, help: "Called AE Title")
    var calledAE: String = "DICOMKIT_SCP"
    
    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false
    
    mutating func run() async throws {
        if verbose {
            print("Checking server status...")
            print("  Host: \(host)")
            print("  Port: \(port)")
            print("  Calling AE: \(callingAE)")
            print("  Called AE: \(calledAE)")
        }
        
        // Perform C-ECHO to check if server is running
        #if canImport(Network)
        do {
            let result = try await DICOMVerificationService.echo(
                host: host,
                port: port,
                callingAE: callingAE,
                calledAE: calledAE,
                timeout: 10.0
            )
            guard result.success else { throw ExitCode.failure }
            print("✓ Server is running and responsive")
            if verbose {
                print("  Status: \(result.status)")
                print("  Round-trip time: \(String(format: "%.3f", result.roundTripTime))s")
            }
        } catch {
            print("✗ Server is not responding")
            if verbose {
                print("  Error: \(error)")
            }
            throw ExitCode.failure
        }
        #else
        print("✗ Network operations not supported on this platform")
        throw ExitCode.failure
        #endif
    }
}

// MARK: - Stop Command

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
struct StopCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop the DICOM server",
        discussion: """
            Stop a running DICOM server gracefully.
            """
    )
    
    @Option(name: [.customLong("port"), .customShort("p")], help: "Server port")
    var port: UInt16 = 11112
    
    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false
    
    mutating func run() async throws {
        if verbose {
            print("Stopping DICOM server on port \(port)...")
        }
        
        // In a production implementation, this would send a shutdown signal
        // For now, we'll print a message
        print("To stop the server, send SIGINT (Ctrl+C) to the running process")
        
        // TODO: Implement proper shutdown mechanism with PID file or REST API
    }
}

// MARK: - Stats Command

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
struct StatsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stats",
        abstract: "Display server statistics"
    )
    
    @Option(name: .shortAndLong, help: "Server host")
    var host: String = "localhost"
    
    @Option(name: .shortAndLong, help: "Server port")
    var port: UInt16 = 11112
    
    @Option(name: .long, help: "Calling AE Title")
    var callingAe: String = "DICOM_STATS"
    
    @Option(name: .long, help: "Called AE Title")
    var calledAe: String = "DICOMKIT_SCP"
    
    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false
    
    func run() async throws {
        #if canImport(Network)
        if verbose {
            print("Connecting to DICOM server at \(host):\(port)...")
        }
        
        // For now, just perform a C-ECHO to check if server is running
        // In a full implementation, we would query the server for statistics
        // via a custom DICOM service or REST API
        
        let result = try await DICOMVerificationService.echo(
            host: host,
            port: port,
            callingAE: callingAe,
            calledAE: calledAe,
            timeout: 10.0
        )
        
        if result.success {
            print("Server is running at \(host):\(port)")
            print()
            print("Note: Detailed statistics require server-side implementation.")
            print("Consider adding a REST API endpoint for statistics retrieval.")
            print()
            print("To view real-time server statistics, check the server logs or")
            print("implement a management interface.")
        } else {
            print("Error: Unable to connect to server")
            throw ExitCode.failure
        }
        #else
        print("Error: Network operations not supported on this platform")
        throw ExitCode.failure
        #endif
    }
}
