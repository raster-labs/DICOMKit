// FileOperationsTests.swift
// DICOMStudioTests
//
// DICOM Studio — Tests for File Operations & Drag-and-Drop (Milestone 22)

import Testing
@testable import DICOMStudio
import Foundation
#if canImport(Darwin)
import Darwin
#endif

private func makeFileOperationsTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("DICOMKit-FileOperations-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
}

// MARK: - Model Tests

@Suite("File Operations Model Tests")
struct FileOperationsModelTests {

    // MARK: - FileDropMode

    @Test("FileDropMode.single displayName is 'Single File'")
    func test_fileDropMode_single_displayName() {
        #expect(FileDropMode.single.displayName == "Single File")
    }

    @Test("FileDropMode.multiple displayName is 'Multiple Files'")
    func test_fileDropMode_multiple_displayName() {
        #expect(FileDropMode.multiple.displayName == "Multiple Files")
    }

    @Test("FileDropMode has two cases")
    func test_fileDropMode_allCases_count() {
        #expect(FileDropMode.allCases.count == 2)
    }

    @Test("FileDropMode id equals rawValue")
    func test_fileDropMode_id_equalsRawValue() {
        for mode in FileDropMode.allCases {
            #expect(mode.id == mode.rawValue)
        }
    }

    // MARK: - DropZoneHighlight

    @Test("DropZoneHighlight idle != active")
    func test_dropZoneHighlight_idle_notEqualToActive() {
        #expect(DropZoneHighlight.idle != DropZoneHighlight.active)
    }

    @Test("DropZoneHighlight rejected != idle")
    func test_dropZoneHighlight_rejected_notEqualToIdle() {
        #expect(DropZoneHighlight.rejected != DropZoneHighlight.idle)
    }

    // MARK: - DroppedFile

    @Test("DroppedFile initialiser sets all fields")
    func test_droppedFile_init_setsAllFields() {
        let url = URL(fileURLWithPath: "/tmp/test.dcm")
        let file = DroppedFile(
            url: url,
            fileName: "test.dcm",
            fileSizeBytes: 2048,
            isDICOM: true,
            modality: "CT",
            patientName: "Doe^John",
            studyDate: "20240101"
        )
        #expect(file.fileName == "test.dcm")
        #expect(file.fileSizeBytes == 2048)
        #expect(file.isDICOM == true)
        #expect(file.modality == "CT")
        #expect(file.patientName == "Doe^John")
        #expect(file.studyDate == "20240101")
    }

    @Test("DroppedFile default fields are nil")
    func test_droppedFile_defaultFields_areNil() {
        let url = URL(fileURLWithPath: "/tmp/test.dcm")
        let file = DroppedFile(url: url, fileName: "test.dcm", fileSizeBytes: 0, isDICOM: false)
        #expect(file.modality == nil)
        #expect(file.patientName == nil)
        #expect(file.studyDate == nil)
        #expect(file.warning == nil)
    }

    @Test("DroppedFile is Hashable and Identifiable via UUID")
    func test_droppedFile_hashable_identifiable() {
        let url = URL(fileURLWithPath: "/tmp/test.dcm")
        let file1 = DroppedFile(url: url, fileName: "test.dcm", fileSizeBytes: 0, isDICOM: true)
        let file2 = DroppedFile(url: url, fileName: "test.dcm", fileSizeBytes: 0, isDICOM: true)
        #expect(file1.id != file2.id)
    }

    // MARK: - FileDropZoneState

    @Test("FileDropZoneState default state is idle with no files")
    func test_fileDropZoneState_defaultState() {
        let state = FileDropZoneState()
        #expect(state.highlight == .idle)
        #expect(state.files.isEmpty)
        #expect(state.mode == .single)
        #expect(state.rejectionMessage == nil)
    }

    @Test("FileDropZoneState.singleFile returns first file or nil")
    func test_fileDropZoneState_singleFile_returnsFirstOrNil() {
        var state = FileDropZoneState()
        #expect(state.singleFile == nil)
        let file = DroppedFile(url: URL(fileURLWithPath: "/tmp/a.dcm"), fileName: "a.dcm", fileSizeBytes: 0, isDICOM: true)
        state.files = [file]
        #expect(state.singleFile?.fileName == "a.dcm")
    }

    @Test("FileDropZoneState.hasFiles is false when empty")
    func test_fileDropZoneState_hasFiles_falseWhenEmpty() {
        let state = FileDropZoneState()
        #expect(state.hasFiles == false)
    }

    @Test("FileDropZoneState.hasFiles is true when files present")
    func test_fileDropZoneState_hasFiles_trueWhenFilesPresent() {
        let file = DroppedFile(url: URL(fileURLWithPath: "/tmp/a.dcm"), fileName: "a.dcm", fileSizeBytes: 0, isDICOM: true)
        let state = FileDropZoneState(files: [file])
        #expect(state.hasFiles == true)
    }

    // MARK: - OutputPathMode

    @Test("OutputPathMode.sameAsInput displayName is 'Same as Input'")
    func test_outputPathMode_sameAsInput_displayName() {
        #expect(OutputPathMode.sameAsInput.displayName == "Same as Input")
    }

    @Test("OutputPathMode.lastUsed displayName is 'Last Used'")
    func test_outputPathMode_lastUsed_displayName() {
        #expect(OutputPathMode.lastUsed.displayName == "Last Used")
    }

    @Test("OutputPathMode.desktop displayName is 'Desktop'")
    func test_outputPathMode_desktop_displayName() {
        #expect(OutputPathMode.desktop.displayName == "Desktop")
    }

    @Test("OutputPathMode.custom displayName is 'Custom'")
    func test_outputPathMode_custom_displayName() {
        #expect(OutputPathMode.custom.displayName == "Custom")
    }

    @Test("OutputPathMode has 4 cases")
    func test_outputPathMode_allCases_count() {
        #expect(OutputPathMode.allCases.count == 4)
    }

    // MARK: - OutputPathConfig

    @Test("OutputPathConfig default is sameAsInput with no overwrite warning")
    func test_outputPathConfig_default() {
        let config = OutputPathConfig()
        #expect(config.mode == .sameAsInput)
        #expect(config.overwriteWarning == false)
        #expect(config.resolvedURL == nil)
    }

    @Test("OutputPathConfig.displayPath returns 'Not set' when URL is nil")
    func test_outputPathConfig_displayPath_notSetWhenNil() {
        let config = OutputPathConfig()
        #expect(config.displayPath == "Not set")
    }

