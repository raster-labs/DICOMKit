import Foundation

// NEMA-verified: 2026a, checked 2026-09-28 — carries no DICOM-standard data (in-memory HTTP response cache; Accept and Accept-Encoding are generic RFC 7231 header names)
/// In-memory cache implementation for DICOMweb responses
///
/// Provides a thread-safe, LRU-based cache for storing HTTP responses.
/// Supports TTL, size limits, and entry limits.
public actor InMemoryCache: CacheStorage {
    
    // MARK: - Types
    
    private struct CacheNode {
        let key: String
        var entry: CacheEntry
        var lastAccessed: Date
    }
    
    // MARK: - Properties
    
    private let configuration: CacheConfiguration
    private var entries: [String: CacheNode] = [:]
    private var accessOrder: [String] = []
    private var currentSize: Int = 0
    private var hits: Int = 0
    private var misses: Int = 0
    
    // MARK: - Initialization
    
    /// Creates an in-memory cache with the given configuration
    /// - Parameter configuration: The cache configuration
    public init(configuration: CacheConfiguration = .default) {
        self.configuration = configuration
    }
    
    // MARK: - CacheStorage
    
    public func get(_ key: String) async -> CacheEntry? {
        guard configuration.enabled else {
            misses += 1
            return nil
        }
        
        guard var node = entries[key] else {
            misses += 1
            return nil
        }
        
        // Check if expired
        if node.entry.isExpired {
            await remove(key)
            misses += 1
            return nil
        }
        
        // Update access time and order
        node.lastAccessed = Date()
        entries[key] = node
        updateAccessOrder(key)
        
        hits += 1
        return node.entry
    }
    
    public func set(_ entry: CacheEntry, forKey key: String) async {
        guard configuration.enabled else { return }
        
        // Remove existing entry if present
        if entries[key] != nil {
            await remove(key)
        }
        
        // Check if entry fits in cache
        let entrySize = entry.size
        if entrySize > configuration.maxSizeBytes {
            // Entry too large for cache
            return
        }
        
        // Evict entries if necessary
        while currentSize + entrySize > configuration.maxSizeBytes && !entries.isEmpty {
            await evictLeastRecentlyUsed()
        }
        
        while entries.count >= configuration.maxEntries && !entries.isEmpty {
            await evictLeastRecentlyUsed()
        }
        
        // Store entry
        let node = CacheNode(key: key, entry: entry, lastAccessed: Date())
        entries[key] = node
        accessOrder.append(key)
        currentSize += entrySize
    }
    
    public func remove(_ key: String) async {
        guard let node = entries.removeValue(forKey: key) else { return }
        currentSize -= node.entry.size
        accessOrder.removeAll { $0 == key }
    }
    
    public func clear() async {
        entries.removeAll()
        accessOrder.removeAll()
        currentSize = 0
        // Preserve hit/miss stats
    }
    
    public func getStats() async -> CacheStats {
        return CacheStats(
            entryCount: entries.count,
            totalSize: currentSize,
            hits: hits,
            misses: misses
        )
    }
    
    // MARK: - Helper Methods
    
    /// Gets an entry if it exists and is valid, otherwise returns validation info
    /// - Parameter key: The cache key
    /// - Returns: Tuple of optional entry and validation headers
    public func getWithValidation(_ key: String) async -> (entry: CacheEntry?, validationHeaders: [String: String]) {
        guard configuration.enabled else {
            return (nil, [:])
        }
        
        guard let node = entries[key] else {
            return (nil, [:])
        }
        
        // If not expired, return the entry
        if !node.entry.isExpired {
            hits += 1
            updateAccessOrder(key)
            return (node.entry, [:])
        }
        
        // Entry is expired but can potentially be validated
        var headers: [String: String] = [:]
        
        if configuration.useETags, let etag = node.entry.etag {
            headers["If-None-Match"] = etag
        }
        
        if configuration.useLastModified, let lastModified = node.entry.lastModified {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "GMT")
            headers["If-Modified-Since"] = formatter.string(from: lastModified)
        }
        
        return (nil, headers)
    }
    
    /// Updates an entry's expiration after successful validation
    /// - Parameters:
    ///   - key: The cache key
    ///   - newExpiration: The new expiration date
    public func updateExpiration(_ key: String, newExpiration: Date) async {
        guard var node = entries[key] else { return }
        
        // Create new entry with updated expiration
        let updatedEntry = CacheEntry(
            data: node.entry.data,
            contentType: node.entry.contentType,
            etag: node.entry.etag,
            lastModified: node.entry.lastModified,
            expiresAt: newExpiration,
            headers: node.entry.headers
        )
        
        node.entry = updatedEntry
        node.lastAccessed = Date()
        entries[key] = node
        updateAccessOrder(key)
    }
    
    /// Removes expired entries
    public func removeExpired() async {
        let expiredKeys = entries.filter { $0.value.entry.isExpired }.map { $0.key }
        for key in expiredKeys {
            await remove(key)
        }
    }
    
    /// Resets statistics
    public func resetStats() async {
        hits = 0
        misses = 0
    }
    
    // MARK: - Private Methods
    
    private func updateAccessOrder(_ key: String) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }
    
    private func evictLeastRecentlyUsed() async {
        guard !accessOrder.isEmpty else { return }
        let key = accessOrder.removeFirst()
        if let node = entries.removeValue(forKey: key) {
            currentSize -= node.entry.size
        }
    }
}

