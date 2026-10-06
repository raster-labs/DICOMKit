/// DICOM Print Management Service
///
/// Implements the DICOM Print Management Service Class as defined in PS3.4 Annex H.
/// Provides data models, SOP Class UIDs, and service operations for DICOM printing.
///
/// Reference: PS3.4 Annex H - Print Management Service Class

import Foundation
import DICOMCore

#if canImport(CoreGraphics)
import CoreGraphics
// NEMA-verified: 2026a, checked 2026-10-06 — extractStringValue length rule routed through DICOMCore's VR.uses32BitLength (PS3.5 2026a 7.1.2: 21 VRs of Table 7.1-2 16-bit, the other 13 32-bit; D276); the 12 print SOP Class / instance UIDs registered in PS3.6 2026a Table A-1 and 11 defined-term enums text-diffed against PS3.3 2026a C.13.1/C.13.3/C.13.5/C.13.8/C.13.9 (Scripts/diff_network.py; MediumType MAMMO CLEAR FILM / MAMMO BLUE FILM added 2026-09-29, P-MAMMO, old spellings deprecated and written as the terms); N-ACTION-RSP Print Job reference per PS3.4 Tables H.4-3/H.4-8; colour item per Table C.13-5; Text String (2030,0020) written as a legal LO per PS3.5 2026a Table 6.2-1 (D41, checked 2026-09-29); FilmDestination re-checked 2026-10-01 against PS3.3 2026a Table C.13-1 (MAGAZINE, PROCESSOR, BIN_i numbered from 1, no maximum, no leading zeros; P-BIN: .bin(n), .bin1/.bin2 deprecated)
#else
// Define CGSize for platforms without CoreGraphics
public struct CGSize: Sendable {
    public let width: Double
    public let height: Double
    
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}
#endif

// MARK: - Print Management SOP Class UIDs

/// Basic Film Session SOP Class UID (PS3.4 H.4.1)
public let basicFilmSessionSOPClassUID = "1.2.840.10008.5.1.1.1"
/// Basic Film Box SOP Class UID (PS3.4 H.4.2)
public let basicFilmBoxSOPClassUID = "1.2.840.10008.5.1.1.2"
/// Basic Grayscale Image Box SOP Class UID (PS3.4 H.4.3.1)
public let basicGrayscaleImageBoxSOPClassUID = "1.2.840.10008.5.1.1.4"
/// Basic Color Image Box SOP Class UID (PS3.4 H.4.3.2)
public let basicColorImageBoxSOPClassUID = "1.2.840.10008.5.1.1.4.1"
/// Basic Grayscale Print Management Meta SOP Class UID
public let basicGrayscalePrintManagementMetaSOPClassUID = "1.2.840.10008.5.1.1.9"
/// Basic Color Print Management Meta SOP Class UID
public let basicColorPrintManagementMetaSOPClassUID = "1.2.840.10008.5.1.1.18"
/// Printer SOP Class UID (PS3.4 H.4.6)
public let printerSOPClassUID = "1.2.840.10008.5.1.1.16"
/// Printer SOP Instance UID (Well-Known)
public let printerSOPInstanceUID = "1.2.840.10008.5.1.1.17"
/// Print Job SOP Class UID (PS3.4 H.4.5)
public let printJobSOPClassUID = "1.2.840.10008.5.1.1.14"
/// Presentation LUT SOP Class UID (PS3.4 H.4.9). An optional SOP Class of the
/// Print Management Service Class (Table H.3.3.2-1), *not* a member of the
/// Grayscale/Color Print Management Meta SOP Classes: it must be negotiated
/// on a presentation context of its own.
public let presentationLUTSOPClassUID = "1.2.840.10008.5.1.1.23"
/// Basic Annotation Box SOP Class UID (PS3.4 H.4.4)
public let basicAnnotationBoxSOPClassUID = "1.2.840.10008.5.1.1.15"
/// Basic Print Image Overlay Box SOP Class UID (PS3.4 H.4.12, retired)
public let basicPrintImageOverlayBoxSOPClassUID = "1.2.840.10008.5.1.1.24.1"

// MARK: - Print-specific DICOM Tags

extension Tag {
    // Film Session tags (PS3.3 C.13.1)
    /// Number of Copies (2000,0010)
    public static let numberOfCopies = Tag(group: 0x2000, element: 0x0010)
    /// Print Priority (2000,0020)
    public static let printPriority = Tag(group: 0x2000, element: 0x0020)
    /// Medium Type (2000,0030)
    public static let mediumType = Tag(group: 0x2000, element: 0x0030)
    /// Film Destination (2000,0040)
    public static let filmDestination = Tag(group: 0x2000, element: 0x0040)
    /// Film Session Label (2000,0050)
    public static let filmSessionLabel = Tag(group: 0x2000, element: 0x0050)
    /// Memory Allocation (2000,0060)
    public static let memoryAllocation = Tag(group: 0x2000, element: 0x0060)
    /// Referenced Film Box Sequence (2000,0500)
    public static let referencedFilmBoxSequence = Tag(group: 0x2000, element: 0x0500)
    
    // Film Box tags (PS3.3 C.13.3)
    /// Image Display Format (2010,0010)
    public static let imageDisplayFormat = Tag(group: 0x2010, element: 0x0010)
    /// Annotation Display Format ID (2010,0030)
    public static let annotationDisplayFormatID = Tag(group: 0x2010, element: 0x0030)
    /// Film Orientation (2010,0040)
    public static let filmOrientation = Tag(group: 0x2010, element: 0x0040)
    /// Film Size ID (2010,0050)
    public static let filmSizeID = Tag(group: 0x2010, element: 0x0050)
    /// Magnification Type (2010,0060)
    public static let magnificationType = Tag(group: 0x2010, element: 0x0060)
    /// Smoothing Type (2010,0080)
    public static let smoothingType = Tag(group: 0x2010, element: 0x0080)
    /// Border Density (2010,0100)
    public static let borderDensity = Tag(group: 0x2010, element: 0x0100)
    /// Empty Image Density (2010,0110)
    public static let emptyImageDensity = Tag(group: 0x2010, element: 0x0110)
    /// Min Density (2010,0120)
    public static let minDensity = Tag(group: 0x2010, element: 0x0120)
    /// Max Density (2010,0130)
    public static let maxDensity = Tag(group: 0x2010, element: 0x0130)
    /// Trim (2010,0140)
    public static let trim = Tag(group: 0x2010, element: 0x0140)
    /// Configuration Information (2010,0150)
    public static let configurationInformation = Tag(group: 0x2010, element: 0x0150)
    /// Referenced Film Session Sequence (2010,0500)
    public static let referencedFilmSessionSequence = Tag(group: 0x2010, element: 0x0500)
    /// Referenced Image Box Sequence (2010,0510)
    public static let referencedImageBoxSequence = Tag(group: 0x2010, element: 0x0510)
    /// Referenced Basic Annotation Box Sequence (2010,0520)
    public static let referencedBasicAnnotationBoxSequence = Tag(group: 0x2010, element: 0x0520)

    // Annotation Box tags (PS3.3 C.13.7)
    /// Annotation Position (2030,0010)
    public static let annotationPosition = Tag(group: 0x2030, element: 0x0010)
    /// Text String (2030,0020)
    public static let textString = Tag(group: 0x2030, element: 0x0020)

    // Presentation LUT tags (PS3.3 C.11.4, the hardcopy Presentation LUT Module)
    /// Presentation LUT Shape (2050,0020)
    public static let presentationLUTShape = Tag(group: 0x2050, element: 0x0020)
    /// Referenced Presentation LUT Sequence (2050,0500)
    public static let referencedPresentationLUTSequence = Tag(group: 0x2050, element: 0x0500)

    // Image Box tags (PS3.3 C.13.5)
    /// Image Box Position (2020,0010)
    public static let imageBoxPosition = Tag(group: 0x2020, element: 0x0010)
    /// Polarity (2020,0020)
    public static let polarity = Tag(group: 0x2020, element: 0x0020)
    /// Requested Image Size (2020,0030)
    public static let requestedImageSize = Tag(group: 0x2020, element: 0x0030)
    /// Requested Decimate/Crop Behavior (2020,0040)
    public static let requestedDecimateCropBehavior = Tag(group: 0x2020, element: 0x0040)
    /// Preformatted Grayscale Image Sequence (2020,0110)
    public static let preformattedGrayscaleImageSequence = Tag(group: 0x2020, element: 0x0110)
    /// Preformatted Color Image Sequence (2020,0111)
    public static let preformattedColorImageSequence = Tag(group: 0x2020, element: 0x0111)
    /// Referenced Image Overlay Box Sequence (2020,0130)
    public static let referencedImageOverlayBoxSequence = Tag(group: 0x2020, element: 0x0130)
    
    // Printer tags (PS3.3 C.13.9)
    /// Printer Status (2110,0010)
    public static let printerStatus = Tag(group: 0x2110, element: 0x0010)
    /// Printer Status Info (2110,0020)
    public static let printerStatusInfo = Tag(group: 0x2110, element: 0x0020)
    /// Printer Name (2110,0030)
    public static let printerName = Tag(group: 0x2110, element: 0x0030)
    
    // Print Job tags (PS3.3 C.13.8)
    /// Execution Status (2100,0020)
    public static let executionStatus = Tag(group: 0x2100, element: 0x0020)
    /// Execution Status Info (2100,0030)
    public static let executionStatusInfo = Tag(group: 0x2100, element: 0x0030)
    /// Creation Date (2100,0040)
    public static let creationDate = Tag(group: 0x2100, element: 0x0040)
    /// Creation Time (2100,0050)
    public static let creationTime = Tag(group: 0x2100, element: 0x0050)
    /// Originator (2100,0070), VR AE — the Application Entity Title that
    /// issued the print operation (PS3.3 Table C.13-8; PS3.6 keyword
    /// `Originator`).
    ///
    /// FIXME(NEMA 2026a): the member name predates verification; the tag's
    /// name is Originator. Renaming is a public API change pending owner
    /// approval.
    public static let originatingPrintManagement = Tag(group: 0x2100, element: 0x0070)

    // MARK: - Presentation LUT viewing conditions (Film Box, PS3.4 Table H.4-6)
    /// Illumination (2010,015E) US — cd/m², used with a Presentation LUT
    public static let illumination = Tag(group: 0x2010, element: 0x015E)
    /// Reflected Ambient Light (2010,0160) US — cd/m², used with a Presentation LUT
    public static let reflectedAmbientLight = Tag(group: 0x2010, element: 0x0160)
}

// MARK: - Print Configuration

/// Configuration for DICOM Print operations
public struct PrintConfiguration: Sendable {
    public let host: String
    public let port: UInt16
    public let callingAETitle: String
    public let calledAETitle: String
    public let timeout: TimeInterval
    public let colorMode: PrintColorMode
    
    public init(host: String, port: UInt16, callingAETitle: String, calledAETitle: String,
                timeout: TimeInterval = 30, colorMode: PrintColorMode = .grayscale) {
        self.host = host
        self.port = port
        self.callingAETitle = callingAETitle
        self.calledAETitle = calledAETitle
        self.timeout = timeout
        self.colorMode = colorMode
    }
}

/// Print color mode.
///
/// The same type as `DICOMKit.PrintColorMode`: both are `DICOMCore.PrintColorMode` (D24).
public typealias PrintColorMode = DICOMCore.PrintColorMode

// MARK: - Film Session

/// Film session parameters (PS3.4 H.4.1)
public struct FilmSession: Sendable, Equatable {
    public let sopInstanceUID: String
    public var numberOfCopies: Int
    public var printPriority: PrintPriority
    public var mediumType: MediumType
    public var filmDestination: FilmDestination
    public var filmSessionLabel: String?
    
    public init(sopInstanceUID: String = "",
                numberOfCopies: Int = 1,
                printPriority: PrintPriority = .medium,
                mediumType: MediumType = .paper,
                filmDestination: FilmDestination = .processor,
                filmSessionLabel: String? = nil) {
        self.sopInstanceUID = sopInstanceUID
        self.numberOfCopies = numberOfCopies
        self.printPriority = printPriority
        self.mediumType = mediumType
        self.filmDestination = filmDestination
        self.filmSessionLabel = filmSessionLabel
    }
}

/// Print priority levels
public enum PrintPriority: String, Sendable, Hashable, CaseIterable, Codable {
    case high = "HIGH"
    case medium = "MED"
    case low = "LOW"
}

/// Medium Type (2000,0030) — the Defined Terms of PS3.3 Table C.13-1.
public enum MediumType: String, Sendable, Hashable, CaseIterable, Codable {
    case paper = "PAPER"
    case clearFilm = "CLEAR FILM"
    case blueFilm = "BLUE FILM"
    case mammoClearFilm = "MAMMO CLEAR FILM"
    case mammoBlueFilm = "MAMMO BLUE FILM"

    /// `MAMMO CLEAR` is not a Medium Type term. Kept so older code compiles and
    /// an SCU that sends it can still be read; it is written as
    /// `MAMMO CLEAR FILM` (see ``wireValue``).
    @available(*, deprecated, renamed: "mammoClearFilm",
               message: "PS3.3 Table C.13-1 defines MAMMO CLEAR FILM")
    case mammoFilmClearBase = "MAMMO CLEAR"

    /// `MAMMO BLUE` is not a Medium Type term; written as `MAMMO BLUE FILM`.
    @available(*, deprecated, renamed: "mammoBlueFilm",
               message: "PS3.3 Table C.13-1 defines MAMMO BLUE FILM")
    case mammoFilmBlueBase = "MAMMO BLUE"

    /// The case for this value with the two deprecated spellings mapped to the
    /// terms they meant — what a received value is stored as.
    public var normalized: MediumType {
        switch rawValue {
        case "MAMMO CLEAR": return .mammoClearFilm
        case "MAMMO BLUE":  return .mammoBlueFilm
        default:            return self
        }
    }

    /// The value written to Medium Type (2000,0030): always a Table C.13-1
    /// Defined Term, whichever case was chosen.
    public var wireValue: String { normalized.rawValue }

    /// The five Defined Terms of Table C.13-1. The deprecated spellings are not
    /// listed: a received one is normalized to its term before any set of
    /// supported media is consulted.
    public static let allCases: [MediumType] = [
        .paper, .clearFilm, .blueFilm, .mammoClearFilm, .mammoBlueFilm
    ]
}

