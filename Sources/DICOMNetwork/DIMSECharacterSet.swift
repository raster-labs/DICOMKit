import Foundation
import DICOMCore
// NEMA-verified: 2026a, checked 2026-09-28 — defined terms ISO_IR 100 / ISO_IR 192 and the inclusion rule checked against PS3.5 2026a §6.1.2 and PS3.4 C.4.1.1.3.1 / C.2.2.2

/// Chooses and applies the Specific Character Set (0008,0005) for the string
/// values of a DIMSE identifier or data set built by an SCU.
///
/// PS3.5 6.1.2 requires every character in a data set to be representable in
/// the declared character repertoire; PS3.4 C.4.1.1.3.1 requires the C-FIND
/// Identifier to carry (0008,0005) whenever its keys use anything beyond the
/// default repertoire. Encoding a value as ASCII when it contains non-ASCII
/// characters silently produced a zero-length element, i.e. a Universal Match.
///
/// Selection policy when the caller does not force a character set:
/// - all values are ISO 646 (ASCII): no (0008,0005) is needed
/// - all values fit ISO 8859-1: "ISO_IR 100" (the most widely supported set)
/// - otherwise: "ISO_IR 192" (UTF-8)
public struct DIMSECharacterSet: Sendable, Hashable {
    /// The value to write into (0008,0005), or nil when the default repertoire suffices
    public let specificCharacterSet: String?

    /// Creates a character set selection from an explicit defined term
    public init(specificCharacterSet: String?) {
        let trimmed = specificCharacterSet?.trimmingCharacters(in: .whitespaces)
        self.specificCharacterSet = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    /// Chooses the narrowest character set that can represent all `values`.
    public static func choose(for values: [String]) -> DIMSECharacterSet {
        var needsLatin1 = false
        for value in values {
            for scalar in value.unicodeScalars {
                if scalar.value > 0xFF {
                    return DIMSECharacterSet(specificCharacterSet: "ISO_IR 192")
                }
                if scalar.value > 0x7F { needsLatin1 = true }
            }
        }
        return DIMSECharacterSet(specificCharacterSet: needsLatin1 ? "ISO_IR 100" : nil)
    }

    /// Chooses a character set: the caller's override when given, else the
    /// narrowest one that represents `values`.
    public static func choose(for values: [String], override: String?) -> DIMSECharacterSet {
        if let override, !override.trimmingCharacters(in: .whitespaces).isEmpty {
            return DIMSECharacterSet(specificCharacterSet: override)
        }
        return choose(for: values)
    }

    /// The handler that encodes and decodes with this character set
    public var handler: CharacterSetHandler {
        CharacterSetHandler.from(specificCharacterSet: specificCharacterSet)
    }

    /// Encodes a text value. Non-representable characters are never dropped
    /// silently: if the declared set cannot encode the string, UTF-8 bytes are
    /// used so the value still reaches the wire with its full length.
    public func encode(_ value: String) -> Data {
        guard !value.isEmpty else { return Data() }
        let data = handler.encode(value)
        if data.isEmpty { return Data(value.utf8) }
        return data
    }

    /// Whether `value` is pure ISO 646 and needs no extended repertoire
    public static func isASCII(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { $0.value <= 0x7F }
    }
}
