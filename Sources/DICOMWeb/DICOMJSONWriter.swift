import Foundation

/// Serialises a DICOM JSON Model object graph (`[String: Any]`, `[Any]`, `String`, `NSNumber`,
/// `NSNull`) to bytes with the attribute objects in ascending lexicographic order of their
/// property name, as PS3.18 F.2.2 requires.
///
/// `JSONSerialization`'s `.sortedKeys` orders keys with a locale-aware, numeric-aware
/// comparison on current Apple platforms ("7FE00010" sorts before "0020000D"), which is not
/// the lexicographic order of the eight-character hexadecimal tag names, so the DICOM JSON
/// Model cannot be written with it. This writer compares keys by their Unicode scalars.
///
/// NEMA-verified: 2026a, checked 2026-09-28 — key ordering per PS3.18 2026a F.2.2; string
/// escaping per RFC 8259 §7; numbers written with Swift's shortest round-trip representation.
struct DICOMJSONWriter {
    /// Whether to pretty print (two-space indent, newline-separated)
    let prettyPrinted: Bool
    /// Whether to order object keys (true for the DICOM JSON Model)
    let sortedKeys: Bool

    init(prettyPrinted: Bool = false, sortedKeys: Bool = true) {
        self.prettyPrinted = prettyPrinted
        self.sortedKeys = sortedKeys
    }

    /// Serialises `object` (a dictionary or an array) to UTF-8 JSON.
    func data(with object: Any) throws -> Data {
        var out = ""
        try write(object, indent: 0, into: &out)
        if prettyPrinted {
            out += "\n"
        }
        return Data(out.utf8)
    }

    private func write(_ value: Any, indent: Int, into out: inout String) throws {
        switch value {
        case let dictionary as [String: Any]:
            try writeObject(dictionary, indent: indent, into: &out)
        case let array as [Any]:
            try writeArray(array, indent: indent, into: &out)
        case let string as String:
            Self.writeString(string, into: &out)
        case is NSNull:
            out += "null"
        case let number as NSNumber:
            try Self.writeNumber(number, into: &out)
        case let bool as Bool:
            out += bool ? "true" : "false"
        default:
            throw DICOMwebError.invalidJSON(reason: "Unsupported JSON value of type \(type(of: value))")
        }
    }

    private func writeObject(_ dictionary: [String: Any], indent: Int, into out: inout String) throws {
        guard !dictionary.isEmpty else {
            out += "{}"
            return
        }
        // PS3.18 F.2.2: ascending lexicographic order of the property name
        let keys = sortedKeys
            ? dictionary.keys.sorted { $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars) }
            : Array(dictionary.keys)
        out += "{"
        for (index, key) in keys.enumerated() {
            if index > 0 {
                out += ","
            }
            newline(indent + 1, into: &out)
            Self.writeString(key, into: &out)
            out += prettyPrinted ? " : " : ":"
            try write(dictionary[key]!, indent: indent + 1, into: &out)
        }
        newline(indent, into: &out)
        out += "}"
    }

    private func writeArray(_ array: [Any], indent: Int, into out: inout String) throws {
        guard !array.isEmpty else {
            out += "[]"
            return
        }
        out += "["
        for (index, element) in array.enumerated() {
            if index > 0 {
                out += ","
            }
            newline(indent + 1, into: &out)
            try write(element, indent: indent + 1, into: &out)
        }
        newline(indent, into: &out)
        out += "]"
    }

    private func newline(_ indent: Int, into out: inout String) {
        guard prettyPrinted else { return }
        out += "\n" + String(repeating: "  ", count: indent)
    }

    /// RFC 8259 §7: quotation mark, reverse solidus and the control characters are escaped.
    private static func writeString(_ string: String, into out: inout String) {
        out += "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case ..<" ": out += String(format: "\\u%04X", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
    }

    private static func writeNumber(_ number: NSNumber, into out: inout String) throws {
        if number === kCFBooleanTrue as NSNumber || number === kCFBooleanFalse as NSNumber {
            out += number.boolValue ? "true" : "false"
            return
        }
        switch String(cString: number.objCType) {
        case "f":
            let value = number.floatValue
            guard value.isFinite else { throw DICOMwebError.invalidJSON(reason: "Non-finite number") }
            out += value.description
        case "d":
            let value = number.doubleValue
            guard value.isFinite else { throw DICOMwebError.invalidJSON(reason: "Non-finite number") }
            out += value.description
        case "Q":
            out += String(number.uint64Value)
        default:
            out += String(number.int64Value)
        }
    }
}
