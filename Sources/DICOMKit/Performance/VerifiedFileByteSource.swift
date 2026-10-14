// NEMA-verified: 2026a, checked 2026-10-14 — no DICOM-standard data (verified file I/O).
#if canImport(Darwin) || canImport(Glibc)
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import DICOMCore

/// Legacy error names retained for source compatibility of diagnostics.
public enum VerifiedSourceError: Error, Equatable, Sendable {
    case invalidOptions, notRegularFile, sizeLimit, readFailed, sourceChanged
    case invalidRange, unbudgetedReadUnsupported
}

/// Anchored, immutable file transcript with admitted control, path and digest storage.
/// Aliases explicitly share the same mapped owner. Every later acquisition verifies
/// complete blocks and copies those same bytes; no verification/reread gap exists.
public struct VerifiedFileByteSource: ~Copyable, @unchecked Sendable {
    /// Largest admitted source; this is independent of simultaneous encoded storage.
    public static let maximumSourceBytes = 256 * 1024 * 1024
    /// Fixed hashing/verification window.
    public static let blockBytes = 64 * 1024
    private let storage: DICOMByteBuffer
    var view: VerifiedSourceView {
        guard let base = storage.unsafeMutableBytes.baseAddress else { preconditionFailure("Missing source backing") }
        return VerifiedSourceView(base: base, cancellation: .never)
    }
    /// Complete source length.
    public var count: Int { view.count }
    /// SHA-256 of the complete captured byte transcript, retained without a String.
    public var identity: DICOMContentDigest { view.header.pointee.identity }
    /// Snapshot including all allocations sharing this ledger.
    public var allocationReceipt: DICOMAllocationReceipt { view.header.pointee.budget.receipt }

    /// Explicit alias; the file descriptor and all backing remain alive until the last alias dies.
    public borrowing func share() throws(DICOMManagedFailure) -> Self {
        try shareOutcome().get()
    }
    private init(storage: consuming DICOMByteBuffer) { self.storage = storage }
    /// Retain this source with scalar status and no throwing-runtime call.
    /// - Returns: An alias retaining its descriptor and all admitted metadata, or refusal.
    public borrowing func shareOutcome() -> DICOMManagedOutcome<Self> {
        switch storage.managedShareOutcome() {
        case .success(let owner): return .success(Self(storage: owner))
        case .failure(let failure): return .failure(failure)
        }
    }


    /// Compatibility URL adapter. URL/path conversion is a caller-side Foundation
    /// operation; use `capture(path:budget:execution:maximumBytes:cancellation:)` for the admitted boundary.
    public init(url: URL, budget: borrowing DICOMAllocationBudget,
                maximumBytes: Int = maximumSourceBytes,
                cancellation: DICOMCancellation = .never) throws {
        guard url.isFileURL else { throw DICOMManagedFailure(.invalidOptions) }
        let path = url.path
        guard !path.utf8.contains(0) else { throw DICOMManagedFailure(.invalidOptions) }
        var result: Self?
        try path.withCString { pointer in
            result = try Self(path: UnsafeBufferPointer(start: pointer, count: strlen(pointer) + 1),
                              budget: budget, maximumBytes: maximumBytes, cancellation: cancellation)
        }
        guard let value = consume result else { throw DICOMManagedFailure(.invalidOptions) }
        self = value
    }

    /// Open a caller-owned NUL-terminated path without following a final symlink.
    /// Copies and admits the complete path before opening; its bytes must remain
    /// stable only for this synchronous call. No Foundation path conversion occurs.
    public init(path: UnsafeBufferPointer<CChar>, budget: borrowing DICOMAllocationBudget,
                maximumBytes: Int = maximumSourceBytes,
                cancellation: DICOMCancellation = .never) throws(DICOMManagedFailure) {
        try self.init(path: path, descriptor: nil, budget: budget, maximumBytes: maximumBytes,
                      cancellation: cancellation, hooks: Hooks())
    }

