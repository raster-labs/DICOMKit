import Foundation
import DICOMCore
// NEMA-verified: 2026a, checked 2026-09-28 — carries no DICOM-standard data (server pool, retry and circuit-breaker plumbing over DICOMStorageService)

#if canImport(Network)

// MARK: - Server Entry

/// A single DICOM server entry in the server pool
///
/// Contains connection information and configuration for a DICOM storage server.
///
/// Reference: PS3.4 Annex B - Storage Service Class
public struct ServerEntry: Sendable, Hashable, Identifiable {
    /// Unique identifier for this server entry
    public let id: UUID
    
    /// The server hostname or IP address
    public let host: String
    
    /// The server port number
    public let port: UInt16
    
    /// The Application Entity title of the server
    public let aeTitle: AETitle
    
    /// Server priority for selection (higher is preferred)
    public let priority: Int
    
    /// Server weight for weighted selection (used in weighted round-robin)
    public let weight: Double
    
    /// Whether this server is currently enabled
    public var isEnabled: Bool
    
    /// Optional TLS configuration for secure connections
    public let tlsConfiguration: TLSConfiguration?
    
    /// User identity for authentication (optional)
    public let userIdentity: UserIdentity?
    
    /// Maximum PDU size for this server
    public let maxPDUSize: UInt32
    
    /// Connection timeout for this server
    public let timeout: TimeInterval
    
    /// Creates a server entry
    ///
    /// - Parameters:
    ///   - host: The server hostname or IP address
    ///   - port: The server port number (default: 104)
    ///   - aeTitle: The Application Entity title of the server
    ///   - priority: Server priority for selection (default: 0, higher is preferred)
    ///   - weight: Server weight for weighted selection (default: 1.0)
    ///   - isEnabled: Whether this server is enabled (default: true)
    ///   - tlsConfiguration: Optional TLS configuration
    ///   - userIdentity: Optional user identity for authentication
    ///   - maxPDUSize: Maximum PDU size (default: 64 KB, `defaultMaxPDUSize`)
    ///   - timeout: Connection timeout (default: 60 seconds)
    public init(
        host: String,
        port: UInt16 = dicomDefaultPort,
        aeTitle: AETitle,
        priority: Int = 0,
        weight: Double = 1.0,
        isEnabled: Bool = true,
        tlsConfiguration: TLSConfiguration? = nil,
        userIdentity: UserIdentity? = nil,
        maxPDUSize: UInt32 = defaultMaxPDUSize,
        timeout: TimeInterval = 60
    ) {
        self.id = UUID()
        self.host = host
        self.port = port
        self.aeTitle = aeTitle
        self.priority = priority
        self.weight = max(0.001, weight) // Ensure weight is positive
        self.isEnabled = isEnabled
        self.tlsConfiguration = tlsConfiguration
        self.userIdentity = userIdentity
        self.maxPDUSize = maxPDUSize
        self.timeout = timeout
    }
    
    /// Creates a server entry with a string AE title
    ///
    /// - Parameters:
    ///   - host: The server hostname or IP address
    ///   - port: The server port number (default: 104)
    ///   - aeTitle: The Application Entity title string
    ///   - priority: Server priority for selection (default: 0, higher is preferred)
    ///   - weight: Server weight for weighted selection (default: 1.0)
    ///   - isEnabled: Whether this server is enabled (default: true)
    ///   - tlsConfiguration: Optional TLS configuration
    ///   - userIdentity: Optional user identity for authentication
    ///   - maxPDUSize: Maximum PDU size (default: 64 KB, `defaultMaxPDUSize`)
    ///   - timeout: Connection timeout (default: 60 seconds)
    /// - Throws: `DICOMNetworkError.invalidAETitle` if the AE title is invalid
    public init(
        host: String,
        port: UInt16 = dicomDefaultPort,
        aeTitle: String,
        priority: Int = 0,
        weight: Double = 1.0,
        isEnabled: Bool = true,
        tlsConfiguration: TLSConfiguration? = nil,
        userIdentity: UserIdentity? = nil,
        maxPDUSize: UInt32 = defaultMaxPDUSize,
        timeout: TimeInterval = 60
    ) throws {
        let ae = try AETitle(aeTitle)
        self.init(
            host: host,
            port: port,
            aeTitle: ae,
            priority: priority,
            weight: weight,
            isEnabled: isEnabled,
            tlsConfiguration: tlsConfiguration,
            userIdentity: userIdentity,
            maxPDUSize: maxPDUSize,
            timeout: timeout
        )
    }
}

