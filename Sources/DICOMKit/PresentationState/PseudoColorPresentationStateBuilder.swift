// NEMA-verified: 2026a, checked 2026-09-29 — PS3.3 2026a Table A.33.3-1: the palette carries no baked window (PS3.4 N.2, N.2.4.2); Palette Color LUT (C.7.9), ICC Profile (C.11.15) and Shutter Presentation Color CIELab Value (Table C.11.12-1)
// PseudoColorPresentationStateBuilder.swift
// DICOMKit
//
// Writes a Pseudo-Color Softcopy Presentation State (PS3.3 A.33.3) — the
// standard object for "this monochrome image was being read through a colour
// table".
//
// This is the object that lets a palette leave the machine. A GSPS has no
// colour vocabulary — its Presentation LUT speaks only of grey and its
// inverse — which is why the palette used to live in a private sidecar and
// vanished from any exported study. The Pseudo-Color IOD replaces the
// Presentation LUT with a Palette Color Lookup Table module (PS3.3 C.7.9):
// the very table the renderer applies, carried in the file, readable by any
// conforming viewer.
//
// The composition strategy is deliberate: everything the grayscale builder
// writes — patient, study, series, identification, references, VOI, spatial,
// displayed area, annotations — means exactly the same thing here, so this
// builder delegates to it and then converts the object, rather than
// duplicating four hundred lines that would drift. The conversion is:
//
//   * SOP Class UID becomes 1.2.840.10008.5.1.4.1.1.11.3.
//   * Presentation LUT Shape is removed — the module is not in this IOD. An
//     INVERSE state does not lose its inversion: the palette's entries are
//     written back-to-front instead, which renders identically and is the only
//     spelling this IOD has for it.
//   * The Palette Color LUT module is added, sized to the image: the table
//     covers the image's whole stored-pixel range (2^Bits Stored entries,
//     resampled from the palette's 256), so a conforming viewer indexing it
//     with a 12-bit pixel lands inside the table instead of clamping past its
//     end — which is what painted exported CT views a single colour. An 8-bit
//     image gets the exact 256-entry Annex B shape, as before.
//   * Palette Color Lookup Table UID (0028,1199) is added for the eight
//     palettes the standard defines — but only when the emitted table *is*
//     the Annex B table (256 entries, uninverted). A resampled table is no
//     longer the table the UID names.
//   * The ICC Profile module (C.11.15) is added — mandatory in this IOD — with
//     the fixed sRGB profile every palette here is defined in.
//
// The read half is `GrayscalePresentationStateParser`, which accepts this SOP
// class and hands the palette back through the data set's own
// `paletteColorLUT()`; `PseudoColorPalette.matching(_:)` then turns the table
// back into the palette the reader chose. The round trip is tested, because a
// state that cannot survive one is not worth storing.

import Foundation
import DICOMCore

/// Builds a conformant Pseudo-Color Softcopy Presentation State data set.
public struct PseudoColorPresentationStateBuilder: Sendable {

    /// SOP Class UID of the Pseudo-Color Softcopy Presentation State Storage
    /// IOD.
    public static let sopClassUID = "1.2.840.10008.5.1.4.1.1.11.3"

    /// Modality of a presentation state series — fixed by PS3.3 C.11.10, and
    /// the same "PR" whichever presentation state IOD the series holds.
    public static let modality = GrayscalePresentationStateBuilder.modality

    public init() {}

    // MARK: - Building

