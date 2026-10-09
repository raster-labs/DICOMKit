import Foundation

/// Handler for DICOM character set processing according to ISO 2022 standard
///
/// Handles encoding and decoding of DICOM text values with support for:
/// - Single-byte and multi-byte character sets
/// - ISO 2022 escape sequences designating character sets to G0 and G1 (DICOM uses no
///   G2/G3 and no locking shifts: G0 is read in GL and G1 in GR)
/// - Restoring the Value 1 character sets at lines, values and name components
///
/// NEMA-verified: 2026a, checked 2026-09-24 — text-diffed against PS3.3 2026a Tables C.12-2
/// to C.12-5: all 20 Defined Terms, and every escape sequence byte for byte. Code extension
/// rules follow PS3.5 2026a Section 6.1.2.5.3. Decoding and encoding reproduce the worked
/// examples of PS3.5 Annex H.3.1, H.3.2 and I.2 byte for byte (see CharacterSetISO2022Tests).
///
/// Reference: DICOM PS3.5 Section 6.1 - Support of Character Repertoires
/// Reference: DICOM PS3.5 Annex H - ISO 2022 Escape Sequences
/// Reference: DICOM PS3.3 C.12.1.1.2 - Specific Character Set
public struct CharacterSetHandler: Sendable {
    
    /// The character set encodings to use, in order
    /// - First element applies to the default character repertoire (G0)
    /// - Additional elements apply to extended character repertoires
    private let characterSets: [CharacterSetEncoding]
    
    /// Creates a character set handler from a Specific Character Set value
    ///
    /// - Parameter specificCharacterSet: Value from (0008,0005) Specific Character Set
    /// - Returns: A configured CharacterSetHandler
    public static func from(specificCharacterSet: String?) -> CharacterSetHandler {
        guard let specificCharacterSet = specificCharacterSet?.trimmingCharacters(in: .whitespaces),
              !specificCharacterSet.isEmpty else {
            // Default to ISO_IR 6 (ASCII) when no character set is specified
            return CharacterSetHandler(characterSets: [.isoIR6])
        }
        
        // Split by backslash for multi-valued character sets. Empty values are kept: an
        // empty Value 1 means ISO 2022 IR 6 (PS3.3 C.12.1.1.2), and dropping it would
        // promote Value 2 (e.g. ISO 2022 IR 87) into Value 1's role.
        let values = specificCharacterSet.split(separator: "\\", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }

        // Value 1 is the initial (default) repertoire; an unrecognized Value 1 falls back to
        // ISO-IR 6. Unrecognized later values are skipped.
        let value1 = CharacterSetEncoding.from(definedTerm: values[0]) ?? .isoIR6
        let extensions = values.dropFirst().filter { !$0.isEmpty }
            .compactMap { CharacterSetEncoding.from(definedTerm: $0) }

        return CharacterSetHandler(characterSets: [value1] + extensions)
    }
    
    /// Creates a character set handler with specific character set encodings
    ///
    /// - Parameter characterSets: Array of character set encodings
    public init(characterSets: [CharacterSetEncoding]) {
        self.characterSets = characterSets.isEmpty ? [.isoIR6] : characterSets
    }
    
    /// Decodes data to a string using the configured character sets
    ///
    /// Implements the code extension techniques of PS3.5 Section 6.1.2.5: ISO 2022 escape
    /// sequences designate character sets to G0 and G1, bytes 00/00-07/15 are read in G0
    /// and bytes 08/00-15/15 in G1 (no locking shifts are used), and the character sets of
    /// Value 1 become active again after each control character (Section 6.1.2.5.3).
    /// UTF-8, GB18030 and GBK allow no code extensions and decode the whole value directly.
    ///
    /// - Parameter data: The raw byte data to decode
    /// - Returns: The decoded string, or nil if decoding fails
    public func decode(_ data: Data) -> String? {
        // Empty data returns empty string
        guard !data.isEmpty else {
            return ""
        }

        let primary = characterSets[0]
        if !primary.usesCodeExtensions {
            return primary.decode(data)
        }

        // A single set without escapes: its ISO 8859 part covers G0 and G1 directly.
        // ISO_IR 13 (JIS X 0201) has no Foundation equivalent and takes the G0/G1 path.
        if characterSets.count == 1 && primary != .isoIR13 && !data.contains(ISO2022.escape) {
            return primary.decode(data)
        }

        return ISO2022.decode(data, initial: ISO2022.State(value1: primary))
    }

