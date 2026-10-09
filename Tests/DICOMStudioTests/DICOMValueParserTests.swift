// DICOMValueParserTests.swift
// DICOMStudioTests
//
// Tests for DICOMValueParser

import Testing
@testable import DICOMStudio
import Foundation

@Suite("DICOMValueParser Tests")
struct DICOMValueParserTests {

    // MARK: - Date (DA) Formatting

    @Test("Format DICOM date YYYYMMDD")
    func testFormatDate() {
        #expect(DICOMValueParser.formatDate("20230115") == "2023-01-15")
    }

    @Test("Format date with dots")
    func testFormatDateWithDots() {
        #expect(DICOMValueParser.formatDate("2023.01.15") == "2023-01-15")
    }

    @Test("Short date returns original")
    func testFormatDateShort() {
        #expect(DICOMValueParser.formatDate("202") == "202")
    }

    // MARK: - Time (TM) Formatting

    @Test("Format DICOM time HHMMSS")
    func testFormatTime() {
        #expect(DICOMValueParser.formatTime("143025") == "14:30:25")
    }

    @Test("Format time HHMM")
    func testFormatTimeShort() {
        #expect(DICOMValueParser.formatTime("1430") == "14:30")
    }

    @Test("Format time with fractional seconds")
    func testFormatTimeWithFraction() {
        let result = DICOMValueParser.formatTime("143025.123456")
        #expect(result == "14:30:25")
    }

    @Test("Short time returns original")
    func testFormatTimeVeryShort() {
        #expect(DICOMValueParser.formatTime("14") == "14")
    }

    // MARK: - DateTime (DT) Formatting

    @Test("Format full datetime")
    func testFormatDateTime() {
        let result = DICOMValueParser.formatDateTime("20230115143025")
        #expect(result == "2023-01-15 14:30:25")
    }

    @Test("Format date-only datetime")
    func testFormatDateTimeShort() {
        let result = DICOMValueParser.formatDateTime("20230115")
        #expect(result == "2023-01-15")
    }

    // MARK: - Age (AS) Formatting

    @Test("Format age in years")
    func testFormatAgeYears() {
        #expect(DICOMValueParser.formatAge("045Y") == "45 years")
    }

    @Test("Format age in months")
    func testFormatAgeMonths() {
        #expect(DICOMValueParser.formatAge("006M") == "6 months")
    }

    @Test("Format age in weeks")
    func testFormatAgeWeeks() {
        #expect(DICOMValueParser.formatAge("012W") == "12 weeks")
    }

    @Test("Format age in days")
    func testFormatAgeDays() {
        #expect(DICOMValueParser.formatAge("001D") == "1 day")
    }

    @Test("Singular year")
    func testFormatAgeSingularYear() {
        #expect(DICOMValueParser.formatAge("001Y") == "1 year")
    }

    @Test("Invalid age returns original")
    func testFormatAgeInvalid() {
        #expect(DICOMValueParser.formatAge("X") == "X")
    }

    // MARK: - Person Name (PN) Formatting

    @Test("Format full person name")
    func testFormatPersonNameFull() {
        let result = DICOMValueParser.formatPersonName("Doe^John^M^Dr.^Jr.")
        #expect(result == "Dr. John M Doe, Jr.")
    }

    @Test("Format simple person name")
    func testFormatPersonNameSimple() {
        let result = DICOMValueParser.formatPersonName("Doe^John")
        #expect(result == "John Doe")
    }

    @Test("Format family-only name")
    func testFormatPersonNameFamilyOnly() {
        let result = DICOMValueParser.formatPersonName("Doe")
        #expect(result == "Doe")
    }

    @Test("Empty name returns original")
    func testFormatPersonNameEmpty() {
        #expect(DICOMValueParser.formatPersonName("") == "")
    }

    @Test("PN component groups (PS3.5 6.2.1.2) are formatted separately and joined with =")
    func testFormatPersonNameComponentGroups() {
        // The PS3.5 6.2.1.1 example: alphabetic=ideographic=phonetic.
        let result = DICOMValueParser.formatPersonName("Yamada^Tarou=山田^太郎=やまだ^たろう")
        #expect(result == "Tarou Yamada = 太郎 山田 = たろう やまだ")
        // A leading empty group (alphabetic absent) is skipped, not shown as an empty name.
        #expect(DICOMValueParser.formatPersonName("=山田^太郎") == "太郎 山田")
    }

