import XCTest
import DICOMCore
@testable import DICOMNetwork

final class RetrieveServiceTests: XCTestCase {
    
    // MARK: - RetrieveProgress Tests
    
    func testRetrieveProgressInit() {
        let progress = RetrieveProgress(remaining: 10, completed: 5, failed: 1, warning: 2)
        
        XCTAssertEqual(progress.remaining, 10)
        XCTAssertEqual(progress.completed, 5)
        XCTAssertEqual(progress.failed, 1)
        XCTAssertEqual(progress.warning, 2)
    }
    
    func testRetrieveProgressTotal() {
        let progress = RetrieveProgress(remaining: 10, completed: 5, failed: 1, warning: 2)
        XCTAssertEqual(progress.total, 18)
    }
    
    func testRetrieveProgressFractionComplete() {
        let progress = RetrieveProgress(remaining: 5, completed: 10, failed: 2, warning: 1)
        // Total = 18, completed + failed + warning = 13
        // Fraction = 13/18 ≈ 0.722
        XCTAssertEqual(progress.fractionComplete, 13.0 / 18.0, accuracy: 0.001)
    }
    
    func testRetrieveProgressFractionCompleteZeroTotal() {
        let progress = RetrieveProgress()
        XCTAssertEqual(progress.fractionComplete, 0.0)
    }
    
    func testRetrieveProgressIsComplete() {
        let progressIncomplete = RetrieveProgress(remaining: 5, completed: 10)
        XCTAssertFalse(progressIncomplete.isComplete)
        
        let progressComplete = RetrieveProgress(remaining: 0, completed: 10, failed: 0, warning: 0)
        XCTAssertTrue(progressComplete.isComplete)
    }
    
    func testRetrieveProgressHasFailures() {
        let progressNoFailures = RetrieveProgress(remaining: 0, completed: 10)
        XCTAssertFalse(progressNoFailures.hasFailures)
        
        let progressWithFailures = RetrieveProgress(remaining: 0, completed: 8, failed: 2)
        XCTAssertTrue(progressWithFailures.hasFailures)
    }
    
    func testRetrieveProgressDescription() {
        let progress = RetrieveProgress(remaining: 5, completed: 10, failed: 2, warning: 1)
        let description = progress.description
        
        XCTAssertTrue(description.contains("10"))
        XCTAssertTrue(description.contains("18"))
        XCTAssertTrue(description.contains("2"))
        XCTAssertTrue(description.contains("5"))
    }
    
    func testRetrieveProgressEquatable() {
        let progress1 = RetrieveProgress(remaining: 5, completed: 10, failed: 2, warning: 1)
        let progress2 = RetrieveProgress(remaining: 5, completed: 10, failed: 2, warning: 1)
        let progress3 = RetrieveProgress(remaining: 6, completed: 10, failed: 2, warning: 1)
        
        XCTAssertEqual(progress1, progress2)
        XCTAssertNotEqual(progress1, progress3)
    }
    
    func testRetrieveProgressHashable() {
        var set = Set<RetrieveProgress>()
        set.insert(RetrieveProgress(remaining: 5, completed: 10))
        set.insert(RetrieveProgress(remaining: 5, completed: 10)) // Duplicate
        set.insert(RetrieveProgress(remaining: 6, completed: 10))
        
        XCTAssertEqual(set.count, 2)
    }
    
    // MARK: - RetrieveResult Tests
    
    func testRetrieveResultIsSuccess() {
        let successResult = RetrieveResult(
            status: .success,
            progress: RetrieveProgress(remaining: 0, completed: 10, failed: 0, warning: 0)
        )
        XCTAssertTrue(successResult.isSuccess)
        
        let failedResult = RetrieveResult(
            status: .success,
            progress: RetrieveProgress(remaining: 0, completed: 8, failed: 2, warning: 0)
        )
        XCTAssertFalse(failedResult.isSuccess)
    }
    
    func testRetrieveResultHasPartialFailures() {
        let partialResult = RetrieveResult(
            status: .success,
            progress: RetrieveProgress(remaining: 0, completed: 8, failed: 2, warning: 0)
        )
        XCTAssertTrue(partialResult.hasPartialFailures)
        
        let fullSuccessResult = RetrieveResult(
            status: .success,
            progress: RetrieveProgress(remaining: 0, completed: 10, failed: 0, warning: 0)
        )
        XCTAssertFalse(fullSuccessResult.hasPartialFailures)
    }
    
    func testRetrieveResultDescription() {
        let result = RetrieveResult(
            status: .success,
            progress: RetrieveProgress(remaining: 0, completed: 10)
        )
        let description = result.description
        
        XCTAssertTrue(description.contains("RetrieveResult"))
        XCTAssertTrue(description.contains("Status"))
        XCTAssertTrue(description.contains("Progress"))
    }
    
    // MARK: - RetrieveConfiguration Tests
    
