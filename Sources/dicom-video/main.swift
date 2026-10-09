// NEMA-verified: 2026a, checked 2026-10-06 — input/output contract of all 42 option/flag/argument declarations (4 subcommands) by script: --transfer-syntax accepts the 16 MPEG2/MPEG-4 AVC/HEVC UIDs of PS3.6 2026a Table A-1 while the 2 unregistered Fragmentable HEVC UIDs DICOMCore accepts are refused with exit 1 (DICOMKit VideoOptionConformance, lifted D269; P-VIDEO-TS-REGISTERED); --type selects the 3 Video IODs of PS3.3 A.32.5-A.32.7 (Modality ES/GM/XC, SOP Class names per Table A-1); --modality/--patient-sex/--patient-birth-date values the IOD forbids are refused with exit 1 (A.32.x.4.1, Table C.7-1, DA; P-VIDEO-MODALITY-ENUMERATED, P-VIDEO-SEX-ENUMERATED); help text is VideoConsole.Help (16 names vs PS3.6 Table 6-1); --audio-channel-source per PS3.16 CID 3000 (DICOMKit AudioChannelSourceOption, lifted D269; 6 rows) into Table C.7-13 (003A,0300), repeatable once per audio track (P-AUDIO-SOURCE-PER-TRACK)

import Foundation
import ArgumentParser
import DICOMKit
import DICOMCore
import DICOMDictionary

// The conversion, probing, validation and extraction logic all live in the
// DICOMKit library (Sources/DICOMKit/Video/) so this CLI and DICOMStudio's CLI
// Workshop run the same code. `VideoWorkflow` owns the operations and
// `VideoConsole` owns every line of text, so the two surfaces cannot drift.
// This file is a thin adapter: parse argv, call the library, print.

// MARK: - Exit Codes

/// Exit codes, so scripts can tell "broken" from "not DICOM-legal".
///
/// 0 success, 1 I/O or usage error, 2 conformance rejection. The values live in
/// `VideoConsole.ExitCode` so the app's status badge maps them the same way.
private extension VideoConsole.ExitCode {
    /// This exit code as ArgumentParser's, for throwing out of `run()`.
    var argumentParserCode: ExitCode { ExitCode(rawValue) }
}

// MARK: - Shared Output Helpers

private func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// Prints a failure and exits with the code it maps to.
private func fail(_ failure: VideoWorkflow.Failure) -> Error {
    printError(failure.message)
    return failure.exitCode.argumentParserCode
}

/// Whether a path names an existing directory rather than a file.
private func isExistingDirectory(_ path: String) -> Bool {
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
    return exists && isDirectory.boolValue
}

// MARK: - Main Command

struct DICOMVideo: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-video",
        abstract: "Convert H.264/HEVC/MPEG-2 video to and from DICOM Video IODs",
        discussion: """
            Wraps an already-conformant video bitstream in a DICOM Video IOD without
            re-encoding it, and extracts it back out. Remuxing preserves the camera's
            pixel data bit-for-bit; non-conformant input is rejected with the specific
            violated constraint rather than silently re-encoded.

            Examples:
              # Convert a clip, letting the transfer syntax be detected
              dicom-video convert clip.mp4 --output clip.dcm

              # Inspect a clip without writing anything
              dicom-video probe clip.mp4

              # Check conformance without producing an object
              dicom-video convert clip.mp4 --output clip.dcm --dry-run

              # Convert a folder of clips as one series
              dicom-video batch clips/ --output-dir out/ --patient-name "Doe^Jane"

              # Extract the bitstream back out
              dicom-video extract clip.dcm --output clip.mp4

            Exit codes: 0 success, 1 I/O or usage error, 2 conformance rejection.
            """,
        version: VideoConsole.toolVersion,
        subcommands: [
            Convert.self,
            Batch.self,
            Extract.self,
            Probe.self
        ]
    )
}

// MARK: - Shared Options

/// Patient, study and series attributes shared by convert and batch.
///
/// The help strings come from `VideoConsole.Help` so the CLI's `--help`, the
/// Workshop's form help and the invalid-value messages all read identically.
struct MetadataOptions: ParsableArguments {
    @Option(name: .long, help: .init(stringLiteral: VideoConsole.Help.patientName))
    var patientName: String?

