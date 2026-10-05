// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data of its own: validation runs through the shared DICOMKit.DICOMValidator and renders through DICOMKit.ValidationReport (the dicom-validate engine and renderer); the level range 1-5 and its refusal text are dicom-validate's; IOD suggestions come from ValidationHelpers.knownIODs (PS3.6 Table A-1 keywords)
// ValidationViewModel.swift
// DICOMStudio
//
// ViewModel for the DICOM Validation view.
// Runs validation through DICOMKit.DICOMValidator — the exact same engine the
// `dicom-validate` CLI uses — so the app and the tool cannot drift. The library
// ValidationResult is mapped onto the view's display model (ValidationFileResult).

import Foundation
import Observation
import DICOMKit
import DICOMCore
import DICOMDictionary

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
@Observable
@MainActor
public final class ValidationViewModel {
    private let service: ValidationService

    // MARK: - Options (mirrors dicom-validate CLI flags)

    /// Positional argument: path to DICOM file or directory.
    public var inputPath: String = ""
    /// --level 1-5
    public var level: Int = 3
    /// --iod CTImageStorage etc.
    public var iod: String = ""
    /// --detailed
    public var detailed: Bool = false
    /// --recursive
    public var recursive: Bool = false
    /// --format text|json
    public var format: ValidateOutputFormat = .text
    /// --output path (empty = stdout / display in UI)
    public var outputPath: String = ""
    /// --strict
    public var strict: Bool = false
    /// --force
    public var force: Bool = false

    // MARK: - UI State

    public var isRunning: Bool = false
    public var validationOutput: String = ""
    public var lastResults: [ValidationFileResult] = []
    public var runHistory: [ValidationRunRecord] = []
    public var iodSuggestions: [String] = ValidationHelpers.knownIODs
    public var showIODPicker: Bool = false

    // MARK: - Security-Scoped Resource Access
    // Set by the view (or CLIWorkshopViewModel) immediately after the user picks
    // a file via NSOpenPanel / NSSavePanel.  Required for sandbox file access.
    public var inputScopedURL: URL?
    public var outputScopedURL: URL?

    // MARK: - Init

    public init(service: ValidationService = ValidationService()) {
        self.service = service
    }

    // MARK: - Command Builder

    /// Returns the exact dicom-validate CLI command for the current settings.
    public var cliCommand: String {
        ValidationHelpers.buildCommand(
            inputPath: inputPath,
            level: level,
            iod: iod,
            detailed: detailed,
            recursive: recursive,
            format: format,
            outputPath: outputPath,
            strict: strict,
            force: force
        )
    }

    // MARK: - Run Validation

    /// Validates the input file/directory using the shared DICOMKit engine.
    /// Output text is rendered by ValidationHelpers (matching the CLI report).
    public func runValidation() {
        guard !inputPath.isEmpty else {
            validationOutput = "Error: Input path is required.\n"
            return
        }
        guard level >= 1 && level <= 5 else {
            validationOutput = "Error: Validation level must be between 1 and 5\n"   // dicom-validate's text
            return
        }

        isRunning = true
        validationOutput = "Running: \(cliCommand)\n\n"

        Task {
            // Start security-scoped resource access for the entire validation run.
            // The sandbox requires this for any user-selected file or directory.
            let inputAccessing = inputScopedURL?.startAccessingSecurityScopedResource() ?? false
            let outputAccessing = outputScopedURL?.startAccessingSecurityScopedResource() ?? false
            defer {
                if inputAccessing  { inputScopedURL?.stopAccessingSecurityScopedResource() }
                if outputAccessing { outputScopedURL?.stopAccessingSecurityScopedResource() }
            }
            do {
                let sharedResults = try await validateInput()
                // Render + exit code via the SHARED DICOMKit.ValidationReport — the
                // exact renderer dicom-validate uses — so the app console is
                // byte-identical to the CLI (no app-only "Exit code:" annotation).
                let report = DICOMKit.ValidationReport(
                    results: sharedResults, detailed: detailed, strict: strict)
                let output = (try? report.render(format: format == .json ? .json : .text)) ?? ""
                let code = report.exitCode()
                // Map to the display model for the results list / history UI.
                let results = sharedResults.map(Self.mapResult)

                // Save to history
                let record = ValidationRunRecord(
                    inputPath: inputPath,
                    level: level,
                    iod: iod,
                    strict: strict,
                    recursive: recursive,
                    format: format,
                    results: results,
                    output: output,
                    exitCode: code
                )
                service.addHistory(record)

                // Optionally write to file — sandbox/TCC-resilient: prefer the picker's
                // scoped URL; else try the typed path; on failure (e.g. macOS TCC blocks
                // ~/Desktop) fall back to ~/Downloads/DICOMStudio and surface a note so the
                // write never silently fails (the old `try?` swallowed TCC denials).
                var writeNote: String? = nil
                if !outputPath.isEmpty {
                    // Resolve a directory-valued --output to <dir>/<input-stem>.json|.txt via
                    // the shared resolver — the exact call dicom-validate makes — so the app
                    // and the CLI write the same file path.
                    let resolvedOutputPath = OutputPathResolver.resolveFileOutput(
                        output: outputPath,
                        input: inputPath,
                        fileExtension: format == .json ? "json" : "txt"
                    )
                    do {
                        writeNote = try OutputAccess.writeString(output, toPath: resolvedOutputPath,
                                                                 scopedURL: outputScopedURL,
                                                                 subfolder: "Validate").note
                    } catch {
                        writeNote = "⚠ Could not write report to \(resolvedOutputPath): \(error.localizedDescription)"
                    }
                }

                await MainActor.run {
                    self.lastResults = results
                    self.validationOutput = writeNote.map { output + "\n" + $0 } ?? output
                    self.runHistory.insert(record, at: 0)
                    self.isRunning = false
                }
            } catch {
                await MainActor.run {
                    self.validationOutput += "Error: \(error.localizedDescription)\n"
                    self.isRunning = false
                }
            }
        }
    }

