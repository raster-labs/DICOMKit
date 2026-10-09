import Foundation
// NEMA-verified: 2026a, checked 2026-09-28 — carries no DICOM-standard data (token-bucket tuning constants only)

// MARK: - Bandwidth Configuration

/// Configuration for bandwidth limiting
///
/// Controls the maximum data transfer rate for DICOM network operations.
/// Uses a token bucket algorithm to allow bursts while enforcing average limits.
///
/// ## Usage
///
/// ```swift
/// // Limit to 10 MB/s with 5 MB burst capacity
/// let config = BandwidthConfiguration(
///     bytesPerSecond: 10_000_000,
///     burstCapacity: 5_000_000
/// )
///
/// // Unlimited bandwidth
/// let unlimited = BandwidthConfiguration.unlimited
/// ```
///
/// Reference: Token bucket algorithm for network traffic shaping
public struct BandwidthConfiguration: Sendable, Hashable {
    
    /// Maximum sustained bytes per second
    ///
    /// A value of 0 or less means unlimited bandwidth.
    public let bytesPerSecond: Int
    
    /// Maximum burst capacity in bytes
    ///
    /// This allows temporary bursts above the sustained rate.
    /// Should be at least equal to bytesPerSecond for smooth operation.
    public let burstCapacity: Int
    
    /// Whether bandwidth limiting is enabled
    public var isEnabled: Bool {
        bytesPerSecond > 0
    }
    
    // MARK: - Initialization
    
    /// Creates a bandwidth configuration
    ///
    /// - Parameters:
    ///   - bytesPerSecond: Maximum sustained bytes per second (0 or negative = unlimited)
    ///   - burstCapacity: Maximum burst capacity in bytes (defaults to bytesPerSecond)
    public init(bytesPerSecond: Int, burstCapacity: Int? = nil) {
        self.bytesPerSecond = max(0, bytesPerSecond)
        let defaultBurst = self.bytesPerSecond > 0 ? self.bytesPerSecond : 0
        self.burstCapacity = burstCapacity.map { max(0, $0) } ?? defaultBurst
    }
    
    // MARK: - Presets
    
    /// Unlimited bandwidth (no limiting)
    public static let unlimited = BandwidthConfiguration(bytesPerSecond: 0)
    
    /// Low bandwidth limit (1 MB/s) - suitable for constrained networks
    public static let low = BandwidthConfiguration(bytesPerSecond: 1_000_000)
    
    /// Medium bandwidth limit (10 MB/s) - suitable for shared networks
    public static let medium = BandwidthConfiguration(bytesPerSecond: 10_000_000)
    
    /// High bandwidth limit (100 MB/s) - suitable for local networks
    public static let high = BandwidthConfiguration(bytesPerSecond: 100_000_000)
    
    /// Creates a configuration for a specific MB/s rate
    ///
    /// - Parameter megabytesPerSecond: Rate in megabytes per second
    /// - Returns: Configuration with the specified rate
    public static func megabytesPerSecond(_ megabytesPerSecond: Int) -> BandwidthConfiguration {
        BandwidthConfiguration(bytesPerSecond: megabytesPerSecond * 1_000_000)
    }
    
    /// Creates a configuration for a specific KB/s rate
    ///
    /// - Parameter kilobytesPerSecond: Rate in kilobytes per second
    /// - Returns: Configuration with the specified rate
    public static func kilobytesPerSecond(_ kilobytesPerSecond: Int) -> BandwidthConfiguration {
        BandwidthConfiguration(bytesPerSecond: kilobytesPerSecond * 1_000)
    }
}

extension BandwidthConfiguration: CustomStringConvertible {
    public var description: String {
        if !isEnabled {
            return "BandwidthConfiguration(unlimited)"
        }
        let mbps = Double(bytesPerSecond) / 1_000_000.0
        return "BandwidthConfiguration(\(String(format: "%.1f", mbps)) MB/s, burst: \(burstCapacity) bytes)"
    }
}

// MARK: - Bandwidth Statistics

/// Statistics about bandwidth usage
public struct BandwidthStatistics: Sendable {
    /// Total bytes transferred
    public let totalBytesTransferred: Int
    
    /// Bytes transferred in the current time window
    public let bytesInCurrentWindow: Int
    
    /// Current effective rate in bytes per second
    public let currentRateBytesPerSecond: Int
    
    /// Available tokens in the bucket
    public let availableTokens: Int
    
    /// Number of times throttling was applied
    public let throttleCount: Int
    
