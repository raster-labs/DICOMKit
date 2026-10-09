import Foundation
// NEMA-verified: 2026a, checked 2026-09-28 — the 4 storage SOP Class UIDs registered in PS3.6 2026a Table A-1 (Scripts/diff_network.py); retry policy itself is not standard data

// MARK: - Retry Policy Configuration

/// Configuration for retry behavior on DICOM operations
///
/// Defines how operations should be retried when they fail, including
/// the number of attempts, delay strategies, and which errors to retry.
///
/// ## Retry Strategies
///
/// - **Fixed delay**: Wait a constant amount of time between retries
/// - **Exponential backoff**: Double the delay after each attempt
/// - **Exponential with jitter**: Add randomness to prevent thundering herd
///
/// ## Usage
///
/// ```swift
/// // Default retry policy with exponential backoff and jitter
/// let policy = RetryPolicy.default
///
/// // Custom policy for critical operations
/// let criticalPolicy = RetryPolicy(
///     maxAttempts: 5,
///     initialDelay: 1.0,
///     maxDelay: 60.0,
///     strategy: .exponentialWithJitter(factor: 2.0, jitterRange: 0.25),
///     retryableCategories: [.transient, .timeout]
/// )
/// ```
///
/// Reference: PS3.4 Annex B - Storage Service Class
public struct RetryPolicy: Sendable, Hashable {
    
    // MARK: - Properties
    
    /// Maximum number of retry attempts (not counting the initial attempt)
    ///
    /// A value of 0 means no retries (fail immediately on first error).
    /// A value of 3 means up to 3 retries (4 total attempts).
    public let maxAttempts: Int
    
    /// Initial delay in seconds before the first retry
    public let initialDelay: TimeInterval
    
    /// Maximum delay in seconds between retries
    ///
    /// This caps the delay when using exponential backoff strategies.
    public let maxDelay: TimeInterval
    
    /// Maximum total time in seconds allowed for all retry attempts
    ///
    /// If nil, there is no total time limit (only per-attempt limits apply).
    public let maxTotalTime: TimeInterval?
    
    /// The delay strategy to use between retries
    public let strategy: RetryStrategy
    
    /// Error categories that should trigger a retry
    ///
    /// Only errors with a category in this set will be retried.
    /// Other errors will be thrown immediately without retry.
    public let retryableCategories: Set<ErrorCategory>
    
    /// Whether to use circuit breaker integration
    ///
    /// When true, checks if the circuit breaker is open before retrying.
    public let useCircuitBreaker: Bool
    
    // MARK: - Initialization
    
    /// Creates a retry policy with the specified parameters
    ///
    /// - Parameters:
    ///   - maxAttempts: Maximum retry attempts (default: 3)
    ///   - initialDelay: Initial delay in seconds (default: 1.0)
    ///   - maxDelay: Maximum delay in seconds (default: 30.0)
    ///   - maxTotalTime: Maximum total time for all attempts (default: nil)
    ///   - strategy: Delay strategy (default: exponential with jitter)
    ///   - retryableCategories: Categories to retry (default: transient, timeout, resource)
    ///   - useCircuitBreaker: Use circuit breaker (default: true)
    public init(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 30.0,
        maxTotalTime: TimeInterval? = nil,
        strategy: RetryStrategy = .exponentialWithJitter(factor: 2.0, jitterRange: 0.25),
        retryableCategories: Set<ErrorCategory> = [.transient, .timeout, .resource],
        useCircuitBreaker: Bool = true
    ) {
        self.maxAttempts = max(0, maxAttempts)
        self.initialDelay = max(0.1, initialDelay)
        self.maxDelay = max(self.initialDelay, maxDelay)
        self.maxTotalTime = maxTotalTime
        self.strategy = strategy
        self.retryableCategories = retryableCategories
        self.useCircuitBreaker = useCircuitBreaker
    }
    
    // MARK: - Presets
    
    /// Default retry policy suitable for most DICOM operations
    ///
    /// - maxAttempts: 3
    /// - initialDelay: 1.0 seconds
    /// - maxDelay: 30.0 seconds
    /// - strategy: exponential with jitter
    public static let `default` = RetryPolicy()
    
