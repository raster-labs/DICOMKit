// NEMA-verified: 2026a, checked 2026-10-14 — no DICOM-standard data (owned decoded storage).
import Foundation

/// Descriptor-bearing decoded output whose backing has an explicit allocation lease.
/// The buffer's visible count may be smaller than its retained capacity. Transfer
/// the complete backing to resident/preview ownership once using `data.transfer`.
/// Shared references retain one charge until the last reference is destroyed.
public struct ManagedDecodedPixelFrame: Sendable {
    /// Immutable decoded bytes and their complete retained backing charge.
    public let data: DICOMByteBuffer
    /// Descriptor of the actual output, including any explicitly recovered precision.
    public let descriptor: PixelDataDescriptor
    /// Zero-based frame index in the source instance.
    public let sourceFrameIndex: Int
    /// Interpretation diagnostics produced by the canonical codec policy.
    public let diagnostics: [PixelDecodeDiagnostic]

    /// Wrap existing managed storage without copying it or transferring its charge.
    /// - Parameters:
    ///   - data: Storage retained by the frame.
    ///   - descriptor: Description of the decoded bytes.
    ///   - sourceFrameIndex: Zero-based frame index in the source.
    ///   - diagnostics: Any interpretation changes reported by decoding.
    public init(data: DICOMByteBuffer, descriptor: PixelDataDescriptor, sourceFrameIndex: Int,
                diagnostics: [PixelDecodeDiagnostic] = []) {
        self.data = data
        self.descriptor = descriptor
        self.sourceFrameIndex = sourceFrameIndex
        self.diagnostics = diagnostics
    }
}

/// Lexically scoped codec scratch. The mapping is destroyed before its backing
/// lease releases. The fixed control allowance is not runtime-heap qualification.
func withCodecWorkspace<Result>(count: Int, budget: DICOMAllocationBudget,
    _ body: (UnsafeMutableRawBufferPointer) throws -> Result) throws -> Result {
    let control = try budget.reserve(DICOMByteBuffer.controlCapacity, as: .metadata)
    let storage = try AlignedPixelBuffer(byteCount: count, budget: budget, resource: .staging)
    return try withExtendedLifetime((storage, control)) {
        try body(UnsafeMutableRawBufferPointer(start: storage.baseAddress, count: count))
    }
}
