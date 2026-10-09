import XCTest
@testable import DICOMKit
@testable import DICOMCore
@testable import DICOMDictionary
import Foundation

/// Tests for dicom-dcmdir tool
///
/// Tests the DICOMDIR creation, validation, and management functionality.
final class DICOMDcmdirTests: XCTestCase {
    
    var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        // Create temp directory for test files
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DICOMDcmdirTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    /// Create a minimal DICOM file for testing
    func createMinimalDICOMFile(
        patientName: String = "TEST^PATIENT",
        patientID: String = "12345",
        studyUID: String = "1.2.3.4.5",
        seriesUID: String = "1.2.3.4.5.6",
        instanceUID: String? = nil,
        modality: String = "CT"
    ) throws -> Data {
        let instanceUIDValue = instanceUID ?? "1.2.3.4.5.6.7.\(UUID().uuidString)"
        
        // Create file meta information
        var fileMeta = DataSet()
        var versionData = Data(count: 2)
        versionData[0] = 0x00
        versionData[1] = 0x01
        fileMeta[.fileMetaInformationVersion] = DataElement.data(tag: .fileMetaInformationVersion, vr: .OB, data: versionData)
        fileMeta[.mediaStorageSOPClassUID] = DataElement.string(tag: .mediaStorageSOPClassUID, vr: .UI, value: "1.2.840.10008.5.1.4.1.1.2")
        fileMeta[.mediaStorageSOPInstanceUID] = DataElement.string(tag: .mediaStorageSOPInstanceUID, vr: .UI, value: instanceUIDValue)
        fileMeta[.transferSyntaxUID] = DataElement.string(tag: .transferSyntaxUID, vr: .UI, value: TransferSyntax.explicitVRLittleEndian.uid)
        fileMeta[.implementationClassUID] = DataElement.string(tag: .implementationClassUID, vr: .UI, value: "1.2.826.0.1.3680043.10.1")
        
        // Create data set
        var dataSet = DataSet()
        dataSet[.sopClassUID] = DataElement.string(tag: .sopClassUID, vr: .UI, value: "1.2.840.10008.5.1.4.1.1.2")
        dataSet[.sopInstanceUID] = DataElement.string(tag: .sopInstanceUID, vr: .UI, value: instanceUIDValue)
        dataSet[.modality] = DataElement.string(tag: .modality, vr: .CS, value: modality)
        dataSet[.patientName] = DataElement.string(tag: .patientName, vr: .PN, value: patientName)
        dataSet[.patientID] = DataElement.string(tag: .patientID, vr: .LO, value: patientID)
        dataSet[.studyInstanceUID] = DataElement.string(tag: .studyInstanceUID, vr: .UI, value: studyUID)
        dataSet[.seriesInstanceUID] = DataElement.string(tag: .seriesInstanceUID, vr: .UI, value: seriesUID)
        dataSet[.studyDate] = DataElement.string(tag: .studyDate, vr: .DA, value: "20240101")
        dataSet[.studyTime] = DataElement.string(tag: .studyTime, vr: .TM, value: "120000")
        dataSet[.seriesNumber] = DataElement.string(tag: .seriesNumber, vr: .IS, value: "1")
        dataSet[.instanceNumber] = DataElement.string(tag: .instanceNumber, vr: .IS, value: "1")
        
        let file = DICOMFile(fileMetaInformation: fileMeta, dataSet: dataSet)
        return try file.write()
    }
    
    // MARK: - DICOMDirectory.Builder Tests
    
    func testBuilderCreation() throws {
        let builder = DICOMDirectory.Builder(fileSetID: "TEST_SET", profile: .standardGeneralCD)
        let directory = builder.build()
        
        XCTAssertEqual(directory.fileSetID, "TEST_SET")
        XCTAssertEqual(directory.profile, .standardGeneralCD)
        XCTAssertTrue(directory.rootRecords.isEmpty)
        XCTAssertTrue(directory.isConsistent)
    }
    
