import XCTest
import DICOMCore
@testable import DICOMNetwork

final class StorageSCPTests: XCTestCase {
    
    // MARK: - StorageSCPConfiguration Tests
    
    func testStorageSCPConfigurationDefaults() throws {
        let aeTitle = try AETitle("MY_SCP")
        
        let config = StorageSCPConfiguration(aeTitle: aeTitle)
        
        XCTAssertEqual(config.aeTitle.value, "MY_SCP")
        XCTAssertEqual(config.port, dicomAlternativePort)
        XCTAssertEqual(config.maxPDUSize, defaultMaxPDUSize)
        XCTAssertEqual(config.implementationClassUID, StorageSCPConfiguration.defaultImplementationClassUID)
        XCTAssertEqual(config.implementationVersionName, StorageSCPConfiguration.defaultImplementationVersionName)
        XCTAssertEqual(config.maxConcurrentAssociations, 10)
        XCTAssertNil(config.acceptedSOPClasses)
        XCTAssertNil(config.acceptedTransferSyntaxes)
        XCTAssertNil(config.callingAEWhitelist)
        XCTAssertNil(config.callingAEBlacklist)
    }
    
    func testStorageSCPConfigurationCustomValues() throws {
        let aeTitle = try AETitle("CUSTOM_SCP")
        let sopClasses: Set<String> = ["1.2.840.10008.5.1.4.1.1.2"]
        let transferSyntaxes: Set<String> = ["1.2.840.10008.1.2.1"]
        let whitelist: Set<String> = ["ALLOWED_SCU"]
        let blacklist: Set<String> = ["BLOCKED_SCU"]
        
        let config = StorageSCPConfiguration(
            aeTitle: aeTitle,
            port: 5000,
            maxPDUSize: 32768,
            implementationClassUID: "1.2.3.4.5",
            implementationVersionName: "TEST_V1",
            maxConcurrentAssociations: 5,
            acceptedSOPClasses: sopClasses,
            acceptedTransferSyntaxes: transferSyntaxes,
            callingAEWhitelist: whitelist,
            callingAEBlacklist: blacklist
        )
        
        XCTAssertEqual(config.aeTitle.value, "CUSTOM_SCP")
        XCTAssertEqual(config.port, 5000)
        XCTAssertEqual(config.maxPDUSize, 32768)
        XCTAssertEqual(config.implementationClassUID, "1.2.3.4.5")
        XCTAssertEqual(config.implementationVersionName, "TEST_V1")
        XCTAssertEqual(config.maxConcurrentAssociations, 5)
        XCTAssertEqual(config.acceptedSOPClasses, sopClasses)
        XCTAssertEqual(config.acceptedTransferSyntaxes, transferSyntaxes)
        XCTAssertEqual(config.callingAEWhitelist, whitelist)
        XCTAssertEqual(config.callingAEBlacklist, blacklist)
    }
    
    func testStorageSCPConfigurationEffectiveSOPClasses() throws {
        let aeTitle = try AETitle("TEST_SCP")
        
        // With nil, should return common SOP Classes
        let config1 = StorageSCPConfiguration(aeTitle: aeTitle)
        XCTAssertEqual(config1.effectiveSOPClasses, StorageSCPConfiguration.commonStorageSOPClasses)
        
        // With custom, should return custom
        let custom: Set<String> = ["1.2.3.4.5"]
        let config2 = StorageSCPConfiguration(aeTitle: aeTitle, acceptedSOPClasses: custom)
        XCTAssertEqual(config2.effectiveSOPClasses, custom)
    }
    
    func testStorageSCPConfigurationEffectiveTransferSyntaxes() throws {
        let aeTitle = try AETitle("TEST_SCP")
        
        // With nil, should return common transfer syntaxes
        let config1 = StorageSCPConfiguration(aeTitle: aeTitle)
        XCTAssertEqual(config1.effectiveTransferSyntaxes, StorageSCPConfiguration.commonTransferSyntaxes)
        
        // With custom, should return custom
        let custom: Set<String> = ["1.2.840.10008.1.2.1"]
        let config2 = StorageSCPConfiguration(aeTitle: aeTitle, acceptedTransferSyntaxes: custom)
        XCTAssertEqual(config2.effectiveTransferSyntaxes, custom)
    }
    
    func testStorageSCPConfigurationCallingAEAllowed_NoLists() throws {
        let aeTitle = try AETitle("TEST_SCP")
        let config = StorageSCPConfiguration(aeTitle: aeTitle)
        
        // With no whitelist or blacklist, all should be allowed
        XCTAssertTrue(config.isCallingAEAllowed("ANY_SCU"))
        XCTAssertTrue(config.isCallingAEAllowed("OTHER_SCU"))
    }
    
