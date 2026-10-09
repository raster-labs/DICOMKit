import Foundation
import DICOMCore
// NEMA-verified: 2026a, checked 2026-09-28 — carries no DICOM-standard data (facade over the services; defaults only)

#if canImport(Network)

// MARK: - DICOMClient Configuration

/// Configuration for a DICOM Client
///
/// Contains all the parameters needed to connect to a remote DICOM service.
///
/// ## Usage
///
/// ```swift
/// let config = DICOMClientConfiguration(
///     host: "pacs.hospital.com",
///     port: 11112,
///     callingAE: "MY_SCU",
///     calledAE: "PACS"
/// )
///
/// let client = DICOMClient(configuration: config)
/// ```
public struct DICOMClientConfiguration: Sendable, Hashable {
    /// The remote host address (IP or hostname)
    public let host: String
    
    /// The remote port number
    public let port: UInt16
    
    /// The local Application Entity title (calling AE)
    public let callingAETitle: AETitle
    
    /// The remote Application Entity title (called AE)
    public let calledAETitle: AETitle
    
    /// Connection timeout in seconds
    public let timeout: TimeInterval
    
    /// Granular timeout configuration for different operation phases
    ///
    /// Provides fine-grained control over timeouts for different phases of
    /// DICOM network operations. If not explicitly set, defaults to using the
    /// legacy `timeout` value for all timeout types.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // Use default timeout configuration
    /// let config = try DICOMClientConfiguration(
    ///     host: "pacs.hospital.com",
    ///     port: 11112,
    ///     callingAE: "MY_SCU",
    ///     calledAE: "PACS",
    ///     timeoutConfiguration: .default
    /// )
    ///
    /// // Use fast timeouts for local network
    /// let fastConfig = try DICOMClientConfiguration(
    ///     host: "localhost",
    ///     port: 11112,
    ///     callingAE: "MY_SCU",
    ///     calledAE: "PACS",
    ///     timeoutConfiguration: .fast
    /// )
    ///
    /// // Use slow timeouts for WAN connections
    /// let slowConfig = try DICOMClientConfiguration(
    ///     host: "remote-pacs.example.com",
    ///     port: 11112,
    ///     callingAE: "MY_SCU",
    ///     calledAE: "PACS",
    ///     timeoutConfiguration: .slow
    /// )
    ///
    /// // Custom timeout configuration
    /// let customConfig = try DICOMClientConfiguration(
    ///     host: "pacs.hospital.com",
    ///     port: 11112,
    ///     callingAE: "MY_SCU",
    ///     calledAE: "PACS",
    ///     timeoutConfiguration: TimeoutConfiguration(
    ///         connect: 15,
    ///         read: 60,
    ///         write: 30,
    ///         operation: 300,
    ///         association: 45
    ///     )
    /// )
    /// ```
    public var timeoutConfiguration: TimeoutConfiguration {
        // Use the legacy timeout value for backward compatibility
        // Each timeout type defaults to the single timeout value
        return TimeoutConfiguration(
            connect: timeout,
            read: timeout,
            write: timeout,
            operation: timeout * 4, // Operations typically need more time
            association: timeout
        )
    }
    
    /// Maximum PDU size to propose
    public let maxPDUSize: UInt32
    
    /// Implementation Class UID
    public let implementationClassUID: String
    
    /// Implementation Version Name (optional)
    public let implementationVersionName: String?
    
    /// Whether to use TLS encryption
    ///
    /// - Note: For more advanced TLS configuration, use `tlsConfiguration` property instead.
    public var tlsEnabled: Bool {
        return tlsConfiguration != nil
    }
    
    /// TLS configuration for secure connections
    ///
    /// When set, enables TLS with the specified configuration. When nil, plain TCP is used.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // Use default secure TLS
    /// let config = try DICOMClientConfiguration(
    ///     host: "secure-pacs.hospital.com",
    ///     port: 2762,
    ///     callingAE: "MY_SCU",
    ///     calledAE: "PACS",
    ///     tlsConfiguration: .default
    /// )
    ///
    /// // Use insecure TLS for development (self-signed certificates)
    /// let devConfig = try DICOMClientConfiguration(
    ///     host: "dev-pacs.local",
    ///     port: 2762,
    ///     callingAE: "MY_SCU",
    ///     calledAE: "PACS",
    ///     tlsConfiguration: .insecure
    /// )
    ///
    /// // Custom TLS with certificate pinning
    /// let pinnedConfig = try DICOMClientConfiguration(
    ///     host: "pacs.hospital.com",
    ///     port: 2762,
    ///     callingAE: "MY_SCU",
    ///     calledAE: "PACS",
    ///     tlsConfiguration: TLSConfiguration(
    ///         minimumVersion: .tlsProtocol13,
    ///         certificateValidation: .pinned([myCertificate])
    ///     )
    /// )
    /// ```
    public let tlsConfiguration: TLSConfiguration?
    
    /// Retry policy for network operations
    public let retryPolicy: RetryPolicy
    