    /// No retries - fail immediately on first error
    ///
    /// Note: The initialDelay is set to 0.1 (the minimum) even though retries won't occur.
    /// This ensures consistent behavior if the policy is ever used as a base for other configurations.
    public static let noRetry = RetryPolicy(
        maxAttempts: 0,
        initialDelay: 0.1,  // Minimum allowed, but won't be used since maxAttempts is 0
        maxDelay: 0.1,
        strategy: .fixed
    )
    
    /// Aggressive retry policy for critical operations
    ///
    /// - maxAttempts: 5
    /// - initialDelay: 0.5 seconds
    /// - maxDelay: 60.0 seconds
    /// - maxTotalTime: 180.0 seconds (3 minutes)
    public static let aggressive = RetryPolicy(
        maxAttempts: 5,
        initialDelay: 0.5,
        maxDelay: 60.0,
        maxTotalTime: 180.0,
        strategy: .exponentialWithJitter(factor: 2.0, jitterRange: 0.3)
    )
    
    /// Conservative retry policy for non-critical operations
    ///
    /// - maxAttempts: 2
    /// - initialDelay: 2.0 seconds
    /// - maxDelay: 10.0 seconds
    /// - maxTotalTime: 30.0 seconds
    public static let conservative = RetryPolicy(
        maxAttempts: 2,
        initialDelay: 2.0,
        maxDelay: 10.0,
        maxTotalTime: 30.0,
        strategy: .exponentialWithJitter(factor: 1.5, jitterRange: 0.1)
    )
    
    /// Fast retry policy for local networks or testing
    ///
    /// - maxAttempts: 2
    /// - initialDelay: 0.1 seconds
    /// - maxDelay: 1.0 seconds
    public static let fast = RetryPolicy(
        maxAttempts: 2,
        initialDelay: 0.1,
        maxDelay: 1.0,
        strategy: .fixed
    )
    
    // MARK: - Methods
    
    /// Calculates the delay for a given attempt number
    ///
    /// - Parameter attempt: The attempt number (0 = first retry, 1 = second retry, etc.)
    /// - Returns: The delay in seconds before the next attempt
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        let baseDelay = strategy.calculateDelay(
            attempt: attempt,
            initialDelay: initialDelay
        )
        return min(baseDelay, maxDelay)
    }
    
    /// Checks if an error should be retried based on its category
    ///
    /// - Parameter error: The error to check
    /// - Returns: true if the error should be retried
    public func shouldRetry(_ error: Error) -> Bool {
        if let networkError = error as? DICOMNetworkError {
            return retryableCategories.contains(networkError.category)
        }
        // For non-DICOM errors, default to retry only for transient-like behaviors
        return false
    }
}

extension RetryPolicy: CustomStringConvertible {
    public var description: String {
        var components = ["RetryPolicy("]
        components.append("maxAttempts: \(maxAttempts)")
        components.append(", initialDelay: \(initialDelay)s")
        components.append(", maxDelay: \(maxDelay)s")
        if let maxTotal = maxTotalTime {
            components.append(", maxTotalTime: \(maxTotal)s")
        }
        components.append(", strategy: \(strategy)")
        components.append(")")
        return components.joined()
    }
}

// MARK: - Retry Strategy

/// Strategy for calculating delay between retry attempts
///
/// Different strategies offer various tradeoffs:
/// - **Fixed**: Simple, predictable, but can cause thundering herd
/// - **Exponential**: Better backoff, but deterministic
/// - **Exponential with jitter**: Best for distributed systems
public enum RetryStrategy: Sendable, Hashable {
    /// Fixed delay between retries
    ///
    /// Every retry waits the same initial delay.
    case fixed
    
    /// Exponential backoff without jitter
    ///
    /// Delay = initialDelay * (factor ^ attempt)
    ///
    /// - Parameter factor: Multiplier for each attempt (typically 2.0)
    case exponential(factor: Double)
    
    /// Exponential backoff with random jitter
    ///
    /// Adds randomness to prevent thundering herd when multiple
    /// clients retry simultaneously.
    ///
    /// Delay = baseDelay * (1 + random(-jitterRange, jitterRange))
    ///
    /// - Parameters:
    ///   - factor: Multiplier for each attempt (typically 2.0)
    ///   - jitterRange: Range of jitter as fraction of delay (0.0 to 1.0)
    case exponentialWithJitter(factor: Double, jitterRange: Double)
    
    /// Linear backoff
    ///
    /// Delay = initialDelay * (1 + attempt * increment)
    ///
    /// - Parameter increment: Amount to add per attempt (fraction of initial)
    case linear(increment: Double)
    
