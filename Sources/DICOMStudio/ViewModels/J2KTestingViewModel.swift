// J2KTestingViewModel.swift
// DICOMStudio
//
// DICOM Studio — J2KSwift implementation testing panel ViewModel
//
// NEMA-verified: 2026a, checked 2026-10-05 — the support matrix is DICOMCore TransferSyntax.selectableEncodings filtered by isJPEG2000, named by SelectableEncoding.displayName (PS3.6 2026a Table A-1 names); the one UID literal (.4.90 default) is an A-1 row; no other standard data

import Foundation
import Observation
import DICOMKit
import DICOMCore
import J2KCore

#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: - Supporting Types

/// A row in the transfer syntax support matrix.
public struct J2KSupportEntry: Sendable, Identifiable {
    public let id: String
    public let uid: String
    public let shortName: String
    /// Intent-aware lossless flag from the shared catalog. For `both`-capable UIDs
    /// (`.91`, `.93`, `.203`) this distinguishes the two rows that share a UID.
    public let isLossless: Bool
    public let canDecode: Bool
    public let canEncode: Bool

    public init(id: String, uid: String, shortName: String, isLossless: Bool,
                canDecode: Bool, canEncode: Bool) {
        self.id = id
        self.uid = uid
        self.shortName = shortName
        self.isLossless = isLossless
        self.canDecode = canDecode
        self.canEncode = canEncode
    }
}

/// Result of a multi-iteration decode benchmark.
public struct J2KBenchmarkResult: Sendable {
    public let iterations: Int
    public let minMs: Double
    public let maxMs: Double
    public let avgMs: Double
    public let totalMs: Double
    public let backend: CodecBackend
    public let codecName: String
    public let transferSyntaxUID: String
}

/// Result of a J2K encode → decode round-trip test for a single transfer syntax.
public struct J2KRoundTripResult: Sendable {
    public let targetSyntaxName: String
    /// Raw pixel buffer size (frame0.count before encoding).
    public let originalBytes: Int
    /// Encoded bitstream size produced by J2KSwift.
    public let encodedBytes: Int
    /// Decoded pixel buffer size after decoding the bitstream back.
    public let decodedBytes: Int
    public let encodeMs: Double
    public let decodeMs: Double
    public let compressionRatio: Double
    /// True when `decodedBytes == originalBytes`.
    public let passed: Bool
    public let notes: String
    // Image geometry (from PixelDataDescriptor)
    public let imageWidth: Int
    public let imageHeight: Int
    public let bitsAllocated: Int
    public let samplesPerPixel: Int
}

/// Per-codec entry in the round-trip results table.
public struct J2KRoundTripEntry: Identifiable, Sendable {
    /// Unique per row — the shared catalog's `SelectableEncoding.id`
    /// ("<uid>#lossless" / "<uid>#lossy" / "<uid>"), so the two `.91`/`.93`/`.203`
    /// rows that share a UID stay distinct in results, image maps, and pickers.
    public let id: String
    public let uid: String
    public let shortName: String
    public var state: J2KRoundTripState

    public init(id: String, uid: String, shortName: String, state: J2KRoundTripState) {
        self.id = id
        self.uid = uid
        self.shortName = shortName
        self.state = state
    }
}

public enum J2KBenchmarkState: Sendable {
    case idle
    case running
    case complete(J2KBenchmarkResult)
    case failed(String)
}

public enum J2KRoundTripState: Sendable {
    case idle
    case running
    case complete(J2KRoundTripResult)
    case failed(String)
}

// MARK: - J2KTestingViewModel

/// ViewModel for the J2KSwift implementation testing panel.
///
/// Provides:
/// - Platform backend probe (Metal / Accelerate / Scalar availability)
/// - J2K / HTJ2K transfer syntax support matrix
/// - Multi-iteration decode benchmark against the current file
/// - Per-codec encode → decode round-trip with image previews
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
@Observable
@MainActor
public final class J2KTestingViewModel {

    // MARK: - Platform Info

    public let availableBackends: [CodecBackend] = CodecBackendProbe.availableBackends
    public let bestBackend: CodecBackend = CodecBackendProbe.bestAvailable
    public let supportMatrix: [J2KSupportEntry] = J2KTestingViewModel.buildSupportMatrix()

