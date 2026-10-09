import Foundation
import DICOMCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// DICOMweb client for retrieving DICOM objects over HTTP
///
/// Implements the WADO-RS (Web Access to DICOM Objects - RESTful Services)
/// specification for retrieving studies, series, instances, and frames.
///
/// NEMA-verified: 2026a, checked 2026-09-28 — Accept media types diffed against PS3.18 2026a
/// Table 10.4.4-1 (instances, metadata, pixel data, thumbnails) and Table 8.7.3-5 (frames);
/// rendered parameters per 8.3.5.1.2-8.3.5.1.4; STOW-RS status handling per Table 10.5.3-1;
/// UPS-RS methods, resources and status codes per Tables 11.3-1, 11.4.3-1, 11.6.3-1,
/// 11.7.3-1, 11.8.3-1, 11.10.1-2 and 11.10.3-1; Transaction UID rule per PS3.4 CC.2.1.2.
///
/// Reference: PS3.18 Section 10.4 - Retrieve Transaction (WADO-RS)
///
/// ## Example Usage
///
/// ```swift
/// let config = try DICOMwebConfiguration(
///     baseURLString: "https://pacs.example.com/dicom-web",
///     authentication: .bearer(token: "your-token")
/// )
/// let client = DICOMwebClient(configuration: config)
///
/// // Retrieve a study
/// let instances = try await client.retrieveStudy(studyUID: "1.2.3.4.5")
///
/// // Retrieve metadata
/// let metadata = try await client.retrieveStudyMetadata(studyUID: "1.2.3.4.5")
///
/// // Retrieve a rendered image
/// let image = try await client.retrieveRenderedInstance(
///     studyUID: "1.2.3.4.5",
///     seriesUID: "1.2.3.4.5.6",
///     instanceUID: "1.2.3.4.5.6.7"
/// )
/// ```
#if canImport(FoundationNetworking) || os(macOS) || os(iOS) || os(visionOS) || os(tvOS) || os(watchOS)
public final class DICOMwebClient: @unchecked Sendable {
    
    // MARK: - Types
    
    /// Progress information for downloads
    public struct RetrieveProgress: Sendable {
        /// Bytes received so far
        public let bytesReceived: Int64
        
        /// Total bytes expected (may be unknown)
        public let totalBytes: Int64?
        
        /// Instances received so far
        public let instancesReceived: Int
        
        /// Total instances expected (may be unknown)
        public let totalInstances: Int?
        
        /// Fraction completed (0.0 to 1.0)
        public var fractionCompleted: Double {
            if let total = totalBytes, total > 0 {
                return Double(bytesReceived) / Double(total)
            }
            if let total = totalInstances, total > 0 {
                return Double(instancesReceived) / Double(total)
            }
            return 0
        }
    }
    
    /// Result of a retrieve operation containing DICOM data
    public struct RetrieveResult: Sendable {
        /// The retrieved DICOM instances as raw Part 10 data
        public let instances: [Data]
        
        /// Content type of the retrieved data
        public let contentType: DICOMMediaType?
        
        /// Transfer syntax of the retrieved data
        public var transferSyntax: String? {
            return contentType?.transferSyntax
        }
    }
    
    /// Frame data result
    public struct FrameResult: Sendable {
        /// Frame number (1-based)
        public let frameNumber: Int
        
        /// Raw frame data
        public let data: Data
        
        /// Content type of the frame data
        public let contentType: DICOMMediaType?
    }
    
    /// Rendered image options
    public struct RenderOptions: Sendable {
        /// Window center for VOI LUT
        public let windowCenter: Double?
        
        /// Window width for VOI LUT
        public let windowWidth: Double?
        
        /// Viewport width in pixels
        public let viewportWidth: Int?
        
        /// Viewport height in pixels
        public let viewportHeight: Int?
        
        /// Quality (0-100) for lossy compression
        public let quality: Int?
        
        /// Desired output format
        public let format: ImageFormat
        
        /// Image format for rendered output
        public enum ImageFormat: Sendable {
            case jpeg
            case png
            case gif
            
            var mediaType: DICOMMediaType {
                switch self {
                case .jpeg: return .jpeg
                case .png: return .png
                case .gif: return .gif
                }
            }
        }
        
        /// Creates render options
        public init(
            windowCenter: Double? = nil,
            windowWidth: Double? = nil,
            viewportWidth: Int? = nil,
            viewportHeight: Int? = nil,
            quality: Int? = nil,
            format: ImageFormat = .jpeg
        ) {
            self.windowCenter = windowCenter
            self.windowWidth = windowWidth
            self.viewportWidth = viewportWidth
            self.viewportHeight = viewportHeight
            self.quality = quality
            self.format = format
        }
        
        /// Default options
        public static let `default` = RenderOptions()
        
        /// Options for thumbnails: only `viewport` applies to Thumbnail resources
        /// (PS3.18 Table 8.3.5-2), so no windowing or quality is sent.
        public static func thumbnail(size: Int = 128) -> RenderOptions {
            return RenderOptions(
                viewportWidth: size,
                viewportHeight: size,
                format: .jpeg
            )
        }
    }
    
    // MARK: - Properties
    
    /// The underlying HTTP client
    public let httpClient: HTTPClient
    
    /// The configuration for this client
    public var configuration: DICOMwebConfiguration {
        return httpClient.configuration
    }
    
    /// URL builder for this client
    public var urlBuilder: DICOMwebURLBuilder {
        return configuration.urlBuilder
    }
    
    // MARK: - Initialization
    
    /// Creates a DICOMweb client with the specified configuration
    /// - Parameter configuration: The DICOMweb configuration
    public init(configuration: DICOMwebConfiguration) {
        self.httpClient = HTTPClient(configuration: configuration)
    }
    
