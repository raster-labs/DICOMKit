import Foundation
import Testing
@testable import DICOMCore

@Suite("DICOM DT instant formatting")
struct DICOMDateTimeFormattingTests {
    @Test("Compact DT preserves a fractional instant with an explicit offset")
    func fractionalInstant() throws {
        let source = Date(timeIntervalSince1970: 1_792_816_200.123456)
        for minutes in [0, 330, -480] {
            let dt = try #require(DICOMDateTime(date: source, timeZone: TimeZone(secondsFromGMT: minutes * 60)!))
            #expect(dt.timezoneOffsetMinutes == minutes)
            #expect(dt.microsecond == 123456)
            #expect(abs(try #require(dt.toDate()).timeIntervalSince(source)) < 0.0000011)
            #expect(DICOMValueRules.parseDateTime(dt.dicomString) == dt)
        }
    }

    @Test("Microsecond rounding carries across the day boundary")
    func roundingCarry() throws {
        let calendar = Calendar(identifier: .gregorian)
        let midnight = try #require(calendar.date(from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026, month: 10, day: 25)))
        let dt = try #require(DICOMDateTime(date: midnight.addingTimeInterval(-0.0000002)))
        #expect(dt.dicomString == "20261025000000.000000+0000")
    }
}