// MARK: - Cache Key Generation

/// Utilities for generating cache keys
public enum CacheKeyGenerator {
    /// Generates a cache key for a URL
    /// - Parameter url: The URL to generate a key for
    /// - Returns: A unique cache key
    public static func key(for url: URL) -> String {
        return url.absoluteString
    }
    
    /// Generates a cache key for a URL with headers
    /// - Parameters:
    ///   - url: The URL
    ///   - headers: Headers that affect the response (e.g., Accept)
    /// - Returns: A unique cache key
    public static func key(for url: URL, headers: [String: String]) -> String {
        var components = [url.absoluteString]
        
        // Include relevant headers in key
        let relevantHeaders = ["Accept", "Accept-Encoding", "Accept-Language"]
        for header in relevantHeaders {
            if let value = headers[header] {
                components.append("\(header):\(value)")
            }
        }
        
        return components.joined(separator: "|")
    }
    
    /// Generates a cache key for DICOM metadata
    /// - Parameters:
    ///   - studyUID: Study Instance UID
    ///   - seriesUID: Optional Series Instance UID
    ///   - instanceUID: Optional SOP Instance UID
    /// - Returns: A unique cache key for metadata
    public static func metadataKey(
        studyUID: String,
        seriesUID: String? = nil,
        instanceUID: String? = nil
    ) -> String {
        var components = ["metadata", studyUID]
        if let seriesUID = seriesUID {
            components.append(seriesUID)
        }
        if let instanceUID = instanceUID {
            components.append(instanceUID)
        }
        return components.joined(separator: "/")
    }
}

// MARK: - Cache-Control Parsing

/// Parses Cache-Control headers
public struct CacheControlDirective: Sendable, Equatable {
    /// Whether the response is cacheable
    public let isPublic: Bool
    
    /// Whether caching is prohibited
    public let noStore: Bool
    
    /// Whether validation is required
    public let noCache: Bool
    
    /// Maximum age in seconds
    public let maxAge: Int?
    
    /// Shared cache maximum age in seconds
    public let sMaxAge: Int?
    
    /// Whether revalidation is required after stale
    public let mustRevalidate: Bool
    
    /// Stale-while-revalidate seconds
    public let staleWhileRevalidate: Int?
    
    /// Parses a Cache-Control header value
    /// - Parameter headerValue: The Cache-Control header value
    public init(headerValue: String) {
        let directives = headerValue.lowercased()
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        
        var isPublic = false
        var noStore = false
        var noCache = false
        var maxAge: Int? = nil
        var sMaxAge: Int? = nil
        var mustRevalidate = false
        var staleWhileRevalidate: Int? = nil
        
        for directive in directives {
            if directive == "public" {
                isPublic = true
            } else if directive == "no-store" {
                noStore = true
            } else if directive == "no-cache" {
                noCache = true
            } else if directive == "must-revalidate" {
                mustRevalidate = true
            } else if directive.hasPrefix("max-age=") {
                let value = directive.dropFirst("max-age=".count)
                maxAge = Int(value)
            } else if directive.hasPrefix("s-maxage=") {
                let value = directive.dropFirst("s-maxage=".count)
                sMaxAge = Int(value)
            } else if directive.hasPrefix("stale-while-revalidate=") {
                let value = directive.dropFirst("stale-while-revalidate=".count)
                staleWhileRevalidate = Int(value)
            }
        }
        
        self.isPublic = isPublic
        self.noStore = noStore
        self.noCache = noCache
        self.maxAge = maxAge
        self.sMaxAge = sMaxAge
        self.mustRevalidate = mustRevalidate
        self.staleWhileRevalidate = staleWhileRevalidate
    }
    
    /// Whether the response should be cached
    public var shouldCache: Bool {
        return !noStore
    }
    
    /// Calculates the expiration date based on directives
    /// - Parameter fallbackTTL: Fallback TTL if no max-age is specified
    /// - Returns: The expiration date
    public func expirationDate(fallbackTTL: TimeInterval = 300) -> Date {
        let ttl: TimeInterval
        if let maxAge = maxAge {
            ttl = TimeInterval(maxAge)
        } else {
            ttl = fallbackTTL
        }
        return Date().addingTimeInterval(ttl)
    }
}
