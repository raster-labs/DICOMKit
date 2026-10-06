// NEMA-verified: 2026a, checked 2026-10-06 — FilmDestination(catalogToken:) accepts any BIN_i per PS3.3 2026a Table C.13-1 (numbered from 1, no maximum, no leading zeros; D242); Film Size ID, Film Orientation, Print Priority, Medium Type, Film Destination, Magnification Type, Polarity, Trim, Presentation LUT Shape and Border/Empty Image Density values offered text-diffed against PS3.3 2026a Tables C.13-1, C.13-3, C.13-5, C.11-4 via the DICOMNetwork raw values (Scripts/diff_printkit.py: all match); bit depths 8/12 per Table C.13-5 (citation corrected from C.13-3, D23); all five Medium Type terms offered, MAMMO CLEAR FILM / MAMMO BLUE FILM since P-MAMMO
// PrintOptionCatalog.swift
// DICOMPrintKit
//
// The single source of truth for the selectable values of every print option:
// the layouts, presets, film sizes, and enumerations both the dicom-print CLI
// and the DICOMStudio print UI offer. UI pickers derive from these tables so a
// value can never exist in one surface and not the other.

import Foundation
import DICOMNetwork

// MARK: - Layout

/// A selectable rows × columns film layout.
///
/// Every grid from 1×1 to 4×4, plus the 4×5 film sheet — the same list the
/// viewer hangs images in, deliberately: film order is viewer order, and a grid
/// a reader can arrange on screen but not print would break that promise the
/// moment they tried to print it.
public enum PrintLayoutOption: String, CaseIterable, Sendable, Identifiable, Codable {
    case layout1x1 = "1x1"
    case layout1x2 = "1x2"
    case layout1x3 = "1x3"
    case layout1x4 = "1x4"
    case layout2x1 = "2x1"
    case layout2x2 = "2x2"
    case layout2x3 = "2x3"
    case layout2x4 = "2x4"
    case layout3x1 = "3x1"
    case layout3x2 = "3x2"
    case layout3x3 = "3x3"
    case layout3x4 = "3x4"
    case layout4x1 = "4x1"
    case layout4x2 = "4x2"
    case layout4x3 = "4x3"
    case layout4x4 = "4x4"
    case layout4x5 = "4x5"

    public var id: String { rawValue }

    /// Rows and columns for this layout.
    public var layout: PrintLayout {
        switch self {
        case .layout1x1: return PrintLayout(rows: 1, columns: 1)
        case .layout1x2: return PrintLayout(rows: 1, columns: 2)
        case .layout1x3: return PrintLayout(rows: 1, columns: 3)
        case .layout1x4: return PrintLayout(rows: 1, columns: 4)
        case .layout2x1: return PrintLayout(rows: 2, columns: 1)
        case .layout2x2: return PrintLayout(rows: 2, columns: 2)
        case .layout2x3: return PrintLayout(rows: 2, columns: 3)
        case .layout2x4: return PrintLayout(rows: 2, columns: 4)
        case .layout3x1: return PrintLayout(rows: 3, columns: 1)
        case .layout3x2: return PrintLayout(rows: 3, columns: 2)
        case .layout3x3: return PrintLayout(rows: 3, columns: 3)
        case .layout3x4: return PrintLayout(rows: 3, columns: 4)
        case .layout4x1: return PrintLayout(rows: 4, columns: 1)
        case .layout4x2: return PrintLayout(rows: 4, columns: 2)
        case .layout4x3: return PrintLayout(rows: 4, columns: 3)
        case .layout4x4: return PrintLayout(rows: 4, columns: 4)
        case .layout4x5: return PrintLayout(rows: 4, columns: 5)
    }
    }

    /// The Image Display Format (2010,0010) string this layout sends.
    public var imageDisplayFormat: String { layout.imageDisplayFormat }

    /// Cells on one film.
    public var cellCount: Int { layout.rows * layout.columns }

    /// Label for menus: "2×2 (4 images)".
    public var displayName: String {
        "\(layout.rows)×\(layout.columns) (\(cellCount) image\(cellCount == 1 ? "" : "s"))"
    }
}

// MARK: - Band layouts

/// A selectable band layout: one of the PS3.3 C.13.3 films whose rows — or
/// columns — hold different numbers of images.
///
/// `ROW\1,2` is one image over two; `COL\1,4,4` is one image beside two columns
/// of four. No rows × columns pair names either of them, which is why they are
/// carried as the Image Display Format itself rather than as a ``PrintLayout``.
/// The list is short and fixed on purpose: these are the arrangements a reader
/// asks for by name, and anything else is typed into the custom field.
public enum PrintBandLayout: String, CaseIterable, Sendable, Identifiable {
    case rowOneOverTwo    = "ROW\\1,2"
    case rowTwoOverThree  = "ROW\\2,3"
    case columnOneAndTwo  = "COL\\1,2"
    case columnOneAndThree = "COL\\1,3"
    case columnOneAndFour = "COL\\1,4"
    case columnOneAndTwoFours = "COL\\1,4,4"
    case columnTwoAndTwoFours = "COL\\2,4,4"

