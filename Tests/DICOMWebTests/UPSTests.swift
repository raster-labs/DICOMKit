import XCTest
@testable import DICOMWeb

/// Tests for UPS (Unified Procedure Step) data types
final class UPSTests: XCTestCase {
    
    // MARK: - UPSState Tests
    
    func testUPSStateRawValues() {
        XCTAssertEqual(UPSState.scheduled.rawValue, "SCHEDULED")
        XCTAssertEqual(UPSState.inProgress.rawValue, "IN PROGRESS")
        XCTAssertEqual(UPSState.completed.rawValue, "COMPLETED")
        XCTAssertEqual(UPSState.canceled.rawValue, "CANCELED")
    }
    
    func testUPSStateIsFinal() {
        XCTAssertFalse(UPSState.scheduled.isFinal)
        XCTAssertFalse(UPSState.inProgress.isFinal)
        XCTAssertTrue(UPSState.completed.isFinal)
        XCTAssertTrue(UPSState.canceled.isFinal)
    }
    
    func testUPSStateValidTransitions() {
        // From SCHEDULED
        XCTAssertTrue(UPSState.scheduled.canTransition(to: .inProgress))
        // PS3.4 Table CC.1.1-2: Change State to CANCELED from SCHEDULED fails (C310H); the SCP
        // cancels a SCHEDULED UPS itself on Request Cancel (CC.2.2.3)
        XCTAssertFalse(UPSState.scheduled.canTransition(to: .canceled))
        XCTAssertFalse(UPSState.scheduled.canTransition(to: .completed))
        XCTAssertFalse(UPSState.scheduled.canTransition(to: .scheduled))
        
        // From IN PROGRESS
        XCTAssertTrue(UPSState.inProgress.canTransition(to: .completed))
        XCTAssertTrue(UPSState.inProgress.canTransition(to: .canceled))
        XCTAssertFalse(UPSState.inProgress.canTransition(to: .scheduled))
        XCTAssertFalse(UPSState.inProgress.canTransition(to: .inProgress))
        
        // From COMPLETED (no transitions allowed)
        XCTAssertFalse(UPSState.completed.canTransition(to: .scheduled))
        XCTAssertFalse(UPSState.completed.canTransition(to: .inProgress))
        XCTAssertFalse(UPSState.completed.canTransition(to: .canceled))
        XCTAssertFalse(UPSState.completed.canTransition(to: .completed))
        
        // From CANCELED (no transitions allowed)
        XCTAssertFalse(UPSState.canceled.canTransition(to: .scheduled))
        XCTAssertFalse(UPSState.canceled.canTransition(to: .inProgress))
        XCTAssertFalse(UPSState.canceled.canTransition(to: .completed))
        XCTAssertFalse(UPSState.canceled.canTransition(to: .canceled))
    }
    
    // MARK: - UPSPriority Tests
    
    func testUPSPriorityRawValues() {
        XCTAssertEqual(UPSPriority.stat.rawValue, "STAT")
        XCTAssertEqual(UPSPriority.high.rawValue, "HIGH")
        XCTAssertEqual(UPSPriority.medium.rawValue, "MEDIUM")
        XCTAssertEqual(UPSPriority.low.rawValue, "LOW")
    }
    
    func testUPSPriorityNumericValues() {
        // Lower numeric value = higher priority
        XCTAssertEqual(UPSPriority.stat.numericValue, 1)
        XCTAssertEqual(UPSPriority.high.numericValue, 2)
        XCTAssertEqual(UPSPriority.medium.numericValue, 3)
        XCTAssertEqual(UPSPriority.low.numericValue, 4)
        
        // Verify ordering
        XCTAssertLessThan(UPSPriority.stat.numericValue, UPSPriority.high.numericValue)
        XCTAssertLessThan(UPSPriority.high.numericValue, UPSPriority.medium.numericValue)
        XCTAssertLessThan(UPSPriority.medium.numericValue, UPSPriority.low.numericValue)
    }
    
    // MARK: - Workitem Tests
    
    func testWorkitemBasicInitialization() {
        let workitem = Workitem(workitemUID: "1.2.3.4.5")
        
        XCTAssertEqual(workitem.workitemUID, "1.2.3.4.5")
        XCTAssertEqual(workitem.state, .scheduled)
        XCTAssertEqual(workitem.priority, .medium)
    }
    
    func testWorkitemSchedulingInitialization() {
        let scheduledDate = Date()
        let workitem = Workitem(
            workitemUID: "1.2.3.4.5",
            scheduledStartDateTime: scheduledDate,
            patientName: "Smith^John",
            patientID: "PAT001",
            procedureStepLabel: "CT Scan",
            priority: .high
        )
        
        XCTAssertEqual(workitem.workitemUID, "1.2.3.4.5")
        XCTAssertEqual(workitem.state, .scheduled)
        XCTAssertEqual(workitem.priority, .high)
        XCTAssertEqual(workitem.scheduledStartDateTime, scheduledDate)
        XCTAssertEqual(workitem.patientName, "Smith^John")
        XCTAssertEqual(workitem.patientID, "PAT001")
        XCTAssertEqual(workitem.procedureStepLabel, "CT Scan")
    }
    
