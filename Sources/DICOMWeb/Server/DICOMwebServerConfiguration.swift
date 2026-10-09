import Foundation

// NEMA-verified: 2026a, checked 2026-09-28 — carries no DICOM-standard data (ports, TLS files, CORS, STOW policies); TLS is PS3.15 B.12, not PS3.18
/// Configuration for DICOMweb server
///
/// Contains settings for hosting a DICOMweb server including
/// binding address, port, paths, and security settings.
///
/// Reference: PS3.18 - Web Services
public struct DICOMwebServerConfiguration: Sendable {
    /// The port to listen on
    public let port: Int
    
    /// The host/address to bind to
    public let host: String
    
    /// The base URL path prefix (e.g., "/dicom-web")
    public let pathPrefix: String
    
    /// TLS configuration for HTTPS
    public let tlsConfiguration: TLSConfiguration?
    
    /// Maximum request body size in bytes
    public let maxRequestBodySize: Int
    
    /// Maximum concurrent requests
    public let maxConcurrentRequests: Int
    
    /// CORS configuration
    public let corsConfiguration: CORSConfiguration?
    
    /// Rate limiting configuration
    public let rateLimitConfiguration: RateLimitConfiguration?
    
    /// STOW-RS configuration
    public let stowConfiguration: STOWConfiguration
    
    /// Server name for response headers
    public let serverName: String
    
    /// Compression configuration for HTTP responses
    public let compressionConfiguration: CompressionConfiguration
    
    /// Server-side cache configuration for HTTP responses
    public let cacheConfiguration: CacheConfiguration
    
    /// Creates a DICOMweb server configuration
    /// - Parameters:
    ///   - port: The port to listen on (default: 8042)
    ///   - host: The host to bind to (default: "0.0.0.0")
    ///   - pathPrefix: URL path prefix (default: "/dicom-web")
    ///   - tlsConfiguration: Optional TLS configuration
    ///   - maxRequestBodySize: Maximum request body size (default: 500MB)
    ///   - maxConcurrentRequests: Maximum concurrent requests (default: 100)
    ///   - corsConfiguration: Optional CORS configuration
    ///   - rateLimitConfiguration: Optional rate limiting
    ///   - stowConfiguration: STOW-RS configuration (default: .default)
    ///   - serverName: Server name for headers (default: "DICOMKit/1.0")
    ///   - compressionConfiguration: HTTP response compression settings (default: .default)
    ///   - cacheConfiguration: Server-side cache settings (default: .disabled)
    public init(
        port: Int = 8042,
        host: String = "0.0.0.0",
        pathPrefix: String = "/dicom-web",
        tlsConfiguration: TLSConfiguration? = nil,
        maxRequestBodySize: Int = 500 * 1024 * 1024,
        maxConcurrentRequests: Int = 100,
        corsConfiguration: CORSConfiguration? = nil,
        rateLimitConfiguration: RateLimitConfiguration? = nil,
        stowConfiguration: STOWConfiguration = .default,
        serverName: String = "DICOMKit/1.0",
        compressionConfiguration: CompressionConfiguration = .default,
        cacheConfiguration: CacheConfiguration = .disabled
    ) {
        self.port = port
        self.host = host
        self.pathPrefix = pathPrefix
        self.tlsConfiguration = tlsConfiguration
        self.maxRequestBodySize = maxRequestBodySize
        self.maxConcurrentRequests = maxConcurrentRequests
        self.corsConfiguration = corsConfiguration
        self.rateLimitConfiguration = rateLimitConfiguration
        self.stowConfiguration = stowConfiguration
        self.serverName = serverName
        self.compressionConfiguration = compressionConfiguration
        self.cacheConfiguration = cacheConfiguration
    }
    
    /// The base URL for the server (computed without TLS)
    public var baseURL: URL {
        let scheme = tlsConfiguration != nil ? "https" : "http"
        // Use localhost instead of 0.0.0.0 for URL generation
        let hostForURL = host == "0.0.0.0" ? "localhost" : host
        return URL(string: "\(scheme)://\(hostForURL):\(port)\(pathPrefix)")!
    }
}

