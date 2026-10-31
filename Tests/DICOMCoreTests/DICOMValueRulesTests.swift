import XCTest
import Foundation
@testable import DICOMCore

final class DICOMValueRulesTests: XCTestCase {
    func testStoredTextGrammarRejectsTheRegisteredFailures() {
        let invalid: [(VR, String)] = [(.AS, "Y123"), (.DA, "20260231"), (.DS, "1..2"),
                                      (.IS, "++1"), (.DT, "20269999112233"), (.TM, "256199"),
                                      (.UI, "1..02"), (.AE, "Müller")]
        for (vr, text) in invalid { XCTAssertNotNil(DICOMValueRules.valueProblem(text, vr: vr), "\(vr): \(text)") }
        for vr in [VR.AS, .DA, .DS, .IS, .DT, .TM, .UI, .AE] {
            XCTAssertNil(DICOMValueRules.valueProblem("", vr: vr), "Zero-length \(vr) is encodable")
        }
    }

    func testNumericTextGrammarAndBounds() {
        for valid in ["0", "-1", "+.5", "1.", "-1.25e+3", " +1.0 "] {
            XCTAssertNil(DICOMValueRules.valueProblem(valid, vr: .DS), valid)
        }
        for invalid in ["NaN", "Infinity", "1e", "--1", "1 2", ".", "12345678901234567"] {
            XCTAssertNotNil(DICOMValueRules.valueProblem(invalid, vr: .DS), invalid)
        }
        for valid in ["-2147483648", "+2147483647", " 1 "] { XCTAssertNil(DICOMValueRules.valueProblem(valid, vr: .IS), valid) }
        for invalid in ["2147483648", "-2147483649", "1.0", "+", "1e2"] { XCTAssertNotNil(DICOMValueRules.valueProblem(invalid, vr: .IS), invalid) }
    }

    func testGregorianDateBoundaries() {
        for valid in ["20000229", "20240229", "15000228", "00010101", "99991231"] { XCTAssertTrue(DICOMValueRules.isValidDate(valid), valid) }
        for invalid in ["19000229", "20260229", "20260431", "20260001", "20260100", "00000101", " 20260101", "2026-01-01"] { XCTAssertFalse(DICOMValueRules.isValidDate(invalid), invalid) }
    }

    func testPartialDateTimeAndOffsets() throws {
        for valid in ["2026", "202602", "20260228", "2026022812", "202602281234", "20260228123456",
                      "20260228123456.1", "20260228123456.123456+0530", "2026-1200", "2026+1400", "2026+0000", "20260228123460", "2026 "] {
            XCTAssertTrue(DICOMValueRules.isValidDateTime(valid), valid)
        }
        for invalid in ["202", "20261", "2026023", "20260230", "2026022824", "202602281260", "20260228123461",
                        "2026.1", "202602281234.1", "20260228123456.", "20260228123456.1234567", "2026-1201", "2026+1401",
                        "2026+1360", "2026-0000", " 2026", "2026 01", "2026-01-01T12:00:00Z"] {
            XCTAssertFalse(DICOMValueRules.isValidDateTime(invalid), invalid)
        }
        let parsed = try XCTUnwrap(DICOMValueRules.parseDateTime("20260228123456.12-0530"))
        XCTAssertEqual(parsed.microsecond, 120000)
        XCTAssertEqual(parsed.timezoneOffsetMinutes, -330)
        XCTAssertNil(try XCTUnwrap(DICOMValueRules.parseDateTime("2026+1400")).month)
    }

    func testTimePrecisionAndLeapSecondSyntax() {
        for valid in ["00", "2359", "235960", "123456.123456", "12 "] { XCTAssertTrue(DICOMValueRules.isValidTime(valid), valid) }
        for invalid in ["", "1", "2400", "1260", "123461", "12.5", "1234.5", "123456.", "123456.1234567", " 12"] { XCTAssertFalse(DICOMValueRules.isValidTime(invalid), invalid) }
    }

    func testUIDComponentsAndLength() {
        for valid in ["1.2.840.10008.1.2", "0.0.1", "2.25.123"] { XCTAssertTrue(DICOMValueRules.isValidUID(valid), valid) }
        for invalid in ["", ".1.2", "1.2.", "1..2", "1.02", "01.2", "1.2 ", "1.2\0", "1.2a", String(repeating: "1", count: 65)] { XCTAssertFalse(DICOMValueRules.isValidUID(invalid), invalid) }
    }

