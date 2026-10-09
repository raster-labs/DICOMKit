import XCTest
import Foundation
@testable import DICOMKit
@testable import DICOMCore
@testable import DICOMNetwork
@testable import dicom_server

final class DICOMServerTests: XCTestCase {
    
    // MARK: - Server Configuration Tests
    
    func test_ServerConfiguration_Initialization() {
        let config = ServerConfiguration(
            aeTitle: "TEST_PACS",
            port: 11112,
            dataDirectory: "/tmp/test-data",
            databaseURL: "sqlite:///tmp/test.db",
            maxConcurrentConnections: 10,
            maxPDUSize: 16384,
            allowedCallingAETitles: ["SCU1", "SCU2"],
            blockedCallingAETitles: ["OLD_SCU"],
            enableTLS: false,
            verbose: true
        )
        
        XCTAssertEqual(config.aeTitle, "TEST_PACS")
        XCTAssertEqual(config.port, 11112)
        XCTAssertEqual(config.dataDirectory, "/tmp/test-data")
        XCTAssertEqual(config.maxConcurrentConnections, 10)
        XCTAssertTrue(config.verbose)
    }
    
    func test_ServerConfiguration_DefaultValues() {
        let config = ServerConfiguration(
            aeTitle: "DEFAULT_PACS",
            port: 11112,
            dataDirectory: "/tmp/default",
            databaseURL: ""
        )
        
        XCTAssertEqual(config.aeTitle, "DEFAULT_PACS")
        XCTAssertEqual(config.maxConcurrentConnections, 10)
        XCTAssertEqual(config.maxPDUSize, 16384)
        XCTAssertNil(config.allowedCallingAETitles)
        XCTAssertFalse(config.enableTLS)
        XCTAssertFalse(config.verbose)
    }
    
    func test_ServerConfiguration_JSONEncoding() throws {
        let config = ServerConfiguration(
            aeTitle: "TEST_PACS",
            port: 11112,
            dataDirectory: "/tmp/test",
            databaseURL: "sqlite:///tmp/test.db",
            maxConcurrentConnections: 15,
            maxPDUSize: 32768,
            enableTLS: true,
            verbose: false
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ServerConfiguration.self, from: data)
        
        XCTAssertEqual(decoded.aeTitle, config.aeTitle)
        XCTAssertEqual(decoded.port, config.port)
        XCTAssertEqual(decoded.maxConcurrentConnections, config.maxConcurrentConnections)
        XCTAssertEqual(decoded.enableTLS, config.enableTLS)
    }
    
    func test_ServerConfiguration_SaveAndLoad() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let configPath = tempDir.appendingPathComponent("test-config.json").path
        
        let config = ServerConfiguration(
            aeTitle: "SAVE_TEST",
            port: 11112,
            dataDirectory: "/tmp/save-test",
            databaseURL: "sqlite:///tmp/save-test.db"
        )
        