    func testRetrieveConfigurationDefaults() throws {
        let callingAE = try AETitle("CALLING")
        let calledAE = try AETitle("CALLED")
        
        let config = RetrieveConfiguration(
            callingAETitle: callingAE,
            calledAETitle: calledAE
        )
        
        XCTAssertEqual(config.callingAETitle.value, "CALLING")
        XCTAssertEqual(config.calledAETitle.value, "CALLED")
        XCTAssertEqual(config.timeout, 60)
        XCTAssertEqual(config.maxPDUSize, defaultMaxPDUSize)
        XCTAssertEqual(config.implementationClassUID, RetrieveConfiguration.defaultImplementationClassUID)
        XCTAssertEqual(config.implementationVersionName, RetrieveConfiguration.defaultImplementationVersionName)
        XCTAssertEqual(config.informationModel, .studyRoot)
    }
    
    func testRetrieveConfigurationCustomValues() throws {
        let callingAE = try AETitle("MY_SCU")
        let calledAE = try AETitle("PACS")
        
        let config = RetrieveConfiguration(
            callingAETitle: callingAE,
            calledAETitle: calledAE,
            timeout: 120,
            maxPDUSize: 32768,
            implementationClassUID: "1.2.3.4.5",
            implementationVersionName: "TEST_V1",
            informationModel: .patientRoot
        )
        
        XCTAssertEqual(config.callingAETitle.value, "MY_SCU")
        XCTAssertEqual(config.calledAETitle.value, "PACS")
        XCTAssertEqual(config.timeout, 120)
        XCTAssertEqual(config.maxPDUSize, 32768)
        XCTAssertEqual(config.implementationClassUID, "1.2.3.4.5")
        XCTAssertEqual(config.implementationVersionName, "TEST_V1")
        XCTAssertEqual(config.informationModel, .patientRoot)
    }
    
    func testRetrieveConfigurationHashable() throws {
        let callingAE = try AETitle("SCU")
        let calledAE = try AETitle("SCP")
        
        let config1 = RetrieveConfiguration(
            callingAETitle: callingAE,
            calledAETitle: calledAE,
            timeout: 60
        )
        let config2 = RetrieveConfiguration(
            callingAETitle: callingAE,
            calledAETitle: calledAE,
            timeout: 60
        )
        let config3 = RetrieveConfiguration(
            callingAETitle: callingAE,
            calledAETitle: calledAE,
            timeout: 120
        )
        
        XCTAssertEqual(config1, config2)
        XCTAssertNotEqual(config1, config3)
    }
    
    // MARK: - RetrieveKeys Tests
    
    func testRetrieveKeysForStudy() {
        let keys = RetrieveKeys.forStudy("1.2.3.4.5")
        
        XCTAssertEqual(keys.level, .study)
        XCTAssertEqual(keys.keys.count, 1)
        XCTAssertEqual(keys.keys[0].tag, .studyInstanceUID)
        XCTAssertEqual(keys.keys[0].value, "1.2.3.4.5")
        XCTAssertEqual(keys.keys[0].vr, .UI)
    }
    
    func testRetrieveKeysForSeries() {
        let keys = RetrieveKeys.forSeries(studyUID: "1.2.3.4.5", seriesUID: "1.2.3.4.5.6")
        
        XCTAssertEqual(keys.level, .series)
        XCTAssertEqual(keys.keys.count, 2)
        
        // Check study UID
        let studyKey = keys.keys.first { $0.tag == .studyInstanceUID }
        XCTAssertNotNil(studyKey)
        XCTAssertEqual(studyKey?.value, "1.2.3.4.5")
        
        // Check series UID
        let seriesKey = keys.keys.first { $0.tag == .seriesInstanceUID }
        XCTAssertNotNil(seriesKey)
        XCTAssertEqual(seriesKey?.value, "1.2.3.4.5.6")
    }
    
    func testRetrieveKeysForInstance() {
        let keys = RetrieveKeys.forInstance(
            studyUID: "1.2.3.4.5",
            seriesUID: "1.2.3.4.5.6",
            instanceUID: "1.2.3.4.5.6.7"
        )
        
        XCTAssertEqual(keys.level, .image)
        XCTAssertEqual(keys.keys.count, 3)
        
        // Check all UIDs are present
        let studyKey = keys.keys.first { $0.tag == .studyInstanceUID }
        let seriesKey = keys.keys.first { $0.tag == .seriesInstanceUID }
        let instanceKey = keys.keys.first { $0.tag == .sopInstanceUID }
        
        XCTAssertNotNil(studyKey)
        XCTAssertNotNil(seriesKey)
        XCTAssertNotNil(instanceKey)
        
        XCTAssertEqual(studyKey?.value, "1.2.3.4.5")
        XCTAssertEqual(seriesKey?.value, "1.2.3.4.5.6")
        XCTAssertEqual(instanceKey?.value, "1.2.3.4.5.6.7")
    }
    
    func testRetrieveKeysFluentAPI() {
        let keys = RetrieveKeys(level: .study)
            .studyInstanceUID("1.2.3")
            .patientID("12345")
        
        XCTAssertEqual(keys.keys.count, 2)
        
        let studyKey = keys.keys.first { $0.tag == .studyInstanceUID }
        let patientKey = keys.keys.first { $0.tag == .patientID }
        
        XCTAssertEqual(studyKey?.value, "1.2.3")
        XCTAssertEqual(patientKey?.value, "12345")
    }
    