    @Option(name: .long, help: .init(stringLiteral: VideoConsole.Help.patientID))
    var patientID: String?

    @Option(name: .long, help: .init(stringLiteral: DICOMKit.VideoOptionConformance.patientBirthDateHelp))
    var patientBirthDate: String?

    @Option(name: .long, help: .init(stringLiteral: DICOMKit.VideoOptionConformance.patientSexHelp))
    var patientSex: String?

    @Option(name: .long, help: .init(stringLiteral: VideoConsole.Help.studyUID))
    var studyUID: String?

    @Option(name: .long, help: .init(stringLiteral: VideoConsole.Help.seriesUID))
    var seriesUID: String?

    @Option(name: .long, help: .init(stringLiteral: VideoConsole.Help.accessionNumber))
    var accessionNumber: String?

    @Option(name: .long, help: .init(stringLiteral: VideoConsole.Help.studyID))
    var studyID: String?

    @Option(name: .long, help: .init(stringLiteral: VideoConsole.Help.referringPhysician))
    var referringPhysician: String?

    @Option(name: .long, help: .init(stringLiteral: VideoConsole.Help.seriesDescription))
    var seriesDescription: String?

    @Option(name: .long, help: .init(stringLiteral: DICOMKit.VideoOptionConformance.modalityHelp))
    var modality: String?

    @Flag(name: .long, help: "Reject a --modality value that is not a current DICOM Defined Term")
    var strictModality: Bool = false

    @Option(name: .long, help: .init(stringLiteral: VideoConsole.Help.manufacturer))
    var manufacturer: String?

    @Option(name: .long, help: .init(stringLiteral: VideoConsole.Help.institutionName))
    var institutionName: String?

    /// PS3.16 CID 3000 keyword or SCHEME:VALUE[:MEANING]; see
    /// `AudioChannelSourceOption` (D56). Once: the source of every audio track
    /// (`VideoWorkflow.Metadata.audioChannelSource`); repeated: one per audio
    /// track in container order (`audioChannelSources`, P-AUDIO-SOURCE-PER-TRACK).
    @Option(name: .customLong("audio-channel-source"),
            help: .init(stringLiteral: DICOMKit.AudioChannelSourceOption.help))
    var audioChannelSource: [String] = []

    /// The shared metadata value the engine takes, with `--modality` and
    /// `--audio-channel-source` validated.
    ///
    /// Throwing so `--strict-modality` and a bad channel source can stop the
    /// run; the non-throwing `shared` below stays for callers that have already
    /// validated (it carries no audio channel source).
    func validatedShared() throws -> VideoWorkflow.Metadata {
        var metadata = shared
        if let resolved = try ModalityOptionValidator.resolve(modality, strict: strictModality) {
            metadata.modality = resolved
        }
        let sources = try audioChannelSource.map(DICOMKit.AudioChannelSourceOption.parse)
        if sources.count == 1 {
            metadata.audioChannelSource = sources[0]
        } else if sources.count > 1 {
            metadata.audioChannelSources = sources
        }
        return metadata
    }

    /// The shared metadata value the engine takes.
    var shared: VideoWorkflow.Metadata {
        VideoWorkflow.Metadata(
            patientName: patientName,
            patientID: patientID,
            patientBirthDate: patientBirthDate,
            patientSex: patientSex,
            studyUID: studyUID,
            seriesUID: seriesUID,
            accessionNumber: accessionNumber,
            studyID: studyID,
            referringPhysician: referringPhysician,
            seriesDescription: seriesDescription,
            modality: modality,
            manufacturer: manufacturer,
            institutionName: institutionName
        )
    }
}

// The argument enums are the shared ones; the CLI only adds argv parsing to them.
extension VideoConsole.TypeArgument: ExpressibleByArgument {}
extension VideoConsole.SeriesMode: ExpressibleByArgument {}

// MARK: - Convert Subcommand