// MARK: - TLS Configuration

extension DICOMwebServerConfiguration {
    /// TLS configuration for secure HTTPS connections
    ///
    /// Provides comprehensive TLS settings for the DICOMweb server including
    /// certificate management, protocol versions, and client authentication (mTLS).
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // Basic HTTPS configuration
    /// let tlsConfig = TLSConfiguration(
    ///     certificatePath: "/path/to/server.pem",
    ///     privateKeyPath: "/path/to/server.key"
    /// )
    ///
    /// // With client certificate authentication (mTLS)
    /// let mtlsConfig = TLSConfiguration(
    ///     certificatePath: "/path/to/server.pem",
    ///     privateKeyPath: "/path/to/server.key",
    ///     requireClientCertificate: true,
    ///     clientCACertificatePath: "/path/to/ca.pem"
    /// )
    ///
    /// // Using presets
    /// let strictConfig = TLSConfiguration.strict(
    ///     certificatePath: "/path/to/server.pem",
    ///     privateKeyPath: "/path/to/server.key"
    /// )
    /// ```
    ///
    /// Reference: PS3.15 Annex B.12 - Secure Transport Connection Profiles (PS3.18 Section 6 is Conformance)
    public struct TLSConfiguration: Sendable, Equatable {
        /// Path to the certificate file (PEM or DER format)
        public let certificatePath: String
        
        /// Path to the private key file (PEM format)
        public let privateKeyPath: String
        
        /// Password for the private key (if encrypted)
        public let privateKeyPassword: String?
        
        /// Minimum TLS protocol version to accept
        public let minimumTLSVersion: TLSVersion
        
        /// Maximum TLS protocol version to accept (nil means latest available)
        public let maximumTLSVersion: TLSVersion?
        
        /// Whether to require client certificates for mutual TLS (mTLS)
        public let requireClientCertificate: Bool
        
        /// Path to CA certificates for client certificate verification
        public let clientCACertificatePath: String?
        
        /// Certificate validation mode for client certificates
        public let clientCertificateValidation: CertificateValidationMode
        
        /// Whether to allow self-signed client certificates (for development)
        public let allowSelfSignedClientCertificates: Bool
        
        /// Cipher suites to use (empty array uses system defaults)
        public let cipherSuites: [String]
        
        /// Creates a TLS configuration for the DICOMweb server
        ///
        /// - Parameters:
        ///   - certificatePath: Path to the server certificate file (PEM or DER)
        ///   - privateKeyPath: Path to the server private key file (PEM)
        ///   - privateKeyPassword: Password for encrypted private key
        ///   - minimumTLSVersion: Minimum TLS version (default: TLS 1.2)
        ///   - maximumTLSVersion: Maximum TLS version (default: nil, meaning latest)
        ///   - requireClientCertificate: Whether to require client certificates (default: false)
        ///   - clientCACertificatePath: Path to CA certificates for client verification
        ///   - clientCertificateValidation: How to validate client certificates (default: .strict)
        ///   - allowSelfSignedClientCertificates: Allow self-signed client certs (default: false)
        ///   - cipherSuites: Specific cipher suites to use (default: empty, uses system defaults)
        public init(
            certificatePath: String,
            privateKeyPath: String,
            privateKeyPassword: String? = nil,
            minimumTLSVersion: TLSVersion = .v12,
            maximumTLSVersion: TLSVersion? = nil,
            requireClientCertificate: Bool = false,
            clientCACertificatePath: String? = nil,
            clientCertificateValidation: CertificateValidationMode = .strict,
            allowSelfSignedClientCertificates: Bool = false,
            cipherSuites: [String] = []
        ) {
            self.certificatePath = certificatePath
            self.privateKeyPath = privateKeyPath
            self.privateKeyPassword = privateKeyPassword
            self.minimumTLSVersion = minimumTLSVersion
            self.maximumTLSVersion = maximumTLSVersion
            self.requireClientCertificate = requireClientCertificate
            self.clientCACertificatePath = clientCACertificatePath
            self.clientCertificateValidation = clientCertificateValidation
            self.allowSelfSignedClientCertificates = allowSelfSignedClientCertificates
            self.cipherSuites = cipherSuites
        }
        
