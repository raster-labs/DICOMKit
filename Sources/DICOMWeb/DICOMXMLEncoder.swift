import Foundation
import DICOMCore
import DICOMDictionary

/// Encoder for converting DICOM DataSets to XML format
///
/// Implements the DICOM Native XML Model as specified in PS3.19 Annex A.1.
/// The XML format uses the NativeDicomModel root element with DicomAttribute
/// elements for each DICOM tag.
///
/// NEMA-verified: 2026a, checked 2026-10-01 — PersonName number runs 1..n with an empty value
/// kept as `<PersonName number="n"/>` (Table A.1.5-2, D115); a BulkData uri names its element's
/// own Value Field, with the item path inside sequences (D110); checked 2026-09-28 — elements and attributes diffed against
/// PS3.19 2026a Table A.1.5-2 and the A.1.6 schema (34 VRs; Value / Item / PersonName /
/// BulkData / InlineBinary; tag, vr, keyword, privateCreator, uri); AT format and the
/// empty-value rule of A.1.5-2; xml:space="preserve" and the Group Length rule of A.1.1;
/// tests `DICOMXMLEncoderTests`, `DICOMXMLModelConformanceTests`.
///
/// Reference: PS3.19 Annex A.1 - Native DICOM Model
public struct DICOMXMLEncoder: Sendable {
    /// Configuration for encoding options
    public struct Configuration: Sendable {
        /// Whether to keep attributes whose Value Field is empty.
        ///
        /// PS3.19 Table A.1.5-2 defines every child of DicomAttribute as conditional on the
        /// Data Element not being zero length, so an empty attribute is written as an empty
        /// `<DicomAttribute/>`. The default is `true`; `false` drops empty attributes.
        public let includeEmptyValues: Bool

        /// Whether to use inline binary (Base64) for bulk data
        public let inlineBinaryThreshold: Int?

        /// Base URL for generating bulk data URIs
        public let bulkDataBaseURL: URL?

        /// Whether to output pretty-printed XML
        public let prettyPrinted: Bool

        /// Whether to include keyword attributes
        public let includeKeywords: Bool

        /// Creates encoding configuration
        /// - Parameters:
        ///   - includeEmptyValues: Keep empty attributes (default: true)
        ///   - inlineBinaryThreshold: Inline binary up to this size in bytes (nil for always URI)
        ///   - bulkDataBaseURL: Base URL for bulk data URIs
        ///   - prettyPrinted: Pretty print XML (default: false)
        ///   - includeKeywords: Include keyword attributes (default: true)
        public init(
            includeEmptyValues: Bool = true,
            inlineBinaryThreshold: Int? = 1024,
            bulkDataBaseURL: URL? = nil,
            prettyPrinted: Bool = false,
            includeKeywords: Bool = true
        ) {
            self.includeEmptyValues = includeEmptyValues
            self.inlineBinaryThreshold = inlineBinaryThreshold
            self.bulkDataBaseURL = bulkDataBaseURL
            self.prettyPrinted = prettyPrinted
            self.includeKeywords = includeKeywords
        }

        /// Default configuration
        public static let `default` = Configuration()
    }

    /// The XML namespace of the Native DICOM Model (PS3.19 A.1.6)
    public static let namespace = "http://dicom.nema.org/PS3.19/models/NativeDICOM"

    /// The encoding configuration
    public let configuration: Configuration

    /// Creates an XML encoder with the specified configuration
    /// - Parameter configuration: Encoding configuration
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    /// Encodes a list of data elements to XML data
    /// - Parameter elements: The data elements to encode
    /// - Returns: XML encoded data
    /// - Throws: DICOMwebError if encoding fails
    public func encode(_ elements: [DataElement]) throws -> Data {
        let xmlString = try encodeToString(elements)
        guard let data = xmlString.data(using: .utf8) else {
            throw DICOMwebError.invalidXML(reason: "Failed to encode XML string to UTF-8 data")
        }
        return data
    }

