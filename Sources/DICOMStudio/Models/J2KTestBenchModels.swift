// J2KTestBenchModels.swift
// DICOMStudio
//
// DICOM Studio — J2K Test Bench data model.
//
// The test bench runs a matrix of (fixture × transfer syntax × codec) cells,
// scores each against a real pass/fail criterion — bit-exact reconstruction
// for lossless syntaxes, a PSNR threshold for lossy — and persists every run
// so codec speed/quality regressions are visible over time.
//
// NEMA-verified: 2026a, checked 2026-10-05 — J2KBenchSyntax.all is built from DICOMCore TransferSyntax.selectableEncodings, so its names are SelectableEncoding.displayName (PS3.6 2026a Table A-1 names); the 5 default UIDs of J2KTestPlan are A-1 rows and their comment names text-diffed against A-1 (5 match after .110 "JPEG XL Lossless Only" → "JPEG XL Lossless"); isLossless defaults to the registry's answer; the rest is bench plumbing

import Foundation
import DICOMCore

// MARK: - Errors

/// A lightweight, message-carrying error so bench sub-operations can surface a
/// human-readable reason through `Result`.
public struct J2KBenchError: Error, Sendable {
    public let message: String
    /// `true` when the target is deliberately blocked rather than broken — the
    /// codec declines to produce this syntax at all (see
    /// `J2KRoutePlanner.unsupportedEncodeReason`). Such a row is reported as
    /// ``J2KTestOutcome/skipped(_:)``, not as an error: nothing failed, there was
    /// simply nothing to measure.
    public let isUnsupported: Bool

    public init(_ message: String, isUnsupported: Bool = false) {
        self.message = message
        self.isUnsupported = isUnsupported
    }
}

// MARK: - Codec

/// A compression family the bench can exercise. Each format names one
/// reference Swift codec (which produces the codestream) plus the same-family
/// peer codecs that decode it — mirroring how J2KSwift is compared against
/// Kakadu/Grok, replicated per format.
public enum J2KBenchFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case jpeg2000 = "JPEG 2000"
    case jpeg     = "JPEG"
    case jpegLS   = "JPEG-LS"
    case jpegXL   = "JPEG XL"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .jpeg2000: return "square.stack.3d.up"
        case .jpeg:     return "photo"
        case .jpegLS:   return "waveform"
        case .jpegXL:   return "sparkles"
        }
    }

    /// The Swift codec that produces this format's reference codestream.
    public var referenceCodec: J2KBenchCodec {
        switch self {
        case .jpeg2000: return .j2kSwift
        case .jpeg:     return .jliSwift
        case .jpegLS:   return .jlSwift
        case .jpegXL:   return .jxlSwift
        }
    }

    /// All codecs in this format's bench, reference first then same-family peers.
    public var codecs: [J2KBenchCodec] {
        switch self {
        case .jpeg2000: return [.j2kSwift, .kakadu, .grok]
        case .jpeg:     return [.jliSwift, .djpeg]
        case .jpegLS:   return [.jlSwift, .charls]
        case .jpegXL:   return [.jxlSwift, .djxl]
        }
    }
}

/// A codec participating in a test-bench run.
public enum J2KBenchCodec: String, CaseIterable, Identifiable, Codable, Sendable {
    // JPEG 2000 family
    case j2kSwift = "J2KSwift"
    case kakadu   = "Kakadu"
    case grok     = "Grok"
    // JPEG family
    case jliSwift = "JLISwift"
    case djpeg    = "djpeg"
    // JPEG-LS family
    case jlSwift  = "JLSwift"
    case charls   = "CharLS (dcmdjpls)"
    // JPEG XL family
    case jxlSwift = "JXLSwift"
    case djxl     = "djxl"

    public var id: String { rawValue }

    /// The compression family this codec belongs to.
    public var format: J2KBenchFormat {
        switch self {
        case .j2kSwift, .kakadu, .grok: return .jpeg2000
        case .jliSwift, .djpeg:                    return .jpeg
        case .jlSwift, .charls:                    return .jpegLS
        case .jxlSwift, .djxl:                     return .jpegXL
        }
    }

    /// True for the reference codec of each format — the one that produces the
    /// codestream its peers decode. Peers are decode-only in the bench.
    public var encodes: Bool { self == format.referenceCodec }

    /// SF Symbol shown beside the codec in the results grid.
    public var systemImage: String {
        switch self {
        case .j2kSwift, .jliSwift, .jlSwift, .jxlSwift: return "swift"
        case .kakadu, .grok, .djpeg, .djxl, .charls:    return "terminal"
        }
    }
}

// MARK: - Transfer syntax