    func testRetrieveKeysEquatable() {
        let keys1 = RetrieveKeys.forStudy("1.2.3")
        let keys2 = RetrieveKeys.forStudy("1.2.3")
        let keys3 = RetrieveKeys.forStudy("1.2.4")
        
        XCTAssertEqual(keys1, keys2)
        XCTAssertNotEqual(keys1, keys3)
    }
    
    // MARK: - Query/Retrieve Information Model Extension Tests
    
    func testPatientRootMoveSOPClassUID() {
        XCTAssertEqual(QueryRetrieveInformationModel.patientRoot.moveSOPClassUID, "1.2.840.10008.5.1.4.1.2.1.2")
    }
    
    func testStudyRootMoveSOPClassUID() {
        XCTAssertEqual(QueryRetrieveInformationModel.studyRoot.moveSOPClassUID, "1.2.840.10008.5.1.4.1.2.2.2")
    }
    
    func testPatientRootGetSOPClassUID() {
        XCTAssertEqual(QueryRetrieveInformationModel.patientRoot.getSOPClassUID, "1.2.840.10008.5.1.4.1.2.1.3")
    }
    
    func testStudyRootGetSOPClassUID() {
        XCTAssertEqual(QueryRetrieveInformationModel.studyRoot.getSOPClassUID, "1.2.840.10008.5.1.4.1.2.2.3")
    }
    
    // MARK: - C-MOVE Message Tests
    
    func testCMoveRequestCreation() {
        let request = CMoveRequest(
            messageID: 1,
            affectedSOPClassUID: studyRootQueryRetrieveMoveSOPClassUID,
            moveDestination: "MY_SCP",
            priority: .medium,
            presentationContextID: 1
        )
        
        XCTAssertEqual(request.messageID, 1)
        XCTAssertEqual(request.affectedSOPClassUID, studyRootQueryRetrieveMoveSOPClassUID)
        XCTAssertEqual(request.moveDestination, "MY_SCP")
        XCTAssertEqual(request.priority, .medium)
        XCTAssertEqual(request.presentationContextID, 1)
        XCTAssertTrue(request.hasDataSet)
        XCTAssertEqual(request.commandSet.command, .cMoveRequest)
    }
    
    func testCMoveRequestWithPatientRootModel() {
        let request = CMoveRequest(
            messageID: 1,
            affectedSOPClassUID: patientRootQueryRetrieveMoveSOPClassUID,
            moveDestination: "STORAGE_SCP",
            priority: .high,
            presentationContextID: 3
        )
        
        XCTAssertEqual(request.affectedSOPClassUID, patientRootQueryRetrieveMoveSOPClassUID)
        XCTAssertEqual(request.moveDestination, "STORAGE_SCP")
        XCTAssertEqual(request.priority, .high)
    }
    
    func testCMoveResponseCreation() {
        // Success response
        let successResponse = CMoveResponse(
            messageIDBeingRespondedTo: 1,
            affectedSOPClassUID: studyRootQueryRetrieveMoveSOPClassUID,
            status: .success,
            remaining: 0,
            completed: 10,
            failed: 0,
            warning: 0,
            presentationContextID: 1
        )
        
        XCTAssertEqual(successResponse.messageIDBeingRespondedTo, 1)
        XCTAssertEqual(successResponse.affectedSOPClassUID, studyRootQueryRetrieveMoveSOPClassUID)
        XCTAssertTrue(successResponse.status.isSuccess)
        XCTAssertEqual(successResponse.numberOfRemainingSuboperations, 0)
        XCTAssertEqual(successResponse.numberOfCompletedSuboperations, 10)
        XCTAssertEqual(successResponse.numberOfFailedSuboperations, 0)
        XCTAssertEqual(successResponse.numberOfWarningSuboperations, 0)
        
        // Pending response
        let pendingResponse = CMoveResponse(
            messageIDBeingRespondedTo: 1,
            affectedSOPClassUID: studyRootQueryRetrieveMoveSOPClassUID,
            status: .pending(warningOptionalKeys: false),
            remaining: 5,
            completed: 5,
            failed: 0,
            warning: 0,
            presentationContextID: 1
        )
        
        XCTAssertTrue(pendingResponse.status.isPending)
        XCTAssertEqual(pendingResponse.numberOfRemainingSuboperations, 5)
        XCTAssertEqual(pendingResponse.numberOfCompletedSuboperations, 5)
    }
    
