// CLIWorkshopServiceTests.swift
// DICOMStudioTests
//
// DICOM Studio — Tests for CLI Tools Workshop service (Milestone 16)

import Testing
@testable import DICOMStudio
import Foundation

@Suite("CLI Workshop Service Tests")
struct CLIWorkshopServiceTests {

    // MARK: - 16.1 Network Configuration

    @Test("getNetworkProfiles returns default profile on init")
    func testDefaultNetworkProfiles() {
        let service = CLIWorkshopService()
        let profiles = service.getNetworkProfiles()
        #expect(profiles.count == 1)
        #expect(profiles[0].name == "Default")
    }

    @Test("addProfile appends a profile")
    func testAddProfile() {
        let service = CLIWorkshopService()
        let profile = CLINetworkProfile(name: "PACS1")
        service.addProfile(profile)
        #expect(service.getNetworkProfiles().count == 2)
    }

    @Test("removeProfile removes by ID")
    func testRemoveProfile() {
        let service = CLIWorkshopService()
        let profile = CLINetworkProfile(name: "ToRemove")
        service.addProfile(profile)
        #expect(service.getNetworkProfiles().count == 2)
        service.removeProfile(id: profile.id)
        #expect(service.getNetworkProfiles().count == 1)
    }

    @Test("updateProfile updates matching profile")
    func testUpdateProfile() {
        let service = CLIWorkshopService()
        var profile = CLINetworkProfile(name: "Original")
        service.addProfile(profile)
        profile.name = "Updated"
        service.updateProfile(profile)
        let updated = service.getNetworkProfiles().first { $0.id == profile.id }
        #expect(updated?.name == "Updated")
    }

    @Test("activeProfileID defaults to nil")
    func testActiveProfileIDDefault() {
        let service = CLIWorkshopService()
        #expect(service.getActiveProfileID() == nil)
    }

    @Test("setActiveProfileID stores and retrieves")
    func testSetActiveProfileID() {
        let service = CLIWorkshopService()
        let id = UUID()
        service.setActiveProfileID(id)
        #expect(service.getActiveProfileID() == id)
    }

    @Test("connectionTestStatus defaults to untested")
    func testConnectionTestStatusDefault() {
        let service = CLIWorkshopService()
        #expect(service.getConnectionTestStatus() == .untested)
    }

    @Test("setConnectionTestStatus updates status")
    func testSetConnectionTestStatus() {
        let service = CLIWorkshopService()
        service.setConnectionTestStatus(.success)
        #expect(service.getConnectionTestStatus() == .success)
    }

    // MARK: - 16.2 Tool Catalog

    @Test("getTools returns 35 tools")
    func testGetTools() {
        let service = CLIWorkshopService()
        #expect(service.getTools().count == 35)
    }

    @Test("selectedToolID defaults to nil")
    func testSelectedToolIDDefault() {
        let service = CLIWorkshopService()
        #expect(service.getSelectedToolID() == nil)
    }

    @Test("setSelectedToolID stores and retrieves")
    func testSetSelectedToolID() {
        let service = CLIWorkshopService()
        service.setSelectedToolID("dicom-info")
        #expect(service.getSelectedToolID() == "dicom-info")
    }

    // MARK: - 16.3 Parameter Configuration

    @Test("parameterDefinitions defaults to empty")
    func testParameterDefinitionsDefault() {
        let service = CLIWorkshopService()
        #expect(service.getParameterDefinitions().isEmpty)
    }

    @Test("setParameterDefinitions stores and retrieves")
    func testSetParameterDefinitions() {
        let service = CLIWorkshopService()
        let defs = [CLIParameterDefinition(id: "x", flag: "--x", displayName: "X", parameterType: .textField)]
        service.setParameterDefinitions(defs)
        #expect(service.getParameterDefinitions().count == 1)
    }

    @Test("updateParameterValue creates or updates value")
    func testUpdateParameterValue() {
        let service = CLIWorkshopService()
        let val = CLIParameterValue(parameterID: "input", stringValue: "file.dcm")
        service.updateParameterValue(val)
        #expect(service.getParameterValues().count == 1)

        let updated = CLIParameterValue(parameterID: "input", stringValue: "other.dcm")
        service.updateParameterValue(updated)
        #expect(service.getParameterValues().count == 1)
        #expect(service.getParameterValues()[0].stringValue == "other.dcm")
    }

    // MARK: - 16.4 File Drop Zone

    @Test("inputFiles defaults to empty")
    func testInputFilesDefault() {
        let service = CLIWorkshopService()
        #expect(service.getInputFiles().isEmpty)
    }

    @Test("addInputFile appends a file")
    func testAddInputFile() {
        let service = CLIWorkshopService()
        let file = CLIFileEntry(path: "/f", filename: "scan.dcm")
        service.addInputFile(file)
        #expect(service.getInputFiles().count == 1)
    }

