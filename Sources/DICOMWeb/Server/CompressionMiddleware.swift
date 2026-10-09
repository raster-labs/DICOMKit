import Foundation
#if canImport(Compression)
import Compression
#endif

// NEMA-verified: 2026a, checked 2026-09-28 — carries no DICOM-standard data beyond media type names (all in PS3.18 2026a 8.7.3.5 / Table 8.7.4-1); Content-Encoding of a whole response is permitted by PS3.18 8.4.2 Table 8.4.2-1
/// Configuration for HTTP response compression
///
/// Controls how the DICOMweb server compresses responses to reduce bandwidth
/// and improve transfer speeds for supported clients.
///
/// Reference: RFC 7231 Section 5.3.4 - Accept-Encoding
public struct CompressionConfiguration: Sendable, Equatable {
    /// Whether compression is enabled
    public let enabled: Bool
    
    /// Compression algorithms to use (in order of preference)
    public let algorithms: [CompressionAlgorithm]
    
    /// Minimum response size in bytes to trigger compression
    /// Responses smaller than this won't be compressed (overhead not worth it)
    public let minimumSize: Int
    
    /// Compression level (0-9, where 0=none, 1=fastest, 9=best compression)
    public let level: Int
    
    /// Content types that should be compressed
    /// Empty set means compress all compressible types
    public let compressibleTypes: Set<String>
    
    /// Content types that should never be compressed (e.g., already compressed formats)
    public let excludedTypes: Set<String>
    
    /// Creates a compression configuration
    /// - Parameters:
    ///   - enabled: Whether compression is enabled (default: true)
    ///   - algorithms: Compression algorithms to use (default: [.gzip, .deflate])
    ///   - minimumSize: Minimum response size to compress (default: 1024 bytes)
    ///   - level: Compression level 0-9 (default: 6, good balance)
    ///   - compressibleTypes: Content types to compress (empty = all compressible)
    ///   - excludedTypes: Content types to never compress
    public init(
        enabled: Bool = true,
        algorithms: [CompressionAlgorithm] = [.gzip, .deflate],
        minimumSize: Int = 1024,
        level: Int = 6,
        compressibleTypes: Set<String> = [],
        excludedTypes: Set<String> = CompressionConfiguration.defaultExcludedTypes
    ) {
        self.enabled = enabled
        self.algorithms = algorithms
        self.minimumSize = max(0, minimumSize)
        self.level = max(0, min(9, level))
        self.compressibleTypes = compressibleTypes
        self.excludedTypes = excludedTypes
    }
    
    /// Default compression configuration with gzip and deflate
    public static let `default` = CompressionConfiguration()
    
    /// High compression configuration for slower networks
    public static let highCompression = CompressionConfiguration(
        minimumSize: 512,
        level: 9
    )
    
    /// Fast compression configuration for low latency
    public static let fast = CompressionConfiguration(
        minimumSize: 2048,
        level: 1
    )
    
    /// Disabled compression configuration
    public static let disabled = CompressionConfiguration(enabled: false)
    
    /// Default content types that should not be compressed (already compressed)
    public static let defaultExcludedTypes: Set<String> = [
        "image/jpeg",
        "image/png",
        "image/gif",
        "image/webp",
        "video/mp4",
        "video/mpeg",
        "video/webm",
        "audio/mpeg",
        "audio/mp4",
        "application/zip",
        "application/gzip",
        "application/x-gzip",
        "application/x-compressed"
    ]
    
    /// Default compressible content types for DICOMweb
    public static let dicomwebCompressibleTypes: Set<String> = [
        "application/dicom+json",
        "application/dicom+xml",
        "application/json",
        "application/xml",
        "text/plain",
        "text/html",
        "text/xml",
        "application/dicom" // Uncompressed DICOM can benefit from compression
    ]
}

/// Supported compression algorithms
public enum CompressionAlgorithm: String, Sendable, Equatable, CaseIterable {
    /// gzip compression (RFC 1952)
    case gzip = "gzip"
    
