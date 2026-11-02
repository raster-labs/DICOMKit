import Foundation

/// A terminal C-FIND Cancel response (FE00), with results already received.
///
/// PS3.4 Table C.4-1 distinguishes cancellation from successful completion.
/// The caller may display these partial results, but must not claim a complete
/// query. Keeping them on the error preserves the existing throwing find API.
public struct QueryCancelledError: Error, Sendable, CustomStringConvertible, LocalizedError {
    public let partialResults: [GenericQueryResult]

    public init(partialResults: [GenericQueryResult]) {
        self.partialResults = partialResults
    }

    public var description: String {
        "C-FIND cancelled (FE00); \(partialResults.count) partial result(s) received. Query results are incomplete."
    }

    public var errorDescription: String? { description }
}