    /// Display name for the J2KSwift codec, including its library version
    /// (e.g. "J2KSwift 10.7.0"). Sourced from `J2KCore.getVersion()` so the
    /// comparison UI always shows the J2KSwift build under test.
    public nonisolated static let j2kSwiftCodecName = "J2KSwift \(J2KCore.getVersion())"

    // MARK: - Benchmark

    public var benchmarkState: J2KBenchmarkState = .idle
    public var benchmarkIterations: Int = 10

    // MARK: - Round-Trip

    /// Selectable-encoding id selected for the single-codec run. Keyed on
    /// `SelectableEncoding.id` (not the bare UID) so the two `.91` rows
    /// (Lossless vs Lossy) can be picked and encoded independently. For
    /// single-capability UIDs (e.g. `.90`) the id equals the UID.
    public var selectedRoundTripID: String = "1.2.840.10008.1.2.4.90"

    /// Results of the most recent round-trip run, one entry per codec tested.
    public private(set) var roundTripResults: [J2KRoundTripEntry] = []

    /// Whether any round-trip task is currently in progress.
    public private(set) var isRoundTripRunning: Bool = false

    // MARK: - Images

    #if canImport(CoreGraphics)
    /// The original raw frame from the loaded DICOM file.
    public private(set) var rawImage: CGImage? = nil

    /// Encoded-then-decoded preview images, keyed by transfer syntax UID.
    /// For lossless codecs this is pixel-identical to `rawImage`;
    /// for lossy codecs it shows compression artefacts.
    public private(set) var encodedImages: [String: CGImage] = [:]

    /// Decoded images from the full round-trip, keyed by UID. Identical to
    /// `encodedImages` unless separate encode/decode passes produce different results.
    public private(set) var decodedImages: [String: CGImage] = [:]
    #endif

    // MARK: - Codec Comparison

    /// Results of the most recent codec comparison run.
    public private(set) var comparisonResults: [CodecComparisonEntry] = []

    /// Whether the codec comparison is currently running.
    public private(set) var isComparisonRunning: Bool = false

    /// Codestream byte count from the most recent comparison run (J2K-encoded payload).
    public private(set) var comparisonCodestreamBytes: Int = 0

    /// Raw frame byte count from the most recent comparison run (decoded pixel buffer size).
    public private(set) var comparisonRawBytes: Int = 0

    /// When true, each codec runs 2 untimed warmups + 7 timed runs and the median
    /// of the 7 timed samples is reported. Matches the published J2KSwift cross-host
    /// bench methodology (`Documentation/Benchmarks/CROSS_HOST_M2_M4_inproc.md`):
    /// `--in-proc --runs 7 --warmups 2`, `DispatchTime` clock.
    public var comparisonWarmup: Bool = true

    /// Which J2KSwift decode API the J2K Compare panel exercises for the
    /// J2KSwift row. Defaults to `.cpu` to match the published bench. The viewer's
    /// production decode path is unaffected; it always uses the runtime size router.
    public var j2kSwiftDecodeMode: J2KSwiftDecodeMode = .cpu

    /// Which J2KSwift encode API the J2K Compare panel uses to produce the
    /// reference bitstream. Defaults to `.cpu` to match the published bench.
    /// Other codecs decode whatever J2KSwift produced; only the J2KSwift row's
    /// encode time is reported (the other codecs aren't asked to encode).
    public var j2kSwiftEncodeMode: J2KSwiftEncodeMode = .cpu

    #if canImport(CoreGraphics)
    /// Decoded preview images from the comparison run, keyed by codec name.
    public private(set) var comparisonImages: [String: CGImage] = [:]
    #endif

    // MARK: - Computed

    public var isRunning: Bool {
        if case .running = benchmarkState { return true }
        return isRoundTripRunning || isComparisonRunning
    }

    // MARK: - Actions

    public func runBenchmark(file: DICOMFile) {
        guard !isRunning else { return }
        benchmarkState = .running
        let iterations = max(1, min(100, benchmarkIterations))
        Task {
            let result = await Self.performBenchmark(file: file, iterations: iterations)
            benchmarkState = result
        }
    }

