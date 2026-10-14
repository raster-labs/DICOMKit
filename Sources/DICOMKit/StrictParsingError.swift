import Foundation
import DICOMCore

/// Failures introduced by opt-in strict structural reads. No patient values are included.
/// Strict parsing is not IOD, pixel-semantic, or clinical validation.
public enum StrictParsingError: Error, Sendable, Equatable {
    /// Structural counters limited by strict parsing options, excluding runtime heap usage.
    public enum Resource: Sendable, Equatable {
        case inputBytes
        case sequenceDepth
        case totalElements
        case sequenceItems
        case materializedValueBytes
    }

    case resourceLimitExceeded(resource: Resource, limit: Int)
    case invalidOptions
    case missingTransferSyntax
    case unsupportedTransferSyntax(String)
    case duplicateTag(tag: Tag, offset: Int)
    case malformedStructure(offset: Int, reason: String)
    case elementLimitExceeded(Int)
}