    func testWorkitemDescription() {
        let workitem = Workitem(
            workitemUID: "1.2.3.4.5",
            scheduledStartDateTime: Date(),
            patientName: "Smith^John",
            procedureStepLabel: "CT Scan"
        )
        
        let description = workitem.description
        XCTAssertTrue(description.contains("1.2.3.4.5"))
        XCTAssertTrue(description.contains("SCHEDULED"))
        XCTAssertTrue(description.contains("MEDIUM"))
        XCTAssertTrue(description.contains("CT Scan"))
        XCTAssertTrue(description.contains("Smith^John"))
    }
    
    // MARK: - CodedEntry Tests
    
    func testCodedEntryInitialization() {
        let code = CodedEntry(
            codeValue: "12345",
            codingSchemeDesignator: "DCM",
            codingSchemeVersion: "01",
            codeMeaning: "Test Procedure"
        )
        
        XCTAssertEqual(code.codeValue, "12345")
        XCTAssertEqual(code.codingSchemeDesignator, "DCM")
        XCTAssertEqual(code.codingSchemeVersion, "01")
        XCTAssertEqual(code.codeMeaning, "Test Procedure")
    }
    
    func testCodedEntryEquality() {
        let code1 = CodedEntry(codeValue: "12345", codingSchemeDesignator: "DCM", codeMeaning: "Test")
        let code2 = CodedEntry(codeValue: "12345", codingSchemeDesignator: "DCM", codeMeaning: "Test")
        let code3 = CodedEntry(codeValue: "67890", codingSchemeDesignator: "DCM", codeMeaning: "Different")
        
        XCTAssertEqual(code1, code2)
        XCTAssertNotEqual(code1, code3)
    }
    
    // MARK: - HumanPerformer Tests
    
    func testHumanPerformerInitialization() {
        let performer = HumanPerformer(
            performerCode: CodedEntry(codeValue: "121081", codingSchemeDesignator: "DCM", codeMeaning: "Physician"),
            performerName: "Smith^Jane",
            performerOrganization: "City Hospital"
        )
        
        XCTAssertEqual(performer.performerName, "Smith^Jane")
        XCTAssertEqual(performer.performerOrganization, "City Hospital")
        XCTAssertEqual(performer.performerCode?.codeValue, "121081")
    }
    
    // MARK: - ReferencedInstance Tests
    
    func testReferencedInstanceInitialization() {
        let ref = ReferencedInstance(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7",
            studyInstanceUID: "1.2.3.4",
            seriesInstanceUID: "1.2.3.4.5"
        )
        
        XCTAssertEqual(ref.sopClassUID, "1.2.840.10008.5.1.4.1.1.2")
        XCTAssertEqual(ref.sopInstanceUID, "1.2.3.4.5.6.7")
        XCTAssertEqual(ref.studyInstanceUID, "1.2.3.4")
        XCTAssertEqual(ref.seriesInstanceUID, "1.2.3.4.5")
    }
    
    // MARK: - ProgressInformation Tests
    
    func testProgressInformationInitialization() {
        let progress = ProgressInformation(
            progressPercentage: 50,
            progressDescription: "Halfway done",
            communicationURIs: ["ws://localhost:8080/progress"],
            contactDisplayName: "Dr. Smith"
        )
        
        XCTAssertEqual(progress.progressPercentage, 50)
        XCTAssertEqual(progress.progressDescription, "Halfway done")
        XCTAssertEqual(progress.communicationURIs?.count, 1)
        XCTAssertEqual(progress.contactDisplayName, "Dr. Smith")
    }
    
    // MARK: - UPSStateChangeRequest Tests
    
    func testStateChangeRequestToInProgress() {
        let request = UPSStateChangeRequest(
            targetState: .inProgress,
            transactionUID: nil
        )
        
        XCTAssertEqual(request.targetState, .inProgress)
        XCTAssertNil(request.transactionUID)
    }
    
    func testStateChangeRequestToCompleted() {
        let request = UPSStateChangeRequest(
            targetState: .completed,
            transactionUID: "2.25.123456789"
        )
        
        XCTAssertEqual(request.targetState, .completed)
        XCTAssertEqual(request.transactionUID, "2.25.123456789")
    }
    
    // MARK: - UPSCancellationRequest Tests
    
    func testCancellationRequestInitialization() {
        let request = UPSCancellationRequest(
            workitemUID: "1.2.3.4.5",
            reason: "Patient no-show",
            contactDisplayName: "Reception"
        )
        
        XCTAssertEqual(request.workitemUID, "1.2.3.4.5")
        XCTAssertEqual(request.reason, "Patient no-show")
        XCTAssertEqual(request.contactDisplayName, "Reception")
    }
}

