import Foundation

// NEMA-verified: 2026a, checked 2026-09-28 — carries no DICOM-standard data (request prefetching)
/// Configuration for HTTP request prefetching
///
/// Controls predictive prefetching behavior for likely future requests.
public struct HTTPPrefetchConfiguration: Sendable, Hashable {
    /// Maximum number of items to prefetch ahead
    public let maxPrefetchAhead: Int
    
    /// Maximum cache size in bytes for prefetched data
    public let maxCacheSize: Int64
    
    /// Whether to enable prefetching
    public let enablePrefetching: Bool
    
    /// Prefetch strategy
    public let strategy: PrefetchStrategy
    
    /// Priority for prefetch requests
    public let prefetchPriority: Priority
    
    /// Prefetch strategy options
    public enum PrefetchStrategy: String, Sendable, Hashable {
        /// Sequential prefetching (e.g., next images in a series)
        case sequential
        
        /// Predictive prefetching based on usage patterns
        case predictive
        
        /// Aggressive prefetching (prefetch entire series/study)
        case aggressive
    }
    
    /// Priority levels for prefetch requests
    public enum Priority: Int, Sendable, Hashable {
        case low = 0
        case medium = 1
        case high = 2
    }
    
    /// Creates a prefetch configuration
    /// - Parameters:
    ///   - maxPrefetchAhead: Maximum items to prefetch (default: 5)
    ///   - maxCacheSize: Maximum cache size in bytes (default: 500MB)
    ///   - enablePrefetching: Enable prefetching (default: true)
    ///   - strategy: Prefetch strategy (default: sequential)
    ///   - prefetchPriority: Priority level (default: low)
    public init(
        maxPrefetchAhead: Int = 5,
        maxCacheSize: Int64 = 500_000_000,
        enablePrefetching: Bool = true,
        strategy: PrefetchStrategy = .sequential,
        prefetchPriority: Priority = .low
    ) {
        self.maxPrefetchAhead = max(1, maxPrefetchAhead)
        self.maxCacheSize = max(1_000_000, maxCacheSize)
        self.enablePrefetching = enablePrefetching
        self.strategy = strategy
        self.prefetchPriority = prefetchPriority
    }
    
    /// Default configuration for standard prefetching
    public static let `default` = HTTPPrefetchConfiguration()
    
    /// Disabled configuration (no prefetching)
    public static let disabled = HTTPPrefetchConfiguration(enablePrefetching: false)
    
    /// Aggressive configuration for maximum prefetching
    public static let aggressive = HTTPPrefetchConfiguration(
        maxPrefetchAhead: 20,
        maxCacheSize: 2_000_000_000,
        strategy: .aggressive,
        prefetchPriority: .high
    )
    
    /// Low-resource configuration for constrained environments
    public static let lowResource = HTTPPrefetchConfiguration(
        maxPrefetchAhead: 2,
        maxCacheSize: 100_000_000,
        strategy: .sequential,
        prefetchPriority: .low
    )
}

/// Statistics for HTTP prefetching
public struct HTTPPrefetchStatistics: Sendable {
    /// Total requests prefetched
    public let requestsPrefetched: Int
    
    /// Total prefetch hits (data was already cached)
    public let prefetchHits: Int
    
    /// Total prefetch misses (data not cached when needed)
    public let prefetchMisses: Int
    
    /// Total bytes prefetched
    public let bytesPrefetched: Int64
    
    /// Current cache size in bytes
    public let currentCacheSize: Int64
    
    /// Number of items in cache
    public let cacheItems: Int
    
    /// Number of cache evictions
    public let cacheEvictions: Int
    
    /// Hit rate (0.0 to 1.0)
    public var hitRate: Double {
        let total = prefetchHits + prefetchMisses
        return total > 0 ? Double(prefetchHits) / Double(total) : 0.0
    }
    
    /// Creates prefetch statistics
    public init(
        requestsPrefetched: Int,
        prefetchHits: Int,
        prefetchMisses: Int,
        bytesPrefetched: Int64,
        currentCacheSize: Int64,
        cacheItems: Int,
        cacheEvictions: Int
    ) {
        self.requestsPrefetched = requestsPrefetched
        self.prefetchHits = prefetchHits
        self.prefetchMisses = prefetchMisses
        self.bytesPrefetched = bytesPrefetched
        self.currentCacheSize = currentCacheSize
        self.cacheItems = cacheItems
        self.cacheEvictions = cacheEvictions
    }
}