    /// Creates a DICOMweb client with the specified HTTP client
    /// - Parameter httpClient: The HTTP client to use
    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }
    
    // MARK: - Study Retrieval (WADO-RS)
    
    /// Retrieves all instances in a study
    ///
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - transferSyntax: Preferred transfer syntax (optional)
    /// - Returns: Retrieved DICOM instances
    /// - Throws: DICOMwebError on failure
    ///
    /// Reference: PS3.18 Section 10.4.1 - RetrieveStudy
    public func retrieveStudy(
        studyUID: String,
        transferSyntax: String? = nil
    ) async throws -> RetrieveResult {
        let url = urlBuilder.studyURL(studyUID: studyUID)
        return try await retrieveDICOM(from: url, transferSyntax: transferSyntax)
    }
    
    /// Retrieves all instances in a study as a stream
    ///
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - transferSyntax: Preferred transfer syntax (optional)
    /// - Returns: AsyncThrowingStream of DICOM instance data
    /// - Throws: DICOMwebError on failure
    public func retrieveStudyStream(
        studyUID: String,
        transferSyntax: String? = nil
    ) -> AsyncThrowingStream<Data, Error> {
        let url = urlBuilder.studyURL(studyUID: studyUID)
        return retrieveDICOMStream(from: url, transferSyntax: transferSyntax)
    }
    
    // MARK: - Series Retrieval (WADO-RS)
    
    /// Retrieves all instances in a series
    ///
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    ///   - transferSyntax: Preferred transfer syntax (optional)
    /// - Returns: Retrieved DICOM instances
    /// - Throws: DICOMwebError on failure
    ///
    /// Reference: PS3.18 Section 10.4.1 - RetrieveSeries
    public func retrieveSeries(
        studyUID: String,
        seriesUID: String,
        transferSyntax: String? = nil
    ) async throws -> RetrieveResult {
        let url = urlBuilder.seriesURL(studyUID: studyUID, seriesUID: seriesUID)
        return try await retrieveDICOM(from: url, transferSyntax: transferSyntax)
    }
    
    /// Retrieves all instances in a series as a stream
    ///
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    ///   - transferSyntax: Preferred transfer syntax (optional)
    /// - Returns: AsyncThrowingStream of DICOM instance data
    public func retrieveSeriesStream(
        studyUID: String,
        seriesUID: String,
        transferSyntax: String? = nil
    ) -> AsyncThrowingStream<Data, Error> {
        let url = urlBuilder.seriesURL(studyUID: studyUID, seriesUID: seriesUID)
        return retrieveDICOMStream(from: url, transferSyntax: transferSyntax)
    }
    
    // MARK: - Instance Retrieval (WADO-RS)
    
    /// Retrieves a specific instance
    ///
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    ///   - instanceUID: The SOP Instance UID
    ///   - transferSyntax: Preferred transfer syntax (optional)
    /// - Returns: Retrieved DICOM instance data
    /// - Throws: DICOMwebError on failure
    ///
    /// Reference: PS3.18 Section 10.4.1 - RetrieveInstance
    public func retrieveInstance(
        studyUID: String,
        seriesUID: String,
        instanceUID: String,
        transferSyntax: String? = nil
    ) async throws -> Data {
        let url = urlBuilder.instanceURL(
            studyUID: studyUID,
            seriesUID: seriesUID,
            instanceUID: instanceUID
        )
        let result = try await retrieveDICOM(from: url, transferSyntax: transferSyntax)
        guard let first = result.instances.first else {
            throw DICOMwebError.notFound(resource: "Instance \(instanceUID)")
        }
        return first
    }
    
    // MARK: - Metadata Retrieval (WADO-RS)
    
    /// Retrieves metadata for a study
    ///
    /// - Parameter studyUID: The Study Instance UID
    /// - Returns: Array of DICOM JSON objects (one per instance)
    /// - Throws: DICOMwebError on failure
    ///
    /// Reference: PS3.18 Section 10.4.1.1 - RetrieveStudyMetadata
    public func retrieveStudyMetadata(studyUID: String) async throws -> [[String: Any]] {
        let url = urlBuilder.studyMetadataURL(studyUID: studyUID)
        return try await retrieveMetadata(from: url)
    }
    
    /// Retrieves metadata for a series
    ///
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    /// - Returns: Array of DICOM JSON objects (one per instance)
    /// - Throws: DICOMwebError on failure
    ///
    /// Reference: PS3.18 Section 10.4.1.1 - RetrieveSeriesMetadata
    public func retrieveSeriesMetadata(
        studyUID: String,
        seriesUID: String
    ) async throws -> [[String: Any]] {
        let url = urlBuilder.seriesMetadataURL(studyUID: studyUID, seriesUID: seriesUID)
        return try await retrieveMetadata(from: url)
    }
    
    /// Retrieves metadata for an instance
    ///
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    ///   - instanceUID: The SOP Instance UID
    /// - Returns: Array with single DICOM JSON object
    /// - Throws: DICOMwebError on failure
    ///
    /// Reference: PS3.18 Section 10.4.1.1 - RetrieveInstanceMetadata
    public func retrieveInstanceMetadata(
        studyUID: String,
        seriesUID: String,
        instanceUID: String
    ) async throws -> [[String: Any]] {
        let url = urlBuilder.instanceMetadataURL(
            studyUID: studyUID,
            seriesUID: seriesUID,
            instanceUID: instanceUID
        )
        return try await retrieveMetadata(from: url)
    }
    
    // MARK: - Frame Retrieval (WADO-RS)
    
    /// Retrieves specific frames from an instance
    ///
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    ///   - instanceUID: The SOP Instance UID
    ///   - frames: Array of frame numbers (1-based)
    ///   - transferSyntax: Preferred transfer syntax (optional)
    /// - Returns: Array of frame data
    /// - Throws: DICOMwebError on failure
    ///
    /// Reference: PS3.18 Section 10.4.1 - RetrieveFrames
    public func retrieveFrames(
        studyUID: String,
        seriesUID: String,
        instanceUID: String,
        frames: [Int],
        transferSyntax: String? = nil
    ) async throws -> [FrameResult] {
        guard !frames.isEmpty else {
            throw DICOMwebError.badRequest(message: "At least one frame number is required")
        }
        
        // Validate frame numbers are positive
        for frame in frames {
            if frame < 1 {
                throw DICOMwebError.invalidFrameNumber(frame: frame, maxFrame: nil)
            }
        }
        
        let url = urlBuilder.framesURL(
            studyUID: studyUID,
            seriesUID: seriesUID,
            instanceUID: instanceUID,
            frames: frames
        )
        
        let headers = buildFramesAcceptHeader(transferSyntax: transferSyntax)
        let response = try await httpClient.get(url, headers: headers)
        
        // Parse multipart response
        let contentType = response.header("Content-Type") ?? ""
        let parts = try parseMultipartResponse(data: response.body, contentType: contentType)
        
        // Build frame results - use requested frame numbers for corresponding parts
        // WADO-RS spec states frames are returned in the order requested
        return zip(frames, parts).map { frameNumber, part in
            FrameResult(
                frameNumber: frameNumber,
                data: part.body,
                contentType: part.contentType
            )
        }
    }
    
    /// Retrieves a single frame from an instance
    ///
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    ///   - instanceUID: The SOP Instance UID
    ///   - frame: Frame number (1-based)
    ///   - transferSyntax: Preferred transfer syntax (optional)
    /// - Returns: Frame data
    /// - Throws: DICOMwebError on failure
    public func retrieveFrame(
        studyUID: String,
        seriesUID: String,
        instanceUID: String,
        frame: Int,
        transferSyntax: String? = nil
    ) async throws -> Data {
        let results = try await retrieveFrames(
            studyUID: studyUID,
            seriesUID: seriesUID,
            instanceUID: instanceUID,
            frames: [frame],
            transferSyntax: transferSyntax
        )
        guard let first = results.first else {
            throw DICOMwebError.invalidFrameNumber(frame: frame, maxFrame: nil)
        }
        return first.data
    }
    
    // MARK: - Rendered Image Retrieval (WADO-RS)
    
    /// Retrieves a rendered representation of an instance
    ///
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    ///   - instanceUID: The SOP Instance UID
    ///   - options: Render options (windowing, viewport, format)
    /// - Returns: Rendered image data
    /// - Throws: DICOMwebError on failure
    ///
    /// Reference: PS3.18 Section 10.4.1 - RetrieveRenderedInstance
    public func retrieveRenderedInstance(
        studyUID: String,
        seriesUID: String,
        instanceUID: String,
        options: RenderOptions = .default
    ) async throws -> Data {
        var url = urlBuilder.instanceRenderedURL(
            studyUID: studyUID,
            seriesUID: seriesUID,
            instanceUID: instanceUID
        )
        url = applyRenderOptions(to: url, options: options)
        
        let headers = ["Accept": options.format.mediaType.description]
        let response = try await httpClient.get(url, headers: headers)
        return response.body
    }
    
    /// Retrieves rendered representations of specific frames
    ///
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    ///   - instanceUID: The SOP Instance UID
    ///   - frames: Array of frame numbers (1-based)
    ///   - options: Render options
    /// - Returns: Array of rendered frame data
    /// - Throws: DICOMwebError on failure
    ///
    /// Reference: PS3.18 Section 10.4.1 - RetrieveRenderedFrames
    public func retrieveRenderedFrames(
        studyUID: String,
        seriesUID: String,
        instanceUID: String,
        frames: [Int],
        options: RenderOptions = .default
    ) async throws -> [Data] {
        guard !frames.isEmpty else {
            throw DICOMwebError.badRequest(message: "At least one frame number is required")
        }
        
        var url = urlBuilder.framesRenderedURL(
            studyUID: studyUID,
            seriesUID: seriesUID,
            instanceUID: instanceUID,
            frames: frames
        )
        url = applyRenderOptions(to: url, options: options)
        
        let headers = ["Accept": options.format.mediaType.description]
        let response = try await httpClient.get(url, headers: headers)
        
        // For single frame, return directly
        if frames.count == 1 {
            return [response.body]
        }
        
        // For multiple frames, parse multipart response
        let contentType = response.header("Content-Type") ?? ""
        if contentType.contains("multipart") {
            let parts = try parseMultipartResponse(data: response.body, contentType: contentType)
            return parts.map { $0.body }
        } else {
            return [response.body]
        }
    }
    
    // MARK: - Thumbnail Retrieval (WADO-RS)
    
    /// Retrieves a thumbnail for a study
    ///
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - options: Render options (viewport size controls thumbnail size)
    /// - Returns: Thumbnail image data
    /// - Throws: DICOMwebError on failure
    ///
    /// Reference: PS3.18 Section 10.4.1 - RetrieveStudyThumbnail
    public func retrieveStudyThumbnail(
        studyUID: String,
        options: RenderOptions = .thumbnail()
    ) async throws -> Data {
        var url = urlBuilder.studyThumbnailURL(studyUID: studyUID)
        url = applyRenderOptions(to: url, options: options)
        
        let headers = ["Accept": options.format.mediaType.description]
        let response = try await httpClient.get(url, headers: headers)
        return response.body
    }
    
    /// Retrieves a thumbnail for a series
    ///
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    ///   - options: Render options
    /// - Returns: Thumbnail image data
    /// - Throws: DICOMwebError on failure
    ///
    /// Reference: PS3.18 Section 10.4.1 - RetrieveSeriesThumbnail
    public func retrieveSeriesThumbnail(
        studyUID: String,
        seriesUID: String,
        options: RenderOptions = .thumbnail()
    ) async throws -> Data {
        var url = urlBuilder.seriesThumbnailURL(studyUID: studyUID, seriesUID: seriesUID)
        url = applyRenderOptions(to: url, options: options)
        
        let headers = ["Accept": options.format.mediaType.description]
        let response = try await httpClient.get(url, headers: headers)
        return response.body
    }
    
    /// Retrieves a thumbnail for an instance
    ///
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    ///   - instanceUID: The SOP Instance UID
    ///   - options: Render options
    /// - Returns: Thumbnail image data
    /// - Throws: DICOMwebError on failure
    ///
    /// Reference: PS3.18 Section 10.4.1 - RetrieveInstanceThumbnail
    public func retrieveInstanceThumbnail(
        studyUID: String,
        seriesUID: String,
        instanceUID: String,
        options: RenderOptions = .thumbnail()
    ) async throws -> Data {
        var url = urlBuilder.instanceThumbnailURL(
            studyUID: studyUID,
            seriesUID: seriesUID,
            instanceUID: instanceUID
        )
        url = applyRenderOptions(to: url, options: options)
        
        let headers = ["Accept": options.format.mediaType.description]
        let response = try await httpClient.get(url, headers: headers)
        return response.body
    }
    
    // MARK: - Bulk Data Retrieval (WADO-RS)
    
    /// Retrieves bulk data by URI
    ///
    /// - Parameters:
    ///   - uri: The bulk data URI from a metadata response
    ///   - range: Optional byte range for partial retrieval
    /// - Returns: Bulk data
    /// - Throws: DICOMwebError on failure
    ///
    /// Reference: PS3.18 Section 10.4.1 - RetrieveBulkdata
    public func retrieveBulkData(
        uri: String,
        range: Range<Int>? = nil
    ) async throws -> Data {
        guard let url = URL(string: uri) else {
            throw DICOMwebError.invalidBulkDataReference(uri: uri)
        }
        
        var headers: [String: String] = [:]
        
        if let range = range {
            headers["Range"] = "bytes=\(range.lowerBound)-\(range.upperBound - 1)"
        }
        
        let response = try await httpClient.get(url, headers: headers)
        return response.body
    }
    
    /// Retrieves bulk data for a specific attribute
    ///
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    ///   - instanceUID: The SOP Instance UID
    ///   - attributePath: The attribute tag path (e.g., "7FE00010" for pixel data)
    /// - Returns: Bulk data
    /// - Throws: DICOMwebError on failure
    public func retrieveAttributeBulkData(
        studyUID: String,
        seriesUID: String,
        instanceUID: String,
        attributePath: String
    ) async throws -> Data {
        let url = urlBuilder.bulkdataURL(
            studyUID: studyUID,
            seriesUID: seriesUID,
            instanceUID: instanceUID,
            attributePath: attributePath
        )
        
        let response = try await httpClient.get(url)
        return response.body
    }
    
    // MARK: - Private Methods
    
    /// Builds Accept header for DICOM retrieval
    private func buildAcceptHeader(transferSyntax: String? = nil) -> [String: String] {
        var accept = "multipart/related; type=\"application/dicom\""
        
        if let ts = transferSyntax {
            accept += "; transfer-syntax=\(ts)"
        } else if let preferred = configuration.preferredTransferSyntaxes.first {
            accept += "; transfer-syntax=\(preferred)"
        }
        
        return ["Accept": accept]
    }
    
    /// Builds the Accept header for a Frames (pixel data) resource.
    ///
    /// PS3.18 Table 10.4.4-1: pixel data is `multipart/related; type="application/octet-stream"`
    /// (uncompressed, Table 8.7.3-4) or a compressed bulk data media type of Table 8.7.3-5;
    /// `application/dicom` is not a pixel data representation. A transfer syntax picks the
    /// media type of Table 8.7.3-5 and is sent as its transfer-syntax parameter.
    private func buildFramesAcceptHeader(transferSyntax: String? = nil) -> [String: String] {
        let requested = transferSyntax ?? configuration.preferredTransferSyntaxes.first
        var mediaType = DICOMMediaType.octetStream
        if let ts = requested, let bulk = DICOMMediaType.bulkDataMediaType(forTransferSyntax: ts) {
            mediaType = bulk
        }
        var accept = "multipart/related; type=\"\(mediaType.description)\""
        if let ts = requested {
            accept += "; transfer-syntax=\(ts)"
        }
        return ["Accept": accept]
    }
    
    /// Retrieves DICOM objects from a URL
    private func retrieveDICOM(
        from url: URL,
        transferSyntax: String?
    ) async throws -> RetrieveResult {
        let headers = buildAcceptHeader(transferSyntax: transferSyntax)
        let response = try await httpClient.get(url, headers: headers)
        
        // Parse multipart response
        let contentType = response.header("Content-Type") ?? ""
        let parts = try parseMultipartResponse(data: response.body, contentType: contentType)
        
        return RetrieveResult(
            instances: parts.map { $0.body },
            contentType: parts.first?.contentType
        )
    }
    
    /// Retrieves DICOM objects as a stream
    private func retrieveDICOMStream(
        from url: URL,
        transferSyntax: String?
    ) -> AsyncThrowingStream<Data, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let headers = buildAcceptHeader(transferSyntax: transferSyntax)
                    let response = try await httpClient.get(url, headers: headers)
                    
                    let contentType = response.header("Content-Type") ?? ""
                    let parts = try parseMultipartResponse(data: response.body, contentType: contentType)
                    
                    for part in parts {
                        // Check for cancellation
                        try Task.checkCancellation()
                        continuation.yield(part.body)
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Retrieves metadata from a URL
    private func retrieveMetadata(from url: URL) async throws -> [[String: Any]] {
        let headers = ["Accept": DICOMMediaType.dicomJSON.description]
        let response = try await httpClient.get(url, headers: headers)
        
        guard let json = try JSONSerialization.jsonObject(with: response.body) as? [[String: Any]] else {
            throw DICOMwebError.invalidJSON(reason: "Expected array of DICOM JSON objects")
        }
        
        return json
    }
    
    /// Parses a multipart MIME response
    private func parseMultipartResponse(data: Data, contentType: String) throws -> [MultipartMIME.Part] {
        // If content type is not multipart, return single part
        // MIME types are case-insensitive per RFC 2045 §5.1
        guard contentType.lowercased().contains("multipart") else {
            let mediaType = DICOMMediaType.parse(contentType) ?? .octetStream
            return [MultipartMIME.Part(contentType: mediaType, body: data)]
        }
        
        // Parse multipart
        let multipart = try MultipartMIME.parse(data: data, contentType: contentType)
        return multipart.parts
    }
    
    /// Applies render options to a URL as the query parameters of PS3.18 Table 8.3.5-1
    /// (`window=center,width,function`, `viewport=vw,vh`, `quality`)
    private func applyRenderOptions(to url: URL, options: RenderOptions) -> URL {
        let params = DICOMwebURLBuilder.renderedParameters(
            windowCenter: options.windowCenter, windowWidth: options.windowWidth,
            viewportWidth: options.viewportWidth, viewportHeight: options.viewportHeight,
            quality: options.quality)
        return DICOMwebURLBuilder.appendQueryParameters(to: url, parameters: params)
    }
}

