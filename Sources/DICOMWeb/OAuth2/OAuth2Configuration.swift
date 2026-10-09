import Foundation

// NEMA-verified: 2026a, checked 2026-09-28 — carries no DICOM-standard data (OAuth2 / SMART on FHIR scopes, RFC 6749; not governed by DICOM)
/// Configuration for OAuth2 authentication
///
/// Supports multiple OAuth2 flows including client credentials, authorization code,
/// and SMART on FHIR for healthcare integration.
///
/// Reference: RFC 6749 - The OAuth 2.0 Authorization Framework
/// Reference: SMART on FHIR - http://hl7.org/fhir/smart-app-launch/
public struct OAuth2Configuration: Sendable {
    /// The OAuth2 authorization endpoint URL
    public let authorizationEndpoint: URL?
    
    /// The OAuth2 token endpoint URL
    public let tokenEndpoint: URL
    
    /// The client identifier
    public let clientID: String
    
    /// The client secret (optional, may be absent for public clients)
    public let clientSecret: String?
    
    /// The redirect URI for authorization code flow
    public let redirectURI: URL?
    
    /// OAuth2 scopes to request
    public let scopes: [String]
    
    /// Whether to use PKCE (Proof Key for Code Exchange)
    public let usePKCE: Bool
    
    /// Token refresh buffer time (refresh before expiration)
    public let refreshBufferTime: TimeInterval
    
    /// Creates an OAuth2 configuration
    /// - Parameters:
    ///   - authorizationEndpoint: The authorization endpoint URL (required for auth code flow)
    ///   - tokenEndpoint: The token endpoint URL
    ///   - clientID: The client identifier
    ///   - clientSecret: The client secret (optional for public clients)
    ///   - redirectURI: The redirect URI for authorization code flow
    ///   - scopes: OAuth2 scopes to request
    ///   - usePKCE: Whether to use PKCE (default: true)
    ///   - refreshBufferTime: Time before expiration to refresh (default: 60 seconds)
    public init(
        authorizationEndpoint: URL? = nil,
        tokenEndpoint: URL,
        clientID: String,
        clientSecret: String? = nil,
        redirectURI: URL? = nil,
        scopes: [String] = [],
        usePKCE: Bool = true,
        refreshBufferTime: TimeInterval = 60
    ) {
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        self.scopes = scopes
        self.usePKCE = usePKCE
        self.refreshBufferTime = refreshBufferTime
    }
}

// MARK: - OAuth2 Flow Types

extension OAuth2Configuration {
    /// OAuth2 grant types
    public enum GrantType: String, Sendable {
        /// Client credentials grant (machine-to-machine)
        case clientCredentials = "client_credentials"
        
        /// Authorization code grant (user authentication)
        case authorizationCode = "authorization_code"
        
        /// Refresh token grant
        case refreshToken = "refresh_token"
    }
    
    /// Determines the available grant type based on configuration
    public var availableGrantType: GrantType? {
        if authorizationEndpoint != nil && redirectURI != nil {
            return .authorizationCode
        } else if clientSecret != nil {
            return .clientCredentials
        }
        return nil
    }
}

// MARK: - SMART on FHIR

extension OAuth2Configuration {
    /// SMART on FHIR scopes
    public enum SMARTScope: String, Sendable, CaseIterable {
        /// Launch context from EHR
        case launchEHR = "launch"
        
        /// Launch context from standalone app
        case launchStandalone = "launch/patient"
        
        /// OpenID Connect identity
        case openID = "openid"
        
        /// FHIR user identity
        case fhirUser = "fhirUser"
        
        /// Online access (default token lifetime)
        case onlineAccess = "online_access"
        
        /// Offline access (refresh token)
        case offlineAccess = "offline_access"
        
        /// Read patient data
        case patientRead = "patient/*.read"
        
        /// Read user data
        case userRead = "user/*.read"
        
        /// Read system data
        case systemRead = "system/*.read"
        
        /// Read all DICOM instances
        case dicomRead = "system/ImagingStudy.read"
        
        /// Write DICOM instances
        case dicomWrite = "system/ImagingStudy.write"
    }
    
    /// Creates a SMART on FHIR configuration
    /// - Parameters:
    ///   - fhirBaseURL: The FHIR server base URL
    ///   - clientID: The client identifier
    ///   - clientSecret: The client secret (optional for public clients)
    ///   - redirectURI: The redirect URI
    ///   - scopes: SMART scopes to request
    ///   - usePKCE: Whether to use PKCE
    /// - Returns: OAuth2 configuration for SMART on FHIR
    public static func smartOnFHIR(
        fhirBaseURL: URL,
        clientID: String,
        clientSecret: String? = nil,
        redirectURI: URL? = nil,
        scopes: [SMARTScope] = [.openID, .fhirUser, .patientRead],
        usePKCE: Bool = true
    ) -> OAuth2Configuration {
        // Standard SMART endpoints relative to FHIR base
        let authURL = fhirBaseURL.appendingPathComponent("authorize")
        let tokenURL = fhirBaseURL.appendingPathComponent("token")
        
        return OAuth2Configuration(
            authorizationEndpoint: authURL,
            tokenEndpoint: tokenURL,
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: redirectURI,
            scopes: scopes.map { $0.rawValue },
            usePKCE: usePKCE
        )
    }
    
    /// Discovers SMART endpoints from a FHIR server
    /// - Parameter fhirBaseURL: The FHIR server base URL
    /// - Returns: The well-known SMART configuration URL
    public static func smartWellKnownURL(for fhirBaseURL: URL) -> URL {
        fhirBaseURL.appendingPathComponent(".well-known/smart-configuration")
    }
}

// MARK: - Preset Configurations

extension OAuth2Configuration {
    /// Creates a client credentials configuration
    /// - Parameters:
    ///   - tokenEndpoint: The token endpoint URL
    ///   - clientID: The client identifier
    ///   - clientSecret: The client secret
    ///   - scopes: Scopes to request
    /// - Returns: OAuth2 configuration for client credentials flow
    public static func clientCredentials(
        tokenEndpoint: URL,
        clientID: String,
        clientSecret: String,
        scopes: [String] = []
    ) -> OAuth2Configuration {
        OAuth2Configuration(
            tokenEndpoint: tokenEndpoint,
            clientID: clientID,
            clientSecret: clientSecret,
            scopes: scopes,
            usePKCE: false
        )
    }
    
    /// Creates an authorization code configuration
    /// - Parameters:
    ///   - authorizationEndpoint: The authorization endpoint URL
    ///   - tokenEndpoint: The token endpoint URL
    ///   - clientID: The client identifier
    ///   - clientSecret: The client secret (optional for public clients)
    ///   - redirectURI: The redirect URI
    ///   - scopes: Scopes to request
    ///   - usePKCE: Whether to use PKCE
    /// - Returns: OAuth2 configuration for authorization code flow
    public static func authorizationCode(
        authorizationEndpoint: URL,
        tokenEndpoint: URL,
        clientID: String,
        clientSecret: String? = nil,
        redirectURI: URL,
        scopes: [String] = [],
        usePKCE: Bool = true
    ) -> OAuth2Configuration {
        OAuth2Configuration(
            authorizationEndpoint: authorizationEndpoint,
            tokenEndpoint: tokenEndpoint,
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: redirectURI,
            scopes: scopes,
            usePKCE: usePKCE
        )
    }
}