    /// Circuit breaker configuration for failing server protection
    ///
    /// When set, enables the circuit breaker pattern to prevent cascading failures
    /// when a server is consistently failing. When nil, circuit breaker is disabled.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // Enable circuit breaker with default settings
    /// let config = try DICOMClientConfiguration(
    ///     host: "pacs.hospital.com",
    ///     port: 11112,
    ///     callingAE: "MY_SCU",
    ///     calledAE: "PACS",
    ///     circuitBreakerConfiguration: .default
    /// )
    ///
    /// // Enable with custom settings
    /// let customConfig = try DICOMClientConfiguration(
    ///     host: "pacs.hospital.com",
    ///     port: 11112,
    ///     callingAE: "MY_SCU",
    ///     calledAE: "PACS",
    ///     circuitBreakerConfiguration: CircuitBreakerConfiguration(
    ///         failureThreshold: 3,
    ///         successThreshold: 1,
    ///         resetTimeout: 15
    ///     )
    /// )
    /// ```
    public let circuitBreakerConfiguration: CircuitBreakerConfiguration?
    
    /// Whether circuit breaker is enabled
    public var circuitBreakerEnabled: Bool {
        return circuitBreakerConfiguration != nil
    }
    
    /// User identity for authentication (optional)
    ///
    /// When set, user identity information will be included in the A-ASSOCIATE-RQ PDU
    /// for authentication with the remote SCP.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // Username only authentication
    /// let config = try DICOMClientConfiguration(
    ///     host: "pacs.hospital.com",
    ///     port: 11112,
    ///     callingAE: "MY_SCU",
    ///     calledAE: "PACS",
    ///     userIdentity: .username("john.doe")
    /// )
    ///
    /// // Username and password authentication
    /// let authConfig = try DICOMClientConfiguration(
    ///     host: "pacs.hospital.com",
    ///     port: 11112,
    ///     callingAE: "MY_SCU",
    ///     calledAE: "PACS",
    ///     userIdentity: .usernameAndPasscode(
    ///         username: "john.doe",
    ///         passcode: "secretPassword",
    ///         positiveResponseRequested: true
    ///     )
    /// )
    ///
    /// // JWT authentication
    /// let jwtConfig = try DICOMClientConfiguration(
    ///     host: "pacs.hospital.com",
    ///     port: 11112,
    ///     callingAE: "MY_SCU",
    ///     calledAE: "PACS",
    ///     userIdentity: .jwt(token: "eyJhbGciOiJIUzI1NiIs...")
    /// )
    /// ```
    ///
    /// Reference: PS3.7 Section D.3.3.7 - User Identity Negotiation
    public let userIdentity: UserIdentity?
    
    /// Default Implementation Class UID for DICOMKit
    public static let defaultImplementationClassUID = DICOMNetworkImplementation.classUID
    
    /// Default Implementation Version Name for DICOMKit
    public static let defaultImplementationVersionName = "DICOMKIT_001"
    
    /// Creates a DICOM client configuration
    ///
    /// - Parameters:
    ///   - host: The remote host address (IP or hostname)
    ///   - port: The remote port number (default: 104)
    ///   - callingAE: The local AE title string
    ///   - calledAE: The remote AE title string
    ///   - timeout: Connection timeout in seconds (default: 30)
    ///   - maxPDUSize: Maximum PDU size (default: 64 KB, `defaultMaxPDUSize`)
    ///   - implementationClassUID: Implementation Class UID
    ///   - implementationVersionName: Implementation Version Name
    ///   - tlsEnabled: Use TLS encryption with default configuration (default: false)
    ///   - retryPolicy: Retry policy for operations (default: no retries)
    ///   - circuitBreakerConfiguration: Circuit breaker configuration (nil to disable)
    ///   - userIdentity: User identity for authentication (optional)
    /// - Throws: `DICOMNetworkError.invalidAETitle` if AE titles are invalid
    public init(
        host: String,
        port: UInt16 = dicomDefaultPort,
        callingAE: String,
        calledAE: String,
        timeout: TimeInterval = 30,
        maxPDUSize: UInt32 = defaultMaxPDUSize,
        implementationClassUID: String = defaultImplementationClassUID,
        implementationVersionName: String? = defaultImplementationVersionName,
        tlsEnabled: Bool = false,
        retryPolicy: RetryPolicy = .noRetry,
        circuitBreakerConfiguration: CircuitBreakerConfiguration? = nil,
        userIdentity: UserIdentity? = nil
    ) throws {
        self.host = host
        self.port = port
        self.callingAETitle = try AETitle(callingAE)
        self.calledAETitle = try AETitle(calledAE)
        self.timeout = timeout
        self.maxPDUSize = maxPDUSize
        self.implementationClassUID = implementationClassUID
        self.implementationVersionName = implementationVersionName
        self.tlsConfiguration = tlsEnabled ? .default : nil
        self.retryPolicy = retryPolicy
        self.circuitBreakerConfiguration = circuitBreakerConfiguration
        self.userIdentity = userIdentity
    }
    
