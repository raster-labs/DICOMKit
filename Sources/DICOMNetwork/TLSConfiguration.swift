import Foundation
#if canImport(Network)
import Network
#if canImport(Security)
import Security
// NEMA-verified: 2026a, checked 2026-10-06 — compared with PS3.15 2026a Annex B (B.1–B.3 and B.9–B.11 retired; B.12 / B.13 live): the profile titles in SecureTransportConnectionProfile are the B.12 / B.13 section titles, the TLS versions of `.bcp195` / `.modifiedBCP195` follow B.12 (TLS 1.2 shall, 1.3 may and is attempted) and B.13 (TLS 1.2 or 1.3, 1.3 attempted), and the 9 TLSCipherSuite names are text-diffed against the B.13 TLS 1.3 list (3 of its 5) and TLS 1.2 required list (6 of its 10) — the remaining B.13 suites (CCM, CCM_8, Camellia, DHE) are not exposed by Security's tls_ciphersuite_t; citation to a non-existent PS3.8 Annex A removed (2026-09-28)
#endif

// MARK: - TLSConfiguration

/// Configuration for TLS (Transport Layer Security) in DICOM connections
///
/// Provides comprehensive TLS settings including protocol version, certificate
/// validation, and custom certificate configuration.
///
/// Reference: PS3.15 Annex B.12 "BCP 195 RFC 8996, 9325 TLS Secure Transport Connection
/// Profile" and B.13 "Modified BCP 195 RFC 8996, 9325 TLS Secure Transport Connection
/// Profile" (PS3.15 2026a; the older B.1/B.3/B.9-B.11 profiles are retired). PS3.8 has no
/// TLS annex: it defers the secure transport to the PS3.15 profiles (PS3.8 §9.1.1).
///
/// Conformance note: B.12 requires TLS 1.2 (TLS 1.3 optional, preferred when offered) and
/// forbids NULL key exchange, cipher and hash; B.13 additionally restricts the cipher suites
/// and key lengths. Use ``bcp195`` / ``modifiedBCP195`` (or ``profile(_:certificateValidation:clientIdentity:)``)
/// for a configuration per profile: ``modifiedBCP195`` restricts the offered cipher suites to
/// the B.13 suites Security exposes (``TLSCipherSuite``). `TLSConfiguration.default` meets the
/// version rule of B.12; `.strict` pins TLS 1.3 and so is no B.12 configuration (B.12 requires
/// TLS 1.2). The `tlsProtocol10` / `tlsProtocol11` options exist for legacy peers only — a
/// connection using them conforms to no PS3.15 profile (RFC 8996 prohibits them).
///
/// ## Usage
///
/// ```swift
/// // Use system trust store (default)
/// let defaultTLS = TLSConfiguration.default
///
/// // Development mode with self-signed certificates
/// let devTLS = TLSConfiguration.insecure
///
/// // Custom configuration
/// let customTLS = TLSConfiguration(
///     minimumVersion: .tlsProtocol12,
///     maximumVersion: .tlsProtocol13,
///     certificateValidation: .system
/// )
///
/// // Use in client configuration
/// let config = try DICOMClientConfiguration(
///     host: "secure-pacs.hospital.com",
///     port: 2762,
///     callingAE: "MY_SCU",
///     calledAE: "PACS",
///     tlsConfiguration: customTLS
/// )
/// ```
public struct TLSConfiguration: Sendable, Hashable {
    
    // MARK: - TLS Protocol Version
    
    /// Minimum TLS protocol version to accept
    public let minimumVersion: TLSProtocolVersion
    
    /// Maximum TLS protocol version to accept (nil means no maximum)
    public let maximumVersion: TLSProtocolVersion?
    
    /// Certificate validation mode
    public let certificateValidation: CertificateValidation
    
    /// Application protocols to advertise (ALPN)
    public let applicationProtocols: [String]
    
    /// Optional client identity for mutual TLS authentication
    public let clientIdentity: ClientIdentity?

    /// The cipher suites offered, in order; nil leaves the choice to Network.framework's
    /// default set. ``modifiedBCP195`` sets the PS3.15 2026a B.13 suites Security exposes.
    public let cipherSuites: [TLSCipherSuite]?
    
    // MARK: - Initialization
    
