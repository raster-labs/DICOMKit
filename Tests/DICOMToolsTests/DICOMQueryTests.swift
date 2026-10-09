import XCTest
import DICOMCore
import DICOMNetwork
@testable import dicom_query

final class DICOMQueryTests: XCTestCase {
    
    // MARK: - URL Parsing Tests
    
    func testParsePACSURL() throws {
        let query = DICOMQuery()
        let result = try query.parseServerURL("pacs://server.example.com:11112")
        XCTAssertEqual(result.scheme, "pacs")
        XCTAssertEqual(result.host, "server.example.com")
        XCTAssertEqual(result.port, 11112)
    }
    
    func testParsePACSURLWithoutPort() throws {
        let query = DICOMQuery()
        let result = try query.parseServerURL("pacs://server.example.com")
        XCTAssertEqual(result.scheme, "pacs")
        XCTAssertEqual(result.host, "server.example.com")
        XCTAssertEqual(result.port, 104) // DICOM default port
    }
    
    func testParseHTTPURL() throws {
        let query = DICOMQuery()
        let result = try query.parseServerURL("http://server.example.com:8080/qido")
        XCTAssertEqual(result.scheme, "http")
        XCTAssertEqual(result.host, "server.example.com")
        XCTAssertEqual(result.port, 8080)
    }
    
    func testParseHTTPSURL() throws {
        let query = DICOMQuery()
        let result = try query.parseServerURL("https://server.example.com/qido")
        XCTAssertEqual(result.scheme, "https")
        XCTAssertEqual(result.host, "server.example.com")
        XCTAssertEqual(result.port, 443)
    }
    
    func testInvalidURL() {
        let query = DICOMQuery()
        XCTAssertThrowsError(try query.parseServerURL("not-a-url"))
    }
    
    func testInvalidScheme() {
        let query = DICOMQuery()
        XCTAssertThrowsError(try query.parseServerURL("ftp://server.example.com"))
    }
    
    func testURLWithoutHost() {
        let query = DICOMQuery()
        XCTAssertThrowsError(try query.parseServerURL("pacs://"))
    }
    
    // MARK: - Query Level Tests
    
    func testQueryLevelPatient() {
        let level = QueryLevelOption.patient
        XCTAssertEqual(level.queryLevel, .patient)
    }
    
    func testQueryLevelStudy() {
        let level = QueryLevelOption.study
        XCTAssertEqual(level.queryLevel, .study)
    }
    
    func testQueryLevelSeries() {
        let level = QueryLevelOption.series
        XCTAssertEqual(level.queryLevel, .series)
    }
    
    func testQueryLevelInstance() {
        let level = QueryLevelOption.instance
        XCTAssertEqual(level.queryLevel, .image)
    }
    
    // MARK: - Query Keys Building Tests
    
    func testBuildPatientQueryKeys() throws {
        var query = DICOMQuery()
        query.level = .patient
        query.patientName = "SMITH^JOHN*"
        query.patientId = "12345"
        
        let keys = query.buildQueryKeys()
        
        XCTAssertEqual(keys.level, .patient)
        XCTAssertTrue(keys.keys.contains { $0.tag == .patientName && $0.value == "SMITH^JOHN*" })
        XCTAssertTrue(keys.keys.contains { $0.tag == .patientID && $0.value == "12345" })
    }
    
    func testBuildStudyQueryKeys() throws {
        var query = DICOMQuery()
        query.level = .study
        query.studyDate = "20240101-20240131"
        query.modality = "CT"
        query.accessionNumber = "ACC123"
        
        let keys = query.buildQueryKeys()
        
        XCTAssertEqual(keys.level, .study)
        XCTAssertTrue(keys.keys.contains { $0.tag == .studyDate && $0.value == "20240101-20240131" })
        XCTAssertTrue(keys.keys.contains { $0.tag == .modality && $0.value == "CT" })
        XCTAssertTrue(keys.keys.contains { $0.tag == .accessionNumber && $0.value == "ACC123" })
    }
    
    func testBuildSeriesQueryKeys() throws {
        var query = DICOMQuery()
        query.level = .series
        query.seriesUid = "1.2.3.4.5"
        query.modality = "MR"
        
        let keys = query.buildQueryKeys()
        
        XCTAssertEqual(keys.level, .series)
        XCTAssertTrue(keys.keys.contains { $0.tag == .seriesInstanceUID && $0.value == "1.2.3.4.5" })
        XCTAssertTrue(keys.keys.contains { $0.tag == .modality && $0.value == "MR" })
    }
    
