// StudioTheme.swift
// DICOMStudio
//
// DICOM Studio — Theming and appearance definitions

#if canImport(SwiftUI)
import SwiftUI
#endif

import Foundation
import DICOMCore

/// Medical imaging color palette for radiology-appropriate theming.
///
/// Colors are defined as platform-independent values; SwiftUI `Color`
/// extensions are conditionally available on Apple platforms.
public enum StudioColors: Sendable {
    // MARK: - Primary Palette

    /// Teal blue used for primary actions and navigation highlights.
    public static let primaryRed: Double = 0.22
    public static let primaryGreen: Double = 0.60
    public static let primaryBlue: Double = 0.78

    /// Deep navy for backgrounds in radiology mode.
    public static let backgroundRed: Double = 0.06
    public static let backgroundGreen: Double = 0.07
    public static let backgroundBlue: Double = 0.10

    /// Neutral grey for the mount the reading area is set into — the gutter
    /// between the image and the panes flanking it.
    ///
    /// Deliberately lighter than the image area, which is pure black: on a
    /// reporting station the darkest thing on screen must be the picture, so the
    /// chrome reads as furniture and the eye lands on the anatomy without being
    /// told to. Neutral grey rather than tinted — a colour cast next to a
    /// greyscale image shifts how its own greys are judged.
    public static let viewerChromeWhite: Double = 0.10

    /// Surface of the panes flanking the reading area — the series list on the
    /// left, the selection tray on the right.
    ///
    /// A clear step lighter than the gutter, because the three columns used to
    /// sit at one tone and read as a single dark field: which of them held the
    /// images that were about to print was a question the screen did not answer.
    /// Lighter panes, a darker mount and a black picture put the columns on
    /// three separate planes, and the reading area is the one that recedes.
    public static let viewerPanelWhite: Double = 0.19

    /// Header strip at the top of a pane — a step lighter again, so each column
    /// is titled and the titles sit on a surface of their own.
    public static let viewerPanelHeaderWhite: Double = 0.25

    /// Soft white for text on dark backgrounds.
    public static let textOnDarkRed: Double = 0.92
    public static let textOnDarkGreen: Double = 0.93
    public static let textOnDarkBlue: Double = 0.94

    // MARK: - Status Colors

    /// Green for success/connected status.
    public static let successRed: Double = 0.30
    public static let successGreen: Double = 0.75
    public static let successBlue: Double = 0.40

    /// Amber for warnings.
    public static let warningRed: Double = 0.95
    public static let warningGreen: Double = 0.75
    public static let warningBlue: Double = 0.20

    /// Red for errors.
    public static let errorRed: Double = 0.90
    public static let errorGreen: Double = 0.25
    public static let errorBlue: Double = 0.25

    // MARK: - Modality Colors

    /// Color for CT modality.
    public static let ctRed: Double = 0.25
    public static let ctGreen: Double = 0.55
    public static let ctBlue: Double = 0.85

    /// Color for MR modality.
    public static let mrRed: Double = 0.50
    public static let mrGreen: Double = 0.35
    public static let mrBlue: Double = 0.80

    /// Color for US modality.
    public static let usRed: Double = 0.30
    public static let usGreen: Double = 0.70
    public static let usBlue: Double = 0.50

    /// Color for XR/DX modality.
    public static let xrRed: Double = 0.75
    public static let xrGreen: Double = 0.60
    public static let xrBlue: Double = 0.30

    /// Returns RGB tuple for a given modality string.
    ///
    /// Colors are assigned per ``DICOMCore/Modality/Category`` so every one of
    /// the 79 defined terms gets a meaningful color rather than only the four
    /// codes this switch once listed. Aliases (`MRI`, `XR`, `PET`, …) resolve
    /// through ``DICOMCore/Modality/normalized(_:)``, the project's one alias table.
    public static func modalityColor(for modality: String) -> (red: Double, green: Double, blue: Double) {
        guard let resolved = Modality.normalized(modality) else {
            return (primaryRed, primaryGreen, primaryBlue)
        }
        switch resolved.category {
        case .crossSectional:
            // CT and MR are distinct enough in daily use to keep their own hues.
            if resolved == .mr { return (mrRed, mrGreen, mrBlue) }
            return (ctRed, ctGreen, ctBlue)
        case .ultrasound:
            return (usRed, usGreen, usBlue)
        case .radiography:
            return (xrRed, xrGreen, xrBlue)
        default:
            return (primaryRed, primaryGreen, primaryBlue)
        }
    }
}

#if canImport(SwiftUI)
extension StudioColors {
    /// Primary accent color.
    public static var primary: Color {
        Color(red: primaryRed, green: primaryGreen, blue: primaryBlue)
    }

    /// Radiology-mode background color.
    public static var radiologyBackground: Color {
        Color(red: backgroundRed, green: backgroundGreen, blue: backgroundBlue)
    }

    /// The mount the reading area is set into: the gutter around the image.
    public static var viewerChrome: Color {
        Color(white: viewerChromeWhite)
    }

    /// Surface of the panes flanking the reading area.
    public static var viewerPanel: Color {
        Color(white: viewerPanelWhite)
    }

    /// Surface of a pane's title strip.
    public static var viewerPanelHeader: Color {
        Color(white: viewerPanelHeaderWhite)
    }

    /// Hairline along the edge where a pane meets the gutter.
    public static var viewerPanelEdge: Color {
        Color.black.opacity(0.55)
    }

    /// Fill behind the selected study in the library.
    ///
    /// A dimmed, desaturated version of the accent rather than the accent
    /// itself: selection has to be obvious at a glance without competing with
    /// the row's own text, and a full-strength tint behind a list of studies is
    /// tiring to read against on a dark window.
    public static var selectionFill: Color {
        Color(red: primaryRed * selectionDim,
              green: primaryGreen * selectionDim,
              blue: primaryBlue * selectionDim)
        .opacity(0.35)
    }

    /// Edge of the selected study, a little brighter than its fill so the row's
    /// extent is readable where the fill meets the background.
    public static var selectionBorder: Color {
        Color(red: primaryRed * selectionDim,
              green: primaryGreen * selectionDim,
              blue: primaryBlue * selectionDim)
        .opacity(0.75)
    }

    /// How far the accent is knocked back for selection surfaces.
    private static let selectionDim: Double = 0.62

    /// Hairline that frames the reading area against the chrome.
    public static var readingAreaBorder: Color {
        Color.white.opacity(0.14)
    }

    /// Text color for dark backgrounds.
    public static var textOnDark: Color {
        Color(red: textOnDarkRed, green: textOnDarkGreen, blue: textOnDarkBlue)
    }

    /// Success/connected indicator color.
    public static var success: Color {
        Color(red: successRed, green: successGreen, blue: successBlue)
    }

    /// Warning indicator color.
    public static var warning: Color {
        Color(red: warningRed, green: warningGreen, blue: warningBlue)
    }

    /// Error indicator color.
    public static var error: Color {
        Color(red: errorRed, green: errorGreen, blue: errorBlue)
    }

    /// Returns a SwiftUI Color for a given modality.
    public static func color(for modality: String) -> Color {
        let rgb = modalityColor(for: modality)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
#endif

/// Typography scale constants following Dynamic Type sizing.
public enum StudioTypography: Sendable {
    /// Display title size.
    public static let displaySize: CGFloat = 28

    /// Section header size.
    public static let headerSize: CGFloat = 20

    /// Body text size.
    public static let bodySize: CGFloat = 14

    /// Caption / detail size.
    public static let captionSize: CGFloat = 11

    /// Monospaced size for tags and UIDs.
    public static let monoSize: CGFloat = 12
}
