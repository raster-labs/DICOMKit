// HangingProtocolService.swift
// DICOMStudio
//
// DICOM Studio — Service for managing hanging protocols
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (protocol storage, selection and active-protocol state over HangingProtocolHelpers)

import Foundation

/// Service for managing hanging protocols, including matching,
/// persistence, and user-defined protocol editing.
public final class HangingProtocolService: Sendable {

    public init() {}

    // MARK: - Protocol Matching

    /// Selects the best matching hanging protocol for a study.
    ///
    /// Checks user-defined protocols first, then built-in protocols.
    ///
    /// - Parameters:
    ///   - userProtocols: User-defined protocols.
    ///   - modality: Study modality.
    ///   - bodyPart: Body part examined.
    ///   - studyDescription: Study description.
    /// - Returns: Best matching protocol, or nil.
    public func selectProtocol(
        userProtocols: [HangingProtocolModel],
        modality: String?,
        bodyPart: String? = nil,
        studyDescription: String? = nil
    ) -> HangingProtocolModel? {
        // Try user-defined protocols first
        let allProtocols = userProtocols + HangingProtocolHelpers.builtInProtocols

        return HangingProtocolHelpers.selectBestProtocol(
            from: allProtocols,
            modality: modality,
            bodyPart: bodyPart,
            procedureCode: nil,
            studyDescription: studyDescription,
            seriesDescription: nil
        )
    }

    /// Returns all available protocols (user + built-in).
    ///
    /// - Parameter userProtocols: User-defined protocols.
    /// - Returns: All protocols sorted by priority.
    public func allProtocols(userProtocols: [HangingProtocolModel]) -> [HangingProtocolModel] {
        let all = userProtocols + HangingProtocolHelpers.builtInProtocols
        return all.sorted { $0.priority > $1.priority }
    }

    /// Filters protocols that match a given modality.
    ///
    /// - Parameters:
    ///   - protocols: Available protocols.
    ///   - modality: Modality to filter by.
    /// - Returns: Matching protocols.
    public func protocols(
        from protocols: [HangingProtocolModel],
        forModality modality: String
    ) -> [HangingProtocolModel] {
        protocols.filter { proto in
            guard let criteriaModality = proto.matchingCriteria.modality else { return false }
            return criteriaModality.caseInsensitiveCompare(modality) == .orderedSame
        }
    }

    // MARK: - Protocol Editing

    /// Creates a new user-defined hanging protocol.
    ///
    /// - Parameters:
    ///   - name: Protocol name.
    ///   - layoutType: Layout type.
    ///   - modality: Target modality.
    ///   - description: Protocol description.
    /// - Returns: A new hanging protocol model.
    public func createUserProtocol(
        name: String,
        layoutType: LayoutType,
        modality: String,
        description: String? = nil
    ) -> HangingProtocolModel {
        let cellCount = layoutType.cellCount

        let viewports = (0..<cellCount).map { index in
            ViewportDefinition(
                position: index,
                selectionCriteria: ImageSelectionCriteria(modality: modality),
                isInitialActive: index == 0
            )
        }

        return HangingProtocolModel(
            name: name,
            protocolDescription: description,
            layoutType: layoutType,
            matchingCriteria: ProtocolMatchingCriteria(modality: modality),
            priority: 100, // User protocols get high priority
            viewportDefinitions: viewports,
            isUserDefined: true,
            creationDate: Date()
        )
    }

    // MARK: - Viewport Assignment

    /// Assigns series to viewports based on selection criteria.
    ///
    /// - Parameters:
    ///   - hangingProtocol: The hanging protocol.
    ///   - availableSeries: Available series from the study.
    /// - Returns: Array of (viewportPosition, matchedSeries) tuples.
    public func assignSeries(
        hangingProtocol: HangingProtocolModel,
        availableSeries: [SeriesModel]
    ) -> [(position: Int, series: SeriesModel?)] {
        hangingProtocol.viewportDefinitions.map { definition in
            let matched = HangingProtocolHelpers.matchingSeries(
                from: availableSeries,
                criteria: definition.selectionCriteria
            )
            return (definition.position, matched.first)
        }
    }
}
