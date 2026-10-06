import XCTest
@testable import DICOMNetwork

#if canImport(Network) && canImport(Security)

import Security

final class TLSConfigurationTests: XCTestCase {
    
    // MARK: - TLS Protocol Version Tests
    
    func testTLSProtocolVersionRawValues() {
        XCTAssertEqual(TLSProtocolVersion.tlsProtocol10.rawValue, "TLS 1.0")
        XCTAssertEqual(TLSProtocolVersion.tlsProtocol11.rawValue, "TLS 1.1")
        XCTAssertEqual(TLSProtocolVersion.tlsProtocol12.rawValue, "TLS 1.2")
        XCTAssertEqual(TLSProtocolVersion.tlsProtocol13.rawValue, "TLS 1.3")
    }
    
    func testTLSProtocolVersionAllCases() {
        let allCases = TLSProtocolVersion.allCases
        XCTAssertEqual(allCases.count, 4)
        XCTAssertTrue(allCases.contains(.tlsProtocol10))
        XCTAssertTrue(allCases.contains(.tlsProtocol11))
        XCTAssertTrue(allCases.contains(.tlsProtocol12))
        XCTAssertTrue(allCases.contains(.tlsProtocol13))
    }
    
    // MARK: - TLS Configuration Creation Tests
    
    func testDefaultConfiguration() {
        let config = TLSConfiguration.default
        
        XCTAssertEqual(config.minimumVersion, .tlsProtocol12)
        XCTAssertNil(config.maximumVersion)
        XCTAssertEqual(config.certificateValidation, .system)
        XCTAssertTrue(config.applicationProtocols.isEmpty)
        XCTAssertNil(config.clientIdentity)
    }
    
    func testStrictConfiguration() {
        let config = TLSConfiguration.strict
        
        XCTAssertEqual(config.minimumVersion, .tlsProtocol13)
        XCTAssertEqual(config.maximumVersion, .tlsProtocol13)
        XCTAssertEqual(config.certificateValidation, .system)
    }
    
    func testInsecureConfiguration() {
        let config = TLSConfiguration.insecure
        
        XCTAssertEqual(config.minimumVersion, .tlsProtocol12)
        XCTAssertNil(config.maximumVersion)
        XCTAssertEqual(config.certificateValidation, .disabled)
    }
    
    func testCustomConfiguration() {
        let config = TLSConfiguration(
            minimumVersion: .tlsProtocol12,
            maximumVersion: .tlsProtocol13,
            certificateValidation: .system,
            applicationProtocols: ["dicom"],
            clientIdentity: nil
        )
        
        XCTAssertEqual(config.minimumVersion, .tlsProtocol12)
        XCTAssertEqual(config.maximumVersion, .tlsProtocol13)
        XCTAssertEqual(config.certificateValidation, .system)
        XCTAssertEqual(config.applicationProtocols, ["dicom"])
        XCTAssertNil(config.clientIdentity)
    }
    
    // MARK: - Certificate Validation Mode Tests
    
    func testCertificateValidationEquality() {
        XCTAssertEqual(CertificateValidation.system, CertificateValidation.system)
        XCTAssertEqual(CertificateValidation.disabled, CertificateValidation.disabled)
        XCTAssertNotEqual(CertificateValidation.system, CertificateValidation.disabled)
    }
    
    func testCertificateValidationHashable() {
        let validations: Set<CertificateValidation> = [.system, .disabled]
        XCTAssertEqual(validations.count, 2)
        XCTAssertTrue(validations.contains(.system))
        XCTAssertTrue(validations.contains(.disabled))
    }
    
    // MARK: - TLS Configuration Hashable Tests
    
    func testTLSConfigurationEquality() {
        let config1 = TLSConfiguration.default
        let config2 = TLSConfiguration.default
        let config3 = TLSConfiguration.strict
        
        XCTAssertEqual(config1, config2)
        XCTAssertNotEqual(config1, config3)
    }
    
