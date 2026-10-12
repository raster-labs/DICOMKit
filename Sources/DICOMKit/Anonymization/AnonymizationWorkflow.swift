//
// AnonymizationWorkflow.swift
// DICOMKit
//
// The whole `dicom-anon` run, shared by the CLI and DICOMStudio's CLI Workshop.
//
// Both surfaces build a `Request` in the CLI's own vocabulary (flag values as
// typed), hand it to `run(_:emit:)`, and print whatever the sink receives. Input
// parsing (option / region / style / mode / codec), validation messages, the
// pixel-first ordering, the Burned In Annotation policy, the refusal contract and
// every console line therefore come from ONE place — the two surfaces cannot
// drift. The CLI is a thin ArgumentParser adapter; the app adds only sandbox
// plumbing (security-scoped URLs, a writable-output fallback).
//
// There is exactly one profile: PS3.15 Annex E Basic Application Level
// Confidentiality Profile, always applied, with the standard's named retention
// options and the Clean Pixel Data option (on by default) as the only knobs.
//

import Foundation
import DICOMCore

public struct AnonymizationWorkflow: Sendable {

    // MARK: - Errors

    /// A fatal input or run error. The CLI prints `Error: <message>` and exits 1;
    /// the app prints the identical line.
    public struct ValidationError: Error, LocalizedError, Equatable, Sendable {
        public let message: String
        public init(_ message: String) { self.message = message }
        public var errorDescription: String? { message }
    }

    // MARK: - Request (dicom-anon's inputs, verbatim)

    /// Every `dicom-anon` input, named after its flag and carrying the raw value the
    /// operator gave. Nothing here is parsed yet — ``resolve(_:)`` does that, so a
    /// bad value produces the same error on every surface.
    public struct Request: Sendable, Equatable {
        /// Positional path to a DICOM file or directory.
        public var inputPath: String
        /// `--output`
        public var output: String?

        // PS3.15 Annex E retention options.
        /// `--retain-dates` — Retain Longitudinal Temporal Information with Full Dates.
        public var retainDates = false
        /// `--shift-dates N` — … with Modified Dates (every date shifted by N days).
        public var shiftDates: Int?
        public var retainCharacteristics = false
        public var retainDevice = false
        public var retainInstitution = false
        public var retainUids = false
        public var cleanDescriptors = false
        public var retainSafePrivate = false
        public var cleanGraphics = false
        public var cleanStructuredContent = false
        public var cleanRecognizableVisualFeatures = false
        public var retainModifiedDates = false
        public var remove: [String] = []
        public var replace: [String] = []


        // Clean Pixel Data option (on unless `--no-clean-pixel-data`).
        public var cleanPixelData = true
        /// `--redact-region x,y,w,h` (repeatable)
        public var redactRegion: [String] = []
        /// `--redact-fill black|white|<stored value>` (nil = black)
        public var redactFill: String?
        /// `--redact-style blank|label|replace`
        public var redactStyle: String = "blank"
        /// `--redact-label`
        public var redactLabel: String?
        /// `--recompress source|<codec>`
        public var recompress: String?
        /// `--ocr-mode header|classify`
        public var ocrMode: String = "classify"
        /// `--ocr-all-frames`
        public var ocrAllFrames = false
        /// `--text-only`
        public var textOnly = false
        public var allowBurnedInPHI = false

        // Run control.
        public var recursive = false
        public var dryRun = false
        public var backup = false
        /// `--audit-log`
        public var auditLog: String?
        public var force = false
        public var verbose = false

        public init(inputPath: String) {
            self.inputPath = inputPath
        }
    }

    // MARK: - Resolved (typed inputs the engines consume)

    /// What ``resolve(_:)`` produces: the request with every string parsed and
    /// every cross-flag rule checked.
    public struct Resolved: Sendable {
        public let options: ConfidentialityProfile.Options
        public let pixelOptions: PixelCleaningWorkflow.Options
    }