    func testCMoveCommandSetEncoding() {
        let request = CMoveRequest(
            messageID: 42,
            affectedSOPClassUID: studyRootQueryRetrieveMoveSOPClassUID,
            moveDestination: "MY_SCP",
            presentationContextID: 1
        )
        
        let encodedData = request.commandSet.encode()
        
        // Verify the command set can be encoded
        XCTAssertGreaterThan(encodedData.count, 0)
        
        // Verify round-trip decode
        do {
            let decodedCommandSet = try CommandSet.decode(from: encodedData)
            XCTAssertEqual(decodedCommandSet.command, .cMoveRequest)
            XCTAssertEqual(decodedCommandSet.messageID, 42)
            XCTAssertEqual(decodedCommandSet.affectedSOPClassUID, studyRootQueryRetrieveMoveSOPClassUID)
            XCTAssertEqual(decodedCommandSet.moveDestination, "MY_SCP")
            XCTAssertTrue(decodedCommandSet.hasDataSet)
        } catch {
            XCTFail("Failed to decode command set: \(error)")
        }
    }
    
    // MARK: - C-GET Message Tests
    
    func testCGetRequestCreation() {
        let request = CGetRequest(
            messageID: 1,
            affectedSOPClassUID: studyRootQueryRetrieveGetSOPClassUID,
            priority: .medium,
            presentationContextID: 1
        )
        
        XCTAssertEqual(request.messageID, 1)
        XCTAssertEqual(request.affectedSOPClassUID, studyRootQueryRetrieveGetSOPClassUID)
        XCTAssertEqual(request.priority, .medium)
        XCTAssertEqual(request.presentationContextID, 1)
        XCTAssertTrue(request.hasDataSet)
        XCTAssertEqual(request.commandSet.command, .cGetRequest)
    }
    
    func testCGetRequestWithPatientRootModel() {
        let request = CGetRequest(
            messageID: 1,
            affectedSOPClassUID: patientRootQueryRetrieveGetSOPClassUID,
            priority: .high,
            presentationContextID: 3
        )
        
        XCTAssertEqual(request.affectedSOPClassUID, patientRootQueryRetrieveGetSOPClassUID)
        XCTAssertEqual(request.priority, .high)
    }
    
    func testCGetResponseCreation() {
        // Success response
        let successResponse = CGetResponse(
            messageIDBeingRespondedTo: 1,
            affectedSOPClassUID: studyRootQueryRetrieveGetSOPClassUID,
            status: .success,
            remaining: 0,
            completed: 10,
            failed: 0,
            warning: 0,
            presentationContextID: 1
        )
        
        XCTAssertEqual(successResponse.messageIDBeingRespondedTo, 1)
        XCTAssertEqual(successResponse.affectedSOPClassUID, studyRootQueryRetrieveGetSOPClassUID)
        XCTAssertTrue(successResponse.status.isSuccess)
        XCTAssertEqual(successResponse.numberOfRemainingSuboperations, 0)
        XCTAssertEqual(successResponse.numberOfCompletedSuboperations, 10)
        XCTAssertEqual(successResponse.numberOfFailedSuboperations, 0)
        XCTAssertEqual(successResponse.numberOfWarningSuboperations, 0)
        
        // Pending response
        let pendingResponse = CGetResponse(
            messageIDBeingRespondedTo: 1,
            affectedSOPClassUID: studyRootQueryRetrieveGetSOPClassUID,
            status: .pending(warningOptionalKeys: false),
            remaining: 5,
            completed: 5,
            failed: 0,
            warning: 0,
            presentationContextID: 1
        )
        
        XCTAssertTrue(pendingResponse.status.isPending)
        XCTAssertEqual(pendingResponse.numberOfRemainingSuboperations, 5)
    }
    
    func testCGetCommandSetEncoding() {
        let request = CGetRequest(
            messageID: 42,
            affectedSOPClassUID: studyRootQueryRetrieveGetSOPClassUID,
            presentationContextID: 1
        )
        
        let encodedData = request.commandSet.encode()
        
        // Verify the command set can be encoded
        XCTAssertGreaterThan(encodedData.count, 0)
        
        // Verify round-trip decode
        do {
            let decodedCommandSet = try CommandSet.decode(from: encodedData)
            XCTAssertEqual(decodedCommandSet.command, .cGetRequest)
            XCTAssertEqual(decodedCommandSet.messageID, 42)
            XCTAssertEqual(decodedCommandSet.affectedSOPClassUID, studyRootQueryRetrieveGetSOPClassUID)
            XCTAssertTrue(decodedCommandSet.hasDataSet)
        } catch {
            XCTFail("Failed to decode command set: \(error)")
        }
    }
    
    // MARK: - Message Fragmentation Tests
    
    func testCMoveRequestFragmentation() {
        let request = CMoveRequest(
            messageID: 1,
            affectedSOPClassUID: studyRootQueryRetrieveMoveSOPClassUID,
            moveDestination: "MY_SCP",
            presentationContextID: 1
        )
        
        // Create a sample identifier data set (Study Instance UID)
        let identifierData = Data([
            0x08, 0x00, 0x52, 0x00, // Query Retrieve Level tag
            0x43, 0x53,             // VR: CS
            0x06, 0x00,             // Length: 6
            0x53, 0x54, 0x55, 0x44, 0x59, 0x20  // "STUDY "
        ])
        
        let fragmenter = MessageFragmenter(maxPDUSize: 16384)
        let pdus = fragmenter.fragmentMessage(
            commandSet: request.commandSet,
            dataSet: identifierData,
            presentationContextID: 1
        )
        
        // Should have at least command and data set PDVs
        XCTAssertGreaterThanOrEqual(pdus.count, 2)
        
        // First PDU should be command
        let commandPDU = pdus[0]
        XCTAssertEqual(commandPDU.presentationDataValues.count, 1)
        XCTAssertTrue(commandPDU.presentationDataValues[0].isCommand)
    }
    
