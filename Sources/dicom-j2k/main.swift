// NEMA-verified: 2026a, checked 2026-10-01 — P-items: --frame-number (1-based, PS3.3 2026a Table 10-3) on info/validate/roi/benchmark/compare, 0-based --frame deprecated, labels "Frame number N"; --json adds PS3.6 2026a Table 6-1 keys TransferSyntaxUID / NumberOfFrames (camelCase keys deprecated); the 3 j2k-part2-* targets refused (PS3.5 2026a A.4.4, exit 1); JPEG2000Lossless / HTJ2KLossless select their Table A-1 UIDs .90 / .201 (note printed). Earlier: the 7 UID/name rows of the help diffed by script against PS3.6 2026a Table A-1 (7 wrong names fixed) and the 10 transcode target rows (alias → UID → intent, 10 match); 33 options classified (input contract); frame lookup, Photometric Interpretation, lossy provenance, derived-image and .202 handling moved to J2KDICOMBoundary.swift (PS3.5 A.4.4, 8.2.4, 8.2.14, 10.18.1; PS3.3 C.7.6.1.1.2, C.7.6.1.1.5); --quality now reaches the encoder; validate exits 2 on read errors as documented
// main.swift — dicom-j2k
// JPEG 2000 / HTJ2K codestream operations on DICOM files.
//
// Phase 9.1 of J2KSwift v3 integration (J2KSWIFT_V3_2_INTEGRATION_PLAN.md).

import Foundation
import ArgumentParser
import DICOMCore
import DICOMKit
import DICOMDictionary
import J2KCore
import J2KCodec
import J2KFileFormat

@available(macOS 10.15, *)
struct DICOMJ2K: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-j2k",
        abstract: "JPEG 2000 / HTJ2K codestream operations on DICOM files",
        discussion: """
            Inspect, validate, transcode, reduce, and benchmark the JPEG 2000 or HTJ2K
            codestream embedded in a DICOM file. All operations preserve the DICOM
            metadata and re-wrap the result in a conformant DICOM file.

            Transfer Syntaxes supported:
              1.2.840.10008.1.2.4.90  JPEG 2000 Image Compression (Lossless Only)
              1.2.840.10008.1.2.4.91  JPEG 2000 Image Compression
              1.2.840.10008.1.2.4.92  JPEG 2000 Part 2 Multi-component Image Compression (Lossless Only)
              1.2.840.10008.1.2.4.93  JPEG 2000 Part 2 Multi-component Image Compression
              1.2.840.10008.1.2.4.201 High-Throughput JPEG 2000 Image Compression (Lossless Only)
              1.2.840.10008.1.2.4.202 High-Throughput JPEG 2000 with RPCL Options Image Compression (Lossless Only)
              1.2.840.10008.1.2.4.203 High-Throughput JPEG 2000 Image Compression
            (.91, .93 and .203 carry a lossless or a lossy codestream, PS3.5 A.4.4.)

            Examples:
              dicom-j2k info scan.dcm
              dicom-j2k info scan.dcm --json
              dicom-j2k validate scan.dcm
              dicom-j2k transcode j2k.dcm --output htj2k.dcm --target htj2k-lossless
              dicom-j2k transcode htj2k.dcm --output j2k.dcm --target j2k-lossless
              dicom-j2k reduce input.dcm --output small.dcm --levels 3 --layers 4
              dicom-j2k roi input.dcm --output roi.dcm --frame-number 1 --region 0,0,256,256
              dicom-j2k benchmark scan.dcm
              dicom-j2k benchmark scan.dcm --iterations 20
              dicom-j2k compare ref.dcm test.dcm
              dicom-j2k completions zsh
            """,
        version: "1.0.0",
        subcommands: [
            InfoCommand.self,
            ValidateCommand.self,
            TranscodeCommand.self,
            ReduceCommand.self,
            ROICommand.self,
            BenchmarkCommand.self,
            CompareCommand.self,
            CompletionsCommand.self
        ],
        defaultSubcommand: InfoCommand.self
    )
}

// MARK: - Helpers

/// Load a DICOM file from a path string; throws a user-friendly error on failure.
@available(macOS 10.15, *)
private func loadDICOM(at path: String) throws -> DICOMFile {
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: path) else {
        throw ValidationError("File not found: \(path)")
    }
    do {
        return try DICOMFile.read(from: url)
    } catch {
        throw ValidationError("Failed to read DICOM file '\(path)': \(error.localizedDescription)")
    }
}

/// The J2K codestream of one frame (0-based index = Frame number − 1). A frame may span several fragments
/// (PS3.5 A.4.4); the mapping is in `J2KDICOMBoundary.frameCodestreams`.
@available(macOS 10.15, *)
private func j2kCodestream(from dicom: DICOMFile, frameIndex: Int = 0) throws -> Data {
    do {
        return try J2KDICOMBoundary.frameCodestream(of: dicom, frame: frameIndex)
    } catch let error as J2KDICOMBoundary.FrameError {
        throw ValidationError("No JPEG 2000 codestream for Frame number \(frameIndex + 1): \(error)")
    }
}

/// Every frame's J2K codestream, in frame order.
@available(macOS 10.15, *)
private func j2kCodestreams(from dicom: DICOMFile) throws -> [Data] {
    do {
        return try J2KDICOMBoundary.frameCodestreams(of: dicom)
    } catch let error as J2KDICOMBoundary.FrameError {
        throw ValidationError("Cannot read the JPEG 2000 frames: \(error)")
    }
}

/// Encoder settings that keep the codestream family of `uid` (HTJ2K block coder for
/// .201/.202/.203) and, for .202, the PS3.5 10.18.1 progression (RPCL) and enough
/// decomposition levels for a base resolution of at most 64.
@available(macOS 10.15, *)
private func configureFamily(_ config: inout J2KEncodingConfiguration, uid: String,
                             rows: Int, columns: Int) {
    let ts = TransferSyntax.from(uid: uid)
    if ts?.isHTJ2K == true {
        config.useHTJ2K = true
        config.htj2kBlockFormat = .conformant
    }
    if uid == TransferSyntax.htj2kRPCLLossless.uid {
        config.progressionOrder = .rpcl
        config.decompositionLevels = max(
            config.decompositionLevels,
            J2KDICOMBoundary.minimumDecompositionLevelsForRPCL(rows: rows, columns: columns))
    }
}