    /// Creates a DICOM client configuration with TLS configuration
    ///
    /// - Parameters:
    ///   - host: The remote host address (IP or hostname)
    ///   - port: The remote port number (default: 104)
    ///   - callingAE: The local AE title string
    ///   - calledAE: The remote AE title string
    ///   - timeout: Connection timeout in seconds (default: 30)
    ///   - maxPDUSize: Maximum PDU size (default: 64 KB, `defaultMaxPDUSize`)
    ///   - implementationClassUID: Implementation Class UID
    ///   - implementationVersionName: Implementation Version Name
    ///   - tlsConfiguration: TLS configuration for secure connections (nil for plain TCP)
    ///   - retryPolicy: Retry policy for operations (default: no retries)
    ///   - circuitBreakerConfiguration: Circuit breaker configuration (nil to disable)
    ///   - userIdentity: User identity for authentication (optional)
    /// - Throws: `DICOMNetworkError.invalidAETitle` if AE titles are invalid
    public init(
        host: String,
        port: UInt16 = dicomDefaultPort,
        callingAE: String,
        calledAE: String,
        timeout: TimeInterval = 30,
        maxPDUSize: UInt32 = defaultMaxPDUSize,
        implementationClassUID: String = defaultImplementationClassUID,
        implementationVersionName: String? = defaultImplementationVersionName,
        tlsConfiguration: TLSConfiguration?,
        retryPolicy: RetryPolicy = .noRetry,
        circuitBreakerConfiguration: CircuitBreakerConfiguration? = nil,
        userIdentity: UserIdentity? = nil
    ) throws {
        self.host = host
        self.port = port
        self.callingAETitle = try AETitle(callingAE)
        self.calledAETitle = try AETitle(calledAE)
        self.timeout = timeout
        self.maxPDUSize = maxPDUSize
        self.implementationClassUID = implementationClassUID
        self.implementationVersionName = implementationVersionName
        self.tlsConfiguration = tlsConfiguration
        self.retryPolicy = retryPolicy
        self.circuitBreakerConfiguration = circuitBreakerConfiguration
        self.userIdentity = userIdentity
    }
    
    /// Creates a DICOM client configuration with pre-validated AE titles
    ///
    /// - Parameters:
    ///   - host: The remote host address (IP or hostname)
    ///   - port: The remote port number (default: 104)
    ///   - callingAETitle: The local AE title
    ///   - calledAETitle: The remote AE title
    ///   - timeout: Connection timeout in seconds (default: 30)
    ///   - maxPDUSize: Maximum PDU size (default: 64 KB, `defaultMaxPDUSize`)
    ///   - implementationClassUID: Implementation Class UID
    ///   - implementationVersionName: Implementation Version Name
    ///   - tlsEnabled: Use TLS encryption with default configuration (default: false)
    ///   - retryPolicy: Retry policy for operations (default: no retries)
    ///   - circuitBreakerConfiguration: Circuit breaker configuration (nil to disable)
    ///   - userIdentity: User identity for authentication (optional)
    public init(
        host: String,
        port: UInt16 = dicomDefaultPort,
        callingAETitle: AETitle,
        calledAETitle: AETitle,
        timeout: TimeInterval = 30,
        maxPDUSize: UInt32 = defaultMaxPDUSize,
        implementationClassUID: String = defaultImplementationClassUID,
        implementationVersionName: String? = defaultImplementationVersionName,
        tlsEnabled: Bool = false,
        retryPolicy: RetryPolicy = .noRetry,
        circuitBreakerConfiguration: CircuitBreakerConfiguration? = nil,
        userIdentity: UserIdentity? = nil
    ) {
        self.host = host
        self.port = port
        self.callingAETitle = callingAETitle
        self.calledAETitle = calledAETitle
        self.timeout = timeout
        self.maxPDUSize = maxPDUSize
        self.implementationClassUID = implementationClassUID
        self.implementationVersionName = implementationVersionName
        self.tlsConfiguration = tlsEnabled ? .default : nil
        self.retryPolicy = retryPolicy
        self.circuitBreakerConfiguration = circuitBreakerConfiguration
        self.userIdentity = userIdentity
    }
    
    /// Creates a DICOM client configuration with pre-validated AE titles and TLS configuration
    ///
    /// - Parameters:
    ///   - host: The remote host address (IP or hostname)
    ///   - port: The remote port number (default: 104)
    ///   - callingAETitle: The local AE title
    ///   - calledAETitle: The remote AE title
    ///   - timeout: Connection timeout in seconds (default: 30)
    ///   - maxPDUSize: Maximum PDU size (default: 64 KB, `defaultMaxPDUSize`)
    ///   - implementationClassUID: Implementation Class UID
    ///   - implementationVersionName: Implementation Version Name
    ///   - tlsConfiguration: TLS configuration for secure connections (nil for plain TCP)
    ///   - retryPolicy: Retry policy for operations (default: no retries)
    ///   - circuitBreakerConfiguration: Circuit breaker configuration (nil to disable)
    ///   - userIdentity: User identity for authentication (optional)
    public init(
        host: String,
        port: UInt16 = dicomDefaultPort,
        callingAETitle: AETitle,
        calledAETitle: AETitle,
        timeout: TimeInterval = 30,
        maxPDUSize: UInt32 = defaultMaxPDUSize,
        implementationClassUID: String = defaultImplementationClassUID,
        implementationVersionName: String? = defaultImplementationVersionName,
        tlsConfiguration: TLSConfiguration?,
        retryPolicy: RetryPolicy = .noRetry,
        circuitBreakerConfiguration: CircuitBreakerConfiguration? = nil,
        userIdentity: UserIdentity? = nil
    ) {
        self.host = host
        self.port = port
        self.callingAETitle = callingAETitle
        self.calledAETitle = calledAETitle
        self.timeout = timeout
        self.maxPDUSize = maxPDUSize
        self.implementationClassUID = implementationClassUID
        self.implementationVersionName = implementationVersionName
        self.tlsConfiguration = tlsConfiguration
        self.retryPolicy = retryPolicy
        self.circuitBreakerConfiguration = circuitBreakerConfiguration
        self.userIdentity = userIdentity
    }
}