    /// Creates a TLS configuration with specified settings
    ///
    /// - Parameters:
    ///   - minimumVersion: Minimum TLS protocol version (default: TLS 1.2)
    ///   - maximumVersion: Maximum TLS protocol version (default: nil, meaning latest)
    ///   - certificateValidation: Certificate validation mode (default: system trust store)
    ///   - applicationProtocols: ALPN protocols to advertise (default: none)
    ///   - clientIdentity: Client certificate for mutual TLS (default: none)
    ///   - cipherSuites: Cipher suites to offer, in order (default: nil, Network.framework's set)
    public init(
        minimumVersion: TLSProtocolVersion = .tlsProtocol12,
        maximumVersion: TLSProtocolVersion? = nil,
        certificateValidation: CertificateValidation = .system,
        applicationProtocols: [String] = [],
        clientIdentity: ClientIdentity? = nil,
        cipherSuites: [TLSCipherSuite]? = nil
    ) {
        self.minimumVersion = minimumVersion
        self.maximumVersion = maximumVersion
        self.certificateValidation = certificateValidation
        self.applicationProtocols = applicationProtocols
        self.clientIdentity = clientIdentity
        self.cipherSuites = cipherSuites
    }
    
    // MARK: - Preset Configurations
    
    /// Default secure TLS configuration
    ///
    /// Uses TLS 1.2 as minimum with system trust store validation.
    /// Suitable for production use with properly signed certificates.
    public static let `default` = TLSConfiguration(
        minimumVersion: .tlsProtocol12,
        maximumVersion: nil,
        certificateValidation: .system
    )
    
    /// Strict TLS configuration requiring TLS 1.3
    ///
    /// Uses TLS 1.3 only with system trust store validation.
    /// Provides the highest level of security but may not work with older servers.
    /// Not a B.12 configuration (B.12 requires TLS 1.2); a B.13 client may be TLS 1.3-only,
    /// but ``modifiedBCP195`` is the B.13 configuration.
    public static let strict = TLSConfiguration(
        minimumVersion: .tlsProtocol13,
        maximumVersion: .tlsProtocol13,
        certificateValidation: .system
    )
    
    /// Insecure TLS configuration for development
    ///
    /// Disables certificate validation - **USE ONLY FOR DEVELOPMENT/TESTING**
    ///
    /// - Warning: This configuration is insecure and should never be used in production.
    ///   It allows connections to servers with self-signed, expired, or invalid certificates.
    public static let insecure = TLSConfiguration(
        minimumVersion: .tlsProtocol12,
        maximumVersion: nil,
        certificateValidation: .disabled
    )
    
    // MARK: - PS3.15 Secure Transport Connection Profiles

    /// PS3.15 2026a B.12 "BCP 195 RFC 8996, 9325 TLS Secure Transport Connection Profile".
    ///
    /// TLS 1.2 minimum and no maximum: B.12 requires TLS 1.2, allows TLS 1.3, and requires a
    /// client to attempt TLS 1.3 when supported — Network.framework offers TLS 1.3 first when
    /// the maximum is open. System trust evaluation; no client certificate (B.12 makes mutual
    /// authentication optional for clients — pass `clientIdentity` through
    /// ``profile(_:certificateValidation:clientIdentity:)`` to use it).
    ///
    /// Not enforced here: B.12 defers the cipher-suite rules to BCP 195 (RFC 9325); this
    /// configuration offers Network.framework's default suite set, which this package does not
    /// filter (use ``modifiedBCP195`` for an explicit suite list).
    public static let bcp195 = TLSConfiguration(
        minimumVersion: .tlsProtocol12,
        maximumVersion: nil,
        certificateValidation: .system
    )

    /// PS3.15 2026a B.13 "Modified BCP 195 RFC 8996, 9325 TLS Secure Transport Connection Profile".
    ///
    /// TLS 1.2 minimum and no maximum (B.13: a client supports TLS 1.2 or 1.3 and attempts
    /// TLS 1.3), system trust evaluation, and only the B.13 cipher suites that Security's
    /// `tls_ciphersuite_t` can express (``TLSCipherSuite/modifiedBCP195``): the three TLS 1.3
    /// suites AES-256-GCM, ChaCha20-Poly1305, AES-128-GCM, and six of the ten required TLS 1.2
    /// suites (ECDHE with AES-GCM or ChaCha20-Poly1305).
    ///
    /// Not enforced here: the B.13 CCM / CCM_8, Camellia and DHE suites cannot be offered
    /// (Security has no constant for them); the key-length rules (DHE ≥ 2048, ECDHE ≥ 256 bits)
    /// and certificate rules (RSA ≥ 2048 / ECC ≥ 256 bits, SHA-256 or greater) are not checked by
    /// this configuration beyond the system trust evaluation; the signature-algorithm list
    /// cannot be set through Network.framework.
    public static let modifiedBCP195 = TLSConfiguration(
        minimumVersion: .tlsProtocol12,
        maximumVersion: nil,
        certificateValidation: .system,
        cipherSuites: TLSCipherSuite.modifiedBCP195
    )