    /// Parses and validates every input. Messages are the CLI's, verbatim.
    public static func resolve(_ r: Request) throws -> Resolved {
        if r.retainModifiedDates && (r.shiftDates == nil || r.retainDates) {
            throw ValidationError("--retain-modified-dates requires --shift-dates and cannot be combined with full-date retention.")
        }
        if r.retainDates, r.shiftDates != nil {
            throw ValidationError(
                "--retain-dates and --shift-dates are alternatives: --retain-dates keeps the original "
                + "dates (Retain Longitudinal Temporal Information with Full Dates); --shift-dates N "
                + "replaces them with shifted dates (… with Modified Dates).")
        }
        let options = ConfidentialityProfile.Options(
            retainLongitudinalTemporal: r.retainDates || r.shiftDates != nil,
            retainPatientCharacteristics: r.retainCharacteristics,
            retainDeviceIdentity: r.retainDevice,
            retainInstitutionIdentity: r.retainInstitution,
            retainUIDs: r.retainUids,
            cleanDescriptors: r.cleanDescriptors,
            dateOffsetDays: r.shiftDates,
            retainSafePrivate: r.retainSafePrivate,
            cleanGraphics: r.cleanGraphics,
            cleanStructuredContent: r.cleanStructuredContent)
        if r.cleanRecognizableVisualFeatures && r.redactRegion.isEmpty {
            throw ValidationError("--clean-recognizable-visual-features requires --redact-region x,y,w,h.")
        }
        _ = try customActions(r)
        var pixelOptions = try pixelCleaningOptions(r)
        pixelOptions.cleanRecognizableVisualFeatures = r.cleanRecognizableVisualFeatures
        return Resolved(options: options, pixelOptions: pixelOptions)
    }

    private static func customActions(_ request: Request) throws -> [Tag: AnonymizationAction] {
        var actions: [Tag: AnonymizationAction] = [:]
        for value in request.remove {
            guard let tag = AnonCLI.parseTag(value) else { throw ValidationError("Invalid --remove tag: \(value)") }
            actions[tag] = .remove
        }
        for value in request.replace {
            let pair = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2, let tag = AnonCLI.parseTag(String(pair[0])) else {
                throw ValidationError("Invalid --replace; expected tag=value.")
            }
            actions[tag] = .replaceWithDummy(String(pair[1]))
        }
        return actions
    }

    // MARK: - Hooks

    /// Writes one output file. Surfaces that cannot write wherever they like (the
    /// sandboxed app) substitute their own writer; a returned note is appended to
    /// that file's warnings so the summary shows where the bytes actually went.
    public typealias FileWriter = @Sendable (Data, URL) throws -> String?

    private let writeFile: FileWriter

    public init(writeFile: @escaping FileWriter = { data, url in
        // Create the output's parent so `--output new-folder/` (or a nested file
        // path) works the same on every surface — the Studio writer already does.
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return nil
    }) {
        self.writeFile = writeFile
    }

    // MARK: - Run

    /// Everything the run produced besides console text.
    public struct Outcome: Sendable {
        public let results: [AnonymizationResult]
        /// CLI rule: any failed file → 1.
        public var exitCode: Int32 { results.contains(where: { !$0.success }) ? 1 : 0 }
    }

    /// Runs `dicom-anon` end to end. `emit` receives every console line in order,
    /// newline-terminated, exactly as the CLI prints it. Throws a
    /// ``ValidationError`` (or an engine error) for a fatal failure — the caller
    /// renders it as `Error: <localizedDescription>`.
    public func run(_ request: Request, emit: (String) -> Void) async throws -> Outcome {
        let inputURL = URL(fileURLWithPath: request.inputPath)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: request.inputPath, isDirectory: &isDirectory) else {
            throw ValidationError("File not found")
        }

        let resolved = try Self.resolve(request)

        // Build the engine state ONCE for the whole run so UID remapping stays
        // consistent across every file in a directory.
        let anonymizer = Anonymizer(options: resolved.options, customActions: try Self.customActions(request))