// MARK: - Operation Configuration Projection

extension DICOMClientConfiguration {
    /// Full configuration consumed by connection pools.
    func pooledAssociationConfiguration(artimTimeout: TimeInterval? = 30) -> AssociationConfiguration {
        AssociationConfiguration(
            callingAETitle: callingAETitle,
            calledAETitle: calledAETitle,
            host: host,
            port: port,
            maxPDUSize: maxPDUSize,
            implementationClassUID: implementationClassUID,
            implementationVersionName: implementationVersionName,
            timeout: timeout,
            artimTimeout: artimTimeout,
            tlsConfiguration: tlsConfiguration,
            userIdentity: userIdentity
        )
    }

    /// Full configuration consumed by association-only and C-ECHO operations.
    var verificationServiceConfiguration: VerificationConfiguration {
        VerificationConfiguration(
            callingAETitle: callingAETitle,
            calledAETitle: calledAETitle,
            timeout: timeout,
            maxPDUSize: maxPDUSize,
            implementationClassUID: implementationClassUID,
            implementationVersionName: implementationVersionName,
            tlsConfiguration: tlsConfiguration,
            userIdentity: userIdentity
        )
    }

    /// Full configuration consumed by C-FIND operations.
    var queryServiceConfiguration: QueryConfiguration {
        QueryConfiguration(
            callingAETitle: callingAETitle,
            calledAETitle: calledAETitle,
            timeout: timeout,
            maxPDUSize: maxPDUSize,
            implementationClassUID: implementationClassUID,
            implementationVersionName: implementationVersionName,
            tlsConfiguration: tlsConfiguration,
            userIdentity: userIdentity
        )
    }

    /// Full configuration consumed by C-GET and C-MOVE operations.
    var retrieveServiceConfiguration: RetrieveConfiguration {
        RetrieveConfiguration(
            callingAETitle: callingAETitle,
            calledAETitle: calledAETitle,
            timeout: timeout,
            maxPDUSize: maxPDUSize,
            implementationClassUID: implementationClassUID,
            implementationVersionName: implementationVersionName,
            tlsConfiguration: tlsConfiguration,
            userIdentity: userIdentity
        )
    }

    /// Full configuration consumed by C-STORE operations.
    func storageServiceConfiguration(priority: DIMSEPriority) -> StorageConfiguration {
        StorageConfiguration(
            callingAETitle: callingAETitle,
            calledAETitle: calledAETitle,
            timeout: timeout,
            maxPDUSize: maxPDUSize,
            implementationClassUID: implementationClassUID,
            implementationVersionName: implementationVersionName,
            priority: priority,
            tlsConfiguration: tlsConfiguration,
            userIdentity: userIdentity
        )
    }
}

// MARK: - DICOMClient

/// Unified high-level DICOM client for network operations
///
/// Provides a convenient interface for DICOM networking including verification (C-ECHO),
/// query (C-FIND), and retrieve (C-MOVE, C-GET) operations.
///
/// Reference: PS3.7 - Message Exchange
/// Reference: PS3.8 - Network Communication Support
///
/// ## Usage
///
/// ```swift
/// // Create a client
/// let config = try DICOMClientConfiguration(
///     host: "pacs.hospital.com",
///     port: 11112,
///     callingAE: "MY_SCU",
///     calledAE: "PACS"
/// )
/// let client = DICOMClient(configuration: config)
///
/// // Test connectivity
/// let success = try await client.verify()
///
/// // Query for studies
/// let studies = try await client.findStudies(
///     matching: QueryKeys(level: .study)
///         .patientName("DOE^JOHN*")
///         .studyDate("20240101-20241231")
/// )
///
/// // Download a study using C-GET
/// for await event in try await client.getStudy(studyInstanceUID: studies[0].studyInstanceUID!) {
///     switch event {
///     case .instance(_, _, let data):
///         print("Received \(data.count) bytes")
///     case .completed(let result):
///         print("Download complete: \(result.progress.completed) instances")
///     default:
///         break
///     }
/// }
/// ```
public final class DICOMClient: Sendable {
    
    /// The client configuration
    public let configuration: DICOMClientConfiguration
    
    /// Circuit breaker for this client (nil if disabled)
    private let circuitBreaker: CircuitBreaker?
    