// MARK: - UPS Query Tests

final class UPSQueryTests: XCTestCase {
    
    func testEmptyQuery() {
        let query = UPSQuery()
        
        XCTAssertTrue(query.isEmpty)
        XCTAssertEqual(query.parameterCount, 0)
    }
    
    func testQueryByState() {
        let query = UPSQuery().state(.scheduled)
        
        let params = query.toParameters()
        XCTAssertEqual(params[UPSQueryAttribute.procedureStepState], "SCHEDULED")
    }
    
    func testQueryByMultipleStates() {
        let query = UPSQuery().states([.scheduled, .inProgress])
        
        let params = query.toParameters()
        XCTAssertEqual(params[UPSQueryAttribute.procedureStepState], "SCHEDULED,IN PROGRESS")
    }
    
    func testQueryByPriority() {
        let query = UPSQuery().priority(.high)
        
        let params = query.toParameters()
        XCTAssertEqual(params[UPSQueryAttribute.scheduledProcedureStepPriority], "HIGH")
    }
    
    func testQueryByPatientID() {
        let query = UPSQuery().patientID("PAT001")
        
        let params = query.toParameters()
        XCTAssertEqual(params[UPSQueryAttribute.patientID], "PAT001")
    }
    
    func testQueryByPatientName() {
        let query = UPSQuery().patientName("Smith*")
        
        let params = query.toParameters()
        XCTAssertEqual(params[UPSQueryAttribute.patientName], "Smith*")
    }
    
    func testQueryWithPagination() {
        let query = UPSQuery()
            .limit(10)
            .offset(20)
        
        let params = query.toParameters()
        XCTAssertEqual(params["limit"], "10")
        XCTAssertEqual(params["offset"], "20")
    }
    
    func testQueryIncludeFields() {
        let query = UPSQuery()
            .includeField(UPSQueryAttribute.procedureStepLabel)
            .includeField(UPSQueryAttribute.patientName)
        
        let params = query.toParameters()
        XCTAssertTrue(params["includefield"]?.contains(UPSQueryAttribute.procedureStepLabel) == true)
        XCTAssertTrue(params["includefield"]?.contains(UPSQueryAttribute.patientName) == true)
    }
    
    func testQueryIncludeAllFields() {
        let query = UPSQuery().includeAllFields()
        
        let params = query.toParameters()
        XCTAssertEqual(params["includefield"], "all")
    }
    
    func testQueryFuzzyMatching() {
        let query = UPSQuery().fuzzyMatching(true)
        
        let params = query.toParameters()
        XCTAssertEqual(params["fuzzymatching"], "true")
    }
    
    func testCombinedQuery() {
        let query = UPSQuery()
            .state(.scheduled)
            .priority(.high)
            .patientID("PAT001")
            .limit(10)
        
        let params = query.toParameters()
        XCTAssertEqual(params[UPSQueryAttribute.procedureStepState], "SCHEDULED")
        XCTAssertEqual(params[UPSQueryAttribute.scheduledProcedureStepPriority], "HIGH")
        XCTAssertEqual(params[UPSQueryAttribute.patientID], "PAT001")
        XCTAssertEqual(params["limit"], "10")
        XCTAssertEqual(query.parameterCount, 4)
    }
    
    // MARK: - Convenience Queries
    
    func testScheduledQuery() {
        let query = UPSQuery.scheduled(limit: 5)
        
        let params = query.toParameters()
        XCTAssertEqual(params[UPSQueryAttribute.procedureStepState], "SCHEDULED")
        XCTAssertEqual(params["limit"], "5")
    }
    
    func testInProgressQuery() {
        let query = UPSQuery.inProgress()
        
        let params = query.toParameters()
        XCTAssertEqual(params[UPSQueryAttribute.procedureStepState], "IN PROGRESS")
    }
    
    func testForPatientQuery() {
        let query = UPSQuery.forPatient("PAT001", state: .scheduled)
        
        let params = query.toParameters()
        XCTAssertEqual(params[UPSQueryAttribute.patientID], "PAT001")
        XCTAssertEqual(params[UPSQueryAttribute.procedureStepState], "SCHEDULED")
    }
    
    func testHighPriorityQuery() {
        let query = UPSQuery.highPriority()
        
        let params = query.toParameters()
        XCTAssertEqual(params[UPSQueryAttribute.procedureStepState], "SCHEDULED")
        // PS3.3 C.30.2: STAT is not a defined term; HIGH is "equivalent to a STAT request"
        XCTAssertFalse(params[UPSQueryAttribute.scheduledProcedureStepPriority]?.contains("STAT") == true)
        XCTAssertTrue(params[UPSQueryAttribute.scheduledProcedureStepPriority]?.contains("HIGH") == true)
    }
}

// MARK: - UPS Results Tests

final class UPSResultsTests: XCTestCase {
    