extension DICOMVideo {
    struct Convert: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "convert",
            abstract: "Wrap a video bitstream in a DICOM Video IOD"
        )

        @Argument(help: .init(stringLiteral: VideoConsole.Help.input))
        var input: String

        @Option(name: .shortAndLong, help: .init(stringLiteral: VideoConsole.Help.output))
        var output: String

        @Option(name: .long, help: .init(stringLiteral: VideoConsole.Help.type))
        var type: VideoConsole.TypeArgument?

        @Option(name: .long, help: .init(stringLiteral: DICOMKit.VideoOptionConformance.transferSyntaxHelp))
        var transferSyntax: String?

        @Option(name: .long, help: .init(stringLiteral: VideoConsole.Help.frameRate))
        var frameRate: Double?

        @Option(name: .long, help: .init(stringLiteral: VideoConsole.Help.instanceNumber))
        var instanceNumber: Int = 1

        @Option(name: .long, help: .init(stringLiteral: VideoConsole.Help.seriesNumber))
        var seriesNumber: Int = 1

        @Flag(name: .long, help: .init(stringLiteral: VideoConsole.Help.dryRun))
        var dryRun: Bool = false

        @Flag(name: .long, help: .init(stringLiteral: VideoConsole.Help.trustInput))
        var trustInput: Bool = false

        @Flag(name: .long, help: .init(stringLiteral: VideoConsole.Help.force))
        var force: Bool = false

        @Flag(name: .shortAndLong, help: .init(stringLiteral: VideoConsole.Help.verbose))
        var verbose: Bool = false

        @OptionGroup var metadata: MetadataOptions

        mutating func run() throws {
            let inputURL = URL(fileURLWithPath: input)
            guard let bitstream = FileManager.default.contents(atPath: inputURL.path) else {
                printError(VideoConsole.cannotReadLine(input))
                throw ExitCode(1)
            }

            // A wrong --type yields a valid but mislabelled object, so the
            // default is announced by the engine rather than applied silently.
            let resolvedType = type ?? .endoscopic
            let sharedMetadata = try metadata.validatedShared()
            // Values the engine accepts but the IOD does not are refused
            // (DICOMKit VideoOptionConformance; exit 1, nothing written).
            let refusals = DICOMKit.VideoOptionConformance.violations(
                type: resolvedType, metadata: sharedMetadata, transferSyntax: transferSyntax)
            if !refusals.isEmpty {
                refusals.forEach(printError)
                throw ExitCode(1)
            }

            let outcome: VideoWorkflow.ConvertOutcome
            do {
                outcome = try VideoWorkflow.convert(
                    bitstream: bitstream,
                    type: resolvedType,
                    typeWasExplicit: type != nil,
                    explicitTransferSyntax: transferSyntax,
                    trustInput: trustInput,
                    frameRateOverride: frameRate,
                    dryRun: dryRun,
                    verbose: verbose,
                    metadata: sharedMetadata,
                    seriesNumber: seriesNumber,
                    instanceNumber: instanceNumber
                )
            } catch let verboseFailure as VideoWorkflow.VerboseFailure {
                // Verbose commentary precedes the rejection it explains.
                printError(verboseFailure.combinedMessage)
                throw verboseFailure.exitCode.argumentParserCode
            } catch let failure as VideoWorkflow.Failure {
                throw fail(failure)
            }

            // Notices and warnings go to stderr, as they always did.
            if !outcome.output.isEmpty { printError(outcome.output) }

            if dryRun {
                print(VideoConsole.describe(
                    outcome.plan.probe, transferSyntax: outcome.plan.transferSyntax))
                print(VideoConsole.dryRunTrailer)
                return
            }

            let resolved = VideoWorkflow.resolveOutputURL(
                output: output, input: inputURL, fileExtension: "dcm",
                isDirectory: isExistingDirectory)
            let outputURL = resolved.url
            let outputPath = resolved.redirectedIntoDirectory ? outputURL.path : output
            if FileManager.default.fileExists(atPath: outputURL.path), !force {
                printError(VideoConsole.outputExistsLine(outputPath))
                throw ExitCode(1)
            }

            do {
                try outcome.data?.write(to: outputURL)
            } catch {
                printError(VideoConsole.cannotWriteLine(
                    outputPath, reason: error.localizedDescription))
                throw ExitCode(1)
            }

            print(VideoConsole.wroteLine(outputPath))
            print(VideoConsole.describe(
                outcome.plan.probe, transferSyntax: outcome.plan.transferSyntax))
        }
    }
}

