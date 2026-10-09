import Testing
import Foundation
@testable import DICOMWeb
@testable import DICOMKit
@testable import DICOMCore

// MARK: - DICOMweb Server Configuration Tests

@Suite("DICOMweb Server Configuration Tests")
struct DICOMwebServerConfigurationTests {
    
    @Test("Default configuration values")
    func testDefaultConfiguration() {
        let config = DICOMwebServerConfiguration()
        
        #expect(config.port == 8042)
        #expect(config.host == "0.0.0.0")
        #expect(config.pathPrefix == "/dicom-web")
        #expect(config.maxRequestBodySize == 500 * 1024 * 1024)
        #expect(config.maxConcurrentRequests == 100)
        #expect(config.serverName == "DICOMKit/1.0")
        #expect(config.tlsConfiguration == nil)
        #expect(config.corsConfiguration == nil)
        #expect(config.rateLimitConfiguration == nil)
    }
    
    @Test("Custom configuration values")
    func testCustomConfiguration() {
        let config = DICOMwebServerConfiguration(
            port: 8080,
            host: "127.0.0.1",
            pathPrefix: "/api/dicom",
            maxRequestBodySize: 100 * 1024 * 1024,
            maxConcurrentRequests: 50,
            serverName: "TestServer/1.0"
        )
        
        #expect(config.port == 8080)
        #expect(config.host == "127.0.0.1")
        #expect(config.pathPrefix == "/api/dicom")
        #expect(config.maxRequestBodySize == 100 * 1024 * 1024)
        #expect(config.maxConcurrentRequests == 50)
        #expect(config.serverName == "TestServer/1.0")
    }
    
    @Test("Base URL generation without TLS")
    func testBaseURLWithoutTLS() {
        let config = DICOMwebServerConfiguration(port: 8042, host: "localhost")
        #expect(config.baseURL.absoluteString == "http://localhost:8042/dicom-web")
    }
    
    @Test("Base URL generation with TLS")
    func testBaseURLWithTLS() {
        let tlsConfig = DICOMwebServerConfiguration.TLSConfiguration(
            certificatePath: "/path/to/cert.pem",
            privateKeyPath: "/path/to/key.pem"
        )
        let config = DICOMwebServerConfiguration(
            port: 443,
            host: "localhost",
            tlsConfiguration: tlsConfig
        )
        #expect(config.baseURL.absoluteString == "https://localhost:443/dicom-web")
    }
    
    @Test("Base URL with 0.0.0.0 replaces with localhost")
    func testBaseURLWith0000() {
        let config = DICOMwebServerConfiguration(port: 8042, host: "0.0.0.0")
        #expect(config.baseURL.absoluteString == "http://localhost:8042/dicom-web")
    }
    
    @Test("Development preset configuration")
    func testDevelopmentPreset() {
        let config = DICOMwebServerConfiguration.development
        
        #expect(config.port == 8042)
        #expect(config.host == "127.0.0.1")
        #expect(config.corsConfiguration != nil)
    }
    
    @Test("CORS configuration allow all")
    func testCORSAllowAll() {
        let cors = DICOMwebServerConfiguration.CORSConfiguration.allowAll
        
        #expect(cors.allowedOrigins == ["*"])
        #expect(cors.allowedMethods.contains("GET"))
        #expect(cors.allowedMethods.contains("POST"))
        #expect(cors.allowedHeaders.contains("Content-Type"))
        #expect(cors.exposedHeaders.contains("X-Total-Count"))
    }
    
    @Test("Rate limit configuration")
    func testRateLimitConfiguration() {
        let rateLimit = DICOMwebServerConfiguration.RateLimitConfiguration(
            maxRequests: 500,
            windowSeconds: 30,
            limitBy: .apiKey
        )
        
        #expect(rateLimit.maxRequests == 500)
        #expect(rateLimit.windowSeconds == 30)
        if case .apiKey = rateLimit.limitBy {
            // Expected
        } else {
            Issue.record("Expected apiKey limit type")
        }
    }
}

// MARK: - DICOMweb Router Tests

@Suite("DICOMweb Router Tests")
struct DICOMwebRouterTests {
    
    let router = DICOMwebRouter(pathPrefix: "/dicom-web")
    
    @Test("Match search studies route")
    func testMatchSearchStudies() {
        let match = router.match(path: "/dicom-web/studies", method: .get)
        
        #expect(match != nil)
        #expect(match?.handlerType == .searchStudies)
        #expect(match?.parameters.isEmpty == true)
    }
    
    @Test("Match retrieve study route")
    func testMatchRetrieveStudy() {
        let match = router.match(path: "/dicom-web/studies/1.2.3.4.5", method: .get)
        
        #expect(match != nil)
        #expect(match?.handlerType == .retrieveStudy)
        #expect(match?.parameters["studyUID"] == "1.2.3.4.5")
    }
    
    @Test("Match retrieve series route")
    func testMatchRetrieveSeries() {
        let match = router.match(path: "/dicom-web/studies/1.2.3/series/4.5.6", method: .get)
        
        #expect(match != nil)
        #expect(match?.handlerType == .retrieveSeries)
        #expect(match?.parameters["studyUID"] == "1.2.3")
        #expect(match?.parameters["seriesUID"] == "4.5.6")
    }
    
    @Test("Match retrieve instance route")
    func testMatchRetrieveInstance() {
        let match = router.match(path: "/dicom-web/studies/1.2.3/series/4.5.6/instances/7.8.9", method: .get)
        
        #expect(match != nil)
        #expect(match?.handlerType == .retrieveInstance)
        #expect(match?.parameters["studyUID"] == "1.2.3")
        #expect(match?.parameters["seriesUID"] == "4.5.6")
        #expect(match?.parameters["instanceUID"] == "7.8.9")
    }
    
    @Test("Match study metadata route")
    func testMatchStudyMetadata() {
        let match = router.match(path: "/dicom-web/studies/1.2.3/metadata", method: .get)
        
        #expect(match != nil)
        #expect(match?.handlerType == .retrieveStudyMetadata)
        #expect(match?.parameters["studyUID"] == "1.2.3")
    }
    
    @Test("Match search series in study route")
    func testMatchSearchSeriesInStudy() {
        let match = router.match(path: "/dicom-web/studies/1.2.3/series", method: .get)
        
        #expect(match != nil)
        #expect(match?.handlerType == .searchSeriesInStudy)
        #expect(match?.parameters["studyUID"] == "1.2.3")
    }
    
