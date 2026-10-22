import Foundation
import Testing
import DICOMCore

@Suite("Strict DICOM TM parsing")
struct StrictDICOMTimeTests {
    @Test("Valid component precision and fractions", arguments: [
        ("14", DICOMTime(hour: 14)),
        ("1430", DICOMTime(hour: 14, minute: 30)),
        ("143025", DICOMTime(hour: 14, minute: 30, second: 25)),
        ("143025.1", DICOMTime(hour: 14, minute: 30, second: 25, microsecond: 100000)),
        ("143025.12", DICOMTime(hour: 14, minute: 30, second: 25, microsecond: 120000)),
        ("143025.123", DICOMTime(hour: 14, minute: 30, second: 25, microsecond: 123000)),
        ("143025.1234", DICOMTime(hour: 14, minute: 30, second: 25, microsecond: 123400)),
        ("143025.12345", DICOMTime(hour: 14, minute: 30, second: 25, microsecond: 123450)),
        ("143025.123456 ", DICOMTime(hour: 14, minute: 30, second: 25, microsecond: 123456)),
        ("070907.0705 ", DICOMTime(hour: 7, minute: 9, second: 7, microsecond: 70500)),
        ("000000.000000", DICOMTime(hour: 0, minute: 0, second: 0, microsecond: 0)),
        ("235959.999999", DICOMTime(hour: 23, minute: 59, second: 59, microsecond: 999999)),
        ("235960", DICOMTime(hour: 23, minute: 59, second: 60)),
        ("005960.5", DICOMTime(hour: 0, minute: 59, second: 60, microsecond: 500000)),
        ("14            ", DICOMTime(hour: 14))
    ])
    func valid(_ input: String, _ expected: DICOMTime) {
        #expect(DICOMTime.parseStrict(input) == expected)
        #expect(DICOMTime.parse(input) == expected)
        let bytes = Array(input.utf8)
        #expect(bytes.withUnsafeBytes { DICOMTime.parseStrict($0) } == expected)
        let element = DataElement(tag: .studyTime, vr: .TM,
                                  length: UInt32(bytes.count), valueData: Data(bytes))
        #expect(element.strictTimeValue == expected)
    }

    @Test("Reject malformed scalar syntax without normalization", arguments: [
        "", " ", "  ", "              ", ".", "..", "1", "021 ", "120", "12345", "123456x", "12345678",
        "123456.1234567", "123456.123456x", "123456.", "12.5", "1234.5",
        " 123456", "\t123456", "123456\t", "123456\n", "\r123456", "123456\0",
        "\u{00A0}123456", "123456\u{00A0}", "１２３４５６", "١٢٣٤٥٦",
        "+1", "-0", "12+100", "1234+1", "123456.+1", "123456.-1",
        "123456.123456.7", "2400", "126000", "125961", "12 456",
        "14             ", "143025.123456  ", "123456Z", "123456+0530",
        "12\\13", "1200-1300", "\"\"", ":", "123456:", "1:23456", "12::3456",
        "12:", "12:34", "12:34:", "12:3456", "1234:56", "12:34:56.", "12:34:56.1234567",
        "12:34:56.123456  "
    ])
    func malformed(_ input: String) {
        #expect(DICOMTime.parseStrict(input) == nil)
        #expect(DICOMTime.parse(input) == nil)
        let bytes = Array(input.utf8)
        #expect(bytes.withUnsafeBytes { DICOMTime.parseStrict($0) } == nil)
        let element = DataElement(tag: .studyTime, vr: .TM,
                                  length: UInt32(bytes.count), valueData: Data(bytes))
        #expect(element.strictTimeValue == nil)
    }

    @Test("Colon compatibility is explicit and strict paths reject it", arguments: [
        "12:34:56", "12:34:56.1", "12:34:56.123456 ", "23:59:60"
    ])
    func legacy(_ input: String) {
        #expect(DICOMTime.parse(input) != nil)
        #expect(DICOMTime.parseStrict(input) == nil)
        let data = Data(input.utf8)
        #expect(data.withUnsafeBytes { DICOMTime.parseStrict($0) } == nil)
        let element = DataElement(tag: .studyTime, vr: .TM, length: UInt32(data.count), valueData: data)
        #expect(element.timeValue != nil)
        #expect(element.strictTimeValue == nil)
    }

    @Test("Raw accessor does not hide invalid padding or wrong VR")
    func originalBytes() {
        for input in [" 123456", "123456\n", "123456\0", "\t123456"] {
            let data = Data(input.utf8)
            let element = DataElement(tag: .studyTime, vr: .TM, length: UInt32(data.count), valueData: data)
            #expect(element.timeValue != nil) // Historical trimmed accessor remains explicit.
            #expect(element.strictTimeValue == nil)
        }
        let wrongVR = DataElement(tag: .studyTime, vr: .LO, length: 6, valueData: Data("123456".utf8))
        #expect(wrongVR.strictTimeValue == nil)
        #expect(DICOMTime.parseStrict(UnsafeRawBufferPointer(start: nil, count: 0)) == nil)
        let nonASCII: [UInt8] = [49, 50, 0xFF, 52, 53, 54]
        #expect(nonASCII.withUnsafeBytes { DICOMTime.parseStrict($0) } == nil)
        let framed: [UInt8] = [0xFF, 49, 50, 51, 52, 53, 54, 0xFF]
        let parsed = framed.withUnsafeBytes { DICOMTime.parseStrict(UnsafeRawBufferPointer(rebasing: $0[1..<7])) }
        #expect(parsed == DICOMTime(hour: 12, minute: 34, second: 56))
    }

    @Test("All minute values preserve component boundaries")
    func allMinutes() {
        for hour in 0..<24 {
            for minute in 0..<60 {
                let input = String(format: "%02d%02d", hour, minute)
                #expect(DICOMTime.parseStrict(input) == DICOMTime(hour: hour, minute: minute))
            }
        }
    }

    @Test("Excessive input is rejected rather than scanned or truncated")
    func excessiveInput() {
        let input = "123456." + String(repeating: "1", count: 100_000)
        #expect(DICOMTime.parseStrict(input) == nil)
        #expect(DICOMTime.parse(input) == nil)
        let bytes = Array(input.utf8)
        #expect(bytes.withUnsafeBytes { DICOMTime.parseStrict($0) } == nil)
    }
}
