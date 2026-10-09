import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// NEMA-verified: 2026a, checked 2026-10-01 — all 19 query parameters of PS3.18 2026a Tables 9.1.2-1 (4), 9.1.2-2 (2), 9.4.1-1 (3) and 9.5.1-1 (12, contentType/charset shared) are requestable through `Parameters` (D108; annotation for application/dicom, imageAnnotation for rendered, as the two tables name it); `MediaType` carries application/dicom and the 15 Rendered Media Types of Table 8.7.4-1 (14 distinct); value rules from 9.1.2.2.1, 9.5.1.2.1, 9.5.1.2.4-9.5.1.2.7 and 8.3.5.1.2; checked 2026-09-28 — ContentType: 7 / 7 (image/jphc deprecated and mapped to image/jph)
/// Client for WADO-URI (Web Access to DICOM Objects — URI-based) retrieval
///
/// Implements the WADO-URI protocol defined in DICOM PS3.18 Chapter 9 (URI Service) for retrieving
/// individual DICOM objects using HTTP GET with query parameters.
/// This is the older WADO standard, commonly supported by legacy PACS such as dcm4chee2.
///
/// WADO-URI differs from WADO-RS in that it uses query-string parameters
/// (`requestType=WADO&studyUID=...&seriesUID=...&objectUID=...`) rather than
/// RESTful path segments (`/studies/{uid}/series/{uid}/instances/{uid}`).
///
/// ## Example Usage
///
/// ```swift
/// let config = try DICOMwebConfiguration(
///     baseURLString: "http://pacs.hospital.org/wado"
/// )
/// let client = WADOURIClient(configuration: config)
///
/// // Retrieve a DICOM object
/// let data = try await client.retrieve(
///     studyUID: "1.2.3",
///     seriesUID: "1.2.3.4",
///     objectUID: "1.2.3.4.5"
/// )
///
/// // Retrieve as JPEG image
/// let jpeg = try await client.retrieve(
///     studyUID: "1.2.3",
///     seriesUID: "1.2.3.4",
///     objectUID: "1.2.3.4.5",
///     contentType: .jpeg
/// )
/// ```
///
/// Reference: DICOM PS3.18 §9 — URI Service
#if canImport(FoundationNetworking) || os(macOS) || os(iOS) || os(visionOS) || os(tvOS) || os(watchOS)
public final class WADOURIClient: @unchecked Sendable {

    // MARK: - Types

    /// Content type to request from WADO-URI
    public enum ContentType: String, Sendable {
        /// DICOM Part 10 file (application/dicom)
        case dicom = "application/dicom"
        /// JPEG image (image/jpeg)
        case jpeg = "image/jpeg"
        /// PNG image (image/png)
        case png = "image/png"
        /// GIF image (image/gif)
        case gif = "image/gif"
        /// JPEG 2000 image (image/jp2)
        case jpeg2000 = "image/jp2"
        /// HTJ2K codestream image (image/jph)
        case htj2k = "image/jph"
        /// image/jphc is a compressed bulk data media type (PS3.18 Table 8.7.3-5), not a Rendered
        /// Media Type of Table 8.7.4-1, so 9.1.2.2.1 does not allow it as a contentType value.
        /// Requests map to `.htj2k` (image/jph).
        @available(*, deprecated, renamed: "htj2k", message: "PS3.18 9.1.2.2.1: image/jphc is not a Rendered Media Type; use image/jph")
        case htj2kContainer = "image/jphc"
        /// MPEG video (video/mpeg)
        case mpeg = "video/mpeg"

