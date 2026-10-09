import Foundation

// NEMA-verified: 2026a, checked 2026-09-28 — carries no DICOM-standard data (connection pooling)
/// Configuration for HTTP connection pooling
///
/// Controls connection lifecycle, limits, and behavior for HTTP/2 multiplexing
/// and connection reuse.
public struct HTTPConnectionPoolConfiguration: Sendable, Hashable {
    /// Maximum number of concurrent connections per host
    public let maxConnectionsPerHost: Int
    
    /// Maximum number of concurrent requests per connection (HTTP/2 streams)
    public let maxStreamsPerConnection: Int
    
    /// Time in seconds before an idle connection is closed
    public let idleTimeout: TimeInterval
    
    /// Maximum age in seconds before a connection is recycled
    public let maxConnectionAge: TimeInterval
    
    /// Whether to enable connection keep-alive
    public let enableKeepAlive: Bool
    
    /// Whether to enable HTTP/2 multiplexing
    public let enableHTTP2: Bool
    
    /// Creates a connection pool configuration
    /// - Parameters:
    ///   - maxConnectionsPerHost: Maximum connections per host (default: 6)
    ///   - maxStreamsPerConnection: Maximum HTTP/2 streams per connection (default: 100)
    ///   - idleTimeout: Idle timeout in seconds (default: 60)
    ///   - maxConnectionAge: Maximum connection age in seconds (default: 600)
    ///   - enableKeepAlive: Enable keep-alive (default: true)
    ///   - enableHTTP2: Enable HTTP/2 (default: true)
    public init(
        maxConnectionsPerHost: Int = 6,
        maxStreamsPerConnection: Int = 100,
        idleTimeout: TimeInterval = 60,
        maxConnectionAge: TimeInterval = 600,
        enableKeepAlive: Bool = true,
        enableHTTP2: Bool = true
    ) {
        self.maxConnectionsPerHost = max(1, maxConnectionsPerHost)
        self.maxStreamsPerConnection = max(1, maxStreamsPerConnection)
        self.idleTimeout = max(1, idleTimeout)
        self.maxConnectionAge = max(1, maxConnectionAge)
        self.enableKeepAlive = enableKeepAlive
        self.enableHTTP2 = enableHTTP2
    }
    
    /// Default configuration suitable for most use cases
    public static let `default` = HTTPConnectionPoolConfiguration()
    
    /// High-throughput configuration for busy servers
    public static let highThroughput = HTTPConnectionPoolConfiguration(
        maxConnectionsPerHost: 10,
        maxStreamsPerConnection: 200,
        idleTimeout: 120,
        maxConnectionAge: 1200
    )
    
    /// Low-resource configuration for constrained environments
    public static let lowResource = HTTPConnectionPoolConfiguration(
        maxConnectionsPerHost: 2,
        maxStreamsPerConnection: 50,
        idleTimeout: 30,
        maxConnectionAge: 300
    )
}

/// Statistics for HTTP connection pooling
public struct HTTPConnectionPoolStatistics: Sendable {
    /// Total number of connections across all hosts
    public let totalConnections: Int
    
    /// Number of active (in-use) connections
    public let activeConnections: Int
    
    /// Number of idle (available) connections
    public let idleConnections: Int
    
    /// Total number of HTTP/2 streams currently active
    public let activeStreams: Int
    
    /// Total connections created since start
    public let connectionsCreated: Int
    
    /// Total connections closed since start
    public let connectionsClosed: Int
    
    /// Total connections reused
    public let connectionsReused: Int
    
    /// Number of times a connection was recycled due to age
    public let connectionsRecycled: Int
    
    /// Number of requests that waited for a connection
    public let requestsQueued: Int
    
