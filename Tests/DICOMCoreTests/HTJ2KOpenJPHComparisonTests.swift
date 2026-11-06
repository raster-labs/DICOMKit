import Foundation
import Testing
@testable import DICOMCore
@testable import DICOMKit
#if canImport(SwiftJ2K)
import SwiftJ2K
#endif

/// Compares DICOMKit's HTJ2K path (J2KSwift `.conformant` Part-15) against
/// the reference OpenJPH implementation (`ojph_expand`). Skipped when
/// OpenJPH CLI tools are not installed.
///
/// Measures:
/// - J2KSwift decode time (median of N runs)
/// - OpenJPH `ojph_expand` decode time (median of N runs)
/// - Bit-exact pixel equality between the two decoders for the same codestream
@Suite("HTJ2K vs OpenJPH Comparison", .serialized)
struct HTJ2KOpenJPHComparisonTests {

    // MARK: - Fixtures

    private func localDatasetsRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("LocalDatasets/medical-dicom-organized", isDirectory: true)
    }

    private func firstDICOMFile(in relativeDirectory: String) -> URL? {
        let directory = localDatasetsRoot().appendingPathComponent(relativeDirectory, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }
        for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "dcm" {
            return fileURL
        }
        return nil
    }

    private func realSample(modality: String) throws -> (url: URL, file: DICOMFile, pixelData: PixelData) {
        guard let fileURL = firstDICOMFile(in: modality) else {
            throw DICOMError.parsingFailed("No .dcm file under LocalDatasets/medical-dicom-organized/\(modality)")
        }
        let file = try DICOMFile.read(from: fileURL)
        let pixelData = try file.tryPixelData()
        return (fileURL, file, pixelData)
    }

    // MARK: - OpenJPH driver

    private func openjphExpandPath() -> String? {
        for candidate in ["/opt/homebrew/bin/ojph_expand", "/usr/local/bin/ojph_expand"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// Runs `ojph_expand -i <input> -o <output.pgm>` once and returns elapsed ms.
    /// Throws if the tool exits non-zero.
    private func runOJPHExpand(_ ojph: String, input: URL, output: URL) throws -> Double {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ojph)
        process.arguments = ["-i", input.path, "-o", output.path]
        let devNull = FileHandle(forWritingAtPath: "/dev/null")
        process.standardOutput = devNull
        process.standardError = devNull
        let start = CFAbsoluteTimeGetCurrent()
        try process.run()
        process.waitUntilExit()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        try devNull?.close()
        guard process.terminationStatus == 0 else {
            throw DICOMError.parsingFailed("ojph_expand exited with status \(process.terminationStatus)")
        }
        return elapsed
    }

    /// Parses 16-bit P5 PGM (binary grayscale, maxval > 255, big-endian samples per spec).
    /// Returns little-endian pixel bytes for comparison against DICOM's typical layout.
    /// The header is pure ASCII and is scanned byte-by-byte so the binary body doesn't
    /// poison `String(data:encoding:.ascii)`.
    private func parsePGM16AsLE(_ url: URL) throws -> (width: Int, height: Int, data: Data) {
        let raw = try Data(contentsOf: url)

        func isWhitespace(_ b: UInt8) -> Bool {
            b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D
        }

        var i = 0
        var tokens: [String] = []
        while i < raw.count && tokens.count < 4 {
            let b = raw[i]
            if b == 0x23 { // '#' comment until newline
                while i < raw.count && raw[i] != 0x0A { i += 1 }
                if i < raw.count { i += 1 }
                continue
            }
            if isWhitespace(b) { i += 1; continue }
            var end = i
            while end < raw.count && !isWhitespace(raw[end]) && raw[end] != 0x23 { end += 1 }
            let tok = String(data: raw.subdata(in: i..<end), encoding: .ascii) ?? ""
            tokens.append(tok)
            i = end
        }
        // Advance past the single whitespace that terminates the maxval token; body starts there.
        if i < raw.count && isWhitespace(raw[i]) { i += 1 }

        guard tokens.count == 4, tokens[0] == "P5",
              let width = Int(tokens[1]), let height = Int(tokens[2]),
              let maxVal = Int(tokens[3]) else {
            throw DICOMError.parsingFailed("PGM header parse failed: \(tokens)")
        }
        let bytesPerSample = maxVal > 255 ? 2 : 1
        let expected = width * height * bytesPerSample
        guard raw.count >= i + expected else {
            throw DICOMError.parsingFailed("PGM body short: expected \(expected) bytes at offset \(i), got \(raw.count - i)")
        }
        let body = raw.subdata(in: i..<i + expected)
        if bytesPerSample == 1 { return (width, height, body) }
        // PGM 16-bit is big-endian; DICOM stores as LE bytes in PixelData's default Explicit VR LE.
        var le = Data(capacity: expected)
        var j = 0
        while j + 1 < body.count {
            le.append(body[j + 1])
            le.append(body[j])
            j += 2
        }
        return (width, height, le)
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let n = sorted.count
        return n % 2 == 0 ? (sorted[n/2 - 1] + sorted[n/2]) / 2.0 : sorted[n/2]
    }

    // MARK: - Benchmark

    @Test(
        "HTJ2K vs OpenJPH — decode speed and bit-exact comparison on real DICOM",
        .enabled(if: LocalCodecFixtureAvailability.hasMR, "Requires optional MR LocalDatasets fixture")
    )
    func compareHTJ2KDecodeAgainstOpenJPH() throws {
        guard let ojph = openjphExpandPath() else {
            print("SKIP: ojph_expand not found — install via `brew install openjph`")
            return
        }

        let sample = try realSample(modality: "mr")
        let descriptor = sample.pixelData.descriptor
        let original = sample.pixelData.data

        // Encode via DICOMKit's HTJ2K (J2KSwift 5.1.1 .conformant Part-15).
        let codec = J2KSwiftCodec(encodingTransferSyntaxUID: TransferSyntax.htj2kLossless.uid)
        let codestream = try codec.encodeFrame(original, descriptor: descriptor, frameIndex: 0, configuration: .lossless)

        // Write codestream for OpenJPH subprocess.
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("htj2k-ojph-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let j2cURL = tmpDir.appendingPathComponent("frame.j2c")
        let pgmURL = tmpDir.appendingPathComponent("frame.pgm")
        try codestream.write(to: j2cURL)

        // Warm up each decoder once to remove first-call JIT / cache effects.
        _ = try codec.decodeFrame(codestream, descriptor: descriptor, frameIndex: 0)
        _ = try runOJPHExpand(ojph, input: j2cURL, output: pgmURL)

        // Measure medians over N runs.
        let iterations = 5
        var j2kswiftTimes: [Double] = []
        var openjphTimes: [Double] = []
        for _ in 0..<iterations {
            let t0 = CFAbsoluteTimeGetCurrent()
            _ = try codec.decodeFrame(codestream, descriptor: descriptor, frameIndex: 0)
            j2kswiftTimes.append((CFAbsoluteTimeGetCurrent() - t0) * 1000.0)
            openjphTimes.append(try runOJPHExpand(ojph, input: j2cURL, output: pgmURL))
        }

        let j2kswiftDecoded = try codec.decodeFrame(codestream, descriptor: descriptor, frameIndex: 0)
        let openjphParsed = try parsePGM16AsLE(pgmURL)

        // Bit-exact comparison.
        let minLen = min(j2kswiftDecoded.count, openjphParsed.data.count)
        var mismatches = 0
        var firstMismatchOffset = -1
        for i in 0..<minLen where j2kswiftDecoded[i] != openjphParsed.data[i] {
            if firstMismatchOffset < 0 { firstMismatchOffset = i }
            mismatches += 1
        }

        let j2kMedian = median(j2kswiftTimes)
        let ojphMedian = median(openjphTimes)
        let speedup = ojphMedian / j2kMedian

        print("""

        HTJ2K vs OpenJPH comparison
          sample:             \(sample.url.lastPathComponent)
          dimensions:         \(descriptor.columns) x \(descriptor.rows) @ \(descriptor.bitsStored)-bit
          codestream bytes:   \(codestream.count)
          iterations:         \(iterations)
          J2KSwift median:    \(String(format: "%.3f", j2kMedian)) ms  (min \(String(format: "%.3f", j2kswiftTimes.min() ?? 0)), max \(String(format: "%.3f", j2kswiftTimes.max() ?? 0)))
          OpenJPH  median:    \(String(format: "%.3f", ojphMedian)) ms  (min \(String(format: "%.3f", openjphTimes.min() ?? 0)), max \(String(format: "%.3f", openjphTimes.max() ?? 0)))
          speedup (ojph/j2k): \(String(format: "%.2fx", speedup))
          decoded bytes:      J2KSwift=\(j2kswiftDecoded.count), OpenJPH=\(openjphParsed.data.count)
          byte mismatches:    \(mismatches) / \(minLen)\(firstMismatchOffset >= 0 ? " (first at offset \(firstMismatchOffset))" : "")
        """)

        // OpenJPH is the reference — if our output decodes differently the Part-15
        // bitstream is broken. Allow the benchmark to surface the number rather than
        // hard-fail in every CI run, since the bit-exactness is what the failing-case
        // test `htj2k lossless round-trip` already asserts on the J2KSwift side.
        #expect(j2kswiftDecoded.count == openjphParsed.data.count,
                "J2KSwift and OpenJPH decoded byte counts differ — Part-15 bitstream mismatch")
        #expect(mismatches == 0,
                "J2KSwift/OpenJPH decoded pixel mismatch — \(mismatches)/\(minLen) bytes differ, first at offset \(firstMismatchOffset)")
    }

    @Test(
        "HTJ2K decode time breakdown: wrapper vs J2KSwift core",
        .enabled(if: LocalCodecFixtureAvailability.hasMR, "Requires optional MR LocalDatasets fixture")
    )
    func decodeTimeBreakdown() throws {
        #if canImport(SwiftJ2K)
        let sample = try realSample(modality: "mr")
        let descriptor = sample.pixelData.descriptor
        let original = sample.pixelData.data
        let codec = J2KSwiftCodec(encodingTransferSyntaxUID: TransferSyntax.htj2kLossless.uid)
        let codestream = try codec.encodeFrame(original, descriptor: descriptor, frameIndex: 0, configuration: .lossless)

        // Warmups
        _ = try codec.decodeFrame(codestream, descriptor: descriptor, frameIndex: 0)
        let warmSem = DispatchSemaphore(value: 0)
        Task.detached { _ = try? await J2KDecoder().decode(codestream); warmSem.signal() }
        warmSem.wait()

        // Full wrapper decode (includes async bridge, pack/unpack, endian swap).
        var wrapperTimes: [Double] = []
        for _ in 0..<5 {
            let t = CFAbsoluteTimeGetCurrent()
            _ = try codec.decodeFrame(codestream, descriptor: descriptor, frameIndex: 0)
            wrapperTimes.append((CFAbsoluteTimeGetCurrent() - t) * 1000.0)
        }

        // Raw SwiftJ2K core — what we'd time if we could drop the Swift wrapper to zero.
        final class ResultBox: @unchecked Sendable { var ms: Double = 0 }
        var coreTimes: [Double] = []
        for _ in 0..<5 {
            let s = DispatchSemaphore(value: 0)
            let box = ResultBox()
            let streamCopy = codestream
            Task.detached {
                let t = CFAbsoluteTimeGetCurrent()
                _ = try? await J2KDecoder().decode(streamCopy)
                box.ms = (CFAbsoluteTimeGetCurrent() - t) * 1000.0
                s.signal()
            }
            s.wait()
            coreTimes.append(box.ms)
        }

        let wm = median(wrapperTimes)
        let cm = median(coreTimes)
        print("""

        Decode time breakdown (medians over 5 runs)
          sample:              \(sample.url.lastPathComponent)
          J2KSwiftCodec wrap:  \(String(format: "%.3f", wm)) ms
          J2KDecoder core:     \(String(format: "%.3f", cm)) ms  [may be Task-scheduling dominated when run after other detached-Task tests]
          wrapper overhead:    \(String(format: "%.3f", wm - cm)) ms  (async bridge + pack/unpack + endian swap)
        """)
        // No assertion — this is a diagnostic / profiling test. Cross-test
        // Task.detached scheduling occasionally flips wrapper vs core ordering.
        #endif
    }
}