/// Warns when a .202 codestream misses a PS3.5 2026a 10.18.1 requirement (the encoder,
/// not this tool, decides the markers it writes).
@available(macOS 10.15, *)
private func warnIfNotRPCLConformant(_ codestream: Data?, uid: String, rows: Int, columns: Int) {
    guard uid == TransferSyntax.htj2kRPCLLossless.uid, let codestream else { return }
    let problems = J2KDICOMBoundary.rpclViolations(
        J2KDICOMBoundary.codestreamFacts(codestream), rows: rows, columns: columns)
    if !problems.isEmpty {
        FileHandle.standardError.write(Data((
            "Warning: PS3.5 10.18.1 (\(uid)): " + problems.joined(separator: "; ") + "\n").utf8))
    }
}

/// Synchronously runs an async throwing closure and returns its result.
/// Used to bridge ParsableCommand.run() (synchronous) with async J2KSwift APIs.
@available(macOS 10.15, *)
@discardableResult
private func runAsync<T: Sendable>(_ block: @escaping @Sendable () async throws -> T) throws -> T {
    let sema = DispatchSemaphore(value: 0)
    // The semaphore's signal->wait is a happens-before edge, so this manually
    // synchronized capture is visible after sema.wait().
    nonisolated(unsafe) var result: Result<T, Error>?
    let task = Task { try await block() }
    Task {
        result = await task.result
        sema.signal()
    }
    sema.wait()
    return try result!.get()
}

/// Decode a J2K codestream synchronously using J2KDecoder.
@available(macOS 10.15, *)
private func decodeJ2K(_ data: Data) throws -> J2KImage {
    try runAsync { try await J2KDecoder().decode(data) }
}

/// Human-readable transfer syntax label from UID, sourced from the shared
/// `TransferSyntax` catalog so labels stay consistent across the whole library.
///
/// For the `both`-capable general UIDs (`.91`/`.93`/`.203`) the bare UID cannot tell
/// the user whether a codestream is reversible. When the caller knows the selected
/// intent (e.g. a compress target), pass `lossless:` so the label spells it out —
/// "JPEG 2000 Part 2 Multi-component Lossy (…93)" rather than the ambiguous base name.
private func tsLabel(_ uid: String?, lossless: Bool? = nil) -> String {
    guard let uid else { return "Unknown" }
    guard let ts = TransferSyntax.from(uid: uid) else { return uid }
    let name: String
    if ts.losslessCapability == .both, let lossless {
        name = SelectableEncoding(transferSyntax: ts, intent: lossless ? .lossless : .lossy).displayName
    } else {
        name = ts.displayName
    }
    return "\(name) (\(uid))"
}

/// True if the transfer syntax UID indicates JPEG 2000 or HTJ2K compression,
/// per the shared `TransferSyntax` source of truth.
private func isJ2KTransferSyntax(_ uid: String?) -> Bool {
    guard let uid else { return false }
    return TransferSyntax.from(uid: uid)?.isJPEG2000 ?? false
}

// MARK: - info

@available(macOS 10.15, *)
extension DICOMJ2K {
    struct InfoCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "info",
            abstract: "Show J2K/HTJ2K codestream metadata embedded in a DICOM file",
            discussion: """
                Decodes the JPEG 2000 or HTJ2K codestream header and displays
                structural metadata: dimensions, components, bit depth, tiling,
                colour space, progression order, quality layers, and HTJ2K flag.

                Examples:
                  dicom-j2k info scan.dcm
                  dicom-j2k info scan.dcm --json
                  dicom-j2k info scan.dcm --frame-number 2

                --json keys: TransferSyntaxUID and NumberOfFrames are the PS3.6 Table 6-1
                keywords; transferSyntaxUID and totalFrames are deprecated (same values).
                frameNumber is the Frame number (from 1); frame is the deprecated 0-based index.
                """
        )

        @Argument(help: "Input DICOM file path")
        var input: String

        @OptionGroup var frameSelection: FrameSelection

        /// 0-based index of the selected frame.
        var frame: Int { frameSelection.index }

        @Flag(name: .long, help: "Output as JSON")
        var json: Bool = false

        @Flag(name: .shortAndLong, help: "Verbose output")
        var verbose: Bool = false

        mutating func run() throws {
            frameSelection.warnIfDeprecated()
            let dicom = try loadDICOM(at: input)
            let tsUID = dicom.transferSyntaxUID

            guard isJ2KTransferSyntax(tsUID) else {
                throw ValidationError(
                    "Not a JPEG 2000 file. Transfer syntax: \(tsLabel(tsUID))"
                )
            }

            let codestream = try j2kCodestream(from: dicom, frameIndex: frame)

            let image = try decodeJ2K(codestream)

            if json {
                printInfoJSON(image: image, codestream: codestream, tsUID: tsUID, dicom: dicom)
            } else {
                printInfoText(image: image, codestream: codestream, tsUID: tsUID, dicom: dicom)
            }
        }

        private func printInfoText(image: J2KImage, codestream: Data, tsUID: String?, dicom: DICOMFile) {
            print("JPEG 2000 Codestream Info")
            print("=========================")
            print("File:             \(input)")
            print("Transfer Syntax:  \(tsLabel(tsUID))")
            print("Frame number:     \(frame + 1) of \(dicom.numberOfFrames ?? 1)")
            print("Codestream Size:  \(ByteCountFormatter.string(fromByteCount: Int64(codestream.count), countStyle: .file))")
            print("")
            print("Image Geometry")
            print("--------------")
            print("Width:            \(image.width) px")
            print("Height:           \(image.height) px")
            print("Components:       \(image.componentCount)")
            print("Colour Space:     \(image.colorSpace)")
            print("Grayscale:        \(image.isGrayscale ? "Yes" : "No")")
            if image.isTiled {
                print("Tile Width:       \(image.tileWidth) px")
                print("Tile Height:      \(image.tileHeight) px")
                print("Tile Count:       \(image.tileCount) (\(image.tilesX)×\(image.tilesY))")
            } else {
                print("Tiling:           None (single tile)")
            }
            print("")
            print("Component Details")
            print("-----------------")
            for comp in image.components {
                let subsamp = comp.isSubsampled ? " [subsampled \(comp.subsamplingX)×\(comp.subsamplingY)]" : ""
                let sign = comp.signed ? "signed" : "unsigned"
                print("  Component \(comp.index): \(comp.bitDepth)-bit \(sign), \(comp.width)×\(comp.height)\(subsamp)")
            }
            if verbose {
                print("")
                print("Geometry Details")
                print("----------------")
                print("Tile Offset X:    \(image.tileOffsetX)")
                print("Tile Offset Y:    \(image.tileOffsetY)")
                print("Image Offset X:   \(image.offsetX)")
                print("Image Offset Y:   \(image.offsetY)")
                print("Aspect Ratio:     \(String(format: "%.4f", image.aspectRatio))")
                print("Pixel Count:      \(image.pixelCount)")
            }
        }

        private func printInfoJSON(image: J2KImage, codestream: Data, tsUID: String?, dicom: DICOMFile) {
            var dict: [String: Any] = [
                "file": input,
                "transferSyntaxUID": tsUID as Any,
                "transferSyntaxDescription": tsLabel(tsUID),
                "frame": frame,
                "frameNumber": frame + 1,
                "totalFrames": dicom.numberOfFrames ?? 1,
                "codestreamBytes": codestream.count,
                "width": image.width,
                "height": image.height,
                "componentCount": image.componentCount,
                "colorSpace": "\(image.colorSpace)",
                "isGrayscale": image.isGrayscale,
                "isTiled": image.isTiled,
                "pixelCount": image.pixelCount,
                "aspectRatio": image.aspectRatio
            ]
            dict.merge(J2KJSONKeys.keywordFields(transferSyntaxUID: tsUID,
                                                 numberOfFrames: dicom.numberOfFrames ?? 1)) { $1 }
            if image.isTiled {
                dict["tileWidth"] = image.tileWidth
                dict["tileHeight"] = image.tileHeight
                dict["tileCount"] = image.tileCount
                dict["tilesX"] = image.tilesX
                dict["tilesY"] = image.tilesY
            }
            let comps = image.components.map { c -> [String: Any] in
                [
                    "index": c.index,
                    "bitDepth": c.bitDepth,
                    "signed": c.signed,
                    "width": c.width,
                    "height": c.height,
                    "subsamplingX": c.subsamplingX,
                    "subsamplingY": c.subsamplingY
                ]
            }
            dict["components"] = comps
            if let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                print(jsonStr)
            }
        }
    }
}

