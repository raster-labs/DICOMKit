// PseudoColorPalette.swift
// DICOMCore
//
// DICOM Core — pseudo-colour palettes, as one source of truth.
//
// A pseudo-colour palette turns a windowed monochrome frame into colour. It is
// a *display* choice, not a property of the image: the stored pixels are
// untouched, and the same frame under two palettes is the same measurement seen
// two ways.
//
// Why this type lives in DICOMCore rather than beside the viewer that first
// needed it: the palette has to mean the same thing in four places that cannot
// see each other's code — the CPU renderer, the Metal renderer, the print
// preprocessor, and the picker the reader chooses from. Four separate
// implementations of "Hot Iron" is four different pictures called by one name,
// which on film is a clinical problem rather than an aesthetic one.
//
// Provenance is deliberate and is recorded per palette (see ``Provenance``).
// Palettes the DICOM standard defines are transcribed from PS3.6 Annex B and
// carry the standard's own Content Label and SOP Instance UID, so a film can
// say exactly which normative palette it was printed with. Everything else is
// computed here from published mathematics or from its own definition. No ramp
// data is taken from another viewer's implementation.

import Foundation

// MARK: - Palette

/// A pseudo-colour palette: 256 RGB entries indexed by a windowed grey level.
///
/// The palette is the *what*; ``PseudoColorPalette/lut()`` produces the DICOM
/// ``PaletteColorLUT`` that every renderer and the print path already consume,
/// so adding a palette never means teaching a renderer a new concept.
public enum PseudoColorPalette: String, Sendable, Equatable, Hashable, CaseIterable, Codable {

    // MARK: DICOM PS3.6 Annex B — Well-Known Color Palettes
    //
    // Raw values are the standard's Content Label (0070,0080) exactly, so the
    // stored form of a print job is itself normative.

    case hotIron        = "HOT_IRON"
    case pet            = "PET"
    case hotMetalBlue   = "HOT_METAL_BLUE"
    case petTwentyStep  = "PET_20_STEP"
    case spring         = "SPRING"
    case summer         = "SUMMER"
    case fall           = "FALL"
    case winter         = "WINTER"

    // MARK: Perceptually uniform (CC0 / public domain)

    case viridis        = "VIRIDIS"
    case inferno        = "INFERNO"
    case magma          = "MAGMA"
    case plasma         = "PLASMA"

    // MARK: Spectrum sweeps (defined by formula)

    case jet            = "JET"
    case rainbow        = "RAINBOW"
    case grayRainbow    = "GRAY_RAINBOW"
    case spectrum       = "SPECTRUM"

    // MARK: Single-hue and flow

    case hotGreen       = "HOT_GREEN"
    case hueOne         = "HUE_1"
    case hueTwo         = "HUE_2"
    case flow           = "FLOW"
    case ratio          = "RATIO"

    // MARK: Grey

    /// No pseudo-colour: the identity ramp. The frame prints as grey.
    case grayscale      = "GRAYSCALE"

    /// Grey, reversed.
    ///
    /// Offered because readers expect to find it in this list, but note the
    /// print path already inverts through ``ViewerPresentation/invert`` and, on
    /// the wire, through Polarity (2020,0020) = REVERSE — which a film printer
    /// applies itself, without forcing the film to colour. Prefer those; this
    /// entry exists so that choosing it from the palette list does the
    /// unsurprising thing rather than nothing.
    case inverseGrayscale = "GRAYSCALE_INVERSE"

    /// The number of entries every palette here defines.
    ///
    /// 256 is not an arbitrary choice: PS3.6 Annex B gives every well-known
    /// palette the descriptor `(256, 0, 8)`, and matching it means the standard
    /// palettes are transcribed rather than resampled.
    public static let entryCount = 256
}

// MARK: - Grouping

extension PseudoColorPalette {

    /// The heading a palette is offered under.
    ///
    /// Grouping is how the list stays honest at 20-odd entries: the reader can
    /// see at a glance which palettes are the standard's (and so mean the same
    /// thing on any conforming system) and which are ours.
    public enum Group: String, Sendable, CaseIterable, Codable {
        case dicomStandard
        case perceptuallyUniform
        case spectrum
        case singleHue
        case gray