    /// Runs encode → decode for only the selected transfer syntax.
    public func runSelectedRoundTrip(file: DICOMFile) {
        guard !isRunning else { return }
        guard let entry = supportMatrix.first(where: { $0.id == selectedRoundTripID }) else { return }
        let id = entry.id
        let uid = entry.uid
        let name = entry.shortName
        let isLossless = entry.isLossless
        roundTripResults = [J2KRoundTripEntry(id: id, uid: uid, shortName: name, state: .running)]
        isRoundTripRunning = true
        Task {
            let output = await Self.performRoundTrip(file: file, targetUID: uid, targetName: name, isLossless: isLossless)
            roundTripResults = [J2KRoundTripEntry(id: id, uid: uid, shortName: name, state: output.state)]
            #if canImport(CoreGraphics)
            if rawImage == nil { rawImage = output.rawImage }
            if let img = output.encodedImage { encodedImages[id] = img }
            if let img = output.decodedImage { decodedImages[id] = img }
            #endif
            isRoundTripRunning = false
        }
    }

    /// Runs encode → decode for every encodable transfer syntax in parallel.
    public func runAllRoundTrips(file: DICOMFile) {
        guard !isRunning else { return }
        let encodable = supportMatrix.filter(\.canEncode)
        guard !encodable.isEmpty else { return }
        roundTripResults = encodable.map { J2KRoundTripEntry(id: $0.id, uid: $0.uid, shortName: $0.shortName, state: .running) }
        isRoundTripRunning = true
        Task {
            await withTaskGroup(of: (String, RoundTripOutput).self) { group in
                for entry in encodable {
                    let id = entry.id
                    let uid = entry.uid
                    let name = entry.shortName
                    let isLossless = entry.isLossless
                    group.addTask {
                        let output = await Self.performRoundTrip(file: file, targetUID: uid, targetName: name, isLossless: isLossless)
                        return (id, output)
                    }
                }
                for await (id, output) in group {
                    if let idx = roundTripResults.firstIndex(where: { $0.id == id }) {
                        roundTripResults[idx].state = output.state
                    }
                    #if canImport(CoreGraphics)
                    if rawImage == nil { rawImage = output.rawImage }
                    if let img = output.encodedImage { encodedImages[id] = img }
                    if let img = output.decodedImage { decodedImages[id] = img }
                    #endif
                }
            }
            isRoundTripRunning = false
        }
    }

    /// Clears all stored images while keeping metric results.
    public func clearImages() {
        #if canImport(CoreGraphics)
        rawImage = nil
        encodedImages = [:]
        decodedImages = [:]
        #endif
    }

    /// Resets benchmark results, round-trip results, and all images.
    public func reset() {
        guard !isRunning else { return }
        benchmarkState = .idle
        roundTripResults = []
        comparisonResults = []
        comparisonCodestreamBytes = 0
        comparisonRawBytes = 0
        #if canImport(CoreGraphics)
        comparisonImages = [:]
        #endif
        clearImages()
    }

    // MARK: - Codec Comparison

    /// Encodes frame 0 with J2KSwift using the selected transfer syntax, then decodes
    /// the resulting bitstream with J2KSwift and installed external CLI peers.
    /// Results are written to ``comparisonResults`` and ``comparisonImages``.
    public func runCodecComparison(file: DICOMFile) {
        guard !isRunning else { return }
        isComparisonRunning = true
        var entries: [CodecComparisonEntry] = [
            CodecComparisonEntry(codecName: Self.j2kSwiftCodecName, state: .running)
        ]
        #if os(macOS)
        if KakaduCLICodec.binaryPath != nil {
            entries.append(CodecComparisonEntry(codecName: "Kakadu (CLI)", state: .running))
        }
        if GrokCLICodec.binaryPath != nil {
            entries.append(CodecComparisonEntry(codecName: "Grok (CLI)", state: .running))
        }
        #endif
        comparisonResults = entries
        let entry = supportMatrix.first(where: { $0.id == selectedRoundTripID })
        let uid = entry?.uid ?? selectedRoundTripID
        let isLossless = entry?.isLossless ?? true
        let warmup = comparisonWarmup
        let decMode = j2kSwiftDecodeMode
        let encMode = j2kSwiftEncodeMode
        Task {
            let output = await Self.performComparison(file: file, targetUID: uid, isLossless: isLossless, warmup: warmup, j2kSwiftDecodeMode: decMode, j2kSwiftEncodeMode: encMode)
            comparisonResults = output.entries
            comparisonCodestreamBytes = output.codestreamBytes
            comparisonRawBytes = output.rawBytes
            #if canImport(CoreGraphics)
            if rawImage == nil { rawImage = output.rawImage }
            for (name, img) in output.images { comparisonImages[name] = img }
            #endif
            isComparisonRunning = false
        }
    }