    @Test("Match delete study route")
    func testMatchDeleteStudy() {
        let match = router.match(path: "/dicom-web/studies/1.2.3", method: .delete)
        
        #expect(match != nil)
        #expect(match?.handlerType == .deleteStudy)
        #expect(match?.parameters["studyUID"] == "1.2.3")
    }
    
    @Test("Match STOW-RS store route")
    func testMatchStoreInstances() {
        let match = router.match(path: "/dicom-web/studies", method: .post)
        
        #expect(match != nil)
        #expect(match?.handlerType == .storeInstances)
    }
    
    @Test("No match for unknown path")
    func testNoMatchUnknownPath() {
        let match = router.match(path: "/dicom-web/unknown", method: .get)
        #expect(match == nil)
    }
    
    @Test("No match for wrong prefix")
    func testNoMatchWrongPrefix() {
        let match = router.match(path: "/api/studies", method: .get)
        #expect(match == nil)
    }
    
    @Test("Match frames route")
    func testMatchFramesRoute() {
        let match = router.match(path: "/dicom-web/studies/1.2.3/series/4.5.6/instances/7.8.9/frames/1,2,3", method: .get)
        
        #expect(match != nil)
        #expect(match?.handlerType == .retrieveFrames)
        #expect(match?.parameters["frames"] == "1,2,3")
    }
}

// MARK: - DICOMweb Request/Response Tests

@Suite("DICOMweb Request Tests")
struct DICOMwebRequestTests {
    
    @Test("Request header lookup is case-insensitive")
    func testHeaderCaseInsensitive() {
        let request = DICOMwebRequest(
            method: .get,
            path: "/studies",
            headers: ["Content-Type": "application/json"]
        )
        
        #expect(request.header("content-type") == "application/json")
        #expect(request.header("CONTENT-TYPE") == "application/json")
        #expect(request.header("Content-Type") == "application/json")
    }
    
    @Test("Request parses Accept header")
    func testAcceptTypes() {
        let request = DICOMwebRequest(
            method: .get,
            path: "/studies",
            headers: ["Accept": "application/dicom+json, application/json"]
        )
        
        #expect(request.acceptTypes.count == 2)
    }
    
    @Test("Request parses Content-Type")
    func testContentType() {
        let request = DICOMwebRequest(
            method: .post,
            path: "/studies",
            headers: ["Content-Type": "multipart/related; boundary=myboundary"]
        )
        
        #expect(request.contentType != nil)
        #expect(request.contentType?.parameters["boundary"] == "myboundary")
    }
}

@Suite("DICOMweb Response Tests")
struct DICOMwebResponseTests {
    
    @Test("OK JSON response")
    func testOKJSONResponse() {
        let json = "{\"test\": true}".data(using: .utf8)!
        let response = DICOMwebResponse.ok(json: json)
        
        #expect(response.statusCode == 200)
        #expect(response.headers["Content-Type"] == "application/dicom+json")
        #expect(response.headers["Content-Length"] == "\(json.count)")
    }
    
    @Test("Not found response")
    func testNotFoundResponse() {
        let response = DICOMwebResponse.notFound(message: "Study not found")
        
        #expect(response.statusCode == 404)
        #expect(response.headers["Content-Type"] == "application/json")
    }
    
    @Test("Bad request response")
    func testBadRequestResponse() {
        let response = DICOMwebResponse.badRequest(message: "Invalid parameter")
        
        #expect(response.statusCode == 400)
    }
    
    @Test("No content response")
    func testNoContentResponse() {
        let response = DICOMwebResponse.noContent()
        
        #expect(response.statusCode == 204)
        #expect(response.body == nil)
    }
}

// MARK: - In-Memory Storage Provider Tests

@Suite("InMemory Storage Provider Tests")
struct InMemoryStorageProviderTests {
    
    @Test("Empty provider has no studies")
    func testEmptyProvider() async throws {
        let storage = InMemoryStorageProvider()
        let studies = try await storage.searchStudies(query: StorageQuery())
        #expect(studies.isEmpty)
        #expect(await storage.studyCount == 0)
    }
    
    @Test("Store and retrieve instance")
    func testStoreAndRetrieve() async throws {
        let storage = InMemoryStorageProvider()
        let testData = Data("test dicom data".utf8)
        
        try await storage.storeInstance(
            data: testData,
            studyUID: "1.2.3",
            seriesUID: "1.2.3.4",
            instanceUID: "1.2.3.4.5"
        )
        
        let retrieved = try await storage.getInstance(
            studyUID: "1.2.3",
            seriesUID: "1.2.3.4",
            instanceUID: "1.2.3.4.5"
        )
        
        #expect(retrieved == testData)
        #expect(await storage.studyCount == 1)
        #expect(await storage.instanceCount == 1)
    }
    
    @Test("Delete instance")
    func testDeleteInstance() async throws {
        let storage = InMemoryStorageProvider()
        let testData = Data("test data".utf8)
        
        try await storage.storeInstance(
            data: testData,
            studyUID: "1.2.3",
            seriesUID: "1.2.3.4",
            instanceUID: "1.2.3.4.5"
        )
        
        let deleted = try await storage.deleteInstance(
            studyUID: "1.2.3",
            seriesUID: "1.2.3.4",
            instanceUID: "1.2.3.4.5"
        )
        
        #expect(deleted == true)
        #expect(await storage.instanceCount == 0)
    }
    
    @Test("Delete non-existent instance returns false")
    func testDeleteNonExistent() async throws {
        let storage = InMemoryStorageProvider()
        
        let deleted = try await storage.deleteInstance(
            studyUID: "1.2.3",
            seriesUID: "1.2.3.4",
            instanceUID: "1.2.3.4.5"
        )
        
        #expect(deleted == false)
    }
    
    @Test("Get series instances")
    func testGetSeriesInstances() async throws {
        let storage = InMemoryStorageProvider()
        
        // Store multiple instances in the same series
        try await storage.storeInstance(
            data: Data("data1".utf8),
            studyUID: "1.2.3",
            seriesUID: "1.2.3.4",
            instanceUID: "1.2.3.4.1"
        )
        try await storage.storeInstance(
            data: Data("data2".utf8),
            studyUID: "1.2.3",
            seriesUID: "1.2.3.4",
            instanceUID: "1.2.3.4.2"
        )
        
        let instances = try await storage.getSeriesInstances(
            studyUID: "1.2.3",
            seriesUID: "1.2.3.4"
        )
        
        #expect(instances.count == 2)
    }
    
