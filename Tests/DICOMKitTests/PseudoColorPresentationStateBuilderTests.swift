//
// PseudoColorPresentationStateBuilderTests.swift
// DICOMKit
//
// The contract that makes a coloured saved view exportable: what the
// Pseudo-Color builder writes, the parser reads back, and the palette
// catalogue recognises — byte-exactly, for every palette offered.
//
// Most of these are round trips for the same reason the grayscale builder's
// tests are: a palette that renders as Hot Iron here and as an anonymous table
// anywhere else has not actually been carried, and the whole point of writing
// …11.3 instead of a private sidecar is that the file itself says which
// colours the reader was looking through.
//

import XCTest
import DICOMCore
@testable import DICOMKit

final class PseudoColorPresentationStateBuilderTests: XCTestCase {

    // MARK: - Fixtures

    private let imageSOPClassUID = "1.2.840.10008.5.1.4.1.1.2"

    private func context() -> PresentationStatePatientContext {
        PresentationStatePatientContext(
            patientName: "DOE^JANE",
            patientID: "12345",
            studyInstanceUID: "1.2.3.4.5",
            studyDate: "20260101")
    }

    private func state(
        presentationLUT: PresentationLUT? = .identity,
        voiLUT: VOILUT? = .window(
            center: 40, width: 400, explanation: nil, function: .linear)
    ) -> GrayscalePresentationState {
        GrayscalePresentationState(
            sopInstanceUID: "1.2.3.4.5.99.1",
            sopClassUID: PseudoColorPresentationStateBuilder.sopClassUID,
            instanceNumber: 1,
            presentationLabel: "PET fused",
            // Type 1 in Table C.11.10-1
            presentationCreationDate: DICOMDate(year: 2026, month: 9, day: 29),
            presentationCreationTime: DICOMTime(hour: 9, minute: 0, second: 0),
            referencedSeries: [
                ReferencedSeries(
                    seriesInstanceUID: "1.2.3.4.5.6",
                    referencedImages: [
                        ReferencedImage(
                            sopClassUID: imageSOPClassUID,
                            sopInstanceUID: "1.2.3.4.5.6.1")
                    ])
            ],
            voiLUT: voiLUT,
            presentationLUT: presentationLUT)
    }

    private func build(
        _ palette: PseudoColorPalette,
        presentationLUT: PresentationLUT? = .identity
    ) -> DataSet {
        PseudoColorPresentationStateBuilder().buildDataSet(
            from: state(presentationLUT: presentationLUT),
            palette: palette,
            patient: context(),
            seriesInstanceUID: "1.2.3.4.5.900",
            seriesNumber: 900,
            // The state records no area; the Type 1 Displayed Area (Table
            // C.10-4) is derived from the image size.
            imageSize: (columns: 512, rows: 512))
    }

    // MARK: - Identity

    func test_build_writesPseudoColorSOPClass() {
        let dataSet = build(.hotIron)
        XCTAssertEqual(
            dataSet.string(for: .sopClassUID), "1.2.840.10008.5.1.4.1.1.11.3")
        XCTAssertEqual(dataSet.string(for: .modality), "PR")
    }

    /// The Softcopy Presentation LUT module is not part of this IOD, so the
    /// shape the delegated grayscale build wrote must come out again — a
    /// left-over IDENTITY would be a module from someone else's IOD.
    func test_build_stripsPresentationLUTShape() {
        XCTAssertNil(build(.hotIron)[.presentationLUTShape])
        XCTAssertNil(build(.hotIron, presentationLUT: .inverse)[.presentationLUTShape])
    }

    // MARK: - The palette module

    /// Descriptor `(256, 0, 8)` — the exact shape PS3.6 Annex B gives every
    /// well-known palette, as three US values.
    func test_build_writesAnnexBDescriptors() throws {
        let dataSet = build(.pet)
        for tag: Tag in [.redPaletteColorLookupTableDescriptor,
                         .greenPaletteColorLookupTableDescriptor,
                         .bluePaletteColorLookupTableDescriptor] {
            let element = try XCTUnwrap(dataSet[tag])
            XCTAssertEqual(element.vr, .US)
            XCTAssertEqual(element.valueData, Data([0x00, 0x01, 0, 0, 8, 0]))
        }
    }