// MARK: - Probe Subcommand

extension DICOMVideo {
    struct Probe: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "probe",
            abstract: "Report a video's geometry, profile, level and conformance"
        )

        @Argument(help: .init(stringLiteral: VideoConsole.Help.probeInput))
        var input: String

        @Flag(name: .long, help: .init(stringLiteral: VideoConsole.Help.probeTrustInput))
        var trustInput: Bool = false

        @Flag(name: .shortAndLong, help: .init(stringLiteral: VideoConsole.Help.verbose))
        var verbose: Bool = false

        mutating func run() throws {
            guard let bitstream = FileManager.default.contents(
                atPath: URL(fileURLWithPath: input).path) else {
                printError(VideoConsole.cannotReadLine(input))
                throw ExitCode(1)
            }

            let outcome: VideoWorkflow.ProbeOutcome
            do {
                outcome = try VideoWorkflow.probe(
                    bitstream: bitstream, trustInput: trustInput, verbose: verbose)
            } catch let failure as VideoWorkflow.Failure {
                throw fail(failure)
            }

            // Commentary precedes the report, so a redirected stdout keeps only
            // the report.
            if !outcome.diagnostics.isEmpty { printError(outcome.diagnostics) }
            print(outcome.output)
            guard outcome.exitCode == .success else {
                throw outcome.exitCode.argumentParserCode
            }
        }
    }
}

// MARK: - Extract Subcommand

extension DICOMVideo {
    struct Extract: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "extract",
            abstract: "Recover the video bitstream from a DICOM Video object"
        )

        @Argument(help: .init(stringLiteral: VideoConsole.Help.extractInput))
        var input: String

        @Option(name: .shortAndLong, help: .init(stringLiteral: VideoConsole.Help.extractOutput))
        var output: String

        @Flag(name: .long, help: .init(stringLiteral: VideoConsole.Help.force))
        var force: Bool = false

        @Flag(name: .shortAndLong, help: .init(stringLiteral: VideoConsole.Help.verbose))
        var verbose: Bool = false

        mutating func run() throws {
            guard let data = FileManager.default.contents(
                atPath: URL(fileURLWithPath: input).path) else {
                printError(VideoConsole.cannotReadLine(input))
                throw ExitCode(1)
            }

            let extracted: ExtractedVideo
            do {
                extracted = try VideoWorkflow.extract(fileData: data, inputPath: input)
            } catch let failure as VideoWorkflow.Failure {
                throw fail(failure)
            }

            if verbose {
                printError(VideoConsole.verboseBlock(
                    VideoConsole.verboseExtractLines(extracted)))
            }

            // Into a folder, the payload's own container names the file, so the
            // extension is right by construction and the warning cannot fire.
            let resolved = VideoWorkflow.resolveOutputURL(
                output: output, input: URL(fileURLWithPath: input),
                fileExtension: extracted.suggestedFileExtension,
                isDirectory: isExistingDirectory)
            let outputURL = resolved.url
            let outputPath = resolved.redirectedIntoDirectory ? outputURL.path : output
            if FileManager.default.fileExists(atPath: outputURL.path), !force {
                printError(VideoConsole.outputExistsLine(outputPath))
                throw ExitCode(1)
            }

            if let warning = VideoWorkflow.conformanceWarning(for: extracted) {
                printError(warning)
            }

            if let warning = VideoWorkflow.extensionWarning(
                for: extracted, outputPath: outputPath) {
                printError(warning)
            }

            do {
                try extracted.bitstream.write(to: outputURL)
            } catch {
                printError(VideoConsole.cannotWriteLine(
                    outputPath, reason: error.localizedDescription))
                throw ExitCode(1)
            }

            print(VideoConsole.extractedLine(
                path: outputPath, byteCount: extracted.bitstream.count))
            print(VideoConsole.extractSummary(extracted))
        }
    }
}

// MARK: - Batch Subcommand

