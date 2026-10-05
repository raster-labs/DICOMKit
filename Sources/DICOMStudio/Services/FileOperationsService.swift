// FileOperationsService.swift
// DICOMStudio
//
// DICOM Studio — Thread-safe service for File Operations & Drag-and-Drop (Milestone 22)
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (drop handling and output path
// resolution).

import Foundation

/// Thread-safe service that manages state for the File Operations & Drag-and-Drop feature.
public final class FileOperationsService: @unchecked Sendable {
    private let lock = NSLock()

    // 22.1 File Input Controls
    private var _dropZone: FileDropZoneState = FileDropZoneState()

    // 22.2 Output Path Controls
    private var _outputPath: OutputPathConfig = OutputPathConfig()
    private var _outputDirectory: OutputDirectoryConfig = OutputDirectoryConfig()
    private var _lastUsedOutputURL: URL? = nil

    // 22.3 File Validation & Preview
    private var _filePreview: FilePreviewInfo? = nil

    // 22.4 Directory Input Support
    private var _directoryDrop: DirectoryDropState = DirectoryDropState()

    // General
    private var _selectedTab: FileOperationsTab = .fileInput
    private var _associatedToolName: String = ""

    public init() {}

    // MARK: - State Accessors

    /// Returns the current complete `FileOperationsState`.
    public func getState() -> FileOperationsState {
        lock.withLock {
            FileOperationsState(
                selectedTab:      _selectedTab,
                dropZone:         _dropZone,
                outputPath:       _outputPath,
                outputDirectory:  _outputDirectory,
                directoryDrop:    _directoryDrop,
                filePreview:      _filePreview,
                associatedToolName: _associatedToolName
            )
        }
    }

    /// Returns the current drop zone state.
    public func getDropZone() -> FileDropZoneState { lock.withLock { _dropZone } }

    /// Returns the current output path configuration.
    public func getOutputPath() -> OutputPathConfig { lock.withLock { _outputPath } }

    /// Returns the current output directory configuration.
    public func getOutputDirectory() -> OutputDirectoryConfig { lock.withLock { _outputDirectory } }

    /// Returns the current file preview information.
    public func getFilePreview() -> FilePreviewInfo? { lock.withLock { _filePreview } }

    /// Returns the current directory drop state.
    public func getDirectoryDrop() -> DirectoryDropState { lock.withLock { _directoryDrop } }

    // MARK: - 22.1 File Input Controls

    /// Sets the drop zone mode and resets any existing file selection.
    public func setDropMode(_ mode: FileDropMode) {
        lock.withLock {
            _dropZone.mode = mode
            _dropZone.files = []
            _dropZone.highlight = .idle
            _dropZone.rejectionMessage = nil
        }
    }

    /// Sets the drag-hover highlight state of the drop zone.
    public func setDropHighlight(_ highlight: DropZoneHighlight) {
        lock.withLock { _dropZone.highlight = highlight }
    }

    /// Adds a file to the drop zone, performing DICOM validation.
    ///
    /// For `.single` mode the file replaces any existing selection.
    /// For `.multiple` mode the file is appended.
    /// Returns the validated `DroppedFile`, or `nil` when the drop was rejected.
    @discardableResult
    public func addFile(url: URL) -> DroppedFile? {
        guard DICOMFileDropHelpers.hasAcceptedExtension(url) else {
            lock.withLock {
                _dropZone.highlight = .rejected
                _dropZone.rejectionMessage = "\(url.lastPathComponent) is not a DICOM file."
            }
            return nil
        }

        let validationResult = FileValidationHelpers.quickValidate(url: url)
        guard validationResult.isDICOM else {
            lock.withLock {
                _dropZone.highlight = .rejected
                _dropZone.rejectionMessage = "\(url.lastPathComponent) does not appear to be a DICOM file."
            }
            return nil
        }

        let fileSizeBytes: Int64 = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize.map { Int64($0) }) ?? 0
        let warnings = FileValidationHelpers.warnings(
            validationResult: validationResult,
            fileSizeBytes: fileSizeBytes,
            transferSyntaxUID: nil
        )

        let file = DroppedFile(
            url: url,
            fileName: url.lastPathComponent,
            fileSizeBytes: fileSizeBytes,
            isDICOM: true,
            warning: warnings.first
        )

        lock.withLock {
            if _dropZone.mode == .single {
                _dropZone.files = [file]
            } else {
                _dropZone.files.append(file)
            }
            _dropZone.highlight = .idle
            _dropZone.rejectionMessage = nil
            _filePreview = FilePreviewInfo(
                fileName: file.fileName,
                fileSizeBytes: file.fileSizeBytes,
                modality: file.modality,
                patientName: file.patientName,
                studyDate: file.studyDate,
                warnings: warnings
            )
        }

        updateOutputPathForInput(url: url)
        return file
    }

    /// Adds a pre-built `DroppedFile` directly (used when metadata has already been extracted).
    public func addDroppedFile(_ file: DroppedFile) {
        lock.withLock {
            if _dropZone.mode == .single {
                _dropZone.files = [file]
            } else {
                _dropZone.files.append(file)
            }
            _dropZone.highlight = .idle
            _dropZone.rejectionMessage = nil
            _filePreview = FilePreviewInfo(
                fileName: file.fileName,
                fileSizeBytes: file.fileSizeBytes,
                modality: file.modality,
                patientName: file.patientName,
                studyDate: file.studyDate,
                warnings: file.warning.map { [$0] } ?? []
            )
        }
        updateOutputPathForInput(url: file.url)
    }

    /// Removes the file at `index` from the drop zone list.
    public func removeFile(at index: Int) {
        lock.withLock {
            DICOMFileDropHelpers.remove(from: &_dropZone.files, at: index)
            if _dropZone.files.isEmpty {
                _filePreview = nil
            }
        }
    }

    /// Moves the file at `fromIndex` to `toIndex` for reorder support.
    public func moveFile(fromIndex: Int, toIndex: Int) {
        lock.withLock {
            DICOMFileDropHelpers.move(items: &_dropZone.files, fromIndex: fromIndex, toIndex: toIndex)
        }
    }

    /// Clears all files from the drop zone and resets related state.
    public func clearFiles() {
        lock.withLock {
            _dropZone.files = []
            _dropZone.highlight = .idle
            _dropZone.rejectionMessage = nil
            _filePreview = nil
        }
    }

    /// Rejects all dropped items and sets an appropriate rejection message.
    public func rejectDrop(reason: String) {
        lock.withLock {
            _dropZone.highlight = .rejected
            _dropZone.rejectionMessage = reason
        }
    }

    // MARK: - 22.2 Output Path Controls

    /// Sets the tool name and updates the output path suggestion.
    public func setTool(_ toolName: String) {
        lock.withLock { _associatedToolName = toolName }
        refreshOutputPath()
    }

    /// Overrides the output path with a user-selected URL.
    public func setCustomOutputURL(_ url: URL) {
        lock.withLock {
            _outputPath.mode = .custom
            _outputPath.resolvedURL = url
            _outputPath.overwriteWarning = OutputPathHelpers.fileExists(at: url)
            _lastUsedOutputURL = url.deletingLastPathComponent()
        }
    }

    /// Overrides the output directory with a user-selected URL.
    public func setCustomOutputDirectory(_ url: URL) {
        lock.withLock {
            _outputDirectory.mode = .custom
            _outputDirectory.resolvedURL = url
            _lastUsedOutputURL = url
        }
    }

    /// Resets the output path to the default (derived from the current input file).
    public func resetOutputPath() {
        refreshOutputPath()
    }

    // MARK: - 22.3 File Validation & Preview

    /// Updates the file preview with the supplied information.
    public func setFilePreview(_ preview: FilePreviewInfo?) {
        lock.withLock { _filePreview = preview }
    }

    // MARK: - 22.4 Directory Input Support

    /// Sets the directory drop highlight state.
    public func setDirectoryDropHighlight(_ highlight: DropZoneHighlight) {
        lock.withLock { _directoryDrop.highlight = highlight }
    }

    /// Selects a directory URL, validates it, and triggers a file count scan.
    ///
    /// The count is performed synchronously here for simplicity; in a real app this
    /// would be dispatched to a background task.
    public func setDirectory(_ url: URL) {
        guard DirectoryInputHelpers.isDirectory(url) else {
            lock.withLock {
                _directoryDrop.highlight = .rejected
                _directoryDrop.rejectionMessage = "\(url.lastPathComponent) is not a folder."
            }
            return
        }

        let mode = lock.withLock { _directoryDrop.scanMode }
        lock.withLock {
            _directoryDrop.directoryURL = url
            _directoryDrop.highlight = .idle
            _directoryDrop.rejectionMessage = nil
            _directoryDrop.isScanning = true
            _directoryDrop.dicomFileCount = 0
        }

        // Count DICOM files (synchronous; would be async in production).
        let count = DirectoryInputHelpers.countDICOMFiles(in: url, scanMode: mode)
        lock.withLock {
            _directoryDrop.dicomFileCount = count
            _directoryDrop.isScanning = false
        }
    }

    /// Changes the scan mode and re-scans if a directory is already selected.
    public func setScanMode(_ mode: DirectoryScanMode) {
        let currentURL = lock.withLock { () -> URL? in
            _directoryDrop.scanMode = mode
            return _directoryDrop.directoryURL
        }
        if let url = currentURL {
            setDirectory(url)
        }
    }

    /// Clears the selected directory.
    public func clearDirectory() {
        lock.withLock {
            _directoryDrop.directoryURL = nil
            _directoryDrop.dicomFileCount = 0
            _directoryDrop.isScanning = false
            _directoryDrop.highlight = .idle
            _directoryDrop.rejectionMessage = nil
        }
    }

    // MARK: - Tab Selection

    /// Selects the given tab.
    public func selectTab(_ tab: FileOperationsTab) {
        lock.withLock { _selectedTab = tab }
    }

    // MARK: - Private Helpers

    private func updateOutputPathForInput(url: URL) {
        let toolName = lock.withLock { _associatedToolName }
        let suggestedName = toolName.isEmpty
            ? nil
            : OutputPathHelpers.suggestedFilename(for: toolName, input: url)
        let (dirURL, mode) = OutputPathHelpers.resolveOutputDirectory(
            inputURL: url,
            lastUsedURL: lock.withLock { _lastUsedOutputURL }
        )
        let outputURL = dirURL.appendingPathComponent(suggestedName ?? url.lastPathComponent)
        lock.withLock {
            _outputPath.mode = mode
            _outputPath.suggestedFilename = suggestedName
            _outputPath.resolvedURL = outputURL
            _outputPath.overwriteWarning = OutputPathHelpers.fileExists(at: outputURL)
        }
    }

    private func refreshOutputPath() {
        let (inputURL, toolName) = lock.withLock { (_dropZone.singleFile?.url, _associatedToolName) }
        let (dirURL, mode) = OutputPathHelpers.resolveOutputDirectory(
            inputURL: inputURL,
            lastUsedURL: lock.withLock { _lastUsedOutputURL }
        )
        let suggestedName = inputURL.map { OutputPathHelpers.suggestedFilename(for: toolName, input: $0) }
        let outputURL = dirURL.appendingPathComponent(suggestedName ?? "output")
        lock.withLock {
            _outputPath.mode = mode
            _outputPath.suggestedFilename = suggestedName
            _outputPath.resolvedURL = outputURL
            _outputPath.overwriteWarning = OutputPathHelpers.fileExists(at: outputURL)
        }
    }
}
