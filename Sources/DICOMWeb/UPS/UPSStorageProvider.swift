import Foundation
import DICOMCore

// NEMA-verified: 2026a, checked 2026-09-28 — state changes per PS3.4 2026a Table CC.1.1-2 and CC.2.1.3; Request Cancel of a SCHEDULED UPS per CC.2.2.3; Transaction UIDs per PS3.5 9.1 / B.2
// MARK: - UPSStorageProvider Protocol

/// Protocol for UPS workitem storage backend
///
/// This protocol defines the interface for storage providers that manage
/// UPS workitems. Implementations can use databases, files, or in-memory storage.
///
/// Reference: PS3.18 Section 11 - UPS-RS
public protocol UPSStorageProvider: Sendable {
    
    // MARK: - Workitem Operations
    
    /// Retrieves a workitem by its UID
    /// - Parameter workitemUID: The workitem's SOP Instance UID
    /// - Returns: The workitem, or nil if not found
    func getWorkitem(workitemUID: String) async throws -> Workitem?
    
    /// Creates a new workitem
    /// - Parameter workitem: The workitem to create
    /// - Throws: UPSError.workitemAlreadyExists if a workitem with the same UID exists
    func createWorkitem(_ workitem: Workitem) async throws
    
    /// Updates an existing workitem
    /// - Parameter workitem: The workitem with updated values
    /// - Throws: UPSError.workitemNotFound if the workitem doesn't exist
    func updateWorkitem(_ workitem: Workitem) async throws
    
    /// Deletes a workitem
    /// - Parameter workitemUID: The workitem's SOP Instance UID
    /// - Returns: True if deleted, false if not found
    func deleteWorkitem(workitemUID: String) async throws -> Bool
    
    // MARK: - Query Operations
    
    /// Searches for workitems matching the query
    /// - Parameter query: The query parameters
    /// - Returns: Array of matching workitems
    func searchWorkitems(query: UPSStorageQuery) async throws -> [Workitem]
    
    /// Gets the total count of workitems matching the query
    /// - Parameter query: The query parameters
    /// - Returns: Total count of matching workitems
    func countWorkitems(query: UPSStorageQuery) async throws -> Int
    
    // MARK: - State Operations
    
    /// Changes the state of a workitem
    /// - Parameters:
    ///   - workitemUID: The workitem's UID
    ///   - newState: The target state
    ///   - transactionUID: Transaction UID (required for certain transitions)
    /// - Throws: UPSError for invalid state transitions or missing transaction UID
    func changeWorkitemState(
        workitemUID: String,
        newState: UPSState,
        transactionUID: String?
    ) async throws
    
    /// Updates progress information for a workitem
    /// - Parameters:
    ///   - workitemUID: The workitem's UID
    ///   - progress: The progress information
    func updateProgress(
        workitemUID: String,
        progress: ProgressInformation
    ) async throws
}

// MARK: - UPSStorageQuery

/// Query parameters for workitem searches
public struct UPSStorageQuery: Sendable {
    
    /// Filter by state
    public var state: UPSState?
    
    /// Filter by multiple states
    public var states: [UPSState]?
    
    /// Filter by priority
    public var priority: UPSPriority?
    
    /// Filter by multiple priorities
    public var priorities: [UPSPriority]?
    
    /// Filter by workitem UID
    public var workitemUID: String?
    
    /// Filter by patient ID
    public var patientID: String?
    
    /// Filter by patient name (supports wildcards)
    public var patientName: String?
    
    /// Filter by study instance UID
    public var studyInstanceUID: String?
    
    /// Filter by accession number
    public var accessionNumber: String?
    
    /// Filter by procedure step label (supports wildcards)
    public var procedureStepLabel: String?
    
    /// Filter by worklist label (supports wildcards)
    public var worklistLabel: String?
    
    /// Filter by scheduled start datetime range
    public var scheduledStartDateTimeRange: DateTimeRange?
    
