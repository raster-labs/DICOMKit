import Testing
import Foundation
@testable import DICOMWeb

@Suite("DICOMwebClient Tests")
struct DICOMwebClientTests {
    
    let testURL = URL(string: "https://pacs.example.com/dicom-web")!
    
    // MARK: - Initialization Tests
    
    @Test("Client initialization with configuration")
    func testClientInitWithConfiguration() {
        let config = DICOMwebConfiguration(baseURL: testURL)
        let client = DICOMwebClient(configuration: config)
        
        #expect(client.configuration.baseURL == testURL)
    }
    
    @Test("Client initialization with HTTP client")
    func testClientInitWithHTTPClient() {
        let config = DICOMwebConfiguration(baseURL: testURL)
        let httpClient = HTTPClient(configuration: config)
        let client = DICOMwebClient(httpClient: httpClient)
        
        #expect(client.configuration.baseURL == testURL)
    }
    
    @Test("URL builder accessible from client")
    func testClientURLBuilder() {
        let config = DICOMwebConfiguration(baseURL: testURL)
        let client = DICOMwebClient(configuration: config)
        
        let studyURL = client.urlBuilder.studyURL(studyUID: "1.2.3.4.5")
        #expect(studyURL.absoluteString == "https://pacs.example.com/dicom-web/studies/1.2.3.4.5")
    }
    
    // MARK: - RetrieveProgress Tests
    
    @Test("RetrieveProgress fraction with total bytes")
    func testProgressFractionWithBytes() {
        let progress = DICOMwebClient.RetrieveProgress(
            bytesReceived: 500,
            totalBytes: 1000,
            instancesReceived: 0,
            totalInstances: nil
        )
        
        #expect(progress.fractionCompleted == 0.5)
    }
    
    @Test("RetrieveProgress fraction with total instances")
    func testProgressFractionWithInstances() {
        let progress = DICOMwebClient.RetrieveProgress(
            bytesReceived: 0,
            totalBytes: nil,
            instancesReceived: 3,
            totalInstances: 10
        )
        
        #expect(progress.fractionCompleted == 0.3)
    }
    
    @Test("RetrieveProgress fraction with no totals")
    func testProgressFractionWithNoTotals() {
        let progress = DICOMwebClient.RetrieveProgress(
            bytesReceived: 100,
            totalBytes: nil,
            instancesReceived: 1,
            totalInstances: nil
        )
        
        #expect(progress.fractionCompleted == 0)
    }
    
    @Test("RetrieveProgress prefers bytes over instances")
    func testProgressPrefersBytesOverInstances() {
        let progress = DICOMwebClient.RetrieveProgress(
            bytesReceived: 250,
            totalBytes: 1000,
            instancesReceived: 9,
            totalInstances: 10
        )
        
        // Should use bytes: 250/1000 = 0.25, not instances: 9/10 = 0.9
        #expect(progress.fractionCompleted == 0.25)
    }
    
    // MARK: - RetrieveResult Tests
    
    @Test("RetrieveResult transfer syntax from content type")
    func testRetrieveResultTransferSyntax() {
        let contentType = DICOMMediaType.dicom(transferSyntax: "1.2.840.10008.1.2.1")
        let result = DICOMwebClient.RetrieveResult(
            instances: [Data()],
            contentType: contentType
        )
        
        #expect(result.transferSyntax == "1.2.840.10008.1.2.1")
    }
    
    @Test("RetrieveResult with no content type")
    func testRetrieveResultNoContentType() {
        let result = DICOMwebClient.RetrieveResult(
            instances: [Data()],
            contentType: nil
        )
        
        #expect(result.transferSyntax == nil)
    }
    
    // MARK: - FrameResult Tests
    
    @Test("FrameResult initialization")
    func testFrameResultInit() {
        let data = Data([0x01, 0x02, 0x03])
        let result = DICOMwebClient.FrameResult(
            frameNumber: 5,
            data: data,
            contentType: .jpeg
        )
        
        #expect(result.frameNumber == 5)
        #expect(result.data == data)
        #expect(result.contentType?.matches(.jpeg) == true)
    }
    