    /// Encodes a string to data using the configured character sets
    ///
    /// With a single character set, or with UTF-8, GB18030 or GBK, the string is encoded
    /// in that set without escape sequences. With several values (code extensions), each
    /// character is written in the first configured set that can represent it, designated
    /// with its escape sequence when it is not already active, and the Value 1 sets are
    /// made active again before control characters, before the "\\", "^" and "="
    /// delimiters, and at the end of the value (PS3.5 Section 6.1.2.5.3). Characters that
    /// no configured set can represent are written as "?".
    ///
    /// - Parameter string: The string to encode
    /// - Returns: The encoded data
    public func encode(_ string: String) -> Data {
        guard !string.isEmpty else {
            return Data()
        }

        let primary = characterSets[0]
        if !primary.usesCodeExtensions || (characterSets.count == 1 && primary != .isoIR13) {
            return primary.encode(string)
        }

        return ISO2022.encode(string, characterSets: characterSets)
    }
}

// MARK: - ISO 2022 code extensions (PS3.5 Section 6.1.2.5)

/// Designation, decoding and encoding for DICOM's use of ISO/IEC 2022.
enum ISO2022 {
    static let escape: UInt8 = 0x1B

    /// The code element a character set is designated to.
    enum CodeElement { case g0, g1 }

    /// The character sets designated to G0 and G1.
    struct State: Equatable {
        var g0: CharacterSetEncoding
        var g1: CharacterSetEncoding?

        /// The state that Value 1 of Specific Character Set establishes, and that is restored
        /// at each line, page, value and name component (PS3.5 Section 6.1.2.5.3). ISO_IR 13
        /// is ISO-IR 14 in G0 with ISO-IR 13 in G1 (PS3.3 Table C.12-2). The multi-byte sets
        /// of Table C.12-4 are allowed only as Values 2 to n; if one appears as Value 1 it is
        /// tolerated as an extension, and G0 starts in ISO-IR 6 until an escape designates it.
        init(value1: CharacterSetEncoding) {
            switch value1 {
            case .isoIR13:
                g0 = .isoIR14
                g1 = .isoIR13
            case .isoIR14:
                g0 = .isoIR14
                g1 = nil
            case .isoIR87, .isoIR159:
                g0 = .isoIR6
                g1 = nil
            default:
                g0 = .isoIR6
                g1 = value1.codeElement == .g1 ? value1 : nil
            }
        }
    }

    /// Every character set that has a designating escape sequence (PS3.3 Tables C.12-3, C.12-4).
    static let designatable: [CharacterSetEncoding] = [
        .isoIR6, .isoIR14, .isoIR87, .isoIR159,
        .isoIR13, .isoIR100, .isoIR101, .isoIR109, .isoIR110, .isoIR126, .isoIR127,
        .isoIR138, .isoIR144, .isoIR148, .isoIR166, .isoIR203, .isoIR149, .isoIR58,
    ]

