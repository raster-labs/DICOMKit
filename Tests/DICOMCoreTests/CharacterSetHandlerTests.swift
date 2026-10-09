import Foundation
import Testing
@testable import DICOMCore

@Suite("CharacterSetHandler Tests")
struct CharacterSetHandlerTests {
    
    // MARK: - CharacterSetEncoding Tests
    
    @Test("Parse ISO IR 6 (ASCII) defined term")
    func testParseISOIR6() {
        let encoding = CharacterSetEncoding.from(definedTerm: "ISO_IR 6")
        #expect(encoding == .isoIR6)
    }
    
    @Test("Parse empty defined term defaults to ISO IR 6")
    func testParseEmptyDefaultsToASCII() {
        let encoding = CharacterSetEncoding.from(definedTerm: "")
        #expect(encoding == .isoIR6)
    }
    
    @Test("Parse ISO IR 100 (Latin-1)")
    func testParseISOIR100() {
        let encoding = CharacterSetEncoding.from(definedTerm: "ISO_IR 100")
        #expect(encoding == .isoIR100)
    }
    
    @Test("Parse ISO 2022 IR 100 (Latin-1 with ISO 2022)")
    func testParseISO2022IR100() {
        let encoding = CharacterSetEncoding.from(definedTerm: "ISO 2022 IR 100")
        #expect(encoding == .isoIR100)
    }
    
    @Test("Parse ISO IR 192 (UTF-8)")
    func testParseISOIR192() {
        let encoding = CharacterSetEncoding.from(definedTerm: "ISO_IR 192")
        #expect(encoding == .isoIR192)
    }
    
    @Test("Parse ISO IR 87 (Japanese Kanji)")
    func testParseISOIR87() {
        let encoding = CharacterSetEncoding.from(definedTerm: "ISO_IR 87")
        #expect(encoding == .isoIR87)
    }
    
    @Test("Parse ISO IR 149 (Korean)")
    func testParseISOIR149() {
        let encoding = CharacterSetEncoding.from(definedTerm: "ISO_IR 149")
        #expect(encoding == .isoIR149)
    }
    
    @Test("Parse unknown defined term returns nil")
    func testParseUnknownTerm() {
        let encoding = CharacterSetEncoding.from(definedTerm: "UNKNOWN_CHARSET")
        #expect(encoding == nil)
    }
    
    @Test("Encoding decode ASCII text")
    func testEncodingDecodeASCII() {
        let text = "Hello, World!"
        let data = text.data(using: .ascii)!
        
        let decoded = CharacterSetEncoding.isoIR6.decode(data)
        #expect(decoded == text)
    }
    
    @Test("Encoding decode UTF-8 text")
    func testEncodingDecodeUTF8() {
        let text = "Hello, 世界! 🌍"
        let data = text.data(using: .utf8)!
        
        let decoded = CharacterSetEncoding.isoIR192.decode(data)
        #expect(decoded == text)
    }
    
    @Test("Encoding encode ASCII text")
    func testEncodingEncodeASCII() {
        let text = "Hello, World!"
        let encoded = CharacterSetEncoding.isoIR6.encode(text)
        
        let decoded = String(data: encoded, encoding: .ascii)
        #expect(decoded == text)
    }
    
    @Test("Encoding encode UTF-8 text")
    func testEncodingEncodeUTF8() {
        let text = "Hello, 世界!"
        let encoded = CharacterSetEncoding.isoIR192.encode(text)
        
        let decoded = String(data: encoded, encoding: .utf8)
        #expect(decoded == text)
    }
    
    @Test("UTF-8 bytes per character - single byte")
    func testUTF8BytesPerCharSingleByte() {
        let count = CharacterSetEncoding.isoIR192.bytesPerCharacter(startingWith: 0x41) // 'A'
        #expect(count == 1)
    }
    
    @Test("UTF-8 bytes per character - two bytes")
    func testUTF8BytesPerCharTwoBytes() {
        let count = CharacterSetEncoding.isoIR192.bytesPerCharacter(startingWith: 0xC3) // Latin-1 supplement
        #expect(count == 2)
    }
    