    // MARK: - RenderOptions Tests
    
    @Test("RenderOptions default initialization")
    func testRenderOptionsDefault() {
        let options = DICOMwebClient.RenderOptions.default
        
        #expect(options.windowCenter == nil)
        #expect(options.windowWidth == nil)
        #expect(options.viewportWidth == nil)
        #expect(options.viewportHeight == nil)
        #expect(options.quality == nil)
    }
    
    @Test("RenderOptions thumbnail preset")
    func testRenderOptionsThumbnail() {
        let options = DICOMwebClient.RenderOptions.thumbnail(size: 256)
        
        #expect(options.viewportWidth == 256)
        #expect(options.viewportHeight == 256)
        // PS3.18 Table 8.3.5-2: a Thumbnail resource takes only accept, charset and viewport
        #expect(options.quality == nil)
    }
    
    @Test("RenderOptions custom initialization")
    func testRenderOptionsCustom() {
        let options = DICOMwebClient.RenderOptions(
            windowCenter: 40,
            windowWidth: 400,
            viewportWidth: 512,
            viewportHeight: 512,
            quality: 90,
            format: .png
        )
        
        #expect(options.windowCenter == 40)
        #expect(options.windowWidth == 400)
        #expect(options.viewportWidth == 512)
        #expect(options.viewportHeight == 512)
        #expect(options.quality == 90)
    }
    
    @Test("RenderOptions image format media types")
    func testRenderOptionsImageFormatMediaTypes() {
        let jpegOptions = DICOMwebClient.RenderOptions(format: .jpeg)
        let pngOptions = DICOMwebClient.RenderOptions(format: .png)
        let gifOptions = DICOMwebClient.RenderOptions(format: .gif)
        
        #expect(jpegOptions.format.mediaType.matches(.jpeg))
        #expect(pngOptions.format.mediaType.matches(.png))
        #expect(gifOptions.format.mediaType.matches(.gif))
    }
}

// MARK: - URL Building Tests

@Suite("DICOMwebClient URL Building Tests")
struct DICOMwebClientURLBuildingTests {
    
    let testURL = URL(string: "https://pacs.example.com/dicom-web")!
    
    @Test("Study URL construction")
    func testStudyURL() {
        let config = DICOMwebConfiguration(baseURL: testURL)
        let client = DICOMwebClient(configuration: config)
        
        let url = client.urlBuilder.studyURL(studyUID: "1.2.3.4.5")
        #expect(url.absoluteString == "https://pacs.example.com/dicom-web/studies/1.2.3.4.5")
    }
    
    @Test("Series URL construction")
    func testSeriesURL() {
        let config = DICOMwebConfiguration(baseURL: testURL)
        let client = DICOMwebClient(configuration: config)
        
        let url = client.urlBuilder.seriesURL(studyUID: "1.2.3", seriesUID: "1.2.3.4")
        #expect(url.absoluteString == "https://pacs.example.com/dicom-web/studies/1.2.3/series/1.2.3.4")
    }
    
    @Test("Instance URL construction")
    func testInstanceURL() {
        let config = DICOMwebConfiguration(baseURL: testURL)
        let client = DICOMwebClient(configuration: config)
        
        let url = client.urlBuilder.instanceURL(
            studyUID: "1.2.3",
            seriesUID: "1.2.3.4",
            instanceUID: "1.2.3.4.5"
        )
        #expect(url.absoluteString == "https://pacs.example.com/dicom-web/studies/1.2.3/series/1.2.3.4/instances/1.2.3.4.5")
    }
    
    @Test("Metadata URL construction")
    func testMetadataURL() {
        let config = DICOMwebConfiguration(baseURL: testURL)
        let client = DICOMwebClient(configuration: config)
        
        let studyMetadataURL = client.urlBuilder.studyMetadataURL(studyUID: "1.2.3")
        #expect(studyMetadataURL.absoluteString == "https://pacs.example.com/dicom-web/studies/1.2.3/metadata")
        
        let seriesMetadataURL = client.urlBuilder.seriesMetadataURL(studyUID: "1.2.3", seriesUID: "1.2.3.4")
        #expect(seriesMetadataURL.absoluteString == "https://pacs.example.com/dicom-web/studies/1.2.3/series/1.2.3.4/metadata")
    }
    
