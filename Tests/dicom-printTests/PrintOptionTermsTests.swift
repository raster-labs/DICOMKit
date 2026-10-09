import XCTest
import ArgumentParser
import DICOMNetwork
@testable import dicom_print

/// `dicom-print send` option vocabularies against DICOM 2026a.
///
/// The expected terms are the Defined Terms / Enumerated Values of PS3.3 2026a
/// Tables C.13-1 (Basic Film Session Presentation Module), C.13-3 (Basic Film Box
/// Presentation Module) and C.11-4 (Presentation LUT Module), dumped from the
/// DocBook by script.
final class PrintOptionTermsTests: XCTestCase {

    private func terms<T: StandardTermOption>(_ type: T.Type) -> [String] {
        T.allCases.compactMap(\.standardTerm)
    }

    // PS3.3 Table C.13-3, Film Size ID (2010,0050): 12 Defined Terms.
    func testFilmSizeOffersEveryFilmSizeID() {
        XCTAssertEqual(terms(FilmSizeOption.self), [
            "8INX10IN", "8_5INX11IN", "10INX12IN", "10INX14IN", "11INX14IN", "11INX17IN",
            "14INX14IN", "14INX17IN", "24CMX24CM", "24CMX30CM", "A4", "A3"])
    }

    // PS3.3 Table C.13-1, Medium Type (2000,0030): 5 Defined Terms.
    func testMediumOffersEveryMediumType() {
        XCTAssertEqual(terms(MediumOption.self), [
            "PAPER", "CLEAR FILM", "BLUE FILM", "MAMMO CLEAR FILM", "MAMMO BLUE FILM"])
        XCTAssertEqual(MediumOption(argument: "mammo-clear-film")?.mediumType.wireValue, "MAMMO CLEAR FILM")
        XCTAssertEqual(MediumOption(argument: "mammo-blue-film")?.mediumType.wireValue, "MAMMO BLUE FILM")
    }

    // PS3.3 Table C.13-1, Print Priority (2000,0020): Enumerated Values HIGH, MED, LOW.
    func testPrintPrioritySendsEnumeratedValues() {
        XCTAssertEqual(Set(terms(PrintPriorityOption.self)), ["HIGH", "MED", "LOW"])
        XCTAssertEqual(PrintPriorityOption(argument: "medium")?.printPriority.rawValue, "MED")
    }

    // PS3.3 Table C.13-1, Film Destination (2000,0040): MAGAZINE, PROCESSOR, BIN_i.
    func testFilmDestinationTerms() {
        XCTAssertEqual(FilmDestinationOption(argument: "magazine")?.standardTerm, "MAGAZINE")
        XCTAssertEqual(FilmDestinationOption(argument: "processor")?.standardTerm, "PROCESSOR")
        // P-BIN: "Film sorter BINs shall be numbered sequentially starting from 1 and no
        // maximum is placed on the number of BINs" — any bin-N / BIN_N is sent.
        XCTAssertEqual(FilmDestinationOption(argument: "bin-1")?.standardTerm, "BIN_1")
        XCTAssertEqual(FilmDestinationOption(argument: "bin-3")?.standardTerm, "BIN_3")
        XCTAssertEqual(FilmDestinationOption(argument: "BIN_42")?.standardTerm, "BIN_42")
        XCTAssertEqual(FilmDestinationOption(argument: "bin_7")?.rawValue, "bin-7")
        // "The encoding of the BIN number shall not contain leading zeros."
        XCTAssertNil(FilmDestinationOption(argument: "bin-03"))
        XCTAssertNil(FilmDestinationOption(argument: "bin-0"))
        XCTAssertNil(FilmDestinationOption(argument: "bin-"))
        XCTAssertNil(FilmDestinationOption(argument: "tray"))
        XCTAssertNoThrow(try SendCommand.parse(["pacs://h:104", "x.dcm", "--aet", "A", "--film-destination", "bin-12"]))
        XCTAssertThrowsError(try SendCommand.parse(["pacs://h:104", "x.dcm", "--aet", "A", "--film-destination", "bin-012"]))
        XCTAssertEqual(try SendCommand.parse(["pacs://h:104", "x.dcm", "--aet", "A", "--film-destination", "BIN_9"])
                        .filmDestination.filmDestination, .bin(9))
    }