    /// Calculates the delay for a given attempt number
    ///
    /// - Parameters:
    ///   - attempt: The attempt number (0 = first retry)
    ///   - initialDelay: The base delay in seconds
    /// - Returns: The calculated delay in seconds
    func calculateDelay(attempt: Int, initialDelay: TimeInterval) -> TimeInterval {
        let attemptDouble = Double(attempt)
        
        switch self {
        case .fixed:
            return initialDelay
            
        case .exponential(let factor):
            return initialDelay * pow(factor, attemptDouble)
            
        case .exponentialWithJitter(let factor, let jitterRange):
            let baseDelay = initialDelay * pow(factor, attemptDouble)
            let jitter = Double.random(in: -jitterRange...jitterRange)
            return baseDelay * (1.0 + jitter)
            
        case .linear(let increment):
            return initialDelay * (1.0 + attemptDouble * increment)
        }
    }
}

extension RetryStrategy: CustomStringConvertible {
    public var description: String {
        switch self {
        case .fixed:
            return "fixed"
        case .exponential(let factor):
            return "exponential(factor: \(factor))"
        case .exponentialWithJitter(let factor, let jitterRange):
            return "exponentialWithJitter(factor: \(factor), jitter: \(jitterRange))"
        case .linear(let increment):
            return "linear(increment: \(increment))"
        }
    }
}

// MARK: - Retry Context

/// Context information about the current retry state
///
/// Provides information about retry progress that can be used
/// for logging, monitoring, or making decisions about whether
/// to continue retrying.
///
/// ## Attempt Numbering
///
/// `attemptNumber` starts at 1 for the initial attempt and increments for each retry.
/// `maxAttempts` is the number of **retry** attempts allowed (not including the initial attempt).
/// Total possible attempts = 1 (initial) + maxAttempts (retries)
///
/// For example, with maxAttempts=3:
/// - attemptNumber=1 is the initial attempt
/// - attemptNumber=2 is the 1st retry
/// - attemptNumber=3 is the 2nd retry
/// - attemptNumber=4 is the 3rd retry (final)
public struct RetryContext: Sendable {
    /// The number of attempts that have been made (including the initial attempt)
    ///
    /// Starts at 1 for the initial attempt.
    public let attemptNumber: Int
    
    /// The maximum number of retry attempts allowed (not counting the initial attempt)
    ///
    /// Total possible attempts = 1 + maxAttempts
    public let maxAttempts: Int
    
    /// Whether there are more retry attempts available
    public var hasMoreAttempts: Bool {
        attemptNumber <= maxAttempts
    }
    
    /// The fraction of attempts used (0.0 to 1.0)
    public var fractionUsed: Double {
        guard maxAttempts > 0 else { return 1.0 }
        return Double(attemptNumber - 1) / Double(maxAttempts)
    }
    
    /// The error from the previous attempt (nil for first attempt)
    public let lastError: Error?
    
    /// The time elapsed since the first attempt
    public let elapsedTime: TimeInterval
    
    /// The delay that will be used before the next attempt
    public let nextDelay: TimeInterval?
    
    /// Creates a retry context
    public init(
        attemptNumber: Int,
        maxAttempts: Int,
        lastError: Error? = nil,
        elapsedTime: TimeInterval = 0,
        nextDelay: TimeInterval? = nil
    ) {
        self.attemptNumber = attemptNumber
        self.maxAttempts = maxAttempts
        self.lastError = lastError
        self.elapsedTime = elapsedTime
        self.nextDelay = nextDelay
    }
}

extension RetryContext: CustomStringConvertible {
    public var description: String {
        var components = ["RetryContext("]
        components.append("attempt \(attemptNumber)/\(maxAttempts + 1)")
        components.append(", elapsed: \(String(format: "%.1f", elapsedTime))s")
        if let delay = nextDelay {
            components.append(", nextDelay: \(String(format: "%.2f", delay))s")
        }
        if let error = lastError {
            components.append(", lastError: \(error)")
        }
        components.append(")")
        return components.joined()
    }
}

// MARK: - Retry Result

/// Result of a retried operation
///
/// Contains information about the operation result and the retry
/// attempts that were made.
public struct RetryResult<T: Sendable>: Sendable {
    /// The successful result value (nil if all attempts failed)
    public let value: T?
    
    /// Total number of attempts made (including the initial attempt)
    public let totalAttempts: Int
    
