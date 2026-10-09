import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// NEMA-verified: 2026a, checked 2026-09-28 — carries no DICOM-standard data (RFC 6749 token fetch and refresh)
/// Protocol for providing OAuth2 tokens with automatic refresh
///
/// Conforming types manage the OAuth2 token lifecycle including
/// acquiring, caching, and refreshing tokens.
public protocol OAuth2TokenProvider: Sendable {
    /// Gets a valid access token, refreshing if necessary
    /// - Returns: A valid access token string
    /// - Throws: OAuth2Error on authentication failure
    func getAccessToken() async throws -> String
    
    /// Forces a token refresh
    /// - Returns: The new access token
    /// - Throws: OAuth2Error on refresh failure
    func refreshAccessToken() async throws -> String
    
    /// Clears any cached tokens
    func clearTokens() async
    
    /// The current token (may be expired)
    var currentToken: OAuth2Token? { get async }
}

/// OAuth2 token manager with automatic refresh support
///
/// Manages the OAuth2 token lifecycle including:
/// - Client credentials flow (machine-to-machine)
/// - Token caching
/// - Automatic refresh before expiration
///
/// Example usage:
/// ```swift
/// let config = OAuth2Configuration.clientCredentials(
///     tokenEndpoint: URL(string: "https://auth.example.com/token")!,
///     clientID: "my-client",
///     clientSecret: "secret",
///     scopes: ["dicom.read"]
/// )
/// let tokenProvider = OAuth2TokenManager(configuration: config)
/// let token = try await tokenProvider.getAccessToken()
/// ```
#if canImport(FoundationNetworking) || os(macOS) || os(iOS) || os(visionOS) || os(tvOS) || os(watchOS)
public actor OAuth2TokenManager: OAuth2TokenProvider {
    
    // MARK: - Properties
    
    /// The OAuth2 configuration
    public let configuration: OAuth2Configuration
    
    /// The current token (if any)
    private var token: OAuth2Token?
    
    /// The URL session for token requests
    private let session: URLSession
    
    /// Lock to prevent concurrent refresh
    private var refreshTask: Task<OAuth2Token, Error>?
    
    // MARK: - Initialization
    
    /// Creates an OAuth2 token manager
    /// - Parameter configuration: The OAuth2 configuration
    public init(configuration: OAuth2Configuration) {
        self.configuration = configuration
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30
        sessionConfig.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: sessionConfig)
    }
    
    /// Creates an OAuth2 token manager with an existing token
    /// - Parameters:
    ///   - configuration: The OAuth2 configuration
    ///   - token: An existing token to use
    public init(configuration: OAuth2Configuration, token: OAuth2Token) {
        self.configuration = configuration
        self.token = token
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30
        sessionConfig.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: sessionConfig)
    }
    
    // MARK: - OAuth2TokenProvider
    
    public var currentToken: OAuth2Token? {
        return token
    }
    
    public func getAccessToken() async throws -> String {
        // Check if we have a valid token
        if let existingToken = token, !existingToken.needsRefresh(buffer: configuration.refreshBufferTime) {
            return existingToken.accessToken
        }
        
        // Try to refresh if we have a refresh token
        if let existingToken = token,
           existingToken.refreshToken != nil {
            return try await refreshAccessToken()
        }
        
        // Otherwise, acquire a new token
        let newToken = try await acquireToken()
        token = newToken
        return newToken.accessToken
    }
    
    public func refreshAccessToken() async throws -> String {
        // Check if there's already a refresh in progress
        if let existingTask = refreshTask {
            let result = try await existingTask.value
            return result.accessToken
        }
        
        // Start a new refresh task
        let task = Task<OAuth2Token, Error> {
            let newToken: OAuth2Token
            
            if let existingToken = token,
               let refreshToken = existingToken.refreshToken {
                // Use refresh token
                newToken = try await performRefreshToken(refreshToken)
            } else {
                // Re-acquire token using client credentials
                newToken = try await acquireToken()
            }
            
            self.token = newToken
            return newToken
        }
        
        refreshTask = task
        
        defer {
            refreshTask = nil
        }
        
        let result = try await task.value
        return result.accessToken
    }
    
    public func clearTokens() async {
        token = nil
        refreshTask?.cancel()
        refreshTask = nil
    }
    
    // MARK: - Token Acquisition
    
    private func acquireToken() async throws -> OAuth2Token {
        guard configuration.availableGrantType == .clientCredentials else {
            throw OAuth2Error(
                error: .unsupportedGrantType,
                errorDescription: "Only client credentials flow is supported for automatic token acquisition"
            )
        }
        
        return try await performClientCredentials()
    }
    
    /// Performs client credentials flow
    private func performClientCredentials() async throws -> OAuth2Token {
        guard let clientSecret = configuration.clientSecret else {
            throw OAuth2Error(
                error: .invalidClient,
                errorDescription: "Client secret is required for client credentials flow"
            )
        }
        
        var request = URLRequest(url: configuration.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Build request body
        var params: [String: String] = [
            "grant_type": OAuth2Configuration.GrantType.clientCredentials.rawValue,
            "client_id": configuration.clientID,
            "client_secret": clientSecret
        ]
        
        if !configuration.scopes.isEmpty {
            params["scope"] = configuration.scopes.joined(separator: " ")
        }
        
        request.httpBody = encodeFormData(params)
        
        return try await executeTokenRequest(request)
    }
    
    /// Performs token refresh
    private func performRefreshToken(_ refreshToken: String) async throws -> OAuth2Token {
        var request = URLRequest(url: configuration.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var params: [String: String] = [
            "grant_type": OAuth2Configuration.GrantType.refreshToken.rawValue,
            "refresh_token": refreshToken,
            "client_id": configuration.clientID
        ]
        
        if let clientSecret = configuration.clientSecret {
            params["client_secret"] = clientSecret
        }
        
        request.httpBody = encodeFormData(params)
        
        return try await executeTokenRequest(request)
    }
    
    /// Executes a token request and parses the response
    private func executeTokenRequest(_ request: URLRequest) async throws -> OAuth2Token {
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuth2Error(
                error: .serverError,
                errorDescription: "Invalid response from authorization server"
            )
        }
        
        // Check for error response
        if !((200..<300).contains(httpResponse.statusCode)) {
            // Try to parse OAuth2 error
            if let errorResponse = try? JSONDecoder().decode(OAuth2Error.self, from: data) {
                throw errorResponse
            }
            
            throw OAuth2Error(
                error: .serverError,
                errorDescription: "Token request failed with status \(httpResponse.statusCode)"
            )
        }
        
        // Parse token response
        return try JSONDecoder().decode(OAuth2Token.self, from: data)
    }
    
    // MARK: - Authorization Code Flow Support
    
    /// Builds the authorization URL for authorization code flow
    /// - Parameters:
    ///   - state: A random state value for CSRF protection
    ///   - pkce: Optional PKCE parameters
    /// - Returns: The authorization URL
    /// - Throws: OAuth2Error if authorization endpoint is not configured
    public func buildAuthorizationURL(state: String, pkce: PKCE? = nil) throws -> URL {
        guard let authEndpoint = configuration.authorizationEndpoint else {
            throw OAuth2Error(
                error: .invalidRequest,
                errorDescription: "Authorization endpoint is not configured"
            )
        }
        
        guard let redirectURI = configuration.redirectURI else {
            throw OAuth2Error(
                error: .invalidRequest,
                errorDescription: "Redirect URI is not configured"
            )
        }
        
        var components = URLComponents(url: authEndpoint, resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "state", value: state)
        ]
        
        if !configuration.scopes.isEmpty {
            queryItems.append(URLQueryItem(name: "scope", value: configuration.scopes.joined(separator: " ")))
        }
        
        if let pkce = pkce {
            queryItems.append(URLQueryItem(name: "code_challenge", value: pkce.codeChallenge))
            queryItems.append(URLQueryItem(name: "code_challenge_method", value: pkce.codeChallengeMethod))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else {
            throw OAuth2Error(
                error: .invalidRequest,
                errorDescription: "Failed to build authorization URL"
            )
        }
        
        return url
    }
    
    /// Exchanges an authorization code for tokens
    /// - Parameters:
    ///   - code: The authorization code
    ///   - pkce: The PKCE verifier used in the authorization request
    /// - Returns: The OAuth2 token
    /// - Throws: OAuth2Error on failure
    public func exchangeAuthorizationCode(_ code: String, pkce: PKCE? = nil) async throws -> OAuth2Token {
        guard let redirectURI = configuration.redirectURI else {
            throw OAuth2Error(
                error: .invalidRequest,
                errorDescription: "Redirect URI is not configured"
            )
        }
        
        var request = URLRequest(url: configuration.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var params: [String: String] = [
            "grant_type": OAuth2Configuration.GrantType.authorizationCode.rawValue,
            "code": code,
            "redirect_uri": redirectURI.absoluteString,
            "client_id": configuration.clientID
        ]
        
        if let clientSecret = configuration.clientSecret {
            params["client_secret"] = clientSecret
        }
        
        if let pkce = pkce {
            params["code_verifier"] = pkce.codeVerifier
        }
        
        request.httpBody = encodeFormData(params)
        
        let newToken = try await executeTokenRequest(request)
        token = newToken
        return newToken
    }
    
    // MARK: - Helpers
    
    private func encodeFormData(_ params: [String: String]) -> Data {
        let encoded = params.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
        
        return Data(encoded.utf8)
    }
}
#endif

// MARK: - Static Token Provider

/// A simple token provider that returns a static token
///
/// Useful for testing or when tokens are managed externally.
public actor StaticTokenProvider: OAuth2TokenProvider {
    private var token: OAuth2Token?
    
    /// Creates a static token provider
    /// - Parameter token: The token to provide
    public init(token: OAuth2Token) {
        self.token = token
    }
    
    /// Creates a static token provider from just an access token string
    /// - Parameter accessToken: The access token string
    public init(accessToken: String) {
        self.token = OAuth2Token(accessToken: accessToken)
    }
    
    public var currentToken: OAuth2Token? {
        return token
    }
    
    public func getAccessToken() async throws -> String {
        guard let token = token else {
            throw OAuth2Error(error: .invalidGrant, errorDescription: "No token available")
        }
        return token.accessToken
    }
    
    public func refreshAccessToken() async throws -> String {
        // Static tokens cannot be refreshed
        throw OAuth2Error(error: .invalidGrant, errorDescription: "Static tokens cannot be refreshed")
    }
    
    public func clearTokens() async {
        token = nil
    }
    
    /// Updates the token
    /// - Parameter newToken: The new token
    public func setToken(_ newToken: OAuth2Token) {
        token = newToken
    }
}
