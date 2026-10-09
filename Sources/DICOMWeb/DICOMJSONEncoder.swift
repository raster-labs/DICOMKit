import Foundation
import DICOMCore

/// Encoder for converting DICOM DataSets to JSON format
///
/// Implements the DICOM JSON Model as specified in PS3.18 Annex F.
/// Each attribute object is keyed by its eight-character uppercase hexadecimal tag,
/// carries `vr`, and at most one of `Value`, `BulkDataURI` or `InlineBinary` as
/// siblings of `vr` (PS3.18 F.2.2).
///
/// NEMA-verified: 2026a, checked 2026-10-01 — a BulkDataURI names its element's own Value
/// Field (PS3.18 F.2.6): `<base>/<GGGGEEEE>` at the top level, `<base>/<SQ tag>/<item n>/…/<GGGGEEEE>`
/// inside sequence items (D110); checked 2026-09-28 — VR-to-JSON types diffed against PS3.18 2026a
/// Table F.2.3-1 (34 / 34); object layout, ordering, Group Length exclusion, AT format, null
/// values, BulkDataURI/InlineBinary rules read against F.2.2-F.2.7 and PS3.19 Table A.1.5-2;
/// tests `DICOMJSONEncoderTests`, `DICOMJSONModelConformanceTests`.
///
/// Reference: PS3.18 Annex F - DICOM JSON Model
public struct DICOMJSONEncoder: Sendable {
    /// Configuration for encoding options
    public struct Configuration: Sendable {
        /// Whether to keep attributes whose Value Field is empty.
        ///
        /// PS3.18 F.2.5: an attribute that is present but empty "shall be preserved in the
        /// DICOM JSON attribute object containing no Value, BulkDataURI or InlineBinary",
        /// so the default is `true` and such an attribute is written as `{"vr": "XX"}`.
        /// Set it to `false` to drop empty attributes altogether.
        public let includeEmptyValues: Bool

        /// Whether to use inline binary (Base64) for bulk data
        public let inlineBinaryThreshold: Int?

        /// Base URL for generating bulk data URIs
        public let bulkDataBaseURL: URL?

        /// Whether to output pretty-printed JSON
        public let prettyPrinted: Bool

        /// Whether to sort keys alphabetically.
        ///
        /// PS3.18 F.2.2 requires attribute objects to be ordered by their property name in
        /// ascending lexicographic order, so the default is `true`.
        public let sortedKeys: Bool

        /// Creates encoding configuration
        /// - Parameters:
        ///   - includeEmptyValues: Keep empty attributes as `{"vr": ...}` (default: true, PS3.18 F.2.5)
        ///   - inlineBinaryThreshold: Inline binary up to this size in bytes (nil for always URI)
        ///   - bulkDataBaseURL: Base URL for bulk data URIs
        ///   - prettyPrinted: Pretty print JSON (default: false)
        ///   - sortedKeys: Sort keys (default: true, PS3.18 F.2.2)
        public init(
            includeEmptyValues: Bool = true,
            inlineBinaryThreshold: Int? = 1024,
            bulkDataBaseURL: URL? = nil,
            prettyPrinted: Bool = false,
            sortedKeys: Bool = true
        ) {
            self.includeEmptyValues = includeEmptyValues
            self.inlineBinaryThreshold = inlineBinaryThreshold
            self.bulkDataBaseURL = bulkDataBaseURL
            self.prettyPrinted = prettyPrinted
            self.sortedKeys = sortedKeys
        }

        /// Default configuration
        public static let `default` = Configuration()
    }

    /// The encoding configuration
    public let configuration: Configuration

    /// Creates a JSON encoder with the specified configuration
    /// - Parameter configuration: Encoding configuration
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    /// Encodes a list of data elements to JSON data
    /// - Parameter elements: The data elements to encode
    /// - Returns: JSON encoded data
    /// - Throws: DICOMwebError if encoding fails
    public func encode(_ elements: [DataElement]) throws -> Data {
        let jsonObject = try encodeToObject(elements)
        return try writer.data(with: jsonObject)
    }

    /// Encodes a list of data elements to a JSON string
    /// - Parameter elements: The data elements to encode
    /// - Returns: JSON string
    /// - Throws: DICOMwebError if encoding fails
    public func encodeToString(_ elements: [DataElement]) throws -> String {
        let data = try encode(elements)
        guard let string = String(data: data, encoding: .utf8) else {
            throw DICOMwebError.invalidJSON(reason: "Failed to create UTF-8 string")
        }
        return string
    }

