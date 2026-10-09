// NEMA-verified: 2026a, checked 2026-09-29 — footer Text String (2030,0020) kept a legal LO per PS3.5 2026a Table 6.2-1 (64 characters, no backslash or control characters); Annotation Display Format ID per PS3.3 Table C.13-3; Annotation Position per Table C.13-7
// FilmIdentification.swift
// DICOMPrintKit
//
// Where a film says whose study it is: under every picture, or once along the
// bottom of the sheet.
//
// A film of one study repeats the same name in every cell, which is noise on
// paper and pixels taken off each picture for a caption that has already been
// read. A film that mixes studies cannot say it once — a single footer under a
// sheet holding two patients is the kind of statement that puts a report on the
// wrong chart — so there the caption stays with the image it belongs to.
//
// The decision is per *film*, not per job: a job can spill onto a second sheet
// carrying a different study, and each sheet has to be identifiable on its own.
//
// This is the one place the rule lives. The preview, the composed sheet and the
// print run all ask it the same question, so the film matches the screen it was
// approved on.

import Foundation
import DICOMNetwork

// MARK: - Placement

/// Where patient identification is drawn on a film.
public enum PrintIdentificationPlacement: String, CaseIterable, Sendable, Codable {

    /// One footer when the whole sheet is one study, a caption per image when it
    /// is not. The rule a reader would apply by hand.
    case automatic

    /// A caption under every image, whatever the sheet holds.
    case perImage

    /// One footer along the bottom of the sheet, whatever the sheet holds.
    ///
    /// A sheet mixing studies footers every distinct caption on it rather than
    /// silently naming one patient for all of them.
    case filmFooter

    /// Menu title.
    public var title: String {
        switch self {
        case .automatic:  return "Automatic"
        case .perImage:   return "Under each image"
        case .filmFooter: return "Once at the foot of the film"
        }
    }

    /// One line of explanation, shown under the control.
    public var help: String {
        switch self {
        case .automatic:
            return "One caption at the foot of a film whose images are all from "
                + "one study; a caption under each image when a film mixes studies."
        case .perImage:
            return "Every image carries its own caption, as on a mixed film."
        case .filmFooter:
            return "One caption at the foot of every film. A film mixing studies "
                + "lists each of them."
        }
    }
}

// MARK: - Inputs

/// One image on a film, as the identification rule sees it.
public struct FilmIdentificationSource: Sendable, Equatable {

    /// Whatever the caller identifies the image by — a mark ID, or a file path.
    public let key: String

    /// Study Instance UID (0020,000D), or empty when it could not be read.
    public let studyKey: String

    /// The caption lines for this image, blank ones already removed.
    public let lines: [String]

    public init(key: String, studyKey: String, lines: [String]) {
        self.key = key
        self.studyKey = studyKey
        self.lines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Whether this image has anything to say about its patient.
    public var hasCaption: Bool { !lines.isEmpty }
}

// MARK: - Decision

/// How one film carries its identification.
public enum FilmIdentification: Sendable, Equatable {

    /// Nothing to draw — identification is off, or nothing could be read.
    case none

    /// A caption burned under each image, as it has always been.
    case perImage

    /// One caption along the bottom of the sheet, drawn once.
    case footer(lines: [String])

    /// The footer's lines, or none when this film does not carry one.
    public var footerLines: [String] {
        if case .footer(let lines) = self { return lines }
        return []
    }

    /// Whether each image on this film burns its own caption.
    public var isPerImage: Bool { self == .perImage }
}

// MARK: - Planner

/// Decides how a film carries its identification.
public enum FilmIdentificationPlanner {

    /// The identification for one film's images, in cell order.
    ///
    /// A film is footered when every captioned image on it belongs to the same
    /// study. Study Instance UID is the test rather than the caption text: two
    /// studies of one patient on the same day produce identical caption lines
    /// and are still two studies, and a footer that says otherwise is wrong
    /// about what the reader is holding.
    ///
    /// An image whose study could not be read (an unreadable header) has no
    /// study to agree with, so it forces per-image captions — the film says less
    /// than it might, rather than something it cannot support.
    public static func identification(
        for sources: [FilmIdentificationSource],
        placement: PrintIdentificationPlacement
    ) -> FilmIdentification {
        let captioned = sources.filter(\.hasCaption)
        guard !captioned.isEmpty else { return .none }

        switch placement {
        case .perImage:
            return .perImage

        case .filmFooter:
            return .footer(lines: distinctCaptions(captioned).flatMap { $0 })

        case .automatic:
            let studies = Set(captioned.map(\.studyKey))
            guard studies.count == 1, let study = studies.first, !study.isEmpty else {
                return .perImage
            }
            // One study can still be described two ways when two of its files
            // disagree about the study description; the film then says both,
            // rather than picking one and hiding the other.
            return .footer(lines: distinctCaptions(captioned).flatMap { $0 })
        }
    }