/// A transfer syntax / mode the bench can exercise, tagged with its codec
/// family. Every family's modes come from the shared core catalog (see
/// ``all``): JPEG exposes Baseline/Extended/Lossless variants, JPEG-LS its
/// Lossless + Near-Lossless pair, JPEG XL Lossless (.110) + the general JPEG XL
/// (lossless/lossy) syntax — the bench's axis is bit-exact round-trip (lossless) or
/// PSNR (lossy). Names follow PS3.6 Table A-1 (``SelectableEncoding/displayName``).
public struct J2KBenchSyntax: Identifiable, Hashable, Codable, Sendable {
    /// Unique per row. For JPEG 2000 `both`-capable UIDs (.91/.93/.203) this is the
    /// shared catalog's `SelectableEncoding.id` ("<uid>#lossless" / "<uid>#lossy"),
    /// so the two rows that share a UID stay distinct. For single-capability
    /// syntaxes it equals the UID.
    public let id: String
    public let uid: String
    public let shortName: String
    /// The codec family this syntax belongs to.
    public let format: J2KBenchFormat
    /// Lossless syntaxes must reconstruct bit-exact; lossy ones are scored
    /// against a PSNR threshold.
    public let isLossless: Bool

    public init(id: String? = nil, uid: String, shortName: String,
                format: J2KBenchFormat = .jpeg2000, isLossless: Bool? = nil) {
        self.uid = uid
        self.shortName = shortName
        self.format = format
        // When not specified, ask the registry: a `both`-capable UID (.91/.93/.203/.112)
        // reports lossy, as do the lossy-only syntaxes (.50/.51/.81), so the bench scores
        // them by PSNR rather than demanding a bit-exact round trip. The old UID-suffix
        // guess called JPEG Baseline and JPEG-LS Near-Lossless "lossless".
        self.isLossless = isLossless
            ?? TransferSyntax.from(uid: uid)?.isLossless
            ?? (!uid.hasSuffix(".91") && !uid.hasSuffix(".93") && !uid.hasSuffix(".203"))
        self.id = id ?? uid
    }

    /// Every syntax across all formats, driven entirely by the shared
    /// transfer-syntax catalog so each codec family's mode list stays canonical
    /// with DICOMKit core. Each `both`-capable UID (JPEG 2000 `.91`/`.93`, HTJ2K
    /// `.203`, JPEG XL `.112`) expands into two rows (Lossless + Lossy); every
    /// other UID contributes one. The bench encodes raw frames, so JPEG XL's JPEG
    /// Recompression syntax (`.111`) — which losslessly repacks an *existing* JPEG
    /// rather than a raw frame — is excluded, matching the omission in
    /// ``TransferSyntax/negotiableImageSyntaxTokens``.
    public static let all: [J2KBenchSyntax] = {
        TransferSyntax.selectableEncodings.compactMap { enc -> J2KBenchSyntax? in
            guard enc.uid != TransferSyntax.jpegXLRecompression.uid else { return nil }
            guard let format = benchFormat(for: enc.transferSyntax) else { return nil }
            return J2KBenchSyntax(id: enc.id, uid: enc.uid, shortName: enc.displayName,
                                  format: format, isLossless: enc.isLossless)
        }
    }()

    /// Maps a core transfer syntax to the bench codec family that exercises it,
    /// or `nil` for syntaxes no bench family covers (uncompressed, RLE, video, JPIP).
    private static func benchFormat(for ts: TransferSyntax) -> J2KBenchFormat? {
        if ts.isJPEG2000 { return .jpeg2000 }
        if ts.isJPEG     { return .jpeg }
        if ts.isJPEGLS   { return .jpegLS }
        if ts.isJPEGXL   { return .jpegXL }
        return nil
    }

    /// Syntaxes belonging to a given format, in canonical order.
    public static func all(for format: J2KBenchFormat) -> [J2KBenchSyntax] {
        all.filter { $0.format == format }
    }

    public static func named(_ uid: String) -> J2KBenchSyntax? {
        all.first { $0.uid == uid }
    }
}

// MARK: - Fixture

