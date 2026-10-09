import Foundation

// NEMA-verified: 2026a, checked 2026-09-28 — carries no DICOM-standard data (request counters and timings)
/// Performance metrics for DICOMweb operations
///
/// Tracks request latency, throughput, and error rates for
/// monitoring and performance optimization.
public actor DICOMwebMetrics {
    
    // MARK: - Types
    
    /// Operation types for metrics
    public enum OperationType: String, Sendable, CaseIterable {
        case wadoRetrieve = "wado_retrieve"
        case qidoQuery = "qido_query"
        case stowStore = "stow_store"
        case upsOperation = "ups_operation"
        case other = "other"
    }
    
    /// A single metric sample
    public struct Sample: Sendable {
        public let operation: OperationType
        public let duration: TimeInterval
        public let bytesSent: Int
        public let bytesReceived: Int
        public let success: Bool
        public let statusCode: Int?
        public let timestamp: Date
        
        public init(
            operation: OperationType,
            duration: TimeInterval,
            bytesSent: Int = 0,
            bytesReceived: Int = 0,
            success: Bool,
            statusCode: Int? = nil,
            timestamp: Date = Date()
        ) {
            self.operation = operation
            self.duration = duration
            self.bytesSent = bytesSent
            self.bytesReceived = bytesReceived
            self.success = success
            self.statusCode = statusCode
            self.timestamp = timestamp
        }
    }
    
    /// Aggregated metrics for an operation type
    public struct AggregatedMetrics: Sendable {
        public let operation: OperationType
        public let requestCount: Int
        public let successCount: Int
        public let errorCount: Int
        public let totalBytesSent: Int64
        public let totalBytesReceived: Int64
        public let minDuration: TimeInterval
        public let maxDuration: TimeInterval
        public let avgDuration: TimeInterval
        public let p50Duration: TimeInterval
        public let p95Duration: TimeInterval
        public let p99Duration: TimeInterval
        
        /// Success rate (0.0 to 1.0)
        public var successRate: Double {
            guard requestCount > 0 else { return 0 }
            return Double(successCount) / Double(requestCount)
        }
        
        /// Error rate (0.0 to 1.0)
        public var errorRate: Double {
            guard requestCount > 0 else { return 0 }
            return Double(errorCount) / Double(requestCount)
        }
        
        /// Average throughput in bytes per second
        public var avgThroughput: Double {
            guard avgDuration > 0 else { return 0 }
            return Double(totalBytesReceived) / (avgDuration * Double(requestCount))
        }
    }
    
    // MARK: - Properties
    
    private var samples: [Sample] = []
    private let maxSamples: Int
    private let windowDuration: TimeInterval
    
    // MARK: - Initialization
    
    /// Creates a metrics collector
    /// - Parameters:
    ///   - maxSamples: Maximum number of samples to retain (default: 10000)
    ///   - windowDuration: Time window for metrics (default: 1 hour)
    public init(maxSamples: Int = 10000, windowDuration: TimeInterval = 3600) {
        self.maxSamples = maxSamples
        self.windowDuration = windowDuration
    }
    
    // MARK: - Recording
    
    /// Records a metric sample
    /// - Parameter sample: The sample to record
    public func record(_ sample: Sample) {
        samples.append(sample)
        
        // Trim old samples
        trimSamples()
    }
    
    /// Records a successful operation
    /// - Parameters:
    ///   - operation: The operation type
    ///   - duration: Time taken
    ///   - bytesSent: Bytes sent in request
    ///   - bytesReceived: Bytes received in response
    ///   - statusCode: HTTP status code
    public func recordSuccess(
        operation: OperationType,
        duration: TimeInterval,
        bytesSent: Int = 0,
        bytesReceived: Int = 0,
        statusCode: Int? = nil
    ) {
        record(Sample(
            operation: operation,
            duration: duration,
            bytesSent: bytesSent,
            bytesReceived: bytesReceived,
            success: true,
            statusCode: statusCode
        ))
    }
    
    /// Records a failed operation
    /// - Parameters:
    ///   - operation: The operation type
    ///   - duration: Time taken before failure
    ///   - statusCode: HTTP status code (if any)
    public func recordFailure(
        operation: OperationType,
        duration: TimeInterval,
        statusCode: Int? = nil
    ) {
        record(Sample(
            operation: operation,
            duration: duration,
            success: false,
            statusCode: statusCode
        ))
    }
    
    // MARK: - Querying
    
    /// Gets aggregated metrics for all operations
    /// - Returns: Array of aggregated metrics per operation type
    public func getAggregatedMetrics() -> [AggregatedMetrics] {
        trimSamples()
        
        var results: [AggregatedMetrics] = []
        
        for operation in OperationType.allCases {
            let operationSamples = samples.filter { $0.operation == operation }
            if !operationSamples.isEmpty {
                results.append(aggregate(operationSamples, operation: operation))
            }
        }
        
        return results
    }
    
    /// Gets aggregated metrics for a specific operation
    /// - Parameter operation: The operation type
    /// - Returns: Aggregated metrics for the operation
    public func getMetrics(for operation: OperationType) -> AggregatedMetrics? {
        trimSamples()
        
        let operationSamples = samples.filter { $0.operation == operation }
        guard !operationSamples.isEmpty else { return nil }
        
        return aggregate(operationSamples, operation: operation)
    }
    
    /// Gets overall metrics summary
    /// - Returns: Summary of all metrics
    public func getSummary() -> MetricsSummary {
        trimSamples()
        
        let totalRequests = samples.count
        let successfulRequests = samples.filter { $0.success }.count
        let failedRequests = totalRequests - successfulRequests
        let totalBytesSent = samples.reduce(0) { $0 + $1.bytesSent }
        let totalBytesReceived = samples.reduce(0) { $0 + $1.bytesReceived }
        
        let durations = samples.map { $0.duration }
        let avgLatency = durations.isEmpty ? 0 : durations.reduce(0, +) / Double(durations.count)
        
        // Calculate requests per minute
        let oldestSample = samples.min(by: { $0.timestamp < $1.timestamp })
        let windowSeconds = oldestSample.map { Date().timeIntervalSince($0.timestamp) } ?? 0
        let requestsPerMinute = windowSeconds > 0 ? (Double(totalRequests) / windowSeconds) * 60 : 0
        
        return MetricsSummary(
            totalRequests: totalRequests,
            successfulRequests: successfulRequests,
            failedRequests: failedRequests,
            totalBytesSent: Int64(totalBytesSent),
            totalBytesReceived: Int64(totalBytesReceived),
            avgLatencyMs: avgLatency * 1000,
            requestsPerMinute: requestsPerMinute,
            windowDuration: windowDuration
        )
    }
    
    /// Clears all recorded metrics
    public func clear() {
        samples.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func trimSamples() {
        let cutoff = Date().addingTimeInterval(-windowDuration)
        samples.removeAll { $0.timestamp < cutoff }
        
        // Also trim by count
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
    }
    
    private func aggregate(_ samples: [Sample], operation: OperationType) -> AggregatedMetrics {
        let durations = samples.map { $0.duration }.sorted()
        let successCount = samples.filter { $0.success }.count
        let totalBytesSent = Int64(samples.reduce(0) { $0 + $1.bytesSent })
        let totalBytesReceived = Int64(samples.reduce(0) { $0 + $1.bytesReceived })
        
        return AggregatedMetrics(
            operation: operation,
            requestCount: samples.count,
            successCount: successCount,
            errorCount: samples.count - successCount,
            totalBytesSent: totalBytesSent,
            totalBytesReceived: totalBytesReceived,
            minDuration: durations.first ?? 0,
            maxDuration: durations.last ?? 0,
            avgDuration: durations.isEmpty ? 0 : durations.reduce(0, +) / Double(durations.count),
            p50Duration: percentile(durations, p: 50),
            p95Duration: percentile(durations, p: 95),
            p99Duration: percentile(durations, p: 99)
        )
    }
    
    private func percentile(_ sorted: [TimeInterval], p: Int) -> TimeInterval {
        guard !sorted.isEmpty else { return 0 }
        let index = Int(Double(sorted.count - 1) * Double(p) / 100)
        return sorted[index]
    }
}

// MARK: - Metrics Summary

/// Summary of all DICOMweb metrics
public struct MetricsSummary: Sendable {
    public let totalRequests: Int
    public let successfulRequests: Int
    public let failedRequests: Int
    public let totalBytesSent: Int64
    public let totalBytesReceived: Int64
    public let avgLatencyMs: Double
    public let requestsPerMinute: Double
    public let windowDuration: TimeInterval
    
    public var successRate: Double {
        guard totalRequests > 0 else { return 0 }
        return Double(successfulRequests) / Double(totalRequests)
    }
    
    public var errorRate: Double {
        guard totalRequests > 0 else { return 0 }
        return Double(failedRequests) / Double(totalRequests)
    }
}

// MARK: - Metric Timer

/// Helper for timing operations
public struct MetricTimer: Sendable {
    private let startTime: Date
    private let operation: DICOMwebMetrics.OperationType
    
    /// Creates a timer for an operation
    /// - Parameter operation: The operation type being timed
    public init(operation: DICOMwebMetrics.OperationType) {
        self.startTime = Date()
        self.operation = operation
    }
    
    /// Gets the elapsed time since the timer was created
    public var elapsed: TimeInterval {
        Date().timeIntervalSince(startTime)
    }
    
    /// Finishes timing and returns a sample
    /// - Parameters:
    ///   - success: Whether the operation succeeded
    ///   - bytesSent: Bytes sent
    ///   - bytesReceived: Bytes received
    ///   - statusCode: HTTP status code
    /// - Returns: A metric sample
    public func finish(
        success: Bool,
        bytesSent: Int = 0,
        bytesReceived: Int = 0,
        statusCode: Int? = nil
    ) -> DICOMwebMetrics.Sample {
        DICOMwebMetrics.Sample(
            operation: operation,
            duration: elapsed,
            bytesSent: bytesSent,
            bytesReceived: bytesReceived,
            success: success,
            statusCode: statusCode
        )
    }
}
