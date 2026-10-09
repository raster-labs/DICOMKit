// CLICodecSupport.swift
// DICOMCore
//
// Shared helpers for codec adapters that shell out to locally-installed
// CLI binaries (Kakadu, Grok). macOS-only.
// NEMA-verified: 2026a, checked 2026-09-25 — carries no DICOM-standard data beyond the Planar Configuration 0/1 sample order, which matches PS3.3 2026a C.7.6.3.1.3 (0 = colour-by-pixel, 1 = colour-by-plane). C1 classification confirmed.

#if os(macOS)
import Foundation

enum CLICodecError: Error, LocalizedError {
    case binaryNotFound(String)
    case launchFailed(String)
    case nonZeroExit(Int32, String)
    case outputSizeMismatch(expected: Int, got: Int)
    case unsupportedConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let name):
            return "\(name): binary not found on PATH or standard install locations"
        case .launchFailed(let msg):
            return "Failed to launch codec binary: \(msg)"
        case .nonZeroExit(let code, let stderr):
            return "Codec exited with status \(code)\(stderr.isEmpty ? "" : ": \(stderr.prefix(200))")"
        case .outputSizeMismatch(let expected, let got):
            return "Codec output size mismatch: expected \(expected) bytes, got \(got)"
        case .unsupportedConfiguration(let reason):
            return "Codec configuration not supported: \(reason)"
        }
    }
}

/// Searches a name on $PATH and a small list of common install locations.
func locateBinary(name: String) -> String? {
    let candidates: [String] = [
        "/usr/local/bin/\(name)",
        "/opt/homebrew/bin/\(name)",
        "/usr/bin/\(name)"
    ]
    for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
        return c
    }
    // PATH fallback.
    if let path = ProcessInfo.processInfo.environment["PATH"] {
        for dir in path.split(separator: ":") {
            let full = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: full) { return full }
        }
    }
    return nil
}

/// Launches `executable` with the given arguments and waits for exit.
/// Throws on launch failure or non-zero exit; stdout/stderr are captured and surfaced on failure.
func runProcess(executable: String, arguments: [String]) throws {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: executable)
    proc.arguments = arguments
    let stderrPipe = Pipe()
    let stdoutPipe = Pipe()
    proc.standardError = stderrPipe
    proc.standardOutput = stdoutPipe
    do {
        try proc.run()
    } catch {
        throw CLICodecError.launchFailed(error.localizedDescription)
    }
    proc.waitUntilExit()
    if proc.terminationStatus != 0 {
        let err = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let out = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let msg = String(data: err.isEmpty ? out : err, encoding: .utf8) ?? "<no output>"
        throw CLICodecError.nonZeroExit(proc.terminationStatus, msg)
    }
}

/// A throwaway temp directory under NSTemporaryDirectory().
final class TempWorkDir {
    let url: URL

    init(prefix: String) throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = base.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Runs `<binary> <flag>` and returns the first output line containing `match`
/// (case-insensitive), trimmed — used to surface a CLI codec's version string.
func cliVersion(at path: String, flag: String, matching match: String) -> String {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: path)
    proc.arguments = [flag]
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = pipe
    do { try proc.run() } catch { return "unknown" }
    proc.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    if let line = String(data: data, encoding: .utf8)?
        .split(whereSeparator: \.isNewline)
        .first(where: { $0.localizedCaseInsensitiveContains(match) || $0.localizedCaseInsensitiveContains("version") }) {
        return String(line).trimmingCharacters(in: .whitespaces)
    }
    return "installed"
}

/// Parses a binary PNM blob (`P5` PGM / `P6` PPM) emitted by a decoder CLI
/// (djpeg, djxl) and repacks it into the DICOM frame layout described by
/// `descriptor`: little-endian samples, channel order per Planar Configuration.
///
/// PNM stores samples **big-endian** and channel-**interleaved**; a maxval > 255
/// means 16-bit samples. DICOM stores 16-bit samples little-endian, and may be
/// planar (Planar Configuration 1) for multi-component frames.
func pnmToDICOMFrame(_ pnm: Data, descriptor: PixelDataDescriptor) throws -> Data {
    let bytes = [UInt8](pnm)
    func fail(_ m: String) -> CLICodecError { .unsupportedConfiguration("PNM parse: \(m)") }

    guard bytes.count >= 2, bytes[0] == 0x50 /* 'P' */ else { throw fail("not a PNM stream") }
    let channels: Int
    switch bytes[1] {
    case 0x35: channels = 1   // 'P5' → PGM (grayscale)
    case 0x36: channels = 3   // 'P6' → PPM (RGB)
    default:   throw fail("unsupported magic")
    }
    var i = 2

    // Header integer reader — skips whitespace and `#` comment lines.
    func nextInt() throws -> Int {
        while i < bytes.count {
            let c = bytes[i]
            if c == 0x23 {                                  // '#' comment to EOL
                while i < bytes.count && bytes[i] != 0x0A { i += 1 }
            } else if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D {
                i += 1
            } else { break }
        }
        var value = 0, digits = 0
        while i < bytes.count, bytes[i] >= 0x30, bytes[i] <= 0x39 {
            value = value * 10 + Int(bytes[i] - 0x30); i += 1; digits += 1
        }
        guard digits > 0 else { throw fail("expected integer in header") }
        return value
    }

    let width = try nextInt()
    let height = try nextInt()
    let maxval = try nextInt()
    guard i < bytes.count else { throw fail("missing pixel data") }
    i += 1   // single whitespace byte separates the header from binary data

    guard width == descriptor.columns, height == descriptor.rows else {
        throw fail("dimensions \(width)x\(height) != \(descriptor.columns)x\(descriptor.rows)")
    }
    guard channels == descriptor.samplesPerPixel else {
        throw fail("channels \(channels) != samplesPerPixel \(descriptor.samplesPerPixel)")
    }

    let srcBytesPerSample = maxval > 255 ? 2 : 1
    let nSamples = width * height * channels
    guard bytes.count - i >= nSamples * srcBytesPerSample else {
        throw fail("short pixel data: have \(bytes.count - i), need \(nSamples * srcBytesPerSample)")
    }

    let dstBytesPerSample = descriptor.bitsAllocated <= 8 ? 1 : 2
    let planar = descriptor.planarConfiguration == 1 && channels > 1
    var out = Data(count: nSamples * dstBytesPerSample)

    out.withUnsafeMutableBytes { raw in
        guard let base = raw.baseAddress else { return }
        let dst = base.assumingMemoryBound(to: UInt8.self)
        var s = i
        for idx in 0..<nSamples {
            let sample: Int
            if srcBytesPerSample == 1 {
                sample = Int(bytes[s]); s += 1
            } else {
                sample = (Int(bytes[s]) << 8) | Int(bytes[s + 1]); s += 2   // big-endian
            }
            let dstSampleIndex: Int
            if planar {
                dstSampleIndex = (idx % channels) * width * height + (idx / channels)
            } else {
                dstSampleIndex = idx
            }
            let dstByte = dstSampleIndex * dstBytesPerSample
            if dstBytesPerSample == 1 {
                dst[dstByte] = UInt8(truncatingIfNeeded: sample)
            } else {
                dst[dstByte] = UInt8(sample & 0xFF)
                dst[dstByte + 1] = UInt8((sample >> 8) & 0xFF)
            }
        }
    }
    return out
}
#endif
