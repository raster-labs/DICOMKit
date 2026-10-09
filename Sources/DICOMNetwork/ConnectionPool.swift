import Foundation
import DICOMCore
// NEMA-verified: 2026a, checked 2026-09-28 — carries only the Verification SOP Class and the two default transfer syntaxes (registered in PS3.6 2026a Table A-1) and the C-ECHO service of PS3.7 2026a §9.1.5; no other standard data

#if canImport(Network)

// MARK: - Connection Pool Configuration

/// Configuration for a DICOM Connection Pool
///
/// Contains all the parameters needed to manage a pool of DICOM associations
/// for efficient reuse.
///
/// ## Usage
///
/// ```swift
/// let config = ConnectionPoolConfiguration(
///     maxConnections: 5,
///     minConnections: 1,
///     idleTimeout: 300,  // 5 minutes
///     healthCheckInterval: 60  // 1 minute
/// )
/// ```
public struct ConnectionPoolConfiguration: Sendable, Hashable {
    /// Maximum number of connections in the pool
    public let maxConnections: Int
    
    /// Minimum number of connections to maintain (warm pool)
    public let minConnections: Int
    
    /// Time in seconds before an idle connection is closed
    public let idleTimeout: TimeInterval
    
    /// Interval in seconds for periodic health checks using C-ECHO
    /// Set to `nil` to disable health checks
    public let healthCheckInterval: TimeInterval?
    
    /// Maximum time to wait for an available connection in seconds
    public let acquireTimeout: TimeInterval
    
    /// Whether to validate connections before returning them from the pool
    public let validateOnAcquire: Bool
    
    /// Creates a connection pool configuration
    ///
    /// - Parameters:
    ///   - maxConnections: Maximum connections in pool (default: 10)
    ///   - minConnections: Minimum connections to maintain (default: 0)
    ///   - idleTimeout: Idle timeout in seconds (default: 300 = 5 minutes)
    ///   - healthCheckInterval: Health check interval in seconds (default: 60, nil to disable)
    ///   - acquireTimeout: Maximum wait time to acquire a connection (default: 30 seconds)
    ///   - validateOnAcquire: Validate connections before use (default: false)
    public init(
        maxConnections: Int = 10,
        minConnections: Int = 0,
        idleTimeout: TimeInterval = 300,
        healthCheckInterval: TimeInterval? = 60,
        acquireTimeout: TimeInterval = 30,
        validateOnAcquire: Bool = false
    ) {
        self.maxConnections = max(1, maxConnections)
        self.minConnections = max(0, min(minConnections, maxConnections))
        self.idleTimeout = max(1, idleTimeout)
        self.healthCheckInterval = healthCheckInterval.map { max(1, $0) }
        self.acquireTimeout = max(1, acquireTimeout)
        self.validateOnAcquire = validateOnAcquire
    }
    
    /// Default connection pool configuration
    public static let `default` = ConnectionPoolConfiguration()
    
    /// Configuration optimized for high throughput
    public static let highThroughput = ConnectionPoolConfiguration(
        maxConnections: 20,
        minConnections: 5,
        idleTimeout: 600,
        healthCheckInterval: 120,
        acquireTimeout: 60,
        validateOnAcquire: false
    )
    
    /// Configuration optimized for low resource usage
    public static let lowResource = ConnectionPoolConfiguration(
        maxConnections: 3,
        minConnections: 0,
        idleTimeout: 60,
        healthCheckInterval: nil,  // Disable health checks
        acquireTimeout: 15,
        validateOnAcquire: true
    )
}

// MARK: - Pooled Connection

/// A pooled DICOM connection wrapper
///
/// Contains an association along with metadata for pool management.
public struct PooledConnection: Sendable {
    /// Unique identifier for this pooled connection
    public let id: UUID
    
    /// The underlying DICOM association
    public let association: Association
    
    /// Timestamp when this connection was created
    public let createdAt: Date
    
    /// Timestamp of the last activity on this connection
    public internal(set) var lastUsedAt: Date
    
    /// Number of times this connection has been used
    public internal(set) var useCount: Int
    
    /// Creates a new pooled connection
    init(association: Association) {
        self.id = UUID()
        self.association = association
        self.createdAt = Date()
        self.lastUsedAt = Date()
        self.useCount = 0
    }
    
    /// Updates the last used timestamp and increments use count
    mutating func markUsed() {
        lastUsedAt = Date()
        useCount += 1
    }
    
    /// Whether this connection has been idle for longer than the specified timeout
    func isIdleFor(timeout: TimeInterval) -> Bool {
        Date().timeIntervalSince(lastUsedAt) > timeout
    }
}

// MARK: - Connection Pool Statistics

