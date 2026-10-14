// NEMA-verified: 2026a, checked 2026-10-14 — no DICOM-standard data (managed operation status).

/// Fixed-size failure returned by an explicitly admitted synchronous operation.
/// Formatting a user-facing message is deliberately a separate caller operation.
public struct DICOMManagedFailure: Error, Sendable, Equatable {
    /// Stable failure category; operands carry only structural numbers, never patient data.
    public enum Code: UInt16, Sendable {
        case allocation, cancelled, invalidOptions, invalidRange, notRegularFile, sizeLimit
        case readFailed, sourceChanged, unbudgetedRead, unexpectedEnd, invalidPrefix
        case invalidTransferSyntax, missingTransferSyntax, malformed, limitExceeded
        case invalidDescriptor, codecFailure, codecResultMismatch
    }
    /// Machine-readable failure category.
    public let code: Code
    /// Absolute source offset, when available; otherwise zero.
    public let offset: Int
    /// Category-specific structural operand.
    public let operand1: Int
    /// Category-specific structural operand.
    public let operand2: Int
    /// Additional fixed-size dependency detail, when present.
    public let operand3: Int
    /// Additional fixed-size dependency detail, when present.
    public let operand4: Int
    /// Dependency namespace: zero for DICOMKit; codec adapters document nonzero values.
    public let domain: UInt16
    /// Exact allocator rejection, if the failure originated at admission/allocation.
    public let allocation: DICOMAllocationError?

    /// Create a scalar failure without allocating a message or existential error box.
    public init(_ code: Code, offset: Int = 0, _ operand1: Int = 0, _ operand2: Int = 0,
                operand3: Int = 0, operand4: Int = 0, domain: UInt16 = 0) {
        self.code = code; self.offset = offset; self.operand1 = operand1; self.operand2 = operand2
        self.operand3 = operand3; self.operand4 = operand4; self.domain = domain
        allocation = nil
    }
    /// Preserve the allocator's fixed-size rejection reason.
    public init(allocation: DICOMAllocationError) {
        code = .allocation; offset = 0; operand1 = 0; operand2 = 0
        operand3 = 0; operand4 = 0; domain = 0; self.allocation = allocation
    }
}

/// Caller-owned cancellation observation for a synchronous managed operation.
/// The context must remain alive until the operation actually returns. Cancelling
/// a subscriber never destroys storage that a worker still owns.
public struct DICOMCancellation: @unchecked Sendable {
    /// Thin, noncapturing callback. Its implementation must not allocate or block.
    public let check: (@convention(c) (UnsafeMutableRawPointer?) -> Bool)?
    /// Borrowed context owned by the caller for the complete synchronous call.
    public let context: UnsafeMutableRawPointer?
    /// No cancellation callback.
    public static var never: Self { Self() }
    /// Construct a token; no closure context or task-local runtime storage is created.
    public init(check: (@convention(c) (UnsafeMutableRawPointer?) -> Bool)? = nil,
                context: UnsafeMutableRawPointer? = nil) {
        self.check = check; self.context = context
    }
    /// Observe cancellation as a scalar value without Swift's throwing runtime.
    public var failure: DICOMManagedFailure? {
        check?(context) == true ? DICOMManagedFailure(.cancelled) : nil
    }
    /// Observe cancellation without allocating an error message or task object.
    public func validate() throws(DICOMManagedFailure) {
        if check?(context) == true { throw DICOMManagedFailure(.cancelled) }
    }
}