    /// Capture a source on a worker whose complete stack is already admitted.
    /// Retain `execution` through the complete synchronous parse/acquisition/decode
    /// operation, including failure and cancellation. The path and cancellation
    /// context are borrowed caller inputs; they must remain valid during this call.
    @available(*, noasync, message: "Qualified input must remain on its admitted synchronous worker")
    public init(path: UnsafeBufferPointer<CChar>, budget: borrowing DICOMAllocationBudget,
                execution: borrowing DICOMExecutionReservation, maximumBytes: Int = maximumSourceBytes,
                cancellation: DICOMCancellation = .never) throws(DICOMManagedFailure) {
        self = try Self.capture(path: path, budget: budget, execution: execution,
                                maximumBytes: maximumBytes, cancellation: cancellation).get()
    }

    /// Duplicate a source descriptor on a worker whose complete stack is admitted.
    /// Retain the reservation until the entire synchronous operation returns.
    @available(*, noasync, message: "Qualified input must remain on its admitted synchronous worker")
    public init(descriptor: Int32, budget: borrowing DICOMAllocationBudget,
                execution: borrowing DICOMExecutionReservation, maximumBytes: Int = maximumSourceBytes,
                cancellation: DICOMCancellation = .never) throws(DICOMManagedFailure) {
        self = try Self.capture(descriptor: descriptor, budget: budget, execution: execution,
                                maximumBytes: maximumBytes, cancellation: cancellation).get()
    }

    /// Validate the current worker against this source's retained allocation ledger.
    @available(*, noasync, message: "Qualified input must remain on its admitted synchronous worker")
    public func validateExecution(_ execution: borrowing DICOMExecutionReservation) throws(DICOMManagedFailure) {
        try validateExecutionOutcome(execution).get()
    }

    /// Duplicate a caller-owned descriptor; pread never changes its file offset.
    public init(descriptor: Int32, budget: borrowing DICOMAllocationBudget,
                maximumBytes: Int = maximumSourceBytes,
                cancellation: DICOMCancellation = .never) throws(DICOMManagedFailure) {
        try self.init(path: UnsafeBufferPointer(start: nil, count: 0), descriptor: descriptor,
                      budget: budget, maximumBytes: maximumBytes, cancellation: cancellation, hooks: Hooks())
    }

    /// Test callbacks are thin functions with a caller-owned context. Their storage,
    /// behavior are outside the library's admitted implementation. Unlike operation
    /// cancellation, this internal test context must outlive every source alias.
    struct Hooks: @unchecked Sendable {
        var context: UnsafeMutableRawPointer? = nil
        var stage: (@convention(c) (UnsafeMutableRawPointer?, Int, Int) -> Int32)? = nil
        var read: (@convention(c) (UnsafeMutableRawPointer?, Int32, UnsafeMutableRawPointer?, Int, off_t) -> Int)? = nil
    }

    init(path: UnsafeBufferPointer<CChar>, descriptor: Int32?, budget: borrowing DICOMAllocationBudget,
         maximumBytes: Int, cancellation: DICOMCancellation, hooks: Hooks) throws(DICOMManagedFailure) {
        self = try Self.capture(path: path, descriptor: descriptor, budget: budget,
            maximumBytes: maximumBytes, cancellation: cancellation, hooks: hooks).get()
    }