    func testBuilderAddSingleFile() throws {
        var builder = DICOMDirectory.Builder(fileSetID: "TEST_SET", profile: .standardGeneralCD)
        
        let fileData = try createMinimalDICOMFile()
        let dicomFile = try DICOMFile.read(from: fileData)
        
        try builder.addFile(dicomFile, relativePath: ["IMAGES", "IM001.dcm"])
        let directory = builder.build()
        
        XCTAssertEqual(directory.rootRecords.count, 1)
        XCTAssertEqual(directory.rootRecords[0].recordType, .patient)
        
        let stats = directory.statistics()
        XCTAssertEqual(stats.patientCount, 1)
        XCTAssertEqual(stats.studyCount, 1)
        XCTAssertEqual(stats.seriesCount, 1)
        XCTAssertEqual(stats.imageCount, 1)
    }
    
    func testBuilderAddMultipleFilesOnePatient() throws {
        var builder = DICOMDirectory.Builder(fileSetID: "TEST_SET", profile: .standardGeneralCD)
        
        // Add 3 images for same patient, same study, same series
        for i in 1...3 {
            let fileData = try createMinimalDICOMFile(
                patientName: "DOE^JOHN",
                patientID: "P001",
                studyUID: "1.2.3.4.5",
                seriesUID: "1.2.3.4.5.6",
                instanceUID: "1.2.3.4.5.6.7.\(i)"
            )
            let dicomFile = try DICOMFile.read(from: fileData)
            try builder.addFile(dicomFile, relativePath: ["IMAGES", "IM00\(i).dcm"])
        }
        
        let directory = builder.build()
        let stats = directory.statistics()
        
        XCTAssertEqual(stats.patientCount, 1)
        XCTAssertEqual(stats.studyCount, 1)
        XCTAssertEqual(stats.seriesCount, 1)
        XCTAssertEqual(stats.imageCount, 3)
    }
    
    func testBuilderAddMultiplePatientsStudiesSeries() throws {
        var builder = DICOMDirectory.Builder(fileSetID: "TEST_SET", profile: .standardGeneralCD)
        
        // Patient 1: 2 studies, each with 1 series
        for studyIndex in 1...2 {
            let fileData = try createMinimalDICOMFile(
                patientName: "PATIENT^ONE",
                patientID: "P001",
                studyUID: "1.2.3.4.\(studyIndex)",
                seriesUID: "1.2.3.4.\(studyIndex).1"
            )
            let dicomFile = try DICOMFile.read(from: fileData)
            try builder.addFile(dicomFile, relativePath: ["P001", "ST\(studyIndex)", "IM001.dcm"])
        }
        
        // Patient 2: 1 study, 2 series
        for seriesIndex in 1...2 {
            let fileData = try createMinimalDICOMFile(
                patientName: "PATIENT^TWO",
                patientID: "P002",
                studyUID: "1.2.3.5",
                seriesUID: "1.2.3.5.\(seriesIndex)"
            )
            let dicomFile = try DICOMFile.read(from: fileData)
            try builder.addFile(dicomFile, relativePath: ["P002", "ST1", "SE\(seriesIndex)", "IM001.dcm"])
        }
        
        let directory = builder.build()
        let stats = directory.statistics()
        
        XCTAssertEqual(stats.patientCount, 2)
        XCTAssertEqual(stats.studyCount, 3) // 2 + 1
        XCTAssertEqual(stats.seriesCount, 4) // 2 + 2
        XCTAssertEqual(stats.imageCount, 4)
    }
    
    // MARK: - DICOMDIRWriter Tests
    
    func testWriteEmptyDICOMDIR() throws {
        let builder = DICOMDirectory.Builder(fileSetID: "EMPTY_SET", profile: .standardGeneralCD)
        let directory = builder.build()
        
        let data = try DICOMDIRWriter.write(directory)
        
        XCTAssertFalse(data.isEmpty)
        XCTAssertTrue(data.count > 128) // At least DICOM preamble and magic
        
        // Verify DICOM magic
        let magic = data[128..<132]
        XCTAssertEqual(String(data: magic, encoding: .ascii), "DICM")
    }
    