    func testCGetRequestFragmentation() {
        let request = CGetRequest(
            messageID: 1,
            affectedSOPClassUID: studyRootQueryRetrieveGetSOPClassUID,
            presentationContextID: 1
        )
        
        // Create a sample identifier data set
        let identifierData = Data([
            0x08, 0x00, 0x52, 0x00, // Query Retrieve Level tag
            0x43, 0x53,             // VR: CS
            0x06, 0x00,             // Length: 6
            0x53, 0x54, 0x55, 0x44, 0x59, 0x20  // "STUDY "
        ])
        
        let fragmenter = MessageFragmenter(maxPDUSize: 16384)
        let pdus = fragmenter.fragmentMessage(
            commandSet: request.commandSet,
            dataSet: identifierData,
            presentationContextID: 1
        )
        
        // Should have at least command and data set PDVs
        XCTAssertGreaterThanOrEqual(pdus.count, 2)
        
        // First PDU should be command
        let commandPDU = pdus[0]
        XCTAssertTrue(commandPDU.presentationDataValues[0].isCommand)
    }
    
    // MARK: - Presentation Context Tests
    
    func testCMovePresentationContextCreation() throws {
        let context = try PresentationContext(
            id: 1,
            abstractSyntax: studyRootQueryRetrieveMoveSOPClassUID,
            transferSyntaxes: [
                explicitVRLittleEndianTransferSyntaxUID,
                implicitVRLittleEndianTransferSyntaxUID
            ]
        )
        
        XCTAssertEqual(context.id, 1)
        XCTAssertEqual(context.abstractSyntax, studyRootQueryRetrieveMoveSOPClassUID)
        XCTAssertEqual(context.transferSyntaxes.count, 2)
    }
    
    func testCGetPresentationContextCreation() throws {
        let context = try PresentationContext(
            id: 1,
            abstractSyntax: studyRootQueryRetrieveGetSOPClassUID,
            transferSyntaxes: [
                explicitVRLittleEndianTransferSyntaxUID,
                implicitVRLittleEndianTransferSyntaxUID
            ]
        )
        
        XCTAssertEqual(context.id, 1)
        XCTAssertEqual(context.abstractSyntax, studyRootQueryRetrieveGetSOPClassUID)
        XCTAssertEqual(context.transferSyntaxes.count, 2)
    }
    
    // MARK: - Message Assembly Tests
    
    func testCMoveResponseAssembly() throws {
        // Create a C-MOVE response (pending, no data set)
        let response = CMoveResponse(
            messageIDBeingRespondedTo: 1,
            affectedSOPClassUID: studyRootQueryRetrieveMoveSOPClassUID,
            status: .pending(warningOptionalKeys: false),
            remaining: 5,
            completed: 3,
            failed: 0,
            warning: 0,
            presentationContextID: 1
        )
        
        // Fragment it
        let fragmenter = MessageFragmenter(maxPDUSize: 16384)
        let pdus = fragmenter.fragmentMessage(
            commandSet: response.commandSet,
            dataSet: nil,
            presentationContextID: 1
        )
        
        // Assemble it back
        let assembler = MessageAssembler()
        var assembledMessage: AssembledMessage?
        
        for pdu in pdus {
            assembledMessage = try assembler.addPDVs(from: pdu)
        }
        
        XCTAssertNotNil(assembledMessage)
        
        let moveResponse = assembledMessage?.asCMoveResponse()
        XCTAssertNotNil(moveResponse)
        XCTAssertEqual(moveResponse?.messageIDBeingRespondedTo, 1)
        XCTAssertTrue(moveResponse?.status.isPending ?? false)
        XCTAssertEqual(moveResponse?.numberOfRemainingSuboperations, 5)
        XCTAssertEqual(moveResponse?.numberOfCompletedSuboperations, 3)
    }
    
    func testCGetResponseAssembly() throws {
        // Create a C-GET response (success)
        let response = CGetResponse(
            messageIDBeingRespondedTo: 1,
            affectedSOPClassUID: studyRootQueryRetrieveGetSOPClassUID,
            status: .success,
            remaining: 0,
            completed: 10,
            failed: 0,
            warning: 0,
            presentationContextID: 1
        )
        
        // Fragment it
        let fragmenter = MessageFragmenter(maxPDUSize: 16384)
        let pdus = fragmenter.fragmentMessage(
            commandSet: response.commandSet,
            dataSet: nil,
            presentationContextID: 1
        )
        
        // Assemble it back
        let assembler = MessageAssembler()
        var assembledMessage: AssembledMessage?
        
        for pdu in pdus {
            assembledMessage = try assembler.addPDVs(from: pdu)
        }
        
        XCTAssertNotNil(assembledMessage)
        
        let getResponse = assembledMessage?.asCGetResponse()
        XCTAssertNotNil(getResponse)
        XCTAssertEqual(getResponse?.messageIDBeingRespondedTo, 1)
        XCTAssertTrue(getResponse?.status.isSuccess ?? false)
        XCTAssertEqual(getResponse?.numberOfCompletedSuboperations, 10)
    }
    
