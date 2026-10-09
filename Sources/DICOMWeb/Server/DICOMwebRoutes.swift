import Foundation

/// HTTP request structure for DICOMweb server
public struct DICOMwebRequest: Sendable {
    /// HTTP method
    public let method: HTTPMethod
    
    /// Request path (without query string)
    public let path: String
    
    /// Query parameters
    public let queryParameters: [String: String]
    
    /// HTTP headers
    public let headers: [String: String]
    
    /// Request body
    public let body: Data?
    
    /// Remote client address
    public let remoteAddress: String?
    
    /// Creates a DICOMweb request
    public init(
        method: HTTPMethod,
        path: String,
        queryParameters: [String: String] = [:],
        headers: [String: String] = [:],
        body: Data? = nil,
        remoteAddress: String? = nil
    ) {
        self.method = method
        self.headers = headers
        self.body = body
        self.remoteAddress = remoteAddress
        
        // Parse query parameters from path if present
        if let queryIndex = path.firstIndex(of: "?") {
            self.path = String(path[path.startIndex..<queryIndex])
            var parsedParams = queryParameters
            let queryString = String(path[path.index(after: queryIndex)...])
            for param in queryString.split(separator: "&") {
                let parts = param.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    let key = String(parts[0])
                    let value = String(parts[1])
                    if parsedParams[key] == nil {
                        parsedParams[key] = value
                    }
                }
            }
            self.queryParameters = parsedParams
        } else {
            self.path = path
            self.queryParameters = queryParameters
        }
    }
    
    /// Gets a header value (case-insensitive)
    public func header(_ name: String) -> String? {
        let lowercased = name.lowercased()
        return headers.first { $0.key.lowercased() == lowercased }?.value
    }
    
    /// Gets the Accept header as an array of media types
    public var acceptTypes: [DICOMMediaType] {
        guard let accept = header("Accept") else {
            return []
        }
        return accept.split(separator: ",")
            .compactMap { DICOMMediaType.parse(String($0).trimmingCharacters(in: .whitespaces)) }
    }
    
    /// Gets the Content-Type header
    public var contentType: DICOMMediaType? {
        guard let ct = header("Content-Type") else { return nil }
        return DICOMMediaType.parse(ct)
    }
    
    /// Gets the Accept-Charset header as an array of charset preferences
    ///
    /// Parses the Accept-Charset header and returns an array of charset names with optional quality values.
    /// If no Accept-Charset header is present, defaults to ["utf-8"].
    ///
    /// Example: "iso-8859-5, unicode-1-1;q=0.8, utf-8;q=1.0" returns ["iso-8859-5", "utf-8", "unicode-1-1"]
    ///
    /// Reference: RFC 7231 Section 5.3.3 - Accept-Charset
    public var acceptCharsets: [String] {
        guard let acceptCharset = header("Accept-Charset") else {
            // Default to utf-8 if no Accept-Charset header is present
            return ["utf-8"]
        }
        
        // Parse charset preferences with optional quality values
        var charsets: [(charset: String, quality: Double)] = []
        
        for part in acceptCharset.split(separator: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            let components = trimmed.split(separator: ";")
            
            guard !components.isEmpty else { continue }
            
            let charset = String(components[0]).trimmingCharacters(in: .whitespaces).lowercased()
            var quality = 1.0
            
            // Parse quality value if present (e.g., "q=0.8")
            if components.count > 1 {
                for component in components[1...] {
                    let param = component.trimmingCharacters(in: .whitespaces)
                    if param.hasPrefix("q="), let qValue = Double(param.dropFirst(2)) {
                        quality = qValue
                        break
                    }
                }
            }
            
            charsets.append((charset: charset, quality: quality))
        }
        
        // Sort by quality value (descending) and return charset names
        return charsets
            .sorted { $0.quality > $1.quality }
            .map { $0.charset }
    }
    
    /// Negotiates the best matching charset from available charsets
    ///
    /// - Parameter available: Array of available charset names (e.g., ["utf-8", "iso-8859-1"])
    /// - Returns: The best matching charset, or nil if no match found
    ///
    /// Reference: RFC 7231 Section 5.3.3 - Accept-Charset
    public func negotiateCharset(from available: [String]) -> String? {
        let acceptedCharsets = acceptCharsets
        let availableNormalized = available.map { $0.lowercased() }
        
        // Special case: "*" matches any charset
        if acceptedCharsets.contains("*") {
            return available.first
        }
        
        // Find first accepted charset that's available
        for acceptedCharset in acceptedCharsets {
            if let index = availableNormalized.firstIndex(of: acceptedCharset) {
                return available[index]
            }
        }
        
        return nil
    }
    
    /// Gets the Range header value
    ///
    /// The Range header is used to request partial content from the server.
    ///
    /// Example: "bytes=0-1023" requests bytes 0 through 1023 (inclusive)
    ///
    /// Reference: RFC 7233 Section 3.1 - Range Header
    public var rangeHeader: String? {
        return header("Range")
    }
    
    /// Parses the Range header and returns the requested byte range
    ///
    /// Supports the standard HTTP Range header format: "bytes=start-end"
    ///
    /// - Returns: A tuple with start and end byte positions (inclusive), or nil if no valid range
    ///
    /// Reference: RFC 7233 Section 3.1 - Range Header
    public var byteRange: (start: Int, end: Int)? {
        guard let rangeValue = rangeHeader else { return nil }
        
        // Parse "bytes=start-end" format
        let trimmed = rangeValue.trimmingCharacters(in: .whitespaces)
        
        // Must start with "bytes="
        guard trimmed.hasPrefix("bytes=") else { return nil }
        
        let rangeSpec = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        
        // Find the first hyphen that separates start from end
        // The range spec should be "start-end" or "start-" (open-ended)
        guard let hyphenIndex = rangeSpec.firstIndex(of: "-") else { return nil }
        
        let startStr = String(rangeSpec[rangeSpec.startIndex..<hyphenIndex]).trimmingCharacters(in: .whitespaces)
        let endStr = String(rangeSpec[rangeSpec.index(after: hyphenIndex)...]).trimmingCharacters(in: .whitespaces)
        
        // Parse start position
        guard !startStr.isEmpty, let start = Int(startStr), start >= 0 else {
            return nil
        }
        
        // Parse end position (may be empty for open-ended range)
        if endStr.isEmpty {
            // bytes=100- means from byte 100 to end
            return (start: start, end: Int.max)
        }
        
        guard let end = Int(endStr), end >= start else {
            return nil
        }
        
        return (start: start, end: end)
    }
    
    /// HTTP methods
    public enum HTTPMethod: String, Sendable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
        case options = "OPTIONS"
        case head = "HEAD"
    }
}