    /// Creates connection pool statistics
    public init(
        totalConnections: Int,
        activeConnections: Int,
        idleConnections: Int,
        activeStreams: Int,
        connectionsCreated: Int,
        connectionsClosed: Int,
        connectionsReused: Int,
        connectionsRecycled: Int,
        requestsQueued: Int
    ) {
        self.totalConnections = totalConnections
        self.activeConnections = activeConnections
        self.idleConnections = idleConnections
        self.activeStreams = activeStreams
        self.connectionsCreated = connectionsCreated
        self.connectionsClosed = connectionsClosed
        self.connectionsReused = connectionsReused
        self.connectionsRecycled = connectionsRecycled
        self.requestsQueued = requestsQueued
    }
}

/// Actor managing HTTP connection pooling and lifecycle
///
/// Implements connection pooling with HTTP/2 multiplexing support.
/// Connections are pooled per-host and automatically recycled based
/// on age and idle time.
actor HTTPConnectionPool {
    
    // MARK: - Types
    
    /// Represents a pooled HTTP connection with metadata
    struct PooledConnection {
        /// Unique identifier for this connection
        let id: UUID
        
        /// The host this connection is for
        let host: String
        
        /// When the connection was created
        let createdAt: Date
        
        /// When the connection was last used
        var lastUsedAt: Date
        
        /// Number of times this connection has been used
        var useCount: Int
        
        /// Number of active HTTP/2 streams on this connection
        var activeStreams: Int
        
        /// Creates a pooled connection
        init(host: String) {
            self.id = UUID()
            self.host = host
            self.createdAt = Date()
            self.lastUsedAt = Date()
            self.useCount = 0
            self.activeStreams = 0
        }
        
        /// Checks if the connection is idle for the specified timeout
        func isIdleFor(timeout: TimeInterval) -> Bool {
            return Date().timeIntervalSince(lastUsedAt) >= timeout
        }
        
        /// Checks if the connection has exceeded its maximum age
        func isOlderThan(age: TimeInterval) -> Bool {
            return Date().timeIntervalSince(createdAt) >= age
        }
        
        /// Checks if the connection can accept more streams
        func canAcceptStream(maxStreams: Int) -> Bool {
            return activeStreams < maxStreams
        }
        
        /// Marks the connection as used
        mutating func markUsed() {
            lastUsedAt = Date()
            useCount += 1
        }
        
        /// Acquires a stream on this connection
        mutating func acquireStream() {
            activeStreams += 1
            markUsed()
        }
        
        /// Releases a stream on this connection
        mutating func releaseStream() {
            activeStreams = max(0, activeStreams - 1)
            lastUsedAt = Date()
        }
    }
    
    // MARK: - Properties
    
    /// Configuration for the connection pool
    private let configuration: HTTPConnectionPoolConfiguration
    
    /// All connections, keyed by host
    private var connections: [String: [PooledConnection]] = [:]
    
    /// Statistics tracking
    private var stats = Stats()
    
    /// Background task for cleanup
    private var cleanupTask: Task<Void, Never>?
    
    /// Whether the pool is running
    private var isRunning = false
    
    // MARK: - Statistics Struct
    
    private struct Stats {
        var connectionsCreated: Int = 0
        var connectionsClosed: Int = 0
        var connectionsReused: Int = 0
        var connectionsRecycled: Int = 0
        var requestsQueued: Int = 0
    }
    
    // MARK: - Initialization
    
    /// Creates an HTTP connection pool
    /// - Parameter configuration: Pool configuration
    public init(configuration: HTTPConnectionPoolConfiguration = .default) {
        self.configuration = configuration
    }
    
    // MARK: - Lifecycle
    
    /// Starts the connection pool and background cleanup
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        
        // Start background cleanup task
        cleanupTask = Task { [weak self] in
            await self?.runCleanupLoop()
        }
    }
    
    /// Stops the connection pool and closes all connections
    public func stop() async {
        isRunning = false
        cleanupTask?.cancel()
        cleanupTask = nil
        
        // Close all connections
        for (host, _) in connections {
            connections[host] = []
        }
        
        // Update statistics
        let totalClosed = connections.values.reduce(0) { $0 + $1.count }
        stats.connectionsClosed += totalClosed
    }
    
    // MARK: - Connection Acquisition
    
    /// Acquires a connection for the specified host
    /// - Parameter host: The target host
    /// - Returns: Connection ID that was acquired
    public func acquireConnection(for host: String) -> UUID {
        // Try to find an available connection
        if var hostConnections = connections[host] {
            // Find connection with available streams
            if let index = hostConnections.firstIndex(where: {
                $0.canAcceptStream(maxStreams: configuration.maxStreamsPerConnection)
            }) {
                hostConnections[index].acquireStream()
                connections[host] = hostConnections
                stats.connectionsReused += 1
                return hostConnections[index].id
            }
            
            // Check if we can create a new connection
            if hostConnections.count < configuration.maxConnectionsPerHost {
                var newConnection = PooledConnection(host: host)
                newConnection.acquireStream()
                hostConnections.append(newConnection)
                connections[host] = hostConnections
                stats.connectionsCreated += 1
                return newConnection.id
            }
            
            // Wait for an existing connection (queue request)
            stats.requestsQueued += 1
            // For now, reuse the least loaded connection
            if let index = hostConnections.indices.min(by: {
                hostConnections[$0].activeStreams < hostConnections[$1].activeStreams
            }) {
                hostConnections[index].acquireStream()
                connections[host] = hostConnections
                return hostConnections[index].id
            }
        }
        
        // No connections for this host - create first one
        var newConnection = PooledConnection(host: host)
        newConnection.acquireStream()
        connections[host] = [newConnection]
        stats.connectionsCreated += 1
        return newConnection.id
    }
    
    /// Releases a stream on the connection
    /// - Parameters:
    ///   - connectionID: The connection ID
    ///   - host: The host
    public func releaseConnection(_ connectionID: UUID, for host: String) {
        guard var hostConnections = connections[host] else { return }
        
        if let index = hostConnections.firstIndex(where: { $0.id == connectionID }) {
            hostConnections[index].releaseStream()
            connections[host] = hostConnections
        }
    }
    
    // MARK: - Statistics
    
    /// Returns current connection pool statistics
    public func statistics() -> HTTPConnectionPoolStatistics {
        let totalConns = connections.values.reduce(0) { $0 + $1.count }
        let activeConns = connections.values.reduce(0) { acc, conns in
            acc + conns.filter { $0.activeStreams > 0 }.count
        }
        let idleConns = totalConns - activeConns
        let totalStreams = connections.values.reduce(0) { acc, conns in
            acc + conns.reduce(0) { $0 + $1.activeStreams }
        }
        
        return HTTPConnectionPoolStatistics(
            totalConnections: totalConns,
            activeConnections: activeConns,
            idleConnections: idleConns,
            activeStreams: totalStreams,
            connectionsCreated: stats.connectionsCreated,
            connectionsClosed: stats.connectionsClosed,
            connectionsReused: stats.connectionsReused,
            connectionsRecycled: stats.connectionsRecycled,
            requestsQueued: stats.requestsQueued
        )
    }
    
    // MARK: - Private Methods
    
    /// Background loop for cleaning up idle and old connections
    private func runCleanupLoop() async {
        while isRunning {
            // Sleep for 30 seconds between cleanups
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            
            guard !Task.isCancelled else { break }

            cleanupConnections()
        }
    }
    
    /// Cleans up idle and old connections
    private func cleanupConnections() {
        for (host, var hostConnections) in connections {
            var removedCount = 0
            
            // Remove idle connections
            hostConnections.removeAll { connection in
                let shouldRemove = connection.activeStreams == 0 && (
                    connection.isIdleFor(timeout: configuration.idleTimeout) ||
                    connection.isOlderThan(age: configuration.maxConnectionAge)
                )
                
                if shouldRemove {
                    removedCount += 1
                    if connection.isOlderThan(age: configuration.maxConnectionAge) {
                        stats.connectionsRecycled += 1
                    }
                }
                
                return shouldRemove
            }
            
            if removedCount > 0 {
                stats.connectionsClosed += removedCount
            }
            
            connections[host] = hostConnections
            
            // Remove empty host entries
            if hostConnections.isEmpty {
                connections.removeValue(forKey: host)
            }
        }
    }
}
