import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import DICOMCore
import DICOMDictionary

/// Decoder for converting XML to DICOM DataSets
///
/// Implements parsing of the DICOM Native XML Model as specified in PS3.19 Annex A.1.
/// Numeric VRs (FL, FD, SL, SS, UL, US, SV, UV, AT) are converted from their character
/// data to the binary Value Field; private Data Elements (tag gggg00ee with a
/// privateCreator attribute) are placed in the block that their Private Creator owns in
/// the enclosing Data Set, allocating a block and its Private Creator element when needed.
///
/// NEMA-verified: 2026a, checked 2026-10-01 — a BulkData uri/uuid goes to the optional bulkDataResolver (PS3.19 Table A.1.5-2: a reference to retrievable data, D113); checked 2026-09-28 — elements and attributes read against PS3.19
/// 2026a Table A.1.5-2 and the A.1.6 schema (Value, Item, PersonName, BulkData uri/uuid,
/// InlineBinary; tag, vr, keyword, privateCreator); tests `DICOMXMLDecoderTests`,
/// `DICOMXMLModelConformanceTests`.
///
/// Reference: PS3.19 Annex A.1 - Native DICOM Model
public struct DICOMXMLDecoder: Sendable {
    /// Configuration for decoding options
    public struct Configuration: Sendable {
        /// Whether to allow missing VR attributes
        public let allowMissingVR: Bool
        
        /// Whether to fetch bulk data from URIs
        public let fetchBulkData: Bool
        
        /// Handler for bulk data URIs
        public let bulkDataHandler: (@Sendable (String) async throws -> Data)?
        
        /// Synchronous resolver for a `BulkData` reference (its `uri`, else its `uuid`;
        /// PS3.19 Table A.1.5-2): returns the element's Value Field, or nil when it cannot be
        /// retrieved — the element is then decoded with an empty Value Field. A throw is ignored.
        public let bulkDataResolver: (@Sendable (_ reference: String, _ tag: Tag) throws -> Data?)?
        
        /// Creates decoding configuration
        /// - Parameters:
        ///   - allowMissingVR: Allow missing VR (infer from tag dictionary)
        ///   - fetchBulkData: Fetch bulk data from URIs (default: false)
        ///   - bulkDataHandler: Custom handler for fetching bulk data
        ///   - bulkDataResolver: Synchronous BulkData resolver (default: none)
        public init(
            allowMissingVR: Bool = true,
            fetchBulkData: Bool = false,
            bulkDataHandler: (@Sendable (String) async throws -> Data)? = nil,
            bulkDataResolver: (@Sendable (_ reference: String, _ tag: Tag) throws -> Data?)? = nil
        ) {
            self.allowMissingVR = allowMissingVR
            self.fetchBulkData = fetchBulkData
            self.bulkDataHandler = bulkDataHandler
            self.bulkDataResolver = bulkDataResolver
        }
        
        /// Default configuration
        public static let `default` = Configuration()
    }
    
    /// The decoding configuration
    public let configuration: Configuration
    