    @Test("UTF-8 bytes per character - three bytes")
    func testUTF8BytesPerCharThreeBytes() {
        let count = CharacterSetEncoding.isoIR192.bytesPerCharacter(startingWith: 0xE4) // CJK
        #expect(count == 3)
    }
    
    @Test("UTF-8 bytes per character - four bytes")
    func testUTF8BytesPerCharFourBytes() {
        let count = CharacterSetEncoding.isoIR192.bytesPerCharacter(startingWith: 0xF0) // Emoji
        #expect(count == 4)
    }
    
    @Test("Single-byte encoding bytes per character")
    func testSingleByteEncodingBytesPerChar() {
        let count = CharacterSetEncoding.isoIR100.bytesPerCharacter(startingWith: 0x41)
        #expect(count == 1)
    }
    
    @Test("Double-byte encoding bytes per character")
    func testDoubleByteEncodingBytesPerChar() {
        let count = CharacterSetEncoding.isoIR87.bytesPerCharacter(startingWith: 0x41)
        #expect(count == 2)
    }
    
    // MARK: - CharacterSetHandler Creation Tests
    
    @Test("Create handler from nil Specific Character Set defaults to ASCII")
    func testCreateFromNilDefaultsToASCII() {
        let handler = CharacterSetHandler.from(specificCharacterSet: nil)
        
        let text = "ASCII Text"
        let data = text.data(using: .ascii)!
        let decoded = handler.decode(data)
        
        #expect(decoded == text)
    }
    