// MARK: - validate

@available(macOS 10.15, *)
extension DICOMJ2K {
    struct ValidateCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "validate",
            abstract: "ISO/IEC 15444-4 conformance check of the embedded J2K codestream",
            discussion: """
                Runs structural validation of the JPEG 2000 or HTJ2K codestream using
                J2KSwift's built-in conformance tester. Reports marker ordering,
                segment-length consistency, capability signalling (CAP marker for HTJ2K),
                and interoperability issues.

                Exit code 0 = valid, 1 = violations found, 2 = read error.

                Examples:
                  dicom-j2k validate scan.dcm
                  dicom-j2k validate scan.dcm --frame-number 1 --strict

                --json keys: TransferSyntaxUID is the PS3.6 Table 6-1 keyword;
                transferSyntaxUID is deprecated (same value). frameNumber is the Frame number
                (from 1); frame is the deprecated 0-based index.
                """
        )

        @Argument(help: "Input DICOM file path")
        var input: String

        @OptionGroup var frameSelection: FrameSelection

        /// 0-based index of the selected frame.
        var frame: Int { frameSelection.index }

        @Flag(name: .long, help: "Treat warnings as errors (strict mode)")
        var strict: Bool = false

        @Flag(name: .long, help: "Output results as JSON")
        var json: Bool = false

        mutating func run() throws {
            frameSelection.warnIfDeprecated()
            // Exit 2 when the file, its transfer syntax or the frame cannot be read, as the
            // discussion documents (exit 1 is reserved for codestream violations).
            let dicom: DICOMFile
            let tsUID: String?
            let codestream: Data
            do {
                dicom = try loadDICOM(at: input)
                tsUID = dicom.transferSyntaxUID
                guard isJ2KTransferSyntax(tsUID) else {
                    throw ValidationError(
                        "Not a JPEG 2000 file. Transfer syntax: \(tsLabel(tsUID))"
                    )
                }
                codestream = try j2kCodestream(from: dicom, frameIndex: frame)
            } catch {
                FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
                throw ExitCode(2)
            }

            let htValidator = HTJ2KConformanceTestHarness()
            let interopValidator = J2KHTInteroperabilityValidator()
            let structureViolations = htValidator.validateCodestreamStructure(codestream)
            let markerViolations = interopValidator.validateMarkerOrdering(codestream: codestream)
            let segmentViolations = interopValidator.validateSegmentLengths(codestream: codestream)
            let capResult = interopValidator.validateCapabilitySignaling(codestream: codestream)
            let interopResult = interopValidator.validateInteroperability(codestream: codestream)

            let capViolations = capResult.errors
            let allViolations = structureViolations + markerViolations + segmentViolations + capViolations
            let interopWarnings = interopResult.warnings
            let isValid = allViolations.isEmpty && (strict ? interopWarnings.isEmpty : true)

            if json {
                var out: [String: Any] = [
                    "file": input,
                    "frame": frame,
                    "frameNumber": frame + 1,
                    "transferSyntaxUID": tsUID as Any,
                    "valid": isValid,
                    "violations": allViolations,
                    "interoperabilityWarnings": interopWarnings
                ]
                out.merge(J2KJSONKeys.keywordFields(transferSyntaxUID: tsUID, numberOfFrames: nil)) { $1 }
                if let data = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]),
                   let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
            } else {
                print("Validation: \(input) (Frame number \(frame + 1))")
                print("Transfer Syntax: \(tsLabel(tsUID))")
                print("")
                if allViolations.isEmpty {
                    print("✓ No structural violations found.")
                } else {
                    print("✗ \(allViolations.count) violation(s):")
                    for v in allViolations { print("  · \(v)") }
                }
                if !interopWarnings.isEmpty {
                    print("\nInteroperability warnings (\(interopWarnings.count)):")
                    for w in interopWarnings { print("  · \(w)") }
                }
                print("")
                print("Result: \(isValid ? "VALID ✓" : "INVALID ✗")")
            }

            if !isValid {
                throw ExitCode(1)
            }
        }
    }
}

// MARK: - transcode