    static func capture(path: UnsafeBufferPointer<CChar>, descriptor: Int32?, budget: borrowing DICOMAllocationBudget,
         maximumBytes: Int, cancellation: DICOMCancellation, hooks: Hooks) -> DICOMManagedOutcome<Self> {
        if let failure = cancellation.failure { return .failure(failure) }
        guard maximumBytes >= 0, maximumBytes <= Self.maximumSourceBytes else {
            return .failure(DICOMManagedFailure(.invalidOptions))
        }
        if descriptor == nil {
            guard path.count > 1, path[path.count - 1] == 0 else {
                return .failure(DICOMManagedFailure(.invalidOptions))
            }
            for i in 0..<(path.count - 1) where path[i] == 0 { return .failure(DICOMManagedFailure(.invalidOptions)) }
        }
        // The path is admitted before any persistent copy. The full digest table is
        // bounded by the source envelope; its exact logical length is set after stat.
        var failure = DICOMManagedFailure(.invalidOptions)
        guard let pathOwner = DICOMByteBuffer.admit(count: path.count, budget: budget, resource: .metadata)
            .takeValue(failure: &failure) else { return .failure(failure) }
        if path.count > 0 {
            pathOwner.unsafeMutableBytes.copyMemory(from: UnsafeRawBufferPointer(path))
        }
        let expected: SourceFingerprint?
        let fd: Int32
        if let descriptor {
            expected = nil
            fd = fcntl(descriptor, F_DUPFD_CLOEXEC, 0)
        } else {
            guard let value = SourceFingerprint.path(pathOwner.unsafeMutableBytes.baseAddress)
                .takeValue(failure: &failure) else { return .failure(failure) }
            expected = value
            guard (expected?.mode ?? 0) & S_IFMT == S_IFREG else {
                return .failure(DICOMManagedFailure(.notRegularFile))
            }
            guard let pathBase = pathOwner.unsafeMutableBytes.baseAddress else {
                return .failure(DICOMManagedFailure(.invalidOptions))
            }
            fd = open(pathBase.assumingMemoryBound(to: CChar.self),
                             O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        }
        guard fd >= 0 else { return .failure(DICOMManagedFailure(.readFailed)) }
        var accepted = false
        defer { if !accepted { _ = close(fd) } }
        guard let initial = SourceFingerprint.descriptor(fd).takeValue(failure: &failure) else {
            return .failure(failure)
        }
        guard initial.mode & S_IFMT == S_IFREG else { return .failure(DICOMManagedFailure(.notRegularFile)) }
        guard expected == nil || initial == expected else { return .failure(DICOMManagedFailure(.sourceChanged)) }
        guard initial.size >= 0, initial.size <= maximumBytes else { return .failure(DICOMManagedFailure(.sizeLimit)) }
        let count = Int(initial.size), blocks = (count + Self.blockBytes - 1) / Self.blockBytes
        let digestOffset = MemoryLayout<VerifiedSourceHeader>.stride
        let digestEnd = digestOffset + blocks * 32
        let pathOffset = digestEnd
        guard path.count <= Int.max - pathOffset else { return .failure(DICOMManagedFailure(.invalidOptions)) }
        guard let owner = DICOMByteBuffer.admit(count: pathOffset + path.count, budget: budget, resource: .metadata)
            .takeValue(failure: &failure) else { return .failure(failure) }
        let bytes = owner.unsafeMutableBytes
        guard let base = bytes.baseAddress else { return .failure(DICOMManagedFailure(.invalidOptions)) }
        if path.count > 0 {
            UnsafeMutableRawBufferPointer(rebasing: bytes[pathOffset..<bytes.count])
                .copyMemory(from: UnsafeRawBufferPointer(pathOwner.unsafeMutableBytes))
        }
        var full = BoundedSHA256()
        for block in 0..<blocks {
            if let failure = cancellation.failure { return .failure(failure) }
            let start = block * Self.blockBytes
            guard let window = VerifiedSourceView.readBlock(fd, start: start,
                length: min(Self.blockBytes, count - start), budget: budget, cancellation: cancellation, hooks: hooks)
                .takeValue(failure: &failure) else { return .failure(failure) }
            window.withBorrowedBytes { input in
                full.update(input)
                var hash = BoundedSHA256(); hash.update(input)
                hash.finalize().write(to: UnsafeMutableRawBufferPointer(rebasing: bytes[
                    digestOffset + block * 32..<digestOffset + (block + 1) * 32]))
            }
            if case .failure(let failure) = VerifiedSourceView.callHook(hooks, stage: 0, operand: block) {
                return .failure(failure)
            }
        }
        var probe: UInt8 = 0
        var extra: Int
        repeat {
            if let failure = cancellation.failure { return .failure(failure) }
            extra = VerifiedSourceView.pread(hooks, fd, &probe, 1, off_t(count))
        } while extra < 0 && errno == EINTR
        guard extra >= 0 else { return .failure(DICOMManagedFailure(.readFailed)) }
        guard extra == 0 else { return .failure(DICOMManagedFailure(.sourceChanged)) }
        if case .failure(let failure) = VerifiedSourceView.callHook(hooks, stage: 1, operand: 0) {
            return .failure(failure)
        }
        if let failure = cancellation.failure { return .failure(failure) }
        guard let finalFingerprint = SourceFingerprint.descriptor(fd).takeValue(failure: &failure) else {
            return .failure(failure)
        }
        guard finalFingerprint == initial else { return .failure(DICOMManagedFailure(.sourceChanged)) }
        if path.count > 0 {
            guard let finalPath = SourceFingerprint.path(base.advanced(by: pathOffset))
                .takeValue(failure: &failure) else {
                return .failure(failure)
            }
            guard finalPath == initial else { return .failure(DICOMManagedFailure(.sourceChanged)) }
        }
        guard let retainedBudget = budget.managedShareOutcome().takeValue(failure: &failure) else {
            return .failure(failure)
        }
        let header = base.bindMemory(to: VerifiedSourceHeader.self, capacity: 1)
        header.initialize(to: VerifiedSourceHeader(descriptor: fd, count: count, fingerprint: initial,
            identity: full.finalize(), digestOffset: digestOffset, pathOffset: pathOffset, pathCount: path.count,
            budget: retainedBudget, hooks: hooks))
        guard pthread_mutex_init(&header.pointee.mutex, nil) == 0 else {
            header.deinitialize(count: 1); return .failure(DICOMManagedFailure(allocation: .synchronizationFailed))
        }
        let finalizerStatus = owner.installFinalizerOutcome { pointer, _ in
            guard let pointer else { return }
            let h = pointer.assumingMemoryBound(to: VerifiedSourceHeader.self)
            _ = close(h.pointee.descriptor)
            _ = pthread_mutex_destroy(&h.pointee.mutex)
            h.deinitialize(count: 1)
        }
        if case .failure(let error) = finalizerStatus {
            _ = pthread_mutex_destroy(&header.pointee.mutex)
            header.deinitialize(count: 1)
            return .failure(DICOMManagedFailure(allocation: error))
        }
        accepted = true
        return .success(Self(storage: owner))
    }

    /// Recheck the anchored source; invalidation is sticky across all aliases.
    public func validate(cancellation: DICOMCancellation = .never) throws(DICOMManagedFailure) {
        try validateOutcome(cancellation: cancellation).get()
    }
    /// Acquire one independently admitted verified range.
    public func read(_ range: Range<Int>, resource: DICOMAllocationClass = .encoded,
                     cancellation: DICOMCancellation = .never) throws(DICOMManagedFailure) -> DICOMByteBuffer {
        try readOutcome(range, resource: resource, cancellation: cancellation).get()
    }
    /// Copy the same verified bytes into caller-admitted storage.
    public func copy(_ range: Range<Int>, to destination: UnsafeMutableRawBufferPointer,
                     cancellation: DICOMCancellation = .never) throws(DICOMManagedFailure) {
        try copyOutcome(range, to: destination, cancellation: cancellation).get()
    }

    /// Capture a caller-owned path with scalar failure status.
    /// - Parameters:
    ///   - path: Stable NUL-terminated bytes borrowed until this call returns.
    ///   - budget: Ledger admitting all persistent and temporary source storage.
    ///   - maximumBytes: Source envelope, at most `maximumSourceBytes`.
    ///   - cancellation: Caller-owned synchronous cancellation observer.
    /// - Returns: An anchored verified source or scalar refusal after complete cleanup.
    public static func capture(path: UnsafeBufferPointer<CChar>, budget: borrowing DICOMAllocationBudget,
        maximumBytes: Int = maximumSourceBytes, cancellation: DICOMCancellation = .never) -> DICOMManagedOutcome<Self> {
        capture(path: path, descriptor: nil, budget: budget, maximumBytes: maximumBytes,
                cancellation: cancellation, hooks: Hooks())
    }

    /// Capture a duplicated descriptor using scalar status; the caller's offset is unchanged.
    /// - Parameters:
    ///   - descriptor: Borrowed open regular-file descriptor, valid until capture returns.
    ///   - budget: Admission ledger.
    ///   - maximumBytes: Maximum accepted source length.
    ///   - cancellation: Caller-owned synchronous cancellation observer.
    /// - Returns: An independently owned descriptor/transcript, or scalar failure.
    public static func capture(descriptor: Int32, budget: borrowing DICOMAllocationBudget,
        maximumBytes: Int = maximumSourceBytes, cancellation: DICOMCancellation = .never) -> DICOMManagedOutcome<Self> {
        capture(path: UnsafeBufferPointer(start: nil, count: 0), descriptor: descriptor, budget: budget,
                maximumBytes: maximumBytes, cancellation: cancellation, hooks: Hooks())
    }

    /// Capture a path on its validated, explicitly admitted synchronous worker.
    /// - Parameters:
    ///   - path: Borrowed NUL-terminated caller bytes.
    ///   - budget: Shared operation ledger.
    ///   - execution: Stack reservation retained through actual worker return.
    ///   - maximumBytes: Maximum accepted source length.
    ///   - cancellation: Borrowed synchronous cancellation observer.
    /// - Returns: A verified source or scalar worker/source failure.
    @available(*, noasync, message: "Qualified input must remain on its admitted synchronous worker")
    public static func capture(path: UnsafeBufferPointer<CChar>, budget: borrowing DICOMAllocationBudget,
        execution: borrowing DICOMExecutionReservation, maximumBytes: Int = maximumSourceBytes,
        cancellation: DICOMCancellation = .never) -> DICOMManagedOutcome<Self> {
        if case .failure(let failure) = execution.validateOutcome(budget: budget) {
            return .failure(DICOMManagedFailure(allocation: failure))
        }
        return capture(path: path, budget: budget, maximumBytes: maximumBytes, cancellation: cancellation)
    }

    /// Capture a descriptor on its validated, explicitly admitted synchronous worker.
    /// - Parameters:
    ///   - descriptor: Borrowed open descriptor.
    ///   - budget: Shared operation ledger.
    ///   - execution: Whole-stack reservation retained through actual worker return.
    ///   - maximumBytes: Maximum accepted source length.
    ///   - cancellation: Borrowed synchronous cancellation observer.
    /// - Returns: A verified source or scalar worker/source failure.
    @available(*, noasync, message: "Qualified input must remain on its admitted synchronous worker")
    public static func capture(descriptor: Int32, budget: borrowing DICOMAllocationBudget,
        execution: borrowing DICOMExecutionReservation, maximumBytes: Int = maximumSourceBytes,
        cancellation: DICOMCancellation = .never) -> DICOMManagedOutcome<Self> {
        if case .failure(let failure) = execution.validateOutcome(budget: budget) {
            return .failure(DICOMManagedFailure(allocation: failure))
        }
        return capture(descriptor: descriptor, budget: budget, maximumBytes: maximumBytes, cancellation: cancellation)
    }

    /// Validate the retained ledger and current worker without invoking throwing runtime.
    /// - Parameter execution: Original synchronous worker reservation.
    /// - Returns: Success or scalar identity/query failure.
    @available(*, noasync, message: "Validate on the original admitted worker")
    public func validateExecutionOutcome(_ execution: borrowing DICOMExecutionReservation)
        -> DICOMManagedOutcome<Void> {
        switch execution.validateOutcome(budget: view.header.pointee.budget) {
        case .success: return .success(())
        case .failure(let failure): return .failure(DICOMManagedFailure(allocation: failure))
        }
    }

    /// Recheck the anchored source using scalar status; invalidation remains sticky across aliases.
    /// - Parameter cancellation: Observer borrowed for this synchronous call only.
    /// - Returns: Success or a fixed cancellation/source failure.
    public func validateOutcome(cancellation: DICOMCancellation = .never) -> DICOMManagedOutcome<Void> {
        view.withCancellation(cancellation).validate()
    }

    /// Acquire verified bytes into independently admitted storage using scalar status.
    /// - Parameters:
    ///   - range: Valid source-relative byte range.
    ///   - resource: Allocation class for the result.
    ///   - cancellation: Observer borrowed until actual return.
    /// - Returns: Same-transcript bytes or a scalar failure after temporary cleanup.
    public func readOutcome(_ range: Range<Int>, resource: DICOMAllocationClass = .encoded,
        cancellation: DICOMCancellation = .never) -> DICOMManagedOutcome<DICOMByteBuffer> {
        view.withCancellation(cancellation).read(range, resource: resource)
    }

    /// Copy the same verified bytes into caller-admitted storage using scalar status.
    /// - Parameters:
    ///   - range: Valid source-relative byte range.
    ///   - destination: Caller-owned admitted storage matching the range length.
    ///   - cancellation: Observer borrowed until actual return.
    /// - Returns: Success or a scalar failure; partial destination bytes must not be published after failure.
    public func copyOutcome(_ range: Range<Int>, to destination: UnsafeMutableRawBufferPointer,
        cancellation: DICOMCancellation = .never) -> DICOMManagedOutcome<Void> {
        view.withCancellation(cancellation).copy(range, to: destination)
    }

}

private struct SourceFingerprint: Equatable {
    let device: dev_t, inode: ino_t, mode: mode_t, size: off_t
    let modifiedSeconds: Int, modifiedNanos: Int, changedSeconds: Int, changedNanos: Int
    init(_ value: stat) {
        device = value.st_dev; inode = value.st_ino; mode = value.st_mode; size = value.st_size
        #if canImport(Darwin)
        modifiedSeconds = value.st_mtimespec.tv_sec; modifiedNanos = value.st_mtimespec.tv_nsec
        changedSeconds = value.st_ctimespec.tv_sec; changedNanos = value.st_ctimespec.tv_nsec
        #else
        modifiedSeconds = value.st_mtim.tv_sec; modifiedNanos = value.st_mtim.tv_nsec
        changedSeconds = value.st_ctim.tv_sec; changedNanos = value.st_ctim.tv_nsec
        #endif
    }
    static func descriptor(_ fd: Int32) -> DICOMManagedOutcome<Self> {
        var value = stat()
        guard fstat(fd, &value) == 0 else { return .failure(DICOMManagedFailure(.readFailed)) }
        return .success(Self(value))
    }
    static func path(_ pointer: UnsafeRawPointer?) -> DICOMManagedOutcome<Self> {
        guard let pointer else { return .failure(DICOMManagedFailure(.invalidOptions)) }
        var value = stat()
        guard lstat(pointer.assumingMemoryBound(to: CChar.self), &value) == 0 else {
            return .failure(DICOMManagedFailure(.sourceChanged))
        }
        return .success(Self(value))
    }
}

private struct VerifiedSourceHeader: ~Copyable {
    let descriptor: Int32, count: Int
    let fingerprint: SourceFingerprint
    let identity: DICOMContentDigest
    let digestOffset: Int, pathOffset: Int, pathCount: Int
    let budget: DICOMAllocationBudget
    let hooks: VerifiedFileByteSource.Hooks
    var mutex = pthread_mutex_t()
    var invalid = false
}

/// Internal non-owning view. Its owner is retained by the enclosing source/index;
/// this view never escapes a public operation or replaces the owning handle.
struct VerifiedSourceView {
    let base: UnsafeMutableRawPointer
    let cancellation: DICOMCancellation
    func withCancellation(_ cancellation: DICOMCancellation) -> Self {
        Self(base: base, cancellation: cancellation)
    }
    fileprivate var header: UnsafeMutablePointer<VerifiedSourceHeader> {
        base.assumingMemoryBound(to: VerifiedSourceHeader.self)
    }
    var count: Int { header.pointee.count }
    var identity: DICOMContentDigest { header.pointee.identity }
    var receipt: DICOMAllocationReceipt { header.pointee.budget.receipt }
    func withBorrowedBudget<R: ~Copyable>(_ body: (borrowing DICOMAllocationBudget) -> R) -> R {
        body(header.pointee.budget)
    }
    func validate() -> DICOMManagedOutcome<Void> {
        if let failure = cancellation.failure { return .failure(failure) }
        pthread_mutex_lock(&header.pointee.mutex)
        let invalid = header.pointee.invalid
        pthread_mutex_unlock(&header.pointee.mutex)
        guard !invalid else { return .failure(DICOMManagedFailure(.sourceChanged)) }
        var failure = DICOMManagedFailure(.sourceChanged)
        guard let fingerprint = SourceFingerprint.descriptor(header.pointee.descriptor)
            .takeValue(failure: &failure) else {
            invalidate()
            return .failure(failure)
        }
        guard fingerprint == header.pointee.fingerprint else {
            invalidate()
            return .failure(DICOMManagedFailure(.sourceChanged))
        }
        if header.pointee.pathCount > 0 {
            guard let pathFingerprint = SourceFingerprint.path(base.advanced(by: header.pointee.pathOffset))
                .takeValue(failure: &failure) else {
                invalidate()
                return .failure(failure)
            }
            guard pathFingerprint == header.pointee.fingerprint else {
                invalidate()
                return .failure(DICOMManagedFailure(.sourceChanged))
            }
        }
        if let failure = cancellation.failure { return .failure(failure) }
        return .success(())
    }
    private func invalidate() {
        pthread_mutex_lock(&header.pointee.mutex); header.pointee.invalid = true
        pthread_mutex_unlock(&header.pointee.mutex)
    }
    private func readFailure<Value: ~Copyable>(_ failure: DICOMManagedFailure) -> DICOMManagedOutcome<Value> {
        if failure.code == .readFailed || failure.code == .sourceChanged { invalidate() }
        return .failure(failure)
    }
    func read(_ range: Range<Int>, resource: DICOMAllocationClass) -> DICOMManagedOutcome<DICOMByteBuffer> {
        if let failure = validateRange(range) { return .failure(failure) }
        if case .failure(let failure) = validate() { return .failure(failure) }
        var failure = DICOMManagedFailure(.invalidOptions)
        guard let output = DICOMByteBuffer.admit(count: range.count, budget: header.pointee.budget, resource: resource)
            .takeValue(failure: &failure) else { return .failure(failure) }
        if case .failure(let failure) = copy(range, to: output.unsafeMutableBytes) { return .failure(failure) }
        if case .failure(let failure) = validate() { return .failure(failure) }
        return .success(output)
    }
    func copy(_ range: Range<Int>, to destination: UnsafeMutableRawBufferPointer) -> DICOMManagedOutcome<Void> {
        if let failure = validateRange(range) { return .failure(failure) }
        guard range.count == destination.count else { return .failure(DICOMManagedFailure(.invalidRange)) }
        if case .failure(let failure) = validate() { return .failure(failure) }
        var failure = DICOMManagedFailure(.invalidOptions)
        var position = range.lowerBound
        while position < range.upperBound {
            let block = position / VerifiedFileByteSource.blockBytes
            let start = block * VerifiedFileByteSource.blockBytes
            guard let window = verifiedBlock(block).takeValue(failure: &failure) else {
                return readFailure(failure)
            }
            window.withBorrowedBytes { bytes in
                let copied = min(range.upperBound - position, bytes.count - (position - start))
                if let target = destination.baseAddress, let source = bytes.baseAddress {
                    target.advanced(by: position - range.lowerBound)
                        .copyMemory(from: source.advanced(by: position - start), byteCount: copied)
                }
                position += copied
            }
        }
        if case .failure(let failure) = validate() { return readFailure(failure) }
        return .success(())
    }
    func verifiedBlock(_ block: Int) -> DICOMManagedOutcome<DICOMByteBuffer> {
        let blockCount = (count + VerifiedFileByteSource.blockBytes - 1) / VerifiedFileByteSource.blockBytes
        guard block >= 0, block < blockCount else {
            return .failure(DICOMManagedFailure(.invalidRange))
        }
        if case .failure(let failure) = validate() { return .failure(failure) }
        let start = block * VerifiedFileByteSource.blockBytes
        var failure = DICOMManagedFailure(.invalidOptions)
        guard let window = Self.readBlock(header.pointee.descriptor, start: start,
            length: min(VerifiedFileByteSource.blockBytes, count - start), budget: header.pointee.budget,
            cancellation: cancellation, hooks: header.pointee.hooks).takeValue(failure: &failure) else {
            return readFailure(failure)
        }
        let matches = window.withBorrowedBytes { bytes in
            var hash = BoundedSHA256(); hash.update(bytes)
            return hash.finalize().matches(UnsafeRawBufferPointer(
                start: base.advanced(by: header.pointee.digestOffset + block * 32), count: 32))
        }
        guard matches else { return readFailure(DICOMManagedFailure(.sourceChanged)) }
        if case .failure(let failure) = Self.callHook(header.pointee.hooks, stage: 2, operand: block) {
            return readFailure(failure)
        }
        if case .failure(let failure) = validate() { return readFailure(failure) }
        return .success(window)
    }
    private func validateRange(_ range: Range<Int>) -> DICOMManagedFailure? {
        guard range.lowerBound >= 0, range.upperBound <= count else { return DICOMManagedFailure(.invalidRange) }
        return nil
    }
    static func readBlock(_ fd: Int32, start: Int, length: Int, budget: borrowing DICOMAllocationBudget,
        cancellation: DICOMCancellation, hooks: VerifiedFileByteSource.Hooks) -> DICOMManagedOutcome<DICOMByteBuffer> {
        var failure = DICOMManagedFailure(.invalidOptions)
        guard let buffer = DICOMByteBuffer.admit(count: length, budget: budget, resource: .encoded)
            .takeValue(failure: &failure) else { return .failure(failure) }
        let bytes = buffer.unsafeMutableBytes
        var done = 0
        while done < length {
            if let failure = cancellation.failure { return .failure(failure) }
            let amount = pread(hooks, fd, bytes.baseAddress?.advanced(by: done), length - done, off_t(start + done))
            if amount < 0 {
                if errno == EINTR { continue }
                return .failure(DICOMManagedFailure(.readFailed))
            }
            guard amount > 0, amount <= length - done else { return .failure(DICOMManagedFailure(.sourceChanged)) }
            done += amount
        }
        return .success(buffer)
    }
    static func pread(_ hooks: VerifiedFileByteSource.Hooks, _ fd: Int32,
                      _ bytes: UnsafeMutableRawPointer?, _ count: Int, _ offset: off_t) -> Int {
        if let read = hooks.read { return read(hooks.context, fd, bytes, count, offset) }
        #if canImport(Darwin)
        return Darwin.pread(fd, bytes, count, offset)
        #else
        return Glibc.pread(fd, bytes, count, offset)
        #endif
    }
    static func callHook(_ hooks: VerifiedFileByteSource.Hooks, stage: Int, operand: Int) -> DICOMManagedOutcome<Void> {
        if hooks.stage?(hooks.context, stage, operand) ?? 0 != 0 { return .failure(DICOMManagedFailure(.readFailed)) }
        return .success(())
    }
}
#endif