extension ServerEntry: CustomStringConvertible {
    public var description: String {
        let tlsStr = tlsConfiguration != nil ? " [TLS]" : ""
        let enabledStr = isEnabled ? "" : " [DISABLED]"
        return "Server(\(aeTitle)@\(host):\(port), priority=\(priority), weight=\(weight)\(tlsStr)\(enabledStr))"
    }
}

// MARK: - Server Selection Strategy

/// Strategy for selecting a server from the pool
///
/// Defines how the storage client chooses which server to use for store operations.
public enum ServerSelectionStrategy: Sendable, Hashable {
    /// Select servers in round-robin order
    ///
    /// Each server is selected in turn, cycling through the list.
    /// Provides even distribution of load across servers.
    case roundRobin
    
    /// Select server with the highest priority
    ///
    /// Servers with higher priority values are always preferred.
    /// If multiple servers have the same highest priority, the first is selected.
    case priority
    
    /// Select servers in weighted round-robin order
    ///
    /// Servers are selected in round-robin order, but servers with higher
    /// weights are selected more frequently proportional to their weight.
    case weightedRoundRobin
    
    /// Select a random server
    ///
    /// Each request randomly selects from available servers.
    case random
    
    /// Select a random server weighted by priority
    ///
    /// Servers with higher priority have a higher chance of being selected.
    case randomWeighted
    
    /// Always use the first available server
    ///
    /// Servers are ordered by priority. The first enabled server is always used.
    /// Failover occurs only when the primary server fails.
    case failover
}

extension ServerSelectionStrategy: CustomStringConvertible {
    public var description: String {
        switch self {
        case .roundRobin: return "RoundRobin"
        case .priority: return "Priority"
        case .weightedRoundRobin: return "WeightedRoundRobin"
        case .random: return "Random"
        case .randomWeighted: return "RandomWeighted"
        case .failover: return "Failover"
        }
    }
}

// MARK: - Server Pool

/// A pool of DICOM servers for storage operations
///
/// Manages a collection of servers and implements server selection strategies.
///
/// ## Usage
///
/// ```swift
/// var pool = ServerPool()
///
/// // Add servers with different priorities
/// try pool.addServer(host: "primary.hospital.com", port: 11112, aeTitle: "PRIMARY", priority: 10)
/// try pool.addServer(host: "backup.hospital.com", port: 11112, aeTitle: "BACKUP", priority: 5)
///
/// // Select a server using the current strategy
/// if let server = pool.selectServer() {
///     // Use server for storage
/// }
/// ```
public struct ServerPool: Sendable {
    
    // MARK: - Properties
    
    /// The servers in the pool
    private var servers: [ServerEntry]
    
    /// The server selection strategy
    public var selectionStrategy: ServerSelectionStrategy
    
    /// Round-robin index for selection
    private var roundRobinIndex: Int
    
    /// Weighted round-robin state
    private var weightedState: WeightedRoundRobinState
    
    // MARK: - Initialization
    
    /// Creates an empty server pool
    ///
    /// - Parameter selectionStrategy: The server selection strategy (default: roundRobin)
    public init(selectionStrategy: ServerSelectionStrategy = .roundRobin) {
        self.servers = []
        self.selectionStrategy = selectionStrategy
        self.roundRobinIndex = 0
        self.weightedState = WeightedRoundRobinState()
    }
    
    /// Creates a server pool with the given servers
    ///
    /// - Parameters:
    ///   - servers: Initial servers to add to the pool
    ///   - selectionStrategy: The server selection strategy (default: roundRobin)
    public init(
        servers: [ServerEntry],
        selectionStrategy: ServerSelectionStrategy = .roundRobin
    ) {
        self.servers = servers
        self.selectionStrategy = selectionStrategy
        self.roundRobinIndex = 0
        self.weightedState = WeightedRoundRobinState()
    }
    
    // MARK: - Server Management
    
    /// Adds a server to the pool
    ///
    /// - Parameter server: The server entry to add
    public mutating func addServer(_ server: ServerEntry) {
        servers.append(server)
        weightedState.reset()
    }
    