    /// Encodes a list of data elements to a JSON-compatible dictionary
    ///
    /// Group Length (gggg,0000) attributes are not included (PS3.18 F.2.2).
    ///
    /// - Parameter elements: The data elements to encode
    /// - Returns: Dictionary representing the DICOM JSON
    /// - Throws: DICOMwebError if encoding fails
    public func encodeToObject(_ elements: [DataElement]) throws -> [String: Any] {
        try encodeToObject(elements, path: [])
    }

    /// `path`: the BulkDataURI path segments of the enclosing sequence items
    /// (`<SQ tag>`, `<item number from 1>`, …), so each URI names one element (D110).
    private func encodeToObject(_ elements: [DataElement], path: [String]) throws -> [String: Any] {
        var result: [String: Any] = [:]

        for element in elements where element.tag.element != 0x0000 {
            if let encoded = try encodeElement(element, path: path) {
                result[element.tag.hexString] = encoded
            }
        }

        return result
    }

    /// Encodes multiple data element lists (for search results)
    ///
    /// Multiple results are a single top-level JSON array of objects (PS3.18 F.2.1).
    ///
    /// - Parameter elementLists: Array of data element lists
    /// - Returns: JSON encoded data as array
    /// - Throws: DICOMwebError if encoding fails
    public func encodeMultiple(_ elementLists: [[DataElement]]) throws -> Data {
        let jsonArray = try elementLists.map { try encodeToObject($0) }
        return try writer.data(with: jsonArray)
    }
    
    // MARK: - Private Methods
    
    /// Writes with the attribute objects in ascending lexicographic tag order (PS3.18 F.2.2);
    /// `JSONSerialization.sortedKeys` orders "7FE00010" before "0020000D" and cannot be used.
    private var writer: DICOMJSONWriter {
        DICOMJSONWriter(prettyPrinted: configuration.prettyPrinted, sortedKeys: configuration.sortedKeys)
    }

    /// One attribute object: `vr` plus at most one of `Value`, `BulkDataURI`, `InlineBinary`
    /// (PS3.18 F.2.2). Returns nil when the attribute is empty and empty attributes are dropped.
    private func encodeElement(_ element: DataElement, path: [String]) throws -> [String: Any]? {
        var result: [String: Any] = ["vr": element.vr.rawValue]

        // Sequences: an array of DICOM JSON objects, empty items as empty objects (F.2.2, F.2.5)
        if element.vr == .SQ {
            let items = element.sequenceItems ?? []
            guard !items.isEmpty else {
                return configuration.includeEmptyValues ? result : nil
            }
            result["Value"] = try items.enumerated().map { index, item in
                try encodeToObject(item.allElements, path: path + [element.tag.hexString, String(index + 1)])
            }
            return result
        }

        // OB, OD, OF, OL, OV, OW, UN: the whole Value Field as one InlineBinary string or one
        // BulkDataURI, never per value (F.2.6, F.2.7)
        if isInlineBinaryVR(element.vr) {
            guard !element.valueData.isEmpty else {
                return configuration.includeEmptyValues ? result : nil
            }
            if shouldEncodeBulkData(element), let baseURL = configuration.bulkDataBaseURL {
                result["BulkDataURI"] = Self.bulkDataURI(base: baseURL, path: path, tag: element.tag)
            } else {
                result["InlineBinary"] = element.valueData.base64EncodedString()
            }
            return result
        }

        // Everything else goes in the "Value" array (F.2.4)
        let values: [Any]?
        if element.vr == .PN {
            values = encodePersonNames(element)
        } else if let stringValues = encodeStringValues(element) {
            values = stringValues
        } else if let numericValues = encodeNumericValues(element) {
            values = numericValues
        } else if element.valueData.isEmpty {
            values = nil
        } else if let stringValue = element.stringValue {
            values = [stringValue]
        } else {
            values = nil
        }

        guard let values = values, !values.isEmpty else {
            // Empty Value Field: no "Value" at all (F.2.5)
            return configuration.includeEmptyValues ? result : nil
        }
        result["Value"] = values
        return result
    }

    /// The BulkDataURI of one element: `<base>/<GGGGEEEE>` for a top-level element and
    /// `<base>/<SQ tag>/<item number>/…/<GGGGEEEE>` inside sequence items, so the same tag in
    /// two items or at two levels gets two URIs (PS3.18 F.2.6: the URI of that element's
    /// Bulk Data). Shared with `DICOMXMLEncoder`.
    static func bulkDataURI(base: URL, path: [String], tag: Tag) -> String {
        (path + [tag.hexString]).reduce(base) { $0.appendingPathComponent($1) }.absoluteString
    }

    private func shouldEncodeBulkData(_ element: DataElement) -> Bool {
        if let threshold = configuration.inlineBinaryThreshold {
            return element.valueData.count > threshold
        }
        return configuration.bulkDataBaseURL != nil
    }