    /// Whether the operation ultimately succeeded
    public var success: Bool {
        value != nil
    }
    
    /// Total time spent on all attempts (including delays)
    public let totalTime: TimeInterval
    
    /// The errors encountered during retries (empty if first attempt succeeded)
    public let errors: [Error]
    
    /// The final error if the operation failed (nil if succeeded)
    public var finalError: Error? {
        errors.last
    }
    
    /// Creates a successful retry result
    public static func success(
        _ value: T,
        attempts: Int,
        time: TimeInterval,
        errors: [Error] = []
    ) -> RetryResult<T> {
        RetryResult(
            value: value,
            totalAttempts: attempts,
            totalTime: time,
            errors: errors
        )
    }
    
    /// Creates a failed retry result
    public static func failure(
        attempts: Int,
        time: TimeInterval,
        errors: [Error]
    ) -> RetryResult<T> {
        RetryResult(
            value: nil,
            totalAttempts: attempts,
            totalTime: time,
            errors: errors
        )
    }
    
    /// Creates a retry result
    private init(
        value: T?,
        totalAttempts: Int,
        totalTime: TimeInterval,
        errors: [Error]
    ) {
        self.value = value
        self.totalAttempts = totalAttempts
        self.totalTime = totalTime
        self.errors = errors
    }
}

extension RetryResult: CustomStringConvertible {
    public var description: String {
        if success {
            return "RetryResult(success after \(totalAttempts) attempt(s), \(String(format: "%.2f", totalTime))s)"
        } else {
            return "RetryResult(failed after \(totalAttempts) attempt(s), \(String(format: "%.2f", totalTime))s, errors: \(errors.count))"
        }
    }
}

// MARK: - Retry Executor

