// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (thread-safe Workshop state holder: selected tool, parameter values, console status, history; grep for tags, UIDs, STD-* profiles, VR codes and PS3 clauses found none)
// CLIWorkshopService.swift
// DICOMStudio
//
// DICOM Studio — Thread-safe service for CLI Tools Workshop state (Milestone 16)

import Foundation

/// Thread-safe service that manages state for the CLI Tools Workshop feature.
public final class CLIWorkshopService: @unchecked Sendable {
    private let lock = NSLock()

    // 16.1 Network Configuration
    private var _networkProfiles: [CLINetworkProfile] = [NetworkConfigHelpers.defaultProfile()]
    private var _activeProfileID: UUID? = nil
    private var _connectionTestStatus: CLIConnectionTestStatus = .untested

    // 16.2 Tool Catalog
    private var _tools: [CLIToolDefinition] = ToolCatalogHelpers.allTools()
    private var _selectedToolID: String? = nil

    // 16.3 Parameter Configuration
    private var _parameterDefinitions: [CLIParameterDefinition] = []
    private var _parameterValues: [CLIParameterValue] = []

    // 16.4 File Drop Zone
    private var _inputFiles: [CLIFileEntry] = []
    private var _outputPath: String = ""
    private var _fileDropState: CLIFileDropState = .empty

    // 16.5 Console
    private var _consoleStatus: CLIConsoleStatus = .idle
    private var _consoleOutput: String = ""
    private var _commandPreview: String = ""

    // 16.6 Command History
    private var _commandHistory: [CLICommandHistoryEntry] = []

    // 16.8 Educational Features
    private var _experienceMode: CLIExperienceMode = .beginner
    private var _glossaryEntries: [CLIGlossaryEntry] = EducationalHelpers.defaultGlossaryEntries()
    private var _glossarySearchQuery: String = ""

    public init() {}

    // MARK: - 16.1 Network Configuration

    public func getNetworkProfiles() -> [CLINetworkProfile] { lock.withLock { _networkProfiles } }
    public func setNetworkProfiles(_ profiles: [CLINetworkProfile]) { lock.withLock { _networkProfiles = profiles } }
    public func getActiveProfileID() -> UUID? { lock.withLock { _activeProfileID } }
    public func setActiveProfileID(_ id: UUID?) { lock.withLock { _activeProfileID = id } }
    public func getConnectionTestStatus() -> CLIConnectionTestStatus { lock.withLock { _connectionTestStatus } }
    public func setConnectionTestStatus(_ status: CLIConnectionTestStatus) { lock.withLock { _connectionTestStatus = status } }

    public func addProfile(_ profile: CLINetworkProfile) {
        lock.withLock { _networkProfiles.append(profile) }
    }

    public func removeProfile(id: UUID) {
        lock.withLock { _networkProfiles.removeAll { $0.id == id } }
    }

    public func updateProfile(_ profile: CLINetworkProfile) {
        lock.withLock {
            guard let idx = _networkProfiles.firstIndex(where: { $0.id == profile.id }) else { return }
            _networkProfiles[idx] = profile
        }
    }

    // MARK: - 16.2 Tool Catalog

    public func getTools() -> [CLIToolDefinition] { lock.withLock { _tools } }
    public func getSelectedToolID() -> String? { lock.withLock { _selectedToolID } }
    public func setSelectedToolID(_ id: String?) { lock.withLock { _selectedToolID = id } }

    // MARK: - 16.3 Parameter Configuration

    public func getParameterDefinitions() -> [CLIParameterDefinition] { lock.withLock { _parameterDefinitions } }
    public func setParameterDefinitions(_ defs: [CLIParameterDefinition]) { lock.withLock { _parameterDefinitions = defs } }
    public func getParameterValues() -> [CLIParameterValue] { lock.withLock { _parameterValues } }
    public func setParameterValues(_ values: [CLIParameterValue]) { lock.withLock { _parameterValues = values } }

    public func updateParameterValue(_ value: CLIParameterValue) {
        lock.withLock {
            if let idx = _parameterValues.firstIndex(where: { $0.parameterID == value.parameterID }) {
                _parameterValues[idx] = value
            } else {
                _parameterValues.append(value)
            }
        }
    }

    // MARK: - 16.4 File Drop Zone

    public func getInputFiles() -> [CLIFileEntry] { lock.withLock { _inputFiles } }
    public func setInputFiles(_ files: [CLIFileEntry]) { lock.withLock { _inputFiles = files } }
    public func getOutputPath() -> String { lock.withLock { _outputPath } }
    public func setOutputPath(_ path: String) { lock.withLock { _outputPath = path } }
    public func getFileDropState() -> CLIFileDropState { lock.withLock { _fileDropState } }
    public func setFileDropState(_ state: CLIFileDropState) { lock.withLock { _fileDropState = state } }

    public func addInputFile(_ file: CLIFileEntry) {
        lock.withLock { _inputFiles.append(file) }
    }

    public func removeInputFile(id: UUID) {
        lock.withLock { _inputFiles.removeAll { $0.id == id } }
    }

    // MARK: - 16.5 Console

    public func getConsoleStatus() -> CLIConsoleStatus { lock.withLock { _consoleStatus } }
    public func setConsoleStatus(_ status: CLIConsoleStatus) { lock.withLock { _consoleStatus = status } }
    public func getConsoleOutput() -> String { lock.withLock { _consoleOutput } }
    public func setConsoleOutput(_ output: String) { lock.withLock { _consoleOutput = output } }
    public func appendConsoleOutput(_ text: String) { lock.withLock { _consoleOutput += text } }
    public func getCommandPreview() -> String { lock.withLock { _commandPreview } }
    public func setCommandPreview(_ preview: String) { lock.withLock { _commandPreview = preview } }

    // MARK: - 16.6 Command History

    public func getCommandHistory() -> [CLICommandHistoryEntry] { lock.withLock { _commandHistory } }
    public func setCommandHistory(_ history: [CLICommandHistoryEntry]) {
        lock.withLock { _commandHistory = ConsoleHelpers.trimHistory(history) }
    }

    public func addCommandHistoryEntry(_ entry: CLICommandHistoryEntry) {
        lock.withLock {
            _commandHistory.append(entry)
            _commandHistory = ConsoleHelpers.trimHistory(_commandHistory)
        }
    }

    public func clearCommandHistory() {
        lock.withLock { _commandHistory.removeAll() }
    }

    // MARK: - 16.8 Educational Features

    public func getExperienceMode() -> CLIExperienceMode { lock.withLock { _experienceMode } }
    public func setExperienceMode(_ mode: CLIExperienceMode) { lock.withLock { _experienceMode = mode } }
    public func getGlossaryEntries() -> [CLIGlossaryEntry] { lock.withLock { _glossaryEntries } }
    public func setGlossaryEntries(_ entries: [CLIGlossaryEntry]) { lock.withLock { _glossaryEntries = entries } }
    public func getGlossarySearchQuery() -> String { lock.withLock { _glossarySearchQuery } }
    public func setGlossarySearchQuery(_ query: String) { lock.withLock { _glossarySearchQuery = query } }
}
