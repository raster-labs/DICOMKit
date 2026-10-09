import Foundation
// NEMA-verified: 2026a, checked 2026-09-28 — carries no DICOM-standard data (failure thresholds and timers only)

// MARK: - Circuit Breaker Configuration

/// Configuration for a Circuit Breaker
///
/// The circuit breaker pattern prevents cascading failures by tracking
/// failure rates and temporarily stopping requests to failing servers.
///
/// ## States
///
/// - **Closed**: Normal operation, requests are allowed through
/// - **Open**: Circuit is tripped, requests fail immediately
/// - **Half-Open**: Testing if the service has recovered
///
/// ## Usage
///
/// ```swift
/// let config = CircuitBreakerConfiguration(
///     failureThreshold: 5,         // Open after 5 failures
///     successThreshold: 2,          // Close after 2 successes in half-open
///     resetTimeout: 30,             // Wait 30 seconds before trying again
///     failureWindow: 60             // Count failures within 60 seconds
/// )
/// ```
public struct CircuitBreakerConfiguration: Sendable, Hashable {
    /// Number of failures required to open the circuit
    public let failureThreshold: Int
    
    /// Number of consecutive successes required to close the circuit from half-open state
    public let successThreshold: Int
    
    /// Time in seconds to wait before transitioning from open to half-open
    public let resetTimeout: TimeInterval
    
    /// Time window in seconds for counting failures (sliding window)
    public let failureWindow: TimeInterval
    
    /// Creates a circuit breaker configuration
    ///
    /// - Parameters:
    ///   - failureThreshold: Failures required to trip the circuit (default: 5)
    ///   - successThreshold: Successes required to close from half-open (default: 2)
    ///   - resetTimeout: Seconds before retrying after circuit opens (default: 30)
    ///   - failureWindow: Seconds for failure counting window (default: 60)
    public init(
        failureThreshold: Int = 5,
        successThreshold: Int = 2,
        resetTimeout: TimeInterval = 30,
        failureWindow: TimeInterval = 60
    ) {
        self.failureThreshold = max(1, failureThreshold)
        self.successThreshold = max(1, successThreshold)
        self.resetTimeout = max(1, resetTimeout)
        self.failureWindow = max(1, failureWindow)
    }
    
    /// Default circuit breaker configuration
    public static let `default` = CircuitBreakerConfiguration()
    
    /// Aggressive configuration that trips quickly
    public static let aggressive = CircuitBreakerConfiguration(
        failureThreshold: 3,
        successThreshold: 1,
        resetTimeout: 15,
        failureWindow: 30
    )
    
    /// Conservative configuration that tolerates more failures
    public static let conservative = CircuitBreakerConfiguration(
        failureThreshold: 10,
        successThreshold: 3,
        resetTimeout: 60,
        failureWindow: 120
    )
}

// MARK: - Circuit Breaker State

/// The state of a circuit breaker
public enum CircuitBreakerState: Sendable, Hashable {
    /// Circuit is closed - requests are allowed through
    case closed
    
    /// Circuit is open - requests fail immediately
    case open
    
    /// Circuit is half-open - testing if service has recovered
    case halfOpen
}

extension CircuitBreakerState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .closed: return "closed"
        case .open: return "open"
        case .halfOpen: return "half-open"
        }
    }
}

// MARK: - Circuit Breaker Statistics

/// Statistics about circuit breaker operation
public struct CircuitBreakerStatistics: Sendable {
    /// Current state of the circuit breaker
    public let state: CircuitBreakerState
    
    /// Total number of successful operations
    public let totalSuccesses: Int
    
    /// Total number of failed operations
    public let totalFailures: Int
    
    /// Number of recent failures (within the failure window)
    public let recentFailures: Int
    
    /// Number of times the circuit has been opened
    public let timesOpened: Int
    
    /// Time when the circuit was last opened (nil if never opened)
    public let lastOpenedAt: Date?
    
    /// Time when the circuit was last closed (nil if never closed after opening)
    public let lastClosedAt: Date?
    
    /// Consecutive successes in half-open state
    public let consecutiveSuccesses: Int
}

// MARK: - Circuit Breaker Error

/// Error thrown when the circuit breaker is open
public struct CircuitBreakerOpenError: Error, Sendable {
    /// The host for which the circuit is open
    public let host: String
    
    /// The port for which the circuit is open
    public let port: UInt16
    
    /// When the circuit was opened
    public let openedAt: Date
    
    /// When the circuit may transition to half-open
    public let retryAfter: Date
}

extension CircuitBreakerOpenError: CustomStringConvertible {
    public var description: String {
        let retryInSeconds = max(0, retryAfter.timeIntervalSinceNow)
        return "Circuit breaker open for \(host):\(port). Retry in \(Int(retryInSeconds)) seconds."
    }
}

