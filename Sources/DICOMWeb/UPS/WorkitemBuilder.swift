import Foundation

// NEMA-verified: 2026a, checked 2026-09-28 — defaults read against PS3.3 2026a C.30.2 (MEDIUM priority, READY readiness are defined terms); builds through Workitem, whose tags are verified there
/// Fluent builder for constructing UPS Workitem instances
///
/// WorkitemBuilder provides a chainable API for creating fully populated Workitem objects.
/// Required fields are validated before building; optional fields can be set via fluent setters.
///
/// ## Example Usage
///
/// ```swift
/// let workitem = try WorkitemBuilder(workitemUID: "1.2.3.4.5")
///     .setPatientName("Smith^John")
///     .setPatientID("PAT001")
///     .setPriority(.high)
///     .setProcedureStepLabel("CT Scan")
///     .setScheduledStartDateTime(Date())
///     .build()
/// ```
///
/// ## Factory Methods
///
/// ```swift
/// let scheduled = try WorkitemBuilder.scheduledProcedure(
///     workitemUID: "1.2.3",
///     patientName: "Doe^Jane",
///     patientID: "PAT002",
///     procedureStepLabel: "MRI Brain"
/// ).build()
///
/// let simple = try WorkitemBuilder.simpleTask(
///     workitemUID: "1.2.4",
///     label: "Process Report"
/// ).build()
/// ```
///
/// Reference: PS3.4 Annex CC - Unified Procedure Step Service
/// Reference: PS3.18 Section 11 - UPS-RS
public final class WorkitemBuilder {
    
    // MARK: - Properties
    
    private var workitemUID: String
    private var state: UPSState = .scheduled
    private var priority: UPSPriority = .medium
    private var inputReadinessState: InputReadinessState = .ready
    
    // Patient
    private var patientName: String?
    private var patientID: String?
    private var patientBirthDate: String?
    private var patientSex: String?
    
    // Scheduling
    private var scheduledStartDateTime: Date?
    private var expectedCompletionDateTime: Date?
    private var modificationDateTime: Date?
    
    // Study Reference
    private var studyInstanceUID: String?
    private var accessionNumber: String?
    private var referringPhysicianName: String?
    private var requestedProcedureID: String?
    
    // Identification
    private var scheduledProcedureStepID: String?
    private var procedureStepLabel: String?
    private var worklistLabel: String?
    private var comments: String?
    
    // Transaction
    private var transactionUID: String?
    
    // Cancellation
    private var cancellationDateTime: Date?
    private var cancellationReason: String?
    private var discontinuationReasonCodes: [CodedEntry]?
    
    // Performers
    private var scheduledHumanPerformers: [HumanPerformer]?
    private var actualHumanPerformers: [HumanPerformer]?
    
    // Code
    private var scheduledWorkitemCode: CodedEntry?
    
    // Station
    private var scheduledStationNameCodes: [CodedEntry]?
    private var scheduledStationClassCodes: [CodedEntry]?
    private var scheduledStationGeographicLocationCodes: [CodedEntry]?
    
    // I/O
    private var inputInformation: [ReferencedInstance]?
    private var outputInformation: [ReferencedInstance]?
    
    // Progress
    private var progressInformation: ProgressInformation?
    
    // Admission
    private var admissionID: String?
    private var issuerOfAdmissionID: String?
    
    // Other patient IDs
    private var otherPatientIDs: [String]?
    
    // Performed station
    private var performedStationNameCodes: [CodedEntry]?
    
    // MARK: - Initialization
    
    /// Creates a new WorkitemBuilder with the specified workitem UID
    ///
    /// - Parameter workitemUID: The SOP Instance UID for the workitem
    public init(workitemUID: String) {
        self.workitemUID = workitemUID
    }
    
    // MARK: - Fluent Setters
    
    /// Sets the procedure step state
    @discardableResult
    public func setState(_ state: UPSState) -> Self {
        self.state = state
        return self
    }
    