    /// Encoding for JIS X 0208 and JIS X 0212 runs. ISO-2022-JP-1 covers both; Foundation's
    /// EUC-JP does not cover JIS X 0212.
    static let iso2022JP1 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(0x0822))

    // MARK: Decoding

    static func decode(_ data: Data, initial: State) -> String {
        let bytes = [UInt8](data)
        var state = initial
        var result = ""
        var run: [UInt8] = []
        var runIsG1 = false

        func flush() {
            guard !run.isEmpty else { return }
            result += runIsG1 ? decodeG1(run, set: state.g1) : decodeG0(run, set: state.g0)
            run.removeAll(keepingCapacity: true)
        }

        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == escape {
                flush()
                let (designation, length) = parseEscape(bytes, at: index)
                if let (element, set) = designation {
                    if element == .g0 { state.g0 = set } else { state.g1 = set }
                }
                index += length
                continue
            }
            if byte < 0x20 {
                // CR, LF, FF, TAB and other control characters: Value 1 is active again.
                flush()
                state = initial
                result.unicodeScalars.append(Unicode.Scalar(byte))
                index += 1
                continue
            }
            let isG1 = byte >= 0x80
            if isG1 != runIsG1 {
                flush()
                runIsG1 = isG1
            }
            run.append(byte)
            index += 1
        }
        flush()
        return result
    }

    /// Parses the escape sequence at `index`: ESC, intermediate bytes 02/00-02/15, and a
    /// final byte 03/00-07/14. Returns the designation it makes, if recognized, and its
    /// length, so an unrecognized or truncated sequence is skipped rather than decoded.
    static func parseEscape(_ bytes: [UInt8], at index: Int) -> ((CodeElement, CharacterSetEncoding)?, Int) {
        var end = index + 1
        while end < bytes.count, (0x20...0x2F).contains(bytes[end]) { end += 1 }
        guard end < bytes.count, (0x30...0x7E).contains(bytes[end]) else {
            return (nil, end - index)
        }
        let sequence = Array(bytes[index...end])
        for set in designatable {
            if set.escapeSequenceToG0() == sequence { return ((.g0, set), sequence.count) }
            if set.escapeSequenceToG1() == sequence { return ((.g1, set), sequence.count) }
        }
        return (nil, sequence.count)
    }

    /// Decodes bytes 02/00-07/15 in the G0 set.
    static func decodeG0(_ bytes: [UInt8], set: CharacterSetEncoding) -> String {
        switch set {
        case .isoIR87, .isoIR159:
            // Two-byte 94x94 sets. Bytes outside 02/01-07/14 (SPACE, DEL) are single characters.
            var result = ""
            var pairs: [UInt8] = []
            func flushPairs() {
                guard !pairs.isEmpty else { return }
                let designation = set.escapeSequenceToG0() ?? []
                let wrapped = Data(designation + pairs + [escape, 0x28, 0x42])
                result += String(data: wrapped, encoding: iso2022JP1)
                    ?? String(repeating: "\u{FFFD}", count: pairs.count / 2)
                pairs.removeAll()
            }
            var index = 0
            while index < bytes.count {
                if (0x21...0x7E).contains(bytes[index]), index + 1 < bytes.count,
                   (0x21...0x7E).contains(bytes[index + 1]) {
                    pairs += [bytes[index], bytes[index + 1]]
                    index += 2
                } else {
                    flushPairs()
                    let byte = bytes[index]
                    result.unicodeScalars.append((0x21...0x7E).contains(byte) ? "\u{FFFD}" : Unicode.Scalar(byte))
                    index += 1
                }
            }
            flushPairs()
            return result
        default:
            // ISO-IR 6, and ISO-IR 14 (JIS X 0201 Romaji). 05/12 and 07/14 are kept as
            // "\\" and "~" so that 05/12 still separates values (PS3.5 Section 6.1.2.5.3).
            return String(decoding: bytes, as: UTF8.self)
        }
    }

    /// Decodes bytes 08/00-15/15 in the G1 set.
    static func decodeG1(_ bytes: [UInt8], set: CharacterSetEncoding?) -> String {
        guard let set else {
            return String(repeating: "\u{FFFD}", count: bytes.count)
        }
        switch set {
        case .isoIR13:
            // JIS X 0201 Katakana: 10/01-13/15 map to U+FF61-U+FF9F.
            var result = ""
            for byte in bytes {
                result.unicodeScalars.append((0xA1...0xDF).contains(byte)
                    ? Unicode.Scalar(0xFF61 + UInt32(byte) - 0xA1)!
                    : "\u{FFFD}")
            }
            return result
        default:
            // ISO 8859 parts decode G1 bytes directly; KS X 1001 and GB 2312 in G1 are
            // byte-identical to EUC-KR and EUC-CN.
            return String(data: Data(bytes), encoding: set.stringEncoding)
                ?? String(repeating: "\u{FFFD}", count: bytes.count)
        }
    }

    // MARK: Encoding

    static func encode(_ string: String, characterSets: [CharacterSetEncoding]) -> Data {
        let initial = State(value1: characterSets[0])
        var state = initial
        var output = Data()

        func designate(_ set: CharacterSetEncoding) {
            switch set.codeElement {
            case .g0?:
                if state.g0 != set, let sequence = set.escapeSequenceToG0() {
                    output += sequence
                    state.g0 = set
                }
            case .g1?:
                if state.g1 != set, let sequence = set.escapeSequenceToG1() {
                    output += sequence
                    state.g1 = set
                }
            case nil:
                break
            }
        }

        func restoreInitial() {
            if state.g0 != initial.g0, let sequence = initial.g0.escapeSequenceToG0() {
                output += sequence
            }
            if state.g1 != initial.g1, let g1 = initial.g1, let sequence = g1.escapeSequenceToG1() {
                output += sequence
            }
            state = initial
        }

        func writeASCII(_ byte: UInt8) {
            if state.g0 != .isoIR6 && state.g0 != .isoIR14 {
                designate(initial.g0 == .isoIR14 ? .isoIR14 : .isoIR6)
            }
            output.append(byte)
        }

        for scalar in string.precomposedStringWithCanonicalMapping.unicodeScalars {
            let value = scalar.value
            if value < 0x20 || scalar == "\\" || scalar == "^" || scalar == "=" {
                restoreInitial()
                output.append(UInt8(value))
                continue
            }
            if value < 0x80 {
                writeASCII(UInt8(value))
                continue
            }
            var candidates: [CharacterSetEncoding] = []
            for set in [state.g1, state.g0].compactMap({ $0 }) + characterSets where !candidates.contains(set) {
                candidates.append(set)
            }
            var written = false
            for set in candidates {
                if let bytes = set.iso2022Bytes(for: scalar) {
                    designate(set)
                    output += bytes
                    written = true
                    break
                }
            }
            if !written {
                writeASCII(0x3F) // "?"
            }
        }
        restoreInitial()
        return output
    }
}