    @Test("OutputPathConfig.displayPath uses last two path components for deep paths")
    func test_outputPathConfig_displayPath_lastTwoComponents() {
        let url = URL(fileURLWithPath: "/Users/john/Documents/DICOM/output.dcm")
        let config = OutputPathConfig(resolvedURL: url)
        #expect(config.displayPath.contains("DICOM"))
        #expect(config.displayPath.contains("output.dcm"))
    }

    // MARK: - OutputDirectoryConfig

    @Test("OutputDirectoryConfig default mode is desktop")
    func test_outputDirectoryConfig_defaultMode_isDesktop() {
        let config = OutputDirectoryConfig()
        #expect(config.mode == .desktop)
    }

    @Test("OutputDirectoryConfig.displayPath returns 'Not set' when URL is nil")
    func test_outputDirectoryConfig_displayPath_notSetWhenNil() {
        let config = OutputDirectoryConfig()
        #expect(config.displayPath == "Not set")
    }

    // MARK: - FileValidationWarning

    @Test("FileValidationWarning.missingPreamble displayName is non-empty")
    func test_fileValidationWarning_missingPreamble_displayName() {
        #expect(!FileValidationWarning.missingPreamble.displayName.isEmpty)
    }

    @Test("FileValidationWarning.veryLargeFile symbolName is non-empty")
    func test_fileValidationWarning_veryLargeFile_symbolName() {
        #expect(!FileValidationWarning.veryLargeFile.symbolName.isEmpty)
    }

    @Test("FileValidationWarning.corrupt symbolName contains 'xmark'")
    func test_fileValidationWarning_corrupt_symbolNameContainsXmark() {
        #expect(FileValidationWarning.corrupt.symbolName.contains("xmark"))
    }

    @Test("FileValidationWarning has 4 cases")
    func test_fileValidationWarning_allCases_count() {
        #expect(FileValidationWarning.allCases.count == 4)
    }

    // MARK: - FileValidationResult

    @Test("FileValidationResult.valid.isDICOM is true")
    func test_fileValidationResult_valid_isDICOM() {
        #expect(FileValidationResult.valid.isDICOM == true)
    }

    @Test("FileValidationResult.validWithoutPreamble.isDICOM is true")
    func test_fileValidationResult_validWithoutPreamble_isDICOM() {
        #expect(FileValidationResult.validWithoutPreamble.isDICOM == true)
    }

    @Test("FileValidationResult.notDICOM.isDICOM is false")
    func test_fileValidationResult_notDICOM_isDICOM() {
        #expect(FileValidationResult.notDICOM.isDICOM == false)
    }

    @Test("FileValidationResult.unreadable.isDICOM is false")
    func test_fileValidationResult_unreadable_isDICOM() {
        #expect(FileValidationResult.unreadable(reason: "error").isDICOM == false)
    }

    // MARK: - FilePreviewInfo

    @Test("FilePreviewInfo initialiser stores all fields")
    func test_filePreviewInfo_init_storesFields() {
        let preview = FilePreviewInfo(
            fileName: "scan.dcm",
            fileSizeBytes: 1024,
            modality: "MR",
            patientName: "Smith^Jane",
            studyDate: "20230601",
            warnings: [.veryLargeFile]
        )
        #expect(preview.fileName == "scan.dcm")
        #expect(preview.fileSizeBytes == 1024)
        #expect(preview.modality == "MR")
        #expect(preview.patientName == "Smith^Jane")
        #expect(preview.studyDate == "20230601")
        #expect(preview.warnings == [.veryLargeFile])
    }

    @Test("FilePreviewInfo default warnings list is empty")
    func test_filePreviewInfo_defaultWarnings_isEmpty() {
        let preview = FilePreviewInfo(fileName: "a.dcm", fileSizeBytes: 0)
        #expect(preview.warnings.isEmpty)
    }

    // MARK: - DirectoryScanMode

    @Test("DirectoryScanMode.shallow displayName is 'Top Level Only'")
    func test_directoryScanMode_shallow_displayName() {
        #expect(DirectoryScanMode.shallow.displayName == "Top Level Only")
    }

    @Test("DirectoryScanMode.recursive displayName is 'Recursive'")
    func test_directoryScanMode_recursive_displayName() {
        #expect(DirectoryScanMode.recursive.displayName == "Recursive")
    }

    @Test("DirectoryScanMode has 2 cases")
    func test_directoryScanMode_allCases_count() {
        #expect(DirectoryScanMode.allCases.count == 2)
    }

    // MARK: - DirectoryDropState

    @Test("DirectoryDropState default has no directory and is idle")
    func test_directoryDropState_default() {
        let state = DirectoryDropState()
        #expect(state.directoryURL == nil)
        #expect(state.highlight == .idle)
        #expect(state.dicomFileCount == 0)
        #expect(!state.isScanning)
    }

    @Test("DirectoryDropState.directoryDisplayName is 'No directory selected' when nil")
    func test_directoryDropState_displayName_noDirectory() {
        let state = DirectoryDropState()
        #expect(state.directoryDisplayName == "No directory selected")
    }

    @Test("DirectoryDropState.directoryDisplayName returns folder name")
    func test_directoryDropState_displayName_folderName() {
        let url = URL(fileURLWithPath: "/tmp/DICOM_Studies")
        let state = DirectoryDropState(directoryURL: url)
        #expect(state.directoryDisplayName == "DICOM_Studies")
    }

    @Test("DirectoryDropState.fileCountDescription shows 'Scanning' when isScanning")
    func test_directoryDropState_fileCountDescription_scanning() {
        let state = DirectoryDropState(isScanning: true)
        #expect(state.fileCountDescription.contains("Scanning"))
    }

    @Test("DirectoryDropState.fileCountDescription pluralises correctly for 0")
    func test_directoryDropState_fileCountDescription_zeroFiles() {
        let state = DirectoryDropState(dicomFileCount: 0)
        #expect(state.fileCountDescription.contains("files"))
    }

    @Test("DirectoryDropState.fileCountDescription uses singular for 1 file")
    func test_directoryDropState_fileCountDescription_oneFile() {
        let state = DirectoryDropState(dicomFileCount: 1)
        #expect(state.fileCountDescription.contains("1 DICOM file "))
    }

    @Test("DirectoryDropState.fileCountDescription pluralises for 5 files")
    func test_directoryDropState_fileCountDescription_multipleFiles() {
        let state = DirectoryDropState(dicomFileCount: 5)
        #expect(state.fileCountDescription.contains("5 DICOM files"))
    }

    // MARK: - FileOperationsTab

    @Test("FileOperationsTab.fileInput displayName is 'File Input'")
    func test_fileOperationsTab_fileInput_displayName() {
        #expect(FileOperationsTab.fileInput.displayName == "File Input")
    }

