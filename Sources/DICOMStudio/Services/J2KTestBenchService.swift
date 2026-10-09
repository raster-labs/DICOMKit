// J2KTestBenchService.swift
// DICOMStudio
//
// DICOM Studio — J2K Test Bench codec runner.
//
// Stateless: exercises J2KSwift / Kakadu / Grok on raw frame data
// and scores each reconstruction against the original with a real pass/fail
// criterion — bit-exact for lossless syntaxes, PSNR ≥ threshold for lossy.
// Every entry point is synchronous and blocking; callers run them off the
// main actor.
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no transcribed DICOM-standard data — encodes/decodes through DICOMKit codecs by UID, PSNR dynamic range uses Bits Stored (PS3.3 C.7.6.3.1.1) as 2^bitsStored − 1; names come from J2KBenchSyntax

import Foundation
import DICOMKit
import DICOMCore

public enum J2KTestBenchService {

    /// The J2KSwift encode-quality preset used to produce every *lossy* reference
    /// codestream in the bench matrix. The lossy pass/fail PSNR bar is derived
    /// from this same preset (`CompressionQuality.expectedMinPSNRDb`), so the two
    /// stay co-calibrated: change the preset here and the default threshold moves
    /// with it instead of leaving a fixed bar the preset can't clear.
    public static let lossyEncodeQuality: CompressionQuality = .medium

    // MARK: - Encode

    /// Encodes a frame with the syntax's reference codec to produce the
    /// reference codestream that every codec in that format's matrix then
    /// decodes. JPEG 2000 uses J2KSwift's mode-aware bench encoder; the other
    /// formats use their pure-Swift codec's synchronous `encodeFrame`.
    public static func encodeReference(
        frame: Data,
        descriptor: PixelDataDescriptor,
        syntax: J2KBenchSyntax,
        mode: J2KSwiftEncodeMode,
        warmups: Int,
        runs: Int
    ) -> Result<(codestream: Data, encodeMs: Double), J2KBenchError> {
        let configuration = CompressionConfiguration(
            quality: syntax.isLossless ? .maximum : J2KTestBenchService.lossyEncodeQuality,
            speed: .balanced,
            progressive: false,
            preferLossless: syntax.isLossless
        )
        switch syntax.format {
        case .jpeg2000:
            // A blocked target (currently JPEG 2000 Part 2 `.92`/`.93`) is reported as
            // skipped rather than run. Without this the row would benchmark whatever
            // substitute the planner falls back to and present it as a Part-2 pass.
            if let reason = J2KRoutePlanner.unsupportedEncodeReason(transferSyntaxUID: syntax.uid) {
                return .failure(J2KBenchError(reason, isUnsupported: true))
            }

            let result = J2KSwiftCodec.benchEncode(
                frame,
                descriptor: descriptor,
                transferSyntaxUID: syntax.uid,
                configuration: configuration,
                mode: mode,
                warmups: max(0, warmups),
                runs: max(1, runs)
            )
            guard let data = result.data, !result.samples.isEmpty else {
                return .failure(J2KBenchError(result.error ?? "encode produced no output"))
            }
            return .success((data, median(result.samples)))

        case .jpeg:
            return timedEncode(warmups: warmups, runs: runs) {
                try JLICodec().encodeFrame(frame, descriptor: descriptor,
                                           frameIndex: 0, configuration: configuration)
            }.map { (codestream: $0.data, encodeMs: $0.ms) }

        case .jpegLS:
            return timedEncode(warmups: warmups, runs: runs) {
                try JPEGLSCodec().encodeFrame(frame, descriptor: descriptor,
                                              frameIndex: 0, configuration: configuration)
            }.map { (codestream: $0.data, encodeMs: $0.ms) }

        case .jpegXL:
            return timedEncode(warmups: warmups, runs: runs) {
                try JXLCodec().encodeFrame(frame, descriptor: descriptor,
                                           frameIndex: 0, configuration: configuration)
            }.map { (codestream: $0.data, encodeMs: $0.ms) }
        }
    }

    // MARK: - Decode + score