    @Test("Frames URL construction")
    func testFramesURL() {
        let config = DICOMwebConfiguration(baseURL: testURL)
        let client = DICOMwebClient(configuration: config)
        
        let url = client.urlBuilder.framesURL(
            studyUID: "1.2.3",
            seriesUID: "1.2.3.4",
            instanceUID: "1.2.3.4.5",
            frames: [1, 3, 5]
        )
        #expect(url.absoluteString.contains("/frames/1,3,5"))
    }
    
    @Test("Rendered URL construction")
    func testRenderedURL() {
        let config = DICOMwebConfiguration(baseURL: testURL)
        let client = DICOMwebClient(configuration: config)
        
        let url = client.urlBuilder.instanceRenderedURL(
            studyUID: "1.2.3",
            seriesUID: "1.2.3.4",
            instanceUID: "1.2.3.4.5"
        )
        #expect(url.absoluteString.contains("/rendered"))
    }
    
    @Test("Thumbnail URL construction")
    func testThumbnailURL() {
        let config = DICOMwebConfiguration(baseURL: testURL)
        let client = DICOMwebClient(configuration: config)
        
        let studyThumbnailURL = client.urlBuilder.studyThumbnailURL(studyUID: "1.2.3")
        #expect(studyThumbnailURL.absoluteString.contains("/thumbnail"))
        
        let seriesThumbnailURL = client.urlBuilder.seriesThumbnailURL(studyUID: "1.2.3", seriesUID: "1.2.3.4")
        #expect(seriesThumbnailURL.absoluteString.contains("/thumbnail"))
        
        let instanceThumbnailURL = client.urlBuilder.instanceThumbnailURL(
            studyUID: "1.2.3",
            seriesUID: "1.2.3.4",
            instanceUID: "1.2.3.4.5"
        )
        #expect(instanceThumbnailURL.absoluteString.contains("/thumbnail"))
    }
    
    @Test("Bulk data URL construction")
    func testBulkdataURL() {
        let config = DICOMwebConfiguration(baseURL: testURL)
        let client = DICOMwebClient(configuration: config)
        
        let url = client.urlBuilder.bulkdataURL(
            studyUID: "1.2.3",
            seriesUID: "1.2.3.4",
            instanceUID: "1.2.3.4.5",
            attributePath: "7FE00010"
        )
        #expect(url.absoluteString.contains("/bulkdata/7FE00010"))
    }
}

// MARK: - Render Options Query Parameter Tests

@Suite("DICOMwebClient Render Options Tests")
struct DICOMwebClientRenderOptionsTests {
    
    @Test("Render options URL with window parameters")
    func testRenderOptionsWithWindowParams() {
        let baseURL = URL(string: "https://example.com/rendered")!
        let url = DICOMwebURLBuilder.renderedURL(
            base: baseURL,
            windowCenter: 40,
            windowWidth: 400
        )
        
        #expect(url.absoluteString.contains("window=40,400,linear"))
    }
    
    @Test("Render options URL with viewport parameters")
    func testRenderOptionsWithViewportParams() {
        let baseURL = URL(string: "https://example.com/rendered")!
        let url = DICOMwebURLBuilder.renderedURL(
            base: baseURL,
            viewportWidth: 512,
            viewportHeight: 512
        )
        
        #expect(url.absoluteString.contains("viewport=512,512"))
    }
    
    @Test("Render options URL with quality parameter")
    func testRenderOptionsWithQuality() {
        let baseURL = URL(string: "https://example.com/rendered")!
        let url = DICOMwebURLBuilder.renderedURL(
            base: baseURL,
            quality: 85
        )
        
        #expect(url.absoluteString.contains("quality=85"))
    }
    
