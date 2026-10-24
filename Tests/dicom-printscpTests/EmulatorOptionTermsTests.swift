import XCTest
import ArgumentParser
import DICOMNetwork
import DICOMPrintKit
@testable import DICOMPrintCommandSupport

/// `dicom-printscp` option vocabularies and help against DICOM 2026a: PS3.3 Tables
/// C.13-1, C.13-3, C.13-5, C.13-9 and C.11-4, PS3.4 Annex H, PS3.6 Tables 6-1 / A-1
/// (values dumped from the DocBook by script).
final class EmulatorOptionTermsTests: XCTestCase {

    // The standard term is accepted for its token, in any case.
    func testStandardTermsAreAcceptedAsAliases() throws {
        XCTAssertEqual(try SCPOptionTokens.validate("14INX17IN", in: PrintOptionCatalog.filmSizes.map(\.cliToken),
                                                 terms: SCPOptionTokens.filmSizeTerms, flag: "--film-size"), "14x17")
        XCTAssertEqual(try SCPOptionTokens.validate("24cmx30cm", in: PrintOptionCatalog.filmSizes.map(\.cliToken),
                                                 terms: SCPOptionTokens.filmSizeTerms, flag: "--film-size"), "24x30cm")
        XCTAssertEqual(try SCPOptionTokens.validate("MAMMO BLUE FILM", in: PrintOptionCatalog.mediumTypes.map(\.cliToken),
                                                 terms: SCPOptionTokens.mediumTerms, flag: "--medium"), "mammo-blue-film")
        XCTAssertEqual(try SCPOptionTokens.validate("LIN OD", in: PrintOptionCatalog.presentationLUTShapes.map(\.cliToken),
                                                 terms: SCPOptionTokens.presentationLUTShapeTerms,
                                                 flag: "--presentation-lut"), "lin-od")
        XCTAssertThrowsError(try SCPOptionTokens.validate("15INX15IN", in: PrintOptionCatalog.filmSizes.map(\.cliToken),
                                                       terms: SCPOptionTokens.filmSizeTerms, flag: "--film-size"))
    }

    // PS3.3 Table C.13-3 Film Size ID: 12 Defined Terms; Table C.13-1 Medium Type: 5.
    func testTermListsCoverTheDefinedTerms() {
        XCTAssertEqual(SCPOptionTokens.filmSizeTerms.compactMap(\.term), [
            "8INX10IN", "8_5INX11IN", "10INX12IN", "10INX14IN", "11INX14IN", "11INX17IN",
            "14INX14IN", "14INX17IN", "24CMX24CM", "24CMX30CM", "A4", "A3"])
        XCTAssertEqual(SCPOptionTokens.mediumTerms.compactMap(\.term), [
            "PAPER", "CLEAR FILM", "BLUE FILM", "MAMMO CLEAR FILM", "MAMMO BLUE FILM"])
        XCTAssertEqual(SCPOptionTokens.polarityTerms.compactMap(\.term), ["NORMAL", "REVERSE"])
        XCTAssertEqual(SCPOptionTokens.presentationLUTShapeTerms.compactMap(\.term), ["IDENTITY", "LIN OD"])
        XCTAssertEqual(SCPOptionTokens.printerStatusTerms.compactMap(\.term), ["NORMAL", "WARNING", "FAILURE"])
    }

    // PS3.3 Table C.13-3 Border Density / Empty Image Density: BLACK, WHITE, or i in
    // hundredths of OD.
    func testSimulateDensityTakesHundredthsOfOD() throws {
        let command = try SCPSimulateCommand.parse(["a.dcm"])
        XCTAssertEqual(try command.density("150", flag: "--border-density"), "150")
        XCTAssertEqual(try command.density("0150", flag: "--border-density"), "150")
        XCTAssertEqual(try command.density("white", flag: "--border-density"), "WHITE")
        XCTAssertThrowsError(try command.density("1.5", flag: "--border-density"))
        XCTAssertThrowsError(try command.density("-20", flag: "--border-density"))
        XCTAssertThrowsError(try command.density("GREY", flag: "--border-density"))

        let request = try SCPSimulateCommand.parse(
            ["a.dcm", "--border-density", "150", "--empty-density", "WHITE"]).makeRequest()
        XCTAssertEqual(request.borderDensity, "150")
        XCTAssertEqual(request.emptyImageDensity, "WHITE")
    }

