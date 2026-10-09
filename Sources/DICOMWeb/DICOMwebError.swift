import Foundation

// NEMA-verified: 2026a, checked 2026-09-28 — the 15 mapped status codes read against PS3.18 2026a Table 8.5-1 (413 listed; 422, 429, 502, 504 are generic HTTP codes the table does not list; 410 Gone is mapped to httpError)
/// Errors that can occur during DICOMweb operations
///
/// Reference: PS3.18 Section 8.5 - Status Codes (Table 8.5-1)
public enum DICOMwebError: Error, Sendable {
    // MARK: - HTTP Status Code Errors
    
    /// 400 Bad Request - The request was malformed or invalid
    case badRequest(message: String? = nil)
    
    /// 401 Unauthorized - Authentication is required
    case unauthorized(message: String? = nil)
    
    /// 403 Forbidden - Access to the resource is denied
    case forbidden(message: String? = nil)
    
    /// 404 Not Found - The requested resource does not exist
    case notFound(resource: String? = nil)
    
    /// 406 Not Acceptable - The requested representation is not available
    case notAcceptable(supported: [DICOMMediaType]? = nil)
    
    /// 409 Conflict - The request conflicts with the current state
    case conflict(message: String? = nil)
    
    /// 413 Payload Too Large - The request body exceeds the limit
    case payloadTooLarge(limit: Int? = nil)
    
    /// 415 Unsupported Media Type - The request content type is not supported
    case unsupportedMediaType(mediaType: String? = nil)
    
    /// 422 Unprocessable Entity - The request is well-formed but semantically incorrect
    case unprocessableEntity(message: String? = nil)
    
    /// 429 Too Many Requests - Rate limit exceeded
    case tooManyRequests(retryAfter: TimeInterval? = nil)
    
    /// 500 Internal Server Error - Server-side error
    case internalServerError(message: String? = nil)
    
    /// 501 Not Implemented - The requested functionality is not implemented
    case notImplemented(message: String? = nil)
    
    /// 502 Bad Gateway - Invalid response from upstream server
    case badGateway(message: String? = nil)
    
    /// 503 Service Unavailable - The server is temporarily unavailable
    case serviceUnavailable(retryAfter: TimeInterval? = nil)
    
    /// 504 Gateway Timeout - Upstream server timed out
    case gatewayTimeout(message: String? = nil)
    
    /// Other HTTP error with status code
    case httpError(statusCode: Int, message: String? = nil)
    
    // MARK: - Network Errors
    
    /// Network connection failed
    case connectionFailed(underlying: Error? = nil)
    
    /// Request timed out
    case timeout(operation: String? = nil)
    
    /// DNS lookup failed
    case dnsLookupFailed(host: String? = nil)
    
    /// SSL/TLS error
    case sslError(message: String? = nil)
    
    // MARK: - Data Format Errors
    
    /// Invalid DICOM JSON format
    case invalidJSON(reason: String? = nil)
    
    /// Invalid DICOM XML format
    case invalidXML(reason: String? = nil)
    
    /// Invalid multipart MIME format
    case invalidMultipart(reason: String? = nil)
    
    /// Missing required field in response
    case missingRequiredField(field: String)
    
    /// Invalid value representation encoding
    case invalidVREncoding(vr: String, reason: String? = nil)
    
    /// Invalid bulk data reference
    case invalidBulkDataReference(uri: String? = nil)
    
    /// Base64 decoding failed
    case base64DecodingFailed(reason: String? = nil)
    
    // MARK: - DICOM-Specific Errors
    
    /// Invalid Study Instance UID
    case invalidStudyUID(uid: String? = nil)
    
    /// Invalid Series Instance UID
    case invalidSeriesUID(uid: String? = nil)
    
    /// Invalid SOP Instance UID
    case invalidSOPInstanceUID(uid: String? = nil)
    
    /// Invalid frame number
    case invalidFrameNumber(frame: Int, maxFrame: Int? = nil)
    
    /// Transfer syntax not supported
    case transferSyntaxNotSupported(uid: String? = nil)
    