    /// One byte per entry: 256 bytes per channel, even-length so OW carries it
    /// without padding, and the form `PaletteColorLUT.parseLUTData` reads back
    /// byte-for-byte.
    func test_build_writes256ByteChannels() throws {
        let dataSet = build(.viridis)
        for tag: Tag in [.redPaletteColorLookupTableData,
                         .greenPaletteColorLookupTableData,
                         .bluePaletteColorLookupTableData] {
            let element = try XCTUnwrap(dataSet[tag])
            XCTAssertEqual(element.vr, .OW)
            XCTAssertEqual(element.valueData.count, 256)
        }
    }

    /// The eight standard palettes carry the standard's own name for their
    /// table; a palette of our own has no UID to claim.
    func test_build_writesWellKnownUIDOnlyForStandardPalettes() {
        XCTAssertEqual(
            build(.hotIron).string(for: .paletteColorLookupTableUID),
            "1.2.840.10008.1.5.1")
        XCTAssertNil(build(.viridis).string(for: .paletteColorLookupTableUID))
        // A reversed table is no longer the table the UID names.
        XCTAssertNil(
            build(.hotIron, presentationLUT: .inverse)
                .string(for: .paletteColorLookupTableUID))
    }

    // MARK: - ICC Profile module

    /// Mandatory in this IOD (PS3.3 A.33.4) — and the profile has to be one our
    /// own ICC parser accepts, or we would be shipping bytes we cannot vouch for.
    func test_build_writesParseableICCProfile() throws {
        let dataSet = build(.jet)
        let element = try XCTUnwrap(dataSet[.iccProfile])
        XCTAssertEqual(element.vr, .OB)

        let parsed = try ICCProfileParser.parse(element.valueData)
        // PS3.3 C.11.15.1.1: the profile is an ICC Input Device profile ("scnr")
        XCTAssertEqual(parsed.header.deviceClass, .inputDevice)
        XCTAssertEqual(parsed.header.dataColorSpace, .rgb)
        XCTAssertEqual(dataSet.string(for: .colorSpace), "SRGB")
    }

    /// Deterministic: the same view saved twice must be the same bytes, and a
    /// profile that varies with the OS that wrote it breaks that.
    func test_iccProfile_isByteStable() {
        XCTAssertEqual(SRGBICCProfileWriter.profileData, SRGBICCProfileWriter.profileData)
        XCTAssertEqual(
            Int(SRGBICCProfileWriter.profileData.count) % 4, 0,
            "ICC profiles are 4-byte aligned")
        // The declared size in the header is the actual size.
        let declared = SRGBICCProfileWriter.profileData.prefix(4)
            .reduce(0) { ($0 << 8) | UInt32($1) }
        XCTAssertEqual(Int(declared), SRGBICCProfileWriter.profileData.count)
    }

    // MARK: - Round trips

