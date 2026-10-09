// PrintPaletteTests.swift
// DICOMPrintKitTests
//
// The rules that decide whether a film goes to colour, and what it gives up
// when it does. These are the decisions no unit test of the palettes themselves
// would catch: the palette can be perfect and the film still print grey because
// the preparer never widened, or print colour and silently lose the bit depth
// the job asked for.

import Testing
import Foundation
import DICOMCore
@testable import DICOMPrintKit

@Suite("Print palette rules")
struct PrintPaletteTests {

    private func request(
        palette: PseudoColorPalette? = nil,
        raw: Bool = false,
        bitDepth: Int = 8
    ) -> PrintJobRequest {
        var request = PrintJobRequest()
        request.palette = palette
        request.raw = raw
        request.bitDepth = bitDepth
        return request
    }

    // MARK: Which palettes reach the pixels

    @Test("A colour palette is carried to the preparer")
    func colourPaletteIsCarried() {
        #expect(PrintImagePreparer.preparationPalette(request(palette: .hotIron))
                == .hotIron)
    }

    /// Grey is the absence of colour, and a film must not pay for it. Carrying
    /// it down would push the frame onto the RGB path, which costs the bit depth
    /// and the density curve for no colour at all.
    @Test("Grey palettes are dropped rather than carried",
          arguments: [PseudoColorPalette.grayscale, .inverseGrayscale])
    func greyPalettesAreDropped(_ palette: PseudoColorPalette) {
        #expect(PrintImagePreparer.preparationPalette(request(palette: palette)) == nil)
    }

    /// Raw means the stored values reach the printer untouched. A palette is by
    /// definition a transformation of them, so the two cannot both be honoured —
    /// and raw is the more explicit request.
    @Test("A raw job never colourises")
    func rawNeverColourises() {
        #expect(PrintImagePreparer.preparationPalette(
            request(palette: .hotIron, raw: true)) == nil)
    }

    @Test("No palette means no palette")
    func noPalette() {
        #expect(PrintImagePreparer.preparationPalette(request()) == nil)
    }

    // MARK: What colour costs

    /// PS3.3 Table C.13-5 fixes Bits Allocated and Bits Stored at 8 for the
    /// Basic Color Image Box, so a coloured frame has no deeper form to take.
    /// Asking for 12- or 16-bit greys alongside a palette is a contradiction,
    /// and the palette wins.
    @Test("Colour drops the job to 8-bit", arguments: [8, 12, 16])
    func colourIsEightBit(_ depth: Int) {
        #expect(PrintImagePreparer.preparationBitDepth(
            request(palette: .pet, bitDepth: depth)) == 8)
    }

    /// A grey film keeps every depth the standard actually allows. 16 is not
    /// one of them — PS3.3 Table C.13-5 enumerates Bits Stored as 8 or 12 — so
    /// it is tested separately, below, where it is clamped rather than kept.
    @Test("A grey film keeps the depth it asked for", arguments: [8, 12])
    func greyKeepsDepth(_ depth: Int) {
        #expect(PrintImagePreparer.preparationBitDepth(
            request(bitDepth: depth)) == depth)
        // Explicit grey is still grey: it must not cost the depth either.
        #expect(PrintImagePreparer.preparationBitDepth(
            request(palette: .grayscale, bitDepth: depth)) == depth)
    }

    /// 16-bit *stored* is not a Basic Grayscale Image Box value, however
    /// natural it looks beside a 16-bit source. It is clamped to the deepest
    /// legal depth rather than refused, so the film still prints — see
    /// `PrintBitDepthConformanceTests` for the full rule.
    @Test("A grey film cannot ask for 16-bit")
    func greyClampsSixteenBit() {
        #expect(PrintImagePreparer.preparationBitDepth(request(bitDepth: 16)) == 12)
        #expect(PrintImagePreparer.preparationBitDepth(
            request(palette: .grayscale, bitDepth: 16)) == 12)
    }

    // MARK: Widening

    private func descriptor(samplesPerPixel: Int, photometric: PhotometricInterpretation)
        -> PixelDataDescriptor {
        PixelDataDescriptor(
            rows: 8, columns: 8, numberOfFrames: 1,
            bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false,
            samplesPerPixel: samplesPerPixel,
            photometricInterpretation: photometric)
    }

    /// The behaviour the whole feature rests on: a palette is the one thing that
    /// puts colour into a monochrome source. Without this the cell is prepared
    /// as grey and the chosen colours never reach the film.
    @Test("A palette widens a monochrome source to colour")
    func paletteWidensMonochrome() {
        let mode = PrintImagePreparer.preparationColorMode(
            request(palette: .hotIron),
            sourceDescriptor: descriptor(samplesPerPixel: 1, photometric: .monochrome2))
        #expect(mode == .color)
    }

    /// The pre-existing rule, which must survive: a monochrome source with no
    /// palette stays monochrome whatever else is asked for.
    @Test("Without a palette a monochrome source stays grey")
    func monochromeStaysGrey() {
        let mode = PrintImagePreparer.preparationColorMode(
            request(),
            sourceDescriptor: descriptor(samplesPerPixel: 1, photometric: .monochrome2))
        #expect(mode == .grayscale)
    }

    @Test("An explicitly grey palette does not widen")
    func greyDoesNotWiden() {
        let mode = PrintImagePreparer.preparationColorMode(
            request(palette: .grayscale),
            sourceDescriptor: descriptor(samplesPerPixel: 1, photometric: .monochrome2))
        #expect(mode == .grayscale)
    }
}

