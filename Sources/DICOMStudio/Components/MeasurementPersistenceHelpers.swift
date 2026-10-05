// MeasurementPersistenceHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent measurement persistence helpers
// NEMA-verified: 2026a, checked 2026-10-05 — the 8 SR concepts diffed by script against PS3.16 2026a Table D-1 and the CID tables: (125007, DCM, "Measurement Group") TID 1501 row 1; Length / Area / Mean / Standard Deviation / Minimum / Maximum match CID 7470 / 7471 / 7464 / 3488; (364499001, SCT, "Angle") is in no CID table (external SNOMED CT id, not verifiable from NEMA text; CID 7469 has no angle concept); UCUM codes mm, mm2, deg match CID 7460, CID 7461, CID 7183; CSV/JSON layout is the app's own

import Foundation

/// Platform-independent helpers for measurement serialization and persistence.
///
/// Supports exporting measurements to CSV and JSON, and defines DICOM SR concepts
/// per PS3.16 TID 1500 (Measurement Report).
public enum MeasurementPersistenceHelpers: Sendable {

    // MARK: - DICOM SR Concept Names (CID 7470, TID 1500)

    /// DICOM SR concept for a measurement group.
    public static let measurementGroupConcept = SRConcept(
        codeValue: "125007",
        codingSchemeDesignator: "DCM",
        codeMeaning: "Measurement Group"
    )

    /// DICOM SR concept for length.
    public static let lengthConcept = SRConcept(
        codeValue: "410668003",
        codingSchemeDesignator: "SCT",
        codeMeaning: "Length"
    )

    /// DICOM SR concept for angle.
    public static let angleConcept = SRConcept(
        codeValue: "364499001",
        codingSchemeDesignator: "SCT",
        codeMeaning: "Angle"
    )

    /// DICOM SR concept for area.
    public static let areaConcept = SRConcept(
        codeValue: "42798000",
        codingSchemeDesignator: "SCT",
        codeMeaning: "Area"
    )

    /// DICOM SR concept for mean value.
    public static let meanConcept = SRConcept(
        codeValue: "373098007",
        codingSchemeDesignator: "SCT",
        codeMeaning: "Mean"
    )

    /// DICOM SR concept for standard deviation.
    public static let stdDevConcept = SRConcept(
        codeValue: "386136009",
        codingSchemeDesignator: "SCT",
        codeMeaning: "Standard Deviation"
    )

    /// DICOM SR concept for minimum value.
    public static let minimumConcept = SRConcept(
        codeValue: "255605001",
        codingSchemeDesignator: "SCT",
        codeMeaning: "Minimum"
    )

    /// DICOM SR concept for maximum value.
    public static let maximumConcept = SRConcept(
        codeValue: "56851009",
        codingSchemeDesignator: "SCT",
        codeMeaning: "Maximum"
    )

    /// UCUM unit code for millimeters.
    public static let ucumMM = "mm"

    /// UCUM unit code for millimeters squared.
    public static let ucumMM2 = "mm2"

    /// UCUM unit code for degrees.
    public static let ucumDegrees = "deg"

    // MARK: - JSON Export

    /// Exports measurements to a JSON-compatible dictionary array.
    ///
    /// - Parameters:
    ///   - measurements: Array of measurement entries.
    ///   - calibration: Optional calibration for physical values.
    /// - Returns: Array of dictionaries.
    public static func measurementsToJSON(
        _ measurements: [MeasurementEntry],
        calibration: CalibrationModel = .uncalibrated
    ) -> [[String: String]] {
        measurements.map { entry in
            measurementToDict(entry, calibration: calibration)
        }
    }

    /// Converts a single measurement entry to a dictionary.
    ///
    /// - Parameters:
    ///   - entry: The measurement entry.
    ///   - calibration: Calibration model.
    /// - Returns: String-keyed dictionary.
    public static func measurementToDict(
        _ entry: MeasurementEntry,
        calibration: CalibrationModel = .uncalibrated
    ) -> [String: String] {
        var dict: [String: String] = [
            "id": entry.id.uuidString,
            "type": entry.toolType.rawValue,
            "label": entry.label,
            "sopInstanceUID": entry.sopInstanceUID,
            "frameNumber": "\(entry.frameNumber)",
            "pointCount": "\(entry.points.count)",
        ]

        // Add point coordinates
        for (i, pt) in entry.points.enumerated() {
            dict["point\(i)_x"] = String(format: "%.4f", pt.x)
            dict["point\(i)_y"] = String(format: "%.4f", pt.y)
        }

        // Add computed values based on type
        switch entry.toolType {
        case .length:
            if entry.points.count == 2 {
                let result = MeasurementHelpers.measureLength(
                    from: entry.points[0], to: entry.points[1],
                    calibration: calibration
                )
                dict["lengthPixels"] = String(format: "%.4f", result.lengthPixels)
                if let mm = result.lengthMM {
                    dict["lengthMM"] = String(format: "%.4f", mm)
                }
            }
        case .angle:
            if entry.points.count == 3 {
                if let result = MeasurementHelpers.measureAngle(
                    vertex: entry.points[1],
                    point1: entry.points[0],
                    point2: entry.points[2]
                ) {
                    dict["angleDegrees"] = String(format: "%.4f", result.angleDegrees)
                }
            }
        case .cobbAngle:
            if entry.points.count == 4 {
                if let result = MeasurementHelpers.measureCobbAngle(
                    line1Start: entry.points[0], line1End: entry.points[1],
                    line2Start: entry.points[2], line2End: entry.points[3]
                ) {
                    dict["cobbAngleDegrees"] = String(format: "%.4f", result.angleDegrees)
                }
            }
        default:
            break
        }

        return dict
    }