    /// Creates a new DICOM client
    ///
    /// - Parameter configuration: The client configuration
    public init(configuration: DICOMClientConfiguration) {
        self.configuration = configuration
        
        // Create circuit breaker if configured
        if let cbConfig = configuration.circuitBreakerConfiguration {
            self.circuitBreaker = CircuitBreaker(
                host: configuration.host,
                port: configuration.port,
                configuration: cbConfig
            )
        } else {
            self.circuitBreaker = nil
        }
    }
    
    // MARK: - Convenience Initializer
    
    /// Creates a new DICOM client with the specified parameters
    ///
    /// - Parameters:
    ///   - host: The remote host address
    ///   - port: The remote port number (default: 104)
    ///   - callingAE: The local AE title
    ///   - calledAE: The remote AE title
    ///   - timeout: Connection timeout (default: 30 seconds)
    ///   - retryPolicy: Retry policy (default: no retries)
    ///   - circuitBreakerConfiguration: Circuit breaker configuration (nil to disable)
    /// - Throws: `DICOMNetworkError.invalidAETitle` if AE titles are invalid
    public convenience init(
        host: String,
        port: UInt16 = dicomDefaultPort,
        callingAE: String,
        calledAE: String,
        timeout: TimeInterval = 30,
        retryPolicy: RetryPolicy = .noRetry,
        circuitBreakerConfiguration: CircuitBreakerConfiguration? = nil
    ) throws {
        let config = try DICOMClientConfiguration(
            host: host,
            port: port,
            callingAE: callingAE,
            calledAE: calledAE,
            timeout: timeout,
            retryPolicy: retryPolicy,
            circuitBreakerConfiguration: circuitBreakerConfiguration
        )
        self.init(configuration: config)
    }
    
    // MARK: - Verification (C-ECHO)

    /// Diagnoses transport and association negotiation without sending C-ECHO.
    ///
    /// A successful result is intentionally limited to TCP/TLS and A-ASSOCIATE
    /// negotiation. Use `echo()` when DIMSE verification is also required.
    public func diagnoseAssociation() async throws -> AssociationDiagnosticResult {
        try await withRetry {
            try await DICOMVerificationService.diagnoseAssociation(
                host: self.configuration.host,
                port: self.configuration.port,
                configuration: self.configuration.verificationServiceConfiguration
            )
        }
    }
    
    /// Tests connectivity with the remote DICOM service using C-ECHO
    ///
    /// - Returns: `true` if verification succeeded, `false` otherwise
    /// - Throws: `DICOMNetworkError` for connection or protocol errors
    public func verify() async throws -> Bool {
        try await withRetry {
            try await DICOMVerificationService.echo(
                host: self.configuration.host,
                port: self.configuration.port,
                configuration: self.configuration.verificationServiceConfiguration
            ).success
        }
    }
    
    /// Performs a C-ECHO operation and returns detailed results
    ///
    /// - Returns: A `VerificationResult` with detailed information
    /// - Throws: `DICOMNetworkError` for connection or protocol errors
    public func echo() async throws -> VerificationResult {
        try await withRetry {
            try await DICOMVerificationService.echo(
                host: self.configuration.host,
                port: self.configuration.port,
                configuration: self.configuration.verificationServiceConfiguration
            )
        }
    }
    
    // MARK: - Query (C-FIND)
    
    /// Finds studies matching the specified query keys
    ///
    /// - Parameter matching: Query keys specifying match criteria (optional)
    /// - Returns: Array of study results
    /// - Throws: `DICOMNetworkError` for connection or protocol errors
    public func findStudies(matching: QueryKeys? = nil) async throws -> [StudyResult] {
        try await withRetry {
            try await DICOMQueryService.findStudies(
                host: self.configuration.host,
                port: self.configuration.port,
                configuration: self.configuration.queryServiceConfiguration,
                matching: matching
            )
        }
    }
    
    /// Finds series within a study matching the specified query keys
    ///
    /// - Parameters:
    ///   - studyInstanceUID: The Study Instance UID
    ///   - matching: Additional query keys (optional)
    /// - Returns: Array of series results
    /// - Throws: `DICOMNetworkError` for connection or protocol errors
    public func findSeries(
        forStudy studyInstanceUID: String,
        matching: QueryKeys? = nil
    ) async throws -> [SeriesResult] {
        try await withRetry {
            try await DICOMQueryService.findSeries(
                host: self.configuration.host,
                port: self.configuration.port,
                configuration: self.configuration.queryServiceConfiguration,
                forStudy: studyInstanceUID,
                matching: matching
            )
        }
    }
    
    /// Finds instances within a series matching the specified query keys
    ///
    /// - Parameters:
    ///   - studyInstanceUID: The Study Instance UID
    ///   - seriesInstanceUID: The Series Instance UID
    ///   - matching: Additional query keys (optional)
    /// - Returns: Array of instance results
    /// - Throws: `DICOMNetworkError` for connection or protocol errors
    public func findInstances(
        forStudy studyInstanceUID: String,
        forSeries seriesInstanceUID: String,
        matching: QueryKeys? = nil
    ) async throws -> [InstanceResult] {
        try await withRetry {
            try await DICOMQueryService.findInstances(
                host: self.configuration.host,
                port: self.configuration.port,
                configuration: self.configuration.queryServiceConfiguration,
                forStudy: studyInstanceUID,
                forSeries: seriesInstanceUID,
                matching: matching
            )
        }
    }
    