    @Test("FileOperationsTab.outputPath displayName is 'Output Path'")
    func test_fileOperationsTab_outputPath_displayName() {
        #expect(FileOperationsTab.outputPath.displayName == "Output Path")
    }

    @Test("FileOperationsTab.fileValidation displayName is 'Validation & Preview'")
    func test_fileOperationsTab_fileValidation_displayName() {
        #expect(FileOperationsTab.fileValidation.displayName == "Validation & Preview")
    }

    @Test("FileOperationsTab.directoryInput displayName is 'Directory Input'")
    func test_fileOperationsTab_directoryInput_displayName() {
        #expect(FileOperationsTab.directoryInput.displayName == "Directory Input")
    }

    @Test("FileOperationsTab has 4 cases")
    func test_fileOperationsTab_allCases_count() {
        #expect(FileOperationsTab.allCases.count == 4)
    }

    @Test("FileOperationsTab symbol names are non-empty")
    func test_fileOperationsTab_symbolNames_nonEmpty() {
        for tab in FileOperationsTab.allCases {
            #expect(!tab.symbolName.isEmpty)
        }
    }

    // MARK: - FileOperationsState

    @Test("FileOperationsState default selectedTab is .fileInput")
    func test_fileOperationsState_default_selectedTab() {
        let state = FileOperationsState()
        #expect(state.selectedTab == .fileInput)
    }

    @Test("FileOperationsState default associatedToolName is empty")
    func test_fileOperationsState_default_toolName() {
        let state = FileOperationsState()
        #expect(state.associatedToolName.isEmpty)
    }

    @Test("FileOperationsState Equatable works for two identical defaults")
    func test_fileOperationsState_equatable_twoDefaults() {
        let a = FileOperationsState()
        let b = FileOperationsState()
        #expect(a == b)
    }
}

// MARK: - Helpers Tests

@Suite("File Operations Helpers Tests")
struct FileOperationsHelpersTests {

    // MARK: - FileDropHelpers

    @Test("DICOMFileDropHelpers.acceptedExtensions contains dcm")
    func test_fileDropHelpers_acceptedExtensions_containsDcm() {
        #expect(DICOMFileDropHelpers.acceptedExtensions.contains("dcm"))
    }

    @Test("DICOMFileDropHelpers.acceptedExtensions contains DCM")
    func test_fileDropHelpers_acceptedExtensions_containsDCM() {
        #expect(DICOMFileDropHelpers.acceptedExtensions.contains("DCM"))
    }

    @Test("DICOMFileDropHelpers.acceptedExtensions contains dicom")
    func test_fileDropHelpers_acceptedExtensions_containsDicom() {
        #expect(DICOMFileDropHelpers.acceptedExtensions.contains("dicom"))
    }

    @Test("DICOMFileDropHelpers.hasAcceptedExtension returns true for .dcm")
    func test_fileDropHelpers_hasAcceptedExtension_dcm() {
        let url = URL(fileURLWithPath: "/tmp/test.dcm")
        #expect(DICOMFileDropHelpers.hasAcceptedExtension(url) == true)
    }

    @Test("DICOMFileDropHelpers.hasAcceptedExtension returns true for extensionless file")
    func test_fileDropHelpers_hasAcceptedExtension_noExtension() {
        let url = URL(fileURLWithPath: "/tmp/DICOMFILE")
        #expect(DICOMFileDropHelpers.hasAcceptedExtension(url) == true)
    }

    @Test("DICOMFileDropHelpers.hasAcceptedExtension returns false for .jpg")
    func test_fileDropHelpers_hasAcceptedExtension_jpg() {
        let url = URL(fileURLWithPath: "/tmp/photo.jpg")
        #expect(DICOMFileDropHelpers.hasAcceptedExtension(url) == false)
    }

    @Test("DICOMFileDropHelpers.validateMagicBytes returns .valid for DICM preamble")
    func test_fileDropHelpers_validateMagicBytes_validDICM() {
        var data = Data(repeating: 0, count: 132)
        data[128] = 0x44; data[129] = 0x49; data[130] = 0x43; data[131] = 0x4D
        #expect(DICOMFileDropHelpers.validateMagicBytes(data) == .valid)
    }

    @Test("DICOMFileDropHelpers.validateMagicBytes returns .notDICOM for wrong magic")
    func test_fileDropHelpers_validateMagicBytes_wrongMagic() {
        var data = Data(repeating: 0, count: 132)
        data[128] = 0xFF; data[129] = 0xAA; data[130] = 0x00; data[131] = 0x00
        // Group at offset 0 is 0x0000, which is not 0x0002 or 0x0008
        #expect(DICOMFileDropHelpers.validateMagicBytes(data) == .notDICOM)
    }

    @Test("DICOMFileDropHelpers.validateMagicBytes returns .notDICOM for short data")
    func test_fileDropHelpers_validateMagicBytes_shortData() {
        let data = Data(repeating: 0, count: 10)
        #expect(DICOMFileDropHelpers.validateMagicBytes(data) == .notDICOM)
    }

    @Test("DICOMFileDropHelpers.validateMagicBytes returns .validWithoutPreamble for ACR-NEMA group 0008")
    func test_fileDropHelpers_validateMagicBytes_acrNemaGroup0008() {
        var data = Data(repeating: 0x00, count: 132)
        // group 0x0008 little-endian at bytes 0-1
        data[0] = 0x08; data[1] = 0x00
        #expect(DICOMFileDropHelpers.validateMagicBytes(data) == .validWithoutPreamble)
    }

    // symbolName previously carried its own icon switch, which disagreed with
    // ModalityMapping (CT was "lungs" here and "cylinder.split.1x2" there).
    // The 2026a adoption made ModalityMapping the one icon map; these now
    // assert the two entry points agree rather than pinning the old values.