    // MARK: - Error Type Tests
    
    func testRetrieveFailedError() {
        let error = DICOMNetworkError.retrieveFailed(.refusedOutOfResources)
        
        switch error {
        case .retrieveFailed(let status):
            XCTAssertTrue(status.isFailure)
            XCTAssertEqual(status.rawValue, 0xA700)
        default:
            XCTFail("Expected retrieveFailed error")
        }
        
        let description = error.description
        XCTAssertTrue(description.contains("Retrieve failed"))
    }
    
    // MARK: - Common Storage SOP Class UIDs Tests
    
    func testCommonStorageSOPClassUIDsNotEmpty() {
        XCTAssertGreaterThan(commonStorageSOPClassUIDs.count, 0)
    }
    
    func testCommonStorageSOPClassUIDsIncludesCTImageStorage() {
        XCTAssertTrue(commonStorageSOPClassUIDs.contains("1.2.840.10008.5.1.4.1.1.2"))
    }
    
    func testCommonStorageSOPClassUIDsIncludesMRImageStorage() {
        XCTAssertTrue(commonStorageSOPClassUIDs.contains("1.2.840.10008.5.1.4.1.1.4"))
    }
    
    func testCommonStorageSOPClassUIDsIncludesSecondaryCaptureStorage() {
        XCTAssertTrue(commonStorageSOPClassUIDs.contains("1.2.840.10008.5.1.4.1.1.7"))
    }
    
    // MARK: - SOP Class UID Constants Tests
    
    func testMoveSOPClassUIDsAreValid() {
        XCTAssertFalse(patientRootQueryRetrieveMoveSOPClassUID.isEmpty)
        XCTAssertTrue(patientRootQueryRetrieveMoveSOPClassUID.hasPrefix("1.2.840.10008"))
        
        XCTAssertFalse(studyRootQueryRetrieveMoveSOPClassUID.isEmpty)
        XCTAssertTrue(studyRootQueryRetrieveMoveSOPClassUID.hasPrefix("1.2.840.10008"))
    }
    
    func testGetSOPClassUIDsAreValid() {
        XCTAssertFalse(patientRootQueryRetrieveGetSOPClassUID.isEmpty)
        XCTAssertTrue(patientRootQueryRetrieveGetSOPClassUID.hasPrefix("1.2.840.10008"))
        
        XCTAssertFalse(studyRootQueryRetrieveGetSOPClassUID.isEmpty)
        XCTAssertTrue(studyRootQueryRetrieveGetSOPClassUID.hasPrefix("1.2.840.10008"))
    }
}

// MARK: - Retrieve conformance (PS3.4 C.4.2.1.4.2, C.4.3.1.4.2, Table C.4-2, C.4.2.1.4.1)

final class RetrieveConformanceTests: XCTestCase {

    // MARK: RetrieveResult status semantics

