// NEMA-verified: 2026a, checked 2026-10-14 — no DICOM-standard data (scalar operation outcomes).

/// Allocation result with no Swift Error conformance requirement or throwing runtime path.
/// Qualified callers switch over the value and propagate failure without calling `get()`.
public enum DICOMAllocationOutcome<Value: ~Copyable>: ~Copyable {
    /// Successfully constructed or updated value.
    case success(Value)
    /// Scalar admission, mapping, ownership or synchronization refusal.
    case failure(DICOMAllocationError)

    /// Internal propagation helper; `.success(nil)` remains distinct from failure.
    @inlinable @inline(__always)
    package consuming func takeValue(failure: inout DICOMAllocationError) -> Value? {
        switch consume self {
        case .success(let value): return .some(value)
        case .failure(let reason): failure = reason; return nil
        }
    }

    /// Throwing compatibility adapter, outside the qualified allocation boundary.
    /// Swift's cold Error witness initialization may allocate; do not use this in admitted work.
    /// - Returns: The successful value, consuming this outcome.
    public consuming func get() throws(DICOMAllocationError) -> Value {
        switch consume self {
        case .success(let value): return value
        case .failure(let failure): throw failure
        }
    }
}
extension DICOMAllocationOutcome: Copyable where Value: Copyable {}
extension DICOMAllocationOutcome: Sendable where Value: Sendable {}

/// Managed-operation result whose failure is a fixed scalar value, never an Error box.
/// It does not invoke Swift's throwing machinery or require an Error witness table.
public enum DICOMManagedOutcome<Value: ~Copyable>: ~Copyable {
    /// Successfully constructed or updated value.
    case success(Value)
    /// Scalar failure to propagate without entering a throwing compatibility adapter.
    case failure(DICOMManagedFailure)

    /// Internal propagation helper without Error metadata or witness lookup.
    @inlinable @inline(__always)
    package consuming func takeValue(failure: inout DICOMManagedFailure) -> Value? {
        switch consume self {
        case .success(let value): return .some(value)
        case .failure(let reason): failure = reason; return nil
        }
    }

    /// Throwing compatibility adapter, outside the qualified operation boundary.
    /// - Returns: The successful value, consuming this outcome.
    public consuming func get() throws(DICOMManagedFailure) -> Value {
        switch consume self {
        case .success(let value): return value
        case .failure(let failure): throw failure
        }
    }
}
extension DICOMManagedOutcome: Copyable where Value: Copyable {}
extension DICOMManagedOutcome: Sendable where Value: Sendable {}
