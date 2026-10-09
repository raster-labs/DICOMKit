//
// FilmGeometryTests.swift
// DICOMPrintKitTests
//
// Film sheet sizing and cell layout — the platform-independent half of the
// composer, which is where the layout bugs actually live.
//

import XCTest
import DICOMNetwork
@testable import DICOMPrintKit

final class FilmSheetTests: XCTestCase {

    func testImperialFilmSizesAreExactInchConversions() {
        let sheet = FilmSheet(filmSize: .size14InX17In, orientation: .portrait, dpi: 300)
        XCTAssertEqual(sheet.widthMillimeters, 355.6, accuracy: 0.001)
        XCTAssertEqual(sheet.heightMillimeters, 431.8, accuracy: 0.001)
        // 14 in × 300 dpi = 4200 px, 17 in × 300 dpi = 5100 px.
        XCTAssertEqual(sheet.pixelWidth, 4200)
        XCTAssertEqual(sheet.pixelHeight, 5100)
    }

    /// PS3.3 Table C.13-3: "10INX14IN corresponds with 25.7CMX36.4CM" — the
    /// sheet sold as 10×14 is JIS B4, not 254 × 355.6 mm.
    func testTenByFourteenIsTheSizeTheStandardStates() {
        let size = FilmSheet.portraitSizeMillimeters(for: .size10InX14In)
        XCTAssertEqual(size.width, 257, accuracy: 0.001)
        XCTAssertEqual(size.height, 364, accuracy: 0.001)
        // A3 is stated in the same row.
        XCTAssertEqual(FilmSheet.portraitSizeMillimeters(for: .a3).width, 297, accuracy: 0.001)
        XCTAssertEqual(FilmSheet.portraitSizeMillimeters(for: .a3).height, 420, accuracy: 0.001)
    }

    func testMetricAndISOFilmSizes() {
        XCTAssertEqual(FilmSheet.portraitSizeMillimeters(for: .a4).width, 210, accuracy: 0.001)
        XCTAssertEqual(FilmSheet.portraitSizeMillimeters(for: .a4).height, 297, accuracy: 0.001)
        XCTAssertEqual(FilmSheet.portraitSizeMillimeters(for: .size24CmX30Cm).width, 240, accuracy: 0.001)
        XCTAssertEqual(FilmSheet.portraitSizeMillimeters(for: .size24CmX30Cm).height, 300, accuracy: 0.001)
    }

    func testLandscapeSwapsTheSheet() {
        let portrait = FilmSheet(filmSize: .a4, orientation: .portrait, dpi: 150)
        let landscape = FilmSheet(filmSize: .a4, orientation: .landscape, dpi: 150)
        XCTAssertEqual(portrait.widthMillimeters, landscape.heightMillimeters, accuracy: 0.001)
        XCTAssertEqual(portrait.heightMillimeters, landscape.widthMillimeters, accuracy: 0.001)
        XCTAssertGreaterThan(landscape.pixelWidth, landscape.pixelHeight)
    }

    func testDPIScalesThePixelSheet() {
        let low = FilmSheet(filmSize: .size8InX10In, orientation: .portrait, dpi: 150)
        let high = FilmSheet(filmSize: .size8InX10In, orientation: .portrait, dpi: 300)
        XCTAssertEqual(low.pixelWidth * 2, high.pixelWidth)
        XCTAssertEqual(low.pixelHeight * 2, high.pixelHeight)
    }
}

final class FilmCellLayoutTests: XCTestCase {

    private let sheet = FilmSheet(filmSize: .size8InX10In, orientation: .portrait, dpi: 100)

    private func cells(_ format: String, margin: Double = 0, spacing: Double = 0) -> [FilmCell] {
        FilmCellLayout.cells(
            for: PrintImageDisplayFormat.parse(format), on: sheet,
            marginMillimeters: margin, spacingMillimeters: spacing)
    }

