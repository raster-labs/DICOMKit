// DjxlCLICodec.swift
// DICOMCore
//
// Decodes JXLSwift-produced JPEG XL via the libjxl `djxl` CLI, for head-to-head
// comparison in the DICOMStudio JPEG XL bench. Decode-only — JXLSwift is the
// reference encoder. djxl is selected by output extension: `.pgm` for
// grayscale, `.ppm` for RGB, both binary PNM. macOS-only, mirrors the
// Kakadu/Grok CLI peers.
// NEMA-verified: 2026a, checked 2026-09-25 — carries no DICOM-standard data (external libjxl CLI wrapper). C1 classification confirmed.

#if os(macOS)
import Foundation

public struct DjxlCLICodec: Sendable {

    public static let binaryName = "djxl"

    public static let binaryPath: String? = locateBinary(name: binaryName)

    public static var version: String {
        binaryPath.map { cliVersion(at: $0, flag: "--version", matching: "djxl") } ?? "unavailable"
    }

    public init() {}

    public func decodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor) throws -> Data {
        guard let bin = Self.binaryPath else {
            throw CLICodecError.binaryNotFound(Self.binaryName)
        }
        guard descriptor.samplesPerPixel == 1 || descriptor.samplesPerPixel == 3 else {
            throw CLICodecError.unsupportedConfiguration("samplesPerPixel=\(descriptor.samplesPerPixel)")
        }

        let work = try TempWorkDir(prefix: "djxl")
        defer { work.cleanup() }

        let inputURL = work.url.appendingPathComponent("in.jxl")
        // Force the PNM flavor by extension so the magic number is deterministic.
        let outName = descriptor.samplesPerPixel == 1 ? "out.pgm" : "out.ppm"
        let outputURL = work.url.appendingPathComponent(outName)
        try frameData.write(to: inputURL)

        try runProcess(executable: bin, arguments: [
            inputURL.path,
            outputURL.path
        ])

        let pnm = try Data(contentsOf: outputURL)
        let frame = try pnmToDICOMFrame(pnm, descriptor: descriptor)
        let expected = descriptor.bytesPerFrame
        guard frame.count == expected else {
            throw CLICodecError.outputSizeMismatch(expected: expected, got: frame.count)
        }
        return frame
    }
}
#endif