        var results: [AnonymizationResult] = []
        if isDirectory.boolValue {
            guard request.recursive else {
                throw ValidationError("Directory anonymization requires --recursive flag")
            }
            guard let outputPath = request.output else {
                throw ValidationError("Directory anonymization requires --output directory")
            }
            results = try await anonymizeDirectory(
                request, resolved, inputURL: inputURL,
                outputURL: URL(fileURLWithPath: outputPath), anonymizer: anonymizer, emit: emit)
        } else {
            // Writing back over the input is never implied. Without --output there is
            // nowhere to write, so anonymizing would silently discard its result and
            // still report success — require --output unless this is a --dry-run preview.
            guard request.dryRun || request.output != nil else {
                throw ValidationError("Anonymization requires --output (or use --dry-run to preview without writing)")
            }
            let result = try await anonymizeFile(
                request, resolved, inputURL: inputURL,
                outputURL: request.output.map { Self.singleFileOutputURL($0, inputURL: inputURL) },
                anonymizer: anonymizer, sweep: nil, emit: emit)
            results = [result]
        }

        emit(AnonConsole.summary(
            totalFiles: results.count,
            successful: results.filter { $0.success }.count,
            failed: results.filter { !$0.success }.count,
            dryRun: request.dryRun,
            warnings: results.flatMap { $0.warnings },
            modifiedTags: Set(results.flatMap { $0.changedTags }.map { "\($0)" }),
            verbose: request.verbose))

        // The audit log is written even under --dry-run: dry-run auditing is a primary use case.
        if let auditLogPath = request.auditLog, !auditLogPath.isEmpty {
            try anonymizer.writeAuditLog(to: URL(fileURLWithPath: auditLogPath))
            if request.verbose {
                emit(AnonConsole.auditLogLine(path: auditLogPath) + "\n")
            }
        }

