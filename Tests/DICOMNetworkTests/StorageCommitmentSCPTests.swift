import XCTest
import DICOMCore
@testable import DICOMNetwork

final class StorageCommitmentSCPTests: XCTestCase {
    
    // MARK: - Configuration Tests
    
    func testStorageCommitmentSCPConfigurationCreation() throws {
        let aeTitle = try AETitle("MY_SCP")
        
        let config = StorageCommitmentSCPConfiguration(aeTitle: aeTitle)
        
        XCTAssertEqual(config.aeTitle, aeTitle)
        XCTAssertEqual(config.port, dicomAlternativePort)
        XCTAssertEqual(config.maxPDUSize, defaultMaxPDUSize)
        XCTAssertEqual(config.maxConcurrentAssociations, 10)
        XCTAssertNil(config.callingAEWhitelist)
        XCTAssertNil(config.callingAEBlacklist)
    }
    
    func testStorageCommitmentSCPConfigurationWithCustomPort() throws {
        let aeTitle = try AETitle("MY_SCP")
        
        let config = StorageCommitmentSCPConfiguration(
            aeTitle: aeTitle,
            port: 11113
        )
        
        XCTAssertEqual(config.port, 11113)
    }
    
    func testStorageCommitmentSCPConfigurationWithCustomMaxPDUSize() throws {
        let aeTitle = try AETitle("MY_SCP")
        
        let config = StorageCommitmentSCPConfiguration(
            aeTitle: aeTitle,
            maxPDUSize: 32768
        )
        
        XCTAssertEqual(config.maxPDUSize, 32768)
    }
    
    func testStorageCommitmentSCPConfigurationWithCustomMaxAssociations() throws {
        let aeTitle = try AETitle("MY_SCP")
        
        let config = StorageCommitmentSCPConfiguration(
            aeTitle: aeTitle,
            maxConcurrentAssociations: 20
        )
        
        XCTAssertEqual(config.maxConcurrentAssociations, 20)
    }
    
    func testStorageCommitmentSCPConfigurationWithMinimumMaxAssociations() throws {
        let aeTitle = try AETitle("MY_SCP")
        
        let config = StorageCommitmentSCPConfiguration(
            aeTitle: aeTitle,
            maxConcurrentAssociations: 0
        )
        
        // Should be at least 1
        XCTAssertEqual(config.maxConcurrentAssociations, 1)
    }
    
    func testStorageCommitmentSCPConfigurationWithWhitelist() throws {
        let aeTitle = try AETitle("MY_SCP")
        
        let config = StorageCommitmentSCPConfiguration(
            aeTitle: aeTitle,
            callingAEWhitelist: ["SCU1", "SCU2"]
        )
        
        XCTAssertNotNil(config.callingAEWhitelist)
        XCTAssertEqual(config.callingAEWhitelist?.count, 2)
    }
    
    func testStorageCommitmentSCPConfigurationWithBlacklist() throws {
        let aeTitle = try AETitle("MY_SCP")
        
        let config = StorageCommitmentSCPConfiguration(
            aeTitle: aeTitle,
            callingAEBlacklist: ["BANNED"]
        )
        
        XCTAssertNotNil(config.callingAEBlacklist)
        XCTAssertEqual(config.callingAEBlacklist?.count, 1)
    }
    
    func testStorageCommitmentSCPConfigurationHashable() throws {
        let aeTitle = try AETitle("MY_SCP")
        
        let config1 = StorageCommitmentSCPConfiguration(aeTitle: aeTitle, port: 11112)
        let config2 = StorageCommitmentSCPConfiguration(aeTitle: aeTitle, port: 11112)
        let config3 = StorageCommitmentSCPConfiguration(aeTitle: aeTitle, port: 11113)
        
        XCTAssertEqual(config1, config2)
        XCTAssertNotEqual(config1, config3)
    }
    
    // MARK: - AE Title Filtering Tests
    