    func testTLSConfigurationHashable() {
        let config1 = TLSConfiguration.default
        let config2 = TLSConfiguration.default
        
        XCTAssertEqual(config1.hashValue, config2.hashValue)
    }
    
    // MARK: - Description Tests
    
    func testDefaultConfigurationDescription() {
        let config = TLSConfiguration.default
        let description = config.description
        
        XCTAssertTrue(description.contains("TLS 1.2"))
        XCTAssertTrue(description.contains("system trust"))
    }
    
    func testInsecureConfigurationDescription() {
        let config = TLSConfiguration.insecure
        let description = config.description
        
        XCTAssertTrue(description.contains("INSECURE"))
    }
    
    func testStrictConfigurationDescription() {
        let config = TLSConfiguration.strict
        let description = config.description
        
        XCTAssertTrue(description.contains("TLS 1.3"))
    }
    
    // MARK: - TLS Configuration Error Tests
    
    func testTLSConfigurationErrorDescriptions() {
        XCTAssertTrue(TLSConfigurationError.noPinnedCertificates.description.contains("pinned"))
        XCTAssertTrue(TLSConfigurationError.noTrustRoots.description.contains("trust roots"))
        XCTAssertTrue(TLSConfigurationError.pkcs12ImportFailed(status: -1).description.contains("PKCS#12"))
        XCTAssertTrue(TLSConfigurationError.pkcs12NoIdentity.description.contains("identity"))
        XCTAssertTrue(TLSConfigurationError.keychainIdentityNotFound(label: "test", status: -1).description.contains("test"))
        XCTAssertTrue(TLSConfigurationError.invalidCertificateData.description.contains("invalid"))
    }
    
    // MARK: - Certificate Loading Helper Tests
    
    func testCertificateFromInvalidDERThrows() {
        let invalidData = Data([0x00, 0x01, 0x02, 0x03])
        
        XCTAssertThrowsError(try TLSConfiguration.certificate(fromDER: invalidData)) { error in
            XCTAssertTrue(error is TLSConfigurationError)
            if case TLSConfigurationError.invalidCertificateData = error {
                // Expected
            } else {
                XCTFail("Wrong error type")
            }
        }
    }
    
    func testCertificateFromInvalidPEMThrows() {
        let invalidPEM = "Not a valid PEM certificate".data(using: .utf8)!
        
        XCTAssertThrowsError(try TLSConfiguration.certificate(fromPEM: invalidPEM)) { error in
            XCTAssertTrue(error is TLSConfigurationError)
        }
    }
    
    func testCertificatesFromEmptyPEMThrows() {
        let emptyPEM = "".data(using: .utf8)!
        
        XCTAssertThrowsError(try TLSConfiguration.certificates(fromPEM: emptyPEM)) { error in
            XCTAssertTrue(error is TLSConfigurationError)
        }
    }
    
    // MARK: - Client Identity Tests
    
    func testClientIdentityFromPKCS12() {
        let identity = ClientIdentity(pkcs12Data: Data(), password: "test")
        
        if case .pkcs12(let data, let password) = identity.source {
            XCTAssertTrue(data.isEmpty)
            XCTAssertEqual(password, "test")
        } else {
            XCTFail("Wrong source type")
        }
    }
    
    func testClientIdentityFromKeychain() {
        let identity = ClientIdentity(keychainLabel: "my-identity")
        
        if case .keychain(let label) = identity.source {
            XCTAssertEqual(label, "my-identity")
        } else {
            XCTFail("Wrong source type")
        }
    }
    
    func testClientIdentityEquality() {
        let identity1 = ClientIdentity(keychainLabel: "test")
        let identity2 = ClientIdentity(keychainLabel: "test")
        let identity3 = ClientIdentity(keychainLabel: "other")
        
        XCTAssertEqual(identity1, identity2)
        XCTAssertNotEqual(identity1, identity3)
    }
    