    /// deflate compression (RFC 1951)
    case deflate = "deflate"
    
    /// The HTTP header value for this algorithm
    public var headerValue: String {
        rawValue
    }
    
    /// Parses an Accept-Encoding header value to extract algorithm
    /// - Parameter value: The header value (e.g., "gzip", "gzip;q=0.8")
    /// - Returns: The algorithm if supported
    public static func parse(_ value: String) -> CompressionAlgorithm? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        // Remove quality parameter if present (e.g., "gzip;q=0.8" -> "gzip")
        let algorithm = trimmed.split(separator: ";").first.map(String.init) ?? trimmed
        return CompressionAlgorithm(rawValue: algorithm.lowercased())
    }
}

/// Represents a parsed Accept-Encoding header entry with quality value
public struct AcceptEncodingEntry: Sendable, Equatable {
    /// The compression algorithm
    public let algorithm: CompressionAlgorithm
    
    /// Quality value (0.0-1.0, higher is more preferred)
    public let quality: Double
    
    /// Creates an Accept-Encoding entry
    /// - Parameters:
    ///   - algorithm: The compression algorithm
    ///   - quality: Quality value (default: 1.0)
    public init(algorithm: CompressionAlgorithm, quality: Double = 1.0) {
        self.algorithm = algorithm
        self.quality = max(0.0, min(1.0, quality))
    }
    
    /// Parses a single Accept-Encoding entry (e.g., "gzip;q=0.8")
    /// - Parameter value: The entry string
    /// - Returns: The parsed entry, or nil if invalid
    public static func parse(_ value: String) -> AcceptEncodingEntry? {
        let parts = value.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let algorithmPart = parts.first,
              let algorithm = CompressionAlgorithm(rawValue: algorithmPart.lowercased()) else {
            return nil
        }
        
        var quality: Double = 1.0
        for part in parts.dropFirst() {
            if part.lowercased().hasPrefix("q=") {
                let qValue = String(part.dropFirst(2))
                quality = Double(qValue) ?? 1.0
            }
        }
        
        return AcceptEncodingEntry(algorithm: algorithm, quality: quality)
    }
}

/// Middleware for compressing HTTP responses
///
/// Handles Accept-Encoding header parsing and response compression
/// using gzip or deflate algorithms based on client preferences.
public struct CompressionMiddleware: Sendable {
    /// The compression configuration
    public let configuration: CompressionConfiguration
    
    /// Creates a compression middleware
    /// - Parameter configuration: The compression configuration
    public init(configuration: CompressionConfiguration = .default) {
        self.configuration = configuration
    }
    
    /// Parses the Accept-Encoding header to get preferred algorithms
    /// - Parameter header: The Accept-Encoding header value
    /// - Returns: Sorted array of accepted algorithms (highest quality first)
    public func parseAcceptEncoding(_ header: String?) -> [AcceptEncodingEntry] {
        guard let header = header, !header.isEmpty else {
            return []
        }
        
        // Parse all entries
        let entries = header.split(separator: ",")
            .compactMap { AcceptEncodingEntry.parse(String($0)) }
            .filter { $0.quality > 0 } // Quality 0 means "not acceptable"
            .sorted { $0.quality > $1.quality } // Sort by quality descending
        
        return entries
    }
    
    /// Selects the best compression algorithm based on client and server preferences
    /// - Parameter acceptEncoding: The Accept-Encoding header value
    /// - Returns: The selected algorithm, or nil if none should be used
    public func selectAlgorithm(acceptEncoding: String?) -> CompressionAlgorithm? {
        guard configuration.enabled, !configuration.algorithms.isEmpty else {
            return nil
        }
        
        let clientPreferences = parseAcceptEncoding(acceptEncoding)
        guard !clientPreferences.isEmpty else {
            return nil
        }
        
        // Find the first algorithm that both client and server support
        // Client preferences are sorted by quality, server preferences are in order
        for clientEntry in clientPreferences {
            if configuration.algorithms.contains(clientEntry.algorithm) {
                return clientEntry.algorithm
            }
        }
        
        return nil
    }
    
