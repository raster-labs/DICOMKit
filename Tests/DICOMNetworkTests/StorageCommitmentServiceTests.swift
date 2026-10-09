import XCTest
import DICOMCore
@testable import DICOMNetwork

final class StorageCommitmentServiceTests: XCTestCase {
    
    // MARK: - SOP Class UID Constants Tests
    
    func testStorageCommitmentPushModelSOPClassUID() {
        XCTAssertEqual(storageCommitmentPushModelSOPClassUID, "1.2.840.10008.1.20.1")
    }
    
    func testStorageCommitmentPushModelSOPInstanceUID() {
        XCTAssertEqual(storageCommitmentPushModelSOPInstanceUID, "1.2.840.10008.1.20.1.1")
    }
    
    func testStorageCommitmentActionTypeID() {
        XCTAssertEqual(storageCommitmentRequestActionTypeID, 1)
    }
    
    func testStorageCommitmentEventTypeIDs() {
        XCTAssertEqual(storageCommitmentSuccessEventTypeID, 1)
        XCTAssertEqual(storageCommitmentFailureEventTypeID, 2)
    }
    
    // MARK: - SOPReference Tests
    
    func testSOPReferenceCreation() {
        let reference = SOPReference(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9"
        )
        
        XCTAssertEqual(reference.sopClassUID, "1.2.840.10008.5.1.4.1.1.2")
        XCTAssertEqual(reference.sopInstanceUID, "1.2.3.4.5.6.7.8.9")
    }
    
    func testSOPReferenceHashable() {
        let ref1 = SOPReference(sopClassUID: "1.2.3", sopInstanceUID: "1.2.3.4")
        let ref2 = SOPReference(sopClassUID: "1.2.3", sopInstanceUID: "1.2.3.4")
        let ref3 = SOPReference(sopClassUID: "1.2.3", sopInstanceUID: "1.2.3.5")
        
        XCTAssertEqual(ref1, ref2)
        XCTAssertNotEqual(ref1, ref3)
    }
    
    func testSOPReferenceDescription() {
        let reference = SOPReference(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5"
        )
        
        let description = reference.description
        XCTAssertTrue(description.contains("SOPReference"))
        XCTAssertTrue(description.contains("1.2.840.10008.5.1.4.1.1.2"))
        XCTAssertTrue(description.contains("1.2.3.4.5"))
    }
    
    // MARK: - FailedSOPReference Tests
    
    func testFailedSOPReferenceCreation() {
        let reference = SOPReference(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5"
        )
        let failed = FailedSOPReference(reference: reference, failureReason: 0x0112)
        
        XCTAssertEqual(failed.reference, reference)
        XCTAssertEqual(failed.failureReason, 0x0112)
    }
    
    func testFailedSOPReferenceFailureReasonDescriptions() {
        let reference = SOPReference(sopClassUID: "1.2.3", sopInstanceUID: "1.2.3.4")
        
        // Processing failure
        let processingFailure = FailedSOPReference(reference: reference, failureReason: 0x0110)
        XCTAssertEqual(processingFailure.failureReasonDescription, "Processing failure")
        
        // No such object instance
        let noSuchObject = FailedSOPReference(reference: reference, failureReason: 0x0112)
        XCTAssertEqual(noSuchObject.failureReasonDescription, "No such object instance")
        
        // Resource limitation
        let resourceLimitation = FailedSOPReference(reference: reference, failureReason: 0x0213)
        XCTAssertEqual(resourceLimitation.failureReasonDescription, "Resource limitation")
        
        // Referenced SOP Class not supported
        let sopClassNotSupported = FailedSOPReference(reference: reference, failureReason: 0x0122)
        XCTAssertEqual(sopClassNotSupported.failureReasonDescription, "Referenced SOP Class not supported")
        
        // Class/Instance conflict
        let classInstanceConflict = FailedSOPReference(reference: reference, failureReason: 0x0119)
        XCTAssertEqual(classInstanceConflict.failureReasonDescription, "Class/Instance conflict")
        
        // Duplicate transaction UID (PS3.4 Table J.3-3)
        let duplicateTransaction = FailedSOPReference(reference: reference, failureReason: 0x0131)
        XCTAssertEqual(duplicateTransaction.failureReasonDescription, "Duplicate transaction UID")
        
        // Unknown failure reason
        let unknown = FailedSOPReference(reference: reference, failureReason: 0x9999)
        XCTAssertTrue(unknown.failureReasonDescription.contains("Unknown"))
        XCTAssertTrue(unknown.failureReasonDescription.contains("9999"))
    }
    