    /// Total time spent waiting due to throttling (in seconds)
    public let totalThrottleTime: TimeInterval
}

// MARK: - Bandwidth Limiter

/// Rate limiter for controlling DICOM data transfer bandwidth
///
/// Uses a token bucket algorithm to enforce bandwidth limits while allowing
/// short bursts above the sustained rate. The limiter is thread-safe and
/// designed for use with async/await.
///
/// ## Token Bucket Algorithm
///
/// The limiter maintains a "bucket" of tokens, where each token represents
/// one byte of transfer capacity:
/// - Tokens are added at the configured rate (bytesPerSecond)
/// - Tokens accumulate up to the burst capacity
/// - Each byte transferred consumes one token
/// - If insufficient tokens are available, the operation waits
///
/// ## Usage
///
/// ```swift
/// let limiter = BandwidthLimiter(configuration: .megabytesPerSecond(10))
///
/// // Wait for permission to transfer data
/// await limiter.acquire(bytes: data.count)
///
/// // Check if bytes can be transferred immediately
/// let canProceed = await limiter.tryAcquire(bytes: data.count)
///
/// // Get current statistics
/// let stats = await limiter.statistics()
/// ```
public actor BandwidthLimiter {
    
    // MARK: - Properties
    
    /// The bandwidth configuration
    public let configuration: BandwidthConfiguration
    
    /// Current available tokens (bytes)
    private var availableTokens: Double
    
    /// Last time tokens were replenished
    private var lastReplenishTime: Date
    
    /// Total bytes transferred through this limiter
    private var totalBytesTransferred: Int = 0
    
    /// Number of times throttling was applied
    private var throttleCount: Int = 0
    
    /// Total time spent waiting due to throttling
    private var totalThrottleTime: TimeInterval = 0
    
    // MARK: - Initialization
    
    /// Creates a new bandwidth limiter
    ///
    /// - Parameter configuration: The bandwidth configuration to enforce
    public init(configuration: BandwidthConfiguration) {
        self.configuration = configuration
        self.availableTokens = Double(configuration.burstCapacity)
        self.lastReplenishTime = Date()
    }
    
    /// Creates an unlimited bandwidth limiter
    public static var unlimited: BandwidthLimiter {
        BandwidthLimiter(configuration: .unlimited)
    }
    
    // MARK: - Public Methods
    
    /// Acquires permission to transfer the specified number of bytes
    ///
    /// This method blocks (asynchronously) until sufficient bandwidth
    /// is available. If the limiter is configured as unlimited, returns
    /// immediately.
    ///
    /// - Parameter bytes: Number of bytes to acquire
    /// - Returns: The time waited in seconds (0 if no wait was needed)
    @discardableResult
    public func acquire(bytes: Int) async -> TimeInterval {
        guard configuration.isEnabled && bytes > 0 else {
            totalBytesTransferred += bytes
            return 0
        }
        
        var totalWaitTime: TimeInterval = 0
        var bytesRemaining = bytes
        
        while bytesRemaining > 0 {
            replenishTokens()
            
            let tokensToConsume = min(Double(bytesRemaining), availableTokens)
            
            if tokensToConsume > 0 {
                availableTokens -= tokensToConsume
                bytesRemaining -= Int(tokensToConsume)
                totalBytesTransferred += Int(tokensToConsume)
            }
            
            if bytesRemaining > 0 {
                // Calculate wait time for remaining bytes
                let waitTime = calculateWaitTime(forBytes: bytesRemaining)
                
                if waitTime > 0 {
                    throttleCount += 1
                    totalThrottleTime += waitTime
                    totalWaitTime += waitTime
                    
                    try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
                }
            }
        }
        
        return totalWaitTime
    }
    
    /// Tries to acquire permission to transfer bytes without waiting
    ///
    /// - Parameter bytes: Number of bytes to transfer
    /// - Returns: true if the bytes can be transferred immediately
    public func tryAcquire(bytes: Int) -> Bool {
        guard configuration.isEnabled && bytes > 0 else {
            totalBytesTransferred += bytes
            return true
        }
        
        replenishTokens()
        
        if availableTokens >= Double(bytes) {
            availableTokens -= Double(bytes)
            totalBytesTransferred += bytes
            return true
        }
        
        return false
    }
    
    /// Gets the current available bandwidth in bytes
    ///
    /// - Returns: Number of bytes that can be transferred immediately
    public func available() -> Int {
        replenishTokens()
        return Int(availableTokens)
    }
    
    /// Gets the estimated wait time for transferring the specified bytes
    ///
    /// - Parameter bytes: Number of bytes to transfer
    /// - Returns: Estimated wait time in seconds (0 if no wait needed)
    public func estimatedWaitTime(forBytes bytes: Int) -> TimeInterval {
        guard configuration.isEnabled && bytes > 0 else { return 0 }
        
        replenishTokens()
        
        let deficit = Double(bytes) - availableTokens
        if deficit <= 0 { return 0 }
        
        return deficit / Double(configuration.bytesPerSecond)
    }
    
    /// Gets bandwidth usage statistics
    ///
    /// - Returns: Current bandwidth statistics
    public func statistics() -> BandwidthStatistics {
        replenishTokens()
        
        let elapsed = Date().timeIntervalSince(lastReplenishTime)
        let windowBytes = elapsed > 0 ? Int(Double(totalBytesTransferred) * elapsed) : 0
        let currentRate = elapsed > 0 ? Int(Double(totalBytesTransferred) / max(1, elapsed)) : 0
        
        return BandwidthStatistics(
            totalBytesTransferred: totalBytesTransferred,
            bytesInCurrentWindow: windowBytes,
            currentRateBytesPerSecond: currentRate,
            availableTokens: Int(availableTokens),
            throttleCount: throttleCount,
            totalThrottleTime: totalThrottleTime
        )
    }
    
    /// Resets the limiter state
    ///
    /// Refills the token bucket and clears statistics.
    public func reset() {
        availableTokens = Double(configuration.burstCapacity)
        lastReplenishTime = Date()
        totalBytesTransferred = 0
        throttleCount = 0
        totalThrottleTime = 0
    }
    
    // MARK: - Private Methods
    
    /// Replenishes tokens based on elapsed time
    private func replenishTokens() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastReplenishTime)
        
        if elapsed > 0 {
            let newTokens = elapsed * Double(configuration.bytesPerSecond)
            availableTokens = min(availableTokens + newTokens, Double(configuration.burstCapacity))
            lastReplenishTime = now
        }
    }
    
    /// Calculates wait time needed for the specified bytes
    private func calculateWaitTime(forBytes bytes: Int) -> TimeInterval {
        let deficit = Double(bytes) - availableTokens
        if deficit <= 0 { return 0 }
        
        // Calculate time needed to replenish enough tokens
        return deficit / Double(configuration.bytesPerSecond)
    }
}