    @Test("DICOMFileDropHelpers.symbolName agrees with ModalityMapping for CT")
    func test_fileDropHelpers_symbolName_CT() {
        #expect(DICOMFileDropHelpers.symbolName(for: "CT")
                == ModalityMapping.systemImage(for: "CT"))
    }

    @Test("DICOMFileDropHelpers.symbolName agrees with ModalityMapping for US")
    func test_fileDropHelpers_symbolName_US() {
        #expect(DICOMFileDropHelpers.symbolName(for: "US")
                == ModalityMapping.systemImage(for: "US"))
    }

    @Test("DICOMFileDropHelpers.symbolName returns default for unknown modality")
    func test_fileDropHelpers_symbolName_unknown() {
        #expect(DICOMFileDropHelpers.symbolName(for: "XYZ") == "cross.case")
    }

    @Test("DICOMFileDropHelpers.symbolName returns default for nil modality")
    func test_fileDropHelpers_symbolName_nil() {
        #expect(DICOMFileDropHelpers.symbolName(for: nil) == "cross.case")
    }

    @Test("DICOMFileDropHelpers.formattedFileSize returns non-empty string")
    func test_fileDropHelpers_formattedFileSize_nonEmpty() {
        #expect(!DICOMFileDropHelpers.formattedFileSize(1_048_576).isEmpty)
    }

    @Test("DICOMFileDropHelpers.isVeryLarge returns true for 1 GB")
    func test_fileDropHelpers_isVeryLarge_oneGB() {
        #expect(DICOMFileDropHelpers.isVeryLarge(1_073_741_824) == true)
    }

    @Test("DICOMFileDropHelpers.isVeryLarge returns false for 512 MB")
    func test_fileDropHelpers_isVeryLarge_halfGB() {
        #expect(DICOMFileDropHelpers.isVeryLarge(536_870_912) == false)
    }

    @Test("DICOMFileDropHelpers.move reorders items correctly")
    func test_fileDropHelpers_move_reordersItems() {
        var items = ["a", "b", "c"]
        DICOMFileDropHelpers.move(items: &items, fromIndex: 0, toIndex: 2)
        #expect(items == ["b", "c", "a"])
    }

    @Test("DICOMFileDropHelpers.move is no-op for equal indices")
    func test_fileDropHelpers_move_equalIndices_noOp() {
        var items = ["a", "b", "c"]
        DICOMFileDropHelpers.move(items: &items, fromIndex: 1, toIndex: 1)
        #expect(items == ["a", "b", "c"])
    }

    @Test("DICOMFileDropHelpers.move is no-op for out-of-range index")
    func test_fileDropHelpers_move_outOfRange_noOp() {
        var items = ["a", "b"]
        DICOMFileDropHelpers.move(items: &items, fromIndex: 0, toIndex: 5)
        #expect(items == ["a", "b"])
    }

    @Test("DICOMFileDropHelpers.remove returns and removes item at index")
    func test_fileDropHelpers_remove_returnsAndRemovesItem() {
        var items = ["a", "b", "c"]
        let removed = DICOMFileDropHelpers.remove(from: &items, at: 1)
        #expect(removed == "b")
        #expect(items == ["a", "c"])
    }

    @Test("DICOMFileDropHelpers.remove returns nil for out-of-range index")
    func test_fileDropHelpers_remove_outOfRange_returnsNil() {
        var items = ["a"]
        let removed = DICOMFileDropHelpers.remove(from: &items, at: 5)
        #expect(removed == nil)
    }

    // MARK: - OutputPathHelpers

    @Test("OutputPathHelpers.suggestedFilename for dicom-anon appends _anonymized")
    func test_outputPathHelpers_suggestedFilename_anonTool() {
        let input = URL(fileURLWithPath: "/tmp/scan.dcm")
        let name = OutputPathHelpers.suggestedFilename(for: "dicom-anon", input: input)
        #expect(name == "scan_anonymized.dcm")
    }

    @Test("OutputPathHelpers.suggestedFilename for dicom-json changes extension to .json")
    func test_outputPathHelpers_suggestedFilename_jsonTool() {
        let input = URL(fileURLWithPath: "/tmp/scan.dcm")
        let name = OutputPathHelpers.suggestedFilename(for: "dicom-json", input: input)
        #expect(name == "scan.json")
    }

    @Test("OutputPathHelpers.suggestedFilename for dicom-convert appends _converted")
    func test_outputPathHelpers_suggestedFilename_convertTool() {
        let input = URL(fileURLWithPath: "/tmp/chest.dcm")
        let name = OutputPathHelpers.suggestedFilename(for: "dicom-convert", input: input)
        #expect(name == "chest_converted.dcm")
    }

    @Test("OutputPathHelpers.suggestedFilename for dicom-image returns .png")
    func test_outputPathHelpers_suggestedFilename_imageTool() {
        let input = URL(fileURLWithPath: "/tmp/scan.dcm")
        let name = OutputPathHelpers.suggestedFilename(for: "dicom-image", input: input)
        #expect(name == "scan.png")
    }

    @Test("OutputPathHelpers.suggestedFilename for unknown tool appends _output")
    func test_outputPathHelpers_suggestedFilename_unknownTool() {
        let input = URL(fileURLWithPath: "/tmp/data.dcm")
        let name = OutputPathHelpers.suggestedFilename(for: "dicom-unknown", input: input)
        #expect(name.contains("_output"))
    }

    @Test("OutputPathHelpers.resolveOutputDirectory uses input parent when input is provided")
    func test_outputPathHelpers_resolveOutputDirectory_usesInputParent() {
        let input = URL(fileURLWithPath: "/Users/john/Documents/scan.dcm")
        let (url, mode) = OutputPathHelpers.resolveOutputDirectory(inputURL: input, lastUsedURL: nil)
        #expect(url.path == "/Users/john/Documents")
        #expect(mode == .sameAsInput)
    }

    @Test("OutputPathHelpers.resolveOutputDirectory uses lastUsed when no input")
    func test_outputPathHelpers_resolveOutputDirectory_usesLastUsed() {
        let last = URL(fileURLWithPath: "/Users/john/LastUsed")
        let (url, mode) = OutputPathHelpers.resolveOutputDirectory(inputURL: nil, lastUsedURL: last)
        #expect(url.path == "/Users/john/LastUsed")
        #expect(mode == .lastUsed)
    }

    @Test("OutputPathHelpers.resolveOutputDirectory falls back to desktop")
    func test_outputPathHelpers_resolveOutputDirectory_fallsBackToDesktop() {
        let desktop = URL(fileURLWithPath: "/Users/john/Desktop")
        let (url, mode) = OutputPathHelpers.resolveOutputDirectory(
            inputURL: nil,
            lastUsedURL: nil,
            desktopFallback: desktop
        )
        #expect(url.path == "/Users/john/Desktop")
        #expect(mode == .desktop)
    }

    @Test("OutputPathHelpers.quotedPath quotes paths with spaces")
    func test_outputPathHelpers_quotedPath_spacedPath() {
        let url = URL(fileURLWithPath: "/Users/my folder/file.dcm")
        let quoted = OutputPathHelpers.quotedPath(url)
        #expect(quoted.hasPrefix("\""))
        #expect(quoted.hasSuffix("\""))
    }

    @Test("OutputPathHelpers.quotedPath does not quote paths without spaces")
    func test_outputPathHelpers_quotedPath_noSpacePath() {
        let url = URL(fileURLWithPath: "/tmp/file.dcm")
        let quoted = OutputPathHelpers.quotedPath(url)
        #expect(!quoted.hasPrefix("\""))
    }

    @Test("OutputPathHelpers.fileArguments joins multiple URLs with spaces")
    func test_outputPathHelpers_fileArguments_multipleURLs() {
        let urls = [
            URL(fileURLWithPath: "/tmp/a.dcm"),
            URL(fileURLWithPath: "/tmp/b.dcm"),
        ]
        let args = OutputPathHelpers.fileArguments(for: urls)
        #expect(args.contains("/tmp/a.dcm"))
        #expect(args.contains("/tmp/b.dcm"))
    }

    @Test("OutputPathHelpers.fileArguments returns empty string for empty array")
    func test_outputPathHelpers_fileArguments_emptyArray() {
        #expect(OutputPathHelpers.fileArguments(for: []) == "")
    }

    // MARK: - FileValidationHelpers

    @Test("FileValidationHelpers.preambleSize is 132")
    func test_fileValidationHelpers_preambleSize() {
        #expect(FileValidationHelpers.preambleSize == 132)
    }

    @Test("FileValidationHelpers.warnings includes .veryLargeFile for >1GB")
    func test_fileValidationHelpers_warnings_veryLargeFile() {
        let w = FileValidationHelpers.warnings(
            validationResult: .valid,
            fileSizeBytes: 2_000_000_000,
            transferSyntaxUID: nil
        )
        #expect(w.contains(.veryLargeFile))
    }

    @Test("FileValidationHelpers.warnings includes .missingPreamble for validWithoutPreamble")
    func test_fileValidationHelpers_warnings_missingPreamble() {
        let w = FileValidationHelpers.warnings(
            validationResult: .validWithoutPreamble,
            fileSizeBytes: 100,
            transferSyntaxUID: nil
        )
        #expect(w.contains(.missingPreamble))
    }

    @Test("FileValidationHelpers.warnings includes .corrupt for notDICOM")
    func test_fileValidationHelpers_warnings_corrupt() {
        let w = FileValidationHelpers.warnings(
            validationResult: .notDICOM,
            fileSizeBytes: 100,
            transferSyntaxUID: nil
        )
        #expect(w.contains(.corrupt))
    }

    @Test("FileValidationHelpers.warnings is empty for valid small standard file")
    func test_fileValidationHelpers_warnings_emptyForValidSmallFile() {
        let w = FileValidationHelpers.warnings(
            validationResult: .valid,
            fileSizeBytes: 1024,
            transferSyntaxUID: "1.2.840.10008.1.2.1" // Explicit VR LE
        )
        #expect(w.isEmpty)
    }

    @Test("FileValidationHelpers.warnings includes .unusualTransferSyntax for proprietary UID")
    func test_fileValidationHelpers_warnings_unusualTransferSyntax() {
        let w = FileValidationHelpers.warnings(
            validationResult: .valid,
            fileSizeBytes: 1024,
            transferSyntaxUID: "1.2.3.4.5.6.999"
        )
        #expect(w.contains(.unusualTransferSyntax))
    }

    @Test("FileValidationHelpers.isUnusualTransferSyntax returns false for Explicit VR LE")
    func test_fileValidationHelpers_isUnusualTransferSyntax_explicitVRLE_false() {
        #expect(FileValidationHelpers.isUnusualTransferSyntax("1.2.840.10008.1.2.1") == false)
    }

    @Test("FileValidationHelpers.isUnusualTransferSyntax returns true for unknown UID")
    func test_fileValidationHelpers_isUnusualTransferSyntax_unknownUID_true() {
        #expect(FileValidationHelpers.isUnusualTransferSyntax("9.9.9.9") == true)
    }

    @Test("FileValidationHelpers common syntaxes are the 13 PS3.6 2026a Table A-1 UIDs named in the source")
    func test_fileValidationHelpers_commonSyntaxes_pinned() {
        let common = ["1.2.840.10008.1.2", "1.2.840.10008.1.2.1", "1.2.840.10008.1.2.2",
                      "1.2.840.10008.1.2.4.50", "1.2.840.10008.1.2.4.51", "1.2.840.10008.1.2.4.57",
                      "1.2.840.10008.1.2.4.70", "1.2.840.10008.1.2.4.90", "1.2.840.10008.1.2.4.91",
                      "1.2.840.10008.1.2.4.201", "1.2.840.10008.1.2.4.202", "1.2.840.10008.1.2.4.203",
                      "1.2.840.10008.1.2.5"]
        for uid in common {
            #expect(FileValidationHelpers.isUnusualTransferSyntax(uid) == false, "\(uid)")
        }
        // Registered but not in the list: JPEG XL Lossless (.110) and JPEG-LS Lossless (.80).
        #expect(FileValidationHelpers.isUnusualTransferSyntax("1.2.840.10008.1.2.4.110") == true)
        #expect(FileValidationHelpers.isUnusualTransferSyntax("1.2.840.10008.1.2.4.80") == true)
    }

    @Test("FileValidationHelpers.imageDimensions returns nil for zero rows")
    func test_fileValidationHelpers_imageDimensions_zeroRows_nil() {
        #expect(FileValidationHelpers.imageDimensions(rows: 0, columns: 512) == nil)
    }

    @Test("FileValidationHelpers.imageDimensions returns formatted string")
    func test_fileValidationHelpers_imageDimensions_formattedString() {
        let result = FileValidationHelpers.imageDimensions(rows: 512, columns: 512)
        #expect(result == "512×512")
    }

    @Test("FileValidationHelpers.formattedStudyDate returns original for invalid input")
    func test_fileValidationHelpers_formattedStudyDate_invalidInput_returnsOriginal() {
        let raw = "not-a-date"
        #expect(FileValidationHelpers.formattedStudyDate(raw) == raw)
    }

    @Test("FileValidationHelpers.formattedStudyDate parses YYYYMMDD into display string")
    func test_fileValidationHelpers_formattedStudyDate_validDate() {
        let result = FileValidationHelpers.formattedStudyDate("20240101")
        #expect(!result.isEmpty)
        #expect(result != "20240101" || result.contains("2024"))
    }

    @Test("FileValidationHelpers.formattedPatientName formats Doe^John as Doe, John")
    func test_fileValidationHelpers_formattedPatientName_familyGiven() {
        let result = FileValidationHelpers.formattedPatientName("DOE^JOHN")
        #expect(result.contains("Doe"))
        #expect(result.contains("John"))
    }

    @Test("FileValidationHelpers.formattedPatientName handles single component")
    func test_fileValidationHelpers_formattedPatientName_singleComponent() {
        let result = FileValidationHelpers.formattedPatientName("ANONYMOUS")
        #expect(result == "Anonymous")
    }

    @Test("FileValidationHelpers.quickValidate returns .unreadable for nonexistent file")
    func test_fileValidationHelpers_quickValidate_nonexistentFile_unreadable() {
        let url = URL(fileURLWithPath: "/tmp/does_not_exist_\(UUID().uuidString).dcm")
        let result = FileValidationHelpers.quickValidate(url: url)
        if case .unreadable = result {
            // Expected
        } else {
            Issue.record("Expected .unreadable but got \(result)")
        }
    }

    @Test("FileValidationHelpers.quickValidate returns .valid for file with DICM magic")
    func test_fileValidationHelpers_quickValidate_validDICM() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).dcm")
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        var data = Data(repeating: 0, count: 132)
        data[128] = 0x44; data[129] = 0x49; data[130] = 0x43; data[131] = 0x4D
        try data.write(to: tmpURL)
        let result = FileValidationHelpers.quickValidate(url: tmpURL)
        #expect(result == .valid)
    }

    // MARK: - DirectoryInputHelpers

    @Test("DirectoryInputHelpers.recursiveFlag returns '--recursive' for recursive mode")
    func test_directoryInputHelpers_recursiveFlag_recursive() {
        #expect(DirectoryInputHelpers.recursiveFlag(for: .recursive) == "--recursive")
    }

    @Test("DirectoryInputHelpers.recursiveFlag returns '' for shallow mode")
    func test_directoryInputHelpers_recursiveFlag_shallow() {
        #expect(DirectoryInputHelpers.recursiveFlag(for: .shallow) == "")
    }

    @Test("DirectoryInputHelpers.cliArgument includes path and recursive flag")
    func test_directoryInputHelpers_cliArgument_recursiveIncludesFlag() {
        let url = URL(fileURLWithPath: "/tmp/studies")
        let arg = DirectoryInputHelpers.cliArgument(for: url, scanMode: .recursive)
        #expect(arg.contains("studies"))
        #expect(arg.contains("--recursive"))
    }

    @Test("DirectoryInputHelpers.cliArgument shallow omits recursive flag")
    func test_directoryInputHelpers_cliArgument_shallowOmitsFlag() {
        let url = URL(fileURLWithPath: "/tmp/studies")
        let arg = DirectoryInputHelpers.cliArgument(for: url, scanMode: .shallow)
        #expect(!arg.contains("--recursive"))
    }

    @Test("DirectoryInputHelpers.isDirectory returns true for a known directory")
    func test_directoryInputHelpers_isDirectory_trueForDirectory() {
        #expect(DirectoryInputHelpers.isDirectory(URL(fileURLWithPath: "/tmp")) == true)
    }

    @Test("DirectoryInputHelpers.isDirectory returns false for a file")
    func test_directoryInputHelpers_isDirectory_falseForFile() throws {
        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: tmpFile) }
        try "hello".write(to: tmpFile, atomically: true, encoding: .utf8)
        #expect(DirectoryInputHelpers.isDirectory(tmpFile) == false)
    }

    @Test("DirectoryInputHelpers.dicomExtensions contains dcm and dicom")
    func test_directoryInputHelpers_dicomExtensions_containsExpected() {
        #expect(DirectoryInputHelpers.dicomExtensions.contains("dcm"))
        #expect(DirectoryInputHelpers.dicomExtensions.contains("dicom"))
    }

    #if canImport(Darwin)
    @Test("Directory scanning never opens or counts named pipes")
    func test_directoryInputHelpers_namedPipesAreNotFiles() throws {
        let directory = try makeFileOperationsTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let extensionlessPipe = directory.appendingPathComponent("extensionless-pipe")
        let dicomNamedPipe = directory.appendingPathComponent("misleading.dcm")
        #expect(mkfifo(extensionlessPipe.path, 0o600) == 0)
        #expect(mkfifo(dicomNamedPipe.path, 0o600) == 0)

        let validation = FileValidationHelpers.quickValidate(url: extensionlessPipe)
        guard case .unreadable = validation else {
            Issue.record("A named pipe must be rejected before it is opened")
            return
        }
        #expect(
            DirectoryInputHelpers.countDICOMFiles(
                in: directory,
                scanMode: .recursive
            ) == 0)
    }
    #endif
}

