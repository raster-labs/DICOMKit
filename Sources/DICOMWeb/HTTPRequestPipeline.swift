import Foundation

// NEMA-verified: 2026a, checked 2026-09-28 — carries no DICOM-standard data (request pipelining)
/// Configuration for HTTP request pipelining
///
/// Controls request queueing, pipelining depth, and ordering behavior.
public struct HTTPPipelineConfiguration: Sendable, Hashable {
    /// Maximum number of requests to pipeline together
    public let maxPipelineDepth: Int
    
    /// Whether to enable request pipelining
    public let enablePipelining: Bool
    
    /// Whether to maintain strict request/response ordering
    public let strictOrdering: Bool
    
    /// Maximum time to wait before flushing pending requests (in seconds)
    public let flushTimeout: TimeInterval
    
    /// Creates a pipeline configuration
    /// - Parameters:
    ///   - maxPipelineDepth: Maximum pipelined requests (default: 10)
    ///   - enablePipelining: Enable pipelining (default: true)
    ///   - strictOrdering: Maintain strict ordering (default: true)
    ///   - flushTimeout: Flush timeout in seconds (default: 0.1)
    public init(
        maxPipelineDepth: Int = 10,
        enablePipelining: Bool = true,
        strictOrdering: Bool = true,
        flushTimeout: TimeInterval = 0.1
    ) {
        self.maxPipelineDepth = max(1, maxPipelineDepth)
        self.enablePipelining = enablePipelining
        self.strictOrdering = strictOrdering
        self.flushTimeout = max(0.001, flushTimeout)
    }
    
    /// Default configuration for standard pipelining
    public static let `default` = HTTPPipelineConfiguration()
    
    /// Disabled configuration (no pipelining)
    public static let disabled = HTTPPipelineConfiguration(enablePipelining: false)
    
    /// Aggressive configuration for maximum throughput
    public static let aggressive = HTTPPipelineConfiguration(
        maxPipelineDepth: 50,
        flushTimeout: 0.05
    )
}

/// Statistics for HTTP request pipelining
public struct HTTPPipelineStatistics: Sendable {
    /// Total requests pipelined
    public let requestsPipelined: Int
    
    /// Total requests sent individually (not pipelined)
    public let requestsIndividual: Int
    
    /// Number of pipeline flushes
    public let pipelineFlushes: Int
    
    /// Average pipeline depth when flushed
    public let averagePipelineDepth: Double
    
    /// Number of pipeline errors
    public let pipelineErrors: Int
    
    /// Number of out-of-order responses detected
    public let outOfOrderResponses: Int
    
    /// Creates pipeline statistics
    public init(
        requestsPipelined: Int,
        requestsIndividual: Int,
        pipelineFlushes: Int,
        averagePipelineDepth: Double,
        pipelineErrors: Int,
        outOfOrderResponses: Int
    ) {
        self.requestsPipelined = requestsPipelined
        self.requestsIndividual = requestsIndividual
        self.pipelineFlushes = pipelineFlushes
        self.averagePipelineDepth = averagePipelineDepth
        self.pipelineErrors = pipelineErrors
        self.outOfOrderResponses = outOfOrderResponses
    }
}

