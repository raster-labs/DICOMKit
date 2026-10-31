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
    // Remains true for the entire start() call, including its run loop/cleanup.
    private var isStarting = false
    private var currentRunID: UUID?
    private var isStopping = false
    private var stopRequested = false
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []
    private var listenerFailure: String?
    private var activeSessions: [UUID: ServerSession] = [:]
    
    public init(configuration: ServerConfiguration) throws {
        self.configuration = try configuration.validated()
        
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
        guard !isRunning, !isStarting, !isStopping else {
            throw ServerError.invalidConfiguration("Server is already running or starting")
        }
        isStarting = true
        defer { isStarting = false }
        let runID = UUID()
        currentRunID = runID
        stopRequested = false
        listenerFailure = nil
        do {
            await logger.info("Starting DICOM server on port \(configuration.port)", context: "PACSServer")
            try await storage.acquireExclusiveAccess()
            if let database {
                try await database.initialize(storage: storage)
                let count = await database.instanceCount
                await logger.info("Filesystem reindex complete: \(count) instance(s)", context: "PACSServer")
            } else {
                // Validate existing files even when queries are explicitly disabled.
                _ = try await storage.scanForIndex()
                await logger.info("Index disabled (--database none); FIND/GET/MOVE unavailable", context: "PACSServer")
            }
            try Task.checkCancellation()
            guard !stopRequested else { throw CancellationError() }
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: configuration.port)!)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                Task { await self.handleListenerState(state, runID: runID) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                Task { await self.handleNewConnection(connection, runID: runID) }
            }
            isRunning = true
            listener.start(queue: .global(qos: .userInitiated))
            while isRunning { try await Task.sleep(nanoseconds: 100_000_000) }
            if let listenerFailure { throw ServerError.invalidConfiguration(listenerFailure) }
        } catch {
            // Retain lifecycle ownership until cleanup finishes, so a later
            // start cannot acquire a lock that this start then releases.
            await stop()
            await storage.releaseExclusiveAccess()
            throw error
        }
    }

    /// Stop the PACS server
    public func stop() async {
        stopRequested = true
        currentRunID = nil
        if isStopping {
            await withCheckedContinuation { stopWaiters.append($0) }
            return
        }
        guard isRunning else { return }
        isStopping = true
        isRunning = false
        listener?.cancel()
        
        await logger.info("Stopping DICOM server", context: "PACSServer")
        
        if configuration.verbose {
            print("[PACSServer] Stopping server...")
        }
        
        // Cancel all active sessions
        let sessions = Array(activeSessions.values)
        for session in sessions { await session.cancel() }
        for session in sessions { await session.waitForPendingRequests() }
        activeSessions.removeAll()
        
        // Stop listener
        listener?.cancel()
        listener = nil
        isRunning = false
        await storage.releaseExclusiveAccess()
        isStopping = false
        let waiters = stopWaiters
        stopWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        
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
    
    private func handleListenerState(_ state: NWListener.State, runID: UUID) async {
        guard currentRunID == runID else { return }
        switch state {
        case .ready:
            print("✓ DICOM Server started successfully; listening on port \(configuration.port)")
            print("Press Ctrl+C to stop the server")
            Task {
                await logger.info("Listener ready", context: "PACSServer")
            }
            if configuration.verbose {
                print("[PACSServer] Listener ready")
            }
        case .failed(let error):
            listenerFailure = "Listener failed: \(error)"
            Task {
                await logger.error("Listener failed", error: error, context: "PACSServer")
            }
            if configuration.verbose {
                print("[PACSServer] Listener failed: \(error)")
            }
            await stop()
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
    
    private func handleNewConnection(_ connection: NWConnection, runID: UUID) async {
        guard isRunning, currentRunID == runID else { connection.cancel(); return }
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
        
        // stop() can run while the statistics/logging awaits above yield.
        // Do not insert an untracked worker after shutdown took its snapshot.
        guard isRunning, currentRunID == runID else {
            connection.cancel()
            await statistics.recordConnectionEnd()
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