    /// Determines if a content type should be compressed
    /// - Parameter contentType: The Content-Type header value
    /// - Returns: true if the content should be compressed
    public func shouldCompress(contentType: String?) -> Bool {
        guard let contentType = contentType else {
            return false
        }
        
        // Extract base content type (without parameters like charset)
        let baseType = contentType.split(separator: ";").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? contentType
        let lowercasedType = baseType.lowercased()
        
        // Check excluded types first
        if configuration.excludedTypes.contains(lowercasedType) {
            return false
        }
        
        // If specific compressible types are configured, check against them
        if !configuration.compressibleTypes.isEmpty {
            return configuration.compressibleTypes.contains(lowercasedType)
        }
        
        // Default: compress text-based and JSON/XML types
        return lowercasedType.hasPrefix("text/") ||
               lowercasedType.contains("+json") ||
               lowercasedType.contains("+xml") ||
               lowercasedType == "application/json" ||
               lowercasedType == "application/xml" ||
               lowercasedType == "application/dicom"
    }
    
    /// Compresses a response if appropriate
    /// - Parameters:
    ///   - response: The original response
    ///   - acceptEncoding: The Accept-Encoding header from the request
    /// - Returns: The possibly compressed response with updated headers
    public func compressResponse(
        _ response: DICOMwebResponse,
        acceptEncoding: String?
    ) -> DICOMwebResponse {
        guard configuration.enabled,
              let body = response.body,
              body.count >= configuration.minimumSize else {
            return response
        }
        
        // Check if content type is compressible
        let contentType = response.headers["Content-Type"]
        guard shouldCompress(contentType: contentType) else {
            return response
        }
        
        // Check if already encoded
        if response.headers["Content-Encoding"] != nil {
            return response
        }
        
        // Select algorithm based on client preferences
        guard let algorithm = selectAlgorithm(acceptEncoding: acceptEncoding) else {
            return response
        }
        
        // Compress the body
        guard let compressedBody = compress(data: body, using: algorithm) else {
            return response
        }
        
        // Only use compression if it actually reduces size
        guard compressedBody.count < body.count else {
            return response
        }
        
        // Create new response with compressed body and updated headers
        var headers = response.headers
        headers["Content-Encoding"] = algorithm.headerValue
        headers["Content-Length"] = "\(compressedBody.count)"
        headers["Vary"] = appendVaryHeader(existing: headers["Vary"], adding: "Accept-Encoding")
        
        return DICOMwebResponse(
            statusCode: response.statusCode,
            headers: headers,
            body: compressedBody
        )
    }
    
    /// Compresses data using the specified algorithm
    /// - Parameters:
    ///   - data: The data to compress
    ///   - algorithm: The compression algorithm to use
    /// - Returns: The compressed data, or nil if compression failed
    public func compress(data: Data, using algorithm: CompressionAlgorithm) -> Data? {
        #if canImport(Compression)
        switch algorithm {
        case .gzip:
            // Note: Compression framework uses ZLIB internally
            // For proper gzip format, we need to add gzip header/trailer
            return compressGzip(data: data)
        case .deflate:
            break
        }
        
        // For deflate, use the Compression framework directly
        if algorithm == .deflate {
            return compressDeflate(data: data)
        }
        
        return nil
        #else
        // Compression framework not available (e.g., Linux)
        return compressUsingFoundation(data: data, algorithm: algorithm)
        #endif
    }
    