        // MARK: - Preset Configurations
        
        /// Creates a strict TLS 1.3 only configuration
        ///
        /// Provides maximum security by requiring TLS 1.3 and strict certificate validation.
        /// Recommended for production environments with modern clients.
        ///
        /// - Parameters:
        ///   - certificatePath: Path to the server certificate
        ///   - privateKeyPath: Path to the server private key
        ///   - privateKeyPassword: Optional password for encrypted private key
        /// - Returns: A TLSConfiguration with strict settings
        public static func strict(
            certificatePath: String,
            privateKeyPath: String,
            privateKeyPassword: String? = nil
        ) -> TLSConfiguration {
            TLSConfiguration(
                certificatePath: certificatePath,
                privateKeyPath: privateKeyPath,
                privateKeyPassword: privateKeyPassword,
                minimumTLSVersion: .v13,
                maximumTLSVersion: .v13,
                clientCertificateValidation: .strict
            )
        }
        
        /// Creates a compatible TLS configuration
        ///
        /// Provides good security while maintaining compatibility with older clients.
        /// Supports TLS 1.2 and higher.
        ///
        /// - Parameters:
        ///   - certificatePath: Path to the server certificate
        ///   - privateKeyPath: Path to the server private key
        ///   - privateKeyPassword: Optional password for encrypted private key
        /// - Returns: A TLSConfiguration with compatible settings
        public static func compatible(
            certificatePath: String,
            privateKeyPath: String,
            privateKeyPassword: String? = nil
        ) -> TLSConfiguration {
            TLSConfiguration(
                certificatePath: certificatePath,
                privateKeyPath: privateKeyPath,
                privateKeyPassword: privateKeyPassword,
                minimumTLSVersion: .v12,
                maximumTLSVersion: nil,
                clientCertificateValidation: .standard
            )
        }
        
        /// Creates a development TLS configuration
        ///
        /// - Warning: This configuration is less secure and should ONLY be used
        ///   for local development and testing with self-signed certificates.
        ///   Never use in production with real patient data.
        ///
        /// - Parameters:
        ///   - certificatePath: Path to the server certificate
        ///   - privateKeyPath: Path to the server private key
        ///   - privateKeyPassword: Optional password for encrypted private key
        /// - Returns: A TLSConfiguration suitable for development
        public static func development(
            certificatePath: String,
            privateKeyPath: String,
            privateKeyPassword: String? = nil
        ) -> TLSConfiguration {
            TLSConfiguration(
                certificatePath: certificatePath,
                privateKeyPath: privateKeyPath,
                privateKeyPassword: privateKeyPassword,
                minimumTLSVersion: .v12,
                maximumTLSVersion: nil,
                requireClientCertificate: false,
                clientCertificateValidation: .permissive,
                allowSelfSignedClientCertificates: true
            )
        }
        
        /// Creates a mutual TLS (mTLS) configuration
        ///
        /// Requires client certificate authentication for all connections.
        /// Provides the highest level of authentication security.
        ///
        /// - Parameters:
        ///   - certificatePath: Path to the server certificate
        ///   - privateKeyPath: Path to the server private key
        ///   - clientCACertificatePath: Path to CA certificates for client verification
        ///   - privateKeyPassword: Optional password for encrypted private key
        /// - Returns: A TLSConfiguration requiring client certificates
        public static func mutualTLS(
            certificatePath: String,
            privateKeyPath: String,
            clientCACertificatePath: String,
            privateKeyPassword: String? = nil
        ) -> TLSConfiguration {
            TLSConfiguration(
                certificatePath: certificatePath,
                privateKeyPath: privateKeyPath,
                privateKeyPassword: privateKeyPassword,
                minimumTLSVersion: .v12,
                maximumTLSVersion: nil,
                requireClientCertificate: true,
                clientCACertificatePath: clientCACertificatePath,
                clientCertificateValidation: .strict
            )
        }
        
