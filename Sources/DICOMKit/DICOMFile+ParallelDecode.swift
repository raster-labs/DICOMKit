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
    public func pixelData(frames: [Int], maxInFlightBytes: Int = 64 << 20,
                          aligned: Bool = false) async throws -> [Int: PixelData] {
        try await pixelData(frames: frames, maxInFlightBytes: maxInFlightBytes, aligned: aligned, codecRegistry: .shared)
    }

    public func pixelData(
        frames: [Int],
        maxInFlightBytes: Int = 64 << 20,
        aligned: Bool = false,
        codecRegistry: CodecRegistry
    ) async throws -> [Int: PixelData] {
        let descriptor = try dataSet.tryPixelDataDescriptor()
        let wanted = Array(Set(frames)).sorted()
        guard let first = wanted.first else { return [:] }
        let source = try frameSource(descriptor: descriptor, frame: first, registry: codecRegistry)
        return try await decodeFrames(wanted, descriptor: descriptor, source: source,
                                      maxInFlightBytes: maxInFlightBytes, aligned: aligned)
    }

    private func decodeFrames(_ wanted: [Int], descriptor: PixelDataDescriptor, source: FrameSource,
                              maxInFlightBytes: Int, aligned: Bool) async throws -> [Int: PixelData] {
        let size = try Self.checkedFrameBytes(descriptor, frame: wanted.first ?? 0)
        let width = Self.maxConcurrentFrames(bytesPerFrame: size, maxInFlightBytes: maxInFlightBytes)
        var results: [Int: PixelData] = [:]
        results.reserveCapacity(wanted.count)

        try await withThrowingTaskGroup(of: (Int, PixelData).self) { group in
            var next = 0
            func schedule(_ frame: Int) {
                group.addTask {
                    try Task.checkCancellation()
                    let pd = try self.readFrame(frame, descriptor: descriptor, source: source, aligned: aligned)
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
        try await pixelDataParallel(maxInFlightBytes: maxInFlightBytes, codecRegistry: .shared)
    }

    public func pixelDataParallel(
        maxInFlightBytes: Int = 64 << 20,
        codecRegistry: CodecRegistry
    ) async throws -> PixelData {
        let descriptor = try dataSet.tryPixelDataDescriptor()
        let source = try frameSource(descriptor: descriptor, frame: 0, registry: codecRegistry)
        // Validate the size before constructing the list of all frames.
        switch source {
        case .encapsulated:
            _ = try descriptor.checkedNativeConversionFrameBytes()
        case .native(let element):
            let size = try Self.checkedFrameBytes(descriptor, frame: 0)
            let (samples, overflow) = size.multipliedReportingOverflow(by: descriptor.numberOfFrames)
            guard !overflow else { throw PixelDataError.frameExtractionFailed(frameIndex: 0) }
            let required = descriptor.bitsAllocated == 1 ? (samples - 1) / 8 + 1 : samples
            guard required <= element.valueData.count else { throw PixelDataError.frameExtractionFailed(frameIndex: 0) }
        }
        let frames = try await decodeFrames(Array(0..<descriptor.numberOfFrames), descriptor: descriptor,
                                            source: source, maxInFlightBytes: maxInFlightBytes, aligned: false)
        guard let first = frames[0] else { throw PixelDataError.frameExtractionFailed(frameIndex: 0) }
        let actual = first.descriptor
        var combined = Data()
        for i in 0..<descriptor.numberOfFrames {
            guard let frame = frames[i], frame.descriptor == actual else {
                throw PixelDataError.frameExtractionFailed(frameIndex: i)
            }
            combined.append(frame.data)
        }
        let full = PixelDataDescriptor(rows: actual.rows, columns: actual.columns, numberOfFrames: descriptor.numberOfFrames,
                                       bitsAllocated: actual.bitsAllocated, bitsStored: actual.bitsStored,
                                       highBit: actual.highBit, isSigned: actual.isSigned,
                                       samplesPerPixel: actual.samplesPerPixel,
                                       photometricInterpretation: actual.photometricInterpretation,
                                       planarConfiguration: actual.planarConfiguration)
        return PixelData(data: combined, descriptor: full)
    }
}