    /// Encodes a list of data elements to an XML string
    ///
    /// The root element carries `xml:space="preserve"` (PS3.19 Table A.1.5-1) and Group
    /// Length (gggg,0000) attributes are not included (A.1.1).
    ///
    /// - Parameter elements: The data elements to encode
    /// - Returns: XML string
    /// - Throws: DICOMwebError if encoding fails
    public func encodeToString(_ elements: [DataElement]) throws -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<NativeDicomModel xmlns=\"\(Self.namespace)\" xml:space=\"preserve\">\n"
        xml += try encodeDataSet(elements, indent: configuration.prettyPrinted ? "  " : "", path: [])
        xml += "</NativeDicomModel>\n"
        return xml
    }

    /// Encodes one Data Set (the root or a sequence item)
    /// `path`: the BulkData uri segments of the enclosing items (`<SQ tag>`, `<item number>`).
    private func encodeDataSet(_ elements: [DataElement], indent: String, path: [String]) throws -> String {
        var xml = ""
        let creators = Self.privateCreators(in: elements)
        for element in elements where element.tag.element != 0x0000 {
            // An SQ element carries its content in `sequenceItems`, not
            // `valueData` — `valueData` is always empty for sequences.
            let hasSequenceItems = !(element.sequenceItems?.isEmpty ?? true)
            if !configuration.includeEmptyValues && element.valueData.isEmpty && !hasSequenceItems {
                continue
            }
            xml += try encodeElement(element, privateCreator: creators[element.tag], indent: indent, path: path)
        }
        return xml
    }

    /// The Private Creator (gggg,00xx) of every private Data Element (gggg,xxee) in a Data Set
    private static func privateCreators(in elements: [DataElement]) -> [Tag: String] {
        var creatorsByBlock: [Tag: String] = [:]
        for element in elements where element.tag.isPrivate && element.tag.element >= 0x0010 && element.tag.element <= 0x00FF {
            if let creator = element.stringValue, !creator.isEmpty {
                creatorsByBlock[element.tag] = creator
            }
        }
        var result: [Tag: String] = [:]
        for element in elements where element.tag.isPrivate && element.tag.element > 0x00FF {
            let block = Tag(group: element.tag.group, element: element.tag.element >> 8)
            if let creator = creatorsByBlock[block] {
                result[element.tag] = creator
            }
        }
        return result
    }

    /// Encodes a single data element to XML
    private func encodeElement(_ element: DataElement, privateCreator: String?, indent: String,
                               path: [String]) throws -> String {
        // Private Data Elements have the form gggg00ee, since the Private Creator is conveyed
        // explicitly and the block used in the DICOM encoding is not sent (PS3.19 Table A.1.5-2)
        let tag: String
        if let privateCreator = privateCreator {
            tag = String(format: "%04X00%02X", element.tag.group, element.tag.element & 0xFF)
        } else {
            tag = element.tag.hexString
        }
        let vr = element.vr.rawValue

        var attributes = "tag=\"\(tag)\" vr=\"\(vr)\""

        // Add keyword if enabled ("Required unless the DICOM Data Element is unknown to the host")
        if configuration.includeKeywords, privateCreator == nil,
           let entry = DataElementDictionary.lookup(tag: element.tag) {
            attributes += " keyword=\"\(entry.keyword)\""
        }
        if let privateCreator = privateCreator {
            attributes += " privateCreator=\"\(escapeXML(privateCreator))\""
        }

        var xml = "\(indent)<DicomAttribute \(attributes)>\n"

        // Handle sequences
        if element.vr == .SQ, let sequence = element.sequenceItems {
            for (index, item) in sequence.enumerated() {
                xml += "\(indent)  <Item number=\"\(index + 1)\">\n"
                xml += try encodeDataSet(item.allElements, indent: indent + "    ",
                                         path: path + [element.tag.hexString, String(index + 1)])
                xml += "\(indent)  </Item>\n"
            }
        }
        // Handle binary bulk data (OB, OD, OF, OL, OV, OW, UN): one InlineBinary or BulkData for
        // the whole Value Field
        else if isBinaryVR(element.vr) {
            if !element.valueData.isEmpty {
                let shouldInline: Bool
                if let threshold = configuration.inlineBinaryThreshold {
                    shouldInline = element.valueData.count <= threshold
                } else {
                    shouldInline = false
                }

                if shouldInline {
                    let base64 = element.valueData.base64EncodedString()
                    xml += "\(indent)  <InlineBinary>\(base64)</InlineBinary>\n"
                } else if let baseURL = configuration.bulkDataBaseURL {
                    // One URI per element: the item path inside sequences, and the full
                    // (gggg,xxee) tag of a private element, so no two elements share one (D110)
                    let uri = DICOMJSONEncoder.bulkDataURI(base: baseURL, path: path, tag: element.tag)
                    xml += "\(indent)  <BulkData uri=\"\(escapeXML(uri))\"/>\n"
                } else {
                    // Default to inline if no base URL specified
                    let base64 = element.valueData.base64EncodedString()
                    xml += "\(indent)  <InlineBinary>\(base64)</InlineBinary>\n"
                }
            }
        }
        // Handle PersonName specially: one PersonName per value, numbered 1..n by 1 with an
        // empty value kept as <PersonName number="n"/> (Table A.1.5-2; the A.1.6 schema
        // makes every name component group optional) — D115
        else if element.vr == .PN {
            for (index, value) in Self.stringValues(of: element).enumerated() {
                xml += encodePersonName(value, number: index + 1, indent: indent + "  ")
            }
        }
        // Handle other values: one Value per DICOM value, empty values included (Table A.1.5-2)
        else {
            for (index, value) in Self.valueStrings(of: element).enumerated() {
                xml += "\(indent)  <Value number=\"\(index + 1)\">\(escapeXML(value))</Value>\n"
            }
        }

        xml += "\(indent)</DicomAttribute>\n"
        return xml
    }

    /// The values of a string VR, split on backslash with empty values kept ("MPG\\XR3" is
    /// three values, the second empty) and padding trimmed; a Value Field that is empty or
    /// padding only has no values.
    static func stringValues(of element: DataElement) -> [String] {
        guard let raw = element.stringValue else {
            return []
        }
        let values = raw.components(separatedBy: "\\").map {
            $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
        }
        return values.allSatisfy({ $0.isEmpty }) ? [] : values
    }

    /// Every value of a non-binary, non-PN, non-SQ element as plain character data:
    /// numeric VRs from their binary encoding, AT as the eight-character uppercase
    /// hexadecimal tag (PS3.19 Table A.1.5-2), the rest as strings.
    static func valueStrings(of element: DataElement) -> [String] {
        switch element.vr {
        case .FL:
            return (element.float32Values ?? []).map { $0.description }
        case .FD:
            return (element.float64Values ?? []).map { $0.description }
        case .SL:
            return (element.int32Values ?? []).map { String($0) }
        case .SS:
            return (element.int16Values ?? []).map { String($0) }
        case .UL:
            return (element.uint32Values ?? []).map { String($0) }
        case .US:
            return (element.uint16Values ?? []).map { String($0) }
        case .SV:
            return (element.int64Values ?? []).map { String($0) }
        case .UV:
            return (element.uint64Values ?? []).map { String($0) }
        case .AT:
            return (element.attributeTagValues ?? []).map { $0.hexString }
        default:
            return stringValues(of: element)
        }
    }

    /// Encodes a PersonName value
    private func encodePersonName(_ value: String, number: Int, indent: String) -> String {
        if value.isEmpty { return "\(indent)<PersonName number=\"\(number)\"/>\n" }
        var xml = "\(indent)<PersonName number=\"\(number)\">\n"

        // Parse PersonName component groups (Alphabetic=Ideographic=Phonetic)
        let components = value.split(separator: "=", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)

        // Alphabetic component (required)
        if !components.isEmpty && !components[0].isEmpty {
            xml += "\(indent)  <Alphabetic>\n"
            xml += encodePersonNameComponent(components[0], indent: indent + "    ")
            xml += "\(indent)  </Alphabetic>\n"
        }

        // Ideographic component (optional)
        if components.count > 1 && !components[1].isEmpty {
            xml += "\(indent)  <Ideographic>\n"
            xml += encodePersonNameComponent(components[1], indent: indent + "    ")
            xml += "\(indent)  </Ideographic>\n"
        }

        // Phonetic component (optional)
        if components.count > 2 && !components[2].isEmpty {
            xml += "\(indent)  <Phonetic>\n"
            xml += encodePersonNameComponent(components[2], indent: indent + "    ")
            xml += "\(indent)  </Phonetic>\n"
        }

        xml += "\(indent)</PersonName>\n"
        return xml
    }

    /// Encodes a PersonName component group (Family^Given^Middle^Prefix^Suffix)
    private func encodePersonNameComponent(_ component: String, indent: String) -> String {
        let parts = component.split(separator: "^", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
        var xml = ""

        if !parts.isEmpty && !parts[0].isEmpty {
            xml += "\(indent)<FamilyName>\(escapeXML(parts[0]))</FamilyName>\n"
        }
        if parts.count > 1 && !parts[1].isEmpty {
            xml += "\(indent)<GivenName>\(escapeXML(parts[1]))</GivenName>\n"
        }
        if parts.count > 2 && !parts[2].isEmpty {
            xml += "\(indent)<MiddleName>\(escapeXML(parts[2]))</MiddleName>\n"
        }
        if parts.count > 3 && !parts[3].isEmpty {
            xml += "\(indent)<NamePrefix>\(escapeXML(parts[3]))</NamePrefix>\n"
        }
        if parts.count > 4 && !parts[4].isEmpty {
            xml += "\(indent)<NameSuffix>\(escapeXML(parts[4]))</NameSuffix>\n"
        }

        return xml
    }

    /// VRs whose Value Field is carried as InlineBinary or BulkData (PS3.19 A.1.5-2; the same
    /// set as PS3.18 Table F.2.3-1 "Base64 encoded octet-stream")
    private func isBinaryVR(_ vr: VR) -> Bool {
        switch vr {
        case .OB, .OD, .OF, .OL, .OV, .OW, .UN:
            return true
        default:
            return false
        }
    }

    /// Escapes special XML characters
    private func escapeXML(_ string: String) -> String {
        var escaped = string
        escaped = escaped.replacingOccurrences(of: "&", with: "&amp;")
        escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
        escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
        escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
        escaped = escaped.replacingOccurrences(of: "'", with: "&apos;")
        return escaped
    }
}