    func testFailedSOPReferenceHashable() {
        let ref = SOPReference(sopClassUID: "1.2.3", sopInstanceUID: "1.2.3.4")
        let failed1 = FailedSOPReference(reference: ref, failureReason: 0x0112)
        let failed2 = FailedSOPReference(reference: ref, failureReason: 0x0112)
        let failed3 = FailedSOPReference(reference: ref, failureReason: 0x0110)
        
        XCTAssertEqual(failed1, failed2)
        XCTAssertNotEqual(failed1, failed3)
    }
    
    // MARK: - CommitmentRequest Tests
    
    func testCommitmentRequestCreation() {
        let references = [
            SOPReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.4.5"),
            SOPReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.4.6")
        ]
        
        let request = CommitmentRequest(
            transactionUID: "1.2.840.113619.2.1.1.2024",
            references: references,
            remoteAETitle: "PACS"
        )
        
        XCTAssertEqual(request.transactionUID, "1.2.840.113619.2.1.1.2024")
        XCTAssertEqual(request.references.count, 2)
        XCTAssertEqual(request.remoteAETitle, "PACS")
        XCTAssertNotNil(request.timestamp)
    }
    
    func testCommitmentRequestWithCustomTimestamp() {
        let date = Date(timeIntervalSince1970: 1704067200) // 2024-01-01 00:00:00 UTC
        let request = CommitmentRequest(
            transactionUID: "1.2.3",
            references: [],
            timestamp: date,
            remoteAETitle: "TEST"
        )
        
        XCTAssertEqual(request.timestamp, date)
    }
    
    func testCommitmentRequestHashable() {
        let references = [SOPReference(sopClassUID: "1.2.3", sopInstanceUID: "1.2.3.4")]
        let timestamp = Date(timeIntervalSince1970: 0)
        
        let req1 = CommitmentRequest(
            transactionUID: "1.2.3.4",
            references: references,
            timestamp: timestamp,
            remoteAETitle: "TEST"
        )
        let req2 = CommitmentRequest(
            transactionUID: "1.2.3.4",
            references: references,
            timestamp: timestamp,
            remoteAETitle: "TEST"
        )
        let req3 = CommitmentRequest(
            transactionUID: "1.2.3.5", // Different transaction UID
            references: references,
            timestamp: timestamp,
            remoteAETitle: "TEST"
        )
        
        XCTAssertEqual(req1, req2)
        XCTAssertNotEqual(req1, req3)
    }
    
    func testCommitmentRequestDescription() {
        let request = CommitmentRequest(
            transactionUID: "1.2.3.4.5",
            references: [
                SOPReference(sopClassUID: "1.2.3", sopInstanceUID: "1.2.3.4")
            ],
            remoteAETitle: "PACS"
        )
        
        let description = request.description
        XCTAssertTrue(description.contains("CommitmentRequest"))
        XCTAssertTrue(description.contains("1.2.3.4.5"))
        XCTAssertTrue(description.contains("1"))
        XCTAssertTrue(description.contains("PACS"))
    }
    
    // MARK: - CommitmentResult Tests
    
    func testCommitmentResultSuccessCreation() {
        let committedReferences = [
            SOPReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.4.5"),
            SOPReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.4.6")
        ]
        
        let result = CommitmentResult(
            transactionUID: "1.2.840.113619.2.1.1.2024",
            committedReferences: committedReferences,
            failedReferences: [],
            remoteAETitle: "PACS"
        )
        
        XCTAssertEqual(result.transactionUID, "1.2.840.113619.2.1.1.2024")
        XCTAssertEqual(result.committedReferences.count, 2)
        XCTAssertEqual(result.failedReferences.count, 0)
        XCTAssertTrue(result.isSuccess)
        XCTAssertFalse(result.isPartialSuccess)
        XCTAssertFalse(result.isFailure)
        XCTAssertEqual(result.totalCount, 2)
    }
    
