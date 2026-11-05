import Foundation
import DICOMCore
import DICOMKit
import DICOMSwiftJ2KIntegration
import SwiftJ2K

private enum CLIExitStatus: Int32 {
    case success = 0
    case usage = 64
    case runtimeFailure = 1
}

private struct CLIArguments {
    let subcommand: String
    var positionals: [String] = []
    var codec: String?
    var transferSyntax: String?
    var quality: CompressionQuality?
    var provider: String = "swiftj2k"
    var fallback: J2KProviderFallbackPolicy = .strict
    var backend: CodecBackendPreference = .auto
    var stripPrivate: Bool = false
    var reportJSONPath: String?
}

private struct TelemetrySummaryEntry: Codable {
    let kind: String
    let transferSyntaxUID: String
    let targetTransferSyntaxUID: String?
    let frameIndex: Int
    let backend: String
    let fallbackReason: String?
    let fidelity: String
    let pixelAllocationCount: Int?
    let peakPixelBytes: Int?
    let peakWorkspaceBytes: Int?
    let elapsedSeconds: Double?
}

private struct CLIReportPayload: Codable {
    let subcommand: String
    let configuredProvider: String
    let fallbackPolicy: String
    let resolvedDecodeProviderID: String?
    let resolvedEncodeProviderID: String?
    let resolvedTranscodeProviderID: String?
    let sourceTransferSyntaxUID: String?
    let targetTransferSyntaxUID: String?
    let wasTranscoded: Bool?
    let isLossless: Bool?
    let inputBytes: Int
    let outputBytes: Int?
    let swiftJ2KOperations: [TelemetrySummaryEntry]
}

private func fidelityLabel(_ fidelity: Fidelity) -> String {
    switch fidelity {
    case .exactSamples:
        return "exactSamples"
    case .boundedError(let bound):
        return "boundedError(\(bound))"
    case .lossy:
        return "lossy"
    case .originalBitstream:
        return "originalBitstream"
    }
}

private func backendLabel(_ backend: Backend) -> String {
    switch backend {
    case .scalarCPU:
        return "scalarCPU"
    case .accelerated:
        return "accelerated"
    }
}

private func fallbackLabel(_ policy: J2KProviderFallbackPolicy) -> String {
    switch policy {
    case .strict:
        return "strict"
    case .preselectPredecessorOnUnsupportedCapability:
        return "predecessor"
    }
}

private func printUsage(to stream: UnsafeMutablePointer<FILE> = stderr) {
    let text = """
    Usage:
      dicom-swiftj2k compress <input> <output> --codec <name> [--quality <preset|0.0..1.0>] [--provider swiftj2k|j2kswift] [--fallback strict|predecessor] [--backend auto|scalar|accelerate|metal] [--report-json <path>]
      dicom-swiftj2k decompress <input> <output> [--provider swiftj2k|j2kswift] [--fallback strict|predecessor] [--backend auto|scalar|accelerate|metal] [--report-json <path>]
      dicom-swiftj2k convert <input> <output> --transfer-syntax <token|uid> [--strip-private] [--provider swiftj2k|j2kswift] [--fallback strict|predecessor] [--report-json <path>]
      dicom-swiftj2k info <input>
      dicom-swiftj2k --help
    """
    fputs(text + "\n", stream)
}

private func parseQuality(_ raw: String) throws -> CompressionQuality {
    switch raw.lowercased() {
    case "maximum", "max":
        return .maximum
    case "high":
        return .high
    case "medium", "med":
        return .medium
    case "low":
        return .low
    default:
        guard let numeric = Double(raw), numeric.isFinite, (0.0...1.0).contains(numeric) else {
            throw NSError(
                domain: "dicom-swiftj2k",
                code: 64,
                userInfo: [NSLocalizedDescriptionKey: "Invalid --quality value '\(raw)'"]
            )
        }
        return .custom(numeric)
    }
}

private func parseBackend(_ raw: String) throws -> CodecBackendPreference {
    switch raw.lowercased() {
    case "auto":
        return .auto
    case "scalar":
        return .scalar
    case "accelerate":
        return .accelerate
    case "metal":
        return .metal
    default:
        throw NSError(
            domain: "dicom-swiftj2k",
            code: 64,
            userInfo: [NSLocalizedDescriptionKey: "Invalid --backend value '\(raw)'; expected auto, scalar, accelerate, or metal"]
        )
    }
}