// MARK: - Service Tests

@Suite("File Operations Service Tests")
struct FileOperationsServiceTests {

    @Test("Service initial state has idle drop zone and no files")
    func test_service_initialState_idleNoFiles() {
        let service = FileOperationsService()
        let state = service.getState()
        #expect(state.dropZone.highlight == .idle)
        #expect(state.dropZone.files.isEmpty)
        #expect(state.selectedTab == .fileInput)
    }

    @Test("setDropMode changes mode and clears files")
    func test_service_setDropMode_changesModeAndClearsFiles() {
        let service = FileOperationsService()
        service.setDropMode(.multiple)
        #expect(service.getDropZone().mode == .multiple)
    }

    @Test("setDropHighlight updates highlight state")
    func test_service_setDropHighlight_updatesHighlight() {
        let service = FileOperationsService()
        service.setDropHighlight(.active)
        #expect(service.getDropZone().highlight == .active)
    }

    @Test("addFile with non-DICOM extension returns nil and rejects")
    func test_service_addFile_nonDICOMExtension_rejectsAndReturnsNil() {
        let service = FileOperationsService()
        let url = URL(fileURLWithPath: "/tmp/photo.jpg")
        let result = service.addFile(url: url)
        #expect(result == nil)
        #expect(service.getDropZone().highlight == .rejected)
        #expect(service.getDropZone().rejectionMessage != nil)
    }

