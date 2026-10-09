// CharLSCLICodec.swift
// DICOMStudio
//
// Decodes JLSwift-produced JPEG-LS via DCMTK's `dcmdjpls` CLI, the CharLS-backed
// peer for the DICOMStudio JPEG-LS bench. Decode-only — JLSwift is the reference
// encoder. Unlike the raw-codestream peers (djpeg/djxl/Kakadu/Grok), `dcmdjpls`
// operates on DICOM files, so this adapter wraps the JLS codestream into a
// minimal encapsulated DICOM, decompresses it, and reads the pixels back.
// macOS-only; mirrors the other CLI peers' `binaryPath` / `version` /
// `decodeFrame` surface so the bench can treat it identically.
//
// NEMA-verified: 2026a, checked 2026-10-05 — the throwaway wrapper file sets the PS3.3 C.7.6.3 Image Pixel attributes from the PixelDataDescriptor and encapsulates one fragment with an empty Basic Offset Table (PS3.5 2026a A.4) under JPEG-LS Lossless (A-1 .4.80); no standard data of its own

#if os(macOS)
import Foundation
import DICOMCore
import DICOMKit

public struct CharLSCLICodec: Sendable {

    public static let binaryName = "dcmdjpls"

    /// Located once on $PATH and the standard Homebrew/`/usr/local` locations.
    public static let binaryPath: String? = Self.locate(name: binaryName)

    /// First `--version` line (e.g. "$dcmtk: dcmdjpls v3.7.0 …$"), or "unavailable".
    public static var version: String {
        guard let bin = binaryPath else { return "unavailable" }
        return Self.firstVersionLine(at: bin) ?? "installed"
    }

    public init() {}

    /// Decodes a single-frame JPEG-LS codestream by round-tripping it through a
    /// throwaway encapsulated DICOM file and `dcmdjpls`, returning the raw frame
    /// in the DICOM pixel layout described by `descriptor`.
    public func decodeFrame(_ codestream: Data, descriptor: PixelDataDescriptor) throws -> Data {
        guard let bin = Self.binaryPath else {
            throw CharLSError.binaryNotFound(Self.binaryName)
        }

        let work = try TempDir(prefix: "dcmdjpls")
        defer { work.cleanup() }
        let inputURL = work.url.appendingPathComponent("in.dcm")
        let outputURL = work.url.appendingPathComponent("out.dcm")

        // Wrap the codestream in a minimal single-frame JPEG-LS DICOM file. The
        // declared syntax only tells dcmdjpls "this is JPEG-LS"; the actual
        // reconstruction (lossless vs near-lossless) is carried by the codestream,
        // so JPEG-LS Lossless (.80) works as the container for both .80 and .81.
        let file = Self.wrap(codestream: codestream, descriptor: descriptor)
        try file.write().write(to: inputURL)

        try Self.run(executable: bin, arguments: [inputURL.path, outputURL.path])

        let outData = try Data(contentsOf: outputURL)
        let outFile = try DICOMFile.read(from: outData)
        guard let pixels = outFile.dataSet[.pixelData]?.valueData else {
            throw CharLSError.noPixelData
        }

        let expected = descriptor.bytesPerFrame
        // dcmdjpls decodes every frame; the bench feeds one frame at a time, so the
        // first `bytesPerFrame` bytes are this frame (trailing byte drops any pad).
        guard pixels.count >= expected else {
            throw CharLSError.outputSizeMismatch(expected: expected, got: pixels.count)
        }
        return pixels.prefix(expected)
    }

    // MARK: - DICOM wrapping

    /// Builds a single-frame, encapsulated JPEG-LS Lossless DICOM file carrying
    /// `codestream` as the one pixel-data fragment. Secondary Capture SOP class —
    /// dcmdjpls decodes on the transfer syntax, not the SOP class.
    private static func wrap(codestream: Data, descriptor: PixelDataDescriptor) -> DICOMFile {
        var ds = DataSet()
        ds.setUInt16(UInt16(descriptor.rows), for: .rows)
        ds.setUInt16(UInt16(descriptor.columns), for: .columns)
        ds.setUInt16(UInt16(descriptor.bitsAllocated), for: .bitsAllocated)
        ds.setUInt16(UInt16(descriptor.bitsStored), for: .bitsStored)
        ds.setUInt16(UInt16(descriptor.highBit), for: .highBit)
        ds.setUInt16(descriptor.isSigned ? 1 : 0, for: .pixelRepresentation)
        ds.setUInt16(UInt16(descriptor.samplesPerPixel), for: .samplesPerPixel)
        ds.setString(descriptor.photometricInterpretation.rawValue,
                     for: .photometricInterpretation, vr: .CS)
        if descriptor.samplesPerPixel > 1 {
            ds.setUInt16(UInt16(descriptor.planarConfiguration), for: .planarConfiguration)
        }
        ds[.pixelData] = DataElement(
            tag: .pixelData, vr: .OB, length: 0xFFFFFFFF, valueData: Data(),
            encapsulatedFragments: [codestream], encapsulatedOffsetTable: [])

        return DICOMFile.create(dataSet: ds,
                                transferSyntaxUID: TransferSyntax.jpegLSLossless.uid)
    }

    // MARK: - Process helpers (self-contained; DICOMCore's are module-internal)

    enum CharLSError: Error, LocalizedError {
        case binaryNotFound(String)
        case nonZeroExit(Int32, String)
        case noPixelData
        case outputSizeMismatch(expected: Int, got: Int)

        var errorDescription: String? {
            switch self {
            case .binaryNotFound(let name):
                return "\(name): binary not found on PATH or standard install locations"
            case .nonZeroExit(let code, let stderr):
                return "dcmdjpls exited with status \(code)\(stderr.isEmpty ? "" : ": \(stderr.prefix(200))")"
            case .noPixelData:
                return "dcmdjpls output contained no pixel data"
            case .outputSizeMismatch(let expected, let got):
                return "dcmdjpls output size mismatch: expected \(expected) bytes, got \(got)"
            }
        }
    }

    private static func locate(name: String) -> String? {
        let candidates = ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return c }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                let full = "\(dir)/\(name)"
                if FileManager.default.isExecutableFile(atPath: full) { return full }
            }
        }
        return nil
    }

    private static func run(executable: String, arguments: [String]) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = Pipe()
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let err = errPipe.fileHandleForReading.readDataToEndOfFile()
            throw CharLSError.nonZeroExit(proc.terminationStatus,
                                          String(data: err, encoding: .utf8) ?? "")
        }
    }

    private static func firstVersionLine(at path: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = ["--version"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        guard (try? proc.run()) != nil else { return nil }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .split(whereSeparator: \.isNewline).first
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// A throwaway temp directory under NSTemporaryDirectory().
    private final class TempDir {
        let url: URL
        init(prefix: String) throws {
            let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            url = base.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        func cleanup() { try? FileManager.default.removeItem(at: url) }
    }
}
#endif
