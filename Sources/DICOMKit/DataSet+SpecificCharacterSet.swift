// NEMA-verified: 2026a, checked 2026-10-01 — Specific Character Set (0008,0005) Type 1C "Required if an expanded or replacement character set is used" (PS3.3 2026a Table C.12-1), Defined Term "ISO_IR 192" = Unicode in UTF-8 (Table C.12-5); the VRs it affects are SH, LO, ST, LT, PN, UC, UT (PS3.5 2026a 6.1.2.3) — dumped from the DocBook by script
import Foundation
import DICOMCore

extension DataSet {

    /// Specific Character Set (0008,0005) Defined Term for Unicode in UTF-8
    /// (PS3.3 2026a Table C.12-5).
    static let utf8SpecificCharacterSet = "ISO_IR 192"

    /// The string VRs whose repertoire Specific Character Set extends (PS3.5 6.1.2.3).
    static let characterSetDependentVRs: Set<VR> = [.SH, .LO, .ST, .LT, .PN, .UC, .UT]

    /// Whether any SH, LO, ST, LT, PN, UC or UT value in this data set, or in an
    /// Item of one of its Sequences, holds a byte outside the Default Character
    /// Repertoire (a byte of 0x80 or more).
    func containsNonASCIIText() -> Bool {
        Self.containsNonASCIIText(in: Array(self))
    }

    private static func containsNonASCIIText(in elements: [DataElement]) -> Bool {
        for element in elements {
            if let items = element.sequenceItems {
                for item in items where containsNonASCIIText(in: Array(item.elements.values)) {
                    return true
                }
            } else if characterSetDependentVRs.contains(element.vr),
                      element.valueData.contains(where: { $0 >= 0x80 }) {
                return true
            }
        }
        return false
    }

    /// Sets Specific Character Set (0008,0005) to `ISO_IR 192` when it is absent and a
    /// text value is not ASCII. DICOMKit encodes string values as UTF-8, and the
    /// attribute is Type 1C, "Required if an expanded or replacement character set is
    /// used" (PS3.3 2026a Table C.12-1). An existing value is left alone.
    mutating func setUTF8SpecificCharacterSetIfNeeded() {
        guard self[.specificCharacterSet] == nil, containsNonASCIIText() else { return }
        setString(Self.utf8SpecificCharacterSet, for: .specificCharacterSet, vr: .CS)
    }
}

/// A text conversion failed rather than silently substituting characters.
public struct DICOMTextEncodingError: Error, LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }
}

extension DataSet {
    /// Attach the effective declaration to raw text, recursively. Item declarations
    /// override their enclosing dataset; otherwise that context is inherited.
    static func bindingTextContext(in elements: [Tag: DataElement], inherited: String) -> [Tag: DataElement] {
        let charset = elements[.specificCharacterSet]?.stringValue ?? inherited
        return elements.mapValues { element in
            if let items = element.sequenceItems {
                let bound = items.map { SequenceItem(elements: bindingTextContext(in: $0.elements, inherited: charset)) }
                return DataElement(tag: element.tag, vr: element.vr, length: element.length,
                                   valueData: element.valueData, sequenceItems: bound, byteOrder: element.byteOrder)
            }
            return element.bindingSpecificCharacterSet(charset)
        }
    }

    /// Converts every charset-dependent text value, including nested Items, as one
    /// transaction. Existing Item overrides are converted too. No byte stream is
    /// merely relabelled, and an unrepresentable/undecodable value fails the operation.
    /// Set `preservingItemOverrides` when changing only the root declaration: an
    /// explicit Item declaration remains its own encoding boundary.
    public func transcodingText(to specificCharacterSet: String = "ISO_IR 192",
                                preservingItemOverrides: Bool = false) throws -> DataSet {
        guard CharacterSetHandler.isSupported(specificCharacterSet: specificCharacterSet) else {
            throw DICOMTextEncodingError(message: "Unsupported Specific Character Set: \(specificCharacterSet)")
        }
        let converted = try Self.transcodeText(in: Dictionary(uniqueKeysWithValues: map { ($0.tag, $0) }), inherited: "",
                                              target: specificCharacterSet, path: "DataSet",
                                              preservingItemOverrides: preservingItemOverrides)
        var result = DataSet(elements: Array(converted.values))
        result.setString(specificCharacterSet, for: .specificCharacterSet, vr: .CS)
        return result
    }