        /// The heading as shown to the reader.
        public var title: String {
            switch self {
            case .dicomStandard:       return "DICOM Standard"
            case .perceptuallyUniform: return "Perceptually Uniform"
            case .spectrum:            return "Spectrum"
            case .singleHue:           return "Single Hue & Flow"
            case .gray:                return "Grayscale"
            }
        }

        /// A one-line note for the heading, where one earns its place.
        public var note: String? {
            switch self {
            case .dicomStandard:
                return "Defined by DICOM PS3.6 Annex B — identical on any conforming system."
            case .perceptuallyUniform:
                return "Equal steps in the data look like equal steps to the eye."
            case .spectrum:
                return "Familiar, but colour order does not track magnitude — read values, not hues."
            case .singleHue, .gray:
                return nil
            }
        }
    }

    /// The group this palette is offered under.
    public var group: Group {
        switch self {
        case .hotIron, .pet, .hotMetalBlue, .petTwentyStep,
             .spring, .summer, .fall, .winter:
            return .dicomStandard
        case .viridis, .inferno, .magma, .plasma:
            return .perceptuallyUniform
        case .jet, .rainbow, .grayRainbow, .spectrum:
            return .spectrum
        case .hotGreen, .hueOne, .hueTwo, .flow, .ratio:
            return .singleHue
        case .grayscale, .inverseGrayscale:
            return .gray
        }
    }

    /// Every palette in the order it is offered, grouped.
    ///
    /// Order within a group is deliberate: the DICOM group leads with the four
    /// palettes that have real clinical demand (NM/PET), and the four fMRI
    /// activation palettes follow.
    public static let catalog: [(group: Group, palettes: [PseudoColorPalette])] = [
        (.gray,                [.grayscale, .inverseGrayscale]),
        (.dicomStandard,       [.hotIron, .pet, .hotMetalBlue, .petTwentyStep,
                                .spring, .summer, .fall, .winter]),
        (.perceptuallyUniform, [.viridis, .inferno, .magma, .plasma]),
        (.spectrum,            [.jet, .rainbow, .grayRainbow, .spectrum]),
        (.singleHue,           [.hotGreen, .hueOne, .hueTwo, .flow, .ratio])
    ]
}

// MARK: - Identity

extension PseudoColorPalette {

    /// Where a palette's colours come from — recorded, not assumed.
    public enum Provenance: Sendable, Equatable {
        /// Transcribed from DICOM PS3.6 Annex B, with the standard's own
        /// identity. A film printed with one of these can name it normatively.
        case dicomWellKnown(label: String, uid: String)
        /// Computed here from a published, freely reusable definition.
        case publicDomain(source: String)
        /// Computed here from its own definition.
        case computed
    }

    /// This palette's provenance.
    ///
    /// NEMA-verified: 2026a, checked 2026-09-24 — text-diffed: the 8 labels and UIDs match PS3.6 2026a
    /// Table B.1-1 exactly.
    public var provenance: Provenance {
        switch self {
        case .hotIron:
            return .dicomWellKnown(label: "HOT_IRON", uid: "1.2.840.10008.1.5.1")
        case .pet:
            return .dicomWellKnown(label: "PET", uid: "1.2.840.10008.1.5.2")
        case .hotMetalBlue:
            return .dicomWellKnown(label: "HOT_METAL_BLUE", uid: "1.2.840.10008.1.5.3")
        case .petTwentyStep:
            return .dicomWellKnown(label: "PET_20_STEP", uid: "1.2.840.10008.1.5.4")
        case .spring:
            return .dicomWellKnown(label: "SPRING", uid: "1.2.840.10008.1.5.5")
        case .summer:
            return .dicomWellKnown(label: "SUMMER", uid: "1.2.840.10008.1.5.6")
        case .fall:
            return .dicomWellKnown(label: "FALL", uid: "1.2.840.10008.1.5.7")
        case .winter:
            return .dicomWellKnown(label: "WINTER", uid: "1.2.840.10008.1.5.8")
        case .viridis, .inferno, .magma, .plasma:
            return .publicDomain(source: "matplotlib (CC0 public domain)")
        default:
            return .computed
        }
    }