    func testIsCallingAEAllowedWithNoFilters() throws {
        let aeTitle = try AETitle("MY_SCP")
        let config = StorageCommitmentSCPConfiguration(aeTitle: aeTitle)
        
        XCTAssertTrue(config.isCallingAEAllowed("ANY_SCU"))
        XCTAssertTrue(config.isCallingAEAllowed("ANOTHER_SCU"))
    }
    
    func testIsCallingAEAllowedWithWhitelist() throws {
        let aeTitle = try AETitle("MY_SCP")
        let config = StorageCommitmentSCPConfiguration(
            aeTitle: aeTitle,
            callingAEWhitelist: ["ALLOWED_SCU", "OTHER_ALLOWED"]
        )
        
        XCTAssertTrue(config.isCallingAEAllowed("ALLOWED_SCU"))
        XCTAssertTrue(config.isCallingAEAllowed("OTHER_ALLOWED"))
        XCTAssertFalse(config.isCallingAEAllowed("DENIED_SCU"))
    }
    
    func testIsCallingAEAllowedWithBlacklist() throws {
        let aeTitle = try AETitle("MY_SCP")
        let config = StorageCommitmentSCPConfiguration(
            aeTitle: aeTitle,
            callingAEBlacklist: ["BLOCKED_SCU"]
        )
        
        XCTAssertTrue(config.isCallingAEAllowed("ANY_SCU"))
        XCTAssertFalse(config.isCallingAEAllowed("BLOCKED_SCU"))
    }
    
    func testBlacklistTakesPrecedenceOverWhitelist() throws {
        let aeTitle = try AETitle("MY_SCP")
        let config = StorageCommitmentSCPConfiguration(
            aeTitle: aeTitle,
            callingAEWhitelist: ["SCU1", "SCU2"],
            callingAEBlacklist: ["SCU1"]
        )
        
        // SCU1 is in both - blacklist wins
        XCTAssertFalse(config.isCallingAEAllowed("SCU1"))
        // SCU2 is only in whitelist
        XCTAssertTrue(config.isCallingAEAllowed("SCU2"))
        // SCU3 is in neither but whitelist exists
        XCTAssertFalse(config.isCallingAEAllowed("SCU3"))
    }
    
    // MARK: - Default Constants Tests
    
    func testDefaultImplementationClassUID() {
        XCTAssertEqual(
            StorageCommitmentSCPConfiguration.defaultImplementationClassUID,
            "1.2.826.0.1.3680043.10.511.3.0.5.0"  // DICOMKit root (D155)
        )
    }
    
    func testDefaultImplementationVersionName() {
        XCTAssertEqual(
            StorageCommitmentSCPConfiguration.defaultImplementationVersionName,
            "DICOMKIT_SCSCP"
        )
    }
    
    // MARK: - CommitmentRequestInfo Tests
    
    func testCommitmentRequestInfoCreation() {
        let references = [
            SOPReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.4.5"),
            SOPReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.4.6")
        ]
        
        let requestInfo = CommitmentRequestInfo(
            transactionUID: "1.2.840.113619.2.1.1.2024",
            references: references,
            callingAETitle: "TEST_SCU"
        )
        
        XCTAssertEqual(requestInfo.transactionUID, "1.2.840.113619.2.1.1.2024")
        XCTAssertEqual(requestInfo.references.count, 2)
        XCTAssertEqual(requestInfo.callingAETitle, "TEST_SCU")
        XCTAssertNotNil(requestInfo.timestamp)
    }
    
    func testCommitmentRequestInfoWithCustomTimestamp() {
        let timestamp = Date(timeIntervalSince1970: 1704067200)
        
        let requestInfo = CommitmentRequestInfo(
            transactionUID: "1.2.3",
            references: [],
            callingAETitle: "SCU",
            timestamp: timestamp
        )
        
        XCTAssertEqual(requestInfo.timestamp, timestamp)
    }
    