    func testBuildInstanceQueryKeys() throws {
        var query = DICOMQuery()
        query.level = .instance
        query.studyUid = "1.2.3"
        query.seriesUid = "1.2.3.4"
        
        let keys = query.buildQueryKeys()
        
        XCTAssertEqual(keys.level, .image)
        XCTAssertTrue(keys.keys.contains { $0.tag == .studyInstanceUID && $0.value == "1.2.3" })
        XCTAssertTrue(keys.keys.contains { $0.tag == .seriesInstanceUID && $0.value == "1.2.3.4" })
    }
}

// MARK: - Query Formatter Tests

final class QueryFormatterTests: XCTestCase {
    
    func testFormatEmptyTableResults() {
        let formatter = QueryFormatter(format: .table, level: .study)
        let output = formatter.format(results: [])
        XCTAssertTrue(output.contains("No results found"))
    }
    
    func testFormatPatientTable() {
        let formatter = QueryFormatter(format: .table, level: .patient)
        
        let attributes: [Tag: Data] = [
            .patientName: "SMITH^JOHN".data(using: .utf8)!,
            .patientID: "12345".data(using: .utf8)!,
            .patientBirthDate: "19800101".data(using: .utf8)!,
            .patientSex: "M".data(using: .utf8)!
        ]
        
        let result = GenericQueryResult(attributes: attributes, level: .patient)
        let output = formatter.format(results: [result])
        
        XCTAssertTrue(output.contains("SMITH^JOHN"))
        XCTAssertTrue(output.contains("12345"))
        XCTAssertTrue(output.contains("1980-01-01"))
        XCTAssertTrue(output.contains("M"))
    }
    
    func testFormatStudyTable() {
        let formatter = QueryFormatter(format: .table, level: .study)
        
        let attributes: [Tag: Data] = [
            .patientName: "DOE^JANE".data(using: .utf8)!,
            .patientID: "67890".data(using: .utf8)!,
            .studyDate: "20240215".data(using: .utf8)!,
            .studyDescription: "CT CHEST".data(using: .utf8)!,
            .modalitiesInStudy: "CT".data(using: .utf8)!
        ]
        
        let result = GenericQueryResult(attributes: attributes, level: .study)
        let output = formatter.format(results: [result])
        
        XCTAssertTrue(output.contains("DOE^JANE"))
        XCTAssertTrue(output.contains("67890"))
        XCTAssertTrue(output.contains("2024-02-15"))
        XCTAssertTrue(output.contains("CT CHEST"))
        XCTAssertTrue(output.contains("CT"))
    }
    
    func testFormatSeriesTable() {
        let formatter = QueryFormatter(format: .table, level: .series)
        
        let attributes: [Tag: Data] = [
            .seriesNumber: "1".data(using: .utf8)!,
            .modality: "CT".data(using: .utf8)!,
            .seriesDescription: "Axial".data(using: .utf8)!,
            .seriesDate: "20240215".data(using: .utf8)!
        ]
        
        let result = GenericQueryResult(attributes: attributes, level: .series)
        let output = formatter.format(results: [result])
        
        XCTAssertTrue(output.contains("1"))
        XCTAssertTrue(output.contains("CT"))
        XCTAssertTrue(output.contains("Axial"))
        XCTAssertTrue(output.contains("2024-02-15"))
    }
    
    func testFormatInstanceTable() {
        let formatter = QueryFormatter(format: .table, level: .image)
        
        let attributes: [Tag: Data] = [
            .instanceNumber: "1".data(using: .utf8)!,
            .sopInstanceUID: "1.2.3.4.5.6.7.8.9".data(using: .utf8)!,
            .sopClassUID: "1.2.840.10008.5.1.4.1.1.2".data(using: .utf8)!,
            .rows: Data([0x00, 0x02, 0x00, 0x00]), // 512 as UInt16 little-endian
            .columns: Data([0x00, 0x02, 0x00, 0x00])
        ]
        
        let result = GenericQueryResult(attributes: attributes, level: .image)
        let output = formatter.format(results: [result])
        
        XCTAssertTrue(output.contains("1"))
    }
    
    func testFormatJSON() {
        let formatter = QueryFormatter(format: .json, level: .study)
        
        let attributes: [Tag: Data] = [
            .patientName: "SMITH^JOHN".data(using: .utf8)!,
            .patientID: "12345".data(using: .utf8)!,
            .studyDate: "20240215".data(using: .utf8)!
        ]
        
        let result = GenericQueryResult(attributes: attributes, level: .study)
        let output = formatter.format(results: [result])
        
        XCTAssertTrue(output.contains("SMITH^JOHN"))
        XCTAssertTrue(output.contains("12345"))
        XCTAssertTrue(output.contains("20240215"))
        XCTAssertTrue(output.contains("["))
        XCTAssertTrue(output.contains("]"))
    }
    