    /// The configuration for a PS3.15 2026a Annex B Secure Transport Connection Profile, with
    /// the given certificate validation and optional client identity (mutual authentication).
    public static func profile(
        _ profile: SecureTransportConnectionProfile,
        certificateValidation: CertificateValidation = .system,
        clientIdentity: ClientIdentity? = nil
    ) -> TLSConfiguration {
        let base: TLSConfiguration
        switch profile {
        case .bcp195:         base = .bcp195
        case .modifiedBCP195: base = .modifiedBCP195
        }
        return TLSConfiguration(
            minimumVersion: base.minimumVersion,
            maximumVersion: base.maximumVersion,
            certificateValidation: certificateValidation,
            applicationProtocols: base.applicationProtocols,
            clientIdentity: clientIdentity,
            cipherSuites: base.cipherSuites
        )
    }

    // MARK: - Network.framework Integration
    
    /// Creates NWProtocolTLS.Options for use with Network.framework
    ///
    /// - Returns: Configured TLS options for NWConnection
    /// - Throws: `TLSConfigurationError` if the configuration is invalid
    public func makeNWProtocolTLSOptions() throws -> NWProtocolTLS.Options {
        let options = NWProtocolTLS.Options()
        let secOptions = options.securityProtocolOptions
        
        // Set minimum TLS version using the modern API
        sec_protocol_options_set_min_tls_protocol_version(
            secOptions,
            minimumVersion.secProtocolVersion
        )
        
        // Set maximum TLS version if specified
        if let maxVersion = maximumVersion {
            sec_protocol_options_set_max_tls_protocol_version(
                secOptions,
                maxVersion.secProtocolVersion
            )
        }
        
        // Configure certificate validation
        switch certificateValidation {
        case .system:
            // Use default system trust store - no additional configuration needed
            break
            
        case .disabled:
            // Disable certificate verification for development/testing
            sec_protocol_options_set_verify_block(
                secOptions,
                { _, _, completion in
                    // Accept all certificates
                    completion(true)
                },
                .main
            )
            
        case .pinned(let pinnedCertificates):
            // Certificate pinning
            try configurePinnedCertificates(pinnedCertificates, options: secOptions)
            
        case .custom(let trustRoots):
            // Custom trust roots
            try configureCustomTrustRoots(trustRoots, options: secOptions)
        }
        
        // Restrict the offered cipher suites when a list is given (B.13)
        if let suites = cipherSuites {
            for suite in suites {
                if let value = tls_ciphersuite_t(rawValue: suite.rawValue) {
                    sec_protocol_options_append_tls_ciphersuite(secOptions, value)
                }
            }
        }

        // Configure ALPN protocols if specified
        for proto in applicationProtocols {
            sec_protocol_options_add_tls_application_protocol(
                secOptions,
                proto
            )
        }
        
        // Configure client identity for mutual TLS
        if let identity = clientIdentity {
            try configureClientIdentity(identity, options: secOptions)
        }
        
        return options
    }
    
    // MARK: - Private Certificate Configuration
    
