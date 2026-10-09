import XCTest
import DICOMNetwork
@testable import DICOMPrintKit

/// D242 (2026-10-06): PrintOptionCatalog film destinations accept any BIN_i.
/// PS3.3 2026a Table C.13-1 Film Destination (2000,0040): MAGAZINE, PROCESSOR, BIN_i —
/// "numbered sequentially starting from 1 and no maximum is placed on the number of
/// BINs. The encoding of the BIN number shall not contain leading zeros."
final class FilmDestinationCatalogTokenTests: XCTestCase {

    func testPickerDefaultsUnchanged() {
        XCTAssertEqual(PrintOptionCatalog.filmDestinations.map(\.cliToken),
                       ["magazine", "processor", "bin-1", "bin-2"])
        for row in PrintOptionCatalog.filmDestinations {
            XCTAssertEqual(FilmDestination(catalogToken: row.cliToken), row.value)
            XCTAssertEqual(row.value.catalogToken, row.cliToken)
        }
    }

    func testAnyBinIsAccepted() {
        XCTAssertEqual(FilmDestination(catalogToken: "bin-3"), .bin(3))
        XCTAssertEqual(FilmDestination(catalogToken: "BIN_42")?.rawValue, "BIN_42")
        XCTAssertEqual(FilmDestination(catalogToken: " Bin-1000 ")?.catalogToken, "bin-1000")
        XCTAssertEqual(FilmDestination(catalogToken: "MAGAZINE"), .magazine)
        XCTAssertEqual(FilmDestination(catalogToken: "Processor"), .processor)
    }

    func testRefusals() {
        for token in ["bin-0", "bin-01", "BIN_03", "bin-", "bin--1", "tray", ""] {
            XCTAssertNil(FilmDestination(catalogToken: token), token)
        }
        XCTAssertTrue(FilmDestination.catalogTokenList.contains("bin-N = BIN_N"))
    }
}