    // MARK: - Decimal String (DS) Formatting

    @Test("Format integer decimal string")
    func testFormatDecimalStringInteger() {
        #expect(DICOMValueParser.formatDecimalString("42") == "42")
    }

    @Test("Format floating point decimal string")
    func testFormatDecimalStringFloat() {
        let result = DICOMValueParser.formatDecimalString("3.14159")
        #expect(result == "3.14159")
    }

    @Test("Format multi-value decimal string")
    func testFormatDecimalStringMulti() {
        let result = DICOMValueParser.formatDecimalString("1.0\\2.0\\3.0")
        #expect(result == "1 \\ 2 \\ 3")
    }

    // MARK: - Integer String (IS) Formatting

    @Test("Format integer string")
    func testFormatIntegerString() {
        #expect(DICOMValueParser.formatIntegerString("42") == "42")
    }

    @Test("Format multi-value integer string")
    func testFormatIntegerStringMulti() {
        let result = DICOMValueParser.formatIntegerString("1\\2\\3")
        #expect(result == "1 \\ 2 \\ 3")
    }

    @Test("Format integer string with spaces")
    func testFormatIntegerStringSpaces() {
        #expect(DICOMValueParser.formatIntegerString("  42  ") == "42")
    }

    // MARK: - UID Formatting

    @Test("Format UID trims whitespace and null")
    func testFormatUID() {
        let result = DICOMValueParser.formatUID("1.2.840.10008.1.2 \0")
        #expect(result == "1.2.840.10008.1.2")
    }

    // MARK: - CS Formatting

    @Test("CS is uppercased")
    func testFormatCS() {
        let result = DICOMValueParser.format(value: "monochrome2", vr: "CS")
        #expect(result == "MONOCHROME2")
    }

    // MARK: - Empty Value

    @Test("Empty value returns (empty)")
    func testEmptyValue() {
        #expect(DICOMValueParser.format(value: "", vr: "LO") == "(empty)")
    }

    @Test("Whitespace-only value returns (empty)")
    func testWhitespaceValue() {
        #expect(DICOMValueParser.format(value: "   ", vr: "LO") == "(empty)")
    }

    // MARK: - Character Set Description

    @Test("UTF-8 character set")
    func testCharacterSetUTF8() {
        #expect(DICOMValueParser.characterSetDescription("ISO_IR 192") == "Unicode (UTF-8)")
    }

    /// PS3.3 2026a Tables C.12-2, C.12-3, C.12-4 and C.12-5: every Defined Term of Specific
    /// Character Set (0008,0005) has a description (none falls through to the raw term).
    static let specificCharacterSetTerms = [
        "ISO_IR 100", "ISO_IR 101", "ISO_IR 109", "ISO_IR 110", "ISO_IR 144", "ISO_IR 127",
        "ISO_IR 126", "ISO_IR 138", "ISO_IR 148", "ISO_IR 203", "ISO_IR 13", "ISO_IR 166",
        "ISO 2022 IR 6", "ISO 2022 IR 100", "ISO 2022 IR 101", "ISO 2022 IR 109", "ISO 2022 IR 110",
        "ISO 2022 IR 144", "ISO 2022 IR 127", "ISO 2022 IR 126", "ISO 2022 IR 138", "ISO 2022 IR 148",
        "ISO 2022 IR 203", "ISO 2022 IR 13", "ISO 2022 IR 166",
        "ISO 2022 IR 87", "ISO 2022 IR 159", "ISO 2022 IR 149", "ISO 2022 IR 58",
        "ISO_IR 192", "GB18030", "GBK",
    ]

    @Test("Every single-valued Specific Character Set Defined Term of PS3.3 2026a C.12-2/C.12-5 is described")
    func testCharacterSetTablesC122AndC125() {
        for term in ["ISO_IR 100", "ISO_IR 101", "ISO_IR 109", "ISO_IR 110", "ISO_IR 144", "ISO_IR 127",
                     "ISO_IR 126", "ISO_IR 138", "ISO_IR 148", "ISO_IR 203", "ISO_IR 13", "ISO_IR 166",
                     "ISO_IR 192", "GB18030", "GBK"] {
            #expect(DICOMValueParser.characterSetDescription(term) != term, "\(term)")
        }
        #expect(DICOMValueParser.characterSetDescription("ISO_IR 203").hasPrefix("Latin-9"))
        #expect(DICOMValueParser.characterSetDescription("GBK") == "Chinese (GBK)")
    }

