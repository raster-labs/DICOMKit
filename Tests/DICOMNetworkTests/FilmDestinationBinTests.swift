import XCTest
@testable import DICOMNetwork

/// P-BIN (closes D89). Film Destination (2000,0040), PS3.3 2026a Table C.13-1: "BIN_i …
/// Film sorter BINs shall be numbered sequentially starting from 1 and no maximum is placed
/// on the number of BINs. The encoding of the BIN number shall not contain leading zeros."
final class FilmDestinationBinTests: XCTestCase {

    func testAnyBinNumberIsCarried() {
        XCTAssertEqual(FilmDestination.bin(1).rawValue, "BIN_1")
        XCTAssertEqual(FilmDestination.bin(3).rawValue, "BIN_3")
        XCTAssertEqual(FilmDestination.bin(250).rawValue, "BIN_250")
        XCTAssertEqual(FilmDestination.bin(17).binNumber, 17)
        XCTAssertNil(FilmDestination.magazine.binNumber)
        XCTAssertEqual(FilmDestination.magazine.rawValue, "MAGAZINE")
        XCTAssertEqual(FilmDestination.processor.rawValue, "PROCESSOR")
    }

    func testRawValueParsingFollowsTableC13_1() {
        XCTAssertEqual(FilmDestination(rawValue: "BIN_12"), .bin(12))
        XCTAssertEqual(FilmDestination(rawValue: "MAGAZINE"), .magazine)
        XCTAssertEqual(FilmDestination(rawValue: "PROCESSOR"), .processor)
        XCTAssertNil(FilmDestination(rawValue: "BIN_0"))     // numbered from 1
        XCTAssertNil(FilmDestination(rawValue: "BIN_03"))    // no leading zeros
        XCTAssertNil(FilmDestination(rawValue: "BIN_"))
        XCTAssertNil(FilmDestination(rawValue: "BIN_-1"))
        XCTAssertNil(FilmDestination(rawValue: "BIN_1A"))
        XCTAssertNil(FilmDestination(rawValue: "bin_1"))     // CS Defined Term is upper case
        XCTAssertNil(FilmDestination(rawValue: "BIN_1234567890123"))  // CS is at most 16 characters
        XCTAssertNotNil(FilmDestination(rawValue: "BIN_999999999999"))
        XCTAssertEqual(FilmDestination.bin(FilmDestination.maximumBinNumber).rawValue.count, 16)
    }

    @available(*, deprecated)
    func testDeprecatedFixedBinsStillWork() {
        XCTAssertEqual(FilmDestination.bin1, .bin(1))
        XCTAssertEqual(FilmDestination.bin2.rawValue, "BIN_2")
        XCTAssertEqual(FilmDestination.allCases.map(\.rawValue), ["MAGAZINE", "PROCESSOR", "BIN_1", "BIN_2"])
    }

    func testCodableIsASingleStringAndRejectsInvalidTerms() throws {
        let data = try JSONEncoder().encode([FilmDestination.bin(7)])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[\"BIN_7\"]")
        XCTAssertEqual(try JSONDecoder().decode([FilmDestination].self, from: data), [.bin(7)])
        XCTAssertThrowsError(try JSONDecoder().decode([FilmDestination].self, from: Data("[\"BIN_07\"]".utf8)))
    }

    func testSessionWritesTheBinTerm() {
        let session = FilmSession(filmDestination: .bin(5))
        XCTAssertEqual(session.filmDestination.rawValue, "BIN_5")
    }
}