    #if canImport(Compression)
    /// Compresses data using gzip format
    private func compressGzip(data: Data) -> Data? {
        // Use NSData's compressed method with ZLIB, then wrap with gzip header/trailer
        let sourceSize = data.count
        let destinationBufferSize = sourceSize + 1024 // Extra space for headers
        var destinationBuffer = [UInt8](repeating: 0, count: destinationBufferSize)
        
        var sourceBuffer = [UInt8](data)
        
        let compressedSize = compression_encode_buffer(
            &destinationBuffer,
            destinationBufferSize,
            &sourceBuffer,
            sourceSize,
            nil,
            COMPRESSION_ZLIB
        )
        
        guard compressedSize > 0 else {
            return nil
        }
        
        // Build gzip format: header + compressed data + trailer
        var gzipData = Data()
        
        // Gzip header (10 bytes)
        gzipData.append(contentsOf: [
            0x1f, 0x8b,  // Magic number
            0x08,        // Compression method (deflate)
            0x00,        // Flags
            0x00, 0x00, 0x00, 0x00,  // Modification time (not set)
            0x00,        // Extra flags
            0xff         // OS (unknown)
        ])
        
        // Apple's COMPRESSION_ZLIB emits a *raw* DEFLATE stream (RFC 1951) —
        // there is no zlib header/trailer to strip. Append the deflate stream
        // verbatim between the gzip header and trailer. (The previous code
        // stripped a non-existent 2-byte header + 4-byte trailer, corrupting
        // the stream.)
        gzipData.append(contentsOf: destinationBuffer[0..<compressedSize])
        
        // Gzip trailer: CRC32 (4 bytes) + original size (4 bytes)
        let crc = crc32(data: data)
        gzipData.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })
        gzipData.append(contentsOf: withUnsafeBytes(of: UInt32(sourceSize).littleEndian) { Array($0) })
        
        return gzipData
    }
    
    /// Compresses data using deflate (raw zlib)
    private func compressDeflate(data: Data) -> Data? {
        let sourceSize = data.count
        let destinationBufferSize = sourceSize + 1024
        var destinationBuffer = [UInt8](repeating: 0, count: destinationBufferSize)
        
        var sourceBuffer = [UInt8](data)
        
        let compressedSize = compression_encode_buffer(
            &destinationBuffer,
            destinationBufferSize,
            &sourceBuffer,
            sourceSize,
            nil,
            COMPRESSION_ZLIB
        )
        
        guard compressedSize > 0 else {
            return nil
        }
        
        return Data(destinationBuffer[0..<compressedSize])
    }
    
    /// Calculates CRC32 checksum for gzip trailer
    private func crc32(data: Data) -> UInt32 {
        // CRC32 lookup table
        let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
            var crc = UInt32(i)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc = crc >> 1
                }
            }
            return crc
        }
        
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = crcTable[index] ^ (crc >> 8)
        }
        
        return crc ^ 0xFFFFFFFF
    }
    #endif
    
    #if !canImport(Compression)
    /// Fallback compression using Foundation when Compression framework unavailable
    private func compressUsingFoundation(data: Data, algorithm: CompressionAlgorithm) -> Data? {
        // On platforms without Compression framework, try using NSData compression if available
        // This is a best-effort fallback
        return nil
    }
    #endif
    
    /// Appends a value to the Vary header
    private func appendVaryHeader(existing: String?, adding: String) -> String {
        guard let existing = existing, !existing.isEmpty else {
            return adding
        }
        
        // Check if already present
        let parts = existing.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        if parts.contains(adding.lowercased()) {
            return existing
        }
        
        return "\(existing), \(adding)"
    }
}

// MARK: - Decompression Support

extension CompressionMiddleware {
    /// Decompresses data using the specified algorithm
    /// - Parameters:
    ///   - data: The compressed data
    ///   - algorithm: The compression algorithm used
    /// - Returns: The decompressed data, or nil if decompression failed
    public func decompress(data: Data, using algorithm: CompressionAlgorithm) -> Data? {
        #if canImport(Compression)
        switch algorithm {
        case .gzip:
            return decompressGzip(data: data)
        case .deflate:
            return decompressDeflate(data: data)
        }
        #else
        return nil
        #endif
    }
    
