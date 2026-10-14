// NEMA-verified: 2026a, checked 2026-10-14 — no DICOM-standard data (verified file I/O).
#if canImport(CryptoKit) && canImport(Darwin)
import Foundation
import CryptoKit
import Darwin
import DICOMCore

/// Bounded acquisition failures deliberately omit paths and source contents.
public enum VerifiedSourceError: Error, Equatable, Sendable {
    case invalidOptions, notRegularFile, sizeLimit, readFailed, sourceChanged
    case invalidRange, unbudgetedReadUnsupported
}

/// Anchored regular-file source with a complete SHA-256 identity and verified reads.
///
/// Initial capture hashes every byte incrementally and retains only block digests.
/// Later reads hash each complete block and expose exactly those verified bytes.
/// Metadata guards detect ordinary replacement/truncation/mutation; block hashes
/// also detect changed contents when file timestamps have been restored. This is
/// not an atomic filesystem snapshot against a hostile writer during capture.
/// No file mappings or complete owned snapshots are used.
public final class VerifiedFileByteSource: DICOMVerifiedByteSource, @unchecked Sendable {
    /// Largest source admitted by this initial verified-input profile, in bytes.
    public static let maximumSourceBytes = 256 * 1024 * 1024
    /// Fixed verification block length in bytes.
    public static let blockBytes = 64 * 1024
    /// Complete source length captured at initialization.
    public let count: Int
    /// Lowercase SHA-256 of the complete captured byte transcript.
    public let identity: String
    private let descriptor: Int32
    private let path: String?
    private let fingerprint: Fingerprint
    private let hashes: DICOMByteBuffer
    private let controlLease: DICOMAllocationLease
    /// Ledger shared by the source, parsed views and acquired byte buffers.
    public var allocationBudget: DICOMAllocationBudget { budget }
    private let budget: DICOMAllocationBudget
    private let hooks: Hooks
    private let lock = NSLock()
    private var invalid = false

    enum Stage: Sendable { case capturedBlock(Int), beforeVerification, verifiedBlock(Int) }
    struct Hooks: Sendable {
        var stage: (@Sendable (Stage) throws -> Void)?
        var read: @Sendable (Int32, UnsafeMutableRawPointer?, Int, off_t) -> Int = {
            Darwin.pread($0, $1, $2, $3)
        }
    }
    private struct Fingerprint: Equatable, Sendable {
        let device: dev_t, inode: ino_t, mode: mode_t, size: off_t
        let modifiedSeconds: Int, modifiedNanos: Int, changedSeconds: Int, changedNanos: Int
        init(_ value: stat) {
            device = value.st_dev; inode = value.st_ino; mode = value.st_mode; size = value.st_size
            modifiedSeconds = value.st_mtimespec.tv_sec; modifiedNanos = value.st_mtimespec.tv_nsec
            changedSeconds = value.st_ctimespec.tv_sec; changedNanos = value.st_ctimespec.tv_nsec
        }
    }