/// Actor managing HTTP request prefetching
///
/// Implements predictive prefetching with LRU caching for improved performance.
actor HTTPPrefetchManager {
    
    // MARK: - Types
    
    /// Cached prefetch entry
    private struct CacheEntry {
        /// The cached URL
        let url: URL
        
        /// The cached response data
        let data: Data
        
        /// The response headers
        let headers: [String: String]
        
        /// When the entry was cached
        let cachedAt: Date
        
        /// Last access time
        var lastAccessedAt: Date
        
        /// Access count
        var accessCount: Int
        
        /// Size in bytes
        var size: Int64 {
            return Int64(data.count)
        }
    }
    
    /// Prefetch request in queue
    private struct PrefetchRequest {
        /// The URL to prefetch
        let url: URL
        
        /// Priority
        let priority: HTTPPrefetchConfiguration.Priority
        
        /// When queued
        let queuedAt: Date
    }
    
    // MARK: - Properties
    
    /// Configuration for this prefetch manager
    private let configuration: HTTPPrefetchConfiguration
    
    /// Prefetch cache (URL -> CacheEntry)
    private var cache: [String: CacheEntry] = [:]
    
    /// Prefetch queue (sorted by priority)
    private var prefetchQueue: [PrefetchRequest] = []
    
    /// Currently prefetching URLs
    private var inflightPrefetches: Set<String> = []
    
    /// Statistics tracking
    private var stats = Stats()
    
    /// Whether the manager is running
    private var isRunning = false
    
    /// Background prefetch task
    private var prefetchTask: Task<Void, Never>?
    
    // MARK: - Statistics Struct
    
    private struct Stats {
        var requestsPrefetched: Int = 0
        var prefetchHits: Int = 0
        var prefetchMisses: Int = 0
        var bytesPrefetched: Int64 = 0
        var cacheEvictions: Int = 0
    }
    
    // MARK: - Initialization
    
    /// Creates a prefetch manager
    /// - Parameter configuration: Prefetch configuration
    public init(configuration: HTTPPrefetchConfiguration = .default) {
        self.configuration = configuration
    }
    
    // MARK: - Lifecycle
    
    /// Starts the prefetch manager
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        
        if configuration.enablePrefetching {
            // Start background prefetch task
            prefetchTask = Task { [weak self] in
                await self?.runPrefetchLoop()
            }
        }
    }
    
    /// Stops the prefetch manager
    public func stop() {
        isRunning = false
        prefetchTask?.cancel()
        prefetchTask = nil
        prefetchQueue.removeAll()
        inflightPrefetches.removeAll()
    }
    
    // MARK: - Cache Operations
    
    /// Checks if a URL is cached
    /// - Parameter url: The URL to check
    /// - Returns: True if cached
    public func isCached(_ url: URL) -> Bool {
        return cache[url.absoluteString] != nil
    }
    
    /// Gets cached data for a URL
    /// - Parameter url: The URL to retrieve
    /// - Returns: Cached response if available
    public func getCached(_ url: URL) -> HTTPClient.Response? {
        let key = url.absoluteString
        
        guard var entry = cache[key] else {
            stats.prefetchMisses += 1
            return nil
        }
        
        // Update access info
        entry.lastAccessedAt = Date()
        entry.accessCount += 1
        cache[key] = entry
        
        stats.prefetchHits += 1
        
        return HTTPClient.Response(
            statusCode: 200,
            headers: entry.headers,
            body: entry.data
        )
    }
    
    /// Adds data to cache
    /// - Parameters:
    ///   - url: The URL
    ///   - data: The response data
    ///   - headers: Response headers
    private func addToCache(url: URL, data: Data, headers: [String: String]) {
        let key = url.absoluteString
        let entry = CacheEntry(
            url: url,
            data: data,
            headers: headers,
            cachedAt: Date(),
            lastAccessedAt: Date(),
            accessCount: 0
        )
        
        // Check if we need to evict entries
        while currentCacheSize + entry.size > configuration.maxCacheSize && !cache.isEmpty {
            evictLRU()
        }
        
        cache[key] = entry
        stats.bytesPrefetched += entry.size
    }
    
    /// Evicts least recently used entry
    private func evictLRU() {
        guard let lruKey = cache.min(by: { $0.value.lastAccessedAt < $1.value.lastAccessedAt })?.key else {
            return
        }
        
        cache.removeValue(forKey: lruKey)
        stats.cacheEvictions += 1
    }
    
    /// Current cache size
    private var currentCacheSize: Int64 {
        return cache.values.reduce(0) { $0 + $1.size }
    }
    
    // MARK: - Prefetching
    
    /// Enqueues URLs for prefetching
    /// - Parameters:
    ///   - urls: URLs to prefetch
    ///   - priority: Priority level
    public func enqueuePrefetch(urls: [URL], priority: HTTPPrefetchConfiguration.Priority = .low) {
        guard configuration.enablePrefetching else { return }
        
        let now = Date()
        for url in urls {
            let key = url.absoluteString
            
            // Skip if already cached or in flight
            guard !isCached(url) && !inflightPrefetches.contains(key) else {
                continue
            }
            
            let request = PrefetchRequest(
                url: url,
                priority: priority,
                queuedAt: now
            )
            
            prefetchQueue.append(request)
        }
        
        // Sort queue by priority (high to low)
        prefetchQueue.sort { $0.priority.rawValue > $1.priority.rawValue }
    }
    
    /// Background loop for processing prefetch queue
    private func runPrefetchLoop() async {
        while isRunning {
            // Sleep briefly between batches
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            
            guard !Task.isCancelled && !prefetchQueue.isEmpty else {
                continue
            }
            
            // Process next batch (limited by maxPrefetchAhead)
            let batchSize = min(configuration.maxPrefetchAhead, prefetchQueue.count)
            let batch = Array(prefetchQueue.prefix(batchSize))
            prefetchQueue.removeFirst(batchSize)
            
            // Note: Actual prefetching would need an executor function
            // For now, we just mark them as inflight
            for request in batch {
                inflightPrefetches.insert(request.url.absoluteString)
            }
        }
    }
    
    // MARK: - Statistics
    
    /// Returns current prefetch statistics
    public func statistics() -> HTTPPrefetchStatistics {
        return HTTPPrefetchStatistics(
            requestsPrefetched: stats.requestsPrefetched,
            prefetchHits: stats.prefetchHits,
            prefetchMisses: stats.prefetchMisses,
            bytesPrefetched: stats.bytesPrefetched,
            currentCacheSize: currentCacheSize,
            cacheItems: cache.count,
            cacheEvictions: stats.cacheEvictions
        )
    }
    
    /// Clears the prefetch cache
    public func clearCache() {
        cache.removeAll()
    }
}