    /// Decodes the reference codestream with `codec`, times it, and scores the
    /// reconstruction against the original frame.
    public static func decodeAndScore(
        codestream: Data,
        original: Data,
        descriptor: PixelDataDescriptor,
        syntax: J2KBenchSyntax,
        codec: J2KBenchCodec,
        decodeMode: J2KSwiftDecodeMode,
        warmups: Int,
        runs: Int,
        lossyThresholdDb: Double
    ) -> (decodeMs: Double?, psnrDb: Double?, outcome: J2KTestOutcome, decoded: Data?) {

        let decoded: Data
        let decodeMs: Double

        switch codec {
        case .j2kSwift:
            let result = J2KSwiftCodec.benchDecode(
                codestream, descriptor: descriptor, mode: decodeMode,
                warmups: max(0, warmups), runs: max(1, runs))
            guard let data = result.data, !result.samples.isEmpty else {
                return (nil, nil, .error(result.error ?? "decode produced no output"), nil)
            }
            decoded = data
            decodeMs = median(result.samples)

        case .kakadu:
            #if os(macOS)
            guard KakaduCLICodec.binaryPath != nil else {
                return (nil, nil, .skipped("Kakadu CLI not installed"), nil)
            }
            switch timedDecode(warmups: warmups, runs: runs, {
                try KakaduCLICodec().decodeFrame(codestream, descriptor: descriptor)
            }) {
            case .failure(let message): return (nil, nil, .error(message.message), nil)
            case .success(let timed): decoded = timed.data; decodeMs = timed.ms
            }
            #else
            return (nil, nil, .skipped("Kakadu unavailable on this platform"), nil)
            #endif

        case .grok:
            #if os(macOS)
            guard GrokCLICodec.binaryPath != nil else {
                return (nil, nil, .skipped("Grok CLI not installed"), nil)
            }
            switch timedDecode(warmups: warmups, runs: runs, {
                try GrokCLICodec().decodeFrame(codestream, descriptor: descriptor)
            }) {
            case .failure(let message): return (nil, nil, .error(message.message), nil)
            case .success(let timed): decoded = timed.data; decodeMs = timed.ms
            }
            #else
            return (nil, nil, .skipped("Grok unavailable on this platform"), nil)
            #endif

        case .jliSwift:
            switch timedDecode(warmups: warmups, runs: runs, {
                try JLICodec().decodeFrame(codestream, descriptor: descriptor, frameIndex: 0)
            }) {
            case .failure(let message): return (nil, nil, .error(message.message), nil)
            case .success(let timed): decoded = timed.data; decodeMs = timed.ms
            }

        case .djpeg:
            #if os(macOS)
            guard DjpegCLICodec.binaryPath != nil else {
                return (nil, nil, .skipped("djpeg CLI not installed"), nil)
            }
            switch timedDecode(warmups: warmups, runs: runs, {
                try DjpegCLICodec().decodeFrame(codestream, descriptor: descriptor)
            }) {
            case .failure(let message): return (nil, nil, .error(message.message), nil)
            case .success(let timed): decoded = timed.data; decodeMs = timed.ms
            }
            #else
            return (nil, nil, .skipped("djpeg unavailable on this platform"), nil)
            #endif

        case .jlSwift:
            switch timedDecode(warmups: warmups, runs: runs, {
                try JPEGLSCodec().decodeFrame(codestream, descriptor: descriptor, frameIndex: 0)
            }) {
            case .failure(let message): return (nil, nil, .error(message.message), nil)
            case .success(let timed): decoded = timed.data; decodeMs = timed.ms
            }

        case .charls:
            #if os(macOS)
            guard CharLSCLICodec.binaryPath != nil else {
                return (nil, nil, .skipped("dcmdjpls (DCMTK/CharLS) not installed"), nil)
            }
            switch timedDecode(warmups: warmups, runs: runs, {
                try CharLSCLICodec().decodeFrame(codestream, descriptor: descriptor)
            }) {
            case .failure(let message): return (nil, nil, .error(message.message), nil)
            case .success(let timed): decoded = timed.data; decodeMs = timed.ms
            }
            #else
            return (nil, nil, .skipped("CharLS unavailable on this platform"), nil)
            #endif

        case .jxlSwift:
            switch timedDecode(warmups: warmups, runs: runs, {
                try JXLCodec().decodeFrame(codestream, descriptor: descriptor, frameIndex: 0)
            }) {
            case .failure(let message): return (nil, nil, .error(message.message), nil)
            case .success(let timed): decoded = timed.data; decodeMs = timed.ms
            }

        case .djxl:
            #if os(macOS)
            guard DjxlCLICodec.binaryPath != nil else {
                return (nil, nil, .skipped("djxl CLI not installed"), nil)
            }
            switch timedDecode(warmups: warmups, runs: runs, {
                try DjxlCLICodec().decodeFrame(codestream, descriptor: descriptor)
            }) {
            case .failure(let message): return (nil, nil, .error(message.message), nil)
            case .success(let timed): decoded = timed.data; decodeMs = timed.ms
            }
            #else
            return (nil, nil, .skipped("djxl unavailable on this platform"), nil)
            #endif
        }

        let scored = score(decoded: decoded, original: original,
                            syntax: syntax, descriptor: descriptor,
                            lossyThresholdDb: lossyThresholdDb)
        return (decodeMs, scored.psnrDb, scored.outcome, decoded)
    }

