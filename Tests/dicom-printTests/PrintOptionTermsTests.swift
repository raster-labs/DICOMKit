import XCTest
import ArgumentParser
import DICOMNetwork
@testable import DICOMPrintCommandSupport

/// `dicom-print send` option vocabularies against DICOM 2026a.
///
/// The expected terms are the Defined Terms / Enumerated Values of PS3.3 2026a
/// Tables C.13-1 (Basic Film Session Presentation Module), C.13-3 (Basic Film Box
/// Presentation Module) and C.11-4 (Presentation LUT Module), dumped from the
/// DocBook by script.
final class PrintOptionTermsTests: XCTestCase {

    private func terms<T: SCUStandardTermOption>(_ type: T.Type) -> [String] {
        T.allCases.compactMap(\.standardTerm)
    }

    // PS3.3 Table C.13-3, Film Size ID (2010,0050): 12 Defined Terms.
    func testFilmSizeOffersEveryFilmSizeID() {
        XCTAssertEqual(terms(SCUFilmSizeOption.self), [
            "8INX10IN", "8_5INX11IN", "10INX12IN", "10INX14IN", "11INX14IN", "11INX17IN",
            "14INX14IN", "14INX17IN", "24CMX24CM", "24CMX30CM", "A4", "A3"])
    }

    // PS3.3 Table C.13-1, Medium Type (2000,0030): 5 Defined Terms.
    func testMediumOffersEveryMediumType() {
        XCTAssertEqual(terms(SCUMediumOption.self), [
            "PAPER", "CLEAR FILM", "BLUE FILM", "MAMMO CLEAR FILM", "MAMMO BLUE FILM"])
        XCTAssertEqual(SCUMediumOption(argument: "mammo-clear-film")?.mediumType.wireValue, "MAMMO CLEAR FILM")
        XCTAssertEqual(SCUMediumOption(argument: "mammo-blue-film")?.mediumType.wireValue, "MAMMO BLUE FILM")
    }

    // PS3.3 Table C.13-1, Print Priority (2000,0020): Enumerated Values HIGH, MED, LOW.
    func testPrintPrioritySendsEnumeratedValues() {
        XCTAssertEqual(Set(terms(SCUPrintPriorityOption.self)), ["HIGH", "MED", "LOW"])
        XCTAssertEqual(SCUPrintPriorityOption(argument: "medium")?.printPriority.rawValue, "MED")
    }

    // PS3.3 Table C.13-1, Film Destination (2000,0040): MAGAZINE, PROCESSOR, BIN_i.
    func testFilmDestinationTerms() {
        XCTAssertEqual(SCUFilmDestinationOption(argument: "magazine")?.standardTerm, "MAGAZINE")
        XCTAssertEqual(SCUFilmDestinationOption(argument: "processor")?.standardTerm, "PROCESSOR")
        // P-BIN: "Film sorter BINs shall be numbered sequentially starting from 1 and no
        // maximum is placed on the number of BINs" — any bin-N / BIN_N is sent.
        XCTAssertEqual(SCUFilmDestinationOption(argument: "bin-1")?.standardTerm, "BIN_1")
        XCTAssertEqual(SCUFilmDestinationOption(argument: "bin-3")?.standardTerm, "BIN_3")
        XCTAssertEqual(SCUFilmDestinationOption(argument: "BIN_42")?.standardTerm, "BIN_42")
        XCTAssertEqual(SCUFilmDestinationOption(argument: "bin_7")?.rawValue, "bin-7")
        // "The encoding of the BIN number shall not contain leading zeros."
        XCTAssertNil(SCUFilmDestinationOption(argument: "bin-03"))
        XCTAssertNil(SCUFilmDestinationOption(argument: "bin-0"))
        XCTAssertNil(SCUFilmDestinationOption(argument: "bin-"))
        XCTAssertNil(SCUFilmDestinationOption(argument: "tray"))
        XCTAssertNoThrow(try SCUSendCommand.parse(["pacs://h:104", "x.dcm", "--aet", "A", "--film-destination", "bin-12"]))
        XCTAssertThrowsError(try SCUSendCommand.parse(["pacs://h:104", "x.dcm", "--aet", "A", "--film-destination", "bin-012"]))
        XCTAssertEqual(try SCUSendCommand.parse(["pacs://h:104", "x.dcm", "--aet", "A", "--film-destination", "BIN_9"])
                        .filmDestination.filmDestination, .bin(9))
    }