        // MARK: - Validation
        
        /// Validates the TLS configuration
        ///
        /// Checks that all required files exist and are accessible.
        ///
        /// - Throws: `TLSConfigurationError` if the configuration is invalid
        public func validate() throws {
            // Check certificate file exists
            guard FileManager.default.fileExists(atPath: certificatePath) else {
                throw TLSConfigurationError.certificateFileNotFound(path: certificatePath)
            }
            
            // Check private key file exists
            guard FileManager.default.fileExists(atPath: privateKeyPath) else {
                throw TLSConfigurationError.privateKeyFileNotFound(path: privateKeyPath)
            }
            
            // Check CA certificate file if mTLS is enabled
            if requireClientCertificate, let caPath = clientCACertificatePath {
                guard FileManager.default.fileExists(atPath: caPath) else {
                    throw TLSConfigurationError.caCertificateFileNotFound(path: caPath)
                }
            }
            
            // Validate TLS version range
            if let maxVersion = maximumTLSVersion {
                guard minimumTLSVersion <= maxVersion else {
                    throw TLSConfigurationError.invalidVersionRange(
                        minimum: minimumTLSVersion,
                        maximum: maxVersion
                    )
                }
            }
        }
    }
    
    /// TLS protocol version
    public enum TLSVersion: String, Sendable, Comparable, CaseIterable {
        /// TLS 1.2 (minimum recommended for DICOM)
        case v12 = "TLS 1.2"
        
        /// TLS 1.3 (most secure)
        case v13 = "TLS 1.3"
        
        // MARK: - Comparable
        
        public static func < (lhs: TLSVersion, rhs: TLSVersion) -> Bool {
            switch (lhs, rhs) {
            case (.v12, .v13):
                return true
            default:
                return false
            }
        }
    }
    
    /// Certificate validation mode for client certificates
    public enum CertificateValidationMode: String, Sendable {
        /// Strict validation - verify certificate chain and check revocation
        case strict
        
        /// Standard validation - verify certificate chain
        case standard
        
        /// Permissive validation - minimal checks (for development only)
        case permissive
        
        /// Description of the validation mode
        public var description: String {
            switch self {
            case .strict:
                return "Strict: Full certificate chain validation with revocation checking"
            case .standard:
                return "Standard: Certificate chain validation without revocation checking"
            case .permissive:
                return "Permissive: Minimal validation (DEVELOPMENT ONLY)"
            }
        }
    }
    
    /// Errors that can occur when configuring TLS
    public enum TLSConfigurationError: Error, Sendable, CustomStringConvertible {
        /// Server certificate file not found
        case certificateFileNotFound(path: String)
        
        /// Server private key file not found
        case privateKeyFileNotFound(path: String)
        
        /// CA certificate file not found
        case caCertificateFileNotFound(path: String)
        
        /// Invalid TLS version range
        case invalidVersionRange(minimum: TLSVersion, maximum: TLSVersion)
        
        /// Invalid certificate data
        case invalidCertificateData(reason: String)
        
        /// Invalid private key data
        case invalidPrivateKeyData(reason: String)
        
        /// Certificate loading failed
        case certificateLoadingFailed(reason: String)
        