    private func configurePinnedCertificates(
        _ certificates: [SecCertificate],
        options: sec_protocol_options_t
    ) throws {
        guard !certificates.isEmpty else {
            throw TLSConfigurationError.noPinnedCertificates
        }
        
        sec_protocol_options_set_verify_block(
            options,
            { _, secTrust, completion in
                let trust = sec_trust_copy_ref(secTrust).takeRetainedValue()
                
                // Get the server certificate using the modern API
                guard SecTrustGetCertificateCount(trust) > 0 else {
                    completion(false)
                    return
                }
                
                // Use SecTrustCopyCertificateChain (available on macOS 12+/iOS 15+)
                // Fall back to deprecated API for older systems
                let serverCert: SecCertificate?
                if #available(macOS 12.0, iOS 15.0, *) {
                    if let certChain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
                       let firstCert = certChain.first {
                        serverCert = firstCert
                    } else {
                        serverCert = nil
                    }
                } else {
                    serverCert = SecTrustGetCertificateAtIndex(trust, 0)
                }
                
                guard let serverCert = serverCert else {
                    completion(false)
                    return
                }
                
                // Check if server certificate matches any pinned certificate
                let serverCertData = SecCertificateCopyData(serverCert) as Data
                let matches = certificates.contains { pinnedCert in
                    let pinnedCertData = SecCertificateCopyData(pinnedCert) as Data
                    return serverCertData == pinnedCertData
                }
                
                completion(matches)
            },
            .main
        )
    }
    
    private func configureCustomTrustRoots(
        _ trustRoots: [SecCertificate],
        options: sec_protocol_options_t
    ) throws {
        guard !trustRoots.isEmpty else {
            throw TLSConfigurationError.noTrustRoots
        }
        
        sec_protocol_options_set_verify_block(
            options,
            { _, secTrust, completion in
                let trust = sec_trust_copy_ref(secTrust).takeRetainedValue()
                
                // Set custom anchor certificates
                let status = SecTrustSetAnchorCertificates(trust, trustRoots as CFArray)
                guard status == errSecSuccess else {
                    completion(false)
                    return
                }
                
                // Only trust the custom anchors, not the system anchors
                SecTrustSetAnchorCertificatesOnly(trust, true)
                
                // Evaluate trust
                var error: CFError?
                let trusted = SecTrustEvaluateWithError(trust, &error)
                completion(trusted)
            },
            .main
        )
    }
    
    private func configureClientIdentity(
        _ identity: ClientIdentity,
        options: sec_protocol_options_t
    ) throws {
        let secIdentity = try identity.makeSecIdentity()
        if let secIdentityRef = sec_identity_create(secIdentity) {
            sec_protocol_options_set_local_identity(options, secIdentityRef)
        }
    }
}

// MARK: - Secure Transport Connection Profile

/// The live PS3.15 2026a Annex B TLS Secure Transport Connection Profiles. B.1 (Basic TLS),
/// B.2 (ISCL), B.3 (AES TLS) and B.9–B.11 (BCP 195, Non-Downgrading BCP 195, Extended BCP 195)
/// are retired; the raw value is the profile's section title without the trailing
/// "Secure Transport Connection Profile".
public enum SecureTransportConnectionProfile: String, Sendable, Hashable, CaseIterable, Codable {
    /// PS3.15 2026a B.12 "BCP 195 RFC 8996, 9325 TLS Secure Transport Connection Profile".
    case bcp195 = "BCP 195 RFC 8996, 9325 TLS"
    /// PS3.15 2026a B.13 "Modified BCP 195 RFC 8996, 9325 TLS Secure Transport Connection Profile".
    case modifiedBCP195 = "Modified BCP 195 RFC 8996, 9325 TLS"

    /// The PS3.15 2026a Annex B section of this profile.
    public var section: String {
        switch self {
        case .bcp195:         return "B.12"
        case .modifiedBCP195: return "B.13"
        }
    }

    /// The profile's full title in PS3.15 2026a Annex B.
    public var title: String { rawValue + " Secure Transport Connection Profile" }

    /// The DICOMNetwork configuration for this profile (``TLSConfiguration/bcp195`` or
    /// ``TLSConfiguration/modifiedBCP195``).
    public var tlsConfiguration: TLSConfiguration {
        switch self {
        case .bcp195:         return .bcp195
        case .modifiedBCP195: return .modifiedBCP195
        }
    }
}

// MARK: - TLS Cipher Suite

/// TLS cipher suites that Security's `tls_ciphersuite_t` exposes and PS3.15 2026a B.13 permits,
/// by IANA name (raw value: the IANA code point). Security has no constant for the B.13 CCM,
/// CCM_8, Camellia or DHE suites, so they cannot be listed.
public enum TLSCipherSuite: UInt16, Sendable, Hashable, CaseIterable, Codable {
    /// TLS 1.3, B.13 list.
    case TLS_AES_256_GCM_SHA384 = 0x1302
    /// TLS 1.3, B.13 list.
    case TLS_CHACHA20_POLY1305_SHA256 = 0x1303
    /// TLS 1.3, B.13 list.
    case TLS_AES_128_GCM_SHA256 = 0x1301
    /// TLS 1.2, B.13 required list.
    case TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384 = 0xC02C
    /// TLS 1.2, B.13 required list.
    case TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384 = 0xC030
    /// TLS 1.2, B.13 required list.
    case TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256 = 0xCCA9
    /// TLS 1.2, B.13 required list.
    case TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256 = 0xCCA8
    /// TLS 1.2, B.13 required list.
    case TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256 = 0xC02F
    /// TLS 1.2, B.13 required list.
    case TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256 = 0xC02B

