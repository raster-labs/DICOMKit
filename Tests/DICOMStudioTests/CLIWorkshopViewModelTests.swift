// CLIWorkshopViewModelTests.swift
// DICOMStudioTests
//
// DICOM Studio — Tests for CLI Tools Workshop ViewModel (Milestone 16)

import Testing
@testable import DICOMStudio
import Foundation
import DICOMKit
import DICOMCore
import DICOMNetwork
import DICOMWeb

@Suite("CLI Workshop ViewModel Tests")
@MainActor
struct CLIWorkshopViewModelTests {

    // MARK: - Initialization

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("ViewModel initializes with default state")
    func testInit() {
        let vm = CLIWorkshopViewModel()
        #expect(vm.activeTab == .fileInspection)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
        #expect(vm.networkProfiles.count == 1)
        #expect(vm.activeProfileID == nil)
        #expect(vm.connectionTestStatus == .untested)
        #expect(vm.tools.count == 33)
        #expect(vm.selectedToolID == nil)
        #expect(vm.parameterDefinitions.isEmpty)
        #expect(vm.parameterValues.isEmpty)
        #expect(vm.inputFiles.isEmpty)
        #expect(vm.outputPath == "")
        #expect(vm.fileDropState == .empty)
        #expect(vm.consoleStatus == .idle)
        #expect(vm.consoleOutput == "")
        #expect(vm.commandPreview == "")
        #expect(vm.commandHistory.isEmpty)
        #expect(vm.experienceMode == .beginner)
        #expect(!vm.glossaryEntries.isEmpty)
        #expect(vm.glossarySearchQuery == "")
    }

