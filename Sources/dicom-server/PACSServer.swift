// NEMA-verified: 2026a, checked 2026-10-01 — carries no DICOM-standard data (NWListener lifecycle, connection limit, session bookkeeping)
import Foundation
import DICOMCore
import DICOMNetwork

#if canImport(Network)
import Network

/// PACS Server implementation
///
/// Provides C-ECHO, C-FIND, C-STORE, C-MOVE, and C-GET services
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public actor PACSServer {
    private let configuration: ServerConfiguration
    private let storage: StorageManager
    private let database: DatabaseManager?
    private let statistics: ServerStatistics
    private let logger: ServerLogger
    private var listener: NWListener?
    private var isRunning = false
    private var activeSessions: [UUID: ServerSession] = [:]
    
    public init(configuration: ServerConfiguration) throws {
        self.configuration = configuration
        
        // Initialize storage manager
        self.storage = try StorageManager(dataDirectory: configuration.dataDirectory)
        
        // Initialize database manager if configured
        if !configuration.databaseURL.isEmpty {
            self.database = try DatabaseManager(connectionString: configuration.databaseURL)
        } else {
            self.database = nil
        }
        
        // Initialize statistics
        self.statistics = ServerStatistics()
        
        // Initialize logger
        self.logger = try ServerLogger(
            minimumLevel: configuration.verbose ? .debug : .info,
            includeTimestamp: true,
            includeLevel: true,
            logFilePath: nil // TODO: Add log file configuration
        )
    }
    
    /// Start the PACS server
    public func start() async throws {
        guard !isRunning else {
            throw ServerError.invalidConfiguration("Server is already running")
        }
        
        await logger.info("Starting DICOM server on port \(configuration.port)", context: "PACSServer")
        await logger.info("AE Title: \(configuration.aeTitle)", context: "PACSServer")
        
        // Initialize database if configured
        if let db = database {
            try await db.initialize()
        }
        
        // Create listener
        let parameters = NWParameters.tcp
        let port = NWEndpoint.Port(rawValue: configuration.port)!
        
        let listener = try NWListener(using: parameters, on: port)
        self.listener = listener
        
        // Set up listener state handler
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task {
                await self.handleListenerState(state)
            }
        }
        
        // Set up new connection handler
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task {
                await self.handleNewConnection(connection)
            }
        }
        
        // Start listening
        listener.start(queue: .global(qos: .userInitiated))
        isRunning = true
        
        if configuration.verbose {
            print("[PACSServer] Server started on port \(configuration.port)")
        }
        
        // Wait for the server to stop
        while isRunning {
            try await Task.sleep(nanoseconds: 1_000_000_000) // Sleep for 1 second
        }
    }
    
    /// Stop the PACS server
    public func stop() async {
        guard isRunning else { return }
        
        await logger.info("Stopping DICOM server", context: "PACSServer")
        
        if configuration.verbose {
            print("[PACSServer] Stopping server...")
        }
        
        // Cancel all active sessions
        for (_, session) in activeSessions {
            await session.cancel()
        }
        activeSessions.removeAll()
        
        // Stop listener
        listener?.cancel()
        listener = nil
        isRunning = false
        
        await logger.info("Server stopped", context: "PACSServer")
        await logger.flush()
        
        if configuration.verbose {
            print("[PACSServer] Server stopped")
        }
    }
    
    /// Get current statistics
    public func getStatistics() async -> StatisticsSummary {
        return await statistics.getSummary()
    }
    
    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            Task {
                await logger.info("Listener ready", context: "PACSServer")
            }
            if configuration.verbose {
                print("[PACSServer] Listener ready")
            }
        case .failed(let error):
            Task {
                await logger.error("Listener failed", error: error, context: "PACSServer")
            }
            if configuration.verbose {
                print("[PACSServer] Listener failed: \(error)")
            }
            Task { await self.stop() }
        case .cancelled:
            Task {
                await logger.info("Listener cancelled", context: "PACSServer")
            }
            if configuration.verbose {
                print("[PACSServer] Listener cancelled")
            }
        default:
            break
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) async {
        let sessionId = UUID()
        
        await statistics.recordConnectionStart()
        await logger.debug("New connection: \(sessionId)", context: "PACSServer")
        
        if configuration.verbose {
            print("[PACSServer] New connection: \(sessionId)")
        }
        
        // Check if we've reached max connections
        if activeSessions.count >= configuration.maxConcurrentConnections {
            await logger.warning("Max connections reached, rejecting connection", context: "PACSServer")
            if configuration.verbose {
                print("[PACSServer] Max connections reached, rejecting connection")
            }
            connection.cancel()
            await statistics.recordConnectionFailure()
            return
        }
        
        // Create and start session
        let session = ServerSession(
            id: sessionId,
            connection: connection,
            configuration: configuration,
            storage: storage,
            database: database,
            statistics: statistics,
            logger: logger
        )
        
        activeSessions[sessionId] = session
        
        await session.start()
        
        // Remove session when done
        activeSessions.removeValue(forKey: sessionId)
        await statistics.recordConnectionEnd()
        await logger.debug("Session ended: \(sessionId)", context: "PACSServer")
        
        if configuration.verbose {
            print("[PACSServer] Session ended: \(sessionId)")
        }
    }
}

#else
// Fallback for platforms without Network framework
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public actor PACSServer {
    public init(configuration: ServerConfiguration) throws {
        throw ServerError.invalidConfiguration("Network operations not supported on this platform")
    }
    
    public func start() async throws {
        throw ServerError.invalidConfiguration("Network operations not supported on this platform")
    }
    
    public func stop() async {
    }
    
    public func getStatistics() async -> StatisticsSummary {
        // Return empty statistics for unsupported platforms
        return StatisticsSummary(
            totalConnections: 0,
            activeConnections: 0,
            failedConnections: 0,
            echoRequests: 0,
            storeRequests: 0,
            findRequests: 0,
            moveRequests: 0,
            getRequests: 0,
            successfulStores: 0,
            failedStores: 0,
            successfulFinds: 0,
            failedFinds: 0,
            successfulMoves: 0,
            failedMoves: 0,
            successfulGets: 0,
            failedGets: 0,
            bytesReceived: 0,
            bytesSent: 0,
            totalStoredInstances: 0,
            startTime: Date(),
            uptime: 0
        )
    }
}
#endif