    /// The IANA name (identical to the PS3.15 2026a B.13 spelling).
    public var ianaName: String { String(describing: self) }

    /// Whether this is a TLS 1.3 suite (B.13's TLS 1.3 list) rather than a TLS 1.2 one.
    public var isTLS13: Bool { rawValue >> 8 == 0x13 }

    /// The suites ``TLSConfiguration/modifiedBCP195`` offers, in B.13's order (TLS 1.3, then TLS 1.2).
    public static let modifiedBCP195: [TLSCipherSuite] = allCases
}

// MARK: - TLS Protocol Version

/// Supported TLS protocol versions
///
/// DICOM networks typically require TLS 1.2 or higher for security compliance.
///
/// > Warning: TLS 1.0 and TLS 1.1 are deprecated and no longer supported on
/// > macOS 13+/iOS 16+ systems. On these newer systems, selecting TLS 1.0 or
/// > TLS 1.1 will automatically fall back to TLS 1.2 to maintain security
/// > compliance. If you require TLS 1.0/1.1 for legacy server compatibility,
/// > ensure your deployment targets support these protocol versions.
public enum TLSProtocolVersion: String, Sendable, Hashable, CaseIterable {
    /// TLS 1.0 (deprecated, not recommended)
    ///
    /// > Warning: TLS 1.0 is not available on macOS 13+/iOS 16+ and will
    /// > automatically fall back to TLS 1.2 on these systems.
    case tlsProtocol10 = "TLS 1.0"
    
    /// TLS 1.1 (deprecated, not recommended)
    ///
    /// > Warning: TLS 1.1 is not available on macOS 13+/iOS 16+ and will
    /// > automatically fall back to TLS 1.2 on these systems.
    case tlsProtocol11 = "TLS 1.1"
    
    /// TLS 1.2 (recommended minimum)
    case tlsProtocol12 = "TLS 1.2"
    
    /// TLS 1.3 (most secure)
    case tlsProtocol13 = "TLS 1.3"
    
    /// The corresponding Security framework protocol version
    ///
    /// > Note: On macOS 13+/iOS 16+, TLS 1.0 and TLS 1.1 are no longer
    /// > available and will return TLS 1.2 instead.
    @available(macOS 10.15, iOS 13.0, *)
    var secProtocolVersion: tls_protocol_version_t {
        switch self {
        case .tlsProtocol10:
            // TLSv10 is deprecated and not available on newer systems
            // Fall back to TLS 1.2 for security compliance
            if #available(macOS 13.0, iOS 16.0, *) {
                return .TLSv12
            } else {
                return .TLSv10
            }
        case .tlsProtocol11:
            // TLSv11 is deprecated and not available on newer systems
            // Fall back to TLS 1.2 for security compliance
            if #available(macOS 13.0, iOS 16.0, *) {
                return .TLSv12
            } else {
                return .TLSv11
            }
        case .tlsProtocol12:
            return .TLSv12
        case .tlsProtocol13:
            return .TLSv13
        }
    }
    
    /// Whether this protocol version is available on the current system
    ///
    /// TLS 1.0 and TLS 1.1 are not available on macOS 13+/iOS 16+.
    @available(macOS 10.15, iOS 13.0, *)
    public var isAvailableOnCurrentSystem: Bool {
        switch self {
        case .tlsProtocol10, .tlsProtocol11:
            if #available(macOS 13.0, iOS 16.0, *) {
                return false
            }
            return true
        case .tlsProtocol12, .tlsProtocol13:
            return true
        }
    }
}

// MARK: - Certificate Validation

/// Certificate validation mode for TLS connections
///
/// Determines how server certificates are validated during TLS handshake.
public enum CertificateValidation: Sendable, Hashable {
    /// Use system trust store for validation (default, recommended)
    ///
    /// Certificates are validated against the system's trusted CA certificates.
    /// This is the standard, secure mode for production use.
    case system
    
    /// Disable certificate validation (insecure, development only)
    ///
    /// - Warning: This mode accepts any certificate including self-signed,
    ///   expired, and revoked certificates. Use only for development/testing.
    case disabled
    