        return Outcome(results: results)
    }

    // MARK: - Burned In Annotation policy

    /// The per-file pixel policy for (0028,0301) Burned In Annotation:
    ///
    /// - `YES` → clean (OCR, declared regions, device templates, explicit rectangles);
    /// - absent → OCR decides whether there is anything to clean;
    /// - `NO` → the declaration is trusted: the pixels are neither inspected nor
    ///   modified. Two things override that trust, because they are evidence the
    ///   declaration does not speak to: rectangles the operator named, and overlay
    ///   planes in the file.
    ///
    /// Returns the options to run with and, when the pass was skipped on trust, the
    /// note that goes to the verbose console and the audit log.
    static func pixelPolicy(
        for dataSet: DataSet, options: PixelCleaningWorkflow.Options
    ) -> (options: PixelCleaningWorkflow.Options, trustedNote: String?) {
        if dataSet[.pixelData] == nil && dataSet[.floatPixelData] == nil && dataSet[.doubleFloatPixelData] == nil,
           options.explicitRegions.isEmpty {
            var headerOnly = options
            headerOnly.cleanPixelData = false
            headerOnly.detectText = nil
            return (headerOnly, nil)
        }
        guard options.cleanPixelData else { return (options, nil) }
        let declared = dataSet.string(for: .burnedInAnnotation)?
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard declared == "NO", options.explicitRegions.isEmpty,
              ConfidentialityEngine.overlayGroups(in: dataSet).isEmpty
        else { return (options, nil) }
        var trusted = options
        trusted.cleanPixelData = false
        trusted.detectText = nil
        return (trusted, AnonConsole.burnedInAnnotationTrustedNote)
    }

    // MARK: - Directory

    private func anonymizeDirectory(
        _ request: Request, _ resolved: Resolved,
        inputURL: URL, outputURL: URL, anonymizer: Anonymizer, emit: (String) -> Void
    ) async throws -> [AnonymizationResult] {
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        guard let fileURLs = FileGatherer.regularFiles(under: inputURL) else {
            throw ValidationError("Failed to enumerate directory: \(inputURL.path)")
        }

        var results: [AnonymizationResult] = []

        // Concatenation pre-pass (§4.4): with OCR on, sweep every part first so text
        // found in one part is blanked in all of them.
        var sweep = PixelCleaningWorkflow.ConcatenationSweep()
        if resolved.pixelOptions.detectText != nil {
            for fileURL in fileURLs {
                guard let data = try? Data(contentsOf: fileURL),
                      let file = try? DICOMFile.read(from: data, force: request.force),
                      MultiframeConcatenation.isPart(file.dataSet)
                else { continue }
                let (options, trusted) = Self.pixelPolicy(for: file.dataSet, options: resolved.pixelOptions)
                guard trusted == nil else { continue }
                if let swept = try? await PixelCleaningWorkflow().sweep(fileData: data, options: options),
                   let info = swept.info {
                    sweep.add(info, regions: swept.regions)
                }
            }
        }

        // Relative paths are computed on symlink-resolved paths: the gatherer yields
        // resolved URLs, so an input given through a symlink (e.g. /var → /private/var
        // on macOS) would otherwise leak the resolved prefix into the output tree.
        let basePath = inputURL.resolvingSymlinksInPath().path
        for fileURL in fileURLs {
            let filePath = fileURL.resolvingSymlinksInPath().path
            guard filePath.hasPrefix(basePath + "/") else { continue }
            let relativePath = String(filePath.dropFirst(basePath.count + 1))
            guard !relativePath.isEmpty else { continue }

            let outputFileURL = outputURL.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: outputFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            do {
                let result = try await anonymizeFile(
                    request, resolved, inputURL: fileURL, outputURL: outputFileURL,
                    anonymizer: anonymizer, sweep: sweep, emit: emit)
                results.append(result)
                if request.verbose {
                    emit(AnonConsole.fileSuccessLine(relativePath: relativePath) + "\n")
                }
            } catch {
                if request.verbose {
                    emit(AnonConsole.fileFailureLine(relativePath: relativePath, message: error.localizedDescription) + "\n")
                }
                results.append(AnonymizationResult(
                    filePath: fileURL.path, success: false, changedTags: [],
                    warnings: [error.localizedDescription]))
            }
        }
        return results
    }

    /// `--output` is "Output file or directory path". For a single input file a
    /// path that is an existing directory (or is written with a trailing `/`)
    /// names the folder to write INTO, under the input's own file name; anything
    /// else is the output file itself. Without this, a directory output made the
    /// writer try to save a file *onto* the folder — which is exactly what
    /// DICOMStudio's Browse button hands the workflow, since it can only grant a folder.
    static func singleFileOutputURL(_ output: String, inputURL: URL) -> URL {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: output, isDirectory: &isDirectory)
        if (exists && isDirectory.boolValue) || output.hasSuffix("/") {
            return URL(fileURLWithPath: output, isDirectory: true)
                .appendingPathComponent(inputURL.lastPathComponent)
        }
        return URL(fileURLWithPath: output)
    }

    // MARK: - One file

    private func anonymizeFile(
        _ request: Request, _ resolved: Resolved,
        inputURL: URL, outputURL: URL?, anonymizer: Anonymizer,
        sweep: PixelCleaningWorkflow.ConcatenationSweep?, emit: (String) -> Void
    ) async throws -> AnonymizationResult {
        var fileData = try Data(contentsOf: inputURL)
        var dicomFile = try DICOMFile.read(from: fileData, force: request.force)

        // --- Pixel work runs FIRST, before any header de-identification. ---
        // The region decision reads Modality / Manufacturer / model, which
        // de-identification removes; planning afterwards would see a scrubbed data set
        // and match nothing. Both CTP and Presidio document this same ordering
        // dependency, so the order here is a correctness requirement, not a preference.
        var pixelWarnings: [String] = []
        var pixelNotes: [String] = []
        var (pixelOptions, trustedNote) = Self.pixelPolicy(for: dicomFile.dataSet, options: resolved.pixelOptions)
        if let trustedNote {
            // The declaration was taken on trust: say so where an auditor will look.
            if request.verbose { emit(trustedNote + "\n") }
            anonymizer.recordPixelAudit(filePath: inputURL.path, lines: [trustedNote])
        }
        if let sweep, let info = PixelCleaningWorkflow.concatenationInfo(of: dicomFile.dataSet) {
            pixelOptions.presetDetectedRegions = sweep.regions(for: info.uid)
            pixelOptions.concatenationAnalyzedCompletely = sweep.isComplete(info.uid)
        }
        // `replace` draws the header engine's OWN values: preview the header pass on the
        // original data set (in memory, nothing written) and read what it produces.
        if case .replace = pixelOptions.style, pixelOptions.detectText != nil {
            let preview = anonymizer.preview(file: dicomFile)
            pixelOptions.replacementMapping = PixelCleaningWorkflow.ReplacementMapping.derive(
                original: dicomFile.dataSet, deidentified: preview.dataSet)
        }
        if pixelOptions.isActive {
            let report = try await PixelCleaningWorkflow().run(
                fileData: fileData, options: pixelOptions, dryRun: request.dryRun)
            if pixelOptions.detectText != nil {
                emit(AnonConsole.textDetectionLine(report: report))
                anonymizer.recordPixelAudit(filePath: inputURL.path, lines: report.auditLines)
            }
            if request.dryRun {
                emit(AnonConsole.pixelPlanTable(report: report, showText: true))
            }
            if let outcome = report.outcome {
                fileData = report.data
                dicomFile = try DICOMFile.read(from: report.data, force: request.force)
                if request.verbose {
                    emit(AnonConsole.pixelRedactionLines(outcome: outcome))
                }
                if let r = report.recompression {
                    // Always shown: the lossy/fallback caveats are not optional information.
                    emit(AnonConsole.recompressionLines(r))
                }
            }
            // Coverage notes are reported, never used to refuse.
            pixelNotes = report.warnings
            // Detection feeds the refusal contract: text the tool KNOWS is there and
            // will not blank must block an output file unless the operator accepts it.
            pixelWarnings = report.residualWarnings
            if !pixelWarnings.isEmpty && outputURL != nil && !request.dryRun && !request.allowBurnedInPHI {
                throw ValidationError(
                    """
                    Refusing to anonymize \(inputURL.lastPathComponent): OCR found burned-in \
                    text that this run would leave in the pixels.

                    \(pixelWarnings.map { "  ⚠️  \($0)" }.joined(separator: "\n"))

                    Let pixel cleaning blank the detected regions (drop --text-only), or pass \
                    --allow-burned-in-phi to write the metadata-scrubbed file anyway \
                    (it will be marked Patient Identity Removed = NO).
                    """)
            }
        }

        // --- Header pass: PS3.15 Annex E Basic Profile + the selected options. ---
        var (anonymizedFile, res) = anonymizer.deidentify(file: dicomFile, filePath: inputURL.path)
        // Refuse to emit a file whose pixels may still identify the patient unless
        // the operator explicitly accepts that. Writing it silently is the harmful
        // case: the metadata looks clean, so the file reads as safe to release.
        if !res.warnings.isEmpty && !request.allowBurnedInPHI && !request.dryRun {
            throw ValidationError(
                """
                Refusing to anonymize \(inputURL.lastPathComponent): the pixel data may \
                still contain PHI.

                \(res.warnings.map { "  ⚠️  \($0)" }.joined(separator: "\n"))

                With --no-clean-pixel-data this tool de-identifies the DATASET ONLY, \
                so burned-in text survives unchanged.

                Let pixel cleaning run (add --redact-region x,y,w,h if the automatic \
                region selection cannot resolve this device), or pass \
                --allow-burned-in-phi to write the metadata-scrubbed file anyway \
                (it will be marked Patient Identity Removed = NO).
                """)
        }
        let result = AnonymizationResult(
            filePath: res.filePath, success: res.success,
            changedTags: res.changedTags, warnings: res.warnings + pixelWarnings + pixelNotes)

        // The operator accepted detected-but-unredacted text: the output must say so.
        // A YES here would be the false attestation this whole pipeline exists to avoid.
        if !pixelWarnings.isEmpty {
            var ds = anonymizedFile.dataSet
            PixelCleaningWorkflow.markDetectedTextRetained(in: &ds)
            anonymizedFile = DICOMFile(fileMetaInformation: anonymizedFile.fileMetaInformation, dataSet: ds)
        }

        // Write output if not dry-run
        var writeNotes: [String] = []
        if !request.dryRun, let outputURL {
            if request.backup {
                let backupURL = outputURL.appendingPathExtension("backup")
                try? FileManager.default.copyItem(at: inputURL, to: backupURL)
            }
            let outputData = try anonymizedFile.write()
            if let note = try writeFile(outputData, outputURL) {
                writeNotes.append(note)
            }
        }

        guard !writeNotes.isEmpty else { return result }
        return AnonymizationResult(
            filePath: result.filePath, success: result.success,
            changedTags: result.changedTags, warnings: result.warnings + writeNotes)
    }

    // MARK: - Input parsing (the CLI's, verbatim)

    /// Translates the pixel-related flags into the shared pixel workflow options.
    private static func pixelCleaningOptions(_ r: Request) throws -> PixelCleaningWorkflow.Options {
        let editor = PixelEditor(verbose: false)
        let explicit = try r.redactRegion.map { spec -> PixelRedactionPlan.Region in
            let region = try editor.parseRegion(spec)
            return PixelRedactionPlan.Region(x: region.x, y: region.y, width: region.width, height: region.height)
        }
        guard let mode = PixelCleaningWorkflow.TextDetectionMode.parse(r.ocrMode) else {
            throw ValidationError(
                "Invalid --ocr-mode '\(r.ocrMode)'. Use 'header' or 'classify' (default).")
        }
        if r.textOnly, !r.cleanPixelData {
            throw ValidationError("--text-only needs pixel cleaning; drop --no-clean-pixel-data.")
        }
        guard let fill = PixelCleaningWorkflow.RedactFill.parse(r.redactFill) else {
            throw ValidationError("Invalid --redact-fill '\(r.redactFill ?? "")'. Use 'black', 'white' or a non-negative stored pixel value.")
        }
        guard let style = PixelRedactor.Style.parse(r.redactStyle, label: r.redactLabel) else {
            throw ValidationError("Invalid --redact-style '\(r.redactStyle)'. Use 'blank', 'label' or 'replace'.")
        }
        if case .replace = style {
            // Replacement values come from the classifier's matched header attribute,
            // so the pixel pass (and with it OCR) has to run at all.
            guard r.cleanPixelData else {
                throw ValidationError("--redact-style replace needs pixel cleaning; drop --no-clean-pixel-data (replacement values come from classified matches).")
            }
        }
        var recompressTarget: PixelCleaningWorkflow.Recompress?
        if let raw = r.recompress {
            guard let parsed = PixelCleaningWorkflow.Recompress.parse(raw) else {
                throw ValidationError("Invalid --recompress '\(raw)'. Use 'source' or a dicom-compress codec name.")
            }
            guard r.cleanPixelData || !r.redactRegion.isEmpty else {
                throw ValidationError("--recompress only applies after pixel cleaning; drop --no-clean-pixel-data or add --redact-region.")
            }
            recompressTarget = parsed
        }
        return PixelCleaningWorkflow.Options(
            cleanPixelData: r.cleanPixelData, explicitRegions: explicit,
            detectText: r.cleanPixelData ? mode : nil, ocrAllFrames: r.ocrAllFrames,
            fillValue: { if case .value(let v) = fill { return v } else { return nil } }(),
            style: style, recompress: recompressTarget, fillWhite: fill == .white,
            textOnly: r.textOnly)
    }
}