    /// Turns a presentation state and the palette it was read through into a
    /// data set ready to be written.
    ///
    /// - Parameters:
    ///   - state: What to record — the same model the grayscale builder takes,
    ///     because everything except the colour means the same thing. Its
    ///     `presentationLUT` is honoured by *baking*: `.inverse` reverses the
    ///     palette entries, since this IOD has no shape to send.
    ///   - palette: The pseudo-colour palette the view was read through.
    ///   - pixelDomain: The stored-pixel range of the image the state
    ///     describes. The palette table is resampled to cover it entry for
    ///     entry, because the Palette Color LUT is indexed by pixel value and
    ///     a 256-entry table under a 12-bit image leaves nearly every pixel
    ///     clamped to the last entry. `nil` keeps the 8-bit Annex B shape.
    ///   - patient: Patient/study attributes copied from the source image.
    ///   - seriesInstanceUID: The presentation-state series this object joins.
    ///   - seriesNumber: Series Number of that series.
    ///   - imageSize: Columns and rows of the referenced image, used to write
    ///     the mandatory Displayed Area when the state records none (see the
    ///     grayscale builder).
    /// - Returns: A data set carrying the full Pseudo-Color Softcopy
    ///   Presentation State IOD.
    public func buildDataSet(
        from state: GrayscalePresentationState,
        palette: PseudoColorPalette,
        pixelDomain: PixelDomain? = nil,
        patient: PresentationStatePatientContext,
        seriesInstanceUID: String,
        seriesNumber: Int,
        imageSize: (columns: Int, rows: Int)? = nil
    ) -> DataSet {
        // Everything shared is written by the builder that owns it.
        var dataSet = GrayscalePresentationStateBuilder().buildDataSet(
            from: state,
            patient: patient,
            seriesInstanceUID: seriesInstanceUID,
            seriesNumber: seriesNumber,
            imageSize: imageSize)

        // MARK: SOP Common — this is a different SOP class.
        dataSet.setString(Self.sopClassUID, for: .sopClassUID, vr: .UI)

        // MARK: Presentation State Shutter (C.11.12)
        //
        // Table C.11.12-1: Shutter Presentation Color CIELab Value (0018,1624)
        // is required with a shutter in every class but GSPS — this one included.
        GrayscalePresentationStateBuilder.applyShutterPresentationColor(
            state.shutterPresentationColor, to: &dataSet)

        // MARK: Presentation LUT, translated rather than dropped.
        //
        // The Softcopy Presentation LUT module is not part of this IOD, so the
        // shape the grayscale builder wrote comes out. INVERSE is preserved by
        // reversing the table below — same picture, legal spelling.
        let inverted = state.presentationLUT == .inverse
        dataSet[.presentationLUTShape] = nil

        // MARK: Palette Color Lookup Table module (C.7.9), the point of it all.
        //
        // PS3.4 N.2 (Figure N.2-1) applies the VOI LUT first and then scales its
        // full output range onto the palette's whole input range (N.2.4.2 says so
        // for the same stage in blending), so the table carries the palette's
        // ramp evenly and the window is written once, as VOI. Baking the window
        // into the table as well doubled the windowing in a conforming viewer.
        // Weasis indexes the table with raw stored pixels before any VOI; that
        // is a known interoperability limitation of that viewer, not encoded
        // around here.
        Self.applyPaletteColorLUT(
            palette, inverted: inverted, domain: pixelDomain, window: nil,
            to: &dataSet)

        // MARK: ICC Profile module (C.11.15) — mandatory in this IOD.
        //
        // The fixed sRGB profile: it is the space the palettes are defined in,
        // and being byte-stable it keeps two saves of the same view identical.
        dataSet[.iccProfile] = DataElement(
            tag: .iccProfile, vr: .OB,
            length: UInt32(SRGBICCProfileWriter.profileData.count),
            valueData: SRGBICCProfileWriter.profileData)
        dataSet.setString(SRGBICCProfileWriter.colorSpace, for: .colorSpace, vr: .CS)

        return dataSet
    }

    // MARK: - Palette module

    /// The stored-pixel range of the image a palette table must cover.
    public struct PixelDomain: Sendable, Equatable {

        /// Bits Stored (0028,0101) of the image. Clamped to 8...16.
        public let bitsStored: Int

        /// Whether Pixel Representation (0028,0103) is 1 — two's-complement
        /// stored pixels, whose smallest value is negative.
        public let isSigned: Bool

        /// Rescale Slope and Intercept (0028,1053/1052) of the image — what
        /// converts the state's window, which C.11.8 keeps in rescaled units,
        /// back into the stored-value domain the palette table is indexed by.
        public let rescaleSlope: Double
        public let rescaleIntercept: Double

        public init(
            bitsStored: Int, isSigned: Bool,
            rescaleSlope: Double = 1, rescaleIntercept: Double = 0
        ) {
            self.bitsStored = min(16, max(8, bitsStored))
            self.isSigned = isSigned
            self.rescaleSlope = rescaleSlope == 0 ? 1 : rescaleSlope
            self.rescaleIntercept = rescaleIntercept
        }

        /// How many entries the table needs: one per possible stored value.
        var entryCount: Int { 1 << bitsStored }

        /// The smallest stored value — what the descriptor's second value
        /// must name, or a signed image indexes the table from its middle.
        var firstMappedValue: Int { isSigned ? -(1 << (bitsStored - 1)) : 0 }
    }