    func testCommitmentRequestInfoDescription() {
        let requestInfo = CommitmentRequestInfo(
            transactionUID: "1.2.3.4.5",
            references: [
                SOPReference(sopClassUID: "1.2.3", sopInstanceUID: "1.2.3.4")
            ],
            callingAETitle: "TEST_SCU"
        )
        
        let description = requestInfo.description
        XCTAssertTrue(description.contains("CommitmentRequestInfo"))
        XCTAssertTrue(description.contains("1.2.3.4.5"))
        XCTAssertTrue(description.contains("1"))
        XCTAssertTrue(description.contains("TEST_SCU"))
    }
    
    // MARK: - StorageCommitmentServerEvent Tests
    
    func testStorageCommitmentServerEventStarted() {
        let event = StorageCommitmentServerEvent.started(port: 11112)
        
        if case .started(let port) = event {
            XCTAssertEqual(port, 11112)
        } else {
            XCTFail("Expected started event")
        }
    }
    
    func testStorageCommitmentServerEventStopped() {
        let event = StorageCommitmentServerEvent.stopped
        
        if case .stopped = event {
            // Success
        } else {
            XCTFail("Expected stopped event")
        }
    }
    
    func testStorageCommitmentServerEventCommitmentRequestReceived() {
        let requestInfo = CommitmentRequestInfo(
            transactionUID: "1.2.3",
            references: [],
            callingAETitle: "SCU"
        )
        let event = StorageCommitmentServerEvent.commitmentRequestReceived(requestInfo)
        
        if case .commitmentRequestReceived(let info) = event {
            XCTAssertEqual(info.transactionUID, "1.2.3")
        } else {
            XCTFail("Expected commitmentRequestReceived event")
        }
    }
    
    func testStorageCommitmentServerEventCommitmentResultSent() {
        let event = StorageCommitmentServerEvent.commitmentResultSent(transactionUID: "1.2.3", success: true)
        
        if case .commitmentResultSent(let txn, let success) = event {
            XCTAssertEqual(txn, "1.2.3")
            XCTAssertTrue(success)
        } else {
            XCTFail("Expected commitmentResultSent event")
        }
    }
    
    func testStorageCommitmentServerEventError() {
        let testError = DICOMNetworkError.connectionClosed
        let event = StorageCommitmentServerEvent.error(testError)
        
        if case .error(let error) = event {
            XCTAssertTrue(error is DICOMNetworkError)
        } else {
            XCTFail("Expected error event")
        }
    }
    
    // MARK: - DefaultCommitmentHandler Tests
    
    func testDefaultCommitmentHandlerAcceptsAllAssociations() async {
        let handler = DefaultCommitmentHandler()
        let info = AssociationInfo(
            callingAETitle: "TEST",
            calledAETitle: "SCP",
            remoteHost: "127.0.0.1",
            remotePort: 11112,
            proposedSOPClasses: [],
            proposedTransferSyntaxes: []
        )
        
        let result = await handler.shouldAcceptAssociation(from: info)
        XCTAssertTrue(result)
    }
    
    func testDefaultCommitmentHandlerCommitsAllReferences() async throws {
        let handler = DefaultCommitmentHandler()
        
        let references = [
            SOPReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.4.5"),
            SOPReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.4.6")
        ]
        
        let requestInfo = CommitmentRequestInfo(
            transactionUID: "1.2.840.113619.2.1.1.2024",
            references: references,
            callingAETitle: "TEST_SCU"
        )
        
        let result = try await handler.processCommitmentRequest(requestInfo)
        
        XCTAssertEqual(result.transactionUID, "1.2.840.113619.2.1.1.2024")
        XCTAssertEqual(result.committedReferences.count, 2)
        XCTAssertEqual(result.failedReferences.count, 0)
        XCTAssertTrue(result.isSuccess)
    }
    