// MARK: - Convenience Extensions

extension DICOMwebClient {
    /// Retrieves metadata for a study and decodes it using DICOMJSONDecoder
    ///
    /// - Parameter studyUID: The Study Instance UID
    /// - Returns: Array of DataElement arrays (one per instance)
    /// - Throws: DICOMwebError on failure
    public func retrieveStudyMetadataAsElements(studyUID: String) async throws -> [[DataElement]] {
        let url = urlBuilder.studyMetadataURL(studyUID: studyUID)
        let headers = ["Accept": DICOMMediaType.dicomJSON.description]
        let response = try await httpClient.get(url, headers: headers)
        
        let decoder = DICOMJSONDecoder()
        return try decoder.decodeMultiple(response.body)
    }
    
    /// Retrieves metadata for a series and decodes it using DICOMJSONDecoder
    ///
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    /// - Returns: Array of DataElement arrays (one per instance)
    /// - Throws: DICOMwebError on failure
    public func retrieveSeriesMetadataAsElements(
        studyUID: String,
        seriesUID: String
    ) async throws -> [[DataElement]] {
        let url = urlBuilder.seriesMetadataURL(studyUID: studyUID, seriesUID: seriesUID)
        let headers = ["Accept": DICOMMediaType.dicomJSON.description]
        let response = try await httpClient.get(url, headers: headers)
        
        let decoder = DICOMJSONDecoder()
        return try decoder.decodeMultiple(response.body)
    }
    
    /// Retrieves metadata for an instance and decodes it using DICOMJSONDecoder
    ///
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    ///   - instanceUID: The SOP Instance UID
    /// - Returns: Array of DataElement
    /// - Throws: DICOMwebError on failure
    public func retrieveInstanceMetadataAsElements(
        studyUID: String,
        seriesUID: String,
        instanceUID: String
    ) async throws -> [DataElement] {
        let url = urlBuilder.instanceMetadataURL(
            studyUID: studyUID,
            seriesUID: seriesUID,
            instanceUID: instanceUID
        )
        let headers = ["Accept": DICOMMediaType.dicomJSON.description]
        let response = try await httpClient.get(url, headers: headers)
        
        let decoder = DICOMJSONDecoder()
        let arrays = try decoder.decodeMultiple(response.body)
        return arrays.first ?? []
    }
}