    func testStorageSCPConfigurationCallingAEAllowed_WhitelistOnly() throws {
        let aeTitle = try AETitle("TEST_SCP")
        let whitelist: Set<String> = ["ALLOWED_SCU", "ANOTHER_ALLOWED"]
        let config = StorageSCPConfiguration(aeTitle: aeTitle, callingAEWhitelist: whitelist)
        
        XCTAssertTrue(config.isCallingAEAllowed("ALLOWED_SCU"))
        XCTAssertTrue(config.isCallingAEAllowed("ANOTHER_ALLOWED"))
        XCTAssertFalse(config.isCallingAEAllowed("NOT_IN_LIST"))
    }
    
    func testStorageSCPConfigurationCallingAEAllowed_BlacklistOnly() throws {
        let aeTitle = try AETitle("TEST_SCP")
        let blacklist: Set<String> = ["BLOCKED_SCU"]
        let config = StorageSCPConfiguration(aeTitle: aeTitle, callingAEBlacklist: blacklist)
        
        XCTAssertFalse(config.isCallingAEAllowed("BLOCKED_SCU"))
        XCTAssertTrue(config.isCallingAEAllowed("ANY_OTHER"))
    }
    
    func testStorageSCPConfigurationCallingAEAllowed_BlacklistTakesPrecedence() throws {
        let aeTitle = try AETitle("TEST_SCP")
        let whitelist: Set<String> = ["ALLOWED_SCU", "BLOCKED_BUT_WHITELISTED"]
        let blacklist: Set<String> = ["BLOCKED_BUT_WHITELISTED"]
        let config = StorageSCPConfiguration(
            aeTitle: aeTitle,
            callingAEWhitelist: whitelist,
            callingAEBlacklist: blacklist
        )
        
        XCTAssertTrue(config.isCallingAEAllowed("ALLOWED_SCU"))
        XCTAssertFalse(config.isCallingAEAllowed("BLOCKED_BUT_WHITELISTED"))
    }
    
    func testStorageSCPConfigurationMaxConcurrentAssociationsMinimum() throws {
        let aeTitle = try AETitle("TEST_SCP")
        
        // Zero should become 1
        let config1 = StorageSCPConfiguration(aeTitle: aeTitle, maxConcurrentAssociations: 0)
        XCTAssertEqual(config1.maxConcurrentAssociations, 1)
        
        // Negative should become 1
        let config2 = StorageSCPConfiguration(aeTitle: aeTitle, maxConcurrentAssociations: -5)
        XCTAssertEqual(config2.maxConcurrentAssociations, 1)
    }
    
    func testStorageSCPConfigurationCommonSOPClasses() {
        let sopClasses = StorageSCPConfiguration.commonStorageSOPClasses
        
        // Check that it includes major storage SOP Classes
        XCTAssertTrue(sopClasses.contains("1.2.840.10008.5.1.4.1.1.2")) // CT Image Storage
        XCTAssertTrue(sopClasses.contains("1.2.840.10008.5.1.4.1.1.4")) // MR Image Storage
        XCTAssertTrue(sopClasses.contains("1.2.840.10008.5.1.4.1.1.7")) // Secondary Capture
        XCTAssertTrue(sopClasses.contains("1.2.840.10008.1.1")) // Verification
    }
    
    func testStorageSCPConfigurationCommonTransferSyntaxes() {
        let transferSyntaxes = StorageSCPConfiguration.commonTransferSyntaxes
        
        // Check that it includes major transfer syntaxes
        XCTAssertTrue(transferSyntaxes.contains("1.2.840.10008.1.2")) // Implicit VR LE
        XCTAssertTrue(transferSyntaxes.contains("1.2.840.10008.1.2.1")) // Explicit VR LE
        XCTAssertTrue(transferSyntaxes.contains("1.2.840.10008.1.2.4.50")) // JPEG Baseline
    }
    
    func testStorageSCPConfigurationHashable() throws {
        let aeTitle = try AETitle("TEST_SCP")
        
        let config1 = StorageSCPConfiguration(aeTitle: aeTitle, port: 11112)
        let config2 = StorageSCPConfiguration(aeTitle: aeTitle, port: 11112)
        let config3 = StorageSCPConfiguration(aeTitle: aeTitle, port: 11113)
        
        XCTAssertEqual(config1, config2)
        XCTAssertNotEqual(config1, config3)
    }
    
