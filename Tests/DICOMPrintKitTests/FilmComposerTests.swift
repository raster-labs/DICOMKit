//
// FilmComposerTests.swift
// DICOMPrintKitTests
//
// Composition tests. Rather than committing opaque bitmap hashes (which would
// churn with every CoreGraphics release), these assert the two things a golden
// hash is actually a proxy for — the output is *deterministic*, and it *differs*
// when the film attributes differ — plus direct pixel probes for the rules that
// matter clinically: polarity, LUT shape, density, and layout placement.
//

import XCTest
import DICOMCore
import DICOMNetwork
@testable import DICOMPrintKit

final class FilmComposerTests: XCTestCase {

    // MARK: Fixtures

    /// A uniform grayscale image of the given 8-bit value.
    private func image(value: UInt8, size: UInt16 = 32, photometric: String = "MONOCHROME2") -> PrintImageData {
        PrintImageData(
            pixelData: Data(repeating: value, count: Int(size) * Int(size)),
            rows: size, columns: size,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            samplesPerPixel: 1, pixelRepresentation: 0,
            photometricInterpretation: photometric)
    }

    /// A film with one image box per layout cell, all carrying `image`.
    private func film(
        format: String = "STANDARD\\1,1",
        image source: PrintImageData? = nil,
        boxCount: Int? = nil,
        orientation: FilmOrientation = .portrait,
        filmSize: FilmSize = .size8InX10In,
        polarity: ImagePolarity = .normal,
        decimateCrop: DecimateCropBehavior = .decimate,
        borderDensity: String = "BLACK",
        emptyImageDensity: String = "BLACK",
        trim: TrimOption = .no,
        presentationLUTShape: PresentationLUTShape? = nil,
        annotations: [PrintAnnotation] = [],
        requestedImageSize: String? = nil
    ) -> ReceivedFilm {
        let parsed = PrintImageDisplayFormat.parse(format)
        let count = boxCount ?? parsed.imageBoxCount
        let payload = source ?? image(value: 255)
        let boxes = (1...max(1, parsed.imageBoxCount)).map { position in
            ReceivedImageBox(
                sopInstanceUID: "1.2.3.\(position)",
                sopClassUID: payload.samplesPerPixel == 3
                    ? basicColorImageBoxSOPClassUID : basicGrayscaleImageBoxSOPClassUID,
                content: ImageBoxContent(
                    sopInstanceUID: "1.2.3.\(position)",
                    imagePosition: UInt16(position),
                    polarity: polarity,
                    requestedImageSize: requestedImageSize,
                    requestedDecimateCropBehavior: decimateCrop),
                image: position <= count ? payload : nil)
        }
        return ReceivedFilm(
            printJobUID: "1.2.9.1",
            filmSession: FilmSession(sopInstanceUID: "1.2.9.2", numberOfCopies: 1),
            filmBox: FilmBox(
                sopInstanceUID: "1.2.9.3",
                imageDisplayFormat: format,
                filmOrientation: orientation,
                filmSizeID: filmSize,
                borderDensity: borderDensity,
                emptyImageDensity: emptyImageDensity,
                trimOption: trim),
            layout: parsed.layout,
            imageBoxes: boxes,
            presentationLUTShape: presentationLUTShape,
            annotations: annotations,
            callingAETitle: "TEST_SCU",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000))
    }

    /// A low-DPI composer: the layout rules are resolution-independent and a
    /// 300 DPI 8×10 sheet is 6 MB per test.
    private let composer = FilmComposer(configuration: FilmComposerConfiguration(dpi: 50))

    /// The 8-bit sample at a normalized position on the sheet.
    private func sample(_ film: ComposedFilm, atFractionX fx: Double, y fy: Double) -> UInt8 {
        let x = min(film.width - 1, max(0, Int(Double(film.width) * fx)))
        let y = min(film.height - 1, max(0, Int(Double(film.height) * fy)))
        return film.pixels[film.pixels.startIndex + y * film.bytesPerRow + x * film.samplesPerPixel]
    }

    // MARK: Sheet

    func testComposesASheetSizedFromTheFilmBox() throws {
        let composed = try composer.compose(film(filmSize: .size14InX17In))
        // 14 × 17 in at 50 DPI.
        XCTAssertEqual(composed.width, 700)
        XCTAssertEqual(composed.height, 850)
        XCTAssertEqual(composed.samplesPerPixel, 1)
        XCTAssertEqual(composed.pixels.count, 700 * 850)
    }

    func testLandscapeOrientationSwapsTheSheet() throws {
        let portrait = try composer.compose(film(orientation: .portrait))
        let landscape = try composer.compose(film(orientation: .landscape))
        XCTAssertEqual(portrait.width, landscape.height)
        XCTAssertEqual(portrait.height, landscape.width)
    }

    func testOversizedSheetIsRejectedRatherThanAllocated() {
        // 14 in at the maximum DPI is ~9100 px, well past the cap.
        let huge = FilmComposer(configuration: FilmComposerConfiguration(
            dpi: PrintSCPSettings.dpiRange.upperBound, maximumPixelDimension: 1000))
        XCTAssertThrowsError(try huge.compose(film(filmSize: .size14InX17In))) { error in
            guard case FilmCompositionError.sheetTooLarge = error else {
                return XCTFail("Expected sheetTooLarge, got \(error)")
            }
        }
    }

    func testResolutionIsClampedToWhatFilmImagersAddress() {
        // Film imagers top out around 650 DPI, so a higher request is composed
        // at the ceiling rather than spending memory on detail film cannot hold.
        XCTAssertEqual(FilmComposerConfiguration(dpi: 4800).dpi,
                       PrintSCPSettings.dpiRange.upperBound)
        XCTAssertEqual(FilmComposerConfiguration(dpi: 1).dpi,
                       PrintSCPSettings.dpiRange.lowerBound)
        // The default sits inside the range, so it survives the clamp intact.
        XCTAssertEqual(FilmComposerConfiguration().dpi, PrintSCPSettings.defaultDPI)
    }

    // MARK: Determinism and sensitivity — what a golden hash is a proxy for

    func testCompositionIsDeterministic() throws {
        let source = film(format: "STANDARD\\2,2")
        let first = try composer.compose(source)
        let second = try composer.compose(source)
        XCTAssertEqual(first.pixelFingerprint, second.pixelFingerprint)
    }

    func testDifferentLayoutsProduceDifferentFilms() throws {
        let single = try composer.compose(film(format: "STANDARD\\1,1"))
        let quad = try composer.compose(film(format: "STANDARD\\2,2"))
        let wide = try composer.compose(film(format: "STANDARD\\2,1", orientation: .landscape))
        XCTAssertNotEqual(single.pixelFingerprint, quad.pixelFingerprint)
        XCTAssertNotEqual(single.pixelFingerprint, wide.pixelFingerprint)
        XCTAssertEqual(single.info.rows, 1)
        XCTAssertEqual(quad.info.rows, 2)
        XCTAssertEqual(quad.info.columns, 2)
    }

    func testMagnificationTypeChangesTheRendering() throws {
        // Same film, different interpolation: a scaled-up 2×2 checkerboard is
        // blocky under REPLICATE and smooth under CUBIC.
        let checker = PrintImageData(
            pixelData: Data([0, 255, 255, 0]),
            rows: 2, columns: 2, bitsAllocated: 8, bitsStored: 8, highBit: 7,
            samplesPerPixel: 1, pixelRepresentation: 0,
            photometricInterpretation: "MONOCHROME2")

        func compose(_ magnification: MagnificationType) throws -> ComposedFilm {
            var source = film(image: checker)
            var box = source.filmBox
            box.magnificationType = magnification
            source = ReceivedFilm(
                printJobUID: source.printJobUID, filmSession: source.filmSession,
                filmBox: box, layout: source.layout, imageBoxes: source.imageBoxes,
                callingAETitle: source.callingAETitle, timestamp: source.timestamp)
            return try composer.compose(source)
        }

        let replicate = try compose(.replicate)
        let cubic = try compose(.cubic)
        XCTAssertNotEqual(replicate.pixelFingerprint, cubic.pixelFingerprint)
    }

    // MARK: Pixel rules

    func testWhiteImageRendersLightAndBlackImageRendersDark() throws {
        let white = try composer.compose(film(image: image(value: 255)))
        let black = try composer.compose(film(image: image(value: 0)))
        XCTAssertGreaterThan(sample(white, atFractionX: 0.5, y: 0.5), 200)
        XCTAssertLessThan(sample(black, atFractionX: 0.5, y: 0.5), 55)
    }

    func testPolarityReverseInvertsTheImage() throws {
        let normal = try composer.compose(film(image: image(value: 255), polarity: .normal))
        let reverse = try composer.compose(film(image: image(value: 255), polarity: .reverse))
        XCTAssertGreaterThan(sample(normal, atFractionX: 0.5, y: 0.5), 200)
        XCTAssertLessThan(sample(reverse, atFractionX: 0.5, y: 0.5), 55)
    }

    func testMonochrome1SourceIsInverted() throws {
        let mono1 = try composer.compose(
            film(image: image(value: 255, photometric: "MONOCHROME1")))
        XCTAssertLessThan(sample(mono1, atFractionX: 0.5, y: 0.5), 55,
                          "MONOCHROME1 maximum value is white-on-film, i.e. dark on paper")
    }

    func testInversePresentationLUTInvertsTheImage() throws {
        let identity = try composer.compose(
            film(image: image(value: 255), presentationLUTShape: .identity))
        let inverse = try composer.compose(
            film(image: image(value: 255), presentationLUTShape: .inverseRendered))
        XCTAssertGreaterThan(sample(identity, atFractionX: 0.5, y: 0.5), 200)
        XCTAssertLessThan(sample(inverse, atFractionX: 0.5, y: 0.5), 55)
    }

    func testLinODKeepsItsOrientation() throws {
        // Low P prints light (Min Density), high P dark — the direction the
        // old invert-toggle already had, so films do not flip under the fix.
        let low = try composer.compose(
            film(image: image(value: 0), presentationLUTShape: .linearOpticalDensity))
        let high = try composer.compose(
            film(image: image(value: 255), presentationLUTShape: .linearOpticalDensity))
        XCTAssertGreaterThan(sample(low, atFractionX: 0.5, y: 0.5), 200)
        XCTAssertLessThan(sample(high, atFractionX: 0.5, y: 0.5), 10)
    }

    func testLinODIsADensityCurveNotANegation() throws {
        // Mid-gray under LIN OD: OD = 0.2 + 0.5·(3.0 − 0.2) = 1.6, whose
        // transmitted luminance is ~4% of full — nowhere near the 50% a plain
        // inversion (the old behavior) put there. The curve *is* the fix.
        let mid = try composer.compose(
            film(image: image(value: 128), presentationLUTShape: .linearOpticalDensity))
        let value = sample(mid, atFractionX: 0.5, y: 0.5)
        XCTAssertLessThan(value, 40, "mid P-value must fall on the exponential density curve")
        XCTAssertGreaterThan(value, 0, "…but not clip to black")
    }

    // MARK: Annotation bands (FR-006)

    /// Ink from the annotation text: any bright pixel inside the given
    /// fractional region of the sheet (rows are top-down, like the bitmap).
    private func regionHasInk(
        _ film: ComposedFilm,
        x: ClosedRange<Double> = 0...1,
        y: ClosedRange<Double> = 0...1
    ) -> Bool {
        let x0 = max(0, Int(Double(film.width) * x.lowerBound))
        let x1 = min(film.width - 1, Int(Double(film.width) * x.upperBound))
        let y0 = max(0, Int(Double(film.height) * y.lowerBound))
        let y1 = min(film.height - 1, Int(Double(film.height) * y.upperBound))
        for row in y0...y1 {
            let base = film.pixels.startIndex + row * film.bytesPerRow
            for column in x0...x1 where film.pixels[base + column * film.samplesPerPixel] > 128 {
                return true
            }
        }
        return false
    }

    private func composer(edge: FilmAnnotationEdge) -> FilmComposer {
        FilmComposer(configuration: FilmComposerConfiguration(dpi: 50, annotationEdge: edge))
    }

    private func annotatedFilm() -> ReceivedFilm {
        // A black image so the only bright pixels on the sheet are the text.
        film(image: image(value: 0),
             annotations: [PrintAnnotation(position: 1, text: "DOE^JANE 123456")])
    }

    func testHeaderBandPutsTheTextAtTheTop() throws {
        let composed = try composer(edge: .top).compose(annotatedFilm())
        XCTAssertTrue(regionHasInk(composed, y: 0...0.1),
                      "header text must be at the top of the sheet")
        XCTAssertFalse(regionHasInk(composed, y: 0.9...1),
                       "…and nowhere near the foot")
    }

    func testFooterBandPutsTheTextAtTheBottom() throws {
        let composed = try composer(edge: .bottom).compose(annotatedFilm())
        XCTAssertTrue(regionHasInk(composed, y: 0.9...1))
        XCTAssertFalse(regionHasInk(composed, y: 0...0.1))
    }

    func testSideBandsPutTheTextOnTheirEdge() throws {
        let left = try composer(edge: .left).compose(annotatedFilm())
        XCTAssertTrue(regionHasInk(left, x: 0...0.1),
                      "left-band text must run along the left edge")
        XCTAssertFalse(regionHasInk(left, x: 0.9...1))

        let right = try composer(edge: .right).compose(annotatedFilm())
        XCTAssertTrue(regionHasInk(right, x: 0.9...1),
                      "right-band text must run along the right edge")
        XCTAssertFalse(regionHasInk(right, x: 0...0.1))
    }

    func testBandsMoveTheCellsOffTheirEdge() {
        let format = PrintImageDisplayFormat.parse("STANDARD\\1,1")
        let sheet = FilmSheet(filmSize: .size8InX10In, orientation: .portrait, dpi: 50)

        let plain = FilmCellLayout.cells(for: format, on: sheet)[0]
        let top = FilmCellLayout.cells(
            for: format, on: sheet, footerMillimeters: 12, annotationEdge: .top)[0]
        let bottom = FilmCellLayout.cells(
            for: format, on: sheet, footerMillimeters: 12, annotationEdge: .bottom)[0]
        let leftBand = FilmCellLayout.cells(
            for: format, on: sheet, footerMillimeters: 12, annotationEdge: .left)[0]
        let overlay = FilmCellLayout.cells(
            for: format, on: sheet, footerMillimeters: 12, annotationEdge: .overlay)[0]

        XCTAssertGreaterThan(top.y, plain.y, "a header pushes the cells down")
        XCTAssertLessThan(top.height, plain.height)
        XCTAssertEqual(bottom.y, plain.y, "a footer leaves the top edge alone")
        XCTAssertLessThan(bottom.height, plain.height)
        XCTAssertGreaterThan(leftBand.x, plain.x, "a left band pushes the cells right")
        XCTAssertLessThan(leftBand.width, plain.width)
        XCTAssertEqual(leftBand.height, plain.height, "a side band never costs height")
        XCTAssertEqual(overlay.width, plain.width, "overlay reserves nothing")
        XCTAssertEqual(overlay.height, plain.height)
    }

    func testTwoInversionsCancel() throws {
        // MONOCHROME1 + REVERSE polarity is back to normal.
        let composed = try composer.compose(
            film(image: image(value: 255, photometric: "MONOCHROME1"), polarity: .reverse))
        XCTAssertGreaterThan(sample(composed, atFractionX: 0.5, y: 0.5), 200)
    }

    func testFilmEmulationInvertsRelativeToPaperDirect() throws {
        let paper = FilmComposer(configuration: FilmComposerConfiguration(
            dpi: 50, densityMapping: .paperDirect))
        let emulation = FilmComposer(configuration: FilmComposerConfiguration(
            dpi: 50, densityMapping: .filmEmulation))
        let source = film(image: image(value: 255))

        XCTAssertGreaterThan(sample(try paper.compose(source), atFractionX: 0.5, y: 0.5), 200)
        XCTAssertLessThan(sample(try emulation.compose(source), atFractionX: 0.5, y: 0.5), 55)
    }

    func testBorderDensityPaintsTheSheetBackground() throws {
        let whiteBorder = try composer.compose(
            film(borderDensity: "WHITE", emptyImageDensity: "WHITE"))
        let blackBorder = try composer.compose(
            film(borderDensity: "BLACK", emptyImageDensity: "BLACK"))
        // Sample inside the sheet margin, outside any image cell.
        XCTAssertGreaterThan(sample(whiteBorder, atFractionX: 0.005, y: 0.005), 200)
        XCTAssertLessThan(sample(blackBorder, atFractionX: 0.005, y: 0.005), 55)
    }

    func testEmptyImageBoxesShowEmptyImageDensityNotTheImage() throws {
        // A 2×2 layout with only the first box filled.
        let composed = try composer.compose(
            film(format: "STANDARD\\2,2", image: image(value: 255), boxCount: 1,
                 borderDensity: "BLACK", emptyImageDensity: "BLACK"))
        XCTAssertGreaterThan(sample(composed, atFractionX: 0.25, y: 0.25), 200, "filled cell")
        XCTAssertLessThan(sample(composed, atFractionX: 0.75, y: 0.75), 55, "empty cell")
        XCTAssertEqual(composed.info.filledImageBoxCount, 1)
        XCTAssertEqual(composed.info.imageBoxCount, 4)
    }

    func testImagesLandInTheirImageBoxPositions() throws {
        // Distinct values per position prove the row-major ordering end to end.
        let parsed = PrintImageDisplayFormat.parse("STANDARD\\2,2")
        let values: [UInt8] = [255, 0, 0, 255]
        let boxes = (1...4).map { position in
            ReceivedImageBox(
                sopInstanceUID: "1.2.3.\(position)",
                sopClassUID: basicGrayscaleImageBoxSOPClassUID,
                content: ImageBoxContent(
                    sopInstanceUID: "1.2.3.\(position)", imagePosition: UInt16(position)),
                image: image(value: values[position - 1]))
        }
        let source = ReceivedFilm(
            printJobUID: "1.2.9.1",
            filmSession: FilmSession(sopInstanceUID: "1.2.9.2"),
            filmBox: FilmBox(sopInstanceUID: "1.2.9.3", imageDisplayFormat: "STANDARD\\2,2"),
            layout: parsed.layout, imageBoxes: boxes,
            callingAETitle: "TEST_SCU")

        let composed = try composer.compose(source)
        XCTAssertGreaterThan(sample(composed, atFractionX: 0.25, y: 0.25), 200, "position 1: top-left")
        XCTAssertLessThan(sample(composed, atFractionX: 0.75, y: 0.25), 55, "position 2: top-right")
        XCTAssertLessThan(sample(composed, atFractionX: 0.25, y: 0.75), 55, "position 3: bottom-left")
        XCTAssertGreaterThan(sample(composed, atFractionX: 0.75, y: 0.75), 200, "position 4: bottom-right")
    }

    func testImagesAreDrawnUprightNotFlipped() throws {
        // A top-half-white / bottom-half-black image must stay that way: the
        // rasterizer works in CoreGraphics' bottom-left origin while the layout
        // is top-left, and getting that flip wrong is invisible on symmetric
        // fixtures.
        var pixels = Data(repeating: 255, count: 32 * 16)
        pixels.append(Data(repeating: 0, count: 32 * 16))
        let split = PrintImageData(
            pixelData: pixels, rows: 32, columns: 32,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            samplesPerPixel: 1, pixelRepresentation: 0,
            photometricInterpretation: "MONOCHROME2")

        let composed = try composer.compose(film(image: split, decimateCrop: .crop))
        XCTAssertGreaterThan(sample(composed, atFractionX: 0.5, y: 0.3), 200, "top stays white")
        XCTAssertLessThan(sample(composed, atFractionX: 0.5, y: 0.7), 55, "bottom stays black")
    }

    // MARK: Bit depth and colour

    func testSixteenBitImagesAreScaledFromBitsStored() throws {
        // 12-bit stored: 4095 is full scale and must render white, not mid-gray.
        var pixels = Data()
        for _ in 0..<(16 * 16) {
            pixels.append(contentsOf: [0xFF, 0x0F]) // 4095, little-endian
        }
        let deep = PrintImageData(
            pixelData: pixels, rows: 16, columns: 16,
            bitsAllocated: 16, bitsStored: 12, highBit: 11,
            samplesPerPixel: 1, pixelRepresentation: 0,
            photometricInterpretation: "MONOCHROME2")

        let composed = try composer.compose(film(image: deep))
        XCTAssertGreaterThan(sample(composed, atFractionX: 0.5, y: 0.5), 250)
    }

    func testColorImageBoxProducesAnRGBFilm() throws {
        var pixels = Data()
        for _ in 0..<(16 * 16) { pixels.append(contentsOf: [200, 40, 40]) }
        let rgb = PrintImageData(
            pixelData: pixels, rows: 16, columns: 16,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            samplesPerPixel: 3, pixelRepresentation: 0,
            photometricInterpretation: "RGB")

        let composed = try composer.compose(film(image: rgb))
        XCTAssertTrue(composed.isColor)
        XCTAssertEqual(composed.samplesPerPixel, 3)

        let x = composed.width / 2, y = composed.height / 2
        let offset = composed.pixels.startIndex + y * composed.bytesPerRow + x * 3
        XCTAssertGreaterThan(composed.pixels[offset], 150, "red channel dominates")
        XCTAssertLessThan(composed.pixels[offset + 1], 90)
    }

    func testYBRFull422IsUnpackedAndConverted() throws {
        // Packed 4:2:2: Y1 Y2 Cb Cr per pixel pair (PS3.5 8.7.4). Neutral chroma
        // with maximum luma must come out white.
        var pixels = Data()
        for _ in 0..<(16 * 16 / 2) { pixels.append(contentsOf: [255, 255, 128, 128]) }
        let ybr = PrintImageData(
            pixelData: pixels, rows: 16, columns: 16,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            samplesPerPixel: 3, pixelRepresentation: 0,
            photometricInterpretation: "YBR_FULL_422")

        let composed = try composer.compose(film(image: ybr))
        let x = composed.width / 2, y = composed.height / 2
        let offset = composed.pixels.startIndex + y * composed.bytesPerRow + x * 3
        XCTAssertGreaterThan(composed.pixels[offset], 240)
        XCTAssertGreaterThan(composed.pixels[offset + 1], 240)
        XCTAssertGreaterThan(composed.pixels[offset + 2], 240)
    }

    // MARK: Failures and metadata

    func testFailBehaviorSkipsTheBoxAndReportsIt() throws {
        // A 4000 px image cannot fit a 50 DPI 8×10 cell at 1:1 with FAIL.
        let big = image(value: 255, size: 4000)
        let composed = try composer.compose(film(image: big, decimateCrop: .failOver))
        XCTAssertEqual(composed.info.skippedImageBoxes.count, 1)
        XCTAssertLessThan(sample(composed, atFractionX: 0.5, y: 0.5), 55,
                          "the unplaceable box falls back to empty density")
    }

    func testComposedInfoCarriesTheFilmAttributes() throws {
        let composed = try composer.compose(film(
            format: "STANDARD\\2,2", filmSize: .a4, trim: .yes,
            presentationLUTShape: .inverseRendered,
            annotations: [PrintAnnotation(position: 1, text: "DOE^JANE")]))

        XCTAssertEqual(composed.info.filmSize, "A4")
        XCTAssertEqual(composed.info.imageDisplayFormat, "STANDARD\\2,2")
        XCTAssertEqual(composed.info.trim, "YES")
        XCTAssertEqual(composed.info.presentationLUTShape, "INVERSE_RENDERED")
        XCTAssertEqual(composed.info.annotations, ["1: DOE^JANE"])
        XCTAssertEqual(composed.info.callingAETitle, "TEST_SCU")
        XCTAssertEqual(composed.info.densityMapping, .paperDirect)

        // The attributes inspector payload must round-trip as JSON.
        let json = try composed.info.jsonRepresentation()
        XCTAssertTrue(json.contains("\"filmSize\" : \"A4\""), json)
    }

    func testDownsamplingShrinksTheBitmapAndKeepsTheMetadata() throws {
        let composed = try FilmComposer(configuration: FilmComposerConfiguration(dpi: 150))
            .compose(film(filmSize: .size14InX17In))
        let preview = composed.downsampled(maxDimension: 400)
        XCTAssertEqual(max(preview.width, preview.height), 400)
        XCTAssertEqual(preview.info.printJobUID, composed.info.printJobUID)
        XCTAssertEqual(preview.pixels.count, preview.bytesPerRow * preview.height)
    }

    func testCGImageIsProducedForOutput() throws {
        let composed = try composer.compose(film())
        let image = composed.makeCGImage()
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.width, composed.width)
        XCTAssertEqual(image?.height, composed.height)
    }

    // MARK: Trim (2010,0140) — D92

    /// Bright runs along one row of the sheet (row as a fraction, top-down).
    private func brightRuns(_ film: ComposedFilm, atFractionY fy: Double) -> Int {
        let row = min(film.height - 1, max(0, Int(Double(film.height) * fy)))
        let base = film.pixels.startIndex + row * film.bytesPerRow
        var runs = 0, inRun = false
        for column in 0..<film.width {
            let bright = film.pixels[base + column * film.samplesPerPixel] > 128
            if bright && !inRun { runs += 1 }
            inRun = bright
        }
        return runs
    }

    /// PS3.3 2026a Table C.13-3, Trim (2010,0140): "Specifies whether a trim box
    /// shall be printed surrounding each image on the film." A black 2×2 film on a
    /// black border shows only the trim boxes: a row through the top two images
    /// crosses four box edges, and the sheet corners stay clear.
    func testTrimYesPrintsABoxSurroundingEachImage() throws {
        let trimmed = try composer.compose(
            film(format: "STANDARD\\2,2", image: image(value: 0), trim: .yes))
        XCTAssertEqual(brightRuns(trimmed, atFractionY: 0.25), 4,
                       "left and right edge of the trim box around each of the two images")
        XCTAssertFalse(regionHasInk(trimmed, x: 0...0.02, y: 0...0.02),
                       "no sheet-corner crop marks")
        XCTAssertFalse(regionHasInk(trimmed, x: 0.98...1, y: 0.98...1))

        let untrimmed = try composer.compose(
            film(format: "STANDARD\\2,2", image: image(value: 0), trim: .no))
        XCTAssertFalse(regionHasInk(untrimmed), "Trim = NO prints no box")
    }

    func testTrimBoxDoesNotCoverTheImage() throws {
        // A white image on a black border: the box is drawn outside the image,
        // so the image's own pixels are unchanged by Trim = YES.
        let plain = try composer.compose(film(image: image(value: 255), trim: .no))
        let trimmed = try composer.compose(film(image: image(value: 255), trim: .yes))
        XCTAssertEqual(sample(trimmed, atFractionX: 0.5, y: 0.5), sample(plain, atFractionX: 0.5, y: 0.5))
        XCTAssertNotEqual(trimmed.pixels, plain.pixels, "the trim box is printed")
    }
}