    @Test("Count series in study")
    func testCountSeries() async throws {
        let storage = InMemoryStorageProvider()
        
        try await storage.storeInstance(
            data: Data("data1".utf8),
            studyUID: "1.2.3",
            seriesUID: "1.2.3.1",
            instanceUID: "1.2.3.1.1"
        )
        try await storage.storeInstance(
            data: Data("data2".utf8),
            studyUID: "1.2.3",
            seriesUID: "1.2.3.2",
            instanceUID: "1.2.3.2.1"
        )
        
        let count = try await storage.countSeries(studyUID: "1.2.3")
        #expect(count == 2)
    }
    
    @Test("Search studies with query")
    func testSearchStudies() async throws {
        let storage = InMemoryStorageProvider()
        
        try await storage.storeInstance(
            data: Data("data1".utf8),
            studyUID: "1.2.3",
            seriesUID: "1.2.3.4",
            instanceUID: "1.2.3.4.5"
        )
        try await storage.storeInstance(
            data: Data("data2".utf8),
            studyUID: "2.3.4",
            seriesUID: "2.3.4.5",
            instanceUID: "2.3.4.5.6"
        )
        
        // Search for specific study
        let query = StorageQuery(studyInstanceUID: "1.2.3")
        let results = try await storage.searchStudies(query: query)
        
        #expect(results.count == 1)
        #expect(results.first?.studyInstanceUID == "1.2.3")
    }
    
    @Test("Pagination in search")
    func testPagination() async throws {
        let storage = InMemoryStorageProvider()
        
        // Store 5 instances in different studies
        for i in 1...5 {
            try await storage.storeInstance(
                data: Data("data\(i)".utf8),
                studyUID: "1.2.\(i)",
                seriesUID: "1.2.\(i).1",
                instanceUID: "1.2.\(i).1.1"
            )
        }
        
        // Get first 2
        var query = StorageQuery(offset: 0, limit: 2)
        var results = try await storage.searchStudies(query: query)
        #expect(results.count == 2)
        
        // Get next 2
        query = StorageQuery(offset: 2, limit: 2)
        results = try await storage.searchStudies(query: query)
        #expect(results.count == 2)
        
        // Get last 1
        query = StorageQuery(offset: 4, limit: 2)
        results = try await storage.searchStudies(query: query)
        #expect(results.count == 1)
    }
}

// MARK: - DICOMweb Server Tests

@Suite("DICOMweb Server Tests")
struct DICOMwebServerTests {
    
    @Test("Server initialization")
    func testServerInit() async throws {
        let storage = InMemoryStorageProvider()
        let server = DICOMwebServer(storage: storage)
        
        #expect(await server.port == 8042)
        #expect(await server.running == false)
    }
    
    @Test("Server start and stop")
    func testStartStop() async throws {
        let storage = InMemoryStorageProvider()
        let server = DICOMwebServer(storage: storage)
        
        try await server.start()
        #expect(await server.running == true)
        
        await server.stop()
        #expect(await server.running == false)
    }
    
    @Test("Handle unknown route returns 404")
    func testUnknownRoute() async throws {
        let storage = InMemoryStorageProvider()
        let server = DICOMwebServer(storage: storage)
        
        let request = DICOMwebRequest(method: .get, path: "/unknown")
        let response = await server.handleRequest(request)
        
        #expect(response.statusCode == 404)
    }
    
    @Test("Handle CORS preflight")
    func testCORSPreflight() async throws {
        let config = DICOMwebServerConfiguration(corsConfiguration: .allowAll)
        let storage = InMemoryStorageProvider()
        let server = DICOMwebServer(configuration: config, storage: storage)
        
        let request = DICOMwebRequest(
            method: .options,
            path: "/dicom-web/studies",
            headers: ["Origin": "http://localhost:3000"]
        )
        let response = await server.handleRequest(request)
        
        #expect(response.statusCode == 204)
        #expect(response.headers["Access-Control-Allow-Origin"] != nil)
    }
    
    @Test("Search studies returns empty array when no data")
    func testSearchStudiesEmpty() async throws {
        let storage = InMemoryStorageProvider()
        let server = DICOMwebServer(storage: storage)
        
        let request = DICOMwebRequest(method: .get, path: "/dicom-web/studies")
        let response = await server.handleRequest(request)
        
        #expect(response.statusCode == 200)
        #expect(response.headers["X-Total-Count"] == "0")
    }
    
    @Test("Retrieve non-existent study returns 404")
    func testRetrieveNonExistentStudy() async throws {
        let storage = InMemoryStorageProvider()
        let server = DICOMwebServer(storage: storage)
        
        let request = DICOMwebRequest(
            method: .get,
            path: "/dicom-web/studies/1.2.3.4.5"
        )
        let response = await server.handleRequest(request)
        
        #expect(response.statusCode == 404)
    }
    
    @Test("Delete non-existent study returns 404")
    func testDeleteNonExistentStudy() async throws {
        let storage = InMemoryStorageProvider()
        let server = DICOMwebServer(storage: storage)
        
        let request = DICOMwebRequest(
            method: .delete,
            path: "/dicom-web/studies/1.2.3.4.5"
        )
        let response = await server.handleRequest(request)
        
        #expect(response.statusCode == 404)
    }
    
    @Test("Soft delete instance")
    func testSoftDeleteInstance() async throws {
        // Create storage with a test instance
        let testData = Data([1, 2, 3, 4])
        let studyUID = "1.2.3.4"
        let seriesUID = "1.2.3.4.5"
        let instanceUID = "1.2.3.4.5.6"
        
        let storage = await InMemoryStorageProvider(instances: [
            (studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID, data: testData)
        ])
        
        // Soft delete the instance
        let deleted = try await storage.deleteInstance(
            studyUID: studyUID,
            seriesUID: seriesUID,
            instanceUID: instanceUID,
            mode: .soft
        )
        
        #expect(deleted == true, "Instance should be soft-deleted")
        
        // Instance should not be retrievable after soft delete
        let retrieved = try await storage.getInstance(
            studyUID: studyUID,
            seriesUID: seriesUID,
            instanceUID: instanceUID
        )
        #expect(retrieved == nil, "Soft-deleted instance should not be retrievable")
    }
    
    @Test("Permanent delete instance")
    func testPermanentDeleteInstance() async throws {
        // Create storage with a test instance
        let testData = Data([1, 2, 3, 4])
        let studyUID = "1.2.3.4"
        let seriesUID = "1.2.3.4.5"
        let instanceUID = "1.2.3.4.5.6"
        
        let storage = await InMemoryStorageProvider(instances: [
            (studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID, data: testData)
        ])
        
        // Permanently delete the instance
        let deleted = try await storage.deleteInstance(
            studyUID: studyUID,
            seriesUID: seriesUID,
            instanceUID: instanceUID,
            mode: .permanent
        )
        
        #expect(deleted == true, "Instance should be permanently deleted")
        
        // Instance should not be retrievable after permanent delete
        let retrieved = try await storage.getInstance(
            studyUID: studyUID,
            seriesUID: seriesUID,
            instanceUID: instanceUID
        )
        #expect(retrieved == nil, "Permanently deleted instance should not be retrievable")
    }
    
