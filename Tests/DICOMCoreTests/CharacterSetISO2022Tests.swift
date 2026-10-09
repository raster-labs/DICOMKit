import Foundation
import Testing
@testable import DICOMCore

/// ISO 2022 code extensions (PS3.5 2026a Section 6.1.2.5) checked against the worked
/// examples in PS3.5 2026a Annexes H (Japanese), I (Korean) and K (Chinese), and the
/// Defined Terms of PS3.3 2026a Tables C.12-2 to C.12-5.
@Suite("CharacterSetHandler ISO 2022 Tests")
struct CharacterSetISO2022Tests {

    /// Bytes written in the Standard's column/row notation, e.g. "05/09 01/11".
    private func annex(_ notation: String) -> Data {
        Data(notation.split(separator: " ").map { pair in
            let parts = pair.split(separator: "/").map { UInt8($0)! }
            return parts[0] << 4 | parts[1]
        })
    }

    // MARK: - PS3.5 Annex H.3.1, Example 1: "\\ISO 2022 IR 87"

    private let japaneseExample1 = "Yamada^Tarou=山田^太郎=やまだ^たろう"
    private var japaneseExample1Bytes: Data {
        annex("05/09 06/01 06/13 06/01 06/04 06/01 5/14 05/04 06/01 07/02 06/15 07/05 03/13 01/11 02/04 04/02 03/11 03/03 04/05 04/04 01/11 02/08 04/02 05/14 01/11 02/04 04/02 04/02 04/00 04/15 03/10 01/11 02/08 04/02 03/13 01/11 02/04 04/02 02/04 06/04 02/04 05/14 02/04 04/00 01/11 02/08 04/02 05/14 01/11 02/04 04/02 02/04 03/15 02/04 06/13 02/04 02/06 01/11 02/08 04/02")
    }

