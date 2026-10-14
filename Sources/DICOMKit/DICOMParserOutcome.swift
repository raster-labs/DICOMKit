// NEMA-verified: 2026a, checked 2026-10-14 — no DICOM-standard data (parser operation outcome).

/// Canonical parser result without Swift throwing machinery on the selected core path.
public enum DICOMParserOutcome<Value: ~Copyable>: ~Copyable {
    /// Successfully parsed or acquired value.
    case success(Value)
    /// Fixed scalar parser status; formatting belongs outside the admitted operation.
    case failure(DICOMParserFailure)

    @inline(__always)
    consuming func takeValue(failure: inout DICOMParserFailure) -> Value? {
        switch consume self {
        case .success(let value): return .some(value)
        case .failure(let reason): failure = reason; return nil
        }
    }

    /// Throwing compatibility adapter outside the qualified parser boundary.
    /// - Returns: The successful value, consuming this outcome.
    public consuming func get() throws(DICOMParserFailure) -> Value {
        switch consume self {
        case .success(let value): return value
        case .failure(let failure): throw failure
        }
    }
}
extension DICOMParserOutcome: Copyable where Value: Copyable {}
extension DICOMParserOutcome: Sendable where Value: Sendable {}

import DICOMCore

// The canonical grammar also serves legacy owned values. Concrete internal
// carriers keep discarded successful legacy placeholders from requiring cold
// generic result metadata on the bounded path. No grammar or value semantics differ.

enum DICOMDataSetOutcome {
    case success(DataSet)
    case failure(DICOMParserFailure)

    @inline(__always)
    consuming func takeValue(failure: inout DICOMParserFailure) -> DataSet? {
        switch self {
        case .success(let value): return value
        case .failure(let reason): failure = reason; return nil
        }
    }

    consuming func get() throws(DICOMParserFailure) -> DataSet {
        switch self {
        case .success(let value): return value
        case .failure(let failure): throw failure
        }
    }
}

enum DICOMDataElementOutcome {
    case success(DataElement)
    case failure(DICOMParserFailure)

    @inline(__always)
    consuming func takeValue(failure: inout DICOMParserFailure) -> DataElement? {
        switch self {
        case .success(let value): return value
        case .failure(let reason): failure = reason; return nil
        }
    }

    consuming func get() throws(DICOMParserFailure) -> DataElement {
        switch self {
        case .success(let value): return value
        case .failure(let failure): throw failure
        }
    }
}

enum DICOMSequenceItemOutcome {
    case success(SequenceItem)
    case failure(DICOMParserFailure)

    @inline(__always)
    consuming func takeValue(failure: inout DICOMParserFailure) -> SequenceItem? {
        switch self {
        case .success(let value): return value
        case .failure(let reason): failure = reason; return nil
        }
    }

    consuming func get() throws(DICOMParserFailure) -> SequenceItem {
        switch self {
        case .success(let value): return value
        case .failure(let failure): throw failure
        }
    }
}

enum DICOMSequenceItemsOutcome {
    case success([SequenceItem])
    case failure(DICOMParserFailure)

    @inline(__always)
    consuming func takeValue(failure: inout DICOMParserFailure) -> [SequenceItem]? {
        switch self {
        case .success(let value): return value
        case .failure(let reason): failure = reason; return nil
        }
    }

    consuming func get() throws(DICOMParserFailure) -> [SequenceItem] {
        switch self {
        case .success(let value): return value
        case .failure(let failure): throw failure
        }
    }
}

enum DICOMDataElementsOutcome {
    case success([DataElement])
    case failure(DICOMParserFailure)

    @inline(__always)
    consuming func takeValue(failure: inout DICOMParserFailure) -> [DataElement]? {
        switch self {
        case .success(let value): return value
        case .failure(let reason): failure = reason; return nil
        }
    }

    consuming func get() throws(DICOMParserFailure) -> [DataElement] {
        switch self {
        case .success(let value): return value
        case .failure(let failure): throw failure
        }
    }
}