    @Test("Soft delete then permanent delete")
    func testSoftThenPermanentDelete() async throws {
        // Create storage with a test instance
        let testData = Data([1, 2, 3, 4])
        let studyUID = "1.2.3.4"
        let seriesUID = "1.2.3.4.5"
        let instanceUID = "1.2.3.4.5.6"
        
        let storage = await InMemoryStorageProvider(instances: [
            (studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID, data: testData)
        ])
        
        // Soft delete first
        _ = try await storage.deleteInstance(
            studyUID: studyUID,
            seriesUID: seriesUID,
            instanceUID: instanceUID,
            mode: .soft
        )
        
        // Then permanently delete
        let deleted = try await storage.deleteInstance(
            studyUID: studyUID,
            seriesUID: seriesUID,
            instanceUID: instanceUID,
            mode: .permanent
        )
        
        #expect(deleted == true, "Instance should be permanently deleted after soft delete")
        
        // Instance should not exist anymore
        let retrieved = try await storage.getInstance(
            studyUID: studyUID,
            seriesUID: seriesUID,
            instanceUID: instanceUID
        )
        #expect(retrieved == nil, "Instance should not exist after permanent delete")
    }
    
    @Test("Soft delete series")
    func testSoftDeleteSeries() async throws {
        // Create storage with multiple instances in a series
        let studyUID = "1.2.3.4"
        let seriesUID = "1.2.3.4.5"
        
        let storage = await InMemoryStorageProvider(instances: [
            (studyUID: studyUID, seriesUID: seriesUID, instanceUID: "1.2.3.4.5.1", data: Data([1])),
            (studyUID: studyUID, seriesUID: seriesUID, instanceUID: "1.2.3.4.5.2", data: Data([2])),
            (studyUID: studyUID, seriesUID: seriesUID, instanceUID: "1.2.3.4.5.3", data: Data([3]))
        ])
        
        // Soft delete the series
        let deleted = try await storage.deleteSeries(
            studyUID: studyUID,
            seriesUID: seriesUID,
            mode: .soft
        )
        
        #expect(deleted == 3, "All 3 instances should be soft-deleted")
        
        // No instances should be retrievable
        let instances = try await storage.getSeriesInstances(studyUID: studyUID, seriesUID: seriesUID)
        #expect(instances.isEmpty, "Soft-deleted series should return no instances")
    }
    
    @Test("Soft delete study")
    func testSoftDeleteStudy() async throws {
        // Create storage with multiple series in a study
        let studyUID = "1.2.3.4"
        
        let storage = await InMemoryStorageProvider(instances: [
            (studyUID: studyUID, seriesUID: "1.2.3.4.1", instanceUID: "1.2.3.4.1.1", data: Data([1])),
            (studyUID: studyUID, seriesUID: "1.2.3.4.1", instanceUID: "1.2.3.4.1.2", data: Data([2])),
            (studyUID: studyUID, seriesUID: "1.2.3.4.2", instanceUID: "1.2.3.4.2.1", data: Data([3])),
            (studyUID: studyUID, seriesUID: "1.2.3.4.2", instanceUID: "1.2.3.4.2.2", data: Data([4]))
        ])
        
        // Soft delete the study
        let deleted = try await storage.deleteStudy(studyUID: studyUID, mode: .soft)
        
        #expect(deleted == 4, "All 4 instances should be soft-deleted")
        
        // No instances should be retrievable
        let instances = try await storage.getStudyInstances(studyUID: studyUID)
        #expect(instances.isEmpty, "Soft-deleted study should return no instances")
    }
    
    @Test("Soft delete via HTTP DELETE with query parameter")
    func testSoftDeleteViaHTTP() async throws {
        // Create storage with a test instance
        let testData = Data([1, 2, 3, 4])
        let studyUID = "1.2.3.4"
        let seriesUID = "1.2.3.4.5"
        let instanceUID = "1.2.3.4.5.6"
        
        let storage = await InMemoryStorageProvider(instances: [
            (studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID, data: testData)
        ])
        let server = DICOMwebServer(storage: storage)
        
        // Delete with mode=soft query parameter
        let request = DICOMwebRequest(
            method: .delete,
            path: "/dicom-web/studies/\(studyUID)/series/\(seriesUID)/instances/\(instanceUID)?mode=soft"
        )
        let response = await server.handleRequest(request)
        
        #expect(response.statusCode == 204, "Soft delete should succeed with 204 No Content")
        
        // Verify instance is soft-deleted (not retrievable)
        let retrieved = try await storage.getInstance(
            studyUID: studyUID,
            seriesUID: seriesUID,
            instanceUID: instanceUID
        )
        #expect(retrieved == nil, "Soft-deleted instance should not be retrievable via API")
    }
}

// MARK: - Storage Query Tests

@Suite("Storage Query Tests")
struct StorageQueryTests {
    
    @Test("Default query values")
    func testDefaultQuery() {
        let query = StorageQuery()
        
        #expect(query.offset == 0)
        #expect(query.limit == 100)
        #expect(query.fuzzyMatching == false)
        #expect(query.patientName == nil)
        #expect(query.studyInstanceUID == nil)
    }
    
    @Test("Query with parameters")
    func testQueryWithParameters() {
        let query = StorageQuery(
            patientName: "DOE^JOHN",
            patientID: "12345",
            modality: "CT",
            offset: 10,
            limit: 25,
            fuzzyMatching: true
        )
        
        #expect(query.patientName == "DOE^JOHN")
        #expect(query.patientID == "12345")
        #expect(query.modality == "CT")
        #expect(query.offset == 10)
        #expect(query.limit == 25)
        #expect(query.fuzzyMatching == true)
    }
    
    @Test("Date range query")
    func testDateRange() {
        let startDate = Date()
        let endDate = Date().addingTimeInterval(86400)
        
        let dateRange = StorageQuery.DateRange(start: startDate, end: endDate)
        let query = StorageQuery(studyDate: dateRange)
        
        #expect(query.studyDate?.start == startDate)
        #expect(query.studyDate?.end == endDate)
    }
}

// MARK: - STOW-RS Configuration Tests

@Suite("STOW-RS Configuration Tests")
struct STOWConfigurationTests {
    