/// HTTP response structure for DICOMweb server
public struct DICOMwebResponse: Sendable {
    /// HTTP status code
    public let statusCode: Int
    
    /// HTTP headers
    public var headers: [String: String]
    
    /// Response body
    public let body: Data?
    
    /// Creates a DICOMweb response
    public init(
        statusCode: Int,
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
    
    // MARK: - Factory Methods
    
    /// Creates a 200 OK response with JSON body
    public static func ok(json: Data, headers: [String: String] = [:]) -> DICOMwebResponse {
        var allHeaders = headers
        allHeaders["Content-Type"] = "application/dicom+json"
        allHeaders["Content-Length"] = "\(json.count)"
        return DICOMwebResponse(statusCode: 200, headers: allHeaders, body: json)
    }
    
    /// Creates a 200 OK response with multipart DICOM body
    public static func ok(multipart: Data, boundary: String, headers: [String: String] = [:]) -> DICOMwebResponse {
        var allHeaders = headers
        allHeaders["Content-Type"] = "multipart/related; type=\"application/dicom\"; boundary=\"\(boundary)\""
        allHeaders["Content-Length"] = "\(multipart.count)"
        return DICOMwebResponse(statusCode: 200, headers: allHeaders, body: multipart)
    }
    
    /// Creates a 200 OK response with image body
    public static func ok(image: Data, mediaType: DICOMMediaType, headers: [String: String] = [:]) -> DICOMwebResponse {
        var allHeaders = headers
        allHeaders["Content-Type"] = mediaType.description
        allHeaders["Content-Length"] = "\(image.count)"
        return DICOMwebResponse(statusCode: 200, headers: allHeaders, body: image)
    }
    
    /// Creates a 204 No Content response
    public static func noContent() -> DICOMwebResponse {
        DICOMwebResponse(statusCode: 204)
    }
    
    /// Creates a 304 Not Modified response
    /// - Parameter etag: The ETag of the cached resource
    public static func notModified(etag: String? = nil) -> DICOMwebResponse {
        var headers: [String: String] = [:]
        if let etag = etag {
            headers["ETag"] = etag
        }
        return DICOMwebResponse(statusCode: 304, headers: headers)
    }
    
    /// Creates a 400 Bad Request response
    public static func badRequest(message: String) -> DICOMwebResponse {
        let body = "{\"error\": \"\(message)\"}"
        return DICOMwebResponse(
            statusCode: 400,
            headers: ["Content-Type": "application/json"],
            body: body.data(using: .utf8)
        )
    }
    
    /// Creates a 404 Not Found response
    public static func notFound(message: String = "Resource not found") -> DICOMwebResponse {
        let body = "{\"error\": \"\(message)\"}"
        return DICOMwebResponse(
            statusCode: 404,
            headers: ["Content-Type": "application/json"],
            body: body.data(using: .utf8)
        )
    }
    
    /// Creates a 406 Not Acceptable response for media types
    public static func notAcceptable(supportedTypes: [DICOMMediaType]) -> DICOMwebResponse {
        let types = supportedTypes.map { $0.description }.joined(separator: ", ")
        let body = "{\"error\": \"Not Acceptable\", \"supportedTypes\": \"\(types)\"}"
        return DICOMwebResponse(
            statusCode: 406,
            headers: ["Content-Type": "application/json"],
            body: body.data(using: .utf8)
        )
    }
    
    /// Creates a 406 Not Acceptable response for charsets
    /// - Parameter supportedCharsets: Array of supported charset names
    /// - Returns: A 406 response with supported charsets listed
    ///
    /// Reference: RFC 7231 Section 6.5.6 - 406 Not Acceptable
    public static func notAcceptable(supportedCharsets: [String]) -> DICOMwebResponse {
        let charsets = supportedCharsets.joined(separator: ", ")
        let body = "{\"error\": \"Not Acceptable\", \"supportedCharsets\": \"\(charsets)\"}"
        return DICOMwebResponse(
            statusCode: 406,
            headers: ["Content-Type": "application/json"],
            body: body.data(using: .utf8)
        )
    }
    
    /// Creates a 409 Conflict response
    public static func conflict(message: String) -> DICOMwebResponse {
        let body = "{\"error\": \"\(message)\"}"
        return DICOMwebResponse(
            statusCode: 409,
            headers: ["Content-Type": "application/json"],
            body: body.data(using: .utf8)
        )
    }
    
    /// Creates a 415 Unsupported Media Type response
    public static func unsupportedMediaType() -> DICOMwebResponse {
        let body = "{\"error\": \"Unsupported Media Type\"}"
        return DICOMwebResponse(
            statusCode: 415,
            headers: ["Content-Type": "application/json"],
            body: body.data(using: .utf8)
        )
    }
    
    /// Creates a 416 Range Not Satisfiable response
    /// - Parameter totalLength: Total length of the resource in bytes
    /// - Returns: A 416 response with Content-Range header indicating total size
    ///
    /// Reference: RFC 7233 Section 4.4 - 416 Range Not Satisfiable
    public static func rangeNotSatisfiable(totalLength: Int) -> DICOMwebResponse {
        let body = "{\"error\": \"Range Not Satisfiable\"}"
        var headers: [String: String] = ["Content-Type": "application/json"]
        headers["Content-Range"] = "bytes */\(totalLength)"
        return DICOMwebResponse(
            statusCode: 416,
            headers: headers,
            body: body.data(using: .utf8)
        )
    }
    
    /// Creates a 206 Partial Content response
    /// - Parameters:
    ///   - body: Partial content data
    ///   - range: The byte range being returned (start and end, inclusive)
    ///   - totalLength: Total length of the complete resource
    ///   - contentType: Media type of the content
    /// - Returns: A 206 response with Content-Range header
    ///
    /// Reference: RFC 7233 Section 4.1 - 206 Partial Content
    public static func partialContent(
        body: Data,
        range: (start: Int, end: Int),
        totalLength: Int,
        contentType: String = "application/octet-stream"
    ) -> DICOMwebResponse {
        var headers: [String: String] = [:]
        headers["Content-Type"] = contentType
        headers["Content-Length"] = "\(body.count)"
        headers["Content-Range"] = "bytes \(range.start)-\(range.end)/\(totalLength)"
        headers["Accept-Ranges"] = "bytes"
        
        return DICOMwebResponse(
            statusCode: 206,
            headers: headers,
            body: body
        )
    }
    
    /// Creates a 501 Not Implemented response (PS3.18 Table 8.5-1)
    public static func notImplemented(message: String = "Not implemented") -> DICOMwebResponse {
        let body = "{\"error\": \"\(message)\"}"
        return DICOMwebResponse(
            statusCode: 501,
            headers: ["Content-Type": "application/json"],
            body: body.data(using: .utf8)
        )
    }
    
    /// Creates a 500 Internal Server Error response
    public static func internalError(message: String = "Internal server error") -> DICOMwebResponse {
        let body = "{\"error\": \"\(message)\"}"
        return DICOMwebResponse(
            statusCode: 500,
            headers: ["Content-Type": "application/json"],
            body: body.data(using: .utf8)
        )
    }
    
    /// Creates a 503 Service Unavailable response
    public static func serviceUnavailable() -> DICOMwebResponse {
        let body = "{\"error\": \"Service Unavailable\"}"
        return DICOMwebResponse(
            statusCode: 503,
            headers: ["Content-Type": "application/json"],
            body: body.data(using: .utf8)
        )
    }
}

/// Route matching result with extracted path parameters
public struct RouteMatch: Sendable {
    /// The matched route pattern
    public let pattern: String
    