    func testWriteAndReadRoundTrip() throws {
        var builder = DICOMDirectory.Builder(fileSetID: "ROUNDTRIP_TEST", profile: .standardGeneralCD)
        
        let fileData = try createMinimalDICOMFile(
            patientName: "ROUNDTRIP^PATIENT",
            patientID: "RT001"
        )
        let dicomFile = try DICOMFile.read(from: fileData)
        try builder.addFile(dicomFile, relativePath: ["IMAGES", "IM001.dcm"])
        
        let originalDirectory = builder.build()
        
        // Write to data
        let writtenData = try DICOMDIRWriter.write(originalDirectory)
        
        // Read back
        let readDirectory = try DICOMDIRReader.read(from: writtenData)
        
        // Verify
        XCTAssertEqual(readDirectory.fileSetID, originalDirectory.fileSetID)
        XCTAssertEqual(readDirectory.isConsistent, originalDirectory.isConsistent)
        
        let originalStats = originalDirectory.statistics()
        let readStats = readDirectory.statistics()
        
        XCTAssertEqual(readStats.patientCount, originalStats.patientCount)
        XCTAssertEqual(readStats.studyCount, originalStats.studyCount)
        XCTAssertEqual(readStats.seriesCount, originalStats.seriesCount)
        XCTAssertEqual(readStats.imageCount, originalStats.imageCount)
    }
    
    func testWriteToFile() throws {
        var builder = DICOMDirectory.Builder(fileSetID: "FILE_TEST", profile: .standardGeneralCD)
        
        let fileData = try createMinimalDICOMFile()
        let dicomFile = try DICOMFile.read(from: fileData)
        try builder.addFile(dicomFile, relativePath: ["IM001.dcm"])
        
        let directory = builder.build()
        let outputURL = tempDirectory.appendingPathComponent("DICOMDIR")
        
        try DICOMDIRWriter.write(directory, to: outputURL)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        
        // Verify can read back
        let readDirectory = try DICOMDIRReader.read(from: outputURL)
        XCTAssertEqual(readDirectory.fileSetID, "FILE_TEST")
    }
    
    // MARK: - DICOMDIRReader Tests
    
    func testReadInvalidData() throws {
        let invalidData = Data(repeating: 0xFF, count: 1000)
        
        XCTAssertThrowsError(try DICOMDIRReader.read(from: invalidData)) { error in
            XCTAssertTrue(error is DICOMError)
        }
    }
    
    func testReadNonDICOMDIRFile() throws {
        // Create a regular DICOM file (not DICOMDIR)
        let regularFileData = try createMinimalDICOMFile()
        
        XCTAssertThrowsError(try DICOMDIRReader.read(from: regularFileData)) { error in
            if let dicomError = error as? DICOMError {
                switch dicomError {
                case .parsingFailed(let message):
                    XCTAssertTrue(message.contains("Not a valid DICOMDIR"))
                default:
                    XCTFail("Expected parsingFailed error")
                }
            }
        }
    }
    
    // MARK: - DICOMDirectory Tests
    
    func testDirectoryStatistics() throws {
        var builder = DICOMDirectory.Builder(fileSetID: "STATS_TEST", profile: .standardGeneralCD)
        
        // Create hierarchical structure: 2 patients, 3 studies total, 5 series total, 10 images total
        for patientIndex in 1...2 {
            for studyIndex in 1...2 {
                let seriesCount = patientIndex == 1 ? 2 : 3
                for seriesIndex in 1...seriesCount {
                    let imageCount = 2
                    for imageIndex in 1...imageCount {
                        let fileData = try createMinimalDICOMFile(
                            patientName: "PATIENT^\(patientIndex)",
                            patientID: "P00\(patientIndex)",
                            studyUID: "1.2.3.\(patientIndex).\(studyIndex)",
                            seriesUID: "1.2.3.\(patientIndex).\(studyIndex).\(seriesIndex)",
                            instanceUID: "1.2.3.\(patientIndex).\(studyIndex).\(seriesIndex).\(imageIndex)"
                        )
                        let dicomFile = try DICOMFile.read(from: fileData)
                        try builder.addFile(dicomFile, relativePath: ["P00\(patientIndex)", "ST\(studyIndex)", "SE\(seriesIndex)", "IM\(imageIndex).dcm"])
                    }
                }
            }
        }
        
        let directory = builder.build()
        let stats = directory.statistics()
        
        XCTAssertEqual(stats.patientCount, 2)
        XCTAssertEqual(stats.studyCount, 4) // 2 patients × 2 studies
        XCTAssertEqual(stats.seriesCount, 10) // P1: 2×2=4, P2: 2×3=6
        XCTAssertEqual(stats.imageCount, 20) // 10 series × 2 images
    }
    
