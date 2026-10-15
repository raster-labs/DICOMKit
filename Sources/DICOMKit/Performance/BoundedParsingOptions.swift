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

    /// This syntax's bit in the scalar bounded-parser allowlist.
    public var mask: UInt8 { UInt8(1) << rawValue }
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
              options.stopAfterTag == nil else {
            throw .invalidOptions
        }
        var mask: UInt8 = 0x03
        if let allowed = options.allowedTransferSyntaxUIDs {
            mask = 0
            for uid in allowed {
                guard let syntax = BoundedTransferSyntax.fromUID(uid) else { throw .invalidOptions }
                mask |= syntax.mask
            }
        }
        guard let result = Self.make(allowedTransferSyntaxMask: mask, maxElements: options.maxElements,
            maxSequenceDepth: options.maxSequenceDepth, maxElementLength: options.maxElementLength,
            maxTotalElements: options.maxTotalElements, maxFragmentCount: options.maxFragmentCount,
            strictEncapsulation: options.strictEncapsulation,
            maximumEncapsulatedBytes: options.maximumEncapsulatedBytes,
            maximumInflatedByteCount: options.maximumInflatedByteCount,
            strictResourceLimits: options.strictResourceLimits) else { throw .invalidOptions }
        self = result
    }

    /// Construct strict full-read policy without a String, Set, legacy options or throwing path.
    /// This performs exactly the existing strict bounded-option validation. Optional caps
    /// that the legacy initializer retains without validation remain unchanged here.
    /// - Parameters:
    ///   - allowedTransferSyntaxMask: Union of `BoundedTransferSyntax.mask` bits; unknown bits refuse.
    ///     The default admits both native syntaxes. Zero preserves the legacy empty allowlist.
    ///   - maxElements: Optional positive top-level element cap.
    ///   - maxSequenceDepth: Existing general parser depth cap, retained unchanged.
    ///   - maxElementLength: Existing optional element-length cap, retained unchanged.
    ///   - maxTotalElements: Existing optional element-count cap, retained unchanged.
    ///   - maxFragmentCount: Must be positive when compressed syntaxes are enabled and it is supplied.
    ///   - strictEncapsulation: Required when compressed syntaxes are enabled.
    ///   - maximumEncapsulatedBytes: Must be positive when compressed syntaxes are enabled.
    ///   - maximumInflatedByteCount: Existing inflation cap, retained unchanged.
    ///   - strictResourceLimits: Every strict structural limit must be positive.
    /// - Returns: Scalar policy, or nil for the same invalid-options refusal as the legacy initializer.
    public static func make(allowedTransferSyntaxMask: UInt8 = 0x03, maxElements: Int? = nil,
        maxSequenceDepth: Int = 64, maxElementLength: Int? = nil, maxTotalElements: Int? = nil,
        maxFragmentCount: Int? = nil, strictEncapsulation: Bool = false,
        maximumEncapsulatedBytes: Int = 1 << 30, maximumInflatedByteCount: Int = 1 << 30,
        strictResourceLimits: ParsingOptions.StrictResourceLimits = .init()) -> Self? {
        guard allowedTransferSyntaxMask & ~UInt8(0x1f) == 0, strictResourceLimits.isValid else { return nil }
        if let maximum = maxElements, maximum <= 0 { return nil }
        if allowedTransferSyntaxMask & 0x1c != 0 {
            guard strictEncapsulation, maximumEncapsulatedBytes > 0 else { return nil }
            if let maximum = maxFragmentCount, maximum <= 0 { return nil }
        }
        return Self(allowedTransferSyntaxMask: allowedTransferSyntaxMask, maxElements: maxElements,
            maxSequenceDepth: maxSequenceDepth, maxElementLength: maxElementLength,
            maxTotalElements: maxTotalElements, maxFragmentCount: maxFragmentCount,
            strictEncapsulation: strictEncapsulation, maximumEncapsulatedBytes: maximumEncapsulatedBytes,
            maximumInflatedByteCount: maximumInflatedByteCount, strictResourceLimits: strictResourceLimits)
    }

    private init(allowedTransferSyntaxMask: UInt8, maxElements: Int?, maxSequenceDepth: Int,
        maxElementLength: Int?, maxTotalElements: Int?, maxFragmentCount: Int?, strictEncapsulation: Bool,
        maximumEncapsulatedBytes: Int, maximumInflatedByteCount: Int,
        strictResourceLimits: ParsingOptions.StrictResourceLimits) {
        validationPolicy = .strict
        mode = .full
        stopAfterTag = nil
        self.allowedTransferSyntaxMask = allowedTransferSyntaxMask
        self.maxElements = maxElements
        self.maxSequenceDepth = maxSequenceDepth
        self.maxElementLength = maxElementLength
        self.maxTotalElements = maxTotalElements
        self.maxFragmentCount = maxFragmentCount
        self.strictEncapsulation = strictEncapsulation
        self.maximumEncapsulatedBytes = maximumEncapsulatedBytes
        self.maximumInflatedByteCount = maximumInflatedByteCount
        self.strictResourceLimits = strictResourceLimits
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