    public var id: String { rawValue }

    /// The Image Display Format (2010,0010) this layout sends — the raw value.
    public var imageDisplayFormat: String { rawValue }

    /// The parsed format, for laying the cells out and counting them.
    public var displayFormat: PrintImageDisplayFormat {
        PrintImageDisplayFormat.parse(rawValue)
    }

    /// Cells on one film.
    public var cellCount: Int { displayFormat.imageBoxCount }

    /// Label for menus: what the film puts where, in words.
    public var displayName: String {
        switch self {
        case .rowOneOverTwo:        return "1 over 2"
        case .rowTwoOverThree:      return "2 over 3"
        case .columnOneAndTwo:      return "1 beside 2"
        case .columnOneAndThree:    return "1 beside 3"
        case .columnOneAndFour:     return "1 beside 4"
        case .columnOneAndTwoFours: return "1 beside 4 and 4"
        case .columnTwoAndTwoFours: return "2 beside 4 and 4"
        }
    }
}

// MARK: - Template presets

/// A layout preset that also fixes film size and orientation.
public enum PrintTemplatePreset: String, CaseIterable, Sendable, Identifiable, Codable {
    case single
    case comparison
    case grid
    case multiPhase = "multi-phase"

    public var id: String { rawValue }

    /// The built-in `PrintTemplate` this preset maps to.
    public var template: PrintTemplate {
        switch self {
        case .single:     return SingleImageTemplate()
        case .comparison: return ComparisonTemplate()
        case .grid:       return GridTemplate(rows: 2, columns: 2)
        case .multiPhase: return MultiPhaseTemplate(rows: 2, columns: 3)
        }
    }

    /// The image layout (rows × columns) for this preset.
    public var layout: PrintLayout {
        switch self {
        case .single:     return PrintLayout(rows: 1, columns: 1)
        case .comparison: return PrintLayout(rows: 1, columns: 2)
        case .grid:       return PrintLayout(rows: 2, columns: 2)
        case .multiPhase: return PrintLayout(rows: 2, columns: 3)
        }
    }

    /// The film size this preset fixes.
    public var filmSize: FilmSize { template.filmSize }

    /// The orientation this preset fixes.
    public var filmOrientation: FilmOrientation { template.filmOrientation }

    /// Label for menus.
    public var displayName: String {
        switch self {
        case .single:     return "Single image"
        case .comparison: return "Comparison (1×2)"
        case .grid:       return "Grid (2×2)"
        case .multiPhase: return "Multi-phase (2×3)"
        }
    }
}

// MARK: - Catalog

/// Selectable values, with labels, for every print option.
public enum PrintOptionCatalog {

    /// Film sizes offered, in the CLI's `--film-size` order.
    public static let filmSizes: [(value: FilmSize, cliToken: String, label: String)] = [
        (.size8InX10In,   "8x10",    "8 × 10 in"),
        (.size8_5InX11In, "8.5x11",  "8.5 × 11 in"),
        (.size10InX12In,  "10x12",   "10 × 12 in"),
        (.size10InX14In,  "10x14",   "10 × 14 in"),
        (.size11InX14In,  "11x14",   "11 × 14 in"),
        (.size11InX17In,  "11x17",   "11 × 17 in"),
        (.size14InX14In,  "14x14",   "14 × 14 in"),
        (.size14InX17In,  "14x17",   "14 × 17 in"),
        (.size24CmX24Cm,  "24x24cm", "24 × 24 cm"),
        (.size24CmX30Cm,  "24x30cm", "24 × 30 cm"),
        (.a4,             "a4",      "A4"),
        (.a3,             "a3",      "A3")
    ]

    /// Film orientations.
    public static let orientations: [(value: FilmOrientation, cliToken: String, label: String)] = [
        (.portrait,  "portrait",  "Portrait"),
        (.landscape, "landscape", "Landscape")
    ]

    /// Print priorities.
    public static let priorities: [(value: PrintPriority, cliToken: String, label: String)] = [
        (.low,    "low",    "Low"),
        (.medium, "medium", "Medium"),
        (.high,   "high",   "High")
    ]

    /// Medium types — every Defined Term of PS3.3 Table C.13-1.
    public static let mediumTypes: [(value: MediumType, cliToken: String, label: String)] = [
        (.paper,          "paper",            "Paper"),
        (.clearFilm,      "clear-film",       "Clear film"),
        (.blueFilm,       "blue-film",        "Blue film"),
        (.mammoClearFilm, "mammo-clear-film", "Mammography clear film"),
        (.mammoBlueFilm,  "mammo-blue-film",  "Mammography blue film")
    ]

    /// Film destinations offered by the pickers: MAGAZINE, PROCESSOR and the first two
    /// sorter bins. PS3.3 2026a Table C.13-1 places no maximum on BIN_i, so these are
    /// defaults, not the whole vocabulary: any `bin-N` / `BIN_N` is resolved by
    /// ``FilmDestination/init(catalogToken:)`` (D242).
    public static let filmDestinations: [(value: FilmDestination, cliToken: String, label: String)] = [
        (.magazine,  "magazine",  "Magazine"),
        (.processor, "processor", "Processor"),
        (.bin(1),    "bin-1",     "Bin 1"),
        (.bin(2),    "bin-2",     "Bin 2")
    ]