    /// Adds a server to the pool using connection parameters
    ///
    /// - Parameters:
    ///   - host: The server hostname or IP address
    ///   - port: The server port number (default: 104)
    ///   - aeTitle: The Application Entity title string
    ///   - priority: Server priority (default: 0)
    ///   - weight: Server weight (default: 1.0)
    /// - Throws: `DICOMNetworkError.invalidAETitle` if the AE title is invalid
    public mutating func addServer(
        host: String,
        port: UInt16 = dicomDefaultPort,
        aeTitle: String,
        priority: Int = 0,
        weight: Double = 1.0
    ) throws {
        let server = try ServerEntry(
            host: host,
            port: port,
            aeTitle: aeTitle,
            priority: priority,
            weight: weight
        )
        addServer(server)
    }
    
    /// Removes a server from the pool
    ///
    /// - Parameter id: The ID of the server to remove
    /// - Returns: The removed server entry, or nil if not found
    @discardableResult
    public mutating func removeServer(id: UUID) -> ServerEntry? {
        guard let index = servers.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let server = servers.remove(at: index)
        if roundRobinIndex >= servers.count {
            roundRobinIndex = 0
        }
        weightedState.reset()
        return server
    }
    
    /// Enables or disables a server
    ///
    /// - Parameters:
    ///   - id: The ID of the server to modify
    ///   - enabled: Whether the server should be enabled
    public mutating func setServerEnabled(id: UUID, enabled: Bool) {
        guard let index = servers.firstIndex(where: { $0.id == id }) else {
            return
        }
        servers[index].isEnabled = enabled
        weightedState.reset()
    }
    
    /// All servers in the pool
    public var allServers: [ServerEntry] {
        servers
    }
    
    /// All enabled servers in the pool
    public var enabledServers: [ServerEntry] {
        servers.filter { $0.isEnabled }
    }
    
    /// Number of servers in the pool
    public var count: Int {
        servers.count
    }
    
    /// Number of enabled servers in the pool
    public var enabledCount: Int {
        servers.filter { $0.isEnabled }.count
    }
    
    /// Whether the pool is empty
    public var isEmpty: Bool {
        servers.isEmpty
    }
    
    /// Whether there are any enabled servers
    public var hasEnabledServers: Bool {
        servers.contains { $0.isEnabled }
    }
    
    // MARK: - Server Selection
    
    /// Selects a server from the pool using the current strategy
    ///
    /// - Returns: A server entry, or nil if no servers are available
    public mutating func selectServer() -> ServerEntry? {
        let available = enabledServers
        guard !available.isEmpty else { return nil }
        
        switch selectionStrategy {
        case .roundRobin:
            return selectRoundRobin(from: available)
        case .priority:
            return selectByPriority(from: available)
        case .weightedRoundRobin:
            return selectWeightedRoundRobin(from: available)
        case .random:
            return selectRandom(from: available)
        case .randomWeighted:
            return selectRandomWeighted(from: available)
        case .failover:
            return selectFailover(from: available)
        }
    }
    
    /// Selects a specific server by ID
    ///
    /// - Parameter id: The ID of the server to select
    /// - Returns: The server entry, or nil if not found or disabled
    public func selectServer(id: UUID) -> ServerEntry? {
        servers.first { $0.id == id && $0.isEnabled }
    }
    
    // MARK: - Selection Algorithms
    
    private mutating func selectRoundRobin(from servers: [ServerEntry]) -> ServerEntry {
        let server = servers[roundRobinIndex % servers.count]
        roundRobinIndex = (roundRobinIndex + 1) % servers.count
        return server
    }
    
    private func selectByPriority(from servers: [ServerEntry]) -> ServerEntry {
        // Sort by priority descending, return first
        servers.sorted { $0.priority > $1.priority }.first!
    }
    
    private mutating func selectWeightedRoundRobin(from servers: [ServerEntry]) -> ServerEntry {
        // Smooth Weighted Round Robin (SWRR) algorithm
        // Each server has a current weight that changes over time
        
        // Initialize state if needed
        if weightedState.currentWeights.isEmpty {
            for server in servers {
                weightedState.currentWeights[server.id] = 0
            }
        }
        
        // Add effective weight to current weight for each server
        var maxWeight: Double = -Double.infinity
        var selected: ServerEntry?
        
        for server in servers {
            let currentWeight = (weightedState.currentWeights[server.id] ?? 0) + server.weight
            weightedState.currentWeights[server.id] = currentWeight
            
            if currentWeight > maxWeight {
                maxWeight = currentWeight
                selected = server
            }
        }
        
        // Decrease the selected server's weight by total weight
        if let selected = selected {
            let totalWeight = servers.reduce(0) { $0 + $1.weight }
            weightedState.currentWeights[selected.id] = maxWeight - totalWeight
        }
        
        return selected!
    }
    