    @Test("Default STOW configuration")
    func testDefaultConfiguration() {
        let config = DICOMwebServerConfiguration.STOWConfiguration.default
        
        #expect(config.validateRequiredAttributes == true)
        #expect(config.validateSOPClasses == false)
        #expect(config.validateUIDFormat == true)
        #expect(config.allowedSOPClasses.isEmpty)
        #expect(config.additionalRequiredTags.isEmpty)
        if case .replace = config.duplicatePolicy {
            // Expected
        } else {
            Issue.record("Expected replace duplicate policy")
        }
    }
    
    @Test("Strict STOW configuration")
    func testStrictConfiguration() {
        let config = DICOMwebServerConfiguration.STOWConfiguration.strict
        
        #expect(config.validateRequiredAttributes == true)
        #expect(config.validateSOPClasses == true)
        #expect(config.validateUIDFormat == true)
        if case .reject = config.duplicatePolicy {
            // Expected
        } else {
            Issue.record("Expected reject duplicate policy")
        }
    }
    
    @Test("Permissive STOW configuration")
    func testPermissiveConfiguration() {
        let config = DICOMwebServerConfiguration.STOWConfiguration.permissive
        
        #expect(config.validateRequiredAttributes == false)
        #expect(config.validateSOPClasses == false)
        #expect(config.validateUIDFormat == false)
        if case .accept = config.duplicatePolicy {
            // Expected
        } else {
            Issue.record("Expected accept duplicate policy")
        }
    }
    
    @Test("Custom STOW configuration with allowed SOP classes")
    func testCustomConfiguration() {
        let ctSOPClass = "1.2.840.10008.5.1.4.1.1.2"
        let mrSOPClass = "1.2.840.10008.5.1.4.1.1.4"
        
        let config = DICOMwebServerConfiguration.STOWConfiguration(
            duplicatePolicy: .reject,
            validateRequiredAttributes: true,
            validateSOPClasses: true,
            allowedSOPClasses: [ctSOPClass, mrSOPClass],
            validateUIDFormat: true,
            additionalRequiredTags: [0x00100010, 0x00100020] // Patient Name, Patient ID
        )
        
        #expect(config.allowedSOPClasses.count == 2)
        #expect(config.allowedSOPClasses.contains(ctSOPClass))
        #expect(config.allowedSOPClasses.contains(mrSOPClass))
        #expect(config.additionalRequiredTags.count == 2)
    }
    
    @Test("Server configuration includes STOW config")
    func testServerConfigWithSTOW() {
        let stowConfig = DICOMwebServerConfiguration.STOWConfiguration.strict
        let serverConfig = DICOMwebServerConfiguration(
            port: 8080,
            stowConfiguration: stowConfig
        )
        
        #expect(serverConfig.port == 8080)
        if case .reject = serverConfig.stowConfiguration.duplicatePolicy {
            // Expected
        } else {
            Issue.record("Expected reject duplicate policy")
        }
    }
}

// MARK: - STOW-RS Server Handler Tests

@Suite("STOW-RS Server Handler Tests")
struct STOWRSServerHandlerTests {
    
    @Test("STOW-RS rejects empty request body")
    func testRejectsEmptyBody() async throws {
        let storage = InMemoryStorageProvider()
        let server = DICOMwebServer(storage: storage)
        
        let request = DICOMwebRequest(
            method: .post,
            path: "/dicom-web/studies",
            headers: ["Content-Type": "multipart/related; boundary=testboundary"],
            body: nil
        )
        
        let response = await server.handleRequest(request)
        #expect(response.statusCode == 400)
    }
    
    @Test("STOW-RS rejects missing content type")
    func testRejectsMissingContentType() async throws {
        let storage = InMemoryStorageProvider()
        let server = DICOMwebServer(storage: storage)
        
        let request = DICOMwebRequest(
            method: .post,
            path: "/dicom-web/studies",
            headers: [:],
            body: Data("test".utf8)
        )
        
        let response = await server.handleRequest(request)
        #expect(response.statusCode == 415)
    }
    
    @Test("STOW-RS rejects unsupported content type")
    func testRejectsUnsupportedContentType() async throws {
        let storage = InMemoryStorageProvider()
        let server = DICOMwebServer(storage: storage)
        
        let request = DICOMwebRequest(
            method: .post,
            path: "/dicom-web/studies",
            headers: ["Content-Type": "application/json"],
            body: Data("{}".utf8)
        )
        
        let response = await server.handleRequest(request)
        #expect(response.statusCode == 415)
    }
    
    @Test("STOW-RS rejects multipart without boundary")
    func testRejectsMultipartWithoutBoundary() async throws {
        let storage = InMemoryStorageProvider()
        let server = DICOMwebServer(storage: storage)
        
        let request = DICOMwebRequest(
            method: .post,
            path: "/dicom-web/studies",
            headers: ["Content-Type": "multipart/related"],
            body: Data("test".utf8)
        )
        
        let response = await server.handleRequest(request)
        #expect(response.statusCode == 400)
    }
    
    @Test("STOW-RS accepts application/dicom content type")
    func testAcceptsSingleDicomContentType() async throws {
        let storage = InMemoryStorageProvider()
        let server = DICOMwebServer(storage: storage)
        
        // Note: This will fail validation since it's not valid DICOM, but
        // it should not fail due to content type
        let request = DICOMwebRequest(
            method: .post,
            path: "/dicom-web/studies",
            headers: ["Content-Type": "application/dicom"],
            body: Data("not valid dicom".utf8)
        )
        
        let response = await server.handleRequest(request)
        // PS3.18 Table 10.5.3-1: 409 when no Instance could be stored (cannot understand), not 415
        #expect(response.statusCode == 409)
    }
    
    @Test("STOW-RS request size limit")
    func testRequestSizeLimit() async throws {
        let config = DICOMwebServerConfiguration(
            maxRequestBodySize: 100  // 100 bytes limit
        )
        let storage = InMemoryStorageProvider()
        let server = DICOMwebServer(configuration: config, storage: storage)
        
        // Create request larger than limit
        let largeData = Data(repeating: 0, count: 200)
        let request = DICOMwebRequest(
            method: .post,
            path: "/dicom-web/studies",
            headers: ["Content-Type": "application/dicom"],
            body: largeData
        )
        
        let response = await server.handleRequest(request)
        #expect(response.statusCode == 413)
    }
}

// MARK: - STOW Delegate Tests

@Suite("STOW Delegate Tests")
struct STOWDelegateTests {
    
    @Test("Store delegate default implementations exist")
    func testDefaultImplementations() async throws {
        // This test verifies that default implementations exist and don't crash
        // We can't easily test the full delegate behavior without creating a proper DICOM file
        let storage = InMemoryStorageProvider()
        let server = DICOMwebServer(storage: storage)
        
        // Server should work without a delegate
        #expect(await server.running == false)
    }
}