    @Test("Annex H Example 1 decodes")
    func testJapaneseExample1Decode() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "\\ISO 2022 IR 87")
        #expect(handler.decode(japaneseExample1Bytes) == japaneseExample1)
    }

    @Test("Annex H Example 1 encodes to the Standard's bytes")
    func testJapaneseExample1Encode() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "\\ISO 2022 IR 87")
        #expect(handler.encode(japaneseExample1) == japaneseExample1Bytes)
    }

    // MARK: - PS3.5 Annex H.3.2, Example 2: "ISO 2022 IR 13\\ISO 2022 IR 87"

    private let japaneseExample2 = "ﾔﾏﾀﾞ^ﾀﾛｳ=山田^太郎=やまだ^たろう"
    private var japaneseExample2Bytes: Data {
        annex("13/04 12/15 12/00 13/14 05/14 12/00 13/11 11/03 03/13 01/11 02/04 04/02 03/11 03/03 04/05 04/04 01/11 02/08 04/10 05/14 01/11 02/04 04/02 04/02 04/00 04/15 03/10 01/11 02/08 04/10 03/13 01/11 02/04 04/02 02/04 06/04 02/04 05/14 02/04 04/00 01/11 02/08 04/10 05/14 01/11 02/04 04/02 02/04 03/15 02/04 06/13 02/04 02/06 01/11 02/08 04/10")
    }

    @Test("Annex H Example 2 decodes")
    func testJapaneseExample2Decode() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO 2022 IR 13\\ISO 2022 IR 87")
        #expect(handler.decode(japaneseExample2Bytes) == japaneseExample2)
    }

    @Test("Annex H Example 2 encodes to the Standard's bytes")
    func testJapaneseExample2Encode() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO 2022 IR 13\\ISO 2022 IR 87")
        #expect(handler.encode(japaneseExample2) == japaneseExample2Bytes)
    }

    // MARK: - PS3.5 Annex I.2: "\\ISO 2022 IR 149"

    private let koreanExample = "Hong^Gildong=洪^吉洞=홍^길동"
    private var koreanExampleBytes: Data {
        annex("04/08 06/15 06/14 06/07 05/14 04/07 06/09 06/12 06/04 06/15 06/14 06/07 03/13 01/11 02/04 02/09 04/03 15/11 15/03 05/14 01/11 02/04 02/09 04/03 13/01 12/14 13/04 13/07 03/13 01/11 02/04 02/09 04/03 12/08 10/11 05/14 01/11 02/04 02/09 04/03 11/01 14/06 11/05 11/15")
    }

    @Test("Annex I example decodes")
    func testKoreanDecode() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "\\ISO 2022 IR 149")
        #expect(handler.decode(koreanExampleBytes) == koreanExample)
    }

    @Test("Annex I example encodes to the Standard's bytes")
    func testKoreanEncode() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "\\ISO 2022 IR 149")
        #expect(handler.encode(koreanExample) == koreanExampleBytes)
    }

    // MARK: - PS3.5 Annex K.2: "\\ISO 2022 IR 58"

    @Test("Annex K person name round-trips with ISO-IR 58 re-designated per component")
    func testChinesePersonName() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "\\ISO 2022 IR 58")
        let name = "Zhang^XiaoDong=张^小东="
        // ESC $ ) A 张 ^ ESC $ ) A 小东 = ; GB 2312: 张 D5C5, 小 D0A1, 东 B6AB.
        var expected = Data("Zhang^XiaoDong=".utf8)
        expected += [0x1B, 0x24, 0x29, 0x41, 0xD5, 0xC5, 0x5E]
        expected += [0x1B, 0x24, 0x29, 0x41, 0xD0, 0xA1, 0xB6, 0xAB, 0x3D]
        #expect(handler.encode(name) == expected)
        #expect(handler.decode(expected) == name)
    }

    @Test("Annex K long text: ISO-IR 58 must be designated again on each line")
    func testChineseLines() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "\\ISO 2022 IR 58")
        let text = "1) 第一行\r\n2) 第二行"
        let encoded = handler.encode(text)
        #expect([UInt8](encoded).filter { $0 == 0x1B }.count == 2)
        #expect(handler.decode(encoded) == text)
    }

    // MARK: - Decoder rules

    @Test("A control character makes the Value 1 sets active again")
    func testControlCharacterResets() {
        // G1 = ISO-IR 149 on line 1 only; line 2's high bytes have no G1 designated.
        let handler = CharacterSetHandler.from(specificCharacterSet: "\\ISO 2022 IR 149")
        let data = Data([0x1B, 0x24, 0x29, 0x43, 0xB0, 0xA1, 0x0D, 0x0A, 0xB0, 0xA1])
        #expect(handler.decode(data) == "가\r\n\u{FFFD}\u{FFFD}")
    }

    @Test("Unrecognized escape sequences are skipped, not decoded as text")
    func testUnknownEscapeSkipped() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO 2022 IR 6")
        let data = Data([0x41, 0x1B, 0x28, 0x5A, 0x42]) // ESC ( Z is not a DICOM set
        #expect(handler.decode(data) == "AB")
    }

    @Test("JIS X 0212 (ISO-IR 159) decodes and encodes")
    func testSupplementaryKanji() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "\\ISO 2022 IR 87\\ISO 2022 IR 159")
        let data = Data([0x1B, 0x24, 0x28, 0x44, 0x30, 0x21, 0x1B, 0x28, 0x42]) // 丂
        #expect(handler.decode(data) == "丂")
        #expect(handler.encode("丂") == data)
    }

    @Test("ISO_IR 13 alone decodes JIS X 0201 half-width Katakana")
    func testISOIR13Single() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 13")
        let data = Data([0x41, 0xD4, 0xCF])
        #expect(handler.decode(data) == "Aﾔﾏ")
        #expect(handler.encode("Aﾔﾏ") == data)
    }

    @Test("A character no configured set can represent is written as ?")
    func testUnencodableCharacter() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "\\ISO 2022 IR 149")
        #expect(handler.encode("aกb") == Data("a?b".utf8))
    }

    @Test("A multi-byte set wrongly given as Value 1 still starts G0 in ISO-IR 6")
    func testMultiByteValue1Tolerated() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO 2022 IR 87")
        var data = Data("Yamada^".utf8)
        data += [0x1B, 0x24, 0x42, 0x3B, 0x33, 0x1B, 0x28, 0x42]  // ESC $ B 山 ESC ( B
        #expect(handler.decode(data) == "Yamada^山")
        #expect(handler.encode("Yamada^山") == data)
    }

    // MARK: - Defined Terms added in 2026a coverage (PS3.3 Tables C.12-2 to C.12-5)

    @Test("New Defined Terms parse", arguments: [
        ("ISO_IR 203", CharacterSetEncoding.isoIR203),
        ("ISO 2022 IR 203", .isoIR203),
        ("ISO 2022 IR 58", .isoIR58),
        ("GB18030", .gb18030),
        ("GBK", .gbk),
    ])
    func testNewTerms(term: String, expected: CharacterSetEncoding) {
        #expect(CharacterSetEncoding.from(definedTerm: term) == expected)
    }

    @Test("ISO_IR 203 decodes ISO 8859-15 (euro sign at 10/04)")
    func testLatin9() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 203")
        #expect(handler.decode(Data([0x41, 0xA4])) == "A€")
        #expect(handler.encode("A€") == Data([0x41, 0xA4]))
    }

    @Test("ESC - b designates ISO-IR 203 to G1")
    func testLatin9Escape() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO 2022 IR 100\\ISO 2022 IR 203")
        let data = Data([0x1B, 0x2D, 0x62, 0xA4, 0x1B, 0x2D, 0x41])
        #expect(handler.decode(data) == "€")
        #expect(handler.encode("€") == data)
    }

    @Test("GB18030 and GBK decode and encode without escape sequences")
    func testGB18030AndGBK() {
        let gb18030 = CharacterSetHandler.from(specificCharacterSet: "GB18030")
        let gbk = CharacterSetHandler.from(specificCharacterSet: "GBK")
        let text = "Wang^XiaoDong=王^小東="
        for handler in [gb18030, gbk] {
            let encoded = handler.encode(text)
            #expect(!encoded.contains(0x1B))
            #expect(handler.decode(encoded) == text)
        }
        // A GB18030 four-byte sequence (U+0080).
        #expect(gb18030.decode(Data([0x81, 0x30, 0x81, 0x30])) == "\u{80}")
    }
}