    /// Filter by expected completion datetime range
    public var expectedCompletionDateTimeRange: DateTimeRange?
    
    /// Filter by scheduled station name
    public var scheduledStationName: String?
    
    /// Filter by scheduled performer name
    public var scheduledPerformerName: String?
    
    /// Pagination: offset
    public var offset: Int
    
    /// Pagination: limit
    public var limit: Int
    
    /// Whether to use fuzzy matching
    public var fuzzyMatching: Bool
    
    /// Additional custom query parameters (DICOM tags)
    public var customParameters: [String: String]
    
    /// Creates a storage query with default values
    public init(
        state: UPSState? = nil,
        states: [UPSState]? = nil,
        priority: UPSPriority? = nil,
        priorities: [UPSPriority]? = nil,
        workitemUID: String? = nil,
        patientID: String? = nil,
        patientName: String? = nil,
        studyInstanceUID: String? = nil,
        accessionNumber: String? = nil,
        procedureStepLabel: String? = nil,
        worklistLabel: String? = nil,
        scheduledStartDateTimeRange: DateTimeRange? = nil,
        expectedCompletionDateTimeRange: DateTimeRange? = nil,
        scheduledStationName: String? = nil,
        scheduledPerformerName: String? = nil,
        offset: Int = 0,
        limit: Int = 100,
        fuzzyMatching: Bool = false,
        customParameters: [String: String] = [:]
    ) {
        self.state = state
        self.states = states
        self.priority = priority
        self.priorities = priorities
        self.workitemUID = workitemUID
        self.patientID = patientID
        self.patientName = patientName
        self.studyInstanceUID = studyInstanceUID
        self.accessionNumber = accessionNumber
        self.procedureStepLabel = procedureStepLabel
        self.worklistLabel = worklistLabel
        self.scheduledStartDateTimeRange = scheduledStartDateTimeRange
        self.expectedCompletionDateTimeRange = expectedCompletionDateTimeRange
        self.scheduledStationName = scheduledStationName
        self.scheduledPerformerName = scheduledPerformerName
        self.offset = offset
        self.limit = limit
        self.fuzzyMatching = fuzzyMatching
        self.customParameters = customParameters
    }
    
    /// Date/time range for queries
    public struct DateTimeRange: Sendable {
        public let start: Date?
        public let end: Date?
        
        /// Creates a datetime range
        public init(start: Date?, end: Date?) {
            self.start = start
            self.end = end
        }
        
        /// Creates a datetime range for a single day
        public init(date: Date) {
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: date)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)
            self.start = startOfDay
            self.end = endOfDay
        }
    }
}

// MARK: - In-Memory UPS Storage Provider

