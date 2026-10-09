// NEMA-verified: 2026a, checked 2026-09-29 — Requested Image Size (2020,0030), Requested Decimate/Crop Behavior (2020,0040) DECIMATE/CROP per PS3.3 2026a Table C.13-5; Pixel Spacing (0028,0030), Imager Pixel Spacing (0018,1164), Nominal Scanned Pixel Spacing (0018,2010) per PS3.6 Table 6-1 and PS3.3 10.7; CROP-without-size read as filling the box (P-CROP, PRINT_CONFORMANCE.md 3.5)
// PrintCellPlacement.swift
// DICOMPrintKit
//
// How an image is scaled into its film cell, and where it sits when it does
// not fill it. SRS FR-003.
//
// Scaling is expressed on the wire through two Image Box attributes — Requested
// Image Size (2020,0030) and Requested Decimate/Crop Behavior (2020,0040) — so
// three of the four modes travel to a real printer. Stretch and the alignment
// have no DICOM form: they exist only where this toolkit composes the film
// itself (preview, save-film, the SCP emulator), and a job printed through a
// third-party SCP centres, as printers do.

import Foundation
import DICOMCore
import DICOMKit
import DICOMNetwork

// MARK: - Scaling mode

/// How an image is scaled to its cell (SRS FR-003).
public enum PrintScalingMode: String, Sendable, Equatable, Codable, CaseIterable {
    /// Scale to fit within the cell, aspect ratio kept, letterboxed. The
    /// default, and what DECIMATE with no requested size asks a printer for.
    case fitToFilm

    /// Scale to fill the cell completely, aspect ratio kept, overflow cropped.
    /// CROP on the wire. PS3.3 Table C.13-5 crops only rows or columns that
    /// exceed the box at the size of "optimal filling", which it does not
    /// define; this toolkit reads it as filling the box (PRINT_CONFORMANCE.md
    /// 3.5, P-CROP), and a printer that reads it as fit prints this fitted.
    case fillToFilm

    /// Print at actual physical size, from the source's pixel spacing.
    /// Carried as Requested Image Size (2020,0030); only guaranteed when the
    /// printer honours that attribute.
    case trueSize

    /// Fill the cell exactly, aspect ratio ignored. **Not for diagnostic use**
    /// (SRS §4.3): anatomy is distorted. Local composition only — no printer
    /// implements it.
    case stretch

    /// The Requested Decimate/Crop Behavior (2020,0040) this mode asks of a
    /// printer. Stretch has no wire form and degrades to DECIMATE.
    public var decimateCropBehavior: DecimateCropBehavior {
        switch self {
        case .fitToFilm, .stretch: return .decimate
        // True size prints at the requested size and crops what the cell
        // cannot hold — silently shrinking would be a false 1:1.
        case .fillToFilm, .trueSize: return .crop
        }
    }

    /// UI label.
    public var displayName: String {
        switch self {
        case .fitToFilm:  return "Fit to Film"
        case .fillToFilm: return "Fill to Film"
        case .trueSize:   return "True Size (1:1)"
        case .stretch:    return "Stretch"
        }
    }
}

// MARK: - Alignment

/// Where an image sits inside its cell when it does not fill it (SRS FR-003).
///
/// For a fitted image this moves the picture inside its letterbox; for a
/// filled one it moves the crop window over the source instead, so "top" keeps
/// the top of the anatomy either way.
public enum PrintCellAlignment: String, Sendable, Equatable, Codable, CaseIterable {
    case topLeft, topCenter, topRight
    case centerLeft, center, centerRight
    case bottomLeft, bottomCenter, bottomRight

    /// Horizontal placement fraction: 0 flush left, ½ centred, 1 flush right.
    public var horizontalFraction: Double {
        switch self {
        case .topLeft, .centerLeft, .bottomLeft:     return 0
        case .topCenter, .center, .bottomCenter:     return 0.5
        case .topRight, .centerRight, .bottomRight:  return 1
        }
    }

    /// Vertical placement fraction: 0 flush top, ½ centred, 1 flush bottom.
    public var verticalFraction: Double {
        switch self {
        case .topLeft, .topCenter, .topRight:          return 0
        case .centerLeft, .center, .centerRight:       return 0.5
        case .bottomLeft, .bottomCenter, .bottomRight: return 1
        }
    }

    /// The top-left origin of `width` × `height` content placed in `cell`.
    public func origin(
        forContentWidth width: Double, height: Double, in cell: FilmCell
    ) -> (x: Double, y: Double) {
        (x: cell.x + (cell.width - width) * horizontalFraction,
         y: cell.y + (cell.height - height) * verticalFraction)
    }

    /// UI label.
    public var displayName: String {
        switch self {
        case .topLeft:      return "Top Left"
        case .topCenter:    return "Top"
        case .topRight:     return "Top Right"
        case .centerLeft:   return "Left"
        case .center:       return "Center"
        case .centerRight:  return "Right"
        case .bottomLeft:   return "Bottom Left"
        case .bottomCenter: return "Bottom"
        case .bottomRight:  return "Bottom Right"
        }
    }
}

// MARK: - Physical size

/// Reads the physical size a frame prints at 1:1, for true-size printing.
public enum PrintPhysicalSize {

    /// The physical size of one pixel in millimetres, (row, column), when the
    /// file records it. Sources, in order of preference (PS3.3 10.7):
    ///
    /// 1. Pixel Spacing (0028,0030) — the patient-plane spacing.
    /// 2. Imager Pixel Spacing (0018,1164) — the *detector*-plane spacing of a
    ///    projection image; true size from it is detector size, not anatomy
    ///    (geometric magnification is real and unrecoverable here).
    /// 3. Nominal Scanned Pixel Spacing (0018,2010).
    ///
    /// Both values of the pair are required and must be positive; a file
    /// carrying one number or zeros has not said what a pixel measures.
    public static func pixelSpacing(from dataSet: DataSet) -> (row: Double, column: Double)? {
        for tag in [
            Tag(group: 0x0028, element: 0x0030),   // Pixel Spacing
            Tag(group: 0x0018, element: 0x1164),   // Imager Pixel Spacing
            Tag(group: 0x0018, element: 0x2010),   // Nominal Scanned Pixel Spacing
        ] {
            guard let text = dataSet.string(for: tag) else { continue }
            // DS, VM 2: "row spacing\column spacing".
            let parts = text.split(separator: "\\").map {
                Double($0.trimmingCharacters(in: .whitespaces))
            }
            guard parts.count >= 2,
                  let row = parts[0], let column = parts[1],
                  row > 0, column > 0 else { continue }
            return (row: row, column: column)
        }
        return nil
    }

    /// The printed width in millimetres of `columns` pixels at 1:1, or `nil`
    /// when the file does not record its spacing — in which case true size is
    /// undefined and the caller must fall back *audibly*, never silently.
    public static func trueWidthMillimeters(columns: Int, dataSet: DataSet) -> Double? {
        guard columns > 0, let spacing = pixelSpacing(from: dataSet) else { return nil }
        return Double(columns) * spacing.column
    }
}