/// One DICOM image in the test corpus. Geometry is cached on add so the
/// corpus list renders without re-reading every file.
public struct J2KTestFixture: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let path: String
    /// Absolute path of the original source file, used to de-duplicate the
    /// corpus. Optional so corpora saved before this field still decode.
    public let sourcePath: String?
    public var name: String
    public let columns: Int
    public let rows: Int
    public let bitsAllocated: Int
    public let samplesPerPixel: Int
    public let frameCount: Int
    public let photometric: String
    public let modality: String

    public init(id: UUID = UUID(), path: String, sourcePath: String? = nil,
                name: String, columns: Int, rows: Int, bitsAllocated: Int,
                samplesPerPixel: Int, frameCount: Int,
                photometric: String, modality: String) {
        self.id = id
        self.path = path
        self.sourcePath = sourcePath
        self.name = name
        self.columns = columns
        self.rows = rows
        self.bitsAllocated = bitsAllocated
        self.samplesPerPixel = samplesPerPixel
        self.frameCount = frameCount
        self.photometric = photometric
        self.modality = modality
    }

    /// Pixels per frame — used for nearest-baseline matching.
    public var pixelCount: Int { columns * rows }

    /// "512×512 · 16-bit · MONOCHROME2 · 3 frames"
    public var geometrySummary: String {
        let frames = frameCount == 1 ? "1 frame" : "\(frameCount) frames"
        let kind = samplesPerPixel >= 3 ? "RGB" : photometric
        return "\(columns)×\(rows) · \(bitsAllocated)-bit · \(kind) · \(frames)"
    }
}

// MARK: - Outcome

/// Outcome of one test cell against its pass criterion.
public enum J2KTestOutcome: Codable, Equatable, Sendable {
    /// Met the criterion — bit-exact (lossless) or PSNR ≥ threshold (lossy).
    case pass
    /// Ran cleanly but missed the criterion.
    case fail(String)
    /// Encode or decode threw.
    case error(String)
    /// Codec unavailable, or the operation does not apply.
    case skipped(String)

    public var isPass: Bool { if case .pass = self { return true } else { return false } }
    public var isFail: Bool { if case .fail = self { return true } else { return false } }
    public var isError: Bool { if case .error = self { return true } else { return false } }
    public var isSkipped: Bool { if case .skipped = self { return true } else { return false } }

    /// Human-readable detail for the results grid.
    public var detail: String {
        switch self {
        case .pass: return "Pass"
        case .fail(let reason): return reason
        case .error(let reason): return reason
        case .skipped(let reason): return reason
        }
    }
}

// MARK: - Cell

/// Result for one (fixture, syntax, codec) cell of the test matrix.
///
/// The fixture and syntax names are denormalized into the cell so a persisted
/// run is fully self-describing without the live corpus.
public struct J2KTestCell: Identifiable, Codable, Sendable {
    public let id: UUID
    public let fixtureName: String
    /// Modality of the source fixture (e.g. "CT") — denormalized so a loaded
    /// historical run can still be matched against the published baseline.
    public let fixtureModality: String
    /// Pixels per frame of the source fixture, for nearest-baseline matching.
    public let fixturePixelCount: Int
    public let syntaxUID: String
    public let syntaxName: String
    public let codec: J2KBenchCodec

    /// Encode time (ms) — populated only for the encoding codec (J2KSwift).
    public var encodeMs: Double?
    /// Decode time (ms) — median of the timed runs.
    public var decodeMs: Double?
    /// Encoded codestream size (bytes).
    public var encodedBytes: Int?
    /// Raw frame size (bytes) before encoding.
    public var rawBytes: Int?
    public var compressionRatio: Double?
    /// PSNR of the decoded frame vs the original, in dB. `nil` means infinite
    /// (bit-exact reconstruction).
    public var psnrDb: Double?
    public var outcome: J2KTestOutcome

    public init(id: UUID = UUID(), fixtureName: String,
                fixtureModality: String = "", fixturePixelCount: Int = 0,
                syntaxUID: String, syntaxName: String, codec: J2KBenchCodec,
                encodeMs: Double? = nil, decodeMs: Double? = nil,
                encodedBytes: Int? = nil, rawBytes: Int? = nil,
                compressionRatio: Double? = nil, psnrDb: Double? = nil,
                outcome: J2KTestOutcome) {
        self.id = id
        self.fixtureName = fixtureName
        self.fixtureModality = fixtureModality
        self.fixturePixelCount = fixturePixelCount
        self.syntaxUID = syntaxUID
        self.syntaxName = syntaxName
        self.codec = codec
        self.encodeMs = encodeMs
        self.decodeMs = decodeMs
        self.encodedBytes = encodedBytes
        self.rawBytes = rawBytes
        self.compressionRatio = compressionRatio
        self.psnrDb = psnrDb
        self.outcome = outcome
    }

    /// Stable identity across runs — used to line up regression deltas. Includes
    /// `syntaxName` so the two rows of a `both`-capable UID (e.g. `.91` Lossless vs
    /// Lossy) stay distinct even though they share `syntaxUID`.
    public var matchKey: String { "\(fixtureName)|\(syntaxUID)|\(syntaxName)|\(codec.rawValue)" }
}

// MARK: - Run