/// Actor managing HTTP request pipelining
///
/// Implements request queueing and pipelining for improved network efficiency.
/// Requests are grouped and sent together when possible, with responses
/// returned in the original order.
actor HTTPRequestPipeline {
    
    // MARK: - Types
    
    /// Represents a pipelined request awaiting response
    private struct PipelinedRequest {
        /// Unique identifier for this request
        let id: UUID
        
        /// The original request
        let request: HTTPClient.Request
        
        /// When the request was queued
        let queuedAt: Date
        
        /// When the request was sent (nil if not yet sent)
        var sentAt: Date?
        
        /// Continuation for returning the response
        let continuation: CheckedContinuation<HTTPClient.Response, Error>
        
        /// Creates a pipelined request
        init(
            request: HTTPClient.Request,
            continuation: CheckedContinuation<HTTPClient.Response, Error>
        ) {
            self.id = UUID()
            self.request = request
            self.queuedAt = Date()
            self.sentAt = nil
            self.continuation = continuation
        }
    }
    
    // MARK: - Properties
    
    /// Configuration for this pipeline
    private let configuration: HTTPPipelineConfiguration
    
    /// Pending requests waiting to be sent
    private var pendingRequests: [String: [PipelinedRequest]] = [:]
    
    /// Requests that have been sent but not yet responded
    private var inflightRequests: [UUID: PipelinedRequest] = [:]
    
    /// Statistics tracking
    private var stats = Stats()
    
    /// Flush timer task
    private var flushTask: Task<Void, Never>?
    
    /// Whether the pipeline is running
    private var isRunning = false
    
    // MARK: - Statistics Struct
    
    private struct Stats {
        var requestsPipelined: Int = 0
        var requestsIndividual: Int = 0
        var pipelineFlushes: Int = 0
        var totalPipelineDepth: Int = 0
        var pipelineErrors: Int = 0
        var outOfOrderResponses: Int = 0
    }
    
    // MARK: - Initialization
    
    /// Creates an HTTP request pipeline
    /// - Parameter configuration: Pipeline configuration
    public init(configuration: HTTPPipelineConfiguration = .default) {
        self.configuration = configuration
    }
    
    // MARK: - Lifecycle
    
    /// Starts the request pipeline
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        
        if configuration.enablePipelining {
            // Start flush timer task
            flushTask = Task { [weak self] in
                await self?.runFlushLoop()
            }
        }
    }
    
    /// Stops the request pipeline and cancels pending requests
    public func stop() async {
        isRunning = false
        flushTask?.cancel()
        flushTask = nil
        
        // Cancel all pending requests
        for (host, requests) in pendingRequests {
            for request in requests {
                request.continuation.resume(
                    throwing: DICOMwebError.connectionFailed(
                        underlying: NSError(
                            domain: "HTTPPipeline",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Pipeline stopped"]
                        )
                    )
                )
            }
            pendingRequests[host] = []
        }
        
        // Clear inflight requests
        inflightRequests.removeAll()
    }
    
    // MARK: - Request Queueing
    
    /// Queues a request for pipelining
    /// - Parameters:
    ///   - request: The request to queue
    ///   - executor: Closure to execute the request
    /// - Returns: The response
    public func enqueue(
        _ request: HTTPClient.Request,
        executor: @escaping @Sendable (HTTPClient.Request) async throws -> HTTPClient.Response
    ) async throws -> HTTPClient.Response {
        guard configuration.enablePipelining else {
            // Pipelining disabled - execute immediately
            stats.requestsIndividual += 1
            return try await executor(request)
        }
        
        let host = request.url.host ?? "unknown"
        
        // Check if we should flush immediately
        if shouldFlushImmediately(for: host) {
            await flushPipeline(for: host, executor: executor)
        }
        
        // Queue the request and wait for response
        return try await withCheckedThrowingContinuation { continuation in
            let pipelinedRequest = PipelinedRequest(
                request: request,
                continuation: continuation
            )
            
            Task {
                self.addToPipeline(pipelinedRequest, for: host)
            }
        }
    }
    
    /// Adds a request to the pipeline
    private func addToPipeline(_ request: PipelinedRequest, for host: String) {
        var hostQueue = pendingRequests[host] ?? []
        hostQueue.append(request)
        pendingRequests[host] = hostQueue
    }
    
    // MARK: - Pipeline Flushing
    
    /// Checks if the pipeline should be flushed immediately
    private func shouldFlushImmediately(for host: String) -> Bool {
        guard let hostQueue = pendingRequests[host] else {
            return false
        }
        
        return hostQueue.count >= configuration.maxPipelineDepth
    }
    
    /// Flushes the pipeline for a specific host
    private func flushPipeline(
        for host: String,
        executor: @escaping @Sendable (HTTPClient.Request) async throws -> HTTPClient.Response
    ) async {
        guard var hostQueue = pendingRequests[host], !hostQueue.isEmpty else {
            return
        }
        
        pendingRequests[host] = []
        stats.pipelineFlushes += 1
        stats.totalPipelineDepth += hostQueue.count
        stats.requestsPipelined += hostQueue.count
        
        // Mark requests as sent
        let now = Date()
        for i in 0..<hostQueue.count {
            hostQueue[i].sentAt = now
            inflightRequests[hostQueue[i].id] = hostQueue[i]
        }
        
        // Execute requests concurrently with a bounded window (plan M4): an
        // unbounded group holds every response body in memory at once and can
        // dispatch hundreds of connections in a burst. The window matches the
        // per-host connection limit.
        await withTaskGroup(of: (UUID, Result<HTTPClient.Response, Error>).self) { group in
            let width = 6 // matches HTTPConnectionPool's default maxConnectionsPerHost
            var next = 0
            func schedule(_ request: PipelinedRequest) {
                group.addTask {
                    let result: Result<HTTPClient.Response, Error>
                    do {
                        let response = try await executor(request.request)
                        result = .success(response)
                    } catch {
                        result = .failure(error)
                    }
                    return (request.id, result)
                }
            }
            while next < min(width, hostQueue.count) {
                schedule(hostQueue[next]); next += 1
            }

            // Collect responses, refilling the window as tasks finish
            var responses: [UUID: Result<HTTPClient.Response, Error>] = [:]
            for await (id, result) in group {
                responses[id] = result
                if next < hostQueue.count {
                    schedule(hostQueue[next]); next += 1
                }
            }
            
            // Resume continuations in order
            if configuration.strictOrdering {
                // Return responses in request order
                for request in hostQueue {
                    if let result = responses[request.id] {
                        completeRequest(request.id, result: result)
                    }
                }
            } else {
                // Return responses as they arrive (already done above)
                for (id, result) in responses {
                    completeRequest(id, result: result)
                }
            }
        }
    }
    
    /// Completes a request with its result
    private func completeRequest(_ id: UUID, result: Result<HTTPClient.Response, Error>) {
        guard let request = inflightRequests.removeValue(forKey: id) else {
            return
        }
        
        switch result {
        case .success(let response):
            request.continuation.resume(returning: response)
        case .failure(let error):
            stats.pipelineErrors += 1
            request.continuation.resume(throwing: error)
        }
    }
    
    // MARK: - Background Flush Loop
    
    /// Background loop for flushing pipelines based on timeout
    private func runFlushLoop() async {
        while isRunning {
            // Sleep for flush timeout
            try? await Task.sleep(nanoseconds: UInt64(configuration.flushTimeout * 1_000_000_000))
            
            guard !Task.isCancelled else { break }
            
            // Flush all non-empty pipelines
            let hosts = Array(pendingRequests.keys)
            for _ in hosts {
                // Note: We can't capture executor here, so this will be handled differently
                // For now, we'll just track that we should flush
            }
        }
    }
    
    // MARK: - Statistics
    
    /// Returns current pipeline statistics
    public func statistics() -> HTTPPipelineStatistics {
        let avgDepth = stats.pipelineFlushes > 0
            ? Double(stats.totalPipelineDepth) / Double(stats.pipelineFlushes)
            : 0.0
        
        return HTTPPipelineStatistics(
            requestsPipelined: stats.requestsPipelined,
            requestsIndividual: stats.requestsIndividual,
            pipelineFlushes: stats.pipelineFlushes,
            averagePipelineDepth: avgDepth,
            pipelineErrors: stats.pipelineErrors,
            outOfOrderResponses: stats.outOfOrderResponses
        )
    }
}