    func testWorkitemResultParsing() {
        let json: [String: Any] = [
            "00080018": ["Value": ["1.2.3.4.5"]],
            "00741000": ["Value": ["SCHEDULED"]],
            "00741200": ["Value": ["HIGH"]],
            "00741204": ["Value": ["CT Abdomen"]],
            "00100010": ["Value": [["Alphabetic": "Smith^John"]]],
            "00100020": ["Value": ["PAT001"]]
        ]
        
        let result = WorkitemResult.parse(json: json)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.workitemUID, "1.2.3.4.5")
        XCTAssertEqual(result?.state, .scheduled)
        XCTAssertEqual(result?.priority, .high)
        XCTAssertEqual(result?.procedureStepLabel, "CT Abdomen")
        XCTAssertEqual(result?.patientName, "Smith^John")
        XCTAssertEqual(result?.patientID, "PAT001")
    }
    
    func testWorkitemResultParsingMissingUID() {
        let json: [String: Any] = [
            "00741000": ["Value": ["SCHEDULED"]]
        ]
        
        let result = WorkitemResult.parse(json: json)
        
        XCTAssertNil(result)
    }
    
    // MARK: - Shared Worklist Search Builder (CLI ⇄ app parity)

    /// The shared builder maps ONLY the two real `dicom-wado ups --search` flags and
    /// sets no `limit`/`includefield` — the exact CLI behaviour both the app and the
    /// parity reference must mirror, with no app-only filters.
    func testWorkitemSearchEmptyFilters() throws {
        let query = try UPSQuery.workitemSearch(filterState: "", scheduledStation: "")
        XCTAssertTrue(query.toParameters().isEmpty)
        let nilQuery = try UPSQuery.workitemSearch(filterState: nil, scheduledStation: nil)
        XCTAssertTrue(nilQuery.toParameters().isEmpty)
    }

    func testWorkitemSearchStateFilter() throws {
        let params = try UPSQuery.workitemSearch(filterState: "SCHEDULED", scheduledStation: "").toParameters()
        XCTAssertEqual(params, ["00741000": "SCHEDULED"])  // exactly one filter, no limit / includefield

        // INPROGRESS alias resolves to the canonical "IN PROGRESS" rawValue (matches the CLI).
        let inProgress = try UPSQuery.workitemSearch(filterState: "INPROGRESS", scheduledStation: "").toParameters()
        XCTAssertEqual(inProgress, ["00741000": "IN PROGRESS"])
    }

    /// D107: PS3.3 2026a Table C.30.1-1 (Enumerated Values) spells the state "IN PROGRESS" (with a space); the
    /// shared builder accepts it as written, case-insensitively, and still takes IN_PROGRESS.
    func testWorkitemSearchAcceptsTheStandardInProgressTerm() throws {
        for term in ["IN PROGRESS", "in progress", " IN PROGRESS ", "IN_PROGRESS"] {
            let params = try UPSQuery.workitemSearch(filterState: term, scheduledStation: nil).toParameters()
            XCTAssertEqual(params, ["00741000": "IN PROGRESS"], term)
        }
        XCTAssertThrowsError(try UPSQuery.workitemSearch(filterState: "IN  PROGRESS", scheduledStation: nil))
        XCTAssertThrowsError(try UPSQuery.workitemSearch(filterState: "STARTED", scheduledStation: nil)) { error in
            XCTAssertTrue((error as? UPSSearchFilterError)?.description.contains("IN PROGRESS") == true)
        }
    }

    func testWorkitemSearchStationFilter() throws {
        let params = try UPSQuery.workitemSearch(filterState: "", scheduledStation: "CT_AE_01").toParameters()
        XCTAssertEqual(params, ["00404025": "CT_AE_01"])
    }

    func testWorkitemSearchBothFilters() throws {
        let params = try UPSQuery.workitemSearch(filterState: "COMPLETED", scheduledStation: "CT_AE_01").toParameters()
        XCTAssertEqual(params, ["00741000": "COMPLETED", "00404025": "CT_AE_01"])
    }

    func testWorkitemSearchInvalidStateThrows() {
        XCTAssertThrowsError(try UPSQuery.workitemSearch(filterState: "BOGUS", scheduledStation: "")) { error in
            XCTAssertEqual(error as? UPSSearchFilterError, .invalidState("BOGUS"))
        }
    }

    // MARK: - Shared UPSResultFormatter (CLI ⇄ app parity)

    func testUPSResultFormatterJSONAndCSV() {
        let items = [
            WorkitemResult(workitemUID: "1.2.3", state: .scheduled,
                           procedureStepLabel: "CT Chest", patientName: "Doe^Jane", patientID: "PAT001"),
            WorkitemResult(workitemUID: "1.2.4", state: .inProgress)
        ]
        let formatter = UPSResultFormatter()

        // JSON carries the full attribute set and is valid JSON.
        let jsonString = formatter.format(items, format: .json)
        let parsed = (try? JSONSerialization.jsonObject(with: Data(jsonString.utf8))) as? [[String: Any]]
        XCTAssertEqual(parsed?.count, 2)
        XCTAssertEqual(parsed?.first?["workitemUID"] as? String, "1.2.3")
        XCTAssertEqual(parsed?.first?["patientName"] as? String, "Doe^Jane")

        // CSV is a header row + one row per workitem.
        let csv = formatter.format(items, format: .csv)
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.first, "WorkitemUID,State,ProcedureStepLabel,PatientName,PatientID")
        XCTAssertEqual(lines.count, 3)

        // Table renders a "="-bordered block with a header.
        let table = formatter.format(items, format: .table)
        XCTAssertTrue(table.contains("Worklist UID"))
        XCTAssertTrue(table.contains("1.2.3"))
    }

    func testUPSQueryResultParsing() {
        let jsonArray: [[String: Any]] = [
            [
                "00080018": ["Value": ["1.2.3.4.5"]],
                "00741000": ["Value": ["SCHEDULED"]]
            ],
            [
                "00080018": ["Value": ["1.2.3.4.6"]],
                "00741000": ["Value": ["IN PROGRESS"]]
            ]
        ]
        
        let result = UPSQueryResult.parse(
            jsonArray: jsonArray,
            totalCount: 10,
            offset: 0,
            limit: 2
        )
        
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.totalCount, 10)
        XCTAssertTrue(result.hasMore)
        XCTAssertEqual(result.nextOffset, 2)
    }
    
    func testEmptyQueryResult() {
        let result = UPSQueryResult.empty
        
        XCTAssertEqual(result.count, 0)
        XCTAssertEqual(result.totalCount, 0)
        XCTAssertFalse(result.hasMore)
    }
    
    func testPaginationInfo() {
        let pagination = PaginationInfo(offset: 10, limit: 20, hasMore: true)
        
        XCTAssertEqual(pagination.offset, 10)
        XCTAssertEqual(pagination.limit, 20)
        XCTAssertTrue(pagination.hasMore)
        XCTAssertEqual(pagination.nextOffset, 30)
    }
    
    func testPaginationInfoNoMoreResults() {
        let pagination = PaginationInfo(offset: 0, limit: 10, hasMore: false)
        
        XCTAssertNil(pagination.nextOffset)
    }
}

