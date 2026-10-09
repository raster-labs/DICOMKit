import XCTest
@testable import DICOMKit
import DICOMCore

/// Locks the exact `dicom-compress` console text produced by the shared
/// `CompressionConsole`. The CLI (`Sources/dicom-compress`) and the DICOMStudio
/// CLI Workshop both render through these functions, so pinning the strings here
/// guarantees the two surfaces stay byte-for-byte identical (no parity drift) and
/// that the strings keep matching the CLI-parity goldens.
final class CompressionConsoleTests: XCTestCase {

    func testByteFormatting() {
        XCTAssertEqual(CompressionConsole.formatBytes(0), "0 B")
        XCTAssertEqual(CompressionConsole.formatBytes(512), "512 B")
        XCTAssertEqual(CompressionConsole.formatBytes(1024), "1.0 KB")
        XCTAssertEqual(CompressionConsole.formatBytes(528_924), "516.5 KB")
        XCTAssertEqual(CompressionConsole.formatBytes(5 * 1024 * 1024), "5.0 MB")
    }

    func testQualityParsing() throws {
        XCTAssertNil(try CompressionConsole.parseQuality(nil))
        XCTAssertNil(try CompressionConsole.parseQuality("   "))
        XCTAssertEqual(try CompressionConsole.parseQuality("high"), .high)
        XCTAssertEqual(try CompressionConsole.parseQuality("MAXIMUM"), .maximum)
        if case .custom(let v)? = try CompressionConsole.parseQuality("0.8") {
            XCTAssertEqual(v, 0.8, accuracy: 1e-9)
        } else { XCTFail("expected .custom(0.8)") }
        XCTAssertThrowsError(try CompressionConsole.parseQuality("nope")) { err in
            XCTAssertEqual("\(err)", "Invalid --quality value 'nope'. Use maximum / high / medium / low, or a number in 0.0...1.0.")
        }
    }

    func testBackendPreference() {
        // CodecBackendPreference isn't Equatable; it wraps `forced: CodecBackend?`
        // (nil == auto). Assert the forced backend is reflected in its description.
        XCTAssertTrue(String(describing: CompressionConsole.backendPreference(for: "metal")).contains("metal"))
        XCTAssertTrue(String(describing: CompressionConsole.backendPreference(for: "ACCELERATE")).contains("accelerate"))
        XCTAssertTrue(String(describing: CompressionConsole.backendPreference(for: "scalar")).contains("scalar"))
        XCTAssertTrue(String(describing: CompressionConsole.backendPreference(for: "")).contains("nil"))
        XCTAssertTrue(String(describing: CompressionConsole.backendPreference(for: "weird")).contains("nil"))
    }

    func testElapsedFormatting() {
        XCTAssertEqual(CompressionConsole.formatElapsed(0.001),   "0.001s")
        XCTAssertEqual(CompressionConsole.formatElapsed(0.123),   "0.123s")
        XCTAssertEqual(CompressionConsole.formatElapsed(1.0),     "1.000s")
        XCTAssertEqual(CompressionConsole.formatElapsed(1.234),   "1.234s")
        XCTAssertEqual(CompressionConsole.formatElapsed(59.999),  "59.999s")
        XCTAssertEqual(CompressionConsole.formatElapsed(60.0),    "1m 0.000s")
        XCTAssertEqual(CompressionConsole.formatElapsed(83.456),  "1m 23.456s")
    }

