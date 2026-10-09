import Testing
import Foundation
@testable import DICOMWeb

@Suite("DICOMwebURLBuilder Tests")
struct DICOMwebURLBuilderTests {
    
    let baseURL = URL(string: "https://pacs.example.com/dicom-web")!
    
    var builder: DICOMwebURLBuilder {
        DICOMwebURLBuilder(baseURL: baseURL)
    }
    
    // MARK: - Studies URLs
    
    @Test("Studies URL")
    func testStudiesURL() {
        #expect(builder.studiesURL.absoluteString == "https://pacs.example.com/dicom-web/studies")
    }
    
    @Test("Study URL")
    func testStudyURL() {
        let url = builder.studyURL(studyUID: "1.2.3.4.5")
        #expect(url.absoluteString == "https://pacs.example.com/dicom-web/studies/1.2.3.4.5")
    }
    
    @Test("Study metadata URL")
    func testStudyMetadataURL() {
        let url = builder.studyMetadataURL(studyUID: "1.2.3.4.5")
        #expect(url.absoluteString == "https://pacs.example.com/dicom-web/studies/1.2.3.4.5/metadata")
    }
    
    @Test("Study rendered URL")
    func testStudyRenderedURL() {
        let url = builder.studyRenderedURL(studyUID: "1.2.3.4.5")
        #expect(url.absoluteString == "https://pacs.example.com/dicom-web/studies/1.2.3.4.5/rendered")
    }
    
    @Test("Study thumbnail URL")
    func testStudyThumbnailURL() {
        let url = builder.studyThumbnailURL(studyUID: "1.2.3.4.5")
        #expect(url.absoluteString == "https://pacs.example.com/dicom-web/studies/1.2.3.4.5/thumbnail")
    }
    
    // MARK: - Series URLs
    
    @Test("Series URL for study")
    func testSeriesURLForStudy() {
        let url = builder.seriesURL(studyUID: "1.2.3")
        #expect(url.absoluteString == "https://pacs.example.com/dicom-web/studies/1.2.3/series")
    }
    
    @Test("Series URL with series UID")
    func testSeriesURLWithUID() {
        let url = builder.seriesURL(studyUID: "1.2.3", seriesUID: "4.5.6")
        #expect(url.absoluteString == "https://pacs.example.com/dicom-web/studies/1.2.3/series/4.5.6")
    }
    
    @Test("Series metadata URL")
    func testSeriesMetadataURL() {
        let url = builder.seriesMetadataURL(studyUID: "1.2.3", seriesUID: "4.5.6")
        #expect(url.absoluteString == "https://pacs.example.com/dicom-web/studies/1.2.3/series/4.5.6/metadata")
    }
    
    // MARK: - Instances URLs
    
    @Test("Instances URL")
    func testInstancesURL() {
        let url = builder.instancesURL(studyUID: "1.2.3", seriesUID: "4.5.6")
        #expect(url.absoluteString == "https://pacs.example.com/dicom-web/studies/1.2.3/series/4.5.6/instances")
    }
    
    @Test("Instance URL")
    func testInstanceURL() {
        let url = builder.instanceURL(studyUID: "1.2.3", seriesUID: "4.5.6", instanceUID: "7.8.9")
        #expect(url.absoluteString == "https://pacs.example.com/dicom-web/studies/1.2.3/series/4.5.6/instances/7.8.9")
    }
    
    @Test("Instance metadata URL")
    func testInstanceMetadataURL() {
        let url = builder.instanceMetadataURL(studyUID: "1.2.3", seriesUID: "4.5.6", instanceUID: "7.8.9")
        #expect(url.absoluteString == "https://pacs.example.com/dicom-web/studies/1.2.3/series/4.5.6/instances/7.8.9/metadata")
    }
    
    @Test("Instance rendered URL")
    func testInstanceRenderedURL() {
        let url = builder.instanceRenderedURL(studyUID: "1.2.3", seriesUID: "4.5.6", instanceUID: "7.8.9")
        #expect(url.absoluteString == "https://pacs.example.com/dicom-web/studies/1.2.3/series/4.5.6/instances/7.8.9/rendered")
    }
    