    func testStandardGridIsRowMajorAndCoversTheSheet() {
        // STANDARD\2,3 is 2 columns × 3 rows (PS3.3 C.13.3).
        let grid = cells("STANDARD\\2,3")
        XCTAssertEqual(grid.count, 6)
        XCTAssertEqual(grid.map(\.position), [1, 2, 3, 4, 5, 6])

        let width = Double(sheet.pixelWidth), height = Double(sheet.pixelHeight)
        XCTAssertEqual(grid[0].x, 0, accuracy: 0.001)
        XCTAssertEqual(grid[0].y, 0, accuracy: 0.001)
        XCTAssertEqual(grid[0].width, width / 2, accuracy: 0.001)
        XCTAssertEqual(grid[0].height, height / 3, accuracy: 0.001)

        // Position 2 sits to the right of position 1; position 3 starts the next row.
        XCTAssertEqual(grid[1].y, grid[0].y, accuracy: 0.001)
        XCTAssertEqual(grid[1].x, width / 2, accuracy: 0.001)
        XCTAssertEqual(grid[2].x, 0, accuracy: 0.001)
        XCTAssertEqual(grid[2].y, height / 3, accuracy: 0.001)

        // The last cell ends flush with the sheet.
        XCTAssertEqual(grid[5].x + grid[5].width, width, accuracy: 0.001)
        XCTAssertEqual(grid[5].y + grid[5].height, height, accuracy: 0.001)
    }

    func testMarginAndSpacingInsetTheCells() {
        let grid = cells("STANDARD\\2,1", margin: 10, spacing: 5)
        XCTAssertEqual(grid.count, 2)
        let inset = sheet.pixels(fromMillimeters: 10)
        let gap = sheet.pixels(fromMillimeters: 5)
        XCTAssertEqual(grid[0].x, inset, accuracy: 0.001)
        XCTAssertEqual(grid[0].y, inset, accuracy: 0.001)
        XCTAssertEqual(grid[1].x, inset + grid[0].width + gap, accuracy: 0.001)
        XCTAssertEqual(grid[1].x + grid[1].width, Double(sheet.pixelWidth) - inset, accuracy: 0.001)
    }

    func testRowFormatGivesEachBandItsOwnCellCount() {
        // ROW\2,3 — a row of 2 above a row of 3.
        let bands = cells("ROW\\2,3")
        XCTAssertEqual(bands.count, 5)
        XCTAssertEqual(bands.map(\.position), [1, 2, 3, 4, 5])

        let width = Double(sheet.pixelWidth), height = Double(sheet.pixelHeight)
        XCTAssertEqual(bands[0].width, width / 2, accuracy: 0.001)
        XCTAssertEqual(bands[0].height, height / 2, accuracy: 0.001)
        XCTAssertEqual(bands[2].width, width / 3, accuracy: 0.001)
        XCTAssertEqual(bands[2].y, height / 2, accuracy: 0.001)
    }

    func testColumnFormatGivesEachBandItsOwnCellCount() {
        // COL\1,2 — a full-height cell beside a stack of 2.
        let bands = cells("COL\\1,2")
        XCTAssertEqual(bands.count, 3)
        let width = Double(sheet.pixelWidth), height = Double(sheet.pixelHeight)
        XCTAssertEqual(bands[0].width, width / 2, accuracy: 0.001)
        XCTAssertEqual(bands[0].height, height, accuracy: 0.001)
        XCTAssertEqual(bands[1].x, width / 2, accuracy: 0.001)
        XCTAssertEqual(bands[1].height, height / 2, accuracy: 0.001)
        XCTAssertEqual(bands[2].y, height / 2, accuracy: 0.001)
    }

    func testSlideAndCustomFormatsUseOneFullCell() {
        for format in ["SLIDE", "SUPERSLIDE", "CUSTOM\\7"] {
            let single = cells(format)
            XCTAssertEqual(single.count, 1, format)
            XCTAssertEqual(single[0].width, Double(sheet.pixelWidth), accuracy: 0.001)
            XCTAssertEqual(single[0].height, Double(sheet.pixelHeight), accuracy: 0.001)
        }
    }
}

final class FilmImageFitterTests: XCTestCase {

    private let sheet = FilmSheet(filmSize: .size8InX10In, orientation: .portrait, dpi: 100)
    private let cell = FilmCell(position: 1, x: 100, y: 200, width: 400, height: 200)