        public var description: String {
            switch self {
            case .certificateFileNotFound(let path):
                return "Server certificate file not found: \(path)"
            case .privateKeyFileNotFound(let path):
                return "Server private key file not found: \(path)"
            case .caCertificateFileNotFound(let path):
                return "CA certificate file not found: \(path)"
            case .invalidVersionRange(let min, let max):
                return "Invalid TLS version range: minimum (\(min.rawValue)) is greater than maximum (\(max.rawValue))"
            case .invalidCertificateData(let reason):
                return "Invalid certificate data: \(reason)"
            case .invalidPrivateKeyData(let reason):
                return "Invalid private key data: \(reason)"
            case .certificateLoadingFailed(let reason):
                return "Failed to load certificate: \(reason)"
            }
        }
    }
}

// MARK: - Certificate Loading Helpers

extension DICOMwebServerConfiguration.TLSConfiguration {
    
    /// Loads the server certificate from the configured path
    ///
    /// - Returns: The certificate data
    /// - Throws: `TLSConfigurationError` if loading fails
    public func loadCertificateData() throws -> Data {
        guard FileManager.default.fileExists(atPath: certificatePath) else {
            throw DICOMwebServerConfiguration.TLSConfigurationError.certificateFileNotFound(path: certificatePath)
        }
        
        do {
            return try Data(contentsOf: URL(fileURLWithPath: certificatePath))
        } catch {
            throw DICOMwebServerConfiguration.TLSConfigurationError.certificateLoadingFailed(
                reason: error.localizedDescription
            )
        }
    }
    
    /// Loads the server private key from the configured path
    ///
    /// - Returns: The private key data
    /// - Throws: `TLSConfigurationError` if loading fails
    public func loadPrivateKeyData() throws -> Data {
        guard FileManager.default.fileExists(atPath: privateKeyPath) else {
            throw DICOMwebServerConfiguration.TLSConfigurationError.privateKeyFileNotFound(path: privateKeyPath)
        }
        
        do {
            return try Data(contentsOf: URL(fileURLWithPath: privateKeyPath))
        } catch {
            throw DICOMwebServerConfiguration.TLSConfigurationError.certificateLoadingFailed(
                reason: error.localizedDescription
            )
        }
    }
    
    /// Loads the CA certificate from the configured path
    ///
    /// - Returns: The CA certificate data, or nil if not configured
    /// - Throws: `TLSConfigurationError` if loading fails
    public func loadCACertificateData() throws -> Data? {
        guard let caPath = clientCACertificatePath else {
            return nil
        }
        
        guard FileManager.default.fileExists(atPath: caPath) else {
            throw DICOMwebServerConfiguration.TLSConfigurationError.caCertificateFileNotFound(path: caPath)
        }
        
        do {
            return try Data(contentsOf: URL(fileURLWithPath: caPath))
        } catch {
            throw DICOMwebServerConfiguration.TLSConfigurationError.certificateLoadingFailed(
                reason: error.localizedDescription
            )
        }
    }
    
    /// Extracts the PEM content from certificate data
    ///
    /// - Parameter data: The certificate data (may be PEM or DER)
    /// - Returns: The DER-encoded certificate data
    /// - Throws: `TLSConfigurationError` if extraction fails
    public static func extractPEMContent(_ data: Data) throws -> Data {
        // Check if it's already DER format
        if data.prefix(1) == Data([0x30]) {
            return data
        }
        
        // Try to parse as PEM
        guard let pemString = String(data: data, encoding: .utf8) else {
            throw DICOMwebServerConfiguration.TLSConfigurationError.invalidCertificateData(
                reason: "Data is neither valid PEM nor DER format"
            )
        }
        
        // Extract base64 content from PEM
        let lines = pemString.components(separatedBy: .newlines)
        var base64Content = ""
        var inBlock = false
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("-----BEGIN") {
                inBlock = true
            } else if trimmedLine.hasPrefix("-----END") {
                break
            } else if inBlock && !trimmedLine.isEmpty {
                base64Content += trimmedLine
            }
        }
        
        guard !base64Content.isEmpty,
              let derData = Data(base64Encoded: base64Content) else {
            throw DICOMwebServerConfiguration.TLSConfigurationError.invalidCertificateData(
                reason: "Failed to decode PEM content"
            )
        }
        