    /// Magnification (interpolation) types.
    public static let magnificationTypes: [(value: MagnificationType, cliToken: String, label: String)] = [
        (.replicate,            "replicate", "Replicate"),
        (.bilinear,             "bilinear",  "Bilinear"),
        (.cubic,                "cubic",     "Cubic"),
        (MagnificationType.none, "none",     "None")
    ]

    /// Image polarities.
    public static let polarities: [(value: ImagePolarity, cliToken: String, label: String)] = [
        (.normal,  "normal",  "Normal"),
        (.reverse, "reverse", "Reverse")
    ]

    /// Trim options.
    public static let trimOptions: [(value: TrimOption, cliToken: String, label: String)] = [
        (TrimOption.no,  "no",  "No trim box"),
        (TrimOption.yes, "yes", "Trim box")
    ]

    /// Presentation LUT shapes (plus "none", represented by `nil`).
    ///
    /// Only Identity and LIN OD are Presentation LUT Shapes on the wire — PS3.3
    /// C.11.4 enumerates no others. "Inverse (rendered)" is offered because
    /// users want inverted film, and is realised by inverting the pixels, the
    /// same answer DCMTK gives with `dcmpsprt --inverse-plut`.
    public static let presentationLUTShapes: [(value: PresentationLUTShape, cliToken: String, label: String)] = [
        (.identity,               "identity", "Identity"),
        (.linearOpticalDensity,   "lin-od",   "Linear optical density (LIN OD)"),
        (.inverseRendered,        "inverse",  "Inverse (rendered into pixels)")
    ]

    /// Color modes.
    public static let colorModes: [(value: DICOMNetwork.PrintColorMode, cliToken: String, label: String)] = [
        (.grayscale, "grayscale", "Grayscale"),
        (.color,     "color",     "Color")
    ]

    /// Grayscale output bit depths the Basic Grayscale Image Box allows.
    ///
    /// Eight and twelve, and nothing else: PS3.3 Table C.13-5 (Image Box Pixel
    /// Presentation Module, Basic Grayscale Image Sequence) enumerates Bits
    /// Stored as 8 or 12. Sixteen *bits allocated* is legal and is how 12-bit
    /// film travels, but 16 bits *stored* is not a value the table lists, so it
    /// is not offered here. A request that still asks for it is clamped rather
    /// than refused — see `PrintImagePreparer.preparationBitDepth`.
    public static let bitDepths: [Int] = [8, 12]

    /// How a depth is described to the reader, since the trade-off is not
    /// obvious from the number alone.
    public static func bitDepthLabel(_ depth: Int) -> String {
        switch depth {
        case 8:  return "8-bit (widest printer support)"
        case 12: return "12-bit (deep grayscale — the printer must support it)"
        default: return "\(depth)-bit"
        }
    }

    /// Border / empty-image density values.
    public static let densities: [String] = ["BLACK", "WHITE"]

    // MARK: Token lookup

    /// Resolves a CLI film-size token ("14x17") to its `FilmSize`.
    public static func filmSize(forToken token: String) -> FilmSize? {
        filmSizes.first { $0.cliToken == token }?.value
    }

    /// The CLI token for a film size, for round-tripping UI state to a command line.
    public static func token(for filmSize: FilmSize) -> String? {
        filmSizes.first { $0.value == filmSize }?.cliToken
    }

    /// Human label for a film size.
    public static func label(for filmSize: FilmSize) -> String {
        filmSizes.first { $0.value == filmSize }?.label ?? filmSize.rawValue
    }
}

// MARK: - Film Destination tokens (D242)

extension FilmDestination {
    /// Resolves a film-destination token, case-insensitively and ignoring surrounding
    /// spaces: the catalog tokens `magazine` / `processor`, `bin-N` for any sorter bin
    /// N, or a Defined Term MAGAZINE / PROCESSOR / BIN_N. PS3.3 2026a Table C.13-1:
    /// BIN_i bins are "numbered sequentially starting from 1 and no maximum is placed
    /// on the number of BINs", without leading zeros — so `bin-0` and `bin-01` are
    /// refused (nil), and N is bounded only by the 16-character CS value
    /// (``maximumBinNumber``). Shared by the dicom-print `--film-destination` option and
    /// DICOMStudio's print settings.
    public init?(catalogToken token: String) {
        let upper = token.trimmingCharacters(in: .whitespaces).uppercased()
        let term = upper.hasPrefix("BIN-") ? "BIN_" + upper.dropFirst(4) : upper
        self.init(rawValue: term)
    }

    /// The catalog token: `magazine`, `processor` or `bin-N`.
    public var catalogToken: String {
        if let n = binNumber { return "bin-\(n)" }
        return rawValue.lowercased()
    }

    /// The token list for help text: the picker defaults and the open-ended `bin-N`.
    public static let catalogTokenList =
        "magazine = MAGAZINE, processor = PROCESSOR, bin-1 = BIN_1, bin-2 = BIN_2, ... bin-N = BIN_N"
}