    func testCompressLines() {
        XCTAssertEqual(
            CompressionConsole.compressResultLine(input: "/in.dcm", output: "/out.dcm"),
            "Compressed: /in.dcm → /out.dcm\n")
        // Normal compress preamble (source uncompressed)
        XCTAssertEqual(
            CompressionConsole.compressPreamble(input: "/in.dcm", codec: "htj2k-lossless",
                                                quality: nil, backendDisplayName: "Metal (GPU)"),
            "Compressing: /in.dcm\nCodec: htj2k-lossless\nBackend: Metal (GPU)\n")
        XCTAssertEqual(
            CompressionConsole.compressPreamble(input: "/in.dcm", codec: "htj2k",
                                                quality: " high ", backendDisplayName: "Scalar (CPU)"),
            "Compressing: /in.dcm\nCodec: htj2k\nQuality: high\nBackend: Scalar (CPU)\n")
        // Recompression preamble (source already compressed): header stays
        // "Compressing:" (no "Recompressing" wording), plus Source/Target codec lines.
        XCTAssertEqual(
            CompressionConsole.compressPreamble(input: "/in.dcm", codec: "jpeg-ls-lossless",
                                                quality: nil, backendDisplayName: "Metal (GPU)",
                                                sourceTransferSyntaxName: "JPEG 2000 Lossless"),
            "Compressing: /in.dcm\nSource codec: JPEG 2000 Lossless (compressed)\nTarget codec: jpeg-ls-lossless\nBackend: Metal (GPU)\n")
        // Recompress note (non-verbose always-shown line)
        XCTAssertEqual(
            CompressionConsole.recompressNoteLine(sourceName: "JPEG 2000 Lossless"),
            "Note: Source is already compressed (JPEG 2000 Lossless) — decompressing to native pixels first, then re-encoding\n")

        // Compression phase ratio/time lines (time's double space aligns its value
        // under the one-char-longer ratio label). Ratios are "N:1" — PS3.3 2026a
        // C.7.6.1.1.5.2 (D183); the decompression phase is "1:N".
        XCTAssertEqual(CompressionConsole.compressRatioLine(inputSize: 528_924, outputSize: 174_400),
                       "Compression ratio: 3.03:1\n")
        XCTAssertEqual(CompressionConsole.compressTimeLine(elapsed: 1.234), "Compression time:  1.234s\n")
        // No input bytes → no ratio line
        XCTAssertEqual(CompressionConsole.compressRatioLine(inputSize: 0, outputSize: 100), "")

        // Plain compress (uncompressed source): single compression ratio + time.
        XCTAssertEqual(
            CompressionConsole.compressSummary(inputSize: 528_924, intermediateSize: nil, outputSize: 174_400,
                                               decompressElapsed: nil, compressElapsed: 0.5),
            "Compression ratio: 3.03:1\nCompression time:  0.500s\n")
        XCTAssertEqual(
            CompressionConsole.compressStats(inputSize: 528_924, intermediateSize: nil, outputSize: 174_400,
                                             decompressElapsed: nil, compressElapsed: 0.5),
            "Input size:  516.5 KB\nOutput size: 170.3 KB\nCompression ratio: 3.03:1\nCompression time:  0.500s\n")

        // Recompression (already-compressed source → different codec): BOTH phases —
        // decompression (source→native) then compression (native→target).
        // input=170.3 KB compressed, native=516.5 KB, target=255.0 KB.
        XCTAssertEqual(
            CompressionConsole.compressSummary(inputSize: 174_400, intermediateSize: 528_924, outputSize: 261_120,
                                               decompressElapsed: 0.042, compressElapsed: 1.234),
            "Decompression ratio: 1:3.03\nDecompression time:  0.042s\nCompression ratio: 2.03:1\nCompression time:  1.234s\n")
        XCTAssertEqual(
            CompressionConsole.compressStats(inputSize: 174_400, intermediateSize: 528_924, outputSize: 261_120,
                                             decompressElapsed: 0.042, compressElapsed: 1.234),
            "Input size:        170.3 KB\nDecompressed size: 516.5 KB\nOutput size:       255.0 KB\nDecompression ratio: 1:3.03\nDecompression time:  0.042s\nCompression ratio: 2.03:1\nCompression time:  1.234s\n")
    }