    /// Sets the priority
    @discardableResult
    public func setPriority(_ priority: UPSPriority) -> Self {
        self.priority = priority
        return self
    }
    
    /// Sets the input readiness state
    @discardableResult
    public func setInputReadinessState(_ state: InputReadinessState) -> Self {
        self.inputReadinessState = state
        return self
    }
    
    /// Sets the patient name
    @discardableResult
    public func setPatientName(_ name: String) -> Self {
        self.patientName = name
        return self
    }
    
    /// Sets the patient ID
    @discardableResult
    public func setPatientID(_ id: String) -> Self {
        self.patientID = id
        return self
    }
    
    /// Sets the patient birth date
    @discardableResult
    public func setPatientBirthDate(_ date: String) -> Self {
        self.patientBirthDate = date
        return self
    }
    
    /// Sets the patient sex
    @discardableResult
    public func setPatientSex(_ sex: String) -> Self {
        self.patientSex = sex
        return self
    }
    
    /// Sets the scheduled start date/time
    @discardableResult
    public func setScheduledStartDateTime(_ date: Date) -> Self {
        self.scheduledStartDateTime = date
        return self
    }
    
    /// Sets the expected completion date/time
    @discardableResult
    public func setExpectedCompletionDateTime(_ date: Date) -> Self {
        self.expectedCompletionDateTime = date
        return self
    }
    
    /// Sets the modification date/time
    @discardableResult
    public func setModificationDateTime(_ date: Date) -> Self {
        self.modificationDateTime = date
        return self
    }
    
    /// Sets the study instance UID
    @discardableResult
    public func setStudyInstanceUID(_ uid: String) -> Self {
        self.studyInstanceUID = uid
        return self
    }
    
    /// Sets the accession number
    @discardableResult
    public func setAccessionNumber(_ accession: String) -> Self {
        self.accessionNumber = accession
        return self
    }
    
    /// Sets the referring physician's name
    @discardableResult
    public func setReferringPhysicianName(_ name: String) -> Self {
        self.referringPhysicianName = name
        return self
    }
    
    /// Sets the requested procedure ID
    @discardableResult
    public func setRequestedProcedureID(_ id: String) -> Self {
        self.requestedProcedureID = id
        return self
    }
    
    /// Sets the scheduled procedure step ID
    @discardableResult
    public func setScheduledProcedureStepID(_ id: String) -> Self {
        self.scheduledProcedureStepID = id
        return self
    }
    
    /// Sets the procedure step label
    @discardableResult
    public func setProcedureStepLabel(_ label: String) -> Self {
        self.procedureStepLabel = label
        return self
    }
    
    /// Sets the worklist label
    @discardableResult
    public func setWorklistLabel(_ label: String) -> Self {
        self.worklistLabel = label
        return self
    }
    
    /// Sets the comments
    @discardableResult
    public func setComments(_ comments: String) -> Self {
        self.comments = comments
        return self
    }
    
    /// Sets the transaction UID
    @discardableResult
    public func setTransactionUID(_ uid: String) -> Self {
        self.transactionUID = uid
        return self
    }
    
    /// Sets the cancellation date/time
    @discardableResult
    public func setCancellationDateTime(_ date: Date) -> Self {
        self.cancellationDateTime = date
        return self
    }
    
    /// Sets the cancellation reason
    @discardableResult
    public func setCancellationReason(_ reason: String) -> Self {
        self.cancellationReason = reason
        return self
    }
    
    /// Sets the discontinuation reason codes
    @discardableResult
    public func setDiscontinuationReasonCodes(_ codes: [CodedEntry]) -> Self {
        self.discontinuationReasonCodes = codes
        return self
    }
    
    /// Sets the scheduled human performers
    @discardableResult
    public func setScheduledHumanPerformers(_ performers: [HumanPerformer]) -> Self {
        self.scheduledHumanPerformers = performers
        return self
    }
    