    /// Pin specific certificates
    ///
    /// Only accept connections where the server presents one of the pinned certificates.
    /// Provides the strongest security but requires certificate management.
    ///
    /// - Parameter certificates: The certificates to pin
    case pinned([SecCertificate])
    
    /// Use custom trust roots instead of system trust store
    ///
    /// Useful for internal PKI where a private CA is used.
    ///
    /// - Parameter trustRoots: Custom CA certificates to trust
    case custom([SecCertificate])
    
    // MARK: - Hashable conformance
    
    public static func == (lhs: CertificateValidation, rhs: CertificateValidation) -> Bool {
        switch (lhs, rhs) {
        case (.system, .system):
            return true
        case (.disabled, .disabled):
            return true
        case (.pinned(let lhsCerts), .pinned(let rhsCerts)):
            return certificatesEqual(lhsCerts, rhsCerts)
        case (.custom(let lhsCerts), .custom(let rhsCerts)):
            return certificatesEqual(lhsCerts, rhsCerts)
        default:
            return false
        }
    }
    
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .system:
            hasher.combine(0)
        case .disabled:
            hasher.combine(1)
        case .pinned(let certs):
            hasher.combine(2)
            for cert in certs {
                hasher.combine(SecCertificateCopyData(cert) as Data)
            }
        case .custom(let certs):
            hasher.combine(3)
            for cert in certs {
                hasher.combine(SecCertificateCopyData(cert) as Data)
            }
        }
    }
    
    private static func certificatesEqual(_ lhs: [SecCertificate], _ rhs: [SecCertificate]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (lhsCert, rhsCert) in zip(lhs, rhs) {
            let lhsData = SecCertificateCopyData(lhsCert) as Data
            let rhsData = SecCertificateCopyData(rhsCert) as Data
            if lhsData != rhsData {
                return false
            }
        }
        return true
    }
}

// MARK: - Client Identity

/// Client identity for mutual TLS (mTLS) authentication
///
/// Used when the server requires client certificate authentication.
public struct ClientIdentity: @unchecked Sendable, Hashable {
    
    /// The source of the client identity
    public enum Source: Hashable {
        /// Load identity from PKCS#12 data
        case pkcs12(data: Data, password: String)
        
        /// Load identity from keychain by label
        case keychain(label: String)
        
        /// Use an existing SecIdentity
        case secIdentity(SecIdentity)
        
        // MARK: - Hashable conformance
        
        public static func == (lhs: Source, rhs: Source) -> Bool {
            switch (lhs, rhs) {
            case (.pkcs12(let lhsData, let lhsPassword), .pkcs12(let rhsData, let rhsPassword)):
                return lhsData == rhsData && lhsPassword == rhsPassword
            case (.keychain(let lhsLabel), .keychain(let rhsLabel)):
                return lhsLabel == rhsLabel
            case (.secIdentity(let lhsIdentity), .secIdentity(let rhsIdentity)):
                // Compare identities by their certificate data
                var lhsCert: SecCertificate?
                var rhsCert: SecCertificate?
                SecIdentityCopyCertificate(lhsIdentity, &lhsCert)
                SecIdentityCopyCertificate(rhsIdentity, &rhsCert)
                guard let lc = lhsCert, let rc = rhsCert else { return false }
                return SecCertificateCopyData(lc) as Data == SecCertificateCopyData(rc) as Data
            default:
                return false
            }
        }
        
        public func hash(into hasher: inout Hasher) {
            switch self {
            case .pkcs12(let data, let password):
                hasher.combine(0)
                hasher.combine(data)
                hasher.combine(password)
            case .keychain(let label):
                hasher.combine(1)
                hasher.combine(label)
            case .secIdentity(let identity):
                hasher.combine(2)
                var cert: SecCertificate?
                SecIdentityCopyCertificate(identity, &cert)
                if let c = cert {
                    hasher.combine(SecCertificateCopyData(c) as Data)
                }
            }
        }
    }
    
    /// The source of the identity
    public let source: Source
    
    /// Creates a client identity from PKCS#12 data
    ///
    /// - Parameters:
    ///   - pkcs12Data: The PKCS#12 (.p12 or .pfx) file data
    ///   - password: The password for the PKCS#12 file
    public init(pkcs12Data: Data, password: String) {
        self.source = .pkcs12(data: pkcs12Data, password: password)
    }
    
    /// Creates a client identity from the keychain
    ///
    /// - Parameter keychainLabel: The label of the identity in the keychain
    public init(keychainLabel: String) {
        self.source = .keychain(label: keychainLabel)
    }
    