    func testFormatCSV() {
        let formatter = QueryFormatter(format: .csv, level: .study)
        
        let attributes: [Tag: Data] = [
            .patientName: "SMITH^JOHN".data(using: .utf8)!,
            .patientID: "12345".data(using: .utf8)!
        ]
        
        let result = GenericQueryResult(attributes: attributes, level: .study)
        let output = formatter.format(results: [result])
        
        XCTAssertTrue(output.contains("SMITH^JOHN"))
        XCTAssertTrue(output.contains("12345"))
        XCTAssertTrue(output.contains(","))
    }
    
    func testFormatCSVWithSpecialCharacters() {
        let formatter = QueryFormatter(format: .csv, level: .study)
        
        let attributes: [Tag: Data] = [
            .patientName: "SMITH, JOHN".data(using: .utf8)!, // Contains comma
            .studyDescription: "CT \"CHEST\"".data(using: .utf8)! // Contains quotes
        ]
        
        let result = GenericQueryResult(attributes: attributes, level: .study)
        let output = formatter.format(results: [result])
        
        // CSV should escape commas and quotes
        XCTAssertTrue(output.contains("\"SMITH, JOHN\""))
        XCTAssertTrue(output.contains("\"\""))
    }
    
    func testFormatCompactPatient() {
        let formatter = QueryFormatter(format: .compact, level: .patient)
        
        let attributes: [Tag: Data] = [
            .patientName: "SMITH^JOHN".data(using: .utf8)!,
            .patientID: "12345".data(using: .utf8)!,
            .patientBirthDate: "19800101".data(using: .utf8)!
        ]
        
        let result = GenericQueryResult(attributes: attributes, level: .patient)
        let output = formatter.format(results: [result])
        
        XCTAssertTrue(output.contains("SMITH^JOHN"))
        XCTAssertTrue(output.contains("12345"))
        XCTAssertTrue(output.contains("19800101"))
        XCTAssertTrue(output.contains(" | "))
    }
    
    func testFormatCompactStudy() {
        let formatter = QueryFormatter(format: .compact, level: .study)
        
        let attributes: [Tag: Data] = [
            .patientName: "DOE^JANE".data(using: .utf8)!,
            .patientID: "67890".data(using: .utf8)!,
            .studyDate: "20240215".data(using: .utf8)!,
            .studyDescription: "MR BRAIN".data(using: .utf8)!,
            .studyInstanceUID: "1.2.3.4.5".data(using: .utf8)!
        ]
        
        let result = GenericQueryResult(attributes: attributes, level: .study)
        let output = formatter.format(results: [result])
        
        XCTAssertTrue(output.contains("DOE^JANE"))
        XCTAssertTrue(output.contains("67890"))
        XCTAssertTrue(output.contains("20240215"))
        XCTAssertTrue(output.contains("MR BRAIN"))
        XCTAssertTrue(output.contains("1.2.3.4.5"))
        XCTAssertTrue(output.contains(" | "))
    }
    
    func testDateFormatting() {
        let formatter = QueryFormatter(format: .table, level: .study)
        
        let attributes: [Tag: Data] = [
            .patientName: "TEST".data(using: .utf8)!,
            .studyDate: "20240215".data(using: .utf8)!
        ]
        
        let result = GenericQueryResult(attributes: attributes, level: .study)
        let output = formatter.format(results: [result])
        
        // Date should be formatted as YYYY-MM-DD
        XCTAssertTrue(output.contains("2024-02-15"))
    }
    
    func testMultipleResults() {
        let formatter = QueryFormatter(format: .table, level: .patient)
        
        let attributes1: [Tag: Data] = [
            .patientName: "SMITH^JOHN".data(using: .utf8)!,
            .patientID: "001".data(using: .utf8)!
        ]
        
        let attributes2: [Tag: Data] = [
            .patientName: "DOE^JANE".data(using: .utf8)!,
            .patientID: "002".data(using: .utf8)!
        ]
        
        let result1 = GenericQueryResult(attributes: attributes1, level: .patient)
        let result2 = GenericQueryResult(attributes: attributes2, level: .patient)
        
        let output = formatter.format(results: [result1, result2])
        
        XCTAssertTrue(output.contains("SMITH^JOHN"))
        XCTAssertTrue(output.contains("DOE^JANE"))
        XCTAssertTrue(output.contains("Total: 2 patient(s)"))
    }
}