/// Statistics about the connection pool
public struct ConnectionPoolStatistics: Sendable {
    /// Current number of connections in the pool (available + in use)
    public let totalConnections: Int
    
    /// Number of connections currently available
    public let availableConnections: Int
    
    /// Number of connections currently in use
    public let inUseConnections: Int
    
    /// Total number of connections created since pool creation
    public let connectionsCreated: Int
    
    /// Total number of connections closed since pool creation
    public let connectionsClosed: Int
    
    /// Number of successful health checks
    public let healthChecksSucceeded: Int
    
    /// Number of failed health checks
    public let healthChecksFailed: Int
    
    /// Number of times a connection was acquired from the pool
    public let acquisitionCount: Int
    
    /// Number of times acquire timed out
    public let acquisitionTimeouts: Int
}

// MARK: - Connection Pool

/// DICOM Connection Pool for efficient association reuse
///
/// Manages a pool of DICOM associations to reduce the overhead of establishing
/// new connections for each operation. Connections are validated using C-ECHO
/// health checks.
///
/// Reference: PS3.7 Section 9.1.5 - C-ECHO Service
///
/// ## Usage
///
/// ```swift
/// let config = try DICOMClientConfiguration(
///     host: "pacs.hospital.com",
///     port: 11112,
///     callingAE: "MY_SCU",
///     calledAE: "PACS"
/// )
///
/// let pool = ConnectionPool(
///     clientConfiguration: config,
///     poolConfiguration: .default
/// )
///
/// // Start the pool (begins health check timer)
/// try await pool.start()
///
/// // Acquire a connection for use
/// let connection = try await pool.acquire(
///     presentationContexts: [verificationContext]
/// )
///
/// // Use the connection...
///
/// // Release back to pool
/// await pool.release(connection)
///
/// // Stop the pool when done
/// await pool.stop()
/// ```
public actor ConnectionPool {
    
    // MARK: - Properties
    
    /// The DICOM client configuration for creating connections
    public let clientConfiguration: DICOMClientConfiguration
    
    /// The pool configuration
    public let poolConfiguration: ConnectionPoolConfiguration
    
    /// Available connections ready for use
    private var availableConnections: [PooledConnection] = []
    
    /// Connections currently in use
    private var inUseConnections: [UUID: PooledConnection] = [:]
    
    /// Statistics tracking
    private var connectionsCreated: Int = 0
    private var connectionsClosed: Int = 0
    private var healthChecksSucceeded: Int = 0
    private var healthChecksFailed: Int = 0
    private var acquisitionCount: Int = 0
    private var acquisitionTimeouts: Int = 0
    
    /// Whether the pool is currently running
    private var isRunning: Bool = false
    
    /// Health check task
    private var healthCheckTask: Task<Void, Never>?
    
    /// Idle cleanup task
    private var idleCleanupTask: Task<Void, Never>?
    
    /// Waiters for available connections (keyed by unique ID)
    private var waiters: [UUID: CheckedContinuation<PooledConnection, Error>] = [:]
    
    // MARK: - Initialization
    
    /// Creates a new connection pool
    ///
    /// - Parameters:
    ///   - clientConfiguration: Configuration for creating DICOM connections
    ///   - poolConfiguration: Pool management configuration
    public init(
        clientConfiguration: DICOMClientConfiguration,
        poolConfiguration: ConnectionPoolConfiguration = .default
    ) {
        self.clientConfiguration = clientConfiguration
        self.poolConfiguration = poolConfiguration
    }
    
    // MARK: - Pool Lifecycle
    
    /// Starts the connection pool
    ///
    /// Begins periodic health checks and idle connection cleanup.
    public func start() async throws {
        guard !isRunning else { return }
        isRunning = true
        
        // Start health check timer if configured
        if let interval = poolConfiguration.healthCheckInterval {
            healthCheckTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(interval))
                    guard !Task.isCancelled else { break }
                    guard let self = self else { break }
                    await self.performHealthChecks()
                }
            }
        }
        
        // Capture idleTimeout before task to avoid accessing self later
        let idleTimeout = poolConfiguration.idleTimeout
        
        // Start idle cleanup timer
        idleCleanupTask = Task { [weak self] in
            let checkInterval = min(60.0, idleTimeout / 2)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(checkInterval))
                guard !Task.isCancelled else { break }
                guard let self = self else { break }
                await self.cleanupIdleConnections()
            }
        }
        
        // Warm up the pool if minConnections > 0
        if poolConfiguration.minConnections > 0 {
            for _ in 0..<poolConfiguration.minConnections {
                guard availableConnections.count + inUseConnections.count < poolConfiguration.maxConnections else { break }
                do {
                    let connection = try await createConnection(presentationContexts: [])
                    availableConnections.append(connection)
                } catch {
                    // Log but don't fail - warm-up is best effort
                    break
                }
            }
        }
    }
    
    /// Stops the connection pool
    ///
    /// Cancels health checks and closes all connections.
    public func stop() async {
        isRunning = false
        
        // Cancel background tasks
        healthCheckTask?.cancel()
        healthCheckTask = nil
        idleCleanupTask?.cancel()
        idleCleanupTask = nil
        
        // Fail all waiters
        for (_, waiter) in waiters {
            waiter.resume(throwing: DICOMNetworkError.poolShutdown)
        }
        waiters.removeAll()
        
        // Close all available connections
        for connection in availableConnections {
            await closeConnection(connection)
        }
        availableConnections.removeAll()
        
        // Close all in-use connections
        for (_, connection) in inUseConnections {
            await closeConnection(connection)
        }
        inUseConnections.removeAll()
    }
    
    // MARK: - Connection Acquisition
    
    /// Acquires a connection from the pool
    ///
    /// If no connection is available and the pool is not at capacity, a new
    /// connection is created. If the pool is at capacity, this method waits
    /// up to `acquireTimeout` for a connection to become available.
    ///
    /// - Parameter presentationContexts: The presentation contexts needed for the association
    /// - Returns: A pooled connection ready for use
    /// - Throws: `DICOMNetworkError.poolExhausted` if no connection available within timeout
    public func acquire(
        presentationContexts: [PresentationContext]
    ) async throws -> PooledConnection {
        guard isRunning else {
            throw DICOMNetworkError.poolShutdown
        }
        
        acquisitionCount += 1
        
        // Try to get an available connection
        if let connection = await getAvailableConnection(presentationContexts: presentationContexts) {
            return connection
        }
        
        // If we can create a new connection, do so
        let totalConnections = availableConnections.count + inUseConnections.count
        if totalConnections < poolConfiguration.maxConnections {
            let connection = try await createConnection(presentationContexts: presentationContexts)
            var mutableConnection = connection
            mutableConnection.markUsed()
            inUseConnections[connection.id] = mutableConnection
            return mutableConnection
        }
        
        // Wait for a connection to become available
        let waiterID = UUID()
        let acquireTimeout = poolConfiguration.acquireTimeout
        
        return try await withCheckedThrowingContinuation { continuation in
            waiters[waiterID] = continuation
            
            // Set up timeout
            Task {
                try? await Task.sleep(for: .seconds(acquireTimeout))
                self.timeoutWaiter(waiterID: waiterID)
            }
        }
    }
    
    /// Helper to timeout a waiter
    private func timeoutWaiter(waiterID: UUID) {
        if let continuation = waiters.removeValue(forKey: waiterID) {
            acquisitionTimeouts += 1
            continuation.resume(throwing: DICOMNetworkError.poolExhausted)
        }
        // If waiterID not found, the continuation was already resumed by release()
    }
    
    /// Releases a connection back to the pool
    ///
    /// The connection is returned to the available pool if it's still valid,
    /// otherwise it's closed.
    ///
    /// - Parameter connection: The connection to release
    public func release(_ connection: PooledConnection) async {
        // Remove from in-use
        inUseConnections.removeValue(forKey: connection.id)
        
        // Check if connection is still usable
        guard connection.association.state == .established else {
            await closeConnection(connection)
            return
        }
        
        // Update last used time
        var mutableConnection = connection
        mutableConnection.lastUsedAt = Date()
        
        // If there are waiters, give them the connection (FIFO order via first key)
        if let firstWaiterID = waiters.keys.first,
           let waiter = waiters.removeValue(forKey: firstWaiterID) {
            mutableConnection.markUsed()
            inUseConnections[connection.id] = mutableConnection
            waiter.resume(returning: mutableConnection)
            return
        }
        
        // Return to available pool
        availableConnections.append(mutableConnection)
    }
    
    /// Removes a connection from the pool (e.g., after an error)
    ///
    /// - Parameter connection: The connection to remove
    public func remove(_ connection: PooledConnection) async {
        inUseConnections.removeValue(forKey: connection.id)
        await closeConnection(connection)
    }
    
    // MARK: - Statistics
    
    /// Gets current pool statistics
    public func statistics() -> ConnectionPoolStatistics {
        ConnectionPoolStatistics(
            totalConnections: availableConnections.count + inUseConnections.count,
            availableConnections: availableConnections.count,
            inUseConnections: inUseConnections.count,
            connectionsCreated: connectionsCreated,
            connectionsClosed: connectionsClosed,
            healthChecksSucceeded: healthChecksSucceeded,
            healthChecksFailed: healthChecksFailed,
            acquisitionCount: acquisitionCount,
            acquisitionTimeouts: acquisitionTimeouts
        )
    }
    
    // MARK: - Private Methods
    
    /// Gets an available connection if one exists
    private func getAvailableConnection(
        presentationContexts: [PresentationContext]
    ) async -> PooledConnection? {
        while !availableConnections.isEmpty {
            var connection = availableConnections.removeFirst()
            
            // Check if connection is still valid
            guard connection.association.state == .established else {
                await closeConnection(connection)
                continue
            }
            
            // Optionally validate with C-ECHO
            if poolConfiguration.validateOnAcquire {
                if await !validateConnection(connection) {
                    await closeConnection(connection)
                    continue
                }
            }
            
            // Mark as in use
            connection.markUsed()
            inUseConnections[connection.id] = connection
            return connection
        }
        
        return nil
    }
    
    /// Creates a new connection
    private func createConnection(
        presentationContexts: [PresentationContext]
    ) async throws -> PooledConnection {
        let config = clientConfiguration.pooledAssociationConfiguration()
        
        let association = Association(configuration: config)
        
        // Use default verification context if no contexts provided
        let contexts = presentationContexts.isEmpty ?
            [try PresentationContext(
                id: 1,
                abstractSyntax: verificationSOPClassUID,
                transferSyntaxes: [implicitVRLittleEndianTransferSyntaxUID, explicitVRLittleEndianTransferSyntaxUID]
            )] : presentationContexts
        
        _ = try await association.request(presentationContexts: contexts)
        connectionsCreated += 1
        
        return PooledConnection(association: association)
    }
    
    /// Closes a connection
    private func closeConnection(_ connection: PooledConnection) async {
        do {
            try await connection.association.release()
        } catch {
            // Already disconnected or error - just clean up
        }
        connectionsClosed += 1
    }
    
    /// Validates a connection using C-ECHO
    private func validateConnection(_ connection: PooledConnection) async -> Bool {
        do {
            // Get the first accepted presentation context
            guard let contextID = connection.association.negotiated?.acceptedPresentationContexts.first?.id else {
                return false
            }
            
            // Build C-ECHO request
            let echoRequest = CEchoRequest(
                messageID: UInt16.random(in: 1...65535),
                affectedSOPClassUID: verificationSOPClassUID,
                presentationContextID: contextID
            )
            
            // Send C-ECHO command
            let commandData = echoRequest.commandSet.encode()
            let pdv = PresentationDataValue(
                presentationContextID: contextID,
                isCommand: true,
                isLastFragment: true,
                data: commandData
            )
            try await connection.association.send(pdv: pdv)
            
            // Receive response
            let responsePDU = try await connection.association.receive()
            guard let responseData = responsePDU.presentationDataValues.first?.data else {
                return false
            }
            
            // Parse response
            let responseCommandSet = try CommandSet.decode(from: responseData)
            guard let status = responseCommandSet.status else {
                return false
            }
            
            return status.isSuccess
        } catch {
            return false
        }
    }
    
    /// Performs health checks on all available connections
    private func performHealthChecks() async {
        var connectionsToRemove: [Int] = []
        
        for (index, connection) in availableConnections.enumerated().reversed() {
            // Skip if connection is not in established state
            guard connection.association.state == .established else {
                connectionsToRemove.append(index)
                healthChecksFailed += 1
                continue
            }
            
            let isHealthy = await validateConnection(connection)
            if isHealthy {
                healthChecksSucceeded += 1
            } else {
                connectionsToRemove.append(index)
                healthChecksFailed += 1
            }
        }
        
        // Remove unhealthy connections
        for index in connectionsToRemove.sorted(by: >) {
            let connection = availableConnections.remove(at: index)
            await closeConnection(connection)
        }
    }
    
    /// Cleans up idle connections
    private func cleanupIdleConnections() async {
        let idleTimeout = poolConfiguration.idleTimeout
        let minConnections = poolConfiguration.minConnections
        
        // Sort by last used time (oldest first)
        availableConnections.sort { $0.lastUsedAt < $1.lastUsedAt }
        
        // Remove idle connections, but keep at least minConnections
        while availableConnections.count > minConnections {
            guard let oldest = availableConnections.first,
                  oldest.isIdleFor(timeout: idleTimeout) else {
                break
            }
            
            let connection = availableConnections.removeFirst()
            await closeConnection(connection)
        }
    }
}

// MARK: - DICOMNetworkError Extensions

extension DICOMNetworkError {
    /// Pool has been shut down
    static let poolShutdown = DICOMNetworkError.invalidState("Connection pool has been shut down")
    
    /// No connections available in the pool
    static let poolExhausted = DICOMNetworkError.timeout
}

#endif