// MARK: - Circuit Breaker

/// Circuit breaker for preventing cascading failures to failing DICOM servers
///
/// The circuit breaker monitors the success/failure rate of operations and
/// automatically "trips" to prevent sending requests to servers that are
/// consistently failing.
///
/// Reference: https://martinfowler.com/bliki/CircuitBreaker.html
///
/// ## Usage
///
/// ```swift
/// let breaker = CircuitBreaker(
///     host: "pacs.hospital.com",
///     port: 11112,
///     configuration: .default
/// )
///
/// // Execute operation with circuit breaker protection
/// let result = try await breaker.execute {
///     try await someDICOMOperation()
/// }
///
/// // Or manually check and record
/// try breaker.checkState()  // Throws if open
/// do {
///     let result = try await operation()
///     await breaker.recordSuccess()
///     return result
/// } catch {
///     await breaker.recordFailure()
///     throw error
/// }
/// ```
public actor CircuitBreaker {
    
    // MARK: - Properties
    
    /// The host this circuit breaker monitors
    public let host: String
    
    /// The port this circuit breaker monitors
    public let port: UInt16
    
    /// The configuration for this circuit breaker
    public let configuration: CircuitBreakerConfiguration
    
    /// Current state of the circuit breaker
    public private(set) var state: CircuitBreakerState = .closed
    
    /// Timestamps of recent failures (for sliding window)
    private var failureTimestamps: [Date] = []
    
    /// Total successful operations
    private var totalSuccesses: Int = 0
    
    /// Total failed operations
    private var totalFailures: Int = 0
    
    /// Times the circuit has been opened
    private var timesOpened: Int = 0
    
    /// When the circuit was last opened
    private var lastOpenedAt: Date?
    
    /// When the circuit was last closed (after being open)
    private var lastClosedAt: Date?
    
    /// Consecutive successes in half-open state
    private var consecutiveSuccesses: Int = 0
    
    // MARK: - Initialization
    
    /// Creates a new circuit breaker
    ///
    /// - Parameters:
    ///   - host: The host address to monitor
    ///   - port: The port number to monitor
    ///   - configuration: Circuit breaker configuration
    public init(
        host: String,
        port: UInt16,
        configuration: CircuitBreakerConfiguration = .default
    ) {
        self.host = host
        self.port = port
        self.configuration = configuration
    }
    
    // MARK: - Public Methods
    
    /// Executes an operation with circuit breaker protection
    ///
    /// If the circuit is open, throws `CircuitBreakerOpenError` immediately.
    /// If the circuit is closed or half-open, executes the operation and
    /// records the result.
    ///
    /// - Parameter operation: The operation to execute
    /// - Returns: The result of the operation
    /// - Throws: `CircuitBreakerOpenError` if circuit is open, or the operation's error
    public func execute<T>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try checkState()
        
        do {
            let result = try await operation()
            recordSuccess()
            return result
        } catch {
            recordFailure()
            throw error
        }
    }
    
    /// Checks if operations are allowed and transitions state if needed
    ///
    /// - Throws: `CircuitBreakerOpenError` if the circuit is open
    public func checkState() throws {
        switch state {
        case .closed:
            // Clean up old failures outside the window
            pruneOldFailures()
            
        case .open:
            // Check if we should transition to half-open
            if shouldTransitionToHalfOpen() {
                transitionToHalfOpen()
            } else {
                throw CircuitBreakerOpenError(
                    host: host,
                    port: port,
                    openedAt: lastOpenedAt ?? Date(),
                    retryAfter: (lastOpenedAt ?? Date()).addingTimeInterval(configuration.resetTimeout)
                )
            }
            
        case .halfOpen:
            // Allow limited operations through
            break
        }
    }
    
    /// Records a successful operation
    public func recordSuccess() {
        totalSuccesses += 1
        
        switch state {
        case .closed:
            // Normal operation continues
            break
            
        case .open:
            // Shouldn't happen, but treat as half-open success
            consecutiveSuccesses = 1
            
        case .halfOpen:
            consecutiveSuccesses += 1
            
            // Check if we should close the circuit
            if consecutiveSuccesses >= configuration.successThreshold {
                transitionToClosed()
            }
        }
    }
    
    /// Records a failed operation
    public func recordFailure() {
        totalFailures += 1
        failureTimestamps.append(Date())
        
        // Prune old failures
        pruneOldFailures()
        
        switch state {
        case .closed:
            // Check if we should open the circuit
            if failureTimestamps.count >= configuration.failureThreshold {
                transitionToOpen()
            }
            
        case .open:
            // Already open, nothing to do
            break
            
        case .halfOpen:
            // Any failure in half-open state trips the circuit again
            transitionToOpen()
        }
    }
    
    /// Gets current statistics
    ///
    /// - Returns: Current circuit breaker statistics
    public func statistics() -> CircuitBreakerStatistics {
        pruneOldFailures()
        
        return CircuitBreakerStatistics(
            state: state,
            totalSuccesses: totalSuccesses,
            totalFailures: totalFailures,
            recentFailures: failureTimestamps.count,
            timesOpened: timesOpened,
            lastOpenedAt: lastOpenedAt,
            lastClosedAt: lastClosedAt,
            consecutiveSuccesses: consecutiveSuccesses
        )
    }
    
    /// Resets the circuit breaker to its initial state
    public func reset() {
        state = .closed
        failureTimestamps.removeAll()
        consecutiveSuccesses = 0
        // Note: We don't reset statistics counters, only operational state
    }
    
    /// Forces the circuit to open (for testing or manual control)
    public func forceOpen() {
        transitionToOpen()
    }
    
    /// Forces the circuit to close (for testing or manual control)
    public func forceClose() {
        transitionToClosed()
    }
    
    // MARK: - Private Methods
    
    /// Prunes failures outside the sliding window
    private func pruneOldFailures() {
        let cutoff = Date().addingTimeInterval(-configuration.failureWindow)
        failureTimestamps.removeAll { $0 < cutoff }
    }
    
    /// Checks if the circuit should transition from open to half-open
    private func shouldTransitionToHalfOpen() -> Bool {
        guard let openedAt = lastOpenedAt else { return true }
        return Date().timeIntervalSince(openedAt) >= configuration.resetTimeout
    }
    
    /// Transitions to the open state
    private func transitionToOpen() {
        state = .open
        lastOpenedAt = Date()
        timesOpened += 1
        consecutiveSuccesses = 0
    }
    
    /// Transitions to the half-open state
    private func transitionToHalfOpen() {
        state = .halfOpen
        consecutiveSuccesses = 0
    }
    
    /// Transitions to the closed state
    private func transitionToClosed() {
        state = .closed
        lastClosedAt = Date()
        consecutiveSuccesses = 0
        failureTimestamps.removeAll()
    }
}

