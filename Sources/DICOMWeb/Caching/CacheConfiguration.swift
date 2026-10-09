import Foundation

// NEMA-verified: 2026a, checked 2026-09-28 — carries no DICOM-standard data (cache time-to-live and size limits only)
/// Configuration for HTTP caching
///
/// Configures how DICOMweb responses are cached for improved
/// performance and reduced network traffic.
public struct CacheConfiguration: Sendable {
    /// Whether caching is enabled
    public let enabled: Bool
    
    /// Maximum number of entries in the cache
    public let maxEntries: Int
    
    /// Maximum size of the cache in bytes
    public let maxSizeBytes: Int
    
    /// Default TTL for cache entries (in seconds)
    public let defaultTTL: TimeInterval
    
    /// Whether to use ETags for validation
    public let useETags: Bool
    
    /// Whether to use Last-Modified for validation
    public let useLastModified: Bool
    
    /// Whether to respect Cache-Control headers from server
    public let respectCacheControl: Bool
    
    /// Cache storage type
    public let storageType: StorageType
    
    /// Creates a cache configuration
    /// - Parameters:
    ///   - enabled: Whether caching is enabled (default: true)
    ///   - maxEntries: Maximum cache entries (default: 1000)
    ///   - maxSizeBytes: Maximum cache size in bytes (default: 100MB)
    ///   - defaultTTL: Default time-to-live in seconds (default: 300)
    ///   - useETags: Whether to use ETags (default: true)
    ///   - useLastModified: Whether to use Last-Modified (default: true)
    ///   - respectCacheControl: Whether to respect server cache headers (default: true)
    ///   - storageType: Cache storage type (default: .memory)
    public init(
        enabled: Bool = true,
        maxEntries: Int = 1000,
        maxSizeBytes: Int = 100 * 1024 * 1024,
        defaultTTL: TimeInterval = 300,
        useETags: Bool = true,
        useLastModified: Bool = true,
        respectCacheControl: Bool = true,
        storageType: StorageType = .memory
    ) {
        self.enabled = enabled
        self.maxEntries = maxEntries
        self.maxSizeBytes = maxSizeBytes
        self.defaultTTL = defaultTTL
        self.useETags = useETags
        self.useLastModified = useLastModified
        self.respectCacheControl = respectCacheControl
        self.storageType = storageType
    }
    
    /// Cache storage type
    public enum StorageType: Sendable {
        /// In-memory cache (lost on app termination)
        case memory
        
        /// Disk-based cache (persists across app launches)
        case disk(directory: URL)
        
        /// Hybrid cache (memory with disk backing)
        case hybrid(memoryMaxSize: Int, diskDirectory: URL)
    }
}

// MARK: - Preset Configurations

extension CacheConfiguration {
    /// Disabled caching
    public static let disabled = CacheConfiguration(enabled: false)
    
    /// Minimal caching (100 entries, 10MB, short TTL)
    public static let minimal = CacheConfiguration(
        enabled: true,
        maxEntries: 100,
        maxSizeBytes: 10 * 1024 * 1024,
        defaultTTL: 60
    )
    
    /// Default caching configuration
    public static let `default` = CacheConfiguration()
    
    /// Aggressive caching (larger cache, longer TTL)
    public static let aggressive = CacheConfiguration(
        enabled: true,
        maxEntries: 10000,
        maxSizeBytes: 500 * 1024 * 1024,
        defaultTTL: 3600
    )
}

// MARK: - Cache Entry

/// A cached HTTP response
public struct CacheEntry: Sendable {
    /// The cached response data
    public let data: Data
    
    /// The content type of the response
    public let contentType: String?
    
    /// The ETag for validation
    public let etag: String?
    
    /// Last-Modified date
    public let lastModified: Date?
    
    /// When the entry was created
    public let createdAt: Date
    
    /// When the entry expires
    public let expiresAt: Date?
    
    /// The original response headers
    public let headers: [String: String]
    
    /// Size of the data in bytes
    public var size: Int { data.count }
    
    /// Creates a cache entry
    /// - Parameters:
    ///   - data: The response data
    ///   - contentType: Content type
    ///   - etag: ETag header value
    ///   - lastModified: Last-Modified date
    ///   - expiresAt: Expiration date
    ///   - headers: Response headers
    public init(
        data: Data,
        contentType: String? = nil,
        etag: String? = nil,
        lastModified: Date? = nil,
        expiresAt: Date? = nil,
        headers: [String: String] = [:]
    ) {
        self.data = data
        self.contentType = contentType
        self.etag = etag
        self.lastModified = lastModified
        self.createdAt = Date()
        self.expiresAt = expiresAt
        self.headers = headers
    }
    
    /// Whether the entry has expired
    public var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }
    
    /// Whether the entry can be validated (has ETag or Last-Modified)
    public var canValidate: Bool {
        return etag != nil || lastModified != nil
    }
}

// MARK: - Cache Protocol

/// Protocol for cache storage implementations
public protocol CacheStorage: Sendable {
    /// Gets a cached entry for the given key
    /// - Parameter key: The cache key
    /// - Returns: The cached entry if found
    func get(_ key: String) async -> CacheEntry?
    
    /// Stores an entry in the cache
    /// - Parameters:
    ///   - entry: The entry to cache
    ///   - key: The cache key
    func set(_ entry: CacheEntry, forKey key: String) async
    
    /// Removes an entry from the cache
    /// - Parameter key: The cache key
    func remove(_ key: String) async
    
    /// Clears all entries from the cache
    func clear() async
    
    /// Gets cache statistics
    func getStats() async -> CacheStats
}

/// Cache statistics
public struct CacheStats: Sendable {
    /// Number of entries in the cache
    public let entryCount: Int
    
    /// Total size of cached data in bytes
    public let totalSize: Int
    
    /// Number of cache hits
    public let hits: Int
    
    /// Number of cache misses
    public let misses: Int
    
    /// Cache hit ratio (0.0 to 1.0)
    public var hitRatio: Double {
        let total = hits + misses
        guard total > 0 else { return 0 }
        return Double(hits) / Double(total)
    }
    
    public init(entryCount: Int = 0, totalSize: Int = 0, hits: Int = 0, misses: Int = 0) {
        self.entryCount = entryCount
        self.totalSize = totalSize
        self.hits = hits
        self.misses = misses
    }
}