    /// Creates an XML decoder with the specified configuration
    /// - Parameter configuration: Decoding configuration
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }
    
    /// Decodes XML data to a list of data elements
    /// - Parameter data: XML data to decode
    /// - Returns: Array of data elements
    /// - Throws: DICOMwebError if decoding fails
    public func decode(_ data: Data) throws -> [DataElement] {
        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw DICOMwebError.invalidXML(reason: "Failed to decode XML data as UTF-8")
        }
        return try decode(xmlString)
    }
    
    /// Decodes XML string to a list of data elements
    /// - Parameter xmlString: XML string to decode
    /// - Returns: Array of data elements
    /// - Throws: DICOMwebError if decoding fails
    public func decode(_ xmlString: String) throws -> [DataElement] {
        let parser = XMLParser(data: Data(xmlString.utf8))
        let delegate = ParserDelegate(configuration: configuration)
        parser.delegate = delegate
        
        guard parser.parse() else {
            if let error = parser.parserError {
                throw DICOMwebError.invalidXML(reason: "XML parsing failed: \(error.localizedDescription)")
            } else {
                throw DICOMwebError.invalidXML(reason: "XML parsing failed with unknown error")
            }
        }
        
        return delegate.elements
    }
    
    // MARK: - XML Parser Delegate
    
    private class ParserDelegate: NSObject, XMLParserDelegate {
        let configuration: Configuration
        var elements: [DataElement] = []
        
        // Stack for nested structures
        private var elementStack: [StackEntry] = []
        private var currentText = ""
        
        enum StackEntry {
            case attribute(tag: Tag, vr: VR?, values: [String], personNames: [PersonNameBuilder], items: [SequenceItem], binaryData: Data?, bulkDataURI: String?, privateCreator: String?)
            case item(elements: [DataElement])
            case personName(number: Int, alphabetic: PersonNameComponents?, ideographic: PersonNameComponents?, phonetic: PersonNameComponents?, currentGroup: PersonNameGroup?, components: PersonNameComponents)
            case value(number: Int, text: String)
            case inlineBinary(data: Data?)
            
            enum PersonNameGroup {
                case alphabetic
                case ideographic
                case phonetic
            }
        }
        
        struct PersonNameComponents {
            var familyName: String?
            var givenName: String?
            var middleName: String?
            var namePrefix: String?
            var nameSuffix: String?
            
            func toString() -> String {
                // DICOM PS3.5 PN: trailing empty components are dropped, so a
                // family+given name serialises as "Doe^John", not "Doe^John^^^".
                var parts = [familyName, givenName, middleName, namePrefix, nameSuffix]
                    .map { $0 ?? "" }
                while let last = parts.last, last.isEmpty {
                    parts.removeLast()
                }
                return parts.joined(separator: "^")
            }
        }
        
        struct PersonNameBuilder {
            var alphabetic: PersonNameComponents?
            var ideographic: PersonNameComponents?
            var phonetic: PersonNameComponents?
            
            func toString() -> String {
                let alpha = alphabetic?.toString() ?? ""
                let ideo = ideographic?.toString() ?? ""
                let phone = phonetic?.toString() ?? ""
                
                if !ideo.isEmpty || !phone.isEmpty {
                    return "\(alpha)=\(ideo)=\(phone)"
                } else {
                    return alpha
                }
            }
        }
        
        init(configuration: Configuration) {
            self.configuration = configuration
        }
        
        func parserDidEndDocument(_ parser: XMLParser) {
            elements = Self.resolvePrivateBlocks(elements)
        }
        
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
            switch elementName {
            case "NativeDicomModel":
                break
                
            case "DicomAttribute":
                guard let tagString = attributeDict["tag"],
                      let tag = parseTag(tagString) else {
                    return
                }
                
                let vr: VR?
                if let vrString = attributeDict["vr"] {
                    vr = VR(rawValue: vrString)
                } else if configuration.allowMissingVR {
                    // Try to infer from dictionary (use first VR)
                    vr = DataElementDictionary.lookup(tag: tag)?.vr.first
                } else {
                    vr = nil
                }
                
                // PS3.19 Table A.1.5-2: private Data Elements carry the Private Creator explicitly
                // and their tag has the form gggg00ee; the block is assigned when the Data Set ends
                let privateCreator = tag.isPrivate ? attributeDict["privateCreator"] : nil
                elementStack.append(.attribute(tag: tag, vr: vr, values: [], personNames: [], items: [], binaryData: nil, bulkDataURI: nil, privateCreator: privateCreator))
                
            case "Item":
                elementStack.append(.item(elements: []))
                
            case "PersonName":
                if let numberString = attributeDict["number"],
                   let number = Int(numberString) {
                    elementStack.append(.personName(number: number, alphabetic: nil, ideographic: nil, phonetic: nil, currentGroup: nil, components: PersonNameComponents()))
                }
                
            case "Alphabetic":
                if case .personName(let num, let alph, let ideo, let phone, _, let comp) = elementStack.last {
                    elementStack[elementStack.count - 1] = .personName(number: num, alphabetic: alph, ideographic: ideo, phonetic: phone, currentGroup: .alphabetic, components: comp)
                }
                
            case "Ideographic":
                if case .personName(let num, let alph, let ideo, let phone, _, let comp) = elementStack.last {
                    elementStack[elementStack.count - 1] = .personName(number: num, alphabetic: alph, ideographic: ideo, phonetic: phone, currentGroup: .ideographic, components: comp)
                }
                
            case "Phonetic":
                if case .personName(let num, let alph, let ideo, let phone, _, let comp) = elementStack.last {
                    elementStack[elementStack.count - 1] = .personName(number: num, alphabetic: alph, ideographic: ideo, phonetic: phone, currentGroup: .phonetic, components: comp)
                }
                
            case "FamilyName", "GivenName", "MiddleName", "NamePrefix", "NameSuffix", "Value":
                currentText = ""
                
            case "InlineBinary":
                currentText = ""
                
            case "BulkData":
                // uri (WADO-RS) or uuid (Application Hosting GetData); either is a reference only
                if let uri = attributeDict["uri"] ?? attributeDict["uuid"],
                   case .attribute(let tag, let vr, let vals, let pn, let items, _, _, let creator) = elementStack.last {
                    elementStack[elementStack.count - 1] = .attribute(tag: tag, vr: vr, values: vals, personNames: pn, items: items, binaryData: nil, bulkDataURI: uri, privateCreator: creator)
                }
                
            default:
                break
            }
        }
        
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            currentText += string
        }
        
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            
            switch elementName {
            case "Value":
                if case .attribute(let tag, let vr, var vals, let pn, let items, let bin, let uri, let creator) = elementStack.last {
                    vals.append(trimmed)
                    elementStack[elementStack.count - 1] = .attribute(tag: tag, vr: vr, values: vals, personNames: pn, items: items, binaryData: bin, bulkDataURI: uri, privateCreator: creator)
                }
                
            case "InlineBinary":
                if let data = Data(base64Encoded: trimmed, options: .ignoreUnknownCharacters),
                   case .attribute(let tag, let vr, let vals, let pn, let items, _, let uri, let creator) = elementStack.last {
                    elementStack[elementStack.count - 1] = .attribute(tag: tag, vr: vr, values: vals, personNames: pn, items: items, binaryData: data, bulkDataURI: uri, privateCreator: creator)
                }
                
            case "FamilyName":
                if case .personName(let num, let alph, let ideo, let phone, let group, var comp) = elementStack.last {
                    comp.familyName = trimmed
                    elementStack[elementStack.count - 1] = .personName(number: num, alphabetic: alph, ideographic: ideo, phonetic: phone, currentGroup: group, components: comp)
                }
                
            case "GivenName":
                if case .personName(let num, let alph, let ideo, let phone, let group, var comp) = elementStack.last {
                    comp.givenName = trimmed
                    elementStack[elementStack.count - 1] = .personName(number: num, alphabetic: alph, ideographic: ideo, phonetic: phone, currentGroup: group, components: comp)
                }
                
            case "MiddleName":
                if case .personName(let num, let alph, let ideo, let phone, let group, var comp) = elementStack.last {
                    comp.middleName = trimmed
                    elementStack[elementStack.count - 1] = .personName(number: num, alphabetic: alph, ideographic: ideo, phonetic: phone, currentGroup: group, components: comp)
                }
                
            case "NamePrefix":
                if case .personName(let num, let alph, let ideo, let phone, let group, var comp) = elementStack.last {
                    comp.namePrefix = trimmed
                    elementStack[elementStack.count - 1] = .personName(number: num, alphabetic: alph, ideographic: ideo, phonetic: phone, currentGroup: group, components: comp)
                }
                
            case "NameSuffix":
                if case .personName(let num, let alph, let ideo, let phone, let group, var comp) = elementStack.last {
                    comp.nameSuffix = trimmed
                    elementStack[elementStack.count - 1] = .personName(number: num, alphabetic: alph, ideographic: ideo, phonetic: phone, currentGroup: group, components: comp)
                }
                
            case "Alphabetic", "Ideographic", "Phonetic":
                if case .personName(let num, var alph, var ideo, var phone, let group, let comp) = elementStack.last {
                    switch group {
                    case .alphabetic:
                        alph = comp
                    case .ideographic:
                        ideo = comp
                    case .phonetic:
                        phone = comp
                    case .none:
                        break
                    }
                    elementStack[elementStack.count - 1] = .personName(number: num, alphabetic: alph, ideographic: ideo, phonetic: phone, currentGroup: nil, components: PersonNameComponents())
                }
                
            case "PersonName":
                guard case .personName(_, let alph, let ideo, let phone, _, _) = elementStack.popLast() else {
                    return
                }
                
                if case .attribute(let tag, let vr, let vals, var pn, let items, let bin, let uri, let creator) = elementStack.last {
                    let builder = PersonNameBuilder(alphabetic: alph, ideographic: ideo, phonetic: phone)
                    pn.append(builder)
                    elementStack[elementStack.count - 1] = .attribute(tag: tag, vr: vr, values: vals, personNames: pn, items: items, binaryData: bin, bulkDataURI: uri, privateCreator: creator)
                }
                
            case "Item":
                guard case .item(let itemElements) = elementStack.popLast() else {
                    return
                }
                
                if case .attribute(let tag, let vr, let vals, let pn, var items, let bin, let uri, let creator) = elementStack.last {
                    items.append(SequenceItem(elements: Self.resolvePrivateBlocks(itemElements)))
                    elementStack[elementStack.count - 1] = .attribute(tag: tag, vr: vr, values: vals, personNames: pn, items: items, binaryData: bin, bulkDataURI: uri, privateCreator: creator)
                }
                
            case "DicomAttribute":
                guard case .attribute(let tag, let vr, let vals, let personNames, let items, let binaryData, let bulkDataURI, let privateCreator) = elementStack.popLast() else {
                    return
                }
                
                guard let vrValue = vr else {
                    // Skip elements without VR
                    return
                }
                
                var element: DataElement
                
                // Handle sequences
                if vrValue == .SQ {
                    let element = DataElement(
                        tag: tag,
                        vr: .SQ,
                        length: 0xFFFFFFFF, // Undefined length for sequences
                        valueData: Data(),
                        sequenceItems: items
                    )
                    
                    // Add to parent structure
                    if case .item(var itemElements) = elementStack.last {
                        itemElements.append(element)
                        elementStack[elementStack.count - 1] = .item(elements: itemElements)
                    } else {
                        elements.append(element)
                    }
                    return
                }
                // Handle binary data
                else if let data = binaryData {
                    element = DataElement(tag: tag, vr: vrValue, length: UInt32(data.count), valueData: data)
                }
                // Handle bulk data URI (placeholder)
                else if let reference = bulkDataURI {
                    // Resolved through the configured resolver, else an empty Value Field
                    if let resolver = configuration.bulkDataResolver,
                       let data = (try? resolver(reference, tag)) ?? nil {
                        element = DataElement(tag: tag, vr: vrValue, length: UInt32(data.count), valueData: data)
                    } else {
                        element = DataElement(tag: tag, vr: vrValue, length: 0, valueData: Data())
                    }
                }
                // Handle person names
                else if vrValue == .PN && !personNames.isEmpty {
                    let pnStrings = personNames.map { $0.toString() }
                    let combinedString = pnStrings.joined(separator: "\\")
                    let data = Data(combinedString.utf8)
                    element = DataElement(tag: tag, vr: vrValue, length: UInt32(data.count), valueData: data)
                }
                // Handle regular values: numeric VRs are converted to their binary encoding
                else if !vals.isEmpty {
                    let data = Self.valueData(for: vals, vr: vrValue)
                    element = DataElement(tag: tag, vr: vrValue, length: UInt32(data.count), valueData: data)
                }
                // Empty element
                else {
                    element = DataElement(tag: tag, vr: vrValue, length: 0, valueData: Data())
                }
                
                if let privateCreator = privateCreator {
                    element = PrivateElement.pending(element, creator: privateCreator)
                }
                
                // Add to parent structure
                if case .item(var itemElements) = elementStack.last {
                    itemElements.append(element)
                    elementStack[elementStack.count - 1] = .item(elements: itemElements)
                } else {
                    elements.append(element)
                }
                
            default:
                break
            }
            
            currentText = ""
        }
        
        /// Encodes the character data of a numeric VR (PS3.19 Table A.1.5-2) as a little-endian
        /// Value Field; string VRs are joined with backslash (empty values preserved).
        static func valueData(for values: [String], vr: VR) -> Data {
            var data = Data()
            func append<T: FixedWidthInteger>(_ value: T) {
                var le = value.littleEndian
                data.append(Data(bytes: &le, count: MemoryLayout<T>.size))
            }
            switch vr {
            case .FL:
                for v in values { if let f = Float32(v) { append(f.bitPattern) } }
            case .FD:
                for v in values { if let f = Float64(v) { append(f.bitPattern) } }
            case .SL:
                for v in values { if let n = Int32(v) { append(n) } }
            case .SS:
                for v in values { if let n = Int16(v) { append(n) } }
            case .UL:
                for v in values { if let n = UInt32(v) { append(n) } }
            case .US:
                for v in values { if let n = UInt16(v) { append(n) } }
            case .SV:
                for v in values { if let n = Int64(v) { append(n) } }
            case .UV:
                for v in values { if let n = UInt64(v) { append(n) } }
            case .AT:
                for v in values where v.count == 8 {
                    if let group = UInt16(v.prefix(4), radix: 16), let element = UInt16(v.suffix(4), radix: 16) {
                        append(group)
                        append(element)
                    }
                }
            default:
                data = Data(values.joined(separator: "\\").utf8)
            }
            return data
        }
        
        /// Places every private element whose Private Creator was conveyed by the privateCreator
        /// attribute into the block that creator owns in this Data Set, allocating the first free
        /// block (0x10-0xFF) and its Private Creator element when the creator is new
        /// (PS3.5 7.8.1; PS3.19 Table A.1.5-2).
        static func resolvePrivateBlocks(_ elements: [DataElement]) -> [DataElement] {
            guard elements.contains(where: { PrivateElement.creator(of: $0) != nil }) else {
                return elements
            }
            var result: [DataElement] = []
            var pending: [(DataElement, String)] = []
            // creator string -> block, per private group
            var blocks: [UInt16: [String: UInt16]] = [:]
            var usedBlocks: [UInt16: Set<UInt16>] = [:]
            for element in elements {
                if let creator = PrivateElement.creator(of: element) {
                    pending.append((PrivateElement.unwrap(element), creator))
                } else {
                    result.append(element)
                    let tag = element.tag
                    if tag.isPrivate && tag.element >= 0x0010 && tag.element <= 0x00FF, let name = element.stringValue, !name.isEmpty {
                        blocks[tag.group, default: [:]][name] = tag.element
                        usedBlocks[tag.group, default: []].insert(tag.element)
                    }
                }
            }
            for (element, creator) in pending {
                let group = element.tag.group
                let block: UInt16
                if let existing = blocks[group]?[creator] {
                    block = existing
                } else {
                    var candidate: UInt16 = 0x0010
                    while usedBlocks[group, default: []].contains(candidate) && candidate < 0x00FF {
                        candidate += 1
                    }
                    block = candidate
                    blocks[group, default: [:]][creator] = block
                    usedBlocks[group, default: []].insert(block)
                    var creatorData = Data(creator.utf8)
                    if creatorData.count % 2 != 0 { creatorData.append(0x20) }
                    result.append(DataElement(tag: Tag(group: group, element: block), vr: .LO,
                                              length: UInt32(creatorData.count), valueData: creatorData))
                }
                let tag = Tag(group: group, element: (block << 8) | (element.tag.element & 0x00FF))
                if let items = element.sequenceItems {
                    result.append(DataElement(tag: tag, vr: element.vr, length: element.length, valueData: element.valueData, sequenceItems: items))
                } else {
                    result.append(DataElement(tag: tag, vr: element.vr, length: element.length, valueData: element.valueData))
                }
            }
            return result.sorted { $0.tag < $1.tag }
        }
        
        private func parseTag(_ tagString: String) -> Tag? {
            guard tagString.count == 8 else {
                return nil
            }
            
            let groupStr = String(tagString.prefix(4))
            let elemStr = String(tagString.suffix(4))
            
            guard let group = UInt16(groupStr, radix: 16),
                  let element = UInt16(elemStr, radix: 16) else {
                return nil
            }
            
            return Tag(group: group, element: element)
        }
    }
}