    func testClientIdentityMakeSecIdentityFromInvalidPKCS12Throws() {
        let identity = ClientIdentity(pkcs12Data: Data([0x00]), password: "wrong")
        
        XCTAssertThrowsError(try identity.makeSecIdentity()) { error in
            XCTAssertTrue(error is TLSConfigurationError)
        }
    }
    
    func testClientIdentityMakeSecIdentityFromMissingKeychainThrows() {
        let identity = ClientIdentity(keychainLabel: "non-existent-identity-12345")
        
        XCTAssertThrowsError(try identity.makeSecIdentity()) { error in
            XCTAssertTrue(error is TLSConfigurationError)
        }
    }
}

// MARK: - DICOMClientConfiguration TLS Tests

final class DICOMClientConfigurationTLSTests: XCTestCase {
    
    func testConfigurationWithTLSEnabled() throws {
        let config = try DICOMClientConfiguration(
            host: "secure-pacs.hospital.com",
            port: 2762,
            callingAE: "MY_SCU",
            calledAE: "PACS",
            tlsEnabled: true
        )
        
        XCTAssertTrue(config.tlsEnabled)
        XCTAssertNotNil(config.tlsConfiguration)
        XCTAssertEqual(config.tlsConfiguration, .default)
    }
    
    func testConfigurationWithTLSDisabled() throws {
        let config = try DICOMClientConfiguration(
            host: "pacs.hospital.com",
            port: 11112,
            callingAE: "MY_SCU",
            calledAE: "PACS",
            tlsEnabled: false
        )
        
        XCTAssertFalse(config.tlsEnabled)
        XCTAssertNil(config.tlsConfiguration)
    }
    
    func testConfigurationWithCustomTLSConfiguration() throws {
        let tlsConfig = TLSConfiguration(
            minimumVersion: .tlsProtocol13,
            maximumVersion: .tlsProtocol13,
            certificateValidation: .system
        )
        
        let config = try DICOMClientConfiguration(
            host: "secure-pacs.hospital.com",
            port: 2762,
            callingAE: "MY_SCU",
            calledAE: "PACS",
            tlsConfiguration: tlsConfig
        )
        
        XCTAssertTrue(config.tlsEnabled)
        XCTAssertEqual(config.tlsConfiguration, tlsConfig)
    }
    
    func testConfigurationWithInsecureTLS() throws {
        let config = try DICOMClientConfiguration(
            host: "dev-pacs.local",
            port: 2762,
            callingAE: "MY_SCU",
            calledAE: "PACS",
            tlsConfiguration: .insecure
        )
        
        XCTAssertTrue(config.tlsEnabled)
        XCTAssertEqual(config.tlsConfiguration?.certificateValidation, .disabled)
    }
    
    func testConfigurationWithNilTLSConfiguration() throws {
        let config = try DICOMClientConfiguration(
            host: "pacs.hospital.com",
            port: 11112,
            callingAE: "MY_SCU",
            calledAE: "PACS",
            tlsConfiguration: nil
        )
        
        XCTAssertFalse(config.tlsEnabled)
        XCTAssertNil(config.tlsConfiguration)
    }
    
    func testConfigurationTLSHashable() throws {
        let tlsConfig = TLSConfiguration.default
        
        let config1 = try DICOMClientConfiguration(
            host: "pacs.hospital.com",
            port: 11112,
            callingAE: "MY_SCU",
            calledAE: "PACS",
            tlsConfiguration: tlsConfig
        )
        
        let config2 = try DICOMClientConfiguration(
            host: "pacs.hospital.com",
            port: 11112,
            callingAE: "MY_SCU",
            calledAE: "PACS",
            tlsConfiguration: tlsConfig
        )
        
        let config3 = try DICOMClientConfiguration(
            host: "pacs.hospital.com",
            port: 11112,
            callingAE: "MY_SCU",
            calledAE: "PACS",
            tlsConfiguration: .strict
        )
        
        XCTAssertEqual(config1, config2)
        XCTAssertNotEqual(config1, config3)
        XCTAssertEqual(config1.hashValue, config2.hashValue)
    }
    