/// In-memory implementation of UPSStorageProvider for testing
public actor InMemoryUPSStorageProvider: UPSStorageProvider {
    
    /// Stored workitems keyed by UID
    private var workitems: [String: Workitem] = [:]
    
    /// Optional event dispatcher for event generation
    /// Strong reference is safe here as the dispatcher doesn't hold a reference back to the storage
    private var eventDispatcher: EventDispatcher?
    
    /// Creates an empty in-memory storage provider
    public init() {}
    
    /// Creates an in-memory storage provider with initial workitems
    public init(workitems: [Workitem]) {
        for workitem in workitems {
            self.workitems[workitem.workitemUID] = workitem
        }
    }
    
    /// Sets the event dispatcher for event generation
    /// - Parameter dispatcher: The event dispatcher to use
    public func setEventDispatcher(_ dispatcher: EventDispatcher?) {
        self.eventDispatcher = dispatcher
    }
    
    // MARK: - UPSStorageProvider Implementation
    
    public func getWorkitem(workitemUID: String) async throws -> Workitem? {
        return workitems[workitemUID]
    }
    
    public func createWorkitem(_ workitem: Workitem) async throws {
        if workitems[workitem.workitemUID] != nil {
            throw UPSError.workitemAlreadyExists(uid: workitem.workitemUID)
        }
        workitems[workitem.workitemUID] = workitem
    }
    
    public func updateWorkitem(_ workitem: Workitem) async throws {
        guard workitems[workitem.workitemUID] != nil else {
            throw UPSError.workitemNotFound(uid: workitem.workitemUID)
        }
        workitems[workitem.workitemUID] = workitem
    }
    
    public func deleteWorkitem(workitemUID: String) async throws -> Bool {
        return workitems.removeValue(forKey: workitemUID) != nil
    }
    
    public func searchWorkitems(query: UPSStorageQuery) async throws -> [Workitem] {
        var results = Array(workitems.values)
        
        // Apply filters
        if let state = query.state {
            results = results.filter { $0.state == state }
        }
        
        if let states = query.states, !states.isEmpty {
            results = results.filter { states.contains($0.state) }
        }
        
        if let priority = query.priority {
            results = results.filter { $0.priority == priority }
        }
        
        if let priorities = query.priorities, !priorities.isEmpty {
            results = results.filter { priorities.contains($0.priority) }
        }
        
        if let workitemUID = query.workitemUID {
            results = results.filter { $0.workitemUID == workitemUID }
        }
        
        if let patientID = query.patientID {
            results = results.filter { matchWildcard(value: $0.patientID, pattern: patientID) }
        }
        
        if let patientName = query.patientName {
            results = results.filter { matchWildcard(value: $0.patientName, pattern: patientName) }
        }
        
        if let studyUID = query.studyInstanceUID {
            results = results.filter { $0.studyInstanceUID == studyUID }
        }
        
        if let accession = query.accessionNumber {
            results = results.filter { $0.accessionNumber == accession }
        }
        
        if let label = query.procedureStepLabel {
            results = results.filter { matchWildcard(value: $0.procedureStepLabel, pattern: label) }
        }
        
        if let worklistLabel = query.worklistLabel {
            results = results.filter { matchWildcard(value: $0.worklistLabel, pattern: worklistLabel) }
        }
        
        if let range = query.scheduledStartDateTimeRange {
            results = results.filter { workitem in
                guard let startDateTime = workitem.scheduledStartDateTime else { return false }
                if let start = range.start, startDateTime < start { return false }
                if let end = range.end, startDateTime >= end { return false }
                return true
            }
        }
        
        // Sort by scheduled start datetime (earliest first), then by priority
        results.sort { a, b in
            // First by priority (lower numericValue = higher priority)
            if a.priority.numericValue != b.priority.numericValue {
                return a.priority.numericValue < b.priority.numericValue
            }
            // Then by scheduled start time (earlier first)
            if let aTime = a.scheduledStartDateTime, let bTime = b.scheduledStartDateTime {
                return aTime < bTime
            }
            return a.scheduledStartDateTime != nil
        }
        
        // Apply pagination
        let startIndex = min(query.offset, results.count)
        let endIndex = min(startIndex + query.limit, results.count)
        
        return Array(results[startIndex..<endIndex])
    }
    
    public func countWorkitems(query: UPSStorageQuery) async throws -> Int {
        // Create a query without pagination to count all
        var countQuery = query
        countQuery.offset = 0
        countQuery.limit = Int.max
        let results = try await searchWorkitems(query: countQuery)
        return results.count
    }
    
    public func changeWorkitemState(
        workitemUID: String,
        newState: UPSState,
        transactionUID: String?
    ) async throws {
        guard var workitem = workitems[workitemUID] else {
            throw UPSError.workitemNotFound(uid: workitemUID)
        }
        
        let currentState = workitem.state
        
        // Validate state transition (PS3.4 Table CC.1.1-2). A SCHEDULED UPS is cancelled by
        // this provider itself on a cancellation request: through IN PROGRESS (CC.2.2.3).
        if currentState == .scheduled && newState == .canceled {
            try await changeWorkitemState(workitemUID: workitemUID, newState: .inProgress,
                                          transactionUID: transactionUID ?? generateTransactionUID())
            let lock = workitems[workitemUID]?.transactionUID
            try await changeWorkitemState(workitemUID: workitemUID, newState: .canceled, transactionUID: lock)
            return
        }
        guard currentState.canTransition(to: newState) else {
            throw UPSError.invalidStateTransition(from: currentState, to: newState)
        }
        
        // Validate transaction UID requirements
        if currentState == .inProgress && (newState == .completed || newState == .canceled) {
            guard let txUID = transactionUID else {
                throw UPSError.transactionUIDRequired
            }
            guard workitem.transactionUID == txUID else {
                throw UPSError.transactionUIDMismatch
            }
        }
        
        // PS3.4 CC.2.1.3: on the change to IN PROGRESS the SCP records the Transaction UID the
        // SCU provided (one is generated for callers that supplied none)
        if newState == .inProgress {
            workitem.transactionUID = transactionUID ?? generateTransactionUID()
        }
        
        workitem.state = newState
        workitem.modificationDateTime = Date()
        
        if newState == .canceled {
            workitem.cancellationDateTime = Date()
        }
        
        workitems[workitemUID] = workitem
        
        // Generate state change event
        if let dispatcher = eventDispatcher {
            // PS3.4 CC.2.4.3: one UPS State Report per state change, with the current
            // Procedure Step State and Input Readiness State
            let event = UPSStateReportEvent(
                workitemUID: workitemUID,
                transactionUID: workitem.transactionUID,
                previousState: currentState,
                newState: newState,
                reason: newState == .canceled ? workitem.cancellationReason : nil,
                inputReadinessState: workitem.inputReadinessState ?? .ready
            )
            await dispatcher.dispatch(event)
            
        }
    }
    
    public func updateProgress(
        workitemUID: String,
        progress: ProgressInformation
    ) async throws {
        guard var workitem = workitems[workitemUID] else {
            throw UPSError.workitemNotFound(uid: workitemUID)
        }
        
        workitem.progressInformation = progress
        workitem.modificationDateTime = Date()
        workitems[workitemUID] = workitem
        
        // Generate progress event
        if let dispatcher = eventDispatcher {
            let event = UPSProgressReportEvent(
                workitemUID: workitemUID,
                transactionUID: workitem.transactionUID,
                progressInformation: progress
            )
            await dispatcher.dispatch(event)
        }
    }
    
    // MARK: - Helper Methods
    
    /// Gets the current transaction UID for a workitem
    public func getTransactionUID(workitemUID: String) async throws -> String? {
        return workitems[workitemUID]?.transactionUID
    }
    
    /// Gets all workitems (for testing)
    public func getAllWorkitems() async -> [Workitem] {
        return Array(workitems.values)
    }
    
    /// Clears all workitems (for testing)
    public func clear() async {
        workitems.removeAll()
    }
    
    // MARK: - Private Helpers
    
    /// Simple wildcard matching (* and ?)
    private func matchWildcard(value: String?, pattern: String) -> Bool {
        guard let value = value else { return false }
        
        if !pattern.contains("*") && !pattern.contains("?") {
            return value == pattern
        }
        
        // Convert DICOM wildcard pattern to regex
        var regex = "^"
        for char in pattern {
            switch char {
            case "*":
                regex += ".*"
            case "?":
                regex += "."
            case ".":
                regex += "\\."
            default:
                regex += String(char)
            }
        }
        regex += "$"
        
        do {
            let re = try NSRegularExpression(pattern: regex, options: [.caseInsensitive])
            let range = NSRange(value.startIndex..., in: value)
            return re.firstMatch(in: value, options: [], range: range) != nil
        } catch {
            return value == pattern
        }
    }
    
    /// Generates a unique transaction UID (PS3.5 9.1: digits and dots only, so the UUID is
    /// carried as its decimal value under the 2.25 root, PS3.5 B.2)
    private func generateTransactionUID() -> String {
        return UIDGenerator.generateUID().value
    }
}
