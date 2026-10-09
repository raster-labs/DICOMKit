import Testing
import Foundation
@testable import DICOMWeb

@Suite("DICOMwebConfiguration Tests")
struct DICOMwebConfigurationTests {
    
    let testURL = URL(string: "https://pacs.example.com/dicom-web")!
    
    // MARK: - Basic Initialization
    
    @Test("Basic initialization")
    func testBasicInit() {
        let config = DICOMwebConfiguration(baseURL: testURL)
        
        #expect(config.baseURL == testURL)
        #expect(config.authentication == nil)
        #expect(config.maxConcurrentRequests == 4)
        #expect(config.followRedirects == true)
        #expect(config.userAgent == "DICOMKit/1.0")
    }
    
    @Test("Initialization with authentication")
    func testWithAuthentication() {
        let config = DICOMwebConfiguration(
            baseURL: testURL,
            authentication: .bearer(token: "my-token")
        )
        
        #expect(config.authentication != nil)
    }
    
    @Test("Initialize from string URL")
    func testInitFromString() throws {
        let config = try DICOMwebConfiguration(baseURLString: "https://example.com/dicom-web")
        #expect(config.baseURL.absoluteString == "https://example.com/dicom-web")
    }
    
    @Test("Initialize from invalid string throws")
    func testInitFromInvalidString() {
        // Test with clearly invalid URL (empty string)
        do {
            _ = try DICOMwebConfiguration(baseURLString: "")
            #expect(Bool(false), "Expected error for empty URL")
        } catch {
            // Expected
            #expect(error is DICOMwebError)
        }
    }
    
    // MARK: - Authentication Tests
    
    @Test("Basic authentication header")
    func testBasicAuth() {
        let auth = DICOMwebConfiguration.Authentication.basic(
            username: "user",
            password: "pass"
        )
        let header = auth.authorizationHeader
        
        #expect(header.name == "Authorization")
        #expect(header.value.hasPrefix("Basic "))
        
        // Verify base64 encoding
        let encoded = Data("user:pass".utf8).base64EncodedString()
        #expect(header.value == "Basic \(encoded)")
    }
    
    @Test("Bearer authentication header")
    func testBearerAuth() {
        let auth = DICOMwebConfiguration.Authentication.bearer(token: "my-token")
        let header = auth.authorizationHeader
        
        #expect(header.name == "Authorization")
        #expect(header.value == "Bearer my-token")
    }
    
    @Test("API key authentication header")
    func testAPIKeyAuth() {
        let auth = DICOMwebConfiguration.Authentication.apiKey(
            key: "secret-key",
            headerName: "X-API-Key"
        )
        let header = auth.authorizationHeader
        
        #expect(header.name == "X-API-Key")
        #expect(header.value == "secret-key")
    }
    
    @Test("Custom authentication header")
    func testCustomAuth() {
        let auth = DICOMwebConfiguration.Authentication.custom(
            headerName: "X-Custom-Header",
            headerValue: "custom-value"
        )
        let header = auth.authorizationHeader
        
        #expect(header.name == "X-Custom-Header")
        #expect(header.value == "custom-value")
    }
    
    // MARK: - Timeout Configuration Tests
    
    @Test("Default timeout configuration")
    func testDefaultTimeouts() {
        let timeouts = DICOMwebConfiguration.TimeoutConfiguration.default
        
        #expect(timeouts.connectTimeout == 30)
        #expect(timeouts.readTimeout == 60)
        #expect(timeouts.resourceTimeout == 300)
        #expect(timeouts.operationTimeout == 120)
    }
    
    @Test("Fast timeout configuration")
    func testFastTimeouts() {
        let timeouts = DICOMwebConfiguration.TimeoutConfiguration.fast
        
        #expect(timeouts.connectTimeout == 10)
        #expect(timeouts.readTimeout == 30)
        #expect(timeouts.resourceTimeout == 60)
    }
    
    @Test("Slow timeout configuration")
    func testSlowTimeouts() {
        let timeouts = DICOMwebConfiguration.TimeoutConfiguration.slow
        
        #expect(timeouts.connectTimeout == 60)
        #expect(timeouts.readTimeout == 300)
        #expect(timeouts.resourceTimeout == 1800)
    }
    
    // MARK: - Development Configuration
    
    @Test("Development configuration")
    func testDevelopmentConfig() {
        let config = DICOMwebConfiguration.development()
        
        #expect(config.baseURL.host == "localhost")
        #expect(config.baseURL.port == 8042)
        #expect(config.baseURL.path == "/dicom-web")
    }
    