    private func selectRandom(from servers: [ServerEntry]) -> ServerEntry {
        servers.randomElement()!
    }
    
    private func selectRandomWeighted(from servers: [ServerEntry]) -> ServerEntry {
        let totalWeight = servers.reduce(0) { $0 + $1.weight }
        let random = Double.random(in: 0..<totalWeight)
        
        var cumulative: Double = 0
        for server in servers {
            cumulative += server.weight
            if random < cumulative {
                return server
            }
        }
        
        return servers.last!
    }
    
    private func selectFailover(from servers: [ServerEntry]) -> ServerEntry {
        // Sort by priority descending, return first
        servers.sorted { $0.priority > $1.priority }.first!
    }
}

/// State for weighted round-robin selection
private struct WeightedRoundRobinState: Sendable {
    var currentWeights: [UUID: Double] = [:]
    
    mutating func reset() {
        currentWeights.removeAll()
    }
}

extension ServerPool: CustomStringConvertible {
    public var description: String {
        "ServerPool(\(count) servers, \(enabledCount) enabled, strategy=\(selectionStrategy))"
    }
}

// MARK: - DICOMStorageClient Configuration

/// Configuration for the DICOMStorageClient
///
/// Contains all settings for the unified storage client including server pool,
/// retry policies, and queue settings.
///
/// ## Usage
///
/// ```swift
/// // Create a configuration with servers
/// var serverPool = ServerPool(selectionStrategy: .roundRobin)
/// try serverPool.addServer(host: "pacs1.hospital.com", port: 11112, aeTitle: "PACS1", priority: 10)
/// try serverPool.addServer(host: "pacs2.hospital.com", port: 11112, aeTitle: "PACS2", priority: 5)
///
/// let config = DICOMStorageClientConfiguration(
///     callingAETitle: try AETitle("MY_SCU"),
///     serverPool: serverPool,
///     retryPolicy: .aggressive,
///     useQueue: true
/// )
/// ```
///
/// Reference: PS3.4 Annex B - Storage Service Class
public struct DICOMStorageClientConfiguration: Sendable {
    
    // MARK: - Properties
    
    /// The local Application Entity title (calling AE)
    public let callingAETitle: AETitle
    
    /// The server pool for storage destinations
    public var serverPool: ServerPool
    
    /// Retry policy for failed operations
    public let retryPolicy: RetryPolicy
    
    /// Per-SOP Class retry configuration
    public let sopClassRetryConfiguration: SOPClassRetryConfiguration?
    
    /// Whether to use the store-and-forward queue
    public let useQueue: Bool
    
    /// Store-and-forward queue configuration (required if useQueue is true)
    public let queueConfiguration: StoreAndForwardConfiguration?
    
    /// Default priority for store operations
    public let defaultPriority: DIMSEPriority
    
    /// Implementation Class UID
    public let implementationClassUID: String
    
    /// Implementation Version Name
    public let implementationVersionName: String?
    
    /// Transcoding configuration for automatic transfer syntax conversion
    public let transcodingConfiguration: TranscodingConfiguration?
    
    /// Validation configuration for pre-send validation
    public let validationConfiguration: ValidationConfiguration?
    
    /// Whether to use circuit breaker for failure tracking
    public let useCircuitBreaker: Bool
    
    /// Circuit breaker configuration
    public let circuitBreakerThreshold: Int
    
    /// Circuit breaker reset timeout
    public let circuitBreakerResetTimeout: TimeInterval
    
    // MARK: - Initialization
    
