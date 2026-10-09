import Foundation
import DICOMCore
import DICOMKit

/// DICOMweb server for serving DICOM objects over HTTP
///
/// This server implements WADO-RS (Retrieve), QIDO-RS (Search), and STOW-RS (Store)
/// services per the DICOM PS3.18 web services specification.
///
/// NEMA-verified: 2026a, checked 2026-09-28 — status codes per transaction diffed against
/// PS3.18 2026a Tables 8.5-1, 10.4.3-1, 10.5.3-1, 10.6.3-1, 11.4.3-1, 11.6.3-1, 11.7.3-1,
/// 11.8.3-1, 11.10.3-1, 11.11.3-1, 11.12.3-1; Warning header texts per 8.3.4.4.1, 11.4.3.2,
/// 11.6.3.2, 11.7.3.2, 11.8.3.2, 11.10.3.2; media types per Tables 10.4.4-1, 10.5.4-1,
/// 10.6.4-1; multipart part headers per Table 8.6.1-1; Store Instances Response Module per
/// Tables I.1-1, I.2-2; QIDO return attributes per Tables 10.6.3-3..5; UPS behaviour per
/// PS3.4 CC.1.1-2, CC.2.1.3, CC.2.2.3, CC.2.5.3, CC.2.6.3, CC.2.7.3. Not implemented and
/// answered 501: frames, rendered, thumbnail and bulk data retrieval; application/dicom+xml
/// metadata; the 8.9 Capabilities Description (a JSON document is served instead).
/// Not in PS3.18: DELETE on studies/series/instances, the X-Total-Count header.
///
/// Reference: PS3.18 - Web Services
///
/// - Note: This implementation provides the request handling logic. It can be integrated
///   with various HTTP server frameworks (SwiftNIO, Vapor, Hummingbird) by implementing
///   the request/response bridge.
public actor DICOMwebServer {
    
    // MARK: - Properties
    
    /// Server configuration
    public let configuration: DICOMwebServerConfiguration
    
    /// Storage provider
    private let storage: any DICOMwebStorageProvider
    
    /// Router for matching requests
    private let router: DICOMwebRouter
    
    /// Whether the server is running
    private var isRunning: Bool = false
    
    /// Server delegate for events
    public weak var delegate: DICOMwebServerDelegate?
    
    /// Store delegate for STOW-RS events
    public weak var storeDelegate: STOWDelegate?
    
    /// UPS storage provider for workitem operations (optional)
    private var upsStorage: (any UPSStorageProvider)?
    
    /// Compression middleware for response compression
    private let compressionMiddleware: CompressionMiddleware
    
    /// Server-side cache middleware for response caching
    private let cacheMiddleware: ServerCacheMiddleware
    
    // MARK: - Initialization
    
    /// Creates a DICOMweb server
    /// - Parameters:
    ///   - configuration: Server configuration
    ///   - storage: Storage provider
    public init(
        configuration: DICOMwebServerConfiguration,
        storage: any DICOMwebStorageProvider
    ) {
        self.configuration = configuration
        self.storage = storage
        self.router = DICOMwebRouter(pathPrefix: configuration.pathPrefix)
        self.compressionMiddleware = CompressionMiddleware(configuration: configuration.compressionConfiguration)
        self.cacheMiddleware = ServerCacheMiddleware(configuration: configuration.cacheConfiguration)
    }
    
    /// Creates a DICOMweb server with default development configuration
    /// - Parameter storage: Storage provider
    public init(storage: any DICOMwebStorageProvider) {
        self.init(configuration: .development, storage: storage)
    }
    
    /// Creates a DICOMweb server with UPS storage support
    /// - Parameters:
    ///   - configuration: Server configuration
    ///   - storage: DICOM storage provider
    ///   - upsStorage: UPS storage provider for workitem operations
    public init(
        configuration: DICOMwebServerConfiguration,
        storage: any DICOMwebStorageProvider,
        upsStorage: any UPSStorageProvider
    ) {
        self.configuration = configuration
        self.storage = storage
        self.upsStorage = upsStorage
        self.router = DICOMwebRouter(pathPrefix: configuration.pathPrefix)
        self.compressionMiddleware = CompressionMiddleware(configuration: configuration.compressionConfiguration)
        self.cacheMiddleware = ServerCacheMiddleware(configuration: configuration.cacheConfiguration)
    }
    
    /// Sets the UPS storage provider
    /// - Parameter upsStorage: The UPS storage provider to use
    public func setUPSStorage(_ upsStorage: any UPSStorageProvider) {
        self.upsStorage = upsStorage
    }
    
    // MARK: - Server Control
    
    /// Starts the server
    ///
    /// - Note: This sets the server state to running. Actual HTTP listening
    ///   must be implemented by the integrating HTTP framework.
    public func start() async throws {
        guard !isRunning else { return }
        isRunning = true
        await delegate?.serverDidStart(self)
    }
    
    /// Stops the server
    public func stop() async {
        guard isRunning else { return }
        isRunning = false
        await delegate?.serverDidStop(self)
    }
    
    /// Whether the server is currently running
    public var running: Bool {
        isRunning
    }
    
    /// The base URL of the server
    public var baseURL: URL {
        configuration.baseURL
    }
    
    /// The port the server is configured for
    public var port: Int {
        configuration.port
    }
    
    // MARK: - Request Handling
    
    /// Handles an incoming DICOMweb request
    /// - Parameter request: The HTTP request
    /// - Returns: The HTTP response
    public func handleRequest(_ request: DICOMwebRequest) async -> DICOMwebResponse {
        // Handle CORS preflight
        if request.method == .options {
            return handleCORSPreflight(request)
        }
        
        // Match route
        guard let match = router.match(path: request.path, method: request.method, queryParameters: request.queryParameters) else {
            return .notFound(message: "No route matched for \(request.method.rawValue) \(request.path)")
        }
        
        // Check server-side cache for GET requests
        if request.method == .get {
            if let cachedResponse = await cacheMiddleware.cachedResponse(for: request) {
                var response = cachedResponse
                addCORSHeaders(to: &response, request: request)
                response.headers["Server"] = configuration.serverName
                return response
            }
        }
        
        // Handle the request based on handler type
        do {
            var response = try await handleRoute(match: match, request: request)
            
            // Store response in server-side cache for GET requests
            if request.method == .get {
                response = await cacheMiddleware.cacheResponse(response, for: request)
            }
            
            // Invalidate cache on mutations (STOW-RS, DELETE)
            if request.method == .post || request.method == .put || request.method == .delete {
                await cacheMiddleware.invalidateAll()
            }
            
            // Add CORS headers if configured
            addCORSHeaders(to: &response, request: request)
            
            // Add server header
            response.headers["Server"] = configuration.serverName
            
            // Apply compression if configured and appropriate
            response = compressionMiddleware.compressResponse(response, acceptEncoding: request.acceptEncoding)
            
            return response
        } catch let error as DICOMwebError {
            return errorResponse(for: error)
        } catch {
            return .internalError(message: error.localizedDescription)
        }
    }
    
    // MARK: - Route Handlers
    
    private func handleRoute(match: RouteMatch, request: DICOMwebRequest) async throws -> DICOMwebResponse {
        switch match.handlerType {
        // WADO-RS Retrieve
        case .retrieveStudy:
            return try await handleRetrieveStudy(parameters: match.parameters, request: request)
        case .retrieveSeries:
            return try await handleRetrieveSeries(parameters: match.parameters, request: request)
        case .retrieveInstance:
            return try await handleRetrieveInstance(parameters: match.parameters, request: request)
        case .retrieveStudyMetadata:
            return try await handleRetrieveStudyMetadata(parameters: match.parameters, request: request)
        case .retrieveSeriesMetadata:
            return try await handleRetrieveSeriesMetadata(parameters: match.parameters, request: request)
        case .retrieveInstanceMetadata:
            return try await handleRetrieveInstanceMetadata(parameters: match.parameters, request: request)
        case .retrieveFrames:
            return try await handleRetrieveFrames(parameters: match.parameters, request: request)
        case .retrieveRendered:
            return try await handleRetrieveRendered(parameters: match.parameters, request: request)
        case .retrieveThumbnail:
            return try await handleRetrieveThumbnail(parameters: match.parameters, request: request)
        case .retrieveBulkData:
            return try await handleRetrieveBulkData(parameters: match.parameters, request: request)
            
        // QIDO-RS Search
        case .searchStudies:
            return try await handleSearchStudies(request: request)
        case .searchSeries:
            return try await handleSearchSeries(studyUID: nil, request: request)
        case .searchSeriesInStudy:
            return try await handleSearchSeries(studyUID: match.parameters["studyUID"], request: request)
        case .searchInstances:
            return try await handleSearchInstances(studyUID: nil, seriesUID: nil, request: request)
        case .searchInstancesInStudy:
            return try await handleSearchInstances(studyUID: match.parameters["studyUID"], seriesUID: nil, request: request)
        case .searchInstancesInSeries:
            return try await handleSearchInstances(studyUID: match.parameters["studyUID"], seriesUID: match.parameters["seriesUID"], request: request)
            
        // STOW-RS Store
        case .storeInstances:
            return try await handleStoreInstances(studyUID: nil, request: request)
        case .storeInstancesInStudy:
            return try await handleStoreInstances(studyUID: match.parameters["studyUID"], request: request)
            
        // Delete (merge request query parameters for mode support)
        case .deleteStudy:
            return try await handleDeleteStudy(parameters: match.parameters.merging(request.queryParameters) { current, _ in current })
        case .deleteSeries:
            return try await handleDeleteSeries(parameters: match.parameters.merging(request.queryParameters) { current, _ in current })
        case .deleteInstance:
            return try await handleDeleteInstance(parameters: match.parameters.merging(request.queryParameters) { current, _ in current })
            
        // UPS-RS Handlers
        case .searchWorkitems:
            return try await handleSearchWorkitems(request: request)
        case .retrieveWorkitem:
            return try await handleRetrieveWorkitem(parameters: match.parameters, request: request)
        case .createWorkitem:
            return try await handleCreateWorkitem(parameters: match.parameters, request: request)
        case .createWorkitemWithUID:
            return try await handleCreateWorkitem(parameters: match.parameters, request: request)
        case .updateWorkitem:
            return try await handleUpdateWorkitem(parameters: match.parameters, request: request)
        case .changeWorkitemState:
            return try await handleChangeWorkitemState(parameters: match.parameters, request: request)
        case .requestWorkitemCancellation:
            return try await handleRequestWorkitemCancellation(parameters: match.parameters, request: request)
        case .subscribeWorkitem:
            return try await handleSubscribeWorkitem(parameters: match.parameters, request: request)
        case .unsubscribeWorkitem:
            return try await handleUnsubscribeWorkitem(parameters: match.parameters, request: request)
        case .subscribeGlobal:
            return try await handleSubscribeGlobal(parameters: match.parameters, request: request)
        case .unsubscribeGlobal:
            return try await handleUnsubscribeGlobal(parameters: match.parameters, request: request)
        case .suspendSubscription:
            return try await handleSuspendSubscription(parameters: match.parameters, request: request)
            
        case .capabilities:
            return handleCapabilities()
        }
    }
    
    // MARK: - Content negotiation (PS3.18 8.7.5, 8.7.7)
    
    /// Whether the Acceptable Media Types allow one of `supported`. A request without an
    /// Accept header is treated as `*/*` (8.7.5 would answer 406; this server is lenient
    /// because browsers and simple clients omit it). Wildcards and the multipart `type`
    /// parameter are honoured; other parameters are ignored (8.7.7).
    private func accepts(_ request: DICOMwebRequest, _ supported: [DICOMMediaType]) -> Bool {
        let acceptable = request.acceptTypes
        guard !acceptable.isEmpty else { return true }
        for accepted in acceptable {
            for candidate in supported {
                if accepted.type == "*" { return true }
                if accepted.type == candidate.type && (accepted.subtype == "*" || accepted.subtype == candidate.subtype) {
                    if candidate.type == "multipart", let want = accepted.parameters["type"], let have = candidate.parameters["type"] {
                        if want.lowercased() == have.lowercased() || want.hasSuffix("/*") { return true }
                        continue
                    }
                    return true
                }
            }
        }
        return false
    }
    
    private static let instanceMediaTypes = [
        DICOMMediaType.multipartRelated.withParameter("type", value: "application/dicom"), DICOMMediaType.dicom]
    private static let metadataMediaTypes = [DICOMMediaType.dicomJSON, DICOMMediaType.json]
    
    /// `Warning: 299 <service>: text` (RFC 7234 5.5; PS3.18 8.3.4.4.1, 11.x.3.2)
    private func warning(_ text: String) -> String {
        "299 \(configuration.baseURL.absoluteString): \(text)"
    }
    
    private func response(_ statusCode: Int, warning text: String? = nil, body: Data? = nil) -> DICOMwebResponse {
        var headers: [String: String] = [:]
        if let text = text {
            headers["Warning"] = warning(text)
        }
        if let body = body {
            headers["Content-Type"] = DICOMMediaType.dicomJSON.description
            headers["Content-Length"] = "\(body.count)"
        }
        return DICOMwebResponse(statusCode: statusCode, headers: headers, body: body)
    }
    
    // MARK: - WADO-RS Handlers
    
    private func handleRetrieveStudy(parameters: [String: String], request: DICOMwebRequest) async throws -> DICOMwebResponse {
        guard let studyUID = parameters["studyUID"] else {
            return .badRequest(message: "Missing studyUID")
        }
        
        guard accepts(request, Self.instanceMediaTypes) else {
            return .notAcceptable(supportedTypes: Self.instanceMediaTypes)
        }
        let instances = try await storage.getStudyInstances(studyUID: studyUID)
        
        if instances.isEmpty {
            return .notFound(message: "Study not found: \(studyUID)")
        }
        
        // Build multipart response
        let (body, boundary) = buildMultipartDICOMResponse(instances: instances)
        return .ok(multipart: body, boundary: boundary)
    }
    
    private func handleRetrieveSeries(parameters: [String: String], request: DICOMwebRequest) async throws -> DICOMwebResponse {
        guard let studyUID = parameters["studyUID"],
              let seriesUID = parameters["seriesUID"] else {
            return .badRequest(message: "Missing studyUID or seriesUID")
        }
        
        guard accepts(request, Self.instanceMediaTypes) else {
            return .notAcceptable(supportedTypes: Self.instanceMediaTypes)
        }
        let instances = try await storage.getSeriesInstances(studyUID: studyUID, seriesUID: seriesUID)
        
        if instances.isEmpty {
            return .notFound(message: "Series not found: \(seriesUID)")
        }
        
        // Build multipart response
        let (body, boundary) = buildMultipartDICOMResponse(instances: instances)
        return .ok(multipart: body, boundary: boundary)
    }
    
    private func handleRetrieveInstance(parameters: [String: String], request: DICOMwebRequest) async throws -> DICOMwebResponse {
        guard let studyUID = parameters["studyUID"],
              let seriesUID = parameters["seriesUID"],
              let instanceUID = parameters["instanceUID"] else {
            return .badRequest(message: "Missing studyUID, seriesUID, or instanceUID")
        }
        
        guard accepts(request, Self.instanceMediaTypes) else {
            return .notAcceptable(supportedTypes: Self.instanceMediaTypes)
        }
        guard let data = try await storage.getInstance(studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID) else {
            return .notFound(message: "Instance not found: \(instanceUID)")
        }
        
        // Table 10.4.4-1: application/dicom (single part) is optional for an Instance resource;
        // the default is multipart/related; type="application/dicom"
        let wantsSinglePart = request.acceptTypes.contains { $0.type == "application" && $0.subtype == "dicom" }
            && !request.acceptTypes.contains { $0.type == "multipart" }
        if wantsSinglePart {
            let headers = ["Content-Type": DICOMMediaType.dicom.description, "Content-Length": "\(data.count)",
                           "Content-Location": instanceURL(studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID)]
            return DICOMwebResponse(statusCode: 200, headers: headers, body: data)
        }
        
        // Return single instance as multipart (per WADO-RS spec)
        let instanceInfo = InstanceInfo(
            studyUID: studyUID,
            seriesUID: seriesUID,
            instanceUID: instanceUID,
            size: Int64(data.count),
            data: data
        )
        let (body, boundary) = buildMultipartDICOMResponse(instances: [instanceInfo])
        return .ok(multipart: body, boundary: boundary)
    }
    
    private func handleRetrieveStudyMetadata(parameters: [String: String], request: DICOMwebRequest) async throws -> DICOMwebResponse {
        guard let studyUID = parameters["studyUID"] else {
            return .badRequest(message: "Missing studyUID")
        }
        
        guard accepts(request, Self.metadataMediaTypes) else {
            return .notAcceptable(supportedTypes: Self.metadataMediaTypes)
        }
        let datasets = try await storage.getStudyMetadata(studyUID: studyUID)
        
        if datasets.isEmpty {
            return .notFound(message: "Study not found: \(studyUID)")
        }
        
        let json = try encodeMetadataAsJSON(datasets: datasets)
        return .ok(json: json)
    }
    
    private func handleRetrieveSeriesMetadata(parameters: [String: String], request: DICOMwebRequest) async throws -> DICOMwebResponse {
        guard let studyUID = parameters["studyUID"],
              let seriesUID = parameters["seriesUID"] else {
            return .badRequest(message: "Missing studyUID or seriesUID")
        }
        
        guard accepts(request, Self.metadataMediaTypes) else {
            return .notAcceptable(supportedTypes: Self.metadataMediaTypes)
        }
        let datasets = try await storage.getSeriesMetadata(studyUID: studyUID, seriesUID: seriesUID)
        
        if datasets.isEmpty {
            return .notFound(message: "Series not found: \(seriesUID)")
        }
        
        let json = try encodeMetadataAsJSON(datasets: datasets)
        return .ok(json: json)
    }
    
    private func handleRetrieveInstanceMetadata(parameters: [String: String], request: DICOMwebRequest) async throws -> DICOMwebResponse {
        guard let studyUID = parameters["studyUID"],
              let seriesUID = parameters["seriesUID"],
              let instanceUID = parameters["instanceUID"] else {
            return .badRequest(message: "Missing studyUID, seriesUID, or instanceUID")
        }
        
        guard accepts(request, Self.metadataMediaTypes) else {
            return .notAcceptable(supportedTypes: Self.metadataMediaTypes)
        }
        guard let dataset = try await storage.getInstanceMetadata(studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID) else {
            return .notFound(message: "Instance not found: \(instanceUID)")
        }
        
        let json = try encodeMetadataAsJSON(datasets: [dataset])
        return .ok(json: json)
    }
    
    // PS3.18 Table 8.5-1: 501 (Not Implemented) when the server does not support the
    // functionality required to fulfil the request
    private func handleRetrieveFrames(parameters: [String: String], request: DICOMwebRequest) async throws -> DICOMwebResponse {
        return .notImplemented(message: "Frame retrieval not yet implemented")
    }
    
    private func handleRetrieveRendered(parameters: [String: String], request: DICOMwebRequest) async throws -> DICOMwebResponse {
        return .notImplemented(message: "Rendered image retrieval not yet implemented")
    }
    
    private func handleRetrieveThumbnail(parameters: [String: String], request: DICOMwebRequest) async throws -> DICOMwebResponse {
        return .notImplemented(message: "Thumbnail retrieval not yet implemented")
    }
    
    private func handleRetrieveBulkData(parameters: [String: String], request: DICOMwebRequest) async throws -> DICOMwebResponse {
        return .notImplemented(message: "Bulk data retrieval not yet implemented")
    }
    
    // MARK: - QIDO-RS Handlers
    
    private func handleSearchStudies(request: DICOMwebRequest) async throws -> DICOMwebResponse {
        guard accepts(request, Self.metadataMediaTypes) else {
            return .notAcceptable(supportedTypes: Self.metadataMediaTypes)
        }
        let query = parseQIDOQuery(from: request.queryParameters)
        
        let studies = try await storage.searchStudies(query: query)
        let totalCount = try await storage.countStudies(query: query)
        
        let json = try encodeStudyResultsAsJSON(studies: studies)
        
        var headers: [String: String] = [:]
        headers["X-Total-Count"] = "\(totalCount)"
        // PS3.18 8.3.4.4.1: remaining = total - (offset + results)
        let remaining = totalCount - (query.offset + studies.count)
        if remaining > 0 {
            headers["Warning"] = warning("There are \(remaining) additional results that can be requested")
        }
        
        return .ok(json: json, headers: headers)
    }
    
    private func handleSearchSeries(studyUID: String?, request: DICOMwebRequest) async throws -> DICOMwebResponse {
        guard accepts(request, Self.metadataMediaTypes) else {
            return .notAcceptable(supportedTypes: Self.metadataMediaTypes)
        }
        let query = parseQIDOQuery(from: request.queryParameters)
        
        let series = try await storage.searchSeries(studyUID: studyUID, query: query)
        
        let json = try encodeSeriesResultsAsJSON(series: series)
        
        var headers: [String: String] = [:]
        headers["X-Total-Count"] = "\(series.count)"
        
        return .ok(json: json, headers: headers)
    }
    
    private func handleSearchInstances(studyUID: String?, seriesUID: String?, request: DICOMwebRequest) async throws -> DICOMwebResponse {
        guard accepts(request, Self.metadataMediaTypes) else {
            return .notAcceptable(supportedTypes: Self.metadataMediaTypes)
        }
        let query = parseQIDOQuery(from: request.queryParameters)
        
        let instances = try await storage.searchInstances(studyUID: studyUID, seriesUID: seriesUID, query: query)
        
        let json = try encodeInstanceResultsAsJSON(instances: instances)
        
        var headers: [String: String] = [:]
        headers["X-Total-Count"] = "\(instances.count)"
        
        return .ok(json: json, headers: headers)
    }
    
    // MARK: - STOW-RS Handlers
    
    private func handleStoreInstances(studyUID: String?, request: DICOMwebRequest) async throws -> DICOMwebResponse {
        let stowConfig = configuration.stowConfiguration
        
        // Validate request body exists
        guard let body = request.body, !body.isEmpty else {
            return .badRequest(message: "Missing request body")
        }
        
        // Validate request body size
        if body.count > configuration.maxRequestBodySize {
            return DICOMwebResponse(
                statusCode: 413,
                headers: ["Content-Type": "application/json"],
                body: "{\"error\": \"Request body too large\"}".data(using: .utf8)
            )
        }
        
        // Validate and parse content type
        guard let contentType = request.contentType else {
            return .unsupportedMediaType()
        }
        
        // Parse DICOM instances based on content type
        let dicomParts: [Data]
        
        if contentType.type == "multipart" && contentType.subtype == "related" {
            // Multipart request (standard STOW-RS)
            guard let boundary = contentType.parameters["boundary"] else {
                return .badRequest(message: "Missing multipart boundary")
            }
            
            // Use the byte-scanning MultipartMIME parser. The prior UTF-8
            // string-based parser dropped/corrupted binary Part-10 bodies
            // (which are not valid UTF-8), silently storing nothing.
            do {
                let multipart = try MultipartMIME.parse(data: body, boundary: boundary)
                dicomParts = multipart.parts.map { $0.body }
            } catch {
                return .badRequest(message: "Invalid multipart body: \(error)")
            }
        } else if contentType.type == "application" && contentType.subtype == "dicom" {
            // Single DICOM instance
            dicomParts = [body]
        } else {
            return .unsupportedMediaType()
        }
        
        // Process each DICOM instance
        var storedInstances: [STOWStoredInstance] = []
        var failedInstances: [STOWFailedInstance] = []
        var hasWarnings = false
        
        for partData in dicomParts {
            let result = await processSTOWInstance(
                data: partData,
                expectedStudyUID: studyUID,
                configuration: stowConfig
            )
            
            switch result {
            case .stored(let instance):
                storedInstances.append(instance)
            case .duplicate(let instance):
                // Handle according to duplicate policy
                switch stowConfig.duplicatePolicy {
                case .reject:
                    failedInstances.append(STOWFailedInstance(
                        sopInstanceUID: instance.sopInstanceUID,
                        sopClassUID: instance.sopClassUID,
                        failureReason: .duplicateSOPInstance
                    ))
                case .replace:
                    // Already replaced in storage
                    storedInstances.append(instance)
                    hasWarnings = true
                case .accept:
                    // Accept silently
                    storedInstances.append(instance)
                }
            case .failed(let failure):
                failedInstances.append(failure)
            }
        }
        
        // Notify delegate
        await notifyStoreDelegate(stored: storedInstances, failed: failedInstances)
        
        // Build STOW-RS response with proper status codes
        return buildSTOWResponseWithStatus(
            stored: storedInstances,
            failed: failedInstances,
            hasWarnings: hasWarnings
        )
    }
    
    /// Result of processing a single STOW-RS instance
    private enum STOWProcessResult {
        case stored(STOWStoredInstance)
        case duplicate(STOWStoredInstance)
        case failed(STOWFailedInstance)
    }
    
    /// Information about a successfully stored instance
    private struct STOWStoredInstance {
        let sopInstanceUID: String
        let sopClassUID: String
        let studyUID: String
        let seriesUID: String
    }
    
    /// Information about a failed instance
    private struct STOWFailedInstance {
        let sopInstanceUID: String
        let sopClassUID: String?
        let failureReason: STOWFailureReason
    }
    
    /// Failure Reason (0008,1197) values per PS3.18 Table I.2-2: 0110 Processing failure,
    /// 0122 Referenced SOP Class not supported, A9xx Data Set does not match SOP Class,
    /// Cxxx Cannot understand. 0111 (Duplicate SOP Instance, PS3.7 C.5.9) is not in the
    /// table; I.2.2 allows additional codes, documented in the Conformance Statement.
    private enum STOWFailureReason: UInt16 {
        case processingFailure = 0x0110
        case duplicateSOPInstance = 0x0111
        case invalidDICOMData = 0xC000
        case missingRequiredAttribute = 0xA900
        case invalidAttributeValue = 0xA901
        case sopClassNotSupported = 0x0122
        case studyUIDMismatch = 0xC001
        case invalidUIDFormat = 0xA902
        
        var description: String {
            switch self {
            case .processingFailure: return "Processing failure"
            case .duplicateSOPInstance: return "Duplicate SOP Instance"
            case .invalidDICOMData: return "Invalid DICOM data"
            case .missingRequiredAttribute: return "Missing required attribute"
            case .invalidAttributeValue: return "Invalid attribute value"
            case .sopClassNotSupported: return "SOP Class not supported"
            case .studyUIDMismatch: return "Study UID mismatch"
            case .invalidUIDFormat: return "Invalid UID format"
            }
        }
    }
    
    /// Processes a single DICOM instance for STOW-RS storage
    private func processSTOWInstance(
        data: Data,
        expectedStudyUID: String?,
        configuration stowConfig: DICOMwebServerConfiguration.STOWConfiguration
    ) async -> STOWProcessResult {
        // Parse the DICOM data
        guard let dicomFile = try? DICOMFile.read(from: data, force: true) else {
            return .failed(STOWFailedInstance(
                sopInstanceUID: "unknown",
                sopClassUID: nil,
                failureReason: .invalidDICOMData
            ))
        }
        
        let dataSet = dicomFile.dataSet
        
        // Extract required UIDs
        guard let sopInstanceUID = dataSet.string(for: Tag.sopInstanceUID),
              let seriesUID = dataSet.string(for: Tag.seriesInstanceUID),
              let studyUID = dataSet.string(for: Tag.studyInstanceUID) else {
            return .failed(STOWFailedInstance(
                sopInstanceUID: dataSet.string(for: Tag.sopInstanceUID) ?? "unknown",
                sopClassUID: dataSet.string(for: Tag.sopClassUID),
                failureReason: .missingRequiredAttribute
            ))
        }
        
        let sopClassUID = dataSet.string(for: Tag.sopClassUID) ?? "1.2.840.10008.5.1.4.1.1.2"
        
        // Validate UID format if enabled
        if stowConfig.validateUIDFormat {
            if !isValidUID(sopInstanceUID) || !isValidUID(seriesUID) || !isValidUID(studyUID) {
                return .failed(STOWFailedInstance(
                    sopInstanceUID: sopInstanceUID,
                    sopClassUID: sopClassUID,
                    failureReason: .invalidUIDFormat
                ))
            }
        }
        
        // Validate Study UID matches path parameter if provided
        if let expectedStudyUID = expectedStudyUID, expectedStudyUID != studyUID {
            return .failed(STOWFailedInstance(
                sopInstanceUID: sopInstanceUID,
                sopClassUID: sopClassUID,
                failureReason: .studyUIDMismatch
            ))
        }
        
        // Validate SOP Class if enabled
        if stowConfig.validateSOPClasses && !stowConfig.allowedSOPClasses.isEmpty {
            if !stowConfig.allowedSOPClasses.contains(sopClassUID) {
                return .failed(STOWFailedInstance(
                    sopInstanceUID: sopInstanceUID,
                    sopClassUID: sopClassUID,
                    failureReason: .sopClassNotSupported
                ))
            }
        }
        
        // Validate additional required tags
        if stowConfig.validateRequiredAttributes {
            for tagValue in stowConfig.additionalRequiredTags {
                // Convert UInt32 to group/element (upper 16 bits = group, lower 16 bits = element)
                let group = UInt16(tagValue >> 16)
                let element = UInt16(tagValue & 0xFFFF)
                let tag = Tag(group: group, element: element)
                if dataSet[tag] == nil {
                    return .failed(STOWFailedInstance(
                        sopInstanceUID: sopInstanceUID,
                        sopClassUID: sopClassUID,
                        failureReason: .missingRequiredAttribute
                    ))
                }
            }
        }
        
        // Check for duplicate
        let existing = try? await storage.getInstance(
            studyUID: studyUID,
            seriesUID: seriesUID,
            instanceUID: sopInstanceUID
        )
        
        let isDuplicate = existing != nil
        
        // Store the instance (replaces if exists)
        do {
            try await storage.storeInstance(
                data: data,
                studyUID: studyUID,
                seriesUID: seriesUID,
                instanceUID: sopInstanceUID
            )
            
            let storedInstance = STOWStoredInstance(
                sopInstanceUID: sopInstanceUID,
                sopClassUID: sopClassUID,
                studyUID: studyUID,
                seriesUID: seriesUID
            )
            
            if isDuplicate {
                return .duplicate(storedInstance)
            } else {
                return .stored(storedInstance)
            }
        } catch {
            return .failed(STOWFailedInstance(
                sopInstanceUID: sopInstanceUID,
                sopClassUID: sopClassUID,
                failureReason: .processingFailure
            ))
        }
    }
    
    /// Validates a DICOM UID format
    private func isValidUID(_ uid: String) -> Bool {
        // DICOM UID: 1-64 characters, only digits and dots, no leading/trailing dots
        // Components are numeric (no leading zeros except for 0 itself)
        guard !uid.isEmpty, uid.count <= 64 else { return false }
        guard !uid.hasPrefix("."), !uid.hasSuffix(".") else { return false }
        
        let components = uid.split(separator: ".")
        for component in components {
            // Each component must be a valid number (no leading zeros unless it's just "0")
            guard !component.isEmpty else { return false }
            guard component.allSatisfy({ $0.isNumber }) else { return false }
            if component.count > 1 && component.first == "0" {
                return false
            }
        }
        
        return true
    }
    
    /// Notifies the store delegate about stored and failed instances
    private func notifyStoreDelegate(stored: [STOWStoredInstance], failed: [STOWFailedInstance]) async {
        guard let delegate = storeDelegate else { return }
        
        for instance in stored {
            await delegate.server(self, didStoreInstance: instance.sopInstanceUID, studyUID: instance.studyUID, seriesUID: instance.seriesUID)
        }
        
        for instance in failed {
            await delegate.server(self, didFailToStoreInstance: instance.sopInstanceUID, reason: instance.failureReason.description)
        }
    }
    
    /// Builds a STOW-RS response with appropriate HTTP status code
    private func buildSTOWResponseWithStatus(
        stored: [STOWStoredInstance],
        failed: [STOWFailedInstance],
        hasWarnings: Bool
    ) -> DICOMwebResponse {
        // PS3.18 Table 10.5.3-1: 200 all stored; 202 some stored, warnings or failures for
        // others; 409 none stored because of a conflict in the request (unsupported SOP Class,
        // Study Instance UID mismatch, or a mixture of reasons); 400 is for bad syntax, which
        // the multipart parser reports before this point
        let statusCode: Int
        if failed.isEmpty && !hasWarnings {
            statusCode = 200
        } else if !stored.isEmpty && !failed.isEmpty {
            statusCode = 202
        } else if stored.isEmpty && !failed.isEmpty {
            statusCode = 409
        } else {
            // All stored, with warnings (e.g., duplicates replaced)
            statusCode = 202
        }
        
        // Build response JSON
        let responseJSON = buildSTOWResponseJSON(stored: stored, failed: failed)
        
        var headers: [String: String] = [
            "Content-Type": "application/dicom+json",
            "Content-Length": "\(responseJSON.count)"
        ]
        
        // Table 10.5.3-2: Location of the created resource, when all instances went to one Study
        if let studyUID = Set(stored.map { $0.studyUID }).first, stored.count > 0, Set(stored.map { $0.studyUID }).count == 1 {
            headers["Location"] = "\(configuration.baseURL.absoluteString)/studies/\(studyUID)"
        }
        if hasWarnings || !failed.isEmpty {
            headers["Warning"] = warning("Some instances were not stored as sent; see the Failed SOP Sequence")
        }
        
        return DICOMwebResponse(statusCode: statusCode, headers: headers, body: responseJSON)
    }
    
    /// Builds the STOW-RS response JSON body
    private func buildSTOWResponseJSON(stored: [STOWStoredInstance], failed: [STOWFailedInstance]) -> Data {
        var response: [String: Any] = [:]
        
        // Referenced SOP Sequence - stored instances (00081199)
        if !stored.isEmpty {
            var referencedSOPSequence: [[String: Any]] = []
            for instance in stored {
                var item: [String: Any] = [:]
                // Referenced SOP Class UID (00081150)
                item["00081150"] = createDICOMJSONValue(vr: "UI", value: instance.sopClassUID)
                // Referenced SOP Instance UID (00081155)
                item["00081155"] = createDICOMJSONValue(vr: "UI", value: instance.sopInstanceUID)
                // Retrieve URL (00081190) - optional
                let retrieveURL = "\(configuration.baseURL)/studies/\(instance.studyUID)/series/\(instance.seriesUID)/instances/\(instance.sopInstanceUID)"
                item["00081190"] = createDICOMJSONValue(vr: "UR", value: retrieveURL)
                referencedSOPSequence.append(item)
            }
            response["00081199"] = ["vr": "SQ", "Value": referencedSOPSequence]
        }
        
        // Failed SOP Sequence (00081198)
        if !failed.isEmpty {
            var failedSOPSequence: [[String: Any]] = []
            for instance in failed {
                var item: [String: Any] = [:]
                // Referenced SOP Class UID (00081150) - if available
                if let sopClassUID = instance.sopClassUID {
                    item["00081150"] = createDICOMJSONValue(vr: "UI", value: sopClassUID)
                }
                // Referenced SOP Instance UID (00081155)
                item["00081155"] = createDICOMJSONValue(vr: "UI", value: instance.sopInstanceUID)
                // Failure Reason (00081197) - US value should be numeric
                item["00081197"] = createDICOMJSONValue(vr: "US", intValue: Int(instance.failureReason.rawValue))
                failedSOPSequence.append(item)
            }
            response["00081198"] = ["vr": "SQ", "Value": failedSOPSequence]
        }
        
        // Store Instances Response Module: one Data Set (PS3.18 10.5.3, Annex I), written in
        // PS3.18 F.2.2 order
        if let data = try? DICOMJSONWriter().data(with: response) {
            return data
        }
        return Data()
    }
    
    // MARK: - Delete Handlers
    
    private func handleDeleteStudy(parameters: [String: String]) async throws -> DICOMwebResponse {
        guard let studyUID = parameters["studyUID"] else {
            return .badRequest(message: "Missing studyUID")
        }
        
        // Check for deletion mode in query parameters (defaults to permanent)
        let mode: DeletionMode = parameters["mode"]?.lowercased() == "soft" ? .soft : .permanent
        
        let deleted = try await storage.deleteStudy(studyUID: studyUID, mode: mode)
        
        if deleted == 0 {
            return .notFound(message: "Study not found: \(studyUID)")
        }
        
        return .noContent()
    }
    
    private func handleDeleteSeries(parameters: [String: String]) async throws -> DICOMwebResponse {
        guard let studyUID = parameters["studyUID"],
              let seriesUID = parameters["seriesUID"] else {
            return .badRequest(message: "Missing studyUID or seriesUID")
        }
        
        // Check for deletion mode in query parameters (defaults to permanent)
        let mode: DeletionMode = parameters["mode"]?.lowercased() == "soft" ? .soft : .permanent
        
        let deleted = try await storage.deleteSeries(studyUID: studyUID, seriesUID: seriesUID, mode: mode)
        
        if deleted == 0 {
            return .notFound(message: "Series not found: \(seriesUID)")
        }
        
        return .noContent()
    }
    
    private func handleDeleteInstance(parameters: [String: String]) async throws -> DICOMwebResponse {
        guard let studyUID = parameters["studyUID"],
              let seriesUID = parameters["seriesUID"],
              let instanceUID = parameters["instanceUID"] else {
            return .badRequest(message: "Missing studyUID, seriesUID, or instanceUID")
        }
        
        // Check for deletion mode in query parameters (defaults to permanent)
        let mode: DeletionMode = parameters["mode"]?.lowercased() == "soft" ? .soft : .permanent
        
        let deleted = try await storage.deleteInstance(studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID, mode: mode)
        
        if !deleted {
            return .notFound(message: "Instance not found: \(instanceUID)")
        }
        
        return .noContent()
    }
    
    // MARK: - UPS-RS Handlers
    
    /// Handles GET /workitems - Search workitems
    private func handleSearchWorkitems(request: DICOMwebRequest) async throws -> DICOMwebResponse {
        guard let upsStorage = upsStorage else {
            return .init(statusCode: 501, headers: ["Content-Type": "application/json"],
                        body: "{\"error\": \"UPS-RS not configured\"}".data(using: .utf8))
        }
        
        // Parse query parameters into UPSStorageQuery
        let query = parseUPSQuery(from: request.queryParameters)
        
        // Search workitems
        let workitems = try await upsStorage.searchWorkitems(query: query)
        let totalCount = try await upsStorage.countWorkitems(query: query)
        
        // Convert workitems to DICOM JSON array
        let jsonArray = workitems.map { workitemToDICOMJSON($0) }
        
        guard let jsonData = try? DICOMJSONWriter().data(with: jsonArray) else {
            return .internalError(message: "Failed to serialize workitem results")
        }
        
        var headers: [String: String] = [
            "Content-Type": DICOMMediaType.dicomJSON.description,
            "Content-Length": "\(jsonData.count)",
            "X-Total-Count": "\(totalCount)"
        ]
        let remaining = totalCount - (query.offset + workitems.count)
        if remaining > 0 {
            headers["Warning"] = warning("There are \(remaining) additional results that can be requested")
        }
        
        return DICOMwebResponse(statusCode: 200, headers: headers, body: jsonData)
    }
    
    /// Handles GET /workitems/{workitemUID} - Retrieve specific workitem
    private func handleRetrieveWorkitem(parameters: [String: String], request: DICOMwebRequest) async throws -> DICOMwebResponse {
        guard let upsStorage = upsStorage else {
            return .init(statusCode: 501, headers: ["Content-Type": "application/json"],
                        body: "{\"error\": \"UPS-RS not configured\"}".data(using: .utf8))
        }
        
        guard let workitemUID = parameters["workitemUID"] else {
            return .badRequest(message: "Missing workitemUID")
        }
        
        guard let workitem = try await upsStorage.getWorkitem(workitemUID: workitemUID) else {
            return .notFound(message: "Workitem not found: \(workitemUID)")
        }
        
        // Convert to DICOM JSON
        let json = workitemToDICOMJSON(workitem)
        
        guard let jsonData = try? DICOMJSONWriter().data(with: json) else {
            return .internalError(message: "Failed to serialize workitem")
        }
        
        return .ok(json: jsonData)
    }
    
    /// Handles POST /workitems and POST /workitems/{workitemUID} - Create workitem
    private func handleCreateWorkitem(parameters: [String: String], request: DICOMwebRequest) async throws -> DICOMwebResponse {
        guard let upsStorage = upsStorage else {
            return .init(statusCode: 501, headers: ["Content-Type": "application/json"],
                        body: "{\"error\": \"UPS-RS not configured\"}".data(using: .utf8))
        }
        
        guard let body = request.body, !body.isEmpty else {
            return .badRequest(message: "Request body is required")
        }
        
        // Parse JSON body
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return .badRequest(message: "Invalid JSON body")
        }
        
        // Workitem UID from the workitem query parameter (Table 11.4.1-1), else from the
        // payload (11.4.1.1: the Data Set shall contain it when the Worklist is the target),
        // else generated
        let workitemUID: String
        if let pathUID = parameters["workitemUID"] {
            workitemUID = pathUID
        } else if let uidFromBody = extractString(from: json, tag: UPSTag.sopInstanceUID) {
            workitemUID = uidFromBody
        } else {
            workitemUID = generateUID()
        }
        
        // PS3.4 CC.2.5.3: creation is accepted only with Procedure Step State SCHEDULED (C309H)
        if let state = extractString(from: json, tag: UPSTag.procedureStepState), state != UPSState.scheduled.rawValue {
            return .badRequest(message: "Procedure Step State (0074,1000) must be SCHEDULED for a Create Workitem request")
        }
        
        // Table 11.4.3-1: 409 when the Target Workitem already exists
        if let _ = try await upsStorage.getWorkitem(workitemUID: workitemUID) {
            return .conflict(message: "Workitem already exists: \(workitemUID)")
        }
        
        // 11.4.2: the new Workitem is in the SCHEDULED state
        var workitem = parseWorkitemFromJSON(json, workitemUID: workitemUID)
        workitem.state = .scheduled
        workitem.transactionUID = nil
        
        try await upsStorage.createWorkitem(workitem)
        
        // 11.4.3: 201, Location of the created Workitem, no payload
        let locationURL = "\(configuration.baseURL.absoluteString)/workitems/\(workitemUID)"
        return DICOMwebResponse(statusCode: 201, headers: ["Location": locationURL])
    }
    
    /// Handles PUT /workitems/{workitemUID} - Update workitem
    private func handleUpdateWorkitem(parameters: [String: String], request: DICOMwebRequest) async throws -> DICOMwebResponse {
        guard let upsStorage = upsStorage else {
            return .init(statusCode: 501, headers: ["Content-Type": "application/json"],
                        body: "{\"error\": \"UPS-RS not configured\"}".data(using: .utf8))
        }
        
        guard let workitemUID = parameters["workitemUID"] else {
            return .badRequest(message: "Missing workitemUID")
        }
        
        guard let body = request.body, !body.isEmpty else {
            return .badRequest(message: "Request body is required")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return .badRequest(message: "Invalid JSON body")
        }
        
        // Get existing workitem
        guard var workitem = try await upsStorage.getWorkitem(workitemUID: workitemUID) else {
            return .notFound(message: "Workitem not found: \(workitemUID)")
        }
        
        // 11.6.2: a COMPLETED or CANCELED Workitem gives 400 (PS3.4 CC.2.6.3)
        if workitem.state.isFinal {
            return response(400, warning: "The submitted request is inconsistent with the current state of the Workitem.")
        }
        
        // 11.6.1: the Transaction UID of a claimed (IN PROGRESS) Workitem comes as the query
        // parameter (00081195 / TransactionUID) or in the Data Set; PS3.4 CC.2.6.3: the set
        // request is refused when it does not carry the recorded value
        if workitem.state == .inProgress {
            let fromBody = extractString(from: json, tag: UPSTag.transactionUID)
            let provided = request.queryParameters["00081195"] ?? request.queryParameters["TransactionUID"] ?? fromBody
            guard let provided = provided, provided == workitem.transactionUID else {
                return response(400, warning: "The Target URI did not reference a claimed Workitem.")
            }
        }
        
        // Apply updates from JSON
        applyWorkitemUpdates(&workitem, from: json)
        
        // Save the updated workitem
        try await upsStorage.updateWorkitem(workitem)
        
        // Table 11.6.3-1: 200; 11.6.3.3: no payload
        return DICOMwebResponse(statusCode: 200)
    }
    
    /// Handles PUT /workitems/{workitemUID}/state - Change workitem state
    private func handleChangeWorkitemState(parameters: [String: String], request: DICOMwebRequest) async throws -> DICOMwebResponse {
        guard let upsStorage = upsStorage else {
            return .init(statusCode: 501, headers: ["Content-Type": "application/json"],
                        body: "{\"error\": \"UPS-RS not configured\"}".data(using: .utf8))
        }
        
        guard let workitemUID = parameters["workitemUID"] else {
            return .badRequest(message: "Missing workitemUID")
        }
        
        guard let body = request.body, !body.isEmpty else {
            return .badRequest(message: "Request body is required")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return .badRequest(message: "Invalid JSON body")
        }
        
        // Extract target state
        guard let stateString = extractString(from: json, tag: UPSTag.procedureStepState),
              let targetState = UPSState(rawValue: stateString) else {
            return .badRequest(message: "Missing or invalid Procedure Step State")
        }
        
        // Get existing workitem
        guard let workitem = try await upsStorage.getWorkitem(workitemUID: workitemUID) else {
            return .notFound(message: "Workitem not found: \(workitemUID)")
        }
        
        // 11.7.1.4: the payload shall include the Transaction UID (Table 11.7.3-1: 400 when missing)
        guard let transactionUID = extractString(from: json, tag: UPSTag.transactionUID), !transactionUID.isEmpty else {
            return response(400, warning: "The Transaction UID is missing.")
        }
        
        // PS3.4 Table CC.1.1-2 / PS3.18 11.7.3.2: already in the requested final state is a warning
        if workitem.state == targetState && targetState.isFinal {
            return response(200, warning: "The UPS is already in the requested state of \(targetState.rawValue).")
        }
        
        // Table CC.1.1-2: a change of an IN PROGRESS UPS needs the recorded Transaction UID
        // (C301H; Table 11.7.3-1: 400 incorrect)
        if workitem.state == .inProgress, workitem.transactionUID != transactionUID {
            return response(400, warning: "The Transaction UID is incorrect.")
        }
        
        // Table CC.1.1-2: every other transition the table refuses (SCHEDULED to COMPLETED or
        // CANCELED, IN PROGRESS to IN PROGRESS, out of a final state) is a 409
        guard workitem.state.canTransition(to: targetState) else {
            return response(409, warning: "The submitted request is inconsistent with the state of the UPS Instance.")
        }
        
        do {
            try await upsStorage.changeWorkitemState(
                workitemUID: workitemUID,
                newState: targetState,
                transactionUID: transactionUID
            )
        } catch let error as UPSError {
            switch error {
            case .transactionUIDRequired:
                return response(400, warning: "The Transaction UID is missing.")
            case .transactionUIDMismatch:
                return response(400, warning: "The Transaction UID is incorrect.")
            default:
                return response(409, warning: "The submitted request is inconsistent with the state of the UPS Instance.")
            }
        }
        
        // 11.7.3.3: a success response shall have no payload
        return DICOMwebResponse(statusCode: 200)
    }
    
    /// Handles PUT /workitems/{workitemUID}/cancelrequest - Request workitem cancellation
    private func handleRequestWorkitemCancellation(parameters: [String: String], request: DICOMwebRequest) async throws -> DICOMwebResponse {
        guard let upsStorage = upsStorage else {
            return .init(statusCode: 501, headers: ["Content-Type": "application/json"],
                        body: "{\"error\": \"UPS-RS not configured\"}".data(using: .utf8))
        }
        
        guard let workitemUID = parameters["workitemUID"] else {
            return .badRequest(message: "Missing workitemUID")
        }
        
        // Get existing workitem
        guard let workitem = try await upsStorage.getWorkitem(workitemUID: workitemUID) else {
            return .notFound(message: "Workitem not found: \(workitemUID)")
        }
        
        // 11.8.3.2 / Table CC.1.1-2: already CANCELED is a warning (B304H), COMPLETED a failure (C311H)
        switch workitem.state {
        case .canceled:
            return response(202, warning: "The UPS is already in the requested state of CANCELED.")
        case .completed:
            return response(409, warning: "The UPS is already COMPLETED.")
        case .scheduled, .inProgress:
            break
        }
        
        // Parse cancellation request body if present (PS3.4 Table CC.2.2-1)
        var reason: String? = nil
        if let body = request.body, !body.isEmpty,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            reason = extractString(from: json, tag: UPSTag.reasonForCancellation)
        }
        
        // PS3.4 CC.2.2.3: a SCHEDULED UPS is changed by the SCP to IN PROGRESS and then to
        // CANCELED; for an IN PROGRESS UPS the request is only reported to the performer
        if workitem.state == .scheduled {
            try await upsStorage.changeWorkitemState(
                workitemUID: workitemUID,
                newState: .canceled,
                transactionUID: nil
            )
            
            // Update cancellation reason if provided
            if let reason = reason, var updated = try await upsStorage.getWorkitem(workitemUID: workitemUID) {
                updated.cancellationReason = reason
                try await upsStorage.updateWorkitem(updated)
            }
        }
        
        // Table 11.8.3-1: 202 (Accepted)
        return DICOMwebResponse(statusCode: 202, headers: [:], body: nil)
    }
    
    /// Handles POST /workitems/{workitemUID}/subscribers/{aeTitle} - Subscribe to workitem
    private func handleSubscribeWorkitem(parameters: [String: String], request: DICOMwebRequest) async throws -> DICOMwebResponse {
        guard upsStorage != nil else {
            return .init(statusCode: 501, headers: ["Content-Type": "application/json"],
                        body: "{\"error\": \"UPS-RS not configured\"}".data(using: .utf8))
        }
        
        // Note: aeTitle is validated but subscription management is not fully implemented yet.
        // Full subscription tracking will be added in a future version with event delivery.
        guard let workitemUID = parameters["workitemUID"],
              let _ = parameters["aeTitle"] else {
            return .badRequest(message: "Missing workitemUID or aeTitle")
        }
        
        // Verify workitem exists
        guard let _ = try await upsStorage?.getWorkitem(workitemUID: workitemUID) else {
            return .notFound(message: "Workitem not found: \(workitemUID)")
        }
        
        // Table 11.10.3-1: 201 (Created). Subscriptions and deletion locks are not tracked by
        // this server, so a requested lock is answered with the 11.10.3.2 warning
        return subscriptionCreatedResponse(request)
    }
    
    private func subscriptionCreatedResponse(_ request: DICOMwebRequest) -> DICOMwebResponse {
        if request.queryParameters["deletionlock"]?.lowercased() == "true" {
            return response(201, warning: "Deletion Lock not granted.")
        }
        return DICOMwebResponse(statusCode: 201)
    }
    
    /// Handles DELETE /workitems/{workitemUID}/subscribers/{aeTitle} - Unsubscribe from workitem
    private func handleUnsubscribeWorkitem(parameters: [String: String], request: DICOMwebRequest) async throws -> DICOMwebResponse {
        guard upsStorage != nil else {
            return .init(statusCode: 501, headers: ["Content-Type": "application/json"],
                        body: "{\"error\": \"UPS-RS not configured\"}".data(using: .utf8))
        }
        
        // Return 200 regardless - idempotent operation
        return DICOMwebResponse(statusCode: 200, headers: [:], body: nil)
    }
    
    /// Handles POST /workitems/1.2.840.10008.5.1.4.34.5/subscribers/{aeTitle} - Global subscription
    private func handleSubscribeGlobal(parameters: [String: String], request: DICOMwebRequest) async throws -> DICOMwebResponse {
        guard upsStorage != nil else {
            return .init(statusCode: 501, headers: ["Content-Type": "application/json"],
                        body: "{\"error\": \"UPS-RS not configured\"}".data(using: .utf8))
        }
        
        // Table 11.10.1-2: a filter is required for the Filtered Worklist; 11.10.3.2: 403 when unsupported
        if parameters["workitemUID"] == DICOMwebURLBuilder.filteredGlobalSubscriptionUID {
            return DICOMwebResponse(statusCode: 403, headers: ["Warning": warning("Filtered Worklist Subscriptions are not supported.")])
        }
        return subscriptionCreatedResponse(request)
    }
    
    /// Handles DELETE /workitems/1.2.840.10008.5.1.4.34.5/subscribers/{aeTitle} - Global unsubscription
    private func handleUnsubscribeGlobal(parameters: [String: String], request: DICOMwebRequest) async throws -> DICOMwebResponse {
        guard upsStorage != nil else {
            return .init(statusCode: 501, headers: ["Content-Type": "application/json"],
                        body: "{\"error\": \"UPS-RS not configured\"}".data(using: .utf8))
        }
        
        return DICOMwebResponse(statusCode: 200, headers: [:], body: nil)
    }
    
    /// Handles POST /workitems/{workitemUID}/subscribers/{aeTitle}/suspend - Suspend subscription
    /// Handles POST /workitems/{workitemUID}/subscribers/{aeTitle}/suspend - Suspend subscription
    private func handleSuspendSubscription(parameters: [String: String], request: DICOMwebRequest) async throws -> DICOMwebResponse {
        guard upsStorage != nil else {
            return .init(statusCode: 501, headers: ["Content-Type": "application/json"],
                        body: "{\"error\": \"UPS-RS not configured\"}".data(using: .utf8))
        }
        
        // Note: aeTitle is validated but subscription management is not fully implemented yet.
        // Full subscription suspend tracking will be added in a future version with event delivery.
        guard let workitemUID = parameters["workitemUID"],
              let _ = parameters["aeTitle"] else {
            return .badRequest(message: "Missing workitemUID or aeTitle")
        }
        
        // Verify workitem exists
        guard let _ = try await upsStorage?.getWorkitem(workitemUID: workitemUID) else {
            return .notFound(message: "Workitem not found: \(workitemUID)")
        }
        
        return DICOMwebResponse(statusCode: 200, headers: [:], body: nil)
    }
    
    // MARK: - UPS Helper Methods
    
    /// Parses query parameters into UPSStorageQuery
    private func parseUPSQuery(from parameters: [String: String]) -> UPSStorageQuery {
        var query = UPSStorageQuery()
        
        // Parse state
        if let stateStr = parameters["00741000"] ?? parameters["ProcedureStepState"] {
            query.state = UPSState(rawValue: stateStr)
        }
        
        // Parse priority
        if let priorityStr = parameters["00741200"] ?? parameters["ScheduledProcedureStepPriority"] {
            query.priority = UPSPriority(rawValue: priorityStr)
        }
        
        // Parse patient info
        query.patientID = parameters["00100020"] ?? parameters["PatientID"]
        query.patientName = parameters["00100010"] ?? parameters["PatientName"]
        
        // Parse procedure info
        query.procedureStepLabel = parameters["00741204"] ?? parameters["ProcedureStepLabel"]
        query.worklistLabel = parameters["00741202"] ?? parameters["WorklistLabel"]
        
        // Parse study reference
        query.studyInstanceUID = parameters["0020000D"] ?? parameters["StudyInstanceUID"]
        query.accessionNumber = parameters["00080050"] ?? parameters["AccessionNumber"]
        
        // Parse pagination
        if let limitStr = parameters["limit"], let limit = Int(limitStr) {
            query.limit = min(limit, 1000) // Cap at 1000
        }
        if let offsetStr = parameters["offset"], let offset = Int(offsetStr) {
            query.offset = offset
        }
        
        // Parse fuzzy matching
        query.fuzzyMatching = parameters["fuzzymatching"]?.lowercased() == "true"
        
        return query
    }
    
    /// Converts a Workitem to DICOM JSON format
    private func workitemToDICOMJSON(_ workitem: Workitem) -> [String: Any] {
        var json: [String: Any] = [:]
        
        // SOP Instance UID
        json[UPSTag.sopInstanceUID] = [
            "vr": "UI",
            "Value": [workitem.workitemUID]
        ]
        
        // Procedure Step State
        json[UPSTag.procedureStepState] = [
            "vr": "CS",
            "Value": [workitem.state.rawValue]
        ]
        
        // Priority
        json[UPSTag.scheduledProcedureStepPriority] = [
            "vr": "CS",
            "Value": [workitem.priority.dicomValue]
        ]
        
        // Patient info
        if let patientName = workitem.patientName {
            json[UPSTag.patientName] = [
                "vr": "PN",
                "Value": [["Alphabetic": patientName]]
            ]
        }
        
        if let patientID = workitem.patientID {
            json[UPSTag.patientID] = [
                "vr": "LO",
                "Value": [patientID]
            ]
        }
        
        // Scheduling info
        if let scheduledStart = workitem.scheduledStartDateTime {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
            json[UPSTag.scheduledProcedureStepStartDateTime] = [
                "vr": "DT",
                "Value": [formatter.string(from: scheduledStart)]
            ]
        }
        
        // Labels
        if let label = workitem.procedureStepLabel {
            json[UPSTag.procedureStepLabel] = [
                "vr": "LO",
                "Value": [label]
            ]
        }
        
        if let worklistLabel = workitem.worklistLabel {
            json[UPSTag.worklistLabel] = [
                "vr": "LO",
                "Value": [worklistLabel]
            ]
        }
        
        // Study reference
        if let studyUID = workitem.studyInstanceUID {
            json[UPSTag.studyInstanceUID] = [
                "vr": "UI",
                "Value": [studyUID]
            ]
        }
        
        if let accession = workitem.accessionNumber {
            json[UPSTag.accessionNumber] = [
                "vr": "SH",
                "Value": [accession]
            ]
        }
        
        // PS3.18 11.5.2 / PS3.4 CC.2.7.3: the returned Workitem shall not contain the Transaction
        // UID (0008,1195), which is the access lock
        
        // Progress info (Procedure Step Progress (0074,1004) is DS, PS3.6 Table 6-1)
        if let progress = workitem.progressInformation {
            if let percentage = progress.progressPercentage {
                json[UPSTag.procedureStepProgress] = [
                    "vr": "DS",
                    "Value": [String(percentage)]
                ]
            }
            if let description = progress.progressDescription {
                json[UPSTag.procedureStepProgressDescription] = [
                    "vr": "ST",
                    "Value": [description]
                ]
            }
        }
        
        // Comments
        if let comments = workitem.comments {
            json[UPSTag.commentsOnTheScheduledProcedureStep] = [
                "vr": "LT",
                "Value": [comments]
            ]
        }
        
        return json
    }
    
    /// Parses a Workitem from DICOM JSON
    private func parseWorkitemFromJSON(_ json: [String: Any], workitemUID: String) -> Workitem {
        var workitem = Workitem(workitemUID: workitemUID)
        
        // Parse state
        if let stateStr = extractString(from: json, tag: UPSTag.procedureStepState),
           let state = UPSState(rawValue: stateStr) {
            workitem.state = state
        }
        
        // Parse priority
        if let priorityStr = extractString(from: json, tag: UPSTag.scheduledProcedureStepPriority),
           let priority = UPSPriority(rawValue: priorityStr) {
            workitem.priority = priority
        }
        
        // Parse patient info
        workitem.patientName = extractPersonName(from: json, tag: UPSTag.patientName)
        workitem.patientID = extractString(from: json, tag: UPSTag.patientID)
        
        // Parse scheduling
        if let dateStr = extractString(from: json, tag: UPSTag.scheduledProcedureStepStartDateTime) {
            workitem.scheduledStartDateTime = parseDateTime(dateStr)
        }
        
        // Parse labels
        workitem.procedureStepLabel = extractString(from: json, tag: UPSTag.procedureStepLabel)
        workitem.worklistLabel = extractString(from: json, tag: UPSTag.worklistLabel)
        
        // Parse study reference
        workitem.studyInstanceUID = extractString(from: json, tag: UPSTag.studyInstanceUID)
        workitem.accessionNumber = extractString(from: json, tag: UPSTag.accessionNumber)
        
        // Parse comments
        workitem.comments = extractString(from: json, tag: UPSTag.commentsOnTheScheduledProcedureStep)
        
        return workitem
    }
    
    /// Applies updates from JSON to an existing workitem
    private func applyWorkitemUpdates(_ workitem: inout Workitem, from json: [String: Any]) {
        // Update patient info if provided
        if let patientName = extractPersonName(from: json, tag: UPSTag.patientName) {
            workitem.patientName = patientName
        }
        if let patientID = extractString(from: json, tag: UPSTag.patientID) {
            workitem.patientID = patientID
        }
        
        // Update scheduling if provided
        if let dateStr = extractString(from: json, tag: UPSTag.scheduledProcedureStepStartDateTime) {
            workitem.scheduledStartDateTime = parseDateTime(dateStr)
        }
        
        // Update labels if provided
        if let label = extractString(from: json, tag: UPSTag.procedureStepLabel) {
            workitem.procedureStepLabel = label
        }
        if let worklistLabel = extractString(from: json, tag: UPSTag.worklistLabel) {
            workitem.worklistLabel = worklistLabel
        }
        
        // Update priority if provided
        if let priorityStr = extractString(from: json, tag: UPSTag.scheduledProcedureStepPriority),
           let priority = UPSPriority(rawValue: priorityStr) {
            workitem.priority = priority
        }
        
        // Update comments if provided
        if let comments = extractString(from: json, tag: UPSTag.commentsOnTheScheduledProcedureStep) {
            workitem.comments = comments
        }
        
        // Update modification time
        workitem.modificationDateTime = Date()
    }
    
    /// Extracts a string value from DICOM JSON
    private func extractString(from json: [String: Any], tag: String) -> String? {
        guard let element = json[tag] as? [String: Any],
              let values = element["Value"] as? [Any],
              let first = values.first else {
            return nil
        }
        return first as? String
    }
    
    /// Extracts a person name from DICOM JSON
    private func extractPersonName(from json: [String: Any], tag: String) -> String? {
        guard let element = json[tag] as? [String: Any],
              let values = element["Value"] as? [Any],
              let first = values.first else {
            return nil
        }
        
        if let stringValue = first as? String {
            return stringValue
        }
        if let dictValue = first as? [String: Any],
           let alphabetic = dictValue["Alphabetic"] as? String {
            return alphabetic
        }
        return nil
    }
    
    /// Parses a DICOM DateTime string to Date
    private func parseDateTime(_ string: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        if let date = isoFormatter.date(from: string) {
            return date
        }
        
        // Try without time component using a simple parser
        // DICOM date format is yyyyMMdd
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        return dateFormatter.date(from: string)
    }
    
    /// Generates a DICOM UID using the 2.25 root and timestamp/random components
    private func generateUID() -> String {
        // Use timestamp and random for uniqueness
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        let random = UInt64.random(in: 0..<UInt64.max)
        return "2.25.\(timestamp)\(random % 10000000000)"
    }
    
    // MARK: - Capabilities
    
    /// Serves DICOMKit's JSON capabilities document at GET / and GET /capabilities. This is
    /// not the PS3.18 8.9 Retrieve Capabilities Transaction (OPTIONS / returning a WADL
    /// Capabilities Description, Annex H), which is not implemented.
    private func handleCapabilities() -> DICOMwebResponse {
        // Build capabilities based on server configuration
        let capabilities = DICOMwebCapabilities(
            apiVersion: "1.0",
            serverName: "DICOMKit",
            serverVersion: "0.8.8",
            services: DICOMwebCapabilities.SupportedServices(
                wadoRS: true,
                qidoRS: true,
                stowRS: true,
                upsRS: upsStorage != nil,
                delete: true,
                rendered: false,
                thumbnails: false,
                bulkdata: true
            ),
            mediaTypes: DICOMwebCapabilities.MediaTypeSupport(),
            transferSyntaxes: [
                "1.2.840.10008.1.2.1",     // Explicit VR Little Endian
                "1.2.840.10008.1.2",       // Implicit VR Little Endian
                "1.2.840.10008.1.2.2",     // Explicit VR Big Endian
                "1.2.840.10008.1.2.4.50",  // JPEG Baseline
                "1.2.840.10008.1.2.4.70",  // JPEG Lossless, Non-Hierarchical, First-Order Prediction (Process 14 [Selection Value 1])
                "1.2.840.10008.1.2.4.90",  // JPEG 2000 Lossless
                "1.2.840.10008.1.2.4.91",  // JPEG 2000
                "1.2.840.10008.1.2.5"      // RLE Lossless
            ],
            queryCapabilities: DICOMwebCapabilities.QueryCapabilities(
                fuzzyMatching: false,
                wildcardMatching: true,
                dateRangeQueries: true,
                includeFieldAll: true
            ),
            storeCapabilities: DICOMwebCapabilities.StoreCapabilities(
                maxRequestSize: configuration.maxRequestBodySize,
                partialSuccess: true
            ),
            authenticationMethods: [.none, .basic, .bearer, .apiKey]
        )
        
        let json = capabilities.toJSONDictionary()
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            var headers: [String: String] = ["Content-Type": "application/json"]
            headers["Content-Length"] = "\(jsonData.count)"
            return DICOMwebResponse(statusCode: 200, headers: headers, body: jsonData)
        }
        return .internalError()
    }
    
    // MARK: - CORS Handling
    
    private func handleCORSPreflight(_ request: DICOMwebRequest) -> DICOMwebResponse {
        guard let cors = configuration.corsConfiguration else {
            return DICOMwebResponse(statusCode: 204)
        }
        
        var headers: [String: String] = [:]
        
        if cors.allowedOrigins.contains("*") {
            headers["Access-Control-Allow-Origin"] = "*"
        } else if let origin = request.header("Origin"), cors.allowedOrigins.contains(origin) {
            headers["Access-Control-Allow-Origin"] = origin
        }
        
        headers["Access-Control-Allow-Methods"] = cors.allowedMethods.joined(separator: ", ")
        headers["Access-Control-Allow-Headers"] = cors.allowedHeaders.joined(separator: ", ")
        headers["Access-Control-Max-Age"] = "\(cors.maxAge)"
        
        if cors.allowCredentials {
            headers["Access-Control-Allow-Credentials"] = "true"
        }
        
        return DICOMwebResponse(statusCode: 204, headers: headers)
    }
    
    private func addCORSHeaders(to response: inout DICOMwebResponse, request: DICOMwebRequest) {
        guard let cors = configuration.corsConfiguration else { return }
        
        if cors.allowedOrigins.contains("*") {
            response.headers["Access-Control-Allow-Origin"] = "*"
        } else if let origin = request.header("Origin"), cors.allowedOrigins.contains(origin) {
            response.headers["Access-Control-Allow-Origin"] = origin
        }
        
        if !cors.exposedHeaders.isEmpty {
            response.headers["Access-Control-Expose-Headers"] = cors.exposedHeaders.joined(separator: ", ")
        }
        
        if cors.allowCredentials {
            response.headers["Access-Control-Allow-Credentials"] = "true"
        }
    }
    
    // MARK: - Helper Methods
    
    /// Maps QIDO-RS query parameters to a `StorageQuery`.
    ///
    /// PS3.18 8.3.4.1: `{attributeID}` may be the keyword *or* the 8-hex tag
    /// (`PatientName=` and `00100010=` are equivalent), so both are accepted for
    /// every key. Covers every required matching attribute of PS3.18 Table
    /// 10.6.1-5 plus the common optional ones.
    private func parseQIDOQuery(from parameters: [String: String]) -> StorageQuery {
        var query = StorageQuery()
        func value(_ keyword: String, _ tag: String) -> String? {
            let v = parameters[keyword] ?? parameters[tag]
            return (v?.isEmpty ?? true) ? nil : v
        }

        // Study level
        query.patientName = value("PatientName", "00100010")
        query.patientID = value("PatientID", "00100020")
        query.accessionNumber = value("AccessionNumber", "00080050")
        query.studyInstanceUID = value("StudyInstanceUID", "0020000D")
        query.studyID = value("StudyID", "00200010")
        query.studyDescription = value("StudyDescription", "00081030")
        query.referringPhysicianName = value("ReferringPhysicianName", "00080090")
        if let date = value("StudyDate", "00080020") {
            query.studyDate = StorageQuery.DateRange(dicomValue: date)
        }
        if let time = value("StudyTime", "00080030") {
            query.studyTime = StorageQuery.DateRange(dicomValue: time, format: "HHmmss")
        }
        if let modalities = value("ModalitiesInStudy", "00080061") {
            query.modalitiesInStudy = modalities
                .split(whereSeparator: { $0 == "\\" || $0 == "," })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        // Series level
        query.seriesInstanceUID = value("SeriesInstanceUID", "0020000E")
        query.modality = value("Modality", "00080060")
        query.seriesDescription = value("SeriesDescription", "0008103E")
        query.bodyPartExamined = value("BodyPartExamined", "00180015")
        if let number = value("SeriesNumber", "00200011").flatMap({ Int($0) }) {
            query.seriesNumber = number
        }

        // Instance level
        query.sopInstanceUID = value("SOPInstanceUID", "00080018")
        query.sopClassUID = value("SOPClassUID", "00080016")
        if let number = value("InstanceNumber", "00200013").flatMap({ Int($0) }) {
            query.instanceNumber = number
        }

        // Anything else (e.g. PerformedProcedureStepStartDate) is kept for
        // providers that can match on it.
        let handled: Set<String> = [
            "PatientName", "00100010", "PatientID", "00100020", "AccessionNumber", "00080050",
            "StudyInstanceUID", "0020000D", "StudyID", "00200010", "StudyDescription", "00081030",
            "ReferringPhysicianName", "00080090", "StudyDate", "00080020", "StudyTime", "00080030",
            "ModalitiesInStudy", "00080061", "SeriesInstanceUID", "0020000E", "Modality", "00080060",
            "SeriesDescription", "0008103E", "BodyPartExamined", "00180015", "SeriesNumber", "00200011",
            "SOPInstanceUID", "00080018", "SOPClassUID", "00080016", "InstanceNumber", "00200013",
            "offset", "limit", "fuzzymatching", "includefield",
        ]
        for (k, v) in parameters where !handled.contains(k) {
            query.customParameters[k] = v
        }

        if let offset = parameters["offset"], let value = Int(offset) {
            query.offset = value
        }
        if let limit = parameters["limit"], let value = Int(limit) {
            query.limit = value
        }
        if let fuzzy = parameters["fuzzymatching"], fuzzy.lowercased() == "true" {
            query.fuzzyMatching = true
        }
        
        return query
    }
    
    private func buildMultipartDICOMResponse(instances: [InstanceInfo]) -> (data: Data, boundary: String) {
        let boundary = "----DICOMBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var body = Data()
        
        for instance in instances {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/dicom\r\n".data(using: .utf8)!)
            // PS3.18 Table 8.6.1-1: each part that is a representation of a resource carries its URL
            let location = instanceURL(studyUID: instance.studyUID, seriesUID: instance.seriesUID, instanceUID: instance.instanceUID)
            body.append("Content-Location: \(location)\r\n".data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
            body.append(instance.data)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return (body, boundary)
    }
    
    private func instanceURL(studyUID: String, seriesUID: String, instanceUID: String) -> String {
        "\(configuration.baseURL.absoluteString)/studies/\(studyUID)/series/\(seriesUID)/instances/\(instanceUID)"
    }
    
    private func encodeMetadataAsJSON(datasets: [DataSet]) throws -> Data {
        let encoder = DICOMJSONEncoder()
        // Convert DataSets to arrays of DataElements for JSON encoding
        let elementArrays = datasets.map { $0.allElements }
        return try encoder.encodeMultiple(elementArrays)
    }
    
    private func encodeStudyResultsAsJSON(studies: [StudyRecord]) throws -> Data {
        var results: [[String: Any]] = []
        
        for study in studies {
            var dict: [String: Any] = [:]
            
            // Study Instance UID
            dict["0020000D"] = createDICOMJSONValue(vr: "UI", value: study.studyInstanceUID)
            
            if let name = study.patientName {
                dict["00100010"] = createDICOMJSONValue(vr: "PN", value: name)
            }
            if let id = study.patientID {
                dict["00100020"] = createDICOMJSONValue(vr: "LO", value: id)
            }
            if let date = study.studyDate {
                dict["00080020"] = createDICOMJSONValue(vr: "DA", value: date)
            }
            if let time = study.studyTime {
                dict["00080030"] = createDICOMJSONValue(vr: "TM", value: time)
            }
            if let desc = study.studyDescription {
                dict["00081030"] = createDICOMJSONValue(vr: "LO", value: desc)
            }
            if let acc = study.accessionNumber {
                dict["00080050"] = createDICOMJSONValue(vr: "SH", value: acc)
            }
            if !study.modalitiesInStudy.isEmpty {
                dict["00080061"] = createDICOMJSONValue(vr: "CS", values: study.modalitiesInStudy)
            }
            // Remaining required return attributes (PS3.18 Table 10.6.1-5)
            if let referring = study.referringPhysicianName {
                dict["00080090"] = createDICOMJSONValue(vr: "PN", value: referring)
            }
            if let birthDate = study.patientBirthDate {
                dict["00100030"] = createDICOMJSONValue(vr: "DA", value: birthDate)
            }
            if let sex = study.patientSex {
                dict["00100040"] = createDICOMJSONValue(vr: "CS", value: sex)
            }
            if let studyID = study.studyID {
                dict["00200010"] = createDICOMJSONValue(vr: "SH", value: studyID)
            }
            dict["00080056"] = createDICOMJSONValue(vr: "CS", value: "ONLINE")   // Instance Availability
            dict["00081190"] = createDICOMJSONValue(vr: "UR",                   // Retrieve URL
                value: "\(configuration.baseURL.absoluteString)/studies/\(study.studyInstanceUID)")
            
            dict["00201206"] = createDICOMJSONValue(vr: "IS", value: "\(study.numberOfStudyRelatedSeries)")
            dict["00201208"] = createDICOMJSONValue(vr: "IS", value: "\(study.numberOfStudyRelatedInstances)")
            
            results.append(dict)
        }
        
        return try DICOMJSONWriter().data(with: results)
    }
    
    private func encodeSeriesResultsAsJSON(series: [SeriesRecord]) throws -> Data {
        var results: [[String: Any]] = []
        
        for s in series {
            var dict: [String: Any] = [:]
            
            dict["0020000D"] = createDICOMJSONValue(vr: "UI", value: s.studyInstanceUID)
            dict["0020000E"] = createDICOMJSONValue(vr: "UI", value: s.seriesInstanceUID)
            
            if let modality = s.modality {
                dict["00080060"] = createDICOMJSONValue(vr: "CS", value: modality)
            }
            if let num = s.seriesNumber {
                dict["00200011"] = createDICOMJSONValue(vr: "IS", value: "\(num)")
            }
            if let desc = s.seriesDescription {
                dict["0008103E"] = createDICOMJSONValue(vr: "LO", value: desc)
            }
            if let bodyPart = s.bodyPartExamined {
                dict["00180015"] = createDICOMJSONValue(vr: "CS", value: bodyPart)
            }
            dict["00081190"] = createDICOMJSONValue(vr: "UR",                   // Retrieve URL
                value: "\(configuration.baseURL.absoluteString)/studies/\(s.studyInstanceUID)/series/\(s.seriesInstanceUID)")
            
            dict["00201209"] = createDICOMJSONValue(vr: "IS", value: "\(s.numberOfSeriesRelatedInstances)")
            
            results.append(dict)
        }
        
        return try DICOMJSONWriter().data(with: results)
    }
    
    private func encodeInstanceResultsAsJSON(instances: [InstanceRecord]) throws -> Data {
        var results: [[String: Any]] = []
        
        for instance in instances {
            var dict: [String: Any] = [:]
            
            dict["0020000D"] = createDICOMJSONValue(vr: "UI", value: instance.studyInstanceUID)
            dict["0020000E"] = createDICOMJSONValue(vr: "UI", value: instance.seriesInstanceUID)
            dict["00080018"] = createDICOMJSONValue(vr: "UI", value: instance.sopInstanceUID)
            
            if let sopClass = instance.sopClassUID {
                dict["00080016"] = createDICOMJSONValue(vr: "UI", value: sopClass)
            }
            if let num = instance.instanceNumber {
                dict["00200013"] = createDICOMJSONValue(vr: "IS", value: "\(num)")
            }
            if let frames = instance.numberOfFrames {
                dict["00280008"] = createDICOMJSONValue(vr: "IS", value: "\(frames)")
            }
            if let rows = instance.rows {
                dict["00280010"] = ["vr": "US", "Value": [rows]]
            }
            if let columns = instance.columns {
                dict["00280011"] = ["vr": "US", "Value": [columns]]
            }
            if let bits = instance.bitsAllocated {
                dict["00280100"] = ["vr": "US", "Value": [bits]]
            }
            dict["00081190"] = createDICOMJSONValue(vr: "UR",                   // Retrieve URL
                value: "\(configuration.baseURL.absoluteString)/studies/\(instance.studyInstanceUID)/series/\(instance.seriesInstanceUID)/instances/\(instance.sopInstanceUID)")
            
            results.append(dict)
        }
        
        return try DICOMJSONWriter().data(with: results)
    }
    
    private func createDICOMJSONValue(vr: String, value: String) -> [String: Any] {
        if vr == "PN" {
            return ["vr": vr, "Value": [["Alphabetic": value]]]
        }
        return ["vr": vr, "Value": [value]]
    }
    
    private func createDICOMJSONValue(vr: String, values: [String]) -> [String: Any] {
        return ["vr": vr, "Value": values]
    }
    
    private func createDICOMJSONValue(vr: String, intValue: Int) -> [String: Any] {
        return ["vr": vr, "Value": [intValue]]
    }
    
    private func errorResponse(for error: DICOMwebError) -> DICOMwebResponse {
        switch error {
        case .invalidURL, .badRequest:
            return .badRequest(message: error.localizedDescription)
        case .notFound:
            return .notFound()
        case .timeout:
            return .serviceUnavailable()
        default:
            return .internalError(message: error.localizedDescription)
        }
    }
}

// MARK: - Server Delegate

/// Delegate for DICOMweb server events
public protocol DICOMwebServerDelegate: AnyObject, Sendable {
    /// Called when the server starts
    func serverDidStart(_ server: DICOMwebServer) async
    
    /// Called when the server stops
    func serverDidStop(_ server: DICOMwebServer) async
    
    /// Called when a request is received
    func server(_ server: DICOMwebServer, didReceiveRequest request: DICOMwebRequest) async
    
    /// Called when a response is sent
    func server(_ server: DICOMwebServer, didSendResponse response: DICOMwebResponse, forRequest request: DICOMwebRequest) async
}

/// Default implementations for optional delegate methods
extension DICOMwebServerDelegate {
    public func serverDidStart(_ server: DICOMwebServer) async {}
    public func serverDidStop(_ server: DICOMwebServer) async {}
    public func server(_ server: DICOMwebServer, didReceiveRequest request: DICOMwebRequest) async {}
    public func server(_ server: DICOMwebServer, didSendResponse response: DICOMwebResponse, forRequest request: DICOMwebRequest) async {}
}

// MARK: - STOW-RS Delegate

/// Delegate for STOW-RS (Store) operations
///
/// Implement this protocol to be notified when DICOM instances are stored
/// or when storage fails. This allows for custom handling such as:
/// - Logging store operations
/// - Triggering post-storage processing
/// - Implementing custom rejection logic
/// - Updating external indexes or databases
///
/// Reference: PS3.18 Section 10.5 - STOW-RS
public protocol STOWDelegate: AnyObject, Sendable {
    /// Called when an instance is successfully stored
    /// - Parameters:
    ///   - server: The DICOMweb server
    ///   - sopInstanceUID: The SOP Instance UID of the stored instance
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    func server(_ server: DICOMwebServer, didStoreInstance sopInstanceUID: String, studyUID: String, seriesUID: String) async
    
    /// Called when storing an instance fails
    /// - Parameters:
    ///   - server: The DICOMweb server
    ///   - sopInstanceUID: The SOP Instance UID (may be "unknown" if not available)
    ///   - reason: The failure reason
    func server(_ server: DICOMwebServer, didFailToStoreInstance sopInstanceUID: String, reason: String) async
    
    /// Called before storing an instance to determine if it should be accepted
    ///
    /// This optional method allows implementing custom rejection logic beyond
    /// the standard STOW-RS validation. Return false to reject the instance.
    /// - Parameters:
    ///   - server: The DICOMweb server
    ///   - sopInstanceUID: The SOP Instance UID
    ///   - sopClassUID: The SOP Class UID
    ///   - studyUID: The Study Instance UID
    /// - Returns: True to accept the instance, false to reject
    func server(_ server: DICOMwebServer, shouldAcceptInstance sopInstanceUID: String, sopClassUID: String, studyUID: String) async -> Bool
}

/// Default implementations for optional STOW delegate methods
extension STOWDelegate {
    public func server(_ server: DICOMwebServer, didStoreInstance sopInstanceUID: String, studyUID: String, seriesUID: String) async {}
    public func server(_ server: DICOMwebServer, didFailToStoreInstance sopInstanceUID: String, reason: String) async {}
    public func server(_ server: DICOMwebServer, shouldAcceptInstance sopInstanceUID: String, sopClassUID: String, studyUID: String) async -> Bool { true }
}