    @Test("Render options URL with all parameters")
    func testRenderOptionsWithAllParams() {
        let baseURL = URL(string: "https://example.com/rendered")!
        let url = DICOMwebURLBuilder.renderedURL(
            base: baseURL,
            windowCenter: 40,
            windowWidth: 400,
            viewportWidth: 256,
            viewportHeight: 256,
            quality: 90
        )
        
        #expect(url.absoluteString.contains("window=40,400,linear"))
        #expect(url.absoluteString.contains("viewport=256,256"))
        #expect(url.absoluteString.contains("quality=90"))
    }
    
    @Test("Render options URL with quality clamping")
    func testRenderOptionsQualityClamping() {
        let baseURL = URL(string: "https://example.com/rendered")!
        
        // Quality over 100 should be clamped to 100
        let urlOver = DICOMwebURLBuilder.renderedURL(base: baseURL, quality: 150)
        #expect(urlOver.absoluteString.contains("quality=100"))
        
        // PS3.18 8.3.5.1.2: quality is an integer between 1 and 100 inclusive
        let urlUnder = DICOMwebURLBuilder.renderedURL(base: baseURL, quality: -50)
        #expect(urlUnder.absoluteString.contains("quality=1"))
    }
}

// MARK: - Accept Header Tests

@Suite("DICOMwebClient Accept Header Tests")
struct DICOMwebClientAcceptHeaderTests {
    
    @Test("Default accept types from configuration")
    func testDefaultAcceptTypes() {
        let testURL = URL(string: "https://pacs.example.com/dicom-web")!
        let config = DICOMwebConfiguration(
            baseURL: testURL,
            defaultAcceptTypes: [.dicomJSON, .dicom]
        )
        
        let headers = config.headers()
        #expect(headers["Accept"]?.contains("application/dicom+json") == true)
        #expect(headers["Accept"]?.contains("application/dicom") == true)
    }
    
    @Test("Custom accept header overrides default")
    func testCustomAcceptHeaderOverridesDefault() {
        let testURL = URL(string: "https://pacs.example.com/dicom-web")!
        let config = DICOMwebConfiguration(
            baseURL: testURL,
            defaultAcceptTypes: [.dicomJSON]
        )
        
        let headers = config.headers(accept: [.jpeg])
        #expect(headers["Accept"] == "image/jpeg")
    }
    
    @Test("Preferred transfer syntaxes configuration")
    func testPreferredTransferSyntaxes() {
        let testURL = URL(string: "https://pacs.example.com/dicom-web")!
        let config = DICOMwebConfiguration(
            baseURL: testURL,
            preferredTransferSyntaxes: [
                DICOMMediaType.TransferSyntax.jpegLosslessSV1,
                DICOMMediaType.TransferSyntax.explicitVRLittleEndian
            ]
        )
        
        #expect(config.preferredTransferSyntaxes.count == 2)
        #expect(config.preferredTransferSyntaxes[0] == "1.2.840.10008.1.2.4.70")
    }
}

// MARK: - Multipart Parsing Tests

@Suite("DICOMwebClient Multipart Parsing Tests")
struct DICOMwebClientMultipartParsingTests {
    
    @Test("Parse single part response as non-multipart")
    func testSinglePartResponse() throws {
        let data = Data([0x01, 0x02, 0x03, 0x04])
        let contentType = "application/dicom"
        
        // When content type is not multipart, the entire data should be returned as a single part
        let mediaType = DICOMMediaType.parse(contentType)
        #expect(mediaType?.type == "application")
        #expect(mediaType?.subtype == "dicom")
    }
    
    @Test("Parse multipart boundary extraction")
    func testMultipartBoundaryExtraction() throws {
        let contentType = "multipart/related; boundary=----DICOMBoundary123"
        let mediaType = DICOMMediaType.parse(contentType)
        
        #expect(mediaType?.parameters["boundary"] == "----DICOMBoundary123")
    }
    