private func parseFallback(_ raw: String) throws -> J2KProviderFallbackPolicy {
    switch raw.lowercased() {
    case "strict":
        return .strict
    case "predecessor", "j2kswift":
        return .preselectPredecessorOnUnsupportedCapability
    default:
        throw NSError(
            domain: "dicom-swiftj2k",
            code: 64,
            userInfo: [NSLocalizedDescriptionKey: "Invalid --fallback value '\(raw)'; expected strict or predecessor"]
        )
    }
}

private func parseArguments(_ rawArgs: [String]) throws -> CLIArguments? {
    guard let first = rawArgs.first else {
        throw NSError(domain: "dicom-swiftj2k", code: 64, userInfo: [NSLocalizedDescriptionKey: "Missing subcommand"])
    }
    if first == "--help" || first == "-h" || first == "help" {
        printUsage(to: stdout)
        return nil
    }
    var parsed = CLIArguments(subcommand: first)
    var index = 1
    while index < rawArgs.count {
        let arg = rawArgs[index]
        switch arg {
        case "--help", "-h":
            printUsage(to: stdout)
            return nil
        case "--strip-private":
            parsed.stripPrivate = true
            index += 1
        case "--codec", "-c":
            guard index + 1 < rawArgs.count else {
                throw NSError(domain: "dicom-swiftj2k", code: 64, userInfo: [NSLocalizedDescriptionKey: "Missing value for \(arg)"])
            }
            parsed.codec = rawArgs[index + 1]
            index += 2
        case "--transfer-syntax", "-t":
            guard index + 1 < rawArgs.count else {
                throw NSError(domain: "dicom-swiftj2k", code: 64, userInfo: [NSLocalizedDescriptionKey: "Missing value for \(arg)"])
            }
            parsed.transferSyntax = rawArgs[index + 1]
            index += 2
        case "--quality", "-q":
            guard index + 1 < rawArgs.count else {
                throw NSError(domain: "dicom-swiftj2k", code: 64, userInfo: [NSLocalizedDescriptionKey: "Missing value for \(arg)"])
            }
            parsed.quality = try parseQuality(rawArgs[index + 1])
            index += 2
        case "--provider":
            guard index + 1 < rawArgs.count else {
                throw NSError(domain: "dicom-swiftj2k", code: 64, userInfo: [NSLocalizedDescriptionKey: "Missing value for --provider"])
            }
            let value = rawArgs[index + 1].lowercased()
            guard value == "swiftj2k" || value == "j2kswift" else {
                throw NSError(domain: "dicom-swiftj2k", code: 64, userInfo: [NSLocalizedDescriptionKey: "Invalid --provider '\(rawArgs[index + 1])'; expected swiftj2k or j2kswift"])
            }
            parsed.provider = value
            index += 2
        case "--fallback":
            guard index + 1 < rawArgs.count else {
                throw NSError(domain: "dicom-swiftj2k", code: 64, userInfo: [NSLocalizedDescriptionKey: "Missing value for --fallback"])
            }
            parsed.fallback = try parseFallback(rawArgs[index + 1])
            index += 2
        case "--backend":
            guard index + 1 < rawArgs.count else {
                throw NSError(domain: "dicom-swiftj2k", code: 64, userInfo: [NSLocalizedDescriptionKey: "Missing value for --backend"])
            }
            parsed.backend = try parseBackend(rawArgs[index + 1])
            index += 2
        case "--report-json":
            guard index + 1 < rawArgs.count else {
                throw NSError(domain: "dicom-swiftj2k", code: 64, userInfo: [NSLocalizedDescriptionKey: "Missing value for --report-json"])
            }
            parsed.reportJSONPath = rawArgs[index + 1]
            index += 2
        default:
            if arg.hasPrefix("-") {
                throw NSError(domain: "dicom-swiftj2k", code: 64, userInfo: [NSLocalizedDescriptionKey: "Unknown option '\(arg)'"])
            }
            parsed.positionals.append(arg)
            index += 1
        }
    }
    return parsed
}

private func buildRegistry(
    provider: String,
    fallback: J2KProviderFallbackPolicy,
    collector: SwiftJ2KTelemetryCollector
) -> CodecRegistry {
    if provider == "j2kswift" {
        return .j2kSwiftRollback
    }
    let options = SwiftJ2KProviderOptions(collector: collector)
    return .swiftJ2K(options: options, fallbackPolicy: fallback)
}

