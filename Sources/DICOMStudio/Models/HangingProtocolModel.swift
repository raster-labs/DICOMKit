// HangingProtocolModel.swift
// DICOMStudio
//
// DICOM Studio — Hanging Protocol models, loosely modelled on DICOM PS3.3 C.23
// NEMA-verified: 2026a, checked 2026-10-05 — the only standard-shaped enum, ImageSortDirection (ASCENDING / DESCENDING), diffed against PS3.3 2026a Sorting Direction (0072,0604) Enumerated Values INCREASING / DECREASING (Table C.23.3-1): 0 match — P-STUDIO-HP-SORTING-DIRECTION; LayoutType, ImageSortField, the matching criteria, priority and viewport definitions are the app's own model and do not encode Hanging Protocol Definition / Display Module attributes (Tables C.23.1-1, C.23.3-1); the HangingProtocolModel doc comment no longer claims correspondence with the C.23 modules

import Foundation

/// Viewport layout configuration type.
public enum LayoutType: String, Sendable, Equatable, Hashable, CaseIterable {
    case single = "1x1"
    case twoByOne = "2x1"
    case oneByTwo = "1x2"
    case twoByTwo = "2x2"
    case threeByTwo = "3x2"
    case threeByThree = "3x3"
    case custom = "CUSTOM"

    /// Number of columns in this layout.
    public var columns: Int {
        switch self {
        case .single, .oneByTwo: return 1
        case .twoByOne, .twoByTwo: return 2
        case .threeByTwo, .threeByThree: return 3
        case .custom: return 1
        }
    }

    /// Number of rows in this layout.
    public var rows: Int {
        switch self {
        case .single, .twoByOne, .threeByTwo: return 1
        case .oneByTwo, .twoByTwo: return 2
        case .threeByThree: return 3
        case .custom: return 1
        }
    }

    /// Total number of viewport cells.
    public var cellCount: Int {
        columns * rows
    }
}

/// Sorting direction for images within viewports.
///
/// PS3.3 2026a Sorting Direction (0072,0604) enumerates INCREASING and DECREASING (Table C.23.3-1);
/// these raw values are the app's own and are kept for stored-state compatibility (P-STUDIO-HP-SORTING-DIRECTION).
public enum ImageSortDirection: String, Sendable, Equatable, Hashable, CaseIterable {
    case ascending = "ASCENDING"
    case descending = "DESCENDING"
}

/// Sorting criteria for images within a viewport.
public enum ImageSortField: String, Sendable, Equatable, Hashable, CaseIterable {
    case instanceNumber = "INSTANCE_NUMBER"
    case imagePosition = "IMAGE_POSITION"
    case acquisitionTime = "ACQUISITION_TIME"
    case contentTime = "CONTENT_TIME"
}

/// Image selection criteria for a viewport.
public struct ImageSelectionCriteria: Sendable, Equatable, Hashable {
    /// Modality filter (e.g., "CT", "MR", "PT").
    public let modality: String?

    /// Series description filter (substring match).
    public let seriesDescription: String?

    /// Body part examined filter.
    public let bodyPartExamined: String?

    /// Series number filter.
    public let seriesNumber: Int?

    /// Image sort field.
    public let sortField: ImageSortField

    /// Image sort direction.
    public let sortDirection: ImageSortDirection

    /// Creates new image selection criteria.
    public init(
        modality: String? = nil,
        seriesDescription: String? = nil,
        bodyPartExamined: String? = nil,
        seriesNumber: Int? = nil,
        sortField: ImageSortField = .instanceNumber,
        sortDirection: ImageSortDirection = .ascending
    ) {
        self.modality = modality
        self.seriesDescription = seriesDescription
        self.bodyPartExamined = bodyPartExamined
        self.seriesNumber = seriesNumber
        self.sortField = sortField
        self.sortDirection = sortDirection
    }

    /// Whether any filter is set.
    public var hasFilters: Bool {
        modality != nil || seriesDescription != nil || bodyPartExamined != nil || seriesNumber != nil
    }
}

/// Matching criteria for a hanging protocol.
public struct ProtocolMatchingCriteria: Sendable, Equatable, Hashable {
    /// Modality match (e.g., "CT").
    public let modality: String?