/// Character set encoding definitions for DICOM
///
/// Reference: DICOM PS3.3 C.12.1.1.2, Tables C.12-2 to C.12-5 - Defined Terms for
/// Specific Character Set (0008,0005); PS3.5 Section 6.1 - character repertoires
public enum CharacterSetEncoding: Sendable, Hashable {
    /// ISO IR 6 - ASCII (G0 default)
    case isoIR6
    
    /// ISO IR 13 - Japanese Katakana
    case isoIR13
    
    /// ISO IR 14 - Japanese Romaji
    case isoIR14
    
    /// ISO IR 87 - Japanese Kanji (JIS X 0208)
    case isoIR87
    
    /// ISO IR 100 - Latin-1 (Western European)
    case isoIR100
    
    /// ISO IR 101 - Latin-2 (Central European)
    case isoIR101
    
    /// ISO IR 109 - Latin-3 (South European)
    case isoIR109
    
    /// ISO IR 110 - Latin-4 (North European/Baltic)
    case isoIR110
    
    /// ISO IR 126 - Greek
    case isoIR126
    
    /// ISO IR 127 - Arabic
    case isoIR127
    
    /// ISO IR 138 - Hebrew
    case isoIR138
    
    /// ISO IR 144 - Cyrillic
    case isoIR144
    
    /// ISO IR 148 - Latin-5 (Turkish)
    case isoIR148
    
    /// ISO IR 149 - Korean
    case isoIR149
    
    /// ISO IR 159 - Japanese Supplementary Kanji (JIS X 0212)
    case isoIR159
    
    /// ISO IR 166 - Thai
    case isoIR166
    
    /// ISO IR 192 - UTF-8
    case isoIR192

    /// ISO IR 203 - Latin alphabet No. 9 (ISO 8859-15)
    case isoIR203

    /// ISO IR 58 - Simplified Chinese (GB 2312), multi-byte with code extensions
    case isoIR58

    /// GB18030 - Chinese, multi-byte without code extensions
    case gb18030

    /// GBK - Chinese, multi-byte without code extensions
    case gbk
    