    func testConfigurationWithPrevalidatedAETitlesAndTLS() {
        let callingAE = try! AETitle("MY_SCU")
        let calledAE = try! AETitle("PACS")
        
        let config = DICOMClientConfiguration(
            host: "secure-pacs.hospital.com",
            port: 2762,
            callingAETitle: callingAE,
            calledAETitle: calledAE,
            tlsConfiguration: .default
        )
        
        XCTAssertTrue(config.tlsEnabled)
        XCTAssertEqual(config.tlsConfiguration, .default)
    }
}

// MARK: - DICOMConnection TLS Tests

final class DICOMConnectionTLSTests: XCTestCase {
    
    func testConnectionWithTLSConfiguration() throws {
        let tlsConfig = TLSConfiguration.default
        
        let connection = try DICOMConnection(
            host: "secure-pacs.hospital.com",
            port: 2762,
            tlsConfiguration: tlsConfig
        )
        
        XCTAssertEqual(connection.host, "secure-pacs.hospital.com")
        XCTAssertEqual(connection.port, 2762)
        XCTAssertEqual(connection.tlsConfiguration, tlsConfig)
    }
    
    func testConnectionWithNilTLSConfiguration() throws {
        let connection = try DICOMConnection(
            host: "pacs.hospital.com",
            port: 11112,
            tlsConfiguration: nil
        )
        
        XCTAssertEqual(connection.host, "pacs.hospital.com")
        XCTAssertEqual(connection.port, 11112)
        XCTAssertNil(connection.tlsConfiguration)
    }
    
    func testConnectionWithInsecureTLS() throws {
        let connection = try DICOMConnection(
            host: "dev-pacs.local",
            port: 2762,
            tlsConfiguration: .insecure
        )
        
        XCTAssertEqual(connection.tlsConfiguration?.certificateValidation, .disabled)
    }
    
    func testConnectionWithStrictTLS() throws {
        let connection = try DICOMConnection(
            host: "strict-pacs.hospital.com",
            port: 2762,
            tlsConfiguration: .strict
        )
        
        XCTAssertEqual(connection.tlsConfiguration?.minimumVersion, .tlsProtocol13)
        XCTAssertEqual(connection.tlsConfiguration?.maximumVersion, .tlsProtocol13)
    }

    // MARK: - PS3.15 2026a Annex B profiles (P-STUDIO-TLS-PROFILES)

    /// PS3.15 2026a B.12 / B.13 section titles (extracted from part15_2026a.xml by script, 2026-10-06).
    private static let b12Title = "BCP 195 RFC 8996, 9325 TLS Secure Transport Connection Profile"
    private static let b13Title = "Modified BCP 195 RFC 8996, 9325 TLS Secure Transport Connection Profile"

    /// PS3.15 2026a B.13 cipher-suite lists: TLS 1.3 (5) and TLS 1.2 required (10).
    private static let b13TLS13 = ["TLS_AES_256_GCM_SHA384", "TLS_CHACHA20_POLY1305_SHA256", "TLS_AES_128_GCM_SHA256",
                                   "TLS_AES_128_CCM_SHA256", "TLS_AES_128_CCM_8_SHA256"]
    private static let b13TLS12Required = [
        "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384", "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
        "TLS_ECDHE_ECDSA_WITH_AES_256_CCM", "TLS_ECDHE_ECDSA_WITH_AES_256_CCM_8",
        "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256", "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256",
        "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256", "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
        "TLS_ECDHE_ECDSA_WITH_AES_128_CCM", "TLS_ECDHE_ECDSA_WITH_AES_128_CCM_8"]