    /// Body part examined match.
    public let bodyPartExamined: String?

    /// Procedure code match.
    public let procedureCode: String?

    /// Study description pattern match.
    public let studyDescriptionPattern: String?

    /// Series description pattern match.
    public let seriesDescriptionPattern: String?

    /// Creates new matching criteria.
    public init(
        modality: String? = nil,
        bodyPartExamined: String? = nil,
        procedureCode: String? = nil,
        studyDescriptionPattern: String? = nil,
        seriesDescriptionPattern: String? = nil
    ) {
        self.modality = modality
        self.bodyPartExamined = bodyPartExamined
        self.procedureCode = procedureCode
        self.studyDescriptionPattern = studyDescriptionPattern
        self.seriesDescriptionPattern = seriesDescriptionPattern
    }
}

/// A viewport definition within a hanging protocol.
public struct ViewportDefinition: Identifiable, Sendable, Equatable, Hashable {
    /// Unique identifier.
    public let id: UUID

    /// Position in grid (0-based, row-major order).
    public let position: Int

    /// Image selection criteria.
    public let selectionCriteria: ImageSelectionCriteria

    /// Whether this viewport is the initial active viewport.
    public let isInitialActive: Bool

    /// Creates a new viewport definition.
    public init(
        id: UUID = UUID(),
        position: Int,
        selectionCriteria: ImageSelectionCriteria = ImageSelectionCriteria(),
        isInitialActive: Bool = false
    ) {
        self.id = id
        self.position = position
        self.selectionCriteria = selectionCriteria
        self.isInitialActive = isInitialActive
    }
}

/// A hanging protocol that defines how to display studies.
///
/// An app-level simplification of the DICOM PS3.3 C.23 Hanging Protocol modules: layout, matching
/// criteria and per-viewport selection, not the Hanging Protocol IOD's attributes.
public struct HangingProtocolModel: Identifiable, Sendable, Equatable, Hashable {
    /// Unique identifier.
    public let id: UUID

    /// Protocol name.
    public let name: String

    /// Protocol description.
    public let protocolDescription: String?

    /// Layout type for the protocol.
    public let layoutType: LayoutType

    /// Custom columns (if layoutType is .custom).
    public let customColumns: Int?

    /// Custom rows (if layoutType is .custom).
    public let customRows: Int?

    /// Matching criteria to determine when this protocol applies.
    public let matchingCriteria: ProtocolMatchingCriteria

    /// Priority level (higher = preferred when multiple protocols match).
    public let priority: Int

    /// Viewport definitions.
    public let viewportDefinitions: [ViewportDefinition]

    /// Whether this is a user-defined protocol.
    public let isUserDefined: Bool

    /// Creation date.
    public let creationDate: Date?

    /// Creates a new hanging protocol.
    public init(
        id: UUID = UUID(),
        name: String,
        protocolDescription: String? = nil,
        layoutType: LayoutType = .single,
        customColumns: Int? = nil,
        customRows: Int? = nil,
        matchingCriteria: ProtocolMatchingCriteria = ProtocolMatchingCriteria(),
        priority: Int = 0,
        viewportDefinitions: [ViewportDefinition] = [],
        isUserDefined: Bool = false,
        creationDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.protocolDescription = protocolDescription
        self.layoutType = layoutType
        self.customColumns = customColumns
        self.customRows = customRows
        self.matchingCriteria = matchingCriteria
        self.priority = priority
        self.viewportDefinitions = viewportDefinitions
        self.isUserDefined = isUserDefined
        self.creationDate = creationDate
    }

    /// Effective number of columns (handles custom layout).
    public var effectiveColumns: Int {
        if layoutType == .custom, let cols = customColumns {
            return max(1, cols)
        }
        return layoutType.columns
    }

    /// Effective number of rows (handles custom layout).
    public var effectiveRows: Int {
        if layoutType == .custom, let rows = customRows {
            return max(1, rows)
        }
        return layoutType.rows
    }

    /// Effective number of cells.
    public var effectiveCellCount: Int {
        effectiveColumns * effectiveRows
    }
}