    // MARK: - Scoring

    /// Scores a decoded frame against the original: bit-exact reconstruction
    /// for lossless syntaxes, PSNR ≥ threshold for lossy ones.
    public static func score(
        decoded: Data,
        original: Data,
        syntax: J2KBenchSyntax,
        descriptor: PixelDataDescriptor,
        lossyThresholdDb: Double
    ) -> (outcome: J2KTestOutcome, psnrDb: Double?) {
        let expected = descriptor.bytesPerFrame
        let reference: Data = original.count > expected
            ? original.prefix(expected)
            : original

        guard decoded.count == reference.count else {
            return (.fail("decoded \(decoded.count) B ≠ original \(reference.count) B"), nil)
        }

        let differing = differingByteCount(decoded, reference)
        let psnr = computePSNR(decoded: decoded, original: reference, descriptor: descriptor)

        if syntax.isLossless {
            if differing == 0 {
                return (.pass, psnr)            // psnr nil ⇒ infinite (perfect)
            }
            let pct = Double(differing) / Double(max(1, decoded.count)) * 100
            return (.fail(String(format: "not bit-exact — %d B differ (%.2f%%)", differing, pct)), psnr)
        } else {
            guard let psnr else { return (.pass, nil) }   // perfect reconstruction
            if psnr >= lossyThresholdDb {
                return (.pass, psnr)
            }
            return (.fail(String(format: "PSNR %.1f dB < %.0f dB threshold", psnr, lossyThresholdDb)), psnr)
        }
    }

    // MARK: - Helpers

    /// Median of timing samples — same convention as the cross-host bench.
    public static func median(_ samples: [Double]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        return sorted[sorted.count / 2]
    }

    private static func timedDecode(
        warmups: Int,
        runs: Int,
        _ decode: () throws -> Data
    ) -> Result<(data: Data, ms: Double), J2KBenchError> {
        do {
            var last = Data()
            for _ in 0..<max(0, warmups) { last = try decode() }
            var samples: [Double] = []
            let timed = max(1, runs)
            samples.reserveCapacity(timed)
            for _ in 0..<timed {
                let start = DispatchTime.now()
                last = try decode()
                let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                samples.append(Double(ns) / 1_000_000.0)
            }
            return .success((last, median(samples)))
        } catch {
            return .failure(J2KBenchError(error.localizedDescription))
        }
    }

    /// Encode counterpart of `timedDecode`: warmups + median-timed encode runs,
    /// returning the last produced bitstream and the median wall-clock time.
    /// Used for the non-J2KSwift reference encoders (JLISwift / JLSwift / JXLSwift),
    /// whose `encodeFrame` is synchronous (J2KSwift has its own benchEncode).
    private static func timedEncode(
        warmups: Int,
        runs: Int,
        _ encode: () throws -> Data
    ) -> Result<(data: Data, ms: Double), J2KBenchError> {
        do {
            var last = Data()
            for _ in 0..<max(0, warmups) { last = try encode() }
            var samples: [Double] = []
            let timed = max(1, runs)
            samples.reserveCapacity(timed)
            for _ in 0..<timed {
                let start = DispatchTime.now()
                last = try encode()
                let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                samples.append(Double(ns) / 1_000_000.0)
            }
            return .success((last, median(samples)))
        } catch {
            return .failure(J2KBenchError(error.localizedDescription))
        }
    }