    // MARK: - ReceivedFile Tests
    
    func testReceivedFileCreation() {
        let data = Data([0x00, 0x01, 0x02, 0x03])
        let timestamp = Date()
        
        let file = ReceivedFile(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9",
            dataSetData: data,
            transferSyntaxUID: "1.2.840.10008.1.2.1",
            callingAETitle: "SENDING_SCU",
            timestamp: timestamp
        )
        
        XCTAssertEqual(file.sopClassUID, "1.2.840.10008.5.1.4.1.1.2")
        XCTAssertEqual(file.sopInstanceUID, "1.2.3.4.5.6.7.8.9")
        XCTAssertEqual(file.dataSetData, data)
        XCTAssertEqual(file.transferSyntaxUID, "1.2.840.10008.1.2.1")
        XCTAssertEqual(file.callingAETitle, "SENDING_SCU")
        XCTAssertEqual(file.timestamp, timestamp)
        XCTAssertNil(file.filePath)
        XCTAssertEqual(file.dataSize, 4)
    }
    
    func testReceivedFileWithFilePath() {
        let data = Data([0x00])
        let url = URL(fileURLWithPath: "/tmp/test.dcm")
        
        var file = ReceivedFile(
            sopClassUID: "1.2.3",
            sopInstanceUID: "4.5.6",
            dataSetData: data,
            transferSyntaxUID: "1.2.840.10008.1.2",
            callingAETitle: "SCU"
        )
        file.filePath = url
        
        XCTAssertEqual(file.filePath, url)
    }
    
    func testReceivedFileDescription() {
        let data = Data(repeating: 0x00, count: 1024)
        
        let file = ReceivedFile(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9",
            dataSetData: data,
            transferSyntaxUID: "1.2.840.10008.1.2.1",
            callingAETitle: "SENDING_SCU"
        )
        
        let description = file.description
        XCTAssertTrue(description.contains("1.2.3.4.5.6.7.8.9"))
        XCTAssertTrue(description.contains("SENDING_SCU"))
    }
    
    // MARK: - AssociationInfo Tests
    
    func testAssociationInfoCreation() {
        let info = AssociationInfo(
            callingAETitle: "CALLING",
            calledAETitle: "CALLED",
            remoteHost: "192.168.1.100",
            remotePort: 11112,
            proposedSOPClasses: ["1.2.840.10008.5.1.4.1.1.2"],
            proposedTransferSyntaxes: ["1.2.840.10008.1.2.1"]
        )
        
        XCTAssertEqual(info.callingAETitle, "CALLING")
        XCTAssertEqual(info.calledAETitle, "CALLED")
        XCTAssertEqual(info.remoteHost, "192.168.1.100")
        XCTAssertEqual(info.remotePort, 11112)
        XCTAssertEqual(info.proposedSOPClasses, ["1.2.840.10008.5.1.4.1.1.2"])
        XCTAssertEqual(info.proposedTransferSyntaxes, ["1.2.840.10008.1.2.1"])
    }
    
    // MARK: - StorageServerEvent Tests
    
    func testStorageServerEventStarted() {
        let event = StorageServerEvent.started(port: 11112)
        
        if case .started(let port) = event {
            XCTAssertEqual(port, 11112)
        } else {
            XCTFail("Expected started event")
        }
    }
    
    func testStorageServerEventStopped() {
        let event = StorageServerEvent.stopped
        
        if case .stopped = event {
            // Success
        } else {
            XCTFail("Expected stopped event")
        }
    }
    
    func testStorageServerEventAssociationEstablished() {
        let info = AssociationInfo(
            callingAETitle: "SCU",
            calledAETitle: "SCP",
            remoteHost: "localhost",
            remotePort: 1234,
            proposedSOPClasses: [],
            proposedTransferSyntaxes: []
        )
        let event = StorageServerEvent.associationEstablished(info)
        
        if case .associationEstablished(let eventInfo) = event {
            XCTAssertEqual(eventInfo.callingAETitle, "SCU")
        } else {
            XCTFail("Expected associationEstablished event")
        }
    }
    
    func testStorageServerEventAssociationReleased() {
        let event = StorageServerEvent.associationReleased(callingAE: "RELEASED_SCU")
        
        if case .associationReleased(let ae) = event {
            XCTAssertEqual(ae, "RELEASED_SCU")
        } else {
            XCTFail("Expected associationReleased event")
        }
    }
    