    /// SOP Class not supported
    case sopClassNotSupported(uid: String? = nil)
    
    // MARK: - Configuration Errors
    
    /// Invalid URL configuration
    case invalidURL(url: String? = nil)
    
    /// Missing required configuration
    case missingConfiguration(parameter: String)
    
    /// Invalid authentication configuration
    case invalidAuthentication(reason: String? = nil)
    
    // MARK: - Factory Methods
    
    /// Creates an error from an HTTP status code
    /// - Parameters:
    ///   - statusCode: The HTTP status code
    ///   - message: Optional error message
    ///   - headers: Response headers for extracting retry-after, etc.
    /// - Returns: An appropriate DICOMwebError
    public static func fromHTTPStatus(
        _ statusCode: Int,
        message: String? = nil,
        headers: [String: String]? = nil
    ) -> DICOMwebError {
        let retryAfter = headers?["Retry-After"].flatMap { TimeInterval($0) }
        
        switch statusCode {
        case 400: return .badRequest(message: message)
        case 401: return .unauthorized(message: message)
        case 403: return .forbidden(message: message)
        case 404: return .notFound(resource: message)
        case 406: return .notAcceptable(supported: nil)
        case 409: return .conflict(message: message)
        case 413: return .payloadTooLarge(limit: nil)
        case 415: return .unsupportedMediaType(mediaType: message)
        case 422: return .unprocessableEntity(message: message)
        case 429: return .tooManyRequests(retryAfter: retryAfter)
        case 500: return .internalServerError(message: message)
        case 501: return .notImplemented(message: message)
        case 502: return .badGateway(message: message)
        case 503: return .serviceUnavailable(retryAfter: retryAfter)
        case 504: return .gatewayTimeout(message: message)
        default: return .httpError(statusCode: statusCode, message: message)
        }
    }
}

// MARK: - Error Descriptions