    private static func differingByteCount(_ a: Data, _ b: Data) -> Int {
        guard a.count == b.count else { return max(a.count, b.count) }
        var diff = 0
        let aBase = a.startIndex
        let bBase = b.startIndex
        for i in 0..<a.count where a[aBase + i] != b[bBase + i] { diff += 1 }
        return diff
    }

    /// Sample-wise PSNR in dB. `nil` means the frames are identical (infinite).
    /// 16-bit data is compared as little-endian samples, not raw bytes, and the
    /// dynamic range uses `bitsStored` so the figure is physically meaningful.
    public static func computePSNR(
        decoded: Data,
        original: Data,
        descriptor: PixelDataDescriptor
    ) -> Double? {
        guard decoded.count == original.count, !decoded.isEmpty else { return nil }
        let dBase = decoded.startIndex
        let oBase = original.startIndex
        let maxValue = Double((1 << max(1, descriptor.bitsStored)) - 1)
        var mse = 0.0

        if descriptor.bitsAllocated <= 8 {
            for i in 0..<decoded.count {
                let diff = Double(Int(decoded[dBase + i]) - Int(original[oBase + i]))
                mse += diff * diff
            }
            mse /= Double(decoded.count)
        } else {
            let sampleCount = decoded.count / 2
            guard sampleCount > 0 else { return nil }
            for i in 0..<sampleCount {
                let d = Int(decoded[dBase + 2 * i]) | (Int(decoded[dBase + 2 * i + 1]) << 8)
                let o = Int(original[oBase + 2 * i]) | (Int(original[oBase + 2 * i + 1]) << 8)
                let diff = Double(d - o)
                mse += diff * diff
            }
            mse /= Double(sampleCount)
        }

        guard mse > 0 else { return nil }
        return 10.0 * log10((maxValue * maxValue) / mse)
    }

    // MARK: - Full-resolution decode

    /// Decodes a codestream once — no warmups, no timing — for the lightbox.
    /// Returns the raw pixel buffer, or `nil` if the codec is unavailable or
    /// the decode fails.
    public static func decodeFullResolution(
        codestream: Data,
        descriptor: PixelDataDescriptor,
        codec: J2KBenchCodec,
        decodeMode: J2KSwiftDecodeMode
    ) -> Data? {
        switch codec {
        case .j2kSwift:
            return J2KSwiftCodec.benchDecode(codestream, descriptor: descriptor,
                                             mode: decodeMode, warmups: 0, runs: 1).data
        case .kakadu:
            #if os(macOS)
            return try? KakaduCLICodec().decodeFrame(codestream, descriptor: descriptor)
            #else
            return nil
            #endif
        case .grok:
            #if os(macOS)
            return try? GrokCLICodec().decodeFrame(codestream, descriptor: descriptor)
            #else
            return nil
            #endif
        case .jliSwift:
            return try? JLICodec().decodeFrame(codestream, descriptor: descriptor, frameIndex: 0)
        case .jlSwift:
            return try? JPEGLSCodec().decodeFrame(codestream, descriptor: descriptor, frameIndex: 0)
        case .charls:
            #if os(macOS)
            return try? CharLSCLICodec().decodeFrame(codestream, descriptor: descriptor)
            #else
            return nil
            #endif
        case .jxlSwift:
            return try? JXLCodec().decodeFrame(codestream, descriptor: descriptor, frameIndex: 0)
        case .djpeg:
            #if os(macOS)
            return try? DjpegCLICodec().decodeFrame(codestream, descriptor: descriptor)
            #else
            return nil
            #endif
        case .djxl:
            #if os(macOS)
            return try? DjxlCLICodec().decodeFrame(codestream, descriptor: descriptor)
            #else
            return nil
            #endif
        }
    }
}
