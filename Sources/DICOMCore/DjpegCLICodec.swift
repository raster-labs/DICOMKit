// DjpegCLICodec.swift
// DICOMCore
//
// Decodes JLISwift-produced JPEG via the libjpeg-turbo `djpeg` CLI, for
// head-to-head comparison in the DICOMStudio JPEG bench. Decode-only —
// JLISwift is the reference encoder. libjpeg-turbo 3.x decodes lossless
// (SOF3) JPEG, so JLISwift's lossless output round-trips through djpeg.
// macOS-only, mirrors the Kakadu/Grok CLI peers.
// NEMA-verified: 2026a, checked 2026-09-25 — carries no DICOM-standard data (external libjpeg-turbo CLI wrapper). C1 classification confirmed.

#if os(macOS)
import Foundation

public struct DjpegCLICodec: Sendable {

    public static let binaryName = "djpeg"

    public static let binaryPath: String? = locateBinary(name: binaryName)

    public static var version: String {
        binaryPath.map { cliVersion(at: $0, flag: "-version", matching: "libjpeg") } ?? "unavailable"
    }

    public init() {}

    public func decodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor) throws -> Data {
        guard let bin = Self.binaryPath else {
            throw CLICodecError.binaryNotFound(Self.binaryName)
        }
        guard descriptor.samplesPerPixel == 1 || descriptor.samplesPerPixel == 3 else {
            throw CLICodecError.unsupportedConfiguration("samplesPerPixel=\(descriptor.samplesPerPixel)")
        }

        let work = try TempWorkDir(prefix: "djpeg")
        defer { work.cleanup() }

        let inputURL = work.url.appendingPathComponent("in.jpg")
        let outputURL = work.url.appendingPathComponent("out.pnm")
        try frameData.write(to: inputURL)

        // `-pnm` emits P5 (grayscale) or P6 (RGB) automatically; 16-bit data
        // yields a 16-bit PNM (maxval > 255).
        try runProcess(executable: bin, arguments: [
            "-pnm",
            "-outfile", outputURL.path,
            inputURL.path
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
