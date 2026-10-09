import Foundation

// NEMA-verified: 2026a, checked 2026-09-28 — carries no DICOM-standard data (RFC 6749 §5.1 / §5.2 token and error responses)
/// OAuth2 token response
///
/// Represents an OAuth2 access token with optional refresh token
/// and expiration information.
///
/// Reference: RFC 6749 Section 5.1 - Successful Response
public struct OAuth2Token: Sendable, Codable, Equatable {
    /// The access token string
    public let accessToken: String
    
    /// The token type (typically "Bearer")
    public let tokenType: String
    
    /// The refresh token (optional)
    public let refreshToken: String?
    
    /// Token expiration time in seconds from issuance
    public let expiresIn: Int?
    
    /// The scopes granted (may differ from requested)
    public let scope: String?
    
    /// The ID token for OpenID Connect (optional)
    public let idToken: String?
    
    /// Time when the token was issued
    public let issuedAt: Date
    
    // MARK: - Coding Keys
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
        case idToken = "id_token"
    }
    
    // MARK: - Initialization
    
    /// Creates an OAuth2 token
    /// - Parameters:
    ///   - accessToken: The access token string
    ///   - tokenType: The token type (default: "Bearer")
    ///   - refreshToken: Optional refresh token
    ///   - expiresIn: Token expiration in seconds
    ///   - scope: Granted scopes
    ///   - idToken: Optional OpenID Connect ID token
    ///   - issuedAt: Time of issuance (default: now)
    public init(
        accessToken: String,
        tokenType: String = "Bearer",
        refreshToken: String? = nil,
        expiresIn: Int? = nil,
        scope: String? = nil,
        idToken: String? = nil,
        issuedAt: Date = Date()
    ) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.scope = scope
        self.idToken = idToken
        self.issuedAt = issuedAt
    }
    
    // MARK: - Codable
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        tokenType = try container.decodeIfPresent(String.self, forKey: .tokenType) ?? "Bearer"
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        expiresIn = try container.decodeIfPresent(Int.self, forKey: .expiresIn)
        scope = try container.decodeIfPresent(String.self, forKey: .scope)
        idToken = try container.decodeIfPresent(String.self, forKey: .idToken)
        issuedAt = Date()
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accessToken, forKey: .accessToken)
        try container.encode(tokenType, forKey: .tokenType)
        try container.encodeIfPresent(refreshToken, forKey: .refreshToken)
        try container.encodeIfPresent(expiresIn, forKey: .expiresIn)
        try container.encodeIfPresent(scope, forKey: .scope)
        try container.encodeIfPresent(idToken, forKey: .idToken)
    }
    
    // MARK: - Expiration
    
    /// The expiration date of the token (if known)
    public var expirationDate: Date? {
        guard let expiresIn = expiresIn else { return nil }
        return issuedAt.addingTimeInterval(TimeInterval(expiresIn))
    }
    
    /// Whether the token is expired
    public var isExpired: Bool {
        guard let expirationDate = expirationDate else { return false }
        return Date() >= expirationDate
    }
    
    /// Whether the token will expire soon (within buffer time)
    /// - Parameter buffer: Time buffer in seconds (default: 60)
    /// - Returns: True if token expires within the buffer time
    public func willExpireSoon(buffer: TimeInterval = 60) -> Bool {
        guard let expirationDate = expirationDate else { return false }
        return Date().addingTimeInterval(buffer) >= expirationDate
    }
    
    /// Whether the token needs refresh (expired or expiring soon)
    /// - Parameter buffer: Time buffer in seconds
    /// - Returns: True if token should be refreshed
    public func needsRefresh(buffer: TimeInterval = 60) -> Bool {
        return isExpired || willExpireSoon(buffer: buffer)
    }
    
    /// The granted scopes as an array
    public var scopes: [String] {
        guard let scope = scope else { return [] }
        return scope.components(separatedBy: " ").filter { !$0.isEmpty }
    }
    
    /// The Authorization header value
    public var authorizationHeader: String {
        return "\(tokenType) \(accessToken)"
    }
}

// MARK: - OAuth2 Error

/// OAuth2 error response
///
/// Reference: RFC 6749 Section 5.2 - Error Response
public struct OAuth2Error: Error, Sendable, Codable, Equatable {
    /// The error code
    public let error: ErrorCode
    
    /// Human-readable error description from server
    public let message: String?
    
    /// URI to error documentation
    public let errorURI: String?
    
    // MARK: - Coding Keys
    
    enum CodingKeys: String, CodingKey {
        case error
        case message = "error_description"
        case errorURI = "error_uri"
    }
    
    // MARK: - Error Codes
    