    /// Creates a storage client configuration
    ///
    /// - Parameters:
    ///   - callingAETitle: The local Application Entity title
    ///   - serverPool: The server pool for storage destinations
    ///   - retryPolicy: Retry policy for failed operations (default: .default)
    ///   - sopClassRetryConfiguration: Per-SOP Class retry configuration (optional)
    ///   - useQueue: Whether to use store-and-forward queue (default: false)
    ///   - queueConfiguration: Queue configuration (required if useQueue is true)
    ///   - defaultPriority: Default operation priority (default: .medium)
    ///   - implementationClassUID: Implementation Class UID
    ///   - implementationVersionName: Implementation Version Name
    ///   - transcodingConfiguration: Transcoding configuration (optional)
    ///   - validationConfiguration: Validation configuration (optional)
    ///   - useCircuitBreaker: Whether to use circuit breaker (default: true)
    ///   - circuitBreakerThreshold: Failures before opening circuit (default: 5)
    ///   - circuitBreakerResetTimeout: Time before resetting circuit (default: 30 seconds)
    public init(
        callingAETitle: AETitle,
        serverPool: ServerPool,
        retryPolicy: RetryPolicy = .default,
        sopClassRetryConfiguration: SOPClassRetryConfiguration? = nil,
        useQueue: Bool = false,
        queueConfiguration: StoreAndForwardConfiguration? = nil,
        defaultPriority: DIMSEPriority = .medium,
        implementationClassUID: String = StorageConfiguration.defaultImplementationClassUID,
        implementationVersionName: String? = StorageConfiguration.defaultImplementationVersionName,
        transcodingConfiguration: TranscodingConfiguration? = nil,
        validationConfiguration: ValidationConfiguration? = nil,
        useCircuitBreaker: Bool = true,
        circuitBreakerThreshold: Int = 5,
        circuitBreakerResetTimeout: TimeInterval = 30
    ) {
        self.callingAETitle = callingAETitle
        self.serverPool = serverPool
        self.retryPolicy = retryPolicy
        self.sopClassRetryConfiguration = sopClassRetryConfiguration
        self.useQueue = useQueue
        self.queueConfiguration = queueConfiguration
        self.defaultPriority = defaultPriority
        self.implementationClassUID = implementationClassUID
        self.implementationVersionName = implementationVersionName
        self.transcodingConfiguration = transcodingConfiguration
        self.validationConfiguration = validationConfiguration
        self.useCircuitBreaker = useCircuitBreaker
        self.circuitBreakerThreshold = max(1, circuitBreakerThreshold)
        self.circuitBreakerResetTimeout = max(5, circuitBreakerResetTimeout) // Minimum 5 seconds to prevent rapid cycles
    }
    
    /// Creates a configuration with a single server
    ///
    /// - Parameters:
    ///   - callingAETitle: The local Application Entity title string
    ///   - host: The server hostname or IP address
    ///   - port: The server port number (default: 104)
    ///   - calledAETitle: The remote Application Entity title string
    ///   - retryPolicy: Retry policy for failed operations (default: .default)
    /// - Throws: `DICOMNetworkError.invalidAETitle` if AE titles are invalid
    public init(
        callingAETitle: String,
        host: String,
        port: UInt16 = dicomDefaultPort,
        calledAETitle: String,
        retryPolicy: RetryPolicy = .default
    ) throws {
        let callingAE = try AETitle(callingAETitle)
        var pool = ServerPool()
        try pool.addServer(host: host, port: port, aeTitle: calledAETitle)
        
        self.init(
            callingAETitle: callingAE,
            serverPool: pool,
            retryPolicy: retryPolicy
        )
    }
}

extension DICOMStorageClientConfiguration {
    /// Builds the exact per-server configuration consumed by storage operations.
    func storageConfiguration(
        for server: ServerEntry,
        priority: DIMSEPriority
    ) -> StorageConfiguration {
        StorageConfiguration(
            callingAETitle: callingAETitle,
            calledAETitle: server.aeTitle,
            timeout: server.timeout,
            maxPDUSize: server.maxPDUSize,
            implementationClassUID: implementationClassUID,
            implementationVersionName: implementationVersionName,
            priority: priority,
            tlsConfiguration: server.tlsConfiguration,
            userIdentity: server.userIdentity,
            transcodingConfiguration: transcodingConfiguration
        )
    }
}

extension DICOMStorageClientConfiguration: CustomStringConvertible {
    public var description: String {
        var components = ["DICOMStorageClientConfiguration("]
        components.append("callingAE=\(callingAETitle)")
        components.append(", servers=\(serverPool.count)")
        components.append(", retry=\(retryPolicy.maxAttempts) attempts")
        if useQueue {
            components.append(", queue=enabled")
        }
        if useCircuitBreaker {
            components.append(", circuitBreaker=enabled")
        }
        components.append(")")
        return components.joined()
    }
}

// MARK: - Store Operation Result

/// Result of a store operation through the storage client
///
/// Contains the store result along with metadata about which server was used
/// and how many retry attempts were made.
public struct StorageClientResult: Sendable {
    /// The underlying store result
    public let storeResult: StoreResult
    
    /// The server that was used for the successful operation
    public let server: ServerEntry
    
    /// Number of retry attempts made (0 if succeeded on first try)
    public let retryAttempts: Int
    
    /// Total time for the operation including retries
    public let totalTime: TimeInterval
    
    /// Whether the operation required server failover
    public let usedFailover: Bool
    
