// NEMA-verified: 2026a, checked 2026-10-14 — parser failure representation only.
import Foundation
import DICOMCore

/// Scalar failures emitted by the canonical parser's admitted core. No diagnostic
/// formatting or existential conversion occurs until a legacy API requests it.
public enum DICOMParserFailure: Error, Sendable, Equatable {
    case managed(DICOMManagedFailure)
    case strict(StrictParsingError)
    case unexpectedEndOfData
    case unbudgetedMaterialization
    case malformed(offset: Int, reason: MalformedReason)
    case parsing(ParsingReason)
    case limit(LimitReason)
    case totalElementLimit(Int)
    case elementLength(tag: Tag, length: UInt32, limit: Int)
    case fragmentCountLimit(Int)
    case sequenceDepthLimit(Int)
    case expectedBOTItem(Tag)
    case expectedItemOrDelimiter(Tag)
    case expectedSequenceItem(Tag)
    case invalidVR(UInt8, UInt8)

    public enum MalformedReason: UInt8, Sendable {
        case scopeBoundary
        case delimiterLength
        case oddValueLength
        case fileMetaLength
        case fileMetaBoundary
        case fileMetaInDataSet
        case unexpectedDelimiter
        case undefinedNonSequence
        case reservedVRBytes
        case expectedSequenceItem
        case sequenceBoundary
        case fileMetaInItem
        case itemBoundary
        case pixelPaddingLength
        case pixelPaddingRepresentation
    }
    public enum ParsingReason: UInt8, Sendable {
        case encapsulatedSyntax
        case encapsulatedVR
        case encapsulatedReserved
        case encapsulatedLength
        case missingBOTItem
        case botLength
        case sequenceDelimiterLength
        case fragmentLength
        case incompleteEncapsulation
        case expectedItemOrDelimiter
    }
    public enum LimitReason: UInt8, Sendable {
        case botBytes
        case botCount
        case encapsulatedBytes
    }
    internal var isLegacyLimit: Bool {
        switch self {
        case .limit, .totalElementLimit, .elementLength, .fragmentCountLimit, .sequenceDepthLimit: return true
        default: return false
        }
    }
    /// Compatibility formatting is outside the qualified synchronous operation.
    internal var legacyError: any Error {
        switch self {
        case .managed(let failure): return failure
        case .strict(let failure): return failure
        case .unexpectedEndOfData: return DICOMError.unexpectedEndOfData
        case .unbudgetedMaterialization: return DICOMError.parsingFailed("Unbudgeted materialization in bounded parser")
        case .malformed(let offset, let reason):
            let message: String
            switch reason {
            case .scopeBoundary: message = "Declared scope boundary exceeds available data"
            case .delimiterLength: message = "Missing or nonzero delimiter length"
            case .oddValueLength: message = "Odd value length"
            case .fileMetaLength: message = "Invalid file-meta group length"
            case .fileMetaBoundary: message = "File-meta group length mismatch"
            case .fileMetaInDataSet: message = "File-meta element within main dataset"
            case .unexpectedDelimiter: message = "Unexpected item or delimiter tag"
            case .undefinedNonSequence: message = "Undefined-length non-SQ value is outside strict scope"
            case .reservedVRBytes: message = "Nonzero or missing reserved VR bytes"
            case .expectedSequenceItem: message = "Expected sequence item"
            case .sequenceBoundary: message = "Sequence boundary mismatch"
            case .fileMetaInItem: message = "File-meta element within sequence item"
            case .itemBoundary: message = "Item boundary mismatch"
            case .pixelPaddingLength: message = "Implicit pixel padding must contain one 16-bit value"
            case .pixelPaddingRepresentation: message = "Implicit pixel padding requires valid Pixel Representation context"
            }
            return StrictParsingError.malformedStructure(offset: offset, reason: message)
        case .parsing(let reason):
            switch reason {
            case .encapsulatedSyntax: return DICOMError.parsingFailed("Encapsulated Pixel Data requires Explicit VR Little Endian")
            case .encapsulatedVR: return DICOMError.parsingFailed("Invalid encapsulated Pixel Data VR")
            case .encapsulatedReserved: return DICOMError.parsingFailed("Encapsulated Pixel Data requires OB and zero reserved bytes")
            case .encapsulatedLength: return DICOMError.parsingFailed("Encapsulated Pixel Data requires undefined length")
            case .missingBOTItem: return DICOMError.parsingFailed("Expected Item tag for Basic Offset Table")
            case .botLength: return DICOMError.parsingFailed("Invalid Basic Offset Table length")
            case .sequenceDelimiterLength: return DICOMError.parsingFailed("Nonzero Sequence Delimitation Item length")
            case .fragmentLength: return DICOMError.parsingFailed("Invalid encapsulated fragment length")
            case .incompleteEncapsulation: return DICOMError.parsingFailed("Incomplete encapsulation or invalid Basic Offset Table offsets")
            case .expectedItemOrDelimiter: return DICOMError.parsingFailed("Expected Item or Sequence Delimitation tag")
            }
        case .limit(let reason):
            switch reason {
            case .botBytes: return DICOMError.limitExceeded("Basic Offset Table exceeds input or encapsulated byte budget")
            case .botCount: return DICOMError.limitExceeded("Basic Offset Table exceeds fragment count budget")
            case .encapsulatedBytes: return DICOMError.limitExceeded("Encapsulated payload exceeds cumulative byte budget")
            }
        case .totalElementLimit(let value): return DICOMError.limitExceeded("Element count exceeds maxTotalElements (\(value))")
        case .elementLength(let tag, let length, let limit):
            return DICOMError.limitExceeded("Element \(tag) declares length \(length), exceeding maxElementLength (\(limit))")
        case .fragmentCountLimit(let value): return DICOMError.limitExceeded("Encapsulated fragment count exceeds maxFragmentCount (\(value))")
        case .sequenceDepthLimit(let value): return DICOMError.limitExceeded("Sequence nesting depth exceeds maxSequenceDepth (\(value))")
        case .expectedBOTItem(let tag): return DICOMError.parsingFailed("Expected Item tag (FFFE,E000), found \(tag)")
        case .expectedItemOrDelimiter(let tag): return DICOMError.parsingFailed("Expected Item or Sequence Delimitation tag, found \(tag)")
        case .expectedSequenceItem(let tag): return DICOMError.parsingFailed("Expected Item tag (FFFE,E000) in sequence, found \(tag)")
        case .invalidVR(let a, let b): return DICOMError.invalidVR(String(bytes: [a, b], encoding: .ascii) ?? "non-ASCII")
        }
    }
}
