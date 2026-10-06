// NEMA-verified: 2026a, checked 2026-10-06 — lifted from dicom-pdf EncapsulationAttributes.swift (D272) and re-read against the 2026a DocBook: PS3.3 Table C.24-2 Encapsulated Document Length (0042,0015) Type 3 "not including any trailing padding … If present, shall be equal to the Value Length if even, or one less than the Value Length if odd" (UL per PS3.6 Table 6-1; cut via EncapsulatedDocumentParser.documentStream, D181), Burned In Annotation (0028,0301) Type 1 YES / NO, HL7 Instance Identifier (0040,E001) Type 1C "Required if encapsulated document is a CDA document", "encoded as a UID (OID or UUID), concatenated with a caret ("^") and Extension value (if Extension is present)"; Conversion Type (0008,0064) Defined Terms of Table C.8-24 (via conversionTypeDefinedTerms); Specific Character Set (0008,0005) Type 1C (Table C.12-1), ISO_IR 192 = Unicode in UTF-8 (Table C.12-5), via DataSet.setUTF8SpecificCharacterSetIfNeeded (D166)
//
// EncapsulatedDocumentBuilder+OptionRules.swift
// DICOMKit
//
// The encapsulation option vocabularies and attribute completion that `dicom-pdf` and
// DICOMStudio's CLI Workshop share (the Workshop carried a text-identical copy,
// WorkshopPDFEncapsulation). Pure: no I/O.
//

import Foundation
import DICOMCore

extension EncapsulatedDocumentBuilder {

    /// Option vocabularies and the attributes added around ``EncapsulatedDocumentBuilder`` /
    /// ``EncapsulatedDocumentParser`` for an encapsulation tool.
    public enum OptionRules {

        /// An option value outside its vocabulary; `description` is the text to print.
        public struct ValidationError: Error, LocalizedError, CustomStringConvertible, Equatable, Sendable {
            public let message: String
            public init(_ message: String) { self.message = message }
            public var description: String { message }
            public var errorDescription: String? { message }
        }

        /// Encapsulated Document Length (0042,0015), UL (PS3.3 Table C.24-2, Type 3).
        public static let encapsulatedDocumentLength = EncapsulatedDocumentParser.encapsulatedDocumentLengthTag

        /// PS3.3 2026a Table C.8-24 Conversion Type (0008,0064) Defined Terms, in table order.
        public static let conversionTypes = EncapsulatedDocumentBuilder.conversionTypeDefinedTerms

        /// Default Conversion Type: the document was produced on a workstation.
        public static let defaultConversionType = EncapsulatedDocumentBuilder.defaultConversionType

        /// Burned In Annotation (0028,0301) values (PS3.3 Table C.24-2).
        public static let burnedInAnnotationValues = ["YES", "NO"]

        /// Specific Character Set Defined Term for UTF-8 (PS3.3 Table C.12-5).
        public static let utf8CharacterSet = "ISO_IR 192"

        // MARK: - Option values

        /// Validates a Conversion Type option (case-insensitive) and returns the Defined Term.
        public static func conversionType(_ raw: String) throws -> String {
            let value = raw.uppercased()
            guard conversionTypes.contains(value) else {
                throw ValidationError("--conversion-type \(raw) is not a Conversion Type (0008,0064) Defined Term of PS3.3 Table C.8-24: \(conversionTypes.joined(separator: ", "))")
            }
            return value
        }

        /// Validates a Burned In Annotation option (case-insensitive): `true` for YES.
        public static func burnedInAnnotation(_ raw: String) throws -> Bool {
            switch raw.uppercased() {
            case "YES": return true
            case "NO": return false
            default:
                throw ValidationError("--burned-in-annotation \(raw) is not YES or NO (Burned In Annotation (0028,0301), PS3.3 Table C.24-2)")
            }
        }

        /// The HL7 Instance Identifier of a CDA document: `root^extension` (or `root`)
        /// of the first `<id>` child of `<ClinicalDocument>`, as Table C.24-2 defines it.
        public static func hl7InstanceIdentifier(fromCDA data: Data) -> String? {
            let finder = ClinicalDocumentIDFinder()
            let parser = XMLParser(data: data)
            parser.shouldProcessNamespaces = true
            parser.delegate = finder
            parser.parse()
            guard let root = finder.root, !root.isEmpty else { return nil }
            if let ext = finder.extensionValue, !ext.isEmpty { return "\(root)^\(ext)" }
            return root
        }

        // MARK: - Dataset completion and extraction

        /// Sets Encapsulated Document Length (0042,0015) to the unpadded byte count, and
        /// Specific Character Set (0008,0005) `ISO_IR 192` when a string value (also inside
        /// a Sequence Item) is not ASCII. ``EncapsulatedDocumentBuilder/buildDataSet()``
        /// already writes both; this completes a data set built elsewhere.
        public static func complete(_ dataSet: inout DataSet, documentByteCount: Int) {
            dataSet[encapsulatedDocumentLength] = DataElement.uint32(
                tag: encapsulatedDocumentLength, value: UInt32(clamping: documentByteCount))
            dataSet.setUTF8SpecificCharacterSetIfNeeded()
        }

        /// Whether any SH, LO, ST, LT, PN, UC or UT value (also inside a Sequence Item)
        /// holds a byte outside the Default Character Repertoire (PS3.5 6.1.2.3).
        public static func hasNonASCIIText(_ dataSet: DataSet) -> Bool {
            dataSet.containsNonASCIIText()
        }

        /// The document bytes without the trailing padding, through
        /// ``EncapsulatedDocumentParser/documentStream(_:in:)``: cut to Encapsulated Document
        /// Length (0042,0015) when that is one less than the value length, as Table C.24-2
        /// allows ("equal to the Value Length if even, or one less than the Value Length if
        /// odd"); otherwise the value as stored.
        public static func documentBytes(_ value: Data, in dataSet: DataSet) -> Data {
            EncapsulatedDocumentParser.documentStream(value, in: dataSet)
        }
    }
}

/// Finds `/ClinicalDocument/id/@root` and `@extension` (HL7 CDA R2).
private final class ClinicalDocumentIDFinder: NSObject, XMLParserDelegate {
    var root: String?
    var extensionValue: String?
    private var depth = 0
    private var isClinicalDocument = false

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        depth += 1
        if depth == 1 {
            isClinicalDocument = elementName == "ClinicalDocument"
            if !isClinicalDocument { parser.abortParsing() }
        }
        if depth == 2, isClinicalDocument, elementName == "id", root == nil {
            root = attributes["root"]
            extensionValue = attributes["extension"]
            parser.abortParsing()
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        depth -= 1
    }
}
