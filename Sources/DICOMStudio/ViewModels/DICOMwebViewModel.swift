// DICOMwebViewModel.swift
// DICOMStudio
// NEMA-verified: 2026a, checked 2026-10-05 — transitionUPSState refuses per PS3.4 2026a Table CC.1.1-2 and refuses a SCHEDULED target with dicom-wado's PS3.18 2026a 11.7.1.4 message; UPS state and priority strings mapped from DICOMWeb diffed against PS3.3 2026a C.30.1 (4/4) and C.30.2 (3/3; STAT folded into HIGH as DICOMWeb does); the QIDO level is passed to the query so the Table 10.6.1-5 key is chosen; frames jobs with a frame list use the Frame Pixel Data resource of Table 10.4.1.6-1; the remaining code is request plumbing over DICOMWeb (verified 2026-09-28)
//
// DICOM Studio — ViewModel for the DICOMweb Integration Hub (Milestone 10)
// Reference: DICOM PS3.18 (Web Services), PS3.19 (Application Hosting)

import Foundation
import Observation
import DICOMWeb

/// Injectable connectivity boundary for the server-profile probe. Production
/// performs a minimal QIDO-RS request; tests can return a deterministic result
/// without opening a network connection.
public typealias DICOMwebConnectionProbe = @Sendable (
    _ profile: DICOMwebServerProfile
) async throws -> Void

/// ViewModel for the DICOMweb Integration Hub, managing state for all six sections:
/// server configuration, QIDO-RS queries, WADO-RS retrieval, STOW-RS uploads,
/// UPS-RS workitem management, and performance monitoring.
///
/// Requires macOS 14+ / iOS 17+ for the `@Observable` macro.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
@MainActor
@Observable
public final class DICOMwebViewModel {

    // MARK: - Dependencies

    private let service: DICOMwebService
    private let profileStorage: DICOMwebServerProfileStorageService
    private let connectionProbe: DICOMwebConnectionProbe

    // MARK: - Navigation

    /// Currently active DICOMweb tab.
    public var activeTab: DICOMwebTab = .serverConfig
    /// Whether an operation is in progress.
    public var isLoading: Bool = false
    /// Error message to display, if any.
    public var errorMessage: String? = nil

    // MARK: - 10.1 Server Configuration

    /// All configured DICOMweb server profiles.
    public var serverProfiles: [DICOMwebServerProfile] = []
    /// Currently selected server profile ID (for editing/testing).
    public var selectedServerProfileID: UUID? = nil
    /// Whether the add-server sheet is showing.
    public var isAddServerSheetPresented: Bool = false
    /// Whether the edit-server sheet is showing.
    public var isEditServerSheetPresented: Bool = false
    /// Conformance statement text for the currently selected server (fetched on demand).
    public var serverCapabilitiesText: String = ""

    // MARK: - 10.2 QIDO-RS

    /// The query level (study / series / instance).
    public var qidoQueryLevel: QIDOQueryLevel = .study
    /// Current query parameters.
    public var qidoQueryParams: QIDOQueryParams = QIDOQueryParams()
    /// Results from the most recent QIDO-RS query.
    public var qidoResults: [QIDOResultItem] = []
    /// Whether a QIDO query is currently running.
    public var isQIDORunning: Bool = false
    /// Currently selected query result ID for drill-down.
    public var qidoSelectedResultID: UUID? = nil
    /// Named query templates (name → params).
    public var savedQueryTemplates: [String: QIDOQueryParams] = [:]
    /// Total number of results available on the server (for pagination display).
    public var qidoTotalResultCount: Int? = nil

    // MARK: - 10.3 WADO-RS

    /// All WADO-RS retrieve jobs.
    public var wadoJobs: [WADORetrieveJob] = []
    /// Study UID for the next job to enqueue.
    public var wadoNewJobStudyUID: String = ""
    /// Series UID for the next job to enqueue (empty = study-level).
    public var wadoNewJobSeriesUID: String = ""
    /// SOP Instance UID for the next job to enqueue (empty = series/study-level).
    public var wadoNewJobInstanceUID: String = ""
    /// Retrieve mode for the next job.
    public var wadoNewJobMode: WADORetrieveMode = .study
    /// Whether the new-WADO-job sheet is showing.
    public var isWADOJobSheetPresented: Bool = false
    /// Currently selected WADO job ID.
    public var wadoSelectedJobID: UUID? = nil

    // MARK: - 10.4 STOW-RS

    /// All STOW-RS upload jobs.
    public var stowJobs: [STOWUploadJob] = []
    /// File paths staged for the next upload job.
    public var stowNewFilePaths: [String] = []
    /// How to handle duplicate instances.
    public var stowDuplicateHandling: STOWDuplicateHandling = .reject
    /// Whether DICOM validation runs before upload.
    public var stowValidationEnabled: Bool = true
    /// Number of concurrent upload streams for new jobs.
    public var stowPipelineConcurrency: Int = 5
    /// Whether the new-STOW-upload sheet is showing.
    public var isSTOWUploadSheetPresented: Bool = false
    /// Currently selected STOW job ID.
    public var stowSelectedJobID: UUID? = nil