    // MARK: - 16.1 Network Configuration

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("addProfile increases profile count")
    func testAddProfile() {
        let vm = CLIWorkshopViewModel()
        let profile = CLINetworkProfile(name: "New")
        vm.addProfile(profile)
        #expect(vm.networkProfiles.count == 2)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("removeProfile decreases profile count")
    func testRemoveProfile() {
        let vm = CLIWorkshopViewModel()
        let profile = CLINetworkProfile(name: "ToRemove")
        vm.addProfile(profile)
        vm.removeProfile(id: profile.id)
        #expect(vm.networkProfiles.count == 1)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("removeProfile resets activeProfileID if removed profile was active")
    func testRemoveActiveProfile() {
        let vm = CLIWorkshopViewModel()
        let profile = CLINetworkProfile(name: "Active")
        vm.addProfile(profile)
        vm.setActiveProfile(id: profile.id)
        vm.removeProfile(id: profile.id)
        #expect(vm.activeProfileID != profile.id)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("updateProfile updates matching profile fields")
    func testUpdateProfile() {
        let vm = CLIWorkshopViewModel()
        var profile = CLINetworkProfile(name: "Original")
        vm.addProfile(profile)
        profile.name = "Updated"
        vm.updateProfile(profile)
        let updated = vm.networkProfiles.first { $0.id == profile.id }
        #expect(updated?.name == "Updated")
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("activeProfile returns first profile when no activeProfileID set")
    func testActiveProfileDefault() {
        let vm = CLIWorkshopViewModel()
        let profile = vm.activeProfile()
        #expect(profile != nil)
        #expect(profile?.name == "Default")
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("activeConnectionSummary returns formatted string")
    func testActiveConnectionSummary() {
        let vm = CLIWorkshopViewModel()
        let summary = vm.activeConnectionSummary()
        #expect(summary.contains("DICOMSTUDIO"))
        #expect(summary.contains("ANY-SCP"))
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("updateConnectionTestStatus changes status")
    func testUpdateConnectionTestStatus() {
        let vm = CLIWorkshopViewModel()
        vm.updateConnectionTestStatus(.success)
        #expect(vm.connectionTestStatus == .success)
    }

    // MARK: - 16.2 Tool Selection

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("selectTool updates selectedToolID")
    func testSelectTool() {
        let vm = CLIWorkshopViewModel()
        vm.selectTool(id: "dicom-info")
        #expect(vm.selectedToolID == "dicom-info")
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("selectTool resets parameters and console")
    func testSelectToolResetsState() {
        let vm = CLIWorkshopViewModel()
        vm.parameterValues = [CLIParameterValue(parameterID: "x", stringValue: "y")]
        vm.consoleOutput = "old output"
        vm.selectTool(id: "dicom-info")
        // The previous tool's parameters are cleared...
        #expect(!vm.parameterValues.contains { $0.parameterID == "x" })
        // ...and replaced by the new tool's pre-populated defaults (e.g. --format text).
        #expect(vm.parameterValues.contains { $0.parameterID == "format" && $0.stringValue == "text" })
        #expect(vm.consoleOutput == "")
        #expect(vm.consoleStatus == .idle)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("selectedTool returns matching tool")
    func testSelectedTool() {
        let vm = CLIWorkshopViewModel()
        vm.selectTool(id: "dicom-info")
        let tool = vm.selectedTool()
        #expect(tool != nil)
        #expect(tool?.name == "dicom-info")
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("selectedTool returns nil when no tool selected")
    func testSelectedToolNil() {
        let vm = CLIWorkshopViewModel()
        #expect(vm.selectedTool() == nil)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("toolsForActiveTab returns tools for current tab")
    func testToolsForActiveTab() {
        let vm = CLIWorkshopViewModel()
        vm.activeTab = .fileInspection
        let tools = vm.toolsForActiveTab()
        #expect(tools.count == 4)
        for tool in tools {
            #expect(tool.category == .fileInspection)
        }
    }

    // MARK: - 16.3 Parameter Configuration

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("updateParameterValue creates new entry if missing")
    func testUpdateParameterValueCreates() {
        let vm = CLIWorkshopViewModel()
        vm.updateParameterValue(parameterID: "format", value: "json")
        #expect(vm.parameterValues.count == 1)
        #expect(vm.parameterValues[0].stringValue == "json")
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("updateParameterValue updates existing entry")
    func testUpdateParameterValueUpdates() {
        let vm = CLIWorkshopViewModel()
        vm.updateParameterValue(parameterID: "format", value: "json")
        vm.updateParameterValue(parameterID: "format", value: "csv")
        #expect(vm.parameterValues.count == 1)
        #expect(vm.parameterValues[0].stringValue == "csv")
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("isCommandValid returns true when required params are satisfied")
    func testIsCommandValidTrue() {
        let vm = CLIWorkshopViewModel()
        vm.setParameterDefinitions([
            CLIParameterDefinition(id: "input", flag: "", displayName: "Input", parameterType: .filePath, isRequired: true)
        ])
        vm.updateParameterValue(parameterID: "input", value: "file.dcm")
        #expect(vm.isCommandValid == true)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("isCommandValid returns false when required params are missing")
    func testIsCommandValidFalse() {
        let vm = CLIWorkshopViewModel()
        vm.setParameterDefinitions([
            CLIParameterDefinition(id: "input", flag: "", displayName: "Input", parameterType: .filePath, isRequired: true)
        ])
        #expect(vm.isCommandValid == false)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("visibleParameters in beginner mode hides advanced params")
    func testVisibleParametersBeginner() {
        let vm = CLIWorkshopViewModel()
        vm.setParameterDefinitions([
            CLIParameterDefinition(id: "input", flag: "", displayName: "Input", parameterType: .filePath, isAdvanced: false),
            CLIParameterDefinition(id: "force", flag: "--force-parse", displayName: "Force Parse", parameterType: .booleanToggle, isAdvanced: true),
        ])
        vm.experienceMode = .beginner
        let visible = vm.visibleParameters()
        #expect(visible.count == 1)
        #expect(visible[0].id == "input")
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("visibleParameters in advanced mode shows all params")
    func testVisibleParametersAdvanced() {
        let vm = CLIWorkshopViewModel()
        vm.setParameterDefinitions([
            CLIParameterDefinition(id: "input", flag: "", displayName: "Input", parameterType: .filePath, isAdvanced: false),
            CLIParameterDefinition(id: "force", flag: "--force-parse", displayName: "Force Parse", parameterType: .booleanToggle, isAdvanced: true),
        ])
        vm.experienceMode = .advanced
        let visible = vm.visibleParameters()
        #expect(visible.count == 2)
    }

    // MARK: - 16.4 File Drop Zone

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("addInputFile updates files and drop state")
    func testAddInputFile() {
        let vm = CLIWorkshopViewModel()
        let file = CLIFileEntry(path: "/f", filename: "scan.dcm")
        vm.addInputFile(file)
        #expect(vm.inputFiles.count == 1)
        #expect(vm.fileDropState == .selected)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("removeInputFile resets drop state when empty")
    func testRemoveInputFile() {
        let vm = CLIWorkshopViewModel()
        let file = CLIFileEntry(path: "/f", filename: "scan.dcm")
        vm.addInputFile(file)
        vm.removeInputFile(id: file.id)
        #expect(vm.inputFiles.isEmpty)
        #expect(vm.fileDropState == .empty)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("updateFileDropState changes state")
    func testUpdateFileDropState() {
        let vm = CLIWorkshopViewModel()
        vm.updateFileDropState(.dragHover)
        #expect(vm.fileDropState == .dragHover)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("updateOutputPath stores path")
    func testUpdateOutputPath() {
        let vm = CLIWorkshopViewModel()
        vm.updateOutputPath("/output")
        #expect(vm.outputPath == "/output")
    }

    // MARK: - 16.5 Console

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("rebuildCommandPreview generates correct preview")
    func testRebuildCommandPreview() {
        let vm = CLIWorkshopViewModel()
        vm.selectTool(id: "dicom-info")
        vm.setParameterDefinitions([
            CLIParameterDefinition(id: "format", flag: "--format", displayName: "Format", parameterType: .enumPicker)
        ])
        vm.updateParameterValue(parameterID: "format", value: "json")
        #expect(vm.commandPreview.contains("dicom-info"))
        #expect(vm.commandPreview.contains("--format"))
        #expect(vm.commandPreview.contains("json"))
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("rebuildCommandPreview is empty when no tool selected")
    func testRebuildCommandPreviewNoTool() {
        let vm = CLIWorkshopViewModel()
        vm.rebuildCommandPreview()
        #expect(vm.commandPreview == "")
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("commandTokens returns tokens for current preview")
    func testCommandTokens() {
        let vm = CLIWorkshopViewModel()
        vm.selectTool(id: "dicom-info")
        vm.setParameterDefinitions([
            CLIParameterDefinition(id: "format", flag: "--format", displayName: "Format", parameterType: .enumPicker)
        ])
        vm.updateParameterValue(parameterID: "format", value: "json")
        let tokens = vm.commandTokens()
        #expect(!tokens.isEmpty)
        #expect(tokens[0].tokenType == .toolName)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("clearConsoleOutput resets output and status")
    func testClearConsoleOutput() {
        let vm = CLIWorkshopViewModel()
        vm.consoleOutput = "some output"
        vm.consoleStatus = .success
        vm.clearConsoleOutput()
        #expect(vm.consoleOutput == "")
        #expect(vm.consoleStatus == .idle)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("appendConsoleOutput accumulates text")
    func testAppendConsoleOutput() {
        let vm = CLIWorkshopViewModel()
        vm.appendConsoleOutput("Line 1\n")
        vm.appendConsoleOutput("Line 2\n")
        #expect(vm.consoleOutput == "Line 1\nLine 2\n")
    }

    // MARK: - 16.6 Command History

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("addToHistory creates entry with PHI redaction")
    func testAddToHistory() {
        let vm = CLIWorkshopViewModel()
        vm.addToHistory(toolName: "dicom-anon", command: "dicom-anon --patient-name \"John Doe\" file.dcm",
                        exitCode: 0, output: "Done")
        #expect(vm.commandHistory.count == 1)
        #expect(vm.commandHistory[0].redactedCommand.contains("<redacted>"))
        #expect(!vm.commandHistory[0].redactedCommand.contains("John Doe"))
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("addToHistory sets completed state on exit code 0")
    func testAddToHistorySuccess() {
        let vm = CLIWorkshopViewModel()
        vm.addToHistory(toolName: "t", command: "c", exitCode: 0, output: "")
        #expect(vm.commandHistory[0].executionState == .completed)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("addToHistory sets failed state on non-zero exit code")
    func testAddToHistoryFailure() {
        let vm = CLIWorkshopViewModel()
        vm.addToHistory(toolName: "t", command: "c", exitCode: 1, output: "")
        #expect(vm.commandHistory[0].executionState == .failed)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("clearHistory removes all entries")
    func testClearHistory() {
        let vm = CLIWorkshopViewModel()
        vm.addToHistory(toolName: "t", command: "c", exitCode: 0, output: "")
        vm.clearHistory()
        #expect(vm.commandHistory.isEmpty)
    }

    // MARK: - 16.8 Educational Features

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("toggleExperienceMode switches between modes")
    func testToggleExperienceMode() {
        let vm = CLIWorkshopViewModel()
        #expect(vm.experienceMode == .beginner)
        vm.toggleExperienceMode()
        #expect(vm.experienceMode == .advanced)
        vm.toggleExperienceMode()
        #expect(vm.experienceMode == .beginner)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("setExperienceMode directly sets mode")
    func testSetExperienceMode() {
        let vm = CLIWorkshopViewModel()
        vm.setExperienceMode(.advanced)
        #expect(vm.experienceMode == .advanced)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("filteredGlossaryEntries returns all for empty query")
    func testFilteredGlossaryAll() {
        let vm = CLIWorkshopViewModel()
        let all = vm.filteredGlossaryEntries()
        #expect(all.count == vm.glossaryEntries.count)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("filteredGlossaryEntries filters by query")
    func testFilteredGlossaryQuery() {
        let vm = CLIWorkshopViewModel()
        vm.updateGlossarySearch("AE Title")
        let filtered = vm.filteredGlossaryEntries()
        #expect(filtered.count >= 1)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("examplePresetsForSelectedTool returns presets for known tool")
    func testExamplePresetsForTool() {
        let vm = CLIWorkshopViewModel()
        vm.selectTool(id: "dicom-info")
        let presets = vm.examplePresetsForSelectedTool()
        #expect(!presets.isEmpty)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("examplePresetsForSelectedTool returns empty when no tool selected")
    func testExamplePresetsNoTool() {
        let vm = CLIWorkshopViewModel()
        let presets = vm.examplePresetsForSelectedTool()
        #expect(presets.isEmpty)
    }

    // MARK: - File-tool executor helpers mirror the dicom-* CLIs (DICOM 2026a)

    @Test("WorkshopFileSetRules: File-set ID default and refusal follow PS3.10 8.1 / 8.5 (D132)")
    func fileSetRules() {
        #expect(WorkshopFileSetRules.defaultFileSetID(fromDirectoryName: "my study-01") == "MY_STUDY_01")
        #expect(WorkshopFileSetRules.defaultFileSetID(fromDirectoryName: "ABCDEFGHIJKLMNOPQRSTUVWXYZ").count == 16)
        #expect(WorkshopFileSetRules.fileSetIDRefusal("STUDY_01") == nil)
        #expect(WorkshopFileSetRules.fileSetIDRefusal("") == nil)                       // (0004,1130) is Type 2
        #expect(WorkshopFileSetRules.fileSetIDRefusal("study-01")?.hasPrefix("Refusing --file-set-id:") == true)
        #expect(WorkshopFileSetRules.fileSetIDRefusal(String(repeating: "A", count: 17))?.contains("at most 16") == true)
        #expect(WorkshopFileSetRules.fileIDViolations(["DICOM", "IM000001"]).isEmpty)
        #expect(!WorkshopFileSetRules.fileIDViolations(["img1.dcm"]).isEmpty)           // '.' is outside PS3.10 8.5
        #expect(!WorkshopFileSetRules.fileIDViolations(["ABCDEFGHI"]).isEmpty)          // 9 characters (PS3.10 8.2)
    }

    @Test("WorkshopFileSetRules: a deprecated --profile spelling gets the CLI's note; a PS3.11 identifier none (D29)")
    func profileDeprecationNote() throws {
        let resolved = try #require(DICOMDIRProfile(rawValue: "STD-GEN-DVD"))
        let note = WorkshopFileSetRules.profileDeprecationNote(requested: "STD-GEN-DVD", resolved: resolved)
        #expect(note?.contains("--profile STD-GEN-DVD is deprecated") == true)
        #expect(note?.contains("PS3.11 2026a Table H.1-1") == true)
        #expect(WorkshopFileSetRules.profileDeprecationNote(requested: "STD-GEN-CD", resolved: .standardGeneralCD) == nil)
    }

    @Test("dicom-export animate rate: --fps, else Recommended Display Frame Rate, Cine Rate, 1000 / Frame Time, else 10 (PS3.3 Table C.7-13)")
    func exportCineFrameRate() {
        var ds = DataSet()
        #expect(CLIWorkshopViewModel.exportCineFrameRate(explicit: nil, dataSet: ds).fps == 10)
        #expect(CLIWorkshopViewModel.exportCineFrameRate(explicit: 12, dataSet: ds).source == "--fps")
        ds.setString("40", for: .frameTime, vr: .DS)
        let fromFrameTime = CLIWorkshopViewModel.exportCineFrameRate(explicit: nil, dataSet: ds)
        #expect(fromFrameTime.fps == 25)
        #expect(fromFrameTime.source == "Frame Time (0018,1063)")
        ds.setString("30", for: .cineRate, vr: .IS)
        #expect(CLIWorkshopViewModel.exportCineFrameRate(explicit: nil, dataSet: ds).fps == 30)
        ds.setString("15", for: .recommendedDisplayFrameRate, vr: .IS)
        let preferred = CLIWorkshopViewModel.exportCineFrameRate(explicit: nil, dataSet: ds)
        #expect(preferred.fps == 15)
        #expect(preferred.source == "Recommended Display Frame Rate (0008,2144)")
    }

    @Test("dicom-export texts equal the CLI's (P-EXPORT-1, P-EXPORT-3, Burned In Annotation (0028,0301))")
    func exportTexts() {
        #expect(CLIWorkshopViewModel.exportFrameDeprecationNote(option: "--frame", replacement: "--frame-number")
                == "warning: --frame is deprecated (0-based index); use --frame-number (numbered from 1, PS3.3 Table 10-3: the first Frame is Frame number 1)")
        #expect(CLIWorkshopViewModel.exportInvalidFrameNumberMessage(requested: 5, total: 3)
                == "Frame number 5 does not exist. The file has 3 frames, numbered 1 to 3.")
        #expect(CLIWorkshopViewModel.exportFrameSelectionConflict(zeroBased: "--frame", oneBased: "--frame-number")
                == "--frame (deprecated, 0-based) and --frame-number (numbered from 1) cannot be used together")
        #expect(CLIWorkshopViewModel.exportApplyWindowDeprecationNote(subcommand: "bulk").hasPrefix("warning: bulk --apply-window is deprecated"))
        var ds = DataSet()
        #expect(!CLIWorkshopViewModel.exportBurnedInAnnotationIsYes(ds))
        ds.setString("YES", for: .burnedInAnnotation, vr: .CS)
        #expect(CLIWorkshopViewModel.exportBurnedInAnnotationIsYes(ds))
        #expect(CLIWorkshopViewModel.exportBurnedInWarning(for: "a.dcm").contains("a.dcm: Burned In Annotation (0028,0301) is YES"))
    }

    @Test("dicom-archive --study-date warning: a DA value or DA range (PS3.4 C.2.2.2.5.1) is silent")
    func archiveStudyDateWarning() {
        #expect(CLIWorkshopViewModel.archiveStudyDateWarning(nil) == nil)
        #expect(CLIWorkshopViewModel.archiveStudyDateWarning("20240102") == nil)
        #expect(CLIWorkshopViewModel.archiveStudyDateWarning("20240101-20240201") == nil)
        #expect(CLIWorkshopViewModel.archiveStudyDateWarning("-20240201") == nil)
        #expect(CLIWorkshopViewModel.archiveStudyDateWarning("2024")?.hasPrefix("warning: --study-date '2024'") == true)
    }

    @Test("dicom-dump tag argument: 0010,0010, (0010,0010), 00100010 or a PS3.6 keyword")
    func dumpTagParsing() {
        let patientName = Tag(group: 0x0010, element: 0x0010)
        #expect(CLIWorkshopViewModel.parseDumpTagStr("0010,0010") == patientName)
        #expect(CLIWorkshopViewModel.parseDumpTagStr("(0010,0010)") == patientName)
        #expect(CLIWorkshopViewModel.parseDumpTagStr("00100010") == patientName)
        #expect(CLIWorkshopViewModel.parseDumpTagStr("PatientName") == patientName)
        #expect(CLIWorkshopViewModel.parseDumpTagStr("nonsense") == nil)
        #expect(CLIWorkshopViewModel.dumpInvalidTagMessage("x")
                == "Error: Invalid tag format: x. Use format: 0010,0010 or a PS3.6 keyword such as PatientName\n")
    }

    @Test("dicom-json / dicom-xml --filter-tag forms and deprecation notes (PS3.18 F.2.2; PS3.19 Table A.1.5-2)")
    func dataExchangeHelpers() {
        #expect(CLIWorkshopViewModel.normalizedDataExchangeFilterTags(["00100020", "(0008,0016)", "PatientName", "0010,0010"])
                == ["0010,0020", "0008,0016", "PatientName", "0010,0010"])
        #expect(CLIWorkshopViewModel.dataExchangeDeprecationNotes(toolName: "dicom-json", noSortKeys: true, noKeywords: false)
                == ["dicom-json: warning: --no-sort-keys is deprecated and will be removed: PS3.18 2026a F.2.2 requires attribute objects in ascending tag order"])
        #expect(CLIWorkshopViewModel.dataExchangeDeprecationNotes(toolName: "dicom-xml", noSortKeys: false, noKeywords: true)
                == ["dicom-xml: warning: --no-keywords is deprecated and will be removed: PS3.19 2026a Table A.1.5-2 requires the keyword attribute for every PS3.6 Data Element"])
        #expect(CLIWorkshopViewModel.dataExchangeDeprecationNotes(toolName: "dicom-json", noSortKeys: false, noKeywords: false).isEmpty)
    }

    @Test("dicom-uid --root: PS3.5 9.1 syntax (digits, single dots, no leading zero) and room for the generated suffix")
    func uidRootProblems() {
        #expect(CLIWorkshopViewModel.uidRootProblems(root: "1.2.826.0.1.3680043", typed: false).isEmpty)
        #expect(CLIWorkshopViewModel.uidRootProblems(root: "1..2", typed: false).first?.contains("empty component") == true)
        #expect(CLIWorkshopViewModel.uidRootProblems(root: "1.02", typed: false).first?.contains("leading zero") == true)
        #expect(CLIWorkshopViewModel.uidRootProblems(root: "1.a", typed: false).first?.contains("not a number") == true)
        #expect(CLIWorkshopViewModel.uidRootProblems(root: String(repeating: "1.", count: 30) + "1", typed: true)
                .contains { $0.contains("may not exceed 64") })
    }

    @Test("dicom-validate --iod: PS3.6 Table A-1 keyword or UID resolves to the engine IOD name")
    func validateIODEngineName() {
        #expect(CLIWorkshopViewModel.validateIODEngineName(for: "CTImageStorage") == "CTImageStorage")
        #expect(CLIWorkshopViewModel.validateIODEngineName(for: "1.2.840.10008.5.1.4.1.1.4") == "MRImageStorage")
        #expect(CLIWorkshopViewModel.validateIODEngineName(for: "ComputedRadiographyImageStorage") == "CRImageStorage")
        #expect(CLIWorkshopViewModel.validateIODEngineName(for: "us") == "USImageStorage")
        #expect(CLIWorkshopViewModel.validateIODEngineName(for: "BasicTextSRStorage") == "StructuredReport")
        #expect(CLIWorkshopViewModel.validateIODEngineName(for: "ct") == "ct")        // the engine's own short name passes through
    }

    // MARK: - Network tools (workshop-net, DICOM 2026a)

    @Test("dicom-query --level: patient/study/series/image → Query/Retrieve Level (0008,0052); 'instance' is the CLI alias of IMAGE (PS3.4 Table C.6.1-1)")
    func queryLevelOption() {
        #expect(CLIWorkshopViewModel.queryLevelOption("patient") == .patient)
        #expect(CLIWorkshopViewModel.queryLevelOption("study") == .study)
        #expect(CLIWorkshopViewModel.queryLevelOption("series") == .series)
        #expect(CLIWorkshopViewModel.queryLevelOption("image") == .image)
        #expect(CLIWorkshopViewModel.queryLevelOption("instance") == .image)
        #expect(CLIWorkshopViewModel.queryLevelOption("IMAGE")?.rawValue == "IMAGE")
        #expect(CLIWorkshopViewModel.queryLevelOption("frame") == nil)
    }

    @Test("dicom-query validate(): SERIES needs --study-uid, IMAGE needs both (PS3.4 C.4.1.2.1) with the CLI's texts")
    func queryLevelRefusal() {
        #expect(CLIWorkshopViewModel.queryLevelRefusal(level: .study, studyUID: "", seriesUID: "") == nil)
        #expect(CLIWorkshopViewModel.queryLevelRefusal(level: .series, studyUID: "", seriesUID: "")
                == "--level series requires --study-uid (PS3.4 C.4.1.2.1: the Study Instance UID of the level above must be given)")
        #expect(CLIWorkshopViewModel.queryLevelRefusal(level: .series, studyUID: "1.2.3", seriesUID: "") == nil)
        #expect(CLIWorkshopViewModel.queryLevelRefusal(level: .image, studyUID: "1.2.3", seriesUID: "")
                == "--level image (instance) requires --study-uid and --series-uid (PS3.4 C.4.1.2.1)")
        #expect(CLIWorkshopViewModel.queryLevelRefusal(level: .image, studyUID: "1.2.3", seriesUID: "1.2.3.4") == nil)
    }

    @Test("dicom-query --format dicom-json renders the PS3.18 F.2 DICOM JSON Model through DICOMWeb's encoder; --csv-keywords names columns by PS3.6 keyword")
    func queryResultFormatter() {
        let fmt = CLIWorkshopViewModel.queryResultFormatter(format: .dicomJSON, level: .study, csvKeywords: false)
        #expect(fmt.dicomJSONEncoder != nil)
        #expect(fmt.csvHeader == .tag)
        let csv = CLIWorkshopViewModel.queryResultFormatter(format: .csv, level: .study, csvKeywords: true)
        #expect(csv.csvHeader == .keyword)
    }

    @Test("--modality runs through the shared ModalityOptionValidator: alias noted only with --verbose, unknown warned and sent, rejected under --strict-modality")
    func resolveModalityOption() {
        let ct = CLIWorkshopViewModel.resolveModalityOption("CT", strict: true, verbose: true)
        #expect(ct.value == "CT" && ct.lines.isEmpty && ct.error == nil)
        let alias = CLIWorkshopViewModel.resolveModalityOption("MRI", strict: false, verbose: false)
        #expect(alias.value == "MR" && alias.lines.isEmpty && alias.error == nil)
        #expect(CLIWorkshopViewModel.resolveModalityOption("MRI", strict: false, verbose: true).lines.count == 1)
        let unknown = CLIWorkshopViewModel.resolveModalityOption("ZZ", strict: false, verbose: false)
        #expect(unknown.value == "ZZ" && unknown.error == nil)
        #expect(unknown.lines.first?.hasPrefix("warning: ") == true && unknown.lines.first?.hasSuffix(" Sending it as-is.") == true)
        let strict = CLIWorkshopViewModel.resolveModalityOption("ZZ", strict: true, verbose: false)
        #expect(strict.error?.hasSuffix(" Rejected because --strict-modality is set.") == true)
        #expect(CLIWorkshopViewModel.resolveModalityOption("", strict: true, verbose: false).error == nil)
    }

    @Test("dicom-send classes a C-STORE response per PS3.4 Table B.2-1: 0000 stored, B000/B006/B007 stored with warning, A7xx/A9xx/Cxxx/0122 not stored")
    func sendStoreOutcomeClasses() {
        typealias Outcome = CLIWorkshopViewModel.WorkshopStoreOutcome
        #expect(Outcome(status: .from(0x0000)) == .stored)
        for warning: UInt16 in [0xB000, 0xB006, 0xB007] {
            #expect(Outcome(status: .from(warning)) == .storedWithWarning, Comment(rawValue: String(warning, radix: 16)))
        }
        for failure: UInt16 in [0xA700, 0xA900, 0xC000, 0xC123, 0x0122] {
            #expect(Outcome(status: .from(failure)) == .failed, Comment(rawValue: String(failure, radix: 16)))
        }
        // The CLI's SendError texts, printed as `Error: …`.
        #expect(CLIWorkshopViewModel.sendStoreFailedText(.from(0xA700)).hasSuffix(" — not stored (PS3.4 Table B.2-1)"))
        #expect(CLIWorkshopViewModel.sendStoreFailedText(.from(0xA700)).hasPrefix("C-STORE response status "))
        #expect(CLIWorkshopViewModel.sendPartialFailureText(succeeded: 2, failed: 1) == "Send completed with 2 succeeded and 1 failed")
    }

    @Test("dicom-retrieve / dicom-qr --priority words → Priority (0000,0700) LOW 0002H / MEDIUM 0000H / HIGH 0001H (PS3.7 Tables 9.3-9 / 9.3-6)")
    func retrievePriorityOption() {
        #expect(CLIWorkshopViewModel.retrievePriorityOption("low") == .low)
        #expect(CLIWorkshopViewModel.retrievePriorityOption("medium") == .medium)
        #expect(CLIWorkshopViewModel.retrievePriorityOption("high") == .high)
        #expect(CLIWorkshopViewModel.retrievePriorityOption("") == .medium)
        #expect(CLIWorkshopViewModel.retrievePriorityOption("low").rawValue == 0x0002)
        #expect(CLIWorkshopViewModel.retrievePriorityOption("medium").rawValue == 0x0000)
        #expect(CLIWorkshopViewModel.retrievePriorityOption("high").rawValue == 0x0001)
    }

    @Test("dicom-retrieve UID rules: baseline needs the Unique Keys of the levels above (PS3.4 C.4.2.2.1); --relational-retrieve relaxes them (C.4.2.2.2.1) — the CLI's texts")
    func retrieveUIDRefusal() {
        typealias VM = CLIWorkshopViewModel
        #expect(VM.retrieveUIDRefusal(studyUID: "", seriesUID: "", instanceUID: "", uidList: "", relationalRetrieve: false)
                == "Must specify either --study-uid or --uid-list")
        #expect(VM.retrieveUIDRefusal(studyUID: "", seriesUID: "", instanceUID: "", uidList: "", relationalRetrieve: true)
                == "Must specify --study-uid, --series-uid, --instance-uid or --uid-list")
        // Without --study-uid (or --uid-list) the CLI's first guard answers; the per-level texts
        // are reached when a --uid-list run also names a series / instance without its parents.
        #expect(VM.retrieveUIDRefusal(studyUID: "", seriesUID: "1.2", instanceUID: "", uidList: "", relationalRetrieve: false)
                == "Must specify either --study-uid or --uid-list")
        #expect(VM.retrieveUIDRefusal(studyUID: "", seriesUID: "1.2", instanceUID: "", uidList: "uids.txt", relationalRetrieve: false)
                == "--series-uid requires --study-uid (PS3.4 C.4.2.2.1), or --relational-retrieve")
        #expect(VM.retrieveUIDRefusal(studyUID: "1", seriesUID: "", instanceUID: "1.2.3", uidList: "", relationalRetrieve: false)
                == "--instance-uid requires both --study-uid and --series-uid (PS3.4 C.4.2.2.1), or --relational-retrieve")
        #expect(VM.retrieveUIDRefusal(studyUID: "", seriesUID: "1.2", instanceUID: "", uidList: "", relationalRetrieve: true) == nil)
        #expect(VM.retrieveUIDRefusal(studyUID: "1", seriesUID: "1.2", instanceUID: "1.2.3", uidList: "", relationalRetrieve: false) == nil)
        #expect(VM.retrieveUIDRefusal(studyUID: "", seriesUID: "", instanceUID: "", uidList: "uids.txt", relationalRetrieve: false) == nil)
        // The Identifier's level follows the most specific UID (PS3.4 Table C.6.1-1).
        #expect(VM.retrieveKeys(studyUID: "1", seriesUID: nil, sopUID: nil).level == .study)
        #expect(VM.retrieveKeys(studyUID: nil, seriesUID: "1.2", sopUID: nil).level == .series)
        #expect(VM.retrieveKeys(studyUID: "1", seriesUID: "1.2", sopUID: "1.2.3").level == .image)
    }

    @Test("C-MOVE / C-GET final response: success only for 0000 with no failed sub-operations (PS3.4 C.4.2.2.1); failures worded by DIMSEServiceStatusText (Tables C.4-2 / C.4-3) with the PS3.7 counters")
    func retrieveCheckTexts() {
        typealias VM = CLIWorkshopViewModel
        let ok = RetrieveResult(status: .from(0x0000), progress: RetrieveProgress(completed: 3))
        #expect(VM.retrieveCheck(ok, service: .cMove).failure == nil)
        #expect(VM.retrieveCheck(ok, service: .cMove).lines.isEmpty)
        #expect(VM.qrRetrieveCheck(ok, service: .cGet).failure == nil)

        let warning = RetrieveResult(status: .from(0xB000), progress: RetrieveProgress(completed: 2, failed: 1),
                                     failedSOPInstanceUIDs: ["1.2.3"])
        let check = VM.retrieveCheck(warning, service: .cMove)
        let described = DIMSEServiceStatusText.describe(.from(0xB000), service: .cMove)
        let counts = DIMSEServiceStatusText.subOperationCounts(warning.progress)
        #expect(check.lines == ["Failed SOP Instance UID List (0008,0058), 1 UID(s):", "  1.2.3",
                                "Final C-MOVE response: " + described + " — " + counts])
        #expect(check.failure == "C-MOVE final response " + described + " (" + counts + "); Failed SOP Instance UID List (0008,0058): 1.2.3")
        #expect(described.hasPrefix("Warning (0xB000): "))
        #expect(counts == "Number of Completed Sub-operations: 2, Number of Failed Sub-operations: 1, Number of Warning Sub-operations: 0")

        let qr = VM.qrRetrieveCheck(warning, service: .cGet)
        let describedGet = DIMSEServiceStatusText.describe(.from(0xB000), service: .cGet)
        #expect(qr.lines == ["  Failed SOP Instance UID List (0008,0058):", "    1.2.3"])
        #expect(qr.failure == "Retrieval failed: C-GET final response " + describedGet + " (" + counts + "); Failed SOP Instance UID List (0008,0058): 1.2.3")

        // A failed sub-operation makes a 0000 status a failure too (PS3.4 C.4.2.2.1).
        let partial = RetrieveResult(status: .from(0x0000), progress: RetrieveProgress(completed: 1, failed: 1))
        #expect(VM.retrieveCheck(partial, service: .cGet).failure != nil)
    }

    @Test("dicom-mwl --sps-status: a PS3.3 Table C.4-10 Defined Term is silent; a PPS word (Table C.4-14) gets the CLI's warning")
    func mwlSPSStatusWarning() {
        #expect(CLIWorkshopViewModel.mwlScheduledProcedureStepStatusDefinedTerms == ["SCHEDULED", "ARRIVED", "READY", "STARTED", "DEPARTED"])
        for term in CLIWorkshopViewModel.mwlScheduledProcedureStepStatusDefinedTerms {
            #expect(CLIWorkshopViewModel.mwlSPSStatusWarning(term) == nil, Comment(rawValue: term))
        }
        #expect(CLIWorkshopViewModel.mwlSPSStatusWarning("") == nil)
        #expect(CLIWorkshopViewModel.mwlSPSStatusWarning(nil) == nil)
        let warning = CLIWorkshopViewModel.mwlSPSStatusWarning("COMPLETED")
        #expect(warning == "warning: --sps-status 'COMPLETED' is not a Scheduled Procedure Step Status Defined Term "
                + "(PS3.3 Table C.4-10: SCHEDULED, ARRIVED, READY, STARTED, DEPARTED); "
                + "it is sent as given and will match only an SCP that uses that private term\n")
    }

    @Test("dicom-mpps value rules: status words (PS3.3 Table C.4-14), Patient's Sex M/F/O (Table C.2-3), birth date DA (PS3.5 Table 6.2-1), warning wording via DIMSEServiceStatusText")
    func mppsValueRules() {
        typealias VM = CLIWorkshopViewModel
        #expect(VM.mppsStatusOption("IN PROGRESS") == .inProgress)
        #expect(VM.mppsStatusOption("in_progress") == .inProgress)
        #expect(VM.mppsStatusOption("completed") == .completed)
        #expect(VM.mppsStatusOption("DISCONTINUED") == .discontinued)
        #expect(VM.mppsStatusOption("STARTED") == nil)
        #expect(VM.mppsPatientSex("f").value == "F")
        #expect(VM.mppsPatientSex("").value == nil && VM.mppsPatientSex("").error == nil)
        #expect(VM.mppsPatientSex("U").error == "--patient-sex must be one of M, F, O (Patient's Sex (0010,0040) Enumerated Values, PS3.3 Table C.2-3), got 'U'")
        #expect(VM.mppsBirthDate("19800115").value == "19800115")
        #expect(VM.mppsBirthDate("1980-01-15").error == "--patient-birth-date must be YYYYMMDD (VR DA, PS3.5 Table 6.2-1), got '1980-01-15'")
        let line = VM.mppsWarningLine(.from(0x0107), operation: "N-SET")
        #expect(line == "warning: SCP completed the N-SET with "
                + DIMSEServiceStatusText.describe(.from(0x0107), service: .mppsNSet)
                + " — attributes may have been coerced or dropped\n")
        #expect(VM.mppsWarningLine(.from(0x0107), operation: "N-CREATE").contains(DIMSEServiceStatusText.describe(.from(0x0107), service: .dimseN)))
    }

    @Test("dicom-wado ups --state: IN PROGRESS / COMPLETED / CANCELED are Change State targets (PS3.18 11.7.1.4); SCHEDULED is refused with the CLI's text (PS3.4 Table CC.1.1-2, C303H), exit 1")
    func upsChangeStateRefusal() throws {
        typealias Rules = WorkshopWADOOptionRules
        #expect(try Rules.changeStateTarget("IN PROGRESS") == "IN PROGRESS")
        #expect(try Rules.changeStateTarget("in_progress") == "IN PROGRESS")
        #expect(try Rules.changeStateTarget("completed") == "COMPLETED")
        #expect(try Rules.changeStateTarget("CANCELED") == "CANCELED")
        #expect(Rules.changeStateTargets == ["IN PROGRESS", "COMPLETED", "CANCELED"])
        #expect(Rules.upsState("SCHEDULED") == "SCHEDULED")
        do {
            _ = try Rules.changeStateTarget("SCHEDULED")
            Issue.record("SCHEDULED must be refused")
        } catch let e as Rules.Refusal {
            #expect(e.exitCode == 1)
            #expect(e.message == "SCHEDULED is not a Change Workitem State target: PS3.18 2026a 11.7.1.4 "
                    + "allows IN PROGRESS, COMPLETED or CANCELED, and PS3.4 2026a Table CC.1.1-2 refuses a change "
                    + "to SCHEDULED (C303H)")
        }
        do {
            _ = try Rules.changeStateTarget("DONE")
            Issue.record("an unknown state must be refused")
        } catch let e as Rules.Refusal {
            #expect(e.message == "Invalid state: DONE. Valid states: IN PROGRESS (or IN_PROGRESS), COMPLETED, CANCELED (PS3.18 2026a 11.7.1.4)")
        }
        // --change-state / --update: one or the other (deprecated alias), never both.
        #expect(try Rules.changeStateWorkitem(changeState: "1.2", update: nil) == "1.2")
        #expect(try Rules.changeStateWorkitem(changeState: nil, update: "1.2") == "1.2")
        #expect(try Rules.changeStateWorkitem(changeState: nil, update: nil) == nil)
        #expect(throws: Rules.Refusal.self) { try Rules.changeStateWorkitem(changeState: "1", update: "2") }
        #expect(Rules.updateDeprecationNote.hasPrefix("Note: --update is deprecated; use --change-state"))
    }

    @Test("dicom-wado retrieve --uri rules: contentType per PS3.18 9.1.2.2.1 / Table 8.7.4-1, frameNumber a positive integer (9.5.1.2.1), limit / offset unsigned (8.3.4.4) — the CLI's texts")
    func wadoURIRules() throws {
        typealias Rules = WorkshopWADOOptionRules
        #expect(try Rules.uriContentType(nil) == .dicom)
        #expect(try Rules.uriContentType("") == .dicom)
        #expect(try Rules.uriContentType("image/jpeg") == .jpeg)
        #expect(try Rules.uriContentType("pdf") == .pdf)
        #expect(Rules.uriContentTypes.count == 15)                                   // application/dicom + 14 Rendered Media Types
        do {
            _ = try Rules.uriContentType("image/bmp")
            Issue.record("image/bmp is not a Rendered Media Type")
        } catch let e as Rules.Refusal {
            #expect(e.exitCode == 64)
            #expect(e.message.hasPrefix("--content-type 'image/bmp' cannot be requested over WADO-URI. Use one of: application/dicom, image/jpeg"))
            #expect(e.message.hasSuffix("(PS3.18 9.1.2.2.1: application/dicom or a Rendered Media Type of Table 8.7.4-1)"))
        }
        #expect(try Rules.uriFrameNumber(nil) == nil)
        #expect(try Rules.uriFrameNumber("3")?.frame == 3)
        #expect(try Rules.uriFrameNumber("2, 4, 6")?.notSent == 2)
        #expect(throws: Rules.Refusal.self) { try Rules.uriFrameNumber("0") }
        #expect(throws: Rules.Refusal.self) { try Rules.uriFrameNumber("a") }
        #expect(Rules.pagingProblem(limit: 0, offset: 0) == nil)
        #expect(Rules.pagingProblem(limit: -1, offset: 0) == "--limit must be 0 or more (PS3.18 8.3.4.4: limit is an unsigned integer)")
        #expect(Rules.pagingProblem(limit: 1, offset: -1) == "--offset must be 0 or more (PS3.18 8.3.4.4: offset is an unsigned integer)")
        let warnings = Rules.uriParameterWarnings(contentType: .dicom, frame: 1, rows: nil, columns: nil, transferSyntax: nil, anonymize: false)
        #expect(warnings == ["frameNumber (--frames) is a Retrieve Rendered Instance parameter (PS3.18 Table 9.5.1-1), not defined for application/dicom (Table 9.4.1-1); the server may ignore it"])
        #expect(Rules.timeouts(seconds: 90).readTimeout == 90)
    }
}