    private static func transcodeText(in elements: [Tag: DataElement], inherited: String,
                                      target: String, path: String,
                                      preservingItemOverrides: Bool) throws -> [Tag: DataElement] {
        guard CharacterSetHandler.isSupported(specificCharacterSet: target) else {
            throw DICOMTextEncodingError(message: "\(path): unsupported Specific Character Set '\(target)'")
        }
        let declaration = elements[.specificCharacterSet]?.stringValue ?? inherited
        var result = elements
        for (tag, element) in elements {
            let location = "\(path)/\(tag)"
            if let items = element.sequenceItems {
                let converted = try items.enumerated().map { index, item in
                    let itemTarget = preservingItemOverrides
                        ? (item.elements[.specificCharacterSet]?.stringValue ?? target) : target
                    return SequenceItem(elements: try transcodeText(in: item.elements, inherited: declaration,
                        target: itemTarget, path: "\(location)[\(index)]",
                        preservingItemOverrides: preservingItemOverrides))
                }
                result[tag] = DataElement(tag: tag, vr: .SQ, length: element.length, valueData: Data(),
                                          sequenceItems: converted, byteOrder: element.byteOrder)
            } else if characterSetDependentVRs.contains(element.vr) {
                let source = element.specificCharacterSet ?? declaration
                guard let decoded = CharacterSetHandler.decodeStrict(element.valueData, specificCharacterSet: source) else {
                    throw DICOMTextEncodingError(message: "\(location) \(element.vr): cannot decode Specific Character Set '\(source)'")
                }
                let text = DataElement.removingValuePadding(decoded, vr: element.vr)
                let handler = CharacterSetHandler.from(specificCharacterSet: target)
                var bytes = handler.encode(text)
                guard CharacterSetHandler.decodeStrict(bytes, specificCharacterSet: target) == text else {
                    throw DICOMTextEncodingError(message: "\(location) \(element.vr): value cannot be represented in '\(target)'")
                }
                if bytes.count % 2 != 0 { bytes.append(0x20) }
                result[tag] = DataElement(tag: tag, vr: element.vr, length: UInt32(bytes.count),
                                          valueData: bytes, specificCharacterSet: target)
            }
        }
        if elements[.specificCharacterSet] != nil {
            result[.specificCharacterSet] = .string(tag: .specificCharacterSet, vr: .CS, value: target)
        }
        return result
    }

    /// Preserve an unchanged legacy encoding. If newly-created/copy-in text has a
    /// different repertoire, convert the complete dataset before writing a file.
    func preparingTextForWriting() throws -> DataSet {
        if Self.needsTextNormalization(in: Dictionary(uniqueKeysWithValues: map { ($0.tag, $0) }), inherited: "") {
            return try transcodingText()
        }
        try Self.validateTextEncoding(in: Dictionary(uniqueKeysWithValues: map { ($0.tag, $0) }), inherited: "", path: "DataSet")
        return self
    }

    private static func validateTextEncoding(in elements: [Tag: DataElement], inherited: String, path: String) throws {
        let charset = elements[.specificCharacterSet]?.stringValue ?? inherited
        for element in elements.values {
            if let items = element.sequenceItems {
                for (index, item) in items.enumerated() {
                    try validateTextEncoding(in: item.elements, inherited: charset,
                                             path: "\(path)/\(element.tag)[\(index)]")
                }
            } else if characterSetDependentVRs.contains(element.vr),
                      CharacterSetHandler.decodeStrict(element.valueData, specificCharacterSet: charset) == nil {
                throw DICOMTextEncodingError(message: "\(path)/\(element.tag) \(element.vr): invalid bytes for Specific Character Set '\(charset)'")
            }
        }
    }

    private static func needsTextNormalization(in elements: [Tag: DataElement], inherited: String) -> Bool {
        let charset = elements[.specificCharacterSet]?.stringValue ?? inherited
        for element in elements.values {
            if let items = element.sequenceItems {
                if items.contains(where: { needsTextNormalization(in: $0.elements, inherited: charset) }) { return true }
            } else if characterSetDependentVRs.contains(element.vr),
                      element.valueData.contains(where: { $0 >= 0x80 || $0 == 0x1B }),
                      let actual = element.specificCharacterSet, actual != charset {
                return true
            }
        }
        return false
    }
}
