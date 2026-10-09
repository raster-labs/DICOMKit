// CADVisualizationHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent CAD findings visualization helpers
// Reference: DICOM PS3.3 A.35.5 (Mammography CAD SR IOD), A.35.6 (Chest CAD SR IOD), PS3.16 TID 4000 / TID 4100, TID 4015 / 4016 / 4018 (CAD Detections / Analyses Performed), TID 4019 (Algorithm Identification)
// NEMA-verified: 2026a, checked 2026-10-05 — citations checked against PS3.3 / PS3.16 2026a titles (C.17.3 is the SR Document Content Module, replaced by the CAD SR IOD and template references); carries no DICOM-standard data: colours, opacities, severity labels and the ACR BI-RADS category descriptions are display conventions, and CADFinding / CADFindingType are not coded concepts (TID 4000 / 4100 content is built elsewhere)

import Foundation

/// Platform-independent helpers for CAD (Computer-Aided Detection) findings
/// visualization, including mammography CAD and chest CAD display.
public enum CADVisualizationHelpers: Sendable {

    // MARK: - CAD Finding Display

    /// Returns a display color name for a CAD finding type.
    ///
    /// - Parameter findingType: The type of CAD finding.
    /// - Returns: A color name string for UI rendering.
    public static func colorForFindingType(_ findingType: CADFindingType) -> String {
        switch findingType {
        case .mass: return "red"
        case .calcification: return "yellow"
        case .architecturalDistortion: return "orange"
        case .nodule: return "blue"
        case .consolidation: return "purple"
        case .lesion: return "pink"
        }
    }

    /// Returns an opacity value based on confidence score.
    ///
    /// Higher confidence findings are more opaque.
    ///
    /// - Parameter confidence: Confidence score (0.0–1.0).
    /// - Returns: Opacity value (0.3–1.0).
    public static func opacityForConfidence(_ confidence: Double) -> Double {
        let clamped = min(max(confidence, 0.0), 1.0)
        return 0.3 + (clamped * 0.7)
    }

    /// Returns a severity label for a confidence score.
    ///
    /// - Parameter confidence: Confidence score (0.0–1.0).
    /// - Returns: A severity label string.
    public static func severityLabel(for confidence: Double) -> String {
        switch confidence {
        case 0.0..<0.3: return "Low"
        case 0.3..<0.6: return "Moderate"
        case 0.6..<0.8: return "High"
        case 0.8...1.0: return "Very High"
        default: return "Unknown"
        }
    }

    /// Returns the SF Symbol name for a CAD finding status.
    ///
    /// - Parameter status: The review status.
    /// - Returns: SF Symbol name.
    public static func sfSymbolForStatus(_ status: CADFindingStatus) -> String {
        switch status {
        case .pending: return "questionmark.circle"
        case .accepted: return "checkmark.circle.fill"
        case .rejected: return "xmark.circle.fill"
        }
    }

    /// Returns a color name for a CAD finding status.
    ///
    /// - Parameter status: The review status.
    /// - Returns: A color name.
    public static func colorForStatus(_ status: CADFindingStatus) -> String {
        switch status {
        case .pending: return "gray"
        case .accepted: return "green"
        case .rejected: return "red"
        }
    }

    // MARK: - BI-RADS Display

    /// Returns a color name for a BI-RADS category.
    ///
    /// - Parameter category: The BI-RADS assessment category.
    /// - Returns: A color name.
    public static func colorForBIRADS(_ category: BIRADSCategory) -> String {
        switch category {
        case .category0: return "gray"
        case .category1: return "green"
        case .category2: return "green"
        case .category3: return "yellow"
        case .category4: return "orange"
        case .category5: return "red"
        case .category6: return "red"
        }
    }

    /// Returns a short description for a BI-RADS category.
    ///
    /// - Parameter category: The BI-RADS assessment category.
    /// - Returns: A short description.
    public static func biradsDescription(_ category: BIRADSCategory) -> String {
        switch category {
        case .category0: return "Additional imaging needed"
        case .category1: return "No findings"
        case .category2: return "Definitely benign findings"
        case .category3: return "Probably benign; short follow-up suggested"
        case .category4: return "Suspicious abnormality; biopsy should be considered"
        case .category5: return "Highly suggestive of malignancy; take appropriate action"
        case .category6: return "Known biopsy-proven malignancy"
        }
    }

    // MARK: - Mammography CAD Helpers

    /// Creates mammography CAD findings from structured parameters.
    ///
    /// - Parameters:
    ///   - masses: Array of mass findings (location, confidence).
    ///   - calcifications: Array of calcification findings (location, confidence).
    ///   - distortions: Array of architectural distortion findings.
    ///   - birads: Overall BI-RADS assessment.
    /// - Returns: Array of CAD findings.
    public static func buildMammographyFindings(
        masses: [(location: String, confidence: Double)] = [],
        calcifications: [(location: String, confidence: Double)] = [],
        distortions: [(location: String, confidence: Double)] = [],
        birads: BIRADSCategory? = nil
    ) -> [CADFinding] {
        var findings: [CADFinding] = []

        for mass in masses {
            findings.append(CADFinding(
                findingType: .mass,
                confidence: mass.confidence,
                locationDescription: mass.location,
                biradsCategory: birads
            ))
        }

        for calc in calcifications {
            findings.append(CADFinding(
                findingType: .calcification,
                confidence: calc.confidence,
                locationDescription: calc.location,
                biradsCategory: birads
            ))
        }

        for distortion in distortions {
            findings.append(CADFinding(
                findingType: .architecturalDistortion,
                confidence: distortion.confidence,
                locationDescription: distortion.location,
                biradsCategory: birads
            ))
        }

        return findings
    }

