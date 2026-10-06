// NEMA-verified: 2026a, checked 2026-10-01 — decompress/batch --syntax accept only the native PS3.5 2026a A.1 / A.2 / A.5 targets (explicit-le, implicit-le, deflate) and the retired A.3 explicit-be (engine byte-swaps per PS3.5 7.3, D206); every encapsulated A-1 UID refused, exit 1, P-COMPRESS-SYNTAX; info --json adds the 9 PS3.6 2026a Table 6-1 keyword keys (P-COMPRESS-JSON); the 25 codec/syntax help rows (alias → UID → name) diffed by script against PS3.6 2026a Table A-1 and the engine codec table: 24 match, 1 fixed (.4.110 is "JPEG XL Lossless", D9), now pinned by dicom-compressTests; JPEG Extended 8/12-bit per PS3.5 2026a Table 8.2.1-1; the cited PS3.5 A.4.4 / A.4.12 section titles confirmed; 21 options classified (input contract); compressed / decompressed output checked on fixtures against PS3.3 C.7.6.1.1.5 and PS3.5 8.2, 8.2.4, 8.2.14, 10.18.1 (engine findings deferred)
import Foundation
import ArgumentParser
import DICOMCore
import DICOMKit
import DICOMDictionary

@available(macOS 10.15, *)
struct DICOMCompress: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-compress",
        abstract: "DICOM compression and decompression utilities",
        discussion: """
            Compress, decompress, and analyze DICOM file transfer syntaxes.
            
            Examples:
              dicom-compress info file.dcm
              dicom-compress info file.dcm --json
              dicom-compress compress input.dcm --output output.dcm --codec jpeg-lossless
              dicom-compress compress input.dcm --output output.dcm --codec jpeg2000 --quality high
              dicom-compress decompress compressed.dcm --output uncompressed.dcm
              dicom-compress decompress compressed.dcm --output uncompressed.dcm --syntax explicit-le
              dicom-compress batch input_dir/ --output output_dir/ --codec jpeg-lossless --recursive
              dicom-compress batch input_dir/ --output output_dir/ --decompress --recursive
            """,
        version: "1.3.3",
        subcommands: [Compress.self, Decompress.self, Info.self, Batch.self, Backends.self],
        defaultSubcommand: Info.self
    )
}

// MARK: - Compress Subcommand