extension DICOMVideo {
    struct Batch: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "batch",
            abstract: "Convert a directory of clips into DICOM Video objects",
            discussion: """
                Clips are converted in natural-sort order, so clip2 precedes clip10.

                --series-mode single (the default) puts every clip in one series,
                which is what IHE Endoscopy Image Archiving 3.10.4.1.1.1 requires of
                clips from one procedure step on one piece of equipment.

                --series-mode per-file gives each clip its own series, for clips from
                different procedure steps or different equipment, where IHE requires
                separate series.
                """
        )

        @Argument(help: .init(stringLiteral: VideoConsole.Help.batchInput))
        var inputDirectory: String

        @Option(name: .long, help: .init(stringLiteral: VideoConsole.Help.batchOutputDir))
        var outputDir: String

        @Option(name: .long, help: .init(stringLiteral: VideoConsole.Help.seriesMode))
        var seriesMode: VideoConsole.SeriesMode = .single

        @Option(name: .long, help: .init(stringLiteral: VideoConsole.Help.type))
        var type: VideoConsole.TypeArgument?

        @Option(name: .long, help: .init(stringLiteral: DICOMKit.VideoOptionConformance.transferSyntaxHelp))
        var transferSyntax: String?

        @Flag(name: .long, help: .init(stringLiteral: VideoConsole.Help.recursive))
        var recursive: Bool = false

        @Flag(name: .long, help: .init(stringLiteral: VideoConsole.Help.continueOnError))
        var continueOnError: Bool = false

        @Flag(name: .long, help: .init(stringLiteral: VideoConsole.Help.batchForce))
        var force: Bool = false

        @Flag(name: .long, help: .init(stringLiteral: VideoConsole.Help.dryRun))
        var dryRun: Bool = false

        @Flag(name: .shortAndLong, help: .init(stringLiteral: VideoConsole.Help.verbose))
        var verbose: Bool = false

        @OptionGroup var metadata: MetadataOptions

        mutating func run() throws {
            let inputURL = URL(fileURLWithPath: inputDirectory)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                printError(VideoConsole.notADirectoryLine(inputDirectory))
                throw ExitCode(1)
            }

            // An explicit --series-uid contradicts per-file, which mints a new
            // UID per clip. Rejecting beats silently ignoring the flag.
            let sharedMetadata = try metadata.validatedShared()
            do {
                try VideoWorkflow.validateBatchOptions(
                    seriesMode: seriesMode, metadata: sharedMetadata)
            } catch let failure as VideoWorkflow.Failure {
                throw fail(failure)
            }
            let refusals = DICOMKit.VideoOptionConformance.violations(
                type: type ?? .endoscopic, metadata: sharedMetadata,
                transferSyntax: transferSyntax)
            if !refusals.isEmpty {
                refusals.forEach(printError)
                throw ExitCode(1)
            }

            let files = try VideoWorkflow.discoverInputs(in: inputURL, recursive: recursive)
            guard !files.isEmpty else {
                printError(VideoConsole.noVideoFilesLine(inputDirectory))
                throw ExitCode(1)
            }

            let outputURL = URL(fileURLWithPath: outputDir)
            if !dryRun {
                try FileManager.default.createDirectory(
                    at: outputURL, withIntermediateDirectories: true)
            }

            let writeForce = force
            let outcome = VideoWorkflow.runBatch(
                inputs: files,
                type: type ?? .endoscopic,
                typeWasExplicit: type != nil,
                explicitTransferSyntax: transferSyntax,
                seriesMode: seriesMode,
                continueOnError: continueOnError,
                dryRun: dryRun,
                verbose: verbose,
                recursive: recursive,
                metadata: sharedMetadata,
                readFile: { FileManager.default.contents(atPath: $0.path) },
                writeFile: { item in
                    let destination = outputURL.appendingPathComponent(item.outputName)
                    if FileManager.default.fileExists(atPath: destination.path), !writeForce {
                        throw VideoWorkflow.Failure.inputError(
                            VideoConsole.batchOutputExistsLine(destination.lastPathComponent))
                    }
                    try item.data?.write(to: destination)
                    return destination.path
                }
            )

            // Per-clip lines and the summary are the result, so they go to
            // stdout; notices and the fail-fast report are commentary on stderr.
            if !outcome.diagnostics.isEmpty { printError(outcome.diagnostics) }
            if !outcome.output.isEmpty { print(outcome.output) }
            guard outcome.exitCode == .success else {
                throw outcome.exitCode.argumentParserCode
            }
        }
    }
}

DICOMVideo.main()