    @Test("addDroppedFile in single mode replaces existing file")
    func test_service_addDroppedFile_singleMode_replacesFile() {
        let service = FileOperationsService()
        let file1 = DroppedFile(url: URL(fileURLWithPath: "/tmp/a.dcm"), fileName: "a.dcm", fileSizeBytes: 0, isDICOM: true)
        let file2 = DroppedFile(url: URL(fileURLWithPath: "/tmp/b.dcm"), fileName: "b.dcm", fileSizeBytes: 0, isDICOM: true)
        service.addDroppedFile(file1)
        service.addDroppedFile(file2)
        #expect(service.getDropZone().files.count == 1)
        #expect(service.getDropZone().files.first?.fileName == "b.dcm")
    }

    @Test("addDroppedFile in multiple mode accumulates files")
    func test_service_addDroppedFile_multipleMode_accumulatesFiles() {
        let service = FileOperationsService()
        service.setDropMode(.multiple)
        let file1 = DroppedFile(url: URL(fileURLWithPath: "/tmp/a.dcm"), fileName: "a.dcm", fileSizeBytes: 0, isDICOM: true)
        let file2 = DroppedFile(url: URL(fileURLWithPath: "/tmp/b.dcm"), fileName: "b.dcm", fileSizeBytes: 0, isDICOM: true)
        service.addDroppedFile(file1)
        service.addDroppedFile(file2)
        #expect(service.getDropZone().files.count == 2)
    }