    // MARK: - CSV Export

    /// CSV header row for measurement export.
    public static let csvHeader = "ID,Type,Label,SOPInstanceUID,Frame,PointCount,Point0_X,Point0_Y,Point1_X,Point1_Y,LengthPx,LengthMM,AngleDeg"

    /// Exports measurements to CSV rows.
    ///
    /// - Parameters:
    ///   - measurements: Array of measurement entries.
    ///   - calibration: Calibration model.
    /// - Returns: CSV string including header.
    public static func measurementsToCSV(
        _ measurements: [MeasurementEntry],
        calibration: CalibrationModel = .uncalibrated
    ) -> String {
        var lines = [csvHeader]
        for entry in measurements {
            lines.append(measurementToCSVRow(entry, calibration: calibration))
        }
        return lines.joined(separator: "\n")
    }

    /// Converts a single measurement to a CSV row.
    ///
    /// - Parameters:
    ///   - entry: The measurement entry.
    ///   - calibration: Calibration model.
    /// - Returns: CSV row string.
    public static func measurementToCSVRow(
        _ entry: MeasurementEntry,
        calibration: CalibrationModel = .uncalibrated
    ) -> String {
        let p0x = entry.points.count > 0 ? String(format: "%.4f", entry.points[0].x) : ""
        let p0y = entry.points.count > 0 ? String(format: "%.4f", entry.points[0].y) : ""
        let p1x = entry.points.count > 1 ? String(format: "%.4f", entry.points[1].x) : ""
        let p1y = entry.points.count > 1 ? String(format: "%.4f", entry.points[1].y) : ""

        var lengthPx = ""
        var lengthMM = ""
        var angleDeg = ""

        switch entry.toolType {
        case .length:
            if entry.points.count == 2 {
                let result = MeasurementHelpers.measureLength(
                    from: entry.points[0], to: entry.points[1],
                    calibration: calibration
                )
                lengthPx = String(format: "%.4f", result.lengthPixels)
                if let mm = result.lengthMM {
                    lengthMM = String(format: "%.4f", mm)
                }
            }
        case .angle:
            if entry.points.count == 3 {
                if let result = MeasurementHelpers.measureAngle(
                    vertex: entry.points[1],
                    point1: entry.points[0],
                    point2: entry.points[2]
                ) {
                    angleDeg = String(format: "%.4f", result.angleDegrees)
                }
            }
        default:
            break
        }

        // Escape label for CSV
        let escapedLabel = entry.label.contains(",") ? "\"\(entry.label)\"" : entry.label

        return [
            entry.id.uuidString,
            entry.toolType.rawValue,
            escapedLabel,
            entry.sopInstanceUID,
            "\(entry.frameNumber)",
            "\(entry.points.count)",
            p0x, p0y, p1x, p1y,
            lengthPx, lengthMM, angleDeg
        ].joined(separator: ",")
    }

    // MARK: - SR Concept Model

    /// Returns the appropriate SR concept for a measurement tool type.
    ///
    /// - Parameter toolType: Measurement tool type.
    /// - Returns: SRConcept for the measurement.
    public static func srConcept(for toolType: MeasurementToolType) -> SRConcept {
        switch toolType {
        case .length, .bidirectional:
            return lengthConcept
        case .angle, .cobbAngle:
            return angleConcept
        case .ellipticalROI, .rectangularROI, .freehandROI, .polygonalROI, .circularROI:
            return areaConcept
        case .textAnnotation, .arrowAnnotation, .marker:
            return measurementGroupConcept
        }
    }

    /// Returns the UCUM unit code for a measurement tool type.
    ///
    /// - Parameter toolType: Measurement tool type.
    /// - Returns: UCUM unit code string.
    public static func ucumUnit(for toolType: MeasurementToolType) -> String {
        switch toolType {
        case .length, .bidirectional:
            return ucumMM
        case .angle, .cobbAngle:
            return ucumDegrees
        case .ellipticalROI, .rectangularROI, .freehandROI, .polygonalROI, .circularROI:
            return ucumMM2
        case .textAnnotation, .arrowAnnotation, .marker:
            return ""
        }
    }
}

// MARK: - SR Concept

/// A DICOM Structured Report coded concept.
public struct SRConcept: Sendable, Equatable, Hashable {
    /// Code value.
    public let codeValue: String

    /// Coding scheme designator (e.g., "SCT", "DCM", "LN").
    public let codingSchemeDesignator: String

    /// Code meaning (human-readable).
    public let codeMeaning: String

    /// Creates a new SR concept.
    public init(codeValue: String, codingSchemeDesignator: String, codeMeaning: String) {
        self.codeValue = codeValue
        self.codingSchemeDesignator = codingSchemeDesignator
        self.codeMeaning = codeMeaning
    }
}