    /// Open a path with no final-component symlink following. The source owns the
    /// descriptor until all parsed views and acquisitions release this object.
    /// - Parameters:
    ///   - url: Regular file URL; a final-component symlink is refused.
    ///   - budget: Ledger shared by source and all acquired storage.
    ///   - maximumBytes: Source byte limit, at most `maximumSourceBytes`.
    public convenience init(url: URL, budget: DICOMAllocationBudget,
                            maximumBytes: Int = maximumSourceBytes) throws {
        try self.init(url: url, budget: budget, maximumBytes: maximumBytes, hooks: Hooks())
    }
    convenience init(url: URL, budget: DICOMAllocationBudget, maximumBytes: Int, hooks: Hooks) throws {
        let path = url.path
        guard url.isFileURL, !path.utf8.contains(0) else { throw VerifiedSourceError.invalidOptions }
        let initial = try Self.pathFingerprint(path)
        guard initial.mode & S_IFMT == S_IFREG else { throw VerifiedSourceError.notRegularFile }
        let fd = path.withCString { Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC) }
        guard fd >= 0 else { throw VerifiedSourceError.readFailed }
        // The designated initializer takes ownership even when it fails.
        try self.init(ownedDescriptor: fd, path: path, expected: initial,
                      budget: budget, maximumBytes: maximumBytes, hooks: hooks)
    }

    /// Duplicate a caller-owned descriptor. Reads use pread and never alter the
    /// caller's file offset. This checks the anchored file, not an absent path.
    /// - Parameters:
    ///   - descriptor: Caller-owned readable regular-file descriptor, retained independently by duplication.
    ///   - budget: Ledger shared by source and all acquired storage.
    ///   - maximumBytes: Source byte limit, at most `maximumSourceBytes`.
    public convenience init(descriptor: Int32, budget: DICOMAllocationBudget,
                            maximumBytes: Int = maximumSourceBytes) throws {
        let fd = fcntl(descriptor, F_DUPFD_CLOEXEC, 0)
        guard fd >= 0 else { throw VerifiedSourceError.readFailed }
        try self.init(ownedDescriptor: fd, path: nil, expected: nil,
                      budget: budget, maximumBytes: maximumBytes, hooks: Hooks())
    }

    private init(ownedDescriptor fd: Int32, path: String?, expected: Fingerprint?,
                 budget: DICOMAllocationBudget, maximumBytes: Int, hooks: Hooks) throws {
        var acquired = false
        defer { if !acquired { _ = Darwin.close(fd) } }
        try Task.checkCancellation()
        guard maximumBytes >= 0, maximumBytes <= Self.maximumSourceBytes else {
            throw VerifiedSourceError.invalidOptions
        }
        let initial = try Self.descriptorFingerprint(fd)
        guard initial.mode & S_IFMT == S_IFREG else { throw VerifiedSourceError.notRegularFile }
        guard expected == nil || expected == initial else { throw VerifiedSourceError.sourceChanged }
        if let path, try Self.pathFingerprint(path) != initial { throw VerifiedSourceError.sourceChanged }
        guard initial.size >= 0, initial.size <= maximumBytes else { throw VerifiedSourceError.sizeLimit }
        let count = Int(initial.size)
        let blocks = (count + Self.blockBytes - 1) / Self.blockBytes
        // Provisional control allowance for source/lock/path and hash contexts;
        // it is not a qualified runtime-allocation bound. Payload window and
        // digest-table mappings have independent exact charges.
        let controls = try budget.reserve(64 * 1024, as: .metadata)
        var fullHash = SHA256()
        let hashes = try DICOMByteBuffer(count: blocks * SHA256.byteCount,
                                        budget: budget, resource: .metadata) { table in
            for block in 0..<blocks {
                try Task.checkCancellation()
                let start = block * Self.blockBytes
                let length = min(Self.blockBytes, count - start)
                let window = try Self.readBlock(fd, start: start, length: length, budget: budget, hooks: hooks)
                window.withUnsafeBytes { bytes in
                    fullHash.update(bufferPointer: bytes)
                    var blockHash = SHA256(); blockHash.update(bufferPointer: bytes)
                    blockHash.finalize().withUnsafeBytes { digest in
                        if let target = table.baseAddress, let source = digest.baseAddress {
                            target.advanced(by: block * SHA256.byteCount)
                                .copyMemory(from: source, byteCount: SHA256.byteCount)
                        }
                    }
                }
                try hooks.stage?(.capturedBlock(block))
            }
        }
        var probe: UInt8 = 0
        var extra: Int
        repeat {
            try Task.checkCancellation()
            extra = hooks.read(fd, &probe, 1, off_t(count))
        } while extra < 0 && errno == EINTR
        guard extra >= 0 else { throw VerifiedSourceError.readFailed }
        guard extra == 0 else { throw VerifiedSourceError.sourceChanged }
        try hooks.stage?(.beforeVerification)
        try Task.checkCancellation()
        guard try Self.descriptorFingerprint(fd) == initial else { throw VerifiedSourceError.sourceChanged }
        if let path, try Self.pathFingerprint(path) != initial { throw VerifiedSourceError.sourceChanged }
        self.descriptor = fd; self.path = path; self.fingerprint = initial
        self.count = count; self.hashes = hashes; self.budget = budget; self.hooks = hooks
        self.controlLease = controls
        self.identity = withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 64) { hex in
            var position = 0
            for byte in fullHash.finalize() {
                let high = byte >> 4, low = byte & 15
                hex[position] = high < 10 ? 48 + high : 87 + high
                hex[position + 1] = low < 10 ? 48 + low : 87 + low
                position += 2
            }
            return String(decoding: hex, as: UTF8.self)
        }
        acquired = true
    }
    deinit { _ = Darwin.close(descriptor) }

    /// Validate before publishing a parse/frame result. A detected source error
    /// permanently invalidates this source, including all retained views.
    public func validate() throws {
        try Task.checkCancellation()
        lock.lock(); let wasInvalid = invalid; lock.unlock()
        guard !wasInvalid else { throw VerifiedSourceError.sourceChanged }
        do {
            guard try Self.descriptorFingerprint(descriptor) == fingerprint else {
                throw VerifiedSourceError.sourceChanged
            }
            if let path, try Self.pathFingerprint(path) != fingerprint { throw VerifiedSourceError.sourceChanged }
            try Task.checkCancellation()
        } catch {
            if error is VerifiedSourceError { invalidate() }
            throw error
        }
    }

    /// Acquire an immutable, independently charged range. The window charge
    /// overlaps this destination charge until every verified copy has completed.
    /// - Parameters:
    ///   - range: Absolute source byte range.
    ///   - resource: Allocation class for the returned payload.
    /// - Returns: Immutable bytes matching the captured source identity.
    public func read(_ range: Range<Int>, resource: DICOMAllocationClass = .encoded) throws -> DICOMByteBuffer {
        try validateRange(range)
        try validate()
        let result = try DICOMByteBuffer(count: range.count, budget: budget, resource: resource) { destination in
            try copy(range, to: destination)
        }
        try validate()
        return result
    }

    /// Nonescaping copy into already-admitted storage. The same verified
    /// block supplies the copied bytes; there is no verification/reread gap.
    /// - Parameters:
    ///   - range: Absolute source byte range.
    ///   - destination: Caller-admitted storage whose count exactly matches the range.
    public func copy(_ range: Range<Int>, to destination: UnsafeMutableRawBufferPointer) throws {
        try validateRange(range)
        guard destination.count == range.count else { throw VerifiedSourceError.invalidRange }
        try validate()
        do {
            var position = range.lowerBound
            while position < range.upperBound {
                try Task.checkCancellation()
                let block = position / Self.blockBytes
                let start = block * Self.blockBytes
                let length = min(Self.blockBytes, count - start)
                let window = try verifiedBlock(block)
                try window.withUnsafeBytes { bytes in
                    try Task.checkCancellation()
                    let copied = min(range.upperBound - position, length - (position - start))
                    if let target = destination.baseAddress, let source = bytes.baseAddress {
                        target.advanced(by: position - range.lowerBound)
                            .copyMemory(from: source.advanced(by: position - start), byteCount: copied)
                    }
                    position += copied
                }
            }
            try validate()
        } catch {
            if error is VerifiedSourceError { invalidate() }
            throw error
        }
    }

    /// A cursor retains this immutable block through all scalar reads. Refill
    /// creates a new independently charged window, never a mutable alias.
    func verifiedBlock(_ block: Int) throws -> DICOMByteBuffer {
        guard block >= 0, block < (count + Self.blockBytes - 1) / Self.blockBytes else {
            throw VerifiedSourceError.invalidRange
        }
        try validate()
        do {
            let start = block * Self.blockBytes
            let window = try Self.readBlock(descriptor, start: start,
                length: min(Self.blockBytes, count - start), budget: budget, hooks: hooks)
            let matches = window.withUnsafeBytes { bytes in
                var hash = SHA256(); hash.update(bufferPointer: bytes)
                return hash.finalize().withUnsafeBytes { digest in
                    hashes.withUnsafeBytes { table in
                        UnsafeRawBufferPointer(rebasing: table[block * SHA256.byteCount..<(block + 1) * SHA256.byteCount])
                            .elementsEqual(digest)
                    }
                }
            }
            guard matches else { throw VerifiedSourceError.sourceChanged }
            try hooks.stage?(.verifiedBlock(block))
            try validate()
            return window
        } catch {
            if error is VerifiedSourceError { invalidate() }
            throw error
        }
    }

    /// Legacy unbudgeted bridges are intentionally unavailable on verified sources.
    /// Use `read(_:resource:)` so ownership and potential copies remain explicit.
    public func bytes(in range: Range<Int>) throws -> Data { throw VerifiedSourceError.unbudgetedReadUnsupported }
    /// Refuse an unbudgeted whole-source copy; acquire explicit verified ranges instead.
    public func wholeData() throws -> Data { throw VerifiedSourceError.unbudgetedReadUnsupported }

    private func invalidate() { lock.lock(); invalid = true; lock.unlock() }
    private func validateRange(_ range: Range<Int>) throws {
        guard range.lowerBound >= 0, range.upperBound <= count else { throw VerifiedSourceError.invalidRange }
    }
    private static func readBlock(_ fd: Int32, start: Int, length: Int,
                                  budget: DICOMAllocationBudget, hooks: Hooks) throws -> DICOMByteBuffer {
        try DICOMByteBuffer(count: length, budget: budget, resource: .encoded) { bytes in
            var done = 0
            while done < length {
                try Task.checkCancellation()
                let amount = hooks.read(fd, bytes.baseAddress?.advanced(by: done), length - done, off_t(start + done))
                if amount < 0 {
                    if errno == EINTR { continue }
                    throw VerifiedSourceError.readFailed
                }
                guard amount > 0, amount <= length - done else { throw VerifiedSourceError.sourceChanged }
                done += amount
            }
        }
    }
    private static func descriptorFingerprint(_ fd: Int32) throws -> Fingerprint {
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw VerifiedSourceError.readFailed }
        return Fingerprint(info)
    }
    private static func pathFingerprint(_ path: String) throws -> Fingerprint {
        var info = stat()
        guard path.withCString({ lstat($0, &info) }) == 0 else { throw VerifiedSourceError.sourceChanged }
        return Fingerprint(info)
    }
}
#endif