// MARK: - UPS Error Tests

final class UPSErrorTests: XCTestCase {
    
    func testWorkitemNotFoundError() {
        let error = UPSError.workitemNotFound(uid: "1.2.3.4.5")
        
        XCTAssertTrue(error.description.contains("1.2.3.4.5"))
        XCTAssertTrue(error.description.contains("not found"))
    }
    
    func testInvalidStateTransitionError() {
        let error = UPSError.invalidStateTransition(from: .completed, to: .inProgress)
        
        XCTAssertTrue(error.description.contains("COMPLETED"))
        XCTAssertTrue(error.description.contains("IN PROGRESS"))
        XCTAssertTrue(error.description.contains("Invalid state transition"))
    }
    
    func testTransactionUIDRequiredError() {
        let error = UPSError.transactionUIDRequired
        
        XCTAssertTrue(error.description.contains("Transaction UID required"))
    }
    
    func testWorkitemInFinalStateError() {
        let error = UPSError.workitemInFinalState(state: .completed)
        
        XCTAssertTrue(error.description.contains("COMPLETED"))
        XCTAssertTrue(error.description.contains("final state"))
    }
}

// MARK: - UPS Storage Provider Tests

final class InMemoryUPSStorageProviderTests: XCTestCase {
    
    func testCreateAndRetrieveWorkitem() async throws {
        let storage = InMemoryUPSStorageProvider()
        
        let workitem = Workitem(
            workitemUID: "1.2.3.4.5",
            scheduledStartDateTime: Date(),
            patientName: "Smith^John",
            patientID: "PAT001"
        )
        
        try await storage.createWorkitem(workitem)
        
        let retrieved = try await storage.getWorkitem(workitemUID: "1.2.3.4.5")
        
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.workitemUID, "1.2.3.4.5")
        XCTAssertEqual(retrieved?.patientName, "Smith^John")
        XCTAssertEqual(retrieved?.patientID, "PAT001")
    }
    
    func testCreateDuplicateWorkitem() async throws {
        let storage = InMemoryUPSStorageProvider()
        
        let workitem = Workitem(workitemUID: "1.2.3.4.5")
        try await storage.createWorkitem(workitem)
        
        do {
            try await storage.createWorkitem(workitem)
            XCTFail("Expected error to be thrown")
        } catch let error as UPSError {
            if case .workitemAlreadyExists(let uid) = error {
                XCTAssertEqual(uid, "1.2.3.4.5")
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }
    
    func testUpdateWorkitem() async throws {
        let storage = InMemoryUPSStorageProvider()
        
        var workitem = Workitem(workitemUID: "1.2.3.4.5")
        try await storage.createWorkitem(workitem)
        
        workitem.patientName = "Updated Name"
        try await storage.updateWorkitem(workitem)
        
        let retrieved = try await storage.getWorkitem(workitemUID: "1.2.3.4.5")
        XCTAssertEqual(retrieved?.patientName, "Updated Name")
    }
    
    func testDeleteWorkitem() async throws {
        let storage = InMemoryUPSStorageProvider()
        
        let workitem = Workitem(workitemUID: "1.2.3.4.5")
        try await storage.createWorkitem(workitem)
        
        let deleted = try await storage.deleteWorkitem(workitemUID: "1.2.3.4.5")
        XCTAssertTrue(deleted)
        
        let retrieved = try await storage.getWorkitem(workitemUID: "1.2.3.4.5")
        XCTAssertNil(retrieved)
    }
    
    func testDeleteNonexistentWorkitem() async throws {
        let storage = InMemoryUPSStorageProvider()
        
        let deleted = try await storage.deleteWorkitem(workitemUID: "nonexistent")
        XCTAssertFalse(deleted)
    }
    
    func testSearchByState() async throws {
        let storage = InMemoryUPSStorageProvider()
        
        let w1 = Workitem(workitemUID: "1", state: .scheduled)
        let w2 = Workitem(workitemUID: "2", state: .scheduled)
        let w3 = Workitem(workitemUID: "3", state: .inProgress)
        
        try await storage.createWorkitem(w1)
        try await storage.createWorkitem(w2)
        try await storage.createWorkitem(w3)
        
        let query = UPSStorageQuery(state: .scheduled)
        let results = try await storage.searchWorkitems(query: query)
        
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.state == .scheduled })
    }
    
    func testSearchByPriority() async throws {
        let storage = InMemoryUPSStorageProvider()
        
        let w1 = Workitem(workitemUID: "1", priority: .high)
        let w2 = Workitem(workitemUID: "2", priority: .high)
        let w3 = Workitem(workitemUID: "3", priority: .low)
        
        try await storage.createWorkitem(w1)
        try await storage.createWorkitem(w2)
        try await storage.createWorkitem(w3)
        
        let query = UPSStorageQuery(priority: .high)
        let results = try await storage.searchWorkitems(query: query)
        
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.priority == .high })
    }
    
    func testSearchByPatientID() async throws {
        let storage = InMemoryUPSStorageProvider()
        
        var w1 = Workitem(workitemUID: "1")
        w1.patientID = "PAT001"
        var w2 = Workitem(workitemUID: "2")
        w2.patientID = "PAT002"
        
        try await storage.createWorkitem(w1)
        try await storage.createWorkitem(w2)
        
        let query = UPSStorageQuery(patientID: "PAT001")
        let results = try await storage.searchWorkitems(query: query)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.patientID, "PAT001")
    }
    
    func testSearchWithWildcard() async throws {
        let storage = InMemoryUPSStorageProvider()
        
        var w1 = Workitem(workitemUID: "1")
        w1.patientName = "Smith^John"
        var w2 = Workitem(workitemUID: "2")
        w2.patientName = "Smith^Jane"
        var w3 = Workitem(workitemUID: "3")
        w3.patientName = "Jones^Bob"
        
        try await storage.createWorkitem(w1)
        try await storage.createWorkitem(w2)
        try await storage.createWorkitem(w3)
        
        let query = UPSStorageQuery(patientName: "Smith*")
        let results = try await storage.searchWorkitems(query: query)
        
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.patientName?.hasPrefix("Smith") == true })
    }
    
    func testSearchWithPagination() async throws {
        let storage = InMemoryUPSStorageProvider()
        
        // Create 5 workitems
        for i in 1...5 {
            let workitem = Workitem(workitemUID: "1.2.3.\(i)")
            try await storage.createWorkitem(workitem)
        }
        
        let query1 = UPSStorageQuery(offset: 0, limit: 2)
        let results1 = try await storage.searchWorkitems(query: query1)
        XCTAssertEqual(results1.count, 2)
        
        let query2 = UPSStorageQuery(offset: 2, limit: 2)
        let results2 = try await storage.searchWorkitems(query: query2)
        XCTAssertEqual(results2.count, 2)
        
        let query3 = UPSStorageQuery(offset: 4, limit: 2)
        let results3 = try await storage.searchWorkitems(query: query3)
        XCTAssertEqual(results3.count, 1)
    }
    
    func testChangeStateToInProgress() async throws {
        let storage = InMemoryUPSStorageProvider()
        
        let workitem = Workitem(workitemUID: "1.2.3.4.5", state: .scheduled)
        try await storage.createWorkitem(workitem)
        
        try await storage.changeWorkitemState(
            workitemUID: "1.2.3.4.5",
            newState: .inProgress,
            transactionUID: nil
        )
        
        let retrieved = try await storage.getWorkitem(workitemUID: "1.2.3.4.5")
        XCTAssertEqual(retrieved?.state, .inProgress)
        XCTAssertNotNil(retrieved?.transactionUID)
    }
    
    func testChangeStateToCompleted() async throws {
        let storage = InMemoryUPSStorageProvider()
        
        var workitem = Workitem(workitemUID: "1.2.3.4.5", state: .scheduled)
        try await storage.createWorkitem(workitem)
        
        // First transition to IN PROGRESS
        try await storage.changeWorkitemState(
            workitemUID: "1.2.3.4.5",
            newState: .inProgress,
            transactionUID: nil
        )
        
        // Get the transaction UID
        let transactionUID = try await storage.getTransactionUID(workitemUID: "1.2.3.4.5")
        XCTAssertNotNil(transactionUID)
        
        // Now complete with the transaction UID
        try await storage.changeWorkitemState(
            workitemUID: "1.2.3.4.5",
            newState: .completed,
            transactionUID: transactionUID
        )
        
        let retrieved = try await storage.getWorkitem(workitemUID: "1.2.3.4.5")
        XCTAssertEqual(retrieved?.state, .completed)
    }
    
    func testChangeStateInvalidTransition() async throws {
        let storage = InMemoryUPSStorageProvider()
        
        let workitem = Workitem(workitemUID: "1.2.3.4.5", state: .scheduled)
        try await storage.createWorkitem(workitem)
        
        // Try to complete directly from SCHEDULED (should fail)
        do {
            try await storage.changeWorkitemState(
                workitemUID: "1.2.3.4.5",
                newState: .completed,
                transactionUID: nil
            )
            XCTFail("Expected error to be thrown")
        } catch let error as UPSError {
            if case .invalidStateTransition(let from, let to) = error {
                XCTAssertEqual(from, .scheduled)
                XCTAssertEqual(to, .completed)
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }
    
    func testChangeStateMissingTransactionUID() async throws {
        let storage = InMemoryUPSStorageProvider()
        
        var workitem = Workitem(workitemUID: "1.2.3.4.5", state: .inProgress)
        workitem.transactionUID = "2.25.12345"
        try await storage.createWorkitem(workitem)
        
        // Try to complete without transaction UID (should fail)
        do {
            try await storage.changeWorkitemState(
                workitemUID: "1.2.3.4.5",
                newState: .completed,
                transactionUID: nil
            )
            XCTFail("Expected error to be thrown")
        } catch let error as UPSError {
            XCTAssertEqual(error, .transactionUIDRequired)
        }
    }
    
    func testCountWorkitems() async throws {
        let storage = InMemoryUPSStorageProvider()
        
        let w1 = Workitem(workitemUID: "1", state: .scheduled)
        let w2 = Workitem(workitemUID: "2", state: .scheduled)
        let w3 = Workitem(workitemUID: "3", state: .inProgress)
        
        try await storage.createWorkitem(w1)
        try await storage.createWorkitem(w2)
        try await storage.createWorkitem(w3)
        
        let allCount = try await storage.countWorkitems(query: UPSStorageQuery())
        XCTAssertEqual(allCount, 3)
        
        let scheduledCount = try await storage.countWorkitems(query: UPSStorageQuery(state: .scheduled))
        XCTAssertEqual(scheduledCount, 2)
    }
    
    func testUpdateProgress() async throws {
        let storage = InMemoryUPSStorageProvider()
        
        let workitem = Workitem(workitemUID: "1.2.3.4.5")
        try await storage.createWorkitem(workitem)
        
        let progress = ProgressInformation(
            progressPercentage: 50,
            progressDescription: "Halfway done"
        )
        
        try await storage.updateProgress(workitemUID: "1.2.3.4.5", progress: progress)
        
        let retrieved = try await storage.getWorkitem(workitemUID: "1.2.3.4.5")
        XCTAssertEqual(retrieved?.progressInformation?.progressPercentage, 50)
        XCTAssertEqual(retrieved?.progressInformation?.progressDescription, "Halfway done")
    }
}

// MARK: - UPS URL Builder Tests

final class UPSURLBuilderTests: XCTestCase {
    
    var urlBuilder: DICOMwebURLBuilder!
    
    override func setUp() {
        super.setUp()
        urlBuilder = try! DICOMwebURLBuilder(baseURLString: "https://pacs.example.com/dicom-web")
    }
    
    func testWorkitemsURL() {
        let url = urlBuilder.workitemsURL
        XCTAssertEqual(url.absoluteString, "https://pacs.example.com/dicom-web/workitems")
    }
    
    func testWorkitemURL() {
        let url = urlBuilder.workitemURL(workitemUID: "1.2.3.4.5")
        XCTAssertEqual(url.absoluteString, "https://pacs.example.com/dicom-web/workitems/1.2.3.4.5")
    }
    
    func testWorkitemStateURL() {
        let url = urlBuilder.workitemStateURL(workitemUID: "1.2.3.4.5")
        XCTAssertEqual(url.absoluteString, "https://pacs.example.com/dicom-web/workitems/1.2.3.4.5/state")
    }
    
    func testWorkitemCancelRequestURL() {
        let url = urlBuilder.workitemCancelRequestURL(workitemUID: "1.2.3.4.5")
        XCTAssertEqual(url.absoluteString, "https://pacs.example.com/dicom-web/workitems/1.2.3.4.5/cancelrequest")
    }
    
    func testWorkitemSubscriptionURL() {
        let url = urlBuilder.workitemSubscriptionURL(workitemUID: "1.2.3.4.5", aeTitle: "MYAE")
        XCTAssertEqual(url.absoluteString, "https://pacs.example.com/dicom-web/workitems/1.2.3.4.5/subscribers/MYAE")
    }
    
    func testGlobalWorkitemSubscriptionURL() {
        let url = urlBuilder.globalWorkitemSubscriptionURL(aeTitle: "MYAE")
        XCTAssertEqual(url.absoluteString, "https://pacs.example.com/dicom-web/workitems/1.2.840.10008.5.1.4.34.5/subscribers/MYAE")
    }
    
    func testWorkitemSubscriptionSuspendURL() {
        let url = urlBuilder.workitemSubscriptionSuspendURL(workitemUID: "1.2.3.4.5", aeTitle: "MYAE")
        XCTAssertEqual(url.absoluteString, "https://pacs.example.com/dicom-web/workitems/1.2.3.4.5/subscribers/MYAE/suspend")
    }
    
    func testSearchWorkitemsURL() {
        let url = urlBuilder.searchWorkitemsURL(parameters: [
            "00741000": "SCHEDULED",
            "limit": "10"
        ])
        let urlString = url.absoluteString
        XCTAssertTrue(urlString.hasPrefix("https://pacs.example.com/dicom-web/workitems?"))
        XCTAssertTrue(urlString.contains("00741000=SCHEDULED"))
        XCTAssertTrue(urlString.contains("limit=10"))
    }
}

// MARK: - UPS Response Types Tests

final class UPSResponseTypesTests: XCTestCase {
    
    func testUPSCreateResponse() {
        let response = UPSCreateResponse(
            workitemUID: "1.2.3.4.5",
            retrieveURL: "https://pacs.example.com/workitems/1.2.3.4.5",
            warnings: ["Warning 1"]
        )
        
        XCTAssertEqual(response.workitemUID, "1.2.3.4.5")
        XCTAssertEqual(response.retrieveURL, "https://pacs.example.com/workitems/1.2.3.4.5")
        XCTAssertEqual(response.warnings.count, 1)
    }
    
    func testUPSStateChangeResponse() {
        let response = UPSStateChangeResponse(
            workitemUID: "1.2.3.4.5",
            newState: .inProgress,
            transactionUID: "2.25.12345",
            warnings: []
        )
        
        XCTAssertEqual(response.workitemUID, "1.2.3.4.5")
        XCTAssertEqual(response.newState, .inProgress)
        XCTAssertEqual(response.transactionUID, "2.25.12345")
        XCTAssertTrue(response.warnings.isEmpty)
    }
    
    func testUPSCancellationResponseAccepted() {
        let response = UPSCancellationResponse(
            workitemUID: "1.2.3.4.5",
            accepted: true,
            rejectionReason: nil,
            warnings: []
        )
        
        XCTAssertTrue(response.accepted)
        XCTAssertNil(response.rejectionReason)
    }
    
    func testUPSCancellationResponseRejected() {
        let response = UPSCancellationResponse(
            workitemUID: "1.2.3.4.5",
            accepted: false,
            rejectionReason: "Workitem is already in progress",
            warnings: []
        )
        
        XCTAssertFalse(response.accepted)
        XCTAssertEqual(response.rejectionReason, "Workitem is already in progress")
    }
}

// MARK: - UPS Client Initialization Tests

#if canImport(FoundationNetworking) || os(macOS) || os(iOS) || os(visionOS)
final class UPSClientTests: XCTestCase {
    
    func testClientInitializationWithConfiguration() throws {
        let config = try DICOMwebConfiguration(baseURLString: "https://pacs.example.com/dicom-web")
        let client = UPSClient(configuration: config)
        
        XCTAssertEqual(client.configuration.baseURL.absoluteString, "https://pacs.example.com/dicom-web")
    }
    
    func testClientInitializationWithHTTPClient() throws {
        let config = try DICOMwebConfiguration(baseURLString: "https://pacs.example.com/dicom-web")
        let httpClient = HTTPClient(configuration: config)
        let client = UPSClient(httpClient: httpClient)
        
        XCTAssertEqual(client.configuration.baseURL.absoluteString, "https://pacs.example.com/dicom-web")
    }
    
    func testURLBuilderAccess() throws {
        let config = try DICOMwebConfiguration(baseURLString: "https://pacs.example.com/dicom-web")
        let client = UPSClient(configuration: config)
        
        let workitemsURL = client.urlBuilder.workitemsURL
        XCTAssertEqual(workitemsURL.absoluteString, "https://pacs.example.com/dicom-web/workitems")
    }
}
#endif