    /// Extracted path parameters
    public let parameters: [String: String]
    
    /// The matched route handler type
    public let handlerType: RouteHandlerType
    
    public init(pattern: String, parameters: [String: String], handlerType: RouteHandlerType) {
        self.pattern = pattern
        self.parameters = parameters
        self.handlerType = handlerType
    }
}

/// Types of DICOMweb route handlers
public enum RouteHandlerType: Sendable {
    // WADO-RS retrieve endpoints
    case retrieveStudy
    case retrieveSeries
    case retrieveInstance
    case retrieveStudyMetadata
    case retrieveSeriesMetadata
    case retrieveInstanceMetadata
    case retrieveFrames
    case retrieveRendered
    case retrieveThumbnail
    case retrieveBulkData
    
    // QIDO-RS search endpoints
    case searchStudies
    case searchSeries
    case searchSeriesInStudy
    case searchInstances
    case searchInstancesInStudy
    case searchInstancesInSeries
    
    // STOW-RS store endpoints
    case storeInstances
    case storeInstancesInStudy
    
    // Delete endpoints
    case deleteStudy
    case deleteSeries
    case deleteInstance
    
    // UPS-RS endpoints
    case searchWorkitems
    case retrieveWorkitem
    case createWorkitem
    case createWorkitemWithUID
    case updateWorkitem
    case changeWorkitemState
    case requestWorkitemCancellation
    case subscribeWorkitem
    case unsubscribeWorkitem
    case subscribeGlobal
    case unsubscribeGlobal
    case suspendSubscription
    