    /// The Well-known Color Palette SOP Instance UID, for the eight the standard
    /// defines. `nil` for every palette of our own.
    ///
    /// Print Management has nowhere to *send* this — PS3.3 Table C.13-5 allows
    /// only `RGB` in a Basic Color Image Sequence, so the palette is baked into
    /// the pixels and the printer never learns which one was used. It is
    /// recorded in the print audit trail instead, which is the only place the
    /// choice survives.
    public var wellKnownSOPInstanceUID: String? {
        if case let .dicomWellKnown(_, uid) = provenance { return uid }
        return nil
    }

    /// The DICOM Content Label (0070,0080), for the eight the standard defines.
    public var contentLabel: String? {
        if case let .dicomWellKnown(label, _) = provenance { return label }
        return nil
    }

    /// The name shown to the reader.
    ///
    /// For the standard's palettes this is its Content Description (0070,0081)
    /// verbatim — "Hot Iron", not "HotIron" or "Hot iron" — so what the reader
    /// picks matches what the standard calls it.
    public var displayName: String {
        switch self {
        case .hotIron:          return "Hot Iron"
        case .pet:              return "PET"
        case .hotMetalBlue:     return "Hot Metal Blue"
        case .petTwentyStep:    return "PET 20 Step"
        case .spring:           return "Spring"
        case .summer:           return "Summer"
        case .fall:             return "Fall"
        case .winter:           return "Winter"
        case .viridis:          return "Viridis"
        case .inferno:          return "Inferno"
        case .magma:            return "Magma"
        case .plasma:           return "Plasma"
        case .jet:              return "Jet"
        case .rainbow:          return "Rainbow"
        case .grayRainbow:      return "Gray Rainbow"
        case .spectrum:         return "Spectrum"
        case .hotGreen:         return "Hot Green"
        case .hueOne:           return "Hue 1"
        case .hueTwo:           return "Hue 2"
        case .flow:             return "Flow"
        case .ratio:            return "Ratio"
        case .grayscale:        return "Grayscale"
        case .inverseGrayscale: return "Inverse Grayscale"
        }
    }

    /// Whether this palette leaves the frame grey.
    ///
    /// The one question the print path actually needs answered: a grey palette
    /// must not widen a monochrome film to RGB, because doing so would cost it
    /// the deep-grayscale bit depth and the density curve for no colour at all.
    /// See `PrintImagePreparer.preparationColorMode`.
    public var isGrayscale: Bool {
        self == .grayscale || self == .inverseGrayscale
    }
}

// MARK: - Table

extension PseudoColorPalette {

    /// This palette as 256 RGB triples, in index order.
    ///
    /// The standard's palettes come from their transcribed tables; the rest are
    /// evaluated from the ramp definitions below.
    public func entries() -> [(red: UInt8, green: UInt8, blue: UInt8)] {
        if let table = DICOMWellKnownPalettes.table(for: self) { return table }
        if let table = PerceptualColormaps.table(for: self) { return table }
        return (0..<Self.entryCount).map { index in
            let t = Double(index) / Double(Self.entryCount - 1)
            let (r, g, b) = color(at: t)
            return (Self.byte(r), Self.byte(g), Self.byte(b))
        }
    }