    @Test("Parse multipart with type parameter")
    func testMultipartTypeParameter() throws {
        let contentType = "multipart/related; type=\"application/dicom\"; boundary=abc"
        let mediaType = DICOMMediaType.parse(contentType)
        
        #expect(mediaType?.parameters["type"] == "application/dicom")
        #expect(mediaType?.parameters["boundary"] == "abc")
    }
}

// MARK: - Error Handling Tests

@Suite("DICOMwebClient Error Handling Tests")
struct DICOMwebClientErrorHandlingTests {
    
    @Test("Invalid bulk data URI validation")
    func testInvalidBulkDataURIValidation() async {
        // Test that URL parsing handles various invalid cases
        // The URL(string:) initializer is lenient, but we can test the pattern
        
        // Test with empty string - URL(string: "") returns nil
        let emptyURL = URL(string: "")
        #expect(emptyURL == nil)
        
        // Test that the DICOMwebError has the correct format
        let error = DICOMwebError.invalidBulkDataReference(uri: "test-uri")
        #expect(error.errorDescription?.contains("bulk data") == true)
    }
    
    @Test("Empty bulk data URI throws error")
    func testEmptyBulkDataURIThrows() async {
        let testURL = URL(string: "https://pacs.example.com/dicom-web")!
        let config = DICOMwebConfiguration(baseURL: testURL)
        let client = DICOMwebClient(configuration: config)
        
        do {
            // Empty string returns nil from URL(string:), which should throw invalidBulkDataReference
            _ = try await client.retrieveBulkData(uri: "")
            #expect(Bool(false), "Expected error for empty URI")
        } catch let error as DICOMwebError {
            if case .invalidBulkDataReference = error {
                // Expected
            } else {
                #expect(Bool(false), "Expected invalidBulkDataReference error, got \(error)")
            }
        } catch {
            #expect(Bool(false), "Expected DICOMwebError")
        }
    }
    
    @Test("Empty frames array throws error")
    func testEmptyFramesArrayThrows() async {
        let testURL = URL(string: "https://pacs.example.com/dicom-web")!
        let config = DICOMwebConfiguration(baseURL: testURL)
        let client = DICOMwebClient(configuration: config)
        
        do {
            _ = try await client.retrieveFrames(
                studyUID: "1.2.3",
                seriesUID: "1.2.3.4",
                instanceUID: "1.2.3.4.5",
                frames: []
            )
            #expect(Bool(false), "Expected error for empty frames")
        } catch let error as DICOMwebError {
            if case .badRequest = error {
                // Expected
            } else {
                #expect(Bool(false), "Expected badRequest error")
            }
        } catch {
            #expect(Bool(false), "Expected DICOMwebError")
        }
    }
    
    @Test("Invalid frame number throws error")
    func testInvalidFrameNumberThrows() async {
        let testURL = URL(string: "https://pacs.example.com/dicom-web")!
        let config = DICOMwebConfiguration(baseURL: testURL)
        let client = DICOMwebClient(configuration: config)
        
        do {
            // Frame numbers must be >= 1
            _ = try await client.retrieveFrames(
                studyUID: "1.2.3",
                seriesUID: "1.2.3.4",
                instanceUID: "1.2.3.4.5",
                frames: [0]
            )
            #expect(Bool(false), "Expected error for invalid frame number")
        } catch let error as DICOMwebError {
            if case .invalidFrameNumber = error {
                // Expected
            } else {
                #expect(Bool(false), "Expected invalidFrameNumber error, got \(error)")
            }
        } catch {
            #expect(Bool(false), "Expected DICOMwebError")
        }
    }
    
    @Test("Negative frame number throws error")
    func testNegativeFrameNumberThrows() async {
        let testURL = URL(string: "https://pacs.example.com/dicom-web")!
        let config = DICOMwebConfiguration(baseURL: testURL)
        let client = DICOMwebClient(configuration: config)
        
        do {
            _ = try await client.retrieveFrames(
                studyUID: "1.2.3",
                seriesUID: "1.2.3.4",
                instanceUID: "1.2.3.4.5",
                frames: [-1]
            )
            #expect(Bool(false), "Expected error for negative frame number")
        } catch let error as DICOMwebError {
            if case .invalidFrameNumber = error {
                // Expected
            } else {
                #expect(Bool(false), "Expected invalidFrameNumber error")
            }
        } catch {
            #expect(Bool(false), "Expected DICOMwebError")
        }
    }
}