extension DICOMwebError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .badRequest(let message):
            return "Bad Request\(message.map { ": \($0)" } ?? "")"
        case .unauthorized(let message):
            return "Unauthorized\(message.map { ": \($0)" } ?? "")"
        case .forbidden(let message):
            return "Forbidden\(message.map { ": \($0)" } ?? "")"
        case .notFound(let resource):
            return "Not Found\(resource.map { ": \($0)" } ?? "")"
        case .notAcceptable(let supported):
            let supportedStr = supported?.map { $0.description }.joined(separator: ", ")
            return "Not Acceptable\(supportedStr.map { ". Supported: \($0)" } ?? "")"
        case .conflict(let message):
            return "Conflict\(message.map { ": \($0)" } ?? "")"
        case .payloadTooLarge(let limit):
            return "Payload Too Large\(limit.map { ". Maximum: \($0) bytes" } ?? "")"
        case .unsupportedMediaType(let mediaType):
            return "Unsupported Media Type\(mediaType.map { ": \($0)" } ?? "")"
        case .unprocessableEntity(let message):
            return "Unprocessable Entity\(message.map { ": \($0)" } ?? "")"
        case .tooManyRequests(let retryAfter):
            return "Too Many Requests\(retryAfter.map { ". Retry after \($0) seconds" } ?? "")"
        case .internalServerError(let message):
            return "Internal Server Error\(message.map { ": \($0)" } ?? "")"
        case .notImplemented(let message):
            return "Not Implemented\(message.map { ": \($0)" } ?? "")"
        case .badGateway(let message):
            return "Bad Gateway\(message.map { ": \($0)" } ?? "")"
        case .serviceUnavailable(let retryAfter):
            return "Service Unavailable\(retryAfter.map { ". Retry after \($0) seconds" } ?? "")"
        case .gatewayTimeout(let message):
            return "Gateway Timeout\(message.map { ": \($0)" } ?? "")"
        case .httpError(let statusCode, let message):
            return "HTTP Error \(statusCode)\(message.map { ": \($0)" } ?? "")"
        case .connectionFailed(let underlying):
            // Surface the underlying URLError reason instead of a bare "Connection
            // failed". This is what reveals an App Transport Security block of cleartext
            // http:// (URLError -1022) — otherwise the real cause is hidden and operators
            // chase phantom UID/endpoint problems for a request that is actually correct.
            return "Connection failed" + (underlying.map { ": \($0.localizedDescription)" } ?? "")
        case .timeout(let operation):
            return "Timeout\(operation.map { " during \($0)" } ?? "")"
        case .dnsLookupFailed(let host):
            return "DNS lookup failed\(host.map { " for \($0)" } ?? "")"
        case .sslError(let message):
            return "SSL/TLS error\(message.map { ": \($0)" } ?? "")"
        case .invalidJSON(let reason):
            return "Invalid DICOM JSON\(reason.map { ": \($0)" } ?? "")"
        case .invalidXML(let reason):
            return "Invalid DICOM XML\(reason.map { ": \($0)" } ?? "")"
        case .invalidMultipart(let reason):
            return "Invalid multipart MIME\(reason.map { ": \($0)" } ?? "")"
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        case .invalidVREncoding(let vr, let reason):
            return "Invalid VR encoding for \(vr)\(reason.map { ": \($0)" } ?? "")"
        case .invalidBulkDataReference(let uri):
            return "Invalid bulk data reference\(uri.map { ": \($0)" } ?? "")"
        case .base64DecodingFailed(let reason):
            return "Base64 decoding failed\(reason.map { ": \($0)" } ?? "")"
        case .invalidStudyUID(let uid):
            return "Invalid Study Instance UID\(uid.map { ": \($0)" } ?? "")"
        case .invalidSeriesUID(let uid):
            return "Invalid Series Instance UID\(uid.map { ": \($0)" } ?? "")"
        case .invalidSOPInstanceUID(let uid):
            return "Invalid SOP Instance UID\(uid.map { ": \($0)" } ?? "")"
        case .invalidFrameNumber(let frame, let maxFrame):
            return "Invalid frame number \(frame)\(maxFrame.map { ". Maximum: \($0)" } ?? "")"
        case .transferSyntaxNotSupported(let uid):
            return "Transfer syntax not supported\(uid.map { ": \($0)" } ?? "")"
        case .sopClassNotSupported(let uid):
            return "SOP Class not supported\(uid.map { ": \($0)" } ?? "")"
        case .invalidURL(let url):
            return "Invalid URL\(url.map { ": \($0)" } ?? "")"
        case .missingConfiguration(let parameter):
            return "Missing configuration: \(parameter)"
        case .invalidAuthentication(let reason):
            return "Invalid authentication\(reason.map { ": \($0)" } ?? "")"
        }
    }
}

// MARK: - Error Categories

extension DICOMwebError {
    /// Indicates if the error is transient and the operation can be retried
    public var isTransient: Bool {
        switch self {
        case .timeout, .connectionFailed, .dnsLookupFailed,
             .serviceUnavailable, .gatewayTimeout, .tooManyRequests:
            return true
        case .httpError(let statusCode, _) where statusCode >= 500:
            return true
        default:
            return false
        }
    }
    
    /// Indicates if the error is a client error (4xx)
    public var isClientError: Bool {
        switch self {
        case .badRequest, .unauthorized, .forbidden, .notFound,
             .notAcceptable, .conflict, .payloadTooLarge,
             .unsupportedMediaType, .unprocessableEntity, .tooManyRequests:
            return true
        case .httpError(let statusCode, _) where statusCode >= 400 && statusCode < 500:
            return true
        default:
            return false
        }
    }
    
    /// Indicates if the error is a server error (5xx)
    public var isServerError: Bool {
        switch self {
        case .internalServerError, .notImplemented, .badGateway,
             .serviceUnavailable, .gatewayTimeout:
            return true
        case .httpError(let statusCode, _) where statusCode >= 500:
            return true
        default:
            return false
        }
    }
    
    /// The suggested retry delay, if applicable
    public var retryAfter: TimeInterval? {
        switch self {
        case .tooManyRequests(let retryAfter):
            return retryAfter
        case .serviceUnavailable(let retryAfter):
            return retryAfter
        default:
            return nil
        }
    }
}