    // MARK: - Clear

    public func clearOutput() {
        validationOutput = ""
        lastResults = []
    }

    public func clearHistory() {
        runHistory.removeAll()
        service.clearHistory()
    }

    // MARK: - Private: Core Validation (shared DICOMKit engine)
    //
    // Validation runs through DICOMKit.DICOMValidator — the exact engine the
    // `dicom-validate` CLI uses. There is no app-local validation logic anymore;
    // library results are mapped onto ValidationFileResult for display so the app
    // and the CLI can never disagree on what is valid.

    private func validateInput() async throws -> [DICOMKit.ValidationResult] {
        let url = URL(fileURLWithPath: inputPath)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: inputPath, isDirectory: &isDir) else {
            throw NSError(domain: "ValidationViewModel", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Input path not found: \(inputPath)"])
        }

        let trimmedIOD = iod.trimmingCharacters(in: .whitespaces)
        let validator = DICOMKit.DICOMValidator(
            level: level,
            iod: trimmedIOD.isEmpty ? nil : trimmedIOD,
            force: force
        )

        if isDir.boolValue {
            guard recursive else {
                throw NSError(domain: "ValidationViewModel", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Directory validation requires --recursive flag"])
            }
            return validateDirectory(url: url, validator: validator)
        } else {
            return [validateFile(url: url, validator: validator)]
        }
    }

    private func validateDirectory(url: URL, validator: DICOMKit.DICOMValidator) -> [DICOMKit.ValidationResult] {
        // Shared, sorted directory walk — the same gatherer the dicom-validate CLI
        // uses, so both surfaces validate the same files in the same order.
        let fileURLs = FileGatherer.regularFiles(under: url) ?? []
        return fileURLs.map { validateFile(url: $0, validator: validator) }
    }

    /// Validates one file through the shared DICOMKit engine, wrapping read
    /// failures in a synthetic result exactly like the dicom-validate CLI does.
    private func validateFile(url: URL, validator: DICOMKit.DICOMValidator) -> DICOMKit.ValidationResult {
        do {
            let data = try Data(contentsOf: url)
            return try validator.validate(data: data, filePath: url.path)
        } catch {
            return DICOMKit.ValidationResult(
                filePath: url.path,
                isValid: false,
                errors: [DICOMKit.ValidationIssue(level: .error, message: error.localizedDescription, tag: nil)],
                warnings: []
            )
        }
    }

    // MARK: - Mapping (library result -> display model)

    private static func mapResult(_ result: DICOMKit.ValidationResult) -> ValidationFileResult {
        ValidationFileResult(
            filePath: result.filePath,
            isValid: result.isValid,
            errors: result.errors.map(mapIssue),
            warnings: result.warnings.map(mapIssue)
        )
    }

    private static func mapIssue(_ issue: DICOMKit.ValidationIssue) -> ValidationIssueEntry {
        ValidationIssueEntry(
            level: issue.level == .error ? .error : .warning,
            message: issue.message,
            tagString: issue.tag.map { $0.description }
        )
    }
}