// MARK: - Bandwidth Scheduler

/// Scheduling configuration for bandwidth management
///
/// Allows different bandwidth limits during different time periods,
/// such as reduced limits during peak hours.
///
/// ## Usage
///
/// ```swift
/// // Create schedule with off-peak hours at full speed
/// var schedule = BandwidthSchedule()
///
/// // Off-peak hours (11 PM - 6 AM): unlimited
/// schedule.addPeriod(
///     BandwidthSchedulePeriod(
///         startHour: 23, startMinute: 0,
///         endHour: 6, endMinute: 0,
///         configuration: .unlimited
///     )
/// )
///
/// // Peak hours (9 AM - 5 PM): limited
/// schedule.addPeriod(
///     BandwidthSchedulePeriod(
///         startHour: 9, startMinute: 0,
///         endHour: 17, endMinute: 0,
///         configuration: .megabytesPerSecond(5)
///     )
/// )
/// ```
public struct BandwidthSchedulePeriod: Sendable, Hashable {
    /// Start hour (0-23)
    public let startHour: Int
    
    /// Start minute (0-59)
    public let startMinute: Int
    
    /// End hour (0-23)
    public let endHour: Int
    
    /// End minute (0-59)
    public let endMinute: Int
    
    /// Days of the week this period applies to (1 = Sunday, 7 = Saturday)
    /// Empty array means all days
    public let daysOfWeek: Set<Int>
    
    /// Bandwidth configuration for this period
    public let configuration: BandwidthConfiguration
    
    /// Creates a schedule period
    ///
    /// - Parameters:
    ///   - startHour: Start hour (0-23)
    ///   - startMinute: Start minute (0-59)
    ///   - endHour: End hour (0-23)
    ///   - endMinute: End minute (0-59)
    ///   - daysOfWeek: Days of week (1=Sunday to 7=Saturday), empty = all days
    ///   - configuration: Bandwidth configuration for this period
    public init(
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int,
        daysOfWeek: Set<Int> = [],
        configuration: BandwidthConfiguration
    ) {
        self.startHour = max(0, min(23, startHour))
        self.startMinute = max(0, min(59, startMinute))
        self.endHour = max(0, min(23, endHour))
        self.endMinute = max(0, min(59, endMinute))
        self.daysOfWeek = daysOfWeek
        self.configuration = configuration
    }
    