    func testDecimateFitsAndCentresWithoutDistortion() {
        // A 4:1 image in a 2:1 cell must letterbox, keeping its aspect ratio.
        let result = FilmImageFitter.fit(
            imageWidth: 800, imageHeight: 200, in: cell,
            requestedSizeMillimeters: nil, behavior: .decimate, sheet: sheet)

        guard case .placed(let destination, _, _, let sourceWidth, let sourceHeight) = result else {
            return XCTFail("Expected a placement, got \(result)")
        }
        XCTAssertEqual(destination.width, 400, accuracy: 0.001)
        XCTAssertEqual(destination.height, 100, accuracy: 0.001)
        XCTAssertEqual(destination.x, 100, accuracy: 0.001)
        XCTAssertEqual(destination.y, 250, accuracy: 0.001, "vertically centred in the cell")
        // The whole image is drawn — nothing cropped.
        XCTAssertEqual(sourceWidth, 800, accuracy: 0.001)
        XCTAssertEqual(sourceHeight, 200, accuracy: 0.001)
    }

    func testCropFillsTheCellAndTrimsTheOverflowSymmetrically() {
        // A 1:1 image in a 2:1 cell must fill it and lose the top and bottom.
        let result = FilmImageFitter.fit(
            imageWidth: 400, imageHeight: 400, in: cell,
            requestedSizeMillimeters: nil, behavior: .crop, sheet: sheet)

        guard case .placed(let destination, let sourceX, let sourceY,
                           let sourceWidth, let sourceHeight) = result else {
            return XCTFail("Expected a placement, got \(result)")
        }
        XCTAssertEqual(destination.width, cell.width, accuracy: 0.001)
        XCTAssertEqual(destination.height, cell.height, accuracy: 0.001)
        XCTAssertEqual(sourceWidth, 400, accuracy: 0.001, "full width is used")
        XCTAssertEqual(sourceHeight, 200, accuracy: 0.001, "half the height survives")
        XCTAssertEqual(sourceX, 0, accuracy: 0.001)
        XCTAssertEqual(sourceY, 100, accuracy: 0.001, "cropped equally top and bottom")
    }

    func testFailBehaviorRejectsAnImageLargerThanTheCell() {
        let result = FilmImageFitter.fit(
            imageWidth: 4000, imageHeight: 4000, in: cell,
            requestedSizeMillimeters: nil, behavior: .failOver, sheet: sheet)
        guard case .failed = result else {
            return XCTFail("Expected FAIL to refuse an oversized image, got \(result)")
        }
    }

    func testFailBehaviorAcceptsAnImageThatFits() {
        let result = FilmImageFitter.fit(
            imageWidth: 100, imageHeight: 100, in: cell,
            requestedSizeMillimeters: nil, behavior: .failOver, sheet: sheet)
        guard case .placed(let destination, _, _, _, _) = result else {
            return XCTFail("Expected a placement, got \(result)")
        }
        XCTAssertEqual(destination.width, 100, accuracy: 0.001, "drawn 1:1")
    }

    func testRequestedImageSizePinsThePhysicalWidth() {
        // 25.4 mm at 100 DPI is 100 px, well inside the 400 px cell.
        let result = FilmImageFitter.fit(
            imageWidth: 200, imageHeight: 200, in: cell,
            requestedSizeMillimeters: 25.4, behavior: .decimate, sheet: sheet)
        guard case .placed(let destination, _, _, _, _) = result else {
            return XCTFail("Expected a placement, got \(result)")
        }
        XCTAssertEqual(destination.width, 100, accuracy: 0.5)
        XCTAssertEqual(destination.height, 100, accuracy: 0.5)
    }

    func testRequestedImageSizeNeverOverflowsTheCell() {
        // A request bigger than the cell is clamped rather than spilling over.
        let result = FilmImageFitter.fit(
            imageWidth: 200, imageHeight: 200, in: cell,
            requestedSizeMillimeters: 500, behavior: .decimate, sheet: sheet)
        guard case .placed(let destination, _, _, _, _) = result else {
            return XCTFail("Expected a placement, got \(result)")
        }
        XCTAssertLessThanOrEqual(destination.width, cell.width + 0.001)
        XCTAssertLessThanOrEqual(destination.height, cell.height + 0.001)
    }
}