    // MARK: - 10.5 UPS-RS

    /// All UPS-RS workitems.
    public var upsWorkitems: [UPSWorkitem] = []
    /// All active UPS-RS event subscriptions.
    public var upsSubscriptions: [UPSEventSubscription] = []
    /// Whether a UPS workitem query is running.
    public var isUPSQueryRunning: Bool = false
    /// Currently selected UPS workitem ID.
    public var upsSelectedWorkitemID: UUID? = nil
    /// Event types to subscribe to when creating a new subscription.
    public var upsSubscribeEventTypes: Set<UPSEventType> = Set(UPSEventType.allCases)
    /// Workitem UID for the next subscription (empty = global subscription).
    public var upsNewSubscriptionWorkitemUID: String = ""
    /// Whether the new-subscription sheet is showing.
    public var isUPSSubscriptionSheetPresented: Bool = false

    // MARK: - 10.5.1 UPS Event Channel

    /// Current state of the UPS WebSocket event channel.
    public var upsEventChannelState: UPSEventChannelState = .disconnected
    /// Events received via the UPS WebSocket event channel.
    public var upsReceivedEvents: [UPSReceivedEvent] = []
    /// Whether event monitoring is active (listening for events).
    public var isUPSEventMonitoringActive: Bool = false
    /// Maximum number of received events to retain in the UI.
    public var upsMaxEventHistory: Int = 200

    /// The event channel manager handling subscriptions + WebSocket.
    private var eventChannelManager: UPSEventChannelManager?
    /// Task consuming the WebSocket async event stream.
    private var wsEventTask: Task<Void, Never>?

    // MARK: - 10.6 Performance Dashboard

    /// Latest performance statistics snapshot.
    public var performanceStats: DICOMwebPerformanceStats = DICOMwebPerformanceStats()
    /// Historical performance snapshots (up to 100 entries).
    public var performanceHistory: [DICOMwebPerformanceStats] = []

    // MARK: - Init

    public init(
        service: DICOMwebService = DICOMwebService(),
        profileStorage: DICOMwebServerProfileStorageService = DICOMwebServerProfileStorageService(),
        connectionProbe: DICOMwebConnectionProbe? = nil
    ) {
        self.service = service
        self.profileStorage = profileStorage
        self.connectionProbe = connectionProbe ?? Self.performConnectionProbe
        // Load persisted profiles into the service before loading state
        let persisted = profileStorage.load()
        for profile in persisted {
            service.addServerProfile(profile)
        }
        loadFromService()
    }

    private static func performConnectionProbe(
        _ profile: DICOMwebServerProfile
    ) async throws {
        let client = try DICOMwebClientFactory.makeClient(from: profile)
        _ = try await client.searchStudies(query: QIDOQuery().limit(1))
    }

    // MARK: - Load All State

    private func loadFromService() {
        serverProfiles        = service.getServerProfiles()
        qidoQueryParams       = service.getQIDOQueryParams()
        qidoResults           = service.getQIDOResults()
        qidoSelectedResultID  = service.getQIDOSelectedResultID()
        savedQueryTemplates   = service.getSavedQueryTemplates()
        wadoJobs              = service.getWADOJobs()
        stowJobs              = service.getSTOWJobs()
        upsWorkitems          = service.getUPSWorkitems()
        upsSubscriptions      = service.getUPSSubscriptions()
        performanceStats      = service.getPerformanceStats()
        performanceHistory    = service.getPerformanceHistory()
    }

    // MARK: - Persistence

    /// Persists the current server profiles to disk.
    private func persistProfiles() {
        try? profileStorage.save(serverProfiles)
    }

    // MARK: - 10.1 Server Config Operations

    /// Adds a new DICOMweb server profile.
    public func addServerProfile(_ profile: DICOMwebServerProfile) {
        service.addServerProfile(profile)
        serverProfiles = service.getServerProfiles()
        persistProfiles()
    }

    /// Updates an existing DICOMweb server profile.
    public func updateServerProfile(_ profile: DICOMwebServerProfile) {
        service.updateServerProfile(profile)
        serverProfiles = service.getServerProfiles()
        persistProfiles()
    }

    /// Removes a DICOMweb server profile by ID.
    public func removeServerProfile(id: UUID) {
        service.removeServerProfile(id: id)
        if selectedServerProfileID == id { selectedServerProfileID = nil }
        serverProfiles = service.getServerProfiles()
        persistProfiles()
    }

    /// Makes the profile with the given ID the default.
    public func setDefaultProfile(id: UUID) {
        service.setDefaultProfile(id: id)
        serverProfiles = service.getServerProfiles()
        persistProfiles()
    }

    /// Returns the currently selected server profile, if any.
    public var selectedServerProfile: DICOMwebServerProfile? {
        guard let id = selectedServerProfileID else { return nil }
        return serverProfiles.first { $0.id == id }
    }