@available(macOS 10.15, *)
extension DICOMJ2K {
    struct TranscodeCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "transcode",
            abstract: "Transcode J2K ↔ HTJ2K while preserving DICOM metadata",
            discussion: """
                Decodes the source JPEG 2000 / HTJ2K codestream and re-encodes it using
                the specified target transfer syntax. The DICOM dataset is preserved
                bit-for-bit except for the pixel data element and transfer syntax UID.

                Target transfer syntax values (the general .91/.203 UIDs carry either a
                lossy or a lossless codestream per PS3.5 A.4.4; "-lossless-only" selects the
                distinct reversible-only UID):
                  j2k-lossy                 JPEG 2000, lossy          (1.2.840.10008.1.2.4.91)
                  j2k-lossless              JPEG 2000, lossless       (1.2.840.10008.1.2.4.91)
                  j2k-lossless-only         JPEG 2000 Lossless Only   (1.2.840.10008.1.2.4.90)
                  htj2k-lossy               HTJ2K, lossy              (1.2.840.10008.1.2.4.203)
                  htj2k-lossless            HTJ2K, lossless           (1.2.840.10008.1.2.4.203)
                  htj2k-lossless-only       HTJ2K Lossless Only       (1.2.840.10008.1.2.4.201)
                  htj2k-rpcl-lossless-only  HTJ2K Lossless Only, RPCL (1.2.840.10008.1.2.4.202)

                Refused (exit 1) — .92 / .93 specify the JPEG 2000 Part 2 multiple component
                transformation extensions (PS3.5 A.4.4), which the encoder does not write:
                  j2k-part2-lossy           JPEG 2000 Part 2, lossy   (1.2.840.10008.1.2.4.93)
                  j2k-part2-lossless        JPEG 2000 Part 2, lossless(1.2.840.10008.1.2.4.93)
                  j2k-part2-lossless-only   JPEG 2000 Part 2 Lossless Only (1.2.840.10008.1.2.4.92)

                A PS3.6 Table A-1 keyword selects its Table A-1 UID: JPEG2000Lossless now means
                .90 and HTJ2KLossless .201 (a note is printed); the reversible encode into .91 /
                .203 is JPEG2000Reversible / HTJ2KReversible (or j2k-lossless / htj2k-lossless).

                Examples:
                  dicom-j2k transcode j2k.dcm --output htj2k.dcm --target htj2k-lossless
                  dicom-j2k transcode htj2k.dcm --output j2k.dcm --target j2k-lossless
                  dicom-j2k transcode input.dcm --output out.dcm --target htj2k --quality 0.9
                """
        )

        @Argument(help: "Input DICOM file path")
        var input: String

        @Option(name: .shortAndLong, help: "Output DICOM file path")
        var output: String

        @Option(name: .shortAndLong, help: "Target transfer syntax (j2k-lossy, j2k-lossless, j2k-lossless-only, htj2k-lossy, htj2k-lossless, htj2k-lossless-only, htj2k-rpcl-lossless-only; the j2k-part2-* targets are refused, PS3.5 A.4.4)")
        var target: String

        @Option(name: .shortAndLong, help: "Encoding quality 0.0–1.0 (ignored for lossless targets)")
        var quality: Double = 0.9

        @Flag(name: .shortAndLong, help: "Verbose output")
        var verbose: Bool = false

        mutating func validate() throws {
            // Validate against the shared catalog so the accepted names track the library.
            // Any JPEG 2000 / HTJ2K target (lossy, lossless, or lossless-only) is allowed.
            guard let enc = TransferSyntax.parseEncoding(target), enc.transferSyntax.isJPEG2000 else {
                throw ValidationError(
                    "Invalid target '\(target)'. Valid values: j2k-lossy, j2k-lossless, "
                    + "j2k-lossless-only, htj2k-lossy, htj2k-lossless, htj2k-lossless-only, "
                    + "htj2k-rpcl-lossless-only")
            }
            // P-J2K-PART2: .92 / .93 are the Part 2 multi-component extensions; refused as the
            // engine refuses them (exit 1, not a usage error).
            if let reason = Self.part2RefusalReason(enc.transferSyntax) {
                throw TargetRefused(description: reason)
            }
            guard (0.0...1.0).contains(quality) else {
                throw ValidationError("Quality must be between 0.0 and 1.0")
            }
        }

        mutating func run() throws {
            if let note = TransferSyntax.reassignedKeywordNote(for: target) {
                FileHandle.standardError.write(Data((note + "\n").utf8))
            }
            let dicom = try loadDICOM(at: input)
            let srcUID = dicom.transferSyntaxUID
            guard isJ2KTransferSyntax(srcUID) else {
                throw ValidationError(
                    "Not a JPEG 2000 file. Transfer syntax: \(tsLabel(srcUID))"
                )
            }

            // Resolve UID + encode intent from the shared catalog. The general UIDs
            // (.91/.203) honour the selected lossy/lossless intent (e.g. `htj2k-lossless`
            // encodes reversibly into .203); the lossless-only UIDs (.90/.201/.202) are
            // always lossless. `parseEncoding` is validated non-nil in validate().
            let targetEncoding = TransferSyntax.parseEncoding(target)
                ?? SelectableEncoding(transferSyntax: .jpeg2000Lossless, intent: .notApplicable)
            let targetUID = targetEncoding.transferSyntax.uid
            let isLossless = targetEncoding.isLossless

            if verbose {
                print("Source:  \(tsLabel(srcUID))")
                print("Target:  \(tsLabel(targetUID, lossless: isLossless))")
                print("Quality: \(isLossless ? "lossless" : String(format: "%.2f", quality))")
            }

            // Decode all frames, re-encode, and rebuild DICOM
            let rows = Int(dicom.dataSet.uint16(for: .rows) ?? 0)
            let columns = Int(dicom.dataSet.uint16(for: .columns) ?? 0)
            var encConfig = J2KEncodingConfiguration()
            encConfig.lossless = isLossless
            // --quality drives the irreversible encode (ignored when lossless).
            if !isLossless { encConfig.quality = quality }
            // HTJ2K block coder (ISO/IEC 15444-15, conformant wire format) for .201/.202/.203,
            // and the PS3.5 10.18.1 RPCL settings for .202.
            configureFamily(&encConfig, uid: targetUID, rows: rows, columns: columns)

            let encoder = J2KEncoder(encodingConfiguration: encConfig)
            var newFragments = [Data]()
            for cs in try j2kCodestreams(from: dicom) {
                let img = try decodeJ2K(cs)
                let enc: Data = try runAsync { try await encoder.encode(img) }
                newFragments.append(enc)
            }

            guard !newFragments.isEmpty else {
                throw ValidationError("No J2K frames found in input file.")
            }
            warnIfNotRPCLConformant(newFragments.first, uid: targetUID, rows: rows, columns: columns)

            var newDataSet = dicom.dataSet
            var newMeta = dicom.fileMetaInformation
            J2KDICOMBoundary.setEncapsulatedPixelData(newFragments, in: &newDataSet)
            // Photometric Interpretation follows the written codestream (PS3.5 8.2.4 / 8.2.14).
            J2KDICOMBoundary.applyPixelModule(to: &newDataSet, firstCodestream: newFragments[0])
            // An irreversible encode is lossy compression (PS3.3 C.7.6.1.1.5).
            if !isLossless, let method = targetEncoding.transferSyntax.lossyImageCompressionMethod {
                J2KDICOMBoundary.applyLossyCompression(
                    to: &newDataSet, meta: &newMeta, method: method,
                    uncompressedBytes: J2KDICOMBoundary.uncompressedByteCount(
                        of: newDataSet, frames: newFragments.count),
                    compressedBytes: newFragments.reduce(0) { $0 + $1.count })
            }

            // Update transfer syntax in file meta
            newMeta.setString(targetUID, for: .transferSyntaxUID, vr: .UI)
            J2KDICOMBoundary.invalidateGroupLength(&newMeta)

            let newFile = DICOMFile(fileMetaInformation: newMeta, dataSet: newDataSet)
            let outputURL = URL(fileURLWithPath: output)
            let data = try newFile.write()
            try data.write(to: outputURL)

            if verbose {
                print("Written to: \(output)")
            } else {
                print("Transcoded to \(target): \(output)")
            }
        }

        /// The refusal text for a JPEG 2000 Part 2 target (.92 / .93), `nil` for any other.
        /// PS3.5 2026a A.4.4: these UIDs specify the Part 2 (Annex J) multiple component
        /// transformation extensions; the encoder writes Part 1 codestreams only.
        static func part2RefusalReason(_ syntax: TransferSyntax) -> String? {
            guard syntax.isJPEG2000Part2 else { return nil }
            let engine = J2KRoutePlanner.unsupportedEncodeReason(transferSyntaxUID: syntax.uid)
                ?? "\(syntax.uid) encoding is not supported."
            return "Target refused: \(syntax.uid) specifies the JPEG 2000 Part 2 multiple component "
                + "transformation extensions (PS3.5 2026a A.4.4), which dicom-j2k does not write. " + engine
        }
    }
}