    func testDirectoryValidation() throws {
        var builder = DICOMDirectory.Builder(fileSetID: "VALID_TEST", profile: .standardGeneralCD)
        
        let fileData = try createMinimalDICOMFile()
        let dicomFile = try DICOMFile.read(from: fileData)
        try builder.addFile(dicomFile, relativePath: ["IM001.dcm"])
        
        let directory = builder.build()
        
        // Validate should not throw for a properly built directory
        XCTAssertNoThrow(try directory.validate(checkFileExistence: false))
    }
    
    func testDirectoryConsistencyFlag() throws {
        let builder = DICOMDirectory.Builder(fileSetID: "CONSISTENT_TEST", profile: .standardGeneralCD)
        let directory = builder.build()
        
        XCTAssertTrue(directory.isConsistent)
    }
    
    func testDirectoryProfileTypes() throws {
        let profiles: [DICOMDIRProfile] = [
            .standardGeneralCD,
            .standardGeneralDVDJPEG,   // STD-GEN-DVD-JPEG, PS3.11 2026a Table H.1-1
            .standardGeneralUSBJPEG    // STD-GEN-USB-JPEG, PS3.11 2026a Table J.1-1
        ]
        
        for profile in profiles {
            let builder = DICOMDirectory.Builder(fileSetID: "PROFILE_TEST", profile: profile)
            let directory = builder.build()
            XCTAssertEqual(directory.profile, profile)
        }
    }
    
    // MARK: - DirectoryRecord Tests
    
    func testRecordHierarchy() throws {
        var builder = DICOMDirectory.Builder(fileSetID: "HIERARCHY_TEST", profile: .standardGeneralCD)
        
        let fileData = try createMinimalDICOMFile()
        let dicomFile = try DICOMFile.read(from: fileData)
        try builder.addFile(dicomFile, relativePath: ["IM001.dcm"])
        
        let directory = builder.build()
        
        // Verify hierarchy: Patient -> Study -> Series -> Image
        XCTAssertEqual(directory.rootRecords.count, 1)
        let patient = directory.rootRecords[0]
        XCTAssertEqual(patient.recordType, .patient)
        XCTAssertEqual(patient.children.count, 1)
        
        let study = patient.children[0]
        XCTAssertEqual(study.recordType, .study)
        XCTAssertEqual(study.children.count, 1)
        
        let series = study.children[0]
        XCTAssertEqual(series.recordType, .series)
        XCTAssertEqual(series.children.count, 1)
        
        let image = series.children[0]
        XCTAssertEqual(image.recordType, .image)
        XCTAssertTrue(image.children.isEmpty)
    }
    
    func testRecordAttributes() throws {
        var builder = DICOMDirectory.Builder(fileSetID: "ATTR_TEST", profile: .standardGeneralCD)
        
        let fileData = try createMinimalDICOMFile(
            patientName: "ATTRIBUTES^TEST",
            patientID: "ATTR001",
            modality: "MR"
        )
        let dicomFile = try DICOMFile.read(from: fileData)
        try builder.addFile(dicomFile, relativePath: ["IM001.dcm"])
        
        let directory = builder.build()
        let patient = directory.rootRecords[0]
        
        // Check patient attributes
        let patientName = patient.attribute(for: .patientName)?.stringValue
        XCTAssertEqual(patientName, "ATTRIBUTES^TEST")
        
        let patientID = patient.attribute(for: .patientID)?.stringValue
        XCTAssertEqual(patientID, "ATTR001")
        
        // Check series modality
        let series = patient.children[0].children[0]
        let modality = series.attribute(for: .modality)?.stringValue
        XCTAssertEqual(modality, "MR")
    }
    