// MARK: - UPS-RS Server Handler Tests

@Suite("UPS-RS Server Handler Tests")
struct UPSRSServerHandlerTests {
    
    @Test("Search workitems returns empty when no UPS storage configured")
    func testSearchWithoutUPSStorage() async throws {
        let storage = InMemoryStorageProvider()
        let server = DICOMwebServer(storage: storage)
        
        let request = DICOMwebRequest(
            method: .get,
            path: "/dicom-web/workitems",
            queryParameters: [:]
        )
        
        let response = await server.handleRequest(request)
        #expect(response.statusCode == 501)
    }
    
    @Test("Search workitems returns results")
    func testSearchWorkitems() async throws {
        let storage = InMemoryStorageProvider()
        let upsStorage = InMemoryUPSStorageProvider()
        let server = DICOMwebServer(configuration: .development, storage: storage, upsStorage: upsStorage)
        
        // Create test workitems
        let workitem1 = Workitem(
            workitemUID: "1.2.3.4.5",
            scheduledStartDateTime: Date(),
            patientName: "Smith^John",
            patientID: "PAT001",
            procedureStepLabel: "CT Scan"
        )
        try await upsStorage.createWorkitem(workitem1)
        
        let request = DICOMwebRequest(
            method: .get,
            path: "/dicom-web/workitems",
            queryParameters: [:]
        )
        
        let response = await server.handleRequest(request)
        #expect(response.statusCode == 200)
        #expect(response.headers["X-Total-Count"] == "1")
        #expect(response.headers["Content-Type"]?.contains("application/dicom+json") == true)
    }
    