    func testMultiplicityAndMalformedBinaryWidths() throws {
        XCTAssertTrue(try XCTUnwrap(DICOMValueRules.ValueMultiplicity("2-2n")).allows(6))
        XCTAssertFalse(try XCTUnwrap(DICOMValueRules.ValueMultiplicity("2-2n")).allows(3))
        XCTAssertTrue(try XCTUnwrap(DICOMValueRules.ValueMultiplicity("1-3")).allows(2))
        XCTAssertFalse(try XCTUnwrap(DICOMValueRules.ValueMultiplicity("1-3")).allows(4))
        for invalid in ["", "0", "1-0n", "2-1", "1-", "-1"] { XCTAssertNil(DICOMValueRules.ValueMultiplicity(invalid), invalid) }
        let tag = Tag(group: 0x0028, element: 0x0010)
        for (vr, width) in [(VR.US, 2), (.SS, 2), (.UL, 4), (.FL, 4), (.FD, 8), (.AT, 4)] {
            let valid = DataElement(tag: tag, vr: vr, length: UInt32(width * 2), valueData: Data(repeating: 0, count: width * 2))
            XCTAssertEqual(DICOMValueRules.valueCount(of: valid), 2)
            XCTAssertNil(DICOMValueRules.binaryLengthProblem(of: valid))
            let invalid = DataElement(tag: tag, vr: vr, length: UInt32(width + 1), valueData: Data(repeating: 0, count: width + 1))
            XCTAssertNil(DICOMValueRules.valueCount(of: invalid))
            XCTAssertNotNil(DICOMValueRules.binaryLengthProblem(of: invalid))
        }
    }

    func testDecodedValuesPreserveIllegalLeadingWhitespaceAndLegalPadding() {
        let tag = Tag(group: 0x0008, element: 0x002A)
        let leading = DataElement.string(tag: tag, vr: .DT, value: " 2026")
        XCTAssertEqual(DICOMValueRules.values(of: leading), [" 2026"])
        XCTAssertNotNil(DICOMValueRules.valueProblem(DICOMValueRules.values(of: leading)[0], vr: .DT))
        let uid = DataElement(tag: tag, vr: .UI, length: 6, valueData: Data("1.2.3\0".utf8))
        XCTAssertEqual(DICOMValueRules.values(of: uid), ["1.2.3"])
        let latin = DataElement(tag: tag, vr: .PN, length: 6, valueData: Data([0x4D, 0xFC, 0x6C, 0x6C, 0x65, 0x72]), specificCharacterSet: "ISO_IR 100")
        XCTAssertEqual(DICOMValueRules.values(of: latin), ["Müller"])
    }

    func testDelimiterOnlyFieldsAreEmptyButMixedValuesRetainMultiplicity() {
        let tag = Tag(group: 0x0010, element: 0x0030)
        for value in ["", "\\", "\\\\"] {
            let element = DataElement.string(tag: tag, vr: .DA, value: value)
            XCTAssertEqual(DICOMValueRules.valueCount(of: element), 0)
        }
        let mixed = DataElement.string(tag: tag, vr: .DS, value: "1\\")
        XCTAssertEqual(DICOMValueRules.values(of: mixed), ["1", ""])
        XCTAssertEqual(DICOMValueRules.valueCount(of: mixed), 2)
    }

    func testPersonNameGroupDelimiterCountsTowardLimit() {
        XCTAssertNil(DICOMValueRules.valueProblem(String(repeating: "A", count: 63) + "=B", vr: .PN))
        XCTAssertNotNil(DICOMValueRules.valueProblem(String(repeating: "A", count: 64) + "=B", vr: .PN))
        XCTAssertNil(DICOMValueRules.valueProblem(String(repeating: "A", count: 64), vr: .PN))
    }

    func testC1ControlsAreRejectedAndTextLineControlsRemainLegal() {
        for vr in [VR.LO, .PN, .UT] {
            XCTAssertNotNil(DICOMValueRules.valueProblem("A\u{0085}B", vr: vr))
            XCTAssertNotNil(DICOMValueRules.valueProblem("A\u{009F}B", vr: vr))
        }
        XCTAssertNil(DICOMValueRules.valueProblem("A\tB\nC", vr: .UT))
        XCTAssertNotNil(DICOMValueRules.valueProblem("A\tB", vr: .LO))
    }
}