    /// Maps DICOM Defined Term to CharacterSetEncoding
    ///
    /// - Parameter definedTerm: The value from Specific Character Set (0008,0005)
    /// - Returns: The corresponding encoding, or nil if unknown
    public static func from(definedTerm: String) -> CharacterSetEncoding? {
        switch definedTerm {
        case "ISO_IR 6", "ISO 2022 IR 6", "": // Empty defaults to ISO IR 6
            return .isoIR6
        case "ISO_IR 13", "ISO 2022 IR 13":
            return .isoIR13
        case "ISO_IR 14", "ISO 2022 IR 14":
            return .isoIR14
        case "ISO_IR 87", "ISO 2022 IR 87":
            return .isoIR87
        case "ISO_IR 100", "ISO 2022 IR 100":
            return .isoIR100
        case "ISO_IR 101", "ISO 2022 IR 101":
            return .isoIR101
        case "ISO_IR 109", "ISO 2022 IR 109":
            return .isoIR109
        case "ISO_IR 110", "ISO 2022 IR 110":
            return .isoIR110
        case "ISO_IR 126", "ISO 2022 IR 126":
            return .isoIR126
        case "ISO_IR 127", "ISO 2022 IR 127":
            return .isoIR127
        case "ISO_IR 138", "ISO 2022 IR 138":
            return .isoIR138
        case "ISO_IR 144", "ISO 2022 IR 144":
            return .isoIR144
        case "ISO_IR 148", "ISO 2022 IR 148":
            return .isoIR148
        case "ISO_IR 149", "ISO 2022 IR 149":
            return .isoIR149
        case "ISO_IR 159", "ISO 2022 IR 159":
            return .isoIR159
        case "ISO_IR 166", "ISO 2022 IR 166":
            return .isoIR166
        case "ISO_IR 192":
            return .isoIR192
        case "ISO_IR 203", "ISO 2022 IR 203":
            return .isoIR203
        case "ISO 2022 IR 58":
            return .isoIR58
        case "GB18030":
            return .gb18030
        case "GBK":
            return .gbk
        default:
            return nil
        }
    }
    
    /// Returns the Foundation String.Encoding for this character set
    ///
    /// Each ISO-IR registration maps to the ISO/IEC 8859 part (or national standard) that
    /// defines it: G0 ISO-IR 6 plus the G1 set in the upper half is exactly that 8859 part.
    /// ISO-IR 149 (KS X 1001) invoked into G1 is byte-identical to EUC-KR. ISO-IR 13
    /// (Katakana) is approximated with Shift JIS.
    public var stringEncoding: String.Encoding {
        switch self {
        case .isoIR6, .isoIR14: // ASCII and Japanese Romaji
            return .ascii
        case .isoIR13: // Katakana - use Shift JIS as approximation
            return .shiftJIS
        case .isoIR87, .isoIR159: // Japanese Kanji
            return .iso2022JP
        case .isoIR100: // Latin-1
            return .isoLatin1
        case .isoIR101: // Latin-2
            return .isoLatin2
        case .isoIR109: // Latin-3, ISO 8859-3
            return Self.coreFoundation(0x0203) // kCFStringEncodingISOLatin3
        case .isoIR110: // Latin-4, ISO 8859-4
            return Self.coreFoundation(0x0204) // kCFStringEncodingISOLatin4
        case .isoIR126: // Greek, ISO 8859-7
            return Self.coreFoundation(0x0207) // kCFStringEncodingISOLatinGreek
        case .isoIR127: // Arabic, ISO 8859-6
            return Self.coreFoundation(0x0206) // kCFStringEncodingISOLatinArabic
        case .isoIR138: // Hebrew, ISO 8859-8
            return Self.coreFoundation(0x0208) // kCFStringEncodingISOLatinHebrew
        case .isoIR144: // Cyrillic, ISO 8859-5
            return Self.coreFoundation(0x0205) // kCFStringEncodingISOLatinCyrillic
        case .isoIR148: // Latin-5 (Turkish), ISO 8859-9
            return Self.coreFoundation(0x0209) // kCFStringEncodingISOLatin5
        case .isoIR149: // Korean, KS X 1001 in G1 = EUC-KR
            return Self.coreFoundation(0x0940) // kCFStringEncodingEUC_KR
        case .isoIR166: // Thai, TIS 620-2533 = ISO 8859-11
            return Self.coreFoundation(0x020B) // kCFStringEncodingISOLatinThai
        case .isoIR192: // UTF-8
            return .utf8
        case .isoIR203: // Latin-9, ISO 8859-15
            return Self.coreFoundation(0x020F) // kCFStringEncodingISOLatin9
        case .isoIR58: // GB 2312 in G1 = EUC-CN
            return Self.coreFoundation(0x0930) // kCFStringEncodingEUC_CN
        case .gb18030:
            return Self.coreFoundation(0x0632) // kCFStringEncodingGB_18030_2000
        case .gbk:
            return Self.coreFoundation(0x0631) // kCFStringEncodingGBK_95
        }
    }
    