    // MARK: - Retrieve (C-MOVE)
    
    /// Moves a study to a destination AE using C-MOVE
    ///
    /// - Parameters:
    ///   - studyInstanceUID: The Study Instance UID
    ///   - moveDestination: The destination AE title
    ///   - onProgress: Optional progress callback
    /// - Returns: The retrieve result
    /// - Throws: `DICOMNetworkError` for connection or protocol errors
    public func moveStudy(
        studyInstanceUID: String,
        moveDestination: String,
        onProgress: (@Sendable (RetrieveProgress) -> Void)? = nil
    ) async throws -> RetrieveResult {
        try await withRetry {
            try await DICOMRetrieveService.move(
                host: self.configuration.host,
                port: self.configuration.port,
                configuration: self.configuration.retrieveServiceConfiguration,
                keys: .forStudy(studyInstanceUID),
                moveDestination: moveDestination,
                onProgress: onProgress
            )
        }
    }
    
    /// Moves a series to a destination AE using C-MOVE
    ///
    /// - Parameters:
    ///   - studyInstanceUID: The Study Instance UID
    ///   - seriesInstanceUID: The Series Instance UID
    ///   - moveDestination: The destination AE title
    ///   - onProgress: Optional progress callback
    /// - Returns: The retrieve result
    /// - Throws: `DICOMNetworkError` for connection or protocol errors
    public func moveSeries(
        studyInstanceUID: String,
        seriesInstanceUID: String,
        moveDestination: String,
        onProgress: (@Sendable (RetrieveProgress) -> Void)? = nil
    ) async throws -> RetrieveResult {
        try await withRetry {
            try await DICOMRetrieveService.move(
                host: self.configuration.host,
                port: self.configuration.port,
                configuration: self.configuration.retrieveServiceConfiguration,
                keys: .forSeries(studyUID: studyInstanceUID, seriesUID: seriesInstanceUID),
                moveDestination: moveDestination,
                onProgress: onProgress
            )
        }
    }
    
    /// Moves an instance to a destination AE using C-MOVE
    ///
    /// - Parameters:
    ///   - studyInstanceUID: The Study Instance UID
    ///   - seriesInstanceUID: The Series Instance UID
    ///   - sopInstanceUID: The SOP Instance UID
    ///   - moveDestination: The destination AE title
    ///   - onProgress: Optional progress callback
    /// - Returns: The retrieve result
    /// - Throws: `DICOMNetworkError` for connection or protocol errors
    public func moveInstance(
        studyInstanceUID: String,
        seriesInstanceUID: String,
        sopInstanceUID: String,
        moveDestination: String,
        onProgress: (@Sendable (RetrieveProgress) -> Void)? = nil
    ) async throws -> RetrieveResult {
        try await withRetry {
            try await DICOMRetrieveService.move(
                host: self.configuration.host,
                port: self.configuration.port,
                configuration: self.configuration.retrieveServiceConfiguration,
                keys: .forInstance(
                    studyUID: studyInstanceUID,
                    seriesUID: seriesInstanceUID,
                    instanceUID: sopInstanceUID
                ),
                moveDestination: moveDestination,
                onProgress: onProgress
            )
        }
    }
    
    // MARK: - Download (C-GET)
    
    /// Downloads a study using C-GET
    ///
    /// C-GET retrieves images directly on the same association without
    /// needing a separate Storage SCP.
    ///
    /// - Parameter studyInstanceUID: The Study Instance UID
    /// - Returns: An async stream of retrieve events
    /// - Throws: `DICOMNetworkError` for connection or protocol errors
    public func getStudy(
        studyInstanceUID: String
    ) async throws -> AsyncStream<DICOMRetrieveService.GetEvent> {
        // Note: C-GET operations are not retried since they return a stream
        // Individual failures are reported through the stream
        DICOMRetrieveService.get(
            host: configuration.host,
            port: configuration.port,
            configuration: configuration.retrieveServiceConfiguration,
            keys: .forStudy(studyInstanceUID)
        )
    }
    
    /// Downloads a series using C-GET
    ///
    /// - Parameters:
    ///   - studyInstanceUID: The Study Instance UID
    ///   - seriesInstanceUID: The Series Instance UID
    /// - Returns: An async stream of retrieve events
    /// - Throws: `DICOMNetworkError` for connection or protocol errors
    public func getSeries(
        studyInstanceUID: String,
        seriesInstanceUID: String
    ) async throws -> AsyncStream<DICOMRetrieveService.GetEvent> {
        DICOMRetrieveService.get(
            host: configuration.host,
            port: configuration.port,
            configuration: configuration.retrieveServiceConfiguration,
            keys: .forSeries(studyUID: studyInstanceUID, seriesUID: seriesInstanceUID)
        )
    }
    