    // PS3.3 Table C.13-3: Film Orientation PORTRAIT, LANDSCAPE; Magnification Type
    // REPLICATE, BILINEAR, CUBIC, NONE.
    func testOrientationAndMagnificationTerms() {
        XCTAssertEqual(terms(OrientationOption.self), ["PORTRAIT", "LANDSCAPE"])
        XCTAssertEqual(terms(MagnificationOption.self), ["REPLICATE", "BILINEAR", "CUBIC", "NONE"])
    }

    // PS3.3 Table C.11-4, Presentation LUT Shape (2050,0020): IDENTITY, LIN OD only.
    // `inverse` sends no shape.
    func testPresentationLUTShapeTerms() {
        XCTAssertEqual(terms(PresentationLUTOption.self), ["IDENTITY", "LIN OD"])
        XCTAssertNil(PresentationLUTOption.inverse.standardTerm)
    }

    // The standard term itself is accepted as an alias, in any case.
    func testStandardTermsAreAcceptedAsAliases() {
        XCTAssertEqual(FilmSizeOption(argument: "14INX17IN"), .size14x17)
        XCTAssertEqual(FilmSizeOption(argument: "8_5inx11in"), .size8_5x11)
        XCTAssertEqual(FilmSizeOption(argument: "A4"), .a4)
        XCTAssertEqual(PrintPriorityOption(argument: "MED"), .medium)
        XCTAssertEqual(MediumOption(argument: "CLEAR FILM"), .clearFilm)
        XCTAssertEqual(FilmDestinationOption(argument: "BIN_2"), .bin2)
        XCTAssertEqual(PresentationLUTOption(argument: "LIN OD"), .linOD)
        XCTAssertEqual(OrientationOption(argument: "LANDSCAPE"), .landscape)
        XCTAssertEqual(MagnificationOption(argument: "CUBIC"), .cubic)
        // The tool's tokens still work, and an unknown value is refused.
        XCTAssertEqual(FilmSizeOption(argument: "14x17"), .size14x17)
        XCTAssertNil(FilmSizeOption(argument: "15x15"))
        XCTAssertNil(PrintPriorityOption(argument: "urgent"))
    }

    // PS3.3 Table C.13-3, Image Display Format (2010,0010): STANDARD\C,R, ROW\..., COL\...,
    // SLIDE, SUPERSLIDE, CUSTOM\i — all six forms are accepted; a grid token RxC is R rows by
    // C columns, sent as STANDARD\C,R.
    func testLayoutAcceptsEveryImageDisplayFormat() {
        for value in ["STANDARD\\3,2", "ROW\\1,2", "COL\\1,4,4", "SLIDE", "SUPERSLIDE", "CUSTOM\\7"] {
            XCTAssertNotNil(LayoutOption(argument: value), value)
        }
        guard case .explicit(let grid)? = LayoutOption(argument: "2x3")?.selection else {
            return XCTFail("2x3 is a grid token")
        }
        XCTAssertEqual(grid.imageDisplayFormat, "STANDARD\\3,2")
        XCTAssertNil(LayoutOption(argument: "DIAGONAL\\2"))
    }

    // Help names each attribute and the term every token sends.
    func testSendHelpNamesTheStandardTerms() {
        let help = SendCommand.helpMessage(columns: 400)
        for text in ["Film Size ID (2010,0050)", "14x17 = 14INX17IN", "Print Priority (2000,0020)",
                     "medium = MED", "Medium Type (2000,0030)", "mammo-blue-film = MAMMO BLUE FILM",
                     "Film Destination (2000,0040)", "bin-1 = BIN_1", "Magnification Type (2010,0060)",
                     "Film Orientation (2010,0040)", "Presentation LUT Shape (2050,0020)",
                     "lin-od = LIN OD", "Image Display Format (2010,0010)", "STANDARD\\C,R",
                     "Table C.13-5 allows Bits Stored of 8 or 12",
                     "Basic Color Print Management Meta SOP Class (1.2.840.10008.5.1.1.18)"] {
            XCTAssertTrue(help.contains(text), text)
        }
        XCTAssertFalse(help.contains("Table C.13-3 allows Bits Stored"))
    }
}