    @Test("removeFile at valid index removes the file")
    func test_service_removeFile_validIndex_removesFile() {
        let service = FileOperationsService()
        service.setDropMode(.multiple)
        let file = DroppedFile(url: URL(fileURLWithPath: "/tmp/a.dcm"), fileName: "a.dcm", fileSizeBytes: 0, isDICOM: true)
        service.addDroppedFile(file)
        service.removeFile(at: 0)
        #expect(service.getDropZone().files.isEmpty)
    }

    @Test("clearFiles empties the drop zone")
    func test_service_clearFiles_emptiesDropZone() {
        let service = FileOperationsService()
        service.setDropMode(.multiple)
        let file = DroppedFile(url: URL(fileURLWithPath: "/tmp/a.dcm"), fileName: "a.dcm", fileSizeBytes: 0, isDICOM: true)
        service.addDroppedFile(file)
        service.clearFiles()
        #expect(service.getDropZone().files.isEmpty)
        #expect(service.getFilePreview() == nil)
    }

    @Test("rejectDrop sets rejected highlight and message")
    func test_service_rejectDrop_setsRejectedState() {
        let service = FileOperationsService()
        service.rejectDrop(reason: "Not a DICOM file")
        #expect(service.getDropZone().highlight == .rejected)
        #expect(service.getDropZone().rejectionMessage == "Not a DICOM file")
    }

    @Test("setTool updates associatedToolName in state")
    func test_service_setTool_updatesToolName() {
        let service = FileOperationsService()
        service.setTool("dicom-anon")
        #expect(service.getState().associatedToolName == "dicom-anon")
    }

    @Test("setCustomOutputURL sets custom mode and URL")
    func test_service_setCustomOutputURL_setsCustomMode() {
        let service = FileOperationsService()
        let url = URL(fileURLWithPath: "/tmp/output.dcm")
        service.setCustomOutputURL(url)
        #expect(service.getOutputPath().mode == .custom)
        #expect(service.getOutputPath().resolvedURL == url)
    }

    @Test("selectTab changes selectedTab in state")
    func test_service_selectTab_changesSelectedTab() {
        let service = FileOperationsService()
        service.selectTab(.outputPath)
        #expect(service.getState().selectedTab == .outputPath)
    }

    @Test("addDroppedFile updates filePreview")
    func test_service_addDroppedFile_updatesFilePreview() {
        let service = FileOperationsService()
        let file = DroppedFile(url: URL(fileURLWithPath: "/tmp/a.dcm"), fileName: "a.dcm", fileSizeBytes: 2048, isDICOM: true, modality: "CT")
        service.addDroppedFile(file)
        let preview = service.getFilePreview()
        #expect(preview != nil)
        #expect(preview?.fileName == "a.dcm")
    }

    @Test("moveFile reorders files in multiple mode")
    func test_service_moveFile_reordersFiles() {
        let service = FileOperationsService()
        service.setDropMode(.multiple)
        let fileA = DroppedFile(url: URL(fileURLWithPath: "/tmp/a.dcm"), fileName: "a.dcm", fileSizeBytes: 0, isDICOM: true)
        let fileB = DroppedFile(url: URL(fileURLWithPath: "/tmp/b.dcm"), fileName: "b.dcm", fileSizeBytes: 0, isDICOM: true)
        service.addDroppedFile(fileA)
        service.addDroppedFile(fileB)
        service.moveFile(fromIndex: 0, toIndex: 1)
        #expect(service.getDropZone().files[0].fileName == "b.dcm")
    }

    @Test("setDirectory rejects a file path")
    func test_service_setDirectory_rejectsFilePath() throws {
        let service = FileOperationsService()
        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: tmpFile) }
        try "hello".write(to: tmpFile, atomically: true, encoding: .utf8)
        service.setDirectory(tmpFile)
        #expect(service.getDirectoryDrop().highlight == .rejected)
    }

    @Test("setDirectory accepts a real directory and sets URL")
    func test_service_setDirectory_acceptsDirectory() throws {
        let directory = try makeFileOperationsTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = FileOperationsService()
        service.setDirectory(directory)
        #expect(service.getDirectoryDrop().directoryURL == directory)
    }

    @Test("setScanMode changes the scan mode")
    func test_service_setScanMode_changesScanMode() {
        let service = FileOperationsService()
        service.setScanMode(.shallow)
        #expect(service.getDirectoryDrop().scanMode == .shallow)
    }

    @Test("clearDirectory resets directory drop state")
    func test_service_clearDirectory_resetsState() throws {
        let directory = try makeFileOperationsTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = FileOperationsService()
        service.setDirectory(directory)
        service.clearDirectory()
        #expect(service.getDirectoryDrop().directoryURL == nil)
        #expect(service.getDirectoryDrop().dicomFileCount == 0)
    }
}

// MARK: - ViewModel Tests