    /// Foundation encoding for a CFStringEncoding constant.
    private static func coreFoundation(_ cfEncoding: UInt32) -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
    }

    /// Decodes data using this character set encoding
    ///
    /// - Parameter data: The data to decode
    /// - Returns: The decoded string, or nil if decoding fails
    public func decode(_ data: Data) -> String? {
        return String(data: data, encoding: stringEncoding)
    }
    
    /// Encodes a string using this character set encoding
    ///
    /// - Parameter string: The string to encode
    /// - Returns: The encoded data
    public func encode(_ string: String) -> Data {
        return string.data(using: stringEncoding) ?? Data()
    }
    
    /// Returns the number of bytes per character for this encoding
    ///
    /// - Parameter firstByte: The first byte of the character
    /// - Returns: Number of bytes to read for this character
    public func bytesPerCharacter(startingWith firstByte: UInt8) -> Int {
        switch self {
        case .isoIR6, .isoIR13, .isoIR14, .isoIR100, .isoIR101, .isoIR109, .isoIR110,
             .isoIR126, .isoIR127, .isoIR138, .isoIR144, .isoIR148, .isoIR166, .isoIR203:
            // Single-byte encodings
            return 1
            
        case .isoIR87, .isoIR149, .isoIR159, .isoIR58:
            // Double-byte encodings (simplified - actual detection is more complex)
            return 2

        case .gbk, .gb18030:
            // ASCII is one byte; other characters are two bytes. GB18030 also has
            // four-byte sequences, which can only be told apart by the second byte.
            return firstByte < 0x80 ? 1 : 2
            
        case .isoIR192:
            // UTF-8 - variable length (1-4 bytes)
            if firstByte & 0x80 == 0 {
                return 1 // 0xxxxxxx
            } else if firstByte & 0xE0 == 0xC0 {
                return 2 // 110xxxxx
            } else if firstByte & 0xF0 == 0xE0 {
                return 3 // 1110xxxx
            } else if firstByte & 0xF8 == 0xF0 {
                return 4 // 11110xxx
            } else {
                return 1 // Invalid, treat as single byte
            }
        }
    }
    
    /// Normalizes a string using NFC (Canonical Decomposition followed by Canonical Composition)
    ///
    /// This normalization is recommended for display purposes to ensure that visually equivalent
    /// characters are represented consistently. For example, "é" can be represented as a single
    /// composed character (U+00E9) or as "e" + combining acute accent (U+0065 U+0301).
    /// NFC normalization ensures consistent representation.
    ///
    /// Reference: Unicode Standard Annex #15 - Unicode Normalization Forms
    /// - Parameter string: The string to normalize
    /// - Returns: The NFC-normalized string
    public static func normalizeForDisplay(_ string: String) -> String {
        return string.precomposedStringWithCanonicalMapping
    }
    
    /// Normalizes a string using NFD (Canonical Decomposition)
    ///
    /// This normalization decomposes characters into their constituent parts.
    /// Useful for certain text processing operations.
    ///
    /// - Parameter string: The string to normalize
    /// - Returns: The NFD-normalized string
    public static func normalizeDecomposed(_ string: String) -> String {
        return string.decomposedStringWithCanonicalMapping
    }
    
    /// Returns the ISO 2022 escape sequence to designate this encoding to G0
    ///
    /// - Returns: Escape sequence bytes, or nil if not applicable (UTF-8, single-byte sets)
    public func escapeSequenceToG0() -> [UInt8]? {
        switch self {
        case .isoIR6:
            return [0x1B, 0x28, 0x42] // ESC ( B
        case .isoIR14:
            return [0x1B, 0x28, 0x4A] // ESC ( J
        case .isoIR87:
            return [0x1B, 0x24, 0x42] // ESC $ B
        case .isoIR159:
            return [0x1B, 0x24, 0x28, 0x44] // ESC $ ( D
        default:
            return nil // No G0 designation for other sets
        }
    }
    
    /// Returns the ISO 2022 escape sequence to designate this encoding to G1
    ///
    /// - Returns: Escape sequence bytes, or nil if not applicable
    public func escapeSequenceToG1() -> [UInt8]? {
        switch self {
        case .isoIR13:
            return [0x1B, 0x29, 0x49] // ESC ) I
        case .isoIR100:
            return [0x1B, 0x2D, 0x41] // ESC - A
        case .isoIR101:
            return [0x1B, 0x2D, 0x42] // ESC - B
        case .isoIR109:
            return [0x1B, 0x2D, 0x43] // ESC - C
        case .isoIR110:
            return [0x1B, 0x2D, 0x44] // ESC - D
        case .isoIR126:
            return [0x1B, 0x2D, 0x46] // ESC - F
        case .isoIR127:
            return [0x1B, 0x2D, 0x47] // ESC - G
        case .isoIR138:
            return [0x1B, 0x2D, 0x48] // ESC - H
        case .isoIR144:
            return [0x1B, 0x2D, 0x4C] // ESC - L
        case .isoIR148:
            return [0x1B, 0x2D, 0x4D] // ESC - M
        case .isoIR149:
            return [0x1B, 0x24, 0x29, 0x43] // ESC $ ) C
        case .isoIR166:
            return [0x1B, 0x2D, 0x54] // ESC - T
        case .isoIR203:
            return [0x1B, 0x2D, 0x62] // ESC - b
        case .isoIR58:
            return [0x1B, 0x24, 0x29, 0x41] // ESC $ ) A
        default:
            return nil
        }
    }

    // MARK: - ISO 2022 support

    /// Whether the set may be combined with others through ISO 2022 code extensions.
    /// UTF-8, GB18030 and GBK may not (PS3.3 Table C.12-5).
    var usesCodeExtensions: Bool {
        switch self {
        case .isoIR192, .gb18030, .gbk: return false
        default: return true
        }
    }

    /// The code element this set is designated to (PS3.3 Tables C.12-3 and C.12-4), or nil
    /// for sets used without code extensions.
    var codeElement: ISO2022.CodeElement? {
        switch self {
        case .isoIR6, .isoIR14, .isoIR87, .isoIR159: return .g0
        case .isoIR192, .gb18030, .gbk: return nil
        default: return .g1
        }
    }

    /// The bytes that represent `scalar` in this set once it is designated, or nil if the
    /// set cannot represent it. G0 sets are written in 02/01-07/14 and G1 sets in 10/00-15/15.
    func iso2022Bytes(for scalar: Unicode.Scalar) -> [UInt8]? {
        let character = String(scalar)
        switch self {
        case .isoIR6, .isoIR192, .gb18030, .gbk:
            return nil
        case .isoIR14:
            // JIS X 0201 Romaji: YEN SIGN at 05/12 and OVERLINE at 07/14.
            switch scalar {
            case "\u{00A5}": return [0x5C]
            case "\u{203E}": return [0x7E]
            default: return nil
            }
        case .isoIR13:
            // JIS X 0201 Katakana: U+FF61-U+FF9F at 10/01-13/15.
            guard (0xFF61...0xFF9F).contains(scalar.value) else { return nil }
            return [UInt8(0xA1 + scalar.value - 0xFF61)]
        case .isoIR87, .isoIR159:
            // ISO-2022-JP-1 writes ESC <designation> b1 b2 ESC ( B; keep b1 b2 only
            // when the designation is this set's.
            guard let data = character.data(using: ISO2022.iso2022JP1),
                  let designation = escapeSequenceToG0() else { return nil }
            let bytes = [UInt8](data)
            let expected = designation.count + 2 + 3
            guard bytes.count == expected, Array(bytes.prefix(designation.count)) == designation else {
                return nil
            }
            return Array(bytes[designation.count..<designation.count + 2])
        case .isoIR149, .isoIR58:
            // KS X 1001 and GB 2312 in G1 are EUC-KR and EUC-CN two-byte characters.
            guard let data = character.data(using: stringEncoding), data.count == 2,
                  data.allSatisfy({ $0 >= 0xA1 }) else { return nil }
            return [UInt8](data)
        default:
            // ISO 8859 parts: one byte in the upper half.
            guard let data = character.data(using: stringEncoding), data.count == 1,
                  let byte = data.first, byte >= 0xA0 else { return nil }
            return [byte]
        }
    }
}