    /// Every palette in the catalogue must survive the full journey: built into
    /// tags, parsed back as a table, recognised as itself. One failure here is
    /// a palette that exports as an anonymous ramp.
    func test_everyPalette_roundTripsByteExactly() throws {
        for palette in PseudoColorPalette.allCases {
            let dataSet = build(palette)

            let parsed = try GrayscalePresentationStateParser().parse(dataSet: dataSet)
            XCTAssertEqual(
                parsed.sopClassUID, PseudoColorPresentationStateBuilder.sopClassUID,
                "\(palette.rawValue): SOP class must survive the parse")

            let lut = try XCTUnwrap(
                dataSet.paletteColorLUT(), "\(palette.rawValue): LUT must read back")
            XCTAssertEqual(lut.redLUT, palette.lut().redLUT, palette.rawValue)
            XCTAssertEqual(lut.greenLUT, palette.lut().greenLUT, palette.rawValue)
            XCTAssertEqual(lut.blueLUT, palette.lut().blueLUT, palette.rawValue)

            let match = try XCTUnwrap(
                PseudoColorPalette.matching(lut),
                "\(palette.rawValue): the catalogue must recognise its own table")
            // Table equality, not case equality: the catalogue holds one
            // genuine duplicate — FALL (PS3.6 Annex B) and Hue 2 compute the
            // identical 256 entries — and recognition can only ever name the
            // table, which renders the same under either name. (For the
            // duplicated pair the well-known palette wins by catalogue order,
            // which is the better name: it carries the standard's UID.)
            XCTAssertEqual(
                match.palette.lut().redLUT, palette.lut().redLUT, palette.rawValue)
            XCTAssertEqual(
                match.palette.lut().greenLUT, palette.lut().greenLUT, palette.rawValue)
            XCTAssertEqual(
                match.palette.lut().blueLUT, palette.lut().blueLUT, palette.rawValue)
            XCTAssertFalse(match.inverted, palette.rawValue)
        }
    }

    /// The shared display attributes still mean what the grayscale builder's
    /// tests prove they mean — delegation must not have cost the window.
    func test_roundTrip_preservesSharedDisplayAttributes() throws {
        let parsed = try GrayscalePresentationStateParser().parse(dataSet: build(.pet))
        guard case .window(let center, let width, _, _)? = parsed.voiLUT else {
            return XCTFail("VOI window lost in the pseudo-colour round trip")
        }
        XCTAssertEqual(center, 40)
        XCTAssertEqual(width, 400)
        XCTAssertEqual(
            parsed.referencedSeries.first?.referencedImages.first?.sopInstanceUID,
            "1.2.3.4.5.6.1")
    }

    /// INVERSE has no legal spelling in this IOD, so it is baked: the table is
    /// written back-to-front, and recognition reports both the palette and the
    /// inversion. Losing either half would restore a different view than was
    /// saved.
    func test_inverse_isBakedIntoTheTableAndRecognised() throws {
        let dataSet = build(.hotIron, presentationLUT: .inverse)

        let lut = try XCTUnwrap(dataSet.paletteColorLUT())
        let entries = PseudoColorPalette.hotIron.entries()
        XCTAssertEqual(UInt8(lut.redLUT[0] >> 8), entries[255].red)
        XCTAssertEqual(UInt8(lut.redLUT[255] >> 8), entries[0].red)

        let match = try XCTUnwrap(PseudoColorPalette.matching(lut))
        XCTAssertEqual(match.palette, .hotIron)
        XCTAssertTrue(match.inverted)
    }

    // MARK: - The palette module, sized to the image

    private func build(
        _ palette: PseudoColorPalette,
        domain: PseudoColorPresentationStateBuilder.PixelDomain,
        presentationLUT: PresentationLUT? = .identity,
        voiLUT: VOILUT? = nil
    ) -> DataSet {
        PseudoColorPresentationStateBuilder().buildDataSet(
            from: state(presentationLUT: presentationLUT, voiLUT: voiLUT),
            palette: palette,
            pixelDomain: domain,
            patient: context(),
            seriesInstanceUID: "1.2.3.4.5.900",
            seriesNumber: 900)
    }

    /// The bug this sizing exists to fix: a 256-entry table under a 12-bit CT
    /// leaves pixel 1500 clamped to entry 255, and the whole film comes out
    /// the top colour. The table must hold one entry per storable value —
    /// descriptor `(4096, 0, 8)`, 4096 bytes per channel — and with no window
    /// to bake, resampled so entry `i` is palette entry `i / 16`.
    func test_build_12BitDomain_writesFullRangeTable() throws {
        let dataSet = build(
            .hotIron, domain: .init(bitsStored: 12, isSigned: false))

        for tag: Tag in [.redPaletteColorLookupTableDescriptor,
                         .greenPaletteColorLookupTableDescriptor,
                         .bluePaletteColorLookupTableDescriptor] {
            let element = try XCTUnwrap(dataSet[tag])
            XCTAssertEqual(element.vr, .US)
            XCTAssertEqual(element.valueData, Data([0x00, 0x10, 0, 0, 8, 0]))
        }

        let entries = PseudoColorPalette.hotIron.entries()
        for tag: Tag in [.redPaletteColorLookupTableData,
                         .greenPaletteColorLookupTableData,
                         .bluePaletteColorLookupTableData] {
            XCTAssertEqual(try XCTUnwrap(dataSet[tag]).valueData.count, 4096)
        }
        let red = try XCTUnwrap(dataSet[.redPaletteColorLookupTableData]).valueData
        XCTAssertEqual(red[red.startIndex], entries[0].red)
        XCTAssertEqual(red[red.startIndex + 15], entries[0].red)
        XCTAssertEqual(red[red.startIndex + 16], entries[1].red)
        XCTAssertEqual(red[red.startIndex + 4095], entries[255].red)
    }

