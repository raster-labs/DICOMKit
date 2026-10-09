//
// PrintBitDepthConformanceTests.swift
// DICOMPrintKitTests
//
// The depth a film actually goes out at.
//
// PS3.3 Table C.13-5 enumerates Bits Stored as 8 or 12 in the Basic Grayscale
// Image Sequence, and fixes the colour sequence at 8. Enumerated Values are
// closed sets (PS3.5 3.6.1), so 16 bits *stored* is not a deep-grayscale
// option — it is a non-conformant image box a printer may refuse outright.
//
// The rule these tests pin is that we neither send it nor throw the job away:
// the depth is clamped to the deepest legal value and the operator is told.
// A film at 12-bit is a good outcome; a failed job over a label nobody looks at
// is not.
//

import XCTest
import DICOMCore
import DICOMNetwork
@testable import DICOMPrintKit

final class PrintBitDepthConformanceTests: XCTestCase {

    // MARK: Fixtures

    private func request(
        bitDepth: Int,
        palette: PseudoColorPalette? = nil,
        raw: Bool = false
    ) -> PrintJobRequest {
        PrintJobRequest(
            frameSelection: .first,
            raw: raw,
            bitDepth: bitDepth,
            palette: palette)
    }

    // MARK: The catalog

    /// The picker must not offer a depth the standard does not allow: a reader
    /// choosing 16 from a list is entitled to assume it works.
    func testCatalogOffersOnlyEnumeratedDepths() {
        XCTAssertEqual(PrintOptionCatalog.bitDepths, [8, 12])
    }

    func testCatalogLabelsNameTheTradeOff() {
        XCTAssertTrue(PrintOptionCatalog.bitDepthLabel(12).contains("12-bit"))
        XCTAssertTrue(PrintOptionCatalog.bitDepthLabel(8).contains("8-bit"))
        // The labels exist so the choice is informed, not decorative.
        XCTAssertNotEqual(
            PrintOptionCatalog.bitDepthLabel(8),
            PrintOptionCatalog.bitDepthLabel(12))
    }

    // MARK: Clamping

    func testLegalDepthsPassThroughUntouched() {
        XCTAssertEqual(PrintImagePreparer.preparationBitDepth(request(bitDepth: 8)), 8)
        XCTAssertEqual(PrintImagePreparer.preparationBitDepth(request(bitDepth: 12)), 12)
    }

    /// The case this file exists for: 16 becomes 12, not 8. Dropping four bits
    /// is a visible loss on film and dropping eight is a worse one, so the
    /// clamp goes to the *deepest* legal value, not the safest one.
    func testSixteenBitClampsToTwelveNotEight() {
        XCTAssertEqual(PrintImagePreparer.preparationBitDepth(request(bitDepth: 16)), 12)
    }

    /// Clamping never rounds up. A job that asked for 8 gets 8 — inventing
    /// precision the caller did not ask for would be its own kind of wrong.
    func testClampNeverIncreasesDepth() {
        XCTAssertEqual(PrintImagePreparer.clampedGrayscaleBitDepth(8), 8)
        XCTAssertEqual(PrintImagePreparer.clampedGrayscaleBitDepth(10), 8)
        XCTAssertEqual(PrintImagePreparer.clampedGrayscaleBitDepth(12), 12)
        XCTAssertEqual(PrintImagePreparer.clampedGrayscaleBitDepth(16), 12)
    }

    /// A palette takes the frame to the colour image box, which Table C.13-5
    /// fixes at 8 bits per sample — so the palette wins over any depth asked
    /// for, including a legal one.
    func testPaletteForcesEightBitsRegardlessOfRequest() {
        XCTAssertEqual(
            PrintImagePreparer.preparationBitDepth(
                request(bitDepth: 12, palette: .hotIron)), 8)
        XCTAssertEqual(
            PrintImagePreparer.preparationBitDepth(
                request(bitDepth: 16, palette: .hotIron)), 8)
    }