        return derData
    }
    
    /// Checks if the certificate file is in PEM format
    ///
    /// - Returns: true if the certificate is PEM formatted
    public var isPEMFormat: Bool {
        guard let data = try? loadCertificateData(),
              let string = String(data: data, encoding: .utf8) else {
            return false
        }
        return string.contains("-----BEGIN")
    }
}

// MARK: - CustomStringConvertible

extension DICOMwebServerConfiguration.TLSConfiguration: CustomStringConvertible {
    public var description: String {
        var parts: [String] = []
        
        // TLS version
        if let maxVersion = maximumTLSVersion {
            if minimumTLSVersion == maxVersion {
                parts.append(minimumTLSVersion.rawValue)
            } else {
                parts.append("\(minimumTLSVersion.rawValue)-\(maxVersion.rawValue)")
            }
        } else {
            parts.append("\(minimumTLSVersion.rawValue)+")
        }
        
        // Client auth
        if requireClientCertificate {
            parts.append("mTLS")
        }
        
        // Validation mode
        parts.append("(\(clientCertificateValidation.rawValue))")
        
        return parts.joined(separator: " ")
    }
}

// MARK: - CORS Configuration

extension DICOMwebServerConfiguration {
    /// CORS (Cross-Origin Resource Sharing) configuration
    public struct CORSConfiguration: Sendable {
        /// Allowed origins (use ["*"] for all)
        public let allowedOrigins: [String]
        
        /// Allowed HTTP methods
        public let allowedMethods: [String]
        
        /// Allowed headers
        public let allowedHeaders: [String]
        
        /// Headers to expose to the client
        public let exposedHeaders: [String]
        
        /// Whether to allow credentials
        public let allowCredentials: Bool
        
        /// Max age for preflight cache in seconds
        public let maxAge: Int
        
        public init(
            allowedOrigins: [String] = ["*"],
            allowedMethods: [String] = ["GET", "POST", "DELETE", "OPTIONS"],
            allowedHeaders: [String] = ["Content-Type", "Accept", "Authorization"],
            exposedHeaders: [String] = ["X-Total-Count"],
            allowCredentials: Bool = false,
            maxAge: Int = 86400
        ) {
            self.allowedOrigins = allowedOrigins
            self.allowedMethods = allowedMethods
            self.allowedHeaders = allowedHeaders
            self.exposedHeaders = exposedHeaders
            self.allowCredentials = allowCredentials
            self.maxAge = maxAge
        }
        
        /// Default CORS configuration allowing all origins
        public static let allowAll = CORSConfiguration()
        
        /// Strict CORS configuration (no cross-origin allowed)
        public static let strict = CORSConfiguration(
            allowedOrigins: [],
            allowCredentials: false
        )
    }
}

// MARK: - Rate Limit Configuration

extension DICOMwebServerConfiguration {
    /// Rate limiting configuration
    public struct RateLimitConfiguration: Sendable {
        /// Maximum requests per time window
        public let maxRequests: Int
        
        /// Time window in seconds
        public let windowSeconds: Int
        
        /// Rate limit by (IP, API key, etc.)
        public let limitBy: LimitBy
        
        public init(
            maxRequests: Int = 1000,
            windowSeconds: Int = 60,
            limitBy: LimitBy = .ipAddress
        ) {
            self.maxRequests = maxRequests
            self.windowSeconds = windowSeconds
            self.limitBy = limitBy
        }
        
        /// What to use for rate limiting identification
        public enum LimitBy: Sendable {
            case ipAddress
            case apiKey
            case combined
        }
    }
}

// MARK: - Preset Configurations

extension DICOMwebServerConfiguration {
    /// Development configuration for local testing
    ///
    /// - Warning: This configuration uses unencrypted HTTP and should ONLY be used for
    ///   local development with test data. Never use in production or with real patient data
    ///   as DICOM data may contain Protected Health Information (PHI).
    public static let development = DICOMwebServerConfiguration(
        port: 8042,
        host: "127.0.0.1",
        corsConfiguration: .allowAll
    )
    