    func testCommitmentResultPartialSuccessCreation() {
        let reference = SOPReference(sopClassUID: "1.2.3", sopInstanceUID: "1.2.3.4")
        let failedRef = FailedSOPReference(reference: reference, failureReason: 0x0112)
        
        let result = CommitmentResult(
            transactionUID: "1.2.3.4.5",
            committedReferences: [SOPReference(sopClassUID: "1.2.3", sopInstanceUID: "1.2.3.5")],
            failedReferences: [failedRef],
            remoteAETitle: "PACS"
        )
        
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.isPartialSuccess)
        XCTAssertFalse(result.isFailure)
        XCTAssertEqual(result.totalCount, 2)
    }
    
    func testCommitmentResultFailureCreation() {
        let reference = SOPReference(sopClassUID: "1.2.3", sopInstanceUID: "1.2.3.4")
        let failedRef = FailedSOPReference(reference: reference, failureReason: 0x0112)
        
        let result = CommitmentResult(
            transactionUID: "1.2.3.4.5",
            committedReferences: [],
            failedReferences: [failedRef],
            remoteAETitle: "PACS"
        )
        
        XCTAssertFalse(result.isSuccess)
        XCTAssertFalse(result.isPartialSuccess)
        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(result.totalCount, 1)
    }
    
    func testCommitmentResultEmptyCreation() {
        let result = CommitmentResult(
            transactionUID: "1.2.3.4.5",
            committedReferences: [],
            failedReferences: [],
            remoteAETitle: "PACS"
        )
        
        XCTAssertTrue(result.isSuccess) // Empty is considered success
        XCTAssertFalse(result.isPartialSuccess)
        XCTAssertFalse(result.isFailure)
        XCTAssertEqual(result.totalCount, 0)
    }
    
    func testCommitmentResultHashable() {
        let timestamp = Date(timeIntervalSince1970: 0)
        
        let result1 = CommitmentResult(
            transactionUID: "1.2.3",
            committedReferences: [],
            failedReferences: [],
            timestamp: timestamp,
            remoteAETitle: "TEST"
        )
        let result2 = CommitmentResult(
            transactionUID: "1.2.3",
            committedReferences: [],
            failedReferences: [],
            timestamp: timestamp,
            remoteAETitle: "TEST"
        )
        let result3 = CommitmentResult(
            transactionUID: "1.2.4", // Different UID
            committedReferences: [],
            failedReferences: [],
            timestamp: timestamp,
            remoteAETitle: "TEST"
        )
        
        XCTAssertEqual(result1, result2)
        XCTAssertNotEqual(result1, result3)
    }
    
    func testCommitmentResultDescription() {
        let result = CommitmentResult(
            transactionUID: "1.2.3.4.5",
            committedReferences: [
                SOPReference(sopClassUID: "1.2.3", sopInstanceUID: "1.2.3.4")
            ],
            failedReferences: [],
            remoteAETitle: "PACS"
        )
        
        let description = result.description
        XCTAssertTrue(description.contains("CommitmentResult"))
        XCTAssertTrue(description.contains("SUCCESS"))
        XCTAssertTrue(description.contains("1.2.3.4.5"))
    }
    
    // MARK: - StorageCommitmentConfiguration Tests
    
    func testStorageCommitmentConfigurationCreation() throws {
        let callingAE = try AETitle("MY_SCU")
        let calledAE = try AETitle("PACS")
        
        let config = StorageCommitmentConfiguration(
            callingAETitle: callingAE,
            calledAETitle: calledAE
        )
        
        XCTAssertEqual(config.callingAETitle, callingAE)
        XCTAssertEqual(config.calledAETitle, calledAE)
        XCTAssertEqual(config.timeout, 60)
        XCTAssertEqual(config.maxPDUSize, defaultMaxPDUSize)
        XCTAssertEqual(config.implementationClassUID, StorageCommitmentConfiguration.defaultImplementationClassUID)
        XCTAssertEqual(config.implementationVersionName, StorageCommitmentConfiguration.defaultImplementationVersionName)
    }
    
    func testStorageCommitmentConfigurationCustomValues() throws {
        let callingAE = try AETitle("SCU")
        let calledAE = try AETitle("SCP")
        
        let config = StorageCommitmentConfiguration(
            callingAETitle: callingAE,
            calledAETitle: calledAE,
            timeout: 120,
            maxPDUSize: 32768,
            implementationClassUID: "1.2.3.4.5.6.7.8.9",
            implementationVersionName: "TEST_V1"
        )
        
        XCTAssertEqual(config.timeout, 120)
        XCTAssertEqual(config.maxPDUSize, 32768)
        XCTAssertEqual(config.implementationClassUID, "1.2.3.4.5.6.7.8.9")
        XCTAssertEqual(config.implementationVersionName, "TEST_V1")
    }
    
    func testStorageCommitmentConfigurationHashable() throws {
        let callingAE = try AETitle("SCU")
        let calledAE = try AETitle("SCP")
        
        let config1 = StorageCommitmentConfiguration(
            callingAETitle: callingAE,
            calledAETitle: calledAE
        )
        let config2 = StorageCommitmentConfiguration(
            callingAETitle: callingAE,
            calledAETitle: calledAE
        )
        let config3 = StorageCommitmentConfiguration(
            callingAETitle: callingAE,
            calledAETitle: calledAE,
            timeout: 30 // Different timeout
        )
        
        XCTAssertEqual(config1, config2)
        XCTAssertNotEqual(config1, config3)
    }
    
    // MARK: - Default Constants Tests
    
    func testDefaultImplementationClassUID() {
        XCTAssertEqual(
            StorageCommitmentConfiguration.defaultImplementationClassUID,
            "1.2.826.0.1.3680043.10.511.3.0.5.0"  // DICOMKit root (D155)
        )
    }
    
    func testDefaultImplementationVersionName() {
        XCTAssertEqual(
            StorageCommitmentConfiguration.defaultImplementationVersionName,
            "DICOMKIT_001"
        )
    }
    
    // MARK: - CommitmentNotificationListenerConfiguration Tests
    
    func testCommitmentNotificationListenerConfigurationCreation() throws {
        let aeTitle = try AETitle("MY_SCU")
        
        let config = CommitmentNotificationListenerConfiguration(
            aeTitle: aeTitle
        )
        
        XCTAssertEqual(config.aeTitle, aeTitle)
        XCTAssertEqual(config.port, 11113)
        XCTAssertEqual(config.maxPDUSize, defaultMaxPDUSize)
        XCTAssertEqual(config.implementationClassUID, CommitmentNotificationListenerConfiguration.defaultImplementationClassUID)
        XCTAssertEqual(config.implementationVersionName, CommitmentNotificationListenerConfiguration.defaultImplementationVersionName)
        XCTAssertEqual(config.maxConcurrentAssociations, 5)
        XCTAssertNil(config.callingAEWhitelist)
    }
    
    func testCommitmentNotificationListenerConfigurationCustomValues() throws {
        let aeTitle = try AETitle("SCU")
        let whitelist: Set<String> = ["PACS1", "PACS2"]
        
        let config = CommitmentNotificationListenerConfiguration(
            aeTitle: aeTitle,
            port: 12345,
            maxPDUSize: 32768,
            implementationClassUID: "1.2.3.4.5",
            implementationVersionName: "TEST_V1",
            maxConcurrentAssociations: 10,
            callingAEWhitelist: whitelist
        )
        
        XCTAssertEqual(config.port, 12345)
        XCTAssertEqual(config.maxPDUSize, 32768)
        XCTAssertEqual(config.implementationClassUID, "1.2.3.4.5")
        XCTAssertEqual(config.implementationVersionName, "TEST_V1")
        XCTAssertEqual(config.maxConcurrentAssociations, 10)
        XCTAssertEqual(config.callingAEWhitelist, whitelist)
    }
    
    func testCommitmentNotificationListenerConfigurationMinimumAssociations() throws {
        let aeTitle = try AETitle("SCU")
        
        // Setting 0 should result in 1
        let config = CommitmentNotificationListenerConfiguration(
            aeTitle: aeTitle,
            maxConcurrentAssociations: 0
        )
        
        XCTAssertEqual(config.maxConcurrentAssociations, 1)
    }
    
    func testCommitmentNotificationListenerConfigurationIsCallingAEAllowed() throws {
        let aeTitle = try AETitle("SCU")
        
        // No whitelist - all allowed
        let configNoWhitelist = CommitmentNotificationListenerConfiguration(aeTitle: aeTitle)
        XCTAssertTrue(configNoWhitelist.isCallingAEAllowed("ANY_AE"))
        
        // With whitelist - only allowed if in whitelist
        let configWithWhitelist = CommitmentNotificationListenerConfiguration(
            aeTitle: aeTitle,
            callingAEWhitelist: ["ALLOWED1", "ALLOWED2"]
        )
        XCTAssertTrue(configWithWhitelist.isCallingAEAllowed("ALLOWED1"))
        XCTAssertTrue(configWithWhitelist.isCallingAEAllowed("ALLOWED2"))
        XCTAssertFalse(configWithWhitelist.isCallingAEAllowed("NOT_ALLOWED"))
    }
    
    func testCommitmentNotificationListenerConfigurationHashable() throws {
        let aeTitle = try AETitle("SCU")
        
        let config1 = CommitmentNotificationListenerConfiguration(aeTitle: aeTitle, port: 11113)
        let config2 = CommitmentNotificationListenerConfiguration(aeTitle: aeTitle, port: 11113)
        let config3 = CommitmentNotificationListenerConfiguration(aeTitle: aeTitle, port: 11114)
        
        XCTAssertEqual(config1, config2)
        XCTAssertNotEqual(config1, config3)
    }
    
    func testCommitmentNotificationListenerConfigurationDefaultConstants() {
        XCTAssertEqual(
            CommitmentNotificationListenerConfiguration.defaultImplementationClassUID,
            "1.2.826.0.1.3680043.10.511.3.0.5.0"  // DICOMKit root (D155)
        )
        XCTAssertEqual(
            CommitmentNotificationListenerConfiguration.defaultImplementationVersionName,
            "DICOMKIT_CMTLSN"
        )
    }
    
    // MARK: - CommitmentNotificationListenerEvent Tests
    
    func testCommitmentNotificationListenerEventStarted() {
        let event = CommitmentNotificationListenerEvent.started(port: 11113)
        
        switch event {
        case .started(let port):
            XCTAssertEqual(port, 11113)
        default:
            XCTFail("Expected .started event")
        }
    }
    
    func testCommitmentNotificationListenerEventResultReceived() {
        let result = CommitmentResult(
            transactionUID: "1.2.3.4.5",
            committedReferences: [SOPReference(sopClassUID: "1.2.3", sopInstanceUID: "1.2.3.4")],
            failedReferences: [],
            remoteAETitle: "PACS"
        )
        
        let event = CommitmentNotificationListenerEvent.resultReceived(result)
        
        switch event {
        case .resultReceived(let receivedResult):
            XCTAssertEqual(receivedResult.transactionUID, "1.2.3.4.5")
            XCTAssertTrue(receivedResult.isSuccess)
        default:
            XCTFail("Expected .resultReceived event")
        }
    }
    
    func testCommitmentNotificationListenerEventAssociationEstablished() {
        let event = CommitmentNotificationListenerEvent.associationEstablished(callingAE: "PACS")
        
        switch event {
        case .associationEstablished(let ae):
            XCTAssertEqual(ae, "PACS")
        default:
            XCTFail("Expected .associationEstablished event")
        }
    }
    
    func testCommitmentNotificationListenerEventAssociationRejected() {
        let event = CommitmentNotificationListenerEvent.associationRejected(
            callingAE: "UNKNOWN",
            reason: "AE not allowed"
        )
        
        switch event {
        case .associationRejected(let ae, let reason):
            XCTAssertEqual(ae, "UNKNOWN")
            XCTAssertEqual(reason, "AE not allowed")
        default:
            XCTFail("Expected .associationRejected event")
        }
    }
    
    #if canImport(Network)
    // MARK: - CommitmentNotificationListener Tests
    
    func testCommitmentNotificationListenerCreation() async throws {
        let config = CommitmentNotificationListenerConfiguration(
            aeTitle: try AETitle("MY_SCU")
        )
        
        let listener = CommitmentNotificationListener(configuration: config)
        let isRunning = await listener.isRunning
        let associationCount = await listener.activeAssociationCount
        
        XCTAssertFalse(isRunning)
        XCTAssertEqual(associationCount, 0)
    }
    
    func testCommitmentNotificationListenerStartStop() async throws {
        let config = CommitmentNotificationListenerConfiguration(
            aeTitle: try AETitle("MY_SCU"),
            port: 19123 // Use a high port that's likely available
        )
        
        let listener = CommitmentNotificationListener(configuration: config)
        
        // Start the listener
        try await listener.start()
        var isRunning = await listener.isRunning
        XCTAssertTrue(isRunning)
        
        // Stop the listener
        await listener.stop()
        isRunning = await listener.isRunning
        XCTAssertFalse(isRunning)
    }
    
    func testCommitmentNotificationListenerCannotStartTwice() async throws {
        let config = CommitmentNotificationListenerConfiguration(
            aeTitle: try AETitle("MY_SCU"),
            port: 19124
        )
        
        let listener = CommitmentNotificationListener(configuration: config)
        
        try await listener.start()
        
        // Second start should fail
        do {
            try await listener.start()
            XCTFail("Expected error when starting already running listener")
        } catch let error as DICOMNetworkError {
            switch error {
            case .invalidState:
                break // Expected
            default:
                XCTFail("Expected invalidState error, got \(error)")
            }
        }
        
        await listener.stop()
    }
    
    func testCommitmentNotificationListenerWaitForResultTimeout() async throws {
        let config = CommitmentNotificationListenerConfiguration(
            aeTitle: try AETitle("MY_SCU"),
            port: 19125
        )
        
        let listener = CommitmentNotificationListener(configuration: config)
        try await listener.start()
        
        // Wait for a result that will never come - should timeout
        do {
            _ = try await listener.waitForResult(
                transactionUID: "non.existent.transaction",
                timeout: .milliseconds(100)
            )
            XCTFail("Expected timeout error")
        } catch let error as DICOMNetworkError {
            switch error {
            case .timeout:
                break // Expected
            default:
                XCTFail("Expected timeout error, got \(error)")
            }
        }
        
        await listener.stop()
    }
    #endif
    
    // MARK: - Retry Configuration Tests
    
    func testStorageCommitmentConfigurationWithRetryPolicy() throws {
        let callingAE = try AETitle("MY_SCU")
        let calledAE = try AETitle("PACS")
        let retryPolicy = RetryPolicy.aggressive
        
        let config = StorageCommitmentConfiguration(
            callingAETitle: callingAE,
            calledAETitle: calledAE,
            retryPolicy: retryPolicy
        )
        
        XCTAssertEqual(config.callingAETitle, callingAE)
        XCTAssertEqual(config.calledAETitle, calledAE)
        XCTAssertEqual(config.retryPolicy, retryPolicy)
    }
    
    func testStorageCommitmentConfigurationDefaultRetryPolicy() throws {
        let callingAE = try AETitle("MY_SCU")
        let calledAE = try AETitle("PACS")
        
        let config = StorageCommitmentConfiguration(
            callingAETitle: callingAE,
            calledAETitle: calledAE
        )
        
        // Should use default retry policy
        XCTAssertEqual(config.retryPolicy, RetryPolicy.default)
    }
    
    func testStorageCommitmentConfigurationNoRetryPolicy() throws {
        let callingAE = try AETitle("MY_SCU")
        let calledAE = try AETitle("PACS")
        
        let config = StorageCommitmentConfiguration(
            callingAETitle: callingAE,
            calledAETitle: calledAE,
            retryPolicy: .noRetry
        )
        
        XCTAssertEqual(config.retryPolicy, RetryPolicy.noRetry)
        XCTAssertEqual(config.retryPolicy.maxAttempts, 0)
    }
    
    func testStorageCommitmentConfigurationCustomRetryPolicy() throws {
        let callingAE = try AETitle("MY_SCU")
        let calledAE = try AETitle("PACS")
        
        let customPolicy = RetryPolicy(
            maxAttempts: 10,
            initialDelay: 0.5,
            maxDelay: 120.0,
            strategy: .exponential(factor: 3.0)
        )
        
        let config = StorageCommitmentConfiguration(
            callingAETitle: callingAE,
            calledAETitle: calledAE,
            retryPolicy: customPolicy
        )
        
        XCTAssertEqual(config.retryPolicy.maxAttempts, 10)
        XCTAssertEqual(config.retryPolicy.initialDelay, 0.5)
        XCTAssertEqual(config.retryPolicy.maxDelay, 120.0)
    }
    
    func testStorageCommitmentConfigurationHashableWithRetryPolicy() throws {
        let callingAE = try AETitle("SCU")
        let calledAE = try AETitle("SCP")
        
        let config1 = StorageCommitmentConfiguration(
            callingAETitle: callingAE,
            calledAETitle: calledAE,
            retryPolicy: .default
        )
        let config2 = StorageCommitmentConfiguration(
            callingAETitle: callingAE,
            calledAETitle: calledAE,
            retryPolicy: .default
        )
        let config3 = StorageCommitmentConfiguration(
            callingAETitle: callingAE,
            calledAETitle: calledAE,
            retryPolicy: .aggressive // Different retry policy
        )
        
        XCTAssertEqual(config1, config2)
        XCTAssertNotEqual(config1, config3)
    }
}