    // Capabilities
    case capabilities
}

/// Route pattern matcher for DICOMweb URLs
///
/// NEMA-verified: 2026a, checked 2026-09-28 — (method, template) pairs diffed against PS3.18
/// 2026a Tables 10.3-1, 10.4.1-1..4, 10.4.1.5-1, 10.5.1-1, 10.6.1-1, 11.3-1, 11.4.1-1,
/// 11.10.1-1, 11.11.1-1 and 11.12.1-1. Not in PS3.18: DELETE on studies/series/instances,
/// GET /capabilities (8.9 defines OPTIONS / returning a WADL Capabilities Description),
/// PUT as an alias of POST for Update and Request Cancellation, and the per-workitem suspend.
public struct DICOMwebRouter: Sendable {
    
    /// The path prefix for all routes
    private let pathPrefix: String
    
    /// Creates a router with the given path prefix
    public init(pathPrefix: String = "/dicom-web") {
        self.pathPrefix = pathPrefix.hasSuffix("/") ? String(pathPrefix.dropLast()) : pathPrefix
    }
    
    /// Matches a request path and method to a route handler
    /// - Parameters:
    ///   - path: The request path
    ///   - method: The HTTP method
    /// - Returns: A route match if found, nil otherwise
    public func match(path: String, method: DICOMwebRequest.HTTPMethod) -> RouteMatch? {
        return match(path: path, method: method, queryParameters: [:])
    }
    