    /// Checks if the given date/time falls within this period
    ///
    /// - Parameters:
    ///   - date: The date to check
    ///   - calendar: Calendar to use for calculations
    /// - Returns: true if the date is within this period
    public func contains(date: Date, calendar: Calendar = .current) -> Bool {
        let components = calendar.dateComponents([.hour, .minute, .weekday], from: date)
        guard let hour = components.hour,
              let minute = components.minute,
              let weekday = components.weekday else {
            return false
        }
        
        // Check day of week if specified
        if !daysOfWeek.isEmpty && !daysOfWeek.contains(weekday) {
            return false
        }
        
        let currentMinutes = hour * 60 + minute
        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute
        
        // Handle periods that cross midnight
        if startMinutes <= endMinutes {
            return currentMinutes >= startMinutes && currentMinutes < endMinutes
        } else {
            return currentMinutes >= startMinutes || currentMinutes < endMinutes
        }
    }
}

extension BandwidthSchedulePeriod: CustomStringConvertible {
    public var description: String {
        let start = String(format: "%02d:%02d", startHour, startMinute)
        let end = String(format: "%02d:%02d", endHour, endMinute)
        let days = daysOfWeek.isEmpty ? "all days" : "days \(daysOfWeek.sorted())"
        return "BandwidthSchedulePeriod(\(start)-\(end) \(days), \(configuration))"
    }
}

/// Bandwidth schedule with multiple time periods
///
/// Manages a collection of schedule periods and determines the active
/// configuration based on the current time.
public struct BandwidthSchedule: Sendable {
    
    /// Scheduled periods (evaluated in order)
    public private(set) var periods: [BandwidthSchedulePeriod]
    
    /// Default configuration when no period matches
    public let defaultConfiguration: BandwidthConfiguration
    
    /// Creates a bandwidth schedule
    ///
    /// - Parameter defaultConfiguration: Configuration to use when no period matches
    public init(defaultConfiguration: BandwidthConfiguration = .unlimited) {
        self.periods = []
        self.defaultConfiguration = defaultConfiguration
    }
    
    /// Adds a schedule period
    ///
    /// - Parameter period: The period to add
    public mutating func addPeriod(_ period: BandwidthSchedulePeriod) {
        periods.append(period)
    }
    
    /// Removes all periods
    public mutating func clearPeriods() {
        periods.removeAll()
    }
    
    /// Gets the active configuration for the specified time
    ///
    /// - Parameters:
    ///   - date: The date/time to check
    ///   - calendar: Calendar to use
    /// - Returns: The active configuration
    public func activeConfiguration(at date: Date = Date(), calendar: Calendar = .current) -> BandwidthConfiguration {
        for period in periods {
            if period.contains(date: date, calendar: calendar) {
                return period.configuration
            }
        }
        return defaultConfiguration
    }
    
    /// Checks if any scheduled period is active
    ///
    /// - Parameters:
    ///   - date: The date/time to check
    ///   - calendar: Calendar to use
    /// - Returns: true if a scheduled period is active
    public func isScheduledPeriodActive(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        periods.contains { $0.contains(date: date, calendar: calendar) }
    }
    
    // MARK: - Presets
    
    /// Business hours schedule (9 AM - 5 PM weekdays): limited, off-hours: unlimited
    ///
    /// - Parameter peakConfiguration: Configuration for business hours
    /// - Returns: Configured schedule
    public static func businessHours(peakConfiguration: BandwidthConfiguration = .megabytesPerSecond(5)) -> BandwidthSchedule {
        var schedule = BandwidthSchedule(defaultConfiguration: .unlimited)
        
        // Monday through Friday, 9 AM - 5 PM
        schedule.addPeriod(BandwidthSchedulePeriod(
            startHour: 9,
            startMinute: 0,
            endHour: 17,
            endMinute: 0,
            daysOfWeek: [2, 3, 4, 5, 6], // Monday through Friday
            configuration: peakConfiguration
        ))
        
        return schedule
    }
    