    /// Production configuration template (requires TLS)
    public static func production(
        port: Int = 443,
        certificatePath: String,
        privateKeyPath: String
    ) -> DICOMwebServerConfiguration {
        DICOMwebServerConfiguration(
            port: port,
            host: "0.0.0.0",
            tlsConfiguration: TLSConfiguration(
                certificatePath: certificatePath,
                privateKeyPath: privateKeyPath,
                minimumTLSVersion: .v12
            ),
            rateLimitConfiguration: RateLimitConfiguration()
        )
    }
}

// MARK: - STOW-RS Configuration

extension DICOMwebServerConfiguration {
    /// Configuration for STOW-RS (Store) operations
    ///
    /// Controls how the server handles incoming DICOM instances via STOW-RS,
    /// including duplicate handling, validation, and allowed SOP Classes.
    ///
    /// Reference: PS3.18 Section 10.5 - Store Transaction (STOW-RS)
    public struct STOWConfiguration: Sendable {
        /// How to handle duplicate instances (same SOP Instance UID)
        public let duplicatePolicy: DuplicatePolicy
        
        /// Whether to validate required DICOM attributes
        public let validateRequiredAttributes: Bool
        
        /// Whether to validate SOP Class UIDs against allowed list
        public let validateSOPClasses: Bool
        
        /// Allowed SOP Class UIDs (empty means all are allowed)
        public let allowedSOPClasses: Set<String>
        
        /// Whether to validate UID format
        public let validateUIDFormat: Bool
        
        /// Additional required tags beyond the standard ones
        public let additionalRequiredTags: [UInt32]
        
        /// Creates a STOW-RS configuration
        /// - Parameters:
        ///   - duplicatePolicy: How to handle duplicates (default: .replace)
        ///   - validateRequiredAttributes: Whether to validate required attributes (default: true)
        ///   - validateSOPClasses: Whether to validate SOP Classes (default: false)
        ///   - allowedSOPClasses: Set of allowed SOP Class UIDs (default: empty, allows all)
        ///   - validateUIDFormat: Whether to validate UID format (default: true)
        ///   - additionalRequiredTags: Additional tags that must be present (default: empty)
        public init(
            duplicatePolicy: DuplicatePolicy = .replace,
            validateRequiredAttributes: Bool = true,
            validateSOPClasses: Bool = false,
            allowedSOPClasses: Set<String> = [],
            validateUIDFormat: Bool = true,
            additionalRequiredTags: [UInt32] = []
        ) {
            self.duplicatePolicy = duplicatePolicy
            self.validateRequiredAttributes = validateRequiredAttributes
            self.validateSOPClasses = validateSOPClasses
            self.allowedSOPClasses = allowedSOPClasses
            self.validateUIDFormat = validateUIDFormat
            self.additionalRequiredTags = additionalRequiredTags
        }
        
        /// Default STOW-RS configuration
        public static let `default` = STOWConfiguration()
        
        /// Strict STOW-RS configuration with full validation
        public static let strict = STOWConfiguration(
            duplicatePolicy: .reject,
            validateRequiredAttributes: true,
            validateSOPClasses: true,
            validateUIDFormat: true
        )
        
        /// Permissive STOW-RS configuration (accepts and replaces)
        public static let permissive = STOWConfiguration(
            duplicatePolicy: .accept,
            validateRequiredAttributes: false,
            validateSOPClasses: false,
            validateUIDFormat: false
        )
        
        /// Policy for handling duplicate SOP Instance UIDs
        public enum DuplicatePolicy: Sendable {
            /// Reject duplicates with 409 Conflict
            case reject
            /// Replace existing instance with new one
            case replace
            /// Accept silently (idempotent - returns success without storing)
            case accept
        }
    }
}