// MARK: - DICOMwebClient UPS-RS Tests

@Suite("DICOMwebClient UPS-RS Tests")
struct DICOMwebClientUPSTests {
    
    let testURL = URL(string: "https://pacs.example.com/dicom-web")!
    
    // MARK: - URL Building Tests
    
    @Test("Workitems URL construction")
    func testWorkitemsURL() {
        let config = DICOMwebConfiguration(baseURL: testURL)
        let client = DICOMwebClient(configuration: config)
        
        let url = client.urlBuilder.workitemsURL
        #expect(url.absoluteString == "https://pacs.example.com/dicom-web/workitems")
    }
    
    @Test("Workitem URL construction")
    func testWorkitemURL() {
        let config = DICOMwebConfiguration(baseURL: testURL)
        let client = DICOMwebClient(configuration: config)
        
        let url = client.urlBuilder.workitemURL(workitemUID: "1.2.3.4.5")
        #expect(url.absoluteString == "https://pacs.example.com/dicom-web/workitems/1.2.3.4.5")
    }
    
    @Test("Workitem state URL construction")
    func testWorkitemStateURL() {
        let config = DICOMwebConfiguration(baseURL: testURL)
        let client = DICOMwebClient(configuration: config)
        
        let url = client.urlBuilder.workitemStateURL(workitemUID: "1.2.3.4.5")
        #expect(url.absoluteString == "https://pacs.example.com/dicom-web/workitems/1.2.3.4.5/state")
    }
    
    @Test("Workitem cancel request URL construction")
    func testWorkitemCancelRequestURL() {
        let config = DICOMwebConfiguration(baseURL: testURL)
        let client = DICOMwebClient(configuration: config)
        
        let url = client.urlBuilder.workitemCancelRequestURL(workitemUID: "1.2.3.4.5")
        #expect(url.absoluteString == "https://pacs.example.com/dicom-web/workitems/1.2.3.4.5/cancelrequest")
    }
    
    @Test("Workitem subscription URL construction")
    func testWorkitemSubscriptionURL() {
        let config = DICOMwebConfiguration(baseURL: testURL)
        let client = DICOMwebClient(configuration: config)
        
        let url = client.urlBuilder.workitemSubscriptionURL(workitemUID: "1.2.3.4.5", aeTitle: "MY_AE")
        #expect(url.absoluteString == "https://pacs.example.com/dicom-web/workitems/1.2.3.4.5/subscribers/MY_AE")
    }
    
    @Test("Global workitem subscription URL construction")
    func testGlobalWorkitemSubscriptionURL() {
        let config = DICOMwebConfiguration(baseURL: testURL)
        let client = DICOMwebClient(configuration: config)
        
        let url = client.urlBuilder.globalWorkitemSubscriptionURL(aeTitle: "MY_AE")
        #expect(url.absoluteString == "https://pacs.example.com/dicom-web/workitems/1.2.840.10008.5.1.4.34.5/subscribers/MY_AE")
    }
    
    @Test("Workitem subscription suspend URL construction")
    func testWorkitemSubscriptionSuspendURL() {
        let config = DICOMwebConfiguration(baseURL: testURL)
        let client = DICOMwebClient(configuration: config)
        
        let url = client.urlBuilder.workitemSubscriptionSuspendURL(workitemUID: "1.2.3.4.5", aeTitle: "MY_AE")
        #expect(url.absoluteString == "https://pacs.example.com/dicom-web/workitems/1.2.3.4.5/subscribers/MY_AE/suspend")
    }
    
