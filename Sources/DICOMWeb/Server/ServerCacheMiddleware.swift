import Foundation

// NEMA-verified: 2026a, checked 2026-09-28 — carries no DICOM-standard data (ETag / 304 cache keyed on the Accept header); media type names in PS3.18 2026a 8.7.3.5
/// Middleware for server-side HTTP response caching
///
/// Provides server-side caching for DICOMweb responses with ETag-based
/// conditional request support. Cacheable responses are stored in an
/// in-memory cache and served directly for subsequent requests, reducing
/// storage backend load. Supports `If-None-Match` conditional requests
/// that return `304 Not Modified` when the cached version is still valid.
///
/// Reference: RFC 7232 - Conditional Requests
/// Reference: RFC 7234 - HTTP Caching
public actor ServerCacheMiddleware {

    // MARK: - Properties

    /// The cache configuration
    public let configuration: CacheConfiguration

    /// The underlying cache storage
    private let cache: InMemoryCache

    // MARK: - Initialization

    /// Creates a server cache middleware
    /// - Parameter configuration: The cache configuration
    public init(configuration: CacheConfiguration = .default) {
        self.configuration = configuration
        self.cache = InMemoryCache(configuration: configuration)
    }

    // MARK: - Cache Operations

    /// Checks if a cached response exists for the request and handles conditional requests
    /// - Parameter request: The incoming HTTP request
    /// - Returns: A cached response if available, or nil if the request should be processed normally
    public func cachedResponse(for request: DICOMwebRequest) async -> DICOMwebResponse? {
        guard configuration.enabled else { return nil }

        // Only cache GET requests
        guard request.method == .get else { return nil }

        let cacheKey = self.cacheKey(for: request)

        // Check for cached entry
        guard let entry = await cache.get(cacheKey) else {
            return nil
        }

        // Handle conditional request: If-None-Match
        if let ifNoneMatch = request.header("If-None-Match"),
           let etag = entry.etag {
            let clientETags = parseETags(ifNoneMatch)
            if clientETags.contains(etag) || clientETags.contains("*") {
                // Client has a matching version - return 304 Not Modified
                return notModified(etag: etag)
            }
        }

        // Return cached response with ETag and Cache-Control headers
        var headers = entry.headers
        if let etag = entry.etag {
            headers["ETag"] = etag
        }
        if let contentType = entry.contentType {
            headers["Content-Type"] = contentType
        }
        if let data = entry.data as Data? {
            headers["Content-Length"] = "\(data.count)"
        }
        headers["X-Cache"] = "HIT"

        return DICOMwebResponse(
            statusCode: 200,
            headers: headers,
            body: entry.data
        )
    }

    /// Stores a response in the cache and adds caching headers
    /// - Parameters:
    ///   - response: The response to cache
    ///   - request: The original request
    /// - Returns: The response with added caching headers (ETag, Cache-Control)
    public func cacheResponse(
        _ response: DICOMwebResponse,
        for request: DICOMwebRequest
    ) async -> DICOMwebResponse {
        guard configuration.enabled else { return response }

        // Only cache successful GET responses
        guard request.method == .get, response.statusCode == 200 else { return response }

        // Don't cache responses without a body
        guard let body = response.body, !body.isEmpty else { return response }

        // Don't cache if handler type is not cacheable
        guard isCacheableContentType(response.headers["Content-Type"]) else {
            return response
        }

        // Generate ETag from response body
        let etag = generateETag(from: body)

        // Create cache entry
        let entry = CacheEntry(
            data: body,
            contentType: response.headers["Content-Type"],
            etag: etag,
            lastModified: nil,
            expiresAt: Date().addingTimeInterval(configuration.defaultTTL),
            headers: filteredHeaders(from: response.headers)
        )

        let cacheKey = self.cacheKey(for: request)
        await cache.set(entry, forKey: cacheKey)

        // Add caching headers to response
        var headers = response.headers
        headers["ETag"] = etag
        headers["Cache-Control"] = "public, max-age=\(Int(configuration.defaultTTL))"
        headers["X-Cache"] = "MISS"

        return DICOMwebResponse(
            statusCode: response.statusCode,
            headers: headers,
            body: body
        )
    }

    /// Invalidates cached entries related to a study
    /// - Parameter studyUID: The study UID whose cache entries should be invalidated
    public func invalidate(studyUID: String) async {
        // Clear all cache entries (simple approach; a production system would
        // maintain an index of cache keys per study for targeted invalidation)
        await cache.clear()
    }

    /// Invalidates all cached entries
    public func invalidateAll() async {
        await cache.clear()
    }

    /// Returns current cache statistics
    public func statistics() async -> CacheStats {
        await cache.getStats()
    }

    // MARK: - Private Helpers

    /// Generates a cache key from a request
    private func cacheKey(for request: DICOMwebRequest) -> String {
        var components = [request.path]

        // Include sorted query parameters for consistent keys
        let sortedParams = request.queryParameters.sorted { $0.key < $1.key }
        for (key, value) in sortedParams {
            components.append("\(key)=\(value)")
        }

        // Include Accept header as it affects the response format
        if let accept = request.header("Accept") {
            components.append("Accept:\(accept)")
        }

        return components.joined(separator: "|")
    }

    /// Generates an ETag from response data
    ///
    /// Uses a simple hash-based approach for generating weak ETags.
    /// For large responses, samples the data to avoid hashing the entire payload.
    private func generateETag(from data: Data) -> String {
        // Use a hash of the data content and size for the ETag
        var hasher = Hasher()
        hasher.combine(data.count)

        // Sample data for hashing to avoid processing very large payloads
        let sampleSize = min(data.count, 8192)
        if sampleSize > 0 {
            data.prefix(sampleSize).withUnsafeBytes { buffer in
                if let baseAddress = buffer.baseAddress {
                    hasher.combine(bytes: UnsafeRawBufferPointer(start: baseAddress, count: sampleSize))
                }
            }
        }

        // Also sample the end of the data if it's larger than sampleSize
        if data.count > sampleSize {
            let tailStart = data.count - sampleSize
            data.suffix(from: tailStart).prefix(sampleSize).withUnsafeBytes { buffer in
                if let baseAddress = buffer.baseAddress {
                    hasher.combine(bytes: UnsafeRawBufferPointer(start: baseAddress, count: min(sampleSize, buffer.count)))
                }
            }
        }

        let hash = hasher.finalize()
        return "W/\"\(String(format: "%08x", abs(hash)))\""
    }

    /// Parses a comma-separated list of ETags from the If-None-Match header
    private func parseETags(_ headerValue: String) -> [String] {
        return headerValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Creates a 304 Not Modified response
    private func notModified(etag: String) -> DICOMwebResponse {
        DICOMwebResponse(
            statusCode: 304,
            headers: [
                "ETag": etag,
                "X-Cache": "HIT"
            ],
            body: nil
        )
    }

    /// Determines if a content type should be cached
    private func isCacheableContentType(_ contentType: String?) -> Bool {
        guard let contentType = contentType else { return true }

        let lowered = contentType.lowercased()

        // Cache JSON metadata responses and DICOM multipart responses
        return lowered.contains("application/dicom+json") ||
               lowered.contains("application/json") ||
               lowered.contains("multipart/related") ||
               lowered.contains("application/dicom") ||
               lowered.contains("application/octet-stream")
    }

    /// Filters response headers to store only relevant ones in cache
    private func filteredHeaders(from headers: [String: String]) -> [String: String] {
        let headersToKeep = Set([
            "content-type",
            "x-total-count",
            "warning"
        ])

        return headers.filter { headersToKeep.contains($0.key.lowercased()) }
    }
}