        /// Maps a CLI / UI `--content-type` string (full media type or short alias) to a
        /// `ContentType`. A nil, empty, or unrecognised value defaults to `.dicom` — the
        /// WADO-URI default representation. This is the SINGLE source of truth shared by the
        /// `dicom-wado` CLI and the CLI-parity reference, so the two can never request
        /// different representations for the same `--content-type` argument.
        public static func fromRequestString(_ raw: String?) -> ContentType {
            switch (raw ?? "").lowercased() {
            case "image/jpeg", "jpeg":                    return .jpeg
            case "image/png", "png":                      return .png
            case "image/gif", "gif":                      return .gif
            case "image/jp2", "jp2":                      return .jpeg2000
            case "image/jph", "jph", "htj2k":             return .htj2k
            case "image/jphc", "jphc", "htj2k-container": return .htj2k  // not a Rendered Media Type (9.1.2.2.1)
            case "video/mpeg", "mpeg":                    return .mpeg
            default:                                       return .dicom
            }
        }
    }

    /// A WADO-URI `contentType` value (PS3.18 2026a 9.1.2.2.1): application/dicom or one of
    /// the Rendered Media Types of Table 8.7.4-1. A struct rather than the `ContentType`
    /// enum so that media types can be added without breaking exhaustive switches.
    public struct MediaType: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public var description: String { rawValue }

        /// application/dicom — Retrieve DICOM Instance (9.4)
        public static let dicom = MediaType(rawValue: "application/dicom")
        // Table 8.7.4-1, Single Frame / Multi-frame Image
        public static let jpeg = MediaType(rawValue: "image/jpeg")
        public static let gif = MediaType(rawValue: "image/gif")
        public static let png = MediaType(rawValue: "image/png")
        public static let jp2 = MediaType(rawValue: "image/jp2")
        public static let jph = MediaType(rawValue: "image/jph")
        public static let jxl = MediaType(rawValue: "image/jxl")
        // Table 8.7.4-1, Video
        public static let mpeg = MediaType(rawValue: "video/mpeg")
        public static let mp4 = MediaType(rawValue: "video/mp4")
        public static let h265 = MediaType(rawValue: "video/H265")
        // Table 8.7.4-1, Text
        public static let html = MediaType(rawValue: "text/html")
        public static let plainText = MediaType(rawValue: "text/plain")
        public static let xml = MediaType(rawValue: "text/xml")
        public static let rtf = MediaType(rawValue: "text/rtf")
        public static let pdf = MediaType(rawValue: "application/pdf")

        /// The distinct Rendered Media Types of PS3.18 2026a Table 8.7.4-1 (14; image/gif
        /// and image/jxl appear under both Single Frame and Multi-frame Image).
        public static let renderedMediaTypes: [MediaType] = [
            .jpeg, .gif, .png, .jp2, .jph, .jxl, .mpeg, .mp4, .h265, .html, .plainText, .xml, .rtf, .pdf,
        ]

        /// application/dicom plus every Rendered Media Type (the values 9.1.2.2.1 allows).
        public static let allowed: [MediaType] = [.dicom] + renderedMediaTypes

        /// The `MediaType` of a legacy `ContentType` value.
        public init(_ contentType: ContentType) {
            switch contentType.rawValue {
            case "image/jphc": self = .jph  // not a Rendered Media Type (9.1.2.2.1)
            default:           self.init(rawValue: contentType.rawValue)
            }
        }

        /// Maps a CLI / UI string (full media type, case-insensitive, or a short alias) to an
        /// allowed media type; nil when 9.1.2.2.1 does not allow it.
        public static func fromRequestString(_ raw: String) -> MediaType? {
            let key = raw.trimmingCharacters(in: .whitespaces).lowercased()
            if let exact = allowed.first(where: { $0.rawValue.lowercased() == key }) { return exact }
            switch key {
            case "dicom":                              return .dicom
            case "jpeg", "jpg":                        return .jpeg
            case "gif":                                return .gif
            case "png":                                return .png
            case "jp2":                                return .jp2
            case "jph", "htj2k", "image/jphc", "jphc", "htj2k-container": return .jph
            case "jxl":                                return .jxl
            case "mpeg":                               return .mpeg
            case "mp4":                                return .mp4
            case "h265", "hevc":                       return .h265
            case "html":                               return .html
            case "text", "txt":                        return .plainText
            case "xml":                                return .xml
            case "rtf":                                return .rtf
            case "pdf":                                return .pdf
            default:                                   return nil
            }
        }