    /// VRs whose Value Field is encoded as Base64 (PS3.18 Table F.2.3-1, F.2.7)
    private func isInlineBinaryVR(_ vr: VR) -> Bool {
        switch vr {
        case .OB, .OD, .OF, .OL, .OV, .OW, .UN:
            return true
        default:
            return false
        }
    }

    /// Splits a multi-valued string Value Field on 05/12 (backslash) keeping empty values
    /// (PS3.18 F.2.4 Note), trimmed of padding.
    private static func splitValues(_ element: DataElement) -> [String]? {
        guard let raw = element.stringValue else {
            return nil
        }
        let values = raw.components(separatedBy: "\\").map {
            $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
        }
        // A Value Field that is empty or padding only is an empty attribute
        if values.allSatisfy({ $0.isEmpty }) {
            return []
        }
        return values
    }

    /// String VRs of Table F.2.3-1. DS and IS are "Number or String"; they are written as
    /// strings to preserve their original format (F.2.3 Note). Empty values of a multi-valued
    /// attribute are `null` (F.2.5).
    private func encodeStringValues(_ element: DataElement) -> [Any]? {
        switch element.vr {
        case .AE, .AS, .CS, .DA, .DS, .DT, .IS, .LO, .LT, .SH, .ST, .TM, .UC, .UI, .UR, .UT:
            guard let values = Self.splitValues(element) else {
                return element.valueData.isEmpty ? [] : nil
            }
            return values.map { $0.isEmpty ? NSNull() : $0 as Any }
        default:
            return nil
        }
    }

    /// Numeric VRs of Table F.2.3-1 (JSON Numbers), and AT as the eight-character uppercase
    /// hexadecimal tag (F.2.3).
    private func encodeNumericValues(_ element: DataElement) -> [Any]? {
        switch element.vr {
        case .FL:
            return element.float32Values.map { $0.map { $0 as Any } }
        case .FD:
            return element.float64Values.map { $0.map { $0 as Any } }
        case .SL:
            return element.int32Values.map { $0.map { $0 as Any } }
        case .SS:
            return element.int16Values.map { $0.map { $0 as Any } }
        case .UL:
            return element.uint32Values.map { $0.map { $0 as Any } }
        case .US:
            return element.uint16Values.map { $0.map { $0 as Any } }
        case .SV:
            return element.int64Values.map { $0.map { Self.jsonValue(forInt64: $0) } }
        case .UV:
            return element.uint64Values.map { $0.map { Self.jsonValue(forUInt64: $0) } }
        case .AT:
            return element.attributeTagValues.map { $0.map { $0.hexString as Any } }
        default:
            return nil
        }
    }

    /// Largest integer magnitude a JSON Number carries exactly in IEEE 754 binary64
    /// (2^53 - 1), which is how most JSON consumers, including JavaScript, parse numbers.
    private static let maxExactJSONInteger: UInt64 = (1 << 53) - 1

    /// SV and UV are "Number or String" (PS3.18 Table F.2.3-1). Values that a binary64
    /// JSON Number cannot represent exactly are written as a String, as the Note to
    /// F.2.3 allows "to avoid losing precision".
    private static func jsonValue(forInt64 value: Int64) -> Any {
        value.magnitude <= maxExactJSONInteger ? value as Any : String(value)
    }

    private static func jsonValue(forUInt64 value: UInt64) -> Any {
        value <= maxExactJSONInteger ? value as Any : String(value)
    }

    /// PN: one object per value with the non-empty component groups `Alphabetic`,
    /// `Ideographic` and `Phonetic` as strings (PS3.18 F.2.2, Table F.3.1-1); an empty
    /// value of a multi-valued attribute is `null` (F.2.5).
    private func encodePersonNames(_ element: DataElement) -> [Any]? {
        guard let values = Self.splitValues(element) else {
            return element.valueData.isEmpty ? [] : nil
        }
        return values.map { value -> Any in
            guard !value.isEmpty else { return NSNull() }
            let groups = value.components(separatedBy: "=")
            var object: [String: Any] = [:]
            for (name, index) in [("Alphabetic", 0), ("Ideographic", 1), ("Phonetic", 2)] {
                if index < groups.count {
                    let group = groups[index].trimmingCharacters(in: .whitespaces)
                    if !group.isEmpty {
                        object[name] = group
                    }
                }
            }
            return object
        }
    }
}

// MARK: - Tag Extension

extension Tag {
    /// Returns the tag as an 8-character uppercase hexadecimal string (GGGGEEEE), the
    /// attribute name of the DICOM JSON Model (PS3.18 F.2.2) and the `tag` attribute of
    /// the Native DICOM Model (PS3.19 Table A.1.5-2).
    var hexString: String {
        return String(format: "%04X%04X", group, element)
    }
}