@available(macOS 10.15, *)
extension DICOMCompress {
    struct Compress: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Compress a DICOM file using a specified codec",
            discussion: """
                Compress uncompressed DICOM images to various codecs.
                
                Supported codecs (per PS3.5 A.4.4/A.4.12 the general JPEG 2000 / HTJ2K / JPEG XL
                UIDs carry either a lossy or lossless codestream, so each offers a symmetric
                -lossy/-lossless pair plus a -lossless-only entry for the reversible-only UID):
                  jpeg, jpeg-baseline       JPEG Baseline (lossy, 8-bit)
                  jpeg-extended             JPEG Extended (lossy, 8/12-bit)
                  jpeg-lossless             JPEG Lossless (Process 14)
                  jpeg-lossless-sv1         JPEG Lossless SV1 (default lossless JPEG)
                  jpeg2000, jpeg2000-lossy  JPEG 2000, lossy            (.91)
                  jpeg2000-lossless         JPEG 2000, lossless         (.91)
                  jpeg2000-lossless-only    JPEG 2000 Lossless Only     (.90)
                  j2k-part2, …-lossy        JPEG 2000 Part 2, lossy     (.93)
                  j2k-part2-lossless        JPEG 2000 Part 2, lossless  (.93)
                  j2k-part2-lossless-only   JPEG 2000 Part 2 Lossless Only (.92)
                  htj2k, htj2k-lossy        HTJ2K, lossy                (.203)
                  htj2k-lossless            HTJ2K, lossless             (.203)
                  htj2k-lossless-only       HTJ2K Lossless Only         (.201)
                  htj2k-rpcl-lossless-only  HTJ2K RPCL Lossless Only    (.202)
                  jpeg-ls-lossless          JPEG-LS Lossless
                  jpeg-ls, jls              JPEG-LS Near-Lossless
                  jpeg-xl, jpeg-xl-lossy    JPEG XL, lossy              (.112)
                  jpeg-xl-lossless          JPEG XL, lossless           (.112)
                  jpeg-xl-lossless-only     JPEG XL Lossless            (.110)
                  rle                       RLE Lossless
                  deflate                   Deflated Explicit VR Little Endian
                  explicit-le               Explicit VR Little Endian
                  implicit-le               Implicit VR Little Endian
                
                Examples:
                  dicom-compress compress input.dcm --output output.dcm --codec jpeg-lossless
                  dicom-compress compress input.dcm --output output.dcm --codec jpeg2000 --quality high
                  dicom-compress compress input.dcm --output output.dcm --codec htj2k-lossless
                  dicom-compress compress input.dcm --output output.dcm --codec htj2k --quality 0.9
                """
        )

        @Argument(help: "Input DICOM file path")
        var input: String

        @Option(name: .shortAndLong, help: "Output DICOM file path")
        var output: String

        @Option(name: .shortAndLong, help: "Target codec (e.g., jpeg-lossless, jpeg2000, rle)")
        var codec: String

        @Option(name: .shortAndLong, help: "Quality: maximum, high, medium, low, or a value 0.0-1.0")
        var quality: String?

        @Flag(name: .shortAndLong, help: "Show verbose output")
        var verbose: Bool = false

        @Option(name: .long, help: "Hardware backend: auto (default), metal, accelerate, scalar")
        var backend: String = "auto"

        mutating func validate() throws {
            guard FileManager.default.fileExists(atPath: input) else {
                throw ValidationError("Input file not found: \(input)")
            }
            guard CompressionManager.transferSyntax(for: codec) != nil else {
                let supported = CompressionManager.supportedCodecs().map { $0.name }.joined(separator: ", ")
                throw ValidationError("Unknown codec '\(codec)'. Supported: \(supported)")
            }
            let validBackends = ["auto", "metal", "accelerate", "scalar"]
            guard validBackends.contains(backend.lowercased()) else {
                throw ValidationError("Unknown backend '\(backend)'. Valid options: \(validBackends.joined(separator: ", "))")
            }
        }

        mutating func run() throws {
            let manager = CompressionManager()
            let backendPref = CompressionConsole.backendPreference(for: backend)
            let qualityPreset = try CompressionConsole.parseQuality(quality)

            do {
                // Read input once — reused for source-info detection and compression
                // so the file is not read twice.
                let inputData = try Data(contentsOf: URL(fileURLWithPath: input))

                // Detect recompression (source already compressed → target also a
                // compressed syntax, so the engine decodes to native pixels then
                // re-encodes). Detection lives once in CompressionManager so the CLI
                // and the Studio Workshop agree without re-deriving it.
                let sourceInfo = try? manager.getCompressionInfo(data: inputData)
                let isRecompression = CompressionManager.isRecompression(
                    sourceInfo: sourceInfo, targetCodec: codec, quality: qualityPreset)
                let sourceCodecName = isRecompression ? sourceInfo?.transferSyntaxName : nil

                // All console text comes from the shared CompressionConsole so the
                // CLI and the Studio Workshop never drift.
                if verbose {
                    // Report the backend selected for this codec's encode step, not
                    // merely the best available hardware. Auto uses Metal for both
                    // lossy and lossless J2K/HTJ2K when Metal is available.
                    let resolvedBackend = CompressionConsole.compressBackend(
                        codec: codec, preference: backendPref)
                    fprint(CompressionConsole.compressPreamble(
                        input: input, codec: codec, quality: quality,
                        backendDisplayName: resolvedBackend.displayName,
                        sourceTransferSyntaxName: sourceCodecName,
                        backendNote: resolvedBackend.note))
                } else if let name = sourceCodecName {
                    fprint(CompressionConsole.recompressNoteLine(sourceName: name))
                }

                // Engine returns per-phase metrics (a recompression is timed/sized as a
                // decompress phase + a compress phase); the console text is derived from
                // them in DICOMKit core so the CLI and Studio never drift.
                let (outputData, metrics) = try manager.compressDataWithMetrics(
                    inputData, codec: codec, quality: qualityPreset, sourceInfo: sourceInfo,
                    backend: backendPref)
                // `--output` may name a directory (the Workshop hands one back, and
                // `~/Desktop/DICOM_Output/` is the natural thing to type). The shared
                // resolver turns it into a file so the write cannot fail with
                // "Is a directory", and reports the path actually written.
                let destination = OutputPathResolver.resolveFileOutput(
                    output: output, input: input, fileExtension: "dcm")
                try FileManager.default.createDirectory(
                    at: URL(fileURLWithPath: destination).deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try outputData.write(to: URL(fileURLWithPath: destination))

                fprint(CompressionConsole.compressResultLine(input: input, output: destination))
                if verbose {
                    fprint(CompressionConsole.compressStats(
                        inputSize: metrics.inputSize, intermediateSize: metrics.intermediateSize,
                        outputSize: metrics.outputSize, decompressElapsed: metrics.decompressElapsed,
                        compressElapsed: metrics.compressElapsed))
                } else {
                    fprint(CompressionConsole.compressSummary(
                        inputSize: metrics.inputSize, intermediateSize: metrics.intermediateSize,
                        outputSize: metrics.outputSize, decompressElapsed: metrics.decompressElapsed,
                        compressElapsed: metrics.compressElapsed))
                }
            } catch {
                fprintln("Error: \(error)")
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Decompress Subcommand

@available(macOS 10.15, *)
extension DICOMCompress {
    struct Decompress: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Decompress a compressed DICOM file",
            discussion: """
                Decompress compressed DICOM images to a native (uncompressed) transfer syntax.
                
                Target syntaxes (native, PS3.5 A.1, A.2, A.5; A.3 retired):
                  explicit-le   Explicit VR Little Endian (default)
                  implicit-le   Implicit VR Little Endian
                  deflate       Deflated Explicit VR Little Endian
                  explicit-be   Explicit VR Big Endian (Retired) — for legacy readers only;
                                PS3.5 A.3 retired it in 2006 (described in PS3.5 2016b)
                
                Refused (exit 1): every compressed codec name (use `compress`).
                
                Examples:
                  dicom-compress decompress compressed.dcm --output uncompressed.dcm
                  dicom-compress decompress compressed.dcm --output uncompressed.dcm --syntax explicit-le
                """
        )

        @Argument(help: "Input DICOM file path")
        var input: String

        @Option(name: .shortAndLong, help: "Output DICOM file path")
        var output: String

        @Option(name: .shortAndLong, help: "Native target syntax: explicit-le (default), implicit-le, deflate, explicit-be (retired)")
        var syntax: String = "explicit-le"

        @Flag(name: .shortAndLong, help: "Show verbose output")
        var verbose: Bool = false

        mutating func validate() throws {
            guard FileManager.default.fileExists(atPath: input) else {
                throw ValidationError("Input file not found: \(input)")
            }
            _ = try CompressionConsole.NativeTargetSyntax.resolve(syntax)
        }

        mutating func run() throws {
            let manager = CompressionManager()
            let targetSyntax = try CompressionConsole.NativeTargetSyntax.resolve(syntax)

            if verbose {
                fprint(CompressionConsole.decompressPreamble(
                    input: input,
                    targetSyntaxName: CompressionManager.transferSyntaxDisplayName(targetSyntax)))
            }

            do {
                let inputData = try Data(contentsOf: URL(fileURLWithPath: input))

                let start = Date()
                let outputData = try manager.decompressData(inputData, syntax: targetSyntax)
                let elapsed = Date().timeIntervalSince(start)
                // Same directory-aware resolution as `compress` — see the note there.
                let destination = OutputPathResolver.resolveFileOutput(
                    output: output, input: input, fileExtension: "dcm")
                try FileManager.default.createDirectory(
                    at: URL(fileURLWithPath: destination).deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try outputData.write(to: URL(fileURLWithPath: destination))

                fprint(CompressionConsole.decompressResultLine(input: input, output: destination))
                if verbose {
                    fprint(CompressionConsole.decompressStats(
                        inputSize: inputData.count, outputSize: outputData.count, elapsed: elapsed))
                } else {
                    fprint(CompressionConsole.decompressSummary(
                        inputSize: inputData.count, outputSize: outputData.count, elapsed: elapsed))
                }
            } catch {
                fprintln("Error: \(error)")
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Info Subcommand

@available(macOS 10.15, *)
extension DICOMCompress {
    struct Info: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show compression information about a DICOM file",
            discussion: """
                Display transfer syntax, compression status, and image parameters.
                
                --json keys: the PS3.6 Table 6-1 keywords TransferSyntaxUID, Rows, Columns,
                BitsAllocated, BitsStored, SamplesPerPixel, PhotometricInterpretation,
                NumberOfFrames and LossyImageCompression (when present). The camelCase keys
                (transferSyntaxUID, rows, columns, bitsAllocated, bitsStored, samplesPerPixel,
                photometricInterpretation, numberOfFrames) are deprecated and keep their old
                values; file, transferSyntax, compressed, lossless, codec and pixelDataSize
                are tool keys.
                
                Examples:
                  dicom-compress info file.dcm
                  dicom-compress info file.dcm --json
                """
        )

        @Argument(help: "DICOM file path")
        var input: String

        @Flag(name: .long, help: "Output as JSON")
        var json: Bool = false

        mutating func validate() throws {
            guard FileManager.default.fileExists(atPath: input) else {
                throw ValidationError("File not found: \(input)")
            }
        }

        mutating func run() throws {
            let manager = CompressionManager()

            do {
                let info = try manager.getCompressionInfo(path: input)

                if json {
                    print(try CompressionConsole.infoJSON(info, filePath: input), terminator: "")
                } else {
                    print(CompressionConsole.infoText(info, filePath: input), terminator: "")
                }
            } catch {
                fprint(CompressionConsole.infoErrorLine(error))
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Batch Subcommand

@available(macOS 10.15, *)
extension DICOMCompress {
    struct Batch: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Batch compress or decompress DICOM files in a directory",
            discussion: """
                Process all DICOM files in a directory, optionally recursing into subdirectories.
                
                Examples:
                  dicom-compress batch input_dir/ --output output_dir/ --codec jpeg-lossless
                  dicom-compress batch input_dir/ --output output_dir/ --codec jpeg2000 --quality high --recursive
                  dicom-compress batch input_dir/ --output output_dir/ --decompress --recursive
                """
        )

        @Argument(help: "Input directory path")
        var input: String

        @Option(name: .shortAndLong, help: "Output directory path")
        var output: String

        @Option(name: .shortAndLong, help: "Target codec for compression (e.g., jpeg-lossless, jpeg2000)")
        var codec: String?

        @Flag(name: .long, help: "Decompress files instead of compressing")
        var decompress: Bool = false

        @Option(name: .shortAndLong, help: "Quality: maximum, high, medium, low, or a value 0.0-1.0")
        var quality: String?

        @Option(name: .shortAndLong, help: "Native target syntax for decompression: explicit-le (default), implicit-le, deflate, explicit-be (retired)")
        var syntax: String = "explicit-le"

        @Flag(name: .shortAndLong, help: "Process subdirectories recursively")
        var recursive: Bool = false

        @Flag(name: .long, help: "Show verbose output")
        var verbose: Bool = false

        mutating func validate() throws {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: input, isDirectory: &isDir), isDir.boolValue else {
                throw ValidationError("Input directory not found: \(input)")
            }
            if !decompress && codec == nil {
                throw ValidationError("Specify --codec for compression or use --decompress for decompression")
            }
            if let c = codec {
                guard CompressionManager.transferSyntax(for: c) != nil else {
                    let supported = CompressionManager.supportedCodecs().map { $0.name }.joined(separator: ", ")
                    throw ValidationError("Unknown codec '\(c)'. Supported: \(supported)")
                }
            }
            if decompress {
                _ = try CompressionConsole.NativeTargetSyntax.resolve(syntax)
            }
        }

        mutating func run() throws {
            let manager = CompressionManager()

            // Create output directory
            try FileManager.default.createDirectory(
                atPath: output,
                withIntermediateDirectories: true
            )

            let files: [String]
            do {
                files = try CompressionManager.findDICOMFiles(in: input, recursive: recursive)
            } catch {
                fprintln("Error scanning directory: \(error)")
                throw ExitCode.failure
            }

            if files.isEmpty {
                fprintln("No DICOM files found in: \(input)")
                throw ExitCode.failure
            }

            fprint(CompressionConsole.batchFoundLine(count: files.count))

            let qualityPreset = try CompressionConsole.parseQuality(quality)
            var successCount = 0
            var failCount = 0

            for filePath in files {
                // Compute relative path and build output path
                let relativePath: String
                if filePath.hasPrefix(input) {
                    var rel = String(filePath.dropFirst(input.count))
                    if rel.hasPrefix("/") { rel = String(rel.dropFirst()) }
                    relativePath = rel
                } else {
                    relativePath = URL(fileURLWithPath: filePath).lastPathComponent
                }

                let outputPath = (output as NSString).appendingPathComponent(relativePath)

                // Create intermediate directories
                let outputDir = (outputPath as NSString).deletingLastPathComponent
                try FileManager.default.createDirectory(
                    atPath: outputDir,
                    withIntermediateDirectories: true
                )

                do {
                    if decompress {
                        let targetSyntax = try CompressionConsole.NativeTargetSyntax.resolve(syntax)
                        try manager.decompressFile(
                            inputPath: filePath,
                            outputPath: outputPath,
                            syntax: targetSyntax
                        )
                    } else {
                        try manager.compressFile(
                            inputPath: filePath,
                            outputPath: outputPath,
                            codec: codec!,
                            quality: qualityPreset
                        )
                    }
                    successCount += 1
                    if verbose {
                        fprint(CompressionConsole.batchProgressLine(success: true, relativePath: relativePath, error: nil))
                    }
                } catch {
                    failCount += 1
                    if verbose {
                        fprint(CompressionConsole.batchProgressLine(success: false, relativePath: relativePath, error: "\(error)"))
                    }
                }
            }

            fprint(CompressionConsole.batchSummaryLine(
                decompress: decompress, success: successCount, fail: failCount, total: files.count))

            if failCount > 0 {
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Native decompress targets

/// `decompress --syntax` / `batch --syntax`: only native Transfer Syntaxes are targets
/// (P-COMPRESS-SYNTAX). PS3.6 2026a Table A-1 names, PS3.5 2026a A.1 (Implicit VR Little
/// Endian), A.2 (Explicit VR Little Endian), A.5 (Deflated Explicit VR Little Endian), and
/// the retired A.3 Explicit VR Big Endian (accepted again since the engine writer byte-swaps
/// values per PS3.5 2026a 7.3, D206). Every other name — the compressed codecs included — is
/// refused with exit 1.
/// The pre-D267 name of `CompressionConsole.NativeTargetSyntax` (the native `--syntax` targets of
/// `decompress` / `batch --decompress` and their refusal texts), now shared with the DICOMStudio
/// CLI Workshop. The tool calls the DICOMKit type; this typealias only forwards.
@available(*, deprecated, renamed: "CompressionConsole.NativeTargetSyntax")
typealias NativeTargetSyntax = CompressionConsole.NativeTargetSyntax

// MARK: - Helpers

private func fprintln(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8) ?? Data())
}

/// Writes pre-formatted text (already newline-terminated) to stderr verbatim.
/// Used with `CompressionConsole` builders so the CLI emits byte-for-byte the
/// same text DICOMStudio's Workshop renders. See CompressionConsole.swift.
private func fprint(_ message: String) {
    FileHandle.standardError.write(message.data(using: .utf8) ?? Data())
}

// MARK: - Backends subcommand

@available(macOS 10.15, *)
extension DICOMCompress {
    struct Backends: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "backends",
            abstract: "List available hardware acceleration backends",
            discussion: """
                Displays the hardware acceleration backends available on this platform
                and shows which backend will be used automatically.

                Examples:
                  dicom-compress backends
                  dicom-compress backends --json
                """
        )

        @Flag(name: .long, help: "Output as JSON")
        var json: Bool = false

        mutating func run() throws {
            if json {
                print(try CompressionConsole.backendsJSON(), terminator: "")
            } else {
                print(CompressionConsole.backendsText(), terminator: "")
            }
        }
    }
}

DICOMCompress.main()