// MARK: - Output Format Tests

final class OutputFormatTests: XCTestCase {
    
    func testOutputFormatRawValue() {
        XCTAssertEqual(OutputFormat.table.rawValue, "table")
        XCTAssertEqual(OutputFormat.json.rawValue, "json")
        XCTAssertEqual(OutputFormat.csv.rawValue, "csv")
        XCTAssertEqual(OutputFormat.compact.rawValue, "compact")
    }
    
    func testOutputFormatFromString() {
        XCTAssertEqual(OutputFormat(rawValue: "table"), .table)
        XCTAssertEqual(OutputFormat(rawValue: "json"), .json)
        XCTAssertEqual(OutputFormat(rawValue: "csv"), .csv)
        XCTAssertEqual(OutputFormat(rawValue: "compact"), .compact)
        XCTAssertNil(OutputFormat(rawValue: "invalid"))
    }
}

// MARK: - Integration Test Placeholders

final class QueryExecutorIntegrationTests: XCTestCase {
    
    // Note: These tests require a live PACS server and are marked as disabled
    // They serve as documentation for how to test with a real server
    
    func testDisabled_QueryRealPACSServer() async throws {
        throw XCTSkip("Requires live PACS server for testing")
        
        // Example of how this would be tested with a real server:
        /*
        let executor = QueryExecutor(
            host: "pacs.example.com",
            port: 11112,
            callingAE: "TEST_SCU",
            calledAE: "PACS",
            timeout: 30
        )
        
        let queryKeys = QueryKeys(level: .study)
            .patientName("TEST*")
            .requestStudyDate()
        
        let results = try await executor.executeQuery(
            level: .study,
            queryKeys: queryKeys
        )
        
        XCTAssertGreaterThanOrEqual(results.count, 0)
        */
    }
    
    func testDisabled_HandleConnectionTimeout() async throws {
        throw XCTSkip("Requires network testing infrastructure")
        
        // Example of how timeout would be tested:
        /*
        let executor = QueryExecutor(
            host: "10.255.255.1", // Non-routable IP
            port: 11112,
            callingAE: "TEST_SCU",
            calledAE: "PACS",
            timeout: 5
        )
        
        let queryKeys = QueryKeys(level: .study)
        
        do {
            _ = try await executor.executeQuery(level: .study, queryKeys: queryKeys)
            XCTFail("Should have timed out")
        } catch {
            // Expected timeout error
        }
        */
    }
}

// MARK: - Hierarchical-model warnings (PS3.4 C.4.1.2.1)

final class DICOMQueryParentLevelFilterTests: XCTestCase {

    func testSeriesLevelPatientFilterProducesWarningAndIsNotSentAsKey() throws {
        var query = DICOMQuery()
        query.level = .series
        query.studyUid = "1.2.3"
        query.patientName = "DOE*"
        query.studyDate = "20240101"

        let warning = try XCTUnwrap(query.parentLevelFilterWarning())
        XCTAssertTrue(warning.contains("Patient Name"))
        XCTAssertTrue(warning.contains("Study Date"))
        XCTAssertTrue(warning.contains("C.4.1.2.1"))

        // The filters are not emitted as matching keys at SERIES level, and the
        // parent-level return keys are absent without --include-parent-keys.
        let keys = query.buildQueryKeys()
        XCTAssertFalse(keys.keys.contains { $0.tag == .patientName })
        XCTAssertFalse(keys.keys.contains { $0.tag == .studyDate })
        XCTAssertTrue(keys.keys.contains { $0.tag == .studyInstanceUID && $0.value == "1.2.3" })
    }

    func testIncludeParentKeysFlagAddsReturnKeys() throws {
        var query = DICOMQuery()
        query.level = .instance
        query.studyUid = "1.2.3"
        query.seriesUid = "1.2.3.4"
        query.includeParentKeys = true
        let keys = query.buildQueryKeys()
        XCTAssertTrue(keys.keys.contains { $0.tag == .patientName && $0.value.isEmpty })
        XCTAssertTrue(keys.keys.contains { $0.tag == .modality && $0.value.isEmpty })
        XCTAssertNil(query.parentLevelFilterWarning())
    }

    func testStudyLevelFiltersProduceNoWarning() {
        var query = DICOMQuery()
        query.level = .study
        query.patientName = "DOE*"
        XCTAssertNil(query.parentLevelFilterWarning())
    }
}