    /// Creates chest CAD findings from structured parameters.
    ///
    /// - Parameters:
    ///   - nodules: Array of nodule findings (location, confidence).
    ///   - masses: Array of mass findings (location, confidence).
    ///   - consolidations: Array of consolidation findings (location, confidence).
    ///   - lesions: Array of lesion findings (location, confidence).
    /// - Returns: Array of CAD findings.
    public static func buildChestCADFindings(
        nodules: [(location: String, confidence: Double)] = [],
        masses: [(location: String, confidence: Double)] = [],
        consolidations: [(location: String, confidence: Double)] = [],
        lesions: [(location: String, confidence: Double)] = []
    ) -> [CADFinding] {
        var findings: [CADFinding] = []

        for nodule in nodules {
            findings.append(CADFinding(
                findingType: .nodule,
                confidence: nodule.confidence,
                locationDescription: nodule.location
            ))
        }

        for mass in masses {
            findings.append(CADFinding(
                findingType: .mass,
                confidence: mass.confidence,
                locationDescription: mass.location
            ))
        }

        for consolidation in consolidations {
            findings.append(CADFinding(
                findingType: .consolidation,
                confidence: consolidation.confidence,
                locationDescription: consolidation.location
            ))
        }

        for lesion in lesions {
            findings.append(CADFinding(
                findingType: .lesion,
                confidence: lesion.confidence,
                locationDescription: lesion.location
            ))
        }

        return findings
    }

    // MARK: - Filtering and Sorting

    /// Filters findings by type.
    ///
    /// - Parameters:
    ///   - findings: Array of CAD findings.
    ///   - type: The finding type to filter by.
    /// - Returns: Filtered array.
    public static func filterByType(
        _ findings: [CADFinding],
        type: CADFindingType
    ) -> [CADFinding] {
        findings.filter { $0.findingType == type }
    }

    /// Filters findings by status.
    ///
    /// - Parameters:
    ///   - findings: Array of CAD findings.
    ///   - status: The status to filter by.
    /// - Returns: Filtered array.
    public static func filterByStatus(
        _ findings: [CADFinding],
        status: CADFindingStatus
    ) -> [CADFinding] {
        findings.filter { $0.status == status }
    }

    /// Filters findings by minimum confidence.
    ///
    /// - Parameters:
    ///   - findings: Array of CAD findings.
    ///   - minConfidence: Minimum confidence threshold (0.0–1.0).
    /// - Returns: Filtered array.
    public static func filterByMinConfidence(
        _ findings: [CADFinding],
        minConfidence: Double
    ) -> [CADFinding] {
        findings.filter { $0.confidence >= minConfidence }
    }

    /// Sorts findings by confidence (descending).
    ///
    /// - Parameter findings: Array of CAD findings.
    /// - Returns: Sorted array.
    public static func sortByConfidence(_ findings: [CADFinding]) -> [CADFinding] {
        findings.sorted { $0.confidence > $1.confidence }
    }

    /// Sorts findings by type, then confidence.
    ///
    /// - Parameter findings: Array of CAD findings.
    /// - Returns: Sorted array.
    public static func sortByTypeAndConfidence(_ findings: [CADFinding]) -> [CADFinding] {
        findings.sorted { a, b in
            if a.findingType.rawValue != b.findingType.rawValue {
                return a.findingType.rawValue < b.findingType.rawValue
            }
            return a.confidence > b.confidence
        }
    }

    // MARK: - Statistics

    /// Computes summary statistics for CAD findings.
    ///
    /// - Parameter findings: Array of CAD findings.
    /// - Returns: Dictionary of statistic name to value.
    public static func findingStatistics(_ findings: [CADFinding]) -> [String: Int] {
        var stats: [String: Int] = [
            "total": findings.count,
            "pending": 0,
            "accepted": 0,
            "rejected": 0,
        ]
        for finding in findings {
            switch finding.status {
            case .pending: stats["pending", default: 0] += 1
            case .accepted: stats["accepted", default: 0] += 1
            case .rejected: stats["rejected", default: 0] += 1
            }
        }
        for findingType in CADFindingType.allCases {
            stats[findingType.rawValue.lowercased()] = findings.filter {
                $0.findingType == findingType
            }.count
        }
        return stats
    }

    /// Returns the average confidence for a set of findings.
    ///
    /// - Parameter findings: Array of CAD findings.
    /// - Returns: Average confidence (0.0 if empty).
    public static func averageConfidence(_ findings: [CADFinding]) -> Double {
        guard !findings.isEmpty else { return 0.0 }
        let sum = findings.reduce(0.0) { $0 + $1.confidence }
        return sum / Double(findings.count)
    }
}