    func testAllRecords() throws {
        var builder = DICOMDirectory.Builder(fileSetID: "ALL_RECORDS_TEST", profile: .standardGeneralCD)
        
        let fileData = try createMinimalDICOMFile()
        let dicomFile = try DICOMFile.read(from: fileData)
        try builder.addFile(dicomFile, relativePath: ["IM001.dcm"])
        
        let directory = builder.build()
        let allRecords = directory.allRecords()
        
        // Should have 4 records: Patient, Study, Series, Image
        XCTAssertEqual(allRecords.count, 4)
        
        let recordTypes = allRecords.map { $0.recordType }
        XCTAssertTrue(recordTypes.contains(.patient))
        XCTAssertTrue(recordTypes.contains(.study))
        XCTAssertTrue(recordTypes.contains(.series))
        XCTAssertTrue(recordTypes.contains(.image))
    }
    
    // MARK: - Error Handling Tests
    
    func testBuilderInvalidFile() throws {
        var builder = DICOMDirectory.Builder(fileSetID: "ERROR_TEST", profile: .standardGeneralCD)
        
        // Create file with missing required tags
        var fileMeta = DataSet()
        var versionData = Data(count: 2)
        versionData[0] = 0x00
        versionData[1] = 0x01
        fileMeta[.fileMetaInformationVersion] = DataElement.data(tag: .fileMetaInformationVersion, vr: .OB, data: versionData)
        
        var dataSet = DataSet()
        dataSet[.patientName] = DataElement.string(tag: .patientName, vr: .PN, value: "TEST")
        // Missing SOP Instance UID, Study UID, Series UID, etc.
        
        let incompleteFile = DICOMFile(fileMetaInformation: fileMeta, dataSet: dataSet)
        
        // Should throw or handle gracefully
        XCTAssertThrowsError(try builder.addFile(incompleteFile, relativePath: ["IM001.dcm"]))
    }
    
    // MARK: - Integration Tests
    
    func testFullWorkflow() throws {
        // Create a directory structure with multiple DICOM files
        let studyDir = tempDirectory.appendingPathComponent("STUDY001")
        try FileManager.default.createDirectory(at: studyDir, withIntermediateDirectories: true)
        
        // Create 5 DICOM files
        for i in 1...5 {
            let fileData = try createMinimalDICOMFile(
                patientName: "WORKFLOW^TEST",
                patientID: "WF001",
                studyUID: "1.2.3.4.5",
                seriesUID: "1.2.3.4.5.6",
                instanceUID: "1.2.3.4.5.6.7.\(i)"
            )
            let fileURL = studyDir.appendingPathComponent("IM00\(i).dcm")
            try fileData.write(to: fileURL)
        }
        
        // Create DICOMDIR
        var builder = DICOMDirectory.Builder(fileSetID: "WORKFLOW_SET", profile: .standardGeneralCD)
        
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(at: studyDir, includingPropertiesForKeys: nil)
        
        for fileURL in files {
            let fileData = try Data(contentsOf: fileURL)
            let dicomFile = try DICOMFile.read(from: fileData)
            let relativePath = [fileURL.lastPathComponent]
            try builder.addFile(dicomFile, relativePath: relativePath)
        }
        
        let directory = builder.build()
        
        // Write DICOMDIR
        let dicomdirURL = studyDir.appendingPathComponent("DICOMDIR")
        try DICOMDIRWriter.write(directory, to: dicomdirURL)
        
        // Read and validate
        let readDirectory = try DICOMDIRReader.read(from: dicomdirURL)
        
        XCTAssertEqual(readDirectory.fileSetID, "WORKFLOW_SET")
        let stats = readDirectory.statistics()
        XCTAssertEqual(stats.imageCount, 5)
        XCTAssertTrue(readDirectory.isConsistent)
        
        try readDirectory.validate(checkFileExistence: false)
    }
}
