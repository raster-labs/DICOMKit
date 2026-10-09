// NEMA-verified: 2026a, checked 2026-10-01 — transfer syntax names via DICOMCore; ratio lines in the N:1 form of PS3.3 2026a C.7.6.1.1.5.2 and the "Samples per Pixel" label of PS3.6 2026a Table 6-1 (0028,0002) (D183)
// NEMA-verified: 2026a, checked 2026-10-06 — NativeTargetSyntax (lifted from dicom-compress, D267): the 4 targets are the PS3.6 2026a Table A-1 rows 1.2.840.10008.1.2.1 Explicit VR Little Endian, 1.2.840.10008.1.2 Implicit VR Little Endian, 1.2.840.10008.1.2.1.99 Deflated Explicit VR Little Endian, 1.2.840.10008.1.2.2 Explicit VR Big Endian (Retired) (dumped by script), i.e. the native encodings of PS3.5 2026a A.1, A.2, A.5 and the retired A.3; every other Table A-1 Transfer Syntax the engine names is encapsulated and refused
// CompressionConsole.swift
// DICOMKit
//
// Shared console-output + input-parsing helpers for `dicom-compress`.
//
// WHY: the standalone `dicom-compress` CLI and DICOMStudio's CLI Workshop both
// drive the SAME `CompressionManager` engine, but each used to format its own
// console text (byte sizes, the "Compressed:" line, the verbose preamble/stats)
// and parse `--quality` with its own copy of the logic. Duplicated formatting
// drifts: a tweak in one surface silently diverges the other, and the Workshop's
// terminal-compare then reports a mismatch even though the bytes are identical.
//
// This type is the single source of truth for that text and for `--quality`
// parsing, so the CLI and the app render byte-for-byte identical output. It is
// pure (no I/O) and `Sendable`, so it is safe to call from the app's detached
// formatting tasks and the CLI alike.
//
// Reference: mirrors the shared-formatter pattern used by NetworkConsole and
// DICOMConverter (CLI ↔ app parity).

import Foundation
import DICOMCore

/// Pure formatters and parsers shared by the `dicom-compress` CLI and the
/// DICOMStudio CLI Workshop so their console output never drifts.
public enum CompressionConsole {

    // MARK: - Input parsing (shared)

    /// Parses the `--quality` option: `maximum` / `high` / `medium` / `low`, or a
    /// floating-point value in `0.0...1.0`. Returns `nil` when no value is given
    /// (codec default). Throws `CompressionError.invalidQuality` on a bad value —
    /// the CLI and app surface the identical message.
    public static func parseQuality(_ string: String?) throws -> CompressionQuality? {
        guard let qs = string?.trimmingCharacters(in: .whitespaces), !qs.isEmpty else { return nil }
        switch qs.lowercased() {
        case "maximum": return .maximum
        case "high":    return .high
        case "medium":  return .medium
        case "low":     return .low
        default:
            if let v = Double(qs), v >= 0.0, v <= 1.0 { return .custom(v) }
            throw CompressionError.invalidQuality(qs)
        }
    }

    /// Maps a `--backend` raw value to a `CodecBackendPreference` (defaults to
    /// `.auto` for unknown/empty input), matching the CLI's accepted spellings.
    public static func backendPreference(for raw: String) -> CodecBackendPreference {
        switch raw.lowercased() {
        case "metal":      return .metal
        case "accelerate": return .accelerate
        case "scalar":     return .scalar
        default:           return .auto
        }
    }

    // MARK: - Byte formatting (shared)

