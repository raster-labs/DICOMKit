// CalibrationHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent calibration helpers for pixel-to-physical conversion
// NEMA-verified: 2026a, checked 2026-10-05 — the 4 attributes diffed against PS3.6 2026a Table 6-1 (Pixel Spacing (0028,0030), Imager Pixel Spacing (0018,1164), Nominal Scanned Pixel Spacing (0018,2010), Estimated Radiographic Magnification Factor (0018,1114): 4/4); value order row\column and mm per PS3.3 2026a 10.7.1.3 and C.7.6.2.1.1; the precedence Pixel Spacing (calibrated, in the patient) over Imager Pixel Spacing (at the detector) follows 10.7.1.1 / 10.7.1.3; citations corrected to the 2026a section titles (10.7.1.1 "Pixel Spacing", 10.7.1.3 "Pixel Spacing Value Order and Valid Values")

import Foundation

/// Platform-independent helpers for pixel-to-physical space calibration.
///
/// Extracts and manages pixel spacing from DICOM headers and supports
/// manual calibration. Reference: DICOM PS3.3 C.7.6.2 (Image Plane Module), C.7.6.3 (Image Pixel Module),
/// 10.7.1.1 (Pixel Spacing), 10.7.1.3 (Pixel Spacing Value Order and Valid Values).
public enum CalibrationHelpers: Sendable {

    // MARK: - DICOM Tag Extraction

    /// Parses a Pixel Spacing (0028,0030) string into row and column spacing.
    ///
    /// The format is "row_spacing\\column_spacing" in mm.
    ///
    /// - Parameter pixelSpacingString: The DICOM Pixel Spacing value.
    /// - Returns: Tuple of (row, column) spacing in mm, or nil if invalid.
    public static func parsePixelSpacing(_ pixelSpacingString: String) -> (row: Double, column: Double)? {
        let components = pixelSpacingString.split(separator: "\\")
        guard components.count == 2,
              let row = Double(components[0].trimmingCharacters(in: .whitespaces)),
              let col = Double(components[1].trimmingCharacters(in: .whitespaces)),
              row > 0, col > 0 else {
            return nil
        }
        return (row, col)
    }

    /// Creates a calibration model from a Pixel Spacing string (0028,0030).
    ///
    /// - Parameter pixelSpacingString: DICOM Pixel Spacing value.
    /// - Returns: CalibrationModel, or uncalibrated if invalid.
    public static func calibrationFromPixelSpacing(_ pixelSpacingString: String) -> CalibrationModel {
        guard let spacing = parsePixelSpacing(pixelSpacingString) else {
            return .uncalibrated
        }
        return CalibrationModel(
            pixelSpacingRow: spacing.row,
            pixelSpacingColumn: spacing.column,
            source: .pixelSpacing
        )
    }

    /// Creates a calibration model from an Imager Pixel Spacing string (0018,1164).
    ///
    /// - Parameter imagerPixelSpacingString: DICOM Imager Pixel Spacing value.
    /// - Returns: CalibrationModel, or uncalibrated if invalid.
    public static func calibrationFromImagerPixelSpacing(_ imagerPixelSpacingString: String) -> CalibrationModel {
        guard let spacing = parsePixelSpacing(imagerPixelSpacingString) else {
            return .uncalibrated
        }
        return CalibrationModel(
            pixelSpacingRow: spacing.row,
            pixelSpacingColumn: spacing.column,
            source: .imagerPixelSpacing
        )
    }

    /// Creates a calibration model from a Nominal Scanned Pixel Spacing string (0018,2010).
    ///
    /// - Parameter nominalSpacingString: DICOM Nominal Scanned Pixel Spacing value.
    /// - Returns: CalibrationModel, or uncalibrated if invalid.
    public static func calibrationFromNominalScannedPixelSpacing(_ nominalSpacingString: String) -> CalibrationModel {
        guard let spacing = parsePixelSpacing(nominalSpacingString) else {
            return .uncalibrated
        }
        return CalibrationModel(
            pixelSpacingRow: spacing.row,
            pixelSpacingColumn: spacing.column,
            source: .nominalScannedPixelSpacing
        )
    }

    // MARK: - Manual Calibration