    /// Creates a storage client result
    public init(
        storeResult: StoreResult,
        server: ServerEntry,
        retryAttempts: Int,
        totalTime: TimeInterval,
        usedFailover: Bool = false
    ) {
        self.storeResult = storeResult
        self.server = server
        self.retryAttempts = retryAttempts
        self.totalTime = totalTime
        self.usedFailover = usedFailover
    }
}

extension StorageClientResult: CustomStringConvertible {
    public var description: String {
        let statusStr = storeResult.isWarning ? "WARNING" : (storeResult.isStored ? "SUCCESS" : "FAILED")
        let failoverStr = usedFailover ? " [FAILOVER]" : ""
        return "StorageClientResult(\(statusStr), server=\(server.aeTitle), retries=\(retryAttempts), time=\(String(format: "%.2f", totalTime))s\(failoverStr))"
    }
}

// MARK: - DICOMStorageClient

/// Unified DICOM Storage Client with server pool, automatic retry, and failover
///
/// `DICOMStorageClient` provides a high-level interface for storing DICOM files
/// with automatic server selection, retry logic, and optional queue-based delivery.
///
/// ## Features
///
/// - **Server Pool**: Manage multiple storage destinations with different priorities
/// - **Selection Strategies**: Round-robin, priority, weighted, random, or failover
/// - **Automatic Retry**: Configurable retry policies with exponential backoff
/// - **Circuit Breaker**: Prevent cascading failures with circuit breaker pattern
/// - **Store-and-Forward**: Optional queue for reliable delivery
/// - **Transcoding**: Automatic transfer syntax conversion when needed
/// - **Validation**: Pre-send validation of DICOM data
///
/// ## Usage
///
/// ```swift
/// // Create a client with server pool
/// var serverPool = ServerPool(selectionStrategy: .roundRobin)
/// try serverPool.addServer(host: "pacs1.hospital.com", port: 11112, aeTitle: "PACS1", priority: 10)
/// try serverPool.addServer(host: "pacs2.hospital.com", port: 11112, aeTitle: "PACS2", priority: 5)
///
/// let config = DICOMStorageClientConfiguration(
///     callingAETitle: try AETitle("MY_SCU"),
///     serverPool: serverPool,
///     retryPolicy: .aggressive
/// )
///
/// let client = DICOMStorageClient(configuration: config)
///
/// // Store a DICOM file
/// let result = try await client.store(fileData: dicomData)
/// print("Stored to \(result.server.aeTitle) in \(result.totalTime)s")
/// ```
///
/// Reference: PS3.4 Annex B - Storage Service Class
public actor DICOMStorageClient {
    
    // MARK: - Properties
    
    /// The client configuration
    public private(set) var configuration: DICOMStorageClientConfiguration
    
    /// Circuit breakers for each server (keyed by server ID)
    private var circuitBreakers: [UUID: CircuitBreaker]
    
    /// The retry executor for automatic retries
    private var retryExecutor: RetryExecutor?
    
    /// Store-and-forward queue (if enabled)
    private var storeQueue: StoreAndForwardQueue?
    
    /// Whether the client has been started
    private var isStarted: Bool
    
    // MARK: - Initialization
    
    /// Creates a new DICOM storage client
    ///
    /// - Parameter configuration: The client configuration
    public init(configuration: DICOMStorageClientConfiguration) {
        self.configuration = configuration
        self.circuitBreakers = [:]
        self.isStarted = false
        
        // Initialize circuit breakers for each server
        if configuration.useCircuitBreaker {
            for server in configuration.serverPool.allServers {
                let breakerConfig = CircuitBreakerConfiguration(
                    failureThreshold: configuration.circuitBreakerThreshold,
                    resetTimeout: configuration.circuitBreakerResetTimeout
                )
                let breaker = CircuitBreaker(
                    host: server.host,
                    port: server.port,
                    configuration: breakerConfig
                )
                circuitBreakers[server.id] = breaker
            }
        }
        
        // Initialize retry executor
        self.retryExecutor = RetryExecutor(
            policy: configuration.retryPolicy,
            circuitBreaker: nil // Per-server breakers managed separately
        )
    }
    
    // MARK: - Lifecycle
    
    /// Starts the storage client
    ///
    /// If queue is enabled, starts the store-and-forward queue.
    public func start() async throws {
        guard !isStarted else { return }
        
        if configuration.useQueue, let queueConfig = configuration.queueConfiguration {
            storeQueue = try await StoreAndForwardQueue(configuration: queueConfig)
            try await storeQueue?.start()
        }
        
        isStarted = true
    }
    
    /// Stops the storage client
    ///
    /// If queue is enabled, stops the store-and-forward queue.
    public func stop() async {
        isStarted = false
        
        await storeQueue?.stop()
        storeQueue = nil
    }
    
    // MARK: - Server Pool Management
    
    /// Adds a server to the pool
    ///
    /// - Parameter server: The server entry to add
    public func addServer(_ server: ServerEntry) {
        configuration.serverPool.addServer(server)
        
        // Add circuit breaker for new server
        if configuration.useCircuitBreaker {
            let breakerConfig = CircuitBreakerConfiguration(
                failureThreshold: configuration.circuitBreakerThreshold,
                resetTimeout: configuration.circuitBreakerResetTimeout
            )
            let breaker = CircuitBreaker(
                host: server.host,
                port: server.port,
                configuration: breakerConfig
            )
            circuitBreakers[server.id] = breaker
        }
    }
    
    /// Removes a server from the pool
    ///
    /// - Parameter id: The ID of the server to remove
    /// - Returns: The removed server entry, or nil if not found
    @discardableResult
    public func removeServer(id: UUID) -> ServerEntry? {
        let server = configuration.serverPool.removeServer(id: id)
        circuitBreakers.removeValue(forKey: id)
        return server
    }
    
    /// Enables or disables a server
    ///
    /// - Parameters:
    ///   - id: The ID of the server to modify
    ///   - enabled: Whether the server should be enabled
    public func setServerEnabled(id: UUID, enabled: Bool) {
        configuration.serverPool.setServerEnabled(id: id, enabled: enabled)
    }
    
    /// Gets current server pool status
    public var serverPool: ServerPool {
        configuration.serverPool
    }
    
    // MARK: - Store Operations
    
    /// Stores DICOM file data to the server pool
    ///
    /// Automatically selects a server, handles retries, and failover.
    ///
    /// - Parameters:
    ///   - data: The DICOM file data
    ///   - priority: Operation priority (uses default if not specified)
    ///   - preferredServer: Specific server ID to use (optional)
    /// - Returns: A `StorageClientResult` with operation details
    /// - Throws: `DICOMNetworkError` if all servers fail
    public func store(
        fileData data: Data,
        priority: DIMSEPriority? = nil,
        preferredServer: UUID? = nil
    ) async throws -> StorageClientResult {
        // Parse the DICOM file to get metadata
        let parser = DICOMFileParser(data: data)
        let fileInfo = try parser.parseForStorage()
        
        return try await storeDataSet(
            dataSetData: fileInfo.dataSetData,
            sopClassUID: fileInfo.sopClassUID,
            sopInstanceUID: fileInfo.sopInstanceUID,
            transferSyntaxUID: fileInfo.transferSyntaxUID,
            priority: priority,
            preferredServer: preferredServer
        )
    }
    
    /// Stores a DICOM data set to the server pool
    ///
    /// - Parameters:
    ///   - data: The DICOM data set (without file meta information)
    ///   - sopClassUID: The SOP Class UID
    ///   - sopInstanceUID: The SOP Instance UID
    ///   - transferSyntaxUID: The transfer syntax of the data
    ///   - priority: Operation priority (uses default if not specified)
    ///   - preferredServer: Specific server ID to use (optional)
    /// - Returns: A `StorageClientResult` with operation details
    /// - Throws: `DICOMNetworkError` if all servers fail
    public func storeDataSet(
        dataSetData data: Data,
        sopClassUID: String,
        sopInstanceUID: String,
        transferSyntaxUID: String = explicitVRLittleEndianTransferSyntaxUID,
        priority: DIMSEPriority? = nil,
        preferredServer: UUID? = nil
    ) async throws -> StorageClientResult {
        let startTime = Date()
        let opPriority = priority ?? configuration.defaultPriority
        
        // Get retry policy for this SOP Class
        let retryPolicy = configuration.sopClassRetryConfiguration?.policy(for: sopClassUID)
            ?? configuration.retryPolicy
        
        // Track attempted servers for failover
        var attemptedServers: Set<UUID> = []
        var lastError: Error?
        var totalRetries = 0
        var usedFailover = false
        
        while true {
            // Select a server
            guard let server = selectServer(preferredID: preferredServer, excluding: attemptedServers) else {
                if let error = lastError {
                    throw error
                }
                throw DICOMNetworkError.noServersAvailable
            }
            
            attemptedServers.insert(server.id)
            if attemptedServers.count > 1 {
                usedFailover = true
            }
            
            // Check circuit breaker for this server
            if let breaker = circuitBreakers[server.id] {
                do {
                    try await breaker.checkState()
                } catch {
                    // Circuit is open, try next server
                    continue
                }
            }
            
            // Create storage configuration for this server
            let storageConfig = configuration.storageConfiguration(
                for: server,
                priority: opPriority
            )
            
            // Attempt store with retries
            let executor = RetryExecutor(policy: retryPolicy)
            let result = await executor.executeWithResult {
                try await self.performStore(
                    server: server,
                    configuration: storageConfig,
                    dataSetData: data,
                    sopClassUID: sopClassUID,
                    sopInstanceUID: sopInstanceUID,
                    transferSyntaxUID: transferSyntaxUID
                )
            }
            
            totalRetries += result.totalAttempts - 1
            
            if let storeResult = result.value {
                // Record success with circuit breaker
                if let breaker = circuitBreakers[server.id] {
                    await breaker.recordSuccess()
                }
                
                let elapsed = Date().timeIntervalSince(startTime)
                return StorageClientResult(
                    storeResult: storeResult,
                    server: server,
                    retryAttempts: totalRetries,
                    totalTime: elapsed,
                    usedFailover: usedFailover
                )
            } else {
                // Record failure with circuit breaker
                if let breaker = circuitBreakers[server.id] {
                    await breaker.recordFailure()
                }
                
                lastError = result.finalError
                
                // Check if we should try another server
                if configuration.serverPool.enabledCount <= attemptedServers.count {
                    // No more servers to try
                    if let error = lastError {
                        throw error
                    }
                    throw DICOMNetworkError.allServersFailed(
                        attemptedCount: attemptedServers.count
                    )
                }
                
                // Continue to next server
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Selects a server from the pool
    private func selectServer(preferredID: UUID?, excluding: Set<UUID>) -> ServerEntry? {
        // If a preferred server is specified, try to use it
        if let preferredID = preferredID,
           let server = configuration.serverPool.selectServer(id: preferredID),
           !excluding.contains(server.id) {
            return server
        }
        
        // Filter enabled servers that haven't been excluded
        let availableServers = configuration.serverPool.enabledServers.filter { !excluding.contains($0.id) }
        guard !availableServers.isEmpty else { return nil }
        
        // For strategies that need the pool's internal state (round-robin, weighted), we must use selectServer()
        // For other strategies, we can work directly with the filtered list
        switch configuration.serverPool.selectionStrategy {
        case .priority, .failover:
            // Select highest priority from available servers
            return availableServers.max { $0.priority < $1.priority }
        case .random:
            // Select random from available servers
            return availableServers.randomElement()
        case .randomWeighted:
            // Select random weighted from available servers
            let totalWeight = availableServers.reduce(0) { $0 + $1.weight }
            let random = Double.random(in: 0..<totalWeight)
            var cumulative: Double = 0
            for server in availableServers {
                cumulative += server.weight
                if random < cumulative {
                    return server
                }
            }
            return availableServers.last
        case .roundRobin, .weightedRoundRobin:
            // For round-robin strategies, we need to use the pool's internal state
            // Try to find a server not in the exclusion set
            var pool = configuration.serverPool
            for _ in 0..<pool.enabledCount {
                if let server = pool.selectServer(), !excluding.contains(server.id) {
                    return server
                }
            }
            return nil
        }
    }
    
    /// Performs the actual store operation
    private func performStore(
        server: ServerEntry,
        configuration: StorageConfiguration,
        dataSetData: Data,
        sopClassUID: String,
        sopInstanceUID: String,
        transferSyntaxUID: String
    ) async throws -> StoreResult {
        return try await DICOMStorageService.store(
            dataSetData: dataSetData,
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            transferSyntaxUID: transferSyntaxUID,
            to: server.host,
            port: server.port,
            configuration: configuration
        )
    }
}

// MARK: - DICOMNetworkError Extensions

extension DICOMNetworkError {
    /// No servers are available in the pool
    static let noServersAvailable = DICOMNetworkError.invalidState("No servers available in the pool")
    
    /// All servers failed to accept the store operation
    static func allServersFailed(attemptedCount: Int) -> DICOMNetworkError {
        DICOMNetworkError.invalidState("All \(attemptedCount) server(s) failed to accept the store operation")
    }
}

#endif