    /// With a window, the table is *not* baked: PS3.4 N.2 (Figure N.2-1)
    /// applies the VOI LUT first and maps its full output range onto the
    /// palette's whole input range, so the window goes out once, as Softcopy
    /// VOI LUT, and the table carries the palette's ramp evenly over the
    /// stored range — baking it as well double-windowed in a conforming viewer.
    func test_build_windowedDomain_keepsTheWindowOutOfTheTable() throws {
        // Window 40±40 rescaled, intercept -1024 → stored 1024...1104.
        let dataSet = build(
            .hotIron,
            domain: .init(
                bitsStored: 12, isSigned: false,
                rescaleSlope: 1, rescaleIntercept: -1024),
            voiLUT: .window(center: 40, width: 80, explanation: nil, function: .linear))

        let entries = PseudoColorPalette.hotIron.entries()
        let red = try XCTUnwrap(dataSet[.redPaletteColorLookupTableData]).valueData
        XCTAssertEqual(red.count, 4096)
        // Evenly resampled: entry i is palette entry i / 16, window or not.
        XCTAssertEqual(red[red.startIndex], entries[0].red)
        XCTAssertEqual(red[red.startIndex + 1024], entries[64].red)
        XCTAssertEqual(red[red.startIndex + 1064], entries[66].red)
        XCTAssertEqual(red[red.startIndex + 4095], entries[255].red)

        // The window itself travels in the Softcopy VOI LUT Sequence (C.11.8).
        let voi = try XCTUnwrap(dataSet[.softcopyVOILUTSequence]?.sequenceItems?.first)
        XCTAssertEqual(voi.string(for: .windowCenter), "40")
        XCTAssertEqual(voi.string(for: .windowWidth), "80")

        // Resampled is not the Annex B table, so no Annex B name.
        XCTAssertNil(dataSet.string(for: .paletteColorLookupTableUID))

        // And it still comes back as the palette the reader chose.
        let lut = try XCTUnwrap(dataSet.paletteColorLUT())
        let match = try XCTUnwrap(PseudoColorPalette.matching(lut))
        XCTAssertEqual(match.palette, .hotIron)
        XCTAssertFalse(match.inverted)
    }

    /// The inverse view writes the reversed palette — and recognition reports
    /// both halves, or the restored view is a different picture.
    func test_build_windowedInverse_reversesTableAndIsRecognised() throws {
        let dataSet = build(
            .hotIron,
            domain: .init(
                bitsStored: 12, isSigned: false,
                rescaleSlope: 1, rescaleIntercept: -1024),
            presentationLUT: .inverse,
            voiLUT: .window(center: 40, width: 80, explanation: nil, function: .linear))
        let lut = try XCTUnwrap(dataSet.paletteColorLUT())
        let match = try XCTUnwrap(PseudoColorPalette.matching(lut))
        XCTAssertEqual(match.palette, .hotIron)
        XCTAssertTrue(match.inverted)
    }