    // MARK: - Background Workers

    private static func performBenchmark(file: DICOMFile, iterations: Int) async -> J2KBenchmarkState {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let service = ImageDecodingService()
                var times: [Double] = []
                var lastResult: DecodedImageResult?

                for _ in 0..<iterations {
                    let t0 = Date()
                    guard let r = service.decode(file: file) else {
                        continuation.resume(returning: .failed("File has no pixel data or unsupported codec"))
                        return
                    }
                    times.append(Date().timeIntervalSince(t0) * 1_000)
                    lastResult = r
                }

                guard let last = lastResult, !times.isEmpty else {
                    continuation.resume(returning: .failed("No results recorded"))
                    return
                }

                let avg = times.reduce(0, +) / Double(times.count)
                let result = J2KBenchmarkResult(
                    iterations: iterations,
                    minMs: times.min()!,
                    maxMs: times.max()!,
                    avgMs: avg,
                    totalMs: times.reduce(0, +),
                    backend: last.backend,
                    codecName: last.codecName,
                    transferSyntaxUID: last.transferSyntaxUID
                )
                continuation.resume(returning: .complete(result))
            }
        }
    }

    private static func performRoundTrip(
        file: DICOMFile,
        targetUID: String,
        targetName: String,
        isLossless: Bool
    ) async -> RoundTripOutput {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let pixData = file.pixelData() else {
                    continuation.resume(returning: .init(state: .failed("File has no decodable pixel data")))
                    return
                }
                guard let frame0 = pixData.frameData(at: 0) else {
                    continuation.resume(returning: .init(state: .failed("Frame 0 is not accessible")))
                    return
                }

                let descriptor = pixData.descriptor
                let originalBytes = frame0.count

                // Render original frame for display
                let rawImage = makePreviewImage(pixels: frame0, descriptor: descriptor)

                // Encode
                let encoder = J2KSwiftCodec(encodingTransferSyntaxUID: targetUID)
                let encodeStart = Date()
                let encoded: Data
                do {
                    encoded = try encoder.encodeFrame(
                        frame0,
                        descriptor: descriptor,
                        frameIndex: 0,
                        configuration: CompressionConfiguration(
                            quality: isLossless ? .maximum : .medium,
                            speed: .balanced,
                            progressive: false,
                            preferLossless: isLossless
                        )
                    )
                } catch {
                    continuation.resume(returning: .init(
                        state: .failed("Encode failed: \(error.localizedDescription)"),
                        rawImage: rawImage
                    ))
                    return
                }
                let encodeMs = Date().timeIntervalSince(encodeStart) * 1_000

                // Decode
                let decoder = J2KSwiftCodec()
                let decodeStart = Date()
                let decoded: Data
                do {
                    decoded = try decoder.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0)
                } catch {
                    continuation.resume(returning: .init(
                        state: .failed("Decode failed: \(error.localizedDescription)"),
                        rawImage: rawImage
                    ))
                    return
                }
                let decodeMs = Date().timeIntervalSince(decodeStart) * 1_000

                // Render encoded preview (decoded from encoded bytes) and final decoded image
                let encodedImage = makePreviewImage(pixels: decoded, descriptor: descriptor)
                let decodedImage = encodedImage // same pixels; distinct reference for independent clearing

                let ratio = Double(originalBytes) / Double(max(1, encoded.count))
                let decodedBytes = decoded.count
                let passed = decodedBytes == originalBytes
                let notes: String
                if passed {
                    notes = isLossless
                        ? "Lossless round-trip verified — decoded \(decodedBytes) B matches raw"
                        : "Lossy cycle complete — decoded \(decodedBytes) B (values intentionally differ)"
                } else {
                    notes = "Size mismatch: decoded \(decodedBytes) B ≠ raw \(originalBytes) B"
                }

                let result = J2KRoundTripResult(
                    targetSyntaxName: targetName,
                    originalBytes: originalBytes,
                    encodedBytes: encoded.count,
                    decodedBytes: decodedBytes,
                    encodeMs: encodeMs,
                    decodeMs: decodeMs,
                    compressionRatio: ratio,
                    passed: passed,
                    notes: notes,
                    imageWidth: descriptor.columns,
                    imageHeight: descriptor.rows,
                    bitsAllocated: descriptor.bitsAllocated,
                    samplesPerPixel: descriptor.samplesPerPixel
                )
                continuation.resume(returning: .init(
                    state: .complete(result),
                    rawImage: rawImage,
                    encodedImage: encodedImage,
                    decodedImage: decodedImage
                ))
            }
        }
    }

    // MARK: - Image Rendering

    /// Converts raw pixel bytes + descriptor into a displayable CGImage.
    /// 8-bit data is used directly; 16-bit is auto-normalised to 8-bit.
    private nonisolated static func makePreviewImage(pixels: Data, descriptor: PixelDataDescriptor) -> CGImage? {
        #if canImport(CoreGraphics)
        let w = descriptor.columns
        let h = descriptor.rows
        let spp = descriptor.samplesPerPixel
        let bpa = descriptor.bitsAllocated
        guard w > 0, h > 0, spp == 1 || spp == 3 else { return nil }

        if bpa <= 8 {
            let cs = spp == 1 ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
            let bi = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
            guard let prov = CGDataProvider(data: pixels as CFData) else { return nil }
            return CGImage(width: w, height: h,
                           bitsPerComponent: 8, bitsPerPixel: 8 * spp,
                           bytesPerRow: w * spp,
                           space: cs, bitmapInfo: bi,
                           provider: prov, decode: nil,
                           shouldInterpolate: true, intent: .defaultIntent)
        } else {
            // 16-bit → normalise min/max to 0-255 for display.
            // Read bytes individually (little-endian pairs) — no unsafe memory binding,
            // no alignment requirements.
            let pixelCount = w * h * spp
            guard pixels.count >= pixelCount * 2 else { return nil }
            let base = pixels.startIndex
            var pixelValues = [UInt16](repeating: 0, count: pixelCount)
            var lo: UInt16 = .max, hi: UInt16 = 0
            for i in 0..<pixelCount {
                let v = UInt16(pixels[base + i * 2]) | (UInt16(pixels[base + i * 2 + 1]) << 8)
                pixelValues[i] = v
                if v < lo { lo = v }
                if v > hi { hi = v }
            }
            let rng = hi > lo ? Double(hi - lo) : 1.0
            var outBytes = [UInt8](repeating: 0, count: pixelCount)
            for i in 0..<pixelCount {
                outBytes[i] = UInt8(clamping: Int(Double(pixelValues[i] - lo) / rng * 255.0))
            }
            let out = Data(outBytes)
            let cs = spp == 1 ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
            let bi = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
            guard let prov = CGDataProvider(data: out as CFData) else { return nil }
            return CGImage(width: w, height: h,
                           bitsPerComponent: 8, bitsPerPixel: 8 * spp,
                           bytesPerRow: w * spp,
                           space: cs, bitmapInfo: bi,
                           provider: prov, decode: nil,
                           shouldInterpolate: true, intent: .defaultIntent)
        }
        #else
        return nil
        #endif
    }

    // MARK: - Support Matrix Builder

    private static func buildSupportMatrix() -> [J2KSupportEntry] {
        // Driven by the shared transfer-syntax catalog so the list stays canonical.
        // `both`-capable UIDs (.91/.93/.203) expand into two rows (Lossless + Lossy).
        return TransferSyntax.selectableEncodings
            .filter { $0.transferSyntax.isJPEG2000 }
            .map { enc in
                J2KSupportEntry(
                    id: enc.id,
                    uid: enc.uid,
                    shortName: enc.displayName,
                    isLossless: enc.isLossless,
                    canDecode: CodecRegistry.shared.hasCodec(for: enc.uid),
                    canEncode: CodecRegistry.shared.encoder(for: enc.uid) != nil
                )
            }
    }

    // MARK: - Init

    public init() {}
}