/// Executes operations with automatic retry logic
///
/// `RetryExecutor` wraps operations and automatically retries them
/// according to the configured retry policy when they fail with
/// retryable errors.
///
/// ## Usage
///
/// ```swift
/// let executor = RetryExecutor(policy: .default)
///
/// // Execute with retry
/// let result = try await executor.execute {
///     try await client.store(fileData: data, to: "pacs.hospital.com", port: 11112)
/// }
///
/// // Execute with progress callback
/// let result = try await executor.execute(
///     onRetry: { context in
///         print("Retry attempt \(context.attemptNumber), waiting \(context.nextDelay ?? 0)s")
///     }
/// ) {
///     try await client.verify(host: "pacs.hospital.com", port: 11112)
/// }
/// ```
public actor RetryExecutor {
    
    // MARK: - Properties
    
    /// The retry policy to use
    public let policy: RetryPolicy
    
    /// Optional circuit breaker for tracking failures
    public let circuitBreaker: CircuitBreaker?
    
    // MARK: - Initialization
    
    /// Creates a retry executor with the specified policy
    ///
    /// - Parameters:
    ///   - policy: The retry policy to use
    ///   - circuitBreaker: Optional circuit breaker for failure tracking
    public init(
        policy: RetryPolicy = .default,
        circuitBreaker: CircuitBreaker? = nil
    ) {
        self.policy = policy
        self.circuitBreaker = circuitBreaker
    }
    
    // MARK: - Execution
    
    /// Executes an operation with automatic retries
    ///
    /// - Parameters:
    ///   - onRetry: Optional callback invoked before each retry
    ///   - operation: The operation to execute
    /// - Returns: The result of the successful operation
    /// - Throws: The last error if all retry attempts fail
    public func execute<T: Sendable>(
        onRetry: (@Sendable (RetryContext) async -> Void)? = nil,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        let result = await executeWithResult(onRetry: onRetry, operation: operation)
        
        if let value = result.value {
            return value
        } else if let error = result.finalError {
            throw error
        } else {
            throw RetryError.exhausted(attempts: result.totalAttempts, errors: result.errors)
        }
    }
    
    /// Executes an operation with automatic retries and returns detailed result
    ///
    /// Unlike `execute`, this method never throws and returns a `RetryResult`
    /// containing both success/failure information and retry statistics.
    ///
    /// - Parameters:
    ///   - onRetry: Optional callback invoked before each retry
    ///   - operation: The operation to execute
    /// - Returns: A `RetryResult` containing the outcome and retry statistics
    public func executeWithResult<T: Sendable>(
        onRetry: (@Sendable (RetryContext) async -> Void)? = nil,
        operation: @Sendable () async throws -> T
    ) async -> RetryResult<T> {
        let startTime = Date()
        var errors: [Error] = []
        var attemptNumber = 1
        
        while true {
            // Check circuit breaker if enabled
            if policy.useCircuitBreaker, let breaker = circuitBreaker {
                do {
                    try await breaker.checkState()
                } catch let error as CircuitBreakerOpenError {
                    // Circuit is open, wrap in DICOMNetworkError
                    let networkError = DICOMNetworkError.circuitBreakerOpen(
                        host: error.host,
                        port: error.port,
                        retryAfter: error.retryAfter
                    )
                    errors.append(networkError)
                    
                    // Circuit breaker open is retryable if we have time
                    let elapsedTime = Date().timeIntervalSince(startTime)
                    if let maxTotal = policy.maxTotalTime, elapsedTime >= maxTotal {
                        return .failure(
                            attempts: attemptNumber,
                            time: elapsedTime,
                            errors: errors
                        )
                    }
                    
                    // Wait for circuit breaker reset
                    let waitTime = max(0.1, error.retryAfter.timeIntervalSinceNow)
                    try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
                    continue
                } catch {
                    // Unexpected error from circuit breaker
                    errors.append(error)
                }
            }
            
            // Execute the operation
            do {
                let result = try await operation()
                
                // Record success with circuit breaker
                if let breaker = circuitBreaker {
                    await breaker.recordSuccess()
                }
                
                let totalTime = Date().timeIntervalSince(startTime)
                return .success(result, attempts: attemptNumber, time: totalTime, errors: errors)
                
            } catch {
                errors.append(error)
                
                // Record failure with circuit breaker
                if let breaker = circuitBreaker {
                    await breaker.recordFailure()
                }
                
                let elapsedTime = Date().timeIntervalSince(startTime)
                
                // Check if we should retry
                let shouldRetry = policy.shouldRetry(error)
                let hasMoreAttempts = attemptNumber <= policy.maxAttempts
                let withinTimeLimit: Bool
                if let maxTotal = policy.maxTotalTime {
                    withinTimeLimit = elapsedTime < maxTotal
                } else {
                    withinTimeLimit = true
                }
                
                if !shouldRetry || !hasMoreAttempts || !withinTimeLimit {
                    return .failure(
                        attempts: attemptNumber,
                        time: elapsedTime,
                        errors: errors
                    )
                }
                
                // Calculate delay
                let delay = policy.delay(forAttempt: attemptNumber - 1)
                
                // Check if delay would exceed time limit
                if let maxTotal = policy.maxTotalTime, elapsedTime + delay >= maxTotal {
                    return .failure(
                        attempts: attemptNumber,
                        time: elapsedTime,
                        errors: errors
                    )
                }
                
                // Invoke retry callback
                let context = RetryContext(
                    attemptNumber: attemptNumber + 1,
                    maxAttempts: policy.maxAttempts,
                    lastError: error,
                    elapsedTime: elapsedTime,
                    nextDelay: delay
                )
                await onRetry?(context)
                
                // Wait before retry
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                
                attemptNumber += 1
            }
        }
    }
}

// MARK: - Retry Error

/// Errors specific to retry operations
public enum RetryError: Error, Sendable {
    /// All retry attempts were exhausted
    ///
    /// - Parameters:
    ///   - attempts: Total number of attempts made
    ///   - errors: The errors encountered during each attempt
    case exhausted(attempts: Int, errors: [Error])
    
    /// Operation was cancelled during retry
    case cancelled
    
    /// Maximum total time was exceeded
    ///
    /// - Parameters:
    ///   - elapsed: Time elapsed when the limit was reached
    ///   - limit: The configured time limit
    case timeLimitExceeded(elapsed: TimeInterval, limit: TimeInterval)
}

extension RetryError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .exhausted(let attempts, let errors):
            return "Retry exhausted after \(attempts) attempt(s). Last error: \(errors.last?.localizedDescription ?? "unknown")"
        case .cancelled:
            return "Retry operation was cancelled"
        case .timeLimitExceeded(let elapsed, let limit):
            return "Retry time limit exceeded (elapsed: \(String(format: "%.1f", elapsed))s, limit: \(String(format: "%.1f", limit))s)"
        }
    }
}

// MARK: - SOP Class Retry Configuration