/// A refused `--target`. Not a `ValidationError`, so the command exits 1.
struct TargetRefused: LocalizedError, CustomStringConvertible {
    let description: String
    var errorDescription: String? { description }
}

// MARK: - JSON keys (PS3.6 Table 6-1)

/// The PS3.6 2026a Table 6-1 keyword keys of the `--json` outputs (P-J2K-JSON), added next to
/// the deprecated camelCase keys (`transferSyntaxUID`, `totalFrames`), which keep their values:
/// TransferSyntaxUID (0002,0010) and NumberOfFrames (0028,0008).
enum J2KJSONKeys {
    static func keywordFields(transferSyntaxUID: String?, numberOfFrames: Int?) -> [String: Any] {
        var fields: [String: Any] = ["TransferSyntaxUID": transferSyntaxUID as Any]
        if let n = numberOfFrames { fields["NumberOfFrames"] = n }
        return fields
    }
}

// MARK: - Frame selection (PS3.3 Table 10-3)

/// `--frame-number` (1-based, PS3.3 2026a Table 10-3: "The first Frame shall be denoted as Frame
/// number 1") and the deprecated 0-based `--frame` (P-J2K-FRAME). Both at once exits 1.
struct FrameSelection: ParsableArguments {
    @Option(name: .long, help: "Frame number, numbered from 1 (PS3.3 Table 10-3; default 1)")
    var frameNumber: Int?

    @Option(name: .long, help: "deprecated: 0-based index; use --frame-number")
    var frame: Int?

    mutating func validate() throws {
        if let n = frameNumber, n < 1 {
            throw ValidationError("--frame-number must be 1 or more (PS3.3 Table 10-3: the first Frame is Frame number 1)")
        }
        if let f = frame, f < 0 {
            throw ValidationError("--frame is a 0-based index and must be 0 or more")
        }
        if frame != nil && frameNumber != nil {
            throw FrameSelectionConflict()
        }
    }

    /// 0-based index: --frame-number − 1, else the deprecated --frame, else the first frame.
    var index: Int { frameNumber.map { $0 - 1 } ?? frame ?? 0 }

    /// The one-line stderr deprecation note when --frame was used.
    static let deprecationNote =
        "warning: --frame is deprecated (0-based index); use --frame-number (numbered from 1, PS3.3 Table 10-3)"

    func warnIfDeprecated() {
        if frame != nil { FileHandle.standardError.write(Data((Self.deprecationNote + "\n").utf8)) }
    }
}

/// `--frame` and `--frame-number` given together. Not a `ValidationError`, so exit 1.
struct FrameSelectionConflict: LocalizedError, CustomStringConvertible {
    var description: String {
        "--frame (deprecated, 0-based) and --frame-number (numbered from 1) cannot be used together"
    }
    var errorDescription: String? { description }
}

// MARK: - reduce

@available(macOS 10.15, *)
extension DICOMJ2K {
    struct ReduceCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "reduce",
            abstract: "Re-encode losslessly with other decomposition levels or quality layers",
            discussion: """
                Decodes every frame and re-encodes it reversibly with the given number of
                wavelet decomposition levels (the reduced resolutions a decoder can extract)
                and quality layers. The re-encode is lossless: pixel values, Rows (0028,0010),
                Columns (0028,0011) and the transfer syntax stay as they are.

                --levels  Number of wavelet decomposition levels (1–10). For
                          1.2.840.10008.1.2.4.202 at least enough for a base resolution
                          of 64 or less (PS3.5 10.18.1).
                --layers  Number of quality layers (1–20).

                Examples:
                  dicom-j2k reduce input.dcm --output thumb.dcm --levels 2
                  dicom-j2k reduce input.dcm --output preview.dcm --levels 3 --layers 4
                """
        )

        @Argument(help: "Input DICOM file path")
        var input: String

        @Option(name: .shortAndLong, help: "Output DICOM file path")
        var output: String

        @Option(name: .long, help: "Number of wavelet decomposition levels (1–10)")
        var levels: Int?

        @Option(name: .long, help: "Number of quality layers (1–20)")
        var layers: Int?

        @Flag(name: .shortAndLong, help: "Verbose output")
        var verbose: Bool = false

        mutating func validate() throws {
            if let l = levels, !(1...10).contains(l) {
                throw ValidationError("--levels must be between 1 and 10")
            }
            if let l = layers, !(1...20).contains(l) {
                throw ValidationError("--layers must be between 1 and 20")
            }
            if levels == nil && layers == nil {
                throw ValidationError("Specify at least one of --levels or --layers")
            }
        }

        mutating func run() throws {
            let dicom = try loadDICOM(at: input)
            guard isJ2KTransferSyntax(dicom.transferSyntaxUID) else {
                throw ValidationError(
                    "Not a JPEG 2000 file. Transfer syntax: \(tsLabel(dicom.transferSyntaxUID))"
                )
            }

            let sourceUID = dicom.transferSyntaxUID ?? ""
            let rows = Int(dicom.dataSet.uint16(for: .rows) ?? 0)
            let columns = Int(dicom.dataSet.uint16(for: .columns) ?? 0)
            if sourceUID == TransferSyntax.htj2kRPCLLossless.uid, let l = levels {
                let need = J2KDICOMBoundary.minimumDecompositionLevelsForRPCL(rows: rows, columns: columns)
                guard l >= need else {
                    throw ValidationError(
                        "--levels \(l) is too few for \(sourceUID): PS3.5 10.18.1 needs at least \(need) "
                        + "decomposition levels for a \(columns)×\(rows) image (base resolution ≤ 64).")
                }
            }

            // Reversible re-encode: the pixel values, Rows and Columns do not change.
            var encConfig = J2KEncodingConfiguration()
            encConfig.lossless = true
            if let l = levels {
                encConfig.decompositionLevels = l
                if verbose { print("Re-encoding with \(l) decomposition levels") }
            }
            if let l = layers {
                encConfig.qualityLayers = l
                if verbose { print("Re-encoding with \(l) quality layers") }
            }
            // Keep the codestream family of the unchanged transfer syntax (HTJ2K for .20x).
            configureFamily(&encConfig, uid: sourceUID, rows: rows, columns: columns)

            let encoder = J2KEncoder(encodingConfiguration: encConfig)
            var newFragments = [Data]()
            for cs in try j2kCodestreams(from: dicom) {
                let img = try decodeJ2K(cs)
                let encoded: Data = try runAsync { try await encoder.encode(img) }
                newFragments.append(encoded)
            }
            warnIfNotRPCLConformant(newFragments.first, uid: sourceUID, rows: rows, columns: columns)

            var newDataSet = dicom.dataSet
            J2KDICOMBoundary.setEncapsulatedPixelData(newFragments, in: &newDataSet)
            if let first = newFragments.first {
                J2KDICOMBoundary.applyPixelModule(to: &newDataSet, firstCodestream: first)
            }

            let newFile = DICOMFile(fileMetaInformation: dicom.fileMetaInformation, dataSet: newDataSet)
            let outputURL = URL(fileURLWithPath: output)
            let outData = try newFile.write()
            try outData.write(to: outputURL)

            if verbose {
                print("Written to: \(output)")
            } else {
                print("Reduced DICOM written to: \(output)")
            }
        }
    }
}