/// A complete test-bench run — the unit of history and regression diffing.
public struct J2KTestRun: Identifiable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    /// "J2KSwift 10.9.3 · arm64" — the environment the run was captured on.
    public let environment: String
    public let cells: [J2KTestCell]
    public let fixtureCount: Int
    public let syntaxCount: Int

    public init(id: UUID = UUID(), timestamp: Date = Date(),
                environment: String, cells: [J2KTestCell],
                fixtureCount: Int, syntaxCount: Int) {
        self.id = id
        self.timestamp = timestamp
        self.environment = environment
        self.cells = cells
        self.fixtureCount = fixtureCount
        self.syntaxCount = syntaxCount
    }

    public var passCount: Int { cells.filter { $0.outcome.isPass }.count }
    public var failCount: Int { cells.filter { !$0.outcome.isPass }.count }
    public var totalCount: Int { cells.count }

    /// Cells keyed by `matchKey` for O(1) regression lookup.
    public var cellsByKey: [String: J2KTestCell] {
        Dictionary(cells.map { ($0.matchKey, $0) }, uniquingKeysWith: { a, _ in a })
    }
}

// MARK: - Plan

/// Configuration for a test-bench run.
public struct J2KTestPlan: Sendable {
    /// The compression family being benchmarked.
    public var format: J2KBenchFormat
    /// Transfer syntaxes to exercise, keyed by ``J2KBenchSyntax/id`` (not the bare
    /// UID) so the two rows of a `both`-capable UID can be selected independently.
    public var selectedSyntaxIDs: Set<String>
    public var includeKakadu: Bool
    public var includeGrok: Bool
    /// JPEG peer (libjpeg-turbo djpeg) — decodes the JLISwift codestream.
    public var includeDjpeg: Bool
    /// JPEG XL peer (libjxl djxl) — decodes the JXLSwift codestream.
    public var includeDjxl: Bool
    /// JPEG-LS peer (DCMTK dcmdjpls, CharLS-backed) — decodes the JLSwift codestream.
    public var includeCharLS: Bool
    /// Which J2KSwift encode API produces the reference codestream (JPEG 2000 only).
    public var encodeMode: J2KSwiftEncodeMode
    /// Which J2KSwift decode API the J2KSwift row exercises (JPEG 2000 only).
    public var decodeMode: J2KSwiftDecodeMode
    /// Untimed warmups before timing (cross-host bench default: 2).
    public var warmups: Int
    /// Timed runs; the median is reported (cross-host bench default: 7).
    public var timedRuns: Int
    /// Minimum PSNR (dB) for a lossy cell to pass. Defaults to the bar implied by
    /// the bench's lossy encode preset (`J2KTestBenchService.lossyEncodeQuality`)
    /// so it tracks that preset instead of a fixed value the preset can't clear.
    public var lossyPSNRThresholdDb: Double

    public init(format: J2KBenchFormat = .jpeg2000,
                // PS3.6 2026a Table A-1 names:
                selectedSyntaxIDs: Set<String> = ["1.2.840.10008.1.2.4.90",   // JPEG 2000 Image Compression (Lossless Only)
                                                  "1.2.840.10008.1.2.4.201",  // High-Throughput JPEG 2000 Image Compression (Lossless Only)
                                                  "1.2.840.10008.1.2.4.70",   // JPEG Lossless, Non-Hierarchical, First-Order Prediction (Process 14 [Selection Value 1])
                                                  "1.2.840.10008.1.2.4.80",   // JPEG-LS Lossless Image Compression
                                                  "1.2.840.10008.1.2.4.110"], // JPEG XL Lossless
                includeKakadu: Bool = true,
                includeGrok: Bool = true,
                includeDjpeg: Bool = true,
                includeDjxl: Bool = true,
                includeCharLS: Bool = true,
                encodeMode: J2KSwiftEncodeMode = .cpu,
                decodeMode: J2KSwiftDecodeMode = .cpu,
                warmups: Int = 2,
                timedRuns: Int = 7,
                lossyPSNRThresholdDb: Double = J2KTestBenchService.lossyEncodeQuality.expectedMinPSNRDb) {
        self.format = format
        self.selectedSyntaxIDs = selectedSyntaxIDs
        self.includeKakadu = includeKakadu
        self.includeGrok = includeGrok
        self.includeDjpeg = includeDjpeg
        self.includeDjxl = includeDjxl
        self.includeCharLS = includeCharLS
        self.encodeMode = encodeMode
        self.decodeMode = decodeMode
        self.warmups = warmups
        self.timedRuns = timedRuns
        self.lossyPSNRThresholdDb = lossyPSNRThresholdDb
    }

    /// Selected syntaxes for the active format, in canonical order.
    public var syntaxes: [J2KBenchSyntax] {
        J2KBenchSyntax.all(for: format).filter { selectedSyntaxIDs.contains($0.id) }
    }
}