    @Test("Development configuration with custom host")
    func testDevelopmentConfigCustom() {
        let config = DICOMwebConfiguration.development(host: "192.168.1.100", port: 8080, path: "/api")
        
        #expect(config.baseURL.host == "192.168.1.100")
        #expect(config.baseURL.port == 8080)
        #expect(config.baseURL.path == "/api")
    }
    
    // MARK: - Headers Tests
    
    @Test("Headers include user agent")
    func testHeadersUserAgent() {
        let config = DICOMwebConfiguration(baseURL: testURL)
        let headers = config.headers()
        
        #expect(headers["User-Agent"] == "DICOMKit/1.0")
    }
    
    @Test("Headers include accept types")
    func testHeadersAccept() {
        let config = DICOMwebConfiguration(
            baseURL: testURL,
            defaultAcceptTypes: [.dicomJSON, .dicom]
        )
        let headers = config.headers()
        
        #expect(headers["Accept"]?.contains("application/dicom+json") == true)
        #expect(headers["Accept"]?.contains("application/dicom") == true)
    }
    
    @Test("Headers include authentication")
    func testHeadersAuth() {
        let config = DICOMwebConfiguration(
            baseURL: testURL,
            authentication: .bearer(token: "test-token")
        )
        let headers = config.headers()
        
        #expect(headers["Authorization"] == "Bearer test-token")
    }
    
    @Test("Headers include content type")
    func testHeadersContentType() {
        let config = DICOMwebConfiguration(baseURL: testURL)
        let headers = config.headers(contentType: .dicomJSON)
        
        #expect(headers["Content-Type"] == "application/dicom+json")
    }
    
    @Test("Headers include custom headers")
    func testHeadersCustom() {
        let config = DICOMwebConfiguration(
            baseURL: testURL,
            customHeaders: ["X-Custom": "value"]
        )
        let headers = config.headers()
        
        #expect(headers["X-Custom"] == "value")
    }
    
    @Test("Additional headers override custom headers")
    func testHeadersOverride() {
        let config = DICOMwebConfiguration(
            baseURL: testURL,
            customHeaders: ["X-Custom": "original"]
        )
        let headers = config.headers(additionalHeaders: ["X-Custom": "overridden"])
        
        #expect(headers["X-Custom"] == "overridden")
    }
    
    // MARK: - URL Builder
    
    @Test("URL builder is available")
    func testURLBuilder() {
        let config = DICOMwebConfiguration(baseURL: testURL)
        let builder = config.urlBuilder
        
        #expect(builder.baseURL == testURL)
    }

    // MARK: - PS3.15 2026a Annex B TLS profile (P-STUDIO-TLS-PROFILES)

    @Test("TLSProfile raw values are the PS3.15 2026a B.12 / B.13 titles; default is nil")
    func tlsProfileValues() {
        #expect(DICOMwebConfiguration.TLSProfile.allCases.map(\.rawValue)
                == ["BCP 195 RFC 8996, 9325 TLS", "Modified BCP 195 RFC 8996, 9325 TLS"])
        #expect(DICOMwebConfiguration.TLSProfile.bcp195.section == "B.12")
        #expect(DICOMwebConfiguration.TLSProfile.modifiedBCP195.section == "B.13")
        for profile in DICOMwebConfiguration.TLSProfile.allCases { #expect(profile.minimumTLSVersion == "1.2") }
        #expect(DICOMwebConfiguration(baseURL: testURL).tlsProfile == nil)
        #expect(DICOMwebConfiguration(baseURL: testURL, tlsProfile: .modifiedBCP195).tlsProfile == .modifiedBCP195)
    }

    #if canImport(Darwin)
    @Test("A TLS profile sets the URLSession minimum to TLS 1.2 and leaves the maximum open")
    func tlsProfileAppliedToSession() {
        for profile in DICOMwebConfiguration.TLSProfile.allCases {
            let session = URLSessionConfiguration.ephemeral
            HTTPClient.applyTLSProfile(profile, to: session)
            #expect(session.tlsMinimumSupportedProtocolVersion == .TLSv12)
            #expect(session.tlsMaximumSupportedProtocolVersion == URLSessionConfiguration.ephemeral.tlsMaximumSupportedProtocolVersion)
        }
        let untouched = URLSessionConfiguration.ephemeral
        let before = untouched.tlsMinimumSupportedProtocolVersion
        HTTPClient.applyTLSProfile(nil, to: untouched)
        #expect(untouched.tlsMinimumSupportedProtocolVersion == before)
    }
    #endif
}