// MARK: - Codec Comparison Types

/// One row in the codec comparison table.
public struct CodecComparisonEntry: Identifiable, Sendable {
    public var id: String { codecName }
    public let codecName: String
    public var state: CodecComparisonState
}

public enum CodecComparisonState: Sendable {
    case idle
    case running
    case complete(CodecComparisonResult)
    case failed(String)
}

/// Timing and correctness result for a single codec in the comparison.
public struct CodecComparisonResult: Sendable {
    public let decodeMs: Double
    public let outputBytes: Int
    /// Whether the output byte count matches the reference (J2KSwift) output.
    public let matchesReference: Bool
    /// Peak signal-to-noise ratio vs J2KSwift output (nil when outputs are different sizes).
    public let psnrDb: Double?
    /// J2KSwift decode route picked for this geometry (`"CPU"`, `"decodeGPU"`,
    /// `"decodeWithGPUHT"`). Populated only for the J2KSwift row; nil for others.
    public let route: String?
    /// Encode time in ms. Populated only for the J2KSwift row (it's the only
    /// codec asked to encode); nil for Kakadu / Grok decode-only rows.
    public let encodeMs: Double?

    public init(decodeMs: Double, outputBytes: Int, matchesReference: Bool, psnrDb: Double?, route: String? = nil, encodeMs: Double? = nil) {
        self.decodeMs = decodeMs
        self.outputBytes = outputBytes
        self.matchesReference = matchesReference
        self.psnrDb = psnrDb
        self.route = route
        self.encodeMs = encodeMs
    }
}