    @Test("Retrieve specific workitem")
    func testRetrieveWorkitem() async throws {
        let storage = InMemoryStorageProvider()
        let upsStorage = InMemoryUPSStorageProvider()
        let server = DICOMwebServer(configuration: .development, storage: storage, upsStorage: upsStorage)
        
        let workitem = Workitem(
            workitemUID: "1.2.3.4.5",
            scheduledStartDateTime: Date(),
            patientName: "Smith^John"
        )
        try await upsStorage.createWorkitem(workitem)
        
        let request = DICOMwebRequest(
            method: .get,
            path: "/dicom-web/workitems/1.2.3.4.5",
            queryParameters: [:]
        )
        
        let response = await server.handleRequest(request)
        #expect(response.statusCode == 200)
        
        // Verify JSON response contains workitem UID
        if let body = response.body,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            let sopUIDElement = json["00080018"] as? [String: Any]
            let values = sopUIDElement?["Value"] as? [String]
            #expect(values?.first == "1.2.3.4.5")
        }
    }
    
    @Test("Retrieve non-existent workitem returns 404")
    func testRetrieveNonExistentWorkitem() async throws {
        let storage = InMemoryStorageProvider()
        let upsStorage = InMemoryUPSStorageProvider()
        let server = DICOMwebServer(configuration: .development, storage: storage, upsStorage: upsStorage)
        
        let request = DICOMwebRequest(
            method: .get,
            path: "/dicom-web/workitems/1.2.3.4.5",
            queryParameters: [:]
        )
        
        let response = await server.handleRequest(request)
        #expect(response.statusCode == 404)
    }
    
    @Test("Create workitem without UID")
    func testCreateWorkitemWithoutUID() async throws {
        let storage = InMemoryStorageProvider()
        let upsStorage = InMemoryUPSStorageProvider()
        let server = DICOMwebServer(configuration: .development, storage: storage, upsStorage: upsStorage)
        
        let workitemJSON: [String: Any] = [
            "00741000": ["vr": "CS", "Value": ["SCHEDULED"]],
            "00100010": ["vr": "PN", "Value": [["Alphabetic": "Smith^John"]]],
            "00100020": ["vr": "LO", "Value": ["PAT001"]]
        ]
        let body = try JSONSerialization.data(withJSONObject: workitemJSON)
        
        let request = DICOMwebRequest(
            method: .post,
            path: "/dicom-web/workitems",
            headers: ["Content-Type": "application/dicom+json"],
            body: body
        )
        
        let response = await server.handleRequest(request)
        #expect(response.statusCode == 201)
        #expect(response.headers["Location"] != nil)
    }
    
    @Test("Create workitem with specific UID")
    func testCreateWorkitemWithUID() async throws {
        let storage = InMemoryStorageProvider()
        let upsStorage = InMemoryUPSStorageProvider()
        let server = DICOMwebServer(configuration: .development, storage: storage, upsStorage: upsStorage)
        
        let workitemJSON: [String: Any] = [
            "00741000": ["vr": "CS", "Value": ["SCHEDULED"]],
            "00100010": ["vr": "PN", "Value": [["Alphabetic": "Smith^John"]]]
        ]
        let body = try JSONSerialization.data(withJSONObject: workitemJSON)
        
        // PS3.18 Table 11.4.1-1: POST /workitems?workitem={uid}
        let request = DICOMwebRequest(
            method: .post,
            path: "/dicom-web/workitems?workitem=1.2.3.4.5",
            headers: ["Content-Type": "application/dicom+json"],
            body: body
        )
        
        let response = await server.handleRequest(request)
        #expect(response.statusCode == 201)
        #expect(response.headers["Location"]?.contains("1.2.3.4.5") == true)
        #expect(response.body == nil, "11.4.3.3: a success response should have no payload")
    }
    
    @Test("Create duplicate workitem returns 409")
    func testCreateDuplicateWorkitem() async throws {
        let storage = InMemoryStorageProvider()
        let upsStorage = InMemoryUPSStorageProvider()
        let server = DICOMwebServer(configuration: .development, storage: storage, upsStorage: upsStorage)
        
        // Create initial workitem
        let workitem = Workitem(workitemUID: "1.2.3.4.5")
        try await upsStorage.createWorkitem(workitem)
        
        // Try to create duplicate
        let workitemJSON: [String: Any] = [
            "00741000": ["vr": "CS", "Value": ["SCHEDULED"]]
        ]
        let body = try JSONSerialization.data(withJSONObject: workitemJSON)
        
        let request = DICOMwebRequest(
            method: .post,
            path: "/dicom-web/workitems?workitem=1.2.3.4.5",
            headers: ["Content-Type": "application/dicom+json"],
            body: body
        )
        
        let response = await server.handleRequest(request)
        #expect(response.statusCode == 409)
    }
    
    @Test("Update workitem")
    func testUpdateWorkitem() async throws {
        let storage = InMemoryStorageProvider()
        let upsStorage = InMemoryUPSStorageProvider()
        let server = DICOMwebServer(configuration: .development, storage: storage, upsStorage: upsStorage)
        
        // Create workitem
        let workitem = Workitem(
            workitemUID: "1.2.3.4.5",
            scheduledStartDateTime: Date(),
            patientName: "Smith^John"
        )
        try await upsStorage.createWorkitem(workitem)
        
        // Update workitem
        let updateJSON: [String: Any] = [
            "00100010": ["vr": "PN", "Value": [["Alphabetic": "Jones^Jane"]]]
        ]
        let body = try JSONSerialization.data(withJSONObject: updateJSON)
        
        // PS3.18 11.6.1: POST /workitems/{workitem}; Table 11.6.3-1: 200
        let request = DICOMwebRequest(
            method: .post,
            path: "/dicom-web/workitems/1.2.3.4.5",
            headers: ["Content-Type": "application/dicom+json"],
            body: body
        )
        
        let response = await server.handleRequest(request)
        #expect(response.statusCode == 200)
        
        // Verify update
        let updated = try await upsStorage.getWorkitem(workitemUID: "1.2.3.4.5")
        #expect(updated?.patientName == "Jones^Jane")
    }
    
    @Test("Change workitem state to IN PROGRESS")
    func testChangeStateToInProgress() async throws {
        let storage = InMemoryStorageProvider()
        let upsStorage = InMemoryUPSStorageProvider()
        let server = DICOMwebServer(configuration: .development, storage: storage, upsStorage: upsStorage)
        
        // Create workitem
        let workitem = Workitem(workitemUID: "1.2.3.4.5", state: .scheduled)
        try await upsStorage.createWorkitem(workitem)
        
        // Change state: PS3.18 11.7.1.4 / PS3.4 CC.2.1.2, the SCU generates and sends the Transaction UID
        let stateJSON: [String: Any] = [
            "00741000": ["vr": "CS", "Value": ["IN PROGRESS"]],
            "00081195": ["vr": "UI", "Value": ["2.25.111"]]
        ]
        let body = try JSONSerialization.data(withJSONObject: stateJSON)
        
        let request = DICOMwebRequest(
            method: .put,
            path: "/dicom-web/workitems/1.2.3.4.5/state",
            headers: ["Content-Type": "application/dicom+json"],
            body: body
        )
        
        let response = await server.handleRequest(request)
        #expect(response.statusCode == 200)
        #expect(response.body == nil, "11.7.3.3: a success response shall have no payload")
        
        // PS3.4 CC.2.1.3: the SCP records the Transaction UID the SCU provided
        let claimed = try await upsStorage.getWorkitem(workitemUID: "1.2.3.4.5")
        #expect(claimed?.transactionUID == "2.25.111")
        if false {
        }
    }
    
    @Test("Invalid state transition returns 409")
    func testInvalidStateTransition() async throws {
        let storage = InMemoryStorageProvider()
        let upsStorage = InMemoryUPSStorageProvider()
        let server = DICOMwebServer(configuration: .development, storage: storage, upsStorage: upsStorage)
        
        // Create workitem in SCHEDULED state
        let workitem = Workitem(workitemUID: "1.2.3.4.5", state: .scheduled)
        try await upsStorage.createWorkitem(workitem)
        
        // Try to complete directly (invalid: PS3.4 Table CC.1.1-2 gives C310H; PS3.18 Table 11.7.3-1: 409)
        let stateJSON: [String: Any] = [
            "00741000": ["vr": "CS", "Value": ["COMPLETED"]],
            "00081195": ["vr": "UI", "Value": ["2.25.222"]]
        ]
        let body = try JSONSerialization.data(withJSONObject: stateJSON)
        
        let request = DICOMwebRequest(
            method: .put,
            path: "/dicom-web/workitems/1.2.3.4.5/state",
            headers: ["Content-Type": "application/dicom+json"],
            body: body
        )
        
        let response = await server.handleRequest(request)
        #expect(response.statusCode == 409)
    }
    
    @Test("Request cancellation for SCHEDULED workitem")
    func testRequestCancellationScheduled() async throws {
        let storage = InMemoryStorageProvider()
        let upsStorage = InMemoryUPSStorageProvider()
        let server = DICOMwebServer(configuration: .development, storage: storage, upsStorage: upsStorage)
        
        // Create workitem
        let workitem = Workitem(workitemUID: "1.2.3.4.5", state: .scheduled)
        try await upsStorage.createWorkitem(workitem)
        
        // PS3.18 11.8.1: POST /workitems/{workitem}/cancelrequest; Table 11.8.3-1: 202
        let request = DICOMwebRequest(
            method: .post,
            path: "/dicom-web/workitems/1.2.3.4.5/cancelrequest",
            headers: ["Content-Type": "application/dicom+json"],
            body: nil
        )
        
        let response = await server.handleRequest(request)
        #expect(response.statusCode == 202)
        
        // Verify workitem is canceled
        let updated = try await upsStorage.getWorkitem(workitemUID: "1.2.3.4.5")
        #expect(updated?.state == .canceled)
    }
    
    @Test("Subscribe to workitem returns success")
    func testSubscribeWorkitem() async throws {
        let storage = InMemoryStorageProvider()
        let upsStorage = InMemoryUPSStorageProvider()
        let server = DICOMwebServer(configuration: .development, storage: storage, upsStorage: upsStorage)
        
        // Create workitem
        let workitem = Workitem(workitemUID: "1.2.3.4.5")
        try await upsStorage.createWorkitem(workitem)
        
        let request = DICOMwebRequest(
            method: .post,
            path: "/dicom-web/workitems/1.2.3.4.5/subscribers/MYAE",
            headers: [:]
        )
        
        let response = await server.handleRequest(request)
        #expect(response.statusCode == 201, "PS3.18 Table 11.10.3-1: 201 (Created)")
    }
    
    @Test("Unsubscribe from workitem returns success")
    func testUnsubscribeWorkitem() async throws {
        let storage = InMemoryStorageProvider()
        let upsStorage = InMemoryUPSStorageProvider()
        let server = DICOMwebServer(configuration: .development, storage: storage, upsStorage: upsStorage)
        
        let request = DICOMwebRequest(
            method: .delete,
            path: "/dicom-web/workitems/1.2.3.4.5/subscribers/MYAE",
            headers: [:]
        )
        
        let response = await server.handleRequest(request)
        #expect(response.statusCode == 200)
    }
    
    @Test("Search workitems with query parameters")
    func testSearchWithQueryParameters() async throws {
        let storage = InMemoryStorageProvider()
        let upsStorage = InMemoryUPSStorageProvider()
        let server = DICOMwebServer(configuration: .development, storage: storage, upsStorage: upsStorage)
        
        // Create workitems with different states
        var w1 = Workitem(workitemUID: "1.2.3.1", state: .scheduled)
        w1.patientID = "PAT001"
        var w2 = Workitem(workitemUID: "1.2.3.2", state: .inProgress)
        w2.patientID = "PAT002"
        
        try await upsStorage.createWorkitem(w1)
        try await upsStorage.createWorkitem(w2)
        
        // Search for SCHEDULED only
        let request = DICOMwebRequest(
            method: .get,
            path: "/dicom-web/workitems",
            queryParameters: ["00741000": "SCHEDULED"]
        )
        
        let response = await server.handleRequest(request)
        #expect(response.statusCode == 200)
        #expect(response.headers["X-Total-Count"] == "1")
    }
    
    @Test("Capabilities include upsRS when configured")
    func testCapabilitiesWithUPS() async throws {
        let storage = InMemoryStorageProvider()
        let upsStorage = InMemoryUPSStorageProvider()
        let config = DICOMwebServerConfiguration(pathPrefix: "/dicom-web")
        let server = DICOMwebServer(configuration: config, storage: storage, upsStorage: upsStorage)
        
        // We would need to add a capabilities endpoint route for this test
        // For now, this validates the server initializes correctly with UPS storage
        #expect(await server.running == false)
    }
    
    @Test("Setting UPS storage dynamically")
    func testSetUPSStorage() async throws {
        let storage = InMemoryStorageProvider()
        let server = DICOMwebServer(storage: storage)
        
        // Initially no UPS storage
        let request1 = DICOMwebRequest(
            method: .get,
            path: "/dicom-web/workitems",
            queryParameters: [:]
        )
        let response1 = await server.handleRequest(request1)
        #expect(response1.statusCode == 501)
        
        // Set UPS storage
        let upsStorage = InMemoryUPSStorageProvider()
        await server.setUPSStorage(upsStorage)
        
        // Now should work
        let response2 = await server.handleRequest(request1)
        #expect(response2.statusCode == 200)
    }
}