// MARK: - roi

@available(macOS 10.15, *)
extension DICOMJ2K {
    struct ROICommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "roi",
            abstract: "Extract a region of interest (ROI) frame into a new DICOM file",
            discussion: """
                Decodes the specified frame, crops to the given rectangle, and re-encodes
                the crop losslessly as a single-frame DICOM file in the original transfer
                syntax. The crop is a derived image (PS3.3 C.7.6.1.1.2): Image Type value 1
                becomes DERIVED, it gets a new SOP Instance UID, Rows / Columns, Number of
                Frames and Image Position (Patient) describe the crop, and Derivation
                Description names the region.

                --region x,y,width,height   Crop rectangle in pixels (origin at top-left).

                Examples:
                  dicom-j2k roi input.dcm --output roi.dcm --frame-number 1 --region 0,0,256,256
                  dicom-j2k roi input.dcm --output roi.dcm --region 128,128,512,512
                """
        )

        @Argument(help: "Input DICOM file path")
        var input: String

        @Option(name: .shortAndLong, help: "Output DICOM file path")
        var output: String

        @OptionGroup var frameSelection: FrameSelection

        /// 0-based index of the selected frame.
        var frame: Int { frameSelection.index }

        @Option(name: .long, help: "Region of interest: x,y,width,height")
        var region: String

        @Flag(name: .shortAndLong, help: "Verbose output")
        var verbose: Bool = false

        mutating func validate() throws {
            let parts = region.split(separator: ",").compactMap { Int($0) }
            guard parts.count == 4 else {
                throw ValidationError("--region must be x,y,width,height (four integers)")
            }
            guard parts[2] > 0, parts[3] > 0 else {
                throw ValidationError("--region width and height must be positive")
            }
            guard parts[0] >= 0, parts[1] >= 0 else {
                throw ValidationError("--region x and y must be 0 or more (origin at the top-left pixel)")
            }
            guard parts[2] <= Int(UInt16.max), parts[3] <= Int(UInt16.max) else {
                throw ValidationError("--region width and height must fit Rows / Columns (US, at most 65535)")
            }
        }

        mutating func run() throws {
            frameSelection.warnIfDeprecated()
            let parts = region.split(separator: ",").compactMap { Int($0) }
            let roiX = parts[0], roiY = parts[1], roiW = parts[2], roiH = parts[3]

            let dicom = try loadDICOM(at: input)
            guard isJ2KTransferSyntax(dicom.transferSyntaxUID) else {
                throw ValidationError(
                    "Not a JPEG 2000 file. Transfer syntax: \(tsLabel(dicom.transferSyntaxUID))"
                )
            }
            let codestream = try j2kCodestream(from: dicom, frameIndex: frame)

            let image = try decodeJ2K(codestream)
            guard roiX + roiW <= image.width, roiY + roiH <= image.height else {
                throw ValidationError(
                    "ROI \(roiX),\(roiY),\(roiW),\(roiH) extends outside image bounds \(image.width)×\(image.height)"
                )
            }

            // Crop each component's data
            let croppedComps: [J2KComponent] = image.components.map { comp in
                let srcW = comp.width, srcH = comp.height
                // Account for subsampling
                let sx = Int(ceil(Double(roiX) / Double(comp.subsamplingX)))
                let sy = Int(ceil(Double(roiY) / Double(comp.subsamplingY)))
                let sw = Int(ceil(Double(roiW) / Double(comp.subsamplingX)))
                let sh = Int(ceil(Double(roiH) / Double(comp.subsamplingY)))
                let actualW = min(sw, srcW - sx)
                let actualH = min(sh, srcH - sy)

                var croppedData = Data(capacity: actualW * actualH * (comp.bitDepth <= 8 ? 1 : 2))
                let bytesPerSample = comp.bitDepth <= 8 ? 1 : 2
                let srcData = comp.data
                for row in 0..<actualH {
                    let srcRow = sy + row
                    let srcOffset = (srcRow * srcW + sx) * bytesPerSample
                    let count = actualW * bytesPerSample
                    if srcOffset + count <= srcData.count {
                        croppedData.append(srcData[srcOffset..<(srcOffset + count)])
                    }
                }
                return J2KComponent(
                    index: comp.index,
                    bitDepth: comp.bitDepth,
                    signed: comp.signed,
                    width: actualW,
                    height: actualH,
                    subsamplingX: comp.subsamplingX,
                    subsamplingY: comp.subsamplingY,
                    data: croppedData
                )
            }

            let croppedImage = J2KImage(
                width: roiW,
                height: roiH,
                components: croppedComps,
                offsetX: 0,
                offsetY: 0,
                tileWidth: roiW,
                tileHeight: roiH,
                tileOffsetX: 0,
                tileOffsetY: 0,
                colorSpace: image.colorSpace
            )

            let sourceUID = dicom.transferSyntaxUID ?? ""
            var encConfig = J2KEncodingConfiguration()
            encConfig.lossless = true
            configureFamily(&encConfig, uid: sourceUID, rows: roiH, columns: roiW)
            let encoder = J2KEncoder(encodingConfiguration: encConfig)
            let encoded: Data = try runAsync { try await encoder.encode(croppedImage) }
            warnIfNotRPCLConformant(encoded, uid: sourceUID, rows: roiH, columns: roiW)

            var newDataSet = dicom.dataSet
            var newMeta = dicom.fileMetaInformation
            J2KDICOMBoundary.setEncapsulatedPixelData([encoded], in: &newDataSet)
            J2KDICOMBoundary.applyPixelModule(to: &newDataSet, firstCodestream: encoded)
            // Rows / Columns, Number of Frames 1, the kept frame's functional groups and the
            // Image Position (Patient) of the crop origin (PS3.3 C.7.6.2.1.1, C.7.6.16).
            J2KDICOMBoundary.applyCrop(to: &newDataSet, frame: frame, x: roiX, y: roiY,
                                       width: roiW, height: roiH)
            // A crop is a derived image with other pixel data: Image Type DERIVED and a new
            // SOP Instance UID (PS3.3 C.7.6.1.1.2).
            let sourceSOP = dicom.dataSet.string(for: .sopInstanceUID) ?? "unknown"
            J2KDICOMBoundary.appendDerivationDescription(
                "Region \(roiX),\(roiY),\(roiW),\(roiH) of Frame number \(frame + 1) of \(sourceSOP)",
                to: &newDataSet)
            J2KDICOMBoundary.markDerived(&newDataSet, meta: &newMeta)

            let newFile = DICOMFile(fileMetaInformation: newMeta, dataSet: newDataSet)
            let outputURL = URL(fileURLWithPath: output)
            let outData = try newFile.write()
            try outData.write(to: outputURL)

            if verbose {
                print("ROI \(roiW)×\(roiH) from Frame number \(frame + 1) written to: \(output)")
            } else {
                print("ROI extracted to: \(output)")
            }
        }
    }
}