    /// Creates a client identity from an existing SecIdentity
    ///
    /// - Parameter identity: The SecIdentity to use
    public init(identity: SecIdentity) {
        self.source = .secIdentity(identity)
    }
    
    /// Creates the SecIdentity from the configured source
    ///
    /// - Returns: The SecIdentity for use with TLS
    /// - Throws: `TLSConfigurationError` if the identity cannot be loaded
    public func makeSecIdentity() throws -> SecIdentity {
        switch source {
        case .pkcs12(let data, let password):
            return try loadPKCS12Identity(data: data, password: password)
            
        case .keychain(let label):
            return try loadKeychainIdentity(label: label)
            
        case .secIdentity(let identity):
            return identity
        }
    }
    
    private func loadPKCS12Identity(data: Data, password: String) throws -> SecIdentity {
        let options: [String: Any] = [kSecImportExportPassphrase as String: password]
        var items: CFArray?
        
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
        
        guard status == errSecSuccess else {
            throw TLSConfigurationError.pkcs12ImportFailed(status: status)
        }
        
        guard let itemsArray = items as? [[String: Any]],
              let firstItem = itemsArray.first,
              let identityRef = firstItem[kSecImportItemIdentity as String] else {
            throw TLSConfigurationError.pkcs12NoIdentity
        }
        
        // The identity is guaranteed to be a SecIdentity from SecPKCS12Import
        // swiftlint:disable:next force_cast
        let identity = identityRef as! SecIdentity
        return identity
    }
    
    private func loadKeychainIdentity(label: String) throws -> SecIdentity {
        // kSecClassIdentity queries do not reliably filter on kSecAttrLabel
        // (the label lives on the certificate half of the identity), so fetch
        // attributes for all candidates and match the label ourselves.
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: label,
            kSecReturnRef as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            throw TLSConfigurationError.keychainIdentityNotFound(label: label, status: status)
        }

        guard let items = result as? [[String: Any]] else {
            throw TLSConfigurationError.keychainIdentityNotFound(label: label, status: errSecItemNotFound)
        }

        for attributes in items {
            guard let itemLabel = attributes[kSecAttrLabel as String] as? String,
                  itemLabel == label,
                  let identityRef = attributes[kSecValueRef as String] else {
                continue
            }
            // The value ref is guaranteed to be a SecIdentity for kSecClassIdentity
            // swiftlint:disable:next force_cast
            return identityRef as! SecIdentity
        }

        throw TLSConfigurationError.keychainIdentityNotFound(label: label, status: errSecItemNotFound)
    }
}

extension ClientIdentity.Source: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        switch self {
        case .pkcs12:
            return "pkcs12(redacted)"
        case .keychain:
            return "keychain(redacted)"
        case .secIdentity:
            return "SecIdentity(redacted)"
        }
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["source": description], displayStyle: .enum)
    }
}

extension ClientIdentity: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "ClientIdentity(\(source))" }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["source": source.description], displayStyle: .struct)
    }
}

// MARK: - TLS Configuration Errors

/// Errors that can occur when configuring TLS
public enum TLSConfigurationError: Error, Sendable, CustomStringConvertible {
    /// No pinned certificates were provided
    case noPinnedCertificates
    
    /// No trust roots were provided
    case noTrustRoots
    
    /// Failed to import PKCS#12 data
    case pkcs12ImportFailed(status: OSStatus)
    
    /// PKCS#12 data did not contain an identity
    case pkcs12NoIdentity
    
    /// Identity not found in keychain
    case keychainIdentityNotFound(label: String, status: OSStatus)
    
    /// Certificate data is invalid
    case invalidCertificateData
    
    public var description: String {
        switch self {
        case .noPinnedCertificates:
            return "No pinned certificates provided for certificate pinning"
        case .noTrustRoots:
            return "No trust roots provided for custom certificate validation"
        case .pkcs12ImportFailed(let status):
            return "Failed to import PKCS#12 data: OSStatus \(status)"
        case .pkcs12NoIdentity:
            return "PKCS#12 data did not contain an identity"
        case .keychainIdentityNotFound(let label, let status):
            return "Identity '\(label)' not found in keychain: OSStatus \(status)"
        case .invalidCertificateData:
            return "Certificate data is invalid or could not be parsed"
        }
    }
}

// MARK: - Certificate Loading Helpers

extension TLSConfiguration {
    