    /// The distinct captions among these images, in the order they first appear.
    private static func distinctCaptions(
        _ sources: [FilmIdentificationSource]
    ) -> [[String]] {
        var seen: Set<[String]> = []
        var result: [[String]] = []
        for source in sources where !seen.contains(source.lines) {
            seen.insert(source.lines)
            result.append(source.lines)
        }
        return result
    }
}

// MARK: - Footer geometry

/// How much of a sheet the identification footer takes.
///
/// One definition, in millimetres, so the preview's strip and the composed
/// sheet's strip are the same fraction of the film. The cells are laid out in
/// what is left: text drawn over a corner of the bottom row is text over
/// anatomy, which is exactly what the footer exists to avoid.
public enum FilmIdentificationFooter {

    /// Type size on a sheet of this height, in millimetres.
    ///
    /// A caption is read at the distance the film is read at, and that distance
    /// goes with the sheet: a 14×17 hanging on a viewing box is looked at from
    /// across a room, an 8×10 is held. Type fixed in millimetres would be
    /// oversized on the small sheet and lost on the large one, so it is a
    /// fraction of the film's own height — the same relationship the cells have
    /// to it.
    ///
    /// Bounded at both ends: below the floor the strip stops being readable at
    /// any distance, and above the ceiling a caption starts taking height the
    /// pictures need.
    public static func fontMillimeters(sheetHeightMillimeters height: Double) -> Double {
        guard height > 0 else { return minimumFontMillimeters }
        return min(max(height * fontHeightFraction, minimumFontMillimeters),
                   maximumFontMillimeters)
    }

    /// Type size as a fraction of the sheet's height. A 14×17 portrait sheet
    /// (432 mm) gets ~4.75 mm; an 8×10 (254 mm) gets ~2.8 mm.
    public static let fontHeightFraction: Double = 0.011

    /// The SRS legibility floor (§4.6): 8 pt at 300 DPI. A point is 1/72 in,
    /// so 8 pt = 8/72 × 25.4 ≈ 2.82 mm on the physical sheet — regardless of
    /// the DPI it is rasterized at, which is the point of stating it in
    /// millimetres.
    public static let minimumFontMillimeters: Double = 8.0 / 72.0 * 25.4
    public static let maximumFontMillimeters: Double = 6

    /// Baseline-to-baseline distance, as a multiple of the type size.
    public static let lineFactor: Double = 1.35

    /// Clearance above and below the block of text, as a multiple of the type
    /// size — so the strip breathes the same way at every sheet size.
    public static let paddingFactor: Double = 0.5

    /// The band `lineCount` lines of footer need on a sheet of this height, in
    /// millimetres.
    public static func heightMillimeters(
        lineCount: Int,
        sheetHeightMillimeters height: Double
    ) -> Double {
        guard lineCount > 0 else { return 0 }
        let font = fontMillimeters(sheetHeightMillimeters: height)
        return font * (2 * paddingFactor + Double(lineCount) * lineFactor)
    }

    /// The band this film's annotation boxes need, in millimetres.
    public static func heightMillimeters(
        for annotations: [PrintAnnotation],
        sheetHeightMillimeters height: Double
    ) -> Double {
        heightMillimeters(lineCount: annotations.count, sheetHeightMillimeters: height)
    }

    /// The Annotation Display Format ID used when the printer's own has not
    /// been configured.
    ///
    /// The attribute's formats are "defined in the Conformance Statement"
    /// (PS3.3 Table C.13-3), so it is printer-defined, and a film box cannot
    /// carry annotation boxes without one, so a job that wants a footer must
    /// send *something*. This is a plain, widely-recognised token; a device that
    /// refuses it refuses the film box, which the SCU recovers from by creating
    /// the box again without the attribute. Where the printer's real format ID
    /// is known it should be configured — this is the fallback, not the answer.
    public static let defaultAnnotationDisplayFormatID = "ANNOTATION"

    /// The annotation boxes that carry `lines` as a film footer, in order.
    ///
    /// Position 1 is the first line: the composer stacks them upwards from the
    /// bottom margin, and a printer lays them out per its own configured
    /// Annotation Display Format. Each line is made a legal Text String
    /// first — see ``textString(_:)``.
    public static func annotations(for lines: [String]) -> [PrintAnnotation] {
        lines.enumerated().map { index, text in
            PrintAnnotation(position: UInt16(index + 1), text: textString(text))
        }
    }

    /// The most characters a Text String (2030,0020) carries: the attribute is
    /// LO, "64 chars maximum" (PS3.5 Table 6.2-1).
    public static let textStringMaximumLength = 64

    /// A caption line as a legal LO value.
    ///
    /// PS3.5 Table 6.2-1: at most 64 characters, no backslash (it separates
    /// the values of a multi-valued element) and no control characters but
    /// ESC. A patient footer runs long — name, ID, birth date and a study
    /// description joined on one line — and a printer is within its rights to
    /// reject the N-CREATE of a box that exceeds the VR, so the line is cut at
    /// the limit rather than sent whole. A backslash becomes a slash, which
    /// reads the same on film.
    public static func textString(_ line: String) -> String {
        let cleaned = line
            .replacingOccurrences(of: "\\", with: "/")
            .filter { character in
                !character.unicodeScalars.contains {
                    $0.properties.generalCategory == .control && $0 != "\u{1B}"
                }
            }
        return String(cleaned.prefix(textStringMaximumLength))
    }
}