    /// Off-peak schedule (unlimited during night hours)
    ///
    /// - Parameters:
    ///   - peakConfiguration: Configuration for peak hours
    ///   - offPeakStart: Start hour for off-peak (default 22:00)
    ///   - offPeakEnd: End hour for off-peak (default 06:00)
    /// - Returns: Configured schedule
    public static func offPeak(
        peakConfiguration: BandwidthConfiguration = .megabytesPerSecond(10),
        offPeakStart: Int = 22,
        offPeakEnd: Int = 6
    ) -> BandwidthSchedule {
        var schedule = BandwidthSchedule(defaultConfiguration: peakConfiguration)
        
        // Off-peak hours: unlimited
        schedule.addPeriod(BandwidthSchedulePeriod(
            startHour: offPeakStart,
            startMinute: 0,
            endHour: offPeakEnd,
            endMinute: 0,
            configuration: .unlimited
        ))
        
        return schedule
    }
}

extension BandwidthSchedule: CustomStringConvertible {
    public var description: String {
        if periods.isEmpty {
            return "BandwidthSchedule(default: \(defaultConfiguration))"
        }
        return "BandwidthSchedule(\(periods.count) periods, default: \(defaultConfiguration))"
    }
}

// MARK: - Scheduled Bandwidth Limiter

/// Bandwidth limiter with time-based schedule support
///
/// Automatically adjusts bandwidth limits based on a configured schedule.
/// Useful for reducing network impact during business hours.
///
/// ## Usage
///
/// ```swift
/// let schedule = BandwidthSchedule.businessHours(
///     peakConfiguration: .megabytesPerSecond(5)
/// )
/// let limiter = ScheduledBandwidthLimiter(schedule: schedule)
///
/// // Automatically uses appropriate limits based on current time
/// await limiter.acquire(bytes: data.count)
/// ```
public actor ScheduledBandwidthLimiter {
    
    // MARK: - Properties
    
    /// The bandwidth schedule
    public let schedule: BandwidthSchedule
    
    /// The calendar to use for schedule calculations
    public let calendar: Calendar
    
    /// Active bandwidth limiter
    private var currentLimiter: BandwidthLimiter
    
    /// Configuration of the current limiter
    private var currentConfiguration: BandwidthConfiguration
    
    /// Total bytes transferred
    private var totalBytesTransferred: Int = 0
    
    // MARK: - Initialization
    
    /// Creates a scheduled bandwidth limiter
    ///
    /// - Parameters:
    ///   - schedule: The bandwidth schedule
    ///   - calendar: Calendar for schedule calculations
    public init(schedule: BandwidthSchedule, calendar: Calendar = .current) {
        self.schedule = schedule
        self.calendar = calendar
        let initialConfig = schedule.activeConfiguration(at: Date(), calendar: calendar)
        self.currentConfiguration = initialConfig
        self.currentLimiter = BandwidthLimiter(configuration: initialConfig)
    }
    
    // MARK: - Public Methods
    
    /// Acquires permission to transfer the specified number of bytes
    ///
    /// Automatically updates the limiter if the schedule has changed.
    ///
    /// - Parameter bytes: Number of bytes to transfer
    /// - Returns: Time waited in seconds
    @discardableResult
    public func acquire(bytes: Int) async -> TimeInterval {
        updateLimiterIfNeeded()
        let waitTime = await currentLimiter.acquire(bytes: bytes)
        totalBytesTransferred += bytes
        return waitTime
    }
    
    /// Tries to acquire permission without waiting
    ///
    /// - Parameter bytes: Number of bytes to transfer
    /// - Returns: true if transfer can proceed immediately
    public func tryAcquire(bytes: Int) async -> Bool {
        updateLimiterIfNeeded()
        let result = await currentLimiter.tryAcquire(bytes: bytes)
        if result {
            totalBytesTransferred += bytes
        }
        return result
    }
    
    /// Gets the current active configuration
    ///
    /// - Returns: The currently active bandwidth configuration
    public func activeConfiguration() -> BandwidthConfiguration {
        updateLimiterIfNeeded()
        return currentConfiguration
    }
    
    /// Gets bandwidth usage statistics
    ///
    /// - Returns: Current statistics
    public func statistics() async -> BandwidthStatistics {
        return await currentLimiter.statistics()
    }
    
    // MARK: - Private Methods
    
    /// Updates the limiter if the schedule configuration has changed
    private func updateLimiterIfNeeded() {
        let activeConfig = schedule.activeConfiguration(at: Date(), calendar: calendar)
        
        if activeConfig != currentConfiguration {
            // Transfer statistics to new limiter if needed
            currentConfiguration = activeConfig
            currentLimiter = BandwidthLimiter(configuration: activeConfig)
        }
    }
}