    /// Returns the default server profile, if any.
    public var defaultServerProfile: DICOMwebServerProfile? {
        service.defaultProfile()
    }

    /// Tests connectivity for the profile with the given ID by issuing a
    /// real QIDO-RS search (limit 1) against the server.
    ///
    /// Sets the status to `.testing` while the request is in-flight, then
    /// updates to `.online` on success or `.error` on failure.
    public func testConnection(profileID: UUID) async {
        service.updateConnectionStatus(.testing, error: nil, for: profileID)
        serverProfiles = service.getServerProfiles()

        guard let profile = service.profile(for: profileID), profile.isConfigured else {
            service.updateConnectionStatus(.offline, error: "No URL configured", for: profileID)
            serverProfiles = service.getServerProfiles()
            return
        }

        do {
            try await connectionProbe(profile)
            service.updateConnectionStatus(.online, error: nil, for: profileID)
        } catch {
            service.updateConnectionStatus(
                .error,
                error: error.localizedDescription,
                for: profileID
            )
        }
        serverProfiles = service.getServerProfiles()
        persistProfiles()
    }

    /// Returns validation errors for a server profile.
    public func validationErrors(for profile: DICOMwebServerProfile) -> [String] {
        var errors: [String] = []
        if profile.name.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Server name must not be empty.")
        }
        if let urlError = DICOMwebURLHelpers.validationError(for: profile.baseURL) {
            errors.append(urlError)
        }
        if let authError = DICOMwebAuthHelpers.validationError(
            for: profile.authMethod,
            token: profile.bearerToken,
            username: profile.username,
            password: profile.password
        ) {
            errors.append(authError)
        }
        return errors
    }

    // MARK: - 10.2 QIDO-RS Operations

    /// Executes a QIDO-RS query using the current parameters against the
    /// default server profile's DICOMweb endpoint.
    ///
    /// Maps the DICOMStudio `QIDOQueryParams` to the DICOMWeb library's
    /// `QIDOQuery`, executes the search, and converts the results back to
    /// `QIDOResultItem` for display.
    public func runQIDOQuery() async {
        isQIDORunning = true
        errorMessage = nil
        // The level picker drives `qidoQueryLevel`; the query parameters carry their own copy,
        // which chooses the matching key (Modalities in Study vs Modality, PS3.18 Table 10.6.1-5).
        qidoQueryParams.queryLevel = qidoQueryLevel
        service.setQIDOQueryParams(qidoQueryParams)
        service.clearQIDOResults()
        qidoResults = []
        qidoTotalResultCount = nil

        defer {
            isQIDORunning = false
        }

        guard let profile = defaultServerProfile ?? serverProfiles.first else {
            errorMessage = "No DICOMweb server configured. Add a server profile first."
            return
        }

        do {
            let client = try DICOMwebClientFactory.makeClient(from: profile)
            let query = DICOMwebClientFactory.buildQIDOQuery(from: qidoQueryParams)
            let items: [QIDOResultItem]
            let totalCount: Int?

            switch qidoQueryLevel {
            case .study:
                let results = try await client.searchStudies(query: query)
                items = DICOMwebClientFactory.mapStudyResults(results)
                totalCount = results.totalCount
            case .series:
                let results = try await client.searchAllSeries(query: query)
                items = DICOMwebClientFactory.mapSeriesResults(results)
                totalCount = results.totalCount
            case .instance:
                let results = try await client.searchAllInstances(query: query)
                items = DICOMwebClientFactory.mapInstanceResults(results)
                totalCount = results.totalCount
            }

            service.setQIDOResults(items)
            qidoResults = items
            qidoTotalResultCount = totalCount ?? items.count
        } catch {
            errorMessage = "QIDO-RS query failed: \(error.localizedDescription)"
        }
    }

    /// Clears all QIDO-RS results and resets selection.
    public func clearQIDOResults() {
        service.clearQIDOResults()
        qidoResults = []
        qidoSelectedResultID = nil
        qidoTotalResultCount = nil
        service.setQIDOSelectedResultID(nil)
    }

    /// Saves the current query parameters under the given template name.
    public func saveQueryTemplate(name: String) {
        guard !name.isEmpty else { return }
        service.saveQueryTemplate(name: name, params: qidoQueryParams)
        savedQueryTemplates = service.getSavedQueryTemplates()
    }

    /// Loads a saved query template by name into the active parameters.
    public func loadQueryTemplate(name: String) {
        guard let params = savedQueryTemplates[name] else { return }
        qidoQueryParams = params
    }

    /// Removes a saved query template by name.
    public func removeQueryTemplate(name: String) {
        service.removeQueryTemplate(name: name)
        savedQueryTemplates = service.getSavedQueryTemplates()
    }

    /// Selects a QIDO result item by ID and persists the selection.
    public func selectQIDOResult(_ id: UUID?) {
        qidoSelectedResultID = id
        service.setQIDOSelectedResultID(id)
    }

    /// Returns the currently selected QIDO result item, if any.
    public var selectedQIDOResult: QIDOResultItem? {
        guard let id = qidoSelectedResultID else { return nil }
        return qidoResults.first { $0.id == id }
    }

    /// Returns a short human-readable summary of the current query parameters.
    public var qidoQuerySummary: String {
        DICOMwebQIDOHelpers.buildQuerySummary(params: qidoQueryParams)
    }

    // MARK: - 10.3 WADO-RS Operations

    /// Adds a WADO-RS retrieve job.
    public func addWADOJob(_ job: WADORetrieveJob) {
        service.addWADOJob(job)
        wadoJobs = service.getWADOJobs()
    }

    /// Removes a WADO-RS retrieve job by ID.
    public func removeWADOJob(id: UUID) {
        service.removeWADOJob(id: id)
        if wadoSelectedJobID == id { wadoSelectedJobID = nil }
        wadoJobs = service.getWADOJobs()
    }

    /// Removes all WADO-RS jobs that have reached a terminal status.
    public func clearCompletedWADOJobs() {
        service.clearCompletedWADOJobs()
        wadoJobs = service.getWADOJobs()
    }

    /// Creates a new WADO-RS job from the current `wadoNewJob*` fields, enqueues it,
    /// and immediately begins the retrieve against the default server.
    public func enqueueWADOJob() async {
        guard !wadoNewJobStudyUID.isEmpty else {
            errorMessage = "Study UID is required."
            return
        }
        var job = WADORetrieveJob(
            studyInstanceUID: wadoNewJobStudyUID,
            seriesInstanceUID: wadoNewJobSeriesUID.isEmpty ? nil : wadoNewJobSeriesUID,
            sopInstanceUID: wadoNewJobInstanceUID.isEmpty ? nil : wadoNewJobInstanceUID,
            retrieveMode: wadoNewJobMode
        )
        addWADOJob(job)
        let jobID = job.id
        wadoNewJobStudyUID = ""
        wadoNewJobSeriesUID = ""
        wadoNewJobInstanceUID = ""
        isWADOJobSheetPresented = false

        // Execute the retrieve
        guard let profile = defaultServerProfile ?? serverProfiles.first else {
            updateWADOJobStatus(id: jobID, status: .failed, error: "No DICOMweb server configured.")
            return
        }

        do {
            let client = try DICOMwebClientFactory.makeClient(from: profile)

            // Mark in progress
            job.status = .inProgress
            job.startTime = Date()
            service.updateWADOJob(job)
            wadoJobs = service.getWADOJobs()

            var receivedInstances = 0
            var receivedBytes: Int64 = 0

            switch job.retrieveMode {
            case .study:
                let result = try await client.retrieveStudy(studyUID: job.studyInstanceUID)
                receivedInstances = result.instances.count
                receivedBytes = Int64(result.instances.reduce(0) { $0 + $1.count })
            case .series:
                guard let seriesUID = job.seriesInstanceUID else {
                    updateWADOJobStatus(id: jobID, status: .failed, error: "Series UID required for series retrieval.")
                    return
                }
                let result = try await client.retrieveSeries(studyUID: job.studyInstanceUID, seriesUID: seriesUID)
                receivedInstances = result.instances.count
                receivedBytes = Int64(result.instances.reduce(0) { $0 + $1.count })
            case .instance:
                guard let seriesUID = job.seriesInstanceUID,
                      let instanceUID = job.sopInstanceUID else {
                    updateWADOJobStatus(id: jobID, status: .failed, error: "Series and Instance UIDs required.")
                    return
                }
                let data = try await client.retrieveInstance(
                    studyUID: job.studyInstanceUID,
                    seriesUID: seriesUID,
                    instanceUID: instanceUID
                )
                receivedInstances = 1
                receivedBytes = Int64(data.count)
            case .rendered:
                guard let seriesUID = job.seriesInstanceUID,
                      let instanceUID = job.sopInstanceUID else {
                    updateWADOJobStatus(id: jobID, status: .failed, error: "Instance UIDs required for rendered mode.")
                    return
                }
                let data = try await client.retrieveRenderedInstance(
                    studyUID: job.studyInstanceUID,
                    seriesUID: seriesUID,
                    instanceUID: instanceUID
                )
                receivedInstances = 1
                receivedBytes = Int64(data.count)
            case .frames where !job.frameNumbers.isEmpty:
                // Frame Pixel Data resource /studies/{study}/series/{series}/instances/{instance}/frames/{frames}
                // (PS3.18 Table 10.4.1.6-1); frame numbers are 1-based (PS3.3 Table 10-3).
                guard let seriesUID = job.seriesInstanceUID,
                      let instanceUID = job.sopInstanceUID else {
                    updateWADOJobStatus(id: jobID, status: .failed, error: "Instance UIDs required for this mode.")
                    return
                }
                let frames = try await client.retrieveFrames(
                    studyUID: job.studyInstanceUID,
                    seriesUID: seriesUID,
                    instanceUID: instanceUID,
                    frames: job.frameNumbers
                )
                receivedInstances = 1
                receivedBytes = Int64(frames.reduce(0) { $0 + $1.data.count })
            case .frames, .bulkData:
                // Without a frame list (or a Bulk Data URI) the whole Instance resource is retrieved.
                guard let seriesUID = job.seriesInstanceUID,
                      let instanceUID = job.sopInstanceUID else {
                    updateWADOJobStatus(id: jobID, status: .failed, error: "Instance UIDs required for this mode.")
                    return
                }
                let data = try await client.retrieveInstance(
                    studyUID: job.studyInstanceUID,
                    seriesUID: seriesUID,
                    instanceUID: instanceUID
                )
                receivedInstances = 1
                receivedBytes = Int64(data.count)
            }

            // Mark completed
            if var updated = service.wadoJob(for: jobID) {
                updated.status = .completed
                updated.instancesReceived = receivedInstances
                updated.totalInstances = receivedInstances
                updated.bytesReceived = receivedBytes
                updated.totalBytes = receivedBytes
                updated.completionTime = Date()
                service.updateWADOJob(updated)
                wadoJobs = service.getWADOJobs()
            }
        } catch {
            updateWADOJobStatus(id: jobID, status: .failed, error: error.localizedDescription)
        }
    }

    /// Helper to update a WADO job's terminal status.
    private func updateWADOJobStatus(id: UUID, status: WADORetrieveStatus, error: String?) {
        if var updated = service.wadoJob(for: id) {
            updated.status = status
            updated.errorMessage = error
            updated.completionTime = Date()
            service.updateWADOJob(updated)
            wadoJobs = service.getWADOJobs()
        }
    }

    /// Returns the currently selected WADO-RS job, if any.
    public var selectedWADOJob: WADORetrieveJob? {
        guard let id = wadoSelectedJobID else { return nil }
        return wadoJobs.first { $0.id == id }
    }

    /// Returns the number of WADO-RS jobs currently in progress.
    public var activeWADOJobCount: Int {
        wadoJobs.filter { $0.status == .inProgress }.count
    }

    // MARK: - 10.4 STOW-RS Operations

    /// Adds a STOW-RS upload job.
    public func addSTOWJob(_ job: STOWUploadJob) {
        service.addSTOWJob(job)
        stowJobs = service.getSTOWJobs()
    }

    /// Removes a STOW-RS upload job by ID.
    public func removeSTOWJob(id: UUID) {
        service.removeSTOWJob(id: id)
        if stowSelectedJobID == id { stowSelectedJobID = nil }
        stowJobs = service.getSTOWJobs()
    }

    /// Removes all STOW-RS jobs that have reached a terminal status.
    public func clearCompletedSTOWJobs() {
        service.clearCompletedSTOWJobs()
        stowJobs = service.getSTOWJobs()
    }

    /// Creates a new STOW-RS job from the current staging fields, enqueues it,
    /// and immediately begins the upload against the default server.
    public func enqueueSTOWUpload() async {
        guard !stowNewFilePaths.isEmpty else {
            errorMessage = "No files selected for upload."
            return
        }
        var job = STOWUploadJob(
            filePaths: stowNewFilePaths,
            totalFiles: stowNewFilePaths.count,
            duplicateHandling: stowDuplicateHandling,
            validationEnabled: stowValidationEnabled,
            pipelineConcurrency: stowPipelineConcurrency
        )
        addSTOWJob(job)
        let jobID = job.id
        let filePaths = stowNewFilePaths
        stowNewFilePaths = []
        isSTOWUploadSheetPresented = false

        // Execute the upload
        guard let profile = defaultServerProfile ?? serverProfiles.first else {
            updateSTOWJobStatus(id: jobID, status: .failed, error: "No DICOMweb server configured.")
            return
        }

        do {
            let client = try DICOMwebClientFactory.makeClient(from: profile)

            // Read file data
            job.status = .validating
            job.startTime = Date()
            service.updateSTOWJob(job)
            stowJobs = service.getSTOWJobs()

            var instances: [Data] = []
            var totalSize: Int64 = 0
            for path in filePaths {
                let url = URL(fileURLWithPath: path)
                let data = try Data(contentsOf: url)
                instances.append(data)
                totalSize += Int64(data.count)
            }

            // Update total size and start uploading
            if var updated = service.stowJob(for: jobID) {
                updated.status = .uploading
                updated.totalBytes = totalSize
                service.updateSTOWJob(updated)
                stowJobs = service.getSTOWJobs()
            }

            let response = try await client.storeInstances(
                instances: instances,
                options: DICOMwebClient.StoreOptions(
                    batchSize: stowPipelineConcurrency,
                    continueOnError: true
                )
            )

            // Update job with results
            if var updated = service.stowJob(for: jobID) {
                updated.uploadedFiles = response.successCount
                updated.failedFiles = response.failureCount
                updated.bytesUploaded = totalSize
                updated.completionTime = Date()
                if response.isFullSuccess {
                    updated.status = .completed
                } else if response.isFullFailure {
                    updated.status = .rejected
                    updated.errorMessage = response.failedInstances.first?.failureDescription
                } else {
                    updated.status = .completed
                    updated.errorMessage = "\(response.failureCount) instance(s) failed"
                }
                service.updateSTOWJob(updated)
                stowJobs = service.getSTOWJobs()
            }
        } catch {
            updateSTOWJobStatus(id: jobID, status: .failed, error: error.localizedDescription)
        }
    }

    /// Helper to update a STOW job's terminal status.
    private func updateSTOWJobStatus(id: UUID, status: STOWUploadStatus, error: String?) {
        if var updated = service.stowJob(for: id) {
            updated.status = status
            updated.errorMessage = error
            updated.completionTime = Date()
            service.updateSTOWJob(updated)
            stowJobs = service.getSTOWJobs()
        }
    }

    /// Returns the currently selected STOW-RS job, if any.
    public var selectedSTOWJob: STOWUploadJob? {
        guard let id = stowSelectedJobID else { return nil }
        return stowJobs.first { $0.id == id }
    }

    /// Returns the number of STOW-RS jobs not yet in a terminal state.
    public var activeSTOWJobCount: Int {
        stowJobs.filter { !$0.status.isTerminal }.count
    }

    // MARK: - 10.5 UPS-RS Operations

    /// Loads UPS-RS workitems from the default DICOMweb server using the
    /// UPS-RS search endpoint.
    public func loadUPSWorkitems() async {
        isUPSQueryRunning = true
        errorMessage = nil

        defer {
            isUPSQueryRunning = false
        }

        guard let profile = defaultServerProfile ?? serverProfiles.first else {
            errorMessage = "No DICOMweb server configured."
            return
        }

        do {
            let client = try DICOMwebClientFactory.makeClient(from: profile)
            let result = try await client.searchWorkitems()
            let items: [UPSWorkitem] = result.workitems.map { workitem in
                let mappedState: UPSState = {
                    switch workitem.state?.rawValue {
                    case "SCHEDULED": return .scheduled
                    case "IN PROGRESS": return .inProgress
                    case "COMPLETED": return .completed
                    case "CANCELED": return .cancelled
                    default: return .scheduled
                    }
                }()
                let mappedPriority: UPSPriority = {
                    switch workitem.priority?.rawValue {
                    case "STAT", "HIGH": return .high
                    case "MEDIUM": return .medium
                    case "LOW": return .low
                    default: return .medium
                    }
                }()
                return UPSWorkitem(
                    workitemUID: workitem.workitemUID,
                    patientName: workitem.patientName ?? "",
                    patientID: workitem.patientID ?? "",
                    procedureStepLabel: workitem.procedureStepLabel ?? "Unnamed",
                    state: mappedState,
                    priority: mappedPriority,
                    completionPercentage: workitem.progressPercentage ?? 0
                )
            }
            service.setUPSWorkitems(items)
            upsWorkitems = items
        } catch {
            errorMessage = "UPS-RS query failed: \(error.localizedDescription)"
        }
    }

    /// Transitions a UPS workitem to a new state, enforcing the UPS state machine of
    /// PS3.4 Table CC.1.1-2 (Change Workitem State, PS3.18 11.7). SCHEDULED is refused as a
    /// target with the same message as dicom-wado (PS3.18 11.7.1.4; Table CC.1.1-2 C303H).
    public func transitionUPSState(_ newState: UPSState, workitemID: UUID) {
        guard let workitem = upsWorkitems.first(where: { $0.id == workitemID }) else { return }
        if let refusal = DICOMwebUPSHelpers.changeStateRefusal(from: workitem.state, to: newState) {
            errorMessage = refusal
            return
        }
        service.updateUPSWorkitemState(newState, for: workitemID)
        upsWorkitems = service.getUPSWorkitems()
    }

    /// Creates a new UPS-RS event subscription from the current subscription fields.
    public func addUPSSubscription() {
        let sub = UPSEventSubscription(
            workitemUID: upsNewSubscriptionWorkitemUID.isEmpty ? nil : upsNewSubscriptionWorkitemUID,
            eventTypes: upsSubscribeEventTypes
        )
        service.addUPSSubscription(sub)
        upsSubscriptions = service.getUPSSubscriptions()
        upsNewSubscriptionWorkitemUID = ""
        isUPSSubscriptionSheetPresented = false
    }

    /// Removes a UPS-RS event subscription by ID.
    public func removeUPSSubscription(id: UUID) {
        service.removeUPSSubscription(id: id)
        upsSubscriptions = service.getUPSSubscriptions()
    }

    /// Returns the currently selected UPS workitem, if any.
    public var selectedUPSWorkitem: UPSWorkitem? {
        guard let id = upsSelectedWorkitemID else { return nil }
        return upsWorkitems.first { $0.id == id }
    }

    /// Returns the first active global subscription (workitem UID = nil), if any.
    public var globalSubscription: UPSEventSubscription? {
        upsSubscriptions.first { $0.isGlobal && $0.isActive }
    }

    // MARK: - 10.5.1 UPS Event Channel Operations

    /// Starts monitoring UPS events via a real WebSocket event channel.
    ///
    /// Opens a `UPSEventChannelManager` against the default (or first) server profile
    /// and begins consuming events from the async stream.
    public func startEventMonitoring() {
        guard !isUPSEventMonitoringActive else { return }

        isUPSEventMonitoringActive = true
        upsEventChannelState = .connecting

        wsEventTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let profile = self.defaultServerProfile ?? self.serverProfiles.first else {
                    await MainActor.run {
                        self.upsEventChannelState = .disconnected
                        self.isUPSEventMonitoringActive = false
                        self.errorMessage = "No DICOMweb server configured for event monitoring."
                    }
                    return
                }

                let configuration = try DICOMwebClientFactory.makeConfiguration(from: profile)
                let aeTitle = "DICOM_STUDIO"
                let manager = UPSEventChannelManager(
                    configuration: configuration,
                    aeTitle: aeTitle
                )

                await MainActor.run {
                    self.eventChannelManager = manager
                }

                // Only open the WebSocket event channel.
                // REST subscriptions are managed externally by the user
                // (e.g. via CLI Workshop → dicom-ups subscribe) and must
                // already exist on the server before the WebSocket will
                // receive any events.  We do NOT register REST subscriptions
                // here to avoid creating unwanted subscriptions on the server.
                try await manager.openEventChannel()

                await MainActor.run {
                    self.upsEventChannelState = .connected
                }

                // Consume events from the async stream
                for await wsEvent in manager.events {
                    guard !Task.isCancelled else { break }
                    let received = Self.mapWebSocketEvent(wsEvent)
                    await MainActor.run {
                        self.appendReceivedEvent(received)
                        // Sync connection state from the manager
                        self.syncChannelState(from: manager)
                    }
                }

                // Stream ended (server closed or explicit close)
                await MainActor.run {
                    if self.isUPSEventMonitoringActive {
                        self.upsEventChannelState = .disconnected
                        self.isUPSEventMonitoringActive = false
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.upsEventChannelState = .disconnected
                    self.isUPSEventMonitoringActive = false
                    self.errorMessage = "Event channel error: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Stops monitoring UPS events and closes the WebSocket channel.
    /// REST subscriptions are NOT removed — they are managed externally
    /// (e.g. via CLI Workshop) and persist on the server independently.
    public func stopEventMonitoring() {
        wsEventTask?.cancel()
        wsEventTask = nil
        let manager = eventChannelManager
        eventChannelManager = nil
        isUPSEventMonitoringActive = false
        upsEventChannelState = .disconnected
        // Only close the WebSocket channel — do NOT send REST unsubscribe
        // requests, since subscriptions were created externally by the user.
        if let manager {
            manager.closeEventChannel()
        }
    }

    /// Syncs the UI channel state from the manager's current connection state.
    private func syncChannelState(from manager: UPSEventChannelManager) {
        let newState: UPSEventChannelState
        switch manager.channelState {
        case .disconnected: newState = .disconnected
        case .connecting:   newState = .connecting
        case .connected:    newState = .connected
        case .reconnecting: newState = .reconnecting
        case .closed:       newState = .closed
        }
        upsEventChannelState = newState
    }

    /// Maps a `UPSWebSocketEvent` from the DICOMWeb library to a `UPSReceivedEvent` display model.
    nonisolated private static func mapWebSocketEvent(_ wsEvent: UPSWebSocketEvent) -> UPSReceivedEvent {
        let eventType: UPSEventType
        switch wsEvent.eventType {
        case .stateReport, .assigned, .completed, .canceled, .scpStatusChange:
            eventType = .stateChange
        case .progressReport:
            eventType = .progressChange
        case .cancelRequested:
            eventType = .cancellationRequested
        }

        // Extract event-specific details from the raw DICOM JSON payload
        let parsed = UPSEventPayloadParser.parse(rawJSON: wsEvent.rawJSON, eventType: wsEvent.eventType)

        let summary: String
        switch wsEvent.eventType {
        case .stateReport:
            if let prev = parsed.previousState, let cur = parsed.newState {
                summary = "State: \(prev) → \(cur)"
            } else if let cur = parsed.newState {
                summary = "State changed to \(cur)"
            } else {
                summary = "State changed"
            }
        case .progressReport:
            if let pct = parsed.progressPercentage, let desc = parsed.progressDescription {
                summary = "Progress: \(pct)% — \(desc)"
            } else if let pct = parsed.progressPercentage {
                summary = "Progress: \(pct)%"
            } else if let desc = parsed.progressDescription {
                summary = "Progress: \(desc)"
            } else {
                summary = "Progress updated"
            }
        case .cancelRequested:
            if let reason = parsed.reason {
                summary = "Cancellation requested: \(reason)"
            } else {
                summary = "Cancellation requested"
            }
        case .assigned:
            if let contact = parsed.contactDisplayName {
                summary = "Assigned to \(contact)"
            } else {
                summary = "Workitem assigned"
            }
        case .completed:
            if let reason = parsed.reason {
                summary = "Completed — \(reason)"
            } else {
                summary = "Workitem completed"
            }
        case .canceled:
            if let reason = parsed.reason {
                summary = "Canceled — \(reason)"
            } else {
                summary = "Workitem canceled"
            }
        case .scpStatusChange:
            summary = "Origin server status changed (restarted or going down)"
        }

        return UPSReceivedEvent(
            eventType: eventType,
            workitemUID: wsEvent.workitemUID,
            transactionUID: wsEvent.transactionUID,
            receivedAt: wsEvent.receivedAt,
            summary: summary,
            previousState: parsed.previousState,
            newState: parsed.newState,
            reason: parsed.reason,
            progressPercentage: parsed.progressPercentage,
            progressDescription: parsed.progressDescription,
            contactDisplayName: parsed.contactDisplayName
        )
    }

    /// Updates the event channel connection state.
    public func updateEventChannelState(_ state: UPSEventChannelState) {
        upsEventChannelState = state
    }

    /// Appends a received UPS event to the event log.
    ///
    /// Trims history to `upsMaxEventHistory` entries, removing the oldest first.
    /// Asynchronously fetches workitem context for richer display.
    public func appendReceivedEvent(_ event: UPSReceivedEvent) {
        upsReceivedEvents.insert(event, at: 0)
        if upsReceivedEvents.count > upsMaxEventHistory {
            upsReceivedEvents = Array(upsReceivedEvents.prefix(upsMaxEventHistory))
        }

        // Auto-update workitem state if this is a state change event
        if event.eventType == .stateChange {
            updateWorkitemFromEvent(event)
        }

        // Fetch workitem context asynchronously for richer display
        if !event.workitemUID.isEmpty {
            fetchWorkitemContextForEvent(eventID: event.id, workitemUID: event.workitemUID)
        }
    }

    /// Clears the received events log.
    public func clearReceivedEvents() {
        upsReceivedEvents.removeAll()
    }

    /// Updates a workitem's state based on a received event.
    private func updateWorkitemFromEvent(_ event: UPSReceivedEvent) {
        if let index = upsWorkitems.firstIndex(where: { $0.workitemUID == event.workitemUID }) {
            // Workitem state was updated; re-load from service for consistency
            upsWorkitems = service.getUPSWorkitems()
            _ = index // silences unused warning
        }
    }

    /// Fetches workitem details from the server and enriches the received event.
    ///
    /// Reuses the existing `UPSEventChannelManager.upsClient` to avoid creating
    /// new URLSessions that could destabilize the active WebSocket connection.
    private func fetchWorkitemContextForEvent(eventID: UUID, workitemUID: String) {
        // Reuse the event channel manager's persistent UPS client — creating a
        // new client for each event would spawn separate URLSessions / TCP
        // connections that interfere with dcm4chee-arc's WebSocket channel.
        guard let client = eventChannelManager?.upsClient else { return }

        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await client.retrieveWorkitemResult(uid: workitemUID)

                await MainActor.run {
                    guard let index = self.upsReceivedEvents.firstIndex(where: { $0.id == eventID }) else { return }
                    self.upsReceivedEvents[index].patientName = result.patientName
                    self.upsReceivedEvents[index].patientID = result.patientID
                    self.upsReceivedEvents[index].procedureStepLabel = result.procedureStepLabel
                    self.upsReceivedEvents[index].scheduledStartDateTime = result.scheduledStartDateTime
                    self.upsReceivedEvents[index].workitemState = result.state?.rawValue
                    self.upsReceivedEvents[index].workitemPriority = result.priority?.rawValue
                    self.upsReceivedEvents[index].accessionNumber = result.accessionNumber
                    self.upsReceivedEvents[index].isWorkitemContextLoaded = true
                }
            } catch {
                // Silently mark as loaded (no context available) — don't block event display
                await MainActor.run {
                    guard let index = self.upsReceivedEvents.firstIndex(where: { $0.id == eventID }) else { return }
                    self.upsReceivedEvents[index].isWorkitemContextLoaded = true
                }
            }
        }
    }

    // MARK: - 10.6 Performance Operations

    /// Refreshes the performance stats and history from the service.
    public func refreshPerformanceStats() {
        performanceStats    = service.getPerformanceStats()
        performanceHistory  = service.getPerformanceHistory()
    }

    /// Records a new performance sample and updates the history.
    public func recordPerformanceSample(_ stats: DICOMwebPerformanceStats) {
        service.updatePerformanceStats(stats)
        performanceStats   = service.getPerformanceStats()
        performanceHistory = service.getPerformanceHistory()
    }

    /// Resets all performance stats and clears the history.
    public func resetPerformanceStats() {
        service.resetPerformanceStats()
        performanceStats   = DICOMwebPerformanceStats()
        performanceHistory = []
    }

    /// Returns an overall health label for the current performance stats.
    public var performanceHealthDescription: String {
        DICOMwebPerformanceHelpers.overallHealthDescription(stats: performanceStats)
    }
}