    /// A resampled table is not the table the Annex B UID names; writing the
    /// name anyway would invite a viewer to substitute the named 256-entry
    /// table — reintroducing the very clamping the resampling fixes.
    func test_build_resampledTable_carriesNoWellKnownUID() {
        XCTAssertNil(
            build(.hotIron, domain: .init(bitsStored: 12, isSigned: false))
                .string(for: .paletteColorLookupTableUID))
        // An 8-bit domain resolves to the exact Annex B table, which keeps
        // its name — with or without a window, since the window is never
        // baked into the table (PS3.4 N.2).
        XCTAssertEqual(
            build(.hotIron, domain: .init(bitsStored: 8, isSigned: false))
                .string(for: .paletteColorLookupTableUID),
            "1.2.840.10008.1.5.1")
        XCTAssertEqual(
            build(.hotIron, domain: .init(bitsStored: 8, isSigned: false),
                  voiLUT: .window(
                      center: 128, width: 128, explanation: nil, function: .linear))
                .string(for: .paletteColorLookupTableUID),
            "1.2.840.10008.1.5.1")
    }

    /// Signed pixels index from below zero, so the descriptor's first mapped
    /// value must be the smallest stored value — written two's complement
    /// under VR SS, the encoding PS3.3 C.7.6.3.1.5 keys to Pixel
    /// Representation.
    func test_build_signedDomain_writesSignedDescriptor() throws {
        let dataSet = build(.pet, domain: .init(bitsStored: 12, isSigned: true))
        let element = try XCTUnwrap(dataSet[.redPaletteColorLookupTableDescriptor])
        XCTAssertEqual(element.vr, .SS)
        // 4096 entries, first mapped -2048 (0xF800), 8 bits.
        XCTAssertEqual(element.valueData, Data([0x00, 0x10, 0x00, 0xF8, 8, 0]))
    }

    /// A 16-bit domain needs 65536 entries, which the descriptor spells as 0.
    func test_build_16BitDomain_spellsEntryCountAsZero() throws {
        let dataSet = build(.jet, domain: .init(bitsStored: 16, isSigned: false))
        let element = try XCTUnwrap(dataSet[.redPaletteColorLookupTableDescriptor])
        XCTAssertEqual(element.valueData, Data([0x00, 0x00, 0, 0, 8, 0]))
        XCTAssertEqual(
            try XCTUnwrap(dataSet[.redPaletteColorLookupTableData]).valueData.count,
            65536)
    }

    /// The journey that makes the sizing safe to ship: a full-range table must
    /// still come back as the palette the reader chose — inversion included —
    /// or deep saves would restore anonymous.
    func test_12BitDomain_roundTripsToNamedPalette() throws {
        let domain = PseudoColorPresentationStateBuilder.PixelDomain(
            bitsStored: 12, isSigned: false)

        let lut = try XCTUnwrap(
            build(.viridis, domain: domain).paletteColorLUT())
        let match = try XCTUnwrap(PseudoColorPalette.matching(lut))
        XCTAssertEqual(match.palette, .viridis)
        XCTAssertFalse(match.inverted)

        let invertedLUT = try XCTUnwrap(
            build(.hotIron, domain: domain, presentationLUT: .inverse)
                .paletteColorLUT())
        let invertedMatch = try XCTUnwrap(PseudoColorPalette.matching(invertedLUT))
        XCTAssertEqual(invertedMatch.palette, .hotIron)
        XCTAssertTrue(invertedMatch.inverted)
    }

    /// Recognition compares every entry, not one sample per block — a foreign
    /// table that merely agrees at the sampled points must not be named ours.
    func test_matching_rejectsForeignResampledTables() throws {
        let lut = try XCTUnwrap(
            build(.hotIron, domain: .init(bitsStored: 12, isSigned: false))
                .paletteColorLUT())
        var red = lut.redLUT
        // Inside a block, off the sampled point: entry 17 belongs to block 1.
        red[17] ^= 0x0100
        let tampered = PaletteColorLUT(
            redDescriptor: lut.redDescriptor,
            greenDescriptor: lut.greenDescriptor,
            blueDescriptor: lut.blueDescriptor,
            redLUT: red, greenLUT: lut.greenLUT, blueLUT: lut.blueLUT)
        XCTAssertNil(PseudoColorPalette.matching(tampered))
    }

