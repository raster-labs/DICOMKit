// KakaduCLICodec.swift
// DICOMCore
//
// Decode-only JPEG 2000 codec that shells out to a locally-installed
// Kakadu `kdu_expand` binary. Used exclusively in the J2KSwift comparison
// panel — not registered in CodecRegistry.
//
// Requires the Kakadu SDK installed locally (commercial license).
// Probed paths: $PATH, /usr/local/bin/kdu_expand, /opt/homebrew/bin/kdu_expand.
// NEMA-verified: 2026a, checked 2026-09-25 — carries no DICOM-standard data (external Kakadu CLI wrapper). C1 classification confirmed.

#if os(macOS)
import Foundation

public struct KakaduCLICodec: Sendable {

    public static let binaryName = "kdu_expand"

    public static let binaryPath: String? = locateBinary(name: binaryName)

    public static var version: String { binaryPath.map { runVersion(at: $0) } ?? "unavailable" }

    public init() {}

    public func decodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor) throws -> Data {
        guard let bin = Self.binaryPath else {
            throw CLICodecError.binaryNotFound(Self.binaryName)
        }
        guard descriptor.samplesPerPixel == 1 else {
            throw CLICodecError.unsupportedConfiguration("samplesPerPixel=\(descriptor.samplesPerPixel) not yet supported")
        }

        let work = try TempWorkDir(prefix: "kakadu")
        defer { work.cleanup() }

        let inputURL = work.url.appendingPathComponent("in.j2c")
        let outputURL = work.url.appendingPathComponent("out.rawl")
        try frameData.write(to: inputURL)

        try runProcess(executable: bin, arguments: [
            "-i", inputURL.path,
            "-o", outputURL.path,
            "-quiet"
        ])

        let raw = try Data(contentsOf: outputURL)
        let expected = descriptor.rows * descriptor.columns * descriptor.samplesPerPixel * (descriptor.bitsAllocated <= 8 ? 1 : 2)
        guard raw.count == expected else {
            throw CLICodecError.outputSizeMismatch(expected: expected, got: raw.count)
        }
        return raw
    }

    private static func runVersion(at path: String) -> String {
        // `kdu_expand -v` writes version to stdout but exits non-zero on some builds.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = ["-v"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do { try proc.run() } catch { return "unknown" }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let line = String(data: data, encoding: .utf8)?
            .split(whereSeparator: \.isNewline)
            .first(where: { $0.localizedCaseInsensitiveContains("kakadu") || $0.localizedCaseInsensitiveContains("version") }) {
            return String(line).trimmingCharacters(in: .whitespaces)
        }
        return "installed"
    }
}
#endif