    @Test("Search workitems URL with query parameters")
    func testSearchWorkitemsURLWithParams() {
        let config = DICOMwebConfiguration(baseURL: testURL)
        let client = DICOMwebClient(configuration: config)
        
        let params = [
            "PatientID": "PAT001",
            "limit": "10"
        ]
        let url = client.urlBuilder.searchWorkitemsURL(parameters: params)
        #expect(url.absoluteString.contains("/workitems?"))
        #expect(url.absoluteString.contains("PatientID=PAT001"))
        #expect(url.absoluteString.contains("limit=10"))
    }
    
    // MARK: - UPS Query Building Tests
    
    @Test("UPS query with default parameters")
    func testUPSQueryDefault() {
        let query = UPSQuery()
        let params = query.toParameters()
        
        #expect(params.isEmpty)
    }
    
    @Test("UPS query for scheduled workitems")
    func testUPSQueryScheduled() {
        let query = UPSQuery.scheduled()
        let params = query.toParameters()
        
        #expect(params["00741000"] == "SCHEDULED")
    }
    
    @Test("UPS query for in-progress workitems")
    func testUPSQueryInProgress() {
        let query = UPSQuery.inProgress()
        let params = query.toParameters()
        
        #expect(params["00741000"] == "IN PROGRESS")
    }
    
    @Test("UPS query with patient ID")
    func testUPSQueryWithPatientID() {
        let query = UPSQuery().patientID("PAT001")
        let params = query.toParameters()
        
        #expect(params["00100020"] == "PAT001")
    }
    
    @Test("UPS query with priority")
    func testUPSQueryWithPriority() {
        let query = UPSQuery().priority(.high)
        let params = query.toParameters()
        
        #expect(params["00741200"] == "HIGH")
    }
    
    @Test("UPS query with pagination")
    func testUPSQueryWithPagination() {
        let query = UPSQuery().limit(10).offset(20)
        let params = query.toParameters()
        
        #expect(params["limit"] == "10")
        #expect(params["offset"] == "20")
    }
    
    // MARK: - UPS Result Types Tests
    
    @Test("UPSCreateResponse initialization")
    func testUPSCreateResponse() {
        let response = UPSCreateResponse(
            workitemUID: "1.2.3.4.5",
            retrieveURL: "https://pacs.example.com/workitems/1.2.3.4.5",
            warnings: ["Warning 1"]
        )
        
        #expect(response.workitemUID == "1.2.3.4.5")
        #expect(response.retrieveURL == "https://pacs.example.com/workitems/1.2.3.4.5")
        #expect(response.warnings.count == 1)
        #expect(response.warnings[0] == "Warning 1")
    }
    
    @Test("UPSStateChangeResponse initialization")
    func testUPSStateChangeResponse() {
        let response = UPSStateChangeResponse(
            workitemUID: "1.2.3.4.5",
            newState: UPSState.inProgress,
            transactionUID: "2.16.840.1.113883.3.1",
            warnings: []
        )
        
        #expect(response.workitemUID == "1.2.3.4.5")
        #expect(response.newState == UPSState.inProgress)
        #expect(response.transactionUID == "2.16.840.1.113883.3.1")
        #expect(response.warnings.isEmpty)
    }
    
    @Test("UPSCancellationResponse accepted")
    func testUPSCancellationResponseAccepted() {
        let response = UPSCancellationResponse(
            workitemUID: "1.2.3.4.5",
            accepted: true,
            rejectionReason: nil,
            warnings: []
        )
        
        #expect(response.workitemUID == "1.2.3.4.5")
        #expect(response.accepted)
        #expect(response.rejectionReason == nil)
    }
    
    @Test("UPSCancellationResponse rejected")
    func testUPSCancellationResponseRejected() {
        let response = UPSCancellationResponse(
            workitemUID: "1.2.3.4.5",
            accepted: false,
            rejectionReason: "Workitem already in progress",
            warnings: []
        )
        
        #expect(response.workitemUID == "1.2.3.4.5")
        #expect(!response.accepted)
        #expect(response.rejectionReason == "Workitem already in progress")
    }
    