    @Test("removeInputFile removes by ID")
    func testRemoveInputFile() {
        let service = CLIWorkshopService()
        let file = CLIFileEntry(path: "/f", filename: "scan.dcm")
        service.addInputFile(file)
        service.removeInputFile(id: file.id)
        #expect(service.getInputFiles().isEmpty)
    }

    @Test("fileDropState defaults to empty")
    func testFileDropStateDefault() {
        let service = CLIWorkshopService()
        #expect(service.getFileDropState() == .empty)
    }

    @Test("setFileDropState updates state")
    func testSetFileDropState() {
        let service = CLIWorkshopService()
        service.setFileDropState(.selected)
        #expect(service.getFileDropState() == .selected)
    }

    @Test("outputPath defaults to empty string")
    func testOutputPathDefault() {
        let service = CLIWorkshopService()
        #expect(service.getOutputPath() == "")
    }

    @Test("setOutputPath stores and retrieves")
    func testSetOutputPath() {
        let service = CLIWorkshopService()
        service.setOutputPath("/output")
        #expect(service.getOutputPath() == "/output")
    }

    // MARK: - 16.5 Console

    @Test("consoleStatus defaults to idle")
    func testConsoleStatusDefault() {
        let service = CLIWorkshopService()
        #expect(service.getConsoleStatus() == .idle)
    }

    @Test("setConsoleStatus updates status")
    func testSetConsoleStatus() {
        let service = CLIWorkshopService()
        service.setConsoleStatus(.running)
        #expect(service.getConsoleStatus() == .running)
    }

    @Test("consoleOutput defaults to empty")
    func testConsoleOutputDefault() {
        let service = CLIWorkshopService()
        #expect(service.getConsoleOutput() == "")
    }

    @Test("appendConsoleOutput appends text")
    func testAppendConsoleOutput() {
        let service = CLIWorkshopService()
        service.appendConsoleOutput("Line 1\n")
        service.appendConsoleOutput("Line 2\n")
        #expect(service.getConsoleOutput() == "Line 1\nLine 2\n")
    }

    @Test("commandPreview defaults to empty")
    func testCommandPreviewDefault() {
        let service = CLIWorkshopService()
        #expect(service.getCommandPreview() == "")
    }

    // MARK: - 16.6 Command History

    @Test("commandHistory defaults to empty")
    func testCommandHistoryDefault() {
        let service = CLIWorkshopService()
        #expect(service.getCommandHistory().isEmpty)
    }

    @Test("addCommandHistoryEntry appends entry")
    func testAddCommandHistoryEntry() {
        let service = CLIWorkshopService()
        let entry = CLICommandHistoryEntry(toolName: "dicom-info", rawCommand: "c", redactedCommand: "c")
        service.addCommandHistoryEntry(entry)
        #expect(service.getCommandHistory().count == 1)
    }

    @Test("addCommandHistoryEntry trims to 50 entries")
    func testAddCommandHistoryEntryTrims() {
        let service = CLIWorkshopService()
        for i in 0..<55 {
            let entry = CLICommandHistoryEntry(toolName: "t\(i)", rawCommand: "c", redactedCommand: "c")
            service.addCommandHistoryEntry(entry)
        }
        #expect(service.getCommandHistory().count == 50)
    }

    @Test("clearCommandHistory removes all entries")
    func testClearCommandHistory() {
        let service = CLIWorkshopService()
        let entry = CLICommandHistoryEntry(toolName: "t", rawCommand: "c", redactedCommand: "c")
        service.addCommandHistoryEntry(entry)
        service.clearCommandHistory()
        #expect(service.getCommandHistory().isEmpty)
    }

    // MARK: - 16.8 Educational Features

    @Test("experienceMode defaults to beginner")
    func testExperienceModeDefault() {
        let service = CLIWorkshopService()
        #expect(service.getExperienceMode() == .beginner)
    }

    @Test("setExperienceMode updates mode")
    func testSetExperienceMode() {
        let service = CLIWorkshopService()
        service.setExperienceMode(.advanced)
        #expect(service.getExperienceMode() == .advanced)
    }

    @Test("glossaryEntries defaults to non-empty")
    func testGlossaryEntriesDefault() {
        let service = CLIWorkshopService()
        #expect(!service.getGlossaryEntries().isEmpty)
    }

    @Test("glossarySearchQuery defaults to empty")
    func testGlossarySearchQueryDefault() {
        let service = CLIWorkshopService()
        #expect(service.getGlossarySearchQuery() == "")
    }

    @Test("setGlossarySearchQuery stores and retrieves")
    func testSetGlossarySearchQuery() {
        let service = CLIWorkshopService()
        service.setGlossarySearchQuery("AE")
        #expect(service.getGlossarySearchQuery() == "AE")
    }
}