/// Retry configuration for specific SOP Classes
///
/// Allows different retry policies for different types of DICOM
/// operations. For example, you might want more aggressive retries
/// for CT images than for secondary capture images.
///
/// ## Usage
///
/// ```swift
/// var config = SOPClassRetryConfiguration()
///
/// // Critical SOP Classes get aggressive retries
/// config.setPolicy(.aggressive, for: "1.2.840.10008.5.1.4.1.1.2")   // CT Image Storage
/// config.setPolicy(.aggressive, for: "1.2.840.10008.5.1.4.1.1.4")   // MR Image Storage
///
/// // Less critical SOP Classes get conservative retries
/// config.setPolicy(.conservative, for: "1.2.840.10008.5.1.4.1.1.7") // Secondary Capture Image Storage
///
/// // Get policy for a specific SOP Class
/// let policy = config.policy(for: sopClassUID)
/// ```
public struct SOPClassRetryConfiguration: Sendable {
    
    // MARK: - Properties
    
    /// The default policy used when no specific policy is configured
    public var defaultPolicy: RetryPolicy
    
    /// Per-SOP Class retry policies
    private var sopClassPolicies: [String: RetryPolicy]
    
    // MARK: - Initialization
    
    /// Creates a SOP Class retry configuration
    ///
    /// - Parameter defaultPolicy: The default policy for SOP Classes without specific configuration
    public init(defaultPolicy: RetryPolicy = .default) {
        self.defaultPolicy = defaultPolicy
        self.sopClassPolicies = [:]
    }
    
    // MARK: - Configuration
    
    /// Sets the retry policy for a specific SOP Class
    ///
    /// - Parameters:
    ///   - policy: The retry policy to use
    ///   - sopClassUID: The SOP Class UID
    public mutating func setPolicy(_ policy: RetryPolicy, for sopClassUID: String) {
        sopClassPolicies[sopClassUID] = policy
    }
    
    /// Removes the specific policy for a SOP Class (will use default)
    ///
    /// - Parameter sopClassUID: The SOP Class UID
    public mutating func removePolicy(for sopClassUID: String) {
        sopClassPolicies.removeValue(forKey: sopClassUID)
    }
    
    /// Gets the retry policy for a specific SOP Class
    ///
    /// - Parameter sopClassUID: The SOP Class UID
    /// - Returns: The configured policy, or the default policy
    public func policy(for sopClassUID: String) -> RetryPolicy {
        sopClassPolicies[sopClassUID] ?? defaultPolicy
    }
    
    /// Whether a specific policy is configured for a SOP Class
    ///
    /// - Parameter sopClassUID: The SOP Class UID
    /// - Returns: true if a specific policy is configured
    public func hasSpecificPolicy(for sopClassUID: String) -> Bool {
        sopClassPolicies[sopClassUID] != nil
    }
    
    /// All SOP Class UIDs with specific policies
    public var configuredSOPClasses: [String] {
        Array(sopClassPolicies.keys)
    }
    
    // MARK: - Presets
    
    /// Configuration with aggressive retries for all modality images
    ///
    /// Configured SOP Classes:
    /// - CT Image Storage: aggressive
    /// - MR Image Storage: aggressive
    /// - Enhanced CT Image Storage: aggressive
    /// - Enhanced MR Image Storage: aggressive
    /// - CR Image Storage: default
    /// - DX Image Storage: default
    /// - US Image Storage: default
    public static var modalityImages: SOPClassRetryConfiguration {
        var config = SOPClassRetryConfiguration()
        
        // CT gets aggressive retry
        config.setPolicy(.aggressive, for: "1.2.840.10008.5.1.4.1.1.2")      // CT Image Storage
        config.setPolicy(.aggressive, for: "1.2.840.10008.5.1.4.1.1.2.1")    // Enhanced CT Image Storage
        
        // MR gets aggressive retry
        config.setPolicy(.aggressive, for: "1.2.840.10008.5.1.4.1.1.4")      // MR Image Storage
        config.setPolicy(.aggressive, for: "1.2.840.10008.5.1.4.1.1.4.1")    // Enhanced MR Image Storage
        
        return config
    }
}

extension SOPClassRetryConfiguration: CustomStringConvertible {
    public var description: String {
        if sopClassPolicies.isEmpty {
            return "SOPClassRetryConfiguration(default: \(defaultPolicy))"
        }
        return "SOPClassRetryConfiguration(default: \(defaultPolicy), \(sopClassPolicies.count) specific policies)"
    }
}
