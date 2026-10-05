// CLIWorkshopViewModel.swift
// DICOMStudio
//
// DICOM Studio — ViewModel for CLI Tools Workshop (Milestone 16)

import Foundation
import Observation
import DICOMCore
import DICOMKit
import DICOMNetwork
import DICOMWeb

#if canImport(CoreGraphics)
import CoreGraphics
import ImageIO
#endif

// MARK: - DICOM Part 10 File Format helpers (file-private, context-free)

/// Encodes a 16-bit unsigned integer in little-endian byte order.
private func le16(_ v: UInt16) -> Data {
    Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)])
}

/// Encodes a 32-bit unsigned integer in little-endian byte order.
private func le32(_ v: UInt32) -> Data {
    Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF),
          UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)])
}

/// Encodes a File Meta Information element with VR "UL" (4-byte unsigned long).
private func fmiUL(_ group: UInt16, _ element: UInt16, _ value: UInt32) -> Data {
    le16(group) + le16(element)
    + Data([0x55, 0x4C])  // "UL"
    + le16(4)             // value length
    + le32(value)
}

/// Encodes a File Meta Information element with VR "OB" (uses 4-byte length field).
private func fmiOB(_ group: UInt16, _ element: UInt16, _ value: Data) -> Data {
    le16(group) + le16(element)
    + Data([0x4F, 0x42])  // "OB"
    + Data([0x00, 0x00])  // reserved
    + le32(UInt32(value.count))
    + value
}

/// Encodes a File Meta Information element with VR "UI".
/// UI values are null-padded to even byte length per PS3.5 §6.2.
private func fmiUI(_ group: UInt16, _ element: UInt16, _ value: String) -> Data {
    var bytes = value.data(using: .ascii) ?? Data()
    if bytes.count % 2 != 0 { bytes.append(0x00) }  // null padding for UI
    return le16(group) + le16(element)
        + Data([0x55, 0x49])      // "UI"
        + le16(UInt16(bytes.count))
        + bytes
}

/// Wraps raw DICOM C-STORE dataset bytes in a DICOM Part 10 file container.
///
/// C-STORE transfers deliver raw dataset bytes without the 128-byte preamble,
/// DICM magic bytes, or File Meta Information group (0002,xxxx).  This function
/// reconstructs the proper Part 10 layout required by every conformant DICOM
/// reader, following PS3.10 §7.1.
///
/// - Parameters:
///   - dataset:          Raw dataset bytes as delivered by C-STORE / C-GET.
///   - sopClassUID:      SOP Class UID for (0002,0002) and (0002,0003).
///   - sopInstanceUID:   SOP Instance UID for (0002,0003).
///   - transferSyntaxUID: Transfer Syntax UID for (0002,0010).
/// - Returns: A complete Part 10 DICOM file object (Data).
func part10Wrap(dataset: Data, sopClassUID: String,
                sopInstanceUID: String,
                transferSyntaxUID: String) -> Data {
    // Build the File Meta Information elements (all Explicit VR LE)
    var meta = Data()
    meta += fmiOB(0x0002, 0x0001, Data([0x00, 0x01]))       // FileMetaInformationVersion
    meta += fmiUI(0x0002, 0x0002, sopClassUID)               // MediaStorageSOPClassUID
    meta += fmiUI(0x0002, 0x0003, sopInstanceUID)            // MediaStorageSOPInstanceUID
    meta += fmiUI(0x0002, 0x0010, transferSyntaxUID)         // TransferSyntaxUID
    meta += fmiUI(0x0002, 0x0012, "1.2.826.0.1.3680043.9.7433.1.1")  // ImplementationClassUID

    var file = Data()
    file += Data(repeating: 0, count: 128)                  // 128-byte preamble
    file += Data([0x44, 0x49, 0x43, 0x4D])                  // "DICM" magic
    file += fmiUL(0x0002, 0x0000, UInt32(meta.count))       // FileMetaInformationGroupLength
    file += meta
    file += dataset
    return file
}

/// Best-effort scan of a raw C-GET dataset for SeriesInstanceUID (0020,000E).
///
/// Mirrors the `dicom-retrieve` CLI helper (Sources/dicom-retrieve/RetrieveExecutor.swift)
/// so the app and CLI file study-level C-GET results into the same `studyUID/seriesUID/`
/// tree. Handles Explicit and Implicit VR Little Endian (every transfer syntax a C-GET
/// yields; encapsulated pixel data still uses Explicit VR LE for the surrounding data
/// set). Returns `nil` on anything it can't confidently parse (undefined-length
/// sequences, big endian, truncation) so callers fall back to a flat layout rather than
/// misfiling. Never traps: every read is bounds-checked.
func extractSeriesUID(fromDataSet data: Data, transferSyntaxUID: String) -> String? {
    let bytes = Data(data)   // re-base to guarantee 0-based indexing
    let implicitVR = (transferSyntaxUID == "1.2.840.10008.1.2")
    let longFormVRs: Set<String> = ["OB", "OW", "OF", "OD", "OL", "SQ", "UT", "UN", "UC", "UR"]

    var offset = 0
    while offset + 8 <= bytes.count {
        guard let group = bytes.readUInt16LE(at: offset),
              let element = bytes.readUInt16LE(at: offset + 2) else { return nil }
        // Elements are ordered by (group, element); once we pass 0020,000E it's absent.
        if group > 0x0020 || (group == 0x0020 && element > 0x000E) { return nil }

        let valueLength: Int
        let valueOffset: Int
        if implicitVR {
            guard let len = bytes.readUInt32LE(at: offset + 4) else { return nil }
            valueLength = Int(len); valueOffset = offset + 8
        } else {
            let vr = String(decoding: bytes[offset + 4 ..< offset + 6], as: UTF8.self)
            if longFormVRs.contains(vr) {
                guard offset + 12 <= bytes.count, let len = bytes.readUInt32LE(at: offset + 8) else { return nil }
                valueLength = Int(len); valueOffset = offset + 12
            } else {
                guard let len = bytes.readUInt16LE(at: offset + 6) else { return nil }
                valueLength = Int(len); valueOffset = offset + 8
            }
        }

        if valueLength == 0xFFFF_FFFF { return nil }   // undefined length — can't skip reliably
        guard valueOffset + valueLength <= bytes.count else { return nil }

        if group == 0x0020 && element == 0x000E {
            let raw = bytes[valueOffset ..< valueOffset + valueLength]
            let uid = String(decoding: raw, as: UTF8.self)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
            return uid.isEmpty ? nil : uid
        }
        offset = valueOffset + valueLength
    }
    return nil
}

// MARK: - SCP Storage Delegate

/// StorageDelegate that saves received C-STORE instances as proper Part 10
/// DICOM files (with preamble, DICM magic, and File Meta Information).
private actor DICOMStudioSCPDelegate: StorageDelegate {
    private let storageDir: URL

    init(storageDir: URL) {
        self.storageDir = storageDir
    }

    func didReceive(file: ReceivedFile) async throws {
        let wrapped = part10Wrap(
            dataset: file.dataSetData,
            sopClassUID: file.sopClassUID,
            sopInstanceUID: file.sopInstanceUID,
            transferSyntaxUID: file.transferSyntaxUID
        )
        try FileManager.default.createDirectory(
            at: storageDir, withIntermediateDirectories: true)
        let dst = storageDir.appendingPathComponent("\(file.sopInstanceUID).dcm")
        try wrapped.write(to: dst, options: .atomic)
    }
}

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
@MainActor
@Observable
public final class CLIWorkshopViewModel {
    private let service: CLIWorkshopService

    /// Callback to open a retrieved file in the Viewer tab.
    /// Set by MainViewModel to wire navigation.
    public var onOpenInViewer: ((String, URL?) -> Void)?

    /// Callback to open a set of retrieved files as a navigable series in the Viewer tab.
    /// Parameters: ordered file paths, start index, optional security-scoped parent URL.
    /// When set, `openRetrievedFileInViewer()` uses this instead of `onOpenInViewer`.
    public var onOpenSeriesInViewer: (([String], Int, URL?) -> Void)?

    public var activeTab: CLIWorkshopTab = .fileInspection
    public var isLoading: Bool = false
    public var errorMessage: String? = nil

    // 16.1 Network Configuration
    public var networkProfiles: [CLINetworkProfile] = []
    public var activeProfileID: UUID? = nil
    public var connectionTestStatus: CLIConnectionTestStatus = .untested

    // 16.2 Tool Catalog
    public var tools: [CLIToolDefinition] = []
    public var selectedToolID: String? = nil

    // 16.3 Parameter Configuration
    public var parameterDefinitions: [CLIParameterDefinition] = []
    public var parameterValues: [CLIParameterValue] = []

    // 16.4 File Drop Zone
    public var inputFiles: [CLIFileEntry] = []
    public var outputPath: String = ""
    public var fileDropState: CLIFileDropState = .empty

    /// Security-scoped URLs from file importers, keyed by parameter ID.
    /// Used to gain sandbox access when reading user-selected files.
    public var securityScopedURLs: [String: URL] = [:]

    /// File paths of the most recently retrieved DICOM files (from dicom-retrieve or dicom-qr).
    /// Used to enable "Open in Viewer" after retrieval.
    public var lastRetrievedFiles: [String] = []

    /// Security-scoped output URL used for the last file write batch.
    /// Stored here so the viewer can access files written outside the sandbox container.
    public var lastRetrievedOutputURL: URL? = nil

    // MARK: - Local SCP Listener

    /// Whether the local DICOM SCP listener is currently running.
    public var scpIsRunning: Bool = false
    /// Port the local SCP listens on.
    public var scpPort: String = "11112"
    /// AE Title used by the local SCP.
    public var scpAETitle: String = "DICOMSTUDIO"
    /// Output directory where the SCP writes received DICOM files.
    public var scpOutputDir: String = {
        NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first
            ?? NSTemporaryDirectory()
    }()
    /// Human-readable status message for the local SCP.
    public var scpStatusMessage: String = "SCP not started"
    /// Files received through the local SCP listener (most recent first).
    public var scpReceivedFiles: [String] = []
    /// Structured event log for the local SCP listener.
    public var appLog: [SCPLogEntry] = []

    private var storageSCP: DICOMStorageServer?
    private var scpEventTask: Task<Void, Never>?

    // 16.5 Console
    public var consoleStatus: CLIConsoleStatus = .idle
    public var consoleOutput: String = ""
    public var commandPreview: String = ""

    // ⚠️ TESTING-ONLY — terminal-vs-app parity check for the selected tool (see
    // CLIToolTerminalCompare.swift). Requires the App Sandbox to be disabled.
    // REMOVE BEFORE PRODUCTION (memory: dicom-info-terminal-compare-testonly).
    var isRunningTerminalCompare: Bool = false
    var terminalCompareResult: CLIToolCompareResult?

    // 16.6 Command History
    public var commandHistory: [CLICommandHistoryEntry] = []

    // 16.8 Educational Features
    public var experienceMode: CLIExperienceMode = .beginner
    public var glossaryEntries: [CLIGlossaryEntry] = []
    public var glossarySearchQuery: String = ""

    // Server selection for network tools
    /// Saved PACS server profiles from the Networking tab.
    public var savedServerProfiles: [PACSServerProfile] = []
    /// Whether the user is picking a saved server or entering details manually.
    public var networkInputMode: NetworkInputMode = .manual
    /// The ID of the selected saved server profile.
    public var selectedSavedServerID: UUID? = nil
    /// Whether the "Add Server" sheet is shown.
    public var showAddServerSheet: Bool = false
    /// Whether the "Edit Server" sheet is shown.
    public var showEditServerSheet: Bool = false
    /// The ID of the PACS server being edited (nil when adding).
    public var editingServerID: UUID? = nil
    /// Editable fields for adding/editing a server.
    public var newServerName: String = ""
    public var newServerHost: String = ""
    public var newServerPort: String = "11112"
    public var newServerCalledAET: String = ""
    public var newServerCallingAET: String = "DICOMSTUDIO"

    // MARK: - UPS Transaction UID Cache
    /// Stores the Transaction UID used when claiming each workitem (IN PROGRESS).
    /// Per PS3.18 §11.5.2, the server never returns the Transaction UID in
    /// Retrieve Workitem responses — it acts as an access lock.  We must
    /// remember it ourselves for subsequent COMPLETED / CANCELED transitions.
    /// Key = Workitem UID, Value = Transaction UID.
    private var upsTransactionUIDs: [String: String] = [:]

    // DICOMweb server selection
    /// Saved DICOMweb server profiles.
    public var savedDICOMwebProfiles: [DICOMwebServerProfile] = []
    /// The ID of the selected DICOMweb server profile.
    public var selectedDICOMwebServerID: UUID? = nil
    /// Whether the "Add DICOMweb Server" sheet is shown.
    public var showAddDICOMwebServerSheet: Bool = false
    /// Whether the "Edit DICOMweb Server" sheet is shown.
    public var showEditDICOMwebServerSheet: Bool = false
    /// The ID of the DICOMweb server being edited (nil when adding).
    public var editingDICOMwebServerID: UUID? = nil
    /// Editable fields for adding/editing a DICOMweb server.
    public var newDICOMwebServerName: String = ""
    public var newDICOMwebServerURL: String = ""
    public var newDICOMwebAuthMethod: String = "none"
    public var newDICOMwebUsername: String = ""
    public var newDICOMwebToken: String = ""

    /// Toggles between using a saved server profile and entering parameters manually.
    public enum NetworkInputMode: String, Sendable, CaseIterable, Identifiable {
        case savedServer = "Saved Server"
        case manual = "Manual"
        public var id: String { rawValue }
    }

    // MARK: - Persistent Default Server

    /// UserDefaults keys for persistent default server values.
    private enum DefaultServerKeys {
        static let host = "studio.cli.defaultServerHost"
        static let port = "studio.cli.defaultServerPort"
        static let calledAET = "studio.cli.defaultCalledAET"
        static let callingAET = "studio.cli.defaultCallingAET"
    }

    /// Saves the current server parameters as persistent defaults.
    public func saveCurrentServerAsDefault() {
        let hostVal = paramValue("host")
        let portVal = paramValue("port")
        let calledAET = paramValue("called-aet")
        let callingAET = paramValue("aet")
        if !hostVal.isEmpty { UserDefaults.standard.set(hostVal, forKey: DefaultServerKeys.host) }
        if !portVal.isEmpty { UserDefaults.standard.set(portVal, forKey: DefaultServerKeys.port) }
        if !calledAET.isEmpty { UserDefaults.standard.set(calledAET, forKey: DefaultServerKeys.calledAET) }
        if !callingAET.isEmpty { UserDefaults.standard.set(callingAET, forKey: DefaultServerKeys.callingAET) }
    }

    /// Loads persistent default server values, returning non-nil values for each.
    public func persistentDefaults() -> (host: String?, port: String?, calledAET: String?, callingAET: String?) {
        return (
            host: UserDefaults.standard.string(forKey: DefaultServerKeys.host),
            port: UserDefaults.standard.string(forKey: DefaultServerKeys.port),
            calledAET: UserDefaults.standard.string(forKey: DefaultServerKeys.calledAET),
            callingAET: UserDefaults.standard.string(forKey: DefaultServerKeys.callingAET)
        )
    }

    public init(service: CLIWorkshopService = CLIWorkshopService()) {
        self.service = service
        loadFromService()

        // Load persisted DICOMweb server profiles from disk.
        let webStorage = DICOMwebServerProfileStorageService()
        savedDICOMwebProfiles = webStorage.load()
    }

    /// Loads all state from the backing service into observable properties.
    public func loadFromService() {
        networkProfiles      = service.getNetworkProfiles()
        activeProfileID      = service.getActiveProfileID()
        connectionTestStatus = service.getConnectionTestStatus()
        tools                = service.getTools()
        selectedToolID       = service.getSelectedToolID()
        parameterDefinitions = service.getParameterDefinitions()
        parameterValues      = service.getParameterValues()
        inputFiles           = service.getInputFiles()
        outputPath           = service.getOutputPath()
        fileDropState        = service.getFileDropState()
        consoleStatus        = service.getConsoleStatus()
        consoleOutput        = service.getConsoleOutput()
        commandPreview       = service.getCommandPreview()
        commandHistory       = service.getCommandHistory()
        experienceMode       = service.getExperienceMode()
        glossaryEntries      = service.getGlossaryEntries()
        glossarySearchQuery  = service.getGlossarySearchQuery()
    }

    // MARK: - 16.1 Network Configuration

    /// Adds a new network profile.
    public func addProfile(_ profile: CLINetworkProfile) {
        networkProfiles.append(profile)
        service.addProfile(profile)
    }

    /// Removes a network profile by ID.
    public func removeProfile(id: UUID) {
        networkProfiles.removeAll { $0.id == id }
        service.removeProfile(id: id)
        if activeProfileID == id {
            activeProfileID = networkProfiles.first?.id
            service.setActiveProfileID(activeProfileID)
        }
    }

    /// Updates an existing network profile.
    public func updateProfile(_ profile: CLINetworkProfile) {
        guard let idx = networkProfiles.firstIndex(where: { $0.id == profile.id }) else { return }
        networkProfiles[idx] = profile
        service.updateProfile(profile)
    }

    /// Sets the active network profile by ID.
    public func setActiveProfile(id: UUID?) {
        activeProfileID = id
        service.setActiveProfileID(id)
    }

    /// Returns the currently active network profile, or nil.
    public func activeProfile() -> CLINetworkProfile? {
        guard let id = activeProfileID else { return networkProfiles.first }
        return networkProfiles.first { $0.id == id }
    }

    /// Returns the connection summary for the active profile.
    public func activeConnectionSummary() -> String {
        guard let profile = activeProfile() else { return "No profile configured" }
        return NetworkConfigHelpers.connectionSummary(for: profile)
    }

    /// Updates the connection test status.
    public func updateConnectionTestStatus(_ status: CLIConnectionTestStatus) {
        connectionTestStatus = status
        service.setConnectionTestStatus(status)
    }

    // MARK: - 16.2 Tool Selection

    /// Switches to a category tab and refreshes the UI by selecting that
    /// category's first tool — so the parameter form, command preview, and
    /// console all update to the new selection (rather than showing stale state).
    public func selectCategory(_ tab: CLIWorkshopTab) {
        activeTab = tab
        if tab == .listener {
            selectTool(id: nil)
        } else {
            selectTool(id: toolsForActiveTab().first?.id)
        }
    }

    /// Selects a tool by ID.
    public func selectTool(id: String?) {
        selectedToolID = id
        service.setSelectedToolID(id)
        // Reset parameters when tool changes
        parameterValues.removeAll()
        service.setParameterValues([])
        inputFiles.removeAll()
        service.setInputFiles([])
        consoleOutput = ""
        service.setConsoleOutput("")
        consoleStatus = .idle
        service.setConsoleStatus(.idle)
        // Refresh the output side: drop any TESTING-ONLY terminal-compare result
        // from the previously selected tool.
        terminalCompareResult = nil
        isRunningTerminalCompare = false
        // Clear security-scoped URLs from previous tool
        securityScopedURLs.removeAll()
        // Load parameter definitions and apply defaults for the selected tool
        if let toolID = id {
            let defs = ToolCatalogHelpers.parameterDefinitions(for: toolID)
            parameterDefinitions = defs
            service.setParameterDefinitions(defs)
            // Pre-populate default values
            for def in defs where !def.defaultValue.isEmpty {
                let pv = CLIParameterValue(parameterID: def.id, stringValue: def.defaultValue)
                parameterValues.append(pv)
            }
            // Re-apply the saved server profile on tool switch so the connection
            // params are consistent, but do NOT restore UserDefaults-persisted
            // values — manually-typed data should not carry over across tools.
            let hasHostParam = defs.contains(where: { $0.id == "host" })
            if let serverID = selectedSavedServerID,
               let server = savedServerProfiles.first(where: { $0.id == serverID }),
               hasHostParam {
                updateParameterValueSilent(parameterID: "host", value: server.host)
                let port = server.port > 0 ? server.port : 11112
                updateParameterValueSilent(parameterID: "port", value: String(port))
                updateParameterValueSilent(parameterID: "aet", value: server.localAETitle)
                updateParameterValueSilent(parameterID: "called-aet", value: server.remoteAETitle)
                updateParameterValueSilent(parameterID: "timeout", value: String(Int(server.timeoutSeconds)))
            }
            service.setParameterValues(parameterValues)
            rebuildCommandPreview()
        } else {
            parameterDefinitions = []
            service.setParameterDefinitions([])
        }
    }

    /// Returns the currently selected tool definition, or nil.
    public func selectedTool() -> CLIToolDefinition? {
        guard let id = selectedToolID else { return nil }
        return tools.first { $0.id == id }
    }

    /// Returns tools filtered by the active tab.
    public func toolsForActiveTab() -> [CLIToolDefinition] {
        ToolCatalogHelpers.tools(for: activeTab)
    }

    /// Returns network tools grouped by DIMSE vs DICOMweb for the Network Operations tab.
    public func groupedNetworkTools() -> [(group: NetworkToolGroup, tools: [CLIToolDefinition])] {
        ToolCatalogHelpers.groupedNetworkOperationsTools()
    }

    /// Whether the currently selected tool is a network tool that supports server selection.
    public var isNetworkToolSelected: Bool {
        guard let tool = selectedTool() else { return false }
        return tool.requiresNetwork
    }

    /// Whether the currently selected tool is a DICOMweb tool (vs DIMSE).
    public var isDICOMwebToolSelected: Bool {
        guard let tool = selectedTool() else { return false }
        return tool.networkToolGroup == .dicomweb
    }

    /// Applies a saved PACS server profile's values to the current parameters.
    public func applySavedServer(id: UUID?) {
        selectedSavedServerID = id
        guard let serverID = id,
              let server = savedServerProfiles.first(where: { $0.id == serverID }) else {
            return
        }
        let port = server.port > 0 ? server.port : 11112
        updateParameterValue(parameterID: "host", value: server.host)
        updateParameterValue(parameterID: "port", value: String(port))
        updateParameterValue(parameterID: "aet", value: server.localAETitle)
        updateParameterValue(parameterID: "called-aet", value: server.remoteAETitle)
        updateParameterValue(parameterID: "timeout", value: String(Int(server.timeoutSeconds)))
        rebuildCommandPreview()
    }

    /// Applies a saved DICOMweb server profile's values to the current parameters.
    public func applySavedDICOMwebServer(id: UUID?) {
        selectedDICOMwebServerID = id
        guard let serverID = id,
              let server = savedDICOMwebProfiles.first(where: { $0.id == serverID }) else {
            return
        }
        updateParameterValue(parameterID: "url", value: server.baseURL)
        switch server.authMethod {
        case .none:
            updateParameterValue(parameterID: "auth", value: "none")
        case .basic:
            updateParameterValue(parameterID: "auth", value: "basic")
            updateParameterValue(parameterID: "username", value: server.username)
            // #45: the password goes into the internal `password` field, never
            // into `token` — `--token` is Bearer-only in the dicom-wado CLI.
            updateParameterValue(parameterID: "password", value: server.password)
        case .bearer, .jwt:
            updateParameterValue(parameterID: "auth", value: "bearer")
            updateParameterValue(parameterID: "token", value: server.bearerToken)
        case .oauth2PKCE:
            updateParameterValue(parameterID: "auth", value: "bearer")
            updateParameterValue(parameterID: "token", value: server.bearerToken)
        }
        rebuildCommandPreview()
    }

    /// Adds a new DICOMweb server profile from the "Add DICOMweb Server" form.
    public func addNewDICOMwebServerFromForm() {
        let name = newDICOMwebServerName.trimmingCharacters(in: .whitespaces)
        let url = newDICOMwebServerURL.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !url.isEmpty else { return }

        let authMethod: DICOMwebAuthMethod
        switch newDICOMwebAuthMethod {
        case "basic": authMethod = .basic
        case "bearer": authMethod = .bearer
        default: authMethod = .none
        }

        let profile = DICOMwebServerProfile(
            name: name,
            baseURL: url,
            authMethod: authMethod,
            bearerToken: authMethod == .bearer ? newDICOMwebToken : "",
            username: authMethod == .basic ? newDICOMwebUsername : "",
            password: authMethod == .basic ? newDICOMwebToken : ""
        )
        savedDICOMwebProfiles.append(profile)

        // Persist via DICOMwebServerProfileStorageService
        let storage = DICOMwebServerProfileStorageService()
        try? storage.save(savedDICOMwebProfiles)

        // Reset form
        newDICOMwebServerName = ""
        newDICOMwebServerURL = ""
        newDICOMwebAuthMethod = "none"
        newDICOMwebUsername = ""
        newDICOMwebToken = ""
        showAddDICOMwebServerSheet = false

        // Auto-select the newly added server
        applySavedDICOMwebServer(id: profile.id)
    }

    /// Removes a saved DICOMweb server profile by ID.
    public func removeSavedDICOMwebServer(id: UUID) {
        savedDICOMwebProfiles.removeAll { $0.id == id }
        if selectedDICOMwebServerID == id {
            selectedDICOMwebServerID = nil
        }

        // Persist removal
        let storage = DICOMwebServerProfileStorageService()
        try? storage.save(savedDICOMwebProfiles)
    }

    /// Populates the edit form with an existing DICOMweb server profile's data.
    public func beginEditDICOMwebServer(id: UUID) {
        guard let server = savedDICOMwebProfiles.first(where: { $0.id == id }) else { return }
        editingDICOMwebServerID = server.id
        newDICOMwebServerName = server.name
        newDICOMwebServerURL = server.baseURL
        switch server.authMethod {
        case .basic:
            newDICOMwebAuthMethod = "basic"
            newDICOMwebUsername = server.username
            newDICOMwebToken = server.password
        case .bearer, .jwt:
            newDICOMwebAuthMethod = "bearer"
            newDICOMwebToken = server.bearerToken
        case .oauth2PKCE:
            newDICOMwebAuthMethod = "bearer"
            newDICOMwebToken = server.bearerToken
        case .none:
            newDICOMwebAuthMethod = "none"
        }
        showEditDICOMwebServerSheet = true
    }

    /// Saves edits to an existing DICOMweb server profile.
    public func saveEditedDICOMwebServer() {
        guard let editID = editingDICOMwebServerID,
              let idx = savedDICOMwebProfiles.firstIndex(where: { $0.id == editID }) else { return }
        let name = newDICOMwebServerName.trimmingCharacters(in: .whitespaces)
        let url = newDICOMwebServerURL.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !url.isEmpty else { return }

        let authMethod: DICOMwebAuthMethod
        switch newDICOMwebAuthMethod {
        case "basic": authMethod = .basic
        case "bearer": authMethod = .bearer
        default: authMethod = .none
        }

        savedDICOMwebProfiles[idx] = DICOMwebServerProfile(
            id: editID,
            name: name,
            baseURL: url,
            authMethod: authMethod,
            bearerToken: authMethod == .bearer ? newDICOMwebToken : "",
            username: authMethod == .basic ? newDICOMwebUsername : "",
            password: authMethod == .basic ? newDICOMwebToken : ""
        )

        let storage = DICOMwebServerProfileStorageService()
        try? storage.save(savedDICOMwebProfiles)

        // Reset form
        editingDICOMwebServerID = nil
        newDICOMwebServerName = ""
        newDICOMwebServerURL = ""
        newDICOMwebAuthMethod = "none"
        newDICOMwebUsername = ""
        newDICOMwebToken = ""
        showEditDICOMwebServerSheet = false

        // Re-apply if this was the selected server
        if selectedDICOMwebServerID == editID {
            applySavedDICOMwebServer(id: editID)
        }
    }

    /// Saves the current DICOMweb server parameters as persistent defaults.
    public func saveDICOMwebServerAsDefault() {
        let url = paramValue("url")
        let auth = paramValue("auth")
        let user = paramValue("username")
        // #45: under basic auth the secret lives in the internal `password`
        // field; `token` is populated only in bearer mode.
        let token = paramValue("token").isEmpty ? paramValue("password") : paramValue("token")
        if !url.isEmpty { UserDefaults.standard.set(url, forKey: DICOMwebDefaultKeys.url) }
        if !auth.isEmpty { UserDefaults.standard.set(auth, forKey: DICOMwebDefaultKeys.auth) }
        if !user.isEmpty { UserDefaults.standard.set(user, forKey: DICOMwebDefaultKeys.username) }
        if !token.isEmpty { UserDefaults.standard.set(token, forKey: DICOMwebDefaultKeys.token) }
    }

    /// UserDefaults keys for persistent default DICOMweb server values.
    private enum DICOMwebDefaultKeys {
        static let url = "studio.cli.defaultDICOMwebURL"
        static let auth = "studio.cli.defaultDICOMwebAuth"
        static let username = "studio.cli.defaultDICOMwebUsername"
        static let token = "studio.cli.defaultDICOMwebToken"
    }

    /// Adds a new server profile from the CLI Workshop "Add Server" form and persists it.
    public func addNewServerFromForm() {
        let name = newServerName.trimmingCharacters(in: .whitespaces)
        let host = newServerHost.trimmingCharacters(in: .whitespaces)
        let port = UInt16(newServerPort) ?? 11112
        let calledAET = newServerCalledAET.trimmingCharacters(in: .whitespaces)
        let callingAET = newServerCallingAET.trimmingCharacters(in: .whitespaces)

        guard !name.isEmpty, !host.isEmpty, !calledAET.isEmpty else { return }

        let profile = PACSServerProfile(
            name: name,
            host: host,
            port: port,
            remoteAETitle: calledAET,
            localAETitle: callingAET.isEmpty ? "DICOMSTUDIO" : callingAET
        )
        savedServerProfiles.append(profile)

        // Also persist via ServerProfileStorageService
        let storage = ServerProfileStorageService()
        var all = storage.load()
        all.append(profile)
        try? storage.save(all)

        // Reset form
        newServerName = ""
        newServerHost = ""
        newServerPort = "11112"
        newServerCalledAET = ""
        newServerCallingAET = "DICOMSTUDIO"
        showAddServerSheet = false

        // Auto-select the newly added server
        applySavedServer(id: profile.id)
    }

    /// Removes a saved server profile by ID.
    public func removeSavedServer(id: UUID) {
        savedServerProfiles.removeAll { $0.id == id }
        if selectedSavedServerID == id {
            selectedSavedServerID = nil
        }

        // Persist removal
        let storage = ServerProfileStorageService()
        var all = storage.load()
        all.removeAll { $0.id == id }
        try? storage.save(all)
    }

    /// Populates the edit form with an existing PACS server profile's data.
    public func beginEditServer(id: UUID) {
        guard let server = savedServerProfiles.first(where: { $0.id == id }) else { return }
        editingServerID = server.id
        newServerName = server.name
        newServerHost = server.host
        newServerPort = String(server.port)
        newServerCalledAET = server.remoteAETitle
        newServerCallingAET = server.localAETitle
        showEditServerSheet = true
    }

    /// Saves edits to an existing PACS server profile.
    public func saveEditedServer() {
        guard let editID = editingServerID,
              let idx = savedServerProfiles.firstIndex(where: { $0.id == editID }) else { return }
        let name = newServerName.trimmingCharacters(in: .whitespaces)
        let host = newServerHost.trimmingCharacters(in: .whitespaces)
        let port = UInt16(newServerPort) ?? 11112
        let calledAET = newServerCalledAET.trimmingCharacters(in: .whitespaces)
        let callingAET = newServerCallingAET.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !host.isEmpty, !calledAET.isEmpty else { return }

        savedServerProfiles[idx] = PACSServerProfile(
            id: editID,
            name: name,
            host: host,
            port: port,
            remoteAETitle: calledAET,
            localAETitle: callingAET.isEmpty ? "DICOMSTUDIO" : callingAET
        )

        let storage = ServerProfileStorageService()
        try? storage.save(savedServerProfiles)

        // Reset form
        editingServerID = nil
        newServerName = ""
        newServerHost = ""
        newServerPort = "11112"
        newServerCalledAET = ""
        newServerCallingAET = "DICOMSTUDIO"
        showEditServerSheet = false

        // Re-apply if this was the selected server
        if selectedSavedServerID == editID {
            applySavedServer(id: editID)
        }
    }

    /// Resets network parameters to defaults when switching to manual mode.
    public func resetToManualInput() {
        selectedSavedServerID = nil
        // Reload defaults from parameter definitions
        parameterValues.removeAll()
        for def in parameterDefinitions where !def.defaultValue.isEmpty {
            parameterValues.append(CLIParameterValue(parameterID: def.id, stringValue: def.defaultValue))
        }
        service.setParameterValues(parameterValues)
        rebuildCommandPreview()
    }

    // MARK: - 16.3 Parameter Configuration

    /// Sets parameter definitions for the selected tool.
    public func setParameterDefinitions(_ defs: [CLIParameterDefinition]) {
        parameterDefinitions = defs
        service.setParameterDefinitions(defs)
    }

    /// Updates a single parameter value.
    public func updateParameterValue(parameterID: String, value: String) {
        if let idx = parameterValues.firstIndex(where: { $0.parameterID == parameterID }) {
            parameterValues[idx].stringValue = value
        } else {
            parameterValues.append(CLIParameterValue(parameterID: parameterID, stringValue: value))
        }
        // When the WADO protocol tab switches, rewrite the Base URL suffix so the
        // field always shows the correct servlet path (/rs for WADO-RS, /wado for WADO-URI).
        if parameterID == "wado-protocol", selectedToolID == "dicom-wado" {
            let currentURL = paramValue("url")
            if !currentURL.isEmpty {
                let adjusted = Self.adjustWADOBaseURL(currentURL, forProtocol: value)
                updateParameterValueSilent(parameterID: "url", value: adjusted)
            }
        }
        service.setParameterValues(parameterValues)
        rebuildCommandPreview()
    }

    /// Rewrites the trailing path segment of a WADO base URL to match the selected protocol.
    ///
    /// Replaces a trailing `/rs` or `/wado` segment with the correct one for the protocol,
    /// or appends the suffix when no endpoint segment is present. Preserves trailing slashes.
    ///
    /// Exception — dcm4chee2-style root `/wado` URLs (single non-empty path segment):
    /// these are fixed legacy endpoints and are returned unchanged regardless of the
    /// selected protocol, since dcm4chee2 has no sibling `/rs` servlet.
    static func adjustWADOBaseURL(_ rawURL: String, forProtocol newProtocol: String) -> String {
        guard var components = URLComponents(string: rawURL) else { return rawURL }
        var segments = components.path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        let newSuffix = newProtocol == "wado-uri" ? "wado" : "rs"
        if let lastIdx = segments.lastIndex(where: { !$0.isEmpty }) {
            let last = segments[lastIdx].lowercased()
            let nonEmptyCount = segments.filter { !$0.isEmpty }.count
            if last == "rs" || (last == "wado" && nonEmptyCount > 1) {
                // Replace existing endpoint segment (dcm4chee5-style: .../aets/AET/rs or .../wado)
                segments[lastIdx] = newSuffix
            } else if last != "wado" {
                // No endpoint suffix yet — append
                segments.insert(newSuffix, at: lastIdx + 1)
            }
            // else: single-segment /wado (dcm4chee2 root endpoint) — leave unchanged
        } else {
            segments.append(newSuffix)
        }
        components.path = segments.joined(separator: "/")
        return components.url?.absoluteString ?? rawURL
    }

    /// Silently updates a parameter value without rebuilding the command preview.
    /// Used when batch-setting multiple defaults at tool selection time.
    private func updateParameterValueSilent(parameterID: String, value: String) {
        if let idx = parameterValues.firstIndex(where: { $0.parameterID == parameterID }) {
            parameterValues[idx].stringValue = value
        } else {
            parameterValues.append(CLIParameterValue(parameterID: parameterID, stringValue: value))
        }
    }

    /// Stores a security-scoped URL for the given parameter ID and updates the parameter value.
    public func setSecurityScopedURL(_ url: URL, forParameterID parameterID: String) {
        securityScopedURLs[parameterID] = url
        updateParameterValue(parameterID: parameterID, value: url.path)
    }

    /// Reads file data from a path, handling security-scoped resource access if needed.
    ///
    /// When the security-scoped URL for `parameterID` is a directory (e.g. the user
    /// browsed for a folder), the scope is started on the directory and the individual
    /// file at `path` is read within that scope.
    public func readFileData(at path: String, parameterID: String = "files") throws -> Data {
        if let scopedURL = securityScopedURLs[parameterID] {
            let accessing = scopedURL.startAccessingSecurityScopedResource()
            defer {
                if accessing { scopedURL.stopAccessingSecurityScopedResource() }
            }
            // If the scoped URL is a directory or differs from the target path,
            // read the actual file at `path` (which is covered by the directory scope).
            let fileURL = URL(fileURLWithPath: path)
            if scopedURL.path == path {
                return try Data(contentsOf: scopedURL)
            } else {
                return try Data(contentsOf: fileURL)
            }
        }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    /// Resolves the output directory for retrieved files.
    /// If the user hasn't set a path (or left the default "."),
    /// falls back to ~/Downloads/DICOMStudio (entitlement-allowed).
    private func resolvedOutputDir(_ rawOutput: String) -> String {
        if rawOutput == "." || rawOutput.isEmpty {
            if let scopedURL = securityScopedURLs["output"] {
                return scopedURL.path
            }
            // Use ~/Downloads/DICOMStudio as the default (sandbox entitlement: downloads.read-write)
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
            let defaultDir = downloads.appendingPathComponent("DICOMStudio")
            try? FileManager.default.createDirectory(at: defaultDir, withIntermediateDirectories: true)
            return defaultDir.path
        }
        return rawOutput
    }

    /// Writes received DICOM data to disk in the specified output directory.
    ///
    /// The raw dataset bytes delivered by C-STORE / C-GET sub-operations lack the
    /// Part 10 header (128-byte preamble + "DICM" magic + File Meta Information).
    /// This function wraps them in a proper Part 10 container before saving so that
    /// all conformant DICOM readers can open the resulting file directly.
    ///
    /// - Parameters:
    ///   - data: The raw DICOM dataset bytes (no Part 10 header).
    ///   - sopInstanceUID: The SOP Instance UID (used as the filename).
    ///   - sopClassUID: The SOP Class UID for the File Meta Information.
    ///   - transferSyntaxUID: The transfer syntax the dataset is encoded in.
    ///   - studyUID: The Study Instance UID (for hierarchical organisation).
    ///   - seriesUID: Optional Series Instance UID (for hierarchical organisation).
    ///   - outputDir: The base output directory path.
    ///   - hierarchical: If true, organises as `<studyUID>/<seriesUID>/<sopInstanceUID>.dcm`.
    /// - Returns: The full path where the file was written.
    @discardableResult
    public func writeReceivedDICOMFile(
        data: Data,
        sopInstanceUID: String,
        sopClassUID: String = "1.2.840.10008.5.1.4.1.1.7",
        transferSyntaxUID: String = "1.2.840.10008.1.2.1",
        studyUID: String,
        seriesUID: String? = nil,
        outputDir: String,
        hierarchical: Bool
    ) throws -> String {
        let fm = FileManager.default

        // Build destination directory
        var dirURL: URL
        var accessing = false
        if let scopedURL = securityScopedURLs["output"] {
            accessing = scopedURL.startAccessingSecurityScopedResource()
            dirURL = scopedURL
        } else {
            dirURL = URL(fileURLWithPath: outputDir)
        }
        defer {
            if accessing {
                securityScopedURLs["output"]?.stopAccessingSecurityScopedResource()
            }
        }

        if hierarchical {
            dirURL = dirURL.appendingPathComponent(studyUID)
            // For a study-level C-GET the caller has no series UID; recover it from the
            // received dataset so --hierarchical doesn't collapse to studyUID/ only.
            // Only raw C-GET datasets are scanned — a Part 10 blob (WADO-RS, DICM prefix)
            // is left to the flat/study layout. Falls back to no series subdir on failure.
            var effectiveSeriesUID = seriesUID
            if (effectiveSeriesUID == nil || effectiveSeriesUID?.isEmpty == true),
               !(data.count >= 132 && data[128] == 0x44 && data[129] == 0x49 && data[130] == 0x43 && data[131] == 0x4D) {
                effectiveSeriesUID = extractSeriesUID(fromDataSet: data, transferSyntaxUID: transferSyntaxUID)
            }
            if let series = effectiveSeriesUID, !series.isEmpty {
                dirURL = dirURL.appendingPathComponent(series)
            }
        }

        try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)

        let filename = "\(sopInstanceUID).dcm"
        let fileURL = dirURL.appendingPathComponent(filename)

        // If the data already has a DICM prefix it is a complete Part 10 file
        // (e.g. from WADO-RS). Write it as-is to avoid double-wrapping.
        let fileData: Data
        if data.count >= 132,
           data[128] == 0x44, data[129] == 0x49, data[130] == 0x43, data[131] == 0x4D {
            fileData = data
        } else {
            fileData = part10Wrap(
                dataset: data,
                sopClassUID: sopClassUID,
                sopInstanceUID: sopInstanceUID,
                transferSyntaxUID: transferSyntaxUID
            )
        }
        try fileData.write(to: fileURL, options: .atomic)

        return fileURL.path
    }

    /// Writes arbitrary data to a file in the output directory, handling security-scoped access.
    ///
    /// Unlike `writeReceivedDICOMFile` (which wraps DICOM datasets in Part 10 containers),
    /// this writes raw data as-is — suitable for rendered images, JSON exports, etc.
    ///
    /// - Parameters:
    ///   - data: The data to write.
    ///   - filename: The filename (including extension) for the output file.
    ///   - outputDir: The resolved output directory path.
    /// - Returns: The full path where the file was written.
    @discardableResult
    public func writeOutputFile(data: Data, filename: String, outputDir: String) throws -> String {
        let fm = FileManager.default
        var dirURL: URL
        var accessing = false

        if let scopedURL = securityScopedURLs["output"] {
            accessing = scopedURL.startAccessingSecurityScopedResource()
            dirURL = scopedURL
        } else {
            dirURL = URL(fileURLWithPath: outputDir)
        }
        defer {
            if accessing {
                securityScopedURLs["output"]?.stopAccessingSecurityScopedResource()
            }
        }

        try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
        let fileURL = dirURL.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)
        return fileURL.path
    }

    /// Checks whether all required parameters are satisfied.
    public var isCommandValid: Bool {
        CommandBuilderHelpers.validateRequired(
            parameterValues: parameterValues,
            parameterDefinitions: parameterDefinitions
        )
    }

    /// Returns visible parameters based on experience mode and conditional visibility rules.
    public func visibleParameters() -> [CLIParameterDefinition] {
        let base: [CLIParameterDefinition]
        switch experienceMode {
        case .beginner:
            base = parameterDefinitions.filter { !$0.isAdvanced }
        case .advanced:
            base = parameterDefinitions
        }
        return base.filter { satisfiesVisibility($0) }
    }

    /// Advanced parameters that are kept out of the main grid in Beginner mode so
    /// they can be shown in a collapsible "Advanced options" section — this keeps
    /// every available flag reachable in the UI without cluttering the default
    /// view. Empty in Advanced mode, where all parameters already appear.
    public func advancedParameters() -> [CLIParameterDefinition] {
        guard experienceMode == .beginner else { return [] }
        return parameterDefinitions.filter { $0.isAdvanced && satisfiesVisibility($0) }
    }

    /// Evaluates a parameter's `visibleWhen` + `visibleWhenAll` conditions against the
    /// current values. Shares the predicate with `buildCommand()` / `validateRequired()`
    /// so the rendered form, the command preview, and the Run button never disagree.
    private func satisfiesVisibility(_ param: CLIParameterDefinition) -> Bool {
        CommandBuilderHelpers.isVisible(
            param, parameterValues: parameterValues, parameterDefinitions: parameterDefinitions)
    }

    // MARK: - 16.4 File Drop Zone

    /// Adds an input file.
    public func addInputFile(_ file: CLIFileEntry) {
        inputFiles.append(file)
        service.addInputFile(file)
        fileDropState = .selected
        service.setFileDropState(.selected)
        rebuildCommandPreview()
    }

    /// Removes an input file by ID.
    public func removeInputFile(id: UUID) {
        inputFiles.removeAll { $0.id == id }
        service.removeInputFile(id: id)
        fileDropState = inputFiles.isEmpty ? .empty : .selected
        service.setFileDropState(fileDropState)
        rebuildCommandPreview()
    }

    /// Updates the file drop state (e.g., for drag hover).
    public func updateFileDropState(_ state: CLIFileDropState) {
        fileDropState = state
        service.setFileDropState(state)
    }

    /// Updates the output path.
    public func updateOutputPath(_ path: String) {
        outputPath = path
        service.setOutputPath(path)
        rebuildCommandPreview()
    }

    // MARK: - 16.5 Console

    /// Rebuilds the command preview based on current tool and parameter state.
    public func rebuildCommandPreview() {
        guard let tool = selectedTool() else {
            commandPreview = ""
            service.setCommandPreview("")
            return
        }
        var values = parameterValues
        // dicom-send: picked/dropped files live in `inputFiles`, not in the `files`
        // field — mirror them into the positional list (deduplicated against the
        // typed paths) so the previewed command carries every file the executor
        // will send. `executeDicomSend` performs the identical union.
        if tool.name == "dicom-send", !inputFiles.isEmpty {
            var paths = CommandBuilderHelpers.splitMultiValue(
                values.first(where: { $0.parameterID == "files" })?.stringValue ?? "")
            for file in inputFiles where !paths.contains(file.path) {
                paths.append(file.path)
            }
            let joined = paths.joined(separator: ";")
            if let idx = values.firstIndex(where: { $0.parameterID == "files" }) {
                values[idx].stringValue = joined
            } else {
                values.append(CLIParameterValue(parameterID: "files", stringValue: joined))
            }
        }
        var preview = CommandBuilderHelpers.buildCommand(
            toolName: tool.name,
            parameterValues: values,
            parameterDefinitions: parameterDefinitions
        )
        // dicom-mwl `create` is an IN-APP-ONLY operation (N-CREATE via the shared
        // DICOMKit API): the real dicom-mwl CLI registers only the query
        // subcommand, so a `dicom-mwl create …` line must never present as a
        // paste-runnable command. Render the preview fully commented out behind
        // an explicit banner — pasting it into a terminal is a no-op.
        if tool.name == "dicom-mwl" {
            let rawOp = values.first(where: { $0.parameterID == "operation" })?.stringValue ?? ""
            let effectiveOp = rawOp.isEmpty
                ? (parameterDefinitions.first(where: { $0.id == "operation" })?.defaultValue ?? "")
                : rawOp
            if effectiveOp == "create" {
                preview = "# in-app only — dicom-mwl has no create subcommand\n# " + preview
            }
        }
        // #45: the app-only "basic" authentication mode executes HTTP Basic via
        // the shared DICOMweb client, but the dicom-wado CLI has no basic-auth
        // flags (--token is Bearer-only) — the state is not CLI-representable,
        // so the preview must not present as paste-runnable.
        if ["dicom-qido", "dicom-wado", "dicom-stow", "dicom-ups"].contains(tool.name) {
            let rawAuth = values.first(where: { $0.parameterID == "auth" })?.stringValue ?? ""
            let effectiveAuth = rawAuth.isEmpty
                ? (parameterDefinitions.first(where: { $0.id == "auth" })?.defaultValue ?? "")
                : rawAuth
            if effectiveAuth == "basic" {
                preview = "# in-app only — basic auth is not CLI-representable (dicom-wado --token is Bearer-only)\n# " + preview
            }
        }
        commandPreview = preview
        service.setCommandPreview(preview)
    }

    /// Returns syntax tokens for the current command preview.
    public func commandTokens() -> [CLISyntaxToken] {
        CommandBuilderHelpers.tokenize(commandPreview)
    }

    /// Clears the console output.
    public func clearConsoleOutput() {
        consoleOutput = ""
        service.setConsoleOutput("")
        consoleStatus = .idle
        service.setConsoleStatus(.idle)
    }

    /// Opens retrieved files from the last retrieve/QR operation in the viewer.
    ///
    /// If multiple files were retrieved, loads them as a navigable series via
    /// `onOpenSeriesInViewer`. Falls back to opening just the first file via
    /// `onOpenInViewer` when the series callback is not set.
    public func openRetrievedFileInViewer() {
        guard !lastRetrievedFiles.isEmpty else { return }
        if let seriesCallback = onOpenSeriesInViewer, lastRetrievedFiles.count > 1 {
            seriesCallback(lastRetrievedFiles, 0, lastRetrievedOutputURL)
        } else {
            onOpenInViewer?(lastRetrievedFiles[0], lastRetrievedOutputURL)
        }
    }

    // MARK: - dicom-json Execution

    /// Converts between DICOM and JSON (DICOM JSON Model / DICOMweb JSON) in-process,
    /// mirroring the dicom-json CLI using DICOMWeb's DICOMJSONEncoder/DICOMJSONDecoder.
    private func executeDicomJSON() async {
        let inputPath = paramValue("inputPath")
        guard !inputPath.isEmpty else {
            appendConsoleOutput("Error: Input file path is required.\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-json", command: commandPreview, exitCode: 1, output: "Missing input path")
            return
        }

        await runDataExchangeTool(format: .json, toolName: "dicom-json", inputPath: inputPath)
    }

    // MARK: - dicom-xml Execution

    /// Converts between DICOM and the DICOM Native XML Model (PS3.19) in-process.
    ///
    /// Mirrors the `dicom-xml` CLI: DICOM → XML via `DICOMXMLEncoder` and
    /// XML → DICOM (`--reverse`) via `DICOMXMLDecoder`. Supports --pretty,
    /// --no-keywords, --include-empty, --inline-threshold, --bulk-data-url,
    /// --metadata-only, --filter-tag and --verbose.
    private func executeDicomXML() async {
        let inputPath = paramValue("input")
        guard !inputPath.isEmpty else {
            appendConsoleOutput("Error: Input file path is required.\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-xml", command: commandPreview, exitCode: 1, output: "Missing input path")
            return
        }

        await runDataExchangeTool(format: .xml, toolName: "dicom-xml", inputPath: inputPath)
    }

    /// Shared executor for dicom-json / dicom-xml — the entire pipeline runs in
    /// the SHARED `DataExchangeWorkflow` (DICOMWeb), the same code the two CLIs
    /// call, so behavior and console text cannot drift. CLI-canonical behavior:
    /// output ALWAYS goes to a file (default `<input>.json`/`.xml`/`.dcm`, never
    /// printed to the console), reverse works without --output, and a
    /// non-verbose success run prints nothing.
    private func runDataExchangeTool(
        format: DataExchangeWorkflow.Format, toolName: String, inputPath: String
    ) async {
        let reverse = paramValue("reverse") == "true"
        let verbose = paramValue("verbose") == "true"
        let noSortKeys = format == .json && paramValue("no-sort-keys") == "true"
        let noKeywords = format == .xml && paramValue("no-keywords") == "true"

        // dicom-json / dicom-xml check the input first (ArgumentParser ValidationError, exit 64).
        guard FileManager.default.fileExists(atPath: (securityScopedURLs["inputPath"] ?? securityScopedURLs["input"])?.path ?? inputPath) else {
            appendConsoleOutput("Error: File not found: \(inputPath)\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: toolName, command: commandPreview, exitCode: 64, output: "File not found")
            return
        }
        // Deprecated options in use: the CLIs' one-line stderr notes (P-JSON-NO-SORT-KEYS,
        // P-XML-NO-KEYWORDS), same text.
        for note in Self.dataExchangeDeprecationNotes(toolName: toolName, noSortKeys: noSortKeys, noKeywords: noKeywords) {
            appendConsoleOutput(note + "\n")
        }

        let options = DataExchangeWorkflow.Options(
            reverse: reverse,
            pretty: paramValue("pretty") == "true",
            // PS3.18 F.2.5 / PS3.19 Table A.1.5-2: empty attributes are kept unless
            // --no-include-empty (the toggle off) — the CLI default (D114).
            includeEmpty: paramValue("include-empty") != "false",
            inlineThreshold: Int(paramValue("inline-threshold")) ?? 1024,
            bulkDataURL: paramValue("bulk-data-url").isEmpty ? nil : paramValue("bulk-data-url"),
            metadataOnly: paramValue("metadata-only") == "true",
            // --filter-tag is a repeatable array option in the CLI (one value per
            // flag occurrence); split hex-tag aware so `0010,0010` survives, then
            // accept the (GGGG,EEEE) and GGGGEEEE forms as the CLIs do.
            filterTags: Self.normalizedDataExchangeFilterTags(CommandBuilderHelpers.splitMultiValue(paramValue("filter-tag"))),
            verbose: verbose,
            sortKeys: !noSortKeys,        // json only
            includeKeywords: !noKeywords  // xml only
        )

        // CLI-canonical output path (used in the header + preview); the sandbox
        // may redirect the actual write below, with a note.
        let outputPath = paramValue("output").isEmpty
            ? DataExchangeWorkflow.defaultOutputPath(input: inputPath, reverse: reverse, format: format)
            : paramValue("output")

        // Sandbox access. (The input param id doubles as the scoped-URL key:
        // "inputPath" for dicom-json, "input" for dicom-xml.)
        let inputScopedURL = securityScopedURLs["inputPath"] ?? securityScopedURLs["input"]
        let outputScopedURL = securityScopedURLs["output"]
        let accessingInput = inputScopedURL?.startAccessingSecurityScopedResource() ?? false
        let accessingOutput = outputScopedURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if accessingInput { inputScopedURL?.stopAccessingSecurityScopedResource() }
            if accessingOutput { outputScopedURL?.stopAccessingSecurityScopedResource() }
        }
        let inputURL = inputScopedURL ?? URL(fileURLWithPath: inputPath)
        // Sandbox/TCC-resilient output: prefer the picker's scoped URL; else probe the
        // typed path and, if it's not writable (TCC), redirect to ~/Downloads/DICOMStudio.
        let (outputURL, outRedirectNote) = OutputAccess.resolveWritableURL(
            forPath: outputPath, scopedURL: outputScopedURL, subfolder: toolName)
        if let note = outRedirectNote { appendConsoleOutput(note + "\n") }

        for line in DataExchangeWorkflow.headerLines(
            input: inputPath, output: outputPath, reverse: reverse, format: format, verbose: verbose) {
            appendConsoleOutput(line + "\n")
        }

        let (output, exitCode) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
            do {
                let readStart = Date()
                let inputData = try Data(contentsOf: inputURL)
                let readSeconds = Date().timeIntervalSince(readStart)

                let result = reverse
                    ? try DataExchangeWorkflow.decode(textData: inputData, format: format, options: options, readSeconds: readSeconds)
                    : try DataExchangeWorkflow.encode(dicomData: inputData, format: format, options: options, readSeconds: readSeconds)

                // Warnings (an unresolved BulkData reference on --reverse) carry the
                // CLI's stderr prefix "dicom-json: " / "dicom-xml: ".
                var log = result.console.map { ($0.hasPrefix("Warning:") ? toolName + ": " + $0 : $0) + "\n" }.joined()

                let writeStart = Date()
                try result.data.write(to: outputURL)
                let writeSeconds = Date().timeIntervalSince(writeStart)
                let writeLines = reverse
                    ? DataExchangeWorkflow.reverseWriteLine(size: Int64(result.data.count), seconds: writeSeconds, verbose: verbose)
                    : DataExchangeWorkflow.forwardWriteLine(seconds: writeSeconds, verbose: verbose)
                log += writeLines.map { $0 + "\n" }.joined()

                log += DataExchangeWorkflow.completionLines(
                    outputSize: Int64(result.data.count), verbose: verbose).map { $0 + "\n" }.joined()
                return (log, 0)
            } catch let e as DataExchangeWorkflow.WorkflowError {
                // The CLIs rethrow a WorkflowError as ArgumentParser's ValidationError (exit 64).
                return ("Error: \(e.errorDescription ?? "\(e)")\n", 64)
            } catch {
                return ("Error: \(error.localizedDescription)\n", 1)
            }
        }.value

        appendConsoleOutput(output)
        addToHistory(toolName: toolName, command: commandPreview, exitCode: exitCode, output: output)
        consoleStatus = exitCode == 0 ? .success : .error
        service.setConsoleStatus(exitCode == 0 ? .success : .error)
    }

    /// The stderr notes `dicom-json` / `dicom-xml` print for a deprecated option in use
    /// (their `deprecationNotes`; P-JSON-NO-SORT-KEYS, P-XML-NO-KEYWORDS). The text is
    /// CLI-local (not in DICOMWeb's DataExchangeWorkflow), so it is kept identical here.
    nonisolated static func dataExchangeDeprecationNotes(toolName: String, noSortKeys: Bool, noKeywords: Bool) -> [String] {
        var notes: [String] = []
        if toolName == "dicom-json", noSortKeys {
            notes.append("dicom-json: warning: --no-sort-keys is deprecated and will be removed: PS3.18 2026a F.2.2 requires attribute objects in ascending tag order")
        }
        if toolName == "dicom-xml", noKeywords {
            notes.append("dicom-xml: warning: --no-keywords is deprecated and will be removed: PS3.19 2026a Table A.1.5-2 requires the keyword attribute for every PS3.6 Data Element")
        }
        return notes
    }

    /// `--filter-tag` forms of dicom-json / dicom-xml (`normalizedFilterTags`): the eight-character
    /// tag (the PS3.18 F.2.2 attribute name / PS3.19 Table A.1.5-2 `tag` form, e.g. `00100020`)
    /// and `(GGGG,EEEE)` besides the keyword and `GGGG,EEEE` forms the shared workflow resolves.
    nonisolated static func normalizedDataExchangeFilterTags(_ specs: [String]) -> [String] {
        specs.map { spec in
            var s = spec.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("("), s.hasSuffix(")") { s = String(s.dropFirst().dropLast()) }
            if s.count == 8, s.allSatisfy(\.isHexDigit) {
                return "\(s.prefix(4)),\(s.suffix(4))"
            }
            return s.contains(",") ? s : spec
        }
    }

// MARK: - dicom-uid Execution

/// Performs DICOM UID generation, validation, registry lookup, and in-file
/// regeneration in-process using DICOMCore `UIDGenerator`, DICOMDictionary
/// `UIDDictionary`, and DICOMKit `DICOMFile`. Mirrors the `dicom-uid` CLI
/// (subcommands: generate, validate, lookup, regenerate).
private func executeDicomUID() async {
    let subcommand = paramValue("subcommand").isEmpty ? "generate" : paramValue("subcommand")
    switch subcommand {
    case "validate":
        await executeDicomUIDValidate()
    case "lookup":
        await executeDicomUIDLookup()
    case "regenerate":
        await executeDicomUIDRegenerate()
    default:
        await executeDicomUIDGenerate()
    }
}

/// `dicom-uid generate` — create one or more fresh UIDs.
private func executeDicomUIDGenerate() async {
    let countStr = paramValue("count").isEmpty ? "1" : paramValue("count")
    let typeRaw = paramValue("type")
    let rootRaw = paramValue("root").trimmingCharacters(in: .whitespacesAndNewlines)
    let asJSON = paramValue("json") == "true"
    let uuid = paramValue("uuid") == "true"

    // dicom-uid generate's validate(): ArgumentParser ValidationError, exit 64.
    func refuse(_ message: String) {
        appendConsoleOutput("Error: \(message)\n")
        consoleStatus = .error; service.setConsoleStatus(.error)
        addToHistory(toolName: "dicom-uid", command: commandPreview, exitCode: 64, output: message)
    }
    guard let count = Int(countStr), count >= 1 else { return refuse("Count must be at least 1") }
    guard count <= 1000 else { return refuse("Count must not exceed 1000") }
    let typeIsGeneric = typeRaw.isEmpty || typeRaw.lowercased() == "generic"
    if !typeIsGeneric, !["study", "series", "instance", "sop"].contains(typeRaw.lowercased()) {
        return refuse("Invalid type '\(typeRaw)'. Valid types: study, series, instance (alias sop), generic")
    }
    // The form's picker always carries a --type value; only a non-generic one conflicts
    // with --uuid, as on the CLI (where generic is the absent option).
    if uuid && (!rootRaw.isEmpty || !typeIsGeneric) {
        return refuse("--uuid makes 2.25.<UUID> UIDs (PS3.5 B.2) and cannot be combined with --root or --type")
    }
    if !rootRaw.isEmpty {
        let problems = Self.uidRootProblems(root: rootRaw, typed: !typeIsGeneric)
        if !problems.isEmpty { return refuse(problems.joined(separator: "\n")) }
    }
    let type: String? = typeIsGeneric ? nil : typeRaw
    let root: String? = rootRaw.isEmpty ? nil : rootRaw

    let (output, exitCode) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
        // Generate via the shared DICOMKit UIDManager (or the shared DICOMCore UUID
        // derived UID of PS3.5 B.2) and render via the shared UIDConsole — the exact
        // code path the CLI prints from.
        let uids = uuid
            ? (0..<count).map { _ in UIDGenerator.uuidDerivedUID().value }
            : UIDManager().generateUIDs(count: count, root: root, type: type)

        if asJSON {
            do {
                return (try UIDConsole.generatedJSON(uids: uids), 0)
            } catch {
                return ("Error: \(error.localizedDescription)\n", 1)
            }
        } else {
            return (UIDConsole.generatedList(uids: uids), 0)
        }
    }.value

    appendConsoleOutput(output)
    addToHistory(toolName: "dicom-uid", command: commandPreview, exitCode: exitCode, output: output)
    consoleStatus = exitCode == 0 ? .success : .error
    service.setConsoleStatus(exitCode == 0 ? .success : .error)
}

/// `dicom-uid validate` — validate UIDs from arguments and/or a DICOM file
/// against PS3.5 Section 9 rules.
private func executeDicomUIDValidate() async {
    // <uids> is a variadic positional list in the CLI; split with the shared
    // helper so the values match the positional tokens emitted in the
    // command preview.
    let argUIDs = CommandBuilderHelpers.splitMultiValue(paramValue("uids"))
    let filePath = paramValue("file")
    let checkRegistry = paramValue("check-registry") == "true"
    let asJSON = paramValue("json") == "true"

    guard !argUIDs.isEmpty || !filePath.isEmpty else {
        appendConsoleOutput("Error: Provide UIDs as arguments or use --file to validate a DICOM file\n")
        consoleStatus = .error; service.setConsoleStatus(.error)
        addToHistory(toolName: "dicom-uid", command: commandPreview, exitCode: 64, output: "No UIDs or file")
        return
    }

    let inputScopedURL = securityScopedURLs["file"]
    let accessing = inputScopedURL?.startAccessingSecurityScopedResource() ?? false
    defer { if accessing { inputScopedURL?.stopAccessingSecurityScopedResource() } }
    let fileURL: URL? = filePath.isEmpty ? nil : (inputScopedURL ?? URL(fileURLWithPath: filePath))

    let (output, exitCode) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
        // Validate via the shared DICOMKit UIDManager (PS3.5 Section 9 rules).
        // (Qualify the result type: DICOMStudio has its own UIDValidationResult.)
        let manager = UIDManager()
        var results: [DICOMKit.UIDValidationResult] = []
        for uid in argUIDs { results.append(manager.validateUID(uid)) }

        if let url = fileURL {
            do {
                // Gather + validate every UI element via the shared
                // UIDManager.validateFileUIDs — the exact call the CLI makes.
                results.append(contentsOf: try manager.validateFileUIDs(path: url.path))
            } catch {
                return ("Error: \(error.localizedDescription)\n", 1)
            }
        }

        if asJSON {
            do {
                return (try UIDConsole.validationJSON(results: results), 0)
            } catch {
                return ("Error: \(error.localizedDescription)\n", 1)
            }
        } else {
            let (text, allValid) = UIDConsole.validationText(results: results, checkRegistry: checkRegistry)
            return (text, allValid ? 0 : 1)
        }
    }.value

    appendConsoleOutput(output)
    addToHistory(toolName: "dicom-uid", command: commandPreview, exitCode: exitCode, output: output)
    consoleStatus = exitCode == 0 ? .success : .error
    service.setConsoleStatus(exitCode == 0 ? .success : .error)
}

/// `dicom-uid lookup` — look up a single UID, or list/search registry entries.
private func executeDicomUIDLookup() async {
    let uid = paramValue("lookup-uid").trimmingCharacters(in: .whitespacesAndNewlines)
    let listAll = paramValue("list-all") == "true"
    let typeFilter = paramValue("lookup-type")
    let search = paramValue("search").trimmingCharacters(in: .whitespacesAndNewlines)
    let asJSON = paramValue("json") == "true"

    guard !uid.isEmpty || listAll || !search.isEmpty else {
        appendConsoleOutput("Error: Provide a UID, use --list-all, or --search to find UIDs\n")
        consoleStatus = .error; service.setConsoleStatus(.error)
        addToHistory(toolName: "dicom-uid", command: commandPreview, exitCode: 64, output: "No lookup criteria")
        return
    }

    let (output, exitCode) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
        // P-UID-TYPE (as dicom-uid): text and the JSON `uidType` key carry the PS3.6 Table A-1
        // UID Type (UIDManager.tableA1UIDType); the JSON `type` key keeps the legacy wording.
        if !uid.isEmpty {
            guard let entry = UIDDictionary.lookup(uid: uid) else {
                return (UIDConsole.lookupNotFoundLine(uid: uid) + "\n", 1)
            }
            let uidType = UIDManager.tableA1UIDType(of: entry)
            if asJSON {
                do {
                    return (try UIDConsole.lookupEntryJSON(
                        uid: uid, name: entry.name,
                        type: UIDManager.uidTypeDescription(entry.type), uidType: uidType), 0)
                } catch {
                    return ("Error: \(error.localizedDescription)\n", 1)
                }
            } else {
                return (UIDConsole.lookupEntryText(uid: uid, name: entry.name, type: uidType), 0)
            }
        }

        // List / search. The type filter is the shared engine list of PS3.6 Table A-1 UID
        // Types (UIDConsole.entries(forTypeFilter:)), the exact call the CLI makes.
        var entries = UIDDictionary.allEntries
        if !typeFilter.isEmpty {
            guard let filtered = UIDConsole.entries(forTypeFilter: typeFilter) else {
                return (UIDConsole.unknownTypeFilterLine(typeFilter) + "\n", 1)
            }
            entries = filtered
        }
        if !search.isEmpty {
            let lower = search.lowercased()
            entries = entries.filter {
                $0.name.lowercased().contains(lower) || $0.uid.lowercased().contains(lower)
            }
        }
        if entries.isEmpty {
            return (UIDConsole.noMatchesLine() + "\n", 1)
        }
        if asJSON {
            do {
                let rows = entries.map {
                    (uid: $0.uid, name: $0.name, type: UIDManager.uidTypeDescription($0.type),
                     uidType: UIDManager.tableA1UIDType(of: $0))
                }
                return (try UIDConsole.listingJSON(entries: rows), 0)
            } catch {
                return ("Error: \(error.localizedDescription)\n", 1)
            }
        } else {
            var lines = entries.map { UIDConsole.listingLine(uid: $0.uid, name: $0.name, type: UIDManager.tableA1UIDType(of: $0)) }
            lines.append(UIDConsole.listingSummary(count: entries.count))
            return (lines.joined(separator: "\n") + "\n", 0)
        }
    }.value

    appendConsoleOutput(output)
    addToHistory(toolName: "dicom-uid", command: commandPreview, exitCode: exitCode, output: output)
    consoleStatus = exitCode == 0 ? .success : .error
    service.setConsoleStatus(exitCode == 0 ? .success : .error)
}

/// `dicom-uid regenerate` — replace instance UIDs in a DICOM file with fresh
/// ones (preserving well-known UIDs). Single-file subset of the CLI.
private func executeDicomUIDRegenerate() async {
    // <inputs> is a variadic positional list in the CLI — split with the shared
    // helper so multiple files (and the cross-file UID remapping) work like the
    // CLI. A picked scoped URL is unioned with any typed paths.
    var inputPaths = CommandBuilderHelpers.splitMultiValue(paramValue("inputPath"))
    let inputScopedURL = securityScopedURLs["inputPath"]
    if let scoped = inputScopedURL, !inputPaths.contains(scoped.path) {
        if inputPaths.count <= 1 { inputPaths = [scoped.path] }
        else { inputPaths.append(scoped.path) }
    }
    guard !inputPaths.isEmpty else {
        appendConsoleOutput("Error: At least one input file is required\n")
        consoleStatus = .error; service.setConsoleStatus(.error)
        addToHistory(toolName: "dicom-uid", command: commandPreview, exitCode: 64, output: "Missing input path")
        return
    }
    let outputPath = paramValue("output").trimmingCharacters(in: .whitespacesAndNewlines)
    let rootRaw = paramValue("root").trimmingCharacters(in: .whitespacesAndNewlines)
    if !rootRaw.isEmpty {
        // dicom-uid regenerate's validate(): a --root outside PS3.5 9.1 is a usage error (exit 64).
        let problems = Self.uidRootProblems(root: rootRaw, typed: false)
        if !problems.isEmpty {
            let message = problems.joined(separator: "\n")
            appendConsoleOutput("Error: \(message)\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-uid", command: commandPreview, exitCode: 64, output: message)
            return
        }
    }
    let root: String? = rootRaw.isEmpty ? nil : rootRaw
    let maintainRelationships = paramValue("maintain-relationships") == "true"
    let dryRun = paramValue("dry-run") == "true"
    let verbose = paramValue("verbose") == "true"
    let exportMap = paramValue("export-map").trimmingCharacters(in: .whitespacesAndNewlines)

    let inAccessing = inputScopedURL?.startAccessingSecurityScopedResource() ?? false
    defer { if inAccessing { inputScopedURL?.stopAccessingSecurityScopedResource() } }

    let outputScopedURL = securityScopedURLs["output"]
    let outAccessing = outputScopedURL?.startAccessingSecurityScopedResource() ?? false
    defer { if outAccessing { outputScopedURL?.stopAccessingSecurityScopedResource() } }

    let mapScopedURL = securityScopedURLs["export-map"]
    let mapAccessing = mapScopedURL?.startAccessingSecurityScopedResource() ?? false
    defer { if mapAccessing { mapScopedURL?.stopAccessingSecurityScopedResource() } }

    let effectiveOutput = outputScopedURL?.path ?? (outputPath.isEmpty ? nil : outputPath)
    let resolvedMapPath: String? = mapScopedURL?.path ?? (exportMap.isEmpty ? nil : exportMap)

    let (output, exitCode) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
        // Mirrors the CLI's regenerate loop (dicom-uid main.swift): shared
        // globalMappings across files, output treated as a directory for
        // multiple inputs, warnings (not errors) for missing files.
        var globalMappings: [String: String] = [:]
        var allMappings: [UIDMapping] = []
        var lines: [String] = []

        let isMultipleFiles = inputPaths.count > 1
        var outputDir: String?
        if isMultipleFiles, let out = effectiveOutput {
            outputDir = out
            if !dryRun {
                do {
                    try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
                } catch {
                    return ("Error: \(error.localizedDescription)\n", 1)
                }
            }
        }

        for inputPath in inputPaths {
            guard FileManager.default.fileExists(atPath: inputPath) else {
                lines.append(UIDConsole.fileNotFoundWarning(path: inputPath))
                continue
            }
            let fileOutputPath: String?
            if let dir = outputDir {
                let filename = URL(fileURLWithPath: inputPath).lastPathComponent
                fileOutputPath = (dir as NSString).appendingPathComponent(filename)
            } else {
                fileOutputPath = effectiveOutput
            }

            if verbose { lines.append(UIDConsole.processingLine(path: inputPath)) }

            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: inputPath))

                if dryRun {
                    // Shared preview (DICOMKit UIDManager) → byte-identical to the
                    // CLI's dry-run STDOUT (the "Dry run complete" line is CLI
                    // stderr chrome and deliberately not mirrored here).
                    let file = try DICOMFile.read(from: data, force: false)
                    lines.append(contentsOf: UIDManager.regenerationPreviewLines(for: file.dataSet))
                    continue
                }

                // Regenerate via the shared engine; multi-file runs always thread
                // the shared mapping (the CLI forces maintainRelationships for
                // multiple inputs).
                let (newData, mappings) = try UIDManager().regenerateData(
                    data, root: root,
                    maintainRelationships: maintainRelationships || isMultipleFiles,
                    existingMappings: &globalMappings)
                allMappings.append(contentsOf: mappings)

                // Sandbox/TCC-resilient write (prefer scoped URL for a single
                // output; else fall back to ~/Downloads with a note).
                let writeRes = try OutputAccess.write(
                    newData, toPath: fileOutputPath ?? inputPath,
                    scopedURL: (isMultipleFiles ? nil : outputScopedURL), subfolder: "UIDRegenerate")

                if verbose {
                    for m in mappings {
                        lines.append(UIDConsole.mappingLine(tagName: m.tagName, oldUID: m.oldUID, newUID: m.newUID))
                    }
                }
                if let note = writeRes.note { lines.append(note) }
                lines.append(UIDConsole.wroteLine(path: writeRes.url.path, count: mappings.count))
            } catch {
                return (lines.joined(separator: "\n") + "\nError: \(error.localizedDescription)\n", 1)
            }
        }

        if let mapPath = resolvedMapPath, !dryRun {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let mapData = try encoder.encode(allMappings)
                let mapRes = try OutputAccess.write(mapData, toPath: mapPath,
                                                    scopedURL: mapScopedURL, subfolder: "UIDRegenerate")
                if let note = mapRes.note { lines.append(note) }
                lines.append(UIDConsole.mapExportedLine(path: mapRes.url.path))
            } catch {
                return (lines.joined(separator: "\n") + "\nError: \(error.localizedDescription)\n", 1)
            }
        }

        // No dry-run confirmation line here: the CLI prints
        // UIDConsole.dryRunCompleteLine() to STDERR (chrome), and the parity
        // contract is app console ≡ CLI stdout — the goldens pin this.

        return (lines.joined(separator: "\n") + "\n", 0)
    }.value

    appendConsoleOutput(output)
    addToHistory(toolName: "dicom-uid", command: commandPreview, exitCode: exitCode, output: output)
    consoleStatus = exitCode == 0 ? .success : .error
    service.setConsoleStatus(exitCode == 0 ? .success : .error)
}

/// PS3.5 9.1 checks for a dicom-uid `--root` value and the room it leaves for the generated
/// UID (dicom-uid's `UIDRootRule`, kept text-identical here; the rule is CLI-local until it is
/// lifted into DICOMKit). The longest suffix `UIDGenerator` appends is `.<µs timestamp>.<random
/// 0-999999>`, plus `.<1|2|3>` for a typed UID.
nonisolated static func uidRootProblems(root: String, typed: Bool) -> [String] {
    let timestampDigits = String(UInt64(Date().timeIntervalSince1970 * 1_000_000)).count
    let suffixLength = 1 + timestampDigits + 1 + 6 + (typed ? 2 : 0)
    var out: [String] = []
    let components = root.split(separator: ".", omittingEmptySubsequences: false)
    if root.isEmpty || components.contains(where: { $0.isEmpty }) {
        out.append("UID root '\(root)' has an empty component; components are separated by single \".\" characters (PS3.5 9.1)")
    }
    for component in components where !component.isEmpty {
        if !component.allSatisfy({ ("0"..."9").contains($0) }) {
            out.append("UID root component '\(component)' is not a number; only the digits 0-9 are allowed (PS3.5 9.1)")
        } else if component.count > 1 && component.hasPrefix("0") {
            out.append("UID root component '\(component)' has a leading zero; only a single-digit component may start with 0 (PS3.5 9.1)")
        }
    }
    let room = DICOMUniqueIdentifier.maximumLength - suffixLength
    if root.count > room {
        out.append("UID root is \(root.count) characters; generated UIDs add up to \(suffixLength) more and may not exceed \(DICOMUniqueIdentifier.maximumLength) (PS3.5 9.1), so the root may have at most \(room)")
    }
    return out
}

private func executeDicomDcmdir() async {
        let subcommand = paramValue("subcommand").isEmpty ? "create" : paramValue("subcommand")
        switch subcommand {
        case "create":   await executeDicomDcmdirCreate()
        case "validate": await executeDicomDcmdirValidate()
        case "dump":     await executeDicomDcmdirDump()
        case "update":   await executeDicomDcmdirUpdate()
        default:
            appendConsoleOutput("Error: Unknown subcommand '\(subcommand)'. Use create, validate, dump, or update.\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-dcmdir", command: commandPreview, exitCode: 1, output: "Unknown subcommand")
        }
    }

    // MARK: dicom-dcmdir create

    /// Mirrors `dicom-dcmdir create`: the same shared `DICOMDIRWorkflow` build (and `--copy-to`),
    /// the CLI's File-set ID default and refusal (PS3.10 8.1, 8.5; P-DCMDIR-FSID), its `--profile`
    /// check and deprecation note (PS3.11 identifiers only, D29) and its exit codes: ArgumentParser
    /// ValidationError 64, the File-set ID refusal and "no file could be indexed" 1 (D132).
    private func executeDicomDcmdirCreate() async {
        let inputDirectory = paramValue("inputDirectory")
        guard !inputDirectory.isEmpty else {
            appendConsoleOutput("Error: Missing expected argument '<input-directory>'\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-dcmdir", command: commandPreview, exitCode: 64, output: "Missing input directory")
            return
        }

        let outputArg = paramValue("output")
        let fileSetIDArg = paramValue("fileSetID")
        let profileStr = paramValue("profile").isEmpty ? "STD-GEN-CD" : paramValue("profile")
        let recursive = paramValue("recursive").isEmpty ? true : (paramValue("recursive") == "true")
        let strict = paramValue("strict") == "true"
        let copyToArg = paramValue("copyTo")
        let verbose = paramValue("createVerbose") == "true"

        let inputScopedURL = securityScopedURLs["inputDirectory"]
        let inputAccessing = inputScopedURL?.startAccessingSecurityScopedResource() ?? false
        defer { if inputAccessing { inputScopedURL?.stopAccessingSecurityScopedResource() } }
        let inputURL = inputScopedURL ?? URL(fileURLWithPath: inputDirectory)

        let outputScopedURL = securityScopedURLs["output"]
        let outputAccessing = outputScopedURL?.startAccessingSecurityScopedResource() ?? false
        defer { if outputAccessing { outputScopedURL?.stopAccessingSecurityScopedResource() } }

        let copyToScopedURL = securityScopedURLs["copyTo"]
        let copyToAccessing = copyToScopedURL?.startAccessingSecurityScopedResource() ?? false
        defer { if copyToAccessing { copyToScopedURL?.stopAccessingSecurityScopedResource() } }
        let copyRoot: URL? = copyToScopedURL ?? (copyToArg.isEmpty ? nil : URL(fileURLWithPath: copyToArg))

        // Resolve the OUTPUT to a DICOMDIR *file* path. When the user chose/typed a
        // folder (or a trailing-slash path), the DICOMDIR is written INSIDE it — writing
        // onto a directory path is what produced "the file … couldn't be saved in the
        // folder …". Default, as the CLI: a DICOMDIR in the --copy-to folder, else in the
        // input directory. (Scope is active.)
        let intendedOutputPath: String
        if !outputArg.isEmpty { intendedOutputPath = outputArg }
        else if let scoped = outputScopedURL { intendedOutputPath = scoped.path }
        else { intendedOutputPath = (copyRoot ?? inputURL).appendingPathComponent("DICOMDIR").path }
        let outputFilePath = DICOMDIRWorkflow.resolvedDICOMDIRPath(intendedOutputPath)

        let (output, exitCode): (String, Int) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
            var out = ""

            // The CLI's ValidationErrors (exit 64), in its order.
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDir) else {
                return ("Error: Input directory not found: \(inputDirectory)\n", 64)
            }
            guard isDir.boolValue else {
                return ("Error: Input path is not a directory: \(inputDirectory)\n", 64)
            }
            // The File IDs are relative to the DICOMDIR's folder (PS3.10 8.6): with --copy-to
            // the DICOMDIR goes in the root of the new File-set.
            if let copyRoot, URL(fileURLWithPath: outputFilePath).deletingLastPathComponent().standardizedFileURL.path
                != copyRoot.standardizedFileURL.path {
                return ("Error: With --copy-to the DICOMDIR is written in that folder (PS3.10 8.6); omit --output or use --output \(copyRoot.path)/DICOMDIR\n", 64)
            }

            // File-set ID (0004,1130): PS3.10 8.1 (0-16 characters) and 8.5 (A-Z, 0-9, _).
            // P-DCMDIR-FSID: a non-conformant --file-set-id is refused (exit 1), not written.
            let fsID: String
            if !fileSetIDArg.isEmpty {
                if let refusal = WorkshopFileSetRules.fileSetIDRefusal(fileSetIDArg) {
                    return ("Error: \(refusal)\n", 1)
                }
                fsID = fileSetIDArg
            } else {
                fsID = WorkshopFileSetRules.defaultFileSetID(fromDirectoryName: inputURL.lastPathComponent)
            }

            // --profile: a PS3.11 identifier (DICOMCore registry), the CLI's error text otherwise.
            guard let dicomProfile = DICOMDIRProfile(rawValue: profileStr) else {
                let standard = DICOMDIRProfile.allStandard.map(\.rawValue).joined(separator: ", ")
                return ("Error: Invalid profile: \(profileStr). Use a PS3.11 Application Profile identifier: \(standard), or STD-US-<ID|SC|CC>-<SF|MF>-<media>\n", 64)
            }
            // P-DCMDIR-PROFILE: a pre-2026-09-25 spelling still works, with the CLI's note
            // naming the PS3.11 identifier that is written.
            if let note = WorkshopFileSetRules.profileDeprecationNote(requested: profileStr, resolved: dicomProfile) {
                out += note + "\n"
            }

            if verbose {
                out += "Creating DICOMDIR...\n"
                out += "  Input directory: \(inputDirectory)\n"
                out += "  Output file: \(outputFilePath)\n"
                out += "  File-set ID: \(fsID)\n"
                out += "  Profile: \(dicomProfile.rawValue)\n"
                out += "  Recursive: \(recursive)\n\n"
            }

            // Build the DICOMDIR via the shared DICOMDIRWorkflow — identical file
            // discovery, build loop, and relative-path computation as the dicom-dcmdir
            // CLI, so the two surfaces produce a byte-identical DICOMDIR.
            let result: DICOMDIRWorkflow.CreateResult
            do {
                result = try DICOMDIRWorkflow.buildDirectory(
                    fromFilesIn: inputURL, recursive: recursive, strict: strict,
                    fileSetID: fsID, profile: dicomProfile, copyingInto: copyRoot,
                    verbose: verbose, progress: { out += $0 })
            } catch DICOMDIRWorkflow.WorkflowError.noDICOMFiles {
                return (out + "Error: No DICOM files found in directory: \(inputDirectory)\n", 64)
            } catch {
                return (out + "Error: \(error.localizedDescription)\n", 1)
            }

            // Every file refused (PS3.10 8.2/8.5 File ID, PS3.11 profile table, duplicate
            // instance): a DICOMDIR without directory records is not written (PS3.11 D.3.3).
            guard result.processed > 0 else {
                var message = "Error: no file could be indexed; no DICOMDIR written\n"
                for failure in result.failures { message += "  \(failure.file): \(failure.reason)\n" }
                if copyRoot == nil {
                    message += "Use --copy-to <folder> to copy the files into a new File-set under conformant File IDs (PS3.10 8.2, 8.5)\n"
                }
                return (out + message, 1)
            }

            // Serialize the DICOMDIR, then write it sandbox/TCC-resiliently via
            // OutputAccess: it writes INSIDE a security-scoped folder (the common case
            // for the output picker) and falls back to ~/Downloads/DICOMStudio with a
            // visible note when the destination isn't writable — never onto a directory
            // path, which is what produced "couldn't be saved in the folder …".
            let writtenURL: URL
            do {
                let dicomdirData = try DICOMDIRWriter.write(result.directory)
                let written = try OutputAccess.write(dicomdirData, toPath: outputFilePath,
                                                     scopedURL: outputScopedURL, subfolder: "DICOMDIR")
                if let note = written.note { out += note + "\n" }
                writtenURL = written.url
            } catch {
                return (out + "Error: Failed to write DICOMDIR: \(error.localizedDescription)\n", 1)
            }

            // Append the shared summary block (showing where the file actually landed),
            // then the CLI's stderr warning for files it did not index.
            out += DICOMDIRWorkflow.renderCreateSummary(result, outputPath: writtenURL.path)
            if result.failed > 0 {
                out += "Warning: \(result.failed) file(s) not indexed (listed in the summary)\n"
            }
            return (out, 0)
        }.value

        appendConsoleOutput(output)
        addToHistory(toolName: "dicom-dcmdir", command: commandPreview, exitCode: exitCode, output: output)
        consoleStatus = exitCode == 0 ? .success : .error
        service.setConsoleStatus(exitCode == 0 ? .success : .error)
    }

    // MARK: dicom-dcmdir validate

    /// Mirrors `dicom-dcmdir validate`: the engine's structural validation, then the File-set
    /// ID / File ID rules of PS3.10 8.1, 8.2, 8.5, 8.6 and PS3.3 Table F.3-3 with the clause each
    /// failure names (D132), then the shared report; exit 64 for a missing path, 1 for a failure.
    private func executeDicomDcmdirValidate() async {
        let dicomdirPath = paramValue("dicomdirPath")
        guard !dicomdirPath.isEmpty else {
            appendConsoleOutput("Error: Missing expected argument '<dicomdir-path>'\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-dcmdir", command: commandPreview, exitCode: 64, output: "Missing DICOMDIR path")
            return
        }
        let checkFiles = paramValue("checkFiles") == "true"
        let detailed = paramValue("detailed") == "true"

        let scopedURL = securityScopedURLs["dicomdirPath"]
        let accessing = scopedURL?.startAccessingSecurityScopedResource() ?? false
        defer { if accessing { scopedURL?.stopAccessingSecurityScopedResource() } }
        // Accept either a DICOMDIR file or the media directory that contains it.
        let requestedURL = scopedURL ?? URL(fileURLWithPath: dicomdirPath)
        let fileURL = DICOMDIRWorkflow.resolvedDICOMDIRURL(requestedURL)

        let (output, exitCode): (String, Int) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                let message = fileURL.path == requestedURL.path
                    ? "DICOMDIR file not found: \(dicomdirPath)"
                    : "No DICOMDIR found in directory: \(dicomdirPath)"
                return ("Error: \(message)\n", 64)
            }

            var out = ""
            out += "Validating DICOMDIR: \(fileURL.path)\n\n"

            let directory: DICOMDirectory
            do {
                directory = try DICOMDIRReader.read(from: fileURL)
            } catch {
                out += "❌ Failed to read DICOMDIR: \(WorkshopFileSetRules.describe(error))\n"
                return (out, 1)
            }

            // Structure (PS3.3 Table F.4-1 hierarchy, duplicate SOP Instances)
            do {
                try directory.validate(checkFileExistence: checkFiles)
            } catch {
                out += "❌ Validation failed: \(WorkshopFileSetRules.describe(error))\n"
                return (out, 1)
            }

            // File-set ID and File ID rules (PS3.10 8.1, 8.2, 8.5, 8.6; PS3.3 Table F.3-3)
            let findings = WorkshopFileSetRules.findings(
                for: directory, mediaFolder: fileURL.deletingLastPathComponent(), checkFiles: checkFiles)
            if !findings.isEmpty {
                for finding in findings { out += "❌ \(finding)\n" }
                out += "\n"
                out += "❌ Validation failed: \(findings.count) rule violation(s)\n"
                return (out, 1)
            }

            // Append the shared validation report — the single source of truth
            // shared with the dicom-dcmdir CLI.
            out += DICOMDIRWorkflow.renderValidationReport(directory, detailed: detailed)
            return (out, 0)
        }.value

        appendConsoleOutput(output)
        addToHistory(toolName: "dicom-dcmdir", command: commandPreview, exitCode: exitCode, output: output)
        consoleStatus = exitCode == 0 ? .success : .error
        service.setConsoleStatus(exitCode == 0 ? .success : .error)
    }

    // MARK: dicom-dcmdir dump

    private func executeDicomDcmdirDump() async {
        let dicomdirPath = paramValue("dicomdirPath")
        guard !dicomdirPath.isEmpty else {
            appendConsoleOutput("Error: Missing expected argument '<dicomdir-path>'\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-dcmdir", command: commandPreview, exitCode: 64, output: "Missing DICOMDIR path")
            return
        }
        let format = paramValue("format").isEmpty ? "tree" : paramValue("format")
        let verbose = paramValue("dumpVerbose") == "true"

        let scopedURL = securityScopedURLs["dicomdirPath"]
        let accessing = scopedURL?.startAccessingSecurityScopedResource() ?? false
        defer { if accessing { scopedURL?.stopAccessingSecurityScopedResource() } }
        // Accept either a DICOMDIR file or the media directory that contains it.
        let requestedURL = scopedURL ?? URL(fileURLWithPath: dicomdirPath)
        let fileURL = DICOMDIRWorkflow.resolvedDICOMDIRURL(requestedURL)

        let (output, exitCode): (String, Int) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                let message = fileURL.path == requestedURL.path
                    ? "DICOMDIR file not found: \(dicomdirPath)"
                    : "No DICOMDIR found in directory: \(dicomdirPath)"
                return ("Error: \(message)\n", 64)
            }
            var out = ""

            let directory: DICOMDirectory
            do {
                directory = try DICOMDIRReader.read(from: fileURL)
            } catch {
                out += "Error reading DICOMDIR: \(WorkshopFileSetRules.describe(error))\n"
                return (out, 1)
            }

            // Render via the shared DICOMDIRDumpFormatter — the single source of
            // truth shared with the dicom-dcmdir CLI so the dump output (tree /
            // json / text) cannot drift between the two surfaces.
            guard let rendered = DICOMDIRDumpFormatter.render(directory, format: format, verbose: verbose) else {
                out += "Error: Invalid format: \(format). Use tree, json, or text\n"
                return (out, 64)
            }
            out += rendered
            return (out, 0)
        }.value

        appendConsoleOutput(output)
        addToHistory(toolName: "dicom-dcmdir", command: commandPreview, exitCode: exitCode, output: output)
        consoleStatus = exitCode == 0 ? .success : .error
        service.setConsoleStatus(exitCode == 0 ? .success : .error)
    }

    // MARK: dicom-dcmdir update

    /// Updates an existing DICOMDIR via the SHARED `DICOMDIRWorkflow.updateDirectory`
    /// — the exact code the dicom-dcmdir CLI runs (parse → union with --add →
    /// deterministic rebuild with the original file-set ID/profile → write).
    private func executeDicomDcmdirUpdate() async {
        let dicomdirPath = paramValue("dicomdirPath")
        guard !dicomdirPath.isEmpty else {
            appendConsoleOutput("Error: Missing expected argument '<dicomdir-path>'\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-dcmdir", command: commandPreview, exitCode: 64, output: "Missing DICOMDIR path")
            return
        }
        let addPath = paramValue("add")
        let verbose = paramValue("updateVerbose") == "true"

        let dirScopedURL = securityScopedURLs["dicomdirPath"]
        let addScopedURL = securityScopedURLs["add"]
        let accessingDir = dirScopedURL?.startAccessingSecurityScopedResource() ?? false
        let accessingAdd = addScopedURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if accessingDir { dirScopedURL?.stopAccessingSecurityScopedResource() }
            if accessingAdd { addScopedURL?.stopAccessingSecurityScopedResource() }
        }
        let dicomdirURL = DICOMDIRWorkflow.resolvedDICOMDIRURL(
            dirScopedURL ?? URL(fileURLWithPath: dicomdirPath))
        guard FileManager.default.fileExists(atPath: dicomdirURL.path) else {
            // ArgumentParser ValidationError in the CLI (exit 64).
            let msg = "Error: DICOMDIR not found: \(dicomdirURL.path)\n"
            appendConsoleOutput(msg)
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-dcmdir", command: commandPreview, exitCode: 64, output: msg)
            return
        }

        if verbose {
            appendConsoleOutput("Updating DICOMDIR: \(dicomdirURL.path)\n")
            if !addPath.isEmpty { appendConsoleOutput("Adding from: \(addPath)\n") }
            appendConsoleOutput("\n")
        }
        let effectiveAdd = addScopedURL?.path ?? (addPath.isEmpty ? nil : addPath)

        let (output, exitCode) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
            var log = ""
            do {
                let result = try DICOMDIRWorkflow.updateDirectory(
                    dicomdirURL: dicomdirURL, addPath: effectiveAdd,
                    verbose: verbose, progress: { log += $0 }
                )
                try DICOMDIRWriter.write(result.directory, to: dicomdirURL)
                log += DICOMDIRWorkflow.renderUpdateSummary(result, outputPath: dicomdirURL.path)
                return (log, 0)
            } catch {
                return (log + "Error: \(error)\n", 1)
            }
        }.value

        appendConsoleOutput(output)
        addToHistory(toolName: "dicom-dcmdir", command: commandPreview, exitCode: exitCode, output: output)
        consoleStatus = exitCode == 0 ? .success : .error
        service.setConsoleStatus(exitCode == 0 ? .success : .error)
    }

    // MARK: - dicom-pdf Execution

    /// Extracts an embedded document from a DICOM Encapsulated Document, or
    /// encapsulates a document (PDF/CDA/STL/OBJ/MTL) into a DICOM file.
    /// In-process reimplementation of the `dicom-pdf` CLI using DICOMKit's
    /// EncapsulatedDocumentParser / EncapsulatedDocumentBuilder. Directory
    /// (`--recursive`) mode is supported via the scoped directory URL.
    private func executeDicomPdf() async {
        let inputPath = paramValue("inputPath")
        guard !inputPath.isEmpty else {
            appendConsoleOutput("Error: Input path is required.\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-pdf", command: commandPreview, exitCode: 1, output: "Missing input path")
            return
        }

        let outputPath  = paramValue("output")
        let extractMode = paramValue("extract") == "true"
        let patientName = paramValue("patient-name")
        let patientID   = paramValue("patient-id")
        let title       = paramValue("title")
        let studyUID    = paramValue("study-uid")
        let seriesUID   = paramValue("series-uid")
        let modality    = paramValue("modality")
        let seriesDesc  = paramValue("series-description")
        let seriesNumber   = Int(paramValue("series-number"))
        let instanceNumber = Int(paramValue("instance-number"))
        let recursive   = paramValue("recursive") == "true"
        let showMeta    = paramValue("show-metadata") == "true"
        let verbose     = paramValue("verbose") == "true"

        // Gain sandbox access via security-scoped URLs registered by the file pickers.
        let inputScopedURL  = securityScopedURLs["inputPath"]
        let outputScopedURL = securityScopedURLs["output"]
        let accessingInput  = inputScopedURL?.startAccessingSecurityScopedResource()  ?? false
        let accessingOutput = outputScopedURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if accessingInput  { inputScopedURL?.stopAccessingSecurityScopedResource() }
            if accessingOutput { outputScopedURL?.stopAccessingSecurityScopedResource() }
        }

        let inputURL = inputScopedURL ?? URL(fileURLWithPath: inputPath)

        // Resolve a sandbox-writable destination (scoped URL → ~/Downloads → fallback).
        let (resolvedOutput, redirectNote) = SecurityViewModel.resolveWritableOutput(
            path: outputScopedURL?.path ?? outputPath,
            scopedURL: outputScopedURL
        )
        if let note = redirectNote { appendConsoleOutput(note) }
        let effectiveOutput = resolvedOutput.isEmpty ? outputPath : resolvedOutput

        let (output, exitCode) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
            let fm = FileManager.default

            // MARK: helpers
            //
            // Document-type ↔ extension mapping, default modality, the byte-size
            // formatter, the `--show-metadata` report, and the builder option chain
            // all come from DICOMKit's shared `EncapsulatedDocumentWorkflow`, so this
            // reimplementation and the `dicom-pdf` CLI share one source of truth and
            // cannot drift. UID generation uses the shared `UIDGenerator` (DICOMCore).

            func generateUID() -> String { UIDGenerator.generateUID().value }

            // MARK: input classification

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: inputURL.path, isDirectory: &isDir) else {
                return ("Error: Input path not found: \(inputURL.path)\n", 1)
            }

            // MARK: single-file extraction

            func extractFromFile(_ srcURL: URL, outURLOrPath: String?) -> (String, Int) {
                var log = ""
                if verbose { log += "Extracting document from: \(srcURL.path)\n" }
                do {
                    let data = try Data(contentsOf: srcURL)
                    let dicomFile = try DICOMFile.read(from: data, force: false)
                    let document = try EncapsulatedDocumentParser.parse(from: dicomFile.dataSet)

                    if showMeta { log += document.metadataReport() }

                    // Determine output path.
                    let finalOutputPath: String
                    if let specified = outURLOrPath, !specified.isEmpty {
                        // If a directory was supplied, auto-name inside it.
                        var d: ObjCBool = false
                        if fm.fileExists(atPath: specified, isDirectory: &d), d.boolValue {
                            let baseName = srcURL.deletingPathExtension().lastPathComponent
                            let ext = document.documentType.fileExtension
                            finalOutputPath = URL(fileURLWithPath: specified)
                                .appendingPathComponent("\(baseName).\(ext)").path
                        } else {
                            finalOutputPath = specified
                        }
                    } else {
                        let baseName = srcURL.deletingPathExtension().lastPathComponent
                        let ext = document.documentType.fileExtension
                        finalOutputPath = srcURL.deletingLastPathComponent()
                            .appendingPathComponent("\(baseName).\(ext)").path
                    }

                    let writeRes = try OutputAccess.write(document.documentData, toPath: finalOutputPath,
                                                          scopedURL: outputScopedURL, subfolder: "PDF/Extracted")
                    if let note = writeRes.note { log += note + "\n" }

                    if verbose {
                        log += "✓ Extracted \(document.documentType) (\(EncapsulatedDocumentFormatting.fileSize(Int64(document.documentData.count))))\n"
                        log += "  Output: \(writeRes.url.path)\n"
                    } else {
                        log += "Extracted: \(writeRes.url.path)\n"
                    }
                    return (log, 0)
                } catch {
                    log += "Error: \(error.localizedDescription)\n"
                    return (log, 1)
                }
            }

            // MARK: single-file encapsulation

            func encapsulateFile(_ srcURL: URL, outURLOrPath: String?) -> (String, Int) {
                var log = ""
                if verbose { log += "Encapsulating document: \(srcURL.path)\n" }

                guard !patientName.isEmpty else {
                    return ("Error: Patient Name is required for encapsulation (--patient-name)\n", 1)
                }
                guard !patientID.isEmpty else {
                    return ("Error: Patient ID is required for encapsulation (--patient-id)\n", 1)
                }

                do {
                    let documentData = try Data(contentsOf: srcURL)
                    let documentType = DICOMKit.EncapsulatedDocumentType(fileExtension: srcURL.pathExtension)

                    let finalStudyUID  = studyUID.isEmpty  ? generateUID() : studyUID
                    let finalSeriesUID = seriesUID.isEmpty ? generateUID() : seriesUID

                    let finalModality = modality.isEmpty ? documentType.defaultModality : modality

                    let builder = EncapsulatedDocumentBuilder(
                        documentData: documentData,
                        mimeType: documentType.expectedMIMEType,
                        documentType: documentType,
                        studyInstanceUID: finalStudyUID,
                        seriesInstanceUID: finalSeriesUID
                    )
                    .applyStandardOptions(
                        patientName: patientName,
                        patientID: patientID,
                        modality: finalModality,
                        title: title,
                        seriesDescription: seriesDesc,
                        seriesNumber: seriesNumber,
                        instanceNumber: instanceNumber
                    )

                    let dataSet = try builder.buildDataSet()
                    let dicomFile = DICOMFile.create(
                        dataSet: dataSet,
                        sopClassUID: documentType.sopClassUID,
                        transferSyntaxUID: "1.2.840.10008.1.2.1" // Explicit VR Little Endian
                    )
                    let dicomData = try dicomFile.write()

                    let finalOutputPath: String
                    if let specified = outURLOrPath, !specified.isEmpty {
                        var d: ObjCBool = false
                        if fm.fileExists(atPath: specified, isDirectory: &d), d.boolValue {
                            let baseName = srcURL.deletingPathExtension().lastPathComponent
                            finalOutputPath = URL(fileURLWithPath: specified)
                                .appendingPathComponent("\(baseName).dcm").path
                        } else {
                            finalOutputPath = specified
                        }
                    } else {
                        finalOutputPath = srcURL.deletingPathExtension()
                            .appendingPathExtension("dcm").path
                    }

                    let writeRes = try OutputAccess.write(dicomData, toPath: finalOutputPath,
                                                          scopedURL: outputScopedURL, subfolder: "PDF/Encapsulated")
                    if let note = writeRes.note { log += note + "\n" }

                    if verbose {
                        log += "✓ Encapsulated \(documentType) (\(EncapsulatedDocumentFormatting.fileSize(Int64(documentData.count))))\n"
                        log += "  DICOM size: \(EncapsulatedDocumentFormatting.fileSize(Int64(dicomData.count)))\n"
                        log += "  Patient: \(patientName) [\(patientID)]\n"
                        log += "  Study UID: \(finalStudyUID)\n"
                        log += "  Output: \(writeRes.url.path)\n"
                    } else {
                        log += "Encapsulated: \(writeRes.url.path)\n"
                    }
                    return (log, 0)
                } catch {
                    log += "Error: \(error.localizedDescription)\n"
                    return (log, 1)
                }
            }

            // MARK: directory mode

            func enumerateFiles(_ dir: URL) -> [URL] {
                // Shared, sorted directory walk — the same gatherer the dicom-pdf
                // CLI uses, so both surfaces process the same files in the same order.
                FileGatherer.regularFiles(under: dir) ?? []
            }

            func extractFromDirectory(_ dir: URL) -> (String, Int) {
                var log = ""
                let outDirRequested: URL = (outURLOrPathString().isEmpty)
                    ? dir.appendingPathComponent("extracted")
                    : URL(fileURLWithPath: outURLOrPathString())
                // Sandbox/TCC-resilient output directory (else fall back to ~/Downloads/DICOMStudio).
                let _od = OutputAccess.resolveWritableURL(forPath: outDirRequested.path, scopedURL: outputScopedURL, subfolder: "PDF/Extracted", isDirectory: true)
                let outDir = _od.url
                if let note = _od.note { log += note + "\n" }
                do {
                    try fm.createDirectory(at: outDir, withIntermediateDirectories: true)
                } catch {
                    return ("Error: Unable to create output directory: \(error.localizedDescription)\n", 1)
                }
                if verbose {
                    log += "Extracting documents from: \(dir.path)\n"
                    log += "Output directory: \(outDir.path)\n\n"
                }
                var success = 0, failure = 0
                for f in enumerateFiles(dir) {
                    do {
                        let data = try Data(contentsOf: f)
                        let dicomFile = try DICOMFile.read(from: data, force: false)
                        let document = try EncapsulatedDocumentParser.parse(from: dicomFile.dataSet)
                        let baseName = f.deletingPathExtension().lastPathComponent
                        let ext = document.documentType.fileExtension
                        let outFile = outDir.appendingPathComponent("\(baseName).\(ext)")
                        try document.documentData.write(to: outFile)
                        success += 1
                        if verbose { log += "✓ \(f.lastPathComponent) → \(outFile.lastPathComponent)\n" }
                    } catch {
                        failure += 1
                        if verbose { log += "✗ \(f.lastPathComponent): \(error.localizedDescription)\n" }
                    }
                }
                log += "\nExtraction complete:\n"
                log += "  Successful: \(success)\n"
                if failure > 0 { log += "  Failed: \(failure)\n" }
                log += "  Output directory: \(outDir.path)\n"
                return (log, failure > 0 && success == 0 ? 1 : 0)
            }

            func encapsulateFromDirectory(_ dir: URL) -> (String, Int) {
                var log = ""
                guard !patientName.isEmpty else {
                    return ("Error: Patient Name is required for batch encapsulation (--patient-name)\n", 1)
                }
                guard !patientID.isEmpty else {
                    return ("Error: Patient ID is required for batch encapsulation (--patient-id)\n", 1)
                }
                let outDirRequested: URL = (outURLOrPathString().isEmpty)
                    ? dir.appendingPathComponent("encapsulated")
                    : URL(fileURLWithPath: outURLOrPathString())
                // Sandbox/TCC-resilient output directory (else fall back to ~/Downloads/DICOMStudio).
                let _od = OutputAccess.resolveWritableURL(forPath: outDirRequested.path, scopedURL: outputScopedURL, subfolder: "PDF/Encapsulated", isDirectory: true)
                let outDir = _od.url
                if let note = _od.note { log += note + "\n" }
                do {
                    try fm.createDirectory(at: outDir, withIntermediateDirectories: true)
                } catch {
                    return ("Error: Unable to create output directory: \(error.localizedDescription)\n", 1)
                }
                if verbose {
                    log += "Encapsulating documents from: \(dir.path)\n"
                    log += "Output directory: \(outDir.path)\n\n"
                }
                var success = 0, failure = 0
                var instNum = instanceNumber ?? 1
                let finalStudyUID  = studyUID.isEmpty  ? generateUID() : studyUID
                let finalSeriesUID = seriesUID.isEmpty ? generateUID() : seriesUID

                for f in enumerateFiles(dir) {
                    let docType = DICOMKit.EncapsulatedDocumentType(fileExtension: f.pathExtension)
                    guard docType != .unknown else {
                        if verbose { log += "⊘ \(f.lastPathComponent): Unsupported file type\n" }
                        continue
                    }
                    do {
                        let documentData = try Data(contentsOf: f)
                        let finalModality = modality.isEmpty ? docType.defaultModality : modality
                        let builder = EncapsulatedDocumentBuilder(
                            documentData: documentData,
                            mimeType: docType.expectedMIMEType,
                            documentType: docType,
                            studyInstanceUID: finalStudyUID,
                            seriesInstanceUID: finalSeriesUID
                        )
                        .applyStandardOptions(
                            patientName: patientName,
                            patientID: patientID,
                            modality: finalModality,
                            title: title,
                            seriesDescription: seriesDesc,
                            seriesNumber: seriesNumber,
                            instanceNumber: instNum
                        )

                        let dataSet = try builder.buildDataSet()
                        let dicomFile = DICOMFile.create(
                            dataSet: dataSet,
                            sopClassUID: docType.sopClassUID,
                            transferSyntaxUID: "1.2.840.10008.1.2.1"
                        )
                        let dicomData = try dicomFile.write()
                        let baseName = f.deletingPathExtension().lastPathComponent
                        let outFile = outDir.appendingPathComponent("\(baseName).dcm")
                        try dicomData.write(to: outFile)
                        success += 1
                        instNum += 1
                        if verbose { log += "✓ \(f.lastPathComponent) → \(outFile.lastPathComponent)\n" }
                    } catch {
                        failure += 1
                        if verbose { log += "✗ \(f.lastPathComponent): \(error.localizedDescription)\n" }
                    }
                }
                log += "\nEncapsulation complete:\n"
                log += "  Successful: \(success)\n"
                if failure > 0 { log += "  Failed: \(failure)\n" }
                log += "  Study UID: \(finalStudyUID)\n"
                log += "  Series UID: \(finalSeriesUID)\n"
                log += "  Output directory: \(outDir.path)\n"
                return (log, failure > 0 && success == 0 ? 1 : 0)
            }

            func outURLOrPathString() -> String { effectiveOutput }

            // MARK: dispatch

            if isDir.boolValue {
                guard recursive else {
                    return ("Error: Directory processing requires --recursive flag\n", 1)
                }
                return extractMode ? extractFromDirectory(inputURL) : encapsulateFromDirectory(inputURL)
            } else {
                let outArg = effectiveOutput.isEmpty ? nil : effectiveOutput
                return extractMode
                    ? extractFromFile(inputURL, outURLOrPath: outArg)
                    : encapsulateFile(inputURL, outURLOrPath: outArg)
            }
        }.value

        appendConsoleOutput(output)
        addToHistory(toolName: "dicom-pdf", command: commandPreview, exitCode: exitCode, output: output)
        consoleStatus = exitCode == 0 ? .success : .error
        service.setConsoleStatus(exitCode == 0 ? .success : .error)
    }

    // MARK: - dicom-pixedit Execution

    /// Edits pixel data in a DICOM file (mask / crop / window-level / invert) and
    /// writes a new DICOM file. Reimplements the executable-local PixelEditor logic
    /// in-process using DICOMKit/DICOMCore APIs.
    private func executeDicomPixedit() async {
        let inputPath = paramValue("inputPath")
        let outputPath = paramValue("output")
        let maskRegionStr = paramValue("mask-region")
        let fillValueStr = paramValue("fill-value")
        let cropStr = paramValue("crop")
        let windowCenterStr = paramValue("window-center")
        let windowWidthStr = paramValue("window-width")
        let applyWindow = paramValue("apply-window") == "true"
        let invert = paramValue("invert") == "true"
        let verbose = paramValue("verbose") == "true"

        guard !inputPath.isEmpty else {
            appendConsoleOutput("Error: Input file path is required.\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-pixedit", command: commandPreview, exitCode: 1, output: "Missing input path")
            return
        }
        guard !outputPath.isEmpty else {
            appendConsoleOutput("Error: Output path is required.\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-pixedit", command: commandPreview, exitCode: 1, output: "Missing output path")
            return
        }

        // Build the operation list (shared DICOMKit PixelOperation), mirroring
        // main.swift validation order. Region strings parse via the shared
        // PixelEditor.parseRegion — the exact parser the CLI uses.
        let regionParser = PixelEditor(verbose: false)

        var operations: [PixelOperation] = []

        if !maskRegionStr.isEmpty {
            guard let r = try? regionParser.parseRegion(maskRegionStr) else {
                appendConsoleOutput("Error: \(PixelEditError.invalidRegion(maskRegionStr).errorDescription ?? "Invalid region")\n")
                consoleStatus = .error; service.setConsoleStatus(.error)
                addToHistory(toolName: "dicom-pixedit", command: commandPreview, exitCode: 1, output: "Invalid mask region")
                return
            }
            operations.append(.mask(x: r.x, y: r.y, width: r.width, height: r.height, fillValue: Int(fillValueStr) ?? 0))
        }

        if !cropStr.isEmpty {
            guard let r = try? regionParser.parseRegion(cropStr) else {
                appendConsoleOutput("Error: \(PixelEditError.invalidRegion(cropStr).errorDescription ?? "Invalid region")\n")
                consoleStatus = .error; service.setConsoleStatus(.error)
                addToHistory(toolName: "dicom-pixedit", command: commandPreview, exitCode: 1, output: "Invalid crop region")
                return
            }
            operations.append(.crop(x: r.x, y: r.y, width: r.width, height: r.height))
        }

        if applyWindow {
            guard let center = Double(windowCenterStr), let width = Double(windowWidthStr) else {
                appendConsoleOutput("Error: --apply-window requires both --window-center and --window-width\n")
                consoleStatus = .error; service.setConsoleStatus(.error)
                addToHistory(toolName: "dicom-pixedit", command: commandPreview, exitCode: 1, output: "Window center/width required")
                return
            }
            operations.append(.windowLevel(center: center, width: width))
        }

        if invert { operations.append(.invert) }

        guard !operations.isEmpty else {
            appendConsoleOutput("Error: No operations specified. Use --mask-region, --crop, --apply-window, or --invert\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-pixedit", command: commandPreview, exitCode: 1, output: "No operations specified")
            return
        }

        // Gain sandbox access via security-scoped URLs.
        let inputScopedURL = securityScopedURLs["inputPath"]
        let outputScopedURL = securityScopedURLs["output"]
        let accessingInput = inputScopedURL?.startAccessingSecurityScopedResource() ?? false
        let accessingOutput = outputScopedURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if accessingInput { inputScopedURL?.stopAccessingSecurityScopedResource() }
            if accessingOutput { outputScopedURL?.stopAccessingSecurityScopedResource() }
        }
        let inputURL = inputScopedURL ?? URL(fileURLWithPath: inputPath)
        let outputURL = outputScopedURL ?? URL(fileURLWithPath: outputPath)

        if verbose {
            for line in PixelEditConsole.headerLines(input: inputURL.path, output: outputURL.path, operationCount: operations.count) {
                appendConsoleOutput(line + "\n")
            }
        }

        let (output, outputData, exitCode) = await Task.detached(priority: .userInitiated) { () -> (String, Data?, Int) in
            var log = ""
            do {
                let fileData = try Data(contentsOf: inputURL)
                // Apply pixel operations via the shared DICOMKit engine — the exact
                // same PixelEditor the `dicom-pixedit` CLI uses, so the produced
                // DICOM bytes AND the verbose log lines (Image:, Applied mask:, …)
                // are identical. Output is written below via the sandbox-aware
                // OutputAccess path.
                let editor = PixelEditor(verbose: verbose, log: { log += $0 + "\n" })
                let (written, _) = try editor.processData(fileData, operations: operations)
                return (log, written, 0)
            } catch let e as PixelEditError {
                return ("Error: \(e.errorDescription ?? "\(e)")\n", nil, 1)
            } catch {
                return ("Error: \(error.localizedDescription)\n", nil, 1)
            }
        }.value

        if exitCode == 0, let outputData {
            do {
                // Sandbox/TCC-resilient write (prefer scoped URL; else fall back to ~/Downloads).
                let writeRes = try OutputAccess.write(outputData, toPath: outputPath, scopedURL: outputScopedURL, subfolder: "PixEdit")
                appendConsoleOutput(output)
                if let note = writeRes.note { appendConsoleOutput(note + "\n") }
                // CLI parity: Written/Done are verbose-gated shared lines — a
                // non-verbose dicom-pixedit run is silent on success.
                if verbose {
                    appendConsoleOutput(PixelEditConsole.writtenLine(path: writeRes.url.path) + "\n")
                    appendConsoleOutput(PixelEditConsole.doneLine() + "\n")
                }
                consoleStatus = .success; service.setConsoleStatus(.success)
                addToHistory(toolName: "dicom-pixedit", command: commandPreview, exitCode: 0, output: output)
            } catch {
                let msg = "Error: Failed to write output: \(error.localizedDescription)\n"
                appendConsoleOutput(output)
                appendConsoleOutput(msg)
                consoleStatus = .error; service.setConsoleStatus(.error)
                addToHistory(toolName: "dicom-pixedit", command: commandPreview, exitCode: 1, output: msg)
            }
        } else {
            appendConsoleOutput(output)
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-pixedit", command: commandPreview, exitCode: exitCode, output: output)
        }
    }

private func executeDicomSplit() async {
    let inputPath = paramValue("inputPath")
    guard !inputPath.isEmpty else {
        appendConsoleOutput("Error: Input DICOM file or directory is required.\n")
        consoleStatus = .error; service.setConsoleStatus(.error)
        addToHistory(toolName: "dicom-split", command: commandPreview, exitCode: 1, output: "Missing input path")
        return
    }

    let outputDir = paramValue("output").isEmpty ? "." : paramValue("output")
    let framesSpec = paramValue("frames")
    let frameNumbersSpec = paramValue("frame-numbers")
    let format = paramValue("format").isEmpty ? "dicom" : paramValue("format")
    let applyWindow = paramValue("apply-window") == "true"
    let pattern = paramValue("pattern").isEmpty ? nil : paramValue("pattern")
    let recursive = paramValue("recursive") == "true"
    let verbose = paramValue("verbose") == "true"

    // Value parsing happens in ArgumentParser on the CLI, before `run()` sees
    // anything: a non-numeric --window-center / --window-width / --frames-per is
    // the FIRST thing reported, with ArgumentParser's two-line message. Mirror
    // that (shared wording via SplitConsole) instead of silently coercing to nil.
    let windowCenterStr = paramValue("window-center")
    let windowWidthStr = paramValue("window-width")
    let framesPerStr = paramValue("frames-per").trimmingCharacters(in: .whitespaces)
    let valueChecks: [(raw: String, flag: String, help: String, ok: Bool)] = [
        (windowCenterStr, "--window-center", SplitConsole.windowCenterHelp, windowCenterStr.isEmpty || Double(windowCenterStr) != nil),
        (windowWidthStr, "--window-width", SplitConsole.windowWidthHelp, windowWidthStr.isEmpty || Double(windowWidthStr) != nil),
        (framesPerStr, "--frames-per", SplitConsole.framesPerHelp, framesPerStr.isEmpty || Int(framesPerStr) != nil),
    ]
    for check in valueChecks where !check.ok {
        let lines = SplitConsole.invalidValueLines(value: check.raw, option: check.flag, help: check.help)
        for line in lines { appendConsoleOutput(line + "\n") }
        consoleStatus = .error; service.setConsoleStatus(.error)
        addToHistory(toolName: "dicom-split", command: commandPreview, exitCode: 64, output: lines[0])
        return
    }
    let windowCenter = Double(windowCenterStr)
    let windowWidth = Double(windowWidthStr)

    // P-SPLIT-1, as the CLI's validate(): both frame selections at once is refused (exit 1,
    // not a usage error); the deprecated 0-based --frames then prints its stderr note first.
    if !framesSpec.isEmpty && !frameNumbersSpec.isEmpty {
        let msg = SplitConsole.framesAndFrameNumbersConflictMessage
        appendConsoleOutput("Error: \(msg)\n")
        consoleStatus = .error; service.setConsoleStatus(.error)
        addToHistory(toolName: "dicom-split", command: commandPreview, exitCode: 1, output: msg)
        return
    }
    if !framesSpec.isEmpty {
        appendConsoleOutput(SplitConsole.framesDeprecatedLine + "\n")
    }

    // Enhanced-multiframe options — the same SplitOptions the dicom-split CLI builds.
    var splitOptions = SplitOptions()
    splitOptions.target = SplitTargetPolicy(rawValue: paramValue("target")) ?? .auto
    splitOptions.pixelHandling = MultiframePixelHandling(rawValue: paramValue("pixel-handling")) ?? .preserve
    splitOptions.privateGroups = PrivateFunctionalGroupPolicy(rawValue: paramValue("private-groups")) ?? .flatten
    splitOptions.instanceNumbering = SplitInstanceNumbering(rawValue: paramValue("instance-number")) ?? .frame
    splitOptions.seriesGrouping = SplitSeriesGrouping(rawValue: paramValue("split-by")) ?? .none
    splitOptions.newSeries = paramValue("new-series") == "true"
    splitOptions.deterministicUIDs = paramValue("random-uids") != "true"
    splitOptions.framesPerInstance = framesPerStr.isEmpty ? nil : Int(framesPerStr)

    // Sandbox access.
    let inputScopedURL = securityScopedURLs["inputPath"]
    let outputScopedURL = securityScopedURLs["output"]
    let accessingInput = inputScopedURL?.startAccessingSecurityScopedResource() ?? false
    let accessingOutput = outputScopedURL?.startAccessingSecurityScopedResource() ?? false
    defer {
        if accessingInput { inputScopedURL?.stopAccessingSecurityScopedResource() }
        if accessingOutput { outputScopedURL?.stopAccessingSecurityScopedResource() }
    }
    let inputURL = inputScopedURL ?? URL(fileURLWithPath: inputPath)
    // Sandbox/TCC-resilient output directory (frames are written inside it).
    let _splitOut = OutputAccess.resolveWritableURL(forPath: outputDir, scopedURL: outputScopedURL, subfolder: "SplitFrames", isDirectory: true)
    let outputBaseURL = _splitOut.url
    if let note = _splitOut.note { appendConsoleOutput(note + "\n") }

    // From here on the checks run in the CLI's `run()` order: input exists,
    // output directory, --frames-per >= 1, banner, --frames parse.
    let fm = FileManager.default
    var isDir: ObjCBool = false
    // (The CLI raises these as ArgumentParser ValidationError: exit 64.)
    guard fm.fileExists(atPath: inputURL.path, isDirectory: &isDir) else {
        let msg = SplitConsole.inputNotFoundMessage(path: inputURL.path)
        appendConsoleOutput("Error: \(msg)\n")
        consoleStatus = .error; service.setConsoleStatus(.error)
        addToHistory(toolName: "dicom-split", command: commandPreview, exitCode: 64, output: msg)
        return
    }

    // Ensure output directory exists.
    do {
        try fm.createDirectory(at: outputBaseURL, withIntermediateDirectories: true)
    } catch {
        appendConsoleOutput("Error: \(SplitConsole.outputNotDirectoryMessage(path: outputBaseURL.path))\n")
        consoleStatus = .error; service.setConsoleStatus(.error)
        addToHistory(toolName: "dicom-split", command: commandPreview, exitCode: 64, output: error.localizedDescription)
        return
    }

    if let per = splitOptions.framesPerInstance, per < 1 {
        let msg = SplitConsole.framesPerTooSmallMessage
        appendConsoleOutput("Error: \(msg)\n")
        consoleStatus = .error; service.setConsoleStatus(.error)
        addToHistory(toolName: "dicom-split", command: commandPreview, exitCode: 64, output: msg)
        return
    }

    // Banner via the SHARED SplitConsole — byte-identical to the CLI's.
    if verbose {
        for line in SplitConsole.headerLines(
            input: inputURL.path, output: outputBaseURL.path,
            format: SplitOutputFormat(rawValue: format) ?? .dicom,
            frames: framesSpec, applyWindow: applyWindow,
            windowCenter: windowCenter, windowWidth: windowWidth,
            options: splitOptions, frameNumbers: frameNumbersSpec
        ) {
            appendConsoleOutput(line + "\n")
        }
    }

    // Parse the frame selection through the SHARED SplitConsole parsers — Frame numbers
    // from 1 (PS3.3 C.7.6.16.1.2) for --frame-numbers, the deprecated 0-based grammar for
    // --frames — with the exact error text the dicom-split CLI uses (exit 64). The CLI
    // parses it after the banner, so a bad selection still shows the verbose header.
    var frameIndices: Set<Int>? = nil
    if !frameNumbersSpec.isEmpty || !framesSpec.isEmpty {
        do {
            frameIndices = !frameNumbersSpec.isEmpty
                ? try SplitConsole.parseFrameNumberSelection(frameNumbersSpec)
                : try SplitConsole.parseFrameSelection(framesSpec)
        } catch {
            let parseError = (error as? SplitConsole.FrameSelectionError)?.description ?? "\(error)"
            appendConsoleOutput("Error: \(parseError)\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-split", command: commandPreview, exitCode: 64, output: parseError)
            return
        }
    }

    // Capture immutable values for the detached worker.
    let workIsDirectory = isDir.boolValue
    let workInputPath = inputURL.path
    let workRecursive = recursive
    let workOutputBase = outputBaseURL.path
    let workFrameIndices = frameIndices
    let workFormat = format
    let workApplyWindow = applyWindow
    let workWindowCenter = windowCenter
    let workWindowWidth = windowWidth
    let workPattern = pattern
    let workVerbose = verbose
    let workOptions = splitOptions

    struct SplitOutcome: Sendable {
        var log: String = ""
        var writtenPaths: [String] = []
        var processedFiles = 0
        var skippedFiles = 0
        var extracted = 0
        var failed = 0
        var walkError: String? = nil
    }

    let outcome = await Task.detached(priority: .userInitiated) { () -> SplitOutcome in
        // Delegate frame extraction to the shared DICOMKit engine — the exact same
        // FrameSplitter the `dicom-split` CLI uses. Verbose progress is collected
        // through the log sink; per-frame stats come back in SplitResult.
        final class LogBox: @unchecked Sendable { var text = "" }
        let logBox = LogBox()
        let splitter = FrameSplitter(
            outputPath: workOutputBase,
            format: SplitOutputFormat(rawValue: workFormat) ?? .dicom,
            applyWindow: workApplyWindow,
            windowCenter: workWindowCenter,
            windowWidth: workWindowWidth,
            namingPattern: workPattern,
            verbose: workVerbose,
            options: workOptions,
            log: { logBox.text += $0 + "\n" }
        )

        var split = SplitResult()
        var walkError: String? = nil
        if workIsDirectory {
            // Directory input goes through the SHARED FrameSplitter.processDirectory —
            // the exact call the dicom-split CLI makes (sorted order, hidden files
            // included, shared DICOM-file filter). The verbose "Found N files to
            // process" line arrives through the log sink like all other progress.
            do {
                split = try await splitter.processDirectory(workInputPath, recursive: workRecursive, frameIndices: workFrameIndices)
            } catch {
                walkError = "\(error)"
            }
        } else {
            await splitter.processFile(workInputPath, frameIndices: workFrameIndices, into: &split)
        }

        var result = SplitOutcome()
        result.log = logBox.text
        result.writtenPaths = split.writtenPaths
        result.processedFiles = split.processedFiles
        result.skippedFiles = split.skippedFiles
        result.extracted = split.extracted
        result.failed = split.failed
        result.walkError = walkError
        return result
    }.value

    // Emit the engine's log unconditionally: FrameSplitter gates its own
    // progress lines on `verbose`, but its warnings (non-DICOM / unsplittable
    // file skipped, `--frames` ignored for concatenation parts) are always
    // printed by the CLI — gating the whole log here used to drop them.
    if !outcome.log.isEmpty {
        appendConsoleOutput(outcome.log)
    }

    // Directory walk failure (SplitError.directoryAccessFailed) — the CLI throws
    // here, so mirror an error exit instead of a silent empty summary.
    if let walkError = outcome.walkError {
        appendConsoleOutput("Error: \(walkError)\n")
        consoleStatus = .error; service.setConsoleStatus(.error)
        addToHistory(toolName: "dicom-split", command: commandPreview, exitCode: 1, output: walkError)
        return
    }

    // Summary via the SHARED SplitConsole — one stats line for every outcome
    // (including "nothing to split"), exactly as the CLI reports it. The app used
    // to substitute its own prose here, which diffed on every run.
    var splitResult = SplitResult()
    splitResult.processedFiles = outcome.processedFiles
    splitResult.skippedFiles = outcome.skippedFiles
    splitResult.extracted = outcome.extracted
    splitResult.failed = outcome.failed
    splitResult.writtenPaths = outcome.writtenPaths
    for line in SplitConsole.completionLines(result: splitResult) {
        appendConsoleOutput(line + "\n")
    }

    let exitCode = outcome.failed > 0 ? 1 : 0
    let summary = "Extracted \(outcome.extracted) frame(s), \(outcome.failed) failed"
    consoleStatus = exitCode == 0 ? .success : .error
    service.setConsoleStatus(exitCode == 0 ? .success : .error)
    addToHistory(toolName: "dicom-split", command: commandPreview, exitCode: exitCode, output: summary)
}

    // MARK: - dicom-merge Execution

    /// Merges multiple single-frame DICOM files into a multi-frame object.
    ///
    /// Reimplements the executable-local `FrameMerger` using DICOMKit/DICOMCore APIs:
    /// gathers input files (file or directory, optionally recursive), optionally validates
    /// pixel/attribute consistency, sorts frames, concatenates Pixel Data, sets
    /// Number of Frames, mints a fresh SOP Instance UID, and writes the result.
    ///
    /// Levels:
    ///  - `file`   -> a single merged multi-frame file written to `--output`
    ///  - `series` -> one merged file per Series Instance UID, written into `--output` dir
    ///  - `study`  -> per-study dir, one merged file per series within each study
    ///
    /// The `--format` enhanced-*/legacy-converted-*/sc-/us-multiframe construction runs
    /// through the same shared FrameMerger (FunctionalGroupBuilder + MultiframePixelAssembler)
    /// the CLI uses, so the app and the CLI produce the same object.
    private func executeDicomMerge() async {
        let inputPath = paramValue("inputPath")
        let outputPath = paramValue("output")
        let format = paramValue("format").isEmpty ? "standard" : paramValue("format")
        let level = paramValue("level").isEmpty ? "file" : paramValue("level")
        let sortBy = paramValue("sort-by").isEmpty ? "InstanceNumber" : paramValue("sort-by")
        let order = paramValue("order").isEmpty ? "ascending" : paramValue("order")
        let validate = paramValue("validate") == "true"
        let recursive = paramValue("recursive") == "true"
        let verbose = paramValue("verbose") == "true"

        var mergeOptions = MergeOptions()
        mergeOptions.pixelHandling = MultiframePixelHandling(rawValue: paramValue("pixel-handling")) ?? .preserve
        mergeOptions.makeStacks = paramValue("make-stacks") == "true"
        mergeOptions.temporalPositions = paramValue("temporal-position") == "true"
        mergeOptions.newSeries = paramValue("new-series") == "true"
        mergeOptions.allowAnySource = paramValue("allow-any-source") == "true"

        // dicom-merge's refusals are ArgumentParser ValidationErrors (exit 64), same text.
        guard !inputPath.isEmpty else {
            appendConsoleOutput("Error: \(MergeConsole.noInputFilesMessage)\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-merge", command: commandPreview, exitCode: 64, output: "Missing input path")
            return
        }
        guard !outputPath.isEmpty else {
            appendConsoleOutput("Error: Missing expected argument '--output <output>'\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-merge", command: commandPreview, exitCode: 64, output: "Missing output path")
            return
        }

        // Gain sandbox access via security-scoped URLs.
        let inputScopedURL = securityScopedURLs["inputPath"]
        let outputScopedURL = securityScopedURLs["output"]
        let accessingInput = inputScopedURL?.startAccessingSecurityScopedResource() ?? false
        let accessingOutput = outputScopedURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if accessingInput { inputScopedURL?.stopAccessingSecurityScopedResource() }
            if accessingOutput { outputScopedURL?.stopAccessingSecurityScopedResource() }
        }

        let inputURL = inputScopedURL ?? URL(fileURLWithPath: inputPath)
        // Sandbox/TCC-resilient output (series/study modes write a directory; file mode a single file).
        let (outputURL, outRedirectNote) = OutputAccess.resolveWritableURL(
            forPath: outputPath, scopedURL: outputScopedURL, subfolder: "Merge", isDirectory: level != "file")
        if let note = outRedirectNote { appendConsoleOutput(note + "\n") }

        // The CLI's <inputs> is a variadic positional list; the field may hold several
        // semicolon-separated roots (the preview expands the same split into positional
        // tokens). The browsed (security-scoped) URL stands in when only one path is given.
        let mergeRoots = CommandBuilderHelpers.splitMultiValue(inputPath)
        let mergeRootPaths = mergeRoots.count > 1 ? mergeRoots : [inputURL.path]

        // Every root must exist — the CLI validates this before its banner (a
        // missing root is "Input path does not exist", not "No DICOM files found").
        for root in mergeRootPaths where !FileManager.default.fileExists(atPath: root) {
            let msg = MergeConsole.inputNotFoundMessage(path: root)
            appendConsoleOutput("Error: \(msg)\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-merge", command: commandPreview, exitCode: 64, output: msg)
            return
        }

        // Banner via the SHARED MergeConsole — byte-identical to the CLI's.
        if verbose {
            for line in MergeConsole.headerLines(
                inputCount: mergeRootPaths.count, output: outputURL.path,
                format: MergeFormat(rawValue: format) ?? .standard,
                level: MergeLevel(rawValue: level) ?? .file,
                sortBy: MergeSortCriteria(rawValue: sortBy) ?? .instanceNumber,
                order: MergeSortOrder(rawValue: order) ?? .ascending,
                options: mergeOptions
            ) {
                appendConsoleOutput(line + "\n")
            }
        }

        let (output, exitCode) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
            var log = ""
            let fm = FileManager.default

            do {
                // Discovery runs through the shared, sorted FrameMerger gatherer — the
                // exact walk the dicom-merge CLI uses.
                let files = try FrameMerger.gatherInputFiles(from: mergeRootPaths, recursive: recursive)
                // "Found N DICOM files" precedes the empty check on the CLI, so a
                // verbose run that finds nothing still reports "Found 0".
                if verbose {
                    log += MergeConsole.foundFilesLines(count: files.count).map { $0 + "\n" }.joined()
                }
                guard !files.isEmpty else {
                    return (log + "Error: \(MergeConsole.noDICOMFilesFoundMessage)\n", 64)
                }

                // Delegate the merge to the shared DICOMKit engine — the exact same
                // FrameMerger the `dicom-merge` CLI uses. Verbose progress flows
                // through the log sink so app and CLI cannot drift.
                let mergeLevel = MergeLevel(rawValue: level) ?? .file
                let merger = FrameMerger(
                    format: MergeFormat(rawValue: format) ?? .standard,
                    level: mergeLevel,
                    sortBy: MergeSortCriteria(rawValue: sortBy) ?? .instanceNumber,
                    order: MergeSortOrder(rawValue: order) ?? .ascending,
                    validate: validate,
                    verbose: verbose,
                    options: mergeOptions,
                    log: { log += $0 + "\n" }
                )

                switch mergeLevel {
                case .file:
                    // Ensure the parent directory exists for a single-file output.
                    try? fm.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try await merger.mergeToSingleFile(files: files, outputPath: outputURL.path)
                case .series:
                    try await merger.mergeBySeries(files: files, outputDirectory: outputURL.path)
                case .study:
                    try await merger.mergeByStudy(files: files, outputDirectory: outputURL.path)
                }

                log += MergeConsole.completionLines().map { $0 + "\n" }.joined()
                return (log, 0)
            } catch let e as MergeError {
                return (log + "Error: \(e.description)\n", 1)
            } catch {
                return (log + "Error: \(error.localizedDescription)\n", 1)
            }
        }.value

        appendConsoleOutput(output)
        addToHistory(toolName: "dicom-merge", command: commandPreview, exitCode: exitCode, output: output)
        consoleStatus = exitCode == 0 ? .success : .error
        service.setConsoleStatus(exitCode == 0 ? .success : .error)
    }

private func executeDicomArchive() async {
    let sub = paramValue("subcommand").isEmpty ? "list" : paramValue("subcommand")

    // Resolve the relevant directory path per subcommand (init uses "path", others "archive").
    let archivePathParam = sub == "init" ? paramValue("path") : paramValue("archive")
    guard !archivePathParam.isEmpty else {
        // ArgumentParser's message for the missing required option (exit 64).
        let msg = sub == "init"
            ? "Error: Missing expected argument '--path <path>'\n"
            : "Error: Missing expected argument '--archive <archive>'\n"
        appendConsoleOutput(msg)
        consoleStatus = .error; service.setConsoleStatus(.error)
        addToHistory(toolName: "dicom-archive", command: commandPreview, exitCode: 64, output: "Missing archive path")
        return
    }

    // The CLI requires --output for export; guard the empty case so an empty path
    // is never resolved to the process CWD and silently exported into.
    if sub == "export" && paramValue("output").isEmpty {
        appendConsoleOutput("Error: Missing expected argument '--output <output>'\n")
        consoleStatus = .error; service.setConsoleStatus(.error)
        addToHistory(toolName: "dicom-archive", command: commandPreview, exitCode: 64, output: "Missing export output directory")
        return
    }

    // Security-scoped access. "init"/"export" may write under "path"/"output";
    // "import" reads from "files". Start access on whatever scoped URLs we have.
    let archiveScopedURL = securityScopedURLs[sub == "init" ? "path" : "archive"]
    let outputScopedURL = securityScopedURLs["output"]
    let filesScopedURL = securityScopedURLs["files"]
    let a1 = archiveScopedURL?.startAccessingSecurityScopedResource() ?? false
    let a2 = outputScopedURL?.startAccessingSecurityScopedResource() ?? false
    let a3 = filesScopedURL?.startAccessingSecurityScopedResource() ?? false
    defer {
        if a1 { archiveScopedURL?.stopAccessingSecurityScopedResource() }
        if a2 { outputScopedURL?.stopAccessingSecurityScopedResource() }
        if a3 { filesScopedURL?.stopAccessingSecurityScopedResource() }
    }

    let archiveURL: URL
    if sub == "init" || sub == "import" {
        // Write subcommands: ensure the archive directory is writable (sandbox/TCC).
        // Read subcommands (list/query/check/stats) must NOT redirect.
        let r = OutputAccess.resolveWritableURL(forPath: archivePathParam, scopedURL: archiveScopedURL, subfolder: "Archive", isDirectory: true)
        if let note = r.note { appendConsoleOutput(note + "\n") }
        archiveURL = r.url
    } else {
        archiveURL = archiveScopedURL ?? URL(fileURLWithPath: archivePathParam)
    }
    let archivePathResolved = archiveURL.path

    // Gather parameter values on the main actor before detaching.
    let force = paramValue("force") == "true"
    let recursive = paramValue("recursive") == "true"
    let skipDuplicates = paramValue("skip-duplicates") == "true"
    let verbose = paramValue("verbose") == "true"
    let format = paramValue("format")
    let showInstances = paramValue("show-instances") == "true"
    let verifyFiles = paramValue("verify-files") == "true"
    let flatten = paramValue("flatten") == "true"
    let filesArg = paramValue("files")
    let filesScopedPath = filesScopedURL?.path
    let outputParam = paramValue("output")
    let outputResolved = (outputScopedURL ?? (outputParam.isEmpty ? nil : URL(fileURLWithPath: outputParam)))?.path ?? outputParam
    let qPatientName = paramValue("patient-name")
    let qPatientID = paramValue("patient-id")
    let qStudyUID = paramValue("study-uid")
    let qSeriesUID = paramValue("series-uid")
    let qModality = paramValue("modality")
    let qStrictModality = paramValue("strict-modality") == "true"
    let qStudyDate = paramValue("study-date")

    let (output, exitCode) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
        // All archive operations are delegated to the shared DICOMKit engine —
        // the exact same ArchiveStore the `dicom-archive` CLI uses, so the app and
        // CLI cannot drift. Sandbox-resolved paths are passed in from the caller.
        var log = ""
        var modality: String? = qModality.isEmpty ? nil : qModality
        if sub == "query" {
            // The CLI's `query` runs the value through the shared DICOMCore
            // ModalityOptionValidator (PS3.3 C.7.3.1.1.1 Defined Terms): a retired,
            // non-standard or unknown code warns on stderr and is sent as-is, or is
            // rejected (exit 1) with --strict-modality; an alias note is printed only
            // with --verbose, which `query` has not.
            if let outcome = ModalityOptionValidator.validate(modality) {
                if let warning = outcome.warning {
                    if qStrictModality, outcome.isStrictFailure {
                        return ("Error: \(warning) Rejected because --strict-modality is set.\n", 1)
                    }
                    if !outcome.isNote {
                        log += "warning: \(warning) Sending it as-is.\n"
                    }
                }
                modality = outcome.value
            }
            // dicom-archive's ArchiveQueryKeys.studyDateWarning (CLI-local, same text): a
            // Study Date that is neither a DA value (PS3.5 Table 6.2-1) nor a DA range
            // (PS3.4 C.2.2.2.5.1) is compared as a literal string.
            if let warning = Self.archiveStudyDateWarning(qStudyDate) {
                log += warning + "\n"
            }
        }
        do {
            let out: String
            switch sub {
            case "init":
                out = try ArchiveStore.initArchive(at: archivePathResolved, force: force)
            case "import":
                // The CLI's <files> is a variadic positional list — the field may hold
                // several semicolon-separated paths (the preview expands the same split
                // into positional tokens). A browsed (security-scoped) file is unioned
                // with the typed paths rather than replacing them.
                var inputs = CommandBuilderHelpers.splitMultiValue(filesArg)
                if let scoped = filesScopedPath, !inputs.contains(scoped) {
                    inputs.append(scoped)
                }
                out = try ArchiveStore.importFiles(
                    into: archivePathResolved, files: inputs,
                    recursive: recursive, skipDuplicates: skipDuplicates, verbose: verbose)
            case "query":
                out = try ArchiveStore.query(
                    in: archivePathResolved,
                    patientName: qPatientName.isEmpty ? nil : qPatientName,
                    patientID: qPatientID.isEmpty ? nil : qPatientID,
                    studyUID: qStudyUID.isEmpty ? nil : qStudyUID,
                    modality: modality,
                    studyDate: qStudyDate.isEmpty ? nil : qStudyDate,
                    format: format.isEmpty ? "table" : format)
            case "list":
                out = try ArchiveStore.list(
                    in: archivePathResolved,
                    format: format.isEmpty ? "tree" : format,
                    showInstances: showInstances)
            case "export":
                out = try ArchiveStore.export(
                    from: archivePathResolved, output: outputResolved,
                    studyUID: qStudyUID.isEmpty ? nil : qStudyUID,
                    seriesUID: qSeriesUID.isEmpty ? nil : qSeriesUID,
                    patientID: qPatientID.isEmpty ? nil : qPatientID,
                    flatten: flatten, verbose: verbose)
            case "check":
                out = try ArchiveStore.check(in: archivePathResolved, verifyFiles: verifyFiles, verbose: verbose)
            case "stats":
                out = try ArchiveStore.stats(in: archivePathResolved, format: format.isEmpty ? "text" : format)
            default:
                return ("Error: Unknown subcommand '\(sub)'.\n", 1)
            }
            return (log + out, 0)
        } catch let error as ArchiveError {
            // dicom-archive rethrows ArchiveError as ArgumentParser's ValidationError (exit 64).
            return (log + "Error: \(error.errorDescription ?? "\(error)")\n", 64)
        } catch {
            return (log + "Error: \(error.localizedDescription)\n", 1)
        }
    }.value

    appendConsoleOutput(output)
    addToHistory(toolName: "dicom-archive", command: commandPreview, exitCode: exitCode, output: output)
    consoleStatus = exitCode == 0 ? .success : .error
    service.setConsoleStatus(exitCode == 0 ? .success : .error)
}

/// `dicom-archive query`'s warning for a `--study-date` that the shared ArchiveStore cannot match
/// as DICOM (its `ArchiveQueryKeys.studyDateWarning`, CLI-local, kept text-identical): neither a
/// DA value (PS3.5 Table 6.2-1: YYYYMMDD) nor a DA range (PS3.4 C.2.2.2.5.1: "<date1>-<date2>",
/// "-<date1>", "<date1>-").
nonisolated static func archiveStudyDateWarning(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    if ArchiveMatching.dateRange(value) != nil { return nil }
    return "warning: --study-date '\(value)' is neither a DA value (YYYYMMDD) nor a DA range "
        + "(PS3.4 C.2.2.2.5.1); it matches only a Study Date (0008,0020) equal to the whole string"
}

private func executeDicomCompress() async {
    let operation = paramValue("operation").isEmpty ? "info" : paramValue("operation")

    switch operation {
    case "compress":
        await executeDicomCompressCompress()
    case "decompress":
        await executeDicomCompressDecompress()
    case "batch":
        await executeDicomCompressBatch()
    case "backends":
        await executeDicomCompressBackends()
    default:
        await executeDicomCompressInfo()
    }
}

// MARK: - dicom-compress display helpers (the compression engine now lives in DICOMKit's CompressionManager)

// dicom-compress input parsing + byte formatting are owned by the shared
// DICOMKit `CompressionConsole` (single source of truth — the CLI uses the same
// helpers) so the Workshop and the CLI never drift. These thin wrappers keep the
// existing call sites readable.
private nonisolated static func dcCompressParseQuality(_ q: String?) throws -> CompressionQuality? {
    try CompressionConsole.parseQuality(q)
}

// MARK: - dicom-compress: info

private func executeDicomCompressInfo() async {
    let inputPath = paramValue("input")
    guard !inputPath.isEmpty else {
        appendConsoleOutput("Error: Input file path is required.\n")
        consoleStatus = .error; service.setConsoleStatus(.error)
        addToHistory(toolName: "dicom-compress", command: commandPreview, exitCode: 1, output: "Missing input path")
        return
    }
    let asJSON = paramValue("json") == "true"
    let inputScopedURL = securityScopedURLs["input"]
    let accessing = inputScopedURL?.startAccessingSecurityScopedResource() ?? false
    defer { if accessing { inputScopedURL?.stopAccessingSecurityScopedResource() } }
    let fileURL = inputScopedURL ?? URL(fileURLWithPath: inputPath)
    let displayPath = inputPath

    let (output, exitCode) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
        do {
            // Extract via the shared DICOMKit engine and render via the shared
            // CompressionConsole builders — the exact code path dicom-compress prints from.
            let data = try Data(contentsOf: fileURL)
            let info = try CompressionManager().getCompressionInfo(data: data)
            if asJSON {
                return (try CompressionConsole.infoJSON(info, filePath: displayPath), 0)
            }
            return (CompressionConsole.infoText(info, filePath: displayPath), 0)
        } catch {
            return (CompressionConsole.infoErrorLine(error), 1)
        }
    }.value

    appendConsoleOutput(output)
    addToHistory(toolName: "dicom-compress", command: commandPreview, exitCode: exitCode, output: output)
    consoleStatus = exitCode == 0 ? .success : .error
    service.setConsoleStatus(exitCode == 0 ? .success : .error)
}

// MARK: - dicom-compress: compress

private func executeDicomCompressCompress() async {
    let inputPath = paramValue("input")
    let outputPath = paramValue("output")
    let codec = paramValue("codec")
    let qualityStr = paramValue("quality")
    let verbose = paramValue("verbose") == "true"
    let backendRaw = paramValue("backend").isEmpty ? "auto" : paramValue("backend")
    // JPEG Baseline encoder choice (JLICodec vs Apple ImageIO). App-only — the CLI has
    // no equivalent flag and always runs the `.jli` default. Unknown/absent → `.jli`,
    // and the engine itself ignores it for every syntax other than JPEG Baseline.
    let jpegEngine = JPEGCodecEngine(rawValue: paramValue("jpegCodec")) ?? .jli

    guard !inputPath.isEmpty else {
        appendConsoleOutput("Error: Input file path is required.\n")
        consoleStatus = .error; service.setConsoleStatus(.error)
        addToHistory(toolName: "dicom-compress", command: commandPreview, exitCode: 1, output: "Missing input path")
        return
    }
    guard !outputPath.isEmpty else {
        appendConsoleOutput("Error: Output file path is required.\n")
        consoleStatus = .error; service.setConsoleStatus(.error)
        addToHistory(toolName: "dicom-compress", command: commandPreview, exitCode: 1, output: "Missing output path")
        return
    }
    guard CompressionManager.transferSyntax(for: codec) != nil else {
        let msg = "Error: Unknown codec '\(codec)'.\n"
        appendConsoleOutput(msg)
        consoleStatus = .error; service.setConsoleStatus(.error)
        addToHistory(toolName: "dicom-compress", command: commandPreview, exitCode: 1, output: msg)
        return
    }

    let inputScopedURL = securityScopedURLs["input"]
    let outputScopedURL = securityScopedURLs["output"]
    let accessingIn = inputScopedURL?.startAccessingSecurityScopedResource() ?? false
    let accessingOut = outputScopedURL?.startAccessingSecurityScopedResource() ?? false
    defer {
        if accessingIn { inputScopedURL?.stopAccessingSecurityScopedResource() }
        if accessingOut { outputScopedURL?.stopAccessingSecurityScopedResource() }
    }
    let inputURL = inputScopedURL ?? URL(fileURLWithPath: inputPath)
    // Shared backend resolution (same helper the CLI uses) — the preference is
    // both displayed AND forwarded into the engine (J2K/HTJ2K honor metal→GPU).
    // Report the backend selected for this codec's encode step, not merely the
    // best available hardware. Auto uses Metal for lossy and lossless J2K/HTJ2K
    // when Metal is available; forced Metal is downgraded only when unavailable
    // or when the target codec has no GPU encode path.
    let backendPref = CompressionConsole.backendPreference(for: backendRaw)
    let resolvedBackend = CompressionConsole.compressBackend(codec: codec, preference: backendPref)
    let backendName = resolvedBackend.displayName
    let backendNote = resolvedBackend.note
    // The JPEG engine choice only changes the encoder for JPEG Baseline; for every other
    // target the registry ignores it, so don't claim it applied.
    let appliesJPEGEngine =
        CompressionManager.transferSyntax(for: codec)?.uid == CodecRegistry.jpegEngineSelectableUID

    let (output, exitCode) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
        var log = ""
        do {
            let quality = try CompressionConsole.parseQuality(qualityStr)
            let inputData = try Data(contentsOf: inputURL)

            // Detect recompression (source already compressed → target also a
            // compressed syntax, so the engine decodes to native pixels then
            // re-encodes). Detection lives once in CompressionManager so the
            // Workshop and the CLI agree without re-deriving it.
            let sourceInfo = try? CompressionManager().getCompressionInfo(data: inputData)
            let isRecompression = CompressionManager.isRecompression(
                sourceInfo: sourceInfo, targetCodec: codec, quality: quality)
            let sourceCodecName = isRecompression ? sourceInfo?.transferSyntaxName : nil

            // All console text comes from the shared DICOMKit CompressionConsole so
            // the Workshop and the CLI render byte-for-byte identical output.
            if verbose {
                log += CompressionConsole.compressPreamble(
                    input: inputPath, codec: codec, quality: qualityStr, backendDisplayName: backendName,
                    sourceTransferSyntaxName: sourceCodecName, backendNote: backendNote)
            } else if let name = sourceCodecName {
                log += CompressionConsole.recompressNoteLine(sourceName: name)
            }

            // The JPEG engine is a Workshop-only encoder choice with no CLI counterpart,
            // so its note is emitted HERE rather than in the shared CompressionConsole —
            // and only for the non-default `.native` engine, which keeps every default
            // run byte-for-byte identical to `dicom-compress` output.
            if jpegEngine != .jli, appliesJPEGEngine {
                log += "JPEG engine: \(jpegEngine.displayName)\n"
            }

            // Compress via the shared DICOMKit engine (same code the CLI runs). The
            // engine returns per-phase metrics — a recompression is timed/sized as a
            // decompress phase + a compress phase — and the console text is derived from
            // them in DICOMKit core so the Workshop and CLI stay byte-for-byte identical.
            let (outputData, metrics) = try CompressionManager().compressDataWithMetrics(
                inputData, codec: codec, quality: quality, sourceInfo: sourceInfo,
                backend: backendPref, jpegEngine: jpegEngine)

            // Sandbox/TCC-resilient write (prefer scoped URL; else fall back to ~/Downloads).
            let writeRes = try OutputAccess.write(outputData, toPath: outputPath, scopedURL: outputScopedURL, subfolder: "Compressed")
            if let note = writeRes.note { log += note + "\n" }
            log += CompressionConsole.compressResultLine(input: inputPath, output: writeRes.url.path)
            if verbose {
                log += CompressionConsole.compressStats(inputSize: metrics.inputSize, intermediateSize: metrics.intermediateSize, outputSize: metrics.outputSize, decompressElapsed: metrics.decompressElapsed, compressElapsed: metrics.compressElapsed)
            } else {
                log += CompressionConsole.compressSummary(inputSize: metrics.inputSize, intermediateSize: metrics.intermediateSize, outputSize: metrics.outputSize, decompressElapsed: metrics.decompressElapsed, compressElapsed: metrics.compressElapsed)
            }
            return (log, 0)
        } catch {
            log += "Error: \(error.localizedDescription)\n"
            return (log, 1)
        }
    }.value

    appendConsoleOutput(output)
    addToHistory(toolName: "dicom-compress", command: commandPreview, exitCode: exitCode, output: output)
    consoleStatus = exitCode == 0 ? .success : .error
    service.setConsoleStatus(exitCode == 0 ? .success : .error)
}

// MARK: - dicom-compress: decompress

private func executeDicomCompressDecompress() async {
    let inputPath = paramValue("input")
    let outputPath = paramValue("output")
    let syntax = paramValue("syntax").isEmpty ? "explicit-le" : paramValue("syntax")
    let verbose = paramValue("verbose") == "true"

    guard !inputPath.isEmpty else {
        appendConsoleOutput("Error: Input file path is required.\n")
        consoleStatus = .error; service.setConsoleStatus(.error)
        addToHistory(toolName: "dicom-compress", command: commandPreview, exitCode: 1, output: "Missing input path")
        return
    }
    guard !outputPath.isEmpty else {
        appendConsoleOutput("Error: Output file path is required.\n")
        consoleStatus = .error; service.setConsoleStatus(.error)
        addToHistory(toolName: "dicom-compress", command: commandPreview, exitCode: 1, output: "Missing output path")
        return
    }
    guard let targetSyntax = CompressionManager.transferSyntax(for: syntax) else {
        let msg = "Error: Unknown syntax '\(syntax)'. Use explicit-le or implicit-le.\n"
        appendConsoleOutput(msg)
        consoleStatus = .error; service.setConsoleStatus(.error)
        addToHistory(toolName: "dicom-compress", command: commandPreview, exitCode: 1, output: msg)
        return
    }

    let inputScopedURL = securityScopedURLs["input"]
    let outputScopedURL = securityScopedURLs["output"]
    let accessingIn = inputScopedURL?.startAccessingSecurityScopedResource() ?? false
    let accessingOut = outputScopedURL?.startAccessingSecurityScopedResource() ?? false
    defer {
        if accessingIn { inputScopedURL?.stopAccessingSecurityScopedResource() }
        if accessingOut { outputScopedURL?.stopAccessingSecurityScopedResource() }
    }
    let inputURL = inputScopedURL ?? URL(fileURLWithPath: inputPath)
    let targetName = CompressionManager.transferSyntaxDisplayName(targetSyntax)

    let (output, exitCode) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
        var log = ""
        do {
            if verbose {
                log += CompressionConsole.decompressPreamble(input: inputPath, targetSyntaxName: targetName)
            }
            let inputData = try Data(contentsOf: inputURL)
            // Decompress via the shared DICOMKit engine (same code the CLI runs).
            let start = Date()
            let outputData = try CompressionManager().decompressData(inputData, syntax: targetSyntax)
            let elapsed = Date().timeIntervalSince(start)
            let writeRes = try OutputAccess.write(outputData, toPath: outputPath, scopedURL: outputScopedURL, subfolder: "Decompressed")
            if let note = writeRes.note { log += note + "\n" }
            log += CompressionConsole.decompressResultLine(input: inputPath, output: writeRes.url.path)
            if verbose {
                log += CompressionConsole.decompressStats(inputSize: inputData.count, outputSize: outputData.count, elapsed: elapsed)
            } else {
                log += CompressionConsole.decompressSummary(inputSize: inputData.count, outputSize: outputData.count, elapsed: elapsed)
            }
            return (log, 0)
        } catch {
            log += "Error: \(error.localizedDescription)\n"
            return (log, 1)
        }
    }.value

    appendConsoleOutput(output)
    addToHistory(toolName: "dicom-compress", command: commandPreview, exitCode: exitCode, output: output)
    consoleStatus = exitCode == 0 ? .success : .error
    service.setConsoleStatus(exitCode == 0 ? .success : .error)
}

// MARK: - dicom-compress: batch

private func executeDicomCompressBatch() async {
    let inputDir = paramValue("inputDir")
    let outputDir = paramValue("outputDir")
    let codec = paramValue("batchCodec")
    let decompress = paramValue("decompress") == "true"
    let qualityStr = paramValue("quality")
    let syntax = paramValue("syntax").isEmpty ? "explicit-le" : paramValue("syntax")
    let recursive = paramValue("recursive") == "true"
    let verbose = paramValue("verbose") == "true"

    guard !inputDir.isEmpty else {
        appendConsoleOutput("Error: Input directory is required.\n")
        consoleStatus = .error; service.setConsoleStatus(.error)
        addToHistory(toolName: "dicom-compress", command: commandPreview, exitCode: 1, output: "Missing input directory")
        return
    }
    guard !outputDir.isEmpty else {
        appendConsoleOutput("Error: Output directory is required.\n")
        consoleStatus = .error; service.setConsoleStatus(.error)
        addToHistory(toolName: "dicom-compress", command: commandPreview, exitCode: 1, output: "Missing output directory")
        return
    }
    if !decompress && codec.trimmingCharacters(in: .whitespaces).isEmpty {
        let msg = "Error: Specify --codec for compression or enable Decompress for decompression.\n"
        appendConsoleOutput(msg)
        consoleStatus = .error; service.setConsoleStatus(.error)
        addToHistory(toolName: "dicom-compress", command: commandPreview, exitCode: 1, output: msg)
        return
    }
    if !codec.trimmingCharacters(in: .whitespaces).isEmpty, CompressionManager.transferSyntax(for: codec) == nil {
        let msg = "Error: Unknown codec '\(codec)'.\n"
        appendConsoleOutput(msg)
        consoleStatus = .error; service.setConsoleStatus(.error)
        addToHistory(toolName: "dicom-compress", command: commandPreview, exitCode: 1, output: msg)
        return
    }

    let inputScopedURL = securityScopedURLs["inputDir"]
    let outputScopedURL = securityScopedURLs["outputDir"]
    let accessingIn = inputScopedURL?.startAccessingSecurityScopedResource() ?? false
    let accessingOut = outputScopedURL?.startAccessingSecurityScopedResource() ?? false
    defer {
        if accessingIn { inputScopedURL?.stopAccessingSecurityScopedResource() }
        if accessingOut { outputScopedURL?.stopAccessingSecurityScopedResource() }
    }
    let inputBase = inputScopedURL ?? URL(fileURLWithPath: inputDir)
    let outputBase = outputScopedURL ?? URL(fileURLWithPath: outputDir)

    let (output, exitCode) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
        var log = ""
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: outputBase, withIntermediateDirectories: true)
            let quality = try CompressionConsole.parseQuality(qualityStr)

            // Discover DICOM files via the shared CompressionManager finder — the
            // exact call the dicom-compress CLI batch path makes, so both surfaces
            // use one detection heuristic and one (sorted) ordering.
            let files = (try CompressionManager.findDICOMFiles(in: inputBase.path, recursive: recursive))
                .map { URL(fileURLWithPath: $0) }

            if files.isEmpty {
                log += "No DICOM files found in: \(inputDir)\n"
                return (log, 1)
            }
            log += CompressionConsole.batchFoundLine(count: files.count)

            let basePath = inputBase.path
            var successCount = 0
            var failCount = 0
            for fileURL in files {
                let filePath = fileURL.path
                let relativePath: String
                if filePath.hasPrefix(basePath) {
                    var rel = String(filePath.dropFirst(basePath.count))
                    if rel.hasPrefix("/") { rel = String(rel.dropFirst()) }
                    relativePath = rel.isEmpty ? fileURL.lastPathComponent : rel
                } else {
                    relativePath = fileURL.lastPathComponent
                }
                let outURL = outputBase.appendingPathComponent(relativePath)
                do {
                    try fm.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let inputData = try Data(contentsOf: fileURL)
                    // Compress/decompress via the shared DICOMKit engine.
                    let outputData: Data
                    if decompress {
                        let target = CompressionManager.transferSyntax(for: syntax) ?? .explicitVRLittleEndian
                        outputData = try CompressionManager().decompressData(inputData, syntax: target)
                    } else {
                        outputData = try CompressionManager().compressData(inputData, codec: codec, quality: quality)
                    }
                    try outputData.write(to: outURL)
                    successCount += 1
                    if verbose { log += CompressionConsole.batchProgressLine(success: true, relativePath: relativePath, error: nil) }
                } catch {
                    failCount += 1
                    if verbose { log += CompressionConsole.batchProgressLine(success: false, relativePath: relativePath, error: "\(error)") }
                }
            }
            log += CompressionConsole.batchSummaryLine(
                decompress: decompress, success: successCount, fail: failCount, total: files.count)
            return (log, failCount > 0 ? 1 : 0)
        } catch {
            log += "Error: \(error.localizedDescription)\n"
            return (log, 1)
        }
    }.value

    appendConsoleOutput(output)
    addToHistory(toolName: "dicom-compress", command: commandPreview, exitCode: exitCode, output: output)
    consoleStatus = exitCode == 0 ? .success : .error
    service.setConsoleStatus(exitCode == 0 ? .success : .error)
}

// MARK: - dicom-compress: backends

private func executeDicomCompressBackends() async {
    let asJSON = paramValue("json") == "true"
    let (output, exitCode) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
        // Shared CompressionConsole builders — the exact code path dicom-compress prints from.
        if asJSON {
            return ((try? CompressionConsole.backendsJSON()) ?? "[]\n", 0)
        }
        return (CompressionConsole.backendsText(), 0)
    }.value

    appendConsoleOutput(output)
    addToHistory(toolName: "dicom-compress", command: commandPreview, exitCode: exitCode, output: output)
    consoleStatus = exitCode == 0 ? .success : .error
    service.setConsoleStatus(exitCode == 0 ? .success : .error)
}

private func executeDicomStudy() async {
        let operation = paramValue("operation").isEmpty ? "organize" : paramValue("operation")

        switch operation {
        case "organize": await executeDicomStudyOrganize()
        case "summary":  await executeDicomStudySummary()
        case "check":    await executeDicomStudyCheck()
        case "stats":    await executeDicomStudyStats()
        case "compare":  await executeDicomStudyCompare()
        default:
            appendConsoleOutput("Error: Unknown operation '\(operation)'.\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-study", command: commandPreview, exitCode: 1, output: "Unknown operation")
        }
    }

    // MARK: - dicom-study : organize

    private func executeDicomStudyOrganize() async {
        let input = paramValue("input")
        let output = paramValue("output")
        // ArgumentParser's messages for the missing positional / required option (exit 64).
        guard !input.isEmpty else {
            appendConsoleOutput("Error: Missing expected argument '<input>'\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-study", command: commandPreview, exitCode: 64, output: "Missing input")
            return
        }
        guard !output.isEmpty else {
            appendConsoleOutput("Error: Missing expected argument '--output <output>'\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-study", command: commandPreview, exitCode: 64, output: "Missing output")
            return
        }
        let pattern = paramValue("pattern").isEmpty ? "descriptive" : paramValue("pattern")
        let copy = paramValue("copy") == "true"
        let verbose = paramValue("verbose") == "true"

        let inputScoped = securityScopedURLs["input"] ?? securityScopedURLs["inputPath"]
        let outputScoped = securityScopedURLs["output"]
        let aIn = inputScoped?.startAccessingSecurityScopedResource() ?? false
        let aOut = outputScoped?.startAccessingSecurityScopedResource() ?? false
        defer {
            if aIn { inputScoped?.stopAccessingSecurityScopedResource() }
            if aOut { outputScoped?.stopAccessingSecurityScopedResource() }
        }
        let inputURL = inputScoped ?? URL(fileURLWithPath: input)
        // Sandbox/TCC-resilient output directory (organize writes a folder tree).
        let _orgOut = OutputAccess.resolveWritableURL(forPath: output, scopedURL: outputScoped, subfolder: "StudyOrganize", isDirectory: true)
        let outputURL = _orgOut.url
        if let note = _orgOut.note { appendConsoleOutput(note + "\n") }

        let (output_, exitCode) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
            var log = ""
            do {
                // Organize via the shared DICOMKit StudyOrganizer — identical file
                // naming/ordering and the same copy/move "already exists" error as the
                // CLI (Sources/DICOMKit/Study/StudyOrganizer.swift). Output is written
                // under the sandbox-resolved outputURL.
                try StudyOrganizer().organize(
                    inputPath: inputURL.path, outputPath: outputURL.path,
                    pattern: pattern, copy: copy, verbose: verbose,
                    log: { log += $0 + "\n" })
                return (log, 0)
            } catch let e as StudyError {
                return (log + "Error: \(e.errorDescription ?? "\(e)")\n", 1)
            } catch {
                return (log + "Error: \(error.localizedDescription)\n", 1)
            }
        }.value

        appendConsoleOutput(output_)
        addToHistory(toolName: "dicom-study", command: commandPreview, exitCode: exitCode, output: output_)
        consoleStatus = exitCode == 0 ? .success : .error
        service.setConsoleStatus(exitCode == 0 ? .success : .error)
    }

    // MARK: - dicom-study : summary

    private func executeDicomStudySummary() async {
        let path = paramValue("path")
        guard !path.isEmpty else {
            appendConsoleOutput("Error: Missing expected argument '<path>'\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-study", command: commandPreview, exitCode: 64, output: "Missing path")
            return
        }
        let format = paramValue("summary-format").isEmpty ? "table" : paramValue("summary-format")
        let verbose = paramValue("verbose") == "true"

        let scoped = securityScopedURLs["path"] ?? securityScopedURLs["inputPath"]
        let accessing = scoped?.startAccessingSecurityScopedResource() ?? false
        defer { if accessing { scoped?.stopAccessingSecurityScopedResource() } }
        let pathURL = scoped ?? URL(fileURLWithPath: path)

        let (output, exitCode) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
            guard FileManager.default.fileExists(atPath: pathURL.path) else {
                return ("Error: Directory not found: \(pathURL.path)\n", 1)
            }
            let studies = StudyScanner.scanStudies(at: pathURL.path)
            if studies.isEmpty { return ("Error: No DICOM files found in the specified directory\n", 1) }
            // Render via the shared DICOMKit engine — same code the CLI uses.
            do {
                let out = try StudyReport.renderSummary(studies: studies, format: format, verbose: verbose)
                return (out, 0)
            } catch {
                return ("Error: Invalid format: \(format). Use 'table', 'json', or 'csv'\n", 1)
            }
        }.value

        appendConsoleOutput(output)
        addToHistory(toolName: "dicom-study", command: commandPreview, exitCode: exitCode, output: output)
        consoleStatus = exitCode == 0 ? .success : .error
        service.setConsoleStatus(exitCode == 0 ? .success : .error)
    }

    // MARK: - dicom-study : check

    private func executeDicomStudyCheck() async {
        let path = paramValue("path")
        guard !path.isEmpty else {
            appendConsoleOutput("Error: Missing expected argument '<path>'\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-study", command: commandPreview, exitCode: 64, output: "Missing path")
            return
        }
        let expectedSeries = Int(paramValue("expected-series"))
        let expectedInstances = Int(paramValue("expected-instances"))
        let reportPath = paramValue("report")
        let verbose = paramValue("verbose") == "true"

        let scoped = securityScopedURLs["path"] ?? securityScopedURLs["inputPath"]
        let reportScoped = securityScopedURLs["report"] ?? securityScopedURLs["output"]
        let accessing = scoped?.startAccessingSecurityScopedResource() ?? false
        let accessingReport = reportScoped?.startAccessingSecurityScopedResource() ?? false
        defer {
            if accessing { scoped?.stopAccessingSecurityScopedResource() }
            if accessingReport { reportScoped?.stopAccessingSecurityScopedResource() }
        }
        let pathURL = scoped ?? URL(fileURLWithPath: path)
        let reportURL: URL? = reportPath.isEmpty ? nil : (reportScoped ?? URL(fileURLWithPath: reportPath))

        let (output, exitCode) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
            guard FileManager.default.fileExists(atPath: pathURL.path) else {
                return ("Error: Directory not found: \(pathURL.path)\n", 1)
            }
            var out = ""
            if verbose { out += "Checking study completeness: \(pathURL.path)\n" }
            let studies = StudyScanner.scanStudies(at: pathURL.path)
            guard let study = studies.first else {
                return (out + "Error: No DICOM files found in the specified directory\n", 1)
            }
            // Evaluate via the shared DICOMKit engine — same code the CLI uses.
            let result = StudyReport.evaluateCompleteness(
                study: study, expectedSeries: expectedSeries, expectedInstances: expectedInstances)
            let issues = result.issues
            out += result.output

            if let reportURL = reportURL {
                let report = issues.joined(separator: "\n")
                // Sandbox/TCC-resilient: prefer the scoped URL; else try the typed path;
                // on failure fall back to ~/Downloads/DICOMStudio and note the redirect.
                do {
                    let res = try OutputAccess.writeString(report, toPath: reportURL.path,
                                                           scopedURL: reportScoped, subfolder: "StudyCheck")
                    out += "Report written to: \(res.url.path)\n"
                    if let note = res.note { out += note + "\n" }
                } catch {
                    return (out + "Error: Write error: \(error.localizedDescription)\n", 1)
                }
            }
            return (out, 0)
        }.value

        appendConsoleOutput(output)
        addToHistory(toolName: "dicom-study", command: commandPreview, exitCode: exitCode, output: output)
        consoleStatus = exitCode == 0 ? .success : .error
        service.setConsoleStatus(exitCode == 0 ? .success : .error)
    }

    // MARK: - dicom-study : stats

    private func executeDicomStudyStats() async {
        let path = paramValue("path")
        guard !path.isEmpty else {
            appendConsoleOutput("Error: Missing expected argument '<path>'\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-study", command: commandPreview, exitCode: 64, output: "Missing path")
            return
        }
        let detailed = paramValue("detailed") == "true"
        let format = paramValue("stats-format").isEmpty ? "text" : paramValue("stats-format")

        let scoped = securityScopedURLs["path"] ?? securityScopedURLs["inputPath"]
        let accessing = scoped?.startAccessingSecurityScopedResource() ?? false
        defer { if accessing { scoped?.stopAccessingSecurityScopedResource() } }
        let pathURL = scoped ?? URL(fileURLWithPath: path)

        let (output, exitCode) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
            guard FileManager.default.fileExists(atPath: pathURL.path) else {
                return ("Error: Directory not found: \(pathURL.path)\n", 1)
            }
            let studies = StudyScanner.scanStudies(at: pathURL.path)
            guard let study = studies.first else {
                return ("Error: No DICOM files found in the specified directory\n", 1)
            }
            // Compute + render via the shared DICOMKit engine — same code as the CLI.
            let stats = StudyReport.computeStatistics(for: study, detailed: detailed)
            do {
                let out = try StudyReport.renderStats(stats, detailed: detailed, format: format)
                return (out, 0)
            } catch {
                return ("Error: Failed to encode JSON\n", 1)
            }
        }.value

        appendConsoleOutput(output)
        addToHistory(toolName: "dicom-study", command: commandPreview, exitCode: exitCode, output: output)
        consoleStatus = exitCode == 0 ? .success : .error
        service.setConsoleStatus(exitCode == 0 ? .success : .error)
    }

    // MARK: - dicom-study : compare

    private func executeDicomStudyCompare() async {
        let path1 = paramValue("path1")
        let path2 = paramValue("path2")
        guard !path1.isEmpty, !path2.isEmpty else {
            appendConsoleOutput("Error: Missing expected argument '\(path1.isEmpty ? "<path1>" : "<path2>")'\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-study", command: commandPreview, exitCode: 64, output: "Missing path")
            return
        }
        let format = paramValue("compare-format").isEmpty ? "text" : paramValue("compare-format")
        let verbose = paramValue("verbose") == "true"

        let scoped1 = securityScopedURLs["path1"] ?? securityScopedURLs["inputPath"]
        let scoped2 = securityScopedURLs["path2"]
        let a1 = scoped1?.startAccessingSecurityScopedResource() ?? false
        let a2 = scoped2?.startAccessingSecurityScopedResource() ?? false
        defer {
            if a1 { scoped1?.stopAccessingSecurityScopedResource() }
            if a2 { scoped2?.stopAccessingSecurityScopedResource() }
        }
        let url1 = scoped1 ?? URL(fileURLWithPath: path1)
        let url2 = scoped2 ?? URL(fileURLWithPath: path2)

        let (output, exitCode) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
            guard FileManager.default.fileExists(atPath: url1.path) else {
                return ("Error: Directory not found: \(url1.path)\n", 1)
            }
            guard FileManager.default.fileExists(atPath: url2.path) else {
                return ("Error: Directory not found: \(url2.path)\n", 1)
            }
            let studies1 = StudyScanner.scanStudies(at: url1.path)
            let studies2 = StudyScanner.scanStudies(at: url2.path)
            guard let s1 = studies1.first else { return ("Error: No DICOM files found in the specified directory\n", 1) }
            guard let s2 = studies2.first else { return ("Error: No DICOM files found in the specified directory\n", 1) }
            // Compare + render via the shared DICOMKit engine — same code as the CLI.
            let cmp = StudyReport.compareStudies(s1, s2)
            do {
                let out = try StudyReport.renderComparison(cmp, format: format, verbose: verbose)
                return (out, 0)
            } catch {
                return ("Error: Failed to encode JSON\n", 1)
            }
        }.value

        appendConsoleOutput(output)
        addToHistory(toolName: "dicom-study", command: commandPreview, exitCode: exitCode, output: output)
        consoleStatus = exitCode == 0 ? .success : .error
        service.setConsoleStatus(exitCode == 0 ? .success : .error)
    }

    // MARK: - dicom-video Execution

    /// Routes to the `dicom-video` subcommand the form selected.
    ///
    /// Every one of these runs DICOMKit's shared `VideoWorkflow` engine and
    /// renders through the shared `VideoConsole`, which the `dicom-video` CLI
    /// also uses — so the two surfaces emit the same text for the same input.
    /// What lives here is only the adapter's business: reading the form,
    /// security-scoped input access, and writing through `OutputAccess`.
    private func executeDicomVideo() async {
        let operation = paramValue("operation").isEmpty ? "convert" : paramValue("operation")

        switch operation {
        case "probe":
            await executeDicomVideoProbe()
        case "extract":
            await executeDicomVideoExtract()
        case "batch":
            await executeDicomVideoBatch()
        default:
            await executeDicomVideoConvert()
        }
    }

    /// Reads the patient/study/series fields the form collects for convert and
    /// batch. An empty field is left `nil` so the engine emits the Type 2
    /// attribute zero-length, exactly as an omitted CLI flag does.
    private func dicomVideoMetadata() -> VideoWorkflow.Metadata {
        func optional(_ id: String) -> String? {
            let value = paramValue(id).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return VideoWorkflow.Metadata(
            patientName: optional("patientName"),
            patientID: optional("patientID"),
            patientBirthDate: optional("patientBirthDate"),
            patientSex: optional("patientSex"),
            studyUID: optional("studyUID"),
            seriesUID: optional("seriesUID"),
            accessionNumber: optional("accessionNumber"),
            studyID: optional("studyID"),
            referringPhysician: optional("referringPhysician"),
            seriesDescription: optional("seriesDescription"),
            modality: optional("modality"),
            manufacturer: optional("manufacturer"),
            institutionName: optional("institutionName")
        )
    }

    /// Finishes a `dicom-video` run: prints, records history and sets status.
    ///
    /// Exit code 2 is a conformance rejection — the input was understood and
    /// found not DICOM-legal — so it is surfaced as an error status just like
    /// exit 1, while the console keeps the engine's specific explanation.
    private func finishDicomVideo(output: String, exitCode: VideoConsole.ExitCode) {
        var text = output
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        appendConsoleOutput(text)
        addToHistory(toolName: "dicom-video", command: commandPreview,
                     exitCode: Int(exitCode.rawValue), output: text)
        let status: CLIConsoleStatus = exitCode == .success ? .success : .error
        consoleStatus = status
        service.setConsoleStatus(status)
    }

    /// Reports a missing required form field the way the CLI's ArgumentParser
    /// would report the same omission.
    private func failDicomVideoMissing(_ message: String) {
        finishDicomVideo(output: "Error: \(message)", exitCode: .inputError)
    }

    // MARK: - dicom-video: convert

    private func executeDicomVideoConvert() async {
        let inputPath = paramValue("input")
        let typedOutputPath = paramValue("output")
        guard !inputPath.isEmpty else {
            failDicomVideoMissing("Input video path is required.")
            return
        }
        guard !typedOutputPath.isEmpty else {
            failDicomVideoMissing("Output DICOM file path is required.")
            return
        }
        // A folder picker hands back a directory; writing to it literally would
        // collide with the folder itself and report a name clash for a clip that
        // converts perfectly. Same resolution the CLI does, so both surfaces name
        // the object identically.
        let outputPath = VideoWorkflow.resolveOutputURL(
            output: typedOutputPath,
            input: URL(fileURLWithPath: inputPath),
            fileExtension: "dcm",
            isDirectory: { path in
                var isDirectory: ObjCBool = false
                let exists = FileManager.default.fileExists(
                    atPath: path, isDirectory: &isDirectory)
                return exists && isDirectory.boolValue
            }
        ).url.path

        // An unparseable numeric field is reported with ArgumentParser's own two
        // lines, which is what the CLI prints for the same typed value.
        let frameRateRaw = paramValue("frameRate").trimmingCharacters(in: .whitespaces)
        var frameRate: Double?
        if !frameRateRaw.isEmpty {
            guard let parsed = Double(frameRateRaw) else {
                finishDicomVideo(output: VideoConsole.invalidFrameRateLine(frameRateRaw),
                                 exitCode: .inputError)
                return
            }
            frameRate = parsed
        }

        let typeRaw = paramValue("type").trimmingCharacters(in: .whitespaces)
        var type: VideoConsole.TypeArgument = .endoscopic
        if !typeRaw.isEmpty {
            guard let parsed = VideoConsole.TypeArgument(rawValue: typeRaw) else {
                finishDicomVideo(output: VideoConsole.invalidTypeLine(typeRaw),
                                 exitCode: .inputError)
                return
            }
            type = parsed
        }

        let instanceNumber = Int(paramValue("instanceNumber")) ?? 1
        let seriesNumber = Int(paramValue("seriesNumber")) ?? 1
        let transferSyntaxRaw = paramValue("transferSyntax").trimmingCharacters(in: .whitespaces)
        let dryRun = paramValue("dryRun") == "true"
        let trustInput = paramValue("trustInput") == "true"
        let force = paramValue("force") == "true"
        let verbose = paramValue("verbose") == "true"
        let metadata = dicomVideoMetadata()
        let typeWasExplicit = !typeRaw.isEmpty

        let inputScopedURL = securityScopedURLs["input"]
        let outputScopedURL = securityScopedURLs["output"]
        let accessingIn = inputScopedURL?.startAccessingSecurityScopedResource() ?? false
        defer { if accessingIn { inputScopedURL?.stopAccessingSecurityScopedResource() } }
        let inputURL = inputScopedURL ?? URL(fileURLWithPath: inputPath)

        let (output, exitCode) = await Task.detached(priority: .userInitiated) {
            () -> (String, VideoConsole.ExitCode) in
            guard let bitstream = FileManager.default.contents(atPath: inputURL.path) else {
                return (VideoConsole.cannotReadLine(inputPath), .inputError)
            }

            let outcome: VideoWorkflow.ConvertOutcome
            do {
                outcome = try VideoWorkflow.convert(
                    bitstream: bitstream,
                    type: type,
                    typeWasExplicit: typeWasExplicit,
                    explicitTransferSyntax: transferSyntaxRaw.isEmpty ? nil : transferSyntaxRaw,
                    trustInput: trustInput,
                    frameRateOverride: frameRate,
                    dryRun: dryRun,
                    verbose: verbose,
                    metadata: metadata,
                    seriesNumber: seriesNumber,
                    instanceNumber: instanceNumber
                )
            } catch let verboseFailure as VideoWorkflow.VerboseFailure {
                // Verbose commentary precedes the rejection it explains, the
                // same order the CLI writes the two to stderr.
                return (verboseFailure.combinedMessage, verboseFailure.exitCode)
            } catch let failure as VideoWorkflow.Failure {
                return (failure.message, failure.exitCode)
            } catch {
                return (error.localizedDescription, .inputError)
            }

            var lines: [String] = []
            if !outcome.output.isEmpty { lines.append(outcome.output) }

            let report = VideoConsole.describe(
                outcome.plan.probe, transferSyntax: outcome.plan.transferSyntax)

            if dryRun {
                lines.append(report)
                lines.append(VideoConsole.dryRunTrailer)
                return (lines.joined(separator: "\n"), .success)
            }

            // The sandbox check mirrors the CLI's: refuse an existing file unless
            // --force. Only the typed path is checked, because that is what the
            // user named; a redirect lands somewhere they have not claimed.
            if outputScopedURL == nil,
               FileManager.default.fileExists(atPath: outputPath), !force {
                lines.append(VideoConsole.outputExistsLine(outputPath))
                return (lines.joined(separator: "\n"), .inputError)
            }

            guard let data = outcome.data else {
                lines.append(VideoConsole.cannotWriteLine(outputPath, reason: "nothing was built"))
                return (lines.joined(separator: "\n"), .inputError)
            }

            do {
                let written = try OutputAccess.write(
                    data, toPath: outputPath, scopedURL: outputScopedURL, subfolder: "Video")
                if let note = written.note { lines.append(note) }
                lines.append(VideoConsole.wroteLine(written.url.path))
            } catch {
                lines.append(VideoConsole.cannotWriteLine(
                    outputPath, reason: error.localizedDescription))
                return (lines.joined(separator: "\n"), .inputError)
            }

            lines.append(report)
            return (lines.joined(separator: "\n"), .success)
        }.value

        finishDicomVideo(output: output, exitCode: exitCode)
    }

    // MARK: - dicom-video: probe

    private func executeDicomVideoProbe() async {
        let inputPath = paramValue("input")
        guard !inputPath.isEmpty else {
            failDicomVideoMissing("Input video path is required.")
            return
        }
        let trustInput = paramValue("trustInput") == "true"
        let verbose = paramValue("verbose") == "true"

        let inputScopedURL = securityScopedURLs["input"]
        let accessing = inputScopedURL?.startAccessingSecurityScopedResource() ?? false
        defer { if accessing { inputScopedURL?.stopAccessingSecurityScopedResource() } }
        let inputURL = inputScopedURL ?? URL(fileURLWithPath: inputPath)

        let (output, exitCode) = await Task.detached(priority: .userInitiated) {
            () -> (String, VideoConsole.ExitCode) in
            guard let bitstream = FileManager.default.contents(atPath: inputURL.path) else {
                return (VideoConsole.cannotReadLine(inputPath), .inputError)
            }
            do {
                let outcome = try VideoWorkflow.probe(
                    bitstream: bitstream, trustInput: trustInput, verbose: verbose)
                // One console here, so the CLI's two streams are shown together,
                // commentary first — exactly as a terminal interleaves them.
                guard !outcome.diagnostics.isEmpty else {
                    return (outcome.output, outcome.exitCode)
                }
                return (outcome.diagnostics + "\n" + outcome.output, outcome.exitCode)
            } catch let failure as VideoWorkflow.Failure {
                return (failure.message, failure.exitCode)
            } catch {
                return (error.localizedDescription, .inputError)
            }
        }.value

        finishDicomVideo(output: output, exitCode: exitCode)
    }

    // MARK: - dicom-video: extract

    private func executeDicomVideoExtract() async {
        let inputPath = paramValue("dicomInput")
        let typedOutputPath = paramValue("videoOutput")
        guard !inputPath.isEmpty else {
            failDicomVideoMissing("Input DICOM file path is required.")
            return
        }
        guard !typedOutputPath.isEmpty else {
            failDicomVideoMissing("Output video file path is required.")
            return
        }
        let force = paramValue("force") == "true"
        let verbose = paramValue("verbose") == "true"

        let inputScopedURL = securityScopedURLs["dicomInput"]
        let outputScopedURL = securityScopedURLs["videoOutput"]
        let accessing = inputScopedURL?.startAccessingSecurityScopedResource() ?? false
        defer { if accessing { inputScopedURL?.stopAccessingSecurityScopedResource() } }
        let inputURL = inputScopedURL ?? URL(fileURLWithPath: inputPath)

        let (output, exitCode) = await Task.detached(priority: .userInitiated) {
            () -> (String, VideoConsole.ExitCode) in
            guard let data = FileManager.default.contents(atPath: inputURL.path) else {
                return (VideoConsole.cannotReadLine(inputPath), .inputError)
            }

            let extracted: ExtractedVideo
            do {
                extracted = try VideoWorkflow.extract(fileData: data, inputPath: inputPath)
            } catch let failure as VideoWorkflow.Failure {
                return (failure.message, failure.exitCode)
            } catch {
                return (error.localizedDescription, .inputError)
            }

            var lines: [String] = []
            if verbose {
                lines.append(VideoConsole.verboseBlock(
                    VideoConsole.verboseExtractLines(extracted)))
            }
            // Into a folder, the recovered container names the file, so the
            // extension is right by construction. Resolved here rather than up
            // front because only the extracted payload knows what it is.
            let outputPath = VideoWorkflow.resolveOutputURL(
                output: typedOutputPath,
                input: URL(fileURLWithPath: inputPath),
                fileExtension: extracted.suggestedFileExtension,
                isDirectory: { path in
                    var isDirectory: ObjCBool = false
                    let exists = FileManager.default.fileExists(
                        atPath: path, isDirectory: &isDirectory)
                    return exists && isDirectory.boolValue
                }
            ).url.path
            if outputScopedURL == nil,
               FileManager.default.fileExists(atPath: outputPath), !force {
                lines.append(VideoConsole.outputExistsLine(outputPath))
                return (lines.joined(separator: "\n"), .inputError)
            }

            if let warning = VideoWorkflow.conformanceWarning(for: extracted) {
                lines.append(warning)
            }

            if let warning = VideoWorkflow.extensionWarning(
                for: extracted, outputPath: outputPath) {
                lines.append(warning)
            }

            do {
                let written = try OutputAccess.write(
                    extracted.bitstream, toPath: outputPath,
                    scopedURL: outputScopedURL, subfolder: "Video")
                if let note = written.note { lines.append(note) }
                lines.append(VideoConsole.extractedLine(
                    path: written.url.path, byteCount: extracted.bitstream.count))
            } catch {
                lines.append(VideoConsole.cannotWriteLine(
                    outputPath, reason: error.localizedDescription))
                return (lines.joined(separator: "\n"), .inputError)
            }

            lines.append(VideoConsole.extractSummary(extracted))
            return (lines.joined(separator: "\n"), .success)
        }.value

        finishDicomVideo(output: output, exitCode: exitCode)
    }

    // MARK: - dicom-video: batch

    private func executeDicomVideoBatch() async {
        let inputDirectory = paramValue("inputDirectory")
        let outputDir = paramValue("outputDir")
        guard !inputDirectory.isEmpty else {
            failDicomVideoMissing("Input directory is required.")
            return
        }
        guard !outputDir.isEmpty else {
            failDicomVideoMissing("Output directory is required.")
            return
        }

        let typeRaw = paramValue("type").trimmingCharacters(in: .whitespaces)
        var type: VideoConsole.TypeArgument = .endoscopic
        if !typeRaw.isEmpty {
            guard let parsed = VideoConsole.TypeArgument(rawValue: typeRaw) else {
                finishDicomVideo(output: VideoConsole.invalidTypeLine(typeRaw),
                                 exitCode: .inputError)
                return
            }
            type = parsed
        }

        let seriesModeRaw = paramValue("seriesMode").trimmingCharacters(in: .whitespaces)
        var seriesMode: VideoConsole.SeriesMode = .single
        if !seriesModeRaw.isEmpty {
            guard let parsed = VideoConsole.SeriesMode(rawValue: seriesModeRaw) else {
                finishDicomVideo(output: VideoConsole.invalidSeriesModeLine(seriesModeRaw),
                                 exitCode: .inputError)
                return
            }
            seriesMode = parsed
        }

        let transferSyntaxRaw = paramValue("transferSyntax").trimmingCharacters(in: .whitespaces)
        let recursive = paramValue("recursive") == "true"
        let continueOnError = paramValue("continueOnError") == "true"
        let dryRun = paramValue("dryRun") == "true"
        let force = paramValue("force") == "true"
        let verbose = paramValue("verbose") == "true"
        let metadata = dicomVideoMetadata()
        let typeWasExplicit = !typeRaw.isEmpty

        let inputScopedURL = securityScopedURLs["inputDirectory"]
        let outputScopedURL = securityScopedURLs["outputDir"]
        let accessingIn = inputScopedURL?.startAccessingSecurityScopedResource() ?? false
        let accessingOut = outputScopedURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if accessingIn { inputScopedURL?.stopAccessingSecurityScopedResource() }
            if accessingOut { outputScopedURL?.stopAccessingSecurityScopedResource() }
        }
        let inputBase = inputScopedURL ?? URL(fileURLWithPath: inputDirectory)

        // Resolve the destination once, so a sandbox redirect is announced before
        // the per-clip lines rather than repeated on each of them.
        let resolvedOutput = OutputAccess.resolveWritableURL(
            forPath: outputDir, scopedURL: outputScopedURL,
            subfolder: "Video", isDirectory: true)
        let outputBase = resolvedOutput.url
        let redirectNote = resolvedOutput.note

        let (output, exitCode) = await Task.detached(priority: .userInitiated) {
            () -> (String, VideoConsole.ExitCode) in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                    atPath: inputBase.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return (VideoConsole.notADirectoryLine(inputDirectory), .inputError)
            }

            do {
                try VideoWorkflow.validateBatchOptions(
                    seriesMode: seriesMode, metadata: metadata)
            } catch let failure as VideoWorkflow.Failure {
                return (failure.message, failure.exitCode)
            } catch {
                return (error.localizedDescription, .inputError)
            }

            let files: [URL]
            do {
                files = try VideoWorkflow.discoverInputs(in: inputBase, recursive: recursive)
            } catch {
                return (VideoConsole.notADirectoryLine(inputDirectory), .inputError)
            }
            guard !files.isEmpty else {
                return (VideoConsole.noVideoFilesLine(inputDirectory), .inputError)
            }

            if !dryRun {
                do {
                    try FileManager.default.createDirectory(
                        at: outputBase, withIntermediateDirectories: true)
                } catch {
                    return (VideoConsole.cannotWriteLine(
                        outputDir, reason: error.localizedDescription), .inputError)
                }
            }

            let outcome = VideoWorkflow.runBatch(
                inputs: files,
                type: type,
                typeWasExplicit: typeWasExplicit,
                explicitTransferSyntax: transferSyntaxRaw.isEmpty ? nil : transferSyntaxRaw,
                seriesMode: seriesMode,
                continueOnError: continueOnError,
                dryRun: dryRun,
                verbose: verbose,
                recursive: recursive,
                metadata: metadata,
                readFile: { FileManager.default.contents(atPath: $0.path) },
                writeFile: { item in
                    let destination = outputBase.appendingPathComponent(item.outputName)
                    if FileManager.default.fileExists(atPath: destination.path), !force {
                        throw VideoWorkflow.Failure.inputError(
                            VideoConsole.batchOutputExistsLine(destination.lastPathComponent))
                    }
                    try item.data?.write(to: destination)
                    return destination.path
                }
            )

            // The Workshop has one console, so the CLI's two streams are shown
            // together — diagnostics first, exactly as a terminal interleaves them.
            guard let note = redirectNote else { return (outcome.combined, outcome.exitCode) }
            return (note + "\n" + outcome.combined, outcome.exitCode)
        }.value

        finishDicomVideo(output: output, exitCode: exitCode)
    }

    // MARK: - dicom-image Execution

    /// Converts standard image files (JPEG/PNG/TIFF/BMP/GIF) to DICOM Secondary
    /// Capture, faithfully reproducing the `dicom-image` CLI in-process using
    /// CoreGraphics/ImageIO + DICOMKit. Supports single-file, recursive batch
    /// directory, and multi-page TIFF splitting, plus optional EXIF extraction.
    private func executeDicomImage() async {
        let input = paramValue("input")
        guard !input.isEmpty else {
            appendConsoleOutput("Error: Input path is required.\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-image", command: commandPreview, exitCode: 1, output: "Missing input path")
            return
        }

        let outputRaw = paramValue("output")
        let outputPath: String? = outputRaw.isEmpty ? nil : outputRaw
        let patientName = paramValue("patient-name")
        let patientID = paramValue("patient-id")
        let studyDescription = paramValue("study-description").isEmpty ? nil : paramValue("study-description")
        let seriesDescription = paramValue("series-description").isEmpty ? nil : paramValue("series-description")
        let studyUIDArg = paramValue("study-uid").isEmpty ? nil : paramValue("study-uid")
        let seriesUIDArg = paramValue("series-uid").isEmpty ? nil : paramValue("series-uid")
        let seriesNumber = Int(paramValue("series-number"))
        let instanceNumberArg = Int(paramValue("instance-number"))
        let modalityVal = paramValue("modality").isEmpty ? "OT" : paramValue("modality")
        let useExif = paramValue("use-exif") == "true"
        let splitPages = paramValue("split-pages") == "true"
        let recursive = paramValue("recursive") == "true"
        let verbose = paramValue("verbose") == "true"

        // Security-scoped access for input and output (when provided as bookmarks).
        let inputScopedURL = securityScopedURLs["input"]
        let inputAccessing = inputScopedURL?.startAccessingSecurityScopedResource() ?? false
        defer { if inputAccessing { inputScopedURL?.stopAccessingSecurityScopedResource() } }
        let outputScopedURL = securityScopedURLs["output"]
        let outputAccessing = outputScopedURL?.startAccessingSecurityScopedResource() ?? false
        defer { if outputAccessing { outputScopedURL?.stopAccessingSecurityScopedResource() } }

        let inputURL = inputScopedURL ?? URL(fileURLWithPath: input)
        // Resolve the output URL: prefer a scoped bookmark; else probe the typed path and
        // redirect to ~/Downloads/DICOMStudio if it isn't writable (sandbox/TCC).
        let resolvedOutputURL: URL?
        if let scoped = outputScopedURL {
            resolvedOutputURL = scoped
        } else if let op = outputPath, !op.isEmpty {
            let r = OutputAccess.resolveWritableURL(forPath: op, scopedURL: nil,
                                                    subfolder: "ImageConversion",
                                                    isDirectory: recursive || splitPages)
            if let note = r.note { appendConsoleOutput(note + "\n") }
            resolvedOutputURL = r.url
        } else {
            resolvedOutputURL = nil
        }

        #if canImport(CoreGraphics)
        let (output, exitCode) = await Task.detached(priority: .userInitiated) {
            () -> (String, Int) in
            let fm = FileManager.default

            // Validate input exists.
            guard fm.fileExists(atPath: inputURL.path) else {
                return ("Error: Input path not found: \(inputURL.path)\n", 1)
            }

            // Patient identity is mandatory for any conversion.
            guard !patientName.isEmpty else {
                return ("Error: Patient Name is required for conversion (--patient-name)\n", 1)
            }
            guard !patientID.isEmpty else {
                return ("Error: Patient ID is required for conversion (--patient-id)\n", 1)
            }

            var out = ""

            // Pixel extraction, EXIF mapping, and Secondary Capture assembly now
            // come from the shared DICOMKit ImageConverter — the exact same code
            // the dicom-image CLI runs. These thin wrappers keep call sites tidy.
            func generateUID() -> String { ImageConverter.generateUID() }
            func isImageFile(_ url: URL) -> Bool { ImageConverter.isImageFile(url) }

            func makeMetadata(studyUID: String, seriesUID: String, instanceNumber: Int) -> ImageConverter.Metadata {
                ImageConverter.Metadata(
                    patientName: patientName, patientID: patientID,
                    studyUID: studyUID, seriesUID: seriesUID, instanceNumber: instanceNumber,
                    studyDescription: studyDescription, seriesDescription: seriesDescription,
                    modality: modalityVal, seriesNumber: seriesNumber)
            }

            // Loads, encodes and writes a single image (page 0) to a .dcm file URL
            // via the shared engine. The write goes through `OutputAccess.write`:
            // the output Browse picker grants a FOLDER, so when the user then types
            // a filename the file must be written INSIDE that grant, named from the
            // typed path. Writing straight onto the scoped folder URL produced
            // "The file "Test" couldn't be saved in the folder "Desktop"".
            // Returns the URL actually written, or an error message.
            func convertImageFile(
                imageURL: URL,
                outputURL: URL,
                studyUID: String,
                seriesUID: String,
                instanceNumber: Int
            ) -> (written: URL?, error: String?) {
                do {
                    let data = try ImageConverter.secondaryCaptureData(
                        imageURL: imageURL,
                        metadata: makeMetadata(studyUID: studyUID, seriesUID: seriesUID, instanceNumber: instanceNumber),
                        useExif: useExif)
                    let r = try OutputAccess.write(data, toPath: outputURL.path, scopedURL: outputScopedURL,
                                                   subfolder: "ImageConversion")
                    if let note = r.note { out += note + "\n" }
                    return (r.url, nil)
                } catch let e as ImageConversionError {
                    return (nil, e.errorDescription)
                } catch {
                    return (nil, error.localizedDescription)
                }
            }

            // MARK: Dispatch on input kind.

            var isDir: ObjCBool = false
            _ = fm.fileExists(atPath: inputURL.path, isDirectory: &isDir)

            if isDir.boolValue {
                // ---- Directory (batch) conversion ----
                guard recursive else {
                    return ("Error: Directory processing requires --recursive flag\n", 1)
                }
                let outputDirURL = resolvedOutputURL ?? inputURL.appendingPathComponent("dicom")
                do {
                    try fm.createDirectory(at: outputDirURL, withIntermediateDirectories: true)
                } catch {
                    return ("Error: \(error.localizedDescription)\n", 1)
                }
                if verbose {
                    out += ImageConsole.batchHeader(inputPath: inputURL.path, outputDir: outputDirURL.path)
                }

                let finalStudyUID = studyUIDArg ?? generateUID()
                let finalSeriesUID = seriesUIDArg ?? generateUID()
                var instanceNum = instanceNumberArg ?? 1
                var successCount = 0
                var failureCount = 0

                // Shared, sorted directory walk — the exact gatherer dicom-image uses.
                let fileURLs = FileGatherer.regularFiles(under: inputURL) ?? []
                for fileURL in fileURLs {
                    guard isImageFile(fileURL) else {
                        if verbose { out += ImageConsole.skippedLine(fileName: fileURL.lastPathComponent) + "\n" }
                        continue
                    }
                    let baseName = fileURL.deletingPathExtension().lastPathComponent
                    let outFileURL = outputDirURL.appendingPathComponent("\(baseName).dcm")
                    let result = convertImageFile(
                        imageURL: fileURL, outputURL: outFileURL,
                        studyUID: finalStudyUID, seriesUID: finalSeriesUID,
                        instanceNumber: instanceNum
                    )
                    if let err = result.error {
                        failureCount += 1
                        if verbose { out += ImageConsole.fileFailureLine(inputName: fileURL.lastPathComponent, message: err) + "\n" }
                    } else {
                        successCount += 1
                        instanceNum += 1
                        let writtenName = (result.written ?? outFileURL).lastPathComponent
                        if verbose { out += ImageConsole.fileSuccessLine(inputName: fileURL.lastPathComponent, outputName: writtenName) + "\n" }
                    }
                }

                out += ImageConsole.batchSummary(
                    successful: successCount, failed: failureCount,
                    studyUID: finalStudyUID, seriesUID: finalSeriesUID, outputDir: outputDirURL.path
                )
                return (out, successCount > 0 || failureCount == 0 ? 0 : 1)
            }

            let ext = inputURL.pathExtension.lowercased()
            if splitPages && (ext == "tiff" || ext == "tif") {
                // ---- Multi-page TIFF split (shared ImageConverter) ----
                let pageCount: Int
                do { pageCount = try ImageConverter.pageCount(of: inputURL) }
                catch { return ("Error: Failed to load image file\n", 1) }
                guard pageCount > 0 else {
                    return ("Error: TIFF file contains no pages\n", 1)
                }
                let outputDirURL: URL
                if let resolved = resolvedOutputURL {
                    outputDirURL = resolved
                } else {
                    let baseName = inputURL.deletingPathExtension().lastPathComponent
                    outputDirURL = inputURL.deletingLastPathComponent().appendingPathComponent("\(baseName)_frames")
                }
                do {
                    try fm.createDirectory(at: outputDirURL, withIntermediateDirectories: true)
                } catch {
                    return ("Error: \(error.localizedDescription)\n", 1)
                }
                if verbose {
                    out += ImageConsole.tiffHeader(fileName: inputURL.lastPathComponent, pages: pageCount, outputDir: outputDirURL.path)
                }
                let finalStudyUID = studyUIDArg ?? generateUID()
                let finalSeriesUID = seriesUIDArg ?? generateUID()
                for pageIndex in 0..<pageCount {
                    let fileName = String(format: "frame_%04d.dcm", pageIndex + 1)
                    let outFileURL = outputDirURL.appendingPathComponent(fileName)
                    do {
                        let data = try ImageConverter.secondaryCaptureData(
                            imageURL: inputURL, pageIndex: pageIndex,
                            metadata: makeMetadata(studyUID: finalStudyUID, seriesUID: finalSeriesUID,
                                                   instanceNumber: (instanceNumberArg ?? 1) + pageIndex),
                            // Honor --use-exif per page (matches the CLI fix): the
                            // converter reads each page's own EXIF at pageIndex.
                            useExif: useExif)
                        try data.write(to: outFileURL, options: .atomic)
                        if verbose { out += ImageConsole.pageSuccessLine(page: pageIndex + 1, outputName: fileName) + "\n" }
                    } catch {
                        if verbose { out += ImageConsole.pageFailureLine(page: pageIndex + 1, message: error.localizedDescription) + "\n" }
                    }
                }
                out += ImageConsole.tiffSummary(pages: pageCount, outputDir: outputDirURL.path)
                return (out, 0)
            }

            // ---- Single-file conversion ----
            let finalOutputURL: URL
            if outputScopedURL != nil, let op = outputPath {
                // Browse granted a folder; the field may now hold folder + filename.
                // Hand the TYPED path to OutputAccess.write, which places it inside
                // the grant (or names a file after it when it falls outside).
                finalOutputURL = URL(fileURLWithPath: op)
            } else if let resolved = resolvedOutputURL {
                finalOutputURL = resolved
            } else {
                finalOutputURL = inputURL.deletingPathExtension().appendingPathExtension("dcm")
            }
            if verbose { out += ImageConsole.convertingLine(inputPath: inputURL.path) + "\n" }
            let single = convertImageFile(
                imageURL: inputURL, outputURL: finalOutputURL,
                studyUID: studyUIDArg ?? generateUID(),
                seriesUID: seriesUIDArg ?? generateUID(),
                instanceNumber: instanceNumberArg ?? 1
            )
            if let err = single.error {
                return (out + "Error: \(err)\n", 1)
            }
            out += ImageConsole.convertedLine(outputPath: (single.written ?? finalOutputURL).path, verbose: verbose) + "\n"
            return (out, 0)
        }.value
        #else
        let output = "Error: Image conversion not supported on this platform\n"
        let exitCode = 1
        #endif

        appendConsoleOutput(output)
        addToHistory(toolName: "dicom-image", command: commandPreview, exitCode: exitCode, output: output)
        consoleStatus = exitCode == 0 ? .success : .error
        service.setConsoleStatus(exitCode == 0 ? .success : .error)
    }

    // MARK: - dicom-export Execution

    /// Advanced DICOM image export: single image (+EXIF), contact sheet, animated GIF, and bulk export.
    /// Reimplements the dicom-export CLI in-process using DICOMKit rendering + CoreGraphics/ImageIO.
    /// Mirrors `dicom-export` (D127): every subcommand renders through the shared
    /// `DICOMImageExporter.renderFrameForExport` (the PS3.4 N.2 grayscale chain), frames are
    /// selected by Frame number from 1 (`--frame-number`, `--start-frame-number`,
    /// `--end-frame-number`; PS3.3 Table 10-3) with the 0-based options deprecated (P-EXPORT-1),
    /// the animate rate defaults to the file's Cine Module (PS3.3 Table C.7-13), bulk patient
    /// folders are keyed on Patient ID + Issuer of Patient ID (P-EXPORT-2), `--apply-window` is
    /// deprecated on contact-sheet / bulk (P-EXPORT-3), and Burned In Annotation (0028,0301) YES
    /// warns. Exit codes: ArgumentParser ValidationError 64, every other error 1.
    private func executeDicomExport() async {
        #if canImport(CoreGraphics) && canImport(ImageIO)
        let operation = paramValue("operation").isEmpty ? "single" : paramValue("operation")
        let inputPath = paramValue("inputPath")
        let outputPath = paramValue("output")

        func refuse(_ message: String, exitCode: Int) {
            appendConsoleOutput("Error: \(message)\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-export", command: commandPreview, exitCode: exitCode, output: message)
        }
        guard !inputPath.isEmpty else {
            return refuse("Missing expected argument '<\(operation == "contact-sheet" ? "inputs" : "input")>'", exitCode: 64)
        }
        // `single --output` is optional on the CLI (the image goes next to the working directory);
        // a sandboxed app has no working directory to write to, so the form requires it.
        guard !outputPath.isEmpty else {
            return refuse("Missing expected argument '--output <output>'", exitCode: 64)
        }

        // Gather all parameter values on the MainActor before detaching.
        let formatSel: String
        switch operation {
        case "contact-sheet": formatSel = paramValue("sheet-format").isEmpty ? "png" : paramValue("sheet-format")
        case "bulk":          formatSel = paramValue("bulk-format").isEmpty ? "png" : paramValue("bulk-format")
        case "single":        formatSel = paramValue("format").isEmpty ? "jpeg" : paramValue("format")
        default:              formatSel = "png"
        }
        let quality = Int(paramValue("quality")) ?? 90
        let embedMetadata = paramValue("embed-metadata") == "true"
        let exifFieldsRaw = paramValue("exif-fields")
        let frame = Int(paramValue("frame"))
        let frameNumber = Int(paramValue("frame-number"))
        let applyWindow = paramValue("apply-window") == "true"
        let applyWindowDeprecated = paramValue("apply-window-deprecated") == "true"
        let windowCenter = Double(paramValue("window-center"))
        let windowWidth = Double(paramValue("window-width"))
        let columns = max(1, Int(paramValue("columns")) ?? 4)
        let thumbnailSize = max(16, Int(paramValue("thumbnail-size")) ?? 256)
        let spacing = max(0, Int(paramValue("spacing")) ?? 4)
        let labels = paramValue("labels") == "true"
        let fps = Double(paramValue("fps"))
        let loopCount = Int(paramValue("loop-count")) ?? 0
        let startFrame = Int(paramValue("start-frame"))
        let endFrame = Int(paramValue("end-frame"))
        let startFrameNumber = Int(paramValue("start-frame-number"))
        let endFrameNumber = Int(paramValue("end-frame-number"))
        let scale = Double(paramValue("scale")) ?? 1.0
        let organizeBy = paramValue("organize-by").isEmpty ? "flat" : paramValue("organize-by")
        let recursive = paramValue("recursive") == "true"
        let verbose = paramValue("verbose") == "true"

        // The CLI's validate(): a usage error is exit 64; mixing a 0-based option with a Frame
        // number option is refused with exit 1 (P-EXPORT-1).
        var notes: [String] = []
        switch operation {
        case "single":
            if let f = frame, f < 0 {
                return refuse("--frame is a 0-based frame index and must be 0 or more", exitCode: 64)
            }
            if let n = frameNumber, n < 1 {
                return refuse("--frame-number must be 1 or more (\(Self.exportFrameNumberReference))", exitCode: 64)
            }
            if frame != nil && frameNumber != nil {
                return refuse(Self.exportFrameSelectionConflict(zeroBased: "--frame", oneBased: "--frame-number"), exitCode: 1)
            }
            if frame != nil {
                notes.append(Self.exportFrameDeprecationNote(option: "--frame", replacement: "--frame-number"))
            }
        case "animate":
            for (name, value) in [("--start-frame-number", startFrameNumber), ("--end-frame-number", endFrameNumber)] {
                if let n = value, n < 1 {
                    return refuse("\(name) must be 1 or more (\(Self.exportFrameNumberReference))", exitCode: 64)
                }
            }
            let zeroBased = [("--start-frame", startFrame), ("--end-frame", endFrame)].filter { $0.1 != nil }.map(\.0)
            let oneBased = [("--start-frame-number", startFrameNumber), ("--end-frame-number", endFrameNumber)].filter { $0.1 != nil }.map(\.0)
            if let z = zeroBased.first, let o = oneBased.first {
                return refuse(Self.exportFrameSelectionConflict(zeroBased: z, oneBased: o), exitCode: 1)
            }
            if startFrame != nil {
                notes.append(Self.exportFrameDeprecationNote(option: "--start-frame", replacement: "--start-frame-number"))
            }
            if endFrame != nil {
                notes.append(Self.exportFrameDeprecationNote(option: "--end-frame", replacement: "--end-frame-number"))
            }
        case "contact-sheet", "bulk":
            // P-EXPORT-3: the flag has no effect here; the CLI prints its note and renders with
            // the file's VOI.
            if applyWindowDeprecated {
                notes.append(Self.exportApplyWindowDeprecationNote(subcommand: operation))
            }
        default:
            break
        }
        for note in notes { appendConsoleOutput(note + "\n") }

        // 0-based frame index / range, as the CLI derives them: the Frame number options - 1,
        // else the deprecated 0-based options, else the first frame / the whole file.
        let frameIndex = frameNumber.map { $0 - 1 } ?? frame ?? 0
        let frameIndexRange: (start: Int, end: Int?) = (startFrameNumber != nil || endFrameNumber != nil)
            ? ((startFrameNumber ?? 1) - 1, endFrameNumber.map { $0 - 1 })
            : (startFrame ?? 0, endFrame)

        // Sandbox access.
        let inputScopedURL = securityScopedURLs["inputPath"]
        let outputScopedURL = securityScopedURLs["output"]
        let accessingInput = inputScopedURL?.startAccessingSecurityScopedResource() ?? false
        let accessingOutput = outputScopedURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if accessingInput { inputScopedURL?.stopAccessingSecurityScopedResource() }
            if accessingOutput { outputScopedURL?.stopAccessingSecurityScopedResource() }
        }
        let inputURL = inputScopedURL ?? URL(fileURLWithPath: inputPath)
        // Sandbox/TCC-resilient output (single/contact-sheet/animate write a file; bulk a directory).
        let _exportOut = OutputAccess.resolveWritableURL(forPath: outputPath, scopedURL: outputScopedURL, subfolder: "Export", isDirectory: operation == "bulk")
        let outputURL = _exportOut.url
        if let note = _exportOut.note { appendConsoleOutput(note + "\n") }

        let (output, exitCode) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
            var log = ""

            // MARK: helpers — pure export logic (EXIF, paths, window, encoding)
            // comes from the shared DICOMKit DICOMImageExporter; these thin
            // wrappers keep the orchestration call sites unchanged.

            func fileExtension(_ format: String) -> String {
                (ExportImageFormat(rawValue: format.lowercased()) ?? .png).fileExtension
            }

            func exportCGImage(_ image: CGImage, to url: URL, format: String, quality: Int, metadata: CFDictionary?) throws {
                let fmt = ExportImageFormat(rawValue: format.lowercased()) ?? .png
                try DICOMImageExporter.exportCGImage(image, to: url, format: fmt, quality: quality, metadata: metadata)
            }

            /// The one frame-render decision of every dicom-export subcommand (its ExportFrames.render):
            /// the shared PS3.4 N.2 chain of DICOMImageExporter.renderFrameForExport.
            func render(file: DICOMFile, pixelData: PixelData? = nil, frameIndex: Int,
                        applyWindow: Bool, windowCenter: Double?, windowWidth: Double?) throws -> CGImage {
                guard let pixelData = pixelData ?? file.pixelData() else { throw ExportError.noPixelData }
                return try DICOMImageExporter.renderFrameForExport(
                    file: file, pixelData: pixelData, frameIndex: frameIndex,
                    applyWindow: applyWindow, windowCenter: windowCenter, windowWidth: windowWidth)
            }

            // Collect DICOM files from a directory (used by contact-sheet & bulk) —
            // the shared, sorted gatherer dicom-export uses.
            func collectDICOMFiles(in dir: URL, recursive: Bool) -> [URL] {
                FileGatherer.regularFiles(under: dir, recursive: recursive) ?? []
            }

            do {
                switch operation {

                // MARK: single
                case "single":
                    guard FileManager.default.fileExists(atPath: inputURL.path) else {
                        throw ExportError.invalidInput("Input file not found: \(inputPath)")
                    }
                    let fileData = try Data(contentsOf: inputURL)
                    let dicomFile = try DICOMFile.read(from: fileData)
                    guard let pixelData = dicomFile.pixelData() else {
                        throw ExportError.noPixelData
                    }
                    if Self.exportBurnedInAnnotationIsYes(dicomFile.dataSet) {
                        log += Self.exportBurnedInWarning(for: inputPath) + "\n"
                    }
                    let totalFrames = pixelData.descriptor.numberOfFrames
                    guard frameIndex >= 0 && frameIndex < totalFrames else {
                        if let number = frameNumber {
                            throw ExportError.invalidInput(Self.exportInvalidFrameNumberMessage(requested: number, total: totalFrames))
                        }
                        throw ExportError.invalidFrame(frameIndex, totalFrames)
                    }
                    let image = try DICOMImageExporter.renderFrameForExport(
                        file: dicomFile, pixelData: pixelData, frameIndex: frameIndex,
                        applyWindow: applyWindow, windowCenter: windowCenter, windowWidth: windowWidth
                    )
                    // Determine output path; if output looks like a directory, derive filename
                    // (the CLI's default name <input stem>.<format extension>).
                    var finalOutput = outputURL
                    var outIsDir: ObjCBool = false
                    let outExists = FileManager.default.fileExists(atPath: outputURL.path, isDirectory: &outIsDir)
                    if (outExists && outIsDir.boolValue) || (!outExists && outputURL.pathExtension.isEmpty) {
                        try? FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
                        let baseName = inputURL.deletingPathExtension().lastPathComponent
                        finalOutput = outputURL.appendingPathComponent("\(baseName).\(fileExtension(formatSel))")
                    } else {
                        try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(),
                                                                 withIntermediateDirectories: true)
                    }
                    var metadata: CFDictionary? = nil
                    if embedMetadata {
                        let fields = exifFieldsRaw.isEmpty ? nil : exifFieldsRaw.split(separator: ",").map(String.init)
                        for field in DICOMImageExporter.unsupportedEXIFFields(fields ?? []) {
                            log += "warning: --exif-fields '\(field)' has no EXIF/TIFF mapping and is not embedded (supported: \(DICOMImageExporter.supportedEXIFFields.joined(separator: ", ")))\n"
                        }
                        metadata = DICOMImageExporter.buildEXIFMetadata(from: dicomFile, fields: fields)
                    }
                    try exportCGImage(image, to: finalOutput, format: formatSel, quality: quality, metadata: metadata)
                    log += ExportConsole.exportedLine(path: finalOutput.path) + "\n"
                    return (log, 0)

                // MARK: contact-sheet
                case "contact-sheet":
                    // The CLI's contact-sheet <inputs> is a variadic positional list —
                    // the field may hold several semicolon-separated paths (the preview
                    // expands the same split into positional tokens). Directory entries
                    // are expanded to their DICOM files, a documented in-app extra (the
                    // CLI takes explicit files only).
                    let roots = CommandBuilderHelpers.splitMultiValue(inputPath)
                    let rootURLs = roots.count > 1 ? roots.map { URL(fileURLWithPath: $0) } : [inputURL]
                    var inputs: [URL] = []
                    for root in rootURLs {
                        var isDir: ObjCBool = false
                        if FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue {
                            inputs.append(contentsOf: collectDICOMFiles(in: root, recursive: false))
                        } else {
                            inputs.append(root)
                        }
                    }
                    guard !inputs.isEmpty else {
                        throw ExportError.invalidInput("No input files specified")
                    }
                    let layout = DICOMImageExporter.contactSheetLayout(
                        imageCount: inputs.count, columns: columns,
                        thumbnailSize: thumbnailSize, spacing: spacing, includeLabels: labels
                    )
                    let rows = layout.rows
                    let totalWidth = layout.totalWidth
                    let totalHeight = layout.totalHeight

                    let colorSpace = CGColorSpaceCreateDeviceRGB()
                    guard let context = CGContext(
                        data: nil, width: totalWidth, height: totalHeight,
                        bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    ) else {
                        throw ExportError.exportFailed
                    }
                    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
                    context.fill(CGRect(x: 0, y: 0, width: totalWidth, height: totalHeight))

                    var burnedIn = 0
                    for (index, inPath) in inputs.enumerated() {
                        let pos = DICOMImageExporter.thumbnailPosition(
                            index: index, columns: columns,
                            thumbnailSize: thumbnailSize, spacing: spacing, includeLabels: labels
                        )
                        let flippedY = totalHeight - pos.y - thumbnailSize
                        let rect = CGRect(x: pos.x, y: flippedY, width: thumbnailSize, height: thumbnailSize)
                        do {
                            let fileData = try Data(contentsOf: inPath)
                            let dicomFile = try DICOMFile.read(from: fileData)
                            // Same render as `single` (the PS3.4 N.2 chain with the file's VOI in
                            // modality units); --apply-window has no effect here (P-EXPORT-3).
                            let image = try render(file: dicomFile, frameIndex: 0,
                                                   applyWindow: false, windowCenter: nil, windowWidth: nil)
                            if Self.exportBurnedInAnnotationIsYes(dicomFile.dataSet) { burnedIn += 1 }
                            context.draw(image, in: rect)
                        } catch {
                            // Draw placeholder for failed files
                            context.setFillColor(CGColor(red: 0.2, green: 0, blue: 0, alpha: 1))
                            context.fill(rect)
                        }
                    }
                    guard let sheetImage = context.makeImage() else {
                        throw ExportError.renderFailed
                    }
                    try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(),
                                                             withIntermediateDirectories: true)
                    try exportCGImage(sheetImage, to: outputURL, format: formatSel, quality: quality, metadata: nil)
                    log += ExportConsole.contactSheetLine(path: outputURL.path, imageCount: inputs.count, columns: columns, rows: rows) + "\n"
                    if burnedIn > 0 { log += Self.exportBurnedInSummaryWarning(count: burnedIn) + "\n" }
                    return (log, 0)

                // MARK: animate
                case "animate":
                    guard FileManager.default.fileExists(atPath: inputURL.path) else {
                        throw ExportError.invalidInput("Input file not found: \(inputPath)")
                    }
                    let fileData = try Data(contentsOf: inputURL)
                    let dicomFile = try DICOMFile.read(from: fileData)
                    let totalFrames = dicomFile.numberOfFrames ?? 1
                    guard totalFrames > 0 else {
                        throw ExportError.noFrames
                    }
                    guard let range = DICOMImageExporter.validatedFrameRange(
                        start: frameIndexRange.start, end: frameIndexRange.end, totalFrames: totalFrames
                    ) else {
                        throw ExportError.noFrames
                    }
                    let clampedScale = max(0.1, min(2.0, scale))
                    // The rate: --fps, else the file's Cine Module (PS3.3 Table C.7-13), else 10.
                    let rate = Self.exportCineFrameRate(explicit: fps, dataSet: dicomFile.dataSet)
                    let delay = DICOMImageExporter.gifFrameDelay(fps: rate.fps)
                    if Self.exportBurnedInAnnotationIsYes(dicomFile.dataSet) {
                        log += Self.exportBurnedInWarning(for: inputPath) + "\n"
                    }
                    let frameCount = range.end - range.start + 1

                    try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(),
                                                             withIntermediateDirectories: true)
                    guard let destination = CGImageDestinationCreateWithURL(
                        outputURL as CFURL, "com.compuserve.gif" as CFString, frameCount, nil
                    ) else {
                        throw ExportError.exportFailed
                    }
                    let gifFileProperties: [String: Any] = [
                        kCGImagePropertyGIFDictionary as String: [
                            kCGImagePropertyGIFLoopCount as String: loopCount
                        ]
                    ]
                    CGImageDestinationSetProperties(destination, gifFileProperties as CFDictionary)
                    let frameProperties: [String: Any] = [
                        kCGImagePropertyGIFDictionary as String: [
                            kCGImagePropertyGIFDelayTime as String: delay
                        ]
                    ]
                    guard let pixelData = dicomFile.pixelData() else {
                        throw ExportError.noPixelData
                    }
                    for frameIndex in range.start...range.end {
                        // Same render as `single`: the PS3.4 N.2 chain, window in modality units.
                        var image = try render(file: dicomFile, pixelData: pixelData, frameIndex: frameIndex,
                                               applyWindow: applyWindow, windowCenter: windowCenter, windowWidth: windowWidth)
                        if clampedScale != 1.0 {
                            let newWidth = Int(Double(image.width) * clampedScale)
                            let newHeight = Int(Double(image.height) * clampedScale)
                            if newWidth > 0, newHeight > 0,
                               let cs = image.colorSpace,
                               let ctx = CGContext(
                                   data: nil, width: newWidth, height: newHeight,
                                   bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                               ) {
                                ctx.interpolationQuality = .high
                                ctx.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
                                if let scaled = ctx.makeImage() { image = scaled }
                            }
                        }
                        CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
                    }
                    guard CGImageDestinationFinalize(destination) else {
                        throw ExportError.exportFailed
                    }
                    log += ExportConsole.animatedGIFLine(path: outputURL.path, frameCount: frameCount, fps: rate.fps) + "\n"
                    return (log, 0)

                // MARK: bulk
                case "bulk":
                    var isDirectory: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory),
                          isDirectory.boolValue else {
                        throw ExportError.invalidInput("Input must be a directory: \(inputPath)")
                    }
                    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
                    guard let files = FileGatherer.regularFiles(under: inputURL, recursive: recursive) else {
                        throw ExportError.invalidInput("Failed to enumerate directory: \(inputPath)")
                    }

                    var fileCount = 0, successCount = 0, errorCount = 0, burnedIn = 0
                    let scheme = OrganizationScheme(rawValue: organizeBy) ?? .flat
                    for fileURL in files {
                        fileCount += 1
                        do {
                            let fileData = try Data(contentsOf: fileURL)
                            let dicomFile = try DICOMFile.read(from: fileData)
                            guard let pixelDataObj = dicomFile.pixelData() else {
                                if verbose { log += ExportConsole.bulkSkipLine(fileName: fileURL.lastPathComponent) + "\n" }
                                continue
                            }
                            // --apply-window is deprecated here and has no effect (no window values).
                            let image = try DICOMImageExporter.renderFrameForExport(
                                file: dicomFile, pixelData: pixelDataObj, frameIndex: 0,
                                applyWindow: false, windowCenter: nil, windowWidth: nil
                            )
                            // Patient folder keyed on Patient ID (0010,0020) and Issuer of Patient ID
                            // (0010,0021) (P-EXPORT-2; PS3.3 Table C.7-1).
                            let patientID = dicomFile.dataSet.string(for: .patientID)
                            let issuer = dicomFile.dataSet.string(for: .issuerOfPatientID)
                            let studyUID = dicomFile.dataSet.string(for: .studyInstanceUID)
                            let seriesUID = dicomFile.dataSet.string(for: .seriesInstanceUID)
                            let baseName = fileURL.deletingPathExtension().lastPathComponent + "." + fileExtension(formatSel)
                            let outputPath = DICOMImageExporter.buildOrganizedPath(
                                baseOutput: outputURL.path, scheme: scheme,
                                patientID: patientID, issuerOfPatientID: issuer,
                                studyUID: studyUID, seriesUID: seriesUID, filename: baseName
                            )
                            let outFileURL = URL(fileURLWithPath: outputPath)
                            try FileManager.default.createDirectory(at: outFileURL.deletingLastPathComponent(),
                                                                    withIntermediateDirectories: true)
                            var metadata: CFDictionary? = nil
                            if embedMetadata { metadata = DICOMImageExporter.buildEXIFMetadata(from: dicomFile, fields: nil) }
                            try exportCGImage(image, to: outFileURL, format: formatSel, quality: quality, metadata: metadata)
                            successCount += 1
                            if Self.exportBurnedInAnnotationIsYes(dicomFile.dataSet) { burnedIn += 1 }
                            if verbose { log += ExportConsole.bulkSuccessLine(path: outFileURL.path) + "\n" }
                        } catch {
                            errorCount += 1
                            if verbose { log += ExportConsole.bulkFailureLine(fileName: fileURL.lastPathComponent, message: error.localizedDescription) + "\n" }
                        }
                    }
                    log += ExportConsole.bulkSummaryLine(success: successCount, total: fileCount, failed: errorCount) + "\n"
                    if burnedIn > 0 { log += Self.exportBurnedInSummaryWarning(count: burnedIn) + "\n" }
                    // As the CLI: the summary line carries the failures, the exit status is 0.
                    return (log, 0)

                default:
                    return ("Error: Unknown operation '\(operation)'\n", 1)
                }
            } catch {
                return (log + "Error: \(error.localizedDescription)\n", 1)
            }
        }.value

        appendConsoleOutput(output)
        addToHistory(toolName: "dicom-export", command: commandPreview, exitCode: exitCode, output: output)
        consoleStatus = exitCode == 0 ? .success : .error
        service.setConsoleStatus(exitCode == 0 ? .success : .error)
        #else
        appendConsoleOutput("Error: Image export requires macOS or iOS (CoreGraphics).\n")
        consoleStatus = .error; service.setConsoleStatus(.error)
        addToHistory(toolName: "dicom-export", command: commandPreview, exitCode: 1, output: "Unsupported platform")
        #endif
    }

    // MARK: dicom-export standard texts (Sources/dicom-export/ExportStandard.swift, CLI-local)
    //
    // These mirror dicom-export's CLI-local ExportStandard.swift text for text; lifting them into
    // DICOMKit is the recorded follow-up. The DICOM inputs: PS3.3 2026a Table 10-3 ("The first
    // Frame shall be denoted as Frame number 1"), Table C.7-13 (Recommended Display Frame Rate
    // (0008,2144), Cine Rate (0018,0040), Frame Time (0018,1063) msec), Table C.7-9 (Burned In
    // Annotation (0028,0301), Enumerated Values YES / NO).

    nonisolated static let exportFrameNumberReference = "PS3.3 Table 10-3: the first Frame is Frame number 1"

    nonisolated static func exportFrameDeprecationNote(option: String, replacement: String) -> String {
        "warning: \(option) is deprecated (0-based index); use \(replacement) (numbered from 1, \(exportFrameNumberReference))"
    }

    /// Text for a Frame number the file does not have.
    nonisolated static func exportInvalidFrameNumberMessage(requested: Int, total: Int) -> String {
        "Frame number \(requested) does not exist. The file has \(total) frame\(total == 1 ? "" : "s"), numbered 1 to \(max(total, 1))."
    }

    /// A 0-based option and a Frame number option given together (exit 1).
    nonisolated static func exportFrameSelectionConflict(zeroBased: String, oneBased: String) -> String {
        "\(zeroBased) (deprecated, 0-based) and \(oneBased) (numbered from 1) cannot be used together"
    }

    /// `--apply-window` on contact-sheet / bulk (P-EXPORT-3): no effect, deprecated.
    nonisolated static func exportApplyWindowDeprecationNote(subcommand: String) -> String {
        "warning: \(subcommand) --apply-window is deprecated and has no effect: the file's VOI (Window Center (0028,1050) / Window Width (0028,1051), else VOI LUT Sequence (0028,3010), else the full pixel range) is always applied"
    }

    /// Burned In Annotation (0028,0301) == YES (PS3.3 Table C.7-9).
    nonisolated static func exportBurnedInAnnotationIsYes(_ dataSet: DataSet) -> Bool {
        dataSet.string(for: .burnedInAnnotation)?.trimmingCharacters(in: .whitespaces).uppercased() == "YES"
    }

    nonisolated static func exportBurnedInWarning(for path: String) -> String {
        "warning: \(path): Burned In Annotation (0028,0301) is YES — the exported image "
            + "contains burned-in text that identifies the patient"
    }

    nonisolated static func exportBurnedInSummaryWarning(count: Int) -> String {
        "warning: \(count) exported image(s) have Burned In Annotation (0028,0301) YES — "
            + "burned-in text that identifies the patient"
    }

    /// The frame rate of an `animate` export (dicom-export's CineFrameRate): `--fps`, else the
    /// Cine Module (PS3.3 Table C.7-13) — Recommended Display Frame Rate (0008,2144), then Cine
    /// Rate (0018,0040), then 1000 / Frame Time (0018,1063) (msec, C.7.6.5.1.1) — else 10.
    /// `source` is the PS3.6 name and tag of the attribute the rate came from.
    nonisolated static func exportCineFrameRate(explicit: Double?, dataSet: DataSet) -> (fps: Double, source: String) {
        func positive(_ raw: String?) -> Double? {
            guard let raw, let value = Double(raw.trimmingCharacters(in: .whitespaces)),
                  value.isFinite, value > 0 else { return nil }
            return value
        }
        if let explicit { return (explicit, "--fps") }
        if let rate = positive(dataSet.string(for: .recommendedDisplayFrameRate)) {
            return (rate, "Recommended Display Frame Rate (0008,2144)")
        }
        if let rate = positive(dataSet.string(for: .cineRate)) {
            return (rate, "Cine Rate (0018,0040)")
        }
        if let msec = positive(dataSet.string(for: .frameTime)) {
            return (1000.0 / msec, "Frame Time (0018,1063)")
        }
        return (10, "default")
    }

    // MARK: - dicom-script Execution

    private func executeDicomScript() async {
        let operation = paramValue("operation").isEmpty ? "run" : paramValue("operation")

        // Template operation emits a canned starter script (no script file needed),
        // matching the CLI's `dicom-script template <name>` stdout.
        if operation == "template" {
            let name = paramValue("templateName")
            // Emit the canned starter script from the shared DICOMKit
            // TemplateGenerator — the exact same templates the CLI uses.
            do {
                let template = try TemplateGenerator().generate(templateName: name)
                appendConsoleOutput(template)
                consoleStatus = .success; service.setConsoleStatus(.success)
                addToHistory(toolName: "dicom-script", command: commandPreview, exitCode: 0, output: template)
            } catch {
                // Shared ScriptError text ("Invalid template name: …") — the app used
                // to invent its own wording here.
                let msg = error.localizedDescription
                appendConsoleOutput("Error: \(msg)\n")
                consoleStatus = .error; service.setConsoleStatus(.error)
                addToHistory(toolName: "dicom-script", command: commandPreview, exitCode: 1, output: msg)
            }
            return
        }

        let scriptPath = paramValue("scriptPath")
        guard !scriptPath.isEmpty else {
            appendConsoleOutput("Error: Script file path is required.\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-script", command: commandPreview, exitCode: 1, output: "Missing script path")
            return
        }
        let dryRun = paramValue("dryRun") == "true"
        let verbose = paramValue("verbose") == "true"
        let parallel = paramValue("parallel") == "true"
        let variablesParam = paramValue("variables")
        let logParam = paramValue("log")
        let logScoped = securityScopedURLs["log"]
        let resolvedLog: String? = logParam.isEmpty ? nil
            : OutputAccess.resolveWritableURL(forPath: logParam, scopedURL: logScoped, subfolder: "dicom-script").url.path

        let scopedURL = securityScopedURLs["scriptPath"]
        let accessing = scopedURL?.startAccessingSecurityScopedResource() ?? false
        defer { if accessing { scopedURL?.stopAccessingSecurityScopedResource() } }
        let url = scopedURL ?? URL(fileURLWithPath: scriptPath)

        // Run/validate via the SHARED DICOMKit script engine (ScriptExecutor /
        // ScriptValidator) — the exact code the dicom-script CLI runs — so the app and
        // CLI emit byte-identical output. Output flows through the injected `log` closure
        // (the CLI prints the same lines to stdout); execution of nested tools isn't
        // supported in-app, so the runner throws (never reached on a dry run).
        let (output, exitCode): (String, Int) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
            var log = ""
            do {
                if operation == "validate" {
                    let validator = ScriptValidator(log: { log += $0 + "\n" })
                    let issues = try validator.validate(scriptPath: url.path, verbose: verbose)
                    // Verdict block via the SHARED ScriptConsole.
                    log += ScriptConsole.validationLines(issues: issues).map { $0 + "\n" }.joined()
                    return (log, issues.isEmpty ? 0 : 1)
                }
                // --variables is a repeatable array option in the CLI (one
                // KEY=VALUE per flag occurrence); split with the shared helper
                // so values containing spaces or commas survive intact, then
                // parse through the shared parser (which rejects '='-less
                // entries with the CLI's ScriptError.invalidVariable).
                let vars = try ScriptConsole.parseVariables(
                    CommandBuilderHelpers.splitMultiValue(variablesParam))
                let executor = ScriptExecutor(
                    runCommand: { tool, _ in
                        throw ScriptError.executionError(ScriptConsole.unsupportedRunnerMessage(tool: tool))
                    },
                    log: { log += $0 + "\n" })
                try executor.execute(scriptPath: url.path, variables: vars, parallel: parallel,
                                     verbose: verbose, dryRun: dryRun, logPath: resolvedLog)
                return (log, 0)
            } catch {
                return (log + "Error: \(error.localizedDescription)\n", 1)
            }
        }.value

        appendConsoleOutput(output)
        addToHistory(toolName: "dicom-script", command: commandPreview, exitCode: exitCode, output: output)
        consoleStatus = exitCode == 0 ? .success : .error
        service.setConsoleStatus(exitCode == 0 ? .success : .error)
    }

    /// Ensures the directories referenced by any output-path parameters exist,
    /// so writing output files succeeds. Only ever acts on a path the USER chose
    /// (fields start empty and are filled via Browse) — the sandbox grants write
    /// access through that selection; there is no longer any absolute-path
    /// entitlement backing a pre-seeded folder.
    private func ensureOutputDirectories() {
        for def in parameterDefinitions where def.parameterType == .outputPath {
            let value = paramValue(def.id)
            guard !value.isEmpty else { continue }
            let url = URL(fileURLWithPath: value)
            let dir = value.hasSuffix("/") ? url : url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Executes the currently selected command.
    /// For dicom-echo, performs a real C-ECHO via DICOMVerificationService.
    public func executeCommand() async {
        guard let tool = selectedTool() else { return }
        rebuildCommandPreview()
        ensureOutputDirectories()

        consoleOutput = ""
        consoleStatus = .running
        service.setConsoleStatus(.running)
        appendConsoleOutput("$ \(commandPreview)\n\n")

        switch tool.id {
        case "dicom-echo":
            await executeDicomEcho()
        case "dicom-query":
            await executeDicomQuery()
        case "dicom-send":
            await executeDicomSend()
        case "dicom-retrieve":
            await executeDicomRetrieve()
        case "dicom-qr":
            await executeDicomQR()
        case "dicom-mwl":
            await executeDicomMWL()
        case "dicom-mpps":
            await executeDicomMPPS()
        case "dicom-qido":
            await executeDicomQIDO()
        case "dicom-wado":
            await executeDicomWADO()
        case "dicom-stow":
            await executeDicomSTOW()
        case "dicom-ups":
            await executeDicomUPS()
        case "dicom-convert":
            await executeDicomConvert()
        case "dicom-validate":
            await executeDicomValidate()
        case "dicom-anon":
            await executeDicomAnon()
        case "dicom-info":
            await executeDicomInfo()
        case "dicom-dump":
            await executeDicomDump()
        case "dicom-tags":
            await executeDicomTags()
        case "dicom-diff":
            await executeDicomDiff()
        case "dicom-json":
            await executeDicomJSON()
        case "dicom-xml":
            await executeDicomXML()
case "dicom-uid":
    await executeDicomUID()
case "dicom-dcmdir":
            await executeDicomDcmdir()
        case "dicom-pdf":
            await executeDicomPdf()
        case "dicom-pixedit":
            await executeDicomPixedit()
case "dicom-split":
            await executeDicomSplit()
        case "dicom-merge":
            await executeDicomMerge()
case "dicom-archive":
            await executeDicomArchive()
case "dicom-compress":
    await executeDicomCompress()
case "dicom-study":
            await executeDicomStudy()
        case "dicom-image":
            await executeDicomImage()
        case "dicom-video":
            await executeDicomVideo()
        case "dicom-export":
            await executeDicomExport()
        case "dicom-script":
            await executeDicomScript()
        default:
            appendConsoleOutput("⚠ Command execution not yet supported for \(tool.name).\n")
            consoleStatus = .idle
            service.setConsoleStatus(.idle)
        }
    }

    // MARK: - dicom-convert Execution

    /// Performs DICOM file conversion: transfer syntax conversion or image export.
    private func executeDicomConvert() async {
        let inputPath = paramValue("inputPath")
        let outputPath = paramValue("output")
        let format = paramValue("format").isEmpty ? "dicom" : paramValue("format")
        let transferSyntax = paramValue("transfer-syntax")
        let qualityStr = paramValue("quality")
        let windowCenterStr = paramValue("window-center")
        let windowWidthStr = paramValue("window-width")
        let applyWindow = paramValue("apply-window") == "true"
        let frameStr = paramValue("frame")
        let stripPrivate = paramValue("strip-private") == "true"
        let recursive = paramValue("recursive") == "true"
        let validateOutput = paramValue("validate") == "true"
        let force = paramValue("force") == "true"

        guard !inputPath.isEmpty else {
            appendConsoleOutput("Error: Input file path is required.\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-convert", command: commandPreview, exitCode: 1, output: "Missing input path")
            return
        }
        guard !outputPath.isEmpty else {
            appendConsoleOutput("Error: Output path is required.\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-convert", command: commandPreview, exitCode: 1, output: "Missing output path")
            return
        }

        // Gain sandbox access via security-scoped URLs
        let inputScopedURL = securityScopedURLs["inputPath"]
        let outputScopedURL = securityScopedURLs["output"]
        let accessingInput = inputScopedURL?.startAccessingSecurityScopedResource() ?? false
        let accessingOutput = outputScopedURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if accessingInput { inputScopedURL?.stopAccessingSecurityScopedResource() }
            if accessingOutput { outputScopedURL?.stopAccessingSecurityScopedResource() }
        }

        let inputURL = inputScopedURL ?? URL(fileURLWithPath: inputPath)
        // Sandbox/TCC-resilient output: prefer the picker's scoped URL; else probe the typed
        // path and redirect to ~/Downloads/DICOMStudio if it isn't writable. Covers both the
        // DICOM-convert Data write and the image-export CGImageDestination below.
        let _convOut = OutputAccess.resolveWritableURL(forPath: outputPath, scopedURL: outputScopedURL, subfolder: "dicom-convert")
        var outputURL = _convOut.url
        if let note = _convOut.note { appendConsoleOutput(note + "\n") }

        appendConsoleOutput("Input:  \(inputURL.path)\n")
        appendConsoleOutput("Output: \(outputURL.path)\n")
        appendConsoleOutput("Format: \(format)\n")
        if format == "dicom" && !transferSyntax.isEmpty {
            appendConsoleOutput("Transfer Syntax: \(transferSyntax)\n")
        }
        appendConsoleOutput("\n")

        // Check if the input is a directory
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory) else {
            appendConsoleOutput("Error: Input path not found: \(inputURL.path)\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-convert", command: commandPreview, exitCode: 1, output: "Input not found")
            return
        }

        // When converting a single file and the output path is (or was chosen as) a
        // directory, write the result *inside* that directory using the input filename.
        // Resolved through the SAME shared `OutputPathResolver` + `ConvertConsole`
        // extension map the CLI uses (dicom-convert's `convert()`), so the two surfaces
        // cannot disagree on the destination. This previously duplicated both the
        // directory test and the format→extension switch here.
        if !isDirectory.boolValue {
            outputURL = URL(fileURLWithPath: OutputPathResolver.resolveFileOutput(
                output: outputURL.path,
                input: inputURL.path,
                fileExtension: ConvertConsole.fileExtension(forFormat: format)))
            // The GUI can hand us a destination whose parent doesn't exist yet; create it
            // so the write below doesn't fail (the CLI does the same after resolving).
            try? FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } else {
            // Directory-to-directory: make sure output dir exists
            try? FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        }

        if isDirectory.boolValue {
            guard recursive else {
                appendConsoleOutput("Error: Directory conversion requires the Recursive option to be enabled.\n")
                consoleStatus = .error
                service.setConsoleStatus(.error)
                addToHistory(toolName: "dicom-convert", command: commandPreview, exitCode: 1, output: "Recursive required")
                return
            }
            await convertDirectory(
                inputURL: inputURL, outputURL: outputURL,
                format: format, transferSyntax: transferSyntax,
                quality: Int(qualityStr) ?? 90,
                windowCenter: Double(windowCenterStr), windowWidth: Double(windowWidthStr),
                applyWindow: applyWindow, frame: Int(frameStr),
                stripPrivate: stripPrivate, validateOutput: validateOutput, force: force
            )
        } else {
            do {
                try convertSingleFile(
                    inputURL: inputURL, outputURL: outputURL,
                    format: format, transferSyntax: transferSyntax,
                    quality: Int(qualityStr) ?? 90,
                    windowCenter: Double(windowCenterStr), windowWidth: Double(windowWidthStr),
                    applyWindow: applyWindow, frame: Int(frameStr),
                    stripPrivate: stripPrivate, validateOutput: validateOutput, force: force
                )
                appendConsoleOutput("\n✅ Conversion completed successfully.\n")
                consoleStatus = .success
                service.setConsoleStatus(.success)
                addToHistory(toolName: "dicom-convert", command: commandPreview, exitCode: 0, output: "Success")
            } catch {
                // Same failure report as the dicom-convert CLI (shared ConvertConsole).
                appendConsoleOutput("\n" + ConvertConsole.failureReport(for: error))
                consoleStatus = .error
                service.setConsoleStatus(.error)
                addToHistory(toolName: "dicom-convert", command: commandPreview, exitCode: 1, output: ConvertConsole.failureSummary(for: error))
            }
        }
    }

    /// Converts a single DICOM file to the specified format.
    private func convertSingleFile(
        inputURL: URL, outputURL: URL,
        format: String, transferSyntax: String,
        quality: Int,
        windowCenter: Double?, windowWidth: Double?,
        applyWindow: Bool, frame: Int?,
        stripPrivate: Bool, validateOutput: Bool, force: Bool
    ) throws {
        let fileData = try Data(contentsOf: inputURL)
        let dicomFile = try DICOMFile.read(from: fileData, force: force)

        switch format {
        case "png", "jpeg", "tiff":
            try exportDicomImage(
                dicomFile: dicomFile, outputURL: outputURL, format: format,
                quality: quality, windowCenter: windowCenter, windowWidth: windowWidth,
                applyWindow: applyWindow, frame: frame
            )
        default:
            // DICOM transfer syntax conversion
            guard !transferSyntax.isEmpty else {
                throw ConvertError.missingTransferSyntax
            }
            let targetEncoding = try parseTransferSyntax(transferSyntax)

            // Shared process → output pipeline (identical bytes in CLI and app). The resolved
            // intent drives reversible-vs-irreversible encoding into the general UIDs and the
            // Lossy Image Compression provenance attributes.
            let outcome = try DICOMConverter.convertToDICOM(
                dicomFile: dicomFile,
                to: targetEncoding,
                stripPrivate: stripPrivate
            )
            let outputData = outcome.data

            // Create output directory if needed
            let outputDir = outputURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

            try outputData.write(to: outputURL)
            // Console via the SHARED ConvertConsole (DICOMKit) — the CLI's exact
            // (terse) output: one transcode line when bytes were transcoded,
            // nothing extra. The old app-only Read/Wrote/Transfer-Syntax chrome
            // made terminal-compare diff on every run.
            appendConsoleOutput(ConvertConsole.transcodeLine(
                wasTranscoded: outcome.wasTranscoded,
                sourceUID: outcome.sourceSyntax.uid, targetUID: outcome.targetSyntax.uid,
                isLossless: outcome.isLossless))

            if validateOutput {
                // Mirror the CLI: re-read to validate, silent on success.
                let validationData = try Data(contentsOf: outputURL)
                _ = try DICOMFile.read(from: validationData, force: false)
            }
        }
    }

    /// Exports DICOM pixel data to an image format (PNG, JPEG, or TIFF).
    private func exportDicomImage(
        dicomFile: DICOMFile, outputURL: URL,
        format: String, quality: Int,
        windowCenter: Double?, windowWidth: Double?,
        applyWindow: Bool, frame: Int?
    ) throws {
        #if canImport(CoreGraphics)
        let pixelData = try dicomFile.tryPixelData()
        let frameIndex = frame ?? 0
        guard frameIndex >= 0 && frameIndex < pixelData.descriptor.numberOfFrames else {
            throw ConvertError.invalidFrame(frameIndex, pixelData.descriptor.numberOfFrames)
        }

        guard let imageFormat = ExportImageFormat(rawValue: format) else {
            throw ConvertError.exportFailed
        }

        // Create output directory if needed
        let outputDir = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // Shared render (incl. window resolution) + shared encode → identical raster in CLI and app.
        let image = try DICOMImageExporter.renderFrameForExport(
            file: dicomFile, pixelData: pixelData, frameIndex: frameIndex,
            applyWindow: applyWindow, windowCenter: windowCenter, windowWidth: windowWidth
        )
        try DICOMImageExporter.exportCGImage(
            image, to: outputURL, format: imageFormat, quality: quality, metadata: nil
        )
        // Image export prints nothing — the CLI is silent here (ConvertConsole
        // has no export line), so the app console must be too.
        #else
        throw ConvertError.unsupportedPlatform
        #endif
    }

    /// Recursively converts all DICOM files in a directory.
    private func convertDirectory(
        inputURL: URL, outputURL: URL,
        format: String, transferSyntax: String,
        quality: Int,
        windowCenter: Double?, windowWidth: Double?,
        applyWindow: Bool, frame: Int?,
        stripPrivate: Bool, validateOutput: Bool, force: Bool
    ) async {
        do {
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        } catch {
            appendConsoleOutput("Error: Could not create output directory: \(error.localizedDescription)\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-convert", command: commandPreview, exitCode: 1, output: error.localizedDescription)
            return
        }

        // Shared, sorted directory walk — the same gatherer the dicom-convert CLI
        // uses, so both surfaces convert the same files in the same order.
        guard let fileURLs = FileGatherer.regularFiles(under: inputURL) else {
            appendConsoleOutput("Error: Failed to enumerate directory.\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-convert", command: commandPreview, exitCode: 1, output: "Enumeration failed")
            return
        }

        var fileCount = 0
        var successCount = 0
        var errorCount = 0

        for fileURL in fileURLs {

            fileCount += 1
            let relativePath = fileURL.path.replacingOccurrences(of: inputURL.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            var outFileURL = outputURL.appendingPathComponent(relativePath)
            // Image formats must not keep the source `.dcm` extension: the bytes are
            // PNG/JPEG/TIFF, so retag to match contents (the single-file path already
            // does this via OutputPathResolver). `dicom` keeps its original name.
            if format != "dicom" {
                outFileURL.deletePathExtension()
                outFileURL.appendPathExtension(ConvertConsole.fileExtension(forFormat: format))
            }
            let outDir = outFileURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

            do {
                try convertSingleFile(
                    inputURL: fileURL, outputURL: outFileURL,
                    format: format, transferSyntax: transferSyntax,
                    quality: quality, windowCenter: windowCenter, windowWidth: windowWidth,
                    applyWindow: applyWindow, frame: frame,
                    stripPrivate: stripPrivate, validateOutput: validateOutput, force: force
                )
                successCount += 1
                appendConsoleOutput(ConvertConsole.batchProgressLine(success: true, relativePath: relativePath, error: nil))
            } catch {
                errorCount += 1
                appendConsoleOutput(ConvertConsole.batchProgressLine(success: false, relativePath: relativePath, error: ConvertConsole.failureSummary(for: error)))
            }
        }

        // Summary via the SHARED ConvertConsole — the CLI's exact
        // "Conversion complete: …" line (not the old app-only "Batch conversion…").
        appendConsoleOutput(ConvertConsole.batchSummary(succeeded: successCount, total: fileCount, failed: errorCount))
        if errorCount == 0 {
            consoleStatus = .success
            service.setConsoleStatus(.success)
            addToHistory(toolName: "dicom-convert", command: commandPreview, exitCode: 0,
                         output: "\(successCount)/\(fileCount) converted")
        } else {
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-convert", command: commandPreview, exitCode: 1,
                         output: "\(successCount)/\(fileCount) succeeded, \(errorCount) failed")
        }
    }

    /// Parses a transfer syntax name string to a TransferSyntax value.
    ///
    /// Single source of truth: the shared ``DICOMConverter`` target catalog (DICOMKit),
    /// so the CLI Workshop accepts exactly the same tokens (UID / CamelCase / kebab /
    /// short aliases) as the `dicom-convert` CLI.
    private func parseTransferSyntax(_ name: String) throws -> SelectableEncoding {
        // Resolve the full encoding (UID + intent) so the app matches the CLI: `…-lossless`
        // names encode reversibly into the general UID, `…-lossy` names carry the provenance.
        guard let encoding = DICOMConverter.resolveTargetEncoding(name) else {
            throw ConvertError.unknownTransferSyntax(name)
        }
        return encoding
    }

    // MARK: - Local SCP Listener Management

    /// Starts the local DICOM SCP listener so other applications can connect,
    /// send C-ECHO (verification), and C-STORE (push files) to DICOMStudio.
    ///
    /// The SCP uses ``DICOMStorageServer`` which already accepts all common
    /// storage SOP classes as well as the Verification SOP Class, so incoming
    /// C-ECHO requests are handled automatically alongside C-STORE sub-operations.
    public func startLocalSCP() async {
        guard !scpIsRunning else { return }
        let portNum = UInt16(scpPort) ?? 11112
        let aetStr = scpAETitle.isEmpty ? "DICOMSTUDIO" : scpAETitle
        let outputURL = URL(fileURLWithPath:
            scpOutputDir.isEmpty
                ? (NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first
                    ?? NSTemporaryDirectory())
                : scpOutputDir
        )

        do {
            let aeTitle = try AETitle(aetStr)
            let config = StorageSCPConfiguration(aeTitle: aeTitle, port: portNum)
            let delegate = DICOMStudioSCPDelegate(storageDir: outputURL)
            let scp = DICOMStorageServer(configuration: config, delegate: delegate)
            try await scp.start()
            storageSCP = scp
            scpIsRunning = true
            scpStatusMessage = "Listening on port \(portNum) as \(aetStr)"
            appendConsoleOutput("\n🔌 Local SCP started — port \(portNum), AE Title: \(aetStr)\n")
            appendConsoleOutput("   Files will be written to: \(outputURL.path)\n\n")
            appLog.insert(SCPLogEntry(
                level: .info,
                message: "Local SCP started on port \(portNum) as \(aetStr)"
            ), at: 0)

            // Consume the event stream and relay updates to main-actor state
            scpEventTask = Task { [weak self] in
                guard let self else { return }
                let eventStream = await scp.events
                for await event in eventStream {
                    await MainActor.run { self.handleSCPEvent(event) }
                }
            }
        } catch {
            scpStatusMessage = "Failed to start: \(error.localizedDescription)"
            appendConsoleOutput("\n❌ Failed to start local SCP: \(error.localizedDescription)\n")
            appLog.insert(SCPLogEntry(
                level: .error,
                message: "Failed to start SCP: \(error.localizedDescription)"
            ), at: 0)
        }
    }

    /// Stops the local DICOM SCP listener.
    public func stopLocalSCP() async {
        guard scpIsRunning, let scp = storageSCP else { return }
        await scp.stop()
        scpEventTask?.cancel()
        scpEventTask = nil
        storageSCP = nil
        scpIsRunning = false
        scpStatusMessage = "SCP stopped"
        appendConsoleOutput("\n🔌 Local SCP stopped\n")
        appLog.insert(SCPLogEntry(level: .info, message: "Local SCP stopped"), at: 0)
    }

    private func handleSCPEvent(_ event: StorageServerEvent) {
        switch event {
        case .fileReceived(let file):
            let path = scpOutputDir + "/" + file.sopInstanceUID + ".dcm"
            scpReceivedFiles.insert(path, at: 0)
            appendConsoleOutput("  📥 Received: \(file.sopInstanceUID)"
                + " from \(file.callingAETitle) → \(path)\n")
            appLog.insert(SCPLogEntry(
                level: .fileReceived,
                message: "Received \(file.sopInstanceUID).dcm",
                remoteAETitle: file.callingAETitle
            ), at: 0)
        case .associationEstablished(let info):
            appendConsoleOutput("  🔗 Association from \(info.callingAETitle)"
                + " (\(info.remoteHost):\(info.remotePort))\n")
            appLog.insert(SCPLogEntry(
                level: .connection,
                message: "Association established from \(info.callingAETitle)",
                remoteAETitle: info.callingAETitle,
                remoteHost: "\(info.remoteHost):\(info.remotePort)"
            ), at: 0)
        case .associationRejected(let ae, let reason):
            appendConsoleOutput("  ⛔ Rejected association from \(ae): \(reason)\n")
            appLog.insert(SCPLogEntry(
                level: .warning,
                message: "Association rejected from \(ae): \(reason)",
                remoteAETitle: ae
            ), at: 0)
        case .error(let error):
            appendConsoleOutput("  ❌ SCP error: \(error.localizedDescription)\n")
            scpStatusMessage = "SCP error: \(error.localizedDescription)"
            appLog.insert(SCPLogEntry(
                level: .error,
                message: "SCP error: \(error.localizedDescription)"
            ), at: 0)
            // Reset running state so the listener can be restarted after
            // a failure (e.g. port already in use).
            scpIsRunning = false
            scpEventTask?.cancel()
            scpEventTask = nil
            storageSCP = nil
        default:
            break
        }
    }

    /// Clears the application event log.
    public func clearAppLog() {
        appLog.removeAll()
    }

    /// Parses host string that may contain an embedded port (e.g. "server:4242").
    /// Returns the host and resolved port, using the given explicit port if non-nil.
    private func resolveHostPort(_ hostValue: String, explicitPort: String?) -> (host: String, port: UInt16)? {
        guard !hostValue.isEmpty else { return nil }
        var host = hostValue
        var port: UInt16 = 11112

        // Strip pacs:// prefix for backward compatibility with saved defaults
        if host.hasPrefix("pacs://") {
            host = String(host.dropFirst(7))
        }

        // Check if host contains embedded port
        if let lastColon = host.lastIndex(of: ":") {
            let portStr = String(host[host.index(after: lastColon)...])
            if let embeddedPort = UInt16(portStr) {
                host = String(host[..<lastColon])
                port = embeddedPort
            }
        }

        // Explicit --port overrides embedded port
        if let ep = explicitPort, let explicitPortNum = UInt16(ep) {
            port = explicitPortNum
        }

        guard !host.isEmpty else { return nil }
        return (host, port)
    }

    // MARK: - dicom-validate Execution

    /// Validates DICOM files for IOD conformance, matching dicom-validate CLI output exactly.
    private func executeDicomValidate() async {
        // Mirrors dicom-validate's run(): the same shared engine (DICOMValidator), the same
        // directory walk (FileGatherer.regularFiles), the same renderer and exit code
        // (ValidationReport), and the CLI's refusals (ArgumentParser ValidationError, exit 64).
        let inputPath = paramValue("inputPath")
        guard !inputPath.isEmpty else {
            appendConsoleOutput("Error: Missing expected argument '<input-path>'\n")
            addToHistory(toolName: "dicom-validate", command: commandPreview, exitCode: 64, output: "Missing input path")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            return
        }

        let levelStr  = paramValue("level")
        let level     = Int(levelStr) ?? 3
        let iodRaw    = paramValue("iod").trimmingCharacters(in: .whitespaces)
        let detailed  = paramValue("detailed") == "true"
        let recursive = paramValue("recursive") == "true"
        let strict    = paramValue("strict") == "true"
        let format    = paramValue("format").isEmpty ? "text" : paramValue("format")
        let outputPath = paramValue("output")
        let force     = paramValue("force") == "true"

        // Gain sandbox access via security-scoped URLs registered by the file picker.
        let inputScopedURL  = securityScopedURLs["inputPath"]
        let outputScopedURL = securityScopedURLs["output"]
        let accessingInput  = inputScopedURL?.startAccessingSecurityScopedResource()  ?? false
        let accessingOutput = outputScopedURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if accessingInput  { inputScopedURL?.stopAccessingSecurityScopedResource() }
            if accessingOutput { outputScopedURL?.stopAccessingSecurityScopedResource() }
        }
        let inputURL = inputScopedURL ?? URL(fileURLWithPath: inputPath)
        // --iod takes a PS3.6 Table A-1 keyword or UID as well as the engine's own names.
        let iod: String? = iodRaw.isEmpty ? nil : Self.validateIODEngineName(for: iodRaw)
        let outputFormat: ValidationOutputFormat = format == "json" ? .json : .text

        let (output, code) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory) else {
                return ("Error: Input path not found: \(inputURL.path)\n", 64)
            }
            guard level >= 1 && level <= 5 else {
                return ("Error: Validation level must be between 1 and 5\n", 64)
            }
            let validator = DICOMValidator(level: level, iod: iod, force: force)
            func validateFile(_ url: URL) throws -> DICOMKit.ValidationResult {
                try validator.validate(data: try Data(contentsOf: url), filePath: url.path)
            }

            var results: [DICOMKit.ValidationResult] = []
            do {
                if isDirectory.boolValue {
                    guard recursive else {
                        return ("Error: Directory validation requires --recursive flag\n", 64)
                    }
                    guard let fileURLs = FileGatherer.regularFiles(under: inputURL) else {
                        return ("Error: Failed to enumerate directory: \(inputURL.path)\n", 64)
                    }
                    for fileURL in fileURLs {
                        do {
                            results.append(try validateFile(fileURL))
                        } catch {
                            results.append(DICOMKit.ValidationResult(
                                filePath: fileURL.path, isValid: false,
                                errors: [DICOMKit.ValidationIssue(level: .error, message: error.localizedDescription, tag: nil)],
                                warnings: []))
                        }
                    }
                } else {
                    results = [try validateFile(inputURL)]
                }
            } catch {
                return ("Error: \(error.localizedDescription)\n", 1)
            }

            let report = DICOMKit.ValidationReport(results: results, detailed: detailed, strict: strict)
            let outputText: String
            do {
                outputText = try report.render(format: outputFormat)
            } catch {
                return ("Error: \(error.localizedDescription)\n", 1)
            }

            var console = ""
            if !outputPath.isEmpty {
                // Directory-valued --output resolves to <dir>/<input-stem>.json|.txt by the
                // shared resolver, the exact call dicom-validate makes.
                let resolvedOutputPath = OutputPathResolver.resolveFileOutput(
                    output: outputScopedURL?.path ?? outputPath, input: inputURL.path,
                    fileExtension: outputFormat == .json ? "json" : "txt")
                do {
                    let written = try OutputAccess.writeString(outputText, toPath: resolvedOutputPath,
                                                               scopedURL: outputScopedURL, subfolder: "Validate")
                    if let note = written.note { console += note + "\n" }
                } catch {
                    return ("Error: Failed to write validation report to \(resolvedOutputPath): \(error.localizedDescription)\n", 64)
                }
            } else {
                console = outputText
            }
            return (console, Int(report.exitCode()))
        }.value

        appendConsoleOutput(output)
        addToHistory(toolName: "dicom-validate", command: commandPreview, exitCode: code, output: output)
        consoleStatus = code == 0 ? .success : .error
        service.setConsoleStatus(code == 0 ? .success : .error)
    }

    /// Engine IOD name per SOP Class UID (PS3.6 Table A-1), as `DICOMValidator` detects it from
    /// (0008,0016). dicom-validate's `IODOption` maps the same seven classes; DICOMValidator
    /// does not export the map, so the Workshop carries it until it is lifted into DICOMKit.
    nonisolated static let validateEngineNameBySOPClassUID: [String: String] = [
        "1.2.840.10008.5.1.4.1.1.2": "CTImageStorage",                          // CT Image Storage
        "1.2.840.10008.5.1.4.1.1.4": "MRImageStorage",                          // MR Image Storage
        "1.2.840.10008.5.1.4.1.1.1": "CRImageStorage",                          // Computed Radiography Image Storage
        "1.2.840.10008.5.1.4.1.1.6.1": "USImageStorage",                        // Ultrasound Image Storage
        "1.2.840.10008.5.1.4.1.1.7": "SecondaryCaptureImageStorage",            // Secondary Capture Image Storage
        "1.2.840.10008.5.1.4.1.1.11.1": "GrayscaleSoftcopyPresentationState",   // Grayscale Softcopy Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.11.3": "PseudoColorSoftcopyPresentationState", // Pseudo-Color Softcopy Presentation State Storage
    ]

    /// The engine IOD name for an `--iod` value: a PS3.6 Table A-1 keyword (any case) or SOP
    /// Class UID of a supported class, else the value itself (the engine's short names, or an
    /// unsupported IOD the engine reports as "IOD validation not implemented").
    nonisolated static func validateIODEngineName(for value: String) -> String {
        if value.lowercased() == "us" { return "USImageStorage" }   // the engine knows "ultrasound" only
        let uid: String?
        if let entry = UIDDictionary.lookup(uid: value) { uid = entry.uid }
        else if let entry = UIDDictionary.lookup(keyword: value) { uid = entry.uid }
        else {
            let lower = value.lowercased()
            uid = UIDDictionary.sopClasses.first { $0.keyword.lowercased() == lower }?.uid
        }
        guard let uid else { return value }
        if let name = validateEngineNameBySOPClassUID[uid] { return name }
        if DICOMCore.SRDocumentType.isSRDocument(sopClassUID: uid) { return "StructuredReport" }
        return value
    }

    // MARK: - dicom-anon Execution

    /// Anonymizes DICOM files, matching dicom-anon CLI output exactly.
    private func executeDicomAnon() async {
        let inputPath = paramValue("inputPath")
        guard !inputPath.isEmpty else {
            appendConsoleOutput("Error: Input path is required.\n")
            addToHistory(toolName: "dicom-anon", command: commandPreview, exitCode: 1, output: "Missing input path")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            return
        }

        let outputPath     = paramValue("output")
        let profileStr     = paramValue("profile").isEmpty ? "legacy-basic" : paramValue("profile")
        let shiftDaysStr   = paramValue("shift-dates")
        let regenUIDs      = paramValue("regenerate-uids") == "true"
        let removeTagsRaw  = paramValue("remove")
        let replaceRaw     = paramValue("replace")
        let keepTagsRaw    = paramValue("keep")
        let recursive      = paramValue("recursive") == "true"
        let dryRun         = paramValue("dry-run") == "true"
        let backup         = paramValue("backup") == "true"
        let auditLogPath   = paramValue("audit-log")
        let force          = paramValue("force") == "true"
        let verbose        = paramValue("verbose") == "true"

        // Gain sandbox access via security-scoped URLs registered by the file picker.
        let inputScopedURL  = securityScopedURLs["inputPath"]
        let outputScopedURL = securityScopedURLs["output"]
        let accessingInput  = inputScopedURL?.startAccessingSecurityScopedResource()  ?? false
        let accessingOutput = outputScopedURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if accessingInput  { inputScopedURL?.stopAccessingSecurityScopedResource() }
            if accessingOutput { outputScopedURL?.stopAccessingSecurityScopedResource() }
        }

        // Map the CLI profile string to the app's profile. The app's profiles are the
        // CLI's deprecated `legacy-*` attribute lists; `ps315` and its alias `basic`
        // (the PS3.15 Basic Profile, the CLI default since 2026-10-01) have no app
        // profile yet, so they are refused rather than silently run as legacy-basic.
        let profile: AnonymizationProfile
        switch profileStr.lowercased() {
        case "legacy-clinical-trial", "clinical-trial", "clinicaltrial": profile = .clinicalTrial
        case "legacy-research", "research":                               profile = .research
        case "legacy-basic":                                              profile = .basic
        case "ps315", "basic":
            appendConsoleOutput("Error: --profile \(profileStr) is the PS3.15 Basic Application Level Confidentiality Profile (Table E.1-1), which the Workshop cannot run yet; use legacy-basic, legacy-clinical-trial or legacy-research, or run dicom-anon in the terminal.\n")
            addToHistory(toolName: "dicom-anon", command: commandPreview, exitCode: 1, output: "PS3.15 profile not available in the Workshop")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            return
        default:
            appendConsoleOutput("Error: Unknown --profile '\(profileStr)': use legacy-basic, legacy-clinical-trial or legacy-research (dicom-anon also accepts ps315 and its alias basic).\n")
            addToHistory(toolName: "dicom-anon", command: commandPreview, exitCode: 1, output: "Unknown profile")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            return
        }

        let shiftDays = Int(shiftDaysStr)

        // Parse tag lists via the shared semicolon `splitMultiValue` convention (the same
        // splitter `buildCommand()` uses for these repeatable flags). Do NOT split on
        // commas: a tag is written `GGGG,EEEE` (and --replace is `GGGG,EEEE=value`), so
        // comma-splitting `0010,0010` would shred it into "0010"+"0010", match nothing,
        // and silently drop the modifier (F19 — same class as the F18 xml --filter-tag bug).
        let removeTags   = CommandBuilderHelpers.splitMultiValue(removeTagsRaw)
        let replacePairs = CommandBuilderHelpers.splitMultiValue(replaceRaw)
        let keepTags     = CommandBuilderHelpers.splitMultiValue(keepTagsRaw)

        // Build a SecurityViewModel scoped just for this run.
        // Resolve a sandbox-writable output path: scoped URL → ~/Downloads path → fallback.
        let (resolvedOutputPath, outputRedirectNote) = SecurityViewModel.resolveWritableOutput(
            path: outputScopedURL?.path ?? outputPath,
            scopedURL: outputScopedURL
        )
        if let note = outputRedirectNote { appendConsoleOutput(note) }

        // Parity with the dicom-anon CLI: a single-file run with no output path (and not
        // a dry run) has nowhere to write, so error instead of running and reporting
        // success on a file that was never anonymized. Directory runs resolve an output
        // dir separately and are unaffected.
        var anonInputIsDir: ObjCBool = false
        let anonInputPathResolved = (inputScopedURL ?? URL(fileURLWithPath: inputPath)).path
        let anonInputExists = FileManager.default.fileExists(atPath: anonInputPathResolved, isDirectory: &anonInputIsDir)
        if !dryRun && resolvedOutputPath.isEmpty && anonInputExists && !anonInputIsDir.boolValue {
            appendConsoleOutput("Error: Anonymization requires an output path (or enable Dry Run to preview without writing).\n")
            addToHistory(toolName: "dicom-anon", command: commandPreview, exitCode: 1, output: "Output required")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            return
        }

        let secVM = SecurityViewModel()
        secVM.anonInputPath       = (inputScopedURL ?? URL(fileURLWithPath: inputPath)).path
        secVM.anonOutputPath      = resolvedOutputPath
        secVM.anonProfile         = profile
        secVM.anonShiftDatesEnabled = shiftDays != nil
        secVM.anonShiftDays       = shiftDays ?? 0
        secVM.anonRegenerateUIDs  = regenUIDs
        secVM.anonRemoveTags      = removeTags
        secVM.anonReplacePairs    = replacePairs
        secVM.anonKeepTags        = keepTags
        secVM.anonRecursive       = recursive
        secVM.anonDryRun          = dryRun
        secVM.anonBackup          = backup
        secVM.anonAuditLogPath    = auditLogPath
        secVM.anonForce           = force
        secVM.anonVerbose         = verbose
        secVM.anonInputScopedURL  = inputScopedURL
        secVM.anonOutputScopedURL = outputScopedURL

        secVM.runAnonymization()

        var waited = 0
        while secVM.anonIsRunning && waited < 300 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 1
        }

        let output = secVM.anonOutput
        appendConsoleOutput(output)

        // (The single-file "no output path" case is rejected up front now, matching the
        // dicom-anon CLI — see the guard above.)

        // Structured exit code from the run itself (CLI rule: any failed file → 1) —
        // never derived by sniffing the output text.
        let exitCode = secVM.anonLastExitCode
        addToHistory(toolName: "dicom-anon", command: commandPreview, exitCode: exitCode, output: output)
        consoleStatus = exitCode == 0 ? .success : .error
        service.setConsoleStatus(exitCode == 0 ? .success : .error)
    }

    // MARK: - dicom-info Execution

    /// Displays DICOM file metadata — output matches `dicom-info` CLI tool exactly.
    private func executeDicomInfo() async {
        let inputPath = paramValue("inputPath")
        guard !inputPath.isEmpty else {
            appendConsoleOutput("Error: Input file path is required.\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-info", command: commandPreview, exitCode: 1, output: "Missing input path")
            return
        }

        let format      = paramValue("format").isEmpty ? "text" : paramValue("format")
        let tagFilters  = CommandBuilderHelpers.splitMultiValue(paramValue("tag"))
        let showPrivate = paramValue("show-private") == "true"
        let statistics  = paramValue("statistics") == "true"
        let force       = paramValue("force") == "true"

        let inputScopedURL = securityScopedURLs["inputPath"]
        let accessing = inputScopedURL?.startAccessingSecurityScopedResource() ?? false
        defer { if accessing { inputScopedURL?.stopAccessingSecurityScopedResource() } }

        let fileURL = inputScopedURL ?? URL(fileURLWithPath: inputPath)

        let (output, exitCode) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
            do {
                // dicom-info throws ArgumentParser's ValidationError here: exit 64.
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    return ("Error: File not found: \(fileURL.path)\n", 64)
                }
                let data = try Data(contentsOf: fileURL)
                let dicomFile = try DICOMFile.read(from: data, force: force)
                // Render via the shared DICOMKit.MetadataPresenter — the exact same
                // code the `dicom-info` CLI uses — so UI and CLI output cannot drift.
                let presenter = MetadataPresenter(
                    file: dicomFile, filterTags: tagFilters,
                    includePrivate: showPrivate, showStats: statistics
                )
                let rendered = try presenter.render(format: MetadataOutputFormat(rawValue: format) ?? .text)
                return (rendered, 0)
            } catch {
                return ("Error: \(error.localizedDescription)\n", 1)
            }
        }.value

        appendConsoleOutput(output)
        addToHistory(toolName: "dicom-info", command: commandPreview, exitCode: exitCode, output: output)
        consoleStatus = exitCode == 0 ? .success : .error
        service.setConsoleStatus(exitCode == 0 ? .success : .error)
    }

    // MARK: - ⚠️ TESTING-ONLY: terminal-vs-app parity check (all tools)
    //
    // Runs the REAL `dicom-*` binary for the selected tool as a subprocess and
    // compares its output to the app's in-process output, shown side-by-side in
    // the console. Requires the App Sandbox to be DISABLED. REMOVE BEFORE
    // PRODUCTION — see CLIToolTerminalCompare.swift and memory
    // `dicom-info-terminal-compare-testonly`.

    /// Clears the active terminal-compare result (returns the console to normal).
    public func clearTerminalCompare() {
        terminalCompareResult = nil
    }

    /// TESTING-ONLY. Runs the selected tool in-process AND via its real binary
    /// (argv taken verbatim from the command preview), then stores a side-by-side
    /// comparison. Works for any tool.
    public func runTerminalCompare() async {
        #if os(macOS)
        guard let tool = selectedToolID, !commandPreview.isEmpty else { return }

        // In-app-only states render the preview fully commented out (e.g.
        // dicom-mwl create, DICOMweb basic auth) — there is no CLI-representable
        // command to compare against, so report that instead of exec'ing "#".
        if commandPreview.hasPrefix("#") {
            terminalCompareResult = CLIToolCompareResult(
                toolName: tool,
                appOutput: "",
                terminalOutput: "",
                binaryPath: nil,
                commandLine: commandPreview,
                matched: false,
                differingLineCount: 0,
                note: "This state is in-app only — the real CLI has no equivalent command to compare against.")
            return
        }

        isRunningTerminalCompare = true
        terminalCompareResult = nil
        defer { isRunningTerminalCompare = false }

        // 1. App (in-process) output — drive the real Studio code path.
        clearConsoleOutput()
        await executeCommand()
        let appOutput = consoleOutput

        // 2. argv from the exact command preview (single source of truth).
        let argv = CLIToolTerminalCompare.shellSplit(commandPreview)
        guard let executable = argv.first else { return }
        let arguments = Array(argv.dropFirst())

        // 2a. Rebuild the tool FRESH (release) before running it, so the Compare-CLI
        //     panel can NEVER compare against a stale binary — the CLI output must
        //     always reflect the latest source (project requirement). Release is the
        //     configuration that ships. On build failure, surface the error instead of
        //     silently comparing against a stale/missing binary. The rebuild is
        //     incremental, so it is near-instant when nothing changed.
        let buildOutcome = await Task.detached { CLIToolBuilder.build(products: [executable]) }.value
        guard buildOutcome.success else {
            terminalCompareResult = CLIToolCompareResult(
                toolName: tool,
                appOutput: appOutput,
                terminalOutput: "Build failed — refusing to compare against a stale binary.\n\n"
                    + String(buildOutcome.log.suffix(4000)),
                binaryPath: nil,
                commandLine: commandPreview,
                matched: false,
                differingLineCount: 0,
                note: "Build failed for \(executable) — fix the build, then Compare again.")
            return
        }
        let freshBinDir = buildOutcome.binDir

        // 3. Grant file access (sandbox-off test build), then run the binary AND
        //    compute the comparison entirely off the main actor. A large dump can
        //    be thousands of lines, so use a cheap O(n) line comparison — an
        //    O(n·m) LCS on the main thread would freeze the UI (the compare view
        //    shows raw side-by-side text, not a line-level diff).
        let basename = compareFixtureBasename()
        let scopedURLs = securityScopedURLs.values.map { ($0, $0.startAccessingSecurityScopedResource()) }
        let computed = await Task.detached { () -> (CLIToolTerminalCompare.Outcome, Int) in
            // Pin the binary to the freshly-built dir so a stale binary elsewhere on
            // disk (or a more-recently-built debug build) can never shadow it.
            let oc = CLIToolTerminalCompare.run(tool: executable, arguments: arguments, binDir: freshBinDir)
            let appLines  = CLIToolTerminalCompare.normalize(appOutput, fixtureBasename: basename)
            // Compare against the FULL terminal output (stdout + stderr). Some tools
            // (e.g. `dicom-echo --count`) emit their data to stderr, so a stdout-only
            // comparison would silently drop it and disagree with the terminal.
            let termLines = CLIToolTerminalCompare.normalize(oc.combined, fixtureBasename: basename)
            var diffCount = abs(appLines.count - termLines.count)
            for (a, b) in zip(appLines, termLines) where a != b { diffCount += 1 }
            return (oc, diffCount)
        }.value
        for (url, ok) in scopedURLs where ok { url.stopAccessingSecurityScopedResource() }

        // 4. Verdict from the cheap comparison.
        let outcome = computed.0
        let differing = computed.1
        let matched = outcome.launchError == nil && outcome.exitCode == 0 && differing == 0

        let note: String
        if let err = outcome.launchError {
            note = err
        } else if outcome.exitCode != 0 {
            note = "\(tool) exited with code \(outcome.exitCode)" + (outcome.stderr.isEmpty ? "" : ": \(outcome.stderr)")
        } else if matched {
            note = "✓ Terminal output matches the app output."
        } else {
            note = "⚠ \(differing) line(s) differ between terminal and app output."
        }

        // Show exactly what a terminal shows: stdout AND stderr together. Picking
        // one stream hid `dicom-echo --count`'s `Summary:` block (it goes to stderr
        // while the progress dots go to stdout), so the panel no longer matched a
        // real terminal run.
        let terminalText = outcome.launchError ?? outcome.combined

        terminalCompareResult = CLIToolCompareResult(
            toolName: tool,
            appOutput: appOutput,
            terminalOutput: terminalText,
            binaryPath: outcome.binaryPath,
            commandLine: commandPreview,
            matched: matched,
            differingLineCount: differing,
            note: note)
        #endif
    }

    /// Best-effort fixture basename (from the first file-ish parameter) used to
    /// canonicalize absolute paths when diffing terminal vs app output.
    private func compareFixtureBasename() -> String {
        for key in ["inputPath", "input", "filePath", "file1", "file"] {
            let v = paramValue(key)
            if !v.isEmpty { return (v as NSString).lastPathComponent }
        }
        return ""
    }

    // dicom-info and dicom-dump now render through shared DICOMKit code
    // (`MetadataPresenter`, `HexDumper`/`HexDumper.tagDump`), so the previous
    // in-app renderers and value formatter were removed — one code path per tool
    // for UI and CLI.

    // MARK: - dicom-dump Execution

    /// Hex-dumps a DICOM file — output matches `dicom-dump` CLI tool exactly.
    private func executeDicomDump() async {
        let inputPath = paramValue("inputPath")
        guard !inputPath.isEmpty else {
            appendConsoleOutput("Error: Input file path is required.\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-dump", command: commandPreview, exitCode: 1, output: "Missing input path")
            return
        }

        let tagFilter    = paramValue("tag")
        let offsetStr    = paramValue("offset")
        let lengthStr    = paramValue("length")
        let bplStr       = paramValue("bytes-per-line")
        let highlightTag = paramValue("highlight")
        let annotate     = paramValue("annotate") == "true"
        let verbose      = paramValue("verbose") == "true"
        let force        = paramValue("force") == "true"
        // `--no-color` defaults off, as in dicom-dump. The dump is rendered with the
        // CLI's colour setting and the ANSI escapes are stripped for the SwiftUI
        // console, which cannot render them (the Compare-CLI diff strips both sides).
        let noColor      = paramValue("no-color") == "true"
        let bytesPerLine = Int(bplStr) ?? 16

        let inputScopedURL = securityScopedURLs["inputPath"]
        let accessing = inputScopedURL?.startAccessingSecurityScopedResource() ?? false
        defer { if accessing { inputScopedURL?.stopAccessingSecurityScopedResource() } }

        let fileURL = inputScopedURL ?? URL(fileURLWithPath: inputPath)

        let (output, exitCode) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
            do {
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    return ("Error: File not found: \(fileURL.path)\n", 1)
                }
                let fileData = try Data(contentsOf: fileURL)

                // --tag: dump only the value bytes of that tag (shared core helper,
                // identical to the dicom-dump CLI). The tag is parsed first, as the
                // CLI's dumpTag does, with the CLI's refusal text (exit 1).
                if !tagFilter.isEmpty {
                    guard let tag = Self.parseDumpTagStr(tagFilter) else {
                        return (Self.dumpInvalidTagMessage(tagFilter), 1)
                    }
                    let dicomFile = try DICOMFile.read(from: fileData, force: force)
                    // Cap to --length (default 65,536) — same as the CLI. Without
                    // this, dumping PixelData builds a multi-MB string and the
                    // SwiftUI console hangs in CoreText layout on the main thread.
                    guard let dump = HexDumper.tagDump(
                        tag: tag, in: dicomFile,
                        bytesPerLine: bytesPerLine, useColor: !noColor, verbose: verbose,
                        maxBytes: Int(lengthStr) ?? 65_536
                    ) else {
                        return ("Error: Tag \(tag.description) not found in file\n", 1)
                    }
                    return (Self.stripANSI(dump), 0)
                }

                // Parse start offset (dicom-dump parseOffset: "0x" hex or decimal; a
                // value that is neither is refused with exit 1)
                let startOffset: Int
                if offsetStr.isEmpty {
                    startOffset = 0
                } else if offsetStr.lowercased().hasPrefix("0x") {
                    guard let v = Int(offsetStr.dropFirst(2), radix: 16) else {
                        return ("Error: Invalid hex offset: \(offsetStr)\n", 1)
                    }
                    startOffset = v
                } else {
                    guard let v = Int(offsetStr) else {
                        return ("Error: Invalid offset: \(offsetStr)\n", 1)
                    }
                    startOffset = v
                }
                if let hl = Optional(highlightTag), !hl.isEmpty, Self.parseDumpTagStr(hl) == nil {
                    return (Self.dumpInvalidTagMessage(hl), 1)
                }

                guard startOffset >= 0, startOffset <= fileData.count else {
                    return ("Error: Offset \(startOffset) is out of range (file is \(fileData.count) bytes).\n", 1)
                }
                // When no explicit --length is given, cap the dump so a whole
                // (possibly large) file doesn't build a huge string and freeze
                // the UI. Pass --length to dump more.
                let defaultDumpCap = 65_536
                let lengthGiven = Int(lengthStr) != nil
                let requestedLength = Int(lengthStr) ?? min(defaultDumpCap, fileData.count - startOffset)
                let endOffset = min(startOffset + requestedLength, max(startOffset, fileData.count))

                // The CLI parses the whole file for annotations (and warns on stderr
                // with --verbose when it cannot); the dump itself proceeds either way.
                var dumpOut = ""
                var dicomFile: DICOMFile?
                do {
                    dicomFile = try DICOMFile.read(from: fileData, force: force)
                } catch {
                    if verbose {
                        dumpOut += "Warning: Could not parse DICOM structure: \(error.localizedDescription)\n"
                        dumpOut += "Dumping raw bytes without annotations\n\n"
                    }
                }
                let highlightTagObj: Tag? = highlightTag.isEmpty ? nil : Self.parseDumpTagStr(highlightTag)

                // Render via the shared DICOMKit.HexDumper — the same engine and the
                // same whole-file call the `dicom-dump` CLI uses (D144: annotations and
                // the highlight are found by walking the file from its start).
                dumpOut += HexDumper(
                    bytesPerLine: bytesPerLine, useColor: !noColor,
                    annotate: annotate, verbose: verbose
                ).dump(
                    fileData: fileData, startOffset: startOffset,
                    length: endOffset - startOffset,
                    dicomFile: dicomFile, highlightTag: highlightTagObj
                )
                if !lengthGiven && endOffset < fileData.count {
                    dumpOut += "\n… showing first \(endOffset - startOffset) of \(fileData.count) bytes — pass --length to dump more.\n"
                }
                return (Self.stripANSI(dumpOut) + "\n", 0)   // the CLI's print(output) adds the newline
            } catch {
                return ("Error: \(error.localizedDescription)\n", 1)
            }
        }.value

        appendConsoleOutput(output)
        addToHistory(toolName: "dicom-dump", command: commandPreview, exitCode: exitCode, output: output)
        consoleStatus = exitCode == 0 ? .success : .error
        service.setConsoleStatus(exitCode == 0 ? .success : .error)
    }

    /// Parses `0010,0010`, `(0010,0010)`, `00100010`, or a PS3.6 keyword (exact case) —
    /// the forms `dicom-dump`'s `parseTagArgument` accepts (PS3.5 7.1.1; PS3.6 Table 6-1).
    nonisolated static func parseDumpTagStr(_ s: String) -> Tag? {
        let clean = s.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespaces)
        if clean.count == 8, clean.allSatisfy(\.isHexDigit), let v = UInt32(clean, radix: 16) {
            return Tag(group: UInt16((v >> 16) & 0xFFFF), element: UInt16(v & 0xFFFF))
        }
        return DataElementDictionary.lookup(keyword: s.trimmingCharacters(in: .whitespaces))?.tag
    }

    /// `dicom-dump`'s refusal for a tag argument it cannot parse (exit 1).
    nonisolated static func dumpInvalidTagMessage(_ s: String) -> String {
        "Error: Invalid tag format: \(s). Use format: 0010,0010 or a PS3.6 keyword such as PatientName\n"
    }

    /// Removes ANSI SGR / CSI escape sequences: the SwiftUI console is not a terminal.
    nonisolated static func stripANSI(_ text: String) -> String {
        guard text.contains("\u{1B}") else { return text }
        return text.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
    }

    // dicom-dump now renders through the shared `DICOMKit.HexDumper` (see
    // executeDicomDump), so the previous in-app hexDump/buildHexAnnotations
    // reimplementations were removed — there is one dump engine for UI and CLI.

    // MARK: - dicom-tags Execution

    /// Adds, modifies, or deletes tags in a DICOM file — output matches `dicom-tags` CLI tool.
    private func executeDicomTags() async {
        // --list-modalities: the PS3.3 C.7.3.1.1.1 Defined Terms from the shared
        // DICOMCore listing (the same call dicom-tags prints), then exit 0; no input.
        if paramValue("list-modalities") == "true" {
            let listing = ModalityOptionValidator.listing() + "\n"
            appendConsoleOutput(listing)
            consoleStatus = .success; service.setConsoleStatus(.success)
            addToHistory(toolName: "dicom-tags", command: commandPreview, exitCode: 0, output: listing)
            return
        }
        let inputPath = paramValue("inputPath")
        guard !inputPath.isEmpty else {
            // ArgumentParser's message for the missing positional (exit 64).
            appendConsoleOutput("Error: Missing expected argument '<input>'\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-tags", command: commandPreview, exitCode: 64, output: "Missing input path")
            return
        }

        let outputPath     = paramValue("output")
        let setRaw         = paramValue("set")
        let deleteRaw      = paramValue("delete")
        let deletePrivate  = paramValue("delete-private") == "true"
        let copyFromPath   = paramValue("copy-from")
        let tagsRaw        = paramValue("tags")
        let verbose        = paramValue("verbose") == "true"
        let dryRun         = paramValue("dry-run") == "true"

        // --set / --delete are repeatable array options in the CLI; split
        // hex-tag aware so `0008,0090=...` survives and the values match the
        // repeated flags emitted in the command preview.
        let sets    = CommandBuilderHelpers.splitMultiValue(setRaw)
        let deletes = CommandBuilderHelpers.splitMultiValue(deleteRaw)
        // --tags (copy) is a single option the CLI itself comma-splits, so plain
        // comma splitting matches the CLI exactly here.
        let copyTags = tagsRaw.isEmpty ? [String]() : tagsRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        guard !sets.isEmpty || !deletes.isEmpty || deletePrivate || !copyFromPath.isEmpty else {
            // The CLI throws the shared TagEditorError (exit 1): same text.
            appendConsoleOutput("Error: \(TagEditorError.noOperationsSpecified.localizedDescription)\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-tags", command: commandPreview, exitCode: 1, output: "No operations")
            return
        }

        // Sandbox access for input, output, copy-from
        let inputScopedURL    = securityScopedURLs["inputPath"]
        let outputScopedURL   = securityScopedURLs["output"]
        let copyFromScopedURL = securityScopedURLs["copy-from"]
        let accessIn  = inputScopedURL?.startAccessingSecurityScopedResource()    ?? false
        let accessOut = outputScopedURL?.startAccessingSecurityScopedResource()   ?? false
        let accessCF  = copyFromScopedURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if accessIn  { inputScopedURL?.stopAccessingSecurityScopedResource() }
            if accessOut { outputScopedURL?.stopAccessingSecurityScopedResource() }
            if accessCF  { copyFromScopedURL?.stopAccessingSecurityScopedResource() }
        }

        let fileURL      = inputScopedURL ?? URL(fileURLWithPath: inputPath)
        let copyFromURL  = copyFromPath.isEmpty ? nil : (copyFromScopedURL ?? URL(fileURLWithPath: copyFromPath))

        // Resolve writable output path
        let (resolvedOutputPath, redirectNote) = SecurityViewModel.resolveWritableOutput(
            path: outputScopedURL?.path ?? outputPath,
            scopedURL: outputScopedURL
        )
        if let note = redirectNote { appendConsoleOutput(note) }

        let (output, exitCode) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
            do {
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    return ("Error: \(TagEditorError.fileNotFound(fileURL.path).localizedDescription)\n", 1)
                }
                if let cfURL = copyFromURL, !FileManager.default.fileExists(atPath: cfURL.path) {
                    return ("Error: \(TagEditorError.fileNotFound(cfURL.path).localizedDescription)\n", 1)
                }
                let fileData = try Data(contentsOf: fileURL)
                let dicomFile = try DICOMFile.read(from: fileData)
                var dataSet = dicomFile.dataSet

                // Load copy-from file if requested
                var sourceDataSet: DataSet?
                if let cfURL = copyFromURL {
                    let cfData = try Data(contentsOf: cfURL)
                    let cfFile = try DICOMFile.read(from: cfData)
                    sourceDataSet = cfFile.dataSet
                }

                // Apply all operations via the shared DICOMKit engine — the exact
                // same checked TagEditor call the `dicom-tags` CLI makes: it refuses
                // (throws, before anything changes) an edit the standard does not
                // allow — group 0002 (PS3.10 7.1), Items/delimiters, unused groups
                // (PS3.5 7.8.1) or a --set value outside the PS3.5 Table 6.2-1 limits
                // of the VR it writes (TagEditRules, D150) — and the Workshop exits 1
                // with the same text.
                let descriptions = try TagEditor().applyCheckedChanges(
                    to: &dataSet,
                    sets: sets,
                    deletes: deletes,
                    deletePrivate: deletePrivate,
                    sourceDataSet: sourceDataSet,
                    copyTags: copyTags,
                    verbose: verbose,
                    dryRun: dryRun
                )

                // Console text via the SHARED TagEditConsole (DICOMKit) — the exact
                // builders dicom-tags uses: the change block is gated on
                // --verbose/--dry-run, and the completion line reads
                // "Output written to:" (the CLI never prints an unconditional
                // count line or "Saved:").
                var out = TagEditConsole.changesBlock(descriptions, verbose: verbose, dryRun: dryRun)

                // When --output is a directory, write <dir>/<inputName> instead
                // of failing ("… couldn't be saved in the folder"). Resolved by
                // the shared core helper, so the CLI lands on the same path.
                let destPath = OutputPathResolver.resolveFileOutput(
                    output: resolvedOutputPath, input: fileURL.path)
                if !dryRun {
                    let modifiedFile = DICOMFile(fileMetaInformation: dicomFile.fileMetaInformation, dataSet: dataSet)
                    let outData = try modifiedFile.write()
                    let destURL  = URL(fileURLWithPath: destPath)
                    try FileManager.default.createDirectory(
                        at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try outData.write(to: destURL)
                }
                out += TagEditConsole.completionLine(dryRun: dryRun, outputPath: destPath)

                return (out, 0)
            } catch {
                return ("Error: \(error.localizedDescription)\n", 1)
            }
        }.value

        appendConsoleOutput(output)
        addToHistory(toolName: "dicom-tags", command: commandPreview, exitCode: exitCode, output: output)
        consoleStatus = exitCode == 0 ? .success : .error
        service.setConsoleStatus(exitCode == 0 ? .success : .error)
    }

    nonisolated private static func tagsParseSpecifier(_ spec: String) -> Tag? {
        let t = spec.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
        if t.contains(",") {
            let parts = t.split(separator: ",")
            if parts.count == 2,
               let g = UInt16(parts[0].trimmingCharacters(in: .whitespaces), radix: 16),
               let e = UInt16(parts[1].trimmingCharacters(in: .whitespaces), radix: 16) {
                return Tag(group: g, element: e)
            }
        } else if t.count == 8, t.allSatisfy({ $0.isHexDigit }), let v = UInt32(t, radix: 16) {
            return Tag(group: UInt16((v >> 16) & 0xFFFF), element: UInt16(v & 0xFFFF))
        }
        // Try tag name lookup via DICOMDictionary
        return DataElementDictionary.lookup(keyword: t)?.tag
    }

    // MARK: - dicom-diff Execution

    /// Compares two DICOM files — output matches `dicom-diff` CLI tool exactly.
    private func executeDicomDiff() async {
        let file1Path = paramValue("file1")
        let file2Path = paramValue("file2")
        guard !file1Path.isEmpty else {
            appendConsoleOutput("Error: File 1 path is required.\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-diff", command: commandPreview, exitCode: 1, output: "Missing file1")
            return
        }
        guard !file2Path.isEmpty else {
            appendConsoleOutput("Error: File 2 path is required.\n")
            consoleStatus = .error; service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-diff", command: commandPreview, exitCode: 1, output: "Missing file2")
            return
        }

        let format         = paramValue("format").isEmpty ? "text" : paramValue("format")
        let ignoreTagsRaw  = paramValue("ignore-tag")
        let ignorePrivate  = paramValue("ignore-private") == "true"
        let comparePixels  = paramValue("compare-pixels") == "true"
        let toleranceStr   = paramValue("tolerance")
        let quick          = paramValue("quick") == "true"
        let showIdentical  = paramValue("show-identical") == "true"
        let verbose        = paramValue("verbose") == "true"

        let tolerance = Double(toleranceStr) ?? 0.0
        let ignoreTags = CommandBuilderHelpers.splitMultiValue(ignoreTagsRaw)

        let file1ScopedURL = securityScopedURLs["file1"]
        let file2ScopedURL = securityScopedURLs["file2"]
        let access1 = file1ScopedURL?.startAccessingSecurityScopedResource() ?? false
        let access2 = file2ScopedURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if access1 { file1ScopedURL?.stopAccessingSecurityScopedResource() }
            if access2 { file2ScopedURL?.stopAccessingSecurityScopedResource() }
        }

        let url1 = file1ScopedURL ?? URL(fileURLWithPath: file1Path)
        let url2 = file2ScopedURL ?? URL(fileURLWithPath: file2Path)

        let (output, exitCode) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
            // Exit status as dicom-diff (P-DIFF-1, the diff(1)/cmp(1) convention):
            // 0 identical, 1 different, 2 a file is missing or cannot be read as
            // DICOM or the comparison fails (stderr "dicom-diff: error: …"), 64 an
            // invalid --ignore-tag (ArgumentParser usage error).
            // (file, nil) or (nil, the dicom-diff stderr text)
            func load(_ url: URL) -> (DICOMFile?, String?) {
                guard FileManager.default.fileExists(atPath: url.path) else {
                    return (nil, "File not found: \(url.path)")
                }
                do {
                    return (try DICOMFile.read(from: try Data(contentsOf: url)), nil)
                } catch {
                    return (nil, "Cannot read \(url.path) as DICOM: \(error)")
                }
            }
            func trouble(_ message: String) -> (String, Int) { ("dicom-diff: error: \(message)\n", 2) }

            let (loaded1, problem1) = load(url1)
            guard let df1 = loaded1 else { return trouble(problem1 ?? "") }
            let (loaded2, problem2) = load(url2)
            guard let df2 = loaded2 else { return trouble(problem2 ?? "") }

            var header = ""
            if verbose {
                header = "Comparing: \(url1.lastPathComponent)\n     with: \(url2.lastPathComponent)\n\n"
            }

            // Resolve each ignore-tag as the CLI's parseTag does: (gggg,eeee),
            // gggg,eeee, ggggeeee or a PS3.6 keyword; anything else is a usage error.
            var ignoreTagSet = Set<Tag>()
            for spec in ignoreTags {
                guard let tag = Self.tagsParseSpecifier(spec) else {
                    return (header + "Error: Invalid tag format: \(spec). Use (gggg,eeee), gggg,eeee, ggggeeee or a PS3.6 keyword like 'SOPInstanceUID'\n", 64)
                }
                ignoreTagSet.insert(tag)
            }

            // Compare + render via the shared DICOMKit engine — the exact same
            // code the `dicom-diff` CLI uses, so app and CLI cannot drift.
            let comparer = DICOMComparer(
                file1: df1, file2: df2,
                tagsToIgnore: ignoreTagSet, ignorePrivate: ignorePrivate,
                comparePixels: comparePixels && !quick,
                pixelTolerance: tolerance, showIdentical: showIdentical
            )
            let result: DICOMKit.ComparisonResult
            do {
                result = try comparer.compare()
            } catch {
                return (header + "dicom-diff: error: Comparison failed: \(error)\n", 2)
            }
            let report = ComparisonReport(
                result: result,
                file1Name: url1.lastPathComponent, file2Name: url2.lastPathComponent,
                showIdentical: showIdentical
            )
            let outputFormat = ComparisonOutputFormat(rawValue: format) ?? .text
            do {
                // The CLI's print(output) ends with a newline.
                let rendered = try report.render(format: outputFormat) + "\n"
                return (header + rendered, result.hasDifferences ? 1 : 0)
            } catch {
                return (header + "Error: \(error.localizedDescription)\n", 1)
            }
        }.value

        appendConsoleOutput(output)
        addToHistory(toolName: "dicom-diff", command: commandPreview, exitCode: exitCode, output: output)
        consoleStatus = exitCode == 0 ? .success : .error
        service.setConsoleStatus(exitCode == 0 ? .success : .error)
    }

    /// Performs a real C-ECHO against the server configured in the parameter
    /// fields. Honors `--count`, `--stats`, `--verbose` and `--diagnose` so the
    /// in-app tool mirrors the dicom-echo CLI (relied on by the CLI Parity
    /// screen's network mode and by the command presets that pass these flags).
    private func executeDicomEcho() async {
        let hostValue = paramValue("host")
        let portValue = paramValue("port")
        let callingAET = paramValue("aet").isEmpty ? "DICOMSTUDIO" : paramValue("aet")
        let calledAET = paramValue("called-aet").isEmpty ? "ANY-SCP" : paramValue("called-aet")
        let timeoutStr = paramValue("timeout")
        let count = max(1, Int(paramValue("count")) ?? 1)
        let showStats = paramValue("stats") == "true"
        let diagnose = paramValue("diagnose") == "true"
        let verbose = paramValue("verbose") == "true"

        guard let server = resolveHostPort(hostValue, explicitPort: portValue.isEmpty ? nil : portValue) else {
            appendConsoleOutput("Error: A valid host is required (e.g. hostname or 192.168.1.1).\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-echo", command: commandPreview, exitCode: 1, output: "Invalid host")
            return
        }

        let host = server.host
        let port = server.port
        let timeout = TimeInterval(timeoutStr) ?? 30

        // Verbose header via the SHARED NetworkConsole formatter (DICOMNetwork) — byte-
        // identical to the dicom-echo CLI. Gated on --verbose, matching the CLI and the
        // rest of the network tools; without it the output is just the echo results.
        if verbose {
            appendConsoleOutput(NetworkConsole.echoHeader(
                host: host, port: port,
                callingAE: callingAET, calledAE: calledAET,
                timeout: Int(timeout), count: count))
        }

        if diagnose {
            await runEchoDiagnostics(host: host, port: port,
                                     callingAET: callingAET, calledAET: calledAET, timeout: timeout)
            return
        }

        var results: [VerificationResult] = []
        var successCount = 0
        var failureCount = 0

        for i in 1...count {
            if verbose && count > 1 { appendConsoleOutput(NetworkConsole.echoProgress(index: i, total: count)) }
            do {
                let result = try await DICOMVerificationService.echo(
                    host: host, port: port,
                    callingAE: callingAET, calledAE: calledAET, timeout: timeout)
                results.append(result)
                if result.success {
                    successCount += 1
                    // Per-echo detail only for a single echo or in verbose mode —
                    // matches the CLI's gating so multi-echo runs compare equal.
                    if verbose || count == 1 {
                        appendConsoleOutput(NetworkConsole.echoSuccess(
                            remoteAE: result.remoteAETitle, status: result.status, rtt: result.roundTripTime))
                    } else {
                        appendConsoleOutput(NetworkConsole.echoProgressDot())   // progress dot per echo, mirrors the CLI
                    }
                } else {
                    failureCount += 1
                    appendConsoleOutput(NetworkConsole.echoStatusFailure(status: result.status))
                }
            } catch let netErr as DICOMNetworkError {
                failureCount += 1
                appendConsoleOutput(NetworkConsole.echoFailureDetail(
                    netErr, host: host, port: port,
                    callingAE: callingAET, calledAE: calledAET, timeout: Int(timeout)))
            } catch {
                failureCount += 1
                appendConsoleOutput(NetworkConsole.echoError(error.localizedDescription))
            }
            if i < count { try? await Task.sleep(nanoseconds: 100_000_000) }   // 100ms between requests
        }

        if count > 1 && !verbose { appendConsoleOutput(NetworkConsole.echoDotsTerminator()) }   // newline after the progress dots

        // Summary (mirrors the CLI: shown for multi-echo runs or when --stats is set),
        // all via the SHARED NetworkConsole formatter.
        if count > 1 || showStats {
            appendConsoleOutput(NetworkConsole.echoSummary(sent: count, succeeded: successCount, failed: failureCount))
            if showStats {
                let rtts = results.filter { $0.success }.map { $0.roundTripTime }
                appendConsoleOutput(NetworkConsole.echoStats(roundTripTimes: rtts))
            }
        }

        let ok = failureCount == 0
        consoleStatus = ok ? .success : .error
        service.setConsoleStatus(ok ? .success : .error)
        addToHistory(toolName: "dicom-echo", command: commandPreview, exitCode: ok ? 0 : 1,
                     output: ok ? "C-ECHO \(successCount)/\(count) successful"
                                : "C-ECHO failed (\(failureCount)/\(count))")
    }

    /// Runs the `--diagnose` flow: basic connectivity, a 5-request stability
    /// probe, and association parameters — mirroring the dicom-echo CLI so the
    /// CLI Parity screen can compare the two semantically.
    private func runEchoDiagnostics(host: String, port: UInt16,
                                    callingAET: String, calledAET: String, timeout: TimeInterval) async {
        // All diagnostics chrome flows through the SHARED NetworkConsole formatter
        // (DICOMNetwork) so the Studio panel and the dicom-echo CLI emit byte-identical
        // output (the implementation-class/version strings are read inside the formatter
        // from the same VerificationConfiguration defaults both sides use).
        appendConsoleOutput(NetworkConsole.echoDiagnoseHeader())

        // Test 1: Basic connectivity
        appendConsoleOutput(NetworkConsole.echoDiagnoseTest1Header(host: host, port: port))
        do {
            let result = try await DICOMVerificationService.echo(
                host: host, port: port, callingAE: callingAET, calledAE: calledAET, timeout: timeout)
            appendConsoleOutput(NetworkConsole.echoDiagnoseBasicResult(
                success: result.success, status: result.status, rtt: result.roundTripTime))
        } catch {
            appendConsoleOutput(NetworkConsole.echoDiagnoseBasicError(error.localizedDescription))
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-echo", command: commandPreview, exitCode: 1,
                         output: "Diagnostics: basic connectivity error")
            return
        }

        // Test 2: Connection stability (5 requests)
        appendConsoleOutput(NetworkConsole.echoDiagnoseTest2Header())
        var stableSuccessCount = 0
        var stableRTTs: [TimeInterval] = []
        for i in 1...5 {
            do {
                let result = try await DICOMVerificationService.echo(
                    host: host, port: port, callingAE: callingAET, calledAE: calledAET, timeout: timeout)
                if result.success {
                    stableSuccessCount += 1
                    stableRTTs.append(result.roundTripTime)
                    appendConsoleOutput(NetworkConsole.echoDiagnoseStabilitySuccess(index: i, total: 5, rtt: result.roundTripTime))
                } else {
                    appendConsoleOutput(NetworkConsole.echoDiagnoseStabilityFailure(index: i, total: 5, status: result.status))
                }
            } catch {
                appendConsoleOutput(NetworkConsole.echoDiagnoseStabilityError(index: i, total: 5, message: error.localizedDescription))
            }
            if i < 5 { try? await Task.sleep(nanoseconds: 100_000_000) }
        }
        appendConsoleOutput(NetworkConsole.echoDiagnoseStabilitySummary(
            successes: stableSuccessCount, total: 5, roundTripTimes: stableRTTs))

        // Test 3: Association parameters
        appendConsoleOutput(NetworkConsole.echoDiagnoseAssociationParams())

        // Verdict
        appendConsoleOutput(NetworkConsole.echoDiagnoseResult(stabilitySuccesses: stableSuccessCount))
        let ok = stableSuccessCount == 5
        consoleStatus = ok ? .success : .error
        service.setConsoleStatus(ok ? .success : .error)
        addToHistory(toolName: "dicom-echo", command: commandPreview, exitCode: ok ? 0 : 1,
                     output: "Diagnostics: \(stableSuccessCount)/5 stable")
    }

    /// Returns the current string value for a parameter by ID.
    private func paramValue(_ paramID: String) -> String {
        parameterValues.first(where: { $0.parameterID == paramID })?.stringValue ?? ""
    }

    // MARK: - DICOMweb Tool Execution

    /// Creates a `DICOMwebServerProfile` from the current parameter values.
    private func dicomwebProfileFromParams() -> DICOMwebServerProfile? {
        let url = paramValue("url")
        guard !url.isEmpty else { return nil }
        let authStr = paramValue("auth")
        let authMethod: DICOMwebAuthMethod
        switch authStr {
        case "basic": authMethod = .basic
        case "bearer": authMethod = .bearer
        default: authMethod = .none
        }
        return DICOMwebServerProfile(
            name: "CLI",
            baseURL: url,
            authMethod: authMethod,
            bearerToken: paramValue("token"),
            username: paramValue("username"),
            // #45: basic-auth passwords live in the internal `password` field —
            // `token` is Bearer-only (matching the CLI's --token semantics).
            password: paramValue("password")
        )
    }

    /// Executes a QIDO-RS query against a DICOMweb server.
    private func executeDicomQIDO() async {
        guard let profile = dicomwebProfileFromParams() else {
            appendConsoleOutput("Error: Base URL is required.\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-qido", command: commandPreview, exitCode: 1, output: "Base URL is required")
            return
        }

        let levelStr = paramValue("level").uppercased()
        let limit = Int(paramValue("limit")) ?? 100
        let offset = Int(paramValue("offset")) ?? 0
        // The in-app query faithfully reproduces the `dicom-wado query` CLI (the
        // Workshop's purpose), so it emits ONLY the formatted result the CLI prints —
        // no app-only "Querying…/returned N" chrome that the non-verbose CLI omits and
        // that would otherwise shift every line out of alignment in the Compare-CLI diff.
        let fmt = QIDOOutputFormat(rawValue: paramValue("output-format").lowercased()) ?? .table
        // --verbose mirrors the CLI's stderr chrome: a header before the query and
        // a "Found N …" line after the results.
        let verbose = paramValue("verbose") == "true"
        if verbose {
            appendConsoleOutput("DICOMweb Server: \(paramValue("base-url"))\n")
            appendConsoleOutput("Query Level: \(levelStr.lowercased())\n")
            appendConsoleOutput("Limit: \(limit), Offset: \(offset)\n")
        }

        do {
            let client = try DICOMwebClientFactory.makeClient(from: profile)

            var query = QIDOQuery().limit(limit).offset(offset).includeAllFields()
            let patientName = paramValue("patient-name")
            let patientID = paramValue("patient-id")
            let studyDate = paramValue("study-date")
            let modality = paramValue("modality")
            let studyUID = paramValue("study-uid")
            let seriesUID = paramValue("series-uid")
            let accession = paramValue("accession")
            let studyDesc = paramValue("study-description")

            // Pass patient name as-is (matches CLI behavior)
            if !patientName.isEmpty {
                query = query.patientName(patientName)
            }
            if !patientID.isEmpty { query = query.patientID(patientID) }
            if !studyDate.isEmpty { query = query.studyDate(studyDate) }
            if !modality.isEmpty {
                // Use the correct DICOM tag per query level:
                // Study level: Modalities in Study (0008,0061)
                // Series level: Modality (0008,0060)
                if levelStr == "SERIES" {
                    query = query.modality(modality)
                } else {
                    query = query.modalitiesInStudy(modality)
                }
            }
            if !studyUID.isEmpty { query = query.studyInstanceUID(studyUID) }
            if !seriesUID.isEmpty { query = query.seriesInstanceUID(seriesUID) }
            if !accession.isEmpty { query = query.accessionNumber(accession) }
            if !studyDesc.isEmpty { query = query.studyDescription(studyDesc) }

            // Series-level matching keys (PS3.18 Table 10.6.1-5). The parameter
            // definitions hide these outside the series level, so no misplaced-key
            // warning is reachable here — unlike the CLI, where the flags can be
            // typed at any level.
            let ppsStartDate = paramValue("pps-start-date")
            let ppsStartTime = paramValue("pps-start-time")
            let qidoSPSID = paramValue("qido-sps-id")
            let qidoRequestedProcedureID = paramValue("qido-requested-procedure-id")
            if !ppsStartDate.isEmpty { query = query.performedProcedureStepStartDate(ppsStartDate) }
            if !ppsStartTime.isEmpty { query = query.performedProcedureStepStartTime(ppsStartTime) }
            if !qidoSPSID.isEmpty { query = query.scheduledProcedureStepID(qidoSPSID) }
            if !qidoRequestedProcedureID.isEmpty {
                query = query.requestedProcedureID(qidoRequestedProcedureID)
            }

            // Dispatch mirrors the CLI run(): when the scoping UIDs are present the
            // query is path-scoped (GET /studies/{uid}/series, /studies/{uid}/series/{uid}/instances,
            // /studies/{uid}/instances); the root all-series/all-instances resources are
            // optional in PS3.18 and only used when the query is unscoped.
            switch levelStr {
            case "SERIES":
                let results: QIDOSeriesResults
                if !studyUID.isEmpty {
                    results = try await client.searchSeries(studyUID: studyUID, query: query)
                } else {
                    results = try await client.searchAllSeries(query: query)
                }
                appendConsoleOutput(QIDOResultFormatter().formatSeries(results.results, format: fmt))
                if verbose { appendConsoleOutput("\nFound \(results.results.count) series\n") }
                consoleStatus = .success
                service.setConsoleStatus(.success)
                addToHistory(toolName: "dicom-qido", command: commandPreview, exitCode: 0,
                             output: "\(results.results.count) series returned")

            case "INSTANCE":
                let results: QIDOInstanceResults
                if !studyUID.isEmpty, !seriesUID.isEmpty {
                    results = try await client.searchInstances(studyUID: studyUID, seriesUID: seriesUID, query: query)
                } else if !studyUID.isEmpty {
                    results = try await client.searchInstances(studyUID: studyUID, query: query)
                } else {
                    results = try await client.searchAllInstances(query: query)
                }
                appendConsoleOutput(QIDOResultFormatter().formatInstances(results.results, format: fmt))
                if verbose { appendConsoleOutput("\nFound \(results.results.count) instance(s)\n") }
                consoleStatus = .success
                service.setConsoleStatus(.success)
                addToHistory(toolName: "dicom-qido", command: commandPreview, exitCode: 0,
                             output: "\(results.results.count) instances returned")

            default: // STUDY
                let results = try await client.searchStudies(query: query)
                let total = results.totalCount.map { " (total: \($0))" } ?? ""
                appendConsoleOutput(QIDOResultFormatter().formatStudies(results.results, format: fmt))
                if verbose { appendConsoleOutput("\nFound \(results.results.count) study(ies)\n") }
                consoleStatus = .success
                service.setConsoleStatus(.success)
                addToHistory(toolName: "dicom-qido", command: commandPreview, exitCode: 0,
                             output: "\(results.results.count) studies returned\(total)")
            }
        } catch {
            appendConsoleOutput("❌ QIDO-RS query failed\n")
            appendConsoleOutput("  Error: \(error.localizedDescription)\n")
            appendConsoleOutput("\n  💡 Hint: Verify the Base URL is correct and the DICOMweb server is reachable.\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-qido", command: commandPreview, exitCode: 1,
                         output: error.localizedDescription)
        }
    }

    /// Executes a WADO retrieve (WADO-RS or WADO-URI) against a DICOMweb server.
    private func executeDicomWADO() async {
        let protocol_ = paramValue("wado-protocol")
        if protocol_ == "wado-uri" {
            await executeDicomWADOURI()
            return
        }

        // Default: WADO-RS path
        guard let profile = dicomwebProfileFromParams() else {
            appendConsoleOutput("Error: Base URL is required.\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-wado", command: commandPreview, exitCode: 1, output: "Base URL is required")
            return
        }

        let studyUID = paramValue("study-uid")
        let seriesUID = paramValue("series-uid")
        let instanceUID = paramValue("instance-uid")
        let metadataFlag = paramValue("metadata") == "true"
        let renderedFlag = paramValue("rendered") == "true"
        let thumbnailFlag = paramValue("thumbnail") == "true"
        let framesStr = paramValue("frames")
        let verbose = paramValue("verbose") == "true"
        // --format is the METADATA format (json|xml), matching the CLI; it no longer
        // doubles as a rendered image-format selector (rendered is JPEG, like the CLI).
        let metadataFormat = paramValue("format").lowercased() == "xml" ? "xml" : "json"

        guard !studyUID.isEmpty else {
            appendConsoleOutput("Error: Study Instance UID is required.\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-wado", command: commandPreview, exitCode: 1, output: "Study UID is required")
            return
        }

        let outputDir = resolvedOutputDir(paramValue("output"))
        let hierarchical = false

        // Track retrieved files for viewer integration
        lastRetrievedFiles.removeAll()
        lastRetrievedOutputURL = securityScopedURLs["output"]

        do {
            let client = try DICOMwebClientFactory.makeClient(from: profile)

            // Console rendering is delegated to the SHARED WADORetrieveConsoleFormatter
            // (DICOMWeb) — the same renderer the `dicom-wado retrieve` CLI uses — so the
            // app and CLI retrieve output pipelines cannot drift. The verbose preamble,
            // status lines and metadata body all come from the formatter. The per-instance
            // dataset previews below are an explicit app-only convenience (WADO parity is
            // on the matched outcome, not console text, so the extra preview is harmless).
            let fmt = WADORetrieveConsoleFormatter()
            if verbose {
                appendConsoleOutput(fmt.verbosePreambleRS(
                    baseURL: profile.baseURL, studyUID: studyUID,
                    seriesUID: seriesUID.isEmpty ? nil : seriesUID,
                    instanceUID: instanceUID.isEmpty ? nil : instanceUID) + "\n")
                appendConsoleOutput("\n")
            }

            // Dispatch mirrors the CLI run(): metadata > rendered > thumbnail > frames > instances.
            if metadataFlag {
                if verbose { appendConsoleOutput(fmt.metadataRetrieving() + "\n") }
                if metadataFormat == "json" {
                    let metadata: [[String: Any]]
                    if !instanceUID.isEmpty, !seriesUID.isEmpty {
                        metadata = try await client.retrieveInstanceMetadata(
                            studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID)
                    } else if !seriesUID.isEmpty {
                        metadata = try await client.retrieveSeriesMetadata(studyUID: studyUID, seriesUID: seriesUID)
                    } else {
                        metadata = try await client.retrieveStudyMetadata(studyUID: studyUID)
                    }
                    appendConsoleOutput(try fmt.metadataJSON(metadata) + "\n")
                    if verbose { appendConsoleOutput(fmt.metadataCount(metadata.count) + "\n") }
                    consoleStatus = .success
                    service.setConsoleStatus(.success)
                    addToHistory(toolName: "dicom-wado", command: commandPreview, exitCode: 0,
                                 output: "metadata: \(metadata.count) instance(s)")
                } else {
                    let instances: [[DataElement]]
                    if !instanceUID.isEmpty, !seriesUID.isEmpty {
                        instances = [try await client.retrieveInstanceMetadataAsElements(
                            studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID)]
                    } else if !seriesUID.isEmpty {
                        instances = try await client.retrieveSeriesMetadataAsElements(
                            studyUID: studyUID, seriesUID: seriesUID)
                    } else {
                        instances = try await client.retrieveStudyMetadataAsElements(studyUID: studyUID)
                    }
                    appendConsoleOutput(try fmt.metadataXML(instances) + "\n")
                    if verbose { appendConsoleOutput(fmt.metadataCount(instances.count) + "\n") }
                    consoleStatus = .success
                    service.setConsoleStatus(.success)
                    addToHistory(toolName: "dicom-wado", command: commandPreview, exitCode: 0,
                                 output: "metadata: \(instances.count) instance(s)")
                }

            } else if renderedFlag {
                // Mirror the CLI: rendered requires series+instance and is JPEG-only
                // (no --format image selection, no rendered-frames path).
                guard !seriesUID.isEmpty, !instanceUID.isEmpty else {
                    appendConsoleOutput("Error: Series UID and Instance UID are required for rendered retrieval.\n")
                    consoleStatus = .error
                    service.setConsoleStatus(.error)
                    addToHistory(toolName: "dicom-wado", command: commandPreview, exitCode: 1,
                                 output: "Series and Instance UID required for rendered")
                    return
                }
                if verbose { appendConsoleOutput(fmt.renderedRetrieving() + "\n") }
                let imageData = try await client.retrieveRenderedInstance(
                    studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID)
                let savedPath = try writeOutputFile(
                    data: imageData, filename: "rendered_\(instanceUID).jpg", outputDir: outputDir)
                lastRetrievedFiles.append(savedPath)
                if verbose { appendConsoleOutput(fmt.renderedSaved(bytes: imageData.count) + "\n") }
                consoleStatus = .success
                service.setConsoleStatus(.success)
                addToHistory(toolName: "dicom-wado", command: commandPreview, exitCode: 0,
                             output: "rendered, \(imageData.count) bytes → \(savedPath)")

            } else if thumbnailFlag {
                if verbose { appendConsoleOutput(fmt.thumbnailRetrieving() + "\n") }
                let thumbnailData: Data
                let filename: String
                if !instanceUID.isEmpty, !seriesUID.isEmpty {
                    thumbnailData = try await client.retrieveInstanceThumbnail(
                        studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID)
                    filename = "thumbnail_\(instanceUID).jpg"
                } else if !seriesUID.isEmpty {
                    thumbnailData = try await client.retrieveSeriesThumbnail(studyUID: studyUID, seriesUID: seriesUID)
                    filename = "thumbnail_series_\(seriesUID).jpg"
                } else {
                    thumbnailData = try await client.retrieveStudyThumbnail(studyUID: studyUID)
                    filename = "thumbnail_study_\(studyUID).jpg"
                }
                let savedPath = try writeOutputFile(data: thumbnailData, filename: filename, outputDir: outputDir)
                lastRetrievedFiles.append(savedPath)
                if verbose { appendConsoleOutput(fmt.thumbnailSaved(bytes: thumbnailData.count) + "\n") }
                consoleStatus = .success
                service.setConsoleStatus(.success)
                addToHistory(toolName: "dicom-wado", command: commandPreview, exitCode: 0,
                             output: "thumbnail, \(thumbnailData.count) bytes → \(savedPath)")

            } else if !framesStr.isEmpty {
                // Mirror the CLI: retrieve ALL listed frames (not just the first) and save
                // each as raw pixel bytes (frame_<n>_<uid>.raw).
                guard !seriesUID.isEmpty, !instanceUID.isEmpty else {
                    appendConsoleOutput("Error: Series UID and Instance UID are required for frame retrieval.\n")
                    consoleStatus = .error
                    service.setConsoleStatus(.error)
                    addToHistory(toolName: "dicom-wado", command: commandPreview, exitCode: 1,
                                 output: "Series and Instance UID required for frames")
                    return
                }
                let frameNumbers: [Int]
                do {
                    frameNumbers = try fmt.parseFrameNumbers(framesStr)
                } catch let e as WADOFrameParseError {
                    appendConsoleOutput("Error: \(e.description)\n")
                    consoleStatus = .error
                    service.setConsoleStatus(.error)
                    addToHistory(toolName: "dicom-wado", command: commandPreview, exitCode: 1, output: e.description)
                    return
                }
                if verbose { appendConsoleOutput(fmt.framesRetrieving(frameNumbers) + "\n") }
                let frames = try await client.retrieveFrames(
                    studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID, frames: frameNumbers)
                for frame in frames {
                    let savedPath = try writeOutputFile(
                        data: frame.data, filename: "frame_\(frame.frameNumber)_\(instanceUID).raw", outputDir: outputDir)
                    lastRetrievedFiles.append(savedPath)
                    if verbose { appendConsoleOutput(fmt.frameSaved(number: frame.frameNumber, bytes: frame.data.count) + "\n") }
                }
                if verbose { appendConsoleOutput(fmt.framesCount(frames.count) + "\n") }
                consoleStatus = .success
                service.setConsoleStatus(.success)
                addToHistory(toolName: "dicom-wado", command: commandPreview, exitCode: 0,
                             output: "\(frames.count) frame(s) → \(outputDir)")

            } else if !instanceUID.isEmpty, !seriesUID.isEmpty {
                // Single instance
                if verbose { appendConsoleOutput(fmt.instancesRetrieving() + "\n") }
                let data = try await client.retrieveInstance(
                    studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID)
                try writeReceivedDICOMFile(
                    data: data, sopInstanceUID: instanceUID,
                    studyUID: studyUID, seriesUID: seriesUID, outputDir: outputDir, hierarchical: hierarchical)
                if verbose { appendConsoleOutput(fmt.instanceSaved(bytes: data.count) + "\n") }
                wadoDisplayDataset(data, index: 1)  // app-only preview
                consoleStatus = .success
                service.setConsoleStatus(.success)
                addToHistory(toolName: "dicom-wado", command: commandPreview, exitCode: 0,
                             output: "1 instance, \(data.count) bytes → \(outputDir)")

            } else if !seriesUID.isEmpty {
                // Series
                if verbose { appendConsoleOutput(fmt.instancesRetrieving() + "\n") }
                let result = try await client.retrieveSeries(studyUID: studyUID, seriesUID: seriesUID)
                for (index, instanceData) in result.instances.enumerated() {
                    let sopUID = wadoExtractSOPInstanceUID(instanceData) ?? "instance_\(index + 1)"
                    _ = try? writeReceivedDICOMFile(
                        data: instanceData, sopInstanceUID: sopUID,
                        studyUID: studyUID, seriesUID: seriesUID, outputDir: outputDir, hierarchical: hierarchical)
                    if verbose { appendConsoleOutput(fmt.instanceSaved(index: index + 1, bytes: instanceData.count) + "\n") }
                    wadoDisplayDataset(instanceData, index: index + 1)  // app-only preview
                }
                if verbose { appendConsoleOutput(fmt.instancesCount(result.instances.count) + "\n") }
                consoleStatus = .success
                service.setConsoleStatus(.success)
                addToHistory(toolName: "dicom-wado", command: commandPreview, exitCode: 0,
                             output: "\(result.instances.count) instances → \(outputDir)")

            } else {
                // Full study
                if verbose { appendConsoleOutput(fmt.instancesRetrieving() + "\n") }
                let result = try await client.retrieveStudy(studyUID: studyUID)
                for (index, instanceData) in result.instances.enumerated() {
                    let sopUID = wadoExtractSOPInstanceUID(instanceData) ?? "instance_\(index + 1)"
                    _ = try? writeReceivedDICOMFile(
                        data: instanceData, sopInstanceUID: sopUID,
                        studyUID: studyUID, outputDir: outputDir, hierarchical: hierarchical)
                    if verbose { appendConsoleOutput(fmt.instanceSaved(index: index + 1, bytes: instanceData.count) + "\n") }
                    wadoDisplayDataset(instanceData, index: index + 1)  // app-only preview
                }
                if verbose { appendConsoleOutput(fmt.instancesCount(result.instances.count) + "\n") }
                consoleStatus = .success
                service.setConsoleStatus(.success)
                addToHistory(toolName: "dicom-wado", command: commandPreview, exitCode: 0,
                             output: "\(result.instances.count) instances → \(outputDir)")
            }
        } catch {
            appendConsoleOutput("❌ WADO-RS retrieve failed\n")
            appendConsoleOutput("  Error: \(error.localizedDescription)\n")
            appendConsoleOutput("\n  💡 Hint: Verify the Study UID exists on the server and the Base URL is correct.\n")
            if renderedFlag {
                appendConsoleOutput("  💡 Hint: Not all servers support the /rendered endpoint. Try instance retrieval instead.\n")
            }
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-wado", command: commandPreview, exitCode: 1,
                         output: error.localizedDescription)
        }
    }

    /// Executes a WADO-URI retrieve against a legacy DICOMweb/WADO server.
    ///
    /// WADO-URI uses query parameters (`?requestType=WADO&studyUID=...&seriesUID=...&objectUID=...`)
    /// and retrieves a single DICOM object per request. Common for dcm4chee2 and older PACS.
    ///
    /// Reference: DICOM PS3.18 §8 — WADO by means of URI
    private func executeDicomWADOURI() async {
        guard let profile = dicomwebProfileFromParams() else {
            appendConsoleOutput("Error: Base URL is required.\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-wado", command: commandPreview, exitCode: 1, output: "Base URL is required")
            return
        }

        let studyUID = paramValue("study-uid")
        let seriesUID = paramValue("series-uid")
        let instanceUID = paramValue("instance-uid")
        let acceptType = paramValue("content-type")
        let framesStr = paramValue("frames")
        // WADO-URI supports a single frame — take the first entry, trimmed, exactly
        // like the CLI (DICOMWado retrieve --uri). `0` is preserved as a real value
        // (the server surfaces the error), not silently treated as "no frame".
        let frameNumber: Int? = framesStr.split(separator: ",").first
            .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let verbose = paramValue("verbose") == "true"

        guard !studyUID.isEmpty else {
            appendConsoleOutput("Error: Study Instance UID is required for WADO-URI.\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-wado", command: commandPreview, exitCode: 1, output: "Study UID is required")
            return
        }
        guard !seriesUID.isEmpty else {
            appendConsoleOutput("Error: Series Instance UID is required for WADO-URI.\n")
            appendConsoleOutput("  💡 WADO-URI requires Study UID, Series UID, and SOP Instance UID.\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-wado", command: commandPreview, exitCode: 1, output: "Series UID is required for WADO-URI")
            return
        }
        guard !instanceUID.isEmpty else {
            appendConsoleOutput("Error: SOP Instance UID is required for WADO-URI.\n")
            appendConsoleOutput("  💡 WADO-URI requires Study UID, Series UID, and SOP Instance UID.\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-wado", command: commandPreview, exitCode: 1, output: "SOP Instance UID is required for WADO-URI")
            return
        }

        let outputDir = resolvedOutputDir(paramValue("output"))
        let hierarchical = false

        lastRetrievedFiles.removeAll()
        lastRetrievedOutputURL = securityScopedURLs["output"]

        // Shared content-type mapping (single source of truth) — the SAME factory the
        // `dicom-wado retrieve --uri` CLI calls, so the app and CLI request the identical
        // representation for a given --content-type (incl. jp2/jph/jphc/mpeg + short
        // aliases). Previously the app hand-rolled a divergent subset switch here.
        let contentType = WADOURIClient.ContentType.fromRequestString(acceptType.isEmpty ? nil : acceptType)

        let fmt = WADORetrieveConsoleFormatter()
        if verbose {
            appendConsoleOutput(fmt.verbosePreambleURI(
                baseURL: profile.baseURL, studyUID: studyUID, seriesUID: seriesUID,
                instanceUID: instanceUID, contentType: contentType.rawValue,
                frame: frameNumber) + "\n")
            appendConsoleOutput("\n")
        }

        do {
            let client = try DICOMwebClientFactory.makeWADOURIClient(from: profile)

            let result = try await client.retrieve(
                studyUID: studyUID,
                seriesUID: seriesUID,
                objectUID: instanceUID,
                contentType: contentType,
                frameNumber: frameNumber
            )

            let data = result.data

            // Filename matches the CLI: <instanceUID>[_frameN].<ext>
            let ext: String
            switch contentType {
            case .dicom:          ext = "dcm"
            case .jpeg:           ext = "jpg"
            case .png:            ext = "png"
            case .gif:            ext = "gif"
            case .jpeg2000:       ext = "jp2"
            case .htj2k:          ext = "jph"
            case .htj2kContainer: ext = "jphc"
            case .mpeg:           ext = "mpg"
            }
            let frameSuffix = frameNumber.map { "_frame\($0)" } ?? ""
            let filename = "\(instanceUID)\(frameSuffix).\(ext)"

            let savedPath: String
            if contentType == .dicom {
                let sopUID = wadoExtractSOPInstanceUID(data) ?? instanceUID
                savedPath = try writeReceivedDICOMFile(
                    data: data, sopInstanceUID: sopUID,
                    studyUID: studyUID, seriesUID: seriesUID,
                    outputDir: outputDir, hierarchical: hierarchical
                )
            } else {
                savedPath = try writeOutputFile(data: data, filename: filename, outputDir: outputDir)
                lastRetrievedFiles.append(savedPath)
            }

            if verbose {
                appendConsoleOutput(fmt.uriRetrievedVerbose(bytes: data.count) + "\n")
                appendConsoleOutput(fmt.savedTo(path: savedPath) + "\n")
            } else {
                appendConsoleOutput(fmt.uriRetrieved(bytes: data.count, filename: filename) + "\n")
            }

            if contentType == .dicom {
                wadoDisplayDataset(data, index: 1)  // app-only preview
            }

            consoleStatus = .success
            service.setConsoleStatus(.success)
            addToHistory(toolName: "dicom-wado", command: commandPreview, exitCode: 0,
                         output: "WADO-URI: 1 object, \(data.count) bytes → \(outputDir)")
        } catch {
            appendConsoleOutput("❌ WADO-URI retrieve failed\n")
            appendConsoleOutput("  Error: \(error.localizedDescription)\n")
            appendConsoleOutput("\n  💡 Hint: Verify all three UIDs (Study, Series, SOP Instance) exist on the server.\n")
            appendConsoleOutput("  💡 Hint: Ensure the Base URL points to the WADO endpoint (e.g. http://server:8080/wado).\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-wado", command: commandPreview, exitCode: 1,
                         output: error.localizedDescription)
        }
    }

    /// Attempts to extract the SOP Instance UID from raw DICOM instance data.
    private func wadoExtractSOPInstanceUID(_ data: Data) -> String? {
        guard let file = try? DICOMFile.read(from: data, force: true) else { return nil }
        return file.sopInstanceUID
    }

    /// Displays a detailed DICOM dataset summary for a retrieved instance.
    private func wadoDisplayDataset(_ data: Data, index: Int) {
        guard let file = try? DICOMFile.read(from: data, force: true) else { return }
        let ds = file.dataSet
        appendConsoleOutput("─── Instance [\(index)] ────────────────────────────────────\n")
        appendConsoleOutput("  SOP Instance UID ..... \(file.sopInstanceUID ?? "N/A")\n")
        appendConsoleOutput("  SOP Class UID ........ \(file.sopClassUID ?? "N/A")\n")
        appendConsoleOutput("  Transfer Syntax ...... \(file.transferSyntaxUID ?? "N/A")\n")
        appendConsoleOutput("  Patient Name ......... \(ds.string(for: .patientName) ?? "N/A")\n")
        appendConsoleOutput("  Patient ID ........... \(ds.string(for: .patientID) ?? "N/A")\n")
        appendConsoleOutput("  Study Instance UID ... \(ds.string(for: .studyInstanceUID) ?? "N/A")\n")
        appendConsoleOutput("  Series Instance UID .. \(ds.string(for: .seriesInstanceUID) ?? "N/A")\n")
        appendConsoleOutput("  Modality ............. \(ds.string(for: .modality) ?? "N/A")\n")
        appendConsoleOutput("  Study Date ........... \(ds.string(for: .studyDate) ?? "N/A")\n")
        appendConsoleOutput("  Study Description .... \(ds.string(for: .studyDescription) ?? "N/A")\n")
        appendConsoleOutput("  Series Number ........ \(ds.string(for: .seriesNumber) ?? "N/A")\n")
        appendConsoleOutput("  Instance Number ...... \(ds.string(for: .instanceNumber) ?? "N/A")\n")
        appendConsoleOutput("  Rows ................. \(ds.uint16(for: .rows).map(String.init) ?? "N/A")\n")
        appendConsoleOutput("  Columns .............. \(ds.uint16(for: .columns).map(String.init) ?? "N/A")\n")
        appendConsoleOutput("  Bits Allocated ....... \(ds.uint16(for: .bitsAllocated).map(String.init) ?? "N/A")\n")
        appendConsoleOutput("  Bits Stored .......... \(ds.uint16(for: .bitsStored).map(String.init) ?? "N/A")\n")
        appendConsoleOutput("  Photometric Interp ... \(ds.string(for: .photometricInterpretation) ?? "N/A")\n")
        appendConsoleOutput("\n")
    }

    /// Executes a STOW-RS upload against a DICOMweb server.
    private func executeDicomSTOW() async {
        guard let profile = dicomwebProfileFromParams() else {
            appendConsoleOutput("Error: Base URL is required.\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-stow", command: commandPreview, exitCode: 1, output: "Base URL is required")
            return
        }

        let filesPath = paramValue("files")
        let studyUID = paramValue("study-uid").isEmpty ? nil : paramValue("study-uid")
        let batchSize = Int(paramValue("batch")) ?? 10
        // Batch size feeds `stride(by:)`, which traps on a non-positive stride.
        guard batchSize >= 1 else {
            appendConsoleOutput("Error: Batch size must be at least 1.\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-stow", command: commandPreview, exitCode: 1, output: "Invalid batch size")
            return
        }
        let continueOnError = paramValue("continue-on-error") == "true"
        let verbose = paramValue("verbose") == "true"
        let recursive = true  // Always scan directories recursively

        // Console rendering is delegated to the SHARED STOWResultFormatter (DICOMWeb) —
        // the same renderer the `dicom-wado store` CLI uses — so the app and CLI store
        // output pipelines cannot drift.
        let stowFmt = STOWResultFormatter()

        // ── Collect DICOM file paths ────────────────────────────────
        // Merge drag-and-drop entries with the text-field path, resolve
        // directories into individual .dcm files, and obtain
        // security-scoped access for sandboxed reads.

        var resolvedFiles: [(path: String, url: URL)] = []

        // Start security-scoped access if we have one for "files"
        let scopedURL = securityScopedURLs["files"]
        let accessing = scopedURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if accessing { scopedURL?.stopAccessingSecurityScopedResource() }
        }

        // Helper: collect DICOM files from a single path (file or directory)
        func collectDICOMFiles(from basePath: String) {
            let fm = FileManager.default
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: basePath, isDirectory: &isDir) else { return }

            if isDir.boolValue {
                // Directory — enumerate contents
                let enumerator: FileManager.DirectoryEnumerator?
                if recursive {
                    enumerator = fm.enumerator(atPath: basePath)
                } else {
                    // Non-recursive: just immediate children via shallow enumeration
                    enumerator = fm.enumerator(at: URL(fileURLWithPath: basePath),
                                               includingPropertiesForKeys: [.isRegularFileKey],
                                               options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles])
                        .map { ShallowEnumeratorWrapper($0) }
                }
                if let enumerator = enumerator {
                    if recursive {
                        // String-based enumerator
                        while let relativePath = enumerator.nextObject() as? String {
                            let fullPath = (basePath as NSString).appendingPathComponent(relativePath)
                            if isDICOMCandidate(fullPath) {
                                resolvedFiles.append((path: fullPath, url: URL(fileURLWithPath: fullPath)))
                            }
                        }
                    }
                } else {
                    // Fallback: try shallow contents
                    if let contents = try? fm.contentsOfDirectory(atPath: basePath) {
                        for name in contents where !name.hasPrefix(".") {
                            let fullPath = (basePath as NSString).appendingPathComponent(name)
                            if isDICOMCandidate(fullPath) {
                                resolvedFiles.append((path: fullPath, url: URL(fileURLWithPath: fullPath)))
                            }
                        }
                    }
                }
                // For non-recursive URL enumerator, handled via contentsOfDirectory fallback above
                if !recursive {
                    if let contents = try? fm.contentsOfDirectory(atPath: basePath) {
                        for name in contents where !name.hasPrefix(".") {
                            let fullPath = (basePath as NSString).appendingPathComponent(name)
                            if isDICOMCandidate(fullPath),
                               !resolvedFiles.contains(where: { $0.path == fullPath }) {
                                resolvedFiles.append((path: fullPath, url: URL(fileURLWithPath: fullPath)))
                            }
                        }
                    }
                }
            } else {
                // Single file
                resolvedFiles.append((path: basePath, url: URL(fileURLWithPath: basePath)))
            }
        }

        // Collect from inputFiles (drag-and-drop)
        for entry in inputFiles {
            collectDICOMFiles(from: entry.path)
        }

        // Collect from text field path(s) — semicolon-separated (the shared multi-value
        // convention; the preview expands the same split into positional tokens).
        if !filesPath.isEmpty {
            let paths = CommandBuilderHelpers.splitMultiValue(filesPath)
            for path in paths {
                if !resolvedFiles.contains(where: { $0.path == path }) {
                    collectDICOMFiles(from: path)
                }
            }
        }

        // Collect from the --input file list (one path per line; blank lines and
        // '#'-comments are skipped) — mirrors the `dicom-wado store --input` CLI option,
        // which the app form exposed but previously never read.
        let inputListPath = paramValue("input")
        if !inputListPath.isEmpty {
            if let contents = try? String(contentsOf: URL(fileURLWithPath: inputListPath), encoding: .utf8) {
                let lines = contents.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && !$0.hasPrefix("#") }
                for path in lines where !resolvedFiles.contains(where: { $0.path == path }) {
                    collectDICOMFiles(from: path)
                }
            } else {
                appendConsoleOutput("⚠️ Could not read input list: \(inputListPath)\n")
            }
        }

        guard !resolvedFiles.isEmpty else {
            appendConsoleOutput("Error: No DICOM files found. Verify the path exists and contains DICOM files.\n")
            if filesPath.isEmpty {
                appendConsoleOutput("  💡 Hint: Enter a file or directory path, or drag and drop DICOM files.\n")
            } else {
                appendConsoleOutput("  💡 Hint: The path '\(filesPath)' may be a directory. Enable 'Recursive Scan' to search subdirectories.\n")
            }
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-stow", command: commandPreview, exitCode: 1, output: "No DICOM files found")
            return
        }

        // Pre-upload header is verbose-only, matching the `dicom-wado store` CLI.
        if verbose {
            appendConsoleOutput(stowFmt.header(baseURL: profile.baseURL, targetStudyUID: studyUID,
                                               fileCount: resolvedFiles.count, batchSize: batchSize) + "\n")
            appendConsoleOutput("\n")
        }

        do {
            let client = try DICOMwebClientFactory.makeClient(from: profile)

            var totalStored = 0
            var totalFailed = 0

            // Upload in batches
            let batches = stride(from: 0, to: resolvedFiles.count, by: batchSize).map {
                Array(resolvedFiles[$0..<min($0 + batchSize, resolvedFiles.count)])
            }

            for (batchIndex, batch) in batches.enumerated() {
                if verbose {
                    appendConsoleOutput(stowFmt.batchStart(batchNumber: batchIndex + 1, fileCount: batch.count) + "\n")
                }

                var batchInstances: [Data] = []
                for file in batch {
                    do {
                        let data = try Data(contentsOf: file.url)
                        batchInstances.append(data)
                    } catch {
                        appendConsoleOutput("  ⚠️ Cannot read \(file.url.lastPathComponent): \(error.localizedDescription)\n")
                        totalFailed += 1
                        if !continueOnError {
                            appendConsoleOutput("❌ Aborting (continue-on-error is off)\n")
                            consoleStatus = .error
                            service.setConsoleStatus(.error)
                            addToHistory(toolName: "dicom-stow", command: commandPreview, exitCode: 1,
                                         output: error.localizedDescription)
                            return
                        }
                    }
                }

                guard !batchInstances.isEmpty else { continue }

                // Per-batch do/catch mirrors the CLI: an upload failure counts the whole
                // batch as failed and, only when continue-on-error is OFF, aborts the
                // remaining batches (previously the app aborted regardless of the flag).
                do {
                    let response = try await client.storeInstances(instances: batchInstances, studyUID: studyUID)
                    let stored = response.storedInstances.count
                    let failed = response.failedInstances.count
                    totalStored += stored
                    totalFailed += failed

                    if verbose {
                        appendConsoleOutput(stowFmt.batchResult(success: stored, failure: failed) + "\n")
                        for failure in response.failedInstances {
                            let reason = stowFmt.failureReason(description: failure.failureDescription,
                                                               code: failure.failureReason)
                            appendConsoleOutput(stowFmt.failureDetail(sopInstanceUID: failure.sopInstanceUID,
                                                                      reason: reason) + "\n")
                        }
                    }
                } catch {
                    totalFailed += batch.count
                    if continueOnError {
                        if verbose {
                            appendConsoleOutput("  ⚠️ Batch \(batchIndex + 1) failed: \(error.localizedDescription)\n")
                        }
                    } else {
                        throw error
                    }
                }
            }

            // Always-printed summary block — the parity contract shared with the CLI.
            appendConsoleOutput(stowFmt.summary(total: resolvedFiles.count, succeeded: totalStored,
                                                failed: totalFailed) + "\n")
            // Mirror the CLI exit semantics: failures are an error only when
            // continue-on-error is OFF (with it ON, the CLI exits success).
            let isError = totalFailed > 0 && !continueOnError
            consoleStatus = isError ? .error : .success
            service.setConsoleStatus(isError ? .error : .success)
            addToHistory(toolName: "dicom-stow", command: commandPreview,
                         exitCode: isError ? 1 : 0,
                         output: "\(totalStored) stored, \(totalFailed) failed")
        } catch {
            appendConsoleOutput("❌ STOW-RS upload failed\n")
            appendConsoleOutput("  Error: \(error.localizedDescription)\n")
            appendConsoleOutput("\n  💡 Hint: Verify the file paths are valid DICOM files and the Base URL is correct.\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-stow", command: commandPreview, exitCode: 1,
                         output: error.localizedDescription)
        }
    }

    /// Checks whether a file path looks like a DICOM candidate (by extension or lack thereof).
    private func isDICOMCandidate(_ path: String) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { return false }
        let lower = (path as NSString).lastPathComponent.lowercased()
        // Accept .dcm, .dicom, .dic, or files without an extension (common in DICOM)
        return lower.hasSuffix(".dcm") || lower.hasSuffix(".dicom") || lower.hasSuffix(".dic") || !lower.contains(".")
    }

    /// Minimal wrapper to bridge URL-based directory enumeration into the string pattern.
    private class ShallowEnumeratorWrapper: FileManager.DirectoryEnumerator {
        private let inner: FileManager.DirectoryEnumerator
        init(_ inner: FileManager.DirectoryEnumerator) { self.inner = inner }
        override func nextObject() -> Any? { inner.nextObject() }
    }

    /// Executes a UPS-RS operation against a DICOMweb server.
    private func executeDicomUPS() async {
        guard let profile = dicomwebProfileFromParams() else {
            appendConsoleOutput("Error: Base URL is required.\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-ups", command: commandPreview, exitCode: 1, output: "Base URL is required")
            return
        }

        let operation = paramValue("operation").lowercased()
        // Resolve workitem UID from the appropriate parameter based on operation
        let workitemUID: String
        switch operation {
        case "get":
            workitemUID = paramValue("get-uid")
        case "change-state":
            workitemUID = paramValue("update-uid")
        default:
            workitemUID = paramValue("workitem-uid")
        }

        appendConsoleOutput("UPS-RS \(operation.isEmpty ? "search" : operation) on \(profile.baseURL) ...\n\n")

        do {
            let client = try DICOMwebClientFactory.makeClient(from: profile)

            switch operation {
            case "get":
                guard !workitemUID.isEmpty else {
                    appendConsoleOutput("Error: Workitem UID is required for get operation.\n")
                    consoleStatus = .error
                    service.setConsoleStatus(.error)
                    return
                }
                // Render through the SHARED UPSResultFormatter, honoring --format (table/json/
                // csv) — the SAME renderer the dicom-wado ups CLI's get (and the search case)
                // uses, so the app and CLI get output cannot drift. retrieveWorkitemResult
                // returns the WorkitemResult the formatter consumes (package --format contract).
                let getResult = try await client.retrieveWorkitemResult(uid: workitemUID)
                let getFmt = UPSOutputFormat(rawValue: paramValue("output-format").lowercased()) ?? .table
                appendConsoleOutput(UPSResultFormatter().format([getResult], format: getFmt))
                consoleStatus = .success
                service.setConsoleStatus(.success)
                addToHistory(toolName: "dicom-ups", command: commandPreview, exitCode: 0,
                             output: "Workitem retrieved")

            case "create-json":
                // The CLI's `--create <json-file>` form: create a workitem from a
                // DICOM-JSON file via the same client call the CLI makes.
                let jsonPath = paramValue("create-json-file")
                guard !jsonPath.isEmpty else {
                    appendConsoleOutput("Error: Workitem JSON file is required for create.\n")
                    consoleStatus = .error
                    service.setConsoleStatus(.error)
                    return
                }
                let jsonScopedURL = securityScopedURLs["create-json-file"]
                let accessing = jsonScopedURL?.startAccessingSecurityScopedResource() ?? false
                defer { if accessing { jsonScopedURL?.stopAccessingSecurityScopedResource() } }
                let jsonURL = jsonScopedURL ?? URL(fileURLWithPath: jsonPath)
                let jsonData = try Data(contentsOf: jsonURL)
                guard let workitemData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                    appendConsoleOutput("Error: Invalid JSON format in \(jsonPath)\n")
                    consoleStatus = .error
                    service.setConsoleStatus(.error)
                    addToHistory(toolName: "dicom-ups", command: commandPreview, exitCode: 1,
                                 output: "Invalid workitem JSON")
                    return
                }
                let createResponse = try await client.createWorkitem(workitem: workitemData)
                // The CLI's printCreateResponse text via the shared UPSConsole builder.
                appendConsoleOutput(UPSConsole.createResponseText(createResponse))
                consoleStatus = .success
                service.setConsoleStatus(.success)
                addToHistory(toolName: "dicom-ups", command: commandPreview, exitCode: 0,
                             output: "Workitem created: \(createResponse.workitemUID)")

            case "create-workitem":
                // DICOMweb (UPS-RS) create flow
                let stepLabel = paramValue("create-label")
                guard !stepLabel.isEmpty else {
                    appendConsoleOutput("Error: Procedure Step Label is required for create operation.\n")
                    consoleStatus = .error
                    service.setConsoleStatus(.error)
                    return
                }

                let uid = workitemUID.isEmpty ? generateDICOMUID() : workitemUID
                appendConsoleOutput("Creating workitem \(uid)...\n")
                appendConsoleOutput("  Label: \(stepLabel)\n")

                let builder = WorkitemBuilder(workitemUID: uid)
                    .setState(.scheduled)
                    .setProcedureStepLabel(stepLabel)

                let priorityStr = paramValue("create-priority")
                if !priorityStr.isEmpty {
                    switch priorityStr.uppercased() {
                    case "STAT", "HIGH": builder.setPriority(.high)  // PS3.3 C.30.2: HIGH is equivalent to STAT

                    case "MEDIUM": builder.setPriority(.medium)
                    case "LOW": builder.setPriority(.low)
                    default: break
                    }
                    appendConsoleOutput("  Priority: \(priorityStr)\n")
                }

                let patName = paramValue("create-patient-name")
                if !patName.isEmpty {
                    builder.setPatientName(patName)
                    appendConsoleOutput("  Patient Name: \(patName)\n")
                }

                let patID = paramValue("create-patient-id")
                if !patID.isEmpty {
                    builder.setPatientID(patID)
                    appendConsoleOutput("  Patient ID: \(patID)\n")
                }

                let birthDate = paramValue("create-patient-birth-date")
                if !birthDate.isEmpty {
                    builder.setPatientBirthDate(birthDate)
                    appendConsoleOutput("  Patient Birth Date: \(birthDate)\n")
                }

                let patSex = paramValue("create-patient-sex")
                if !patSex.isEmpty {
                    // Mirror the CLI's ValidationError: an invalid sex code is an
                    // error (exit 1), never a silently dropped attribute.
                    let normalizedSex = patSex.uppercased()
                    guard ["M", "F", "O"].contains(normalizedSex) else {
                        appendConsoleOutput("Error: Invalid patient sex '\(patSex)'. Valid values: M, F, O\n")
                        consoleStatus = .error
                        service.setConsoleStatus(.error)
                        addToHistory(toolName: "dicom-ups", command: commandPreview, exitCode: 1,
                                     output: "Invalid --patient-sex")
                        return
                    }
                    builder.setPatientSex(normalizedSex)
                    appendConsoleOutput("  Patient Sex: \(normalizedSex)\n")
                }

                let startStr = paramValue("create-scheduled-start")
                if !startStr.isEmpty {
                    // Mirror the CLI's ValidationError: an unparseable date is an
                    // error (exit 1), never a silently dropped attribute.
                    guard let startDate = parseISO8601(startStr) else {
                        appendConsoleOutput("Error: Invalid date format for --scheduled-start: '\(startStr)'. Use ISO 8601 (e.g. 2026-03-20T14:00:00)\n")
                        consoleStatus = .error
                        service.setConsoleStatus(.error)
                        addToHistory(toolName: "dicom-ups", command: commandPreview, exitCode: 1,
                                     output: "Invalid --scheduled-start date")
                        return
                    }
                    builder.setScheduledStartDateTime(startDate)
                    appendConsoleOutput("  Scheduled Start: \(startStr)\n")
                }

                let completionStr = paramValue("create-expected-completion")
                if !completionStr.isEmpty {
                    // Mirror the CLI's ValidationError: an unparseable date is an
                    // error (exit 1), never a silently dropped attribute.
                    guard let completionDate = parseISO8601(completionStr) else {
                        appendConsoleOutput("Error: Invalid date format for --expected-completion: '\(completionStr)'. Use ISO 8601 (e.g. 2026-03-20T14:00:00)\n")
                        consoleStatus = .error
                        service.setConsoleStatus(.error)
                        addToHistory(toolName: "dicom-ups", command: commandPreview, exitCode: 1,
                                     output: "Invalid --expected-completion date")
                        return
                    }
                    builder.setExpectedCompletionDateTime(completionDate)
                    appendConsoleOutput("  Expected Completion: \(completionStr)\n")
                }

                let studyRef = paramValue("create-study-uid")
                if !studyRef.isEmpty {
                    builder.setStudyInstanceUID(studyRef)
                    appendConsoleOutput("  Study UID: \(studyRef) (→ Input Information + Referenced Request)\n")
                }

                let accession = paramValue("create-accession")
                if !accession.isEmpty {
                    builder.setAccessionNumber(accession)
                    appendConsoleOutput("  Accession: \(accession)\n")
                }

                let referring = paramValue("create-referring-physician")
                if !referring.isEmpty {
                    builder.setReferringPhysicianName(referring)
                    appendConsoleOutput("  Referring Physician: \(referring)\n")
                }

                let procID = paramValue("create-procedure-id")
                if !procID.isEmpty {
                    builder.setRequestedProcedureID(procID)
                    appendConsoleOutput("  Procedure ID: \(procID)\n")
                }

                let stepID = paramValue("create-step-id")
                if !stepID.isEmpty {
                    builder.setScheduledProcedureStepID(stepID)
                    appendConsoleOutput("  Step ID: \(stepID)\n")
                }

                let wlLabel = paramValue("create-worklist-label")
                if !wlLabel.isEmpty {
                    builder.setWorklistLabel(wlLabel)
                    appendConsoleOutput("  Worklist Label: \(wlLabel)\n")
                }

                let station = paramValue("create-station-name")
                if !station.isEmpty {
                    builder.setScheduledStationNameCodes([
                        CodedEntry(codeValue: station, codingSchemeDesignator: "L", codeMeaning: station)
                    ])
                    appendConsoleOutput("  Station: \(station)\n")
                }

                // A performer entry is added when either the name or the organization
                // is set — the same either-or the CLI's createWorkitemFromOptions uses.
                let performer = paramValue("create-performer")
                let performerOrg = paramValue("create-performer-organization")
                if !performer.isEmpty || !performerOrg.isEmpty {
                    builder.addScheduledHumanPerformer(
                        HumanPerformer(
                            performerName: performer.isEmpty ? nil : performer,
                            performerOrganization: performerOrg.isEmpty ? nil : performerOrg
                        )
                    )
                    if !performer.isEmpty { appendConsoleOutput("  Performer: \(performer)\n") }
                    if !performerOrg.isEmpty { appendConsoleOutput("  Performer Organization: \(performerOrg)\n") }
                }

                let cmt = paramValue("create-comments")
                if !cmt.isEmpty {
                    builder.setComments(cmt)
                }

                let admissionID = paramValue("create-admission-id")
                if !admissionID.isEmpty {
                    builder.setAdmissionID(admissionID)
                    appendConsoleOutput("  Admission ID: \(admissionID)\n")
                }

                appendConsoleOutput("\n")

                let workitem = try builder.build()

                // Log the equivalent curl command for debugging
                do {
                    let createJSON = workitem.toDICOMJSONForCreate()
                    let createURL: URL
                    if uid.isEmpty {
                        createURL = client.urlBuilder.workitemsURL
                    } else {
                        createURL = client.urlBuilder.createWorkitemURL(workitemUID: uid)
                    }
                    if let jsonData = try? JSONSerialization.data(
                        withJSONObject: createJSON,
                        options: [.prettyPrinted, .sortedKeys]
                    ),
                       let jsonStr = String(data: jsonData, encoding: .utf8) {
                        let escapedJSON = jsonStr.replacingOccurrences(of: "'", with: "'\\''")
                        appendConsoleOutput("─── curl equivalent ───\n")
                        appendConsoleOutput("curl -X POST \\\n")
                        appendConsoleOutput("  '\(createURL.absoluteString)' \\\n")
                        appendConsoleOutput("  -H 'Content-Type: application/dicom+json' \\\n")
                        appendConsoleOutput("  -H 'Accept: application/dicom+json' \\\n")
                        appendConsoleOutput("  -d '\(escapedJSON)'\n")
                        appendConsoleOutput("───────────────────────\n\n")
                    }
                }

                let response = try await client.createWorkitem(workitem)

                // CLI parity: the same printCreateResponse block the dicom-wado ups
                // CLI prints, via the shared UPSConsole builder.
                appendConsoleOutput(UPSConsole.createResponseText(response))
                consoleStatus = .success
                service.setConsoleStatus(.success)
                addToHistory(toolName: "dicom-ups", command: commandPreview, exitCode: 0,
                             output: "Workitem created: \(response.workitemUID)")

            case "change-state":
                // DICOMweb (UPS-RS) change-state flow
                guard !workitemUID.isEmpty else {
                    appendConsoleOutput("Error: Workitem UID is required for change-state operation.\n")
                    consoleStatus = .error
                    service.setConsoleStatus(.error)
                    return
                }
                let stateStr = paramValue("state")
                // `rawState` is the DICOM CS spelling ("IN PROGRESS"/"COMPLETED"/
                // "CANCELED") used for narration and the pre-flight state-machine
                // check. The actual transition is driven through the SHARED
                // DICOMwebClient helpers below; the package's DICOMWeb.UPSState is
                // resolved CONTEXTUALLY at each call site (DICOMStudio also defines
                // a local UPSState with different raw values, and the module exposes
                // a `DICOMWeb` namespace enum that shadows the module name — so we
                // deliberately never spell the type out here).
                let rawState: String
                switch stateStr.uppercased() {
                case "SCHEDULED": rawState = "SCHEDULED"
                case "COMPLETED": rawState = "COMPLETED"
                case "CANCELED":  rawState = "CANCELED"
                default:          rawState = "IN PROGRESS"
                }

                // Per PS3.4 CC.2 UPS State Machine:
                //   SCHEDULED → IN PROGRESS  : client supplies a new Transaction UID
                //   IN PROGRESS → COMPLETED  : client MUST supply the same Transaction UID
                //   IN PROGRESS → CANCELED   : client MUST supply the same Transaction UID
                //
                // Per PS3.18 §11.5.2, the server NEVER returns the Transaction UID
                // in Retrieve Workitem responses — it acts as an access lock.
                // We cache it locally when claiming (IN PROGRESS) and auto-fill it
                // for subsequent COMPLETED / CANCELED transitions.
                let userTxUID = paramValue("transaction-uid")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                var effectiveTxUID: String
                if rawState == "IN PROGRESS" {
                    // New transition — generate a fresh Transaction UID
                    effectiveTxUID = userTxUID.isEmpty ? generateDICOMUID() : userTxUID
                } else if rawState == "SCHEDULED" {
                    // SCHEDULED — the Transaction UID is optional and NEVER
                    // auto-generated (mirrors the CLI's default branch in
                    // DICOMWado.updateWorkitem): pass through what the user
                    // supplied; empty resolves to nil at the call site below.
                    effectiveTxUID = userTxUID
                } else {
                    // COMPLETED / CANCELED — must reuse the Transaction UID from IN PROGRESS.
                    // Check (in order): user-provided → cached from previous IN PROGRESS claim.
                    let cachedTxUID = upsTransactionUIDs[workitemUID]
                    if !userTxUID.isEmpty {
                        effectiveTxUID = userTxUID
                    } else if let cached = cachedTxUID, !cached.isEmpty {
                        effectiveTxUID = cached
                        appendConsoleOutput("  ℹ️  Using cached Transaction UID from IN PROGRESS claim\n")
                    } else {
                        appendConsoleOutput("Error: Transaction UID is required for \(rawState) transition.\n")
                        appendConsoleOutput("  💡 Use the Transaction UID returned when the workitem was moved to IN PROGRESS.\n")
                        consoleStatus = .error
                        service.setConsoleStatus(.error)
                        return
                    }
                }

                // Per PS3.18 §11.6 the Requesting AE may be appended as the last
                // path segment of the state URL.  Some servers (e.g. dcm4chee-arc)
                // **require** this segment; without it the route returns 404.
                // Use the "Requesting AE" field (change-state-aet, previewed as
                // --aet) — falling back to "DCM4CHEE", the AE that owns the UPS
                // instance on a default dcm4chee-arc.
                let requestingAEValue = paramValue("change-state-aet")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let requestingAE = requestingAEValue.isEmpty ? "DCM4CHEE" : requestingAEValue

                // CLI parity: the CLI's --verbose header (the Workshop panel is
                // always verbose), via the shared UPSConsole builder.
                appendConsoleOutput(UPSConsole.updateVerboseHeader(
                    uid: workitemUID, stateRaw: rawState,
                    requestingAE: requestingAE,
                    transactionUID: effectiveTxUID.isEmpty ? nil : effectiveTxUID))

                // Per PS3.18 §11.6, the Transaction UID for the state
                // change goes in the REQUEST BODY only (not the URL).
                // The URL query parameter ?00081195 belongs only to the
                // Update Workitem endpoint (§11.5).
                let stateURL = client.urlBuilder.workitemStateURL(
                    workitemUID: workitemUID,
                    requestingAE: requestingAE)
                appendConsoleOutput("  URL: \(stateURL.absoluteString)\n")

                // Pre-flight: retrieve the workitem to verify current state.
                // NOTE: Per PS3.18 §11.5.2, the server NEVER returns Transaction
                // UID (0008,1195) — it acts as an access lock known only to the
                // owner.  We rely on our local cache instead.
                do {
                    let currentAttrs = try await client.retrieveWorkitem(uid: workitemUID)
                    if let stateElem = currentAttrs[UPSTag.procedureStepState] as? [String: Any],
                       let vals = stateElem["Value"] as? [String],
                       let currentRaw = vals.first {
                        appendConsoleOutput("  Current state:   \(currentRaw)\n")

                        // Validate transition using the DICOM PS3.4 CC.1.1 state machine.
                        // SCHEDULED is never a valid *transition* target (it is the
                        // N-CREATE initial state), but the CLI submits the request and
                        // reports the server's verdict — do the same here rather than
                        // hard-blocking client-side.
                        let validTargets: [String]
                        switch currentRaw {
                        case "SCHEDULED":   validTargets = ["IN PROGRESS"]
                        case "IN PROGRESS": validTargets = ["COMPLETED", "CANCELED"]
                        default:            validTargets = []
                        }
                        if rawState != "SCHEDULED", !validTargets.contains(rawState) {
                            appendConsoleOutput("\n❌ Invalid state transition: \(currentRaw) → \(rawState)\n")
                            if currentRaw == "COMPLETED" || currentRaw == "CANCELED" {
                                appendConsoleOutput("  💡 The workitem is in a final state and cannot be changed.\n")
                            } else {
                                appendConsoleOutput("  💡 The workitem must be in \(rawState == "IN PROGRESS" ? "SCHEDULED" : "IN PROGRESS") state.\n")
                            }
                            consoleStatus = .error
                            service.setConsoleStatus(.error)
                            addToHistory(toolName: "dicom-ups", command: commandPreview, exitCode: 1,
                                         output: "Invalid transition \(currentRaw) → \(rawState)")
                            return
                        }
                    } else {
                        appendConsoleOutput("  ⚠️  Could not read current state from server\n")
                    }
                    appendConsoleOutput("\n")
                } catch {
                    // Pre-flight check is best-effort; proceed with the state
                    // change even if it fails.
                    appendConsoleOutput("  ⚠️  Pre-flight check failed: \(error.localizedDescription)\n\n")
                }

                // ── Perform the state change through the SHARED DICOMwebClient ──
                // completeWorkitem() (COMPLETED) and changeWorkitemState()
                // (IN PROGRESS / CANCELED) are the SAME single source of truth
                // the dicom-wado ups CLI calls (see DICOMWado.updateWorkitem).
                // The request payload — including the Final State attributes
                // (Performed Procedure Sequence) PS3.4 CC.2.5-3 requires before
                // COMPLETED — is built in exactly ONE place inside the package,
                // so the app and the CLI cannot drift.
                do {
                    let response: UPSStateChangeResponse
                    switch rawState {
                    case "COMPLETED":
                        // completeWorkitem first sends the minimal Final State
                        // Update Workitem (PS3.18 §11.5) the SCP requires, then
                        // performs the Change State to COMPLETED (§11.6).
                        appendConsoleOutput("📝 Populating Final State attributes, then completing ...\n")
                        appendConsoleOutput("   (Performed Procedure Sequence required by PS3.4 CC.2.5-3 before COMPLETED)\n")
                        response = try await client.completeWorkitem(
                            uid: workitemUID,
                            transactionUID: effectiveTxUID,
                            requestingAE: requestingAE)
                    case "CANCELED":
                        // `.canceled` resolves to DICOMWeb.UPSState via the `state:` parameter.
                        response = try await client.changeWorkitemState(
                            uid: workitemUID,
                            state: .canceled,
                            transactionUID: effectiveTxUID,
                            requestingAE: requestingAE)
                    case "SCHEDULED":
                        // Real SCHEDULED transition, mirroring the CLI
                        // (DICOMWado.updateWorkitem) — the Transaction UID is
                        // optional here, so an empty field resolves to nil.
                        response = try await client.changeWorkitemState(
                            uid: workitemUID,
                            state: .scheduled,
                            transactionUID: effectiveTxUID.isEmpty ? nil : effectiveTxUID,
                            requestingAE: requestingAE)
                    default: // IN PROGRESS
                        response = try await client.changeWorkitemState(
                            uid: workitemUID,
                            state: .inProgress,
                            transactionUID: effectiveTxUID,
                            requestingAE: requestingAE)
                    }

                    // Cache / clear the Transaction UID for this workitem (silent
                    // bookkeeping — COMPLETED/CANCELED auto-fill from this cache).
                    // Prefer the Transaction UID the server returned on the
                    // IN PROGRESS response; fall back to the one we supplied.
                    let resolvedTxUID = response.transactionUID ?? effectiveTxUID
                    if rawState == "IN PROGRESS" {
                        upsTransactionUIDs[workitemUID] = resolvedTxUID
                    } else if rawState != "SCHEDULED" {
                        // Terminal state — drop the cached TX UID.
                        upsTransactionUIDs.removeValue(forKey: workitemUID)
                    }

                    // CLI parity: the CLI's change-state result block via the shared
                    // UPSConsole builder (success line, transaction UID, warnings).
                    appendConsoleOutput(UPSConsole.updateResultText(
                        uid: workitemUID, stateRaw: rawState,
                        transactionUID: resolvedTxUID.isEmpty ? nil : resolvedTxUID,
                        warnings: response.warnings))
                } catch let error as DICOMwebError {
                    appendConsoleOutput("\n")
                    switch error {
                    case .conflict(let message):
                        appendConsoleOutput("❌ State change failed (HTTP 409)\n")
                        if let msg = message, !msg.isEmpty {
                            appendConsoleOutput("  Server message: \(msg)\n")
                        }
                        appendConsoleOutput("  💡 State transition conflict — check:\n")
                        appendConsoleOutput("     • Current state allows transition to \(rawState)?\n")
                        appendConsoleOutput("     • Transaction UID matches the one from IN PROGRESS?\n")
                        appendConsoleOutput("     • Workitem is not locked by another performer?\n")
                        if rawState == "COMPLETED" {
                            appendConsoleOutput("     • Final State attributes (Performed Procedure Sequence) are populated?\n")
                        }
                    case .notFound:
                        appendConsoleOutput("❌ State change failed (HTTP 404)\n")
                        appendConsoleOutput("  💡 Workitem \(workitemUID) not found on the server.\n")
                    case .badRequest(let message):
                        appendConsoleOutput("❌ State change failed (HTTP 400)\n")
                        if let msg = message, !msg.isEmpty {
                            appendConsoleOutput("  Server message: \(msg)\n")
                        }
                    default:
                        appendConsoleOutput("❌ State change failed: \(error.localizedDescription)\n")
                    }
                    consoleStatus = .error
                    service.setConsoleStatus(.error)
                    addToHistory(toolName: "dicom-ups", command: commandPreview, exitCode: 1,
                                 output: "State change to \(rawState) failed")
                    return
                } catch let error as UPSError {
                    // CustomStringConvertible — interpolate directly for a readable message.
                    appendConsoleOutput("\n❌ State change failed: \(error)\n")
                    if case .transactionUIDMismatch = error {
                        appendConsoleOutput("  💡 The Transaction UID must match the one returned when the workitem moved to IN PROGRESS.\n")
                    }
                    consoleStatus = .error
                    service.setConsoleStatus(.error)
                    addToHistory(toolName: "dicom-ups", command: commandPreview, exitCode: 1,
                                 output: "State change to \(rawState) failed")
                    return
                }

                consoleStatus = .success
                service.setConsoleStatus(.success)
                addToHistory(toolName: "dicom-ups", command: commandPreview, exitCode: 0,
                             output: "State changed to \(rawState)")

            case "subscribe":
                guard !workitemUID.isEmpty else {
                    appendConsoleOutput("Error: Workitem UID is required for subscribe operation.\n")
                    consoleStatus = .error
                    service.setConsoleStatus(.error)
                    return
                }
                // Honor the --aet field the command preview shows (defaults to
                // DICOM_STUDIO, the AE the in-app Event Monitor listens as).
                // subscribe and unsubscribe MUST read the same source so the
                // round-trip targets one subscription.
                let subscribeAET = paramValue("subscribe-aet").isEmpty ? "DICOM_STUDIO" : paramValue("subscribe-aet")
                appendConsoleOutput("Subscribing to workitem \(workitemUID) as \(subscribeAET) ...\n")
                try await client.subscribeToWorkitem(
                    workitemUID: workitemUID,
                    aeTitle: subscribeAET
                )
                appendConsoleOutput("✅ Subscription created\n")

                // Fetch and display workitem details for context
                appendConsoleOutput("\nFetching workitem details...\n")
                do {
                    let result = try await client.retrieveWorkitemResult(uid: workitemUID)
                    appendConsoleOutput("  Workitem UID:   \(result.workitemUID)\n")
                    if let label = result.procedureStepLabel {
                        appendConsoleOutput("  Procedure:      \(label)\n")
                    }
                    if let state = result.state {
                        appendConsoleOutput("  State:          \(state.rawValue)\n")
                    }
                    if let priority = result.priority {
                        appendConsoleOutput("  Priority:       \(priority.rawValue)\n")
                    }
                    if let name = result.patientName {
                        appendConsoleOutput("  Patient Name:   \(name)\n")
                    }
                    if let pid = result.patientID {
                        appendConsoleOutput("  Patient ID:     \(pid)\n")
                    }
                    if let accession = result.accessionNumber {
                        appendConsoleOutput("  Accession:      \(accession)\n")
                    }
                    if let scheduled = result.scheduledStartDateTime {
                        appendConsoleOutput("  Scheduled:      \(scheduled)\n")
                    }
                    if let pct = result.progressPercentage {
                        appendConsoleOutput("  Progress:       \(pct)%\n")
                    }
                    if let desc = result.progressDescription {
                        appendConsoleOutput("  Progress Desc:  \(desc)\n")
                    }
                    appendConsoleOutput("\n")
                } catch {
                    appendConsoleOutput("  (Could not fetch workitem details: \(error.localizedDescription))\n\n")
                }

                appendConsoleOutput("📡 Events for this workitem will appear in the DICOMweb Event Monitor.\n")
                appendConsoleOutput("   Navigate to DICOMweb → UPS → Event Monitor to view live events.\n")

                consoleStatus = .success
                service.setConsoleStatus(.success)
                addToHistory(toolName: "dicom-ups", command: commandPreview, exitCode: 0,
                             output: "Subscribed to \(workitemUID)")

            case "unsubscribe":
                guard !workitemUID.isEmpty else {
                    appendConsoleOutput("Error: Workitem UID is required for unsubscribe operation.\n")
                    consoleStatus = .error
                    service.setConsoleStatus(.error)
                    return
                }
                // Route through the SHARED DICOMwebClient.unsubscribeFromWorkitem()
                // the dicom-wado ups CLI uses. Read the same --aet field the
                // subscribe case uses (default DICOM_STUDIO) so the unsubscribe
                // targets the subscription the app created.
                let unsubscribeAET = paramValue("subscribe-aet").isEmpty ? "DICOM_STUDIO" : paramValue("subscribe-aet")
                appendConsoleOutput("Unsubscribing from workitem \(workitemUID) as \(unsubscribeAET) ...\n")
                try await client.unsubscribeFromWorkitem(
                    workitemUID: workitemUID,
                    aeTitle: unsubscribeAET
                )
                appendConsoleOutput("✅ Unsubscribed from workitem \(workitemUID)\n")
                appendConsoleOutput("   No further events for this workitem will be delivered to the Event Monitor.\n")

                consoleStatus = .success
                service.setConsoleStatus(.success)
                addToHistory(toolName: "dicom-ups", command: commandPreview, exitCode: 0,
                             output: "Unsubscribed from \(workitemUID)")

            default: // search
                // Build the query via the SHARED UPSQuery.workitemSearch builder (DICOMWeb) —
                // the SAME single source of truth the dicom-wado ups CLI and the CLI-parity
                // reference call, so all three issue an IDENTICAL UPS-RS query. Only the two
                // real CLI search flags (--filter-state / --scheduled-station) feed it; the app
                // adds no extra filters, no limit, and no includefield (the CLI sets none).
                let query: UPSQuery
                do {
                    query = try UPSQuery.workitemSearch(filterState: paramValue("filter-state"),
                                                        scheduledStation: paramValue("scheduled-station"))
                } catch {
                    appendConsoleOutput("Error: \(error)\n")
                    consoleStatus = .error
                    service.setConsoleStatus(.error)
                    addToHistory(toolName: "dicom-ups", command: commandPreview, exitCode: 1,
                                 output: "\(error)")
                    return
                }

                // Log the outgoing query
                let searchURL = client.urlBuilder.searchWorkitemsURL(parameters: query.toParameters())
                appendConsoleOutput("Query URL: \(searchURL.absoluteString)\n")
                if !query.toParameters().isEmpty {
                    appendConsoleOutput("Filters:\n")
                    for (key, value) in query.toParameters().sorted(by: { $0.key < $1.key }) {
                        appendConsoleOutput("  \(key) = \(value)\n")
                    }
                }
                appendConsoleOutput("\n")

                let results = try await client.searchWorkitems(query: query)
                let count = results.workitems.count
                appendConsoleOutput("✅ UPS-RS returned \(count) workitem(s)\n\n")
                // Render the matched workitems through the SHARED UPSResultFormatter — the SAME
                // table/json/csv renderer the dicom-wado ups CLI uses — so the app and CLI
                // output pipelines cannot drift (mirrors QIDOResultFormatter for the query
                // subcommand).
                let fmt = UPSOutputFormat(rawValue: paramValue("output-format").lowercased()) ?? .table
                appendConsoleOutput(UPSResultFormatter().format(results.workitems, format: fmt))
                consoleStatus = .success
                service.setConsoleStatus(.success)
                addToHistory(toolName: "dicom-ups", command: commandPreview, exitCode: 0,
                             output: "\(count) workitems returned")
            }
        } catch {
            appendConsoleOutput("❌ UPS-RS \(operation) failed\n")
            appendConsoleOutput("  Error: \(error.localizedDescription)\n")
            appendConsoleOutput("\n  💡 Hint: Verify the Base URL is correct and the server supports UPS-RS.\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-ups", command: commandPreview, exitCode: 1,
                         output: error.localizedDescription)
        }
    }

    /// Generates a DICOM UID for workitem creation.
    private func generateDICOMUID() -> String {
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000000)
        let random = UInt32.random(in: 1...999999)
        return "1.2.826.0.1.3680043.8.498.\(timestamp).\(random)"
    }

    /// Parses an ISO 8601 date string into a Date.
    private func parseISO8601(_ value: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: value) { return date }
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: value) { return date }
        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        // Same fallback list as the dicom-wado CLI's parseISO8601Date, including
        // the compact DICOM-style forms (e.g. "20260320T140000", "20260320").
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd", "yyyyMMdd'T'HHmmss", "yyyyMMdd"] {
            fallback.dateFormat = fmt
            if let date = fallback.date(from: value) { return date }
        }
        return nil
    }

    /// The `--level` value → Query/Retrieve Level (0008,0052). The picker offers the
    /// PS3.4 2026a Table C.6.1-1 / C.6.2-1 values in lower case (patient, study, series,
    /// image); "instance" is accepted as the CLI's alias of image (QueryLevelOption).
    nonisolated static func queryLevelOption(_ raw: String) -> QueryLevel? {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "patient": return .patient
        case "study": return .study
        case "series": return .series
        case "image", "instance": return .image
        default: return nil
        }
    }

    /// dicom-query's `validate()` (PS3.4 C.4.1.2.1): a SERIES query needs the parent
    /// Study UID, an IMAGE query needs Study and Series UIDs. Returns the CLI's
    /// ValidationError text (exit 64), or nil when the keys are complete.
    nonisolated static func queryLevelRefusal(level: QueryLevel, studyUID: String, seriesUID: String) -> String? {
        switch level {
        case .series where studyUID.isEmpty:
            return "--level series requires --study-uid (PS3.4 C.4.1.2.1: the Study Instance UID of the level above must be given)"
        case .image where studyUID.isEmpty || seriesUID.isEmpty:
            return "--level image (instance) requires --study-uid and --series-uid (PS3.4 C.4.1.2.1)"
        default:
            return nil
        }
    }

    /// The shared formatter exactly as dicom-query builds it: `dicom-json` is encoded by
    /// DICOMWeb's PS3.18 F.2 encoder (pretty-printed, attributes in ascending tag order
    /// per F.2.2) and `--csv-keywords` names the CSV columns by PS3.6 keyword.
    nonisolated static func queryResultFormatter(format: QueryOutputFormat, level: QueryLevel,
                                                 csvKeywords: Bool) -> DICOMQueryResultFormatter {
        DICOMQueryResultFormatter(
            format: format, level: level,
            csvHeader: csvKeywords ? .keyword : .tag,
            dicomJSONEncoder: { try DICOMJSONEncoder(configuration: .init(prettyPrinted: true)).encodeMultiple($0) })
    }

    /// Runs a `--modality` value through the shared DICOMCore.ModalityOptionValidator
    /// exactly as the CLIs' `ModalityOptionValidator.resolve(_:strict:verbose:)`: an alias
    /// is normalised (noted only with --verbose), a retired / unknown code warns and is
    /// sent as-is, or is rejected under --strict-modality. Returns the value to send and
    /// the console lines, or the CLI's error text (exit 1).
    nonisolated static func resolveModalityOption(_ raw: String, strict: Bool, verbose: Bool)
        -> (value: String, lines: [String], error: String?) {
        guard let outcome = ModalityOptionValidator.validate(raw) else { return (raw, [], nil) }
        var lines: [String] = []
        if let warning = outcome.warning {
            if strict, outcome.isStrictFailure {
                return (raw, [], warning + " Rejected because --strict-modality is set.")
            }
            if !outcome.isNote || verbose {
                lines.append(outcome.isNote ? warning : "warning: " + warning + " Sending it as-is.")
            }
        }
        return (outcome.value, lines, nil)
    }

    /// Performs a C-FIND query against the server configured in the parameter fields.
    private func executeDicomQuery() async {
        let hostValue = paramValue("host")
        let portValue = paramValue("port")
        let callingAET = paramValue("aet").isEmpty ? "DICOMSTUDIO" : paramValue("aet")
        let calledAET = paramValue("called-aet").isEmpty ? "ANY-SCP" : paramValue("called-aet")
        let timeoutStr = paramValue("timeout")
        let levelStr = paramValue("level")
        let outputFormat = paramValue("output-format").lowercased()
        let csvKeywords = paramValue("csv-keywords") == "true"
        let strictModality = paramValue("strict-modality") == "true"
        let verbose = paramValue("verbose") == "true"

        /// Refuses the run with the CLI's `Error: …` line and exit code.
        func refuse(_ message: String, exitCode: Int) {
            appendConsoleOutput("Error: \(message)\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-query", command: commandPreview, exitCode: exitCode, output: message)
        }

        guard let server = resolveHostPort(hostValue, explicitPort: portValue) else {
            refuse("A valid host is required (e.g. hostname or hostname:11112).", exitCode: 64)
            return
        }

        let host = server.host
        let port = server.port
        let timeout = TimeInterval(timeoutStr) ?? 60

        // The picker offers the PS3.4 Table C.6.1-1 values (patient/study/series/image);
        // "instance" is the CLI's alias of image. The wire value is always IMAGE.
        let level = Self.queryLevelOption(levelStr) ?? .study

        // Collect all user-provided filter values
        let patientID = paramValue("patient-id")
        let patientName = paramValue("patient-name")
        let studyDate = paramValue("study-date")
        var modality = paramValue("modality")
        let studyUID = paramValue("study-uid")
        let seriesUID = paramValue("series-uid")
        let seriesDate = paramValue("series-date")
        let instanceUID = paramValue("instance-uid")
        let accession = paramValue("accession-number")
        let studyDesc = paramValue("study-description")
        let referringPhysician = paramValue("referring-physician")
        let includeParentKeys = paramValue("include-parent-keys") == "true"

        // PS3.4 C.4.1.2.1 (dicom-query validate()): the Unique Keys of the levels above
        // the query level must be given — ArgumentParser usage error, exit 64.
        if let message = Self.queryLevelRefusal(level: level, studyUID: studyUID, seriesUID: seriesUID) {
            refuse(message, exitCode: 64)
            return
        }

        // --modality through the shared ModalityOptionValidator (PS3.3 C.7.3.1.1.1), as the
        // CLI's run() does before any connection: alias note (verbose), retired/unknown
        // warning, or --strict-modality rejection (exit 1).
        let resolved = Self.resolveModalityOption(modality, strict: strictModality, verbose: verbose)
        if let message = resolved.error {
            refuse(message, exitCode: 1)
            return
        }
        modality = resolved.value
        for line in resolved.lines { appendConsoleOutput(line + "\n") }

        // Verbose header via the SHARED NetworkConsole formatter (DICOMNetwork), gated on
        // --verbose so a plain run is just the results table — identical to the CLI. The
        // filter list uses the same canonical order/labels as the CLI's appliedFilters().
        if verbose {
            let model = (level == .patient) ? "Patient Root" : "Study Root"
            var filters: [(label: String, value: String)] = []
            func addFilter(_ label: String, _ value: String) {
                if !value.isEmpty { filters.append((label, value)) }
            }
            addFilter("Patient Name:", patientName)
            addFilter("Patient ID:", patientID)
            addFilter("Study Date:", studyDate)
            addFilter("Modality:", modality)
            addFilter("Study UID:", studyUID)
            addFilter("Series UID:", seriesUID)
            addFilter("Accession:", accession)
            addFilter("Study Desc:", studyDesc)
            addFilter("Referring Physician:", referringPhysician)
            appendConsoleOutput(NetworkConsole.queryHeader(
                host: host, port: port,
                callingAE: callingAET, calledAE: calledAET,
                level: level, informationModel: model,
                timeout: Int(timeout), filters: filters))
        }

        // PS3.4 C.4.1.2.1: patient/study filters cannot be matched at SERIES or IMAGE
        // level under the hierarchical model. The CLI warns on stderr rather than dropping
        // them silently; the Workshop prints the SAME text (the level named by its
        // Query/Retrieve Level (0008,0052) value, PS3.4 Table C.6.2-1) into the console.
        let ignoredFilters = DICOMQueryService.ignoredParentLevelFilters(
            level: level,
            patientName: patientName, patientID: patientID,
            studyDate: studyDate, accession: accession,
            studyDescription: studyDesc, referringPhysician: referringPhysician)
        if !ignoredFilters.isEmpty {
            appendConsoleOutput(
                "Warning: \(ignoredFilters.joined(separator: ", ")) cannot be matched at \(level.rawValue) level "
                + "under the hierarchical query model and will be ignored "
                + "(PS3.4 C.4.1.2.1: only the Unique Keys of the levels above may be sent). "
                + "Query at STUDY level first, then narrow with --study-uid.\n")
        }

        // Build C-FIND keys via the SHARED package mapping (DICOMNetwork) — the same
        // code the dicom-query CLI and the CLI-parity reference use, so input→C-FIND
        // cannot drift. Pass the SAME argument set as the CLI (incl. accession and
        // study-description) so the keys — and therefore the result table — match.
        let queryKeys = DICOMQueryService.buildQueryKeys(
            level: level,
            patientName: patientName, patientID: patientID,
            studyDate: studyDate, modality: modality,
            accession: accession, studyDescription: studyDesc,
            referringPhysician: referringPhysician,
            studyUID: studyUID, seriesUID: seriesUID,
            seriesDate: seriesDate, instanceUID: instanceUID,
            includeParentLevelReturnKeys: includeParentKeys)

        do {
            let informationModel: QueryRetrieveInformationModel = (level == .patient) ? .patientRoot : .studyRoot
            let config = QueryConfiguration(
                callingAETitle: try AETitle(callingAET),
                calledAETitle: try AETitle(calledAET),
                timeout: timeout,
                informationModel: informationModel
            )

            // Direct C-FIND — the same single-query pipeline as the dicom-query CLI.
            let results = try await DICOMQueryService.find(
                host: host, port: port, configuration: config, queryKeys: queryKeys)

            // Render via the SHARED formatter (DICOMNetwork) built exactly as the CLI
            // builds it (DICOMQuery.formatter): dicom-json through DICOMWeb's PS3.18 F.2
            // encoder, CSV header by tag or PS3.6 keyword. The formatter renders "No
            // results found." for an empty set, so both cases go through one code path.
            let fmt = QueryOutputFormat(rawValue: outputFormat) ?? .table
            let formatter = Self.queryResultFormatter(format: fmt, level: level, csvKeywords: csvKeywords)
            appendConsoleOutput(formatter.format(results: results))
            consoleStatus = .success
            service.setConsoleStatus(.success)
            addToHistory(toolName: "dicom-query", command: commandPreview, exitCode: 0,
                         output: "\(results.count) result(s) found")
        } catch {
            // ArgumentParser prints a thrown error as `Error: <description>` and exits 1.
            let errorDetail = (error as? DICOMNetworkError)?.description ?? error.localizedDescription
            refuse(errorDetail, exitCode: 1)
        }
    }

    /// Fetches parent study/patient info from the server for a set of Study UIDs.
    /// Returns a lookup dictionary keyed by Study Instance UID.
    private func fetchParentStudyInfo(
        host: String, port: UInt16,
        callingAET: String, calledAET: String,
        timeout: TimeInterval,
        studyUIDs: [String]
    ) async -> [String: GenericQueryResult] {
        var lookup: [String: GenericQueryResult] = [:]
        for uid in studyUIDs {
            do {
                let keys = QueryKeys(level: .study)
                    .studyInstanceUID(uid)
                    .requestPatientName()
                    .requestPatientID()
                    .requestPatientBirthDate()
                    .requestPatientSex()
                    .requestStudyDate()
                    .requestStudyTime()
                    .requestStudyDescription()
                    .requestAccessionNumber()
                    .requestModalitiesInStudy()
                    .requestNumberOfStudyRelatedSeries()
                    .requestNumberOfStudyRelatedInstances()
                let config = QueryConfiguration(
                    callingAETitle: try AETitle(callingAET),
                    calledAETitle: try AETitle(calledAET),
                    timeout: timeout,
                    informationModel: .studyRoot
                )
                let results = try await DICOMQueryService.find(
                    host: host, port: port,
                    configuration: config,
                    queryKeys: keys
                )
                if let first = results.first {
                    lookup[uid] = first
                }
            } catch {
                // Parent info is supplementary — continue on failure
            }
        }
        return lookup
    }

    /// Performs a concurrent two-step lookup for SERIES/IMAGE queries without Study UID.
    ///
    /// Step 1: Find all matching Study UIDs (applying patient/study filters).
    /// Step 2: Query target level concurrently across studies with early cancellation
    ///         when a globally unique UID is provided.
    private func concurrentSeriesLookup(
        host: String, port: UInt16, config: QueryConfiguration,
        level: QueryLevel,
        patientID: String, patientName: String,
        studyDate: String,
        modality: String, seriesUID: String,
        seriesDate: String, instanceUID: String,
        callingAET: String, calledAET: String,
        timeout: TimeInterval
    ) async throws -> [GenericQueryResult] {
        // Step 1: Find matching studies
        appendConsoleOutput("Step 1: Finding matching studies...\n")
        var studyQueryKeys = QueryKeys(level: .study)
            .requestStudyInstanceUID()
        if !patientID.isEmpty { studyQueryKeys = studyQueryKeys.patientID(patientID) }
        if !patientName.isEmpty { studyQueryKeys = studyQueryKeys.patientName(patientName) }
        if !studyDate.isEmpty { studyQueryKeys = studyQueryKeys.studyDate(studyDate) }
        if !modality.isEmpty { studyQueryKeys = studyQueryKeys.modalitiesInStudy(modality) }

        let studyConfig = QueryConfiguration(
            callingAETitle: try AETitle(callingAET),
            calledAETitle: try AETitle(calledAET),
            timeout: timeout,
            informationModel: .studyRoot
        )
        let studies = try await DICOMQueryService.find(
            host: host, port: port,
            configuration: studyConfig,
            queryKeys: studyQueryKeys
        )
        let studyUIDs = studies.compactMap { $0.toStudyResult().studyInstanceUID }
        appendConsoleOutput("  Found \(studyUIDs.count) matching study(ies)\n")

        guard !studyUIDs.isEmpty else {
            appendConsoleOutput("No matching studies found — no \(level) results.\n")
            return []
        }

        let hasUniqueMatch = (level == .series && !seriesUID.isEmpty) ||
            (level == .image && !instanceUID.isEmpty)

        // Step 2: Query concurrently across studies
        appendConsoleOutput("Step 2: Querying \(level) level across \(studyUIDs.count) study(ies)...\n")

        let allResults: [GenericQueryResult] = try await withThrowingTaskGroup(
            of: [GenericQueryResult].self
        ) { group in
            // Limit concurrency to avoid overwhelming the PACS
            let maxConcurrent = min(studyUIDs.count, 8)
            var submitted = 0
            var collected: [GenericQueryResult] = []

            for uid in studyUIDs.prefix(maxConcurrent) {
                group.addTask { [self] in
                    try await self.queryLevelForStudy(
                        host: host, port: port, config: config,
                        level: level, studyUID: uid,
                        seriesUID: seriesUID, modality: modality,
                        seriesDate: seriesDate, instanceUID: instanceUID
                    )
                }
                submitted += 1
            }

            var uidIndex = maxConcurrent
            for try await results in group {
                collected.append(contentsOf: results)
                // Early exit for globally unique UIDs
                if hasUniqueMatch && !collected.isEmpty {
                    group.cancelAll()
                    break
                }
                // Submit next batch
                if uidIndex < studyUIDs.count {
                    let nextUID = studyUIDs[uidIndex]
                    group.addTask { [self] in
                        try await self.queryLevelForStudy(
                            host: host, port: port, config: config,
                            level: level, studyUID: nextUID,
                            seriesUID: seriesUID, modality: modality,
                            seriesDate: seriesDate, instanceUID: instanceUID
                        )
                    }
                    uidIndex += 1
                }
            }
            return collected
        }

        if hasUniqueMatch && !allResults.isEmpty {
            appendConsoleOutput("  Found match (searched \(studyUIDs.count) studies concurrently)\n\n")
        } else if hasUniqueMatch {
            appendConsoleOutput("  No match found across \(studyUIDs.count) studies\n\n")
        } else {
            appendConsoleOutput("\n")
        }

        return allResults
    }

    /// Queries a specific level within a single study.
    /// For IMAGE level without a Series UID, performs an intermediate series discovery.
    private func queryLevelForStudy(
        host: String, port: UInt16, config: QueryConfiguration,
        level: QueryLevel, studyUID: String,
        seriesUID: String, modality: String,
        seriesDate: String, instanceUID: String
    ) async throws -> [GenericQueryResult] {
        if level == .series {
            var subKeys = QueryKeys(level: .series)
                .studyInstanceUID(studyUID)
            if !seriesUID.isEmpty { subKeys = subKeys.seriesInstanceUID(seriesUID) }
            else { subKeys = subKeys.requestSeriesInstanceUID() }
            if !modality.isEmpty { subKeys = subKeys.modality(modality) }
            else { subKeys = subKeys.requestModality() }
            if !seriesDate.isEmpty { subKeys = subKeys.seriesDate(seriesDate) }
            subKeys = subKeys
                .requestSeriesNumber()
                .requestSeriesDescription()
                .requestNumberOfSeriesRelatedInstances()

            return try await DICOMQueryService.find(
                host: host, port: port,
                configuration: config,
                queryKeys: subKeys
            )
        }

        // IMAGE level — DCM4CHEE requires non-empty Series Instance UID
        if !seriesUID.isEmpty {
            // Series UID provided — direct image query
            var subKeys = QueryKeys(level: .image)
                .studyInstanceUID(studyUID)
                .seriesInstanceUID(seriesUID)
            if !instanceUID.isEmpty { subKeys = subKeys.sopInstanceUID(instanceUID) }
            else { subKeys = subKeys.requestSOPInstanceUID() }
            subKeys = subKeys
                .requestSOPClassUID()
                .requestInstanceNumber()
            return try await DICOMQueryService.find(
                host: host, port: port,
                configuration: config,
                queryKeys: subKeys
            )
        }

        // No Series UID — discover series first, then query images within each
        let seriesKeys = QueryKeys(level: .series)
            .studyInstanceUID(studyUID)
            .requestSeriesInstanceUID()
        let seriesResults = try await DICOMQueryService.find(
            host: host, port: port,
            configuration: config,
            queryKeys: seriesKeys
        )
        let discoveredSeriesUIDs = seriesResults.compactMap {
            $0.toSeriesResult().seriesInstanceUID
        }

        var imageResults: [GenericQueryResult] = []
        for sUID in discoveredSeriesUIDs {
            var subKeys = QueryKeys(level: .image)
                .studyInstanceUID(studyUID)
                .seriesInstanceUID(sUID)
            if !instanceUID.isEmpty { subKeys = subKeys.sopInstanceUID(instanceUID) }
            else { subKeys = subKeys.requestSOPInstanceUID() }
            subKeys = subKeys
                .requestSOPClassUID()
                .requestInstanceNumber()

            let results = try await DICOMQueryService.find(
                host: host, port: port,
                configuration: config,
                queryKeys: subKeys
            )
            imageResults.append(contentsOf: results)

            // Early exit when searching for a unique SOP Instance UID
            if !instanceUID.isEmpty && !imageResults.isEmpty {
                break
            }
        }
        return imageResults
    }

    // MARK: - C-STORE Execution (dicom-send)

    /// How a C-STORE response status is reported, per PS3.4 2026a Table B.2-1 — the
    /// same three classes as dicom-send's StoreOutcome: Success (0000) and the Warning
    /// class (B000 / B006 / B007) mean the SCP stored the SOP Instance; the Failure class
    /// (A7xx, A9xx, Cxxx, 0122) means it was not stored and counts as a failed transfer.
    enum WorkshopStoreOutcome: Equatable {
        case stored
        case storedWithWarning
        case failed

        init(status: DIMSEStatus) {
            if status.isSuccess {
                self = .stored
            } else if status.isWarning {
                self = .storedWithWarning
            } else {
                self = .failed
            }
        }
    }

    /// dicom-send's SendError.storeFailed text for a Failure-class C-STORE response.
    nonisolated static func sendStoreFailedText(_ status: DIMSEStatus) -> String {
        "C-STORE response status \(status) — not stored (PS3.4 Table B.2-1)"
    }

    /// dicom-send's SendError.partialFailure text (printed as `Error: …`, exit 1).
    nonisolated static func sendPartialFailureText(succeeded: Int, failed: Int) -> String {
        "Send completed with \(succeeded) succeeded and \(failed) failed"
    }

    /// Performs a real C-STORE to send DICOM files to the configured server.
    private func executeDicomSend() async {
        let hostValue = paramValue("host")
        let portValue = paramValue("port")
        let callingAET = paramValue("aet").isEmpty ? "DICOMSTUDIO" : paramValue("aet")
        let calledAET = paramValue("called-aet").isEmpty ? "ANY-SCP" : paramValue("called-aet")
        let timeoutStr = paramValue("timeout")
        let priorityStr = paramValue("priority").lowercased()
        let verifyFirst = paramValue("verify") == "true"
        let dryRun = paramValue("dry-run") == "true"
        let retryCount = Int(paramValue("retry")) ?? 0
        let verbose = paramValue("verbose") == "true"
        let transferSyntaxRaw = paramValue("transfer-syntax")

        /// Refuses the run with the CLI's `Error: …` line and exit code (64 = usage).
        func refuse(_ message: String, exitCode: Int) {
            appendConsoleOutput("Error: \(message)\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-send", command: commandPreview, exitCode: exitCode, output: message)
        }

        // Retry drives `0...retryCount`; a negative value would trap that range.
        guard retryCount >= 0 else {
            refuse("--retry must be zero or greater", exitCode: 64)
            return
        }

        // Priority (0000,0700), PS3.7 Table 9.3-1: low 0002H, medium 0000H, high 0001H.
        let priority: DIMSEPriority
        switch priorityStr {
        case "low": priority = .low
        case "high": priority = .high
        default: priority = .medium
        }

        guard let server = resolveHostPort(hostValue, explicitPort: portValue) else {
            refuse("A valid host is required (e.g. hostname or hostname:11112).", exitCode: 64)
            return
        }

        let host = server.host
        let port = server.port
        let timeout = TimeInterval(timeoutStr) ?? 60
        let recursive = paramValue("recursive") == "true"

        // --transfer-syntax via the SHARED DICOMCore parser (TransferSyntax.parse) — the
        // identical alias map the CLI resolves; an unknown name is a usage error (64).
        let preferredTransferSyntaxUID: String?
        if !transferSyntaxRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let syntax = TransferSyntax.parse(transferSyntaxRaw) else {
                refuse("Unknown transfer syntax: \(transferSyntaxRaw)", exitCode: 64)
                return
            }
            preferredTransferSyntaxUID = syntax.uid
        } else {
            preferredTransferSyntaxUID = nil
        }

        // ── Collect DICOM file paths ────────────────────────────────
        // Merge drag-and-drop entries with the text-field path, resolve
        // directories into individual DICOM files, and obtain
        // security-scoped access for sandboxed reads.

        let filesParamPath = paramValue("files").trimmingCharacters(in: .whitespaces)

        // Start security-scoped access for the entire collection phase
        let scopedURL = securityScopedURLs["files"]
        let accessing = scopedURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if accessing { scopedURL?.stopAccessingSecurityScopedResource() }
        }

        // Gather files via the SHARED DICOMSendFileGatherer (DICOMNetwork) — the EXACT
        // same enumeration the dicom-send CLI uses (Sources/dicom-send/DICOMSend.swift):
        // DICOM detection by extension OR "DICM" magic, glob expansion, directory
        // recursion, dotfile handling, and ordering. The files field may hold several
        // semicolon-separated paths (positional list — the preview expands the same
        // split into tokens); picked/dropped `inputFiles` are additive, deduplicated
        // against the typed paths so a file mirrored into the preview is not sent twice.
        var inputPaths = CommandBuilderHelpers.splitMultiValue(filesParamPath)
        for entry in inputFiles where !inputPaths.contains(entry.path) {
            inputPaths.append(entry.path)
        }
        // Surface the gatherer's warnings (e.g. "Path not found: …") under --verbose,
        // mirroring the CLI's `warn: verbose ? { fprintln("Warning: \($0)") } : nil`.
        var gatherWarnings: [String] = []
        let gatheredPaths = DICOMSendFileGatherer.gather(
            paths: inputPaths, recursive: recursive,
            warn: verbose ? { gatherWarnings.append($0) } : nil)
        for warning in gatherWarnings {
            appendConsoleOutput("Warning: \(warning)\n")
        }
        let fm = FileManager.default
        let fileEntries: [CLIFileEntry] = gatheredPaths.map { path in
            let size = ((try? fm.attributesOfItem(atPath: path))?[.size] as? Int64) ?? 0
            return CLIFileEntry(path: path, filename: (path as NSString).lastPathComponent, fileSize: size)
        }

        guard !fileEntries.isEmpty else {
            // dicom-send: ValidationError("No DICOM files found to send"), exit 64.
            refuse("No DICOM files found to send", exitCode: 64)
            return
        }

        // Header via the SHARED NetworkConsole formatter (DICOMNetwork) — identical to
        // the dicom-send CLI, which passes the resolved Transfer Syntax UID.
        appendConsoleOutput(NetworkConsole.sendHeader(
            host: host, port: port,
            callingAE: callingAET, calledAE: calledAET,
            priority: priorityStr, timeout: Int(timeout), fileCount: fileEntries.count,
            retryAttempts: retryCount, transferSyntax: preferredTransferSyntaxUID, dryRun: dryRun))

        if dryRun {
            for (index, file) in fileEntries.enumerated() {
                appendConsoleOutput(NetworkConsole.sendDryRunLine(
                    index: index + 1, total: fileEntries.count,
                    filename: file.filename, size: Int(file.fileSize)))
            }
            appendConsoleOutput("\nDry run complete. No files were sent.\n")
            consoleStatus = .success
            service.setConsoleStatus(.success)
            addToHistory(toolName: "dicom-send", command: commandPreview, exitCode: 0,
                         output: "Dry run: \(fileEntries.count) file(s)")
            return
        }

        // Verify connection first if requested (SendExecutor.verifyConnection: a
        // non-success C-ECHO status is a connectionFailed error; exit 1).
        if verifyFirst {
            appendConsoleOutput("Verifying connection with C-ECHO...\n")
            do {
                let echoResult = try await DICOMVerificationService.echo(
                    host: host, port: port,
                    callingAE: callingAET, calledAE: calledAET,
                    timeout: timeout
                )
                guard echoResult.success else {
                    throw DICOMNetworkError.connectionFailed(
                        "C-ECHO verification returned a non-success status: \(echoResult.status)")
                }
                appendConsoleOutput("  ✅ Connection verified\n\n")
            } catch {
                appendConsoleOutput("  ❌ C-ECHO failed — aborting send\n")
                refuse((error as? DICOMNetworkError)?.description ?? error.localizedDescription, exitCode: 1)
                return
            }
        }

        // Send each file — all progress/summary text via the SHARED NetworkConsole
        // formatter (DICOMNetwork) so it is byte-identical to the dicom-send CLI
        // (SendExecutor.sendFiles): the response status is classed per PS3.4 Table
        // B.2-1 — Success / Warning stored (the Warning class gets its
        // sendFileWarningLine and the summary Warnings count), Failure class not stored,
        // retried like a transport error and counted as failed.
        var successCount = 0
        var warningCount = 0
        var failureCount = 0
        var totalBytesTransferred = 0
        let startTime = Date()

        for (index, file) in fileEntries.enumerated() {
            let fileNumber = index + 1
            appendConsoleOutput(NetworkConsole.sendFilePrefix(
                index: fileNumber, total: fileEntries.count,
                filename: file.filename, size: Int(file.fileSize)))

            do {
                let fileData = try readFileData(at: file.path, parameterID: "files")
                var lastError: String?
                var stored: StoreResult?

                for _ in 0...retryCount {
                    do {
                        let result: StoreResult
                        if let preferredTransferSyntaxUID {
                            result = try await DICOMStorageService.store(
                                fileData: fileData,
                                preferredTransferSyntaxUID: preferredTransferSyntaxUID,
                                to: host, port: port,
                                callingAE: callingAET, calledAE: calledAET,
                                priority: priority, timeout: timeout)
                        } else {
                            result = try await DICOMStorageService.store(
                                fileData: fileData,
                                to: host, port: port,
                                callingAE: callingAET, calledAE: calledAET,
                                priority: priority, timeout: timeout)
                        }
                        // A Failure-class status (PS3.4 Table B.2-1) is not stored: the
                        // CLI throws SendError.storeFailed and retries (sendFileWithRetry).
                        if WorkshopStoreOutcome(status: result.status) == .failed {
                            lastError = Self.sendStoreFailedText(result.status)
                            continue
                        }
                        stored = result
                        break
                    } catch {
                        lastError = error.localizedDescription
                        // No per-attempt retry chatter: retries are non-deterministic and
                        // would diverge from the CLI run; only the outcome line is emitted.
                    }
                }

                if let result = stored {
                    successCount += 1
                    totalBytesTransferred += fileData.count
                    appendConsoleOutput(NetworkConsole.sendFileResultSuffix(
                        success: true, rtt: result.roundTripTime, error: nil))
                    if WorkshopStoreOutcome(status: result.status) == .storedWithWarning {
                        // PS3.4 Table B.2-1 Warning class: stored, but the SCP reports a
                        // deviation (coercion, discarded elements, SOP Class mismatch).
                        warningCount += 1
                        appendConsoleOutput(NetworkConsole.sendFileWarningLine(status: result.status))
                    }
                } else {
                    failureCount += 1
                    appendConsoleOutput(NetworkConsole.sendFileResultSuffix(
                        success: false, rtt: 0, error: lastError))
                }
            } catch {
                failureCount += 1
                appendConsoleOutput(NetworkConsole.sendFileResultSuffix(
                    success: false, rtt: 0, error: error.localizedDescription))
            }
        }

        appendConsoleOutput(NetworkConsole.sendSummary(
            total: fileEntries.count, succeeded: successCount, failed: failureCount,
            bytes: totalBytesTransferred, duration: Date().timeIntervalSince(startTime),
            warnings: warningCount))

        if failureCount == 0 {
            consoleStatus = .success
            service.setConsoleStatus(.success)
            addToHistory(toolName: "dicom-send", command: commandPreview, exitCode: 0,
                         output: "\(successCount)/\(fileEntries.count) files sent")
        } else {
            // SendError.partialFailure → `Error: …`, exit 1 (the CLI's exit rule).
            refuse(Self.sendPartialFailureText(succeeded: successCount, failed: failureCount), exitCode: 1)
        }
    }

    // MARK: - C-MOVE / C-GET Execution (dicom-retrieve)

    /// The `--priority` words of dicom-retrieve / dicom-qr → Priority (0000,0700) of the
    /// C-MOVE-RQ / C-GET-RQ (PS3.7 2026a Tables 9.3-9 / 9.3-6: LOW 0002H, MEDIUM 0000H,
    /// HIGH 0001H), as RetrievePriorityOption / QRPriorityOption map them.
    nonisolated static func retrievePriorityOption(_ raw: String) -> DIMSEPriority {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "low": return .low
        case "high": return .high
        default: return .medium
        }
    }

    /// dicom-retrieve's validateUIDOptions(): baseline (PS3.4 C.4.2.2.1 / C.4.3.2.1) needs a
    /// Unique Key for each level above the retrieve level; with --relational-retrieve
    /// (PS3.4 C.4.2.2.2.1 / C.4.3.2.2.1) the retrieve level's own UID is enough. Returns the
    /// CLI's ValidationError text (exit 64), or nil.
    nonisolated static func retrieveUIDRefusal(studyUID: String, seriesUID: String, instanceUID: String,
                                               uidList: String, relationalRetrieve: Bool) -> String? {
        let hasStudy = !studyUID.isEmpty, hasSeries = !seriesUID.isEmpty, hasInstance = !instanceUID.isEmpty
        guard hasStudy || !uidList.isEmpty || (relationalRetrieve && (hasSeries || hasInstance)) else {
            return relationalRetrieve
                ? "Must specify --study-uid, --series-uid, --instance-uid or --uid-list"
                : "Must specify either --study-uid or --uid-list"
        }
        if relationalRetrieve { return nil }
        if hasSeries && !hasStudy {
            return "--series-uid requires --study-uid (PS3.4 C.4.2.2.1), or --relational-retrieve"
        }
        if hasInstance && (!hasStudy || !hasSeries) {
            return "--instance-uid requires both --study-uid and --series-uid (PS3.4 C.4.2.2.1), or --relational-retrieve"
        }
        return nil
    }

    /// The Identifier dicom-retrieve builds (RetrieveExecutor.retrieveKeys): Query/Retrieve
    /// Level from the most specific UID given, and every UID given (PS3.4 C.4.2.2.1;
    /// relational-retrieve allows the above-level ones to be absent, C.4.2.2.2.1).
    nonisolated static func retrieveKeys(studyUID: String?, seriesUID: String?, sopUID: String?) -> RetrieveKeys {
        let level: QueryLevel = sopUID != nil ? .image : (seriesUID != nil ? .series : .study)
        var keys = RetrieveKeys(level: level)
        if let studyUID { keys = keys.studyInstanceUID(studyUID) }
        if let seriesUID { keys = keys.seriesInstanceUID(seriesUID) }
        if let sopUID { keys = keys.sopInstanceUID(sopUID) }
        return keys
    }

    /// dicom-retrieve's RetrieveExecutor.checkResult: the Failed SOP Instance UID List
    /// (0008,0058) lines, then — unless the result is a full success (status 0000 and no
    /// failed sub-operations, PS3.4 C.4.2.2.1 / C.4.3.2.1) — the "Final … response" line
    /// worded per PS3.4 2026a Table C.4-2 (C-MOVE) / C.4-3 (C-GET) via
    /// DIMSEServiceStatusText and the counters per PS3.7 Tables 9.3-10 / 9.3-7, plus the
    /// RetrieveError.retrievalFailed text the CLI exits 1 with.
    nonisolated static func retrieveCheck(_ result: RetrieveResult, service: DIMSEStatusService)
        -> (lines: [String], failure: String?) {
        var lines: [String] = []
        if !result.failedSOPInstanceUIDs.isEmpty {
            lines.append("Failed SOP Instance UID List (0008,0058), \(result.failedSOPInstanceUIDs.count) UID(s):")
            for uid in result.failedSOPInstanceUIDs { lines.append("  \(uid)") }
        }
        if result.isSuccess { return (lines, nil) }
        let described = DIMSEServiceStatusText.describe(result.status, service: service)
        let counts = DIMSEServiceStatusText.subOperationCounts(result.progress)
        lines.append("Final \(service.rawValue) response: " + described + " — " + counts)
        var text = "\(service.rawValue) final response " + described + " (" + counts + ")"
        if !result.failedSOPInstanceUIDs.isEmpty {
            text += "; Failed SOP Instance UID List (0008,0058): " + result.failedSOPInstanceUIDs.joined(separator: ", ")
        }
        return (lines, text)
    }

    /// dicom-qr's RetrieveExecutor.checkRetrieveResult: the stderr Failed SOP Instance UID
    /// List block and the DICOMQRError.retrievalFailed text ("Retrieval failed: …") for a
    /// final response that is not a full success.
    nonisolated static func qrRetrieveCheck(_ result: RetrieveResult, service: DIMSEStatusService)
        -> (lines: [String], failure: String?) {
        if result.isSuccess { return ([], nil) }
        let summary = "\(service.rawValue) final response "
            + DIMSEServiceStatusText.describe(result.status, service: service)
            + " (" + DIMSEServiceStatusText.subOperationCounts(result.progress) + ")"
        var lines: [String] = []
        if !result.failedSOPInstanceUIDs.isEmpty {
            lines.append("  Failed SOP Instance UID List (0008,0058):")
            for uid in result.failedSOPInstanceUIDs { lines.append("    \(uid)") }
        }
        var text = "Retrieval failed: \(summary)"
        if !result.failedSOPInstanceUIDs.isEmpty {
            text += "; Failed SOP Instance UID List (0008,0058): " + result.failedSOPInstanceUIDs.joined(separator: ", ")
        }
        return (lines, text)
    }

    /// Performs a C-MOVE or C-GET retrieval from the configured server — the in-app
    /// dicom-retrieve: the same RetrieveConfiguration (Study Root, Priority (0000,0700),
    /// optional relational-retrieval Extended Negotiation), the same RetrieveKeys, the
    /// shared NetworkConsole chrome and DIMSEServiceStatusText status wording.
    private func executeDicomRetrieve() async {
        let hostValue = paramValue("host")
        let portValue = paramValue("port")
        let callingAET = paramValue("aet").isEmpty ? "DICOMSTUDIO" : paramValue("aet")
        let calledAET = paramValue("called-aet").isEmpty ? "ANY-SCP" : paramValue("called-aet")
        let timeoutStr = paramValue("timeout")
        let methodStr = paramValue("method").lowercased()
        let moveDest = paramValue("move-dest")
        let studyUID = paramValue("study-uid")
        let seriesUID = paramValue("series-uid")
        let instanceUID = paramValue("instance-uid")
        let uidListPath = paramValue("uid-list")
        let outputDir = resolvedOutputDir(paramValue("output"))
        let hierarchical = paramValue("hierarchical") == "true"
        let verbose = paramValue("verbose") == "true"
        let priority = Self.retrievePriorityOption(paramValue("priority"))
        let relationalRetrieve = paramValue("relational-retrieve") == "true"
        let parallel = Int(paramValue("parallel")) ?? 1

        /// Refuses the run with the CLI's `Error: …` line and exit code (64 = usage).
        func refuse(_ message: String, exitCode: Int) {
            appendConsoleOutput("Error: \(message)\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-retrieve", command: commandPreview, exitCode: exitCode, output: message)
        }

        // Clear previous retrieval state
        lastRetrievedFiles.removeAll()
        lastRetrievedOutputURL = securityScopedURLs["output"]

        guard let server = resolveHostPort(hostValue, explicitPort: portValue) else {
            refuse("A valid host is required (e.g. hostname or hostname:11112).", exitCode: 64)
            return
        }

        let host = server.host
        let port = server.port
        let timeout = TimeInterval(timeoutStr) ?? 60

        // Transfer syntax via the SHARED DICOMCore parser — the IDENTICAL alias map the
        // dicom-retrieve CLI uses (TransferSyntax.parse); an unknown name is a usage error.
        let transferSyntaxRetrieve = paramValue("transfer-syntax")
        let preferredTSRetrieve: String?
        if !transferSyntaxRetrieve.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let parsedTS = TransferSyntax.parse(transferSyntaxRetrieve) else {
                refuse("Unknown transfer syntax: \(transferSyntaxRetrieve)", exitCode: 64)
                return
            }
            preferredTSRetrieve = parsedTS.uid
        } else {
            preferredTSRetrieve = nil
        }

        let isCMove = methodStr != "c-get"
        if isCMove && moveDest.isEmpty {
            refuse("C-MOVE requires --move-dest parameter", exitCode: 64)
            return
        }
        guard parallel >= 1 else {
            refuse("--parallel must be at least 1", exitCode: 64)
            return
        }
        // PS3.4 C.4.2.2.1 / C.4.3.2.1 (or C.4.2.2.2.1 with relational-retrieve): the UIDs
        // the retrieve level needs — dicom-retrieve's validateUIDOptions texts, exit 64.
        if let message = Self.retrieveUIDRefusal(studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID,
                                                 uidList: uidListPath, relationalRetrieve: relationalRetrieve) {
            refuse(message, exitCode: 64)
            return
        }

        // The engine configuration exactly as RetrieveExecutor.retrieveConfiguration():
        // Study Root, the requested Priority and, when asked, the relational-retrieval
        // SOP Class Extended Negotiation (PS3.4 C.5.2.1 / C.5.3.1, Table C.5-3 byte 1).
        let configuration: RetrieveConfiguration
        do {
            configuration = RetrieveConfiguration(
                callingAETitle: try AETitle(callingAET),
                calledAETitle: try AETitle(calledAET),
                timeout: timeout,
                informationModel: .studyRoot,
                priority: priority,
                extendedNegotiation: relationalRetrieve ? RetrieveExtendedNegotiation(relationalRetrieval: true) : nil)
        } catch {
            refuse((error as? DICOMNetworkError)?.description ?? error.localizedDescription, exitCode: 1)
            return
        }

        // ── Bulk retrieval from a UID list file (--uid-list, honoring --parallel) ──
        // Mirrors the CLI's bulk path (loadUIDList + RetrieveExecutor.retrieveBulk):
        // like the CLI, it skips the single-study header and reports the closing
        // "Bulk retrieval complete" tally.
        if !uidListPath.isEmpty {
            await executeDicomRetrieveBulk(
                uidListPath: uidListPath,
                host: host, port: port, configuration: configuration,
                isCMove: isCMove, moveDest: moveDest,
                preferredTransferSyntaxUID: preferredTSRetrieve,
                outputDir: outputDir, hierarchical: hierarchical,
                parallel: parallel, verbose: verbose
            )
            return
        }

        // Determine retrieval level (the most specific UID given)
        let levelLabel: String
        if !instanceUID.isEmpty { levelLabel = "Instance" }
        else if !seriesUID.isEmpty { levelLabel = "Series" }
        else { levelLabel = "Study" }

        // Header via the SHARED NetworkConsole formatter (DICOMNetwork) — identical to
        // the dicom-retrieve CLI: the Output line shows the raw `--output` value (what the
        // command preview passes), Priority only when not the MEDIUM default, the
        // relational-retrieval proposal when set, and the CLI's placeholder for a Study
        // UID that relational-retrieve leaves out.
        let rawOutput = paramValue("output").isEmpty ? "." : paramValue("output")
        appendConsoleOutput(NetworkConsole.retrieveHeader(
            method: isCMove ? "C-MOVE" : "C-GET",
            host: host, port: port,
            callingAE: callingAET, calledAE: calledAET,
            moveDestination: isCMove ? moveDest : nil,
            level: levelLabel,
            studyUID: studyUID.isEmpty ? "(not sent — relational-retrieve)" : studyUID,
            seriesUID: seriesUID.isEmpty ? nil : seriesUID,
            instanceUID: instanceUID.isEmpty ? nil : instanceUID,
            output: rawOutput, hierarchical: hierarchical, timeout: Int(timeout),
            transferSyntax: transferSyntaxRetrieve.isEmpty ? nil : transferSyntaxRetrieve,
            priority: priority == .medium ? nil : priority,
            relationalRetrieval: relationalRetrieve))

        appendConsoleOutput("Executing \(isCMove ? "C-MOVE" : "C-GET")...\n")

        let keys = Self.retrieveKeys(studyUID: studyUID.isEmpty ? nil : studyUID,
                                     seriesUID: seriesUID.isEmpty ? nil : seriesUID,
                                     sopUID: instanceUID.isEmpty ? nil : instanceUID)

        do {
            if isCMove {
                // Intermediate progress is suppressed (SCP pacing is not comparable);
                // only the deterministic final result is rendered.
                let result = try await DICOMRetrieveService.move(
                    host: host, port: port,
                    configuration: configuration,
                    keys: keys,
                    moveDestination: moveDest,
                    onProgress: { _ in })
                // C-MOVE result via the SHARED formatter, the status worded per PS3.4
                // 2026a Table C.4-2 (DIMSEServiceStatusText; Studio half of D76).
                appendConsoleOutput(NetworkConsole.cMoveResult(
                    status: DIMSEServiceStatusText.describe(result.status, service: .cMove),
                    completed: result.progress.completed,
                    failed: result.progress.failed,
                    warning: result.progress.warning,
                    isSuccess: result.isSuccess))
                let check = Self.retrieveCheck(result, service: .cMove)
                for line in check.lines { appendConsoleOutput(line + "\n") }
                if let failure = check.failure {
                    refuse(failure, exitCode: 1)
                    return
                }
            } else {
                // C-GET — the preferred TS is proposed for the C-STORE sub-operations.
                let stream = DICOMRetrieveService.get(
                    host: host, port: port,
                    configuration: configuration,
                    keys: keys,
                    preferredTransferSyntaxUID: preferredTSRetrieve)

                var receivedCount = 0
                var finalResult: RetrieveResult?
                for await event in stream {
                    switch event {
                    case .instance(let sopInstanceUID, let sopClassUID, let transferSyntaxUID, let data):
                        receivedCount += 1
                        // Save the received data (Part 10). Per-instance lines are NOT
                        // printed: the SCP's send order/timing is volatile across
                        // associations and would diverge from the CLI run.
                        let savedPath = try writeReceivedDICOMFile(
                            data: data,
                            sopInstanceUID: sopInstanceUID,
                            sopClassUID: sopClassUID,
                            transferSyntaxUID: transferSyntaxUID,
                            studyUID: studyUID.isEmpty
                                ? (Self.extractUID(element: 0x000D, fromDataSet: data, transferSyntaxUID: transferSyntaxUID) ?? "")
                                : studyUID,
                            seriesUID: seriesUID.isEmpty ? nil : seriesUID,
                            outputDir: outputDir,
                            hierarchical: hierarchical
                        )
                        lastRetrievedFiles.append(savedPath)
                    case .progress:
                        // Suppressed: progress cadence is SCP-dependent and differs run-to-run.
                        break
                    case .completed(let result):
                        finalResult = result
                    case .error(let error):
                        throw error
                    }
                }
                // C-GET summary via the SHARED formatter (handles the 0-instances case).
                appendConsoleOutput(NetworkConsole.cGetSummary(received: receivedCount))
                // PS3.4 C.4.3.2.1: same success rule as C-MOVE (Table C.4-3 wording).
                if let result = finalResult {
                    let check = Self.retrieveCheck(result, service: .cGet)
                    for line in check.lines { appendConsoleOutput(line + "\n") }
                    if let failure = check.failure {
                        refuse(failure, exitCode: 1)
                        return
                    }
                }
            }

            consoleStatus = .success
            service.setConsoleStatus(.success)
            addToHistory(toolName: "dicom-retrieve", command: commandPreview, exitCode: 0,
                         output: "Retrieve completed")
        } catch {
            refuse((error as? DICOMNetworkError)?.description ?? error.localizedDescription, exitCode: 1)
        }
    }

    /// Best-effort scan of a raw data set for a group 0020 UID — Study Instance UID
    /// (0020,000D) or Series Instance UID (0020,000E) — as dicom-retrieve's
    /// RetrieveExecutor.extractUID does for a relational retrieve that carries no study
    /// UID to file under. Explicit / Implicit VR Little Endian; nil when unsure.
    nonisolated static func extractUID(element target: UInt16, fromDataSet data: Data, transferSyntaxUID: String) -> String? {
        let bytes = [UInt8](data)
        let implicitVR = (transferSyntaxUID == "1.2.840.10008.1.2")
        let longFormVRs: Set<String> = ["OB", "OW", "OF", "OD", "OL", "SQ", "UT", "UN", "UC", "UR"]
        func u16(_ at: Int) -> UInt16? {
            guard at + 2 <= bytes.count else { return nil }
            return UInt16(bytes[at]) | (UInt16(bytes[at + 1]) << 8)
        }
        func u32(_ at: Int) -> UInt32? {
            guard at + 4 <= bytes.count else { return nil }
            return UInt32(bytes[at]) | (UInt32(bytes[at + 1]) << 8) | (UInt32(bytes[at + 2]) << 16) | (UInt32(bytes[at + 3]) << 24)
        }
        var offset = 0
        while offset + 8 <= bytes.count {
            guard let group = u16(offset), let element = u16(offset + 2) else { return nil }
            if group > 0x0020 || (group == 0x0020 && element > target) { return nil }
            let valueLength: Int
            let valueOffset: Int
            if implicitVR {
                guard let len = u32(offset + 4) else { return nil }
                valueLength = Int(len); valueOffset = offset + 8
            } else {
                let vr = String(decoding: bytes[offset + 4 ..< offset + 6], as: UTF8.self)
                if longFormVRs.contains(vr) {
                    guard let len = u32(offset + 8) else { return nil }
                    valueLength = Int(len); valueOffset = offset + 12
                } else {
                    guard let len = u16(offset + 6) else { return nil }
                    valueLength = Int(len); valueOffset = offset + 8
                }
            }
            if valueLength == 0xFFFF_FFFF { return nil }
            guard valueOffset + valueLength <= bytes.count else { return nil }
            if group == 0x0020 && element == target {
                let uid = String(decoding: bytes[valueOffset ..< valueOffset + valueLength], as: UTF8.self)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
                return uid.isEmpty ? nil : uid
            }
            offset = valueOffset + valueLength
        }
        return nil
    }

    /// Bulk study retrieval from a `--uid-list` file — the in-app equivalent of the
    /// CLI's `loadUIDList` + `RetrieveExecutor.retrieveBulk` (dicom-retrieve):
    /// newline-split UIDs (trimmed, empties and `#` comment lines dropped), study
    /// retrievals batched by `--parallel`, one C-MOVE/C-GET result block per study
    /// (status worded by DIMSEServiceStatusText), then the closing "Bulk retrieval
    /// complete" tally and the CLI's partialFailure error (exit 1).
    private func executeDicomRetrieveBulk(
        uidListPath: String,
        host: String, port: UInt16, configuration: RetrieveConfiguration,
        isCMove: Bool, moveDest: String,
        preferredTransferSyntaxUID: String?,
        outputDir: String, hierarchical: Bool,
        parallel: Int, verbose: Bool
    ) async {
        // Load UIDs with the CLI's exact convention (DICOMRetrieve.loadUIDList).
        let listScopedURL = securityScopedURLs["uid-list"]
        let accessingList = listScopedURL?.startAccessingSecurityScopedResource() ?? false
        defer { if accessingList { listScopedURL?.stopAccessingSecurityScopedResource() } }
        let listURL = listScopedURL ?? URL(fileURLWithPath: uidListPath)

        let uids: [String]
        do {
            let content = try String(contentsOf: listURL, encoding: .utf8)
            uids = content
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") } // Filter empty lines and comments
        } catch {
            appendConsoleOutput("Error: \(error.localizedDescription)\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-retrieve", command: commandPreview, exitCode: 1,
                         output: "Cannot read UID list: \(error.localizedDescription)")
            return
        }

        if verbose {
            appendConsoleOutput("Loaded \(uids.count) UIDs from \(uidListPath)\n\n")
            appendConsoleOutput("Bulk retrieving \(uids.count) studies with parallelism: \(parallel)\n")
        }

        /// Per-study outcome collected from the concurrent batch tasks.
        struct BulkStudyOutcome: Sendable {
            let index: Int
            let consoleText: String
            let savedPaths: [String]
            let success: Bool
            let errorText: String?
        }

        var successCount = 0
        var failureCount = 0

        // Process in batches based on parallelism (mirrors retrieveBulk's chunking).
        var start = 0
        while start < uids.count {
            if Task.isCancelled { break }
            let batch = Array(uids[start..<min(start + parallel, uids.count)])
            let batchStart = start
            start += parallel

            var outcomes: [BulkStudyOutcome] = []
            await withTaskGroup(of: BulkStudyOutcome.self) { group in
                for (offset, studyUID) in batch.enumerated() {
                    group.addTask {
                        do {
                            let keys = RetrieveKeys.forStudy(studyUID)
                            if isCMove {
                                let result = try await DICOMRetrieveService.move(
                                    host: host, port: port,
                                    configuration: configuration,
                                    keys: keys,
                                    moveDestination: moveDest,
                                    onProgress: { _ in })
                                var text = NetworkConsole.cMoveResult(
                                    status: DIMSEServiceStatusText.describe(result.status, service: .cMove),
                                    completed: result.progress.completed,
                                    failed: result.progress.failed,
                                    warning: result.progress.warning,
                                    isSuccess: result.isSuccess)
                                let check = Self.retrieveCheck(result, service: .cMove)
                                text += check.lines.map { $0 + "\n" }.joined()
                                return BulkStudyOutcome(
                                    index: batchStart + offset, consoleText: text,
                                    savedPaths: [], success: check.failure == nil, errorText: check.failure)
                            } else {
                                let stream = DICOMRetrieveService.get(
                                    host: host, port: port,
                                    configuration: configuration,
                                    keys: keys,
                                    preferredTransferSyntaxUID: preferredTransferSyntaxUID)
                                var savedPaths: [String] = []
                                var finalResult: RetrieveResult?
                                for await event in stream {
                                    switch event {
                                    case .instance(let sopInstanceUID, let sopClassUID, let transferSyntaxUID, let data):
                                        let savedPath = try await self.writeReceivedDICOMFile(
                                            data: data,
                                            sopInstanceUID: sopInstanceUID,
                                            sopClassUID: sopClassUID,
                                            transferSyntaxUID: transferSyntaxUID,
                                            studyUID: studyUID,
                                            outputDir: outputDir,
                                            hierarchical: hierarchical
                                        )
                                        savedPaths.append(savedPath)
                                    case .progress:
                                        break
                                    case .completed(let result):
                                        finalResult = result
                                    case .error(let error):
                                        throw error
                                    }
                                }
                                var text = NetworkConsole.cGetSummary(received: savedPaths.count)
                                var failure: String?
                                if let result = finalResult {
                                    let check = Self.retrieveCheck(result, service: .cGet)
                                    text += check.lines.map { $0 + "\n" }.joined()
                                    failure = check.failure
                                }
                                return BulkStudyOutcome(
                                    index: batchStart + offset, consoleText: text,
                                    savedPaths: savedPaths, success: failure == nil, errorText: failure)
                            }
                        } catch {
                            return BulkStudyOutcome(
                                index: batchStart + offset, consoleText: "",
                                savedPaths: [], success: false,
                                errorText: (error as? DICOMNetworkError)?.description ?? error.localizedDescription)
                        }
                    }
                }
                for await outcome in group {
                    outcomes.append(outcome)
                }
            }

            // Emit results deterministically in UID-list order.
            for outcome in outcomes.sorted(by: { $0.index < $1.index }) {
                if !outcome.consoleText.isEmpty {
                    appendConsoleOutput(outcome.consoleText)
                }
                if outcome.success {
                    successCount += 1
                } else {
                    failureCount += 1
                    if verbose, let errorText = outcome.errorText {
                        appendConsoleOutput("Failed to retrieve study: \(errorText)\n")
                    }
                }
                lastRetrievedFiles.append(contentsOf: outcome.savedPaths)
            }
        }

        appendConsoleOutput("\nBulk retrieval complete:\n")
        appendConsoleOutput("  Success: \(successCount)\n")
        appendConsoleOutput("  Failed: \(failureCount)\n")

        if failureCount > 0 {
            // Mirrors the CLI's RetrieveError.partialFailure exit (1).
            let message = "Bulk retrieval partially failed: \(successCount) succeeded, \(failureCount) failed"
            appendConsoleOutput("Error: \(message)\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-retrieve", command: commandPreview, exitCode: 1, output: message)
        } else {
            consoleStatus = .success
            service.setConsoleStatus(.success)
            addToHistory(toolName: "dicom-retrieve", command: commandPreview, exitCode: 0,
                         output: "Bulk retrieval complete: \(successCount) succeeded")
        }
    }

    // MARK: - Query-Retrieve Execution (dicom-qr)

    /// Performs an integrated C-FIND query followed by C-MOVE/C-GET retrieval — the in-app
    /// dicom-qr: keys through DICOMQueryService.buildQueryKeys (STUDY level), each
    /// retrieval through a RetrieveConfiguration carrying the Priority (0000,0700), up
    /// to --parallel studies at once with the CLI's line order, the final response
    /// checked per PS3.4 C.4.2.2.1 / C.4.3.2.1 with DIMSEServiceStatusText wording.
    private func executeDicomQR() async {
        let hostValue = paramValue("host")
        let portValue = paramValue("port")
        let callingAET = paramValue("aet").isEmpty ? "DICOMSTUDIO" : paramValue("aet")
        let calledAET = paramValue("called-aet").isEmpty ? "ANY-SCP" : paramValue("called-aet")
        let timeoutStr = paramValue("timeout")
        let modeStr = paramValue("mode").lowercased()
        let methodStr = paramValue("method").lowercased()
        let moveDest = paramValue("move-dest")
        let patientName = paramValue("patient-name")
        let patientID = paramValue("patient-id")
        let studyDate = paramValue("study-date")
        var modality = paramValue("modality")
        let strictModality = paramValue("strict-modality") == "true"
        let studyUID = paramValue("study-uid")
        let accession = paramValue("accession")
        let studyDesc = paramValue("study-description")
        let outputDir = resolvedOutputDir(paramValue("output"))
        let hierarchical = paramValue("hierarchical") == "true"
        let validate = paramValue("validate") == "true"
        let verbose = paramValue("verbose") == "true"
        let includeParentKeys = paramValue("include-parent-keys") == "true"
        let priority = Self.retrievePriorityOption(paramValue("priority"))
        let parallel = Int(paramValue("parallel")) ?? 1

        /// Refuses the run with the CLI's `Error: …` line and exit code (64 = usage).
        func refuse(_ message: String, exitCode: Int) {
            appendConsoleOutput("Error: \(message)\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-qr", command: commandPreview, exitCode: exitCode, output: message)
        }

        // Clear previous retrieval state
        lastRetrievedFiles.removeAll()
        lastRetrievedOutputURL = securityScopedURLs["output"]

        // --modality through the shared ModalityOptionValidator (PS3.3 C.7.3.1.1.1), as
        // the CLI's run() does first.
        let resolvedModality = Self.resolveModalityOption(modality, strict: strictModality, verbose: verbose)
        if let message = resolvedModality.error {
            refuse(message, exitCode: 1)
            return
        }
        modality = resolvedModality.value
        for line in resolvedModality.lines { appendConsoleOutput(line + "\n") }

        guard let server = resolveHostPort(hostValue, explicitPort: portValue) else {
            refuse("A valid host is required (e.g. hostname or hostname:11112).", exitCode: 64)
            return
        }

        let host = server.host
        let port = server.port
        let timeout = TimeInterval(timeoutStr) ?? 60

        // --parallel sizes the concurrent batches; 0 or less would never retrieve.
        guard parallel >= 1 else {
            refuse("--parallel must be at least 1", exitCode: 64)
            return
        }

        let isCMove: Bool
        switch methodStr {
        case "c-move", "":
            isCMove = true
            // The CLI requires --move-dest for c-move even in --review mode.
            guard !moveDest.isEmpty else {
                refuse("--move-dest is required for C-MOVE method", exitCode: 64)
                return
            }
        case "c-get":
            isCMove = false
        default:
            refuse("Invalid method: \(methodStr). Use c-move or c-get", exitCode: 64)
            return
        }
        let isReviewOnly = modeStr == "review"

        let modeLabel: String = {
            switch modeStr {
            case "auto", "automatic": return "Automatic"
            case "review": return "Review"
            // The app cannot prompt for a study selection, so the in-app
            // "interactive" state retrieves every match and previews as --auto —
            // the header reports Automatic to match the pasted command's output.
            default: return "Automatic"
            }
        }()

        // Transfer syntax via the SHARED DICOMCore parser (TransferSyntax.parse) —
        // the IDENTICAL alias map the CLI uses; an unrecognized name is a usage error.
        let transferSyntaxQR = paramValue("transfer-syntax")
        let preferredTSQR: String?
        if !transferSyntaxQR.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let parsedTS = TransferSyntax.parse(transferSyntaxQR) else {
                refuse("Unknown transfer syntax: \(transferSyntaxQR)", exitCode: 64)
                return
            }
            preferredTSQR = parsedTS.uid
        } else {
            preferredTSQR = nil
        }
        let rawOutputQR = paramValue("output").isEmpty ? "." : paramValue("output")
        // Header via the SHARED NetworkConsole formatter (DICOMNetwork) — identical to
        // the dicom-qr CLI. Filters use the same canonical order/labels as the CLI's
        // appliedFilters(); the Output line shows the raw `--output` value.
        var qrFilters: [(label: String, value: String)] = []
        func addQRFilter(_ label: String, _ value: String) {
            if !value.isEmpty { qrFilters.append((label, value)) }
        }
        addQRFilter("Patient Name:", patientName)
        addQRFilter("Patient ID:", patientID)
        addQRFilter("Study Date:", studyDate)
        addQRFilter("Modality:", modality)
        addQRFilter("Study UID:", studyUID)
        addQRFilter("Accession:", accession)
        addQRFilter("Study Desc:", studyDesc)
        appendConsoleOutput(NetworkConsole.qrHeader(
            host: host, port: port,
            callingAE: callingAET, calledAE: calledAET,
            mode: modeLabel,
            method: isCMove ? "C-MOVE" : "C-GET",
            isReview: isReviewOnly, moveDestination: moveDest,
            output: rawOutputQR, timeout: Int(timeout),
            transferSyntax: transferSyntaxQR.isEmpty ? nil : transferSyntaxQR,
            filters: qrFilters))

        do {
            // dicom-qr always queries at STUDY level, so every filter is a level-appropriate
            // key (PS3.4 C.4.1.2.1). Keys are built through the SHARED DICOMNetwork mapping
            // (DICOMQR.buildQueryKeys); the patient-name match key is upper-cased as before.
            let queryKeys = DICOMQueryService.buildQueryKeys(
                level: .study,
                patientName: patientName.uppercased(),
                patientID: patientID,
                studyDate: studyDate,
                modality: modality,
                accession: accession,
                studyDescription: studyDesc,
                studyUID: studyUID,
                includeParentLevelReturnKeys: includeParentKeys)

            let config = QueryConfiguration(
                callingAETitle: try AETitle(callingAET),
                calledAETitle: try AETitle(calledAET),
                timeout: timeout,
                informationModel: .studyRoot
            )

            let results = try await DICOMQueryService.find(
                host: host, port: port,
                configuration: config,
                queryKeys: queryKeys
            )

            if results.isEmpty {
                appendConsoleOutput(NetworkConsole.qrNoStudies())
                consoleStatus = .success
                service.setConsoleStatus(.success)
                addToHistory(toolName: "dicom-qr", command: commandPreview, exitCode: 0,
                             output: "0 studies found")
                return
            }

            appendConsoleOutput(NetworkConsole.qrFound(count: results.count))
            // Study list via the SHARED NetworkConsole formatter (DICOMNetwork).
            for (index, result) in results.enumerated() {
                let s = result.toStudyResult()
                appendConsoleOutput(NetworkConsole.qrStudyEntry(
                    index: index + 1,
                    patientName: s.patientName, patientID: s.patientID,
                    studyDescription: s.studyDescription, studyDate: s.studyDate,
                    modality: s.modalitiesInStudy, studyUID: s.studyInstanceUID))
            }

            // Review mode — done
            if isReviewOnly {
                appendConsoleOutput(NetworkConsole.qrReviewComplete(count: results.count))
                // --save-state: write the SHARED QRQueryState (DICOMNetwork) with
                // the CLI's exact bytes and follow-up lines, so the app-saved
                // state resumes via `dicom-qr resume` in the terminal.
                let saveStatePath = paramValue("save-state")
                if !saveStatePath.isEmpty {
                    do {
                        let data = try QRSessionState.encode(QRQueryState(results: results))
                        let res = try OutputAccess.write(data, toPath: saveStatePath,
                                                         scopedURL: securityScopedURLs["save-state"],
                                                         subfolder: "QRState")
                        if let note = res.note { appendConsoleOutput(note + "\n") }
                        appendConsoleOutput(NetworkConsole.qrStateSaved(path: res.url.path))
                    } catch {
                        appendConsoleOutput("Error: Could not save state: \(error.localizedDescription)\n")
                    }
                }
                consoleStatus = .success
                service.setConsoleStatus(.success)
                addToHistory(toolName: "dicom-qr", command: commandPreview, exitCode: 0,
                             output: "\(results.count) studies found (review only)")
                return
            }

            // Retrieve phase — all text via the SHARED NetworkConsole formatter so it is
            // byte-identical to the dicom-qr CLI. Per-instance/progress lines are NOT
            // printed (volatile order/timing); each study yields one ✅/❌ outcome line.
            let studiesToRetrieve = results

            // --save-state before retrieval (the CLI's exact behavior): a shared
            // QRRetrievalState that `dicom-qr resume` can continue from.
            let saveStatePath = paramValue("save-state")
            if !saveStatePath.isEmpty {
                do {
                    let state = QRRetrievalState(
                        studies: studiesToRetrieve.map(QRStudyInfo.init(from:)),
                        host: host, port: port,
                        callingAE: callingAET, calledAE: calledAET,
                        moveDestination: moveDest.isEmpty ? nil : moveDest,
                        method: isCMove ? .cMove : .cGet,
                        outputPath: rawOutputQR,
                        hierarchical: hierarchical)
                    let data = try QRSessionState.encode(state)
                    let res = try OutputAccess.write(data, toPath: saveStatePath,
                                                     scopedURL: securityScopedURLs["save-state"],
                                                     subfolder: "QRState")
                    if let note = res.note { appendConsoleOutput(note + "\n") }
                } catch {
                    appendConsoleOutput("Error: Could not save state: \(error.localizedDescription)\n")
                }
            }

            appendConsoleOutput(NetworkConsole.qrRetrieving(count: studiesToRetrieve.count))

            // Study Root configuration carrying the requested Priority (dicom-qr's
            // RetrieveExecutor.retrieveConfiguration; relational-retrieval is not offered
            // at STUDY level, PS3.4 C.4.2.2.1).
            let retrieveConfiguration = RetrieveConfiguration(
                callingAETitle: try AETitle(callingAET),
                calledAETitle: try AETitle(calledAET),
                timeout: timeout,
                informationModel: .studyRoot,
                priority: priority)

            var successCount = 0
            var failureCount = 0
            let total = studiesToRetrieve.count
            let numbered = Array(studiesToRetrieve.enumerated())

            // Each retrieval opens its own association, so up to --parallel of them run
            // at once; the per-study lines are printed in study order once a batch is
            // done (with --parallel 1 each line is printed before its retrieval starts).
            var batchStart = 0
            while batchStart < numbered.count {
                if Task.isCancelled { break }
                let batch = Array(numbered[batchStart ..< min(batchStart + parallel, numbered.count)])
                batchStart += parallel

                if parallel == 1, let (index, result) = batch.first {
                    let s = result.toStudyResult()
                    if let uid = s.studyInstanceUID {
                        appendConsoleOutput(NetworkConsole.qrRetrieveLine(
                            index: index + 1, total: total, patientName: s.patientName, studyUID: uid))
                    }
                    let outcome = await qrRetrieveStudy(result, host: host, port: port,
                                                        configuration: retrieveConfiguration,
                                                        isCMove: isCMove, moveDest: moveDest,
                                                        preferredTransferSyntaxUID: preferredTSQR,
                                                        outputDir: outputDir, hierarchical: hierarchical)
                    qrPrintOutcome(outcome, index: index, total: total, result: result, lineAlreadyPrinted: true)
                    if outcome.success { successCount += 1 } else { failureCount += 1 }
                    continue
                }
                var outcomes: [Int: QRStudyRetrieveOutcome] = [:]
                await withTaskGroup(of: (Int, QRStudyRetrieveOutcome).self) { group in
                    for (index, result) in batch {
                        group.addTask { [self] in
                            (index, await self.qrRetrieveStudy(result, host: host, port: port,
                                                               configuration: retrieveConfiguration,
                                                               isCMove: isCMove, moveDest: moveDest,
                                                               preferredTransferSyntaxUID: preferredTSQR,
                                                               outputDir: outputDir, hierarchical: hierarchical))
                        }
                    }
                    for await (index, outcome) in group { outcomes[index] = outcome }
                }
                for (index, result) in batch {
                    let outcome = outcomes[index] ?? QRStudyRetrieveOutcome(success: false, missingStudyUID: false,
                                                                            lines: [], error: "not run", savedPaths: [])
                    qrPrintOutcome(outcome, index: index, total: total, result: result, lineAlreadyPrinted: false)
                    if outcome.success { successCount += 1 } else { failureCount += 1 }
                }
            }

            appendConsoleOutput(NetworkConsole.qrSummary(
                total: studiesToRetrieve.count, success: successCount, failed: failureCount))

            // Post-retrieve validation pass — the SAME gate and console lines as
            // the dicom-qr CLI (`if validate && successCount > 0` →
            // validateRetrievedFiles).
            if validate && successCount > 0 {
                appendConsoleOutput(NetworkConsole.qrValidatingHeader())
                qrValidateRetrievedFiles(in: outputDir)
            }

            // A study whose final C-MOVE/C-GET response was not Success with no failed
            // sub-operations (PS3.4 C.4.2.2.1 / C.4.3.2.1), or that could not be
            // requested at all, must not leave the exit code at 0 (DICOMQRError.retrievalIncomplete).
            if failureCount > 0 {
                refuse("Retrieval incomplete: \(successCount) study(ies) succeeded, \(failureCount) failed", exitCode: 1)
                return
            }
            consoleStatus = .success
            service.setConsoleStatus(.success)
            addToHistory(toolName: "dicom-qr", command: commandPreview, exitCode: 0,
                         output: "\(successCount)/\(studiesToRetrieve.count) studies retrieved")
        } catch {
            refuse((error as? DICOMNetworkError)?.description ?? error.localizedDescription, exitCode: 1)
        }
    }

    /// One study's dicom-qr retrieval outcome (DICOMQR.Query.StudyRetrieveOutcome plus
    /// the console lines the CLI writes to stderr and the files written).
    struct QRStudyRetrieveOutcome: Sendable {
        let success: Bool
        let missingStudyUID: Bool
        let lines: [String]
        let error: String?
        let savedPaths: [String]
    }

    /// Retrieves one study the way dicom-qr's RetrieveExecutor.retrieveStudy does (silent:
    /// the caller renders the `[i/N] Retrieving…` line and the ✅/❌ outcome); never throws.
    private func qrRetrieveStudy(_ result: GenericQueryResult, host: String, port: UInt16,
                                 configuration: RetrieveConfiguration,
                                 isCMove: Bool, moveDest: String,
                                 preferredTransferSyntaxUID: String?,
                                 outputDir: String, hierarchical: Bool) async -> QRStudyRetrieveOutcome {
        guard let uid = result.toStudyResult().studyInstanceUID else {
            return QRStudyRetrieveOutcome(success: false, missingStudyUID: true, lines: [], error: nil, savedPaths: [])
        }
        do {
            let keys = RetrieveKeys.forStudy(uid)
            if isCMove {
                let moveResult = try await DICOMRetrieveService.move(
                    host: host, port: port, configuration: configuration,
                    keys: keys, moveDestination: moveDest, onProgress: { _ in })
                let check = Self.qrRetrieveCheck(moveResult, service: .cMove)
                return QRStudyRetrieveOutcome(success: check.failure == nil, missingStudyUID: false,
                                              lines: check.lines, error: check.failure, savedPaths: [])
            }
            let stream = DICOMRetrieveService.get(
                host: host, port: port, configuration: configuration,
                keys: keys, preferredTransferSyntaxUID: preferredTransferSyntaxUID)
            var savedPaths: [String] = []
            var finalResult: RetrieveResult?
            for await event in stream {
                switch event {
                case .instance(let sopInstanceUID, let sopClassUID, let transferSyntaxUID, let data):
                    let savedPath = try writeReceivedDICOMFile(
                        data: data,
                        sopInstanceUID: sopInstanceUID,
                        sopClassUID: sopClassUID,
                        transferSyntaxUID: transferSyntaxUID,
                        studyUID: uid,
                        outputDir: outputDir,
                        hierarchical: hierarchical
                    )
                    savedPaths.append(savedPath)
                case .progress:
                    break
                case .completed(let result):
                    finalResult = result
                case .error(let err):
                    throw err
                }
            }
            if let finalResult {
                let check = Self.qrRetrieveCheck(finalResult, service: .cGet)
                return QRStudyRetrieveOutcome(success: check.failure == nil, missingStudyUID: false,
                                              lines: check.lines, error: check.failure, savedPaths: savedPaths)
            }
            return QRStudyRetrieveOutcome(success: true, missingStudyUID: false, lines: [], error: nil, savedPaths: savedPaths)
        } catch {
            return QRStudyRetrieveOutcome(success: false, missingStudyUID: false, lines: [],
                                          error: (error as? DICOMNetworkError)?.description ?? error.localizedDescription,
                                          savedPaths: [])
        }
    }

    /// The per-study lines via the shared NetworkConsole formatter (DICOMQR.Query.printOutcome).
    private func qrPrintOutcome(_ outcome: QRStudyRetrieveOutcome, index: Int, total: Int,
                                result: GenericQueryResult, lineAlreadyPrinted: Bool) {
        let s = result.toStudyResult()
        if outcome.missingStudyUID {
            appendConsoleOutput(NetworkConsole.qrMissingStudyUID(index: index + 1, total: total))
            return
        }
        if !lineAlreadyPrinted, let uid = s.studyInstanceUID {
            appendConsoleOutput(NetworkConsole.qrRetrieveLine(
                index: index + 1, total: total, patientName: s.patientName, studyUID: uid))
        }
        for line in outcome.lines { appendConsoleOutput(line + "\n") }
        lastRetrievedFiles.append(contentsOf: outcome.savedPaths)
        if let error = outcome.error {
            appendConsoleOutput(NetworkConsole.qrRetrieveOutcome(success: false, error: error))
        } else {
            appendConsoleOutput(NetworkConsole.qrRetrieveOutcome(success: true, error: nil))
        }
    }

    /// Validates the retrieved files in the output directory — the SAME console
    /// lines as the dicom-qr CLI's `validateRetrievedFiles` (DICOMQR.swift), so
    /// terminal-compare stays clean: per-file "⚠️  Invalid file:" warnings plus
    /// the closing "Validation: N valid, M invalid" tally.
    private func qrValidateRetrievedFiles(in directory: String) {
        let fm = FileManager.default
        var dirURL = URL(fileURLWithPath: directory)
        var accessing = false
        if let scopedURL = securityScopedURLs["output"] {
            accessing = scopedURL.startAccessingSecurityScopedResource()
            dirURL = scopedURL
        }
        defer {
            if accessing { securityScopedURLs["output"]?.stopAccessingSecurityScopedResource() }
        }

        guard let enumerator = fm.enumerator(
            at: dirURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            appendConsoleOutput(NetworkConsole.qrValidateCannotEnumerate())
            return
        }

        var validCount = 0
        var invalidCount = 0

        for case let fileURL as URL in enumerator {
            let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues?.isRegularFile == true else { continue }

            // Skip non-DICOM files
            guard fileURL.pathExtension.lowercased() == "dcm" || fileURL.pathExtension.isEmpty else {
                continue
            }

            do {
                let data = try Data(contentsOf: fileURL)
                _ = try DICOMFile.read(from: data)
                validCount += 1
            } catch {
                invalidCount += 1
                appendConsoleOutput(NetworkConsole.qrValidateInvalidFile(name: fileURL.lastPathComponent))
            }
        }

        appendConsoleOutput(NetworkConsole.qrValidateSummary(valid: validCount, invalid: invalidCount))
    }

    // MARK: - MWL Execution (dicom-mwl)

    /// Performs a Modality Worklist C-FIND query.
    private func executeDicomMWL() async {
        let operation = paramValue("operation").isEmpty ? "query" : paramValue("operation")
        let hostValue = paramValue("host")
        let portValue = paramValue("port")
        let callingAET = paramValue("aet").isEmpty ? "DICOMSTUDIO" : paramValue("aet")
        let calledAET = paramValue("called-aet").isEmpty ? "ANY-SCP" : paramValue("called-aet")
        let timeoutStr = paramValue("timeout")

        guard let server = resolveHostPort(hostValue, explicitPort: portValue) else {
            appendConsoleOutput("Error: A valid host is required (e.g. hostname or hostname:11112).\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-mwl", command: commandPreview, exitCode: 1, output: "Invalid host")
            return
        }

        let host = server.host
        let port = server.port
        let timeout = TimeInterval(timeoutStr) ?? 60

        if operation == "create" {
            await executeDicomMWLCreate(
                host: host, port: port,
                callingAET: callingAET, calledAET: calledAET,
                timeout: timeout
            )
        } else {
            await executeDicomMWLQuery(
                host: host, port: port,
                callingAET: callingAET, calledAET: calledAET,
                timeout: timeout
            )
        }
    }

    // MARK: - MWL Query (C-FIND)

    /// Scheduled Procedure Step Status (0040,0020) Defined Terms, PS3.3 2026a Table C.4-10 —
    /// dicom-mwl's scheduledProcedureStepStatusDefinedTerms (CLI-local; text-identical).
    nonisolated static let mwlScheduledProcedureStepStatusDefinedTerms: [String] =
        ["SCHEDULED", "ARRIVED", "READY", "STARTED", "DEPARTED"]

    /// dicom-mwl's spsStatusWarning: the warning for a `--sps-status` value outside Table
    /// C.4-10 (almost always a Performed Procedure Step Status of Table C.4-14 typed by
    /// mistake, which matches nothing), or nil when the value is a Defined Term (or absent).
    nonisolated static func mwlSPSStatusWarning(_ value: String?) -> String? {
        guard let value, !value.isEmpty,
              !mwlScheduledProcedureStepStatusDefinedTerms.contains(value) else { return nil }
        return "warning: --sps-status '\(value)' is not a Scheduled Procedure Step Status Defined Term "
            + "(PS3.3 Table C.4-10: \(mwlScheduledProcedureStepStatusDefinedTerms.joined(separator: ", "))); "
            + "it is sent as given and will match only an SCP that uses that private term\n"
    }

    private func executeDicomMWLQuery(
        host: String, port: UInt16,
        callingAET: String, calledAET: String,
        timeout: TimeInterval
    ) async {
        // "Date" field (flag --date): a scheduled-date filter (single value or DICOM
        // range), matching the CLI. "Time" field (flag --time): scheduled-time filter.
        let date = paramValue("date-from")
        let time = paramValue("time-from")
        let station = paramValue("station")
        let patient = paramValue("patient")
        let patientID = paramValue("patient-id")
        var modality = paramValue("modality")
        let strictModality = paramValue("strict-modality") == "true"
        let spsStatus = paramValue("sps-status")
        let accession = paramValue("query-accession-number")
        let performingPhysician = paramValue("query-performing-physician")
        let specificCharacterSet = paramValue("specific-character-set")
        let verbose = paramValue("verbose") == "true"
        let jsonOutput = paramValue("json") == "true"

        /// Refuses the run with the CLI's `Error: …` line and exit code (64 = usage).
        func refuse(_ message: String, exitCode: Int) {
            appendConsoleOutput("Error: \(message)\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-mwl", command: commandPreview, exitCode: exitCode, output: message)
        }

        // --modality through the shared ModalityOptionValidator (PS3.3 C.7.3.1.1.1), as
        // the CLI's run() does first; then the Table C.4-10 warning for --sps-status.
        let resolved = Self.resolveModalityOption(modality, strict: strictModality, verbose: verbose)
        if let message = resolved.error {
            refuse(message, exitCode: 1)
            return
        }
        modality = resolved.value
        for line in resolved.lines { appendConsoleOutput(line + "\n") }
        if let warning = Self.mwlSPSStatusWarning(spsStatus) {
            appendConsoleOutput(warning)
        }

        // Header via the SHARED NetworkConsole formatter (DICOMNetwork) — the IDENTICAL
        // builder the dicom-mwl CLI uses, so the chrome can't drift. The filter list
        // uses the same canonical order/labels as the CLI's appliedFilters(). Gated on
        // --verbose (and suppressed in --json mode so the JSON array stays clean),
        // matching the CLI exactly.
        if verbose && !jsonOutput {
            var filters: [(label: String, value: String)] = []
            func addFilter(_ label: String, _ value: String) {
                if !value.isEmpty { filters.append((label, value)) }
            }
            addFilter("Date:", date)
            addFilter("Time:", time)
            addFilter("Station AET:", station)
            addFilter("Patient Name:", patient)
            addFilter("Patient ID:", patientID)
            addFilter("Modality:", modality)
            addFilter("SPS Status:", spsStatus)
            addFilter("Accession:", accession)
            addFilter("Performing Physician:", performingPhysician)
            appendConsoleOutput(NetworkConsole.mwlQueryHeader(
                host: host, port: port,
                callingAE: callingAET, calledAE: calledAET,
                timeout: Int(timeout), filters: filters))
        }

        // Build C-FIND keys via the SHARED package builder (DICOMNetwork) — the same
        // mapping the dicom-mwl CLI and the CLI-parity reference use, so the in-app
        // query and the CLI cannot drift. A single "Date" matches that exact day,
        // identical to `dicom-mwl query --date`. A bad date / time filter is the CLI's
        // ValidationError (exit 64).
        let queryKeys: WorklistQueryKeys
        do {
            queryKeys = try WorklistQueryKeys.forQuery(
                date: date,
                time: time,
                station: station,
                patientName: patient,
                patientID: patientID,
                modality: modality,
                spsStatus: spsStatus,
                accession: accession,
                performingPhysician: performingPhysician
            )
        } catch {
            refuse((error as? WorklistDateFilterError)?.description ?? "\(error)", exitCode: 64)
            return
        }

        do {
            // --specific-character-set forces Specific Character Set (0008,0005) of the
            // Identifier (PS3.4 Table K.6-1a; PS3.5 6.1.2), as the CLI passes it.
            let items = try await DICOMModalityWorklistService.find(
                host: host,
                port: port,
                callingAE: callingAET,
                calledAE: calledAET,
                matching: queryKeys,
                timeout: timeout,
                specificCharacterSet: specificCharacterSet.isEmpty ? nil : specificCharacterSet
            )

            // Render via the SHARED NetworkConsole formatter (DICOMNetwork) — the
            // IDENTICAL functions AND the SAME structure the dicom-mwl CLI uses: in
            // --json mode print ONLY the JSON array (no surrounding chrome, so the
            // first-'[' … last-']' contract holds); otherwise the formatted list. The
            // result-limit caution is text-mode-only so the JSON array stays clean.
            if jsonOutput {
                appendConsoleOutput(NetworkConsole.mwlJSON(items: items))
            } else if items.isEmpty {
                appendConsoleOutput(NetworkConsole.mwlNoResults())
            } else {
                appendConsoleOutput(NetworkConsole.mwlFound(count: items.count))
                for (index, item) in items.enumerated() {
                    appendConsoleOutput(NetworkConsole.mwlItem(index: index + 1, item: item, verbose: verbose))
                }
                appendConsoleOutput(NetworkConsole.mwlCompleted(count: items.count))
            }
            if !jsonOutput {
                appendConsoleOutput(NetworkConsole.mwlLimitWarning(count: items.count))
            }
            consoleStatus = .success
            service.setConsoleStatus(.success)
            addToHistory(toolName: "dicom-mwl", command: commandPreview, exitCode: 0,
                         output: items.isEmpty ? "0 worklist items found" : "\(items.count) worklist item(s) found")
        } catch {
            // ArgumentParser prints a thrown DICOMNetworkError as `Error: <description>`, exit 1.
            refuse((error as? DICOMNetworkError)?.description ?? error.localizedDescription, exitCode: 1)
        }
    }

    // MARK: - MWL Create (REST API)

    private func executeDicomMWLCreate(
        host: String, port: UInt16,
        callingAET: String, calledAET: String,
        timeout: TimeInterval
    ) async {
        let createMethod = paramValue("create-method").isEmpty ? "hl7" : paramValue("create-method")
        let patientName = paramValue("create-patient-name")
        let patientID = paramValue("create-patient-id")
        let patientDOB = paramValue("patient-dob")
        let patientSex = paramValue("patient-sex")
        let accessionNumber = paramValue("accession-number")
        let referringPhysician = paramValue("referring-physician")
        let procedureID = paramValue("procedure-id")
        let procedureDesc = paramValue("procedure-desc")
        let modality = paramValue("create-modality").isEmpty ? "CT" : paramValue("create-modality")
        let scheduledStation = paramValue("scheduled-station")
        let stationName = paramValue("station-name")
        let scheduledDate = paramValue("scheduled-date")
        let scheduledTime = paramValue("scheduled-time")
        let spsID = paramValue("sps-id")
        let spsDesc = paramValue("sps-desc")
        let performingPhysician = paramValue("performing-physician")

        guard !patientName.isEmpty else {
            appendConsoleOutput("Error: Patient Name is required for worklist creation.\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-mwl", command: commandPreview, exitCode: 1,
                         output: "Patient Name is required")
            return
        }
        guard !patientID.isEmpty else {
            appendConsoleOutput("Error: Patient ID is required for worklist creation.\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-mwl", command: commandPreview, exitCode: 1,
                         output: "Patient ID is required")
            return
        }

        // Resolve scheduled date
        let resolvedDate: String
        if scheduledDate.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            resolvedDate = formatter.string(from: Date())
        } else {
            resolvedDate = resolvedWorklistDate(scheduledDate)
        }

        if createMethod == "hl7" {
            await executeDicomMWLCreateHL7(
                host: host, timeout: timeout,
                patientName: patientName, patientID: patientID,
                patientDOB: patientDOB, patientSex: patientSex,
                accessionNumber: accessionNumber,
                referringPhysician: referringPhysician,
                procedureID: procedureID, procedureDesc: procedureDesc,
                modality: modality, scheduledStation: scheduledStation,
                stationName: stationName, resolvedDate: resolvedDate,
                scheduledTime: scheduledTime, spsID: spsID,
                spsDesc: spsDesc, performingPhysician: performingPhysician
            )
        } else {
            await executeDicomMWLCreateREST(
                host: host, port: port,
                callingAET: callingAET, calledAET: calledAET,
                timeout: timeout,
                patientName: patientName, patientID: patientID,
                patientDOB: patientDOB, patientSex: patientSex,
                accessionNumber: accessionNumber,
                referringPhysician: referringPhysician,
                procedureID: procedureID, procedureDesc: procedureDesc,
                modality: modality, scheduledStation: scheduledStation,
                stationName: stationName, resolvedDate: resolvedDate,
                scheduledTime: scheduledTime, spsID: spsID,
                spsDesc: spsDesc, performingPhysician: performingPhysician
            )
        }
    }

    // MARK: - MWL Create via HL7 ORM^O01 (MLLP)

    private func executeDicomMWLCreateHL7(
        host: String, timeout: TimeInterval,
        patientName: String, patientID: String,
        patientDOB: String, patientSex: String,
        accessionNumber: String, referringPhysician: String,
        procedureID: String, procedureDesc: String,
        modality: String, scheduledStation: String,
        stationName: String, resolvedDate: String,
        scheduledTime: String, spsID: String,
        spsDesc: String, performingPhysician: String
    ) async {
        let hl7PortStr = paramValue("hl7-port")
        let hl7Port = UInt16(hl7PortStr) ?? 2575
        let sendingApp = paramValue("sending-application").isEmpty ? "DICOMSTUDIO" : paramValue("sending-application")
        let sendingFacility = paramValue("sending-facility").isEmpty ? "IMAGING" : paramValue("sending-facility")
        let receivingApp = paramValue("receiving-application").isEmpty ? "DCM4CHEE" : paramValue("receiving-application")
        let receivingFacility = paramValue("receiving-facility").isEmpty ? "HOSPITAL" : paramValue("receiving-facility")

        appendConsoleOutput("DICOM Modality Worklist (HL7 ORM^O01 via MLLP)\n")
        appendConsoleOutput("================================================\n")
        appendConsoleOutput("  HL7 Server:       \(host):\(hl7Port)\n")
        appendConsoleOutput("  Sending App:      \(sendingApp) | \(sendingFacility)\n")
        appendConsoleOutput("  Receiving App:    \(receivingApp) | \(receivingFacility)\n")
        appendConsoleOutput("  Timeout:          \(Int(timeout))s\n")
        // Scheduled-item details via the shared NetworkConsole builder (also used
        // by the REST branch, so the two flows cannot drift).
        appendConsoleOutput(NetworkConsole.mwlCreateDetailBlock(
            patientName: patientName, patientID: patientID,
            patientDOB: patientDOB, patientSex: patientSex,
            accessionNumber: accessionNumber, referringPhysician: referringPhysician,
            modality: modality, scheduledDate: resolvedDate, scheduledTime: scheduledTime,
            stationAET: scheduledStation, stationName: stationName,
            spsID: spsID, spsDescription: spsDesc,
            procedureID: procedureID, procedureDescription: procedureDesc,
            performingPhysician: performingPhysician))
        appendConsoleOutput("\nSending HL7 ORM^O01 order message via MLLP...\n\n")

        do {
            let messageControlID = try await DICOMModalityWorklistService.createViaHL7(
                host: host,
                hl7Port: hl7Port,
                sendingApplication: sendingApp,
                sendingFacility: sendingFacility,
                receivingApplication: receivingApp,
                receivingFacility: receivingFacility,
                patientName: patientName,
                patientID: patientID,
                patientBirthDate: patientDOB.isEmpty ? nil : patientDOB,
                patientSex: patientSex.isEmpty ? nil : patientSex,
                accessionNumber: accessionNumber.isEmpty ? nil : accessionNumber,
                referringPhysicianName: referringPhysician.isEmpty ? nil : referringPhysician,
                requestedProcedureID: procedureID.isEmpty ? nil : procedureID,
                requestedProcedureDescription: procedureDesc.isEmpty ? nil : procedureDesc,
                modality: modality.isEmpty ? nil : modality,
                scheduledStationAETitle: scheduledStation.isEmpty ? nil : scheduledStation,
                scheduledStationName: stationName.isEmpty ? nil : stationName,
                scheduledStartDate: resolvedDate,
                scheduledStartTime: scheduledTime.isEmpty ? nil : scheduledTime,
                scheduledProcedureStepID: spsID.isEmpty ? nil : spsID,
                scheduledProcedureStepDescription: spsDesc.isEmpty ? nil : spsDesc,
                scheduledPerformingPhysicianName: performingPhysician.isEmpty ? nil : performingPhysician,
                timeout: timeout
            )

            appendConsoleOutput("✅ HL7 ORM^O01 accepted by server (ACK: AA)\n")
            appendConsoleOutput("  Message Control ID: \(messageControlID)\n")
            appendConsoleOutput("  Patient and worklist item created automatically.\n")
            consoleStatus = .success
            service.setConsoleStatus(.success)
            addToHistory(toolName: "dicom-mwl", command: commandPreview, exitCode: 0,
                         output: "HL7 ORM sent: \(messageControlID)")
        } catch {
            let errorDesc = (error as? DICOMNetworkError)?.description ?? error.localizedDescription
            appendConsoleOutput("❌ HL7 ORM^O01 failed: \(errorDesc)\n")
            appendConsoleOutput("  💡 Hints:\n")
            appendConsoleOutput("     • Ensure the HL7 MLLP listener is running on \(host):\(hl7Port)\n")
            appendConsoleOutput("     • dcm4chee-arc default HL7 port is 2575 (check hl7-connection in UI config)\n")
            appendConsoleOutput("     • Verify Sending/Receiving Application names match the server config\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-mwl", command: commandPreview, exitCode: 1,
                         output: errorDesc)
        }
    }

    // MARK: - MWL Create via REST API

    private func executeDicomMWLCreateREST(
        host: String, port: UInt16,
        callingAET: String, calledAET: String,
        timeout: TimeInterval,
        patientName: String, patientID: String,
        patientDOB: String, patientSex: String,
        accessionNumber: String, referringPhysician: String,
        procedureID: String, procedureDesc: String,
        modality: String, scheduledStation: String,
        stationName: String, resolvedDate: String,
        scheduledTime: String, spsID: String,
        spsDesc: String, performingPhysician: String
    ) async {
        let restBaseURLRaw = paramValue("rest-base-url")

        // Construct REST base URL (default: dcm4chee-arc pattern)
        let restBaseURL: String? = restBaseURLRaw.isEmpty ? nil : restBaseURLRaw
        let displayURL = restBaseURL ?? "http://\(host):8080/dcm4chee-arc"

        appendConsoleOutput("DICOM Modality Worklist (REST API)\n")
        appendConsoleOutput("===================================\n")
        appendConsoleOutput("  REST Endpoint:    \(displayURL)/aets/\(calledAET)/rs/mwlitems\n")
        appendConsoleOutput("  Timeout:          \(Int(timeout))s\n")
        // Scheduled-item details via the shared NetworkConsole builder (also used
        // by the HL7 branch, so the two flows cannot drift).
        appendConsoleOutput(NetworkConsole.mwlCreateDetailBlock(
            patientName: patientName, patientID: patientID,
            patientDOB: patientDOB, patientSex: patientSex,
            accessionNumber: accessionNumber, referringPhysician: referringPhysician,
            modality: modality, scheduledDate: resolvedDate, scheduledTime: scheduledTime,
            stationAET: scheduledStation, stationName: stationName,
            spsID: spsID, spsDescription: spsDesc,
            procedureID: procedureID, procedureDescription: procedureDesc,
            performingPhysician: performingPhysician))
        appendConsoleOutput("\nCreating Modality Worklist item via REST...\n\n")

        do {
            let sopInstanceUID = try await DICOMModalityWorklistService.create(
                host: host,
                port: port,
                callingAE: callingAET,
                calledAE: calledAET,
                patientName: patientName,
                patientID: patientID,
                patientBirthDate: patientDOB.isEmpty ? nil : patientDOB,
                patientSex: patientSex.isEmpty ? nil : patientSex,
                accessionNumber: accessionNumber.isEmpty ? nil : accessionNumber,
                referringPhysicianName: referringPhysician.isEmpty ? nil : referringPhysician,
                requestedProcedureID: procedureID.isEmpty ? nil : procedureID,
                requestedProcedureDescription: procedureDesc.isEmpty ? nil : procedureDesc,
                modality: modality.isEmpty ? nil : modality,
                scheduledStationAETitle: scheduledStation.isEmpty ? nil : scheduledStation,
                scheduledStationName: stationName.isEmpty ? nil : stationName,
                scheduledStartDate: resolvedDate,
                scheduledStartTime: scheduledTime.isEmpty ? nil : scheduledTime,
                scheduledProcedureStepID: spsID.isEmpty ? nil : spsID,
                scheduledProcedureStepDescription: spsDesc.isEmpty ? nil : spsDesc,
                scheduledPerformingPhysicianName: performingPhysician.isEmpty ? nil : performingPhysician,
                restBaseURL: restBaseURL,
                timeout: timeout
            )

            appendConsoleOutput("✅ Worklist item created successfully\n")
            appendConsoleOutput("  SOP Instance UID: \(sopInstanceUID)\n")
            consoleStatus = .success
            service.setConsoleStatus(.success)
            addToHistory(toolName: "dicom-mwl", command: commandPreview, exitCode: 0,
                         output: "Worklist item created: \(sopInstanceUID)")
        } catch {
            let errorDesc = (error as? DICOMNetworkError)?.description ?? error.localizedDescription
            appendConsoleOutput("❌ Worklist create failed: \(errorDesc)\n")
            appendConsoleOutput("  💡 Hint: REST requires the patient to exist first on the server.\n")
            appendConsoleOutput("     Consider using \"HL7\" create method instead — it auto-creates patient + worklist.\n")
            appendConsoleOutput("     Default endpoint: http://<host>:8080/dcm4chee-arc/aets/<AET>/rs/mwlitems\n")
            appendConsoleOutput("     Set \"REST Base URL\" if your server uses a different URL.\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-mwl", command: commandPreview, exitCode: 1,
                         output: errorDesc)
        }
    }

    /// Resolves a date filter string for MWL queries.
    /// Accepts "today", "tomorrow", or YYYYMMDD format.
    private func resolvedWorklistDate(_ filter: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        switch filter.lowercased() {
        case "today":
            return formatter.string(from: Date())
        case "tomorrow":
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            return formatter.string(from: tomorrow)
        default:
            return filter
        }
    }

    // MARK: - MPPS Execution (dicom-mpps)

    /// dicom-mpps' parseStatus words: IN PROGRESS (space optional or `_`), COMPLETED,
    /// DISCONTINUED (PS3.3 Table C.4-14 Enumerated Values), case-insensitive; nil otherwise.
    nonisolated static func mppsStatusOption(_ raw: String) -> DICOMNetwork.MPPSStatus? {
        switch raw.uppercased().replacingOccurrences(of: " ", with: "") {
        case "INPROGRESS", "IN_PROGRESS": return .inProgress
        case "COMPLETED": return .completed
        case "DISCONTINUED": return .discontinued
        default: return nil
        }
    }

    /// Patient's Sex (0010,0040) Enumerated Values, PS3.3 2026a Table C.2-3: M, F, O
    /// (dicom-mpps validatePatientSex; case-insensitive input is upper-cased).
    nonisolated static func mppsPatientSex(_ value: String) -> (value: String?, error: String?) {
        guard !value.isEmpty else { return (nil, nil) }
        let upper = value.trimmingCharacters(in: .whitespaces).uppercased()
        guard ["M", "F", "O"].contains(upper) else {
            return (nil, "--patient-sex must be one of M, F, O (Patient's Sex (0010,0040) Enumerated Values, PS3.3 Table C.2-3), got '\(value)'")
        }
        return (upper, nil)
    }

    /// `--patient-birth-date` is a DA value YYYYMMDD (PS3.5 Table 6.2-1: 8 bytes fixed,
    /// digits only) — dicom-mpps validateBirthDate.
    nonisolated static func mppsBirthDate(_ value: String) -> (value: String?, error: String?) {
        guard !value.isEmpty else { return (nil, nil) }
        guard value.count == 8, value.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return (nil, "--patient-birth-date must be YYYYMMDD (VR DA, PS3.5 Table 6.2-1), got '\(value)'")
        }
        return (value, nil)
    }

    /// dicom-mpps' reportWarning line: the SCP performed the operation but coerced or
    /// dropped attributes (PS3.7 Annex C); the status worded per PS3.4 Table F.7.2-2 for an
    /// N-SET, else PS3.7 Annex C (MPPS N-CREATE has no specific codes, PS3.4 F.7.2.1.4).
    nonisolated static func mppsWarningLine(_ warning: DIMSEStatus, operation: String) -> String {
        let described = DIMSEServiceStatusText.describe(warning, service: operation == "N-SET" ? .mppsNSet : .dimseN)
        return "warning: SCP completed the \(operation) with \(described) — attributes may have been coerced or dropped\n"
    }

    /// Performs an MPPS N-CREATE or N-SET operation — the in-app dicom-mpps.
    private func executeDicomMPPS() async {
        let hostValue = paramValue("host")
        let portValue = paramValue("port")
        let callingAET = paramValue("aet").isEmpty ? "DICOMSTUDIO" : paramValue("aet")
        let calledAET = paramValue("called-aet").isEmpty ? "ANY-SCP" : paramValue("called-aet")
        let timeoutStr = paramValue("timeout")
        let operation = paramValue("operation").lowercased()
        let studyUID = paramValue("study-uid")
        let mppsUID = paramValue("mpps-uid")
        // Status is split per operation: create offers only IN PROGRESS ("status"),
        // update offers COMPLETED / DISCONTINUED ("status-update").
        let statusStr = (operation != "update") ? paramValue("status") : paramValue("status-update")
        // N-CREATE attributes
        let patientName = paramValue("patient-name")
        let patientID = paramValue("patient-id")
        let spsID = paramValue("sps-id")
        let accessionNumber = paramValue("accession-number")
        var modality = paramValue("modality")
        let strictModality = paramValue("strict-modality") == "true"
        let patientBirthDateRaw = paramValue("patient-birth-date")
        let patientSexRaw = paramValue("patient-sex")
        let studyID = paramValue("study-id")
        let stationName = paramValue("station-name")
        let performedLocation = paramValue("performed-location")
        let procedureStepID = paramValue("procedure-step-id")
        let procedureStepDescription = paramValue("procedure-step-description")
        let createPerformingPhysician = paramValue("create-performing-physician")
        let requestedProcedureID = paramValue("requested-procedure-id")
        let requestedProcedureDescription = paramValue("requested-procedure-description")
        let spsDescription = paramValue("sps-description")
        let referencedStudyUID = paramValue("referenced-study-uid")
        // N-SET attributes
        let seriesUID = paramValue("series-uid")
        let imageUIDsRaw = paramValue("image-uid")
        let sopClassUID = paramValue("sop-class-uid")
        let protocolName = paramValue("protocol-name")
        let seriesDescription = paramValue("series-description")
        let operatorName = paramValue("operator-name")
        let updatePerformingPhysician = paramValue("update-performing-physician")
        let discontinuationReasonRaw = paramValue("discontinuation-reason")
        let legacyNSetScheduledAttributes = paramValue("legacy-nset-scheduled-attributes") == "true"
        // Shared
        let specificCharacterSet = paramValue("specific-character-set")
        let verbose = paramValue("verbose") == "true"

        /// Nil for an empty field so a blank Workshop input never overrides a
        /// library default (e.g. Protocol Name's "UNSPECIFIED").
        func optional(_ value: String) -> String? { value.isEmpty ? nil : value }

        /// Refuses the run with the CLI's `Error: …` line and exit code (64 = usage).
        func refuse(_ message: String, exitCode: Int) {
            appendConsoleOutput("Error: \(message)\n")
            consoleStatus = .error
            service.setConsoleStatus(.error)
            addToHistory(toolName: "dicom-mpps", command: commandPreview, exitCode: exitCode, output: message)
        }

        let isCreate = operation != "update"

        // --modality through the shared ModalityOptionValidator, then the Type 1 rule:
        // Modality (0008,0060) is Type 1 in the N-CREATE (PS3.4 Table F.7.2-1); without it
        // the data set would carry an empty Type 1 attribute (exit 64, as the CLI).
        if isCreate {
            let resolved = Self.resolveModalityOption(modality, strict: strictModality, verbose: verbose)
            if let message = resolved.error {
                refuse(message, exitCode: 1)
                return
            }
            modality = resolved.value
            for line in resolved.lines { appendConsoleOutput(line + "\n") }
            guard !modality.isEmpty else {
                refuse("--modality is required: Modality (0008,0060) is Type 1 in the MPPS N-CREATE (PS3.4 Table F.7.2-1)", exitCode: 64)
                return
            }
        }
        let patientSex = Self.mppsPatientSex(isCreate ? patientSexRaw : "")
        if let message = patientSex.error {
            refuse(message, exitCode: 64)
            return
        }
        let patientBirthDate = Self.mppsBirthDate(isCreate ? patientBirthDateRaw : "")
        if let message = patientBirthDate.error {
            refuse(message, exitCode: 64)
            return
        }

        guard let server = resolveHostPort(hostValue, explicitPort: portValue) else {
            refuse("A valid host is required (e.g. hostname or hostname:11112).", exitCode: 64)
            return
        }

        let host = server.host
        let port = server.port
        let timeout = TimeInterval(timeoutStr) ?? 60

        if isCreate && studyUID.isEmpty {
            // ArgumentParser's own message for the create subcommand's required option.
            refuse("Missing expected argument '--study-uid <study-uid>'", exitCode: 64)
            return
        }

        if !isCreate && mppsUID.isEmpty {
            refuse("Missing expected argument '--mpps-uid <mpps-uid>'", exitCode: 64)
            return
        }

        // Performed Procedure Step Status (0040,0252), PS3.3 Table C.4-14; the N-CREATE
        // starts the step IN PROGRESS (PS3.4 F.7.2.1.2), the N-SET ends it COMPLETED or
        // DISCONTINUED (F.7.2.2.2) — dicom-mpps' parseStatus and status guards (exit 64).
        guard let mppsStatus = Self.mppsStatusOption(statusStr.isEmpty ? (isCreate ? "IN PROGRESS" : "") : statusStr) else {
            refuse("Invalid status. Use 'IN PROGRESS', 'COMPLETED', or 'DISCONTINUED'", exitCode: 64)
            return
        }
        if isCreate, mppsStatus != .inProgress {
            refuse("Create status must be IN PROGRESS — use 'dicom-mpps update --status COMPLETED|DISCONTINUED' to transition the step", exitCode: 64)
            return
        }
        if !isCreate, mppsStatus != .completed, mppsStatus != .discontinued {
            refuse("Update status must be COMPLETED or DISCONTINUED", exitCode: 64)
            return
        }

        // Discontinuation reason: parsed through the SHARED MPPSCodedEntry grammar
        // (DICOMNetwork) before any connection, so a malformed code fails the same
        // way — and with the same message — as the CLI's --discontinuation-reason.
        var discontinuationReason: MPPSCodedEntry?
        if !isCreate, !discontinuationReasonRaw.isEmpty {
            guard mppsStatus == .discontinued else {
                refuse("--discontinuation-reason is only valid with --status DISCONTINUED", exitCode: 64)
                return
            }
            guard let parsed = MPPSCodedEntry.parse(discontinuationReasonRaw) else {
                refuse(MPPSCodedEntry.parseErrorMessage(option: "--discontinuation-reason"), exitCode: 64)
                return
            }
            discontinuationReason = parsed
        }

        // Image references are only encoded inside a Performed Series item, which needs
        // the Study and Series Instance UIDs (PS3.4 Table F.7.2-1) — the CLI's guard.
        let imageUIDs = isCreate ? [] : CommandBuilderHelpers.splitMultiValue(imageUIDsRaw).filter { !$0.isEmpty }
        if !isCreate, !imageUIDs.isEmpty, studyUID.isEmpty || seriesUID.isEmpty {
            refuse("--image-uid needs --study-uid and --series-uid: Referenced Image Sequence (0008,1140) items live in a Performed Series Sequence (0040,0340) item with its Series Instance UID (0020,000E) (PS3.4 Table F.7.2-1)", exitCode: 64)
            return
        }
        if !isCreate, !imageUIDs.isEmpty, sopClassUID.isEmpty {
            appendConsoleOutput("warning: --sop-class-uid not given; Referenced SOP Class UID defaults to Secondary Capture (1.2.840.10008.5.1.4.1.1.7), which is non-conformant for CT/MR/… images\n")
        }

        // Header via the SHARED NetworkConsole formatter (DICOMNetwork) — the IDENTICAL
        // builder and the SAME field list the dicom-mpps CLI passes. Gated on --verbose.
        if verbose {
            var headerFields: [(label: String, value: String)] = []
            func addHeaderField(_ label: String, _ value: String) {
                if !value.isEmpty { headerFields.append((label, value)) }
            }
            if isCreate {
                addHeaderField("Study UID:", studyUID)
                addHeaderField("Patient Name:", patientName)
                addHeaderField("Patient ID:", patientID)
                addHeaderField("SPS ID:", spsID)
                addHeaderField("Accession Number:", accessionNumber)
            } else {
                addHeaderField("MPPS UID:", mppsUID)
                // Same gate as the CLI's verbose header: the Referenced Images row
                // appears only when both --study-uid and --series-uid are given.
                if !studyUID.isEmpty && !seriesUID.isEmpty {
                    addHeaderField("Referenced Images:", "\(imageUIDs.count) instance(s)")
                }
            }
            appendConsoleOutput(NetworkConsole.mppsHeader(
                isCreate: isCreate,
                host: host, port: port,
                callingAE: callingAET, calledAE: calledAET,
                status: mppsStatus.rawValue, timeout: Int(timeout),
                fields: headerFields))
        }

        do {
            if isCreate {
                appendConsoleOutput(NetworkConsole.mppsProgress(isCreate: true))
                // createDetailed (not create) so the SCP's warning status and any
                // reassigned SOP Instance UID reach the console, exactly as the CLI
                // reports them on stderr.
                let result = try await DICOMMPPSService.createDetailed(
                    host: host,
                    port: port,
                    callingAE: callingAET,
                    calledAE: calledAET,
                    studyInstanceUID: studyUID,
                    status: mppsStatus,
                    timeout: timeout,
                    patientName: optional(patientName),
                    patientID: optional(patientID),
                    modality: optional(modality),
                    procedureStepID: optional(procedureStepID),
                    procedureStepDescription: optional(procedureStepDescription),
                    performingPhysicianName: optional(createPerformingPhysician),
                    performedStationName: optional(stationName),
                    accessionNumber: optional(accessionNumber),
                    scheduledProcedureStepID: optional(spsID),
                    patientBirthDate: patientBirthDate.value,
                    patientSex: patientSex.value,
                    studyID: optional(studyID),
                    performedLocation: optional(performedLocation),
                    requestedProcedureID: optional(requestedProcedureID),
                    requestedProcedureDescription: optional(requestedProcedureDescription),
                    scheduledProcedureStepDescription: optional(spsDescription),
                    referencedStudySOPInstanceUID: optional(referencedStudyUID),
                    specificCharacterSet: optional(specificCharacterSet)
                )
                let createdUID = result.sopInstanceUID
                if let warning = result.warning {
                    appendConsoleOutput(Self.mppsWarningLine(warning, operation: "N-CREATE"))
                }
                if result.sopInstanceUIDWasReassigned {
                    appendConsoleOutput(
                        "note: SCP assigned MPPS SOP Instance UID \(result.sopInstanceUID) "
                        + "(requested \(result.requestedSOPInstanceUID)); use the assigned UID "
                        + "for the N-SET (PS3.7 10.1.5.1.4)\n")
                }
                // Result via the SHARED formatter (preserves the "MPPS Instance UID:"
                // marker). The UI-specific next-step hint stays local.
                appendConsoleOutput(NetworkConsole.mppsCreateResult(uid: createdUID))
                appendConsoleOutput("\nTo complete or discontinue this procedure step:\n")
                appendConsoleOutput("  Set Operation to 'update', paste the MPPS UID above,\n")
                appendConsoleOutput("  and set Status to COMPLETED or DISCONTINUED.\n")
                consoleStatus = .success
                service.setConsoleStatus(.success)
                addToHistory(toolName: "dicom-mpps", command: commandPreview, exitCode: 0,
                             output: "Created MPPS: \(createdUID)")
            } else {
                // Build referenced SOPs for the update — gated on BOTH study and
                // series UIDs, mirroring the CLI (DICOMMPPSCommand update builds the
                // Referenced SOP Sequence only when --study-uid and --series-uid are
                // both provided; it never substitutes the MPPS SOP Instance UID).
                var referencedSOPs: [(studyUID: String, seriesUID: String, sopInstanceUID: String)] = []
                if !studyUID.isEmpty && !seriesUID.isEmpty {
                    for uid in imageUIDs {
                        referencedSOPs.append((studyUID: studyUID, seriesUID: seriesUID, sopInstanceUID: uid))
                    }
                }
                appendConsoleOutput(NetworkConsole.mppsProgress(isCreate: false))
                // NOTE: accessionNumber is deliberately NOT forwarded here — the CLI's
                // update subcommand has no --accession-number option, and the field is
                // hidden in update mode (a stale value would silently leak into the N-SET).
                // studyInstanceUID is deliberately NOT forwarded: the CLI's update
                // (DICOMMPPSCommand) never sets it — the study/series UIDs flow only
                // into the Referenced SOP Sequence — so forwarding it here would emit
                // an N-SET dataset the pasted CLI command could never produce.
                let result = try await DICOMMPPSService.update(
                    host: host,
                    port: port,
                    callingAE: callingAET,
                    calledAE: calledAET,
                    mppsInstanceUID: mppsUID,
                    status: mppsStatus,
                    referencedSOPs: referencedSOPs,
                    timeout: timeout,
                    referencedSOPClassUID: optional(sopClassUID),
                    protocolName: optional(protocolName),
                    seriesDescription: optional(seriesDescription),
                    operatorsName: optional(operatorName),
                    performingPhysicianName: optional(updatePerformingPhysician),
                    legacyNSetScheduledStepAttributes: legacyNSetScheduledAttributes,
                    discontinuationReason: discontinuationReason,
                    specificCharacterSet: optional(specificCharacterSet)
                )
                if let warning = result.warning {
                    appendConsoleOutput(Self.mppsWarningLine(warning, operation: "N-SET"))
                }
                // Result via the SHARED formatter (preserves the "New Status:" /
                // "Referenced Images:" markers).
                appendConsoleOutput(NetworkConsole.mppsUpdateResult(
                    uid: mppsUID,
                    status: mppsStatus.rawValue,
                    referencedImages: referencedSOPs.count))
                consoleStatus = .success
                service.setConsoleStatus(.success)
                addToHistory(toolName: "dicom-mpps", command: commandPreview, exitCode: 0,
                             output: "Updated MPPS \(mppsUID) to \(mppsStatus.rawValue)")
            }
        } catch {
            // N-CREATE / N-SET failures arrive as DICOMNetworkError.mppsOperationFailed, worded
            // by DIMSEServiceStatusText; ArgumentParser prints them as `Error: <description>`.
            refuse((error as? DICOMNetworkError)?.description ?? error.localizedDescription, exitCode: 1)
        }
    }

    /// Formats a single generic query result for console display.
    // MARK: - Query Result Formatters

    /// Renders all results as a table matching the CLI's `dicom-query --format table` output.
    private func formatQueryResultsTable(_ pairs: [(result: GenericQueryResult, parent: GenericQueryResult?)], level: QueryLevel) -> String {
        guard !pairs.isEmpty else { return "No results found.\n" }

        switch level {
        case .patient:
            var output = ""
            output += String(repeating: "─", count: 100) + "\n"
            output += padRight("Patient Name", 30) + " "
            output += padRight("Patient ID", 15) + " "
            output += padRight("Birth Date", 12) + " "
            output += padRight("Sex", 5) + " "
            output += padRight("Studies", 8) + "\n"
            output += String(repeating: "─", count: 100) + "\n"
            for pair in pairs {
                let p = pair.result.toPatientResult()
                output += padRight(p.patientName ?? "", 30) + " "
                output += padRight(p.patientID ?? "", 15) + " "
                output += padRight(formatDICOMDate(p.patientBirthDate), 12) + " "
                output += padRight(p.patientSex ?? "", 5) + " "
                output += padRight(p.numberOfPatientRelatedStudies.map(String.init) ?? "", 8) + "\n"
            }
            output += String(repeating: "─", count: 100) + "\n"
            output += "Total: \(pairs.count) patient(s)\n"
            return output

        case .study:
            var output = ""
            output += String(repeating: "─", count: 120) + "\n"
            output += padRight("Patient Name", 25) + " "
            output += padRight("Patient ID", 12) + " "
            output += padRight("Date", 12) + " "
            output += padRight("Description", 30) + " "
            output += padRight("Modalities", 12) + " "
            output += padRight("Series", 8) + "\n"
            output += String(repeating: "─", count: 120) + "\n"
            for pair in pairs {
                let s = pair.result.toStudyResult()
                output += padRight(s.patientName ?? "", 25) + " "
                output += padRight(s.patientID ?? "", 12) + " "
                output += padRight(formatDICOMDate(s.studyDate), 12) + " "
                output += padRight(s.studyDescription ?? "", 30) + " "
                output += padRight(s.modalitiesInStudy ?? "", 12) + " "
                output += padRight(s.numberOfStudyRelatedSeries.map(String.init) ?? "", 8) + "\n"
            }
            output += String(repeating: "─", count: 120) + "\n"
            output += "Total: \(pairs.count) study(ies)\n"
            return output

        case .series:
            var output = ""
            output += String(repeating: "─", count: 100) + "\n"
            output += padRight("Series Number", 15) + " "
            output += padRight("Modality", 10) + " "
            output += padRight("Description", 40) + " "
            output += padRight("Date", 12) + " "
            output += padRight("Instances", 10) + "\n"
            output += String(repeating: "─", count: 100) + "\n"
            for pair in pairs {
                let s = pair.result.toSeriesResult()
                output += padRight(s.seriesNumber.map(String.init) ?? "", 15) + " "
                output += padRight(s.modality ?? "", 10) + " "
                output += padRight(s.seriesDescription ?? "", 40) + " "
                output += padRight(formatDICOMDate(s.seriesDate), 12) + " "
                output += padRight(s.numberOfSeriesRelatedInstances.map(String.init) ?? "", 10) + "\n"
            }
            output += String(repeating: "─", count: 100) + "\n"
            output += "Total: \(pairs.count) series\n"
            return output

        case .image:
            var output = ""
            output += String(repeating: "─", count: 100) + "\n"
            output += padRight("Instance Number", 17) + " "
            output += padRight("SOP Class", 30) + " "
            output += padRight("Dimensions", 15) + " "
            output += padRight("Frames", 8) + "\n"
            output += String(repeating: "─", count: 100) + "\n"
            for pair in pairs {
                let i = pair.result.toInstanceResult()
                output += padRight(i.instanceNumber.map(String.init) ?? "", 17) + " "
                let sopClass = i.sopClassUID ?? ""
                let sopComponents = sopClass.split(separator: ".")
                let shortSOP = sopComponents.count > 5
                    ? "..." + sopComponents.suffix(3).joined(separator: ".")
                    : sopClass
                output += padRight(shortSOP, 30) + " "
                let dims: String
                if let rows = i.rows, let cols = i.columns {
                    dims = "\(cols)×\(rows)"
                } else {
                    dims = ""
                }
                output += padRight(dims, 15) + " "
                output += padRight(i.numberOfFrames.map(String.init) ?? "1", 8) + "\n"
            }
            output += String(repeating: "─", count: 100) + "\n"
            output += "Total: \(pairs.count) instance(s)\n"
            return output
        }
    }

    /// Pads a string to a fixed width, truncating if longer.
    private func padRight(_ string: String, _ width: Int) -> String {
        let truncated = String(string.prefix(width))
        return truncated.padding(toLength: width, withPad: " ", startingAt: 0)
    }

    /// Converts a DICOM date string (YYYYMMDD) to YYYY-MM-DD for display.
    private func formatDICOMDate(_ dateString: String?) -> String {
        guard let dateString = dateString, dateString.count == 8 else {
            return dateString ?? ""
        }
        let year = dateString.prefix(4)
        let month = dateString.dropFirst(4).prefix(2)
        let day = dateString.dropFirst(6)
        return "\(year)-\(month)-\(day)"
    }

    /// Renders all results as a JSON array string.
    private func formatQueryResultsJSON(_ pairs: [(result: GenericQueryResult, parent: GenericQueryResult?)], level: QueryLevel) -> String {
        var entries: [String] = []
        for pair in pairs {
            var fields: [String] = []
            let r = pair.result
            let ps = pair.parent?.toStudyResult()
            let pp = pair.parent?.toPatientResult()
            if level == .image {
                let i = r.toInstanceResult()
                if let v = i.sopClassUID    { fields.append("    \"sopClassUID\": \"\(jsonEscape(v))\"") }
                if let v = i.sopInstanceUID { fields.append("    \"sopInstanceUID\": \"\(jsonEscape(v))\"") }
                if let v = i.instanceNumber { fields.append("    \"instanceNumber\": \(v)") }
                if let v = i.contentDate    { fields.append("    \"contentDate\": \"\(jsonEscape(v))\"") }
                if let r = i.rows, let c = i.columns { fields.append("    \"dimensions\": \"\(c)x\(r)\"") }
                if let v = i.numberOfFrames { fields.append("    \"numberOfFrames\": \(v)") }
            }
            if level == .series || level == .image {
                let s = r.toSeriesResult()
                if let v = s.seriesDescription { fields.append("    \"seriesDescription\": \"\(jsonEscape(v))\"") }
                if let v = s.modality          { fields.append("    \"modality\": \"\(jsonEscape(v))\"") }
                if let v = s.seriesNumber      { fields.append("    \"seriesNumber\": \(v)") }
                if let v = s.seriesDate        { fields.append("    \"seriesDate\": \"\(jsonEscape(v))\"") }
                if let v = s.numberOfSeriesRelatedInstances { fields.append("    \"instances\": \(v)") }
                if let v = s.seriesInstanceUID { fields.append("    \"seriesInstanceUID\": \"\(jsonEscape(v))\"") }
            }
            if level == .study || level == .series || level == .image {
                let s = r.toStudyResult()
                if let v = s.studyDate ?? ps?.studyDate                           { fields.append("    \"studyDate\": \"\(jsonEscape(v))\"") }
                if let v = s.studyTime ?? ps?.studyTime                           { fields.append("    \"studyTime\": \"\(jsonEscape(v))\"") }
                if let v = s.studyDescription ?? ps?.studyDescription             { fields.append("    \"studyDescription\": \"\(jsonEscape(v))\"") }
                if let v = s.accessionNumber ?? ps?.accessionNumber               { fields.append("    \"accessionNumber\": \"\(jsonEscape(v))\"") }
                if let v = s.modalitiesInStudy ?? ps?.modalitiesInStudy           { fields.append("    \"modalitiesInStudy\": \"\(jsonEscape(v))\"") }
                if let v = s.numberOfStudyRelatedSeries ?? ps?.numberOfStudyRelatedSeries         { fields.append("    \"studySeries\": \(v)") }
                if let v = s.numberOfStudyRelatedInstances ?? ps?.numberOfStudyRelatedInstances   { fields.append("    \"studyImages\": \(v)") }
                if let v = s.studyInstanceUID ?? ps?.studyInstanceUID             { fields.append("    \"studyInstanceUID\": \"\(jsonEscape(v))\"") }
            }
            let p = r.toPatientResult()
            if let v = p.patientName ?? pp?.patientName         { fields.append("    \"patientName\": \"\(jsonEscape(v))\"") }
            if let v = p.patientID ?? pp?.patientID             { fields.append("    \"patientID\": \"\(jsonEscape(v))\"") }
            if let v = p.patientBirthDate ?? pp?.patientBirthDate { fields.append("    \"patientBirthDate\": \"\(jsonEscape(v))\"") }
            if let v = p.patientSex ?? pp?.patientSex           { fields.append("    \"patientSex\": \"\(jsonEscape(v))\"") }
            if level == .patient {
                if let v = p.numberOfPatientRelatedStudies   { fields.append("    \"studies\": \(v)") }
                if let v = p.numberOfPatientRelatedSeries    { fields.append("    \"series\": \(v)") }
                if let v = p.numberOfPatientRelatedInstances { fields.append("    \"instances\": \(v)") }
            }
            entries.append("  {\n" + fields.joined(separator: ",\n") + "\n  }")
        }
        return "[\n" + entries.joined(separator: ",\n") + "\n]\n"
    }

    /// Renders all results as a CSV table.
    private func formatQueryResultsCSV(_ pairs: [(result: GenericQueryResult, parent: GenericQueryResult?)], level: QueryLevel) -> String {
        var header: [String] = []
        if level == .image { header += ["SOPClassUID", "SOPInstanceUID", "InstanceNumber", "ContentDate", "Dimensions", "Frames"] }
        if level == .series || level == .image { header += ["SeriesDescription", "Modality", "SeriesNumber", "SeriesDate", "Instances", "SeriesInstanceUID"] }
        if level == .study || level == .series || level == .image { header += ["StudyDate", "StudyTime", "StudyDescription", "AccessionNumber", "ModalitiesInStudy", "StudySeries", "StudyImages", "StudyInstanceUID"] }
        header += ["PatientName", "PatientID", "PatientBirthDate", "PatientSex"]
        if level == .patient { header += ["Studies", "Series", "Instances"] }

        var lines: [String] = [header.map { csvQuote($0) }.joined(separator: ",")]
        for pair in pairs {
            var row: [String] = []
            let r = pair.result
            let ps = pair.parent?.toStudyResult()
            let pp = pair.parent?.toPatientResult()
            if level == .image {
                let i = r.toInstanceResult()
                row += [csvQuote(i.sopClassUID ?? ""),
                        csvQuote(i.sopInstanceUID ?? ""),
                        csvQuote(i.instanceNumber.map(String.init) ?? ""),
                        csvQuote(i.contentDate ?? ""),
                        csvQuote((i.rows != nil && i.columns != nil) ? "\(i.columns!)x\(i.rows!)" : ""),
                        csvQuote(i.numberOfFrames.map(String.init) ?? "")]
            }
            if level == .series || level == .image {
                let s = r.toSeriesResult()
                row += [csvQuote(s.seriesDescription ?? ""),
                        csvQuote(s.modality ?? ""),
                        csvQuote(s.seriesNumber.map(String.init) ?? ""),
                        csvQuote(s.seriesDate ?? ""),
                        csvQuote(s.numberOfSeriesRelatedInstances.map(String.init) ?? ""),
                        csvQuote(s.seriesInstanceUID ?? "")]
            }
            if level == .study || level == .series || level == .image {
                let s = r.toStudyResult()
                let nSeries = (s.numberOfStudyRelatedSeries ?? ps?.numberOfStudyRelatedSeries).map(String.init) ?? ""
                let nImages = (s.numberOfStudyRelatedInstances ?? ps?.numberOfStudyRelatedInstances).map(String.init) ?? ""
                row += [csvQuote(s.studyDate ?? ps?.studyDate ?? ""),
                        csvQuote(s.studyTime ?? ps?.studyTime ?? ""),
                        csvQuote(s.studyDescription ?? ps?.studyDescription ?? ""),
                        csvQuote(s.accessionNumber ?? ps?.accessionNumber ?? ""),
                        csvQuote(s.modalitiesInStudy ?? ps?.modalitiesInStudy ?? ""),
                        csvQuote(nSeries), csvQuote(nImages),
                        csvQuote(s.studyInstanceUID ?? ps?.studyInstanceUID ?? "")]
            }
            let p = r.toPatientResult()
            row += [csvQuote(p.patientName ?? pp?.patientName ?? ""),
                    csvQuote(p.patientID ?? pp?.patientID ?? ""),
                    csvQuote(p.patientBirthDate ?? pp?.patientBirthDate ?? ""),
                    csvQuote(p.patientSex ?? pp?.patientSex ?? "")]
            if level == .patient {
                row += [csvQuote(p.numberOfPatientRelatedStudies.map(String.init) ?? ""),
                        csvQuote(p.numberOfPatientRelatedSeries.map(String.init) ?? ""),
                        csvQuote(p.numberOfPatientRelatedInstances.map(String.init) ?? "")]
            }
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Renders all results as an XML document.
    private func formatQueryResultsXML(_ pairs: [(result: GenericQueryResult, parent: GenericQueryResult?)], level: QueryLevel) -> String {
        var lines: [String] = ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>", "<QueryResults level=\"\(level)\">"]
        for pair in pairs {
            lines.append("  <Result>")
            let r = pair.result
            let ps = pair.parent?.toStudyResult()
            let pp = pair.parent?.toPatientResult()
            if level == .image {
                let i = r.toInstanceResult()
                if let v = i.sopClassUID    { lines.append("    <SOPClassUID>\(xmlEscape(v))</SOPClassUID>") }
                if let v = i.sopInstanceUID { lines.append("    <SOPInstanceUID>\(xmlEscape(v))</SOPInstanceUID>") }
                if let v = i.instanceNumber { lines.append("    <InstanceNumber>\(v)</InstanceNumber>") }
                if let v = i.contentDate    { lines.append("    <ContentDate>\(xmlEscape(v))</ContentDate>") }
                if let rr = i.rows, let c = i.columns { lines.append("    <Dimensions>\(c)x\(rr)</Dimensions>") }
                if let v = i.numberOfFrames { lines.append("    <NumberOfFrames>\(v)</NumberOfFrames>") }
            }
            if level == .series || level == .image {
                let s = r.toSeriesResult()
                if let v = s.seriesDescription { lines.append("    <SeriesDescription>\(xmlEscape(v))</SeriesDescription>") }
                if let v = s.modality          { lines.append("    <Modality>\(xmlEscape(v))</Modality>") }
                if let v = s.seriesNumber      { lines.append("    <SeriesNumber>\(v)</SeriesNumber>") }
                if let v = s.seriesDate        { lines.append("    <SeriesDate>\(xmlEscape(v))</SeriesDate>") }
                if let v = s.numberOfSeriesRelatedInstances { lines.append("    <Instances>\(v)</Instances>") }
                if let v = s.seriesInstanceUID { lines.append("    <SeriesInstanceUID>\(xmlEscape(v))</SeriesInstanceUID>") }
            }
            if level == .study || level == .series || level == .image {
                let s = r.toStudyResult()
                if let v = s.studyDate ?? ps?.studyDate             { lines.append("    <StudyDate>\(xmlEscape(v))</StudyDate>") }
                if let v = s.studyTime ?? ps?.studyTime             { lines.append("    <StudyTime>\(xmlEscape(v))</StudyTime>") }
                if let v = s.studyDescription ?? ps?.studyDescription { lines.append("    <StudyDescription>\(xmlEscape(v))</StudyDescription>") }
                if let v = s.accessionNumber ?? ps?.accessionNumber { lines.append("    <AccessionNumber>\(xmlEscape(v))</AccessionNumber>") }
                if let v = s.modalitiesInStudy ?? ps?.modalitiesInStudy { lines.append("    <ModalitiesInStudy>\(xmlEscape(v))</ModalitiesInStudy>") }
                if let v = s.numberOfStudyRelatedSeries ?? ps?.numberOfStudyRelatedSeries         { lines.append("    <StudySeries>\(v)</StudySeries>") }
                if let v = s.numberOfStudyRelatedInstances ?? ps?.numberOfStudyRelatedInstances   { lines.append("    <StudyImages>\(v)</StudyImages>") }
                if let v = s.studyInstanceUID ?? ps?.studyInstanceUID { lines.append("    <StudyInstanceUID>\(xmlEscape(v))</StudyInstanceUID>") }
            }
            let p = r.toPatientResult()
            if let v = p.patientName ?? pp?.patientName           { lines.append("    <PatientName>\(xmlEscape(v))</PatientName>") }
            if let v = p.patientID ?? pp?.patientID               { lines.append("    <PatientID>\(xmlEscape(v))</PatientID>") }
            if let v = p.patientBirthDate ?? pp?.patientBirthDate { lines.append("    <PatientBirthDate>\(xmlEscape(v))</PatientBirthDate>") }
            if let v = p.patientSex ?? pp?.patientSex             { lines.append("    <PatientSex>\(xmlEscape(v))</PatientSex>") }
            if level == .patient {
                if let v = p.numberOfPatientRelatedStudies   { lines.append("    <Studies>\(v)</Studies>") }
                if let v = p.numberOfPatientRelatedSeries    { lines.append("    <Series>\(v)</Series>") }
                if let v = p.numberOfPatientRelatedInstances { lines.append("    <Instances>\(v)</Instances>") }
            }
            lines.append("  </Result>")
        }
        lines.append("</QueryResults>")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Renders results as HL7 v2.x ADT^A28 / ZDS segment messages (one per result).
    private func formatQueryResultsHL7(_ pairs: [(result: GenericQueryResult, parent: GenericQueryResult?)], level: QueryLevel) -> String {
        let now = Date()
        let dtFormatter = DateFormatter()
        dtFormatter.dateFormat = "yyyyMMddHHmmss"
        let msgDateTime = dtFormatter.string(from: now)
        var messages: [String] = []
        for (idx, pair) in pairs.enumerated() {
            let r = pair.result
            let ps = pair.parent?.toStudyResult()
            let pp = pair.parent?.toPatientResult()
            let p  = r.toPatientResult()
            let s  = r.toStudyResult()
            let patName   = p.patientName ?? pp?.patientName ?? "UNKNOWN"
            let patID     = p.patientID ?? pp?.patientID ?? ""
            let patDOB    = p.patientBirthDate ?? pp?.patientBirthDate ?? ""
            let patSex    = p.patientSex ?? pp?.patientSex ?? ""
            let studyUID  = s.studyInstanceUID ?? ps?.studyInstanceUID ?? ""
            let studyDate = s.studyDate ?? ps?.studyDate ?? ""
            let accession = s.accessionNumber ?? ps?.accessionNumber ?? ""
            let modalities = s.modalitiesInStudy ?? ps?.modalitiesInStudy ?? ""
            let studyDesc  = s.studyDescription ?? ps?.studyDescription ?? ""
            let msgID = String(format: "DICOMSTUDIO%07d", idx + 1)
            var segs: [String] = []
            segs.append("MSH|^~\\&|DICOMSTUDIO||DICOMSERVER||\(msgDateTime)||ADT^A28|\(msgID)|P|2.5")
            segs.append("PID|1||\(hl7Escape(patID))|||\(hl7Escape(patName))||\(hl7Escape(patDOB))|\(hl7Escape(patSex))")
            // ZDS: study information (HL7 Z-segment for DICOM)
            segs.append("ZDS|\(hl7Escape(studyUID))|\(hl7Escape(accession))|\(hl7Escape(studyDate))|\(hl7Escape(modalities))|\(hl7Escape(studyDesc))")
            if level == .series || level == .image {
                let sr = r.toSeriesResult()
                let serUID  = sr.seriesInstanceUID ?? ""
                let serMod  = sr.modality ?? ""
                let serDesc = sr.seriesDescription ?? ""
                let serNum  = sr.seriesNumber.map(String.init) ?? ""
                segs.append("ZSE|\(hl7Escape(serUID))|\(hl7Escape(serNum))|\(hl7Escape(serMod))|\(hl7Escape(serDesc))")
            }
            if level == .image {
                let ir = r.toInstanceResult()
                segs.append("ZIM|\(hl7Escape(ir.sopInstanceUID ?? ""))|\(hl7Escape(ir.sopClassUID ?? ""))|\(ir.instanceNumber ?? 0)")
            }
            messages.append(segs.joined(separator: "\n"))
        }
        return messages.joined(separator: "\n---\n") + "\n"
    }

    private func jsonEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\\\", with: "\\\\\\\\").replacingOccurrences(of: "\"", with: "\\\\\"")
    }
    private func csvQuote(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
    private func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
    private func hl7Escape(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "\\F\\").replacingOccurrences(of: "^", with: "\\S\\")
    }

    private func formatQueryResult(_ result: GenericQueryResult, index: Int, level: QueryLevel, parentStudyInfo: GenericQueryResult? = nil) -> String {
        var lines: [String] = ["--- Result \(index) ---"]

        // Display attributes from the queried (lower) level up to higher parent levels.

        // Image-level attributes
        if level == .image {
            let i = result.toInstanceResult()
            if let v = i.sopClassUID    { lines.append("  SOP Class:     \(v)") }
            if let v = i.sopInstanceUID { lines.append("  SOP Instance:  \(v)") }
            if let v = i.instanceNumber { lines.append("  Instance #:    \(v)") }
            if let v = i.contentDate    { lines.append("  Content Date:  \(v)") }
            if let v = i.rows, let c = i.columns { lines.append("  Dimensions:    \(c)x\(v)") }
            if let v = i.numberOfFrames { lines.append("  Frames:        \(v)") }
        }

        // Series-level attributes
        if level == .series || level == .image {
            let s = result.toSeriesResult()
            if let v = s.seriesDescription { lines.append("  Series Desc:   \(v)") }
            if let v = s.modality       { lines.append("  Modality:      \(v)") }
            if let v = s.seriesNumber   { lines.append("  Series #:      \(v)") }
            if let v = s.seriesDate     { lines.append("  Series Date:   \(v)") }
            if let v = s.numberOfSeriesRelatedInstances { lines.append("  Instances:     \(v)") }
            if let v = s.seriesInstanceUID { lines.append("  Series UID:    \(v)") }
        }

        // Study-level attributes (with parent info fallback for series/image levels)
        if level == .study || level == .series || level == .image {
            let s = result.toStudyResult()
            let ps = parentStudyInfo?.toStudyResult()
            if let v = s.studyDate ?? ps?.studyDate { lines.append("  Study Date:    \(v)") }
            if let v = s.studyTime ?? ps?.studyTime { lines.append("  Study Time:    \(v)") }
            if let v = s.studyDescription ?? ps?.studyDescription { lines.append("  Study Desc:    \(v)") }
            if let v = s.accessionNumber ?? ps?.accessionNumber { lines.append("  Accession:     \(v)") }
            if let v = s.modalitiesInStudy ?? ps?.modalitiesInStudy { lines.append("  Modalities:    \(v)") }
            if let v = s.numberOfStudyRelatedSeries ?? ps?.numberOfStudyRelatedSeries { lines.append("  Study Series:  \(v)") }
            if let v = s.numberOfStudyRelatedInstances ?? ps?.numberOfStudyRelatedInstances { lines.append("  Study Images:  \(v)") }
            if let v = s.studyInstanceUID ?? ps?.studyInstanceUID { lines.append("  Study UID:     \(v)") }
        }

        // Patient-level attributes (highest level — always shown, with parent info fallback)
        let p = result.toPatientResult()
        let pp = parentStudyInfo?.toPatientResult()
        if let v = p.patientName ?? pp?.patientName { lines.append("  Patient Name:  \(v)") }
        if let v = p.patientID ?? pp?.patientID { lines.append("  Patient ID:    \(v)") }
        if let v = p.patientBirthDate ?? pp?.patientBirthDate { lines.append("  Birth Date:    \(v)") }
        if let v = p.patientSex ?? pp?.patientSex { lines.append("  Sex:           \(v)") }
        if level == .patient {
            if let v = p.numberOfPatientRelatedStudies { lines.append("  Studies:       \(v)") }
            if let v = p.numberOfPatientRelatedSeries  { lines.append("  Series:        \(v)") }
            if let v = p.numberOfPatientRelatedInstances { lines.append("  Instances:     \(v)") }
        }

        lines.append("")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Updates the console status.
    public func updateConsoleStatus(_ status: CLIConsoleStatus) {
        consoleStatus = status
        service.setConsoleStatus(status)
    }

    /// Appends text to the console output.
    public func appendConsoleOutput(_ text: String) {
        consoleOutput += text
        service.appendConsoleOutput(text)
    }

    // MARK: - 16.6 Command History

    /// Adds an entry to command history with PHI redaction.
    public func addToHistory(toolName: String, command: String, exitCode: Int?, output: String) {
        let redacted = ConsoleHelpers.redactPHI(command)
        let state: CLIExecutionState = (exitCode == 0) ? .completed : .failed
        let entry = CLICommandHistoryEntry(
            toolName: toolName,
            rawCommand: command,
            redactedCommand: redacted,
            executionState: state,
            exitCode: exitCode,
            outputSnippet: String(output.prefix(200))
        )
        commandHistory.append(entry)
        commandHistory = ConsoleHelpers.trimHistory(commandHistory)
        service.addCommandHistoryEntry(entry)
    }

    /// Clears all command history.
    public func clearHistory() {
        commandHistory.removeAll()
        service.clearCommandHistory()
    }

    // MARK: - 16.8 Educational Features

    /// Toggles between beginner and advanced experience mode.
    public func toggleExperienceMode() {
        experienceMode = (experienceMode == .beginner) ? .advanced : .beginner
        service.setExperienceMode(experienceMode)
    }

    /// Sets the experience mode directly.
    public func setExperienceMode(_ mode: CLIExperienceMode) {
        experienceMode = mode
        service.setExperienceMode(mode)
    }

    /// Returns glossary entries filtered by the current search query.
    public func filteredGlossaryEntries() -> [CLIGlossaryEntry] {
        EducationalHelpers.filterGlossary(glossaryEntries, query: glossarySearchQuery)
    }

    /// Updates the glossary search query.
    public func updateGlossarySearch(_ query: String) {
        glossarySearchQuery = query
        service.setGlossarySearchQuery(query)
    }

    /// Returns example presets for the selected tool.
    public func examplePresetsForSelectedTool() -> [CLIExamplePreset] {
        guard let id = selectedToolID else { return [] }
        return EducationalHelpers.examplePresets(for: id)
    }
}

// MARK: - Convert Error

/// Errors specific to the dicom-convert execution in the CLI Workshop.
enum ConvertError: LocalizedError {
    case missingTransferSyntax
    case unknownTransferSyntax(String)
    case invalidFrame(Int, Int)
    case renderFailed
    case exportFailed
    case unsupportedPlatform

    var errorDescription: String? {
        switch self {
        case .missingTransferSyntax:
            return DICOMConverter.missingTargetMessage
        case .unknownTransferSyntax(let name):
            // Shared list keeps the Workshop's error identical to the dicom-convert CLI.
            return DICOMConverter.unknownTargetMessage(name)
        case .invalidFrame(let requested, let total):
            return DICOMConverter.invalidFrameMessage(requested: requested, total: total)
        case .renderFailed:
            return "Failed to render pixel data to image"
        case .exportFailed:
            return "Failed to export image to file"
        case .unsupportedPlatform:
            return "Image export is not supported on this platform"
        }
    }
}

// MARK: - dicom-dcmdir File-set rules (PS3.10 8.1, 8.2, 8.5, 8.6; PS3.3 Tables F.3-2, F.3-3, F.4-1)

/// The PS3.10 / PS3.3 rules `dicom-dcmdir` applies on top of `DICOMDirectory.validate`, and the
/// clause each failure names — `Sources/dicom-dcmdir/FileSetRules.swift`, kept text-identical
/// here because that type is CLI-local (not in DICOMKit); lifting it into DICOMKit is the
/// recorded follow-up. Rule values: PS3.10 2026a 8.1 (File-set ID 0-16 characters), 8.2 (a File
/// ID has 1-8 components of 1-8 characters), 8.5 (A-Z, 0-9, _), 8.6 (no File outside the
/// File-set); PS3.3 2026a Table F.3-3 (each File referenced by at most one Directory Record).
enum WorkshopFileSetRules {

    /// PS3.10 8.5: File IDs and File-set IDs use A-Z, 0-9 and underscore only.
    static let allowedCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
    /// PS3.10 8.2: a File ID has one to eight components.
    static let maxFileIDComponents = 8
    /// PS3.10 8.2: each component is one to eight characters.
    static let maxComponentLength = 8
    /// PS3.10 8.1: a File-set ID is zero to sixteen characters.
    static let maxFileSetIDLength = 16

    static let fileIDRule = "PS3.10 8.2, 8.5; PS3.3 Table F.3-3 Referenced File ID (0004,1500)"
    static let fileSetIDRule = "PS3.10 8.1, 8.5; PS3.3 Table F.3-2 File-set ID (0004,1130)"

    /// Violations of PS3.10 8.2 / 8.5 for one Referenced File ID (its components).
    static func fileIDViolations(_ components: [String]) -> [String] {
        let shown = components.joined(separator: "\\")
        var out: [String] = []
        if components.isEmpty || components.count > maxFileIDComponents {
            out.append("File ID \(shown) has \(components.count) components; a File ID has 1 to \(maxFileIDComponents) [\(fileIDRule)]")
        }
        for component in components {
            if component.isEmpty || component.count > maxComponentLength {
                out.append("File ID component '\(component)' of \(shown) has \(component.count) characters; each component has 1 to \(maxComponentLength) [\(fileIDRule)]")
            }
            if !component.allSatisfy({ allowedCharacters.contains($0) }) {
                out.append("File ID component '\(component)' of \(shown) uses characters other than A-Z, 0-9 and _ [\(fileIDRule)]")
            }
        }
        return out
    }

    /// Violations of PS3.10 8.1 / 8.5 for a File-set ID (an empty ID is allowed: Type 2).
    static func fileSetIDViolations(_ id: String) -> [String] {
        var out: [String] = []
        if id.count > maxFileSetIDLength {
            out.append("File-set ID '\(id)' has \(id.count) characters; at most \(maxFileSetIDLength) [\(fileSetIDRule)]")
        }
        if !id.allSatisfy({ allowedCharacters.contains($0) }) {
            out.append("File-set ID '\(id)' uses characters other than A-Z, 0-9 and _ [\(fileSetIDRule)]")
        }
        return out
    }

    /// P-DCMDIR-FSID (approved 2026-10-01): `create --file-set-id` refuses an ID that breaks
    /// PS3.10 8.1 / 8.5. Returns the refusal text, or nil.
    static func fileSetIDRefusal(_ id: String) -> String? {
        let problems = fileSetIDViolations(id)
        guard !problems.isEmpty else { return nil }
        return "Refusing --file-set-id: " + problems.joined(separator: "; ")
            + ". A File-set ID is 0 to 16 characters A-Z, 0-9 and _ (PS3.10 2026a 8.1, 8.5; PS3.3 2026a Table F.3-2 File-set ID (0004,1130))"
    }

    /// The pre-2026-09-25 `--profile` spellings that are not PS3.11 identifiers, with the
    /// PS3.11 2026a table that defines the identifier `DICOMDIRProfile(rawValue:)` maps them to
    /// (P-DCMDIR-PROFILE: still accepted, deprecated).
    static let deprecatedProfileTables: [String: String] = [
        "STD-GEN-DVD": "PS3.11 2026a Table H.1-1",
        "STD-GEN-USB": "PS3.11 2026a Table J.1-1",
        "STD-GEN-SEC": "PS3.11 2026a Table D.1-1",
        "STD-CTMR-XXXX": "PS3.11 2026a Table E.1-1",
        "STD-US-XXXX": "PS3.11 2026a Table C.1-1",
    ]

    /// The one-line note for a deprecated `--profile` spelling, naming the PS3.11 identifier
    /// actually used; nil for a PS3.11 identifier.
    static func profileDeprecationNote(requested: String, resolved: DICOMDIRProfile) -> String? {
        let key = requested.trimmingCharacters(in: .whitespaces).uppercased()
        guard let table = deprecatedProfileTables[key] else { return nil }
        return "dicom-dcmdir: warning: --profile \(requested) is deprecated (not a PS3.11 Application Profile identifier); using \(resolved.rawValue) (\(table)). It will be rejected in the next major version."
    }

    /// The File-set ID `create` derives from the input directory name when `--file-set-id` is
    /// not given: upper-cased, every character outside the PS3.10 8.5 set replaced by `_`, cut
    /// to 16 characters (PS3.10 8.1).
    static func defaultFileSetID(fromDirectoryName name: String) -> String {
        let mapped = name.uppercased().map { allowedCharacters.contains($0) ? $0 : "_" }
        return String(String(mapped).prefix(maxFileSetIDLength))
    }

    /// The clause a `DICOMDirectory.ValidationError` breaks.
    static func citation(for error: DICOMDirectory.ValidationError) -> String {
        switch error {
        case .invalidFileSetID:
            return fileSetIDRule
        case .invalidHierarchy, .invalidRecordTypeInHierarchy:
            return "PS3.3 F.4, Table F.4-1"
        case .missingReferencedFile:
            return "PS3.10 8.6; PS3.3 Table F.3-3 Referenced File ID (0004,1500)"
        case .invalidSOPInstanceUID:
            return "PS3.5 9.1; PS3.3 Table F.3-3 Referenced SOP Instance UID in File (0004,1511)"
        case .duplicateSOPInstanceUID:
            return "PS3.3 Table F.3-3 Referenced SOP Instance UID in File (0004,1511); PS3.5 9"
        }
    }

    /// Text for any error thrown while reading or validating: the `description` of a
    /// `CustomStringConvertible` error (a plain Swift error's `localizedDescription` is
    /// only "The operation couldn't be completed"), with the clause for validation errors.
    static func describe(_ error: Error) -> String {
        if let v = error as? DICOMDirectory.ValidationError {
            return "\(v.description) [\(citation(for: v))]"
        }
        if !(type(of: error) is NSError.Type) {
            return String(describing: error)
        }
        return error.localizedDescription
    }

    /// Every File ID / File-set ID finding for a directory. With `checkFiles`, each
    /// Referenced File ID must also name an existing file under `mediaFolder` (PS3.10 8.6).
    static func findings(for directory: DICOMDirectory, mediaFolder: URL?, checkFiles: Bool) -> [String] {
        var out = fileSetIDViolations(directory.fileSetID)
        var seen: [String: Int] = [:]
        for record in directory.allRecords() {
            guard let components = record.referencedFileID, !components.isEmpty else { continue }
            out += fileIDViolations(components)
            let key = components.joined(separator: "\\")
            seen[key, default: 0] += 1
            if seen[key] == 2 {
                out.append("File ID \(key) is referenced by more than one Directory Record; any File shall be referenced by at most one [PS3.3 Table F.3-3 Referenced File ID (0004,1500)]")
            }
            if checkFiles, let mediaFolder {
                let url = components.reduce(mediaFolder) { $0.appendingPathComponent($1) }
                if !FileManager.default.fileExists(atPath: url.path) {
                    out.append("Referenced File ID \(key) does not exist in the File-set [PS3.10 8.6; PS3.3 Table F.3-3 Referenced File ID (0004,1500)]")
                }
            }
        }
        return out
    }
}
