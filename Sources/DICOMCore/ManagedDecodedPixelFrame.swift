// NEMA-verified: 2026a, checked 2026-10-14 — no DICOM-standard data (owned decoded storage).

/// Move-only decoded output with explicitly retained mapped storage.
/// Sharing retains the same capacity; ownership transfer is explicit through `data.transfer`.
public struct ManagedDecodedPixelFrame: ~Copyable, Sendable {
    /// Immutable bytes and their retained payload/control capacities.
    public let data: DICOMByteBuffer
    /// Actual output descriptor, including any recovered precision.
    public let descriptor: PixelDataDescriptor
    /// Zero-based frame index in the source instance.
    public let sourceFrameIndex: Int
    /// Optional scalar interpretation diagnostic; no diagnostic array is allocated.
    public let diagnostic: PixelDecodeDiagnostic?

    /// Consume an owner without copying bytes or transferring its charge.
    /// - Parameters:
    ///   - data: Storage whose ownership moves into this frame.
    ///   - descriptor: Actual decoded output description.
    ///   - sourceFrameIndex: Zero-based source frame index.
    ///   - diagnostic: Optional interpretation change reported by canonical policy.
    public init(data: consuming DICOMByteBuffer, descriptor: PixelDataDescriptor, sourceFrameIndex: Int,
                diagnostic: PixelDecodeDiagnostic? = nil) {
        self.data = data; self.descriptor = descriptor
        self.sourceFrameIndex = sourceFrameIndex; self.diagnostic = diagnostic
    }

    /// Retain the same output without another backing or charge.
    /// - Returns: Independently owned handle with the same descriptor and diagnostic.
    public borrowing func share() throws(DICOMAllocationError) -> ManagedDecodedPixelFrame {
        try legacyAllocationValue(shareOutcome())
    }
    /// Retain this frame with scalar status and no throwing-runtime call.
    /// - Returns: A frame sharing the same backing or a refcount refusal.
    public borrowing func shareOutcome() -> DICOMAllocationOutcome<Self> {
        switch data.shareOutcome() {
        case .success(let alias):
            return .success(Self(data: alias, descriptor: descriptor,
                                 sourceFrameIndex: sourceFrameIndex, diagnostic: diagnostic))
        case .failure(let error): return .failure(error)
        }
    }
}