    @Test("UPSCancellationRequest initialization")
    func testUPSCancellationRequest() {
        let request = UPSCancellationRequest(
            workitemUID: "1.2.3.4.5",
            reason: "No longer needed",
            contactDisplayName: "Dr. Smith",
            contactURI: "mailto:dr.smith@hospital.com"
        )
        
        #expect(request.workitemUID == "1.2.3.4.5")
        #expect(request.reason == "No longer needed")
        #expect(request.contactDisplayName == "Dr. Smith")
        #expect(request.contactURI == "mailto:dr.smith@hospital.com")
    }
    
    // MARK: - UPS Query Result Tests
    
    @Test("UPSQueryResult empty result")
    func testUPSQueryResultEmpty() {
        let result = UPSQueryResult.empty
        
        #expect(result.workitems.isEmpty)
        #expect(result.totalCount == 0)
        #expect(!result.hasMore)
    }
    
    @Test("UPSQueryResult parsing from JSON")
    func testUPSQueryResultParsing() {
        let jsonArray: [[String: Any]] = [
            [
                UPSTag.sopInstanceUID: ["vr": "UI", "Value": ["1.2.3.4.5"]],
                UPSTag.procedureStepState: ["vr": "CS", "Value": ["SCHEDULED"]]
            ],
            [
                UPSTag.sopInstanceUID: ["vr": "UI", "Value": ["1.2.3.4.6"]],
                UPSTag.procedureStepState: ["vr": "CS", "Value": ["IN PROGRESS"]]
            ]
        ]
        
        let result = UPSQueryResult.parse(
            jsonArray: jsonArray,
            totalCount: 10,
            offset: 0,
            limit: 2
        )
        
        #expect(result.workitems.count == 2)
        #expect(result.totalCount == 10)
        #expect(result.hasMore)
    }
    
    // MARK: - Workitem Tests
    
    @Test("Workitem basic initialization")
    func testWorkitemBasicInit() {
        let workitem = Workitem(workitemUID: "1.2.3.4.5")
        
        #expect(workitem.workitemUID == "1.2.3.4.5")
        #expect(workitem.state == UPSState.scheduled)
        #expect(workitem.priority == UPSPriority.medium)
    }
    
    @Test("Workitem full initialization")
    func testWorkitemFullInit() {
        let scheduledDate = Date()
        let workitem = Workitem(
            workitemUID: "1.2.3.4.5",
            scheduledStartDateTime: scheduledDate,
            patientName: "Smith^John",
            patientID: "PAT001",
            procedureStepLabel: "CT Scan",
            priority: .high
        )
        
        #expect(workitem.workitemUID == "1.2.3.4.5")
        #expect(workitem.state == UPSState.scheduled)
        #expect(workitem.priority == UPSPriority.high)
        #expect(workitem.patientName == "Smith^John")
        #expect(workitem.patientID == "PAT001")
        #expect(workitem.procedureStepLabel == "CT Scan")
    }
    
    // MARK: - WorkitemResult Tests
    
    @Test("WorkitemResult parsing from JSON")
    func testWorkitemResultParsing() {
        let json: [String: Any] = [
            UPSTag.sopInstanceUID: ["vr": "UI", "Value": ["1.2.3.4.5"]],
            UPSTag.procedureStepState: ["vr": "CS", "Value": ["SCHEDULED"]],
            UPSTag.scheduledProcedureStepPriority: ["vr": "CS", "Value": ["HIGH"]],
            UPSTag.patientName: ["vr": "PN", "Value": [["Alphabetic": "Smith^John"]]],
            UPSTag.patientID: ["vr": "LO", "Value": ["PAT001"]]
        ]
        
        let result = WorkitemResult.parse(json: json)
        
        #expect(result != nil)
        #expect(result?.workitemUID == "1.2.3.4.5")
        #expect(result?.state == UPSState.scheduled)
        #expect(result?.priority == UPSPriority.high)
        #expect(result?.patientName == "Smith^John")
        #expect(result?.patientID == "PAT001")
    }
}