    @Test("Code-extension terms of PS3.3 2026a C.12-3/C.12-4 the viewer describes")
    func testCharacterSetTablesC123AndC124() {
        for term in Self.specificCharacterSetTerms where term.hasPrefix("ISO 2022") {
            #expect(DICOMValueParser.characterSetDescription(term) != term, "\(term)")
        }
        #expect(DICOMValueParser.characterSetDescription("ISO 2022 IR 58").hasPrefix("Simplified Chinese"))
    }

    @Test("Default character set")
    func testCharacterSetDefault() {
        #expect(DICOMValueParser.characterSetDescription("") == "Default (ASCII)")
    }

    @Test("Latin-1 character set")
    func testCharacterSetLatin1() {
        #expect(DICOMValueParser.characterSetDescription("ISO_IR 100") == "Latin-1 (Western European)")
    }

    @Test("Japanese character set")
    func testCharacterSetJapanese() {
        #expect(DICOMValueParser.characterSetDescription("ISO_IR 13") == "Japanese (JIS X 0201)")
    }

    @Test("Chinese GB18030 character set")
    func testCharacterSetChinese() {
        #expect(DICOMValueParser.characterSetDescription("GB18030") == "Chinese (GB18030)")
    }

    @Test("Unknown character set returns original")
    func testCharacterSetUnknown() {
        #expect(DICOMValueParser.characterSetDescription("CUSTOM") == "CUSTOM")
    }

    @Test("Cyrillic character set")
    func testCharacterSetCyrillic() {
        #expect(DICOMValueParser.characterSetDescription("ISO_IR 144") == "Cyrillic")
    }

    @Test("Arabic character set")
    func testCharacterSetArabic() {
        #expect(DICOMValueParser.characterSetDescription("ISO_IR 127") == "Arabic")
    }

    @Test("Greek character set")
    func testCharacterSetGreek() {
        #expect(DICOMValueParser.characterSetDescription("ISO_IR 126") == "Greek")
    }

    @Test("Hebrew character set")
    func testCharacterSetHebrew() {
        #expect(DICOMValueParser.characterSetDescription("ISO_IR 138") == "Hebrew")
    }

    @Test("Korean character set")
    func testCharacterSetKorean() {
        #expect(DICOMValueParser.characterSetDescription("ISO 2022 IR 149") == "Korean (KS X 1001)")
    }

    @Test("Thai character set")
    func testCharacterSetThai() {
        #expect(DICOMValueParser.characterSetDescription("ISO_IR 166") == "Thai (TIS 620-2533)")
    }

    // MARK: - VR Dispatch

    @Test("Format dispatches to DA parser")
    func testFormatDispatchDA() {
        let result = DICOMValueParser.format(value: "20230115", vr: "DA")
        #expect(result == "2023-01-15")
    }

    @Test("Format dispatches to TM parser")
    func testFormatDispatchTM() {
        let result = DICOMValueParser.format(value: "143025", vr: "TM")
        #expect(result == "14:30:25")
    }

    @Test("Format dispatches to PN parser")
    func testFormatDispatchPN() {
        let result = DICOMValueParser.format(value: "Doe^John", vr: "PN")
        #expect(result == "John Doe")
    }

    @Test("Format dispatches to AS parser")
    func testFormatDispatchAS() {
        let result = DICOMValueParser.format(value: "045Y", vr: "AS")
        #expect(result == "45 years")
    }

    @Test("AE trims whitespace")
    func testFormatAE() {
        let result = DICOMValueParser.format(value: "  PACS  ", vr: "AE")
        #expect(result == "PACS")
    }

    @Test("Unknown VR returns trimmed value")
    func testFormatUnknownVR() {
        let result = DICOMValueParser.format(value: "hello", vr: "XX")
        #expect(result == "hello")
    }
}
