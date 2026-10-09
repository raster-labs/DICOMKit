//
// PrintManagementConformanceTests.swift
// DICOMPrintKit
//
// The print-side findings of the DICOM 2026a pass, each held against the
// clause it follows: --raw frames against the image box pixel enumerations
// (PS3.3 Table C.13-5), the annotation Text String against LO (PS3.5 Table
// 6.2-1), the emulator's default Printer Status Info against the C.13.9.1
// Defined Terms, and the simulator's film box against its job's Image Display
// Format (C.13.3, C.13.5.1).
//

import XCTest
import DICOMCore
import DICOMKit
import DICOMNetwork
@testable import DICOMPrintKit

final class PrintManagementConformanceTests: XCTestCase {

    // MARK: - --raw and Table C.13-5

    private func source(
        samples: Int = 1, photometric: PhotometricInterpretation = .monochrome2,
        allocated: Int = 16, stored: Int = 12, high: Int = 11, signed: Bool = false
    ) -> PixelDataDescriptor {
        PixelDataDescriptor(
            rows: 4, columns: 4, numberOfFrames: 1,
            bitsAllocated: allocated, bitsStored: stored, highBit: high, isSigned: signed,
            samplesPerPixel: samples, photometricInterpretation: photometric)
    }

    func test_rawConformantSources_areAccepted() {
        XCTAssertNil(PrintImagePreparer.rawConformanceProblem(source()))
        XCTAssertNil(PrintImagePreparer.rawConformanceProblem(
            source(allocated: 8, stored: 8, high: 7)))
        XCTAssertNil(PrintImagePreparer.rawConformanceProblem(
            source(photometric: .monochrome1)))
        XCTAssertNil(PrintImagePreparer.rawConformanceProblem(
            source(samples: 3, photometric: .rgb, allocated: 8, stored: 8, high: 7)))
    }

    func test_rawSignedSource_isRefused() {
        let problem = PrintImagePreparer.rawConformanceProblem(source(signed: true))
        XCTAssertEqual(problem?.contains("Pixel Representation"), true)
    }

    func test_rawSixteenBitsStored_isRefused() {
        let problem = PrintImagePreparer.rawConformanceProblem(source(stored: 16, high: 15))
        XCTAssertEqual(problem?.contains("Bits Stored"), true)
    }

    func test_rawYBRSource_isRefused() {
        let problem = PrintImagePreparer.rawConformanceProblem(
            source(samples: 3, photometric: .ybrFull422, allocated: 8, stored: 8, high: 7))
        XCTAssertEqual(problem?.contains("Photometric Interpretation"), true)
    }

    func test_rawPaletteColorSource_isRefused() {
        let problem = PrintImagePreparer.rawConformanceProblem(
            source(photometric: .paletteColor, allocated: 8, stored: 8, high: 7))
        XCTAssertEqual(problem?.contains("Photometric Interpretation"), true)
    }

    func test_rawHighBitNotBelowBitsStored_isRefused() {
        let problem = PrintImagePreparer.rawConformanceProblem(source(stored: 12, high: 15))
        XCTAssertEqual(problem?.contains("High Bit"), true)
    }

    /// The whole path: a raw job of a signed CT throws with the rule, instead
    /// of sending Pixel Representation 1 in a Basic Grayscale Image Box.
    func test_rawJobOfASignedImage_throwsWithTheRule() async throws {
        let descriptor = source(signed: true)
        let pixels = PixelData(data: Data(count: 4 * 4 * 2), descriptor: descriptor)
        var request = PrintJobRequest()
        request.raw = true
        do {
            _ = try await PrintImagePreparer().prepare(
                pixelData: pixels, dataSet: DataSet(), request: request)
            XCTFail("a signed source cannot be sent raw")
        } catch let error as PrintRequestError {
            XCTAssertTrue(error.message.contains("PS3.3 Table C.13-5"), error.message)
        }
    }

    // MARK: - Text String is LO (PS3.5 Table 6.2-1)

    func test_footerLines_areLegalLOValues() {
        let long = String(repeating: "A", count: 80) + "\\B"
        let annotations = FilmIdentificationFooter.annotations(for: [long, "DOE^JANE\\1234"])
        XCTAssertEqual(annotations[0].text.count, 64)
        XCTAssertFalse(annotations[1].text.contains("\\"))
        XCTAssertEqual(annotations[1].text, "DOE^JANE/1234")
        XCTAssertEqual(FilmIdentificationFooter.textStringMaximumLength, 64)
    }

    func test_footerLines_dropControlCharacters() {
        XCTAssertEqual(FilmIdentificationFooter.textString("A\tB\nC"), "ABC")
    }

    // MARK: - Medium Type (PS3.3 Table C.13-1, P-MAMMO)

    func test_catalogOffersEveryMediumTypeTerm() {
        let sent = PrintOptionCatalog.mediumTypes.map(\.value.wireValue)
        XCTAssertEqual(sent, ["PAPER", "CLEAR FILM", "BLUE FILM", "MAMMO CLEAR FILM", "MAMMO BLUE FILM"])
        XCTAssertEqual(PrintOptionCatalog.mediumType(forToken: "mammo-blue-film"), .mammoBlueFilm)
    }

    func test_mammographyPresetSendsTheTerm() {
        XCTAssertEqual(PrintOptions.mammography.mediumType.wireValue, "MAMMO BLUE FILM")
    }

    // MARK: - Printer Status Info (PS3.3 C.13.9.1)

    func test_defaultStatusInfo_isADefinedTerm() {
        XCTAssertEqual(EmulatedPrinterStatus.normal.defaultStatusInfo, "NORMAL")
        XCTAssertEqual(EmulatedPrinterStatus.warning.defaultStatusInfo, "SUPPLY LOW")
        XCTAssertEqual(EmulatedPrinterStatus.failure.defaultStatusInfo, "SUPPLY EMPTY")
    }

    // MARK: - The simulator's film box (C.13.3, C.13.5.1)

    #if canImport(CoreGraphics)
    /// A `ROW\1,2` job is three boxes — one over two — and its film box says
    /// so; composed from the bounding grid it was `STANDARD\2,2`, four boxes.
    func test_simulatedBandFilm_carriesItsOwnImageDisplayFormat() throws {
        let frame = PreparedPrintImage(
            descriptor: PrintImageData(
                pixelData: Data(repeating: 100, count: 16),
                rows: 4, columns: 4, bitsAllocated: 8, bitsStored: 8, highBit: 7,
                samplesPerPixel: 1, pixelRepresentation: 0,
                photometricInterpretation: "MONOCHROME2"),
            sourcePath: nil, frameIndex: 0)
        var request = PrintJobRequest()
        request.layoutSelection = .displayFormat(PrintImageDisplayFormat.parse("ROW\\1,2"))
        let films = try PrintSCPSimulator().composeFilms(
            images: [frame, frame, frame],
            request: request,
            settings: PrintSCPSettings(dpi: 36))
        let film = try XCTUnwrap(films.first)
        XCTAssertEqual(films.count, 1)
        XCTAssertEqual(film.info.imageDisplayFormat, "ROW\\1,2")
        XCTAssertEqual(film.info.imageBoxCount, 3)
        XCTAssertEqual(film.info.filledImageBoxCount, 3)
    }
    #endif
}