    #if canImport(Compression)
    /// Decompresses gzip data
    private func decompressGzip(data: Data) -> Data? {
        guard data.count > 18 else { // Minimum gzip size: 10 header + 8 trailer
            return nil
        }
        
        // Verify gzip magic number
        guard data[0] == 0x1f && data[1] == 0x8b else {
            return nil
        }
        
        // Skip gzip header (minimum 10 bytes, may be more with optional fields)
        var headerSize = 10
        let flags = data[3]
        
        // Check for optional fields
        if flags & 0x04 != 0 { // FEXTRA
            guard data.count > headerSize + 2 else { return nil }
            let extraLen = Int(data[headerSize]) | (Int(data[headerSize + 1]) << 8)
            headerSize += 2 + extraLen
        }
        if flags & 0x08 != 0 { // FNAME
            while headerSize < data.count && data[headerSize] != 0 {
                headerSize += 1
            }
            headerSize += 1 // Skip null terminator
        }
        if flags & 0x10 != 0 { // FCOMMENT
            while headerSize < data.count && data[headerSize] != 0 {
                headerSize += 1
            }
            headerSize += 1 // Skip null terminator
        }
        if flags & 0x02 != 0 { // FHCRC
            headerSize += 2
        }
        
        guard data.count > headerSize + 8 else {
            return nil
        }
        
        // Extract compressed data (between header and trailer)
        let compressedData = data[headerSize..<(data.count - 8)]
        
        // Get expected uncompressed size from trailer (last 4 bytes)
        let expectedSize = Int(data[data.count - 4]) |
                          (Int(data[data.count - 3]) << 8) |
                          (Int(data[data.count - 2]) << 16) |
                          (Int(data[data.count - 1]) << 24)
        
        // The gzip payload is a raw DEFLATE stream. COMPRESSION_ZLIB consumes
        // raw DEFLATE directly — prepending a zlib header (0x78 0x9c) would
        // corrupt the input. Decode the payload as-is.
        return decompressZlib(data: Data(compressedData), expectedSize: expectedSize)
    }
    
    /// Decompresses deflate (zlib) data
    private func decompressDeflate(data: Data) -> Data? {
        // Use 10x compressed size as initial estimate for decompressed size.
        // Typical text/JSON compression achieves 5-10x compression ratios,
        // so 10x provides a reasonable buffer. The decompressZlib function
        // also uses max(expectedSize, compressedSize * 4) as a safety margin.
        return decompressZlib(data: data, expectedSize: data.count * 10)
    }
    
    /// Decompresses a raw DEFLATE stream (RFC 1951) via COMPRESSION_ZLIB.
    ///
    /// `compression_decode_buffer` gives no "destination too small" signal — it
    /// fills the buffer and returns the byte count. A result that exactly fills
    /// the buffer therefore means the output was *probably* truncated, so the
    /// buffer is grown and the decode retried. `expectedSize` is only a starting
    /// hint (exact for gzip via the ISIZE trailer, a guess for bare deflate).
    private func decompressZlib(data: Data, expectedSize: Int) -> Data? {
        let sourceBuffer = [UInt8](data)
        guard !sourceBuffer.isEmpty else { return nil }
        var capacity = max(expectedSize + 1, sourceBuffer.count * 4, 1024)

        for _ in 0..<12 {
            var destinationBuffer = [UInt8](repeating: 0, count: capacity)
            var src = sourceBuffer
            let decompressedSize = compression_decode_buffer(
                &destinationBuffer,
                capacity,
                &src,
                sourceBuffer.count,
                nil,
                COMPRESSION_ZLIB
            )
            guard decompressedSize > 0 else { return nil }
            if decompressedSize < capacity {
                return Data(destinationBuffer[0..<decompressedSize])
            }
            // Buffer filled exactly — output may be truncated; grow and retry.
            capacity *= 4
        }
        return nil
    }
    #endif
}

// MARK: - Request Extension

extension DICOMwebRequest {
    /// Gets the Accept-Encoding header value
    public var acceptEncoding: String? {
        header("Accept-Encoding")
    }
}