// MARK: - Circuit Breaker Registry

/// Registry for managing circuit breakers per host/port combination
///
/// Provides centralized management of circuit breakers for multiple DICOM
/// servers. Each unique host:port combination gets its own circuit breaker.
///
/// ## Usage
///
/// ```swift
/// let registry = CircuitBreakerRegistry(configuration: .default)
///
/// // Get or create a circuit breaker for a server
/// let breaker = await registry.breaker(for: "pacs.hospital.com", port: 11112)
///
/// // Execute with circuit breaker protection
/// let result = try await breaker.execute {
///     try await someDICOMOperation()
/// }
/// ```
public actor CircuitBreakerRegistry {
    
    /// Default configuration for new circuit breakers
    public let defaultConfiguration: CircuitBreakerConfiguration
    
    /// Registered circuit breakers
    private var breakers: [String: CircuitBreaker] = [:]
    
    /// Creates a new circuit breaker registry
    ///
    /// - Parameter configuration: Default configuration for new circuit breakers
    public init(configuration: CircuitBreakerConfiguration = .default) {
        self.defaultConfiguration = configuration
    }
    
    /// Gets or creates a circuit breaker for a specific host and port
    ///
    /// - Parameters:
    ///   - host: The host address
    ///   - port: The port number
    /// - Returns: The circuit breaker for this host:port
    public func breaker(for host: String, port: UInt16) -> CircuitBreaker {
        let key = "\(host):\(port)"
        
        if let existing = breakers[key] {
            return existing
        }
        
        let breaker = CircuitBreaker(
            host: host,
            port: port,
            configuration: defaultConfiguration
        )
        breakers[key] = breaker
        return breaker
    }
    
    /// Removes a circuit breaker from the registry
    ///
    /// - Parameters:
    ///   - host: The host address
    ///   - port: The port number
    public func remove(host: String, port: UInt16) {
        let key = "\(host):\(port)"
        breakers.removeValue(forKey: key)
    }
    
    /// Removes all circuit breakers from the registry
    public func removeAll() {
        breakers.removeAll()
    }
    
    /// Gets statistics for all circuit breakers
    ///
    /// - Returns: Dictionary of statistics keyed by "host:port"
    public func allStatistics() async -> [String: CircuitBreakerStatistics] {
        var stats: [String: CircuitBreakerStatistics] = [:]
        for (key, breaker) in breakers {
            stats[key] = await breaker.statistics()
        }
        return stats
    }
    
    /// Resets all circuit breakers
    public func resetAll() async {
        for breaker in breakers.values {
            await breaker.reset()
        }
    }
}