    // MARK: - Recognition limits

    /// A foreign table must come back as "not ours", not as the nearest of
    /// ours: naming someone else's palette Hot Iron would be a lie on film and
    /// on screen alike.
    func test_matching_rejectsForeignTables() {
        var lut = PseudoColorPalette.hotIron.lut()
        var red = lut.redLUT
        red[128] ^= 0x0100 // one entry, one bit of the significant byte
        lut = PaletteColorLUT(
            redDescriptor: lut.redDescriptor,
            greenDescriptor: lut.greenDescriptor,
            blueDescriptor: lut.blueDescriptor,
            redLUT: red, greenLUT: lut.greenLUT, blueLUT: lut.blueLUT)
        XCTAssertNil(PseudoColorPalette.matching(lut))
    }

    // MARK: - Validation

    /// The object the builder emits must satisfy our own validator's idea of
    /// the IOD — the same check an inbound file gets.
    func test_builtObject_passesIODValidation() {
        let dataSet = build(.spring)
        var errors: [ValidationIssue] = []
        var warnings: [ValidationIssue] = []
        PseudoColorSoftcopyPresentationStateValidator().validate(
            dataSet: dataSet, errors: &errors, warnings: &warnings)
        XCTAssertTrue(errors.isEmpty, "\(errors.map(\.message))")
    }

    /// Table C.11.12-1: Shutter Presentation Color CIELab Value (0018,1624) is
    /// required with a shutter in every class but GSPS — this one included. A
    /// state that names no colour gets black; one that does keeps it.
    func test_build_writesShutterPresentationColourWithShutters() throws {
        let colourTag = Tag(group: 0x0018, element: 0x1624)
        func build(colour: CIELabColor?, shutters: [DisplayShutter]) -> DataSet {
            let base = state()
            let shuttered = GrayscalePresentationState(
                sopInstanceUID: base.sopInstanceUID,
                sopClassUID: base.sopClassUID,
                referencedSeries: base.referencedSeries,
                voiLUT: base.voiLUT,
                shutters: shutters,
                shutterPresentationColor: colour)
            return PseudoColorPresentationStateBuilder().buildDataSet(
                from: shuttered, palette: .hotIron, patient: context(),
                seriesInstanceUID: "1.2.3.4.5.900", seriesNumber: 900,
                imageSize: (columns: 512, rows: 512))
        }
        let circle: DisplayShutter = .circular(centerColumn: 256, centerRow: 256, radius: 200, presentationValue: 0)

        XCTAssertNil(build(colour: nil, shutters: [])[colourTag], "1C: absent without a shutter")

        let defaulted = build(colour: nil, shutters: [circle])
        XCTAssertEqual(defaulted[colourTag]?.vr, .US)
        XCTAssertEqual(defaulted[colourTag]?.uint16Values, [0, 0x8080, 0x8080])

        let named = CIELabColor(l: 40000, a: 0x9000, b: 0x7000)
        let parsed = try GrayscalePresentationStateParser().parse(
            dataSet: build(colour: named, shutters: [circle]))
        XCTAssertEqual(parsed.shutterPresentationColor, named)
        XCTAssertEqual(parsed.shutters, [circle])
        XCTAssertEqual(parsed.displayedArea?.bottomRight.column, 512, "Type 1 area from the image size")
    }

    /// And a GSPS — no palette module — must fail that validator, or the
    /// validator is not checking what makes this IOD itself.
    func test_validator_rejectsGSPSMissingThePaletteModule() {
        let dataSet = GrayscalePresentationStateBuilder().buildDataSet(
            from: state(),
            patient: context(),
            seriesInstanceUID: "1.2.3.4.5.900",
            seriesNumber: 900)
        var errors: [ValidationIssue] = []
        var warnings: [ValidationIssue] = []
        PseudoColorSoftcopyPresentationStateValidator().validate(
            dataSet: dataSet, errors: &errors, warnings: &warnings)
        XCTAssertFalse(errors.isEmpty)
    }
}