    /// Downloads an instance using C-GET
    ///
    /// - Parameters:
    ///   - studyInstanceUID: The Study Instance UID
    ///   - seriesInstanceUID: The Series Instance UID
    ///   - sopInstanceUID: The SOP Instance UID
    /// - Returns: An async stream of retrieve events
    /// - Throws: `DICOMNetworkError` for connection or protocol errors
    public func getInstance(
        studyInstanceUID: String,
        seriesInstanceUID: String,
        sopInstanceUID: String
    ) async throws -> AsyncStream<DICOMRetrieveService.GetEvent> {
        DICOMRetrieveService.get(
            host: configuration.host,
            port: configuration.port,
            configuration: configuration.retrieveServiceConfiguration,
            keys: .forInstance(
                studyUID: studyInstanceUID,
                seriesUID: seriesInstanceUID,
                instanceUID: sopInstanceUID
            )
        )
    }
    
    // MARK: - Storage (C-STORE)
    
    /// Stores a DICOM file to the remote SCP
    ///
    /// Extracts the SOP Class UID and SOP Instance UID from the file's data set
    /// and sends it to the configured destination.
    ///
    /// - Parameters:
    ///   - fileData: The complete DICOM file data (including file meta information)
    ///   - priority: Operation priority (default: medium)
    /// - Returns: A `StoreResult` with detailed information
    /// - Throws: `DICOMNetworkError` for connection or protocol errors
    /// - Throws: `DICOMError` if the file cannot be parsed or is missing required attributes
    public func store(
        fileData: Data,
        priority: DIMSEPriority = .medium
    ) async throws -> StoreResult {
        try await withRetry {
            try await DICOMStorageService.store(
                fileData: fileData,
                to: self.configuration.host,
                port: self.configuration.port,
                configuration: self.configuration.storageServiceConfiguration(priority: priority)
            )
        }
    }
    
    /// Stores a DICOM data set to the remote SCP
    ///
    /// - Parameters:
    ///   - dataSetData: The DICOM data set (without file meta information preamble)
    ///   - sopClassUID: The SOP Class UID
    ///   - sopInstanceUID: The SOP Instance UID
    ///   - transferSyntaxUID: The transfer syntax of the data (default: Explicit VR Little Endian)
    ///   - priority: Operation priority (default: medium)
    /// - Returns: A `StoreResult` with detailed information
    /// - Throws: `DICOMNetworkError` for connection or protocol errors
    public func store(
        dataSetData: Data,
        sopClassUID: String,
        sopInstanceUID: String,
        transferSyntaxUID: String = explicitVRLittleEndianTransferSyntaxUID,
        priority: DIMSEPriority = .medium
    ) async throws -> StoreResult {
        try await withRetry {
            try await DICOMStorageService.store(
                dataSetData: dataSetData,
                sopClassUID: sopClassUID,
                sopInstanceUID: sopInstanceUID,
                transferSyntaxUID: transferSyntaxUID,
                to: self.configuration.host,
                port: self.configuration.port,
                configuration: self.configuration.storageServiceConfiguration(priority: priority)
            )
        }
    }
    
    /// Stores multiple DICOM files to the remote SCP in a batch
    ///
    /// Returns an async stream that emits progress events as files are stored.
    /// Files are sent over a single association for efficiency.
    ///
    /// - Parameters:
    ///   - files: Array of DICOM file data to store
    ///   - priority: Operation priority (default: medium)
    ///   - configuration: Batch configuration options (default: continue on error)
    /// - Returns: An async stream of `StorageProgressEvent` values
    /// - Throws: `DICOMNetworkError` for connection errors during setup
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let files = [fileData1, fileData2, fileData3]
    /// let stream = try await client.storeBatch(files: files)
    ///
    /// for try await event in stream {
    ///     switch event {
    ///     case .progress(let progress):
    ///         print("Progress: \(progress.succeeded)/\(progress.total)")
    ///     case .fileResult(let result):
    ///         print("File \(result.index): \(result.success ? "OK" : "FAILED")")
    ///     case .completed(let result):
    ///         print("Completed: \(result.progress.succeeded) succeeded")
    ///     case .error(let error):
    ///         print("Error: \(error)")
    ///     }
    /// }
    /// ```
    public func storeBatch(
        files: [Data],
        priority: DIMSEPriority = .medium,
        configuration batchConfig: BatchStorageConfiguration = .default
    ) async throws -> AsyncThrowingStream<StorageProgressEvent, Error> {
        // Note: Batch operations are not retried since they return a stream
        // Individual file failures are reported through the stream
        DICOMStorageService.storeBatch(
            files: files,
            to: self.configuration.host,
            port: self.configuration.port,
            storageConfiguration: self.configuration.storageServiceConfiguration(priority: priority),
            configuration: batchConfig
        )
    }
    
    // MARK: - Retry Logic
    
