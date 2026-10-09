// AlignedPixelBuffer.swift
// DICOMCore — GPU_RENDERING_PLAN.md milestone M2b
//
// Page-aligned storage for decoded pixel data, so a GPU can read it in place.
// NEMA-verified: 2026a, checked 2026-09-25 — carries no DICOM-standard data (page-aligned allocation for GPU upload). C1 classification confirmed.

import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A page-aligned, page-sized allocation holding decoded pixel bytes.
///
/// Exists for exactly one reason: `MTLDevice.makeBuffer(bytesNoCopy:…)` requires a
/// page-aligned pointer and a length rounded up to a page multiple. Meet those two
/// conditions and, on a unified-memory device, the GPU reads the decoded frame the
/// CPU already holds — no upload, no staging buffer, no copy. Miss them and the
/// call fails and the renderer falls back to copying, which for a 3000×4000
/// mammogram is ~23 MB per render.
///
/// A plain Swift `Data` or `[UInt8]` cannot make either guarantee, which is why
/// this type exists rather than a pointer cast over the existing storage.
///
/// This is a class, not a struct, because the allocation has a lifetime: the
/// `Data` handed to CPU consumers and the `MTLBuffer` handed to the GPU both point
/// into it, and both keep it alive.
public final class AlignedPixelBuffer: @unchecked Sendable {

    /// The page-aligned base address. Stable for the object's lifetime.
    public let baseAddress: UnsafeMutableRawPointer

    /// The meaningful bytes — what the pixel data actually contains.
    public let byteCount: Int

    /// The allocation, rounded up to a whole number of pages. This is the length
    /// to hand `makeBuffer(bytesNoCopy:length:)`; passing `byteCount` would fail
    /// for any size that is not already a page multiple.
    public let allocatedByteCount: Int

    /// The host page size — 16 KB on Apple Silicon, 4 KB on x86.
    public static var pageSize: Int {
        Int(getpagesize())
    }

    /// Allocates `byteCount` bytes of page-aligned, uninitialised storage.
    ///
    /// Returns `nil` if the allocation fails, so callers keep working from the
    /// unaligned original rather than trapping. Zero-length is refused: there is
    /// nothing to wrap, and a zero-length `MTLBuffer` is not valid either.
    public init?(byteCount: Int) {
        guard byteCount > 0 else { return nil }
        let pageSize = Self.pageSize
        let allocated = ((byteCount + pageSize - 1) / pageSize) * pageSize

        var pointer: UnsafeMutableRawPointer?
        guard posix_memalign(&pointer, pageSize, allocated) == 0,
              let pointer else {
            return nil
        }
        self.baseAddress = pointer
        self.byteCount = byteCount
        self.allocatedByteCount = allocated
    }

    /// Copies `data` into fresh page-aligned storage.
    ///
    /// The copy is the point at which alignment is bought, and it is paid **once**,
    /// when a file enters the frame cache — not per render. Every render after
    /// that reads this allocation directly.
    public convenience init?(copying data: Data) {
        self.init(byteCount: data.count)
        guard byteCount > 0 else { return nil }
        data.withUnsafeBytes { source in
            guard let base = source.baseAddress else { return }
            baseAddress.copyMemory(from: base, byteCount: data.count)
        }
    }

    deinit {
        free(baseAddress)
    }

    /// The bytes as `Data`, without copying them.
    ///
    /// The returned `Data` keeps this buffer alive on its own — the deallocator
    /// closure holds a strong reference — so it stays valid even if the caller
    /// outlives every other reference. (No retain cycle: the closure is owned by
    /// the `Data`, not by `self`.)
    public var data: Data {
        Data(bytesNoCopy: baseAddress, count: byteCount, deallocator: .custom { _, _ in
            withExtendedLifetime(self) {}
        })
    }

    /// Whether `baseAddress` really is page-aligned. Always true by construction;
    /// exists so the zero-copy claim can be asserted rather than assumed.
    public var isPageAligned: Bool {
        UInt(bitPattern: baseAddress) % UInt(Self.pageSize) == 0
    }
}

// MARK: - PixelData integration

extension PixelData {
    /// A copy of this pixel data whose bytes live in page-aligned storage.
    ///
    /// Returns `self` unchanged when the allocation fails or the data is empty, so
    /// a caller can use the result unconditionally — correctness never depends on
    /// alignment succeeding, only performance does.
    ///
    /// Worth doing once per file, at the point it enters a cache. Doing it per
    /// render would pay the copy this is meant to avoid.
    public func pageAligned() -> PixelData {
        if alignedStorage != nil { return self }
        guard let buffer = AlignedPixelBuffer(copying: data) else { return self }
        return PixelData(alignedStorage: buffer, descriptor: descriptor)
    }
}