    /// Creates a manual calibration from a known distance.
    ///
    /// - Parameters:
    ///   - pixelDistance: Distance in pixels between two known points.
    ///   - knownDistanceMM: Known physical distance in mm.
    /// - Returns: CalibrationModel with isotropic pixel spacing, or uncalibrated if invalid.
    public static func calibrationFromManual(
        pixelDistance: Double,
        knownDistanceMM: Double
    ) -> CalibrationModel {
        guard pixelDistance > 0, knownDistanceMM > 0 else {
            return .uncalibrated
        }
        let spacing = knownDistanceMM / pixelDistance
        return CalibrationModel(
            pixelSpacingRow: spacing,
            pixelSpacingColumn: spacing,
            source: .manual
        )
    }

    // MARK: - Calibration Priority

    /// Resolves the best calibration from available DICOM tags.
    ///
    /// Priority order: Pixel Spacing > Imager Pixel Spacing > Nominal Scanned.
    ///
    /// - Parameters:
    ///   - pixelSpacing: Pixel Spacing (0028,0030) string, if available.
    ///   - imagerPixelSpacing: Imager Pixel Spacing (0018,1164) string, if available.
    ///   - nominalScannedPixelSpacing: Nominal Scanned Pixel Spacing (0018,2010), if available.
    /// - Returns: Best available CalibrationModel.
    public static func resolveCalibration(
        pixelSpacing: String?,
        imagerPixelSpacing: String?,
        nominalScannedPixelSpacing: String?
    ) -> CalibrationModel {
        if let ps = pixelSpacing {
            let cal = calibrationFromPixelSpacing(ps)
            if cal.isCalibrated { return cal }
        }
        if let ips = imagerPixelSpacing {
            let cal = calibrationFromImagerPixelSpacing(ips)
            if cal.isCalibrated { return cal }
        }
        if let nps = nominalScannedPixelSpacing {
            let cal = calibrationFromNominalScannedPixelSpacing(nps)
            if cal.isCalibrated { return cal }
        }
        return .uncalibrated
    }

    // MARK: - Magnification Correction

    /// Applies magnification correction from the Estimated Radiographic
    /// Magnification Factor (0018,1114).
    ///
    /// - Parameters:
    ///   - calibration: Base calibration model.
    ///   - magnificationFactor: Magnification factor (>1.0 means magnified).
    /// - Returns: Corrected CalibrationModel.
    public static func applyMagnificationCorrection(
        calibration: CalibrationModel,
        magnificationFactor: Double
    ) -> CalibrationModel {
        guard magnificationFactor > 0, calibration.isCalibrated else {
            return calibration
        }
        return CalibrationModel(
            pixelSpacingRow: calibration.pixelSpacingRow / magnificationFactor,
            pixelSpacingColumn: calibration.pixelSpacingColumn / magnificationFactor,
            source: calibration.source
        )
    }

    // MARK: - Display Helpers

    /// Formats calibration information for display.
    ///
    /// - Parameter calibration: The calibration model.
    /// - Returns: Human-readable calibration description.
    public static func formatCalibration(_ calibration: CalibrationModel) -> String {
        guard calibration.isCalibrated else {
            return "Uncalibrated"
        }
        let source = calibrationSourceLabel(calibration.source)
        if calibration.pixelSpacingRow == calibration.pixelSpacingColumn {
            return String(format: "%.4f mm/px (%@)", calibration.pixelSpacingRow, source)
        }
        return String(format: "%.4f × %.4f mm/px (%@)",
                       calibration.pixelSpacingRow,
                       calibration.pixelSpacingColumn,
                       source)
    }

    /// Returns a human-readable label for a calibration source.
    ///
    /// - Parameter source: The calibration source.
    /// - Returns: Display label.
    public static func calibrationSourceLabel(_ source: CalibrationSource) -> String {
        switch source {
        case .pixelSpacing: return "Pixel Spacing"
        case .imagerPixelSpacing: return "Imager Pixel Spacing"
        case .nominalScannedPixelSpacing: return "Nominal Scanned"
        case .manual: return "Manual"
        case .unknown: return "Unknown"
        }
    }

    /// Returns the calibration indicator text for overlay display.
    ///
    /// - Parameter calibration: The calibration model.
    /// - Returns: Short indicator string.
    public static func calibrationIndicator(_ calibration: CalibrationModel) -> String {
        guard calibration.isCalibrated else { return "⚠️ Uncalibrated" }
        switch calibration.source {
        case .pixelSpacing: return "✓ Calibrated (PS)"
        case .imagerPixelSpacing: return "✓ Calibrated (IPS)"
        case .nominalScannedPixelSpacing: return "✓ Calibrated (NPS)"
        case .manual: return "✓ Manual Calibration"
        case .unknown: return "⚠️ Unknown"
        }
    }
}