    // PS3.3 Table C.13-3 Image Display Format: every form, as dicom-print takes them.
    func testSimulateLayoutTakesImageDisplayFormats() throws {
        for value in ["ROW\\1,2", "COL\\1,4,4", "STANDARD\\3,2", "SLIDE", "SUPERSLIDE", "CUSTOM\\4"] {
            let request = try SCPSimulateCommand.parse(["a.dcm", "--layout", value]).makeRequest()
            guard case .displayFormat(let format) = request.layoutSelection else {
                return XCTFail("\(value) not taken as an Image Display Format")
            }
            XCTAssertEqual(format.raw, value)
        }
        let grid = try SCPSimulateCommand.parse(["a.dcm", "--layout", "2x3"]).makeRequest()
        XCTAssertEqual(grid.layoutSelection, .explicit(.layout2x3))
        XCTAssertThrowsError(try SCPSimulateCommand.parse(["a.dcm", "--layout", "DIAGONAL\\2"]).makeRequest())
    }

    func testSimulateTakesStandardTermsAndRejectsSixteenBitsStored() throws {
        let request = try SCPSimulateCommand.parse(
            ["a.dcm", "--film-size", "A4", "--medium", "MAMMO CLEAR FILM", "--polarity", "REVERSE",
             "--orientation", "LANDSCAPE", "--magnification", "CUBIC"]).makeRequest()
        XCTAssertEqual(request.filmSize, .a4)
        XCTAssertEqual(request.mediumType, .mammoClearFilm)
        XCTAssertEqual(request.polarity, .reverse)
        XCTAssertEqual(request.filmOrientation, .landscape)
        XCTAssertEqual(request.magnificationType, .cubic)
        // Bits Stored is 8 or 12 (Table C.13-5); the help said 16 too.
        XCTAssertThrowsError(try SCPSimulateCommand.parse(["a.dcm", "--bit-depth", "16"]).makeRequest())
        let help = SCPSimulateCommand.helpMessage(columns: 400)
        XCTAssertTrue(help.contains("Grayscale Bits Stored: 8 or 12, PS3.3 Table C.13-5"))
        XCTAssertFalse(help.contains("8, 12, or 16"))
    }

    // Names per PS3.6 Table 6-1 / A-1 and services per PS3.4 Annex H.
    func testServeHelpNamesAttributesAndSOPClasses() {
        let help = SCPServeCommand.helpMessage(columns: 400)
        for text in ["Software Versions (0018,1020)", "Manufacturer's Model Name (0008,1090)",
                     "Printer Name (2110,0030)", "Device Serial Number (0018,1000)",
                     "Printer Status (2110,0010)", "Printer Status Info (2110,0020)",
                     "Basic Color Print Management Meta SOP Class (1.2.840.10008.5.1.1.18)",
                     "Presentation LUT SOP Class (1.2.840.10008.5.1.1.23)",
                     "Basic Annotation Box SOP Class (1.2.840.10008.5.1.1.15): N-SET",
                     "Print Job SOP Class (1.2.840.10008.5.1.1.14)", "Event Type Done (3",
                     "Film Size ID (2010,0050)", "14x17 = 14INX17IN", "Medium Type (2000,0030)"] {
            XCTAssertTrue(help.contains(text), text)
        }
        XCTAssertFalse(help.contains("Software Version (0018,1020)"))
        XCTAssertFalse(help.contains("N-CREATE / N-SET"))
    }
}