/// Film Destination (2000,0040), PS3.3 2026a Table C.13-1: MAGAZINE, PROCESSOR, or
/// BIN_i — "Film sorter BINs shall be numbered sequentially starting from 1 and no maximum
/// is placed on the number of BINs. The encoding of the BIN number shall not contain
/// leading zeros." A bin is `.bin(n)` for any n ≥ 1 (P-BIN; the fixed `.bin1` / `.bin2`
/// are deprecated). The value is a CS (PS3.5 Table 6.2-1, at most 16 characters), so a
/// bin number has at most 12 digits.
///
/// Formerly an enum with four cases; it is a struct so that every BIN_i can be carried.
/// `rawValue`, `init?(rawValue:)`, `Codable` (a single string), `Hashable`, and the
/// `.magazine` / `.processor` / `.bin1` / `.bin2` spellings keep working.
public struct FilmDestination: RawRepresentable, Sendable, Hashable, CaseIterable, Codable,
                               CustomStringConvertible {
    /// The Defined Term written to (2000,0040).
    public let rawValue: String

    /// Accepts MAGAZINE, PROCESSOR or BIN_i (i ≥ 1, no leading zeros, CS length ≤ 16).
    public init?(rawValue: String) {
        if rawValue == "MAGAZINE" || rawValue == "PROCESSOR" || Self.binNumber(of: rawValue) != nil {
            self.rawValue = rawValue
        } else {
            return nil
        }
    }

    private init(term: String) { self.rawValue = term }

    /// The exposed film is stored in film magazine.
    public static let magazine = FilmDestination(term: "MAGAZINE")
    /// The exposed film is developed in film processor.
    public static let processor = FilmDestination(term: "PROCESSOR")

    /// Sorter bin `number` (BIN_<number>); `number` is 1 or more and at most 12 digits.
    public static func bin(_ number: Int) -> FilmDestination {
        precondition(number >= 1 && number <= maximumBinNumber,
                     "Film Destination BIN_i: i is 1 or more (PS3.3 Table C.13-1), got \(number)")
        return FilmDestination(term: "BIN_\(number)")
    }

    @available(*, deprecated, message: "use FilmDestination.bin(1): PS3.3 Table C.13-1 defines BIN_i with no maximum")
    public static var bin1: FilmDestination { .bin(1) }

    @available(*, deprecated, message: "use FilmDestination.bin(2): PS3.3 Table C.13-1 defines BIN_i with no maximum")
    public static var bin2: FilmDestination { .bin(2) }

    /// The largest bin number whose BIN_i term fits a CS value (16 characters).
    public static let maximumBinNumber = 999_999_999_999

    /// The bin number when this is BIN_i, else nil.
    public var binNumber: Int? { Self.binNumber(of: rawValue) }

    /// MAGAZINE, PROCESSOR and the first two bins — the values the former enum listed.
    /// BIN_i has no maximum, so this is not every valid value.
    public static var allCases: [FilmDestination] { [.magazine, .processor, .bin(1), .bin(2)] }

    public var description: String { rawValue }

    /// i of "BIN_i" when i is a positive decimal without leading zeros (Table C.13-1).
    private static func binNumber(of term: String) -> Int? {
        guard term.hasPrefix("BIN_") else { return nil }
        let digits = term.dropFirst(4)
        guard !digits.isEmpty, digits.count <= 12, digits.first != "0",
              digits.allSatisfy({ $0 >= "0" && $0 <= "9" }), let number = Int(digits) else { return nil }
        return number
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = FilmDestination(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Film Destination must be MAGAZINE, PROCESSOR or BIN_i (PS3.3 Table C.13-1), got \(raw)")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Film Box

/// Film box parameters (PS3.4 H.4.2)
public struct FilmBox: Sendable, Equatable {
    public let sopInstanceUID: String
    public var imageDisplayFormat: String
    public var filmOrientation: FilmOrientation
    public var filmSizeID: FilmSize
    public var magnificationType: MagnificationType
    public var borderDensity: String
    public var emptyImageDensity: String
    public var trimOption: TrimOption
    public var configurationInformation: String?
    public let imageBoxSOPInstanceUIDs: [String]
    
    public init(sopInstanceUID: String = "",
                imageDisplayFormat: String = "STANDARD\\1,1",
                filmOrientation: FilmOrientation = .portrait,
                filmSizeID: FilmSize = .size8InX10In,
                magnificationType: MagnificationType = .replicate,
                borderDensity: String = "BLACK",
                emptyImageDensity: String = "BLACK",
                trimOption: TrimOption = .no,
                configurationInformation: String? = nil,
                imageBoxSOPInstanceUIDs: [String] = []) {
        self.sopInstanceUID = sopInstanceUID
        self.imageDisplayFormat = imageDisplayFormat
        self.filmOrientation = filmOrientation
        self.filmSizeID = filmSizeID
        self.magnificationType = magnificationType
        self.borderDensity = borderDensity
        self.emptyImageDensity = emptyImageDensity
        self.trimOption = trimOption
        self.configurationInformation = configurationInformation
        self.imageBoxSOPInstanceUIDs = imageBoxSOPInstanceUIDs
    }
}

/// Film orientation
public enum FilmOrientation: String, Sendable, Hashable, CaseIterable, Codable {
    case portrait = "PORTRAIT"
    case landscape = "LANDSCAPE"
}

/// Film size identifiers (Film Size ID, PS3.3 C.13.3 Table C.13-3)
public enum FilmSize: String, Sendable, Hashable, CaseIterable, Codable {
    case size8InX10In = "8INX10IN"
    case size8_5InX11In = "8_5INX11IN"
    case size10InX12In = "10INX12IN"
    case size10InX14In = "10INX14IN"
    case size11InX14In = "11INX14IN"
    case size11InX17In = "11INX17IN"
    case size14InX14In = "14INX14IN"
    case size14InX17In = "14INX17IN"
    case size24CmX24Cm = "24CMX24CM"
    case size24CmX30Cm = "24CMX30CM"
    case a4 = "A4"
    case a3 = "A3"
}

/// Magnification type
public enum MagnificationType: String, Sendable, Hashable, CaseIterable, Codable {
    case replicate = "REPLICATE"
    case bilinear = "BILINEAR"
    case cubic = "CUBIC"
    case none = "NONE"
}

/// Trim option
public enum TrimOption: String, Sendable, Hashable, CaseIterable, Codable {
    case yes = "YES"
    case no = "NO"
}

// MARK: - Image Box

/// The per-image scaling attributes a job can attach to an image box: what
/// FR-003's scaling modes look like on the wire.
public struct PrintImageBoxOptions: Sendable, Equatable, Hashable {
    /// Requested Image Size (2020,0030) — the printed width in millimetres,
    /// as a DS string. `nil` sends nothing and the printer fits the cell.
    public var requestedImageSize: String?

    /// Requested Decimate/Crop Behavior (2020,0040). DECIMATE — the printer
    /// default — is omitted from the N-SET, so printers that do not implement
    /// the attribute still accept the image box.
    public var requestedDecimateCropBehavior: DecimateCropBehavior

    public init(requestedImageSize: String? = nil,
                requestedDecimateCropBehavior: DecimateCropBehavior = .decimate) {
        self.requestedImageSize = requestedImageSize
        self.requestedDecimateCropBehavior = requestedDecimateCropBehavior
    }
}

/// Image box content (PS3.4 H.4.3)
public struct ImageBoxContent: Sendable, Equatable {
    public let sopInstanceUID: String
    public var imagePosition: UInt16
    public var polarity: ImagePolarity
    public var requestedImageSize: String?
    public var requestedDecimateCropBehavior: DecimateCropBehavior
    
    public init(sopInstanceUID: String = "",
                imagePosition: UInt16 = 1,
                polarity: ImagePolarity = .normal,
                requestedImageSize: String? = nil,
                requestedDecimateCropBehavior: DecimateCropBehavior = .decimate) {
        self.sopInstanceUID = sopInstanceUID
        self.imagePosition = imagePosition
        self.polarity = polarity
        self.requestedImageSize = requestedImageSize
        self.requestedDecimateCropBehavior = requestedDecimateCropBehavior
    }
}

/// Image polarity
public enum ImagePolarity: String, Sendable, Hashable, CaseIterable, Codable {
    case normal = "NORMAL"
    case reverse = "REVERSE"
}

/// Decimate/crop behavior
public enum DecimateCropBehavior: String, Sendable, Hashable, CaseIterable {
    case decimate = "DECIMATE"
    case crop = "CROP"
    case failOver = "FAIL"
}

// MARK: - Printer Status

/// The three operational states a Print SCP reports in Printer Status (2110,0010),
/// plus the case where it reported nothing usable.
///
/// PS3.3 C.13.9 defines exactly NORMAL, WARNING and FAILURE. Callers should switch
/// on this rather than compare ``PrinterStatus/status`` strings, so an unrecognised
/// value from a non-conformant SCP lands on ``unknown`` instead of being silently
/// treated as normal.
public enum PrinterStatusSeverity: String, Sendable, Equatable, Hashable, CaseIterable {
    case normal  = "NORMAL"
    case warning = "WARNING"
    case failure = "FAILURE"
    case unknown = "UNKNOWN"

    /// Human-readable label.
    public var displayName: String {
        switch self {
        case .normal:  return "Normal"
        case .warning: return "Warning"
        case .failure: return "Failure"
        case .unknown: return "Unknown"
        }
    }

    /// Whether new print jobs should be sent while the printer reports this.
    ///
    /// WARNING is accepting-with-notice per the spec (a low-film printer still
    /// prints); FAILURE and UNKNOWN are not safe to submit to.
    public var acceptsJobs: Bool {
        self == .normal || self == .warning
    }
}

/// Printer status information
public struct PrinterStatus: Sendable, Equatable {
    /// Printer Status (2110,0010) — NORMAL, WARNING, or FAILURE per PS3.3 C.13.9.
    /// "UNKNOWN" when the SCP's N-GET response did not include the attribute.
    public let status: String
    /// Printer Status Info (2110,0020) — printer-specific detail, e.g. "SUPPLY LOW".
    public let statusInfo: String?
    /// Printer Name (2110,0030).
    public let printerName: String?
    /// Manufacturer (0008,0070), when returned.
    public let manufacturer: String?
    /// Manufacturer Model Name (0008,1090), when returned.
    public let manufacturerModelName: String?

    public init(status: String, statusInfo: String? = nil, printerName: String? = nil,
                manufacturer: String? = nil, manufacturerModelName: String? = nil) {
        self.status = status
        self.statusInfo = statusInfo
        self.printerName = printerName
        self.manufacturer = manufacturer
        self.manufacturerModelName = manufacturerModelName
    }

    /// The reported state as a closed enum.
    ///
    /// Parsed leniently: SCPs have been seen padding the CS value or varying its
    /// case, and an unrecognised value is reported as ``PrinterStatusSeverity/unknown``
    /// rather than assumed normal.
    public var severity: PrinterStatusSeverity {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return PrinterStatusSeverity(rawValue: normalized) ?? .unknown
    }

    /// Whether the printer is in a normal operational state
    public var isNormal: Bool {
        severity == .normal
    }

    /// Whether the printer is operational but reported a non-blocking issue,
    /// e.g. "SUPPLY LOW". Jobs are still accepted; the user should be told.
    public var isWarning: Bool {
        severity == .warning
    }

    /// Whether the printer reported a condition that should block new jobs.
    public var isFailure: Bool {
        severity == .failure
    }
}

// MARK: - Print Result

/// Result of a print operation
public struct PrintResult: Sendable {
    public let success: Bool
    public let status: DIMSEStatus
    public let filmSessionUID: String?

    /// Every Film Box created by this job, in film order.
    ///
    /// A job spills across multiple film boxes whenever the image count exceeds
    /// the layout's cell count (`rows × columns`), so this has one entry per
    /// physical film. ``filmBoxUID`` remains the last one for source compatibility.
    public let filmBoxUIDs: [String]

    /// Every Print Job SOP Instance UID returned by the job, in film order.
    ///
    /// One per printed film box (SCPs that omit the UID in the N-ACTION response
    /// contribute no entry). Job-status polling needs all of them, not just the
    /// last. ``printJobUID`` remains the last one for source compatibility.
    public let printJobUIDs: [String]

    public let errorMessage: String?

    /// The last Film Box UID of the job (see ``filmBoxUIDs`` for all of them).
    public var filmBoxUID: String? { filmBoxUIDs.last }

    /// The last Print Job UID of the job (see ``printJobUIDs`` for all of them).
    public var printJobUID: String? { printJobUIDs.last }

    public init(success: Bool, status: DIMSEStatus, filmSessionUID: String? = nil,
                filmBoxUID: String? = nil, printJobUID: String? = nil, errorMessage: String? = nil) {
        self.init(success: success,
                  status: status,
                  filmSessionUID: filmSessionUID,
                  filmBoxUIDs: filmBoxUID.map { [$0] } ?? [],
                  printJobUIDs: printJobUID.map { [$0] } ?? [],
                  errorMessage: errorMessage)
    }

    /// Creates a result carrying every film box / print job of a multi-film job.
    public init(success: Bool, status: DIMSEStatus, filmSessionUID: String? = nil,
                filmBoxUIDs: [String], printJobUIDs: [String], errorMessage: String? = nil) {
        self.success = success
        self.status = status
        self.filmSessionUID = filmSessionUID
        self.filmBoxUIDs = filmBoxUIDs
        self.printJobUIDs = printJobUIDs
        self.errorMessage = errorMessage
    }
}

// MARK: - Film Box Result

/// Result of Film Box creation (PS3.4 H.4.2)
public struct FilmBoxResult: Sendable {
    /// The assigned Film Box SOP Instance UID
    public let filmBoxUID: String
    
    /// Array of Image Box SOP Instance UIDs created for this Film Box
    public let imageBoxUIDs: [String]
    
    /// Number of image boxes (calculated from Image Display Format)
    public let imageCount: Int
    
    public init(filmBoxUID: String, imageBoxUIDs: [String], imageCount: Int) {
        self.filmBoxUID = filmBoxUID
        self.imageBoxUIDs = imageBoxUIDs
        self.imageCount = imageCount
    }
}

// MARK: - Print Job Status

/// Status of a print job (PS3.4 H.4.5)
public struct PrintJobStatus: Sendable {
    /// Print Job SOP Instance UID
    public let printJobUID: String
    
    /// Execution status (PENDING, PRINTING, DONE, FAILURE)
    public let executionStatus: String
    
    /// Additional status information (optional)
    public let executionStatusInfo: String?
    
    /// Date when the print job was created
    public let creationDate: Date?
    
    /// Time when the print job was created
    public let creationTime: Date?
    
    public init(printJobUID: String,
                executionStatus: String,
                executionStatusInfo: String? = nil,
                creationDate: Date? = nil,
                creationTime: Date? = nil) {
        self.printJobUID = printJobUID
        self.executionStatus = executionStatus
        self.executionStatusInfo = executionStatusInfo
        self.creationDate = creationDate
        self.creationTime = creationTime
    }
    
    /// Whether the print job is still pending or printing
    public var isInProgress: Bool {
        executionStatus == "PENDING" || executionStatus == "PRINTING"
    }
    
    /// Whether the print job completed successfully
    public var isCompleted: Bool {
        executionStatus == "DONE"
    }
    
    /// Whether the print job failed
    public var isFailed: Bool {
        executionStatus == "FAILURE"
    }
}

// MARK: - Print Events (N-EVENT-REPORT)

/// Printer status event type reported by the Printer SOP Class.
///
/// Reference: PS3.4 H.4.6.2.1 (Printer SOP Class N-EVENT-REPORT, Event Type IDs).
public enum PrinterEventType: UInt16, Sendable, Equatable {
    /// Printer returned to a normal operating state (Event Type ID 1).
    case normal = 1
    /// Printer raised a warning condition, e.g. low film (Event Type ID 2).
    case warning = 2
    /// Printer raised a failure condition, e.g. out of film / jam (Event Type ID 3).
    case failure = 3
}

/// Print job execution event type reported by the Print Job SOP Class.
///
/// Reference: PS3.4 H.4.5.2.1 (Print Job SOP Class N-EVENT-REPORT, Event Type IDs).
public enum PrintJobEventType: UInt16, Sendable, Equatable {
    /// The print job is queued and pending (Event Type ID 1).
    case pending = 1
    /// The print job is currently printing (Event Type ID 2).
    case printing = 2
    /// The print job completed successfully (Event Type ID 3).
    case done = 3
    /// The print job failed (Event Type ID 4).
    case failure = 4
}

/// An asynchronous notification received from a Print SCP via N-EVENT-REPORT.
///
/// A printer may push status changes (Printer SOP Class) or print-job progress
/// (Print Job SOP Class) to the SCU over an open association. These arrive
/// interleaved with the SCU's own request/response traffic and are surfaced to
/// callers through a ``PrintEventHandler``.
public struct PrintEvent: Sendable, Equatable {
    /// The SOP Class UID of the source object (Printer or Print Job).
    public let sopClassUID: String

    /// The SOP Instance UID of the source object.
    public let sopInstanceUID: String

    /// The raw Event Type ID from the N-EVENT-REPORT command.
    public let eventTypeID: UInt16

    /// Printer Status Info (2110,0020) when present in the event data set.
    public let printerStatusInfo: String?

    /// Execution Status Info (2100,0030) when present in the event data set.
    public let executionStatusInfo: String?

    public init(
        sopClassUID: String,
        sopInstanceUID: String,
        eventTypeID: UInt16,
        printerStatusInfo: String? = nil,
        executionStatusInfo: String? = nil
    ) {
        self.sopClassUID = sopClassUID
        self.sopInstanceUID = sopInstanceUID
        self.eventTypeID = eventTypeID
        self.printerStatusInfo = printerStatusInfo
        self.executionStatusInfo = executionStatusInfo
    }

    /// Interpreted printer event, if this came from the Printer SOP Class.
    public var printerEvent: PrinterEventType? {
        sopClassUID == printerSOPClassUID ? PrinterEventType(rawValue: eventTypeID) : nil
    }

    /// Interpreted print job event, if this came from the Print Job SOP Class.
    public var printJobEvent: PrintJobEventType? {
        sopClassUID == printJobSOPClassUID ? PrintJobEventType(rawValue: eventTypeID) : nil
    }

    /// Whether this event indicates a condition the caller should surface
    /// (printer warning/failure, or print-job failure).
    public var isFault: Bool {
        printerEvent == .warning || printerEvent == .failure || printJobEvent == .failure
    }

    /// A concise, human-readable description of the event.
    public var summary: String {
        let source: String
        let state: String
        if let pe = printerEvent {
            source = "Printer"
            switch pe {
            case .normal: state = "Normal"
            case .warning: state = "Warning"
            case .failure: state = "Failure"
            }
        } else if let je = printJobEvent {
            source = "Print Job"
            switch je {
            case .pending: state = "Pending"
            case .printing: state = "Printing"
            case .done: state = "Done"
            case .failure: state = "Failure"
            }
        } else {
            source = "Print"
            state = "Event \(eventTypeID)"
        }
        let info = printerStatusInfo ?? executionStatusInfo
        if let info = info, !info.isEmpty {
            return "\(source) \(state): \(info)"
        }
        return "\(source) \(state)"
    }
}

/// A handler invoked for each ``PrintEvent`` received from a Print SCP.
///
/// The handler is called synchronously on the networking task as events arrive;
/// keep it lightweight (e.g. append to an actor-isolated buffer or log).
public typealias PrintEventHandler = @Sendable (PrintEvent) -> Void

// MARK: - Print Image Data

/// Bundles pixel data with its image descriptor for printing
///
/// The Basic Grayscale/Color Image Sequence (PS3.3 C.13.5, Table C.13-5) requires
/// image attributes (rows, columns, bits allocated, etc.) alongside pixel data.
/// This struct carries both through the print pipeline.
public struct PrintImageData: Sendable, Equatable {
    /// Raw pixel data bytes (uncompressed)
    public let pixelData: Data

    /// Number of rows (height) in the image
    public let rows: UInt16

    /// Number of columns (width) in the image
    public let columns: UInt16

    /// Bits allocated per pixel sample (typically 8 or 16)
    public let bitsAllocated: UInt16

    /// Bits stored per pixel sample
    public let bitsStored: UInt16

    /// Most significant bit (usually bitsStored - 1)
    public let highBit: UInt16

    /// Samples per pixel (1 for grayscale, 3 for color)
    public let samplesPerPixel: UInt16

    /// Pixel representation: 0 = unsigned, 1 = signed
    public let pixelRepresentation: UInt16

    /// Photometric interpretation string (e.g. "MONOCHROME2")
    public let photometricInterpretation: String

    /// Creates a PrintImageData from raw values
    public init(
        pixelData: Data,
        rows: UInt16,
        columns: UInt16,
        bitsAllocated: UInt16,
        bitsStored: UInt16,
        highBit: UInt16,
        samplesPerPixel: UInt16 = 1,
        pixelRepresentation: UInt16 = 0,
        photometricInterpretation: String = "MONOCHROME2"
    ) {
        self.pixelData = pixelData
        self.rows = rows
        self.columns = columns
        self.bitsAllocated = bitsAllocated
        self.bitsStored = bitsStored
        self.highBit = highBit
        self.samplesPerPixel = samplesPerPixel
        self.pixelRepresentation = pixelRepresentation
        self.photometricInterpretation = photometricInterpretation
    }
}

// MARK: - Presentation LUT

/// Presentation LUT Shape (2050,0020) — the transformation applied to stored
/// pixel values before printing.
///
/// Reference: PS3.3 **C.11.4** (Presentation LUT Module, the hardcopy one).
/// That module enumerates exactly two values, `IDENTITY` and `LIN OD`;
/// `INVERSE` belongs to C.11.6, the *softcopy* module, and is not legal on the
/// wire in a print context — DCMTK's `isLegalPrintPresentationLUT` rejects it
/// outright, so a printer is entitled to fail the N-CREATE.
///
/// ``inverseRendered`` therefore is not a shape at all: it is the request to
/// invert the pixels before they are sent, which is how DCMTK's
/// `dcmpsprt --inverse-plut` gets an inverted film out of a conformant
/// printer. It carries ``wireValue`` `nil` for that reason — there is nothing
/// legal to put in (2050,0020) for it.
///
/// For an arbitrary curve, send a ``PresentationLUTTable`` instead of a shape.
public enum PresentationLUTShape: String, Sendable, Equatable, CaseIterable, Codable {
    /// No transformation — stored values map directly to P-Values (IDENTITY).
    case identity = "IDENTITY"
    /// Linear optical density (LIN OD), bounded by Min/Max Density.
    case linearOpticalDensity = "LIN OD"
    /// Inversion rendered into the pixels, with no shape sent (PS3.3 C.11.4
    /// has no `INVERSE`). The film comes out inverted on any printer.
    case inverseRendered = "INVERSE_RENDERED"

    /// The string to put in Presentation LUT Shape (2050,0020), or `nil` when
    /// this option is realised in the pixels instead of on the wire.
    public var wireValue: String? {
        switch self {
        case .identity, .linearOpticalDensity: return rawValue
        case .inverseRendered: return nil
        }
    }

    /// Whether the sender must invert the pixels to honour this option.
    public var invertsPixels: Bool { self == .inverseRendered }

    /// Whether PS3.3 C.11.4 allows this as a Presentation LUT Shape on the wire.
    public var isLegalPrintShape: Bool { wireValue != nil }
}

/// A custom Presentation LUT, sent as the Presentation LUT Sequence
/// (2050,0010) instead of a shape — the SRS's "Custom" option.
///
/// Reference: PS3.3 C.11.4. The LUT Descriptor's first value mapped is always
/// 0 for a Presentation LUT, so only the entries and their depth are stated.
public struct PresentationLUTTable: Sendable, Equatable, Codable {
    /// The output values, in ascending input order. 1...65536 entries.
    public let entries: [UInt16]
    /// Bits per entry, 8...16. Entries must fit.
    public let bitsPerEntry: Int

    /// Fails on an entry count or depth PS3.3 C.11.4 does not allow, because a
    /// malformed LUT would be rejected mid-association after film was created.
    public init?(entries: [UInt16], bitsPerEntry: Int = 12) {
        guard (1...65536).contains(entries.count),
              (8...16).contains(bitsPerEntry),
              entries.allSatisfy({ Int($0) < (1 << bitsPerEntry) }) else { return nil }
        self.entries = entries
        self.bitsPerEntry = bitsPerEntry
    }

    /// The Presentation LUT Sequence element carrying this table.
    ///
    /// Descriptor value 0 means 2^16 entries — the one place DICOM's 16-bit
    /// counter wraps and means "the most", not "none".
    func sequenceElement() -> DataElement {
        let count = entries.count == 65536 ? 0 : entries.count
        var descriptor = Data()
        for value in [UInt16(count), 0, UInt16(bitsPerEntry)] {
            descriptor.append(UInt8(value & 0xFF))
            descriptor.append(UInt8(value >> 8))
        }
        var lutData = Data(capacity: entries.count * 2)
        for value in entries {
            lutData.append(UInt8(value & 0xFF))
            lutData.append(UInt8(value >> 8))
        }
        let item = SequenceItem(elements: [
            DataElement(tag: Tag(group: 0x0028, element: 0x3002), vr: .US,
                        length: UInt32(descriptor.count), valueData: descriptor),
            DataElement(tag: Tag(group: 0x0028, element: 0x3006), vr: .OW,
                        length: UInt32(lutData.count), valueData: lutData)
        ])
        return DataElement(
            tag: Tag(group: 0x2050, element: 0x0010), vr: .SQ,
            length: 0xFFFFFFFF, valueData: Data(), sequenceItems: [item])
    }
}

// MARK: - Print Annotation

/// A text annotation to place on the film via the Basic Annotation Box SOP Class.
///
/// Reference: PS3.3 C.13.7. The printer must be configured with an Annotation
/// Display Format that provides annotation box positions; ``position`` selects
/// which configured box receives ``text``.
public struct PrintAnnotation: Sendable, Equatable, Codable {
    /// The 1-based annotation box position on the film (Annotation Position, 2030,0010).
    public let position: UInt16

    /// The annotation text (Text String, 2030,0020).
    public let text: String

    public init(position: UInt16, text: String) {
        self.position = max(1, position)
        self.text = text
    }

    /// The most characters Text String (2030,0020) carries: it is LO,
    /// "64 chars maximum" (PS3.5 Table 6.2-1).
    public static let textStringMaximumLength = 64

    /// ``text`` as the value written to Text String (2030,0020): a legal LO —
    /// at most 64 characters, no backslash (the value delimiter; written as a
    /// slash) and no control characters but ESC (PS3.5 Table 6.2-1).
    public var textStringValue: String {
        let cleaned = text
            .replacingOccurrences(of: "\\", with: "/")
            .filter { character in
                !character.unicodeScalars.contains {
                    $0.properties.generalCategory == .control && $0 != "\u{1B}"
                }
            }
        return String(cleaned.prefix(Self.textStringMaximumLength))
    }
}

// MARK: - Print Options

/// Options for print operations
///
/// Provides configuration options for print jobs including number of copies,
/// priority, film size, orientation, and other print parameters.
public struct PrintOptions: Sendable {
    /// Number of copies to print
    public let numberOfCopies: Int
    
    /// Print priority
    public let priority: PrintPriority
    
    /// Film size
    public let filmSize: FilmSize
    
    /// Film orientation (portrait or landscape)
    public let filmOrientation: FilmOrientation
    
    /// Medium type (paper, film, etc.)
    public let mediumType: MediumType
    
    /// Film destination
    public let filmDestination: FilmDestination
    
    /// Border density (e.g., "BLACK", "WHITE")
    public let borderDensity: String
    
    /// Empty image density
    public let emptyImageDensity: String
    
    /// Magnification type
    public let magnificationType: MagnificationType
    
    /// Image polarity
    public let polarity: ImagePolarity
    
    /// Trim option
    public let trimOption: TrimOption
    
    /// Optional session label
    public let sessionLabel: String?

    /// Optional Presentation LUT Shape to create and reference from the film box.
    /// When `nil`, no Presentation LUT is created (printer default applies).
    public let presentationLUTShape: PresentationLUTShape?

    /// Optional custom Presentation LUT, sent as a LUT Sequence instead of a
    /// shape. Takes precedence over ``presentationLUTShape`` — an instance
    /// carries one or the other, and a caller providing data means the data.
    public let presentationLUTTable: PresentationLUTTable?

    /// Text annotations to place on the film via Basic Annotation Boxes. Applied
    /// only when ``annotationDisplayFormatID`` is also set (it is printer-specific).
    public let annotations: [PrintAnnotation]

    /// Annotation Display Format ID (2010,0030) identifying the printer-configured
    /// annotation layout. Required for ``annotations`` to be sent.
    public let annotationDisplayFormatID: String?

    /// Annotations for one film each, when the films of a job do not all say the
    /// same thing — a patient footer on a job that spills onto a second sheet
    /// holding a different study.
    ///
    /// Indexed by film; a film past the end, or with an empty entry, falls back
    /// to ``annotations``. Empty (the default) means every film carries
    /// ``annotations``, which is what a job-wide header wants.
    public let filmAnnotations: [[PrintAnnotation]]

    /// Configuration Information (2010,0150) — the printer-specific rendering
    /// configuration to select for this film box.
    ///
    /// Several vendors (Carestream/Kodak, Agfa) *require* this attribute and
    /// either fail the film box or print with the wrong calibration without it.
    /// The value is printer-defined; it comes from the device's conformance
    /// statement, e.g. `"CS000"`.
    public let configurationInformation: String?

    /// Per-image scaling attributes, indexed like the job's images. An image
    /// past the end of the array (or the empty default) gets no Requested
    /// Image Size and DECIMATE behavior — the printer's own fit, exactly as
    /// jobs before this attribute existed were sent.
    public let imageBoxOptions: [PrintImageBoxOptions]

    /// Illumination (2010,015E) in cd/m² — the viewing-condition input a
    /// Presentation LUT printer uses. Optional on the SCU side (PS3.4 Table H.4-6);
    /// when nil the printer assumes its default (2000 cd/m² transmissive,
    /// 150 cd/m² reflective). Sent only when a Presentation LUT is referenced.
    public let illumination: UInt16?

    /// Reflected Ambient Light (2010,0160) in cd/m² — companion to ``illumination``
    /// (printer default 10 cd/m²). Sent only when a Presentation LUT is referenced.
    public let reflectedAmbientLight: UInt16?

    /// Creates print options with specified parameters
    public init(
        numberOfCopies: Int = 1,
        priority: PrintPriority = .medium,
        filmSize: FilmSize = .size8InX10In,
        filmOrientation: FilmOrientation = .portrait,
        mediumType: MediumType = .clearFilm,
        filmDestination: FilmDestination = .processor,
        borderDensity: String = "BLACK",
        emptyImageDensity: String = "BLACK",
        magnificationType: MagnificationType = .replicate,
        polarity: ImagePolarity = .normal,
        trimOption: TrimOption = .no,
        sessionLabel: String? = nil,
        presentationLUTShape: PresentationLUTShape? = nil,
        presentationLUTTable: PresentationLUTTable? = nil,
        annotations: [PrintAnnotation] = [],
        annotationDisplayFormatID: String? = nil,
        configurationInformation: String? = nil,
        filmAnnotations: [[PrintAnnotation]] = [],
        imageBoxOptions: [PrintImageBoxOptions] = [],
        illumination: UInt16? = nil,
        reflectedAmbientLight: UInt16? = nil
    ) {
        self.illumination = illumination
        self.reflectedAmbientLight = reflectedAmbientLight
        self.numberOfCopies = numberOfCopies
        self.priority = priority
        self.filmSize = filmSize
        self.filmOrientation = filmOrientation
        self.mediumType = mediumType
        self.filmDestination = filmDestination
        self.borderDensity = borderDensity
        self.emptyImageDensity = emptyImageDensity
        self.magnificationType = magnificationType
        self.polarity = polarity
        self.trimOption = trimOption
        self.sessionLabel = sessionLabel
        self.presentationLUTShape = presentationLUTShape
        self.presentationLUTTable = presentationLUTTable
        self.annotations = annotations
        self.annotationDisplayFormatID = annotationDisplayFormatID
        self.configurationInformation = configurationInformation
        self.filmAnnotations = filmAnnotations
        self.imageBoxOptions = imageBoxOptions
    }

    /// The scaling attributes for one image, by its 0-based job-wide index.
    public func imageBoxOptions(forImage index: Int) -> PrintImageBoxOptions {
        guard index >= 0, index < imageBoxOptions.count else { return PrintImageBoxOptions() }
        return imageBoxOptions[index]
    }

    /// These options with per-image scaling attributes attached — how a caller
    /// adds them once the images (whose pixel spacing they need) are prepared.
    public func withImageBoxOptions(_ boxOptions: [PrintImageBoxOptions]) -> PrintOptions {
        PrintOptions(
            numberOfCopies: numberOfCopies,
            priority: priority,
            filmSize: filmSize,
            filmOrientation: filmOrientation,
            mediumType: mediumType,
            filmDestination: filmDestination,
            borderDensity: borderDensity,
            emptyImageDensity: emptyImageDensity,
            magnificationType: magnificationType,
            polarity: polarity,
            trimOption: trimOption,
            sessionLabel: sessionLabel,
            presentationLUTShape: presentationLUTShape,
            presentationLUTTable: presentationLUTTable,
            annotations: annotations,
            annotationDisplayFormatID: annotationDisplayFormatID,
            configurationInformation: configurationInformation,
            filmAnnotations: filmAnnotations,
            imageBoxOptions: boxOptions)
    }

    /// The annotations one film carries: its own when it has any, else the
    /// job-wide set.
    public func annotations(forFilm filmIndex: Int) -> [PrintAnnotation] {
        guard filmIndex >= 0, filmIndex < filmAnnotations.count,
              !filmAnnotations[filmIndex].isEmpty else { return annotations }
        return filmAnnotations[filmIndex]
    }

    /// Whether any film in this job carries annotation text.
    public var hasAnnotations: Bool {
        !annotations.isEmpty || filmAnnotations.contains { !$0.isEmpty }
    }
    
    /// Default print options for general use
    ///
    /// Uses standard settings suitable for most print jobs:
    /// - Single copy
    /// - Medium priority
    /// - 8x10 inch film
    /// - Portrait orientation
    /// - Clear film medium
    public static let `default` = PrintOptions()
    
    /// High quality print options
    ///
    /// Uses settings optimized for best print quality:
    /// - Bilinear magnification
    /// - Clear film medium
    /// - High priority
    public static let highQuality = PrintOptions(
        priority: .high,
        filmSize: .size14InX17In,
        mediumType: .clearFilm,
        magnificationType: .bilinear
    )
    
    /// Draft print options for quick previews
    ///
    /// Uses settings optimized for fast printing:
    /// - Paper medium
    /// - Low priority
    /// - Smaller film size
    public static let draft = PrintOptions(
        priority: .low,
        filmSize: .size8_5InX11In,
        mediumType: .paper,
        magnificationType: .replicate
    )
    
    /// Mammography print options
    ///
    /// Uses settings suitable for mammography:
    /// - Mammography blue film (MAMMO BLUE FILM, PS3.3 Table C.13-1)
    /// - High priority
    /// - Large film size
    public static let mammography = PrintOptions(
        priority: .high,
        filmSize: .size14InX17In,
        mediumType: .mammoBlueFilm,
        magnificationType: .bilinear
    )
}

// MARK: - Print Layout

/// Represents a print layout (rows x columns)
public struct PrintLayout: Sendable, Equatable, Codable {
    /// Number of rows in the layout
    public let rows: Int
    
    /// Number of columns in the layout
    public let columns: Int
    
    /// Total number of image positions
    public var imageCount: Int {
        rows * columns
    }
    
    /// Image Display Format (2010,0010) string for DICOM.
    ///
    /// PS3.3 C.13.3 defines the STANDARD form as `STANDARD\C,R` — **columns
    /// first, then rows**. Every place that builds this attribute derives it
    /// from here so the order can never drift again.
    public var imageDisplayFormat: String {
        "STANDARD\\\(columns),\(rows)"
    }
    
    /// Creates a print layout with the specified dimensions
    public init(rows: Int, columns: Int) {
        self.rows = max(1, rows)
        self.columns = max(1, columns)
    }
    
    /// Determines the optimal layout for a given number of images
    ///
    /// - Parameter imageCount: Number of images to fit
    /// - Returns: The optimal layout
    public static func optimalLayout(for imageCount: Int) -> PrintLayout {
        switch imageCount {
        case 1:
            return PrintLayout(rows: 1, columns: 1)
        case 2:
            return PrintLayout(rows: 1, columns: 2)
        case 3, 4:
            return PrintLayout(rows: 2, columns: 2)
        case 5, 6:
            return PrintLayout(rows: 2, columns: 3)
        case 7, 8, 9:
            return PrintLayout(rows: 3, columns: 3)
        case 10, 11, 12:
            return PrintLayout(rows: 3, columns: 4)
        case 13, 14, 15, 16:
            return PrintLayout(rows: 4, columns: 4)
        case 17...20:
            return PrintLayout(rows: 4, columns: 5)
        default:
            // For more than 20 images, use 5x5 layout
            return PrintLayout(rows: 5, columns: 5)
        }
    }
    
    /// Standard single image layout (1x1)
    public static let singleImage = PrintLayout(rows: 1, columns: 1)
    
    /// Standard comparison layout (1x2)
    public static let comparison = PrintLayout(rows: 1, columns: 2)
    
    /// Standard 2x2 grid layout
    public static let grid2x2 = PrintLayout(rows: 2, columns: 2)
    
    /// Standard 3x3 grid layout
    public static let grid3x3 = PrintLayout(rows: 3, columns: 3)
    
    /// Standard 4x4 grid layout
    public static let grid4x4 = PrintLayout(rows: 4, columns: 4)
    
    /// Multi-phase layout (2x3)
    public static let multiPhase2x3 = PrintLayout(rows: 2, columns: 3)
    
    /// Multi-phase layout (3x4)
    public static let multiPhase3x4 = PrintLayout(rows: 3, columns: 4)
}

// MARK: - Print Progress

/// Progress information for print operations
public struct PrintProgress: Sendable {
    /// Phase of the print operation
    public enum Phase: Sendable, Equatable {
        /// Connecting to print server
        case connecting
        /// Querying printer status
        case queryingPrinter
        /// Creating print session
        case creatingSession
        /// Preparing images for printing
        case preparingImages
        /// Uploading images to printer
        case uploadingImages(current: Int, total: Int)
        /// Sending print command
        case printing
        /// Cleaning up session
        case cleanup
        /// Print operation completed
        case completed
    }
    
    /// Current phase of the operation
    public let phase: Phase
    
    /// Progress value from 0.0 to 1.0
    public let progress: Double
    
    /// Human-readable progress message
    public let message: String
    
    /// Creates a progress update
    public init(phase: Phase, progress: Double, message: String) {
        self.phase = phase
        self.progress = max(0.0, min(1.0, progress))
        self.message = message
    }
}

// MARK: - Print Template Protocol

/// Protocol for defining reusable print layouts
///
/// Print templates encapsulate common print configurations that can be
/// reused across different print jobs. Templates define the layout,
/// film size, and other parameters.
public protocol PrintTemplate: Sendable {
    /// Template name
    var name: String { get }
    
    /// Template description
    var description: String { get }
    
    /// Preferred film size for this template
    var filmSize: FilmSize { get }
    
    /// Image display format (e.g., "STANDARD\\2,2")
    var imageDisplayFormat: String { get }
    
    /// Number of images this template can hold
    var imageCount: Int { get }
    
    /// Preferred film orientation
    var filmOrientation: FilmOrientation { get }
    
    /// Creates a FilmBox configured with this template's settings
    func createFilmBox() -> FilmBox
}

// MARK: - Built-in Print Templates

/// Single image print template (1x1)
public struct SingleImageTemplate: PrintTemplate {
    public let name = "Single Image"
    public let description = "Single image fills entire film"
    public let filmSize: FilmSize
    public let imageDisplayFormat = "STANDARD\\1,1"
    public let imageCount = 1
    public let filmOrientation: FilmOrientation
    
    public init(filmSize: FilmSize = .size8InX10In, filmOrientation: FilmOrientation = .portrait) {
        self.filmSize = filmSize
        self.filmOrientation = filmOrientation
    }
    
    public func createFilmBox() -> FilmBox {
        FilmBox(
            imageDisplayFormat: imageDisplayFormat,
            filmOrientation: filmOrientation,
            filmSizeID: filmSize
        )
    }
}

/// Comparison template (1x2) for side-by-side comparison
public struct ComparisonTemplate: PrintTemplate {
    public let name = "Comparison"
    public let description = "Two images side by side for comparison"
    public let filmSize: FilmSize
    public let imageDisplayFormat = PrintLayout(rows: 1, columns: 2).imageDisplayFormat
    public let imageCount = 2
    public let filmOrientation: FilmOrientation
    
    public init(filmSize: FilmSize = .size11InX14In, filmOrientation: FilmOrientation = .landscape) {
        self.filmSize = filmSize
        self.filmOrientation = filmOrientation
    }
    
    public func createFilmBox() -> FilmBox {
        FilmBox(
            imageDisplayFormat: imageDisplayFormat,
            filmOrientation: filmOrientation,
            filmSizeID: filmSize
        )
    }
}

/// Grid template for configurable row/column layouts
public struct GridTemplate: PrintTemplate {
    public let name: String
    public let description: String
    public let filmSize: FilmSize
    public let imageDisplayFormat: String
    public let imageCount: Int
    public let filmOrientation: FilmOrientation
    private let rows: Int
    private let columns: Int
    
    public init(rows: Int, columns: Int, filmSize: FilmSize = .size14InX17In, filmOrientation: FilmOrientation = .portrait) {
        self.rows = max(1, rows)
        self.columns = max(1, columns)
        self.name = "\(self.rows)x\(self.columns) Grid"
        self.description = "\(self.rows * self.columns) images in a \(self.rows)x\(self.columns) grid"
        self.filmSize = filmSize
        self.imageDisplayFormat = PrintLayout(rows: self.rows, columns: self.columns).imageDisplayFormat
        self.imageCount = self.rows * self.columns
        self.filmOrientation = filmOrientation
    }
    
    public func createFilmBox() -> FilmBox {
        FilmBox(
            imageDisplayFormat: imageDisplayFormat,
            filmOrientation: filmOrientation,
            filmSizeID: filmSize
        )
    }
}

/// Multi-phase template for temporal series (e.g., 3x4 for multi-phase CT)
public struct MultiPhaseTemplate: PrintTemplate {
    public let name: String
    public let description: String
    public let filmSize: FilmSize
    public let imageDisplayFormat: String
    public let imageCount: Int
    public let filmOrientation: FilmOrientation
    private let rows: Int
    private let columns: Int
    
    public init(rows: Int, columns: Int, filmSize: FilmSize = .size14InX17In, filmOrientation: FilmOrientation = .portrait) {
        self.rows = max(1, rows)
        self.columns = max(1, columns)
        self.name = "Multi-Phase \(self.rows)x\(self.columns)"
        self.description = "Multi-phase layout with \(self.rows * self.columns) images (\(self.rows) rows × \(self.columns) columns)"
        self.filmSize = filmSize
        self.imageDisplayFormat = PrintLayout(rows: self.rows, columns: self.columns).imageDisplayFormat
        self.imageCount = self.rows * self.columns
        self.filmOrientation = filmOrientation
    }
    
    public func createFilmBox() -> FilmBox {
        FilmBox(
            imageDisplayFormat: imageDisplayFormat,
            filmOrientation: filmOrientation,
            filmSizeID: filmSize
        )
    }
}

// MARK: - Convenience Template Extensions

extension PrintTemplate where Self == SingleImageTemplate {
    /// Single image template with default settings
    public static var singleImage: SingleImageTemplate {
        SingleImageTemplate()
    }
}

extension PrintTemplate where Self == ComparisonTemplate {
    /// Comparison template with default settings
    public static var comparison: ComparisonTemplate {
        ComparisonTemplate()
    }
}

extension PrintTemplate where Self == GridTemplate {
    /// 2x2 grid template
    public static var grid2x2: GridTemplate {
        GridTemplate(rows: 2, columns: 2)
    }
    
    /// 3x3 grid template
    public static var grid3x3: GridTemplate {
        GridTemplate(rows: 3, columns: 3)
    }
    
    /// 4x4 grid template
    public static var grid4x4: GridTemplate {
        GridTemplate(rows: 4, columns: 4)
    }
}

extension PrintTemplate where Self == MultiPhaseTemplate {
    /// Multi-phase 2x3 template
    public static var multiPhase2x3: MultiPhaseTemplate {
        MultiPhaseTemplate(rows: 2, columns: 3)
    }
    
    /// Multi-phase 3x4 template
    public static var multiPhase3x4: MultiPhaseTemplate {
        MultiPhaseTemplate(rows: 3, columns: 4)
    }
    
    /// Multi-phase 4x5 template
    public static var multiPhase4x5: MultiPhaseTemplate {
        MultiPhaseTemplate(rows: 4, columns: 5)
    }
}

// MARK: - Print Retry Policy

/// Policy for retrying print operations
public struct PrintRetryPolicy: Sendable {
    /// Maximum number of retry attempts
    public let maxAttempts: Int
    
    /// Initial delay before first retry (in seconds)
    public let initialDelay: TimeInterval
    
    /// Multiplier for exponential backoff
    public let backoffMultiplier: Double
    
    /// Maximum delay between retries (in seconds)
    public let maxDelay: TimeInterval
    
    /// Creates a retry policy with specified parameters
    public init(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        backoffMultiplier: Double = 2.0,
        maxDelay: TimeInterval = 30.0
    ) {
        self.maxAttempts = max(0, maxAttempts)
        self.initialDelay = max(0, initialDelay)
        self.backoffMultiplier = max(1.0, backoffMultiplier)
        self.maxDelay = max(max(0, maxDelay), self.initialDelay)
    }
    
    /// Calculates the delay for a given attempt number
    /// - Parameter attempt: The attempt number (0-based)
    /// - Returns: The delay in seconds
    public func delay(for attempt: Int) -> TimeInterval {
        guard attempt >= 0 else { return initialDelay }
        let delay = initialDelay * pow(backoffMultiplier, Double(attempt))
        return min(delay, maxDelay)
    }
    
    /// Default retry policy
    public static let `default` = PrintRetryPolicy()
    
    /// Aggressive retry policy for critical prints
    public static let aggressive = PrintRetryPolicy(
        maxAttempts: 5,
        initialDelay: 0.5,
        backoffMultiplier: 1.5,
        maxDelay: 10.0
    )
    
    /// No retry policy
    public static let none = PrintRetryPolicy(maxAttempts: 0)
}

// MARK: - Phase 4: Print Job

/// Represents a print job in the queue
///
/// Print jobs contain all information needed to execute a print operation,
/// including the printer configuration, images to print, and options.
public struct PrintJob: Sendable, Identifiable {
    /// Unique identifier for this job
    public let id: UUID
    
    /// Printer configuration
    public let configuration: PrintConfiguration
    
    /// File URLs for images to print
    public let imageURLs: [URL]
    
    /// Print options
    public let options: PrintOptions
    
    /// Job priority
    public let priority: PrintPriority
    
    /// Date when job was created
    public let createdAt: Date
    
    /// Optional label for the job
    public let label: String?
    
    /// Creates a new print job
    public init(
        id: UUID = UUID(),
        configuration: PrintConfiguration,
        imageURLs: [URL],
        options: PrintOptions = .default,
        priority: PrintPriority = .medium,
        createdAt: Date = Date(),
        label: String? = nil
    ) {
        self.id = id
        self.configuration = configuration
        self.imageURLs = imageURLs
        self.options = options
        self.priority = priority
        self.createdAt = createdAt
        self.label = label
    }
}

// MARK: - Print Job Record

/// Record of a completed print job for history tracking
public struct PrintJobRecord: Sendable, Identifiable {
    /// Unique identifier (matches the original job)
    public let id: UUID
    
    /// Job label
    public let label: String?
    
    /// Number of images printed
    public let imageCount: Int
    
    /// Date when job was submitted
    public let submittedAt: Date
    
    /// Date when job completed
    public let completedAt: Date
    
    /// Whether the job completed successfully
    public let success: Bool
    
    /// Error message if the job failed
    public let errorMessage: String?
    
    /// Printer name that processed the job
    public let printerName: String?
    
    public init(
        id: UUID,
        label: String?,
        imageCount: Int,
        submittedAt: Date,
        completedAt: Date,
        success: Bool,
        errorMessage: String? = nil,
        printerName: String? = nil
    ) {
        self.id = id
        self.label = label
        self.imageCount = imageCount
        self.submittedAt = submittedAt
        self.completedAt = completedAt
        self.success = success
        self.errorMessage = errorMessage
        self.printerName = printerName
    }
}

// MARK: - Print Queue Status

/// Status of a job in the print queue
public enum PrintQueueJobStatus: Sendable, Equatable {
    /// Job is waiting to be processed
    case queued(position: Int)
    
    /// Job is currently being processed
    case processing
    
    /// Job completed successfully
    case completed
    
    /// Job failed with an error
    case failed(message: String)
    
    /// Job was cancelled
    case cancelled
}

// MARK: - Print Queue

/// Actor for managing a queue of print jobs
///
/// The print queue provides:
/// - Priority-based scheduling
/// - Concurrent job processing (for multiple printers)
/// - Job history tracking
/// - Automatic retry on failure
public actor PrintQueue {
    /// Queued jobs sorted by priority and creation time
    private var queue: [PrintJob] = []
    
    /// Currently processing job IDs
    private var processing: Set<UUID> = []
    
    /// Completed job records
    private var history: [PrintJobRecord] = []
    
    /// Maximum number of history records to keep
    private let maxHistorySize: Int
    
    /// Retry policy for failed jobs
    private let retryPolicy: PrintRetryPolicy
    
    /// Retry counts for jobs
    private var retryCounts: [UUID: Int] = [:]
    
    /// Creates a new print queue
    /// - Parameters:
    ///   - maxHistorySize: Maximum history records (default 100)
    ///   - retryPolicy: Policy for retrying failed jobs
    public init(maxHistorySize: Int = 100, retryPolicy: PrintRetryPolicy = .default) {
        self.maxHistorySize = maxHistorySize
        self.retryPolicy = retryPolicy
    }
    
    // MARK: - Queue Operations
    
    /// Adds a job to the queue
    /// - Parameter job: The job to enqueue
    /// - Returns: The job ID
    @discardableResult
    public func enqueue(job: PrintJob) -> UUID {
        queue.append(job)
        sortQueue()
        return job.id
    }
    
    /// Retrieves and removes the next job from the queue
    /// - Returns: The next job to process, or nil if queue is empty
    public func dequeue() -> PrintJob? {
        guard !queue.isEmpty else { return nil }
        let job = queue.removeFirst()
        processing.insert(job.id)
        return job
    }
    
    /// Peeks at the next job without removing it
    /// - Returns: The next job, or nil if queue is empty
    public func peek() -> PrintJob? {
        queue.first
    }
    
    /// Cancels a queued job
    /// - Parameter jobID: ID of the job to cancel
    /// - Returns: True if the job was found and cancelled
    @discardableResult
    public func cancel(jobID: UUID) -> Bool {
        if let index = queue.firstIndex(where: { $0.id == jobID }) {
            let job = queue.remove(at: index)
            
            // Record as cancelled
            let record = PrintJobRecord(
                id: job.id,
                label: job.label,
                imageCount: job.imageURLs.count,
                submittedAt: job.createdAt,
                completedAt: Date(),
                success: false,
                errorMessage: "Cancelled by user"
            )
            addToHistory(record)
            
            return true
        }
        return false
    }
    
    /// Reports that a job completed successfully
    /// - Parameters:
    ///   - jobID: ID of the completed job
    ///   - printerName: Name of the printer that processed the job
    public func markCompleted(jobID: UUID, printerName: String? = nil) {
        processing.remove(jobID)
        retryCounts.removeValue(forKey: jobID)
        
        // Find job details for history (might be nil if already removed)
        // Create a record with available information
        let record = PrintJobRecord(
            id: jobID,
            label: nil,
            imageCount: 0,
            submittedAt: Date(),
            completedAt: Date(),
            success: true,
            printerName: printerName
        )
        addToHistory(record)
    }
    
    /// Reports that a job failed
    /// - Parameters:
    ///   - jobID: ID of the failed job
    ///   - error: The error that caused the failure
    ///   - job: The original job (for retry)
    /// - Returns: True if the job will be retried
    @discardableResult
    public func markFailed(jobID: UUID, error: Error, job: PrintJob? = nil) -> Bool {
        processing.remove(jobID)
        
        let retryCount = retryCounts[jobID] ?? 0
        
        // Check if we should retry
        if retryCount < retryPolicy.maxAttempts, let job = job {
            retryCounts[jobID] = retryCount + 1
            // Re-queue the job
            queue.append(job)
            sortQueue()
            return true
        }
        
        // No more retries - record as failed
        retryCounts.removeValue(forKey: jobID)
        
        let record = PrintJobRecord(
            id: jobID,
            label: job?.label,
            imageCount: job?.imageURLs.count ?? 0,
            submittedAt: job?.createdAt ?? Date(),
            completedAt: Date(),
            success: false,
            errorMessage: error.localizedDescription
        )
        addToHistory(record)
        
        return false
    }
    
    // MARK: - Queue Status
    
    /// Gets the status of a specific job
    /// - Parameter jobID: ID of the job
    /// - Returns: The job status, or nil if not found
    public func status(jobID: UUID) -> PrintQueueJobStatus? {
        if processing.contains(jobID) {
            return .processing
        }
        
        if let position = queue.firstIndex(where: { $0.id == jobID }) {
            return .queued(position: position + 1)
        }
        
        if let record = history.first(where: { $0.id == jobID }) {
            if record.success {
                return .completed
            } else if record.errorMessage == "Cancelled by user" {
                return .cancelled
            } else {
                return .failed(message: record.errorMessage ?? "Unknown error")
            }
        }
        
        return nil
    }
    
    /// Number of jobs in the queue
    public var queuedCount: Int {
        queue.count
    }
    
    /// Number of jobs currently being processed
    public var processingCount: Int {
        processing.count
    }
    
    /// Whether the queue is empty
    public var isEmpty: Bool {
        queue.isEmpty
    }
    
    /// Gets a copy of all queued jobs
    public func allQueuedJobs() -> [PrintJob] {
        queue
    }
    
    // MARK: - History
    
    /// Gets print history
    /// - Parameter limit: Maximum number of records to return
    /// - Returns: Recent print job records (most recent first)
    public func getHistory(limit: Int = 50) -> [PrintJobRecord] {
        let count = min(limit, history.count)
        return Array(history.prefix(count))
    }
    
    /// Clears the print history
    public func clearHistory() {
        history.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func sortQueue() {
        // Sort by priority (high first) then by creation time (oldest first)
        queue.sort { job1, job2 in
            if job1.priority != job2.priority {
                return priorityValue(job1.priority) > priorityValue(job2.priority)
            }
            return job1.createdAt < job2.createdAt
        }
    }
    
    private func priorityValue(_ priority: PrintPriority) -> Int {
        switch priority {
        case .high: return 2
        case .medium: return 1
        case .low: return 0
        }
    }
    
    private func addToHistory(_ record: PrintJobRecord) {
        history.insert(record, at: 0)
        
        // Trim history if needed
        if history.count > maxHistorySize {
            history = Array(history.prefix(maxHistorySize))
        }
    }
}

// MARK: - Printer Capabilities

/// Capabilities of a DICOM printer
public struct PrinterCapabilities: Sendable, Equatable {
    /// Supported film sizes
    public let supportedFilmSizes: [FilmSize]
    
    /// Whether the printer supports color
    public let supportsColor: Bool
    
    /// Maximum number of copies per print job
    public let maxCopies: Int
    
    /// Supported medium types
    public let supportedMediumTypes: [MediumType]
    
    /// Supported magnification types
    public let supportedMagnificationTypes: [MagnificationType]
    
    /// Maximum images per film box
    public let maxImagesPerFilmBox: Int
    
    public init(
        supportedFilmSizes: [FilmSize] = FilmSize.allCases,
        supportsColor: Bool = true,
        maxCopies: Int = 99,
        supportedMediumTypes: [MediumType] = MediumType.allCases,
        supportedMagnificationTypes: [MagnificationType] = MagnificationType.allCases,
        maxImagesPerFilmBox: Int = 25
    ) {
        self.supportedFilmSizes = supportedFilmSizes
        self.supportsColor = supportsColor
        self.maxCopies = maxCopies
        self.supportedMediumTypes = supportedMediumTypes
        self.supportedMagnificationTypes = supportedMagnificationTypes
        self.maxImagesPerFilmBox = maxImagesPerFilmBox
    }
    
    /// Default capabilities (assumes full feature support)
    public static let `default` = PrinterCapabilities()
}

// MARK: - Printer Info

/// Information about a configured DICOM printer
public struct PrinterInfo: Sendable, Identifiable, Equatable {
    /// Unique identifier for this printer
    public let id: UUID
    
    /// Human-readable printer name
    public let name: String
    
    /// Connection configuration
    public let configuration: PrintConfiguration
    
    /// Printer capabilities
    public let capabilities: PrinterCapabilities
    
    /// Whether this is the default printer
    public var isDefault: Bool
    
    /// Whether the printer is currently available
    public var isAvailable: Bool
    
    /// Last time the printer was successfully contacted
    public var lastSeenAt: Date?
    
    public init(
        id: UUID = UUID(),
        name: String,
        configuration: PrintConfiguration,
        capabilities: PrinterCapabilities = .default,
        isDefault: Bool = false,
        isAvailable: Bool = true,
        lastSeenAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.configuration = configuration
        self.capabilities = capabilities
        self.isDefault = isDefault
        self.isAvailable = isAvailable
        self.lastSeenAt = lastSeenAt
    }
    
    public static func == (lhs: PrinterInfo, rhs: PrinterInfo) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Printer Registry

/// Actor for managing multiple DICOM printers
///
/// The printer registry provides:
/// - Printer discovery and registration
/// - Health checks and availability tracking
/// - Default printer selection
/// - Load balancing across printers
public actor PrinterRegistry {
    /// Registered printers
    private var printers: [UUID: PrinterInfo] = [:]
    
    /// ID of the default printer
    private var defaultPrinterID: UUID?
    
    /// Creates a new printer registry
    public init() {}
    
    // MARK: - Printer Management
    
    /// Adds a printer to the registry
    /// - Parameter printer: Printer information
    /// - Throws: PrinterRegistryError if a printer with the same ID exists
    public func addPrinter(_ printer: PrinterInfo) throws {
        guard printers[printer.id] == nil else {
            throw PrinterRegistryError.printerAlreadyExists(id: printer.id)
        }
        
        var info = printer
        
        // If this is the first printer or marked as default, set as default
        if printers.isEmpty || printer.isDefault {
            // Clear previous default
            if let prevDefaultID = defaultPrinterID {
                printers[prevDefaultID]?.isDefault = false
            }
            defaultPrinterID = printer.id
            info.isDefault = true
        }
        
        printers[printer.id] = info
    }
    
    /// Removes a printer from the registry
    /// - Parameter id: ID of the printer to remove
    /// - Returns: The removed printer info, or nil if not found
    @discardableResult
    public func removePrinter(id: UUID) -> PrinterInfo? {
        let removed = printers.removeValue(forKey: id)
        
        // If we removed the default, select a new default
        if id == defaultPrinterID {
            defaultPrinterID = printers.keys.first
            if let newDefaultID = defaultPrinterID {
                printers[newDefaultID]?.isDefault = true
            }
        }
        
        return removed
    }
    
    /// Updates a printer in the registry
    /// - Parameter printer: Updated printer information
    /// - Throws: PrinterRegistryError if printer not found
    public func updatePrinter(_ printer: PrinterInfo) throws {
        guard printers[printer.id] != nil else {
            throw PrinterRegistryError.printerNotFound(id: printer.id)
        }
        
        var info = printer
        
        // Handle default printer logic
        if printer.isDefault && defaultPrinterID != printer.id {
            // Clear previous default
            if let prevDefaultID = defaultPrinterID {
                printers[prevDefaultID]?.isDefault = false
            }
            defaultPrinterID = printer.id
        } else if !printer.isDefault && defaultPrinterID == printer.id {
            // Can't unset default without setting another - keep it default
            info.isDefault = true
        }
        
        printers[printer.id] = info
    }
    
    /// Gets a printer by ID
    /// - Parameter id: Printer ID
    /// - Returns: Printer info, or nil if not found
    public func printer(id: UUID) -> PrinterInfo? {
        printers[id]
    }
    
    /// Gets a printer by name
    /// - Parameter name: Printer name
    /// - Returns: Printer info, or nil if not found
    public func printer(named name: String) -> PrinterInfo? {
        printers.values.first { $0.name == name }
    }
    
    // MARK: - Listing
    
    /// Lists all registered printers
    /// - Returns: Array of printer info
    public func listPrinters() -> [PrinterInfo] {
        Array(printers.values)
    }
    
    /// Lists available printers (currently online)
    /// - Returns: Array of available printer info
    public func listAvailablePrinters() -> [PrinterInfo] {
        printers.values.filter { $0.isAvailable }
    }
    
    /// Number of registered printers
    public var count: Int {
        printers.count
    }
    
    // MARK: - Default Printer
    
    /// Gets the default printer
    /// - Returns: Default printer info, or nil if no printers registered
    public func defaultPrinter() -> PrinterInfo? {
        guard let id = defaultPrinterID else { return nil }
        return printers[id]
    }
    
    /// Sets the default printer
    /// - Parameter id: ID of the printer to set as default
    /// - Throws: PrinterRegistryError if printer not found
    public func setDefaultPrinter(id: UUID) throws {
        guard printers[id] != nil else {
            throw PrinterRegistryError.printerNotFound(id: id)
        }
        
        // Clear previous default
        if let prevDefaultID = defaultPrinterID {
            printers[prevDefaultID]?.isDefault = false
        }
        
        printers[id]?.isDefault = true
        defaultPrinterID = id
    }
    
    // MARK: - Availability
    
    /// Updates the availability status of a printer
    /// - Parameters:
    ///   - id: Printer ID
    ///   - isAvailable: Whether the printer is available
    public func updateAvailability(id: UUID, isAvailable: Bool) {
        printers[id]?.isAvailable = isAvailable
        if isAvailable {
            printers[id]?.lastSeenAt = Date()
        }
    }
    
    /// Marks a printer as seen (updates lastSeenAt)
    /// - Parameter id: Printer ID
    public func markSeen(id: UUID) {
        printers[id]?.lastSeenAt = Date()
        printers[id]?.isAvailable = true
    }
    
    // MARK: - Load Balancing
    
    /// Selects the best available printer for a job
    ///
    /// Selection criteria:
    /// 1. Must be available
    /// 2. Must support required capabilities
    /// 3. Prefers default printer if available
    ///
    /// - Parameters:
    ///   - requiresColor: Whether the job requires color printing
    ///   - filmSize: Required film size
    /// - Returns: Best printer for the job, or nil if none suitable
    public func selectPrinter(requiresColor: Bool = false, filmSize: FilmSize? = nil) -> PrinterInfo? {
        let available = printers.values.filter { $0.isAvailable }
        
        guard !available.isEmpty else { return nil }
        
        // Filter by capabilities
        let suitable = available.filter { printer in
            // Check color support
            if requiresColor && !printer.capabilities.supportsColor {
                return false
            }
            
            // Check film size support
            if let size = filmSize, !printer.capabilities.supportedFilmSizes.contains(size) {
                return false
            }
            
            return true
        }
        
        // Prefer default printer if it's suitable
        if let defaultID = defaultPrinterID,
           let defaultPrinter = suitable.first(where: { $0.id == defaultID }) {
            return defaultPrinter
        }
        
        // Return first suitable printer
        return suitable.first
    }
}

// MARK: - Printer Registry Error

/// Errors that can occur in printer registry operations
public enum PrinterRegistryError: Error, CustomStringConvertible, Equatable {
    /// Printer with the specified ID already exists
    case printerAlreadyExists(id: UUID)
    
    /// Printer with the specified ID was not found
    case printerNotFound(id: UUID)
    
    /// No suitable printer available for the job
    case noPrinterAvailable
    
    public var description: String {
        switch self {
        case .printerAlreadyExists(let id):
            return "Printer already exists: \(id)"
        case .printerNotFound(let id):
            return "Printer not found: \(id)"
        case .noPrinterAvailable:
            return "No suitable printer available"
        }
    }
}

// MARK: - Print Error (Phase 4.3)

/// Detailed error types for print operations
public enum PrintError: Error, CustomStringConvertible, Equatable {
    /// Printer is unavailable or offline
    case printerUnavailable(message: String)
    
    /// Failed to create film session
    case filmSessionCreationFailed(statusCode: UInt16)
    
    /// Failed to create film box
    case filmBoxCreationFailed(statusCode: UInt16)
    
    /// Failed to set image box content
    case imageBoxSetFailed(position: Int, statusCode: UInt16)
    
    /// Print job execution failed
    case printJobFailed(status: String, info: String?)
    
    /// Operation timed out
    case timeout(operation: String)
    
    /// Invalid configuration
    case invalidConfiguration(reason: String)
    
    /// Image preparation failed
    case imagePreparationFailed(reason: String)
    
    /// Network error
    case networkError(message: String)
    
    /// Queue is full
    case queueFull(maxSize: Int)
    
    public var description: String {
        switch self {
        case .printerUnavailable(let message):
            return "Printer unavailable: \(message)"
        case .filmSessionCreationFailed(let statusCode):
            return "Failed to create film session (status: 0x\(String(statusCode, radix: 16, uppercase: true)))"
        case .filmBoxCreationFailed(let statusCode):
            return "Failed to create film box (status: 0x\(String(statusCode, radix: 16, uppercase: true)))"
        case .imageBoxSetFailed(let position, let statusCode):
            return "Failed to set image at position \(position) (status: 0x\(String(statusCode, radix: 16, uppercase: true)))"
        case .printJobFailed(let status, let info):
            if let info = info {
                return "Print job failed: \(status) - \(info)"
            }
            return "Print job failed: \(status)"
        case .timeout(let operation):
            return "Operation timed out: \(operation)"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        case .imagePreparationFailed(let reason):
            return "Image preparation failed: \(reason)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .queueFull(let maxSize):
            return "Print queue is full (maximum \(maxSize) jobs)"
        }
    }
    
    /// Suggested recovery action for this error
    public var recoverySuggestion: String {
        switch self {
        case .printerUnavailable:
            return "Check that the printer is powered on and connected to the network. Verify the printer address and port."
        case .filmSessionCreationFailed:
            return "The printer may be busy or have insufficient resources. Try again later or check printer status."
        case .filmBoxCreationFailed:
            return "Verify that the film size and layout are supported by the printer."
        case .imageBoxSetFailed:
            return "Check that the image format is compatible with the printer. Try reducing image complexity."
        case .printJobFailed:
            return "Check the printer status for paper/film jams or other hardware issues."
        case .timeout:
            return "Increase the timeout value or check network connectivity."
        case .invalidConfiguration:
            return "Review and correct the printer configuration settings."
        case .imagePreparationFailed:
            return "Verify that the DICOM image is valid and contains pixel data."
        case .networkError:
            return "Check network connectivity and firewall settings."
        case .queueFull:
            return "Wait for current jobs to complete or cancel pending jobs."
        }
    }
}

// MARK: - Partial Print Result

/// Result of a print operation that may have partially succeeded
public struct PartialPrintResult: Sendable {
    /// Number of images that printed successfully
    public let successCount: Int
    
    /// Number of images that failed to print
    public let failureCount: Int
    
    /// Positions of images that failed (1-based)
    public let failedPositions: [Int]
    
    /// Errors that occurred during printing
    public let errors: [PrintError]
    
    /// Film session UID (if created)
    public let filmSessionUID: String?
    
    /// Print job UID (if created)
    public let printJobUID: String?
    
    /// Overall success status
    public var isFullySuccessful: Bool {
        failureCount == 0
    }
    
    /// Overall failure status
    public var isFullyFailed: Bool {
        successCount == 0 && failureCount > 0
    }
    
    /// Partial success status
    public var isPartiallySuccessful: Bool {
        successCount > 0 && failureCount > 0
    }
    
    public init(
        successCount: Int,
        failureCount: Int,
        failedPositions: [Int] = [],
        errors: [PrintError] = [],
        filmSessionUID: String? = nil,
        printJobUID: String? = nil
    ) {
        self.successCount = successCount
        self.failureCount = failureCount
        self.failedPositions = failedPositions
        self.errors = errors
        self.filmSessionUID = filmSessionUID
        self.printJobUID = printJobUID
    }
    
    /// Creates a successful result
    public static func success(count: Int, filmSessionUID: String? = nil, printJobUID: String? = nil) -> PartialPrintResult {
        PartialPrintResult(
            successCount: count,
            failureCount: 0,
            filmSessionUID: filmSessionUID,
            printJobUID: printJobUID
        )
    }
    
    /// Creates a failed result
    public static func failure(count: Int, error: PrintError) -> PartialPrintResult {
        PartialPrintResult(
            successCount: 0,
            failureCount: count,
            failedPositions: Array(1...count),
            errors: [error]
        )
    }
}

#if canImport(Network)

// MARK: - DICOM Print Service

/// DICOM Print Management Service (PS3.4 Annex H)
///
/// Provides print management operations using DIMSE-N services:
/// - N-CREATE: Create Film Session, Film Box
/// - N-SET: Set Image Box content
/// - N-GET: Get Printer status
/// - N-ACTION: Print Film Box/Session
/// - N-DELETE: Delete Film Session/Box
///
/// Typical workflow:
/// 1. Get printer status (N-GET on Printer SOP)
/// 2. Create Film Session (N-CREATE)
/// 3. Create Film Box (N-CREATE, returns Image Box UIDs)
/// 4. Set Image Box content (N-SET for each image)
/// 5. Print Film Box (N-ACTION)
/// 6. Delete Film Session (N-DELETE, cleanup)
///
/// Reference: PS3.4 Annex H - Print Management Service Class
public enum DICOMPrintService {
    
    /// Default Implementation Class UID for Print Service
    public static let defaultImplementationClassUID = DICOMNetworkImplementation.classUID
    
    /// Default Implementation Version Name for Print Service
    public static let defaultImplementationVersionName = "DICOMKIT_PRT"
    
    /// Gets the printer status using N-GET
    ///
    /// Sends N-GET to the well-known Printer SOP Instance to retrieve status.
    ///
    /// - Parameter configuration: Print connection configuration
    /// - Returns: The printer status
    /// - Throws: `DICOMNetworkError` if the operation fails
    public static func getPrinterStatus(
        configuration: PrintConfiguration
    ) async throws -> PrinterStatus {
        // Propose the meta SOP Class *and* every individual one: printers that
        // support only the individual classes reject the meta context, and vice
        // versa (see PrintPresentationContexts).
        let proposedContexts = try PrintPresentationContexts.propose(
            colorMode: configuration.colorMode)
        
        // Create association configuration
        let associationConfig = AssociationConfiguration(
            callingAETitle: try AETitle(configuration.callingAETitle),
            calledAETitle: try AETitle(configuration.calledAETitle),
            host: configuration.host,
            port: configuration.port,
            implementationClassUID: defaultImplementationClassUID,
            implementationVersionName: defaultImplementationVersionName,
            timeout: configuration.timeout
        )
        
        // Create association
        let association = Association(configuration: associationConfig)
        
        do {
            // Establish association
            let negotiated = try await association.request(presentationContexts: proposedContexts)
            
            // Verify presentation context was accepted
            // Route this N-service to whichever context the printer accepted
            // for its SOP Class — the individual one if it took it, otherwise
            // the meta class that covers it.
            let contexts = try PrintContextResolver(
                negotiated: negotiated, proposed: proposedContexts,
                colorMode: configuration.colorMode)
            let contextID = try contexts.contextID(for: printerSOPClassUID)

            // Honor the negotiated transfer syntax for both directions (P1-3 full).
            let explicitVR = contexts.usesExplicitVR(contextID)
            
            // Send N-GET request for Printer SOP Instance
            let request = NGetRequest(
                messageID: 1,
                requestedSOPClassUID: printerSOPClassUID,
                requestedSOPInstanceUID: printerSOPInstanceUID,
                presentationContextID: contextID
            )
            
            let fragmenter = MessageFragmenter(maxPDUSize: negotiated.maxPDUSize)
            let pdus = fragmenter.fragmentMessage(
                commandSet: request.commandSet,
                dataSet: nil,
                presentationContextID: request.presentationContextID
            )
            
            for pdu in pdus {
                for pdv in pdu.presentationDataValues {
                    try await association.send(pdv: pdv)
                }
            }
            
            // Receive N-GET response
            let assembler = MessageAssembler()
            while true {
                let responsePDU = try await receiveWithTimeout(
                    association: association, timeout: configuration.timeout,
                    operation: "DIMSE response")
                
                if let message = try assembler.addPDVs(from: responsePDU) {
                    let responseCommandSet = message.commandSet
                    let response = NGetResponse(commandSet: responseCommandSet, presentationContextID: contextID)
                    
                    guard response.status.isSuccessOrWarning else {
                        try await association.abort()
                        throw DICOMNetworkError.queryFailed(response.status)
                    }
                    
                    // Parse printer attributes from response data set
                    if let dataSetData = message.dataSet {
                        let printerStatus = parsePrinterStatus(from: dataSetData, explicitVR: explicitVR)
                        try await association.release()
                        return printerStatus
                    }
                    
                    try await association.release()
                    // No data set: the SCP told us nothing, and nothing is not
                    // NORMAL. The same placeholder `parsePrinterStatus` uses
                    // when Printer Status (2110,0010) is missing.
                    return PrinterStatus(status: "UNKNOWN")
                }
            }
        } catch {
            try? await association.abort()
            throw error
        }
    }

    /// Whether this printer can carry Basic Annotation Boxes.
    ///
    /// Asked by association negotiation and nothing else: the SCU proposes the
    /// Basic Annotation Box SOP Class along with everything else, and a printer
    /// that accepts that context implements the service. The class is one of
    /// the optional Print Management SOP Classes (PS3.4 Table H.3.3.2-1), not a
    /// member of the Print Management Meta SOP Class, so only its own context
    /// counts. There is no N-GET that answers this, and a conformance
    /// statement is not something a print job can read.
    ///
    /// The question is worth an association of its own because the answer
    /// decides how the *pixels* are prepared: film-level text goes in an
    /// annotation box, and a printer that has none needs the caption burned
    /// under each image instead — a decision that has to be made before the
    /// frames are rendered, not halfway through sending them.
    ///
    /// - Returns: `true` when annotation boxes can be sent. A printer that
    ///   refuses the context, or that cannot be reached, returns `false`: the
    ///   caller falls back to burning, which is the outcome that still puts the
    ///   patient's name on the film.
    public static func supportsAnnotationBoxes(
        configuration: PrintConfiguration
    ) async -> Bool {
        guard let proposedContexts = try? PrintPresentationContexts.propose(
                colorMode: configuration.colorMode),
              let callingAE = try? AETitle(configuration.callingAETitle),
              let calledAE = try? AETitle(configuration.calledAETitle) else { return false }

        let association = Association(configuration: AssociationConfiguration(
            callingAETitle: callingAE,
            calledAETitle: calledAE,
            host: configuration.host,
            port: configuration.port,
            implementationClassUID: defaultImplementationClassUID,
            implementationVersionName: defaultImplementationVersionName,
            timeout: configuration.timeout))

        do {
            let negotiated = try await association.request(presentationContexts: proposedContexts)
            let contexts = try PrintContextResolver(
                negotiated: negotiated, proposed: proposedContexts,
                colorMode: configuration.colorMode)
            let supported = contexts.supports(basicAnnotationBoxSOPClassUID)
            try await association.release()
            return supported
        } catch {
            try? await association.abort()
            return false
        }
    }

    /// Re-lays out color-by-pixel samples (RGBRGB…, the layout
    /// ``PrintImageData/pixelData`` carries) as color-by-plane (RRR…GGG…BBB…)
    /// for the Basic Color Image Sequence, whose Planar Configuration
    /// (0028,0006) PS3.3 Table C.13-5 enumerates as 1.
    ///
    /// Data that is not three-sample, or too short for its declared geometry,
    /// is returned unchanged. `internal` (not private) for unit-test access.
    static func colorByPlane(_ pixelData: Data, descriptor: PrintImageData) -> Data {
        guard descriptor.samplesPerPixel == 3 else { return pixelData }
        let bytesPerSample = max(1, Int(descriptor.bitsAllocated) / 8)
        let pixelCount = Int(descriptor.rows) * Int(descriptor.columns)
        let planeBytes = pixelCount * bytesPerSample
        guard pixelCount > 0, pixelData.count >= planeBytes * 3 else { return pixelData }

        var output = Data(count: planeBytes * 3)
        output.withUnsafeMutableBytes { destination in
            pixelData.withUnsafeBytes { source in
                guard let dst = destination.bindMemory(to: UInt8.self).baseAddress,
                      let src = source.bindMemory(to: UInt8.self).baseAddress else { return }
                for pixel in 0..<pixelCount {
                    for plane in 0..<3 {
                        for byte in 0..<bytesPerSample {
                            dst[plane * planeBytes + pixel * bytesPerSample + byte]
                                = src[(pixel * 3 + plane) * bytesPerSample + byte]
                        }
                    }
                }
            }
        }
        return output
    }

    /// The Print Job SOP Instance UID named by an N-ACTION (Print) response.
    ///
    /// PS3.4 Tables H.4-3 (Film Session) and H.4-8 (Film Box): the response
    /// data set carries Referenced Print Job Sequence (2100,0500) with one
    /// item of Referenced SOP Class UID (0008,1150) = Print Job SOP Class and
    /// Referenced SOP Instance UID (0008,1155) = the job. The sequence is
    /// "required if Print Job SOP is supported", so `nil` means the SCP
    /// created no job. The command set's Affected SOP Instance UID is *not*
    /// consulted: it identifies the Film Session or Film Box the action was
    /// invoked on (PS3.7 §10.1.4).
    ///
    /// `internal` (not private) for unit-test access.
    static func printJobUID(inActionResponse dataSet: Data?, explicitVR: Bool) -> String? {
        guard let dataSet, !dataSet.isEmpty,
              let attributes = try? PrintDatasetReader(explicitVR: explicitVR).parse(dataSet),
              let item = attributes.firstItem(of: .referencedPrintJobSequence),
              let uid = item.string(for: .referencedSOPInstanceUID)?
                  .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")),
              !uid.isEmpty
        else { return nil }
        return uid
    }

    /// Builds a human-readable detail string from a failure response's
    /// Error Comment (0000,0902) and Error ID (0000,0903), when the SCP
    /// supplied them. Returns nil when neither is present.
    static func errorDetail(from commandSet: CommandSet) -> String? {
        var parts: [String] = []
        if let comment = commandSet.errorComment, !comment.isEmpty {
            parts.append(comment)
        }
        if let id = commandSet.errorID {
            parts.append("(Error ID \(id))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Parses printer status from an N-GET response data set (Explicit VR LE).
    ///
    /// Decodes Printer Status (2110,0010), Printer Status Info (2110,0020),
    /// Printer Name (2110,0030), and — when the SCP returns them — Manufacturer
    /// (0008,0070) and Manufacturer Model Name (0008,1090). Reference: PS3.3 C.13.9.
    /// `internal` (not private) for unit-test access.
    static func parsePrinterStatus(from data: Data, explicitVR: Bool = true) -> PrinterStatus {
        let status = extractStringValue(from: data, group: 0x2110, element: 0x0010, explicitVR: explicitVR) ?? "UNKNOWN"
        return PrinterStatus(
            status: status,
            statusInfo: extractStringValue(from: data, group: 0x2110, element: 0x0020, explicitVR: explicitVR),
            printerName: extractStringValue(from: data, group: 0x2110, element: 0x0030, explicitVR: explicitVR),
            manufacturer: extractStringValue(from: data, group: 0x0008, element: 0x0070, explicitVR: explicitVR),
            manufacturerModelName: extractStringValue(from: data, group: 0x0008, element: 0x1090, explicitVR: explicitVR)
        )
    }
    
    /// Helper: Creates an association configuration for print operations
    private static func createPrintAssociationConfiguration(
        _ configuration: PrintConfiguration
    ) throws -> AssociationConfiguration {
        return AssociationConfiguration(
            callingAETitle: try AETitle(configuration.callingAETitle),
            calledAETitle: try AETitle(configuration.calledAETitle),
            host: configuration.host,
            port: configuration.port,
            implementationClassUID: defaultImplementationClassUID,
            implementationVersionName: defaultImplementationVersionName,
            timeout: configuration.timeout
        )
    }
    
    /// Helper: number of image boxes an Image Display Format (2010,0010) requests.
    ///
    /// Shares ``PrintImageDisplayFormat`` with the Print SCP, so `ROW\`, `COL\`,
    /// `SLIDE`, `SUPERSLIDE` and `CUSTOM\` count correctly instead of collapsing
    /// to 1. Unparseable values yield 1.
    private static func parseImageDisplayFormat(_ format: String) -> Int {
        PrintImageDisplayFormat.parse(format).imageBoxCount
    }
    
    /// Creates a film session using N-CREATE
    ///
    /// Sends N-CREATE to the Print SCP to create a new Film Session SOP Instance.
    /// The SCP assigns a unique SOP Instance UID which is returned.
    ///
    /// - Parameters:
    ///   - configuration: Print connection configuration
    ///   - session: Film session parameters
    /// - Returns: The assigned Film Session SOP Instance UID
    /// - Throws: `DICOMNetworkError` if the operation fails
    ///
    /// Reference: PS3.4 H.4.1 - Basic Film Session SOP Class
    public static func createFilmSession(
        configuration: PrintConfiguration,
        session: FilmSession
    ) async throws -> String {
        // Propose the meta SOP Class *and* every individual one: printers that
        // support only the individual classes reject the meta context, and vice
        // versa (see PrintPresentationContexts).
        let proposedContexts = try PrintPresentationContexts.propose(
            colorMode: configuration.colorMode)
        
        // Create association configuration
        let associationConfig = try createPrintAssociationConfiguration(configuration)
        
        // Create association
        let association = Association(configuration: associationConfig)
        
        do {
            // Establish association
            let negotiated = try await association.request(presentationContexts: proposedContexts)
            
            // Verify presentation context was accepted
            // Route this N-service to whichever context the printer accepted
            // for its SOP Class — the individual one if it took it, otherwise
            // the meta class that covers it.
            let contexts = try PrintContextResolver(
                negotiated: negotiated, proposed: proposedContexts,
                colorMode: configuration.colorMode)
            let contextID = try contexts.contextID(for: basicFilmSessionSOPClassUID)

            // Honor the negotiated transfer syntax for both directions (P1-3 full).
            let explicitVR = contexts.usesExplicitVR(contextID)
            
            // Build data set with Film Session attributes
            var elements: [DataElement] = []
            
            // Number of Copies (2000,0010) - IS
            elements.append(DataElement.string(
                tag: .numberOfCopies,
                vr: .IS,
                value: String(session.numberOfCopies)
            ))
            
            // Print Priority (2000,0020) - CS
            elements.append(DataElement.string(
                tag: .printPriority,
                vr: .CS,
                value: session.printPriority.rawValue
            ))
            
            // Medium Type (2000,0030) - CS
            elements.append(DataElement.string(
                tag: .mediumType,
                vr: .CS,
                value: session.mediumType.wireValue
            ))
            
            // Film Destination (2000,0040) - CS
            elements.append(DataElement.string(
                tag: .filmDestination,
                vr: .CS,
                value: session.filmDestination.rawValue
            ))
            
            // Film Session Label (2000,0050) - LO (optional)
            if let label = session.filmSessionLabel {
                elements.append(DataElement.string(
                    tag: .filmSessionLabel,
                    vr: .LO,
                    value: label
                ))
            }
            
            // Encode data set
            let dataSetData = serializeElements(elements, explicitVR: explicitVR)
            
            // Send N-CREATE request for Film Session
            let request = NCreateRequest(
                messageID: 1,
                affectedSOPClassUID: basicFilmSessionSOPClassUID,
                affectedSOPInstanceUID: nil, // Let SCP assign the UID
                hasDataSet: true,
                presentationContextID: contextID
            )
            
            let fragmenter = MessageFragmenter(maxPDUSize: negotiated.maxPDUSize)
            let pdus = fragmenter.fragmentMessage(
                commandSet: request.commandSet,
                dataSet: dataSetData,
                presentationContextID: request.presentationContextID
            )
            
            for pdu in pdus {
                for pdv in pdu.presentationDataValues {
                    try await association.send(pdv: pdv)
                }
            }
            
            // Receive N-CREATE response
            let assembler = MessageAssembler()
            while true {
                let responsePDU = try await receiveWithTimeout(
                    association: association, timeout: configuration.timeout,
                    operation: "DIMSE response")
                
                if let message = try assembler.addPDVs(from: responsePDU) {
                    let responseCommandSet = message.commandSet
                    let response = NCreateResponse(commandSet: responseCommandSet, presentationContextID: contextID)
                    
                    guard response.status.isSuccessOrWarning else {
                        try await association.abort()
                        throw DICOMNetworkError.printOperationFailed(response.status, detail: errorDetail(from: response.commandSet))
                    }
                    
                    // Extract assigned SOP Instance UID
                    let filmSessionUID = response.affectedSOPInstanceUID
                    
                    try await association.release()
                    return filmSessionUID
                }
            }
        } catch {
            try? await association.abort()
            throw error
        }
    }
    
    /// Creates a film box using N-CREATE
    ///
    /// Sends N-CREATE to the Print SCP to create a new Film Box SOP Instance within
    /// an existing Film Session. The SCP assigns a unique Film Box UID and creates
    /// Image Box SOP Instances based on the Image Display Format.
    ///
    /// - Parameters:
    ///   - configuration: Print connection configuration
    ///   - filmSessionUID: The Film Session SOP Instance UID to reference
    ///   - filmBox: Film box parameters (layout, size, orientation, etc.)
    /// - Returns: FilmBoxResult containing Film Box UID and Image Box UIDs
    /// - Throws: `DICOMNetworkError` if the operation fails
    ///
    /// Reference: PS3.4 H.4.2 - Basic Film Box SOP Class
    public static func createFilmBox(
        configuration: PrintConfiguration,
        filmSessionUID: String,
        filmBox: FilmBox
    ) async throws -> FilmBoxResult {
        // Propose the meta SOP Class *and* every individual one: printers that
        // support only the individual classes reject the meta context, and vice
        // versa (see PrintPresentationContexts).
        let proposedContexts = try PrintPresentationContexts.propose(
            colorMode: configuration.colorMode)
        
        // Create association configuration
        let associationConfig = try createPrintAssociationConfiguration(configuration)
        
        // Create association
        let association = Association(configuration: associationConfig)
        
        do {
            // Establish association
            let negotiated = try await association.request(presentationContexts: proposedContexts)
            
            // Verify presentation context was accepted
            // Route this N-service to whichever context the printer accepted
            // for its SOP Class — the individual one if it took it, otherwise
            // the meta class that covers it.
            let contexts = try PrintContextResolver(
                negotiated: negotiated, proposed: proposedContexts,
                colorMode: configuration.colorMode)
            let contextID = try contexts.contextID(for: basicFilmBoxSOPClassUID)

            // Honor the negotiated transfer syntax for both directions (P1-3 full).
            let explicitVR = contexts.usesExplicitVR(contextID)
            
            // Build data set with Film Box attributes
            var elements: [DataElement] = []
            
            // Image Display Format (2010,0010) - ST
            elements.append(DataElement.string(
                tag: .imageDisplayFormat,
                vr: .ST,
                value: filmBox.imageDisplayFormat
            ))
            
            // Film Orientation (2010,0040) - CS
            elements.append(DataElement.string(
                tag: .filmOrientation,
                vr: .CS,
                value: filmBox.filmOrientation.rawValue
            ))
            
            // Film Size ID (2010,0050) - CS
            elements.append(DataElement.string(
                tag: .filmSizeID,
                vr: .CS,
                value: filmBox.filmSizeID.rawValue
            ))
            
            // Magnification Type (2010,0060) - CS
            elements.append(DataElement.string(
                tag: .magnificationType,
                vr: .CS,
                value: filmBox.magnificationType.rawValue
            ))
            
            // Border Density (2010,0100) - CS
            elements.append(DataElement.string(
                tag: .borderDensity,
                vr: .CS,
                value: filmBox.borderDensity
            ))
            
            // Empty Image Density (2010,0110) - CS
            elements.append(DataElement.string(
                tag: .emptyImageDensity,
                vr: .CS,
                value: filmBox.emptyImageDensity
            ))
            
            // Trim (2010,0140) - CS. PS3.4 Table H.4-6 (Film Box N-CREATE)
            // gives it SCU/SCP usage U/U — optional on both sides.
            //
            // Sent only when trim is actually wanted: NO is the printer default
            // and conveys nothing, while printers without trim support reject a
            // film box that carries the attribute at all ("trim requested but
            // not supported" — observed against DCMTK's dcmprscp).
            //
            // Illumination (2010,015E) and Reflected Ambient Light (2010,0160)
            // are U/MC in the same table: optional for the SCU, and required
            // of an SCP that supports the Presentation LUT. The SCU is never
            // obliged to send them, so they are not sent.
            if filmBox.trimOption == .yes {
                elements.append(DataElement.string(
                    tag: .trim,
                    vr: .CS,
                    value: filmBox.trimOption.rawValue
                ))
            }
            
            // Configuration Information (2010,0150) - ST (optional)
            if let config = filmBox.configurationInformation {
                elements.append(DataElement.string(
                    tag: .configurationInformation,
                    vr: .ST,
                    value: config
                ))
            }
            
            // Referenced Film Session Sequence (2010,0500) - SQ
            // This references the parent Film Session
            let sessionSequenceItem = SequenceItem(elements: [
                DataElement.string(tag: .referencedSOPClassUID, vr: .UI, value: basicFilmSessionSOPClassUID),
                DataElement.string(tag: .referencedSOPInstanceUID, vr: .UI, value: filmSessionUID)
            ])
            
            let writer = DICOMWriter(explicitVR: explicitVR)
            let seqItemsData = writer.serializeSequenceItem(sessionSequenceItem)
            elements.append(DataElement(
                tag: .referencedFilmSessionSequence,
                vr: .SQ,
                length: UInt32(seqItemsData.count),
                valueData: seqItemsData,
                sequenceItems: [sessionSequenceItem]
            ))
            
            // Encode data set
            let dataSetData = serializeElements(elements, explicitVR: explicitVR)
            
            // Send N-CREATE request for Film Box
            let request = NCreateRequest(
                messageID: 1,
                affectedSOPClassUID: basicFilmBoxSOPClassUID,
                affectedSOPInstanceUID: nil, // Let SCP assign the UID
                hasDataSet: true,
                presentationContextID: contextID
            )
            
            let fragmenter = MessageFragmenter(maxPDUSize: negotiated.maxPDUSize)
            let pdus = fragmenter.fragmentMessage(
                commandSet: request.commandSet,
                dataSet: dataSetData,
                presentationContextID: request.presentationContextID
            )
            
            for pdu in pdus {
                for pdv in pdu.presentationDataValues {
                    try await association.send(pdv: pdv)
                }
            }
            
            // Receive N-CREATE response
            let assembler = MessageAssembler()
            while true {
                let responsePDU = try await receiveWithTimeout(
                    association: association, timeout: configuration.timeout,
                    operation: "DIMSE response")
                
                if let message = try assembler.addPDVs(from: responsePDU) {
                    let responseCommandSet = message.commandSet
                    let response = NCreateResponse(commandSet: responseCommandSet, presentationContextID: contextID)
                    
                    guard response.status.isSuccessOrWarning else {
                        try await association.abort()
                        throw DICOMNetworkError.printOperationFailed(response.status, detail: errorDetail(from: response.commandSet))
                    }
                    
                    // Extract assigned Film Box SOP Instance UID
                    let filmBoxUID = response.affectedSOPInstanceUID
                    
                    // Parse Image Box UIDs from response data set
                    var imageBoxUIDs: [String] = []
                    if let dataSetData = message.dataSet {
                        imageBoxUIDs = parseImageBoxUIDs(from: dataSetData, explicitVR: explicitVR)
                    }
                    
                    // Calculate expected number of image boxes from format
                    let imageCount = parseImageDisplayFormat(filmBox.imageDisplayFormat)
                    
                    try await association.release()
                    return FilmBoxResult(
                        filmBoxUID: filmBoxUID,
                        imageBoxUIDs: imageBoxUIDs,
                        imageCount: imageCount
                    )
                }
            }
        } catch {
            try? await association.abort()
            throw error
        }
    }
    
    /// Helper: Parses Image Box UIDs from N-CREATE response data set
    /// - Parameter data: Response data set containing Referenced Image Box Sequence
    /// - Returns: Array of Image Box SOP Instance UIDs
    ///
    /// Scoped to the Referenced Image Box Sequence (2010,0510) — a whole-data-set
    /// scan for (0008,1155) would also pick up annotation-box or presentation-LUT
    /// references and mis-attribute them as image boxes (enhancement plan P2-2).
    private static func parseImageBoxUIDs(from data: Data, explicitVR: Bool = true) -> [String] {
        parseReferencedSOPInstanceUIDs(from: data, withinSequence: .referencedImageBoxSequence,
                                       explicitVR: explicitVR)
    }

    /// Extracts Referenced SOP Instance UIDs (0008,1155) that live *inside* a
    /// specific sequence, scanning Explicit VR Little Endian bytes.
    ///
    /// Unlike ``parseImageBoxUIDs`` (which scans the whole data set), this bounds
    /// the search to a single sequence so, for example, annotation-box UIDs are
    /// not confused with image-box UIDs when both sequences are present.
    static func parseReferencedSOPInstanceUIDs(from data: Data, withinSequence sequenceTag: Tag,
                                               explicitVR: Bool = true) -> [String] {
        guard data.count >= 8 else { return [] }

        return data.withUnsafeBytes { buffer -> [String] in
            let count = buffer.count

            // Locate the sequence tag and compute the byte window it covers.
            func loadU16(_ off: Int) -> UInt16 { buffer.loadUnaligned(fromByteOffset: off, as: UInt16.self).littleEndian }
            func loadU32(_ off: Int) -> UInt32 { buffer.loadUnaligned(fromByteOffset: off, as: UInt32.self).littleEndian }

            var windowStart = -1
            var windowEnd = count
            var off = 0
            while off + 8 <= count {
                let group = loadU16(off)
                let element = loadU16(off + 2)
                if group == sequenceTag.group && element == sequenceTag.element {
                    // Explicit VR: SQ uses [tag(4)][VR(2)][reserved(2)][len(4)].
                    // Implicit VR: [tag(4)][len(4)] (PS3.5 §7.1.3).
                    let length: UInt32
                    let valueStart: Int
                    if explicitVR {
                        guard off + 12 <= count else { return [] }
                        length = loadU32(off + 8)
                        valueStart = off + 12
                    } else {
                        length = loadU32(off + 4)
                        valueStart = off + 8
                    }
                    if length == 0xFFFF_FFFF {
                        windowStart = valueStart
                        windowEnd = count // undefined length → scan to delimiter/end below
                    } else {
                        windowStart = valueStart
                        windowEnd = min(count, valueStart + Int(length))
                    }
                    break
                }
                off += 1
            }
            guard windowStart >= 0 else { return [] }

            var uids: [String] = []
            var scan = windowStart
            while scan + 8 <= windowEnd {
                let group = loadU16(scan)
                let element = loadU16(scan + 2)
                // Stop at a Sequence Delimitation Item when length was undefined.
                if group == 0xFFFE && element == 0xE00D { break }
                if group == 0x0008 && element == 0x1155 {
                    // Explicit VR UI: 16-bit length at +6, value at +8.
                    // Implicit VR: 32-bit length at +4, value at +8.
                    let length = explicitVR ? Int(loadU16(scan + 6)) : Int(loadU32(scan + 4))
                    guard length > 0, length < 256, scan + 8 + length <= windowEnd else { break }
                    let valueData = Data(bytes: buffer.baseAddress!.advanced(by: scan + 8), count: length)
                    if let uid = String(data: valueData, encoding: .ascii)?
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")), !uid.isEmpty {
                        uids.append(uid)
                    }
                    scan += 8 + length
                } else {
                    scan += 1
                }
            }
            return uids
        }
    }

    /// Creates a Presentation LUT SOP Instance (N-CREATE) carrying either a
    /// Presentation LUT Shape or a custom LUT Sequence, returning its SOP
    /// Instance UID for the film box to reference.
    ///
    /// PS3.3 C.11.4: the instance carries the sequence *or* the shape, never
    /// both — a caller providing table data means the data.
    private static func createPresentationLUTInstance(
        association: Association,
        negotiated: NegotiatedAssociation,
        shape: PresentationLUTShape?,
        table: PresentationLUTTable? = nil,
        messageID: inout UInt16,
        contextID: UInt8,
        timeout: TimeInterval = 30,
        explicitVR: Bool = true,
        eventHandler: PrintEventHandler?
    ) async throws -> String {
        let elements: [DataElement]
        if let table {
            elements = [table.sequenceElement()]
        } else if let shape, let wireValue = shape.wireValue {
            elements = [
                DataElement.string(tag: .presentationLUTShape, vr: .CS, value: wireValue)
            ]
        } else if shape?.invertsPixels == true {
            // Realised in the pixels by the preparer, so there is no SOP
            // instance to create. Reaching here means a caller asked for one
            // anyway; refusing beats emitting an INVERSE that C.11.4 forbids.
            throw PrintError.invalidConfiguration(
                reason: "Rendered inversion is applied to the pixels, "
                    + "not sent as a Presentation LUT")
        } else {
            throw PrintError.invalidConfiguration(
                reason: "A Presentation LUT needs a shape or a table")
        }
        let request = NCreateRequest(
            messageID: messageID,
            affectedSOPClassUID: presentationLUTSOPClassUID,
            affectedSOPInstanceUID: nil,
            hasDataSet: true,
            presentationContextID: contextID
        )
        messageID += 1

        let response = try await sendAndReceive(
            association: association,
            negotiated: negotiated,
            commandSet: request.commandSet,
            dataSet: serializeElements(elements, explicitVR: explicitVR),
            presentationContextID: contextID,
            timeout: timeout,
            eventHandler: eventHandler
        )
        let rsp = NCreateResponse(commandSet: response.commandSet, presentationContextID: contextID)
        guard rsp.status.isSuccessOrWarning else {
            // Abort/cleanup handled by the workflow catch (P2-3).
            throw DICOMNetworkError.printOperationFailed(rsp.status, detail: errorDetail(from: rsp.commandSet))
        }
        let uid = rsp.affectedSOPInstanceUID
        guard !uid.isEmpty else {
            // Abort/cleanup handled by the workflow catch (P2-3).
            throw DICOMNetworkError.unexpectedResponse
        }
        return uid
    }

    /// Sets the content of an image box using N-SET
    ///
    /// Sends N-SET to the Print SCP to set the pixel data and attributes of an Image Box
    /// SOP Instance. This is called after creating a Film Box to populate each image position.
    ///
    /// - Parameters:
    ///   - configuration: Print connection configuration
    ///   - imageBoxUID: The Image Box SOP Instance UID to set
    ///   - imageBox: Image box content (position, polarity, pixel data)
    ///   - pixelData: The pixel data to send (uncompressed)
    /// - Throws: `DICOMNetworkError` if the operation fails
    ///
    /// Reference: PS3.4 H.4.3.1 / H.4.3.2 - Basic Grayscale / Color Image Box SOP Class
    public static func setImageBox(
        configuration: PrintConfiguration,
        imageBoxUID: String,
        imageBox: ImageBoxContent,
        pixelData: Data,
        imageDescriptor: PrintImageData? = nil
    ) async throws {
        // PS3.3 Table C.13-5: the Basic Image Sequence item must carry the
        // pixel-module attributes — an image box without them is rejected by
        // strict SCPs, so the descriptor is required (kept optional in the
        // signature only for source compatibility).
        guard let descriptor = imageDescriptor else {
            throw DICOMNetworkError.encodingFailed(
                "setImageBox requires a PrintImageData descriptor "
                + "(Rows/Columns/BitsAllocated/PhotometricInterpretation are mandatory)")
        }

        let imageBoxSOPClassUID = configuration.colorMode == .color
            ? basicColorImageBoxSOPClassUID
            : basicGrayscaleImageBoxSOPClassUID

        // Propose the meta SOP Class *and* every individual one: printers that
        // support only the individual classes reject the meta context, and vice
        // versa (see PrintPresentationContexts).
        let proposedContexts = try PrintPresentationContexts.propose(
            colorMode: configuration.colorMode)

        // Create association configuration
        let associationConfig = try createPrintAssociationConfiguration(configuration)

        // Create association
        let association = Association(configuration: associationConfig)
        
        do {
            // Establish association
            let negotiated = try await association.request(presentationContexts: proposedContexts)
            
            // Verify presentation context was accepted
            // Route this N-service to whichever context the printer accepted
            // for its SOP Class — the individual one if it took it, otherwise
            // the meta class that covers it.
            let contexts = try PrintContextResolver(
                negotiated: negotiated, proposed: proposedContexts,
                colorMode: configuration.colorMode)
            let contextID = try contexts.contextID(for: imageBoxSOPClassUID)

            // Honor the negotiated transfer syntax for both directions (P1-3 full).
            let explicitVR = contexts.usesExplicitVR(contextID)
            
            // Build data set with Image Box attributes
            var elements: [DataElement] = []
            
            // Image Position (2020,0010) - US
            elements.append(DataElement.uint16(
                tag: .imageBoxPosition,
                value: imageBox.imagePosition
            ))
            
            // Polarity (2020,0020) - CS
            elements.append(DataElement.string(
                tag: .polarity,
                vr: .CS,
                value: imageBox.polarity.rawValue
            ))
            
            // Requested Image Size (2020,0030) - DS (optional)
            if let requestedSize = imageBox.requestedImageSize {
                elements.append(DataElement.string(
                    tag: .requestedImageSize,
                    vr: .DS,
                    value: requestedSize
                ))
            }
            
            // Requested Decimate/Crop Behavior (2020,0040) - CS, Type 3.
            //
            // Sent only when it differs from DECIMATE, which is what printers do
            // by default anyway: printers that do not implement the attribute
            // reject the image box outright when it is present ("requested
            // decimate/crop behaviour not supported" — observed against DCMTK).
            if imageBox.requestedDecimateCropBehavior != .decimate {
                elements.append(DataElement.string(
                    tag: .requestedDecimateCropBehavior,
                    vr: .CS,
                    value: imageBox.requestedDecimateCropBehavior.rawValue
                ))
            }
            
            // Add pixel data based on color mode
            if configuration.colorMode == .grayscale {
                // Preformatted Grayscale Image Sequence (2020,0110) - SQ
                // PS3.3 Table C.13-5 requires image attributes within the sequence item
                var seqElements: [DataElement] = []

                // Pixel-module attributes — always sent (descriptor guarded above).
                seqElements.append(DataElement.uint16(tag: .samplesPerPixel, value: descriptor.samplesPerPixel))
                seqElements.append(DataElement.string(tag: .photometricInterpretation, vr: .CS, value: descriptor.photometricInterpretation))
                seqElements.append(DataElement.uint16(tag: .rows, value: descriptor.rows))
                seqElements.append(DataElement.uint16(tag: .columns, value: descriptor.columns))
                seqElements.append(DataElement.uint16(tag: .bitsAllocated, value: descriptor.bitsAllocated))
                seqElements.append(DataElement.uint16(tag: .bitsStored, value: descriptor.bitsStored))
                seqElements.append(DataElement.uint16(tag: .highBit, value: descriptor.highBit))
                seqElements.append(DataElement.uint16(tag: .pixelRepresentation, value: descriptor.pixelRepresentation))

                // Pixel Data (7FE0,0010) - OW
                seqElements.append(DataElement.data(tag: .pixelData, vr: .OW, data: pixelData))

                let sequenceItem = SequenceItem(elements: seqElements)
                let writer = DICOMWriter(explicitVR: explicitVR)
                let seqItemsData = writer.serializeSequenceItem(sequenceItem)
                elements.append(DataElement(
                    tag: .preformattedGrayscaleImageSequence,
                    vr: .SQ,
                    length: UInt32(seqItemsData.count),
                    valueData: seqItemsData,
                    sequenceItems: [sequenceItem]
                ))
            } else {
                // Preformatted Color Image Sequence (2020,0111) - SQ
                var seqElements: [DataElement] = []

                // Pixel-module attributes — always sent (descriptor guarded above).
                // PS3.3 Table C.13-5 (Basic Color Image Sequence): Planar
                // Configuration (0028,0006) is enumerated as 1, color-by-plane,
                // so the samples are re-laid out RRR…GGG…BBB… on the wire.
                seqElements.append(DataElement.uint16(tag: .samplesPerPixel, value: descriptor.samplesPerPixel))
                seqElements.append(DataElement.string(tag: .photometricInterpretation, vr: .CS, value: descriptor.photometricInterpretation))
                seqElements.append(DataElement.uint16(tag: .planarConfiguration, value: 1))
                seqElements.append(DataElement.uint16(tag: .rows, value: descriptor.rows))
                seqElements.append(DataElement.uint16(tag: .columns, value: descriptor.columns))
                seqElements.append(DataElement.uint16(tag: .bitsAllocated, value: descriptor.bitsAllocated))
                seqElements.append(DataElement.uint16(tag: .bitsStored, value: descriptor.bitsStored))
                seqElements.append(DataElement.uint16(tag: .highBit, value: descriptor.highBit))
                seqElements.append(DataElement.uint16(tag: .pixelRepresentation, value: descriptor.pixelRepresentation))

                seqElements.append(DataElement.data(
                    tag: .pixelData, vr: .OW,
                    data: colorByPlane(pixelData, descriptor: descriptor)))

                let sequenceItem = SequenceItem(elements: seqElements)
                let writer = DICOMWriter(explicitVR: explicitVR)
                let seqItemsData = writer.serializeSequenceItem(sequenceItem)
                elements.append(DataElement(
                    tag: .preformattedColorImageSequence,
                    vr: .SQ,
                    length: UInt32(seqItemsData.count),
                    valueData: seqItemsData,
                    sequenceItems: [sequenceItem]
                ))
            }
            
            // Encode data set
            let dataSetData = serializeElements(elements, explicitVR: explicitVR)
            
            // Send N-SET request for Image Box
            let request = NSetRequest(
                messageID: 1,
                requestedSOPClassUID: imageBoxSOPClassUID,
                requestedSOPInstanceUID: imageBoxUID,
                hasDataSet: true,
                presentationContextID: contextID
            )
            
            let fragmenter = MessageFragmenter(maxPDUSize: negotiated.maxPDUSize)
            let pdus = fragmenter.fragmentMessage(
                commandSet: request.commandSet,
                dataSet: dataSetData,
                presentationContextID: request.presentationContextID
            )
            
            for pdu in pdus {
                for pdv in pdu.presentationDataValues {
                    try await association.send(pdv: pdv)
                }
            }
            
            // Receive N-SET response
            let assembler = MessageAssembler()
            while true {
                let responsePDU = try await receiveWithTimeout(
                    association: association, timeout: configuration.timeout,
                    operation: "DIMSE response")
                
                if let message = try assembler.addPDVs(from: responsePDU) {
                    let responseCommandSet = message.commandSet
                    let response = NSetResponse(commandSet: responseCommandSet, presentationContextID: contextID)
                    
                    guard response.status.isSuccessOrWarning else {
                        try await association.abort()
                        throw DICOMNetworkError.printOperationFailed(response.status, detail: errorDetail(from: response.commandSet))
                    }
                    
                    try await association.release()
                    return
                }
            }
        } catch {
            try? await association.abort()
            throw error
        }
    }
    
    /// Prints a film box using N-ACTION
    ///
    /// Sends N-ACTION (Action Type ID = 1) to the Print SCP to execute printing of a
    /// Film Box SOP Instance. The SCP creates a Print Job SOP Instance and returns its UID.
    ///
    /// - Parameters:
    ///   - configuration: Print connection configuration
    ///   - filmBoxUID: The Film Box SOP Instance UID to print
    /// - Returns: Print Job SOP Instance UID
    /// - Throws: `DICOMNetworkError` if the operation fails
    ///
    /// Reference: PS3.4 H.4.2.2.4 - Film Box Print Action
    public static func printFilmBox(
        configuration: PrintConfiguration,
        filmBoxUID: String
    ) async throws -> String {
        // Propose the meta SOP Class *and* every individual one: printers that
        // support only the individual classes reject the meta context, and vice
        // versa (see PrintPresentationContexts).
        let proposedContexts = try PrintPresentationContexts.propose(
            colorMode: configuration.colorMode)
        
        // Create association configuration
        let associationConfig = try createPrintAssociationConfiguration(configuration)
        
        // Create association
        let association = Association(configuration: associationConfig)
        
        do {
            // Establish association
            let negotiated = try await association.request(presentationContexts: proposedContexts)
            
            // Verify presentation context was accepted
            // Route this N-service to whichever context the printer accepted
            // for its SOP Class — the individual one if it took it, otherwise
            // the meta class that covers it.
            let contexts = try PrintContextResolver(
                negotiated: negotiated, proposed: proposedContexts,
                colorMode: configuration.colorMode)
            let contextID = try contexts.contextID(for: basicFilmBoxSOPClassUID)

            // Send N-ACTION request for Film Box with Action Type ID = 1 (Print)
            // Note: N-ACTION Print typically does not include a data set
            let request = NActionRequest(
                messageID: 1,
                requestedSOPClassUID: basicFilmBoxSOPClassUID,
                requestedSOPInstanceUID: filmBoxUID,
                actionTypeID: 1, // Action Type ID = 1 means "Print"
                hasDataSet: false,
                presentationContextID: contextID
            )
            
            let fragmenter = MessageFragmenter(maxPDUSize: negotiated.maxPDUSize)
            let pdus = fragmenter.fragmentMessage(
                commandSet: request.commandSet,
                dataSet: nil,
                presentationContextID: request.presentationContextID
            )
            
            for pdu in pdus {
                for pdv in pdu.presentationDataValues {
                    try await association.send(pdv: pdv)
                }
            }
            
            // Receive N-ACTION response
            let assembler = MessageAssembler()
            while true {
                let responsePDU = try await receiveWithTimeout(
                    association: association, timeout: configuration.timeout,
                    operation: "DIMSE response")
                
                if let message = try assembler.addPDVs(from: responsePDU) {
                    let responseCommandSet = message.commandSet
                    let response = NActionResponse(commandSet: responseCommandSet, presentationContextID: contextID)
                    
                    guard response.status.isSuccessOrWarning else {
                        try await association.abort()
                        throw DICOMNetworkError.printOperationFailed(response.status, detail: errorDetail(from: response.commandSet))
                    }
                    
                    // The Print Job SOP Instance UID travels in the response
                    // data set as Referenced Print Job Sequence (2100,0500),
                    // PS3.4 Table H.4-8. Affected SOP Instance UID names the
                    // Film Box the action was invoked on (PS3.7 N-ACTION-RSP)
                    // and is never a job UID.
                    guard let printJobUID = printJobUID(
                        inActionResponse: message.dataSet,
                        explicitVR: contexts.usesExplicitVR(contextID)) else {
                        try await association.abort()
                        throw DICOMNetworkError.unexpectedResponse
                    }

                    try await association.release()
                    return printJobUID
                }
            }
        } catch {
            try? await association.abort()
            throw error
        }
    }
    
    /// Deletes a film session using N-DELETE
    ///
    /// Sends N-DELETE to the Print SCP to delete a Film Session SOP Instance.
    /// This should be called after printing is complete to cleanup resources.
    ///
    /// - Parameters:
    ///   - configuration: Print connection configuration
    ///   - filmSessionUID: The Film Session SOP Instance UID to delete
    /// - Throws: `DICOMNetworkError` if the operation fails
    ///
    /// Reference: PS3.4 H.4.1 - Basic Film Session SOP Class
    public static func deleteFilmSession(
        configuration: PrintConfiguration,
        filmSessionUID: String
    ) async throws {
        // Propose the meta SOP Class *and* every individual one: printers that
        // support only the individual classes reject the meta context, and vice
        // versa (see PrintPresentationContexts).
        let proposedContexts = try PrintPresentationContexts.propose(
            colorMode: configuration.colorMode)
        
        // Create association configuration
        let associationConfig = try createPrintAssociationConfiguration(configuration)
        
        // Create association
        let association = Association(configuration: associationConfig)
        
        do {
            // Establish association
            let negotiated = try await association.request(presentationContexts: proposedContexts)
            
            // Verify presentation context was accepted
            // Route this N-service to whichever context the printer accepted
            // for its SOP Class — the individual one if it took it, otherwise
            // the meta class that covers it.
            let contexts = try PrintContextResolver(
                negotiated: negotiated, proposed: proposedContexts,
                colorMode: configuration.colorMode)
            let contextID = try contexts.contextID(for: basicFilmSessionSOPClassUID)

            // Send N-DELETE request for Film Session
            let request = NDeleteRequest(
                messageID: 1,
                requestedSOPClassUID: basicFilmSessionSOPClassUID,
                requestedSOPInstanceUID: filmSessionUID,
                presentationContextID: contextID
            )
            
            let fragmenter = MessageFragmenter(maxPDUSize: negotiated.maxPDUSize)
            let pdus = fragmenter.fragmentMessage(
                commandSet: request.commandSet,
                dataSet: nil,
                presentationContextID: request.presentationContextID
            )
            
            for pdu in pdus {
                for pdv in pdu.presentationDataValues {
                    try await association.send(pdv: pdv)
                }
            }
            
            // Receive N-DELETE response
            let assembler = MessageAssembler()
            while true {
                let responsePDU = try await receiveWithTimeout(
                    association: association, timeout: configuration.timeout,
                    operation: "DIMSE response")
                
                if let message = try assembler.addPDVs(from: responsePDU) {
                    let responseCommandSet = message.commandSet
                    let response = NDeleteResponse(commandSet: responseCommandSet, presentationContextID: contextID)
                    
                    guard response.status.isSuccessOrWarning else {
                        try await association.abort()
                        throw DICOMNetworkError.printOperationFailed(response.status, detail: errorDetail(from: response.commandSet))
                    }
                    
                    try await association.release()
                    return
                }
            }
        } catch {
            try? await association.abort()
            throw error
        }
    }
    
    /// Gets the status of a print job using N-GET
    ///
    /// Sends N-GET to the Print SCP to retrieve the status of a Print Job SOP Instance.
    /// This can be used to monitor the progress of a print operation.
    ///
    /// - Parameters:
    ///   - configuration: Print connection configuration
    ///   - printJobUID: The Print Job SOP Instance UID to query
    /// - Returns: The print job status
    /// - Throws: `DICOMNetworkError` if the operation fails
    ///
    /// Reference: PS3.4 H.4.5 - Print Job SOP Class
    public static func getPrintJobStatus(
        configuration: PrintConfiguration,
        printJobUID: String
    ) async throws -> PrintJobStatus {
        // Propose the meta SOP Class *and* every individual one: printers that
        // support only the individual classes reject the meta context, and vice
        // versa (see PrintPresentationContexts).
        let proposedContexts = try PrintPresentationContexts.propose(
            colorMode: configuration.colorMode)
        
        // Create association configuration
        let associationConfig = try createPrintAssociationConfiguration(configuration)
        
        // Create association
        let association = Association(configuration: associationConfig)
        
        do {
            // Establish association
            let negotiated = try await association.request(presentationContexts: proposedContexts)
            
            // Verify presentation context was accepted
            // Route this N-service to whichever context the printer accepted
            // for its SOP Class — the individual one if it took it, otherwise
            // the meta class that covers it.
            let contexts = try PrintContextResolver(
                negotiated: negotiated, proposed: proposedContexts,
                colorMode: configuration.colorMode)
            let contextID = try contexts.contextID(for: printJobSOPClassUID)

            // Honor the negotiated transfer syntax for both directions (P1-3 full).
            let explicitVR = contexts.usesExplicitVR(contextID)
            
            // Send N-GET request for Print Job SOP Instance
            let request = NGetRequest(
                messageID: 1,
                requestedSOPClassUID: printJobSOPClassUID,
                requestedSOPInstanceUID: printJobUID,
                presentationContextID: contextID
            )
            
            let fragmenter = MessageFragmenter(maxPDUSize: negotiated.maxPDUSize)
            let pdus = fragmenter.fragmentMessage(
                commandSet: request.commandSet,
                dataSet: nil,
                presentationContextID: request.presentationContextID
            )
            
            for pdu in pdus {
                for pdv in pdu.presentationDataValues {
                    try await association.send(pdv: pdv)
                }
            }
            
            // Receive N-GET response
            let assembler = MessageAssembler()
            while true {
                let responsePDU = try await receiveWithTimeout(
                    association: association, timeout: configuration.timeout,
                    operation: "DIMSE response")
                
                if let message = try assembler.addPDVs(from: responsePDU) {
                    let responseCommandSet = message.commandSet
                    let response = NGetResponse(commandSet: responseCommandSet, presentationContextID: contextID)
                    
                    guard response.status.isSuccessOrWarning else {
                        try await association.abort()
                        throw DICOMNetworkError.queryFailed(response.status)
                    }
                    
                    // Parse print job attributes from response data set
                    if let dataSetData = message.dataSet {
                        let printJobStatus = parsePrintJobStatus(from: dataSetData, printJobUID: printJobUID, explicitVR: explicitVR)
                        try await association.release()
                        return printJobStatus
                    }
                    
                    // If no data set returned, return a default status
                    try await association.release()
                    return PrintJobStatus(
                        printJobUID: printJobUID,
                        executionStatus: "UNKNOWN"
                    )
                }
            }
        } catch {
            try? await association.abort()
            throw error
        }
    }
    
    /// Parses print job status from response data
    private static func parsePrintJobStatus(from data: Data, printJobUID: String,
                                            explicitVR: Bool = true) -> PrintJobStatus {
        // Extract Execution Status (2100,0020) - CS
        let executionStatus = extractStringValue(from: data, group: 0x2100, element: 0x0020, explicitVR: explicitVR) ?? "UNKNOWN"

        // Extract Execution Status Info (2100,0030) - CS (optional)
        let executionStatusInfo = extractStringValue(from: data, group: 0x2100, element: 0x0030, explicitVR: explicitVR)

        // Extract Creation Date (2100,0040) - DA (optional)
        var creationDate: Date? = nil
        if let dateString = extractStringValue(from: data, group: 0x2100, element: 0x0040, explicitVR: explicitVR) {
            creationDate = parseDICOMDate(dateString)
        }

        // Extract Creation Time (2100,0050) - TM (optional)
        var creationTime: Date? = nil
        if let timeString = extractStringValue(from: data, group: 0x2100, element: 0x0050, explicitVR: explicitVR) {
            creationTime = parseDICOMTime(timeString)
        }
        
        return PrintJobStatus(
            printJobUID: printJobUID,
            executionStatus: executionStatus,
            executionStatusInfo: executionStatusInfo,
            creationDate: creationDate,
            creationTime: creationTime
        )
    }
    
    /// Parses DICOM Date (DA) format: YYYYMMDD
    private static func parseDICOMDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateString)
    }
    
    /// Parses DICOM Time (TM) format: HHMMSS.FFFFFF
    private static func parseDICOMTime(_ timeString: String) -> Date? {
        let formatter = DateFormatter()
        // Handle various TM formats: HHMMSS, HHMMSS.F, HHMMSS.FFFFFF
        let cleanedTime = timeString.components(separatedBy: ".").first ?? timeString
        formatter.dateFormat = "HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: cleanedTime)
    }
    
    // MARK: - Data Set Serialization Helpers
    
    /// Serializes an array of DataElements into raw Explicit VR Little Endian binary data
    /// - Parameter elements: Array of data elements to serialize (will be sorted by tag)
    /// - Returns: Serialized data set as Data
    private static func serializeElements(_ elements: [DataElement], explicitVR: Bool = true) -> Data {
        let writer = DICOMWriter(explicitVR: explicitVR)
        var data = Data()
        for element in elements.sorted(by: { $0.tag < $1.tag }) {
            data.append(writer.serializeElement(element))
        }
        return data
    }
    
    /// Extracts a string value from raw Explicit VR Little Endian binary data for a specific tag
    /// - Parameters:
    ///   - data: Raw DICOM data set bytes
    ///   - group: Tag group number
    ///   - element: Tag element number
    /// - Returns: The string value if found, nil otherwise
    private static func extractStringValue(from data: Data, group: UInt16, element: UInt16,
                                           explicitVR: Bool = true) -> String? {
        guard data.count >= 8 else { return nil }

        return data.withUnsafeBytes { buffer -> String? in
            var offset = 0

            while offset + 8 <= buffer.count {
                let g = buffer.load(fromByteOffset: offset, as: UInt16.self).littleEndian
                let e = buffer.load(fromByteOffset: offset + 2, as: UInt16.self).littleEndian

                let headerSize: Int
                let valueLength: Int

                if explicitVR {
                    // Read VR (2 bytes ASCII)
                    guard offset + 6 <= buffer.count else { break }
                    let vrByte0 = buffer.load(fromByteOffset: offset + 4, as: UInt8.self)
                    let vrByte1 = buffer.load(fromByteOffset: offset + 5, as: UInt8.self)
                    let vrString = String(UnicodeScalar(vrByte0)) + String(UnicodeScalar(vrByte1))

                    // Length field size by VR — DICOMCore's rule (PS3.5 2026a 7.1.2,
                    // Tables 7.1-1 / 7.1-2): OB, OD, OF, OL, OV, OW, SQ, SV, UC, UN, UR,
                    // UT and UV carry 2 reserved bytes + a 32-bit length. The former
                    // literal list here omitted OV, SV and UV (D276). An unknown VR is
                    // read with a 16-bit length, as before.
                    let uses32BitLength = VR(rawValue: vrString)?.uses32BitLength ?? false

                    if uses32BitLength {
                        guard offset + 12 <= buffer.count else { break }
                        // 2 reserved bytes + 4 byte length
                        valueLength = Int(buffer.load(fromByteOffset: offset + 8, as: UInt32.self).littleEndian)
                        headerSize = 12
                    } else {
                        guard offset + 8 <= buffer.count else { break }
                        valueLength = Int(buffer.load(fromByteOffset: offset + 6, as: UInt16.self).littleEndian)
                        headerSize = 8
                    }
                } else {
                    // Implicit VR LE: [tag(4)][length(4)] (PS3.5 §7.1.3)
                    valueLength = Int(buffer.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self).littleEndian)
                    headerSize = 8
                }

                if g == group && e == element {
                    // Found the target tag - validate length is reasonable (< 1MB)
                    guard valueLength != 0xFFFFFFFF,
                          valueLength < 1_048_576,
                          offset + headerSize + valueLength <= buffer.count else {
                        return nil
                    }
                    let valueData = Data(bytes: buffer.baseAddress!.advanced(by: offset + headerSize), count: valueLength)
                    return String(data: valueData, encoding: .ascii)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
                }
                
                // Skip to next element
                if valueLength == 0xFFFFFFFF {
                    // Undefined length - skip (can't parse further without full sequence parser)
                    break
                }
                offset += headerSize + valueLength
            }
            
            return nil
        }
    }
    
    // MARK: - High-Level Print API (Phase 2)
    
    // MARK: Single-Association Print Workflow
    
    /// Receives one PDU with a DIMSE-response timeout (enhancement plan P1-4).
    ///
    /// `Association.receive()` has no timer of its own, so an SCP that accepts
    /// the association and then goes silent would hang the caller forever. This
    /// races the receive against a deadline. The underlying network read is not
    /// cancellation-aware, so on expiry the association is aborted to unblock
    /// the pending read, then an `operationTimeout` error is thrown.
    static func receiveWithTimeout(
        association: Association,
        timeout: TimeInterval,
        operation: String
    ) async throws -> DataTransferPDU {
        let deadline = max(1, timeout)
        return try await withThrowingTaskGroup(of: DataTransferPDU?.self) { group in
            group.addTask {
                try await association.receive()
            }
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: UInt64(deadline * 1_000_000_000))
                } catch {
                    return nil // cancelled: the response arrived first
                }
                guard !Task.isCancelled else { return nil }
                // Tear down the association so the blocked receive() unwinds.
                try? await association.abort()
                return nil
            }
            defer { group.cancelAll() }
            let start = Date()
            do {
                guard let first = try await group.next(), let pdu = first else {
                    // The timer fired first: the association was aborted above.
                    _ = try? await group.next() // drain the unblocked receive task
                    throw DICOMNetworkError.operationTimeout(
                        type: .operation, duration: deadline, operation: operation)
                }
                return pdu
            } catch let error as DICOMNetworkError {
                if case .operationTimeout = error { throw error }
                // A failure surfacing at/after the deadline was caused by the
                // timer aborting the association — report it as the timeout it
                // is, not as the secondary abort/close error.
                if Date().timeIntervalSince(start) >= deadline - 0.05 {
                    throw DICOMNetworkError.operationTimeout(
                        type: .operation, duration: deadline, operation: operation)
                }
                throw error
            }
        }
    }

    /// Internal helper: sends a DIMSE message and receives the response on an existing association.
    /// Returns the assembled response message.
    private static func sendAndReceive(
        association: Association,
        negotiated: NegotiatedAssociation,
        commandSet: CommandSet,
        dataSet: Data?,
        presentationContextID: UInt8,
        timeout: TimeInterval = 30,
        eventHandler: PrintEventHandler? = nil
    ) async throws -> AssembledMessage {
        let fragmenter = MessageFragmenter(maxPDUSize: negotiated.maxPDUSize)
        let pdus = fragmenter.fragmentMessage(
            commandSet: commandSet,
            dataSet: dataSet,
            presentationContextID: presentationContextID
        )
        for pdu in pdus {
            for pdv in pdu.presentationDataValues {
                try await association.send(pdv: pdv)
            }
        }
        var assembler = MessageAssembler()
        while true {
            let responsePDU = try await receiveWithTimeout(
                association: association, timeout: timeout,
                operation: "DIMSE response (\(commandSet.command.map(String.init(describing:)) ?? "unknown"))")
            if let message = try assembler.addPDVs(from: responsePDU) {
                // The Print SCP may push an N-EVENT-REPORT-RQ (printer status or
                // print-job progress) interleaved with our own responses. Handle
                // it, acknowledge it, and keep waiting for the response we sent
                // this request for. (PS3.7 10.1; PS3.4 H.4.)
                if message.commandSet.command == .nEventReportRequest {
                    try await handleIncomingEvent(
                        association: association,
                        negotiated: negotiated,
                        message: message,
                        eventHandler: eventHandler
                    )
                    assembler = MessageAssembler()
                    continue
                }
                return message
            }
        }
    }

    /// Decodes an incoming N-EVENT-REPORT-RQ, notifies the handler, and sends the
    /// mandatory N-EVENT-REPORT-RSP acknowledgement back to the Print SCP.
    private static func handleIncomingEvent(
        association: Association,
        negotiated: NegotiatedAssociation,
        message: AssembledMessage,
        eventHandler: PrintEventHandler?
    ) async throws {
        let request = NEventReportRequest(
            commandSet: message.commandSet,
            presentationContextID: message.presentationContextID
        )

        // Surface the decoded event to the caller.
        eventHandler?(decodePrintEvent(from: message))

        // A successful acknowledgement is required so the SCP can continue.
        let response = NEventReportResponse(
            messageIDBeingRespondedTo: request.messageID,
            affectedSOPClassUID: request.affectedSOPClassUID,
            affectedSOPInstanceUID: request.affectedSOPInstanceUID,
            eventTypeID: request.eventTypeID,
            status: .success,
            hasDataSet: false,
            presentationContextID: message.presentationContextID
        )
        let fragmenter = MessageFragmenter(maxPDUSize: negotiated.maxPDUSize)
        let pdus = fragmenter.fragmentMessage(
            commandSet: response.commandSet,
            dataSet: nil,
            presentationContextID: response.presentationContextID
        )
        for pdu in pdus {
            for pdv in pdu.presentationDataValues {
                try await association.send(pdv: pdv)
            }
        }
    }

    /// Builds a ``PrintEvent`` from an assembled N-EVENT-REPORT-RQ message.
    private static func decodePrintEvent(from message: AssembledMessage) -> PrintEvent {
        let cmd = message.commandSet
        var printerStatusInfo: String?
        var executionStatusInfo: String?
        if let ds = message.dataSet {
            printerStatusInfo = extractStringValue(from: ds, group: 0x2110, element: 0x0020)
            executionStatusInfo = extractStringValue(from: ds, group: 0x2100, element: 0x0030)
        }
        return PrintEvent(
            sopClassUID: cmd.affectedSOPClassUID ?? "",
            sopInstanceUID: cmd.affectedSOPInstanceUID ?? "",
            eventTypeID: cmd.eventTypeID ?? 0,
            printerStatusInfo: printerStatusInfo,
            executionStatusInfo: executionStatusInfo
        )
    }
    
    /// Performs the complete print workflow within a single DICOM association.
    ///
    /// Per DICOM PS3.4 H.4, all Print Management operations (Film Session, Film Box,
    /// Image Box, Print action) must occur within the same association because the
    /// printer SCP maintains stateful objects tied to the association lifetime.
    ///
    /// - Parameters:
    ///   - configuration: Print connection configuration
    ///   - images: Array of pixel data to print
    ///   - imageDescriptors: Optional per-image descriptors with dimensions and bit depth
    ///   - options: Print options
    ///   - displayFormat: The Image Display Format (2010,0010) the film boxes
    ///     carry. Sent verbatim, and its image-box count — not `rows × columns` —
    ///     is what decides how many images fit one film, so the non-uniform
    ///     `ROW\` and `COL\` bands chunk correctly.
    /// - Returns: The print result
    /// - Throws: `DICOMNetworkError` if any step fails
    private static func executePrintWorkflow(
        configuration: PrintConfiguration,
        images: [Data],
        imageDescriptors: [PrintImageData],
        options: PrintOptions,
        displayFormat: PrintImageDisplayFormat,
        eventHandler: PrintEventHandler? = nil,
        progressHandler: (@Sendable (PrintProgress) -> Void)? = nil
    ) async throws -> PrintResult {
        // PS3.3 Table C.13-5: a Basic Image Sequence item without
        // Rows/Columns/BitsAllocated/PhotometricInterpretation is non-conformant
        // and rejected by strict SCPs — require one descriptor per image up front.
        guard imageDescriptors.count >= images.count else {
            throw DICOMNetworkError.encodingFailed(
                "printing requires a PrintImageData descriptor per image "
                + "(got \(imageDescriptors.count) descriptor(s) for \(images.count) image(s)); "
                + "image-box attributes (Rows/Columns/BitsAllocated/PhotometricInterpretation) are mandatory")
        }

        let imageBoxSOPClassUID = configuration.colorMode == .color
            ? basicColorImageBoxSOPClassUID
            : basicGrayscaleImageBoxSOPClassUID

        // Propose the meta SOP Class *and* every individual one: printers that
        // support only the individual classes reject the meta context, and vice
        // versa (see PrintPresentationContexts).
        let proposedContexts = try PrintPresentationContexts.propose(
            colorMode: configuration.colorMode)
        
        let associationConfig = try createPrintAssociationConfiguration(configuration)
        let association = Association(configuration: associationConfig)

        progressHandler?(PrintProgress(
            phase: .connecting, progress: 0.0, message: "Connecting to print server..."))

        // Set once the film session exists, so the catch below can attempt a
        // best-effort in-association N-DELETE before aborting (P2-3).
        // Carries the film-session context too: the catch below runs outside the
        // scope where the contexts were resolved.
        var sessionCleanup: (negotiated: NegotiatedAssociation, filmSessionUID: String, contextID: UInt8)?

        do {
            let negotiated = try await association.request(presentationContexts: proposedContexts)

            // Each N-service travels on a context the printer actually accepted
            // for its SOP Class: the individual context when the printer took
            // it, the meta-class context otherwise (PrintPresentationContexts).
            let contexts = try PrintContextResolver(
                negotiated: negotiated, proposed: proposedContexts,
                colorMode: configuration.colorMode)
            let sessionContext = try contexts.contextID(for: basicFilmSessionSOPClassUID)
            let filmBoxContext = try contexts.contextID(for: basicFilmBoxSOPClassUID)
            let imageBoxContext = try contexts.contextID(for: imageBoxSOPClassUID)

            // Honor the negotiated transfer syntax for both directions (P1-3
            // full). Every context is proposed with the same syntax list, so the
            // film session's answer is representative.
            let explicitVR = contexts.usesExplicitVR(sessionContext)

            var messageID: UInt16 = 1
            
            progressHandler?(PrintProgress(
                phase: .creatingSession, progress: 0.1, message: "Creating print session..."))
            // ── Step 1: N-CREATE Film Session ─────────────────────────────
            var sessionElements: [DataElement] = []
            sessionElements.append(DataElement.string(tag: .numberOfCopies, vr: .IS, value: String(options.numberOfCopies)))
            sessionElements.append(DataElement.string(tag: .printPriority, vr: .CS, value: options.priority.rawValue))
            sessionElements.append(DataElement.string(tag: .mediumType, vr: .CS, value: options.mediumType.wireValue))
            sessionElements.append(DataElement.string(tag: .filmDestination, vr: .CS, value: options.filmDestination.rawValue))
            if let label = options.sessionLabel {
                sessionElements.append(DataElement.string(tag: .filmSessionLabel, vr: .LO, value: label))
            }
            
            let sessionRequest = NCreateRequest(
                messageID: messageID,
                affectedSOPClassUID: basicFilmSessionSOPClassUID,
                affectedSOPInstanceUID: nil,
                hasDataSet: true,
                presentationContextID: sessionContext
            )
            messageID += 1
            
            let sessionResponse = try await sendAndReceive(
                association: association,
                negotiated: negotiated,
                commandSet: sessionRequest.commandSet,
                dataSet: serializeElements(sessionElements, explicitVR: explicitVR),
                presentationContextID: sessionContext,
                timeout: configuration.timeout,
                eventHandler: eventHandler
            )
            
            let sessionRsp = NCreateResponse(commandSet: sessionResponse.commandSet, presentationContextID: sessionContext)
            guard sessionRsp.status.isSuccessOrWarning else {
                // Abort/cleanup handled by the workflow catch (P2-3).
                throw DICOMNetworkError.printOperationFailed(sessionRsp.status, detail: errorDetail(from: sessionRsp.commandSet))
            }
            let filmSessionUID = sessionRsp.affectedSOPInstanceUID
            sessionCleanup = (negotiated, filmSessionUID, sessionContext)

            // ── Step 1b: N-CREATE Presentation LUT (optional) ─────────────
            // Created once per association and referenced from each film box.
            var presentationLUTUID: String?
            // A pixel-rendered inversion has nothing legal to send, so it must
            // not trigger a Presentation LUT N-CREATE (PS3.3 C.11.4).
            if options.presentationLUTShape?.isLegalPrintShape == true
                || options.presentationLUTTable != nil {
                var lutMessageID: UInt16 = 1000
                presentationLUTUID = try await createPresentationLUTInstance(
                    association: association,
                    negotiated: negotiated,
                    shape: options.presentationLUTShape,
                    table: options.presentationLUTTable,
                    messageID: &lutMessageID,
                    contextID: try contexts.contextID(for: presentationLUTSOPClassUID),
                    timeout: configuration.timeout,
                    explicitVR: explicitVR,
                    eventHandler: eventHandler
                )
            }

            // ── Step 2: Process film boxes ────────────────────────────────
            var allPrintJobUIDs: [String] = []
            var allFilmBoxUIDs: [String] = []

            let imagesPerFilm = max(1, displayFormat.imageBoxCount)
            let filmBoxCount = max(1, (images.count + imagesPerFilm - 1) / imagesPerFilm)

            for filmIndex in 0..<filmBoxCount {
                // ── Step 2a: N-CREATE Film Box ────────────────────────────
                let imageDisplayFormat = displayFormat.raw

                var filmBoxElements: [DataElement] = []
                filmBoxElements.append(DataElement.string(tag: .imageDisplayFormat, vr: .ST, value: imageDisplayFormat))
                filmBoxElements.append(DataElement.string(tag: .filmOrientation, vr: .CS, value: options.filmOrientation.rawValue))
                filmBoxElements.append(DataElement.string(tag: .filmSizeID, vr: .CS, value: options.filmSize.rawValue))
                filmBoxElements.append(DataElement.string(tag: .magnificationType, vr: .CS, value: options.magnificationType.rawValue))
                filmBoxElements.append(DataElement.string(tag: .borderDensity, vr: .CS, value: options.borderDensity))
                filmBoxElements.append(DataElement.string(tag: .emptyImageDensity, vr: .CS, value: options.emptyImageDensity))
                // Trim (2010,0140) is U/U in PS3.4 Table H.4-6 (Film Box
                // N-CREATE): send it only when trim is wanted. A printer without
                // trim support rejects a film box that carries the attribute
                // even with the value NO. Illumination (2010,015E) and Reflected
                // Ambient Light (2010,0160) are U/MC there — optional for the
                // SCU even when a Presentation LUT is referenced — and are not
                // sent.
                if options.trimOption == .yes {
                    filmBoxElements.append(DataElement.string(
                        tag: .trim, vr: .CS, value: options.trimOption.rawValue))
                }
                
                // Referenced Film Session Sequence (2010,0500)
                let sessionSeqItem = SequenceItem(elements: [
                    DataElement.string(tag: .referencedSOPClassUID, vr: .UI, value: basicFilmSessionSOPClassUID),
                    DataElement.string(tag: .referencedSOPInstanceUID, vr: .UI, value: filmSessionUID)
                ])
                let writer = DICOMWriter(explicitVR: explicitVR)
                let seqItemsData = writer.serializeSequenceItem(sessionSeqItem)
                filmBoxElements.append(DataElement(
                    tag: .referencedFilmSessionSequence,
                    vr: .SQ,
                    length: UInt32(seqItemsData.count),
                    valueData: seqItemsData,
                    sequenceItems: [sessionSeqItem]
                ))

                // Referenced Presentation LUT Sequence (2050,0500) — links the
                // film box to the Presentation LUT created above.
                if let lutUID = presentationLUTUID {
                    let lutSeqItem = SequenceItem(elements: [
                        DataElement.string(tag: .referencedSOPClassUID, vr: .UI, value: presentationLUTSOPClassUID),
                        DataElement.string(tag: .referencedSOPInstanceUID, vr: .UI, value: lutUID)
                    ])
                    let lutSeqData = writer.serializeSequenceItem(lutSeqItem)
                    filmBoxElements.append(DataElement(
                        tag: .referencedPresentationLUTSequence,
                        vr: .SQ,
                        length: UInt32(lutSeqData.count),
                        valueData: lutSeqData,
                        sequenceItems: [lutSeqItem]
                    ))
                    // Illumination / Reflected Ambient Light (2010,015E/0160) — the
                    // viewing conditions the Presentation LUT is calibrated for.
                    // Optional for the SCU; sent only when the caller set them.
                    if let illumination = options.illumination {
                        filmBoxElements.append(DataElement.uint16(tag: .illumination, value: illumination))
                    }
                    if let ambient = options.reflectedAmbientLight {
                        filmBoxElements.append(DataElement.uint16(tag: .reflectedAmbientLight, value: ambient))
                    }
                }

                // Annotation Display Format ID (2010,0030) — enables annotation
                // boxes on the film. Printer-specific; only sent when the caller
                // supplied both a format ID and annotations.
                // Configuration Information (2010,0150) — printer-specific and
                // mandatory on several vendors' devices.
                if let configurationInformation = options.configurationInformation,
                   !configurationInformation.isEmpty {
                    filmBoxElements.append(DataElement.string(
                        tag: .configurationInformation, vr: .ST, value: configurationInformation))
                }

                // Per film: a job whose sheets hold different studies footers
                // each sheet with its own patient, not the first one's.
                let filmAnnotations = options.annotations(forFilm: filmIndex)
                var annotationsEnabled = !filmAnnotations.isEmpty
                    && options.annotationDisplayFormatID != nil
                    && contexts.supports(basicAnnotationBoxSOPClassUID)
                let plainFilmBoxElements = filmBoxElements
                if annotationsEnabled, let formatID = options.annotationDisplayFormatID {
                    filmBoxElements.append(DataElement.string(tag: .annotationDisplayFormatID, vr: .CS, value: formatID))
                }

                /// Creates the film box from a set of attributes.
                func createFilmBox(_ elements: [DataElement]) async throws -> (NCreateResponse, AssembledMessage) {
                    let request = NCreateRequest(
                        messageID: messageID,
                        affectedSOPClassUID: basicFilmBoxSOPClassUID,
                        affectedSOPInstanceUID: nil,
                        hasDataSet: true,
                        presentationContextID: filmBoxContext
                    )
                    messageID += 1
                    let response = try await sendAndReceive(
                        association: association,
                        negotiated: negotiated,
                        commandSet: request.commandSet,
                        dataSet: serializeElements(elements, explicitVR: explicitVR),
                        presentationContextID: filmBoxContext,
                        timeout: configuration.timeout,
                        eventHandler: eventHandler
                    )
                    return (NCreateResponse(commandSet: response.commandSet,
                                            presentationContextID: filmBoxContext),
                            response)
                }

                var (filmBoxRsp, filmBoxResponse) = try await createFilmBox(filmBoxElements)

                // Annotation Display Format ID is printer-defined: the value a
                // device does not recognise is a value it may refuse the whole
                // film box over. A refusal is not worth losing the film for, so
                // the box is created again without it and the film prints with
                // no annotation — the pictures are what the job is for.
                if !filmBoxRsp.status.isSuccessOrWarning, annotationsEnabled {
                    progressHandler?(PrintProgress(
                        phase: .creatingSession,
                        progress: 0.15,
                        message: "The printer refused the film box with Annotation Display "
                            + "Format ID '\(options.annotationDisplayFormatID ?? "")'. Retrying "
                            + "without it — this film will carry no annotation text."))
                    annotationsEnabled = false
                    (filmBoxRsp, filmBoxResponse) = try await createFilmBox(plainFilmBoxElements)
                }

                guard filmBoxRsp.status.isSuccessOrWarning else {
                    // Abort/cleanup handled by the workflow catch (P2-3).
                    throw DICOMNetworkError.printOperationFailed(filmBoxRsp.status, detail: errorDetail(from: filmBoxRsp.commandSet))
                }
                
                let filmBoxUID = filmBoxRsp.affectedSOPInstanceUID
                allFilmBoxUIDs.append(filmBoxUID)
                
                // Parse Image Box UIDs from response data set
                var imageBoxUIDs: [String] = []
                if let dataSetData = filmBoxResponse.dataSet {
                    imageBoxUIDs = parseImageBoxUIDs(from: dataSetData, explicitVR: explicitVR)
                }
                
                // ── Step 2b: N-SET Image Boxes ────────────────────────────
                let startIndex = filmIndex * imagesPerFilm
                let endIndex = min(startIndex + imagesPerFilm, images.count)
                
                for (imageIndex, globalIndex) in (startIndex..<endIndex).enumerated() {
                    guard imageIndex < imageBoxUIDs.count else { continue }

                    progressHandler?(PrintProgress(
                        phase: .uploadingImages(current: globalIndex + 1, total: images.count),
                        progress: 0.2 + 0.65 * (Double(globalIndex + 1) / Double(images.count)),
                        message: "Uploading image \(globalIndex + 1) of \(images.count)..."))

                    let imageBoxUID = imageBoxUIDs[imageIndex]
                    let position = UInt16(imageIndex + 1)
                    
                    var imgElements: [DataElement] = []
                    // Image Position (2020,0010)
                    imgElements.append(DataElement.uint16(tag: .imageBoxPosition, value: position))
                    // Polarity (2020,0020)
                    imgElements.append(DataElement.string(tag: .polarity, vr: .CS, value: options.polarity.rawValue))
                    // Requested Image Size (2020,0030), Type 3 — the printed
                    // width in millimetres, when the job asked for one (true
                    // size). Decimate/Crop (2020,0040), Type 3 — omitted for
                    // DECIMATE, the printer default, so printers that do not
                    // implement the attribute still accept the image box.
                    let boxOptions = options.imageBoxOptions(forImage: globalIndex)
                    if let requestedSize = boxOptions.requestedImageSize {
                        imgElements.append(DataElement.string(
                            tag: .requestedImageSize, vr: .DS, value: requestedSize))
                    }
                    if boxOptions.requestedDecimateCropBehavior != .decimate {
                        imgElements.append(DataElement.string(
                            tag: .requestedDecimateCropBehavior, vr: .CS,
                            value: boxOptions.requestedDecimateCropBehavior.rawValue))
                    }

                    // Build Preformatted Image Sequence with image attributes.
                    // The descriptor is guaranteed present by the guard at the top
                    // of the workflow — the pixel-module attributes are always sent.
                    var seqElements: [DataElement] = []
                    let desc = imageDescriptors[globalIndex]
                    let isColorBox = configuration.colorMode == .color
                    seqElements.append(DataElement.uint16(tag: .samplesPerPixel, value: desc.samplesPerPixel))
                    seqElements.append(DataElement.string(tag: .photometricInterpretation, vr: .CS, value: desc.photometricInterpretation))
                    if isColorBox {
                        // PS3.3 Table C.13-5 (Basic Color Image Sequence):
                        // Planar Configuration (0028,0006) = 1, color-by-plane.
                        seqElements.append(DataElement.uint16(tag: .planarConfiguration, value: 1))
                    }
                    seqElements.append(DataElement.uint16(tag: .rows, value: desc.rows))
                    seqElements.append(DataElement.uint16(tag: .columns, value: desc.columns))
                    seqElements.append(DataElement.uint16(tag: .bitsAllocated, value: desc.bitsAllocated))
                    seqElements.append(DataElement.uint16(tag: .bitsStored, value: desc.bitsStored))
                    seqElements.append(DataElement.uint16(tag: .highBit, value: desc.highBit))
                    seqElements.append(DataElement.uint16(tag: .pixelRepresentation, value: desc.pixelRepresentation))
                    seqElements.append(DataElement.data(
                        tag: .pixelData, vr: .OW,
                        data: isColorBox
                            ? colorByPlane(images[globalIndex], descriptor: desc)
                            : images[globalIndex]))
                    
                    let imgSeqItem = SequenceItem(elements: seqElements)
                    let imgWriter = DICOMWriter(explicitVR: explicitVR)
                    let imgSeqData = imgWriter.serializeSequenceItem(imgSeqItem)
                    
                    let seqTag: Tag = configuration.colorMode == .color
                        ? .preformattedColorImageSequence
                        : .preformattedGrayscaleImageSequence
                    imgElements.append(DataElement(
                        tag: seqTag,
                        vr: .SQ,
                        length: UInt32(imgSeqData.count),
                        valueData: imgSeqData,
                        sequenceItems: [imgSeqItem]
                    ))
                    
                    let setRequest = NSetRequest(
                        messageID: messageID,
                        requestedSOPClassUID: imageBoxSOPClassUID,
                        requestedSOPInstanceUID: imageBoxUID,
                        hasDataSet: true,
                        presentationContextID: imageBoxContext
                    )
                    messageID += 1
                    
                    let setResponse = try await sendAndReceive(
                        association: association,
                        negotiated: negotiated,
                        commandSet: setRequest.commandSet,
                        dataSet: serializeElements(imgElements, explicitVR: explicitVR),
                        presentationContextID: imageBoxContext,
                        timeout: configuration.timeout,
                        eventHandler: eventHandler
                    )
                    
                    let setRsp = NSetResponse(commandSet: setResponse.commandSet, presentationContextID: imageBoxContext)
                    guard setRsp.status.isSuccessOrWarning else {
                        // Abort/cleanup handled by the workflow catch (P2-3).
                        throw DICOMNetworkError.printOperationFailed(setRsp.status, detail: errorDetail(from: setRsp.commandSet))
                    }
                }

                // ── Step 2b′: N-SET Annotation Boxes (optional) ───────────
                let annotationContext = (try? contexts.contextID(for: basicAnnotationBoxSOPClassUID))
                    ?? filmBoxContext
                if annotationsEnabled, let dataSetData = filmBoxResponse.dataSet {
                    let annotationBoxUIDs = parseReferencedSOPInstanceUIDs(
                        from: dataSetData,
                        withinSequence: .referencedBasicAnnotationBoxSequence,
                        explicitVR: explicitVR
                    )
                    for annotation in filmAnnotations {
                        let idx = Int(annotation.position) - 1
                        guard idx >= 0, idx < annotationBoxUIDs.count else { continue }
                        let annotationBoxUID = annotationBoxUIDs[idx]

                        let annElements: [DataElement] = [
                            DataElement.uint16(tag: .annotationPosition, value: annotation.position),
                            DataElement.string(tag: .textString, vr: .LO, value: annotation.textStringValue)
                        ]
                        let annRequest = NSetRequest(
                            messageID: messageID,
                            requestedSOPClassUID: basicAnnotationBoxSOPClassUID,
                            requestedSOPInstanceUID: annotationBoxUID,
                            hasDataSet: true,
                            presentationContextID: annotationContext
                        )
                        messageID += 1

                        let annResponse = try await sendAndReceive(
                            association: association,
                            negotiated: negotiated,
                            commandSet: annRequest.commandSet,
                            dataSet: serializeElements(annElements, explicitVR: explicitVR),
                            presentationContextID: annotationContext,
                            timeout: configuration.timeout,
                            eventHandler: eventHandler
                        )
                        let annRsp = NSetResponse(commandSet: annResponse.commandSet, presentationContextID: annotationContext)
                        guard annRsp.status.isSuccessOrWarning else {
                            // Abort/cleanup handled by the workflow catch (P2-3).
                            throw DICOMNetworkError.printOperationFailed(annRsp.status, detail: errorDetail(from: annRsp.commandSet))
                        }
                    }
                }

                progressHandler?(PrintProgress(
                    phase: .printing,
                    progress: 0.9,
                    message: filmBoxCount > 1
                        ? "Sending print command for film \(filmIndex + 1) of \(filmBoxCount)..."
                        : "Sending print command..."))
                // ── Step 2c: N-ACTION Print Film Box ──────────────────────
                let actionRequest = NActionRequest(
                    messageID: messageID,
                    requestedSOPClassUID: basicFilmBoxSOPClassUID,
                    requestedSOPInstanceUID: filmBoxUID,
                    actionTypeID: 1,
                    hasDataSet: false,
                    presentationContextID: filmBoxContext
                )
                messageID += 1
                
                let actionResponse = try await sendAndReceive(
                    association: association,
                    negotiated: negotiated,
                    commandSet: actionRequest.commandSet,
                    dataSet: nil,
                    presentationContextID: filmBoxContext,
                    timeout: configuration.timeout,
                    eventHandler: eventHandler
                )
                
                let actionRsp = NActionResponse(commandSet: actionResponse.commandSet, presentationContextID: filmBoxContext)
                guard actionRsp.status.isSuccessOrWarning else {
                    // Abort/cleanup handled by the workflow catch (P2-3).
                    throw DICOMNetworkError.printOperationFailed(actionRsp.status, detail: errorDetail(from: actionRsp.commandSet))
                }
                
                // The Print Job SOP Instance UID travels only in the response
                // data set, as Referenced Print Job Sequence (2100,0500) —
                // PS3.4 Table H.4-8, "-/MC, required if Print Job SOP is
                // supported". Affected SOP Instance UID is the Film Box the
                // action was invoked on (PS3.7 N-ACTION-RSP), never the job.
                // An SCP without Print Job support sends no sequence, and
                // then there is no UID to record (polling with a made-up one
                // would fail).
                if let printJobUID = printJobUID(
                    inActionResponse: actionResponse.dataSet, explicitVR: explicitVR) {
                    allPrintJobUIDs.append(printJobUID)
                }
            }
            
            progressHandler?(PrintProgress(
                phase: .cleanup, progress: 0.95, message: "Cleaning up session..."))
            // ── Step 3: N-DELETE Film Session ──────────────────────────────
            let deleteRequest = NDeleteRequest(
                messageID: messageID,
                requestedSOPClassUID: basicFilmSessionSOPClassUID,
                requestedSOPInstanceUID: filmSessionUID,
                presentationContextID: sessionContext
            )
            
            let deleteResponse = try await sendAndReceive(
                association: association,
                negotiated: negotiated,
                commandSet: deleteRequest.commandSet,
                dataSet: nil,
                presentationContextID: sessionContext,
                timeout: configuration.timeout,
                eventHandler: eventHandler
            )
            // Ignore N-DELETE status — cleanup is best-effort
            _ = NDeleteResponse(commandSet: deleteResponse.commandSet, presentationContextID: sessionContext)
            
            // ── Step 4: Release association ────────────────────────────────
            try await association.release()
            
            return PrintResult(
                success: true,
                status: .success,
                filmSessionUID: filmSessionUID,
                filmBoxUIDs: allFilmBoxUIDs,
                printJobUIDs: allPrintJobUIDs
            )
        } catch {
            // P2-3: while an abort discards the SCP's box hierarchy per PS3.4,
            // some SCPs persist state — attempt a best-effort in-association
            // Film Session N-DELETE first. Skipped implicitly when the
            // association is already dead (send/receive just fails fast).
            if let cleanup = sessionCleanup {
                let deleteRequest = NDeleteRequest(
                    messageID: 0xFFF0,
                    requestedSOPClassUID: basicFilmSessionSOPClassUID,
                    requestedSOPInstanceUID: cleanup.filmSessionUID,
                    presentationContextID: cleanup.contextID
                )
                _ = try? await sendAndReceive(
                    association: association,
                    negotiated: cleanup.negotiated,
                    commandSet: deleteRequest.commandSet,
                    dataSet: nil,
                    presentationContextID: cleanup.contextID,
                    timeout: min(configuration.timeout, 5),
                    eventHandler: nil
                )
            }
            try? await association.abort()
            throw error
        }
    }

    /// Prints a single image using the complete print workflow
    ///
    /// All DICOM Print operations are performed within a single association as required
    /// by PS3.4 H.4.
    ///
    /// - Parameters:
    ///   - configuration: Print connection configuration
    ///   - imageData: The pixel data to print
    ///   - options: Print options (defaults to `.default`)
    ///   - imageDescriptor: Optional image descriptor with dimensions and bit depth
    ///   - eventHandler: Optional handler invoked for each N-EVENT-REPORT (printer
    ///     status or print-job progress) the SCP pushes during the association.
    /// - Returns: The print result
    /// - Throws: `DICOMNetworkError` if any step of the workflow fails
    public static func printImage(
        configuration: PrintConfiguration,
        imageData: Data,
        options: PrintOptions = .default,
        imageDescriptor: PrintImageData? = nil,
        eventHandler: PrintEventHandler? = nil
    ) async throws -> PrintResult {
        return try await executePrintWorkflow(
            configuration: configuration,
            images: [imageData],
            imageDescriptors: imageDescriptor.map { [$0] } ?? [],
            options: options,
            displayFormat: PrintImageDisplayFormat(layout: PrintLayout(rows: 1, columns: 1)),
            eventHandler: eventHandler
        )
    }
    
    /// Prints multiple images using the complete print workflow with automatic layout
    ///
    /// All DICOM Print operations are performed within a single association as required
    /// by PS3.4 H.4.
    ///
    /// - Parameters:
    ///   - configuration: Print connection configuration
    ///   - images: Array of pixel data to print
    ///   - options: Print options (defaults to `.default`)
    ///   - imageDescriptors: Optional per-image descriptors with dimensions and bit depth
    ///   - layout: Optional explicit layout. When `nil`, an optimal layout is chosen
    ///     automatically for the number of images.
    ///   - displayFormat: Optional Image Display Format, for the `ROW\` and `COL\`
    ///     films a rows × columns grid cannot express. Overrides `layout`.
    ///   - eventHandler: Optional handler invoked for each N-EVENT-REPORT (printer
    ///     status or print-job progress) the SCP pushes during the association.
    /// - Returns: The print result
    /// - Throws: `DICOMNetworkError` if any step of the workflow fails
    ///   - progressHandler: Optional handler invoked with each ``PrintProgress``
    ///     update. Unlike ``printImagesWithProgress(configuration:images:options:imageDescriptors:layout:eventHandler:)``,
    ///     which yields progress but discards the outcome, this reports progress
    ///     *and* returns the result (including every film box and print job UID).
    public static func printImages(
        configuration: PrintConfiguration,
        images: [Data],
        options: PrintOptions = .default,
        imageDescriptors: [PrintImageData] = [],
        layout: PrintLayout? = nil,
        displayFormat: PrintImageDisplayFormat? = nil,
        eventHandler: PrintEventHandler? = nil,
        progressHandler: (@Sendable (PrintProgress) -> Void)? = nil
    ) async throws -> PrintResult {
        guard !images.isEmpty else {
            return PrintResult(
                success: false,
                status: .failedUnableToProcess,
                errorMessage: "No images provided"
            )
        }

        let resolvedFormat = resolveDisplayFormat(
            displayFormat: displayFormat, layout: layout, imageCount: images.count)

        return try await executePrintWorkflow(
            configuration: configuration,
            images: images,
            imageDescriptors: imageDescriptors,
            options: options,
            displayFormat: resolvedFormat,
            eventHandler: eventHandler,
            progressHandler: progressHandler
        )
    }

    /// Prints images using a specific print template
    ///
    /// - Parameters:
    ///   - configuration: Print connection configuration
    ///   - images: Array of pixel data to print
    ///   - template: The print template to use for layout
    ///   - options: Print options (defaults to `.default`)
    /// - Returns: The print result
    /// - Throws: `DICOMNetworkError` if any step of the workflow fails
    ///
    /// Example:
    /// ```swift
    /// let result = try await DICOMPrintService.printWithTemplate(
    ///     configuration: printConfig,
    ///     images: multiPhaseImages,
    ///     template: .multiPhase3x4
    /// )
    /// ```
    public static func printWithTemplate(
        configuration: PrintConfiguration,
        images: [Data],
        template: PrintTemplate,
        options: PrintOptions = .default,
        imageDescriptors: [PrintImageData] = [],
        eventHandler: PrintEventHandler? = nil
    ) async throws -> PrintResult {
        guard !images.isEmpty else {
            return PrintResult(
                success: false,
                status: .failedUnableToProcess,
                errorMessage: "No images provided"
            )
        }

        // The template supplies the layout, film size, and orientation; all other
        // options pass through unchanged.
        let templateOptions = PrintOptions(
            numberOfCopies: options.numberOfCopies,
            priority: options.priority,
            filmSize: template.filmSize,
            filmOrientation: template.filmOrientation,
            mediumType: options.mediumType,
            filmDestination: options.filmDestination,
            borderDensity: options.borderDensity,
            emptyImageDensity: options.emptyImageDensity,
            magnificationType: options.magnificationType,
            polarity: options.polarity,
            trimOption: options.trimOption,
            sessionLabel: options.sessionLabel,
            presentationLUTShape: options.presentationLUTShape,
            annotations: options.annotations,
            annotationDisplayFormatID: options.annotationDisplayFormatID,
            configurationInformation: options.configurationInformation,
            filmAnnotations: options.filmAnnotations
        )

        // Reimplemented on the single-association workflow (PS3.4 H.4): the
        // previous implementation called the discrete createFilmSession /
        // createFilmBox / setImageBox / printFilmBox functions, each of which
        // opens its own association — the Film Session UID from one association
        // is not valid in the next, so strict SCPs rejected the sequence.
        return try await executePrintWorkflow(
            configuration: configuration,
            images: images,
            imageDescriptors: imageDescriptors,
            options: templateOptions,
            // The template's own format string, sent as written: a template is
            // free to name a layout no rows × columns pair can describe.
            displayFormat: PrintImageDisplayFormat.parse(template.imageDisplayFormat),
            eventHandler: eventHandler
        )
    }

    /// Parses an Image Display Format (2010,0010) value into a `PrintLayout`.
    ///
    /// Delegates to ``PrintImageDisplayFormat``, the one grammar shared with the
    /// Print SCP, so the SCU and the emulator always agree on what a format
    /// string means (PS3.3 C.13.3: `STANDARD\C,R` is columns-first).
    /// Unparseable values fall back to 1×1.
    static func layout(fromImageDisplayFormat format: String) -> PrintLayout {
        PrintImageDisplayFormat.parse(format).layout
    }

    /// The Image Display Format a job actually sends.
    ///
    /// An explicit format wins over a grid — it is the more expressive of the
    /// two, and the only one that can say `ROW\` or `COL\`. With neither, the
    /// grid is chosen to fit the images, as it always was.
    static func resolveDisplayFormat(
        displayFormat: PrintImageDisplayFormat?,
        layout: PrintLayout?,
        imageCount: Int
    ) -> PrintImageDisplayFormat {
        if let displayFormat { return displayFormat }
        if let layout { return PrintImageDisplayFormat(layout: layout) }
        if imageCount == 1 { return PrintImageDisplayFormat(layout: PrintLayout(rows: 1, columns: 1)) }
        return PrintImageDisplayFormat(layout: PrintLayout.optimalLayout(for: imageCount))
    }

    /// Prints images with progress reporting via AsyncThrowingStream
    ///
    /// Provides progress updates during the print workflow. The entire workflow
    /// runs on a **single association** as required by PS3.4 H.4 (the previous
    /// implementation opened one association per DIMSE step, which strict SCPs
    /// reject because the Film Session UID does not survive across associations).
    ///
    /// - Parameters:
    ///   - configuration: Print connection configuration
    ///   - images: Array of pixel data to print
    ///   - options: Print options (defaults to `.default`)
    ///   - imageDescriptors: Per-image descriptors (required — see P1-1: image-box
    ///     pixel-module attributes are mandatory)
    ///   - layout: Optional explicit layout; auto-chosen when nil
    ///   - displayFormat: Optional Image Display Format; overrides `layout`
    ///   - eventHandler: Optional handler for N-EVENT-REPORT notifications
    /// - Returns: An AsyncThrowingStream that yields PrintProgress updates
    public static func printImagesWithProgress(
        configuration: PrintConfiguration,
        images: [Data],
        options: PrintOptions = .default,
        imageDescriptors: [PrintImageData] = [],
        layout: PrintLayout? = nil,
        displayFormat: PrintImageDisplayFormat? = nil,
        eventHandler: PrintEventHandler? = nil
    ) -> AsyncThrowingStream<PrintProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard !images.isEmpty else {
                        continuation.finish(
                            throwing: DICOMNetworkError.encodingFailed("No images provided"))
                        return
                    }

                    let resolvedFormat = resolveDisplayFormat(
                        displayFormat: displayFormat, layout: layout, imageCount: images.count)

                    _ = try await executePrintWorkflow(
                        configuration: configuration,
                        images: images,
                        imageDescriptors: imageDescriptors,
                        options: options,
                        displayFormat: resolvedFormat,
                        eventHandler: eventHandler,
                        progressHandler: { continuation.yield($0) }
                    )

                    continuation.yield(PrintProgress(
                        phase: .completed,
                        progress: 1.0,
                        message: "Print job completed successfully"
                    ))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

#endif