    /// This palette as a DICOM ``PaletteColorLUT``.
    ///
    /// Descriptor `(256, 0, 8)` matches PS3.6 Annex B. Entries are stored in the
    /// high byte, which is what ``PaletteColorLUT`` reads back — see its
    /// `normalize`, and PS3.3 C.7.6.3.1.5.
    public func lut() -> PaletteColorLUT {
        let descriptor = PaletteColorLUT.Descriptor(
            numberOfEntries: Self.entryCount,
            firstMappedValue: 0,
            bitsPerEntry: 8
        )
        var red: [UInt16] = []
        var green: [UInt16] = []
        var blue: [UInt16] = []
        red.reserveCapacity(Self.entryCount)
        green.reserveCapacity(Self.entryCount)
        blue.reserveCapacity(Self.entryCount)
        for entry in entries() {
            red.append(UInt16(entry.red) << 8)
            green.append(UInt16(entry.green) << 8)
            blue.append(UInt16(entry.blue) << 8)
        }
        return PaletteColorLUT(
            redDescriptor: descriptor,
            greenDescriptor: descriptor,
            blueDescriptor: descriptor,
            redLUT: red,
            greenLUT: green,
            blueLUT: blue
        )
    }

    /// Maps a normalised grey level to colour.
    ///
    /// `t` is the *windowed* level in [0, 1] — the window has already been
    /// applied, so this is purely the colour assignment.
    func color(at t: Double) -> (Double, Double, Double) {
        let t = min(max(t, 0), 1)
        switch self {
        case .grayscale:
            return (t, t, t)
        case .inverseGrayscale:
            return (1 - t, 1 - t, 1 - t)

        case .viridis, .inferno, .magma, .plasma:
            // Transcribed tables; `entries()` never reaches here.
            return (t, t, t)

        case .jet:
            // The classic blue→cyan→yellow→red sweep, dark at both ends.
            return Self.interpolate(t, [
                (0.000, (0.0, 0.0, 0.5)),
                (0.125, (0.0, 0.0, 1.0)),
                (0.375, (0.0, 1.0, 1.0)),
                (0.625, (1.0, 1.0, 0.0)),
                (0.875, (1.0, 0.0, 0.0)),
                (1.000, (0.5, 0.0, 0.0))
            ])

        case .rainbow:
            // A plain hue sweep from blue to red: hue 240° → 0°.
            return Self.hsv(hue: 240 * (1 - t), saturation: 1, value: 1)

        case .grayRainbow:
            // Grey through the low half, hue through the top half — the dark
            // end stays readable as anatomy while the bright end carries colour.
            if t < 0.5 {
                let g = t * 2 * 0.75
                return (g, g, g)
            }
            return Self.hsv(hue: 240 * (1 - (t - 0.5) * 2), saturation: 1, value: 1)

        case .spectrum:
            // The full visible sweep including magenta: hue 300° → 0°.
            return Self.hsv(hue: 300 * (1 - t), saturation: 1, value: 1)

        case .hotGreen:
            // The heat ramp in green: black → green → pale green → white.
            return Self.interpolate(t, [
                (0.00, (0.0, 0.0, 0.0)),
                (0.40, (0.0, 0.6, 0.0)),
                (0.75, (0.4, 1.0, 0.4)),
                (1.00, (1.0, 1.0, 1.0))
            ])

        case .hueOne:
            // A narrow, cool hue band: cyan → blue → violet.
            return Self.hsv(hue: 180 + 120 * t, saturation: 1, value: 1)

        case .hueTwo:
            // A narrow, warm hue band: yellow → orange → red.
            return Self.hsv(hue: 60 * (1 - t), saturation: 1, value: 1)

        case .flow:
            // Diverging, for signed quantities: blue → white → red, with white
            // at the midpoint so zero reads as neutral.
            if t < 0.5 {
                let u = t * 2
                return (u, u, 1.0)
            }
            let u = (t - 0.5) * 2
            return (1.0, 1.0 - u, 1.0 - u)

        case .ratio:
            // Also diverging but through black, so unity reads as dark rather
            // than bright: cyan → black → yellow.
            if t < 0.5 {
                let u = 1 - t * 2
                return (0.0, u, u)
            }
            let u = (t - 0.5) * 2
            return (u, u, 0.0)

        case .hotIron, .pet, .hotMetalBlue, .petTwentyStep,
             .spring, .summer, .fall, .winter:
            // Transcribed tables; `entries()` never reaches here. Grey is the
            // safe answer if a table is ever missing, since a wrong colour on
            // film is worse than no colour.
            return (t, t, t)
        }
    }