// MARK: - QIDO-RS Query Methods

extension DICOMwebClient {
    
    // MARK: - Search Studies (QIDO-RS)
    
    /// Searches for studies matching the query criteria
    ///
    /// - Parameters:
    ///   - query: Query parameters (optional, returns all studies if empty)
    /// - Returns: QIDO study results with pagination info
    /// - Throws: DICOMwebError on failure
    ///
    /// Reference: PS3.18 Section 10.6.1 - SearchForStudies
    ///
    /// ## Example Usage
    ///
    /// ```swift
    /// // Search for all CT studies in 2024
    /// let query = QIDOQuery()
    ///     .modality("CT")
    ///     .studyDate(from: "20240101", to: "20241231")
    ///     .limit(10)
    ///
    /// let results = try await client.searchStudies(query: query)
    /// for study in results.results {
    ///     print("Study: \(study.studyInstanceUID ?? "unknown")")
    /// }
    /// ```
    public func searchStudies(query: QIDOQuery = QIDOQuery()) async throws -> QIDOStudyResults {
        let url = urlBuilder.searchStudiesURL(parameters: query.toParameters())
        return try await performQIDOQuery(url: url, query: query)
    }
    
    /// Searches for studies with raw parameters
    ///
    /// - Parameter parameters: Raw query parameters dictionary
    /// - Returns: QIDO study results
    /// - Throws: DICOMwebError on failure
    public func searchStudies(parameters: [String: String]) async throws -> QIDOStudyResults {
        let url = urlBuilder.searchStudiesURL(parameters: parameters)
        return try await performQIDOQuery(url: url, query: QIDOQuery(parameters: parameters))
    }
    
    // MARK: - Search Series (QIDO-RS)
    
    /// Searches for series within a specific study
    ///
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - query: Query parameters (optional)
    /// - Returns: QIDO series results with pagination info
    /// - Throws: DICOMwebError on failure
    ///
    /// Reference: PS3.18 Section 10.6.1 - SearchForSeries
    ///
    /// ## Example Usage
    ///
    /// ```swift
    /// let results = try await client.searchSeries(
    ///     studyUID: "1.2.3.4.5",
    ///     query: QIDOQuery().modality("CT")
    /// )
    /// ```
    public func searchSeries(
        studyUID: String,
        query: QIDOQuery = QIDOQuery()
    ) async throws -> QIDOSeriesResults {
        let url = urlBuilder.searchSeriesURL(studyUID: studyUID, parameters: query.toParameters())
        return try await performQIDOQuery(url: url, query: query)
    }
    
    /// Searches for series across all studies
    ///
    /// - Parameter query: Query parameters
    /// - Returns: QIDO series results with pagination info
    /// - Throws: DICOMwebError on failure
    ///
    /// Note: Some servers may not support cross-study series searches.
    public func searchAllSeries(query: QIDOQuery = QIDOQuery()) async throws -> QIDOSeriesResults {
        let url = DICOMwebURLBuilder.appendQueryParameters(
            to: baseSeriesURL,
            parameters: query.toParameters()
        )
        return try await performQIDOQuery(url: url, query: query)
    }
    
    // MARK: - Search Instances (QIDO-RS)
    
    /// Searches for instances within a specific series
    ///
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    ///   - query: Query parameters (optional)
    /// - Returns: QIDO instance results with pagination info
    /// - Throws: DICOMwebError on failure
    ///
    /// Reference: PS3.18 Section 10.6.1 - SearchForInstances
    ///
    /// ## Example Usage
    ///
    /// ```swift
    /// let results = try await client.searchInstances(
    ///     studyUID: "1.2.3.4.5",
    ///     seriesUID: "1.2.3.4.5.6",
    ///     query: QIDOQuery().limit(50)
    /// )
    /// ```
    public func searchInstances(
        studyUID: String,
        seriesUID: String,
        query: QIDOQuery = QIDOQuery()
    ) async throws -> QIDOInstanceResults {
        let url = urlBuilder.searchInstancesURL(
            studyUID: studyUID,
            seriesUID: seriesUID,
            parameters: query.toParameters()
        )
        return try await performQIDOQuery(url: url, query: query)
    }
    
    /// Searches for instances within a specific study (across all series)
    ///
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - query: Query parameters (optional)
    /// - Returns: QIDO instance results with pagination info
    /// - Throws: DICOMwebError on failure
    public func searchInstances(
        studyUID: String,
        query: QIDOQuery = QIDOQuery()
    ) async throws -> QIDOInstanceResults {
        let url = DICOMwebURLBuilder.appendQueryParameters(
            to: urlBuilder.instancesInStudyURL(studyUID: studyUID),
            parameters: query.toParameters()
        )
        return try await performQIDOQuery(url: url, query: query)
    }
    
    /// Searches for instances across all studies
    ///
    /// - Parameter query: Query parameters
    /// - Returns: QIDO instance results with pagination info
    /// - Throws: DICOMwebError on failure
    ///
    /// Note: Some servers may not support cross-study instance searches.
    public func searchAllInstances(query: QIDOQuery = QIDOQuery()) async throws -> QIDOInstanceResults {
        let url = DICOMwebURLBuilder.appendQueryParameters(
            to: baseInstancesURL,
            parameters: query.toParameters()
        )
        return try await performQIDOQuery(url: url, query: query)
    }
    
    // MARK: - Private Helper Methods
    
    /// Base URL for series search across all studies
    private var baseSeriesURL: URL {
        return configuration.baseURL.appendingPathComponent("series")
    }
    
    /// Base URL for instances search across all studies
    private var baseInstancesURL: URL {
        return configuration.baseURL.appendingPathComponent("instances")
    }
    
    /// Performs a QIDO-RS query and parses results
    private func performQIDOQuery<T: QIDOResult>(
        url: URL,
        query: QIDOQuery
    ) async throws -> QIDOResults<T> {
        let headers = ["Accept": DICOMMediaType.dicomJSON.description]
        let response = try await httpClient.get(url, headers: headers)
        
        // Parse JSON array response
        guard let jsonArray = try JSONSerialization.jsonObject(with: response.body) as? [[String: Any]] else {
            throw DICOMwebError.invalidJSON(reason: "Expected array of DICOM JSON objects")
        }
        
        // Extract total count from headers if available
        let totalCount: Int?
        if let totalCountHeader = response.header("X-Total-Count") {
            totalCount = Int(totalCountHeader)
        } else {
            totalCount = nil
        }
        
        // Parse limit and offset from query
        let params = query.toParameters()
        let limit = params[DICOMwebURLBuilder.QueryParameter.limit].flatMap { Int($0) }
        let offset = params[DICOMwebURLBuilder.QueryParameter.offset].flatMap { Int($0) } ?? 0
        
        // Create result objects
        let results: [T] = jsonArray.map { T.init(attributes: $0) }
        
        return QIDOResults(
            results: results,
            totalCount: totalCount,
            offset: offset,
            limit: limit
        )
    }
}

// MARK: - STOW-RS Store Methods

extension DICOMwebClient {
    
    // MARK: - Types
    
    /// Progress information for store operations
    public struct StoreProgress: Sendable {
        /// Number of instances stored so far
        public let instancesStored: Int
        
        /// Total number of instances to store
        public let totalInstances: Int
        
        /// Bytes uploaded so far
        public let bytesUploaded: Int64
        
        /// Total bytes to upload (may be unknown)
        public let totalBytes: Int64?
        
        /// Fraction completed (0.0 to 1.0)
        public var fractionCompleted: Double {
            if totalInstances > 0 {
                return Double(instancesStored) / Double(totalInstances)
            }
            if let total = totalBytes, total > 0 {
                return Double(bytesUploaded) / Double(total)
            }
            return 0
        }
    }
    
    /// Options for store operations
    public struct StoreOptions: Sendable {
        /// Maximum number of instances per request
        /// Set to nil for unlimited (all instances in single request)
        public let batchSize: Int?
        
        /// Continue uploading remaining instances if some fail
        public let continueOnError: Bool
        
        /// Creates store options
        /// - Parameters:
        ///   - batchSize: Maximum instances per request (nil for unlimited)
        ///   - continueOnError: Whether to continue on partial failure
        public init(batchSize: Int? = nil, continueOnError: Bool = true) {
            self.batchSize = batchSize
            self.continueOnError = continueOnError
        }
        
        /// Default options (single request, continue on error)
        public static let `default` = StoreOptions()
    }
    
    // MARK: - Store Single Instance
    