// MARK: - Private element bookkeeping

/// Carries the Private Creator of a private element from the DicomAttribute end event to the
/// end of its Data Set, where the block is assigned. The element is parked in a one-item
/// sequence under a reserved private tag so that no DataElement API needs to change.
private enum PrivateElement {
    static let marker = Tag(group: 0xFFFD, element: 0xFFFD)
    
    static func pending(_ element: DataElement, creator: String) -> DataElement {
        let creatorElement = DataElement(tag: Tag(group: 0xFFFD, element: 0x0010), vr: .LO,
                                         length: UInt32(creator.utf8.count), valueData: Data(creator.utf8))
        return DataElement(tag: marker, vr: .SQ, length: 0xFFFFFFFF, valueData: Data(),
                           sequenceItems: [SequenceItem(elements: [creatorElement, element])])
    }
    
    static func creator(of element: DataElement) -> String? {
        guard element.tag == marker, let item = element.sequenceItems?.first else { return nil }
        return item.allElements.first { $0.tag == Tag(group: 0xFFFD, element: 0x0010) }?.stringValue
    }
    
    static func unwrap(_ element: DataElement) -> DataElement {
        guard let item = element.sequenceItems?.first,
              let inner = item.allElements.first(where: { $0.tag != Tag(group: 0xFFFD, element: 0x0010) }) else {
            return element
        }
        return inner
    }
}