    // MARK: - Frames URLs
    
    @Test("Frames URL with single frame")
    func testFramesURLSingle() {
        let url = builder.framesURL(studyUID: "1.2.3", seriesUID: "4.5.6", instanceUID: "7.8.9", frames: [1])
        #expect(url.absoluteString == "https://pacs.example.com/dicom-web/studies/1.2.3/series/4.5.6/instances/7.8.9/frames/1")
    }
    
    @Test("Frames URL with multiple frames")
    func testFramesURLMultiple() {
        let url = builder.framesURL(studyUID: "1.2.3", seriesUID: "4.5.6", instanceUID: "7.8.9", frames: [1, 3, 5])
        #expect(url.absoluteString == "https://pacs.example.com/dicom-web/studies/1.2.3/series/4.5.6/instances/7.8.9/frames/1,3,5")
    }
    
    @Test("Frames rendered URL")
    func testFramesRenderedURL() {
        let url = builder.framesRenderedURL(studyUID: "1.2.3", seriesUID: "4.5.6", instanceUID: "7.8.9", frames: [1])
        #expect(url.absoluteString == "https://pacs.example.com/dicom-web/studies/1.2.3/series/4.5.6/instances/7.8.9/frames/1/rendered")
    }
    
    // MARK: - Bulk Data URLs
    
    @Test("Bulk data URL")
    func testBulkDataURL() {
        let url = builder.bulkdataURL(studyUID: "1.2.3", seriesUID: "4.5.6", instanceUID: "7.8.9", attributePath: "7FE00010")
        #expect(url.absoluteString == "https://pacs.example.com/dicom-web/studies/1.2.3/series/4.5.6/instances/7.8.9/bulkdata/7FE00010")
    }
    
    // MARK: - Query Parameters
    
    @Test("Append query parameters")
    func testAppendQueryParameters() {
        let url = DICOMwebURLBuilder.appendQueryParameters(
            to: builder.studiesURL,
            parameters: ["PatientName": "Smith", "limit": "10"]
        )
        // Parameters are sorted by key
        #expect(url.absoluteString.contains("PatientName=Smith"))
        #expect(url.absoluteString.contains("limit=10"))
    }
    
    @Test("Search studies URL with parameters")
    func testSearchStudiesURL() {
        let url = builder.searchStudiesURL(parameters: ["00100010": "Smith"])
        #expect(url.absoluteString.contains("00100010=Smith"))
    }
    
    // MARK: - Rendered URL with parameters
    
    @Test("Rendered URL with windowing parameters")
    func testRenderedURLWithWindowing() {
        let baseRendered = builder.instanceRenderedURL(studyUID: "1.2.3", seriesUID: "4.5.6", instanceUID: "7.8.9")
        let url = DICOMwebURLBuilder.renderedURL(
            base: baseRendered,
            windowCenter: 40,
            windowWidth: 400,
            viewportWidth: 512,
            viewportHeight: 512,
            quality: 80
        )
        
        let urlString = url.absoluteString
        // PS3.18 8.3.5.1.3 / 8.3.5.1.4: window=center,width,function and viewport=vw,vh
        #expect(urlString.contains("window=40,400,linear"))
        #expect(urlString.contains("viewport=512,512"))
        #expect(urlString.contains("quality=80"))
        #expect(!urlString.contains("windowcenter"))
        #expect(!urlString.contains("columns"))
    }
    
    // MARK: - Initialization Tests
    
    @Test("Initialize from string")
    func testInitFromString() throws {
        let builder = try DICOMwebURLBuilder(baseURLString: "https://example.com/dicom-web")
        #expect(builder.baseURL.absoluteString == "https://example.com/dicom-web")
    }
    
    @Test("Initialize from invalid string throws")
    func testInitFromInvalidString() {
        // Test with clearly invalid URL (empty string)
        do {
            _ = try DICOMwebURLBuilder(baseURLString: "")
            #expect(Bool(false), "Expected error for empty URL")
        } catch {
            // Expected
            #expect(error is DICOMwebError)
        }
    }
}