    func testSecureTransportConnectionProfileTitles() {
        XCTAssertEqual(SecureTransportConnectionProfile.allCases, [.bcp195, .modifiedBCP195])
        XCTAssertEqual(SecureTransportConnectionProfile.bcp195.title, Self.b12Title)
        XCTAssertEqual(SecureTransportConnectionProfile.modifiedBCP195.title, Self.b13Title)
        XCTAssertEqual(SecureTransportConnectionProfile.bcp195.section, "B.12")
        XCTAssertEqual(SecureTransportConnectionProfile.modifiedBCP195.section, "B.13")
        XCTAssertEqual(SecureTransportConnectionProfile.bcp195.tlsConfiguration, .bcp195)
        XCTAssertEqual(SecureTransportConnectionProfile.modifiedBCP195.tlsConfiguration, .modifiedBCP195)
    }

    func testBCP195ConfigurationFollowsB12() throws {
        let config = TLSConfiguration.bcp195
        // B.12: TLS 1.2 shall be supported, TLS 1.3 may be and is attempted — no maximum.
        XCTAssertEqual(config.minimumVersion, .tlsProtocol12)
        XCTAssertNil(config.maximumVersion)
        XCTAssertEqual(config.certificateValidation, .system)
        XCTAssertNil(config.clientIdentity)
        XCTAssertNil(config.cipherSuites)
        XCTAssertNoThrow(try config.makeNWProtocolTLSOptions())
    }

    func testModifiedBCP195ConfigurationFollowsB13() throws {
        let config = TLSConfiguration.modifiedBCP195
        XCTAssertEqual(config.minimumVersion, .tlsProtocol12)
        XCTAssertNil(config.maximumVersion)
        XCTAssertEqual(config.cipherSuites, TLSCipherSuite.modifiedBCP195)
        XCTAssertNoThrow(try config.makeNWProtocolTLSOptions())
    }

    func testCipherSuitesAreB13SuitesSecurityExposes() {
        let names = TLSCipherSuite.allCases.map(\.ianaName)
        XCTAssertEqual(names.filter { $0.hasPrefix("TLS_AES") || $0.hasPrefix("TLS_CHACHA") },
                       Self.b13TLS13.filter { names.contains($0) })
        XCTAssertEqual(names.filter { Self.b13TLS12Required.contains($0) },
                       Self.b13TLS12Required.filter { names.contains($0) })
        XCTAssertEqual(names.count, 9)
        for suite in TLSCipherSuite.allCases {
            XCTAssertTrue(Self.b13TLS13.contains(suite.ianaName) || Self.b13TLS12Required.contains(suite.ianaName),
                          suite.ianaName)
            XCTAssertEqual(suite.isTLS13, Self.b13TLS13.contains(suite.ianaName), suite.ianaName)
            XCTAssertNotNil(tls_ciphersuite_t(rawValue: suite.rawValue), suite.ianaName)
        }
        XCTAssertEqual(tls_ciphersuite_t(rawValue: TLSCipherSuite.TLS_AES_128_GCM_SHA256.rawValue), .AES_128_GCM_SHA256)
        XCTAssertEqual(tls_ciphersuite_t(rawValue: TLSCipherSuite.TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256.rawValue),
                       .ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256)
    }

    func testProfileFactoryCarriesValidationAndIdentity() {
        let identity = ClientIdentity(keychainLabel: "scu")
        let config = TLSConfiguration.profile(.modifiedBCP195, certificateValidation: .disabled, clientIdentity: identity)
        XCTAssertEqual(config.minimumVersion, .tlsProtocol12)
        XCTAssertEqual(config.certificateValidation, .disabled)
        XCTAssertEqual(config.clientIdentity, identity)
        XCTAssertEqual(config.cipherSuites, TLSCipherSuite.modifiedBCP195)
        XCTAssertEqual(TLSConfiguration.profile(.bcp195), .bcp195)
    }
}

#endif