    func testDefaultCommitmentHandlerWithEmptyReferences() async throws {
        let handler = DefaultCommitmentHandler()
        
        let requestInfo = CommitmentRequestInfo(
            transactionUID: "1.2.3.4.5",
            references: [],
            callingAETitle: "TEST_SCU"
        )
        
        let result = try await handler.processCommitmentRequest(requestInfo)
        
        XCTAssertEqual(result.committedReferences.count, 0)
        XCTAssertEqual(result.failedReferences.count, 0)
        XCTAssertTrue(result.isSuccess) // Empty is considered success
    }
    
    // MARK: - Custom Delegate Tests
    
    func testCustomDelegateCanRejectAssociations() async {
        actor RejectingDelegate: StorageCommitmentDelegate {
            func shouldAcceptAssociation(from info: AssociationInfo) async -> Bool {
                return info.callingAETitle == "ALLOWED_SCU"
            }
            
            func processCommitmentRequest(_ request: CommitmentRequestInfo) async throws -> CommitmentResult {
                CommitmentResult(
                    transactionUID: request.transactionUID,
                    committedReferences: request.references,
                    failedReferences: [],
                    remoteAETitle: request.callingAETitle
                )
            }
        }
        
        let delegate = RejectingDelegate()
        
        let allowedInfo = AssociationInfo(
            callingAETitle: "ALLOWED_SCU",
            calledAETitle: "SCP",
            remoteHost: "127.0.0.1",
            remotePort: 11112,
            proposedSOPClasses: [],
            proposedTransferSyntaxes: []
        )
        
        let deniedInfo = AssociationInfo(
            callingAETitle: "DENIED_SCU",
            calledAETitle: "SCP",
            remoteHost: "127.0.0.1",
            remotePort: 11112,
            proposedSOPClasses: [],
            proposedTransferSyntaxes: []
        )
        
        let allowedResult = await delegate.shouldAcceptAssociation(from: allowedInfo)
        let deniedResult = await delegate.shouldAcceptAssociation(from: deniedInfo)
        
        XCTAssertTrue(allowedResult)
        XCTAssertFalse(deniedResult)
    }
    
    func testCustomDelegateCanReportFailures() async throws {
        actor PartialFailureDelegate: StorageCommitmentDelegate {
            func processCommitmentRequest(_ request: CommitmentRequestInfo) async throws -> CommitmentResult {
                // Fail the first reference, commit the rest
                var committed: [SOPReference] = []
                var failed: [FailedSOPReference] = []
                
                for (index, ref) in request.references.enumerated() {
                    if index == 0 {
                        failed.append(FailedSOPReference(reference: ref, failureReason: 0x0112))
                    } else {
                        committed.append(ref)
                    }
                }
                
                return CommitmentResult(
                    transactionUID: request.transactionUID,
                    committedReferences: committed,
                    failedReferences: failed,
                    remoteAETitle: request.callingAETitle
                )
            }
        }
        
        let delegate = PartialFailureDelegate()
        
        let references = [
            SOPReference(sopClassUID: "1.2.3", sopInstanceUID: "1.2.3.1"),
            SOPReference(sopClassUID: "1.2.3", sopInstanceUID: "1.2.3.2"),
            SOPReference(sopClassUID: "1.2.3", sopInstanceUID: "1.2.3.3")
        ]
        
        let requestInfo = CommitmentRequestInfo(
            transactionUID: "1.2.3.4.5",
            references: references,
            callingAETitle: "TEST_SCU"
        )
        
        let result = try await delegate.processCommitmentRequest(requestInfo)
        
        XCTAssertEqual(result.committedReferences.count, 2)
        XCTAssertEqual(result.failedReferences.count, 1)
        XCTAssertTrue(result.isPartialSuccess)
        XCTAssertFalse(result.isSuccess)
        XCTAssertFalse(result.isFailure)
    }
}