    /// Adds a scheduled human performer
    @discardableResult
    public func addScheduledHumanPerformer(_ performer: HumanPerformer) -> Self {
        if scheduledHumanPerformers == nil {
            scheduledHumanPerformers = []
        }
        scheduledHumanPerformers?.append(performer)
        return self
    }
    
    /// Sets the actual human performers
    @discardableResult
    public func setActualHumanPerformers(_ performers: [HumanPerformer]) -> Self {
        self.actualHumanPerformers = performers
        return self
    }
    
    /// Sets the scheduled workitem code
    @discardableResult
    public func setScheduledWorkitemCode(_ code: CodedEntry) -> Self {
        self.scheduledWorkitemCode = code
        return self
    }
    
    /// Sets the scheduled station name codes
    @discardableResult
    public func setScheduledStationNameCodes(_ codes: [CodedEntry]) -> Self {
        self.scheduledStationNameCodes = codes
        return self
    }
    
    /// Sets the scheduled station class codes
    @discardableResult
    public func setScheduledStationClassCodes(_ codes: [CodedEntry]) -> Self {
        self.scheduledStationClassCodes = codes
        return self
    }
    
    /// Sets the scheduled station geographic location codes
    @discardableResult
    public func setScheduledStationGeographicLocationCodes(_ codes: [CodedEntry]) -> Self {
        self.scheduledStationGeographicLocationCodes = codes
        return self
    }
    
    /// Sets the input information (referenced instances)
    @discardableResult
    public func setInputInformation(_ refs: [ReferencedInstance]) -> Self {
        self.inputInformation = refs
        return self
    }
    
    /// Adds an input referenced instance
    @discardableResult
    public func addInputInformation(_ ref: ReferencedInstance) -> Self {
        if inputInformation == nil {
            inputInformation = []
        }
        inputInformation?.append(ref)
        return self
    }
    
    /// Sets the output information (referenced instances)
    @discardableResult
    public func setOutputInformation(_ refs: [ReferencedInstance]) -> Self {
        self.outputInformation = refs
        return self
    }
    
    /// Sets the progress information
    @discardableResult
    public func setProgressInformation(_ progress: ProgressInformation) -> Self {
        self.progressInformation = progress
        return self
    }
    
    /// Sets the admission ID
    @discardableResult
    public func setAdmissionID(_ id: String) -> Self {
        self.admissionID = id
        return self
    }
    
    /// Sets the issuer of admission ID
    @discardableResult
    public func setIssuerOfAdmissionID(_ issuer: String) -> Self {
        self.issuerOfAdmissionID = issuer
        return self
    }
    
    /// Sets other patient IDs
    @discardableResult
    public func setOtherPatientIDs(_ ids: [String]) -> Self {
        self.otherPatientIDs = ids
        return self
    }
    
    /// Sets the performed station name codes
    @discardableResult
    public func setPerformedStationNameCodes(_ codes: [CodedEntry]) -> Self {
        self.performedStationNameCodes = codes
        return self
    }
    
    // MARK: - Validation
    
    /// Validates the builder configuration
    ///
    /// Checks that all required fields are present and valid.
    ///
    /// - Throws: `UPSError.missingRequiredAttribute` if required fields are missing
    ///           `UPSError.invalidWorkitemData` if data is invalid
    public func validate() throws {
        if workitemUID.isEmpty {
            throw UPSError.missingRequiredAttribute(name: "workitemUID")
        }
        
        if state == .inProgress && transactionUID == nil {
            throw UPSError.invalidWorkitemData(reason: "Transaction UID is required for IN PROGRESS state")
        }
    }
    
    // MARK: - Build
    