        /// Whether this is a Rendered Media Type (Retrieve Rendered Instance, 9.5).
        public var isRendered: Bool { self != .dicom }

        /// A file name extension for a response of this media type.
        public var fileExtension: String {
            switch self {
            case .dicom: return "dcm"
            case .jpeg: return "jpg"
            case .gif: return "gif"
            case .png: return "png"
            case .jp2: return "jp2"
            case .jph: return "jph"
            case .jxl: return "jxl"
            case .mpeg: return "mpg"
            case .mp4: return "mp4"
            case .h265: return "hevc"
            case .html: return "html"
            case .plainText: return "txt"
            case .xml: return "xml"
            case .rtf: return "rtf"
            case .pdf: return "pdf"
            default: return "bin"
            }
        }
    }

    /// Source Image Region (`region`, PS3.18 2026a 9.5.1.2.5): normalized coordinates with
    /// 0.0 <= xmin < xmax <= 1.0 and 0.0 <= ymin < ymax <= 1.0.
    public struct Region: Sendable, Equatable {
        public var xmin: Double, ymin: Double, xmax: Double, ymax: Double
        public init(xmin: Double, ymin: Double, xmax: Double, ymax: Double) {
            self.xmin = xmin; self.ymin = ymin; self.xmax = xmax; self.ymax = ymax
        }
        /// Parses `xmin,ymin,xmax,ymax`; nil when not four decimal numbers.
        public init?(_ text: String) {
            let parts = text.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 4, let a = parts[0], let b = parts[1], let c = parts[2], let d = parts[3] else { return nil }
            self.init(xmin: a, ymin: b, xmax: c, ymax: d)
        }
        var isValid: Bool { 0 <= xmin && xmin < xmax && xmax <= 1 && 0 <= ymin && ymin < ymax && ymax <= 1 }
        var queryValue: String { [xmin, ymin, xmax, ymax].map(WADOURIClient.decimalString).joined(separator: ",") }
    }

    /// The optional WADO-URI query parameters of PS3.18 2026a Tables 9.1.2-2, 9.4.1-1 and
    /// 9.5.1-1. `retrieve(studyUID:seriesUID:objectUID:parameters:)` sends each one that is
    /// set, after `validate()`.
    public struct Parameters: Sendable, Equatable {
        /// `contentType` (9.1.2.2.1): application/dicom, or one or more Rendered Media Types.
        public var contentType: [MediaType]
        /// `charset` (9.1.2.2.2): one or more character-set identifiers (e.g. "UTF-8").
        public var charset: [String]
        /// `anonymize=yes` (9.4.1.2.1, application/dicom).
        public var anonymize: Bool
        /// `annotation` (9.4.1.2.2) / `imageAnnotation` (Table 9.5.1-1): "patient" and/or
        /// "technique" (an origin server may support more keywords).
        public var annotation: [String]
        /// `transferSyntax` (9.4.1.2.3, application/dicom).
        public var transferSyntax: String?
        /// `frameNumber` (9.5.1.2.1): a positive integer, starting at 1.
        public var frameNumber: Int?
        /// `imageQuality` (9.5.1.2.3 → 8.3.5.1.2): 1 to 100.
        public var imageQuality: Int?
        /// `rows` / `columns` (9.5.1.2.4): positive integers; if either is present, both shall be.
        public var rows: Int?
        public var columns: Int?
        /// `region` (9.5.1.2.5).
        public var region: Region?
        /// `windowCenter` / `windowWidth` (9.5.1.2.6): both or neither; not with
        /// application/dicom nor with a Presentation State.
        public var windowCenter: Double?
        public var windowWidth: Double?
        /// `presentationSeriesUID` / `presentationUID` (9.5.1.2.7): both or neither.
        public var presentationSeriesUID: String?
        public var presentationUID: String?

        public init(contentType: [MediaType] = [.dicom], charset: [String] = [], anonymize: Bool = false,
                    annotation: [String] = [], transferSyntax: String? = nil, frameNumber: Int? = nil,
                    imageQuality: Int? = nil, rows: Int? = nil, columns: Int? = nil, region: Region? = nil,
                    windowCenter: Double? = nil, windowWidth: Double? = nil,
                    presentationSeriesUID: String? = nil, presentationUID: String? = nil) {
            self.contentType = contentType
            self.charset = charset
            self.anonymize = anonymize
            self.annotation = annotation
            self.transferSyntax = transferSyntax
            self.frameNumber = frameNumber
            self.imageQuality = imageQuality
            self.rows = rows
            self.columns = columns
            self.region = region
            self.windowCenter = windowCenter
            self.windowWidth = windowWidth
            self.presentationSeriesUID = presentationSeriesUID
            self.presentationUID = presentationUID
        }

        /// Whether the request is for application/dicom (Retrieve DICOM Instance, 9.4).
        public var isDICOM: Bool { contentType.isEmpty || contentType == [.dicom] }

        /// The violations of the PS3.18 2026a rules for these values (each a sentence that
        /// names its clause); empty when the request may be sent. Each is a case the text
        /// answers with 400 (Bad Request) or words as "shall".
        public func problems() -> [String] {
            var out: [String] = []
            if contentType.contains(.dicom) && contentType.count > 1 {
                out.append("contentType is either application/dicom or one or more Rendered Media Types (PS3.18 9.1.2.2.1)")
            }
            for type in contentType where !MediaType.allowed.contains(type) {
                out.append("contentType \(type) is neither application/dicom nor a Rendered Media Type of Table 8.7.4-1 (PS3.18 9.1.2.2.1)")
            }
            if let f = frameNumber, f < 1 { out.append("frameNumber is a positive integer, starting at 1 (PS3.18 9.5.1.2.1)") }
            if let q = imageQuality, !(1...100).contains(q) {
                out.append("imageQuality is an integer between 1 and 100 inclusive (PS3.18 9.5.1.2.3, 8.3.5.1.2)")
            }
            if let r = rows, r < 1 { out.append("rows is a positive integer (PS3.18 9.5.1.2.4.1)") }
            if let c = columns, c < 1 { out.append("columns is a positive integer (PS3.18 9.5.1.2.4.2)") }
            if (rows == nil) != (columns == nil) {
                out.append("rows and columns: if either is present, both shall be present (PS3.18 9.5.1.2.4)")
            }
            if let region, !region.isValid {
                out.append("region is xmin,ymin,xmax,ymax with 0.0 <= xmin < xmax <= 1.0 and 0.0 <= ymin < ymax <= 1.0 (PS3.18 9.5.1.2.5)")
            }
            let windowing = windowCenter != nil || windowWidth != nil
            if (windowCenter == nil) != (windowWidth == nil) {
                out.append("windowCenter and windowWidth: if either is present, both shall be present (PS3.18 9.5.1.2.6)")
            }
            if windowing && isDICOM {
                out.append("windowCenter / windowWidth shall not be present when contentType is application/dicom (PS3.18 9.5.1.2.6)")
            }
            let presentation = presentationUID != nil || presentationSeriesUID != nil
            if (presentationUID == nil) != (presentationSeriesUID == nil) {
                out.append("presentationUID and presentationSeriesUID: if one is present, both shall be present (PS3.18 9.5.1.2.7)")
            }
            if windowing && presentation {
                out.append("the Windowing and Presentation State parameters shall not be present in the same request (PS3.18 9.5.1.2.6)")
            }
            return out
        }

        /// Throws `WADOURIParameterError` listing `problems()`, if any.
        public func validate() throws {
            let p = problems()
            if !p.isEmpty { throw WADOURIParameterError(problems: p) }
        }

        /// The optional query items, in the order of Tables 9.1.2-2, 9.4.1-1, 9.5.1-1.
        func queryItems() -> [URLQueryItem] {
            var items: [URLQueryItem] = []
            let types = contentType.isEmpty ? [MediaType.dicom] : contentType
            items.append(URLQueryItem(name: "contentType", value: types.map(\.rawValue).joined(separator: ",")))
            if !charset.isEmpty { items.append(URLQueryItem(name: "charset", value: charset.joined(separator: ","))) }
            if let transferSyntax, !transferSyntax.isEmpty {
                items.append(URLQueryItem(name: "transferSyntax", value: transferSyntax))
            }
            if anonymize { items.append(URLQueryItem(name: "anonymize", value: "yes")) }
            if !annotation.isEmpty {
                // Table 9.4.1-1 names it "annotation", Table 9.5.1-1 "imageAnnotation".
                items.append(URLQueryItem(name: isDICOM ? "annotation" : "imageAnnotation",
                                          value: annotation.joined(separator: ",")))
            }
            if let rows { items.append(URLQueryItem(name: "rows", value: String(rows))) }
            if let columns { items.append(URLQueryItem(name: "columns", value: String(columns))) }
            if let frameNumber { items.append(URLQueryItem(name: "frameNumber", value: String(frameNumber))) }
            if let imageQuality { items.append(URLQueryItem(name: "imageQuality", value: String(imageQuality))) }
            if let region { items.append(URLQueryItem(name: "region", value: region.queryValue)) }
            if let windowCenter { items.append(URLQueryItem(name: "windowCenter", value: WADOURIClient.decimalString(windowCenter))) }
            if let windowWidth { items.append(URLQueryItem(name: "windowWidth", value: WADOURIClient.decimalString(windowWidth))) }
            if let presentationSeriesUID {
                items.append(URLQueryItem(name: "presentationSeriesUID", value: presentationSeriesUID))
            }
            if let presentationUID { items.append(URLQueryItem(name: "presentationUID", value: presentationUID)) }
            return items
        }
    }

    /// A decimal value as sent in a query (no trailing ".0" for whole numbers).
    static func decimalString(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        return String(value)
    }

    /// Result of a WADO-URI retrieve operation
    public struct RetrieveResult: Sendable {
        /// The retrieved data
        public let data: Data
        /// The Content-Type of the response
        public let responseContentType: String?
        /// The HTTP status code
        public let statusCode: Int
    }

    // MARK: - Properties

    /// The underlying HTTP client
    public let httpClient: HTTPClient

    /// The configuration
    public var configuration: DICOMwebConfiguration {
        return httpClient.configuration
    }

    // MARK: - Initialization

    /// Creates a WADO-URI client with the specified configuration
    /// - Parameter configuration: The DICOMweb configuration (baseURL is the WADO endpoint)
    public init(configuration: DICOMwebConfiguration) {
        self.httpClient = HTTPClient(configuration: configuration)
    }

    /// Creates a WADO-URI client with the specified HTTP client
    /// - Parameter httpClient: The HTTP client to use
    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    // MARK: - Retrieve

    /// Retrieves a single DICOM object via WADO-URI
    ///
    /// Constructs a URL like:
    /// `{baseURL}?requestType=WADO&studyUID=...&seriesUID=...&objectUID=...`
    ///
    /// - Parameters:
    ///   - studyUID: Study Instance UID
    ///   - seriesUID: Series Instance UID
    ///   - objectUID: SOP Instance UID
    ///   - contentType: Requested content type (default: .dicom)
    ///   - transferSyntax: Preferred transfer syntax UID (optional, for contentType .dicom)
    ///   - anonymize: Whether to anonymize the object (optional, "yes" to anonymize)
    ///   - rows: Number of pixel rows for image content types (optional)
    ///   - columns: Number of pixel columns for image content types (optional)
    ///   - frameNumber: Frame number to retrieve for multi-frame objects (optional, 1-based)
    /// - Returns: The retrieved data
    /// - Throws: DICOMwebError on failure
    ///
    /// Reference: DICOM PS3.18 §9.4 — Retrieve DICOM Instance Transaction; §9.5 Retrieve Rendered Instance
    public func retrieve(
        studyUID: String,
        seriesUID: String,
        objectUID: String,
        contentType: ContentType = .dicom,
        transferSyntax: String? = nil,
        anonymize: String? = nil,
        rows: Int? = nil,
        columns: Int? = nil,
        frameNumber: Int? = nil
    ) async throws -> RetrieveResult {
        let url = try buildURL(
            studyUID: studyUID,
            seriesUID: seriesUID,
            objectUID: objectUID,
            contentType: contentType,
            transferSyntax: transferSyntax,
            anonymize: anonymize,
            rows: rows,
            columns: columns,
            frameNumber: frameNumber
        )

        let headers = ["Accept": contentType.rawValue]
        let response = try await httpClient.get(url, headers: headers)

        guard response.isSuccess else {
            let body = String(data: response.body, encoding: .utf8)
            throw DICOMwebError.fromHTTPStatus(response.statusCode, message: body)
        }

        return RetrieveResult(
            data: response.body,
            responseContentType: response.header("Content-Type"),
            statusCode: response.statusCode
        )
    }

    /// Retrieves a DICOM object or a rendered representation via WADO-URI with any of the
    /// optional query parameters of PS3.18 2026a Tables 9.1.2-2, 9.4.1-1 and 9.5.1-1.
    ///
    /// - Throws: `WADOURIParameterError` when `parameters` break a rule of PS3.18 Section 9
    ///   (see `Parameters.problems()`), else `DICOMwebError` on an HTTP failure.
    public func retrieve(
        studyUID: String,
        seriesUID: String,
        objectUID: String,
        parameters: Parameters
    ) async throws -> RetrieveResult {
        try parameters.validate()
        let url = try requestURL(studyUID: studyUID, seriesUID: seriesUID, objectUID: objectUID,
                                 parameters: parameters)
        let types = parameters.contentType.isEmpty ? [MediaType.dicom] : parameters.contentType
        let response = try await httpClient.get(url, headers: ["Accept": types.map(\.rawValue).joined(separator: ", ")])
        guard response.isSuccess else {
            let body = String(data: response.body, encoding: .utf8)
            throw DICOMwebError.fromHTTPStatus(response.statusCode, message: body)
        }
        return RetrieveResult(
            data: response.body,
            responseContentType: response.header("Content-Type"),
            statusCode: response.statusCode
        )
    }

    /// The WADO-URI request URL for `parameters` (not validated):
    /// `{endpoint}?requestType=WADO&studyUID=…&seriesUID=…&objectUID=…&contentType=…[&…]`.
    public func requestURL(studyUID: String, seriesUID: String, objectUID: String,
                           parameters: Parameters) throws -> URL {
        let endpoint = Self.resolveURIEndpoint(configuration.baseURL)
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw DICOMwebError.invalidURL(url: configuration.baseURL.absoluteString)
        }
        components.queryItems = [
            URLQueryItem(name: "requestType", value: "WADO"),
            URLQueryItem(name: "studyUID", value: studyUID),
            URLQueryItem(name: "seriesUID", value: seriesUID),
            URLQueryItem(name: "objectUID", value: objectUID),
        ] + parameters.queryItems()
        guard let url = components.url else {
            throw DICOMwebError.invalidURL(url: configuration.baseURL.absoluteString)
        }
        return url
    }

    /// Retrieves a DICOM object and returns only the raw data
    ///
    /// Convenience method that returns just the `Data` from a WADO-URI retrieve.
    ///
    /// - Parameters:
    ///   - studyUID: Study Instance UID
    ///   - seriesUID: Series Instance UID
    ///   - objectUID: SOP Instance UID
    ///   - contentType: Requested content type (default: .dicom)
    /// - Returns: The retrieved data bytes
    /// - Throws: DICOMwebError on failure
    public func retrieveData(
        studyUID: String,
        seriesUID: String,
        objectUID: String,
        contentType: ContentType = .dicom
    ) async throws -> Data {
        let result = try await retrieve(
            studyUID: studyUID,
            seriesUID: seriesUID,
            objectUID: objectUID,
            contentType: contentType
        )
        return result.data
    }

    // MARK: - URL Building

    /// Resolves the effective WADO-URI endpoint for a configured base URL.
    ///
    /// dcm4chee-arc (5.x) serves WADO-URI (PS3.18 §9) from its `/wado` servlet, while the
    /// sibling RESTful endpoint `/rs` (WADO-RS / QIDO-RS / STOW-RS) returns HTTP 404 for a
    /// `?requestType=WADO` query. A base URL whose final path segment is `rs` is therefore
    /// aimed at the wrong servlet for WADO-URI — almost always because the WADO-RS base URL
    /// (e.g. `…/dcm4chee-arc/aets/AET/rs`) was reused for a URI-mode request. Rewrite that
    /// trailing `/rs` to `/wado` so the request reaches the URI service.
    ///
    /// Any other base URL is already correct and is returned unchanged — dcm4chee2's root
    /// `/wado` endpoint, a custom WADO path, etc. The rewrite is safe to apply
    /// unconditionally here because `WADOURIClient` only ever issues WADO-URI requests, for
    /// which an `/rs` endpoint is never valid. Because the `dicom-wado` CLI, the in-app CLI
    /// Workshop, and the CLI-parity reference all retrieve through this one client, they
    /// resolve the endpoint identically and cannot drift.
    public static func resolveURIEndpoint(_ baseURL: URL) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }
        var segments = components.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let lastSegment = segments.lastIndex(where: { !$0.isEmpty }),
              segments[lastSegment].lowercased() == "rs" else {
            return baseURL
        }
        segments[lastSegment] = "wado"
        components.path = segments.joined(separator: "/")
        return components.url ?? baseURL
    }

    /// Builds a WADO-URI request URL with query parameters
    ///
    /// Reference: PS3.18 §9.4.1 / §9.5.1 — request syntax:
    ///   `{baseURL}?requestType=WADO&studyUID={studyUID}&seriesUID={seriesUID}&objectUID={objectUID}`
    private func buildURL(
        studyUID: String,
        seriesUID: String,
        objectUID: String,
        contentType: ContentType,
        transferSyntax: String?,
        anonymize: String?,
        rows: Int?,
        columns: Int?,
        frameNumber: Int?
    ) throws -> URL {
        // Resolve the WADO-URI servlet (rewriting a WADO-RS `/rs` base to `/wado`) before
        // appending the query parameters — see resolveURIEndpoint.
        let endpoint = Self.resolveURIEndpoint(configuration.baseURL)
        guard var components = URLComponents(
            url: endpoint,
            resolvingAgainstBaseURL: false
        ) else {
            throw DICOMwebError.invalidURL(url: configuration.baseURL.absoluteString)
        }

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "requestType", value: "WADO"),
            URLQueryItem(name: "studyUID", value: studyUID),
            URLQueryItem(name: "seriesUID", value: seriesUID),
            URLQueryItem(name: "objectUID", value: objectUID),
            URLQueryItem(name: "contentType", value: contentType.rawValue),
        ]

        if let transferSyntax, !transferSyntax.isEmpty {
            queryItems.append(URLQueryItem(name: "transferSyntax", value: transferSyntax))
        }
        if let anonymize, !anonymize.isEmpty {
            queryItems.append(URLQueryItem(name: "anonymize", value: anonymize))
        }
        if let rows {
            queryItems.append(URLQueryItem(name: "rows", value: String(rows)))
        }
        if let columns {
            queryItems.append(URLQueryItem(name: "columns", value: String(columns)))
        }
        if let frameNumber {
            queryItems.append(URLQueryItem(name: "frameNumber", value: String(frameNumber)))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw DICOMwebError.invalidURL(url: configuration.baseURL.absoluteString)
        }
        return url
    }
}

/// A WADO-URI request whose optional parameters break a rule of PS3.18 2026a Section 9
/// (each problem names its clause); the request was not sent.
public struct WADOURIParameterError: Error, CustomStringConvertible, Sendable, Equatable {
    public let problems: [String]
    public init(problems: [String]) { self.problems = problems }
    public var description: String { problems.joined(separator: "; ") }
}
#endif