// MARK: - benchmark

@available(macOS 10.15, *)
extension DICOMJ2K {
    struct BenchmarkCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "benchmark",
            abstract: "Decode-speed benchmark across J2KSwift codec backends",
            discussion: """
                Decodes the embedded JPEG 2000 / HTJ2K codestream repeatedly and
                reports timing statistics: average, minimum, maximum, median, and
                standard deviation across all iterations.

                Examples:
                  dicom-j2k benchmark scan.dcm
                  dicom-j2k benchmark scan.dcm --iterations 50
                  dicom-j2k benchmark scan.dcm --json

                --json keys: frameNumber is the Frame number (from 1); frame is the deprecated
                0-based index.
                """
        )

        @Argument(help: "Input DICOM file path")
        var input: String

        @OptionGroup var frameSelection: FrameSelection

        /// 0-based index of the selected frame.
        var frame: Int { frameSelection.index }

        @Option(name: .long, help: "Number of decode iterations (default 10)")
        var iterations: Int = 10

        @Flag(name: .long, help: "Output as JSON")
        var json: Bool = false

        @Flag(name: .shortAndLong, help: "Verbose output")
        var verbose: Bool = false

        mutating func validate() throws {
            guard iterations >= 1 else {
                throw ValidationError("--iterations must be at least 1")
            }
        }

        mutating func run() throws {
            frameSelection.warnIfDeprecated()
            let dicom = try loadDICOM(at: input)
            guard isJ2KTransferSyntax(dicom.transferSyntaxUID) else {
                throw ValidationError(
                    "Not a JPEG 2000 file. Transfer syntax: \(tsLabel(dicom.transferSyntaxUID))"
                )
            }
            let codestream = try j2kCodestream(from: dicom, frameIndex: frame)

            if verbose { print("Benchmarking \(input) (\(iterations) iterations)…") }

            let bench = J2KBenchmark(name: "J2K Decode")
            let result = try bench.measureThrowing(iterations: iterations, warmupIterations: 3) {
                _ = try decodeJ2K(codestream)
            }

            if json {
                let out: [String: Any] = [
                    "file": input,
                    "frame": frame,
                    "frameNumber": frame + 1,
                    "iterations": iterations,
                    "codestreamBytes": codestream.count,
                    "averageMs": result.averageTime * 1000,
                    "minMs": result.minTime * 1000,
                    "maxMs": result.maxTime * 1000,
                    "medianMs": result.medianTime * 1000,
                    "stdDevMs": result.standardDeviation * 1000,
                    "operationsPerSecond": result.operationsPerSecond
                ]
                if let data = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]),
                   let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
            } else {
                print("Benchmark: \(input) (Frame number \(frame + 1))")
                print("Transfer Syntax: \(tsLabel(dicom.transferSyntaxUID))")
                print("Codestream: \(ByteCountFormatter.string(fromByteCount: Int64(codestream.count), countStyle: .file))")
                print("Iterations: \(iterations)")
                print("")
                print(String(format: "  Average:  %7.2f ms", result.averageTime * 1000))
                print(String(format: "  Median:   %7.2f ms", result.medianTime * 1000))
                print(String(format: "  Min:      %7.2f ms", result.minTime * 1000))
                print(String(format: "  Max:      %7.2f ms", result.maxTime * 1000))
                print(String(format: "  Std Dev:  %7.2f ms", result.standardDeviation * 1000))
                print(String(format: "  Throughput: %.1f fps", result.operationsPerSecond))
            }
        }
    }
}

// MARK: - compare

