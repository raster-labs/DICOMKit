// NEMA-verified: 2026a, checked 2026-10-14 — scalar snapshot of the existing strict-parser policy.
import DICOMCore

/// The finite transfer-syntax policy already admitted by strict bounded reads.
public enum BoundedTransferSyntax: UInt8, Sendable {
    /// Native Implicit VR Little Endian.
    case implicitLittleEndian = 0
    /// Native Explicit VR Little Endian.
    case explicitLittleEndian = 1
    /// JPEG Baseline, Process 1.
    case jpegBaseline = 2
    /// JPEG Lossless, Selection Value 1.
    case jpegLosslessSV1 = 3
    /// JPEG-LS Lossless.
    case jpegLSLossless = 4

    var mask: UInt8 { UInt8(1) << rawValue }
    var isExplicitVR: Bool { self != .implicitLittleEndian }
    var isEncapsulated: Bool { rawValue >= Self.jpegBaseline.rawValue }

    /// String materialization is confined to compatibility/UI boundaries.
    public var uid: String {
        switch self {
        case .implicitLittleEndian: return "1.2.840.10008.1.2"
        case .explicitLittleEndian: return "1.2.840.10008.1.2.1"
        case .jpegBaseline: return "1.2.840.10008.1.2.4.50"
        case .jpegLosslessSV1: return "1.2.840.10008.1.2.4.70"
        case .jpegLSLossless: return "1.2.840.10008.1.2.4.80"
        }
    }

    static func fromUID(_ uid: String) -> Self? {
        switch uid {
        case "1.2.840.10008.1.2": return .implicitLittleEndian
        case "1.2.840.10008.1.2.1": return .explicitLittleEndian
        case "1.2.840.10008.1.2.4.50": return .jpegBaseline
        case "1.2.840.10008.1.2.4.70": return .jpegLosslessSV1
        case "1.2.840.10008.1.2.4.80": return .jpegLSLossless
        default: return nil
        }
    }

    /// Compare an already-trimmed token with static UTF-8 storage, without String conversion.
    static func fromToken(_ token: UnsafeBufferPointer<UInt8>) -> Self? {
        if matches(token, "1.2.840.10008.1.2") { return .implicitLittleEndian }
        if matches(token, "1.2.840.10008.1.2.1") { return .explicitLittleEndian }
        if matches(token, "1.2.840.10008.1.2.4.50") { return .jpegBaseline }
        if matches(token, "1.2.840.10008.1.2.4.70") { return .jpegLosslessSV1 }
        if matches(token, "1.2.840.10008.1.2.4.80") { return .jpegLSLossless }
        return nil
    }

    private static func matches(_ token: UnsafeBufferPointer<UInt8>, _ literal: StaticString) -> Bool {
        guard token.count == literal.utf8CodeUnitCount else { return false }
        let expected = literal.utf8Start
        for index in 0..<token.count where token[index] != expected[index] { return false }
        return true
    }
}

/// Copyable scalar policy shared by the canonical parser's storage modes.
/// No transfer-syntax Set or String is retained by the bounded operation.
public struct BoundedParsingOptions: Sendable {
    let validationPolicy: ParsingOptions.ValidationPolicy
    let mode: ParsingOptions.Mode
    let stopAfterTag: Tag?
    let maxElements: Int?
    let maxSequenceDepth: Int
    let maxElementLength: Int?
    let maxTotalElements: Int?
    let maxFragmentCount: Int?
    let strictEncapsulation: Bool
    let maximumEncapsulatedBytes: Int
    let maximumInflatedByteCount: Int
    /// Strict limits copied before the bounded parser operation begins.
    public let strictResourceLimits: ParsingOptions.StrictResourceLimits
    let allowedTransferSyntaxMask: UInt8

    /// Convert and validate legacy public options before entering the bounded operation.
    public init(_ options: ParsingOptions) throws(StrictParsingError) {
        guard options.validationPolicy == .strict, options.mode == .full,
              options.stopAfterTag == nil, options.strictResourceLimits.isValid else {
            throw .invalidOptions
        }
        if let maximum = options.maxElements, maximum <= 0 { throw .invalidOptions }
        if let allowed = options.allowedTransferSyntaxUIDs {
            for uid in allowed where BoundedTransferSyntax.fromUID(uid) == nil { throw .invalidOptions }
        }
        self.init(legacy: options)
        let compressed = BoundedTransferSyntax.jpegBaseline.mask
            | BoundedTransferSyntax.jpegLosslessSV1.mask | BoundedTransferSyntax.jpegLSLossless.mask
        if allowedTransferSyntaxMask & compressed != 0 {
            guard strictEncapsulation, maximumEncapsulatedBytes > 0 else { throw .invalidOptions }
            if let maximum = maxFragmentCount, maximum <= 0 { throw .invalidOptions }
        }
    }

    /// General-parser snapshot; its separate legacy String boundary retains the full allowlist.
    /// Arbitrary permissive options must not be rejected by this conversion.
    init(legacy options: ParsingOptions) {
        validationPolicy = options.validationPolicy
        mode = options.mode
        stopAfterTag = options.stopAfterTag
        maxElements = options.maxElements
        maxSequenceDepth = options.maxSequenceDepth
        maxElementLength = options.maxElementLength
        maxTotalElements = options.maxTotalElements
        maxFragmentCount = options.maxFragmentCount
        strictEncapsulation = options.strictEncapsulation
        maximumEncapsulatedBytes = options.maximumEncapsulatedBytes
        maximumInflatedByteCount = options.maximumInflatedByteCount
        strictResourceLimits = options.strictResourceLimits
        if let allowed = options.allowedTransferSyntaxUIDs {
            var mask: UInt8 = 0
            for uid in allowed {
                if let syntax = BoundedTransferSyntax.fromUID(uid) { mask |= syntax.mask }
            }
            allowedTransferSyntaxMask = mask
        } else {
            allowedTransferSyntaxMask = BoundedTransferSyntax.implicitLittleEndian.mask
                | BoundedTransferSyntax.explicitLittleEndian.mask
        }
    }

    func allows(_ syntax: BoundedTransferSyntax) -> Bool {
        allowedTransferSyntaxMask & syntax.mask != 0
    }
}