private func writeReportIfRequested(_ payload: CLIReportPayload, path: String?) throws {
    guard let path else { return }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let jsonData = try encoder.encode(payload)
    try jsonData.write(to: URL(fileURLWithPath: path), options: .atomic)
}

private func mapTelemetry(_ records: [SwiftJ2KOperationRecord]) -> [TelemetrySummaryEntry] {
    records.map { record in
        TelemetrySummaryEntry(
            kind: record.kind.rawValue,
            transferSyntaxUID: record.transferSyntaxUID,
            targetTransferSyntaxUID: record.targetTransferSyntaxUID,
            frameIndex: record.frameIndex,
            backend: backendLabel(record.report.backend),
            fallbackReason: record.report.fallbackReason,
            fidelity: fidelityLabel(record.report.fidelity),
            pixelAllocationCount: record.report.pixelAllocationCount,
            peakPixelBytes: record.report.peakPixelBytes,
            peakWorkspaceBytes: record.report.peakWorkspaceBytes,
            elapsedSeconds: record.report.elapsedSeconds
        )
    }
}

private func runCLI() -> CLIExitStatus {
    let rawArgs = Array(CommandLine.arguments.dropFirst())
    let args: CLIArguments
    do {
        guard let parsed = try parseArguments(rawArgs) else {
            return .success
        }
        args = parsed
    } catch {
        fputs("Error: \(error.localizedDescription)\n", stderr)
        printUsage(to: stderr)
        return .usage
    }

    let collector = SwiftJ2KTelemetryCollector()
    let registry = buildRegistry(provider: args.provider, fallback: args.fallback, collector: collector)

    do {
        switch args.subcommand {
        case "compress":
            guard args.positionals.count == 2, let codec = args.codec else {
                fputs("Error: 'compress' requires <input> <output> and --codec <name>\n", stderr)
                return .usage
            }
            let inputURL = URL(fileURLWithPath: args.positionals[0])
            let outputURL = URL(fileURLWithPath: args.positionals[1])
            let inputData = try Data(contentsOf: inputURL)
            let sourceFile = try? DICOMFile.read(from: inputData)
            let manager = CompressionManager(codecRegistry: registry)
            let (outputData, metrics) = try manager.compressDataWithMetrics(
                inputData,
                codec: codec,
                quality: args.quality,
                backend: args.backend
            )
            try outputData.write(to: outputURL, options: .atomic)
            let outputFile = try? DICOMFile.read(from: outputData)
            let report = CLIReportPayload(
                subcommand: "compress",
                configuredProvider: args.provider,
                fallbackPolicy: fallbackLabel(args.fallback),
                resolvedDecodeProviderID: metrics.resolvedDecodeProviderID?.rawValue,
                resolvedEncodeProviderID: metrics.resolvedEncodeProviderID?.rawValue,
                resolvedTranscodeProviderID: nil,
                sourceTransferSyntaxUID: sourceFile?.transferSyntaxUID,
                targetTransferSyntaxUID: outputFile?.transferSyntaxUID,
                wasTranscoded: true,
                isLossless: nil,
                inputBytes: inputData.count,
                outputBytes: outputData.count,
                swiftJ2KOperations: mapTelemetry(collector.records)
            )
            try writeReportIfRequested(report, path: args.reportJSONPath)
            print("Compressed \(inputData.count) -> \(outputData.count) bytes (encodeProvider=\(metrics.resolvedEncodeProviderID?.rawValue ?? "none"))")
            return .success

        case "decompress":
            guard args.positionals.count == 2 else {
                fputs("Error: 'decompress' requires <input> <output>\n", stderr)
                return .usage
            }
            let inputURL = URL(fileURLWithPath: args.positionals[0])
            let outputURL = URL(fileURLWithPath: args.positionals[1])
            let inputData = try Data(contentsOf: inputURL)
            let sourceFile = try? DICOMFile.read(from: inputData)
            let manager = CompressionManager(codecRegistry: registry)
            let (outputData, decodeProviderID) = try manager.decompressDataWithMetrics(
                inputData,
                syntax: .explicitVRLittleEndian,
                backend: args.backend
            )
            try outputData.write(to: outputURL, options: .atomic)
            let report = CLIReportPayload(
                subcommand: "decompress",
                configuredProvider: args.provider,
                fallbackPolicy: fallbackLabel(args.fallback),
                resolvedDecodeProviderID: decodeProviderID?.rawValue,
                resolvedEncodeProviderID: nil,
                resolvedTranscodeProviderID: nil,
                sourceTransferSyntaxUID: sourceFile?.transferSyntaxUID,
                targetTransferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
                wasTranscoded: decodeProviderID != nil,
                isLossless: true,
                inputBytes: inputData.count,
                outputBytes: outputData.count,
                swiftJ2KOperations: mapTelemetry(collector.records)
            )
            try writeReportIfRequested(report, path: args.reportJSONPath)
            print("Decompressed \(inputData.count) -> \(outputData.count) bytes (decodeProvider=\(decodeProviderID?.rawValue ?? "none"))")
            return .success

        case "convert":
            guard args.positionals.count == 2, let tsToken = args.transferSyntax else {
                fputs("Error: 'convert' requires <input> <output> and --transfer-syntax <token|uid>\n", stderr)
                return .usage
            }
            guard let encoding = DICOMConverter.resolveTargetEncoding(tsToken) else {
                fputs("Error: \(DICOMConverter.unknownTargetMessage(tsToken))\n", stderr)
                return .usage
            }
            let inputURL = URL(fileURLWithPath: args.positionals[0])
            let outputURL = URL(fileURLWithPath: args.positionals[1])
            let inputData = try Data(contentsOf: inputURL)
            let dicomFile = try DICOMFile.read(from: inputData, options: .init(strictEncapsulation: true))
            let outcome = try DICOMConverter.convertToDICOM(
                dicomFile: dicomFile,
                to: encoding,
                stripPrivate: args.stripPrivate,
                codecRegistry: registry
            )
            try outcome.data.write(to: outputURL, options: .atomic)
            let report = CLIReportPayload(
                subcommand: "convert",
                configuredProvider: args.provider,
                fallbackPolicy: fallbackLabel(args.fallback),
                resolvedDecodeProviderID: outcome.resolvedDecodeProviderID?.rawValue,
                resolvedEncodeProviderID: outcome.resolvedEncodeProviderID?.rawValue,
                resolvedTranscodeProviderID: outcome.resolvedTranscodeProviderID?.rawValue,
                sourceTransferSyntaxUID: outcome.sourceSyntax.uid,
                targetTransferSyntaxUID: outcome.targetSyntax.uid,
                wasTranscoded: outcome.wasTranscoded,
                isLossless: outcome.isLossless,
                inputBytes: inputData.count,
                outputBytes: outcome.data.count,
                swiftJ2KOperations: mapTelemetry(collector.records)
            )
            try writeReportIfRequested(report, path: args.reportJSONPath)
            print("Converted \(outcome.sourceSyntax.uid) -> \(outcome.targetSyntax.uid) (\(outcome.data.count) bytes, transcodeProvider=\(outcome.resolvedTranscodeProviderID?.rawValue ?? "none"), decodeProvider=\(outcome.resolvedDecodeProviderID?.rawValue ?? "none"), encodeProvider=\(outcome.resolvedEncodeProviderID?.rawValue ?? "none"))")
            return .success

        case "info":
            guard args.positionals.count == 1 else {
                fputs("Error: 'info' requires <input>\n", stderr)
                return .usage
            }
            let inputData = try Data(contentsOf: URL(fileURLWithPath: args.positionals[0]))
            let info = try CompressionManager(codecRegistry: registry).getCompressionInfo(data: inputData)
            print("TransferSyntax: \(info.transferSyntaxUID) (\(info.transferSyntaxName))")
            print("Dimensions: \(info.columns ?? 0)x\(info.rows ?? 0)x\(info.numberOfFrames ?? "1")")
            print("BitsAllocated: \(info.bitsAllocated ?? 0), Compressed: \(info.isCompressed), Lossless: \(info.isLossless)")
            return .success

        default:
            fputs("Error: Unknown subcommand '\(args.subcommand)'\n", stderr)
            printUsage(to: stderr)
            return .usage
        }
    } catch {
        fputs("Error: \(error.localizedDescription)\n", stderr)
        return .runtimeFailure
    }
}

exit(runCLI().rawValue)