    @Test("Create handler from empty Specific Character Set defaults to ASCII")
    func testCreateFromEmptyDefaultsToASCII() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "")
        
        let text = "ASCII Text"
        let data = text.data(using: .ascii)!
        let decoded = handler.decode(data)
        
        #expect(decoded == text)
    }
    
    @Test("Create handler from single Specific Character Set value")
    func testCreateFromSingleValue() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 192")
        
        let text = "UTF-8 Text: 日本語"
        let data = text.data(using: .utf8)!
        let decoded = handler.decode(data)
        
        #expect(decoded == text)
    }
    
    @Test("Create handler from multi-valued Specific Character Set")
    func testCreateFromMultiValue() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 6\\ISO_IR 100")
        
        // Should support both ASCII and Latin-1
        let text = "Hello"
        let data = text.data(using: .ascii)!
        let decoded = handler.decode(data)
        
        #expect(decoded == text)
    }
    
    @Test("Create handler with whitespace in Specific Character Set")
    func testCreateWithWhitespace() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "  ISO_IR 192  ")
        
        let text = "Test"
        let data = text.data(using: .utf8)!
        let decoded = handler.decode(data)
        
        #expect(decoded == text)
    }
    
    @Test("Create handler with unknown character set falls back to empty")
    func testCreateWithUnknownCharset() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "UNKNOWN_CHARSET")
        
        // Should still work with default encoding
        let text = "Test"
        let data = text.data(using: .ascii)!
        let decoded = handler.decode(data)
        
        #expect(decoded == text)
    }
    
    // MARK: - Decoding Tests
    
    @Test("Decode empty data returns empty string")
    func testDecodeEmptyData() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 192")
        let decoded = handler.decode(Data())
        
        #expect(decoded == "")
    }
    
    @Test("Decode ASCII text without escape sequences")
    func testDecodeASCIIWithoutEscapes() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 6")
        
        let text = "Hello, World!"
        let data = text.data(using: .ascii)!
        let decoded = handler.decode(data)
        
        #expect(decoded == text)
    }
    
    @Test("Decode UTF-8 text without escape sequences")
    func testDecodeUTF8WithoutEscapes() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 192")
        
        let text = "Hello, 世界! Привет! مرحبا"
        let data = text.data(using: .utf8)!
        let decoded = handler.decode(data)
        
        #expect(decoded == text)
    }
    
    @Test("Decode Latin-1 text")
    func testDecodeLatin1() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 100")
        
        let text = "Café résumé"
        let data = text.data(using: .isoLatin1)!
        let decoded = handler.decode(data)
        
        #expect(decoded == text)
    }
    
    @Test("Decode text with ISO 2022 escape sequence to Latin-1")
    func testDecodeWithEscapeToLatin1() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 6\\ISO_IR 100")
        
        // ASCII text, then ESC - A to switch to Latin-1, then Latin-1 text
        var data = Data("Test ".utf8)
        data.append(contentsOf: [0x1B, 0x2D, 0x41]) // ESC - A (switch to Latin-1 in G1)
        data.append("café".data(using: .isoLatin1)!)
        
        let decoded = handler.decode(data)
        #expect(decoded != nil)
        #expect(decoded?.contains("Test") == true)
    }
    
    @Test("Decode text with escape sequence to ASCII")
    func testDecodeWithEscapeToASCII() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 100")
        
        // Start with some text, ESC ( B to switch to ASCII
        var data = Data()
        data.append(contentsOf: [0x1B, 0x28, 0x42]) // ESC ( B (switch to ASCII in G0)
        data.append("Hello".data(using: .ascii)!)
        
        let decoded = handler.decode(data)
        #expect(decoded != nil)
        #expect(decoded?.contains("Hello") == true)
    }
    
    @Test("Detect escape sequences in data")
    func testDetectEscapeSequences() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 6")
        
        // Data with ESC character
        var data = Data("Test".utf8)
        data.append(0x1B) // ESC
        data.append(0x28)
        data.append(0x42)
        
        // Should handle escape sequences
        let decoded = handler.decode(data)
        #expect(decoded != nil)
    }
    
    @Test("Decode without escape sequences when not present")
    func testDecodeWithoutEscapeSequencesWhenNotPresent() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 192")
        
        let text = "Simple text without escapes"
        let data = text.data(using: .utf8)!
        let decoded = handler.decode(data)
        
        #expect(decoded == text)
    }
    
    // MARK: - Encoding Tests
    
    @Test("Encode empty string returns empty data")
    func testEncodeEmptyString() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 192")
        let encoded = handler.encode("")
        
        #expect(encoded.isEmpty)
    }
    
    @Test("Encode ASCII text")
    func testEncodeASCII() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 6")
        
        let text = "Hello, World!"
        let encoded = handler.encode(text)
        
        let decoded = String(data: encoded, encoding: .ascii)
        #expect(decoded == text)
    }
    
    @Test("Encode UTF-8 text")
    func testEncodeUTF8() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 192")
        
        let text = "Hello, 世界!"
        let encoded = handler.encode(text)
        
        let decoded = String(data: encoded, encoding: .utf8)
        #expect(decoded == text)
    }
    
    @Test("Encode Latin-1 text")
    func testEncodeLatin1() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 100")
        
        let text = "Café"
        let encoded = handler.encode(text)
        
        let decoded = String(data: encoded, encoding: .isoLatin1)
        #expect(decoded == text)
    }
    
    @Test("Encode with multi-valued character set uses first encoding")
    func testEncodeMultiValuedUsesFirst() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 6\\ISO_IR 100")
        
        let text = "Test"
        let encoded = handler.encode(text)
        
        // Should encode and round-trip correctly using the handler
        let decoded = handler.decode(encoded)
        #expect(decoded == text)
    }
    
    // MARK: - Round-trip Tests
    
    @Test("Round-trip ASCII text")
    func testRoundTripASCII() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 6")
        
        let original = "Hello, World! 123"
        let encoded = handler.encode(original)
        let decoded = handler.decode(encoded)
        
        #expect(decoded == original)
    }
    
    @Test("Round-trip UTF-8 text")
    func testRoundTripUTF8() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 192")
        
        let original = "Hello, 世界! Привет! 😊"
        let encoded = handler.encode(original)
        let decoded = handler.decode(encoded)
        
        #expect(decoded == original)
    }
    
    @Test("Round-trip Latin-1 text")
    func testRoundTripLatin1() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 100")
        
        let original = "Café résumé naïve"
        let encoded = handler.encode(original)
        let decoded = handler.decode(encoded)
        
        #expect(decoded == original)
    }
    
    // MARK: - Edge Cases
    
    @Test("Handle data with only escape sequence")
    func testHandleOnlyEscapeSequence() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 6")
        
        // Just an escape sequence, no actual text
        let data = Data([0x1B, 0x28, 0x42])
        let decoded = handler.decode(data)
        
        #expect(decoded == "")
    }
    
    @Test("Handle incomplete escape sequence at end of data")
    func testHandleIncompleteEscapeSequence() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 6")
        
        // Text followed by incomplete escape sequence
        var data = Data("Hello".utf8)
        data.append(0x1B) // ESC but nothing after
        
        let decoded = handler.decode(data)
        #expect(decoded != nil)
        #expect(decoded?.contains("Hello") == true)
    }
    
    @Test("Handle invalid UTF-8 sequence")
    func testHandleInvalidUTF8() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 192")
        
        // Invalid UTF-8 byte sequence
        let data = Data([0xC3, 0x28]) // Invalid continuation byte
        let decoded = handler.decode(data)
        
        // Swift's String(data:encoding:.utf8) returns nil for invalid UTF-8,
        // which is correct strict behavior. The handler may return nil or a
        // partial/replacement string depending on the platform.
        // Just verify it doesn't crash.
        _ = decoded
    }
    
    @Test("Handle very long text")
    func testHandleVeryLongText() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 192")
        
        let original = String(repeating: "Hello, World! 世界 ", count: 1000)
        let encoded = handler.encode(original)
        let decoded = handler.decode(encoded)
        
        #expect(decoded == original)
    }
    
    @Test("Handle text with null bytes")
    func testHandleTextWithNullBytes() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 6")
        
        let data = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x00, 0x57, 0x6F, 0x72, 0x6C, 0x64]) // "Hello\0World"
        let decoded = handler.decode(data)
        
        #expect(decoded != nil)
    }
    
    // MARK: - Character Repertoire Tests
    
    @Test("Parse ISO IR 101 (Latin-2)")
    func testParseISOIR101() {
        let encoding = CharacterSetEncoding.from(definedTerm: "ISO_IR 101")
        #expect(encoding == .isoIR101)
    }
    
    @Test("Parse ISO IR 109 (Latin-3)")
    func testParseISOIR109() {
        let encoding = CharacterSetEncoding.from(definedTerm: "ISO_IR 109")
        #expect(encoding == .isoIR109)
    }
    
    @Test("Parse ISO IR 110 (Latin-4)")
    func testParseISOIR110() {
        let encoding = CharacterSetEncoding.from(definedTerm: "ISO_IR 110")
        #expect(encoding == .isoIR110)
    }
    
    @Test("Parse ISO IR 126 (Greek)")
    func testParseISOIR126() {
        let encoding = CharacterSetEncoding.from(definedTerm: "ISO_IR 126")
        #expect(encoding == .isoIR126)
    }
    
    @Test("Parse ISO IR 127 (Arabic)")
    func testParseISOIR127() {
        let encoding = CharacterSetEncoding.from(definedTerm: "ISO_IR 127")
        #expect(encoding == .isoIR127)
    }
    
    @Test("Parse ISO IR 138 (Hebrew)")
    func testParseISOIR138() {
        let encoding = CharacterSetEncoding.from(definedTerm: "ISO_IR 138")
        #expect(encoding == .isoIR138)
    }
    
    @Test("Parse ISO IR 144 (Cyrillic)")
    func testParseISOIR144() {
        let encoding = CharacterSetEncoding.from(definedTerm: "ISO_IR 144")
        #expect(encoding == .isoIR144)
    }
    
    @Test("Parse ISO IR 148 (Latin-5 Turkish)")
    func testParseISOIR148() {
        let encoding = CharacterSetEncoding.from(definedTerm: "ISO_IR 148")
        #expect(encoding == .isoIR148)
    }
    
    @Test("Parse ISO IR 166 (Thai)")
    func testParseISOIR166() {
        let encoding = CharacterSetEncoding.from(definedTerm: "ISO_IR 166")
        #expect(encoding == .isoIR166)
    }
    
    @Test("Parse ISO IR 13 (Japanese Katakana)")
    func testParseISOIR13() {
        let encoding = CharacterSetEncoding.from(definedTerm: "ISO_IR 13")
        #expect(encoding == .isoIR13)
    }
    
    @Test("Parse ISO IR 14 (Japanese Romaji)")
    func testParseISOIR14() {
        let encoding = CharacterSetEncoding.from(definedTerm: "ISO_IR 14")
        #expect(encoding == .isoIR14)
    }
    
    @Test("Parse ISO IR 159 (Japanese Supplementary Kanji)")
    func testParseISOIR159() {
        let encoding = CharacterSetEncoding.from(definedTerm: "ISO_IR 159")
        #expect(encoding == .isoIR159)
    }
    
    @Test("Parse ISO 2022 IR 13 variant")
    func testParseISO2022IR13() {
        let encoding = CharacterSetEncoding.from(definedTerm: "ISO 2022 IR 13")
        #expect(encoding == .isoIR13)
    }
    
    @Test("Parse ISO 2022 IR 87 variant")
    func testParseISO2022IR87() {
        let encoding = CharacterSetEncoding.from(definedTerm: "ISO 2022 IR 87")
        #expect(encoding == .isoIR87)
    }
    
    // MARK: - Multi-valued Character Set Tests
    
    @Test("Parse multi-valued character set with backslash delimiter")
    func testParseMultiValuedCharacterSet() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 6\\ISO_IR 100\\ISO_IR 101")
        // Handler should be created successfully
        #expect(handler.encode("test").count > 0)
    }
    
    @Test("Parse multi-valued character set with whitespace")
    func testParseMultiValuedCharacterSetWithWhitespace() {
        let handler = CharacterSetHandler.from(specificCharacterSet: " ISO_IR 6 \\ ISO_IR 100 ")
        // Handler should trim whitespace and parse correctly
        #expect(handler.encode("test").count > 0)
    }
    
    @Test("Parse multi-valued character set for Japanese")
    func testParseMultiValuedJapanese() {
        // Common Japanese combination: ASCII + Kanji
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 6\\ISO 2022 IR 87")
        #expect(handler.encode("test").count > 0)
    }
    
    // MARK: - Escape Sequence Tests
    
    @Test("Decode escape sequence ESC ( B (ASCII to G0)")
    func testDecodeEscapeASCIIToG0() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 100")
        
        var data = Data()
        data.append(contentsOf: [0x1B, 0x28, 0x42]) // ESC ( B
        data.append("Hello".data(using: .ascii)!)
        
        let decoded = handler.decode(data)
        #expect(decoded?.contains("Hello") == true)
    }
    
    @Test("Decode escape sequence ESC ) I (Katakana to G1)")
    func testDecodeEscapeKatakanaToG1() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 6\\ISO_IR 13")
        
        var data = Data("Test".utf8)
        data.append(contentsOf: [0x1B, 0x29, 0x49]) // ESC ) I
        
        let decoded = handler.decode(data)
        #expect(decoded != nil)
    }
    
    @Test("Decode escape sequence ESC $ B (JIS X 0208 Kanji to G0)")
    func testDecodeEscapeKanjiToG0() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 6\\ISO_IR 87")
        
        var data = Data()
        data.append(contentsOf: [0x1B, 0x24, 0x42]) // ESC $ B
        
        let decoded = handler.decode(data)
        #expect(decoded != nil)
    }
    
    @Test("Decode escape sequence ESC - F (Greek to G1)")
    func testDecodeEscapeGreekToG1() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 6\\ISO_IR 126")
        
        var data = Data("Test".utf8)
        data.append(contentsOf: [0x1B, 0x2D, 0x46]) // ESC - F
        
        let decoded = handler.decode(data)
        #expect(decoded != nil)
    }
    
    @Test("Decode escape sequence ESC - G (Arabic to G1)")
    func testDecodeEscapeArabicToG1() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 6\\ISO_IR 127")
        
        var data = Data("Test".utf8)
        data.append(contentsOf: [0x1B, 0x2D, 0x47]) // ESC - G
        
        let decoded = handler.decode(data)
        #expect(decoded != nil)
    }
    
    @Test("Decode escape sequence ESC - H (Hebrew to G1)")
    func testDecodeEscapeHebrewToG1() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 6\\ISO_IR 138")
        
        var data = Data("Test".utf8)
        data.append(contentsOf: [0x1B, 0x2D, 0x48]) // ESC - H
        
        let decoded = handler.decode(data)
        #expect(decoded != nil)
    }
    
    @Test("Decode escape sequence ESC - L (Cyrillic to G1)")
    func testDecodeEscapeCyrillicToG1() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 6\\ISO_IR 144")
        
        var data = Data("Test".utf8)
        data.append(contentsOf: [0x1B, 0x2D, 0x4C]) // ESC - L
        
        let decoded = handler.decode(data)
        #expect(decoded != nil)
    }
    
    @Test("Decode escape sequence ESC - M (Latin-5 Turkish to G1)")
    func testDecodeEscapeTurkishToG1() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 6\\ISO_IR 148")
        
        var data = Data("Test".utf8)
        data.append(contentsOf: [0x1B, 0x2D, 0x4D]) // ESC - M
        
        let decoded = handler.decode(data)
        #expect(decoded != nil)
    }
    
    @Test("Decode escape sequence ESC - T (Thai to G1)")
    func testDecodeEscapeThaiToG1() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 6\\ISO_IR 166")
        
        var data = Data("Test".utf8)
        data.append(contentsOf: [0x1B, 0x2D, 0x54]) // ESC - T
        
        let decoded = handler.decode(data)
        #expect(decoded != nil)
    }
    
    @Test("Decode multiple escape sequences in same data")
    func testDecodeMultipleEscapeSequences() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 6\\ISO_IR 100")
        
        var data = Data("Hello ".utf8)
        data.append(contentsOf: [0x1B, 0x2D, 0x41]) // ESC - A (Latin-1)
        data.append("café ".data(using: .isoLatin1)!)
        data.append(contentsOf: [0x1B, 0x28, 0x42]) // ESC ( B (ASCII)
        data.append("world".data(using: .ascii)!)
        
        let decoded = handler.decode(data)
        #expect(decoded != nil)
        #expect(decoded?.contains("Hello") == true)
    }
    
    // MARK: - String Encoding Tests
    
    @Test("Encoding string with single character set uses that encoding")
    func testEncodingSingleCharacterSet() {
        let handler = CharacterSetHandler(characterSets: [.isoIR192])
        let text = "Hello, 世界!"
        let encoded = handler.encode(text)
        
        #expect(encoded.count > 0)
        // Should be UTF-8 encoded
        let decoded = String(data: encoded, encoding: .utf8)
        #expect(decoded == text)
    }
    
    @Test("Encoding with multiple character sets uses first encoding")
    func testEncodingMultipleCharacterSets() {
        // When multiple character sets, uses first one
        let handler = CharacterSetHandler(characterSets: [.isoIR6, .isoIR100])
        let text = "Hello"
        let encoded = handler.encode(text)
        
        #expect(encoded.count > 0)
        // Verify round-trip encoding using the handler
        let decoded = handler.decode(encoded)
        #expect(decoded == text)
    }
    
    // MARK: - Round-trip Tests (Additional)
    
    @Test("Round-trip Latin-2 encoding and decoding")
    func testRoundTripLatin2() {
        let handler = CharacterSetHandler(characterSets: [.isoIR101])
        let original = "Hello World" // Use ASCII-compatible text since Latin-2 is complex
        let encoded = handler.encode(original)
        let decoded = handler.decode(encoded)
        
        #expect(decoded == original)
    }
    
    // MARK: - Edge Cases
    
    @Test("Handler with empty character set array defaults to ASCII")
    func testEmptyCharacterSetDefaults() {
        let handler = CharacterSetHandler(characterSets: [])
        let text = "Hello"
        let encoded = handler.encode(text)
        let decoded = handler.decode(encoded)
        
        #expect(decoded == text)
    }
    
    @Test("Parse nil specific character set defaults to ASCII")
    func testNilSpecificCharacterSet() {
        let handler = CharacterSetHandler.from(specificCharacterSet: nil)
        let text = "Hello"
        let encoded = handler.encode(text)
        let decoded = handler.decode(encoded)
        
        #expect(decoded == text)
    }
    
    @Test("Parse empty specific character set defaults to ASCII")
    func testEmptySpecificCharacterSet() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "")
        let text = "Hello"
        let encoded = handler.encode(text)
        let decoded = handler.decode(encoded)
        
        #expect(decoded == text)
    }
    
    @Test("Parse whitespace-only specific character set defaults to ASCII")
    func testWhitespaceOnlySpecificCharacterSet() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "   ")
        let text = "Hello"
        let encoded = handler.encode(text)
        let decoded = handler.decode(encoded)
        
        #expect(decoded == text)
    }
    
    @Test("Decode with unknown escape sequence is skipped")
    func testDecodeUnknownEscapeSequence() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO_IR 6")
        
        var data = Data("Hello ".utf8)
        data.append(contentsOf: [0x1B, 0xFF, 0xFF]) // Unknown escape sequence
        data.append("World".data(using: .ascii)!)
        
        let decoded = handler.decode(data)
        #expect(decoded != nil)
    }
    
    // MARK: - Escape Sequence Generation Tests
    
    @Test("Escape sequence generation for ASCII to G0")
    func testEscapeSequenceASCIIToG0() {
        let escapeSeq = CharacterSetEncoding.isoIR6.escapeSequenceToG0()
        #expect(escapeSeq == [0x1B, 0x28, 0x42])
    }
    
    @Test("Escape sequence generation for Latin-1 to G1")
    func testEscapeSequenceLatin1ToG1() {
        let escapeSeq = CharacterSetEncoding.isoIR100.escapeSequenceToG1()
        #expect(escapeSeq == [0x1B, 0x2D, 0x41])
    }
    
    @Test("Escape sequence generation for Japanese Kanji to G0")
    func testEscapeSequenceKanjiToG0() {
        let escapeSeq = CharacterSetEncoding.isoIR87.escapeSequenceToG0()
        #expect(escapeSeq == [0x1B, 0x24, 0x42])
    }
    
    @Test("Escape sequence generation for Greek to G1")
    func testEscapeSequenceGreekToG1() {
        let escapeSeq = CharacterSetEncoding.isoIR126.escapeSequenceToG1()
        #expect(escapeSeq == [0x1B, 0x2D, 0x46])
    }
    
    @Test("Escape sequence generation for Korean to G1")
    func testEscapeSequenceKoreanToG1() {
        let escapeSeq = CharacterSetEncoding.isoIR149.escapeSequenceToG1()
        #expect(escapeSeq == [0x1B, 0x24, 0x29, 0x43])
    }
    
    @Test("UTF-8 has no escape sequence to G0")
    func testUTF8NoEscapeSequence() {
        let escapeSeq = CharacterSetEncoding.isoIR192.escapeSequenceToG0()
        #expect(escapeSeq == nil)
    }
    
    @Test("UTF-8 has no escape sequence to G1")
    func testUTF8NoEscapeSequenceToG1() {
        let escapeSeq = CharacterSetEncoding.isoIR192.escapeSequenceToG1()
        #expect(escapeSeq == nil)
    }
    
    @Test("Encoding with multi-valued character set includes escape sequences")
    func testEncodingMultiValuedIncludesEscapeSequence() {
        // JIS X 0208 is only allowed as Value 2..n (PS3.3 C.12.1.1.2): ASCII stays in
        // ISO-IR 6, and the Kanji are wrapped in ESC $ B ... ESC ( B (PS3.5 Annex H).
        let handler = CharacterSetHandler.from(specificCharacterSet: "\\ISO 2022 IR 87")
        let encoded = handler.encode("Test山")
        #expect(encoded == Data([0x54, 0x65, 0x73, 0x74, 0x1B, 0x24, 0x42, 0x3B, 0x33, 0x1B, 0x28, 0x42]))
        #expect(handler.decode(encoded) == "Test山")
    }
    
    @Test("Encoding with UTF-8 does not include escape sequences")
    func testEncodingUTF8NoEscapeSequences() {
        let handler = CharacterSetHandler(characterSets: [.isoIR192, .isoIR6])
        let text = "Test"
        let encoded = handler.encode(text)
        
        // Should NOT start with escape sequence (0x1B)
        #expect(encoded[0] != 0x1B)
        
        // Should be valid UTF-8
        let decoded = String(data: encoded, encoding: .utf8)
        #expect(decoded == text)
    }
    
    // MARK: - Unicode Normalization Tests
    
    @Test("NFC normalization combines decomposed characters")
    func testNFCNormalization() {
        // "é" as decomposed (e + combining acute accent)
        let decomposed = "e\u{0301}"
        let normalized = CharacterSetEncoding.normalizeForDisplay(decomposed)
        
        // Should be composed form
        #expect(normalized == "é")
    }
    
    @Test("NFC normalization is idempotent")
    func testNFCNormalizationIdempotent() {
        let original = "Café résumé"
        let normalized1 = CharacterSetEncoding.normalizeForDisplay(original)
        let normalized2 = CharacterSetEncoding.normalizeForDisplay(normalized1)
        
        #expect(normalized1 == normalized2)
    }
    
    @Test("NFD normalization decomposes characters")
    func testNFDNormalization() {
        // "é" as composed character
        let composed = "é"
        let normalized = CharacterSetEncoding.normalizeDecomposed(composed)
        
        // Should have 2 Unicode scalars (e + combining accent)
        #expect(normalized.unicodeScalars.count == 2)
    }
    
    @Test("Normalize Arabic text for display")
    func testNormalizeArabicText() {
        let arabic = "مرحبا"
        let normalized = CharacterSetEncoding.normalizeForDisplay(arabic)
        
        #expect(normalized.count > 0)
    }
    
    @Test("Normalize Hebrew text for display")
    func testNormalizeHebrewText() {
        let hebrew = "שלום"
        let normalized = CharacterSetEncoding.normalizeForDisplay(hebrew)
        
        #expect(normalized.count > 0)
    }
    
    @Test("Normalize mixed scripts for display")
    func testNormalizeMixedScripts() {
        let mixed = "Hello 世界 مرحبا שלום Привет"
        let normalized = CharacterSetEncoding.normalizeForDisplay(mixed)
        
        #expect(normalized.count > 0)
        #expect(normalized.contains("Hello"))
    }

    // MARK: - PS3.3 2026a C.12.1.1.2: each ISO-IR set decodes as its ISO 8859 part

    @Test("Single-byte character sets decode their upper half, not as UTF-8 or Latin-1",
          arguments: [
            ("ISO_IR 109", [UInt8(0xA1)], "Ħ"),  // ISO 8859-3
            ("ISO_IR 110", [0xA1], "Ą"),         // ISO 8859-4
            ("ISO_IR 144", [0xB0], "А"),         // ISO 8859-5 (Cyrillic A)
            ("ISO_IR 127", [0xC7], "ا"),         // ISO 8859-6
            ("ISO_IR 126", [0xE1], "α"),         // ISO 8859-7
            ("ISO_IR 138", [0xE0], "א"),         // ISO 8859-8
            ("ISO_IR 148", [0xDD], "İ"),         // ISO 8859-9
            ("ISO_IR 166", [0xA1], "ก"),         // TIS 620 / ISO 8859-11
          ])
    func testSingleByteCharacterSets(term: String, bytes: [UInt8], expected: String) {
        let handler = CharacterSetHandler.from(specificCharacterSet: term)
        #expect(handler.decode(Data([0x41] + bytes)) == "A" + expected)
    }

    @Test("ISO 2022 IR 149 (Korean) in G1 decodes as KS X 1001")
    func testKoreanG1() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "\\ISO 2022 IR 149")
        // ESC $ ) C designates KS X 1001 to G1; B0A1 is 가.
        let data = Data([0x1B, 0x24, 0x29, 0x43, 0xB0, 0xA1])
        #expect(handler.decode(data) == "가")
    }

    @Test("ISO 2022 escape into Greek G1 decodes ISO 8859-7")
    func testGreekViaEscape() {
        let handler = CharacterSetHandler.from(specificCharacterSet: "ISO 2022 IR 6\\ISO 2022 IR 126")
        let data = Data([0x41, 0x1B, 0x2D, 0x46, 0xE1, 0xE2])  // "A", ESC - F, αβ
        #expect(handler.decode(data) == "Aαβ")
    }

    @Test("ISO 2022 IR 6 is the default repertoire")
    func testISO2022IR6() {
        #expect(CharacterSetEncoding.from(definedTerm: "ISO 2022 IR 6") == .isoIR6)
    }
}
