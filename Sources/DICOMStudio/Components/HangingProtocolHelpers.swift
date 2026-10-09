// HangingProtocolHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent hanging protocol matching helpers
// NEMA-verified: 2026a, checked 2026-10-05 — the 4 Modality values of the built-in protocols (CT, MR, PT, CR) are PS3.3 2026a Table C.7-3 Defined Terms (4/4); match scoring, series filtering and layout labels are the app's own logic (not the C.23.3 Hanging Protocol Display Module selection semantics)

import Foundation

/// Platform-independent helpers for hanging protocol matching and layout.
///
/// Implements the app's protocol matching logic, priority selection, and layout
/// calculations (a simplification of DICOM PS3.3 C.23).
public enum HangingProtocolHelpers: Sendable {

    // MARK: - Protocol Matching

    /// Computes a match score for a hanging protocol against study/series metadata.
    ///
    /// Higher scores indicate better matches. Each matched criterion adds points.
    ///
    /// - Parameters:
    ///   - criteria: The protocol's matching criteria.
    ///   - modality: Study/series modality.
    ///   - bodyPart: Body part examined.
    ///   - procedureCode: Procedure code.
    ///   - studyDescription: Study description.
    ///   - seriesDescription: Series description.
    /// - Returns: Match score (0 = no match, higher = better match).
    public static func matchScore(
        criteria: ProtocolMatchingCriteria,
        modality: String?,
        bodyPart: String?,
        procedureCode: String?,
        studyDescription: String?,
        seriesDescription: String?
    ) -> Int {
        var score = 0

        if let criteriaModality = criteria.modality {
            if let studyModality = modality,
               criteriaModality.caseInsensitiveCompare(studyModality) == .orderedSame {
                score += 10
            } else {
                return 0 // Modality mismatch is a hard fail
            }
        }

        if let criteriaBodyPart = criteria.bodyPartExamined {
            if let studyBodyPart = bodyPart,
               criteriaBodyPart.caseInsensitiveCompare(studyBodyPart) == .orderedSame {
                score += 5
            }
        }

        if let criteriaProcedure = criteria.procedureCode {
            if let studyProcedure = procedureCode,
               criteriaProcedure.caseInsensitiveCompare(studyProcedure) == .orderedSame {
                score += 5
            }
        }

        if let criteriaStudyDesc = criteria.studyDescriptionPattern {
            if let desc = studyDescription,
               desc.localizedCaseInsensitiveContains(criteriaStudyDesc) {
                score += 3
            }
        }

        if let criteriaSeriesDesc = criteria.seriesDescriptionPattern {
            if let desc = seriesDescription,
               desc.localizedCaseInsensitiveContains(criteriaSeriesDesc) {
                score += 3
            }
        }

        return score
    }

    /// Selects the best matching hanging protocol from a list.
    ///
    /// Uses match score first, then priority as a tiebreaker.
    ///
    /// - Parameters:
    ///   - protocols: Available hanging protocols.
    ///   - modality: Study modality.
    ///   - bodyPart: Body part examined.
    ///   - procedureCode: Procedure code.
    ///   - studyDescription: Study description.
    ///   - seriesDescription: Series description.
    /// - Returns: Best matching protocol, or nil if none match.
    public static func selectBestProtocol(
        from protocols: [HangingProtocolModel],
        modality: String?,
        bodyPart: String?,
        procedureCode: String?,
        studyDescription: String?,
        seriesDescription: String?
    ) -> HangingProtocolModel? {
        var bestMatch: HangingProtocolModel?
        var bestScore = 0
        var bestPriority = Int.min

        for proto in protocols {
            let score = matchScore(
                criteria: proto.matchingCriteria,
                modality: modality,
                bodyPart: bodyPart,
                procedureCode: procedureCode,
                studyDescription: studyDescription,
                seriesDescription: seriesDescription
            )

            if score > bestScore || (score == bestScore && proto.priority > bestPriority) {
                bestMatch = proto
                bestScore = score
                bestPriority = proto.priority
            }
        }

        return bestScore > 0 ? bestMatch : nil
    }

    // MARK: - Series Selection

    /// Filters series that match viewport selection criteria.
    ///
    /// - Parameters:
    ///   - series: Available series.
    ///   - criteria: Selection criteria.
    /// - Returns: Matching series, sorted per criteria.
    public static func matchingSeries(
        from series: [SeriesModel],
        criteria: ImageSelectionCriteria
    ) -> [SeriesModel] {
        var results = series

        if let modality = criteria.modality {
            results = results.filter {
                $0.modality.caseInsensitiveCompare(modality) == .orderedSame
            }
        }

        if let desc = criteria.seriesDescription {
            results = results.filter {
                $0.seriesDescription?.localizedCaseInsensitiveContains(desc) ?? false
            }
        }

        if let bodyPart = criteria.bodyPartExamined {
            results = results.filter {
                $0.bodyPartExamined?.caseInsensitiveCompare(bodyPart) == .orderedSame
            }
        }

        if let seriesNum = criteria.seriesNumber {
            results = results.filter {
                $0.seriesNumber == seriesNum
            }
        }

        // Sort
        results.sort { a, b in
            let aNum = a.seriesNumber ?? 0
            let bNum = b.seriesNumber ?? 0
            return criteria.sortDirection == ImageSortDirection.ascending ? aNum < bNum : aNum > bNum
        }

        return results
    }