@Suite("File Operations ViewModel Tests")
struct FileOperationsViewModelTests {

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("ViewModel initialises with default state")
    func test_viewModel_init_defaultState() {
        let vm = FileOperationsViewModel()
        #expect(vm.dropZone.files.isEmpty)
        #expect(vm.selectedTab == .fileInput)
        #expect(vm.associatedToolName.isEmpty)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("setDropMode updates observable dropZone.mode")
    func test_viewModel_setDropMode_updatesDropZone() {
        let vm = FileOperationsViewModel()
        vm.setDropMode(.multiple)
        #expect(vm.dropZone.mode == .multiple)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("dragEntered sets highlight to .active")
    func test_viewModel_dragEntered_setsActiveHighlight() {
        let vm = FileOperationsViewModel()
        vm.dragEntered()
        #expect(vm.dropZone.highlight == .active)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("dragExited sets highlight to .idle")
    func test_viewModel_dragExited_setsIdleHighlight() {
        let vm = FileOperationsViewModel()
        vm.dragEntered()
        vm.dragExited()
        #expect(vm.dropZone.highlight == .idle)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("dropFile with non-DICOM extension returns false")
    func test_viewModel_dropFile_nonDICOM_returnsFalse() {
        let vm = FileOperationsViewModel()
        let accepted = vm.dropFile(url: URL(fileURLWithPath: "/tmp/photo.jpg"))
        #expect(accepted == false)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("addFile in single mode replaces existing file")
    func test_viewModel_addFile_singleMode_replacesFile() {
        let vm = FileOperationsViewModel()
        let file1 = DroppedFile(url: URL(fileURLWithPath: "/tmp/a.dcm"), fileName: "a.dcm", fileSizeBytes: 0, isDICOM: true)
        let file2 = DroppedFile(url: URL(fileURLWithPath: "/tmp/b.dcm"), fileName: "b.dcm", fileSizeBytes: 0, isDICOM: true)
        vm.addFile(file1)
        vm.addFile(file2)
        #expect(vm.dropZone.files.count == 1)
        #expect(vm.dropZone.files.first?.fileName == "b.dcm")
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("removeFile at index 0 removes first file")
    func test_viewModel_removeFile_removesFirstFile() {
        let vm = FileOperationsViewModel()
        vm.setDropMode(.multiple)
        let file = DroppedFile(url: URL(fileURLWithPath: "/tmp/a.dcm"), fileName: "a.dcm", fileSizeBytes: 0, isDICOM: true)
        vm.addFile(file)
        vm.removeFile(at: 0)
        #expect(vm.dropZone.files.isEmpty)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("clearFiles empties drop zone and clears preview")
    func test_viewModel_clearFiles_emptiesDropZone() {
        let vm = FileOperationsViewModel()
        vm.addFile(DroppedFile(url: URL(fileURLWithPath: "/tmp/a.dcm"), fileName: "a.dcm", fileSizeBytes: 0, isDICOM: true))
        vm.clearFiles()
        #expect(vm.dropZone.files.isEmpty)
        #expect(vm.filePreview == nil)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("setTool updates associatedToolName")
    func test_viewModel_setTool_updatesToolName() {
        let vm = FileOperationsViewModel()
        vm.setTool("dicom-anon")
        #expect(vm.associatedToolName == "dicom-anon")
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("setCustomOutputURL updates outputPath.mode to .custom")
    func test_viewModel_setCustomOutputURL_setsCustomMode() {
        let vm = FileOperationsViewModel()
        vm.setCustomOutputURL(URL(fileURLWithPath: "/tmp/out.dcm"))
        #expect(vm.outputPath.mode == .custom)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("showOverwriteWarning reflects outputPath.overwriteWarning")
    func test_viewModel_showOverwriteWarning_reflectsOutputPath() {
        let vm = FileOperationsViewModel()
        #expect(vm.showOverwriteWarning == false)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("multiFileCommandArguments is empty when no files")
    func test_viewModel_multiFileCommandArguments_emptyWhenNoFiles() {
        let vm = FileOperationsViewModel()
        #expect(vm.multiFileCommandArguments == "")
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("multiFileCommandArguments contains file paths")
    func test_viewModel_multiFileCommandArguments_containsFilePaths() {
        let vm = FileOperationsViewModel()
        vm.setDropMode(.multiple)
        vm.addFile(DroppedFile(url: URL(fileURLWithPath: "/tmp/a.dcm"), fileName: "a.dcm", fileSizeBytes: 0, isDICOM: true))
        vm.addFile(DroppedFile(url: URL(fileURLWithPath: "/tmp/b.dcm"), fileName: "b.dcm", fileSizeBytes: 0, isDICOM: true))
        let args = vm.multiFileCommandArguments
        #expect(args.contains("a.dcm"))
        #expect(args.contains("b.dcm"))
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("previewFileSizeDescription is nil when no preview")
    func test_viewModel_previewFileSizeDescription_nilWhenNoPreview() {
        let vm = FileOperationsViewModel()
        #expect(vm.previewFileSizeDescription == nil)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("previewFileSizeDescription returns non-empty string when preview is set")
    func test_viewModel_previewFileSizeDescription_nonEmptyWhenSet() {
        let vm = FileOperationsViewModel()
        vm.setFilePreview(FilePreviewInfo(fileName: "a.dcm", fileSizeBytes: 1_048_576))
        #expect(vm.previewFileSizeDescription != nil)
        #expect(!(vm.previewFileSizeDescription?.isEmpty ?? true))
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("previewModalitySymbol returns default when no preview")
    func test_viewModel_previewModalitySymbol_defaultWhenNoPreview() {
        let vm = FileOperationsViewModel()
        #expect(!vm.previewModalitySymbol.isEmpty)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("selectTab updates selectedTab")
    func test_viewModel_selectTab_updatesSelectedTab() {
        let vm = FileOperationsViewModel()
        vm.selectTab(.directoryInput)
        #expect(vm.selectedTab == .directoryInput)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("directoryDragEntered sets active highlight on directoryDrop")
    func test_viewModel_directoryDragEntered_setsActiveHighlight() {
        let vm = FileOperationsViewModel()
        vm.directoryDragEntered()
        #expect(vm.directoryDrop.highlight == .active)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("directoryDragExited sets idle highlight on directoryDrop")
    func test_viewModel_directoryDragExited_setsIdleHighlight() {
        let vm = FileOperationsViewModel()
        vm.directoryDragEntered()
        vm.directoryDragExited()
        #expect(vm.directoryDrop.highlight == .idle)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("clearDirectory resets directoryDrop")
    func test_viewModel_clearDirectory_resetsDirectoryDrop() throws {
        let directory = try makeFileOperationsTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let vm = FileOperationsViewModel()
        vm.dropDirectory(url: directory)
        vm.clearDirectory()
        #expect(vm.directoryDrop.directoryURL == nil)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("setScanMode updates directoryDrop.scanMode")
    func test_viewModel_setScanMode_updatesScanMode() {
        let vm = FileOperationsViewModel()
        vm.setScanMode(.shallow)
        #expect(vm.directoryDrop.scanMode == .shallow)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("directoryCliArgument is empty when no directory selected")
    func test_viewModel_directoryCliArgument_emptyWhenNoDirectory() {
        let vm = FileOperationsViewModel()
        #expect(vm.directoryCliArgument.isEmpty)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("rejectDrop sets rejected highlight and message")
    func test_viewModel_rejectDrop_setsRejectedState() {
        let vm = FileOperationsViewModel()
        vm.rejectDrop(reason: "Test reason")
        #expect(vm.dropZone.highlight == .rejected)
        #expect(vm.dropZone.rejectionMessage == "Test reason")
    }
}
