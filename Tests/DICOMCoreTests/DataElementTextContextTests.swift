import Foundation
import Testing
@testable import DICOMCore

@Suite("M2 DataElement text context")
struct DataElementTextContextTests {
    @Test("Full decoded value retains whitespace while accessors remove only field padding")
    func significantWhitespace() {
        let element = DataElement.string(tag: Tag(group: 0x0040, element: 0xA160), vr: .UT, value: "  first\\ second\n")
        #expect(element.stringValue == "  first\\ second\n")
        #expect(element.stringValues == ["  first\\ second\n"])
        let multiple = DataElement.string(tag: .imageType, vr: .LO, value: "  first\\ second")
        #expect(multiple.stringValues == ["  first", " second"])
        #expect(element.decodedStringValue?.hasPrefix("  first") == true)
        let invalidUID = DataElement.string(tag: .sopInstanceUID, vr: .UI, value: " 1.2.3 ")
        #expect(invalidUID.stringValue == " 1.2.3 ")
    }

    @Test("Literal Latin-1 bytes decode after a declared context is bound")
    func boundLatin1() {
        let bytes = Data([0x4D,0xFC,0x6C,0x6C,0x65,0x72,0x5E,0x4A,0xF6,0x72,0x67,0x20])
        let element = DataElement(tag: .patientName, vr: .PN, length: UInt32(bytes.count), valueData: bytes)
        #expect(element.bindingSpecificCharacterSet("ISO_IR 100").stringValue == "Müller^Jörg")
        #expect(element.bindingSpecificCharacterSet("ISO_IR 100").valueData == bytes)
    }

    @Test("Strict declarations use 2026a tables and leave tolerant aliases unchanged")
    func strictDeclarations() {
        for declaration in ["", "ISO_IR 100", "ISO_IR 13", "ISO_IR 192", "GB18030", "GBK",
                            "\\ISO 2022 IR 87", "ISO 2022 IR 13\\ISO 2022 IR 87",
                            "ISO 2022 IR 6\\ISO 2022 IR 100", "\\ISO 2022 IR 149",
                            "\\ISO 2022 IR 58", "\\ISO 2022 IR 87\\ISO 2022 IR 159"] {
            #expect(CharacterSetHandler.isSupported(specificCharacterSet: declaration), "\(declaration)")
        }
        for declaration in ["ISO_IR 6", "ISO_IR 14", "ISO_IR 87", "ISO_IR 159", "ISO 2022 IR 14",
                            "ISO 2022 IR 87", "ISO 2022 IR 100", "ISO_IR 100\\ISO 2022 IR 87",
                            "ISO_IR 192\\ISO 2022 IR 87", "ISO 2022 IR 87\\ISO 2022 IR 159",
                            "\\ISO 2022 IR 6", "ISO 2022 IR 100\\ISO 2022 IR 100",
                            "ISO 2022 IR 6\\", "GBK\\GB18030"] {
            #expect(!CharacterSetHandler.isSupported(specificCharacterSet: declaration), "\(declaration)")
        }
        // Compatibility decoding remains intentionally separate from declarations.
        #expect(CharacterSetEncoding.from(definedTerm: "ISO_IR 87") == .isoIR87)
        #expect(CharacterSetHandler.from(specificCharacterSet: "ISO_IR 6").decode(Data("ASCII".utf8)) == "ASCII")
    }

    @Test("Text factory records its actual UTF-8 encoding and strict decoding rejects invalid escapes")
    func factoryProvenanceAndInvalidEscapes() {
        let element = DataElement.string(tag: .patientName, vr: .PN, value: "Müller^Jörg")
        #expect(element.specificCharacterSet == "ISO_IR 192")
        #expect(element.stringValue == "Müller^Jörg")
        #expect(CharacterSetHandler.decodeStrict(Data([0x1B,0x2D,0x5A]), specificCharacterSet: "ISO 2022 IR 6\\ISO 2022 IR 100") == nil)
        // A known designation is still invalid when absent from (0008,0005).
        #expect(CharacterSetHandler.decodeStrict(Data([0x1B,0x24,0x42,0x3B,0x33]), specificCharacterSet: "ISO 2022 IR 6\\ISO 2022 IR 100") == nil)
    }
}