    // PS3.3 Table C.13-3: Film Orientation PORTRAIT, LANDSCAPE; Magnification Type
    // REPLICATE, BILINEAR, CUBIC, NONE.
    func testOrientationAndMagnificationTerms() {
        XCTAssertEqual(terms(SCUOrientationOption.self), ["PORTRAIT", "LANDSCAPE"])
        XCTAssertEqual(terms(SCUMagnificationOption.self), ["REPLICATE", "BILINEAR", "CUBIC", "NONE"])
    }

    // PS3.3 Table C.11-4, Presentation LUT Shape (2050,0020): IDENTITY, LIN OD only.
    // `inverse` sends no shape.
    func testPresentationLUTShapeTerms() {
        XCTAssertEqual(terms(SCUPresentationLUTOption.self), ["IDENTITY", "LIN OD"])
        XCTAssertNil(SCUPresentationLUTOption.inverse.standardTerm)
    }

    // The standard term itself is accepted as an alias, in any case.
    func testStandardTermsAreAcceptedAsAliases() {
        XCTAssertEqual(SCUFilmSizeOption(argument: "14INX17IN"), .size14x17)
        XCTAssertEqual(SCUFilmSizeOption(argument: "8_5inx11in"), .size8_5x11)
        XCTAssertEqual(SCUFilmSizeOption(argument: "A4"), .a4)
        XCTAssertEqual(SCUPrintPriorityOption(argument: "MED"), .medium)
        XCTAssertEqual(SCUMediumOption(argument: "CLEAR FILM"), .clearFilm)
        XCTAssertEqual(SCUFilmDestinationOption(argument: "BIN_2"), .bin2)
        XCTAssertEqual(SCUPresentationLUTOption(argument: "LIN OD"), .linOD)
        XCTAssertEqual(SCUOrientationOption(argument: "LANDSCAPE"), .landscape)
        XCTAssertEqual(SCUMagnificationOption(argument: "CUBIC"), .cubic)
        // The tool's tokens still work, and an unknown value is refused.
        XCTAssertEqual(SCUFilmSizeOption(argument: "14x17"), .size14x17)
        XCTAssertNil(SCUFilmSizeOption(argument: "15x15"))
        XCTAssertNil(SCUPrintPriorityOption(argument: "urgent"))
    }

    // PS3.3 Table C.13-3, Image Display Format (2010,0010): STANDARD\C,R, ROW\..., COL\...,
    // SLIDE, SUPERSLIDE, CUSTOM\i — all six forms are accepted; a grid token RxC is R rows by
    // C columns, sent as STANDARD\C,R.
    func testLayoutAcceptsEveryImageDisplayFormat() {
        for value in ["STANDARD\\3,2", "ROW\\1,2", "COL\\1,4,4", "SLIDE", "SUPERSLIDE", "CUSTOM\\7"] {
            XCTAssertNotNil(SCULayoutOption(argument: value), value)
        }
        guard case .explicit(let grid)? = SCULayoutOption(argument: "2x3")?.selection else {
            return XCTFail("2x3 is a grid token")
        }
        XCTAssertEqual(grid.imageDisplayFormat, "STANDARD\\3,2")
        XCTAssertNil(SCULayoutOption(argument: "DIAGONAL\\2"))
    }

    // Help names each attribute and the term every token sends.
    func testSendHelpNamesTheStandardTerms() {
        let help = SCUSendCommand.helpMessage(columns: 400)
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