    private static func applyPaletteColorLUT(
        _ palette: PseudoColorPalette,
        inverted: Bool,
        domain: PixelDomain?,
        window: (center: Double, width: Double)?,
        to dataSet: inout DataSet
    ) {
        // The table is sized to the image, not to the palette: the Palette
        // Color LUT is indexed by pixel value, so it must have an entry for
        // every value the image can store. With no domain given, the 8-bit
        // shape `(256, 0, 8)` of PS3.6 Annex B is what goes out — which is
        // also exactly what an 8-bit image resolves to.
        let entryCount = domain?.entryCount ?? PseudoColorPalette.entryCount
        let firstMapped = domain?.firstMappedValue ?? 0

        // Descriptor: entries, first mapped value, bits per entry. The first
        // value is written modulo 2^16 — the standard spells 65536 entries as
        // 0 — and the second as two's complement, the encoding a signed
        // descriptor (VR SS) carries.
        let descriptorValues = [entryCount & 0xFFFF, firstMapped & 0xFFFF, 8]
        var descriptor = Data()
        for value in descriptorValues {
            descriptor.append(UInt8(value & 0xFF))
            descriptor.append(UInt8((value >> 8) & 0xFF))
        }
        // US for unsigned images, SS for signed — PS3.3 C.7.6.3.1.5 keys the
        // descriptor's VR to Pixel Representation, and a reader that honours
        // that is the only kind that reads a negative first value back.
        let descriptorVR: VR = (domain?.isSigned ?? false) ? .SS : .US
        for tag: Tag in [.redPaletteColorLookupTableDescriptor,
                         .greenPaletteColorLookupTableDescriptor,
                         .bluePaletteColorLookupTableDescriptor] {
            dataSet[tag] = DataElement(
                tag: tag, vr: descriptorVR,
                length: UInt32(descriptor.count), valueData: descriptor)
        }

        var entries = palette.entries()
        if inverted { entries.reverse() }

        // With a domain and a window, the table is *baked*: stored values
        // below the window get the palette's first colour, values above it
        // the last, and the window itself carries the full ramp — which is
        // exactly the picture the reader was looking at. Without a window (or
        // without a domain to state it in), entries are block-resampled over
        // the whole range: entry i is palette entry i * 256 / N.
        //
        // One byte per entry — the packed form for 8-bit entries (PS3.3
        // C.7.6.3.1.5), and the form `PaletteColorLUT.parseLUTData` reads
        // back byte-for-byte. Counts are even, so OW needs no padding.
        let scale = entryCount / PseudoColorPalette.entryCount
        var paletteIndexOf: (Int) -> Int = { $0 / scale }
        var baked = false
        if let window, let domain {
            // The window arrives in rescaled units (C.11.8); the table is
            // indexed by stored values. Slope and intercept undo the rescale.
            let slope = domain.rescaleSlope
            let lowStored =
                ((window.center - window.width / 2) - domain.rescaleIntercept) / slope
            let widthStored = window.width / abs(slope)
            if widthStored > 0 {
                baked = true
                let first = Double(domain.firstMappedValue)
                paletteIndexOf = { index in
                    let stored = first + Double(index)
                    let t = (stored - lowStored) / widthStored
                    return t <= 0 ? 0 : (t >= 1 ? 255 : Int((t * 255).rounded()))
                }
            }
        }
        func channel(_ component: KeyPath<
            (red: UInt8, green: UInt8, blue: UInt8), UInt8>) -> Data {
            var bytes = Data(capacity: entryCount)
            for index in 0..<entryCount {
                bytes.append(entries[paletteIndexOf(index)][keyPath: component])
            }
            return bytes
        }
        let channels: [(Tag, Data)] = [
            (.redPaletteColorLookupTableData, channel(\.red)),
            (.greenPaletteColorLookupTableData, channel(\.green)),
            (.bluePaletteColorLookupTableData, channel(\.blue)),
        ]
        for (tag, bytes) in channels {
            dataSet[tag] = DataElement(
                tag: tag, vr: .OW, length: UInt32(bytes.count), valueData: bytes)
        }

        // The standard's own name for the table, when the table going out is
        // the very one the name means: the 256-entry Annex B shape,
        // uninverted. A resampled or reversed table renders the same reading
        // but is a different table, and naming it would invite a viewer to
        // substitute the named one — undoing the resampling this module
        // exists for.
        if !inverted, !baked, scale == 1, let uid = palette.wellKnownSOPInstanceUID {
            dataSet.setString(uid, for: .paletteColorLookupTableUID, vr: .UI)
        }
    }
}