    /// Matches a request path, method and (already parsed) query parameters to a route handler.
    /// The `workitem` query parameter selects the Create Workitem with a client-specified UID
    /// (PS3.18 Table 11.4.1-1).
    public func match(path: String, method: DICOMwebRequest.HTTPMethod, queryParameters: [String: String]) -> RouteMatch? {
        // Strip query string from path if present
        let pathWithoutQuery: String
        var query = queryParameters
        if let queryIndex = path.firstIndex(of: "?") {
            pathWithoutQuery = String(path[path.startIndex..<queryIndex])
            for pair in path[path.index(after: queryIndex)...].split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    query[String(parts[0])] = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                }
            }
        } else {
            pathWithoutQuery = path
        }
        
        // Remove prefix and normalize path
        guard pathWithoutQuery.hasPrefix(pathPrefix) else {
            return nil
        }
        
        let relativePath = String(pathWithoutQuery.dropFirst(pathPrefix.count))
        let normalizedPath = relativePath.isEmpty ? "/" : relativePath
        
        // Split path into components
        let components = normalizedPath.split(separator: "/").map(String.init)
        
        return matchRoute(components: components, method: method, query: query)
    }
    
    /// Well-known UIDs of the Worklist and Filtered Worklist Subscriptions (PS3.18 Table 11.1.1-1)
    private static let globalSubscriptionUIDs: Set<String> = [
        DICOMwebURLBuilder.globalSubscriptionUID, DICOMwebURLBuilder.filteredGlobalSubscriptionUID
    ]
    
    private func matchRoute(components: [String], method: DICOMwebRequest.HTTPMethod, query: [String: String]) -> RouteMatch? {
        switch (method, components.count) {
        
        // GET / or GET /capabilities - Server capabilities
        case (.get, 0):
            return RouteMatch(pattern: "/", parameters: [:], handlerType: .capabilities)
            
        case (.get, 1) where components[0] == "capabilities":
            return RouteMatch(pattern: "/capabilities", parameters: [:], handlerType: .capabilities)
        
        // GET /studies - Search studies (QIDO-RS)
        case (.get, 1) where components[0] == "studies":
            return RouteMatch(pattern: "/studies", parameters: [:], handlerType: .searchStudies)
            
        // GET /series - Search all series (QIDO-RS)
        case (.get, 1) where components[0] == "series":
            return RouteMatch(pattern: "/series", parameters: [:], handlerType: .searchSeries)
            
        // GET /instances - Search all instances (QIDO-RS)
        case (.get, 1) where components[0] == "instances":
            return RouteMatch(pattern: "/instances", parameters: [:], handlerType: .searchInstances)
            
        // POST /studies - Store instances (STOW-RS)
        case (.post, 1) where components[0] == "studies":
            return RouteMatch(pattern: "/studies", parameters: [:], handlerType: .storeInstances)
            
        // GET /studies/{studyUID} - Retrieve study (WADO-RS)
        case (.get, 2) where components[0] == "studies":
            return RouteMatch(
                pattern: "/studies/{studyUID}",
                parameters: ["studyUID": components[1]],
                handlerType: .retrieveStudy
            )
            
        // DELETE /studies/{studyUID} - Delete study
        case (.delete, 2) where components[0] == "studies":
            return RouteMatch(
                pattern: "/studies/{studyUID}",
                parameters: ["studyUID": components[1]],
                handlerType: .deleteStudy
            )
            
        // POST /studies/{studyUID} - Store instances in study (STOW-RS)
        case (.post, 2) where components[0] == "studies":
            return RouteMatch(
                pattern: "/studies/{studyUID}",
                parameters: ["studyUID": components[1]],
                handlerType: .storeInstancesInStudy
            )
            
        // GET /studies/{studyUID}/metadata - Retrieve study metadata
        case (.get, 3) where components[0] == "studies" && components[2] == "metadata":
            return RouteMatch(
                pattern: "/studies/{studyUID}/metadata",
                parameters: ["studyUID": components[1]],
                handlerType: .retrieveStudyMetadata
            )
            
        // GET /studies/{studyUID}/series - Search series in study
        case (.get, 3) where components[0] == "studies" && components[2] == "series":
            return RouteMatch(
                pattern: "/studies/{studyUID}/series",
                parameters: ["studyUID": components[1]],
                handlerType: .searchSeriesInStudy
            )
            
        // GET /studies/{studyUID}/instances - Search instances in study
        case (.get, 3) where components[0] == "studies" && components[2] == "instances":
            return RouteMatch(
                pattern: "/studies/{studyUID}/instances",
                parameters: ["studyUID": components[1]],
                handlerType: .searchInstancesInStudy
            )
            
        // GET /studies/{studyUID}/series/{seriesUID} - Retrieve series
        case (.get, 4) where components[0] == "studies" && components[2] == "series":
            return RouteMatch(
                pattern: "/studies/{studyUID}/series/{seriesUID}",
                parameters: ["studyUID": components[1], "seriesUID": components[3]],
                handlerType: .retrieveSeries
            )
            
        // DELETE /studies/{studyUID}/series/{seriesUID} - Delete series
        case (.delete, 4) where components[0] == "studies" && components[2] == "series":
            return RouteMatch(
                pattern: "/studies/{studyUID}/series/{seriesUID}",
                parameters: ["studyUID": components[1], "seriesUID": components[3]],
                handlerType: .deleteSeries
            )
            
        // GET /studies/{studyUID}/series/{seriesUID}/metadata - Retrieve series metadata
        case (.get, 5) where components[0] == "studies" && components[2] == "series" && components[4] == "metadata":
            return RouteMatch(
                pattern: "/studies/{studyUID}/series/{seriesUID}/metadata",
                parameters: ["studyUID": components[1], "seriesUID": components[3]],
                handlerType: .retrieveSeriesMetadata
            )
            
        // GET /studies/{studyUID}/series/{seriesUID}/instances - Search instances in series
        case (.get, 5) where components[0] == "studies" && components[2] == "series" && components[4] == "instances":
            return RouteMatch(
                pattern: "/studies/{studyUID}/series/{seriesUID}/instances",
                parameters: ["studyUID": components[1], "seriesUID": components[3]],
                handlerType: .searchInstancesInSeries
            )
            
        // GET /studies/{studyUID}/series/{seriesUID}/rendered - Retrieve series rendered
        case (.get, 5) where components[0] == "studies" && components[2] == "series" && components[4] == "rendered":
            return RouteMatch(
                pattern: "/studies/{studyUID}/series/{seriesUID}/rendered",
                parameters: ["studyUID": components[1], "seriesUID": components[3]],
                handlerType: .retrieveRendered
            )
            
        // GET /studies/{studyUID}/series/{seriesUID}/thumbnail - Retrieve series thumbnail
        case (.get, 5) where components[0] == "studies" && components[2] == "series" && components[4] == "thumbnail":
            return RouteMatch(
                pattern: "/studies/{studyUID}/series/{seriesUID}/thumbnail",
                parameters: ["studyUID": components[1], "seriesUID": components[3]],
                handlerType: .retrieveThumbnail
            )
            
        // GET /studies/{studyUID}/series/{seriesUID}/instances/{instanceUID} - Retrieve instance
        case (.get, 6) where components[0] == "studies" && components[2] == "series" && components[4] == "instances":
            return RouteMatch(
                pattern: "/studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}",
                parameters: ["studyUID": components[1], "seriesUID": components[3], "instanceUID": components[5]],
                handlerType: .retrieveInstance
            )
            
        // DELETE /studies/{studyUID}/series/{seriesUID}/instances/{instanceUID} - Delete instance
        case (.delete, 6) where components[0] == "studies" && components[2] == "series" && components[4] == "instances":
            return RouteMatch(
                pattern: "/studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}",
                parameters: ["studyUID": components[1], "seriesUID": components[3], "instanceUID": components[5]],
                handlerType: .deleteInstance
            )
            
        // GET /studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}/metadata - Instance metadata
        case (.get, 7) where components[0] == "studies" && components[2] == "series" && components[4] == "instances" && components[6] == "metadata":
            return RouteMatch(
                pattern: "/studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}/metadata",
                parameters: ["studyUID": components[1], "seriesUID": components[3], "instanceUID": components[5]],
                handlerType: .retrieveInstanceMetadata
            )
            
        // GET /studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}/rendered - Instance rendered
        case (.get, 7) where components[0] == "studies" && components[2] == "series" && components[4] == "instances" && components[6] == "rendered":
            return RouteMatch(
                pattern: "/studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}/rendered",
                parameters: ["studyUID": components[1], "seriesUID": components[3], "instanceUID": components[5]],
                handlerType: .retrieveRendered
            )
            
        // GET /studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}/thumbnail - Instance thumbnail
        case (.get, 7) where components[0] == "studies" && components[2] == "series" && components[4] == "instances" && components[6] == "thumbnail":
            return RouteMatch(
                pattern: "/studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}/thumbnail",
                parameters: ["studyUID": components[1], "seriesUID": components[3], "instanceUID": components[5]],
                handlerType: .retrieveThumbnail
            )
            
        // GET /studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}/bulkdata - Instance Bulk Data (Table 10.4.1.5-1)
        case (.get, 7) where components[0] == "studies" && components[2] == "series" && components[4] == "instances" && components[6] == "bulkdata":
            return RouteMatch(
                pattern: "/studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}/bulkdata",
                parameters: ["studyUID": components[1], "seriesUID": components[3], "instanceUID": components[5]],
                handlerType: .retrieveBulkData
            )
            
        // GET /studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}/frames/{frames} - Retrieve frames
        case (.get, 8) where components[0] == "studies" && components[2] == "series" && components[4] == "instances" && components[6] == "frames":
            return RouteMatch(
                pattern: "/studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}/frames/{frames}",
                parameters: [
                    "studyUID": components[1],
                    "seriesUID": components[3],
                    "instanceUID": components[5],
                    "frames": components[7]
                ],
                handlerType: .retrieveFrames
            )
            
        // GET /studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}/frames/{frames}/rendered
        case (.get, 9) where components[0] == "studies" && components[2] == "series" && components[4] == "instances" && components[6] == "frames" && components[8] == "rendered":
            return RouteMatch(
                pattern: "/studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}/frames/{frames}/rendered",
                parameters: [
                    "studyUID": components[1],
                    "seriesUID": components[3],
                    "instanceUID": components[5],
                    "frames": components[7]
                ],
                handlerType: .retrieveRendered
            )
            
        // ============ UPS-RS Endpoints ============
        
        // GET /workitems - Search workitems (UPS-RS)
        case (.get, 1) where components[0] == "workitems":
            return RouteMatch(pattern: "/workitems", parameters: [:], handlerType: .searchWorkitems)
            
        // POST /workitems?workitem={uid} - Create workitem with a client-specified UID (PS3.18 Table 11.4.1-1)
        case (.post, 1) where components[0] == "workitems" && query["workitem"] != nil:
            return RouteMatch(
                pattern: "/workitems?workitem={workitemUID}",
                parameters: ["workitemUID": query["workitem"]!],
                handlerType: .createWorkitemWithUID
            )
            
        // POST /workitems - Create workitem (UPS-RS)
        case (.post, 1) where components[0] == "workitems":
            return RouteMatch(pattern: "/workitems", parameters: [:], handlerType: .createWorkitem)
            
        // GET /workitems/{workitemUID} - Retrieve workitem (UPS-RS)
        case (.get, 2) where components[0] == "workitems":
            return RouteMatch(
                pattern: "/workitems/{workitemUID}",
                parameters: ["workitemUID": components[1]],
                handlerType: .retrieveWorkitem
            )
            
        // POST /workitems/{workitemUID} - Update workitem (PS3.18 11.6.1); PUT is tolerated as an alias
        case (.post, 2) where components[0] == "workitems",
             (.put, 2) where components[0] == "workitems":
            return RouteMatch(
                pattern: "/workitems/{workitemUID}",
                parameters: ["workitemUID": components[1]],
                handlerType: .updateWorkitem
            )
            
        // PUT /workitems/{workitemUID}/state - Change workitem state (UPS-RS)
        case (.put, 3) where components[0] == "workitems" && components[2] == "state":
            return RouteMatch(
                pattern: "/workitems/{workitemUID}/state",
                parameters: ["workitemUID": components[1]],
                handlerType: .changeWorkitemState
            )
            
        // POST /workitems/{workitemUID}/cancelrequest - Request cancellation (PS3.18 11.8.1); PUT tolerated
        case (.post, 3) where components[0] == "workitems" && components[2] == "cancelrequest",
             (.put, 3) where components[0] == "workitems" && components[2] == "cancelrequest":
            return RouteMatch(
                pattern: "/workitems/{workitemUID}/cancelrequest",
                parameters: ["workitemUID": components[1]],
                handlerType: .requestWorkitemCancellation
            )
            
        // POST /workitems/{workitemUID}/subscribers/{aeTitle} - Subscribe (PS3.18 Table 11.10.1-1);
        // the well-known UIDs 1.2.840.10008.5.1.4.34.5 and .5.1 address the Worklist Subscription
        case (.post, 4) where components[0] == "workitems" && components[2] == "subscribers":
            return RouteMatch(
                pattern: "/workitems/{workitemUID}/subscribers/{aeTitle}",
                parameters: ["workitemUID": components[1], "aeTitle": components[3]],
                handlerType: Self.globalSubscriptionUIDs.contains(components[1]) ? .subscribeGlobal : .subscribeWorkitem
            )
            
        // DELETE /workitems/{workitemUID}/subscribers/{aeTitle} - Unsubscribe (PS3.18 Table 11.11.1-1)
        case (.delete, 4) where components[0] == "workitems" && components[2] == "subscribers":
            return RouteMatch(
                pattern: "/workitems/{workitemUID}/subscribers/{aeTitle}",
                parameters: ["workitemUID": components[1], "aeTitle": components[3]],
                handlerType: Self.globalSubscriptionUIDs.contains(components[1]) ? .unsubscribeGlobal : .unsubscribeWorkitem
            )
            
        // POST /workitems/{workitemUID}/subscribers/{aeTitle}/suspend - Suspend subscription
        case (.post, 5) where components[0] == "workitems" && components[2] == "subscribers" && components[4] == "suspend":
            return RouteMatch(
                pattern: "/workitems/{workitemUID}/subscribers/{aeTitle}/suspend",
                parameters: ["workitemUID": components[1], "aeTitle": components[3]],
                handlerType: .suspendSubscription
            )
            
        default:
            return nil
        }
    }
}