    // MARK: Ramp helpers

    /// Piecewise-linear interpolation between anchor stops.
    static func interpolate(
        _ t: Double,
        _ stops: [(Double, (Double, Double, Double))]
    ) -> (Double, Double, Double) {
        guard let first = stops.first else { return (t, t, t) }
        if t <= first.0 { return first.1 }
        guard let last = stops.last else { return (t, t, t) }
        if t >= last.0 { return last.1 }
        for index in 1..<stops.count {
            let (upperT, upper) = stops[index]
            guard t <= upperT else { continue }
            let (lowerT, lower) = stops[index - 1]
            let span = upperT - lowerT
            let f = span > 0 ? (t - lowerT) / span : 0
            return (
                lower.0 + (upper.0 - lower.0) * f,
                lower.1 + (upper.1 - lower.1) * f,
                lower.2 + (upper.2 - lower.2) * f
            )
        }
        return last.1
    }

    /// HSV → RGB. Hue in degrees, saturation and value in [0, 1].
    static func hsv(hue: Double, saturation: Double, value: Double)
        -> (Double, Double, Double) {
        let wrapped = hue.truncatingRemainder(dividingBy: 360)
        let degrees = wrapped < 0 ? wrapped + 360 : wrapped
        let c = value * saturation
        let x = c * (1 - abs((degrees / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = value - c
        let (r, g, b): (Double, Double, Double)
        switch degrees {
        case ..<60:   (r, g, b) = (c, x, 0)
        case ..<120:  (r, g, b) = (x, c, 0)
        case ..<180:  (r, g, b) = (0, c, x)
        case ..<240:  (r, g, b) = (0, x, c)
        case ..<300:  (r, g, b) = (x, 0, c)
        default:      (r, g, b) = (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }

    /// Rounds a [0, 1] component to a byte, clamping.
    static func byte(_ value: Double) -> UInt8 {
        guard value.isFinite else { return 0 }
        return UInt8(min(max((value * 255).rounded(), 0), 255))
    }
}

// MARK: - Recognition

extension PseudoColorPalette {

    /// What a stored colour table turned out to be, when it is one of ours.
    ///
    /// `inverted` is true when the table is one of our palettes written
    /// back-to-front — the form a pseudo-colour presentation state takes when
    /// the view it records was being read inverted, since that IOD has no
    /// Presentation LUT to say INVERSE in and the reversal is baked into the
    /// entries instead.
    public struct Match: Sendable, Equatable {
        public let palette: PseudoColorPalette
        public let inverted: Bool

        public init(palette: PseudoColorPalette, inverted: Bool) {
            self.palette = palette
            self.inverted = inverted
        }
    }

    /// Recognises a parsed Palette Color LUT as one of this catalogue's
    /// palettes, if it is one.
    ///
    /// This is how a presentation state written by us comes back as the palette
    /// the reader chose rather than as an anonymous table: the file carries the
    /// 256 RGB entries, and this walks the catalogue comparing them. Entries are
    /// compared through the same high-byte normalisation ``PaletteColorLUT``
    /// reads with, so a table that renders identically matches regardless of
    /// whether it was stored as bytes or 16-bit words.
    ///
    /// `nil` for a foreign table — one some other viewer computed — which is a
    /// correct answer, not a failure: such a state still parses, it just cannot
    /// be named.
    public static func matching(_ lut: PaletteColorLUT) -> Match? {
        // Our tables are the 256 palette entries, possibly resampled by equal
        // blocks to cover a deeper image's stored range (the builder writes
        // 2^Bits Stored entries). So a candidate is ours only when its size is
        // a whole multiple of 256 — anything else is foreign by shape.
        let count = lut.redLUT.count
        guard count >= Self.entryCount,
              lut.greenLUT.count == count,
              lut.blueLUT.count == count else { return nil }

        // Normalise once: the high byte is the significant one for both 8- and
        // 16-bit storage (PS3.3 C.7.6.3.1.5), and it is what rendering uses.
        let red = lut.redLUT.map { UInt8($0 >> 8) }
        let green = lut.greenLUT.map { UInt8($0 >> 8) }
        let blue = lut.blueLUT.map { UInt8($0 >> 8) }

        // Two passes, forwards before reversed — over the whole catalogue, not
        // per palette. The catalogue contains its own mirror image once:
        // `inverseGrayscale` *is* `grayscale` reversed, so an interleaved walk
        // would report the inverse ramp as "grayscale, inverted" instead of
        // by its name. A forward match is always the honest reading when one
        // exists.
        if count % Self.entryCount == 0 {
            let scale = count / Self.entryCount
            for palette in Self.allCases {
                if matches(palette.entries(), red: red, green: green, blue: blue,
                           scale: scale) {
                    return Match(palette: palette, inverted: false)
                }
            }
            for palette in Self.allCases {
                if matches(Array(palette.entries().reversed()),
                           red: red, green: green, blue: blue, scale: scale) {
                    return Match(palette: palette, inverted: true)
                }
            }
        }

        // A window-baked table — flat below the window, the ramp across it,
        // flat above — is not a block-resample of anything, but its colours
        // are still the palette's, in the palette's order. The walk below
        // names it without knowing the window that shaped it. Only for
        // tables deeper than the palette: at exactly 256 entries a walk
        // cannot tell a bake from a near-miss foreign table, and the exact
        // block comparison above is the only honest reading.
        guard count > Self.entryCount else { return nil }
        for palette in Self.allCases {
            if rampMatches(palette.entries(), red: red, green: green, blue: blue) {
                return Match(palette: palette, inverted: false)
            }
        }
        for palette in Self.allCases {
            if rampMatches(Array(palette.entries().reversed()),
                           red: red, green: green, blue: blue) {
                return Match(palette: palette, inverted: true)
            }
        }
        return nil
    }

    /// Whether the candidate table walks the palette monotonically: every
    /// entry is a palette colour, consecutive entries only ever move forward
    /// through the palette, and enough distinct colours appear to make the
    /// walk meaningful. This is the shape a window bake produces for *any*
    /// window, which is what lets recognition work without knowing the
    /// window; the strictness — no colour outside the palette, no going
    /// backwards — is what keeps a foreign ramp from being misnamed.
    private static func rampMatches(
        _ entries: [(red: UInt8, green: UInt8, blue: UInt8)],
        red: [UInt8], green: [UInt8], blue: [UInt8]
    ) -> Bool {
        func equal(_ index: Int, _ entry: (red: UInt8, green: UInt8, blue: UInt8))
        -> Bool {
            red[index] == entry.red
                && green[index] == entry.green
                && blue[index] == entry.blue
        }
        guard var position = entries.indices.first(where: { equal(0, entries[$0]) })
        else { return false }
        var distinctSteps = 1
        for index in 1..<red.count where !equal(index, entries[position]) {
            var next = position + 1
            while next < entries.count && !equal(index, entries[next]) { next += 1 }
            guard next < entries.count else { return false }
            position = next
            distinctSteps += 1
        }
        // A meaningful ramp shows a real slice of the palette; two or three
        // colours could be anyone's.
        return distinctSteps >= 16
    }

    /// Whether the candidate table is exactly the palette resampled by equal
    /// blocks: every entry `i` of the candidate must equal palette entry
    /// `i / scale`. Comparing all entries — not one sample per block — is what
    /// keeps a foreign table that merely agrees at the sampled points from
    /// being misnamed as ours.
    private static func matches(
        _ entries: [(red: UInt8, green: UInt8, blue: UInt8)],
        red: [UInt8], green: [UInt8], blue: [UInt8], scale: Int
    ) -> Bool {
        for index in red.indices {
            let entry = entries[index / scale]
            if red[index] != entry.red
                || green[index] != entry.green
                || blue[index] != entry.blue { return false }
        }
        return true
    }
}
