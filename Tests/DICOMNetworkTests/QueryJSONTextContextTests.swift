import Foundation
import XCTest
import DICOMCore
@testable import DICOMNetwork

final class QueryJSONTextContextTests: XCTestCase {
    func testTranscodedTextCarriesItsActualUTF8Context() throws {
        for (charset, text, encoding) in [("ISO_IR 100", "MÜLLER^HANS", String.Encoding.isoLatin1),
                                           ("ISO_IR 192", "山田^太郎", String.Encoding.utf8)] {
            let result = GenericQueryResult(attributes: [
                .specificCharacterSet: Data(charset.utf8), .patientName: try XCTUnwrap(text.data(using: encoding))
            ], level: .study)
            let elements = result.dicomJSONElements()
            let name = try XCTUnwrap(elements.first { $0.tag == .patientName })
            XCTAssertEqual(name.specificCharacterSet, "ISO_IR 192")
            XCTAssertEqual(name.valueData, Data(text.utf8))
            XCTAssertEqual(name.stringValue, text)
            XCTAssertEqual(elements.first { $0.tag == .specificCharacterSet }?.stringValue, "ISO_IR 192")
        }
    }

    func testSequenceItemsInheritOrOverrideOriginalRepertoireBeforeTranscoding() throws {
        let sequenceTag = Tag(group: 0x0008, element: 0x1032)
        let descriptionTag = Tag(group: 0x0008, element: 0x0104)
        let inherited = short(descriptionTag, "LO", try XCTUnwrap("ÉTUDE".data(using: .isoLatin1)))
        let nested = short(descriptionTag, "LO", Data("検査".utf8))
        let overridden = short(.specificCharacterSet, "CS", Data("ISO_IR 192".utf8))
            + short(descriptionTag, "LO", Data("患者".utf8))
            + sequence(sequenceTag, [nested])
        let reset = short(.specificCharacterSet, "CS", Data()) + short(descriptionTag, "LO", Data("ASCII".utf8))
        let raw = items([inherited, overridden, reset])
        let result = GenericQueryResult(attributes: [.specificCharacterSet: Data("ISO_IR 100".utf8), sequenceTag: raw],
            level: .study, vrs: [sequenceTag: .SQ], transferSyntaxUID: explicitVRLittleEndianTransferSyntaxUID)
        let sq = try XCTUnwrap(result.dicomJSONElements().first { $0.tag == sequenceTag })
        let itemList = try XCTUnwrap(sq.sequenceItems)
        XCTAssertEqual(itemList.count, 3)
        XCTAssertEqual(itemList[0][descriptionTag]?.stringValue, "ÉTUDE")
        XCTAssertEqual(itemList[1][descriptionTag]?.stringValue, "患者")
        XCTAssertEqual(itemList[2][descriptionTag]?.stringValue, "ASCII")
        XCTAssertEqual(itemList[1][sequenceTag]?.sequenceItems?.first?[descriptionTag]?.stringValue, "検査")
        XCTAssertEqual(itemList[1][descriptionTag]?.specificCharacterSet, "ISO_IR 192")
        XCTAssertEqual(itemList[1][.specificCharacterSet]?.stringValue, "ISO_IR 192")
    }

    private func u16(_ value: UInt16) -> Data { Data([UInt8(value & 255), UInt8(value >> 8)]) }
    private func u32(_ value: UInt32) -> Data { Data((0..<4).map { UInt8((value >> (8 * $0)) & 255) }) }
    private func short(_ tag: Tag, _ vr: String, _ bytes: Data) -> Data {
        let padded = bytes.count.isMultiple(of: 2) ? bytes : bytes + Data([0x20])
        return u16(tag.group) + u16(tag.element) + Data(vr.utf8) + u16(UInt16(padded.count)) + padded
    }
    private func items(_ values: [Data]) -> Data {
        values.reduce(into: Data()) { $0 += u16(0xFFFE) + u16(0xE000) + u32(UInt32($1.count)) + $1 }
    }
    private func sequence(_ tag: Tag, _ values: [Data]) -> Data {
        let bytes = items(values)
        return u16(tag.group) + u16(tag.element) + Data("SQ".utf8) + Data([0, 0]) + u32(UInt32(bytes.count)) + bytes
    }
}