    /// Builds the Workitem from the configured properties
    ///
    /// - Returns: A fully configured Workitem
    /// - Throws: `UPSError` if validation fails
    public func build() throws -> Workitem {
        try validate()
        
        var workitem = Workitem(workitemUID: workitemUID, state: state, priority: priority)
        workitem.inputReadinessState = inputReadinessState
        
        // Patient
        workitem.patientName = patientName
        workitem.patientID = patientID
        workitem.patientBirthDate = patientBirthDate
        workitem.patientSex = patientSex
        workitem.otherPatientIDs = otherPatientIDs
        
        // Scheduling
        workitem.scheduledStartDateTime = scheduledStartDateTime
        workitem.expectedCompletionDateTime = expectedCompletionDateTime
        workitem.modificationDateTime = modificationDateTime
        
        // Study Reference
        workitem.studyInstanceUID = studyInstanceUID
        workitem.accessionNumber = accessionNumber
        workitem.referringPhysicianName = referringPhysicianName
        workitem.requestedProcedureID = requestedProcedureID
        
        // Identification
        workitem.scheduledProcedureStepID = scheduledProcedureStepID
        workitem.procedureStepLabel = procedureStepLabel
        workitem.worklistLabel = worklistLabel
        workitem.comments = comments
        
        // Transaction
        workitem.transactionUID = transactionUID
        
        // Cancellation
        workitem.cancellationDateTime = cancellationDateTime
        workitem.cancellationReason = cancellationReason
        workitem.discontinuationReasonCodes = discontinuationReasonCodes
        
        // Performers
        workitem.scheduledHumanPerformers = scheduledHumanPerformers
        workitem.actualHumanPerformers = actualHumanPerformers
        workitem.performedStationNameCodes = performedStationNameCodes
        
        // Code
        workitem.scheduledWorkitemCode = scheduledWorkitemCode
        
        // Station
        workitem.scheduledStationNameCodes = scheduledStationNameCodes
        workitem.scheduledStationClassCodes = scheduledStationClassCodes
        workitem.scheduledStationGeographicLocationCodes = scheduledStationGeographicLocationCodes
        
        // I/O
        workitem.inputInformation = inputInformation
        workitem.outputInformation = outputInformation
        
        // Progress
        workitem.progressInformation = progressInformation
        
        // Admission
        workitem.admissionID = admissionID
        workitem.issuerOfAdmissionID = issuerOfAdmissionID
        
        return workitem
    }
    
    // MARK: - Factory Methods
    
    /// Creates a builder pre-configured for a scheduled procedure
    ///
    /// - Parameters:
    ///   - workitemUID: The SOP Instance UID
    ///   - patientName: Patient's name
    ///   - patientID: Patient's identifier
    ///   - procedureStepLabel: Human-readable label for the procedure
    ///   - priority: Priority level (default: MEDIUM)
    ///   - scheduledStartDateTime: When the procedure is scheduled (default: now)
    /// - Returns: A pre-configured WorkitemBuilder
    public static func scheduledProcedure(
        workitemUID: String,
        patientName: String,
        patientID: String,
        procedureStepLabel: String,
        priority: UPSPriority = .medium,
        scheduledStartDateTime: Date = Date()
    ) -> WorkitemBuilder {
        return WorkitemBuilder(workitemUID: workitemUID)
            .setState(.scheduled)
            .setPriority(priority)
            .setPatientName(patientName)
            .setPatientID(patientID)
            .setProcedureStepLabel(procedureStepLabel)
            .setScheduledStartDateTime(scheduledStartDateTime)
    }
    
    /// Creates a builder pre-configured for a simple task workitem
    ///
    /// - Parameters:
    ///   - workitemUID: The SOP Instance UID
    ///   - label: Human-readable label for the task
    ///   - priority: Priority level (default: MEDIUM)
    /// - Returns: A pre-configured WorkitemBuilder
    public static func simpleTask(
        workitemUID: String,
        label: String,
        priority: UPSPriority = .medium
    ) -> WorkitemBuilder {
        return WorkitemBuilder(workitemUID: workitemUID)
            .setState(.scheduled)
            .setPriority(priority)
            .setProcedureStepLabel(label)
    }
}