    /// OAuth2 error codes
    public enum ErrorCode: String, Sendable, Codable {
        /// Invalid request
        case invalidRequest = "invalid_request"
        
        /// Invalid client credentials
        case invalidClient = "invalid_client"
        
        /// Invalid grant
        case invalidGrant = "invalid_grant"
        
        /// Unauthorized client
        case unauthorizedClient = "unauthorized_client"
        
        /// Unsupported grant type
        case unsupportedGrantType = "unsupported_grant_type"
        
        /// Invalid scope
        case invalidScope = "invalid_scope"
        
        /// Access denied (authorization code flow)
        case accessDenied = "access_denied"
        
        /// Unsupported response type
        case unsupportedResponseType = "unsupported_response_type"
        
        /// Server error
        case serverError = "server_error"
        
        /// Temporarily unavailable
        case temporarilyUnavailable = "temporarily_unavailable"
        
        /// Unknown error code
        case unknown
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            self = ErrorCode(rawValue: rawValue) ?? .unknown
        }
    }
    
    // MARK: - Initialization
    
    /// Creates an OAuth2 error
    /// - Parameters:
    ///   - error: The error code
    ///   - message: Human-readable description
    ///   - errorURI: URI to documentation
    public init(
        error: ErrorCode,
        errorDescription message: String? = nil,
        errorURI: String? = nil
    ) {
        self.error = error
        self.message = message
        self.errorURI = errorURI
    }
}

// MARK: - LocalizedError

extension OAuth2Error: LocalizedError {
    public var errorDescription: String? {
        if let serverMessage = message {
            return serverMessage
        }
        
        switch error {
        case .invalidRequest:
            return "The request is malformed or missing required parameters."
        case .invalidClient:
            return "Client authentication failed."
        case .invalidGrant:
            return "The provided authorization grant is invalid, expired, or revoked."
        case .unauthorizedClient:
            return "The client is not authorized to use this grant type."
        case .unsupportedGrantType:
            return "The grant type is not supported by the authorization server."
        case .invalidScope:
            return "The requested scope is invalid, unknown, or malformed."
        case .accessDenied:
            return "The resource owner denied the request."
        case .unsupportedResponseType:
            return "The response type is not supported."
        case .serverError:
            return "The authorization server encountered an unexpected error."
        case .temporarilyUnavailable:
            return "The authorization server is temporarily unavailable."
        case .unknown:
            return "An unknown OAuth2 error occurred."
        }
    }
}

// MARK: - PKCE

#if canImport(CryptoKit)
import CryptoKit
#endif

/// PKCE (Proof Key for Code Exchange) support
///
/// Reference: RFC 7636 - Proof Key for Code Exchange
public struct PKCE: Sendable {
    /// The code verifier (random string)
    public let codeVerifier: String
    
    /// The code challenge (derived from verifier)
    public let codeChallenge: String
    
    /// The code challenge method
    public let codeChallengeMethod: String
    
    #if canImport(CryptoKit) && (os(macOS) || os(iOS) || os(visionOS) || os(tvOS) || os(watchOS))
    /// Creates a new PKCE pair
    public init() {
        // Generate a random 32-byte code verifier
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        
        // Base64URL encode (RFC 4648)
        codeVerifier = Self.base64URLEncode(Data(bytes))
        
        // Create SHA256 hash and Base64URL encode
        let data = Data(codeVerifier.utf8)
        let hash = SHA256.hash(data: data)
        codeChallenge = Self.base64URLEncode(Data(hash))
        
        codeChallengeMethod = "S256"
    }
    #else
    /// Creates a new PKCE pair (non-Apple platforms)
    public init() {
        // Use a simple random string for non-Apple platforms
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        codeVerifier = String((0..<43).map { _ in characters.randomElement()! })
        
        // For non-Apple platforms without CryptoKit, use plain method
        // This is less secure but maintains compatibility
        codeChallenge = codeVerifier
        codeChallengeMethod = "plain"
    }
    #endif
    
    /// Creates PKCE with specified values (for testing)
    /// - Parameters:
    ///   - codeVerifier: The code verifier
    ///   - codeChallenge: The code challenge
    ///   - codeChallengeMethod: The challenge method (default: "S256")
    public init(
        codeVerifier: String,
        codeChallenge: String,
        codeChallengeMethod: String = "S256"
    ) {
        self.codeVerifier = codeVerifier
        self.codeChallenge = codeChallenge
        self.codeChallengeMethod = codeChallengeMethod
    }
    
    /// Base64URL encodes data
    /// - Parameter data: Data to encode
    /// - Returns: Base64URL encoded string
    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