    /// Formats a byte count using binary (1024) units: `B`, `KB`, `MB`, `GB`.
    public static func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024.0) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0)) }
        return String(format: "%.1f GB", Double(bytes) / (1024.0 * 1024.0 * 1024.0))
    }

    // MARK: - Elapsed time formatting (shared)

    /// Formats an elapsed time interval as a human-readable string (e.g. `0.123s`, `1.234s`, `1m 23.456s`).
    public static func formatElapsed(_ elapsed: TimeInterval) -> String {
        if elapsed < 60 {
            return String(format: "%.3fs", elapsed)
        }
        let minutes = Int(elapsed) / 60
        let seconds = elapsed.truncatingRemainder(dividingBy: 60)
        return String(format: "%dm %.3fs", minutes, seconds)
    }

    // MARK: - Phase ratio/time lines (shared)

    /// Shared "<Phase> ratio: …" builder, written as a ratio in the form PS3.3 2026a
    /// C.7.6.1.1.5.2 uses for Lossy Image Compression Ratio (0028,2112): "the numerator of an
    /// implicit ratio in which the denominator is always one", e.g. "30:1" (D183; was the output
    /// size as a percentage of the input). A compression phase prints uncompressed : compressed
    /// = input / output ":1"; a decompression phase prints "1:" output / input (the input is the
    /// compressed side). Sizes are whole-file byte counts. Returns "" when either size is 0.
    private static func ratioLine(phase: String, inputSize: Int, outputSize: Int) -> String {
        guard inputSize > 0, outputSize > 0 else { return "" }
        if phase == "Decompression" {
            let ratio = Double(outputSize) / Double(inputSize)
            return "\(phase) ratio: 1:\(String(format: "%.2f", ratio))\n"
        }
        let ratio = Double(inputSize) / Double(outputSize)
        return "\(phase) ratio: \(String(format: "%.2f", ratio)):1\n"
    }

    /// Shared "<Phase> time:  <elapsed>" builder. The trailing double space aligns the
    /// value under the ratio line above it (the "… time:" label is exactly one
    /// character shorter than "… ratio:").
    private static func timeLine(phase: String, elapsed: TimeInterval) -> String {
        "\(phase) time:  \(formatElapsed(elapsed))\n"
    }

    // MARK: - Compress output (shared)

    /// Verbose preamble printed before a compress run (only when `--verbose`).
    /// When `sourceTransferSyntaxName` is provided the source is already compressed, so
    /// the source codec and a "Target codec" label are shown (the run first decompresses
    /// to native pixels, then compresses). `quality` is the raw user string (echoed
    /// as-is); omitted when empty/nil.
    public static func compressPreamble(input: String, codec: String,
                                        quality: String?, backendDisplayName: String,
                                        sourceTransferSyntaxName: String? = nil,
                                        backendNote: String? = nil) -> String {
        var out = "Compressing: \(input)\n"
        if let sourceName = sourceTransferSyntaxName {
            out += "Source codec: \(sourceName) (compressed)\n"
        }
        out += "\(sourceTransferSyntaxName != nil ? "Target codec" : "Codec"): \(codec)\n"
        if let q = quality?.trimmingCharacters(in: .whitespaces), !q.isEmpty {
            out += "Quality: \(q)\n"
        }
        out += "Backend: \(backendDisplayName)\n"
        if let note = backendNote, !note.isEmpty {
            out += "\(note)\n"
        }
        return out
    }

    /// Resolves the backend the compress engine will **actually** use for `codec`
    /// under `preference`, plus a note when an explicit `--backend metal` request
    /// is downgraded to the CPU.
    ///
    /// GPU (Metal) encode supports lossy and lossless JPEG 2000 / HTJ2K. When
    /// Metal is available, `auto` dispatches those codecs to the GPU; every
    /// non-J2K codec and explicit `accelerate` / `scalar` request runs on the CPU.
    /// An explicit `--backend metal` request is downgraded only when the codec is
    /// not in the JPEG 2000 family or Metal is unavailable. This mirrors
    /// `J2KSwiftCodec.encodeFrame`'s routing policy (via
    /// `CodecBackendPreference.effectiveEncodeBackend`) so the reported "Backend:"
    /// line never disagrees with the path taken.
    public static func compressBackend(
        codec: String, preference: CodecBackendPreference
    ) -> (displayName: String, note: String?) {
        let syntax = CompressionManager.transferSyntax(for: codec)
        let intent = CompressionManager.resolveEncoding(for: codec)?.intent ?? .notApplicable
        let isLossless: Bool = {
            guard let syntax else { return false }
            switch syntax.losslessCapability {
            case .both:         return intent == .lossless
            case .losslessOnly: return true
            case .lossyOnly:    return false
            }
        }()
        let isJPEG2000Family = syntax?.isJPEG2000 ?? false
        let effective = preference.effectiveEncodeBackend(
            isLossless: isLossless, isJPEG2000Family: isJPEG2000Family)
        // Since Phase 2, GPU (Metal) encode covers lossy AND lossless JPEG 2000 /
        // HTJ2K. A forced-Metal request is therefore only downgraded when the codec
        // is not JPEG 2000 / HTJ2K, or Metal is unavailable on this platform.
        let note: String? = {
            guard preference.forced == .metal, effective != .metal else { return nil }
            let reason = !isJPEG2000Family
                ? "GPU (Metal) encode is only available for JPEG 2000 / HTJ2K codecs"
                : "Metal is unavailable on this platform"
            return "Note: \(reason); using \(effective.displayName) for this encode."
        }()
        return (effective.displayName, note)
    }

    /// Informational line printed (always, not just verbose) when the source file is
    /// already compressed and will be decoded to native pixels before re-encoding.
    public static func recompressNoteLine(sourceName: String) -> String {
        "Note: Source is already compressed (\(sourceName)) — decompressing to native pixels first, then re-encoding\n"
    }

    /// The single result line every compress run prints.
    public static func compressResultLine(input: String, output: String) -> String {
        "Compressed: \(input) → \(output)\n"
    }

    /// Ratio line for the compression phase: input size / output size as "N:1" (PS3.3 2026a
    /// C.7.6.1.1.5.2 notation). Returns "" when a size is 0.
    public static func compressRatioLine(inputSize: Int, outputSize: Int) -> String {
        ratioLine(phase: "Compression", inputSize: inputSize, outputSize: outputSize)
    }

    /// Elapsed-time line for the compression phase.
    public static func compressTimeLine(elapsed: TimeInterval) -> String {
        timeLine(phase: "Compression", elapsed: elapsed)
    }

    /// Non-verbose summary printed after a compress run. When the source was already
    /// compressed the engine decompresses it to native pixels and then re-encodes, so
    /// BOTH phases are reported — the decompression (source → native) and the
    /// compression (native → target), each with its own ratio + time. For a plain
    /// compress (uncompressed source) only the single compression ratio + time show.
    /// A recompression is signalled by a non-nil `intermediateSize` + `decompressElapsed`.
    public static func compressSummary(inputSize: Int, intermediateSize: Int?, outputSize: Int,
                                       decompressElapsed: TimeInterval?, compressElapsed: TimeInterval) -> String {
        if let inter = intermediateSize, let dt = decompressElapsed {
            return decompressRatioLine(inputSize: inputSize, outputSize: inter)
                 + decompressTimeLine(elapsed: dt)
                 + compressRatioLine(inputSize: inter, outputSize: outputSize)
                 + compressTimeLine(elapsed: compressElapsed)
        }
        return compressRatioLine(inputSize: inputSize, outputSize: outputSize)
             + compressTimeLine(elapsed: compressElapsed)
    }

    /// Verbose size/ratio/time block printed after a compress run (only when
    /// `--verbose`). Mirrors `compressSummary`'s phase handling and prepends the byte
    /// sizes (including the intermediate decompressed size for a recompression).
    public static func compressStats(inputSize: Int, intermediateSize: Int?, outputSize: Int,
                                     decompressElapsed: TimeInterval?, compressElapsed: TimeInterval) -> String {
        if let inter = intermediateSize, let dt = decompressElapsed {
            var out = "Input size:        \(formatBytes(inputSize))\n"
            out += "Decompressed size: \(formatBytes(inter))\n"
            out += "Output size:       \(formatBytes(outputSize))\n"
            out += decompressRatioLine(inputSize: inputSize, outputSize: inter)
            out += decompressTimeLine(elapsed: dt)
            out += compressRatioLine(inputSize: inter, outputSize: outputSize)
            out += compressTimeLine(elapsed: compressElapsed)
            return out
        }
        var out = "Input size:  \(formatBytes(inputSize))\n"
        out += "Output size: \(formatBytes(outputSize))\n"
        out += compressRatioLine(inputSize: inputSize, outputSize: outputSize)
        out += compressTimeLine(elapsed: compressElapsed)
        return out
    }

    // MARK: - Decompress output (shared)

    /// Verbose preamble printed before a decompress run (only when `--verbose`).
    public static func decompressPreamble(input: String, targetSyntaxName: String) -> String {
        "Decompressing: \(input)\nTarget syntax: \(targetSyntaxName)\n"
    }

    /// The single result line every decompress run prints.
    public static func decompressResultLine(input: String, output: String) -> String {
        "Decompressed: \(input) → \(output)\n"
    }

    /// Ratio line for a decompress run: compressed input : uncompressed output as "1:N"
    /// (PS3.3 2026a C.7.6.1.1.5.2 notation, compressed side first). Returns "" when a size is 0.
    public static func decompressRatioLine(inputSize: Int, outputSize: Int) -> String {
        ratioLine(phase: "Decompression", inputSize: inputSize, outputSize: outputSize)
    }

    /// Elapsed-time line printed after a decompress run.
    public static func decompressTimeLine(elapsed: TimeInterval) -> String {
        timeLine(phase: "Decompression", elapsed: elapsed)
    }

    /// Non-verbose summary printed after a decompress run: expansion ratio + time.
    public static func decompressSummary(inputSize: Int, outputSize: Int, elapsed: TimeInterval) -> String {
        decompressRatioLine(inputSize: inputSize, outputSize: outputSize)
            + decompressTimeLine(elapsed: elapsed)
    }

    /// Verbose size/ratio/time block printed after a decompress run (only when `--verbose`).
    public static func decompressStats(inputSize: Int, outputSize: Int, elapsed: TimeInterval? = nil) -> String {
        var out = "Input size:  \(formatBytes(inputSize))\n"
        out += "Output size: \(formatBytes(outputSize))\n"
        out += decompressRatioLine(inputSize: inputSize, outputSize: outputSize)
        if let t = elapsed {
            out += decompressTimeLine(elapsed: t)
        }
        return out
    }

    // MARK: - Batch output (shared)

    /// The "Found N DICOM file(s)" line printed at the start of a batch run.
    public static func batchFoundLine(count: Int) -> String {
        "Found \(count) DICOM file(s)\n"
    }

    /// A per-file progress line (only when `--verbose`). `error` is the rendered
    /// error string for a failure (nil for success).
    public static func batchProgressLine(success: Bool, relativePath: String, error: String?) -> String {
        if success { return "  ✅ \(relativePath)\n" }
        return "  ❌ \(relativePath): \(error ?? "")\n"
    }

    /// The summary line printed at the end of a batch run.
    public static func batchSummaryLine(decompress: Bool, success: Int, fail: Int, total: Int) -> String {
        let action = decompress ? "Decompressed" : "Compressed"
        return "\(action): \(success) succeeded, \(fail) failed out of \(total) files\n"
    }

    // MARK: - Info subcommand (shared)

    /// The codec label the `info` text output prints (HTJ2K distinguished by UID prefix).
    private static func infoCodecLabel(_ info: CompressionInfo) -> String {
        if info.isJPEG { return "JPEG" }
        if info.isJPEG2000 {
            return info.transferSyntaxUID.hasPrefix("1.2.840.10008.1.2.4.20")
                ? "HTJ2K (High-Throughput JPEG 2000)" : "JPEG 2000"
        }
        if info.isJPEGLS { return "JPEG-LS" }
        if info.isJPEGXL { return "JPEG XL" }
        if info.isRLE { return "RLE" }
        if info.isDeflated { return "Deflate" }
        return "None (uncompressed)"
    }

    /// The full `dicom-compress info` text block (every line newline-terminated).
    public static func infoText(_ info: CompressionInfo, filePath: String) -> String {
        var lines: [String] = []
        lines.append("File: \(filePath)")
        lines.append("Transfer Syntax: \(info.transferSyntaxName)")
        lines.append("Transfer Syntax UID: \(info.transferSyntaxUID)")
        lines.append("Compressed: \(info.isCompressed ? "Yes" : "No")")
        lines.append("Lossless: \(info.isLossless ? "Yes" : "No")")
        lines.append("Codec: \(infoCodecLabel(info))")
        if let size = info.pixelDataSize {
            lines.append("Pixel Data Size: \(formatBytes(size))")
        } else {
            lines.append("Pixel Data Size: N/A (no pixel data)")
        }
        if let rows = info.rows, let cols = info.columns {
            lines.append("Image Dimensions: \(cols) x \(rows)")
        }
        if let ba = info.bitsAllocated { lines.append("Bits Allocated: \(ba)") }
        if let bs = info.bitsStored { lines.append("Bits Stored: \(bs)") }
        if let spp = info.samplesPerPixel { lines.append("Samples per Pixel: \(spp)") }
        if let pi = info.photometricInterpretation { lines.append("Photometric Interpretation: \(pi)") }
        if let nf = info.numberOfFrames { lines.append("Number of Frames: \(nf)") }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The full `dicom-compress info --json` document (pretty-printed, sorted keys,
    /// trailing newline). The JSON codec label intentionally has no HTJ2K variant.
    public static func infoJSON(_ info: CompressionInfo, filePath: String) throws -> String {
        var dict: [String: Any] = [
            "file": filePath,
            "transferSyntax": info.transferSyntaxName,
            "transferSyntaxUID": info.transferSyntaxUID,
            "compressed": info.isCompressed,
            "lossless": info.isLossless,
        ]
        if info.isJPEG { dict["codec"] = "JPEG" }
        else if info.isJPEG2000 { dict["codec"] = "JPEG 2000" }
        else if info.isJPEGLS { dict["codec"] = "JPEG-LS" }
        else if info.isJPEGXL { dict["codec"] = "JPEG XL" }
        else if info.isRLE { dict["codec"] = "RLE" }
        else if info.isDeflated { dict["codec"] = "Deflate" }
        else { dict["codec"] = "None" }
        if let v = info.pixelDataSize { dict["pixelDataSize"] = v }
        if let v = info.rows { dict["rows"] = Int(v) }
        if let v = info.columns { dict["columns"] = Int(v) }
        if let v = info.bitsAllocated { dict["bitsAllocated"] = Int(v) }
        if let v = info.bitsStored { dict["bitsStored"] = Int(v) }
        if let v = info.samplesPerPixel { dict["samplesPerPixel"] = Int(v) }
        if let v = info.photometricInterpretation { dict["photometricInterpretation"] = v }
        if let v = info.numberOfFrames { dict["numberOfFrames"] = v }
        // PS3.6 2026a Table 6-1 keyword keys (P-COMPRESS-JSON), next to the camelCase keys
        // above, which are deprecated but keep their old values. Numbers stay numbers; Number
        // of Frames (IS) is a JSON number when it parses (PS3.18 F.2.3, Table F.2.3-1), else its string.
        for (keyword, value) in infoKeywordFields(info) { dict[keyword] = value }
        let jsonData = try JSONSerialization.data(
            withJSONObject: dict,
            options: [.prettyPrinted, .sortedKeys]
        )
        return (String(data: jsonData, encoding: .utf8) ?? "") + "\n"
    }

    /// The PS3.6 2026a Table 6-1 keyword → value pairs of `info --json` (only the present
    /// ones): TransferSyntaxUID (0002,0010), Rows (0028,0010), Columns (0028,0011),
    /// BitsAllocated (0028,0100), BitsStored (0028,0101), SamplesPerPixel (0028,0002),
    /// PhotometricInterpretation (0028,0004), NumberOfFrames (0028,0008),
    /// LossyImageCompression (0028,2110).
    public static func infoKeywordFields(_ info: CompressionInfo) -> [String: Any] {
        var fields: [String: Any] = ["TransferSyntaxUID": info.transferSyntaxUID]
        if let v = info.rows { fields["Rows"] = Int(v) }
        if let v = info.columns { fields["Columns"] = Int(v) }
        if let v = info.bitsAllocated { fields["BitsAllocated"] = Int(v) }
        if let v = info.bitsStored { fields["BitsStored"] = Int(v) }
        if let v = info.samplesPerPixel { fields["SamplesPerPixel"] = Int(v) }
        if let v = info.photometricInterpretation { fields["PhotometricInterpretation"] = v }
        if let v = info.numberOfFrames { fields["NumberOfFrames"] = Int(v) ?? v as Any }
        if let v = info.lossyImageCompression, !v.isEmpty { fields["LossyImageCompression"] = v }
        return fields
    }

    /// The `info` read-failure line. The CLI prints the raw error value, not
    /// `localizedDescription` — keep that exact rendering on both surfaces.
    public static func infoErrorLine(_ error: Error) -> String {
        "Error reading file: \(error)\n"
    }

    // MARK: - Backends subcommand (shared)

    /// The full `dicom-compress backends` text block (trailing newline).
    public static func backendsText() -> String {
        let best = CodecBackendProbe.bestAvailable
        var lines: [String] = []
        lines.append("Available hardware acceleration backends:")
        lines.append("")
        for backend in CodecBackend.allCases {
            let isAvail = CodecBackendProbe.isAvailable(backend)
            let marker = isAvail ? (backend == best ? "✓ (active)" : "✓") : "✗"
            lines.append("  [\(marker)] \(backend.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0))\(backend.displayName)")
        }
        lines.append("")
        lines.append("Active backend: \(best.displayName)")
        lines.append("Use --backend <name> on the compress command to select a specific backend.")
        return lines.joined(separator: "\n") + "\n"
    }

    /// The full `dicom-compress backends --json` document (trailing newline).
    public static func backendsJSON() throws -> String {
        let best = CodecBackendProbe.bestAvailable
        var items: [[String: Any]] = []
        for backend in CodecBackend.allCases {
            items.append([
                "backend": backend.rawValue,
                "available": CodecBackendProbe.isAvailable(backend),
                "active": backend == best,
                "displayName": backend.displayName
            ])
        }
        let data = try JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted])
        return (String(data: data, encoding: .utf8) ?? "") + "\n"
    }

    // MARK: - Decompress / batch --syntax targets (shared; D267)

    /// The `--syntax` values of `dicom-compress decompress` and `batch --decompress`: only the
    /// native (non-encapsulated) Transfer Syntaxes, because decompression writes native Pixel
    /// Data — PS3.5 2026a A.1 Implicit VR Little Endian, A.2 Explicit VR Little Endian, A.5
    /// Deflated Explicit VR Little Endian, and the retired A.3 Explicit VR Big Endian (UIDs per
    /// PS3.6 2026a Table A-1). Every encapsulated codec name is refused with the text below
    /// (P-COMPRESS-SYNTAX); the CLI and the DICOMStudio Workshop share it.
    public enum NativeTargetSyntax {
        public static let accepted: [(name: String, syntax: TransferSyntax)] = [
            ("explicit-le", .explicitVRLittleEndian),
            ("implicit-le", .implicitVRLittleEndian),
            ("deflate", .deflatedExplicitVRLittleEndian),
            ("explicit-be", .explicitVRBigEndian),
        ]

        /// A refused `--syntax` value. Not an ArgumentParser `ValidationError`, so the command
        /// exits 1 (not 64).
        public struct Refused: LocalizedError, CustomStringConvertible {
            public let description: String
            public var errorDescription: String? { description }
            public init(description: String) { self.description = description }
        }

        /// The Transfer Syntax a `--syntax` value names (case-insensitive), or a ``Refused``
        /// error: one text for an encapsulated codec name, another for an unknown value.
        public static func resolve(_ name: String) throws -> TransferSyntax {
            let lower = name.trimmingCharacters(in: .whitespaces).lowercased()
            if let hit = accepted.first(where: { $0.name == lower }) { return hit.syntax }
            let allowed = accepted.map(\.name).joined(separator: ", ")
            if let codec = CompressionManager.transferSyntax(for: lower) {
                throw Refused(description: "--syntax \(name) names \(codec.uid), an encapsulated (compressed) "
                    + "Transfer Syntax (PS3.6 2026a Table A-1); decompression writes native Pixel Data "
                    + "(PS3.5 2026a A.1, A.2, A.5). Native targets: \(allowed). To compress, use `compress --codec`.")
            }
            throw Refused(description: "Unknown syntax '\(name)'. Native targets: \(allowed)")
        }
    }
}