    // MARK: - Layout Display

    /// Returns a display label for a layout type.
    ///
    /// - Parameter layout: Layout type.
    /// - Returns: Human-readable label.
    public static func layoutLabel(for layout: LayoutType) -> String {
        switch layout {
        case .single: return "Single"
        case .twoByOne: return "2×1"
        case .oneByTwo: return "1×2"
        case .twoByTwo: return "2×2"
        case .threeByTwo: return "3×2"
        case .threeByThree: return "3×3"
        case .custom: return "Custom"
        }
    }

    /// Returns an SF Symbol name for a layout type.
    ///
    /// - Parameter layout: Layout type.
    /// - Returns: SF Symbol name.
    public static func layoutSystemImage(for layout: LayoutType) -> String {
        switch layout {
        case .single: return "square"
        case .twoByOne: return "rectangle.split.2x1"
        case .oneByTwo: return "rectangle.split.1x2"
        case .twoByTwo: return "rectangle.split.2x2"
        case .threeByTwo: return "rectangle.split.3x3"
        case .threeByThree: return "rectangle.split.3x3"
        case .custom: return "rectangle.3.group"
        }
    }

    // MARK: - Built-in Protocols

    /// Returns the built-in (system-defined) hanging protocols.
    ///
    /// These cover common radiology workflows.
    public static let builtInProtocols: [HangingProtocolModel] = [
        HangingProtocolModel(
            name: "CT Standard",
            protocolDescription: "Standard CT viewing with single viewport",
            layoutType: .single,
            matchingCriteria: ProtocolMatchingCriteria(modality: "CT"),
            priority: 1,
            viewportDefinitions: [
                ViewportDefinition(position: 0, selectionCriteria: ImageSelectionCriteria(modality: "CT"), isInitialActive: true)
            ]
        ),
        HangingProtocolModel(
            name: "CT Comparison",
            protocolDescription: "CT comparison with prior study",
            layoutType: .twoByOne,
            matchingCriteria: ProtocolMatchingCriteria(modality: "CT"),
            priority: 0,
            viewportDefinitions: [
                ViewportDefinition(position: 0, selectionCriteria: ImageSelectionCriteria(modality: "CT"), isInitialActive: true),
                ViewportDefinition(position: 1, selectionCriteria: ImageSelectionCriteria(modality: "CT"))
            ]
        ),
        HangingProtocolModel(
            name: "MR Standard",
            protocolDescription: "Standard MR viewing with single viewport",
            layoutType: .single,
            matchingCriteria: ProtocolMatchingCriteria(modality: "MR"),
            priority: 1,
            viewportDefinitions: [
                ViewportDefinition(position: 0, selectionCriteria: ImageSelectionCriteria(modality: "MR"), isInitialActive: true)
            ]
        ),
        HangingProtocolModel(
            name: "MR Multi-Series",
            protocolDescription: "MR viewing with 2×2 layout for multiple sequences",
            layoutType: .twoByTwo,
            matchingCriteria: ProtocolMatchingCriteria(modality: "MR"),
            priority: 0,
            viewportDefinitions: [
                ViewportDefinition(position: 0, selectionCriteria: ImageSelectionCriteria(modality: "MR", seriesDescription: "T1"), isInitialActive: true),
                ViewportDefinition(position: 1, selectionCriteria: ImageSelectionCriteria(modality: "MR", seriesDescription: "T2")),
                ViewportDefinition(position: 2, selectionCriteria: ImageSelectionCriteria(modality: "MR", seriesDescription: "FLAIR")),
                ViewportDefinition(position: 3, selectionCriteria: ImageSelectionCriteria(modality: "MR", seriesDescription: "DWI"))
            ]
        ),
        HangingProtocolModel(
            name: "PET/CT Fusion",
            protocolDescription: "PET/CT fusion display",
            layoutType: .twoByOne,
            matchingCriteria: ProtocolMatchingCriteria(modality: "PT"),
            priority: 2,
            viewportDefinitions: [
                ViewportDefinition(position: 0, selectionCriteria: ImageSelectionCriteria(modality: "CT"), isInitialActive: true),
                ViewportDefinition(position: 1, selectionCriteria: ImageSelectionCriteria(modality: "PT"))
            ]
        ),
        HangingProtocolModel(
            name: "CR/DX Standard",
            protocolDescription: "Standard X-ray viewing",
            layoutType: .single,
            matchingCriteria: ProtocolMatchingCriteria(modality: "CR"),
            priority: 1,
            viewportDefinitions: [
                ViewportDefinition(position: 0, selectionCriteria: ImageSelectionCriteria(modality: "CR"), isInitialActive: true)
            ]
        ),
    ]
}