    func testStorageServerEventAssociationRejected() {
        let event = StorageServerEvent.associationRejected(callingAE: "REJECTED_SCU", reason: "Not allowed")
        
        if case .associationRejected(let ae, let reason) = event {
            XCTAssertEqual(ae, "REJECTED_SCU")
            XCTAssertEqual(reason, "Not allowed")
        } else {
            XCTFail("Expected associationRejected event")
        }
    }
    
    func testStorageServerEventFileReceived() {
        let file = ReceivedFile(
            sopClassUID: "1.2.3",
            sopInstanceUID: "4.5.6",
            dataSetData: Data(),
            transferSyntaxUID: "1.2.840.10008.1.2",
            callingAETitle: "SCU"
        )
        let event = StorageServerEvent.fileReceived(file)
        
        if case .fileReceived(let receivedFile) = event {
            XCTAssertEqual(receivedFile.sopInstanceUID, "4.5.6")
        } else {
            XCTFail("Expected fileReceived event")
        }
    }
    
    func testStorageServerEventError() {
        let error = DICOMNetworkError.connectionFailed("Test error")
        let event = StorageServerEvent.error(error)
        
        if case .error(let receivedError) = event {
            XCTAssertNotNil(receivedError)
        } else {
            XCTFail("Expected error event")
        }
    }
    
    // MARK: - DefaultStorageHandler Tests
    
    func testDefaultStorageHandlerCreation() async {
        let url = URL(fileURLWithPath: "/tmp/dicom_storage")
        let handler = DefaultStorageHandler(storageDirectory: url)
        
        // Handler should accept all associations by default
        let info = AssociationInfo(
            callingAETitle: "ANY",
            calledAETitle: "SCP",
            remoteHost: "localhost",
            remotePort: 1234,
            proposedSOPClasses: [],
            proposedTransferSyntaxes: []
        )
        let shouldAccept = await handler.shouldAcceptAssociation(from: info)
        XCTAssertTrue(shouldAccept)
        
        // Handler should accept all files by default
        let willReceive = await handler.willReceive(sopClassUID: "1.2.3", sopInstanceUID: "4.5.6")
        XCTAssertTrue(willReceive)
    }
    
    func testDefaultStorageHandlerCreationWithHierarchy() {
        let url = URL(fileURLWithPath: "/tmp/dicom_storage")
        let handler = DefaultStorageHandler(storageDirectory: url, organizeByHierarchy: true)
        
        // Just verify creation succeeds
        XCTAssertNotNil(handler)
    }
    
    #if canImport(Network)
    // MARK: - DICOMStorageServer Tests (Basic)
    
    func testDICOMStorageServerCreation() async throws {
        let aeTitle = try AETitle("TEST_SCP")
        let config = StorageSCPConfiguration(aeTitle: aeTitle, port: 12345)
        let handler = DefaultStorageHandler(storageDirectory: URL(fileURLWithPath: "/tmp/test"))
        
        let server = DICOMStorageServer(configuration: config, delegate: handler)
        
        let isRunning = await server.isRunning
        XCTAssertFalse(isRunning)
        
        let count = await server.activeAssociationCount
        XCTAssertEqual(count, 0)
    }
    
    func testDICOMStorageServerStartStop() async throws {
        let aeTitle = try AETitle("TEST_SCP")
        // Let the OS select an available ephemeral port for this lifecycle test.
        let config = StorageSCPConfiguration(aeTitle: aeTitle, port: 0)
        let handler = DefaultStorageHandler(storageDirectory: URL(fileURLWithPath: "/tmp/test"))
        
        let server = DICOMStorageServer(configuration: config, delegate: handler)
        
        // Start server
        try await server.start()
        
        var isRunning = await server.isRunning
        XCTAssertTrue(isRunning)
        
        // Stop server
        await server.stop()
        
        isRunning = await server.isRunning
        XCTAssertFalse(isRunning)
    }
    
    func testDICOMStorageServerDoubleStartFails() async throws {
        let aeTitle = try AETitle("TEST_SCP")
        let config = StorageSCPConfiguration(aeTitle: aeTitle, port: 0)
        let handler = DefaultStorageHandler(storageDirectory: URL(fileURLWithPath: "/tmp/test"))
        
        let server = DICOMStorageServer(configuration: config, delegate: handler)
        
        // Start server
        try await server.start()
        
        // Second start should fail
        do {
            try await server.start()
            XCTFail("Expected error on double start")
        } catch let error as DICOMNetworkError {
            if case .invalidState = error {
                // Expected
            } else {
                XCTFail("Expected invalidState error")
            }
        }
        
        // Cleanup
        await server.stop()
    }
    #endif
}
