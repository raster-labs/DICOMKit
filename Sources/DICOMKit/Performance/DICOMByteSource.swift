// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data (byte source abstraction)
import Foundation
import DICOMCore

/// Abstraction over where DICOM bytes come from (RESEARCH_ADOPTION_PLAN.md M2,
/// research-adoption instructions §5 work package A)
///
/// Decouples parser semantics from one storage strategy. This first slice is
/// synchronous and covers the two strategies the M1 baseline exercises:
/// immutable in-memory bytes and a local file (plain read or memory-mapped).
/// Network/streaming sources arrive with the progressive work (M5).
///
/// Strategy note: mapping is **opt-in per call site**, never a fixed file-size
/// rule (instructions §5.1). `Data(contentsOf:options:.mappedIfSafe)` gives
/// page-backed lazy residency; the parser's whole-buffer semantics are
/// unchanged either way.
public protocol DICOMByteSource: Sendable {
    /// Total byte count of the source.
    var count: Int { get }

    /// Stable identity for caching/telemetry (e.g. path + size + mtime).
    var identity: String { get }

    /// Returns the bytes in `range` (bounds-checked; may share storage).
    func bytes(in range: Range<Int>) throws -> Data

    /// Returns the complete contents. For a mapped file source this is the
    /// mapped region (lazily paged), not an eager copy.
    func wholeData() throws -> Data
}

/// In-memory immutable byte source.
public struct InMemoryByteSource: DICOMByteSource {
    private let data: Data
    public let identity: String

    public init(data: Data, identity: String = "memory") {
        self.data = data
        self.identity = "\(identity)#\(data.count)"
    }

    public var count: Int { data.count }

    public func bytes(in range: Range<Int>) throws -> Data {
        guard range.lowerBound >= 0, range.upperBound <= data.count else {
            throw DICOMError.limitExceeded("Byte range \(range) outside source (0..<\(data.count))")
        }
        return data.subdata(in: data.startIndex + range.lowerBound
                              ..< data.startIndex + range.upperBound)
    }

    public func wholeData() throws -> Data { data }
}

/// Local-file byte source: plain read or memory-mapped (`.mappedIfSafe`).
public struct FileByteSource: DICOMByteSource {
    private let data: Data
    public let identity: String
    public let isMapped: Bool

    /// - Parameters:
    ///   - url: File URL.
    ///   - mapped: When true, uses `.mappedIfSafe` — the file is paged in on
    ///     demand instead of read eagerly. The mapping's lifetime is the
    ///     returned `Data`'s lifetime; mutating the file while parsed data is
    ///     alive is undefined, as with any mapped I/O.
    public init(url: URL, mapped: Bool) throws {
        self.data = mapped
            ? try Data(contentsOf: url, options: .mappedIfSafe)
            : try Data(contentsOf: url)
        self.isMapped = mapped
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        self.identity = "\(url.path)#\(data.count)#\(mtime)"
    }

    public var count: Int { data.count }

    public func bytes(in range: Range<Int>) throws -> Data {
        guard range.lowerBound >= 0, range.upperBound <= data.count else {
            throw DICOMError.limitExceeded("Byte range \(range) outside source (0..<\(data.count))")
        }
        return data.subdata(in: data.startIndex + range.lowerBound
                              ..< data.startIndex + range.upperBound)
    }

    public func wholeData() throws -> Data { data }
}