        // Save
        try config.save(to: configPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath))
        
        // Load
        let loaded = try ServerConfiguration.load(from: configPath)
        XCTAssertEqual(loaded.aeTitle, config.aeTitle)
        XCTAssertEqual(loaded.port, config.port)
        
        // Cleanup
        try? FileManager.default.removeItem(atPath: configPath)
    }
    
    // MARK: - Server Error Tests
    
    func test_ServerError_Description() {
        let error1 = ServerError.invalidConfiguration("test message")
        XCTAssertTrue(error1.description.contains("Invalid configuration"))
        XCTAssertTrue(error1.description.contains("test message"))
        
        let error2 = ServerError.serverNotRunning
        XCTAssertTrue(error2.description.contains("not running"))
        
        let error3 = ServerError.portInUse(11112)
        XCTAssertTrue(error3.description.contains("11112"))
        XCTAssertTrue(error3.description.contains("already in use"))
        
        let error4 = ServerError.databaseError("connection failed")
        XCTAssertTrue(error4.description.contains("Database error"))
        
        let error5 = ServerError.storageError("disk full")
        XCTAssertTrue(error5.description.contains("Storage error"))
    }
    
    // MARK: - Storage Manager Tests
    
    func test_StorageManager_Initialization() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("storage-test")
        let storage = try StorageManager(dataDirectory: tempDir.path)
        
        // Verify directory was created
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func test_StorageManager_StoreAndRetrieve() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("storage-store-test-\(UUID().uuidString)")
        let storage = try StorageManager(dataDirectory: tempDir.path)
        
        // Create a test DICOM file
        let dicomFile = try createTestDICOMFile()
        
        // Store
        let filePath = try await storage.store(file: dicomFile)
        XCTAssertFalse(filePath.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath))
        
        // Retrieve
        let sopInstanceUID = dicomFile.dataSet.string(for: .sopInstanceUID)!
        let retrieved = try await storage.retrieve(sopInstanceUID: sopInstanceUID)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.dataSet.string(for: .sopInstanceUID), sopInstanceUID)
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func test_StorageManager_Statistics() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("storage-stats-test-\(UUID().uuidString)")
        let storage = try StorageManager(dataDirectory: tempDir.path)
        
        // Store some files
        for i in 0..<3 {
            let file = try createTestDICOMFileWithUID("1.2.3.4.5.6.7.8.\(i)")
            _ = try await storage.store(file: file)
        }
        
        // Check statistics
        let stats = try await storage.statistics()
        XCTAssertEqual(stats.totalFiles, 3)
        XCTAssertGreaterThan(stats.totalSize, 0)
        XCTAssertGreaterThan(stats.totalSizeMB, 0)
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func test_StorageManager_RetrieveNonExistent() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("storage-retrieve-test-\(UUID().uuidString)")
        let storage = try StorageManager(dataDirectory: tempDir.path)
        
        let result = try await storage.retrieve(sopInstanceUID: "999.999.999")
        XCTAssertNil(result)
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - Database Manager Tests
    
    func test_DatabaseManager_SQLiteInitialization() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test-\(UUID().uuidString).db").path
        let connectionString = "sqlite://\(dbPath)"
        
        let database = try DatabaseManager(connectionString: connectionString)
        XCTAssertNotNil(database)
        
        // Cleanup
        try? FileManager.default.removeItem(atPath: dbPath)
    }
    
    func test_DatabaseManager_PostgreSQLInitialization() throws {
        let connectionString = "postgres://user:pass@localhost/testdb"
        
        let database = try DatabaseManager(connectionString: connectionString)
        XCTAssertNotNil(database)
    }
    
    func test_DatabaseManager_InvalidConnectionString() {
        let connectionString = "invalid://connection"
        
        XCTAssertThrowsError(try DatabaseManager(connectionString: connectionString)) { error in
            XCTAssertTrue(error is ServerError)
            if case .databaseError(let message) = error as! ServerError {
                XCTAssertTrue(message.contains("Unsupported database type"))
            }
        }
    }
    
    // MARK: - DICOM Metadata Tests
    
    func test_DICOMMetadata_Codable() throws {
        let metadata = DICOMMetadata(
            patientID: "PAT001",
            patientName: "DOE^JOHN",
            studyInstanceUID: "1.2.3.4.5",
            studyDate: "20260215",
            studyDescription: "CT Chest",
            seriesInstanceUID: "1.2.3.4.5.6",
            seriesNumber: "1",
            modality: "CT",
            sopInstanceUID: "1.2.3.4.5.6.7",
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            instanceNumber: "1",
            filePath: "/tmp/test.dcm"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(metadata)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DICOMMetadata.self, from: data)
        
        XCTAssertEqual(decoded.patientID, metadata.patientID)
        XCTAssertEqual(decoded.studyInstanceUID, metadata.studyInstanceUID)
        XCTAssertEqual(decoded.sopInstanceUID, metadata.sopInstanceUID)
        XCTAssertEqual(decoded.filePath, metadata.filePath)
    }
    
    // MARK: - Storage Statistics Tests
    
    func test_StorageStatistics_SizeConversion() {
        let stats = StorageStatistics(totalFiles: 100, totalSize: 1048576)
        XCTAssertEqual(stats.totalFiles, 100)
        XCTAssertEqual(stats.totalSize, 1048576)
        XCTAssertEqual(stats.totalSizeMB, 1.0, accuracy: 0.01)
    }
    
    func test_StorageStatistics_ZeroSize() {
        let stats = StorageStatistics(totalFiles: 0, totalSize: 0)
        XCTAssertEqual(stats.totalFiles, 0)
        XCTAssertEqual(stats.totalSize, 0)
        XCTAssertEqual(stats.totalSizeMB, 0.0)
    }
    
    // MARK: - Helper Methods
    
    private func createTestDICOMFile() throws -> DICOMFile {
        var fileMetaInformation = DataSet()
        var dataSet = DataSet()
        
        // File Meta Information
        fileMetaInformation.setString("1.2.840.10008.1.2.1", for: .transferSyntaxUID, vr: .UI)
        fileMetaInformation.setString("1.2.840.10008.5.1.4.1.1.2", for: .mediaStorageSOPClassUID, vr: .UI)
        fileMetaInformation.setString("1.2.3.4.5.6.7.8.9", for: .mediaStorageSOPInstanceUID, vr: .UI)
        fileMetaInformation.setString("1.2.826.0.1.3680043.10.1078", for: .implementationClassUID, vr: .UI)
        fileMetaInformation.setString("DICOMKit_Test", for: .implementationVersionName, vr: .SH)
        
        // Patient Information
        dataSet.setString("TEST001", for: .patientID, vr: .LO)
        dataSet.setString("DOE^JOHN", for: .patientName, vr: .PN)
        dataSet.setString("19800115", for: .patientBirthDate, vr: .DA)
        dataSet.setString("M", for: .patientSex, vr: .CS)
        
        // Study Information
        dataSet.setString("1.2.840.113619.2.62.994044785528.114289542805", for: .studyInstanceUID, vr: .UI)
        dataSet.setString("ACC12345", for: .accessionNumber, vr: .SH)
        dataSet.setString("CT Chest", for: .studyDescription, vr: .LO)
        dataSet.setString("20260215", for: .studyDate, vr: .DA)
        dataSet.setString("120000", for: .studyTime, vr: .TM)
        
        // Series Information
        dataSet.setString("1.2.840.113619.2.62.994044785528.20070822161025697420", for: .seriesInstanceUID, vr: .UI)
        dataSet.setString("CT", for: .modality, vr: .CS)
        dataSet.setString("1", for: .seriesNumber, vr: .IS)
        
        // SOP Information
        dataSet.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        dataSet.setString("1.2.3.4.5.6.7.8.9", for: .sopInstanceUID, vr: .UI)
        dataSet.setString("1", for: .instanceNumber, vr: .IS)
        
        return DICOMFile(fileMetaInformation: fileMetaInformation, dataSet: dataSet)
    }
    
    private func createTestDICOMFileWithUID(_ sopInstanceUID: String) throws -> DICOMFile {
        var fileMetaInformation = DataSet()
        var dataSet = DataSet()
        
        fileMetaInformation.setString("1.2.840.10008.1.2.1", for: .transferSyntaxUID, vr: .UI)
        fileMetaInformation.setString("1.2.840.10008.5.1.4.1.1.2", for: .mediaStorageSOPClassUID, vr: .UI)
        fileMetaInformation.setString(sopInstanceUID, for: .mediaStorageSOPInstanceUID, vr: .UI)
        fileMetaInformation.setString("1.2.826.0.1.3680043.10.1078", for: .implementationClassUID, vr: .UI)
        fileMetaInformation.setString("DICOMKit_Test", for: .implementationVersionName, vr: .SH)
        
        dataSet.setString("TEST001", for: .patientID, vr: .LO)
        dataSet.setString("DOE^JOHN", for: .patientName, vr: .PN)
        dataSet.setString("1.2.840.113619.2.62.994044785528.114289542805", for: .studyInstanceUID, vr: .UI)
        dataSet.setString("1.2.840.113619.2.62.994044785528.20070822161025697420", for: .seriesInstanceUID, vr: .UI)
        dataSet.setString("CT", for: .modality, vr: .CS)
        dataSet.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        dataSet.setString(sopInstanceUID, for: .sopInstanceUID, vr: .UI)
        
        return DICOMFile(fileMetaInformation: fileMetaInformation, dataSet: dataSet)
    }
    
    // MARK: - Database Query Tests
    
    func test_DatabaseManager_IndexAndQuery() async throws {
        let db = try DatabaseManager(connectionString: "")
        try await db.initialize()
        
        // Create test metadata
        let metadata1 = DICOMMetadata(
            patientID: "PAT001",
            patientName: "DOE^JOHN",
            studyInstanceUID: "1.2.3.4",
            studyDate: "20260101",
            studyDescription: "CT Chest",
            seriesInstanceUID: "1.2.3.4.5",
            seriesNumber: "1",
            modality: "CT",
            sopInstanceUID: "1.2.3.4.5.6",
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            instanceNumber: "1",
            filePath: "/tmp/file1.dcm"
        )
        
        // Index
        try await db.index(filePath: "/tmp/file1.dcm", metadata: metadata1)
        
        // Query at study level
        var queryDS = DataSet()
        queryDS.setString("STUDY", for: .queryRetrieveLevel, vr: .CS)
        queryDS.setString("PAT001", for: .patientID, vr: .LO)
        // PS3.4 C.4.1.1.3.2: only requested keys are returned, so ask for the unique key
        queryDS.setString("", for: .studyInstanceUID, vr: .UI)
        
        let results = try await db.queryForFind(queryDataset: queryDS, level: .study)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].string(for: .studyInstanceUID), "1.2.3.4")
    }
    
    func test_DatabaseManager_PatientLevelQuery() async throws {
        let db = try DatabaseManager(connectionString: "")
        try await db.initialize()
        
        // Index multiple patients
        for i in 1...3 {
            let metadata = DICOMMetadata(
                patientID: "PAT00\(i)",
                patientName: "PATIENT\(i)^TEST",
                studyInstanceUID: "1.2.3.\(i)",
                studyDate: "20260101",
                studyDescription: "Test Study",
                seriesInstanceUID: "1.2.3.\(i).1",
                seriesNumber: "1",
                modality: "CT",
                sopInstanceUID: "1.2.3.\(i).1.1",
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                instanceNumber: "1",
                filePath: "/tmp/file\(i).dcm"
            )
            try await db.index(filePath: "/tmp/file\(i).dcm", metadata: metadata)
        }
        
        // Query all patients
        var queryDS = DataSet()
        queryDS.setString("PATIENT", for: .queryRetrieveLevel, vr: .CS)
        
        let results = try await db.queryForFind(queryDataset: queryDS, level: .patient)
        XCTAssertEqual(results.count, 3)
    }
    
    func test_DatabaseManager_WildcardQuery() async throws {
        let db = try DatabaseManager(connectionString: "")
        try await db.initialize()
        
        // Index patients
        let patients = ["SMITH^JOHN", "SMITH^JANE", "JONES^BOB"]
        for (i, name) in patients.enumerated() {
            let metadata = DICOMMetadata(
                patientID: "PAT00\(i+1)",
                patientName: name,
                studyInstanceUID: "1.2.3.\(i+1)",
                studyDate: "20260101",
                studyDescription: "Test",
                seriesInstanceUID: "1.2.3.\(i+1).1",
                seriesNumber: "1",
                modality: "CT",
                sopInstanceUID: "1.2.3.\(i+1).1.1",
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                instanceNumber: "1",
                filePath: "/tmp/file\(i+1).dcm"
            )
            try await db.index(filePath: "/tmp/file\(i+1).dcm", metadata: metadata)
        }
        
        // Query with wildcard
        var queryDS = DataSet()
        queryDS.setString("PATIENT", for: .queryRetrieveLevel, vr: .CS)
        queryDS.setString("SMITH*", for: .patientName, vr: .PN)
        
        let results = try await db.queryForFind(queryDataset: queryDS, level: .patient)
        XCTAssertEqual(results.count, 2)
    }
    
    func test_DatabaseManager_SeriesLevelQuery() async throws {
        let db = try DatabaseManager(connectionString: "")
        try await db.initialize()
        
        // Index series
        for i in 1...3 {
            let metadata = DICOMMetadata(
                patientID: "PAT001",
                patientName: "TEST^PATIENT",
                studyInstanceUID: "1.2.3.4",
                studyDate: "20260101",
                studyDescription: "Test Study",
                seriesInstanceUID: "1.2.3.4.\(i)",
                seriesNumber: "\(i)",
                modality: i == 1 ? "CT" : "MR",
                sopInstanceUID: "1.2.3.4.\(i).1",
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                instanceNumber: "1",
                filePath: "/tmp/file\(i).dcm"
            )
            try await db.index(filePath: "/tmp/file\(i).dcm", metadata: metadata)
        }
        
        // Query CT series only
        var queryDS = DataSet()
        queryDS.setString("SERIES", for: .queryRetrieveLevel, vr: .CS)
        queryDS.setString("1.2.3.4", for: .studyInstanceUID, vr: .UI)
        queryDS.setString("CT", for: .modality, vr: .CS)
        
        let results = try await db.queryForFind(queryDataset: queryDS, level: .series)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].string(for: .modality), "CT")
    }
    
    func test_DatabaseManager_InstanceLevelQuery() async throws {
        let db = try DatabaseManager(connectionString: "")
        try await db.initialize()
        
        // Index instances
        for i in 1...5 {
            let metadata = DICOMMetadata(
                patientID: "PAT001",
                patientName: "TEST^PATIENT",
                studyInstanceUID: "1.2.3.4",
                studyDate: "20260101",
                studyDescription: "Test Study",
                seriesInstanceUID: "1.2.3.4.5",
                seriesNumber: "1",
                modality: "CT",
                sopInstanceUID: "1.2.3.4.5.\(i)",
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                instanceNumber: "\(i)",
                filePath: "/tmp/file\(i).dcm"
            )
            try await db.index(filePath: "/tmp/file\(i).dcm", metadata: metadata)
        }
        
        // Query specific series
        var queryDS = DataSet()
        queryDS.setString("IMAGE", for: .queryRetrieveLevel, vr: .CS)
        queryDS.setString("1.2.3.4.5", for: .seriesInstanceUID, vr: .UI)
        
        let results = try await db.queryForFind(queryDataset: queryDS, level: .image)
        XCTAssertEqual(results.count, 5)
    }
    
    func test_DatabaseManager_Delete() async throws {
        let db = try DatabaseManager(connectionString: "")
        try await db.initialize()
        
        // Index
        let metadata = DICOMMetadata(
            patientID: "PAT001",
            patientName: "TEST^PATIENT",
            studyInstanceUID: "1.2.3.4",
            studyDate: "20260101",
            studyDescription: "Test Study",
            seriesInstanceUID: "1.2.3.4.5",
            seriesNumber: "1",
            modality: "CT",
            sopInstanceUID: "1.2.3.4.5.6",
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            instanceNumber: "1",
            filePath: "/tmp/file1.dcm"
        )
        try await db.index(filePath: "/tmp/file1.dcm", metadata: metadata)
        
        // Query - should find
        var queryDS = DataSet()
        queryDS.setString("IMAGE", for: .queryRetrieveLevel, vr: .CS)
        queryDS.setString("1.2.3.4.5.6", for: .sopInstanceUID, vr: .UI)
        
        var results = try await db.queryForFind(queryDataset: queryDS, level: .image)
        XCTAssertEqual(results.count, 1)
        
        // Delete
        try await db.delete(sopInstanceUID: "1.2.3.4.5.6")
        
        // Query again - should not find
        results = try await db.queryForFind(queryDataset: queryDS, level: .image)
        XCTAssertEqual(results.count, 0)
    }
    
    // MARK: - StorageManager DIMSE Integration Tests
    
    func test_StorageManager_StoreDataSet() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("storage-dataset-test-\(UUID().uuidString)")
        let storage = try StorageManager(dataDirectory: tempDir.path)
        
        // Create test dataset
        var dataSet = DataSet()
        dataSet.setString("PAT001", for: .patientID, vr: .LO)
        dataSet.setString("DOE^JOHN", for: .patientName, vr: .PN)
        dataSet.setString("1.2.3.4", for: .studyInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4.5", for: .seriesInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4.5.6", for: .sopInstanceUID, vr: .UI)
        dataSet.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        
        // Store
        let filePath = try await storage.storeReceived(
            dataSetData: ServerProtocol.encodeDataSet(dataSet, transferSyntaxUID: "1.2.840.10008.1.2.1"),
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.4.5.6",
            transferSyntaxUID: "1.2.840.10008.1.2.1", serverAETitle: "TEST_SCP", callingAETitle: "TEST_SCU"
        ).filePath
        XCTAssertFalse(filePath.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath))
        XCTAssertTrue(filePath.contains("1.2.3.4"))
        XCTAssertTrue(filePath.contains("1.2.3.4.5"))
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func test_StorageManager_DirectoryStructure() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("storage-structure-test-\(UUID().uuidString)")
        let storage = try StorageManager(dataDirectory: tempDir.path)
        
        // Create test dataset
        var dataSet = DataSet()
        dataSet.setString("STUDY_UID_123", for: .studyInstanceUID, vr: .UI)
        dataSet.setString("SERIES_UID_456", for: .seriesInstanceUID, vr: .UI)
        dataSet.setString("INSTANCE_UID_789", for: .sopInstanceUID, vr: .UI)
        
        // Store
        let filePath = try await storage.storeReceived(
            dataSetData: ServerProtocol.encodeDataSet(dataSet, transferSyntaxUID: "1.2.840.10008.1.2.1"),
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "INSTANCE_UID_789",
            transferSyntaxUID: "1.2.840.10008.1.2.1", serverAETitle: "TEST_SCP", callingAETitle: nil
        ).filePath
        
        // Verify directory structure
        XCTAssertTrue(filePath.contains("STUDY_UID_123"))
        XCTAssertTrue(filePath.contains("SERIES_UID_456"))
        XCTAssertTrue(filePath.hasSuffix("INSTANCE_UID_789.dcm"))
        
        // Verify study directory exists
        let studyDir = tempDir.appendingPathComponent("STUDY_UID_123").path
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: studyDir, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        
        // Verify series directory exists
        let seriesDir = tempDir.appendingPathComponent("STUDY_UID_123/SERIES_UID_456").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: seriesDir, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - C-MOVE Tests (Phase B)
    
    func test_DatabaseManager_QueryForRetrieve_StudyLevel() async throws {
        let db = try DatabaseManager(connectionString: "")
        try await db.initialize()
        
        // Index test files
        let metadata1 = DICOMMetadata(
            patientID: "PAT001",
            patientName: "DOE^JOHN",
            studyInstanceUID: "1.2.3.4",
            studyDate: "20260101",
            studyDescription: "CT Chest",
            seriesInstanceUID: "1.2.3.4.5",
            seriesNumber: "1",
            modality: "CT",
            sopInstanceUID: "1.2.3.4.5.6",
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            instanceNumber: "1",
            filePath: "/tmp/test1.dcm"
        )
        
        let metadata2 = DICOMMetadata(
            patientID: "PAT001",
            patientName: "DOE^JOHN",
            studyInstanceUID: "1.2.3.4",
            studyDate: "20260101",
            studyDescription: "CT Chest",
            seriesInstanceUID: "1.2.3.4.5",
            seriesNumber: "1",
            modality: "CT",
            sopInstanceUID: "1.2.3.4.5.7",
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            instanceNumber: "2",
            filePath: "/tmp/test2.dcm"
        )
        
        try await db.index(filePath: "/tmp/test1.dcm", metadata: metadata1)
        try await db.index(filePath: "/tmp/test2.dcm", metadata: metadata2)
        
        // Query for retrieval at study level
        var queryDS = DataSet()
        queryDS.setString("STUDY", for: .queryRetrieveLevel, vr: .CS)
        queryDS.setString("1.2.3.4", for: .studyInstanceUID, vr: .UI)
        
        let instances = try await db.queryForRetrieve(queryDataset: queryDS, level: .study)
        XCTAssertEqual(instances.count, 2)
        XCTAssertTrue(instances.contains { $0.sopInstanceUID == "1.2.3.4.5.6" })
        XCTAssertTrue(instances.contains { $0.sopInstanceUID == "1.2.3.4.5.7" })
    }
    
    func test_DatabaseManager_QueryForRetrieve_SeriesLevel() async throws {
        let db = try DatabaseManager(connectionString: "")
        try await db.initialize()
        
        // Index test files from two series
        let metadata1 = DICOMMetadata(
            patientID: "PAT001",
            patientName: "DOE^JOHN",
            studyInstanceUID: "1.2.3.4",
            studyDate: "20260101",
            studyDescription: "CT Chest",
            seriesInstanceUID: "1.2.3.4.5",
            seriesNumber: "1",
            modality: "CT",
            sopInstanceUID: "1.2.3.4.5.6",
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            instanceNumber: "1",
            filePath: "/tmp/test1.dcm"
        )
        
        let metadata2 = DICOMMetadata(
            patientID: "PAT001",
            patientName: "DOE^JOHN",
            studyInstanceUID: "1.2.3.4",
            studyDate: "20260101",
            studyDescription: "CT Chest",
            seriesInstanceUID: "1.2.3.4.6",
            seriesNumber: "2",
            modality: "CT",
            sopInstanceUID: "1.2.3.4.6.7",
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            instanceNumber: "1",
            filePath: "/tmp/test2.dcm"
        )
        
        try await db.index(filePath: "/tmp/test1.dcm", metadata: metadata1)
        try await db.index(filePath: "/tmp/test2.dcm", metadata: metadata2)
        
        // Query for specific series
        var queryDS = DataSet()
        queryDS.setString("SERIES", for: .queryRetrieveLevel, vr: .CS)
        queryDS.setString("1.2.3.4.5", for: .seriesInstanceUID, vr: .UI)
        
        let instances = try await db.queryForRetrieve(queryDataset: queryDS, level: .series)
        XCTAssertEqual(instances.count, 1)
        XCTAssertEqual(instances[0].sopInstanceUID, "1.2.3.4.5.6")
    }
    
    func test_DatabaseManager_QueryForRetrieve_InstanceLevel() async throws {
        let db = try DatabaseManager(connectionString: "")
        try await db.initialize()
        
        // Index test file
        let metadata = DICOMMetadata(
            patientID: "PAT001",
            patientName: "DOE^JOHN",
            studyInstanceUID: "1.2.3.4",
            studyDate: "20260101",
            studyDescription: "CT Chest",
            seriesInstanceUID: "1.2.3.4.5",
            seriesNumber: "1",
            modality: "CT",
            sopInstanceUID: "1.2.3.4.5.6",
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            instanceNumber: "1",
            filePath: "/tmp/test1.dcm"
        )
        
        try await db.index(filePath: "/tmp/test1.dcm", metadata: metadata)
        
        // Query for specific instance
        var queryDS = DataSet()
        queryDS.setString("IMAGE", for: .queryRetrieveLevel, vr: .CS)
        queryDS.setString("1.2.3.4.5.6", for: .sopInstanceUID, vr: .UI)
        
        let instances = try await db.queryForRetrieve(queryDataset: queryDS, level: .image)
        XCTAssertEqual(instances.count, 1)
        XCTAssertEqual(instances[0].sopInstanceUID, "1.2.3.4.5.6")
        XCTAssertEqual(instances[0].filePath, "/tmp/test1.dcm")
    }
    
    func test_DatabaseManager_QueryForRetrieve_PatientLevel() async throws {
        let db = try DatabaseManager(connectionString: "")
        try await db.initialize()
        
        // Index test files for patient
        for i in 1...3 {
            let metadata = DICOMMetadata(
                patientID: "PAT001",
                patientName: "DOE^JOHN",
                studyInstanceUID: "1.2.3.\(i)",
                studyDate: "20260101",
                studyDescription: "Study \(i)",
                seriesInstanceUID: "1.2.3.\(i).5",
                seriesNumber: "1",
                modality: "CT",
                sopInstanceUID: "1.2.3.\(i).5.6",
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                instanceNumber: "1",
                filePath: "/tmp/test\(i).dcm"
            )
            try await db.index(filePath: "/tmp/test\(i).dcm", metadata: metadata)
        }
        
        // Query for patient
        var queryDS = DataSet()
        queryDS.setString("PATIENT", for: .queryRetrieveLevel, vr: .CS)
        queryDS.setString("PAT001", for: .patientID, vr: .LO)
        
        let instances = try await db.queryForRetrieve(queryDataset: queryDS, level: .patient)
        XCTAssertEqual(instances.count, 3)
    }
    
    func test_DatabaseManager_QueryForRetrieve_NoMatches() async throws {
        let db = try DatabaseManager(connectionString: "")
        try await db.initialize()
        
        // Query without any indexed data
        var queryDS = DataSet()
        queryDS.setString("STUDY", for: .queryRetrieveLevel, vr: .CS)
        queryDS.setString("999.999.999", for: .studyInstanceUID, vr: .UI)
        
        let instances = try await db.queryForRetrieve(queryDataset: queryDS, level: .study)
        XCTAssertEqual(instances.count, 0)
    }
    
    func test_DatabaseManager_QueryForRetrieve_Wildcard() async throws {
        let db = try DatabaseManager(connectionString: "")
        try await db.initialize()
        
        // Index test files
        for i in 1...3 {
            let metadata = DICOMMetadata(
                patientID: "PAT00\(i)",
                patientName: "PATIENT\(i)^TEST",
                studyInstanceUID: "1.2.3.\(i)",
                studyDate: "20260101",
                studyDescription: "Study \(i)",
                seriesInstanceUID: "1.2.3.\(i).5",
                seriesNumber: "1",
                modality: "CT",
                sopInstanceUID: "1.2.3.\(i).5.6",
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                instanceNumber: "1",
                filePath: "/tmp/test\(i).dcm"
            )
            try await db.index(filePath: "/tmp/test\(i).dcm", metadata: metadata)
        }
        
        // Query with wildcard
        var queryDS = DataSet()
        queryDS.setString("PATIENT", for: .queryRetrieveLevel, vr: .CS)
        queryDS.setString("PAT*", for: .patientID, vr: .LO)
        
        let instances = try await db.queryForRetrieve(queryDataset: queryDS, level: .patient)
        XCTAssertEqual(instances.count, 3)
    }
    
    // MARK: - C-GET Tests (Phase B)
    
    func test_CGetResponse_Creation() {
        let response = CGetResponse(
            messageIDBeingRespondedTo: 1,
            affectedSOPClassUID: "1.2.840.10008.5.1.4.1.2.2.3",
            status: .success,
            remaining: 0,
            completed: 5,
            failed: 0,
            warning: 0,
            presentationContextID: 1
        )
        
        XCTAssertEqual(response.messageIDBeingRespondedTo, 1)
        XCTAssertEqual(response.affectedSOPClassUID, "1.2.840.10008.5.1.4.1.2.2.3")
        XCTAssertTrue(response.status.isSuccess)
        XCTAssertEqual(response.numberOfCompletedSuboperations, 5)
        XCTAssertEqual(response.numberOfFailedSuboperations, 0)
    }
    
    func test_CGetResponse_PendingStatus() {
        let response = CGetResponse(
            messageIDBeingRespondedTo: 1,
            affectedSOPClassUID: "1.2.840.10008.5.1.4.1.2.2.3",
            status: .pending(warningOptionalKeys: false),
            remaining: 3,
            completed: 2,
            failed: 0,
            warning: 0,
            presentationContextID: 1
        )
        
        XCTAssertTrue(response.status.isPending)
        XCTAssertEqual(response.numberOfRemainingSuboperations, 3)
        XCTAssertEqual(response.numberOfCompletedSuboperations, 2)
    }
    
    func test_CMoveResponse_Creation() {
        let response = CMoveResponse(
            messageIDBeingRespondedTo: 1,
            affectedSOPClassUID: "1.2.840.10008.5.1.4.1.2.2.2",
            status: .success,
            remaining: 0,
            completed: 10,
            failed: 0,
            warning: 0,
            presentationContextID: 1
        )
        
        XCTAssertEqual(response.messageIDBeingRespondedTo, 1)
        XCTAssertEqual(response.affectedSOPClassUID, "1.2.840.10008.5.1.4.1.2.2.2")
        XCTAssertTrue(response.status.isSuccess)
        XCTAssertEqual(response.numberOfCompletedSuboperations, 10)
    }
    
    func test_CMoveResponse_WithFailures() {
        let response = CMoveResponse(
            messageIDBeingRespondedTo: 1,
            affectedSOPClassUID: "1.2.840.10008.5.1.4.1.2.2.2",
            status: .warningCoercionOfDataElements,
            remaining: 0,
            completed: 8,
            failed: 2,
            warning: 0,
            presentationContextID: 1
        )
        
        XCTAssertEqual(response.numberOfCompletedSuboperations, 8)
        XCTAssertEqual(response.numberOfFailedSuboperations, 2)
        XCTAssertTrue(response.status.isWarning)
    }
    
    func test_CMoveRequest_MoveDestination() {
        let request = CMoveRequest(
            messageID: 1,
            affectedSOPClassUID: "1.2.840.10008.5.1.4.1.2.2.2",
            moveDestination: "DEST_AE",
            priority: .medium,
            presentationContextID: 1
        )
        
        XCTAssertEqual(request.messageID, 1)
        XCTAssertEqual(request.moveDestination, "DEST_AE")
        XCTAssertEqual(request.affectedSOPClassUID, "1.2.840.10008.5.1.4.1.2.2.2")
    }
    
    func test_CGetRequest_Creation() {
        let request = CGetRequest(
            messageID: 1,
            affectedSOPClassUID: "1.2.840.10008.5.1.4.1.2.2.3",
            priority: .high,
            presentationContextID: 1
        )
        
        XCTAssertEqual(request.messageID, 1)
        XCTAssertEqual(request.affectedSOPClassUID, "1.2.840.10008.5.1.4.1.2.2.3")
        XCTAssertEqual(request.priority, .high)
    }
    
    // MARK: - Phase D.5: ServerLogger Tests
    
    func test_LogLevel_Comparison() {
        XCTAssertTrue(LogLevel.debug < LogLevel.info)
        XCTAssertTrue(LogLevel.info < LogLevel.warning)
        XCTAssertTrue(LogLevel.warning < LogLevel.error)
        XCTAssertFalse(LogLevel.error < LogLevel.debug)
    }
    
    func test_ServerLogger_Initialization() async throws {
        let logger = try ServerLogger(minimumLevel: .debug, includeTimestamp: true, includeLevel: true)
        
        // Logger should be initialized without errors
        await logger.debug("Test debug message")
        await logger.info("Test info message")
        await logger.warning("Test warning message")
        await logger.error("Test error message")
    }
    
    func test_ServerLogger_MinimumLevel_Filtering() async throws {
        // Create logger with minimum level of WARNING
        let logger = try ServerLogger(minimumLevel: .warning, includeTimestamp: false, includeLevel: true)
        
        // These should be filtered out (below WARNING level)
        await logger.debug("Debug message - should not appear")
        await logger.info("Info message - should not appear")
        
        // These should appear (WARNING and above)
        await logger.warning("Warning message - should appear")
        await logger.error("Error message - should appear")
    }
    
    func test_ServerLogger_FileLogging() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let logPath = tempDir.appendingPathComponent("test-server-\(UUID().uuidString).log").path
        
        let logger = try ServerLogger(
            minimumLevel: .info,
            includeTimestamp: true,
            includeLevel: true,
            logFilePath: logPath
        )
        
        await logger.info("Test message 1")
        await logger.warning("Test message 2")
        await logger.error("Test message 3")
        await logger.flush()
        
        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: logPath))
        
        // Verify file content
        let content = try String(contentsOfFile: logPath)
        XCTAssertTrue(content.contains("[INFO] Test message 1"))
        XCTAssertTrue(content.contains("[WARNING] Test message 2"))
        XCTAssertTrue(content.contains("[ERROR] Test message 3"))
        
        // Cleanup
        try? FileManager.default.removeItem(atPath: logPath)
    }
    
    func test_ServerLogger_ContextLogging() async throws {
        let logger = try ServerLogger(minimumLevel: .info, includeTimestamp: false, includeLevel: true)
        
        await logger.info("Connection established", context: "C-ECHO")
        await logger.warning("Query timeout", context: "C-FIND")
        await logger.error("Store failed", context: "C-STORE")
    }
    
    func test_ServerLogger_ErrorWithException() async throws {
        let logger = try ServerLogger(minimumLevel: .error, includeTimestamp: false, includeLevel: true)
        
        let testError = NSError(domain: "TestDomain", code: 42, userInfo: [NSLocalizedDescriptionKey: "Test error description"])
        await logger.error("Operation failed", error: testError)
    }
    
    // MARK: - Phase D.5: ServerStatistics Tests
    
    func test_ServerStatistics_ConnectionTracking() async {
        let stats = ServerStatistics()
        
        // Start connection
        await stats.recordConnectionStart()
        var summary = await stats.getSummary()
        XCTAssertEqual(summary.totalConnections, 1)
        XCTAssertEqual(summary.activeConnections, 1)
        
        // Start another connection
        await stats.recordConnectionStart()
        summary = await stats.getSummary()
        XCTAssertEqual(summary.totalConnections, 2)
        XCTAssertEqual(summary.activeConnections, 2)
        
        // End one connection
        await stats.recordConnectionEnd()
        summary = await stats.getSummary()
        XCTAssertEqual(summary.totalConnections, 2)
        XCTAssertEqual(summary.activeConnections, 1)
        
        // Record failure
        await stats.recordConnectionFailure()
        summary = await stats.getSummary()
        XCTAssertEqual(summary.failedConnections, 1)
    }
    
    func test_ServerStatistics_EchoOperations() async {
        let stats = ServerStatistics()
        
        await stats.recordEchoRequest()
        await stats.recordEchoRequest()
        await stats.recordEchoRequest()
        
        let summary = await stats.getSummary()
        XCTAssertEqual(summary.echoRequests, 3)
    }
    
    func test_ServerStatistics_StoreOperations() async {
        let stats = ServerStatistics()
        
        // Record successful stores
        await stats.recordStoreRequest(success: true, bytesReceived: 1024)
        await stats.recordStoreRequest(success: true, bytesReceived: 2048)
        
        // Record failed store
        await stats.recordStoreRequest(success: false)
        
        let summary = await stats.getSummary()
        XCTAssertEqual(summary.storeRequests, 3)
        XCTAssertEqual(summary.successfulStores, 2)
        XCTAssertEqual(summary.failedStores, 1)
        XCTAssertEqual(summary.bytesReceived, 3072)
        XCTAssertEqual(summary.totalStoredInstances, 2)
    }
    
    func test_ServerStatistics_FindOperations() async {
        let stats = ServerStatistics()
        
        await stats.recordFindRequest(success: true)
        await stats.recordFindRequest(success: true)
        await stats.recordFindRequest(success: false)
        
        let summary = await stats.getSummary()
        XCTAssertEqual(summary.findRequests, 3)
        XCTAssertEqual(summary.successfulFinds, 2)
        XCTAssertEqual(summary.failedFinds, 1)
    }
    
    func test_ServerStatistics_MoveOperations() async {
        let stats = ServerStatistics()
        
        await stats.recordMoveRequest(success: true, instancesSent: 10)
        await stats.recordMoveRequest(success: true, instancesSent: 5)
        await stats.recordMoveRequest(success: false)
        
        let summary = await stats.getSummary()
        XCTAssertEqual(summary.moveRequests, 3)
        XCTAssertEqual(summary.successfulMoves, 2)
        XCTAssertEqual(summary.failedMoves, 1)
    }
    
    func test_ServerStatistics_GetOperations() async {
        let stats = ServerStatistics()
        
        await stats.recordGetRequest(success: true, bytesSent: 5000)
        await stats.recordGetRequest(success: true, bytesSent: 10000)
        await stats.recordGetRequest(success: false)
        
        let summary = await stats.getSummary()
        XCTAssertEqual(summary.getRequests, 3)
        XCTAssertEqual(summary.successfulGets, 2)
        XCTAssertEqual(summary.failedGets, 1)
        XCTAssertEqual(summary.bytesSent, 15000)
    }
    
    func test_ServerStatistics_Reset() async {
        let stats = ServerStatistics()
        
        // Record some operations
        await stats.recordConnectionStart()
        await stats.recordEchoRequest()
        await stats.recordStoreRequest(success: true, bytesReceived: 1000)
        await stats.recordFindRequest(success: true)
        
        // Verify stats are recorded
        var summary = await stats.getSummary()
        XCTAssertGreaterThan(summary.totalConnections, 0)
        XCTAssertGreaterThan(summary.echoRequests, 0)
        
        // Reset
        await stats.reset()
        
        // Verify all stats are zero
        summary = await stats.getSummary()
        XCTAssertEqual(summary.totalConnections, 0)
        XCTAssertEqual(summary.activeConnections, 0)
        XCTAssertEqual(summary.echoRequests, 0)
        XCTAssertEqual(summary.storeRequests, 0)
        XCTAssertEqual(summary.findRequests, 0)
        XCTAssertEqual(summary.bytesReceived, 0)
        XCTAssertEqual(summary.bytesSent, 0)
    }
    
    func test_ServerStatistics_FormattedOutput() async {
        let stats = ServerStatistics()
        
        // Record various operations
        await stats.recordConnectionStart()
        await stats.recordEchoRequest()
        await stats.recordStoreRequest(success: true, bytesReceived: 1048576) // 1 MB
        await stats.recordFindRequest(success: true)
        
        let summary = await stats.getSummary()
        let formatted = summary.formatted()
        
        // Verify formatted output contains expected sections
        XCTAssertTrue(formatted.contains("DICOM Server Statistics"))
        XCTAssertTrue(formatted.contains("CONNECTIONS:"))
        XCTAssertTrue(formatted.contains("OPERATIONS:"))
        XCTAssertTrue(formatted.contains("STORAGE:"))
        XCTAssertTrue(formatted.contains("SUCCESS RATES:"))
        XCTAssertTrue(formatted.contains("Total:       1"))
        XCTAssertTrue(formatted.contains("C-ECHO:      1"))
    }
    
    func test_ServerStatistics_Uptime() async {
        let stats = ServerStatistics()
        
        // Wait a tiny bit to ensure uptime is non-zero
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        let summary = await stats.getSummary()
        let statsStartTime = await stats.startTime
        XCTAssertGreaterThan(summary.uptime, 0)
        XCTAssertEqual(summary.startTime.timeIntervalSinceReferenceDate,
                      statsStartTime.timeIntervalSinceReferenceDate,
                      accuracy: 0.1)
    }
    
    func test_StatisticsSummary_BytesFormatting() async {
        let stats = ServerStatistics()
        
        // Test various byte amounts
        await stats.recordStoreRequest(success: true, bytesReceived: 500) // 500 B
        await stats.recordStoreRequest(success: true, bytesReceived: 1024) // 1 KB
        await stats.recordGetRequest(success: true, bytesSent: 1048576) // 1 MB
        
        let summary = await stats.getSummary()
        let formatted = summary.formatted()
        
        // Verify bytes are formatted with appropriate units
        XCTAssertTrue(formatted.contains("Received:"))
        XCTAssertTrue(formatted.contains("Sent:"))
    }
}