// MARK: - UPS-RS Router Tests

@Suite("UPS-RS Router Tests")
struct UPSRSRouterTests {
    
    let router = DICOMwebRouter(pathPrefix: "/dicom-web")
    
    @Test("Match search workitems route")
    func testMatchSearchWorkitems() {
        let match = router.match(path: "/dicom-web/workitems", method: .get)
        
        #expect(match != nil)
        #expect(match?.handlerType == .searchWorkitems)
    }
    
    @Test("Match create workitem route")
    func testMatchCreateWorkitem() {
        let match = router.match(path: "/dicom-web/workitems", method: .post)
        
        #expect(match != nil)
        #expect(match?.handlerType == .createWorkitem)
    }
    
    @Test("Match retrieve workitem route")
    func testMatchRetrieveWorkitem() {
        let match = router.match(path: "/dicom-web/workitems/1.2.3.4.5", method: .get)
        
        #expect(match != nil)
        #expect(match?.handlerType == .retrieveWorkitem)
        #expect(match?.parameters["workitemUID"] == "1.2.3.4.5")
    }
    
    @Test("Match create workitem with UID route (PS3.18 Table 11.4.1-1: /workitems?workitem=)")
    func testMatchCreateWorkitemWithUID() {
        let match = router.match(path: "/dicom-web/workitems?workitem=1.2.3.4.5", method: .post)
        
        #expect(match != nil)
        #expect(match?.handlerType == .createWorkitemWithUID)
        #expect(match?.parameters["workitemUID"] == "1.2.3.4.5")
    }
    
    @Test("Match update workitem route (PS3.18 11.6.1: POST /workitems/{workitem}; PUT tolerated)")
    func testMatchUpdateWorkitem() {
        let match = router.match(path: "/dicom-web/workitems/1.2.3.4.5", method: .post)
        
        #expect(match != nil)
        #expect(match?.handlerType == .updateWorkitem)
        #expect(router.match(path: "/dicom-web/workitems/1.2.3.4.5", method: .put)?.handlerType == .updateWorkitem)
    }
    
    @Test("Well-known subscription UIDs route to the global handlers (PS3.18 Table 11.10.1-1)")
    func testMatchGlobalSubscription() {
        let global = router.match(path: "/dicom-web/workitems/1.2.840.10008.5.1.4.34.5/subscribers/MYAE", method: .post)
        #expect(global?.handlerType == .subscribeGlobal)
        let filtered = router.match(path: "/dicom-web/workitems/1.2.840.10008.5.1.4.34.5.1/subscribers/MYAE", method: .delete)
        #expect(filtered?.handlerType == .unsubscribeGlobal)
    }
    
    @Test("Match change workitem state route")
    func testMatchChangeWorkitemState() {
        let match = router.match(path: "/dicom-web/workitems/1.2.3.4.5/state", method: .put)
        
        #expect(match != nil)
        #expect(match?.handlerType == .changeWorkitemState)
        #expect(match?.parameters["workitemUID"] == "1.2.3.4.5")
    }
    
    @Test("Match cancel request route")
    func testMatchCancelRequest() {
        let match = router.match(path: "/dicom-web/workitems/1.2.3.4.5/cancelrequest", method: .post)
        
        #expect(match != nil)
        #expect(match?.handlerType == .requestWorkitemCancellation)
    }
    
    @Test("Match subscribe workitem route")
    func testMatchSubscribeWorkitem() {
        let match = router.match(path: "/dicom-web/workitems/1.2.3.4.5/subscribers/MYAE", method: .post)
        
        #expect(match != nil)
        #expect(match?.handlerType == .subscribeWorkitem)
        #expect(match?.parameters["workitemUID"] == "1.2.3.4.5")
        #expect(match?.parameters["aeTitle"] == "MYAE")
    }
    
    @Test("Match unsubscribe workitem route")
    func testMatchUnsubscribeWorkitem() {
        let match = router.match(path: "/dicom-web/workitems/1.2.3.4.5/subscribers/MYAE", method: .delete)
        
        #expect(match != nil)
        #expect(match?.handlerType == .unsubscribeWorkitem)
    }
    
    @Test("Match suspend subscription route")
    func testMatchSuspendSubscription() {
        let match = router.match(path: "/dicom-web/workitems/1.2.3.4.5/subscribers/MYAE/suspend", method: .post)
        
        #expect(match != nil)
        #expect(match?.handlerType == .suspendSubscription)
    }
}