    /// Stores a single DICOM instance
    ///
    /// - Parameters:
    ///   - data: The DICOM Part 10 file data
    ///   - studyUID: Optional Study Instance UID (instances will be added to this study)
    /// - Returns: Store response with result information
    /// - Throws: DICOMwebError on failure
    ///
    /// Reference: PS3.18 Section 10.5 - STOW-RS
    ///
    /// ## Example Usage
    ///
    /// ```swift
    /// let dicomData = try Data(contentsOf: dicomFileURL)
    /// let response = try await client.storeInstance(data: dicomData)
    ///
    /// if response.isFullSuccess {
    ///     print("Stored instance: \(response.storedInstances.first?.sopInstanceUID ?? "unknown")")
    /// }
    /// ```
    public func storeInstance(
        data: Data,
        studyUID: String? = nil
    ) async throws -> STOWResponse {
        return try await storeInstances(instances: [data], studyUID: studyUID)
    }
    
    // MARK: - Store Multiple Instances
    
    /// Stores multiple DICOM instances
    ///
    /// - Parameters:
    ///   - instances: Array of DICOM Part 10 file data
    ///   - studyUID: Optional Study Instance UID (all instances will be added to this study)
    ///   - options: Store options (batch size, error handling)
    /// - Returns: Combined store response with all results
    /// - Throws: DICOMwebError on complete failure
    ///
    /// Reference: PS3.18 Section 10.5 - STOW-RS
    ///
    /// ## Example Usage
    ///
    /// ```swift
    /// let instances = try dicomFiles.map { try Data(contentsOf: $0) }
    /// let response = try await client.storeInstances(
    ///     instances: instances,
    ///     studyUID: "1.2.3.4.5"
    /// )
    ///
    /// print("Stored: \(response.successCount), Failed: \(response.failureCount)")
    /// ```
    public func storeInstances(
        instances: [Data],
        studyUID: String? = nil,
        options: StoreOptions = .default
    ) async throws -> STOWResponse {
        guard !instances.isEmpty else {
            return STOWResponse()
        }
        
        // Determine batch size
        let batchSize = options.batchSize ?? instances.count
        
        // If all instances fit in one batch, do a single request
        if instances.count <= batchSize {
            return try await performStoreRequest(instances: instances, studyUID: studyUID)
        }
        
        // Otherwise, batch the requests
        var allStoredInstances: [STOWResponse.InstanceResult] = []
        var allFailedInstances: [STOWResponse.InstanceFailure] = []
        var allWarnings: [STOWResponse.Warning] = []
        var lastRetrieveURL: String?
        
        // Split into batches
        let batches = stride(from: 0, to: instances.count, by: batchSize).map {
            Array(instances[$0..<min($0 + batchSize, instances.count)])
        }
        
        for batch in batches {
            do {
                let response = try await performStoreRequest(instances: batch, studyUID: studyUID)
                allStoredInstances.append(contentsOf: response.storedInstances)
                allFailedInstances.append(contentsOf: response.failedInstances)
                allWarnings.append(contentsOf: response.warnings)
                if let url = response.retrieveURL {
                    lastRetrieveURL = url
                }
            } catch {
                if !options.continueOnError {
                    throw error
                }
                // On error, mark all instances in this batch as failed
                for _ in batch {
                    allFailedInstances.append(STOWResponse.InstanceFailure(
                        failureDescription: error.localizedDescription
                    ))
                }
            }
        }
        
        return STOWResponse(
            storedInstances: allStoredInstances,
            failedInstances: allFailedInstances,
            warnings: allWarnings,
            retrieveURL: lastRetrieveURL
        )
    }
    
    /// Stores multiple DICOM instances with progress reporting
    ///
    /// - Parameters:
    ///   - instances: Array of DICOM Part 10 file data
    ///   - studyUID: Optional Study Instance UID
    ///   - options: Store options
    /// - Returns: AsyncThrowingStream of progress updates and final response
    ///
    /// ## Example Usage
    ///
    /// ```swift
    /// for try await event in client.storeInstancesWithProgress(instances: dicomFiles) {
    ///     switch event {
    ///     case .progress(let progress):
    ///         print("Progress: \(Int(progress.fractionCompleted * 100))%")
    ///     case .completed(let response):
    ///         print("Complete: \(response.successCount) stored")
    ///     }
    /// }
    /// ```
    public func storeInstancesWithProgress(
        instances: [Data],
        studyUID: String? = nil,
        options: StoreOptions = .default
    ) -> AsyncThrowingStream<StoreEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard !instances.isEmpty else {
                        continuation.yield(.completed(STOWResponse()))
                        continuation.finish()
                        return
                    }
                    
                    let batchSize = options.batchSize ?? instances.count
                    let batches = stride(from: 0, to: instances.count, by: batchSize).map {
                        Array(instances[$0..<min($0 + batchSize, instances.count)])
                    }
                    
                    var allStoredInstances: [STOWResponse.InstanceResult] = []
                    var allFailedInstances: [STOWResponse.InstanceFailure] = []
                    var allWarnings: [STOWResponse.Warning] = []
                    var lastRetrieveURL: String?
                    var instancesProcessed = 0
                    
                    let totalBytes = Int64(instances.reduce(0) { $0 + $1.count })
                    var bytesUploaded: Int64 = 0
                    
                    for batch in batches {
                        try Task.checkCancellation()
                        
                        let batchBytes = Int64(batch.reduce(0) { $0 + $1.count })
                        
                        do {
                            let response = try await performStoreRequest(instances: batch, studyUID: studyUID)
                            allStoredInstances.append(contentsOf: response.storedInstances)
                            allFailedInstances.append(contentsOf: response.failedInstances)
                            allWarnings.append(contentsOf: response.warnings)
                            if let url = response.retrieveURL {
                                lastRetrieveURL = url
                            }
                        } catch {
                            if !options.continueOnError {
                                throw error
                            }
                            for _ in batch {
                                allFailedInstances.append(STOWResponse.InstanceFailure(
                                    failureDescription: error.localizedDescription
                                ))
                            }
                        }
                        
                        instancesProcessed += batch.count
                        bytesUploaded += batchBytes
                        
                        let progress = StoreProgress(
                            instancesStored: instancesProcessed,
                            totalInstances: instances.count,
                            bytesUploaded: bytesUploaded,
                            totalBytes: totalBytes
                        )
                        continuation.yield(.progress(progress))
                    }
                    
                    let finalResponse = STOWResponse(
                        storedInstances: allStoredInstances,
                        failedInstances: allFailedInstances,
                        warnings: allWarnings,
                        retrieveURL: lastRetrieveURL
                    )
                    continuation.yield(.completed(finalResponse))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Event types for progress reporting
    public enum StoreEvent: Sendable {
        /// Progress update
        case progress(StoreProgress)
        
        /// Store operation completed
        case completed(STOWResponse)
    }
    
    // MARK: - Private Methods
    
    /// Performs a single STOW-RS request
    private func performStoreRequest(
        instances: [Data],
        studyUID: String?
    ) async throws -> STOWResponse {
        // Build URL
        let url: URL
        if let studyUID = studyUID {
            url = urlBuilder.storeURL(studyUID: studyUID)
        } else {
            url = urlBuilder.storeURL
        }
        
        // Build multipart body
        let multipart = buildMultipartRequest(instances: instances)
        let body = multipart.encode()
        
        // Build headers
        let headers: [String: String] = [
            "Content-Type": multipart.contentType.description,
            "Accept": DICOMMediaType.dicomJSON.description
        ]
        
        // Execute request
        let response = try await httpClient.post(url, body: body, headers: headers)
        
        // Parse response based on status code
        switch response.statusCode {
        case 200:
            // Full success - parse response body
            return try parseSTOWResponse(data: response.body)
            
        case 202:
            // Partial success (some warnings or failures)
            return try parseSTOWResponse(data: response.body)
            
        case 409:
            // Conflict - typically instance already exists
            let parsed = try? parseSTOWResponse(data: response.body)
            if let parsed = parsed, !parsed.failedInstances.isEmpty {
                return parsed
            }
            throw DICOMwebError.conflict(message: String(data: response.body, encoding: .utf8))
            
        default:
            // Other errors are already handled by HTTPClient
            throw DICOMwebError.fromHTTPStatus(
                response.statusCode,
                message: String(data: response.body, encoding: .utf8)
            )
        }
    }
    
    /// Builds a multipart request body for STOW-RS
    private func buildMultipartRequest(instances: [Data]) -> MultipartMIME {
        var builder = MultipartMIME.builder()
            .withRootType(.dicom)
        
        for instance in instances {
            builder = builder.addDICOM(instance)
        }
        
        return builder.build()
    }
    
    /// Parses a STOW-RS JSON response
    private func parseSTOWResponse(data: Data) throws -> STOWResponse {
        // Empty response is considered success with no details
        if data.isEmpty {
            return STOWResponse()
        }
        
        // Parse JSON
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            // If not valid JSON, return empty success
            return STOWResponse()
        }
        