    /// Executes an operation with retry logic and circuit breaker protection
    ///
    /// - Parameter operation: The operation to execute
    /// - Returns: The result of the operation
    /// - Throws: The last error if all retries fail, or `circuitBreakerOpen` if circuit is open
    private func withRetry<T>(_ operation: @Sendable () async throws -> T) async throws -> T {
        // Check circuit breaker first
        if let breaker = circuitBreaker {
            do {
                try await breaker.checkState()
            } catch let error as CircuitBreakerOpenError {
                throw DICOMNetworkError.circuitBreakerOpen(
                    host: error.host,
                    port: error.port,
                    retryAfter: error.retryAfter
                )
            }
        }
        
        let policy = configuration.retryPolicy
        
        var lastError: Error?
        
        for attempt in 0...policy.maxAttempts {
            do {
                // Wait before retry (no wait on first attempt)
                if attempt > 0 {
                    let delay = policy.delay(forAttempt: attempt)
                    if delay > 0 {
                        try await Task.sleep(for: .seconds(delay))
                    }
                }
                
                let result = try await operation()
                
                // Record success to circuit breaker
                if let breaker = circuitBreaker {
                    await breaker.recordSuccess()
                }
                
                return result
            } catch {
                lastError = error
                
                // Record failure to circuit breaker
                if let breaker = circuitBreaker, shouldRecordFailure(error: error) {
                    await breaker.recordFailure()
                }
                
                // Check if we should retry
                if !shouldRetry(error: error) {
                    throw error
                }
                
                // If this was the last attempt, throw the error
                if attempt == policy.maxAttempts {
                    throw error
                }
            }
        }
        
        // Should never reach here, but just in case
        throw lastError ?? DICOMNetworkError.connectionFailed("Unknown error")
    }
    
    /// Determines if an error should be recorded as a failure in the circuit breaker
    ///
    /// - Parameter error: The error to check
    /// - Returns: `true` if the error should be counted as a failure
    private func shouldRecordFailure(error: Error) -> Bool {
        guard let networkError = error as? DICOMNetworkError else {
            // Unknown errors are considered failures
            return true
        }
        
        switch networkError {
        case .connectionFailed, .timeout, .connectionClosed, .artimTimerExpired:
            // Connection-level failures should trip the circuit
            return true
        case .operationTimeout:
            // Operation timeouts are connection-level failures
            return true
        case .associationRejected(let result, _, _):
            // Only transient rejections are considered server failures
            return result == .rejectedTransient
        case .invalidAETitle, .invalidState, .noPresentationContextAccepted,
             .sopClassNotSupported, .unexpectedPDUType, .invalidPDU,
             .encodingFailed, .decodingFailed, .limitExceeded, .pduTooLarge,
             .associationAborted, .queryFailed, .retrieveFailed,
             .circuitBreakerOpen, .storeFailed, .partialFailure,
             .printOperationFailed, .mppsOperationFailed, .unexpectedResponse:
            // Client-side or protocol errors shouldn't affect circuit breaker
            return false
        }
    }
    
    /// Determines if an error should trigger a retry
    ///
    /// - Parameter error: The error to check
    /// - Returns: `true` if the operation should be retried
    private func shouldRetry(error: Error) -> Bool {
        guard let networkError = error as? DICOMNetworkError else {
            // Retry unknown errors
            return true
        }
        
        switch networkError {
        case .connectionFailed, .timeout, .connectionClosed:
            // Transient errors - retry
            return true
        case .associationRejected(let result, _, _):
            // Retry only transient rejections
            return result == .rejectedTransient
        case .artimTimerExpired, .operationTimeout:
            // Timeout waiting for response - retry
            return true
        case .invalidAETitle, .invalidState, .noPresentationContextAccepted,
             .sopClassNotSupported, .unexpectedPDUType, .invalidPDU,
             .encodingFailed, .decodingFailed, .limitExceeded, .pduTooLarge:
            // Protocol/configuration errors - don't retry
            return false
        case .associationAborted, .queryFailed, .retrieveFailed, .storeFailed,
             .printOperationFailed, .mppsOperationFailed:
            // Application-level failures - don't retry
            return false
        case .circuitBreakerOpen:
            // Circuit is open - don't retry
            return false
        case .partialFailure:
            // Partial failures shouldn't be retried as some operations succeeded
            return false
        case .unexpectedResponse:
            // Unexpected response format - don't retry
            return false
        }
    }
    
    // MARK: - Circuit Breaker Access
    
    /// Gets the current circuit breaker statistics, if circuit breaker is enabled
    ///
    /// - Returns: Circuit breaker statistics, or nil if circuit breaker is disabled
    public func circuitBreakerStatistics() async -> CircuitBreakerStatistics? {
        guard let breaker = circuitBreaker else { return nil }
        return await breaker.statistics()
    }
    
    /// Resets the circuit breaker to closed state
    ///
    /// Call this if you want to manually reset the circuit breaker after
    /// the underlying issue has been resolved.
    public func resetCircuitBreaker() async {
        await circuitBreaker?.reset()
    }
}

// MARK: - CustomStringConvertible

extension DICOMClient: CustomStringConvertible {
    public var description: String {
        """
        DICOMClient:
          Host: \(configuration.host):\(configuration.port)
          Calling AE: \(configuration.callingAETitle)
          Called AE: \(configuration.calledAETitle)
          TLS: \(configuration.tlsEnabled)
          Retry: \(configuration.retryPolicy.maxAttempts) attempts
          Circuit Breaker: \(configuration.circuitBreakerEnabled ? "enabled" : "disabled")
        """
    }
}

#endif