    /// A grey palette is the absence of colour, so it must not drag a film off
    /// the deep-grayscale path — that would cost four bits for no colour at all.
    func testGrayPaletteKeepsDeepGrayscale() {
        XCTAssertEqual(
            PrintImagePreparer.preparationBitDepth(
                request(bitDepth: 12, palette: .grayscale)), 12)
    }

    // MARK: What the operator is told

    func testConformantRequestSaysNothing() {
        XCTAssertNil(PrintImagePreparer.clampNote(request(bitDepth: 8)))
        XCTAssertNil(PrintImagePreparer.clampNote(request(bitDepth: 12)))
    }

    /// The note has to be actionable: it names the depth asked for, the depth
    /// used, and the clause that made the difference, so whoever reads the log
    /// can fix the setting rather than guess.
    func testClampNoteNamesRequestedAndActualDepth() throws {
        let note = try XCTUnwrap(PrintImagePreparer.clampNote(request(bitDepth: 16)))
        XCTAssertTrue(note.contains("16-bit"), note)
        XCTAssertTrue(note.contains("12-bit"), note)
        // Bits Stored 8/12 is the Image Box Pixel Presentation Module, Table
        // C.13-5 (C.13-3 is the Film Box module) — D23.
        XCTAssertTrue(note.contains("C.13-5"), note)
    }

    func testPaletteNoteExplainsWhyDepthWasDropped() throws {
        let note = try XCTUnwrap(
            PrintImagePreparer.clampNote(request(bitDepth: 12, palette: .hotIron)))
        XCTAssertTrue(note.contains("C.13-5"), note)
        XCTAssertTrue(note.contains("8-bit"), note)
    }

    /// `--raw` sends stored pixels untouched by definition, so there is no
    /// preparation depth to complain about.
    func testRawJobSaysNothing() {
        XCTAssertNil(PrintImagePreparer.clampNote(request(bitDepth: 8, raw: true)))
    }

    // MARK: Validation

    /// 16 is still *accepted* — it was offered by earlier builds and survives in
    /// queued jobs — because clamping it later is better than failing a job that
    /// used to run.
    func testSixteenBitRequestStillValidates() {
        XCTAssertNoThrow(try request(bitDepth: 16).validate())
    }

    func testNonsenseDepthIsRejected() {
        XCTAssertThrowsError(try request(bitDepth: 10).validate())
        XCTAssertThrowsError(try request(bitDepth: 0).validate())
    }
}

// MARK: - What the printer's log shows

/// The SCP half of the same rule, checked at the surface the operator actually
/// reads: a corrected image box must produce a visible warning line, not a
/// silent success that looks identical to a conformant job.
final class PrintSCPCorrectionLogTests: XCTestCase {

    func testCorrectionRendersAsAWarningLine() throws {
        let resolved = PrintPixelDepthConformance.resolve(
            bitsStored: 16, bitsAllocated: 16, isColor: false)
        let note = try XCTUnwrap(resolved.notes.first)

        let entry = try XCTUnwrap(PrintSCPConsole.logEntry(
            for: .imageBoxCorrected(uid: "1.2.3", position: 1, detail: note)))

        XCTAssertEqual(entry.level, .warning)
        XCTAssertTrue(entry.message.contains("Image box 1"), entry.message)
        // PS3.3 Table C.13-5 is the Image Box Pixel Presentation Module,
        // which enumerates the depths for both image sequences.
        XCTAssertTrue(entry.message.contains("C.13-5"), entry.message)

        // The rendered line is what ends up on screen, so it is worth pinning
        // that the warning tag survives formatting.
        let line = PrintSCPConsole.consoleLine(for: entry)
        XCTAssertTrue(line.contains("[warn]"), line)
    }

    /// A conformant box must stay quiet: a warning on every ordinary film would
    /// train the operator to ignore the one that matters.
    func testConformantBoxProducesNoCorrectionLine() {
        let resolved = PrintPixelDepthConformance.resolve(
            bitsStored: 12, bitsAllocated: 16, isColor: false)
        XCTAssertTrue(resolved.notes.isEmpty)
    }
}