        // Response can be a single object or array
        if let jsonObject = json as? [String: Any] {
            return try STOWResponse.parse(json: jsonObject)
        } else if let jsonArray = json as? [[String: Any]], let first = jsonArray.first {
            return try STOWResponse.parse(json: first)
        } else {
            return STOWResponse()
        }
    }
    
    // MARK: - UPS-RS Methods (Unified Procedure Step)
    
    /// Searches for workitems and returns the matches as the DICOM JSON Model objects
    /// the origin server sent (PS3.18 F.2), unparsed — for `--format dicom-json`.
    ///
    /// - Parameter query: The UPS query parameters
    /// - Returns: One DICOM JSON Model object per matching workitem (empty if none)
    /// - Throws: DICOMwebError on failure
    ///
    /// Reference: PS3.18 Section 11.9 - Search Transaction; Annex F.2
    public func searchWorkitemsDICOMJSON(query: UPSQuery = UPSQuery()) async throws -> [[String: Any]] {
        let url = urlBuilder.searchWorkitemsURL(parameters: query.toParameters())
        let request = HTTPClient.Request(
            url: url,
            method: .get,
            headers: ["Accept": DICOMMediaType.dicomJSON.description]
        )
        let response: HTTPClient.Response
        do {
            response = try await httpClient.execute(request)
        } catch let error as DICOMwebError {
            if case .notFound = error {
                return []
            }
            throw error
        }
        if response.body.isEmpty {
            return []
        }
        guard let jsonArray = try? JSONSerialization.jsonObject(with: response.body) as? [[String: Any]] else {
            throw DICOMwebError.invalidJSON(reason: "Expected JSON array of workitem objects")
        }
        return jsonArray
    }

    /// Searches for workitems matching the query
    ///
    /// - Parameter query: The UPS query parameters
    /// - Returns: Query results with matching workitems
    /// - Throws: DICOMwebError on failure
    ///
    /// Reference: PS3.18 Section 11.9 - Search Transaction
    public func searchWorkitems(query: UPSQuery = UPSQuery()) async throws -> UPSQueryResult {
        let url = urlBuilder.searchWorkitemsURL(parameters: query.toParameters())
        
        let request = HTTPClient.Request(
            url: url,
            method: .get,
            headers: ["Accept": DICOMMediaType.dicomJSON.description]
        )
        
        let response: HTTPClient.Response
        do {
            response = try await httpClient.execute(request)
        } catch let error as DICOMwebError {
            // Re-map 404 to empty result for search
            if case .notFound = error {
                return UPSQueryResult.empty
            }
            throw error
        }
        
        // Parse JSON response
        guard let jsonArray = try? JSONSerialization.jsonObject(with: response.body) as? [[String: Any]] else {
            // Empty result
            if response.body.isEmpty || String(data: response.body, encoding: .utf8) == "[]" {
                return UPSQueryResult.empty
            }
            throw DICOMwebError.invalidJSON(reason: "Expected JSON array of workitem objects")
        }
        
        // Extract pagination info from headers
        let totalCount = response.header("X-Total-Count").flatMap { Int($0) }
        let queryParams = query.toParameters()
        let offset = queryParams["offset"].flatMap { Int($0) } ?? 0
        let limit = queryParams["limit"].flatMap { Int($0) }
        
        return UPSQueryResult.parse(
            jsonArray: jsonArray,
            totalCount: totalCount,
            offset: offset,
            limit: limit
        )
    }
    
    /// Retrieves a specific workitem by its UID
    ///
    /// - Parameter uid: The workitem's SOP Instance UID
    /// - Returns: The workitem data as DICOM JSON
    /// - Throws: DICOMwebError on failure, UPSError.workitemNotFound if not found
    ///
    /// Reference: PS3.18 Section 11.5 - Retrieve Workitem Transaction
    public func retrieveWorkitem(uid: String) async throws -> [String: Any] {
        let url = urlBuilder.workitemURL(workitemUID: uid)
        
        let request = HTTPClient.Request(
            url: url,
            method: .get,
            headers: ["Accept": DICOMMediaType.dicomJSON.description]
        )
        
        let response: HTTPClient.Response
        do {
            response = try await httpClient.execute(request)
        } catch let error as DICOMwebError {
            if case .notFound = error {
                throw UPSError.workitemNotFound(uid: uid)
            }
            throw error
        }
        
        // Parse JSON response — handle both object {…} and array [{…}] formats
        let parsed = try? JSONSerialization.jsonObject(with: response.body)
        let json: [String: Any]
        if let array = parsed as? [[String: Any]], let first = array.first {
            json = first
        } else if let object = parsed as? [String: Any] {
            json = object
        } else {
            throw DICOMwebError.invalidJSON(reason: "Expected JSON object or array for workitem")
        }
        
        return json
    }
    
    /// Retrieves a specific workitem and parses it to WorkitemResult
    ///
    /// - Parameter uid: The workitem's SOP Instance UID
    /// - Returns: Parsed workitem result
    /// - Throws: DICOMwebError on failure, UPSError.workitemNotFound if not found
    public func retrieveWorkitemResult(uid: String) async throws -> WorkitemResult {
        let json = try await retrieveWorkitem(uid: uid)
        // PS3.4 Table CC.2.5-3 N-GET: (0008,0018) is not in a Retrieve Workitem response
        guard let result = WorkitemResult.parse(json: json, requestedUID: uid) else {
            throw DICOMwebError.invalidJSON(reason: "Failed to parse workitem JSON")
        }
        return result
    }
    
    /// Creates a new workitem
    ///
    /// - Parameters:
    ///   - workitem: The workitem data as DICOM JSON
    ///   - uid: Optional specific UID to use (if nil, server will generate)
    /// - Returns: Response with the created workitem UID
    /// - Throws: DICOMwebError on failure, UPSError.workitemAlreadyExists if UID conflicts
    ///
    /// Reference: PS3.18 Section 11.4 - Create Workitem Transaction
    public func createWorkitem(
        workitem: [String: Any],
        uid: String? = nil
    ) async throws -> UPSCreateResponse {
        // Per PS3.18 §11.4: POST /workitems?workitem={uid} for client-specified UID,
        // POST /workitems for server-generated UID.
        // NOTE: POST /workitems/{uid} is the UPDATE endpoint (§11.5), not CREATE.
        let url: URL
        if let uid = uid {
            url = urlBuilder.createWorkitemURL(workitemUID: uid)
        } else {
            url = urlBuilder.workitemsURL
        }
        
        // Per PS3.18 Section 11.4 and PS3.4 Table CC.2.5-3, enforce attributes
        // for UPS-RS Create request body
        var filteredWorkitem = workitem
        filteredWorkitem.removeValue(forKey: UPSTag.sopInstanceUID)       // (0008,0018) in URL
        // Procedure Step State (0074,1000) MUST be SCHEDULED for N-CREATE per PS3.4 CC.2.5-3
        filteredWorkitem[UPSTag.procedureStepState] = ["vr": "CS", "Value": ["SCHEDULED"]]
        
        // Serialize workitem to JSON
        let body = try JSONSerialization.data(withJSONObject: filteredWorkitem)
        
        let request = HTTPClient.Request(
            url: url,
            method: .post,
            headers: [
                "Content-Type": DICOMMediaType.dicomJSON.description,
                "Accept": DICOMMediaType.dicomJSON.description
            ],
            body: body
        )
        
        let response: HTTPClient.Response
        do {
            response = try await httpClient.execute(request)
        } catch let error as DICOMwebError {
            if case .httpError(let statusCode, _) = error, statusCode == 409 {
                let existingUID = uid ?? "unknown"
                throw UPSError.workitemAlreadyExists(uid: existingUID)
            }
            throw error
        }
        
        // Extract workitem UID from Location header or response
        let locationHeader = response.header("Location")
        let workitemUID = extractWorkitemUIDFromLocation(locationHeader) ?? uid ?? ""
        
        // Check for warnings
        let warnings = extractUPSWarnings(from: response)
        
        return UPSCreateResponse(
            workitemUID: workitemUID,
            retrieveURL: locationHeader,
            warnings: warnings
        )
    }
    
    /// Creates a new workitem from a Workitem struct
    ///
    /// - Parameters:
    ///   - workitem: The workitem to create
    /// - Returns: Response with the created workitem UID
    /// - Throws: DICOMwebError on failure
    public func createWorkitem(_ workitem: Workitem) async throws -> UPSCreateResponse {
        let json = workitemToCreateJSON(workitem)
        return try await createWorkitem(workitem: json, uid: workitem.workitemUID)
    }
    
    /// Updates an existing workitem
    ///
    /// - Parameters:
    ///   - uid: The workitem's SOP Instance UID
    ///   - updates: The updates to apply as DICOM JSON
    ///   - transactionUID: Transaction UID of the claimed workitem (required by PS3.18 §11.6)
    /// - Throws: DICOMwebError on failure, UPSError.workitemNotFound if not found
    ///
    /// Reference: PS3.18 Section 11.6 - Update Workitem Transaction
    /// Uses POST (not PUT) with the Transaction UID as a query parameter.
    public func updateWorkitem(uid: String, updates: [String: Any], transactionUID: String) async throws {
        let url = urlBuilder.updateWorkitemURL(workitemUID: uid, transactionUID: transactionUID)

        // Serialize updates to JSON
        let body = try JSONSerialization.data(withJSONObject: updates)

        let request = HTTPClient.Request(
            url: url,
            method: .post,
            headers: ["Content-Type": DICOMMediaType.dicomJSON.description],
            body: body
        )

        do {
            _ = try await httpClient.execute(request)
        } catch let error as DICOMwebError {
            if case .notFound = error {
                throw UPSError.workitemNotFound(uid: uid)
            }
            throw error
        }
    }
    
    /// Changes the state of a workitem
    ///
    /// - Parameters:
    ///   - uid: The workitem's SOP Instance UID
    ///   - state: The target state
    ///   - transactionUID: Transaction UID (required when completing/canceling from IN PROGRESS)
    ///   - requestingAE: Optional Requesting AE Title appended to the URL (required by some servers)
    /// - Returns: Response with the new state and transaction UID if applicable
    /// - Throws: DICOMwebError on failure, UPSError for invalid state transitions
    ///
    /// Reference: PS3.18 Section 11.7 - Change Workitem State Transaction
    public func changeWorkitemState(
        uid: String,
        state: UPSState,
        transactionUID: String? = nil,
        requestingAE: String? = nil
    ) async throws -> UPSStateChangeResponse {
        let url = urlBuilder.workitemStateURL(workitemUID: uid, requestingAE: requestingAE)
        
        // PS3.4 CC.2.1.2: to claim a SCHEDULED UPS the SCU generates the Transaction UID and
        // sends it with the change to IN PROGRESS; PS3.18 11.7.1.4: the payload shall include it
        let transactionUID = transactionUID ?? (state == .inProgress ? UIDGenerator.generateUID().value : nil)
        
        // Build state change JSON
        let stateChangeJSON = buildUPSStateChangeJSON(state: state, transactionUID: transactionUID)
        let body = try JSONSerialization.data(withJSONObject: stateChangeJSON)
        
        let request = HTTPClient.Request(
            url: url,
            method: .put,
            headers: [
                "Content-Type": DICOMMediaType.dicomJSON.description,
                "Accept": DICOMMediaType.dicomJSON.description
            ],
            body: body
        )
        
        let response: HTTPClient.Response
        do {
            response = try await httpClient.execute(request)
        } catch let error as DICOMwebError {
            switch error {
            case .notFound:
                throw UPSError.workitemNotFound(uid: uid)
            case .conflict(let message):
                // 409 — invalid state transition or transaction UID mismatch
                if let message = message, message.lowercased().contains("transaction") {
                    throw UPSError.transactionUIDMismatch
                }
                throw error
            default:
                throw error
            }
        }
        
        // Parse response to get transaction UID (returned for IN PROGRESS transitions)
        var responseTransactionUID: String? = nil
        if !response.body.isEmpty {
            if let json = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any] {
                responseTransactionUID = extractUPSTransactionUID(from: json)
            }
        }
        
        // Check for warnings
        let warnings = extractUPSWarnings(from: response)
        
        return UPSStateChangeResponse(
            workitemUID: uid,
            newState: state,
            transactionUID: responseTransactionUID ?? transactionUID,
            warnings: warnings
        )
    }

    /// Transitions an IN PROGRESS workitem to COMPLETED, first populating the
    /// minimal Final State attributes the SCP requires.
    ///
    /// Per PS3.4 CC.2.1.3 / Table CC.2.5-3 the SCP validates that the Unified
    /// Procedure Step Performed Procedure Sequence (0074,1216) is populated
    /// before allowing the transition to COMPLETED. This convenience sends a
    /// minimal Update Workitem (PS3.18 §11.5) to satisfy that requirement and
    /// then performs the Change State (PS3.18 §11.6) to COMPLETED — so callers
    /// (the CLI and the CLI-parity reference) share ONE source of truth for the
    /// completion payload and cannot drift.
    ///
    /// - Parameters:
    ///   - uid: The workitem's SOP Instance UID
    ///   - transactionUID: The Transaction UID that locked the workitem at IN PROGRESS
    ///   - requestingAE: Optional Requesting AE Title appended to the URL (required by some servers)
    /// - Returns: The Change State response for the COMPLETED transition
    /// - Throws: DICOMwebError on failure, UPSError for invalid transitions
    public func completeWorkitem(
        uid: String,
        transactionUID: String,
        requestingAE: String? = nil
    ) async throws -> UPSStateChangeResponse {
        let nowDT: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMddHHmmss.SSS000"
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone.current
            return f.string(from: Date())
        }()

        let performedBody: [String: Any] = [
            UPSTag.transactionUID: [
                "vr": "UI", "Value": [transactionUID]
            ] as [String: Any],
            UPSTag.unifiedProcedureStepPerformedProcedureSequence: [
                "vr": "SQ",
                "Value": [
                    [
                        UPSTag.performedProcedureStepStartDateTime: [
                            "vr": "DT", "Value": [nowDT]
                        ] as [String: Any],
                        UPSTag.performedProcedureStepEndDateTime: [
                            "vr": "DT", "Value": [nowDT]
                        ] as [String: Any],
                        UPSTag.performedWorkitemCodeSequence: [
                            "vr": "SQ",
                            "Value": [
                                [
                                    UPSTag.codeValue: ["vr": "SH", "Value": ["12345"]],
                                    UPSTag.codingSchemeDesignator: ["vr": "SH", "Value": ["99LOCAL"]],
                                    UPSTag.codeMeaning: ["vr": "LO", "Value": ["Procedure Step Performed"]]
                                ] as [String: Any]
                            ] as [[String: Any]]
                        ] as [String: Any],
                        UPSTag.performedStationNameCodeSequence: [
                            "vr": "SQ",
                            "Value": [
                                [
                                    UPSTag.codeValue: ["vr": "SH", "Value": ["STATION01"]],
                                    UPSTag.codingSchemeDesignator: ["vr": "SH", "Value": ["99LOCAL"]],
                                    UPSTag.codeMeaning: ["vr": "LO", "Value": ["Default Performing Station"]]
                                ] as [String: Any]
                            ] as [[String: Any]]
                        ] as [String: Any],
                        UPSTag.outputInformationSequence: [
                            "vr": "SQ",
                            "Value": [] as [[String: Any]]
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [[String: Any]]
            ] as [String: Any]
        ]

        try await updateWorkitem(uid: uid, updates: performedBody, transactionUID: transactionUID)

        return try await changeWorkitemState(
            uid: uid,
            state: .completed,
            transactionUID: transactionUID,
            requestingAE: requestingAE
        )
    }

    /// Requests cancellation of a workitem
    ///
    /// - Parameters:
    ///   - uid: The workitem's SOP Instance UID
    ///   - reason: Optional reason for cancellation
    ///   - contactDisplayName: Optional contact display name
    ///   - contactURI: Optional contact URI
    /// - Returns: Response indicating if cancellation was accepted
    /// - Throws: DICOMwebError on failure, UPSError.workitemNotFound if not found
    ///
    /// Reference: PS3.18 Section 11.8 - Request Cancellation Transaction
    public func requestWorkitemCancellation(
        uid: String,
        reason: String? = nil,
        contactDisplayName: String? = nil,
        contactURI: String? = nil,
        requestingAE: String? = nil
    ) async throws -> UPSCancellationResponse {
        let url = urlBuilder.workitemCancelRequestURL(workitemUID: uid, requestingAE: requestingAE)
        
        // Build cancellation request JSON
        let cancellationJSON = buildUPSCancellationJSON(
            reason: reason,
            contactDisplayName: contactDisplayName,
            contactURI: contactURI
        )
        let body = try JSONSerialization.data(withJSONObject: cancellationJSON)
        
        // PS3.18 Table 11.3-1 / 11.8.1: POST /workitems/{workitem}/cancelrequest
        let request = HTTPClient.Request(
            url: url,
            method: .post,
            headers: [
                "Content-Type": DICOMMediaType.dicomJSON.description,
                "Accept": DICOMMediaType.dicomJSON.description
            ],
            body: body
        )
        
        let response: HTTPClient.Response
        var rejectionReason: String? = nil
        var accepted = false
        
        do {
            response = try await httpClient.execute(request)
            // 2xx means cancellation was accepted
            accepted = true
        } catch let error as DICOMwebError {
            switch error {
            case .notFound:
                throw UPSError.workitemNotFound(uid: uid)
            case .conflict(let message):
                // 409 Conflict means cancellation was rejected
                rejectionReason = message
                response = HTTPClient.Response(
                    statusCode: 409,
                    headers: [:],
                    body: Data()
                )
            default:
                throw error
            }
        }
        
        // Check for warnings
        let warnings = extractUPSWarnings(from: response)
        
        return UPSCancellationResponse(
            workitemUID: uid,
            accepted: accepted,
            rejectionReason: rejectionReason,
            warnings: warnings
        )
    }
    
    /// Requests cancellation using a cancellation request struct
    ///
    /// - Parameter cancellationRequest: The cancellation request
    /// - Returns: Response indicating if cancellation was accepted
    /// - Throws: DICOMwebError on failure
    public func requestWorkitemCancellation(_ cancellationRequest: UPSCancellationRequest) async throws -> UPSCancellationResponse {
        return try await requestWorkitemCancellation(
            uid: cancellationRequest.workitemUID,
            reason: cancellationRequest.reason,
            contactDisplayName: cancellationRequest.contactDisplayName,
            contactURI: cancellationRequest.contactURI
        )
    }
    
    /// Subscribes to workitem events
    ///
    /// - Parameters:
    ///   - workitemUID: The workitem's SOP Instance UID (or nil for global subscription)
    ///   - aeTitle: The subscribing AE Title
    ///   - deletionLock: Whether to lock the workitem from deletion while subscribed
    /// - Throws: DICOMwebError on failure
    ///
    /// Reference: PS3.18 Section 11.10 - Subscribe Transaction
    public func subscribeToWorkitem(
        workitemUID: String?,
        aeTitle: String,
        deletionLock: Bool = false
    ) async throws {
        var url: URL
        if let workitemUID = workitemUID {
            url = urlBuilder.workitemSubscriptionURL(workitemUID: workitemUID, aeTitle: aeTitle)
        } else {
            url = urlBuilder.globalWorkitemSubscriptionURL(aeTitle: aeTitle)
        }
        
        // PS3.18 11.10.1.2: the Deletion Lock is the query parameter deletionlock=true
        if deletionLock {
            url = DICOMwebURLBuilder.appendQueryParameters(
                to: url, parameters: [DICOMwebURLBuilder.QueryParameter.deletionlock: "true"])
        }
        
        let request = HTTPClient.Request(
            url: url,
            method: .post,
            headers: [:]
        )
        
        do {
            _ = try await httpClient.execute(request)
        } catch let error as DICOMwebError {
            if case .notFound = error {
                if let workitemUID = workitemUID {
                    throw UPSError.workitemNotFound(uid: workitemUID)
                }
            }
            throw error
        }
    }
    
    /// Subscribes globally to all workitem events
    ///
    /// - Parameters:
    ///   - aeTitle: The subscribing AE Title
    ///   - deletionLock: Whether to lock workitems from deletion while subscribed
    /// - Throws: DICOMwebError on failure
    public func subscribeToAllWorkitems(aeTitle: String, deletionLock: Bool = false) async throws {
        try await subscribeToWorkitem(workitemUID: nil, aeTitle: aeTitle, deletionLock: deletionLock)
    }
    
    /// Unsubscribes from workitem events
    ///
    /// - Parameters:
    ///   - workitemUID: The workitem's SOP Instance UID (or nil for global subscription)
    ///   - aeTitle: The subscribing AE Title
    /// - Throws: DICOMwebError on failure
    ///
    /// Reference: PS3.18 Section 11.11 - Unsubscribe Transaction
    public func unsubscribeFromWorkitem(workitemUID: String?, aeTitle: String) async throws {
        let url: URL
        if let workitemUID = workitemUID {
            url = urlBuilder.workitemSubscriptionURL(workitemUID: workitemUID, aeTitle: aeTitle)
        } else {
            url = urlBuilder.globalWorkitemSubscriptionURL(aeTitle: aeTitle)
        }
        
        let request = HTTPClient.Request(
            url: url,
            method: .delete,
            headers: [:]
        )
        
        do {
            _ = try await httpClient.execute(request)
        } catch let error as DICOMwebError {
            // Subscription may not exist, but that's okay for unsubscribe
            if case .notFound = error {
                return
            }
            throw error
        }
    }
    
    /// Unsubscribes from global workitem events
    ///
    /// - Parameter aeTitle: The subscribing AE Title
    /// - Throws: DICOMwebError on failure
    public func unsubscribeFromAllWorkitems(aeTitle: String) async throws {
        try await unsubscribeFromWorkitem(workitemUID: nil, aeTitle: aeTitle)
    }
    
    /// Suspends a workitem subscription
    ///
    /// - Parameters:
    ///   - uid: The workitem's SOP Instance UID
    ///   - aeTitle: The subscribing AE Title
    /// - Throws: DICOMwebError on failure
    ///
    /// Reference: PS3.18 Section 11.12 - Suspend Global Subscription Transaction
    public func suspendWorkitemSubscription(uid: String, aeTitle: String) async throws {
        let url = urlBuilder.workitemSubscriptionSuspendURL(workitemUID: uid, aeTitle: aeTitle)
        
        let request = HTTPClient.Request(
            url: url,
            method: .post,
            headers: [:]
        )
        
        do {
            _ = try await httpClient.execute(request)
        } catch let error as DICOMwebError {
            if case .notFound = error {
                throw UPSError.workitemNotFound(uid: uid)
            }
            throw error
        }
    }
    
    // MARK: - UPS-RS Private Helpers
    
    /// Extracts workitem UID from a Location header URL
    private func extractWorkitemUIDFromLocation(_ location: String?) -> String? {
        guard let location = location,
              let url = URL(string: location) else {
            return nil
        }
        
        // The UID should be the last path component
        let components = url.pathComponents.filter { $0 != "/" }
        return components.last
    }
    
    /// Extracts warnings from HTTP response headers
    private func extractUPSWarnings(from response: HTTPClient.Response) -> [String] {
        var warnings: [String] = []
        
        if let warning = response.header("Warning") {
            warnings.append(warning)
        }
        
        return warnings
    }
    
    /// Extracts transaction UID from response JSON
    private func extractUPSTransactionUID(from json: [String: Any]) -> String? {
        // Transaction UID is at tag 0008,1195
        if let element = json[UPSTag.transactionUID] as? [String: Any],
           let values = element["Value"] as? [String],
           let uid = values.first {
            return uid
        }
        return nil
    }
    
    /// Builds state change JSON payload
    private func buildUPSStateChangeJSON(state: UPSState, transactionUID: String?) -> [String: Any] {
        var json: [String: Any] = [
            // Procedure Step State (0074,1000)
            UPSTag.procedureStepState: [
                "vr": "CS",
                "Value": [state.rawValue]
            ]
        ]
        
        if let txUID = transactionUID {
            // Transaction UID (0008,1195)
            json[UPSTag.transactionUID] = [
                "vr": "UI",
                "Value": [txUID]
            ]
        }
        
        return json
    }
    
    /// Builds cancellation request JSON payload
    private func buildUPSCancellationJSON(
        reason: String?,
        contactDisplayName: String?,
        contactURI: String?
    ) -> [String: Any] {
        var json: [String: Any] = [:]
        
        if let reason = reason {
            // Reason For Cancellation (0074,1238)
            json[UPSTag.reasonForCancellation] = [
                "vr": "LT",
                "Value": [reason]
            ]
        }
        
        // If contact info provided, add Communication URI sequence
        if contactDisplayName != nil || contactURI != nil {
            var contactItem: [String: Any] = [:]
            
            if let name = contactDisplayName {
                // Contact Display Name
                contactItem["0074100C"] = [
                    "vr": "LO",
                    "Value": [name]
                ]
            }
            
            if let uri = contactURI {
                // Contact URI
                contactItem["0074100A"] = [
                    "vr": "UR",
                    "Value": [uri]
                ]
            }
            
            // Procedure Step Communication URI Sequence
            json["00741008"] = [
                "vr": "SQ",
                "Value": [contactItem]
            ]
        }
        
        return json
    }
    
    /// Converts a Workitem struct to DICOM JSON
    ///
    /// Delegates to `Workitem.toDICOMJSON()` for consistent serialization.
    private func workitemToJSON(_ workitem: Workitem) -> [String: Any] {
        return workitem.toDICOMJSON()
    }
    
    /// Converts a Workitem struct to DICOM JSON for Create Transaction
    ///
    /// Uses `Workitem.toDICOMJSONForCreate()` which only includes attributes
    /// allowed by PS3.4 Table CC.2.5-3 for UPS N-CREATE.
    private func workitemToCreateJSON(_ workitem: Workitem) -> [String: Any] {
        return workitem.toDICOMJSONForCreate()
    }
}
#endif
