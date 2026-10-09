// UnifiedMemoryPool.swift
// DICOMRenderKit — GPU_RENDERING_PLAN.md milestone M2b / design pillar 2
//
// Where "no pixel buffer is ever copied" is actually implemented — and counted, so
// the claim can be asserted by a test instead of trusted.
//
// NEMA-verified: 2026a, checked 2026-09-30 — carries no DICOM-standard data (buffer pooling and zero-copy wrapping). C1 classification confirmed.

import Foundation
import DICOMCore

#if canImport(Metal)
import Metal

/// Hands out `MTLBuffer`s for frame input and render output without copying pixel
/// data, and without allocating in the steady state.
///
/// Two jobs:
///
/// 1. **Input, zero copy.** A `PixelData` carrying page-aligned storage is wrapped
///    with `makeBuffer(bytesNoCopy:)`, so the GPU reads the CPU's own decoded
///    frame. Unaligned input falls back to a pooled buffer and one `memcpy` —
///    correctness never depends on the alignment succeeding.
/// 2. **Output, pooled.** Render targets are reused per size, so a window drag
///    allocates nothing after its first frame.
///
/// All storage is `.storageModeShared`. On Apple Silicon that is coherent at
/// command-buffer boundaries: no `didModifyRange`, no `synchronize(resource:)`, no
/// blit encoder. Those are `.storageModeManaged` concerns and `.managed` does not
/// exist on this hardware — porting that ceremony in from generic Metal samples
/// would be pure overhead.
///
/// The plan proposed sub-allocating from an `MTLHeap`. A size-keyed free list is
/// used instead: reuse is equally free (a hit allocates nothing at all), and with
/// the handful of distinct buffer sizes a viewer actually uses, a heap's
/// sub-allocation would buy nothing for its extra lifetime rules.
final class UnifiedMemoryPool: @unchecked Sendable {

    private let device: MTLDevice
    private let lock = NSLock()

    /// Free output buffers by byte count.
    private var freeBuffers: [Int: [MTLBuffer]] = [:]

    /// Wrapped input buffers, keyed by the identity of the aligned allocation they
    /// wrap. Re-wrapping the same frame every render would not copy pixels, but it
    /// would allocate an `MTLBuffer` object per render — which the M3 exit
    /// criterion forbids.
    private var wrappedInputs: [ObjectIdentifier: (buffer: MTLBuffer, storage: AlignedPixelBuffer)] = [:]
    private let wrappedInputCapacity = 4

    /// Diagnostics. Read by tests to assert the steady state really is allocation-
    /// and copy-free; a comment could not.
    private(set) var bufferAllocationCount = 0
    private(set) var pixelCopyCount = 0
    private(set) var zeroCopyWrapCount = 0

    init(device: MTLDevice) {
        self.device = device
    }

    // MARK: - Input

    /// An `MTLBuffer` over a frame's pixel bytes, without copying where possible.
    ///
    /// - Returns: the buffer, and the byte offset at which the requested frame
    ///   starts within it. The offset is passed to the kernel rather than to
    ///   `setBuffer(offset:)` so that no per-frame alignment rule applies — a
    ///   frame boundary is not page-aligned in general.
    func inputBuffer(for pixelData: PixelData, frameIndex: Int) -> (buffer: MTLBuffer, frameOffset: Int)? {
        let frameOffset = frameIndex * pixelData.descriptor.bytesPerFrame

        if let storage = pixelData.alignedStorage,
           let buffer = wrapNoCopy(storage) {
            return (buffer, frameOffset)
        }

        // Unaligned: one copy into a pooled buffer. Still no bus transfer on a
        // unified-memory device — just an avoidable in-memory copy, which is why
        // M2b exists to avoid it.
        guard let buffer = copyIntoPooledBuffer(pixelData.data) else { return nil }
        return (buffer, frameOffset)
    }