@Suite("Presentation palette")
struct ViewerPresentationPaletteTests {

    /// The trap this feature had to avoid: both render paths and the print path
    /// skip their work entirely when a presentation is the identity, so a
    /// palette that did not count would be written to the cell and then ignored
    /// — the picker would look dead.
    @Test("A colour palette makes a presentation non-identity")
    func colourIsNotIdentity() {
        #expect(ViewerPresentation().isIdentity)
        #expect(ViewerPresentation(palette: .hotIron).isIdentity == false)
        #expect(ViewerPresentation(palette: .viridis).colorizes)
    }

    /// Grey must stay identity, or every cell on a grey film would be dragged
    /// through the arranging path for nothing.
    @Test("Grey palettes leave a presentation at the identity")
    func greyIsIdentity() {
        #expect(ViewerPresentation(palette: .grayscale).isIdentity)
        #expect(ViewerPresentation(palette: .grayscale).colorizes == false)
        #expect(ViewerPresentation(palette: .inverseGrayscale).colorizes == false)
    }

    @Test("No choice resolves to grey")
    func effectivePalette() {
        #expect(ViewerPresentation().effectivePalette == .grayscale)
        #expect(ViewerPresentation(palette: .pet).effectivePalette == .pet)
    }

    /// The presentation is stored with saved views and print jobs, so the
    /// palette has to survive the round trip or a reopened job loses its colour.
    @Test("The palette survives a coding round trip")
    func codingRoundTrip() throws {
        let original = ViewerPresentation(
            zoom: 2, rotationDegrees: 90, invert: true, palette: .hotMetalBlue)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ViewerPresentation.self, from: data)
        #expect(decoded == original)
        #expect(decoded.palette == .hotMetalBlue)
    }

    /// An older saved view has no palette field at all; it must decode as "no
    /// choice" rather than failing the whole presentation.
    @Test("A presentation saved before palettes still decodes")
    func decodesWithoutPalette() throws {
        let json = """
        {"zoom":1.0,"panX":0.0,"panY":0.0,"viewportWidth":0.0,"viewportHeight":0.0,
         "rotationDegrees":0.0,"flipHorizontal":false,"flipVertical":false,"invert":false}
        """
        let decoded = try JSONDecoder().decode(
            ViewerPresentation.self, from: Data(json.utf8))
        #expect(decoded.palette == nil)
        #expect(decoded.isIdentity)
    }
}

@Suite("Palette identity on the wire")
struct PalettePrintIdentityTests {

    /// The fact the whole feature has to be honest about: Print Management has
    /// nowhere to carry a palette. PS3.3 Table C.13-5 enumerates `RGB` as the
    /// only photometric interpretation a Basic Color Image Sequence may hold,
    /// and "palette" does not occur anywhere in PS3.4 Annex H.
    ///
    /// So the UID is *not* something to send — it is what the audit trail
    /// records, and it must exist for exactly the eight the standard defines.
    @Test("Only DICOM's own palettes have a UID to record")
    func onlyStandardPalettesAreIdentifiable() {
        let identified = PseudoColorPalette.allCases
            .filter { $0.wellKnownSOPInstanceUID != nil }
        #expect(identified.count == 8)
        for palette in identified {
            #expect(palette.group == .dicomStandard)
            // Well-known Color Palette SOP Instances live under 1.2.840.10008.1.5.
            #expect(palette.wellKnownSOPInstanceUID?.hasPrefix("1.2.840.10008.1.5.") == true)
        }
    }

    /// A palette's stored form is the standard's Content Label, so a job saved
    /// and reloaded still names the palette the way the standard does.
    @Test("Standard palettes round-trip through their DICOM label")
    func labelsRoundTrip() throws {
        for palette in PseudoColorPalette.allCases where palette.group == .dicomStandard {
            let label = try #require(palette.contentLabel)
            #expect(PseudoColorPalette(rawValue: label) == palette)
        }
    }
}