    func testDecompressLines() {
        XCTAssertEqual(
            CompressionConsole.decompressResultLine(input: "/c.dcm", output: "/u.dcm"),
            "Decompressed: /c.dcm → /u.dcm\n")
        XCTAssertEqual(
            CompressionConsole.decompressPreamble(input: "/c.dcm", targetSyntaxName: "Explicit VR Little Endian"),
            "Decompressing: /c.dcm\nTarget syntax: Explicit VR Little Endian\n")
        // Expansion ratio + time (input=170.3 KB compressed → output=516.5 KB uncompressed).
        XCTAssertEqual(CompressionConsole.decompressRatioLine(inputSize: 174_400, outputSize: 528_924),
                       "Decompression ratio: 1:3.03\n")
        XCTAssertEqual(CompressionConsole.decompressTimeLine(elapsed: 0.042), "Decompression time:  0.042s\n")
        // Non-verbose summary (ratio + time)
        XCTAssertEqual(
            CompressionConsole.decompressSummary(inputSize: 174_400, outputSize: 528_924, elapsed: 0.042),
            "Decompression ratio: 1:3.03\nDecompression time:  0.042s\n")
        // Verbose stats now include the expansion ratio; ratio shows even without elapsed.
        XCTAssertEqual(
            CompressionConsole.decompressStats(inputSize: 174_400, outputSize: 528_924),
            "Input size:  170.3 KB\nOutput size: 516.5 KB\nDecompression ratio: 1:3.03\n")
        XCTAssertEqual(
            CompressionConsole.decompressStats(inputSize: 174_400, outputSize: 528_924, elapsed: 0.042),
            "Input size:  170.3 KB\nOutput size: 516.5 KB\nDecompression ratio: 1:3.03\nDecompression time:  0.042s\n")
    }

    func testCompressBackendReporting() {
        let metalAvailable = CodecBackendProbe.isAvailable(.metal)
        let cpuBackend = CodecBackendProbe.availableBackends.first { $0 != .metal } ?? .scalar
        let expectedJ2KBackend: CodecBackend = metalAvailable ? .metal : cpuBackend

        // Auto uses Metal for lossless J2K/HTJ2K when available and CPU otherwise.
        let autoLossless = CompressionConsole.compressBackend(codec: "jpeg2000-lossless", preference: .auto)
        XCTAssertEqual(autoLossless.displayName, expectedJ2KBackend.displayName)
        XCTAssertNil(autoLossless.note)

        let autoHTJ2KLossless = CompressionConsole.compressBackend(
            codec: "htj2k-lossless-only", preference: .auto)
        XCTAssertEqual(autoHTJ2KLossless.displayName, expectedJ2KBackend.displayName)
        XCTAssertNil(autoHTJ2KLossless.note)

        // Explicit Metal also supports lossless J2K, falling back only when unavailable.
        let metalLossless = CompressionConsole.compressBackend(codec: "jpeg2000-lossless", preference: .metal)
        XCTAssertEqual(metalLossless.displayName, expectedJ2KBackend.displayName)
        XCTAssertEqual(metalLossless.note == nil, metalAvailable)

        // A non-J2K codec always downgrades an explicit Metal request to CPU.
        let rleMetal = CompressionConsole.compressBackend(codec: "rle", preference: .metal)
        XCTAssertEqual(rleMetal.displayName, cpuBackend.displayName)
        XCTAssertNotNil(rleMetal.note)

        // Explicit scalar is honoured and carries no downgrade note.
        let scalar = CompressionConsole.compressBackend(codec: "jpeg2000-lossless", preference: .scalar)
        XCTAssertEqual(scalar.displayName, CodecBackend.scalar.displayName)
        XCTAssertNil(scalar.note)
    }

    func testBatchLines() {
        XCTAssertEqual(CompressionConsole.batchFoundLine(count: 3), "Found 3 DICOM file(s)\n")
        XCTAssertEqual(CompressionConsole.batchProgressLine(success: true, relativePath: "a/b.dcm", error: nil),
                       "  ✅ a/b.dcm\n")
        XCTAssertEqual(CompressionConsole.batchProgressLine(success: false, relativePath: "a/b.dcm", error: "boom"),
                       "  ❌ a/b.dcm: boom\n")
        XCTAssertEqual(CompressionConsole.batchSummaryLine(decompress: false, success: 2, fail: 1, total: 3),
                       "Compressed: 2 succeeded, 1 failed out of 3 files\n")
        XCTAssertEqual(CompressionConsole.batchSummaryLine(decompress: true, success: 3, fail: 0, total: 3),
                       "Decompressed: 3 succeeded, 0 failed out of 3 files\n")
    }
}