    /// Wraps page-aligned storage in place. No copy, ever.
    private func wrapNoCopy(_ storage: AlignedPixelBuffer) -> MTLBuffer? {
        let key = ObjectIdentifier(storage)

        lock.lock()
        if let cached = wrappedInputs[key] {
            lock.unlock()
            return cached.buffer
        }
        lock.unlock()

        // `bytesNoCopy` requires the page-aligned base and the page-rounded
        // length; `AlignedPixelBuffer` guarantees both. `deallocator: nil` because
        // the allocation belongs to the AlignedPixelBuffer, which the cache entry
        // below keeps alive for as long as the MTLBuffer refers to it.
        guard let buffer = device.makeBuffer(
            bytesNoCopy: storage.baseAddress,
            length: storage.allocatedByteCount,
            options: [.storageModeShared],
            deallocator: nil
        ) else {
            return nil
        }

        lock.lock()
        zeroCopyWrapCount += 1
        wrappedInputs[key] = (buffer, storage)
        if wrappedInputs.count > wrappedInputCapacity,
           let victim = wrappedInputs.keys.first(where: { $0 != key }) {
            wrappedInputs.removeValue(forKey: victim)
        }
        lock.unlock()
        return buffer
    }

    private func copyIntoPooledBuffer(_ data: Data) -> MTLBuffer? {
        guard !data.isEmpty, let buffer = takeBuffer(byteCount: data.count) else { return nil }
        data.withUnsafeBytes { source in
            guard let base = source.baseAddress else { return }
            buffer.contents().copyMemory(from: base, byteCount: data.count)
        }
        lock.lock()
        pixelCopyCount += 1
        lock.unlock()
        return buffer
    }

    // MARK: - Output

    /// A shared-storage buffer for a kernel to write its result into.
    ///
    /// The same memory `CGImage` will read — there is no readback step anywhere in
    /// this design.
    func outputBuffer(byteCount: Int) -> MTLBuffer? {
        takeBuffer(byteCount: byteCount)
    }

    /// Returns an output buffer to the pool for reuse.
    ///
    /// Only safe once the GPU is done with it *and* nothing is still reading it —
    /// in practice, once the `CGImage` backed by it has been released. The renderer
    /// therefore recycles a buffer only when it can prove that, and simply drops it
    /// otherwise: serving live image bytes to a second render would corrupt the
    /// first image on screen, which is a far worse outcome than an allocation.
    func recycle(_ buffer: MTLBuffer) {
        lock.lock()
        freeBuffers[buffer.length, default: []].append(buffer)
        lock.unlock()
    }

    private func takeBuffer(byteCount: Int) -> MTLBuffer? {
        lock.lock()
        if var bucket = freeBuffers[byteCount], let reused = bucket.popLast() {
            freeBuffers[byteCount] = bucket
            lock.unlock()
            return reused
        }
        lock.unlock()

        // `.hazardTrackingModeUntracked` skips Metal's automatic dependency
        // tracking: these buffers' lifetimes are managed explicitly here, and each
        // render waits for its own command buffer before anyone reads the result.
        guard let buffer = device.makeBuffer(
            length: byteCount,
            options: [.storageModeShared, .hazardTrackingModeUntracked]
        ) else {
            return nil
        }
        lock.lock()
        bufferAllocationCount += 1
        lock.unlock()
        return buffer
    }

    // MARK: - Diagnostics

    /// Snapshot of the counters, for tests and diagnostics.
    struct Counters: Equatable {
        var allocations: Int
        var pixelCopies: Int
        var zeroCopyWraps: Int
    }

    var counters: Counters {
        lock.lock()
        defer { lock.unlock() }
        return Counters(allocations: bufferAllocationCount,
                        pixelCopies: pixelCopyCount,
                        zeroCopyWraps: zeroCopyWrapCount)
    }

    /// Drops every pooled buffer and every wrapped input. Frees the GPU-visible
    /// memory this pool is holding; used when a study closes and by tests.
    func purge() {
        lock.lock()
        freeBuffers.removeAll()
        wrappedInputs.removeAll()
        lock.unlock()
    }
}
#endif