@available(macOS 10.15, *)
extension DICOMJ2K {
    struct CompareCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "compare",
            abstract: "Compute PSNR / MSE between two DICOM images",
            discussion: """
                Decodes both DICOM files and computes pixel-level fidelity metrics
                between the reference and test image:
                  MSE   — Mean Squared Error (0 = identical)
                  PSNR  — Peak Signal-to-Noise Ratio in dB (∞ = identical, ≥50 = excellent)
                  MAE   — Mean Absolute Error

                Examples:
                  dicom-j2k compare ref.dcm test.dcm
                  dicom-j2k compare ref.dcm test.dcm --json
                  dicom-j2k compare ref.dcm test.dcm --frame-number 3

                --json keys: frameNumber is the Frame number (from 1); frame is the deprecated
                0-based index.
                """
        )

        @Argument(help: "Reference DICOM file")
        var reference: String

        @Argument(help: "Test DICOM file")
        var test: String

        @OptionGroup var frameSelection: FrameSelection

        /// 0-based index of the selected frame.
        var frame: Int { frameSelection.index }

        @Flag(name: .long, help: "Output as JSON")
        var json: Bool = false

        mutating func run() throws {
            frameSelection.warnIfDeprecated()
            let refDICOM = try loadDICOM(at: reference)
            let tstDICOM = try loadDICOM(at: test)

            // Both files are decoded through the shared pixel pipeline, so a native file and a
            // compressed one are compared sample by sample: Bits Allocated, Pixel
            // Representation and Samples per Pixel (PS3.3 C.7.6.3) decide what a sample is.
            func samples(_ file: DICOMFile, _ name: String) throws -> (values: [Double], bitsStored: Int) {
                let pixels: PixelData
                do {
                    pixels = try file.pixelData(frame: frame)
                } catch {
                    throw ValidationError("Cannot extract Frame number \(frame + 1) from the \(name) file: \(error)")
                }
                guard let values = pixels.pixelValues(forFrame: 0) else {
                    throw ValidationError("Cannot extract pixel data from \(name) file.")
                }
                return (values.map(Double.init), pixels.descriptor.bitsStored)
            }
            let ref = try samples(refDICOM, "reference")
            let tst = try samples(tstDICOM, "test")
            let refPixels = ref.values
            let tstPixels = tst.values
            // Peak value for PSNR: the range of Bits Stored (0028,0101) of the reference.
            let maxVal = Double((1 << ref.bitsStored) - 1)

            guard refPixels.count == tstPixels.count else {
                throw ValidationError(
                    "Pixel count mismatch: reference has \(refPixels.count), test has \(tstPixels.count)."
                )
            }

            let n = Double(refPixels.count)
            let mse = zip(refPixels, tstPixels).map { pow($0 - $1, 2) }.reduce(0, +) / n
            let mae = zip(refPixels, tstPixels).map { abs($0 - $1) }.reduce(0, +) / n
            let psnr = mse == 0 ? Double.infinity : 20 * log10(maxVal) - 10 * log10(mse)
            let identical = mse == 0

            if json {
                let out: [String: Any] = [
                    "reference": reference,
                    "test": test,
                    "frame": frame,
                    "frameNumber": frame + 1,
                    "pixelCount": refPixels.count,
                    "mse": mse,
                    "mae": mae,
                    "psnr": psnr.isInfinite ? "Infinity" : psnr,
                    "identical": identical
                ]
                if let data = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]),
                   let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
            } else {
                print("Comparison: \(reference) vs \(test) (Frame number \(frame + 1))")
                print("")
                print(String(format: "  MSE:  %.4f", mse))
                print(String(format: "  MAE:  %.4f", mae))
                if psnr.isInfinite {
                    print("  PSNR: ∞ dB (identical)")
                } else {
                    print(String(format: "  PSNR: %.2f dB", psnr))
                }
                print("  Identical: \(identical ? "Yes" : "No")")
            }
        }
    }
}

// MARK: - completions

@available(macOS 10.15, *)
extension DICOMJ2K {
    struct CompletionsCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "completions",
            abstract: "Generate shell completion scripts",
            discussion: """
                Generates shell completion scripts for bash, zsh, or fish.

                Examples:
                  dicom-j2k completions bash >> ~/.bash_profile
                  dicom-j2k completions zsh  > ~/.zsh/completions/_dicom-j2k
                  dicom-j2k completions fish > ~/.config/fish/completions/dicom-j2k.fish
                """
        )

        @Argument(help: "Shell type: bash, zsh, or fish")
        var shell: String

        mutating func validate() throws {
            guard ["bash", "zsh", "fish"].contains(shell) else {
                throw ValidationError("Shell must be bash, zsh, or fish")
            }
        }

        mutating func run() throws {
            switch shell {
            case "bash":
                print(bashCompletion())
            case "zsh":
                print(zshCompletion())
            case "fish":
                print(fishCompletion())
            default:
                break
            }
        }

        private func bashCompletion() -> String {
            """
            # bash completion for dicom-j2k
            _dicom_j2k() {
                local cur prev opts cmds
                COMPREPLY=()
                cur="${COMP_WORDS[COMP_CWORD]}"
                prev="${COMP_WORDS[COMP_CWORD-1]}"
                cmds="info validate transcode reduce roi benchmark compare completions"
                opts="--help --version"
                case "${prev}" in
                    info|validate|benchmark|compare) COMPREPLY=($(compgen -f -- "${cur}")); return 0;;
                    transcode|reduce|roi) COMPREPLY=($(compgen -f -- "${cur}")); return 0;;
                    --target) COMPREPLY=($(compgen -W "j2k-lossy j2k-lossless j2k-lossless-only htj2k-lossy htj2k-lossless htj2k-lossless-only htj2k-rpcl-lossless-only" -- "${cur}")); return 0;;
                    completions) COMPREPLY=($(compgen -W "bash zsh fish" -- "${cur}")); return 0;;
                    *) COMPREPLY=($(compgen -W "${cmds} ${opts}" -- "${cur}")); return 0;;
                esac
            }
            complete -F _dicom_j2k dicom-j2k
            """
        }

        private func zshCompletion() -> String {
            """
            #compdef dicom-j2k
            _dicom_j2k() {
                local -a cmds
                cmds=(
                    'info:Show J2K codestream metadata'
                    'validate:ISO 15444-4 conformance check'
                    'transcode:Transcode J2K<->HTJ2K'
                    'reduce:Re-encode with other levels/layers (lossless)'
                    'roi:Extract region of interest'
                    'benchmark:Decode-speed benchmark'
                    'compare:Compute PSNR/MSE between images'
                    'completions:Generate shell completions'
                )
                _describe 'command' cmds
            }
            _dicom_j2k
            """
        }

        private func fishCompletion() -> String {
            """
            # fish completion for dicom-j2k
            complete -c dicom-j2k -f
            complete -c dicom-j2k -n __fish_use_subcommand -a info       -d 'Show J2K codestream metadata'
            complete -c dicom-j2k -n __fish_use_subcommand -a validate   -d 'ISO 15444-4 conformance check'
            complete -c dicom-j2k -n __fish_use_subcommand -a transcode  -d 'Transcode J2K<->HTJ2K'
            complete -c dicom-j2k -n __fish_use_subcommand -a reduce     -d 'Re-encode with other levels/layers (lossless)'
            complete -c dicom-j2k -n __fish_use_subcommand -a roi        -d 'Extract region of interest'
            complete -c dicom-j2k -n __fish_use_subcommand -a benchmark  -d 'Decode-speed benchmark'
            complete -c dicom-j2k -n __fish_use_subcommand -a compare    -d 'Compute PSNR/MSE between images'
            complete -c dicom-j2k -n __fish_use_subcommand -a completions -d 'Generate shell completions'
            """
        }
    }
}

// MARK: - Entry point

if #available(macOS 10.15, *) {
    DICOMJ2K.main()
} else {
    fputs("dicom-j2k requires macOS 10.15 or later.\n", stderr)
    exit(1)
}