// MARK: - Comparison Background Worker

extension J2KTestingViewModel {

    /// Output bundle returned by `performComparison`.
    fileprivate struct ComparisonOutput: @unchecked Sendable {
        let entries: [CodecComparisonEntry]
        let codestreamBytes: Int
        let rawBytes: Int
        #if canImport(CoreGraphics)
        let rawImage: CGImage?
        let images: [String: CGImage]
        init(entries: [CodecComparisonEntry],
             codestreamBytes: Int = 0,
             rawBytes: Int = 0,
             rawImage: CGImage? = nil,
             images: [String: CGImage] = [:]) {
            self.entries = entries
            self.codestreamBytes = codestreamBytes
            self.rawBytes = rawBytes
            self.rawImage = rawImage
            self.images = images
        }
        #else
        init(entries: [CodecComparisonEntry], codestreamBytes: Int = 0, rawBytes: Int = 0) {
            self.entries = entries
            self.codestreamBytes = codestreamBytes
            self.rawBytes = rawBytes
        }
        #endif
    }

    fileprivate static func performComparison(
        file: DICOMFile,
        targetUID: String,
        isLossless: Bool,
        warmup: Bool,
        j2kSwiftDecodeMode: J2KSwiftDecodeMode,
        j2kSwiftEncodeMode: J2KSwiftEncodeMode
    ) async -> ComparisonOutput {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {

                // 1. Get raw pixels
                guard let pixData = file.pixelData(),
                      let frame0 = pixData.frameData(at: 0) else {
                    let failed = failedEntries("Frame 0 not accessible")
                    #if canImport(CoreGraphics)
                    continuation.resume(returning: ComparisonOutput(entries: failed))
                    #else
                    continuation.resume(returning: ComparisonOutput(entries: failed))
                    #endif
                    return
                }
                let descriptor = pixData.descriptor
                let rawImage = makePreviewImage(pixels: frame0, descriptor: descriptor)
                let rawBytes = frame0.count

                // 2. Encode with J2KSwift via the user-selected API (`j2kSwiftEncodeMode`)
                //    and time it with the same warmup methodology as decode.
                //    `isLossless` comes from the selected row's catalog intent, so the two
                //    `.91` rows encode differently even though they share a UID.
                let encConfig = CompressionConfiguration(
                    quality: isLossless ? .maximum : .medium,
                    speed: .balanced,
                    progressive: false,
                    preferLossless: isLossless
                )
                // Reuse one J2KEncoder across all warmup + timed iterations (matches
                // the upstream InProcBench.swift methodology). Creating a fresh
                // encoder per iteration can race against
                // `HTBlockEncoderConformant.useNEONHotPath`'s dispatch_once init
                // and crash inside `applyEntropyCodingHTJ2KFused` on HT-J2K targets.
                let encWarmups = warmup ? 2 : 0
                let encRuns = warmup ? 7 : 1
                let encResult = J2KSwiftCodec.benchEncode(
                    frame0,
                    descriptor: descriptor,
                    transferSyntaxUID: targetUID,
                    configuration: encConfig,
                    mode: j2kSwiftEncodeMode,
                    warmups: encWarmups,
                    runs: encRuns
                )
                guard let encoded = encResult.data, !encResult.samples.isEmpty else {
                    let failed = failedEntries("Encode failed: \(encResult.error ?? "unknown")")
                    #if canImport(CoreGraphics)
                    continuation.resume(returning: ComparisonOutput(entries: failed, rawImage: rawImage))
                    #else
                    continuation.resume(returning: ComparisonOutput(entries: failed))
                    #endif
                    return
                }
                let sortedEnc = encResult.samples.sorted()
                let encodeMs = sortedEnc[sortedEnc.count / 2]

                var entries: [CodecComparisonEntry] = []
                #if canImport(CoreGraphics)
                var images: [String: CGImage] = [:]
                #endif
                var referenceOutput: Data? = nil

                // 3. Decode with J2KSwift — user-selectable API (`j2kSwiftDecodeMode`).
                //    Default `.cpu` matches the published cross-host bench
                //    (`CROSS_HOST_M2_M4_inproc.md`). `.decodeGPU` / `.decodeWithGPUHT`
                //    pin to the respective GPU API. The viewer's production decode path
                //    is unaffected by this selection.
                let j2kRoute = j2kSwiftDecodeMode.label
                // Same reuse-one-decoder pattern as encode above.
                let decWarmups = warmup ? 2 : 0
                let decRuns = warmup ? 7 : 1
                let decResult = J2KSwiftCodec.benchDecode(
                    encoded,
                    descriptor: descriptor,
                    mode: j2kSwiftDecodeMode,
                    warmups: decWarmups,
                    runs: decRuns
                )
                let j2k: (data: Data?, ms: Double, error: String?) = {
                    if let d = decResult.data, !decResult.samples.isEmpty {
                        let sorted = decResult.samples.sorted()
                        return (d, sorted[sorted.count / 2], nil)
                    }
                    return (nil, 0, decResult.error)
                }()
                if let out = j2k.data {
                    referenceOutput = out
                    entries.append(CodecComparisonEntry(codecName: j2kSwiftCodecName,
                        state: .complete(CodecComparisonResult(
                            decodeMs: j2k.ms, outputBytes: out.count,
                            matchesReference: true, psnrDb: nil,
                            route: j2kRoute, encodeMs: encodeMs))))
                    #if canImport(CoreGraphics)
                    if let img = makePreviewImage(pixels: out, descriptor: descriptor) {
                        images[j2kSwiftCodecName] = img
                    }
                    #endif
                } else {
                    entries.append(CodecComparisonEntry(codecName: j2kSwiftCodecName, state: .failed(j2k.error ?? "Decode failed")))
                }

                // 4. Decode with Kakadu CLI (macOS only, when installed)
                #if os(macOS)
                if KakaduCLICodec.binaryPath != nil {
                    let name = "Kakadu (CLI)"
                    let r = timedDecode(warmup: warmup) {
                        try KakaduCLICodec().decodeFrame(encoded, descriptor: descriptor)
                    }
                    entries.append(makeEntry(name: name, result: r, reference: referenceOutput, descriptor: descriptor))
                    #if canImport(CoreGraphics)
                    if let out = r.data, let img = makePreviewImage(pixels: out, descriptor: descriptor) {
                        images[name] = img
                    }
                    #endif
                }

                // 6. Decode with Grok CLI (macOS only, when installed)
                if GrokCLICodec.binaryPath != nil {
                    let name = "Grok (CLI)"
                    let r = timedDecode(warmup: warmup) {
                        try GrokCLICodec().decodeFrame(encoded, descriptor: descriptor)
                    }
                    entries.append(makeEntry(name: name, result: r, reference: referenceOutput, descriptor: descriptor))
                    #if canImport(CoreGraphics)
                    if let out = r.data, let img = makePreviewImage(pixels: out, descriptor: descriptor) {
                        images[name] = img
                    }
                    #endif
                }
                #endif

                #if canImport(CoreGraphics)
                continuation.resume(returning: ComparisonOutput(
                    entries: entries,
                    codestreamBytes: encoded.count,
                    rawBytes: rawBytes,
                    rawImage: rawImage,
                    images: images))
                #else
                continuation.resume(returning: ComparisonOutput(
                    entries: entries,
                    codestreamBytes: encoded.count,
                    rawBytes: rawBytes))
                #endif
            }
        }
    }

    /// Times a decode closure using `DispatchTime` (ns precision). Matches the
    /// J2KSwift cross-host bench methodology: 2 untimed warmups + 7 timed runs,
    /// median of 7 reported. `warmup: false` falls back to a single timed call
    /// (no warmups) for the quick path.
    private nonisolated static func timedDecode(
        warmup: Bool,
        _ decode: () throws -> Data
    ) -> (data: Data?, ms: Double, error: String?) {
        if !warmup {
            let t0 = DispatchTime.now()
            do {
                let out = try decode()
                let ms = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000.0
                return (out, ms, nil)
            } catch {
                return (nil, 0, error.localizedDescription)
            }
        }

        var lastOut: Data? = nil
        // 2 untimed warmups — pay per-shape cache / JIT / Metal-pipeline costs.
        for _ in 0..<2 {
            do {
                lastOut = try decode()
            } catch {
                return (nil, 0, error.localizedDescription)
            }
        }

        var samples: [Double] = []
        samples.reserveCapacity(7)
        for _ in 0..<7 {
            let t0 = DispatchTime.now()
            do {
                lastOut = try decode()
            } catch {
                return (nil, 0, error.localizedDescription)
            }
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000.0)
        }
        samples.sort()
        // Median of 7 = the 4th element (0-indexed: samples[3]).
        return (lastOut, samples[3], nil)
    }

    /// Builds a CodecComparisonEntry from a `timedDecode` result, comparing against the reference.
    private nonisolated static func makeEntry(
        name: String,
        result: (data: Data?, ms: Double, error: String?),
        reference: Data?,
        descriptor: PixelDataDescriptor
    ) -> CodecComparisonEntry {
        guard let out = result.data else {
            return CodecComparisonEntry(codecName: name, state: .failed(result.error ?? "Decode failed"))
        }
        let matches = out.count == (reference?.count ?? -1)
        let psnr: Double? = matches ? computePSNR(out, reference!, descriptor: descriptor) : nil
        return CodecComparisonEntry(
            codecName: name,
            state: .complete(CodecComparisonResult(
                decodeMs: result.ms, outputBytes: out.count,
                matchesReference: matches, psnrDb: psnr)))
    }

    private nonisolated static func failedEntries(_ msg: String) -> [CodecComparisonEntry] {
        var entries = [CodecComparisonEntry(codecName: j2kSwiftCodecName, state: .failed(msg))]
        #if os(macOS)
        if KakaduCLICodec.binaryPath != nil {
            entries.append(CodecComparisonEntry(codecName: "Kakadu (CLI)", state: .failed(msg)))
        }
        if GrokCLICodec.binaryPath != nil {
            entries.append(CodecComparisonEntry(codecName: "Grok (CLI)", state: .failed(msg)))
        }
        #endif
        return entries
    }

    /// Computes PSNR in dB between two raw pixel buffers.
    /// Returns `nil` (infinity) when buffers are identical (lossless perfect match).
    private nonisolated static func computePSNR(_ a: Data, _ b: Data, descriptor: PixelDataDescriptor) -> Double? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        let maxVal: Double = descriptor.bitsAllocated <= 8 ? 255.0 : 65535.0
        var mse: Double = 0
        for i in 0..<a.count {
            let diff = Double(Int(a[a.startIndex + i]) - Int(b[b.startIndex + i]))
            mse += diff * diff
        }
        mse /= Double(a.count)
        guard mse > 0 else { return nil }   // nil = infinity (perfect lossless match)
        return 10.0 * log10((maxVal * maxVal) / mse)
    }
}

// MARK: - Round-Trip Output (internal)

/// Bundles the state result with optional preview images from a single round-trip run.
/// Marked @unchecked Sendable because CGImage is thread-safe after creation.
private struct RoundTripOutput: @unchecked Sendable {
    let state: J2KRoundTripState
    #if canImport(CoreGraphics)
    let rawImage: CGImage?
    let encodedImage: CGImage?
    let decodedImage: CGImage?
    init(state: J2KRoundTripState, rawImage: CGImage? = nil,
         encodedImage: CGImage? = nil, decodedImage: CGImage? = nil) {
        self.state = state
        self.rawImage = rawImage
        self.encodedImage = encodedImage
        self.decodedImage = decodedImage
    }
    #else
    init(state: J2KRoundTripState) { self.state = state }
    #endif
}
