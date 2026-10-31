import XCTest
@testable import DICOMWeb

/// Tests for DICOMweb capabilities
final class CapabilitiesTests: XCTestCase {
    
    // MARK: - DICOMwebCapabilities Tests
    
    func testDefaultCapabilities() {
        let capabilities = DICOMwebCapabilities()
        
        XCTAssertNil(capabilities.apiVersion)
        XCTAssertNil(capabilities.serverName)
        XCTAssertTrue(capabilities.services.wadoRS)
        XCTAssertTrue(capabilities.services.qidoRS)
        XCTAssertTrue(capabilities.services.stowRS)
        XCTAssertFalse(capabilities.services.upsRS)
        XCTAssertFalse(capabilities.services.delete)
    }
    
    func testDICOMKitServerCapabilities() {
        let capabilities = DICOMwebCapabilities.dicomKitServer
        
        XCTAssertEqual(capabilities.apiVersion, "1.0")
        XCTAssertEqual(capabilities.serverName, "DICOMKit")
        XCTAssertEqual(capabilities.serverVersion, "0.8.8")
        XCTAssertTrue(capabilities.services.wadoRS)
        XCTAssertTrue(capabilities.services.qidoRS)
        XCTAssertTrue(capabilities.services.stowRS)
        XCTAssertTrue(capabilities.services.upsRS)
        XCTAssertTrue(capabilities.services.delete)
        XCTAssertFalse(capabilities.services.rendered)
        XCTAssertFalse(capabilities.services.thumbnails)
        XCTAssertFalse(capabilities.services.bulkdata)
    }
    
    func testMinimalCapabilities() {
        let capabilities = DICOMwebCapabilities.minimal
        
        XCTAssertTrue(capabilities.services.wadoRS)
        XCTAssertTrue(capabilities.services.qidoRS)
        XCTAssertFalse(capabilities.services.stowRS)
        XCTAssertFalse(capabilities.services.upsRS)
        XCTAssertFalse(capabilities.services.delete)
    }
    
    func testSupportedServices() {
        let services = DICOMwebCapabilities.SupportedServices(
            wadoRS: true,
            qidoRS: true,
            stowRS: false,
            upsRS: true,
            delete: true,
            rendered: true,
            thumbnails: true,
            bulkdata: false
        )
        
        XCTAssertTrue(services.wadoRS)
        XCTAssertTrue(services.qidoRS)
        XCTAssertFalse(services.stowRS)
        XCTAssertTrue(services.upsRS)
        XCTAssertTrue(services.delete)
        XCTAssertTrue(services.rendered)
        XCTAssertTrue(services.thumbnails)
        XCTAssertFalse(services.bulkdata)
    }
    
    func testMediaTypeSupport() {
        let mediaTypes = DICOMwebCapabilities.MediaTypeSupport()
        
        XCTAssertTrue(mediaTypes.retrieve.contains("application/dicom"))
        XCTAssertTrue(mediaTypes.retrieve.contains("application/dicom+json"))
        XCTAssertTrue(mediaTypes.store.contains("application/dicom"))
        XCTAssertTrue(mediaTypes.rendered.contains("image/jpeg"))
        XCTAssertTrue(mediaTypes.rendered.contains("image/png"))
    }
    
    func testQueryCapabilities() {
        let query = DICOMwebCapabilities.QueryCapabilities(
            maxResults: 1000,
            fuzzyMatching: true,
            wildcardMatching: true,
            dateRangeQueries: true,
            includeFieldAll: true,
            queryLevels: [.study, .series]
        )
        
        XCTAssertEqual(query.maxResults, 1000)
        XCTAssertTrue(query.fuzzyMatching)
        XCTAssertTrue(query.wildcardMatching)
        XCTAssertTrue(query.dateRangeQueries)
        XCTAssertTrue(query.includeFieldAll)
        XCTAssertEqual(query.queryLevels.count, 2)
    }
    
    func testStoreCapabilities() {
        let store = DICOMwebCapabilities.StoreCapabilities(
            maxRequestSize: 500 * 1024 * 1024,
            maxInstancesPerRequest: 100,
            supportedSOPClasses: ["1.2.840.10008.5.1.4.1.1.2"],
            partialSuccess: true
        )
        
        XCTAssertEqual(store.maxRequestSize, 500 * 1024 * 1024)
        XCTAssertEqual(store.maxInstancesPerRequest, 100)
        XCTAssertEqual(store.supportedSOPClasses, ["1.2.840.10008.5.1.4.1.1.2"])
        XCTAssertTrue(store.partialSuccess)
    }
    
    func testAuthenticationMethods() {
        let methods: [DICOMwebCapabilities.AuthenticationMethod] = [
            .none, .basic, .bearer, .apiKey, .oauth2, .clientCertificate
        ]
        
        XCTAssertEqual(methods.map { $0.rawValue }, [
            "none", "basic", "bearer", "apiKey", "oauth2", "clientCertificate"
        ])
    }
    
    func testCapabilitiesToJSON() {
        let capabilities = DICOMwebCapabilities(
            apiVersion: "1.0",
            serverName: "TestServer",
            services: DICOMwebCapabilities.SupportedServices(wadoRS: true, qidoRS: true, stowRS: false)
        )
        
        let json = capabilities.toJSONDictionary()
        
        XCTAssertEqual(json["apiVersion"] as? String, "1.0")
        XCTAssertEqual(json["serverName"] as? String, "TestServer")
        
        let services = json["services"] as? [String: Bool]
        XCTAssertNotNil(services)
        XCTAssertEqual(services?["wado-rs"], true)
        XCTAssertEqual(services?["qido-rs"], true)
        XCTAssertEqual(services?["stow-rs"], false)
    }
    
    func testCapabilitiesCodable() throws {
        let original = DICOMwebCapabilities(
            apiVersion: "1.0",
            serverName: "TestServer",
            serverVersion: "1.2.3",
            services: DICOMwebCapabilities.SupportedServices(wadoRS: true, qidoRS: false),
            queryCapabilities: DICOMwebCapabilities.QueryCapabilities(maxResults: 500)
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DICOMwebCapabilities.self, from: data)
        
        XCTAssertEqual(decoded.apiVersion, original.apiVersion)
        XCTAssertEqual(decoded.serverName, original.serverName)
        XCTAssertEqual(decoded.serverVersion, original.serverVersion)
        XCTAssertEqual(decoded.services.wadoRS, original.services.wadoRS)
        XCTAssertEqual(decoded.services.qidoRS, original.services.qidoRS)
        XCTAssertEqual(decoded.queryCapabilities.maxResults, original.queryCapabilities.maxResults)
    }
}
