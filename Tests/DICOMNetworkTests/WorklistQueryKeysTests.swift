import XCTest
import DICOMCore
import DICOMDictionary
@testable import DICOMNetwork

/// Tests for MWL scheduled-date/time filter resolution (PS3.4 C.2.2.2.5, K.6.1).
final class WorklistQueryKeysTests: XCTestCase {

    // MARK: - Date: Single Value Matching

    func testResolveScheduledDate_exact() throws {
        XCTAssertEqual(try WorklistQueryKeys.resolveScheduledDate("20240315"), "20240315")
    }

    func testResolveScheduledDate_today() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        XCTAssertEqual(try WorklistQueryKeys.resolveScheduledDate("today"), formatter.string(from: Date()))
        XCTAssertEqual(try WorklistQueryKeys.resolveScheduledDate("TODAY"), formatter.string(from: Date()))
    }

    func testResolveScheduledDate_tomorrow() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        XCTAssertEqual(try WorklistQueryKeys.resolveScheduledDate("tomorrow"), formatter.string(from: tomorrow))
    }

    func testResolveScheduledDate_invalidThrows() {
        XCTAssertThrowsError(try WorklistQueryKeys.resolveScheduledDate("2024-03-15"))
        XCTAssertThrowsError(try WorklistQueryKeys.resolveScheduledDate("bogus"))
        XCTAssertThrowsError(try WorklistQueryKeys.resolveScheduledDate("202403"))
    }

    // MARK: - Date: Range Matching (PS3.4 C.2.2.2.5.1)

    func testResolveScheduledDate_closedRange() throws {
        XCTAssertEqual(try WorklistQueryKeys.resolveScheduledDate("20240701-20240707"), "20240701-20240707")
    }

    func testResolveScheduledDate_openStartRange() throws {
        XCTAssertEqual(try WorklistQueryKeys.resolveScheduledDate("-20240707"), "-20240707")
    }

    func testResolveScheduledDate_openEndRange() throws {
        XCTAssertEqual(try WorklistQueryKeys.resolveScheduledDate("20240701-"), "20240701-")
    }

    func testResolveScheduledDate_rangeWithTodayTomorrowBounds() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let today = formatter.string(from: Date())
        XCTAssertEqual(try WorklistQueryKeys.resolveScheduledDate("today-"), "\(today)-")
        XCTAssertEqual(try WorklistQueryKeys.resolveScheduledDate("-today"), "-\(today)")
    }

    func testResolveScheduledDate_malformedRangeThrows() {
        // Both bounds empty
        XCTAssertThrowsError(try WorklistQueryKeys.resolveScheduledDate("-"))
        // More than one hyphen
        XCTAssertThrowsError(try WorklistQueryKeys.resolveScheduledDate("20240701-20240707-20240709"))
        // Invalid bound
        XCTAssertThrowsError(try WorklistQueryKeys.resolveScheduledDate("2024-20240707"))
    }

    // MARK: - Time: Single Value Matching

    func testResolveScheduledTime_exact() throws {
        XCTAssertEqual(try WorklistQueryKeys.resolveScheduledTime("103000"), "103000")
    }

    func testResolveScheduledTime_shortForms() throws {
        XCTAssertEqual(try WorklistQueryKeys.resolveScheduledTime("10"), "10")
        XCTAssertEqual(try WorklistQueryKeys.resolveScheduledTime("1030"), "1030")
    }

    func testResolveScheduledTime_fraction() throws {
        XCTAssertEqual(try WorklistQueryKeys.resolveScheduledTime("100000.123456"), "100000.123456")
    }

    func testResolveScheduledTime_invalidThrows() {
        XCTAssertThrowsError(try WorklistQueryKeys.resolveScheduledTime("10:00"))
        XCTAssertThrowsError(try WorklistQueryKeys.resolveScheduledTime("bogus"))
    }

    // MARK: - Time: Range Matching (PS3.4 C.2.2.2.5.2)

    func testResolveScheduledTime_closedRange() throws {
        XCTAssertEqual(try WorklistQueryKeys.resolveScheduledTime("1000-1800"), "1000-1800")
    }

    func testResolveScheduledTime_openStartRange() throws {
        XCTAssertEqual(try WorklistQueryKeys.resolveScheduledTime("-1800"), "-1800")
    }

    func testResolveScheduledTime_openEndRange() throws {
        XCTAssertEqual(try WorklistQueryKeys.resolveScheduledTime("1000-"), "1000-")
    }

    func testResolveScheduledTime_malformedRangeThrows() {
        XCTAssertThrowsError(try WorklistQueryKeys.resolveScheduledTime("-"))
        XCTAssertThrowsError(try WorklistQueryKeys.resolveScheduledTime("1000-1800-2000"))
    }

    // MARK: - forQuery integration

    func testForQuery_setsBothDateAndTimeMatchingKeys() throws {
        let keys = try WorklistQueryKeys.forQuery(date: "20240705-20240707", time: "1000-1800")
        XCTAssertEqual(keys.allSPSKeys[Tag(group: 0x0040, element: 0x0002)], "20240705-20240707")
        XCTAssertEqual(keys.allSPSKeys[Tag(group: 0x0040, element: 0x0003)], "1000-1800")
    }

    func testForQuery_emptyDateAndTimeOmitted() throws {
        let keys = try WorklistQueryKeys.forQuery()
        XCTAssertEqual(keys.allSPSKeys[Tag(group: 0x0040, element: 0x0002)], "")
        XCTAssertEqual(keys.allSPSKeys[Tag(group: 0x0040, element: 0x0003)], "")
    }

    func testForQuery_invalidDatePropagatesError() {
        XCTAssertThrowsError(try WorklistQueryKeys.forQuery(date: "not-a-date"))
    }

    func testForQuery_invalidTimePropagatesError() {
        XCTAssertThrowsError(try WorklistQueryKeys.forQuery(time: "not-a-time"))
    }

    // MARK: - Scheduled Performing Physician's Name (PS3.4 Table K.6-1 Required Matching Key)

    func testForQuery_setsPerformingPhysicianMatchingKey() throws {
        let keys = try WorklistQueryKeys.forQuery(performingPhysician: "SMITH^JOHN")
        XCTAssertEqual(keys.allSPSKeys[Tag(group: 0x0040, element: 0x0006)], "SMITH^JOHN")
    }

    func testForQuery_performingPhysicianWildcardPassedThrough() throws {
        let keys = try WorklistQueryKeys.forQuery(performingPhysician: "SMITH*")
        XCTAssertEqual(keys.allSPSKeys[Tag(group: 0x0040, element: 0x0006)], "SMITH*")
    }

    func testForQuery_omittedPerformingPhysicianStaysUniversalMatch() throws {
        let keys = try WorklistQueryKeys.forQuery()
        // Still requested as a Return Key, just not filtered on.
        XCTAssertEqual(keys.allSPSKeys[Tag(group: 0x0040, element: 0x0006)], "")
    }

    // MARK: - Scheduled Station AE Title (PS3.5 Table 6.2-1, PS3.4 C.2.2.2.4)

    func testStationAETitle_validValuesAccepted() throws {
        XCTAssertNoThrow(try WorklistQueryKeys.validateScheduledStationAETitle("CT1"))
        XCTAssertNoThrow(try WorklistQueryKeys.validateScheduledStationAETitle("CT_ROOM-1 A"))
        XCTAssertNoThrow(try WorklistQueryKeys.validateScheduledStationAETitle("ABCDEFGHIJKLMNOP"), "16 characters")
        XCTAssertNoThrow(try WorklistQueryKeys.validateScheduledStationAETitle(""), "empty is a Universal Match")
        let keys = try WorklistQueryKeys.forQuery(station: "CT1")
        XCTAssertEqual(keys.allSPSKeys[Tag(group: 0x0040, element: 0x0001)], "CT1")
    }

    /// PS3.4 2026a Table K.6-1: "Scheduled Station AE Title shall be retrieved with
    /// Single Value Matching only" — wild card characters are refused (D81).
    func testStationAETitle_wildcardsRefusedSingleValueMatchingOnly() throws {
        XCTAssertThrowsError(try WorklistQueryKeys.validateScheduledStationAETitle("CT*"))
        XCTAssertThrowsError(try WorklistQueryKeys.validateScheduledStationAETitle("CT?"))
        XCTAssertThrowsError(try WorklistQueryKeys.forQuery(station: "CT*"))
        XCTAssertTrue(WorklistDateFilterError.invalidStationAETitle("CT*").description.contains("Table K.6-1"))
    }

    func testStationAETitle_invalidValuesThrow() {
        func assertInvalid(_ value: String, _ why: String, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertThrowsError(try WorklistQueryKeys.validateScheduledStationAETitle(value), why, file: file, line: line) { error in
                guard case WorklistDateFilterError.invalidStationAETitle(let v) = error else {
                    return XCTFail("expected invalidStationAETitle, got \(error)", file: file, line: line)
                }
                XCTAssertEqual(v, value, file: file, line: line)
                XCTAssertTrue(String(describing: error).contains("PS3.5 Table 6.2-1"), file: file, line: line)
            }
            XCTAssertThrowsError(try WorklistQueryKeys.forQuery(station: value), why, file: file, line: line)
        }
        assertInvalid("ABCDEFGHIJKLMNOPQ", "17 characters")
        assertInvalid("CT\\1", "backslash")
        assertInvalid("CT\u{01}", "control character")
        assertInvalid("CT\u{7F}", "DEL")
        assertInvalid("CTÜ", "outside the default repertoire")
    }

    func testDefaultKeys_specificCharacterSetIsAnEmptyReturnKey() {
        XCTAssertEqual(WorklistQueryKeys.default().allKeys[.specificCharacterSet], "",
                       "the value is chosen when the Identifier is built, not hard-coded")
        XCTAssertNil(WorklistQueryKeys.default().specificCharacterSetOverride)
        XCTAssertEqual(WorklistQueryKeys.default().specificCharacterSet("ISO_IR 192").specificCharacterSetOverride, "ISO_IR 192")
    }

    // MARK: - Tag-number correctness vs. the DICOM data dictionary

    /// Guards against mislabeled tag numbers in the MWL key set. Every tag the query
    /// sends is checked against the data dictionary by NAME, so a wrong tag number
    /// (e.g. the (0032,1070) Requested Contrast Agent / (0032,1060) Requested Procedure
    /// Description mix-up) fails here instead of silently querying the wrong attribute.
    func testDefaultKeys_tagNumbersMatchDictionaryNames() throws {
        let expectedTopLevel: [(Tag, String)] = [
            (Tag(group: 0x0008, element: 0x0005), "Specific Character Set"),
            (Tag(group: 0x0010, element: 0x0010), "Patient's Name"),
            (Tag(group: 0x0010, element: 0x0020), "Patient ID"),
            (Tag(group: 0x0010, element: 0x0030), "Patient's Birth Date"),
            (Tag(group: 0x0010, element: 0x0040), "Patient's Sex"),
            (Tag(group: 0x0020, element: 0x000D), "Study Instance UID"),
            (Tag(group: 0x0008, element: 0x0050), "Accession Number"),
            (Tag(group: 0x0008, element: 0x0090), "Referring Physician's Name"),
            (Tag(group: 0x0040, element: 0x1001), "Requested Procedure ID"),
            (Tag(group: 0x0032, element: 0x1060), "Requested Procedure Description"),
        ]
        let expectedSPS: [(Tag, String)] = [
            (Tag(group: 0x0040, element: 0x0001), "Scheduled Station AE Title"),
            (Tag(group: 0x0040, element: 0x0002), "Scheduled Procedure Step Start Date"),
            (Tag(group: 0x0040, element: 0x0003), "Scheduled Procedure Step Start Time"),
            (Tag(group: 0x0008, element: 0x0060), "Modality"),
            (Tag(group: 0x0040, element: 0x0006), "Scheduled Performing Physician's Name"),
            (Tag(group: 0x0040, element: 0x0007), "Scheduled Procedure Step Description"),
            (Tag(group: 0x0040, element: 0x0009), "Scheduled Procedure Step ID"),
            (Tag(group: 0x0040, element: 0x0010), "Scheduled Station Name"),
            (Tag(group: 0x0040, element: 0x0020), "Scheduled Procedure Step Status"),
        ]

        let keys = WorklistQueryKeys.default()

        for (tag, name) in expectedTopLevel {
            XCTAssertNotNil(keys.allKeys[tag],
                            "\(name) \(tag) missing from default() top-level keys")
            XCTAssertEqual(DataElementDictionary.lookup(tag: tag)?.name, name,
                           "Tag \(tag) is not \(name) per the DICOM data dictionary")
        }
        for (tag, name) in expectedSPS {
            XCTAssertNotNil(keys.allSPSKeys[tag],
                            "\(name) \(tag) missing from default() SPS keys")
            XCTAssertEqual(DataElementDictionary.lookup(tag: tag)?.name, name,
                           "Tag \(tag) is not \(name) per the DICOM data dictionary")
        }

        // (0032,1070) is Requested Contrast Agent and must NOT be queried as the
        // Requested Procedure Description.
        XCTAssertNil(keys.allKeys[Tag(group: 0x0032, element: 0x1070)],
                     "(0032,1070) Requested Contrast Agent must not be in the MWL key set")
    }

    // MARK: - Default return keys

    /// Requested Procedure Description is (0032,1060). The default keys used to
    /// request (0032,1070) — Requested Contrast Agent — so a conforming SCP never
    /// returned the description to either the dicom-mwl CLI or DICOMStudio.
    func testDefaultKeys_requestRequestedProcedureDescriptionTag() {
        let keys = WorklistQueryKeys.default()
        XCTAssertNotNil(keys.allKeys[.requestedProcedureDescription])
        XCTAssertNotNil(keys.allKeys[Tag(group: 0x0032, element: 0x1060)])
        XCTAssertNil(keys.allKeys[.requestedContrastAgent])
    }
}