    func testWarningStatusIsNotSuccess() {
        // PS3.4 C.4.2.1.4.2: 0xB000 = "Sub-operations Complete – One or more
        // Failures or Warnings"; only 0x0000 with zero failures is success.
        let result = RetrieveResult(
            status: DIMSEStatus.from(0xB000),
            progress: RetrieveProgress(remaining: 0, completed: 9, failed: 1, warning: 0))
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.isWarning)
        XCTAssertTrue(result.hasFailures)
        XCTAssertFalse(result.isFailure)
    }

    func testWarningStatusWithZeroCountersIsWarningNotSuccess() {
        let result = RetrieveResult(status: .warningCoercionOfDataElements,
                                    progress: RetrieveProgress(remaining: 0, completed: 5))
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.isWarning)
        XCTAssertFalse(result.hasFailures)
    }

    func testSuccessStatusWithWarningCounterIsWarning() {
        let result = RetrieveResult(status: .success,
                                    progress: RetrieveProgress(remaining: 0, completed: 5, warning: 1))
        XCTAssertTrue(result.isSuccess, "0x0000 with zero failures is success even with warning sub-ops")
        XCTAssertTrue(result.isWarning)
    }

    func testFailureStatusIsReportedNotThrown() {
        let result = RetrieveResult(status: .failedUnableToProcess,
                                    progress: RetrieveProgress(remaining: 3, completed: 2, failed: 1),
                                    failedSOPInstanceUIDs: ["1.2.3.4"])
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.isFailure)
        XCTAssertTrue(result.hasFailures)
        XCTAssertEqual(result.progress.completed, 2)
        XCTAssertEqual(result.failedSOPInstanceUIDs, ["1.2.3.4"])
        XCTAssertTrue(result.description.contains("1.2.3.4"))
    }

    func testFailedListAloneMeansHasFailures() {
        let result = RetrieveResult(status: .success, progress: RetrieveProgress(remaining: 0, completed: 1),
                                    failedSOPInstanceUIDs: ["1.2"])
        XCTAssertTrue(result.hasFailures)
    }

    // MARK: Failed SOP Instance UID List (0008,0058)

    func testFailedSOPInstanceUIDTag() {
        XCTAssertEqual(Tag.failedSOPInstanceUIDList, Tag(group: 0x0008, element: 0x0058))
    }

    func testFailedSOPInstanceUIDListParsedFromExplicitVRIdentifier() {
        let ts = explicitVRLittleEndianTransferSyntaxUID
        var identifier = Data()
        identifier += DICOMQueryService.encodeElement(tag: .queryRetrieveLevel, vr: .CS, value: "STUDY", explicit: true)
        identifier += DICOMQueryService.encodeElement(
            tag: .failedSOPInstanceUIDList, vr: .UI, value: "1.2.3.4.5\\1.2.3.4.6\\1.2.3.4.7", explicit: true)
        let failed = DICOMRetrieveService.failedSOPInstanceUIDs(from: identifier, transferSyntax: ts)
        XCTAssertEqual(failed, ["1.2.3.4.5", "1.2.3.4.6", "1.2.3.4.7"])
    }

    func testFailedSOPInstanceUIDListParsedFromImplicitVRIdentifier() {
        let ts = implicitVRLittleEndianTransferSyntaxUID
        let identifier = DICOMQueryService.encodeElement(
            tag: .failedSOPInstanceUIDList, vr: .UI, value: "1.2.3.4.5", explicit: false)
        XCTAssertEqual(DICOMRetrieveService.failedSOPInstanceUIDs(from: identifier, transferSyntax: ts), ["1.2.3.4.5"])
    }

    func testNoIdentifierYieldsEmptyFailedList() {
        XCTAssertEqual(DICOMRetrieveService.failedSOPInstanceUIDs(from: nil, transferSyntax: explicitVRLittleEndianTransferSyntaxUID), [])
        XCTAssertEqual(DICOMRetrieveService.failedSOPInstanceUIDs(from: Data(), transferSyntax: explicitVRLittleEndianTransferSyntaxUID), [])
    }

    // MARK: Patient Root unique keys (Tables C.6-2/C.6-3, C.4.2.1.4.1)

    func testPatientRootStudyRetrieveWithoutPatientIDThrows() {
        XCTAssertThrowsError(try DICOMRetrieveService.validateRetrieveKeys(.forStudy("1.2.3"), informationModel: .patientRoot)) { error in
            guard case DICOMNetworkError.invalidState(let message) = error else {
                return XCTFail("expected invalidState, got \(error)")
            }
            XCTAssertTrue(message.contains("Patient ID (0010,0020)"))
            XCTAssertTrue(message.contains("C.4.2.1.4.1"))
        }
    }

    func testPatientRootRetrievesWithPatientIDValidate() throws {
        try DICOMRetrieveService.validateRetrieveKeys(.forPatient(patientID: "P1"), informationModel: .patientRoot)
        try DICOMRetrieveService.validateRetrieveKeys(.forStudy("1.2.3", patientID: "P1"), informationModel: .patientRoot)
        try DICOMRetrieveService.validateRetrieveKeys(.forSeries(studyUID: "1.2.3", seriesUID: "1.2.3.4", patientID: "P1"), informationModel: .patientRoot)
        try DICOMRetrieveService.validateRetrieveKeys(
            .forInstance(studyUID: "1.2.3", seriesUID: "1.2.3.4", instanceUID: "1.2.3.4.5", patientID: "P1"), informationModel: .patientRoot)
    }

    func testPatientRootPatientLevelAllowsOnlyPatientID() {
        let keys = RetrieveKeys(level: .patient).patientID("P1").studyInstanceUID("1.2.3")
        XCTAssertThrowsError(try DICOMRetrieveService.validateRetrieveKeys(keys, informationModel: .patientRoot))
    }

    func testStudyRootDoesNotRequirePatientID() throws {
        try DICOMRetrieveService.validateRetrieveKeys(.forStudy("1.2.3"), informationModel: .studyRoot)
    }

    func testSeriesRetrieveRequiresStudyUID() {
        let keys = RetrieveKeys(level: .series).seriesInstanceUID("1.2.3.4")
        XCTAssertThrowsError(try DICOMRetrieveService.validateRetrieveKeys(keys, informationModel: .studyRoot))
    }

    func testImageRetrieveRequiresStudyAndSeriesUID() {
        let keys = RetrieveKeys(level: .image).studyInstanceUID("1.2.3").sopInstanceUID("1.2.3.4.5")
        XCTAssertThrowsError(try DICOMRetrieveService.validateRetrieveKeys(keys, informationModel: .studyRoot))
    }

    func testPatientLevelUnsupportedByStudyRootThrows() {
        XCTAssertThrowsError(try DICOMRetrieveService.validateRetrieveKeys(.forPatient(patientID: "P1"), informationModel: .studyRoot))
    }

    func testRetrieveKeysForPatientAndPatientIDInIdentifier() {
        let keys = RetrieveKeys.forSeries(studyUID: "1.2.3", seriesUID: "1.2.3.4", patientID: "P1")
        XCTAssertEqual(keys.keys.filter { $0.tag == .patientID }.count, 1)
        XCTAssertEqual(keys.value(for: .patientID), "P1")
        let identifier = DICOMRetrieveService.buildRetrieveIdentifier(keys: keys, transferSyntax: explicitVRLittleEndianTransferSyntaxUID)
        let attrs = DICOMQueryService.parseQueryResponse(data: identifier, transferSyntax: explicitVRLittleEndianTransferSyntaxUID)
        // "P1" is 2 bytes, already even: no pad (PS3.5 §6.2)
        XCTAssertEqual(attrs[.patientID], "P1".data(using: .ascii)!)
        XCTAssertEqual(attrs[.queryRetrieveLevel].flatMap { String(data: $0, encoding: .ascii) }, "SERIES")
        // patientID(_:) replaces an earlier value rather than duplicating the element
        XCTAssertEqual(keys.patientID("P2").keys.filter { $0.tag == .patientID }.count, 1)
    }

    // MARK: - Retrieve identifier encoding (PS3.5 7.1, 6.1.2; PS3.4 C.4.2.1.4.1)

    /// Tags of an Explicit VR LE data set in wire order.
    private func tagOrder(_ data: Data) -> [Tag] {
        var tags: [Tag] = []
        var offset = 0
        while offset + 8 <= data.count {
            let group = UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
            let element = UInt16(data[offset + 2]) | UInt16(data[offset + 3]) << 8
            tags.append(Tag(group: group, element: element))
            let length = Int(data[offset + 6]) | Int(data[offset + 7]) << 8   // 2-byte VRs only
            offset += 8 + length
        }
        return tags
    }

    func testImageLevelIdentifierWritesSOPInstanceUIDBeforeQueryRetrieveLevel() {
        let keys = RetrieveKeys.forInstance(studyUID: "1.2.3", seriesUID: "1.2.3.4", instanceUID: "1.2.3.4.5")
        let data = DICOMRetrieveService.buildRetrieveIdentifier(keys: keys, transferSyntax: explicitVRLittleEndianTransferSyntaxUID)
        let tags = tagOrder(data)
        XCTAssertEqual(tags, tags.sorted(), "ascending tag order (PS3.5 7.1)")
        XCTAssertEqual(tags, [.sopInstanceUID, .queryRetrieveLevel, .studyInstanceUID, .seriesInstanceUID])
    }

    func testLatin1PatientIDInsertsISOIR100AndEncodesLatin1() {
        let keys = RetrieveKeys.forStudy("1.2.3", patientID: "MÜLLER1")
        let data = DICOMRetrieveService.buildRetrieveIdentifier(keys: keys, transferSyntax: explicitVRLittleEndianTransferSyntaxUID)
        let attrs = DICOMQueryService.parseQueryResponse(data: data, transferSyntax: explicitVRLittleEndianTransferSyntaxUID)
        XCTAssertEqual(attrs[.specificCharacterSet].flatMap { String(data: $0, encoding: .ascii) }, "ISO_IR 100",
                       "PS3.4 C.4.2.1.4.1 / PS3.5 6.1.2: (0008,0005) declares the expanded repertoire")
        // Ü is the single byte 0xDC in ISO 8859-1; 7 bytes are space-padded to 8. Never zero length.
        XCTAssertEqual(attrs[.patientID], "MÜLLER1".data(using: .isoLatin1)! + Data([0x20]))
        XCTAssertEqual(tagOrder(data).first, .specificCharacterSet)
    }

    func testASCIIIdentifierCarriesNoSpecificCharacterSet() {
        let keys = RetrieveKeys.forStudy("1.2.3", patientID: "P1")
        let data = DICOMRetrieveService.buildRetrieveIdentifier(keys: keys, transferSyntax: implicitVRLittleEndianTransferSyntaxUID)
        let attrs = DICOMQueryService.parseQueryResponse(data: data, transferSyntax: implicitVRLittleEndianTransferSyntaxUID)
        XCTAssertNil(attrs[.specificCharacterSet])
    }

    func testUIDBuildersReplaceRatherThanDuplicate() {
        let keys = RetrieveKeys(level: .image)
            .studyInstanceUID("1").studyInstanceUID("2")
            .seriesInstanceUID("3").seriesInstanceUID("4")
            .sopInstanceUID("5").sopInstanceUID("6")
        XCTAssertEqual(keys.keys.count, 3, "a data element occurs at most once (PS3.5 7.1)")
        XCTAssertEqual(keys.value(for: .studyInstanceUID), "2")
        XCTAssertEqual(keys.value(for: .seriesInstanceUID), "4")
        XCTAssertEqual(keys.value(for: .sopInstanceUID), "6")
    }

}
