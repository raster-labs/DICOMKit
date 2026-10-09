// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data (task-group scheduling and byte budgets)
import Foundation
import DICOMCore

/// Byte-budgeted, cancellable parallel frame decoding (WP-G, plan M4)
///
/// Concurrency is bounded by **decoded bytes in flight**, not task count: the
/// window is `min(active cores, maxInFlightBytes / bytesPerFrame)`, never below
/// 1. On Apple unified memory, decode and rendering share bandwidth, so "one
/// task per frame" storms are exactly what the research-adoption instructions
/// (§11) prohibit. Cancellation of the calling task stops scheduling new frames
/// immediately and is checked before every decode.
extension DICOMFile {

    /// The concurrency window for a given budget and frame size (≥ 1).
    static func maxConcurrentFrames(bytesPerFrame: Int, maxInFlightBytes: Int) -> Int {
        guard bytesPerFrame > 0 else { return 1 }
        let byBudget = maxInFlightBytes / bytesPerFrame
        return max(1, min(ProcessInfo.processInfo.activeProcessorCount, byBudget))
    }

    /// Decodes the requested frames concurrently under a decoded-bytes budget
    ///
    /// - Parameters:
    ///   - frames: Zero-based frame indices (deduplicated; order of the result
    ///     dictionary is by key).
    ///   - maxInFlightBytes: Ceiling on decoded bytes held by in-flight decodes
    ///     (default 64 MB). One frame may exceed the budget on its own — it then
    ///     runs alone.
    ///   - aligned: When true, frames decode into page-aligned GPU-ready
    ///     storage via `alignedPixelData(frame:)`.
    /// - Returns: Frame index → single-frame `PixelData`.
    /// - Throws: `CancellationError` when the calling task is cancelled;
    ///   `PixelDataError` for decode failures.
    public func pixelData(
        frames: [Int],
        maxInFlightBytes: Int = 64 << 20,
        aligned: Bool = false
    ) async throws -> [Int: PixelData] {
        let descriptor = try dataSet.tryPixelDataDescriptor()
        let bytesPerFrame = descriptor.rows * descriptor.columns
            * descriptor.samplesPerPixel * max(1, descriptor.bitsAllocated / 8)
        let width = Self.maxConcurrentFrames(bytesPerFrame: bytesPerFrame,
                                             maxInFlightBytes: maxInFlightBytes)
        let wanted = Array(Set(frames)).sorted()

        var results: [Int: PixelData] = [:]
        results.reserveCapacity(wanted.count)

        try await withThrowingTaskGroup(of: (Int, PixelData).self) { group in
            var next = 0
            func schedule(_ frame: Int) {
                group.addTask {
                    try Task.checkCancellation()
                    let pd = aligned
                        ? try self.alignedPixelData(frame: frame)
                        : try self.pixelData(frame: frame)
                    return (frame, pd)
                }
            }
            while next < min(width, wanted.count) {
                schedule(wanted[next]); next += 1
            }
            while let (frame, pd) = try await group.next() {
                results[frame] = pd
                try Task.checkCancellation()
                if next < wanted.count {
                    schedule(wanted[next]); next += 1
                }
            }
            return
        }
        return results
    }

    /// Decodes every frame concurrently under the byte budget and returns one
    /// multi-frame `PixelData` — a bounded-parallel, cancellable alternative to
    /// the serial `pixelData()`.
    public func pixelDataParallel(maxInFlightBytes: Int = 64 << 20) async throws -> PixelData {
        let descriptor = try dataSet.tryPixelDataDescriptor()
        let frames = try await pixelData(frames: Array(0..<descriptor.numberOfFrames),
                                         maxInFlightBytes: maxInFlightBytes)
        var combined = Data(capacity: frames.values.reduce(0) { $0 + $1.data.count })
        var outDescriptor = descriptor
        for i in 0..<descriptor.numberOfFrames {
            guard let frame = frames[i] else {
                throw PixelDataError.frameExtractionFailed(frameIndex: i)
            }
            combined.append(frame.data)
            // Frame decodes may correct the photometric interpretation
            // (JPEG baseline YBR→RGB); carry that into the combined descriptor.
            if frame.descriptor.photometricInterpretation != descriptor.photometricInterpretation {
                outDescriptor = PixelDataDescriptor(
                    rows: descriptor.rows,
                    columns: descriptor.columns,
                    numberOfFrames: descriptor.numberOfFrames,
                    bitsAllocated: descriptor.bitsAllocated,
                    bitsStored: descriptor.bitsStored,
                    highBit: descriptor.highBit,
                    isSigned: descriptor.isSigned,
                    samplesPerPixel: descriptor.samplesPerPixel,
                    photometricInterpretation: frame.descriptor.photometricInterpretation,
                    planarConfiguration: descriptor.planarConfiguration)
            }
        }
        return PixelData(data: combined, descriptor: outDescriptor)
    }
}