    /// Creates a certificate from DER-encoded data
    ///
    /// - Parameter derData: The DER-encoded certificate data
    /// - Returns: The SecCertificate
    /// - Throws: `TLSConfigurationError.invalidCertificateData` if data is invalid
    public static func certificate(fromDER derData: Data) throws -> SecCertificate {
        guard let certificate = SecCertificateCreateWithData(nil, derData as CFData) else {
            throw TLSConfigurationError.invalidCertificateData
        }
        return certificate
    }
    
    /// Creates a certificate from PEM-encoded data
    ///
    /// - Parameter pemData: The PEM-encoded certificate data
    /// - Returns: The SecCertificate
    /// - Throws: `TLSConfigurationError.invalidCertificateData` if data is invalid
    public static func certificate(fromPEM pemData: Data) throws -> SecCertificate {
        guard let pemString = String(data: pemData, encoding: .utf8) else {
            throw TLSConfigurationError.invalidCertificateData
        }
        
        // Extract base64 content from PEM
        let lines = pemString.components(separatedBy: .newlines)
        var base64Content = ""
        var inCertificate = false
        
        for line in lines {
            if line.contains("-----BEGIN CERTIFICATE-----") {
                inCertificate = true
            } else if line.contains("-----END CERTIFICATE-----") {
                break
            } else if inCertificate {
                base64Content += line.trimmingCharacters(in: .whitespaces)
            }
        }
        
        guard let derData = Data(base64Encoded: base64Content) else {
            throw TLSConfigurationError.invalidCertificateData
        }
        
        return try certificate(fromDER: derData)
    }
    
    /// Creates certificates from a PEM file containing multiple certificates
    ///
    /// - Parameter pemData: The PEM-encoded data containing one or more certificates
    /// - Returns: Array of SecCertificates
    /// - Throws: `TLSConfigurationError.invalidCertificateData` if data is invalid
    public static func certificates(fromPEM pemData: Data) throws -> [SecCertificate] {
        guard let pemString = String(data: pemData, encoding: .utf8) else {
            throw TLSConfigurationError.invalidCertificateData
        }
        
        var certificates: [SecCertificate] = []
        var currentCertBase64 = ""
        var inCertificate = false
        
        for line in pemString.components(separatedBy: .newlines) {
            if line.contains("-----BEGIN CERTIFICATE-----") {
                inCertificate = true
                currentCertBase64 = ""
            } else if line.contains("-----END CERTIFICATE-----") {
                inCertificate = false
                if let derData = Data(base64Encoded: currentCertBase64),
                   let cert = SecCertificateCreateWithData(nil, derData as CFData) {
                    certificates.append(cert)
                }
            } else if inCertificate {
                currentCertBase64 += line.trimmingCharacters(in: .whitespaces)
            }
        }
        
        guard !certificates.isEmpty else {
            throw TLSConfigurationError.invalidCertificateData
        }
        
        return certificates
    }
}

// MARK: - CustomStringConvertible

extension TLSConfiguration: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        var parts: [String] = []
        parts.append("TLS \(minimumVersion.rawValue)")
        if let maxVersion = maximumVersion {
            parts.append("- \(maxVersion.rawValue)")
        } else {
            parts.append("+")
        }
        
        switch certificateValidation {
        case .system:
            parts.append("(system trust)")
        case .disabled:
            parts.append("(INSECURE)")
        case .pinned(let certs):
            parts.append("(pinned: \(certs.count) certs)")
        case .custom(let roots):
            parts.append("(custom: \(roots.count) roots)")
        }
        
        if clientIdentity != nil {
            parts.append("+ client cert")
        }
        
        return parts.joined(separator: " ")
    }

    public var debugDescription: String { description }

    /// A redacted mirror that retains operational TLS policy while replacing the
    /// credential-bearing client identity with a presence flag.
    public var customMirror: Mirror {
        let validation: String
        switch certificateValidation {
        case .system:
            validation = "system"
        case .disabled:
            validation = "disabled"
        case .pinned(let certificates):
            validation = "pinned(\(certificates.count))"
        case .custom(let roots):
            validation = "custom(\(roots.count))"
        }

        let children: KeyValuePairs<String, Any> = [
            "minimumVersion": minimumVersion.rawValue,
            "maximumVersion": maximumVersion?.rawValue as Any,
            "certificateValidation": validation,
            "applicationProtocols": applicationProtocols,
            "hasClientIdentity": clientIdentity != nil,
        ]
        return Mirror(self, children: children, displayStyle: .struct)
    }
}

#endif
